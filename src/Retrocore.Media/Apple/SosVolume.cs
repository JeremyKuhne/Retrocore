// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text;

namespace Retrocore.Media;

/// <summary>
///  A SOS volume, read-only: the Apple III's file system, which ProDOS later shared. It reads the volume
///  directory's files from a 140K disk image in either sector order.
/// </summary>
/// <remarks>
///  <para>
///   A volume is 512-byte blocks. Block 2 starts the volume directory, a chain of blocks of 39-byte entries. A
///   file is one data block (seedling), an index block of up to 256 (sapling), or a master index of index blocks
///   (tree). Only the volume directory is read; subdirectories are listed but not entered.
///  </para>
/// </remarks>
public sealed class SosVolume
{
    /// <summary>
    ///  The size of a block.
    /// </summary>
    public const int BlockSize = 512;

    private const int VolumeDirectory = 2;
    private const int DiskSize = DiskBlocks.DiskSize;

    private readonly byte[] _image;
    private readonly bool _proDosOrder;

    private SosVolume(byte[] image, bool proDosOrder)
    {
        _image = image;
        _proDosOrder = proDosOrder;
        byte[] header = Block(VolumeDirectory);
        if ((header[4] >> 4) != 0xF)
        {
            throw new InvalidDataException("The image has no SOS volume directory at block 2.");
        }

        Name = Encoding.ASCII.GetString(header, 5, header[4] & 0xF);
        Files = [.. Entries()];
    }

    /// <summary>
    ///  Gets the volume's name.
    /// </summary>
    public string Name { get; }

    /// <summary>
    ///  Gets the volume directory's files, in directory order.
    /// </summary>
    public IReadOnlyList<SosFileEntry> Files { get; }

    /// <summary>
    ///  Reads a volume from a 140K disk image.
    /// </summary>
    /// <param name="image">The image.</param>
    /// <param name="proDosOrder">
    ///  Whether its sectors are in ProDOS order (<c>.po</c>) rather than DOS order (<c>.dsk</c>).
    /// </param>
    /// <returns>The volume.</returns>
    /// <exception cref="InvalidDataException">The image is not 140K or holds no SOS volume.</exception>
    public static SosVolume Read(byte[] image, bool proDosOrder)
    {
        ArgumentNullException.ThrowIfNull(image);
        return image.Length != DiskSize
            ? throw new InvalidDataException($"A 140K disk image is {DiskSize} bytes; this one is {image.Length}.")
            : new SosVolume(image, proDosOrder);
    }

    /// <summary>
    ///  Reads a file in the volume directory.
    /// </summary>
    /// <param name="name">Its name, in any case.</param>
    /// <returns>Its contents, as long as its end of file.</returns>
    /// <exception cref="FileNotFoundException">The volume directory has no such file.</exception>
    /// <exception cref="InvalidDataException">The file is a directory.</exception>
    public byte[] ReadFile(string name)
    {
        SosFileEntry entry = Files.FirstOrDefault(file => string.Equals(file.Name, name, StringComparison.OrdinalIgnoreCase))
            ?? throw new FileNotFoundException($"The volume /{Name} has no file {name}.", name);

        byte[] data = entry.StorageType switch
        {
            1 => Block(entry.KeyBlock),
            2 => Indexed(entry.KeyBlock, entry.EndOfFile),
            3 => Tree(entry.KeyBlock, entry.EndOfFile),
            _ => throw new InvalidDataException($"{name} is not a file SOS stores in blocks.")
        };

        return data.AsSpan(0, Math.Min(entry.EndOfFile, data.Length)).ToArray();
    }

    /// <summary>
    ///  Reads a block.
    /// </summary>
    /// <param name="block">The block number, 0-279.</param>
    /// <returns>Its 512 bytes.</returns>
    public byte[] Block(int block) => DiskBlocks.Read(_image, _proDosOrder, block);

    private IEnumerable<SosFileEntry> Entries()
    {
        bool header = true;
        for (int number = VolumeDirectory; number != 0;)
        {
            byte[] block = Block(number);
            int length = block[0x23];
            int perBlock = block[0x24];
            for (int index = header ? 1 : 0; index < perBlock; index++)
            {
                int offset = 4 + (index * length);
                int storage = block[offset] >> 4;
                if (storage == 0) { continue; }

                yield return new SosFileEntry(
                    Encoding.ASCII.GetString(block, offset + 1, block[offset] & 0xF),
                    storage,
                    block[offset + 0x10],
                    block[offset + 0x11] | (block[offset + 0x12] << 8),
                    block[offset + 0x15] | (block[offset + 0x16] << 8) | (block[offset + 0x17] << 16),
                    block[offset + 0x1F] | (block[offset + 0x20] << 8));
            }

            header = false;
            number = block[2] | (block[3] << 8);
        }
    }

    // A sapling: an index block whose low bytes are in its first half and high bytes in its second.
    private byte[] Indexed(int key, int length)
    {
        byte[] index = Block(key);
        int blocks = Math.Min(256, (length + BlockSize - 1) / BlockSize);
        byte[] data = new byte[blocks * BlockSize];
        for (int entry = 0; entry < blocks; entry++)
        {
            int number = index[entry] | (index[256 + entry] << 8);
            if (number != 0) { Block(number).CopyTo(data, entry * BlockSize); }
        }

        return data;
    }

    // A tree: a master index of sapling index blocks.
    private byte[] Tree(int key, int length)
    {
        byte[] master = Block(key);
        byte[] data = new byte[length];
        const int perIndex = 256 * BlockSize;
        for (int entry = 0; entry * perIndex < length; entry++)
        {
            int number = master[entry] | (master[256 + entry] << 8);
            if (number == 0) { continue; }

            byte[] part = Indexed(number, Math.Min(perIndex, length - (entry * perIndex)));
            part.AsSpan(0, Math.Min(part.Length, length - (entry * perIndex))).CopyTo(data.AsSpan(entry * perIndex));
        }

        return data;
    }
}
