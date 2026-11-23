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
    // The sources, from BasicNames.Inputs on each use, so the rename gate can run these tests on its copy.
    private static string Apple => Path.Join(BasicNames.Inputs, "AppleSoft");
    private static string Pet => Path.Join(BasicNames.Inputs, "Pet");
    private static string Shared => Path.Join(BasicNames.Inputs, "Microsoft6502Basic");
    private static string AppleNames => Path.Join(Apple, "AppleSoft.HistoricalNames.asm");
    private static string PetNames => Path.Join(Pet, "Basic", "Commodore.HistoricalNames.asm");

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
    ///  AppleSoft keeps its bytes and the documented comma-and-byte entry in each model; COMBYTE, Apple's name for
    ///  it, is in AppleSoft's historical names, which BasicSharedFloatAliasesTests checks entry by entry.
    /// </summary>
    /// <param name="model">The Apple II model.</param>
    [TestMethod]
    [DataRow(Apple2Model.IIPlus)]
    [DataRow(Apple2Model.IIe)]
    [DataRow(Apple2Model.IIeEnhanced)]
    public void AppleInterpreterAliasPreservesBytesAndDocumentation(Apple2Model model)
    {
        string root = Path.Join(Apple, "AppleSoft.asm");
        AssemblyResult native = SdkModules.AssembleAppleSoft(root, model);
        AssemblyResult legacy = SdkModules.AssembleAppleSoft(Path.Join(Apple, "applesoft.mac"), model);
        SdkModules.AppleSoftImage(native).ToArray().Should().Equal(SdkModules.AppleSoftImage(legacy).ToArray());
        native.Symbol("COMBYTE").Should().Be(0xE74C, "Apple TIL 76 identifies this entry");
        native.Symbol("COMBYTE").Should().Be(native.Symbol("COMBYT"));
        foreach (var entry in s_petEntries)
        {
            native.HasSymbol(entry.Name).Should().BeFalse($"{entry.Name} is a PET name");
        }

        AssemblyLocation location = native.HistoricalNames["COMBYTE"].Location
            ?? throw new AssertFailedException("COMBYTE has no source location.");

        location.Path.Should().EndWith("AppleSoft.HistoricalNames.asm");
        DocumentationSet docs = Documents(native, AppleNames);

        // Apple's published COPY and GARBAG names collide with different Microsoft labels.
        native.Symbol("COPYZC").Should().Be(0xDAB7);
        native.Symbol("COPY").Should().NotBe(native.Symbol("COPYZC"));
        native.Symbol("GARBA2").Should().Be(0xE484);
        native.Symbol("GARBAG").Should().Be(0xE474);
        AssertProse(docs, "GETSPT", "COPY");
        AssertProse(docs, "GARBA2", "GARBAG");
        AssertRoutine(native, docs, "COPYZC");

        // StoreString (GETSPT) falls into the copy: the last instruction before it is StoreString's and ends there.
        int copy = checked((int)native.Symbol("COPYZC"));
        AssemblySourceMapEntry last = native.SourceMap
            .Where(entry => entry.Size > 0 && entry.Address < copy)
            .MaxBy(entry => entry.Address)
            ?? throw new AssertFailedException("Nothing precedes COPYZC.");

        (last.Address + last.Size).Should().Be(copy, "StoreString falls into the descriptor copy");
        last.Address.Should().BeGreaterThan(checked((int)native.Symbol("GETSPT")));
        CheckDocumentation(docs, "MsBasic.MemoryAccess.asm", "MsBasic.Assignment.asm", "MsBasic.StringGarbageCollection.asm");
    }

    /// <summary>
    ///  PET revisions retain their assignment and string-function bytes, addresses and vendor names; the names are
    ///  aliases in Commodore's historical names, which cite the build's documents.
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
        AssemblyResult legacy = PetLegacyBasic.Assemble(Pet, model, original);
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

        // The included files document the macros this test does not expand (LET's, for one), whose Also: names would
        // otherwise be predefined second definitions.
        foreach (string file in (string[])["MsBasic.Assignment.asm", "MsBasic.StringConversion.asm", "MsBasic.StringFunctions.asm"])
        {
            string path = Path.Join(Shared, file);
            foreach (DocumentationAlso also in DocumentationParser.Parse(File.ReadAllText(path), path).Comments
                .SelectMany(comment => DocumentationAlso.Of(comment.Sections)))
            {
                symbols.Remove(also.Name);
            }
        }

        string assignment = linked
            ? $"""
                .include "Commodore.StringAssignment.asm"
                .org ${assignmentStart:X4}
                    StringAssignment 1, 1
                    STRING_LINK_ADJUST {(original ? 0 : 1)}
                """
            : $"""
                .org ${assignmentStart:X4}
                    StringAssignment 0, 0
                """;

        string source = $"""
            .cpu Mos6502
            .include "MsBasic.Assignment.asm"
            .include "MsBasic.StringConversion.asm"
            .include "MsBasic.StringFunctions.asm"
            {assignment}
            INTERPRETER_ASSIGNMENT_END:
            .org ${conversionStart:X4}
                StringFromNumber
            INTERPRETER_CONVERSION_END:
            .org ${functionsStart:X4}
                StringFunctions {(early ? 1 : 0)}, {(early ? 1 : 0)}, {(early ? 1 : 0)}, {(linked ? 1 : 0)}
            INTERPRETER_FUNCTIONS_END:
            """;

        AssemblyOptions options = new(ProcessorVariant.Mos6502, 0, 0x10000)
        {
            SourceResolver = new FileAssemblySourceResolver(),
            IncludePaths = [Shared],
            PredefinedSymbols = BasicNames.WithCurrentNames(symbols)
        };

        AssemblyResult native = RequireSuccess(new Retrocore.Assembler.Assembler().Assemble(
            new AssemblySource(BasicNames.ScopedNames(symbols) + "\n" + source, Path.Join(Pet, "Basic", "InterpreterAliasTest.asm")),
            options));

        native.Symbol("INTERPRETER_ASSIGNMENT_END").Should().Be(assignmentEnd);
        native.Symbol("INTERPRETER_CONVERSION_END").Should().Be(conversionEnd);
        native.Symbol("INTERPRETER_FUNCTIONS_END").Should().Be(functionsEnd);
        CompareRegion(legacy, native, assignmentStart, assignmentEnd);
        CompareRegion(legacy, native, conversionStart, conversionEnd);
        CompareRegion(legacy, native, functionsStart, functionsEnd);

        // Each Commodore name reaches, in the whole build, the address the PET listing gives it and its target's, through
        // an alias in Commodore's historical names that cites the build's documents, and the debugger resolves it to
        // its target's source.
        AssemblyResult build = PetSdkModules.AssembleBasic(Pet, model, original);
        DocumentationSet docs = Documents(native, PetNames);
        DocumentationSet buildDocs = Documents(build, PetNames);
        int versionIndex = early ? 0 : linked ? 2 : 1;
        foreach (var entry in s_petEntries)
        {
            native.HasSymbol(entry.Name).Should().BeFalse($"{entry.Name} is in Commodore's historical names, not the modules");
            build.Symbol(entry.Name).Should().Be(build.Symbol(entry.Target));
            build.Symbol(entry.Name).Should().Be(entry.Addresses[versionIndex], $"{entry.Name} must match the PET listing");
            BasicWorkspaceConversionTests.InFiles(build.HistoricalNames[entry.Name], [PetNames]).Should().BeTrue(
                $"{entry.Name} must reach {Path.GetFileName(PetNames)}");

            DocumentationTopic target = AssertAlias(
                build, buildDocs, entry.Target, entry.Name, BasicAttribution.PetKeys(model, original), BasicAttribution.CommodoreKeys);

            // BASIC 4's descriptor copy is its own, in its vendor's file; the others' source is their shared module's.
            string expectedSource = linked && entry.Target == "COPYZC"
                ? Path.Join(Pet, "Basic", "Commodore.StringAssignment.asm")
                : target.Path;

            Path.GetFileName(expectedSource).Should().NotBe(Path.GetFileName(PetNames));
            AssertDebugEntry(build, entry.Name, expectedSource);
        }

        AssertRoutine(native, docs, "COPYZC");
        native.HasSymbol("COMBYTE").Should().BeFalse("COMBYTE is an Apple name");
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

    // The descriptor copy, which the vendors' code enters, is a routine of its own after StoreString's tail.
    private static void AssertRoutine(AssemblyResult result, DocumentationSet docs, string name)
    {
        DocumentationTopic topic = docs.FindTopic(result.DefinitionName(name))
            ?? throw new AssertFailedException($"{name} has no documentation.");

        topic.Kind.Should().Be(DocumentationKind.Routine, $"{name} is a routine");
        topic.Summary.Should().NotBeNullOrWhiteSpace();
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
        DocumentationTopic topic = docs.FindTopic(result.DefinitionName(target))
            ?? throw new AssertFailedException($"{target} has no documentation.");

        DocumentationTopic alias = docs.FindTopic(result.DefinitionName(name))
            ?? throw new AssertFailedException($"{name} has no alias documentation.");

        Path.GetFullPath(alias.Path).Should().Be(Path.GetFullPath(PetNames), $"{name}'s alias is Commodore's");
        DocumentationAlso also = alias.Comments
            .Where(comment => Path.GetFullPath(comment.Path) == Path.GetFullPath(PetNames))
            .SelectMany(comment => DocumentationAlso.Of(comment.Sections))
            .SingleOrDefault(also => also.Name == name)
            ?? throw new AssertFailedException($"{name} is not in its alias's Also: section.");

        also.Sources.Should().Contain(buildKeys, $"{name} must cite the documents that give it in this build");
        also.Sources.Should().BeEquivalentTo(documentKeys, $"{name} must cite every document that gives it");
        foreach (string key in also.Sources)
        {
            BasicAttribution.Bibliography.Find(key).Should().NotBeNull($"{name} cites {key}, which must be in docs/Bibliography.md");
        }

        BasicAttribution.AssertNotShared(result, docs, name);
        return topic;
    }

    // The debugger resolves the name to its address, whose source is the target's.
    private static void AssertDebugEntry(AssemblyResult result, string name, string path)
    {
        DebugInfo debug = new();
        debug.Add(new SourceMapModule(result, area: null));
        DebugTestMemory memory = new();
        memory.Set(0, result.Sections[0].Bytes.ToArray());
        debug.Resolve(name, memory).Should().Be(result.Symbol(name));
        DebugPosition position = debug.Position(memory, checked((ushort)result.Symbol(name)))
            ?? throw new AssertFailedException($"{name} has no debugger source position.");

        Path.GetFullPath(position.Chain[0].Path).Should().Be(Path.GetFullPath(path));
    }

    // Apple's name that is another definition's in AppleSoft: it can't resolve, so the shared remarks give it.
    private static DocumentationTopic AssertProse(DocumentationSet docs, string target, string name)
    {
        DocumentationTopic topic = docs.FindTopic(target)
            ?? throw new AssertFailedException($"{target} has no shared documentation.");

        BasicAttribution.Has(topic.Remarks, name, "AppleSoft")
            .Should().BeTrue($"{target}'s remarks must attribute {name} to AppleSoft and cite its source");

        return topic;
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

    private static int Address(AssemblyResult result, string name) => checked((int)result.Symbol(name));

    private static AssemblyResult RequireSuccess(AssemblyResult result)
    {
        result.Success.Should().BeTrue(string.Join(Environment.NewLine, result.Diagnostics.Select(diagnostic =>
            $"{diagnostic.Location?.Path}:{diagnostic.Location?.Line + 1}: {diagnostic.Message}")));

        return result;
    }
}
