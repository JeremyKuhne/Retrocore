// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Debug;
using Retrocore.Debug.Language;
using Retrocore.Documentation;
using Retrocore.Machines.Apple2;
using Retrocore.Machines.Commodore;

namespace Retrocore.Tests;

/// <summary>
///  Checks documented Apple and PET names against the shared floating-point definitions.
/// </summary>
[TestClass]
public sealed class BasicSharedFloatAliasesTests
{
    // The sources, from BasicNames.Inputs on each use, so the rename gate can run these tests on its copy.
    private static string Apple => Path.Join(BasicNames.Inputs, "AppleSoft");
    private static string Pet => Path.Join(BasicNames.Inputs, "Pet");
    private static string Shared => Path.Join(BasicNames.Inputs, "Microsoft6502Basic");
    private static string AppleAliases => Path.Join(Apple, "AppleSoft.FloatAliases.asm");
    private static string PetAliases => Path.Join(Pet, "Basic", "Commodore.FloatAliases.asm");

    // Addresses in the independently assembled PET1, PET2 and PET4 listings:
    // https://github.com/ethandicks/cbmsymbols/tree/e3120427a32e8b066eb8afdc434af547fd0906f3/listings
    private static readonly Dictionary<string, int[]> s_petAddresses = new(StringComparer.Ordinal)
    {
        ["SQR05"] = [0xD8AB, 0xD8E2, 0xCB0C],
        ["SQR20"] = [0xD8B0, 0xD8E7, 0xCB11],
        ["TENC"] = [0xD9CB, 0xDA05, 0xCC2F],
        ["N0999"] = [0xDC85, 0xDCBF, 0xCEE9],
        ["N9999"] = [0xDC8A, 0xDCC4, 0xCEEE],
        ["NMIL"] = [0xDC8F, 0xDCC9, 0xCEF3],
        ["RMULC"] = [0xDF3D, 0xDF77, 0xD221],
        ["RADDC"] = [0xDF41, 0xDF7B, 0xD225]
    };

    /// <summary>
    ///  Each AppleSoft model retains its ROM bytes, documentation and Apple-only print entry.
    /// </summary>
    /// <param name="model">The Apple II model.</param>
    [TestMethod]
    [DataRow(Apple2Model.IIPlus)]
    [DataRow(Apple2Model.IIe)]
    [DataRow(Apple2Model.IIeEnhanced)]
    public void AppleSoftAliasesPreserveBytesAndDocumentation(Apple2Model model)
    {
        string root = Path.Join(Apple, "AppleSoft.asm");
        AssemblyOptions options = new(ProcessorVariant.Mos6502, 0, 0x10000)
        {
            SourceResolver = new FileAssemblySourceResolver(),
            IncludePaths = [Shared],
            PredefinedSymbols = BasicNames.WithCurrentNames(new Dictionary<string, long>
            {
                ["ENHNCD"] = model == Apple2Model.IIeEnhanced ? 1 : 0,
                ["APLPLS"] = model == Apple2Model.IIPlus ? 1 : 0
            })
        };

        AssemblyResult native = RequireSuccess(new Retrocore.Assembler.Assembler().Assemble(
            new AssemblySource(File.ReadAllText(root), root), options));

        AssemblyResult legacy = SdkModules.AssembleAppleSoft(Path.Join(Apple, "applesoft.mac"), model);
        SdkModules.AppleSoftImage(native).ToArray().Should().Equal(SdkModules.AppleSoftImage(legacy).ToArray());
        native.Symbol("PRNTFAC").Should().Be(0xED2E, "Apple TIL 79 specifies this entry");
        foreach (string petName in s_petAddresses.Keys)
        {
            native.HasSymbol(petName).Should().BeFalse($"{petName} is a PET name");
        }

        CheckAliases(native, AppleAliases, ["PRNTFAC"], ["ASTIL"], ["ASTIL"]);
        CheckDocumentation(native, AppleAliases);
    }

