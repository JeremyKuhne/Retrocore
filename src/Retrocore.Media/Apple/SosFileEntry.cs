// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Media;

/// <summary>
///  A file in a SOS volume directory.
/// </summary>
/// <param name="Name">Its name.</param>
/// <param name="StorageType">1 seedling, 2 sapling, 3 tree, 13 subdirectory.</param>
/// <param name="FileType">Its type, such as <c>$0C</c> for a SOS system file.</param>
/// <param name="KeyBlock">Its key block.</param>
/// <param name="EndOfFile">Its length.</param>
/// <param name="AuxType">Its auxiliary type, such as a binary file's load address.</param>
public sealed record SosFileEntry(string Name, int StorageType, int FileType, int KeyBlock, int EndOfFile, int AuxType);
