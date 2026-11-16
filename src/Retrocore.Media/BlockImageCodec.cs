// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Media;

/// <summary>
///  Writes a block device, such as a 3.5-inch disk or a hard disk, as an image: its bare blocks in ProDOS order, as
///  <c>.po</c>, <c>.hdv</c>, <c>.img</c> and 3.5-inch <c>.dsk</c> files hold them, or a 2MG file.
/// </summary>
/// <remarks>
///  <para>
///   Both are physical: they hold every block. A 2MG keeps the header, comment and creator data of the 2MG the disk
///   was read from, and its locked flag is the disk's lock, so an unchanged disk saved to its own 2MG gives back the
///   file. Bare blocks keep no lock, and a save to them from a 2MG with a comment or creator data says so.
///  </para>
/// </remarks>
public sealed class BlockImageCodec : IImageCodec
{
    private BlockImageCodec(string format, bool twoImg)
    {
        Format = format;
        IsTwoImg = twoImg;
    }

    /// <inheritdoc/>
    public string Format { get; }

    /// <summary>
    ///  Gets whether the codec writes a 2MG file rather than bare blocks.
    /// </summary>
    public bool IsTwoImg { get; }

    /// <summary>
    ///  Gets the codec that writes a block image with an extension.
    /// </summary>
    /// <param name="extension">The extension, with or without its dot, such as <c>.po</c> or <c>2mg</c>.</param>
    /// <returns>The codec, or null for an extension that is not a block image.</returns>
    public static BlockImageCodec? For(string extension)
    {
        string format = extension.TrimStart('.').ToUpperInvariant();
        return format switch
        {
            "2MG" => new(format, twoImg: true),
            "PO" or "HDV" or "IMG" or "DSK" => new(format, twoImg: false),
            _ => null,
        };
    }

    /// <inheritdoc/>
    public EncodedImage Encode(MediumSnapshot snapshot)
    {
        ArgumentNullException.ThrowIfNull(snapshot);
        if (snapshot.Kind != TwoImgContainer.SnapshotKind)
        {
            throw new ArgumentException($"A block image holds a block device, not a {snapshot.Kind} snapshot.", nameof(snapshot));
        }

        if (IsTwoImg) { return new(snapshot.Image.ToArray(), []); }
        TwoImgContainer container = TwoImgContainer.Read(snapshot.Image.Span, out ReadOnlySpan<byte> blocks, out _);
        return new(blocks.ToArray(), [])
        {
            Notes = container.HasExtras ? [$"{Format} does not keep the 2MG's comment and creator data."] : [],
        };
    }
}
