// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Cpu.M6502;
using Retrocore.Machines.Chips;
using Retrocore.Machines.Devices;

namespace Retrocore.Machines.Atari;

/// <summary>
///  The Atari 810 disk drive at the hardware level: its 6507 running the drive's 2 KB ROM, a 6532 RIOT, 128 bytes of
///  6810 RAM, an FD1771 and the mechanism.
/// </summary>
/// <remarks>
///  <para>
///   The wiring follows the Altirra Hardware Reference Manual, 10.10. The 6507 runs at 500 kHz with no interrupts.
///   The RIOT's port A reads the FD1771's DRQ (PA7) and INTRQ (PA6), the write-protect sensor (PA4) and the drive
///   code switches (PA2 and PA0: both set for <c>D1:</c>, PA2 for <c>D2:</c>, neither for <c>D3:</c>, PA0 for
///   <c>D4:</c>), and drives the spindle motor (PA1). Its port B reads the computer's serial data, inverted (PB7), the
///   command line (PB6) and, low, the computer's power (PB1), drives the stepper's four phases (PB2-PB5), and sends the
///   drive's serial data (PB0), which the firmware shifts out bit by bit.
///  </para>
///  <para>
///   The RIOT's interrupt output is the FD1771's index pulse: the 810 can't see the disk's index hole, so the
///   firmware's timer tells the controller when to give up on a sector. Nor does the FD1771 step the head: the
///   firmware turns the stepper's phases itself, two adjacent ones at a time, one phase a track (phases 1 and 4 on
///   track 0), and finds track 0 by stepping out against the stop. The disk turns at 288 rpm while PA1 is set.
///  </para>
///  <para>
///   The drive is powered on when it's built, and has run its start-up (stepping the head out to track 0) by the
///   time the computer starts, as when it's switched on first.
///  </para>
/// </remarks>
public sealed class Atari810 : AtariDiskDrive
{
    /// <summary>
    ///  The 6507's clock.
    /// </summary>
    public const int ClockHertz = 500_000;

    /// <summary>
    ///  The size of the firmware.
    /// </summary>
    public const int RomSize = 0x800;

    private const int RotationsPerMinute = 288;
    private const int LastTrack = 41;
    // Long enough for the firmware's start-up: the head stepped out and in, then the motor's run-on of two Restores,
    // each 255 steps at 12 ms, before it parks.
    private const int WarmUpCycles = 8 * ClockHertz;

    private readonly byte[] _rom;
    private readonly byte[] _ram = new byte[128];
    private readonly char _revision;
    private readonly AtariBus? _bus;
    private Atari810Disk? _disk;
    private bool _motor;
    private int _phases;
    private bool _busy;

    /// <summary>
    ///  Builds a drive, powered on, on a machine's serial bus.
    /// </summary>
    /// <param name="bus">The machine's bus, for the serial lines; null for a drive on its own.</param>
    /// <param name="number">The drive number its switches set, 1-4: <c>D1:</c> to <c>D4:</c>.</param>
    /// <param name="rom">The 2 KB firmware.</param>
    /// <exception cref="ArgumentException">The firmware isn't 2 KB.</exception>
    internal Atari810(AtariBus? bus, int number, ReadOnlySpan<byte> rom) : base(number, "Atari 810: 6507, 6532 and FD1771")
    {
        if (rom.Length != RomSize) { throw new ArgumentException("The 810's firmware is 2 KB.", nameof(rom)); }
        _bus = bus;
        _rom = rom.ToArray();
        _revision = Atari810Firmware.Revision(rom);
        Fdc = new(ClockHertz, rotationsPerMinute: RotationsPerMinute, sensorsWired: false);
        Fdc.Control(drive: 0, side: 0, motor: false, doubleDensity: false);
        Bus = new(this);
        Processor = new(Bus, ProcessorVariant.Mos6502);
        PowerOn();
        for (int cycle = 0; cycle < WarmUpCycles; cycle++) { StepCycle(); }
    }

    /// <summary>
    ///  Gets the firmware's revision: <c>'B'</c>, <c>'C'</c>, <c>'E'</c> or <c>'?'</c>.
    /// </summary>
    public char Revision => _revision;

    /// <summary>
    ///  Gets the 6507's memory map.
    /// </summary>
    public Atari810Bus Bus { get; }

    /// <summary>
    ///  Gets the 6507.
    /// </summary>
    public Processor<Atari810Bus> Processor { get; }

    /// <summary>
    ///  Gets the 6532.
    /// </summary>
    public Riot6532 Riot { get; } = new();

    /// <summary>
    ///  Gets the FD1771.
    /// </summary>
    public WesternDigitalFloppyDiskController Fdc { get; }

    /// <summary>
    ///  Gets the 6810's 128 bytes.
    /// </summary>
    public Span<byte> Ram => _ram;

    /// <summary>
    ///  Gets the track the head is on.
    /// </summary>
    public int Track { get; private set; }

    /// <summary>
    ///  Gets whether the spindle motor turns.
    /// </summary>
    public bool Motor => _motor;

    /// <summary>
    ///  Gets the level the drive puts on the serial bus's data-in line: high is idle.
    /// </summary>
    public bool SerialOutput => (Riot.PortBOutput & 0x01) != 0;

