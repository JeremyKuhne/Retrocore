// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Media.Commodore;

/// <summary>
///  A DOS 2 disk's file system, built on the host: the 4040's layout, which the 1541 kept, in a D64 image's 683
///  sectors. It formats a blank disk and adds program and sequential files, as the drive's <c>N</c> command and
///  <c>SAVE</c> would, and reads back the files a disk holds.
/// </summary>
/// <remarks>
///  <para>
///   Track 18 holds the directory. Its sector 0 is the header: the first directory sector (18, 1), the format
///   (<c>A</c>), the BAM, the disk's name in 16 bytes padded with <c>$A0</c>, its two-byte ID at <c>$A2</c>, and the
///   DOS version, <c>2A</c>, at <c>$A5</c>. The BAM is four bytes a track, from <c>$04</c>: the free sectors, then a
///   bit for each sector, sector 0 in byte 1's bit 0, set where the sector is free. The directory's sectors hold
///   eight entries of 32 bytes: the file's type (<c>$82</c> a program, <c>$81</c> sequential, closed), its first
///   track and sector, its name padded with <c>$A0</c>, and its length in blocks at <c>$1E</c>. The first entry's
///   first two bytes link to the next directory sector, track 0 ending the chain.
///  </para>
///  <para>
///   A file is a chain of blocks, each its next track and sector and 254 bytes; the last block's track is 0 and its
///   sector byte is the index of its last byte. A program file's first two bytes are its load address, as in a
///   <c>.prg</c> file. Blocks are taken from the track nearest the directory with a free sector, 17, then 19, 16, 20
///   and outwards, ten sectors apart within a track, and directory sectors three apart, the 1541's spacings. Any
///   spacing reads; it changes only how long a read waits for the next block to come round. An empty sequential file
///   takes one block holding nothing.
///  </para>
/// </remarks>
public sealed class CbmDosDisk
{
    /// <summary>
    ///  The directory's track.
    /// </summary>
    public const int DirectoryTrack = 18;

    /// <summary>
    ///  The bytes of data a block holds after its link.
    /// </summary>
    public const int BlockData = GcrLayout.SectorSize - 2;

    /// <summary>
    ///  The longest name a disk or a file takes.
    /// </summary>
    public const int MaximumNameLength = 16;

    private const byte Padding = 0xA0;
    private const int EntrySize = 32;
    private const int EntriesPerSector = GcrLayout.SectorSize / EntrySize;
    private const int FileInterleave = 10;
    private const int DirectoryInterleave = 3;
    private const int NameOffset = 0x90;
    private const int IdOffset = 0xA2;

    private readonly byte[] _sectors;

    private CbmDosDisk(byte[] sectors) => _sectors = sectors;

    /// <summary>
    ///  Formats a blank disk, as the drive's <c>N0:name,id</c> command does: an empty directory, and every sector free
    ///  but track 18's first two.
    /// </summary>
    /// <param name="name">The disk's name, at most 16 characters of PETSCII.</param>
    /// <param name="id">The disk's ID, two characters of PETSCII.</param>
    /// <returns>The disk.</returns>
    /// <exception cref="ArgumentException">
    ///  The name or ID is the wrong length or holds a character DOS reserves.
    /// </exception>
    public static CbmDosDisk Format(string name, string id)
    {
        byte[] nameBytes = Petscii(name, nameof(name), 1, MaximumNameLength);
        byte[] idBytes = Petscii(id, nameof(id), 2, 2);
        CbmDosDisk disk = new(new byte[D64Format.Size]);
        Span<byte> header = disk.Sector(DirectoryTrack, 0);
        header[0] = DirectoryTrack;
        header[1] = 1;
        header[2] = (byte)'A';
        for (int track = 1; track <= GcrLayout.Tracks; track++)
        {
            for (int sector = 0; sector < GcrLayout.SectorsOn(track); sector++)
            {
                disk.SetFree(track, sector, free: true);
            }
        }

        disk.SetFree(DirectoryTrack, 0, free: false);
        disk.SetFree(DirectoryTrack, 1, free: false);
        header.Slice(NameOffset, 0x1B).Fill(Padding);
        nameBytes.CopyTo(header[NameOffset..]);
        idBytes.CopyTo(header[IdOffset..]);
        header[0xA5] = (byte)'2';
        header[0xA6] = (byte)'A';

        Span<byte> directory = disk.Sector(DirectoryTrack, 1);
        directory[1] = 0xFF;
        return disk;
    }

