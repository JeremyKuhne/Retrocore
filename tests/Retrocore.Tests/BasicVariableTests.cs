// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text;
using Retrocore.Assembler;
using Retrocore.Basic;
using Retrocore.Machines.Apple2;
using Retrocore.Machines.Trs80;

namespace Retrocore.Tests;

/// <summary>
///  Runs programs on the SDK's ROMs and checks the library reads the variables, arrays, strings and FOR loops BASIC
///  made, writes values as BASIC stores them, evaluates expressions, and formats numbers as PRINT does.
/// </summary>
[TestClass]
public sealed class BasicVariableTests
{
    private static readonly string[] s_appleSoft =
    [
        "10 A=1.5:B%=-3:C$=\"HI\":D=-.25:G=2.75:H=1E10:J=1/3",
        "20 DIM E(2,3):E(1,2)=7:E(2,0)=9:DIM F$(2):F$(1)=\"X\"",
        "30 FOR I=1 TO 10 STEP 2",
        "40 GOSUB 100",
        "50 NEXT",
        "100 PRINT J;\" \";H;\" \";.001;\" \";123456789;\" \";-.5",
        "110 STOP"
    ];

    private static readonly string[] s_level2 =
    [
        "10 A=1.5:B%=-3:C$=\"HI\":D=-.25:G=2.75:H=1E10:J=1/3:K#=1#/3",
        "20 DIM E(2,3):E(1,2)=7:E(2,0)=9:DIM F$(2):F$(1)=\"X\"",
        "30 FOR I=1 TO 10 STEP 2",
        "35 FOR N%=5 TO 1 STEP -1",
        "40 GOSUB 100",
        "50 NEXT:NEXT",
        "100 PRINT J;H;.001;123456789;-.5;K#",
        "110 STOP"
    ];

    /// <summary>
    ///  AppleSoft's variables, arrays, loops and number formats, read and written as the ROM keeps them.
    /// </summary>
    [TestMethod]
    public void AppleSoftVariablesMatchTheRom()
    {
        Apple2Machine machine = BasicMachines.BootIIe(Apple2Model.IIeEnhanced);
        foreach (string line in s_appleSoft) { BasicMachines.TypeLine(machine, line); }
        ushort gone = (ushort)BasicMachines.AppleSoft(Apple2Model.IIeEnhanced).Symbols["GONE"];
        DelegateBasicMemory memory = new(
            address => machine.Bus.Peek((ushort)address),
            (address, value) => machine.Bus.Write((ushort)address, value));

        machine.Bus.QueueKey((byte)'R');
        machine.Bus.QueueKey((byte)'U');
        machine.Bus.QueueKey((byte)'N');
        machine.Bus.QueueKey(13);
        RunTo(() => machine.Processor.Registers.ProgramCounter == gone && Word(memory, 0x75) == 100, machine.StepInstruction);

        BasicVariables variables = new(BasicDialect.AppleSoft, memory);
        int stack = 0x100 + machine.Processor.Registers.StackPointer + 1;
        Check(variables, memory, BasicDialect.AppleSoft, stack, forSize: 18, gosubSize: 7);

        // Run to STOP: the PRINT line is on the screen, as Format writes each number.
        RunTo(() => machine.Processor.Registers.ProgramCounter == gone && Word(memory, 0x75) == 110, machine.StepInstruction);
        string[] expected = [Format(BasicDialect.AppleSoft, 1.0 / 3), "1E+10", "1E-03", "123456789", "-.5"];
        AppleSoftScreen(memory).Should().Contain(string.Join(" ", expected));
    }

