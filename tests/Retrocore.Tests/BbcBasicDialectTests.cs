// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Basic;
using Retrocore.Debug;
using Retrocore.Machines.Acorn;

namespace Retrocore.Tests;

/// <summary>
///  Verifies BBC BASIC II's dialect against the ROM: its keyword table, its tokeniser on lines typed into a Model B,
///  and its programs in memory.
/// </summary>
/// <remarks>
///  <para>
///   The machine runs on the ROMs built from the SDK's sources, so no dumps are needed.
///  </para>
/// </remarks>
[TestClass]
public sealed class BbcBasicDialectTests
{
    private static readonly string s_sources = Path.Join(AppContext.BaseDirectory, "Inputs", "Acorn");
    private static readonly Lazy<BbcRoms> s_roms = new(() => BbcSdkModules.Build(s_sources, filingSystem: false));

    // Lines that take each path through the tokeniser.
    private static readonly string[] s_lines =
    [
        "10 PRINT \"HELLO\";A%:GOTO 10",
        "20IF X>3 THEN 100 ELSE PRINT TIME",
        "30 TIME=0:P.PAGE:PR.\"A\"",
        "40 REM hello PRINT GOTO 10",
        "50 DATA 1,2,PRINT",
        "60 DEF PROCfoo(A$):LOCAL I%",
        "70 PROCPRINT:X=FNTIMER",
        "80 COUNTER=1:TIMER=2:ENDING=3",
        "90 ON X GOTO 10,20,30 ELSE 40",
        "100 *CAT",
        "110 A=&FFAB:B=1.5E3:C=.5",
        "120 printx=3:ENDPROC",
        "130 RESTORE 50:GOSUB 40000",
        "140 X=Y DIV 2 MOD 3 EOR 1 AND NOT 2",
        "150 PRINT ~X;TAB(3);LEFT$(A$,2)",
        "160 HIMEM=LOMEM+PAGE:PTR#C=TIME",
        "170 IF A THEN GOTO 10",
        "180 X=TRUE:Y=FALSE:Z=PI"
    ];

    /// <summary>
    ///  The dialect's keyword table is the ROM's: the same words, tokens and flags, in the order the ROM searches it.
    /// </summary>
    [TestMethod]
    public void KeywordTableMatchesTheRom()
    {
        AssemblyResult basic = BbcSdkModules.AssembleBasic(s_sources);
        ReadOnlySpan<byte> rom = basic.Sections[0].Bytes.Span;
        int at = (int)basic.Symbols["KEYWORD_TABLE"] - BbcSdkModules.PagedOrigin;
        List<(string, byte, int)> table = [];
        while (table.Count < BbcBasicDialect.Table.Count)
        {
            int start = at;
            while (rom[at] < 0x80) { at++; }
            table.Add((System.Text.Encoding.ASCII.GetString(rom[start..at]), rom[at], rom[at + 1]));
            at += 2;
        }

        table.Should().Equal(BbcBasicDialect.Table);
    }

    /// <summary>
    ///  Line numbers pack into three bytes as the ROM's comment gives line 10, and back.
    /// </summary>
    [TestMethod]
    public void LineNumbersPack()
    {
        BbcBasicDialect.PackLineNumber(10).Should().Be((0x54, 0x4A, 0x40));
        for (int number = 0; number <= 32767; number += 7)
        {
            (byte first, byte second, byte third) = BbcBasicDialect.PackLineNumber(number);
            BbcBasicDialect.UnpackLineNumber(first, second, third).Should().Be(number);
            ((int)first).Should().BeInRange(0x40, 0x7F);
        }
    }

    /// <summary>
    ///  Each line tokenises to the bytes BASIC stores when it is typed, and lists back as typed.
    /// </summary>
    [TestMethod]
    public void TypedLinesTokeniseAsTheRomDoes()
    {
        BbcMachine machine = Boot();
        BbcMachineTests.Type(machine, string.Join("\r", s_lines) + "\r");
        BasicProgram stored = BasicProgram.Read(BasicDialect.BbcBasic, Memory(machine));
        stored.Lines.Should().HaveCount(s_lines.Length);
        for (int index = 0; index < s_lines.Length; index++)
        {
            string text = BasicDialect.BbcBasic.SplitLineNumber(s_lines[index], out int number);
            BasicLine line = stored.Lines[index];
            line.Number.Should().Be(number);
            Convert.ToHexString(BasicDialect.BbcBasic.Tokenize(text)).Should().Be(
                Convert.ToHexString(line.Tokens.Span),
                $"line {number} should tokenise as the ROM stored it");

            // Abbreviations list in full, as BASIC's LIST gives them.
            string listed = s_lines[index].Replace("P.PAGE", "PRINTPAGE", StringComparison.Ordinal)
                .Replace("PR.\"", "PRINT\"", StringComparison.Ordinal);

            BasicDialect.BbcBasic.FormatLine(line).Should().Be(listed);
        }
    }

