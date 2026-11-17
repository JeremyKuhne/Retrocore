// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Media.Floppy;

namespace Retrocore.Media.Trs80;

/// <summary>
///  JV1, Jeff Vavasour's first image format: single-sided, single-density tracks of ten 256-byte sectors, 0-9,
///  with no header.
/// </summary>
/// <remarks>
///  <para>
///   As emulators read it, track 17's sectors carry the <c>$FA</c> data address mark TRSDOS gives its
///   directory; every other sector carries <c>$FB</c>.
///  </para>
///  <para>
///   A disk saves to JV1 without loss when it is one side of single-density tracks of sectors 0-9 of 256 bytes, with
///   those marks, no CRC errors, and IDs naming the track they are on; anything else is listed as lost. The order
///   of a track's sectors is not kept: JV1 reads back in the order 0-9, which a program sees only in its timing.
///  </para>
/// </remarks>
public static class Jv1Format
{
    /// <summary>
    ///  Sectors per track.
    /// </summary>
    public const int SectorsPerTrack = 10;

    /// <summary>
    ///  Bytes per sector.
    /// </summary>
    public const int SectorSize = 256;

    /// <summary>
    ///  The directory track, whose sectors carry the <c>$FA</c> mark.
    /// </summary>
    public const int DirectoryTrack = 17;

    private const int TrackSize = SectorsPerTrack * SectorSize;

    /// <summary>
    ///  Reads an image.
    /// </summary>
    /// <param name="image">The file's bytes.</param>
    /// <returns>The disk.</returns>
    /// <exception cref="InvalidDataException">The length is not whole sectors.</exception>
    public static FloppyDisk Read(ReadOnlySpan<byte> image)
    {
        if (image.Length == 0 || image.Length % SectorSize != 0)
        {
            throw new InvalidDataException("A JV1 image is a whole number of 256-byte sectors.");
        }

        FloppyDisk disk = new();
        for (int offset = 0; offset < image.Length; offset += SectorSize)
        {
            int track = offset / TrackSize;
            int sector = (offset % TrackSize) / SectorSize;
            disk.Add(track, 0, new((byte)track, 0, (byte)sector, image.Slice(offset, SectorSize), doubleDensity: false, Mark(track)));
        }

        return disk;
    }

    /// <summary>
    ///  Writes a disk as JV1, listing what JV1 cannot hold of it.
    /// </summary>
    /// <param name="disk">The disk.</param>
    /// <returns>The image and its losses.</returns>
    public static EncodedImage Encode(FloppyDisk disk)
    {
        ArgumentNullException.ThrowIfNull(disk);
        FloppyLosses losses = new();
        int cylinders = Math.Max(1, disk.Cylinders);
        byte[] image = new byte[cylinders * TrackSize];
        int length = image.Length;
        for (int cylinder = 0; cylinder < cylinders; cylinder++)
        {
            if (disk.Track(cylinder, 1).Count != 0) { losses.Add("Side 1's sectors", cylinder); }
            bool[] seen = new bool[SectorsPerTrack];
            foreach (FloppySector sector in disk.Track(cylinder, 0))
            {
                if (sector.Sector >= SectorsPerTrack || seen[sector.Sector])
                {
                    losses.Add("Sectors other than 0-9, or repeated", cylinder);
                    continue;
                }

                if (sector.Data.Length != SectorSize)
                {
                    losses.Add("Sectors of other than 256 bytes", cylinder);
                    continue;
                }

                seen[sector.Sector] = true;
                if (sector.DoubleDensity) { losses.Add("Double-density sectors", cylinder); }
                if (sector.DataAddressMark != Mark(cylinder))
                {
                    losses.Add("Data address marks other than $FA on track 17 and $FB elsewhere", cylinder);
                }

                if (sector.CrcError) { losses.Add("Sectors with CRC errors", cylinder); }
                if (sector.Track != cylinder || sector.Side != 0)
                {
                    losses.Add("Sector IDs naming another track or side", cylinder);
                }

                sector.Data.CopyTo(image.AsSpan((cylinder * TrackSize) + (sector.Sector * SectorSize)));
            }

            // The last track ends after its last sector, as a JV1 image may.
            int end = SectorsPerTrack;
            if (cylinder == cylinders - 1)
            {
                end = Math.Max(1, Array.LastIndexOf(seen, value: true) + 1);
                length = (cylinder * TrackSize) + (end * SectorSize);
            }

            if (seen.AsSpan(0, end).Contains(value: false))
            {
                losses.Add("Sectors 0-9 missing, which JV1 writes as zeros", cylinder);
            }
        }

        return new(image[..length], losses.ToList());
    }

    /// <summary>
    ///  Writes a disk as JV1, which must hold all of it.
    /// </summary>
    /// <param name="disk">The disk.</param>
    /// <returns>The file's bytes.</returns>
    /// <exception cref="InvalidOperationException">JV1 cannot hold all of the disk.</exception>
    public static byte[] Write(FloppyDisk disk)
    {
        EncodedImage encoded = Encode(disk);
        return encoded.IsLossless
            ? encoded.Bytes
            : throw new InvalidOperationException($"JV1 cannot hold all of the disk: {string.Join(" ", encoded.Losses)}");
    }

    private static byte Mark(int track) => track == DirectoryTrack ? (byte)0xFA : (byte)0xFB;
}
