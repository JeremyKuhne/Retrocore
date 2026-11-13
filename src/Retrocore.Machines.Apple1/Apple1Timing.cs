// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Apple1;

/// <summary>
///  The Apple-1's clocks, in 6502 cycles.
/// </summary>
public static class Apple1Timing
{
    /// <summary>
    ///  Cycles per second: the 14.31818 MHz crystal divided by fourteen.
    /// </summary>
    public const int ClockHertz = 1_022_727;

    /// <summary>
    ///  Cycles per scanline.
    /// </summary>
    public const int CyclesPerLine = 65;

    /// <summary>
    ///  Scanlines per frame, at 60 frames a second.
    /// </summary>
    public const int LinesPerFrame = 262;

    /// <summary>
    ///  Cycles per frame: the most a character can wait for the terminal to take it.
    /// </summary>
    public const int CyclesPerFrame = CyclesPerLine * LinesPerFrame;

    /// <summary>
    ///  Cycles per millisecond.
    /// </summary>
    public const int CyclesPerMillisecond = ClockHertz / 1000;
}
