// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Media;

namespace Retrocore.Machines.Apple2;

/// <summary>
///  Slot-six Disk II with caller-supplied P5/P6 firmware, two quarter-track drives and a
///  two-half-clock-per-CPU-cycle logic-state sequencer. All even switches return the latch;
///  odd switches leave the floating bus visible. Motor-off delay is one emulated second.
/// </summary>
/// <remarks>
///  <para>
///   The Apple III's built-in controller is the same logic with four drives, the built-in one and three external,
///   which the machine selects itself through <see cref="SelectDrive"/>.
///  </para>
/// </remarks>
public sealed class DiskIIController
{
    private readonly DiskIIDrive[] _drives;
    private DiskIIFirmware? _firmware;
    private int _selected;
    private byte _magnets;
    private byte _state;
    private byte _latch;
    private byte _input;
    private int _pulse;
    private int _motorOff;
    private bool _motor;
    private bool _q6;
    private bool _q7;
    private bool _halfCycle;

    /// <summary>
    ///  Constructs a controller.
    /// </summary>
    /// <param name="drives">The drives it can select: two on a Disk II card, four on the Apple III.</param>
    public DiskIIController(int drives = 2)
    {
        ArgumentOutOfRangeException.ThrowIfLessThan(drives, 1);
        _drives = new DiskIIDrive[drives];
        for (int i = 0; i < drives; i++) { _drives[i] = new(); }
    }

    /// <summary>
    ///  Gets the number of drives.
    /// </summary>
    public int DriveCount => _drives.Length;

    /// <summary>
    ///  Gets the selected drive, from one.
    /// </summary>
    public int SelectedDrive => _selected + 1;

    /// <summary>
    ///  Gets whether external card firmware is installed.
    /// </summary>
    public bool IsInstalled => _firmware is not null;

    /// <summary>
    ///  Gets the latest sequencer data latch without shifting or changing Q6/Q7.
    /// </summary>
    public byte DataLatch => _latch;

    /// <summary>
    ///  Gets whether the controller is in write mode.
    /// </summary>
    public bool WriteMode => _q7;

    /// <summary>
    ///  Gets the externally supplied slot ROM, or an empty span for an empty slot.
    /// </summary>
    public ReadOnlySpan<byte> BootRom => _firmware is { } firmware ? firmware.Boot : [];

    /// <summary>
    ///  Installs caller-owned firmware and resets controller controls.
    /// </summary>
    /// <param name="firmware">The validated P5/P6 data.</param>
    public void SetFirmware(DiskIIFirmware firmware)
    {
        ArgumentNullException.ThrowIfNull(firmware);
        _firmware = firmware;
        Reset();
    }

    /// <summary>
    ///  Mounts media in an installed card without moving the head.
    /// </summary>
    /// <param name="drive">The drive, from one.</param>
    /// <param name="disk">The caller-owned media.</param>
    public void Mount(int drive, WozDisk disk)
    {
        ArgumentNullException.ThrowIfNull(disk);
        if (!IsInstalled)
        {
            throw new InvalidOperationException("Disk II P5 and P6 firmware must be supplied before mounting a floppy.");
        }

        GetDrive(drive).SetMedia(disk);
    }

    /// <summary>
    ///  Removes the card's firmware, as taking the card out: its disks are ejected, and it answers nothing until
    ///  firmware is set again.
    /// </summary>
    public void RemoveFirmware()
    {
        Reset();
        for (int drive = 1; drive <= _drives.Length; drive++) { Eject(drive); }
        _firmware = null;
    }

    /// <summary>
    ///  Selects a drive, as the Apple III's drive select does; a Disk II card selects with its own switches.
    /// </summary>
    /// <param name="drive">The drive, from one.</param>
    public void SelectDrive(int drive)
    {
        GetDrive(drive);
        if (_selected == drive - 1) { return; }
        if (_q7) { _drives[_selected].EndWrite(); }
        _selected = drive - 1;
    }

    /// <summary>
    ///  Ejects caller-owned media without discarding or acknowledging dirty bits.
    /// </summary>
    /// <param name="drive">The drive, from one.</param>
    /// <returns>The mounted media, or null.</returns>
    public WozDisk? Eject(int drive)
    {
        DiskIIDrive selected = GetDrive(drive);
        WozDisk? media = selected.Media;
        selected.SetMedia(media: null);
        return media;
    }

    /// <summary>
    ///  Gets side-effect-free drive telemetry.
    /// </summary>
    /// <param name="drive">The drive, from one.</param>
    /// <returns>The drive state.</returns>
    public DiskDriveState State(int drive)
    {
        DiskIIDrive selected = GetDrive(drive);
        return new(
            drive,
            selected.QuarterTrack,
            selected.BitPosition,
            selected.BitCount,
            _motor && _selected == drive - 1,
            selected.Media is not null,
            selected.Media?.IsReadOnly ?? true,
            selected.Media?.IsDirty ?? false);
    }

    /// <summary>
    ///  Reads a control switch, including dummy CPU reads.
    /// </summary>
    /// <param name="offset">The low four address bits.</param>
    /// <param name="floatingBus">The video bus value for odd addresses.</param>
    /// <returns>The data latch for even addresses, floating bus for odd addresses.</returns>
    public byte Read(byte offset, byte floatingBus)
    {
        Access(offset);
        return Peek(offset, floatingBus);
    }

