// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Media.Trs80;

/// <summary>
///  JV3, Jeff Vavasour's general format: blocks of a 2,901-entry sector table and a write-protect byte, each
///  followed by the data of its sectors.
/// </summary>
/// <remarks>
///  <para>
///   An entry is the track, the sector and flags: bit 7 double density, bits 6-5 the data address mark, bit 4
///   the side, bit 3 a CRC error, and bits 1-0 the size (0 is 256 bytes, 1 is 128, 2 is 1024, 3 is 512).
///   A track of <c>$FF</c> marks a free entry. A track's sectors pass the head in table order.
///  </para>
/// </remarks>
public static class Jv3Format
{
    /// <summary>
    ///  The entries in one table.
    /// </summary>
    public const int EntriesPerTable = 2901;

    private const int TableSize = (EntriesPerTable * 3) + 1;
    private const byte Free = 0xFF;
    private const byte DoubleDensityFlag = 0x80;
    private const byte MarkMask = 0x60;
    private const byte SideFlag = 0x10;
    private const byte ErrorFlag = 0x08;
    private const byte SizeMask = 0x03;

    // The size in the flags: the IBM size code with its low bit inverted.
    private static readonly int[] s_sizes = [256, 128, 1024, 512];

    /// <summary>
    ///  Gets whether an image looks like JV3: its first table lists at least one sector, and the sectors it lists fit
    ///  in the file. A JV1 image's first bytes, read as a table, list far more sectors than follow them.
    /// </summary>
    /// <param name="image">The file's bytes.</param>
    /// <returns>Whether it is JV3.</returns>
    public static bool IsJv3(ReadOnlySpan<byte> image)
    {
        if (image.Length < TableSize) { return false; }
        long data = 0;
        bool any = false;
        for (int entry = 0; entry < EntriesPerTable; entry++)
        {
            if (image[entry * 3] == Free) { continue; }
            any = true;
            data += s_sizes[image[(entry * 3) + 2] & SizeMask];
        }

        return any && TableSize + data <= image.Length;
    }

    /// <summary>
    ///  Reads an image.
    /// </summary>
    /// <param name="image">The file's bytes.</param>
    /// <returns>The disk.</returns>
    /// <exception cref="InvalidDataException">The table or data is truncated.</exception>
    public static FloppyDisk Read(ReadOnlySpan<byte> image)
    {
        if (image.Length < TableSize) { throw new InvalidDataException("A JV3 image starts with a sector table."); }
        FloppyDisk disk = new() { WriteProtected = image[TableSize - 1] == 0 };
        int offset = 0;
        while (offset + TableSize <= image.Length)
        {
            ReadOnlySpan<byte> table = image.Slice(offset, TableSize);
            offset += TableSize;
            bool any = false;
            for (int entry = 0; entry < EntriesPerTable; entry++)
            {
                byte track = table[entry * 3];
                if (track == Free) { continue; }
                any = true;
                byte flags = table[(entry * 3) + 2];
                int size = s_sizes[flags & SizeMask];
                if (offset + size > image.Length)
                {
                    throw new InvalidDataException("A JV3 sector's data is truncated.");
                }

                int side = (flags & SideFlag) != 0 ? 1 : 0;
                FloppySector sector = new(
                    track,
                    (byte)side,
                    table[(entry * 3) + 1],
                    image.Slice(offset, size).ToArray(),
                    (flags & DoubleDensityFlag) != 0,
                    Mark(flags))
                {
                    CrcError = (flags & ErrorFlag) != 0
                };

                disk.Add(track, side, sector);
                offset += size;
            }

            // A table with no used entries ends the image; a full one may be followed by another.
            if (!any) { break; }
        }

        return disk;
    }

    /// <summary>
    ///  Writes a disk as JV3.
    /// </summary>
    /// <param name="disk">The disk.</param>
    /// <returns>The file's bytes.</returns>
    public static byte[] Write(FloppyDisk disk)
    {
        ArgumentNullException.ThrowIfNull(disk);
        List<(int Cylinder, FloppySector Sector)> sectors = [];
        foreach ((int cylinder, _, IReadOnlyList<FloppySector> track) in disk.Tracks())
        {
            foreach (FloppySector sector in track) { sectors.Add((cylinder, sector)); }
        }

        using MemoryStream output = new();
        int written = 0;
        do
        {
            int count = Math.Min(EntriesPerTable, sectors.Count - written);
            byte[] table = new byte[TableSize];
            Array.Fill(table, Free);
            for (int entry = 0; entry < count; entry++)
            {
                (int cylinder, FloppySector sector) = sectors[written + entry];
                table[entry * 3] = (byte)cylinder;
                table[(entry * 3) + 1] = sector.Sector;
                table[(entry * 3) + 2] = Flags(sector);
            }

            table[TableSize - 1] = disk.WriteProtected ? (byte)0 : (byte)0xFF;
            output.Write(table);
            for (int entry = 0; entry < count; entry++) { output.Write(sectors[written + entry].Sector.Data); }
            written += count;
        }
        while (written < sectors.Count);

        return output.ToArray();
    }

    // Single density marks are $FB, $FA, $F9, $F8; double density has only $FB and $F8.
    private static byte Mark(byte flags)
    {
        int mark = (flags & MarkMask) >> 5;
        return (flags & DoubleDensityFlag) == 0 ? (byte)(0xFB - mark) : mark == 0 ? (byte)0xFB : (byte)0xF8;
    }

    private static byte Flags(FloppySector sector)
    {
        int mark = sector.DoubleDensity ? (sector.DataAddressMark == 0xFB ? 0 : 1) : 0xFB - sector.DataAddressMark;
        int flags = (sector.DoubleDensity ? DoubleDensityFlag : 0)
            | (mark << 5)
            | (sector.Side != 0 ? SideFlag : 0)
            | (sector.CrcError ? ErrorFlag : 0)
            | Array.IndexOf(s_sizes, sector.Data.Length);

        return (byte)flags;
    }
}
