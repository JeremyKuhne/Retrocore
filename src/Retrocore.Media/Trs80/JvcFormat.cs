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
///  <para>
///   A disk saves back with the header it was read with, its sides grown to the disk's, so a geometry other than
///   Disk BASIC's stays. A disk from elsewhere takes its geometry from its first track, with the shortest header
///   that gives it. Every track must then be sectors of that size, numbered from the first sector on, in double
///   density with the <c>$FB</c> mark, no CRC errors and IDs naming where they are; anything else is listed as
///   lost. A track's sector order is not kept, which a program sees only in its timing.
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

    // The header's fields and the values a shorter header leaves them.
    private static readonly byte[] s_defaults = [SectorsPerTrack, 1, 1, 1];

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
                    ReadOnlySpan<byte> data = body.Slice(offset, size);
                    disk.Add(track, side, new((byte)track, (byte)side, (byte)(sector + first), data, doubleDensity: true));
                    offset += size;
                }
            }
        }

        return disk;
    }

    /// <summary>
    ///  Gets an image's header: its first bytes, as many as its length is past whole 256-byte blocks.
    /// </summary>
    /// <param name="image">The file's bytes.</param>
    /// <returns>The header, empty for a headerless image.</returns>
    public static ReadOnlySpan<byte> Header(ReadOnlySpan<byte> image) => image[..(image.Length % 256)];

    /// <summary>
    ///  Writes a disk as JVC in the geometry of its first track, listing what that geometry cannot hold.
    /// </summary>
    /// <param name="disk">The disk.</param>
    /// <returns>The image and its losses.</returns>
    /// <exception cref="InvalidOperationException">The sectors do not fill whole 256-byte blocks.</exception>
    public static EncodedImage Encode(FloppyDisk disk)
    {
        ArgumentNullException.ThrowIfNull(disk);
        IReadOnlyList<FloppySector> first = disk.Track(0, 0);
        byte[] fields =
        [
            first.Count is > 0 and < 256 ? (byte)first.Count : (byte)SectorsPerTrack,
            1,
            first.Count > 0 ? first[0].SizeCode : (byte)1,
            first.Count > 0 ? first.Min(sector => sector.Sector) : (byte)1,
        ];

        // The shortest header that gives the geometry: none for Disk BASIC's.
        int length = fields.Length;
        while (length > 0 && fields[length - 1] == s_defaults[length - 1]) { length--; }
        return Encode(disk, fields.AsSpan(0, length));
    }

    /// <summary>
    ///  Writes a disk as JVC with the header of the image it was read from, its sides grown to the disk's, listing
    ///  what that geometry cannot hold.
    /// </summary>
    /// <param name="disk">The disk.</param>
    /// <param name="header">The header, as <see cref="Header"/> gives it; empty for none.</param>
    /// <returns>The image and its losses.</returns>
    /// <exception cref="ArgumentException">The header is not one <see cref="Read"/> takes.</exception>
    /// <exception cref="InvalidOperationException">
    ///  The sectors do not fill whole 256-byte blocks, which an odd number of 128-byte sectors leaves the image's length
    ///  unable to give its header's.
    /// </exception>
    public static EncodedImage Encode(FloppyDisk disk, ReadOnlySpan<byte> header)
    {
        ArgumentNullException.ThrowIfNull(disk);
        byte[] fields = [.. s_defaults];
        header[..Math.Min(header.Length, fields.Length)].CopyTo(fields);
        int sectors = fields[0];
        int size = 128 << fields[2];
        int firstSector = fields[3];
        if (sectors == 0 || fields[1] is not (1 or 2) || fields[2] > 3 || (header.Length > 4 && header[4] != 0))
        {
            throw new ArgumentException("The JVC header describes an unsupported geometry.", nameof(header));
        }

        // A second side the disk gained is written, the header saying so.
        int sides = Math.Max(fields[1], disk.Sides);
        byte[] written = sides == fields[1] || header.Length >= 2 ? header.ToArray() : fields[..2];
        if (sides != fields[1]) { written[1] = (byte)sides; }

        // The header's length is the image's past whole 256-byte blocks, so the sectors must fill whole blocks.
        int cylinders = Math.Max(1, disk.Cylinders);
        int body = cylinders * sides * sectors * size;
        if (body % 256 != 0)
        {
            throw new InvalidOperationException(
                $"JVC cannot hold {cylinders * sides * sectors} sectors of {size} bytes, which do not fill whole "
                    + "256-byte blocks; save it as DMK.");
        }

        FloppyLosses losses = new();
        byte[] image = new byte[written.Length + body];
        written.CopyTo(image, 0);
        for (int cylinder = 0; cylinder < cylinders; cylinder++)
        {
            for (int side = 0; side < sides; side++)
            {
                int track = written.Length + (((cylinder * sides) + side) * sectors * size);
                Track(disk, cylinder, side, image.AsSpan(track, sectors * size), size, firstSector, losses);
            }
        }

        return new(image, losses.ToList());
    }

    /// <summary>
    ///  Writes a disk as JVC in the geometry of its first track, which must hold all of it.
    /// </summary>
    /// <param name="disk">The disk.</param>
    /// <returns>The image.</returns>
    /// <exception cref="InvalidOperationException">JVC cannot hold all of the disk.</exception>
    public static byte[] Write(FloppyDisk disk)
    {
        EncodedImage encoded = Encode(disk);
        return encoded.IsLossless
            ? encoded.Bytes
            : throw new InvalidOperationException($"JVC cannot hold all of the disk: {string.Join(" ", encoded.Losses)}");
    }

    // A track's sectors in order from the first sector's number, each where its number puts it.
    private static void Track(FloppyDisk disk, int cylinder, int side, Span<byte> track, int size, int firstSector, FloppyLosses losses)
    {
        int sectors = track.Length / size;
        bool[] seen = new bool[sectors];
        foreach (FloppySector sector in disk.Track(cylinder, side))
        {
            // Sector numbers wrap past 255, as Read numbers them.
            int index = (byte)(sector.Sector - firstSector);
            if (index >= sectors || seen[index])
            {
                losses.Add($"Sectors other than {Numbers(firstSector, sectors)}, or repeated", cylinder);
                continue;
            }

            if (sector.Data.Length != size)
            {
                losses.Add($"Sectors of other than {size} bytes", cylinder);
                continue;
            }

            seen[index] = true;
            if (!sector.DoubleDensity) { losses.Add("Single-density sectors", cylinder); }
            if (sector.DataAddressMark != 0xFB) { losses.Add("Data address marks other than $FB", cylinder); }
            if (sector.CrcError) { losses.Add("Sectors with CRC errors", cylinder); }
            if (sector.Track != cylinder || sector.Side != side)
            {
                losses.Add("Sector IDs naming another track or side", cylinder);
            }

            sector.Data.CopyTo(track[(index * size)..]);
        }

        if (seen.Contains(value: false))
        {
            losses.Add($"Sectors {Numbers(firstSector, sectors)} missing, which JVC writes as zeros", cylinder);
        }
    }

    // A track's sector numbers, from the first, wrapping past 255.
    private static string Numbers(int firstSector, int sectors) => $"{firstSector}-{(byte)(firstSector + sectors - 1)}";

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
