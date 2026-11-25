// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Chips;

/// <summary>
///  An Atari POKEY (C012294): four audio channels with countdown timers, polynomial noise generators, the keyboard
///  scan, eight pot (paddle) counters, the serial port and the interrupt logic that ties them together.
/// </summary>
/// <remarks>
///  <para>
///   Behaviour follows the POKEY chapter of the Altirra Hardware Reference Manual (chapter 5; section numbers below
///   refer to it), with register names from Atari's Hardware Manual. The register select is the low four bits of the
///   address, $D200-$D20F. Reads: POT0-7 (0-7), ALLPOT (8), KBCODE (9), RANDOM (10), SERIN (13), IRQST (14) and
///   SKSTAT (15); the others read $FF (5.1). Writes: AUDF1/AUDC1 to AUDF4/AUDC4 (0-7), AUDCTL (8), STIMER (9),
///   SKRES (10), POTGO (11), SEROUT (13), IRQEN (14) and SKCTL (15).
///  </para>
///  <para>
///   The board steps POKEY once per machine cycle (1.79 MHz) with <see cref="Tick"/>. A register access belongs to
///   the cycle that the next <see cref="Tick"/> completes, so an event the manual places N cycles after a write is
///   visible after N calls to <see cref="Tick"/>. The 64 kHz and 15 kHz clocks divide the machine clock by 28 and 114;
///   their phase is set when initialization mode ends (5.2), so that a period-0 timer on them first fires 24 and 83
///   cycles after the SKCTL write.
///  </para>
///  <para>
///   Timers (5.3): a timer clocked at 1.79 MHz with AUDFx = N has a period of N+4 cycles, a linked pair N+7, and one
///   clocked at 64 kHz or 15 kHz (N+1)*28 or (N+1)*114. STIMER reloads every counter three cycles after the write
///   and sets the audio output flip-flops, so an 8-bit 1.79 MHz timer with AUDF = 0 first raises its IRQ eight
///   cycles after STIMER. The reload reads AUDF on the reload cycle itself, one cycle later than the hardware's
///   deadline (5.3, reload timing).
///  </para>
///  <para>
///   IRQST and SKSTAT are active low, as the chip reads them. Only enabled interrupts latch into IRQST, and clearing
///   an IRQEN bit clears its status; the serial output complete status (bit 3) is not latched but follows the idle
///   output shift register whether or not it is enabled (5.7). The IRQEN timing windows (an enable must precede
///   its source by four cycles) are not modeled; status latches on the cycle its source fires.
///  </para>
///  <para>
///   Serial (5.6): SKCTL bits 4-6 select the clocks as in Table 10, for example $23 (output and input clocked by
///   channel 4) for SIO transmission and $13 (asynchronous input on channels 3+4, external output clock) for
///   reception. The external and bidirectional clock lines are not modeled, so modes with an external output clock
///   never shift. Reception is bit level from <see cref="SerialInputLevel"/>, clocked by channel 4 (modes 010 and
///   110) or, in asynchronous mode (SKCTL bit 4), by channels 3+4 held in reset until a start bit's leading edge.
///   In either a frame starts on that edge (the input reading low on the cycle after it read high), so a line held
///   low starts no frame. The start bit is sampled on the first timer 4 pulse at or after its edge (in asynchronous
///   mode one full period after, mid-bit), and each bit after it two periods on; SKSTAT bit 1 shows busy from the
///   start bit's sample to the stop bit's, and a stop bit sampled low is a framing error (SKSTAT bit 7).
///   <see cref="ReceiveByte"/> also delivers a whole byte at once, for devices that work a byte at a time.
///  </para>
///  <para>
///   Not modeled: the transitional AND values of a live pot counter (5.9), the gradual refill of RANDOM with ones
///   when initialization mode is entered (it reads $FF at once), the 1.5 cycle high-pass delay, the DAC's
///   mismatched bit weights and saturation (<see cref="Output"/> is a linear sum), the capacitor dump transistors
///   and truncated pot scans, the stereo modification, and in synchronous receive the phase of the divide-by-two
///   clock the input shares with the output (5.6, shift timing): bits are counted from the start bit's edge instead.
///  </para>
/// </remarks>
public sealed class Pokey
{
    /// <summary>
    ///  IRQST/IRQEN bit 0: timer 1 underflowed.
    /// </summary>
    public const byte Timer1Interrupt = 0x01;