    /// <summary>
    ///  Reads a D64 image's file system, to read its files or add to them.
    /// </summary>
    /// <param name="image">The image's bytes, with or without error codes; the codes are not kept.</param>
    /// <returns>The disk.</returns>
    /// <exception cref="InvalidDataException">The image is not a D64 image's size.</exception>
    public static CbmDosDisk FromD64(ReadOnlySpan<byte> image)
    {
        if (!D64Format.IsD64(image))
        {
            throw new InvalidDataException(
                $"A D64 image is {D64Format.Size} bytes, or {D64Format.SizeWithErrors} with error codes.");
        }

        return new(image[..D64Format.Size].ToArray());
    }

    /// <summary>
    ///  Gets the disk's name, without its padding.
    /// </summary>
    public string Name => Text(Sector(DirectoryTrack, 0).Slice(NameOffset, MaximumNameLength));

    /// <summary>
    ///  Gets the disk's ID.
    /// </summary>
    public string Id => Text(Sector(DirectoryTrack, 0).Slice(IdOffset, 2));

    /// <summary>
    ///  Gets the free blocks, as the directory's <c>BLOCKS FREE.</c> counts them: on every track but the directory's.
    /// </summary>
    public int BlocksFree
    {
        get
        {
            int free = 0;
            for (int track = 1; track <= GcrLayout.Tracks; track++)
            {
                if (track != DirectoryTrack) { free += Bam(track)[0]; }
            }

            return free;
        }
    }

    /// <summary>
    ///  Gets the files in the directory, in its order.
    /// </summary>
    public IReadOnlyList<CbmDosFile> Files
    {
        get
        {
            List<CbmDosFile> files = [];
            foreach ((int track, int sector, int index) in Entries())
            {
                ReadOnlySpan<byte> entry = Entry(track, sector, index);
                if (entry[2] == 0) { continue; }
                files.Add(new(
                    Text(entry.Slice(5, MaximumNameLength)),
                    (CbmDosFileType)(entry[2] & 0x07),
                    (entry[2] & 0x80) != 0,
                    entry[3],
                    entry[4],
                    entry[0x1E] | (entry[0x1F] << 8)));
            }

            return files;
        }
    }

    /// <summary>
    ///  Adds a program file.
    /// </summary>
    /// <param name="name">The file's name, at most 16 characters of PETSCII.</param>
    /// <param name="prg">
    ///  The file's bytes: its load address, low byte first, then the program, as a <c>.prg</c> file.
    /// </param>
    /// <exception cref="ArgumentException">
    ///  The name is empty, too long, holds a character DOS reserves or is taken, or the file is shorter than its load
    ///  address.
    /// </exception>
    /// <exception cref="IOException">The disk or its directory is full; the disk is unchanged.</exception>
    public void AddProgram(string name, ReadOnlySpan<byte> prg)
    {
        if (prg.Length < 2)
        {
            throw new ArgumentException("A program file starts with its load address.", nameof(prg));
        }

        Add(name, CbmDosFileType.Program, prg);
    }

    /// <summary>
    ///  Adds a sequential file.
    /// </summary>
    /// <param name="name">The file's name, at most 16 characters of PETSCII.</param>
    /// <param name="data">The file's bytes, which may be none.</param>
    /// <exception cref="ArgumentException">
    ///  The name is empty, too long, holds a character DOS reserves or is taken.
    /// </exception>
    /// <exception cref="IOException">The disk or its directory is full; the disk is unchanged.</exception>
    public void AddSequential(string name, ReadOnlySpan<byte> data) => Add(name, CbmDosFileType.Sequential, data);

    /// <summary>
    ///  Reads a file's bytes by following its chain of blocks.
    /// </summary>
    /// <param name="name">The file's name, as <see cref="Files"/> gives it.</param>
    /// <returns>The bytes; a program file's start with its load address.</returns>
    /// <exception cref="FileNotFoundException">No file has the name.</exception>
    /// <exception cref="InvalidDataException">The chain leaves the disk or loops.</exception>
    public byte[] ReadFile(string name)
    {
        CbmDosFile file = Files.FirstOrDefault(entry => entry.Name == name)
            ?? throw new FileNotFoundException($"The disk has no file named {name}.", name);

        List<byte> data = [];
        int track = file.Track;
        int sector = file.Sector;
        for (int blocks = 0; ; blocks++)
        {
            if (blocks == GcrLayout.Sectors || !IsSector(track, sector))
            {
                throw new InvalidDataException(
                    $"{name}'s chain of blocks leaves the disk or loops, at track {track}, sector {sector}.");
            }

            ReadOnlySpan<byte> block = Sector(track, sector);
            if (block[0] == 0)
            {
                // The last block's second byte is its last byte's index, so 1 holds nothing.
                if (block[1] > 1) { data.AddRange(block[2..(block[1] + 1)]); }
                return [.. data];
            }

            data.AddRange(block[2..]);
            (track, sector) = (block[0], block[1]);
        }
    }

