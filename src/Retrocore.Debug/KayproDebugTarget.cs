// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Cpu.Z80;
using Retrocore.Isa;
using Retrocore.Machines.Kaypro;
using System.Text.Json.Nodes;

namespace Retrocore.Debug;

/// <summary>
///  Debugs a Kaypro II: its Z80, with the SDK's monitor ROM source, the screen, the drives and the RAM under the ROM.
/// </summary>
internal sealed partial class KayproDebugTarget : IDebugTarget
{
    private static readonly DebugRegisters s_registers = new(Z80Isa.Description);

    private readonly KayproMachine _machine;
    private readonly Z80CallStack _calls;
    private readonly byte[] _pixels;
    private string _screen = DebugScreens.Green;
    private DebugFrame _beforeInstruction;
    private bool _instruction;
    private bool _resetPending;

    /// <summary>
    ///  Creates the target.
    /// </summary>
    /// <param name="machine">The machine.</param>
    internal KayproDebugTarget(KayproMachine machine)
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
    internal KayproMachine Machine => _machine;

    /// <inheritdoc/>
    public string ThreadName => "Kaypro II Z80";

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
    public bool InInstruction => _instruction;

    /// <inheritdoc/>
    public ulong CycleCount => _machine.Processor.CycleCount;

    /// <inheritdoc/>
    public int ClockHertz => KayproTiming.ClockHertz;

    /// <inheritdoc/>
    public bool Accelerated => FastDisk && _machine.Bus.Disks.IsBusy;

    /// <summary>
    ///  Gets or sets whether the machine runs unthrottled while the disk controller is busy.
    /// </summary>
    internal bool FastDisk { get; set; } = true;

    /// <inheritdoc/>
    public IDebugCallStack CallStack => _calls;

    /// <inheritdoc/>
    public int DefaultLoadAddress => 0x0100;

    /// <inheritdoc/>
    public Enum ProgramArea => KayproMemoryArea.Ram;

    /// <inheritdoc/>
    public string ContractModel => "Kaypro2";

    /// <inheritdoc/>
    public IReadOnlyList<string> UsedRegisters { get; } = ["A", "B", "C", "D", "E", "H", "L", "IX", "IY"];

    /// <inheritdoc/>
    public (string Name, ushort Start, int Length) MemoryScope => ("CP/M page zero", 0x0000, 256);

    /// <inheritdoc/>
    public IReadOnlyList<DebugRegion> Regions { get; } =
    [
        new("CP/M page zero", 0x0000, 0x100, "ram"),
        new("Transient program area", 0x0100, 0xE300, "ram"),
        new("Monitor ROM's disk buffers and tables", 0xFC00, 0x400, "ram"),
        new("Video RAM, while the ROM is banked in", 0x3000, 0x1000, "video", offset => Line(offset))
    ];

    /// <inheritdoc/>
    public IReadOnlyList<DebugMemoryBank> Banks => field ??= CreateBanks();

    /// <inheritdoc/>
    public IReadOnlyDictionary<string, Func<JsonObject, JsonObject>> Requests { get; }

    /// <inheritdoc/>
    public byte Peek(ushort address) => _machine.Bus.Peek(address);

    /// <inheritdoc/>
    public Enum ReadArea(ushort address) => _machine.Bus.Area(address);

    /// <inheritdoc/>
    public string? KindAt(ushort address) => _machine.Bus.Area(address) switch
    {
        KayproMemoryArea.Rom => address < KayproRoms.MonitorSize ? "rom" : "none",
        KayproMemoryArea.Video => "video",
        _ => null
    };

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
    public string? Trap(ushort address) => null;

    /// <inheritdoc/>
    public void Poke(ushort address, byte value)
    {
        if (!CanPoke(address))
        {
            throw new ArgumentException($"${address:X4} is the ROM.");
        }

        _machine.Bus.Write(address, value);
    }

    /// <inheritdoc/>
    public bool CanPoke(ushort address) => _machine.Bus.Area(address) is KayproMemoryArea.Ram or KayproMemoryArea.Video;

    /// <inheritdoc/>
    public Machines.ICharacterSet? CharacterSet => _machine.Bus.Video;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   A program loads into RAM whether or not the ROM is banked over it, as a CP/M program loads at <c>$0100</c>.
    ///  </para>
    /// </remarks>
    public void Load(int address, ReadOnlySpan<byte> bytes)
    {
        if (address < 0 || address + bytes.Length > 0x10000)
        {
            throw new ArgumentException($"Program must fit in the 64K of RAM; it ends at ${address + bytes.Length - 1:X4}.");
        }

        for (int index = 0; index < bytes.Length; index++)
        {
            _machine.Bus.PokeRam((ushort)(address + index), bytes[index]);
        }
    }

