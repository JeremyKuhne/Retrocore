// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Atari;

/// <summary>
///  The video chip that takes ANTIC's playfield and adds the colours and the players and missiles.
/// </summary>
public enum AtariGraphicsChip
{
    /// <summary>
    ///  The GTIA, in all but the earliest machines: the CTIA plus three modes of up to 16 colours (BASIC's <c>GRAPHICS 9</c>-<c>11</c>).
    /// </summary>
    Gtia,

    /// <summary>
    ///  The CTIA of the first 400s and 800s, which ignores <c>PRIOR</c> bits 6 and 7.
    /// </summary>
    Ctia
}
