// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug.Project;

/// <summary>
///  What a target's environment built from its program: the environment's own file, and the disk or tape image a
///  launch boots, each written beside the binary.
/// </summary>
/// <param name="File">The environment's file, such as Woz Monitor hex, or null when the binary is the file.</param>
/// <param name="FileKind">What the file is, such as <c>Woz Monitor hex</c>, or null with no file.</param>
/// <param name="Image">
///  The image, or null when the environment builds none or the target's <c>image</c> is false.
/// </param>
/// <param name="ImageKind">What the image is, such as <c>ACI tape (WAV)</c>, or null with no image.</param>
/// <param name="Note">How to load the file or image by hand, or null.</param>
internal sealed record TargetMedia(string? File, string? FileKind, string? Image, string? ImageKind, string? Note = null)
{
    /// <summary>
    ///  Gets the media of an environment that builds nothing beyond the binary, as <c>bare</c> does.
    /// </summary>
    internal static TargetMedia None { get; } = new(File: null, FileKind: null, Image: null, ImageKind: null);
}
