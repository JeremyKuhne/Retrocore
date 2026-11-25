// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Media.Atari;

/// <summary>
///  Writes an <see cref="AtariTape"/> as a <c>.cas</c> file.
/// </summary>
public sealed class AtariTapeCodec : IImageCodec
{
    /// <inheritdoc/>
    public string Format => "CAS";

    /// <inheritdoc/>
    public EncodedImage Encode(MediumSnapshot snapshot)
    {
        ArgumentNullException.ThrowIfNull(snapshot);
        if (snapshot.Kind != AtariTape.SnapshotKind)
        {
            throw new ArgumentException($"A .cas file holds an Atari tape, not a {snapshot.Kind} snapshot.", nameof(snapshot));
        }

        return new(snapshot.Image.ToArray(), []);
    }
}
