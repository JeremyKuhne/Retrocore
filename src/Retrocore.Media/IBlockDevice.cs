// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Media;

/// <summary>
///  Supplies 512-byte blocks to the IIe's development-oriented slot-seven disk card.
///  Image parsing and stream ownership remain the caller's responsibility.
/// </summary>
public interface IBlockDevice
{
    /// <summary>
    ///  Gets the number of available blocks.
    /// </summary>
    uint BlockCount { get; }

    /// <summary>
    ///  Gets whether writes are prohibited.
    /// </summary>
    bool IsReadOnly { get; }

    /// <summary>
    ///  Reads one block.
    /// </summary>
    /// <param name="block">The zero-based block number.</param>
    /// <param name="destination">Exactly 512 destination bytes.</param>
    void ReadBlock(uint block, Span<byte> destination);

    /// <summary>
    ///  Writes one block.
    /// </summary>
    /// <param name="block">The zero-based block number.</param>
    /// <param name="source">Exactly 512 source bytes.</param>
    void WriteBlock(uint block, ReadOnlySpan<byte> source);
}
