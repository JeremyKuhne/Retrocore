// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Trs80.Chips;

/// <summary>
///  One of a <see cref="Z80Pio"/>'s two ports.
/// </summary>
/// <param name="input">Reads the port's input pins.</param>
/// <param name="sink">Takes what the port outputs, or null.</param>
internal sealed class Z80PioPort(Func<byte> input, Action<byte>? sink)
{
    /// <summary>
    ///  Gets the reader of the port's input pins.
    /// </summary>
    public Func<byte> Input { get; } = input;

    /// <summary>
    ///  Gets what takes the port's output, or null.
    /// </summary>
    public Action<byte>? Sink { get; } = sink;

    /// <summary>
    ///  Gets or sets the mode, 0-3.
    /// </summary>
    public int Mode { get; set; } = 1;

    /// <summary>
    ///  Gets or sets the output latch.
    /// </summary>
    public byte Output { get; set; }

    /// <summary>
    ///  Gets or sets mode 3's directions: a set bit is an input.
    /// </summary>
    public byte Direction { get; set; } = 0xFF;

    /// <summary>
    ///  Gets or sets mode 3's interrupt mask: a set bit is not watched.
    /// </summary>
    public byte Mask { get; set; } = 0xFF;

    /// <summary>
    ///  Gets or sets the interrupt vector.
    /// </summary>
    public byte Vector { get; set; }

    /// <summary>
    ///  Gets or sets whether the next control word is mode 3's directions.
    /// </summary>
    public bool AwaitingDirection { get; set; }

    /// <summary>
    ///  Gets or sets whether the next control word is the interrupt mask.
    /// </summary>
    public bool AwaitingMask { get; set; }

    /// <summary>
    ///  Gets or sets whether the port interrupts.
    /// </summary>
    public bool Enabled { get; set; }

    /// <summary>
    ///  Gets or sets whether every watched bit must be active (AND) rather than any (OR).
    /// </summary>
    public bool All { get; set; }

    /// <summary>
    ///  Gets or sets whether a watched bit is active high.
    /// </summary>
    public bool High { get; set; }

    /// <summary>
    ///  Gets or sets whether the watched bits matched at the last check.
    /// </summary>
    public bool Matched { get; set; }

    /// <summary>
    ///  Gets or sets whether the port requests an interrupt.
    /// </summary>
    public bool Pending { get; set; }

    /// <summary>
    ///  Gets or sets whether the port's interrupt is being serviced.
    /// </summary>
    public bool InService { get; set; }
}
