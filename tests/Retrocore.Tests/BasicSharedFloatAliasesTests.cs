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
///  Checks the vendors' historical names for the shared floating-point definitions: each a scoped alias in the
///  vendor's historical-names file that resolves only in that vendor's builds.
/// </summary>
[TestClass]
public sealed class BasicSharedFloatAliasesTests
{
    // The sources, from BasicNames.Inputs on each use, so the rename gate can run these tests on its copy.
    private static string Apple => Path.Join(BasicNames.Inputs, "AppleSoft");
    private static string Pet => Path.Join(BasicNames.Inputs, "Pet");
    private static string Shared => Path.Join(BasicNames.Inputs, "Microsoft6502Basic");
    private static string AppleAliases => Path.Join(Apple, "AppleSoft.HistoricalNames.asm");
    private static string PetAliases => Path.Join(Pet, "Basic", "Commodore.HistoricalNames.asm");

    // AppleSoft's names for shared definitions, with the documents that give each.
    private static readonly Dictionary<string, string[]> s_appleNames = new(StringComparer.Ordinal)
    {
        ["PRNTFAC"] = ["ASTIL"],
        ["FOUT13"] = ["UNKN"],
        ["OVERFLOW"] = ["AS82"],
        ["FIDVT"] = ["ASTIL"],
        ["INSRTDIG"] = ["AS82"],
        ["LOGSER"] = ["AS82"],
        ["BILLION"] = ["AS82"],
        ["MISMTCH"] = ["AS82"],
        ["NEW"] = ["ASTIL", "AS82"],
        ["COMBYTE"] = ["ASTIL", "AS82"],
        ["GOLST1"] = ["UNKN"],
        ["GRODY1"] = ["UNKN"],
        ["GRODY2"] = ["UNKN"],
        ["PRIT31"] = ["UNKN"],
        ["PRIT32"] = ["UNKN"],
        ["REMER1"] = ["UNKN"]
    };

    // The names Microsoft's source gives only in its Commodore builds, with the documents that give each.
    private static readonly Dictionary<string, string[]> s_microsoftPetNames = new(StringComparer.Ordinal)
    {
        ["MULLN2"] = ["M6502", "CBM4S79", "HV4", "HV4R"],
        ["GFDIV"] = ["M6502"]
    };

    // The Commodore reconstructions' spellings of the character reader's labels, which BASIC 1 and 2 take.
    private static readonly Dictionary<string, string[]> s_hoffmannVetterNames = new(StringComparer.Ordinal)
    {
        ["CHDGOT"] = ["HV1", "HV1R", "HV2"],
        ["CHDRTS"] = ["HV1", "HV1R", "HV2"]
    };

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
        foreach (string petName in s_petAddresses.Keys.Concat(s_microsoftPetNames.Keys))
        {
            native.HasSymbol(petName).Should().BeFalse($"{petName} is a PET name");
        }

        // Each old name reaches the address the MACRO-10 build gives it, where that build has it.
        foreach (string name in s_appleNames.Keys.Where(name => legacy.HasSymbol(name)))
        {
            native.Symbol(name).Should().Be(legacy.Symbol(name), $"{name} must keep the overlay's value");
        }

        CheckAliases(native, AppleAliases, s_appleNames, pet: null);
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

        // The character reader's template follows the math region, and Commodore's historical names alias two of its
        // labels: 24 bytes of code and five of seed.
        int templateEnd = end + 29;
        Dictionary<string, long> symbols = legacy.SymbolDefinitions
            .Where(symbol => symbol.Value < start || symbol.Value >= templateEnd)
            .ToDictionary(symbol => symbol.Name, symbol => symbol.Value, StringComparer.Ordinal);

        // The character reader's file also holds the letter test, whose Also: names ISLETC and ISLRTS: the region
        // does not use them, and predefining them would make them second definitions of its old names.
        symbols.Remove("ISLETC");
        symbols.Remove("ISLRTS");

        // BASIC 4's lister names, which the whole builds' tests check, would define the aliases without the lister.
        symbols.Remove("RESCR2");
        symbols.Remove("PRIT3B");

