// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Basic;
using Retrocore.Debug;
using Retrocore.Machines.Apple1;

namespace Retrocore.Tests;

/// <summary>
///  Apple-1 BASIC, assembled from the SDK's source, running on the Apple-1: the prompt, immediate statements, a
///  program, LIST, errors, a key that stops a program, and loading BASIC from tape through the cassette interface.
/// </summary>
[TestClass]
public sealed class Apple1BasicTests
{
    private static byte[]? s_basic;

    /// <summary>
    ///  Gets Apple-1 BASIC assembled from the SDK's source, once.
    /// </summary>
    internal static byte[] Image => s_basic ??=
        Apple1RomTests.Image(Apple1SdkModules.AssembleBasic(Apple1SdkModules.BasicPath(Apple1RomTests.Source(""))));

    /// <summary>
    ///  E000R starts BASIC, which clears the program and shows its > prompt.
    /// </summary>
    [TestMethod]
    public void ColdStartShowsThePrompt()
    {
        Apple1Machine machine = Start();
        LastLine(machine).Should().Be(">");
        Word(machine, 0x4A).Should().Be(0x0800, "LOMEM");
        Word(machine, 0x4C).Should().Be(0x1000, "HIMEM");
        Word(machine, 0xCA).Should().Be(0x1000, "the program is empty");
    }

    /// <summary>
    ///  Statements typed without a line number run at once, one to a line: only a numbered line may hold several.
    /// </summary>
    [TestMethod]
    public void ImmediateStatementsRun()
    {
        Apple1Machine machine = Start();
        Type(machine, "PRINT 6*7, 100/7, -5 MOD 3");
        Output(machine).Should().Contain("42      14      -2");
        Type(machine, "A=3");
        Type(machine, "B=4");
        Type(machine, "PRINT A*A+B*B");
        Output(machine).Should().Contain("25");
        Type(machine, "A=3: B=4");
        Output(machine).Should().Contain("*** SYNTAX ERR");
    }

    /// <summary>
    ///  A program with FOR, GOSUB, strings and IF runs, and LIST shows it as BASIC prints it: a blank before a keyword
    ///  that starts with a letter.
    /// </summary>
    [TestMethod]
    public void ProgramRunsAndLists()
    {
        Apple1Machine machine = Start();
        string[] program =
        [
            "10 DIM A$(10)",
            "20 A$=\"HELLO\"",
            "30 FOR I=1 TO 3",
            "40 GOSUB 100",
            "50 NEXT I",
            "60 PRINT A$;LEN(A$)",
            "70 IF I>3 THEN PRINT \"DONE\"",
            "80 END",
            "100 PRINT I*I;",
            "110 RETURN"
        ];

        foreach (string line in program) { Type(machine, line); }
        Type(machine, "RUN");
        string output = Output(machine);
        output.Should().Contain("149");
        output.Should().Contain("HELLO5");
        output.Should().Contain("DONE");

        Type(machine, "LIST 60,80");
        Output(machine).Should().Contain(
            "   60 PRINT A$; LEN(A$)\n   70 IF I>3 THEN PRINT \"DONE\"\n   80 END");
    }

    /// <summary>
    ///  An error prints its message between *** and ERR; a running program's error names the line.
    /// </summary>
    [TestMethod]
    public void ErrorsAreReported()
    {
        Apple1Machine machine = Start();
        Type(machine, "PRINT 1/0");
        Output(machine).Should().Contain("*** >32767 ERR");
        Type(machine, "10 GOTO 20");
        Type(machine, "RUN");
        Output(machine).Should().Contain("*** BAD BRANCH ERR");
        Output(machine).Should().Contain("STOPPED AT 10");
        Type(machine, "PRINT (");
        Output(machine).Should().Contain("*** SYNTAX ERR");
    }

    /// <summary>
    ///  Any key typed while a program runs stops it, and running off the last line is an END error.
    /// </summary>
    [TestMethod]
    public void AKeyStopsAProgram()
    {
        Apple1Machine machine = Start();
        Type(machine, "10 GOTO 10");
        machine.Keyboard.Type("RUN\n");
        machine.Run(Apple1Timing.ClockHertz / 2);
        machine.Keyboard.Type(" ");
        RunUntilPrompt(machine);
        Output(machine).Should().Contain("STOPPED AT 10");

        Type(machine, "SCR");
        Type(machine, "10 A=1");
        Type(machine, "RUN");
        Output(machine).Should().Contain("*** END ERR");
    }

