// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Atari;

/// <summary>
///  The television standard: it sets ANTIC's frame length and the clock, and GTIA's <c>PAL</c> register.
/// </summary>
public enum AtariVideoStandard
{
    /// <summary>
    ///  NTSC: 262 lines of 114 cycles at 1.7898 MHz, about 59.92 frames a second.
    /// </summary>
    Ntsc,

    /// <summary>
    ///  PAL: 312 lines of 114 cycles at 1.7734 MHz, about 49.86 frames a second.
    /// </summary>
    Pal
}
