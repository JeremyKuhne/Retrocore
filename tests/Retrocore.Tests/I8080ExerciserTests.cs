// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text;
using Retrocore.Cpu.I8080;

namespace Retrocore.Tests;

/// <summary>
///  The classic 8080 CP/M test programs, run on the core under a minimal CP/M: Microcosm Associates' TST8080,
///  8080PRE, SuperSoft Associates' CPUTEST, and 8080EXM, Frank D. Cringle's instruction exerciser as Ian
///  Bartholomew ported it to the 8080, which compares a CRC of thousands of results, every flag bit included,
///  against a real 8080's.
/// </summary>
/// <remarks>
///  <para>
///   8080EXM's table of 25 independent tests is rewritten in memory to hold just one, so each runs as a test case
///   of its own and they run in parallel; the pinned files are never changed. The 8085 runs the programs that test
///   by conditional jumps; 8080EXM's CRCs include the flag bits where the 8085 keeps V and K.
///  </para>
/// </remarks>
[TestClass]
public class I8080ExerciserTests
{
    /// <summary>
    ///  The pinned revision of superzazu/8080, which collects the programs.
    /// </summary>
    internal const string Pin = "274ffd700b81baabea99b0963bc1260b67132185";

    /// <summary>
    ///  The number of tests in 8080EXM's table, at the pinned revision.
    /// </summary>
    internal const int TestCount = 25;

    // BDOS lives at the top of the program's memory; its entry outputs to this port, then returns.
    private const ushort Bdos = 0xF000;
    private const byte BdosPort = 0x00;

    // 8080EXM's table of test descriptor addresses, ending in a zero word.
    private const ushort TestTable = 0x013A;

    // The states Run takes between checks for the final HLT.
    private const ulong Chunk = 4096;

    /// <summary>
    ///  Gets the index of every test in 8080EXM's table.
    /// </summary>
    public static IEnumerable<object[]> Tests => Enumerable.Range(0, TestCount).Select(test => new object[] { test });

    /// <summary>
    ///  An 8080EXM test reports PASS: its CRC over the results, every flag bit included, matches a real 8080's.
    /// </summary>
    /// <param name="test">The test's index in the program's table.</param>
    [TestMethod]
    [TestCategory("Conformance")]
    [DynamicData(nameof(Tests))]
    public void Exm8080TestPasses(int test)
    {
        string output = Run(SelectTest(Program("8080EXM.COM"), test), I8080Variant.I8080, out ulong cycles);
        Console.WriteLine(output);
        Console.WriteLine($"{cycles:N0} states, to the next {Chunk:N0}.");
        output.Should().Contain("Tests complete");
        output.Should().Contain("PASS!", "the test's CRC matches a real 8080's");
        output.Should().NotContain("ERROR");
    }

    /// <summary>
    ///  TST8080 reports the CPU operational.
    /// </summary>
    /// <param name="variant">The CPU.</param>
    [TestMethod]
    [TestCategory("Conformance")]
    [DataRow(I8080Variant.I8080)]
    [DataRow(I8080Variant.I8085)]
    public void Tst8080Passes(I8080Variant variant)
    {
        string output = Run(Program("TST8080.COM"), variant, out _);
        output.Should().Contain("CPU IS OPERATIONAL", output);
    }

    /// <summary>
    ///  8080PRE, the preliminary checks 8080EXM relies on, completes.
    /// </summary>
    /// <param name="variant">The CPU.</param>
    [TestMethod]
    [TestCategory("Conformance")]
    [DataRow(I8080Variant.I8080)]
    [DataRow(I8080Variant.I8085)]
    public void Pre8080Passes(I8080Variant variant)
    {
        string output = Run(Program("8080PRE.COM"), variant, out _);
        output.Should().Contain("8080 Preliminary tests complete", output);
    }

    /// <summary>
    ///  SuperSoft's CPUTEST reports the CPU tests OK.
    /// </summary>
    [TestMethod]
    [TestCategory("Conformance")]
    public void CpuTestPasses()
    {
        string output = Run(Program("CPUTEST.COM"), I8080Variant.I8080, out _);
        output.Should().Contain("CPU TESTS OK", output);
    }

    /// <summary>
    ///  Copies 8080EXM with its test table cut down to one test.
    /// </summary>
    /// <param name="program">The program, as loaded at <c>$0100</c>.</param>
    /// <param name="test">The test's index in the table.</param>
    /// <returns>The program that runs only that test.</returns>
    internal static byte[] SelectTest(byte[] program, int test)
    {
        ArgumentOutOfRangeException.ThrowIfNegative(test);
        ArgumentOutOfRangeException.ThrowIfGreaterThanOrEqual(test, TestCount);
        const int Table = TestTable - 0x0100;
        byte[] selected = [.. program];
        (program[Table + (TestCount * 2)] | program[Table + (TestCount * 2) + 1]).Should().Be(0, "the table ends here");
        int entry = Table + (test * 2);
        selected[Table] = program[entry];
        selected[Table + 1] = program[entry + 1];
        selected[Table + 2] = 0;
        selected[Table + 3] = 0;
        return selected;
    }

    /// <summary>
    ///  Runs a CP/M program until it returns to the warm boot at 0, collecting its console output.
    /// </summary>
    /// <param name="program">The program, loaded at <c>$0100</c>.</param>
    /// <param name="variant">The CPU.</param>
    /// <param name="cycles">The states it ran, rounded up to a whole chunk.</param>
    /// <returns>The console output.</returns>
    internal static string Run(byte[] program, I8080Variant variant, out ulong cycles)
    {
        Z80TestBus bus = new();
        program.CopyTo(bus.Memory, 0x0100);

        // $0000: HLT ends the run at the warm boot. $0005: JMP BDOS, whose address the program reads as its memory
        // top. BDOS: OUT 0, then RET.
        bus.Memory[0x0000] = 0x76;
        bus.Memory[0x0005] = 0xC3;
        bus.Memory[0x0006] = Bdos & 0xFF;
        bus.Memory[0x0007] = Bdos >> 8;
        bus.Memory[Bdos] = 0xD3;
        bus.Memory[Bdos + 1] = BdosPort;
        bus.Memory[Bdos + 2] = 0xC9;

        I8080Processor<Z80TestBus> cpu = new(bus, variant);
        cpu.Registers = cpu.Registers with { PC = 0x0100, SP = Bdos };
        StringBuilder console = new();
        bus.OutputHandler = (port, _) =>
        {
            if ((byte)port != BdosPort) { return; }
            I8080Registers registers = cpu.Registers;
            if (registers.C == 2)
            {
                console.Append((char)registers.E);
            }
            else if (registers.C == 9)
            {
                for (int address = registers.DE; bus.Memory[address] != '$'; address++)
                {
                    console.Append((char)bus.Memory[address]);
                }
            }
        };

        while (!cpu.IsHalted) { cpu.Run(Chunk); }
        cycles = cpu.CycleCount;
        return console.ToString();
    }

    private static byte[] Program(string name)
    {
        if (!File.Exists(Path.Join(ExternalTestData.Cache, Pin, "manifest.json")))
        {
            Assert.Inconclusive("8080 test programs are missing. Run tools\\Fetch-I8080Tests.ps1 with PowerShell 7.");
        }

        return ExternalTestData.Read(Pin, $"cpu_tests/{name}");
    }
}
