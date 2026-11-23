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
///  Checks documented Apple and PET interpreter names against their shared entries.
/// </summary>
[TestClass]
public sealed class BasicSharedInterpreterAliasesTests
{
    private static readonly string s_inputs = Path.Join(AppContext.BaseDirectory, "Inputs");
    private static readonly string s_apple = Path.Join(s_inputs, "AppleSoft");
    private static readonly string s_pet = Path.Join(s_inputs, "Pet");
    private static readonly string s_shared = Path.Join(s_inputs, "Microsoft6502Basic");
    private static readonly string s_appleAliases = Path.Join(s_apple, "AppleSoft.InterpreterAliases.asm");
    private static readonly string s_petAliases = Path.Join(s_pet, "Basic", "Commodore.InterpreterAliases.asm");

    // Addresses in the independently assembled PET1, PET2 and PET4 reconstructions:
    // https://github.com/ethandicks/cbmsymbols/tree/e3120427a32e8b066eb8afdc434af547fd0906f3/listings
    private static readonly (string Name, string Target, int[] Addresses)[] s_petEntries =
    [
        ("COPYC", "COPYZC", [0xC967, 0xC973, 0xBA13]),
        ("STRD", "STR", [0xD349, 0xD33F, 0xC58E]),
        ("CHRD", "CHR", [0xD5C4, 0xD5C6, 0xC822]),
        ("LEFTD", "LEFT", [0xD5D8, 0xD5DA, 0xC836]),
        ("RIGHTD", "RIGHT", [0xD604, 0xD606, 0xC862]),
        ("MIDD", "MID", [0xD60F, 0xD611, 0xC86D])
    ];

    /// <summary>
    ///  AppleSoft keeps its bytes and the documented comma-and-byte entry in each model.
    /// </summary>
    /// <param name="model">The Apple II model.</param>
    [TestMethod]
    [DataRow(Apple2Model.IIPlus)]
    [DataRow(Apple2Model.IIe)]
    [DataRow(Apple2Model.IIeEnhanced)]
    public void AppleInterpreterAliasPreservesBytesAndDocumentation(Apple2Model model)
    {
        string root = Path.Join(s_apple, "AppleSoft.asm");
        AssemblyResult native = SdkModules.AssembleAppleSoft(root, model);
        AssemblyResult legacy = SdkModules.AssembleAppleSoft(Path.Join(s_apple, "applesoft.mac"), model);
        SdkModules.AppleSoftImage(native).ToArray().Should().Equal(SdkModules.AppleSoftImage(legacy).ToArray());
        native.Symbols["COMBYTE"].Should().Be(0xE74C, "Apple TIL 76 identifies this entry");
        native.Symbols["COMBYTE"].Should().Be(native.Symbols["COMBYT"]);
        foreach (var entry in s_petEntries) { native.Symbols.Should().NotContainKey(entry.Name); }

        AssertAliasFile(native, s_appleAliases, ["COMBYTE"]);
        DocumentationSet docs = Documents(native, s_appleAliases);
        DocumentationTopic comma = AssertAlias(native, docs, "COMBYT", "COMBYTE", ["ASTIL"], ["ASTIL", "AS82"]);
        AssertDebugEntry(native, "COMBYTE", comma.Path);

        // Apple's published COPY and GARBAG names collide with different Microsoft labels.
        native.Symbols["COPYZC"].Should().Be(0xDAB7);
        native.Symbols["COPY"].Should().NotBe(native.Symbols["COPYZC"]);
        native.Symbols["GARBA2"].Should().Be(0xE484);
        native.Symbols["GARBAG"].Should().Be(0xE474);
        DocumentationTopic assignment = AssertProse(docs, "GETSPT", "COPY");
        AssertProse(docs, "GARBA2", "GARBAG");
        assignment.EntryLabels.Should().Contain("COPYZC");
        CheckDocumentation(docs, "MsBasic.MemoryAccess.asm", "MsBasic.Assignment.asm", "MsBasic.StringGarbageCollection.asm");
    }

