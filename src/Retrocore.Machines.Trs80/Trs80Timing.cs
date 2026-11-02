// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Trs80;

/// <summary>
///  The Model I's clocks, in Z80 T-states.
/// </summary>
public static class Trs80Timing
{
    /// <summary>
    ///  T-states per second: the 10.6445 MHz crystal divided by six.
    /// </summary>
    public const int ClockHertz = 1_774_080;

    /// <summary>
    ///  T-states per scanline.
    /// </summary>
    public const int CyclesPerLine = 112;

    /// <summary>
    ///  Scanlines per frame, at 60 frames a second.
    /// </summary>
    public const int LinesPerFrame = 264;

    /// <summary>
    ///  T-states per frame.
    /// </summary>
    public const int CyclesPerFrame = CyclesPerLine * LinesPerFrame;

    /// <summary>
    ///  T-states between the Expansion Interface's 40 Hz clock interrupts.
    /// </summary>
    public const int CyclesPerTick = ClockHertz / 40;

    /// <summary>
    ///  T-states per millisecond.
    /// </summary>
    public const int CyclesPerMillisecond = ClockHertz / 1000;
}
