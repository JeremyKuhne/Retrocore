// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Diagnostics;
using System.Globalization;
using Retrocore.Machines.Commodore;
// An instruction's address with the registers before it; the B flag is left out, since MAME shows it set.
using Row = (ushort Pc, byte A, byte X, byte Y, byte P, byte S);

namespace Retrocore.Tests;

/// <summary>
///  The PET 2001 against MAME: from power-on to <c>READY.</c> and on, the ROMs must run the same instructions with the
///  same registers.
/// </summary>
/// <remarks>
///  <para>
///   MAME (<c>RETROCORE_MAME</c>, or <c>%USERPROFILE%\Retrocore\mame\mame.exe</c>) runs <c>tools\PetOracle.lua</c>,
///   which traces with its debugger; the IEEE-488 slot is left empty so the PET's 6502 is MAME's first CPU. The
///   tests are inconclusive without MAME or the ROM sets.
///  </para>
///  <para>
///   MAME's 2001 has no beam: it toggles the retrace line every 1/120 second, where the 2001's is low for 3,840 of
///   each frame's 16,640 cycles. So the interrupts come at other times, and loops that wait for the retrace line run
///   other numbers of times. The comparison leaves out each interrupt, from the vector's target to its RTI, and counts
///   a loop repeated back to back once, as MAME's own trace collapses loops.
///  </para>
/// </remarks>
[TestClass]
public class PetOracleTests
{
    /// <summary>
    ///  From power-on through the RAM test, the banner and <c>READY.</c> to the wait for a key.
    /// </summary>
    /// <param name="model">The model.</param>
    /// <param name="mameMachine">MAME's machine with those ROMs.</param>
    /// <param name="ramKilobytes">The RAM MAME's machine has.</param>
    [TestMethod]
    [TestCategory("Conformance")]
    [DataRow(PetModel.Pet2001, "pet20018", 8)]
    [DataRow(PetModel.Pet2001Basic2, "pet2001n", 8)]
    [DataRow(PetModel.Pet4032, "pet4016", 16)]
    [DataRow(PetModel.Pet4032Business, "pet4032b", 32)]
    public void BootMatchesMame(PetModel model, string mameMachine, int ramKilobytes)
    {
        string mame = Environment.GetEnvironmentVariable("RETROCORE_MAME")
            ?? Path.Join(ExternalTestData.Root, "mame", "mame.exe");

        string roms = Path.Join(Path.GetDirectoryName(PetMachineTests.RomRoot), "mame");
        if (!File.Exists(mame) || !File.Exists(Path.Join(roms, (mameMachine == "pet20018" ? "pet2001" : mameMachine) + ".zip")))
        {
            Assert.Inconclusive("MAME or the PET ROM sets are missing.");
        }

        PetMachine machine = PetMachineTests.Machine(model, ramKilobytes);
        ushort irq = (ushort)(machine.Bus.Peek(0xFFFE) | (machine.Bus.Peek(0xFFFF) << 8));
        List<Row> expected = Collapse(Normalize(WithoutInterrupts(RunMame(mame, mameMachine, roms, seconds: 3), irq, machine.Bus.Peek), machine));
        List<Row> actual = Collapse(Normalize(WithoutInterrupts(RunMachine(machine, seconds: 3), irq, machine.Bus.Peek), machine));
        expected.Count.Should().BeGreaterThan(5_000, "MAME reached READY.");

        int count = Math.Min(expected.Count, actual.Count);
        for (int i = 0; i < count; i++)
        {
            if (expected[i] != actual[i])
            {
                string context = string.Join(
                    '\n',
                    Enumerable.Range(Math.Max(0, i - 8), Math.Min(12, count - Math.Max(0, i - 8)))
                        .Select(j => $"{Show(expected[j])}    {Show(actual[j])}"));

                Assert.Fail($"Instruction {i} of {count} differs (MAME, then ours):\n{context}");
            }
        }

        // Both end waiting for a key, in a loop each counted once.
        Math.Abs(expected.Count - actual.Count).Should().BeLessThan(16);
        machine.ReadTextScreen().Should().Contain(line => line.StartsWith("READY.", StringComparison.Ordinal));
    }

