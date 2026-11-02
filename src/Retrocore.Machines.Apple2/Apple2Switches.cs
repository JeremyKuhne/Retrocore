// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Apple2;

/// <summary>
///  IIe memory and display soft-switch state.
/// </summary>
[Flags]
public enum Apple2Switches : ushort
{
    /// <summary>
    ///  All switches are clear.
    /// </summary>
    None = 0,

    /// <summary>
    ///  Text display is selected.
    /// </summary>
    Text = 1,

    /// <summary>
    ///  Bottom four rows display text in graphics mode.
    /// </summary>
    Mixed = 2,

    /// <summary>
    ///  Display page two is selected.
    /// </summary>
    Page2 = 4,

    /// <summary>
    ///  High-resolution graphics addressing is selected.
    /// </summary>
    HiRes = 8,

    /// <summary>
    ///  Display-page accesses select main or auxiliary RAM through PAGE2.
    /// </summary>
    Store80 = 16,

    /// <summary>
    ///  General RAM reads use auxiliary memory.
    /// </summary>
    RamRead = 32,

    /// <summary>
    ///  General RAM writes use auxiliary memory.
    /// </summary>
    RamWrite = 64,

    /// <summary>
    ///  Zero page, stack, and language-card memory use auxiliary RAM.
    /// </summary>
    AltZeroPage = 128,

    /// <summary>
    ///  Internal firmware is selected in C100-CFFF.
    /// </summary>
    InternalCxRom = 256,

    /// <summary>
    ///  Slot-three firmware is selected instead of internal firmware.
    /// </summary>
    SlotC3Rom = 512,

    /// <summary>
    ///  Eighty-column text is selected.
    /// </summary>
    Column80 = 1024,

    /// <summary>
    ///  Alternate character set is selected.
    /// </summary>
    AlternateCharacters = 2048,

    /// <summary>
    ///  Double graphics is enabled through annunciator three: C05E enables, C05F disables.
    ///  Eighty-column mode must also be selected for double hi-res or double lo-res.
    /// </summary>
    DoubleHiRes = 4096
}
