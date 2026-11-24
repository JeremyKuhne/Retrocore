// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Documentation;

namespace Retrocore.Assembler;

/// <summary>
///  The historical names that <c>;; Also:</c> sections give definitions, by the definition's source line, so
///  code written with an old name (<c>jsr COUT</c>) assembles against the definition's current one.
/// </summary>
/// <remarks>
///  <para>
///   A definition in a macro's body is defined again by each expansion. Its old names reach it only when the build
///   expands it exactly once: the names of a line that two expansions define reach neither, and the lint reports
///   them where the assembly succeeds. A name that differs in each expansion, a parameter's, a <c>.local</c> one
///   or a cheap local, and a <c>.set</c> variable in a macro's body are never given old names.
///  </para>
/// </remarks>
internal sealed class AssemblyAlsoNames
{
    private readonly Dictionary<(string Path, int Line), (string[] Names, bool Macro)> _names;

    // The definitions each macro body line with old names declared, in the order expansions declared them.
    private Dictionary<(string Path, int Line), List<int>>? _expanded;

    private AssemblyAlsoNames(Dictionary<(string Path, int Line), (string[] Names, bool Macro)> names) => _names = names;

    /// <summary>
    ///  Reads the <c>Also:</c> sections of the sources that have any.
    /// </summary>
    /// <param name="sources">The project's sources, includes among them.</param>
    /// <returns>The names, or null when no source has an <c>Also:</c> section.</returns>
    internal static AssemblyAlsoNames? Collect(IEnumerable<AssemblySource> sources)
    {
        Dictionary<(string Path, int Line), (string[] Names, bool Macro)>? names = null;
        HashSet<string> seen = [with(StringComparer.Ordinal)];
        foreach (AssemblySource source in sources)
        {
            // Only a source with the heading on a ;; line needs its documentation parsed, and without the style
            // checks, which the assembly does not need.
            if (!seen.Add(source.Path) || !HasHeading(source.Text)) { continue; }
            foreach (DocumentationComment comment in DocumentationParser.Parse(source.Lines, source.Path, assembled: null, style: false).Comments)
            {
                // A scope has no address of its own: its line is lowered to a hidden start label, which an old name
                // must not reach. A named type is a scope too.
                bool scope = comment.Kind is DocumentationKind.Scope or DocumentationKind.Struct or DocumentationKind.Enum;

                // A name that differs in each expansion of a macro has nothing one old name could reach, nor has a
                // .set variable there, whose versions the documentation can't count as the assembler does.
                bool variable = comment.Macro is not null && comment.Kind == DocumentationKind.Variable;
                bool varies = comment.NamedByParameter || comment.LocalToExpansion || variable;
                if (comment.Keyword is not null || scope || varies) { continue; }
                string[] also = [.. DocumentationAlso.Of(comment.Sections).Select(item => item.Name)];
                if (also.Length == 0) { continue; }
                names ??= [];
                names[(source.Path, comment.TargetLine)] = (also, comment.Macro is not null);
            }
        }

        return names is null ? null : new(names);
    }

    /// <summary>
    ///  Gets the historical names a definition's <c>Also:</c> section gives it.
    /// </summary>
    /// <param name="location">Where the definition is declared: its line, or its line in a macro's body.</param>
    /// <returns>The names, or none.</returns>
    internal IReadOnlyList<string> Of(AssemblyLocation location)
    {
        bool known = _names.TryGetValue((location.Path, location.Line), out (string[] Names, bool Macro) found);
        return known && found.Macro == location.IsMacroExpansion ? found.Names : [];
    }

    // Whether a source has a line that starts ;; Also: in any case.
    private static bool HasHeading(string text)
    {
        int at = 0;
        while ((at = text.IndexOf("Also:", at, StringComparison.OrdinalIgnoreCase)) >= 0)
        {
            int start = text.LastIndexOf('\n', Math.Max(at - 1, 0)) + 1;
            ReadOnlySpan<char> before = text.AsSpan(start, at - start).Trim();
            if (before.Length >= 2 && before.StartsWith(";;".AsSpan()) && before[2..].Trim().IsEmpty) { return true; }
            at += 5;
        }

        return false;
    }

    /// <summary>
    ///  Gives a just-declared definition its historical names.
    /// </summary>
    /// <param name="node">The statement that declares it.</param>
    /// <param name="id">Its symbol ID.</param>
    /// <param name="symbols">The symbol table.</param>
    internal void Apply(AssemblyStatement node, int id, AssemblySymbols symbols)
    {
        if (node.Location is not { } location) { return; }

        // A member that names a nested type ("INNER .struct Inner") shares its line with the type's .scope, whose
        // hidden start label the member's old names must not reach.
        if (node.Kind == AssemblyStatementKind.Scope || node.OpensScope) { return; }
        if (Of(location) is not { Count: > 0 } names) { return; }
        if (!location.IsMacroExpansion)
        {
            foreach (string name in names) { symbols.AddAlias(name, id); }
            return;
        }

        // Whether the build expands the line once is known only at the end.
        _expanded ??= [];
        if (!_expanded.TryGetValue((location.Path, location.Line), out List<int>? ids))
        {
            _expanded[(location.Path, location.Line)] = ids = [];
        }

        ids.Add(id);
    }

    /// <summary>
    ///  Gives the definitions in macro bodies their historical names, once every statement is declared: only a line
    ///  the build expanded exactly once has them.
    /// </summary>
    /// <param name="symbols">The symbol table.</param>
    internal void ApplyExpanded(AssemblySymbols symbols)
    {
        if (_expanded is null) { return; }
        foreach (KeyValuePair<(string Path, int Line), List<int>> expanded in _expanded)
        {
            if (expanded.Value.Count != 1) { continue; }
            foreach (string name in _names[expanded.Key].Names) { symbols.AddAlias(name, expanded.Value[0]); }
        }
    }
}
