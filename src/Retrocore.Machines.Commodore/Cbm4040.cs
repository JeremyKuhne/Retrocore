// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Cpu.M6502;
using Retrocore.Machines.Chips;

namespace Retrocore.Machines.Commodore;

/// <summary>
///  A Commodore 4040 or 2040 dual disk drive on the IEEE-488 bus: two processors sharing four 1K buffers, one
///  running the DOS and the bus, the other the two mechanisms.
/// </summary>
/// <remarks>
///  <para>
///   The 2040 is the same board with DOS 1.2 and its own controller ROM, as MAME's <c>c2040</c> builds it; the
///   ROMs say which the unit is (<see cref="Cbm4040Roms.Model"/>).
///  </para>
///  <para>
///   The DOS processor, a 6502, talks to the bus through two 6532s. The first's port A reads the data lines and its
///   port B drives them. The second's port A has the handshakes: ATNA, DACO, RFDO, EOI and DAV out on PA0-PA4, and
///   EOI, DAV and inverted ATN in on PA5-PA7, whose edge interrupts. Its port B reads the device number on PB0-PB2
///   and NDAC and NRFD on PB6 and PB7, and lights the LEDs from PB3-PB5. Gates answer ATN in hardware, holding NRFD
///   and NDAC until ATNA follows it.
///  </para>
///  <para>
///   The controller, a 6504, runs the 6530's ROM. The 6530's port A is the byte to write, PB0 selects the
///   mechanism, PB1-PB2 the speed zone, PB3 reads write protect, PB6 SYNC, and PB7 is its timer's interrupt. The
///   VIA's port A reads the decoded byte, its port B drives the two steppers and motors, CA1 takes READY, CB1
///   ERROR, CA2 sets MODE SEL and CB2 R/W SEL. Both processors run at 1 MHz, from the 16 MHz clock that also runs
///   the read/write logic.
///  </para>
/// </remarks>
public sealed class Cbm4040
{
    private readonly byte[] _dos;
    private readonly byte[] _controller;
    private readonly byte[][] _buffers = [new byte[0x400], new byte[0x400], new byte[0x400], new byte[0x400]];
    private readonly Ieee488Bus _bus;
    private bool _dosIrq;

    // Whether SO was asserted for an interface clear and is let go after the DOS processor's next cycle.
    private bool _releaseOverflow;
    private bool _controllerIrq;

    /// <summary>
    ///  Builds a unit and connects it to the bus.
    /// </summary>
    /// <param name="roms">The ROMs.</param>
    /// <param name="bus">The bus.</param>
    /// <param name="address">The device number, 8-15.</param>
    public Cbm4040(Cbm4040Roms roms, Ieee488Bus bus, int address = 8)
    {
        ArgumentNullException.ThrowIfNull(roms);
        ArgumentNullException.ThrowIfNull(bus);
        ArgumentOutOfRangeException.ThrowIfLessThan(address, 8);
        ArgumentOutOfRangeException.ThrowIfGreaterThan(address, 15);
        _dos = roms.Dos.ToArray();
        _controller = roms.Controller.ToArray();
        _bus = bus;
        Address = address;
        Port = bus.Attach();
        Model = roms.Model;
        Drive0 = new(address, drive: 0, Model);
        Drive1 = new(address, drive: 1, Model);
        Fdc = new(roms.Gcr, Drive0, Drive1);
        DosBus = new(this);
        ControllerBus = new(this);
        DosProcessor = new(DosBus, ProcessorVariant.Mos6502);
        ControllerProcessor = new(ControllerBus, ProcessorVariant.Mos6502);
        Reset();
    }

    /// <summary>
    ///  Gets the device number.
    /// </summary>
    public int Address { get; }

    /// <summary>
    ///  Gets which drive the unit is: <c>4040</c> or <c>2040</c>.
    /// </summary>
    public string Model { get; }

    /// <summary>
    ///  Gets the unit's connection to the bus.
    /// </summary>
    public Ieee488Port Port { get; }

    /// <summary>
    ///  Gets drive 0.
    /// </summary>
    public CommodoreFloppyDrive Drive0 { get; }

    /// <summary>
    ///  Gets drive 1.
    /// </summary>
    public CommodoreFloppyDrive Drive1 { get; }

