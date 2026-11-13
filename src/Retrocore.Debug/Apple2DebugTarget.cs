// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.Json.Nodes;
using Retrocore.Basic;
using Retrocore.Isa;
using Retrocore.Machines.Apple2;
using Retrocore.Media;
using Touki;

namespace Retrocore.Debug;

/// <summary>
///  The Apple IIe as the debugger sees it: a 6502 or 65C02, the IIe's memory areas, and its text, video, beam
///  and Disk II views.
/// </summary>
internal sealed partial class Apple2DebugTarget : DisposableBase, IDebugTarget
{
    private const byte JsrOpcode = 0x20;
    private const byte BrkOpcode = 0x00;

    private static readonly DebugRegisters s_registers = new(M6502Isa.Description);


    private readonly Apple2Machine _machine;
    private PascalRuntime? _pascal;
    private readonly Apple2Model _model;
    private readonly DebugCallStack _calls;
    private readonly byte[] _pixels = new byte[Apple2Video.Width * Apple2Video.Height * 4];

    // The sectors per track of each slot's Disk II firmware, when it was built from the SDK's sources.
    private readonly Dictionary<int, int> _diskSectors = [];
    // The beam positions scanline breakpoints stop at, as cycles within the frame, and the next one due.
    private int[] _beamBreaks = [];
    private ulong? _nextBeamCycle;

    // A CONTROL-RESET whose handler has not yet started: the 6502's reset sequence runs first.
    private bool _resetPending;
    private DebugAudioSink? _sound;
    private string _soundMode = "speaker";
    private BasicRom? _basicRom;

    // AppleSoft's page-zero flags that its stack reset (STKINI) and MAIN set: the string temporaries, subscripts
    // allowed, the direct-mode line, and ONERR off.
    private const ushort TempPointer = 0x52;
    private const byte FirstTemporary = 0x55;
    private const ushort SubscriptFlag = 0x14;
    private const ushort CurrentLineHigh = 0x76;
    private const ushort ErrorFlag = 0xD8;

    // STKINI's stack pointer, with its bottom entry, which FNDFOR must not take for a FOR, at $01FF.
    private const byte EmptyStack = 0xFE;

    // AppleSoft's text pointer, inside CHRGET; the stack pointer NEWSTT saves (REMSTK); the current line (CURLIN).
    private const ushort TextPointer = 0xB8;
    private const ushort StatementStack = 0xF8;
    private const ushort CurrentLine = 0x75;
    private const byte OnErrActive = 0x80;
    private const int ForEntrySize = 18;

    // AppleSoft's errors by the code ERROR is given in X, which is also what ONERR leaves at 222.
    private static readonly Dictionary<int, string> s_errors = new()
    {
        [0] = "NEXT WITHOUT FOR",
        [16] = "SYNTAX",
        [22] = "RETURN WITHOUT GOSUB",
        [42] = "OUT OF DATA",
        [53] = "ILLEGAL QUANTITY",
        [69] = "OVERFLOW",
        [77] = "OUT OF MEMORY",
        [90] = "UNDEF'D STATEMENT",
        [107] = "BAD SUBSCRIPT",
        [120] = "REDIM'D ARRAY",
        [133] = "DIVISION BY ZERO",
        [149] = "ILLEGAL DIRECT",
        [163] = "TYPE MISMATCH",
        [176] = "STRING TOO LONG",
        [191] = "FORMULA TOO COMPLEX",
        [210] = "CAN'T CONTINUE",
        [224] = "UNDEF'D FUNCTION"
    };

    /// <summary>
    ///  Creates the target for a launched IIe.
    /// </summary>
    /// <param name="machine">The machine.</param>
    /// <param name="model">Its model.</param>
    internal Apple2DebugTarget(Apple2Machine machine, Apple2Model model)
    {
        _machine = machine;
        _model = model;
        _calls = new(machine.Bus);
        Requests = new Dictionary<string, Func<JsonObject, JsonObject>>
        {
            ["apple2/text"] = _ => TextFrame(),
            ["retro/video"] = args => VideoFrame(args.Bool("scanned") ?? false),
            ["apple2/beam"] = _ => Beam(),
            ["apple2/disk"] = _ => DiskState(),
            ["apple2/button"] = Button,
            ["apple2/mouse"] = Mouse,
            ["apple2/sound"] = Sound,
            ["apple2/fastDisk"] = FastDiskRequest
        };
    }

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   <c>SYSTEM.APPLE</c> runs from the language card's RAM at <c>$D000-$FFFF</c>, so Pascal needs 64K. It uses both
    ///   of the card's banks at <c>$D000</c>, and is looked for in each.
    ///  </para>
    /// </remarks>
    public PascalRuntime? Pascal => _pascal ??= new PascalRuntime(
        "Apple Pascal",
        new Apple2PascalMemory(_machine.Bus),
        _machine.Bus.Peek,
        [address => LanguageCard(Apple2MemoryArea.MainLanguageCard, address), address => LanguageCard(Apple2MemoryArea.MainLanguageCardBank1, address)],
        (0xD000, 0x10000),
        extended: false,
        () => 0,
        () => _machine.Drives.Select(drive => drive.Disk).OfType<WozDisk>(),
        () => CycleCount);

    // The language card's RAM at an address, bank 1 below $E000 for that bank's area; the CPU's view elsewhere.
    private byte LanguageCard(Apple2MemoryArea area, ushort address)
    {
        Apple2Bus bus = _machine.Bus;
        if (area == Apple2MemoryArea.MainLanguageCardBank1 && address >= 0xE000)
        {
            area = Apple2MemoryArea.MainLanguageCard;
        }

        return bus.PeekArea(area, address, out byte value) ? value : bus.Peek(address);
    }

