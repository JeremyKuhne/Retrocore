// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

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
            byte mark = track == DirectoryTrack ? (byte)0xFA : (byte)0xFB;
            byte[] data = image.Slice(offset, SectorSize).ToArray();
            disk.Add(track, 0, new((byte)track, 0, (byte)sector, data, doubleDensity: false, mark));
        }

        return disk;
    }

    /// <summary>
    ///  Writes a disk as JV1, which holds sectors 0-9 of side 0 in single density.
    /// </summary>
    /// <param name="disk">The disk.</param>
    /// <returns>The file's bytes.</returns>
    /// <exception cref="InvalidOperationException">A track is not ten single-density 256-byte sectors.</exception>
    public static byte[] Write(FloppyDisk disk)
    {
        ArgumentNullException.ThrowIfNull(disk);
        byte[] image = new byte[disk.Cylinders * TrackSize];
        for (int cylinder = 0; cylinder < disk.Cylinders; cylinder++)
        {
            IReadOnlyList<FloppySector> sectors = disk.Track(cylinder, 0);
            for (int index = 0; index < SectorsPerTrack; index++)
            {
                FloppySector? sector = sectors.FirstOrDefault(candidate => candidate.Sector == index);
                if (sector is null || sector.DoubleDensity || sector.Data.Length != SectorSize)
                {
                    throw new InvalidOperationException($"Track {cylinder} is not a JV1 track.");
                }

                sector.Data.CopyTo(image, (cylinder * TrackSize) + (index * SectorSize));
            }
        }

        return image;
    }
}