    /// <summary>
    ///  A program written into memory runs, and BASIC's own LIST shows it as the dialect gives it.
    /// </summary>
    [TestMethod]
    public void WrittenProgramRuns()
    {
        BbcMachine machine = Boot();
        BasicProgram program = BasicProgram.Parse(
            "10 FOR I%=1 TO 3:PRINT I%*7;:NEXT\n20 PRINT '\"DONE\"\n",
            BasicDialect.BbcBasic).Program ?? throw new AssertFailedException("The program did not parse.");

        program.Write(Memory(machine));
        BbcMachineTests.Type(machine, "LIST\rRUN\r");
        string screen = string.Join("\n", machine.ReadTextScreen().Select(line => line.TrimEnd()));
        screen.Should().Contain("   10 FOR I%=1 TO 3:PRINT I%*7;:NEXT");
        screen.Should().Contain("   20 PRINT '\"DONE\"");
        screen.Should().Contain("         7        14        21");
        screen.Should().Contain("DONE");
    }

    /// <summary>
    ///  A SAVEd program's bytes, from PAGE to TOP, read as the program, and the program writes them back.
    /// </summary>
    [TestMethod]
    public void ImageRoundTrips()
    {
        BbcMachine machine = Boot();
        BbcMachineTests.Type(machine, string.Join("\r", s_lines) + "\r");
        int page = machine.Bus.Peek(0x18) << 8;
        int top = machine.Bus.Peek(0x12) | (machine.Bus.Peek(0x13) << 8);
        byte[] image = machine.Bus.Ram[page..top].ToArray();
        BasicProgram program = BasicProgram.FromImage(BasicDialect.BbcBasic, image);
        program.ToImage().Should().Equal(image);
        (BasicProgram.Parse(program.ToText(), BasicDialect.BbcBasic).Program?.ToImage()).Should().Equal(image);
    }

    /// <summary>
    ///  Watches take BBC BASIC's grammar: its integer operators and their precedence, factor functions without
    ///  brackets, constants, pseudo-variables, hexadecimal and its own LOG, STRING$ and INSTR.
    /// </summary>
    /// <param name="expression">The expression.</param>
    /// <param name="expected">The number it gives.</param>
    [TestMethod]
    [DataRow("7 DIV 2", 3.0)]
    [DataRow("-7 MOD 2", -1.0)]
    [DataRow("1 EOR 3", 2.0)]
    [DataRow("NOT 1+1", -1.0)]
    [DataRow("2^3^2", 64.0)]
    [DataRow("-2^2", 4.0)]
    [DataRow("TRUE", -1.0)]
    [DataRow("FALSE OR 6 AND 3", 2.0)]
    [DataRow("LEN \"abc\"", 3.0)]
    [DataRow("ABS -5", 5.0)]
    [DataRow("LOG(100)", 2.0)]
    [DataRow("LN 1", 0.0)]
    [DataRow("INSTR(N$,\"BC\",3)", 5.0)]
    [DataRow("&FF", 255.0)]
    [DataRow("&FFFFFFFF", -1.0)]
    [DataRow("1E-3*1E+3", 1.0)]
    [DataRow("_count+1", 2.0)]
    [DataRow("X% DIV 2", 3.0)]
    [DataRow("7/2", 3.5)]
    [DataRow("\"A\"<\"B\"", -1.0)]
    [DataRow("PAGE", 0x0E00 * 1.0)]           // no filing system ROM
    [DataRow("TOP-PAGE", 2.0)]                 // TOP is TO then P; an empty program is its end marker
    [DataRow("&7FFFFFFF+1", -2147483648.0)]    // integers wrap at 32 bits
    [DataRow("&7FFFFFFF+1.0", 2147483648.0)]   // a real operand makes the sum real
    [DataRow("LEN LEFT$(\"ABC\",256)", 0.0)]   // the low byte of the count
    [DataRow("LEN STRING$(256,\"X\")", 0.0)]
    public void WatchesTakeBbcGrammar(string expression, double expected)
    {
        BasicEvaluator evaluator = Variables();
        evaluator.Evaluate(expression).Value.Number.Should().BeApproximately(expected, 1e-9, expression);
    }

