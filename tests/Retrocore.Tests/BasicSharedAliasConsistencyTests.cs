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
    string[] Attributions,
    Retrocore.Assembler.AssemblyResult Result);

namespace Retrocore.Tests;

/// <summary>
///  Checks every platform alias against the documentation and the actual native BASIC roots.
/// </summary>
[TestClass]
public sealed class BasicSharedAliasConsistencyTests
{
    private static readonly string s_inputs = Path.GetFullPath(Path.Join(AppContext.BaseDirectory, "Inputs"));
    private static readonly string s_apple = Path.Join(s_inputs, "AppleSoft");
    private static readonly string s_pet = Path.Join(s_inputs, "Pet");
    private static readonly string s_petBasic = Path.Join(s_pet, "Basic");
    private static readonly string s_shared = Path.Join(s_inputs, "Microsoft6502Basic");

    /// <summary>
    ///  All AppleSoft models and PET revisions include their own aliases, with attributed shared documentation,
    ///  and expose no aliases belonging exclusively to the other platform.
    /// </summary>
    [TestMethod]
    public void NativeRootsExposeOnlyTheirDocumentedAliases()
    {
        string[] appleFiles = AliasFiles(s_apple, "AppleSoft");
        string[] petFiles = AliasFiles(s_petBasic, "Commodore");
        List<NativeRoot> roots = [];
        foreach (Apple2Model model in (Apple2Model[])[Apple2Model.IIPlus, Apple2Model.IIe, Apple2Model.IIeEnhanced])
        {
            roots.Add((
                Name: $"AppleSoft {model}",
                Apple: true,
                Directory: s_apple,
                AliasFiles: appleFiles,
                Attributions: ["AppleSoft"],
                Result: SdkModules.AssembleAppleSoft(Path.Join(s_apple, "AppleSoft.asm"), model)));
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
            int version = model.BasicVersion();
            string[] attributions = version switch
            {
                1 => ["PET BASIC 1", "PET BASIC 1/2"],
                2 => ["PET BASIC 2", "PET BASIC 1/2"],
                4 => ["PET BASIC 4"],
                _ => throw new AssertFailedException($"Unexpected PET BASIC version {version}.")
            };

            roots.Add((
                Name: $"PET BASIC {version}, original={original}",
                Apple: false,
                Directory: s_petBasic,
                AliasFiles: petFiles,
                Attributions: attributions,
                Result: PetSdkModules.AssembleBasic(s_pet, model, original, BasicSourceKind.Native)));
        }

        (NativeRoot Root, Alias[] Aliases)[] audits =
            [.. roots.Select(root => (Root: root, Aliases: ReadAliases(root)))];

        HashSet<string> sharedSymbols = roots.SelectMany(root => root.Result.SymbolDefinitions)
            .Where(symbol => IsWithin(symbol.Location?.Path, s_shared))
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
                root.Result.Symbols.Should().NotContainKey(name, $"{root.Name} must not expose the other platform's alias");
            }

