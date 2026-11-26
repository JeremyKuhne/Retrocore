// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Documentation;
using Retrocore.Isa;
using System.Collections.Concurrent;
using System.Text.RegularExpressions;

using Retrocore.Debug.Project;

namespace Retrocore.Debug.Language;

/// <summary>
///  One assembly of a root file and everything it includes, indexed for the language features.
/// </summary>
internal sealed partial class SourceAnalysis
{
    private const int AddressSpaceSize = 0x10000;

    private readonly Dictionary<string, List<SymbolSite>> _definitions = [with(StringComparer.OrdinalIgnoreCase)];
    private readonly List<(AssemblyLocation? Location, InstructionSet Cpu)> _cpuDirectives = [];
    private readonly List<(int Line, InstructionSet Cpu)> _rootCpus = [];
    private readonly Dictionary<string, Dictionary<AssemblyLocation, List<(int Line, InstructionSet Cpu)>>> _includeCpus =
        [with(StringComparer.OrdinalIgnoreCase)];
    private readonly Dictionary<string, AssemblyDialect> _dialects = [with(StringComparer.OrdinalIgnoreCase)];
    private readonly Dictionary<string, string[]> _lines = [with(StringComparer.OrdinalIgnoreCase)];

    // Full paths by the path as the assembly gave it, filled while the constructor runs.
    private readonly Dictionary<string, string> _fullPaths = [with(StringComparer.Ordinal)];

    // Full paths upper-cased for the keys of _usingOrder and the assembled lines, filled while the constructor runs.
    private readonly Dictionary<string, string> _upperPaths = [with(StringComparer.Ordinal)];
    private readonly Func<string, string?> _text;

    // Filled lazily, and language requests run in parallel: a cache entry is computed whole and then published.
    private readonly ConcurrentDictionary<string, IReadOnlyList<IReadOnlyList<DocumentationScopes>>> _scopes = new(StringComparer.OrdinalIgnoreCase);
    private HashSet<string>? _scopeNames;
    private readonly Dictionary<string, List<(string Path, int Line)>> _includedFrom = [with(StringComparer.OrdinalIgnoreCase)];
    private readonly Dictionary<string, HashSet<int>> _usingLines = [with(StringComparer.OrdinalIgnoreCase)];
    private readonly Dictionary<string, Dictionary<int, List<string[]>>> _invokedUsings = [with(StringComparer.OrdinalIgnoreCase)];
    // Keyed by the upper-cased path, as the other path-keyed maps here compare paths without case.
    private readonly Dictionary<(string Path, int Line), int> _usingOrder = [];
    private readonly Dictionary<string, int> _scopeOpened = [with(StringComparer.OrdinalIgnoreCase)];

    // Definitions found only in the text, such as in a branch the assembly skipped.
    private readonly HashSet<SymbolSite> _textOnly = [];

    // Built once under the lock, as requests run in parallel with each other and with the publishing of diagnostics,
    // and the resolver, the lint and a hover's link compare sets by reference: every caller gets the same instance.
    private DocumentationSet? _documentation;
    private object? _documentationLock;

