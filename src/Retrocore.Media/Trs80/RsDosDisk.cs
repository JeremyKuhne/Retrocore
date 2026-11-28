// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text;

namespace Retrocore.Media.Trs80;

/// <summary>
///  A disk in the file system of Disk Extended Color BASIC, RS-DOS: 35 tracks of 18 256-byte sectors, as a JVC image,
///  with its files' directory and allocation table on track 17.
/// </summary>
/// <remarks>
///  <para>
///   The disk is 68 granules of nine sectors, two to a track, the directory's track left out: granule g is on track
///   g / 2, or one more from track 17 on, from sector 1 or 10. Track 17's sector 2 is the file allocation table: a byte
///   for each granule, <c>$FF</c> when it is free, the number of the file's next granule, or <c>$C0</c> and the count of
///   the sectors the file uses in it, for its last. Sectors 3 to 11 are the directory, eight 32-byte entries to a
///   sector: the name, padded with spaces to eight, the extension to three, the file's type (0 a BASIC program, 1
///   data, 2 machine language, 3 text), its ASCII flag (0 binary, <c>$FF</c> text), its first granule and the bytes it
///   uses of its last sector, high byte first. An entry that starts with <c>$FF</c> ends the directory, and a fresh
///   disk's sectors are <c>$FF</c> throughout (<c>DIRSRCH</c> and <c>FATCON</c> in DiskBasic.asm).
///  </para>
/// </remarks>
public static class RsDosDisk
{
    /// <summary>
    ///  The disk's tracks.
    /// </summary>
    public const int Tracks = 35;

    /// <summary>
    ///  The sectors on a track.
    /// </summary>
    public const int SectorsPerTrack = 18;

    /// <summary>
    ///  A sector's bytes.
    /// </summary>
    public const int SectorSize = 256;

    /// <summary>
    ///  The track of the directory and the allocation table.
    /// </summary>
    public const int DirectoryTrack = 17;

    /// <summary>
    ///  The granules a disk has.
    /// </summary>
    public const int Granules = 68;

    /// <summary>
    ///  The type of a machine-language file, which <c>LOADM</c> loads.
    /// </summary>
    public const byte MachineLanguage = 2;

    /// <summary>
    ///  The type of a data file.
    /// </summary>
    public const byte Data = 1;

    // The sectors in a granule.
    private const int GranuleSectors = 9;
    private const int AllocationSector = 2;
    private const int FirstDirectorySector = 3;
    private const int DirectorySectors = 9;
    private const int EntrySize = 32;
    private const byte Free = 0xFF;
    private const byte Last = 0xC0;