    /// <summary>
    ///  Every PET revision preserves the entire shared math region and its documented Commodore names.
    /// </summary>
    /// <param name="model">The PET model.</param>
    /// <param name="original">Whether BASIC 1 or 4 uses its original chip.</param>
    [TestMethod]
    [DataRow(PetModel.Pet2001, false)]
    [DataRow(PetModel.Pet2001, true)]
    [DataRow(PetModel.Pet2001Basic2, false)]
    [DataRow(PetModel.Pet4032, false)]
    [DataRow(PetModel.Pet4032, true)]
    public void PetAliasesPreserveBytesAndDocumentation(PetModel model, bool original)
    {
        AssemblyResult legacy = PetLegacyBasic.Assemble(Pet, model, original);
        int start = checked((int)legacy.Symbol("FADDH"));
        int end = checked((int)legacy.Symbol("INITAT"));
        Dictionary<string, long> symbols = legacy.SymbolDefinitions
            .Where(symbol => symbol.Value < start || symbol.Value >= end)
            .ToDictionary(symbol => symbol.Name, symbol => symbol.Value, StringComparer.Ordinal);

        bool basic1 = model == PetModel.Pet2001;
        bool basic2 = model == PetModel.Pet2001Basic2;
        symbols.Add("SHORT_FMUL_ZERO", basic1 ? 1 : 0);
        symbols.Add("EARLY_FIN_LIMIT", basic1 ? 1 : 0);
        symbols.Add("PRECISE_FOUT_LIMIT", basic1 ? 1 : 0);
        symbols.Add("ZERO_AT_FHALF", basic1 ? 0 : 1);
        symbols.Add("WAIT_EASTER_EGG", basic2 ? 1 : 0);
        symbols.Add("BASIC4_OUTPUT_PADDING", model == PetModel.Pet4032 ? 1 : 0);

        string source = $"""
            .cpu Mos6502
            .org ${start:X4}
            .include "Commodore.FloatingPoint.asm"
            FLOAT_ALIAS_BEFORE:
            .include "Commodore.FloatAliases.asm"
            FLOAT_ALIAS_AFTER:
            """;

        AssemblyOptions options = new(ProcessorVariant.Mos6502, 0, 0x10000)
        {
            SourceResolver = new FileAssemblySourceResolver(),
            IncludePaths = [Shared],
            PredefinedSymbols = BasicNames.WithCurrentNames(symbols)
        };

        AssemblyResult native = RequireSuccess(new Retrocore.Assembler.Assembler().Assemble(
            new AssemblySource(source, Path.Join(Pet, "Basic", "FloatAliasTest.asm")), options));

        native.Symbol("FLOAT_ALIAS_BEFORE").Should().Be(end);
        native.Symbol("FLOAT_ALIAS_AFTER").Should().Be(end);
        native.Sections[0].Bytes.Slice(start, end - start).ToArray()
            .Should().Equal(legacy.Sections[0].Bytes.Slice(start, end - start).ToArray());

        int next = start;
        foreach (AssemblySourceMapEntry entry in native.SourceMap
            .Where(entry => entry.Size > 0 && entry.Operation != ".ORG")
            .OrderBy(entry => entry.Address))
        {
            entry.Address.Should().Be(next, "the native math region must have no gaps or overlaps");
            next += entry.Size;
        }

        next.Should().Be(end);
        int versionIndex = basic1 ? 0 : basic2 ? 1 : 2;
        foreach ((string name, int[] addresses) in s_petAddresses)
        {
            native.Symbol(name).Should().Be(addresses[versionIndex], $"{name} must match the PET listing");
        }

        native.HasSymbol("PRNTFAC").Should().BeFalse("PRNTFAC is an Apple name");
        CheckAliases(native, PetAliases, [.. s_petAddresses.Keys], BasicAttribution.PetKeys(model, original), BasicAttribution.CommodoreKeys);
        CheckDocumentation(native, PetAliases);
    }

