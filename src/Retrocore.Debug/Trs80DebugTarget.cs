// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.Json.Nodes;
using Retrocore.Assembler;
using Retrocore.Basic;
using Retrocore.Cpu.Z80;
using Retrocore.Isa;
using Retrocore.Machines.Trs80;

namespace Retrocore.Debug;

/// <summary>
///  The TRS-80 Model I as the debugger sees it: a Z80, the Model I's memory areas, its 64x16 display, keyboard,
///  cassette and disks.
/// </summary>
internal sealed partial class Trs80DebugTarget : IDebugTarget
{
    private static readonly DebugRegisters s_registers = new(Z80Isa.Description);

    private readonly Trs80Machine _machine;
    private readonly Z80CallStack _calls;
    private readonly int? _revision;
    private readonly byte[] _pixels;
    private DebugFrame _beforeInstruction;
    private bool _instruction;
    private BasicRom? _basicRom;

    // A reset button press whose handler has not yet started.
    private bool _resetPending;

    // Level II's stack and flags that its stack reset (STKINI) and READY use: the bottom of string space, the saved
    // stack for errors, the string temporaries, the last error, and the direct-mode line.
    private const ushort StackTop = 0x40A0;
    private const ushort SavedStack = 0x40E8;
    private const ushort TempPointer = 0x40B3;
    private const ushort FirstTemporary = 0x40B5;
    private const ushort ErrorCode = 0x409A;
    private const ushort CurrentLine = 0x40A2;
    private const ushort ErrorLine = 0x40F0;
    private const ushort InErrorHandler = 0x40F2;
    private const int ForEntrySize = 17;

    // Level II's two-letter error codes, by the code ERROR is given in E, halved.
    private static readonly string[] s_errors =
    [
        "NF", "SN", "RG", "OD", "FC", "OV", "OM", "UL", "BS", "DD", "/0", "ID", "TM", "OS", "LS", "ST", "CN", "NR",
        "RW", "UE", "MO", "FD", "L3"
    ];

    /// <summary>
    ///  Creates the target for a launched Model I.
    /// </summary>
    /// <param name="machine">The machine.</param>
    /// <param name="revision">The Level II revision, 12 or 13, or null for Level I or an unknown ROM.</param>
    internal Trs80DebugTarget(Trs80Machine machine, int? revision)
    {
        _machine = machine;
        _revision = revision;
        _calls = new(this);
        _pixels = new byte[machine.Bus.Video.Width * machine.Bus.Video.Height * 4];
        Requests = new Dictionary<string, Func<JsonObject, JsonObject>>
        {
            ["retro/media"] = Media,
            ["retro/video"] = args => VideoFrame(args.Bool("scanned") ?? true)
        };
    }

    /// <summary>
    ///  Gets the machine.
    /// </summary>
    internal Trs80Machine Machine => _machine;

    /// <inheritdoc/>
    public string ThreadName => "Model I Z80";

    /// <inheritdoc/>
    public string Cpu => "Z80";

    /// <inheritdoc/>
    public DebugRegisters Registers => s_registers;

    /// <inheritdoc/>
    public DebugFrame Frame => FrameOf(_machine.Processor.Registers);

    /// <inheritdoc/>
    public ushort ProgramCounter
    {
        get => _machine.Processor.Registers.PC;
        set
        {
            Z80Registers registers = _machine.Processor.Registers;
            registers.PC = value;
            _machine.Processor.Registers = registers;
        }
    }

    /// <inheritdoc/>
    public bool IsInstructionBoundary => _machine.Processor.IsInstructionBoundary;

    /// <inheritdoc/>
    public bool InInstruction => _instruction;

    /// <inheritdoc/>
    public ulong CycleCount => _machine.Processor.CycleCount;

    /// <inheritdoc/>
    public int ClockHertz => Trs80Timing.ClockHertz;

    /// <inheritdoc/>
    /// <remarks>
    ///  The machine runs as fast as it can while the cassette motor runs, unless the launch asks not to.
    /// </remarks>
    public bool Accelerated => FastCassette && _machine.Bus.Cassette.MotorOn;

    /// <summary>
    ///  Gets or sets whether running outpaces the clock while the cassette motor runs.
    /// </summary>
    internal bool FastCassette { get; set; } = true;

    /// <inheritdoc/>
    public IDebugCallStack CallStack => _calls;

    /// <inheritdoc/>
    public int DefaultLoadAddress => 0x7000;

    /// <inheritdoc/>
    public Enum ProgramArea => Trs80MemoryArea.Ram;

