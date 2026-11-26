// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text;
using Retrocore.Media.Floppy;

namespace Retrocore.Media.Acorn;

/// <summary>
///  A side of an Acorn DFS disk as an <c>.ssd</c> image, whose catalogue can be read and changed: files added and
///  removed, the title and the boot option set, and <c>$.!BOOT</c> written, as DNFS 1.20 changes them.
/// </summary>
/// <remarks>
///  <para>
///   The catalogue is sectors 0 and 1 (the Disc Filing System User Guide's technical information, and the SDK's
///   <c>Dnfs/DfsCatalogue.asm</c>). Sector 0 holds the title's first eight characters, then each file's name (seven
///   characters padded with spaces) and directory, bit 7 of which locks the file. Sector 1 holds the title's last four
///   characters, the sequence number (counting in decimal as the catalogue is written), eight times the number of
///   files, the boot option (bits 4-5 of byte 6) and the disk's sectors (bits 0-1 of byte 6 and byte 7), then each
///   file's load and execution addresses and length (two bytes each, low first), a byte of their bits 16-17 and of
///   the start sector's bits 8-9, and the start sector's low byte. There is room for 31 files.
///  </para>
///  <para>
///   Files are kept in order of start sector, the highest first. A file goes where <c>SAVE</c> would put it: in the
///   first gap that holds it, walking up from sector 2, and a file of the same name is deleted first. A removed file's
///   sectors are left as they were. Entries move in the catalogue as raw bytes, as the DFS moves them, so the files a
///   change does not touch keep their bytes, and the bytes past the last entry stay as the DFS would leave them. An
///   image read and written back unchanged comes back byte for byte.
///  </para>
/// </remarks>
public sealed class AcornDfsDisk
{
    /// <summary>
    ///  The most files a catalogue holds.
    /// </summary>
    public const int MaximumFiles = 31;

    /// <summary>
    ///  The most characters a title holds.
    /// </summary>
    public const int MaximumTitleLength = 12;

    /// <summary>
    ///  The boot file's name, in directory <c>$</c>.
    /// </summary>
    public const string BootFileName = "!BOOT";

    private const int SectorSize = AcornDiskImage.SectorSize;
    private const int TrackSize = AcornDiskImage.TrackSize;
    private const int FirstFileSector = 2;

    // Sector 1's bytes, from the image's start.
    private const int Sequence = SectorSize + 4;
    private const int FileCount = SectorSize + 5;
    private const int OptionAndSize = SectorSize + 6;
    private const int SizeLow = SectorSize + 7;

    private readonly byte[] _image;
    private readonly List<AcornDfsEntry> _entries;

    private AcornDfsDisk(byte[] image, List<AcornDfsEntry> entries, int sectors)
    {
        _image = image;
        _entries = entries;
        Sectors = sectors;
    }

    /// <summary>
    ///  Gets the disk's sectors, as its catalogue gives them.
    /// </summary>
    public int Sectors { get; }

    /// <summary>
    ///  Gets the files, in the catalogue's order: the highest start sector first.
    /// </summary>
    public IReadOnlyList<AcornDfsEntry> Entries => _entries;

    /// <summary>
    ///  Gets the sectors no file uses.
    /// </summary>
    public int FreeSectors => Sectors - FirstFileSector - _entries.Sum(entry => SectorsFor(entry.File.Data.Length));

    /// <summary>
    ///  Gets the catalogue's sequence number, which counts in decimal (BCD) each time the catalogue changes.
    /// </summary>
    public byte SequenceNumber => _image[Sequence];

