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

        // A BBC line holds a zero byte, as its length ends it: 10 REM, a zero, round trips through text as {$00}.
        byte[] zero = [0x0D, 0x00, 0x0A, 0x06, 0xF4, 0x00, 0x0D, 0xFF];
        BasicProgram withZero = BasicProgram.FromImage(BasicDialect.BbcBasic, zero);
        withZero.ToText().Should().Contain("{$00}");
        (BasicProgram.Parse(withZero.ToText(), BasicDialect.BbcBasic).Program?.ToImage()).Should().Equal(zero);
        Action zeroElsewhere = () => BasicDialect.AppleSoft.Tokenize("REM {$00}");
        zeroElsewhere.Should().Throw<FormatException>("a zero ends an AppleSoft line");
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
    [DataRow("&7FFFFFFF*1+1", 2147483648.0)]  // an operand past 16 bits makes * real
    [DataRow("(+&7FFFFFFF)+1", -2147483648.0)] // unary + keeps an integer
    [DataRow("ABS &80000000", -2147483648.0)]  // ABS of an integer wraps
    [DataRow("SGN(1)+&7FFFFFFF", -2147483648.0)]
    [DataRow("VAL(\"2147483647\")+1", -2147483648.0)]
    [DataRow("&7FFFFFFF+INSTR(\"A\",\"B\",3)+1", -2147483648.0)]
    [DataRow("VAL \"+ 12\"", 12.0)]
    [DataRow("VAL \"1.2.3\"", 1.2)]
    [DataRow("EXP -100", 0.0)]
    [DataRow("&7FFFFFFF+1E0", -2147483648.0)]  // a zero exponent keeps an integer
    [DataRow("VAL(\"1E0\")+&7FFFFFFF", -2147483648.0)]
    [DataRow("VAL(\"-2147483648\")-1", -2147483649.0)] // the magnitude is too big for an integer
    [DataRow("1E-40", 0.0)]                    // below BASIC's smallest real
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
        // STR$ gives ten digits, as the ROM does: 0.01 in a 32-bit mantissa is just short of it.
        evaluator.Format(evaluator.Evaluate("STR$0.01")).Should().Be("\"9.999999998E-3\"");
        evaluator.Format(evaluator.Evaluate("STR$(1/3)")).Should().Be("\"0.3333333334\"");
        evaluator.Format(evaluator.Evaluate("1.5E10")).Should().Be("1.5E10");
        evaluator.Format(evaluator.Evaluate("-12.25")).Should().Be("-12.25");

        Action outside = () => evaluator.Evaluate("ASN 2");
        outside.Should().Throw<FormatException>().WithMessage("-ve root.");
        (string, string)[] ranges = [("(-1)^0.5", "Log range."), ("2^1024", "Exp range."), ("EXP 100", "Exp range."), ("1E39", "Too big.")];
        foreach ((string expression, string error) in ranges)
        {
            Action range = () => evaluator.Evaluate(expression);
            range.Should().Throw<FormatException>(expression).WithMessage(error);
        }

        Action missing = () => evaluator.Evaluate("missing=0");
        missing.Should().Throw<FormatException>().WithMessage("No such variable*");
    }

    /// <summary>
    ///  A * command where a statement starts is the MOS's to the end of the line, as OSCLI takes it: its colons start
    ///  no statements, after a colon, THEN or ERROR alike, where a * in an expression multiplies.
    /// </summary>
    [TestMethod]
    public void StarCommandsTakeTheRestOfTheLine()
    {
        foreach ((string line, int count) in (ReadOnlySpan<(string, int)>)[
            ("10 X=1:*KEY 0 LIST:RUN|M", 2), ("10 IF X THEN *FX 15:PRINT", 1), ("10 ON ERROR *KEY 1 A:B", 1),
            ("10 *CAT:*DRIVE 1", 1), ("10 A=2*3:B=1", 2), ("10 PRINT \"*\":C=1", 2), ("10 GOTO 20:*FX 0:X", 2)])
        {
            BasicSource source = BasicSource.Analyze(line + "\n", BasicDialect.BbcBasic);
            source.NumberedLines[0].Statements.Should().HaveCount(count, line);
        }
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
    ///  Between [ and ], over several lines, the assembler's mnemonics, registers and comments are not variables, while
    ///  its labels and the names in its operands are: renaming loop renames .loop and BNE loop, and LDA is no variable.
    ///  Nothing after an implied instruction is read, and LDX, LDY, STX and STY take their register in either case.
    /// </summary>
    [TestMethod]
    public void AssemblerMnemonicsAreNotVariables()
    {
        const string Program = """
            10 DIM code% 100:dest=&70:count=0:mask=1:start=0
            20 FOR pass=0 TO 2 STEP 2:P%=code%
            30 [OPT pass
            40 .loop LDA dest,X:STA &71,Y \ copy X: INX
            50 lda (dest),Y:ASL A:ROR count:ORA #1:AND mask:EOR #&FF:JMP (dest)
            60 EQUB 1:EQUW start:BNE loop ; back to Y
            65 . done RTS back to caller:LDX dest,y:STY count,x then more:CLC
            70 ]:NEXT:X=1
            80 PRINT X

            """;

        BasicSource source = BasicSource.Analyze(Program, BasicDialect.BbcBasic);
        string[] names = [.. source.Sites.Where(site => site.Kind == BasicSiteKind.Variable).Select(site => $"{site.Text}@{site.Line}")];
        names.Should().Equal(
            "code%@0", "dest@0", "count@0", "mask@0", "start@0",
            "pass@1", "P%@1", "code%@1",
            "pass@2",
            "loop@3", "dest@3",
            "dest@4", "count@4", "mask@4", "dest@4",
            "start@5", "loop@5",
            "done@6", "dest@6", "count@6",
            "X@7",
            "X@8");

        // The program assembles, and BASIC makes exactly those variables, the resident P% aside: none for LDA or X's
        // register, though it makes the variable X later.
        BbcMachine machine = Boot();
        BbcMachineTests.Type(machine, Program.Replace("\n", "\r", StringComparison.Ordinal) + "RUN\r");
        machine.Run(TimeSpan.FromSeconds(2));
        string screen = string.Join("\n", machine.ReadTextScreen());
        screen.Should().NotContainAny(["rror", "No such", "Mistake", "Index", "Byte", "range"]);
        static bool Heap(string name) => !(name.Length == 2 && name[1] == '%');
        BasicVariables variables = new(BasicDialect.BbcBasic, Memory(machine));
        variables.Simple().Select(variable => variable.Name).Where(Heap).Should()
            .BeEquivalentTo(names.Select(name => name[..name.IndexOf('@')]).Where(Heap).Distinct());
    }

    /// <summary>
    ///  Another BASIC's word is an ordinary BBC variable, as names are kept whole, so HOME=1 and PRINT HOME are fine;
    ///  only as a statement of its own, where BASIC stops with Mistake, is it warned of.
    /// </summary>
    [TestMethod]
    public void ForeignWordsWarnOnlyAsStatements()
    {
        // Each statement, its foreign word, and whether BASIC II stops on it with Mistake: a ?, ! or ( must follow the
        // name straight away, so after a space only = makes an assignment.
        (string Statement, string Word, bool Mistake)[] statements =
        [
            ("HOME=&900", "HOME", false), ("PRINT HOME", "HOME", false), ("SET(1)=2", "SET", false),
            ("HOME?0=1", "HOME", false), ("HOME!0=1", "HOME", false), ("HOME =&900", "HOME", false),
            ("HOME", "HOME", true), ("IF 1 THEN HOME", "HOME", true), ("HOME ?0=1", "HOME", true),
            ("HOME !0=1", "HOME", true), ("SET (1)=2", "SET", true)
        ];

        string program = "10 DIM SET(1)\n" + string.Concat(statements.Select((entry, index) => $"{index + 2}0 {entry.Statement}\n"));
        BasicSource source = BasicSource.Analyze(program, BasicDialect.BbcBasic);
        source.Diagnostics.Where(diagnostic => diagnostic.Severity == BasicSeverity.Warning).Select(diagnostic => $"{diagnostic.Line}: {diagnostic.Message}")
            .Should().Equal(statements.Select((entry, index) => (entry, line: index + 1)).Where(pair => pair.entry.Mistake).Select(pair =>
                $"{pair.line}: BBC BASIC has no {pair.entry.Word} statement: it reads {pair.entry.Word} as a variable to assign, and stops with Mistake."));

        BbcMachine machine = Boot();
        BbcMachineTests.Type(machine, "DIM SET(1):HOME=&900\r");
        BbcMachineTests.RunToPrompt(machine);
        foreach ((string statement, _, bool mistake) in statements)
        {
            BbcMachineTests.Type(machine, $"CLS:{statement}\r");
            string screen = string.Join("\n", BbcMachineTests.RunToPrompt(machine));
            screen.Contains("Mistake", StringComparison.Ordinal).Should().Be(mistake, statement);
        }

        // AppleSoft still warns of a word it lacks wherever it is, as it reads the name by its first two letters.
        BasicSource appleSoft = BasicSource.Analyze("10 X=ELSE\n", BasicDialect.AppleSoft);
        appleSoft.Diagnostics.Select(diagnostic => diagnostic.Message).Should().Contain("AppleSoft has no ELSE; it reads it as the variable EL.");
    }

    /// <summary>
    ///  The assembler's mnemonics are the table in Assembler.asm, in either case, and anything else where an
    ///  instruction starts is warned of, as BASIC II stops on it with Syntax error: an unknown mnemonic, too few letters,
    ///  EQU without a capital B, W, D or S, OR without A, or another keyword's token. The first three letters are the
    ///  mnemonic whatever follows them, so LDAdest is LDA dest.
    /// </summary>
    [TestMethod]
    public void AssemblerWarnsOfUnknownMnemonics()
    {
        // The table's entries are lines such as: MNEMONIC part, "BRK", $00
        const string Entry = "MNEMONIC part, \"";
        string[] mnemonics =
        [
            .. File.ReadLines(Path.Join(AppContext.BaseDirectory, "Inputs", "Acorn", "Basic", "Assembler.asm"))
                .Select(line => line.Trim())
                .Where(line => line.StartsWith(Entry, StringComparison.Ordinal))
                .Select(line => line.Substring(Entry.Length, 3))
        ];

        mnemonics.Should().HaveCount(58);
        BasicLineScanner.BbcMnemonics.Should().Equal(mnemonics);

        string[] valid =
        [
            .. mnemonics.Where(mnemonic => mnemonic != "EQU").Select(mnemonic => $"{mnemonic} &70"),
            .. mnemonics.Where(mnemonic => mnemonic != "EQU").Select(mnemonic => $"{mnemonic.ToLowerInvariant()} &70"),
            "EQUB &70", "EQUW &70", "EQUD &70", "EQUS \"A\"", "AND #1", "EOR #1", "ORA #1", "LDAdest", "RTSx", ".loop NOP"
        ];

        (string Statement, string Word)[] invalid =
        [
            ("LDZ #1", "LDZ"), ("sat &70", "sat"), ("LD", "LD"), ("EQUX 1", "EQUX"), ("EQUb 1", "EQUb"), ("EQU 1", "EQU"),
            ("PRINT", "PRINT"), ("OR #1", "OR")
        ];

        string[] lines = ["10 [OPT 0", .. valid.Concat(invalid.Select(entry => entry.Statement)).Select((statement, index) => $"{index + 2}0 {statement}"), "9990 ]"];
        BasicSource source = BasicSource.Analyze(string.Join("\n", lines) + "\n", BasicDialect.BbcBasic);
        source.Diagnostics.Where(diagnostic => diagnostic.Severity == BasicSeverity.Warning).Select(diagnostic => $"{diagnostic.Line}: {diagnostic.Message}")
            .Should().Equal(invalid.Select((entry, index) =>
                $"{valid.Length + index + 1}: BBC BASIC's assembler has no {entry.Word}: it stops with Syntax error."));

        // BASIC II stops on each with Syntax error, and assembles the forms that look odd but are valid.
        BbcMachine machine = Boot();
        BbcMachineTests.Type(machine, "dest=&70:x=0\r");
        BbcMachineTests.RunToPrompt(machine);
        foreach (string statement in invalid.Select(entry => entry.Statement).Append("LDAdest:RTSx:lda #1:EQUB 1"))
        {
            BbcMachineTests.Type(machine, $"CLS:P%=&3000:[OPT 2:{statement}\r");
            string screen = string.Join("\n", BbcMachineTests.RunToPrompt(machine));
            screen.Contains("Syntax error", StringComparison.Ordinal).Should().Be(!statement.StartsWith("LDAdest", StringComparison.Ordinal), statement);
        }
    }

    /// <summary>
    ///  An array's bracket must follow its name straight away: FIND_VARIABLE reads the next character, so A (1) is the
    ///  variable A and then (1), and only A(1) is the array.
    /// </summary>
    [TestMethod]
    public void ArrayBracketFollowsTheName()
    {
        BasicSource source = BasicSource.Analyze("10 PRINT A (1),B(1)\n", BasicDialect.BbcBasic);
        source.Sites.Where(site => site.Kind == BasicSiteKind.Variable).Select(site => site.Key).Should().Equal("A", "B(");
    }

    /// <summary>
    ///  @% is a variable, and a * command's text is the MOS's, not BASIC's: renaming FOO leaves *LOAD FOO alone, while
    ///  * in an expression is still multiplication.
    /// </summary>
    [TestMethod]
    public void StarCommandsAndAtPercent()
    {
        const string Program = "10 @%=0:FOO=1:X=FOO*2\n20 *LOAD FOO 2000\n30 IF FOO THEN *CAT\n";
        BasicSource source = BasicSource.Analyze(Program, BasicDialect.BbcBasic);
        string[] names = [.. source.Sites.Where(site => site.Kind == BasicSiteKind.Variable).Select(site => $"{site.Key}@{site.Line}")];
        names.Should().Equal("@%@0", "FOO@0", "X@0", "FOO@0", "FOO@2");  // by source line: none in line 20's *LOAD
    }

    /// <summary>
    ///  Labels in BBC BASIC: a name in small letters such as reminder is no REM, and a * command's text keeps its
    ///  words; TOP's P is no variable.
    /// </summary>
    [TestMethod]
    public void LabelsAndTopReadAsBbcBasic()
    {
        const string Source = "REM retrocore bbcbasic\n    reminder=0:SCOREMARK=1:GOTO done\n    *RENAME GOTO done\n    DATA text:GOTO done\ndone:\n    PRINT TOP\n";
        BasicParseResult parsed = BasicProgram.Parse(Source, BasicDialect.BbcBasic);
        parsed.Diagnostics.Should().BeEmpty();
        string text = parsed.Program?.ToText() ?? "";
        text.Should().Contain("reminder=0:SCOREMARK=1:GOTO 40").And.Contain("*RENAME GOTO done")
            .And.Contain("DATA text:GOTO done");

        BasicSource source = BasicSource.Analyze("10 P=1:PRINT TOP\n", BasicDialect.BbcBasic);
        source.Sites.Where(site => site.Kind == BasicSiteKind.Variable).Should().ContainSingle();

        // After an operand, TO is FOR's, and P% a variable.
        BasicSource loop = BasicSource.Analyze("10 P%=3:FOR I%=1 TOP%:NEXT\n", BasicDialect.BbcBasic);
        loop.Sites.Where(site => site.Kind == BasicSiteKind.Variable).Select(site => site.Text)
            .Should().Equal("P%", "I%", "P%");

        // ERROR starts a statement as THEN does, so the * after it is a command: FOO in it is no variable.
        BasicSource key = BasicSource.Analyze("10 ON ERROR *KEY 1 FOO\n", BasicDialect.BbcBasic);
        key.Sites.Should().NotContain(site => site.Kind == BasicSiteKind.Variable);
        BasicSource repeat = BasicSource.Analyze("10 REPEAT *KEY 1 FOO\n", BasicDialect.BbcBasic);
        repeat.Sites.Should().NotContain(site => site.Kind == BasicSiteKind.Variable, "REPEAT leaves a statement starting");

        // Jumps are where the tokeniser finds them: run together, abbreviated, and never in a * command.
        Dictionary<string, BasicLabel> labels = new() { ["done"] = new("done", 1, 0, 4, 80) };
        foreach (string jump in (string[])["IF1THEN done", "IF X=1THEN done", "G.done", "GOS.done", "IFX PRINT EL.done", "IF X THEN 10 EL. done"])
        {
            BasicProgram.LabelReferences(BasicDialect.BbcBasic, jump, labels).Should().ContainSingle(jump)
                .Which.Name.Should().Be("done");
        }

        BasicProgram.LabelReferences(BasicDialect.BbcBasic, "ON ERROR *KEY 1 GOTO done", labels).Should().BeEmpty();
        BasicProgram.LabelReferences(BasicDialect.BbcBasic, "GOTO done%", labels).Should().BeEmpty("done% is another name");

        // A label after THEN is alone before ELSE however it is abbreviated, and before REM; RUN takes no line.
        const string Else = "REM retrocore bbcbasic\n    IF X THEN done EL. other\n    IF X THEN done ELS.other\n    IF X THEN done REM why\ndone:\n    PRINT 1\nother:\n    PRINT 2\n";
        string elsed = BasicProgram.Parse(Else, BasicDialect.BbcBasic).Program?.ToText() ?? "";
        string[] ifs = [.. elsed.Split('\n').Where(line => line.Contains("IF X", StringComparison.Ordinal))];
        ifs.Should().HaveCount(3);
        foreach (string line in ifs) { line.Should().Contain("THEN 40").And.NotContain("done"); }
        BasicProgram.LabelReferences(BasicDialect.BbcBasic, "RUN done", labels).Should().BeEmpty("BASIC II's RUN takes no line");

        // A line the tokeniser makes a statement of is no label, though it is a name and a colon: PRINTX: is PRINT X.
        BasicParseResult statement = BasicProgram.Parse("REM retrocore bbcbasic\nX=1\nPRINTX:\nPROCinit:\nEND\nDEF PROCinit:ENDPROC\n", BasicDialect.BbcBasic);
        statement.Program?.ToText().Should().Contain("PRINTX:").And.Contain("PROCinit:");

        // TRACE takes a line, its limit, which the tokeniser keeps as a line number: a label there is the line.
        BasicProgram.LabelReferences(BasicDialect.BbcBasic, "TRACE done", labels).Should().ContainSingle()
            .Which.Name.Should().Be("done");

        // A byte the tokeniser copies as it is, after REM, DATA or a * command, is no GOTO even when it is &E5.
        foreach (string literal in (string[])["DATA {$E5} done", "REM {$E5} done", "REPEAT *KEY 1 {$E5} done"])
        {
            BasicProgram.LabelReferences(BasicDialect.BbcBasic, literal, labels).Should().BeEmpty(literal);
        }

        // FALSE is a whole value, so the TO after it is FOR's, and P% a variable.
        BasicSource falseLoop = BasicSource.Analyze("10 P%=3:FOR I%=FALSE TOP%:NEXT\n", BasicDialect.BbcBasic);
        falseLoop.Sites.Where(site => site.Kind == BasicSiteKind.Variable).Select(site => site.Text)
            .Should().Equal("P%", "I%", "P%");
    }

    /// <summary>
    ///  FN calls are checked as BASIC checks them, and reals keep BASIC II's 32-bit mantissa.
    /// </summary>
    [TestMethod]
    public void FunctionsAndRealPrecision()
    {
        BbcMachine machine = Boot();
        BbcMachineTests.Type(machine, "P=PI:H=2147483649+0.5\r");
        BbcMachineTests.RunToPrompt(machine);
        (string Parameter, string Body)? Define(string name) => name switch
        {
            "f" => ("x", "x+&7FFFFFFF"),
            "g" => ("", "42"),
            "a@b" => ("", "7"),
            _ => null
        };

        BasicEvaluator evaluator = new(BasicDialect.BbcBasic, Memory(machine), Define);
        evaluator.Evaluate("FNf(1)").Value.Number.Should().Be(2147483648.0, "a real parameter makes the sum real");
        evaluator.Evaluate("FNg").Value.Number.Should().Be(42);
        Action missing = () => evaluator.Evaluate("FNf");
        missing.Should().Throw<FormatException>().WithMessage("Arguments.");
        Action extra = () => evaluator.Evaluate("FNg(1)");
        extra.Should().Throw<FormatException>().WithMessage("Arguments.");
        evaluator.Evaluate("1E10+1-1E10").Value.Number.Should().Be(0, "1E10+1 rounds to 32 bits");

        // PI is the ROM's packed constant, and an exact half keeps an odd mantissa, both as the ROM stored them.
        evaluator.Evaluate("PI=P").Value.Number.Should().Be(-1);
        evaluator.Evaluate("2147483649+0.5").Value.Number.Should().Be(2147483649.0);
        evaluator.Evaluate("2147483649+0.5=H").Value.Number.Should().Be(-1);

        // A real that rounds up to 2^127 is too big after rounding, as the ROM finds it.
        BbcMachineTests.Type(machine, "PRINT 1.7014118345E38\r");
        BbcMachineTests.RunToPrompt(machine);
        machine.ReadTextScreen().Should().Contain(line => line.Contains("Too big"));
        Action rounded = () => evaluator.Evaluate("1.7014118345E38");
        rounded.Should().Throw<FormatException>().WithMessage("Too big.");

        // SIN, COS and TAN refuse an angle of 2^23 or more, and an exponent takes two digits at most: VAL stops
        // before a third, and a watch finds it left over. Each as the ROM has it.
        BbcMachineTests.Type(machine, "CLS:PRINT VAL(\"1E001\");\"|\";1E01\r");
        BbcMachineTests.RunToPrompt(machine);
        machine.ReadTextScreen().Should().Contain(line => line.Replace(" ", "") == "1|10");
        evaluator.Evaluate("VAL(\"1E001\")").Value.Number.Should().Be(1);
        Action third = () => evaluator.Evaluate("1E001");
        third.Should().Throw<FormatException>();

        // An E with no digits is an exponent of 0, its sign and all.
        BbcMachineTests.Type(machine, "CLS:PRINT 1E;\"|\";1E+;\"|\";1E-;\"|\";2E+1\r");
        BbcMachineTests.RunToPrompt(machine);
        machine.ReadTextScreen().Should().Contain(line => line.Replace(" ", "") == "1|1|1|20");
        foreach ((string literal, double value) in (ReadOnlySpan<(string, double)>)[("1E", 1), ("1E+", 1), ("1E-", 1), ("2E+1", 20)])
        {
            evaluator.Evaluate(literal).Value.Number.Should().Be(value, literal);
        }

        foreach (string trig in (string[])["SIN 8388608", "COS -8388608", "TAN 1E9"])
        {
            BbcMachineTests.Type(machine, $"CLS:PRINT {trig}\r");
            BbcMachineTests.RunToPrompt(machine);
            machine.ReadTextScreen().Should().Contain(line => line.Contains("Accuracy lost"), trig);
            Action lost = () => evaluator.Evaluate(trig);
            lost.Should().Throw<FormatException>().WithMessage("Accuracy lost.", trig);
        }

        evaluator.Evaluate("SIN 8388607").Value.Number.Should().NotBe(0);

        // ^ splits off the whole power nearest its right side, and takes the rest, or all of a power of 64 or more, by
        // LN and EXP, so 0^0.5 and (-1)^64 are Log range and 2^1024 Exp range, as in the ROM, while whole powers below
        // 64 of anything are not.
        foreach ((string power, string error) in (ReadOnlySpan<(string, string)>)[("0^0.5", "Log range"), ("(-1)^64", "Log range"), ("2^1024", "Exp range")])
        {
            BbcMachineTests.Type(machine, $"CLS:PRINT {power}\r");
            BbcMachineTests.RunToPrompt(machine);
            machine.ReadTextScreen().Should().Contain(line => line.Contains(error), power);
            Action raise = () => evaluator.Evaluate(power);
            raise.Should().Throw<FormatException>().WithMessage(error + ".", power);
        }

        BbcMachineTests.Type(machine, "A=2^0.5:B=(-2)^3:C=2^-3:D=3^70:E=0^2\r");
        BbcMachineTests.RunToPrompt(machine);
        foreach (string same in (string[])["(-2)^3=B", "2^-3=C", "0^2=E"])
        {
            evaluator.Evaluate(same).Value.Number.Should().Be(-1, same);
        }

        // Through LN and EXP the ROM's series and the host's functions differ: in the last bit for 2^0.5, and by about
        // 3E-8 for 3^70, whose LN error the ROM multiplies by 70.
        double rootTwo = evaluator.Evaluate("A").Value.Number;
        evaluator.Evaluate("2^0.5").Value.Number.Should().BeApproximately(rootTwo, rootTwo * 1e-9);
        double large = evaluator.Evaluate("D").Value.Number;
        evaluator.Evaluate("3^70").Value.Number.Should().BeApproximately(large, large * 1e-7);

        // Exponent 0 holds reals down to 2^-129: 3E-39/2 is no zero in the ROM or the watch, and an exact half keeps
        // an odd mantissa when BASIC stores it.
        BbcMachineTests.Type(machine, "S=3E-39/2:U=2147483649.5\r");
        BbcMachineTests.RunToPrompt(machine);
        evaluator.Evaluate("S").Value.Number.Should().BeGreaterThan(0);
        evaluator.Evaluate("3E-39/2=S").Value.Number.Should().Be(-1);
        evaluator.Evaluate("U").Value.Number.Should().Be(2147483649.0);

        // Written by the debugger, they pack as BASIC packs them.
        BasicVariables variables = new(BasicDialect.BbcBasic, Memory(machine));
        BasicVariable small = variables.Find("S") ?? throw new InvalidOperationException("No S.");
        double tiny = Math.ScaleB(0.75, -128);
        variables.Write(small.Kind, small.ValueAddress, new BasicValue(tiny));
        variables.Read(small.Kind, small.ValueAddress).Number.Should().Be(tiny);
        byte[] packed = [.. Enumerable.Range(0, 5).Select(offset => machine.Bus.Peek((ushort)(small.ValueAddress + offset)))];
        packed.Should().Equal(0, 0x40, 0, 0, 0);
        variables.Write(small.Kind, small.ValueAddress, new BasicValue(2147483649.5));
        variables.Read(small.Kind, small.ValueAddress).Number.Should().Be(2147483649.0);

        // NaN and infinity have no packed form: writing one is too big, and the variable keeps its value.
        foreach (double unpackable in (double[])[double.NaN, double.PositiveInfinity, double.NegativeInfinity])
        {
            Action write = () => variables.Write(small.Kind, small.ValueAddress, new BasicValue(unpackable));
            write.Should().Throw<OverflowException>(unpackable.ToString(System.Globalization.CultureInfo.InvariantCulture));
            variables.Read(small.Kind, small.ValueAddress).Number.Should().Be(2147483649.0);
        }

        // The integer &80000000 is an integer, but the real -2147483648 is too big to be made one, as the ROM has it.
        BbcMachineTests.Type(machine, "CLS:PRINT STR$(NOT &80000000);\"|\";STR$INT(&80000000)\r");
        BbcMachineTests.RunToPrompt(machine);
        machine.ReadTextScreen().Should().Contain(line => line.Replace(" ", "") == "2147483647|-2147483648");
        evaluator.Evaluate("NOT &80000000").Value.Number.Should().Be(2147483647);
        evaluator.Evaluate("INT(&80000000)").Value.Number.Should().Be(-2147483648);
        BasicEvaluator.IsTrue(evaluator.Evaluate("&80000000"), BasicDialect.BbcBasic).Should().BeTrue();
        foreach (string real in (string[])["NOT -2147483648", "INT(-2147483648)"])
        {
            BbcMachineTests.Type(machine, $"CLS:PRINT {real}\r");
            BbcMachineTests.RunToPrompt(machine);
            machine.ReadTextScreen().Should().Contain(line => line.Contains("Too big"), real);
            Action tooBig = () => evaluator.Evaluate(real);
            tooBig.Should().Throw<FormatException>().WithMessage("Too big.", real);
        }

        Action condition = () => BasicEvaluator.IsTrue(evaluator.Evaluate("-2147483648"), BasicDialect.BbcBasic);
        condition.Should().Throw<FormatException>().WithMessage("Too big.");

        // Assigning to an integer variable takes the integer &80000000 and refuses the real -2147483648, as BASIC does.
        BbcMachineTests.Type(machine, "CLS:Z%=-2147483648\r");
        BbcMachineTests.RunToPrompt(machine);
        machine.ReadTextScreen().Should().Contain(line => line.Contains("Too big"));
        BasicVariable z = variables.Find("Z%") ?? throw new InvalidOperationException("No Z%.");
        variables.Write(z.Kind, z.ValueAddress, evaluator.Evaluate("&80000000").Value);
        variables.Read(z.Kind, z.ValueAddress).Number.Should().Be(-2147483648);

        // Read back, it is still an integer: it writes back, is true in a condition and works in a watch.
        BasicValue stored = variables.Read(z.Kind, z.ValueAddress);
        stored.Long.Should().Be(-2147483648);
        variables.Write(z.Kind, z.ValueAddress, stored);
        BasicEvaluator.IsTrue(new BasicResult(stored), BasicDialect.BbcBasic).Should().BeTrue();
        evaluator.Evaluate("NOT Z%").Value.Number.Should().Be(2147483647);
        Action realWrite = () => variables.Write(z.Kind, z.ValueAddress, evaluator.Evaluate("-2147483648").Value);
        realWrite.Should().Throw<OverflowException>();

        // An FN's name takes @ anywhere, in the ROM and the watch.
        BbcMachineTests.Type(machine, "10 DEF FNa@b=7\rCLS:PRINT FNa@b\r");
        BbcMachineTests.RunToPrompt(machine);
        machine.ReadTextScreen().Should().Contain(line => line.Trim() == "7");
        evaluator.Evaluate("FNa@b").Value.Number.Should().Be(7);

        // With @%'s top byte set, STR$ takes @%'s format (STR$1 is 1.00 here, in the ROM), which the watch says it does
        // not show rather than give the general format; STR$~ is hexadecimal either way.
        BbcMachineTests.Type(machine, "@%=&0102020A:CLS:PRINT STR$1\r");
        BbcMachineTests.RunToPrompt(machine);
        machine.ReadTextScreen().Should().Contain(line => line.TrimEnd() == "1.00");
        Action formatted = () => evaluator.Evaluate("STR$1");
        formatted.Should().Throw<FormatException>().WithMessage("*@%*");
        System.Text.Encoding.ASCII.GetString(evaluator.Evaluate("STR$~255").Value.Text ?? []).Should().Be("FF");
        BbcMachineTests.Type(machine, "@%=&90A\r");
        BbcMachineTests.RunToPrompt(machine);
        System.Text.Encoding.ASCII.GetString(evaluator.Evaluate("STR$1").Value.Text ?? []).Should().Be("1");
    }

    /// <summary>
    ///  A variable list that loops is corrupt: making a variable on it fails rather than hanging.
    /// </summary>
    [TestMethod]
    public void LoopingVariableListIsCorrupt()
    {
        BbcMachine machine = Boot();
        DelegateBasicMemory memory = Memory(machine);
        BasicVariables variables = new(BasicDialect.BbcBasic, memory);
        BasicVariable first = variables.Create("ab");
        BasicProgram.WriteWord(memory, first.Address, first.Address);  // its link points at itself
        Action make = () => variables.Create("ac");
        make.Should().Throw<InvalidOperationException>().WithMessage("*corrupt*");
    }

    /// <summary>
    ///  A PROC or FN name may start with a digit, and a condition is true as BBC BASIC's IF takes it: 0.5 is false, as
    ///  a 32-bit integer, and a string is refused.
    /// </summary>
    [TestMethod]
    public void DigitRoutinesAndConditions()
    {
        BasicSource source = BasicSource.Analyze("10 PROC1\n20 END\n30 DEF PROC1:ENDPROC\n", BasicDialect.BbcBasic);
        source.Sites.Where(site => site.Kind == BasicSiteKind.Function).Select(site => site.Key).Should().Equal("PROC1", "PROC1");

        BasicEvaluator.IsTrue(new BasicResult(new BasicValue(0.5)), BasicDialect.BbcBasic).Should().BeFalse();
        BasicEvaluator.IsTrue(new BasicResult(new BasicValue(-1)), BasicDialect.BbcBasic).Should().BeTrue();
        BasicEvaluator.IsTrue(new BasicResult(new BasicValue(0.5)), BasicDialect.AppleSoft).Should().BeTrue();
        Action text = () => BasicEvaluator.IsTrue(new BasicResult(BasicValue.Of([1])), BasicDialect.BbcBasic);
        text.Should().Throw<FormatException>();
    }

    /// <summary>
    ///  A string at the top of the heap grows in place, as BASIC's assignment grows it, so growing one from 1 to 255
    ///  characters takes about 255 bytes of heap, not the sum of every length.
    /// </summary>
    [TestMethod]
    public void StringsGrowInPlace()
    {
        BbcMachine machine = Boot();
        DelegateBasicMemory memory = Memory(machine);
        BasicVariables variables = new(BasicDialect.BbcBasic, memory);
        BasicVariable text = variables.Create("T$");
        int heap = memory.Read(0x02) | (memory.Read(0x03) << 8);
        for (int length = 1; length <= 255; length++)
        {
            variables.Write(text.Kind, text.ValueAddress, BasicValue.Of([.. Enumerable.Repeat((byte)'A', length)]));
        }

        int used = (memory.Read(0x02) | (memory.Read(0x03) << 8)) - heap;
        used.Should().BeLessThan(400);
        variables.Read(text.Kind, text.ValueAddress).Text.Should().HaveCount(255);
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

        // A routine's name takes @ anywhere, as SCAN_VARIABLE_NAME reads it: PROC@foo, PROCfoo@a and PROCfoo@b are
        // three routines, none of them foo.
        BasicSource at = BasicSource.Analyze("10 PROC@foo:PROCfoo@a:PROCfoo@b\n", BasicDialect.BbcBasic);
        at.Sites.Where(site => site.Kind == BasicSiteKind.Function).Select(site => site.Key)
            .Should().Equal("PROC@foo", "PROCfoo@a", "PROCfoo@b");

        // A number's exponent is READ_EXPONENT's: E and a sign whatever follows, and up to two digits, so 2E and 3E+ hold
        // no variable E, and renaming E5 does not touch 1E5; D starts a name, as in 1:D5.
        BasicSource numbers = BasicSource.Analyze("10 E5=1:E=2:X=1E5:Y=2E:Z=3E+:W=4E-2:V=D5\n", BasicDialect.BbcBasic);
        numbers.Sites.Where(site => site.Kind == BasicSiteKind.Variable).Select(site => site.Text)
            .Should().Equal("E5", "E", "X", "Y", "Z", "W", "V", "D5");

        // A hover names a BBC routine with its word, and a BBC name whole: no two-character note, which the Microsoft
        // BASICs still get.
        BasicSite procedure = routines.First(site => site.Key == "PROCfoo");
        BasicSite function = routines.First(site => site.Key == "FNfoo");
        source.Summary(procedure).Should().Be("**PROCfoo**: a procedure.");
        source.Summary(function).Should().Be("**FNfoo**: a function.");
        BasicSource variables = BasicSource.Analyze("10 count%=1:PRINT count%\n", BasicDialect.BbcBasic);
        BasicSite count = variables.Sites.First(site => site.Kind == BasicSiteKind.Variable);
        variables.Summary(count).Should().NotContain("first two characters");
        BasicSource apple = BasicSource.Analyze("10 ZEBRA=1:PRINT ZE\n", BasicDialect.AppleSoft);
        BasicSite zebra = apple.Sites.First(site => site.Kind == BasicSiteKind.Variable);
        apple.Summary(zebra).Should().Contain("first two characters");

        // NaN, which no comparison holds for, is too big for a condition rather than cast to an integer.
        Action nan = () => BasicEvaluator.IsTrue(new BasicResult(new BasicValue(double.NaN)), BasicDialect.BbcBasic);
        nan.Should().Throw<FormatException>().WithMessage("Too big.");
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

        // The longest name, 255 characters, reads back whole; a longer one is refused before anything is made.
        string longest = "c" + new string('d', 254);
        BasicVariable madeLongest = variables.Create(longest);
        variables.Find(longest).Should().Be(madeLongest);
        variables.Write(madeLongest.Kind, madeLongest.ValueAddress, new BasicValue(1.5));
        variables.Read(madeLongest.Kind, madeLongest.ValueAddress).Number.Should().Be(1.5);
        variables.Find(longest).Should().Be(madeLongest, "writing the value left the name alone");
        Action tooLong = () => variables.Create("e" + new string('f', 255));
        tooLong.Should().Throw<ArgumentException>();
    }

    /// <summary>
    ///  Arrays as the ROM lays them out: the last subscript varies fastest, reals take five bytes and integers and
    ///  strings four, and each element's address and subscripts agree with the value BASIC put there.
    /// </summary>
    [TestMethod]
    public void ArraysAsTheRomLaysThemOut()
    {
        BbcMachine machine = Boot();
        string[] lines =
        [
            "DIM R(2,3),I%(1,4),S$(3,1)",
            "FOR A=0 TO 2:FOR B=0 TO 3:R(A,B)=A*10+B+0.5:NEXT:NEXT",
            "FOR A=0 TO 1:FOR B=0 TO 4:I%(A,B)=A*100+B:NEXT:NEXT",
            "FOR A=0 TO 3:FOR B=0 TO 1:S$(A,B)=STR$A+\",\"+STR$B:NEXT:NEXT",
            ""
        ];

        BbcMachineTests.Type(machine, string.Join('\r', lines));
        BbcMachineTests.RunToPrompt(machine);
        BasicVariables variables = new(BasicDialect.BbcBasic, Memory(machine));
        Dictionary<string, BasicArray> arrays = variables.Arrays().ToDictionary(array => array.Name);

        void Check(string name, int[] dimensions, int size, Func<int[], BasicValue, bool> holds)
        {
            BasicArray array = arrays[name];
            array.Dimensions.Should().Equal(dimensions, name);
            array.ElementSize.Should().Be(size, name);
            array.LastFastest.Should().BeTrue();
            for (int index = 0; index < array.Count; index++)
            {
                int[] subscripts = array.Subscripts(index);
                int address = array.ElementAddress(subscripts);
                address.Should().Be(array.ElementsAddress + (index * size), $"{name}({string.Join(',', subscripts)})");
                holds(subscripts, variables.Read(array.Kind, address)).Should().BeTrue($"{name}({string.Join(',', subscripts)})");
            }

            // The last subscript varies fastest: the second element is (0,1).
            array.Subscripts(1).Should().Equal(0, 1);
        }

        Check("R", [3, 4], 5, (at, value) => value.Number == (at[0] * 10) + at[1] + 0.5);
        Check("I%", [2, 5], 4, (at, value) => value.Number == (at[0] * 100) + at[1]);
        Check("S$", [4, 2], 4, (at, value) => System.Text.Encoding.ASCII.GetString(value.Text ?? []) == $"{at[0]},{at[1]}");
    }

    /// <summary>
    ///  Edge cases the ROM decides: &amp;80000000 DIV or MOD anything is 0, as DIVIDE_INTEGERS loses its one set bit;
    ///  labels are case-sensitive, as BBC names are; AUTO's and RENUMBER's numbers name no line; and the heap is full
    ///  when a new block would reach BASIC's stack.
    /// </summary>
    [TestMethod]
    public void RomEdgeCases()
    {
        BbcMachine machine = Boot();
        BasicEvaluator evaluator = new(BasicDialect.BbcBasic, Memory(machine));
        BbcMachineTests.Type(machine, "CLS:PRINT &80000000 DIV 2;\"|\";&80000000 MOD 3;\"|\";-7 DIV 2;\"|\";-7 MOD 2\r");
        BbcMachineTests.RunToPrompt(machine);
        machine.ReadTextScreen().Should().Contain(line => line.Replace(" ", "") == "0|0|-3|-1");
        foreach ((string expression, double value) in (ReadOnlySpan<(string, double)>)[
            ("&80000000 DIV 2", 0), ("&80000000 MOD 3", 0), ("&80000000 DIV -1", 0), ("-7 DIV 2", -3), ("-7 MOD 2", -1)])
        {
            evaluator.Evaluate(expression).Value.Number.Should().Be(value, expression);
        }

        // READ_NUMBER stops at a second point, which BASIC then finds where no operator can be.
        BbcMachineTests.Type(machine, "CLS:X=1.2.3\r");
        BbcMachineTests.RunToPrompt(machine);
        machine.ReadTextScreen().Should().Contain(line => line.StartsWith("Syntax error", StringComparison.Ordinal));
        Action points = () => evaluator.Evaluate("1.2.3");
        points.Should().Throw<FormatException>();

        // @loop is not LOOP: GOTO LOOP stays a computed jump through the variable LOOP.
        const string Source = "REM retrocore bbcbasic\n    LOOP=20:GOTO LOOP\n@loop\n    GOTO loop\n";
        string program = BasicProgram.Parse(Source, BasicDialect.BbcBasic).Program?.ToText() ?? "";
        program.Should().Contain("GOTO LOOP").And.Contain("GOTO 20");

        // AUTO and RENUMBER take a new first line and a step; DELETE's lines are references.
        BasicSource renumber = BasicSource.Analyze("10 RENUMBER 100,10:AUTO 500,5\n20 DELETE 30,40\n", BasicDialect.BbcBasic);
        renumber.Sites.Where(site => site.Kind == BasicSiteKind.LineReference).Select(site => site.Number)
            .Should().Equal(30, 40);

        // DELETE and LIST take a range, a comma between two lines, either of them a label; end: is a label, as BBC's
        // words are capitals only.
        const string Ranges = "REM retrocore bbcbasic\n@first\n    PRINT 1\n@last\n    PRINT 2\n    DELETE first,last:LIST 10,last\n    GOTO end\nend:\n    PRINT 3\n";
        string ranged = BasicProgram.Parse(Ranges, BasicDialect.BbcBasic).Program?.ToText() ?? "";
        ranged.Should().Contain("DELETE 10,20:LIST 10,20").And.Contain("GOTO 50");

        // A bare point is the real zero: VAL(".") is real, so adding &7FFFFFFF and 1 does not wrap, in the ROM and the
        // watch.
        BbcMachineTests.Type(machine, "CLS:PRINT STR$(VAL(\".\")+&7FFFFFFF+1);\"|\";.+1\r");
        BbcMachineTests.RunToPrompt(machine);
        machine.ReadTextScreen().Should().Contain(line => line.Replace(" ", "") == "2147483648|1");
        evaluator.Evaluate("VAL(\".\")+&7FFFFFFF+1").Value.Number.Should().Be(2147483648.0);
        evaluator.Evaluate(".+1").Value.Number.Should().Be(1);

        // A real variable's block is 2 + 2 + 1 + 5 bytes for abc: reaching the stack is no room, one short is.
        DelegateBasicMemory memory = Memory(machine);
        BasicVariables variables = new(BasicDialect.BbcBasic, memory);
        int heap = memory.Read(0x02) | (memory.Read(0x03) << 8);
        int stack = memory.Read(0x04) | (memory.Read(0x05) << 8);
        try
        {
            memory.Write(0x04, (byte)(heap + 10));
            memory.Write(0x05, (byte)((heap + 10) >> 8));
            Action reaching = () => variables.Create("abc");
            reaching.Should().Throw<InvalidOperationException>().WithMessage("No room*");
            memory.Write(0x04, (byte)(heap + 11));
            memory.Write(0x05, (byte)((heap + 11) >> 8));
            variables.Create("abc").Name.Should().Be("abc");

            // A tiny real, down to the smallest double, packs as zero rather than overflowing the rounding.
            BasicVariable abc = variables.Find("abc") ?? throw new InvalidOperationException("No abc.");
            foreach (double tiny in (double[])[double.Epsilon, -double.Epsilon, 1e-300, Math.ScaleB(1.0, -131)])
            {
                variables.Write(abc.Kind, abc.ValueAddress, new BasicValue(tiny));
                variables.Read(abc.Kind, abc.ValueAddress).Number.Should().Be(0, tiny.ToString(System.Globalization.CultureInfo.InvariantCulture));
            }
        }
        finally
        {
            memory.Write(0x04, (byte)stack);
            memory.Write(0x05, (byte)(stack >> 8));
        }
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

    /// <summary>
    ///  Products and whole powers come out bit for bit as the ROM's, which truncates its partial products: 1.1*1.1 is
    ///  1.21 in BASIC, where the exact product rounds a bit higher, and 1.1^10 drifts as BASIC's does.
    /// </summary>
    [TestMethod]
    public void RealProductsAsTheRomWorksThem()
    {
        BbcMachine machine = Boot();
        string[] expressions =
        [
            "1.1*1.1", "1.21*3.14159", "-7.77*0.3", "123456.789*1E-5", "3.14159*-7.77", "2.5*1.1",
            "1.1^10", "1.1^-3", "2.5^7", "0.3^5", "-7.77^3", "(1.1*1.1=1.21)"
        ];

        BbcMachineTests.Type(machine, $"DIM R({expressions.Length})\r");
        BbcMachineTests.RunToPrompt(machine);
        for (int index = 0; index < expressions.Length; index++)
        {
            BbcMachineTests.Type(machine, $"R({index})={expressions[index]}\r");
            BbcMachineTests.RunToPrompt(machine);
        }

        BasicVariables variables = new(BasicDialect.BbcBasic, Memory(machine));
        BasicEvaluator evaluator = new(BasicDialect.BbcBasic, Memory(machine));
        BasicArray array = variables.Arrays().Single(found => found.Name == "R");
        for (int index = 0; index < expressions.Length; index++)
        {
            double rom = variables.Read(array.Kind, array.ElementAddress([index])).Number;
            evaluator.Evaluate(expressions[index]).Value.Number.Should().Be(rom, expressions[index]);
        }
    }

    /// <summary>
    ///  The indirections read memory as BASIC does: ?, ! and $ before a factor, and ? and ! straight after a variable
    ///  or an array element, whose real value is truncated; $ stops at a carriage return, and without one in 256 bytes
    ///  is empty.
    /// </summary>
    [TestMethod]
    public void IndirectionsAsTheRomReadsThem()
    {
        BbcMachine machine = Boot();
        string[] setup =
        [
            "DIM B% 300,C% 300,D% 300,A%(2):A%(1)=B%:R=B%+0.75:J%=8",
            "?&70=200:!&80=-123456:B%?3=77:B%!8=&12345678:B%?77=99:$(B%+20)=\"HELLO\"",
            "FOR I%=0 TO 299:C%?I%=65:NEXT:FOR I%=0 TO 254:D%?I%=66:NEXT:D%?255=13"
        ];

        string[] numbers =
        [
            "?&70", "!&80", "B%?3", "B%!8", "B%?3+1", "?&70*2", "A%(1)?3", "R?3", "?(B%+3)", "!(B%+8) AND &FF", "-?&70",
            "?&70=200", "A%(1)!J%", "B%?B%?3", "LEN $(B%+20)", "LEN $C%", "LEN $D%", "?(&10000+&70)", "?-&FF90", "!&FFFF AND &FFFFFF", "!-1 AND &FFFF"
        ];

        string[] texts = ["$(B%+20)", "$(B%+20)+\"!\"", "LEFT$($D%,3)"];

        BbcMachineTests.Type(machine, string.Join("\r", setup) + $"\rDIM N({numbers.Length}),T$({texts.Length})\r");
        BbcMachineTests.RunToPrompt(machine);
        for (int index = 0; index < numbers.Length; index++)
        {
            BbcMachineTests.Type(machine, $"N({index})={numbers[index]}\r");
            BbcMachineTests.RunToPrompt(machine);
        }

        for (int index = 0; index < texts.Length; index++)
        {
            BbcMachineTests.Type(machine, $"T$({index})={texts[index]}\r");
            BbcMachineTests.RunToPrompt(machine);
        }

        BasicVariables variables = new(BasicDialect.BbcBasic, Memory(machine));

        // The watch reads through a memory that refuses an address outside 16 bits, so a read past &FFFF must wrap.
        BasicEvaluator evaluator = new(BasicDialect.BbcBasic, new DelegateBasicMemory(
            address => address is >= 0 and <= 0xFFFF ? machine.Bus.Peek((ushort)address) : throw new ArgumentOutOfRangeException(nameof(address)),
            (address, value) => machine.Bus.Write((ushort)address, value)));

        BasicArray stored = variables.Arrays().Single(found => found.Name == "N");
        for (int index = 0; index < numbers.Length; index++)
        {
            double rom = variables.Read(stored.Kind, stored.ElementAddress([index])).Number;

            // Only LEN $C%, a string with no carriage return, is 0: any other 0 would be BASIC refusing the line.
            (rom == 0).Should().Be(numbers[index] == "LEN $C%", numbers[index]);
            evaluator.Evaluate(numbers[index]).Value.Number.Should().Be(rom, numbers[index]);
        }

        BasicArray strings = variables.Arrays().Single(found => found.Name == "T$");
        for (int index = 0; index < texts.Length; index++)
        {
            byte[]? rom = variables.Read(strings.Kind, strings.ElementAddress([index])).Text;
            evaluator.Evaluate(texts[index]).Value.Text.Should().Equal(rom, texts[index]);
        }

        // The offset is a factor, so B%?B%?3 is B%?(B%?3); a space before the operator ends the variable,
        // and $ refuses page zero, as BASIC does.
        Action spaced = () => evaluator.Evaluate("B% ?3");
        spaced.Should().Throw<FormatException>().WithMessage("Syntax error*");
        Action zeroPage = () => evaluator.Evaluate("$&70");
        zeroPage.Should().Throw<FormatException>().WithMessage("$ range.");
        Action text = () => evaluator.Evaluate("T$(0)?1");
        text.Should().Throw<FormatException>().WithMessage("Type mismatch*");
    }

    /// <summary>
    ///  VAL of a string with no number is a real 0, so adding to it does not wrap as an integer would; and the FOR
    ///  stack read while loops are live, integer and real, nested, on one line and over two.
    /// </summary>
    [TestMethod]
    public void ValAndLiveLoopsAsTheRomHasThem()
    {
        BbcMachine machine = Boot();
        BbcMachineTests.Type(machine, "R=VAL(\"X\")+&7FFFFFFF+1:S=VAL(\"\")+&7FFFFFFF+1\r");
        BbcMachineTests.RunToPrompt(machine);
        BasicVariables variables = new(BasicDialect.BbcBasic, Memory(machine));
        BasicEvaluator evaluator = new(BasicDialect.BbcBasic, Memory(machine));
        foreach ((string name, string expression) in (ReadOnlySpan<(string, string)>)[("R", "VAL(\"X\")+&7FFFFFFF+1"), ("S", "VAL(\"\")+&7FFFFFFF+1")])
        {
            BasicVariable stored = variables.Find(name) ?? throw new InvalidOperationException($"No {name}.");
            double rom = variables.Read(stored.Kind, stored.ValueAddress).Number;
            evaluator.Evaluate(expression).Value.Number.Should().Be(rom, expression);
        }

        // STOP would reset the stacks on its way to the prompt, so the loops are read while line 30 runs on.
        foreach (string line in (string[])["10 FOR I%=1 TO -9 STEP -2:FOR F=0.5 TO -3.25 STEP -0.75", "20 FOR J%=5 TO 7", "30 GOTO 30"])
        {
            BbcMachineTests.Type(machine, line + "\r");
            BbcMachineTests.RunToPrompt(machine);
        }

        BbcMachineTests.Type(machine, "RUN\r");

        variables = new(BasicDialect.BbcBasic, Memory(machine));
        int Address(string name) => (variables.Find(name) ?? throw new InvalidOperationException($"No {name}.")).ValueAddress;
        variables.Loops(0, 0, 0).Should().Equal(
            new BasicLoop(Address("J%"), 1, 7, 20),
            new BasicLoop(Address("F"), -0.75, -3.25, 10),
            new BasicLoop(Address("I%"), -2, -9, 10));
    }

    /// <summary>
    ///  Numbers are read as READ_NUMBER reads them, bit for bit: the digits as a 40-bit integer, scaled by ten a step
    ///  at a time with the ROM's truncating multiply and divide, then rounded once, which is not always the nearest
    ///  real to the decimal (4294967295.5 is 2^32).
    /// </summary>
    [TestMethod]
    public void NumbersReadAsTheRomReadsThem()
    {
        BbcMachine machine = Boot();
        string[] expressions =
        [
            "4294967295.5", "512330.05169784", "598.23534", "0.1", "3.14159265", "1.7E-38", "12345678901234",
            "0.123456789012", "65536.00001", "1E-10", "VAL\"4294967295.5\"", "VAL\"-598.23534\"", "VAL\"1.7E-38\""
        ];

        BbcMachineTests.Type(machine, $"DIM R({expressions.Length})\r");
        BbcMachineTests.RunToPrompt(machine);
        for (int index = 0; index < expressions.Length; index++)
        {
            BbcMachineTests.Type(machine, $"R({index})={expressions[index]}\r");
            BbcMachineTests.RunToPrompt(machine);
        }

        BasicVariables variables = new(BasicDialect.BbcBasic, Memory(machine));
        BasicEvaluator evaluator = new(BasicDialect.BbcBasic, Memory(machine));
        BasicArray array = variables.Arrays().Single(found => found.Name == "R");
        for (int index = 0; index < expressions.Length; index++)
        {
            double rom = variables.Read(array.Kind, array.ElementAddress([index])).Number;
            evaluator.Evaluate(expressions[index]).Value.Number.Should().Be(rom, expressions[index]);
        }

        evaluator.Evaluate("4294967295.5").Value.Number.Should().Be(4294967296);
    }

    /// <summary>
    ///  Quotients, square roots and RAD and DEG come out bit for bit as the ROM's: DIVIDE_FP_A_BY_FP_B keeps seven
    ///  rounding bits and no remainder, so 75/9.1 rounds as a half would; SQR is five of the ROM's Newton steps; RAD and
    ///  DEG multiply by its packed constants.
    /// </summary>
    [TestMethod]
    public void QuotientsRootsAndAnglesAsTheRomWorksThem()
    {
        BbcMachine machine = Boot();
        string[] expressions =
        [
            "75/9.1", "150/9.1", "1/3", "-1/3", "1.1^-3", "(-3)^-5", "SQR 6", "SQR 2", "SQR 1E-38", "RAD 1", "RAD 180",
            "DEG 13", "DEG PI"
        ];

        BbcMachineTests.Type(machine, $"DIM R({expressions.Length})\r");
        BbcMachineTests.RunToPrompt(machine);
        for (int index = 0; index < expressions.Length; index++)
        {
            BbcMachineTests.Type(machine, $"R({index})={expressions[index]}\r");
            BbcMachineTests.RunToPrompt(machine);
        }

        BasicVariables variables = new(BasicDialect.BbcBasic, Memory(machine));
        BasicEvaluator evaluator = new(BasicDialect.BbcBasic, Memory(machine));
        BasicArray array = variables.Arrays().Single(found => found.Name == "R");
        for (int index = 0; index < expressions.Length; index++)
        {
            double rom = variables.Read(array.Kind, array.ElementAddress([index])).Number;
            evaluator.Evaluate(expressions[index]).Value.Number.Should().Be(rom, expressions[index]);
        }

        // A sign takes a factor without the sign tests, so a second sign starts a name; -0.0 is 0, unsigned.
        foreach (string signs in (string[])["--1", "- -1", "-+1", "+-1", "++1"])
        {
            Action chained = () => evaluator.Evaluate(signs);
            chained.Should().Throw<FormatException>(signs).WithMessage("No such variable*");
        }

        evaluator.Evaluate("5--3").Value.Number.Should().Be(8);
        double.IsNegative(evaluator.Evaluate("-0.0").Value.Number).Should().BeFalse();
    }

    /// <summary>
    ///  STR$ writes a real character for character as NUMBER_TO_STRING does, rounding with its own half a unit rather
    ///  than to the nearest decimal: 89132.34994506836 is 89132.34994.
    /// </summary>
    [TestMethod]
    public void StringsAsTheRomWritesThem()
    {
        BbcMachine machine = Boot();
        string[] expressions =
        [
            "89132.34994506836", "476707.7541503906", "35.5469564050436", "-4486.574285507202", "1/3", "PI", "9.9999999995",
            "999999999.95", "0.099999999999", "1E-10", "1.5E10", "-2147483648"
        ];

        BbcMachineTests.Type(machine, $"DIM S$({expressions.Length})\r");
        BbcMachineTests.RunToPrompt(machine);
        for (int index = 0; index < expressions.Length; index++)
        {
            BbcMachineTests.Type(machine, $"S$({index})=STR$({expressions[index]})\r");
            BbcMachineTests.RunToPrompt(machine);
        }

        BasicVariables variables = new(BasicDialect.BbcBasic, Memory(machine));
        BasicEvaluator evaluator = new(BasicDialect.BbcBasic, Memory(machine));
        BasicArray array = variables.Arrays().Single(found => found.Name == "S$");
        for (int index = 0; index < expressions.Length; index++)
        {
            byte[] rom = variables.Read(array.Kind, array.ElementAddress([index])).Text ?? [];
            (evaluator.Evaluate($"STR$({expressions[index]})").Value.Text ?? []).Should().Equal(rom, expressions[index]);
        }

        BbcBasicExpression.Format(89132.34994506836).Should().Be("89132.34994");
    }

    /// <summary>
    ///  Sums and differences come out bit for bit as ADD_FP_B_TO_FP_A's, which lines the smaller real up in 40 bits,
    ///  dropping what falls below, and rounds once: 2147483649-(0.5+1/1048576) is 2147483649. A unary plus keeps its
    ///  factor's type, so +N$ is N$, but takes no string literal, as it skips EVALUATE_FACTOR's test for one.
    /// </summary>
    [TestMethod]
    public void SumsAsTheRomAlignsThem()
    {
        BbcMachine machine = Boot();
        string[] expressions =
        [
            "2147483649-(0.5+1/1048576)", "2147483649+(0.5+1/1048576)", "1+1/3E9", "1-1/3E9", "4294967295-1/7",
            "-1E10+1/3", "PI-PI/1E9"
        ];

        BbcMachineTests.Type(machine, $"N$=\"ABCABC\":DIM R({expressions.Length})\r");
        BbcMachineTests.RunToPrompt(machine);
        for (int index = 0; index < expressions.Length; index++)
        {
            BbcMachineTests.Type(machine, $"R({index})={expressions[index]}\r");
            BbcMachineTests.RunToPrompt(machine);
        }

        BasicVariables variables = new(BasicDialect.BbcBasic, Memory(machine));
        BasicEvaluator evaluator = new(BasicDialect.BbcBasic, Memory(machine));
        BasicArray array = variables.Arrays().Single(found => found.Name == "R");
        for (int index = 0; index < expressions.Length; index++)
        {
            double rom = variables.Read(array.Kind, array.ElementAddress([index])).Number;
            evaluator.Evaluate(expressions[index]).Value.Number.Should().Be(rom, expressions[index]);
        }

        evaluator.Evaluate("2147483649-(0.5+1/1048576)").Value.Number.Should().Be(2147483649);

        BbcMachineTests.Type(machine, "CLS:PRINT LEN +N$;\"|\";LEN +(N$)\r");
        BbcMachineTests.RunToPrompt(machine);
        BbcMachineTests.Type(machine, "PRINT +\"AB\"\r");
        BbcMachineTests.RunToPrompt(machine);
        string[] screen = [.. machine.ReadTextScreen().Select(line => line.Trim()).Where(line => line.Length > 0)];
        screen.Should().Contain("6|6").And.Contain("No such variable");
        evaluator.Evaluate("LEN +N$").Value.Number.Should().Be(6);
        evaluator.Evaluate("LEN +(N$)").Value.Number.Should().Be(6);
        Action literal = () => evaluator.Evaluate("+\"AB\"");
        literal.Should().Throw<FormatException>().WithMessage("No such variable*");
        Action negated = () => evaluator.Evaluate("-N$");
        negated.Should().Throw<FormatException>();
    }

    /// <summary>
    ///  The smallest positive real, 2^-129, reads back as 0 once packed, as its five bytes are all 0, and the ROM packs
    ///  the operand PUSH_REAL puts on its stack: the left one, or the right real when the left is an integer, and
    ///  always the left of / and ^. So x+0, 0+x and x=0 treat it as 0, where 2.0*x does not.
    /// </summary>
    [TestMethod]
    public void TinyRealsAsTheRomPacksThem()
    {
        BbcMachine machine = Boot();
        string[] expressions = ["(1/2^43/2^43/2^43)+0", "0+(1/2^43/2^43/2^43)", "(1/2^43/2^43/2^43)-0", "0-(1/2^43/2^43/2^43)", "(1/2^43/2^43/2^43)*2", "2*(1/2^43/2^43/2^43)", "2.0*(1/2^43/2^43/2^43)", "1.5*(1/2^43/2^43/2^43)", "((1/2^43/2^43/2^43)=0)", "(0=(1/2^43/2^43/2^43))", "(0<(1/2^43/2^43/2^43))", "-(1/2^43/2^43/2^43)+0", "SQR (1/2^43/2^43/2^43)"];
        BbcMachineTests.Type(machine, $"DIM R({expressions.Length})\r");
        BbcMachineTests.RunToPrompt(machine);
        for (int index = 0; index < expressions.Length; index++)
        {
            BbcMachineTests.Type(machine, $"R({index})={expressions[index]}\r");
            BbcMachineTests.RunToPrompt(machine);
        }

        BasicVariables variables = new(BasicDialect.BbcBasic, Memory(machine));
        BasicEvaluator evaluator = new(BasicDialect.BbcBasic, Memory(machine));
        BasicArray array = variables.Arrays().Single(found => found.Name == "R");
        for (int index = 0; index < expressions.Length; index++)
        {
            double rom = variables.Read(array.Kind, array.ElementAddress([index])).Number;
            evaluator.Evaluate(expressions[index]).Value.Number.Should().Be(rom, expressions[index]);
        }

        BbcMachineTests.Type(machine, "CLS:PRINT 1/(1/2^43/2^43/2^43)\r");
        BbcMachineTests.RunToPrompt(machine);
        machine.ReadTextScreen().Should().Contain(line => line.StartsWith("Too big", StringComparison.Ordinal));
        Action reciprocal = () => evaluator.Evaluate("1/(1/2^43/2^43/2^43)");
        reciprocal.Should().Throw<FormatException>().WithMessage("Too big*");
        evaluator.Evaluate("(1/2^43/2^43/2^43)+0").Value.Number.Should().Be(0);
    }
}
