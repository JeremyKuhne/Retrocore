// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Documentation;
using System.Text.RegularExpressions;

namespace Retrocore.Debug.Language;

/// <summary>
///  One assembly of a root file and everything it includes, indexed for the language features.
/// </summary>
internal sealed partial class SourceAnalysis
{
    private const int AddressSpaceSize = 0x10000;

    private readonly Dictionary<string, List<SymbolSite>> _definitions = [with(StringComparer.OrdinalIgnoreCase)];
    private readonly Dictionary<string, AssemblyDialect> _dialects = [with(StringComparer.OrdinalIgnoreCase)];
    private readonly Dictionary<string, string[]> _lines = [with(StringComparer.OrdinalIgnoreCase)];
    private readonly Func<string, string?> _text;
    private readonly Dictionary<string, IReadOnlyList<IReadOnlyList<DocumentationScopes>>> _scopes = [with(StringComparer.OrdinalIgnoreCase)];
    private HashSet<string>? _scopeNames;
    private readonly Dictionary<string, List<(string Path, int Line)>> _includedFrom = [with(StringComparer.OrdinalIgnoreCase)];
    private readonly Dictionary<string, HashSet<int>> _usingLines = [with(StringComparer.OrdinalIgnoreCase)];
    private readonly Dictionary<string, Dictionary<int, List<string[]>>> _invokedUsings = [with(StringComparer.OrdinalIgnoreCase)];
    // Keyed by the upper-cased path, as the other path-keyed maps here compare paths without case.
    private readonly Dictionary<(string Path, int Line), int> _usingOrder = [];
    private readonly Dictionary<string, int> _scopeOpened = [with(StringComparer.OrdinalIgnoreCase)];
    private DocumentationSet? _documentation;

