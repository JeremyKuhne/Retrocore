// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Cpu;
using Retrocore.Cpu.M6502;
using Retrocore.Machines.Apple2;
using Retrocore.Machines.Devices;

namespace Retrocore.Machines.Apple3;

/// <summary>
///  A caller-clocked Apple III, independent of UI and debugger protocols.
/// </summary>
/// <remarks>
///  <para>
///   Time runs on the 14.318 MHz master clock, kept in thousandths of a dot. A 1 MHz cycle takes 14.031 dots on
///   average: a line is 65 of them, one stretched by 2 dots (the Service Reference Manual's HPE freeze). A 2 MHz
///   cycle takes 7.516 dots (1.905 MHz), the average MAME measured on hardware, which folds in stretched cycles
///   and DRAM refresh. At 2 MHz with video on, the CPU drops to 1 MHz while the beam draws the visible part of a
///   visible line. The VIAs and the disk run at 14.318 MHz / 14 whatever the CPU does.
///  </para>
///  <para>
///   A frame is 262 lines of 912 dots, as the manual gives them (MAME uses 910): the first 192 lines are visible,
///   and in each the first 560 dots, 40 states of 14. Vertical blanking (lines 192-261) drives VIA 1's CB1 and
///   CB2, and screen blanking VIA 1's PB6.
///  </para>
/// </remarks>
public sealed class Apple3Machine : IMachine
{
    private const int SlowCycle = 14_031;           // 912 / 65 dots
    private const int FastCycle = 7_516;
    private const int LineLength = 912_000;
    private const int VisibleLength = 560_000;
    private const int FrameLines = 262;
    private const int VisibleLines = 192;

    private const string Controller = "Apple III built-in disk controller";

    private static readonly string[] s_memoryAreas = Enum.GetNames<Apple3MemoryArea>();

    private int _lineTime;
    private int _line;
    private bool _drawing;
    private bool _verticalBlank;
    private bool _irq;
    private bool _nmi;
    private IDevice[]? _devices;
    private int _deviceChanges;

    // Time owed to the SoftCard ///'s Z80, less than a T-state.
    private int _z80Time;

    // Whether the SoftCard /// held the 6502 in the last cycle.
    private bool _held;

    /// <summary>
    ///  Constructs a machine at power-on.
    /// </summary>
    /// <param name="roms">The firmware.</param>
    /// <param name="ramKilobytes">128, 256 or 512.</param>
    public Apple3Machine(Apple3Roms roms, int ramKilobytes = 256)
    {
        Bus = new(roms, ramKilobytes);
        Video = new(Bus);
        Drives =
        [
            new(Bus.Disk, 1, "disk1", "Built-in drive (.D1)", "Built-in 5¼-inch floppy drive", Controller),
            new(Bus.Disk, 2, "disk2", "External drive 1 (.D2)", "Disk III 5¼-inch floppy drive", Controller),
            new(Bus.Disk, 3, "disk3", "External drive 2 (.D3)", "Disk III 5¼-inch floppy drive", Controller),
            new(Bus.Disk, 4, "disk4", "External drive 3 (.D4)", "Disk III 5¼-inch floppy drive", Controller)
        ];

        Processor = new(Bus, ProcessorVariant.Mos6502);

        // Where the beam is at power-on is happenstance; it starts where MAME's does, at the start of vertical
        // blanking, so the two run in step.
        _line = VisibleLines;
        _verticalBlank = true;
        Bus.SetDrawing(drawing: false);
        Bus.SetVerticalBlank(blanking: true);
        Processor.Reset();
    }

    /// <summary>
    ///  Gets the memory and devices.
    /// </summary>
    public Apple3Bus Bus { get; }

    /// <summary>
    ///  Gets the video.
    /// </summary>
    public Apple3Video Video { get; }

    /// <summary>
    ///  Gets the CPU, a Synertek 6502A.
    /// </summary>
    public Processor<Apple3Bus> Processor { get; }

    /// <summary>
    ///  Gets the time since power-on, in thousandths of a 14.318 MHz dot.
    /// </summary>
    public long Time { get; private set; }

    /// <summary>
    ///  Gets the line the beam is on: 0-191 visible, 192-261 vertical blanking.
    /// </summary>
    public int Line => _line;

