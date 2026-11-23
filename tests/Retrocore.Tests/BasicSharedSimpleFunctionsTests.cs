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
///  Checks shared free-space, position and integer-to-float entries.
/// </summary>
[TestClass]
public sealed class BasicSharedSimpleFunctionsTests
{
    private static string Inputs => BasicNames.Inputs;

    /// <summary>
    ///  The shared routines retain AppleSoft's bytes and labels for every model.
    /// </summary>
    /// <param name="model">The Apple II model.</param>
    [TestMethod]
    [DataRow(Apple2Model.IIPlus)]
    [DataRow(Apple2Model.IIe)]
    [DataRow(Apple2Model.IIeEnhanced)]
    public void AppleSoftUsesSharedFunctions(Apple2Model model)
    {
        AssemblyResult legacy = SdkModules.AssembleAppleSoft(
            SdkModules.AppleSoftPath(Inputs, BasicSourceKind.Macro10),
            model);

        AssemblyResult native = SdkModules.AssembleAppleSoft(SdkModules.AppleSoftPath(Inputs), model);
        AssemblyResult standalone = AssembleShared(legacy, setCarry: true);
        CompareRegion(legacy, native);
        CompareRegion(legacy, standalone);
        standalone.Symbol("SIMPLE_FUNCTIONS_END").Should().Be(legacy.Symbol("ERRDIR"));
    }

    /// <summary>
    ///  All PET revisions use the same code, with their own workspace and system entries.
    /// </summary>
    /// <param name="model">The PET model.</param>
    /// <param name="original">Whether BASIC 1 or 4 uses its original chip.</param>
    [TestMethod]
    [DataRow(PetModel.Pet2001, false)]
    [DataRow(PetModel.Pet2001, true)]
    [DataRow(PetModel.Pet2001Basic2, false)]
    [DataRow(PetModel.Pet4032, false)]
    [DataRow(PetModel.Pet4032, true)]
    public void SharedFunctionsMatchPet(PetModel model, bool original)
    {
        AssemblyResult legacy = PetLegacyBasic.Assemble(Path.Join(Inputs, "Pet"), model, original);
        AssemblyResult native = AssembleShared(legacy, setCarry: false);
        CompareRegion(legacy, native);
        native.Symbol("SIMPLE_FUNCTIONS_END").Should().Be(legacy.Symbol("ERRDIR"));
    }

    /// <summary>
    ///  The SNGFLT entry either sets carry or preserves the caller's carry before conversion.
    /// </summary>
    /// <param name="setCarry">Whether to emit AppleSoft's extra SEC.</param>
    /// <param name="initialCarry">The carry on entry.</param>
    /// <param name="expectedCarry">The carry at GIVAYF.</param>
    [TestMethod]
    [DataRow(false, false, false)]
    [DataRow(false, true, true)]
    [DataRow(true, false, true)]
    [DataRow(true, true, true)]
    public void FloatByteEntryPreservesOrSetsCarry(bool setCarry, bool initialCarry, bool expectedCarry)
    {
        AssemblyResult legacy = PetLegacyBasic.Assemble(Path.Join(Inputs, "Pet"), PetModel.Pet2001Basic2);
        AssemblyResult native = AssembleShared(legacy, setCarry);
        RecordingBus bus = new();
        native.Sections[0].Bytes.Span.CopyTo(bus.Memory);
        ushort target = checked((ushort)native.Symbol("GIVAYF"));
        Processor<RecordingBus> cpu = new(bus)
        {
            Registers = new()
            {
                ProgramCounter = checked((ushort)native.Symbol("SNGFLT")),
                Y = 42,
                Status = initialCarry ? StatusRegister.Unused | StatusRegister.Carry : StatusRegister.Unused
            }
        };

        for (int instruction = 0; instruction < 4 && cpu.Registers.ProgramCounter != target; instruction++)
        {
            cpu.StepInstruction();
        }

        cpu.Registers.ProgramCounter.Should().Be(target);
        cpu.Registers.Y.Should().Be(42);
        cpu.Registers.Status.HasFlag(StatusRegister.Carry).Should().Be(expectedCarry);
    }

    /// <summary>
    ///  The shared definitions are documented and can be used as breakpoint locations.
    /// </summary>
    [TestMethod]
    public void FunctionsRetainDocumentationAndSourcePositions()
    {
        AssemblyResult native = SdkModules.AssembleAppleSoft(SdkModules.AppleSoftPath(Inputs), Apple2Model.IIeEnhanced);
        int start = checked((int)native.Symbol("FRE"));
        int end = checked((int)native.Symbol("ERRDIR"));
        DebugTestMemory memory = new();
        memory.Set((ushort)start, native.Sections[0].Bytes.Slice(start, end - start).ToArray());
        SourceMapModule module = new(native, area: null);
        foreach (string name in (string[])["FRE", "GIVAYF", "POS", "SNGFLT"])
        {
            DocumentationTopic topic = module.Documentation.FindTopic(name)
                ?? throw new AssertFailedException($"{name} is not documented.");

            topic.Kind.Should().Be(DocumentationKind.Routine);
            topic.Path.Should().EndWith("MsBasic.SimpleFunctions.asm");
            ushort address = checked((ushort)native.Symbol(name));
            DebugPosition position = module.Position(memory, address)
                ?? throw new AssertFailedException($"{name} has no debugger source position.");

            position.Chain[0].Path.Should().EndWith("MsBasic.SimpleFunctions.asm");
            module.Entries(position.Chain[0].Path, position.Chain[0].Line).Should().Contain(address);
        }
    }

    private static AssemblyResult AssembleShared(AssemblyResult legacy, bool setCarry)
    {
        string folder = Path.Join(Inputs, "Microsoft6502Basic");
        string source = $"""
            .cpu Mos6502
            .include "MsBasic.SimpleFunctions.asm"
            .org ${legacy.Symbol("FRE"):X4}
                SIMPLE_FUNCTIONS {(setCarry ? 1 : 0)}
            SIMPLE_FUNCTIONS_END:
            """;

        string[] dependencies =
        [
            "VALTYP", "FREFAC", "GARBA2", "FRETOP", "STREND", "FACHO", "FACMOH", "FLOATS", "TRMPOS"
        ];

        Dictionary<string, long> symbols = dependencies.ToDictionary(
            name => name, name => legacy.Symbol(name), StringComparer.Ordinal);

        AssemblyResult native = new Assembler.Assembler().Assemble(
            new AssemblySource(source, Path.Join(folder, "SharedSimpleFunctionsTest.asm")),
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
        int start = checked((int)legacy.Symbol("FRE"));
        int end = checked((int)legacy.Symbol("ERRDIR"));
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
