// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Basic;
using Retrocore.Machines.Atari;

namespace Retrocore.Tests;

/// <summary>
///  Atari BASIC's dialect: its tokenizer, the ROM's syntax checker ported, against the ROM itself, and its program
///  layout, listing and variables against the machine. The machine runs the SDK's OS, floating point package and BASIC,
///  so no dumps are needed.
/// </summary>
[TestClass]
public sealed class AtariBasicDialectTests
{
    // Lines that use every kind of statement and token: the implied LET, abbreviations, both forms of GOTO, strings,
    // arrays and substrings, constants that read differently, functions, and IF's THEN with a line or a statement.
    private static readonly string[] s_program =
    [
        "10 REM HELLO world, \"quoted\"",
        "20 DIM A$(20),B(10),C(3,4):COM D$(5)",
        "30 A$=\"HI\":B(3)=1.5:C(1,2)=-2E-5:X=.5:Y=1E+10:Z=123456789012",
        "40 FOR I=1 TO 10 STEP 2:PRINT I;\",\";A$(1,1):NEXT I",
        "50 IF A$=\"HI\" THEN PRINT \"YES\":GOTO 70",
        "60 IF X>=2 AND NOT Y<>3 OR Z THEN 10",
        "70 GOSUB 100:POKE 752,1:? CHR$(65);STR$(B(3))",
        "80 ON X GOTO 10,20,30:ON Y GOSUB 100",
        "90 DATA 1,2,ABC",
        "100 TRAP 40000:RETURN",
        "110 GRAPHICS 3+16:COLOR 1:PLOT 1,2:DRAWTO 3,4:POSITION 1,1",
        "120 SOUND 0,121,10,8:SETCOLOR 0,1,2:GO TO 130",
        "130 OPEN #1,4,0,\"D:X\":INPUT #1,A$:CLOSE #1:GET #1,K:PUT #1,K",
        "140 X=SIN(1)+COS(2)*SQR(4)^2-LEN(A$)/PEEK(106)+ASC(A$)+VAL(\"1\")",
        "150 PR.\"A\";:L. 10,20:LET NOTE1=1:POP:END"
    ];

    // The program a text parses to, which must have no errors.
    private static BasicProgram Program(string text) =>
        BasicProgram.Parse(text, BasicDialect.AtariBasic).Program ?? throw new AssertFailedException("The program has errors.");

    // An 800 at READY in the SDK's BASIC.
    private static AtariMachine Machine()
    {
        byte[] image =
        [
            .. AtariFloatingPointSourceTests.Assemble().Sections[0].Bytes.Span,
            .. AtariOsSourceTests.Assemble().Sections[0].Bytes.Span
        ];

        AtariMachine machine = new(
            new AtariRoms(image),
            left: new AtariCartridge(AtariBasicSourceTests.Assemble().Sections[0].Bytes.Span));

        AtariMachineTests.RunToReady(machine);
        return machine;
    }

    /// <summary>
    ///  The tokenizer's tables are the SDK's build of the ROM's, $A49F-$A879.
    /// </summary>
    [TestMethod]
    public void TablesAreTheRoms()
    {
        ReadOnlySpan<byte> rom = AtariBasicSourceTests.Assemble().Sections[0].Bytes.Span;
        int start = AtariBasicSyntax.TablesStart - 0xA000;
        rom.Slice(start, AtariBasicSyntax.Tables.Length).ToArray().Should().Equal(AtariBasicSyntax.Tables);
    }

    /// <summary>
    ///  The keywords of the editor's analysis, which the grammar is generated from, are the ROM's statement and function
    ///  names.
    /// </summary>
    [TestMethod]
    public void KeywordsAreTheRomsNames()
    {
        IReadOnlyList<string> keywords = BasicDialect.AtariBasic.Keywords;
        keywords.Take(AtariBasicSyntax.ImpliedLet).Should().Equal(AtariBasicDialect.StatementNames.Take(AtariBasicSyntax.ImpliedLet));
        keywords.TakeLast(24).Should().Equal(AtariBasicDialect.OperatorNames.Skip(AtariBasicDialect.FirstFunction - 0x10));
    }