    /// <summary>
    ///  IRQST/IRQEN bit 1: timer 2 underflowed.
    /// </summary>
    public const byte Timer2Interrupt = 0x02;

    /// <summary>
    ///  IRQST/IRQEN bit 2: timer 4 underflowed.
    /// </summary>
    public const byte Timer4Interrupt = 0x04;

    /// <summary>
    ///  IRQST/IRQEN bit 3: the serial output shift register is idle (transmission complete). Not latched.
    /// </summary>
    public const byte SerialOutputCompleteInterrupt = 0x08;

    /// <summary>
    ///  IRQST/IRQEN bit 4: SEROUT moved into the output shift register and can take the next byte.
    /// </summary>
    public const byte SerialOutputReadyInterrupt = 0x10;

    /// <summary>
    ///  IRQST/IRQEN bit 5: a byte arrived in SERIN.
    /// </summary>
    public const byte SerialInputReadyInterrupt = 0x20;

    /// <summary>
    ///  IRQST/IRQEN bit 6: the keyboard scan latched a key into KBCODE.
    /// </summary>
    public const byte KeyboardInterrupt = 0x40;

    /// <summary>
    ///  IRQST/IRQEN bit 7: the Break key went down.
    /// </summary>
    public const byte BreakInterrupt = 0x80;

    private const int BorrowDelay = 3;
    private const int StimerReloadDelay = 4;
    private const int Clock64Period = 28;
    private const int Clock15Period = 114;
    private const int Clock64FirstPulse = 21;
    private const int Clock15FirstPulse = 80;
    private const int SlowPotLimit = 228;
    private const int FastPotLimit = 229;
    private const int ControlRow = 0;
    private const int ShiftRow = 2;
    private const int BreakRow = 6;
    private const int ModifierColumn = 0x100;

    private readonly byte[] _audf = new byte[4];
    private readonly byte[] _audc = new byte[4];
    private readonly byte[] _counter = new byte[4];
    private readonly int[] _borrow = new int[4];
    private readonly int[] _reloadDelay = new int[4];
    private readonly bool[] _output = new bool[4];
    private readonly ushort[] _matrix = new ushort[8];
    private readonly byte[] _potTarget = new byte[8];
    private readonly byte[] _pot = new byte[8];

    private byte _audctl;
    private byte _skctl;
    private byte _irqEnable;
    private byte _irqStatus;
    private byte _kbcode;
    private byte _serin;
    private byte _serout;

    // The high-pass flip-flops, which AUDCTL's power-on zero (filters off) holds at 1.
    private bool _highPass1 = true;
    private bool _highPass2 = true;
    private int _resync;
    private bool _twoToneLevel;

    private int _clock64 = Clock64FirstPulse;
    private int _clock15 = Clock15FirstPulse;

    private int _poly4;
    private int _poly5;
    private int _noise = 0x1FFFF;
    private int _poly4History;
    private int _poly5History = 0xFF;
    private int _noiseHistory;

    private int _scanCounter;
    private int _compare;
    private int _keyState;
    private bool _controlLatch;
    private bool _shiftLatch;
    private bool _breakLatch;
    private bool _keyboardOverrun;

    private bool _potScanning;
    private bool _potClearing;
    private bool _potPulsePending;
    private int _potEndDelay;
    private int _potCounter;
    private byte _allPot;

    private bool _seroutPending;
    private int _outShift;
    private byte _outByte;
    private bool _outClock;
    // The bit on SIO DATA OUT, which nothing resets (Altirra Hardware Reference Manual, 5.6). It powers on in no fixed
    // state; ours is high, idle.
    private bool _serialDataBit = true;
    private bool _serialOverrun;
    private bool _framingError;
    // A frame has begun (the input read low); in asynchronous mode it lets timers 3+4 run.
    private bool _inBusy;
    // SKSTAT bit 1: set when the start bit is sampled and cleared when the stop bit is (5.6, serial input).
    private bool _inShifting;
    // The input level the last Tick saw, to find a start bit's leading edge.
    private bool _inputWasHigh = true;
    private int _inPulses;
    private int _inShift;

