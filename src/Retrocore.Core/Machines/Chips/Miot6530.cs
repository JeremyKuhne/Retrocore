// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Chips;

/// <summary>
///  A MOS Technology 6530 MIOT (Rockwell's RRIOT): 1K of mask ROM, 64 bytes of RAM, two 8-bit ports and an interval
///  timer, whose interrupt comes out on PB7.
/// </summary>
/// <remarks>
///  <para>
///   The machine maps the ROM and RAM itself, and gives <see cref="Read(int)"/> and <see cref="Write(int, byte)"/>
///   the I/O's address bits 0-3. With A2 clear they reach the ports: 0 port A, 1 its direction, 2 port B, 3 its
///   direction. With A2 set, a write loads the timer (A0-A1 the prescaler, A3 its interrupt enable); a read with A0
///   clear reads the timer (A3 its interrupt enable), and with A0 set the interrupt flag in bit 7.
///  </para>
///  <para>
///   While PB7 is an input, the pin is the chip's interrupt output, low while the timer has run out with its
///   interrupt enabled.
///  </para>
/// </remarks>
public sealed class Miot6530 : RiotBase
{
    /// <summary>
    ///  Creates a reset MIOT.
    /// </summary>
    public Miot6530() : base(64)
    {
    }

    /// <inheritdoc/>
    public override bool InterruptRequested => (PortBDirection & 0x80) == 0 && TimerExpired && TimerInterruptEnabled;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   PB7, while an input, drives the interrupt output.
    ///  </para>
    /// </remarks>
    public override byte PortBOutput => InterruptRequested ? (byte)(base.PortBOutput & 0x7F) : base.PortBOutput;

    /// <summary>
    ///  Reads an I/O register as the CPU does.
    /// </summary>
    /// <param name="address">The address's bits 0-3.</param>
    /// <returns>The value.</returns>
    public byte Read(int address)
    {
        if ((address & 0x04) == 0) { return ReadPort(address); }
        return (address & 0x01) == 0 ? ReadTimer((address & 0x08) != 0) : (TimerExpired ? TimerFlag : (byte)0);
    }

    /// <summary>
    ///  Reads an I/O register without side effects.
    /// </summary>
    /// <param name="address">The address's bits 0-3.</param>
    /// <returns>The value.</returns>
    public byte Peek(int address)
    {
        if ((address & 0x04) == 0) { return ReadPort(address); }
        return (address & 0x01) == 0 ? PeekTimer() : (TimerExpired ? TimerFlag : (byte)0);
    }

    /// <summary>
    ///  Writes an I/O register as the CPU does.
    /// </summary>
    /// <param name="address">The address's bits 0-3.</param>
    /// <param name="value">The value.</param>
    public void Write(int address, byte value)
    {
        if ((address & 0x04) == 0)
        {
            WritePort(address, value);
            return;
        }

        WriteTimer(address, value, (address & 0x08) != 0);
    }
}
