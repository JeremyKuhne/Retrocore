// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Atari;

/// <summary>
///  The machine's clocks and frame, from ANTIC's counters (Altirra Hardware Reference Manual, 4.2).
/// </summary>
public static class AtariTiming
{
    /// <summary>
    ///  Machine cycles on every scan line, NTSC or PAL.
    /// </summary>
    public const int CyclesPerLine = 114;

    /// <summary>
    ///  Colour clocks on a scan line, two to a machine cycle.
    /// </summary>
    public const int ColorClocksPerLine = CyclesPerLine * 2;

    /// <summary>
    ///  The first scan line ANTIC can display, after vertical blank.
    /// </summary>
    public const int FirstDisplayLine = 8;

    /// <summary>
    ///  The scan line that starts vertical blank and its interrupt; the display list runs on lines 8-247.
    /// </summary>
    public const int VerticalBlankLine = 248;

    /// <summary>
    ///  The first visible colour clock, <c>$22</c>.
    /// </summary>
    public const int FirstVisibleClock = 0x22;

    /// <summary>
    ///  The colour clock just past the last visible one, <c>$DE</c>.
    /// </summary>
    public const int EndVisibleClock = 0xDE;

    /// <summary>
    ///  Gets the scan lines in a frame.
    /// </summary>
    /// <param name="standard">The television standard.</param>
    /// <returns>262 for NTSC, 312 for PAL.</returns>
    public static int LinesPerFrame(AtariVideoStandard standard) => standard == AtariVideoStandard.Pal ? 312 : 262;

    /// <summary>
    ///  Gets the machine clock in hertz.
    /// </summary>
    /// <param name="standard">The television standard.</param>
    /// <returns>1,789,773 for NTSC (half the colour subcarrier) or 1,773,447 for PAL (2/5 of it).</returns>
    public static int CpuHertz(AtariVideoStandard standard) => standard == AtariVideoStandard.Pal ? 1_773_447 : 1_789_773;

    /// <summary>
    ///  Gets the machine cycles in a frame.
    /// </summary>
    /// <param name="standard">The television standard.</param>
    /// <returns>29,868 for NTSC, 35,568 for PAL.</returns>
    public static int CyclesPerFrame(AtariVideoStandard standard) => LinesPerFrame(standard) * CyclesPerLine;
}
