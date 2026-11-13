// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Buffers.Binary;

namespace Retrocore.Media;

/// <summary>
///  A 3.5-inch disk's 512-byte blocks: a 400K or 800K Apple (GCR) disk, or a 720K or 1440K MFM disk, as an Apple
///  3.5 Drive or SuperDrive reads them.
/// </summary>
/// <remarks>
///  <para>
///   Images are the blocks in ProDOS order, as <c>.po</c>, <c>.hdv</c>, <c>.img</c> and 3.5-inch <c>.dsk</c> files
///   hold them, or a 2MG file of ProDOS-ordered blocks, whose locked flag write-protects the disk. The size says the
///   kind of disk. Writes change the copy here, never the image the disk was loaded from.
///  </para>
/// </remarks>
public sealed class Disk35Disk : IBlockDevice
{
    private const int BlockSize = 512;
    private static ReadOnlySpan<byte> TwoImgMagic => "2IMG"u8;

    private readonly byte[] _blocks;

    private Disk35Disk(byte[] blocks, Disk35Format format, bool writeProtected)
    {
        _blocks = blocks;
        Format = format;
        IsReadOnly = writeProtected;
    }

    /// <summary>
    ///  Gets the kind of disk.
    /// </summary>
    public Disk35Format Format { get; }

    /// <inheritdoc/>
    public uint BlockCount => (uint)(_blocks.Length / BlockSize);

    /// <summary>
    ///  Gets or sets whether the disk is write-protected, as its tab is.
    /// </summary>
    public bool IsReadOnly { get; set; }

    /// <summary>
    ///  Gets whether writes have changed the disk since it was loaded.
    /// </summary>
    public bool IsDirty { get; private set; }

    /// <summary>
    ///  Gets a count that changes whenever the disk changes.
    /// </summary>
    public long Version { get; private set; }

    /// <summary>
    ///  Gets whether the disk is a high-density (1440K) disk, which only a SuperDrive reads.
    /// </summary>
    public bool IsHighDensity => Format == Disk35Format.Mfm1440;

    /// <summary>
    ///  Gets whether the disk is recorded in MFM, as PC disks are, rather than Apple's GCR.
    /// </summary>
    public bool IsMfm => Format is Disk35Format.Mfm720 or Disk35Format.Mfm1440;

    /// <summary>
    ///  Gets the number of sides the disk is recorded on.
    /// </summary>
    public int Sides => Format == Disk35Format.Gcr400 ? 1 : 2;

    /// <summary>
    ///  Gets the image file extensions a 3.5-inch disk loads from.
    /// </summary>
    public static IReadOnlyList<string> Extensions { get; } = ["po", "2mg", "hdv", "img", "dsk"];

    /// <summary>
    ///  Loads a disk from an image.
    /// </summary>
    /// <param name="image">The image file's bytes: blocks in ProDOS order, or a 2MG file.</param>
    /// <param name="writeProtected">Whether the disk starts write-protected; a locked 2MG file always is.</param>
    /// <returns>The disk, a copy independent of <paramref name="image"/>.</returns>
    /// <exception cref="InvalidDataException">The image is not a 400K, 800K, 720K or 1440K disk.</exception>
    public static Disk35Disk Load(ReadOnlySpan<byte> image, bool writeProtected = false)
    {
        if (image.Length >= 64 && image[..4].SequenceEqual(TwoImgMagic))
        {
            int headerLength = BinaryPrimitives.ReadUInt16LittleEndian(image[8..]);
            uint order = BinaryPrimitives.ReadUInt32LittleEndian(image[12..]);
            uint flags = BinaryPrimitives.ReadUInt32LittleEndian(image[16..]);
            uint offset = BinaryPrimitives.ReadUInt32LittleEndian(image[24..]);
            uint length = BinaryPrimitives.ReadUInt32LittleEndian(image[28..]);
            if (order != 1)
            {
                throw new InvalidDataException("A 3.5-inch 2MG image must hold its blocks in ProDOS order.");
            }

            if (offset == 0) { offset = (uint)headerLength; }
            if (offset > image.Length || length > image.Length - offset)
            {
                throw new InvalidDataException("The 2MG image's data runs past the end of the file.");
            }

            writeProtected |= (flags & 0x8000_0000) != 0;
            image = image.Slice((int)offset, (int)length);
        }

        Disk35Format format = FormatOf(image.Length) ?? throw new InvalidDataException(
            $"A 3.5-inch disk image holds 400K, 800K, 720K or 1440K; this one has {image.Length} bytes.");

        return new(image.ToArray(), format, writeProtected);
    }

