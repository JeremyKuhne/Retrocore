// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug.Project;

/// <summary>
///  A file a new project writes or changes, or leaves as it is.
/// </summary>
/// <param name="Path">Its full path.</param>
/// <param name="Text">What it will say, or null when it is left as it is.</param>
/// <param name="What">What is done to it, as the command reports it.</param>
internal sealed record ScaffoldFile(string Path, string? Text, string What);
