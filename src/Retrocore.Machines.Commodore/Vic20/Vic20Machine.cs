// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Cpu;
using Retrocore.Cpu.M6502;
using Retrocore.Machines.Chips;
using Retrocore.Machines.Commodore.Serial;
using Retrocore.Machines.Devices;

namespace Retrocore.Machines.Commodore.Vic20;

/// <summary>
///  A caller-clocked Commodore VIC-20, independent of UI and debugger protocols.
/// </summary>
/// <remarks>
///  <para>
///   A NMOS 6502 at 1.02 MHz (NTSC) or 1.11 MHz (PAL), the VIC (6560 or 6561) and two 6522 VIAs. VIA 1's interrupt
///   is the NMI, so RESTORE interrupts through its CA1; VIA 2's is the IRQ, its timer 1 the 60 Hz jiffy clock.
///  </para>
/// </remarks>
public sealed class Vic20Machine : IMachine
{
    private static readonly string[] s_memoryAreas = Enum.GetNames<Vic20MemoryArea>();

    // The drives' 1 MHz against the VIC-20's clock, 14.318 MHz / 14 or 4.434 MHz / 4: each of the computer's cycles
    // adds the first to the count, and each drive cycle takes the second off.
    private readonly long _driveStep;
    private readonly long _cpuStep;
    private long _driveTime;

    private Cbm1541[] _disks = [];
    private bool _irq;
    private bool _nmi;

    /// <summary>
    ///  Constructs a machine at power-on.
    /// </summary>
    /// <param name="roms">The ROMs, whose kernal should be the video standard's.</param>
    /// <param name="standard">NTSC (the 6560) or PAL (the 6561).</param>
    /// <param name="expansion">The RAM in the expansion port.</param>
    /// <param name="cartridge">
    ///  A cartridge, or null. Its ROM takes the blocks it fills from the RAM there, and any RAM it brings is added.
    /// </param>
    public Vic20Machine(
        Vic20Roms roms,
        VicVideoStandard standard = VicVideoStandard.Ntsc,
        Vic20Expansion expansion = Vic20Expansion.None,
        Vic20Cartridge? cartridge = null)
    {
        ArgumentNullException.ThrowIfNull(roms);
        Standard = standard;
        Bus = new(roms, standard, expansion, cartridge);
        Processor = new(Bus, ProcessorVariant.Mos6502);
        Processor.Reset();
        (_driveStep, _cpuStep) = standard == VicVideoStandard.Ntsc ? (14_000_000L, 14_318_181L) : (4_000_000L, 4_433_618L);
        UpdateDevices();
    }

    /// <summary>
    ///  Gets the disk drives on the serial bus, by device number.
    /// </summary>
    public IReadOnlyList<Cbm1541> Disks => _disks;

    /// <summary>
    ///  Connects a 1541 or 1540, as its ROMs say, to the serial bus, at power-on, as plugging one in and switching it
    ///  on does.
    /// </summary>
    /// <param name="roms">The drive's ROMs.</param>
    /// <param name="address">Its device number, 8-11.</param>
    /// <returns>The drive.</returns>
    /// <exception cref="ArgumentException">A drive already has the number.</exception>
    public Cbm1541 AddDisk(Cbm1541Roms roms, int address = 8)
    {
        if (_disks.Any(unit => unit.Address == address))
        {
            throw new ArgumentException($"Device {address} is already on the bus.", nameof(address));
        }

        Cbm1541 added = new(roms, Bus.Serial, address);
        _disks = [.. _disks.Append(added).OrderBy(unit => unit.Address)];
        UpdateDevices();
        return added;
    }

    /// <summary>
    ///  Takes a drive off the serial bus, with any disk in it.
    /// </summary>
    /// <param name="address">Its device number.</param>
    /// <returns>Whether there was one.</returns>
    public bool RemoveDisk(int address)
    {
        if (_disks.FirstOrDefault(unit => unit.Address == address) is not { } unit) { return false; }
        Bus.Serial.Detach(unit.Port);
        _disks = [.. _disks.Where(other => other != unit)];
        UpdateDevices();
        return true;
    }

    private void UpdateDevices() => Devices = [Bus.Cassette, .. _disks.Select(unit => unit.Drive)];

    /// <summary>
    ///  Gets the video standard.
    /// </summary>
    public VicVideoStandard Standard { get; }

    /// <summary>
    ///  Gets the bus clock in hertz.
    /// </summary>
    public double CpuHertz => Bus.Vic.CpuHertz;

