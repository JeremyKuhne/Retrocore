// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Apple3;

/// <summary>
///  The Apple III's clock, a National MM58167 at <c>$C070</c>, whose register the zero-page register selects.
/// </summary>
/// <remarks>
///  <para>
///   Registers 0-7 count, in BCD: ten-thousandths, hundredths and tenths of a second, seconds, minutes, hours (24),
///   the day of the week (1-7), the day of the month and the month. 8-15 are the alarm latches, kept as RAM, which is
///   where SOS keeps the year. 18 resets counters, 19 resets the latches; the rest read as zero. The counters follow
///   <see cref="Now"/> plus whatever the program set; the clock raises no interrupts.
///  </para>
/// </remarks>
public sealed class Mm58167
{
    private readonly byte[] _latches = new byte[8];
    private TimeSpan _offset;

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
        DateTime time = Time;
        return (register & 0x1F) switch
        {
            0 => (byte)(Bcd(time.Millisecond % 10) << 4),
            1 => Bcd(time.Millisecond / 10),
            2 => Bcd(time.Second),
            3 => Bcd(time.Minute),
            4 => Bcd(time.Hour),
            5 => (byte)((int)time.DayOfWeek + 1),
            6 => Bcd(time.Day),
            7 => Bcd(time.Month),
            >= 8 and < 16 => _latches[register & 7],
            _ => 0
        };
    }

    /// <summary>
    ///  Writes a register: a counter sets that field of the time, a latch stores the byte.
    /// </summary>
    /// <param name="register">The register; the low five bits are decoded.</param>
    /// <param name="value">The value, in BCD for the counters.</param>
    public void Write(int register, byte value)
    {
        DateTime time = Time;
        int number = ((value >> 4) * 10) + (value & 0x0F);
        DateTime set = (register & 0x1F) switch
        {
            2 when number < 60 => time.AddSeconds(number - time.Second),
            3 when number < 60 => time.AddMinutes(number - time.Minute),
            4 when number < 24 => time.AddHours(number - time.Hour),
            6 when number is >= 1 and <= 31 => time.AddDays(number - time.Day),
            7 when number is >= 1 and <= 12 => time.AddMonths(number - time.Month),
            _ => time
        };

        _offset += set - time;
        switch (register & 0x1F)
        {
            case >= 8 and < 16:
                _latches[register & 7] = value;
                break;
            case 19:
                Array.Clear(_latches);
                break;
        }
    }

    private DateTime Time => Now() + _offset;

    private static byte Bcd(int value) => (byte)(((value / 10) << 4) | (value % 10));
}
