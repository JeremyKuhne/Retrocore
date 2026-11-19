// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Media.Floppy;

namespace Retrocore.Media.Acorn;

/// <summary>
///  Writes a floppy disk as a DFS image: <c>SSD</c> or <c>DSD</c>.
/// </summary>
/// <param name="format"><c>SSD</c> or <c>DSD</c>.</param>
public sealed class AcornDiskCodec(string format = "SSD") : IImageCodec
{
    /// <inheritdoc/>
    public string Format { get; } = format is "SSD" or "DSD"
        ? format
        : throw new ArgumentException("A DFS disk is written as SSD or DSD.", nameof(format));

    /// <inheritdoc/>
    public EncodedImage Encode(MediumSnapshot snapshot)
    {
        ArgumentNullException.ThrowIfNull(snapshot);
        if (snapshot.Kind != DmkFormat.SnapshotKind)
        {
            throw new ArgumentException(
                $"A {Format} image holds a floppy disk, not a {snapshot.Kind} snapshot.",
                nameof(snapshot));
        }

        return AcornDiskImage.Encode(DmkFormat.ReadSnapshot(snapshot.Image.Span), Format == "DSD");
    }
}
