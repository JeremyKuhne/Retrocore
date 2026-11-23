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
///  The shared operator table preserves each Microsoft BASIC variant's precedence and handlers.
/// </summary>
[TestClass]
public sealed class BasicSharedOperatorTableTests
{
    private static string Inputs => BasicNames.Inputs;

    /// <summary>
    ///  AppleSoft uses the shared table, including its Boolean operator entries.
    /// </summary>
    /// <param name="model">The Apple II model.</param>
    [TestMethod]
    [DataRow(Apple2Model.IIPlus)]
    [DataRow(Apple2Model.IIe)]
    [DataRow(Apple2Model.IIeEnhanced)]
    public void AppleSoftUsesTheSharedTable(Apple2Model model)
    {
        AssemblyResult legacy = SdkModules.AssembleAppleSoft(
            SdkModules.AppleSoftPath(Inputs, BasicSourceKind.Macro10),
            model);

        AssemblyResult native = SdkModules.AssembleAppleSoft(SdkModules.AppleSoftPath(Inputs), model);

        CompareTable(legacy, AssembleTable(legacy, powerBelowNegation: true, highNot: true, andEntry: "OROP1"));
        CompareTable(legacy, native);
        AssemblySymbol definition = native.Definition("OPTAB");
        definition.Location?.Path.Should().EndWith("MsBasic.OperatorTable.asm");
        DocumentationTopic? topic = new SourceMapModule(native, area: null).Documentation.FindTopic("OPTAB");
        topic.Should().NotBeNull();
        topic?.Path.Should().EndWith("MsBasic.OperatorTable.asm");
        topic?.Summary.Should().NotBeNullOrWhiteSpace();
    }

    /// <summary>
    ///  PET BASIC uses the same table shape with its bitwise handlers and precedence.
    /// </summary>
    /// <param name="model">The PET model.</param>
    /// <param name="original">Whether BASIC 1 or 4 uses its original chip.</param>
    [TestMethod]
    [DataRow(PetModel.Pet2001, false)]
    [DataRow(PetModel.Pet2001, true)]
    [DataRow(PetModel.Pet2001Basic2, false)]
    [DataRow(PetModel.Pet4032, false)]
    [DataRow(PetModel.Pet4032, true)]
    public void SharedTableMatchesPet(PetModel model, bool original)
    {
        AssemblyResult legacy = PetLegacyBasic.Assemble(Path.Join(Inputs, "Pet"), model, original);
        CompareTable(legacy, AssembleTable(legacy, powerBelowNegation: false, highNot: false, andEntry: "ANDOP"));
    }

    /// <summary>
    ///  The precedence switches and AND handler can be selected independently for another variant.
    /// </summary>
    /// <param name="powerBelowNegation">Whether power uses AppleSoft's precedence.</param>
    /// <param name="highNot">Whether NOT uses AppleSoft's precedence.</param>
    [TestMethod]
    [DataRow(true, false)]
    [DataRow(false, true)]
    public void PrecedenceChoicesAreIndependent(bool powerBelowNegation, bool highNot)
    {
        AssemblyResult apple = SdkModules.AssembleAppleSoft(
            SdkModules.AppleSoftPath(Inputs, BasicSourceKind.Macro10),
            Apple2Model.IIeEnhanced);

        AssemblyResult pet = PetLegacyBasic.Assemble(Path.Join(Inputs, "Pet"), PetModel.Pet2001Basic2);
        AssemblyResult mixed = AssembleTable(pet, powerBelowNegation, highNot, "ANDOP");

        ByteAt(mixed, "OPTAB", 12).Should().Be(ByteAt(powerBelowNegation ? apple : pet, "OPTAB", 12));
        ByteAt(mixed, "NEGTAB").Should().Be(ByteAt(powerBelowNegation ? apple : pet, "NEGTAB"));
        ByteAt(mixed, "NOTTAB").Should().Be(ByteAt(highNot ? apple : pet, "NOTTAB"));
        int andEntry = checked((int)mixed.Symbol("OPTAB")) + 16;
        int petAndEntry = checked((int)pet.Symbol("OPTAB")) + 16;
        mixed.Sections[0].Bytes.Slice(andEntry, 2).ToArray()
            .Should().Equal(pet.Sections[0].Bytes.Slice(petAndEntry, 2).ToArray());
    }

