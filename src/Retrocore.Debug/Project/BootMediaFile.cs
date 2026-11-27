// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug.Project;

/// <summary>
///  A file of a boot media set.
/// </summary>
/// <param name="Name">Its usual name, which a launch that loads it by name takes.</param>
/// <param name="Size">Its size in bytes.</param>
/// <param name="Sha1">Its SHA-1, in lowercase hex.</param>
internal sealed record BootMediaFile(string Name, int Size, string Sha1);
