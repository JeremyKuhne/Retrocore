// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Media.Acorn;

/// <summary>
///  Writes Acorn tapes as UEF files.
/// </summary>
public sealed class AcornTapeCodec : IImageCodec
{
    /// <inheritdoc/>
    public string Format => "UEF";

    /// <inheritdoc/>
    public EncodedImage Encode(MediumSnapshot snapshot)
    {
        ArgumentNullException.ThrowIfNull(snapshot);
        if (snapshot.Kind != AcornTape.SnapshotKind)
        {
            throw new ArgumentException(
                $"A UEF image holds an Acorn tape, not a {snapshot.Kind} snapshot.",
                nameof(snapshot));
        }

        // UEF keeps no record tab, as bare block images keep no lock.
        return new(snapshot.Image.ToArray(), Losses: []);
    }
}
