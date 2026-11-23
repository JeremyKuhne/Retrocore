// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text;
using Retrocore.Assembler;
using Retrocore.Debug;
using Retrocore.Documentation;
using Retrocore.Machines.Apple2;
using Retrocore.Machines.Commodore;

namespace Retrocore.Tests;

/// <summary>
///  Checks shared DATA, REM, IF and ON statements.
/// </summary>
[TestClass]
public sealed class BasicSharedStatementFlowTests
{
    private static string Inputs => BasicNames.Inputs;

    /// <summary>
    ///  AppleSoft retains its bytes and labels with the POP unwind entry.
    /// </summary>
    /// <param name="model">The Apple II model.</param>
    [TestMethod]
    [DataRow(Apple2Model.IIPlus)]
    [DataRow(Apple2Model.IIe)]
    [DataRow(Apple2Model.IIeEnhanced)]
    public void AppleSoftUsesSharedStatementFlow(Apple2Model model)
    {
        AssemblyResult legacy = SdkModules.AssembleAppleSoft(
            SdkModules.AppleSoftPath(Inputs, BasicSourceKind.Macro10),
            model);

        AssemblyResult native = SdkModules.AssembleAppleSoft(SdkModules.AppleSoftPath(Inputs), model);
        AssemblyResult standalone = AssembleShared(legacy, quoteFirst: false, popExit: true);
        CompareRegion(legacy, native);
        CompareRegion(legacy, standalone);
        standalone.Symbol("STATEMENT_FLOW_END").Should().Be(legacy.Symbol("LINGET"));
        SdkModules.AppleSoftImage(native).ToArray().Should().Equal(SdkModules.AppleSoftImage(legacy).ToArray());
    }

    /// <summary>
    ///  Every PET revision retains its scanner branch order and statement code.
    /// </summary>
    /// <param name="model">The PET model.</param>
    /// <param name="original">Whether BASIC 1 or 4 uses its original chip.</param>
    [TestMethod]
    [DataRow(PetModel.Pet2001, false)]
    [DataRow(PetModel.Pet2001, true)]
    [DataRow(PetModel.Pet2001Basic2, false)]
    [DataRow(PetModel.Pet4032, false)]
    [DataRow(PetModel.Pet4032, true)]
    public void SharedStatementFlowMatchesPet(PetModel model, bool original)
    {
        AssemblyResult legacy = PetLegacyBasic.Assemble(Path.Join(Inputs, "Pet"), model, original);
        AssemblyResult native = AssembleShared(legacy, quoteFirst: model == PetModel.Pet2001, popExit: false);
        CompareRegion(legacy, native);
        native.Symbol("STATEMENT_FLOW_END").Should().Be(legacy.Symbol("LINGET"));
    }

    /// <summary>
    ///  Both scanner branch orderings ignore colons inside quoted fields; REM scans to the zero byte.
    /// </summary>
    /// <param name="quoteFirst">Whether to use the earlier branch ordering.</param>
    /// <param name="entry">The scanner entry.</param>
    /// <param name="text">The text to scan.</param>
    /// <param name="terminator">The expected terminator offset.</param>
    [TestMethod]
    [DataRow(false, "DATAN", "A,\"B:C\":NEXT", 7)]
    [DataRow(true, "DATAN", "A,\"B:C\":NEXT", 7)]
    [DataRow(false, "DATAN", "\"A:B", 4)]
    [DataRow(true, "DATAN", "\"A:B", 4)]
    [DataRow(false, "REMN", "\"A:B\":NEXT", 10)]
    [DataRow(true, "REMN", "\"A:B\":NEXT", 10)]
    public void ScannerFindsTheCorrectTerminator(bool quoteFirst, string entry, string text, int terminator)
    {
        PetModel model = quoteFirst ? PetModel.Pet2001 : PetModel.Pet2001Basic2;
        AssemblyResult legacy = PetLegacyBasic.Assemble(Path.Join(Inputs, "Pet"), model);
        AssemblyResult native = AssembleShared(legacy, quoteFirst, popExit: false);
        RecordingBus bus = new();
        native.Sections[0].Bytes.Span.CopyTo(bus.Memory);
        const ushort textAddress = 0x0400;
        int pointer = checked((int)native.Symbol("TXTPTR"));
        bus.Memory[pointer] = (byte)(textAddress & 0xFF);
        bus.Memory[pointer + 1] = (byte)(textAddress >> 8);
        Encoding.ASCII.GetBytes(text).CopyTo(bus.Memory, textAddress);
        bus.Memory[textAddress + text.Length] = 0;
        Processor<RecordingBus> cpu = new(bus)
        {
            Registers = new()
            {
                ProgramCounter = checked((ushort)native.Symbol(entry)),
                StackPointer = 0xFD,
                Status = StatusRegister.Unused
            }
        };

        ushort finish = checked((ushort)native.Symbol("REMRTS"));
        for (int instruction = 0; instruction < 200 && cpu.Registers.ProgramCounter != finish; instruction++)
        {
            cpu.StepInstruction();
        }

        cpu.Registers.ProgramCounter.Should().Be(finish);
        cpu.Registers.Y.Should().Be((byte)terminator);
        cpu.Registers.Status.HasFlag(StatusRegister.Zero).Should().BeTrue();
    }

