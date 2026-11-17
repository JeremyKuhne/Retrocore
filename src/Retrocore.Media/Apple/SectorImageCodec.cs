// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Media;

/// <summary>
///  Writes a Disk II disk as a 16-sector image: <c>.dsk</c> or <c>.do</c> in DOS's sector order, <c>.po</c> (or a
///  <c>.dsk</c> found to be in it) in ProDOS's.
/// </summary>
/// <remarks>
///  <para>
///   A sector image is guest-equivalent while every track is standard: the machine reads back the same sectors. What
///   it cannot hold is listed, as <see cref="SectorDiskReader.Decode"/> finds it.
///  </para>
/// </remarks>
/// <param name="format">The format's name, such as <c>DSK</c>.</param>
/// <param name="proDosOrder">Whether the image is in ProDOS's sector order.</param>
public sealed class SectorImageCodec(string format, bool proDosOrder) : IImageCodec
{
    /// <inheritdoc/>
    public string Format { get; } = format;

    /// <summary>
    ///  Gets whether the image is in ProDOS's sector order.
    /// </summary>
    public bool ProDosOrder { get; } = proDosOrder;

    /// <inheritdoc/>
    public EncodedImage Encode(MediumSnapshot snapshot)
    {
        ArgumentNullException.ThrowIfNull(snapshot);
        if (snapshot.Kind != WozDisk.SnapshotKind)
        {
            throw new ArgumentException($"A sector image holds a Disk II disk, not a {snapshot.Kind} snapshot.", nameof(snapshot));
        }

        SectorImage image = SectorDiskReader.Decode(WozDisk.Load(snapshot.Image.Span, writable: true), ProDosOrder);
        return new(image.Bytes, image.Losses) { Notes = image.Notes };
    }
}