    /// <summary>
    ///  Inspects a switch value without changing motor, magnets, Q6/Q7 or rotation.
    /// </summary>
    /// <param name="offset">The low four address bits.</param>
    /// <param name="floatingBus">The video bus value.</param>
    /// <returns>The non-mutating value.</returns>
    public byte Peek(byte offset, byte floatingBus)
    {
        return offset > 15 ? throw new ArgumentOutOfRangeException(nameof(offset)) : (offset & 1) == 0 ? _latch : floatingBus;
    }

    /// <summary>
    ///  Writes a soft switch and supplies its byte to the P6 load-data operation.
    /// </summary>
    /// <param name="offset">The low four address bits.</param>
    /// <param name="value">The CPU data bus.</param>
    public void Write(byte offset, byte value)
    {
        _input = value;
        Access(offset);
    }

    /// <summary>
    ///  Advances rotation, flux pulse generation, sequencer and motor delay by one CPU cycle.
    /// </summary>
    public void Tick()
    {
        if (_firmware is not { } firmware) { return; }
        HalfStep(firmware);
        HalfStep(firmware);
        if (_motorOff > 0 && --_motorOff == 0) { _motor = false; }
    }

    /// <summary>
    ///  Advances by one sequencer clock, half of <see cref="Tick"/>, as the Apple III's 2 MHz cycle does.
    /// </summary>
    public void HalfTick()
    {
        if (_firmware is not { } firmware) { return; }
        HalfStep(firmware);
        _halfCycle = !_halfCycle;
        if (!_halfCycle && _motorOff > 0 && --_motorOff == 0) { _motor = false; }
    }

    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    private void HalfStep(DiskIIFirmware firmware)
    {
        int address = (_state & 240)
            | (_q7 ? 8 : 0)
            | (_q6 ? 4 : 0)
            | ((_latch & 128) >> 6)
            | (_pulse == 0 ? 1 : 0);

        byte next = firmware.Sequencer[address];
        bool transition = ((next ^ _state) & 128) != 0;
        _state = next;
        switch (next & 15)
        {
            case 8:
            case 12: break;
            case 9: _latch <<= 1;
                break;
            case 13: _latch = (byte)((_latch << 1) | 1);
                break;
            case 10:
            case 14:
                bool protectedMedia = (_magnets & 2) != 0 || (_drives[_selected].Media?.IsReadOnly ?? true);
                _latch = (byte)((_latch >> 1) | (protectedMedia ? 128 : 0));
                break;
            case 11:
            case 15: _latch = _input;
            break;
            default: _latch = 0;
                break;
        }

        // The card synchronizes the drive's read pulse to the sequencer's clock and shortens it to one clock
        // (Sather, Understanding the Apple II, 9-15). The 16-sector table also reads a pulse two clocks long,
        // but the 13-sector one counts the second clock as another 1.
        if (_pulse != 0) { _pulse--; }
        if (_motor && _drives[_selected].Tick(_q7, transition)) { _pulse = 1; }
    }

    /// <summary>
    ///  Resets controller controls without clearing caller media or moving drive heads.
    /// </summary>
    public void Reset()
    {
        if (_q7) { _drives[_selected].EndWrite(); }
        _selected = 0;
        _magnets = 0;
        _state = 0;
        _latch = 0;
        _input = 0;
        _pulse = 0;
        _motorOff = 0;
        _motor = _q6 = _q7 = false;
    }

    private DiskIIDrive GetDrive(int drive)
    {
        return drive < 1 || drive > _drives.Length
            ? throw new ArgumentOutOfRangeException(nameof(drive))
            : _drives[drive - 1];
    }

    private void Access(byte offset)
    {
        if (offset > 15) { throw new ArgumentOutOfRangeException(nameof(offset)); }
        if (offset < 8)
        {
            byte mask = (byte)(1 << (offset / 2));
            byte magnets = (offset & 1) == 0 ? (byte)(_magnets & ~mask) : (byte)(_magnets | mask);
            if (magnets != _magnets)
            {
                _magnets = magnets;
                int target = MagnetPosition[magnets];
                if (target >= 0)
                {
                    DiskIIDrive drive = _drives[_selected];
                    int direction = (target - drive.Rotor + 8) & 7;
                    if (direction > 4) { direction -= 8; }
                    if (direction != 4)
                    {
                        drive.Step(direction);
                        drive.Rotor = target;
                    }
                }
            }

            return;
        }

        switch (offset)
        {
            case 8: _motorOff = 1_020_500;
                break;
            case 9: _motor = true;
                _motorOff = 0;
                break;
            case 10:
            case 11:
                if (_q7) { _drives[_selected].EndWrite(); }
                _selected = offset - 10;
                break;
            case 12: _q6 = false;
                break;
            case 13: _q6 = true;
                break;
            case 14:
                if (_q7) { _drives[_selected].EndWrite(); }
                _q7 = false;
                break;
            case 15: _q7 = true;
                break;
        }
    }

    private static ReadOnlySpan<sbyte> MagnetPosition => [-1,0,2,1,4,-1,3,-1,6,7,-1,-1,5,-1,-1,-1];
}
