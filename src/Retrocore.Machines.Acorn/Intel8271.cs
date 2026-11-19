// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Media.Floppy;

namespace Retrocore.Machines.Acorn;

/// <summary>
///  An Intel 8271 floppy disk controller with two 5¼-inch drives, at the level of commands, ID fields and data bytes,
///  timed in 2 MHz CPU cycles.
/// </summary>
/// <remarks>
///  <para>
///   Registers: 0 the command register (write) and status (read), 1 a parameter (write) and the result (read), 2 the
///   reset register (writing 1 resets the chip). The data register is separate (<see cref="ReadData"/> and
///   <see cref="WriteData"/>), as the DMA acknowledge line selects it. Status: bit 7 busy, 6 command full, 4 result
///   full, 3 interrupt, 2 a data request in non-DMA mode.
///  </para>
///  <para>
///   A command's bits 6-7 select drive 0 or 1 and its low six bits the command, with its parameters: scan (6),
///   write data and write deleted data (3 for one sector, 4 for several), read data, read deleted data and verify
///   (likewise), read ID (4), format (6), seek (2), read drive status (1), specify (5) and the special registers (2 to
///   read, 3 to write). A multi-sector command's last parameter has the sector count in bits 0-4 and the size code in
///   bits 5-7 (128 bytes shifted by it); a one-sector command transfers 128 bytes.
///  </para>
///  <para>
///   Specify sets, for mini-floppies, the step rate (2 ms units), the head settling time (2 ms), the revolutions an
///   idle head stays loaded (15: always) and the head load time (8 ms), or a surface's two bad tracks and current
///   track, which steps skip. The output port (special register &amp;23) drives side select from bit 5 and the head
///   load from bit 3, which on the BBC's board also runs both drives' motors.
///  </para>
///  <para>
///   A data command loads the head, steps to the track, and waits for the sector's ID to come round: the drive turns
///   at 300 rpm, 3,125 bytes of FM a track, a byte every 64 µs, and each track's sectors are spread evenly round it.
///   The search fails after two revolutions, or at once on an ID from another track. Each data byte is offered (or
///   asked for) with a data request; one the program has not taken when the next comes ends the command with late
///   DMA. The result: 0 good, &amp;0A late DMA, &amp;0E data CRC, &amp;10 not ready, &amp;12 write protected,
///   &amp;14 track 0 not found, &amp;18 sector not found, plus &amp;20 when deleted data was found. Then the chip
///   interrupts until the result is read.
///  </para>
/// </remarks>
public sealed class Intel8271
{
    /// <summary>
    ///  The CPU cycles a byte takes: 64 µs at FM's 125 kbit/s.
    /// </summary>
    public const int ByteCycles = 128;

    /// <summary>
    ///  The CPU cycles a revolution takes: 200 ms at 300 rpm.
    /// </summary>
    public const int RevolutionCycles = 400_000;

    private const int TrackBytes = RevolutionCycles / ByteCycles;
    private const int Milliseconds = 2_000;

    private const byte LateDma = 0x0A;
    private const byte DataCrcError = 0x0E;
    private const byte NotReady = 0x10;
    private const byte WriteProtected = 0x12;
    private const byte TrackZeroNotFound = 0x14;
    private const byte SectorNotFound = 0x18;
    private const byte DeletedData = 0x20;

    private readonly FloppyDisk?[] _disks = new FloppyDisk?[2];
    private readonly int[] _cylinders = new int[2];
    private readonly byte[] _currentTracks = [0xFF, 0xFF];
    private readonly byte[][] _badTracks = [[0xFF, 0xFF], [0xFF, 0xFF]];
    private readonly byte[] _command = new byte[6];
    private int _commandCount;
    private int _phase;
    private bool _ready;
    private FloppySector? _found;
    private byte _result;
    private byte _data;
    private byte _stepRate = 12;
    private byte _settle = 10;
    private byte _indexCount = 15;
    private byte _headLoad = 2;
    private byte _mode = 0xC0;
    private byte _scanSector;
    private readonly byte[] _scanCount = new byte[2];
    private byte _outputPort;
    private long _time;
    private long _idleSince;
    private IEnumerator<int>? _operation;

