// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Kaypro;

/// <summary>
///  The Kaypro II's clocks: the Z80 runs at 2.5 MHz, an eighth of the 20 MHz crystal, and the display's
///  13.9776 MHz dot clock draws 896 dots a line (64.1 microseconds, 160 T-states) and 260 lines a frame (60 Hz).
/// </summary>
public static class KayproTiming
{
    /// <summary>
    ///  The Z80's clock.
    /// </summary>
    public const int ClockHertz = 2_500_000;

    /// <summary>
    ///  The T-states in a scanline.
    /// </summary>
    public const int CyclesPerLine = 160;

    /// <summary>
    ///  The scanlines in a frame, the 240 shown and the 20 of vertical blanking.
    /// </summary>
    public const int LinesPerFrame = 260;

    /// <summary>
    ///  The T-states in a frame.
    /// </summary>
    public const int CyclesPerFrame = CyclesPerLine * LinesPerFrame;

    /// <summary>
    ///  The T-states in a millisecond.
    /// </summary>
    public const int CyclesPerMillisecond = ClockHertz / 1000;
}