    /// <summary>
    ///  Launches a IIe from a launch request's arguments.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   The ROMs are the dumps in <c>romDirectory</c> (or <c>RETROCORE_IIE_ROMS</c>). Without dumps they are
    ///   assembled from the SDK's sources in <c>sdkRoms</c>, or beside the debug host, which are byte-identical to
    ///   them.
    ///  </para>
    /// </remarks>
    /// <param name="args">The arguments, such as <c>romDirectory</c>, <c>model</c> and <c>diskImage</c>.</param>
    /// <returns>The target, reset and past its first cycles.</returns>
    /// <exception cref="ArgumentException">An argument is missing or invalid.</exception>
    internal static Apple2DebugTarget Launch(JsonObject args)
    {
        Apple2Model model = Model(args.String("model"));

        string? sdk = args.String("sdkRoms") is { } sdkRoms ? Path.GetFullPath(sdkRoms) : null;
        string? diskImage = args.String("diskImage");
        string? dos = args.String("dos");
        if (dos is not (null or "3.3" or "3.2")) { throw new ArgumentException("dos must be 3.3 or 3.2."); }
        if (dos is not null && diskImage is not null)
        {
            throw new ArgumentException("Give dos or diskImage, not both.");
        }

        bool thirteenSectors = dos == "3.2"
            || (diskImage is not null && Path.GetExtension(diskImage).Equals(".d13", StringComparison.OrdinalIgnoreCase));

        int dosYear = args.Int("dosYear") ?? 1983;
        if (dosYear is not (1983 or 1980)) { throw new ArgumentException("dosYear must be 1983 or 1980."); }

        // A DOS launch boots a disk built later, once the program is known, in the SDK's 16- or 13-sector card.
        DiskIIFirmware? firmware = dos is null
            ? DiskFirmware(args, diskImage, sdk)
            : SdkModules.BuildDiskII(dos == "3.2" ? 13 : 16, sdk);


        // ${env:RETROCORE_IIE_ROMS} in a launch configuration is empty when the variable is not set.
        string? dumps = args.String("romDirectory");
        if (string.IsNullOrWhiteSpace(dumps)) { dumps = Environment.GetEnvironmentVariable(RomVariable(model)); }

        // The II's Monitor is the original or the Autostart ROM; the other models' Monitors are their own.
        string? monitor = args.String("monitor");
        if (monitor is not null && (model != Apple2Model.II || monitor is not ("original" or "autostart")))
        {
            throw new ArgumentException("monitor is the II's: original or autostart.");
        }

        bool autostart = model != Apple2Model.II || monitor == "autostart";

        Apple2Roms roms = string.IsNullOrWhiteSpace(dumps)
            ? SdkModules.BuildRoms(model, sdk, autostart)
            : Apple2Roms.LoadFromDirectory(model, dumps, autostart);

        // Programmer's Aid #1 in the II's D0 socket, which is otherwise empty.
        bool programmersAid = args.Bool("programmersAid") ?? false;
        if (programmersAid && model != Apple2Model.II)
        {
            throw new ArgumentException("programmersAid is the II's: Programmer's Aid #1 is a chip for its D0 socket.");
        }

        if (programmersAid) { roms = WithProgrammersAid(roms, dumps, sdk); }

        Apple2Machine machine = Apple2Loader.Load(model, roms, diskImage, firmware);
        int revision = args.Int("boardRevision") ?? 1;
        if (revision is not (0 or 1) || (revision == 0 && model != Apple2Model.II))
        {
            throw new ArgumentException("boardRevision is the II's: 0 or 1.");
        }

        machine.Bus.Video.Revision0 = revision == 0;

        // The II and II Plus came with 16, 32 or 48 KB on the board; the IIe always has 48.
        int ram = args.Int("ramKilobytes") ?? 48;
        if (ram is not (16 or 32 or 48) || (model.IsIIe() && ram != 48))
        {
            throw new ArgumentException("ramKilobytes is the II's and II Plus's: 16, 32 or 48.");
        }

        machine.Bus.RamKilobytes = ram;
        Apple2DebugTarget target = new(machine, model)
        {
            SdkRoms = sdk,
            Dos = dos,
            DosYear = dosYear,
            Autostart = autostart,
            ProgrammersAid = programmersAid,
            FirmwareRoms = model.IsIIe() ? null : FirmwareRomDirectory(model, dumps, args.String("firmwareCardRoms"))
        };

        // Slot 0 of a II or II Plus: the II Plus's language card unless the launch says otherwise, or the firmware
        // card with the other model's BASIC.
        string slot0 = args.String("slot0") ?? (model == Apple2Model.IIPlus ? "languageCard" : "empty");
        if (model.IsIIe() && args["slot0"] is not null)
        {
            throw new ArgumentException("slot0 is the II's and II Plus's.");
        }

        if (!model.IsIIe())
        {
            switch (slot0)
            {
                case "languageCard":
                    machine.Bus.InstallLanguageCard();
                    break;
                case "firmwareCard":
                    target.HardwareAction("slot0", "addFirmwareCard", []);
                    break;
                case "empty":
                    break;
                default:
                    throw new ArgumentException("slot0 must be languageCard, firmwareCard or empty.");
            }
        }

        machine.Run(cycles: 7);
        if (machine.Bus.DiskII.IsInstalled && args.String("diskBootRom") is null)
        {
            target._diskSectors[6] = args.Int("diskSectors") ?? (thirteenSectors ? 13 : 16);
        }

        // The Mockingboard is a card a launch puts in; asking to hear it puts it in unless the launch says not to, and
        // then the speaker is all there is to hear.
        string sound = args.String("sound") ?? "speaker";
        if (args.Bool("mockingboard") ?? sound == "mockingboard") { machine.Bus.InstallMockingboard(); }
        if (args.Int("mouse") is { } mouse and not 0) { target.HardwareAction($"slot{mouse}", "addMouse", []); }
        foreach ((int slot, string? image) in ProFileMedia.LaunchCards(args, "a free slot, 1 to 7"))
        {
            target.HardwareAction($"slot{slot}", "addProFile", []);
            if (image is not null && machine.Bus.ProFileIn(slot) is { } card)
            {
                ProFileMedia.Insert(card.Drive, image);
            }
        }

        if (args.String("screen") is { } screen) { machine.Bus.Video.Monitor = ParseScreen(screen); }
        target.SetSound(sound == "mockingboard" && !machine.Bus.MockingboardInstalled ? "speaker" : sound);
        target.FastDisk = args.Bool("fastDisk") ?? true;
        target.StartControllers(args);
        return target;
    }

    /// <summary>
    ///  Gets the environment variable that names a model's ROM dumps when the launch gives no
    ///  <c>romDirectory</c>.
    /// </summary>
    /// <param name="model">The model.</param>
    /// <returns>
    ///  <c>RETROCORE_IIE_ROMS</c> for the IIe models, <c>RETROCORE_IIPLUS_ROMS</c> for the II Plus and
    ///  <c>RETROCORE_II_ROMS</c> for the II.
    /// </returns>
    internal static string RomVariable(Apple2Model model) => model switch
    {
        Apple2Model.IIPlus => "RETROCORE_IIPLUS_ROMS",
        Apple2Model.II => "RETROCORE_II_ROMS",
        _ => "RETROCORE_IIE_ROMS"
    };

    // Where a firmware card's ROMs are: the other model's dumps, given, or named by its variable, or in its folder
    // beside this model's (APPLE II+ beside APPLE II, as the dumps are laid out).
    private static string? FirmwareRomDirectory(Apple2Model model, string? dumps, string? given)
    {
        Apple2Model other = model == Apple2Model.II ? Apple2Model.IIPlus : Apple2Model.II;
        if (!string.IsNullOrWhiteSpace(given)) { return given; }
        if (Environment.GetEnvironmentVariable(RomVariable(other)) is { Length: > 0 } named) { return named; }
        if (string.IsNullOrWhiteSpace(dumps)) { return null; }
        string folder = Path.TrimEndingDirectorySeparator(Path.GetFullPath(dumps));
        if (Path.GetDirectoryName(folder) is not { } parent) { return null; }

        string beside = Path.Join(parent, other == Apple2Model.IIPlus ? "APPLE II+" : "APPLE II");
        return Directory.Exists(beside) ? beside : null;
    }

    /// <summary>
    ///  Gets whether a II has the Autostart Monitor; the II Plus always does.
    /// </summary>
    internal bool Autostart { get; init; }

    /// <summary>
    ///  Gets whether a II's D0 socket holds Programmer's Aid #1.
    /// </summary>
    internal bool ProgrammersAid { get; init; }

    // A II's ROMs with Programmer's Aid #1 at $D000-$D7FF: the launch's dump of the chip when it has one, else the
    // SDK's build, which matches it.
    private static Apple2Roms WithProgrammersAid(Apple2Roms roms, string? dumps, string? sdk)
    {
        byte[] system = roms.System.ToArray();
        string chip = string.IsNullOrWhiteSpace(dumps) ? "" : Path.Join(dumps, Apple2Roms.ProgrammersAidChip);
        byte[] aid = File.Exists(chip)
            ? File.ReadAllBytes(chip)
            : SdkModules.AssembleProgrammersAid(SdkModules.ProgrammersAidPath(sdk)).Sections[0].Bytes.ToArray();

        if (aid.Length != SdkModules.ProgrammersAidSize)
        {
            throw new InvalidDataException($"Programmer's Aid #1 is {SdkModules.ProgrammersAidSize} bytes, not {aid.Length}.");
        }

        // The ROMs hold $C000-$FFFF, so $D000 is $1000 in.
        aid.CopyTo(system.AsSpan(0x1000));
        return new Apple2Roms(system, roms.Characters);
    }

