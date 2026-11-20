// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Altair;

/// <summary>
///  What backs an Altair address.
/// </summary>
public enum AltairMemoryArea
{
    /// <summary>
    ///  Nothing: the S-100 bus floats, and reads return $FF.
    /// </summary>
    None,

    /// <summary>
    ///  RAM.
    /// </summary>
    Ram,

    /// <summary>
    ///  The disk boot loader PROM, DBL, at $FF00.
    /// </summary>
    Dbl,

    /// <summary>
    ///  The multi-boot loader PROM, MBL, at $FE00.
    /// </summary>
    Mbl
}
