// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Globalization;
using Retrocore.Cpu.Z80;

namespace Retrocore.Tests;

/// <summary>
///  The Z80 core against the FUSE emulator's tests: each runs from a state until a T-state count, then compares
///  the memory and I/O accesses in order, the registers, memory and the T-states.
/// </summary>
/// <remarks>
///  <para>
///   FUSE's event times follow its own ZX Spectrum contention model, so the accesses are compared in order
///   without their times; the SingleStepTests check every T-state. FUSE's harness reads a port as its high
///   byte, and this version records no MEMPTR.
///  </para>
///  <para>
///   Where this FUSE differs from the hardware the SingleStepTests record, the comparison allows it: FUSE
///   skips the operand reads of a jump, call or DJNZ not taken, so its accesses need only be in ours with
///   reads between them; and it predates the Q model of <c>SCF</c> and <c>CCF</c> and leaves MEMPTR from the
///   previous test for <c>BIT b,[HL]</c>, so those compare F without X and Y.
///  </para>
/// </remarks>
[TestClass]
public class Z80FuseTests
{
    /// <summary>
    ///  The pinned FUSE revision; its tests are GPL inputs kept in the external cache.
    /// </summary>
    internal const string FusePin = "6d82fee65377fb68432120c58802b76240198121";

    /// <summary>
    ///  Every FUSE test matches.
    /// </summary>
    [TestMethod]
    [TestCategory("Conformance")]
    public void AllFuseTestsMatch()
    {
        if (!File.Exists(Path.Join(ExternalTestData.Cache, FusePin, "manifest.json")))
        {
            Assert.Inconclusive("FUSE fixtures are missing. Run tools\\Fetch-Z80Tests.ps1 with PowerShell 7.");
        }

        string[] input = Lines(ExternalTestData.Read(FusePin, "fuse/z80/tests/tests.in"));
        string[] expected = Lines(ExternalTestData.Read(FusePin, "fuse/z80/tests/tests.expected"));
        int inputLine = 0;
        int expectedLine = 0;
        int count = 0;
        List<string> failures = [];
        while (Next(input, ref inputLine) is { } name)
        {
            Next(expected, ref expectedLine);
            string? failure = Run(name, input, ref inputLine, expected, ref expectedLine);
            if (failure is not null) { failures.Add($"{name}: {failure}"); }
            count++;
        }

        Console.WriteLine($"FUSE: {count - failures.Count} of {count} tests passed.");
        Console.WriteLine(string.Join(Environment.NewLine, failures.Take(40)));
        failures.Should().BeEmpty();
        count.Should().BeGreaterThan(1300);
    }

    private static string? Run(string name, string[] input, ref int inputLine, string[] expected, ref int expectedLine)
    {
        Z80TestBus bus = new() { InputHandler = port => (byte)(port >> 8) };
        Z80Registers registers = Registers(input[inputLine++], input[inputLine++], out bool halted, out int target);
        if (halted) { return "a halted start is not supported"; }
        Memory(input, ref inputLine, bus.Memory);

        Z80Processor<Z80TestBus> cpu = new(bus);
        cpu.Registers = registers;
        List<string> accesses = [];
        do
        {
            ProcessorCycle cycle = cpu.NextCycle();
            string? kind = cycle.Operation switch
            {
                BusOperation.Read => "MR",
                BusOperation.Write => "MW",
                BusOperation.IoRead => "PR",
                BusOperation.IoWrite => "PW",
                _ => null
            };

            if (kind is not null) { accesses.Add($"{kind} {cycle.Address:x4} {cycle.Value:x2}"); }
        }
        while (!cpu.IsInstructionBoundary || ((int)cpu.CycleCount < target && !cpu.IsHalted));

        // The expected events are indented; contention (MC, PC) is FUSE's machine, not the CPU.
        List<string> events = [];
        while (expectedLine < expected.Length && expected[expectedLine].StartsWith(' '))
        {
            string[] parts = expected[expectedLine++].Split(' ', StringSplitOptions.RemoveEmptyEntries);
            if (parts[1] is "MR" or "MW" or "PR" or "PW") { events.Add($"{parts[1]} {parts[2]} {parts[3]}"); }
        }

        Z80Registers wanted = Registers(expected[expectedLine++], expected[expectedLine++], out bool wantedHalted, out int cycles);
        byte[] memory = (byte[])bus.Memory.Clone();
        Memory(expected, ref expectedLine, memory);
        if (!IsReadSuperset(accesses, events))
        {
            return $"accesses [{string.Join(", ", accesses)}], expected [{string.Join(", ", events)}]";
        }

        Z80Registers actual = cpu.Registers;
        if (IgnoresUndocumentedFlags(name))
        {
            actual.F = (byte)(actual.F & ~0x28);
            wanted.F = (byte)(wanted.F & ~0x28);
        }

        (string Name, int Actual, int Expected)[] values =
        [
            ("AF", actual.AF, wanted.AF), ("BC", actual.BC, wanted.BC), ("DE", actual.DE, wanted.DE),
            ("HL", actual.HL, wanted.HL), ("AF'", actual.AlternateAF, wanted.AlternateAF),
            ("BC'", actual.AlternateBC, wanted.AlternateBC), ("DE'", actual.AlternateDE, wanted.AlternateDE),
            ("HL'", actual.AlternateHL, wanted.AlternateHL), ("IX", actual.IX, wanted.IX), ("IY", actual.IY, wanted.IY),
            ("SP", actual.SP, wanted.SP), ("PC", actual.PC, wanted.PC), ("I", actual.I, wanted.I), ("R", actual.R, wanted.R),
            ("IFF1", actual.Iff1 ? 1 : 0, wanted.Iff1 ? 1 : 0), ("IFF2", actual.Iff2 ? 1 : 0, wanted.Iff2 ? 1 : 0),
            ("IM", actual.InterruptMode, wanted.InterruptMode), ("halted", cpu.IsHalted ? 1 : 0, wantedHalted ? 1 : 0),
            ("T-states", (int)cpu.CycleCount, cycles)
        ];

        foreach ((string register, int value, int wantedValue) in values)
        {
            if (value != wantedValue) { return $"{register} is {value:X4}, expected {wantedValue:X4}"; }
        }

        return bus.Memory.AsSpan().SequenceEqual(memory) ? null : "memory differs";
    }

