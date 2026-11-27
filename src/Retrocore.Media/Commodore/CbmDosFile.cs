// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Media.Commodore;

/// <summary>
///  A file in a DOS 2 disk's directory.
/// </summary>
/// <param name="Name">The name, without its padding.</param>
/// <param name="Type">The type, from the entry's low three bits.</param>
/// <param name="IsClosed">Whether the file was closed, the entry's bit 7; an open file was never finished.</param>
/// <param name="Track">The first block's track.</param>
/// <param name="Sector">The first block's sector.</param>
/// <param name="Blocks">The length in blocks, as the directory lists it.</param>
public sealed record CbmDosFile(string Name, CbmDosFileType Type, bool IsClosed, int Track, int Sector, int Blocks);