    // What a write or format has put on the disk so far, kept when a reset or a disk change cuts the command off: the
    // bytes written stay, with no CRC after them.
    private Action? _abandon;
    private int _wait;
    private int _drive;

    // The phases: idle, taking parameters, executing, and a result waiting.
    private const int Idle = 0;
    private const int CommandPhase = 1;
    private const int Execute = 2;
    private const int ResultPhase = 3;

    // What a data command does with each sector.
    private const int ReadKind = 0;
    private const int WriteKind = 1;
    private const int VerifyKind = 2;

    /// <summary>
    ///  Gets whether the chip's interrupt output is asserted: a command finished and its result waits.
    /// </summary>
    public bool InterruptRequest { get; private set; }

    /// <summary>
    ///  Gets whether a data byte waits to be read, or the chip waits for one to be written.
    /// </summary>
    public bool DataRequest { get; private set; }

    /// <summary>
    ///  Gets the INT pin: <see cref="InterruptRequest"/>, or in non-DMA mode (mode register bit 0) a
    ///  <see cref="DataRequest"/> too. In DMA mode data requests go to the DRQ pin instead.
    /// </summary>
    public bool InterruptOutput => InterruptRequest || ((_mode & 1) != 0 && DataRequest);

    /// <summary>
    ///  Gets whether the head load output is high, which runs the drives' motors.
    /// </summary>
    public bool HeadLoaded { get; private set; }

    /// <summary>
    ///  Gets the side the output port selects.
    /// </summary>
    public int Side => (_outputPort >> 5) & 1;

    /// <summary>
    ///  Gets the drive the last command selected, 0 or 1.
    /// </summary>
    public int SelectedDrive => _drive;

    /// <summary>
    ///  Gets whether a command is running.
    /// </summary>
    public bool IsBusy => _phase == Execute;

    /// <summary>
    ///  Gets the sector the running command is on, if any.
    /// </summary>
    public int? Sector { get; private set; }

    /// <summary>
    ///  Gets whether the running command writes.
    /// </summary>
    public bool IsWriting { get; private set; }

    /// <summary>
    ///  Gets the status register.
    /// </summary>
    public byte Status
    {
        get
        {
            int status = InterruptRequest ? 0x08 : 0;
            status |= _phase switch
            {
                CommandPhase => 0x40,
                Execute => 0x80 | ((_mode & 1) != 0 && DataRequest ? 0x04 : 0),
                ResultPhase => 0x10,
                _ => 0
            };

            return (byte)status;
        }
    }

    /// <summary>
    ///  Gets the disk in a drive.
    /// </summary>
    /// <param name="drive">0 or 1.</param>
    /// <returns>The disk, or null.</returns>
    public FloppyDisk? Disk(int drive) => _disks[drive];

    /// <summary>
    ///  Gets the cylinder a drive's head is on.
    /// </summary>
    /// <param name="drive">0 or 1.</param>
    /// <returns>The cylinder.</returns>
    public int Cylinder(int drive) => _cylinders[drive];

    /// <summary>
    ///  Puts a disk in a drive, or empties it. A command running on that drive ends at once, not ready, so it cannot
    ///  go on reading or writing the disk that came out.
    /// </summary>
    /// <param name="drive">0 or 1.</param>
    /// <param name="disk">The disk, or null.</param>
    public void Insert(int drive, FloppyDisk? disk)
    {
        if (ReferenceEquals(_disks[drive], disk)) { return; }
        _disks[drive] = disk;
        if (_operation is null || drive != _drive) { return; }

        Abandon();
        _operation = null;
        Sector = null;
        IsWriting = false;
        DataRequest = false;
        _idleSince = _time;
        _result = NotReady;
        _phase = ResultPhase;
        InterruptRequest = true;
    }

