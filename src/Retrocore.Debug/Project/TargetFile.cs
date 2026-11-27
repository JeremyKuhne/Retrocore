// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug.Project;

/// <summary>
///  A data file a target puts beside its program on its disk, from its <c>files</c>.
/// </summary>
/// <param name="Path">The file's full path, <c>${obj}</c> replaced, such as a step's output.</param>
/// <param name="Name">The name it has on the disk, or null for the environment's name made from its file name.</param>
/// <param name="Address">The load address the disk records for it, or null for the environment's default.</param>
internal sealed record TargetFile(string Path, string? Name, int? Address);
