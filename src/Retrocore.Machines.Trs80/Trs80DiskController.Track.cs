// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Media.Trs80;

namespace Retrocore.Machines.Trs80;

public sealed partial class Trs80DiskController
{
    private const byte IdMark = 0xFE;

    // CRC-CCITT of an ID field: double density includes the three A1 sync bytes before the mark.
    private static ushort IdCrc(FloppySector sector)
    {
        ushort crc = 0xFFFF;
        if (sector.DoubleDensity) { crc = Crc(crc, [0xA1, 0xA1, 0xA1]); }
        return Crc(crc, [IdMark, sector.Track, sector.Side, sector.Sector, sector.SizeCode]);
    }

    private static ushort Crc(ushort crc, ReadOnlySpan<byte> bytes)
    {
        foreach (byte value in bytes)
        {
            crc ^= (ushort)(value << 8);
            for (int bit = 0; bit < 8; bit++)
            {
                crc = (crc & 0x8000) != 0 ? (ushort)((crc << 1) ^ 0x1021) : (ushort)(crc << 1);
            }
        }

        return crc;
    }

    // The track as read track returns it: gaps, then each sector's ID field and data field.
    private byte[] RawTrack()
    {
        List<byte> track = [];
        byte gap = _doubleDensity ? (byte)0x4E : (byte)0xFF;
        if (_selected >= 0 && Current is { } disk)
        {
            foreach (FloppySector sector in disk.Track(_cylinders[_selected], Side))
            {
                if (sector.DoubleDensity != _doubleDensity) { continue; }
                track.AddRange(Enumerable.Repeat(gap, 16));
                track.AddRange(Enumerable.Repeat((byte)0, 6));
                ushort crc = IdCrc(sector);
                track.AddRange([IdMark, sector.Track, sector.Side, sector.Sector, sector.SizeCode, (byte)(crc >> 8), (byte)crc]);
                track.AddRange(Enumerable.Repeat(gap, 11));
                track.AddRange(Enumerable.Repeat((byte)0, 6));
                track.Add(sector.DataAddressMark);
                track.AddRange(sector.Data);
                track.AddRange([0, 0]);
            }
        }

        int length = _rotationCycles / ByteCycles;
        while (track.Count < length) { track.Add(gap); }
        return [.. track];
    }

    // Write track's stream: $FE starts an ID field, $F8-$FB a data field, $F7 writes a CRC, $F5 an A1 sync.
    private static List<FloppySector> ParseTrack(List<byte> bytes, bool doubleDensity)
    {
        List<FloppySector> sectors = [];
        int index = 0;
        while (index < bytes.Count)
        {
            if (bytes[index++] != IdMark || index + 4 > bytes.Count) { continue; }
            byte track = bytes[index];
            byte side = bytes[index + 1];
            byte number = bytes[index + 2];
            int size = 128 << (bytes[index + 3] & 3);
            index += 4;

            // The data field starts at the next data mark.
            while (index < bytes.Count && bytes[index] is not (>= 0xF8 and <= 0xFB)) { index++; }
            if (index + 1 + size > bytes.Count) { break; }
            byte mark = bytes[index++];
            byte[] data = [.. bytes.GetRange(index, size)];
            index += size;
            sectors.Add(new(track, side, number, data, doubleDensity, mark));
        }

        return sectors;
    }
}
