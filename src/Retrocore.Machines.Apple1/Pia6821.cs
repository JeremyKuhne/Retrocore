// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Apple1;

/// <summary>
///  A Motorola 6821 (6820) Peripheral Interface Adapter: two 8-bit ports, each with a data direction register,
///  a control register and two control lines.
/// </summary>
/// <remarks>
///  <para>
///   Register select 0 is port A's data or direction register, as bit 2 of control register A (1) chooses; 2 and 3
///   are port B's. In a control register, bits 0-1 enable C1's interrupt and choose its active edge (1 rising),
///   bit 2 selects the data register, bits 3-5 set up C2, and bits 6-7 are the C2 and C1 flags, which only a read
///   of the port's data register clears.
///  </para>
///  <para>
///   C2 is an output when bit 5 is set: with bit 4 set it follows bit 3; with bit 4 clear it goes low on a read
///   of port A or a write to port B, and goes high again on C1's active edge (bit 3 clear, the handshake) or
///   after one cycle (bit 3 set, the pulse). C2 as an input and the interrupt outputs are not emulated; the
///   Apple-1 leaves them unconnected.
///  </para>
/// </remarks>
public sealed class Pia6821
{
    private const byte SelectData = 0x04;
    private const byte C1Rising = 0x02;
    private const byte C1Flag = 0x80;
    private const byte C2Flag = 0x40;

    private byte _outputA;
    private byte _directionA;
    private byte _controlA;
    private byte _outputB;
    private byte _directionB;
    private byte _controlB;
    private bool _ca1;
    private bool _cb1;
    private bool _ca2Pulse;
    private bool _cb2Pulse;

    /// <summary>
    ///  Creates a PIA in its reset state.
    /// </summary>
    public Pia6821() => Reset();

    /// <summary>
    ///  Gets or sets the levels the outside drives on port A's pins.
    /// </summary>
    public byte InputA { get; set; } = 0xFF;

    /// <summary>
    ///  Gets or sets the levels the outside drives on port B's pins.
    /// </summary>
    public byte InputB { get; set; } = 0xFF;

    /// <summary>
    ///  Gets port A's pins: the output register where the direction register makes them outputs, and the
    ///  inputs elsewhere.
    /// </summary>
    public byte PinsA => (byte)((_outputA & _directionA) | (InputA & ~_directionA));

    /// <summary>
    ///  Gets port B's pins: the output register where the direction register makes them outputs, and the
    ///  inputs elsewhere.
    /// </summary>
    public byte PinsB => (byte)((_outputB & _directionB) | (InputB & ~_directionB));

    /// <summary>
    ///  Gets control register A, its flags included.
    /// </summary>
    public byte ControlA => _controlA;

    /// <summary>
    ///  Gets control register B, its flags included.
    /// </summary>
    public byte ControlB => _controlB;

    /// <summary>
    ///  Gets the level of CA2 as an output; high when it is an input.
    /// </summary>
    public bool CA2 { get; private set; }

    /// <summary>
    ///  Gets the level of CB2 as an output; high when it is an input.
    /// </summary>
    public bool CB2 { get; private set; }

    /// <summary>
    ///  Resets the PIA, as its RESET line does: every register is cleared, so the ports are inputs and the
    ///  direction registers are selected.
    /// </summary>
    public void Reset()
    {
        _outputA = _directionA = _controlA = 0;
        _outputB = _directionB = _controlB = 0;
        _ca2Pulse = _cb2Pulse = false;
        CA2 = CB2 = true;
    }

    /// <summary>
    ///  Reads a register, with the side effects of a CPU read.
    /// </summary>
    /// <param name="register">The register select, 0-3.</param>
    /// <returns>The value.</returns>
    public byte Read(int register)
    {
        byte value = Peek(register);
        switch (register & 3)
        {
            case 0 when (_controlA & SelectData) != 0:
                _controlA &= unchecked((byte)~(C1Flag | C2Flag));
                if ((_controlA & 0x30) == 0x20)
                {
                    // Handshake or pulse: a read of port A takes CA2 low.
                    CA2 = false;
                    _ca2Pulse = (_controlA & 0x08) != 0;
                }

                break;
            case 2 when (_controlB & SelectData) != 0:
                _controlB &= unchecked((byte)~(C1Flag | C2Flag));
                break;
        }

        return value;
    }

    /// <summary>
    ///  Reads a register without side effects, for the debugger.
    /// </summary>
    /// <param name="register">The register select, 0-3.</param>
    /// <returns>The value a read would return.</returns>
    public byte Peek(int register) => (register & 3) switch
    {
        0 => (_controlA & SelectData) != 0 ? PinsA : _directionA,
        1 => _controlA,
        2 => (_controlB & SelectData) != 0 ? PinsB : _directionB,
        _ => _controlB
    };

    /// <summary>
    ///  Writes a register.
    /// </summary>
    /// <param name="register">The register select, 0-3.</param>
    /// <param name="value">The value.</param>
    public void Write(int register, byte value)
    {
        switch (register & 3)
        {
            case 0:
                if ((_controlA & SelectData) != 0) { _outputA = value; } else { _directionA = value; }
                break;
            case 1:
                _controlA = (byte)((_controlA & 0xC0) | (value & 0x3F));
                CA2 = ControlOutput(_controlA, CA2);
                break;
            case 2:
                if ((_controlB & SelectData) == 0)
                {
                    _directionB = value;
                    break;
                }

                _outputB = value;
                if ((_controlB & 0x30) == 0x20)
                {
                    // Handshake or pulse: a write to port B takes CB2 low.
                    CB2 = false;
                    _cb2Pulse = (_controlB & 0x08) != 0;
                }

                break;
            default:
                _controlB = (byte)((_controlB & 0xC0) | (value & 0x3F));
                CB2 = ControlOutput(_controlB, CB2);
                break;
        }
    }

    /// <summary>
    ///  Drives CA1; its active edge sets control register A's bit 7 and ends a CA2 handshake.
    /// </summary>
    /// <param name="level">The new level.</param>
    public void SetCA1(bool level)
    {
        if (level != _ca1 && level == ((_controlA & C1Rising) != 0))
        {
            _controlA |= C1Flag;
            if ((_controlA & 0x38) == 0x20) { CA2 = true; }
        }

        _ca1 = level;
    }

    /// <summary>
    ///  Drives CB1; its active edge sets control register B's bit 7 and ends a CB2 handshake.
    /// </summary>
    /// <param name="level">The new level.</param>
    public void SetCB1(bool level)
    {
        if (level != _cb1 && level == ((_controlB & C1Rising) != 0))
        {
            _controlB |= C1Flag;
            if ((_controlB & 0x38) == 0x20) { CB2 = true; }
        }

        _cb1 = level;
    }

    /// <summary>
    ///  Advances one cycle, ending a C2 pulse.
    /// </summary>
    public void Tick()
    {
        if (_ca2Pulse)
        {
            _ca2Pulse = false;
            CA2 = true;
        }

        if (_cb2Pulse)
        {
            _cb2Pulse = false;
            CB2 = true;
        }
    }

    // The level of C2 after a control register write: the manual level, high as an input, or unchanged in the
    // handshake and pulse modes.
    private static bool ControlOutput(byte control, bool level) => (control & 0x30) switch
    {
        0x30 => (control & 0x08) != 0,
        0x20 => level,
        _ => true
    };
}
