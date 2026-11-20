// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Documentation;

namespace Retrocore.Assembler;

/// <summary>
///  The historical names that <c>;; Also:</c> sections give definitions, by the definition's source line, so
///  code written with an old name (<c>jsr COUT</c>) assembles against the definition's current one.
/// </summary>
internal sealed class AssemblyAlsoNames
{
    private readonly Dictionary<(string Path, int Line), string[]> _names;

    private AssemblyAlsoNames(Dictionary<(string Path, int Line), string[]> names) => _names = names;

    /// <summary>
    ///  Reads the <c>Also:</c> sections of the sources that have any.
    /// </summary>
    /// <param name="sources">The project's sources, includes among them.</param>
    /// <returns>The names, or null when no source has an <c>Also:</c> section.</returns>
    internal static AssemblyAlsoNames? Collect(IEnumerable<AssemblySource> sources)
    {
        Dictionary<(string Path, int Line), string[]>? names = null;
        HashSet<string> seen = [with(StringComparer.Ordinal)];
        foreach (AssemblySource source in sources)
        {
            // Only a source that has the heading needs its documentation parsed.
            if (!seen.Add(source.Path)
                || source.Text.IndexOf("Also:", StringComparison.OrdinalIgnoreCase) < 0)
            {
                continue;
            }

            foreach (DocumentationComment comment in DocumentationParser.Parse(source.Text, source.Path).Comments)
            {
                if (comment.Keyword is not null) { continue; }
                string[] also = [.. DocumentationAlso.Of(comment.Sections).Select(item => item.Name)];
                if (also.Length == 0) { continue; }
                names ??= [];
                names[(source.Path, comment.TargetLine)] = also;
            }
        }

        return names is null ? null : new(names);
    }

    /// <summary>
    ///  Gives a just-declared definition its historical names.
    /// </summary>
    /// <param name="node">The statement that declares it.</param>
    /// <param name="id">Its symbol ID.</param>
    /// <param name="symbols">The symbol table.</param>
    internal void Apply(AssemblyStatement node, int id, AssemblySymbols symbols)
    {
        if (node.Location is not { IsMacroExpansion: false } location) { return; }
        if (!_names.TryGetValue((location.Path, location.Line), out string[]? names)) { return; }
        foreach (string name in names) { symbols.AddAlias(name, id); }
    }
}