    /// <summary>
    ///  Creates a POKEY as this model powers it up: every register zero, so initialization mode is active (SKCTL bits
    ///  0-1 clear), interrupts are disabled and the serial output is idle.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   The real chip has no reset line and powers up in an indeterminate state (5.2); software is expected to
    ///   clear IRQEN and SKCTL before relying on it, which this state already matches.
    ///  </para>
    /// </remarks>
    public Pokey() => EnterInitialization();

    /// <summary>
    ///  Gets or sets what receives each byte when the last bit of its frame (start bit, eight data bits least
    ///  significant first, stop bit) has been shifted out.
    /// </summary>
    public Action<byte>? SerialByteSent { get; set; }

    /// <summary>
    ///  Gets whether POKEY drives its IRQ output: an enabled interrupt status bit is active.
    /// </summary>
    public bool InterruptRequest => (ActiveStatus & _irqEnable) != 0;

    /// <summary>
    ///  Gets the summed audio level of the four channels this cycle: the sum of the volumes (AUDCx bits 0-3) of the
    ///  channels whose output is high or that are in volume-only mode, from 0 to 60.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   The sum is linear; the hardware's mixer compresses the upper range (5.3, volume control). Channels 1 and 2
    ///   pass through the high-pass XOR, which inverts them when the filter is off, as the chip does.
    ///  </para>
    /// </remarks>
    public float Output
    {
        get
        {
            int sum = 0;
            for (int channel = 0; channel < 4; channel++)
            {
                if (ChannelLevel(channel))
                {
                    sum += _audc[channel] & 0x0F;
                }
            }

            return sum;
        }
    }

    /// <summary>
    ///  Sets the output shift register's current bit, which powers on in no fixed state, for a test that matches
    ///  another emulator's choice.
    /// </summary>
    internal bool SerialDataBit
    {
        set => _serialDataBit = value;
    }

    /// <summary>
    ///  Gets the level on the SIO DATA OUT line: the output shift register's current bit, low while SKCTL bit 7 forces
    ///  a break, or the two-tone square wave when SKCTL bit 3 selects two-tone mode.
    /// </summary>
    public bool SerialOutputLevel =>
        (_skctl & 0x08) != 0 ? _twoToneLevel : (_skctl & 0x80) == 0 && _serialDataBit;

    /// <summary>
    ///  Gets or sets the level on the SIO DATA IN line, which SKSTAT bit 4 reads directly. High is idle (mark).
    /// </summary>
    public bool SerialInputLevel { get; set; } = true;

    /// <summary>
    ///  Gets AUDCTL, the audio control register.
    /// </summary>
    public byte AudioControl => _audctl;

    /// <summary>
    ///  Gets SKCTL, the serial port and keyboard control register.
    /// </summary>
    public byte SerialControl => _skctl;

    /// <summary>
    ///  Gets IRQEN, the interrupt enable register.
    /// </summary>
    public byte InterruptEnable => _irqEnable;

    /// <summary>
    ///  Gets IRQST as a read returns it: a 0 bit is an active interrupt.
    /// </summary>
    public byte InterruptStatus => (byte)~ActiveStatus;

    /// <summary>
    ///  Gets SKSTAT as a read returns it: bits are active low.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   Bit 7 serial framing error, 6 keyboard overrun, 5 serial overrun, 4 the serial input line itself, 3 Shift
    ///   down, 2 a key down, 1 the serial input shift register busy; bit 0 reads 1.
    ///  </para>
    /// </remarks>
    public byte SerialStatus
    {
        get
        {
            int value = 0xFF;
            if (_keyboardOverrun) { value &= ~0x40; }
            if (_framingError) { value &= ~0x80; }
            if (_serialOverrun) { value &= ~0x20; }
            if (_inShifting) { value &= ~0x02; }
            if (!SerialInputLevel) { value &= ~0x10; }
            if (_shiftLatch) { value &= ~0x08; }
            if (_keyState >= 2) { value &= ~0x04; }
            return (byte)value;
        }
    }

    /// <summary>
    ///  Gets KBCODE: the last key code latched by the scan, with Shift in bit 6 and Control in bit 7.
    /// </summary>
    public byte KeyboardCode => _kbcode;

    /// <summary>
    ///  Gets or sets whether a Shift key is down. Shift sits on the KR2 line in the row of scan codes $10-$17.
    /// </summary>
    public bool Shift
    {
        get => (_matrix[ShiftRow] & ModifierColumn) != 0;
        set => SetMatrix(ShiftRow, ModifierColumn, value);
    }

