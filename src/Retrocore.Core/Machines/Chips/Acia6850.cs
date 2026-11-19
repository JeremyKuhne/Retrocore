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
///   lost (DCD), 3 clear to send off (CTS), 4 framing error, 5 receiver overrun, 6 parity error, 7 interrupt request.
///  </para>
///  <para>
///   Control bits: 0-1 the clock divide (1, 16 or 64), where 3 is master reset; 2-4 the word format (7 or 8 data
///   bits, even, odd or no parity, 1 or 2 stop bits); 5-6 the transmitter control: RTS low with the transmit interrupt
///   off (0) or on (1), RTS high (2), or RTS low sending a break (3); 7 enables the receive interrupt. After power-on
///   or a master reset the transmitter is held, TDRE clear, until a control write selects a clock divide.
///  </para>
///  <para>
///   The board can drive it a character at a time: it steps the ACIA once per CPU cycle with <see cref="Tick"/>, a
///   character takes <see cref="CyclesPerCharacter"/> cycles in the shift register, then <see cref="Transmitted"/>
///   receives it, and the other end of the line delivers characters with <see cref="Receive"/>. Or it can drive it a
///   bit at a time, as the chip's clock inputs do: <see cref="ClockReceive"/> is one edge of the receive clock with
///   the level of the data input, and <see cref="ClockTransmit"/> one edge of the transmit clock, after which
///   <see cref="TransmitLevel"/> is the data output.
///  </para>
///  <para>
///   The modem lines: a rise of the DCD input sets the DCD status bit and, with the receive interrupt enabled,
///   interrupts, until the status and then the receive data are read; after that the bit follows the input. While the
///   DCD input is high, RDRF reads clear and the receiver is held idle, dropping a character it was assembling. CTS
///   high clears TDRE as read and stops the transmitter taking a character; one already shifting out finishes.
///  </para>
///  <para>
///   A character the bit-clocked receiver completes while the receive data register is still full is lost, and the
///   overrun shows only once the character before it has been read: that read leaves RDRF set with OVRN, and the
///   next read of the receive data clears them both.
///  </para>
/// </remarks>
public sealed class Acia6850 : ISerialLine
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
    ///  DCD: the data carrier detect input rose, or is high.
    /// </summary>
    public const byte CarrierLost = 0x04;

    /// <summary>
    ///  CTS: the clear to send input is high.
    /// </summary>
    public const byte NotClearToSend = 0x08;

    /// <summary>
    ///  FE: the character in the receive data register had no stop bit.
    /// </summary>
    public const byte FramingError = 0x10;

    /// <summary>
    ///  OVRN: a character arrived before the previous one was read, and was lost.
    /// </summary>
    public const byte Overrun = 0x20;

    /// <summary>
    ///  PE: the character in the receive data register had the wrong parity.
    /// </summary>
    public const byte ParityError = 0x40;

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
    private bool _carrierLost;
    private bool _carrierLatched;
    private bool _carrierStatusRead;
    private bool _notClearToSend;
    private bool _overrunPending;

    // The bit-clocked receiver: 0 idle, 1 in the start bit, 2 data bits, 3 parity, 4 stop.
    private int _receiveState;
    private int _receiveClocks;
    private int _receiveBits;
    private int _receiveShift;
    private bool _receiveParity;

    // The bit-clocked transmitter: 0 idle, 1 data bits, 2 parity, 3 stop bits. A character whose last stop bit is on
    // the line is reported at the next bit boundary.
    private int _transmitState;
    private bool _transmitDone;
    private int _transmitClocks;
    private int _transmitBits;
    private int _transmitShift;
    private int _transmitStops;

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
    public byte Status
    {
        get
        {
            int status = _status;
            if (_carrierLatched) { status |= CarrierLost; }
            if (_carrierLost) { status = (status | CarrierLost) & ~ReceiveFull; }
            if (_notClearToSend) { status = (status | NotClearToSend) & ~TransmitEmpty; }
            return (byte)(status | (Interrupt ? InterruptRequest : 0));
        }
    }

    /// <summary>
    ///  Gets whether the ACIA drives its IRQ output: a full receiver, an overrun or a rise of DCD with the receive
    ///  interrupt enabled, or an empty transmit register with the transmit interrupt enabled and CTS low.
    /// </summary>
    public bool Interrupt =>
        !_held
            && (((_control & 0x80) != 0 && ((_status & (ReceiveFull | Overrun)) != 0 || _carrierLatched))
                || ((_control & 0x60) == 0x20 && (_status & TransmitEmpty) != 0 && !_notClearToSend));

    /// <summary>
    ///  Gets or sets the DCD input: high when the carrier is lost.
    /// </summary>
    public bool DataCarrierDetect
    {
        get => _carrierLost;
        set
        {
            if (value && !_carrierLost && !_held)
            {
                _carrierLatched = true;
                _carrierStatusRead = false;
            }

            // Losing the carrier drops a character being assembled, even if it comes back before the next clock.
            if (value) { _receiveState = 0; }

            _carrierLost = value;
        }
    }

    /// <summary>
    ///  Gets or sets the CTS input: high when the other end is not clear to receive.
    /// </summary>
    public bool ClearToSend
    {
        get => _notClearToSend;
        set => _notClearToSend = value;
    }

    /// <summary>
    ///  Gets whether the RTS output is high: transmitter control 2.
    /// </summary>
    public bool RequestToSendHigh => (_control & 0x60) == 0x40;

    /// <summary>
    ///  Gets the transmit data output as the bit-clocked transmitter drives it: high (mark) when idle.
    /// </summary>
    public bool TransmitLevel { get; private set; } = true;

    /// <summary>
    ///  Gets whether the line can deliver another character: the receive data register is empty, without an overrun,
    ///  and the carrier is present, as the receiver drops characters while DCD is high.
    /// </summary>
    public bool CanReceive => !_held && !_carrierLost && (_status & ReceiveFull) == 0;

    /// <summary>
    ///  Reads a register: the status, or the receive data, which clears RDRF and the overrun.
    /// </summary>
    /// <param name="register">The register select: 0 status, 1 receive data.</param>
    /// <returns>The value.</returns>
    public byte Read(int register)
    {
        if ((register & 1) == 0)
        {
            if (_carrierLatched) { _carrierStatusRead = true; }
            return Status;
        }

        if (_carrierStatusRead)
        {
            _carrierLatched = false;
            _carrierStatusRead = false;
        }

        if (_overrunPending)
        {
            // The character before the lost one has been read: now the overrun shows, and RDRF stays set with it.
            _overrunPending = false;
            _status |= Overrun;
            return _receiveData;
        }

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
        if (_held || _carrierLost) { return; }
        if ((_status & ReceiveFull) != 0)
        {
            _status |= Overrun;
            return;
        }

        _receiveData = value;
        _status = (byte)((_status & ~(FramingError | ParityError)) | ReceiveFull);
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

        if (!_shifting && (_status & TransmitEmpty) == 0 && !_notClearToSend)
        {
            _shiftData = _transmitData;
            _shiftCycles = CyclesPerCharacter;
            _shifting = true;
            _status |= TransmitEmpty;
        }
    }

    /// <summary>
    ///  One edge of the receive clock, which samples the data input: a character's start bit is checked half way
    ///  through, then each bit is taken a whole bit time (the clock divide) later. A complete character goes to the
    ///  receive data register, as <see cref="Receive"/> delivers one, with its framing and parity errors.
    /// </summary>
    /// <param name="data">The data input's level: high for a 1 (mark).</param>
    public void ClockReceive(bool data)
    {
        if (_held) { return; }
        if (_carrierLost)
        {
            _receiveState = 0;
            return;
        }

        int divide = Divide;
        switch (_receiveState)
        {
            case 0:
                if (data) { return; }
                _receiveState = 1;
                _receiveClocks = 0;
                if (divide > 1) { return; }
                break;
            case 1:
                if (++_receiveClocks < divide / 2) { return; }
                break;
            default:
                if (++_receiveClocks < divide) { return; }
                break;
        }

        _receiveClocks = 0;
        int format = (_control >> 2) & 7;
        int dataBits = format < 4 ? 7 : 8;
        bool parity = format is not (4 or 5);
        switch (_receiveState)
        {
            case 1:
                // A start bit that is high half way through was noise.
                if (data) { _receiveState = 0; }
                else
                {
                    _receiveState = 2;
                    _receiveBits = 0;
                    _receiveShift = 0;
                    _receiveParity = false;
                }

                break;
            case 2:
                if (data) { _receiveShift |= 1 << _receiveBits; }
                _receiveParity ^= data;
                if (++_receiveBits >= dataBits) { _receiveState = parity ? 3 : 4; }
                break;
            case 3:
                // Even parity makes the ones even, odd parity odd; formats 1, 3 and 7 are odd.
                _receiveParity ^= data ^ (format is 1 or 3 or 7);
                _receiveState = 4;
                break;
            default:
                _receiveState = 0;
                if ((_status & ReceiveFull) != 0)
                {
                    _overrunPending = true;
                    return;
                }

                _receiveData = (byte)_receiveShift;
                int status = (_status & ~(FramingError | ParityError)) | ReceiveFull;
                if (!data) { status |= FramingError; }
                if (parity && _receiveParity) { status |= ParityError; }
                _status = (byte)status;
                break;
        }
    }

    /// <summary>
    ///  One edge of the transmit clock: each bit lasts a bit time (the clock divide), and at a bit boundary with the
    ///  line idle a waiting character starts, with its start bit, its data from bit 0, its parity and its stop bits.
    ///  <see cref="TransmitLevel"/> follows.
    /// </summary>
    public void ClockTransmit()
    {
        if (_held)
        {
            TransmitLevel = true;
            return;
        }

        if (_transmitClocks > 0 && --_transmitClocks > 0) { return; }
        _transmitClocks = Divide;
        int format = (_control >> 2) & 7;
        int dataBits = format < 4 ? 7 : 8;
        bool parity = format is not (4 or 5);
        switch (_transmitState)
        {
            case 0:
                if (_transmitDone)
                {
                    _transmitDone = false;
                    Transmitted?.Invoke((byte)(_transmitShift & ((1 << dataBits) - 1)));
                }

                // The bit clock runs on while the line is idle, so a character written then starts at the next bit
                // boundary, up to a bit time later, and TDRE comes back no sooner. A break holds the line low and
                // keeps a waiting character until it ends.
                if ((_control & 0x60) == 0x60)
                {
                    TransmitLevel = false;
                    return;
                }

                if ((_status & TransmitEmpty) != 0 || _notClearToSend)
                {
                    TransmitLevel = true;
                    return;
                }

                _transmitShift = _transmitData;
                _status |= TransmitEmpty;
                _transmitBits = 0;
                _transmitState = 1;
                TransmitLevel = false;
                return;
            case 1:
                bool bit = (_transmitShift & (1 << _transmitBits)) != 0;
                TransmitLevel = bit;
                if (++_transmitBits >= dataBits)
                {
                    _transmitState = parity ? 2 : 3;
                    _transmitStops = format is 0 or 1 or 4 ? 2 : 1;
                }

                return;
            case 2:
                int ones = System.Numerics.BitOperations.PopCount((uint)(_transmitShift & ((1 << dataBits) - 1)));
                TransmitLevel = ((ones & 1) != 0) ^ (format is 1 or 3 or 7);
                _transmitState = 3;
                return;
            default:
                TransmitLevel = true;
                if (--_transmitStops <= 0)
                {
                    _transmitState = 0;
                    _transmitDone = true;
                }

                return;
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
        _carrierLatched = _carrierStatusRead = false;
        _overrunPending = _transmitDone = false;
        _receiveState = _transmitState = 0;
        _transmitClocks = 0;
        TransmitLevel = true;
    }

    // The clock divide: control bits 0-1 choose 1, 16 or 64.
    private int Divide => (_control & 3) switch { 0 => 1, 1 => 16, _ => 64 };
}