    /// <summary>
    ///  Gets whether the machine's BASIC in ROM is Integer BASIC: a II's, unless its AppleSoft firmware card answers,
    ///  or a II Plus's Integer BASIC firmware card when it answers.
    /// </summary>
    internal bool RunsIntegerBasic => (_model == Apple2Model.II) != _machine.Bus.FirmwareCardActive && !_model.IsIIe();

    /// <summary>
    ///  Starts Integer BASIC at its cold start, $E000, once the Monitor's reset has set up the screen: the original
    ///  Monitor's reset stops at its * prompt rather than starting BASIC.
    /// </summary>
    internal void StartIntegerBasic()
    {
        _machine.Run(cycles: 1_000_000);
        while (!_machine.Processor.IsInstructionBoundary) { _machine.StepCycle(); }
        ProgramCounter = 0xE000;
        _integerChecked = ulong.MaxValue;
    }

    /// <summary>
    ///  Gets the folder of the ROM dumps a II or II Plus firmware card holds, or null when there is none to use.
    /// </summary>
    internal string? FirmwareRoms { get; init; }

    /// <summary>
    ///  Gets the model a launch's <c>model</c> names: <c>ii</c>, <c>iiplus</c>, <c>iie</c> or <c>iie-enhanced</c>
    ///  (the default), or the IIe's older names <c>original</c> and <c>enhanced</c>.
    /// </summary>
    /// <param name="name">The launch's <c>model</c>, or null.</param>
    /// <returns>The model.</returns>
    /// <exception cref="ArgumentException">The name is unknown, or names a model not yet emulated.</exception>
    internal static Apple2Model Model(string? name) => name switch
    {
        null or "iie-enhanced" or "enhanced" => Apple2Model.IIeEnhanced,
        "iie" or "original" => Apple2Model.IIe,
        "iiplus" => Apple2Model.IIPlus,
        "ii" => Apple2Model.II,
        _ => throw new ArgumentException("model must be ii, iiplus, iie or iie-enhanced.")
    };

    // apple2/button: presses or releases Open Apple (0), Closed Apple (1) or the game port's third button (2).
    private JsonObject Button(JsonObject args)
    {
        int button = args.Int("button") ?? throw new ArgumentException("button is required.");
        if (button is < 0 or > 2) { throw new ArgumentException("button must be 0, 1 or 2."); }
        _machine.Bus.SetButton(button, args.Bool("pressed") ?? throw new ArgumentException("pressed is required."));
        return [];
    }

    // apple2/mouse: moves the mouse card's mouse by dx and dy and sets its button when pressed is given. Without the
    // card, nothing happens.
    private JsonObject Mouse(JsonObject args)
    {
        if (_machine.Bus.MouseSlot == 0) { return []; }
        Apple2MouseCard mouse = _machine.Bus.Mouse;
        mouse.Move(args.Int("dx") ?? 0, args.Int("dy") ?? 0);
        if (args.Bool("pressed") is { } pressed) { mouse.Button = pressed; }
        return [];
    }

    /// <inheritdoc/>
    public IReadOnlyList<string> Screens => DebugScreens.WithColor;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   A monochrome monitor shows each of the 560 dots on its own, rather than the color a run of them makes.
    ///  </para>
    /// </remarks>
    public string Screen
    {
        get => _machine.Bus.Video.Monitor.ToString().ToLowerInvariant();
        set => _machine.Bus.Video.Monitor = ParseScreen(value);
    }

    // The launch's and the panel's names for the monitors.
    private static Apple2Monitor ParseScreen(string screen) => screen switch
    {
        "color" => Apple2Monitor.Color,
        "green" => Apple2Monitor.Green,
        "amber" => Apple2Monitor.Amber,
        "white" => Apple2Monitor.White,
        _ => throw new ArgumentException("screen must be color, white, green or amber.")
    };

    // apple2/sound: changes what the panel hears while running, as the launch's sound option does.
    // apple2/fastDisk: turns fast disk on or off.
    private JsonObject FastDiskRequest(JsonObject args)
    {
        FastDisk = args.Bool("enabled") ?? throw new ArgumentException("enabled is required.");
        return new JsonObject { ["enabled"] = FastDisk };
    }

    private JsonObject Sound(JsonObject args)
    {
        SetSound(args.String("mode") ?? throw new ArgumentException("mode is required."));
        return new JsonObject { ["mode"] = _soundMode };
    }

    // off attaches no sink, so the mixer only counts cycles; speaker mixes the speaker alone, in mono, costing about
    // 2%; mockingboard adds the two AY chips in stereo, which costs about 28% because their output is worked out
    // every cycle.
    private void SetSound(string mode)
    {
        Apple2Audio audio = _machine.Bus.Audio;
        _sound = mode switch
        {
            "off" => null,
            "speaker" => new DebugAudioSink(channels: 1, audio.SampleRate),
            "mockingboard" when _machine.Bus.MockingboardInstalled => new DebugAudioSink(channels: 2, audio.SampleRate),
            "mockingboard" => throw new ArgumentException("The Mockingboard is not in slot 4 to hear."),
            _ => throw new ArgumentException("sound must be off, speaker or mockingboard.")
        };

        audio.MixMockingboard = mode == "mockingboard";
        audio.Sink = _sound;
        _soundMode = mode;
    }

    /// <inheritdoc/>
    public JsonObject? TakeAudio()
    {
        if (_sound is null) { return null; }
        _machine.Bus.Audio.Flush();
        return _sound.Take() is { } samples
            ? new JsonObject { ["rate"] = _sound.SampleRate, ["channels"] = _sound.Channels, ["samples"] = samples }
            : null;
    }

    // A Disk II in slot six reads a floppy image; a .po image goes to the slot seven block device unless the
    // launch asks for the Disk II. Its ROMs are the given dumps, or the SDK's 16- or 13-sector sources.
    private static DiskIIFirmware? DiskFirmware(JsonObject args, string? diskImage, string? sdk)
    {
        bool blockImage = diskImage is not null
            && Path.GetExtension(diskImage).Equals(".po", StringComparison.OrdinalIgnoreCase);

        string? p5 = args.String("diskBootRom");
        string? p6 = args.String("diskSequencerRom");
        if ((p5 is null) != (p6 is null)) { throw new ArgumentException("Both Disk II firmware paths are required."); }
        string fallback = p5 is not null || (diskImage is not null && !blockImage) ? "diskII" : "slot7";
        bool diskII = (args.String("diskController") ?? fallback) switch
        {
            "diskII" => true,
            "slot7" => false,
            _ => throw new ArgumentException("diskController must be diskII or slot7.")
        };

        if (!diskII)
        {
            return blockImage || diskImage is null
                ? null
                : throw new ArgumentException("The slot seven block device takes a ProDOS-order .po image.");
        }

        if (p5 is not null)
        {
            return new(
                File.ReadAllBytes(p5),
                File.ReadAllBytes(p6 ?? throw new ArgumentException("Missing sequencer ROM.")),
                (args.String("sequencerLayout") ?? "raw") switch
                {
                    "raw" => P6PromLayout.Raw,
                    "beneath-prodos" => P6PromLayout.BeneathProDos,
                    "boot-socket" => P6PromLayout.BootSocket,
                    _ => throw new ArgumentException("Unknown P6 sequencer layout.")
                });
        }

        // A 13-sector image needs the 13-sector card; anything else defaults to the 16-sector one.
        bool thirteen = diskImage is not null
            && Path.GetExtension(diskImage).Equals(".d13", StringComparison.OrdinalIgnoreCase);

        int sectors = args.Int("diskSectors") ?? (thirteen ? 13 : 16);
        return sectors is 13 or 16
            ? SdkModules.BuildDiskII(sectors, sdk)
            : throw new ArgumentException("diskSectors must be 16 or 13.");
    }

