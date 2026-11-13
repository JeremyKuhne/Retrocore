// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Devices;
using Retrocore.Machines.Trs80;

namespace Retrocore.Machines.Coco;

/// <summary>
///  The Color Computer's disk controller cartridge (26-3022 and the FD-502's): a WD1793, the drive control
///  register, and Disk Extended Color BASIC's ROM in the cartridge slot.
/// </summary>
/// <remarks>
///  <para>
///   Writing <c>$FF40</c> (mirrored to <c>$FF47</c>) sets the drive control register: bits 0-2 select drives 0-2,
///   bit 6 drive 3 or, with another drive, side 1; bit 3 runs the motors; bit 5 selects double density and lets the
///   WD1793's INTRQ drive NMI; bit 7 lets the WD1793's DRQ release HALT. The WD1793's status or command, track,
///   sector and data registers are <c>$FF48-$FF4B</c>, mirrored to <c>$FF4F</c>.
///  </para>
///  <para>
///   Disk BASIC reads and writes sectors with bit 7 set: the CPU halts until each byte is ready, so a tight loop
///   moves the data, and INTRQ at the command's end clears bit 7 and interrupts the loop through NMI.
///  </para>
/// </remarks>
public sealed class CocoDiskController
{
    private const byte HaltEnable = 0x80;
    private const byte DriveThreeOrSide = 0x40;
    private const byte DoubleDensity = 0x20;
    private const byte Motor = 0x08;

    private byte _control;

    /// <summary>
    ///  Creates the controller with its ROM.
    /// </summary>
    /// <param name="diskBasic">Disk Extended Color BASIC, 8 KB.</param>
    /// <exception cref="ArgumentException">The ROM is not 8 KB.</exception>
    public CocoDiskController(ReadOnlySpan<byte> diskBasic)
    {
        if (diskBasic.Length != CocoRoms.BasicSize)
        {
            throw new ArgumentException("Disk BASIC's ROM is 8 KB.", nameof(diskBasic));
        }

        Rom = new(diskBasic, autostart: false);

        // The WD1793 is clocked at 1 MHz; the time units are twice the CPU's slow clock, about 1.79 MHz.
        Chip = new(Trs80Doubler.None, (int)(2 * CocoTiming.ClockHertz));
        Trs80FloppyDrive[] drives = new Trs80FloppyDrive[Trs80DiskController.DriveCount];
        for (int drive = 0; drive < drives.Length; drive++) { drives[drive] = new(Chip, drive, Info(drive)); }
        Drives = drives;
        Reset();
    }

    /// <summary>
    ///  Gets the cartridge's ROM.
    /// </summary>
    public CocoCartridge Rom { get; }

    /// <summary>
    ///  Gets the WD1793.
    /// </summary>
    public Trs80DiskController Chip { get; }

    /// <summary>
    ///  Gets the four drives.
    /// </summary>
    public IReadOnlyList<Trs80FloppyDrive> Drives { get; }

    /// <summary>
    ///  Gets the drive control register's last value.
    /// </summary>
    public byte Control => _control;

    /// <summary>
    ///  Gets whether the controller holds NMI: INTRQ while bit 5 is set.
    /// </summary>
    public bool NonMaskableInterrupt => Chip.InterruptRequest && (_control & DoubleDensity) != 0;

    /// <summary>
    ///  Gets whether the controller holds HALT: bit 7 is set and the WD1793 is not asking for a byte.
    /// </summary>
    public bool Halt => (_control & HaltEnable) != 0 && !Chip.DataRequest;

    /// <summary>
    ///  Reads <c>$FF40-$FF5F</c>: the WD1793 at <c>$FF48-$FF4F</c>; the control register reads the floating bus.
    /// </summary>
    /// <param name="address">The address.</param>
    /// <param name="floating">The floating bus's value.</param>
    /// <returns>The value.</returns>
    internal byte Read(ushort address, byte floating)
    {
        if ((address & 0x18) != 0x08) { return floating; }
        byte value = Chip.Read(address & 3);
        Update();
        return value;
    }

    /// <summary>
    ///  Reads without side effects.
    /// </summary>
    /// <param name="address">The address.</param>
    /// <param name="floating">The floating bus's value.</param>
    /// <returns>The value.</returns>
    internal byte Peek(ushort address, byte floating) =>
        (address & 0x18) == 0x08 ? Chip.Peek(address & 3) : floating;

    /// <summary>
    ///  Writes <c>$FF40-$FF5F</c>.
    /// </summary>
    /// <param name="address">The address.</param>
    /// <param name="value">The value.</param>
    internal void Write(ushort address, byte value)
    {
        switch (address & 0x18)
        {
            case 0x00:
                _control = value;
                Select();
                break;
            case 0x08:
                Chip.Write(address & 3, value);
                break;
        }

        Update();
    }

    /// <summary>
    ///  Advances the WD1793 and the disks.
    /// </summary>
    /// <param name="units">Time units.</param>
    internal void Tick(int units)
    {
        for (int unit = 0; unit < units; unit++) { Chip.Tick(); }
        Update();
    }

    /// <summary>
    ///  Clears the control register, stopping the motors.
    /// </summary>
    internal void Reset()
    {
        _control = 0;
        Select();
    }

    private static DeviceInfo Info(int drive) => new()
    {
        Name = $"Drive {drive}",
        Description = "5¼-inch floppy drive",
        Controller = "WD1793 in the disk controller cartridge",
        Formats = ["dsk", "jvc"],
        Operations = MediaOperations.Insert | MediaOperations.Eject | MediaOperations.WriteProtect,
        Tracks = 40,

        // Drive 3's select line is the other drives' side select, so drive 3 is single-sided.
        Sides = drive == 3 ? 1 : 2
    };

    // Drive selects: bit 2 drive 2, bit 1 drive 1, bit 0 drive 0, else bit 6 drive 3. Bit 6 with drives 0-2 is
    // side 1, as on double-sided drives.
    private void Select()
    {
        int drive = _control switch
        {
            _ when (_control & 0x04) != 0 => 2,
            _ when (_control & 0x02) != 0 => 1,
            _ when (_control & 0x01) != 0 => 0,
            _ when (_control & DriveThreeOrSide) != 0 => 3,
            _ => -1
        };

        int side = drive is >= 0 and < 3 && (_control & DriveThreeOrSide) != 0 ? 1 : 0;
        Chip.Control(drive, side, motor: (_control & Motor) != 0, doubleDensity: (_control & DoubleDensity) != 0);
    }

    // INTRQ ends halting: the command is over, so no more bytes come.
    private void Update()
    {
        if (Chip.InterruptRequest) { _control &= unchecked((byte)~HaltEnable); }
    }
}