    /// <summary>
    ///  Gets or sets the title: up to 12 printable characters, which <c>*TITLE</c> pads with spaces.
    /// </summary>
    /// <exception cref="ArgumentException">
    ///  The title is longer or holds a character that is not printable ASCII.
    /// </exception>
    public string Title
    {
        get
        {
            Span<char> title = stackalloc char[MaximumTitleLength];
            int length = 0;
            while (length < MaximumTitleLength && _image[TitleOffset(length)] != 0)
            {
                title[length] = (char)(_image[TitleOffset(length)] & 0x7F);
                length++;
            }

            return new string(title[..length]).TrimEnd(' ');
        }
        set
        {
            ArgumentNullException.ThrowIfNull(value);
            if (value.Length > MaximumTitleLength || value.Any(character => character is < ' ' or > '~'))
            {
                throw new ArgumentException(
                    $"'{value}' is not a DFS title: up to 12 printable characters.",
                    nameof(value));
            }

            for (int index = 0; index < MaximumTitleLength; index++)
            {
                _image[TitleOffset(index)] = index < value.Length ? (byte)value[index] : (byte)' ';
            }

            WriteCatalogue();
        }
    }

    /// <summary>
    ///  Gets or sets what SHIFT-BREAK does with <c>$.!BOOT</c>, as <c>*OPT 4</c> sets it.
    /// </summary>
    /// <exception cref="ArgumentOutOfRangeException">The option is not one of the four.</exception>
    public AcornBootOption BootOption
    {
        get => (AcornBootOption)((_image[OptionAndSize] >> 4) & 3);
        set
        {
            if (value is < AcornBootOption.None or > AcornBootOption.Exec)
            {
                throw new ArgumentOutOfRangeException(nameof(value), "The boot option is 0-3.");
            }

            _image[OptionAndSize] = (byte)((_image[OptionAndSize] & ~0x30) | ((int)value << 4));
            WriteCatalogue();
        }
    }

    /// <summary>
    ///  Creates a disk as <see cref="AcornDiskImage.Blank"/> formats one: every byte <c>$E5</c> but an empty
    ///  catalogue with no title.
    /// </summary>
    /// <param name="tracks">40 or 80.</param>
    /// <returns>The disk.</returns>
    /// <exception cref="ArgumentOutOfRangeException">The tracks are neither.</exception>
    public static AcornDfsDisk Create(int tracks = 80) =>
        Read(AcornDiskImage.Encode(AcornDiskImage.Blank(tracks), doubleSided: false).Bytes);

    /// <summary>
    ///  Reads an <c>.ssd</c> image, which may stop short of its last tracks; the missing sectors read as zeros.
    /// </summary>
    /// <param name="image">The image.</param>
    /// <returns>The disk.</returns>
    /// <exception cref="InvalidDataException">
    ///  The image is shorter than the catalogue or longer than 80 tracks, or its catalogue is broken: a size of fewer
    ///  than 2 or more than 800 sectors, more than 31 files, or a file outside the disk.
    /// </exception>
    public static AcornDfsDisk Read(ReadOnlySpan<byte> image)
    {
        if (image.Length < 2 * SectorSize)
        {
            throw new InvalidDataException("A DFS image starts with its catalogue's two sectors.");
        }

        if (image.Length > 80 * TrackSize) { throw new InvalidDataException("An .ssd image holds at most 80 tracks."); }

        int sectors = ((image[OptionAndSize] & 3) << 8) | image[SizeLow];
        if (sectors is < FirstFileSector or > 80 * AcornDiskImage.SectorsPerTrack)
        {
            throw new InvalidDataException($"The catalogue gives the disk {sectors} sectors; a DFS disk has 2-800.");
        }

        int count = image[FileCount];
        if ((count & 7) != 0)
        {
            throw new InvalidDataException($"The catalogue's file count, &{count:X2}, is not eight times 0-31.");
        }

        int length = Math.Max(RoundToTrack(image.Length), RoundToTrack(sectors * SectorSize));
        byte[] bytes = new byte[length];
        image.CopyTo(bytes);

        List<AcornDfsEntry> entries = [];
        Span<char> name = stackalloc char[AcornDfsFile.MaximumNameLength];
        for (int index = 0; index < count / 8; index++)
        {
            int names = 8 + (index * 8);
            int info = SectorSize + names;
            for (int at = 0; at < name.Length; at++) { name[at] = (char)(bytes[names + at] & 0x7F); }

            int mixed = bytes[info + 6];
            int fileLength = (((mixed >> 4) & 3) << 16) | (bytes[info + 5] << 8) | bytes[info + 4];
            int start = ((mixed & 3) << 8) | bytes[info + 7];
            int end = start + SectorsFor(fileLength);
            if (start < FirstFileSector || end > sectors)
            {
                throw new InvalidDataException(
                    $"Catalogue entry {index} takes sectors {start}-{end - 1}, outside the disk's 2-{sectors - 1}.");
            }

            AcornDfsFile file = new(
                (char)(bytes[names + 7] & 0x7F),
                name.ToString().TrimEnd(' ', '\0'),
                Address(bytes[info], bytes[info + 1], mixed >> 2),
                Address(bytes[info + 2], bytes[info + 3], mixed >> 6),
                bytes.AsSpan(start * SectorSize, fileLength).ToArray(),
                (bytes[names + 7] & 0x80) != 0);

            entries.Add(new(file, start));
        }

        return new(bytes, entries, sectors);
    }

