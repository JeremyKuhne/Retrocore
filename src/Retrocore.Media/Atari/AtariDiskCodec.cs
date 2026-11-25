// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Media.Atari;

/// <summary>
///  Writes an <see cref="AtariDisk"/> as an ATR or XFD image.
/// </summary>
public sealed class AtariDiskCodec : IImageCodec
{
    private AtariDiskCodec(string format) => Format = format;

    /// <inheritdoc/>
    public string Format { get; }

    /// <summary>
    ///  Gets the codec for an extension.
    /// </summary>
    /// <param name="extension">The extension, with or without its dot.</param>
    /// <returns>The codec, or null for an extension that isn't an Atari disk image.</returns>
    public static AtariDiskCodec? For(string extension)
    {
        string format = extension.TrimStart('.').ToUpperInvariant();
        return format is "ATR" or "XFD" ? new(format) : null;
    }

    /// <inheritdoc/>
    public EncodedImage Encode(MediumSnapshot snapshot)
    {
        ArgumentNullException.ThrowIfNull(snapshot);
        if (snapshot.Kind != AtariDisk.SnapshotKind)
        {
            throw new ArgumentException($"An Atari disk image holds an Atari disk, not a {snapshot.Kind} snapshot.", nameof(snapshot));
        }

        if (Format == "ATR") { return new(snapshot.Image.ToArray(), []); }
        AtariDisk disk = AtariDisk.Load(snapshot.Image.Span);
        if (disk.SectorSize != 128)
        {
            throw new InvalidOperationException("An XFD image holds only single- and enhanced-density disks; save it as an ATR.");
        }

        return new(disk.ToXfd(), []);
    }
}