    private SourceAnalysis(
        string root,
        AssemblyResult result,
        AssemblyProject project,
        IEnumerable<string> members,
        Func<string, string?> text,
        Func<string, string[]?> linesOf)
    {
        Root = root;
        Result = result;
        foreach (AssemblyStatement statement in project.Statements)
        {
            if (statement.Kind == AssemblyStatementKind.Cpu
                && statement.Label is null
                && CpuCatalog.InstructionSets.TryGetValue(statement.Operand.Text.Trim(), out InstructionSet? cpu))
            {
                _cpuDirectives.Add((statement.Location, cpu));
            }
        }

        // Each include occurrence can enter under a different CPU; its nested switches take effect after the include line.
        InstructionSet? current = _cpuDirectives.FirstOrDefault().Cpu;
        if (current is not null) { _rootCpus.Add((0, current)); }
        HashSet<string> entered = [with(StringComparer.OrdinalIgnoreCase)];
        foreach (AssemblyStatement statement in project.Statements)
        {
            for (AssemblyLocation? location = statement.Location; current is not null && location is not null; location = location.ExpandedFrom)
            {
                if (location is { Path.Length: > 0, ExpandedFrom: { } from, IsMacroExpansion: false })
                {
                    string path = FullPath(location.Path);
                    if (!_includeCpus.TryGetValue(path, out Dictionary<AssemblyLocation, List<(int Line, InstructionSet Cpu)>>? contexts))
                    {
                        _includeCpus[path] = contexts = [];
                    }

                    if (!contexts.ContainsKey(from)) { contexts.Add(from, [(0, current)]); }
                    if (entered.Add(path) && location.Line > 0)
                    {
                        _cpuDirectives.Add((new AssemblyLocation(path, 0), current));
                    }
                }
            }

            if (statement.Kind == AssemblyStatementKind.Cpu
                && statement.Label is null
                && CpuCatalog.InstructionSets.TryGetValue(statement.Operand.Text.Trim(), out InstructionSet? cpu))
            {
                current = cpu;
                for (AssemblyLocation? location = statement.Location; location is not null; location = location.ExpandedFrom)
                {
                    if (location is { Path.Length: > 0, ExpandedFrom: null }
                        && string.Equals(FullPath(location.Path), root, StringComparison.OrdinalIgnoreCase))
                    {
                        int line = ReferenceEquals(location, statement.Location) ? location.Line : location.Line + 1;
                        _rootCpus.Add((line, cpu));
                    }

                    if (location is { Path.Length: > 0, ExpandedFrom: { } from, IsMacroExpansion: false }
                        && _includeCpus.TryGetValue(FullPath(location.Path), out var contexts)
                        && contexts.TryGetValue(from, out var runs))
                    {
                        int line = ReferenceEquals(location, statement.Location) ? location.Line : location.Line + 1;
                        runs.Add((line, cpu));
                    }
                }
            }
        }

        _text = text;
        Members = new(members, StringComparer.OrdinalIgnoreCase) { root };

        // The members' lines: an open document's split from its text, a file on disk's shared with the assembly through
        // the file cache. Later lookups of other files read them afresh.
        foreach (string member in Members)
        {
            if (linesOf(member) is { } split) { _lines[member] = split; }
        }

        List<string> scopes = [];
        List<string?> opened = [];
        for (int index = 0; index < project.Statements.Count; index++)
        {
            AssemblyStatement statement = project.Statements[index];
            RecordScopeOrder(statement, index, opened);
            if (statement.Location is not { Path.Length: > 0 } location) { continue; }
            string path = FullPath(location.Path);
            if (_lines.ContainsKey(path))
            {
                _dialects.TryAdd(path, statement.Dialect);
            }

            // An included file is inside the scopes around its .include line.
            if (!location.IsMacroExpansion && location.ExpandedFrom is { Path.Length: > 0 } include)
            {
                // An .include in a macro's body is in the scope where the macro is invoked.
                AssemblyLocation from = include;
                while (from.IsMacroExpansion && from.ExpandedFrom is { Path.Length: > 0 } invocation)
                {
                    from = invocation;
                }


                if (!_includedFrom.TryGetValue(path, out List<(string Path, int Line)>? sites))
                {
                    _includedFrom[path] = sites = [];
                }

                (string Path, int Line) site = (FullPath(from.Path), from.Line);
                if (!sites.Contains(site)) { sites.Add(site); }
            }

            // The .using lines the assembler took, so a branch of an .if it skipped does not count.
            if (!location.IsMacroExpansion)
            {
                if (!_usingLines.TryGetValue(path, out HashSet<int>? usingLines))
                {
                    _usingLines[path] = usingLines = [];
                }

                // Only a .using the assembler accepts: native, without a label, and naming scopes.
                if (statement.Kind == AssemblyStatementKind.Using && AssemblyNameResolver.ReadUsingNames(statement, out _) is not null)
                {
                    usingLines.Add(location.Line);
                    _usingOrder.TryAdd((UpperPath(path), location.Line), index);
                }
            }
            else if (statement.Kind == AssemblyStatementKind.Using && AssemblyNameResolver.ReadUsingNames(statement, out _) is { } names)
            {
                RecordInvokedUsing(location, names, index);
            }

            if (!result.Success && statement.Kind is AssemblyStatementKind.Procedure or AssemblyStatementKind.Scope)
            {
                string name = statement.Operand.Text.Trim();
                if (statement.Kind == AssemblyStatementKind.Procedure
                    && !location.IsMacroExpansion
                    && _lines.TryGetValue(path, out string[]? lines)
                    && location.Line < lines.Length
                    && ProcedureDefinition().Match(lines[location.Line]) is { Success: true } match)
                {
                    Group procedure = match.Groups["name"];
                    name = procedure.Value;
                    string qualified = string.Join("::", scopes.Where(scope => scope.Length != 0).Append(name));
                    if (!_definitions.ContainsKey(qualified))
                    {
                        Add(new(qualified, path, location.Line, procedure.Index, SymbolSiteKind.Label, Value: null, SourceLength: procedure.Length));
                    }
                }

                // A continued piece goes on with the scope of that name.
                scopes.Add(AssemblySyntax.ContinuedScope(name) ?? name);
            }
            else if (!result.Success
                && statement.Kind is AssemblyStatementKind.EndProcedure or AssemblyStatementKind.EndScope
                && scopes.Count != 0)
            {
                scopes.RemoveAt(scopes.Count - 1);
            }
        }

        IncludeSitesFromText();

        // The assembler knows native names; show the spelling the source used.
        Dictionary<string, string> spelling = [with(StringComparer.Ordinal)];
        foreach (KeyValuePair<string, string> alias in result.SymbolAliases) { spelling[alias.Value] = alias.Key; }
        // The lines the assembler defined a name on, by the upper-cased path, so each line costs only its number.
        Dictionary<string, HashSet<int>> assembled = [with(StringComparer.Ordinal)];
        foreach (AssemblySymbol symbol in result.SymbolDefinitions)
        {
            if (symbol.Location is not { } location || location.Path.Length == 0) { continue; }
            string path = FullPath(location.Path);
            int scopeEnd = symbol.Name.LastIndexOf("::", StringComparison.Ordinal);
            int qualifier = scopeEnd < 0 ? 0 : scopeEnd + 2;
            string suffix = symbol.Name[qualifier..];
            bool translated = qualifier == 0
                || (_dialects.TryGetValue(path, out AssemblyDialect dialect) && dialect is AssemblyDialect.Macro10 or AssemblyDialect.Merlin);

            string name = translated && spelling.TryGetValue(suffix, out string? source) ? symbol.Name[..qualifier] + source : symbol.Name;
            SymbolSiteKind kind = symbol.IsConstant ? SymbolSiteKind.Constant : SymbolSiteKind.Label;
            int column = location.Column;
            int? sourceLength = null;
            int scope = name.LastIndexOf("::", StringComparison.Ordinal);
            ReadOnlySpan<char> unqualified = name.AsSpan(scope < 0 ? 0 : scope + 2);
            if (_lines.TryGetValue(path, out string[]? lines)
                && location.Line >= 0
                && location.Line < lines.Length
                && ProcedureDefinition().Match(lines[location.Line]) is { Success: true } procedure
                && unqualified.Equals(procedure.Groups["name"].Value, StringComparison.OrdinalIgnoreCase))
            {
                column = procedure.Groups["name"].Index;
                sourceLength = procedure.Groups["name"].Length;
            }

            Add(new(name, path, location.Line, column, kind, symbol.Value, sourceLength));
            string upper = UpperPath(path);
            if (!assembled.TryGetValue(upper, out HashSet<int>? assembledLines))
            {
                assembled[upper] = assembledLines = [];
            }

            assembledLines.Add(location.Line);
        }

        // Macros and .defines are expanded before assembly, so find their definitions in the text; so are the
        // definitions of a source that does not assemble yet, which the assembler reports none of.
        foreach ((string path, string[] lines) in _lines)
        {
            HashSet<int>? assembledHere = assembled.GetValueOrDefault(UpperPath(path));
            for (int line = 0; line < lines.Length; line++)
            {
                Match match = MacroDefinition().Match(lines[line]);
                if (match.Success)
                {
                    Group name = match.Groups["native"];
                    if (!name.Success) { name = match.Groups["merlin"]; }
                    if (!name.Success) { name = match.Groups["macro10"]; }
                    Add(new(name.Value, path, line, name.Index, SymbolSiteKind.Macro, Value: null));
                    continue;
                }

                // A line the assembler defined a name on has it already, qualified by its scope: most lines that
                // define one, so they are passed over before matching.
                if (assembledHere?.Contains(line) == true) { continue; }
                match = TextDefinition().Match(lines[line]);
                bool bare = match.Success && !match.Groups["colon"].Success && !match.Groups["equate"].Success;
                bool instruction = bare && InstructionDocs.IsMnemonic(match.Groups["name"].Value);
                if (!match.Success || instruction) { continue; }

                // One it did not assemble (a branch of conditional assembly not taken, or a source with errors) is
                // qualified by the scopes around it as the assembler would qualify it, so a name in a scope is not
                // taken for a root name: once for each scope the file is included in.
                bool constant = match.Groups["equate"].Success;
                SymbolSiteKind kind = constant ? SymbolSiteKind.Constant : SymbolSiteKind.Label;
                string plain = match.Groups["name"].Value;

                // A name written qualified keeps its spelling (the assembler rejects defining one), and a cheap local
                // belongs to the label before it, not to a scope.
                bool scoped = !plain.Contains("::", StringComparison.Ordinal) && !plain.StartsWith('@');
                IEnumerable<string> enclosing = scoped ? ScopesAt(path, line).Select(context => context.Scope) : [""];
                foreach (string scope in enclosing.Distinct(StringComparer.Ordinal))
                {
                    string name = scope.Length == 0 ? plain : $"{scope}::{plain}";
                    if (_definitions.ContainsKey(name)) { continue; }
                    long? value = result.Symbols.TryGetValue(name, out long known) ? known : null;
                    SymbolSite site = new(name, path, line, Column: 0, kind, value);
                    _textOnly.Add(site);
                    Add(site);
                }
            }
        }
    }

