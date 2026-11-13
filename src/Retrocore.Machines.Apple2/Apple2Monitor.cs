// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Apple2;

/// <summary>
///  The monitor the video is shown on.
/// </summary>
/// <remarks>
///  <para>
///   A color monitor turns each run of dots into a color, which blurs double hi-res text and pictures drawn for a
///   monochrome screen, as the mouse desktops are. A monochrome monitor shows every one of the 560 dots as its own,
///   lit in the phosphor's color.
///  </para>
/// </remarks>
public enum Apple2Monitor
{
    /// <summary>
    ///  A color monitor or television: lookup colors, as the video has always drawn them.
    /// </summary>
    Color,

    /// <summary>
    ///  A green-phosphor monochrome monitor, such as the Monitor II.
    /// </summary>
    Green,

    /// <summary>
    ///  An amber-phosphor monochrome monitor.
    /// </summary>
    Amber,

    /// <summary>
    ///  A white-phosphor monochrome monitor, such as the Monitor /// or the IIc's.
    /// </summary>
    White,

    /// <summary>
    ///  An RGB color monitor on a IIe's RGB card: no color fringing. In hi-res, neighbouring lit dots are white to
    ///  their edges, a lone dot is its color, and the gap between lone dots is filled with their color, without the
    ///  half-dot delay; text is white on black. Lo-res and double hi-res are as on <see cref="Color"/>.
    /// </summary>
    ColorRgb
}
