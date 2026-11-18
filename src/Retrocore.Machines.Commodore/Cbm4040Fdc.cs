// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Media.Commodore;

namespace Retrocore.Machines.Commodore;

/// <summary>
///  The 2040 and 4040's read/write electronics: the clock recovery that splits the flux into bit cells, the
///  10-bit shift registers, the sync and byte counters, and the GCR PROM that decodes what is read and encodes what
///  is written.
/// </summary>
/// <remarks>
///  <para>
///   The logic runs from the drive's 16 MHz clock. A counter loaded with the speed zone counts to 16 to time a
///   quarter of a bit, and a flux change restarts it; the second quarter shifts the next bit in, a 1 if a flux change
///   came within the last quarters. Ten ones in a row are a sync mark. After sync, every tenth bit is a byte, which
///   pulses READY to the controller's VIA, whose port A reads the PROM's decoding of the shift register. Writing,
///   the PROM encodes port A of the 6530 into ten bits that shift out to the head, one at each bit time.
///  </para>
/// </remarks>
public sealed class Cbm4040Fdc
{
    private readonly byte[] _gcr;
    private readonly CommodoreFloppyDrive[] _drives;

    private int _cycleCounter;
    private int _cellCounter;
    private int _shiftRegister;
    private int _shiftRegisterWrite;
    private int _bitCounter;
    private int _i;
    private int _e;

    // The flux the selected drive's head passes next, as a tick of the disk's turn; past a turn's end once it wraps.
    private long _fluxTick = long.MaxValue;
    private CommodoreDisk? _fluxDisk;
    private int _fluxPosition = -1;
    private bool _fluxDirty = true;

    // The cell the head writes next: a write starts at the cell under the head and puts each bit in the next cell.
    // A bit's time and a cell's differ by a fraction of a clock, which over a write of a few turns adds up to more
    // than a cell; following the head instead would drop or double a bit there. -1 until the next write starts.
    private int _writeCell = -1;

    private int _readyChanges;
    private int _errorChanges;

    /// <summary>
    ///  Builds the electronics for two mechanisms.
    /// </summary>
    /// <param name="gcr">The GCR PROM, 2K.</param>
    /// <param name="drive0">Drive 0.</param>
    /// <param name="drive1">Drive 1.</param>
    internal Cbm4040Fdc(ReadOnlySpan<byte> gcr, CommodoreFloppyDrive drive0, CommodoreFloppyDrive drive1)
    {
        _gcr = gcr.ToArray();
        _drives = [drive0, drive1];
        Reset();
    }

    /// <summary>
    ///  Gets or sets the byte the 6530's port A gives to be written.
    /// </summary>
    public byte WriteData { get; set; }

    /// <summary>
    ///  Gets or sets which mechanism the head electronics use, 0 or 1.
    /// </summary>
    public int DriveSelect
    {
        get => field;
        set
        {
            if (value == field) { return; }
            field = value;
            _fluxDirty = true;
            _writeCell = -1;
        }
    }

    /// <summary>
    ///  Gets or sets the speed zone, 0-3: a bit takes 4 × (16 - zone) clocks.
    /// </summary>
    public int Zone { get; set; }

    /// <summary>
    ///  Gets or sets MODE SEL, the VIA's CA2: high to write a sync mark's ones rather than encode a byte.
    /// </summary>
    public bool ModeSelect { get; set; }

