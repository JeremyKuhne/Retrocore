// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Chips;

/// <summary>
///  One port of a <see cref="Pia6821"/> and its two control lines.
/// </summary>
internal struct Pia6821Port
{
    /// <summary>
    ///  Control register bit 2: the data register, rather than the direction register, is selected.
    /// </summary>
    internal const byte DataRegister = 0x04;

    private const byte C1InterruptEnable = 0x01;
    private const byte C1RisingEdge = 0x02;
    private const byte C2Output = 0x20;
    private const byte C2Manual = 0x10;
    private const byte C2Bit3 = 0x08;
    private const byte C2Flag = 0x40;
    private const byte C1Flag = 0x80;

    /// <summary>
    ///  The output register.
    /// </summary>
    public byte Output;

    /// <summary>
    ///  The data direction register; a set bit is an output.
    /// </summary>
    public byte Direction;

    /// <summary>
    ///  The control register, its two interrupt flags included.
    /// </summary>
    public byte Control;

    /// <summary>
    ///  The level on C1.
    /// </summary>
    public bool C1;

    /// <summary>
    ///  The level driven into C2 from outside.
    /// </summary>
    public bool C2In;

    /// <summary>
    ///  The level C2 outputs; high while it is an input.
    /// </summary>
    public bool C2Out;

    /// <summary>
    ///  Gets whether the port's IRQ output is asserted.
    /// </summary>
    public readonly bool Interrupt =>
        ((Control & C1Flag) != 0 && (Control & C1InterruptEnable) != 0)
            || ((Control & C2Flag) != 0 && (Control & (C2Output | C2Bit3)) == C2Bit3);

    /// <summary>
    ///  Sets C1's level, setting its flag on the active edge.
    /// </summary>
    /// <param name="level">The level.</param>
    public void SetC1(bool level)
    {
        bool rising = (Control & C1RisingEdge) != 0;
        if (level != C1 && level == rising)
        {
            Control |= C1Flag;

            // A strobe that waits for C1 returns high on its active edge.
            if ((Control & (C2Output | C2Manual | C2Bit3)) == C2Output)
            {
                C2Out = true;
            }
        }

        C1 = level;
    }

    /// <summary>
    ///  Sets the level driven into C2, setting its flag on the active edge while C2 is an input.
    /// </summary>
    /// <param name="level">The level.</param>
    public void SetC2(bool level)
    {
        if ((Control & C2Output) == 0)
        {
            bool rising = (Control & C2Manual) != 0;
            if (level != C2In && level == rising)
            {
                Control |= C2Flag;
            }
        }

        C2In = level;
    }

    /// <summary>
    ///  Clears both interrupt flags, as reading the data register does.
    /// </summary>
    public void ClearFlags() => Control &= unchecked((byte)~(C1Flag | C2Flag));

    /// <summary>
    ///  Applies a strobe mode's C2 response to a port A read or port B write: in pulse mode C2 is back high before
    ///  the next access, so only the handshake mode leaves it low.
    /// </summary>
    public void Strobe()
    {
        if ((Control & (C2Output | C2Manual)) == C2Output)
        {
            C2Out = (Control & C2Bit3) != 0;
        }
    }

    /// <summary>
    ///  Writes the control register's six writable bits.
    /// </summary>
    /// <param name="value">The value.</param>
    public void WriteControl(byte value)
    {
        Control = (byte)((Control & (C1Flag | C2Flag)) | (value & 0x3F));
        if ((Control & C2Output) == 0)
        {
            C2Out = true;
        }
        else if ((Control & C2Manual) != 0)
        {
            C2Out = (Control & C2Bit3) != 0;
        }
        else
        {
            // Entering a strobe mode leaves C2 high until the strobe.
            C2Out = true;
        }
    }
}
