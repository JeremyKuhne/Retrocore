// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Devices;
using Retrocore.Media.Floppy;

namespace Retrocore.Machines.Chips;

/// <summary>
///  A Western Digital floppy disk controller, the FD1771 or one of the FD179x and WD179x family, with up to four drives:
///  four registers (command and status, track, sector, data), and the drive, side, density and motor selects that the
///  board around it decodes.
/// </summary>
/// <remarks>
///  <para>
///   The TRS-80 Model I's Expansion Interface has an FD1771, which a doubler's WD1791 joins for double density; the
///   Model III, 4 and II and the Color Computer's disk controller cartridge have an FD179x or WD179x.
///  </para>
///  <para>
///   5¼-inch disks turn at 300 rpm. A sector passes the head at its place among the track's sectors after the
///   index hole, so a read waits for its sector, and data moves one byte per byte time (64 µs in single
///   density, 32 in double) through DRQ: a byte the program has not taken when the next arrives is lost data.
///   Steps take the chip's step rate. A board either runs the motors while its control register says
///   so (<see cref="Control"/>) or starts them for 3 seconds at each select (<see cref="SelectTimed"/>).
///  </para>
/// </remarks>
public sealed partial class WesternDigitalFloppyDiskController
{
    /// <summary>
    ///  The drives.
    /// </summary>
    public const int DriveCount = 4;

    // Status bits.
    private const byte Busy = 0x01;
    private const byte IndexOrRequest = 0x02;
    private const byte TrackZeroOrLost = 0x04;
    private const byte CrcError = 0x08;
    private const byte SeekError = 0x10;
    private const byte HeadLoaded = 0x20;
    private const byte WriteProtect = 0x40;
    private const byte NotReady = 0x80;

    private readonly FloppyDisk?[] _disks = new FloppyDisk?[DriveCount];
    private readonly int[] _cylinders = new int[DriveCount];
    private readonly int _clockHertz;
    private readonly bool _wd179x;
    private readonly bool _eightInch;
    private readonly int _cyclesPerMillisecond;
    private readonly int _rotationCycles;
    private readonly int _indexPulseCycles;
    private readonly int _settleCycles;
    private bool _motorHeld;
    private int _selected = -1;
    private int _motorCycles;
    private long _rotation;

    private byte _status;
    private byte _command;
    private bool _typeOne = true;
    private bool _doubleDensity;
    private bool _request;

    // The command in progress.
    private Phase _phase;
    private int _wait;
    private int _indexPulses;
    private bool _wasIndex;
    private FloppySector? _sector;

    // The disk the sector was found on, which a write goes to only while that disk is still under the head.
    private FloppyDisk? _sectorDisk;
    private byte[] _buffer = [];
    private int _position;
    private int _steps;
    private List<byte>? _trackBytes;

    /// <summary>
    ///  Creates the controller.
    /// </summary>
    /// <param name="clockHertz">The rate <see cref="Tick"/> is called at.</param>
    /// <param name="wd179x">
    ///  Whether the controller is an FD179x or WD179x in both densities rather than an FD1771, which behaves as a
    ///  doubler's WD1791 while double density is selected.
    /// </param>
    /// <param name="eightInch">
    ///  Whether the drives are 8-inch, as the TRS-80 Model II's are: 360 rpm, twice the data rate, and the controller
    ///  clocked at 2 MHz, which halves its step rates.
    /// </param>
    internal WesternDigitalFloppyDiskController(int clockHertz, bool wd179x = false, bool eightInch = false)
    {
        _clockHertz = clockHertz;
        _wd179x = wd179x;
        _eightInch = eightInch;
        _cyclesPerMillisecond = clockHertz / 1000;
        _rotationCycles = eightInch ? clockHertz / 6 : 200 * _cyclesPerMillisecond;
        _indexPulseCycles = 4 * _cyclesPerMillisecond;
        _settleCycles = 15 * _cyclesPerMillisecond;
    }

    /// <summary>
    ///  Gets the track register.
    /// </summary>
    public byte Track { get; private set; }

    /// <summary>
    ///  Gets the sector register.
    /// </summary>
    public byte Sector { get; private set; }