    /// <summary>
    ///  Reads a register.
    /// </summary>
    /// <param name="register">0 status, 1 result; 2 and 3 read <c>$FF</c>.</param>
    /// <returns>The value.</returns>
    public byte Read(int register)
    {
        switch (register & 3)
        {
            case 0:
                return Status;
            case 1:
                if (_phase == ResultPhase) { _phase = Idle; }
                InterruptRequest = false;
                return _result;
            default:
                return 0xFF;
        }
    }

    /// <summary>
    ///  Reads a register without side effects.
    /// </summary>
    /// <param name="register">The register.</param>
    /// <returns>The value.</returns>
    public byte Peek(int register) => (register & 3) switch { 0 => Status, 1 => _result, _ => 0xFF };

    /// <summary>
    ///  Writes a register.
    /// </summary>
    /// <param name="register">0 command, 1 parameter, 2 reset.</param>
    /// <param name="value">The value.</param>
    public void Write(int register, byte value)
    {
        switch (register & 3)
        {
            case 0:
                // A command is taken when the chip is not busy; a result not read is lost.
                if (_phase is not (Idle or ResultPhase)) { return; }
                _command[0] = value;
                _commandCount = 1;
                if (Length(value) is int length && length != 0)
                {
                    _phase = CommandPhase;
                    if (length == 1) { Start(); }
                }

                return;
            case 1:
                if (_phase != CommandPhase) { return; }
                _command[_commandCount++] = value;
                if (_commandCount == Length(_command[0])) { Start(); }
                return;
            case 2:
                if (value == 1) { Reset(); }
                return;
        }
    }

    /// <summary>
    ///  Reads the data register without taking the byte, so the data request and NMI stay as they are.
    /// </summary>
    /// <returns>The byte.</returns>
    public byte PeekData() => _data;

    /// <summary>
    ///  Reads the data register, taking the byte the chip offers.
    /// </summary>
    /// <returns>The byte.</returns>
    public byte ReadData()
    {
        DataRequest = false;
        return _data;
    }

    /// <summary>
    ///  Writes the data register, giving the byte the chip asks for.
    /// </summary>
    /// <param name="value">The byte.</param>
    public void WriteData(byte value)
    {
        if (!DataRequest) { return; }
        DataRequest = false;
        _data = value;
    }

    /// <summary>
    ///  Resets the chip: no command, the head unloaded, the output port clear.
    /// </summary>
    public void Reset()
    {
        Abandon();
        _operation = null;
        _phase = Idle;
        _commandCount = 0;
        _result = 0;
        _mode = 0xC0;
        _outputPort = 0;
        _scanSector = 0;
        _scanCount[0] = _scanCount[1] = 0;
        HeadLoaded = false;
        InterruptRequest = DataRequest = false;
        Sector = null;
        IsWriting = false;
    }

    // Keeps what a write or format cut off has written.
    private void Abandon()
    {
        _abandon?.Invoke();
        _abandon = null;
    }

    /// <summary>
    ///  Advances one CPU cycle.
    /// </summary>
    internal void Tick()
    {
        _time++;
        if (_operation is not null)
        {
            if (--_wait > 0) { return; }
            if (_operation.MoveNext())
            {
                _wait = Math.Max(1, _operation.Current);
                return;
            }

            _operation = null;
            return;
        }

        // An idle head unloads at its count of index pulses, at least one, counted from when it went idle.
        if (HeadLoaded
            && _indexCount != 15
            && (_time / RevolutionCycles) - (_idleSince / RevolutionCycles) >= Math.Max(1, (int)_indexCount))
        {
            HeadLoaded = false;
        }
    }

    // A command's length with its parameters, or 0 for none the chip knows.
    private static int Length(byte command) => (command & 0x3F) switch
    {
        0x00 or 0x04 => 6,
        0x0A or 0x0E or 0x12 or 0x16 or 0x1E => 3,
        0x0B or 0x0F or 0x13 or 0x17 or 0x1F or 0x1B => 4,
        0x23 => 6,
        0x29 => 2,
        0x2C => 1,
        0x35 => 5,
        0x3A => 3,
        0x3D => 2,
        _ => 0
    };

