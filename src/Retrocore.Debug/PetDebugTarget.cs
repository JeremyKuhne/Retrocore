// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Isa;
using Retrocore.Machines;
using Retrocore.Machines.Commodore;
using Retrocore.Machines.Devices;
using System.Text.Json.Nodes;

namespace Retrocore.Debug;

/// <summary>
///  The Commodore PET 2001 as the debugger sees it: a 6502, BASIC, the screen editor and the kernal, its 40x25 screen,
///  keyboard, sound and Datasettes.
/// </summary>
internal sealed partial class PetDebugTarget : IDebugTarget
{
    private const byte JsrOpcode = 0x20;
    private const byte BrkOpcode = 0x00;

    private static readonly DebugRegisters s_registers = new(M6502Isa.Description);

    private readonly PetMachine _machine;
    private readonly DebugCallStack _calls;
    private readonly byte[] _pixels;
    private string _screen;
    private bool _resetPending;
    private DebugAudioSink? _sound;
    private string _soundMode = "off";

    /// <summary>
    ///  Creates the target for a launched PET.
    /// </summary>
    /// <param name="machine">The machine.</param>
    internal PetDebugTarget(PetMachine machine)
    {
        _machine = machine;
        _calls = new(machine.Bus.Peek);
        _pixels = new byte[machine.Video.Width * machine.Video.Height * 4];
        _screen = machine.Model == PetModel.Pet2001 ? DebugScreens.White : DebugScreens.Green;
        Requests = new Dictionary<string, Func<JsonObject, JsonObject>>
        {
            ["retro/media"] = Media,
            ["retro/video"] = args => VideoFrame(args.Bool("scanned") ?? true),
            ["retro/sound"] = args =>
            {
                SetSound(args.String("mode") ?? throw new ArgumentException("mode is required."));
                return new JsonObject { ["mode"] = _soundMode };
            }
        };
    }

    /// <summary>
    ///  Gets the machine.
    /// </summary>
    internal PetMachine Machine => _machine;

    /// <summary>
    ///  Gets or sets whether running outpaces the clock while a Datasette's motor runs with a key down.
    /// </summary>
    internal bool FastCassette { get; set; } = true;

    /// <summary>
    ///  Gets or sets whether the ROMs were built from the SDK's sources rather than loaded from dumps.
    /// </summary>
    internal bool SdkRoms { get; set; }

    /// <summary>
    ///  Gets or sets whether BASIC's revised chip is the original instead: BASIC 1's 901447-01 rather than 901447-09,
    ///  or BASIC 4's 901465-19 rather than 901465-23.
    /// </summary>
    internal bool OriginalBasic { get; set; }

    /// <summary>
    ///  Gets the BASIC source used for the ROM build and debugger mapping.
    /// </summary>
    internal BasicSourceKind BasicSource { get; init; } = BasicSourceKind.Native;

    /// <inheritdoc/>
    public string ThreadName => _machine.Model switch
    {
        PetModel.Pet2001 => "PET 2001 6502",
        PetModel.Pet2001Basic2 => "PET 2001 (BASIC 2) 6502",
        PetModel.Pet4032 => "PET 4032 6502",
        _ => "PET 4032 (business) 6502"
    };

    /// <inheritdoc/>
    public string Cpu => nameof(ProcessorVariant.Mos6502);

    /// <inheritdoc/>
    public InstructionSet InstructionSet => M6502Isa.Get(ProcessorVariant.Mos6502);

    /// <inheritdoc/>
    public ICharacterSet? CharacterSet => _machine.Video;

    /// <inheritdoc/>
    public DebugRegisters Registers => s_registers;

    /// <inheritdoc/>
    public ProcessorCycle LastCycle => _machine.LastCycle;

    /// <inheritdoc/>
    public DebugFrame Frame => M6502Frames.Of(_machine.Processor.Registers);

    /// <inheritdoc/>
    public int StackPointer => _machine.Processor.Registers.StackPointer;

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
    public bool IsTakingInterrupt => _machine.Processor.IsTakingInterrupt;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   S is a byte: the stack is page one.
    ///  </para>
    /// </remarks>
    public int StackMask => 0xFF;

    /// <inheritdoc/>
    public bool InInstruction => _machine.Processor.CurrentOpCode is not null;

    /// <inheritdoc/>
    public ulong CycleCount => _machine.Processor.CycleCount;

    /// <inheritdoc/>
    public int ClockHertz => PetTiming.CpuHertz;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   The machine runs as fast as it can while a Datasette plays or records, unless the launch asks not to.
    ///  </para>
    /// </remarks>
    public bool Accelerated => FastCassette
        && (_machine.Bus.Cassette1.Activity != DeviceActivity.Idle || _machine.Bus.Cassette2.Activity != DeviceActivity.Idle);

