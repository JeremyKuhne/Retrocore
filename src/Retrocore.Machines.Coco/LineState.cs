// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Coco;

/// <summary>
///  What a CoCo 3 scanline showed, captured as it started.
/// </summary>
internal readonly record struct LineState
{
    /// <summary>
    ///  Gets whether the line was in the CoCo 1 and 2 compatible mode.
    /// </summary>
    public bool Legacy { get; init; }

    /// <summary>
    ///  Gets <c>$FF98</c>.
    /// </summary>
    public byte Mode { get; init; }

    /// <summary>
    ///  Gets <c>$FF99</c>.
    /// </summary>
    public byte Resolution { get; init; }

    /// <summary>
    ///  Gets PIA 1's VDG mode bits.
    /// </summary>
    public byte VdgMode { get; init; }

    /// <summary>
    ///  Gets the SAM's video mode.
    /// </summary>
    public byte SamMode { get; init; }

    /// <summary>
    ///  Gets <c>$FF9C</c>.
    /// </summary>
    public byte VerticalScroll { get; init; }

    /// <summary>
    ///  Gets <c>$FF9F</c>.
    /// </summary>
    public byte HorizontalOffset { get; init; }

    /// <summary>
    ///  Gets the physical address of the line's row.
    /// </summary>
    public int Position { get; init; }

    /// <summary>
    ///  Gets the line within its character row.
    /// </summary>
    public byte LineInRow { get; init; }

    /// <summary>
    ///  Gets whether blinking text was blank.
    /// </summary>
    public bool Blink { get; init; }
}
