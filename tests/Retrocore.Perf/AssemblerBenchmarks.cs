// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using BenchmarkDotNet.Attributes;
using Retrocore.Assembler;
using System.Globalization;
using NativeAssembler = Retrocore.Assembler.Assembler;

namespace Retrocore.Perf;

/// <summary>
///  Measures the real ROM workload through text and pre-parsed model entry points.
/// </summary>
[MemoryDiagnoser]
public class AssemblerBenchmarks
{
    private readonly NativeAssembler _assembler = new();
    private readonly AssemblyOptions _options = new(ProcessorVariant.Mos6502, origin: 0xC700, imageSize: 256);
    private AssemblySource? _source;
    private AssemblyProject? _project;
    private readonly AssemblyProject _symbolProject = new();
    private readonly AssemblyOptions _symbolOptions = new(ProcessorVariant.Mos6502, origin: 0x6000, imageSize: SymbolCount * 2);
    private readonly AssemblyProject _dataProject = new();
    private readonly AssemblyOptions _dataOptions = new(ProcessorVariant.Mos6502, origin: 0x1000, imageSize: DataSize);

    private const int SymbolCount = 256;

    private const int DataLines = 200;

    private const int DataLineLength = 16;

    private const int DataSize = 4096;

    /// <summary>
    ///  Loads and verifies the actual ROM source outside timing.
    /// </summary>
    [GlobalSetup]
    public void Setup()
    {
        string text = File.ReadAllText(Path.Join(AppContext.BaseDirectory, "Inputs", "Slot7.rom.asm"));
        string body = string.Join("\n", text.Split('\n').Select(line =>
            line.TrimStart().StartsWith(".rom ", StringComparison.Ordinal) ? "" : line));

        _source = new(body, "Slot7.rom.asm");
        AssemblyParseResult parsed = NativeAssembler.Parse(_source);
        if (!parsed.Success) { throw new InvalidOperationException(parsed.Diagnostics[0].Message); }
        _project = parsed.Project;
        Verify(_assembler.Assemble(_project, _options));
        _symbolProject.Statements.Clear();
        for (int index = 0; index < SymbolCount; index++)
        {
            string name = $"LongIdentifierForAssemblySymbol_{index:D3}";
            _symbolProject.Statements.Add(new(
                AssemblyStatementKind.Constant,
                ".EQU",
                new(index.ToString(CultureInfo.InvariantCulture)),
                name));

            _symbolProject.Statements.Add(new(AssemblyStatementKind.Instruction, "LDA", new("#<" + name)));
        }

        VerifySymbols(Symbols());

        // A forward zero-page reference forces a second layout pass over every data line.
        _dataProject.Statements.Clear();
        _dataProject.Statements.Add(new(AssemblyStatementKind.Instruction, "LDA", new("Forward")));
        for (int line = 0; line < DataLines; line++)
        {
            string[] values = new string[DataLineLength];
            for (int column = 0; column < values.Length; column++)
            {
                values[column] = "$" + ((line + column) & byte.MaxValue).ToString("X2", CultureInfo.InvariantCulture);
            }

            _dataProject.Statements.Add(new(AssemblyStatementKind.Data, ".byte", new(string.Join(", ", values))));
        }

        _dataProject.Statements.Add(new(AssemblyStatementKind.Constant, ".EQU", new("$10"), "Forward"));
        VerifyData(Data());
    }

    /// <summary>
    ///  Parses and compiles annotated ROM text.
    /// </summary>
    /// <returns>The owned output snapshot.</returns>
    [Benchmark]
    public AssemblyResult Text() => _assembler.Assemble(
        _source ?? throw new InvalidOperationException("Run setup first."),
        _options);

    /// <summary>
    ///  Compiles a reusable editable model.
    /// </summary>
    /// <returns>The owned output snapshot.</returns>
    [Benchmark]
    public AssemblyResult Model() => _assembler.Assemble(
        _project ?? throw new InvalidOperationException("Run setup first."),
        _options);

    /// <summary>
    ///  Compiles 256 named constants and references to exercise long-identifier lookup and numeric parsing.
    /// </summary>
    /// <returns>The owned output snapshot.</returns>
    [Benchmark]
    public AssemblyResult Symbols() => _assembler.Assemble(_symbolProject, _symbolOptions);

    /// <summary>
    ///  Compiles 200 sixteen-element .byte lines laid out twice because of a forward reference.
    /// </summary>
    /// <returns>The owned output snapshot.</returns>
    [Benchmark]
    public AssemblyResult Data() => _assembler.Assemble(_dataProject, _dataOptions);

    /// <summary>
    ///  Verifies repeated model compilation outside timing.
    /// </summary>
    [GlobalCleanup]
    public void Validate()
    {
        Verify(Model());
        VerifySymbols(Symbols());
        VerifyData(Data());
    }

    /// <summary>
    ///  Checks the zero-page load and every data byte outside the timed region.
    /// </summary>
    /// <param name="result">The compiled data table.</param>
    private static void VerifyData(AssemblyResult result)
    {
        if (!result.Success) { throw new InvalidOperationException("The data benchmark did not assemble."); }
        ReadOnlySpan<byte> bytes = result.Sections[0].Bytes.Span;
        if (bytes[0] != 0xA5 || bytes[1] != 0x10)
        {
            throw new InvalidOperationException("The data benchmark did not shrink its forward reference.");
        }

        for (int line = 0; line < DataLines; line++)
        {
            for (int column = 0; column < DataLineLength; column++)
            {
                if (bytes[2 + (line * DataLineLength) + column] != ((line + column) & byte.MaxValue))
                {
                    throw new InvalidOperationException("The data benchmark emitted an incorrect byte.");
                }
            }
        }
    }

    /// <summary>
    ///  Checks every expected instruction and symbol outside the timed region.
    /// </summary>
    /// <param name="result">The complete synthetic assembly result.</param>
    private static void VerifySymbols(AssemblyResult result)
    {
        if (!result.Success
            || result.Sections[0].Bytes.Length != SymbolCount * 2
            || result.Symbols.Count != SymbolCount)
        {
            throw new InvalidOperationException("The symbol benchmark output was invalid.");
        }

        ReadOnlySpan<byte> bytes = result.Sections[0].Bytes.Span;
        for (int index = 0; index < SymbolCount; index++)
        {
            if (bytes[index * 2] != 0xA9 || bytes[index * 2 + 1] != index)
            {
                throw new InvalidOperationException("The symbol benchmark emitted an incorrect instruction.");
            }
        }
    }

    private static void Verify(AssemblyResult result)
    {
        if (!result.Success || result.Sections[0].Bytes.Length != 256 || result.Exports["DriverEntry"] != 0xC740)
        {
            throw new InvalidOperationException("ROM benchmark output was invalid.");
        }
    }
}