    /// <summary>
    ///  The debugger's arithmetic and arrays agree with the machine's: MOD is negative when the signs differ, and an
    ///  array counts from 1, as DIM A(3) makes A(1) to A(3).
    /// </summary>
    [TestMethod]
    public void DebuggerAgreesWithTheInterpreter()
    {
        Apple1Machine machine = Start();
        Type(machine, "PRINT 5 MOD -3;\" \";-5 MOD -3;\" \";-5 MOD 3;\" \";5 MOD 3");
        Output(machine).Should().Contain("-2 2 -2 2");
        Type(machine, "B=5");
        Type(machine, "DIM A(3)");
        Type(machine, "A(1)=11");
        Type(machine, "A(3)=33");
        Type(machine, "A(0)=1");
        Output(machine).Should().Contain("*** RANGE ERR", "Apple-1 BASIC has no A(0)");

        Apple1BasicMemory memory = new(machine);
        BasicEvaluator evaluator = new(BasicDialect.Apple1, memory);
        string Evaluate(string expression) => evaluator.Format(evaluator.Evaluate(expression));
        Evaluate("5 MOD -3").Should().Be("-2");
        Evaluate("-5 MOD -3").Should().Be("2");
        Evaluate("-5 MOD 3").Should().Be("-2");
        Evaluate("A(1)").Should().Be("11");
        Evaluate("A(3)").Should().Be("33");
        Evaluate("B(1)").Should().Be("5", "a simple variable is its own first element");
        FluentActions.Invoking(() => evaluator.Evaluate("A(0)")).Should().Throw<FormatException>().WithMessage("*** RANGE ERR*");

        BasicVariables variables = new(BasicDialect.Apple1, memory);
        BasicArray array = variables.FindArray("A") ?? throw new AssertFailedException("DIM A(3) makes an array.");

        array.LowerBound.Should().Be(1);
        array.Count.Should().Be(3);
        array.Subscripts(0).Should().Equal(1);
        variables.Write(array.Kind, array.ElementAddress([2]), new BasicValue(22));
        Type(machine, "PRINT A(2)");
        Output(machine).Should().Contain("22");
    }

    /// <summary>
    ///  BASIC loads from tape as it was sold: E000.EFFFR at the cassette interface's prompt, then E000R.
    /// </summary>
    [TestMethod]
    public void LoadsFromTape()
    {
        Apple1Machine machine = Apple1MachineTests.Boot();
        Apple1CassetteDrive drive = machine.CassetteDrive ?? throw new InvalidOperationException("No cassette interface.");
        drive.Play(Apple1Tape.FromData(Image), "basic");
        Apple1MachineTests.TypeLine(machine, "C100R");
        Apple1MachineTests.TypeLine(machine, "E000.EFFFR", seconds: 60);
        Enumerable.Range(0xE000, Image.Length).Select(at => machine.Bus.Peek((ushort)at)).Should().Equal(Image);
        machine.Keyboard.Type("E000R\n");
        RunUntilPrompt(machine);
        LastLine(machine).Should().Be(">");
    }