    /// <inheritdoc/>
    public string ThreadName => _model switch
    {
        Apple2Model.II => "II CPU",
        Apple2Model.IIPlus => "II Plus CPU",
        _ => "IIe CPU"
    };

    /// <inheritdoc/>
    public string Cpu => _model.Processor().ToString();

    /// <inheritdoc/>
    public DebugRegisters Registers => s_registers;

    /// <inheritdoc/>
    public DebugFrame Frame => M6502Frames.Of(_machine.Processor.Registers);

    /// <inheritdoc/>
    public ushort ProgramCounter
    {
        get => _machine.Processor.Registers.ProgramCounter;
        set
        {
            ProcessorRegisters registers = _machine.Processor.Registers;
            registers.ProgramCounter = value;
            _machine.Processor.Registers = registers;
        }
    }

    /// <inheritdoc/>
    public bool IsInstructionBoundary => _machine.Processor.IsInstructionBoundary;

    /// <inheritdoc/>
    public bool InInstruction => _machine.Processor.CurrentOpCode is not null;

    /// <inheritdoc/>
    public ulong CycleCount => _machine.Bus.CycleCount;

    /// <inheritdoc/>
    public int ClockHertz => 1_020_484;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   With fast disk on, while any slot's Disk II has a drive motor turning: reading or writing, and the second or
    ///   so the drive takes to stop. Only the pacing changes; the machine runs the same cycles.
    ///  </para>
    /// </remarks>
    public bool Accelerated
    {
        get
        {
            if (!FastDisk) { return false; }
            for (int slot = 1; slot <= 7; slot++)
            {
                if (_machine.Bus.DiskIIIn(slot) is { } card && (card.State(drive: 1).Motor || card.State(drive: 2).Motor))
                {
                    return true;
                }
            }

            return false;
        }
    }

    /// <summary>
    ///  Gets or sets whether running goes as fast as it can while a Disk II motor turns.
    /// </summary>
    internal bool FastDisk { get; set; } = true;

    /// <inheritdoc/>
    public IDebugCallStack CallStack => _calls;

    /// <inheritdoc/>
    public int DefaultLoadAddress => 0x6000;

    /// <inheritdoc/>
    public Enum ProgramArea => Apple2MemoryArea.MainRam;

    /// <inheritdoc/>
    public string ContractModel => _model.DocumentationName();

    /// <inheritdoc/>
    public IReadOnlyList<string> UsedRegisters { get; } = ["A", "X", "Y"];

    /// <inheritdoc/>
    public (string Name, ushort Start, int Length) MemoryScope => ("Zero page", 0, 256);

    /// <inheritdoc/>
    public IReadOnlyDictionary<string, Func<JsonObject, JsonObject>> Requests { get; }

    /// <inheritdoc/>
    public byte Peek(ushort address) => _machine.Bus.Peek(address);

    /// <inheritdoc/>
    public Enum ReadArea(ushort address) => _machine.Bus.ReadArea(address);

    /// <inheritdoc/>
    public bool StepCycle()
    {
        ProcessorRegisters before = _machine.Processor.Registers;
        bool wasBoundary = _machine.Processor.IsInstructionBoundary;
        _machine.StepCycle();
        ProcessorCycle cycle = _machine.LastCycle;
        _calls.Observe(cycle, before, _machine.Processor.Registers, wasBoundary, _machine.Processor.IsInstructionBoundary);
        if (_machine.Processor.Status != ProcessorExecutionStatus.Running)
        {
            throw new InvalidOperationException($"CPU stopped: {_machine.Processor.Status}.");
        }

        return _machine.Processor.FetchedOpcode;
    }

    /// <inheritdoc/>
    public (ushort Target, int Length)? CallAt(ushort address) =>
        Peek(address) == JsrOpcode ? ((ushort)(Peek((ushort)(address + 1)) | (Peek((ushort)(address + 2)) << 8)), 3) : null;

    /// <inheritdoc/>
    public ProcessorCycle LastCycle => _machine.LastCycle;

    /// <inheritdoc/>
    public InstructionSet InstructionSet => M6502Isa.Get(_model.Processor());

    /// <inheritdoc/>
    public string? Trap(ushort address) => Peek(address) == BrkOpcode ? $"BRK at ${address:X4}." : null;

    /// <inheritdoc/>
    public bool HasBeam => true;

    /// <inheritdoc/>
    public void SetBeamBreaks(IReadOnlyCollection<int> positions)
    {
        _beamBreaks = [.. positions.Distinct().Order()];
        _nextBeamCycle = NextBeamBreak();
    }

    /// <inheritdoc/>
    public int? CycleBreak()
    {
        if (_nextBeamCycle != CycleCount) { return null; }
        int position = (int)(CycleCount % Apple2Video.CyclesPerFrame);
        _nextBeamCycle = NextBeamBreak();
        return position;
    }

    // The cycle the beam next reaches one of the positions, after this one.
    private ulong? NextBeamBreak()
    {
        if (_beamBreaks.Length == 0) { return null; }
        int now = _machine.Bus.Video.Beam.CycleInFrame;
        int distance = int.MaxValue;
        foreach (int position in _beamBreaks)
        {
            distance = Math.Min(distance, position > now ? position - now : position - now + Apple2Video.CyclesPerFrame);
        }

        return CycleCount + (ulong)distance;
    }

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   The byte goes to the RAM a read of the address maps now, so it is what the CPU and the memory view read
    ///   back.
    ///  </para>
    /// </remarks>
    /// <exception cref="ArgumentException">The address reads ROM, I/O or nothing.</exception>
    public void Poke(ushort address, byte value)
    {
        Apple2MemoryArea area = _machine.Bus.ReadArea(address);
        if (!_machine.Bus.PokeArea(area, address, value))
        {
            throw new ArgumentException($"${address:X4} reads {Label(area)} now, not RAM.");
        }
    }

    /// <inheritdoc/>
    public Enum WriteArea(ushort address) => _machine.Bus.WriteArea(address);

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   Main and auxiliary RAM each hold $0000-$BFFF and the language card's $D000-$FFFF, which is bank two at
    ///   $D000-$DFFF; bank one has its own banks. The system ROM, with the internal firmware at $C100-$CFFF, and
    ///   the ROMs of the slots that have one are read-only.
    ///  </para>
    /// </remarks>
    public IReadOnlyList<DebugMemoryBank> Banks
    {
        get
        {
            // The slots' ROMs come and go with their cards.
            if (_banks is null || _bankCards != _machine.Bus.CardChanges)
            {
                _banks = CreateBanks();
                _bankCards = _machine.Bus.CardChanges;
            }

            return _banks;
        }
    }

    private List<DebugMemoryBank>? _banks;
    private int _bankCards;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   The stack pointer points into page one.
    ///  </para>
    /// </remarks>
    public int? PointsTo(IsaRegister register, long value) => register.Name == "S"
        ? 0x100 | (int)(value & 0xFF)
        : register.Bits >= 16 ? (int)(value & 0xFFFF) : null;