    private SourceAnalysis(
        string root,
        AssemblyResult result,
        AssemblyProject project,
        IEnumerable<string> members,
        Func<string, string?> text)
    {
        Root = root;
        Result = result;
        _text = text;
        Members = new(members, StringComparer.OrdinalIgnoreCase) { root };
        foreach (string member in Members)
        {
            if (text(member) is { } content) { _lines[member] = SourceText.Lines(content); }
        }

        List<string> scopes = [];
        List<string?> opened = [];
        for (int index = 0; index < project.Statements.Count; index++)
        {
            AssemblyStatement statement = project.Statements[index];
            RecordScopeOrder(statement, index, opened);
            if (statement.Location is not { Path.Length: > 0 } location) { continue; }
            string path = Path.GetFullPath(location.Path);
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

                (string Path, int Line) site = (Path.GetFullPath(from.Path), from.Line);
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
                    _usingOrder.TryAdd((path.ToUpperInvariant(), location.Line), index);
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

        // The assembler knows native names; show the spelling the source used.
        Dictionary<string, string> spelling = [with(StringComparer.Ordinal)];
        foreach (KeyValuePair<string, string> alias in result.SymbolAliases) { spelling[alias.Value] = alias.Key; }
        HashSet<(string Path, int Line)> assembled = [];
        foreach (AssemblySymbol symbol in result.SymbolDefinitions)
        {
            if (symbol.Location is not { } location || location.Path.Length == 0) { continue; }
            string name = spelling.TryGetValue(symbol.Name, out string? source) ? source : symbol.Name;
            SymbolSiteKind kind = symbol.IsConstant ? SymbolSiteKind.Constant : SymbolSiteKind.Label;
            string path = Path.GetFullPath(location.Path);
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
            assembled.Add((path.ToUpperInvariant(), location.Line));
        }

        // Macros and .defines are expanded before assembly, so find their definitions in the text; so are the
        // definitions of a source that does not assemble yet, which the assembler reports none of.
        foreach ((string path, string[] lines) in _lines)
        {
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

                match = TextDefinition().Match(lines[line]);
                bool bare = match.Success && !match.Groups["colon"].Success && !match.Groups["equate"].Success;
                bool instruction = bare && InstructionDocs.IsMnemonic(match.Groups["name"].Value);
                // A line the assembler defined a name on has it already, qualified by its scope.
                if (match.Success
                    && !instruction
                    && !_definitions.ContainsKey(match.Groups["name"].Value)
                    && !assembled.Contains((path.ToUpperInvariant(), line)))
                {
                    bool constant = match.Groups["equate"].Success;
                    SymbolSiteKind kind = constant ? SymbolSiteKind.Constant : SymbolSiteKind.Label;
                    string name = match.Groups["name"].Value;
                    long? value = result.Symbols.TryGetValue(name, out long known) ? known : null;
                    Add(new(name, path, line, Column: 0, kind, value));
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
    internal DocumentationSet Documentation => _documentation ??= DocumentationSet.Create(
        _lines.Keys
            .OrderBy(path => string.Equals(path, Root, StringComparison.OrdinalIgnoreCase) ? 0 : 1)
            .Select(path => DocumentationParser.Parse(string.Join("\n", _lines[path]), path, AssembledUsing(path))),
        Symbols(),
        ModuleOf(Root),
        ModelOf(Root),
        Result.SourceMap);

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
    ///  Assembles a root file over the whole address space.
    /// </summary>
    /// <param name="root">The full path of the root.</param>
    /// <param name="openText">Open documents' text by path, or null for files on disk.</param>
    /// <returns>The analysis.</returns>
    internal static SourceAnalysis Assemble(string root, Func<string, string?> openText)
    {
        string text = openText(root) ?? File.ReadAllText(root);
        string configuration = Path.ChangeExtension(root, ".cfg");
        string? configurationText = openText(configuration) ?? (File.Exists(configuration) ? File.ReadAllText(configuration) : null);
        WorkspaceSourceResolver resolver = new(openText);
        AssemblyOptions options = new(ProcessorVariant.Mos6502, 0, AddressSpaceSize)
        {
            SourceResolver = resolver,
            SdkPaths = [SdkModules.SdkDirectory],
            BuildTime = DateTimeOffset.UnixEpoch,
            LinkerConfiguration = configurationText is null ? null : new(configurationText, configuration)
        };

        AssemblySource source = new(WithoutRomDeclaration(text), root);
        AssemblyParseResult parsed = Assembler.Assembler.Parse(source, options);
        Assembler.Assembler assembler = new();
        AssemblyResult result = parsed.Success
            ? assembler.Assemble(parsed.Project, options)
            : new([.. parsed.Diagnostics]);

        return new(root, result, parsed.Project, resolver.Resolved, path => openText(path) ?? (File.Exists(path) ? File.ReadAllText(path) : null));
    }

    /// <summary>
    ///  Gets a member file's lines.
    /// </summary>
    /// <param name="path">The full path.</param>
    /// <returns>The lines, or none for a file this analysis did not read.</returns>
    internal string[] LinesOf(string path) => _lines.TryGetValue(path, out string[]? lines) ? lines : [];

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
        return [.. Documentation.FindAlso(name)
            .Where(topic => topic.Name != name)
            .SelectMany(topic => Find(topic.Name))
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
    /// <returns>The definitions, or null when the name binds to none of them, as a historical name does not.</returns>
    internal IReadOnlyList<SymbolSite>? Bound(string name, string path, int line)
    {
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

    private List<SymbolSite>? Bound(string name, string path, DocumentationScopes scopes, bool exact)
    {
        for (string scope = scopes.Scope; scope.Length != 0; scope = Parent(scope))
        {
            if (Defined($"{scope}::{name}", exact) is { } sites) { return sites; }
        }

        if (Defined(name, exact) is { } root) { return root; }
        foreach (DocumentationUsing directive in scopes.Usings)
        {
            List<SymbolSite> used =
            [
                .. directive.Targets(IsScope, OpenedBefore(path, directive))
                    .Distinct(StringComparer.OrdinalIgnoreCase)
                    .SelectMany(scope => Defined($"{scope}::{name}", exact) ?? [])
            ];

            if (used.Count != 0) { return used; }
        }

        return null;
    }

    // The definitions of a qualified name, matching case when exact.
    private List<SymbolSite>? Defined(string name, bool exact)
    {
        if (!_definitions.TryGetValue(name, out List<SymbolSite>? sites)) { return null; }
        if (!exact) { return sites; }
        List<SymbolSite> matching = [.. sites.Where(site => string.Equals(site.Name, name, StringComparison.Ordinal))];
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
            foreach (string scope in directive.Targets(IsScope, OpenedBefore(path, directive)).Distinct(StringComparer.OrdinalIgnoreCase))
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

    // The scope a line is in and the .using directives in effect on it: one for each distinct scope the file is
    // included in.
    private IReadOnlyList<DocumentationScopes> ScopesAt(string path, int line) => ScopesAt(path, line, depth: 0);

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

            _scopes[path] = contexts;
        }

        return [.. contexts.Select(lines => (uint)line < (uint)lines.Count ? lines[line] : DocumentationScopes.Root)];
    }

    // What the assembler took from a file: its .using lines, and those its macro invocations produced; null when
    // the assembly reached none of the file.
    private DocumentationAssembled? AssembledUsing(string path)
    {
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
        string path = Path.GetFullPath(invocation.Path);
        if (!_invokedUsings.TryGetValue(path, out Dictionary<int, List<string[]>>? lines))
        {
            _invokedUsings[path] = lines = [];
        }

        if (!lines.TryGetValue(invocation.Line, out List<string[]>? list)) { lines[invocation.Line] = list = []; }
        list.Add(names);
        _usingOrder.TryAdd((path.ToUpperInvariant(), invocation.Line), index);
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
        if (_scopeNames is null)
        {
            _scopeNames = [with(StringComparer.OrdinalIgnoreCase)];
            foreach (string definition in _definitions.Keys)
            {
                for (string scope = Parent(definition); scope.Length != 0 && _scopeNames.Add(scope); scope = Parent(scope))
                {
                }
            }
        }

        return _scopeNames.Contains(name);
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

    // The generator's .rom declaration is metadata for the C# source generator, not an instruction.
    private static string WithoutRomDeclaration(string text) => RomDeclaration().Replace(text, "");

    [GeneratedRegex(@"^[ \t]*\.rom[ \t][^\r\n]*", RegexOptions.Multiline | RegexOptions.IgnoreCase)]
    private static partial Regex RomDeclaration();

    // A name in column 0: a label (with or without a colon) or an equate. Directives start with a dot.
    [GeneratedRegex(@"^(?<name>[A-Za-z_@][\w@$%?]*(?:::[\w@$%?]+)*)(?:(?<colon>::?)|(?<equate>\s*(?:==?|\.equ\b|\.set\b|EQU\b))|\s|$)")]
    private static partial Regex TextDefinition();

    [GeneratedRegex(@"^[ \t]*(?:[A-Za-z_@][\w@]*::?[ \t]*)?\.proc[ \t]+(?<name>[A-Za-z_]\w*)(?=[ \t]*(?::[ \t]*[A-Za-z_]\w*)?[ \t]*(?:;|$))", RegexOptions.IgnoreCase)]
    private static partial Regex ProcedureDefinition();

    [GeneratedRegex(
        @"^(?:\s*\.(?:macro|define)\s+(?<native>[A-Za-z_@.][\w@.]*)|(?<merlin>[A-Za-z_]\w*)\s+MAC\b|\s*DEFINE\s+(?<macro10>[A-Za-z$%.][\w$%.]*))",
        RegexOptions.IgnoreCase)]
    private static partial Regex MacroDefinition();
}