    /// <summary>
    ///  An unsupported operator-table selector fails rather than silently choosing a variant.
    /// </summary>
    /// <param name="powerBelowNegation">The power/negation selector.</param>
    /// <param name="highNot">The NOT selector.</param>
    /// <param name="message">The expected diagnostic.</param>
    [TestMethod]
    [DataRow(-1, 0, "powerBelowNegation is 0 or 1.")]
    [DataRow(2, 0, "powerBelowNegation is 0 or 1.")]
    [DataRow(0, -1, "highNot is 0 or 1.")]
    [DataRow(0, 2, "highNot is 0 or 1.")]
    public void InvalidOperatorSelectorIsRejected(int powerBelowNegation, int highNot, string message)
    {
        string folder = Path.Join(Inputs, "Microsoft6502Basic");
        string source = $"""
            .cpu Mos6502
            .include "MsBasic.OperatorTable.asm"
            .org $C000
                OPERATOR_TABLE {powerBelowNegation}, {highNot}, ANDOP
            """;

        string[] dependencies =
            ["FADDT", "FSUBT", "FMULTT", "FDIVT", "FPWRT", "OROP1", "ANDOP", "OROP", "NEGOP", "NOTOP", "DOREL"];

        AssemblyResult result = new Assembler.Assembler().Assemble(
            new AssemblySource(source, Path.Join(folder, "InvalidOperatorTableTest.asm")),
            new AssemblyOptions(ProcessorVariant.Mos6502, 0, 0x10000)
            {
                SourceResolver = new FileAssemblySourceResolver(),
                PredefinedSymbols = BasicNames.WithCurrentNames(dependencies.ToDictionary(name => name, _ => 0xD000L))
            });

        result.Success.Should().BeFalse();
        result.Diagnostics.Should().Contain(diagnostic =>
            diagnostic.Message.Contains(message, StringComparison.Ordinal));
    }

    private static AssemblyResult AssembleTable(
        AssemblyResult legacy, bool powerBelowNegation, bool highNot, string andEntry)
    {
        int start = checked((int)legacy.Symbol("OPTAB"));
        string folder = Path.Join(Inputs, "Microsoft6502Basic");
        string source = $"""
            .cpu Mos6502
            .include "MsBasic.OperatorTable.asm"
            .org ${start:X4}
                OPERATOR_TABLE {(powerBelowNegation ? 1 : 0)}, {(highNot ? 1 : 0)}, {andEntry}
            OPERATOR_TABLE_END:
            """;

        string[] dependencies =
        [
            "FADDT", "FSUBT", "FMULTT", "FDIVT", "FPWRT", andEntry,
            "OROP", "NEGOP", "NOTOP", "DOREL"
        ];

        AssemblyOptions options = new(ProcessorVariant.Mos6502, 0, 0x10000)
        {
            SourceResolver = new FileAssemblySourceResolver(),
            PredefinedSymbols = BasicNames.WithCurrentNames(dependencies.ToDictionary(name => name, name => legacy.Symbol(name)))
        };

        AssemblyResult result = new Assembler.Assembler().Assemble(
            new AssemblySource(source, Path.Join(folder, "OperatorTableTest.asm")),
            options);

        result.Success.Should().BeTrue(string.Join(Environment.NewLine, result.Diagnostics.Select(diagnostic =>
            $"{diagnostic.Location?.Path}:{diagnostic.Location?.Line + 1}: {diagnostic.Message}")));

        result.Symbol("OPERATOR_TABLE_END").Should().Be(legacy.Symbol("RESLST"));
        return result;
    }

    private static void CompareTable(AssemblyResult legacy, AssemblyResult native)
    {
        int start = checked((int)legacy.Symbol("OPTAB"));
        int length = checked((int)(legacy.Symbol("RESLST") - start));
        foreach (string name in (string[])["OPTAB", "NEGTAB", "NOTTAB", "PTDORL"])
        {
            native.Symbol(name).Should().Be(legacy.Symbol(name), $"{name} must retain its ROM address");
        }

        native.Sections[0].Bytes.Slice(start, length).ToArray()
            .Should().Equal(legacy.Sections[0].Bytes.Slice(start, length).ToArray());
    }

    private static byte ByteAt(AssemblyResult result, string label, int offset = 0) =>
        result.Sections[0].Bytes.Span[checked((int)result.Symbol(label)) + offset];
}
