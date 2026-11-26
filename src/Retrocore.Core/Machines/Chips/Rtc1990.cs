// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Chips;

/// <summary>
///  An NEC uPD1990AC serial calendar clock: seconds to month and day of the week, read and set through a 40-bit
///  shift register, and a TP output of 64, 256 or 2048 Hz.
/// </summary>
/// <remarks>
///  <para>
///   A command on C0-C2 is taken when STB rises: 0 register hold (DATA OUT shows a 1 Hz square wave), 1 register
///   shift (DATA OUT shows the shift register's bit 0, and each rising CLK shifts it right, DATA IN entering bit 39),
///   2 time set (the counters are loaded from the shift register), 3 time read (the shift register is loaded from the
///   counters), and 4, 5 and 6 set TP to 64, 256 and 2048 Hz. 7, the test mode, is taken as a hold.
///  </para>
///  <para>
///   The shift register's fields, from bit 0: seconds, minutes, hours and the day of the month, eight bits of BCD
///   each, then the day of the week (0 Sunday) and the month (1 to 12), four binary bits each. The chip has no year,
///   so February always has 28 days here. Chip select and output enable are taken as tied high, as the Model 100
///   and its relatives wire them.
///  </para>
/// </remarks>
public sealed class Rtc1990
{
    private static readonly int[] s_daysInMonth = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];

    private readonly int _cyclesPerSecond;
    private int _command;
    private int _pendingCommand;
    private bool _strobe;
    private bool _clock;
    private ulong _shift;
    private int _tpHalfPeriod;
    private int _tpCount;
    private int _secondCount;

    private int _second;
    private int _minute;
    private int _hour;
    private int _day = 1;
    private int _weekday;
    private int _month = 1;

    /// <summary>
    ///  Creates a clock.
    /// </summary>
    /// <param name="cyclesPerSecond">How many <see cref="Tick"/>s make a second; a multiple of 4096.</param>
    /// <exception cref="ArgumentOutOfRangeException">The rate cannot make TP's frequencies exactly.</exception>
    public Rtc1990(int cyclesPerSecond)
    {
        if (cyclesPerSecond <= 0 || cyclesPerSecond % 4096 != 0)
        {
            throw new ArgumentOutOfRangeException(nameof(cyclesPerSecond));
        }

        _cyclesPerSecond = cyclesPerSecond;
        _tpHalfPeriod = cyclesPerSecond / 128;
    }

    /// <summary>
    ///  Gets TP, the timing pulse output.
    /// </summary>
    public bool TimingPulse { get; private set; }

    /// <summary>
    ///  Gets DATA OUT.
    /// </summary>
    public bool DataOut => _command switch
    {
        1 => (_shift & 1) != 0,
        _ => _secondCount < _cyclesPerSecond / 2
    };

    /// <summary>
    ///  Gets or sets what is told when TP changes, with its new level.
    /// </summary>
    public Action<bool>? TimingPulseChanged { get; set; }

    /// <summary>
    ///  Gets TP's frequency in hertz.
    /// </summary>
    public int TimingPulseHertz => _cyclesPerSecond / (2 * _tpHalfPeriod);

    /// <summary>
    ///  Gets the time the counters hold. The year is the one given to <see cref="SetTime"/>, as the chip keeps none.
    /// </summary>
    /// <param name="year">The year to give the result.</param>
    /// <returns>The time.</returns>
    public DateTime Time(int year)
    {
        int month = Math.Clamp(_month, 1, 12);
        return new(year, month, Math.Clamp(_day, 1, DateTime.DaysInMonth(year, month)), _hour % 24, _minute % 60, _second % 60);
    }

    /// <summary>
    ///  Gets the day of the week the counters hold, 0 for Sunday.
    /// </summary>
    public int Weekday => _weekday;

    /// <summary>
    ///  Sets the counters, as a time-set command would.
    /// </summary>
    /// <param name="time">The time; its year is not kept.</param>
    public void SetTime(DateTime time)
    {
        _second = time.Second;
        _minute = time.Minute;
        _hour = time.Hour;
        _day = time.Day;
        _month = time.Month;
        _weekday = (int)time.DayOfWeek;
        _secondCount = 0;
    }

    /// <summary>
    ///  Sets the control inputs, as the lines carry them.
    /// </summary>
    /// <param name="command">C0-C2.</param>
    /// <param name="clock">CLK.</param>
    /// <param name="dataIn">DATA IN.</param>
    public void SetInputs(int command, bool clock, bool dataIn)
    {
        if (clock && !_clock && _command == 1)
        {
            _shift = (_shift >> 1) | (dataIn ? 1UL << 39 : 0);
        }

        _clock = clock;
        _pendingCommand = command & 7;
    }

    /// <summary>
    ///  Sets STB; a rising edge takes the command on C0-C2.
    /// </summary>
    /// <param name="strobe">The level.</param>
    public void SetStrobe(bool strobe)
    {
        if (strobe && !_strobe) { Execute(_pendingCommand); }
        _strobe = strobe;
    }

    /// <summary>
    ///  Advances the clock one cycle of the rate it was made with.
    /// </summary>
    public void Tick()
    {
        if (++_tpCount >= _tpHalfPeriod)
        {
            _tpCount = 0;
            TimingPulse = !TimingPulse;
            TimingPulseChanged?.Invoke(TimingPulse);
        }

        if (++_secondCount >= _cyclesPerSecond)
        {
            _secondCount = 0;
            AdvanceSecond();
        }
    }

    private void Execute(int command)
    {
        switch (command)
        {
            case 2:
                _second = FromBcd((int)(_shift & 0xFF));
                _minute = FromBcd((int)((_shift >> 8) & 0xFF));
                _hour = FromBcd((int)((_shift >> 16) & 0xFF));
                _day = FromBcd((int)((_shift >> 24) & 0xFF));
                _weekday = (int)((_shift >> 32) & 0xF);
                _month = (int)((_shift >> 36) & 0xF);
                _secondCount = 0;
                break;
            case 3:
                _shift = ToBcd(_second) | (ToBcd(_minute) << 8) | (ToBcd(_hour) << 16) | (ToBcd(_day) << 24);
                _shift |= (ulong)(uint)(_weekday & 0xF) << 32;
                _shift |= (ulong)(uint)(_month & 0xF) << 36;
                break;
            case 4:
                _tpHalfPeriod = _cyclesPerSecond / 128;
                break;
            case 5:
                _tpHalfPeriod = _cyclesPerSecond / 512;
                break;
            case 6:
                _tpHalfPeriod = _cyclesPerSecond / 4096;
                break;
        }

        _command = command is 1 ? 1 : command is 7 ? 0 : command;
        if (_tpCount >= _tpHalfPeriod) { _tpCount = 0; }
    }

    private void AdvanceSecond()
    {
        if (++_second < 60) { return; }
        _second = 0;
        if (++_minute < 60) { return; }
        _minute = 0;
        if (++_hour < 24) { return; }
        _hour = 0;
        _weekday = (_weekday + 1) % 7;
        int days = _month is >= 1 and <= 12 ? s_daysInMonth[_month - 1] : 31;
        if (++_day <= days) { return; }
        _day = 1;
        _month = _month >= 12 ? 1 : _month + 1;
    }

    private static ulong ToBcd(int value) => (ulong)(uint)(((value / 10) << 4) | (value % 10));

    private static int FromBcd(int value) => (value >> 4) * 10 + (value & 0xF);
}
