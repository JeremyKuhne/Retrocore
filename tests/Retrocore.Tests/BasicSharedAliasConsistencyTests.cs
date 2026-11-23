// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Debug;
using Retrocore.Documentation;
using Retrocore.Machines.Apple2;
using Retrocore.Machines.Commodore;
using Alias = (string Name, string Target, string Path, int Line);
using NativeRoot = (
    string Name,
    bool Apple,
    string Directory,
    string[] AliasFiles,
    string[] Keys,
    Retrocore.Assembler.AssemblyResult Result);

namespace Retrocore.Tests;

/// <summary>
///  Checks every platform alias against the documentation and the actual native BASIC roots.
/// </summary>
[TestClass]
public sealed class BasicSharedAliasConsistencyTests
{
    // The sources, from BasicNames.Inputs on each use, so the rename gate can run these tests on its copy.
    private static string Inputs => Path.GetFullPath(BasicNames.Inputs);
    private static string Apple => Path.Join(Inputs, "AppleSoft");
    private static string Pet => Path.Join(Inputs, "Pet");
    private static string PetBasic => Path.Join(Pet, "Basic");
    private static string Shared => Path.Join(Inputs, "Microsoft6502Basic");

    /// <summary>
    ///  All AppleSoft models and PET revisions include their own aliases, each citing the documents that give it in
    ///  that build, and expose no aliases belonging exclusively to the other platform. No shared definition gives a
    ///  vendor's name as a historical name, which would resolve in every build.
    /// </summary>
    [TestMethod]
    public void NativeRootsExposeOnlyTheirDocumentedAliases()
    {
        string[] appleFiles = AliasFiles(Apple, "AppleSoft");
        string[] petFiles = AliasFiles(PetBasic, "Commodore");
        List<NativeRoot> roots = [];
        foreach (Apple2Model model in (Apple2Model[])[Apple2Model.IIPlus, Apple2Model.IIe, Apple2Model.IIeEnhanced])
        {
            roots.Add((
                Name: $"AppleSoft {model}",
                Apple: true,
                Directory: Apple,
                AliasFiles: appleFiles,
                Keys: ["ASTIL"],
                Result: SdkModules.AssembleAppleSoft(Path.Join(Apple, "AppleSoft.asm"), model)));
        }

        foreach ((PetModel model, bool original) in ((PetModel, bool)[])
            [
                (PetModel.Pet2001, false),
                (PetModel.Pet2001, true),
                (PetModel.Pet2001Basic2, false),
                (PetModel.Pet4032, false),
                (PetModel.Pet4032, true)
            ])
        {
            roots.Add((
                Name: $"PET BASIC {model.BasicVersion()}, original={original}",
                Apple: false,
                Directory: PetBasic,
                AliasFiles: petFiles,
                Keys: BasicAttribution.PetKeys(model, original),
                Result: PetSdkModules.AssembleBasic(Pet, model, original, BasicSourceKind.Native)));
        }

        (NativeRoot Root, Alias[] Aliases)[] audits =
            [.. roots.Select(root => (Root: root, Aliases: ReadAliases(root)))];

        HashSet<string> sharedSymbols = roots.SelectMany(root => root.Result.SymbolDefinitions)
            .Where(symbol => IsWithin(symbol.Location?.Path, Shared))
            .Select(symbol => symbol.Name)
            .ToHashSet(StringComparer.Ordinal);

        HashSet<string> appleSymbols = roots.Where(root => root.Apple)
            .SelectMany(root => root.Result.Symbols.Keys).ToHashSet(StringComparer.Ordinal);

        HashSet<string> petSymbols = roots.Where(root => !root.Apple)
            .SelectMany(root => root.Result.Symbols.Keys).ToHashSet(StringComparer.Ordinal);

        HashSet<string> appleNames = audits.Where(audit => audit.Root.Apple)
            .SelectMany(audit => audit.Aliases).Select(alias => alias.Name).ToHashSet(StringComparer.Ordinal);

        HashSet<string> petNames = audits.Where(audit => !audit.Root.Apple)
            .SelectMany(audit => audit.Aliases).Select(alias => alias.Name).ToHashSet(StringComparer.Ordinal);

        foreach (string file in appleFiles.Concat(petFiles))
        {
            audits.SelectMany(audit => audit.Aliases).Where(alias => SameFile(alias.Path, file))
                .Should().NotBeEmpty($"{Path.GetFileName(file)} must define an alias in at least one build");
        }

        foreach ((NativeRoot root, Alias[] aliases) in audits)
        {
            foreach (string file in root.AliasFiles)
            {
                string[] expected = [.. aliases.Where(alias => SameFile(alias.Path, file)).Select(alias => alias.Name)];
                root.Result.SymbolDefinitions.Where(symbol => SameFile(symbol.Location?.Path, file))
                    .Select(symbol => symbol.Name)
                    .Should().BeEquivalentTo(expected, $"{root.Name} must actually include {Path.GetFileName(file)}");

                root.Result.SourceMap.Where(entry => entry.Size > 0 && SameFile(entry.Location?.Path, file))
                    .Should().BeEmpty($"{Path.GetFileName(file)} must not emit bytes");
            }

            foreach (string file in root.Apple ? petFiles : appleFiles)
            {
                root.Result.SourceMap.Where(entry => SameFile(entry.Location?.Path, file))
                    .Should().BeEmpty($"{root.Name} must not include the other platform's aliases");
            }

            HashSet<string> ownNames = aliases.Select(alias => alias.Name).ToHashSet(StringComparer.Ordinal);
            foreach (string name in (root.Apple ? petNames : appleNames).Where(name => !ownNames.Contains(name)))
            {
                root.Result.HasSymbol(name).Should().BeFalse($"{root.Name} must not expose the other platform's alias");
            }

            DocumentationSet docs = Documents(root.Result);
            BasicAttribution.AssertSharedNamesAreMicrosofts(docs);
            foreach (string name in root.Apple ? petNames : appleNames)
            {
                BasicAttribution.AssertNotShared(root.Result, docs, name);
            }

            Dictionary<string, Alias> byName = aliases.ToDictionary(alias => alias.Name, StringComparer.Ordinal);
            foreach (Alias alias in aliases)
            {
                CheckAlias(root, alias, byName, docs, sharedSymbols, root.Apple ? petSymbols : appleSymbols);
            }
        }
    }