    /// <summary>
    ///  Gets or sets whether the Control key is down. Control sits on the KR2 line in the row of scan codes $00-$07.
    /// </summary>
    public bool Control
    {
        get => (_matrix[ControlRow] & ModifierColumn) != 0;
        set => SetMatrix(ControlRow, ModifierColumn, value);
    }

    /// <summary>
    ///  Gets or sets whether the Break key is down. Break sits on the KR2 line in the row of scan codes $30-$37.
    /// </summary>
    public bool Break
    {
        get => (_matrix[BreakRow] & ModifierColumn) != 0;
        set => SetMatrix(BreakRow, ModifierColumn, value);
    }

    /// <summary>
    ///  Gets whether initialization mode is active (SKCTL bits 0 and 1 both clear), holding the 15 kHz and 64 kHz
    ///  clocks, the noise generators, the serial state machines and the keyboard scan in reset.
    /// </summary>
    public bool InitializationMode => (_skctl & 0x03) == 0;

    private byte ActiveStatus =>
        (byte)((_irqStatus & ~SerialOutputCompleteInterrupt) | (_outShift == 0 ? SerialOutputCompleteInterrupt : 0));

    /// <summary>
    ///  Gets a channel's frequency register, AUDFx.
    /// </summary>
    /// <param name="channel">The channel index, 0-3 for channels 1-4.</param>
    /// <returns>The register.</returns>
    public byte Frequency(int channel) => _audf[channel & 3];

    /// <summary>
    ///  Gets a channel's control register, AUDCx: distortion in bits 4-7 and volume in bits 0-3.
    /// </summary>
    /// <param name="channel">The channel index, 0-3 for channels 1-4.</param>
    /// <returns>The register.</returns>
    public byte ChannelControl(int channel) => _audc[channel & 3];

    /// <summary>
    ///  Presses or releases a key of the 8x8 matrix.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   The high three bits of the code pick the row and the low three the column. Keys are not isolated by diodes,
    ///   so three keys on the corners of a rectangle (Shift, Control and Break included) also close the fourth
    ///   (5.8, key conflicts).
    ///  </para>
    /// </remarks>
    /// <param name="code">The key code as KBCODE bits 0-5 report it.</param>
    /// <param name="pressed">Whether the key is down.</param>
    public void SetKey(int code, bool pressed) => SetMatrix((code >> 3) & 7, 1 << (code & 7), pressed);

    /// <summary>
    ///  Sets the count at which a pot input reaches its threshold during a scan.
    /// </summary>
    /// <param name="index">The pot, 0-7.</param>
    /// <param name="value">
    ///  The count, 0-228; larger values never reach the threshold and read 228 in the slow scan, 229 in the fast.
    /// </param>
    public void SetPot(int index, byte value) => _potTarget[index & 7] = value;

    /// <summary>
    ///  Delivers a received byte to SERIN, as if its stop bit had just been sampled.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   If the serial input ready interrupt (IRQST bit 5) is still active the byte overruns: SKSTAT bit 5 is set
    ///   until SKRES. Otherwise the interrupt latches if enabled (5.6, overrun errors). In initialization mode the
    ///   input state machine is held in reset and the byte is lost.
    ///  </para>
    /// </remarks>
    /// <param name="value">The byte.</param>
    public void ReceiveByte(byte value)
    {
        if (InitializationMode) { return; }
        LoadSerin(value);
    }

    // A received byte reaches SERIN: an overrun if the last one's interrupt is still active.
    private void LoadSerin(byte value)
    {
        _serin = value;
        if ((_irqStatus & SerialInputReadyInterrupt) != 0)
        {
            _serialOverrun = true;
        }
        else
        {
            Raise(SerialInputReadyInterrupt);
        }
    }

    /// <summary>
    ///  Reads a register. POKEY's reads have no side effects, so this is <see cref="Peek"/>.
    /// </summary>
    /// <param name="register">The register select; only the low four bits count.</param>
    /// <returns>The value.</returns>
    public byte Read(int register) => Peek(register);