    private List<DebugMemoryBank> CreateBanks()
    {
        List<DebugMemoryBank> banks =
        [
            Bank("main", "Main RAM", [(0x0000, 0xC000), (0xD000, 0x3000)], Apple2MemoryArea.MainRam, Apple2MemoryArea.MainLanguageCard)
        ];

        if (_model.IsIIe())
        {
            banks.Add(Bank(
                "aux",
                "Auxiliary RAM",
                [(0x0000, 0xC000), (0xD000, 0x3000)],
                Apple2MemoryArea.AuxiliaryRam,
                Apple2MemoryArea.AuxiliaryLanguageCard));
        }

        banks.Add(Bank("bank1", "Main language card bank 1", [(0xD000, 0x1000)], Apple2MemoryArea.MainLanguageCardBank1));
        if (_model.IsIIe())
        {
            banks.Add(Bank(
                "auxbank1",
                "Auxiliary language card bank 1",
                [(0xD000, 0x1000)],
                Apple2MemoryArea.AuxiliaryLanguageCardBank1));

            banks.Add(Bank("rom", "System ROM", [(0xC100, 0x3F00)], Apple2MemoryArea.SystemRom));
        }
        else
        {
            banks.Add(Bank("rom", "System ROM", [(0xD000, 0x3000)], Apple2MemoryArea.SystemRom));
        }

        // Each slot whose card has a ROM page: a Disk II's boot ROM, the mouse or ProFile card's firmware, or slot
        // seven's block device.
        for (int slot = 1; slot <= 7; slot++)
        {
            Apple2MemoryArea area = Apple2MemoryArea.Slot1Rom + (slot - 1);
            ushort page = (ushort)(0xC000 | (slot << 8));
            if (!_machine.Bus.PeekArea(area, page, out _)) { continue; }
            string card = slot == _machine.Bus.MouseSlot
                ? "mouse card"
                : _machine.Bus.ProFileIn(slot) is not null
                    ? "ProFile card"
                    : _machine.Bus.DiskIIIn(slot) is not null ? "Disk II boot" : "block device";

            banks.Add(Bank($"slot{slot}", $"Slot {slot} ROM ({card})", [(page, 0x100)], area));
        }

        return banks;
    }

    // A bank of storage areas, each holding the range at the same index.
    private DebugMemoryBank Bank(string name, string label, (ushort Start, int Length)[] ranges, params Apple2MemoryArea[] areas) => new(
        name,
        label,
        [.. areas.Cast<Enum>()],
        ranges,
        address =>
        {
            foreach (Apple2MemoryArea area in areas)
            {
                if (_machine.Bus.PeekArea(area, address, out byte value)) { return value; }
            }

            return null;
        },
        areas is [Apple2MemoryArea.SystemRom or (>= Apple2MemoryArea.Slot1Rom and <= Apple2MemoryArea.Slot7Rom)]
            ? null
            : (address, value) => areas.Any(area => _machine.Bus.PokeArea(area, address, value)));

    private static string Label(Apple2MemoryArea area) => area switch
    {
        Apple2MemoryArea.Io => "I/O",
        Apple2MemoryArea.None => "nothing",
        Apple2MemoryArea.SystemRom => "the system ROM",
        _ => $"slot {area - Apple2MemoryArea.Slot1Rom + 1}'s ROM"
    };

    /// <inheritdoc/>
    public void Load(int address, ReadOnlySpan<byte> bytes)
    {
        if (address < 0 || address >= 0xC000 || bytes.Length > 0xC000 - address)
        {
            throw new ArgumentException("Program must fit in main RAM.");
        }

        for (int i = 0; i < bytes.Length; i++)
        {
            _machine.Bus.SetRam(auxiliary: false, (ushort)(address + i), bytes[i]);
        }
    }

    /// <inheritdoc/>
    public void AddSdkModules(DebugInfo debug, string? directory)
    {
        _basicRom = BasicRom.From(
            SdkModules.AddTo(debug, _model, directory, out Assembler.AssemblyResult? integer, Autostart)?.Symbols,
            "MAIN",
            run: "RUN",
            resume: "CONT",
            [("STOP", "STOP"), ("END", "END"), ("ENDCON", "ENDCON")]);

        _integerRom = IntegerBasicRom(integer?.Symbols);
    }

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   The BASIC in memory now: Integer BASIC when its syntax tables are at $EC00, from the II's ROM, a firmware
    ///   card or a language card DOS loaded; otherwise the model's AppleSoft, which a II has only on a firmware card.
    ///  </para>
    /// </remarks>
    public BasicDialect? Basic => IntegerActive ? BasicDialect.Integer : _model switch
    {
        Apple2Model.IIeEnhanced => BasicDialect.AppleSoft,
        Apple2Model.II when !_machine.Bus.FirmwareCardInstalled => null,
        _ => BasicDialect.AppleSoftOriginal
    };

    /// <inheritdoc/>
    public BasicRom? BasicRom => IntegerActive ? _integerRom : _basicRom;

    /// <inheritdoc/>
    public bool InRom(ushort address) =>
        _machine.Bus.ReadArea(address) == Apple2MemoryArea.SystemRom || (IntegerActive && address is >= 0xE000 and < 0xF800);

    /// <inheritdoc/>
    public int BasicTextPointer => IntegerActive ? IntegerWord(IntegerBasicDialect.Px) - 1 : IntegerWord(TextPointer);

    /// <inheritdoc/>
    public int BasicStack => 0x0100 + Peek(StatementStack) + 1;

    /// <inheritdoc/>
    public int BasicLiveStack => 0x0100 + _machine.Processor.Registers.StackPointer + 1;

    /// <inheritdoc/>
    public int BasicForSize => ForEntrySize;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   GOSUB pushes its five bytes over the statement fetcher's return address, which RETURN uses.
    ///  </para>
    /// </remarks>
    public int BasicGosubSize => 7;

    /// <inheritdoc/>
    public (int Code, string Message, bool Handled) BasicError()
    {
        if (IntegerActive) { return IntegerError(); }
        int code = _machine.Processor.Registers.X;
        string message = s_errors.TryGetValue(code, out string? text) ? $"?{text} ERROR" : $"error {code}";
        return (code, message, (Peek(ErrorFlag) & OnErrActive) != 0);
    }

    /// <inheritdoc/>
    public void SetBasicStatement(int line, int textPointer)
    {
        if (IntegerActive)
        {
            SetIntegerStatement(line, textPointer);
            return;
        }

        Poke(CurrentLine, (byte)line);
        Poke(CurrentLine + 1, (byte)(line >> 8));
        Poke(TextPointer, (byte)textPointer);
        Poke(TextPointer + 1, (byte)(textPointer >> 8));
    }

    /// <inheritdoc/>
    public void EnterBasicPrompt(BasicRom rom)
    {
        if (IntegerActive)
        {
            EnterIntegerPrompt(rom);
            return;
        }

        Poke(TempPointer, FirstTemporary);
        Poke(SubscriptFlag, 0);
        Poke(CurrentLineHigh, 0xFF);
        Poke(ErrorFlag, 0);
        Poke(0x01FF, 0);
        ProcessorRegisters registers = _machine.Processor.Registers;
        registers.StackPointer = EmptyStack;
        registers.ProgramCounter = rom.Prompt;
        _machine.Processor.Registers = registers;
        _calls.Reset();
    }

    /// <inheritdoc/>
    public bool Key(int code)
    {
        _machine.Bus.QueueKey((byte)code);
        return true;
    }

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   About 30 ms a key and 300 ms after a line, at the II's 1.02 MHz: Apple Pascal's Editor takes keys into its
    ///   own type-ahead, which overflows if a pasted program comes faster.
    ///  </para>
    /// </remarks>
    public (ulong Key, ulong Line)? TypingPace => (30_000, 300_000);

    /// <inheritdoc/>
    public void Reset()
    {
        _machine.Reset();
        _resetPending = true;
    }

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   The reset sequence is not at an instruction boundary, so the first boundary after it is the handler's first
    ///   instruction, where the reset vector points.
    ///  </para>
    /// </remarks>
    public bool TakeResetStop()
    {
        if (!_resetPending || !IsInstructionBoundary) { return false; }
        _resetPending = false;
        return true;
    }

    /// <inheritdoc/>
    public IReadOnlyList<Machines.Devices.IDevice> Devices => _machine.Devices;