    /// <summary>
    ///  An alias cites its documents as an <c>Also:</c> item does, by its own name and the documents' keys.
    /// </summary>
    /// <param name="text">The alias's remark.</param>
    /// <param name="expected">The keys it cites for ALIAS, comma-separated, or null for none.</param>
    [TestMethod]
    [DataRow("Commodore's name for <TARGET>: ALIAS (CBM4S79, HV4), in code19.", "CBM4S79,HV4")]
    [DataRow("Commodore's name for <TARGET>: ALIAS (HV4,\n;; HV4R), in code19.", "HV4,HV4R")]
    [DataRow("Commodore's name for <TARGET>: OTHER (HV4); ALIAS is another spelling.", null)]
    [DataRow("Commodore's name for <TARGET>: ALIAS, in code19.", null)]
    [DataRow("Commodore's name for <TARGET>: ALIAS (), in code19.", null)]
    [DataRow("Commodore's name for <TARGET>: XALIAS (HV4) and <ALIAS> (HV4R).", null)]
    public void CitationBelongsToTheAlias(string text, string? expected)
    {
        string source = $"""
            ;; An alias.
            ;;
            ;; {text}
            ALIAS = TARGET
            TARGET = $1234
            """;

        DocumentationFile file = DocumentationParser.Parse(source, Path.Join(PetBasic, "CitationFixture.asm"));
        DocumentationComment comment = file.Comments.Single(comment => comment.Name == "ALIAS");
        comment.Remarks.Should().NotBeEmpty("the fixture's citation must be a remark");

        IReadOnlyList<string>? keys = BasicAttribution.Citation(comment.Remarks, "ALIAS");
        if (expected is null)
        {
            keys.Should().BeNull();
        }
        else
        {
            keys.Should().Equal(expected.Split(','));
        }
    }

