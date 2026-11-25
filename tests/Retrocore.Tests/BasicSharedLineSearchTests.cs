// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Debug;
using Retrocore.Documentation;
using Retrocore.Machines.Apple2;
using Retrocore.Machines.Commodore;

namespace Retrocore.Tests;

/// <summary>
///  Checks the shared program-line search.
/// </summary>
[TestClass]
public sealed class BasicSharedLineSearchTests
{
    private static string Inputs => BasicNames.Inputs;

    /// <summary>
    ///  The shared search retains AppleSoft's bytes and labels for every model.
    /// </summary>
    /// <param name="model">The Apple II model.</param>
    [TestMethod]
    [DataRow(Apple2Model.IIPlus)]
    [DataRow(Apple2Model.IIe)]
    [DataRow(Apple2Model.IIeEnhanced)]
    public void AppleSoftUsesSharedLineSearch(Apple2Model model)
    {
        AssemblyResult legacy = SdkModules.AssembleAppleSoft(
            SdkModules.AppleSoftPath(Inputs, BasicSourceKind.Macro10),
            model);

        AssemblyResult native = SdkModules.AssembleAppleSoft(SdkModules.AppleSoftPath(Inputs), model);
        AssemblyResult standalone = AssembleShared(legacy);
        CompareRegion(legacy, native);
        CompareRegion(legacy, standalone);
        standalone.Symbol("LINE_SEARCH_END").Should().Be(legacy.Symbol("SCRATH"));
    }

    /// <summary>
    ///  All PET revisions use the same search with their own workspace.
    /// </summary>
    /// <param name="model">The PET model.</param>
    /// <param name="original">Whether BASIC 1 or 4 uses its original chip.</param>
    [TestMethod]
    [DataRow(PetModel.Pet2001, false)]
    [DataRow(PetModel.Pet2001, true)]
    [DataRow(PetModel.Pet2001Basic2, false)]
    [DataRow(PetModel.Pet4032, false)]
    [DataRow(PetModel.Pet4032, true)]
    public void SharedLineSearchMatchesPet(PetModel model, bool original)
    {
        AssemblyResult legacy = PetLegacyBasic.Assemble(Path.Join(Inputs, "Pet"), model, original);
        AssemblyResult native = AssembleShared(legacy);
        CompareRegion(legacy, native);
        native.Symbol("LINE_SEARCH_END").Should().Be(legacy.Symbol("SCRATH"));
    }

    /// <summary>
    ///  Search returns the matching, next or end link, with carry set only for a match.
    /// </summary>
    /// <param name="line">The requested line number.</param>
    /// <param name="pointer">The expected link address.</param>
    /// <param name="found">Whether the line exists.</param>
    [TestMethod]
    [DataRow(1, 0x2000, false)]
    [DataRow(10, 0x2000, true)]
    [DataRow(20, 0x2006, false)]
    [DataRow(30, 0x2006, true)]
    [DataRow(40, 0x200C, false)]
    public void SearchFindsTheMatchOrInsertionPoint(int line, int pointer, bool found)
    {
        AssemblyResult legacy = PetLegacyBasic.Assemble(Path.Join(Inputs, "Pet"), PetModel.Pet2001Basic2);
        AssemblyResult native = AssembleShared(legacy);
        RecordingBus bus = new();
        native.Sections[0].Bytes.Span.CopyTo(bus.Memory);
        int text = checked((int)native.Symbol("TXTTAB"));
        int number = checked((int)native.Symbol("LINNUM"));
        int result = checked((int)native.Symbol("LOWTR"));
        bus.Memory[text] = 0x00;
        bus.Memory[text + 1] = 0x20;
        bus.Memory[number] = (byte)line;
        bus.Memory[number + 1] = (byte)(line >> 8);
        byte[] program = [0x06, 0x20, 10, 0, (byte)'A', 0, 0x0C, 0x20, 30, 0, (byte)'B', 0, 0, 0];
        program.CopyTo(bus.Memory, 0x2000);
        const ushort complete = 0x4000;
        bus.Memory[0x01FE] = (byte)((complete - 1) & 0xFF);
        bus.Memory[0x01FF] = (byte)((complete - 1) >> 8);
        Processor<RecordingBus> cpu = new(bus)
        {
            Registers = new()
            {
                ProgramCounter = checked((ushort)native.Symbol("FNDLIN")),
                StackPointer = 0xFD,
                Status = StatusRegister.Unused
            }
        };

        for (int instruction = 0; instruction < 100 && cpu.Registers.ProgramCounter != complete; instruction++)
        {
            cpu.StepInstruction();
        }

        cpu.Registers.ProgramCounter.Should().Be(complete);
        (bus.Memory[result] | (bus.Memory[result + 1] << 8)).Should().Be(pointer);
        cpu.Registers.Status.HasFlag(StatusRegister.Carry).Should().Be(found);
    }

