// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Commodore.Serial;

/// <summary>
///  One device's connection to the <see cref="SerialBus"/>: the lines it pulls low.
/// </summary>
public sealed class SerialPort
{
    /// <summary>
    ///  Gets or sets the lines the device pulls low.
    /// </summary>
    public SerialLines Low { get; set; }

    /// <summary>
    ///  Pulls a line low or releases it.
    /// </summary>
    /// <param name="line">The line.</param>
    /// <param name="low">Whether the device pulls it low.</param>
    public void Pull(SerialLines line, bool low) => Low = low ? Low | line : Low & ~line;
}
