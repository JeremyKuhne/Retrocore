// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.Json.Nodes;
using Retrocore.Isa;
using Retrocore.Machines.Apple1;
using Retrocore.Machines.Devices;

namespace Retrocore.Debug;

/// <summary>
///  The Apple-1 as the debugger sees it: a 6502, the Apple-1's memory areas, its 40x24 terminal, keyboard and
///  cassette interface.
/// </summary>
internal sealed class Apple1DebugTarget : IDebugTarget
{
    private const byte JsrOpcode = 0x20;
    private const byte BrkOpcode = 0x00;
    private const string MonitorDump = "wozmon.bin";
    private const string CassetteDump = "aci.bin";

    private static readonly DebugRegisters s_registers = new(M6502Isa.Description);

    private readonly Apple1Machine _machine;
    private readonly DebugCallStack _calls;
    private readonly byte[] _pixels;

    // The terminal is white on black; a monitor of another phosphor shows it in that color.
    private string _screen = DebugScreens.Green;
    private bool _resetPending;

    // The path a recording is saved to when its tape is ejected.
    private string? _recordingPath;

    /// <summary>
    ///  Creates the target for a launched Apple-1.
    /// </summary>
    /// <param name="machine">The machine.</param>
    internal Apple1DebugTarget(Apple1Machine machine)
    {
        _machine = machine;
        _calls = new(machine.Bus.Peek);
        _pixels = new byte[machine.Terminal.Width * machine.Terminal.Height * 4];
        Requests = new Dictionary<string, Func<JsonObject, JsonObject>>
        {
            ["retro/media"] = Media,
            ["retro/video"] = _ => VideoFrame(),
            ["apple1/clearScreen"] = _ =>
            {
                _machine.ClearScreen();
                return [];
            }
        };
    }

    /// <summary>
    ///  Launches an Apple-1 from a launch request's arguments.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   The Monitor and the cassette interface's PROM are the dumps in <c>romDirectory</c> (or
    ///   <c>RETROCORE_APPLE1_ROMS</c>), <c>wozmon.bin</c> and <c>aci.bin</c>, where they are there, and are otherwise
    ///   assembled from the SDK's sources. The character generator always comes from the SDK, as no dump of the 2513
    ///   is published.
    ///  </para>
    /// </remarks>
    /// <param name="args">The arguments.</param>
    /// <returns>The target, its 6502 through the reset sequence and at the Monitor's first instruction.</returns>
    /// <exception cref="ArgumentException">An argument is invalid.</exception>
    internal static Apple1DebugTarget Launch(JsonObject args)
    {
        Apple1Configuration configuration = new()
        {
            RamKilobytes = args.Int("ramKilobytes") ?? 4,
            HighRam = args.Bool("highRam") ?? true,
            CassetteInterface = args.Bool("cassetteInterface") ?? true
        };

        string? dumps = args.String("romDirectory") ?? Environment.GetEnvironmentVariable("RETROCORE_APPLE1_ROMS");
        string sdk = SdkDirectory(args.String("sdkRoms") is { } roms ? Path.GetFullPath(roms) : null);
        byte[] monitor = Rom(dumps, MonitorDump, Apple1Roms.MonitorSize)
            ?? Image(Apple1SdkModules.AssembleMonitor(Path.Join(sdk, "WozMonitor.asm")));

        byte[] characters = Image(Apple1SdkModules.AssembleCharacterGenerator(Path.Join(sdk, "CharacterGenerator.asm")));
        byte[] cassette = !configuration.CassetteInterface
            ? []
            : Rom(dumps, CassetteDump, Apple1Roms.CassetteSize)
                ?? Image(Apple1SdkModules.AssembleCassette(Path.Join(sdk, "Aci.asm")));

        Apple1Machine machine = new(configuration, new(monitor, characters, cassette));

        // Power-up's reset sequence takes seven cycles, after which the Monitor's first instruction is next.
        machine.Run(7);
        Apple1DebugTarget target = new(machine) { FastCassette = args.Bool("fastCassette") ?? true };
        if (args.String("cassette") is { } tape)
        {
            if (machine.CassetteDrive is null)
            {
                throw new ArgumentException("A cassette needs the cassette interface.");
            }

            target.Insert(tape);
        }

        return target;
    }

    /// <summary>
    ///  Runs the machine in emulated time, before a program loads, so the Monitor sets up the PIA for the program's
    ///  calls to ECHO.
    /// </summary>
    /// <param name="seconds">The emulated seconds.</param>
    internal void Boot(double seconds)
    {
        _machine.Run((ulong)(seconds * Apple1Timing.ClockHertz));
        while (!_machine.Processor.IsInstructionBoundary) { _machine.StepCycle(); }
    }

