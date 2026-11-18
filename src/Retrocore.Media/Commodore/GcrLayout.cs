// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Media.Commodore;

/// <summary>
///  Commodore's group code recording and its 35-track disk layout: each 4-bit nibble written as 5 bits that never
///  hold more than two zeros in a row, sectors per track by zone, and the blocks a sector is written as.
/// </summary>
/// <remarks>
///  <para>
///   A sector is a header block and a data block, each after a sync of at least ten 1s. The header is <c>$08</c>, a
///   checksum (the XOR of the next four), the sector, the track, and the disk's two ID bytes, second first. The data
///   block is <c>$07</c>, 256 bytes, and their XOR. Nine GCR zero bytes follow the header, and between sectors a gap
///   of zero bytes by zone, the rest of the track filled with zero bytes. The 4040's DOS 2 writes syncs of 40 ones
///   and gaps of 11, 19, 15 and 12 bytes from zone 3 down; the 2040's DOS 1, with a sector more in zone 2, syncs of
///   20 and gaps of 11, 8, 15 and 12, as MAME's <c>c4040</c> and <c>c3040</c> formats lay them out.
///  </para>
/// </remarks>
public static class GcrLayout
{
    /// <summary>
    ///  The tracks of a 35-track disk.
    /// </summary>
    public const int Tracks = 35;

    /// <summary>
    ///  The sectors of a 35-track DOS 2 disk.
    /// </summary>
    public const int Sectors = 683;

    /// <summary>
    ///  The sectors of a 35-track DOS 1 disk.
    /// </summary>
    public const int Dos1Sectors = 690;

    /// <summary>
    ///  A sector's bytes.
    /// </summary>
    public const int SectorSize = 256;

    private const int HeaderGap = 9;

    private static readonly byte[] s_encode =
    [
        0x0A, 0x0B, 0x12, 0x13, 0x0E, 0x0F, 0x16, 0x17, 0x09, 0x19, 0x1A, 0x1B, 0x0D, 0x1D, 0x1E, 0x15
    ];

    private static readonly int[] s_gaps = [12, 15, 19, 11];
    private static readonly int[] s_dos1Gaps = [12, 15, 8, 11];

    /// <summary>
    ///  Gets a DOS's sectors on a 35-track disk.
    /// </summary>
    /// <param name="dos">The DOS.</param>
    /// <returns>683 for DOS 2, 690 for DOS 1.</returns>
    public static int SectorCount(CommodoreDos dos) => dos == CommodoreDos.Dos1 ? Dos1Sectors : Sectors;

    /// <summary>
    ///  Gets a track's speed zone.
    /// </summary>
    /// <param name="track">The track, 1-35.</param>
    /// <returns>3 for tracks 1-17, 2 for 18-24, 1 for 25-30, 0 for 31-35.</returns>
    public static int Zone(int track) => track switch { <= 17 => 3, <= 24 => 2, <= 30 => 1, _ => 0 };

    /// <summary>
    ///  Gets a track's sectors.
    /// </summary>
    /// <param name="track">The track, 1-35.</param>
    /// <param name="dos">The DOS whose layout the disk has.</param>
    /// <returns>21, 19 (20 for DOS 1), 18 or 17.</returns>
    public static int SectorsOn(int track, CommodoreDos dos = CommodoreDos.Dos2) => Zone(track) switch
    {
        3 => 21,
        2 => dos == CommodoreDos.Dos1 ? 20 : 19,
        1 => 18,
        _ => 17
    };

    /// <summary>
    ///  Gets the cells a track of a zone holds: what a turn of 200 ms holds at the zone's cell, 16 MHz / (16 − zone)
    ///  / 4, down to whole bytes, as a G64 file keeps a track: 7,692, 7,142, 6,666 and 6,250 bytes from zone 3 down.
    /// </summary>
    /// <param name="zone">The zone, 0-3.</param>
    /// <returns>The cells, a multiple of 8.</returns>
    public static int TrackBits(int zone) => 200_000_000 / (4000 - (250 * zone)) & ~7;

    /// <summary>
    ///  Gets the first sector's index in an image of a disk's sectors in order.
    /// </summary>
    /// <param name="track">The track, 1-35.</param>
    /// <param name="dos">The DOS whose layout the disk has.</param>
    /// <returns>The index.</returns>
    public static int FirstSector(int track, CommodoreDos dos = CommodoreDos.Dos2)
    {
        int index = 0;
        for (int earlier = 1; earlier < track; earlier++) { index += SectorsOn(earlier, dos); }
        return index;
    }