    /// <summary>
    ///  Writes the disk as a D64 image, without error codes.
    /// </summary>
    /// <returns>The image.</returns>
    public byte[] ToD64() => (byte[])_sectors.Clone();

    /// <summary>
    ///  Lays the disk out as the drive's head sees it, each track as the 4040 formats it, to put in an emulated drive.
    /// </summary>
    /// <returns>The disk.</returns>
    public CommodoreDisk ToDisk() => D64Format.Read(_sectors);

    private void Add(string name, CbmDosFileType type, ReadOnlySpan<byte> data)
    {
        byte[] nameBytes = Petscii(name, nameof(name), 1, MaximumNameLength);
        string key = Text(nameBytes);
        if (Files.Any(file => file.Name == key))
        {
            throw new ArgumentException($"The disk already has a file named {key}.", nameof(name));
        }

        // Work on a copy, so a full disk or directory leaves the disk as it was.
        CbmDosDisk work = new((byte[])_sectors.Clone());
        (int entryTrack, int entrySector, int entryIndex) = work.FreeEntry()
            ?? throw new IOException("The disk's directory is full.");

        int blocks = Math.Max(1, (data.Length + BlockData - 1) / BlockData);
        if (blocks > work.BlocksFree)
        {
            throw new IOException($"The disk is full: {key} needs {blocks} blocks, and {work.BlocksFree} are free.");
        }

        (int Track, int Sector)[] chain = new (int, int)[blocks];
        (int track, int sector) = (0, 0);
        for (int i = 0; i < blocks; i++)
        {
            (track, sector) = work.Allocate(i == 0 ? null : (track, sector));
            chain[i] = (track, sector);
        }

        for (int i = 0; i < blocks; i++)
        {
            Span<byte> block = work.Sector(chain[i].Track, chain[i].Sector);
            block.Clear();
            ReadOnlySpan<byte> part = data[(i * BlockData)..Math.Min(data.Length, (i + 1) * BlockData)];
            part.CopyTo(block[2..]);
            if (i + 1 < blocks)
            {
                block[0] = (byte)chain[i + 1].Track;
                block[1] = (byte)chain[i + 1].Sector;
            }
            else
            {
                block[1] = (byte)(part.Length + 1);
            }
        }

        Span<byte> entry = work.Sector(entryTrack, entrySector).Slice(entryIndex * EntrySize, EntrySize);
        entry[2..].Clear();
        entry[2] = (byte)(0x80 | (int)type);
        entry[3] = (byte)chain[0].Track;
        entry[4] = (byte)chain[0].Sector;
        entry.Slice(5, MaximumNameLength).Fill(Padding);
        nameBytes.CopyTo(entry[5..]);
        entry[0x1E] = (byte)blocks;
        entry[0x1F] = (byte)(blocks >> 8);
        work._sectors.CopyTo(_sectors, 0);
    }

    // The next free directory entry, adding a directory sector when the last is full; null when track 18 is full.
    private (int Track, int Sector, int Index)? FreeEntry()
    {
        int last = 1;
        foreach ((int track, int sector, int index) in Entries())
        {
            if (Entry(track, sector, index)[2] == 0) { return (track, sector, index); }
            last = sector;
        }

        int sectors = GcrLayout.SectorsOn(DirectoryTrack);
        for (int step = 0; step < sectors; step++)
        {
            int candidate = (last + DirectoryInterleave + step) % sectors;
            if (!IsFree(DirectoryTrack, candidate)) { continue; }
            SetFree(DirectoryTrack, candidate, free: false);
            Span<byte> added = Sector(DirectoryTrack, candidate);
            added.Clear();
            added[1] = 0xFF;
            Span<byte> previous = Sector(DirectoryTrack, last);
            previous[0] = DirectoryTrack;
            previous[1] = (byte)candidate;
            return (DirectoryTrack, candidate, 0);
        }

        return null;
    }