    // FUSE's accesses, in order, with any of ours between them only reads.
    private static bool IsReadSuperset(List<string> actual, List<string> expected)
    {
        int next = 0;
        foreach (string access in actual)
        {
            if (next < expected.Count && access == expected[next]) { next++; }
            else if (!access.StartsWith("MR", StringComparison.Ordinal)) { return false; }
        }

        return next == expected.Count;
    }

    // SCF, CCF and BIT b,[HL], whose X and Y depend on state this FUSE does not model.
    private static bool IgnoresUndocumentedFlags(string name) =>
        name.StartsWith("37", StringComparison.Ordinal)
            || name.StartsWith("3f", StringComparison.Ordinal)
            || IsBitMemory(name);

    // cb46, cb4e ... cb7e: BIT b,[HL].
    private static bool IsBitMemory(string name) =>
        name.Length == 4
            && name.StartsWith("cb", StringComparison.Ordinal)
            && name[2] is >= '4' and <= '7'
            && name[3] is '6' or 'e';

    // AF BC DE HL AF' BC' DE' HL' IX IY SP PC, then I R IFF1 IFF2 IM halted T-states.
    private static Z80Registers Registers(string words, string state, out bool halted, out int cycles)
    {
        int[] w = [.. words.Split(' ', StringSplitOptions.RemoveEmptyEntries).Select(Hex)];
        string[] s = state.Split(' ', StringSplitOptions.RemoveEmptyEntries);
        halted = s[5] != "0";
        cycles = int.Parse(s[6], CultureInfo.InvariantCulture);
        return new()
        {
            AF = (ushort)w[0],
            BC = (ushort)w[1],
            DE = (ushort)w[2],
            HL = (ushort)w[3],
            AlternateAF = (ushort)w[4],
            AlternateBC = (ushort)w[5],
            AlternateDE = (ushort)w[6],
            AlternateHL = (ushort)w[7],
            IX = (ushort)w[8],
            IY = (ushort)w[9],
            SP = (ushort)w[10],
            PC = (ushort)w[11],
            I = (byte)Hex(s[0]),
            R = (byte)Hex(s[1]),
            Iff1 = s[2] != "0",
            Iff2 = s[3] != "0",
            InterruptMode = byte.Parse(s[4], CultureInfo.InvariantCulture)
        };
    }

    // Blocks of "address byte byte ... -1", ended by a lone -1 in the input or a blank line in the expectations.
    private static void Memory(string[] lines, ref int line, byte[] memory)
    {
        while (line < lines.Length && lines[line].Length != 0 && lines[line] != "-1")
        {
            string[] parts = lines[line++].Split(' ', StringSplitOptions.RemoveEmptyEntries);
            int address = Hex(parts[0]);
            for (int index = 1; index < parts.Length && parts[index] != "-1"; index++)
            {
                memory[(address + index - 1) & 0xFFFF] = (byte)Hex(parts[index]);
            }
        }

        if (line < lines.Length) { line++; }
    }

    private static string? Next(string[] lines, ref int line)
    {
        while (line < lines.Length && lines[line].Length == 0) { line++; }
        return line < lines.Length ? lines[line++] : null;
    }

    private static int Hex(string text) => int.Parse(text, NumberStyles.HexNumber, CultureInfo.InvariantCulture);

    private static string[] Lines(byte[] bytes) =>
        System.Text.Encoding.ASCII.GetString(bytes).Replace("\r", "", StringComparison.Ordinal).Split('\n');
}
