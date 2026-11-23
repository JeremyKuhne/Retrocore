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
///  Checks the shared NEXT and result-type entries against the AppleSoft and PET ROM sources.
/// </summary>
[TestClass]
public sealed class BasicSharedNextTests
{
    private static string Inputs => BasicNames.Inputs;

    /// <summary>
    ///  AppleSoft uses the shared template without changing its NEXT or type-check code.
    /// </summary>
    /// <param name="model">The Apple II model.</param>
    [TestMethod]
    [DataRow(Apple2Model.IIPlus)]
    [DataRow(Apple2Model.IIe)]
    [DataRow(Apple2Model.IIeEnhanced)]
    public void AppleSoftUsesSharedNextEntries(Apple2Model model)
    {
        AssemblyResult legacy = SdkModules.AssembleAppleSoft(
            SdkModules.AppleSoftPath(Inputs, BasicSourceKind.Macro10),
            model);

        AssemblyResult native = SdkModules.AssembleAppleSoft(SdkModules.AppleSoftPath(Inputs), model);

        CompareRegion(legacy, AssembleRegion(legacy, countedStack: true, "NXTCO1"));
        CompareRegion(legacy, native);
        AssemblySymbol definition = native.Definition("NEXT");
        definition.Location?.Path.Should().EndWith("MsBasic.Next.asm");
    }

    /// <summary>
    ///  BASIC 1 counts through the frame; BASIC 2 and 4 calculate its offsets. Both reproduce their ROMs.
    /// </summary>
    /// <param name="model">The PET model.</param>
    /// <param name="original">Whether BASIC 1 or 4 uses its original chip.</param>
    [TestMethod]
    [DataRow(PetModel.Pet2001, false)]
    [DataRow(PetModel.Pet2001, true)]
    [DataRow(PetModel.Pet2001Basic2, false)]
    [DataRow(PetModel.Pet4032, false)]
    [DataRow(PetModel.Pet4032, true)]
    public void SharedNextEntriesMatchPet(PetModel model, bool original)
    {
        AssemblyResult legacy = PetLegacyBasic.Assemble(Path.Join(Inputs, "Pet"), model, original);
        AssemblyResult native = AssembleRegion(legacy, model == PetModel.Pet2001, "NEWSTT");
        native.Symbol("NEXT_END").Should().Be(legacy.Symbol("FRMEVL"));
        CompareRegion(legacy, native);
    }

    /// <summary>
    ///  NEXT has documentation and both its shared definition and AppleSoft invocation accept breakpoints.
    /// </summary>
    [TestMethod]
    public void SharedNextRetainsDocumentationAndSourceChains()
    {
        AssemblyResult native = SdkModules.AssembleAppleSoft(SdkModules.AppleSoftPath(Inputs), Apple2Model.IIeEnhanced);
        ushort start = checked((ushort)native.Symbol("NEXT"));
        int length = checked((int)(native.Symbol("FRMEVL") - start));
        DebugTestMemory memory = new();
        memory.Set(start, native.Sections[0].Bytes.Slice(start, length).ToArray());
        SourceMapModule module = new(native, area: null);
        DebugPosition position = module.Position(memory, start)
            ?? throw new AssertFailedException("NEXT has no debugger source position.");

        position.Chain.Should().HaveCount(2);
        position.Chain[0].Path.Should().EndWith("MsBasic.Next.asm");
        position.Chain[1].Path.Should().EndWith("AppleSoft.Expressions.asm");
        module.Entries(position.Chain[0].Path, position.Chain[0].Line).Should().Contain(start);
        module.Entries(position.Chain[1].Path, position.Chain[1].Line).Should().Contain(start);

        foreach (string name in (string[])["NEXT", "FRMNUM", "CHKNUM", "CHKSTR", "CHKVAL"])
        {
            DocumentationTopic topic = module.Documentation.FindTopic(name)
                ?? throw new AssertFailedException($"{name} is not documented.");

            topic.Kind.Should().Be(DocumentationKind.Routine);
            topic.Path.Should().EndWith("MsBasic.Next.asm");
            topic.Summary.Should().NotBeNullOrWhiteSpace();
        }
    }

