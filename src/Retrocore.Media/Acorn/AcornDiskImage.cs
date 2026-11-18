// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Media.Floppy;

namespace Retrocore.Media.Acorn;

/// <summary>
///  Reads and writes the Acorn DFS's disk images: <c>.ssd</c>, one side's tracks in order, and <c>.dsd</c>, each
///  track's two sides in turn. A track is 10 sectors of 256 bytes in single density (FM), numbered 0-9, with the
///  track number in each ID and side 0 in its head field, as the DFS formats both sides.
/// </summary>
/// <remarks>
///  <para>
///   An image may stop short of its last tracks, as tools trim unused ones; it reads as 40 or 80 tracks, whichever
///   holds both the image and the size the catalogue gives (sector 1's bytes 6 and 7: the sector count). Missing
///   sectors read as zeros.
///  </para>
/// </remarks>
public static class AcornDiskImage
{
    /// <summary>
    ///  The DFS's sectors per track.
    /// </summary>
    public const int SectorsPerTrack = 10;

    /// <summary>
    ///  The DFS's sector size.
    /// </summary>
    public const int SectorSize = 256;

    /// <summary>
    ///  A track's bytes in an image.
    /// </summary>
    public const int TrackSize = SectorsPerTrack * SectorSize;

    /// <summary>
    ///  Gets whether an extension names a double-sided image.
    /// </summary>
    /// <param name="extension">The extension, with or without its dot.</param>
    /// <returns>Whether it is <c>.dsd</c>.</returns>
    public static bool IsDoubleSided(string extension) =>
        extension.TrimStart('.').Equals("dsd", StringComparison.OrdinalIgnoreCase);

    /// <summary>
    ///  Reads an image.
    /// </summary>
    /// <param name="image">The image.</param>
    /// <param name="doubleSided">Whether it is a <c>.dsd</c> image.</param>
    /// <returns>The disk.</returns>
    /// <exception cref="InvalidDataException">The image is larger than 80 tracks.</exception>
    public static FloppyDisk Read(ReadOnlySpan<byte> image, bool doubleSided)
    {
        int sides = doubleSided ? 2 : 1;
        int imageTracks = (image.Length + (TrackSize * sides) - 1) / (TrackSize * sides);
        if (imageTracks > 80) { throw new InvalidDataException("A DFS image holds at most 80 tracks a side."); }

        // Each side's catalogue sector count, at its track 0: sector 1's byte 6 bits 0-1 and byte 7. The larger side
        // sets the geometry, so a trimmed image still gets every track either catalogue declares.
        int catalogueTracks = 0;
        for (int side = 0; side < sides; side++)
        {
            int catalogue = (side * TrackSize) + SectorSize;
            if (image.Length < catalogue + 8) { break; }
            int sectors = ((image[catalogue + 6] & 3) << 8) | image[catalogue + 7];
            catalogueTracks = Math.Max(catalogueTracks, sectors / SectorsPerTrack);
        }

        int tracks = Math.Max(imageTracks, catalogueTracks) > 40 ? 80 : 40;
        FloppyDisk disk = new();
        Span<byte> data = stackalloc byte[SectorSize];
        for (int track = 0; track < tracks; track++)
        {
            for (int side = 0; side < sides; side++)
            {
                int start = ((track * sides) + side) * TrackSize;
                for (int sector = 0; sector < SectorsPerTrack; sector++)
                {
                    data.Clear();
                    int offset = start + (sector * SectorSize);
                    if (offset < image.Length)
                    {
                        image.Slice(offset, Math.Min(SectorSize, image.Length - offset)).CopyTo(data);
                    }

                    disk.Add(track, side, new((byte)track, 0, (byte)sector, data, doubleDensity: false));
                }
            }
        }

        return disk;
    }

