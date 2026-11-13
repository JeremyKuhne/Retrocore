// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Chips;

/// <summary>
///  CPU-cycle 6522 VIA with parallel ports, control pins, timers and serial shifting.
/// </summary>
/// <remarks>
///  Follows the WDC W65C22 register and timing descriptions at CPU clock boundaries.
///  Loaded timed interrupts occur after N+2 clocks; T1 continuous interrupts repeat every N+2.
///  T2 pulse counting uses falling PB6 edges. Serial input samples rising CB1; serial output
///  shifts on falling CB1. External pin changes are immediate; analog propagation and the
///  original NMOS external-shift silicon race are not modeled.
///  <see href="https://www.westerndesigncenter.com/wdc/documentation/w65c22.pdf">VIA data sheet</see>.
/// </remarks>
public sealed class Via6522
{
    private byte _orb;
    private byte _ora;
    private byte _ddrb;
    private byte _ddra;
    private byte _acr;
    private byte _pcr;
    private byte _ifr;
    private byte _ier;
    private byte _portAInput = 255;
    private byte _portBInput = 255;
    private byte _latchedA = 255;
    private byte _latchedB = 255;
    private ushort _t1Latch;
    private ushort _t1Counter;
    private ushort _t2Latch;
    private ushort _t2Counter;
    private bool _t1Started;
    private bool _t2Started;
    private bool _t1Armed;
    private bool _t2Armed;
    private bool _t1Delay;
    private bool _t2Delay;
    private bool _timerB7;
    private bool _ca1 = true;
    private bool _ca2 = true;
    private bool _cb1 = true;
    private bool _cb2 = true;
    private bool _ca2Output = true;
    private bool _cb2Output = true;
    private bool _ca2Pulse;
    private bool _cb2Pulse;
    private byte _shift;
    private int _shiftBits;
    private int _shiftClock;
    private bool _shiftActive;
    private bool _serialClock = true;

    /// <summary>
    ///  Creates a reset VIA.
    /// </summary>
    public Via6522() => Reset();

    /// <summary>
    ///  Gets the combined enabled interrupt level.
    /// </summary>
    public bool InterruptRequested => (_ifr & _ier & 127) != 0;

    /// <summary>
    ///  Gets or sets external PA input pins.
    /// </summary>
    public byte PortAInput
    {
        get => _portAInput;
        set => _portAInput = value;
    }

    /// <summary>
    ///  Gets or sets external PB input pins, including the T2 pulse-count input PB6.
    /// </summary>
    public byte PortBInput
    {
        get => _portBInput;
        set
        {
            byte previous = PortB;
            _portBInput = value;
            CountPortBTransition(previous);
        }
    }

    /// <summary>
    ///  Gets physical PA levels with DDR-selected output latches.
    /// </summary>
    public byte PortA => (byte)((_ora & _ddra) | (_portAInput & ~_ddra));

    /// <summary>
    ///  Gets what port A drives: the output register on output pins, and high on input pins, as pull-ups leave them.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   A machine that wires a port to its own logic, as the Apple III does its environment and bank registers,
    ///   reads this rather than <see cref="PortA"/>, so that inputs from elsewhere on the port cannot change it.
    ///  </para>
    /// </remarks>
    public byte PortAOutput => (byte)((_ora & _ddra) | ~_ddra);

    /// <summary>
    ///  Gets what port B drives: the output register on output pins, and high on input pins, as pull-ups leave them.
    /// </summary>
    public byte PortBOutput => (byte)((_orb & _ddrb) | ~_ddrb);

    /// <summary>
    ///  Gets physical PB levels, including the optional timer-controlled PB7.
    /// </summary>
    public byte PortB => MixPortB(_portBInput);

    /// <summary>
    ///  Gets or sets CA1, capturing latched input and interrupts on the selected edge.
    /// </summary>
    public bool CA1
    {
        get => _ca1;
        set
        {
            bool active = _ca1 != value && value == ((_pcr & 1) != 0);
            _ca1 = value;
            if (!active)
            {
                return;
            }

            _ifr |= 2;
            if ((_acr & 1) != 0)
            {
                _latchedA = _portAInput;
            }

            if (CA2Mode == 4)
            {
                _ca2Output = true;
            }
        }
    }

    /// <summary>
    ///  Gets or sets external CA2, generating interrupts in input modes.
    /// </summary>
    public bool CA2
    {
        get => _ca2;
        set
        {
            int mode = CA2Mode;
            if (mode < 4 && _ca2 != value && value == (mode >= 2))
            {
                _ifr |= 1;
            }

            _ca2 = value;
        }
    }

    /// <summary>
    ///  Gets or sets external CB1, including externally clocked shift modes.
    /// </summary>
    public bool CB1
    {
        get => _cb1;
        set
        {
            bool changed = _cb1 != value;
            _cb1 = value;
            int mode = ShiftMode;
            if (changed && mode is 3 or 7)
            {
                SerialEdge(value);
            }

            if (!changed || mode != 0 || value != ((_pcr & 16) != 0))
            {
                return;
            }

            _ifr |= 16;
            if ((_acr & 2) != 0)
            {
                _latchedB = _portBInput;
            }

            if (CB2Mode == 4)
            {
                _cb2Output = true;
            }
        }
    }

