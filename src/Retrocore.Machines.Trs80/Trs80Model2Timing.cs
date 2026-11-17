// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Trs80;

/// <summary>
///  The Model II family's clocks, in Z80 T-states.
/// </summary>
public static class Trs80Model2Timing
{
    /// <summary>
    ///  T-states per second: the 8 MHz crystal divided by two.
    /// </summary>
    public const int ClockHertz = 4_000_000;

    /// <summary>
    ///  T-states per scanline.
    /// </summary>
    public const int CyclesPerLine = 256;

    /// <summary>
    ///  Scanlines per frame, at about 60 frames a second.
    /// </summary>
    public const int LinesPerFrame = 260;

    /// <summary>
    ///  T-states per frame.
    /// </summary>
    public const int CyclesPerFrame = CyclesPerLine * LinesPerFrame;

    /// <summary>
    ///  T-states per millisecond.
    /// </summary>
    public const int CyclesPerMillisecond = ClockHertz / 1000;
}
