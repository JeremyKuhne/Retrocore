// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Media.Commodore;

namespace Retrocore.Machines.Commodore.Serial;

/// <summary>
///  The 1541's gate array, 325572-01 (the 64H105), as MAME models it with its 64H156: the clock recovery that splits the flux into bit cells, the
///  read and write shift registers, SYNC, and BYTE READY. The DOS does the GCR coding itself.
/// </summary>
/// <remarks>
///  <para>
///   The logic runs from the drive's 16 MHz clock. A counter loaded with the density select (the speed zone, 0-3)
///   counts to 16 to time a quarter of a bit, and a flux change restarts it. When the quarters' counter's bit 1
///   rises, the next bit shifts in: a 1 if a flux change came within the last four quarters. Ten ones in a row are
///   SYNC, which holds the byte counter; after it every eighth bit pulls BYTE READY low, if SOE (VIA 2's CA2) lets it,
///   for the half bit until the counter's bit 1 rises again.
///  </para>
///  <para>
///   BYTE READY goes to the processor's SO pin, whose falling edge sets the overflow flag the DOS polls with
///   <c>BVC</c>, and to VIA 2's CA1, which latches port A. Port A reads the read shift register's low byte.
///   Writing (OE, VIA 2's CB2, low), the eighth bit loads the write shift register from port A, which shifts its top
///   bit to the head as the quarters' counter's bit 1 falls; a 1 is a flux change.
///  </para>
/// </remarks>
public sealed class Cbm1541GateArray
{
    private readonly CommodoreFloppyDrive _drive;

    private int _cycleCounter;
    private int _cellCounter;
    private int _shiftRegister;
    private int _shiftRegisterWrite;
    private int _bitCounter;
    private bool _motor;

    // The flux the head passes next, as a tick of the disk's turn; past a turn's end once it wraps.
    private long _fluxTick = long.MaxValue;
    private CommodoreDisk? _fluxDisk;
    private int _fluxPosition = -1;
    private bool _fluxDirty = true;

    // The cell the head writes next, on the disk and track the write began on, or -1 until a write starts.
    private int _writeCell = -1;
    private CommodoreDisk? _writeDisk;
    private int _writePosition = -1;

    private int _byteChanges;
    private int _pendingByteChanges;

    /// <summary>
    ///  Builds the gate array for the drive's mechanism.
    /// </summary>
    /// <param name="drive">The mechanism.</param>
    internal Cbm1541GateArray(CommodoreFloppyDrive drive)
    {
        _drive = drive;
        Reset();
    }

    /// <summary>
    ///  Gets or sets the byte VIA 2's port A gives to be written.
    /// </summary>
    public byte WriteData { get; set; }

    /// <summary>
    ///  Gets or sets the density select, VIA 2's PB5-PB6: a bit takes 4 × (16 - zone) clocks.
    /// </summary>
    public int Zone { get; set; }

    /// <summary>
    ///  Gets or sets SOE, VIA 2's CA2: whether BYTE READY is let through.
    /// </summary>
    public bool ByteReadyEnabled
    {
        get => field;
        set
        {
            if (value == field) { return; }
            field = value;

            // A change here, between runs, is counted in the next run's, so the drive passes it to CA1 and SO.
            int before = _byteChanges;
            SetByte(!((_bitCounter & 7) == 7 && value && (_cellCounter & 2) == 0) || !_motor);
            _pendingByteChanges += _byteChanges - before;
        }
    }

    /// <summary>
    ///  Gets or sets OE, VIA 2's CB2: high to read, low to write.
    /// </summary>
    public bool ReadSelect
    {
        get => field;
        set
        {
            if (value == field) { return; }
            field = value;
            _fluxDirty = true;
            _writeCell = -1;
            _drive.Writing = !value;
        }
    }

    /// <summary>
    ///  Gets SYNC, low while the read shift register holds ten ones.
    /// </summary>
    public bool Sync { get; private set; } = true;

    /// <summary>
    ///  Gets BYTE READY, low for half a bit as each byte is in (or, writing, taken).
    /// </summary>
    public bool ByteReady { get; private set; } = true;

    /// <summary>
    ///  Gets how many times BYTE READY changed during the last <see cref="Advance(int)"/>, or since the one before it
    ///  as SOE changed: a pulse is two.
    /// </summary>
    public int ByteReadyChanges => _byteChanges;

    /// <summary>
    ///  Gets the read shift register's low byte, for VIA 2's port A.
    /// </summary>
    public byte ReadData => (byte)_shiftRegister;

    /// <summary>
    ///  Gets the read shift register's low byte as it was when BYTE READY last fell, which VIA 2 latches.
    /// </summary>
    public byte ByteData { get; private set; }

    /// <summary>
    ///  Gets whether the disk in the drive is write protected: its notch is covered, so the sensor's light is blocked.
    ///  With no disk the light gets through, as through an open notch.
    /// </summary>
    public bool WriteProtect => _drive.Disk is { IsWriteProtected: true };

    /// <summary>
    ///  Returns the logic to its idle state.
    /// </summary>
    public void Reset()
    {
        _cycleCounter = 0;
        _cellCounter = 0;
        _shiftRegister = 0;
        _shiftRegisterWrite = 0;
        _bitCounter = 0;
        Sync = true;
        ByteReady = true;
        _fluxDirty = true;
        _writeCell = -1;
    }