        bool basic1 = model == PetModel.Pet2001;
        bool basic2 = model == PetModel.Pet2001Basic2;
        symbols.Add("SHORT_MULTIPLY_ZERO", basic1 ? 1 : 0);
        symbols.Add("EARLY_INPUT_EXPONENT_LIMIT", basic1 ? 1 : 0);
        symbols.Add("PRECISE_OUTPUT_LIMIT", basic1 ? 1 : 0);
        symbols.Add("ZERO_IN_HALF_CONSTANT", basic1 ? 0 : 1);
        symbols.Add("WAIT_EASTER_EGG", basic2 ? 1 : 0);
        symbols.Add("BASIC4_OUTPUT_PADDING", model == PetModel.Pet4032 ? 1 : 0);

        string source = $"""
            .cpu Mos6502
            .org ${start:X4}
            {BasicNames.ScopedNames(symbols)}
            .include "Commodore.FloatingPoint.asm"
            FLOAT_ALIAS_BEFORE:
            .include "Commodore.HistoricalNames.asm"
            FLOAT_ALIAS_AFTER:
            .include "MsBasic.CharacterReader.asm"
                CharacterReader {(basic1 ? "$59" : "$58")}
            TEMPLATE_END:
            """;

        AssemblyOptions options = new(ProcessorVariant.Mos6502, 0, 0x10000)
        {
            SourceResolver = new FileAssemblySourceResolver(),
            IncludePaths = [Shared],
            PredefinedSymbols = BasicNames.WithCurrentNames(symbols, PetSdkModules.AssembleBasic(Pet, model, original))
        };

        AssemblyResult native = RequireSuccess(new Retrocore.Assembler.Assembler().Assemble(
            new AssemblySource(source, Path.Join(Pet, "Basic", "FloatAliasTest.asm")), options));

        native.Symbol("FLOAT_ALIAS_BEFORE").Should().Be(end);
        native.Symbol("FLOAT_ALIAS_AFTER").Should().Be(end);
        native.Symbol("TEMPLATE_END").Should().Be(templateEnd);
        native.Sections[0].Bytes.Slice(start, templateEnd - start).ToArray()
            .Should().Equal(legacy.Sections[0].Bytes.Slice(start, templateEnd - start).ToArray());

        int next = start;
        foreach (AssemblySourceMapEntry entry in native.SourceMap
            .Where(entry => entry.Size > 0 && entry.Operation != ".ORG")
            .OrderBy(entry => entry.Address))
        {
            entry.Address.Should().Be(next, "the native math region must have no gaps or overlaps");
            next += entry.Size;
        }

        next.Should().Be(templateEnd);
        int versionIndex = basic1 ? 0 : basic2 ? 1 : 2;
        foreach ((string name, int[] addresses) in s_petAddresses)
        {
            native.Symbol(name).Should().Be(addresses[versionIndex], $"{name} must match the PET listing");
        }

        foreach (string name in s_microsoftPetNames.Keys)
        {
            native.Symbol(name).Should().Be(legacy.Symbol(name), $"{name} must keep the overlay's value");
        }

        foreach (string appleName in s_appleNames.Keys)
        {
            native.HasSymbol(appleName).Should().BeFalse($"{appleName} is an Apple name");
        }

        Dictionary<string, string[]> names = s_petAddresses.Keys
            .ToDictionary(name => name, _ => BasicAttribution.CommodoreKeys, StringComparer.Ordinal);

        // BASIC 4's source leaves the character reader's labels unnamed, so only BASIC 1 and 2 take the spellings.
        IEnumerable<KeyValuePair<string, string[]>> spellings = model == PetModel.Pet4032 ? [] : s_hoffmannVetterNames;
        foreach ((string name, string[] keys) in s_microsoftPetNames.Concat(spellings))
        {
            names.Add(name, keys);
        }

