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
///  Checks shared DEF and FN routines against AppleSoft and PET BASIC.
/// </summary>
[TestClass]
public sealed class BasicSharedUserFunctionsTests
{
    private static string Inputs => BasicNames.Inputs;

    /// <summary>
    ///  The later undefined-function check preserves every AppleSoft model's bytes and labels.
    /// </summary>
    /// <param name="model">The Apple II model.</param>
    [TestMethod]
    [DataRow(Apple2Model.IIPlus)]
    [DataRow(Apple2Model.IIe)]
    [DataRow(Apple2Model.IIeEnhanced)]
    public void AppleSoftUsesSharedUserFunctions(Apple2Model model)
    {
        AssemblyResult legacy = SdkModules.AssembleAppleSoft(
            SdkModules.AppleSoftPath(Inputs, BasicSourceKind.Macro10),
            model);

        AssemblyResult native = SdkModules.AssembleAppleSoft(SdkModules.AppleSoftPath(Inputs), model);
        AssemblyResult standalone = AssembleShared(legacy, earlyCheck: false);
        CompareRegion(legacy, native);
        CompareRegion(legacy, standalone);
        standalone.Symbol("USER_FUNCTIONS_END").Should().Be(legacy.Symbol("STR"));
    }

    /// <summary>
    ///  The early and later checks preserve the corresponding PET revisions.
    /// </summary>
    /// <param name="model">The PET model.</param>
    /// <param name="original">Whether BASIC 1 or 4 uses its original chip.</param>
    [TestMethod]
    [DataRow(PetModel.Pet2001, false)]
    [DataRow(PetModel.Pet2001, true)]
    [DataRow(PetModel.Pet2001Basic2, false)]
    [DataRow(PetModel.Pet4032, false)]
    [DataRow(PetModel.Pet4032, true)]
    public void SharedUserFunctionsMatchPet(PetModel model, bool original)
    {
        AssemblyResult legacy = PetLegacyBasic.Assemble(Path.Join(Inputs, "Pet"), model, original);
        AssemblyResult native = AssembleShared(legacy, model == PetModel.Pet2001);
        CompareRegion(legacy, native);
        native.Symbol("USER_FUNCTIONS_END").Should().Be(legacy.Symbol("STR"));
        native.HasSymbol("ERRGUF").Should().Be(model != PetModel.Pet2001);
    }

    /// <summary>
    ///  The early build checks the address's low byte; the later build checks its high byte.
    /// </summary>
    /// <param name="early">Whether to use BASIC 1's early check.</param>
    /// <param name="address">The function argument variable's address.</param>
    /// <param name="undefined">Whether the check should report an undefined function.</param>
    [TestMethod]
    [DataRow(true, 0x4000, true)]
    [DataRow(false, 0x4000, false)]
    [DataRow(true, 0x0042, false)]
    [DataRow(false, 0x0042, true)]
    [DataRow(true, 0x0000, true)]
    [DataRow(false, 0x0000, true)]
    [DataRow(true, 0x4042, false)]
    [DataRow(false, 0x4042, false)]
    public void UndefinedFunctionCheckUsesTheSelectedByte(bool early, int address, bool undefined)
    {
        PetModel model = early ? PetModel.Pet2001 : PetModel.Pet2001Basic2;
        AssemblyResult legacy = PetLegacyBasic.Assemble(Path.Join(Inputs, "Pet"), model);
        AssemblyResult native = AssembleShared(legacy, early);
        RecordingBus bus = new();
        native.Sections[0].Bytes.Span.CopyTo(bus.Memory);
        foreach (string entry in (string[])["GETFNM", "PARCHK", "CHKNUM"])
        {
            bus.Memory[checked((int)native.Symbol(entry))] = 0x60;
        }

        int function = checked((int)native.Symbol("DEFPNT"));
        int variable = checked((int)native.Symbol("VARPNT"));
        bus.Memory[function] = 0x00;
        bus.Memory[function + 1] = 0x04;
        bus.Memory[0x0402] = (byte)address;
        bus.Memory[0x0403] = (byte)(address >> 8);
        ushort error = checked((ushort)native.Symbol("ERROR"));
        ushort defined = checked((ushort)native.Symbol("DEFSTF"));
        Processor<RecordingBus> cpu = new(bus)
        {
            Registers = new()
            {
                ProgramCounter = checked((ushort)native.Symbol("FNDOER")),
                StackPointer = 0xFD,
                Status = StatusRegister.Unused
            }
        };

        for (int instruction = 0; instruction < 50
            && cpu.Registers.ProgramCounter != error
            && cpu.Registers.ProgramCounter != defined; instruction++)
        {
            cpu.StepInstruction();
        }

        cpu.Registers.ProgramCounter.Should().Be(undefined ? error : defined);
        if (undefined)
        {
            cpu.Registers.X.Should().Be((byte)native.Symbol("ERRUF"));
        }
        else
        {
            (bus.Memory[variable] | (bus.Memory[variable + 1] << 8)).Should().Be(address);
        }
    }

