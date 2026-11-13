// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Chips;

/// <summary>
///  A Motorola MC6850 Asynchronous Communications Interface Adapter: one serial port, with a transmit data register
///  ahead of its shift register and a receive data register behind its own.
/// </summary>
/// <remarks>
///  <para>
///   Register select 0 is the control register when written and the status register when read; register select 1 is
///   the transmit data register when written and the receive data register when read.
///  </para>
///  <para>
///   Status bits: 0 receive data register full (RDRF), 1 transmit data register empty (TDRE), 2 data carrier detect
///   lost, 3 clear to send off, 4 framing error, 5 receiver overrun, 6 parity error, 7 interrupt request. This model's
///   lines always have carrier and are clear to send, and its characters never have framing or parity errors.
///  </para>
///  <para>
///   Control bits: 0-1 the clock divide, where 3 is master reset; 2-4 the word format; 5-6 the transmitter control,
///   where 1 enables the transmit interrupt; 7 enables the receive interrupt. After power-on or a master reset the
///   transmitter is held, TDRE clear, until a control write selects a clock divide.
///  </para>
///  <para>
///   The board steps the ACIA once per CPU cycle with <see cref="Tick"/>. A character takes
///   <see cref="CyclesPerCharacter"/> cycles in the shift register, then <see cref="Transmitted"/> receives it. The
///   other end of the line delivers characters with <see cref="Receive"/>.
///  </para>
/// </remarks>
public sealed class Acia6850
{
    /// <summary>
    ///  RDRF: the receive data register holds a character.
    /// </summary>
    public const byte ReceiveFull = 0x01;

    /// <summary>
    ///  TDRE: the transmit data register can take a character.
    /// </summary>
    public const byte TransmitEmpty = 0x02;

    /// <summary>
    ///  OVRN: a character arrived before the previous one was read, and was lost.
    /// </summary>
    public const byte Overrun = 0x20;

    /// <summary>
    ///  IRQ: the ACIA requests an interrupt.
    /// </summary>
    public const byte InterruptRequest = 0x80;

    private const int MasterReset = 3;

    private byte _control;
    private byte _status;
    private byte _transmitData;
    private byte _receiveData;
    private bool _shifting;
    private byte _shiftData;
    private int _shiftCycles;
    private bool _held = true;

    /// <summary>
    ///  Creates an ACIA as power-on leaves it: held in master reset.
    /// </summary>
    public Acia6850()
    {
    }

    /// <summary>
    ///  Gets or sets the CPU cycles one character takes on the line, start and stop bits included.
    /// </summary>
    /// <exception cref="ArgumentOutOfRangeException">The value is not positive.</exception>
    public int CyclesPerCharacter
    {
        get;
        set => field = value > 0 ? value : throw new ArgumentOutOfRangeException(nameof(value));
    } = 1;

    /// <summary>
    ///  Gets or sets what receives each character as its last bit leaves the shift register.
    /// </summary>
    public Action<byte>? Transmitted { get; set; }

    /// <summary>
    ///  Gets the control register.
    /// </summary>
    public byte Control => _control;

    /// <summary>
    ///  Gets the status register as a read would return it.
    /// </summary>
    public byte Status => (byte)(_status | (Interrupt ? InterruptRequest : 0));

    /// <summary>
    ///  Gets whether the ACIA drives its IRQ output: a full receiver or an overrun with the receive interrupt enabled, or
    ///  an empty transmit register with the transmit interrupt enabled.
    /// </summary>
    public bool Interrupt =>
        !_held
            && (((_control & 0x80) != 0 && (_status & (ReceiveFull | Overrun)) != 0)
                || ((_control & 0x60) == 0x20 && (_status & TransmitEmpty) != 0));

    /// <summary>
    ///  Gets whether the receive data register is empty, so the line can deliver another character without an overrun.
    /// </summary>
    public bool CanReceive => !_held && (_status & ReceiveFull) == 0;

    /// <summary>
    ///  Reads a register: the status, or the receive data, which clears RDRF and the overrun.
    /// </summary>
    /// <param name="register">The register select: 0 status, 1 receive data.</param>
    /// <returns>The value.</returns>
    public byte Read(int register)
    {
        if ((register & 1) == 0) { return Status; }
        _status &= unchecked((byte)~(ReceiveFull | Overrun));
        return _receiveData;
    }

    /// <summary>
    ///  Reads a register without side effects.
    /// </summary>
    /// <param name="register">The register select: 0 status, 1 receive data.</param>
    /// <returns>The value.</returns>
    public byte Peek(int register) => (register & 1) == 0 ? Status : _receiveData;

    /// <summary>
    ///  Writes a register: the control, or the transmit data.
    /// </summary>
    /// <param name="register">The register select: 0 control, 1 transmit data.</param>
    /// <param name="value">The value.</param>
    public void Write(int register, byte value)
    {
        if ((register & 1) == 0)
        {
            _control = value;
            if ((value & 3) == MasterReset)
            {
                Reset();
                _control = value;
                return;
            }

            if (_held)
            {
                _held = false;
                _status |= TransmitEmpty;
            }

            return;
        }

        if (_held) { return; }
        _transmitData = value;
        _status &= unchecked((byte)~TransmitEmpty);
    }

    /// <summary>
    ///  Delivers a character from the line to the receive data register. If the previous one was not read yet, it
    ///  stays and the overrun flag is set, as the chip loses the new one.
    /// </summary>
    /// <param name="value">The character.</param>
    public void Receive(byte value)
    {
        if (_held) { return; }
        if ((_status & ReceiveFull) != 0)
        {
            _status |= Overrun;
            return;
        }

        _receiveData = value;
        _status |= ReceiveFull;
    }

    /// <summary>
    ///  Advances one CPU cycle: a waiting character moves into an idle shift register, and the shifting one leaves.
    /// </summary>
    public void Tick()
    {
        if (_held) { return; }
        if (_shifting && --_shiftCycles <= 0)
        {
            _shifting = false;
            Transmitted?.Invoke(_shiftData);
        }

        if (!_shifting && (_status & TransmitEmpty) == 0)
        {
            _shiftData = _transmitData;
            _shiftCycles = CyclesPerCharacter;
            _shifting = true;
            _status |= TransmitEmpty;
        }
    }

    /// <summary>
    ///  Master reset, as power-on leaves it: the registers clear, the transmitter is held and a character shifting
    ///  out is lost.
    /// </summary>
    public void Reset()
    {
        _control = MasterReset;
        _status = 0;
        _shifting = false;
        _held = true;
    }
}
