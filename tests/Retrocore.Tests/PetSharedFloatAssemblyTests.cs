// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Debug;
using Retrocore.Debug.Language;
using Retrocore.Documentation;
using Retrocore.Machines.Commodore;

namespace Retrocore.Tests;

/// <summary>
///  Compares the composed native PET math package with the independent MACRO-10 BASIC builds.
/// </summary>
[TestClass]
public sealed class PetSharedFloatAssemblyTests
{
    private const string EndLabel = "PET_TEST_END_OF_FLOAT";

    // The character reader's template: 24 bytes of code and five of seed.
    private const int TemplateSize = 29;

    private static string Inputs => BasicNames.Inputs;
    private static string PetInputs => Path.Join(Inputs, "Pet");
    private static string SharedInputs => Path.Join(Inputs, "Microsoft6502Basic");

    /// <summary>
    ///  Every byte and legacy label from FADDH through the byte before INITAT comes from the native module.
    /// </summary>
    /// <param name="model">The PET model.</param>
    /// <param name="original">Whether BASIC 1 or 4 uses its original chip.</param>
    /// <param name="expectedStart">The historical FADDH address.</param>
    /// <param name="expectedEnd">The historical address immediately after the math package.</param>
    [TestMethod]
    [DataRow(PetModel.Pet2001, false, 0xD71E, 0xE0B5)]
    [DataRow(PetModel.Pet2001, true, 0xD71E, 0xE0B5)]
    [DataRow(PetModel.Pet2001Basic2, false, 0xD72C, 0xE0F9)]
    [DataRow(PetModel.Pet4032, false, 0xC97F, 0xD399)]
    [DataRow(PetModel.Pet4032, true, 0xC97F, 0xD399)]
    public void NativeMathMatchesTheLegacyBuild(PetModel model, bool original, int expectedStart, int expectedEnd)
    {
        (AssemblyResult legacy, AssemblyResult native) = Assemble(model, original);
        int start = checked((int)legacy.Symbol("FADDH"));
        int end = checked((int)legacy.Symbol("INITAT"));
        start.Should().Be(expectedStart);
        end.Should().Be(expectedEnd);
        native.Symbol(EndLabel).Should().Be(end, "the native module must end immediately before INITAT");

        // Fixed-size sections are zero-filled, so both assemblies must actually emit the whole comparison range.
        AssertEmittedSpan(legacy, start, end, exact: false);
        AssertEmittedSpan(native, start, end, exact: true);
        ReadOnlySpan<byte> expected = legacy.Sections[0].Bytes.Span.Slice(start, end - start);
        ReadOnlySpan<byte> actual = native.Sections[0].Bytes.Span.Slice(start, end - start);
        int firstDifference = actual.CommonPrefixLength(expected);
        firstDifference.Should().Be(expected.Length, $"the first different byte is at ${start + firstDifference:X4}");

        AssemblySymbol[] labels = legacy.SymbolDefinitions
            .Where(symbol => !symbol.IsConstant && symbol.Value >= start && symbol.Value < end)
            .ToArray();

        labels.Should().NotBeEmpty();
        foreach (AssemblySymbol label in labels)
        {
            AssemblySymbol nativeLabel = native.FindDefinition(label.Name)
                ?? throw new AssertFailedException($"The native module does not define legacy label {label.Name}.");

            nativeLabel.Value.Should().Be(label.Value, $"{label.Name} must retain its legacy address");
            // Stacked labels may legitimately become an assignment alias, but never a supplied external symbol.
            AssemblyLocation location = nativeLabel.Location
                ?? throw new AssertFailedException($"{label.Name} must have a physical definition.");

            location.Path.Should().NotBe("<predefined>", $"{label.Name} belongs to the math module");
        }

        bool basic1 = model == PetModel.Pet2001;
        bool basic2 = model == PetModel.Pet2001Basic2;
        int zero = checked((int)native.Symbol("ZERO"));
        zero.Should().Be(checked((int)legacy.Symbol("ZERO")));
        if (basic1)
        {
            zero.Should().BeLessThan(start, "BASIC 1's ZERO is outside the math package");
        }
        else
        {
            zero.Should().Be(checked((int)native.Symbol("FHALF") + 2), "later BASICs share ZERO with FHALF");
        }

        ReadOnlySpan<byte> image = native.Sections[0].Bytes.Span;
        image[checked((int)native.Symbol("FMULTT"))].Should().Be(basic1 ? (byte)0xF0 : (byte)0xD0);
        image[checked((int)native.Symbol("FINEDG")) + 3].Should().Be(basic1 ? (byte)12 : (byte)10);
        image[checked((int)native.Symbol("NZ9999")) + 4].Should().Be(basic1 ? (byte)0xFE : (byte)0xFD);

        int sineTail = checked((int)(legacy.Symbol("ATN") - legacy.Symbol("SINCON") - 31));
        sineTail.Should().Be(basic2 ? 10 : 0, "only BASIC 2 has the WAIT message after the sine coefficients");
        if (basic2)
        {
            native.Symbol("ZSTORD").Should().Be(legacy.Symbol("FSUBT") + 15);
        }

        int paddingStart = checked((int)legacy.Symbol("NZMIL") + 5);
        int paddingLength = checked((int)legacy.Symbol("INPRT") - paddingStart);
        if (model == PetModel.Pet4032)
        {
            paddingLength.Should().Be(0x80);
            image[paddingStart].Should().Be(0xF9);
            native.Sections[0].Bytes.Slice(paddingStart + 1, paddingLength - 1).ToArray()
                .Should().OnlyContain(value => value == 0xAA, "BASIC 4 fills the rest of the chip with $AA");

            end.Should().BeLessThan(PetSdkModules.EditorOrigin);
        }
        else
        {
            paddingLength.Should().Be(0);
            start.Should().BeLessThan(PetSdkModules.EditorOrigin);
            end.Should().BeGreaterThan(PetSdkModules.EditorOrigin, "BASIC 1 and 2 continue into the editor ROM");
            native.SourceMap.Should().Contain(entry => entry.Size > 0
                && entry.Address <= PetSdkModules.EditorOrigin
                && entry.Address + entry.Size > PetSdkModules.EditorOrigin);
        }
    }

