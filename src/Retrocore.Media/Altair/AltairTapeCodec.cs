// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Media.Altair;

/// <summary>
///  Writes an Altair tape as its TAP image, the bytes in order, which holds all of it.
/// </summary>
public sealed class AltairTapeCodec : IImageCodec
{
    /// <summary>
    ///  The image format's name.
    /// </summary>
    public const string Name = "TAP";

    /// <inheritdoc/>
    public string Format => Name;

    /// <inheritdoc/>
    public EncodedImage Encode(MediumSnapshot snapshot)
    {
        ArgumentNullException.ThrowIfNull(snapshot);
        if (snapshot.Kind != AltairTape.SnapshotKind)
        {
            throw new ArgumentException($"A {Name} image holds an Altair tape, not a {snapshot.Kind} snapshot.", nameof(snapshot));
        }

        return new(snapshot.Image.ToArray(), []);
    }
}
