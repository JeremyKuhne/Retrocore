// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Trs80;

/// <summary>
///  The regions of the Model I's address space.
/// </summary>
public enum Trs80MemoryArea
{
    /// <summary>
    ///  BASIC in ROM.
    /// </summary>
    Rom,

    /// <summary>
    ///  Addresses nothing answers, which read <c>$FF</c>.
    /// </summary>
    Unmapped,

    /// <summary>
    ///  The Expansion Interface's latches, printer and disk controller at <c>$37E0</c>-<c>$37FF</c>.
    /// </summary>
    ExpansionInterface,

    /// <summary>
    ///  The keyboard matrix at <c>$3800</c>-<c>$3BFF</c>.
    /// </summary>
    Keyboard,

    /// <summary>
    ///  Video RAM at <c>$3C00</c>-<c>$3FFF</c>.
    /// </summary>
    Video,

    /// <summary>
    ///  RAM from <c>$4000</c>.
    /// </summary>
    Ram
}