    /// <summary>
    ///  Gets the directory of the Apple-1 ROM sources: a directory that holds them, or its <c>Apple1</c> folder.
    /// </summary>
    /// <param name="directory">The SDK ROM directory, or null for the copy beside the debug host.</param>
    /// <returns>The directory.</returns>
    internal static string SdkDirectory(string? directory)
    {
        string root = directory ?? SdkModules.RomDirectory;
        return File.Exists(Path.Join(root, "WozMonitor.asm")) ? root : Path.Join(root, "Apple1");
    }

    /// <summary>
    ///  Gets the machine.
    /// </summary>
    internal Apple1Machine Machine => _machine;

    /// <summary>
    ///  Gets or sets whether running outpaces the clock while a tape plays or records.
    /// </summary>
    internal bool FastCassette { get; set; } = true;

    /// <inheritdoc/>
    public string ThreadName => "Apple-1 CPU";

    /// <inheritdoc/>
    public string Cpu => nameof(ProcessorVariant.Mos6502);

    /// <inheritdoc/>
    public InstructionSet InstructionSet => M6502Isa.Get(ProcessorVariant.Mos6502);

    /// <inheritdoc/>
    public DebugRegisters Registers => s_registers;

    /// <inheritdoc/>
    public ProcessorCycle LastCycle => _machine.LastCycle;

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
    public ulong CycleCount => _machine.Processor.CycleCount;

    /// <inheritdoc/>
    public int ClockHertz => Apple1Timing.ClockHertz;

    /// <inheritdoc/>
    /// <remarks>
    ///  The machine runs as fast as it can while a tape plays or records, unless the launch asks not to.
    /// </remarks>
    public bool Accelerated => FastCassette && _machine.CassetteDrive?.Activity is DeviceActivity.Reading or DeviceActivity.Writing;

    /// <inheritdoc/>
    public IDebugCallStack CallStack => _calls;

    /// <inheritdoc/>
    public int DefaultLoadAddress => 0x0300;

    /// <inheritdoc/>
    public Enum ProgramArea => Apple1MemoryArea.Ram;

    /// <inheritdoc/>
    public string ContractModel => "Apple1";

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
        _calls.Observe(_machine.LastCycle, before, _machine.Processor.Registers, wasBoundary, _machine.Processor.IsInstructionBoundary);
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
    public string? Trap(ushort address) => Peek(address) == BrkOpcode ? $"BRK at ${address:X4}." : null;

    /// <inheritdoc/>
    public bool InRom(ushort address) =>
        _machine.Bus.Area(address) is Apple1MemoryArea.Monitor or Apple1MemoryArea.CassetteRom;

    /// <inheritdoc/>
    /// <exception cref="ArgumentException">The address is not RAM.</exception>
    public void Poke(ushort address, byte value)
    {
        if (_machine.Bus.Area(address) != Apple1MemoryArea.Ram)
        {
            throw new ArgumentException($"${address:X4} is not RAM.");
        }

        _machine.Bus.Write(address, value);
    }

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
    public void AddSdkModules(DebugInfo debug, string? directory)
    {
        string roms = SdkDirectory(directory);
        string monitor = Path.Join(roms, "WozMonitor.asm");
        if (File.Exists(monitor))
        {
            debug.Add(new SourceMapModule(Apple1SdkModules.AssembleMonitor(monitor), Apple1MemoryArea.Monitor));
        }

        string cassette = Path.Join(roms, "Aci.asm");
        if (_machine.Configuration.CassetteInterface && File.Exists(cassette))
        {
            debug.Add(new SourceMapModule(Apple1SdkModules.AssembleCassette(cassette), Apple1MemoryArea.CassetteRom));
        }
    }

    /// <inheritdoc/>
    public bool Key(int code)
    {
        // The keyboard has every ASCII key, but no lowercase: a lowercase letter types its capital.
        _machine.Keyboard.Type((byte)code);
        return true;
    }

    /// <inheritdoc/>
    public void Reset()
    {
        _machine.Reset();
        _resetPending = true;
    }

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   The reset sequence is not at an instruction boundary, so the first boundary after it is the Monitor's first
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
    public IEnumerable<(string Event, JsonObject Body)> StatusEvents()
    {
        yield return ("retro/media", MediaState());
    }