    /// <summary>
    ///  Gets or sets R/W SEL, the VIA's CB2: high to read, low to write.
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
        }
    }

    /// <summary>
    ///  Gets SYNC, low while the shift register holds a sync mark's ten ones.
    /// </summary>
    public bool Sync { get; private set; } = true;

    /// <summary>
    ///  Gets READY, low for an instant as each byte after sync is in.
    /// </summary>
    public bool Ready { get; private set; } = true;

    /// <summary>
    ///  Gets ERROR, high when the bits read are no GCR code.
    /// </summary>
    public bool Error { get; private set; }

    /// <summary>
    ///  Gets how many times READY changed during the last <see cref="Advance(int)"/>: a pulse is two.
    /// </summary>
    public int ReadyChanges => _readyChanges;

    /// <summary>
    ///  Gets how many times ERROR changed during the last <see cref="Advance(int)"/>.
    /// </summary>
    public int ErrorChanges => _errorChanges;

    /// <summary>
    ///  Gets the byte the PROM decodes from the shift register, for the VIA's port A.
    /// </summary>
    public byte ReadData => (byte)(((_e >> 6) & 1) << 7 | ((_i >> 7) & 1) << 6 | (_e & 0x33) | ((_e >> 2) & 1) << 3 | (_i & 0x04));

    /// <summary>
    ///  Gets WPS for the selected mechanism: high when its disk is write protected or it is empty.
    /// </summary>
    public bool WriteProtect => _drives[DriveSelect].Disk is not { IsWriteProtected: false };

    /// <summary>
    ///  Gets the shift register, for tests.
    /// </summary>
    internal int ShiftRegister => _shiftRegister;

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
        Ready = true;
        Error = true;
        _fluxDirty = true;
        Decode();
    }

    /// <summary>
    ///  Runs the logic and turns the disks.
    /// </summary>
    /// <param name="ticks">16 MHz clocks.</param>
    public void Advance(int ticks)
    {
        _readyChanges = 0;
        _errorChanges = 0;

        CommodoreFloppyDrive selected = _drives[DriveSelect];
        CommodoreFloppyDrive other = _drives[DriveSelect ^ 1];
        other.Turn(ticks);

        // With both motors off the logic is held idle.
        if (!selected.Motor && !other.Motor)
        {
            SetReady(ready: true);
            Sync = true;
            SetError(error: true);
            Decode();
            return;
        }

        CommodoreDisk? disk = selected.Motor ? selected.Disk : null;
        bool reading = ReadSelect && disk is not null;
        if (reading && (_fluxDirty || !ReferenceEquals(disk, _fluxDisk) || selected.Position != _fluxPosition))
        {
            FindFlux(selected, from: selected.Angle);
        }

        while (ticks > 0)
        {
            int toCell = 16 - _cycleCounter;
            long toFlux = reading ? _fluxTick - selected.Angle : long.MaxValue;
            if (toFlux <= toCell && toFlux <= ticks)
            {
                int step = (int)Math.Max(toFlux, 1);
                Spin(selected, step);
                ticks -= step;
                _cycleCounter = Zone;
                Clock(0);
                FindFlux(selected, from: selected.Angle + 1);
            }
            else if (toCell <= ticks)
            {
                Spin(selected, toCell);
                ticks -= toCell;
                _cycleCounter = Zone;
                Clock((_cellCounter + 1) & 0x0F);
            }
            else
            {
                Spin(selected, ticks);
                _cycleCounter += ticks;
                ticks = 0;
            }
        }

        Decode();
    }

    // Turns the selected disk, keeping the next flux change's tick in the same turn.
    private void Spin(CommodoreFloppyDrive drive, int ticks)
    {
        long before = drive.Angle;
        drive.Turn(ticks);
        if (drive.Angle < before && _fluxTick != long.MaxValue) { _fluxTick -= CommodoreFloppyDrive.TicksPerTurn; }
    }

    // The cell counter takes a new value: its bit 1 rising takes a bit in (and writes one), falling ends one.
    private void Clock(int cell)
    {
        bool wasHigh = (_cellCounter & 2) != 0;
        bool high = (cell & 2) != 0;
        _cellCounter = cell;
        bool rising = !wasHigh && high;
        bool falling = wasHigh && !high;

        if (rising)
        {
            _shiftRegister = ((_shiftRegister << 1) | ((cell & 0x0C) == 0 ? 1 : 0)) & 0x3FF;
            if (!ReadSelect) { WriteBit((_shiftRegisterWrite & 0x200) != 0); }
        }

        bool sync = !(_shiftRegister == 0x3FF && ReadSelect);
        if (!sync)
        {
            _bitCounter = 0;
        }
        else if (rising && Sync)
        {
            if (++_bitCounter == 10) { _bitCounter = 0; }
        }

        Sync = sync;
        Decode();

        bool ready = !(falling && _bitCounter == 9);
        if (!ready)
        {
            _shiftRegisterWrite = ((_e & 0xC0) << 2) | (_i & 0x80) | ((_e & 0x3C) << 1) | (_i & 0x04) | (_e & 0x03);
        }
        else if (falling)
        {
            _shiftRegisterWrite = (_shiftRegisterWrite << 1) & 0x3FF;
        }

        SetReady(ready);
        SetError(!((_e & 0x08) != 0 || ready));

        // READY lasts one clock.
        if (!ready)
        {
            SetReady(ready: true);
            SetError(!((_e & 0x08) != 0));
        }
    }

    private void Decode()
    {
        _i = ReadSelect
            ? 0x400 | _shiftRegister
            : ((WriteData & 0xF0) << 1) | (ModeSelect ? 0x10 : 0) | (WriteData & 0x0F);

        _e = _gcr[_i];
    }

    private void SetReady(bool ready)
    {
        if (ready == Ready) { return; }
        _readyChanges++;
        Ready = ready;
    }

    private void SetError(bool error)
    {
        if (error == Error) { return; }
        _errorChanges++;
        Error = error;
    }

    // Writes the next bit: a 1 is a flux change.
    private void WriteBit(bool bit)
    {
        CommodoreFloppyDrive drive = _drives[DriveSelect];
        if (!drive.Motor || drive.Disk is not { IsWriteProtected: false } disk) { return; }
        int count = disk.BitCount(drive.Position);
        if (count == 0) { return; }
        if (_writeCell < 0 || _writeCell >= count)
        {
            _writeCell = (int)(drive.Angle * count / CommodoreFloppyDrive.TicksPerTurn);
        }

        disk.Write(drive.Position, _writeCell, bit);
        _writeCell = (_writeCell + 1) % count;
    }

    // Finds the first flux change at or after a tick of the turn.
    private void FindFlux(CommodoreFloppyDrive drive, long from)
    {
        _fluxDirty = false;
        _fluxDisk = drive.Disk;
        _fluxPosition = drive.Position;
        _fluxTick = long.MaxValue;
        if (_fluxDisk is not { } disk) { return; }

        int count = disk.BitCount(drive.Position);
        if (count == 0) { return; }

        const long turn = CommodoreFloppyDrive.TicksPerTurn;
        long cell = ((from * count) + turn - 1) / turn;
        for (int scanned = 0; scanned <= count; scanned++, cell++)
        {
            int index = (int)(cell % count);
            if (disk.Read(drive.Position, index))
            {
                _fluxTick = cell * turn / count;
                return;
            }
        }
    }
}