    /// <inheritdoc/>
    public IDebugCallStack CallStack => _calls;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   <c>$0800</c> is RAM on every PET, the 4K one included, above where a small BASIC program ends.
    ///  </para>
    /// </remarks>
    public int DefaultLoadAddress => 0x0800;

    /// <inheritdoc/>
    public Enum ProgramArea => PetMemoryArea.Ram;

    /// <inheritdoc/>
    public string ContractModel => "Pet";

    /// <inheritdoc/>
    public IReadOnlyList<string> UsedRegisters { get; } = ["A", "X", "Y"];

    /// <inheritdoc/>
    public (string Name, ushort Start, int Length) MemoryScope => ("Zero page", 0, 256);

    /// <inheritdoc/>
    public IReadOnlyDictionary<string, Func<JsonObject, JsonObject>> Requests { get; }

    /// <inheritdoc/>
    public IReadOnlyList<IDevice> Devices => _machine.Devices;

    /// <inheritdoc/>
    public byte Peek(ushort address) => _machine.Bus.Peek(address);

    /// <inheritdoc/>
    public Enum ReadArea(ushort address) => _machine.Bus.Area(address);

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   The stack pointer points into page one.
    ///  </para>
    /// </remarks>
    public int? PointsTo(IsaRegister register, long value) => register.Name == "S"
        ? 0x100 | (int)(value & 0xFF)
        : register.Bits >= 16 ? (int)(value & 0xFFFF) : null;

    /// <inheritdoc/>
    public bool StepCycle()
    {
        ProcessorRegisters before = _machine.Processor.Registers;
        bool wasBoundary = _machine.Processor.IsInstructionBoundary;
        _machine.StepCycle();
        ProcessorCycle cycle = _machine.LastCycle;
        if (cycle.IsOpcodeFetch && !cycle.IsStalled) { _returnedFromInterrupt = cycle.Value == RtiOpcode; }
        _calls.Observe(cycle, before, _machine.Processor.Registers, wasBoundary, _machine.Processor.IsInstructionBoundary);
        if (_machine.Processor.Status != ProcessorExecutionStatus.Running)
        {
            throw new InvalidOperationException($"CPU stopped: {_machine.Processor.Status}.");
        }

        return _machine.Processor.FetchedOpcode;
    }

    /// <inheritdoc/>
    public void RunCycles(int cycles)
    {
        for (int count = 0; count < cycles; count++) { _machine.StepCycle(); }
        _calls.Reset();
        _returnedFromInterrupt = false;
        if (_machine.Processor.Status != ProcessorExecutionStatus.Running)
        {
            throw new InvalidOperationException($"CPU stopped: {_machine.Processor.Status}.");
        }
    }

    /// <inheritdoc/>
    public (ushort Target, int Length)? CallAt(ushort address) =>
        Peek(address) == JsrOpcode ? ((ushort)(Peek((ushort)(address + 1)) | (Peek((ushort)(address + 2)) << 8)), 3) : null;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   On BASIC 2 and 4 a BRK enters the machine-language monitor, which saves the registers and shows them.
    ///  </para>
    /// </remarks>
    public string? Trap(ushort address) => Peek(address) == BrkOpcode ? $"BRK at ${address:X4}." : null;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   BASIC's CHRGET, which BASIC copies into page zero and runs there, counts as BASIC's: Step Into on SYS stops in
    ///   the machine code SYS calls, not in the CHRGET that fetches its address.
    ///  </para>
    /// </remarks>
    public bool InRom(ushort address) =>
        _machine.Bus.Area(address) is PetMemoryArea.Basic or PetMemoryArea.Editor or PetMemoryArea.Kernal or PetMemoryArea.OptionRom
            || InChrget(address);

    /// <inheritdoc/>
    /// <exception cref="ArgumentException">The address is not RAM.</exception>
    public void Poke(ushort address, byte value)
    {
        if (!CanPoke(address))
        {
            throw new ArgumentException($"${address:X4} is not RAM.");
        }

        _machine.Bus.Write(address, value);
    }

    /// <inheritdoc/>
    public bool CanPoke(ushort address) => _machine.Bus.Area(address) is PetMemoryArea.Ram or PetMemoryArea.VideoRam;

