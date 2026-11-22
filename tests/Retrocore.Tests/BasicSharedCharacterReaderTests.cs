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
///  The shared character-reader template assembles like each machine's Microsoft BASIC source.
/// </summary>
[TestClass]
public sealed class BasicSharedCharacterReaderTests
{
    private static readonly string s_inputs = Path.Join(AppContext.BaseDirectory, "Inputs");

    /// <summary>
    ///  The native AppleSoft listing uses the shared template and preserves the ROM's bytes and labels.
    /// </summary>
    /// <param name="model">The Apple II model.</param>
    [TestMethod]
    [DataRow(Apple2Model.IIPlus)]
    [DataRow(Apple2Model.IIe)]
    [DataRow(Apple2Model.IIeEnhanced)]
    public void AppleSoftUsesTheSharedReader(Apple2Model model)
    {
        AssemblyResult legacy = SdkModules.AssembleAppleSoft(
            SdkModules.AppleSoftPath(s_inputs, BasicSourceKind.Macro10),
            model);

        AssemblyResult native = SdkModules.AssembleAppleSoft(SdkModules.AppleSoftPath(s_inputs), model);

        CompareTemplate(legacy, AssembleTemplate(legacy, 0x58));
        CompareTemplate(legacy, native);
        VerifyStartupCopiesOnlyFourSeedBytes(native);
        AssemblySymbol definition = native.SymbolDefinitions.Single(symbol => symbol.Name == "INITAT");
        definition.Location?.Path.Should().EndWith("MsBasic.CharacterReader.asm");
        DocumentationTopic? topic = new SourceMapModule(native, area: null).Documentation.Find("INITAT");
        topic.Should().NotBeNull();
        topic?.Path.Should().EndWith("MsBasic.CharacterReader.asm");
        topic?.Summary.Should().NotBeNullOrWhiteSpace();
    }

    /// <summary>
    ///  The same template uses each PET's page-zero address and BASIC 1's different random seed.
    /// </summary>
    /// <param name="model">The PET model.</param>
    /// <param name="original">Whether BASIC 1 or 4 uses its original chip.</param>
    [TestMethod]
    [DataRow(PetModel.Pet2001, false)]
    [DataRow(PetModel.Pet2001, true)]
    [DataRow(PetModel.Pet2001Basic2, false)]
    [DataRow(PetModel.Pet4032, false)]
    [DataRow(PetModel.Pet4032, true)]
    public void SharedReaderMatchesPetTemplate(PetModel model, bool original)
    {
        AssemblyResult legacy = PetLegacyBasic.Assemble(Path.Join(s_inputs, "Pet"), model, original);
        byte lastSeed = model == PetModel.Pet2001 ? (byte)0x59 : (byte)0x58;
        CompareTemplate(legacy, AssembleTemplate(legacy, lastSeed));
        VerifyStartupCopiesOnlyFourSeedBytes(legacy);
    }

    /// <summary>
    ///  The shared definition and AppleSoft's macro invocation are both usable as debugger source positions.
    /// </summary>
    [TestMethod]
    public void ReaderRetainsBothSourceMapLocations()
    {
        AssemblyResult native = SdkModules.AssembleAppleSoft(SdkModules.AppleSoftPath(s_inputs), Apple2Model.IIeEnhanced);
        ushort start = checked((ushort)native.Symbols["INITAT"]);
        int length = checked((int)(native.Symbols["INIT"] - start));
        DebugTestMemory memory = new();
        memory.Set(start, native.Sections[0].Bytes.Slice(start, length).ToArray());
        SourceMapModule module = new(native, area: null);
        DebugPosition position = module.Position(memory, start)
            ?? throw new AssertFailedException("INITAT has no debugger source position.");

        position.Chain.Should().HaveCount(2);
        position.Chain[0].Path.Should().EndWith("MsBasic.CharacterReader.asm");
        position.Chain[1].Path.Should().EndWith("AppleSoft.Initialization.asm");
        module.Entries(position.Chain[0].Path, position.Chain[0].Line).Should().Contain(start);
        module.Entries(position.Chain[1].Path, position.Chain[1].Line).Should().Contain(start);
    }