    /// <summary>
    ///  PET revisions retain their assignment and string-function bytes, addresses and vendor names.
    /// </summary>
    /// <param name="model">The PET model.</param>
    /// <param name="original">Whether BASIC 1 or 4 uses its original chip.</param>
    [TestMethod]
    [DataRow(PetModel.Pet2001, false)]
    [DataRow(PetModel.Pet2001, true)]
    [DataRow(PetModel.Pet2001Basic2, false)]
    [DataRow(PetModel.Pet4032, false)]
    [DataRow(PetModel.Pet4032, true)]
    public void PetInterpreterAliasesPreserveBytesAndDocumentation(PetModel model, bool original)
    {
        AssemblyResult legacy = PetLegacyBasic.Assemble(s_pet, model, original);
        bool early = model == PetModel.Pet2001;
        bool linked = model == PetModel.Pet4032;
        int assignmentStart = Address(legacy, "GETSPT");
        int assignmentEnd = Address(legacy, "PRINTN");
        int conversionStart = Address(legacy, "STR");
        int conversionEnd = Address(legacy, "STRINI");
        int functionsStart = Address(legacy, "CHR");
        int functionsEnd = Address(legacy, "GETNUM");
        Dictionary<string, long> symbols = legacy.SymbolDefinitions
            .Where(symbol => symbol.Value < assignmentStart || symbol.Value >= assignmentEnd)
            .Where(symbol => symbol.Value < conversionStart || symbol.Value >= conversionEnd)
            .Where(symbol => symbol.Value < functionsStart || symbol.Value >= functionsEnd)
            .ToDictionary(symbol => symbol.Name, symbol => symbol.Value, StringComparer.Ordinal);

        string assignment = linked
            ? $"""
                .include "Commodore.StringAssignment.asm"
                .org ${assignmentStart:X4}
                    STRING_ASSIGNMENT 1, 1
                    STRING_LINK_ADJUST {(original ? 0 : 1)}
                """
            : $"""
                .org ${assignmentStart:X4}
                    STRING_ASSIGNMENT 0, 0
                """;

        string source = $"""
            .cpu Mos6502
            .include "MsBasic.Assignment.asm"
            .include "MsBasic.StringConversion.asm"
            .include "MsBasic.StringFunctions.asm"
            {assignment}
            INTERPRETER_ASSIGNMENT_END:
            .org ${conversionStart:X4}
                STRING_FROM_NUMBER
            INTERPRETER_CONVERSION_END:
            .org ${functionsStart:X4}
                STRING_FUNCTIONS {(early ? 1 : 0)}, {(early ? 1 : 0)}, {(early ? 1 : 0)}, {(linked ? 1 : 0)}
            INTERPRETER_FUNCTIONS_END:
            .include "Commodore.InterpreterAliases.asm"
            INTERPRETER_ALIASES_END:
            """;

        AssemblyOptions options = new(ProcessorVariant.Mos6502, 0, 0x10000)
        {
            SourceResolver = new FileAssemblySourceResolver(),
            IncludePaths = [s_shared],
            PredefinedSymbols = symbols
        };

        AssemblyResult native = RequireSuccess(new Retrocore.Assembler.Assembler().Assemble(
            new AssemblySource(source, Path.Join(s_pet, "Basic", "InterpreterAliasTest.asm")), options));

        native.Symbols["INTERPRETER_ASSIGNMENT_END"].Should().Be(assignmentEnd);
        native.Symbols["INTERPRETER_CONVERSION_END"].Should().Be(conversionEnd);
        native.Symbols["INTERPRETER_FUNCTIONS_END"].Should().Be(functionsEnd);
        native.Symbols["INTERPRETER_ALIASES_END"].Should().Be(functionsEnd);
        CompareRegion(legacy, native, assignmentStart, assignmentEnd);
        CompareRegion(legacy, native, conversionStart, conversionEnd);
        CompareRegion(legacy, native, functionsStart, functionsEnd);

        AssertAliasFile(native, s_petAliases, [.. s_petEntries.Select(entry => entry.Name)]);
        DocumentationSet docs = Documents(native, s_petAliases);
        int versionIndex = early ? 0 : linked ? 2 : 1;
        foreach (var entry in s_petEntries)
        {
            native.Symbols[entry.Name].Should().Be(native.Symbols[entry.Target]);
            native.Symbols[entry.Name].Should().Be(entry.Addresses[versionIndex], $"{entry.Name} must match the PET listing");
            string topic = entry.Target == "COPYZC" ? "GETSPT" : entry.Target;
            DocumentationTopic documented = AssertAlias(
                native, docs, topic, entry.Name, BasicAttribution.PetKeys(model, original), BasicAttribution.CommodoreKeys);

            string path = linked && entry.Target == "COPYZC"
                ? Path.Join(s_pet, "Basic", "Commodore.StringAssignment.asm")
                : documented.Path;

            AssertDebugEntry(native, entry.Name, path);
        }

        (docs.Find("GETSPT") ?? throw new AssertFailedException("GETSPT has no shared documentation."))
            .EntryLabels.Should().Contain("COPYZC");

        native.Symbols.Should().NotContainKey("COMBYTE");
        CheckDocumentation(docs, "MsBasic.Assignment.asm", "MsBasic.StringConversion.asm", "MsBasic.StringFunctions.asm");
    }

    private static void CompareRegion(AssemblyResult legacy, AssemblyResult native, int start, int end)
    {
        native.Sections[0].Bytes.Slice(start, end - start).ToArray()
            .Should().Equal(legacy.Sections[0].Bytes.Slice(start, end - start).ToArray());

        int next = start;
        foreach (AssemblySourceMapEntry entry in native.SourceMap.Where(entry =>
            entry.Size > 0 && entry.Operation != ".ORG" && entry.Address >= start && entry.Address < end)
            .OrderBy(entry => entry.Address))
        {
            entry.Address.Should().Be(next, "the native region must not have a gap or overlap");
            next += entry.Size;
        }

        next.Should().Be(end);
    }