    /// <summary>
    ///  Reads a register without side effects.
    /// </summary>
    /// <param name="register">The register select; only the low four bits count.</param>
    /// <returns>The value; unassigned registers read $FF.</returns>
    public byte Peek(int register)
    {
        register &= 0x0F;
        return register switch
        {
            < 8 => (_allPot & (1 << register)) != 0 ? (byte)_potCounter : _pot[register],
            8 => _allPot,
            9 => _kbcode,
            10 => (byte)_noise,
            13 => _serin,
            14 => InterruptStatus,
            15 => SerialStatus,
            _ => 0xFF,
        };
    }

    /// <summary>
    ///  Writes a register.
    /// </summary>
    /// <param name="register">The register select; only the low four bits count.</param>
    /// <param name="value">The value.</param>
    public void Write(int register, byte value)
    {
        register &= 0x0F;
        switch (register)
        {
            case < 8:
                if ((register & 1) == 0)
                {
                    _audf[register >> 1] = value;
                }
                else
                {
                    _audc[register >> 1] = value;
                }

                break;
            case 8:
                _audctl = value;
                _highPass1 |= (value & 0x04) == 0;
                _highPass2 |= (value & 0x02) == 0;
                break;
            case 9:
                WriteStimer();
                break;
            case 10:
                _framingError = false;
                _keyboardOverrun = false;
                _serialOverrun = false;
                break;
            case 11:
                StartPotScan();
                break;
            case 13:
                _serout = value;
                _seroutPending = !InitializationMode;
                break;
            case 14:
                _irqEnable = value;
                _irqStatus &= value;
                break;
            case 15:
                WriteSkctl(value);
                break;
        }
    }

    /// <summary>
    ///  Advances one machine cycle: the clocks and noise generators, the four timers with their audio and interrupt
    ///  outputs, the serial port, the pot scan and the keyboard scan.
    /// </summary>
    public void Tick()
    {
        bool pulse64 = false;
        bool pulse15 = false;
        if (!InitializationMode)
        {
            StepPolynomials();
            if (--_clock64 == 0)
            {
                _clock64 = Clock64Period;
                pulse64 = true;
            }

            if (--_clock15 == 0)
            {
                _clock15 = Clock15Period;
                pulse15 = true;
            }
        }

        bool basePulse = (_audctl & 0x01) != 0 ? pulse15 : pulse64;
        bool linked12 = (_audctl & 0x10) != 0;
        bool linked34 = (_audctl & 0x08) != 0;

        // Channels 1 and 2.
        bool fire1 = Count(0, (_audctl & 0x40) != 0 || basePulse);
        bool fire2;
        if (linked12)
        {
            fire2 = Count(1, fire1);
            if (fire2)
            {
                Reload(0);
                Reload(1);
            }
        }
        else
        {
            if (fire1) { Reload(0); }
            fire2 = Count(1, basePulse);
            if (fire2) { Reload(1); }
        }

        // Channels 3 and 4, held in reset by asynchronous receive while the input waits for a start bit; the start
        // bit's leading edge (the input reading low the cycle after it read high) lets them run.
        bool fire3 = false;
        bool fire4 = false;
        bool asynchronous = (_skctl & 0x10) != 0;
        bool startEdge = _inputWasHigh && !SerialInputLevel;
        _inputWasHigh = SerialInputLevel;
        if (asynchronous && !_inBusy && startEdge && !InitializationMode)
        {
            _inBusy = true;
            _inPulses = 0;
            _inShift = 0;
        }

        if (asynchronous && !_inBusy)
        {
            Hold(2);
            Hold(3);
        }
        else
        {
            fire3 = Count(2, (_audctl & 0x20) != 0 || basePulse);
            if (linked34)
            {
                fire4 = Count(3, fire3);
                if (fire4)
                {
                    Reload(2);
                    Reload(3);
                }
            }
            else
            {
                if (fire3) { Reload(2); }
                fire4 = Count(3, basePulse);
                if (fire4) { Reload(3); }
            }
        }

        if (fire1)
        {
            Raise(Timer1Interrupt);
            ClockAudio(0);
        }

        if (fire2)
        {
            Raise(Timer2Interrupt);
            ClockAudio(1);
        }

        // A high-pass flip-flop latches its channel's output when the high channel fires, and is held at 1 while its
        // filter is off (5.3, high-pass filter).
        if (fire3)
        {
            ClockAudio(2);
            if ((_audctl & 0x04) != 0) { _highPass1 = _output[0]; }
        }

        if (fire4)
        {
            Raise(Timer4Interrupt);
            ClockAudio(3);
            if ((_audctl & 0x02) != 0) { _highPass2 = _output[1]; }
        }

        StepTwoTone(fire1, fire2);
        StepSerialOutput(fire2, fire4);
        StepSerialInput(fire4, startEdge);

        // The slow scan's counter steps the cycle after each 15 kHz pulse (5.9, scan timing).
        bool potClock = (_skctl & 0x04) != 0 || _potPulsePending;
        _potPulsePending = pulse15;
        StepPots(potClock);

        if (pulse15 && (_skctl & 0x02) != 0)
        {
            StepKeyboard();
        }
    }

