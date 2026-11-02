// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using BenchmarkDotNet.Attributes;

namespace Retrocore.Perf;

/// <summary>
///  Separately measures full bus-cycle metadata recording into a preallocated trace buffer.
/// </summary>
[MemoryDiagnoser]
public class ProcessorTraceBenchmarks
{
    private const int CyclesPerBatch = CpuWorkload.CyclesPerLoop * 1024;
    private readonly ProcessorCycle[] _trace = new ProcessorCycle[CyclesPerBatch];
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
    ///  Executes and records every bus cycle of a fixed workload batch.
    /// </summary>
    /// <returns>The final recorded cycle number.</returns>
    [Benchmark(OperationsPerInvoke = CyclesPerBatch)]
    public ulong StepCyclesWithTrace()
    {
        Processor<RamBus> cpu = _cpu ?? throw new InvalidOperationException("Benchmark setup was not run.");
        for (int i = 0; i < CyclesPerBatch; i++)
        {
            cpu.StepCycle();
            _trace[i] = cpu.LastCycle;
        }

        return _trace[^1].Number;
    }

    /// <summary>
    ///  Checks the CPU and recorded output outside the measured region.
    /// </summary>
    [GlobalCleanup]
    public void Validate()
    {
        Processor<RamBus> cpu = _cpu ?? throw new InvalidOperationException("Benchmark setup was not run.");
        CpuWorkload.Validate(cpu, _bus);
        if (_trace[^1].Number != cpu.CycleCount || _trace[^1].Operation != BusOperation.Read)
        {
            throw new InvalidOperationException("The trace does not describe the completed workload.");
        }
    }
}