    // Each directory entry's place, following the chain from 18, 1.
    private List<(int Track, int Sector, int Index)> Entries()
    {
        List<(int, int, int)> entries = [];
        HashSet<int> seen = [];
        int track = DirectoryTrack;
        int sector = 1;
        while (track != 0 && IsSector(track, sector) && seen.Add((track << 8) | sector))
        {
            for (int index = 0; index < EntriesPerSector; index++) { entries.Add((track, sector, index)); }
            ReadOnlySpan<byte> block = Sector(track, sector);
            (track, sector) = (block[0], block[1]);
        }

        return entries;
    }

    private ReadOnlySpan<byte> Entry(int track, int sector, int index) =>
        Sector(track, sector).Slice(index * EntrySize, EntrySize);

    // Takes a free sector for a file's next block: on the previous block's track, ten sectors on, while it has one
    // free, else on the track nearest the directory that has one.
    private (int Track, int Sector) Allocate((int Track, int Sector)? previous)
    {
        if (previous is { } last && Bam(last.Track)[0] > 0)
        {
            return Take(last.Track, last.Sector + FileInterleave);
        }

        for (int distance = 1; distance < GcrLayout.Tracks; distance++)
        {
            foreach (int candidate in (int[])[DirectoryTrack - distance, DirectoryTrack + distance])
            {
                if (candidate is >= 1 and <= GcrLayout.Tracks && Bam(candidate)[0] > 0) { return Take(candidate, 0); }
            }
        }

        throw new InvalidOperationException("No sector is free, though the free blocks were counted.");
    }

    // Takes the first free sector on a track at or after a sector, wrapping round.
    private (int Track, int Sector) Take(int track, int from)
    {
        int sectors = GcrLayout.SectorsOn(track);
        for (int step = 0; step < sectors; step++)
        {
            int sector = (from + step) % sectors;
            if (!IsFree(track, sector)) { continue; }
            SetFree(track, sector, free: false);
            return (track, sector);
        }

        throw new InvalidOperationException($"Track {track} has no free sector, though its count says it has.");
    }

    private Span<byte> Bam(int track) => Sector(DirectoryTrack, 0).Slice(4 * track, 4);

    private bool IsFree(int track, int sector) => (Bam(track)[1 + (sector >> 3)] & (1 << (sector & 7))) != 0;

    private void SetFree(int track, int sector, bool free)
    {
        if (IsFree(track, sector) == free) { return; }
        Span<byte> bam = Bam(track);
        bam[1 + (sector >> 3)] ^= (byte)(1 << (sector & 7));
        bam[0] = (byte)(bam[0] + (free ? 1 : -1));
    }

    private static bool IsSector(int track, int sector) =>
        track is >= 1 and <= GcrLayout.Tracks && sector >= 0 && sector < GcrLayout.SectorsOn(track);

    private Span<byte> Sector(int track, int sector) =>
        _sectors.AsSpan((GcrLayout.FirstSector(track) + sector) * GcrLayout.SectorSize, GcrLayout.SectorSize);

    // A name or ID as the DOS stores it: upper case, each character its PETSCII code, refusing the characters the DOS's
    // command parser reads as punctuation or wildcards.
    private static byte[] Petscii(string text, string parameter, int minimum, int maximum)
    {
        ArgumentNullException.ThrowIfNull(text, parameter);
        if (text.Length < minimum || text.Length > maximum)
        {
            throw new ArgumentException(
                minimum == maximum
                    ? $"The {parameter} is {minimum} characters."
                    : $"The {parameter} is {minimum} to {maximum} characters.",
                parameter);
        }

        byte[] bytes = new byte[text.Length];
        for (int i = 0; i < text.Length; i++)
        {
            char c = char.ToUpperInvariant(text[i]);
            if (c is < ' ' or > ']' or '"' or ',' or ':' or '*' or '?' or '=')
            {
                throw new ArgumentException($"'{text[i]}' cannot be in a name on a Commodore disk.", parameter);
            }

            bytes[i] = (byte)c;
        }

        return bytes;
    }

    // Stored bytes as text, up to the first padding byte.
    private static string Text(ReadOnlySpan<byte> bytes)
    {
        int end = bytes.IndexOf(Padding);
        ReadOnlySpan<byte> text = end < 0 ? bytes : bytes[..end];
        return string.Create(text.Length, text.ToArray(), (chars, source) =>
        {
            for (int i = 0; i < source.Length; i++) { chars[i] = (char)source[i]; }
        });
    }
}
