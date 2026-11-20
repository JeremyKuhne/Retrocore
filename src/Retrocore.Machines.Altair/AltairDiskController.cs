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
///   Port $08 selects a drive when written (bit 7 deselects) and reads the drive status, whose bits are low when
///   true: 0 ENWD (enter new write data), 1 head movement allowed, 2 head loaded and settled, 5 the 8080's INTE,
///   6 track 0, 7 NRDA (new read data available); bits 3 and 4 read 0 while a drive is selected. Port $09 commands
///   the drive when written (bit 0 step in, 1 step out, 2 load the head, 3 unload it, 4 and 5 enable and disable
///   interrupts, 6 lower the head current, 7 start a write) and reads the sector position: bits 1-5 the sector
///   under the head, bit 0 low for Sector True, bits 6 and 7 set, or $FF until the head is loaded and settled.
///   Port $0A reads a sector's bytes and takes those to write. With no drive selected the status and position read
///   $FF.
///  </para>
///  <para>
///   The disk turns all the time, a sector every <see cref="AltairDiskTiming.SectorCycles"/>, so the controller
///   works out where the disk is from the cycle count. A sector's 137 bytes come one each
///   <see cref="AltairDiskTiming.ByteCycles"/>, each holding the data port until the next replaces it, which MITS's
///   two-bytes-a-pass read loops rely on; NRDA is asserted as each arrives and cleared by reading the port. A write
///   takes the data port's value each byte time from a handshake that ENWD asserts, and keeps it as the sector's next
///   byte, whether or not the 8080 has sent a new one; the first 137 are the sector.
///  </para>
///  <para>
///   The controller's sector interrupts are not modeled: its interrupt enable is kept, but nothing is requested,
///   as none of the software here uses them. Writes to a write-protected disk are lost, as the drive's write gate
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
    private int _readTaken = -1;

    // A write: the sector it writes (or -1), whether one is waiting for the next sector, the byte to write, the
    // handshakes done, and whether ENWD is asserted.
    private long _writeSector = -1;
    private bool _writePending;
    private byte _writeData;
    private int _writeSlots;
    private bool _writeReady;

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
    ///  Gets whether the controller's interrupts are enabled; they request nothing, as they are not modeled.
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
    ///  Reads a port without side effects.
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
    ///  Takes a disk out of a drive the controller is using: a write in progress is lost, and the drive is no longer
    ///  ready, so the controller lets go of it.
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
        if (!Writing && drive.MayStep(_cycle)) { status &= unchecked((byte)~MoveHead); }
        if (drive.Settled(_cycle)) { status &= unchecked((byte)~HeadStatus); }
        if (_interruptEnable()) { status &= unchecked((byte)~InterruptsEnabled); }
        if (drive.AtTrackZero(_cycle)) { status &= unchecked((byte)~TrackZero); }
        if (!Writing && Data(out int index) >= 0 && index >= 0 && index != _readTaken)
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

    // The byte in the data register, and its index in the sector, or -1 while none of this sector's has arrived.
    private byte Data(out int index)
    {
        index = -1;
        if (_selected is not { } drive || Writing || !drive.HeadLoaded || drive.Disk is not { } disk)
        {
            return _sector[0];
        }

        long sector = CurrentSector;
        int offset = CurrentOffset;
        if (offset < AltairDiskTiming.FirstByteCycles || offset >= AltairDiskTiming.EndOfSectorCycles)
        {
            return _sector[0];
        }

        if (sector != _readSector)
        {
            disk.ReadSector(drive.Track, Sector, _sector);
            Align(_sector);
            _readSector = sector;
            _readTaken = -1;
        }

        index = Math.Min((offset - AltairDiskTiming.FirstByteCycles) / AltairDiskTiming.ByteCycles, AltairDisk.SectorBytes - 1);
        return _sector[index];
    }

    // The controller assembles bytes from the first one bit it sees, so a sector whose first byte lacks bit 7, as a
    // blank one does, reads shifted from that bit, or not at all.
    private static void Align(Span<byte> sector)
    {
        int bit = 0;
        while (bit < sector.Length * 8 && (sector[bit / 8] & (0x80 >> (bit % 8))) == 0) { bit++; }
        if (bit == 0) { return; }
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
        if (Writing) { FinishWrite(); }
        _writePending = false;
        _writeReady = false;
        _selected?.Unload();
        _selected = null;
        _readSector = -1;
    }

    private void Command(byte value)
    {
        if (_selected is not { } drive) { return; }
        if ((value & 0x0F) != 0)
        {
            if ((value & 0x02) != 0)
            {
                drive.Step(_cycle, inward: false);
            }
            else if ((value & 0x01) != 0)
            {
                drive.Step(_cycle, inward: true);
            }

            if ((value & 0x04) != 0)
            {
                drive.Load(_cycle);
            }
            else if ((value & 0x08) != 0 && !Writing)
            {
                drive.Unload();
            }

            _readSector = -1;
        }
        else if ((value & 0x80) != 0 && !Writing)
        {
            // A write enable in the read-clear time writes this sector; later, it waits for the next.
            _writePending = true;
            if (CurrentOffset < AltairDiskTiming.ReadClearCycles) { StartWrite(); }
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
        _writeSector = -1;
        _writeReady = false;
        _readSector = -1;
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
