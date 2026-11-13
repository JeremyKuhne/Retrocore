// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Trs80;

/// <summary>
///  The machines of the Model II family, which share the Model II's Z80 board, 8-inch drives and 80x24 display.
/// </summary>
public enum Trs80Model2Variant : byte
{
    /// <summary>
    ///  The Model II (1979).
    /// </summary>
    Model2,

    /// <summary>
    ///  The Model 12 (1982): a Model II with a newer board, thin-line drives and a detached keyboard.
    /// </summary>
    Model12,

    /// <summary>
    ///  The Model 16, 16B and Tandy 6000, as their Z80 side sees them. Their 68000 board is not emulated, so they
    ///  run what a Model II or 12 runs, such as TRSDOS-II, and not TRS-XENIX.
    /// </summary>
    Model16
}
