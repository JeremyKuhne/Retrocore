// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Media;

/// <summary>
///  Writes a Disk II disk as a WOZ2 image, which holds all of it: every track and its length, the quarter-track map,
///  the image's unknown chunks, and the lock in its write-protection flag.
/// </summary>
/// <param name="sourceVersion">
///  The WOZ version of the image the disk came from, so a WOZ1 image saved back notes that it is now WOZ2.
/// </param>
public sealed class WozCodec(int sourceVersion = 2) : IImageCodec
{
    /// <inheritdoc/>
    public string Format => "WOZ";

    /// <inheritdoc/>
    public EncodedImage Encode(MediumSnapshot snapshot)
    {
        ArgumentNullException.ThrowIfNull(snapshot);
        if (snapshot.Kind != WozDisk.SnapshotKind)
        {
            throw new ArgumentException($"A WOZ image holds a Disk II disk, not a {snapshot.Kind} snapshot.", nameof(snapshot));
        }

        // WOZ2 holds all WOZ1 does, so a WOZ1 image loses nothing, but programs that read only WOZ1 cannot open it.
        return new(snapshot.Image.ToArray(), Losses: [])
        {
            Notes = sourceVersion == 1 ? ["The WOZ1 image is written as WOZ2."] : [],
        };
    }
}