    /// <summary>
    ///  Adds a file where <c>SAVE</c> would put it, replacing an unlocked file of the same directory and name; letters
    ///  match in either case.
    /// </summary>
    /// <param name="file">The file.</param>
    /// <returns>Its entry, with the sector it starts at.</returns>
    /// <exception cref="ArgumentException">
    ///  The file's directory, name, an address or its length is not one a DFS keeps.
    /// </exception>
    /// <exception cref="InvalidOperationException">
    ///  The file it replaces is locked, the catalogue holds 31 files, or no gap on the disk holds the file. The disk is
    ///  left as it was.
    /// </exception>
    public AcornDfsEntry Add(AcornDfsFile file)
    {
        ArgumentNullException.ThrowIfNull(file);
        file.Validate();

        int existing = IndexOf(file.Directory, file.Name);
        if (existing >= 0 && _entries[existing].File.Locked)
        {
            throw new InvalidOperationException($"{_entries[existing].File.FullName} is locked.");
        }

        List<AcornDfsEntry> others = [.. _entries];
        if (existing >= 0) { others.RemoveAt(existing); }
        if (others.Count == MaximumFiles)
        {
            throw new InvalidOperationException($"The catalogue is full: it holds {MaximumFiles} files.");
        }

        // From the gap between sector 2 and the last file up to the gap after the first file, the first that holds
        // the file; the new entry goes at the gap's place in the list.
        int needed = SectorsFor(file.Data.Length);
        for (int slot = others.Count; slot >= 0; slot--)
        {
            int start = slot == others.Count
                ? FirstFileSector
                : others[slot].StartSector + SectorsFor(others[slot].File.Data.Length);

            int limit = slot == 0 ? Sectors : others[slot - 1].StartSector;
            if (limit - start < needed) { continue; }

            AcornDfsEntry entry = new(file with { Data = [.. file.Data] }, start);
            if (existing >= 0) { DeleteEntry(existing); }
            InsertEntry(slot, entry);

            Span<byte> sectors = _image.AsSpan(start * SectorSize, needed * SectorSize);
            sectors.Clear();
            file.Data.CopyTo(sectors);
            WriteCatalogue();
            return entry;
        }

        int free = Sectors - FirstFileSector - others.Sum(other => SectorsFor(other.File.Data.Length));
        throw new InvalidOperationException(
            $"The disk is full: no gap holds {file.FullName}'s {needed} sectors ({free} are free in all).");
    }

    /// <summary>
    ///  Adds the files in turn.
    /// </summary>
    /// <param name="files">The files.</param>
    /// <exception cref="ArgumentException">A file is not one a DFS keeps.</exception>
    /// <exception cref="InvalidOperationException">
    ///  A file cannot be added, as <see cref="Add(AcornDfsFile)"/> says; the files before it are kept.
    /// </exception>
    public void AddRange(IEnumerable<AcornDfsFile> files)
    {
        ArgumentNullException.ThrowIfNull(files);
        foreach (AcornDfsFile file in files) { Add(file); }
    }

