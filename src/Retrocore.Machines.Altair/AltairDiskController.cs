// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Media.Altair;

namespace Retrocore.Machines.Altair;

/// <summary>
///  The MITS 88-DCDD floppy controller: three ports that select a Pertec FD-400 8-inch drive, step and load its
///  head, and pass the bytes of the hard sector under it as the disk turns.
/// </summary>
/// <remarks>
///  <para>
///   Port $08 selects a drive when written (bit 7 deselects) and reads the drive status, whose bits are low when true:
///   0 ENWD (enter new write data), 1 head movement allowed, 2 head loaded and settled, 5 the 8080's INTE, 6 track 0, 7
///   NRDA (new read data available); bits 3 and 4 read 0 while a drive is selected. Port $09 commands the drive when
///   written (bit 0 step in, 1 step out, 2 load the head, 3 unload it, 4 and 5 enable and disable interrupts, 6 lower
///   the head current, 7 start a write) and reads the sector position: bits 1-5 the sector under the head, bit 0 low
///   for Sector True, bits 6 and 7 set, or $FF until the head is loaded and settled. Port $0A reads a sector's bytes
///   and takes those to write. With no drive selected the status and position read $FF.
///  </para>
///  <para>
///   The disk turns all the time, a sector every <see cref="AltairDiskTiming.SectorCycles"/>, so the controller works
///   out where the disk is from the cycle count. A sector's 137 bytes come one each
///   <see cref="AltairDiskTiming.ByteCycles"/>, each holding the data port until the next replaces it, which MITS's
///   two-bytes-a-pass read loops rely on; NRDA is asserted as each arrives and cleared by reading the port or by the
///   sector's end, and the port keeps the last byte until another comes. An image holds a sector's 137 bytes and
///   nothing of the gap after them, so nothing more comes until the next sector. A write takes the data port's value
///   each byte time from a handshake that ENWD asserts, and keeps it as the sector's next byte, whether or not the 8080
///   has sent a new one; the first 137 are the sector. After a write, head movement stays held off until the drive's
///   trim erase ends, <see cref="AltairDiskTiming.TrimEraseCycles"/> into the next sector.
///  </para>
///  <para>
///   The controller's sector interrupts are not modeled: its interrupt enable is kept, but nothing is requested, as
///   none of the software here uses them. Nor is the wait for the index hole after a drive is selected: the sector
///   position shows once the head has settled. Writes to a write-protected disk are lost, as the drive's write gate
///   would refuse them.
///  </para>
/// </remarks>
public sealed class AltairDiskController
{
    /// <summary>
    ///  The controller's first port: drive select and status.
    /// </summary>
    public const byte Port = 0x08;

    /// <summary>
    ///  The drives the controller can address.
    /// </summary>
    public const int MaximumDrives = 16;

    private const byte EnterNewWriteData = 0x01;
    private const byte MoveHead = 0x02;
    private const byte HeadStatus = 0x04;
    private const byte InterruptsEnabled = 0x20;
    private const byte TrackZero = 0x40;
    private const byte NewReadData = 0x80;

    private readonly AltairDiskDrive[] _drives;
    private readonly Func<bool> _interruptEnable;
    private readonly byte[] _sector = new byte[AltairDisk.SectorBytes];
    private readonly byte[] _written = new byte[AltairDisk.SectorBytes];
    private ulong _cycle;
    private AltairDiskDrive? _selected;

    // The sector whose bytes _sector holds, and the last of its bytes the 8080 has read, for NRDA.
    private long _readSector = -1;
    private int _readTrack = -1;

    // The byte the data register keeps while the head is not reading, and the last byte of the sectors before the
    // current one, for the sector and track it was found for.
    private byte _held;
    private byte _previous;
    private long _previousArrival = long.MinValue;

    // When the head last began reading the track it is on: loaded, stepped, or done writing.
    private ulong _readSince;
    private long _previousSector = -1;
    private int _previousTrack = -1;
    private int _readTaken = -1;

