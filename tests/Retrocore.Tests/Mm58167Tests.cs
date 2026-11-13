// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Apple3;

namespace Retrocore.Tests;

/// <summary>
///  The Apple III's clock chip: its counters, how they advance, and its reset commands.
/// </summary>
[TestClass]
public class Mm58167Tests
{
    private DateTime _now = new(2026, 11, 13, 14, 30, 45, 567);

    private Mm58167 Clock() => new() { Now = () => _now };

    /// <summary>
    ///  The counters start at the time source's time, in BCD.
    /// </summary>
    [TestMethod]
    public void CountersStartAtTheTimeSource()
    {
        Mm58167 clock = Clock();
        Enumerable.Range(0, 8).Select(register => clock.Read(register)).Should()
            .Equal(0x70, 0x56, 0x45, 0x30, 0x14, 0x06, 0x13, 0x11);
    }

    /// <summary>
    ///  Each counter is written alone: SOS's SET_TIME writes the day before the month, and a day the current month
    ///  lacks stays as written.
    /// </summary>
    [TestMethod]
    public void DayAndMonthAreWrittenApart()
    {
        Mm58167 clock = Clock();
        clock.Write(6, 0x31);
        clock.Read(7).Should().Be(0x11);
        clock.Write(7, 0x01);
        clock.Read(6).Should().Be(0x31);
        clock.Read(7).Should().Be(0x01);
    }

    /// <summary>
    ///  The counter-reset command resets the counters its bits name, as SOS's SET_TIME does with $FF before it sets
    ///  the time; the fraction of a second then counts from zero.
    /// </summary>
    [TestMethod]
    public void CounterResetClearsTheFraction()
    {
        Mm58167 clock = Clock();
        clock.Write(18, 0x03);
        clock.Read(0).Should().Be(0);
        clock.Read(1).Should().Be(0);
        clock.Read(2).Should().Be(0x45);

        clock.Write(18, 0xFF);
        Enumerable.Range(0, 8).Select(register => clock.Read(register)).Should()
            .Equal(0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x01, 0x01);

        _now = _now.AddMilliseconds(250);
        clock.Read(1).Should().Be(0x25);
    }

    /// <summary>
    ///  The fraction of a second is written through its two registers.
    /// </summary>
    [TestMethod]
    public void FractionIsWritable()
    {
        Mm58167 clock = Clock();
        clock.Write(1, 0x12);
        clock.Write(0, 0x30);
        clock.Read(1).Should().Be(0x12);
        clock.Read(0).Should().Be(0x30);
    }

    /// <summary>
    ///  The counters advance with the time source and carry: the last second of the year rolls to January 1, and the
    ///  day of the week with it.
    /// </summary>
    [TestMethod]
    public void CountersCarryIntoTheNextYear()
    {
        Mm58167 clock = Clock();
        clock.Write(18, 0xFF);
        clock.Write(2, 0x59);
        clock.Write(3, 0x59);
        clock.Write(4, 0x23);
        clock.Write(5, 0x07);
        clock.Write(6, 0x31);
        clock.Write(7, 0x12);

        _now = _now.AddMilliseconds(1500);
        Enumerable.Range(0, 8).Select(register => clock.Read(register)).Should()
            .Equal(0x00, 0x50, 0x00, 0x00, 0x00, 0x01, 0x01, 0x01);
    }

    /// <summary>
    ///  February always has 28 days: the chip knows no leap years.
    /// </summary>
    [TestMethod]
    public void FebruaryHasTwentyEightDays()
    {
        Mm58167 clock = Clock();
        clock.Write(7, 0x02);
        clock.Write(6, 0x28);
        _now = _now.AddDays(1);
        clock.Read(6).Should().Be(0x01);
        clock.Read(7).Should().Be(0x03);
    }

    /// <summary>
    ///  GO resets the fraction and the seconds, and the latches keep what is written until their reset.
    /// </summary>
    [TestMethod]
    public void GoAndLatchReset()
    {
        Mm58167 clock = Clock();
        clock.Write(21, 0);
        clock.Read(0).Should().Be(0);
        clock.Read(1).Should().Be(0);
        clock.Read(2).Should().Be(0);
        clock.Read(3).Should().Be(0x30);

        clock.Write(9, 0x86);
        clock.Read(9).Should().Be(0x86);
        clock.Write(19, 0xFF);
        clock.Read(9).Should().Be(0);
    }
}