    /// <inheritdoc/>
    public string ContractModel => _machine.Configuration.Rom == Trs80Rom.Level1 ? "Level1" : "Level2";

    /// <inheritdoc/>
    public IReadOnlyList<string> UsedRegisters { get; } = ["A", "B", "C", "D", "E", "H", "L", "IX", "IY"];

    /// <inheritdoc/>
    public (string Name, ushort Start, int Length) MemoryScope => ("Communication region", 0x4000, 256);

    /// <inheritdoc/>
    public IReadOnlyDictionary<string, Func<JsonObject, JsonObject>> Requests { get; }

    /// <summary>
    ///  Copies a Z80's registers into a frame, in the instruction set's register order.
    /// </summary>
    /// <param name="registers">The registers.</param>
    /// <returns>The frame.</returns>
    internal static DebugFrame FrameOf(Z80Registers registers)
    {
        DebugFrame frame = new()
        {
            ProgramCounter = registers.PC,
            StackPointer = registers.SP
        };

        ReadOnlySpan<ushort> values =
        [
            registers.A, registers.F, registers.B, registers.C, registers.D, registers.E, registers.H, registers.L,
            registers.I, registers.R, registers.AF, registers.BC, registers.DE, registers.HL, registers.IX, registers.IY,
            registers.SP, registers.PC, registers.AlternateAF, registers.AlternateBC, registers.AlternateDE,
            registers.AlternateHL
        ];

        for (int index = 0; index < values.Length; index++) { frame[index] = values[index]; }
        return frame;
    }

    /// <inheritdoc/>
    public byte Peek(ushort address) => _machine.Bus.Peek(address);

    /// <inheritdoc/>
    public Enum ReadArea(ushort address) => _machine.Bus.Area(address);

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   AF holds the accumulator and flags, not an address.
    ///  </para>
    /// </remarks>
    public int? PointsTo(IsaRegister register, long value) =>
        register.Bits >= 16 && register.Name is not ("AF" or "AF'") ? (int)(value & 0xFFFF) : null;

    /// <inheritdoc/>
    public bool StepCycle()
    {
        if (_machine.Processor.IsInstructionBoundary)
        {
            _beforeInstruction = Frame;
            _instruction = true;
        }

        _machine.StepCycle();
        if (_machine.Processor.Status == ProcessorExecutionStatus.Stopped)
        {
            throw new InvalidOperationException("CPU stopped.");
        }

        if (_machine.Processor.IsInstructionBoundary && _instruction)
        {
            _instruction = false;
            _calls.Complete(_beforeInstruction, Frame);
        }

        return _machine.Processor.FetchedOpcode;
    }

    /// <inheritdoc/>
    public (ushort Target, int Length)? CallAt(ushort address)
    {
        byte opcode = Peek(address);
        return Z80CallStack.CallLength(opcode) switch
        {
            3 => ((ushort)(Peek((ushort)(address + 1)) | (Peek((ushort)(address + 2)) << 8)), 3),
            1 => ((ushort)(opcode & 0x38), 1),
            _ => null
        };
    }

    /// <inheritdoc/>
    public ProcessorCycle LastCycle => _machine.LastCycle;

    /// <inheritdoc/>
    public InstructionSet InstructionSet => Z80Isa.InstructionSet;

    /// <inheritdoc/>
    public bool HasPorts => true;

    /// <inheritdoc/>
    public bool Traps(ushort address) => false;

    /// <inheritdoc/>
    public void Poke(ushort address, byte value)
    {
        if (_machine.Bus.Area(address) is not (Trs80MemoryArea.Ram or Trs80MemoryArea.Video))
        {
            throw new ArgumentException($"${address:X4} is not RAM or video RAM.");
        }

        _machine.Bus.Write(address, value);
    }

    /// <inheritdoc/>
    public void Load(int address, ReadOnlySpan<byte> bytes)
    {
        int end = 0x4000 + (_machine.Configuration.RamKilobytes * 1024);
        if (address < 0x4000 || address > end || bytes.Length > end - address)
        {
            throw new ArgumentException($"Program must fit in RAM, $4000-${end - 1:X4}.");
        }

        for (int i = 0; i < bytes.Length; i++) { _machine.Bus.Write((ushort)(address + i), bytes[i]); }
    }

