// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Apple3;

/// <summary>
///  The Apple III's clock, a National MM58167 at <c>$C070</c>, whose register the zero-page register selects.
/// </summary>
/// <remarks>
///  <para>
///   Registers 0-7 count, in BCD: thousandths, hundredths and tenths of a second, seconds, minutes, hours (24), the
///   day of the week (1-7), the day of the month and the month. 8-15 are the alarm latches, kept as RAM, which is
///   where SOS keeps the year. Writing 18 resets the counters its set bits name, 19 resets the latches, and 21 (GO)
///   resets the thousandths through the seconds; the rest read as zero. The clock raises no interrupts.
///  </para>
///  <para>
///   Each counter is its own register, as on the chip: writing one leaves the others, so a program can set the day
///   before the month whatever the date was. The counters start at <see cref="Now"/> and advance as it does,
///   carrying into each other; the day of the month rolls over at the month's length, February's always 28, as the
///   chip knows no leap years.
///  </para>
/// </remarks>
public sealed class Mm58167
{
    private const int Thousandths = 0;
    private const int Seconds = 1;
    private const int Minutes = 2;
    private const int Hours = 3;
    private const int Weekday = 4;
    private const int Day = 5;
    private const int Month = 6;

    private static readonly int[] s_monthLengths = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];

    private readonly byte[] _latches = new byte[8];

    // The counters, in binary: thousandths of a second (0-999), seconds, minutes, hours, the day of the week, the day
    // of the month and the month, as of _counted.
    private readonly int[] _counters = new int[7];
    private DateTime? _counted;

    /// <summary>
    ///  Gets or sets the time source, the host's local time unless a caller fixes it.
    /// </summary>
    public Func<DateTime> Now { get; set; } = static () => DateTime.Now;

    /// <summary>
    ///  Reads a register.
    /// </summary>
    /// <param name="register">The register; the low five bits are decoded.</param>
    /// <returns>The value.</returns>
    public byte Read(int register)
    {
        register &= 0x1F;
        if (register >= 8) { return register < 16 ? _latches[register & 7] : (byte)0; }
        Advance();
        return register switch
        {
            0 => (byte)(Bcd(_counters[Thousandths] % 10) << 4),
            1 => Bcd(_counters[Thousandths] / 10),
            _ => Bcd(_counters[register - 1])
        };
    }

    /// <summary>
    ///  Writes a register: a counter sets its own count, a latch stores the byte, and the reset commands reset.
    /// </summary>
    /// <param name="register">The register; the low five bits are decoded.</param>
    /// <param name="value">The value, in BCD for the counters.</param>
    public void Write(int register, byte value)
    {
        register &= 0x1F;
        int number = ((value >> 4) * 10) + (value & 0x0F);
        if (register < 8) { Advance(); }
        switch (register)
        {
            case 0:
                _counters[Thousandths] = (_counters[Thousandths] / 10 * 10) + (value >> 4) % 10;
                break;
            case 1:
                _counters[Thousandths] = (number % 100 * 10) + (_counters[Thousandths] % 10);
                break;
            case < 8:
                _counters[register - 1] = number;
                break;
            case < 16:
                _latches[register & 7] = value;
                break;
            case 18:
                Advance();
                ResetCounters(value);
                break;
            case 19:
                Array.Clear(_latches);
                break;
            case 21:
                Advance();
                _counters[Thousandths] = 0;
                _counters[Seconds] = 0;
                break;
        }
    }

    // Resets the counters a counter-reset command's bits name: bit 0 the thousandths, 1 the hundredths and tenths,
    // then one bit a counter from the seconds to the month. The day of the week, the day and the month reset to 1.
    private void ResetCounters(byte bits)
    {
        if ((bits & 0x01) != 0) { _counters[Thousandths] -= _counters[Thousandths] % 10; }
        if ((bits & 0x02) != 0) { _counters[Thousandths] %= 10; }
        for (int counter = Seconds; counter <= Month; counter++)
        {
            if ((bits & (1 << (counter + 1))) != 0) { _counters[counter] = counter >= Weekday ? 1 : 0; }
        }
    }

    // Brings the counters up to the time source: from it the first time, then by the time since, carried through.
    private void Advance()
    {
        DateTime now = Now();
        if (_counted is not { } counted)
        {
            _counters[Thousandths] = now.Millisecond;
            _counters[Seconds] = now.Second;
            _counters[Minutes] = now.Minute;
            _counters[Hours] = now.Hour;
            _counters[Weekday] = (int)now.DayOfWeek + 1;
            _counters[Day] = now.Day;
            _counters[Month] = now.Month;
            _counted = now;
            return;
        }

        long elapsed = (long)(now - counted).TotalMilliseconds;
        if (elapsed <= 0) { return; }
        _counted = counted.AddMilliseconds(elapsed);

        long total = _counters[Thousandths] + elapsed;
        _counters[Thousandths] = (int)(total % 1000);
        total = _counters[Seconds] + (total / 1000);
        _counters[Seconds] = (int)(total % 60);
        total = _counters[Minutes] + (total / 60);
        _counters[Minutes] = (int)(total % 60);
        total = _counters[Hours] + (total / 60);
        _counters[Hours] = (int)(total % 24);
        for (long days = total / 24; days > 0; days--) { NextDay(); }
    }

    private void NextDay()
    {
        _counters[Weekday] = (_counters[Weekday] % 7) + 1;
        int month = _counters[Month];
        int length = month is >= 1 and <= 12 ? s_monthLengths[month - 1] : 31;
        if (++_counters[Day] <= length) { return; }
        _counters[Day] = 1;
        _counters[Month] = month >= 12 ? 1 : month + 1;
    }

    private static byte Bcd(int value) => (byte)(((value / 10 % 10) << 4) | (value % 10));
}
