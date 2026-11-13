// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Apple1;

/// <summary>
///  The regions of the Apple-1's address space.
/// </summary>
public enum Apple1MemoryArea
{
    /// <summary>
    ///  Addresses nothing answers, which read the high byte of the address, the last byte the 6502 fetched for
    ///  most instructions that reach them.
    /// </summary>
    Unmapped,

    /// <summary>
    ///  RAM: from <c>$0000</c>, and the 4K bank at <c>$E000</c> where BASIC runs.
    /// </summary>
    Ram,

    /// <summary>
    ///  The cassette interface's tape flip-flop and input at <c>$C000</c>-<c>$C0FF</c>.
    /// </summary>
    CassetteInterface,

    /// <summary>
    ///  The cassette interface's PROM at <c>$C100</c>-<c>$C1FF</c>.
    /// </summary>
    CassetteRom,

    /// <summary>
    ///  The 6821 PIA's keyboard and display registers at <c>$D010</c>-<c>$D013</c>, repeated through
    ///  <c>$D000</c>-<c>$DFFF</c> wherever address bit 4 is set.
    /// </summary>
    Pia,

    /// <summary>
    ///  The Monitor's PROMs at <c>$FF00</c>-<c>$FFFF</c>, repeated through <c>$F000</c>-<c>$FFFF</c>.
    /// </summary>
    Monitor
}
