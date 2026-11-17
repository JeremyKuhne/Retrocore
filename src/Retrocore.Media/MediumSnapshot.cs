// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Media;

/// <summary>
///  An immutable copy of a medium, taken at one moment: a lossless image of its kind, which the format codecs read
///  to write the medium's image.
/// </summary>
/// <param name="Kind">The kind of image <paramref name="Image"/> is, such as <c>woz2</c> for a Disk II disk.</param>
/// <param name="Version">The medium's version when it was taken.</param>
/// <param name="WriteProtected">The medium's lock when it was taken.</param>
/// <param name="Image">The lossless image, which nothing changes.</param>
public sealed record MediumSnapshot(string Kind, long Version, bool WriteProtected, ReadOnlyMemory<byte> Image);
