// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Media;

namespace Retrocore.Debug;

/// <summary>
///  Where a mounted disk came from, as the host keeps it: its medium id, its image, the codec that writes the image
///  back in its own format and order, and the image's baseline, the revision of the file the disk matches.
/// </summary>
/// <param name="Id">The medium id, so two disks from one image, or one disk inserted twice, are never confused.</param>
/// <param name="Path">The image's full path.</param>
/// <param name="Codec">The codec for the image's format, or null for one that can only be read.</param>
/// <param name="Baseline">The image's revision the disk matches.</param>
internal sealed record DiskSource(Guid Id, string Path, IImageCodec? Codec, FileRevision Baseline)
{
    /// <summary>
    ///  Gets the medium id as the protocol gives it, such as <c>m-3f9c…</c>.
    /// </summary>
    internal string MediumId => $"m-{Id:N}";
}
