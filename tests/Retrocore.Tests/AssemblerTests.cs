// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

extern alias Generator;

using Retrocore.Assembler;
using GeneratorAssembly = Generator::Retrocore.Assembler;
using NativeAssembler = Retrocore.Assembler.Assembler;

namespace Retrocore.Tests;

/// <summary>
///  Public model, runtime encoding and linked-generator parity without Roslyn in the library API.
/// </summary>
[TestClass]
public class AssemblerTests
{
    /// <summary>
    ///  Checks span classification accepts mixed-case directives without modifying caller-owned operation text.
    /// </summary>
    /// <param name="operation">The unnormalized operation.</param>
    /// <param name="kind">The expected syntax category.</param>
    /// <param name="operand">Valid syntax for this category.</param>
    [TestMethod]
    [DataRow("", AssemblyStatementKind.Label, "")]
    [DataRow("nOp", AssemblyStatementKind.Instruction, "")]
    [DataRow(".eQu", AssemblyStatementKind.Constant, "1")]
    [DataRow(".rEs", AssemblyStatementKind.Reserve, "1")]
    [DataRow(".oRg", AssemblyStatementKind.Origin, "0")]
    [DataRow(".cPu", AssemblyStatementKind.Cpu, "Mos6502")]
    [DataRow(".bYtE", AssemblyStatementKind.Data, "1")]
    [DataRow(".wOrD", AssemblyStatementKind.Data, "1")]
    [DataRow(".aSsErT", AssemblyStatementKind.Assertion, "1")]
    [DataRow(".eXpOrT", AssemblyStatementKind.Export, "Entry")]
    public void ModelClassificationDoesNotRequireNormalizedText(
        string operation,
        AssemblyStatementKind kind,
        string operand)
    {
        NativeAssembler assembler = new();
        AssemblyProject project = new();
        project.Statements.Add(new(AssemblyStatementKind.Label, "", label: "Entry"));
        AssemblyStatement node = new(
            kind,
            operation,
            new(operand),
            label: kind == AssemblyStatementKind.Constant ? "Value" : null);

        project.Statements.Add(node);
        AssemblyResult result = assembler.Assemble(project, new(ProcessorVariant.Mos6502, origin: 0, imageSize: 8));
        result.Diagnostics.Should().BeEmpty();
        node.Operation.Should().BeSameAs(operation);
    }

    /// <summary>
    ///  Checks length buckets and whole-span comparisons cannot accept directive prefixes or near matches.
    /// </summary>
    /// <param name="operation">An unknown directive.</param>
    [TestMethod]
    [DataRow(".")]
    [DataRow(".eq")]
    [DataRow(".eqx")]
    [DataRow(".equx")]
    [DataRow(".byteSuffix")]
    [DataRow(".word ")]
    [DataRow(".asseRtX")]
    [DataRow(".exporx")]
    [DataRow(".exportx")]
    [DataRow(" .byte")]
    public void ModelClassificationRejectsUnknownDirectives(string operation)
    {
        NativeAssembler assembler = new();
        AssemblyProject project = new();
        project.Statements.Add(new(AssemblyStatementKind.Data, operation, new("1")));
        AssemblyResult result = assembler.Assemble(project, new(ProcessorVariant.Mos6502, origin: 0, imageSize: 8));
        result.Success.Should().BeFalse();
        result.Diagnostics.Should().ContainSingle(diagnostic => diagnostic.StatementIndex == 0);
    }

    /// <summary>
    ///  Checks reused declaration metadata is copied before callers edit labels, locations or statement kinds.
    /// </summary>
    [TestMethod]
    public void DeclarationReusePreservesIndependentSymbolSnapshots()
    {
        NativeAssembler assembler = new();
        AssemblyParseResult parsed = NativeAssembler.Parse(new("entry: lda #1\nValue = 2", "original.asm"));
        AssemblyOptions options = new(ProcessorVariant.Mos6502, origin: 0x2000, imageSize: 8);
        AssemblyResult first = assembler.Assemble(parsed.Project, options);
        first.Success.Should().BeTrue();
        parsed.Project.Statements[0].Label = "changed";
        parsed.Project.Statements[0].Location = new("edited.asm", line: 9);
        parsed.Project.Statements[1] = new(AssemblyStatementKind.Label, "", label: "Value");
        AssemblyResult second = assembler.Assemble(parsed.Project, options);
        second.Success.Should().BeTrue();
        first.SymbolDefinitions.Single(symbol => symbol.Name == "entry").Location?.Path.Should().Be("original.asm");
        first.SymbolDefinitions.Single(symbol => symbol.Name == "Value").IsConstant.Should().BeTrue();
        second.SymbolDefinitions.Single(symbol => symbol.Name == "Value").IsConstant.Should().BeFalse();
        first.SourceMap[0].Label.Should().Be("entry");
        second.SourceMap[0].Label.Should().Be("changed");
        first.SourceMap.Where(entry => entry.Operation.StartsWith('.'))
            .Should().OnlyContain(entry => entry.AddressMode == "");
    }

