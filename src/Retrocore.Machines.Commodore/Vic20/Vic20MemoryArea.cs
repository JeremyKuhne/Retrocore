// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Commodore.Vic20;

/// <summary>
///  What backs a VIC-20 address.
/// </summary>
public enum Vic20MemoryArea
{
    /// <summary>
    ///  Nothing answers: a read sees the byte the VIC fetched last.
    /// </summary>
    None,

    /// <summary>
    ///  The built-in 5K: <c>$0000-$03FF</c> and <c>$1000-$1FFF</c>.
    /// </summary>
    Ram,

    /// <summary>
    ///  RAM in the expansion port.
    /// </summary>
    ExpansionRam,

    /// <summary>
    ///  A cartridge's ROM, in blocks 1, 2, 3 or 5.
    /// </summary>
    Cartridge,

    /// <summary>
    ///  The 4K character ROM at <c>$8000-$8FFF</c>.
    /// </summary>
    CharacterRom,

    /// <summary>
    ///  The VIC's registers, <c>$9000-$90FF</c>.
    /// </summary>
    Vic,

    /// <summary>
    ///  The two VIAs, <c>$9100-$93FF</c>.
    /// </summary>
    Via,

    /// <summary>
    ///  The 1K × 4 colour RAM at <c>$9400-$97FF</c>.
    /// </summary>
    ColourRam,

    /// <summary>
    ///  BASIC, <c>$C000-$DFFF</c>.
    /// </summary>
    Basic,

    /// <summary>
    ///  The kernal, <c>$E000-$FFFF</c>.
    /// </summary>
    Kernal
}