    /// <inheritdoc/>
    public void Load(int address, ReadOnlySpan<byte> bytes)
    {
        if (address is < 0 or > ushort.MaxValue || address + bytes.Length > 0x10000)
        {
            throw new ArgumentException("Program must fit in the address space.");
        }

        _machine.Bus.Load((ushort)address, bytes);
    }

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   Each of BASIC, the screen editor and the kernal debugs against its SDK source when the machine's ROM is that
    ///   source's build: BASIC against the selected native root or MACRO-10 overlay, including BASIC's end in the
    ///   editor's chip, and the editor and kernal against <c>Basic1/Editor1.asm</c> and <c>Kernal1.asm</c>, or
    ///   BASIC 2's or 4's.
    ///  </para>
    /// </remarks>
    public void AddSdkModules(DebugInfo debug, string? directory)
    {
        string sdk = SdkDirectory(directory);
        PetModel model = _machine.Model;
        if (!File.Exists(Path.Join(sdk, "Basic", PetSdkModules.BasicFile(model, BasicSource)))) { return; }

        Assembler.AssemblyResult basic = PetSdkModules.AssembleBasic(sdk, model, OriginalBasic, BasicSource);
        Assembler.AssemblyResult editor = PetSdkModules.AssembleEditor(sdk, model);
        if (Matches(PetSdkModules.BasicImage(basic, model).Span, PetSdkModules.BasicOrigin(model))
            && Matches(PetSdkModules.EditorImage(basic, editor, model), PetSdkModules.EditorOrigin))
        {
            debug.Add(new SourceMapModule(basic, PetMemoryArea.Basic, collapseSingleStatementMacros: true));
            debug.Add(new SourceMapModule(editor, PetMemoryArea.Editor));
            SetBasicSymbols(basic.SymbolsWithHistoricalNames);
        }

        Assembler.AssemblyResult kernal = PetSdkModules.AssembleKernal(sdk, model);
        if (Matches(kernal.Sections[0].Bytes.Span, PetSdkModules.KernalOrigin))
        {
            debug.Add(new SourceMapModule(kernal, PetMemoryArea.Kernal));
        }
    }

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   ASCII and the PET's own control codes, as <see cref="PetKeyboard.Type(byte)"/> takes them; a lowercase letter
    ///   types its key unshifted.
    ///  </para>
    /// </remarks>
    public bool Key(int code) => code is >= 0 and <= 0xFF && _machine.Keyboard.Type((byte)code);

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   The PET has no RESET key; this resets the 6502, the PIAs and the VIA, keeping RAM, as a reset switch on the
    ///   expansion port does. The kernal starts again from its reset vector.
    ///  </para>
    /// </remarks>
    public void Reset()
    {
        _machine.Reset();
        _resetPending = true;
    }

    /// <inheritdoc/>
    public bool TakeResetStop()
    {
        if (!_resetPending || !IsInstructionBoundary) { return false; }
        _resetPending = false;
        return true;
    }

    /// <inheritdoc/>
    public JsonObject? TakeAudio()
    {
        if (_sound is null) { return null; }
        _machine.Audio.Flush();
        return _sound.Take() is { } samples
            ? new JsonObject { ["rate"] = _sound.SampleRate, ["channels"] = _sound.Channels, ["samples"] = samples }
            : null;
    }

    /// <inheritdoc/>
    public IEnumerable<(string Event, JsonObject Body)> StatusEvents()
    {
        yield return ("retro/media", MediaState());
    }

    /// <inheritdoc/>
    public JsonObject DisplayState(bool running) => new JsonObject
    {
        ["machine"] = DebugMachines.Pet,
        ["model"] = ModelId(_machine.Model),
        ["columns"] = 40,
        ["rows"] = TextRows().ToJsonArray(),
        ["cycles"] = CycleCount,
        ["video"] = VideoState(),
        ["media"] = MediaState(),
        ["sound"] = _soundMode,
        ["screen"] = _screen,
        ["screens"] = Screens.ToJsonArray(),
        ["running"] = running
    };

    /// <inheritdoc/>
    public IReadOnlyList<string> Screens => DebugScreens.Monochrome;

    /// <inheritdoc/>
    public string Screen
    {
        get => _screen;
        set => _screen = DebugScreens.Require(value, Screens);
    }

    /// <inheritdoc/>
    public ReadOnlySpan<byte> RenderVideo()
    {
        _machine.Video.Render(_pixels, scanned: true);
        DebugScreens.Show(_pixels, _screen);
        return _pixels;
    }