    /// <summary>
    ///  Gets the root file.
    /// </summary>
    internal string Root { get; }

    /// <summary>
    ///  Gets the assembly.
    /// </summary>
    internal AssemblyResult Result { get; }

    /// <summary>
    ///  Gets the root and every file it included.
    /// </summary>
    internal HashSet<string> Members { get; }

    /// <summary>
    ///  Gets the documentation comments of the root and every file it included, with values from the assembly.
    /// </summary>
    internal DocumentationSet Documentation =>
        LazyInitializer.EnsureInitialized(ref _documentation, ref _documentationLock, CreateDocumentation);

    private DocumentationSet CreateDocumentation() => DocumentationSet.Create(
        _lines.Keys
            .OrderBy(path => string.Equals(path, Root, StringComparison.OrdinalIgnoreCase) ? 0 : 1)
            .Select(path => DocumentationParser.Parse(SourceText.Rejoined(_lines[path]), path, AssembledUsing(path), style: true)),
        Symbols(),
        ModuleOf(Root),
        ModelOf(Root),
        Result.SourceMap,

        // Branches are chosen while sources expand, so even an assembly with errors says which it took where an error
        // can't have changed that; the conditions decide where it can.
        Result.SkippedLines,

        // An assembly with errors may stop short of definitions it would make, so its macros' expansions aren't known.
        Result.Success ? Result.SymbolDefinitions : null,
        _cpuDirectives);

    // The assembly's symbols, or while it has errors, the definitions found in the text.
    private IReadOnlyDictionary<string, long> Symbols()
    {
        if (Result.Success) { return Result.Symbols; }
        Dictionary<string, long> symbols = new(Result.Symbols, StringComparer.Ordinal);
        foreach (SymbolSite site in Definitions)
        {
            if (site.Kind != SymbolSiteKind.Macro) { symbols.TryAdd(site.Name, site.Value ?? -1); }
        }

        return symbols;
    }

    /// <summary>
    ///  Gets every definition.
    /// </summary>
    internal IEnumerable<SymbolSite> Definitions => _definitions.Values.SelectMany(sites => sites);

    /// <summary>
    ///  Gets whether a definition has exactly this name, matching case.
    /// </summary>
    /// <param name="name">The name, qualified as the definition's is.</param>
    /// <returns>Whether one of <see cref="Definitions"/> has that name.</returns>
    internal bool Defines(string name) =>
        _definitions.TryGetValue(name, out List<SymbolSite>? sites) && sites.Exists(site => site.Name == name);

    /// <summary>
    ///  Assembles a root file over its declared ROM image or the whole address space.
    /// </summary>
    /// <param name="root">The full path of the root.</param>
    /// <param name="openText">Open documents' text by path, or null for files on disk.</param>
    /// <param name="files">
    ///  The files read from disk, shared with other analyses made at the same time, such as the SDK index's; null for a
    ///  cache of this analysis's own.
    /// </param>
    /// <returns>The analysis.</returns>
    internal static SourceAnalysis Assemble(string root, Func<string, string?> openText, SourceFileCache? files = null)
    {
        files ??= new();
        if (root.EndsWith(ProjectSources.Extension, StringComparison.OrdinalIgnoreCase))
        {
            return AssembleTarget(root, openText, files);
        }

        string text = openText(root) ?? files.Read(root);
        string configuration = Path.ChangeExtension(root, ".cfg");
        string? configurationText = openText(configuration) ?? (File.Exists(configuration) ? File.ReadAllText(configuration) : null);
        WorkspaceSourceResolver resolver = new(openText, files);
        (string assemblyText, RomMetadata? rom, AssemblyDiagnostic? romError) = RomSource(text, root);
        AssemblySource? linkerConfiguration = configurationText is not null
            ? new(configurationText, configuration)
            : null;

        AssemblyOptions options = Options(linkerConfiguration);
        AssemblySource source = new(assemblyText, root);
        AssemblyParseResult parsed = Assembler.Assembler.Parse(source, options);
        if (romError is not null)
        {
            parsed = new(parsed.Project, [romError, .. parsed.Diagnostics]);
        }

        if (rom is { } metadata
            && linkerConfiguration is null
            && parsed.Project.Statements.Any(statement => statement.Dialect == AssemblyDialect.Ca65))
        {
            options = Options(AssemblyLinker.ImageConfiguration(metadata.Origin, metadata.ImageSize));
        }

        Assembler.Assembler assembler = new();
        AssemblyResult result = parsed.Success
            ? assembler.Assemble(parsed.Project, options)
            : Assembler.Assembler.Failed(parsed);

        return new(
            root,
            result,
            parsed.Project,
            resolver.Resolved,
            TextOf(openText),
            path => openText(path) is { } open ? SourceText.Lines(open) : files.ReadLinesIfExists(path));

        AssemblyOptions Options(AssemblySource? linker) => new(ProcessorVariant.Mos6502, rom?.Origin ?? 0, rom?.ImageSize ?? AddressSpaceSize)
        {
            SourceResolver = resolver,
            SdkPaths = [SdkModules.SdkDirectory],
            BuildTime = DateTimeOffset.UnixEpoch,
            LinkerConfiguration = linker
        };
    }

