// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Commodore;

/// <summary>
///  The PET 2001's clock and video timing.
/// </summary>
/// <remarks>
///  <para>
///   The 6502 runs at 1 MHz (8 MHz / 8). A line is 64 cycles, and a frame 260 lines, 16,640 cycles, about 60.1
///   frames a second. The signal the schematics call VIDEO ON is low for the first 3,840 cycles of a frame (60 lines
///   of vertical blanking) and high for the 200 lines of the display. On each displayed line the 40 characters are
///   drawn from cycle 23, one a cycle.
///  </para>
/// </remarks>
public static class PetTiming
{
    /// <summary>
    ///  The CPU clock in hertz.
    /// </summary>
    public const int CpuHertz = 1_000_000;

    /// <summary>
    ///  The cycles in one line.
    /// </summary>
    public const int CyclesPerLine = 64;

    /// <summary>
    ///  The lines in one frame.
    /// </summary>
    public const int LinesPerFrame = 260;

    /// <summary>
    ///  The cycles in one frame.
    /// </summary>
    public const int CyclesPerFrame = CyclesPerLine * LinesPerFrame;

    /// <summary>
    ///  The cycles of vertical blanking that start each frame, while VIDEO ON is low.
    /// </summary>
    public const int BlankingCycles = 3_840;

    /// <summary>
    ///  The displayed lines: 25 rows of 8.
    /// </summary>
    public const int DisplayLines = 200;

    /// <summary>
    ///  The cycle in a displayed line at which the first character is drawn.
    /// </summary>
    public const int FirstColumnCycle = 23;
}