    // How many cycles after the first byte's time the sector's bytes come, as the controller assembles them from the
    // sector's first one bit, or -1 for a sector with none, which never gives a byte.
    private int _readDelay;

    // A write: the sector it writes (or -1), whether one is waiting for the next sector, the byte to write, the
    // handshakes done, and whether ENWD is asserted.
    private long _writeSector = -1;
    private bool _writePending;
    private byte _writeData;
    private int _writeSlots;
    private bool _writeReady;

    // When the trim erase after a write ends, and head movement is allowed again.
    private ulong _trimEndsAt;

    /// <summary>
    ///  Builds the controller with its drives.
    /// </summary>
    /// <param name="drives">The drives, numbered from 0; at most <see cref="MaximumDrives"/>.</param>
    /// <param name="interruptEnable">Reads the 8080's INTE, which the status register shows.</param>
    internal AltairDiskController(int drives, Func<bool> interruptEnable)
    {
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(drives);
        ArgumentOutOfRangeException.ThrowIfGreaterThan(drives, MaximumDrives);
        _interruptEnable = interruptEnable;
        _drives = new AltairDiskDrive[drives];
        for (int index = 0; index < drives; index++) { _drives[index] = new(this, index); }
    }

    /// <summary>
    ///  Gets the drives.
    /// </summary>
    public IReadOnlyList<AltairDiskDrive> Drives => _drives;

    /// <summary>
    ///  Gets the selected drive, or null.
    /// </summary>
    public AltairDiskDrive? Selected => _selected;

    /// <summary>
    ///  Gets whether the controller's interrupts are enabled; they request nothing, as they are not modeled. Selecting
    ///  or deselecting a drive disables them.
    /// </summary>
    public bool InterruptEnabled { get; private set; }

    /// <summary>
    ///  Gets whether the selected drive is writing a sector.
    /// </summary>
    public bool Writing => _writeSector >= 0;

    /// <summary>
    ///  Gets the sector under the heads, 0-31.
    /// </summary>
    public int Sector => (int)(_cycle / AltairDiskTiming.SectorCycles % AltairDisk.SectorsPerTrack);

    /// <summary>
    ///  Gets whether a port is the controller's.
    /// </summary>
    /// <param name="port">The port's low byte.</param>
    /// <returns>True for ports $08-$0A.</returns>
    public static bool Answers(byte port) => port is >= Port and <= Port + 2;

    /// <summary>
    ///  Reads a port.
    /// </summary>
    /// <param name="port">The port, $08-$0A.</param>
    /// <returns>The value.</returns>
    public byte Read(byte port)
    {
        switch (port - Port)
        {
            case 0:
                return Status();
            case 1:
                return SectorPosition();
            default:
                byte value = Data(out int index);
                if (index >= 0) { _readTaken = index; }
                return value;
        }
    }

    /// <summary>
    ///  Reads a port as a read would, without taking a byte: NRDA stays as it was, and the data register too.
    /// </summary>
    /// <param name="port">The port, $08-$0A.</param>
    /// <returns>The value a read would return.</returns>
    public byte Peek(byte port) => (port - Port) switch
    {
        0 => Status(),
        1 => SectorPosition(),
        _ => Data(out _)
    };

    /// <summary>
    ///  Writes a port.
    /// </summary>
    /// <param name="port">The port, $08-$0A.</param>
    /// <param name="value">The value.</param>
    public void Write(byte port, byte value)
    {
        switch (port - Port)
        {
            case 0:
                Select(value);
                break;
            case 1:
                Command(value);
                break;
            default:
                AdvanceWrite();
                _writeData = value;
                _writeReady = false;
                break;
        }
    }

    /// <summary>
    ///  Advances one CPU cycle: the disk turns, and a write ends with its sector.
    /// </summary>
    internal void Tick()
    {
        _cycle++;
        if (_writeSector >= 0 && Offset(_writeSector) >= AltairDiskTiming.EndOfSectorCycles) { FinishWrite(); }
        else if (_writePending && _cycle % AltairDiskTiming.SectorCycles == 0) { StartWrite(); }
    }

