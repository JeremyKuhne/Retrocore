// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Chips;

/// <summary>
///  A Motorola MC6821 Peripheral Interface Adapter: two 8-bit ports, each with a data direction register, a control
///  register and two control lines, one of which can also be an output.
/// </summary>
/// <remarks>
///  <para>
///   The machine sets the input pins and control-line inputs, and reads the outputs after each access. Register
///   select 0 is the port A data or direction register (as control register A bit 2 chooses), 1 control register A,
///   2 the port B data or direction register, and 3 control register B.
///  </para>
///  <para>
///   A control register's bits: 0 enables the C1 interrupt; 1 picks C1's active edge (0 falling, 1 rising); 2
///   selects the data register rather than the direction register; 3-5 control C2; 6 is the C2 interrupt flag and 7
///   the C1 interrupt flag, both read-only and cleared by reading the port's data register. With bit 5 clear, C2 is
///   an input like C1, bit 3 enabling its interrupt and bit 4 picking its edge. With bits 5 and 4 set, C2 outputs bit
///   3. With bit 5 set and bit 4 clear, C2 is a strobe: it goes low on a read of port A's data (CA2) or a write of
///   port B's data (CB2), and returns high on C1's active edge (bit 3 clear) or straight away (bit 3 set).
///  </para>
/// </remarks>
public sealed class Pia6821
{
    private Pia6821Port _a;
    private Pia6821Port _b;

    /// <summary>
    ///  Creates a reset PIA.
    /// </summary>
    public Pia6821() => Reset();

    /// <summary>
    ///  Gets or sets the levels on port A's pins from outside, which a read sees on its input bits.
    /// </summary>
    public byte PortAInput { get; set; } = 0xFF;

    /// <summary>
    ///  Gets or sets the levels on port B's pins from outside, which a read sees on its input bits.
    /// </summary>
    public byte PortBInput { get; set; } = 0xFF;

    /// <summary>
    ///  Gets what port A drives: the output register on output pins, and high on input pins, as pull-ups leave them.
    /// </summary>
    public byte PortAOutput => (byte)((_a.Output & _a.Direction) | ~_a.Direction);

    /// <summary>
    ///  Gets what port B drives: the output register on output pins, and high on input pins.
    /// </summary>
    public byte PortBOutput => (byte)((_b.Output & _b.Direction) | ~_b.Direction);

    /// <summary>
    ///  Gets port A's direction register; a set bit is an output.
    /// </summary>
    public byte PortADirection => _a.Direction;

    /// <summary>
    ///  Gets port B's direction register; a set bit is an output.
    /// </summary>
    public byte PortBDirection => _b.Direction;

    /// <summary>
    ///  Gets control register A, its interrupt flags included.
    /// </summary>
    public byte ControlA => _a.Control;

    /// <summary>
    ///  Gets control register B, its interrupt flags included.
    /// </summary>
    public byte ControlB => _b.Control;

    /// <summary>
    ///  Gets the level CA2 outputs; high while it is an input.
    /// </summary>
    public bool CA2Output => _a.C2Out;

    /// <summary>
    ///  Gets the level CB2 outputs; high while it is an input.
    /// </summary>
    public bool CB2Output => _b.C2Out;

    /// <summary>
    ///  Gets whether IRQA is asserted.
    /// </summary>
    public bool InterruptA => _a.Interrupt;

    /// <summary>
    ///  Gets whether IRQB is asserted.
    /// </summary>
    public bool InterruptB => _b.Interrupt;

    /// <summary>
    ///  Gets or sets the level on CA1, setting its flag on the active edge.
    /// </summary>
    public bool CA1
    {
        get => _a.C1;
        set => _a.SetC1(value);
    }

    /// <summary>
    ///  Gets or sets the level on CB1, setting its flag on the active edge.
    /// </summary>
    public bool CB1
    {
        get => _b.C1;
        set => _b.SetC1(value);
    }

    /// <summary>
    ///  Gets or sets the level driven into CA2 while it is an input, setting its flag on the active edge.
    /// </summary>
    public bool CA2
    {
        get => _a.C2In;
        set => _a.SetC2(value);
    }

    /// <summary>
    ///  Gets or sets the level driven into CB2 while it is an input, setting its flag on the active edge.
    /// </summary>
    public bool CB2
    {
        get => _b.C2In;
        set => _b.SetC2(value);
    }

    /// <summary>
    ///  Reads a register as the CPU does, clearing a port's flags when its data register is read.
    /// </summary>
    /// <param name="register">The register select, 0-3.</param>
    /// <returns>The value.</returns>
    public byte Read(int register)
    {
        switch (register & 3)
        {
            case 0:
                if ((_a.Control & Pia6821Port.DataRegister) == 0)
                {
                    return _a.Direction;
                }

                // Port A reads its pins, output pins included.
                byte a = (byte)((_a.Output & _a.Direction) | (PortAInput & ~_a.Direction));
                _a.ClearFlags();
                _a.Strobe();
                return a;
            case 1:
                return _a.Control;
            case 2:
                if ((_b.Control & Pia6821Port.DataRegister) == 0)
                {
                    return _b.Direction;
                }

                // Port B reads its output register on output pins.
                byte b = (byte)((_b.Output & _b.Direction) | (PortBInput & ~_b.Direction));
                _b.ClearFlags();
                return b;
            default:
                return _b.Control;
        }
    }

    /// <summary>
    ///  Reads a register without side effects.
    /// </summary>
    /// <param name="register">The register select, 0-3.</param>
    /// <returns>The value.</returns>
    public byte Peek(int register) => (register & 3) switch
    {
        0 => (_a.Control & Pia6821Port.DataRegister) == 0
            ? _a.Direction
            : (byte)((_a.Output & _a.Direction) | (PortAInput & ~_a.Direction)),
        1 => _a.Control,
        2 => (_b.Control & Pia6821Port.DataRegister) == 0
            ? _b.Direction
            : (byte)((_b.Output & _b.Direction) | (PortBInput & ~_b.Direction)),
        _ => _b.Control
    };

    /// <summary>
    ///  Writes a register as the CPU does.
    /// </summary>
    /// <param name="register">The register select, 0-3.</param>
    /// <param name="value">The value.</param>
    public void Write(int register, byte value)
    {
        switch (register & 3)
        {
            case 0:
                if ((_a.Control & Pia6821Port.DataRegister) == 0) { _a.Direction = value; }
                else { _a.Output = value; }
                return;
            case 1:
                _a.WriteControl(value);
                return;
            case 2:
                if ((_b.Control & Pia6821Port.DataRegister) == 0)
                {
                    _b.Direction = value;
                    return;
                }

                _b.Output = value;
                _b.Strobe();
                return;
            default:
                _b.WriteControl(value);
                return;
        }
    }

    /// <summary>
    ///  Clears every register, as the RESET line does; the control lines become inputs.
    /// </summary>
    public void Reset()
    {
        _a = new Pia6821Port { C1 = _a.C1, C2In = _a.C2In };
        _b = new Pia6821Port { C1 = _b.C1, C2In = _b.C2In };
        _a.C2Out = true;
        _b.C2Out = true;
    }
}