    /// <summary>
    ///  A shared routine and BASIC 2's WAIT message retain their physical documentation and debugger source chains.
    /// </summary>
    [TestMethod]
    public void SharedAndWaitRoutinesRetainDocumentationAndSourceChains()
    {
        (AssemblyResult legacy, AssemblyResult native) = Assemble(PetModel.Pet2001Basic2, original: false, withTemplate: true);
        int start = checked((int)legacy.Symbol("FADDH"));
        int end = checked((int)legacy.Symbol("INITAT")) + TemplateSize;
        DebugTestMemory memory = new();
        memory.Set((ushort)start, native.Sections[0].Bytes.Slice(start, end - start).ToArray());
        SourceMapModule module = new(native, area: null);

        ushort addition = checked((ushort)native.Symbol("FADDH"));
        DebugPosition shared = module.Position(memory, addition)
            ?? throw new AssertFailedException("FADDH has no debugger source position.");

        shared.Chain[0].Path.Should().EndWith("MsBasic.AdditionCore.asm");
        SourceLine invocation = shared.Chain.First(line => line.Path.EndsWith("Commodore.FloatingPoint.asm", StringComparison.Ordinal));
        module.Entries(shared.Chain[0].Path, shared.Chain[0].Line).Should().Contain(addition);
        module.Entries(invocation.Path, invocation.Line).Should().Contain(addition);

        ushort wait = checked((ushort)native.Symbol("ZSTORD"));
        DebugPosition waitPosition = module.Position(memory, wait)
            ?? throw new AssertFailedException("BASIC 2's WAIT message has no debugger source position.");

        waitPosition.Chain[0].Path.Should().EndWith("Commodore.FloatingPoint.asm");
        module.Entries(waitPosition.Chain[0].Path, waitPosition.Chain[0].Line).Should().Contain(wait);

        DocumentationSet docs = module.Documentation;
        foreach ((string name, string file) in ((string, string)[])
            [("FADDH", "MsBasic.AdditionCore.asm"), ("ZSTORD", "Commodore.FloatingPoint.asm")])
        {
            DocumentationTopic topic = docs.FindTopic(name) ?? throw new AssertFailedException($"{name} is not documented.");
            topic.Kind.Should().Be(DocumentationKind.Routine);
            topic.Value.Should().Be(native.Symbol(name));
            topic.Path.Should().EndWith(file);
            topic.Summary.Should().NotBeNullOrWhiteSpace();
        }

        List<DocumentationDiagnostic> problems = new DocumentationResolver(
            docs,
            isDirective: name => DirectiveDocs.Describe(name) is not null,
            isInstruction: InstructionDocs.IsMnemonic).Check();

        problems.Should().BeEmpty(string.Join(Environment.NewLine, problems.Select(problem =>
            $"{Path.GetFileName(problem.Path)}:{problem.Line + 1}: {problem.Message}")));
    }