    // A project's target, assembled as retrocore build assembles it: its platform folders' and sources' files as one
    // stream, with its headers and defines. A target its project no longer has, or whose sources are missing, is an
    // analysis with that error on the project file, its one member.
    private static SourceAnalysis AssembleTarget(string root, Func<string, string?> openText, SourceFileCache files)
    {
        WorkspaceSourceResolver resolver = new(openText, files);
        List<TargetSourceFile> sourceFiles;
        AssemblyOptions options;
        ProjectTarget? target = ProjectSources.Target(root);
        try
        {
            if (target is null) { throw new ProjectException($"{root}: the project no longer has this target."); }
            sourceFiles = target.SourceFiles();
            string? linker = target.LinkerConfiguration;
            options = ProjectBuild.Options(
                target,
                resolver,
                linker is null ? null : new(openText(linker) ?? files.Read(linker), linker));
        }
        catch (Exception exception) when (exception is ProjectException or IOException or UnauthorizedAccessException)
        {
            string file = target?.Project.File ?? ProjectSources.FileOf(root) ?? root;
            AssemblyDiagnostic error = new(exception.Message, new AssemblyLocation(file, line: 0));
            AssemblyProject empty = new(0);
            return new(root, Assembler.Assembler.Failed(new(empty, [error])), empty, [file], TextOf(openText), _ => []);
        }

        List<AssemblySource> sources =
            [.. sourceFiles.Select(file => new AssemblySource(openText(file.Path) ?? files.Read(file.Path), file.Path, file.Dialect))];

        AssemblyParseResult parsed = Assembler.Assembler.Parse(sources, options);
        AssemblyResult result = parsed.Success
            ? new Assembler.Assembler().Assemble(parsed.Project, options)
            : Assembler.Assembler.Failed(parsed);

        return new(
            root,
            result,
            parsed.Project,
            [.. sourceFiles.Select(file => file.Path), .. resolver.Resolved],
            TextOf(openText),
            path => openText(path) is { } open ? SourceText.Lines(open) : files.ReadLinesIfExists(path));
    }

    // The analysis keeps this function, so it is made apart from Assemble's lambdas: those share one closure, and
    // the analysis would keep the build's whole file cache through it.
    private static Func<string, string?> TextOf(Func<string, string?> openText) =>
        path => openText(path) ?? (File.Exists(path) ? File.ReadAllText(path) : null);

    /// <summary>
    ///  Gets a member file's lines.
    /// </summary>
    /// <param name="path">The full path.</param>
    /// <returns>The lines, or none for a file this analysis did not read.</returns>
    internal string[] LinesOf(string path) => _lines.TryGetValue(path, out string[]? lines) ? lines : [];

    /// <summary>
    ///  Gets an included line's CPU across all its inclusion contexts.
    /// </summary>
    /// <param name="path">The full path.</param>
    /// <param name="line">The zero-based line.</param>
    /// <param name="ambiguous">Whether the contexts use different CPUs.</param>
    /// <returns>The CPU, or null when it cannot be determined.</returns>
    internal InstructionSet? InstructionSetAt(string path, int line, out bool ambiguous) =>
        InstructionSetAt(path, line, depth: 0, out ambiguous);

    private InstructionSet? InstructionSetAt(string path, int line, int depth, out bool ambiguous)
    {
        ambiguous = false;
        if (string.Equals(path, Root, StringComparison.OrdinalIgnoreCase) && _rootCpus.Count != 0)
        {
            return CpuAt(_rootCpus, line);
        }

        if (!_includeCpus.TryGetValue(path, out var contexts))
        {
            if (_includedFrom.TryGetValue(path, out List<(string Path, int Line)>? sites))
            {
                if (depth >= 32)
                {
                    ambiguous = true;
                    return null;
                }

                InstructionSet? inherited = null;
                foreach ((string parent, int at) in sites)
                {
                    InstructionSet? cpu = InstructionSetAt(parent, at, depth + 1, out bool uncertain);
                    if (uncertain || cpu is null || (inherited is not null && inherited != cpu))
                    {
                        ambiguous = true;
                        return null;
                    }

                    inherited = cpu;
                }

                return inherited;
            }

            return Documentation.InstructionSetAt(path, line);
        }

        InstructionSet? result = null;
        foreach (List<(int Line, InstructionSet Cpu)> runs in contexts.Values)
        {
            InstructionSet cpu = CpuAt(runs, line);
            if (result is not null && result != cpu)
            {
                ambiguous = true;
                return null;
            }

            result = cpu;
        }

        return result;
    }

    private static InstructionSet CpuAt(List<(int Line, InstructionSet Cpu)> runs, int line)
    {
        InstructionSet cpu = runs[0].Cpu;
        foreach ((int at, InstructionSet set) in runs)
        {
            if (at <= line) { cpu = set; }
        }

        return cpu;
    }

