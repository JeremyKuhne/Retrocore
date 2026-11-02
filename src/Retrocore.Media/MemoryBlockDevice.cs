// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Media;

/// <summary>
///  A caller-created block device backed by copied bytes, useful for tests and read-only disk mounts.
/// </summary>
public sealed class MemoryBlockDevice : IBlockDevice
{
    private readonly byte[] _bytes;

    /// <summary>
    ///  Creates a block device.
    /// </summary>
    /// <param name="bytes">A nonempty whole number of 512-byte blocks.</param>
    /// <param name="isReadOnly">Whether writes are prohibited.</param>
    public MemoryBlockDevice(ReadOnlySpan<byte> bytes, bool isReadOnly = true)
    {
        if (bytes.Length == 0 || bytes.Length % 512 != 0)
        {
            throw new ArgumentException("Whole 512-byte blocks are required.", nameof(bytes));
        }

        _bytes = bytes.ToArray();
        IsReadOnly = isReadOnly;
    }

    /// <inheritdoc/>
    public uint BlockCount => (uint)(_bytes.Length / 512);

    /// <inheritdoc/>
    public bool IsReadOnly { get; }

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
        if (IsReadOnly) { throw new InvalidOperationException("The block device is read-only."); }
        source.CopyTo(_bytes.AsSpan((int)block * 512, length: 512));
    }

    private void Check(uint block, int length)
    {
        if (block >= BlockCount) { throw new ArgumentOutOfRangeException(nameof(block)); }
        if (length != 512)
        {
            throw new ArgumentException("A block buffer must contain exactly 512 bytes.", nameof(length));
        }
    }
}
