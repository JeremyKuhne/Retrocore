// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Trs80;

/// <summary>
///  The regions of the Model III family's address space, which on a Model 4 depend on the memory map selected.
/// </summary>
public enum Trs80Model3MemoryArea
{
    /// <summary>
    ///  The ROM: the Model III ROM, or the Model 4P's boot ROM.
    /// </summary>
    Rom,

    /// <summary>
    ///  Addresses nothing answers, which read <c>$FF</c>.
    /// </summary>
    Unmapped,

    /// <summary>
    ///  The printer status at <c>$37E8</c>-<c>$37E9</c>, in memory maps 0 and 1.
    /// </summary>
    Printer,

    /// <summary>
    ///  The keyboard matrix: <c>$3800</c>-<c>$3BFF</c>, or <c>$F400</c>-<c>$F7FF</c> in a Model 4's map 2.
    /// </summary>
    Keyboard,

    /// <summary>
    ///  Video RAM: <c>$3C00</c>-<c>$3FFF</c>, or <c>$F800</c>-<c>$FFFF</c> in a Model 4's map 2.
    /// </summary>
    Video,

    /// <summary>
    ///  RAM.
    /// </summary>
    Ram
}