    /// <inheritdoc/>
    public IReadOnlyList<HardwareRow> Hardware()
    {
        PetMachine machine = _machine;
        int ram = machine.Bus.Ram.Length / 1024;
        return
        [
            new("model", "Model", ModelName(machine.Model), "The launch's model: pet2001, pet2001-basic2, pet4032 or pet4032-business."),
            new("cpu", "Processor", "6502 at 1 MHz", "The board's processor, with the kernal's reset vector at $FFFC."),
            new("rom", "ROM", RomText(), "The dumps in romDirectory or RETROCORE_PET_ROMS, under MAME's names; without them, built from the SDK's sources."),
            new("memory", "Memory", $"{ram} KB at $0000, 1 KB of video RAM at $8000", "The launch's ramKilobytes option: 4, 8, 16 or 32; 16 is the 4016."),
            new(
                "video",
                "Video",
                machine.Video.Snow ? "40x25 text, with snow" : "40x25 text",
                "The launch's snow option: a CPU access to video RAM while a line is drawn shows as snow, as on the 2001's board."),
            new("sound", "Sound", _soundMode == "off" ? "off" : "CB2 speaker", "The launch's sound option: the VIA's CB2, as a speaker on the user port plays it."),
            new("cassette1", "Cassette #1", "C2N Datasette", "The built-in Datasette on cassette port 1.", [machine.Bus.Cassette1.Id]),
            new("cassette2", "Cassette #2", "C2N Datasette", "A Datasette on cassette port 2.", [machine.Bus.Cassette2.Id]),
            .. DiskRows()
        ];
    }

    /// <summary>
    ///  Gets the launch configuration's <c>model</c> for a model.
    /// </summary>
    /// <param name="model">The model.</param>
    /// <returns><c>pet2001</c>, <c>pet2001-basic2</c>, <c>pet4032</c> or <c>pet4032-business</c>.</returns>
    internal static string ModelId(PetModel model) => model switch
    {
        PetModel.Pet2001 => "pet2001",
        PetModel.Pet2001Basic2 => "pet2001-basic2",
        PetModel.Pet4032 => "pet4032",
        _ => "pet4032-business"
    };

    /// <summary>
    ///  Gets a model's name, as the Machine view and the thread show it.
    /// </summary>
    /// <param name="model">The model.</param>
    /// <returns>The name.</returns>
    internal static string ModelName(PetModel model) => model switch
    {
        PetModel.Pet2001 => "PET 2001",
        PetModel.Pet2001Basic2 => "PET 2001 with BASIC 2",
        PetModel.Pet4032 => "PET 4032",
        _ => "PET 4032 with the business keyboard"
    };

    /// <summary>
    ///  Gets the directory of the PET's ROM sources: a directory that holds them, or its <c>Pet</c> folder.
    /// </summary>
    /// <param name="directory">The SDK ROM directory, or null for the copy beside the debug host.</param>
    /// <returns>The directory.</returns>
    internal static string SdkDirectory(string? directory)
    {
        string root = directory ?? SdkModules.RomDirectory;
        return File.Exists(Path.Join(root, "PetEquates.asm")) ? root : Path.Join(root, "Pet");
    }

    // Whether the machine's ROM at an address holds a build's bytes.
    private bool Matches(ReadOnlySpan<byte> image, int origin)
    {
        for (int i = 0; i < image.Length; i++)
        {
            if (_machine.Bus.Peek((ushort)(origin + i)) != image[i]) { return false; }
        }

        return true;
    }

    private string RomText()
    {
        string basic = _machine.Model.BasicVersion() switch
        {
            1 => OriginalBasic ? "BASIC 1, original" : "BASIC 1, revised",
            2 => "BASIC 2",
            _ => OriginalBasic ? "BASIC 4, original" : "BASIC 4, revised"
        };

        return basic + (SdkRoms ? ", from the SDK's sources" : "");
    }

    // The screen as text, each code as the character set shows it, graphics as spaces.
    private string[] TextRows()
    {
        ICharacterSet characters = _machine.Video;
        string[] rows = new string[25];
        Span<char> line = stackalloc char[40];
        for (int row = 0; row < rows.Length; row++)
        {
            for (int column = 0; column < 40; column++)
            {
                char character = characters.Character(_machine.Bus.VideoRam[(row * 40) + column]);
                line[column] = character == '\0' ? ' ' : character;
            }

            rows[row] = new string(line);
        }

        return rows;
    }

    // off attaches no sink; speaker plays the VIA's CB2.
    private void SetSound(string mode)
    {
        PetAudio audio = _machine.Audio;
        _sound = mode switch
        {
            "off" => null,
            "speaker" => new DebugAudioSink(channels: 1, audio.SampleRate),
            _ => throw new ArgumentException("sound must be off or speaker.")
        };

        audio.Sink = _sound;
        _soundMode = mode;
    }

    private JsonObject VideoState() => new JsonObject
    {
        ["width"] = _machine.Video.Width,
        ["height"] = _machine.Video.Height,
        ["pixelFormat"] = "rgba",
        ["cycles"] = CycleCount
    };

    private JsonObject VideoFrame(bool scanned)
    {
        _machine.Video.Render(_pixels, scanned);
        DebugScreens.Show(_pixels, _screen);
        JsonObject frame = VideoState();
        frame["pixels"] = Convert.ToBase64String(_pixels);
        return frame;
    }
}