    /// <summary>
    ///  Shows a row as the failure messages do.
    /// </summary>
    /// <param name="row">The row.</param>
    /// <returns>The address and registers in hex.</returns>
    internal static string Show(Row row) =>
        $"{row.Pc:X4} {row.A:X2} {row.X:X2} {row.Y:X2} {row.P:X2} {row.S:X2}";

    /// <summary>
    ///  Leaves out each interrupt: from the row at the IRQ vector's target through the RTI that ends it.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   Our machine steps the interrupt and the handler's first instruction, a one-byte PHA, together, so its first
    ///   row is the next. MAME logs the instruction it is about to run when it takes an interrupt instead, then again
    ///   after the RTI, so the row after an interrupt is dropped when it repeats the one before.
    ///  </para>
    /// </remarks>
    /// <param name="rows">The rows.</param>
    /// <param name="irq">The IRQ vector's target.</param>
    /// <param name="peek">Reads the processor's memory, to find each RTI.</param>
    /// <returns>The rows kept.</returns>
    internal static List<Row> WithoutInterrupts(IEnumerable<Row> rows, ushort irq, Func<ushort, byte> peek)
    {
        List<Row> kept = [];
        bool inside = false;
        bool returned = false;
        foreach (Row row in rows)
        {
            if (!inside && (row.Pc == irq || row.Pc == irq + 1)) { inside = true; }
            if (inside)
            {
                if (peek(row.Pc) == 0x40)
                {
                    inside = false;
                    returned = true;
                }

                continue;
            }

            if (returned && kept.Count != 0 && kept[^1] == row)
            {
                returned = false;
                continue;
            }

            returned = false;
            kept.Add(row);
        }

        return kept;
    }

    // Leaves out the editor's waits for the retrace line, VIDEO ON: each LDA $E840, AND #$20 and the branch after
    // them, which run as many times as the beam says, and the retrace bit and zero flag in the row after.
    private static IEnumerable<Row> Normalize(IEnumerable<Row> rows, PetMachine machine)
    {
        int skip = 0;
        bool mask = false;
        foreach (Row row in rows)
        {
            if (skip == 0
                && machine.Bus.Peek(row.Pc) == 0xAD
                && machine.Bus.Peek((ushort)(row.Pc + 1)) == 0x40
                && machine.Bus.Peek((ushort)(row.Pc + 2)) == 0xE8
                && machine.Bus.Peek((ushort)(row.Pc + 3)) == 0x29
                && machine.Bus.Peek((ushort)(row.Pc + 4)) == 0x20)
            {
                skip = 3;
            }

            if (skip > 0)
            {
                skip--;
                mask = skip == 0;
                continue;
            }

            yield return mask ? row with { A = (byte)(row.A & ~0x20), P = (byte)(row.P & ~0x02) } : row;
            mask = false;
        }
    }

    /// <summary>
    ///  Drops every repeat of a run of up to 8 rows that comes straight after itself.
    /// </summary>
    /// <param name="rows">The rows.</param>
    /// <returns>The rows kept.</returns>
    internal static List<Row> Collapse(IEnumerable<Row> rows)
    {
        List<Row> collapsed = [];
        foreach (Row row in rows)
        {
            collapsed.Add(row);
            for (int length = 1; length <= 8 && collapsed.Count >= 2 * length; length++)
            {
                int start = collapsed.Count - length;
                bool repeat = true;
                for (int i = 0; i < length && repeat; i++)
                {
                    repeat = collapsed[start + i] == collapsed[start - length + i];
                }

                if (repeat)
                {
                    collapsed.RemoveRange(start, length);
                    break;
                }
            }
        }

        return collapsed;
    }

    private static List<Row> RunMachine(PetMachine machine, int seconds)
    {
        // The registers' power-on contents are happenstance; take MAME's once the reset sequence is done.
        for (int i = 0; i < 7; i++) { machine.StepCycle(); }
        ProcessorRegisters start = machine.Processor.Registers;
        start.Accumulator = 0;
        start.X = 0x80;
        start.Y = 0;
        start.StackPointer = 0xFD;
        start.Status |= StatusRegister.Zero;
        machine.Processor.Registers = start;

        List<Row> rows = [];
        ulong end = (ulong)seconds * PetTiming.CpuHertz;
        while (machine.Processor.CycleCount < end)
        {
            ProcessorRegisters r = machine.Processor.Registers;
            rows.Add((r.ProgramCounter, r.Accumulator, r.X, r.Y, (byte)((byte)r.Status & 0xEF), r.StackPointer));
            machine.StepInstruction();
        }

        return rows;
    }