        CheckAliases(native, PetAliases, names, (model, original));
        CheckDocumentation(native, PetAliases);
    }

    // Each alias in the file is a scoped constant, documented above it, whose Also: section gives the vendor's
    // names; each name resolves to its target through the alias, and to no shared definition.
    private static void CheckAliases(
        AssemblyResult result,
        string path,
        Dictionary<string, string[]> expected,
        (PetModel Model, bool Original)? pet)
    {
        string full = Path.GetFullPath(path);
        bool InFile(string? location) =>
            location is not null && string.Equals(Path.GetFullPath(location), full, StringComparison.OrdinalIgnoreCase);

        AssemblySymbol[] definitions = [.. result.SymbolDefinitions.Where(symbol => InFile(symbol.Location?.Path))];
        definitions.Should().NotBeEmpty();
        definitions.Should().OnlyContain(
            symbol => symbol.IsConstant && symbol.Name.Contains("::", StringComparison.Ordinal),
            "the file defines only scoped aliases");

        result.SourceMap.Where(entry => entry.Size > 0 && InFile(entry.Location?.Path))
            .Should().BeEmpty("aliases must not emit bytes");

        // The old names the file gives, from its own text: every alias gives at least one.
        DocumentationFile file = DocumentationParser.Parse(File.ReadAllText(path), path);
        // A name the build leaves out (BASIC 4's, in the other builds) must not be expected there either.
        IEnumerable<DocumentationAlso> inBuild = file.Comments
            .SelectMany(comment => DocumentationAlso.Of(comment.Sections))
            .Where(also => expected.ContainsKey(also.Name) || result.HistoricalNames.ContainsKey(also.Name));

        DocumentationAlso[] given = [.. inBuild];
        given.Select(also => also.Name).Should().BeEquivalentTo(expected.Keys);

        DocumentationSet docs = Documents(result, path);
        DebugInfo debug = new();
        SourceMapModule module = new(result, area: null);
        debug.Add(module);
        DebugTestMemory memory = new();
        memory.Set(0, result.Sections[0].Bytes.ToArray());

        foreach (DocumentationAlso also in given)
        {
            string name = also.Name;
            result.HistoricalNames.Should().ContainKey(name, $"{name} must be a historical name in this build");
            AssemblySymbol alias = result.HistoricalNames[name];
            definitions.Select(symbol => symbol.Name).Should().ContainSingle(
                definition => definition == alias.Name, $"{name} must reach its vendor's alias");

            // The target is the definition the alias equates to, documented in the shared modules.
            DocumentationTopic aliasTopic = docs.FindTopic(alias.Name)
                ?? throw new AssertFailedException($"{alias.Name} has no documentation.");

            aliasTopic.Value.Should().Be(result.Symbol(alias.Name));
            DocumentationSection inherit = aliasTopic.Section("Inherit")
                ?? throw new AssertFailedException($"{alias.Name} must inherit its target's documentation.");

            // An absolute link (<::Name>) reaches a top-level definition an alias of the same name would hide.
            string target = inherit.Text.Trim().Trim('<', '>');
            target = target.StartsWith("::", StringComparison.Ordinal) ? target[2..] : target;
            result.Symbol(name).Should().Be(result.Symbol(target), $"{name} must alias {target}");
            debug.Resolve(name, memory).Should().Be(result.Symbol(target));

            DocumentationTopic topic = docs.FindRoutineTopic(target)
                ?? throw new AssertFailedException($"{target} has no shared documentation.");

            Path.GetFullPath(topic.Path).Should().StartWith(Path.GetFullPath(Shared) + Path.DirectorySeparatorChar);
            topic.Value.Should().Be(result.Symbol(target));
            docs.FindTopic(name).Should().BeSameAs(aliasTopic, $"{name} must lead to its vendor's alias");

            // The documents: those that give the name, each in the bibliography, and this build's among them.
            also.Sources.Should().BeEquivalentTo(expected[name], $"{name} must cite every document that gives it");
            foreach (string key in also.Sources)
            {
                BasicAttribution.Bibliography.Find(key).Should().NotBeNull($"{name} cites {key}, which must be in docs/Bibliography.md");
            }

            if (pet is { } build && !also.Sources.Contains("M6502"))
            {
                also.Sources.Should().Contain(BasicAttribution.PetKeys(build.Model, build.Original),
                    $"{name} must cite the documents that give it in this build");
            }

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
