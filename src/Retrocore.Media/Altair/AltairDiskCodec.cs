// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Media.Altair;

/// <summary>
///  Writes an Altair 8-inch disk as its raw image, <c>DSK</c>, which holds all of it.
/// </summary>
public sealed class AltairDiskCodec : IImageCodec
{
    /// <summary>
    ///  The image format's name.
    /// </summary>
    public const string Name = "DSK";

    /// <inheritdoc/>
    public string Format => Name;

    /// <summary>
    ///  Reads an image.
    /// </summary>
    /// <param name="image">The image's bytes.</param>
    /// <returns>The disk and the codec that writes it back.</returns>
    /// <exception cref="InvalidDataException">The image is not an Altair 8-inch disk's size.</exception>
    public static (AltairDisk Disk, AltairDiskCodec Codec) Load(ReadOnlySpan<byte> image) => (AltairDisk.Load(image), new());

    /// <inheritdoc/>
    public EncodedImage Encode(MediumSnapshot snapshot)
    {
        ArgumentNullException.ThrowIfNull(snapshot);
        if (snapshot.Kind != AltairDisk.SnapshotKind)
        {
            throw new ArgumentException($"A {Name} image holds an Altair disk, not a {snapshot.Kind} snapshot.", nameof(snapshot));
        }

        return new(snapshot.Image.ToArray(), []);
    }
}