    private static void CheckAliases(
        AssemblyResult result,
        string path,
        string[] expected,
        string[] buildKeys,
        string[] documentKeys)
    {
        // Each alias is an equate, documented by the ;; block above it.
        (string Name, string Target)[] aliases = [.. File.ReadLines(path)
            .Select(line => line.Split(';', 2)[0])
            .Where(code => code.Contains('='))
            .Select(code => code.Split('=', 2, StringSplitOptions.TrimEntries))
            .Select(parts => (parts[0], parts[1]))];

        aliases.Select(alias => alias.Name).Should().BeEquivalentTo(expected);
        result.SymbolDefinitions
            .Where(symbol => symbol.Location is { } location
                && string.Equals(Path.GetFullPath(location.Path), Path.GetFullPath(path), StringComparison.OrdinalIgnoreCase))
            .Select(symbol => symbol.Name)
            .Should().BeEquivalentTo(aliases.Select(alias => alias.Name), "all file definitions must be documented aliases");

        result.SourceMap.Where(entry => entry.Size > 0
            && entry.Location is { } location
            && string.Equals(Path.GetFullPath(location.Path), Path.GetFullPath(path), StringComparison.OrdinalIgnoreCase))
            .Should().BeEmpty("aliases must not emit bytes");

        DocumentationSet docs = Documents(result, path);
        DebugInfo debug = new();
        SourceMapModule module = new(result, area: null);
        debug.Add(module);
        DebugTestMemory memory = new();
        memory.Set(0, result.Sections[0].Bytes.ToArray());

        foreach ((string name, string target) in aliases)
        {
            result.HasSymbol(target).Should().BeTrue($"{name}'s target {target} must be defined");
            result.Symbol(name).Should().Be(result.Symbol(target), $"{name} must alias {target}");
            debug.Resolve(name, memory).Should().Be(result.Symbol(target));

            DocumentationTopic alias = docs.FindTopic(name)
                ?? throw new AssertFailedException($"{name} has no alias documentation.");

            alias.Summary.Should().NotBeNullOrWhiteSpace();
            Path.GetFullPath(alias.Path).Should().Be(Path.GetFullPath(path));
            alias.Value.Should().Be(result.Symbol(name));
            BasicAttribution.AssertCites(alias, buildKeys, documentKeys, target);

            DocumentationTopic topic = docs.FindTopic(target)
                ?? throw new AssertFailedException($"{target} has no shared documentation.");

            Path.GetFullPath(topic.Path).Should().StartWith(Path.GetFullPath(Shared) + Path.DirectorySeparatorChar);
            topic.Value.Should().Be(result.Symbol(target));

            BasicAttribution.AssertNotShared(result, docs, name);

            DebugPosition position = debug.Position(memory, checked((ushort)result.Symbol(name)))
                ?? throw new AssertFailedException($"{name} has no debugger source position.");

            position.Chain[0].Path.Should().Be(topic.Path);
        }
    }

    private static void CheckDocumentation(AssemblyResult result, string aliases)
    {
        DocumentationSet docs = Documents(result, aliases);
        List<DocumentationDiagnostic> diagnostics = new DocumentationResolver(
            docs,
            isDirective: name => DirectiveDocs.Describe(name) is not null,
            isInstruction: InstructionDocs.IsMnemonic).Check();

        diagnostics.Should().BeEmpty(string.Join(Environment.NewLine, diagnostics.Select(diagnostic =>
            $"{Path.GetFileName(diagnostic.Path)}:{diagnostic.Line + 1}: {diagnostic.Message}")));
    }

    private static DocumentationSet Documents(AssemblyResult result, string aliases)
    {
        IEnumerable<string> paths = result.SourceMap.Select(entry => entry.Location?.Path)
            .Concat(result.SymbolDefinitions.Select(symbol => symbol.Location?.Path))
            .OfType<string>()
            .Append(aliases);

        return DocumentationSet.Create(DebugDocumentation.Parse(paths), result);
    }

    private static AssemblyResult RequireSuccess(AssemblyResult result)
    {
        result.Success.Should().BeTrue(string.Join(Environment.NewLine, result.Diagnostics.Select(diagnostic =>
            $"{diagnostic.Location?.Path}:{diagnostic.Location?.Line + 1}: {diagnostic.Message}")));

        return result;
    }
}
