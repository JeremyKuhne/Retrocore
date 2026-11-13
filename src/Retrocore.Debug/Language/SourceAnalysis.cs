// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.RegularExpressions;
using Retrocore.Assembler;
using Retrocore.Documentation;

namespace Retrocore.Debug.Language;

/// <summary>
///  One assembly of a root file and everything it includes, indexed for the language features.
/// </summary>
internal sealed partial class SourceAnalysis
{
    private const int AddressSpaceSize = 0x10000;

    private readonly Dictionary<string, List<SymbolSite>> _definitions = new(StringComparer.OrdinalIgnoreCase);
    private readonly Dictionary<string, string[]> _lines = new(StringComparer.OrdinalIgnoreCase);
    private DocumentationSet? _documentation;

    private SourceAnalysis(string root, AssemblyResult result, IEnumerable<string> members, Func<string, string?> text)
    {
        Root = root;
        Result = result;
        Members = new(members, StringComparer.OrdinalIgnoreCase) { root };
        foreach (string member in Members)
        {
            if (text(member) is { } content) { _lines[member] = SourceText.Lines(content); }
        }

        // The assembler knows native names; show the spelling the source used.
        Dictionary<string, string> spelling = new(StringComparer.Ordinal);
        foreach (KeyValuePair<string, string> alias in result.SymbolAliases) { spelling[alias.Value] = alias.Key; }
        foreach (AssemblySymbol symbol in result.SymbolDefinitions)
        {
            if (symbol.Location is not { } location || location.Path.Length == 0) { continue; }
            string name = spelling.TryGetValue(symbol.Name, out string? source) ? source : symbol.Name;
            SymbolSiteKind kind = symbol.IsConstant ? SymbolSiteKind.Constant : SymbolSiteKind.Label;
            Add(new(name, Path.GetFullPath(location.Path), location.Line, location.Column, kind, symbol.Value));
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
        WorkspaceSourceResolver resolver = new(openText);
        AssemblyOptions options = new(ProcessorVariant.Mos6502, 0, AddressSpaceSize)
        {
            SourceResolver = resolver,
            SdkPaths = [SdkModules.SdkDirectory],
            BuildTime = DateTimeOffset.UnixEpoch
        };

        AssemblyResult result = new Assembler.Assembler().Assemble(new AssemblySource(WithoutRomDeclaration(text), root), options);
        return new(root, result, resolver.Resolved, path => openText(path) ?? (File.Exists(path) ? File.ReadAllText(path) : null));
    }

    /// <summary>
    ///  Gets a member file's lines.
    /// </summary>
    /// <param name="path">The full path.</param>
    /// <returns>The lines, or none for a file this analysis did not read.</returns>
    internal string[] LinesOf(string path) => _lines.TryGetValue(path, out string[]? lines) ? lines : [];

    /// <summary>
    ///  Finds where a name is defined, trying the spellings the dialects allow.
    /// </summary>
    /// <param name="name">The name as written.</param>
    /// <returns>The definitions, nearest first when there are several.</returns>
    internal IReadOnlyList<SymbolSite> Find(string name)
    {
        if (_definitions.TryGetValue(name, out List<SymbolSite>? sites)) { return sites; }

        // MACRO-10 compares six characters; a local or scoped name may be stored with its scope.
        const int Significant = 6;
        if (name.Length > Significant && _definitions.TryGetValue(name[..Significant], out sites)) { return sites; }
        return [.. Definitions.Where(site => site.Name.EndsWith($"::{name}", StringComparison.OrdinalIgnoreCase))];
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

    [GeneratedRegex(
        @"^(?:\s*\.(?:macro|define)\s+(?<native>[A-Za-z_@.][\w@.]*)|(?<merlin>[A-Za-z_]\w*)\s+MAC\b|\s*DEFINE\s+(?<macro10>[A-Za-z$%.][\w$%.]*))",
        RegexOptions.IgnoreCase)]
    private static partial Regex MacroDefinition();
}
