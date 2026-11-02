// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using BenchmarkDotNet.Attributes;
using Retrocore.Assembler;
using NativeAssembler = Retrocore.Assembler.Assembler;

namespace Retrocore.Perf;

/// <summary>
///  Measures reference-verified Merlin expansion and repeated model assembly.
/// </summary>
[MemoryDiagnoser]
public class MerlinBenchmarks
{
    private readonly NativeAssembler _assembler = new();
    private readonly AssemblySource _source = new("""
        Value   EQU 1
        Entry   LDA #Value+2*3
        :again  DEX
                BNE :again
                STR 'AB'
        """);
    private readonly AssemblyOptions _options = new(ProcessorVariant.Mos6502, 0x1000, 256)
    {
        Dialect = AssemblyDialect.Merlin
    };

    private AssemblyProject? _project;

    /// <summary>
    ///  Parses reusable syntax and validates both entry points outside measurement.
    /// </summary>
    [GlobalSetup]
    public void Setup()
    {
        AssemblyParseResult parsed = NativeAssembler.Parse(_source, _options);
        if (!parsed.Success) { throw new InvalidOperationException(parsed.Diagnostics[0].Message); }
        _project = parsed.Project;
        Validate();
    }

    /// <summary>
    ///  Expands and assembles Merlin text.
    /// </summary>
    /// <returns>The owned output.</returns>
    [Benchmark]
    public AssemblyResult Text() => _assembler.Assemble(_source, _options);

    /// <summary>
    ///  Assembles a reusable Merlin project.
    /// </summary>
    /// <returns>The owned output.</returns>
    [Benchmark]
    public AssemblyResult Model() => _assembler.Assemble(_project ?? throw new InvalidOperationException("Run setup first."), _options);

    /// <summary>
    ///  Requires exact arithmetic, branch bytes, string bytes and entry address.
    /// </summary>
    [GlobalCleanup]
    public void Validate()
    {
        foreach (AssemblyResult result in new[] { Text(), Model() })
        {
            if (!result.Success || result.Symbols["Entry"] != 0x1000)
            {
                throw new InvalidOperationException("Merlin benchmark symbols differ.");
            }

            if (!result.Files["output.bin"].Span.SequenceEqual(new byte[] { 0xA9, 9, 0xCA, 0xD0, 0xFD, 2, 0x41, 0x42 }))
            {
                throw new InvalidOperationException("Merlin benchmark bytes differ.");
            }
        }
    }
}