    /// <summary>
    ///  The documented entry retains its breakpoint-capable source position.
    /// </summary>
    [TestMethod]
    public void LineSearchRetainsDocumentationAndSourcePosition()
    {
        AssemblyResult native = SdkModules.AssembleAppleSoft(SdkModules.AppleSoftPath(Inputs), Apple2Model.IIeEnhanced);
        int start = checked((int)native.Symbol("FNDLIN"));
        int end = checked((int)native.Symbol("SCRATH"));
        DebugTestMemory memory = new();
        memory.Set((ushort)start, native.Sections[0].Bytes.Slice(start, end - start).ToArray());
        SourceMapModule module = new(native, area: null);
        DocumentationTopic topic = module.Documentation.FindTopic("FNDLIN")
            ?? throw new AssertFailedException("FNDLIN is not documented.");

        topic.Kind.Should().Be(DocumentationKind.Routine);
        topic.Path.Should().EndWith("MsBasic.LineSearch.asm");
        DebugPosition position = module.Position(memory, (ushort)start)
            ?? throw new AssertFailedException("FNDLIN has no debugger source position.");

        position.Chain.Should().ContainSingle();
        position.Chain[0].Path.Should().EndWith("MsBasic.LineSearch.asm");
        module.Entries(position.Chain[0].Path, position.Chain[0].Line).Should().Contain((ushort)start);
    }

    private static AssemblyResult AssembleShared(AssemblyResult legacy)
    {
        string folder = Path.Join(Inputs, "Microsoft6502Basic");
        string source = $"""
            .cpu Mos6502
            .org ${legacy.Symbol("FNDLIN"):X4}
            .include "MsBasic.LineSearch.asm"
            LINE_SEARCH_END:
            """;

        string[] dependencies = ["TXTTAB", "LOWTR", "LINNUM"];
        Dictionary<string, long> symbols = dependencies.ToDictionary(
            name => name, name => legacy.Symbol(name), StringComparer.Ordinal);

        AssemblyResult native = new Assembler.Assembler().Assemble(
            new AssemblySource(source, Path.Join(folder, "SharedLineSearchTest.asm")),
            new AssemblyOptions(ProcessorVariant.Mos6502, 0, 0x10000)
            {
                SourceResolver = new FileAssemblySourceResolver(),
                PredefinedSymbols = BasicNames.WithCurrentNames(symbols)
            });

        native.Success.Should().BeTrue(string.Join(Environment.NewLine, native.Diagnostics.Select(diagnostic =>
            $"{diagnostic.Location?.Path}:{diagnostic.Location?.Line + 1}: {diagnostic.Message}")));

        return native;
    }

    private static void CompareRegion(AssemblyResult legacy, AssemblyResult native)
    {
        int start = checked((int)legacy.Symbol("FNDLIN"));
        int end = checked((int)legacy.Symbol("SCRATH"));
        foreach (AssemblySymbol label in legacy.SymbolDefinitions.Where(
            symbol => !symbol.IsConstant && symbol.Value >= start && symbol.Value < end))
        {
            native.SymbolsWithHistoricalNames.Should().ContainKey(label.Name);
            native.Symbol(label.Name).Should().Be(label.Value, $"{label.Name} must retain its ROM address");
        }

        native.Sections[0].Bytes.Slice(start, end - start).ToArray()
            .Should().Equal(legacy.Sections[0].Bytes.Slice(start, end - start).ToArray());
    }
}
