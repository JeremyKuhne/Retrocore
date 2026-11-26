// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Basic;
using Retrocore.Debug;
using Retrocore.Machines.Trs80;
using Retrocore.Media.Trs80;

namespace Retrocore.Tests;

/// <summary>
///  Level I BASIC's program, variables and statements, against lines typed into the SDK's Level I ROM.
/// </summary>
[TestClass]
public class Level1DialectTests
{
    private static readonly AssemblyResult s_rom = Trs80SdkModules.AssembleLevel1(
        Path.Join(AppContext.BaseDirectory, "Inputs", "Trs80", "Level1.asm"));

    /// <summary>
    ///  Typed lines read back as typed, abbreviations and spaces after the number kept, and the text form tokenizes
    ///  back to the bytes the ROM stored.
    /// </summary>
    [TestMethod]
    public void TypedLinesReadBackAsTheRomStoredThem()
    {
        Trs80Machine machine = Boot();
        string typed = "10 PRINT \"HI:THERE\";A: P. 2\n20 A=5\n5 REM A:B\n30 IF A=5 THEN 10\n";
        Type(machine, typed.Replace('\n', '\r'));
        DelegateBasicMemory memory = Memory(machine);

        BasicProgram program = BasicProgram.Read(BasicDialect.Level1, memory);
        program.ToText().Should().Be("5 REM A:B\n10 PRINT \"HI:THERE\";A: P. 2\n20 A=5\n30 IF A=5 THEN 10\n");
        program.Lines[0].Tokens.ToArray().Should().Equal(" REM A:B"u8.ToArray());

        int end = Word(memory, 0x406C);
        byte[] stored = [.. Enumerable.Range(0x4200, end - 0x4200).Select(address => machine.Bus.Peek((ushort)address))];
        BasicParseResult parsed = BasicProgram.Parse(program.ToText(), BasicDialect.Level1);
        (parsed.Program ?? throw new AssertFailedException("The program did not parse.")).ToImage().Should().Equal(stored);
    }

    /// <summary>
    ///  A program written into memory, lowercase made uppercase as the keyboard types it, runs as if typed.
    /// </summary>
    [TestMethod]
    public void AWrittenProgramRuns()
    {
        Trs80Machine machine = Boot();
        BasicProgram program = Found(BasicProgram.Parse("10 b=6\n20 p. b*7\n", BasicDialect.Level1).Program);
        program.Write(Memory(machine));
        Type(machine, "RUN\r");
        Run(machine, 1);
        Screen(machine).Should().Contain(" 42");
    }

    /// <summary>
    ///  A to Z, A(n) counting down from MEMTOP, and A$, read and written in Level I's formats.
    /// </summary>
    [TestMethod]
    public void VariablesReadAndWrite()
    {
        Trs80Machine machine = Boot();
        Type(machine, "A=1.5:B=-2:C=0:D=1E10:A(3)=7:A$=\"HELLO\"\r");
        Run(machine, 1);
        BasicVariables variables = new(BasicDialect.Level1, Memory(machine));

        Value(variables, "A").Should().Be(1.5);
        Value(variables, "B").Should().Be(-2);
        Value(variables, "C").Should().Be(0);
        Value(variables, "D").Should().BeApproximately(1E10, 1E4);
        BasicArray array = Found(variables.FindArray("A"));
        variables.Read(array.Kind, array.ElementAddress([3])).Number.Should().Be(7);
        BasicVariable text = Found(variables.Find("A$"));
        variables.Read(text.Kind, text.ValueAddress).Text.Should().Equal("HELLO"u8.ToArray());

        // What the ROM stored is what the debugger writes. C, zero, is left out: the ROM's zero keeps whatever mantissa
        // it had.
        foreach (string name in (string[])["A", "B", "D"])
        {
            BasicVariable variable = Found(variables.Find(name));
            byte[] bytes = [.. Enumerable.Range(variable.ValueAddress, 4).Select(address => machine.Bus.Peek((ushort)address))];
            Level1Numbers.Write(Value(variables, name)).Should().Equal(bytes);
        }

        variables.Write(BasicVariableKind.Real, Found(variables.Find("E")).ValueAddress, new(-0.25));
        variables.Write(BasicVariableKind.String, text.ValueAddress, BasicValue.Of("BYE"u8.ToArray()));
        Type(machine, "P. E;A$\r");
        Run(machine, 1);
        Screen(machine).Should().Contain("-.25 BYE");

        BasicEvaluator evaluator = new(BasicDialect.Level1, Memory(machine));
        evaluator.Format(evaluator.Evaluate("A*2+A(3)")).Should().Be("10");
        evaluator.Format(evaluator.Evaluate("INT(-A)")).Should().Be("-2");
        evaluator.Format(evaluator.Evaluate("A$")).Should().Be("\"BYE\"");
        evaluator.Format(evaluator.Evaluate("B<A")).Should().Be("1");
    }