    /// <inheritdoc/>
    public void DeviceAction(Machines.Devices.IDevice device, string action, JsonObject args)
    {
        switch (device, action)
        {
            case (Apple2FloppyDrive drive, "insert"):
                string path = Path.GetFullPath(args.String("path") ?? throw new ArgumentException("path is required."));
                drive.Eject();
                Apple2Loader.Insert(drive, path);
                break;
            case (Apple2FloppyDrive drive, "eject"):
                drive.Eject();
                break;
            case (Apple2FloppyDrive drive, "writeProtect"):
                drive.SetWriteProtected(args.Bool("writeProtected") ?? throw new ArgumentException("writeProtected is required."));
                break;
            case (Apple2FloppyDrive drive, "save"):
                Apple2Loader.Save(drive, args.String("path"));
                break;
            case (ProFileDrive drive, "insert"):
                ProFileMedia.Insert(drive, args.String("path") ?? throw new ArgumentException("path is required."));
                break;
            case (ProFileDrive drive, "eject"):
                drive.Eject();
                break;
            default:
                throw new ArgumentException($"{device.Info.Name} does not support {action}.");
        }
    }

    /// <inheritdoc/>
    public IEnumerable<(string Event, JsonObject Body)> StatusEvents()
    {
        yield return ("apple2/disk", DiskState());
    }

    /// <inheritdoc/>
    public JsonObject DisplayState(bool running)
    {
        int columns = (_machine.Bus.Switches & Apple2Switches.Column80) != 0 ? 80 : 40;
        string[] rows = new string[24];
        for (int row = 0; row < rows.Length; row++)
        {
            char[] chars = new char[columns];
            for (int column = 0; column < columns; column++)
            {
                int value = _machine.Bus.TextByte(row, column) & 127;
                chars[column] = (char)(value < 32 ? value + 64 : value);
            }

            rows[row] = new(chars);
        }

        return new JsonObject
        {
            ["machine"] = DebugMachines.Apple2,
            ["model"] = _model.DisplayName(),
            ["columns"] = columns,
            ["rows"] = rows.ToJsonArray(),
            ["scanline"] = _machine.Bus.Scanline,
            ["columnClock"] = _machine.Bus.ColumnClock,
            ["cycles"] = _machine.Processor.CycleCount,
            ["video"] = VideoState(),
            ["disk"] = DiskState(),
            ["sound"] = _soundMode,
            ["mockingboard"] = _machine.Bus.MockingboardInstalled,
            ["mouse"] = _machine.Bus.MouseSlot,
            ["screen"] = Screen,
            ["screens"] = Screens.ToJsonArray(),
            ["fastDisk"] = FastDisk,
            ["running"] = running
        };
    }

    /// <summary>
    ///  Gets the SDK's ROM sources the launch named, which a Disk II card added later builds its firmware from.
    /// </summary>
    internal string? SdkRoms { get; init; }

    /// <summary>
    ///  Gets the DOS the launch boots with the program on its disk, such as <c>3.3</c>, or null.
    /// </summary>
    internal string? Dos { get; init; }

    /// <summary>
    ///  Gets which DOS 3.3 the launch boots: 1983 or 1980.
    /// </summary>
    internal int DosYear { get; init; } = 1983;

    /// <summary>
    ///  Puts a program on a fresh DOS disk in drive 1, as a binary file with a HELLO that BRUNs it, for the IIe
    ///  to boot. The disk holds DOS as INIT writes it, built from the SDK's sources.
    /// </summary>
    /// <param name="address">Where the program loads, which is also where BRUN starts it.</param>
    /// <param name="program">The program.</param>
    /// <param name="name">The binary file's name.</param>
    /// <exception cref="InvalidDataException">The DOS sources have errors.</exception>
    internal void LoadOnDosDisk(int address, ReadOnlySpan<byte> program, string name)
    {
        bool thirteen = Dos == "3.2";
        byte[] dos = SdkModules.AssembleDos(
            SdkModules.DosPath(thirteen ? "Dos32.asm" : "Dos33.asm", SdkRoms),
            master: false,
            DosYear)
            .Sections[0]
            .Bytes
            .ToArray();

        BasicProgram hello = BasicProgram.Parse($"10 PRINT CHR$(4);\"BRUN {name}\"\n", Basic).Program
            ?? throw new InvalidDataException("The greeting program doesn't parse.");

        byte[] disk = DosDisk.Create(
            thirteen ? DosDisk.Dos32Tracks(dos) : DosDisk.Dos33Tracks(dos),
            [DosFile.AppleSoft("HELLO", hello.ToImage(address: 0x0801)), DosFile.Binary(name, address, program)],
            thirteen ? 13 : 16);

        WozDisk media = thirteen
            ? SectorDiskConverter.ConvertThirteenSector(disk)
            : SectorDiskConverter.Convert(disk, proDosOrder: false);

        _machine.Drives[0].Insert(media, $"DOS {Dos} disk with {name}", thirteen ? "D13" : "DSK");
    }

    /// <inheritdoc/>
    public IReadOnlyList<HardwareRow> Hardware()
    {
        if (!_model.IsIIe()) { return BoardHardware(); }
        bool enhanced = _model == Apple2Model.IIeEnhanced;
        return
        [
            new(
                "model",
                "Apple IIe",
                enhanced ? "Enhanced, 65C02" : "Original, 6502",
                "The launch's model: enhanced (the default) or original, with its own ROMs and processor."),
            new(
                "memory",
                "Main memory",
                "64 KB, with the language card's bank-switched 16 KB",
                "Built in: 48 KB at $0000-$BFFF and the language card's 16 KB at $D000-$FFFF, its first 4 KB in two banks."),
            new(
                "builtIn",
                "Built in",
                "Speaker, keyboard, game-port buttons",
                "The IIe's own speaker and keyboard, and the Open Apple, Closed Apple and third buttons."),
            GamePortRow(),
            new(
                "auxiliary",
                "Auxiliary slot",
                "Extended 80-column card, 64 KB",
                "Adds 80-column text, double hi-res and 64 KB of auxiliary memory, banked by the 80STORE, RAMRD, RAMWRT and "
                    + "ALTZP switches. Every launch has it."),
            Slot(1),
            Slot(2),
            HardwareRow.Empty(3, "The IIe's own 80-column firmware answers in slot 3's space, with the auxiliary card in."),
            Slot(4),
            Slot(5),
            Slot(6),
            Slot(7)
        ];
    }

    // The II and II Plus: the board, slot 0, and slots 1 to 7, slot 3 free like the others.
    private List<HardwareRow> BoardHardware() =>
    [
        _model == Apple2Model.II
            ? new(
                "model",
                "Apple II",
                (Autostart ? "6502, Autostart Monitor" : "6502, original Monitor") + (_machine.Bus.Video.Revision0 ? ", revision 0" : ""),
                "The launch's model: ii, with Integer BASIC and the Monitor its monitor option picks (original, which "
                    + "resets into the Monitor, or autostart) and an NMOS 6502. boardRevision 0 gives early boards' "
                    + "four hi-res colors.")
            : new(
                "model",
                "Apple II Plus",
                "6502",
                "The launch's model: iiplus, with AppleSoft and the Autostart Monitor in ROM and an NMOS 6502."),
        new(
            "memory",
            "Main memory",
            $"{_machine.Bus.RamKilobytes} KB",
            $"On the board: {_machine.Bus.RamKilobytes} KB from $0000, as the launch's ramKilobytes says (16, 32 or 48). "
                + "A language card in slot 0 adds 16 KB at $D000-$FFFF."),
        new(
            "builtIn",
            "Built in",
            "Speaker, keyboard, game-port buttons",
            $"The {_model.DisplayName()}'s speaker, its keyboard, which has no lowercase, and the game port's three "
                + "buttons."),
        GamePortRow(),
        .. (_model == Apple2Model.II ? (HardwareRow[])[D0Socket()] : []),
        Slot0(),
        Slot(1),
        Slot(2),
        Slot(3),
        Slot(4),
        Slot(5),
        Slot(6),
        Slot(7)
    ];

