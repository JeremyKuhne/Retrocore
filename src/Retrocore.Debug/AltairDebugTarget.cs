// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.Json.Nodes;
using Retrocore.Cpu.I8080;
using Retrocore.Isa;
using Retrocore.Machines.Altair;
using Retrocore.Machines.Devices;

namespace Retrocore.Debug;

/// <summary>
///  An MITS Altair 8800 under the debugger: the 8080, RAM, and the terminal on the 88-2SIO.
/// </summary>
/// <remarks>
///  <para>
///   The Altair has no ROM, so a launch with no <c>source</c> or <c>program</c> starts at address 0 in empty RAM. Its
///   options are <c>ramKilobytes</c> (1-64, default 64), <c>switches</c> (the front panel's 16 switches, whose high 8
///   are the sense switches) and <c>baudRate</c> (the 88-2SIO's, default 9600).
///  </para>
/// </remarks>
internal sealed class AltairDebugTarget : IDebugTarget
{
    private static readonly DebugRegisters s_registers = new(I8080Isa.Description);

    private readonly AltairMachine _machine;
    private readonly I8080CallStack _calls;
    private readonly byte[] _pixels;

    // The ADM-3A's phosphor was white; a monitor of another phosphor shows it in that color.
    private string _screen = DebugScreens.White;
    private DebugFrame _beforeInstruction;
    private bool _instruction;

    // Whether the instruction in progress began with an interrupt acknowledge, rather than an opcode fetch, and whether
    // it fetched anything at all: a halted 8080's idle states fetch nothing and are not instructions.
    private bool _interrupt;
    private bool _fetched;
    private bool _resetPending;
    private string? _recordingPath;

    /// <summary>
    ///  Wraps a machine.
    /// </summary>
    /// <param name="machine">The machine.</param>
    internal AltairDebugTarget(AltairMachine machine)
    {
        _machine = machine;
        _calls = new(this, is8085: false);
        _pixels = new byte[machine.Terminal.Width * machine.Terminal.Height * 4];
        Requests = new Dictionary<string, Func<JsonObject, JsonObject>>
        {
            ["retro/video"] = _ => VideoFrame(),
            ["retro/media"] = Media,
            ["altair/clearScreen"] = _ =>
            {
                _machine.Terminal.ClearScreen();
                return [];
            }
        };
    }

    /// <summary>
    ///  Builds a target from a launch configuration.
    /// </summary>
    /// <param name="args">The launch arguments.</param>
    /// <returns>The target.</returns>
    internal static AltairDebugTarget Launch(JsonObject args)
    {
        AltairConfiguration configuration = new()
        {
            RamKilobytes = args.Int("ramKilobytes") ?? 64,
            Switches = checked((ushort)(args.Int("switches") ?? 0)),
            BaudRate = args.Int("baudRate") ?? 9600,
            Console = (args.String("console") ?? "2sio") switch
            {
                "2sio" => AltairConsole.Serial2Sio,
                "sio" => AltairConsole.Sio,
                _ => throw new ArgumentException("console must be 2sio or sio.")
            },
            CassetteInterface = args.Bool("cassetteInterface") ?? true,
            UpperCase = args.Bool("upperCase") ?? false
        };

        AltairDebugTarget target = new(new AltairMachine(configuration))
        {
            FastCassette = args.Bool("fastCassette") ?? true
        };

        if (args.String("cassette") is { } tape)
        {
            if (target._machine.Bus.Cassette is null)
            {
                throw new ArgumentException("A cassette needs the 88-ACR cassette interface.");
            }

            target.Insert(tape);
        }

        return target;
    }

    /// <summary>
    ///  Gets or sets whether the machine runs as fast as it can while the cassette plays or records.
    /// </summary>
    internal bool FastCassette { get; set; } = true;

    /// <summary>
    ///  Gets the machine.
    /// </summary>
    internal AltairMachine Machine => _machine;

    /// <inheritdoc/>
    public string ThreadName => "Altair 8080";

    /// <inheritdoc/>
    public string Cpu => I8080Isa.Name;

