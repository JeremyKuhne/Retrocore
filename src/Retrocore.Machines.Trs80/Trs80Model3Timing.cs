// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Trs80;

/// <summary>
///  The Model III family's clocks. The devices count in the Model III's T-states; a Model 4 running at 4 MHz
///  advances them every other T-state.
/// </summary>
public static class Trs80Model3Timing
{
    /// <summary>
    ///  The Model III's Z80 clock, and the Model 4's slow speed: the 20.2752 MHz crystal divided by ten.
    /// </summary>
    public const int ClockHertz = 2_027_520;

    /// <summary>
    ///  The Model 4's fast speed: the crystal divided by five.
    /// </summary>
    public const int FastClockHertz = 4_055_040;

    /// <summary>
    ///  Device T-states per scanline.
    /// </summary>
    public const int CyclesPerLine = 128;

    /// <summary>
    ///  Scanlines per frame, at 60 frames a second.
    /// </summary>
    public const int LinesPerFrame = 264;

    /// <summary>
    ///  Device T-states per frame.
    /// </summary>
    public const int CyclesPerFrame = CyclesPerLine * LinesPerFrame;

    /// <summary>
    ///  Device T-states between real-time clock interrupts, 30 a second.
    /// </summary>
    public const int CyclesPerTick = ClockHertz / 30;

    /// <summary>
    ///  Device T-states per millisecond.
    /// </summary>
    public const int CyclesPerMillisecond = ClockHertz / 1000;
}