    /// <summary>
    ///  RESET: the controller is cleared and its drive deselected, as the 8080's reset line clears it.
    /// </summary>
    internal void Reset() => Deselect();

    /// <summary>
    ///  Takes a disk out of a drive the controller is using: the drive is no longer ready, so the controller lets go
    ///  of it. A write in progress keeps the bytes it has written over the start of its sector.
    /// </summary>
    /// <param name="drive">The drive.</param>
    internal void Removed(AltairDiskDrive drive)
    {
        if (_selected == drive) { Deselect(); }
    }

    // Cycles since the start of an absolute sector (a count of sectors since power-on).
    private long Offset(long sector) => (long)_cycle - (sector * AltairDiskTiming.SectorCycles);

    private long CurrentSector => (long)(_cycle / AltairDiskTiming.SectorCycles);

    private int CurrentOffset => (int)(_cycle % AltairDiskTiming.SectorCycles);

    private byte Status()
    {
        if (_selected is not { } drive) { return 0xFF; }
        AdvanceWrite();
        byte status = 0xFF & ~0x18;
        if (_writeReady) { status &= unchecked((byte)~EnterNewWriteData); }
        if (!Writing && _cycle >= _trimEndsAt && drive.MayStep(_cycle)) { status &= unchecked((byte)~MoveHead); }
        if (drive.Settled(_cycle)) { status &= unchecked((byte)~HeadStatus); }
        if (_interruptEnable()) { status &= unchecked((byte)~InterruptsEnabled); }
        if (drive.AtTrackZero(_cycle)) { status &= unchecked((byte)~TrackZero); }
        _ = Data(out int index);
        if (!Writing && index >= 0 && index != _readTaken)
        {
            status &= unchecked((byte)~NewReadData);
        }

        return status;
    }

    // The sector position register shows the sector only once the head was settled when the sector began.
    private byte SectorPosition()
    {
        if (_selected is not { } drive) { return 0xFF; }
        ulong start = (ulong)CurrentSector * AltairDiskTiming.SectorCycles;
        if (!drive.Settled(start)) { return 0xFF; }
        int sectorTrue = CurrentOffset < AltairDiskTiming.SectorTrueCycles ? 0 : 1;
        return (byte)(0xC0 | (Sector << 1) | sectorTrue);
    }

    // The byte in the data register, and its index in the sector, or -1 while none of this sector's is arriving.
    // The register holds the last byte assembled since the head began reading this track (_readSince): this
    // sector's, or before its first, the last of the sector before; with none since then, the byte it held (_held).
    // That depends only on where the disk is and what the head did, not on what has looked at the port.
    private byte Data(out int index)
    {
        index = -1;
        if (_selected is not { } drive || Writing || !drive.HeadLoaded || drive.Disk is not { } disk)
        {
            return _held;
        }

        long sector = CurrentSector;
        int offset = CurrentOffset;
        if (offset >= AltairDiskTiming.FirstByteCycles)
        {
            Load(sector, drive, disk);
            if (LastArrived(_readDelay, offset) is int last && Arrival(sector, _readDelay, last) >= (long)_readSince)
            {
                // An image holds no bytes past a sector's 137, so the last stays the one arriving until the sector
                // ends, which deasserts NRDA, and then the register keeps it with nothing new to read.
                if (offset < AltairDiskTiming.EndOfSectorCycles) { index = last; }
                return _sector[last];
            }
        }

        byte previous = PreviousLast(sector, drive, disk, out long arrival);
        return arrival >= (long)_readSince ? previous : _held;
    }

    // When a sector's byte is assembled, in cycles since power-on.
    private static long Arrival(long sector, int delay, int index)
    {
        long start = sector * AltairDiskTiming.SectorCycles;
        return start + AltairDiskTiming.FirstByteCycles + delay + ((long)index * AltairDiskTiming.ByteCycles);
    }