    /// <summary>
    ///  The dialect tokenizes each statement as Apple-1 BASIC stores it, and lists the stored line as its LIST does.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   The lines reach every statement, operator and function, with the several tokens a word can have.
    ///  </para>
    /// </remarks>
    [TestMethod]
    public void DialectMatchesTheInterpreter()
    {
        string[] lines =
        [
            "10 REM A REMARK, WITH: PUNCTUATION",
            "20 DIM A$(20),B(5),C$(3)",
            "30 A$=\"HI THERE\": B(2)=-7: C$=A$(1,2)",
            "40 INPUT A$: INPUT \"N\",N1,N2: INPUT X,Y",
            "50 FOR I=1 TO 10 STEP 2: NEXT I: FOR J=1 TO 2: NEXT J",
            "60 IF A#B THEN 100: IF A>=B THEN PRINT \"GE\";",
            "70 PRINT A$;A;: PRINT B(1), C$: PRINT",
            "80 X=PEEK(1)+RND(9)*SGN(-2)/ABS(3) MOD 4",
            "90 Y=NOT X AND (X OR 1)^2: Z=A$=C$: W=A$#C$",
            "100 GOSUB 200: GOTO 80: RETURN: END",
            "110 POKE 768,X: CALL -256: TAB 5",
            "120 LET Q=X<=Y: Q=X<>Y: Q=X<Y: Q=X>Y: Q=X=Y",
            "130 Q=LEN(A$)+USR(1): COLOR=3: PLOT 1,2",
            "140 HLIN 1,2 AT 3"
        ];

        Apple1Machine machine = Start();
        foreach (string line in lines)
        {
            Type(machine, line);
            Output(machine).Should().NotContain("ERR", "BASIC takes {0}", line);
        }

        BasicProgram stored = BasicProgram.Read(BasicDialect.Apple1, new Apple1BasicMemory(machine));
        stored.Lines.Select(line => line.Number).Should().Equal(lines.Select(line => int.Parse(line[..line.IndexOf(' ')])));
        for (int index = 0; index < lines.Length; index++)
        {
            string text = lines[index][(lines[index].IndexOf(' ') + 1)..];
            BasicDialect.Apple1.Tokenize(text).Should().Equal(stored.Lines[index].Tokens.ToArray(), text);
        }

        // LIST, a line at a time, against the stored lines detokenized.
        foreach (BasicLine line in stored.Lines)
        {
            string command = $"LIST {line.Number}";
            Type(machine, command);
            string[] screen = Lines(machine);
            int start = Array.LastIndexOf(screen, $">{command}") + 1;
            string listed = string.Concat(screen[start..].TakeWhile(text => text != ">"));
            string expected = $"{line.Number} {BasicDialect.Apple1.Detokenize(line.Tokens.Span)}";
            Squeeze(listed).Should().Be(Squeeze(expected), "LIST {0}", line.Number);
        }
    }

    // The words of a listed line without the spacing, which LIST pads and breaks at 32 columns.
    private static string Squeeze(string text) => string.Concat(text.Where(character => character != ' '));

    /// <summary>
    ///  Makes an Apple-1 with BASIC in its $E000 bank, starts it from the Monitor, and runs until the prompt.
    /// </summary>
    /// <returns>The machine.</returns>
    internal static Apple1Machine Start()
    {
        Apple1Machine machine = Apple1MachineTests.Boot();
        machine.Bus.Load(0xE000, Image);
        machine.Keyboard.Type("E000R\n");
        RunUntilPrompt(machine);
        return machine;
    }

    /// <summary>
    ///  Types a line and runs until BASIC waits for the next one.
    /// </summary>
    /// <param name="machine">The machine.</param>
    /// <param name="line">The line, without its Return.</param>
    internal static void Type(Apple1Machine machine, string line)
    {
        machine.Keyboard.Type(line + "\n");
        RunUntilPrompt(machine);
    }

    // Runs until the keys are taken and BASIC waits for a key at the > prompt, in RDKEY ($E003-$E00B).
    private static void RunUntilPrompt(Apple1Machine machine)
    {
        long limit = 10L * Apple1Timing.ClockHertz;
        for (long cycle = 0; ; cycle += Apple1Timing.CyclesPerLine)
        {
            cycle.Should().BeLessThan(limit, "BASIC should be back at its prompt within 10 seconds");
            machine.Run(Apple1Timing.CyclesPerLine);
            bool waiting = machine.Keyboard.Pending == 0
                && machine.Processor.Registers.ProgramCounter is >= 0xE003 and <= 0xE00B
                && machine.Bus.Peek(0xD9) < 0x80;

            if (waiting && LastLine(machine) == ">") { break; }
        }

        machine.Run(Apple1Timing.CyclesPerFrame * 2);
    }

    // The screen's lines, without trailing blanks.
    private static string[] Lines(Apple1Machine machine) =>
        [.. Enumerable.Range(0, Apple1Terminal.Rows).Select(row => machine.Terminal.Line(row).TrimEnd())];

    private static string LastLine(Apple1Machine machine) => Lines(machine).Last(line => line.Length > 0);

    // What the last typed line printed: the screen's text, joined with newlines.
    private static string Output(Apple1Machine machine) => string.Join("\n", Lines(machine));

    private static int Word(Apple1Machine machine, ushort address) =>
        machine.Bus.Peek(address) | (machine.Bus.Peek((ushort)(address + 1)) << 8);
}