    /// <summary>
    ///  Gets the drives: the built-in one, then the three external ones, as SOS names them .D1-.D4.
    /// </summary>
    public IReadOnlyList<Apple2FloppyDrive> Drives { get; }

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   The four floppy drives, then the ProFile on each slot's ProFile card, in slot order. The list is made again
    ///   only when a card goes in or comes out.
    ///  </para>
    /// </remarks>
    public IReadOnlyList<IDevice> Devices
    {
        get
        {
            if (_devices is null || _deviceChanges != Bus.CardChanges)
            {
                List<IDevice> devices = [.. Drives];
                for (int slot = 1; slot <= 4; slot++)
                {
                    if (Bus.ProFileIn(slot) is { } card) { devices.Add(card.Drive); }
                }

                _devices = [.. devices];
                _deviceChanges = Bus.CardChanges;
            }

            return _devices;
        }
    }

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   While the SoftCard /// holds the 6502, its last access is marked stalled: the cycle went by without it.
    ///  </para>
    /// </remarks>
    public ProcessorCycle LastCycle => _held ? Processor.LastCycle with { IsStalled = true } : Processor.LastCycle;

    /// <summary>
    ///  Presses RESET, alone or with CONTROL. With the environment register's NMI enable set, RESET alone interrupts
    ///  (NMI) and CONTROL-RESET resets the processor; otherwise the key does nothing. In Apple II emulation both
    ///  interrupt, so CONTROL-RESET runs the emulation's reset code, which the NMI vector points at, and the machine
    ///  stays an Apple II.
    /// </summary>
    /// <param name="control">Whether CONTROL is held.</param>
    public void PressReset(bool control)
    {
        if ((Bus.Environment & Apple3Bus.NmiEnable) == 0) { return; }
        if (control && !Bus.AppleIIMode)
        {
            Reset();
        }
        else
        {
            Processor.Signals |= ProcessorSignals.NonMaskableInterrupt;
            _nmi = true;
        }
    }

    /// <summary>
    ///  Resets the processor and the devices a reset reaches, keeping RAM and the VIAs, as CONTROL-RESET does.
    /// </summary>
    public void Reset()
    {
        Bus.ResetDevices();
        Processor.Reset();
    }

    /// <summary>
    ///  Advances the CPU and the devices by one CPU cycle.
    /// </summary>
    public void StepCycle()
    {
        bool irq = Bus.InterruptRequested;
        if (irq != _irq)
        {
            Processor.Signals = irq
                ? Processor.Signals | ProcessorSignals.InterruptRequest
                : Processor.Signals & ~ProcessorSignals.InterruptRequest;

            _irq = irq;
        }

        bool slow = Bus.IsSlow || (_drawing && (Bus.Environment & Apple3Bus.VideoEnable) != 0);
        int units = slow ? SlowCycle : FastCycle;
        bool stepped = Bus.SoftCard is { } card ? StepWithSoftCard(card, units) : StepProcessor();
        Bus.TickDisk(slow);
        if (_nmi && stepped)
        {
            Processor.Signals &= ~ProcessorSignals.NonMaskableInterrupt;
            _nmi = false;
        }

        Time += units;
        Bus.Advance(units);
        _lineTime += units;
        if (_lineTime >= LineLength)
        {
            _lineTime -= LineLength;
            _line = _line + 1 == FrameLines ? 0 : _line + 1;
            if (_line == 0) { Video.EndVerticalBlank(); }
            if (_line < VisibleLines) { Video.StartLine(_line); }
        }

        UpdateBeam();
    }

    /// <summary>
    ///  Executes an exact cycle budget.
    /// </summary>
    /// <param name="cycles">The cycle budget.</param>
    public void Run(ulong cycles)
    {
        for (ulong i = 0; i < cycles; i++) { StepCycle(); }
    }

    /// <summary>
    ///  Runs for a span of emulated time.
    /// </summary>
    /// <param name="duration">The time to run.</param>
    public void Run(TimeSpan duration)
    {
        // 14.318181 MHz, in thousandths of a dot per tick of 100 ns.
        long end = Time + (long)(duration.Ticks * 1_431.8181);
        while (Time < end) { StepCycle(); }
    }

    /// <summary>
    ///  Completes an instruction within an explicit cycle budget.
    /// </summary>
    /// <param name="maximumCycles">The maximum number of cycles.</param>
    /// <returns>The execution result.</returns>
    public ProcessorExecutionResult StepInstruction(int maximumCycles = 32)
    {
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(maximumCycles);
        // The machine's cycles, which go on while a SoftCard holds the 6502.
        ulong cycles = 0;
        bool instruction = Processor.CurrentOpCode is not null;
        for (int i = 0; i < maximumCycles; i++)
        {
            StepCycle();
            cycles++;
            instruction |= Processor.FetchedOpcode;
            if (Processor.Status != ProcessorExecutionStatus.Running)
            {
                return new() { Status = Processor.Status, Cycles = cycles };
            }

            if (instruction && Processor.IsInstructionBoundary)
            {
                return new() { Status = ProcessorExecutionStatus.InstructionComplete, Cycles = cycles };
            }
        }

        return new() { Status = ProcessorExecutionStatus.CycleBudgetExhausted, Cycles = cycles };
    }

