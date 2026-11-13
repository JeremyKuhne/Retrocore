// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Trs80.Chips;

/// <summary>
///  One of a <see cref="Z80Ctc"/>'s four channels.
/// </summary>
internal sealed class Z80CtcChannel
{
    /// <summary>
    ///  Gets or sets the last control word.
    /// </summary>
    public byte Control { get; set; }

    /// <summary>
    ///  Gets or sets the time constant, 1-256.
    /// </summary>
    public int Constant { get; set; }

    /// <summary>
    ///  Gets or sets the down counter.
    /// </summary>
    public int Counter { get; set; }

    /// <summary>
    ///  Gets or sets the clocks left before the timer counts down.
    /// </summary>
    public int Prescaler { get; set; } = 16;

    /// <summary>
    ///  Gets or sets whether the next write is the time constant.
    /// </summary>
    public bool AwaitingConstant { get; set; }

    /// <summary>
    ///  Gets or sets whether the channel counts.
    /// </summary>
    public bool Running { get; set; }

    /// <summary>
    ///  Gets or sets whether the channel requests an interrupt.
    /// </summary>
    public bool Pending { get; set; }

    /// <summary>
    ///  Gets or sets whether the channel's interrupt is being serviced.
    /// </summary>
    public bool InService { get; set; }

    /// <summary>
    ///  Gets or sets the CLK/TRG input's level.
    /// </summary>
    public bool Input { get; set; }
}