    /// <summary>
    ///  Finds where a name is defined, trying the spellings the reference's dialect allows.
    /// </summary>
    /// <param name="name">The name as written.</param>
    /// <param name="macro10">Whether the reference uses MACRO-10, or null for the root's dialect.</param>
    /// <returns>The definitions, nearest first when there are several.</returns>
    internal IReadOnlyList<SymbolSite> Find(string name, bool? macro10 = null)
    {
        if (_definitions.TryGetValue(name, out List<SymbolSite>? sites)) { return sites; }

        // MACRO-10 compares six characters; a local or scoped name may be stored with its scope.
        const int Significant = 6;
        if ((macro10 ?? UsesMacro10(Root))
            && name.Length > Significant
            && _definitions.TryGetValue(name[..Significant], out sites))
        {
            return sites;
        }

        List<SymbolSite> scoped = [.. Definitions.Where(site => site.Name.EndsWith($"::{name}", StringComparison.OrdinalIgnoreCase))];
        if (scoped.Count != 0) { return scoped; }

        // A historical name finds the definition whose Also: section gives it.
        return [.. Documentation.FindAlso(name, thisBuild: true)
            .Where(topic => topic.Name != name)
            .SelectMany(topic => Documentation.SymbolsOf(topic, name, thisBuild: true).SelectMany(symbol => Find(symbol)))
            .Distinct()];
    }

    /// <summary>
    ///  Gets whether a source is assembled as MACRO-10.
    /// </summary>
    /// <param name="path">The source's path.</param>
    /// <returns>Whether the assembler parsed it as MACRO-10.</returns>
    internal bool UsesMacro10(string path)
    {
        if (_dialects.TryGetValue(path, out AssemblyDialect dialect)) { return dialect == AssemblyDialect.Macro10; }
        string[] lines = _lines.TryGetValue(path, out string[]? known) ? known : SourceText.Lines(_text(path) ?? "");
        bool? declared = SourceText.Macro10Dialect(path, lines);
        if (declared is not null) { return declared.Value; }
        return !path.Equals(Root, StringComparison.OrdinalIgnoreCase) && UsesMacro10(Root);
    }

    /// <summary>
    ///  Finds where a name used on a line is defined, looking a plain name up as the assembler does there: in the
    ///  scopes that contain the line, innermost first, then in the scopes the <c>.using</c> directives in effect
    ///  name, then as <see cref="Find(string, bool?)"/> does.
    /// </summary>
    /// <param name="name">The name as written.</param>
    /// <param name="path">The full path of the file it is used in.</param>
    /// <param name="line">The zero-based line it is used on.</param>
    /// <param name="macro10">Whether the reference uses MACRO-10, or null for the root's dialect.</param>
    /// <returns>The definitions; several when two used scopes define the name.</returns>
    internal IReadOnlyList<SymbolSite> Find(string name, string path, int line, bool? macro10 = null) =>
        Bound(name, path, line) ?? Find(name, macro10);

    /// <summary>
    ///  Finds the definition a plain name used on a line binds to by the assembler's scope rules alone: the scopes
    ///  that contain the line, innermost first, the root, then the scopes the <c>.using</c> directives in effect name.
    /// </summary>
    /// <param name="name">The plain name.</param>
    /// <param name="path">The full path of the file it is used in.</param>
    /// <param name="line">The zero-based line it is used on.</param>
    /// <returns>
    ///  The definitions, or null when the name binds to none of them, as a historical name does not, or is a cheap
    ///  local or unnamed label, which scopes do not name.
    /// </returns>
    internal IReadOnlyList<SymbolSite>? Bound(string name, string path, int line)
    {
        // A cheap local belongs to the label before it, and an unnamed label to its position, not to a scope.
        if (name.StartsWith('@') || name.StartsWith(':')) { return null; }

        if (name.Contains("::", StringComparison.Ordinal))
        {
            return _definitions.GetValueOrDefault(name.TrimStart(':'));
        }

        // A file included in several places binds a name in each; all of them are what the line may mean.
        // The native dialect's names match case, as the assembler matches them; MACRO-10's do not.
        bool exact = !UsesMacro10(path);
        IReadOnlyList<DocumentationScopes> contexts = ScopesAt(path, line);
        if (contexts.Count == 1) { return Bound(name, path, contexts[0], exact); }
        List<SymbolSite> all = [.. contexts.SelectMany(scopes => Bound(name, path, scopes, exact) ?? []).Distinct()];
        return all.Count == 0 ? null : all;
    }

    /// <summary>
    ///  Gets the definitions a plain name binds to at a line only through the <c>.using</c> directives in effect
    ///  there: null when the code's own scopes or the root define it, or no directive's scope does.
    /// </summary>
    /// <param name="name">The plain name, as written.</param>
    /// <param name="path">The file of the use.</param>
    /// <param name="line">Its zero-based line.</param>
    /// <returns>The definitions a <c>.using</c> brings the name to, or null.</returns>
    internal IReadOnlyList<SymbolSite>? BoundThroughUsing(string name, string path, int line)
    {
        // A cheap local, an unnamed label or a qualified name is not looked up through a .using.
        bool plain = !name.StartsWith('@') && !name.StartsWith(':') && !name.Contains("::", StringComparison.Ordinal);
        if (!plain) { return null; }
        bool exact = !UsesMacro10(path);
        List<SymbolSite> all = [];
        foreach (DocumentationScopes scopes in ScopesAt(path, line))
        {
            if (Own(name, scopes, exact) is not null) { return null; }
            all.AddRange(Used(name, path, scopes, exact) ?? []);
        }

        return all.Count == 0 ? null : [.. all.Distinct()];
    }

    /// <summary>
    ///  Finds a name in one specific inclusion's scopes and using directives.
    /// </summary>
    /// <param name="name">The name as the assembler stores it.</param>
    /// <param name="path">The file of the use.</param>
    /// <param name="scopes">The inclusion's scopes.</param>
    /// <param name="exact">Whether names match case.</param>
    /// <returns>The definitions, or null.</returns>
    internal List<SymbolSite>? Bound(string name, string path, DocumentationScopes scopes, bool exact) =>
        Own(name, scopes, exact) ?? (name.Contains("::", StringComparison.Ordinal) ? null : Used(name, path, scopes, exact));

    // What a plain name binds to in the code's own scopes, innermost first, or at the root.
    private List<SymbolSite>? Own(string name, DocumentationScopes scopes, bool exact)
    {
        for (string scope = scopes.Scope; scope.Length != 0; scope = Parent(scope))
        {
            if (Defined($"{scope}::{name}", exact) is { } sites) { return sites; }
        }

        return Defined(name, exact);
    }

