// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text;

namespace Retrocore.Media;

/// <summary>
///  An Apple Pascal volume, read-only: the UCSD file system the Apple II's Pascal uses, from a 140K disk image in
///  either sector order.
/// </summary>
/// <remarks>
///  <para>
///   Blocks 2-5 hold the directory: a 26-byte volume header (the volume's name, its size in blocks and how many files
///   it has), then a 26-byte entry for each file, in block order. A file is a run of blocks, from its first block to
///   the one before the next, and its entry says how much of the last block it uses. The Apple III's Pascal keeps its
///   files on SOS volumes instead (<see cref="SosVolume"/>).
///  </para>
/// </remarks>
public sealed class PascalVolume
{
    private const int DirectoryBlock = 2;
    private const int DirectoryBlocks = 4;
    private const int EntrySize = 26;

    private readonly byte[] _image;
    private readonly bool _proDosOrder;

    private PascalVolume(byte[] image, bool proDosOrder)
    {
        _image = image;
        _proDosOrder = proDosOrder;
        byte[] directory = new byte[DirectoryBlocks * DiskBlocks.BlockSize];
        for (int block = 0; block < DirectoryBlocks; block++)
        {
            Block(DirectoryBlock + block).CopyTo(directory, block * DiskBlocks.BlockSize);
        }

        if (!IsHeader(directory))
        {
            throw new InvalidDataException("The image has no Apple Pascal directory at block 2.");
        }

        Name = Encoding.ASCII.GetString(directory, 7, directory[6]);
        Blocks = Word(directory, 14);
        int count = Math.Min(Word(directory, 16), (directory.Length / EntrySize) - 1);
        List<PascalFileEntry> files = new(count);
        for (int index = 1; index <= count; index++)
        {
            int offset = index * EntrySize;
            int length = Math.Min((int)directory[offset + 6], 15);
            files.Add(new PascalFileEntry(
                Encoding.ASCII.GetString(directory, offset + 7, length),
                Word(directory, offset),
                Word(directory, offset + 2),
                (PascalFileKind)(directory[offset + 4] & 0xF),
                Word(directory, offset + 22),
                Date(Word(directory, offset + 24))));
        }

        Files = files;
    }

    /// <summary>
    ///  Gets the volume's name, such as <c>APPLE1</c>.
    /// </summary>
    public string Name { get; }

    /// <summary>
    ///  Gets the volume's size in blocks.
    /// </summary>
    public int Blocks { get; }

    /// <summary>
    ///  Gets the files, in directory order.
    /// </summary>
    public IReadOnlyList<PascalFileEntry> Files { get; }

    /// <summary>
    ///  Reads a volume from a 140K disk image.
    /// </summary>
    /// <param name="image">The image.</param>
    /// <param name="proDosOrder">
    ///  Whether its sectors are in ProDOS order (<c>.po</c>) rather than DOS order (<c>.dsk</c>).
    /// </param>
    /// <returns>The volume.</returns>
    /// <exception cref="InvalidDataException">The image is not 140K or holds no Pascal volume.</exception>
    public static PascalVolume Read(byte[] image, bool proDosOrder)
    {
        ArgumentNullException.ThrowIfNull(image);
        return image.Length != DiskBlocks.DiskSize
            ? throw new InvalidDataException($"A 140K disk image is {DiskBlocks.DiskSize} bytes; this one is {image.Length}.")
            : new PascalVolume(image, proDosOrder);
    }

    /// <summary>
    ///  Says whether a 140K image holds a Pascal volume.
    /// </summary>
    /// <param name="image">The image.</param>
    /// <param name="proDosOrder">Whether its sectors are in ProDOS order.</param>
    /// <returns>True when block 2 starts a Pascal volume header.</returns>
    public static bool IsPascalVolume(byte[] image, bool proDosOrder)
    {
        ArgumentNullException.ThrowIfNull(image);
        return image.Length == DiskBlocks.DiskSize && IsHeader(DiskBlocks.Read(image, proDosOrder, DirectoryBlock));
    }

    /// <summary>
    ///  Reads a file.
    /// </summary>
    /// <param name="name">Its name, in any case.</param>
    /// <returns>Its contents, as long as the directory says it is.</returns>
    /// <exception cref="FileNotFoundException">The volume has no such file.</exception>
    public byte[] ReadFile(string name)
    {
        PascalFileEntry entry = Files.FirstOrDefault(file => string.Equals(file.Name, name, StringComparison.OrdinalIgnoreCase))
            ?? throw new FileNotFoundException($"The volume {Name}: has no file {name}.", name);

        return ReadFile(entry);
    }

    /// <summary>
    ///  Reads a file.
    /// </summary>
    /// <param name="entry">Its directory entry.</param>
    /// <returns>Its contents.</returns>
    /// <exception cref="InvalidDataException">The entry's blocks are outside the volume.</exception>
    public byte[] ReadFile(PascalFileEntry entry)
    {
        ArgumentNullException.ThrowIfNull(entry);
        if (entry.NextBlock > DiskBlocks.DiskSize / DiskBlocks.BlockSize || entry.FirstBlock > entry.NextBlock)
        {
            throw new InvalidDataException($"{entry.Name}'s blocks are outside the volume.");
        }

        byte[] data = new byte[entry.Length];
        for (int block = entry.FirstBlock; block < entry.NextBlock; block++)
        {
            int offset = (block - entry.FirstBlock) * DiskBlocks.BlockSize;
            Block(block).AsSpan(0, Math.Min(DiskBlocks.BlockSize, data.Length - offset)).CopyTo(data.AsSpan(offset));
        }

        return data;
    }

    /// <summary>
    ///  Reads a block.
    /// </summary>
    /// <param name="block">The block number, 0-279.</param>
    /// <returns>Its 512 bytes.</returns>
    public byte[] Block(int block) => DiskBlocks.Read(_image, _proDosOrder, block);

    // A volume header starts at block 0, ends its directory at block 6, and has a name of 1-7 characters.
    private static bool IsHeader(ReadOnlySpan<byte> directory) =>
        Word(directory, 0) == 0 && Word(directory, 2) == DirectoryBlock + DirectoryBlocks && directory[6] is >= 1 and <= 7;

    // Month in bits 0-3, day in 4-8, the year after 1900 in 9-15.
    private static DateOnly? Date(int value)
    {
        int month = value & 0xF;
        int day = (value >> 4) & 0x1F;
        int year = 1900 + (value >> 9);
        return month is >= 1 and <= 12 && day >= 1 && day <= DateTime.DaysInMonth(year, month) ? new DateOnly(year, month, day) : null;
    }

    private static int Word(ReadOnlySpan<byte> data, int offset) => data[offset] | (data[offset + 1] << 8);
}