    private bool ChannelLevel(int channel)
    {
        byte audc = _audc[channel];
        if ((audc & 0x10) != 0) { return true; }
        bool level = _output[channel];
        return channel switch
        {
            0 => level ^ _highPass1,
            1 => level ^ _highPass2,
            _ => level,
        };
    }

    private void Raise(byte bit)
    {
        if ((_irqEnable & bit) != 0)
        {
            _irqStatus |= bit;
        }
    }

    private bool Count(int channel, bool clock)
    {
        bool fire = _borrow[channel] > 0 && --_borrow[channel] == 0;
        if (_reloadDelay[channel] > 0)
        {
            if (--_reloadDelay[channel] == 0)
            {
                _counter[channel] = _audf[channel];
            }

            return fire;
        }

        if (clock && _counter[channel]-- == 0 && _borrow[channel] == 0)
        {
            _borrow[channel] = BorrowDelay;
        }

        return fire;
    }

    private void Reload(int channel) => _counter[channel] = _audf[channel];

    private void Hold(int channel)
    {
        _counter[channel] = _audf[channel];
        _borrow[channel] = 0;
        _reloadDelay[channel] = 0;
    }

    private void WriteStimer()
    {
        for (int channel = 0; channel < 4; channel++)
        {
            _reloadDelay[channel] = StimerReloadDelay;
            _output[channel] = true;
        }
    }

    private void ClockAudio(int channel)
    {
        byte audc = _audc[channel];
        if ((audc & 0x80) == 0 && !Poly5Bit(channel)) { return; }
        if ((audc & 0x20) != 0)
        {
            _output[channel] = !_output[channel];
        }
        else if ((audc & 0x40) != 0)
        {
            _output[channel] = Poly4Bit(channel);
        }
        else
        {
            _output[channel] = NoiseBit(channel);
        }
    }

    // Each generator's bit reaches channel 1 first and each later channel one cycle after (5.5).
    private bool Poly4Bit(int channel) =>
        channel == 0 ? (_poly4 & 0x08) != 0 : ((_poly4History >> (channel - 1)) & 1) != 0;

    private bool Poly5Bit(int channel) =>
        InitializationMode
            || (channel == 0 ? (_poly5 & 0x10) != 0 : ((_poly5History >> (channel - 1)) & 1) != 0);

    private bool NoiseBit(int channel) =>
        channel == 0 ? (_noise & 1) == 0 : ((_noiseHistory >> (channel - 1)) & 1) != 0;

    private void StepPolynomials()
    {
        // 4-bit 1+x^3+x^4 and 5-bit 1+x^3+x^5 XNOR generators, shifting left from zero.
        _poly4History = (_poly4History << 1) | ((_poly4 >> 3) & 1);
        _poly4 = ((_poly4 << 1) | (~((_poly4 >> 3) ^ (_poly4 >> 2)) & 1)) & 0x0F;
        _poly5History = (_poly5History << 1) | ((_poly5 >> 4) & 1);
        _poly5 = ((_poly5 << 1) | (~((_poly5 >> 4) ^ (_poly5 >> 2)) & 1)) & 0x1F;

        // The 9/17-bit generator, kept as RANDOM reads it (inverted from the audio bits) and shifting right.
        _noiseHistory = (_noiseHistory << 1) | (~_noise & 1);
        int feedback = (_noise ^ (_noise >> 5)) & 1;
        _noise = (_audctl & 0x80) != 0
            ? ((_noise >> 1) & 0xFF) | (feedback << 8)
            : (_noise >> 1) | (feedback << 16);
    }