    // What a plain name binds to through the .using directives in effect, the innermost directive first.
    private List<SymbolSite>? Used(string name, string path, DocumentationScopes scopes, bool exact)
    {
        foreach (DocumentationUsing directive in scopes.Usings)
        {
            List<SymbolSite> used =
            [
                .. directive.Targets(IsScope, OpenedBefore(path, directive))
                    .Distinct(StringComparer.Ordinal)
                    .SelectMany(scope => Defined($"{scope}::{name}", exact) ?? [])
            ];

            if (used.Count != 0) { return used; }
        }

        return null;
    }

    // The definitions of a qualified name, matching case when exact. After a successful assembly, only those it
    // made: a name the text alone defines, as in a skipped .if branch, is not one the assembler bound.
    private List<SymbolSite>? Defined(string name, bool exact)
    {
        if (!_definitions.TryGetValue(name, out List<SymbolSite>? sites)) { return null; }
        bool success = Result.Success;
        List<SymbolSite> matching =
        [
            .. sites.Where(site => (!exact || string.Equals(site.Name, name, StringComparison.Ordinal))
                && !(success && _textOnly.Contains(site)))
        ];

        return matching.Count == 0 ? null : matching;
    }

    /// <summary>
    ///  Gets the names the <c>.using</c> directives in effect on a line make usable unqualified there.
    /// </summary>
    /// <param name="path">The full path.</param>
    /// <param name="line">The zero-based line.</param>
    /// <returns>Each name code there can write that binds to its definition, innermost directive first.</returns>
    internal IEnumerable<(string Name, SymbolSite Site)> UsedNames(string path, int line)
    {
        foreach (DocumentationUsing directive in ScopesAt(path, line).SelectMany(scopes => scopes.Usings).Distinct())
        {
            foreach (string scope in directive.Targets(IsScope, OpenedBefore(path, directive)).Distinct(StringComparer.Ordinal))
            {
                string prefix = $"{scope}::";
                foreach (SymbolSite site in Definitions)
                {
                    if (site.Name.Length <= prefix.Length
                        || !site.Name.StartsWith(prefix, StringComparison.OrdinalIgnoreCase)
                        || site.Name.IndexOf("::", prefix.Length, StringComparison.Ordinal) >= 0)
                    {
                        continue;
                    }

                    // Only where the plain name binds to this definition: not one an enclosing scope's own name
                    // shadows, nor one two used scopes define, which code must qualify.
                    string name = site.Name[prefix.Length..];
                    if (Bound(name, path, line) is { Count: > 0 } bound
                        && bound.All(found => string.Equals(found.Name, site.Name, StringComparison.OrdinalIgnoreCase)))
                    {
                        yield return (name, site);
                    }
                }
            }
        }
    }

    /// <summary>
    ///  Gets the scopes and using directives in effect at a source line.
    /// </summary>
    /// <param name="path">The full path.</param>
    /// <param name="line">The zero-based line.</param>
    /// <returns>The contexts, one for each place the file is included.</returns>
    internal IReadOnlyList<DocumentationScopes> ScopesAt(string path, int line) => ScopesAt(path, line, depth: 0);

    private IReadOnlyList<DocumentationScopes> ScopesAt(string path, int line, int depth)
    {
        if (!_scopes.TryGetValue(path, out IReadOnlyList<IReadOnlyList<DocumentationScopes>>? contexts))
        {
            IReadOnlyList<DocumentationScopes> lines = DocumentationParser.ScopesByLine(LinesOf(path), AssembledUsing(path));

            // Includes are textual: a file included inside a .scope or .proc is in that scope, though the
            // including file's .using directives do not reach it. A file included in several scopes is in each.
            const int MaximumIncludeDepth = 32;
            List<string> outers = depth < MaximumIncludeDepth && _includedFrom.TryGetValue(path, out List<(string Path, int Line)>? sites)
                ? [.. sites.SelectMany(site => ScopesAt(site.Path, site.Line, depth + 1)).Select(scopes => scopes.Scope).Distinct(StringComparer.OrdinalIgnoreCase)]
                : [""];

            contexts = [.. outers.Select(outer => outer.Length == 0
                ? lines
                : (IReadOnlyList<DocumentationScopes>)[.. lines.Select(scopes => Within(outer, scopes))])];

            contexts = _scopes.GetOrAdd(path, contexts);
        }

        return [.. contexts.Select(lines => (uint)line < (uint)lines.Count ? lines[line] : DocumentationScopes.Root)];
    }

    // The assembly shows where a file is included only through the statements the file contributes, so one whose
    // whole content the build skips (an .if branch not taken) has no include site, and its names would seem to be at
    // the root. Such a file takes its sites from the .include lines in the text of the analysis's other files.
    private void IncludeSitesFromText()
    {
        Dictionary<string, List<(string Path, int Line)>> found = [with(StringComparer.OrdinalIgnoreCase)];
        foreach ((string path, string[] lines) in _lines)
        {
            foreach ((int line, string file) in SourceIncludes.IncludeLines(path, lines))
            {
                bool member = _lines.ContainsKey(file) && !string.Equals(file, path, StringComparison.OrdinalIgnoreCase);
                if (!member || _includedFrom.ContainsKey(file)) { continue; }
                if (!found.TryGetValue(file, out List<(string Path, int Line)>? sites)) { found[file] = sites = []; }
                if (!sites.Contains((path, line))) { sites.Add((path, line)); }
            }
        }

        foreach ((string file, List<(string Path, int Line)> sites) in found) { _includedFrom[file] = sites; }
    }

    // What the assembler took from a file: its .using lines, and those its macro invocations produced; null when
    // the assembly reached none of the file.
    private DocumentationAssembled? AssembledUsing(string path)
    {
        // A successful assembly says exactly which it took, for a file it never reached too.
        if (Result.Success) { return DocumentationAssembled.From(Result, path); }
        if (!_usingLines.TryGetValue(path, out HashSet<int>? lines)) { return null; }
        Dictionary<int, List<string[]>>? invoked = _invokedUsings.GetValueOrDefault(path);
        return new(lines.Contains, line => invoked is not null && invoked.TryGetValue(line, out List<string[]>? names) ? names : []);
    }