    /// <summary>
    ///  Each PET build's names come from its own reconstruction, and BASIC 4's from Commodore's listing too.
    /// </summary>
    /// <param name="model">The PET model.</param>
    /// <param name="original">Whether BASIC 1 or 4 uses its original chip.</param>
    /// <param name="expected">The documents' keys, comma-separated.</param>
    [TestMethod]
    [DataRow(PetModel.Pet2001, true, "HV1")]
    [DataRow(PetModel.Pet2001, false, "HV1R")]
    [DataRow(PetModel.Pet2001Basic2, false, "HV2")]
    [DataRow(PetModel.Pet4032, true, "HV4,CBM4S79")]
    [DataRow(PetModel.Pet4032, false, "HV4R,CBM4S79")]
    public void PetBuildsTakeTheirOwnDocuments(PetModel model, bool original, string expected)
    {
        BasicAttribution.PetKeys(model, original).Should().Equal(expected.Split(','));
        foreach (string key in BasicAttribution.PetKeys(model, original))
        {
            BasicAttribution.Bibliography.Find(key).Should().NotBeNull($"{key} must be in docs/Bibliography.md");
        }
    }

    /// <summary>
    ///  A vendor's name that can't resolve is attributed in one sentence of the remarks, with the variant, the name
    ///  and a source.
    /// </summary>
    /// <param name="text">The remarks' sentences.</param>
    /// <param name="expected">Whether they attribute ALIAS to AppleSoft and cite a source.</param>
    [TestMethod]
    [DataRow("In AppleSoft, Apple's listing calls it `ALIAS`.", true)]
    [DataRow("In AppleSoft, Apple's\n;; listing calls it `ALIAS`.", true)]
    [DataRow("In AppleSoft, a listing calls it `OTHER`. In AppleSoft, `ALIAS` is a spelling.", false)]
    [DataRow("In AppleSoft, `ALIAS`.", false)]
    [DataRow("In PET BASIC 4, a listing calls it `ALIAS`.", false)]
    [DataRow("Apple's listing calls it `ALIAS`.", false)]
    public void ProseAttributionBelongsToTheAliasAndVariant(string text, bool expected)
    {
        string source = $"""
            ;; A shared routine.
            ;;
            ;; {text}
            Target:
                rts
            """;

        DocumentationFile file = DocumentationParser.Parse(source, Path.Join(Shared, "AttributionFixture.asm"));
        DocumentationComment comment = file.Comments.Single(comment => comment.Name == "Target");
        comment.Remarks.Should().NotBeEmpty("the fixture's attribution must be a remark");
        BasicAttribution.Has(comment.Remarks, "ALIAS", "AppleSoft").Should().Be(expected);
    }

    /// <summary>
    ///  The vendor-only exception cannot hide a shared entry, an undocumented label or a constant.
    /// </summary>
    [TestMethod]
    public void VendorOnlyExceptionRequiresAPlatformRoutine()
    {
        string source = """
            ;; A platform-only routine.
            Local:
                rts
            SCALAR = $1234                  ;; A constant, not a routine.
            """;

        string path = Path.Join(PetBasic, "VendorOnlyFixture.asm");
        AssemblyResult result = new Retrocore.Assembler.Assembler().Assemble(
            new AssemblySource(source, path), new AssemblyOptions(ProcessorVariant.Mos6502, 0x1000, 0x100));

        result.Success.Should().BeTrue();
        DocumentationSet docs = DocumentationSet.Create([DocumentationParser.Parse(source, path)], result);
        AssemblySymbol local = Symbol(result, "Local", "fixture");
        DocumentationTopic? topic = docs.FindRoutineTopic("Local");
        DocumentationComment? active = ActiveComment(result, topic, "Local");
        HashSet<string> none = [with(StringComparer.Ordinal)];
        HashSet<string> present = [with(StringComparer.Ordinal), "Local"];

        IsVendorOnly(local, topic, active, PetBasic, none, none).Should().BeTrue();
        IsVendorOnly(local, topic, active, PetBasic, present, none).Should().BeFalse();
        IsVendorOnly(local, topic, active, PetBasic, none, present).Should().BeFalse();
        IsVendorOnly(local, topic, active: null, PetBasic, none, none).Should().BeFalse();

        AssemblySymbol scalar = Symbol(result, "SCALAR", "fixture");
        DocumentationTopic? scalarTopic = docs.FindRoutineTopic("SCALAR");
        IsVendorOnly(scalar, scalarTopic, ActiveComment(result, scalarTopic, "SCALAR"), PetBasic, none, none)
            .Should().BeFalse();
    }

