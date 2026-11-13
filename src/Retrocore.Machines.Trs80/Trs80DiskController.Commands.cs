// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Media.Trs80;

namespace Retrocore.Machines.Trs80;

public sealed partial class Trs80DiskController
{
    private const int MaximumCylinder = 79;

    // Step rates in milliseconds, by the command's low two bits.
    private static readonly int[] s_stepRates1771 = [6, 6, 10, 20];
    private static readonly int[] s_stepRates1791 = [6, 12, 20, 30];

    private int _direction = 1;

    // The gap between an ID field and its data, and the bytes of a data field after the data (its CRC).
    private const int IdToDataBytes = 30;
    private const int CrcBytes = 2;

    private void Command(byte value)
    {
        // A Percom doubler takes $FE and $FF as density selects rather than commands.
        if ((_doubler & Trs80Doubler.Percom) != 0 && value is 0xFE or 0xFF)
        {
            _doubleDensity = value == 0xFF;
            return;
        }

        if ((value & 0xF0) == 0xD0)
        {
            if (IsBusy)
            {
                _phase = Phase.Idle;
                _status &= unchecked((byte)~Busy);
            }
            else
            {
                _typeOne = true;
            }

            _request = false;
            InterruptRequest = (value & 0x08) != 0;
            return;
        }

        if (IsBusy) { return; }
        _command = value;
        _status = Busy;
        _request = false;
        InterruptRequest = false;
        _typeOne = (value & 0x80) == 0;
        if (_typeOne)
        {
            StartStep();
            return;
        }

        if (!Ready)
        {
            _status = NotReady;
            Finish();
            return;
        }

        bool write = (value & 0xE0) == 0xA0 || (value & 0xF0) == 0xF0;
        if (write && Current?.WriteProtected == true)
        {
            _status = WriteProtect;
            Finish();
            return;
        }

        // The E bit adds the 15 ms head-load delay.
        _wait = (value & 0x04) != 0 ? _settleCycles : 1;
        _phase = Phase.Delaying;
    }

    private void StartStep()
    {
        int cylinder = _selected >= 0 ? _cylinders[_selected] : 0;
        switch (_command >> 4)
        {
            case 0:
                // Restore steps out to track 0.
                _direction = -1;
                _steps = cylinder;
                Track = 0;
                break;
            case 1:
                _direction = Data > Track ? 1 : -1;
                _steps = Math.Abs(Data - Track);
                Track = Data;
                break;
            default:
                if ((_command & 0x40) != 0) { _direction = (_command & 0x20) != 0 ? -1 : 1; }
                _steps = 1;

                // The u bit updates the track register.
                if ((_command & 0x10) != 0) { Track = (byte)(Track + _direction); }
                break;
        }

        _wait = StepCycles();
        _phase = Phase.Stepping;
        if (_steps == 0) { _wait = 1; }
    }

    private int StepCycles()
    {
        int[] rates = Is179x ? s_stepRates1791 : s_stepRates1771;
        return rates[_command & 3] * _cyclesPerMillisecond / (_eightInch ? 2 : 1);
    }

    private void Run()
    {
        if (_wait > 0 && --_wait > 0) { return; }
        switch (_phase)
        {
            case Phase.Stepping:
                if (_steps > 0)
                {
                    if (_selected >= 0)
                    {
                        _cylinders[_selected] = Math.Clamp(_cylinders[_selected] + _direction, 0, MaximumCylinder);
                    }

                    if (--_steps > 0)
                    {
                        _wait = StepCycles();
                        return;
                    }
                }

                // The V bit verifies the track; h and V load the head.
                if ((_command & 0x0C) != 0) { _status |= HeadLoaded; }
                if ((_command & 0x04) != 0)
                {
                    _wait = _settleCycles;
                    _phase = Phase.Verifying;
                    return;
                }

                Finish();
                return;
            case Phase.Verifying:
                if (!Ready || Current is not { } disk || !HasTrack(disk)) { _status |= SeekError; }
                Finish();
                return;
            case Phase.Delaying:
                _indexPulses = 0;
                _phase = (_command & 0xF0) is 0xE0 or 0xF0 ? Phase.AwaitingIndex : Phase.Searching;
                return;
            case Phase.Searching:
                Search();
                return;
            case Phase.Reading:
                ReadByte();
                return;
            case Phase.Writing:
                WriteByte();
                return;
            case Phase.AwaitingIndex:
                AwaitIndex();
                return;
            case Phase.WritingTrack:
                WriteTrackByte();
                return;
        }
    }

    // Whether the head's track has an ID field for the track register in the selected density.
    private bool HasTrack(FloppyDisk disk)
    {
        foreach (FloppySector sector in disk.Track(_cylinders[_selected], Side))
        {
            if (sector.Track == Track && sector.DoubleDensity == _doubleDensity) { return true; }
        }

        return false;
    }