    /// <summary>
    ///  Builds a disk of files.
    /// </summary>
    /// <param name="files">
    ///  The files, in the directory's order: each name (1 to 8 capital letters and digits from a letter), extension (up
    ///  to 3 of them, also from a letter, or none), type, ASCII flag and contents.
    /// </param>
    /// <returns>The JVC image's 161,280 bytes, with no header.</returns>
    /// <exception cref="ArgumentException">
    ///  A name is not one the SDK puts on a disk (<see cref="IsName"/>), two files share one, or a file is empty.
    /// </exception>
    /// <exception cref="InvalidOperationException">The files do not fit, or the directory is full.</exception>
    public static byte[] Create(IReadOnlyList<(string Name, string Extension, byte Type, bool Ascii, byte[] Bytes)> files)
    {
        ArgumentNullException.ThrowIfNull(files);
        byte[] image = new byte[Tracks * SectorsPerTrack * SectorSize];
        image.AsSpan().Fill(Free);
        if (files.Count > DirectorySectors * (SectorSize / EntrySize))
        {
            throw new InvalidOperationException("An RS-DOS directory holds 72 files.");
        }

        HashSet<string> names = [];
        int granule = 0;
        Span<byte> table = image.AsSpan(Offset(DirectoryTrack, AllocationSector), Granules);
        for (int index = 0; index < files.Count; index++)
        {
            (string name, string extension, byte type, bool ascii, byte[] bytes) = files[index];
            if (!IsName(name, 8) || !(extension.Length == 0 || IsName(extension, 3)))
            {
                throw new ArgumentException($"'{Shown(name, extension)}' is not a name the SDK puts on a disk: 1 to 8 capital letters and digits from a letter, and an extension of up to 3, also from a letter.", nameof(files));
            }

            if (!names.Add(Shown(name, extension)))
            {
                throw new ArgumentException($"Two files are named {Shown(name, extension)}.", nameof(files));
            }

            if (bytes.Length == 0)
            {
                throw new ArgumentException($"{Shown(name, extension)} is empty.", nameof(files));
            }

            int sectors = (bytes.Length + SectorSize - 1) / SectorSize;
            int granules = (sectors + GranuleSectors - 1) / GranuleSectors;
            if (granule + granules > Granules)
            {
                throw new InvalidOperationException($"{Shown(name, extension)} does not fit on the disk.");
            }

            for (int part = 0; part < granules; part++)
            {
                int at = granule + part;
                (int track, int sector) = Start(at);
                int offset = part * GranuleSectors * SectorSize;
                int length = Math.Min(GranuleSectors * SectorSize, bytes.Length - offset);
                bytes.AsSpan(offset, length).CopyTo(image.AsSpan(Offset(track, sector)));
                table[at] = part == granules - 1 ? (byte)(Last + (sectors - (part * GranuleSectors))) : (byte)(at + 1);
            }

            int lastBytes = bytes.Length - ((sectors - 1) * SectorSize);
            Span<byte> entry = image.AsSpan(Offset(DirectoryTrack, FirstDirectorySector) + (index * EntrySize), EntrySize);
            entry.Clear();
            Encoding.ASCII.GetBytes(name.PadRight(8)).CopyTo(entry);
            Encoding.ASCII.GetBytes(extension.PadRight(3)).CopyTo(entry[8..]);
            entry[11] = type;
            entry[12] = ascii ? (byte)0xFF : (byte)0;
            entry[13] = (byte)granule;
            entry[14] = (byte)(lastBytes >> 8);
            entry[15] = (byte)lastBytes;
            granule += granules;
        }

        return image;
    }

    /// <summary>
    ///  Reads a disk's files, as Disk BASIC finds them through its directory and allocation table.
    /// </summary>
    /// <param name="image">The JVC image, with no header.</param>
    /// <returns>Each file's name, extension, type, ASCII flag and contents, in the directory's order.</returns>
    /// <exception cref="InvalidDataException">
    ///  The image is not 35 tracks, or a file's granules do not end or end in more than a granule's nine sectors.
    /// </exception>
    public static IReadOnlyList<(string Name, string Extension, byte Type, bool Ascii, byte[] Bytes)> Read(ReadOnlySpan<byte> image)
    {
        if (image.Length != Tracks * SectorsPerTrack * SectorSize)
        {
            throw new InvalidDataException("An RS-DOS disk here is 35 tracks of 18 256-byte sectors.");
        }

        ReadOnlySpan<byte> table = image.Slice(Offset(DirectoryTrack, AllocationSector), Granules);
        List<(string, string, byte, bool, byte[])> files = [];
        for (int index = 0; index < DirectorySectors * (SectorSize / EntrySize); index++)
        {
            ReadOnlySpan<byte> entry = image.Slice(Offset(DirectoryTrack, FirstDirectorySector) + (index * EntrySize), EntrySize);
            if (entry[0] == Free) { break; }
            if (entry[0] == 0) { continue; }
            List<byte> bytes = [];
            // Disk BASIC counts only the low byte of the last sector's bytes, 0 meaning a whole sector when the high
            // byte is set, and no bytes when the count is 0 (FCBREAD).
            int lastBytes = entry[15] != 0 ? entry[15] : entry[14] != 0 ? SectorSize : 0;
            for (int granule = entry[13], steps = 0; ; steps++)
            {
                if (granule >= Granules || steps == Granules)
                {
                    throw new InvalidDataException("A file's granules do not end.");
                }

                (int track, int sector) = Start(granule);
                byte next = table[granule];
                int sectors = next >= Last ? next - Last : GranuleSectors;
                if (sectors > GranuleSectors)
                {
                    throw new InvalidDataException($"Granule {granule}'s entry, ${next:X2}, ends a file in more sectors than a granule has.");
                }

                for (int part = 0; part < sectors; part++)
                {
                    bool final = next >= Last && part == sectors - 1;
                    bytes.AddRange(image.Slice(Offset(track, sector + part), final ? lastBytes : SectorSize).ToArray());
                }

                if (next >= Last) { break; }
                granule = next;
            }

            files.Add((
                Encoding.ASCII.GetString(entry[..8]).TrimEnd(' '),
                Encoding.ASCII.GetString(entry[8..11]).TrimEnd(' '),
                entry[11],
                entry[12] != 0,
                [.. bytes]));
        }

        return files;
    }

