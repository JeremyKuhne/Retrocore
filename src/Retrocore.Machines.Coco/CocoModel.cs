// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Coco;

/// <summary>
///  A model of the TRS-80 Color Computer.
/// </summary>
public enum CocoModel : byte
{
    /// <summary>
    ///  The Color Computer of 1980: an MC6809E, the MC6883 SAM, the MC6847 VDG, 4 to 64 KB of RAM, and Color
    ///  BASIC with an optional Extended Color BASIC.
    /// </summary>
    Coco1,

    /// <summary>
    ///  The Color Computer 2 of 1983: the same design on a smaller board, with 16 or 64 KB; the 2B has the
    ///  MC6847T1 with lowercase and Color BASIC 1.3.
    /// </summary>
    Coco2,

    /// <summary>
    ///  The Color Computer 3 of 1986: the GIME in place of the SAM and VDG, 128 or 512 KB, 40 and 80 columns,
    ///  and a 32 KB ROM with Super Extended Color BASIC.
    /// </summary>
    Coco3
}