    /// <summary>
    ///  The FOR loop running and the one it is inside, read from LOPVAR and the frame PUSHA left, at the start of a
    ///  statement as the ROM's ST_RUN_4 begins it.
    /// </summary>
    [TestMethod]
    public void LoopsComeFromLopvarAndTheStack()
    {
        Trs80Machine machine = Boot();
        Type(machine, "10 F. I=1 TO 5\r20 F. J=2 TO 9 S. 3\r30 X=1\r40 N. J\r50 N. I\rRUN\r");
        ushort statement = (ushort)s_rom.Symbols["ST_RUN_4"];
        DelegateBasicMemory memory = Memory(machine);
        for (int step = 0; step < 10_000_000; step++)
        {
            machine.StepCycle();
            if (machine.Processor.IsInstructionBoundary
                && machine.Processor.Registers.PC == statement
                && Level1Dialect.LineAddress(memory) is >= 0x4200 and var line
                && Word(memory, line) == 30)
            {
                break;
            }
        }

        machine.Processor.Registers.PC.Should().Be(statement);
        BasicVariables variables = new(BasicDialect.Level1, memory);
        IReadOnlyList<BasicLoop> loops = variables.Loops(machine.Processor.Registers.SP, 0, 0);
        loops.Select(loop => (loop.VariableAddress, loop.Step, loop.Limit, loop.Line)).Should().Equal(
            (0x4000 + (('J' - 'A') * 4), 3.0, 9.0, 20),
            (0x4000 + (('I' - 'A') * 4), 1.0, 5.0, 10));
    }

    /// <summary>
    ///  The analysis finds statements, abbreviated words and line references as EXEC would, and each statement's
    ///  offset in the stored line; REM and DATA run to the line's end.
    /// </summary>
    [TestMethod]
    public void StatementsAndReferences()
    {
        BasicSource source = BasicSource.Analyze("10 P. \"A:B\": G. 30\n20 IF A=1 T. 10\n30 DATA 1:2\n", BasicDialect.Level1);
        source.NumberedLines[0].Statements.Select(statement => statement.Offset).Should().Equal(0, 10);
        source.NumberedLines[2].Statements.Should().HaveCount(1);
        source.Sites.Where(site => site.Kind == BasicSiteKind.LineReference).Select(site => site.Number).Should().Equal(30, 10);
        string[] words = [.. source.Sites.Where(site => site.Kind == BasicSiteKind.Keyword).Select(site => site.Word)];
        words.Should().Equal("PRINT", "GOTO", "IF", "THEN", "DATA");
        source.Diagnostics.Should().BeEmpty();

        Level1Dialect.StatementOffsets(" P. 1: G. 30"u8).Should().Equal(0, 6);
        Level1Dialect.StatementOffsets(" REM A:B"u8).Should().Equal(0);
    }

    /// <summary>
    ///  Level I's CSAVE recording reads back as its program, and a program written as a tape reads back the same; a
    ///  block that does not start at $4200 is memory, not a program.
    /// </summary>
    [TestMethod]
    public void TapesHoldTheProgramFrom4200()
    {
        Trs80Machine machine = Boot();
        Type(machine, "10 P. \"TAPE\"\r20 GOTO 10\r");
        CassetteImage tape = new();
        machine.Bus.Cassette.Record(tape);
        Type(machine, "CSAVE\r");
        for (int step = 0; step < 6000 && !machine.Bus.Cassette.MotorOn; step++) { Run(machine, 0.01); }
        for (int step = 0; step < 6000 && machine.Bus.Cassette.MotorOn; step++) { Run(machine, 0.01); }
        machine.Bus.Cassette.Stop();

        BasicProgram recorded = BasicTape.Read([.. tape.Bytes], out char name);
        (recorded.Dialect, name).Should().Be((BasicDialect.Level1, ' '));
        recorded.ToText().Should().Be("10 P. \"TAPE\"\n20 GOTO 10\n");
        BasicTape.Read(BasicTape.Write(recorded, 'A'), out _).ToText().Should().Be(recorded.ToText());

        // A block from $41FE, whose first two bytes replace CLOAD's return address, as a machine-code tape's do.
        byte[] code = [0x00, 0x42, 0xC3, 0x00, 0x42];
        byte checksum = (byte)-code.Sum(value => value);
        byte[] memory = [.. new byte[128], 0xA5, 0x41, 0xFE, 0x42, 0x03, .. code, checksum];
        FluentActions.Invoking(() => BasicTape.Read(memory, out _)).Should().Throw<InvalidDataException>()
            .WithMessage("This Level I tape loads $41FE-$4202, not a BASIC program from $4200*");
    }