    /// <summary>
    ///  Level II's variables, arrays, loops, including an integer one, and number formats, single and double.
    /// </summary>
    /// <param name="revision">The Level II revision.</param>
    [TestMethod]
    [DataRow(12)]
    [DataRow(13)]
    public void Level2VariablesMatchTheRom(int revision)
    {
        AssemblyResult rom = BasicMachines.Level2(revision);
        Trs80Machine machine = BasicMachines.BootLevel2(rom);
        foreach (string line in s_level2) { BasicMachines.Type(machine, line + "\r"); }
        ushort gone = (ushort)rom.Symbols["GONE"];
        DelegateBasicMemory memory = new(
            address => machine.Bus.Peek((ushort)address),
            (address, value) => machine.Bus.Write((ushort)address, value));

        foreach (char character in "RUN\r") { machine.Bus.Keyboard.Type((byte)character); }
        RunTo(() => machine.Processor.Registers.PC == gone && Word(memory, 0x40A2) == 100, machine.StepInstruction);

        BasicVariables variables = new(BasicDialect.Level2, memory);
        Check(variables, memory, BasicDialect.Level2, Word(memory, 0x40E8), forSize: 17, gosubSize: 5);
        IReadOnlyList<BasicLoop> loops = variables.Loops(Word(memory, 0x40E8), 17, 5);
        loops[0].Should().Be(new BasicLoop(variables.Find("N%")?.ValueAddress ?? -1, -1, 1, 35), "the integer loop");
        double third = variables.Read(BasicVariableKind.Double, variables.Find("K#")?.ValueAddress ?? 0).Number;
        third.Should().BeApproximately(1.0 / 3, 1e-15);

        RunTo(() => machine.Processor.Registers.PC == gone && Word(memory, 0x40A2) == 110, machine.StepInstruction);
        string screen = Level2Screen(machine);
        string[] printed =
        [
            Format(BasicDialect.Level2, 1.0 / 3),
            "1E+10",
            "1E-03",
            BasicNumbers.Format(123456789, 16),
            "-.5",
            BasicNumbers.Format(1.0 / 3, 16)
        ];

        screen.Split(' ', StringSplitOptions.RemoveEmptyEntries).Should().ContainInConsecutiveOrder(printed, "the screen is {0}", screen);
    }

    /// <summary>
    ///  Level II and Color BASIC take true as -1, and AND, OR and NOT bit by bit; AppleSoft takes true as 1 and them
    ///  as logic.
    /// </summary>
    /// <param name="name">The dialect.</param>
    /// <param name="equal">What 1=1 gives.</param>
    /// <param name="and">What 2 AND 1 gives.</param>
    /// <param name="not">What NOT 0 gives.</param>
    [TestMethod]
    [DataRow("applesoft", "1", "1", "1")]
    [DataRow("level2", "-1", "0", "-1")]
    [DataRow("colorbasic", "-1", "0", "-1")]
    public void TruthFollowsTheDialect(string name, string equal, string and, string not)
    {
        BasicDialect dialect = BasicDialect.FromName(name) ?? throw new AssertFailedException(name);
        BasicEvaluator evaluator = new(dialect, DelegateBasicMemory.Of(new byte[0x10000]));
        evaluator.Format(evaluator.Evaluate("1=1")).Should().Be(equal);
        evaluator.Format(evaluator.Evaluate("2 AND 1")).Should().Be(and);
        evaluator.Format(evaluator.Evaluate("NOT 0")).Should().Be(not);
    }