    /// <inheritdoc/>
    public InstructionSet InstructionSet => I8080Isa.InstructionSet;

    /// <inheritdoc/>
    public bool HasPorts => true;

    /// <inheritdoc/>
    public DebugRegisters Registers => s_registers;

    /// <inheritdoc/>
    public ProcessorCycle LastCycle => _machine.LastCycle;

    /// <inheritdoc/>
    public DebugFrame Frame => FrameOf(_machine.Processor.Registers);

    /// <inheritdoc/>
    public ushort ProgramCounter
    {
        get => _machine.Processor.Registers.PC;
        set => _machine.Processor.Registers = _machine.Processor.Registers with { PC = value };
    }

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   A halted 8080 is between instructions in each idle state, with PC past its HLT; it is not at a boundary for the
    ///   debugger until an interrupt or reset sends it on, so breakpoints and steps wait for that.
    ///  </para>
    /// </remarks>
    public bool IsInstructionBoundary => _machine.Processor.IsInstructionBoundary && !IsIdle;

    /// <inheritdoc/>
    public bool InInstruction => _instruction;

    /// <inheritdoc/>
    public bool IsIdle => _machine.Processor.IsHalted;

    /// <inheritdoc/>
    public ulong CycleCount => _machine.Processor.CycleCount;

    /// <inheritdoc/>
    public int ClockHertz => AltairTiming.ClockHertz;

    /// <inheritdoc/>
    public bool Accelerated =>
        FastCassette && _machine.Bus.Cassette?.Activity is DeviceActivity.Reading or DeviceActivity.Writing;

    /// <inheritdoc/>
    public IDebugCallStack CallStack => _calls;

    /// <inheritdoc/>
    public int DefaultLoadAddress => 0x0100;

    /// <inheritdoc/>
    public Enum ProgramArea => AltairMemoryArea.Ram;

    /// <inheritdoc/>
    public string ContractModel => "Altair";

    /// <inheritdoc/>
    public IReadOnlyList<string> UsedRegisters { get; } = ["A", "B", "C", "D", "E", "H", "L"];

    /// <inheritdoc/>
    public (string Name, ushort Start, int Length) MemoryScope => ("Page zero", 0x0000, 256);

    /// <inheritdoc/>
    public IReadOnlyDictionary<string, Func<JsonObject, JsonObject>> Requests { get; }

    /// <inheritdoc/>
    public IReadOnlyList<IDevice> Devices => _machine.Devices;

    /// <inheritdoc/>
    public IReadOnlyList<string> Screens => DebugScreens.Monochrome;

    /// <inheritdoc/>
    public string Screen
    {
        get => _screen;
        set => _screen = DebugScreens.Require(value, Screens);
    }

    /// <summary>
    ///  Builds a debugger frame from the 8080's registers, in the order the instruction-set description lists them.
    /// </summary>
    /// <param name="registers">The registers.</param>
    /// <returns>The frame.</returns>
    internal static DebugFrame FrameOf(I8080Registers registers)
    {
        DebugFrame frame = new()
        {
            ProgramCounter = registers.PC,
            StackPointer = registers.SP
        };

        ReadOnlySpan<ushort> values =
        [
            registers.A, registers.F, registers.B, registers.C, registers.D, registers.E, registers.H, registers.L,
            registers.BC, registers.DE, registers.HL, registers.PSW, registers.SP, registers.PC
        ];

        for (int index = 0; index < values.Length; index++) { frame[index] = values[index]; }
        return frame;
    }

    /// <inheritdoc/>
    public byte Peek(ushort address) => _machine.Bus.Peek(address);

    /// <inheritdoc/>
    public Enum ReadArea(ushort address) => _machine.Bus.Area(address);

    /// <inheritdoc/>
    public int? PointsTo(IsaRegister register, long value) =>
        register.Bits >= 16 && register.Name != "PSW" ? (int)(value & 0xFFFF) : null;

