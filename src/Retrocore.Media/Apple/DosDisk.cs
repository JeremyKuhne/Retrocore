// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Media;

/// <summary>
///  Builds DOS 3.2 and 3.3 disk images: DOS on tracks 0 to 2, the VTOC and catalog on track 17, and files.
/// </summary>
/// <remarks>
///  <para>
///   A 16-sector image comes out in DOS 3.3's sector order, as a <c>.dsk</c> or <c>.do</c> file stores it; a
///   13-sector image in the order of its sectors' numbers, as a <c>.d13</c> file stores it. The layout follows
///   INIT: the VTOC in track 17 sector 0, the catalog in sectors 15 (or 12) down to 1 of the same track, and
///   files from track 18 outward, then from track 16 inward.
///  </para>
/// </remarks>
public static class DosDisk
{
    /// <summary>
    ///  Gets the number of tracks on a disk.
    /// </summary>
    public const int TrackCount = 35;

    /// <summary>
    ///  Gets the size of a sector.
    /// </summary>
    public const int SectorSize = 256;

    /// <summary>
    ///  Gets the track that holds the VTOC and the catalog.
    /// </summary>
    public const int CatalogTrack = 17;

    /// <summary>
    ///  Gets the number of tracks DOS itself occupies.
    /// </summary>
    public const int DosTrackCount = 3;

    /// <summary>
    ///  Gets the number of pages BOOT 1 loads from track 0: the boot sector, BOOT 2 and RWTS.
    /// </summary>
    public const int BootPages = 10;

    private const int EntriesPerSector = 7;
    private const int CatalogEntryStart = 11;
    private const int CatalogEntrySize = 35;
    private const int SectorPairsPerList = 122;
    private const byte DefaultVolume = 254;

    /// <summary>
    ///  Places a DOS 3.3 memory image on tracks 0 to 2, as INIT and the System Masters do.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   The image's last ten pages, from the boot loader's page to the end of DOS, go to track 0 sectors 0 to
    ///   9; the pages below them go backwards from track 2 sector 4. A disk INIT writes holds DOS where it runs,
    ///   $9D00-$BFFF, so its first page lands in track 0 sector 12; a System Master holds the relocator and DOS
    ///   from $1B00, so its first page lands in sector 10.
    ///  </para>
    /// </remarks>
    /// <param name="dos">DOS's memory image, from its first page to its last.</param>
    /// <returns>Tracks 0 to 2 in DOS 3.3's sector order.</returns>
    /// <exception cref="ArgumentException">The image is not whole pages, or does not fit.</exception>
    public static byte[] Dos33Tracks(ReadOnlySpan<byte> dos)
    {
        const int SectorsPerTrack = 16;
        int pages = dos.Length / SectorSize;
        int lastSector = (2 * SectorsPerTrack) + 4;
        if (dos.Length % SectorSize != 0 || pages < BootPages || pages - BootPages > lastSector - BootPages + 1)
        {
            throw new ArgumentException("A DOS 3.3 image is 10 to 37 whole pages.", nameof(dos));
        }

        byte[] tracks = new byte[DosTrackCount * SectorsPerTrack * SectorSize];
        int low = pages - BootPages;
        for (int page = 0; page < BootPages; page++)
        {
            dos.Slice((low + page) * SectorSize, SectorSize).CopyTo(tracks.AsSpan(page * SectorSize));
        }

        for (int page = 0; page < low; page++)
        {
            int sector = lastSector - low + 1 + page;
            dos.Slice(page * SectorSize, SectorSize).CopyTo(tracks.AsSpan(sector * SectorSize));
        }

        return tracks;
    }

