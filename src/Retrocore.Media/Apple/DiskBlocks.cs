// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Media;

/// <summary>
///  The 512-byte blocks of a 140K disk image, as SOS, ProDOS and Apple Pascal number them: block n is two sectors of
///  track n / 8.
/// </summary>
internal static class DiskBlocks
{
    /// <summary>
    ///  The size of a block.
    /// </summary>
    internal const int BlockSize = 512;

    /// <summary>
    ///  The size of a 140K image.
    /// </summary>
    internal const int DiskSize = 35 * 16 * 256;

    // Where a block's two halves are on a DOS-order image: ProDOS sector n of a track is this DOS sector.
    private static ReadOnlySpan<byte> DosSectors => [0x0, 0xE, 0xD, 0xC, 0xB, 0xA, 0x9, 0x8, 0x7, 0x6, 0x5, 0x4, 0x3, 0x2, 0x1, 0xF];

    /// <summary>
    ///  Reads a block.
    /// </summary>
    /// <param name="image">The 140K image.</param>
    /// <param name="proDosOrder">Whether the image's sectors are in ProDOS order rather than DOS order.</param>
    /// <param name="block">The block number, 0-279.</param>
    /// <returns>Its 512 bytes.</returns>
    internal static byte[] Read(byte[] image, bool proDosOrder, int block)
    {
        ArgumentOutOfRangeException.ThrowIfNegative(block);
        ArgumentOutOfRangeException.ThrowIfGreaterThanOrEqual(block, DiskSize / BlockSize);
        if (proDosOrder) { return image.AsSpan(block * BlockSize, BlockSize).ToArray(); }

        byte[] data = new byte[BlockSize];
        int track = block / 8;
        int half = block % 8;
        for (int part = 0; part < 2; part++)
        {
            int sector = DosSectors[(half * 2) + part];
            image.AsSpan(((track * 16) + sector) * 256, 256).CopyTo(data.AsSpan(part * 256));
        }

        return data;
    }
}