    /// <summary>
    ///  Gets the data register.
    /// </summary>
    public byte Data { get; private set; }

    /// <summary>
    ///  Gets whether the controller requests an interrupt (INTRQ).
    /// </summary>
    public bool InterruptRequest { get; private set; }

    /// <summary>
    ///  Gets the last command written, for the debugger.
    /// </summary>
    public byte LastCommand => _command;

    /// <summary>
    ///  Gets the selected drive, 0-3, or -1 when none is.
    /// </summary>
    public int SelectedDrive => _selected;

    /// <summary>
    ///  Gets the side the selected drive's head reads, 0 or 1.
    /// </summary>
    public int Side { get; private set; }

    /// <summary>
    ///  Gets whether the controller reads and writes double density (MFM).
    /// </summary>
    public bool DoubleDensity => _doubleDensity;

    /// <summary>
    ///  Selects single or double density without changing the drive, as a TRS-80 Model I doubler does.
    /// </summary>
    /// <param name="doubleDensity">Whether the controller reads and writes MFM.</param>
    internal void SetDensity(bool doubleDensity) => _doubleDensity = doubleDensity;

    /// <summary>
    ///  Gets whether a command is running.
    /// </summary>
    public bool IsBusy => (_status & Busy) != 0;

    /// <summary>
    ///  Puts a disk in a drive, or empties it.
    /// </summary>
    /// <param name="drive">The drive, 0-3.</param>
    /// <param name="disk">The disk, or null.</param>
    public void Insert(int drive, FloppyDisk? disk)
    {
        ArgumentOutOfRangeException.ThrowIfNegative(drive);
        ArgumentOutOfRangeException.ThrowIfGreaterThanOrEqual(drive, DriveCount);
        _disks[drive] = disk;
    }

    /// <summary>
    ///  Gets whether the drives' motors are turning; they run together.
    /// </summary>
    public bool MotorOn => _motorCycles > 0;

    /// <summary>
    ///  Gets what a drive is doing: only the selected drive does anything.
    /// </summary>
    /// <param name="drive">The drive, 0-3.</param>
    /// <returns>The activity.</returns>
    public DeviceActivity Activity(int drive)
    {
        if (drive != _selected || !IsBusy) { return DeviceActivity.Idle; }

        // Write sector ($A0-$BF) and write track ($F0) wait for their place on the disk before writing.
        bool write = (_command & 0xE0) == 0xA0 || (_command & 0xF0) == 0xF0;
        return _phase switch
        {
            Phase.Stepping or Phase.Verifying => DeviceActivity.Seeking,
            Phase.Writing or Phase.WritingTrack => DeviceActivity.Writing,
            Phase.Reading => DeviceActivity.Reading,
            Phase.Idle => DeviceActivity.Idle,
            _ => write ? DeviceActivity.Writing : DeviceActivity.Reading
        };
    }

    /// <summary>
    ///  Gets the disk in a drive.
    /// </summary>
    /// <param name="drive">The drive, 0-3.</param>
    /// <returns>The disk, or null.</returns>
    public FloppyDisk? Disk(int drive) => _disks[drive];

    /// <summary>
    ///  Gets the cylinder a drive's head is on.
    /// </summary>
    /// <param name="drive">The drive, 0-3.</param>
    /// <returns>The cylinder.</returns>
    public int Cylinder(int drive) => _cylinders[drive];

    /// <summary>
    ///  Selects a drive, its side, the motors and the density directly, for controllers with a drive control
    ///  register such as the Color Computer's and the Model II's: the motors run while <paramref name="motor"/> is
    ///  set.
    /// </summary>
    /// <param name="drive">The drive, 0-3, or -1 for none.</param>
    /// <param name="side">The side, 0 or 1.</param>
    /// <param name="motor">Whether the motors run.</param>
    /// <param name="doubleDensity">Whether the controller reads and writes MFM.</param>
    internal void Control(int drive, int side, bool motor, bool doubleDensity)
    {
        _selected = drive;
        Side = side;
        _doubleDensity = doubleDensity;
        _motorHeld = motor;
        _motorCycles = motor ? 1 : 0;
    }