    /// <summary>
    ///  Gets or sets the level of the computer's serial data-out line, for a drive with no machine.
    /// </summary>
    public bool SerialInput { get; set; } = true;

    /// <summary>
    ///  Gets or sets whether the command line is asserted, for a drive with no machine.
    /// </summary>
    public bool CommandLine { get; set; }

    /// <inheritdoc/>
    public override DeviceActivity Activity => Fdc.Activity(0);

    /// <inheritdoc/>
    public override DiskHead Head => new(_motor, Fdc.IsBusy, Track, 0, Fdc.IsBusy ? Fdc.Sector : null);

    /// <summary>
    ///  Gets the firmware.
    /// </summary>
    internal ReadOnlySpan<byte> Rom => _rom;

    /// <summary>
    ///  Gets or sets what's called before each instruction the 6507 starts, for tracing.
    /// </summary>
    internal Action? InstructionStarting { get; set; }

    /// <summary>
    ///  Switches the drive off and on: the 6507 and the RIOT reset, the FD1771 stops what it was doing (its registers
    ///  keep their values) and the RAM clears; the head stays where it is.
    /// </summary>
    public void PowerOn()
    {
        // RAM powers on in no fixed state; MAME's is clear.
        Riot.Ram.Clear();
        _ram.AsSpan().Clear();

        // The RIOT's pins float high until the FD1771 comes out of reset, so PA7 falls once (as MAME has it), and the
        // edge flag is set.
        Riot.PortAInput = 0xFF;
        Riot.Reset();
        Fdc.Write(0, 0xD0);
        _phases = 0;
        _motor = false;
        Fdc.Control(drive: 0, side: 0, motor: false, doubleDensity: false);
        UpdateInputs();
        Processor.Reset();
    }

    /// <summary>
    ///  Runs the drive one 6507 cycle, 2 µs.
    /// </summary>
    public void StepCycle()
    {
        UpdateInputs();
        if (InstructionStarting is { } trace && Processor.IsInstructionBoundary) { trace(); }
        Processor.StepCycle();
        Riot.Tick();
        Fdc.IndexPulse = Riot.InterruptRequested;
        Fdc.Tick();
        UpdateOutputs();
        if (Fdc.IsBusy != _busy)
        {
            _busy = Fdc.IsBusy;
            _disk?.Sync();
        }
    }

    /// <summary>
    ///  Sets the levels the RIOT reads: the controller, the sensors, the switches and the serial bus.
    /// </summary>
    internal void UpdateInputs()
    {
        int code = Number switch
        {
            1 => 0x05,
            2 => 0x04,
            3 => 0x00,
            _ => 0x01
        };

        // PA5 is a jumper, left open; PA3 and PA1 are outputs.
        int a = 0x2A | code;
        if (Fdc.DataRequest) { a |= 0x80; }
        if (Fdc.InterruptRequest) { a |= 0x40; }
        if (Disk?.IsWriteProtected == true) { a |= 0x10; }
        Riot.SetPortA((byte)a);

        bool data = _bus?.Pokey.SerialOutputLevel ?? SerialInput;
        bool command = _bus?.Sio.CommandLine ?? CommandLine;
        // PB1 is low while the computer is on: the firmware waits, with the motor off, while it reads high. (The HRM's
        // Table 61 gives "1 = ready", but the firmware's poll loop treats a set PB1 as the computer off.)
        Riot.PortBInput = (byte)(0x3D | (data ? 0 : 0x80) | (command ? 0x40 : 0));
    }

    /// <summary>
    ///  Follows the RIOT's outputs: the spindle motor and the stepper.
    /// </summary>
    internal void UpdateOutputs()
    {
        bool motor = (Riot.PortAOutput & 0x02) != 0;
        if (motor != _motor)
        {
            _motor = motor;
            Fdc.Control(drive: 0, side: 0, motor, doubleDensity: false);
        }

        int phases = (Riot.PortBOutput >> 2) & 0x0F;
        if (phases != _phases)
        {
            _phases = phases;
            Step(phases);
        }
    }

    /// <inheritdoc/>
    private protected override void Changed()
    {
        _disk = Disk is { } image ? new(image, _revision) : null;
        Fdc.Insert(0, _disk?.Floppy);
    }

    // Two adjacent phases hold the head on a track: phases 1 and 4 (PB2 and PB5) on track 0, then 1 and 2 on track 1,
    // 2 and 3 on track 2, 3 and 4 on track 3, around again. A pair one phase on pulls the head a track in, one phase
    // back a track out. Other patterns (one phase, none, or opposite ones) leave it. The firmware parks the head on
    // track 39 with the phases off, and turns on phases 3 and 4 to hold it there again.
    private void Step(int phases)
    {
        int pair = phases switch
        {
            0b1001 => 3,
            0b0011 => 0,
            0b0110 => 1,
            0b1100 => 2,
            _ => -1
        };

        if (pair < 0) { return; }
        int difference = (pair - (Track + 3)) & 3;
        if (difference == 1)
        {
            Track = Math.Min(Track + 1, LastTrack);
        }
        else if (difference == 3)
        {
            Track = Math.Max(Track - 1, 0);
        }

        Fdc.SetCylinder(0, Track);
    }
}
