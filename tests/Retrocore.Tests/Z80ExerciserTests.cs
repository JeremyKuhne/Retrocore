// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text;
using Retrocore.Cpu.Z80;

namespace Retrocore.Tests;

/// <summary>
///  ZEXALL and ZEXDOC, Frank D. Cringle's instruction exercisers, run on the core under a minimal CP/M: each
///  compares a CRC of thousands of instruction results against a real Z80's.
/// </summary>
/// <remarks>
///  <para>
///   Each program is a driver and a table of 67 independent tests, each with its own expected CRC, so every test
///   runs as a test case of its own and they run in parallel. The table is rewritten in memory to hold just one
///   test; the pinned files are never changed. The tests are uneven: <c>aluop a,&lt;b,c,d,e,h,l,(hl),a&gt;</c>
///   alone is 20 of the 46.7 billion T-states, so it sets the wall time.
///  </para>
/// </remarks>
[TestClass]
public class Z80ExerciserTests
{
    /// <summary>
    ///  The number of tests in each program's table, at the pinned revision.
    /// </summary>
    internal const int TestCount = 67;

    // BDOS lives at the top of the program's memory; its entry outputs to this port, then returns.
    private const ushort Bdos = 0xF000;
    private const byte BdosPort = 0x00;

    // The table of test descriptor addresses, ending in a zero word; the driver runs each in turn.
    private const ushort TestTable = 0x013A;

    // The T-states Run takes between checks for the final HALT.
    private const ulong Chunk = 4096;

    // The most T-states a program may run before the test fails rather than hang: 2.5 times aluop's 20 billion, the
    // longest test, and deterministic, since it counts emulated T-states.
    private const ulong Budget = 50_000_000_000;

    private const string ZexdocSkipped = "ZEXDOC is optional: ZEXALL checks the same instructions with every flag. "
        + "Set RETROCORE_ZEXDOC=1 to run it, such as to tell whether a ZEXALL failure is only in the undocumented flags.";

    /// <summary>
    ///  Gets the index of every test in a program's table.
    /// </summary>
    public static IEnumerable<object[]> Tests => Enumerable.Range(0, TestCount).Select(test => new object[] { test });

    /// <summary>
    ///  A ZEXALL test reports OK: its CRC over the results, every flag included, matches a real Z80's.
    /// </summary>
    /// <param name="test">The test's index in the program's table.</param>
    [TestMethod]
    [TestCategory("Conformance")]
    [DynamicData(nameof(Tests))]
    public void ZexallTestPasses(int test) => Exercise("zexall.com", test);

    /// <summary>
    ///  A ZEXDOC test reports OK: its CRC over the results, the undocumented flags masked, matches a real Z80's.
    ///  Optional: set <c>RETROCORE_ZEXDOC</c> to run it.
    /// </summary>
    /// <param name="test">The test's index in the program's table.</param>
    /// <remarks>
    ///  <para>
    ///   ZEXDOC runs the same instructions as ZEXALL, with the same operands, and masks only the undocumented X
    ///   and Y flags out of its CRC, so a core that passes ZEXALL passes ZEXDOC. Running both doubles the suite's
    ///   heaviest work, 46.7 billion T-states each, for no extra coverage. ZEXDOC earns its keep when ZEXALL
    ///   fails: if ZEXDOC still passes, the fault is only in the undocumented flags.
    ///  </para>
    /// </remarks>
    [TestMethod]
    [TestCategory("Conformance")]
    [DynamicData(nameof(Tests))]
    public void ZexdocTestPasses(int test)
    {
        if (Environment.GetEnvironmentVariable("RETROCORE_ZEXDOC") is null)
        {
            Assert.Inconclusive(ZexdocSkipped);
        }

        Exercise("zexdoc.com", test);
    }

    /// <summary>
    ///  Copies a ZEX program with its test table cut down to one test.
    /// </summary>
    /// <param name="program">The program, as loaded at <c>$0100</c>.</param>
    /// <param name="test">The test's index in the table.</param>
    /// <returns>The program that runs only that test.</returns>
    internal static byte[] SelectTest(byte[] program, int test)
    {
        ArgumentOutOfRangeException.ThrowIfNegative(test);
        ArgumentOutOfRangeException.ThrowIfGreaterThanOrEqual(test, TestCount);
        const int Table = TestTable - 0x0100;

        // The pinned table holds exactly TestCount addresses and its zero word, at a fixed place.
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
    /// <param name="cycles">The T-states it ran, rounded up to a whole chunk.</param>
    /// <returns>The console output.</returns>
    internal static string Run(byte[] program, out ulong cycles)
    {
        Z80TestBus bus = new();
        program.CopyTo(bus.Memory, 0x0100);

        // $0000: HALT ends the run at the warm boot. $0005: JP BDOS, whose address the program reads as its
        // memory top. BDOS: OUT [0],A, then RET.
        bus.Memory[0x0000] = 0x76;
        bus.Memory[0x0005] = 0xC3;
        bus.Memory[0x0006] = Bdos & 0xFF;
        bus.Memory[0x0007] = Bdos >> 8;
        bus.Memory[Bdos] = 0xD3;
        bus.Memory[Bdos + 1] = BdosPort;
        bus.Memory[Bdos + 2] = 0xC9;

        Z80Processor<Z80TestBus> cpu = new(bus);
        cpu.Registers = cpu.Registers with { PC = 0x0100, SP = Bdos };
        StringBuilder console = new();
        bus.OutputHandler = (port, _) =>
        {
            if ((byte)port != BdosPort) { return; }
            Z80Registers registers = cpu.Registers;
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

        while (!cpu.IsHalted)
        {
            if (cpu.CycleCount >= Budget)
            {
                Assert.Fail($"The program ran {cpu.CycleCount:N0} T-states without returning to CP/M. Output:\n{console}");
            }

            cpu.Run(Chunk);
        }

        cycles = cpu.CycleCount;
        return console.ToString();
    }

    private static void Exercise(string file, int test)
    {
        if (!File.Exists(Path.Join(ExternalTestData.Cache, Z80OracleTests.ZexallPin, "manifest.json")))
        {
            Assert.Inconclusive("Z80 fixtures are missing. Run tools\\Fetch-Z80Tests.ps1 with PowerShell 7.");
        }

        byte[] program = SelectTest(ExternalTestData.Read(Z80OracleTests.ZexallPin, file), test);
        string output = Run(program, out ulong cycles);
        Console.WriteLine(output);
        Console.WriteLine($"{cycles:N0} T-states, to the next {Chunk:N0}.");
        output.Should().Contain("Tests complete");
        output.Should().Contain(" OK", "the test's CRC matches a real Z80's");
        output.Should().NotContain("ERROR");
    }
}
