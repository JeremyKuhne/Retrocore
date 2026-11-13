// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Media;

/// <summary>
///  A file on an Apple Pascal volume: a run of blocks.
/// </summary>
/// <param name="Name">Its name, such as <c>SYSTEM.PASCAL</c>.</param>
/// <param name="FirstBlock">Its first block.</param>
/// <param name="NextBlock">The block after its last.</param>
/// <param name="Kind">Its kind.</param>
/// <param name="BytesInLastBlock">How much of its last block it uses, 1-512.</param>
/// <param name="Modified">When it was last changed, or null when the directory has no date.</param>
public sealed record PascalFileEntry(
    string Name,
    int FirstBlock,
    int NextBlock,
    PascalFileKind Kind,
    int BytesInLastBlock,
    DateOnly? Modified)
{
    /// <summary>
    ///  Gets its length in bytes.
    /// </summary>
    public int Length => NextBlock <= FirstBlock ? 0 : ((NextBlock - FirstBlock - 1) * DiskBlocks.BlockSize) + BytesInLastBlock;
}