    /// <summary>
    ///  Writes <c>$.!BOOT</c> as text, each line ending in a carriage return as <c>*BUILD</c> ends them, with zero
    ///  addresses, and sets the boot option to <see cref="AcornBootOption.Exec"/>, so SHIFT-BREAK types the lines as
    ///  commands: <c>*RUN ADVENT</c>, say.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   The file is placed as <see cref="Add(AcornDfsFile)"/> places any file, by its length, replacing an existing
    ///   one. <c>*BUILD</c> opens it with OSFIND instead, which keeps an existing file's place and addresses, or makes
    ///   a new one with zero addresses and 64 sectors long until it is closed; so on a disk with gaps, or with a
    ///   <c>!BOOT</c> already, the two can differ.
    ///  </para>
    /// </remarks>
    /// <param name="lines">The lines.</param>
    /// <returns>The boot file's entry.</returns>
    /// <exception cref="ArgumentException">A line holds a character that is not printable ASCII.</exception>
    /// <exception cref="InvalidOperationException">
    ///  The file cannot be added, as <see cref="Add(AcornDfsFile)"/> says.
    /// </exception>
    public AcornDfsEntry AddBootFile(params IEnumerable<string> lines)
    {
        ArgumentNullException.ThrowIfNull(lines);
        List<byte> text = [];
        foreach (string line in lines)
        {
            ArgumentNullException.ThrowIfNull(line, nameof(lines));
            if (line.Any(character => character is < ' ' or > '~'))
            {
                throw new ArgumentException($"'{line}' holds a character that is not printable ASCII.", nameof(lines));
            }

            text.AddRange(Encoding.ASCII.GetBytes(line));
            text.Add(0x0D);
        }

        // A file OSFIND makes, as *BUILD makes a new one, has load and execution addresses of zero.
        AcornDfsEntry entry = Add(new('$', BootFileName, 0, 0, [.. text]));
        BootOption = AcornBootOption.Exec;
        return entry;
    }

    /// <summary>
    ///  Finds a file; letters match in either case.
    /// </summary>
    /// <param name="directory">The directory.</param>
    /// <param name="name">The name.</param>
    /// <returns>The file's entry, or null if there is none.</returns>
    public AcornDfsEntry? Find(char directory, string name)
    {
        ArgumentNullException.ThrowIfNull(name);
        int index = IndexOf(directory, name);
        return index < 0 ? null : _entries[index];
    }

    /// <summary>
    ///  Deletes a file as <c>*DELETE</c> does, leaving its sectors as they are.
    /// </summary>
    /// <param name="directory">The directory.</param>
    /// <param name="name">The name; letters match in either case.</param>
    /// <returns>Whether there was such a file.</returns>
    /// <exception cref="InvalidOperationException">The file is locked.</exception>
    public bool Remove(char directory, string name)
    {
        ArgumentNullException.ThrowIfNull(name);
        int index = IndexOf(directory, name);
        if (index < 0) { return false; }
        if (_entries[index].File.Locked)
        {
            throw new InvalidOperationException($"{_entries[index].File.FullName} is locked.");
        }

        DeleteEntry(index);
        WriteCatalogue();
        return true;
    }

    /// <summary>
    ///  Gets the disk as an <c>.ssd</c> image: whole tracks, as many as the catalogue's sectors or the image read
    ///  filled, whichever is more.
    /// </summary>
    /// <returns>The image.</returns>
    public byte[] ToImage() => [.. _image];

    /// <summary>
    ///  Gets the disk as a floppy disk to insert in a drive.
    /// </summary>
    /// <returns>The disk.</returns>
    public FloppyDisk ToDisk() => AcornDiskImage.Read(_image, doubleSided: false);

    // Rounds a size in bytes up to whole tracks: a disk of 400 sectors is 40 tracks.
    private static int RoundToTrack(int bytes) => (bytes + TrackSize - 1) / TrackSize * TrackSize;

    private static int SectorsFor(int length) => (length + SectorSize - 1) / SectorSize;