    // The II's D0 socket, $D000-$D7FF: Programmer's Aid #1 when the launch puts it in.
    private HardwareRow D0Socket() =>
        new(
            "d0Socket",
            "D0 socket",
            ProgrammersAid ? "Programmer's Aid #1" : "empty",
            "The II's ROM socket at $D000-$D7FF, empty as Apple shipped it. The launch option programmersAid: true puts in "
                + "Programmer's Aid #1: hi-res graphics, renumber, append, relocate, tape verify, a RAM test and music.");

    // Slot 0 of a II or II Plus: the language card, the firmware card, or nothing.
    private HardwareRow Slot0()
    {
        if (_machine.Bus.LanguageCardInstalled)
        {
            return new(
                "slot0",
                "Slot 0",
                "Language card, 16 KB",
                "16 KB of RAM at $D000-$FFFF in place of the ROM, its first 4 KB in two banks, switched at "
                    + "$C080-$C08F. The launch's slot0 languageCard installs it; Remove Card takes it out.",
                [],
                ["removeCard"]);
        }

        if (_machine.Bus.FirmwareCardInstalled)
        {
            string basic = _model == Apple2Model.II ? "AppleSoft" : "Integer BASIC";
            string state = _machine.Bus.FirmwareCardActive ? "on" : "off";
            return new(
                "slot0",
                "Slot 0",
                $"{basic} firmware card ({state})",
                $"{basic} and its Monitor in 12 KB of ROM that answers at $D000-$FFFF in place of the board's: $C080 "
                    + "selects the card, $C081 the board, as DOS 3.3's FP and INT do. The launch's slot0 firmwareCard "
                    + "installs it; Remove Card takes it out.",
                [],
                ["removeCard"]);
        }

        return HardwareRow.Empty(
            0,
            "Add Card puts a language card or a firmware card with the other BASIC here; so does the launch's slot0.",
            free: true);
    }

    // A slot that can hold a card: its Disk II card and drives, slot 4's Mockingboard, slot 7's block storage, or
    // empty.
    private HardwareRow Slot(int slot)
    {
        string addCard = slot == 4
            ? "Add Card puts the Mockingboard, a Disk II controller, the mouse card or a ProFile card here."
            : "Add Card puts a Disk II controller, the mouse card or a ProFile card here.";

        if (_machine.Bus.ProFileIn(slot) is { } proFile)
        {
            return new(
                $"slot{slot}",
                $"Slot {slot}",
                "ProFile interface card",
                "Apple's ProFile hard disk as a ProDOS block device, through Retrocore's firmware for the card. Insert a "
                    + ".po or .hdv image of up to 65535 blocks; the startup scan boots it from the highest slot. The "
                    + "launch's proFiles installs it; Remove Card takes it out.",
                [proFile.Drive.Id],
                ["removeCard"]);
        }

        if (slot == _machine.Bus.MouseSlot)
        {
            return new(
                $"slot{slot}",
                $"Slot {slot}",
                "Mouse card",
                "A mouse with the AppleMouse II's firmware calls, interrupts and BASIC IN#/PR# interface. Click the "
                    + "display to move it with your mouse; Escape lets go. The launch installs it with mouse and a slot; "
                    + "Remove Card takes it out.",
                [],
                ["removeCard"]);
        }

        if (slot == 4 && _machine.Bus.MockingboardInstalled)
        {
            return new(
                "slot4",
                "Slot 4",
                "Mockingboard",
                "Two 6522 VIAs and two AY-3-8910 sound chips. The launch installs it with mockingboard true, or with "
                    + "sound mockingboard, which also plays it; Remove Card takes it out.",
                [],
                ["removeCard"]);
        }

        if (_machine.Bus.DiskIIIn(slot) is not null)
        {
            string sectors = _diskSectors.TryGetValue(slot, out int count) ? $", {count}-sector" : "";
            string launch = "";
            if (slot == 6)
            {
                launch = " The launch installs it with diskController diskII, the default for a .dsk, .do, .nib or .woz "
                    + "diskImage.";
            }

            return new(
                $"slot{slot}",
                $"Slot {slot}",
                $"Disk II controller{sectors}",
                $"Two 5.25-inch drives on this card. Remove Card takes it out and ejects its disks.{launch}",
                [.. _machine.DrivesIn(slot).Select(drive => drive.Id)],
                ["removeCard"]);
        }

        if (slot == 7 && _machine.BlockStorage is { } storage)
        {
            return new(
                "slot7",
                "Slot 7",
                "Block storage",
                "A ProDOS block device for a .po diskImage, the default controller for that image.",
                [storage.Id]);
        }

        string hint = slot switch
        {
            4 => " A launch installs the Mockingboard with mockingboard true.",
            6 => " A launch installs one with diskController diskII, or a .dsk, .do, .nib or .woz diskImage.",
            7 => " A .po diskImage installs block storage here instead.",
            _ => ""
        };

        return HardwareRow.Empty(slot, addCard + hint, free: _machine.Bus.IsSlotFree(slot));
    }

    /// <inheritdoc/>
    public void HardwareAction(string id, string action, JsonObject args)
    {
        int slot = id is ['s', 'l', 'o', 't', >= '0' and <= '7' and var digit] ? digit - '0' : -1;
        switch (action)
        {
            case "addLanguageCard" when slot == 0 && _machine.Bus.IsSlot0Free:
                _machine.Bus.InstallLanguageCard();
                break;
            case "addFirmwareCard" when slot == 0 && _machine.Bus.IsSlot0Free:
                // The other model's BASIC and Monitor: from its dumps when there are some, else the SDK's sources.
                Apple2Model other = _model == Apple2Model.II ? Apple2Model.IIPlus : Apple2Model.II;
                byte[] card = FirmwareRoms is { } roms
                    ? Apple2Roms.LoadFirmwareCard(other, roms)
                    : SdkModules.BuildBoardSystem(other, autostart: false, SdkRoms);

                // The AppleSoft card's switch is up on a II, so its Autostart Monitor boots; the Integer card's is down
                // on a II Plus, as its original Monitor would not boot.
                _machine.Bus.InstallFirmwareCard(card, active: _model == Apple2Model.II);
                break;
            case "removeCard" when slot == 0 && !_model.IsIIe() && _machine.Bus.LanguageCardInstalled:
                _machine.Bus.RemoveLanguageCard();
                break;
            case "removeCard" when slot == 0 && _machine.Bus.FirmwareCardInstalled:
                _machine.Bus.RemoveFirmwareCard();
                break;
            case "addDiskII" when slot > 0 && _machine.Bus.IsSlotFree(slot):
                int sectors = args.Int("sectors") ?? 16;
                if (sectors is not (13 or 16)) { throw new ArgumentException("sectors must be 16 or 13."); }
                _machine.Bus.InstallDiskII(slot, SdkModules.BuildDiskII(sectors, SdkRoms));
                _diskSectors[slot] = sectors;
                break;
            case "addMouse" when _machine.Bus.MouseSlot != 0:
                throw new ArgumentException($"The mouse card is already in slot {_machine.Bus.MouseSlot}.");
            case "addMouse" when slot > 0 && _machine.Bus.MouseSlot == 0 && _machine.Bus.IsSlotFree(slot):
                _machine.Bus.InstallMouse(slot);
                break;
            case "removeCard" when slot > 0 && slot == _machine.Bus.MouseSlot:
                _machine.Bus.RemoveMouse();
                break;
            case "addProFile" when slot > 0 && _machine.Bus.IsSlotFree(slot):
                _machine.Bus.InstallProFile(slot);
                break;
            case "removeCard" when slot > 0 && _machine.Bus.ProFileIn(slot) is not null:
                _machine.Bus.RemoveProFile(slot);
                break;
            case "addMockingboard" when slot == 4 && _machine.Bus.IsSlotFree(4):
                _machine.Bus.InstallMockingboard();
                break;
            case "removeCard" when slot == 4 && _machine.Bus.MockingboardInstalled:
                _machine.Bus.RemoveMockingboard();

                // Without the card there is only the speaker to hear.
                if (_soundMode == "mockingboard") { SetSound("speaker"); }
                break;
            case "removeCard" when slot > 0 && _machine.Bus.DiskIIIn(slot) is not null:
                _machine.Bus.RemoveDiskII(slot);
                _diskSectors.Remove(slot);
                break;
            default:
                throw new ArgumentException($"The {id} hardware does not support {action}.");
        }
    }

