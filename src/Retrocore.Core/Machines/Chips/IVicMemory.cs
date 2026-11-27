// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Chips;

/// <summary>
///  What a <see cref="Vic6560"/> reads: its own 14-bit address space, which the machine maps onto its memory, and the
///  colour RAM's 4-bit nybbles.
/// </summary>
public interface IVicMemory
{
    /// <summary>
    ///  Reads a byte the chip fetches, a character code or a character's row of dots.
    /// </summary>
    /// <param name="address">The chip's address, <c>$0000-$3FFF</c>.</param>
    /// <returns>The byte.</returns>
    byte FetchVideo(int address);

    /// <summary>
    ///  Reads the colour nybble the chip fetches beside a character code.
    /// </summary>
    /// <param name="address">The colour RAM address, <c>$000-$3FF</c>: the code's address's low ten bits.</param>
    /// <returns>The nybble, in bits 0-3.</returns>
    byte FetchColour(int address);
}