    /// <summary>
    ///  Places a DOS 3.2 memory image on tracks 0 to 2, as its INIT and System Master do.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   The image's last ten pages, from the boot loader's page to the end of DOS, go to track 0 sectors 0 to
    ///   9; the pages below them go forwards from track 0 sector 10. A System Master's relocator takes sectors 10
    ///   and 11, so its DOS starts in sector 12; a disk INIT writes starts DOS itself in sector 10. DOS 3.2 has no
    ///   sector interleave of its own, so these are the numbers written on the disk.
    ///  </para>
    /// </remarks>
    /// <param name="dos">DOS's memory image, from its first page to its last.</param>
    /// <returns>Tracks 0 to 2 in the order of their sectors' numbers.</returns>
    /// <exception cref="ArgumentException">The image is not whole pages, or does not fit.</exception>
    public static byte[] Dos32Tracks(ReadOnlySpan<byte> dos)
    {
        const int SectorsPerTrack = 13;
        const int FirstLowSector = BootPages;
        int pages = dos.Length / SectorSize;
        int sectors = DosTrackCount * SectorsPerTrack;
        if (dos.Length % SectorSize != 0 || pages < BootPages || pages - BootPages > sectors - FirstLowSector)
        {
            throw new ArgumentException("A DOS 3.2 image is 10 to 39 whole pages.", nameof(dos));
        }

        byte[] tracks = new byte[sectors * SectorSize];
        int low = pages - BootPages;
        for (int page = 0; page < BootPages; page++)
        {
            dos.Slice((low + page) * SectorSize, SectorSize).CopyTo(tracks.AsSpan(page * SectorSize));
        }

        for (int page = 0; page < low; page++)
        {
            dos.Slice(page * SectorSize, SectorSize).CopyTo(tracks.AsSpan((FirstLowSector + page) * SectorSize));
        }

        return tracks;
    }

    /// <summary>
    ///  Builds a disk with DOS on tracks 0 to 2, an initialized VTOC and catalog, and the given files.
    /// </summary>
    /// <param name="dosTracks">Tracks 0 to 2, in the image's sector order.</param>
    /// <param name="files">The files, in catalog order.</param>
    /// <param name="sectorsPerTrack">16 for DOS 3.3, 13 for DOS 3.2.</param>
    /// <param name="volume">The volume number, 1 to 254.</param>
    /// <returns>The disk image.</returns>
    /// <exception cref="ArgumentException">An argument is out of range, or the files do not fit.</exception>
    public static byte[] Create(
        ReadOnlySpan<byte> dosTracks,
        IEnumerable<DosFile> files,
        int sectorsPerTrack = 16,
        byte volume = DefaultVolume)
    {
        ArgumentNullException.ThrowIfNull(files);
        if (sectorsPerTrack is not (13 or 16)) { throw new ArgumentOutOfRangeException(nameof(sectorsPerTrack)); }
        if (volume == 0 || volume == 255) { throw new ArgumentOutOfRangeException(nameof(volume)); }
        if (dosTracks.Length != DosTrackCount * sectorsPerTrack * SectorSize)
        {
            throw new ArgumentException("DOS's tracks must be exactly tracks 0 to 2.", nameof(dosTracks));
        }

        DosDiskLayout disk = new(sectorsPerTrack);
        dosTracks.CopyTo(disk.Image);
        for (int track = 0; track < DosTrackCount; track++) { disk.UseTrack(track); }
        disk.UseTrack(CatalogTrack);

        int entry = 0;
        foreach (DosFile file in files)
        {
            if (entry == (sectorsPerTrack - 1) * EntriesPerSector)
            {
                throw new ArgumentException("The catalog is full.", nameof(files));
            }

            disk.Add(file, entry++);
        }

        disk.WriteCatalogLinks();
        disk.WriteVtoc(volume);
        return disk.Image;
    }