    /// <summary>
    ///  Shared function definitions retain documentation and breakpoint-capable source lines.
    /// </summary>
    [TestMethod]
    public void UserFunctionsRetainDocumentationAndSourcePositions()
    {
        AssemblyResult native = SdkModules.AssembleAppleSoft(SdkModules.AppleSoftPath(Inputs), Apple2Model.IIeEnhanced);
        int start = checked((int)native.Symbol("ERRDIR"));
        int end = checked((int)native.Symbol("STR"));
        DebugTestMemory memory = new();
        memory.Set((ushort)start, native.Sections[0].Bytes.Slice(start, end - start).ToArray());
        SourceMapModule module = new(native, area: null);
        foreach (string name in (string[])["ERRDIR", "ERRGUF", "DEF", "GETFNM", "FNDOER", "DEFFIN"])
        {
            DocumentationTopic topic = module.Documentation.FindTopic(name)
                ?? throw new AssertFailedException($"{name} is not documented.");

            topic.Kind.Should().Be(DocumentationKind.Routine);
            topic.Path.Should().EndWith("MsBasic.UserFunctions.asm");
            ushort address = checked((ushort)native.Symbol(name));
            DebugPosition position = module.Position(memory, address)
                ?? throw new AssertFailedException($"{name} has no debugger source position.");

            position.Chain[0].Path.Should().EndWith("MsBasic.UserFunctions.asm");
            module.Entries(position.Chain[0].Path, position.Chain[0].Line).Should().Contain(address);
        }
    }

    private static AssemblyResult AssembleShared(AssemblyResult legacy, bool earlyCheck)
    {
        string folder = Path.Join(Inputs, "Microsoft6502Basic");
        string source = $"""
            .cpu Mos6502
            .include "MsBasic.UserFunctions.asm"
            .org ${legacy.Symbol("ERRDIR"):X4}
                USER_FUNCTIONS {(earlyCheck ? 1 : 0)}
            USER_FUNCTIONS_END:
            """;

        string[] dependencies =
        [
            "CURLIN", "DIMRTS", "ERRID", "ERRUF", "ERROR", "CHKOPN", "SUBFLG", "PTRGET", "CHKNUM",
            "CHKCLS", "EQULTK", "SYNCHR", "VARPNT", "TXTPTR", "DATA", "FNTK", "PTRGT2", "DEFPNT",
            "PARCHK", "MOVMF", "FRMNUM", "CHRGOT", "SNERR"
        ];

        Dictionary<string, long> symbols = dependencies.ToDictionary(
            name => name, name => legacy.Symbol(name), StringComparer.Ordinal);

        AssemblyResult native = new Assembler.Assembler().Assemble(
            new AssemblySource(source, Path.Join(folder, "SharedUserFunctionsTest.asm")),
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
        int start = checked((int)legacy.Symbol("ERRDIR"));
        int end = checked((int)legacy.Symbol("STR"));
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
