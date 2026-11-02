// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Media;

/// <summary>
///  A DOS 3.2 or 3.3 disk being built: its image, which sectors are in use, and where allocation has reached.
/// </summary>
/// <param name="sectorsPerTrack">16 for DOS 3.3, 13 for DOS 3.2.</param>
internal sealed class DosDiskLayout(int sectorsPerTrack)
{
    private const int PairsPerList = 122;
    private const int EntriesPerSector = 7;
    private const int EntrySize = 35;
    private const int FirstEntry = 0x0B;
    private const int FirstPair = 0x0C;
    private const int FreeMap = 0x38;
    private const int SectorSize = DosDisk.SectorSize;
    private const int CatalogTrack = DosDisk.CatalogTrack;

    private readonly bool[] _used = new bool[DosDisk.TrackCount * sectorsPerTrack];
    private int _lastTrack = CatalogTrack;
    private int _direction = 1;

    /// <summary>
    ///  Gets the disk image, in the order of its sectors' numbers.
    /// </summary>
    public byte[] Image { get; } = new byte[DosDisk.TrackCount * sectorsPerTrack * DosDisk.SectorSize];

    /// <summary>
    ///  Marks a whole track as in use.
    /// </summary>
    /// <param name="track">The track.</param>
    public void UseTrack(int track) => _used.AsSpan(track * sectorsPerTrack, sectorsPerTrack).Fill(value: true);

    /// <summary>
    ///  Writes a file's data and track/sector lists, and its catalog entry.
    /// </summary>
    /// <param name="file">The file.</param>
    /// <param name="entry">Its place in the catalog, from 0.</param>
    /// <exception cref="ArgumentException">The name is not valid, or the disk is full.</exception>
    public void Add(DosFile file, int entry)
    {
        byte[] name = EncodeName(file.Name);
        ReadOnlySpan<byte> contents = file.Contents.Span;
        int dataSectors = (contents.Length + SectorSize - 1) / SectorSize;
        int lists = Math.Max(1, (dataSectors + PairsPerList - 1) / PairsPerList);

        (int Track, int Sector)[] listSectors = new (int, int)[lists];
        for (int list = 0; list < lists; list++)
        {
            listSectors[list] = Allocate();
        }

        for (int data = 0; data < dataSectors; data++)
        {
            (int track, int sector) = Allocate();
            int length = Math.Min(SectorSize, contents.Length - (data * SectorSize));
            contents.Slice(data * SectorSize, length).CopyTo(Sector(track, sector));
            (int listTrack, int listSector) = listSectors[data / PairsPerList];
            Span<byte> list = Sector(listTrack, listSector);
            int pair = FirstPair + ((data % PairsPerList) * 2);
            list[pair] = (byte)track;
            list[pair + 1] = (byte)sector;
        }

        for (int list = 0; list < lists; list++)
        {
            Span<byte> sector = Sector(listSectors[list].Track, listSectors[list].Sector);
            if (list + 1 < lists)
            {
                sector[1] = (byte)listSectors[list + 1].Track;
                sector[2] = (byte)listSectors[list + 1].Sector;
            }

            int offset = list * PairsPerList;
            sector[5] = (byte)offset;
            sector[6] = (byte)(offset >> 8);
        }

        Span<byte> catalog = Sector(CatalogTrack, sectorsPerTrack - 1 - (entry / EntriesPerSector));
        Span<byte> slot = catalog.Slice(FirstEntry + ((entry % EntriesPerSector) * EntrySize), EntrySize);
        slot[0] = (byte)listSectors[0].Track;
        slot[1] = (byte)listSectors[0].Sector;
        slot[2] = (byte)((byte)file.Type | (file.Locked ? 0x80 : 0));
        name.CopyTo(slot[3..]);
        int total = lists + dataSectors;
        slot[33] = (byte)total;
        slot[34] = (byte)(total >> 8);
    }

    /// <summary>
    ///  Chains the catalog's sectors: 15 (or 12) down to 1, the last with no link.
    /// </summary>
    public void WriteCatalogLinks()
    {
        for (int sector = sectorsPerTrack - 1; sector > 1; sector--)
        {
            Span<byte> catalog = Sector(CatalogTrack, sector);
            catalog[1] = CatalogTrack;
            catalog[2] = (byte)(sector - 1);
        }
    }

    /// <summary>
    ///  Writes the VTOC as INIT does, with the free-sector map: a 1 bit for each free sector, four bytes a track.
    /// </summary>
    /// <param name="volume">The volume number.</param>
    public void WriteVtoc(byte volume)
    {
        Span<byte> vtoc = Sector(CatalogTrack, sector: 0);
        vtoc[0] = 4;
        vtoc[1] = CatalogTrack;
        vtoc[2] = (byte)(sectorsPerTrack - 1);
        vtoc[3] = (byte)(sectorsPerTrack == 16 ? 3 : 2);
        vtoc[6] = volume;
        vtoc[0x27] = PairsPerList;
        vtoc[0x30] = (byte)_lastTrack;
        vtoc[0x31] = (byte)_direction;
        vtoc[0x34] = DosDisk.TrackCount;
        vtoc[0x35] = (byte)sectorsPerTrack;
        vtoc[0x36] = 0;
        vtoc[0x37] = 1;
        for (int track = 0; track < DosDisk.TrackCount; track++)
        {
            uint free = 0;
            for (int sector = 0; sector < sectorsPerTrack; sector++)
            {
                if (!_used[(track * sectorsPerTrack) + sector]) { free |= 1u << (sector + 16); }
            }

            int map = FreeMap + (track * 4);
            vtoc[map] = (byte)(free >> 24);
            vtoc[map + 1] = (byte)(free >> 16);
        }
    }

    // The next free sector: tracks 18 outward, then 16 inward, each from its highest sector down.
    private (int Track, int Sector) Allocate()
    {
        foreach (int track in Tracks())
        {
            for (int sector = sectorsPerTrack - 1; sector >= 0; sector--)
            {
                int index = (track * sectorsPerTrack) + sector;
                if (_used[index]) { continue; }

                _used[index] = true;
                _lastTrack = track;
                _direction = track > CatalogTrack ? 1 : 0xFF;
                return (track, sector);
            }
        }

        throw new ArgumentException("The files don't fit on the disk.");
    }

    // Tracks in the order allocation tries them.
    private static IEnumerable<int> Tracks()
    {
        for (int track = CatalogTrack + 1; track < DosDisk.TrackCount; track++) { yield return track; }
        for (int track = CatalogTrack - 1; track >= DosDisk.DosTrackCount; track--) { yield return track; }
    }

    // One sector of the image.
    private Span<byte> Sector(int track, int sector) =>
        Image.AsSpan(((track * sectorsPerTrack) + sector) * SectorSize, SectorSize);

    // A name as the catalog stores it: 30 characters with bit 7 set, padded with spaces.
    private static byte[] EncodeName(string name)
    {
        ArgumentException.ThrowIfNullOrEmpty(name);
        if (name.Length > DosFile.MaximumNameLength)
        {
            throw new ArgumentException($"'{name}' is longer than {DosFile.MaximumNameLength} characters.", nameof(name));
        }

        byte[] encoded = new byte[DosFile.MaximumNameLength];
        for (int index = 0; index < encoded.Length; index++)
        {
            char character = index < name.Length ? name[index] : ' ';
            if (character is < ' ' or > '~' || character == ',')
            {
                throw new ArgumentException($"'{name}' has a character DOS can't use in a name.", nameof(name));
            }

            encoded[index] = (byte)(character | 0x80);
        }

        return encoded;
    }
}