    /// <summary>
    ///  Checks runtime and polyfilled null guards preserve their exception type and parameter names.
    /// </summary>
    [TestMethod]
    public void NullArgumentsRetainParameterNames()
    {
        NativeAssembler assembler = new();
        AssemblyOptions options = new(ProcessorVariant.Mos6502, origin: 0, imageSize: 8);
        (Action Action, string ParameterName)[] checks =
        [
#pragma warning disable CS8625 // Exercise the public null guards.
            (() => NativeAssembler.Parse(source: null), "source"),
            (() => GeneratorAssembly.Assembler.Parse(source: null), "source"),
            (() => assembler.Assemble(new AssemblySource("nop"), options: null), "options"),
            (() => assembler.Assemble(project: null, options), "project"),
            (() => assembler.Assemble(new AssemblyProject(), options: null), "options"),
            (() => new AssemblyLocation(path: null, line: 0), "path"),
            (() => AssemblyOperand.Immediate(expression: null), "expression"),
            (() => AssemblyOperand.Value(expression: null), "expression"),
            (() => new GeneratorAssembly.AssemblyLocation(path: null, line: 0), "path"),
            (() => GeneratorAssembly.AssemblyOperand.Immediate(expression: null), "expression"),
            (() => GeneratorAssembly.AssemblyOperand.Value(expression: null), "expression")
#pragma warning restore CS8625
        ];

        foreach ((Action action, string parameterName) in checks)
        {
            action.Should().Throw<ArgumentNullException>().WithParameterName(parameterName);
        }
    }

    /// <summary>
    ///  Checks text and programmatic assembly use identical layout/encoding and real typed symbols.
    /// </summary>
    [TestMethod]
    public void TextAndProgrammaticModelsProduceIdenticalImages()
    {
        NativeAssembler assembler = new();
        AssemblyOptions options = new(ProcessorVariant.Mos6502, origin: 0x6000, imageSize: 16);
        AssemblySource source = new("entry: lda #1\nsta $42\nbne entry\n.export entry", "sample.asm");
        AssemblyResult text = assembler.Assemble(source, options);
        text.Success.Should().BeTrue();
        AssemblyProject model = new();
        model.Statements.Add(
            new(
                AssemblyStatementKind.Instruction,
                "LDA",
                AssemblyOperand.Immediate(
                    AssemblyExpression.Integer(
                        1)),
                "entry"));

        model.Statements.Add(new(AssemblyStatementKind.Instruction, "STA", AssemblyOperand.Value(new("$42"))));
        model.Statements.Add(new(AssemblyStatementKind.Instruction, "BNE", new("entry")));
        model.Statements.Add(new(AssemblyStatementKind.Export, ".export", new("entry")));
        AssemblyResult built = assembler.Assemble(model, options);
        built.Success.Should().BeTrue();
        built.Sections[0].Bytes.ToArray().Should().Equal(text.Sections[0].Bytes.ToArray());
        built.Sections[0].Bytes.Span[..6].ToArray().Should().Equal(0xA9, 1, 0x85, 0x42, 0xD0, 0xFA);
        built.SymbolDefinitions.Single().IsExported.Should().BeTrue();
        built.SymbolDefinitions.Single().Value.Should().Be(0x6000);
        text.SourceMap[0].Location?.Path.Should().Be("sample.asm");
        built.SourceMap[0].Location.Should().BeNull();
    }

    /// <summary>
    ///  Checks repeated assembly and model edits do not mutate old output or retained resolved syntax.
    /// </summary>
    [TestMethod]
    public void EditingParsedModelsPreservesOldResultSnapshots()
    {
        NativeAssembler assembler = new();
        AssemblyOptions options = new(ProcessorVariant.Mos6502, origin: 0, imageSize: 8);
        AssemblyParseResult parsed = NativeAssembler.Parse(new("value = 1\nlda #value\n.export value", "edit.asm"));
        parsed.Success.Should().BeTrue();
        parsed.Project.Sources.Single().Text.Should().Contain("value = 1");
        AssemblyResult first = assembler.Assemble(parsed.Project, options);
        parsed.Project.Statements[0].Operand = new("2");
        parsed.Project.Statements[1].Operation = "LDX";
        AssemblyResult second = assembler.Assemble(parsed.Project, options);
        first.Sections[0].Bytes.Span[0].Should().Be(0xA9);
        first.Sections[0].Bytes.Span[1].Should().Be(1);
        first.SourceMap[1].Operation.Should().Be("LDA");
        first.SymbolDefinitions.Single().IsConstant.Should().BeTrue();
        second.Sections[0].Bytes.Span[0].Should().Be(0xA2);
        second.Sections[0].Bytes.Span[1].Should().Be(2);
    }

