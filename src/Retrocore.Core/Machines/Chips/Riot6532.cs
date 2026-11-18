// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Chips;

/// <summary>
///  A MOS Technology 6532 RIOT: 128 bytes of RAM, two 8-bit ports, an interval timer, and an interrupt on an edge of
///  PA7.
/// </summary>
/// <remarks>
///  <para>
///   The machine maps the RAM itself, and gives <see cref="Read(int)"/> and <see cref="Write(int, byte)"/> the I/O's
///   address bits 0-4. With A2 clear they reach the ports: 0 port A, 1 its direction, 2 port B, 3 its direction.
///   With A2 set, a write with A4 set loads the timer (A0-A1 the prescaler, A3 its interrupt enable), and one with A4
///   clear sets PA7's edge (A0 rising) and its interrupt enable (A1). A read with A2 set and A0 clear reads the timer
///   (A3 its interrupt enable), and with A0 set the interrupt flags, bit 7 the timer's and bit 6 PA7's edge, which
///   the read clears.
///  </para>
/// </remarks>
public sealed class Riot6532 : RiotBase
{
    private bool _edgeRising;
    private bool _edgeEnabled;

    // PA7's level as last seen.
    private bool _pa7;

    /// <summary>
    ///  Creates a reset RIOT.
    /// </summary>
    public Riot6532() : base(128)
    {
    }

    /// <summary>
    ///  Gets whether PA7 has seen its edge since the flags were last read.
    /// </summary>
    public bool EdgeSeen { get; private set; }

    /// <inheritdoc/>
    public override bool InterruptRequested =>
        (TimerExpired && TimerInterruptEnabled) || (EdgeSeen && _edgeEnabled);

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   PA7's level at reset is the one its edges are then seen from.
    ///  </para>
    /// </remarks>
    public override void Reset()
    {
        base.Reset();
        _edgeEnabled = false;
        _edgeRising = false;
        EdgeSeen = false;
        _pa7 = (PortAInput & 0x80) != 0;
    }

    /// <summary>
    ///  Reads an I/O register as the CPU does.
    /// </summary>
    /// <param name="address">The address's bits 0-4.</param>
    /// <returns>The value.</returns>
    public byte Read(int address)
    {
        if ((address & 0x04) == 0) { return ReadPort(address); }
        if ((address & 0x01) == 0) { return ReadTimer((address & 0x08) != 0); }
        byte flags = Flags;
        EdgeSeen = false;
        return flags;
    }

    /// <summary>
    ///  Reads an I/O register without side effects.
    /// </summary>
    /// <param name="address">The address's bits 0-4.</param>
    /// <returns>The value.</returns>
    public byte Peek(int address) => (address & 0x04) == 0
        ? ReadPort(address)
        : (address & 0x01) == 0 ? PeekTimer() : Flags;

    /// <summary>
    ///  Writes an I/O register as the CPU does.
    /// </summary>
    /// <param name="address">The address's bits 0-4.</param>
    /// <param name="value">The value.</param>
    public void Write(int address, byte value)
    {
        if ((address & 0x04) == 0)
        {
            WritePort(address, value);
            DetectEdge();
        }
        else if ((address & 0x10) != 0)
        {
            WriteTimer(address, value, (address & 0x08) != 0);
        }
        else
        {
            _edgeRising = (address & 0x01) != 0;
            _edgeEnabled = (address & 0x02) != 0;
        }
    }

    /// <summary>
    ///  Sets the levels on port A's pins from outside, watching PA7 for its edge.
    /// </summary>
    /// <param name="value">The levels.</param>
    public void SetPortA(byte value)
    {
        PortAInput = value;
        DetectEdge();
    }

    private byte Flags => (byte)((TimerExpired ? TimerFlag : 0) | (EdgeSeen ? EdgeFlag : 0));

    // PA7 as the pin sees it, an output or an input; the chosen edge sets the flag.
    private void DetectEdge()
    {
        bool pa7 = (((PortAData & PortADirection) | (PortAInput & ~PortADirection)) & 0x80) != 0;
        if (pa7 != _pa7 && pa7 == _edgeRising) { EdgeSeen = true; }
        _pa7 = pa7;
    }
}