    /// <summary>
    ///  Reads the files a disk's catalog lists, in catalog order.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   A 143,360-byte image is 16 sectors a track, in DOS 3.3's sector order as a <c>.dsk</c> or <c>.do</c> file
    ///   stores it, or in ProDOS's order as a <c>.po</c> file does; a 116,480-byte image is 13 sectors a track, as a
    ///   <c>.d13</c> file stores it. Each file's contents are its data sectors in track/sector list order, whole
    ///   sectors, with the length or address DOS keeps at the start; <see cref="DosFile.TryGetBinary"/> and
    ///   <see cref="DosFile.TryGetProgram"/> take that apart.
    ///  </para>
    /// </remarks>
    /// <param name="image">The disk image.</param>
    /// <param name="proDosOrder">Whether a 16-sector image is in ProDOS's sector order.</param>
    /// <returns>The files.</returns>
    /// <exception cref="InvalidDataException">The image is not a DOS disk, or its catalog is broken.</exception>
    public static IReadOnlyList<DosFile> ReadFiles(ReadOnlySpan<byte> image, bool proDosOrder = false)
    {
        int sectorsPerTrack = image.Length switch
        {
            TrackCount * 16 * SectorSize => 16,
            TrackCount * 13 * SectorSize => 13,
            _ => throw new InvalidDataException("A DOS disk image is 143,360 bytes (16 sectors a track) or 116,480 (13).")
        };

        byte[] disk = sectorsPerTrack == 16 && proDosOrder ? FromProDosOrder(image) : image.ToArray();
        List<DosFile> files = [];
        HashSet<int> seen = [];
        Span<char> name = stackalloc char[DosFile.MaximumNameLength];
        ReadOnlySpan<byte> vtoc = Sector(disk, sectorsPerTrack, CatalogTrack, 0);
        (int track, int sector) = (vtoc[1], vtoc[2]);
        while (track != 0)
        {
            if (!seen.Add((track * sectorsPerTrack) + sector))
            {
                throw new InvalidDataException("The catalog's sectors loop.");
            }

            ReadOnlySpan<byte> catalog = Sector(disk, sectorsPerTrack, track, sector);
            for (int entry = 0; entry < EntriesPerSector; entry++)
            {
                ReadOnlySpan<byte> file = catalog.Slice(CatalogEntryStart + (entry * CatalogEntrySize), CatalogEntrySize);

                // A first track of 0 is an entry never used; $FF marks a deleted file.
                if (file[0] is 0 or 0xFF) { continue; }

                for (int index = 0; index < name.Length; index++) { name[index] = (char)(file[3 + index] & 0x7F); }
                files.Add(new DosFile(
                    name.TrimEnd(' ').ToString(),
                    (DosFileType)(file[2] & 0x7F),
                    Contents(disk, sectorsPerTrack, file[0], file[1]),
                    Locked: (file[2] & 0x80) != 0));
            }

            (track, sector) = (catalog[1], catalog[2]);
        }

        return files;
    }

    // A file's data sectors, following its track/sector lists.
    private static byte[] Contents(byte[] disk, int sectorsPerTrack, int track, int sector)
    {
        List<byte> data = [];
        HashSet<int> seen = [];
        while (track != 0)
        {
            if (!seen.Add((track * sectorsPerTrack) + sector))
            {
                throw new InvalidDataException("A file's track/sector lists loop.");
            }

            ReadOnlySpan<byte> list = Sector(disk, sectorsPerTrack, track, sector);
            for (int pair = 0; pair < SectorPairsPerList; pair++)
            {
                int dataTrack = list[12 + (pair * 2)];
                int dataSector = list[13 + (pair * 2)];
                if (dataTrack == 0 && dataSector == 0) { break; }
                data.AddRange(Sector(disk, sectorsPerTrack, dataTrack, dataSector));
            }

            (track, sector) = (list[1], list[2]);
        }

        return [.. data];
    }

    private static ReadOnlySpan<byte> Sector(byte[] disk, int sectorsPerTrack, int track, int sector)
    {
        if (track >= TrackCount || sector >= sectorsPerTrack)
        {
            throw new InvalidDataException($"Track {track} sector {sector} is not on the disk.");
        }

        return disk.AsSpan(((track * sectorsPerTrack) + sector) * SectorSize, SectorSize);
    }

    // Puts a ProDOS-order image's sectors in DOS 3.3's order. The disk's physical sector p holds DOS's sector p*7
    // mod 15 and ProDOS's p*8 mod 15; physical sector 15 is 15 in both.
    private static byte[] FromProDosOrder(ReadOnlySpan<byte> image)
    {
        const int SectorsPerTrack = 16;
        byte[] disk = new byte[image.Length];
        for (int track = 0; track < TrackCount; track++)
        {
            for (int physical = 0; physical < SectorsPerTrack; physical++)
            {
                int dos = physical == 15 ? 15 : physical * 7 % 15;
                int proDos = physical == 15 ? 15 : physical * 8 % 15;
                image.Slice(((track * SectorsPerTrack) + proDos) * SectorSize, SectorSize)
                    .CopyTo(disk.AsSpan(((track * SectorsPerTrack) + dos) * SectorSize));
            }
        }

        return disk;
    }
}