    // The head begins reading, or reads another track: the register keeps its byte until the next is assembled.
    private void BeginReading()
    {
        Latch();
        _readSince = _cycle;
    }

    // Holds the register's byte as reading stops: a head unloaded, a drive deselected or a write begun.
    private void Latch() => _held = Data(out _);

    // Reads this sector's bytes as the controller assembles them, once for each sector and track.
    private void Load(long sector, AltairDiskDrive drive, AltairDisk disk)
    {
        if (sector == _readSector && drive.Track == _readTrack) { return; }
        disk.ReadSector(drive.Track, (int)(sector % AltairDisk.SectorsPerTrack), _sector);
        int bit = Align(_sector);
        _readDelay = bit < 0 ? -1 : bit * AltairDiskTiming.BitCycles;
        if (sector != _readSector) { _readTaken = -1; }
        _readSector = sector;
        _readTrack = drive.Track;
    }

    // The index of the last byte of a sector to have arrived at an offset into it, or null before the first.
    private static int? LastArrived(int delay, int offset)
    {
        int end = Math.Min(offset, AltairDiskTiming.EndOfSectorCycles - 1);
        if (delay < 0 || end < AltairDiskTiming.FirstByteCycles + delay) { return null; }
        int arrived = (end - AltairDiskTiming.FirstByteCycles - delay) / AltairDiskTiming.ByteCycles;
        return Math.Min(arrived, AltairDisk.SectorBytes - 1);
    }

    // The last byte the sectors before this one on the track gave: the nearest with a one bit to read from, or 0 on a
    // track with none.
    private byte PreviousLast(long sector, AltairDiskDrive drive, AltairDisk disk, out long arrival)
    {
        if (sector == _previousSector && drive.Track == _previousTrack)
        {
            arrival = _previousArrival;
            return _previous;
        }

        Span<byte> bytes = stackalloc byte[AltairDisk.SectorBytes];
        _previous = 0;
        _previousArrival = long.MinValue;
        for (int back = 1; back <= AltairDisk.SectorsPerTrack; back++)
        {
            const int Sectors = AltairDisk.SectorsPerTrack;
            int earlier = (int)(((sector - back) % Sectors) + Sectors) % Sectors;
            disk.ReadSector(drive.Track, earlier, bytes);
            int bit = Align(bytes);
            int delay = bit < 0 ? -1 : bit * AltairDiskTiming.BitCycles;
            if (LastArrived(delay, AltairDiskTiming.EndOfSectorCycles) is int last)
            {
                _previous = bytes[last];
                _previousArrival = Arrival(sector - back, delay, last);
                break;
            }
        }

        _previousSector = sector;
        _previousTrack = drive.Track;
        arrival = _previousArrival;
        return _previous;
    }

    // The controller assembles bytes from the first one bit it sees, so a sector whose first byte lacks bit 7 reads
    // shifted from that bit, each byte coming that many bit times later; a blank sector, with no one bit, gives none.
    // Returns the bits skipped, or -1 for a sector with no one bit.
    private static int Align(Span<byte> sector)
    {
        int bit = 0;
        while (bit < sector.Length * 8 && (sector[bit / 8] & (0x80 >> (bit % 8))) == 0) { bit++; }
        if (bit == sector.Length * 8) { return -1; }
        if (bit == 0) { return 0; }
        Span<byte> aligned = stackalloc byte[AltairDisk.SectorBytes];
        for (int index = 0; index < aligned.Length; index++)
        {
            int value = 0;
            for (int shift = 0; shift < 8; shift++)
            {
                int source = bit + (index * 8) + shift;
                int set = source < sector.Length * 8 && (sector[source / 8] & (0x80 >> (source % 8))) != 0 ? 1 : 0;
                value = (value << 1) | set;
            }

            aligned[index] = (byte)value;
        }

        aligned.CopyTo(sector);
        return bit;
    }