    /// <inheritdoc/>
    public void AddSdkModules(DebugInfo debug, string? directory)
    {
        string roms = SdkDirectory(directory);
        if (_machine.Configuration.Rom == Trs80Rom.Level1)
        {
            string level1 = Path.Join(roms, "Level1.asm");
            if (File.Exists(level1))
            {
                debug.Add(new SourceMapModule(Trs80SdkModules.AssembleLevel1(level1), Trs80MemoryArea.Rom));
            }

            return;
        }

        string level2 = Path.Join(roms, "Level2.asm");
        if (_revision is { } revision && File.Exists(level2))
        {
            AssemblyResult result = Trs80SdkModules.AssembleLevel2(level2, revision);
            debug.Add(new SourceMapModule(result, Trs80MemoryArea.Rom));
            _basicRom = BasicRom.From(
                result.Symbols,
                "READY",
                run: "ST_RUN",
                resume: "ST_CONT",
                [("CONSTP", "CONSTP"), ("PRGEND", "PRGEND")]);
        }
    }

    /// <inheritdoc/>
    public BasicDialect? Basic => _machine.Configuration.Rom == Trs80Rom.Level2 ? BasicDialect.Level2 : null;

    /// <inheritdoc/>
    public BasicRom? BasicRom => _basicRom;

    /// <inheritdoc/>
    public bool InRom(ushort address) => _machine.Bus.Area(address) == Trs80MemoryArea.Rom;

    /// <inheritdoc/>
    public int BasicTextPointer => _machine.Processor.Registers.HL;

    /// <inheritdoc/>
    public int BasicStack => Peek(SavedStack) | (Peek((ushort)(SavedStack + 1)) << 8);

    /// <inheritdoc/>
    public int BasicLiveStack => _machine.Processor.Registers.SP;

    /// <inheritdoc/>
    public int BasicForSize => ForEntrySize;

    /// <inheritdoc/>
    public (int Code, string Message, bool Handled) BasicError()
    {
        int code = _machine.Processor.Registers.E;
        string message = code / 2 < s_errors.Length ? $"?{s_errors[code / 2]} ERROR" : $"error {code}";
        bool handled = (Peek(ErrorLine) | Peek((ushort)(ErrorLine + 1))) != 0 && Peek(InErrorHandler) == 0;
        return (code, message, handled);
    }

    /// <inheritdoc/>
    public void SetBasicStatement(int line, int textPointer)
    {
        Poke(CurrentLine, (byte)line);
        Poke((ushort)(CurrentLine + 1), (byte)(line >> 8));
        Z80Registers registers = _machine.Processor.Registers;
        registers.HL = (ushort)textPointer;
        _machine.Processor.Registers = registers;
    }

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   As STKINI does, the stack starts at the bottom of string space with a zero word at its base, which FNDFOR
    ///   stops at. The last error is cleared too, as READY would otherwise start EDIT on a line after a syntax error.
    ///  </para>
    /// </remarks>
    public void EnterBasicPrompt(BasicRom rom)
    {
        int top = Peek(StackTop) | (Peek((ushort)(StackTop + 1)) << 8);
        ushort stack = (ushort)(top - 2);
        Poke(stack, 0);
        Poke((ushort)(stack + 1), 0);
        Poke(SavedStack, (byte)stack);
        Poke((ushort)(SavedStack + 1), (byte)(stack >> 8));
        Poke(TempPointer, FirstTemporary & 0xFF);
        Poke((ushort)(TempPointer + 1), FirstTemporary >> 8);
        Poke(ErrorCode, 0);
        Poke(CurrentLine, 0xFF);
        Poke((ushort)(CurrentLine + 1), 0xFF);
        Z80Registers registers = _machine.Processor.Registers;
        registers.SP = stack;
        registers.PC = rom.Prompt;
        _machine.Processor.Registers = registers;
        _calls.Reset();
    }

    /// <summary>
    ///  Gets the directory of the Model I ROM sources: a directory that holds them, or its <c>Trs80</c> folder.
    /// </summary>
    /// <param name="directory">The SDK ROM directory, or null for the copy beside the debug host.</param>
    /// <returns>The directory.</returns>
    internal static string SdkDirectory(string? directory)
    {
        string root = directory ?? SdkModules.RomDirectory;
        return File.Exists(Path.Join(root, "Level2.asm")) ? root : Path.Join(root, "Trs80");
    }

    /// <inheritdoc/>
    public void Key(int code) => _machine.Bus.Keyboard.Type((byte)code);

