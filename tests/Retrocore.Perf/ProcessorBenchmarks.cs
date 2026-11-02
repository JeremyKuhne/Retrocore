// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using BenchmarkDotNet.Attributes;

namespace Retrocore.Perf;

/// <summary>
///  Measures the public cycle-stepping path with a representative RAM workload on one host thread.
/// </summary>
[MemoryDiagnoser]
public class ProcessorBenchmarks
{
    private const int CyclesPerBatch = CpuWorkload.CyclesPerLoop * 1024;
    private Processor<RamBus>? _cpu;
    private RamBus _bus;

    /// <summary>
    ///  Gets or sets the processor variant.
    /// </summary>
    [Params(ProcessorVariant.Mos6502, ProcessorVariant.Wdc65C02, ProcessorVariant.Rockwell65C02)]
    public ProcessorVariant Variant { get; set; }

    /// <summary>
    ///  Creates and verifies the benchmark workload.
    /// </summary>
    [GlobalSetup]
    public void Setup()
    {
        _cpu = CpuWorkload.Create(Variant, out _bus);
        _cpu.Run(cycleBudget: CpuWorkload.CyclesPerLoop);
        CpuWorkload.Validate(_cpu, _bus);
    }

    /// <summary>
    ///  Executes a fixed number of complete workload loops, reported per emulated CPU cycle.
    /// </summary>
    /// <returns>A value produced by the executed instructions.</returns>
    [Benchmark(OperationsPerInvoke = CyclesPerBatch)]
    public byte StepCycles()
    {
        Processor<RamBus> cpu = _cpu ?? throw new InvalidOperationException("Benchmark setup was not run.");
        for (int i = 0; i < CyclesPerBatch; i++) { cpu.StepCycle(); }
        return cpu.Registers.Accumulator;
    }

    /// <summary>
    ///  Checks the results outside the timed region.
    /// </summary>
    [GlobalCleanup]
    public void Validate() => CpuWorkload.Validate(
        _cpu ?? throw new InvalidOperationException("Benchmark setup was not run."),
        _bus);
}
