// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Trs80Model100;

/// <summary>
///  The Model 100's clocks.
/// </summary>
public static class Trs80Model100Timing
{
    /// <summary>
    ///  The 80C85's clock: the 4.9152 MHz crystal divided by two, 2.4576 MHz.
    /// </summary>
    public const int ClockHertz = 2_457_600;

    /// <summary>
    ///  The CPU cycles in one 60 Hz frame of the display.
    /// </summary>
    public const int CyclesPerFrame = ClockHertz / 60;
}