    /// <summary>
    ///  The copied reader skips spaces across a page boundary and reports both digits and statement delimiters.
    /// </summary>
    /// <param name="character">The character after the space.</param>
    /// <param name="carry">The expected carry flag.</param>
    /// <param name="zero">The expected zero flag.</param>
    [TestMethod]
    [DataRow(0x00, true, true)]
    [DataRow(0x30, false, false)]
    [DataRow(0x39, false, false)]
    [DataRow(0x2F, true, false)]
    [DataRow(0x3A, true, true)]
    [DataRow(0x41, true, false)]
    public void CopiedReaderReportsCharacterFlags(int character, bool carry, bool zero)
    {
        AssemblyResult legacy = PetLegacyBasic.Assemble(Path.Join(s_inputs, "Pet"), PetModel.Pet2001Basic2);
        AssemblyResult reader = AssembleTemplate(legacy, 0x58);
        int start = checked((int)reader.Symbols["INITAT"]);
        int length = checked((int)(legacy.Symbols["INIT"] - start));
        int destination = checked((int)reader.Symbols["CHRGET"]);
        int textPointer = checked((int)reader.Symbols["TXTPTR"]);
        int exit = destination + checked((int)(reader.Symbols["CHZRTS"] - start));

        RecordingBus bus = new();
        reader.Sections[0].Bytes.Span.Slice(start, length).CopyTo(bus.Memory.AsSpan(destination));
        bus.Memory[textPointer] = 0xFE;
        bus.Memory[textPointer + 1] = 0x01;
        bus.Memory[0x01FF] = 0x20;
        bus.Memory[0x0200] = (byte)character;

        Processor<RecordingBus> cpu = new(bus)
        {
            Registers = new()
            {
                ProgramCounter = checked((ushort)destination),
                X = 0x12,
                Y = 0x34,
                Status = StatusRegister.Unused
            }
        };

        for (int instruction = 0; instruction < 32 && cpu.Registers.ProgramCounter != exit; instruction++)
        {
            cpu.StepInstruction();
        }

        cpu.Registers.ProgramCounter.Should().Be((ushort)exit);
        cpu.Registers.Accumulator.Should().Be((byte)character);
        cpu.Registers.X.Should().Be(0x12);
        cpu.Registers.Y.Should().Be(0x34);
        cpu.Registers.Status.HasFlag(StatusRegister.Carry).Should().Be(carry);
        cpu.Registers.Status.HasFlag(StatusRegister.Zero).Should().Be(zero);
        bus.Memory[textPointer].Should().Be(0);
        bus.Memory[textPointer + 1].Should().Be(2);
    }

    private static AssemblyResult AssembleTemplate(AssemblyResult legacy, byte lastSeed)
    {
        int start = checked((int)legacy.Symbols["INITAT"]);
        string folder = Path.Join(s_inputs, "Microsoft6502Basic");
        string source = $"""
            .cpu Mos6502
            .include "MsBasic.CharacterReader.asm"
            .org ${start:X4}
                CHARACTER_READER ${lastSeed:X2}
            READER_END:
            """;

        AssemblyOptions options = new(ProcessorVariant.Mos6502, 0, 0x10000)
        {
            SourceResolver = new FileAssemblySourceResolver(),
            PredefinedSymbols = new Dictionary<string, long>
            {
                ["TXTPTR"] = legacy.Symbols["TXTPTR"],
                ["CHRGET"] = legacy.Symbols["CHRGET"],
                ["RNDX"] = legacy.Symbols["RNDX"]
            }
        };

        AssemblyResult result = new Assembler.Assembler().Assemble(
            new AssemblySource(source, Path.Join(folder, "CharacterReaderTest.asm")),
            options);

        result.Success.Should().BeTrue(string.Join(Environment.NewLine, result.Diagnostics.Select(diagnostic =>
            $"{diagnostic.Location?.Path}:{diagnostic.Location?.Line + 1}: {diagnostic.Message}")));

        result.Symbols["READER_END"].Should().Be(legacy.Symbols["INIT"]);
        return result;
    }

    private static void CompareTemplate(AssemblyResult legacy, AssemblyResult native)
    {
        int start = checked((int)legacy.Symbols["INITAT"]);
        int length = checked((int)(legacy.Symbols["INIT"] - start));
        foreach (string name in (string[])["INITAT", "CHZGOT", "CHZRTS"])
        {
            native.Symbols[name].Should().Be(legacy.Symbols[name], $"{name} must retain its ROM address");
        }

        native.Sections[0].Bytes.Slice(start, length).ToArray()
            .Should().Equal(legacy.Sections[0].Bytes.Slice(start, length).ToArray());
    }

    private static void VerifyStartupCopiesOnlyFourSeedBytes(AssemblyResult basic)
    {
        int loop = checked((int)basic.Symbols["MOVCHG"]);
        int seed = checked((int)basic.Symbols["RNDX"]);
        int sourceSeed = checked((int)basic.Symbols["INIT"]) - 5;
        RecordingBus bus = new();
        basic.Sections[0].Bytes.Span.CopyTo(bus.Memory);
        bus.Memory.AsSpan(seed, 5).Fill(0x55);

        Processor<RecordingBus> cpu = new(bus)
        {
            Registers = new() { ProgramCounter = checked((ushort)(loop - 2)), Status = StatusRegister.Unused }
        };

        cpu.StepInstruction();
        cpu.Registers.ProgramCounter.Should().Be((ushort)loop);
        cpu.Registers.X.Should().Be(28);
        for (int instruction = 0; instruction < 200 && cpu.Registers.X != 0; instruction++)
        {
            cpu.StepInstruction();
        }

        cpu.Registers.X.Should().Be(0);
        bus.Memory.AsSpan(seed, 4).ToArray()
            .Should().Equal(basic.Sections[0].Bytes.Slice(sourceSeed, 4).ToArray());

        bus.Memory[seed + 4].Should().Be(0x55);
    }
}
