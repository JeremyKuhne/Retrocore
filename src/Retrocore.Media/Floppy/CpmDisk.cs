// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text;

namespace Retrocore.Media.Floppy;

/// <summary>
///  The CP/M 2.2 file system on a disk image whose sectors are in order with no skew, as the Kaypro II's are: its
///  directory, and the files it lists in blocks.
/// </summary>
/// <remarks>
///  <para>
///   The disk's first <see cref="CpmGeometry.ReservedTracks"/> tracks hold the system; the blocks follow from there,
///   the directory from the first of them, and no file takes the blocks the allocation vector reserves
///   (<see cref="CpmGeometry.DirectoryBlocks"/>). A name's and type's top bits are attributes (read-only, system),
///   which a name is compared without. Each directory entry is 32 bytes: the user number (<c>$E5</c> for an unused
///   entry), the name, padded with spaces to eight, the type to three, the extent's number, two bytes CP/M keeps (the
///   second the extent's number over 32), the count of 128-byte records in the extent, and the extent's blocks, a byte
///   each while the disk has no more than 256. An extent holds 16K, sixteen 1K blocks (the only block size this writes), so a larger file has an entry for
///   each 16K. A file's last record is filled out with <c>$1A</c>, CP/M's end of text; an empty file is an entry with
///   no records and no blocks.
///  </para>
/// </remarks>
public static class CpmDisk
{
    /// <summary>
    ///  The size of a CP/M record.
    /// </summary>
    public const int RecordSize = 128;

    private const int EntrySize = 32;
    private const byte Unused = 0xE5;
    private const byte EndOfText = 0x1A;
    private const int ExtentBytes = 16 * 1024;

    /// <summary>
    ///  Adds a file to a disk as user 0, in the lowest free blocks and the first unused directory entries.
    /// </summary>
    /// <param name="image">The disk image, which is changed.</param>
    /// <param name="geometry">The disk's geometry.</param>
    /// <param name="name">The file's name: 1 to 8 capital letters and digits from a letter.</param>
    /// <param name="type">
    ///  Its type, such as <c>COM</c>: up to 3 capital letters and digits from a letter, or none.
    /// </param>
    /// <param name="bytes">Its contents.</param>
    /// <exception cref="ArgumentException">
    ///  The name or type is not one the SDK writes, or the disk has the file.
    /// </exception>
    /// <exception cref="InvalidOperationException">
    ///  The file does not fit, in the free blocks or the directory.
    /// </exception>
    public static void Add(byte[] image, CpmGeometry geometry, string name, string type, ReadOnlySpan<byte> bytes)
    {
        ArgumentNullException.ThrowIfNull(image);
        ArgumentNullException.ThrowIfNull(geometry);
        if (geometry.BlockSize != 1024 || geometry.Blocks > 256)
        {
            throw new ArgumentException("The SDK writes CP/M disks of 1K blocks, no more than 256 of them.");
        }

        if (!IsName(name, 8) || !(type.Length == 0 || IsName(type, 3)))
        {
            throw new ArgumentException($"'{name}.{type}' is not a name the SDK puts on a CP/M disk: 1 to 8 capital letters and digits from a letter, and a type of up to 3, also from a letter.");
        }

        byte[] padded = new byte[(bytes.Length + RecordSize - 1) / RecordSize * RecordSize];
        padded.AsSpan().Fill(EndOfText);
        bytes.CopyTo(padded);

        bool[] used = new bool[geometry.Blocks];
        for (int block = 0; block < geometry.DirectoryBlocks; block++) { used[block] = true; }
        List<int> free = [];
        for (int index = 0; index < geometry.DirectoryEntries; index++)
        {
            Span<byte> entry = Entry(image, geometry, index);
            if (entry[0] == Unused)
            {
                free.Add(index);
                continue;
            }

            if (entry[0] == 0 && Matches(entry, name, type))
            {
                throw new ArgumentException($"The disk already has {name}.{type}.");
            }

            foreach (byte block in entry[16..32])
            {
                if (block != 0 && block < used.Length) { used[block] = true; }
            }
        }

        int extents = Math.Max(1, (padded.Length + ExtentBytes - 1) / ExtentBytes);
        if (extents > free.Count)
        {
            throw new InvalidOperationException($"The disk's directory has no room for {name}.{type}.");
        }

        int needed = (padded.Length + geometry.BlockSize - 1) / geometry.BlockSize;
        List<int> blocks = [.. Enumerable.Range(0, used.Length).Where(block => !used[block]).Take(needed)];
        if (blocks.Count < needed)
        {
            throw new InvalidOperationException($"{name}.{type} does not fit on the disk: it needs {needed} blocks, and {blocks.Count} are free.");
        }

        for (int index = 0; index < blocks.Count; index++)
        {
            int offset = index * geometry.BlockSize;
            padded.AsSpan(offset, Math.Min(geometry.BlockSize, padded.Length - offset)).CopyTo(image.AsSpan(geometry.BlockOffset(blocks[index])));
        }

        int blocksPerExtent = ExtentBytes / geometry.BlockSize;
        for (int extent = 0; extent < extents; extent++)
        {
            Span<byte> entry = Entry(image, geometry, free[extent]);
            entry.Clear();
            Encoding.ASCII.GetBytes(name.PadRight(8)).CopyTo(entry[1..]);
            Encoding.ASCII.GetBytes(type.PadRight(3)).CopyTo(entry[9..]);
            entry[12] = (byte)(extent % 32);
            entry[14] = (byte)(extent / 32);
            int records = Math.Min(ExtentBytes, padded.Length - (extent * ExtentBytes)) / RecordSize;
            entry[15] = (byte)records;
            for (int slot = 0; slot < blocksPerExtent && (extent * blocksPerExtent) + slot < blocks.Count; slot++)
            {
                entry[16 + slot] = (byte)blocks[(extent * blocksPerExtent) + slot];
            }
        }
    }