    private void Select(byte value)
    {
        if ((value & 0x80) != 0)
        {
            Deselect();
            return;
        }

        int number = value & 0x0F;
        AltairDiskDrive? drive = number < _drives.Length ? _drives[number] : null;
        if (drive == _selected && drive is not null) { return; }
        Deselect();
        if (drive?.Disk is null) { return; }
        _selected = drive;
        drive.Selected(_cycle);
    }

    private void Deselect()
    {
        Latch();
        if (Writing) { FinishWrite(); }
        _writePending = false;
        _writeReady = false;
        _trimEndsAt = 0;
        InterruptEnabled = false;
        _selected?.Unload();
        _selected = null;
        _readSector = -1;
        _previousSector = -1;
    }

    private void Command(byte value)
    {
        if (_selected is not { } drive) { return; }
        if ((value & 0x0F) != 0)
        {
            // An unload holds the byte the head had, before any step in the same command moves it.
            if ((value & 0x0C) == 0x08) { Latch(); }

            if ((value & 0x03) != 0)
            {
                BeginReading();
                drive.Step(_cycle, inward: (value & 0x02) == 0);
            }

            if ((value & 0x04) != 0)
            {
                if (!drive.HeadLoaded) { BeginReading(); }
                drive.Load(_cycle);
            }
            else if ((value & 0x08) != 0)
            {
                // During a write the status shows the head unloaded at once; the write still ends with its sector.
                drive.Unload();
            }
        }
        else if ((value & 0x80) != 0 && !Writing)
        {
            // A write enable in the read-clear time writes this sector, and one after the end of the sector writes the
            // next; one in between is forgotten when the sector ends.
            if (CurrentOffset < AltairDiskTiming.ReadClearCycles) { StartWrite(); }
            else if (CurrentOffset >= AltairDiskTiming.EndOfSectorCycles) { _writePending = true; }
        }

        if ((value & 0x20) != 0)
        {
            InterruptEnabled = false;
        }
        else if ((value & 0x10) != 0)
        {
            InterruptEnabled = true;
        }
    }

    private void StartWrite()
    {
        Latch();
        _writePending = false;
        if (_selected is null) { return; }
        _writeSector = CurrentSector;
        _writeSlots = 0;
        _writeReady = false;
        Array.Clear(_written);
    }

    // Takes the data port's byte at each handshake that has come: the first handshake asks for the first byte, which
    // the next takes; each byte taken is the sector's next.
    private void AdvanceWrite()
    {
        if (_writeSector < 0) { return; }
        long offset = Math.Min(Offset(_writeSector), AltairDiskTiming.EndOfSectorCycles - 1);
        while (true)
        {
            long slot = AltairDiskTiming.WriteClearCycles + ((long)_writeSlots * AltairDiskTiming.ByteCycles);
            if (slot > offset) { break; }
            if (_writeSlots > 0 && _writeSlots <= AltairDisk.SectorBytes) { _written[_writeSlots - 1] = _writeData; }
            _writeSlots++;
            _writeReady = true;
        }
    }

    private void FinishWrite()
    {
        AdvanceWrite();
        AltairDiskDrive? drive = _selected;
        int sector = (int)(_writeSector % AltairDisk.SectorsPerTrack);
        _trimEndsAt = (ulong)(_writeSector + 1) * AltairDiskTiming.SectorCycles + AltairDiskTiming.TrimEraseCycles;
        _readSince = _cycle;
        _writeSector = -1;
        _writeReady = false;
        _readSector = -1;
        _previousSector = -1;
        if (drive?.Disk is { IsWriteProtected: false } disk && _writeSlots > AltairDisk.SectorBytes)
        {
            disk.WriteSector(drive.Track, sector, _written);
        }
        else if (drive?.Disk is { IsWriteProtected: false } partial && _writeSlots > 1)
        {
            // A write cut short keeps the bytes it took over the start of the sector.
            Span<byte> merged = stackalloc byte[AltairDisk.SectorBytes];
            partial.ReadSector(drive.Track, sector, merged);
            _written.AsSpan(0, _writeSlots - 1).CopyTo(merged);
            partial.WriteSector(drive.Track, sector, merged);
        }
    }
}
