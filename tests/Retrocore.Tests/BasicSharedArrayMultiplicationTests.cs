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
///  Checks the shared array multiplication against the AppleSoft and PET ROM sources.
/// </summary>
[TestClass]
public sealed class BasicSharedArrayMultiplicationTests
{
    private static string Inputs => BasicNames.Inputs;

    /// <summary>
    ///  AppleSoft retains its original bytes and labels after moving the routine into the shared source.
    /// </summary>
    /// <param name="model">The Apple II model.</param>
    [TestMethod]
    [DataRow(Apple2Model.IIPlus)]
    [DataRow(Apple2Model.IIe)]
    [DataRow(Apple2Model.IIeEnhanced)]
    public void AppleSoftUsesSharedArrayMultiplication(Apple2Model model)
    {
        AssemblyResult legacy = SdkModules.AssembleAppleSoft(
            SdkModules.AppleSoftPath(Inputs, BasicSourceKind.Macro10),
            model);

        AssemblyResult native = SdkModules.AssembleAppleSoft(SdkModules.AppleSoftPath(Inputs), model);

        CompareRegion(legacy, native);
        AssemblySymbol definition = native.Definition("UMULT");
        definition.Location?.Path.Should().EndWith("MsBasic.ArrayMultiplication.asm");
    }

    /// <summary>
    ///  The shared source assembles to the complete corresponding region of every PET BASIC revision.
    /// </summary>
    /// <param name="model">The PET model.</param>
    /// <param name="original">Whether BASIC 1 or 4 uses its original chip.</param>
    [TestMethod]
    [DataRow(PetModel.Pet2001, false)]
    [DataRow(PetModel.Pet2001, true)]
    [DataRow(PetModel.Pet2001Basic2, false)]
    [DataRow(PetModel.Pet4032, false)]
    [DataRow(PetModel.Pet4032, true)]
    public void SharedArrayMultiplicationMatchesPet(PetModel model, bool original)
    {
        AssemblyResult legacy = PetLegacyBasic.Assemble(Path.Join(Inputs, "Pet"), model, original);
        AssemblyResult native = AssembleRegion(legacy);
        native.Symbol("MULTIPLY_END").Should().Be(legacy.Symbol("FRE"));
        CompareRegion(legacy, native);
    }

    /// <summary>
    ///  The promoted entry retains its documentation and physical debugger source position.
    /// </summary>
    [TestMethod]
    public void SharedRoutineRetainsDocumentationAndSourcePosition()
    {
        AssemblyResult native = SdkModules.AssembleAppleSoft(SdkModules.AppleSoftPath(Inputs), Apple2Model.IIeEnhanced);
        ushort start = checked((ushort)native.Symbol("UMULT"));
        int length = checked((int)(native.Symbol("FRE") - start));
        DebugTestMemory memory = new();
        memory.Set(start, native.Sections[0].Bytes.Slice(start, length).ToArray());
        SourceMapModule module = new(native, area: null);
        DebugPosition position = module.Position(memory, start)
            ?? throw new AssertFailedException("UMULT has no debugger source position.");

        position.Chain.Should().ContainSingle();
        position.Chain[0].Path.Should().EndWith("MsBasic.ArrayMultiplication.asm");
        module.Entries(position.Chain[0].Path, position.Chain[0].Line).Should().Contain(start);

        DocumentationTopic topic = module.Documentation.FindTopic("UMULT")
            ?? throw new AssertFailedException("UMULT is not documented.");

        topic.Kind.Should().Be(DocumentationKind.Routine);
        topic.Path.Should().EndWith("MsBasic.ArrayMultiplication.asm");
        topic.Summary.Should().NotBeNullOrWhiteSpace();
    }

