// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Media;

/// <summary>
///  A 16-sector disk read into a sector image, with what the image could not hold.
/// </summary>
/// <param name="Bytes">The image: 4,096 bytes for each track, a sector that did not read left as zeros.</param>
/// <param name="Tracks">Its tracks, 35 to 40.</param>
/// <param name="Losses">Everything of the disk the image lost, the tracks that did not read among them.</param>
/// <param name="Unreadable">The tracks that did not read as 16 sectors.</param>
public sealed record SectorImage(byte[] Bytes, int Tracks, IReadOnlyList<string> Losses, IReadOnlyList<string> Unreadable)
{
    /// <summary>
    ///  Gets what the read should say though nothing is lost: a sector whose copy had a bad checksum where another
    ///  copy of it read.
    /// </summary>
    public IReadOnlyList<string> Notes { get; init; } = [];
}