    /// <summary>
    ///  Reads the text screen, in the system bank: 40 columns, or 80 when the switches choose 80-column text.
    /// </summary>
    /// <returns>
    ///  24 lines, with inverse and flashing characters shown as normal ones and codes below <c>$20</c> as the capitals
    ///  they stand for. Graphics modes read as the 40-column page. In Apple II emulation the codes are the Apple II's,
    ///  whose inverse and flashing characters are <c>$00-$7F</c>.
    /// </returns>
    public string[] ReadTextScreen()
    {
        bool appleII = Bus.AppleIIMode;
        byte switches = Bus.VideoSwitches;
        bool eighty = (switches & 0x0A) == 0x02;
        bool page2 = (switches & 0x04) != 0;
        int system = Bus.Ram.Length - 0x8000;
        int primary = system + (page2 ? 0x800 : 0x400);
        int secondary = system + (page2 ? 0x400 : 0x800);
        string[] lines = new string[24];
        Span<char> line = stackalloc char[80];
        for (int row = 0; row < 24; row++)
        {
            int start = ((row & 7) << 7) + ((row >> 3) * 40);
            for (int column = 0; column < 40; column++)
            {
                if (eighty)
                {
                    line[column * 2] = Character(Bus.Ram[primary + start + column]);
                    line[(column * 2) + 1] = Character(Bus.Ram[secondary + start + column]);
                }
                else
                {
                    line[column] = Character(Bus.Ram[primary + start + column]);
                }
            }

            lines[row] = new string(line[..(eighty ? 80 : 40)]);
        }

        return lines;

        char Character(byte value)
        {
            int code = value & (appleII && value < 0x80 ? 0x3F : 0x7F);
            return (char)(code < 0x20 ? code + 0x40 : code);
        }
    }

    /// <inheritdoc/>
    string IMachine.Id => "apple3";

    /// <inheritdoc/>
    ICpuDebugView IMachine.Cpu => Processor;

    /// <inheritdoc/>
    IVideoSource IMachine.Video => Video;

    /// <inheritdoc/>
    IReadOnlyList<string> IMachine.MemoryAreas => s_memoryAreas;

    /// <inheritdoc/>
    byte IMachine.Peek(ushort address) => Bus.Peek(address);

    /// <inheritdoc/>
    int IMachine.MemoryArea(ushort address) => (int)Bus.ReadArea(address);

    /// <inheritdoc/>
    void IMachine.QueueKey(byte code) => Bus.QueueKey(code);

    private bool StepProcessor()
    {
        Processor.StepCycle();
        _held = false;
        return true;
    }

    // The SoftCard ///'s Z80 has the bus, or is finishing its last instruction after giving it back. The card holds
    // the 6502 at its next read, which is its next opcode fetch; until the 6502 gets there, the Z80 waits. After the
    // Z80 gives the bus back, both run until the Z80's next access, which WAIT holds. The Z80 keeps its own clock,
    // so it runs the T-states that fit in the cycle's time. Returns whether the 6502 stepped.
    private bool StepWithSoftCard(SoftCard3 card, int units)
    {
        card.Advance(units);
        bool held = card.OwnsBus && Processor.IsInstructionBoundary;
        if (!held) { Processor.StepCycle(); }
        _held = held;
        if (!card.Running || (card.OwnsBus && !held))
        {
            _z80Time = 0;
            return !held;
        }

        ushort next = Processor.Registers.ProgramCounter;
        for (_z80Time += units; _z80Time >= SoftCard3.TState; _z80Time -= SoftCard3.TState)
        {
            card.StepTState(next);
        }

        return !held;
    }

    private void UpdateBeam()
    {
        bool drawing = _line < VisibleLines && _lineTime < VisibleLength;
        if (drawing != _drawing)
        {
            _drawing = drawing;
            Bus.SetDrawing(drawing);
        }

        bool blank = _line >= VisibleLines;
        if (blank != _verticalBlank)
        {
            _verticalBlank = blank;
            Bus.SetVerticalBlank(blank);
        }
    }
}
