// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Cpu.M6502;
using Retrocore.Machines.Chips;

namespace Retrocore.Machines.Commodore.Serial;

/// <summary>
///  A Commodore 1541 or 1540 disk drive on the serial bus: a 6502 running DOS 2.6, 2K of RAM, two VIAs, the gate
///  array and one mechanism.
/// </summary>
/// <remarks>
///  <para>
///   The 1540 works as the 1541's board does, with its own second ROM (<see cref="Cbm1541Roms.Model"/>), for the VIC-20's faster
///   serial timing. The processor and VIAs run at 1 MHz, from the 16 MHz clock that also runs the gate array.
///  </para>
///  <para>
///   VIA 1 (<c>$1800</c>) is the bus: PB0 reads DATA, PB1 pulls it, PB2 reads CLK, PB3 pulls it, PB4 is ATNA, PB5
///   and PB6 read the device number's jumpers, and PB7 and CA1 read ATN, whose rise (the line falling) interrupts.
///   The bus's inputs are inverted, so a 1 is a line held low. While ATN is held and ATNA has not followed it, an
///   XOR gate pulls DATA, so every device answers ATN in hardware.
///  </para>
///  <para>
///   VIA 2 (<c>$1C00</c>) is the disk: port A is the gate array's byte, PB0 and PB1 the stepper's phases, PB2 the
///   spindle motor, PB3 the activity light, PB4 reads write protect (low when protected), PB5 and PB6 the density,
///   and PB7 reads SYNC. CA1 is BYTE READY, CA2 SOE, CB2 the read/write mode. Both VIAs' interrupts are the IRQ.
///   Until the DOS sets VIA 1's port B's direction, its pins float high into the TTL inverters they drive, which hold
///   CLK and DATA low; that is why the 1541's 901229-05 ROM sets that port first. VIA 2's undriven pins read low, as
///   MAME has them: the DOS reads the port at power-on and writes it back when it sets its direction, so a pin read
///   high would turn the motor on and step the head against its stop.
///  </para>
///  <para>
///   A disk going in or out blocks the write protect sensor's light for a moment with its edge, which is how the DOS
///   knows the disk changed and reads its BAM again; so the sensor reads protected for 0.1 second after each.
///  </para>
/// </remarks>
public sealed class Cbm1541
{
    private readonly byte[] _rom = new byte[0x4000];
    private readonly byte[] _ram = new byte[0x800];
    private readonly SerialBus _bus;
    private bool _irq;
    private bool _overflow;

    // The mount the drive last saw, and the microseconds left of the sensor's light being blocked by a disk's edge.
    private int _mount = -1;
    private int _blocked;

    // Whether SO was pulsed within a microsecond and is let go after the processor's next cycle has seen it.
    private bool _releaseOverflow;

    /// <summary>
    ///  Builds a drive and connects it to the bus.
    /// </summary>
    /// <param name="roms">The ROMs.</param>
    /// <param name="bus">The bus.</param>
    /// <param name="address">The device number, 8-11, as the jumpers set it.</param>
    public Cbm1541(Cbm1541Roms roms, SerialBus bus, int address = 8)
    {
        ArgumentNullException.ThrowIfNull(roms);
        ArgumentNullException.ThrowIfNull(bus);
        ArgumentOutOfRangeException.ThrowIfLessThan(address, 8);
        ArgumentOutOfRangeException.ThrowIfGreaterThan(address, 11);
        roms.Low.CopyTo(_rom);
        roms.High.CopyTo(_rom.AsSpan(0x2000));
        _bus = bus;
        Address = address;
        Model = roms.Model;
        Port = bus.Attach();
        Drive = new(
            $"disk{address}",
            $"Drive {address}",
            $"Commodore {Model} disk drive, 5¼-inch single-sided, 35 tracks",
            $"The {Model}'s 6502, VIAs and gate array, on the serial bus as device {address}",
            ["g64", "d64"],
            drive: 0);

        GateArray = new(Drive);
        Bus = new(this);
        Processor = new(Bus, ProcessorVariant.Mos6502);
        Reset();
    }

    /// <summary>
    ///  Gets the device number.
    /// </summary>
    public int Address { get; }

    /// <summary>
    ///  Gets which drive this is: <c>1541</c> or <c>1540</c>.
    /// </summary>
    public string Model { get; }

    /// <summary>
    ///  Gets the drive's connection to the bus.
    /// </summary>
    public SerialPort Port { get; }

    /// <summary>
    ///  Gets the mechanism.
    /// </summary>
    public CommodoreFloppyDrive Drive { get; }

    /// <summary>
    ///  Gets the gate array.
    /// </summary>
    public Cbm1541GateArray GateArray { get; }

    /// <summary>
    ///  Gets the processor's memory map.
    /// </summary>
    public Cbm1541Bus Bus { get; }

    /// <summary>
    ///  Gets the 6502.
    /// </summary>
    public Processor<Cbm1541Bus> Processor { get; }

    /// <summary>
    ///  Gets VIA 1, at <c>$1800</c>: the serial bus.
    /// </summary>
    public Via6522 Via1 { get; } = new();

    /// <summary>
    ///  Gets VIA 2, at <c>$1C00</c>: the disk.
    /// </summary>
    public Via6522 Via2 { get; } = new();

    /// <summary>
    ///  Gets whether the activity light is lit.
    /// </summary>
    public bool ActivityLight => (Via2.PortB & 0x08) != 0;

    /// <summary>
    ///  Gets the 2K of RAM.
    /// </summary>
    public Span<byte> Ram => _ram;