    /// <summary>
    ///  Gets or sets external CB2, used for serial input and input-mode interrupts.
    /// </summary>
    public bool CB2
    {
        get => _cb2;
        set
        {
            int mode = CB2Mode;
            if (ShiftMode == 0 && mode < 4 && _cb2 != value && value == (mode >= 2))
            {
                _ifr |= 8;
            }

            _cb2 = value;
        }
    }

    /// <summary>
    ///  Gets the CA2 driven level in handshake, pulse or forced-output mode.
    /// </summary>
    public bool CA2Output => _ca2Output;

    /// <summary>
    ///  Gets the CB2 driven level, including serial output's next most-significant bit.
    /// </summary>
    public bool CB2Output => ShiftMode >= 4 ? (_shift & 128) != 0 : _cb2Output;

    /// <summary>
    ///  Gets CB1's generated serial clock, or the external pin in non-generated modes.
    /// </summary>
    public bool CB1Output => ShiftMode is 1 or 2 or 4 or 5 or 6 ? _serialClock : _cb1;

    private int CA2Mode => (_pcr >> 1) & 7;
    private int CB2Mode => (_pcr >> 5) & 7;
    private int ShiftMode => (_acr >> 2) & 7;

    /// <summary>
    ///  Reads a register, acknowledging the flags assigned to that access.
    /// </summary>
    /// <param name="register">The register number; low four bits are decoded.</param>
    /// <returns>The register data before acknowledgement.</returns>
    public byte Read(byte register)
    {
        int address = register & 15;
        byte value = Peek(register);
        switch (address)
        {
            case 0:
                AccessPort(portA: false, handshake: false);
                break;
            case 1:
                AccessPort(portA: true, handshake: true);
                break;
            case 4:
                _ifr &= unchecked((byte)~64);
                break;
            case 8:
                _ifr &= unchecked((byte)~32);
                break;
            case 10:
                StartShift();
                break;
        }

        return value;
    }

    /// <summary>
    ///  Reads without changing flags, handshakes, timers or shifting.
    /// </summary>
    /// <param name="register">The register number; low four bits are decoded.</param>
    /// <returns>The current register data.</returns>
    public byte Peek(byte register) => (register & 15) switch
    {
        0 => MixPortB((_acr & 2) != 0 ? _latchedB : _portBInput),
        1 or 15 => (byte)((_ora & _ddra) | (((_acr & 1) != 0 ? _latchedA : _portAInput) & ~_ddra)),
        2 => _ddrb,
        3 => _ddra,
        4 => (byte)_t1Counter,
        5 => (byte)(_t1Counter >> 8),
        6 => (byte)_t1Latch,
        7 => (byte)(_t1Latch >> 8),
        8 => (byte)_t2Counter,
        9 => (byte)(_t2Counter >> 8),
        10 => _shift,
        11 => _acr,
        12 => _pcr,
        13 => (byte)(_ifr | (InterruptRequested ? 128 : 0)),
        14 => (byte)(_ier | 128),
        _ => 255
    };

    /// <summary>
    ///  Writes a register without advancing the cycle clock.
    /// </summary>
    /// <param name="register">The register number; low four bits are decoded.</param>
    /// <param name="value">The register value.</param>
    public void Write(byte register, byte value)
    {
        byte previousPortB = PortB;
        int previousShiftMode = ShiftMode;
        switch (register & 15)
        {
            case 0:
                _orb = value;
                AccessPort(portA: false, handshake: true);
                break;
            case 1:
                _ora = value;
                AccessPort(portA: true, handshake: true);
                break;
            case 2:
                _ddrb = value;
                break;
            case 3:
                _ddra = value;
                break;
            case 4:
            case 6:
                _t1Latch = (ushort)((_t1Latch & 0xFF00) | value);
                break;
            case 5:
                _t1Latch = (ushort)((value << 8) | (_t1Latch & 255));
                _t1Counter = _t1Latch;
                _t1Started = _t1Armed = _t1Delay = true;
                _timerB7 = false;
                _ifr &= unchecked((byte)~64);
                break;
            case 7:
                _t1Latch = (ushort)((value << 8) | (_t1Latch & 255));
                _ifr &= unchecked((byte)~64);
                break;
            case 8:
                _t2Latch = (ushort)((_t2Latch & 0xFF00) | value);
                break;
            case 9:
                _t2Latch = (ushort)((value << 8) | (_t2Latch & 255));
                _t2Counter = _t2Latch;
                _t2Started = _t2Armed = _t2Delay = true;
                _ifr &= unchecked((byte)~32);
                break;
            case 10:
                _shift = value;
                StartShift();
                break;
            case 11:
                _acr = value;
                if (ShiftMode != previousShiftMode)
                {
                    _shiftActive = false;
                    _serialClock = true;
                    _shiftBits = _shiftClock = 0;
                }

                break;
            case 12:
                _pcr = value;
                _ca2Pulse = _cb2Pulse = false;
                _ca2Output = CA2Mode != 6;
                _cb2Output = CB2Mode != 6;
                break;
            case 13:
                _ifr &= (byte)~(value & 127);
                break;
            case 14:
                _ier = (value & 128) != 0 ? (byte)(_ier | (value & 127)) : (byte)(_ier & ~value);
                break;
            case 15:
                _ora = value;
                break;
        }

        CountPortBTransition(previousPortB);
    }

