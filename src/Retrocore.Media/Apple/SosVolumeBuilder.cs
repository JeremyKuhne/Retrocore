// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text;

namespace Retrocore.Media;

/// <summary>
///  Builds a 140K SOS volume from files, as Apple's disks lay one out: the boot loader in blocks 0 and 1, the volume
///  directory in blocks 2-5, the free-block bitmap in block 6, and the files after it, each in order.
/// </summary>
/// <remarks>
///  <para>
///   A file of one block or less is a seedling, its one data block; a larger one a sapling, an index block naming up
///   to 256 data blocks by their low bytes in its first half and high bytes in its second. The bitmap marks a free
///   block with a 1, from the high bit of its first byte. The directory has room for 51 files.
///  </para>
/// </remarks>
public sealed class SosVolumeBuilder
{
    private const int BlockSize = DiskBlocks.BlockSize;
    private const int TotalBlocks = DiskBlocks.DiskSize / BlockSize;
    private const int Directory = 2;
    private const int DirectoryBlocks = 4;
    private const int Bitmap = Directory + DirectoryBlocks;
    private const int EntryLength = 0x27;
    private const int EntriesPerBlock = 0x0D;

    private readonly string _name;
    private readonly byte[] _boot = new byte[2 * BlockSize];
    private readonly List<(string Name, int FileType, int AuxType, byte[] Data)> _files = [];

    /// <summary>
    ///  Starts a volume.
    /// </summary>
    /// <param name="name">
    ///  Its name, without the slash: 1-15 letters, digits and periods, starting with a letter.
    /// </param>
    /// <exception cref="ArgumentException">The name is not a SOS name.</exception>
    public SosVolumeBuilder(string name) => _name = Name(name);

    /// <summary>
    ///  Gets the files added so far.
    /// </summary>
    public int Count => _files.Count;

    /// <summary>
    ///  Gets the blocks the volume uses so far, with its boot blocks, directory and bitmap.
    /// </summary>
    public int BlocksUsed => Bitmap + 1 + _files.Sum(file => Blocks(file.Data.Length));

    /// <summary>
    ///  Copies the boot loader, blocks 0 and 1, from another volume, so the disk boots SOS.
    /// </summary>
    /// <param name="source">A volume that boots.</param>
    public void BootFrom(SosVolume source)
    {
        ArgumentNullException.ThrowIfNull(source);
        source.Block(0).CopyTo(_boot, 0);
        source.Block(1).CopyTo(_boot, BlockSize);
    }

    /// <summary>
    ///  Adds a file.
    /// </summary>
    /// <param name="name">Its name: 1-15 letters, digits and periods, starting with a letter.</param>
    /// <param name="fileType">Its SOS file type, such as <c>$0C</c> for a SOS system file.</param>
    /// <param name="auxType">Its auxiliary type.</param>
    /// <param name="data">Its contents.</param>
    /// <exception cref="ArgumentException">
    ///  The name is not a SOS name or is taken, the type is not a byte, or the file needs more than a sapling's 256
    ///  blocks.
    /// </exception>
    /// <exception cref="InvalidOperationException">The directory or the volume is full.</exception>
    public void Add(string name, int fileType, int auxType, ReadOnlySpan<byte> data)
    {
        name = Name(name);
        ArgumentOutOfRangeException.ThrowIfGreaterThan((uint)fileType, 0xFFu, nameof(fileType));
        ArgumentOutOfRangeException.ThrowIfGreaterThan((uint)auxType, 0xFFFFu, nameof(auxType));
        if (_files.Any(file => file.Name == name))
        {
            throw new ArgumentException($"The volume already has {name}.", nameof(name));
        }

        if (data.Length > 256 * BlockSize)
        {
            throw new ArgumentException($"{name} is more than 256 blocks.", nameof(data));
        }

        if (_files.Count == (DirectoryBlocks * EntriesPerBlock) - 1)
        {
            throw new InvalidOperationException($"The volume directory of /{_name} is full.");
        }

        if (BlocksUsed + Blocks(data.Length) > TotalBlocks)
        {
            throw new InvalidOperationException($"/{_name} has no room for {name}.");
        }

        _files.Add((name, fileType, auxType, data.ToArray()));
    }

    /// <summary>
    ///  Copies a file from another volume, with its type and auxiliary type.
    /// </summary>
    /// <param name="source">The volume.</param>
    /// <param name="name">The file's name there, which it keeps.</param>
    /// <exception cref="FileNotFoundException">The volume has no such file.</exception>
    public void Add(SosVolume source, string name)
    {
        ArgumentNullException.ThrowIfNull(source);
        SosFileEntry entry = source.Files.FirstOrDefault(file => string.Equals(file.Name, name, StringComparison.OrdinalIgnoreCase))
            ?? throw new FileNotFoundException($"The volume /{source.Name} has no file {name}.", name);

        Add(entry.Name, entry.FileType, entry.AuxType, source.ReadFile(entry.Name));
    }