    /// <summary>
    ///  Gets the read/write logic.
    /// </summary>
    public Cbm4040Fdc Fdc { get; }

    /// <summary>
    ///  Gets the DOS processor's memory map.
    /// </summary>
    public Cbm4040DosBus DosBus { get; }

    /// <summary>
    ///  Gets the controller's memory map.
    /// </summary>
    public Cbm4040ControllerBus ControllerBus { get; }

    /// <summary>
    ///  Gets the DOS processor, a 6502.
    /// </summary>
    public Processor<Cbm4040DosBus> DosProcessor { get; }

    /// <summary>
    ///  Gets the controller, a 6504.
    /// </summary>
    public Processor<Cbm4040ControllerBus> ControllerProcessor { get; }

    /// <summary>
    ///  Gets the 6532 at UC1, on the data lines.
    /// </summary>
    public Riot6532 Riot0 { get; } = new();

    /// <summary>
    ///  Gets the 6532 at UE1, on the handshakes.
    /// </summary>
    public Riot6532 Riot1 { get; } = new();

    /// <summary>
    ///  Gets the controller's 6530.
    /// </summary>
    public Miot6530 Miot { get; } = new();

    /// <summary>
    ///  Gets the controller's VIA.
    /// </summary>
    public Via6522 Via { get; } = new();

    /// <summary>
    ///  Gets whether the error LED is lit.
    /// </summary>
    public bool ErrorLight => (Riot1.PortBOutput & 0x20) != 0;

    /// <summary>
    ///  Gets the DOS.
    /// </summary>
    internal ReadOnlySpan<byte> Dos => _dos;

    /// <summary>
    ///  Gets the controller's ROM.
    /// </summary>
    internal ReadOnlySpan<byte> Controller => _controller;

    /// <summary>
    ///  Gets one of the shared buffers.
    /// </summary>
    /// <param name="index">0-3.</param>
    /// <returns>Its 1K.</returns>
    public Span<byte> Buffer(int index) => _buffers[index];

    /// <summary>
    ///  Takes IFC, the bus's interface clear, as the PET's reset line drives it: the DOS processor's SO input is
    ///  pulsed, and the DOS, which polls its overflow flag for it, goes back to waiting on the bus. Neither processor
    ///  is reset, and the disks and buffers stay, as MAME's <c>c2040</c> takes IFC.
    /// </summary>
    public void InterfaceClear()
    {
        DosProcessor.Signals |= ProcessorSignals.SetOverflow;
        _releaseOverflow = true;
    }

    /// <summary>
    ///  Resets both processors and their chips, as the drive's power coming on does; the disks stay.
    /// </summary>
    public void Reset()
    {
        UpdateInputs();
        Riot0.Reset();
        Riot1.Reset();
        Miot.Reset();
        Via.Reset();
        Fdc.Reset();
        DosProcessor.Reset();
        ControllerProcessor.Reset();

        // A processor's reset keeps its inputs, and the chips' resets release the interrupt, so the lines go high here
        // with the caches that follow them.
        DosProcessor.Signals &= ~ProcessorSignals.InterruptRequest;
        ControllerProcessor.Signals &= ~ProcessorSignals.InterruptRequest;
        _dosIrq = false;
        _controllerIrq = false;
        UpdateInputs();
        UpdateOutputs();
        UpdateControllerOutputs();
        UpdateControllerInputs();
    }

    /// <summary>
    ///  Runs both processors, their chips and the read/write logic one microsecond.
    /// </summary>
    public void StepCycle()
    {
        UpdateInputs();
        UpdateOutputs();

        bool irq = Riot1.InterruptRequested;
        if (irq != _dosIrq)
        {
            DosProcessor.Signals = irq
                ? DosProcessor.Signals | ProcessorSignals.InterruptRequest
                : DosProcessor.Signals & ~ProcessorSignals.InterruptRequest;

            _dosIrq = irq;
        }

        DosProcessor.StepCycle();
        if (_releaseOverflow)
        {
            // SO acts on its edge, which the cycle just taken sampled.
            DosProcessor.Signals &= ~ProcessorSignals.SetOverflow;
            _releaseOverflow = false;
        }

        Riot0.Tick();
        Riot1.Tick();

        irq = Miot.InterruptRequested;
        if (irq != _controllerIrq)
        {
            ControllerProcessor.Signals = irq
                ? ControllerProcessor.Signals | ProcessorSignals.InterruptRequest
                : ControllerProcessor.Signals & ~ProcessorSignals.InterruptRequest;

            _controllerIrq = irq;
        }

        ControllerProcessor.StepCycle();
        Miot.Tick();
        Via.Tick();
        UpdateControllerOutputs();

        Fdc.Advance(ticks: 16);
        UpdateControllerInputs();
        Pulse(Fdc.Ready, Fdc.ReadyChanges, ready: true);
        Pulse(Fdc.Error, Fdc.ErrorChanges, ready: false);
    }

