// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug;

/// <summary>
///  The memory the SoftCard's Z80 runs from, as its view reports areas. One area of its own keeps Z80 code's debug
///  modules apart from the 6502's at the same numbers, whatever Apple memory the card's translation reaches.
/// </summary>
internal enum SoftCardMemoryArea
{
    /// <summary>
    ///  No memory.
    /// </summary>
    None,

    /// <summary>
    ///  The Z80's 64K, through the card's translation.
    /// </summary>
    Z80
}