    /// <summary>
    ///  Gets the DOS, 16K from <c>$C000</c>.
    /// </summary>
    internal ReadOnlySpan<byte> Rom => _rom;

    /// <summary>
    ///  Resets the processor and the VIAs, as power coming on or the bus's RESET line does; the disk stays.
    /// </summary>
    public void Reset()
    {
        Via1.Reset();
        Via2.Reset();
        GateArray.Reset();

        // The gate array's BYTE READY is high again, and CA1 follows it, without an edge the VIA counts.
        Via2.CA1 = true;
        Processor.Reset();
        Processor.Signals &= ~(ProcessorSignals.InterruptRequest | ProcessorSignals.SetOverflow);
        _irq = false;
        _overflow = false;
        _releaseOverflow = false;
        UpdateInputs();
        UpdateOutputs();
    }

    /// <summary>
    ///  Runs the processor, the VIAs and the gate array one microsecond.
    /// </summary>
    public void StepCycle()
    {
        // A disk put in or taken out while the drive runs passes the write protect sensor.
        if (_mount != Drive.MountGeneration)
        {
            if (_mount >= 0) { _blocked = 100_000; }
            _mount = Drive.MountGeneration;
        }
        else if (_blocked > 0)
        {
            _blocked--;
        }

        UpdateInputs();
        bool irq = Via1.InterruptRequested || Via2.InterruptRequested;
        if (irq != _irq)
        {
            Processor.Signals = irq
                ? Processor.Signals | ProcessorSignals.InterruptRequest
                : Processor.Signals & ~ProcessorSignals.InterruptRequest;

            _irq = irq;
        }

        Processor.StepCycle();
        if (_releaseOverflow)
        {
            _releaseOverflow = false;
            SetOverflow(asserted: false);
        }

        Via1.Tick();
        Via2.Tick();
        UpdateOutputs();

        GateArray.Advance(ticks: 16);
        UpdateDiskInputs();
        ChangeByteReady();
    }

    /// <summary>
    ///  Sets the levels VIA 1 reads from the bus.
    /// </summary>
    internal void UpdateInputs()
    {
        SerialLines low = _bus.Low;
        bool atn = (low & SerialLines.Atn) != 0;
        int data = (low & SerialLines.Data) != 0 ? 0x01 : 0;
        int clock = (low & SerialLines.Clock) != 0 ? 0x04 : 0;
        Via1.PortBInput = (byte)(data | clock | (((Address - 8) & 3) << 5) | (atn ? 0x80 : 0) | 0x1A);
        if (Via1.CA1 != atn) { Via1.CA1 = atn; }
        UpdateBusOutputs(atn);
    }

    /// <summary>
    ///  Drives the bus from VIA 1, and the mechanism and gate array from VIA 2.
    /// </summary>
    internal void UpdateOutputs()
    {
        UpdateBusOutputs((_bus.Low & SerialLines.Atn) != 0);

        // Port B's undriven pins read what the inputs hold, so those go first.
        UpdateDiskInputs();

        byte disk = Via2.PortB;
        Drive.Motor = (disk & 0x04) != 0;
        Drive.Step(disk & 3);
        Drive.Selected = true;
        GateArray.Zone = (disk >> 5) & 3;
        GateArray.WriteData = Via2.PortAOutput;
        GateArray.ByteReadyEnabled = Via2.CA2Output;
        GateArray.ReadSelect = Via2.CB2Output;
        UpdateDiskInputs();
    }

    // DATA is pulled by PB1, or by the XOR of ATN held and ATNA; CLK by PB3.
    private void UpdateBusOutputs(bool atn)
    {
        byte bus = Via1.PortBOutput;
        bool acknowledge = (bus & 0x10) != 0;
        Port.Pull(SerialLines.Data, (bus & 0x02) != 0 || (atn ^ acknowledge));
        Port.Pull(SerialLines.Clock, (bus & 0x08) != 0);
    }

    // VIA 2 reads the gate array: its byte, SYNC and write protect.
    private void UpdateDiskInputs()
    {
        bool writeProtect = _blocked > 0 || GateArray.WriteProtect;
        Via2.PortBInput = (byte)((writeProtect ? 0 : 0x10) | (GateArray.Sync ? 0x80 : 0));
        Via2.PortAInput = GateArray.ReadData;
    }

    // BYTE READY goes to CA1, which latches the byte as it was when BYTE READY fell within the microsecond, and to the
    // processor's SO.
    private void ChangeByteReady()
    {
        int changes = GateArray.ByteReadyChanges;
        if (changes == 0) { return; }
        bool high = GateArray.ByteReady;
        Via2.PortAInput = GateArray.ByteData;
        if (changes % 2 == 0)
        {
            // A pulse begun and ended within the microsecond: CA1 sees both edges, and SO stays down for the
            // processor's next cycle, so its falling edge is not lost.
            Via2.CA1 = high;
            Via2.CA1 = !high;
            if (high)
            {
                SetOverflow(asserted: true);
                _releaseOverflow = true;
            }
        }

        Via2.CA1 = high;
        if (!_releaseOverflow) { SetOverflow(asserted: !high); }
        Via2.PortAInput = GateArray.ReadData;
    }

    // SO sets the overflow flag on its falling edge, which the processor sees as the signal being asserted.
    private void SetOverflow(bool asserted)
    {
        if (asserted == _overflow) { return; }
        _overflow = asserted;
        Processor.Signals = asserted
            ? Processor.Signals | ProcessorSignals.SetOverflow
            : Processor.Signals & ~ProcessorSignals.SetOverflow;
    }
}
