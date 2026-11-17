// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Media;

/// <summary>
///  An image a codec wrote, and what of the medium it could not hold.
/// </summary>
/// <param name="Bytes">The image.</param>
/// <param name="Losses">
///  What the image lost, each said so a person can decide, such as <c>track 3 does not read as 16 sectors</c>; empty
///  when the image holds all the format promises.
/// </param>
public sealed record EncodedImage(byte[] Bytes, IReadOnlyList<string> Losses)
{
    /// <summary>
    ///  Gets what the save should say though nothing is lost, such as a WOZ1 image written as WOZ2.
    /// </summary>
    public IReadOnlyList<string> Notes { get; init; } = [];

    /// <summary>
    ///  Gets whether the image lost nothing.
    /// </summary>
    public bool IsLossless => Losses.Count == 0;
}