    private static List<Row> RunMame(string mame, string mameMachine, string roms, int seconds) =>
        RunMame(mame, [mameMachine, "-ieee8", ""], roms, seconds, "PetOracle.lua", environment: new Dictionary<string, string>());

    /// <summary>
    ///  Runs MAME with a tracing script and reads its trace.
    /// </summary>
    /// <param name="mame">MAME.</param>
    /// <param name="machineArguments">The machine and its slot and media options.</param>
    /// <param name="roms">The ROM path.</param>
    /// <param name="seconds">The emulated seconds to trace.</param>
    /// <param name="script">The script, in <c>tools</c>.</param>
    /// <param name="environment">More settings for the script.</param>
    /// <returns>The rows.</returns>
    internal static List<Row> RunMame(
        string mame,
        IReadOnlyList<string> machineArguments,
        string roms,
        int seconds,
        string script,
        IReadOnlyDictionary<string, string> environment)
    {
        string work = Directory.CreateTempSubdirectory("retrocore-mame").FullName;
        try
        {
            string output = Path.Join(work, "trace.log");
            ProcessStartInfo start = new(mame)
            {
                WorkingDirectory = work,
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true
            };

            string[] arguments =
            [
                .. machineArguments, "-rompath", roms, "-cfg_directory", work, "-nvram_directory", work,
                "-video", "none", "-sound", "none", "-nothrottle", "-skip_gameinfo",
                "-debug", "-debugger", "none", "-seconds_to_run", (seconds + 5).ToString(CultureInfo.InvariantCulture),
                "-autoboot_script", FindTool(script), "-autoboot_delay", "0"
            ];

            foreach (string argument in arguments) { start.ArgumentList.Add(argument); }
            start.Environment["RETRO_END"] = seconds.ToString(CultureInfo.InvariantCulture);
            start.Environment["RETRO_OUT"] = output;
            foreach ((string key, string value) in environment) { start.Environment[key] = value; }
            RunToExit(start);

            File.Exists(output).Should().BeTrue("the Lua script traces");
            List<Row> rows = [];
            foreach (string line in File.ReadLines(output))
            {
                int bar = line.IndexOf('|', StringComparison.Ordinal);
                if (bar < 0 || line.Length < bar + 5) { continue; }
                ushort pc = ushort.Parse(line.AsSpan(bar + 1, 4), NumberStyles.HexNumber, CultureInfo.InvariantCulture);
                string[] registers = line[..bar].Split(' ');
                rows.Add((
                    pc,
                    Hex(registers[0]),
                    Hex(registers[1]),
                    Hex(registers[2]),
                    (byte)(Hex(registers[3]) & 0xEF),
                    (byte)(int.Parse(registers[4], NumberStyles.HexNumber, CultureInfo.InvariantCulture) & 0xFF)));
            }

            return rows;
        }
        finally
        {
            Directory.Delete(work, recursive: true);
        }

        static byte Hex(string text) => byte.Parse(text, NumberStyles.HexNumber, CultureInfo.InvariantCulture);
    }

    /// <summary>
    ///  Runs MAME to its end, draining its output and error as it writes them; one still running after five minutes
    ///  is killed, and the test fails.
    /// </summary>
    /// <param name="start">How to start it, with both streams redirected.</param>
    internal static void RunToExit(ProcessStartInfo start)
    {
        using Process process = Process.Start(start) ?? throw new InvalidOperationException("MAME did not start.");
        process.OutputDataReceived += static (_, _) => { };
        process.ErrorDataReceived += static (_, _) => { };
        process.BeginOutputReadLine();
        process.BeginErrorReadLine();
        if (!process.WaitForExit(300_000))
        {
            process.Kill(entireProcessTree: true);
            process.WaitForExit();
            Assert.Fail("MAME did not finish in five minutes.");
        }

        process.WaitForExit();
    }

    private static string FindTool(string name)
    {
        for (DirectoryInfo? directory = new(AppContext.BaseDirectory); directory is not null; directory = directory.Parent)
        {
            string candidate = Path.Join(directory.FullName, "tools", name);
            if (File.Exists(candidate)) { return candidate; }
        }

        throw new FileNotFoundException(name);
    }
}
