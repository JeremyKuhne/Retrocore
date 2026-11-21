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
        foreach (AssemblyStatement statement in project.Statements)
        {
            if (statement.Location is not { Path.Length: > 0 } location) { continue; }
            string path = Path.GetFullPath(location.Path);
            if (_lines.ContainsKey(path))
            {
                _dialects.TryAdd(path, statement.Dialect);
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
                if (match.Success && !instruction && !_definitions.ContainsKey(match.Groups["name"].Value))
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
            .Select(path => DocumentationParser.Parse(string.Join("\n", _lines[path]), path)),
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
