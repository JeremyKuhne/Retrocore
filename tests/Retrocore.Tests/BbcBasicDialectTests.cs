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
    ///  A hexadecimal number is a constant, not a name: renaming BEEF leaves &amp;BEEF alone.
    /// </summary>
    [TestMethod]
    public void HexNumbersAreNotNames()
    {
        BasicSource source = BasicSource.Analyze("10 BEEF=1:PRINT &BEEF\n", BasicDialect.BbcBasic);
        source.Sites.Where(site => site.Kind == BasicSiteKind.Variable).Select(site => site.Key).Should().Equal("BEEF");
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
        Dictionary<string, BasicLabel> labels = new() { ["DONE"] = new("done", 1, 0, 4, 80) };
        foreach (string jump in (string[])["IF1THEN done", "IF X=1THEN done", "G.done", "GOS.done"])
        {
            BasicProgram.LabelReferences(BasicDialect.BbcBasic, jump, labels).Should().ContainSingle(jump)
                .Which.Name.Should().Be("DONE");
        }

        BasicProgram.LabelReferences(BasicDialect.BbcBasic, "ON ERROR *KEY 1 GOTO done", labels).Should().BeEmpty();
        BasicProgram.LabelReferences(BasicDialect.BbcBasic, "GOTO done%", labels).Should().BeEmpty("done% is another name");

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