    // Records a .using a macro expansion produced, at the line of the outermost invocation, where it applies from.
    private void RecordInvokedUsing(AssemblyLocation location, string[] names, int index)
    {
        AssemblyLocation invocation = location;
        while (invocation.IsMacroExpansion && invocation.ExpandedFrom is { } from) { invocation = from; }
        if (invocation.IsMacroExpansion || invocation.Path.Length == 0) { return; }
        string path = FullPath(invocation.Path);
        if (!_invokedUsings.TryGetValue(path, out Dictionary<int, List<string[]>>? lines))
        {
            _invokedUsings[path] = lines = [];
        }

        if (!lines.TryGetValue(invocation.Line, out List<string[]>? list)) { lines[invocation.Line] = list = []; }
        list.Add(names);
        _usingOrder.TryAdd((UpperPath(path), invocation.Line), index);
    }

    // Records where each scope is first opened in the assembled statements, so a .using operand binds, as the
    // assembler binds it, to a scope opened before the directive when there is one.
    private void RecordScopeOrder(AssemblyStatement statement, int index, List<string?> opened)
    {
        if (statement.Kind is AssemblyStatementKind.Procedure or AssemblyStatementKind.Scope)
        {
            string name = statement.Operand.Text.Trim();
            name = AssemblySyntax.ContinuedScope(name) ?? name;
            if (name.Length == 0)
            {
                opened.Add(item: null);
                return;
            }

            string qualified = string.Join("::", opened.OfType<string>().Append(name));
            _scopeOpened.TryAdd(qualified, index);
            opened.Add(name);
        }
        else if (statement.Kind is AssemblyStatementKind.EndProcedure or AssemblyStatementKind.EndScope && opened.Count != 0)
        {
            opened.RemoveAt(opened.Count - 1);
        }
    }

    // Whether a scope is first opened before the .using on a line of a file, or null when that is not known.
    private Func<string, bool>? OpenedBefore(string path, DocumentationUsing directive) =>
        _usingOrder.TryGetValue((path.ToUpperInvariant(), directive.Line), out int at)
            ? scope => _scopeOpened.TryGetValue(scope, out int open) && open < at
            : null;

    // A statement's, symbol's or include's path made full. The assembly names a few files many times over, so each
    // path is made full once; only the constructor calls this, so the cache needs no lock.
    private string FullPath(string path)
    {
        if (!_fullPaths.TryGetValue(path, out string? full)) { _fullPaths[path] = full = Path.GetFullPath(path); }
        return full;
    }

    // A full path upper-cased, as the keys that compare paths without case hold it, once per path; only the
    // constructor calls this, so the cache needs no lock.
    private string UpperPath(string path)
    {
        if (!_upperPaths.TryGetValue(path, out string? upper)) { _upperPaths[path] = upper = path.ToUpperInvariant(); }
        return upper;
    }

    private static string Qualify(string scope, string name) => name.Length == 0 ? scope : $"{scope}::{name}";

    // A line's scopes in a file included inside the scope outer.
    private static DocumentationScopes Within(string outer, DocumentationScopes scopes)
    {
        List<DocumentationUsing> usings = [];
        foreach (DocumentationUsing directive in scopes.Usings)
        {
            usings.Add(new(Qualify(outer, directive.Scope), directive.Names, directive.Line));
        }

        return new(Qualify(outer, scopes.Scope), usings);
    }

    // Whether a qualified name is a scope that some definition is in.
    private bool IsScope(string name)
    {
        HashSet<string>? names = Volatile.Read(ref _scopeNames);
        if (names is null)
        {
            // Built whole before it is published, so a parallel request never sees part of it.
            names = [with(StringComparer.OrdinalIgnoreCase)];
            foreach (string definition in _definitions.Keys)
            {
                for (string scope = Parent(definition); scope.Length != 0 && names.Add(scope); scope = Parent(scope))
                {
                }
            }

            names = Interlocked.CompareExchange(ref _scopeNames, names, comparand: null) ?? names;
        }

        return names.Contains(name);
    }

    private static string Parent(string name)
    {
        int separator = name.LastIndexOf("::", StringComparison.Ordinal);
        return separator < 0 ? "" : name[..separator];
    }

    /// <summary>
    ///  Gets the source map entries a line produced, including through macros it invoked.
    /// </summary>
    /// <param name="path">The full path.</param>
    /// <param name="line">The zero-based line.</param>
    /// <returns>The entries that emit bytes.</returns>
    internal IEnumerable<AssemblySourceMapEntry> Emitted(string path, int line)
    {
        foreach (AssemblySourceMapEntry entry in Result.SourceMap)
        {
            if (entry.Size == 0) { continue; }
            for (AssemblyLocation? location = entry.Location; location is not null; location = location.ExpandedFrom)
            {
                if (location.Line == line && string.Equals(Path.GetFullPath(location.Path), path, StringComparison.OrdinalIgnoreCase))
                {
                    yield return entry;
                    break;
                }
            }
        }
    }

    /// <summary>
    ///  Tests whether a line's bytes came from expanding a macro it calls, as p-code's do from <c>Pcode.asm</c>'s, rather
    ///  than from an instruction of its own.
    /// </summary>
    /// <param name="path">The full path.</param>
    /// <param name="line">The zero-based line.</param>
    /// <returns>Whether the line called a macro that emitted bytes.</returns>
    internal bool ExpandsMacro(string path, int line)
    {
        foreach (AssemblySourceMapEntry entry in Emitted(path, line))
        {
            for (AssemblyLocation? location = entry.Location; location?.ExpandedFrom is { } from; location = from)
            {
                if (location.IsMacroExpansion && from.Line == line && string.Equals(Path.GetFullPath(from.Path), path, StringComparison.OrdinalIgnoreCase))
                {
                    return true;
                }
            }
        }

        return false;
    }

