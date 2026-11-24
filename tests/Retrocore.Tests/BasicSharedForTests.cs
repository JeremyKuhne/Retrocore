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
///  Checks the shared FOR entry against AppleSoft and PET BASIC.
/// </summary>
[TestClass]
public sealed class BasicSharedForTests
{
    private static string Inputs => BasicNames.Inputs;

    /// <summary>
    ///  All AppleSoft models retain their FOR code and labels.
    /// </summary>
    /// <param name="model">The Apple II model.</param>
    [TestMethod]
    [DataRow(Apple2Model.IIPlus)]
    [DataRow(Apple2Model.IIe)]
    [DataRow(Apple2Model.IIeEnhanced)]
    public void AppleSoftUsesSharedFor(Apple2Model model)
    {
        AssemblyResult legacy = SdkModules.AssembleAppleSoft(
            SdkModules.AppleSoftPath(Inputs, BasicSourceKind.Macro10),
            model);

        AssemblyResult native = SdkModules.AssembleAppleSoft(SdkModules.AppleSoftPath(Inputs), model);
        AssemblyResult standalone = AssembleShared(legacy);
        CompareRegion(legacy, native, "NXTCO1");
        CompareRegion(legacy, standalone, "NXTCO1");
        standalone.Symbol("FOR_END").Should().Be(legacy.Symbol("NXTCO1"));
    }

    /// <summary>
    ///  FOR falls directly into NEWSTT and preserves its complete bytes for every PET revision.
    /// </summary>
    /// <param name="model">The PET model.</param>
    /// <param name="original">Whether BASIC 1 or 4 uses its original chip.</param>
    [TestMethod]
    [DataRow(PetModel.Pet2001, false)]
    [DataRow(PetModel.Pet2001, true)]
    [DataRow(PetModel.Pet2001Basic2, false)]
    [DataRow(PetModel.Pet4032, false)]
    [DataRow(PetModel.Pet4032, true)]
    public void SharedForMatchesPet(PetModel model, bool original)
    {
        AssemblyResult legacy = PetLegacyBasic.Assemble(Path.Join(Inputs, "Pet"), model, original);
        AssemblyResult native = AssembleShared(legacy);
        CompareRegion(legacy, native, "NEWSTT");
        native.Symbol("FOR_END").Should().Be(legacy.Symbol("NEWSTT"));
    }

    /// <summary>
    ///  FOR and its STEP entry retain documentation and breakpoint-capable source lines.
    /// </summary>
    [TestMethod]
    public void ForRetainsDocumentationAndSourcePosition()
    {
        AssemblyResult native = SdkModules.AssembleAppleSoft(SdkModules.AppleSoftPath(Inputs), Apple2Model.IIeEnhanced);
        int start = checked((int)native.Symbol("FOR"));
        int end = checked((int)native.Symbol("NXTCO1"));
        DebugTestMemory memory = new();
        memory.Set((ushort)start, native.Sections[0].Bytes.Slice(start, end - start).ToArray());
        SourceMapModule module = new(native, area: null);
        foreach (string name in (string[])["FOR", "LDFONE"])
        {
            DocumentationTopic topic = module.Documentation.FindTopic(name)
                ?? throw new AssertFailedException($"{name} is not documented.");

            topic.Kind.Should().Be(DocumentationKind.Routine);
            topic.Path.Should().EndWith("MsBasic.For.asm");
            ushort address = checked((ushort)native.Symbol(name));
            DebugPosition position = module.Position(memory, address)
                ?? throw new AssertFailedException($"{name} has no debugger source position.");

            position.Chain.Should().ContainSingle();
            position.Chain[0].Path.Should().EndWith("MsBasic.For.asm");
            module.Entries(position.Chain[0].Path, position.Chain[0].Line).Should().Contain(address);
        }
    }

    private static AssemblyResult AssembleShared(AssemblyResult legacy)
    {
        string folder = Path.Join(Inputs, "Microsoft6502Basic");
        string source = $"""
            .cpu Mos6502
            .org ${legacy.Symbol("FOR"):X4}
            .include "MsBasic.For.asm"
            FOR_END:
            """;

        string[] dependencies =
        [
            "SUBFLG", "LET", "FNDFOR", "FORSIZ", "ADDPRC", "GETSTK", "DATAN", "TXTPTR", "CURLIN",
            "TOTK", "SYNCHR", "CHKNUM", "FRMNUM", "FACSGN", "FACHO", "INDEX", "FORPSH", "FONE",
            "MOVFM", "CHRGOT", "STEPTK", "CHRGET", "SIGN", "PUSHF", "FORPNT", "FORTK"
        ];

        Dictionary<string, long> symbols = dependencies.ToDictionary(
            name => name, name => legacy.Symbol(name), StringComparer.Ordinal);

        AssemblyResult native = new Assembler.Assembler().Assemble(
            new AssemblySource(source, Path.Join(folder, "SharedForTest.asm")),
            new AssemblyOptions(ProcessorVariant.Mos6502, 0, 0x10000)
            {
                SourceResolver = new FileAssemblySourceResolver(),
                PredefinedSymbols = BasicNames.WithCurrentNames(symbols)
            });

        native.Success.Should().BeTrue(string.Join(Environment.NewLine, native.Diagnostics.Select(diagnostic =>
            $"{diagnostic.Location?.Path}:{diagnostic.Location?.Line + 1}: {diagnostic.Message}")));

        return native;
    }

    private static void CompareRegion(AssemblyResult legacy, AssemblyResult native, string after)
    {
        int start = checked((int)legacy.Symbol("FOR"));
        int end = checked((int)legacy.Symbol(after));
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
