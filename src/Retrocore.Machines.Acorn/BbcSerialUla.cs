// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Chips;

namespace Retrocore.Machines.Acorn;

/// <summary>
///  The serial ULA: it clocks the 6850 ACIA, switches it between the cassette and RS-423, turns the cassette's tones
///  into bits and bits into tones, and runs the cassette motor relay.
/// </summary>
/// <remarks>
///  <para>
///   Its control register (<c>$FE10</c>, write only): bits 0-2 the transmit clock and 3-5 the receive clock, each the
///   16 MHz crystal over 13 and then over 1, 16, 4, 128, 2, 64, 8 or 256 (19200 to 75 baud with the ACIA dividing by
///   64), bit 6 RS-423 rather than the cassette, bit 7 the motor relay. Reading it writes <c>$FE</c> there, as the
///   data bus holds the address's high byte.
///  </para>
///  <para>
///   Playing a tape, the data separator turns a cycle of 1200 Hz into a 0 and two cycles of 2400 Hz into a 1, each a
///   1200 baud bit with 16 receive clocks for the ACIA; at 300 baud the ACIA divides by 64 and a bit is four of
///   these. Silence starts it again. The run-in detector raises the ACIA's DCD after 100 1s in a row, a twelfth of a
///   second of carrier, which interrupts the MOS as a block's leader starts; a 0 or silence lowers it. Recording,
///   while the ACIA's RTS is low, the modulator's tones come from the crystal, whatever the transmit rate: every
///   1/1200 second it takes the ACIA's transmit data, two cycles of 2400 Hz for a 1, one of 1200 Hz for a 0. While RTS
///   is high it records silence.
///  </para>
///  <para>
///   With RS-423 selected, the ACIA works a character at a time with the host's line: a character takes the time
///   its bits take at the transmit clock and the ACIA's divide. Its DCD is low, and CTS is the line's.
///  </para>
/// </remarks>
public sealed class BbcSerialUla
{
    // The clock's dividers by the 3-bit rate: 16 MHz / 13 / divider.
    private static readonly int[] s_dividers = [1, 16, 4, 128, 2, 64, 8, 256];

    // The cycles without an edge after which the carrier is gone: four units, two of the 1200 Hz tone's half-cycles.
    private const int QuietCycles = 4 * BbcTiming.CpuHertz / Retrocore.Media.Acorn.AcornTape.UnitsPerSecond;

    private readonly Acia6850 _acia;
    private readonly BbcCassette _cassette;
    private int _transmitPhase;
    private int _shortHalves;
    private bool _longHalf;
    private int _ones;
    private bool _carrier;
    private int _quiet;
    // The modulator's clock: "1200 Hz" from the crystal, 16 MHz / 13 / 1024, so 1201.9 Hz, a tape bit every 1664 CPU
    // cycles, which is also the ACIA's bit at 1200 baud, so the two keep step.
    private const int TapeBitCycles = 13 * 1024 / 8;
    private int _tapeCycles;

    /// <summary>
    ///  Creates the ULA.
    /// </summary>
    /// <param name="acia">The ACIA it clocks.</param>
    /// <param name="cassette">The cassette recorder.</param>
    internal BbcSerialUla(Acia6850 acia, BbcCassette cassette)
    {
        _acia = acia;
        _cassette = cassette;
        Write(0x64);
    }

    /// <summary>
    ///  Gets the control register.
    /// </summary>
    public byte Control { get; private set; }

    /// <summary>
    ///  Gets whether RS-423 is selected rather than the cassette.
    /// </summary>
    public bool Rs423 => (Control & 0x40) != 0;

    /// <summary>
    ///  Gets whether the cassette motor relay is closed.
    /// </summary>
    public bool Motor => (Control & 0x80) != 0;

    /// <summary>
    ///  Gets whether the run-in detector hears carrier.
    /// </summary>
    public bool Carrier => _carrier;

    /// <summary>
    ///  Gets or sets the RS-423 line's CTS: high when the other end cannot take a character.
    /// </summary>
    public bool Rs423ClearToSend
    {
        get;
        set
        {
            field = value;
            UpdateLines();
        }
    }

    /// <summary>
    ///  Writes the control register.
    /// </summary>
    /// <param name="value">The value.</param>
    public void Write(byte value)
    {
        bool rs423 = Rs423;
        Control = value;
        _cassette.Motor = Motor;

        // A stopped motor, or a change between the cassette and RS-423, starts the separator again, so the cassette
        // must hear a fresh leader before it has a carrier.
        if (!Motor || rs423 != Rs423)
        {
            ResetSeparator();
            _quiet = 0;
        }

        // The transmit clock's next edge comes within the new rate's period.
        _transmitPhase %= 13 * s_dividers[Control & 7];
        UpdateLines();
        UpdateCharacterTime();
    }