    private static string[] AliasFiles(string directory, string prefix)
    {
        foreach (string part in (string[])["Float", "Interpreter"])
        {
            string file = Path.Join(directory, $"{prefix}.{part}Aliases.asm");
            File.Exists(file).Should().BeTrue($"the platform must retain {Path.GetFileName(file)}");
        }

        return [.. Directory.EnumerateFiles(directory, "*Aliases.asm").Select(Path.GetFullPath)
            .OrderBy(path => path, StringComparer.OrdinalIgnoreCase)];
    }

    // Parse the alias files independently so dropping an include cannot make the coverage check vacuous.
    private static Alias[] ReadAliases(NativeRoot root)
    {
        List<Alias> aliases = [];
        foreach (string path in root.AliasFiles)
        {
            // A type's members (ForFrame::TOKEN) come with their type, and a predefined name is unqualified.
            Dictionary<string, long> context = root.Result.SymbolDefinitions
                .Where(symbol => !SameFile(symbol.Location?.Path, path) && !symbol.Name.Contains("::", StringComparison.Ordinal))
                .ToDictionary(symbol => symbol.Name, symbol => symbol.Value, StringComparer.Ordinal);

            AssemblyParseResult parsed = Retrocore.Assembler.Assembler.Parse(
                new AssemblySource(File.ReadAllText(path), path),
                new AssemblyOptions(ProcessorVariant.Mos6502, 0, 0x10000)
                {
                    PredefinedSymbols = BasicNames.WithCurrentNames(context)
                });

            parsed.Success.Should().BeTrue(string.Join(Environment.NewLine, parsed.Diagnostics.Select(diagnostic =>
                $"{diagnostic.Location?.Path}:{diagnostic.Location?.Line + 1}: {diagnostic.Message}")));

            AssemblyStatement[] definitions = [.. parsed.Project.Statements.Where(statement =>
                statement.Label is not null && SameFile(statement.Location?.Path, path))];

            foreach (AssemblyStatement definition in definitions)
            {
                definition.Kind.Should().Be(AssemblyStatementKind.Constant, $"{path} must contain direct aliases");
                aliases.Add((
                    Name: definition.Label ?? throw new AssertFailedException($"Missing alias name in {path}."),
                    Target: definition.Operand.Text.Trim(),
                    Path: path,
                    Line: definition.Location?.Line ?? throw new AssertFailedException($"Missing source location in {path}.")));
            }
        }

        return [.. aliases];
    }