    private static void AssertAliasFile(AssemblyResult result, string path, string[] expected)
    {
        string full = Path.GetFullPath(path);
        result.SymbolDefinitions
            .Where(symbol => symbol.Location is { } location
                && string.Equals(Path.GetFullPath(location.Path), full, StringComparison.OrdinalIgnoreCase))
            .Select(symbol => symbol.Name)
            .Should().BeEquivalentTo(expected, "the alias file must define precisely the documented names");

        result.SourceMap.Where(entry => entry.Size > 0
            && entry.Location is { } location
            && string.Equals(Path.GetFullPath(location.Path), full, StringComparison.OrdinalIgnoreCase))
            .Should().BeEmpty("aliases must not emit bytes");

        DocumentationSet docs = Documents(result, path);
        foreach (string name in expected)
        {
            DocumentationTopic alias = docs.Find(name)
                ?? throw new AssertFailedException($"{name} has no alias documentation.");

            Path.GetFullPath(alias.Path).Should().Be(full);
            alias.Value.Should().Be(result.Symbols[name]);
            alias.Summary.Should().NotBeNullOrWhiteSpace();
        }
    }

    // The vendor's alias cites the documents that give its name, and the shared definition doesn't give the name.
    private static DocumentationTopic AssertAlias(
        AssemblyResult result,
        DocumentationSet docs,
        string target,
        string name,
        string[] buildKeys,
        string[] documentKeys)
    {
        DocumentationTopic topic = docs.Find(target)
            ?? throw new AssertFailedException($"{target} has no shared documentation.");

        DocumentationTopic alias = docs.Find(name)
            ?? throw new AssertFailedException($"{name} has no alias documentation.");

        BasicAttribution.AssertCites(alias, buildKeys, documentKeys);
        BasicAttribution.AssertNotShared(result, docs, target, name);
        return topic;
    }

    // Apple's name that is another definition's in AppleSoft: it can't resolve, so the shared remarks give it.
    private static DocumentationTopic AssertProse(DocumentationSet docs, string target, string name)
    {
        DocumentationTopic topic = docs.Find(target)
            ?? throw new AssertFailedException($"{target} has no shared documentation.");

        BasicAttribution.Has(topic.Remarks, name, "AppleSoft")
            .Should().BeTrue($"{target}'s remarks must attribute {name} to AppleSoft and cite its source");

        return topic;
    }

    private static void AssertDebugEntry(AssemblyResult result, string name, string path)
    {
        DebugInfo debug = new();
        debug.Add(new SourceMapModule(result, area: null));
        DebugTestMemory memory = new();
        memory.Set(0, result.Sections[0].Bytes.ToArray());
        debug.Resolve(name, memory).Should().Be(result.Symbols[name]);
        DebugPosition position = debug.Position(memory, checked((ushort)result.Symbols[name]))
            ?? throw new AssertFailedException($"{name} has no debugger source position.");

        Path.GetFullPath(position.Chain[0].Path).Should().Be(Path.GetFullPath(path));
    }

    private static DocumentationSet Documents(AssemblyResult result, string aliases)
    {
        IEnumerable<string> paths = result.SourceMap.Select(entry => entry.Location?.Path)
            .Concat(result.SymbolDefinitions.Select(symbol => symbol.Location?.Path))
            .OfType<string>()
            .Append(aliases);

        return DocumentationSet.Create(DebugDocumentation.Parse(paths), result);
    }

    private static void CheckDocumentation(DocumentationSet docs, params string[] files)
    {
        DocumentationResolver resolver = new(
            docs,
            isDirective: name => DirectiveDocs.Describe(name) is not null,
            isInstruction: InstructionDocs.IsMnemonic);

        List<DocumentationDiagnostic> diagnostics = [.. resolver.Check().Where(diagnostic => files.Contains(Path.GetFileName(diagnostic.Path), StringComparer.Ordinal))];

        diagnostics.Should().BeEmpty(string.Join(Environment.NewLine, diagnostics.Select(diagnostic =>
            $"{Path.GetFileName(diagnostic.Path)}:{diagnostic.Line + 1}: {diagnostic.Message}")));
    }

    private static int Address(AssemblyResult result, string name) => checked((int)result.Symbols[name]);

    private static AssemblyResult RequireSuccess(AssemblyResult result)
    {
        result.Success.Should().BeTrue(string.Join(Environment.NewLine, result.Diagnostics.Select(diagnostic =>
            $"{diagnostic.Location?.Path}:{diagnostic.Location?.Line + 1}: {diagnostic.Message}")));

        return result;
    }
}
