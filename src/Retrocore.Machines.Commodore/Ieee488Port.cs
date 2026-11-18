// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Commodore;

/// <summary>
///  One device's connection to the <see cref="Ieee488Bus"/>: what it drives onto the lines.
/// </summary>
public sealed class Ieee488Port
{
    /// <summary>
    ///  Gets or sets what the device drives on the data lines, DIO1 in bit 0: a 0 pulls the line low.
    /// </summary>
    public byte Data { get; set; } = 0xFF;

    /// <summary>
    ///  Gets or sets the control lines the device pulls low.
    /// </summary>
    public Ieee488Lines Low { get; set; }

    /// <summary>
    ///  Pulls a control line low or releases it.
    /// </summary>
    /// <param name="line">The line.</param>
    /// <param name="high">Whether the device releases it.</param>
    public void Drive(Ieee488Lines line, bool high) => Low = high ? Low & ~line : Low | line;
}
