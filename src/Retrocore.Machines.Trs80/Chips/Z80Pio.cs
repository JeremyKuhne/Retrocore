// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Trs80.Chips;

/// <summary>
///  A Z80 PIO: two 8-bit ports, A and B, each in output (mode 0), input (1), bidirectional (2) or bit control
///  (3) mode, with an interrupt vector each.
/// </summary>
/// <remarks>
///  <para>
///   Control words: bit 0 clear is the vector; <c>$xF</c> sets the mode in bits 6-7, and mode 3 takes the
///   direction of each bit next (1 input); <c>$x7</c> is the interrupt control word (bit 7 enable, bit 6 AND, bit 5
///   active high, bit 4 the mask follows, whose set bits are not watched); <c>$x3</c> sets only the enable. In
///   mode 3 the port interrupts when the watched inputs become active: any of them, or with AND all. Port A
///   outranks port B. The handshake strobes are not connected here, so modes 1 and 2 never interrupt.
///  </para>
/// </remarks>
public sealed class Z80Pio : IZ80DaisyDevice
{
    private readonly Z80PioPort[] _ports;

    /// <summary>
    ///  Creates the PIO.
    /// </summary>
    /// <param name="inputA">Reads port A's input pins.</param>
    /// <param name="inputB">Reads port B's input pins.</param>
    /// <param name="outputB">Takes what port B outputs.</param>
    internal Z80Pio(Func<byte> inputA, Func<byte> inputB, Action<byte>? outputB = null)
    {
        _ports = [new(inputA, sink: null), new(inputB, outputB)];
    }

    /// <summary>
    ///  Gets a port's mode, 0-3.
    /// </summary>
    /// <param name="port">0 for A, 1 for B.</param>
    /// <returns>The mode.</returns>
    public int Mode(int port) => _ports[port].Mode;

    /// <summary>
    ///  Reads a register.
    /// </summary>
    /// <param name="register">0 A data, 1 B data, 2 A control, 3 B control.</param>
    /// <returns>The value.</returns>
    internal byte Read(int register)
    {
        Z80PioPort port = _ports[register & 1];
        if ((register & 2) != 0) { return 0xFF; }
        return port.Mode switch
        {
            0 => port.Output,
            3 => (byte)((port.Input() & port.Direction) | (port.Output & ~port.Direction)),
            _ => port.Input()
        };
    }

    /// <summary>
    ///  Reads a register without side effects, for the debugger.
    /// </summary>
    /// <param name="register">0 A data, 1 B data, 2 A control, 3 B control.</param>
    /// <returns>The value.</returns>
    public byte Peek(int register) => Read(register);

    /// <summary>
    ///  Writes a register.
    /// </summary>
    /// <param name="register">0 A data, 1 B data, 2 A control, 3 B control.</param>
    /// <param name="value">The value.</param>
    internal void Write(int register, byte value)
    {
        Z80PioPort port = _ports[register & 1];
        if ((register & 2) == 0)
        {
            port.Output = value;
            if (port.Mode != 1) { port.Sink?.Invoke(value); }
            return;
        }

        if (port.AwaitingDirection)
        {
            port.Direction = value;
            port.AwaitingDirection = false;
            return;
        }

        if (port.AwaitingMask)
        {
            port.Mask = value;
            port.AwaitingMask = false;
            port.Matched = false;
            return;
        }

        if ((value & 1) == 0)
        {
            port.Vector = value;
        }
        else if ((value & 0x0F) == 0x0F)
        {
            port.Mode = value >> 6;
            port.AwaitingDirection = port.Mode == 3;
        }
        else if ((value & 0x0F) == 0x07)
        {
            port.Enabled = (value & 0x80) != 0;
            port.All = (value & 0x40) != 0;
            port.High = (value & 0x20) != 0;
            port.AwaitingMask = (value & 0x10) != 0;
            port.Pending = false;
            port.Matched = false;
        }
        else if ((value & 0x0F) == 0x03)
        {
            port.Enabled = (value & 0x80) != 0;
        }
    }

    /// <summary>
    ///  Watches the bit control ports' inputs, interrupting when their condition becomes true.
    /// </summary>
    internal void Tick()
    {
        foreach (Z80PioPort port in _ports)
        {
            if (port.Mode != 3) { continue; }
            byte watched = (byte)(port.Direction & ~port.Mask);
            byte active = (byte)((port.High ? port.Input() : ~port.Input()) & watched);
            bool match = watched != 0 && (port.All ? active == watched : active != 0);
            if (match && !port.Matched && port.Enabled) { port.Pending = true; }
            port.Matched = match;
        }
    }

    /// <inheritdoc/>
    public byte? PendingVector
    {
        get
        {
            foreach (Z80PioPort port in _ports)
            {
                if (port.InService) { return null; }
                if (port.Pending) { return port.Vector; }
            }

            return null;
        }
    }

    /// <inheritdoc/>
    public bool InService => _ports[0].InService || _ports[1].InService;

    /// <inheritdoc/>
    void IZ80DaisyDevice.Acknowledge()
    {
        Z80PioPort port = _ports[0].Pending ? _ports[0] : _ports[1];
        port.Pending = false;
        port.InService = true;
    }

    /// <inheritdoc/>
    void IZ80DaisyDevice.ReturnFromInterrupt()
    {
        Z80PioPort port = _ports[0].InService ? _ports[0] : _ports[1];
        port.InService = false;
    }
}
