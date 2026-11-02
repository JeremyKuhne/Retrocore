// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Media;
using Touki;

namespace AppleSharp;

/// <summary>
///  App-owned raw ProDOS-order storage. Explicit writable mounts persist and flush each changed block.
/// </summary>
internal sealed class FileBlockDevice : DisposableBase, IBlockDevice
{
    private readonly FileStream _stream;

    /// <summary>
    ///  Opens an existing raw .po image with a capacity representable by the slot-seven firmware.
    /// </summary>
    /// <param name="path">The image file.</param>
    /// <param name="writable">Whether persistent writes are explicitly permitted.</param>
    internal FileBlockDevice(string path, bool writable)
    {
        if (!path.EndsWith(".po", StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidDataException("AppleSharp currently mounts raw ProDOS-order .po images only.");
        }

        _stream = new(path, FileMode.Open, writable ? FileAccess.ReadWrite : FileAccess.Read, FileShare.Read);
        if (_stream.Length < 1024 || _stream.Length % 512 != 0 || _stream.Length / 512 > ushort.MaxValue)
        {
            _stream.Dispose();
            throw new InvalidDataException("A .po image must contain 2-65535 complete 512-byte blocks.");
        }

        BlockCount = (uint)(_stream.Length / 512);
        IsReadOnly = !writable;
    }

    /// <inheritdoc/>
    public uint BlockCount { get; }

    /// <inheritdoc/>
    public bool IsReadOnly { get; }

    /// <inheritdoc/>
    public void ReadBlock(uint block, Span<byte> destination)
    {
        if (destination.Length != 512)
        {
            throw new ArgumentException("A 512-byte destination is required.", nameof(destination));
        }

        if (block >= BlockCount) { throw new ArgumentOutOfRangeException(nameof(block)); }

        _stream.Position = (long)block * 512;
        _stream.ReadExactly(destination);
    }

    /// <inheritdoc/>
    public void WriteBlock(uint block, ReadOnlySpan<byte> source)
    {
        if (source.Length != 512) { throw new ArgumentException("A 512-byte source is required.", nameof(source)); }
        if (block >= BlockCount) { throw new ArgumentOutOfRangeException(nameof(block)); }
        if (IsReadOnly) { throw new InvalidOperationException("This image was mounted read-only."); }
        _stream.Position = (long)block * 512;
        _stream.Write(source);
        _stream.Flush(flushToDisk: true);
    }

    /// <inheritdoc/>
    protected override void Dispose(bool disposing)
    {
        if (disposing) { _stream.Dispose(); }
    }
}