    /// <summary>
    ///  STRING$ repeats its whole string, and what needs BASIC running is refused.
    /// </summary>
    [TestMethod]
    public void WatchStringsAndRefusals()
    {
        BasicEvaluator evaluator = Variables();
        evaluator.Format(evaluator.Evaluate("STRING$(3,\"AB\")")).Should().Be("\"ABABAB\"");
        evaluator.Format(evaluator.Evaluate("STR$~255")).Should().Be("\"FF\"");
        evaluator.Evaluate("PI").Value.Number.Should().BeApproximately(Math.PI, 1e-9);
        Action random = () => evaluator.Evaluate("RND(6)");
        random.Should().Throw<FormatException>().WithMessage("RND* without running BASIC.");

        // STR$ and the watch's own text use BASIC's general format.
        evaluator.Format(evaluator.Evaluate("STR$1234567890")).Should().Be("\"1234567890\"");
        evaluator.Format(evaluator.Evaluate("STR$0.5")).Should().Be("\"0.5\"");
        evaluator.Format(evaluator.Evaluate("STR$0.01")).Should().Be("\"1E-2\"");
        evaluator.Format(evaluator.Evaluate("1.5E10")).Should().Be("1.5E10");
        evaluator.Format(evaluator.Evaluate("-12.25")).Should().Be("-12.25");

        Action outside = () => evaluator.Evaluate("ASN 2");
        outside.Should().Throw<FormatException>().WithMessage("-ve root.");
        Action missing = () => evaluator.Evaluate("missing=0");
        missing.Should().Throw<FormatException>().WithMessage("No such variable*");
    }

    /// <summary>
    ///  A hexadecimal number is a constant, not a name: renaming BEEF leaves &amp;BEEF alone.
    /// </summary>
    [TestMethod]
    public void HexNumbersAreNotNames()
    {
        BasicSource source = BasicSource.Analyze("10 BEEF=1:PRINT &BEEF\n", BasicDialect.BbcBasic);
        source.Sites.Where(site => site.Kind == BasicSiteKind.Variable).Select(site => site.Key).Should().Equal("BEEF");
    }

    /// <summary>
    ///  GOTO takes an expression, so a name after it is a label only when one is defined.
    /// </summary>
    [TestMethod]
    public void GotoTakesAnExpression()
    {
        BasicParseResult parsed = BasicProgram.Parse("10 target%=100:GOTO target%\n100 END\n", BasicDialect.BbcBasic);
        parsed.Program.Should().NotBeNull(string.Join('\n', parsed.Diagnostics.Select(diagnostic => diagnostic.Message)));
    }

    /// <summary>
    ///  PROCfoo and FNfoo are different routines.
    /// </summary>
    [TestMethod]
    public void ProcAndFnAreDifferentRoutines()
    {
        const string Program = "10 PROCfoo:X=FNfoo\n20 END\n30 DEF PROCfoo:ENDPROC\n40 DEF FNfoo=1\n";
        BasicSource source = BasicSource.Analyze(Program, BasicDialect.BbcBasic);
        BasicSite[] routines = [.. source.Sites.Where(site => site.Kind == BasicSiteKind.Function)];
        routines.Select(site => site.Key).Distinct().Should().Equal("PROCfoo", "FNfoo");
        routines.Select(site => site.Name).Distinct().Should().Equal("foo");
        source.References(routines[0]).Should().HaveCount(2);
    }

    /// <summary>
    ///  A variable needs a name before its one suffix, and a long name reads back whole.
    /// </summary>
    [TestMethod]
    public void VariableNamesAreChecked()
    {
        BbcMachine machine = Boot();
        BasicVariables variables = new(BasicDialect.BbcBasic, Memory(machine));
        Action suffixOnly = () => variables.Create("$");
        suffixOnly.Should().Throw<ArgumentException>();
        Action twoSuffixes = () => variables.Create("A%%");
        twoSuffixes.Should().Throw<ArgumentException>();

        string name = "a" + new string('b', 70);
        BasicVariable made = variables.Create(name);
        variables.Find(name).Should().Be(made);
    }

    // A Model B at the prompt with X%=7, _count=1 and N$="ABCABC", and an evaluator on it.
    private static BasicEvaluator Variables()
    {
        BbcMachine machine = Boot();
        BbcMachineTests.Type(machine, "X%=7:_count=1:N$=\"ABCABC\"\r");
        BbcMachineTests.RunToPrompt(machine);
        return new BasicEvaluator(BasicDialect.BbcBasic, Memory(machine));
    }

    // A Model B on the SDK's MOS and BASIC, at BASIC's prompt.
    private static BbcMachine Boot()
    {
        BbcMachine machine = new(s_roms.Value, BbcModel.ModelB, diskInterface: false);
        BbcMachineTests.RunToPrompt(machine);
        return machine;
    }

    private static DelegateBasicMemory Memory(BbcMachine machine) =>
        new(address => machine.Bus.Peek((ushort)address), (address, value) => machine.Bus.Write((ushort)address, value));
}