    /// <inheritdoc/>
    public bool StepCycle()
    {
        if (_machine.Processor.IsInstructionBoundary && !_instruction)
        {
            _beforeInstruction = Frame;
            _instruction = true;
            _interrupt = false;
            _fetched = false;
        }

        _machine.StepCycle();
        _fetched |= _machine.Processor.FetchedOpcode;
        _interrupt |= _machine.LastCycle.Operation == BusOperation.InterruptAcknowledge;
        if (_machine.Processor.IsInstructionBoundary && _instruction)
        {
            _instruction = false;
            if (_fetched) { _calls.Complete(_beforeInstruction, Frame, _interrupt); }
        }

        return _machine.Processor.FetchedOpcode;
    }

    /// <inheritdoc/>
    public (ushort Target, int Length)? CallAt(ushort address)
    {
        byte opcode = Peek(address);
        return I8080CallStack.CallLength(opcode, is8085: false) switch
        {
            3 => ((ushort)(Peek((ushort)(address + 1)) | (Peek((ushort)(address + 2)) << 8)), 3),
            1 => ((ushort)(opcode & 0x38), 1),
            _ => null
        };
    }

    /// <inheritdoc/>
    public string? Trap(ushort address) => null;

    /// <inheritdoc/>
    public void Poke(ushort address, byte value)
    {
        if (_machine.Bus.Area(address) != AltairMemoryArea.Ram)
        {
            throw new ArgumentException($"${address:X4} is not RAM.");
        }

        _machine.Bus.Write(address, value);
    }

    /// <inheritdoc/>
    public void Load(int address, ReadOnlySpan<byte> bytes)
    {
        for (int index = 0; index < bytes.Length; index++)
        {
            if (address + index > 0xFFFF || _machine.Bus.Area((ushort)(address + index)) != AltairMemoryArea.Ram)
            {
                throw new ArgumentException($"Program must fit in RAM; ${address + index:X4} is not RAM.");
            }
        }

        for (int index = 0; index < bytes.Length; index++)
        {
            _machine.Bus.Write((ushort)(address + index), bytes[index]);
        }
    }

    /// <inheritdoc/>
    public void AddSdkModules(DebugInfo debug, string? directory)
    {
        // The Altair has no ROM; its boot PROMs become SDK sources with the disk controller.
    }

    /// <inheritdoc/>
    public bool Key(int code)
    {
        _machine.Terminal.Type((byte)code);
        return true;
    }

    /// <inheritdoc/>
    public void Reset()
    {
        _machine.Reset();
        _calls.Reset();
        _instruction = false;
        _resetPending = true;
    }