    /// <summary>
    ///  Numeric and string checks accept the corresponding type and dispatch a mismatch to ERROR.
    /// </summary>
    /// <param name="stringEntry">Whether to enter CHKSTR rather than CHKNUM.</param>
    /// <param name="type">The result-type byte.</param>
    /// <param name="mismatch">Whether ERROR should be reached.</param>
    [TestMethod]
    [DataRow(false, 0x00, false)]
    [DataRow(false, 0x80, true)]
    [DataRow(true, 0x00, true)]
    [DataRow(true, 0xFF, false)]
    public void TypeChecksAcceptOrRejectTheirResult(bool stringEntry, int type, bool mismatch)
    {
        AssemblyResult legacy = PetLegacyBasic.Assemble(Path.Join(Inputs, "Pet"), PetModel.Pet2001Basic2);
        AssemblyResult native = AssembleRegion(legacy, countedStack: false, "NEWSTT");
        int valueType = checked((int)native.Symbol("VALTYP"));
        ushort accepted = checked((ushort)native.Symbol("CHKOK"));
        ushort error = checked((ushort)native.Symbol("ERROR"));
        RecordingBus bus = new();
        native.Sections[0].Bytes.Span.CopyTo(bus.Memory);
        bus.Memory[valueType] = (byte)type;

        Processor<RecordingBus> cpu = new(bus)
        {
            Registers = new()
            {
                ProgramCounter = checked((ushort)native.Symbol(stringEntry ? "CHKSTR" : "CHKNUM")),
                X = 0x42,
                Status = StatusRegister.Unused
            }
        };

        for (int instruction = 0; instruction < 16
            && cpu.Registers.ProgramCounter != accepted
            && cpu.Registers.ProgramCounter != error; instruction++)
        {
            cpu.StepInstruction();
        }

        cpu.Registers.ProgramCounter.Should().Be(mismatch ? error : accepted);
        bus.Memory[valueType].Should().Be((byte)type);
        if (mismatch)
        {
            cpu.Registers.X.Should().Be((byte)native.Symbol("ERRTM"));
        }
        else
        {
            cpu.Registers.X.Should().Be(0x42);
            cpu.Registers.Status.HasFlag(StatusRegister.Carry).Should().Be(stringEntry);
        }
    }

    private static AssemblyResult AssembleRegion(AssemblyResult legacy, bool countedStack, string resume)
    {
        int start = checked((int)legacy.Symbol("NEXT"));
        string folder = Path.Join(Inputs, "Microsoft6502Basic");
        string source = $"""
            .cpu Mos6502
            .include "MsBasic.Layouts.asm"
            .include "MsBasic.Next.asm"
            .org ${start:X4}
                NextEntries {(countedStack ? 1 : 0)}, RESUME_NEXT
            NEXT_END:
            """;

        string[] dependencies =
        [
            "PTRGET", "FORPNT", "FNDFOR", "ERRNF", "INDEX2", "MOVFM", "FACSGN", "FADD", "MOVVF",
            "FCOMPN", "CURLIN", "TXTPTR", "CHRGOT", "CHRGET", "FRMEVL", "VALTYP", "ERRTM", "ERROR"
        ];

        Dictionary<string, long> symbols = dependencies.ToDictionary(
            name => name, name => legacy.Symbol(name), StringComparer.Ordinal);

        symbols.Add("RESUME_NEXT", legacy.Symbol(resume));

        AssemblyOptions options = new(ProcessorVariant.Mos6502, 0, 0x10000)
        {
            SourceResolver = new FileAssemblySourceResolver(),
            PredefinedSymbols = BasicNames.WithCurrentNames(symbols)
        };

        AssemblyResult native = new Assembler.Assembler().Assemble(
            new AssemblySource(BasicNames.ScopedNames(symbols) + "\n" + source, Path.Join(folder, "NextEntriesTest.asm")),
            options);

        native.Success.Should().BeTrue(string.Join(Environment.NewLine, native.Diagnostics.Select(diagnostic =>
            $"{diagnostic.Location?.Path}:{diagnostic.Location?.Line + 1}: {diagnostic.Message}")));

        return native;
    }

    private static void CompareRegion(AssemblyResult legacy, AssemblyResult native)
    {
        int start = checked((int)legacy.Symbol("NEXT"));
        int end = checked((int)legacy.Symbol("FRMEVL"));
        IEnumerable<AssemblySymbol> labels = legacy.SymbolDefinitions.Where(
            symbol => !symbol.IsConstant && symbol.Value >= start && symbol.Value < end);

        foreach (AssemblySymbol label in labels)
        {
            native.SymbolsWithHistoricalNames.Should().ContainKey(label.Name);
            native.Symbol(label.Name).Should().Be(label.Value, $"{label.Name} must retain its ROM address");
        }

        native.Sections[0].Bytes.Slice(start, end - start).ToArray()
            .Should().Equal(legacy.Sections[0].Bytes.Slice(start, end - start).ToArray());
    }
}
