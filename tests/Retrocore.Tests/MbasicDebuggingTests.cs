// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Basic;

namespace Retrocore.Tests;

/// <summary>
///  MBASIC's dialect as the debugger and editor use it: expressions with crunched constants, names with periods,
///  numbers crunched as FIN reads them, and lines scanned past their binary constants. None needs the MBASIC disk.
/// </summary>
[TestClass]
public sealed class MbasicDebuggingTests
{
    private static BasicDialect Mbasic => BasicDialect.Mbasic;

    /// <summary>
    ///  An expression's numbers, which the dialect crunches into binary constants, evaluate, and print as MBASIC
    ///  prints them: six digits for a single, sixteen for a double.
    /// </summary>
    /// <param name="expression">The expression.</param>
    /// <param name="printed">What MBASIC prints.</param>
    [TestMethod]
    [DataRow("1+2", "3")]
    [DataRow("300*2", "600")]
    [DataRow("40000", "40000")]
    [DataRow("12.5*2", "25")]
    [DataRow("1/3", ".333333")]
    [DataRow("2/3*10", "6.66667")]
    [DataRow("1#/3", ".3333333333333333")]
    [DataRow("1E3", "1000")]
    [DataRow("&H10+&O10", "24")]
    [DataRow("&HFFFF", "-1")]
    public void ConstantsEvaluate(string expression, string printed)
    {
        BasicEvaluator evaluator = new(Mbasic, DelegateBasicMemory.Of(new byte[0x10000]));
        evaluator.Format(evaluator.Evaluate(expression)).Should().Be(printed);
    }

    /// <summary>
    ///  Level II prints a single with six digits, as it did before MBASIC's dialect shared its formatting.
    /// </summary>
    [TestMethod]
    public void LevelTwoSinglesHaveSixDigits()
    {
        BasicDialect level2 = BasicDialect.FromName("level2") ?? throw new AssertFailedException("level2");
        BasicEvaluator evaluator = new(level2, DelegateBasicMemory.Of(new byte[0x10000]));
        evaluator.Format(evaluator.Evaluate("1/3")).Should().Be(".333333");
    }

    /// <summary>
    ///  A name with periods is one variable, in an expression or alone.
    /// </summary>
    [TestMethod]
    public void NamesHoldPeriods()
    {
        BasicEvaluator evaluator = new(Mbasic, DelegateBasicMemory.Of(new byte[0x10000]));
        evaluator.Format(evaluator.Evaluate("ITEM.COUNT")).Should().Be("0");
        evaluator.Format(evaluator.Evaluate("ITEM.COUNT+1")).Should().Be("1");
    }

    /// <summary>
    ///  Numbers crunch as FIN reads them, as MBASIC itself shows: an E before L or Q starts ELSE or EQV, not an
    ///  exponent, and a % constant rounds a half away from zero, overflowing past 32767.
    /// </summary>
    [TestMethod]
    public void NumbersCrunchAsFinReadsThem()
    {
        Convert.ToHexString(Mbasic.Tokenize("IF A THEN B=1 ELSE B=2")).Should().Be("8B204120CF2042F012203AA22042F013");
        Convert.ToHexString(Mbasic.Tokenize("X=1 EQV 2")).Should().Be("58F01220FA2013");
        Convert.ToHexString(Mbasic.Tokenize("X=1.6%")).Should().Be("58F013");
        Convert.ToHexString(Mbasic.Tokenize("X=2.5%")).Should().Be("58F014");
        Convert.ToHexString(Mbasic.Tokenize("X=1.4%")).Should().Be("58F012");
        Action overflow = () => Mbasic.Tokenize("X=32767.6%");
        overflow.Should().Throw<FormatException>();
    }

    /// <summary>
    ///  A function's number after $FF is not a token: SGN's is DATA's and FRE's is REM's, so a constant with a zero
    ///  byte after either still reads back from the program's image.
    /// </summary>
    [TestMethod]
    public void FunctionNumbersAreNotTokens()
    {
        BasicParseResult parsed = BasicProgram.Parse("10 X=SGN(1)+256\n20 Y=FRE(0)+512\n", Mbasic);
        BasicProgram program = parsed.Program ?? throw new AssertFailedException("the program parses");
        BasicProgram.FromImage(Mbasic, program.ToImage()).ToText().Should().Be(program.ToText());
    }

    /// <summary>
    ///  The scanner reads a constant whole: a payload byte that is a colon starts no statement, and a line number
    ///  after GOTO is a reference to its line.
    /// </summary>
    [TestMethod]
    public void ScannerReadsConstantsWhole()
    {
        BasicSource source = BasicSource.Analyze("10 PRINT 58:PRINT 1\n20 GOTO 10\n", Mbasic);
        source.NumberedLines[0].Statements.Should().HaveCount(2);
        source.Sites.Where(site => site.Kind == BasicSiteKind.LineReference).Select(site => site.Number)
            .Should().Equal(10);
    }

    /// <summary>
    ///  MBASIC's names have up to 40 significant characters and may hold periods, so COUNT and COST are two
    ///  variables, and COUNT.TOTAL% is one.
    /// </summary>
    [TestMethod]
    public void NamesHaveFortySignificantCharacters()
    {
        BasicSource source = BasicSource.Analyze("10 COUNT=1:COST=2:COUNT.TOTAL%=3\n", Mbasic);
        source.Sites.Where(site => site.Kind == BasicSiteKind.Variable).Select(site => site.Key)
            .Should().Equal("COUNT", "COST", "COUNT.TOTAL%");
    }

    /// <summary>
    ///  MBASIC takes GOTO only set apart from a name, so GOTOCOUNT=1 is an assignment, not a jump to a label.
    /// </summary>
    [TestMethod]
    public void GotoNeedsToBeSetApart()
    {
        BasicParseResult parsed = BasicProgram.Parse("10 IF A THEN GOTOCOUNT=1\n20 X.GOTO=2\n", Mbasic);
        parsed.Diagnostics.Should().BeEmpty();
        parsed.Program?.ToText().Should().Be("10 IF A THEN GOTOCOUNT=1\n20 X.GOTO=2\n");
    }
}
