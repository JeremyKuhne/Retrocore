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
}
