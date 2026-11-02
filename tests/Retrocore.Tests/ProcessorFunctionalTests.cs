// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Perf;

namespace Retrocore.Tests;

/// <summary>
///  Functional certification against externally cached GPL binaries, without sources or bundled assets.
/// </summary>
[TestClass]
public class ProcessorFunctionalTests
{
    /// <summary>
    ///  Executes a pinned Klaus binary until its documented success loop, rejecting failure loops.
    /// </summary>
    /// <param name="variant">The CPU variant.</param>
    /// <param name="extended">Whether to run the CMOS extended-opcode binary.</param>
    [TestMethod]
    [TestCategory("Functional")]
    [DataRow(ProcessorVariant.Mos6502, false)]
    [DataRow(ProcessorVariant.Wdc65C02, false)]
    [DataRow(ProcessorVariant.Rockwell65C02, false)]
    [DataRow(ProcessorVariant.Wdc65C02, true)]
    [DataRow(ProcessorVariant.Rockwell65C02, true)]
    public void KlausReachesSuccessLoop(ProcessorVariant variant, bool extended)
    {
        string name = extended ? "65C02_extended_opcodes_test" : "6502_functional_test";
        byte[] memory = ExternalTestData.Read(ExternalTestData.KlausPin, $"bin_files/{name}.bin", flatten: true);
        memory.Length.Should().Be(65536);
        Processor<RamBus> cpu = new(new RamBus(memory), variant);
        ProcessorRegisters registers = cpu.Registers;
        registers.ProgramCounter = 0x400;
        cpu.Registers = registers;
        ushort success = extended ? (ushort)0x24F1 : (ushort)0x3469;
        for (int i = 0; i < 100_000_000; i++)
        {
            ushort before = cpu.Registers.ProgramCounter;
            ProcessorExecutionResult result = cpu.StepInstruction(maximumCycles: 32);
            if (result.Status != ProcessorExecutionStatus.InstructionComplete)
            {
                result.Status.Should().Be(ProcessorExecutionStatus.InstructionComplete);
            }

            ushort after = cpu.Registers.ProgramCounter;
            if (before == after)
            {
                after.Should().Be(success, $"{name} must not enter a failure trap");
                Console.WriteLine($"{variant} {name} reached ${success:X4} after {cpu.CycleCount:N0} cycles.");
                return;
            }
        }

        throw new InvalidOperationException("Klaus exceeded the explicit instruction budget without reaching success.");
    }

    /// <summary>
    ///  Validates the exact benchmark denominator and observable output across all CPU variants.
    /// </summary>
    /// <param name="variant">The CPU variant.</param>
    [TestMethod]
    [DataRow(ProcessorVariant.Mos6502)]
    [DataRow(ProcessorVariant.Wdc65C02)]
    [DataRow(ProcessorVariant.Rockwell65C02)]
    public void BenchmarkWorkloadHasExactCycleDenominator(ProcessorVariant variant)
    {
        Processor<RamBus> cpu = CpuWorkload.Create(variant, out RamBus bus);
        cpu.Run(cycleBudget: CpuWorkload.CyclesPerLoop);
        CpuWorkload.Validate(cpu, bus);
        cpu.CycleCount.Should().Be(CpuWorkload.CyclesPerLoop);
        cpu.Run(cycleBudget: CpuWorkload.CyclesPerLoop * 10);
        CpuWorkload.Validate(cpu, bus);
    }
}