    private static void CheckAlias(
        NativeRoot root,
        Alias alias,
        Dictionary<string, Alias> aliases,
        DocumentationSet docs,
        HashSet<string> sharedSymbols,
        HashSet<string> foreignSymbols)
    {
        AssemblySymbol definition = Symbol(root.Result, alias.Name, root.Name);
        AssemblySymbol directTarget = Symbol(root.Result, alias.Target, $"{root.Name}: {alias.Name}'s direct target");
        definition.IsConstant.Should().BeTrue($"{alias.Name} must be an alias");
        SameFile(definition.Location?.Path, alias.Path).Should().BeTrue($"{root.Name} must include {alias.Path}");
        definition.Location?.Line.Should().Be(alias.Line);
        definition.Value.Should().Be(directTarget.Value, $"{alias.Name} must alias {alias.Target}");

        DocumentationTopic aliasTopic = docs.FindTopic(alias.Name)
            ?? throw new AssertFailedException($"{root.Name}: {alias.Name} has no alias documentation.");

        aliasTopic.Comments.Any(comment =>
            SameFile(comment.Path, alias.Path)
                && comment.TargetLine == alias.Line
                && !string.IsNullOrWhiteSpace(comment.Summary))
            .Should().BeTrue($"{alias.Name} must have its own source attribution");

        aliasTopic.Value.Should().Be(definition.Value);
        BasicAttribution.AssertCites(aliasTopic, root.Keys, target: alias.Target);

        // The target by the name it has now, which the alias may give by an old one.
        AssemblySymbol target = Symbol(root.Result, UltimateTarget(alias, aliases), $"{root.Name}: {alias.Name}'s target");
        string targetName = target.Name;
        DocumentationTopic? topic = docs.FindRoutineTopic(targetName);
        DocumentationComment? active = ActiveComment(root.Result, topic, targetName);
        bool shared = sharedSymbols.Contains(targetName)
            || topic?.Comments.Any(comment => IsWithin(comment.Path, Shared)) == true;

        if (shared)
        {
            if (active is null || !IsWithin(active.Path, Shared))
            {
                throw new AssertFailedException($"{root.Name}: {alias.Name}'s shared target {targetName} has no active shared documentation.");
            }

            BasicAttribution.AssertNotShared(root.Result, docs, alias.Name);
        }
        else
        {
            IsVendorOnly(target, topic, active, root.Directory, sharedSymbols, foreignSymbols)
                .Should().BeTrue($"{root.Name}: {targetName} must be a genuinely vendor-only routine, not an undocumented shared entry");
        }
    }

    private static string UltimateTarget(Alias alias, Dictionary<string, Alias> aliases)
    {
        HashSet<string> visited = [with(StringComparer.Ordinal), alias.Name];
        string target = alias.Target;
        while (aliases.TryGetValue(target, out Alias next))
        {
            if (!visited.Add(target)) { throw new AssertFailedException($"Alias cycle starting at {alias.Name}."); }
            target = next.Target;
        }

        return target;
    }

    private static DocumentationComment? ActiveComment(AssemblyResult result, DocumentationTopic? topic, string entry)
    {
        if (topic is null) { return null; }
        AssemblySymbol? definition = result.FindDefinition(topic.Name);
        if (definition?.Location is not { } location) { return null; }
        foreach (DocumentationComment comment in topic.Comments)
        {
            if (!SameFile(comment.Path, location.Path) || comment.TargetLine != location.Line) { continue; }
            if (topic.Name == entry || comment.Aliases.Contains(entry, StringComparer.Ordinal)) { return comment; }
            foreach (DocumentationSection section in comment.Sections)
            {
                if (section.Name.Equals("Entry", StringComparison.OrdinalIgnoreCase)
                    && section.Entries.Any(item => item.Name == entry))
                {
                    return comment;
                }
            }
        }

        return null;
    }

    private static bool IsVendorOnly(
        AssemblySymbol target,
        DocumentationTopic? topic,
        DocumentationComment? active,
        string directory,
        HashSet<string> sharedSymbols,
        HashSet<string> foreignSymbols)
    {
        if (target.IsConstant || topic?.Kind != DocumentationKind.Routine || active is null) { return false; }
        if (!IsWithin(target.Location?.Path, directory) || !IsWithin(active.Path, directory)) { return false; }
        return !sharedSymbols.Contains(target.Name) && !foreignSymbols.Contains(target.Name);
    }

    private static DocumentationSet Documents(AssemblyResult result)
    {
        string[] paths = [.. result.SourceMap.Select(entry => entry.Location?.Path)
            .Concat(result.SymbolDefinitions.Select(symbol => symbol.Location?.Path)).OfType<string>()];

        return DocumentationSet.Create(DebugDocumentation.Parse(paths), result);
    }

    private static AssemblySymbol Symbol(AssemblyResult result, string name, string context) =>
        result.FindDefinition(name)
            ?? throw new AssertFailedException($"{context}: symbol '{name}' is not defined.");

    private static bool SameFile(string? left, string right) =>
        string.Equals(left, right, StringComparison.OrdinalIgnoreCase);

    private static bool IsWithin(string? path, string directory) =>
        path is not null && path.StartsWith(directory + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase);
}