    /// <summary>
    ///  Writes a track's sectors as the drive formats them.
    /// </summary>
    /// <param name="track">The track, 1-35.</param>
    /// <param name="sectors">Its sectors' bytes, 256 each.</param>
    /// <param name="id">The disk's two ID bytes, as the directory's header holds them.</param>
    /// <param name="dos">The DOS whose layout to write: the 4040's DOS 2 or the 2040's DOS 1.</param>
    /// <returns>The cells, packed eight to a byte, and how many.</returns>
    public static (byte[] Bits, int Count) WriteTrack(
        int track,
        ReadOnlySpan<byte> sectors,
        (byte First, byte Second) id,
        CommodoreDos dos = CommodoreDos.Dos2)
    {
        int zone = Zone(track);
        int total = TrackBits(zone);
        int sync = dos == CommodoreDos.Dos1 ? 20 : 40;
        int gap = (dos == CommodoreDos.Dos1 ? s_dos1Gaps : s_gaps)[zone];
        GcrBitWriter writer = new(total);
        for (int sector = 0; sector < SectorsOn(track, dos); sector++)
        {
            writer.Ones(sync);
            byte checksum = (byte)(sector ^ track ^ id.Second ^ id.First);
            writer.Bytes([0x08, checksum, (byte)sector, (byte)track, id.Second, id.First]);
            writer.Zeros(HeaderGap);
            writer.Ones(sync);
            writer.Byte(0x07);
            ReadOnlySpan<byte> data = sectors.Slice(sector * SectorSize, SectorSize);
            byte sum = 0;
            foreach (byte value in data)
            {
                writer.Byte(value);
                sum ^= value;
            }

            writer.Byte(sum);
            writer.Zeros(gap);
        }

        while (writer.Count + 10 <= total) { writer.Byte(0); }
        while (writer.Count < total) { writer.Bit((writer.Count & 1) == 0); }
        return (writer.Buffer, total);
    }

    /// <summary>
    ///  Reads a track's sectors from its cells, as the drive would: each header found after a sync, then the data
    ///  block after the next sync.
    /// </summary>
    /// <param name="bits">The cells, packed eight to a byte.</param>
    /// <param name="count">How many.</param>
    /// <param name="track">The track the headers must name.</param>
    /// <param name="sectors">Receives each sector found, 256 bytes each.</param>
    /// <param name="dos">The DOS whose layout the disk has, which says how many sectors the track holds.</param>
    /// <returns>Which sectors were found with good checksums.</returns>
    public static bool[] ReadTrack(
        ReadOnlySpan<byte> bits,
        int count,
        int track,
        Span<byte> sectors,
        CommodoreDos dos = CommodoreDos.Dos2) => ReadTrack(bits, count, track, sectors, dos, out _, out _, out _);

