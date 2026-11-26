// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug.Project;

/// <summary>
///  A set of boot media or device dumps in the SDK's catalog.
/// </summary>
/// <param name="Id">The set's id, such as <c>c4040</c>.</param>
/// <param name="Title">What it is, as a plural noun phrase.</param>
/// <param name="For">What it is needed for.</param>
/// <param name="Source">Where it usually comes from.</param>
/// <param name="Variable">The environment variable that names a folder of the machine's dumps, or null.</param>
/// <param name="Folder">The folder name a launch that loads the files by name takes them in.</param>
/// <param name="Files">The files.</param>
internal sealed record BootMediaSet(string Id, string Title, string For, string Source, string? Variable, string Folder, IReadOnlyList<BootMediaFile> Files);