    private void Start()
    {
        _commandCount = 0;
        _drive = (_command[0] & 0x80) != 0 ? 1 : 0;
        byte command = (byte)(_command[0] & 0x3F);
        switch (command)
        {
            case 0x2C:
                _result = DriveStatus();
                _phase = ResultPhase;                       // result full, with no interrupt, as for any result
                return;
            case 0x35:
                Specify();
                _phase = Idle;
                return;
            case 0x3D:
                _result = ReadSpecial(_command[1]);
                _phase = ResultPhase;
                return;
            case 0x3A:
                WriteSpecial(_command[1], _command[2]);
                _phase = Idle;
                return;
        }

        _phase = Execute;
        _result = 0;
        IEnumerable<int> operation = command switch
        {
            0x29 => Seek(_command[1]),
            0x1B => ReadIds(),
            0x23 => FormatTrack(),
            0x00 or 0x04 => Transfer(VerifyKind),
            0x0A or 0x0B or 0x0E or 0x0F => Transfer(WriteKind),
            0x1E or 0x1F => Transfer(VerifyKind),
            _ => Transfer(ReadKind)
        };

        _operation = Finish(operation).GetEnumerator();
        _wait = 1;
    }

    private IEnumerable<int> Finish(IEnumerable<int> operation)
    {
        foreach (int wait in operation) { yield return wait; }
        Sector = null;
        IsWriting = false;
        DataRequest = false;
        _idleSince = _time;
        _phase = ResultPhase;
        InterruptRequest = true;
    }

    private byte DriveStatus()
    {
        FloppyDisk? disk = _disks[_drive];
        int status = Ready(1) ? 0x40 : 0;
        // The index hole passes only while a disk turns.
        if (Ready(_drive) && _time % RevolutionCycles < ByteCycles * 4) { status |= 0x10; }
        if (disk is { IsWriteProtected: true }) { status |= 0x08; }       // WR PROT: the disk is protected
        if (Ready(0)) { status |= 0x04; }
        if (_cylinders[_drive] == 0) { status |= 0x02; }                   // TRK0: the head is on track 0
        return (byte)status;
    }

    private bool Ready(int drive) => _disks[drive] is not null && HeadLoaded;

    private void Specify()
    {
        switch (_command[1])
        {
            case 0x0D:
                _stepRate = _command[2];
                _settle = _command[3];
                _indexCount = (byte)(_command[4] >> 4);
                _headLoad = (byte)(_command[4] & 0x0F);
                break;
            case 0x10 or 0x18:
                int drive = (_command[1] >> 3) & 1;
                _badTracks[drive][0] = _command[2];
                _badTracks[drive][1] = _command[3];
                _currentTracks[drive] = _command[4];
                break;
        }
    }

    private byte ReadSpecial(byte register) => (register & 0x3F) switch
    {
        0x06 => _scanSector,
        0x10 or 0x11 => _badTracks[0][register & 1],
        0x12 => _currentTracks[0],
        0x13 => _scanCount[0],
        0x14 => _scanCount[1],
        0x17 => _mode,
        0x18 or 0x19 => _badTracks[1][register & 1],
        0x1A => _currentTracks[1],
        0x22 => DriveStatus(),
        0x23 => (byte)((_command[0] & 0xC0) | _outputPort),
        _ => 0
    };

    private void WriteSpecial(byte register, byte value)
    {
        switch (register)
        {
            case 0x06:
                _scanSector = value;
                break;
            case 0x10 or 0x11:
                _badTracks[0][register & 1] = value;
                break;
            case 0x12:
                _currentTracks[0] = value;
                break;
            case 0x13 or 0x14:
                _scanCount[register - 0x13] = value;
                break;
            case 0x17:
                _mode = (byte)(value | 0xC0);
                break;
            case 0x18 or 0x19:
                _badTracks[1][register & 1] = value;
                break;
            case 0x1A:
                _currentTracks[1] = value;
                break;
            case 0x23:
                // STEP (bit 1) rising moves the head a cylinder, outward when the direction (bit 2) is set; the
                // current track register is left as it is.
                if ((value & 0x02) != 0 && (_outputPort & 0x02) == 0)
                {
                    _cylinders[_drive] = Math.Clamp(_cylinders[_drive] + ((value & 0x04) != 0 ? -1 : 1), 0, 83);
                }

                _outputPort = (byte)(value & 0x3F);
                HeadLoaded = (value & 0x08) != 0;
                _idleSince = _time;
                break;
        }
    }