    /// <summary>
    ///  Gets a machine-language file as <c>LOADM</c> reads it, Disk BASIC's binary format: for each block of bytes, 0,
    ///  its length and its address, each high byte first, and its bytes; then <c>$FF</c>, 0 and the address
    ///  <c>EXEC</c> starts.
    /// </summary>
    /// <param name="blocks">The blocks: where each loads, and its bytes, at least one.</param>
    /// <param name="entry">The address EXEC starts.</param>
    /// <returns>The file's contents.</returns>
    public static byte[] MachineLanguageFile(IEnumerable<(int Address, ReadOnlyMemory<byte> Bytes)> blocks, int entry)
    {
        ArgumentNullException.ThrowIfNull(blocks);
        List<byte> file = [];
        foreach ((int address, ReadOnlyMemory<byte> bytes) in blocks)
        {
            if (bytes.IsEmpty) { continue; }
            file.AddRange([0, (byte)(bytes.Length >> 8), (byte)bytes.Length, (byte)(address >> 8), (byte)address]);
            file.AddRange(bytes.ToArray());
        }

        file.AddRange([0xFF, 0, 0, (byte)(entry >> 8), (byte)entry]);
        return [.. file];
    }

    /// <summary>
    ///  Gets whether a name is one the SDK puts on a disk: 1 to a length of capital letters and digits, from a letter, a
    ///  narrower rule than Disk BASIC's, which refuses a period, a slash, a colon, 0 and <c>$FF</c> in a name and more than
    ///  eight of its characters (GETFNAM), so
    ///  that every name a disk holds is one a program and a launch can type.
    /// </summary>
    /// <param name="name">The name or extension.</param>
    /// <param name="length">The most characters it may have: 8 for a name, 3 for an extension.</param>
    /// <returns>Whether it is such a name.</returns>
    public static bool IsName(string name, int length) =>
        name is { Length: > 0 }
            && name.Length <= length
            && char.IsAsciiLetterUpper(name[0])
            && name.All(character => char.IsAsciiLetterUpper(character) || char.IsAsciiDigit(character));

    /// <summary>
    ///  Gets a file's name as Disk BASIC's commands take it: the name, then a period and the extension when it has one.
    /// </summary>
    /// <param name="name">The name.</param>
    /// <param name="extension">The extension, or empty.</param>
    /// <returns>The name, such as <c>GAME.BIN</c> or <c>NOTES</c>.</returns>
    public static string Shown(string name, string extension) => extension.Length == 0 ? name : $"{name}.{extension}";

    // Where a granule starts: its track, past the directory's, and its first sector.
    private static (int Track, int Sector) Start(int granule)
    {
        int track = granule / 2;
        return (track >= DirectoryTrack ? track + 1 : track, ((granule % 2) * GranuleSectors) + 1);
    }

    // A sector's offset in the image.
    private static int Offset(int track, int sector) => ((track * SectorsPerTrack) + sector - 1) * SectorSize;
}