    /// <summary>
    ///  Selects a drive, its side and the density, starting the motors for 3 seconds, as the TRS-80 Model I's drive
    ///  select latch and the Model III and 4's drive select port do.
    /// </summary>
    /// <param name="drive">The drive, 0-3, or -1 for none.</param>
    /// <param name="side">The side, 0 or 1.</param>
    /// <param name="doubleDensity">Whether the controller reads and writes MFM.</param>
    internal void SelectTimed(int drive, int side, bool doubleDensity)
    {
        _selected = drive;
        Side = side;
        _doubleDensity = doubleDensity;
        _motorHeld = false;
        if (drive >= 0) { _motorCycles = 3000 * _cyclesPerMillisecond; }
    }

    /// <summary>
    ///  Gets whether the data register waits for the program (DRQ).
    /// </summary>
    public bool DataRequest => _request;

    /// <summary>
    ///  Reads a register.
    /// </summary>
    /// <param name="register">0 status, 1 track, 2 sector, 3 data.</param>
    /// <returns>The value.</returns>
    internal byte Read(int register)
    {
        switch (register & 3)
        {
            case 0:
                InterruptRequest = false;
                return Status();
            case 1:
                return Track;
            case 2:
                return Sector;
            default:
                _request = false;
                return Data;
        }
    }

    /// <summary>
    ///  Reads a register without the side effects of a read, for the debugger.
    /// </summary>
    /// <param name="register">0 status, 1 track, 2 sector, 3 data.</param>
    /// <returns>The value.</returns>
    public byte Peek(int register) => (register & 3) switch
    {
        0 => Status(),
        1 => Track,
        2 => Sector,
        _ => Data
    };

    /// <summary>
    ///  Writes a register.
    /// </summary>
    /// <param name="register">0 command, 1 track, 2 sector, 3 data.</param>
    /// <param name="value">The value.</param>
    internal void Write(int register, byte value)
    {
        switch (register & 3)
        {
            case 0:
                Command(value);
                break;
            case 1:
                if (!IsBusy) { Track = value; }
                break;
            case 2:
                if (!IsBusy) { Sector = value; }
                break;
            default:
                Data = value;
                _request = false;
                break;
        }
    }

    /// <summary>
    ///  Advances the disks and the command one T-state.
    /// </summary>
    internal void Tick()
    {
        if (_motorCycles > 0 && !_motorHeld) { _motorCycles--; }
        if (_motorCycles > 0) { _rotation = (_rotation + 1) % _rotationCycles; }
        bool index = Ready && _rotation < _indexPulseCycles;
        if (index && !_wasIndex) { _indexPulses++; }
        _wasIndex = index;
        if (_phase != Phase.Idle) { Run(); }
    }

    private FloppyDisk? Current => _selected >= 0 ? _disks[_selected] : null;

    private bool Ready => Current is not null && _motorCycles > 0;

    private int ByteCycles => (_doubleDensity ? _clockHertz / 31250 : _clockHertz / 15625) / (_eightInch ? 2 : 1);

    // Whether the chip reading now behaves as a WD179x: always for an FD179x or WD179x, and with a doubler's WD1791
    // selected beside an FD1771.
    private bool Is179x => _wd179x || _doubleDensity;

    private byte Status()
    {
        if (!_typeOne)
        {
            byte value = (byte)(_status & ~(IndexOrRequest | NotReady));
            return (byte)(value | (_request ? IndexOrRequest : 0) | (Ready ? 0 : NotReady));
        }

        // Type I status shows the index hole, track 0, write protect and ready as they are now.
        byte status = (byte)(_status & (Busy | CrcError | SeekError | HeadLoaded));
        if (Ready && _rotation < _indexPulseCycles) { status |= IndexOrRequest; }
        if (_selected >= 0 && _cylinders[_selected] == 0) { status |= TrackZeroOrLost; }
        if (Current?.IsWriteProtected == true) { status |= WriteProtect; }
        if (!Ready) { status |= NotReady; }
        return status;
    }
}