    /// <summary>
    ///  Reads the control register's address, which writes <c>$FE</c> there.
    /// </summary>
    /// <returns>0.</returns>
    public byte Read()
    {
        Write(0xFE);
        return 0;
    }

    /// <summary>
    ///  Sets the ACIA's RS-423 character time, after the ACIA's control register or the transmit clock change.
    /// </summary>
    internal void UpdateCharacterTime()
    {
        int format = (_acia.Control >> 2) & 7;
        int bits = 1 + (format < 4 ? 7 : 8) + (format is 4 or 5 ? 0 : 1) + (format is 0 or 1 or 4 ? 2 : 1);
        int divide = (_acia.Control & 3) switch { 0 => 1, 1 => 16, _ => 64 };

        // A transmit clock is 13/8 of a CPU cycle times the divider.
        long cycles = (long)bits * divide * 13 * s_dividers[Control & 7] / 8;
        _acia.CyclesPerCharacter = (int)Math.Clamp(cycles, 1, int.MaxValue);
    }

    /// <summary>
    ///  Advances one 2 MHz cycle.
    /// </summary>
    internal void Tick()
    {
        if (Rs423)
        {
            // The tape still moves while its motor runs: playing, its tones go nowhere; recording, it records silence,
            // a 1200 baud bit's worth at a time on its own clock, as the cassette's output is cut off.
            _acia.Tick();
            if (!_cassette.Recording)
            {
                _cassette.Tick();
            }
            else if (TapeBit())
            {
                _cassette.Write(4, silence: true);
            }

            return;
        }

        // The transmit clock: 16 MHz / 13 / divider is a CPU cycle times 13/8 times the divider.
        _transmitPhase += 8;
        int period = 13 * s_dividers[Control & 7];
        if (_transmitPhase >= period)
        {
            _transmitPhase -= period;
            _acia.ClockTransmit();
        }

        if (_cassette.Recording)
        {
            if (TapeBit()) { Modulate(); }
            return;
        }

        int half = _cassette.Tick();
        if (half != 0)
        {
            _quiet = 0;
            Separate(half);
        }
        else if (++_quiet == QuietCycles)
        {
            // No edge for longer than the slowest tone's half-cycle: silence, or a tape that stopped, drops the carrier
            // now rather than when the silence ends, and restarts a run-in that had not yet made one; once a quiet spell.
            ResetSeparator();
            UpdateLines();
        }
        else if (_quiet > QuietCycles)
        {
            _quiet = QuietCycles;
        }
    }

    // Whether the modulator's clock has a tape bit's time ready.
    private bool TapeBit()
    {
        if (++_tapeCycles < TapeBitCycles) { return false; }
        _tapeCycles = 0;
        return true;
    }

    // Records one 1200 baud bit, or its time in silence.
    private void Modulate()
    {
        if (_acia.RequestToSendHigh)
        {
            _cassette.Write(4, silence: true);
            return;
        }

        bool one = _acia.TransmitLevel;
        for (int half = 0; half < (one ? 4 : 2); half++) { _cassette.Write(one ? 1 : 2, silence: false); }
    }

    // A half-cycle from the tape: 1 unit is 2400 Hz, 2 is 1200 Hz, longer is silence.
    private void Separate(int length)
    {
        if (length >= 3)
        {
            ResetSeparator();
            UpdateLines();
            return;
        }

        if (length == 1)
        {
            _longHalf = false;
            if (++_shortHalves == 4)
            {
                _shortHalves = 0;
                Bit(one: true);
            }

            return;
        }

        _shortHalves = 0;
        if (_longHalf)
        {
            _longHalf = false;
            Bit(one: false);
        }
        else
        {
            _longHalf = true;
        }
    }

    private void Bit(bool one)
    {
        if (one)
        {
            if (++_ones > 100) { _carrier = true; }
        }
        else
        {
            _ones = 0;
            _carrier = false;
        }

        UpdateLines();
        for (int clock = 0; clock < 16; clock++) { _acia.ClockReceive(one); }
    }

    private void ResetSeparator()
    {
        _shortHalves = 0;
        _longHalf = false;
        _ones = 0;
        _carrier = false;
    }

    private void UpdateLines()
    {
        _acia.DataCarrierDetect = !Rs423 && _carrier;
        _acia.ClearToSend = Rs423 && Rs423ClearToSend;
    }
}