    /// <summary>
    ///  Makes a blank disk, every byte zero, as a format leaves it.
    /// </summary>
    /// <param name="format">The kind of disk.</param>
    /// <returns>The disk.</returns>
    public static Disk35Disk Blank(Disk35Format format) => new(new byte[BlocksOf(format) * BlockSize], format, writeProtected: false);

    /// <summary>
    ///  Gets the number of blocks on a kind of disk.
    /// </summary>
    /// <param name="format">The kind of disk.</param>
    /// <returns>800, 1600, 1440 or 2880.</returns>
    public static int BlocksOf(Disk35Format format) => format switch
    {
        Disk35Format.Gcr400 => 800,
        Disk35Format.Gcr800 => 1600,
        Disk35Format.Mfm720 => 1440,
        Disk35Format.Mfm1440 => 2880,
        _ => throw new ArgumentOutOfRangeException(nameof(format))
    };

    private static Disk35Format? FormatOf(int length) => length switch
    {
        800 * BlockSize => Disk35Format.Gcr400,
        1600 * BlockSize => Disk35Format.Gcr800,
        1440 * BlockSize => Disk35Format.Mfm720,
        2880 * BlockSize => Disk35Format.Mfm1440,
        _ => null
    };

    /// <summary>
    ///  Gets where a block lies on the disk: its track, side and sector.
    /// </summary>
    /// <param name="block">The block.</param>
    /// <returns>The track (0-79), side and sector.</returns>
    /// <remarks>
    ///  <para>
    ///   An Apple disk spins slower toward its center and so holds 12 sectors on tracks 0-15, 11 on 16-31, 10 on
    ///   32-47, 9 on 48-63 and 8 on 64-79, both sides of a track before the next. An MFM disk has 9 or 18 sectors on
    ///   every track.
    ///  </para>
    /// </remarks>
    public (int Track, int Side, int Sector) Locate(uint block)
    {
        ArgumentOutOfRangeException.ThrowIfGreaterThanOrEqual(block, BlockCount);
        int remaining = (int)block;
        if (IsMfm)
        {
            int sectors = Format == Disk35Format.Mfm720 ? 9 : 18;
            int cylinder = remaining / (sectors * 2);
            remaining %= sectors * 2;
            return (cylinder, remaining / sectors, remaining % sectors);
        }

        for (int track = 0; ; track++)
        {
            int sectors = 12 - track / 16;
            int perTrack = sectors * Sides;
            if (remaining < perTrack) { return (track, remaining / sectors, remaining % sectors); }
            remaining -= perTrack;
        }
    }

    /// <inheritdoc/>
    public void ReadBlock(uint block, Span<byte> destination)
    {
        Check(block, destination.Length);
        _blocks.AsSpan((int)block * BlockSize, BlockSize).CopyTo(destination);
    }

    /// <inheritdoc/>
    public void WriteBlock(uint block, ReadOnlySpan<byte> source)
    {
        Check(block, source.Length);
        if (IsReadOnly) { throw new InvalidOperationException("The disk is write-protected."); }
        source.CopyTo(_blocks.AsSpan((int)block * BlockSize, BlockSize));
        IsDirty = true;
        Version++;
    }

    /// <summary>
    ///  Formats the disk: every block zero.
    /// </summary>
    /// <exception cref="InvalidOperationException">The disk is write-protected.</exception>
    public void Erase()
    {
        if (IsReadOnly) { throw new InvalidOperationException("The disk is write-protected."); }
        Array.Clear(_blocks);
        IsDirty = true;
        Version++;
    }

    /// <summary>
    ///  Gets the disk's blocks in ProDOS order, as a <c>.po</c> image holds them.
    /// </summary>
    /// <returns>A copy of the blocks.</returns>
    public byte[] ToImage() => (byte[])_blocks.Clone();

    private void Check(uint block, int length)
    {
        ArgumentOutOfRangeException.ThrowIfGreaterThanOrEqual(block, BlockCount);
        if (length != BlockSize) { throw new ArgumentException("A block is 512 bytes.", nameof(length)); }
    }
}