    private void StepTwoTone(bool fire1, bool fire2)
    {
        // The resync reload two cycles after the triggering timer's also cancels an underflow already under way, so a
        // 1.79 MHz timer 1 that drives it runs two cycles longer each period (5.6, two-tone resync timing).
        if ((_resync & 1) != 0)
        {
            Reload(0);
            Reload(1);
            _borrow[0] = 0;
            _borrow[1] = 0;
        }

        _resync >>= 1;
        if ((_skctl & 0x08) == 0) { return; }

        // Timer 2 always toggles the output and resyncs; timer 1 only for a 1 bit (5.6, two-tone resync).
        bool mark = (_skctl & 0x80) == 0 && _serialDataBit;
        if (fire2 || (fire1 && mark))
        {
            _twoToneLevel = !_twoToneLevel;
            _resync |= 2;
        }
    }

    private void StepSerialOutput(bool fire2, bool fire4)
    {
        bool clock = ((_skctl >> 4) & 7) switch
        {
            2 or 3 or 4 or 5 => fire4,
            6 or 7 => fire2,
            _ => false,
        };

        if (!clock) { return; }
        _outClock = !_outClock;
        if (!_outClock || InitializationMode) { return; }

        if (_outShift > 1)
        {
            _outShift >>= 1;
            _serialDataBit = (_outShift & 1) != 0;
            return;
        }

        if (_outShift == 1)
        {
            _outShift = 0;
            SerialByteSent?.Invoke(_outByte);
        }

        if (_seroutPending)
        {
            _seroutPending = false;
            _outByte = _serout;
            _outShift = (_serout << 1) | 0x200;
            _serialDataBit = false;
            Raise(SerialOutputReadyInterrupt);
        }
    }

    // The input shift register: in asynchronous mode it counts timer 4's pulses from the start bit and samples on
    // the odd ones (the middle of each bit); in synchronous mode a start bit's leading edge starts a byte the same way.
    private void StepSerialInput(bool fire4, bool startEdge)
    {
        int mode = (_skctl >> 4) & 7;
        bool clocked = (mode & 1) != 0 || mode is 2 or 6;
        if (!clocked || InitializationMode)
        {
            _inBusy = false;
            _inShifting = false;
            return;
        }

        if (!_inBusy)
        {
            if (!startEdge) { return; }
            _inBusy = true;
            _inPulses = 0;
            _inShift = 0;
        }

        if (!fire4) { return; }
        int pulse = ++_inPulses;
        if ((pulse & 1) == 0) { return; }
        int bit = pulse >> 1;
        if (bit == 0)
        {
            // A start bit that has gone high again by its middle was noise.
            if (SerialInputLevel)
            {
                _inBusy = false;
            }
            else
            {
                _inShifting = true;
            }

            return;
        }

        if (bit <= 8)
        {
            if (SerialInputLevel) { _inShift |= 1 << (bit - 1); }
            return;
        }

        // The stop bit.
        _framingError |= !SerialInputLevel;
        _inBusy = false;
        _inShifting = false;
        LoadSerin((byte)_inShift);
    }

    private void StartPotScan()
    {
        _potCounter = 0;
        _allPot = 0xFF;
        _potScanning = true;
        _potClearing = true;
        _potEndDelay = 0;
        LatchPots();
    }

    // The scan counter: cleared during the cycle after POTGO, then stepped by each clock. Once it reaches its limit
    // (228 slow, overrunning to 229 fast) the pots still counting latch it, and ALLPOT reads $00 two cycles after the
    // slow scan's last step or one cycle after the fast scan's (5.9, scan timing).
    private void StepPots(bool clock)
    {
        if (_potEndDelay > 0)
        {
            if (--_potEndDelay == 0) { _allPot = 0; }
            return;
        }

        if (!_potScanning) { return; }
        if (_potClearing)
        {
            _potClearing = false;
            return;
        }

        if (!clock) { return; }
        _potCounter++;
        bool fast = (_skctl & 0x04) != 0;
        if (_potCounter >= (fast ? FastPotLimit : SlowPotLimit))
        {
            for (int pot = 0; pot < 8; pot++)
            {
                if ((_allPot & (1 << pot)) != 0)
                {
                    _pot[pot] = (byte)_potCounter;
                }
            }

            _potScanning = false;
            _potEndDelay = fast ? 1 : 2;
            return;
        }

        LatchPots();
    }

