// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

extern alias Generator;

using BenchmarkDotNet.Attributes;
using System.Globalization;
using GeneratorAssembly = Generator::Retrocore.Assembler;

namespace Retrocore.Perf;

/// <summary>
///  Measures the actual .NET Standard linked engine on the current .NET host, including polyfill costs.
/// </summary>
/// <remarks>
///  <para>
///   Object return types keep the generated benchmark host independent of linked/native AssemblyResult aliases.
///   This still returns the actual owned result reference; output validation is outside the timed region.
///  </para>
/// </remarks>
[MemoryDiagnoser]
public class LinkedAssemblerBenchmarks
{
    private const int SymbolCount = 256;
    private readonly GeneratorAssembly.Assembler _assembler = CreateAssembler();
    private readonly GeneratorAssembly.AssemblyOptions _options =
        new(Generator::Retrocore.Cpu.M6502.ProcessorVariant.Mos6502, origin: 0xC700, imageSize: 256);
    private readonly GeneratorAssembly.AssemblyOptions _symbolOptions =
        new(Generator::Retrocore.Cpu.M6502.ProcessorVariant.Mos6502, origin: 0x6000, imageSize: SymbolCount * 2);
    private readonly GeneratorAssembly.AssemblyProject _symbolProject = new();
    private GeneratorAssembly.AssemblySource? _source;
    private GeneratorAssembly.AssemblyProject? _project;
    private byte[]? _expected;

    /// <summary>
    ///  Builds equivalent native workloads and verifies linked-engine output before timing.
    /// </summary>
    [GlobalSetup]
    public void Setup()
    {
        string text = File.ReadAllText(Path.Join(AppContext.BaseDirectory, "Inputs", "Slot7.rom.asm"));
        string body = string.Join("\n", text.Split('\n').Select(line =>
            line.TrimStart().StartsWith(".rom ", StringComparison.Ordinal) ? "" : line));

        _source = new(body, "Slot7.rom.asm");
        GeneratorAssembly.AssemblyParseResult parsed = GeneratorAssembly.Assembler.Parse(_source);
        if (!parsed.Success) { throw new InvalidOperationException("The linked benchmark source was invalid."); }
        _project = parsed.Project;
        Retrocore.Assembler.Assembler native = new();
        _expected = native.Assemble(
            new Retrocore.Assembler.AssemblySource(body),
            new(ProcessorVariant.Mos6502, origin: 0xC700, imageSize: 256)).Sections[0].Bytes.ToArray();

        _symbolProject.Statements.Clear();
        for (int index = 0; index < SymbolCount; index++)
        {
            string name = $"LongIdentifierForAssemblySymbol_{index:D3}";
            _symbolProject.Statements.Add(new(
                GeneratorAssembly.AssemblyStatementKind.Constant,
                ".EQU",
                new(index.ToString(CultureInfo.InvariantCulture)),
                name));

            _symbolProject.Statements.Add(new(GeneratorAssembly.AssemblyStatementKind.Instruction, "LDA", new("#<" + name)));
        }

        Validate();
    }

    /// <summary>
    ///  Parses and compiles the real ROM using the linked .NET Standard implementation.
    /// </summary>
    /// <returns>The owned result.</returns>
    [Benchmark]
    public object Text() => _assembler.Assemble(
        _source ?? throw new InvalidOperationException("Run setup first."),
        _options);

    /// <summary>
    ///  Compiles the pre-parsed real ROM using the linked .NET Standard implementation.
    /// </summary>
    /// <returns>The owned result.</returns>
    [Benchmark]
    public object Model() => _assembler.Assemble(
        _project ?? throw new InvalidOperationException("Run setup first."),
        _options);

    /// <summary>
    ///  Exercises the same 256-identifier workload as the native assembler benchmark.
    /// </summary>
    /// <returns>The owned result.</returns>
    [Benchmark]
    public object Symbols() => _assembler.Assemble(_symbolProject, _symbolOptions);

    /// <summary>
    ///  Verifies actual output bytes and symbol cardinality outside the timed regions.
    /// </summary>
    [GlobalCleanup]
    public void Validate()
    {
        byte[] expected = _expected ?? throw new InvalidOperationException("Run setup first.");
        GeneratorAssembly.AssemblyResult text = (GeneratorAssembly.AssemblyResult)Text();
        GeneratorAssembly.AssemblyResult model = (GeneratorAssembly.AssemblyResult)Model();
        GeneratorAssembly.AssemblyResult symbols = (GeneratorAssembly.AssemblyResult)Symbols();
        if (!text.Success
            || !model.Success
            || !symbols.Success
            || !text.Sections[0].Bytes.Span.SequenceEqual(expected)
            || !model.Sections[0].Bytes.Span.SequenceEqual(expected)
            || symbols.Symbols.Count != SymbolCount
            || symbols.Sections[0].Bytes.Length != SymbolCount * 2)
        {
            throw new InvalidOperationException("Linked benchmark output differed from its native workload.");
        }

        ReadOnlySpan<byte> bytes = symbols.Sections[0].Bytes.Span;
        for (int index = 0; index < SymbolCount; index++)
        {
            if (bytes[index * 2] != 0xA9 || bytes[index * 2 + 1] != index)
            {
                throw new InvalidOperationException("Linked symbol benchmark output was invalid.");
            }
        }
    }

    /// <summary>
    ///  Parses the CPU description with the linked parser, without timing setup or Roslyn.
    /// </summary>
    /// <returns>The linked engine with the same MOS 6502 encodings as the native library.</returns>
    private static GeneratorAssembly.Assembler CreateAssembler() =>
        new(Generator::Retrocore.Isa.IsaParser.Parse(OpcodeTable.DescriptionText).InstructionSets);
}