    // Carries READY to CA1 and ERROR to CB1, an edge and its return within the microsecond both.
    private void Pulse(bool level, int changes, bool ready)
    {
        if (changes == 0) { return; }
        if (changes % 2 == 0)
        {
            Set(!level);
        }

        Set(level);

        void Set(bool value)
        {
            if (ready) { Via.CA1 = value; }
            else { Via.CB1 = value; }
        }
    }

    /// <summary>
    ///  Sets the levels the DOS processor's 6532s read from the bus.
    /// </summary>
    internal void UpdateInputs()
    {
        bool atn = _bus.High(Ieee488Lines.Atn);
        Riot0.PortAInput = _bus.Data;
        int eoi = _bus.High(Ieee488Lines.Eoi) ? 0x20 : 0;
        int dav = _bus.High(Ieee488Lines.Dav) ? 0x40 : 0;
        Riot1.SetPortA((byte)(eoi | dav | (atn ? 0 : 0x80)));
        int ndac = _bus.High(Ieee488Lines.Ndac) ? 0x40 : 0;
        int nrfd = _bus.High(Ieee488Lines.Nrfd) ? 0x80 : 0;
        Riot1.PortBInput = (byte)((Address - 8) | ndac | nrfd);
    }

    /// <summary>
    ///  Drives the bus from the DOS processor's 6532s and the ATN gates.
    /// </summary>
    internal void UpdateOutputs()
    {
        byte handshake = Riot1.PortAOutput;
        bool atna = (handshake & 0x01) != 0;
        bool daco = (handshake & 0x02) != 0;
        bool rfdo = (handshake & 0x04) != 0;
        bool atn = _bus.High(Ieee488Lines.Atn);

        Port.Data = Riot0.PortBOutput;
        Port.Drive(Ieee488Lines.Eoi, (handshake & 0x08) != 0);
        Port.Drive(Ieee488Lines.Dav, (handshake & 0x10) != 0);

        // Until ATNA follows ATN, the gates hold NRFD released and NDAC low.
        bool nrfd = !(!(!(atn && atna) && rfdo) || !(atn || atna));
        bool ndac = !(daco || !(atn || atna));
        Port.Drive(Ieee488Lines.Nrfd, nrfd);
        Port.Drive(Ieee488Lines.Ndac, ndac);
    }

    /// <summary>
    ///  Sets the levels the controller's 6530 and VIA read from the read/write logic.
    /// </summary>
    internal void UpdateControllerInputs()
    {
        Miot.PortBInput = (byte)(0xB7 | (Fdc.WriteProtect ? 0x08 : 0) | (Fdc.Sync ? 0x40 : 0));
        Via.PortAInput = Fdc.ReadData;
    }

    /// <summary>
    ///  Sets the read/write logic and the mechanisms from the controller's 6530 and VIA.
    /// </summary>
    internal void UpdateControllerOutputs()
    {
        byte select = Miot.PortBOutput;
        Fdc.WriteData = Miot.PortAOutput;
        Fdc.DriveSelect = select & 1;
        Fdc.Zone = (select >> 1) & 3;
        Fdc.ModeSelect = Via.CA2Output;
        Fdc.ReadSelect = Via.CB2Output;

        byte mechanisms = Via.PortBOutput;
        Drive0.Motor = (mechanisms & 0x20) == 0;
        Drive1.Motor = (mechanisms & 0x10) == 0;
        Drive0.Step((mechanisms >> 2) & 3);
        Drive1.Step(mechanisms & 3);
        Drive0.Selected = Fdc.DriveSelect == 0;
        Drive1.Selected = Fdc.DriveSelect == 1;
    }
}