    /// <summary>
    ///  The shared routines retain documentation and breakpoint-capable source lines.
    /// </summary>
    [TestMethod]
    public void SharedStatementsRetainDocumentationAndSourcePositions()
    {
        AssemblyResult native = SdkModules.AssembleAppleSoft(SdkModules.AppleSoftPath(Inputs), Apple2Model.IIeEnhanced);
        int start = checked((int)native.Symbol("DATA"));
        int end = checked((int)native.Symbol("LINGET"));
        DebugTestMemory memory = new();
        memory.Set((ushort)start, native.Sections[0].Bytes.Slice(start, end - start).ToArray());
        SourceMapModule module = new(native, area: null);
        foreach (string name in (string[])["DATA", "DATAN", "REMN", "IF", "REM", "ONGOTO"])
        {
            DocumentationTopic topic = module.Documentation.FindTopic(name)
                ?? throw new AssertFailedException($"{name} is not documented.");

            topic.Kind.Should().Be(DocumentationKind.Routine);
            topic.Path.Should().EndWith("MsBasic.StatementFlow.asm");
            ushort address = checked((ushort)native.Symbol(name));
            DebugPosition position = module.Position(memory, address)
                ?? throw new AssertFailedException($"{name} has no debugger source position.");

            position.Chain.Should().HaveCount(2);
            position.Chain[0].Path.Should().EndWith("MsBasic.StatementFlow.asm");
            position.Chain[1].Path.Should().EndWith("AppleSoft.ControlFlow.asm");
            module.Entries(position.Chain[0].Path, position.Chain[0].Line).Should().Contain(address);
        }
    }

    private static AssemblyResult AssembleShared(AssemblyResult legacy, bool quoteFirst, bool popExit)
    {
        string folder = Path.Join(Inputs, "Microsoft6502Basic");
        string source = $"""
            .cpu Mos6502
            .include "MsBasic.StatementFlow.asm"
            .org ${legacy.Symbol("DATA"):X4}
                StatementScan {(quoteFirst ? 1 : 0)}, {(popExit ? 1 : 0)}
                ConditionalStatements
            {(popExit ? BasicNames.Label("ON") : "")}
                OnStatement
            STATEMENT_FLOW_END:
            """;

        string[] dependencies =
        [
            "TXTPTR", "CHARAC", "ENDCHR", "FRMEVL", "CHRGOT", "GOTOTK", "THENTK",
            "SYNCHR", "FACEXP", "GOTO", "GONE3", "GETBYT", "GOSUTK", "SNERR2",
            "FACLO", "GONE2", "CHRGET", "LINGET"
        ];

        Dictionary<string, long> symbols = dependencies.ToDictionary(
            name => name, name => legacy.Symbol(name), StringComparer.Ordinal);

        AssemblyResult native = new Assembler.Assembler().Assemble(
            new AssemblySource(BasicNames.ScopedNames(symbols) + "\n" + source, Path.Join(folder, "SharedStatementFlowTest.asm")),
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
        int start = checked((int)legacy.Symbol("DATA"));
        int end = checked((int)legacy.Symbol("LINGET"));
        foreach (AssemblySymbol label in legacy.SymbolDefinitions.Where(
            symbol => !symbol.IsConstant && symbol.Value >= start && symbol.Value < end))
        {
            // A vendor's alias reaches its name only in the vendor's whole build, which this compares too.
            if (BasicNames.IsVendorName(label.Name) && !native.SymbolsWithHistoricalNames.ContainsKey(label.Name))
            {
                continue;
            }

            native.SymbolsWithHistoricalNames.Should().ContainKey(label.Name);
            native.Symbol(label.Name).Should().Be(label.Value, $"{label.Name} must retain its ROM address");
        }

        native.Sections[0].Bytes.Slice(start, end - start).ToArray()
            .Should().Equal(legacy.Sections[0].Bytes.Slice(start, end - start).ToArray());
    }
}
