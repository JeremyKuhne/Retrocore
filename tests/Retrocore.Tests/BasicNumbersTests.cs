// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Basic;

namespace Retrocore.Tests;

/// <summary>
///  Checks writing a number as BASIC's floats from its text, which Retrocore Memory's find by value uses.
/// </summary>
[TestClass]
public sealed class BasicNumbersTests
{
    /// <summary>
    ///  Where a format's mantissa is narrower than a double's, the text and the double write the same bytes.
    /// </summary>
    /// <param name="text">The number.</param>
    [TestMethod]
    [DataRow("1000")]
    [DataRow("-.5")]
    [DataRow("0.1")]
    [DataRow("3.14159265")]
    [DataRow("1E38")]
    [DataRow("-2.5E-3")]
    public void TextMatchesDouble(string text)
    {
        double value = double.Parse(text, System.Globalization.CultureInfo.InvariantCulture);
        BasicNumbers.WriteFloat(text, 5, exponentFirst: true).Should().Equal(BasicNumbers.WriteFloat(value, 5, exponentFirst: true));
        BasicNumbers.WriteFloat(text, 4, exponentFirst: false).Should().Equal(BasicNumbers.WriteFloat(value, 4, exponentFirst: false));
    }

    /// <summary>
    ///  Level II's double keeps 56 bits, so 2^53 + 1, which a double rounds to 2^53, is written exactly.
    /// </summary>
    [TestMethod]
    public void DoubleKeepsEveryBit()
    {
        BasicNumbers.WriteFloat("9007199254740993", 8, exponentFirst: false).Should().Equal(0x04, 0, 0, 0, 0, 0, 0, 0x80 + 54);
        BasicNumbers.WriteFloat(9007199254740993, 8, exponentFirst: false).Should().Equal(0, 0, 0, 0, 0, 0, 0, 0x80 + 54);
        BasicNumbers.WriteFloat("1D0", 8, exponentFirst: false).Should().Equal(0, 0, 0, 0, 0, 0, 0, 0x81);
    }

    /// <summary>
    ///  Zero, and numbers too small to hold, are zero; one too large overflows; text that is no number is refused.
    /// </summary>
    [TestMethod]
    public void EdgesAreZeroOverflowOrRefused()
    {
        BasicNumbers.WriteFloat("0.000", 5, exponentFirst: true).Should().Equal(0, 0, 0, 0, 0);
        BasicNumbers.WriteFloat("1E-50", 5, exponentFirst: true).Should().Equal(0, 0, 0, 0, 0);
        BasicNumbers.WriteFloat("1E-999999", 5, exponentFirst: true).Should().Equal(0, 0, 0, 0, 0);
        FluentActions.Invoking(() => BasicNumbers.WriteFloat("1E40", 5, exponentFirst: true)).Should().Throw<OverflowException>();
        FluentActions.Invoking(() => BasicNumbers.WriteFloat("TEN", 5, exponentFirst: true)).Should().Throw<FormatException>();
        FluentActions.Invoking(() => BasicNumbers.WriteFloat(".", 5, exponentFirst: true)).Should().Throw<FormatException>();
    }
}
