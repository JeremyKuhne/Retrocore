// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Media;

/// <summary>
///  A Disk II disk read from an image, and the codec that writes it back to that image as it was.
/// </summary>
/// <param name="Disk">The disk.</param>
/// <param name="Codec">
///  The codec for the image's own format and order, or null for one that can only be read, as a <c>.d13</c> image.
/// </param>
public sealed record LoadedDisk(WozDisk Disk, IImageCodec? Codec);