    /// <summary>
    ///  Gets the memory and devices.
    /// </summary>
    public Vic20Bus Bus { get; }

    /// <summary>
    ///  Gets the 6502.
    /// </summary>
    public Processor<Vic20Bus> Processor { get; }

    /// <summary>
    ///  Gets the VIC: video, sound and paddles.
    /// </summary>
    public Vic6560 Vic => Bus.Vic;

    /// <summary>
    ///  Gets the keyboard.
    /// </summary>
    public Vic20Keyboard Keyboard => Bus.Keyboard;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   The Datasette, then each disk drive.
    ///  </para>
    /// </remarks>
    public IReadOnlyList<IDevice> Devices { get; private set; } = [];

    /// <summary>
    ///  Gets the Datasette.
    /// </summary>
    public CommodoreDatasette Cassette => Bus.Cassette;

    /// <inheritdoc/>
    public ProcessorCycle LastCycle => Processor.LastCycle;

    /// <summary>
    ///  Resets the 6502, the VIAs and the drives on the serial bus, keeping RAM, as the reset line does. The VIC-20
    ///  has no reset button; the expansion port's reset line, which cartridges and expansion boards switch, pulls it.
    /// </summary>
    public void Reset()
    {
        Bus.ResetDevices();
        Processor.Reset();

        // The reset line is on the serial bus too, and resets the drives.
        foreach (Cbm1541 unit in _disks) { unit.Reset(); }
    }

    /// <summary>
    ///  Advances the CPU and the devices one cycle; <see cref="LastCycle"/> then describes the CPU's bus activity.
    /// </summary>
    public void StepCycle()
    {
        bool irq = Bus.InterruptRequested;
        bool nmi = Bus.NonMaskableInterruptRequested;
        if (irq != _irq || nmi != _nmi)
        {
            ProcessorSignals signals = Processor.Signals;
            signals = irq ? signals | ProcessorSignals.InterruptRequest : signals & ~ProcessorSignals.InterruptRequest;
            signals = nmi ? signals | ProcessorSignals.NonMaskableInterrupt : signals & ~ProcessorSignals.NonMaskableInterrupt;
            Processor.Signals = signals;
            _irq = irq;
            _nmi = nmi;
        }

        Processor.StepCycle();
        Bus.Tick();
        if (_disks.Length == 0) { return; }

        _driveTime += _driveStep;
        while (_driveTime >= _cpuStep)
        {
            _driveTime -= _cpuStep;
            foreach (Cbm1541 unit in _disks) { unit.StepCycle(); }
            Bus.UpdateSerialInputs();
        }
    }

    /// <summary>
    ///  Runs an exact number of cycles.
    /// </summary>
    /// <param name="cycles">The cycles.</param>
    public void Run(ulong cycles)
    {
        for (ulong index = 0; index < cycles; index++) { StepCycle(); }
    }

    /// <summary>
    ///  Runs for a span of emulated time.
    /// </summary>
    /// <param name="duration">The time to run.</param>
    /// <exception cref="ArgumentOutOfRangeException">The duration is negative.</exception>
    public void Run(TimeSpan duration)
    {
        ArgumentOutOfRangeException.ThrowIfLessThan(duration, TimeSpan.Zero);
        Run((ulong)(duration.TotalSeconds * CpuHertz));
    }

    /// <summary>
    ///  Finishes the current instruction, or runs one, within a cycle limit.
    /// </summary>
    /// <param name="maximumCycles">The most cycles to run.</param>
    /// <returns>Why it stopped and the cycles it ran.</returns>
    public ProcessorExecutionResult StepInstruction(int maximumCycles = 32)
    {
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(maximumCycles);
        ulong start = Processor.CycleCount;
        bool instruction = Processor.CurrentOpCode is not null;
        for (int index = 0; index < maximumCycles; index++)
        {
            StepCycle();
            instruction |= Processor.FetchedOpcode;
            if (Processor.Status != ProcessorExecutionStatus.Running)
            {
                return new() { Status = Processor.Status, Cycles = Processor.CycleCount - start };
            }

            if (instruction && Processor.IsInstructionBoundary)
            {
                return new()
                {
                    Status = ProcessorExecutionStatus.InstructionComplete,
                    Cycles = Processor.CycleCount - start
                };
            }
        }

        return new() { Status = ProcessorExecutionStatus.CycleBudgetExhausted, Cycles = Processor.CycleCount - start };
    }

