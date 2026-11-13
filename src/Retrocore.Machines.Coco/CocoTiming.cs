// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Coco;

/// <summary>
///  The Color Computer's clocks, from its 14.31818 MHz crystal.
/// </summary>
/// <remarks>
///  <para>
///   Time is counted in units of eight crystal periods, one fast CPU cycle (1.79 MHz). A slow cycle (0.89 MHz),
///   the rate after reset, is two units. A scanline is 912 crystal periods, 228 VDG clocks: 114 units, or 57 slow
///   cycles. An NTSC field is 262 lines.
///  </para>
/// </remarks>
public static class CocoTiming
{
    /// <summary>
    ///  The crystal frequency in hertz.
    /// </summary>
    public const double CrystalHertz = 14_318_181.8;

    /// <summary>
    ///  The CPU clock at the slow rate, in hertz: the crystal over 16.
    /// </summary>
    public const double ClockHertz = CrystalHertz / 16;

    /// <summary>
    ///  Time units in a slow CPU cycle.
    /// </summary>
    public const int UnitsPerSlowCycle = 2;

    /// <summary>
    ///  Time units in a scanline.
    /// </summary>
    public const int UnitsPerLine = 114;

    /// <summary>
    ///  Slow CPU cycles in a scanline.
    /// </summary>
    public const int CyclesPerLine = UnitsPerLine / UnitsPerSlowCycle;

    /// <summary>
    ///  Scanlines in an NTSC field.
    /// </summary>
    public const int LinesPerField = 262;

    /// <summary>
    ///  Slow CPU cycles in a field, about 1/60 second.
    /// </summary>
    public const int CyclesPerFrame = CyclesPerLine * LinesPerField;

    /// <summary>
    ///  Slow CPU cycles in a millisecond, rounded.
    /// </summary>
    public const int CyclesPerMillisecond = 895;
}
