// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.Json;

namespace Retrocore.Tests;

/// <summary>
///  Full MIT SingleStepTests certification, including every supplied bus-cycle trace.
/// </summary>
[TestClass]
public class ProcessorConformanceTests
{
    /// <summary>
    ///  Executes all 10,000 scenarios for every supplied opcode.
    /// </summary>
    /// <param name="variant">The CPU variant.</param>
    /// <param name="directory">The upstream fixture directory.</param>
    [TestMethod]
    [TestCategory("Conformance")]
    [DataRow(ProcessorVariant.Mos6502, "6502")]
    [DataRow(ProcessorVariant.Wdc65C02, "wdc65c02")]
    [DataRow(ProcessorVariant.Rockwell65C02, "rockwell65c02")]
    public void AllSingleStepVectorsMatch(ProcessorVariant variant, string directory)
    {
        ConformanceBus bus = new();
        Processor<ConformanceBus> cpu = new(bus, variant);
        ProcessorSnapshot baseline = cpu.CaptureState();
        long total = 0;
        List<string> failures = [];
        for (int opcode = 0; opcode < 256; opcode++)
        {
            byte[] bytes = ExternalTestData.Read(ExternalTestData.SingleStepPin, $"{directory}/v1/{opcode:x2}.json");
            if (bytes.Length == 0 && variant == ProcessorVariant.Wdc65C02 && opcode is 0xCB or 0xDB)
            {
                continue;
            }

            using JsonDocument document = JsonDocument.Parse(bytes);
            document.RootElement.GetArrayLength().Should().Be(10000, $"fixture {directory}/{opcode:x2}");
            int caseIndex = 0;
            foreach (JsonElement test in document.RootElement.EnumerateArray())
            {
                cpu.RestoreState(baseline);
                JsonElement initial = test.GetProperty("initial");
                bus.Initialize(initial.GetProperty("ram"));
                cpu.Registers = Registers(initial);
                string? failure;
                try
                {
                    failure = CheckCase(cpu, bus, test);
                }
                catch (InvalidOperationException exception)
                {
                    failure = exception.Message;
                }

                if (failure is not null)
                {
                    failures.Add($"{directory}/{opcode:x2} case {caseIndex} ({test.GetProperty("name").GetString()}): {failure}");
                    break;
                }

                total++;
                caseIndex++;
            }
        }

        Console.WriteLine($"{directory}: {total:N0} scenarios passed; WDC WAI/STP use directed tests, not empty fixtures.");
        Console.WriteLine(string.Join(Environment.NewLine, failures));
        failures.Should().BeEmpty();
        total.Should().Be(variant == ProcessorVariant.Wdc65C02 ? 2540000 : 2560000);
    }

    private static string? CheckCase(Processor<ConformanceBus> cpu, ConformanceBus bus, JsonElement test)
    {
        int index = 0;
        foreach (JsonElement expected in test.GetProperty("cycles").EnumerateArray())
        {
            ProcessorCycle cycle = cpu.NextCycle();
            BusOperation operation = expected[2].GetString() == "read" ? BusOperation.Read : BusOperation.Write;
            if (cycle.Address != expected[0].GetUInt16()
                || cycle.Value != expected[1].GetByte()
                || cycle.Operation != operation
                || bus.AccessCount != index + 1)
            {
                return $"cycle {index}: expected {expected}; actual [{cycle.Address},{cycle.Value},{cycle.Operation}], callbacks {bus.AccessCount}";
            }

            index++;
        }

        JsonElement final = test.GetProperty("final");
        ProcessorRegisters expectedRegisters = Registers(final);
        ProcessorRegisters actual = cpu.Registers;
        if (actual.ProgramCounter != expectedRegisters.ProgramCounter
            || actual.StackPointer != expectedRegisters.StackPointer
            || actual.Accumulator != expectedRegisters.Accumulator
            || actual.X != expectedRegisters.X
            || actual.Y != expectedRegisters.Y
            || actual.Status != expectedRegisters.Status)
        {
            return $"registers expected {final}; actual PC={actual.ProgramCounter} S={actual.StackPointer} A={actual.Accumulator} X={actual.X} Y={actual.Y} P={(byte)actual.Status}";
        }

        foreach (JsonElement pair in final.GetProperty("ram").EnumerateArray())
        {
            if (bus.Peek(pair[0].GetInt32()) != pair[1].GetByte())
            {
                return $"RAM mismatch at {pair[0]}: expected {pair[1]}, actual {bus.Peek(pair[0].GetInt32())}";
            }
        }

        return cpu.Status == ProcessorExecutionStatus.Running && !cpu.IsInstructionBoundary
            ? "Instruction did not finish at the exact end of the supplied trace."
            : null;
    }

    private static ProcessorRegisters Registers(JsonElement state) => new()
    {
        ProgramCounter = state.GetProperty("pc").GetUInt16(),
        StackPointer = state.GetProperty("s").GetByte(),
        Accumulator = state.GetProperty("a").GetByte(),
        X = state.GetProperty("x").GetByte(),
        Y = state.GetProperty("y").GetByte(),
        Status = (StatusRegister)state.GetProperty("p").GetByte()
    };
}
