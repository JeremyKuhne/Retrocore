// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Chips;

/// <summary>
///  The video standard of a Commodore video chip, which sets its line and frame timing and the machine's clock.
/// </summary>
public enum VicVideoStandard
{
    /// <summary>
    ///  NTSC-M: the 6560 in the VIC-20, the 6567 in the 64.
    /// </summary>
    Ntsc,

    /// <summary>
    ///  PAL-B: the 6561 in the VIC-20, the 6569 in the 64.
    /// </summary>
    Pal
}
