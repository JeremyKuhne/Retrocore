// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Basic;
using Retrocore.Cpu.Z80;
using Retrocore.Isa;
using Retrocore.Machines.Trs80;
using System.Text.Json.Nodes;

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

    // The Model I's video is white on black; a monitor of another phosphor shows it in that color.
    private string _screen = DebugScreens.Green;
    private DebugFrame _beforeInstruction;
    private bool _instruction;
    private BasicRom? _basicRom;
    private Trs80Level1Basic? _level1;

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
    public int StackPointer => _machine.Processor.Registers.SP;

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
    public bool IsTakingInterrupt => _machine.Processor.IsTakingInterrupt;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   A halted Z80 runs a refresh fetch every four T-states without leaving the instruction after its HALT.
    ///  </para>
    /// </remarks>
    public bool IsIdle => _machine.Processor.IsHalted;

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
    public IReadOnlyList<DebugRegion> Regions =>
    [
        new(_machine.Configuration.Rom == Trs80Rom.Level1 ? "Level I ROM" : "Level II ROM", 0x0000,
            _machine.Configuration.Rom == Trs80Rom.Level1 ? 0x1000 : 0x3000, "rom"),
        new("Expansion interface I/O", 0x37E0, 0x20, "io"),
        new("Keyboard", 0x3800, 0x400, "io"),
        new("Video", 0x3C00, 0x400, "video", DebugRegion.Rows(64)),
        new("Communication region", 0x4000, 0x100, "ram")
    ];

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
    public void RunCycles(int cycles)
    {
        for (int count = 0; count < cycles; count++) { _machine.StepCycle(); }
        _calls.Reset();
        _instruction = false;
        if (_machine.Processor.Status == ProcessorExecutionStatus.Stopped)
        {
            throw new InvalidOperationException("CPU stopped.");
        }
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
    public string? Trap(ushort address) => null;

    /// <inheritdoc/>
    public void Poke(ushort address, byte value)
    {
        if (!CanPoke(address))
        {
            throw new ArgumentException($"${address:X4} is not RAM or video RAM.");
        }

        _machine.Bus.Write(address, value);
    }

    /// <inheritdoc/>
    public bool CanPoke(ushort address) => _machine.Bus.Area(address) is Trs80MemoryArea.Ram or Trs80MemoryArea.Video;

    /// <inheritdoc/>
    public Machines.ICharacterSet? CharacterSet => _machine.Bus.Video;

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
            // The source and the BASIC thread are the SDK build's, so a dump of another Level I gets neither.
            string level1 = Path.Join(roms, "Level1.asm");
            if (File.Exists(level1)
                && Trs80SdkModules.Matching(SystemRomImage, [() => Trs80SdkModules.AssembleLevel1(level1)]) is { } result)
            {
                debug.Add(new SourceMapModule(result, Trs80MemoryArea.Rom));
                _level1 = Trs80Level1Basic.From(result.Symbols, this, () => _machine.Processor.Registers, SetRegisters, _calls.Reset);
            }

            return;
        }

        // The power-up message picks the revision to build, and the build must be the ROM's bytes, so a dump that only
        // shares a revision's message gets neither the source nor the BASIC thread.
        string level2 = Path.Join(roms, "Level2.asm");
        if (_revision is { } revision
            && File.Exists(level2)
            && Trs80SdkModules.Matching(SystemRomImage, [() => Trs80SdkModules.AssembleLevel2(level2, revision)]) is { } built)
        {
            debug.Add(new SourceMapModule(built, Trs80MemoryArea.Rom));
            _basicRom = BasicRom.From(
                built.Symbols,
                "READY",
                run: "ST_RUN",
                resume: "ST_CONT",
                [("CONSTP", "CONSTP"), ("PRGEND", "PRGEND")]);
        }
    }

    /// <summary>
    ///  Gets the system ROM the machine was launched with: Level II's 12K or Level I's 4K.
    /// </summary>
    internal byte[] SystemRomImage { get; init; } = [];

    /// <inheritdoc/>
    public BasicDialect? Basic => _machine.Configuration.Rom == Trs80Rom.Level2 ? BasicDialect.Level2 : BasicDialect.Level1;

    /// <inheritdoc/>
    public BasicRom? BasicRom => _level1?.Rom ?? _basicRom;

    /// <inheritdoc/>
    public int BasicCurrentLine => _machine.Configuration.Rom == Trs80Rom.Level1
        ? _level1?.LineNumber ?? Level1Dialect.CurrentLineNumber(new TargetBasicMemory(this))
        : Peek(CurrentLine) | (Peek((ushort)(CurrentLine + 1)) << 8);

    /// <inheritdoc/>
    public bool BasicInDirectMode => _level1 is { } level1
        ? level1.LineAddress == 0
        : Basic is not { } dialect || dialect.InDirectMode(new TargetBasicMemory(this));

    /// <inheritdoc/>
    public (int Line, int Address)? BasicStatementStart(ushort pc)
    {
        if (_level1 is { } level1) { return level1.StatementStart(pc); }
        return _basicRom is { } rom && pc == rom.Gone ? (BasicCurrentLine, BasicTextPointer + 1) : null;
    }

    /// <inheritdoc/>
    public IReadOnlyList<(int Line, int TextPointer)>? BasicGosubs => _level1?.Gosubs;

    /// <inheritdoc/>
    public bool InRom(ushort address) => _machine.Bus.Area(address) == Trs80MemoryArea.Rom;

    /// <inheritdoc/>
    public int BasicTextPointer => _level1?.TextPointer ?? _machine.Processor.Registers.HL;

    /// <inheritdoc/>
    public int BasicStack => _level1?.Stack ?? (Peek(SavedStack) | (Peek((ushort)(SavedStack + 1)) << 8));

    /// <inheritdoc/>
    public int BasicLiveStack => _machine.Processor.Registers.SP;

    /// <inheritdoc/>
    public int BasicForSize => _level1 is null ? ForEntrySize : Trs80Level1Basic.ForSize;

    /// <inheritdoc/>
    public (int Code, string Message, bool Handled) BasicError()
    {
        if (_level1 is { } level1) { return level1.Error(); }
        int code = _machine.Processor.Registers.E;
        string message = code / 2 < s_errors.Length ? $"?{s_errors[code / 2]} ERROR" : $"error {code}";
        bool handled = (Peek(ErrorLine) | Peek((ushort)(ErrorLine + 1))) != 0 && Peek(InErrorHandler) == 0;
        return (code, message, handled);
    }

    /// <inheritdoc/>
    public void SetBasicStatement(int line, int textPointer)
    {
        if (_level1 is { } level1)
        {
            level1.SetStatement(line, textPointer);
            return;
        }

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
        if (_level1 is { } level1)
        {
            level1.EnterPrompt();
            return;
        }

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

    private void SetRegisters(Z80Registers registers) => _machine.Processor.Registers = registers;

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
    public bool Key(int code) => _machine.Bus.Keyboard.Type((byte)code);

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
            ["screen"] = _screen,
            ["screens"] = Screens.ToJsonArray(),
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
        _machine.Bus.Video.Render(_pixels, scanned: true);
        DebugScreens.Show(_pixels, _screen);
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
        DebugScreens.Show(_pixels, _screen);
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
