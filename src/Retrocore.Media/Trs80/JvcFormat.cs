// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Media.Trs80;

/// <summary>
///  Reads and writes JVC images, the Color Computer's <c>.dsk</c> files: each track's sectors in order, side 0
///  then side 1, after an optional header.
/// </summary>
/// <remarks>
///  <para>
///   The header is the image's length modulo 256 bytes long. Its bytes, each defaulting when the header is shorter,
///   are the sectors per track (18), the sides (1), the sector size code (1, 256 bytes), the first sector's number
///   (1) and an attribute byte that marks a sector's data address mark (0). The sectors are double density, as
///   Disk Extended Color BASIC formats them: 35 tracks of 18 256-byte sectors on one side is 161,280 bytes.
///  </para>
/// </remarks>
public static class JvcFormat
{
    /// <summary>
    ///  Disk BASIC's sectors per track.
    /// </summary>
    public const int SectorsPerTrack = 18;

    /// <summary>
    ///  Disk BASIC's sector size.
    /// </summary>
    public const int SectorSize = 256;

    /// <summary>
    ///  Disk BASIC's tracks.
    /// </summary>
    public const int Tracks = 35;

    /// <summary>
    ///  Reads an image.
    /// </summary>
    /// <param name="image">The file's bytes.</param>
    /// <returns>The disk.</returns>
    /// <exception cref="InvalidDataException">
    ///  The image's header is unsupported or its size is not whole tracks.
    /// </exception>
    public static FloppyDisk Read(ReadOnlySpan<byte> image)
    {
        int headerLength = image.Length % 256;
        ReadOnlySpan<byte> header = image[..headerLength];
        int sectors = headerLength > 0 ? header[0] : SectorsPerTrack;
        int sides = headerLength > 1 ? header[1] : 1;
        int sizeCode = headerLength > 2 ? header[2] : 1;
        int first = headerLength > 3 ? header[3] : 1;
        bool attributes = headerLength > 4 && header[4] != 0;
        if (sectors == 0 || sides is not (1 or 2) || sizeCode > 3 || attributes)
        {
            throw new InvalidDataException("The JVC header describes an unsupported geometry.");
        }

        int size = 128 << sizeCode;
        int trackLength = sectors * size * sides;
        ReadOnlySpan<byte> body = image[headerLength..];
        if (body.Length == 0 || body.Length % trackLength != 0)
        {
            throw new InvalidDataException("A JVC image is a whole number of tracks.");
        }

        FloppyDisk disk = new();
        int offset = 0;
        for (int track = 0; offset < body.Length; track++)
        {
            for (int side = 0; side < sides; side++)
            {
                for (int sector = 0; sector < sectors; sector++)
                {
                    byte[] data = body.Slice(offset, size).ToArray();
                    disk.Add(track, side, new((byte)track, (byte)side, (byte)(sector + first), data, doubleDensity: true));
                    offset += size;
                }
            }
        }

        return disk;
    }

    /// <summary>
    ///  Writes a disk of Disk BASIC's geometry as a headerless image, or with a header for two sides.
    /// </summary>
    /// <param name="disk">The disk.</param>
    /// <returns>The image.</returns>
    /// <exception cref="InvalidOperationException">
    ///  A track does not hold exactly sectors 1-18 of 256 bytes, so the image could not keep all of it.
    /// </exception>
    public static byte[] Write(FloppyDisk disk)
    {
        ArgumentNullException.ThrowIfNull(disk);
        int sides = disk.Sides;
        int trackLength = SectorsPerTrack * SectorSize;
        byte[] header = sides == 1 ? [] : [SectorsPerTrack, 2];
        byte[] image = new byte[header.Length + (disk.Cylinders * sides * trackLength)];
        header.CopyTo(image, 0);
        int offset = header.Length;
        for (int cylinder = 0; cylinder < disk.Cylinders; cylinder++)
        {
            for (int side = 0; side < sides; side++)
            {
                IReadOnlyList<FloppySector> sectors = disk.Track(cylinder, side);
                if (sectors.Count != SectorsPerTrack)
                {
                    throw new InvalidOperationException(
                        $"Track {cylinder} side {side} has {sectors.Count} sectors, not a JVC track's {SectorsPerTrack}.");
                }

                for (int number = 1; number <= SectorsPerTrack; number++)
                {
                    FloppySector? sector = sectors.FirstOrDefault(candidate => candidate.Sector == number);
                    if (sector is null || sector.Data.Length != SectorSize)
                    {
                        throw new InvalidOperationException($"Track {cylinder} side {side} is not a JVC track.");
                    }

                    sector.Data.CopyTo(image, offset);
                    offset += SectorSize;
                }
            }
        }

        return image;
    }

    /// <summary>
    ///  Creates a disk formatted as Disk BASIC's DSKINI leaves it: every byte <c>$FF</c>, which on track 17 is a
    ///  granule table with all 68 granules free and an empty directory.
    /// </summary>
    /// <returns>The disk.</returns>
    public static FloppyDisk Formatted()
    {
        byte[] image = new byte[Tracks * SectorsPerTrack * SectorSize];
        image.AsSpan().Fill(0xFF);
        return Read(image);
    }
}