    /// <summary>
    ///  A program typed on the machine and the same program tokenized by the dialect are the same bytes, and number
    ///  their variables alike.
    /// </summary>
    [TestMethod]
    public void TokensAreTheRoms()
    {
        AtariMachine machine = Machine();
        foreach (string line in s_program) { AtariMachineTests.Type(machine, line + "\r"); }

        BasicProgram typed = BasicProgram.Read(BasicDialect.AtariBasic, new AtariBasicMemory(machine));
        BasicParseResult parsed = BasicProgram.Parse(string.Join('\n', s_program), BasicDialect.AtariBasic);
        parsed.Diagnostics.Where(diagnostic => diagnostic.Severity == BasicSeverity.Error).Should().BeEmpty();
        BasicProgram program = parsed.Program ?? throw new AssertFailedException("The program has errors.");

        ((AtariBasicDialect)program.Dialect).Names.Should().Equal(((AtariBasicDialect)typed.Dialect).Names);
        program.Lines.Should().HaveCount(typed.Lines.Count);
        for (int index = 0; index < typed.Lines.Count; index++)
        {
            program.Lines[index].Number.Should().Be(typed.Lines[index].Number);
            program.Lines[index].Tokens.ToArray().Should().Equal(typed.Lines[index].Tokens.ToArray(), $"line {typed.Lines[index].Number}");
        }
    }

    /// <summary>
    ///  A line the ROM refuses is refused, at the place the ROM marks.
    /// </summary>
    /// <param name="line">The statements.</param>
    /// <param name="column">Where the error is.</param>
    [TestMethod]
    [DataRow("PRINT (1", 8)]
    [DataRow("FOR I=1 TO", 10)]
    [DataRow("A$=1", 3)]
    [DataRow("GOTO", 4)]
    public void RefusedLinesAreErrors(string line, int column)
    {
        Action tokenize = () => BasicDialect.AtariBasic.Tokenize(line);
        tokenize.Should().Throw<BasicSyntaxException>().Which.Column.Should().Be(column);
    }

    /// <summary>
    ///  The dialect lists a program as LIST does on the machine.
    /// </summary>
    [TestMethod]
    public void ListingIsTheRoms()
    {
        string[] lines =
        [
            "10 FOR I=1 TO 10 STEP 2:PRINT I;\",\";A$(1,1):NEXT I",
            "20 IF X>=2 AND NOT Y<>3 OR Z THEN 10",
            "30 X=1.5E-05:Y=0.05:Z=1E+10:? CHR$(65)",
            "40 PRINT (1"
        ];

        AtariMachine machine = Machine();
        AtariMachineTests.Type(machine, "DIM A$(9)\r");
        foreach (string line in lines) { AtariMachineTests.Type(machine, line + "\r"); }
        AtariMachineTests.Type(machine, "LIST\r");
        // The screen's rows past their two-column margin, run together, as a logical line spans them.
        string text = string.Concat(machine.ReadTextScreen().Select(row => row[2..]));
        BasicProgram typed = BasicProgram.Read(BasicDialect.AtariBasic, new AtariBasicMemory(machine));
        foreach (string listed in typed.ToText().Split('\n', StringSplitOptions.RemoveEmptyEntries))
        {
            // The screen shows the inverse space that marks an ERROR- line's error as a space.
            text.Should().Contain(listed.Replace("{$A0}", " ", StringComparison.Ordinal), "LIST prints it");
        }
    }

    /// <summary>
    ///  A program the dialect writes into memory runs, as one LOADed would.
    /// </summary>
    [TestMethod]
    public void WrittenProgramRuns()
    {
        AtariMachine machine = Machine();
        BasicProgram program = Program("10 DIM N$(5):N$=\"AB\"\n20 FOR I=1 TO 3:PRINT N$;I*7:NEXT I");

        program.Write(new AtariBasicMemory(machine));
        AtariMachineTests.Type(machine, "RUN\r");
        string[] screen = machine.ReadTextScreen();
        screen.Should().Contain(row => row.Trim() == "AB7");
        screen.Should().Contain(row => row.Trim() == "AB21");

        BasicVariables variables = new(BasicDialect.AtariBasic, new AtariBasicMemory(machine));
        BasicVariable i = variables.Find("I") ?? throw new AssertFailedException("I is not a variable.");
        BasicVariable n = variables.Find("N$") ?? throw new AssertFailedException("N$ is not a variable.");
        variables.Read(BasicVariableKind.Real, i.ValueAddress).Number.Should().Be(4);
        variables.Read(BasicVariableKind.String, n.ValueAddress).Text.Should().Equal("AB"u8.ToArray());
    }

