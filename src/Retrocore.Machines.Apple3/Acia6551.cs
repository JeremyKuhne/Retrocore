// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Apple3;

/// <summary>
///  The Apple III's built-in serial port, a 6551 ACIA at <c>$C0F0-$C0F3</c>, with nothing attached.
/// </summary>
/// <remarks>
///  <para>
///   Only the registers, as software sees them with no cable: the transmitter is always empty and nothing is ever
///   received. The boot ROM checks the reset values.
///  </para>
/// </remarks>
public sealed class Acia6551
{
    // Status: transmit data register empty.
    private const byte TransmitEmpty = 0x10;

    /// <summary>
    ///  Constructs a reset ACIA.
    /// </summary>
    public Acia6551() => Reset();

    /// <summary>
    ///  Gets the command register.
    /// </summary>
    public byte Command { get; private set; }

    /// <summary>
    ///  Gets the control register.
    /// </summary>
    public byte Control { get; private set; }

    /// <summary>
    ///  Gets the last byte written for transmission.
    /// </summary>
    public byte Transmitted { get; private set; }

    /// <summary>
    ///  Resets as the RES pin does: command and control cleared.
    /// </summary>
    public void Reset()
    {
        Command = 0;
        Control = 0;
    }

    /// <summary>
    ///  Reads a register without side effects; with nothing attached, reading has none.
    /// </summary>
    /// <param name="register">The register, 0-3.</param>
    /// <returns>The value.</returns>
    public byte Read(int register) => (register & 3) switch
    {
        0 => 0,
        1 => TransmitEmpty,
        2 => Command,
        _ => Control
    };

    /// <summary>
    ///  Writes a register.
    /// </summary>
    /// <param name="register">The register, 0-3; writing the status register resets the chip by program.</param>
    /// <param name="value">The value.</param>
    public void Write(int register, byte value)
    {
        switch (register & 3)
        {
            case 0:
                Transmitted = value;
                break;
            case 1:
                // A programmed reset clears the command register's low five bits.
                Command &= 0xE0;
                break;
            case 2:
                Command = value;
                break;
            default:
                Control = value;
                break;
        }
    }
}
