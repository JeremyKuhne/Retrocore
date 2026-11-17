// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Media;

/// <summary>
///  A block device backed by copied bytes, as a ProFile or the slot 7 device holds an image: a medium the machine
///  writes in memory, which a host saves back to the image.
/// </summary>
/// <remarks>
///  <para>
///   Its snapshot is a 2MG file of its blocks, which holds its lock and, for a disk read from a 2MG, that file's
///   header, comment and creator data, so it saves back to any of the block formats.
///  </para>
/// </remarks>
public sealed class MemoryBlockDevice : IBlockDevice, IMedium
{
    private readonly byte[] _bytes;
    private readonly TwoImgContainer _container;
    private bool _writeProtected;

    /// <summary>
    ///  Creates a block device.
    /// </summary>
    /// <param name="bytes">A nonempty whole number of 512-byte blocks.</param>
    /// <param name="isReadOnly">Whether the device starts write-protected.</param>
    public MemoryBlockDevice(ReadOnlySpan<byte> bytes, bool isReadOnly = true)
        : this(bytes, isReadOnly, container: null)
    {
    }

    private MemoryBlockDevice(ReadOnlySpan<byte> bytes, bool isReadOnly, TwoImgContainer? container)
    {
        if (bytes.Length == 0 || bytes.Length % 512 != 0)
        {
            throw new ArgumentException("Whole 512-byte blocks are required.", nameof(bytes));
        }

        _bytes = bytes.ToArray();
        _writeProtected = isReadOnly;
        _container = container ?? TwoImgContainer.Create(BlockCount);
    }

    /// <summary>
    ///  Loads a block device from an image: its blocks in ProDOS order with no header, as <c>.po</c> and <c>.hdv</c>
    ///  files hold them, or a 2MG file of them, whose locked flag write-protects it.
    /// </summary>
    /// <param name="image">The image file's bytes.</param>
    /// <param name="writeProtected">Whether the device starts write-protected; a locked 2MG file always is.</param>
    /// <returns>The device, a copy independent of <paramref name="image"/>.</returns>
    /// <exception cref="InvalidDataException">The image is not whole blocks, or not a 2MG of blocks.</exception>
    public static MemoryBlockDevice Load(ReadOnlySpan<byte> image, bool writeProtected = false)
    {
        TwoImgContainer? container = null;
        if (TwoImgContainer.IsTwoImg(image))
        {
            container = TwoImgContainer.Read(image, out image, out bool locked);
            writeProtected |= locked;
        }

        if (image.Length == 0 || image.Length % 512 != 0)
        {
            throw new InvalidDataException("A block image must be a whole number of 512-byte blocks.");
        }

        return new(image, writeProtected, container);
    }

    /// <inheritdoc/>
    public uint BlockCount => (uint)(_bytes.Length / 512);

    /// <inheritdoc/>
    public bool IsReadOnly => _writeProtected;

    /// <inheritdoc/>
    public bool IsWriteProtected
    {
        get => _writeProtected;
        set
        {
            if (value == _writeProtected) { return; }
            _writeProtected = value;
            Version++;
        }
    }

    /// <inheritdoc/>
    public long Version { get; private set; }

    /// <summary>
    ///  Gets whether writes have changed the blocks since the device was loaded or last saved.
    /// </summary>
    public bool IsDirty { get; private set; }

    /// <inheritdoc/>
    public void ReadBlock(uint block, Span<byte> destination)
    {
        Check(block, destination.Length);
        _bytes.AsSpan((int)block * 512, length: 512).CopyTo(destination);
    }

    /// <inheritdoc/>
    public void WriteBlock(uint block, ReadOnlySpan<byte> source)
    {
        Check(block, source.Length);
        if (_writeProtected) { throw new InvalidOperationException("The block device is read-only."); }
        source.CopyTo(_bytes.AsSpan((int)block * 512, length: 512));
        IsDirty = true;
        Version++;
    }

    /// <inheritdoc/>
    public MediumSnapshot Snapshot() => new(TwoImgContainer.SnapshotKind, Version, _writeProtected, _container.Wrap(_bytes, _writeProtected));

    /// <summary>
    ///  Records that the blocks were saved to an image that holds them.
    /// </summary>
    public void MarkSaved() => IsDirty = false;

    /// <summary>
    ///  Records that the blocks differ from their image, as after a save that could not hold all of them.
    /// </summary>
    public void MarkChanged() => IsDirty = true;

    private void Check(uint block, int length)
    {
        if (block >= BlockCount) { throw new ArgumentOutOfRangeException(nameof(block)); }
        if (length != 512)
        {
            throw new ArgumentException("A block buffer must contain exactly 512 bytes.", nameof(length));
        }
    }
}