    /// <inheritdoc/>
    public void Reset()
    {
        _machine.Reset();
        _resetPending = true;
    }

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   The reset button raises a non-maskable interrupt, which the Z80 takes at the end of the instruction it is in;
    ///   its handler is at <c>$0066</c>.
    ///  </para>
    /// </remarks>
    public bool TakeResetStop()
    {
        if (!_resetPending || !IsInstructionBoundary || _machine.Processor.Registers.PC != Trs80Machine.ResetHandler)
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
        Trs80Video video = _machine.Bus.Video;
        int step = video.WideCharacters ? 2 : 1;
        string[] rows = new string[Trs80Video.Rows];
        for (int row = 0; row < rows.Length; row++)
        {
            char[] line = new char[Trs80Video.Columns / step];
            for (int column = 0; column < line.Length; column++)
            {
                byte code = video.Read((row * Trs80Video.Columns) + (column * step));
                line[column] = code switch
                {
                    0x80 => ' ',
                    0xBF => '█',
                    >= 0x80 => '▒',
                    >= 0x20 and < 0x7F => (char)code,

                    // Level II writes uppercase letters without bit 6, which only the lowercase modification
                    // keeps; the lowercase kit's font draws $00-$1F as those letters.
                    < 0x20 => (char)(code + 0x40),
                    _ => '.'
                };
            }

            rows[row] = new string(line);
        }

        return new JsonObject
        {
            ["machine"] = DebugMachines.Trs80Model1,
            ["columns"] = Trs80Video.Columns / step,
            ["rows"] = rows.ToJsonArray(),
            ["cycles"] = CycleCount,
            ["video"] = VideoState(),
            ["media"] = MediaState(),
            ["running"] = running
        };
    }

    /// <inheritdoc/>
    public IReadOnlyList<HardwareRow> Hardware()
    {
        Trs80Configuration configuration = _machine.Configuration;
        bool level1 = configuration.Rom == Trs80Rom.Level1;
        string rom = level1 ? "Level I BASIC" : _revision is 12 ? "Level II BASIC 1.2" : "Level II BASIC 1.3";
        string doubler = configuration.Doubler switch
        {
            Trs80Doubler.Percom => ", with a Percom doubler",
            Trs80Doubler.Tandy => ", with a Radio Shack doubler",
            Trs80Doubler.Both => ", with both doublers' selects",
            _ => ", single density"
        };

        return
        [
            new("model", "TRS-80 Model I", "Z80 at 1.774 MHz", "The keyboard unit's processor."),
            new("rom", "ROM", rom, "The launch's rom (level2, the default, or level1) and Level II revision (1.3 or 1.2)."),
            new(
                "memory",
                "Memory",
                $"{configuration.RamKilobytes} KB",
                "The launch's ramKilobytes option: 4 or 16 KB in the keyboard unit, up to 48 KB with the Expansion Interface."),
            new(
                "cassette",
                "Cassette",
                "Cassette recorder",
                "The keyboard unit's tape port, at 500 baud for Level II or 250 for Level I.",
                [_machine.Cassette.Id]),
            new(
                "expansion",
                "Expansion Interface",
                configuration.ExpansionInterface ? "installed" : "none",
                "The launch's expansionInterface option: more memory, the real-time clock and the disk controller."),
            new(
                "disk",
                "Disk controller",
                _machine.Bus.HasDiskController ? "FD1771" + doubler : "none",
                "In the Expansion Interface: the launch's diskController option, with doubler for double density.",
                _machine.Bus.HasDiskController ? [.. _machine.Drives.Select(drive => drive.Id)] : null),
            new(
                "lowercase",
                "Lowercase modification",
                configuration.LowercaseModification ? "installed" : "none",
                "The launch's lowercase option: the extra video memory bit and character generator for lowercase.")
        ];
    }

    /// <inheritdoc/>
    public ReadOnlySpan<byte> RenderVideo()
    {
        _machine.Bus.Video.Render(_pixels, scanned: true);
        return _pixels;
    }

    private JsonObject VideoState() => new JsonObject
    {
        ["width"] = _machine.Bus.Video.Width,
        ["height"] = _machine.Bus.Video.Height,
        ["pixelFormat"] = "rgba",
        ["cycles"] = CycleCount
    };

    private JsonObject VideoFrame(bool scanned)
    {
        _machine.Bus.Video.Render(_pixels, scanned);
        return new JsonObject
        {
            ["width"] = _machine.Bus.Video.Width,
            ["height"] = _machine.Bus.Video.Height,
            ["pixelFormat"] = "rgba",
            ["pixels"] = Convert.ToBase64String(_pixels),
            ["cycles"] = CycleCount
        };
    }
}