    /// <inheritdoc/>
    public JsonObject? Cards()
    {
        JsonObject cards = [];
        ReadOnlySpan<int> slots = _model.IsIIe() ? [1, 2, 4, 5, 6, 7] : [0, 1, 2, 3, 4, 5, 6, 7];
        foreach (int slot in slots) { cards[$"{slot}"] = CardIn(slot); }
        return cards;
    }

    /// <inheritdoc/>
    public IEnumerable<string> RestoreCards(JsonObject cards)
    {
        List<string> problems = [];
        foreach ((string key, JsonNode? node) in cards)
        {
            string? card = node?.GetValueKind() == System.Text.Json.JsonValueKind.String ? node.GetValue<string>() : null;
            bool usable = int.TryParse(key, out int slot) && (_model.IsIIe() ? slot is >= 1 and <= 7 and not 3 : slot is >= 0 and <= 7);
            if (!usable || card is null)
            {
                problems.Add($"Slot {key} cannot take the saved card '{node}'.");
                continue;
            }

            string current = CardIn(slot);

            // Block storage, and a Disk II with the launch's own ROM dumps, are the launch's to give.
            bool launchOwned = current is "blockStorage" or "diskII" || card is "blockStorage" or "diskII";
            if (card == current || launchOwned) { continue; }
            string id = $"slot{slot}";
            try
            {
                if (current != "empty") { HardwareAction(id, "removeCard", []); }
                switch (card)
                {
                    case "mockingboard":
                        HardwareAction(id, "addMockingboard", []);
                        break;
                    case "mouse":
                        // The machine has one mouse card: the saved slot wins over the launch's, whatever the order
                        // the slots come in.
                        if (_machine.Bus.MouseSlot is not 0 and var other && other != slot && _machine.Bus.IsSlotFree(slot))
                        {
                            HardwareAction($"slot{other}", "removeCard", []);
                        }

                        HardwareAction(id, "addMouse", []);
                        break;
                    case "proFile":
                        HardwareAction(id, "addProFile", []);
                        break;
                    case "languageCard":
                        HardwareAction(id, "addLanguageCard", []);
                        break;
                    case "firmwareCard":
                        HardwareAction(id, "addFirmwareCard", []);
                        break;
                    case "diskII16" or "diskII13":
                        HardwareAction(id, "addDiskII", new JsonObject { ["sectors"] = card == "diskII13" ? 13 : 16 });
                        break;
                    case "empty":
                        break;
                    default:
                        problems.Add($"Slot {slot} cannot take the saved card '{card}'.");
                        break;
                }
            }
            catch (ArgumentException error)
            {
                problems.Add(error.Message);
            }
        }

        return problems;
    }

    // A slot's card, as Cards saves it: languageCard or firmwareCard (slot 0 of the II and II Plus), mockingboard, mouse,
    // proFile, diskII16 or diskII13 for a Disk II built from the SDK's ROMs, diskII for one with the launch's ROM
    // dumps, blockStorage, or empty.
    private string CardIn(int slot)
    {
        if (slot == 0)
        {
            return _machine.Bus.LanguageCardInstalled
                ? "languageCard"
                : _machine.Bus.FirmwareCardInstalled ? "firmwareCard" : "empty";
        }

        if (slot == 4 && _machine.Bus.MockingboardInstalled) { return "mockingboard"; }
        if (slot == _machine.Bus.MouseSlot) { return "mouse"; }
        if (_machine.Bus.ProFileIn(slot) is not null) { return "proFile"; }
        if (_machine.Bus.DiskIIIn(slot) is not null)
        {
            return _diskSectors.TryGetValue(slot, out int sectors) ? $"diskII{sectors}" : "diskII";
        }

        return slot == 7 && _machine.BlockStorage is not null ? "blockStorage" : "empty";
    }

    /// <inheritdoc/>
    public ReadOnlySpan<byte> RenderVideo()
    {
        _machine.Bus.Video.RenderScannedBitmap(_pixels);
        return _pixels;
    }

    // apple2/text: the whole frame, with the text screen's own 1-bit-per-dot bitmap besides the video.
    private JsonObject TextFrame()
    {
        JsonObject frame = ((IDebugTarget)this).DisplayFrame(running: false);
        frame["width"] = (frame.Int("columns") ?? 0) * 7;
        frame["height"] = 192;
        frame["pixels"] = Convert.ToBase64String(_machine.Bus.RenderTextBitmap());
        return frame;
    }

    private JsonObject VideoState() => new JsonObject
    {
        ["width"] = Apple2Video.Width,
        ["height"] = Apple2Video.Height,
        ["pixelFormat"] = "rgba",
        ["beam"] = Beam(),
        ["cycles"] = _machine.Bus.CycleCount
    };

    private JsonObject VideoFrame(bool scanned) => new JsonObject
    {
        ["width"] = Apple2Video.Width,
        ["height"] = Apple2Video.Height,
        ["pixelFormat"] = "rgba",
        ["pixels"] = Convert.ToBase64String(scanned ? _machine.Bus.Video.RenderScannedBitmap() : _machine.Bus.Video.RenderBitmap()),
        ["beam"] = Beam(),
        ["cycles"] = _machine.Bus.CycleCount
    };

    private JsonObject Beam()
    {
        Apple2Beam beam = _machine.Bus.Video.Beam;
        return new JsonObject
        {
            ["scanline"] = beam.Scanline,
            ["column"] = beam.ColumnClock,
            ["cycleInFrame"] = beam.CycleInFrame,
            ["horizontalBlank"] = beam.HorizontalBlank,
            ["verticalBlank"] = beam.VerticalBlank,
            ["fetchAddress"] = _machine.Bus.Video.FetchAddress,
            ["cycles"] = _machine.Bus.CycleCount
        };
    }

    private JsonObject DiskState() => new JsonObject
    {
        ["installed"] = _machine.Bus.DiskII.IsInstalled,
        ["dataLatch"] = _machine.Bus.DiskII.DataLatch,
        ["writeMode"] = _machine.Bus.DiskII.WriteMode,
        ["drives"] = Enumerable.Range(1, 2).Select(drive =>
        {
            DiskDriveState state = _machine.Bus.DiskII.State(drive);
            return new JsonObject
            {
                ["drive"] = drive,
                ["quarterTrack"] = state.QuarterTrack,
                ["track"] = state.QuarterTrack / 4.0,
                ["bitPosition"] = state.BitPosition,
                ["bitCount"] = state.BitCount,
                ["motor"] = state.Motor,
                ["mounted"] = state.Mounted,
                ["writeProtected"] = state.WriteProtected,
                ["dirty"] = state.Dirty
            };
        }).ToJsonArray()
    };
}
