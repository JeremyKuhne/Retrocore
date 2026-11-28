// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Media.Floppy;

/// <summary>
///  What a CP/M disk's file system takes from its disk parameter block: where the blocks start, their size and count,
///  and the directory's entries and blocks.
/// </summary>
/// <param name="ReservedTracks">The system's tracks, before the first block (OFF).</param>
/// <param name="TrackBytes">The bytes on a track.</param>
/// <param name="BlockSize">The bytes in a block.</param>
/// <param name="Blocks">The blocks the disk has (DSM + 1).</param>
/// <param name="DirectoryEntries">The directory's entries (DRM + 1).</param>
/// <param name="DirectoryBlocks">
///  The blocks from block 0 that the allocation vector reserves (AL0's bits), which no file may take: the directory's,
///  and on some systems the end of the system itself.
/// </param>
public sealed record CpmGeometry(int ReservedTracks, int TrackBytes, int BlockSize, int Blocks, int DirectoryEntries, int DirectoryBlocks)
{
    /// <summary>
    ///  Gets the Kaypro II's, as its ROM's disk table gives it: one reserved track of ten 512-byte sectors, 195 1K blocks,
    ///  and 64 entries in blocks 0 and 1. AL0 (<c>$F0</c>) reserves blocks 0 to 3, as the system goes on in blocks 2 and
    ///  3: the ROM's boot reads it from track 1's record 16 (<c>TRACK_1_FIRST_RECORD</c> in Kaypro2.asm).
    /// </summary>
    public static CpmGeometry KayproII { get; } = new(
        ReservedTracks: 1,
        TrackBytes: 10 * 512,
        BlockSize: 1024,
        Blocks: 195,
        DirectoryEntries: 64,
        DirectoryBlocks: 4);

    /// <summary>
    ///  Gets where a block starts in the image.
    /// </summary>
    /// <param name="block">The block.</param>
    /// <returns>Its offset.</returns>
    public int BlockOffset(int block) => (ReservedTracks * TrackBytes) + (block * BlockSize);
}