    /// <inheritdoc/>
    public bool TakeResetStop()
    {
        if (!_resetPending || !IsInstructionBoundary || _machine.Processor.Registers.PC != 0)
        {
            return false;
        }

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
        AltairTerminal terminal = _machine.Terminal;
        string[] rows = new string[AltairTerminal.Rows];
        for (int row = 0; row < rows.Length; row++) { rows[row] = terminal.Line(row); }
        return new JsonObject
        {
            ["machine"] = DebugMachines.Altair,
            ["columns"] = AltairTerminal.Columns,
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
    public ReadOnlySpan<byte> RenderVideo()
    {
        _machine.Terminal.Render(_pixels, scanned: true);
        DebugScreens.Show(_pixels, _screen);
        return _pixels;
    }

    /// <inheritdoc/>
    public IReadOnlyList<HardwareRow> Hardware()
    {
        AltairConfiguration configuration = _machine.Configuration;
        return
        [
            new("model", "Altair 8800", "8080 at 2 MHz", "MITS's S-100 computer; it has no ROM, so it starts at $0000 in RAM."),
            new("memory", "Memory", $"{configuration.RamKilobytes} KB at $0000", "The launch's ramKilobytes option: 1 to 64."),
            new(
                "serial",
                "88-2SIO",
                $"Two MC6850 ACIAs at ports $10 and $12, {configuration.BaudRate} baud",
                configuration.Console == AltairConsole.Sio
                    ? "Nothing is connected; the terminal is on the 88-SIO. The launch's baudRate option sets both ports."
                    : "The terminal is on the first port; the second has nothing connected. The launch's baudRate option sets both."),
            .. Sio(configuration),
            new(
                "cassette",
                "88-ACR",
                configuration.CassetteInterface ? "Cassette interface at ports $06 and $07, 300 baud" : "none",
                "The launch's cassetteInterface option: an 88-SIO with a modem for a cassette recorder; cassette loads a tape.",
                _machine.Bus.Cassette is { } drive ? [drive.Id] : null),
            new(
                "terminal",
                "Terminal",
                configuration.UpperCase ? "80x24, ADM-3A controls, caps lock" : "80x24, ADM-3A controls",
                "A glass teletype: ^H ^J ^K ^L move the cursor, ^Z clears, ESC = row column places it."),
            new(
                "panel",
                "Front panel",
                $"Switches ${_machine.FrontPanel.Switches:X4}",
                "The launch's switches option; IN $FF reads the high 8, the sense switches.")
        ];
    }

    /// <inheritdoc/>
    public void DeviceAction(IDevice device, string action, JsonObject args)
    {
        string? path = args.String("path");
        switch (device, action)
        {
            case (AltairCassette, "insert"):
                Insert(path ?? throw new ArgumentException("path is required."));
                break;
            case (AltairCassette cassette, "record"):
                EjectCassette();
                string full = Path.GetFullPath(
                    path ?? throw new ArgumentException("path is required, for saving the recording."));

                cassette.Record(full);
                _recordingPath = full;
                break;
            case (AltairCassette, "eject"):
                EjectCassette();
                break;
            default:
                throw new ArgumentException($"{device.Info.Name} does not support {action}.");
        }
    }

    // The 88-SIO's row, when the terminal is on it.
    private static HardwareRow[] Sio(AltairConfiguration configuration) => configuration.Console == AltairConsole.Sio
        ?
        [
            new(
                "sio",
                "88-SIO",
                $"Ports $00 and $01, {configuration.BaudRate} baud",
                "The launch's console option: the terminal is on the 88-SIO.")
        ]
        : [];

    // retro/media: inserts, records and ejects cassettes.
    private JsonObject Media(JsonObject args)
    {
        string action = args.String("action") ?? throw new ArgumentException("action is required.");
        if ((args.String("device") ?? "cassette") != "cassette" || _machine.Bus.Cassette is not { } drive)
        {
            throw new ArgumentException("The Altair's only media is the 88-ACR's cassette.");
        }

        DeviceAction(drive, action, args);
        return MediaState();
    }

    private void Insert(string path)
    {
        EjectCassette();
        string full = Path.GetFullPath(path);
        AltairCassette drive = _machine.Bus.Cassette
            ?? throw new InvalidOperationException("This Altair has no 88-ACR.");

        drive.Play(File.ReadAllBytes(full), full);
    }

    // A recording is saved to its path when it is ejected.
    private void EjectCassette()
    {
        // Saved before it comes out, so a recording that cannot be written stays in to be ejected again.
        if (_recordingPath is { } path && _machine.Bus.Cassette is { Media: not null } cassette)
        {
            File.WriteAllBytes(path, cassette.Tape);
        }

        _machine.Bus.Cassette?.Eject();
        _recordingPath = null;
    }

    private JsonObject MediaState()
    {
        if (_machine.Bus.Cassette is not { } drive) { return new JsonObject { ["cassette"] = null }; }
        JsonObject cassette = new()
        {
            ["path"] = drive.Media?.Label,
            ["recording"] = _recordingPath is not null,
            ["motor"] = drive.Transport.Motor,
            ["atEnd"] = drive.AtEnd
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
        RenderVideo();
        return new JsonObject
        {
            ["width"] = _machine.Terminal.Width,
            ["height"] = _machine.Terminal.Height,
            ["pixelFormat"] = "rgba",
            ["pixels"] = Convert.ToBase64String(_pixels),
            ["cycles"] = CycleCount
        };
    }
}
