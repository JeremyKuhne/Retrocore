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
///  Checks shared decimal line-number parsing.
/// </summary>
[TestClass]
public sealed class BasicSharedLineNumberTests
{
    private static string Inputs => BasicNames.Inputs;

    /// <summary>
    ///  Every AppleSoft model retains the line-number parser's bytes and labels.
    /// </summary>
    /// <param name="model">The Apple II model.</param>
    [TestMethod]
    [DataRow(Apple2Model.IIPlus)]
    [DataRow(Apple2Model.IIe)]
    [DataRow(Apple2Model.IIeEnhanced)]
    public void AppleSoftUsesSharedLineNumber(Apple2Model model)
    {
        AssemblyResult legacy = SdkModules.AssembleAppleSoft(
            SdkModules.AppleSoftPath(Inputs, BasicSourceKind.Macro10),
            model);

        AssemblyResult native = SdkModules.AssembleAppleSoft(SdkModules.AppleSoftPath(Inputs), model);
        AssemblyResult standalone = AssembleShared(legacy);
        CompareRegion(legacy, native);
        CompareRegion(legacy, standalone);
        standalone.Symbol("LINE_NUMBER_END").Should().Be(legacy.Symbol("LET"));
    }

    /// <summary>
    ///  All PET revisions use the same parser with their own workspace and branch targets.
    /// </summary>
    /// <param name="model">The PET model.</param>
    /// <param name="original">Whether BASIC 1 or 4 uses its original chip.</param>
    [TestMethod]
    [DataRow(PetModel.Pet2001, false)]
    [DataRow(PetModel.Pet2001, true)]
    [DataRow(PetModel.Pet2001Basic2, false)]
    [DataRow(PetModel.Pet4032, false)]
    [DataRow(PetModel.Pet4032, true)]
    public void SharedLineNumberMatchesPet(PetModel model, bool original)
    {
        AssemblyResult legacy = PetLegacyBasic.Assemble(Path.Join(Inputs, "Pet"), model, original);
        AssemblyResult native = AssembleShared(legacy);
        CompareRegion(legacy, native);
        native.Symbol("LINE_NUMBER_END").Should().Be(legacy.Symbol("LET"));
    }

    /// <summary>
    ///  The parser accepts the maximum line number and rejects the next.
    /// </summary>
    /// <param name="digits">The decimal text before a colon.</param>
    /// <param name="number">The expected number on success.</param>
    /// <param name="error">Whether to expect the syntax-error branch.</param>
    [TestMethod]
    [DataRow("0", 0, false)]
    [DataRow("12345", 12345, false)]
    [DataRow("63999", 63999, false)]
    [DataRow("64000", 0, true)]
    public void ParsesLineNumbersAndEnforcesTheLimit(string digits, int number, bool error)
    {
        AssemblyResult legacy = PetLegacyBasic.Assemble(Path.Join(Inputs, "Pet"), PetModel.Pet2001Basic2);
        const ushort reader = 0x5000;
        AssemblyResult native = AssembleShared(legacy, reader);
        RecordingBus bus = new();
        native.Sections[0].Bytes.Span.CopyTo(bus.Memory);
        int text = checked((int)legacy.Symbol("TXTPTR"));
        int line = checked((int)native.Symbol("LINNUM"));
        bus.Memory[text] = 0x00;
        bus.Memory[text + 1] = 0x04;
        for (int offset = 0; offset < digits.Length; offset++)
        {
            bus.Memory[0x0400 + offset] = (byte)digits[offset];
        }

        bus.Memory[0x0400 + digits.Length] = (byte)':';
        byte[] characterReader =
        [
            0xE6, (byte)text, 0xD0, 0x02, 0xE6, (byte)(text + 1),
            0xA0, 0x00, 0xB1, (byte)text, 0xC9, 0x30, 0x90, 0x06,
            0xC9, 0x3A, 0xB0, 0x02, 0x18, 0x60, 0x38, 0x60
        ];

        characterReader.CopyTo(bus.Memory, reader);
        ushort syntax = checked((ushort)native.Symbol("SNERR3"));
        ushort done = checked((ushort)native.Symbol("ONGRTS"));
        Processor<RecordingBus> cpu = new(bus)
        {
            Registers = new()
            {
                ProgramCounter = checked((ushort)native.Symbol("LINGET")),
                Accumulator = (byte)digits[0],
                StackPointer = 0xFD,
                Status = StatusRegister.Unused
            }
        };

        for (int instruction = 0; instruction < 300
            && cpu.Registers.ProgramCounter != syntax
            && cpu.Registers.ProgramCounter != done; instruction++)
        {
            cpu.StepInstruction();
        }

        cpu.Registers.ProgramCounter.Should().Be(error ? syntax : done);
        if (!error)
        {
            (bus.Memory[line] | (bus.Memory[line + 1] << 8)).Should().Be(number);
            cpu.Registers.Accumulator.Should().Be((byte)':');
            cpu.Registers.Status.HasFlag(StatusRegister.Carry).Should().BeTrue();
            (bus.Memory[text] | (bus.Memory[text + 1] << 8)).Should().Be(0x0400 + digits.Length);
        }
    }

    /// <summary>
    ///  The shared parser keeps its documentation and physical breakpoint location.
    /// </summary>
    [TestMethod]
    public void LineNumberRetainsDocumentationAndSourcePosition()
    {
        AssemblyResult native = SdkModules.AssembleAppleSoft(SdkModules.AppleSoftPath(Inputs), Apple2Model.IIeEnhanced);
        int start = checked((int)native.Symbol("LINGET"));
        int end = checked((int)native.Symbol("LET"));
        DebugTestMemory memory = new();
        memory.Set((ushort)start, native.Sections[0].Bytes.Slice(start, end - start).ToArray());
        SourceMapModule module = new(native, area: null);
        DocumentationTopic topic = module.Documentation.FindTopic("LINGET")
            ?? throw new AssertFailedException("LINGET is not documented.");

        topic.Kind.Should().Be(DocumentationKind.Routine);
        topic.Path.Should().EndWith("MsBasic.LineNumber.asm");
        DebugPosition position = module.Position(memory, (ushort)start)
            ?? throw new AssertFailedException("LINGET has no debugger source position.");

        position.Chain.Should().ContainSingle();
        position.Chain[0].Path.Should().EndWith("MsBasic.LineNumber.asm");
        module.Entries(position.Chain[0].Path, position.Chain[0].Line).Should().Contain((ushort)start);
    }

    private static AssemblyResult AssembleShared(AssemblyResult legacy, ushort? reader = null)
    {
        string folder = Path.Join(Inputs, "Microsoft6502Basic");
        string source = $"""
            .cpu Mos6502
            .org ${legacy.Symbol("LINGET"):X4}
            .include "MsBasic.LineNumber.asm"
            LINE_NUMBER_END:
            """;

        string[] dependencies = ["LINNUM", "ONGRTS", "CHARAC", "INDEX", "SNERR3", "CHRGET"];
        Dictionary<string, long> symbols = dependencies.ToDictionary(
            name => name, name => legacy.Symbol(name), StringComparer.Ordinal);

        if (reader is { } address) { symbols["CHRGET"] = address; }
        AssemblyResult native = new Assembler.Assembler().Assemble(
            new AssemblySource(BasicNames.ScopedNames(symbols) + "\n" + source, Path.Join(folder, "SharedLineNumberTest.asm")),
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
        int start = checked((int)legacy.Symbol("LINGET"));
        int end = checked((int)legacy.Symbol("LET"));
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