    /// <summary>
    ///  Gets the SDK modules this analysis's links reach: all but the one it stands in for.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   An SDK source opened from the repository is the same module as the SDK's own copy, so the SDK's module of
    ///   the same name and model is left out; otherwise every name in it would be defined twice. Modules that
    ///   only share include files with it (the IIe's equates are in every IIe source) are kept, so a shared
    ///   file's links to them still resolve.
    ///  </para>
    /// </remarks>
    /// <param name="sdk">The SDK's modules.</param>
    /// <returns>The modules to resolve links against.</returns>
    internal IEnumerable<SourceAnalysis> OtherModules(IEnumerable<SourceAnalysis> sdk)
    {
        string module = ModuleOf(Root);
        string? model = ModelOf(Root);
        return sdk.Where(other => !Replaces(other.Root));

        bool Replaces(string other)
        {
            if (string.Equals(other, Root, StringComparison.OrdinalIgnoreCase)) { return true; }
            bool sameModule = string.Equals(ModuleOf(other), module, StringComparison.OrdinalIgnoreCase);
            return sameModule && string.Equals(ModelOf(other), model, StringComparison.OrdinalIgnoreCase);
        }
    }

    /// <summary>
    ///  Gets the module name documentation links use for a root file: the first part of its name, such as
    ///  <c>Monitor</c>, <c>Firmware</c> or <c>Slot7</c>, and <c>AppleSoft</c> for the overlay.
    /// </summary>
    /// <param name="path">The root's path.</param>
    /// <returns>The module name.</returns>
    internal static string ModuleOf(string path)
    {
        string name = Path.GetFileName(path);
        int dot = name.IndexOf('.');
        string module = dot < 0 ? name : name[..dot];
        return module.Equals("applesoft", StringComparison.OrdinalIgnoreCase) ? "AppleSoft" : module;
    }

    /// <summary>
    ///  Gets the IIe model a root file is written for, from a name such as <c>Firmware.Enhanced.asm</c>.
    /// </summary>
    /// <param name="path">The root's path.</param>
    /// <returns><c>Enhanced</c>, <c>Original</c>, or null.</returns>
    internal static string? ModelOf(string path)
    {
        string[] parts = Path.GetFileName(path).Split('.');
        if (parts.Any(part => part.Equals("Enhanced", StringComparison.OrdinalIgnoreCase))) { return "Enhanced"; }
        return parts.Any(part => part.Equals("Original", StringComparison.OrdinalIgnoreCase)) ? "Original" : null;
    }

    private void Add(SymbolSite site)
    {
        if (!_definitions.TryGetValue(site.Name, out List<SymbolSite>? sites)) { _definitions[site.Name] = sites = []; }
        sites.Add(site);
    }

    // The generator's .rom line supplies image bounds but is not an assembler instruction.
    private static (string Text, RomMetadata? Metadata, AssemblyDiagnostic? Error) RomSource(string text, string path)
    {
        if (!text.Contains(".rom", StringComparison.OrdinalIgnoreCase)) { return (text, null, null); }
        if (!path.EndsWith(".rom.asm", StringComparison.OrdinalIgnoreCase))
        {
            return (RomDeclaration().Replace(text, ""), null, null);
        }

        char[]? source = null;
        RomMetadata? metadata = null;
        AssemblyDiagnostic? error = null;
        int offset = 0;
        int line = 0;
        foreach (ReadOnlyMemory<char> sourceLine in new AssemblyLines(text.AsMemory()))
        {
            int start = offset;
            offset += sourceLine.Length;
            if (offset < text.Length && text[offset] == '\r') { offset++; }
            if (offset < text.Length && text[offset] == '\n') { offset++; }
            int currentLine = line++;
            ReadOnlyMemory<char> content = sourceLine[..AssemblySyntax.WithoutComment(sourceLine.Span).Length].Trim();
            if (!RomMetadata.IsDeclaration(content.Span)) { continue; }

            source ??= text.ToCharArray();
            source.AsSpan(start, sourceLine.Length).Fill(' ');
            if (error is not null) { continue; }
            try
            {
                if (metadata is not null)
                {
                    throw new AssemblyError(currentLine, "Expected one '.rom Namespace.Type, origin, size' declaration.");
                }

                metadata = RomMetadata.Read(content, currentLine);
            }
            catch (AssemblyError failure)
            {
                error = new(failure.Message, new(path, failure.Line));
            }
        }

        return (source is null ? text : new string(source), metadata, error);
    }

    [GeneratedRegex(@"^[ \t]*\.rom[ \t][^\r\n]*", RegexOptions.Multiline | RegexOptions.IgnoreCase)]
    private static partial Regex RomDeclaration();

    // A name in column 0: a label (with or without a colon) or an equate, whatever the source's dialect. Directives
    // start with a dot and match in any case, as the assembler reads them. So does Merlin's EQU, as the Merlin
    // preprocessor reads it, but only as a whole field, as Merlin splits fields at blanks (not Name EQU*1 or EQU;c). A
    // colon followed by .equ or .set (Name: .equ expr) defines a constant or variable, not a label. Each part of the
    // name is atomic, so a name that ends in equ, such as Subsequ, is never cut short to make an equate of its start,
    // while Macro-10's NAME::1,,2 can still give back ::1 to be the label NAME and its statement.
    [GeneratedRegex(@"^(?<name>(?>[A-Za-z_@][\w@$%?]*)(?:::(?>[\w@$%?]+))*)(?:(?<equate>:[ \t]*(?i:\.(?:equ|set))(?=[\s;]|$)|\s*(?::=|==?|(?i:\.equ|\.set)\b|(?i:equ)(?=\s|$)))|(?<colon>::?)|\s|$)")]
    private static partial Regex TextDefinition();

    [GeneratedRegex(@"^[ \t]*(?:[A-Za-z_@][\w@]*::?[ \t]*)?\.proc[ \t]+(?<name>[A-Za-z_]\w*)(?=[ \t]*(?::[ \t]*[A-Za-z_]\w*)?[ \t]*(?:;|$))", RegexOptions.IgnoreCase)]
    private static partial Regex ProcedureDefinition();

    [GeneratedRegex(
        @"^(?:\s*\.(?:macro|define)\s+(?<native>[A-Za-z_@.][\w@.]*)|(?<merlin>[A-Za-z_]\w*)\s+MAC\b|\s*DEFINE\s+(?<macro10>[A-Za-z$%.][\w$%.]*))",
        RegexOptions.IgnoreCase)]
    private static partial Regex MacroDefinition();
}