    /// <summary>
    ///  A saved program's image reads back as the same program.
    /// </summary>
    [TestMethod]
    public void SavedImagesRoundTrip()
    {
        BasicProgram program = Program(string.Join('\n', s_program));
        BasicProgram read = BasicProgram.FromImage(BasicDialect.AtariBasic, program.ToImage());
        read.ToText().Should().Be(program.ToText());
        ((AtariBasicDialect)read.Dialect).Names.Should().Equal(((AtariBasicDialect)program.Dialect).Names);
    }

    /// <summary>
    ///  The debugger's expressions give what PRINT gives on the machine: the string comparisons above NOT and the
    ///  arithmetic, an array's missing second subscript, subscripts and arguments rounded, and DEG's degrees.
    /// </summary>
    /// <param name="expression">The expression.</param>
    [TestMethod]
    [DataRow("NOT A$=\"HI\"")]
    [DataRow("1+A$=\"HELLO\"")]
    [DataRow("-A$<\"Z\"")]
    [DataRow("A$(2,3)")]
    [DataRow("A$(5)")]
    [DataRow("B(2)")]
    [DataRow("B(0.6,1.4)")]
    [DataRow("PEEK(1.6)")]
    [DataRow("CHR$(321)")]
    [DataRow("SIN(90)")]
    [DataRow("ATN(-1)/ATN(-1)")]
    [DataRow("5/3")]
    [DataRow("--1")]
    [DataRow("NOT -1")]
    [DataRow("2*-.5")]
    [DataRow("1E50*1E40")]
    [DataRow("(-2)^3")]
    public void ExpressionsAreTheRoms(string expression)
    {
        AtariMachine machine = EvaluationMachine();
        BasicValue value = new BasicEvaluator(BasicDialect.AtariBasic, new AtariBasicMemory(machine))
            .Evaluate(expression).Value;

        string printed = Printed(machine, expression);
        string expected = value.Text is { } text
            ? new string([.. text.Select(character => (char)character)])
            : AtariBasicExpression.Format(value);

        expected.Should().Be(printed, $"PRINT {expression} prints it");
    }

    /// <summary>
    ///  The debugger's expressions refuse what BASIC refuses, with BASIC's error number.
    /// </summary>
    /// <param name="expression">The expression.</param>
    /// <param name="error">BASIC's error number.</param>
    [TestMethod]
    [DataRow("A$(3,2)", 5)]
    [DataRow("A$(6)", 5)]
    [DataRow("A$(0)", 5)]
    [DataRow("PEEK(-1)", 3)]
    [DataRow("CHR$(65536)", 3)]
    [DataRow("SQR(-1)", 3)]
    [DataRow("LOG(0)", 3)]
    [DataRow("B(4)", 9)]
    [DataRow("B(40000)", 9)]
    [DataRow("0^-1", 3)]
    [DataRow("(-8)^.5", 3)]
    [DataRow("1E50*1E50", 11)]
    public void ExpressionErrorsAreTheRoms(string expression, int error)
    {
        AtariMachine machine = EvaluationMachine();
        Action evaluate = () => new BasicEvaluator(BasicDialect.AtariBasic, new AtariBasicMemory(machine)).Evaluate(expression);

        evaluate.Should().Throw<FormatException>().Which.Message.Should().StartWith($"ERROR- {error}:");
        Printed(machine, expression).Should().MatchRegex($@"^ERROR-\s+{error}\b", $"PRINT {expression} is error {error}");
    }