    /// <summary>
    ///  Reads the screen as text, in the upper-case set: screen codes <c>$00-$1F</c> as <c>@A-Z[£]↑←</c> (£ as
    ///  <c>\</c> and the arrows as <c>^</c> and <c>_</c>), <c>$20-$3F</c> as themselves, reversed characters as normal
    ///  ones, and graphics as spaces.
    /// </summary>
    /// <returns>A line for each of the VIC's rows, as wide as its columns.</returns>
    public string[] ReadTextScreen()
    {
        Vic6560 vic = Vic;
        int columns = vic.Columns;
        int rows = vic.Rows;
        string[] lines = new string[rows];
        char[] line = new char[columns];
        for (int row = 0; row < rows; row++)
        {
            for (int column = 0; column < columns; column++)
            {
                int vicAddress = (vic.ScreenAddress + (row * columns) + column) & 0x3FFF;
                int code = ((IVicMemory)Bus).FetchVideo(vicAddress) & 0x7F;
                line[column] = code switch
                {
                    < 0x20 => (char)(code + 0x40),
                    < 0x40 => (char)code,
                    _ => ' '
                };
            }

            lines[row] = new string(line);
        }

        return lines;
    }

    /// <summary>
    ///  Loads a <c>.prg</c> file into RAM, as the kernal's LOAD does.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   A BASIC program, one whose address is BASIC's start on some VIC-20 (<c>$0401</c> with the 3K, <c>$1001</c>
    ///   unexpanded, <c>$1201</c> with block 1), goes to this machine's start (<c>TXTTAB</c>, <c>$2B</c>), its lines are
    ///   linked again for where they now are, and <c>VARTAB</c>, <c>ARYTAB</c> and <c>STREND</c> are set past it, so
    ///   <c>RUN</c> runs it. Anything else is machine code and goes where its address says.
    ///  </para>
    /// </remarks>
    /// <param name="prg">The file's bytes: the address, low byte first, then the program.</param>
    /// <returns>Where it went, and the address past its last byte.</returns>
    /// <exception cref="ArgumentException">The file is too short, or does not fit in RAM.</exception>
    public (ushort Start, ushort End) LoadProgram(ReadOnlySpan<byte> prg)
    {
        if (prg.Length < 3)
        {
            throw new ArgumentException("A .prg file is its address and at least a byte.", nameof(prg));
        }

        int address = prg[0] | (prg[1] << 8);
        bool basic = address is 0x0401 or 0x1001 or 0x1201;
        int start = basic ? Bus.Peek(0x2B) | (Bus.Peek(0x2C) << 8) : address;
        int end = start + prg.Length - 2;
        if (end > 0x10000) { throw new ArgumentException("The program runs past $FFFF.", nameof(prg)); }
        Bus.Load((ushort)start, prg[2..]);
        if (!basic) { return ((ushort)start, (ushort)end); }

        // Each line is its link, its number, its text and a zero; a zero link ends the program.
        int line = start;
        while (line + 4 < end && (Bus.Peek((ushort)line) | Bus.Peek((ushort)(line + 1))) != 0)
        {
            int next = line + 4;
            while (next < end && Bus.Peek((ushort)next) != 0) { next++; }
            next++;
            Bus.Write((ushort)line, (byte)next);
            Bus.Write((ushort)(line + 1), (byte)(next >> 8));
            line = next;
        }

        foreach (ushort pointer in (ReadOnlySpan<ushort>)[0x2D, 0x2F, 0x31])
        {
            Bus.Write(pointer, (byte)end);
            Bus.Write((ushort)(pointer + 1), (byte)(end >> 8));
        }

        return ((ushort)start, (ushort)end);
    }

    /// <inheritdoc/>
    string IMachine.Id => "vic20";

    /// <inheritdoc/>
    ICpuDebugView IMachine.Cpu => Processor;

    /// <inheritdoc/>
    IVideoSource IMachine.Video => Vic;

    /// <inheritdoc/>
    IReadOnlyList<string> IMachine.MemoryAreas => s_memoryAreas;

    /// <inheritdoc/>
    byte IMachine.Peek(ushort address) => Bus.Peek(address);

    /// <inheritdoc/>
    int IMachine.MemoryArea(ushort address) => (int)Bus.Area(address);

    /// <inheritdoc/>
    void IMachine.QueueKey(byte code) => Bus.Keyboard.Type(code);
}
