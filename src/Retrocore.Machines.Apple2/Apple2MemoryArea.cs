// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Apple2;

/// <summary>
///  Identifies the storage behind an address as the IIe currently maps it, so tools can tell code at the same
///  address apart, such as AppleSoft in ROM at $D000 and ProDOS in language-card RAM.
/// </summary>
public enum Apple2MemoryArea
{
    /// <summary>
    ///  Nothing drives the bus, such as an empty slot's ROM space.
    /// </summary>
    None,

    /// <summary>
    ///  Soft switches and device registers at $C000-$C0FF.
    /// </summary>
    Io,

    /// <summary>
    ///  Main RAM at $0000-$BFFF.
    /// </summary>
    MainRam,

    /// <summary>
    ///  Auxiliary RAM at $0000-$BFFF.
    /// </summary>
    AuxiliaryRam,

    /// <summary>
    ///  Main language-card RAM: $D000-$DFFF bank two and $E000-$FFFF.
    /// </summary>
    MainLanguageCard,

    /// <summary>
    ///  Main language-card RAM: $D000-$DFFF bank one.
    /// </summary>
    MainLanguageCardBank1,

    /// <summary>
    ///  Auxiliary language-card RAM: $D000-$DFFF bank two and $E000-$FFFF.
    /// </summary>
    AuxiliaryLanguageCard,

    /// <summary>
    ///  Auxiliary language-card RAM: $D000-$DFFF bank one.
    /// </summary>
    AuxiliaryLanguageCardBank1,

    /// <summary>
    ///  The motherboard ROM at $C100-$FFFF: internal firmware, the Monitor and AppleSoft.
    /// </summary>
    SystemRom,

    /// <summary>
    ///  Slot one's ROM at $C100-$C1FF.
    /// </summary>
    Slot1Rom,

    /// <summary>
    ///  Slot two's ROM at $C200-$C2FF.
    /// </summary>
    Slot2Rom,

    /// <summary>
    ///  Slot three's ROM at $C300-$C3FF.
    /// </summary>
    Slot3Rom,

    /// <summary>
    ///  Slot four's ROM space at $C400-$C4FF, where the Mockingboard's registers respond.
    /// </summary>
    Slot4Rom,

    /// <summary>
    ///  Slot five's ROM at $C500-$C5FF.
    /// </summary>
    Slot5Rom,

    /// <summary>
    ///  Slot six's ROM at $C600-$C6FF, the Disk II boot ROM when installed.
    /// </summary>
    Slot6Rom,

    /// <summary>
    ///  Slot seven's ROM at $C700-$C7FF, the emulated block device's firmware when a disk is mounted.
    /// </summary>
    Slot7Rom
}
