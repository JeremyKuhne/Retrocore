// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Buffers.Binary;

namespace Retrocore.Media;

/// <summary>
///  What a 2MG file holds around its blocks: its header, with the creator, version, flags and fields no reader here
///  knows, and its comment, creator data and any other bytes, kept so a disk saved back gives the same file.
/// </summary>
/// <remarks>
///  <para>
///   A 2MG file is a 64-byte (or longer) header, then its data, then its comment and creator data, wherever the
///   header says they are. Only ProDOS-ordered blocks are read here, as a 3.5-inch disk and a hard disk hold them;
///   bit 31 of the flags is the disk's lock.
///  </para>
/// </remarks>
public sealed class TwoImgContainer
{
    /// <summary>
    ///  The snapshot kind of a block device: a 2MG file of its blocks, which holds its lock and any 2MG's header.
    /// </summary>
    public const string SnapshotKind = "2mg";

    private const int HeaderLength = 64;
    private const uint Locked = 0x8000_0000;
    private const int FlagsOffset = 16;
    private static ReadOnlySpan<byte> Magic => "2IMG"u8;

    // Everything before the blocks, and everything after them, as the file had them.
    private readonly byte[] _before;
    private readonly byte[] _after;

    private TwoImgContainer(byte[] before, byte[] after)
    {
        _before = before;
        _after = after;
    }

    /// <summary>
    ///  Gets whether the 2MG has a comment or creator data, which a format of bare blocks cannot keep.
    /// </summary>
    public bool HasExtras { get; private init; }

    /// <summary>
    ///  Gets whether an image is a 2MG file.
    /// </summary>
    /// <param name="image">The image's bytes.</param>
    /// <returns>True when it starts with a 2MG header.</returns>
    public static bool IsTwoImg(ReadOnlySpan<byte> image) => image.Length >= HeaderLength && image[..4].SequenceEqual(Magic);

    /// <summary>
    ///  Reads a 2MG file of ProDOS-ordered blocks.
    /// </summary>
    /// <param name="image">The file's bytes.</param>
    /// <param name="blocks">The blocks, a slice of <paramref name="image"/>.</param>
    /// <param name="locked">Whether the file's locked flag is set.</param>
    /// <returns>What the file holds around the blocks.</returns>
    /// <exception cref="InvalidDataException">
    ///  The file is not a 2MG, holds its data in another order, or its data runs past its end.
    /// </exception>
    public static TwoImgContainer Read(ReadOnlySpan<byte> image, out ReadOnlySpan<byte> blocks, out bool locked)
    {
        if (!IsTwoImg(image)) { throw new InvalidDataException("The image is not a 2MG file."); }
        int headerLength = BinaryPrimitives.ReadUInt16LittleEndian(image[8..]);
        uint order = BinaryPrimitives.ReadUInt32LittleEndian(image[12..]);
        uint flags = BinaryPrimitives.ReadUInt32LittleEndian(image[FlagsOffset..]);
        uint count = BinaryPrimitives.ReadUInt32LittleEndian(image[20..]);
        uint offset = BinaryPrimitives.ReadUInt32LittleEndian(image[24..]);
        uint length = BinaryPrimitives.ReadUInt32LittleEndian(image[28..]);
        if (order != 1) { throw new InvalidDataException("A 2MG block image must hold its blocks in ProDOS order."); }

        // Some writers leave the data's offset or length zero, meaning just after the header and all of the blocks.
        if (offset == 0) { offset = (uint)Math.Max(headerLength, HeaderLength); }
        if (length == 0) { length = count * 512; }
        if (offset < HeaderLength || offset > image.Length || length > image.Length - offset)
        {
            throw new InvalidDataException("The 2MG image's data runs past the end of the file.");
        }

        locked = (flags & Locked) != 0;
        blocks = image.Slice((int)offset, (int)length);
        return new(image[..(int)offset].ToArray(), image[(int)(offset + length)..].ToArray())
        {
            HasExtras = BinaryPrimitives.ReadUInt32LittleEndian(image[36..]) != 0
                || BinaryPrimitives.ReadUInt32LittleEndian(image[44..]) != 0,
        };
    }

    /// <summary>
    ///  Makes a new 2MG file's container, for blocks no 2MG gave: a 64-byte header naming Retrocore as the creator.
    /// </summary>
    /// <param name="blockCount">The number of blocks it holds.</param>
    /// <returns>The container.</returns>
    public static TwoImgContainer Create(uint blockCount)
    {
        byte[] header = new byte[HeaderLength];
        Magic.CopyTo(header);
        "RTRC"u8.CopyTo(header.AsSpan(4));
        BinaryPrimitives.WriteUInt16LittleEndian(header.AsSpan(8), HeaderLength);
        BinaryPrimitives.WriteUInt16LittleEndian(header.AsSpan(10), 1);
        BinaryPrimitives.WriteUInt32LittleEndian(header.AsSpan(12), 1);
        BinaryPrimitives.WriteUInt32LittleEndian(header.AsSpan(20), blockCount);
        BinaryPrimitives.WriteUInt32LittleEndian(header.AsSpan(24), HeaderLength);
        BinaryPrimitives.WriteUInt32LittleEndian(header.AsSpan(28), blockCount * 512);
        return new(header, []);
    }

    /// <summary>
    ///  Writes blocks in the container: the 2MG file as it was, with these blocks and this lock.
    /// </summary>
    /// <param name="blocks">The blocks, as many bytes as the container's file held.</param>
    /// <param name="locked">Whether the disk is locked.</param>
    /// <returns>The file.</returns>
    public byte[] Wrap(ReadOnlySpan<byte> blocks, bool locked)
    {
        byte[] file = new byte[_before.Length + blocks.Length + _after.Length];
        _before.CopyTo(file, 0);
        blocks.CopyTo(file.AsSpan(_before.Length));
        _after.CopyTo(file, _before.Length + blocks.Length);
        Span<byte> flags = file.AsSpan(FlagsOffset, 4);
        uint value = BinaryPrimitives.ReadUInt32LittleEndian(flags);
        BinaryPrimitives.WriteUInt32LittleEndian(flags, locked ? value | Locked : value & ~Locked);
        return file;
    }
}