    /// <summary>
    ///  Checks runtime selectors use the same CPU metadata as generator encoding.
    /// </summary>
    /// <param name="variant">An existing CPU variant.</param>
    [TestMethod]
    [DataRow(ProcessorVariant.Mos6502)]
    [DataRow(ProcessorVariant.Wdc65C02)]
    [DataRow(ProcessorVariant.Rockwell65C02)]
    public void RuntimeEncodingMatchesExistingCpuMetadata(ProcessorVariant variant)
    {
        NativeAssembler assembler = new();
        AssemblyResult result = assembler.Assemble(
            new AssemblySource("lda #$34\nsta $1234\nrts"),
            new(variant, origin: 0, imageSize: 8));

        result.Success.Should().BeTrue();
        result.Sections[0].Bytes.Span[..6].ToArray().Should().Equal(0xA9, 0x34, 0x8D, 0x34, 0x12, 0x60);
        result.SourceMap[1].AddressMode.Should().Be("Absolute");
    }

    /// <summary>
    ///  Checks native source/model failures are diagnostic results, not successful empty bytes.
    /// </summary>
    [TestMethod]
    public void InvalidSourceAndModelsHaveStructuredDiagnostics()
    {
        NativeAssembler assembler = new();
        AssemblyOptions options = new(ProcessorVariant.Mos6502, origin: 0, imageSize: 16);
        AssemblyResult unresolved = assembler.Assemble(new AssemblySource("\nlda #missing", "bad.asm"), options);
        unresolved.Success.Should().BeFalse();
        unresolved.Sections.Should().BeEmpty();
        unresolved.Diagnostics.Single().Location?.Line.Should().Be(1);
        AssemblyProject model = new();
        model.Statements.Add(new(AssemblyStatementKind.Data, "LDA", new("#1")));
        AssemblyResult badKind = assembler.Assemble(model, options);
        badKind.Diagnostics.Single().StatementIndex.Should().Be(0);
        badKind.Diagnostics.Single().Location.Should().BeNull();
        NativeAssembler.Parse(new(".rom A.B,0,16")).Diagnostics.Single().Message.Should().Contain("Unsupported");
        Action invalidOptions = () => new AssemblyOptions(ProcessorVariant.Mos6502, origin: 65535, imageSize: 2);
        invalidOptions.Should().Throw<ArgumentOutOfRangeException>();
        Action cancel = () => NativeAssembler.Parse(new("nop"), new CancellationToken(canceled: true));
        cancel.Should().Throw<OperationCanceledException>();
    }

    /// <summary>
    ///  Checks diagnostics identify an edited node rather than guessing from duplicate source lines.
    /// </summary>
    [TestMethod]
    public void ModelDiagnosticsRetainNodeIdentityAndSourceLocation()
    {
        NativeAssembler assembler = new();
        AssemblyProject project = new();
        project.Statements.Add(new(AssemblyStatementKind.Instruction, "NOP") { Location = new("first.asm", line: 0) });
        project.Statements.Add(new(AssemblyStatementKind.Instruction, "LDA", new("#missing"))
        {
            Location = new("second.asm", line: 0)
        });

        AssemblyResult result = assembler.Assemble(project, new(ProcessorVariant.Mos6502, origin: 0, imageSize: 8));
        result.Diagnostics.Single().StatementIndex.Should().Be(1);
        result.Diagnostics.Single().Location?.Path.Should().Be("second.asm");
        project.Statements[1].Location = null;
        result = assembler.Assemble(project, new(ProcessorVariant.Mos6502, origin: 0, imageSize: 8));
        result.Diagnostics.Single().StatementIndex.Should().Be(1);
        result.Diagnostics.Single().Location.Should().BeNull();
    }

    /// <summary>
    ///  Checks runtime compilation of the actual annotated firmware body matches generated ROM bytes.
    /// </summary>
    [TestMethod]
    public void RuntimeEngineMatchesTheSelfHostedSlotSevenImage()
    {
        string original = File.ReadAllText(Path.Join(AppContext.BaseDirectory, "Inputs", "Slot7.rom.asm"));
        string body = string.Join("\n", original.Split('\n').Select(line =>
            line.TrimStart().StartsWith(".rom ", StringComparison.Ordinal) ? "" : line));

        NativeAssembler assembler = new();
        AssemblyResult result = assembler.Assemble(
            new AssemblySource(body, "Slot7.rom.asm"),
            new(ProcessorVariant.Mos6502, origin: 0xC700, imageSize: 256));

        result.Success.Should().BeTrue();
        result.Sections[0].Bytes.ToArray().Should().Equal(Retrocore.Machines.Apple2.Slot7Rom.Bytes.ToArray());
        result.Exports["DriverEntry"].Should().Be(Retrocore.Machines.Apple2.Slot7Rom.DriverEntry);
        result.Exports["DeviceInfo"].Should().Be(Retrocore.Machines.Apple2.Slot7Rom.DeviceInfo);
    }
}