    /// <summary>
    ///  Runs the logic and turns the disk.
    /// </summary>
    /// <param name="ticks">16 MHz clocks.</param>
    public void Advance(int ticks)
    {
        _byteChanges = _pendingByteChanges;
        _pendingByteChanges = 0;
        if (_drive.Motor != _motor)
        {
            // The logic starts from cleared counters as the motor comes on, and is held idle while it is off; either
            // way BYTE READY goes high, which counts as a change if it was low.
            _motor = _drive.Motor;
            bool wasLow = !ByteReady;
            Reset();
            if (wasLow) { _byteChanges++; }
        }

        if (!_motor) { return; }

        CommodoreDisk? disk = _drive.Disk;
        bool reading = ReadSelect && disk is not null;
        if (reading && (_fluxDirty || !ReferenceEquals(disk, _fluxDisk) || _drive.Position != _fluxPosition))
        {
            FindFlux(from: _drive.Angle);
        }

        while (ticks > 0)
        {
            int toCell = 16 - _cycleCounter;
            long toFlux = reading ? _fluxTick - _drive.Angle : long.MaxValue;
            if (toFlux < toCell && toFlux < ticks)
            {
                // A flux change restarts the counters, in the tick it comes in.
                int step = (int)toFlux + 1;
                Spin(step);
                ticks -= step;
                _cycleCounter = Zone;
                _cellCounter = 0;

                // The next clock sees the counter's bit 1 low, and BYTE READY with it.
                SetByte(!((_bitCounter & 7) == 7 && ByteReadyEnabled));
                FindFlux(from: _drive.Angle);
            }
            else if (toCell <= ticks)
            {
                Spin(toCell);
                ticks -= toCell;
                _cycleCounter = Zone;
                Clock((_cellCounter + 1) & 0x0F);
            }
            else
            {
                Spin(ticks);
                _cycleCounter += ticks;
                ticks = 0;
            }
        }
    }

    // Turns the disk, keeping the next flux change's tick in the same turn.
    private void Spin(int ticks)
    {
        long before = _drive.Angle;
        _drive.Turn(ticks);
        if (_drive.Angle < before && _fluxTick != long.MaxValue) { _fluxTick -= CommodoreFloppyDrive.TicksPerTurn; }
    }

    // The quarters' counter takes its next value: its bit 1 rising takes a bit in, falling writes one.
    private void Clock(int cell)
    {
        bool rising = (_cellCounter & 2) == 0 && (cell & 2) != 0;
        bool falling = (_cellCounter & 2) != 0 && (cell & 2) == 0;
        _cellCounter = cell;

        if (rising) { _shiftRegister = ((_shiftRegister << 1) | ((cell & 0x0C) == 0 ? 1 : 0)) & 0x3FF; }
        if (falling && !ReadSelect) { WriteBit((_shiftRegisterWrite & 0x80) != 0); }

        bool sync = !(_shiftRegister == 0x3FF && ReadSelect);
        if (!sync)
        {
            _bitCounter = 8;
        }
        else if (rising && Sync)
        {
            _bitCounter = (_bitCounter + 1) & 0x0F;
        }

        bool eighth = (_bitCounter & 7) == 7;
        if (eighth && (cell & 3) == 3)
        {
            _shiftRegisterWrite = ReadSelect ? _shiftRegister & 0xFF : WriteData;
        }
        else if (rising)
        {
            _shiftRegisterWrite = (_shiftRegisterWrite << 1) & 0xFF;
        }

        SetByte(!(eighth && ByteReadyEnabled && (cell & 2) == 0));
        Sync = sync;
    }

    private void SetByte(bool high)
    {
        if (high == ByteReady) { return; }
        _byteChanges++;
        ByteReady = high;
        if (!high) { ByteData = (byte)_shiftRegister; }
    }

    // Writes the next bit: a 1 is a flux change.
    private void WriteBit(bool bit)
    {
        if (_drive.Disk is not { IsWriteProtected: false } disk)
        {
            _writeCell = -1;
            return;
        }

        int count = disk.BitCount(_drive.Position);
        if (count == 0)
        {
            // A track nothing was recorded on takes cells at the zone it is written at.
            count = GcrLayout.TrackBits(Zone);
            disk.SetTrack(_drive.Position, new byte[count / 8], count, Zone);
            _fluxDirty = true;
        }

        // A write goes on cell by cell only on the track and disk it began on; after a step or a new disk it starts
        // again at the cell under the head.
        if (_writeCell < 0 || _writeCell >= count || !ReferenceEquals(disk, _writeDisk) || _drive.Position != _writePosition)
        {
            _writeCell = (int)(_drive.Angle * count / CommodoreFloppyDrive.TicksPerTurn);
            _writeDisk = disk;
            _writePosition = _drive.Position;
        }

        disk.Write(_drive.Position, _writeCell, bit);
        _writeCell = (_writeCell + 1) % count;
    }

    // Finds the first flux change at or after a tick of the turn.
    private void FindFlux(long from)
    {
        _fluxDirty = false;
        _fluxDisk = _drive.Disk;
        _fluxPosition = _drive.Position;
        _fluxTick = long.MaxValue;
        if (_fluxDisk is not { } disk) { return; }

        int count = disk.BitCount(_drive.Position);
        if (count == 0) { return; }

        const long turn = CommodoreFloppyDrive.TicksPerTurn;
        long cell = ((from * count) + turn - 1) / turn;
        for (int scanned = 0; scanned <= count; scanned++, cell++)
        {
            int index = (int)(cell % count);
            if (disk.Read(_drive.Position, index))
            {
                _fluxTick = cell * turn / count;
                return;
            }
        }
    }
}