    /// <summary>
    ///  Expressions with two unary operators are refused, as rev. C's grammar refuses them.
    /// </summary>
    /// <param name="expression">The expression.</param>
    [TestMethod]
    [DataRow("- -A")]
    [DataRow("- - 1")]
    [DataRow("NOT - 1")]
    [DataRow("NOT NOT 1")]
    public void SecondUnaryIsRefused(string expression)
    {
        AtariMachine machine = EvaluationMachine();
        Action evaluate = () => new BasicEvaluator(BasicDialect.AtariBasic, new AtariBasicMemory(machine)).Evaluate(expression);
        evaluate.Should().Throw<FormatException>();
        Printed(machine, expression).Should().StartWith("ERROR-", $"BASIC refuses PRINT {expression}");
    }

    // An 800 with strings, arrays and DEG set, for the expression tests.
    private static AtariMachine EvaluationMachine()
    {
        AtariMachine machine = Machine();
        AtariMachineTests.Type(machine, "DIM A$(9),B(3,2):A$=\"HELLO\":B(2,0)=7:B(1,1)=1.5:DEG\r");
        return machine;
    }

    // The first row PRINT writes for an expression typed on the machine; an error has an empty row before it.
    private static string Printed(AtariMachine machine, string expression)
    {
        AtariMachineTests.Type(machine, $"PRINT {expression}\r");
        string[] screen = machine.ReadTextScreen();
        int prompt = Array.FindLastIndex(screen, row => row.Trim() == $"PRINT {expression}");
        prompt.Should().BeGreaterThanOrEqualTo(0, "the statement is on the screen");
        return screen.Skip(prompt + 1).Select(row => row.Trim()).FirstOrDefault(row => row.Length > 0) ?? "";
    }

    /// <summary>
    ///  A line whose tokens would fill the 256-byte token buffer is refused, as WRITE_TOKEN refuses it, where one a
    ///  byte shorter is taken.
    /// </summary>
    [TestMethod]
    public void TokenBufferLimitIsTheRoms()
    {
        // Line header (3), statement header (2), then each ",1" adds a comma and a 7-byte constant; PRINT 1 starts it.
        static string Line(int ones) => "10 PRINT 1" + string.Concat(Enumerable.Repeat(",1", ones));

        int taken = Enumerable.Range(1, 40).Last(ones => Tokenizes(Line(ones)));
        Tokenizes(Line(taken + 1)).Should().BeFalse();

        AtariMachine machine = Machine();
        AtariMachineTests.Type(machine, Line(taken) + "\r");
        AtariMachineTests.Type(machine, Line(taken + 1).Replace("10 ", "20 ", StringComparison.Ordinal) + "\r");
        BasicProgram typed = BasicProgram.Read(BasicDialect.AtariBasic, new AtariBasicMemory(machine));
        typed.ToText().Should().Contain(Line(taken), "the ROM takes the longest line the dialect takes");
        typed.ToText().Should().NotContain("20 PRINT", "the ROM refuses the line the dialect refuses");
    }

    private static bool Tokenizes(string line) => BasicProgram.Parse(line, BasicDialect.AtariBasic).Program is not null;

    /// <summary>
    ///  Numbers read and print as the floating point package's AFP and FASC read and write them on the machine.
    /// </summary>
    [TestMethod]
    public void NumbersReadAndPrint()
    {
        string[] numbers = ["1", ".5", "0.05", "123456789012", "1E10", "2E-5", "-2E-5", "1000000000", "65535", "1.5E-5", "0"];
        AtariMachine machine = Machine();
        foreach (string text in numbers)
        {
            int at = 0;
            byte[] number = AtariNumbers.Parse([.. text.Select(character => (byte)character), AtariNumbers.EndOfLine], ref at)
                ?? throw new AssertFailedException($"{text} is not a number.");

            string formatted = AtariNumbers.Format(number);
            AtariNumbers.Format(AtariNumbers.FromDouble(AtariNumbers.ToDouble(number))).Should().Be(formatted);
            AtariMachineTests.Type(machine, $"PRINT {text}\r");
            string[] screen = machine.ReadTextScreen();
            int prompt = Array.FindLastIndex(screen, row => row.Trim() == $"PRINT {text}");
            screen[prompt + 1].Trim().Should().Be(formatted, $"BASIC prints {text} so");
        }
    }
}