    /// <summary>
    ///  Completes one CPU cycle, including timer and generated shift-clock edges.
    /// </summary>
    public void Tick()
    {
        if (_ca2Pulse)
        {
            _ca2Pulse = false;
            _ca2Output = true;
        }

        if (_cb2Pulse)
        {
            _cb2Pulse = false;
            _cb2Output = true;
        }

        if (_t1Started)
        {
            if (_t1Delay)
            {
                _t1Delay = false;
            }
            else if (_t1Counter-- == 0)
            {
                if (_t1Armed || (_acr & 64) != 0)
                {
                    _ifr |= 64;
                    _timerB7 = !_timerB7;
                    _t1Armed = (_acr & 64) != 0;
                }

                if ((_acr & 64) != 0)
                {
                    _t1Counter = _t1Latch;
                    _t1Delay = true;
                }
            }
        }

        if (_t2Started && (_acr & 32) == 0)
        {
            if (_t2Delay)
            {
                _t2Delay = false;
            }
            else
            {
                CountTimer2();
            }
        }

        int mode = ShiftMode;
        if ((!_shiftActive && _serialClock) || mode is 0 or 3 or 7)
        {
            return;
        }

        int halfPeriod = mode is 2 or 6 ? 1 : (_t2Latch & 255) + 2;
        if (++_shiftClock >= halfPeriod)
        {
            _shiftClock = 0;
            _serialClock = !_serialClock;
            SerialEdge(_serialClock);
        }
    }

    /// <summary>
    ///  Resets registers, timers and output pins without altering external input levels.
    /// </summary>
    public void Reset()
    {
        _orb = _ora = _ddrb = _ddra = _acr = _pcr = _ifr = _ier = 0;
        _t1Latch = _t2Latch = _t1Counter = _t2Counter = ushort.MaxValue;
        _t1Started = _t2Started = _t1Armed = _t2Armed = _t1Delay = _t2Delay = false;
        _timerB7 = true;
        _ca2Output = _cb2Output = _serialClock = true;
        _ca2Pulse = _cb2Pulse = _shiftActive = false;
        _shift = 0;
        _shiftBits = _shiftClock = 0;
        _latchedA = _portAInput;
        _latchedB = _portBInput;
    }

    private byte MixPortB(byte input)
    {
        int output = _orb;
        if ((_acr & 128) != 0)
        {
            output = (output & 127) | (_timerB7 ? 128 : 0);
        }

        return (byte)((output & _ddrb) | (input & ~_ddrb));
    }

    private void AccessPort(bool portA, bool handshake)
    {
        int mode = portA ? CA2Mode : CB2Mode;
        int mask = portA ? 2 : 16;
        if (mode is not 1 and not 3)
        {
            mask |= portA ? 1 : 8;
        }

        _ifr &= (byte)~mask;
        if (!handshake || mode is not 4 and not 5)
        {
            return;
        }

        if (portA)
        {
            _ca2Output = false;
            _ca2Pulse = mode == 5;
        }
        else if (ShiftMode == 0)
        {
            _cb2Output = false;
            _cb2Pulse = mode == 5;
        }
    }

    private void CountTimer2()
    {
        if (_t2Counter-- == 0 && _t2Armed)
        {
            _ifr |= 32;
            _t2Armed = false;
        }
    }

    private void CountPortBTransition(byte previous)
    {
        if ((previous & 64) != 0 && (PortB & 64) == 0 && (_acr & 32) != 0 && _t2Started)
        {
            CountTimer2();
        }
    }

    private void StartShift()
    {
        _ifr &= unchecked((byte)~4);
        _shiftBits = _shiftClock = 0;
        _serialClock = true;
        _shiftActive = ShiftMode != 0;
    }

    private void SerialEdge(bool rising)
    {
        int mode = ShiftMode;
        if (!_shiftActive || rising != (mode < 4))
        {
            return;
        }

        _shift = mode < 4
            ? (byte)((_shift << 1) | (_cb2 ? 1 : 0))
            : (byte)((_shift << 1) | ((_shift >> 7) & 1));

        if (++_shiftBits != 8)
        {
            return;
        }

        if (mode == 4)
        {
            _shiftBits = 0;
        }
        else
        {
            _ifr |= 4;
            _shiftActive = false;
        }
    }
}
