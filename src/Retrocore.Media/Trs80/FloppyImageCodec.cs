// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Media.Floppy;

namespace Retrocore.Media.Trs80;

/// <summary>
///  Writes a TRS-80, Color Computer or Kaypro floppy disk as an image: JV1, JV3, JVC, DMK or a raw Kaypro image (IMG).
/// </summary>
/// <remarks>
///  <para>
///   A disk's snapshot is a DMK image, which holds all of it, so a DMK save is the snapshot itself. The others read
///   the snapshot back and list what their format cannot hold. A JVC codec for an image that was read keeps that
///   image's header, and so its geometry. IMD has no writer yet: a disk read from IMD saves as another format.
///  </para>
/// </remarks>
public sealed class FloppyImageCodec : IImageCodec
{
    private readonly byte[]? _jvcHeader;

    private FloppyImageCodec(string format, byte[]? jvcHeader)
    {
        Format = format;
        _jvcHeader = jvcHeader;
    }

    /// <inheritdoc/>
    public string Format { get; }

    /// <summary>
    ///  Gets the header a JVC image was read with, which saving it back keeps; null for another format or a new image.
    /// </summary>
    public byte[]? JvcHeader => _jvcHeader is null ? null : [.. _jvcHeader];

    /// <summary>
    ///  Gets the codec that writes an image with an extension, for a drive that saves some formats.
    /// </summary>
    /// <param name="extension">The extension, with or without its dot, such as <c>.jv3</c>.</param>
    /// <param name="saveFormats">
    ///  The formats the drive saves; <c>dsk</c> is JVC on a drive that saves <c>jvc</c>, as the Color Computer's do,
    ///  and JV1 otherwise.
    /// </param>
    /// <returns>The codec, or null for an extension that is not a floppy image these write.</returns>
    public static FloppyImageCodec? For(string extension, IEnumerable<string> saveFormats)
    {
        ArgumentNullException.ThrowIfNull(extension);
        ArgumentNullException.ThrowIfNull(saveFormats);
        string format = extension.TrimStart('.').ToUpperInvariant();
        if (format == "DSK")
        {
            bool jvc = saveFormats.Contains("jvc", StringComparer.OrdinalIgnoreCase);
            bool kaypro = saveFormats.Contains("img", StringComparer.OrdinalIgnoreCase);
            format = jvc ? "JVC" : kaypro ? "IMG" : "JV1";
        }

        return format is "JV1" or "JV3" or "JVC" or "DMK" or "IMG" ? new(format, jvcHeader: null) : null;
    }

    /// <summary>
    ///  Gets the codec that writes a disk back to the image it was read from.
    /// </summary>
    /// <param name="format">The format the image was read as, such as <c>JV3</c>.</param>
    /// <param name="image">The image's bytes, whose header a JVC codec keeps.</param>
    /// <returns>The codec, or null for a format with no writer, IMD.</returns>
    public static FloppyImageCodec? ForImage(string format, ReadOnlySpan<byte> image) => format switch
    {
        "JV1" or "JV3" or "DMK" or "IMG" => new(format, jvcHeader: null),
        "JVC" => new(format, JvcFormat.Header(image).ToArray()),
        _ => null,
    };

    /// <inheritdoc/>
    public EncodedImage Encode(MediumSnapshot snapshot)
    {
        ArgumentNullException.ThrowIfNull(snapshot);
        if (snapshot.Kind != DmkFormat.SnapshotKind)
        {
            throw new ArgumentException($"A floppy image holds a floppy disk, not a {snapshot.Kind} snapshot.", nameof(snapshot));
        }

        FloppyDisk disk = DmkFormat.ReadSnapshot(snapshot.Image.Span);
        return Format switch
        {
            "DMK" => DmkFormat.Encode(disk),
            "JV1" => Jv1Format.Encode(disk),
            "JV3" => Jv3Format.Encode(disk),
            "IMG" => KayproFormat.Encode(disk),
            _ when _jvcHeader is not null => JvcFormat.Encode(disk, _jvcHeader),
            _ => JvcFormat.Encode(disk),
        };
    }
}
