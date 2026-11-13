// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.Json.Nodes;
using Retrocore.Cpu.Z80;
using Retrocore.Isa;
using Retrocore.Machines.Trs80;

namespace Retrocore.Debug;

/// <summary>
///  The TRS-80 Model II, 12 or 16 as the debugger sees it: a Z80, its banked memory, its 80x24 display, keyboard and
///  8-inch disks.
/// </summary>
internal sealed partial class Trs80Model2DebugTarget : IDebugTarget
{
    private static readonly DebugRegisters s_registers = new(Z80Isa.Description);

    private readonly Trs80Model2Machine _machine;
    private readonly Z80CallStack _calls;
    private readonly byte[] _pixels;
    private string _screen = DebugScreens.Green;
    private DebugFrame _beforeInstruction;
    private bool _instruction;
    private bool _resetPending;

    /// <summary>
    ///  Creates the target for a launched machine.
    /// </summary>
    /// <param name="machine">The machine.</param>
    internal Trs80Model2DebugTarget(Trs80Model2Machine machine)
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
    internal Trs80Model2Machine Machine => _machine;

    private string ModelName => _machine.Configuration.Variant switch
    {
        Trs80Model2Variant.Model12 => "Model 12",
        Trs80Model2Variant.Model16 => "Model 16",
        _ => "Model II"
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
    public bool InInstruction => _instruction;

    /// <inheritdoc/>
    public ulong CycleCount => _machine.Processor.CycleCount;

    /// <inheritdoc/>
    public int ClockHertz => Trs80Model2Timing.ClockHertz;

    /// <inheritdoc/>
    /// <remarks>
    ///  The machine runs as fast as it can while the disk controller works, unless the launch asks not to.
    /// </remarks>
    public bool Accelerated => FastDisk && _machine.Bus.Disks.IsBusy;

    /// <summary>
    ///  Gets or sets whether running outpaces the clock while the disk controller works.
    /// </summary>
    internal bool FastDisk { get; set; } = true;

    /// <inheritdoc/>
    public IDebugCallStack CallStack => _calls;

    /// <inheritdoc/>
    public int DefaultLoadAddress => 0x7000;

    /// <inheritdoc/>
    public Enum ProgramArea => Trs80Model2MemoryArea.Ram;

    /// <inheritdoc/>
    public string ContractModel => "Model2";

    /// <inheritdoc/>
    public IReadOnlyList<string> UsedRegisters { get; } = ["A", "B", "C", "D", "E", "H", "L", "IX", "IY"];

    /// <inheritdoc/>
    public (string Name, ushort Start, int Length) MemoryScope => ("Page zero", 0x0000, 256);

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
        if (_machine.Bus.Area(address) is not (Trs80Model2MemoryArea.Ram or Trs80Model2MemoryArea.Video))
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
            if (address + index > 0xFFFF || _machine.Bus.Area((ushort)(address + index)) != Trs80Model2MemoryArea.Ram)
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
    ///   The SDK has no source for the Model II's boot ROM yet, so nothing is added.
    ///  </para>
    /// </remarks>
    public void AddSdkModules(DebugInfo debug, string? directory)
    {
    }

    /// <inheritdoc/>
    public bool InRom(ushort address) => _machine.Bus.Area(address) == Trs80Model2MemoryArea.Rom;

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
    /// <remarks>
    ///  <para>
    ///   The reset switch resets the Z80, which starts the boot ROM at <c>$0000</c>.
    ///  </para>
    /// </remarks>
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
        Trs80Model2Video video = _machine.Bus.Video;
        string[] rows = new string[video.Rows];
        for (int row = 0; row < rows.Length; row++)
        {
            char[] line = new char[video.Columns];
            for (int column = 0; column < line.Length; column++)
            {
                int code = video.Displayed(row, column) & 0x7F;
                line[column] = code is >= 0x20 and < 0x7F ? (char)code : '.';
            }

            rows[row] = new string(line);
        }

        return new JsonObject
        {
            ["machine"] = DebugMachines.Trs80Model2,
            ["model"] = ModelName,
            ["columns"] = video.Columns,
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
        Trs80Model2Configuration configuration = _machine.Configuration;
        return
        [
            new(
                "model",
                $"TRS-80 {ModelName}",
                configuration.Variant == Trs80Model2Variant.Model16 ? "Z80 at 4 MHz (the 68000 board is not emulated)" : "Z80 at 4 MHz",
                "The launch's model: 2 (the default), 12 or 16."),
            new("rom", "ROM", "Boot ROM (2K)", "From the dumps in romDirectory."),
            new(
                "memory",
                "Memory",
                $"{configuration.RamKilobytes} KB",
                "The launch's ramKilobytes option: 32 to 512 KB in 32K banks, selected at $8000 through port $FF."),
            new("chips", "Peripherals", "Z80 CTC, PIO, SIO and DMA", "The SIO's serial ports have nothing connected."),
            new(
                "disk",
                "Disk controller",
                "FD1791 with the Z80 DMA",
                "Four 8-inch drives.",
                [.. _machine.Drives.Select(drive => drive.Id)])
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