    private void LatchPots()
    {
        for (int pot = 0; pot < 8; pot++)
        {
            int bit = 1 << pot;
            if ((_allPot & bit) != 0 && _potCounter >= _potTarget[pot])
            {
                _pot[pot] = (byte)_potCounter;
                _allPot &= (byte)~bit;
            }
        }
    }

    private void StepKeyboard()
    {
        int code = _scanCounter;
        _scanCounter = (code + 1) & 0x3F;
        int columns = ConnectedColumns(code >> 3);
        bool keyDown = ((columns >> (code & 7)) & 1) != 0;
        bool modifier = (columns & ModifierColumn) != 0;
        switch (code)
        {
            case 0x00:
                _controlLatch = modifier;
                break;
            case 0x10:
                _shiftLatch = modifier;
                break;
            case 0x30:
                if (modifier && !_breakLatch) { Raise(BreakInterrupt); }
                _breakLatch = modifier;
                break;
        }

        // Without debounce (SKCTL bit 0) every comparison passes (5.8, scan algorithm).
        bool match = (_skctl & 0x01) == 0 || _compare == code;
        switch (_keyState)
        {
            case 0:
                if (keyDown)
                {
                    _compare = code;
                    _keyState = 1;
                }

                break;
            case 1:
                if (match && keyDown)
                {
                    _kbcode = (byte)(code | (_shiftLatch ? 0x40 : 0) | (_controlLatch ? 0x80 : 0));
                    if ((_irqStatus & KeyboardInterrupt) != 0) { _keyboardOverrun = true; }
                    Raise(KeyboardInterrupt);
                    _keyState = 3;
                }
                else if (match || keyDown)
                {
                    _keyState = 0;
                }

                break;
            case 3:
                if (match && !keyDown) { _keyState = 2; }
                break;
            case 2:
                // The manual gives only the key-up path; a key down again on its next scan is taken as still held
                // (a bounce on release), returning to state 3 without a second IRQ.
                if (match) { _keyState = keyDown ? 3 : 0; }
                break;
        }
    }

    // The columns (bit 8 is KR2) that reach a row through the pressed keys, phantom paths included.
    private int ConnectedColumns(int row)
    {
        int rows = 1 << row;
        int columns = 0;
        while (true)
        {
            int newColumns = 0;
            int newRows = rows;
            for (int r = 0; r < 8; r++)
            {
                if ((rows & (1 << r)) != 0) { newColumns |= _matrix[r]; }
            }

            for (int r = 0; r < 8; r++)
            {
                if ((_matrix[r] & newColumns) != 0) { newRows |= 1 << r; }
            }

            if (newRows == rows && newColumns == columns) { return columns; }
            rows = newRows;
            columns = newColumns;
        }
    }

    private void SetMatrix(int row, int column, bool pressed)
    {
        if (pressed)
        {
            _matrix[row] |= (ushort)column;
        }
        else
        {
            _matrix[row] &= (ushort)~column;
        }
    }

    private void WriteSkctl(byte value)
    {
        bool wasInitialization = InitializationMode;
        _skctl = value;
        if (InitializationMode)
        {
            EnterInitialization();
        }
        else if (wasInitialization)
        {
            _clock64 = Clock64FirstPulse;
            _clock15 = Clock15FirstPulse;
        }

        if ((value & 0x02) == 0)
        {
            _scanCounter = 0;
            _keyState = 0;
        }

        if ((value & 0x70) == 0)
        {
            _outClock = false;
        }

        if ((value & 0x08) == 0)
        {
            _twoToneLevel = false;
        }
    }

    private void EnterInitialization()
    {
        _clock64 = Clock64FirstPulse;
        _clock15 = Clock15FirstPulse;
        _poly4 = 0;
        _poly5 = 0;
        _noise = 0x1FFFF;
        _poly4History = 0;
        _poly5History = 0xFF;
        _noiseHistory = 0;
        _scanCounter = 0;
        _keyState = 0;

        // The output state machine stops and the queued byte is flushed, but the line keeps its last bit.
        _outShift = 0;
        _seroutPending = false;
        _inBusy = false;
        _inShifting = false;
        _potPulsePending = false;
    }
}
