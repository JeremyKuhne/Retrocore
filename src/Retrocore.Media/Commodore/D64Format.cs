// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Media.Commodore;

/// <summary>
///  Reads and writes D64 images: a 35-track DOS 2 disk's 683 sectors of 256 bytes in order, track 1 first, and
///  optionally a byte of error code for each sector after them.
/// </summary>
/// <remarks>
///  <para>
///   Reading lays each track out as the 4040 formats it (<see cref="GcrLayout"/>), with the disk ID from track 18
///   sector 0's bytes <c>$A2</c> and <c>$A3</c>, as the drive's own format writes it there. An error table whose
///   codes all say a sector is good (<c>$00</c> or <c>$01</c>) holds nothing more; one that marks a sector damaged is
///   refused, since the damage is not reproduced and the disk would read back repaired. Writing reads each sector back
///   from its track, as the drive would; a sector it cannot read is written as zeros and listed.
///  </para>
/// </remarks>
public static class D64Format
{
    /// <summary>
    ///  The size of an image without error codes.
    /// </summary>
    public const int Size = GcrLayout.Sectors * GcrLayout.SectorSize;

    /// <summary>
    ///  The size of an image with an error code for each sector.
    /// </summary>
    public const int SizeWithErrors = Size + GcrLayout.Sectors;

    // Track 18 sector 0's $A2, the 358th sector on both layouts, since tracks 1-17 hold 21 sectors on both.
    private const int IdOffset = 0x165A2;

    /// <summary>
    ///  Gets whether bytes are the size of a D64 image.
    /// </summary>
    /// <param name="image">The bytes.</param>
    /// <returns>Whether they are.</returns>
    public static bool IsD64(ReadOnlySpan<byte> image) => image.Length is Size or SizeWithErrors;

    /// <summary>
    ///  Reads an image.
    /// </summary>
    /// <param name="image">The file's bytes.</param>
    /// <returns>The disk.</returns>
    /// <exception cref="InvalidDataException">
    ///  The image is not a D64 image's size, or its error table marks a sector damaged.
    /// </exception>
    public static CommodoreDisk Read(ReadOnlySpan<byte> image)
    {
        if (!IsD64(image))
        {
            throw new InvalidDataException($"A D64 image is {Size} bytes, or {SizeWithErrors} with error codes.");
        }

        if (image.Length == SizeWithErrors)
        {
            ReadOnlySpan<byte> errors = image[Size..];
            int damaged = errors.IndexOfAnyExcept((byte)0x00, (byte)0x01);
            if (damaged >= 0)
            {
                int track = 1;
                while (track < GcrLayout.Tracks && GcrLayout.FirstSector(track + 1) <= damaged) { track++; }
                int count = 0;
                foreach (byte code in errors) { if (code > 0x01) { count++; } }
                throw new InvalidDataException(
                    $"The D64 image's error table marks {count} sector{(count == 1 ? "" : "s")} damaged, the first "
                        + $"track {track}, sector {damaged - GcrLayout.FirstSector(track)} (code ${errors[damaged]:X2}). "
                        + "Retrocore cannot reproduce the damage; a G64 image of the disk keeps it.");
            }
        }

        return ReadSectors(image, CommodoreDos.Dos2);
    }

    /// <summary>
    ///  Writes a disk's sectors as an image, without error codes.
    /// </summary>
    /// <param name="disk">The disk.</param>
    /// <returns>The image, and the sectors that could not be read, as "track 18, sector 0".</returns>
    public static (byte[] Image, IReadOnlyList<string> Unreadable) Write(CommodoreDisk disk) =>
        WriteSectors(disk, CommodoreDos.Dos2);