    // Loads the head, then steps to a track; _ready says whether the drive is ready.
    private IEnumerable<int> LoadAndSeek(byte track)
    {
        if (!HeadLoaded)
        {
            HeadLoaded = true;
            yield return _headLoad * 8 * Milliseconds;
        }

        _ready = _disks[_drive] is not null;
        if (!_ready) { yield break; }
        foreach (int wait in Steps(track)) { yield return wait; }
    }

    // Steps the head to a track, then settles. The command's track is logical: the bad tracks, physical positions,
    // are left out of the numbering, so each one at or below where the track lands moves it a position further out,
    // and the IDs there still name the logical track. The current track register holds the physical position, and
    // the head steps one physical track at a time.
    private IEnumerable<int> Steps(byte track)
    {
        int physical = Physical(track);
        bool moved = false;
        while (_currentTracks[_drive] != physical)
        {
            bool outward = _currentTracks[_drive] > physical;
            _currentTracks[_drive] = (byte)(_currentTracks[_drive] + (outward ? -1 : 1));
            _cylinders[_drive] = Math.Clamp(_cylinders[_drive] + (outward ? -1 : 1), 0, 83);
            moved = true;
            yield return _stepRate * 2 * Milliseconds;
        }

        if (moved) { yield return _settle * 2 * Milliseconds; }
    }

    // A logical track's physical position: past each bad track at or below it, in order, up to 255.
    private int Physical(byte track)
    {
        int physical = track;
        byte first = Math.Min(_badTracks[_drive][0], _badTracks[_drive][1]);
        byte second = Math.Max(_badTracks[_drive][0], _badTracks[_drive][1]);
        foreach (byte bad in (ReadOnlySpan<byte>)[first, second])
        {
            if (IsBadTrack(bad) && bad <= physical) { physical++; }
        }

        return Math.Min(physical, 0xFF);
    }

    // A bad track register skips its track, but &FF, as the DFS sets them, is no bad track at all.
    private bool IsBadTrack(byte track) =>
        track != 0xFF && (track == _badTracks[_drive][0] || track == _badTracks[_drive][1]);

    private IEnumerable<int> Seek(byte track)
    {
        if (track != 0)
        {
            foreach (int wait in Steps(track)) { yield return wait; }
            yield break;
        }

        // Track 0: step out until the track 0 sensor, at most 255 steps; on track 0 already, the command is done.
        int steps = 0;
        for (; _cylinders[_drive] != 0; steps++)
        {
            if (steps == 255)
            {
                _result = TrackZeroNotFound;
                yield break;
            }

            _cylinders[_drive]--;
            yield return _stepRate * 2 * Milliseconds;
        }

        _currentTracks[_drive] = 0;
        if (steps != 0) { yield return _settle * 2 * Milliseconds; }
    }

