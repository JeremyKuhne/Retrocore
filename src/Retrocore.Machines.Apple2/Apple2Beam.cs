// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Apple2;

/// <summary>
///  NTSC beam coordinates. Cycle zero is the start of horizontal blanking on visible line zero.
///  Visible fetches occupy column clocks 25 through 64; vertical blanking starts on line 192.
/// </summary>
/// <param name="Scanline">The line, from zero through 261.</param>
/// <param name="ColumnClock">The CPU clock within the line, from zero through 64.</param>
/// <param name="CycleInFrame">The CPU clock within the 17030-cycle frame.</param>
public readonly record struct Apple2Beam(int Scanline, int ColumnClock, int CycleInFrame)
{
    /// <summary>
    ///  Gets whether the beam is horizontally blanked.
    /// </summary>
    public bool HorizontalBlank => ColumnClock < 25;

    /// <summary>
    ///  Gets whether the beam is vertically blanked.
    /// </summary>
    public bool VerticalBlank => Scanline >= 192;
}
