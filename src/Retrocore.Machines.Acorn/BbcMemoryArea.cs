// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Acorn;

/// <summary>
///  What backs an address on the BBC Micro.
/// </summary>
public enum BbcMemoryArea
{
    /// <summary>
    ///  Nothing: RAM a Model A lacks.
    /// </summary>
    None,

    /// <summary>
    ///  RAM.
    /// </summary>
    Ram,

    /// <summary>
    ///  The paged (sideways) ROM in socket 0, at <c>$8000-$BFFF</c> while ROMSEL selects it: ROM 0, 4, 8 or 12.
    /// </summary>
    PagedRom0,

    /// <summary>
    ///  The paged ROM in socket 1: ROM 1, 5, 9 or 13.
    /// </summary>
    PagedRom1,

    /// <summary>
    ///  The paged ROM in socket 2: ROM 2, 6, 10 or 14.
    /// </summary>
    PagedRom2,

    /// <summary>
    ///  The paged ROM in socket 3, BASIC's on the Model B: ROM 3, 7, 11 or 15.
    /// </summary>
    PagedRom3,

    /// <summary>
    ///  The MOS, at <c>$C000-$FBFF</c> and <c>$FF00-$FFFF</c>.
    /// </summary>
    Mos,

    /// <summary>
    ///  FRED and JIM, the 1 MHz bus's pages at <c>$FC00-$FDFF</c>.
    /// </summary>
    OneMegahertzBus,

    /// <summary>
    ///  SHEILA, the internal I/O at <c>$FE00-$FEFF</c>.
    /// </summary>
    Sheila
}
