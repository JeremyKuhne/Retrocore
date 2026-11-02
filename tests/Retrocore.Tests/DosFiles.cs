// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Tests;

/// <summary>
///  Reads files from a DOS 3.3 disk image in DOS order, for tests that compare with what a disk holds.
/// </summary>
internal static class DosFiles
{
    private const int SectorSize = 256;

    /// <summary>
    ///  Gets the contents of each file of a type, in catalog order.
    /// </summary>
    /// <param name="disk">The image.</param>
    /// <param name="type">The file type, without the lock bit: 0 text, 1 Integer BASIC, 2 AppleSoft, 4 binary.</param>
    /// <returns>Each file's sectors, in track/sector list order.</returns>
    internal static IEnumerable<byte[]> Read(byte[] disk, int type) =>
        Catalog(disk).Where(entry => entry.Type == type).Select(entry => Contents(disk, entry.Track, entry.Sector));

    /// <summary>
    ///  Gets a file's contents by name.
    /// </summary>
    /// <param name="disk">The image.</param>
    /// <param name="name">The file's name.</param>
    /// <returns>The file's sectors, in track/sector list order, or null when there is no such file.</returns>
    internal static byte[]? Find(byte[] disk, string name) =>
        Catalog(disk).Where(entry => entry.Name == name).Select(entry => Contents(disk, entry.Track, entry.Sector)).FirstOrDefault();

    // The catalog's entries, from the VTOC on track 17: seven 35-byte entries a sector.
    private static List<(string Name, int Type, int Track, int Sector)> Catalog(byte[] disk)
    {
        List<(string, int, int, int)> entries = [];
        ReadOnlySpan<byte> vtoc = SectorOf(disk, 17, 0);
        (int track, int sector) = (vtoc[1], vtoc[2]);
        while (track != 0)
        {
            ReadOnlySpan<byte> catalog = SectorOf(disk, track, sector);
            for (int entry = 0; entry < 7; entry++)
            {
                ReadOnlySpan<byte> file = catalog.Slice(11 + (entry * 35), 35);
                if (file[0] is 0 or 0xFF) { continue; }

                string name = new([.. file[3..33].ToArray().Select(character => (char)(character & 0x7F))]);
                entries.Add((name.TrimEnd(), file[2] & 0x7F, file[0], file[1]));
            }

            (track, sector) = (catalog[1], catalog[2]);
        }

        return entries;
    }

    private static byte[] Contents(byte[] disk, int track, int sector)
    {
        List<byte> data = [];
        while (track != 0)
        {
            ReadOnlySpan<byte> list = SectorOf(disk, track, sector);
            for (int pair = 0; pair < 122; pair++)
            {
                int dataTrack = list[12 + (pair * 2)];
                int dataSector = list[13 + (pair * 2)];
                if (dataTrack == 0 && dataSector == 0) { break; }

                data.AddRange(SectorOf(disk, dataTrack, dataSector));
            }

            (track, sector) = (list[1], list[2]);
        }

        return [.. data];
    }

    private static ReadOnlySpan<byte> SectorOf(byte[] disk, int track, int sector) =>
        disk.AsSpan(((track * 16) + sector) * SectorSize, SectorSize);
}