    private IEnumerable<int> Transfer(int kind)
    {
        bool single = (_command[0] & 1) == 0;
        byte track = _command[1];
        int sector = _command[2];
        int count = single ? 1 : ((_command[3] - 1) & 0x1F) + 1;  // a count of 0 is 32
        int sizeCode = single ? 0 : _command[3] >> 5;
        bool deleted = (_command[0] & 0x04) != 0;
        foreach (int wait in LoadAndSeek(track)) { yield return wait; }
        if (!_ready || _disks[_drive] is not { } disk)
        {
            _result = NotReady;
            yield break;
        }

        if (kind == WriteKind && disk.IsWriteProtected)
        {
            _result = WriteProtected;
            yield break;
        }

        IsWriting = kind == WriteKind;
        for (int index = 0; index < count; index++, sector++)
        {
            Sector = sector;
            foreach (int wait in FindSector(track, sector)) { yield return wait; }
            if (_found is not { } found)
            {
                _result = SectorNotFound;
                yield break;
            }

            // The data field: gap 2, the sync bytes and the mark, then as many bytes as the command's length, whatever
            // the sector holds. A read past a shorter sector's end takes the gap's &FF bytes; a write past it runs
            // into the gap, which nothing keeps. Either way the CRC is not where the field's own length puts it.
            yield return 18 * ByteCycles;
            int size = 128 << sizeCode;
            int held = found.Data.Length;
            byte[] buffer = found.Data.ToArray();
            byte mark = deleted ? (byte)0xF8 : (byte)0xFB;
            if (kind == WriteKind) { _abandon = () => disk.Write(found, buffer, mark, crcError: true); }
            for (int position = 0; position < size; position++)
            {
                if (kind == ReadKind)
                {
                    if (DataRequest)
                    {
                        _result = LateDma;
                        yield break;
                    }

                    _data = position < held ? found.Data[position] : (byte)0xFF;
                    DataRequest = true;
                }
                else if (kind == WriteKind)
                {
                    DataRequest = true;
                }

                yield return ByteCycles;
                if (kind == WriteKind)
                {
                    if (DataRequest)
                    {
                        // The bytes before the late one are on the disk already; the rest of the field is what was
                        // there, with no CRC to match.
                        Abandon();
                        _result = LateDma;
                        yield break;
                    }

                    if (position < held) { buffer[position] = _data; }
                }
            }

            // The CRC, which matches the field only when the command's length is the sector's.
            yield return 2 * ByteCycles;
            if (kind == WriteKind)
            {
                _abandon = null;
                disk.Write(found, buffer, mark, crcError: size != held);
                continue;
            }

            if (found.CrcError || size != held)
            {
                _result = DataCrcError;
                yield break;
            }

            if (found.DataAddressMark == 0xF8) { _result |= DeletedData; }
        }
    }

    // Waits for the sector's ID to come under the head, into _found: up to two revolutions, or an ID from
    // another track, finds none.
    private IEnumerable<int> FindSector(byte track, int sector)
    {
        _found = null;
        IReadOnlyList<FloppySector> sectors = _disks[_drive]?.Track(_cylinders[_drive], Side) ?? [];
        long end = _time + (2 * RevolutionCycles);
        if (sectors.Count == 0)
        {
            yield return (int)(end - _time);
            yield break;
        }

        while (true)
        {
            (int index, int wait) = NextId(sectors.Count);
            if (_time + wait > end)
            {
                yield return (int)(end - _time);
                yield break;
            }

            // The ID field's 7 bytes pass.
            yield return wait + (7 * ByteCycles);
            FloppySector candidate = sectors[index];
            if (candidate.Track != track) { yield break; }

            // The chip matches the track and sector only: the length is the command's.
            if (candidate.Sector == sector)
            {
                _found = candidate;
                yield break;
            }
        }
    }

    // The next ID field to start under the head, and the cycles until it does. A track's IDs are spread evenly after
    // 16 bytes of gap from the index.
    private (int Index, int Wait) NextId(int count)
    {
        int angle = (int)(_time % RevolutionCycles);
        int spacing = (TrackBytes - 16) * ByteCycles / count;
        for (int index = 0; index < count; index++)
        {
            int start = (16 * ByteCycles) + (index * spacing);
            if (start > angle) { return (index, start - angle); }
        }

        return (0, RevolutionCycles - angle + (16 * ByteCycles));
    }

    // An FM ID field's CRC-CCITT, from &FFFF over the ID mark (&FE) and the four ID bytes.
    private static ushort IdCrc(FloppySector sector)
    {
        int crc = 0xFFFF;
        foreach (byte value in (byte[])[0xFE, sector.Track, sector.Side, sector.Sector, sector.SizeCode])
        {
            crc ^= value << 8;
            for (int bit = 0; bit < 8; bit++) { crc = (crc & 0x8000) != 0 ? (crc << 1) ^ 0x1021 : crc << 1; }
        }

        return (ushort)crc;
    }