    /// <summary>
    ///  Builds the volume's disk image.
    /// </summary>
    /// <param name="proDosOrder">
    ///  Whether to write its sectors in ProDOS order (<c>.po</c>) rather than DOS order (<c>.dsk</c>).
    /// </param>
    /// <returns>The 143,360-byte image.</returns>
    public byte[] Build(bool proDosOrder)
    {
        byte[][] blocks = new byte[TotalBlocks][];
        for (int block = 0; block < TotalBlocks; block++) { blocks[block] = new byte[BlockSize]; }

        _boot.AsSpan(0, BlockSize).CopyTo(blocks[0]);
        _boot.AsSpan(BlockSize).CopyTo(blocks[1]);

        // The directory's blocks link to each other, back and forward.
        for (int block = Directory; block < Bitmap; block++)
        {
            Word(blocks[block], 0, block == Directory ? 0 : block - 1);
            Word(blocks[block], 2, block == Bitmap - 1 ? 0 : block + 1);
        }

        byte[] header = blocks[Directory];
        WriteName(header, 4, 0xF, _name);
        header[4 + 0x1E] = 0xC3;
        header[4 + 0x1F] = EntryLength;
        header[4 + 0x20] = EntriesPerBlock;
        Word(header, 4 + 0x21, _files.Count);
        Word(header, 4 + 0x23, Bitmap);
        Word(header, 4 + 0x25, TotalBlocks);

        int next = Bitmap + 1;
        for (int index = 0; index < _files.Count; index++)
        {
            (string name, int fileType, int auxType, byte[] data) = _files[index];
            int dataBlocks = Math.Max(1, (data.Length + BlockSize - 1) / BlockSize);
            bool sapling = data.Length > BlockSize;
            int key = next++;
            if (sapling)
            {
                for (int part = 0; part < dataBlocks; part++)
                {
                    int block = next++;
                    blocks[key][part] = (byte)block;
                    blocks[key][256 + part] = (byte)(block >> 8);
                    Copy(data, part, blocks[block]);
                }
            }
            else
            {
                Copy(data, 0, blocks[key]);
            }

            // The header entry is the first of the first block's thirteen.
            int slot = index + 1;
            byte[] directory = blocks[Directory + (slot / EntriesPerBlock)];
            int entry = 4 + ((slot % EntriesPerBlock) * EntryLength);
            WriteName(directory, entry, sapling ? 2 : 1, name);
            directory[entry + 0x10] = (byte)fileType;
            Word(directory, entry + 0x11, key);
            Word(directory, entry + 0x13, Blocks(data.Length));
            Word(directory, entry + 0x15, data.Length);
            directory[entry + 0x17] = (byte)(data.Length >> 16);
            directory[entry + 0x1E] = 0xE3;
            Word(directory, entry + 0x1F, auxType);
            Word(directory, entry + 0x25, Directory);
        }

        // The bitmap: a 1 for each free block.
        for (int block = next; block < TotalBlocks; block++)
        {
            blocks[Bitmap][block / 8] |= (byte)(0x80 >> (block % 8));
        }

        byte[] image = new byte[DiskBlocks.DiskSize];
        for (int block = 0; block < TotalBlocks; block++)
        {
            DiskBlocks.Write(image, proDosOrder, block, blocks[block]);
        }

        return image;
    }

    // The blocks a file takes: its data, and an index block when it has more than one.
    private static int Blocks(int length) => length <= BlockSize ? 1 : ((length + BlockSize - 1) / BlockSize) + 1;

    private static void Copy(byte[] data, int part, byte[] block)
    {
        int start = part * BlockSize;
        if (start < data.Length) { data.AsSpan(start, Math.Min(BlockSize, data.Length - start)).CopyTo(block); }
    }

    private static void Word(byte[] block, int offset, int value)
    {
        block[offset] = (byte)value;
        block[offset + 1] = (byte)(value >> 8);
    }

    private static void WriteName(byte[] block, int offset, int storage, string name)
    {
        block[offset] = (byte)((storage << 4) | name.Length);
        Encoding.ASCII.GetBytes(name, block.AsSpan(offset + 1));
    }

    // A SOS name, in capitals.
    private static string Name(string name)
    {
        ArgumentNullException.ThrowIfNull(name);
        string upper = name.ToUpperInvariant();
        return upper.Length is >= 1 and <= 15 && upper[0] is >= 'A' and <= 'Z' && upper.All(c => c is (>= 'A' and <= 'Z') or (>= '0' and <= '9') or '.')
            ? upper
            : throw new ArgumentException($"\"{name}\" is not a SOS name: 1-15 letters, digits and periods, starting with a letter.", nameof(name));
    }
}