    /// <inheritdoc/>
    public void AddSdkModules(DebugInfo debug, string? directory)
    {
        string sources = KayproSdkModules.SourceDirectory(directory);
        AddMbasic(debug, sources);
        string source = Path.Join(sources, KayproSdkModules.MonitorSource);
        if (!File.Exists(source)) { return; }
        AssemblyResult result = KayproSdkModules.AssembleMonitor(source);
        if (!result.Sections[0].Bytes.Span.SequenceEqual(MonitorImage)) { return; }

        // Not bound to the ROM's area: the transfer routines run where the ROM copies them, at the top of RAM, and each
        // statement applies wherever memory holds its bytes.
        debug.Add(new SourceMapModule(result, area: null));
    }

    /// <summary>
    ///  Gets the monitor ROM the machine runs.
    /// </summary>
    internal byte[] MonitorImage { get; init; } = [];

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   The cursor keys send <c>$F1</c>-<c>$F4</c> and the keypad's keys codes from <c>$B1</c> up.
    ///  </para>
    /// </remarks>
    public int MaximumKey => 255;

    /// <inheritdoc/>
    public bool Key(int code)
    {
        _machine.Bus.Keyboard.Type((byte)code);
        return true;
    }

    /// <inheritdoc/>
    public void Reset()
    {
        _machine.Reset();
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
        KayproVideo video = _machine.Bus.Video;
        string[] rows = new string[KayproVideo.Rows];
        for (int row = 0; row < rows.Length; row++)
        {
            char[] line = new char[KayproVideo.Columns];
            for (int column = 0; column < line.Length; column++)
            {
                char character = video.Character(video.Displayed(row, column));
                line[column] = character == '\0' ? '.' : character;
            }

            rows[row] = new string(line);
        }

        return new JsonObject
        {
            ["machine"] = DebugMachines.Kaypro2,
            ["model"] = "Kaypro II",
            ["columns"] = KayproVideo.Columns,
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
    public IReadOnlyList<HardwareRow> Hardware() =>
    [
        new("model", "Kaypro II", "Z80 at 2.5 MHz", "Non-Linear Systems' Kaypro II (1982), with 81-149C ROM."),
        new("rom", "ROM", "Monitor ROM 81-149C (2K)", "The SDK's source, or the dumps in romDirectory."),
        new("memory", "Memory", "64 KB, with 4 KB of video RAM", "The ROM and video RAM bank over $0000-$3FFF while the system port's bit 7 is set."),
        new("chips", "Peripherals", "Z80 SIO and two Z80 PIOs", "The keyboard is on the SIO's channel B; the serial and printer ports capture what is sent."),
        new(
            "disk",
            "Disk controller",
            "FD1793",
            "Two 5¼-inch single-sided double-density drives, A and B.",
            [.. _machine.Drives.Select(drive => drive.Id)])
    ];

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

    // A video RAM offset's place on the screen.
    private static string Line(int offset) => (offset % KayproVideo.LineBytes) < KayproVideo.Columns && offset / KayproVideo.LineBytes < KayproVideo.Rows
        ? $"line {offset / KayproVideo.LineBytes}, column {offset % KayproVideo.LineBytes}"
        : "not shown";

    private List<DebugMemoryBank> CreateBanks()
    {
        KayproBus bus = _machine.Bus;
        return
        [
            new(
                "ram",
                "RAM under the ROM",
                [KayproMemoryArea.Ram],
                [(0x0000, KayproBus.BankEnd)],
                address => bus.PeekRam(address),
                (address, value) =>
                {
                    bus.PokeRam(address, value);
                    return true;
                },
                ReadsHere: address => bus.Area(address) == KayproMemoryArea.Ram),
            new(
                "rom",
                "Monitor ROM",
                [KayproMemoryArea.Rom],
                [(0x0000, KayproRoms.MonitorSize)],
                address => MonitorImage.Length > address ? MonitorImage[address] : null,
                Poke: null),
            new(
                "video",
                "Video RAM",
                [KayproMemoryArea.Video],
                [(KayproBus.VideoStart, KayproVideo.Size)],
                address => bus.Video.Read(address - KayproBus.VideoStart),
                (address, value) =>
                {
                    bus.Video.Write(address - KayproBus.VideoStart, value);
                    return true;
                })
        ];
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