    /// <inheritdoc/>
    public JsonObject DisplayState(bool running)
    {
        Apple1Terminal terminal = _machine.Terminal;
        string[] rows = new string[Apple1Terminal.Rows];
        for (int row = 0; row < rows.Length; row++) { rows[row] = terminal.Line(row); }
        return new JsonObject
        {
            ["machine"] = DebugMachines.Apple1,
            ["columns"] = Apple1Terminal.Columns,
            ["rows"] = rows.ToJsonArray(),
            ["cursor"] = new JsonObject { ["row"] = terminal.CursorRow, ["column"] = terminal.CursorColumn },
            ["cycles"] = CycleCount,
            ["video"] = VideoState(),
            ["media"] = MediaState(),
            ["screen"] = _screen,
            ["screens"] = Screens.ToJsonArray(),
            ["running"] = running
        };
    }

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
        _machine.Terminal.Render(_pixels, scanned: true);
        DebugScreens.Show(_pixels, _screen);
        return _pixels;
    }

    /// <inheritdoc/>
    public IReadOnlyList<HardwareRow> Hardware()
    {
        Apple1Configuration configuration = _machine.Configuration;
        string memory = configuration.HighRam
            ? $"{configuration.RamKilobytes} KB at $0000, 4 KB at $E000"
            : $"{configuration.RamKilobytes} KB at $0000";

        return
        [
            new("model", "Apple-1", "6502 at 1.023 MHz", "The board's processor, with the Monitor at $FF00."),
            new(
                "memory",
                "Memory",
                memory,
                "The launch's ramKilobytes (4 or 8) and highRam options; BASIC loads and runs at $E000."),
            new(
                "terminal",
                "Terminal",
                "40x24, Signetics 2513",
                "The video terminal on the PIA's port B: about 60 characters a second, uppercase only."),
            new(
                "cassette",
                "Cassette interface",
                configuration.CassetteInterface ? "Apple Cassette Interface" : "none",
                "The launch's cassetteInterface option: the ACI in the expansion slot, started with C100R.",
                _machine.CassetteDrive is { } drive ? [drive.Id] : null)
        ];
    }

    /// <inheritdoc/>
    public void DeviceAction(IDevice device, string action, JsonObject args)
    {
        string? path = args.String("path");
        switch (device, action)
        {
            case (Apple1CassetteDrive, "insert"):
                Insert(path ?? throw new ArgumentException("path is required."));
                break;
            case (Apple1CassetteDrive cassette, "record"):
                EjectCassette();
                string full = Path.GetFullPath(path ?? throw new ArgumentException("path is required, for saving the recording."));
                cassette.Record(new Apple1Tape(), full);
                _recordingPath = full;
                break;
            case (Apple1CassetteDrive, "eject"):
                EjectCassette();
                break;
            default:
                throw new ArgumentException($"{device.Info.Name} does not support {action}.");
        }
    }

    private static byte[]? Rom(string? directory, string name, int size)
    {
        if (directory is null || !File.Exists(Path.Join(directory, name))) { return null; }
        byte[] rom = File.ReadAllBytes(Path.Join(directory, name));
        return rom.Length == size ? rom : throw new ArgumentException($"{name} must be {size} bytes.");
    }

    private static byte[] Image(Assembler.AssemblyResult result) => result.Sections[0].Bytes.ToArray();

    // retro/media: inserts, records and ejects cassettes.
    private JsonObject Media(JsonObject args)
    {
        string action = args.String("action") ?? throw new ArgumentException("action is required.");
        if ((args.String("device") ?? "cassette") != "cassette" || _machine.CassetteDrive is not { } drive)
        {
            throw new ArgumentException("The Apple-1's only media is the cassette interface's tape.");
        }

        DeviceAction(drive, action, args);
        return MediaState();
    }

    private void Insert(string path)
    {
        EjectCassette();
        string full = Path.GetFullPath(path);
        Apple1CassetteDrive drive = _machine.CassetteDrive
            ?? throw new InvalidOperationException("This Apple-1 has no cassette interface.");

        drive.Play(Apple1Tape.FromWave(File.ReadAllBytes(full)), full);
    }

    // A recording is saved to its path when it is ejected.
    private void EjectCassette()
    {
        // Saved before it comes out, so a recording that cannot be written stays in to be ejected again.
        if (_recordingPath is { } path && _machine.CassetteDrive?.Tape is { } tape)
        {
            File.WriteAllBytes(path, tape.ToWave());
        }

        _machine.CassetteDrive?.Eject();
        _recordingPath = null;
    }

    private JsonObject MediaState()
    {
        if (_machine.CassetteDrive is not { } drive) { return new JsonObject { ["cassette"] = null }; }
        JsonObject cassette = new()
        {
            ["path"] = drive.Media?.Label,
            ["recording"] = _recordingPath is not null,
            ["motor"] = drive.Transport.Motor,
            ["atEnd"] = _machine.Bus.Cassette?.AtEnd ?? true
        };

        return new JsonObject { ["cassette"] = cassette };
    }

    private JsonObject VideoState() => new JsonObject
    {
        ["width"] = _machine.Terminal.Width,
        ["height"] = _machine.Terminal.Height,
        ["pixelFormat"] = "rgba",
        ["cycles"] = CycleCount
    };

    private JsonObject VideoFrame()
    {
        JsonObject frame = VideoState();
        frame["pixels"] = Convert.ToBase64String(RenderVideo());
        return frame;
    }
}