            DocumentationSet docs = Documents(root.Result);
            Dictionary<string, Alias> byName = aliases.ToDictionary(alias => alias.Name, StringComparer.Ordinal);
            foreach (Alias alias in aliases)
            {
                CheckAlias(root, alias, byName, docs, sharedSymbols, root.Apple ? petSymbols : appleSymbols);
            }
        }
    }

    /// <summary>
    ///  The alias, build and source attribution must occur in the same Also entry.
    /// </summary>
    /// <param name="text">An Also entry.</param>
    /// <param name="expected">Whether it attributes the alias to BASIC 4 and cites a source.</param>
    [TestMethod]
    [DataRow("PET BASIC 4: `ALIAS`, Commodore listing.", true)]
    [DataRow("PET BASIC 4: `OTHER`, listing; PET BASIC 1/2: `ALIAS`, reconstruction.", false)]
    [DataRow("PET BASIC 4: `OTHER`, listing. PET BASIC 1/2: `ALIAS`, reconstruction.", false)]
    [DataRow("PET BASIC 4: `ALIAS`", false)]
    [DataRow("PET BASIC 4: `ALIAS`,\n;;     Commodore listing.", true)]
    public void AlsoAttributionBelongsToTheAliasAndBuild(string text, bool expected)
    {
        string source = $"""
            ;; A shared routine.
            ;;
            ;; Also:
            ;;   {text}
            TARGET:
                rts
            """;

        DocumentationFile file = DocumentationParser.Parse(source, Path.Join(s_shared, "AttributionFixture.asm"));
        DocumentationSection also = file.Comments.Single(comment => comment.Name == "TARGET").Section("Also")
            ?? throw new AssertFailedException("The fixture has no Also section.");

        HasAttribution(also, "ALIAS", ["PET BASIC 4"]).Should().Be(expected);
    }

    /// <summary>
    ///  The vendor-only exception cannot hide a shared entry, an undocumented label or a constant.
    /// </summary>
    [TestMethod]
    public void VendorOnlyExceptionRequiresAPlatformRoutine()
    {
        string source = """
            ;; A platform-only routine.
            LOCAL:
                rts
            SCALAR = $1234                  ;; A constant, not a routine.
            """;

        string path = Path.Join(s_petBasic, "VendorOnlyFixture.asm");
        AssemblyResult result = new Retrocore.Assembler.Assembler().Assemble(
            new AssemblySource(source, path), new AssemblyOptions(ProcessorVariant.Mos6502, 0x1000, 0x100));

        result.Success.Should().BeTrue();
        DocumentationSet docs = DocumentationSet.Create([DocumentationParser.Parse(source, path)], result);
        AssemblySymbol local = Symbol(result, "LOCAL", "fixture");
        DocumentationTopic? topic = docs.FindRoutine("LOCAL");
        DocumentationComment? active = ActiveComment(result, topic, "LOCAL");
        HashSet<string> none = [with(StringComparer.Ordinal)];
        HashSet<string> present = [with(StringComparer.Ordinal), "LOCAL"];

        IsVendorOnly(local, topic, active, s_petBasic, none, none).Should().BeTrue();
        IsVendorOnly(local, topic, active, s_petBasic, present, none).Should().BeFalse();
        IsVendorOnly(local, topic, active, s_petBasic, none, present).Should().BeFalse();
        IsVendorOnly(local, topic, active: null, s_petBasic, none, none).Should().BeFalse();

        AssemblySymbol scalar = Symbol(result, "SCALAR", "fixture");
        DocumentationTopic? scalarTopic = docs.FindRoutine("SCALAR");
        IsVendorOnly(scalar, scalarTopic, ActiveComment(result, scalarTopic, "SCALAR"), s_petBasic, none, none)
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
            Dictionary<string, long> context = root.Result.SymbolDefinitions
                .Where(symbol => !SameFile(symbol.Location?.Path, path))
                .ToDictionary(symbol => symbol.Name, symbol => symbol.Value, StringComparer.Ordinal);

            AssemblyParseResult parsed = Retrocore.Assembler.Assembler.Parse(
                new AssemblySource(File.ReadAllText(path), path),
                new AssemblyOptions(ProcessorVariant.Mos6502, 0, 0x10000) { PredefinedSymbols = context });

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

        DocumentationTopic aliasTopic = docs.Find(alias.Name)
            ?? throw new AssertFailedException($"{root.Name}: {alias.Name} has no alias documentation.");

        aliasTopic.Comments.Any(comment =>
            SameFile(comment.Path, alias.Path)
                && comment.TargetLine == alias.Line
                && !string.IsNullOrWhiteSpace(comment.Summary))
            .Should().BeTrue($"{alias.Name} must have its own source attribution");

        aliasTopic.Value.Should().Be(definition.Value);

        string targetName = UltimateTarget(alias, aliases);
        AssemblySymbol target = Symbol(root.Result, targetName, $"{root.Name}: {alias.Name}'s target");
        DocumentationTopic? topic = docs.FindRoutine(targetName);
        DocumentationComment? active = ActiveComment(root.Result, topic, targetName);
        bool shared = sharedSymbols.Contains(targetName)
            || topic?.Comments.Any(comment => IsWithin(comment.Path, s_shared)) == true;

        if (shared)
        {
            if (active is null || !IsWithin(active.Path, s_shared))
            {
                throw new AssertFailedException($"{root.Name}: {alias.Name}'s shared target {targetName} has no active shared documentation.");
            }

            active.Sections.Where(section => section.Name.Equals("Also", StringComparison.OrdinalIgnoreCase))
                .Any(section => HasAttribution(section, alias.Name, root.Attributions))
                .Should().BeTrue($"{root.Name}: {targetName}'s Also section must attribute {alias.Name} and cite its source");
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
        AssemblySymbol? definition = result.SymbolDefinitions.FirstOrDefault(symbol => symbol.Name == topic.Name);
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

    private static bool HasAttribution(DocumentationSection section, string name, string[] variants)
    {
        string marker = $"`{name}`";
        foreach (string entry in AttributionEntries(section))
        {
            int colon = entry.IndexOf(':');
            if (colon < 0 || !variants.Contains(entry[..colon].Trim(), StringComparer.OrdinalIgnoreCase)) { continue; }

            int end = entry.Length;
            int apple = entry.IndexOf("AppleSoft:", colon + 1, StringComparison.OrdinalIgnoreCase);
            int pet = entry.IndexOf("PET BASIC ", colon + 1, StringComparison.OrdinalIgnoreCase);
            if (apple >= 0) { end = Math.Min(end, apple); }
            if (pet >= 0) { end = Math.Min(end, pet); }
            int at = entry.IndexOf(marker, colon + 1, StringComparison.Ordinal);
            if (at < 0 || at >= end) { continue; }
            int comma = entry.IndexOf(',', at + marker.Length);
            if (comma >= 0 && comma < end && entry[(comma + 1)..end].Trim().TrimEnd('.').Length != 0) { return true; }
        }

        return false;
    }

    private static List<string> AttributionEntries(DocumentationSection section)
    {
        List<string> groups = [];
        string? current = null;
        int indentation = 0;
        foreach (string line in section.Lines)
        {
            string text = line.Trim();
            if (text.Length == 0) { continue; }
            int indent = line.Length - line.TrimStart().Length;
            if (current is null || indent <= indentation)
            {
                if (current is not null) { groups.Add(current); }
                current = text;
                indentation = indent;
            }
            else
            {
                current += $" {text}";
            }
        }

        if (current is not null) { groups.Add(current); }
        return [.. groups.SelectMany(group => group.Split(';', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))];
    }

    private static DocumentationSet Documents(AssemblyResult result)
    {
        string[] paths = [.. result.SourceMap.Select(entry => entry.Location?.Path)
            .Concat(result.SymbolDefinitions.Select(symbol => symbol.Location?.Path)).OfType<string>()];

        return DocumentationSet.Create(DebugDocumentation.Parse(paths), result);
    }

    private static AssemblySymbol Symbol(AssemblyResult result, string name, string context) =>
        result.SymbolDefinitions.FirstOrDefault(symbol => symbol.Name == name)
            ?? throw new AssertFailedException($"{context}: symbol '{name}' is not defined.");

    private static bool SameFile(string? left, string right) =>
        string.Equals(left, right, StringComparison.OrdinalIgnoreCase);

    private static bool IsWithin(string? path, string directory) =>
        path is not null && path.StartsWith(directory + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase);
}
