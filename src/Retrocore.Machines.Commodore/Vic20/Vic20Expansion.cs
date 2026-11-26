// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Commodore.Vic20;

/// <summary>
///  The RAM added in the VIC-20's expansion port, by the blocks the port decodes.
/// </summary>
/// <remarks>
///  <para>
///   Commodore's cartridges filled these: the VIC-1210 3K at <c>$0400-$0FFF</c>, the VIC-1110 8K in one of blocks 1-3,
///   and the VIC-1111 16K in blocks 1 and 2. Expansion boards held several. With RAM in block 1 the kernal moves the
///   screen to <c>$1000</c> and starts BASIC at <c>$1201</c>, leaving the 3K unused.
///  </para>
/// </remarks>
[Flags]
public enum Vic20Expansion
{
    /// <summary>
    ///  The unexpanded machine: 5K.
    /// </summary>
    None = 0,

    /// <summary>
    ///  3K at <c>$0400-$0FFF</c> (RAM1-RAM3), as the VIC-1210 adds.
    /// </summary>
    Ram3K = 1,

    /// <summary>
    ///  8K at <c>$2000-$3FFF</c>.
    /// </summary>
    Block1 = 2,

    /// <summary>
    ///  8K at <c>$4000-$5FFF</c>.
    /// </summary>
    Block2 = 4,

    /// <summary>
    ///  8K at <c>$6000-$7FFF</c>.
    /// </summary>
    Block3 = 8,

    /// <summary>
    ///  8K at <c>$A000-$BFFF</c>, where cartridges go; BASIC does not use it.
    /// </summary>
    Block5 = 16,

    /// <summary>
    ///  8K in block 1, as a VIC-1110 adds.
    /// </summary>
    Ram8K = Block1,

    /// <summary>
    ///  16K in blocks 1 and 2, as a VIC-1111 adds.
    /// </summary>
    Ram16K = Block1 | Block2,

    /// <summary>
    ///  24K in blocks 1-3: the most BASIC can use.
    /// </summary>
    Ram24K = Block1 | Block2 | Block3,

    /// <summary>
    ///  Every block: 3K, 24K and block 5.
    /// </summary>
    All = Ram3K | Ram24K | Block5
}