    /// <summary>
    ///  The debugger writes numbers as the ROM's PRINT does, E notation below 0.1 and from a million up.
    /// </summary>
    [TestMethod]
    public void NumbersPrintAsTheRomPrintsThem()
    {
        Trs80Machine machine = Boot();
        double[] values = [0.05, 0.5, 0.1, 0.0999, 123.5, -7, 0.001234, 1234567];
        string typed = string.Join(";", values.Select(value => value.ToString("R", System.Globalization.CultureInfo.InvariantCulture)));
        Type(machine, "CLS\r");
        Type(machine, $"P. {typed}\r");
        Run(machine, 1);
        string printed = Screen(machine);
        foreach (double value in values)
        {
            printed.Should().Contain($" {Level1Numbers.Format(value)} ", $"the ROM prints {value} so");
        }

        // A statement after IF's condition, without THEN, has its own words, and a REM or DATA there skips the rest.
        BasicSource source = BasicSource.Analyze("10 IF A FOR I=1 TO 5\n20 IF A REM RND(1)\n", BasicDialect.Level1);
        string[] words = [.. source.Sites.Where(site => site.Kind == BasicSiteKind.Keyword).Select(site => site.Word)];
        words.Should().Equal("IF", "FOR", "TO", "IF", "REM");
    }

    /// <summary>
    ///  Level I numbers: a fraction from 0.5 up to 1 times a power of two, the sign over the exponent.
    /// </summary>
    [TestMethod]
    public void NumbersRoundTrip()
    {
        Level1Numbers.Write(1).Should().Equal(0x00, 0x00, 0x80, 0x00);
        Level1Numbers.Write(0).Should().Equal(0x00, 0x00, 0x00, 0x40);
        foreach (double value in (double[])[1, -1, 0.5, 3, 1000, -0.125, 32767, 1E-20, 1E30])
        {
            Level1Numbers.Read(Level1Numbers.Write(value)).Should().BeApproximately(value, Math.Abs(value) * 1E-7);
        }
    }

    // A Model I with 16K running the SDK's Level I ROM, booted to READY.
    private static Trs80Machine Boot()
    {
        string roms = Path.Join(AppContext.BaseDirectory, "Inputs", "Trs80");
        byte[] characters = Trs80SdkModules.AssembleCharacterGenerator(Path.Join(roms, "CharacterGenerator.asm"))
            .Sections[0].Bytes.ToArray();

        Trs80Machine machine = new(
            new Trs80Configuration { Rom = Trs80Rom.Level1, RamKilobytes = 16, ExpansionInterface = false },
            new Trs80Roms(s_rom.Sections[0].Bytes.ToArray(), characters));

        Run(machine, 2);
        Screen(machine).Should().Contain("READY");
        return machine;
    }

    private static DelegateBasicMemory Memory(Trs80Machine machine) =>
        new(address => machine.Bus.Peek((ushort)address), (address, value) => machine.Bus.Write((ushort)address, value));

    private static double Value(BasicVariables variables, string name)
    {
        BasicVariable variable = Found(variables.Find(name));
        return variables.Read(variable.Kind, variable.ValueAddress).Number;
    }

    private static T Found<T>(T? value) where T : class => value ?? throw new AssertFailedException("It was not found.");

    private static int Word(DelegateBasicMemory memory, int address) => memory.Read(address) | (memory.Read(address + 1) << 8);

    private static void Run(Trs80Machine machine, double seconds) => machine.Run((ulong)(Trs80Timing.ClockHertz * seconds));

    // Types each character, running until the keyboard has pressed and released it.
    private static void Type(Trs80Machine machine, string text)
    {
        foreach (char character in text) { machine.Bus.Keyboard.Type((byte)character); }
        while (machine.Bus.Keyboard.IsTyping) { machine.Run(1000); }
        Run(machine, 0.2);
    }

    private static string Screen(Trs80Machine machine)
    {
        char[] screen = new char[Trs80Video.Columns * Trs80Video.Rows];
        for (int index = 0; index < screen.Length; index++)
        {
            byte code = machine.Bus.Video.Read(index);
            screen[index] = code is >= 0x20 and < 0x80 ? (char)code : ' ';
        }

        return new(screen);
    }
}
