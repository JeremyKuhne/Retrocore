// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using BenchmarkDotNet.Attributes;
using Retrocore.Assembler;
using NativeAssembler = Retrocore.Assembler.Assembler;

namespace Retrocore.Perf;

/// <summary>
///  Measures ca65 expansion and single-object linking with verified bytes and exported addresses.
/// </summary>
[MemoryDiagnoser]
public class Ca65Benchmarks
{
    private readonly NativeAssembler _assembler = new();
    private readonly AssemblySource _source = new("""
        .setcpu "6502"
        .export Entry, Buffer
        .segment "CODE"
        .proc Entry
        lda #$42
        sta Buffer
        bne :+
        :rts
        .endproc
        .segment "BSS"
        Buffer: .res 1
        """);
    private readonly AssemblyOptions _options = new(ProcessorVariant.Mos6502, 0x1000, 0x6800)
    {
        Dialect = AssemblyDialect.Ca65,
        BuildTime = DateTimeOffset.UnixEpoch
    };

    private AssemblyProject? _project;

    /// <summary>
    ///  Parses reusable input and checks both entry points outside timing.
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
    ///  Parses and links a fresh ca65 object.
    /// </summary>
    /// <returns>The owned output snapshot.</returns>
    [Benchmark]
    public AssemblyResult Text() => _assembler.Assemble(_source, _options);

    /// <summary>
    ///  Links an editable pre-expanded ca65 object without mutating it.
    /// </summary>
    /// <returns>The owned output snapshot.</returns>
    [Benchmark]
    public AssemblyResult Model() => _assembler.Assemble(_project ?? throw new InvalidOperationException("Run setup first."), _options);

    /// <summary>
    ///  Requires nonempty exact bytes, load addresses, exports and no-output BSS.
    /// </summary>
    [GlobalCleanup]
    public void Validate()
    {
        foreach (AssemblyResult result in new[] { Text(), Model() })
        {
            if (!result.Success
                || !result.Files["output.bin"].Span.SequenceEqual(new byte[]
                {
                    0xA9, 0x42, 0x8D, 8, 0x10, 0xD0, 0, 0x60
                })
                || result.Exports["Entry"] != 0x1000
                || result.Exports["Buffer"] != 0x1008
                || result.Sections.Single(section => section.Name == "BSS").Bytes.Length != 0)
            {
                throw new InvalidOperationException("The ca65 benchmark bytes or symbol addresses differ.");
            }
        }
    }
}