    /// <summary>
    ///  Creates a disk formatted as the DFS's *FORM leaves it, with every byte <c>$E5</c> but an empty catalogue.
    /// </summary>
    /// <param name="tracks">40 or 80.</param>
    /// <param name="doubleSided">Whether both sides are formatted.</param>
    /// <returns>The disk.</returns>
    public static FloppyDisk Blank(int tracks = 80, bool doubleSided = false)
    {
        if (tracks is not (40 or 80))
        {
            throw new ArgumentOutOfRangeException(nameof(tracks), "A DFS disk has 40 or 80 tracks.");
        }

        int sides = doubleSided ? 2 : 1;
        byte[] image = new byte[tracks * sides * TrackSize];
        image.AsSpan().Fill(0xE5);
        for (int side = 0; side < sides; side++)
        {
            // The catalogue: an empty title, no files, the disk's sectors.
            Span<byte> catalogue = image.AsSpan(side * TrackSize, 2 * SectorSize);
            catalogue.Clear();
            int sectors = tracks * SectorsPerTrack;
            catalogue[SectorSize + 6] = (byte)(sectors >> 8);
            catalogue[SectorSize + 7] = (byte)sectors;
        }

        return Read(image, doubleSided);
    }

    /// <summary>
    ///  Writes a disk as an image, listing what it cannot hold: sectors that are not one of the 10 of 256 bytes a
    ///  track has, deleted data marks, CRC errors, and sides or tracks past what the format holds.
    /// </summary>
    /// <param name="disk">The disk.</param>
    /// <param name="doubleSided">Whether to write a <c>.dsd</c> image.</param>
    /// <returns>The image.</returns>
    public static EncodedImage Encode(FloppyDisk disk, bool doubleSided)
    {
        ArgumentNullException.ThrowIfNull(disk);
        int sides = doubleSided ? 2 : 1;
        int tracks = Math.Min(Math.Max(disk.Cylinders, 40) > 40 ? 80 : 40, 80);
        byte[] image = new byte[tracks * sides * TrackSize];
        List<string> losses = [];
        if (!doubleSided && disk.Sides > 1) { losses.Add("Side 1, which an .ssd image does not hold."); }
        if (disk.Cylinders > 80) { losses.Add($"Tracks 80-{disk.Cylinders - 1}, past the 80 a DFS image holds."); }

        for (int track = 0; track < tracks; track++)
        {
            for (int side = 0; side < sides; side++)
            {
                int start = ((track * sides) + side) * TrackSize;
                bool[] found = new bool[SectorsPerTrack];
                foreach (FloppySector sector in disk.Track(track, side))
                {
                    if (sector.Sector >= SectorsPerTrack || sector.Data.Length != SectorSize || sector.DoubleDensity)
                    {
                        string size = $"{sector.Data.Length} bytes";
                        losses.Add($"Track {track} side {side}: sector {sector.Sector} of {size}, not a DFS one.");
                        continue;
                    }

                    if (found[sector.Sector])
                    {
                        losses.Add($"Track {track} side {side}: a second sector {sector.Sector}.");
                        continue;
                    }

                    found[sector.Sector] = true;
                    sector.Data.CopyTo(image.AsSpan(start + (sector.Sector * SectorSize)));
                    if (sector.DataAddressMark != 0xFB)
                    {
                        losses.Add($"Track {track} side {side}: sector {sector.Sector}'s deleted data mark.");
                    }

                    if (sector.CrcError)
                    {
                        losses.Add($"Track {track} side {side}: sector {sector.Sector}'s CRC error.");
                    }

                    if (sector.Track != track || sector.Side != 0)
                    {
                        losses.Add(
                            $"Track {track} side {side}: sector {sector.Sector}'s ID of track {sector.Track} head {sector.Side}.");
                    }
                }

                // A track within the disk's geometry that is wholly unformatted comes back as ten zeroed sectors.
                bool onDisk = track < disk.Cylinders && side < disk.Sides;
                if (found.Any(present => !present) && (onDisk || disk.Track(track, side).Count != 0))
                {
                    losses.Add($"Track {track} side {side}: missing sectors, written as zeros.");
                }
            }
        }

        return new(image, losses);
    }
}
