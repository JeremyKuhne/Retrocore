// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using BenchmarkDotNet.Attributes;
using Retrocore.Assembler;
using Retrocore.Machines.Apple2;
using NativeAssembler = Retrocore.Assembler.Assembler;

namespace Retrocore.Perf;

/// <summary>
///  Measures disassembly, native source export and reassembly of the actual original/enhanced IIe ROMs.
/// </summary>
[MemoryDiagnoser]
public class SystemRomBenchmarks
{
    private readonly NativeAssembler _assembler = new();
    private SystemRomWorkload? _workload;

    /// <summary>
    ///  Gets or sets the external system-ROM model.
    /// </summary>
    [Params(Apple2Model.IIe, Apple2Model.IIeEnhanced)]
    public Apple2Model Model { get; set; }

    /// <summary>
    ///  Loads external bytes and establishes exact round-trip validity outside timing.
    /// </summary>
    [GlobalSetup]
    public void Setup()
    {
        string directory = Environment.GetEnvironmentVariable("RETROCORE_IIE_ROMS")
            ?? throw new InvalidOperationException("Set RETROCORE_IIE_ROMS to the external motherboard ROM directory.");

        _workload = new(Model, directory);
        Console.WriteLine($"System-ROM input: {Model}, {_workload.Image.Length} bytes, SHA256={_workload.Sha256}");
        Validate();
    }

    /// <summary>
    ///  Decodes a complete system image sequentially, including data fallbacks.
    /// </summary>
    /// <returns>The owned analysis snapshot.</returns>
    [Benchmark]
    public DisassemblyResult Linear() => Disassembler.Analyze(Workload.LinearProject);

    /// <summary>
    ///  Traces reachable code from NMI/reset/IRQ vectors.
    /// </summary>
    /// <returns>The owned analysis snapshot.</returns>
    [Benchmark]
    public DisassemblyResult Flow() => Disassembler.Analyze(Workload.FlowProject);

    /// <summary>
    ///  Exports the precomputed linear analysis without including disassembly time.
    /// </summary>
    /// <returns>The complete owned source string.</returns>
    [Benchmark]
    public string Export() => Workload.LinearResult.ExportSource();

    /// <summary>
    ///  Parses and compiles the complete exported system-ROM source.
    /// </summary>
    /// <returns>The owned assembled image and metadata.</returns>
    [Benchmark]
    public AssemblyResult Text() => _assembler.Assemble(Workload.Source, Workload.Options);

    /// <summary>
    ///  Compiles the pre-parsed exported system-ROM model.
    /// </summary>
    /// <returns>The owned assembled image and metadata.</returns>
    [Benchmark]
    public AssemblyResult ModelAssembly() => _assembler.Assemble(Workload.Project, Workload.Options);

    /// <summary>
    ///  Rechecks complete work and exact bytes after measurement.
    /// </summary>
    [GlobalCleanup]
    public void Validate()
    {
        SystemRomWorkload workload = Workload;
        SystemRomWorkload.RequireValid(Linear());
        DisassemblyResult flow = Flow();
        SystemRomWorkload.RequireValid(flow);
        workload.Verify(Text());
        workload.Verify(ModelAssembly());
        workload.Verify(_assembler.Assemble(new AssemblySource(Export()), workload.Options));
        workload.Verify(_assembler.Assemble(flow.ToAssemblyProject(), workload.Options));
    }

    /// <summary>
    ///  Gets initialized immutable workload state rather than silently benchmarking empty input.
    /// </summary>
    private SystemRomWorkload Workload => _workload ?? throw new InvalidOperationException("Run setup first.");
}