    // Waits for the next ID field: any for read address, else the one the track and sector registers name.
    private void Search()
    {
        if (!Ready || _selected < 0 || Current is not { } disk)
        {
            _status |= NotReady;
            Finish();
            return;
        }

        if (_indexPulses >= (Is179x ? 5 : 2))
        {
            _status |= SeekError;
            Finish();
            return;
        }

        IReadOnlyList<FloppySector> sectors = disk.Track(_cylinders[_selected], Side);
        if (sectors.Count == 0) { return; }
        int spacing = (_rotationCycles - _indexPulseCycles) / sectors.Count;
        long offset = _rotation - _indexPulseCycles;
        if (offset < 0 || offset % spacing != 0 || offset / spacing >= sectors.Count) { return; }
        FloppySector sector = sectors[(int)(offset / spacing)];
        if (sector.DoubleDensity != _doubleDensity) { return; }
        bool address = (_command & 0xF0) == 0xC0;
        if (!address && (sector.Track != Track || sector.Sector != Sector)) { return; }

        _sector = sector;
        _position = 0;
        if (address)
        {
            ushort crc = IdCrc(sector);
            _buffer = [sector.Track, sector.Side, sector.Sector, sector.SizeCode, (byte)(crc >> 8), (byte)crc];
            Sector = sector.Track;
            _wait = ByteCycles;
            _phase = Phase.Reading;
            return;
        }

        _wait = IdToDataBytes * ByteCycles;
        if ((_command & 0xE0) == 0xA0)
        {
            _buffer = new byte[sector.Data.Length];
            _request = true;
            _phase = Phase.Writing;
            return;
        }

        _buffer = sector.Data;
        _phase = Phase.Reading;
    }

    private void ReadByte()
    {
        if (_position < _buffer.Length)
        {
            if (_request) { _status |= TrackZeroOrLost; }
            Data = _buffer[_position++];
            _request = true;
            _wait = ByteCycles;
            return;
        }

        // The data's CRC passes, then the command ends, or a multiple-sector read goes on to the next sector.
        bool address = (_command & 0xF0) == 0xC0;
        if (!address && _sector is { } sector)
        {
            _status |= Is179x
                ? (sector.DataAddressMark == 0xFB ? (byte)0 : HeadLoaded)
                : (byte)((0xFB - sector.DataAddressMark) << 5);

            if (sector.CrcError) { _status |= CrcError; }
        }

        bool multiple = !address && _sector is not null && (_command & 0x10) != 0;
        if (multiple && (_status & CrcError) == 0)
        {
            Sector++;
            _indexPulses = 0;
            _phase = Phase.Searching;
            _wait = CrcBytes * ByteCycles;
            return;
        }

        Finish();
    }

    // The first byte must be in the data register when the data field starts, or the write ends with lost data.
    private void WriteByte()
    {
        if (_request)
        {
            _status |= TrackZeroOrLost;
            if (_position == 0)
            {
                Finish();
                return;
            }
        }

        _buffer[_position++] = _request ? (byte)0 : Data;
        if (_position < _buffer.Length)
        {
            _request = true;
            _wait = ByteCycles;
            return;
        }

        if (_sector is { } sector)
        {
            _buffer.CopyTo(sector.Data, 0);
            _changed[_selected] = true;

            // The FD1771 writes the mark its a1 a0 bits select; the WD1791's a0 selects $F8.
            sector.DataAddressMark = Is179x
                ? ((_command & 1) != 0 ? (byte)0xF8 : (byte)0xFB)
                : (byte)(0xFB - (_command & 3));

            sector.CrcError = false;
        }

        if ((_command & 0x10) != 0)
        {
            Sector++;
            _indexPulses = 0;
            _phase = Phase.Searching;
            _wait = CrcBytes * ByteCycles;
            return;
        }

        Finish();
    }

    // Read track streams the whole track from the index hole; write track takes it from the program.
    private void AwaitIndex()
    {
        if (!Ready || _indexPulses == 0) { return; }
        _position = 0;
        if ((_command & 0xF0) == 0xE0)
        {
            _buffer = RawTrack();
            _sector = null;
            _wait = ByteCycles;
            _phase = Phase.Reading;
            return;
        }

        _trackBytes = [];
        _indexPulses = 0;
        _request = true;
        _wait = ByteCycles;
        _phase = Phase.WritingTrack;
    }

    private void WriteTrackByte()
    {
        if (_trackBytes is null) { return; }
        if (_indexPulses > 0 && _selected >= 0 && Current is { } disk)
        {
            disk.Format(_cylinders[_selected], Side, ParseTrack(_trackBytes, _doubleDensity));
            _changed[_selected] = true;
            _trackBytes = null;
            Finish();
            return;
        }

        if (_request) { _status |= TrackZeroOrLost; }
        _trackBytes.Add(_request ? (byte)0 : Data);
        _request = true;
        _wait = ByteCycles;
    }

    private void Finish()
    {
        _status &= unchecked((byte)~Busy);
        _request = false;
        _phase = Phase.Idle;
        _wait = 0;
        InterruptRequest = true;
    }
}
