// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.Json;
using Retrocore.Cpu.Z80;

namespace Retrocore.Tests;

/// <summary>
///  The Z80 core against the SingleStepTests: every T-state's address bus, data bus and control lines, then
///  every register, the undocumented state, memory and I/O.
/// </summary>
[TestClass]
public class Z80ConformanceTests
{
    /// <summary>
    ///  Every case of every opcode file matches.
    /// </summary>
    [TestMethod]
    [TestCategory("Conformance")]
    public void AllSingleStepVectorsMatch()
    {
        string root = Path.Join(ExternalTestData.Cache, Z80OracleTests.SingleStepPin);
        if (!File.Exists(Path.Join(root, "manifest.json")))
        {
            Assert.Inconclusive("Z80 fixtures are missing. Run tools\\Fetch-Z80Tests.ps1 with PowerShell 7.");
        }

        Z80TestBus bus = new();
        Z80Processor<Z80TestBus> cpu = new(bus);
        Z80Snapshot baseline = cpu.CaptureState();
        long total = 0;
        List<string> failures = [];
        foreach (string path in Directory.EnumerateFiles(Path.Join(root, "v1"), "*.json").Order(StringComparer.Ordinal))
        {
            string name = "v1/" + Path.GetFileName(path);
            using JsonDocument document = JsonDocument.Parse(ExternalTestData.Read(Z80OracleTests.SingleStepPin, name));
            foreach (JsonElement test in document.RootElement.EnumerateArray())
            {
                cpu.RestoreState(baseline);
                string? failure = Check(cpu, bus, test);
                if (failure is not null)
                {
                    failures.Add($"{test.GetProperty("name").GetString()}: {failure}");
                    break;
                }

                total++;
            }

            // A handful of failing opcodes says enough; the rest would repeat it.
            if (failures.Count >= 40) { break; }
        }

        Console.WriteLine($"Z80: {total:N0} scenarios passed.");
        Console.WriteLine(string.Join(Environment.NewLine, failures));
        failures.Should().BeEmpty();
        total.Should().Be(1_604_000);
    }

    private static string? Check(Z80Processor<Z80TestBus> cpu, Z80TestBus bus, JsonElement test)
    {
        JsonElement initial = test.GetProperty("initial");
        JsonElement final = test.GetProperty("final");
        foreach (JsonElement cell in initial.GetProperty("ram").EnumerateArray())
        {
            bus.Memory[cell[0].GetUInt16()] = cell[1].GetByte();
        }

        bus.ClearIo();
        List<(ushort Port, byte Value)> expectedOutputs = [];
        if (test.TryGetProperty("ports", out JsonElement ports))
        {
            foreach (JsonElement port in ports.EnumerateArray())
            {
                if (port[2].GetString() == "r") { bus.Inputs.Enqueue(port[1].GetByte()); }
                else { expectedOutputs.Add((port[0].GetUInt16(), port[1].GetByte())); }
            }
        }

        cpu.Registers = Registers(initial);
        int? previousData = null;
        int index = 0;
        foreach (JsonElement expected in test.GetProperty("cycles").EnumerateArray())
        {
            ProcessorCycle cycle = cpu.NextCycle();
            (string pins, int? data) = cycle.Operation switch
            {
                BusOperation.Read => ("r-m-", (int?)null),
                BusOperation.Write => ("-wm-", cycle.Value),
                BusOperation.IoRead => ("r--i", null),
                BusOperation.IoWrite => ("-w-i", cycle.Value),
                _ => ("----", previousData)
            };

            // A read's byte is on the data bus at the T-state after the strobe.
            previousData = cycle.Operation is BusOperation.Read or BusOperation.IoRead ? cycle.Value : null;
            int address = expected[0].GetInt32();
            int? expectedData = expected[1].ValueKind == JsonValueKind.Null ? null : expected[1].GetInt32();
            string expectedPins = expected[2].GetString() ?? "";
            if (cycle.Address != address || pins != expectedPins || (expectedData is not null && data != expectedData))
            {
                string wanted = $"{address:X4} {Text(expectedData)} {expectedPins}";
                return $"T{index + 1}: expected {wanted}, got {cycle.Address:X4} {Text(data)} {pins}";
            }

            index++;
        }

        if (!cpu.IsInstructionBoundary) { return $"the instruction is not over after {index} T-states"; }
        if (Compare(cpu.Registers, final) is { } difference) { return difference; }
        foreach (JsonElement cell in final.GetProperty("ram").EnumerateArray())
        {
            ushort address = cell[0].GetUInt16();
            if (bus.Memory[address] != cell[1].GetByte())
            {
                return $"memory ${address:X4} is {bus.Memory[address]:X2}, expected {cell[1].GetByte():X2}";
            }
        }

        return bus.Outputs.SequenceEqual(expectedOutputs) ? null : "the outputs differ";
    }

