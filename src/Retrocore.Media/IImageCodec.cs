// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Media;

/// <summary>
///  Writes a medium's snapshot as an image in one format, saying exactly what the format could not hold.
/// </summary>
/// <remarks>
///  <para>
///   A save never converts silently: a codec lists each thing the snapshot holds that its format cannot, such as a
///   track that no longer reads as sectors, and a host saves such an image only when the user accepts the losses.
///  </para>
/// </remarks>
public interface IImageCodec
{
    /// <summary>
    ///  Gets the format's name as the drives show it, such as <c>WOZ</c> or <c>DSK</c>.
    /// </summary>
    string Format { get; }

    /// <summary>
    ///  Writes a snapshot as an image.
    /// </summary>
    /// <param name="snapshot">The snapshot.</param>
    /// <returns>The image, and what it could not hold.</returns>
    /// <exception cref="ArgumentException">
    ///  The snapshot is of a kind of medium the format cannot hold at all.
    /// </exception>
    EncodedImage Encode(MediumSnapshot snapshot);
}