    private static void AssertEmittedSpan(AssemblyResult result, int start, int end, bool exact)
    {
        IEnumerable<AssemblySourceMapEntry> entries = result.SourceMap.Where(entry =>
            entry.Size > 0 && entry.Operation != ".ORG");

        if (!exact)
        {
            entries = entries.Where(entry => entry.Address < end && entry.Address + entry.Size > start);
        }

        int next = start;
        foreach (AssemblySourceMapEntry entry in entries.OrderBy(entry => entry.Address))
        {
            entry.Section.Should().Be(0);
            int first = exact ? entry.Address : Math.Max(start, entry.Address);
            first.Should().Be(next, $"the emission at ${entry.Address:X4} must not leave a gap or overlap");
            next = exact ? entry.Address + entry.Size : Math.Min(end, entry.Address + entry.Size);
        }

        next.Should().Be(end, "the entire math package must be emitted, with no extra native output");
    }

    private static (AssemblyResult Legacy, AssemblyResult Native) Assemble(
        PetModel model,
        bool original,
        bool withTemplate = false)
    {
        AssemblyResult legacy = PetLegacyBasic.Assemble(PetInputs, model, original);
        int start = checked((int)legacy.Symbol("FADDH"));

        // Commodore's historical names alias two labels of the character reader's template, which follows the math
        // region; a build that checks their documentation assembles the template too.
        int end = checked((int)legacy.Symbol("INITAT")) + (withTemplate ? TemplateSize : 0);

        // Also exclude address-valued assignments in this range: aliases must not satisfy local references for us.
        Dictionary<string, long> symbols = legacy.SymbolDefinitions
            .Where(symbol => symbol.Value < start || symbol.Value >= end)
            .ToDictionary(symbol => symbol.Name, symbol => symbol.Value, StringComparer.Ordinal);

        // The character reader's file also holds the letter test, whose Also: names ISLETC and ISLRTS. The template's
        // build does not use them, and predefining them would make them second definitions of those old names.
        if (withTemplate)
        {
            symbols.Remove("ISLETC");
            symbols.Remove("ISLRTS");
        }

        bool basic1 = model == PetModel.Pet2001;
        symbols.Add("SHORT_MULTIPLY_ZERO", basic1 ? 1 : 0);
        symbols.Add("EARLY_INPUT_EXPONENT_LIMIT", basic1 ? 1 : 0);
        symbols.Add("PRECISE_OUTPUT_LIMIT", basic1 ? 1 : 0);
        symbols.Add("ZERO_IN_HALF_CONSTANT", basic1 ? 0 : 1);
        symbols.Add("WAIT_EASTER_EGG", model == PetModel.Pet2001Basic2 ? 1 : 0);
        symbols.Add("BASIC4_OUTPUT_PADDING", model == PetModel.Pet4032 ? 1 : 0);

        string source = $"""
            .cpu Mos6502
            {BasicNames.ScopedNames(symbols)}
            .org ${start:X4}
            .include "Commodore.FloatingPoint.asm"
            {EndLabel}:
            {(withTemplate ? $".include \"MsBasic.CharacterReader.asm\"\n    CharacterReader {(basic1 ? "$59" : "$58")}" : "")}
            .include "Commodore.HistoricalNames.asm"
            """;

        AssemblyOptions options = new(ProcessorVariant.Mos6502, 0, 0x10000)
        {
            SourceResolver = new FileAssemblySourceResolver(),
            IncludePaths = [SharedInputs],
            PredefinedSymbols = BasicNames.WithCurrentNames(symbols)
        };

        AssemblyResult native = new Retrocore.Assembler.Assembler().Assemble(
            new AssemblySource(source, Path.Join(PetInputs, "Basic", "FloatRegionTest.asm")),
            options);

        native.Success.Should().BeTrue(string.Join(Environment.NewLine, native.Diagnostics.Select(diagnostic =>
            $"{diagnostic.Location?.Path}:{diagnostic.Location?.Line + 1}: {diagnostic.Message}")));

        return (legacy, native);
    }
}