    /// <summary>
    ///  Both entries produce a full 16-bit product and branch to OUT OF MEMORY on overflow.
    /// </summary>
    /// <param name="multiplicand">The initial CURTOL value.</param>
    /// <param name="multiplier">The value supplied directly or in an array descriptor.</param>
    /// <param name="descriptor">Whether to enter through UMULT rather than UMULTD.</param>
    /// <param name="overflow">Whether the product exceeds 16 bits.</param>
    [TestMethod]
    [DataRow(0, 0x1234, false, false)]
    [DataRow(0xFFFF, 1, false, false)]
    [DataRow(0x0123, 0x20, true, false)]
    [DataRow(0x0100, 0x0100, true, true)]
    [DataRow(0xFFFF, 2, false, true)]
    public void MultiplicationHandlesProductsAndOverflow(int multiplicand, int multiplier, bool descriptor, bool overflow)
    {
        AssemblyResult legacy = PetLegacyBasic.Assemble(Path.Join(Inputs, "Pet"), PetModel.Pet2001Basic2);
        AssemblyResult native = AssembleRegion(legacy);
        int cursor = checked((int)native.Symbol("CURTOL"));
        int addend = checked((int)native.Symbol("ADDEND"));
        int lowtr = checked((int)native.Symbol("LOWTR"));
        int index = checked((int)native.Symbol("INDEX"));
        ushort complete = checked((ushort)native.Symbol("UMLRTS"));
        ushort error = checked((ushort)native.Symbol("OMERR1"));

        RecordingBus bus = new();
        native.Sections[0].Bytes.Span.CopyTo(bus.Memory);
        bus.Memory[cursor] = (byte)multiplicand;
        bus.Memory[cursor + 1] = (byte)(multiplicand >> 8);
        bus.Memory[addend] = (byte)multiplier;
        if (descriptor)
        {
            bus.Memory[lowtr] = 0;
            bus.Memory[lowtr + 1] = 2;
            bus.Memory[0x0202] = (byte)(multiplier >> 8);
            bus.Memory[0x0203] = (byte)multiplier;
        }

        Processor<RecordingBus> cpu = new(bus)
        {
            Registers = new()
            {
                ProgramCounter = checked((ushort)native.Symbol(descriptor ? "UMULT" : "UMULTD")),
                Accumulator = (byte)(multiplier >> 8),
                Y = 3,
                Status = StatusRegister.Unused
            }
        };

        for (int instruction = 0; instruction < 400
            && cpu.Registers.ProgramCounter != complete
            && cpu.Registers.ProgramCounter != error; instruction++)
        {
            cpu.StepInstruction();
        }

        if (overflow)
        {
            cpu.Registers.ProgramCounter.Should().Be(error);
            return;
        }

        int product = multiplicand * multiplier;
        cpu.Registers.ProgramCounter.Should().Be(complete);
        cpu.Registers.X.Should().Be((byte)product);
        cpu.Registers.Y.Should().Be((byte)(product >> 8));
        cpu.Registers.Accumulator.Should().Be((byte)(product >> 8));
        bus.Memory[cursor].Should().Be(0);
        bus.Memory[cursor + 1].Should().Be(0);
        if (descriptor)
        {
            bus.Memory[index].Should().Be(3);
        }
    }

    private static AssemblyResult AssembleRegion(AssemblyResult legacy)
    {
        int start = checked((int)legacy.Symbol("UMULT"));
        string folder = Path.Join(Inputs, "Microsoft6502Basic");
        string source = $"""
            .cpu Mos6502
            .org ${start:X4}
            .include "MsBasic.ArrayMultiplication.asm"
            MULTIPLY_END:
            """;

        AssemblyOptions options = new(ProcessorVariant.Mos6502, 0, 0x10000)
        {
            SourceResolver = new FileAssemblySourceResolver(),
            PredefinedSymbols = BasicNames.WithCurrentNames(new Dictionary<string, long>
            {
                ["INDEX"] = legacy.Symbol("INDEX"),
                ["LOWTR"] = legacy.Symbol("LOWTR"),
                ["ADDEND"] = legacy.Symbol("ADDEND"),
                ["CURTOL"] = legacy.Symbol("CURTOL"),
                ["DECCNT"] = legacy.Symbol("DECCNT"),
                ["OMERR1"] = legacy.Symbol("OMERR1")
            })
        };

        AssemblyResult native = new Assembler.Assembler().Assemble(
            new AssemblySource(source, Path.Join(folder, "ArrayMultiplicationTest.asm")),
            options);

        native.Success.Should().BeTrue(string.Join(Environment.NewLine, native.Diagnostics.Select(diagnostic =>
            $"{diagnostic.Location?.Path}:{diagnostic.Location?.Line + 1}: {diagnostic.Message}")));

        return native;
    }

    private static void CompareRegion(AssemblyResult legacy, AssemblyResult native)
    {
        int start = checked((int)legacy.Symbol("UMULT"));
        int length = checked((int)(legacy.Symbol("FRE") - start));
        foreach (string name in (string[])["UMULT", "UMULTD", "UMULTC", "UMLCNT", "UMLRTS"])
        {
            native.Symbol(name).Should().Be(legacy.Symbol(name), $"{name} must retain its ROM address");
        }

        native.Sections[0].Bytes.Slice(start, length).ToArray()
            .Should().Equal(legacy.Sections[0].Bytes.Slice(start, length).ToArray());
    }
}