    // The title's first eight characters begin sector 0, the last four sector 1.
    private static int TitleOffset(int index) => index < 8 ? index : SectorSize + index - 8;

    // Bits 16-17 of 3 stand for &FFFF, the I/O processor's memory.
    private static uint Address(byte low, byte middle, int high)
    {
        uint address = (uint)((middle << 8) | low);
        return (high & 3) == 3 ? address | 0xFFFF0000 : address | ((uint)(high & 3) << 16);
    }

    // Letters match in either case, as the DFS's searches do.
    private static bool SameCharacter(char left, char right) =>
        char.ToUpperInvariant(left) == char.ToUpperInvariant(right);

    private int IndexOf(char directory, string name) => _entries.FindIndex(entry =>
        SameCharacter(entry.File.Directory, directory)
            && entry.File.Name.Length == name.Length
            && entry.File.Name.Zip(name).All(pair => SameCharacter(pair.First, pair.Second)));

    // Removes an entry as the DFS's DELETE_ENTRY does, moving the bytes of the entries after it down a place in both
    // sectors, raw, so the slot that falls out of use takes the bytes past the last entry. With 31 files those are
    // past sector 1, in the DFS's workspace, so the last slot's information is left as it was.
    private void DeleteEntry(int index)
    {
        int count = _entries.Count * 8;
        int from = index * 8;
        _image.AsSpan(16 + from, count - from).CopyTo(_image.AsSpan(8 + from));
        int information = Math.Min(count - from, (2 * SectorSize) - (SectorSize + 16 + from));
        _image.AsSpan(SectorSize + 16 + from, information).CopyTo(_image.AsSpan(SectorSize + 8 + from));
        _entries.RemoveAt(index);
    }

    // Inserts an entry as the DFS's MAKE_CATALOGUE_ENTRY does, moving the bytes of the entries from its place on up a
    // place in both sectors, raw, and writing its own.
    private void InsertEntry(int index, AcornDfsEntry entry)
    {
        int count = _entries.Count * 8;
        int from = index * 8;
        _image.AsSpan(8 + from, count - from).CopyTo(_image.AsSpan(16 + from));
        _image.AsSpan(SectorSize + 8 + from, count - from).CopyTo(_image.AsSpan(SectorSize + 16 + from));
        _entries.Insert(index, entry);

        AcornDfsFile file = entry.File;
        int names = 8 + from;
        int info = SectorSize + names;
        for (int at = 0; at < AcornDfsFile.MaximumNameLength; at++)
        {
            _image[names + at] = at < file.Name.Length ? (byte)file.Name[at] : (byte)' ';
        }

        _image[names + 7] = (byte)(file.Directory | (file.Locked ? 0x80 : 0));
        int length = file.Data.Length;
        _image[info] = (byte)file.LoadAddress;
        _image[info + 1] = (byte)(file.LoadAddress >> 8);
        _image[info + 2] = (byte)file.ExecutionAddress;
        _image[info + 3] = (byte)(file.ExecutionAddress >> 8);
        _image[info + 4] = (byte)length;
        _image[info + 5] = (byte)(length >> 8);
        _image[info + 6] = (byte)((((file.ExecutionAddress >> 16) & 3) << 6)
                | (((uint)length >> 16 & 3) << 4)
                | (((file.LoadAddress >> 16) & 3) << 2)
                | (uint)((entry.StartSector >> 8) & 3));

        _image[info + 7] = (byte)entry.StartSector;
    }

    // Writes the file count and the next sequence number; the DFS's WRITE_CATALOGUE then writes both sectors whole.
    private void WriteCatalogue()
    {
        _image[FileCount] = (byte)(_entries.Count * 8);

        // The sequence number counts in decimal, as the DFS adds one in the 6502's decimal mode: for a BCD number,
        // 99 wraps to 00.
        int sequence = _image[Sequence];
        int units = (sequence & 0x0F) + 1;
        int tens = sequence >> 4;
        if (units > 9) { units = 0; tens++; }
        if (tens > 9) { tens = 0; }
        _image[Sequence] = (byte)((tens << 4) | units);
    }
}