    /// <summary>
    ///  Reads a track's sectors from its cells; says which have a header but no data block after it, as DOS 1 leaves
    ///  each sector it formats until it writes one, and which good sectors the layout has no place for.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   A block with a code no nibble encodes is bad, as the drive's byte decoding error says, whatever its checksum.
    ///   Each data block is decoded on its own and kept only when good, so a bad copy of a sector after a good one
    ///   leaves the good one; a second good copy that differs is reported. GCR never holds ten 1s in a row, so a sync
    ///   inside a data block means the block was cut short: it is bad, and reading goes on from that sync.
    ///  </para>
    /// </remarks>
    /// <param name="bits">The cells, packed eight to a byte.</param>
    /// <param name="count">How many.</param>
    /// <param name="track">The track the headers must name.</param>
    /// <param name="sectors">Receives each sector found, 256 bytes each.</param>
    /// <param name="dos">The DOS whose layout the disk has.</param>
    /// <param name="unwritten">Which sectors have a good header and no data block.</param>
    /// <param name="beyond">
    ///  The good sectors numbered past the layout's last, such as a DOS 1 disk's 20th on a DOS 2 layout.
    /// </param>
    /// <param name="conflicting">The sectors with two good copies that differ, of which the first is kept.</param>
    /// <returns>Which sectors were found with good checksums.</returns>
    internal static bool[] ReadTrack(
        ReadOnlySpan<byte> bits,
        int count,
        int track,
        Span<byte> sectors,
        CommodoreDos dos,
        out bool[] unwritten,
        out IReadOnlyList<int> beyond,
        out IReadOnlyList<int> conflicting)
    {
        SortedSet<int> differ = [];
        conflicting = [];
        bool[] found = new bool[SectorsOn(track, dos)];
        bool[] headers = new bool[found.Length];
        bool[] blocks = new bool[found.Length];
        SortedSet<int> extra = [];
        unwritten = new bool[found.Length];
        beyond = [];
        if (count == 0) { return found; }

        // Twice round, so a block that crosses the track's start is read whole.
        int limit = count * 2;
        int position = 0;
        int sector = -1;
        Span<byte> header = stackalloc byte[5];
        Span<byte> data = stackalloc byte[SectorSize];
        bool atSync = false;
        while (position < limit)
        {
            // A block cut short by a sync leaves the position just past that sync.
            int start = atSync ? position : NextSync(bits, count, ref position, limit);
            atSync = false;
            if (start < 0) { break; }
            bool valid = true;
            byte mark = ReadByte(bits, count, ref position, ref valid);
            if (valid && mark == 0x08)
            {
                for (int i = 0; i < header.Length; i++) { header[i] = ReadByte(bits, count, ref position, ref valid); }
                bool good = valid && (header[0] ^ header[1] ^ header[2] ^ header[3] ^ header[4]) == 0 && header[2] == track;
                sector = good ? header[1] : -1;
                if (sector >= 0 && sector < found.Length) { headers[sector] = true; }
            }
            else if (valid && mark == 0x07 && sector >= 0)
            {
                if (sector < found.Length) { blocks[sector] = true; }
                int probe = position;
                if (NextSync(bits, count, ref probe, position + ((SectorSize + 1) * 10)) >= 0)
                {
                    position = probe;
                    atSync = true;
                    sector = -1;
                    continue;
                }

                byte sum = 0;
                for (int i = 0; i < SectorSize; i++)
                {
                    data[i] = ReadByte(bits, count, ref position, ref valid);
                    sum ^= data[i];
                }

                bool good = ReadByte(bits, count, ref position, ref valid) == sum && valid;
                if (good && sector >= found.Length)
                {
                    extra.Add(sector);
                }
                else if (good && !found[sector])
                {
                    data.CopyTo(sectors.Slice(sector * SectorSize, SectorSize));
                    found[sector] = true;
                }
                else if (good && !data.SequenceEqual(sectors.Slice(sector * SectorSize, SectorSize)))
                {
                    differ.Add(sector);
                }

                sector = -1;
            }
            else
            {
                // Past a header, anything but another header is its data block, damaged: the sector was written.
                if (sector >= 0 && sector < found.Length) { blocks[sector] = true; }
                sector = -1;
            }
        }

        for (int i = 0; i < found.Length; i++) { unwritten[i] = headers[i] && !blocks[i]; }
        beyond = [.. extra];
        conflicting = [.. differ];
        return found;
    }

    /// <summary>
    ///  Gets whether a track holds a sync, a run of at least ten 1s, as anything the drive wrote there has.
    /// </summary>
    /// <param name="bits">The cells, packed eight to a byte.</param>
    /// <param name="count">How many.</param>
    /// <returns>Whether it does.</returns>
    internal static bool HasSync(ReadOnlySpan<byte> bits, int count)
    {
        int position = 0;
        return count > 0 && NextSync(bits, count, ref position, count * 2) >= 0;
    }

    // Moves past the next run of at least ten 1s to the cell after it; returns -1 when there is none before the limit.
    private static int NextSync(ReadOnlySpan<byte> bits, int count, ref int position, int limit)
    {
        int ones = 0;
        while (position < limit)
        {
            bool one = Bit(bits, count, position);
            if (one)
            {
                ones++;
            }
            else if (ones >= 10)
            {
                return position;
            }
            else
            {
                ones = 0;
            }

            position++;
        }

        return -1;
    }

    // Reads ten cells as a byte: two nibbles of five. A code no nibble encodes reads as 0 and clears valid.
    private static byte ReadByte(ReadOnlySpan<byte> bits, int count, ref int position, ref bool valid)
    {
        int code = 0;
        for (int i = 0; i < 10; i++) { code = (code << 1) | (Bit(bits, count, position++) ? 1 : 0); }
        int high = Decode(code >> 5);
        int low = Decode(code & 0x1F);
        if (high < 0 || low < 0) { valid = false; }
        return (byte)((Math.Max(high, 0) << 4) | Math.Max(low, 0));
    }

    /// <summary>
    ///  Gets a byte's ten cells: its high nibble's five, then its low nibble's.
    /// </summary>
    /// <param name="value">The byte.</param>
    /// <returns>The cells, the first in bit 9.</returns>
    internal static int Encode(byte value) => (s_encode[value >> 4] << 5) | s_encode[value & 0x0F];

    // The nibble five cells encode, or -1 for a code none does.
    private static int Decode(int five) => Array.IndexOf(s_encode, (byte)five);

    private static bool Bit(ReadOnlySpan<byte> bits, int count, int position)
    {
        int at = position % count;
        return (bits[at >> 3] & (0x80 >> (at & 7))) != 0;
    }
}