    // The checks both dialects share, at line 100 in the first pass of the FOR loop.
    private static void Check(
        BasicVariables variables,
        DelegateBasicMemory memory,
        BasicDialect dialect,
        int stack,
        int forSize,
        int gosubSize)
    {
        variables.Simple().Select(variable => variable.Name).Should().Contain(["A", "B%", "C$", "D", "G", "H", "J", "I"]);
        Value(variables, "A").Should().Be(1.5);
        Value(variables, "B%").Should().Be(-3);
        Value(variables, "D").Should().Be(-0.25);
        Value(variables, "I").Should().Be(1);
        Text(variables, "C$").Should().Be("HI");

        BasicArray array = variables.FindArray("E") ?? throw new AssertFailedException(Arrays(variables));
        array.Dimensions.Should().Equal(3, 4);
        variables.Read(array.Kind, array.ElementAddress([1, 2])).Number.Should().Be(7);
        variables.Read(array.Kind, array.ElementAddress([2, 0])).Number.Should().Be(9);
        BasicArray strings = variables.FindArray("F$") ?? throw new AssertFailedException("F$");
        Encoding.ASCII.GetString(variables.Read(strings.Kind, strings.ElementAddress([1])).Text ?? []).Should().Be("X");

        BasicLoop loop = variables.Loops(stack, forSize, gosubSize)[^1];
        loop.Should().Be(new BasicLoop(variables.Find("I")?.ValueAddress ?? -1, 2, 10, 30));

        // The evaluator reads what PRINT would.
        BasicEvaluator evaluator = new(dialect, memory);
        evaluator.Format(evaluator.Evaluate("A*2+B%")).Should().Be("0");
        evaluator.Format(evaluator.Evaluate("C$+\"!\"")).Should().Be("\"HI!\"");
        evaluator.Format(evaluator.Evaluate("E(1,2)+LEN(C$)")).Should().Be("9");
        evaluator.Format(evaluator.Evaluate("SCORE")).Should().Be("0", "a bare name is a variable, here not made yet");
        BasicEvaluator.IsTrue(evaluator.Evaluate("A>1 AND B%<0")).Should().BeTrue();
        evaluator.Format(evaluator.Evaluate("NOT 0")).Should().Be(dialect == BasicDialect.Level2 ? "-1" : "1");
        FluentActions.Invoking(() => evaluator.Evaluate("RND(1)")).Should().Throw<FormatException>();

        // A value written is stored as BASIC stores the same value; a string goes into string space.
        BasicVariable a = variables.Find("A") ?? throw new AssertFailedException("A");
        BasicVariable g = variables.Find("G") ?? throw new AssertFailedException("G");
        variables.Write(a.Kind, a.ValueAddress, new(2.75));
        int size = variables.ValueSize(a.Kind);
        Bytes(memory, a.ValueAddress, size).Should().Equal(Bytes(memory, g.ValueAddress, size));
        BasicVariable c = variables.Find("C$") ?? throw new AssertFailedException("C$");
        variables.Write(c.Kind, c.ValueAddress, BasicValue.Of("HELLO"u8.ToArray()));
        Text(variables, "C$").Should().Be("HELLO");

        // A new variable moves the arrays up, which still read.
        variables.Create("Z9");
        variables.Find("Z9").Should().NotBeNull();
        BasicArray moved = variables.FindArray("E") ?? throw new AssertFailedException("E");
        variables.Read(moved.Kind, moved.ElementAddress([1, 2])).Number.Should().Be(7);
        variables.Write(a.Kind, a.ValueAddress, new(1.5));
    }

    // The arrays found, for a failure's message.
    private static string Arrays(BasicVariables variables) =>
        string.Join(", ", variables.Arrays().Select(found => $"{found.Name} {found.Kind} {string.Join("x", found.Dimensions)}"));

    private static double Value(BasicVariables variables, string name)
    {
        BasicVariable variable = variables.Find(name) ?? throw new AssertFailedException(name);
        return variables.Read(variable.Kind, variable.ValueAddress).Number;
    }

    private static string Text(BasicVariables variables, string name)
    {
        BasicVariable variable = variables.Find(name) ?? throw new AssertFailedException(name);
        return Encoding.ASCII.GetString(variables.Read(variable.Kind, variable.ValueAddress).Text ?? []);
    }

    private static byte[] Bytes(DelegateBasicMemory memory, int address, int count) =>
        [.. Enumerable.Range(address, count).Select(memory.Read)];

    private static string Format(BasicDialect dialect, double value) =>
        BasicNumbers.Format(value, dialect == BasicDialect.Level2 ? 6 : 9);

    private static int Word(DelegateBasicMemory memory, int address) =>
        memory.Read(address) | (memory.Read(address + 1) << 8);

    private static void RunTo(Func<bool> reached, Func<int, ProcessorExecutionResult> step)
    {
        for (int count = 0; count < 20_000_000 && !reached(); count++) { step(64); }
        reached().Should().BeTrue("the program got there");
    }

    // The IIe's 40-column text page, row by row.
    private static string AppleSoftScreen(DelegateBasicMemory memory)
    {
        char[] text = new char[24 * 41];
        for (int row = 0; row < 24; row++)
        {
            int start = 0x400 + (128 * (row % 8)) + (40 * (row / 8));
            for (int column = 0; column < 40; column++)
            {
                text[(row * 41) + column] = (char)(memory.Read(start + column) & 0x7F);
            }

            text[(row * 41) + 40] = '\n';
        }

        return new(text);
    }

    private static string Level2Screen(Trs80Machine machine)
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