    /// <summary>
    ///  Reads a user 0 file from a disk, its extents in order.
    /// </summary>
    /// <param name="image">The disk image.</param>
    /// <param name="geometry">The disk's geometry.</param>
    /// <param name="name">The file's name.</param>
    /// <param name="type">Its type.</param>
    /// <returns>Its records, the last filled out as the disk holds it.</returns>
    /// <exception cref="FileNotFoundException">The disk has no such file.</exception>
    public static byte[] Read(byte[] image, CpmGeometry geometry, string name, string type)
    {
        ArgumentNullException.ThrowIfNull(image);
        ArgumentNullException.ThrowIfNull(geometry);
        List<(int Extent, byte[] Bytes)> extents = [];
        for (int index = 0; index < geometry.DirectoryEntries; index++)
        {
            Span<byte> entry = Entry(image, geometry, index);
            if (entry[0] != 0 || !Matches(entry, name, type)) { continue; }

            List<byte> bytes = [];
            int records = entry[15];
            foreach (byte block in entry[16..32])
            {
                if (block == 0 || records <= 0) { break; }
                int take = Math.Min(records * RecordSize, geometry.BlockSize);
                bytes.AddRange(image.AsSpan(geometry.BlockOffset(block), take).ToArray());
                records -= take / RecordSize;
            }

            extents.Add(((entry[14] * 32) + entry[12], [.. bytes]));
        }

        return extents.Count == 0
            ? throw new FileNotFoundException($"The disk has no {name}.{type}.", $"{name}.{type}")
            : [.. extents.OrderBy(extent => extent.Extent).SelectMany(extent => extent.Bytes)];
    }

    /// <summary>
    ///  Gets whether a name is one the SDK puts on a disk: 1 to a length of capital letters and digits, from a letter, a
    ///  narrower rule than CP/M's own, so that every name a disk holds is one a program and a launch can type.
    /// </summary>
    /// <param name="name">The name or type.</param>
    /// <param name="length">The most characters it may have: 8 for a name, 3 for a type.</param>
    /// <returns>Whether it is such a name.</returns>
    public static bool IsName(string name, int length) =>
        name is { Length: > 0 }
            && name.Length <= length
            && char.IsAsciiLetterUpper(name[0])
            && name.All(character => char.IsAsciiLetterUpper(character) || char.IsAsciiDigit(character));

    // Whether an entry names a file, its name's and type's attribute bits left out.
    private static bool Matches(ReadOnlySpan<byte> entry, string name, string type)
    {
        Span<byte> text = stackalloc byte[11];
        for (int index = 0; index < text.Length; index++) { text[index] = (byte)(entry[1 + index] & 0x7F); }
        return Encoding.ASCII.GetString(text[..8]).TrimEnd() == name && Encoding.ASCII.GetString(text[8..]).TrimEnd() == type;
    }

    private static Span<byte> Entry(byte[] image, CpmGeometry geometry, int index) =>
        image.AsSpan(geometry.BlockOffset(0) + (index * EntrySize), EntrySize);
}
