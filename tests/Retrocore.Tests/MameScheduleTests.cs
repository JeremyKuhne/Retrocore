// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Globalization;

namespace Retrocore.Tests;

/// <summary>
///  The schedule the TRS-80 oracles hand MAME's scripts, and the check of when its entries fired.
/// </summary>
[TestClass]
public class MameScheduleTests
{
    /// <summary>
    ///  A time keeps its fraction and a '.', whatever the culture, and is never written with an exponent.
    /// </summary>
    [TestMethod]
    public void SecondsArePlainDecimal()
    {
        CultureInfo culture = CultureInfo.CurrentCulture;
        try
        {
            // German writes 2,5; the Lua scripts read only digits and '.'.
            CultureInfo.CurrentCulture = new("de-DE");
            MameSchedule.Seconds(2.5).Should().Be("2.5");
            MameSchedule.Seconds(12.125).Should().Be("12.125");
            MameSchedule.Seconds(3).Should().Be("3");
            MameSchedule.Seconds(0).Should().Be("0");

            // The default format writes these as 1E-05 and 1E+15.
            MameSchedule.Seconds(0.00001).Should().Be("0.00001");
            MameSchedule.Seconds(1e15).Should().Be("1000000000000000");
        }
        finally
        {
            CultureInfo.CurrentCulture = culture;
        }
    }

    /// <summary>
    ///  A time the scripts can't wait for is refused.
    /// </summary>
    /// <param name="seconds">The time to format.</param>
    [TestMethod]
    [DataRow(-0.5)]
    [DataRow(double.NaN)]
    [DataRow(double.PositiveInfinity)]
    public void SecondsRefusesTimesThatAreNotSeconds(double seconds)
    {
        Action format = () => MameSchedule.Seconds(seconds);
        format.Should().Throw<ArgumentOutOfRangeException>();
    }

    /// <summary>
    ///  An entry is its time, '=' and its text with \r for ENTER; a whole schedule joins them with '|'.
    /// </summary>
    [TestMethod]
    public void ScriptJoinsEntries()
    {
        MameSchedule.Entry((2.5, "RUN\r")).Should().Be("2.5=RUN\\r");
        MameSchedule.Entry((4, "@:LINE7,F1,1")).Should().Be("4=@:LINE7,F1,1");
        MameSchedule.Script([(2.5, "\r"), (6.25, "LIST\r")]).Should().Be("2.5=\\r|6.25=LIST\\r");
        MameSchedule.Script([]).Should().BeEmpty();
    }

    /// <summary>
    ///  Text holding '|', which the scripts would split into two entries, is refused.
    /// </summary>
    [TestMethod]
    public void EntryRefusesTheSeparator()
    {
        Action format = () => MameSchedule.Entry((2, "PRINT 1|2\r"));
        format.Should().Throw<ArgumentException>();
    }

    /// <summary>
    ///  Entries that fired on their frame pass; one that fired late, early or not at all fails.
    /// </summary>
    [TestMethod]
    public void FiredOnTimeAllowsAFrame()
    {
        (double At, string Text)[] script = [(2.5, "\r"), (6, "RUN\r")];
        MameSchedule.ShouldHaveFiredOnTime(script, "2.500000=2.516667\n6.000000=6.000000\n");

        // The whole-seconds bug: 2.5 fired at the next second.
        Action late = () => MameSchedule.ShouldHaveFiredOnTime(script, "2.500000=3.000000\n6.000000=6.000000\n");
        late.Should().Throw<Exception>();

        Action early = () => MameSchedule.ShouldHaveFiredOnTime(script, "2.500000=2.000000\n6.000000=6.000000\n");
        early.Should().Throw<Exception>();

        Action missing = () => MameSchedule.ShouldHaveFiredOnTime(script, "2.500000=2.516667\n");
        missing.Should().Throw<Exception>();

        MameSchedule.ShouldHaveFiredOnTime([], "\n");
    }
}
