// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Trs80;

/// <summary>
///  A double-density adapter for the Expansion Interface's disk controller. Each adds a WD1791, hardwired to double
///  density, beside the FD1771.
/// </summary>
[Flags]
public enum Trs80Doubler : byte
{
    /// <summary>
    ///  The FD1771 alone: single density only.
    /// </summary>
    None = 0,

    /// <summary>
    ///  A Percom doubler: writing <c>$FE</c> to the command register selects the FD1771 for single density, and
    ///  <c>$FF</c> the WD1791 for double density.
    /// </summary>
    Percom = 1,

    /// <summary>
    ///  The Radio Shack doubler: writing <c>$A0</c> to the sector register selects the FD1771, and <c>$80</c> the
    ///  WD1791. Its side select (<c>$40</c>, <c>$60</c>) and precompensation (<c>$C0</c>, <c>$E0</c>) values change
    ///  nothing the disk sees.
    /// </summary>
    Tandy = 2,

    /// <summary>
    ///  Both doublers' selects, so that software written for either finds its doubler, as xtrs does by default.
    /// </summary>
    Both = Percom | Tandy
}