    private static string Text(int? value) => value is { } data ? data.ToString("X2") : "--";

    private static Z80Registers Registers(JsonElement state) => new()
    {
        A = state.GetProperty("a").GetByte(),
        F = state.GetProperty("f").GetByte(),
        B = state.GetProperty("b").GetByte(),
        C = state.GetProperty("c").GetByte(),
        D = state.GetProperty("d").GetByte(),
        E = state.GetProperty("e").GetByte(),
        H = state.GetProperty("h").GetByte(),
        L = state.GetProperty("l").GetByte(),
        AlternateAF = state.GetProperty("af_").GetUInt16(),
        AlternateBC = state.GetProperty("bc_").GetUInt16(),
        AlternateDE = state.GetProperty("de_").GetUInt16(),
        AlternateHL = state.GetProperty("hl_").GetUInt16(),
        IX = state.GetProperty("ix").GetUInt16(),
        IY = state.GetProperty("iy").GetUInt16(),
        SP = state.GetProperty("sp").GetUInt16(),
        PC = state.GetProperty("pc").GetUInt16(),
        I = state.GetProperty("i").GetByte(),
        R = state.GetProperty("r").GetByte(),
        WZ = state.GetProperty("wz").GetUInt16(),
        Q = state.GetProperty("q").GetByte(),
        Iff1 = state.GetProperty("iff1").GetInt32() != 0,
        Iff2 = state.GetProperty("iff2").GetInt32() != 0,
        InterruptMode = state.GetProperty("im").GetByte(),
        AfterEnable = state.GetProperty("ei").GetInt32() != 0,
        AfterLoadInterrupt = state.GetProperty("p").GetInt32() != 0
    };

    private static string? Compare(Z80Registers actual, JsonElement expected)
    {
        Z80Registers wanted = Registers(expected);
        (string Name, int Actual, int Expected)[] values =
        [
            ("A", actual.A, wanted.A), ("F", actual.F, wanted.F), ("B", actual.B, wanted.B), ("C", actual.C, wanted.C),
            ("D", actual.D, wanted.D), ("E", actual.E, wanted.E), ("H", actual.H, wanted.H), ("L", actual.L, wanted.L),
            ("AF'", actual.AlternateAF, wanted.AlternateAF), ("BC'", actual.AlternateBC, wanted.AlternateBC),
            ("DE'", actual.AlternateDE, wanted.AlternateDE), ("HL'", actual.AlternateHL, wanted.AlternateHL),
            ("IX", actual.IX, wanted.IX), ("IY", actual.IY, wanted.IY), ("SP", actual.SP, wanted.SP),
            ("PC", actual.PC, wanted.PC), ("I", actual.I, wanted.I), ("R", actual.R, wanted.R),
            ("WZ", actual.WZ, wanted.WZ), ("Q", actual.Q, wanted.Q), ("IFF1", actual.Iff1 ? 1 : 0, wanted.Iff1 ? 1 : 0),
            ("IFF2", actual.Iff2 ? 1 : 0, wanted.Iff2 ? 1 : 0), ("IM", actual.InterruptMode, wanted.InterruptMode),
            ("EI", actual.AfterEnable ? 1 : 0, wanted.AfterEnable ? 1 : 0),
            ("P", actual.AfterLoadInterrupt ? 1 : 0, wanted.AfterLoadInterrupt ? 1 : 0)
        ];

        foreach ((string name, int value, int wantedValue) in values)
        {
            if (value != wantedValue) { return $"{name} is {value:X2}, expected {wantedValue:X2}"; }
        }

        return null;
    }
}
