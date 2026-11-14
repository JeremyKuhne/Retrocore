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
///  The TRS-80 Model III, 4 or 4P as the debugger sees it: a Z80, the memory map the machine has selected, its 64x16
///  or 80x24 display, keyboard, cassette and disks.
/// </summary>
internal sealed partial class Trs80Model3DebugTarget : IDebugTarget
{
    // Where Level II keeps the stack pointer as each statement begins.
    private const ushort SavedStack = 0x40E8;

    private static readonly DebugRegisters s_registers = new(Z80Isa.Description);

    private readonly Trs80Model3Machine _machine;
    private readonly Z80CallStack _calls;
    private readonly byte[] _pixels;
    private string _screen = DebugScreens.Green;
    private DebugFrame _beforeInstruction;
    private bool _instruction;
    private bool _resetPending;
    private BasicRom? _basicRom;


    /// <summary>
    ///  Creates the target for a launched machine.
    /// </summary>
    /// <param name="machine">The machine.</param>
    internal Trs80Model3DebugTarget(Trs80Model3Machine machine)
    {
        _machine = machine;
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
    internal Trs80Model3Machine Machine => _machine;

    private string ModelName => _machine.Configuration.Variant switch
    {
        Trs80Model3Variant.Model4 => "Model 4",
        Trs80Model3Variant.Model4P => "Model 4P",
        _ => "Model III"
    };

    /// <inheritdoc/>
    public string ThreadName => $"{ModelName} Z80";

    /// <inheritdoc/>
    public string Cpu => "Z80";

    /// <inheritdoc/>
    public InstructionSet InstructionSet => Z80Isa.InstructionSet;

    /// <inheritdoc/>
    public bool HasPorts => true;

    /// <inheritdoc/>
    public DebugRegisters Registers => s_registers;

    /// <inheritdoc/>
    public ProcessorCycle LastCycle => _machine.LastCycle;

    /// <inheritdoc/>
    public DebugFrame Frame => Trs80DebugTarget.FrameOf(_machine.Processor.Registers);

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
    /// <remarks>
    ///  <para>
    ///   Drive select's wait bit holds the Z80 until the disk controller asks for data or finishes, which can take
    ///   a revolution of the disk or more.
    ///  </para>
    /// </remarks>
    public bool IsHeld => _machine.Bus.WaitRequested && !_machine.Processor.IsInstructionBoundary;

    /// <inheritdoc/>
    public bool InInstruction => _instruction;

    /// <inheritdoc/>
    public ulong CycleCount => _machine.Processor.CycleCount;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   A Model 4 changes speed when its program writes port <c>$EC</c> bit 6.
    ///  </para>
    /// </remarks>
    public int ClockHertz => _machine.ClockHertz;

    /// <inheritdoc/>
    /// <remarks>
    ///  The machine runs as fast as it can while the cassette motor runs, unless the launch asks not to.
    /// </remarks>
    public bool Accelerated => FastCassette && _machine.Cassette is not null && _machine.Bus.Cassette.MotorOn;

    /// <summary>
    ///  Gets or sets whether running outpaces the clock while the cassette motor runs.
    /// </summary>
    internal bool FastCassette { get; set; } = true;

    /// <inheritdoc/>
    public IDebugCallStack CallStack => _calls;

    /// <inheritdoc/>
    public int DefaultLoadAddress => 0x7000;

    /// <inheritdoc/>
    public Enum ProgramArea => Trs80Model3MemoryArea.Ram;

    /// <inheritdoc/>
    public string ContractModel => _machine.Configuration.IsModel4 ? "Model4" : "Model3";

    /// <inheritdoc/>
    public IReadOnlyList<string> UsedRegisters { get; } = ["A", "B", "C", "D", "E", "H", "L", "IX", "IY"];

    /// <inheritdoc/>
    public (string Name, ushort Start, int Length) MemoryScope => ("Communication region", 0x4000, 256);

    /// <inheritdoc/>
    public IReadOnlyDictionary<string, Func<JsonObject, JsonObject>> Requests { get; }

    /// <inheritdoc/>
    public byte Peek(ushort address) => _machine.Bus.Peek(address);

    /// <inheritdoc/>
    public Enum ReadArea(ushort address) => _machine.Bus.Area(address);

    /// <inheritdoc/>
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
    public string? Trap(ushort address) => null;

    /// <inheritdoc/>
    public void Poke(ushort address, byte value)
    {
        if (_machine.Bus.Area(address) is not (Trs80Model3MemoryArea.Ram or Trs80Model3MemoryArea.Video))
        {
            throw new ArgumentException($"${address:X4} is not RAM or video RAM.");
        }

        _machine.Bus.Write(address, value);
    }

    /// <inheritdoc/>
    public void Load(int address, ReadOnlySpan<byte> bytes)
    {
        for (int index = 0; index < bytes.Length; index++)
        {
            if (address + index > 0xFFFF || _machine.Bus.Area((ushort)(address + index)) != Trs80Model3MemoryArea.Ram)
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
    /// <remarks>
    ///  <para>
    ///   The source is the build of <c>Model3.asm</c>, <c>Model4PBoot.asm</c> or, for Level I, <c>Level1.asm</c>
    ///   with <c>MODEL = 3</c>, whose bytes are the running ROM's,
    ///   so a dump of another revision gets none. The Model III's and Model 4's BASIC is Level II's, at Level II's
    ///   addresses, so the BASIC debugger reads it as it reads the Model I's.
    ///  </para>
    /// </remarks>
    public void AddSdkModules(DebugInfo debug, string? directory)
    {
        string roms = Trs80DebugTarget.SdkDirectory(directory);
        if (_machine.Configuration.Rom == Trs80Rom.Level1)
        {
            string level1 = Path.Join(roms, "Level1.asm");
            if (File.Exists(level1)
                && Trs80SdkModules.Matching(SystemRomImage, [() => Trs80SdkModules.AssembleLevel1(level1, 3)]) is { } built)
            {
                debug.Add(new SourceMapModule(built, Trs80Model3MemoryArea.Rom));
            }

            return;
        }

        if (_machine.Configuration.Variant == Trs80Model3Variant.Model4P)
        {
            string boot = Path.Join(roms, "Model4PBoot.asm");
            if (File.Exists(boot)
                && Trs80SdkModules.Matching(SystemRomImage, [() => Trs80SdkModules.AssembleModel4PBoot(boot)]) is { } result)
            {
                debug.Add(new SourceMapModule(result, Trs80Model3MemoryArea.Rom));
            }

            return;
        }

        string source = Path.Join(roms, "Model3.asm");
        if (!File.Exists(source)) { return; }
        Func<AssemblyResult>[] builds = _machine.Configuration.Variant == Trs80Model3Variant.Model4
            ? [() => Trs80SdkModules.AssembleModel3(source, 4), () => Trs80SdkModules.AssembleModel3(source, 3)]
            : [() => Trs80SdkModules.AssembleModel3(source, 3), () => Trs80SdkModules.AssembleModel3(source, 3, 'B')];

        if (Trs80SdkModules.Matching(SystemRomImage, builds) is { } basic)
        {
            debug.Add(new SourceMapModule(basic, Trs80Model3MemoryArea.Rom));
            _basicRom = BasicRom.From(
                basic.Symbols,
                "READY",
                run: "ST_RUN",
                resume: "ST_CONT",
                [("CONSTP", "CONSTP"), ("PRGEND", "PRGEND")]);
        }
    }

    /// <summary>
    ///  Gets the ROM the machine was launched with: the 14K system ROM, or the 4P's boot ROM.
    /// </summary>
    internal byte[] SystemRomImage { get; init; } = [];

    /// <inheritdoc/>
    public BasicDialect? Basic =>
        _machine.Configuration.Variant == Trs80Model3Variant.Model4P || _machine.Configuration.Rom == Trs80Rom.Level1
            ? null
            : BasicDialect.Level2;

    /// <inheritdoc/>
    public BasicRom? BasicRom => _basicRom;

    /// <inheritdoc/>
    public int BasicTextPointer => _machine.Processor.Registers.HL;

    /// <inheritdoc/>
    public int BasicStack => Peek(SavedStack) | (Peek((ushort)(SavedStack + 1)) << 8);

    /// <inheritdoc/>
    public bool InRom(ushort address) => _machine.Bus.Area(address) == Trs80Model3MemoryArea.Rom;

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
        if (!_resetPending || !IsInstructionBoundary || _machine.Processor.Registers.PC != Trs80Model3Machine.NmiHandler)
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
        Trs80Model3Video video = _machine.Bus.Video;
        int step = video.WideCharacters ? 2 : 1;
        int columns = video.Eighty ? 80 : 64;
        string[] rows = new string[video.Rows];
        for (int row = 0; row < rows.Length; row++)
        {
            char[] line = new char[columns / step];
            for (int column = 0; column < line.Length; column++)
            {
                byte code = video.Displayed(row, column * step);
                line[column] = code switch
                {
                    0x80 => ' ',
                    0xBF => '█',
                    >= 0x80 and < 0xC0 => '▒',
                    >= 0x20 and < 0x7F => (char)code,
                    _ => '.'
                };
            }

            rows[row] = new string(line);
        }

        return new JsonObject
        {
            ["machine"] = DebugMachines.Trs80Model3,
            ["model"] = ModelName,
            ["columns"] = columns / step,
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
        Trs80Model3Configuration configuration = _machine.Configuration;
        bool model4P = configuration.Variant == Trs80Model3Variant.Model4P;
        List<HardwareRow> rows =
        [
            new(
                "model",
                $"TRS-80 {ModelName}",
                configuration.IsModel4 ? "Z80 at 2.03 or 4.06 MHz" : "Z80 at 2.03 MHz",
                "The launch's model: 3 (the default), 4 or 4p."),
            new(
                "rom",
                "ROM",
                model4P ? "Boot ROM (4K)" : configuration.Rom == Trs80Rom.Level1 ? "Level I BASIC (4K)" : "Model III ROM (14K)",
                "From the dumps in romDirectory, or built from the SDK's sources; the launch's rom option picks Level I."),
            new(
                "memory",
                "Memory",
                $"{configuration.RamKilobytes} KB",
                configuration.IsModel4
                    ? "The launch's ramKilobytes option: 64 or 128 KB, the second 64K banked through port $84."
                    : "The launch's ramKilobytes option: 16, 32 or 48 KB.")
        ];

        if (_machine.Cassette is { } cassette)
        {
            rows.Add(new(
                "cassette",
                "Cassette",
                "Cassette recorder",
                "The cassette port, at 500 baud; the 1500 baud rate is not emulated yet.",
                [cassette.Id]));
        }

        rows.Add(new(
            "disk",
            "Disk controller",
            _machine.Bus.HasDiskController ? "FD1793" : "none",
            "The launch's diskController option, on by default when disks are given.",
            _machine.Bus.HasDiskController ? [.. _machine.Drives.Select(drive => drive.Id)] : null));

        return rows;
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