    /// <summary>
    ///  Lays out a disk from its sectors in order, as a DOS formats each track.
    /// </summary>
    /// <param name="image">The sectors, at least the layout's count of 256 bytes.</param>
    /// <param name="dos">The layout.</param>
    /// <returns>The disk.</returns>
    internal static CommodoreDisk ReadSectors(ReadOnlySpan<byte> image, CommodoreDos dos)
    {
        (byte, byte) id = (image[IdOffset], image[IdOffset + 1]);
        CommodoreDisk disk = new();
        for (int track = 1; track <= GcrLayout.Tracks; track++)
        {
            int first = GcrLayout.FirstSector(track, dos) * GcrLayout.SectorSize;
            int length = GcrLayout.SectorsOn(track, dos) * GcrLayout.SectorSize;
            (byte[] bits, int count) = GcrLayout.WriteTrack(track, image.Slice(first, length), id, dos);
            disk.SetTrack((track - 1) * 2, bits, count, GcrLayout.Zone(track));
        }

        // Laying out the tracks is reading the image, not a change to the disk.
        disk.MarkSaved();
        return disk;
    }

    /// <summary>
    ///  Reads a disk's sectors back in order, as a DOS of the layout would.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   DOS 1 formats a sector's header alone and writes its data block when it first uses the sector, so on a DOS 1
    ///   disk a sector with a header and no data block is one never written, kept as zeros without a loss. On a DOS 2
    ///   disk, whose format writes every block, it is a loss.
    ///  </para>
    /// </remarks>
    /// <param name="disk">The disk.</param>
    /// <param name="dos">The layout.</param>
    /// <returns>The sectors, and the ones that could not be read, written as zeros.</returns>
    internal static (byte[] Image, IReadOnlyList<string> Unreadable) WriteSectors(CommodoreDisk disk, CommodoreDos dos)
    {
        ArgumentNullException.ThrowIfNull(disk);
        byte[] image = new byte[GcrLayout.SectorCount(dos) * GcrLayout.SectorSize];
        List<string> unreadable = [];
        for (int track = 1; track <= GcrLayout.Tracks; track++)
        {
            int position = (track - 1) * 2;
            int first = GcrLayout.FirstSector(track, dos) * GcrLayout.SectorSize;
            Span<byte> sectors = image.AsSpan(first, GcrLayout.SectorsOn(track, dos) * GcrLayout.SectorSize);
            bool[] found = GcrLayout.ReadTrack(
                disk.Track(position),
                disk.BitCount(position),
                track,
                sectors,
                dos,
                out bool[] unwritten,
                out _);

            for (int sector = 0; sector < found.Length; sector++)
            {
                if (found[sector]) { continue; }
                sectors.Slice(sector * GcrLayout.SectorSize, GcrLayout.SectorSize).Clear();
                if (dos == CommodoreDos.Dos1 && unwritten[sector]) { continue; }
                unreadable.Add($"track {track}, sector {sector}");
            }
        }

        return (image, unreadable);
    }

    /// <summary>
    ///  Lists what a disk holds that an image of a layout's sectors has no place for: good sectors numbered past a
    ///  track's last, and anything written at a half-track or past track 35.
    /// </summary>
    /// <param name="disk">The disk.</param>
    /// <param name="dos">The layout.</param>
    /// <returns>Each thing left out, as "track 18, sector 19" or "half-track 18.5".</returns>
    internal static IReadOnlyList<string> Omitted(CommodoreDisk disk, CommodoreDos dos)
    {
        ArgumentNullException.ThrowIfNull(disk);
        List<string> omitted = [];
        byte[] sectors = new byte[21 * GcrLayout.SectorSize];
        for (int position = 0; position < CommodoreDisk.Positions; position++)
        {
            int bits = disk.BitCount(position);
            if (bits == 0) { continue; }
            int track = (position / 2) + 1;
            if (position % 2 == 1 || track > GcrLayout.Tracks)
            {
                if (GcrLayout.HasSync(disk.Track(position), bits))
                {
                    omitted.Add(position % 2 == 1 ? $"half-track {track}.5" : $"track {track}");
                }

                continue;
            }

            GcrLayout.ReadTrack(disk.Track(position), bits, track, sectors, dos, out _, out IReadOnlyList<int> beyond);
            omitted.AddRange(beyond.Select(sector => $"track {track}, sector {sector}"));
        }

        return omitted;
    }
}
