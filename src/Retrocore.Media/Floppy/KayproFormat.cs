// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Media.Floppy;

/// <summary>
///  Reads and writes raw Kaypro disk images (<c>.img</c>): each track's ten 512-byte sectors in order, with no header.
/// </summary>
/// <remarks>
///  <para>
///   A Kaypro II disk is single sided and double density, 40 tracks of ten 512-byte sectors numbered 0-9: 204,800
///   bytes. A Kaypro 4 disk has a second side whose sectors are numbered 10-19, each cylinder's side 0 then side 1:
///   409,600 bytes. Bytes past the last whole track, which some images carry, are ignored.
///  </para>
///  <para>
///   Every track must save as those ten sectors, in double density with the <c>$FB</c> mark, no CRC errors and IDs
///   naming where they are; anything else is listed as lost. Single-density disks need DMK.
///  </para>
/// </remarks>
public static class KayproFormat
{
    /// <summary>
    ///  The sectors on each track.
    /// </summary>
    public const int SectorsPerTrack = 10;

    /// <summary>
    ///  The sector size.
    /// </summary>
    public const int SectorSize = 512;

    /// <summary>
    ///  The tracks on each side.
    /// </summary>
    public const int Tracks = 40;

    /// <summary>
    ///  A Kaypro II disk's length.
    /// </summary>
    public const int SingleSidedLength = Tracks * SectorsPerTrack * SectorSize;

    /// <summary>
    ///  A Kaypro 4 disk's length.
    /// </summary>
    public const int DoubleSidedLength = 2 * SingleSidedLength;

    private const int TrackLength = SectorsPerTrack * SectorSize;

    /// <summary>
    ///  Gets whether an image's length is a Kaypro disk's, allowing less than a track more.
    /// </summary>
    /// <param name="length">The image's length.</param>
    /// <returns>Whether it is.</returns>
    public static bool IsImage(int length) =>
        length is >= SingleSidedLength and < SingleSidedLength + TrackLength
            or >= DoubleSidedLength and < DoubleSidedLength + TrackLength;

    /// <summary>
    ///  Reads an image.
    /// </summary>
    /// <param name="image">The image.</param>
    /// <returns>The disk.</returns>
    /// <exception cref="InvalidDataException">The image is not a Kaypro disk's length.</exception>
    public static FloppyDisk Read(ReadOnlySpan<byte> image)
    {
        if (!IsImage(image.Length))
        {
            throw new InvalidDataException(
                $"A Kaypro image is {SingleSidedLength:N0} bytes (single sided) or {DoubleSidedLength:N0} (double sided).");
        }

        int sides = image.Length >= DoubleSidedLength ? 2 : 1;
        FloppyDisk disk = new();
        for (int cylinder = 0; cylinder < Tracks; cylinder++)
        {
            for (int side = 0; side < sides; side++)
            {
                int track = ((cylinder * sides) + side) * TrackLength;
                for (int sector = 0; sector < SectorsPerTrack; sector++)
                {
                    ReadOnlySpan<byte> data = image.Slice(track + (sector * SectorSize), SectorSize);
                    disk.Add(cylinder, side, new((byte)cylinder, (byte)side, (byte)(FirstSector(side) + sector), data, doubleDensity: true));
                }
            }
        }

        return disk;
    }

    /// <summary>
    ///  Writes a disk as an image, listing what it cannot hold.
    /// </summary>
    /// <param name="disk">The disk.</param>
    /// <returns>The image and its losses.</returns>
    public static EncodedImage Encode(FloppyDisk disk)
    {
        ArgumentNullException.ThrowIfNull(disk);
        int sides = disk.Sides;
        FloppyLosses losses = new();
        if (disk.Cylinders > Tracks) { losses.Add($"Tracks past {Tracks - 1}", Tracks); }
        byte[] image = new byte[sides * Tracks * TrackLength];
        for (int cylinder = 0; cylinder < Tracks; cylinder++)
        {
            for (int side = 0; side < sides; side++)
            {
                Span<byte> track = image.AsSpan(((cylinder * sides) + side) * TrackLength, TrackLength);
                Track(disk, cylinder, side, track, losses);
            }
        }

        return new(image, losses.ToList());
    }

    // The number of a side's first sector.
    private static int FirstSector(int side) => side * SectorsPerTrack;

    private static void Track(FloppyDisk disk, int cylinder, int side, Span<byte> track, FloppyLosses losses)
    {
        bool[] seen = new bool[SectorsPerTrack];
        int first = FirstSector(side);
        foreach (FloppySector sector in disk.Track(cylinder, side))
        {
            int index = sector.Sector - first;
            if (index is < 0 or >= SectorsPerTrack || seen[index])
            {
                losses.Add($"Sectors other than {first}-{first + SectorsPerTrack - 1}, or repeated", cylinder);
                continue;
            }

            if (sector.Data.Length != SectorSize)
            {
                losses.Add($"Sectors of other than {SectorSize} bytes", cylinder);
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

            sector.Data.CopyTo(track[(index * SectorSize)..]);
        }

        if (seen.Contains(value: false))
        {
            losses.Add($"Sectors {first}-{first + SectorsPerTrack - 1} missing, which the image writes as zeros", cylinder);
        }
    }
}