    private IEnumerable<int> ReadIds()
    {
        foreach (int wait in LoadAndSeek(_command[1])) { yield return wait; }
        if (!_ready || _disks[_drive] is not { } disk)
        {
            _result = NotReady;
            yield break;
        }

        IReadOnlyList<FloppySector> sectors = disk.Track(_cylinders[_drive], Side);
        if (sectors.Count == 0)
        {
            yield return 2 * RevolutionCycles;
            _result = SectorNotFound;
            yield break;
        }

        int count = Math.Max(1, (int)_command[3]);
        for (int id = 0; id < count; id++)
        {
            (int index, int wait) = NextId(sectors.Count);
            yield return wait;
            FloppySector sector = sectors[index];

            // The whole ID field after its mark: the four ID bytes and their CRC, high byte first.
            ushort crc = IdCrc(sector);
            byte[] field = [sector.Track, sector.Side, sector.Sector, sector.SizeCode, (byte)(crc >> 8), (byte)crc];
            foreach (byte value in field)
            {
                yield return ByteCycles;
                if (DataRequest)
                {
                    _result = LateDma;
                    yield break;
                }

                _data = value;
                DataRequest = true;
            }

            yield return 3 * ByteCycles;
        }
    }

    // Format: track, gap 3, count and size, gap 5, gap 1. From the index, each sector's 4 ID bytes are asked for as
    // its ID field is written, then its data is written as &E5.
    private IEnumerable<int> FormatTrack()
    {
        byte track = _command[1];
        int gap3 = _command[2];
        int count = ((_command[3] - 1) & 0x1F) + 1;               // a count of 0 is 32
        int sizeCode = _command[3] >> 5;
        int gap5 = _command[4];
        int gap1 = _command[5];
        foreach (int wait in LoadAndSeek(track)) { yield return wait; }
        if (!_ready || _disks[_drive] is not { } disk)
        {
            _result = NotReady;
            yield break;
        }

        if (disk.IsWriteProtected)
        {
            _result = WriteProtected;
            yield break;
        }

        IsWriting = true;
        yield return RevolutionCycles - (int)(_time % RevolutionCycles);

        // Formatting runs to the next index, as the chip's does, writing gap 4 after the last sector and keeping only
        // the sectors whose data was written by then: sixteen 256-byte sectors do not fit a track. A late DMA ends it
        // at once, with the sectors written before it kept.
        long end = _time + RevolutionCycles;
        List<FloppySector> formatted = [];
        int cylinder = _cylinders[_drive];
        int side = Side;
        _abandon = () => disk.Format(cylinder, side, formatted);
        yield return (gap5 == 0 ? gap1 : gap5 + 7 + gap1) * ByteCycles;

        int size = 128 << sizeCode;                             // 128 to 16384: 2048 fits a track once, larger never
        byte[] fill = new byte[size];
        fill.AsSpan().Fill(0xE5);
        int field = (2 + 11 + 7 + size + 2) * ByteCycles;
        for (int index = 0; index < count && _result != LateDma; index++)
        {
            if (_time + ((7 + 4) * ByteCycles) + field > end) { break; }

            Sector = index;
            yield return 7 * ByteCycles;
            byte[] id = new byte[4];
            for (int position = 0; position < 4 && _result != LateDma; position++)
            {
                DataRequest = true;
                yield return ByteCycles;
                if (DataRequest)
                {
                    _result = LateDma;
                }
                else
                {
                    id[position] = _data;
                }
            }

            if (_result == LateDma) { break; }
            yield return field;
            formatted.Add(new(id[0], id[1], id[2], fill, doubleDensity: false));
            // Gap 3 that reaches the index ends the track there: no sector follows it.
            if (_time + (gap3 * ByteCycles) >= end) { break; }
            yield return gap3 * ByteCycles;
        }

        _abandon = null;
        disk.Format(cylinder, side, formatted);
        if (_result != LateDma && _time < end) { yield return (int)(end - _time); }
    }
}
