// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.RegularExpressions;

namespace Retrocore.Debug.Language;

/// <summary>
///  Finds where a label, constant or macro is used: each place its name appears in code, or in a documentation
///  comment's <c>&lt;NAME&gt;</c> link, that resolves to the same definition.
/// </summary>
/// <remarks>
///  <para>
///   The assembler does not record where names are used, so the source text is searched. Each occurrence is
///   resolved the way going to its definition is, so a local label, or another assembly's name that is spelled
///   the same, is not counted. Strings and ordinary comments are skipped.
///  </para>
/// </remarks>
internal static partial class SymbolReferences
{
    /// <summary>
    ///  Finds the references to a name's definitions.
    /// </summary>
    /// <param name="word">The name as written where the search started, which may be scoped (<c>a::b</c>).</param>
    /// <param name="targets">Its definitions.</param>
    /// <param name="analyses">The assemblies to search: the open roots and the SDK's ROM sources.</param>
    /// <param name="sdk">The SDK's ROM sources, which resolve names an assembly does not define.</param>
    /// <param name="includeDeclaration">Whether to include the definitions themselves.</param>
    /// <returns>Each reference: the name as written there, its file, line and column, in file and line order.</returns>
    internal static List<SymbolSite> Find(
        string word,
        IReadOnlyList<SymbolSite> targets,
        IEnumerable<SourceAnalysis> analyses,
        IReadOnlyList<SourceAnalysis> sdk,
        bool includeDeclaration)
    {
        int scope = word.LastIndexOf("::", StringComparison.Ordinal);
        string needle = scope < 0 ? word : word[(scope + 2)..];
        if (needle.Length == 0 || targets.Count == 0) { return []; }
        Dictionary<(string Path, int Line, int Column), SymbolSite> found = [];
        foreach (SourceAnalysis analysis in analyses)
        {
            foreach (string path in analysis.Members)
            {
                string[] lines = analysis.LinesOf(path);
                for (int line = 0; line < lines.Length; line++)
                {
                    if (lines[line].IndexOf(needle, StringComparison.OrdinalIgnoreCase) < 0) { continue; }
                    foreach ((string token, int column) in Occurrences(lines[line], needle))
                    {
                        if (!Resolves(analysis, sdk, lines, (path, line), token, targets)) { continue; }
                        if (!includeDeclaration && Declares(targets, path, line, column)) { continue; }
                        SymbolSite site = new(token, path, line, column, targets[0].Kind, targets[0].Value);
                        found.TryAdd((path.ToUpperInvariant(), line, column), site);
                    }
                }
            }
        }

        return
        [
            .. found.Values
                .OrderBy(site => site.Path, StringComparer.OrdinalIgnoreCase)
                .ThenBy(site => site.Line)
                .ThenBy(site => site.Column)
        ];
    }

    // Whether an occurrence is one of the definitions.
    private static bool Declares(IReadOnlyList<SymbolSite> targets, string path, int line, int column) =>
        targets.Any(target => Same(target.Path, path) && target.Line == line && target.Column == column);

    // The names in a line that end in the needle: in its code, outside strings, and in a ;; comment's links.
    private static IEnumerable<(string Token, int Column)> Occurrences(string line, string needle)
    {
        int comment = SourceText.CommentStart(line);
        int end = comment < 0 ? line.Length : comment;
        char quote = '\0';
        for (int index = 0; index < end; index++)
        {
            char character = line[index];
            if (quote != '\0')
            {
                if (character == quote) { quote = '\0'; }
                continue;
            }

            if (IsQuote(line, index))
            {
                quote = character;
                continue;
            }

            if (!StartsName(line, index) || SourceText.WordAt(line, index) is not { } word) { continue; }
            if (word.Start == index && EndsWith(word.Word, needle)) { yield return word; }
        }

        // A documentation comment links names as <NAME>.
        if (comment >= 0 && comment + 1 < line.Length && line[comment + 1] == ';')
        {
            foreach (Match link in DocumentationLink().Matches(line, comment))
            {
                Group name = link.Groups["name"];
                if (EndsWith(name.Value, needle)) { yield return (name.Value, name.Index); }
            }
        }
    }

    // A quote starts a string, except the apostrophe of the Z80's alternate register, AF'.
    private static bool IsQuote(string line, int index)
    {
        char character = line[index];
        if (character == '"') { return true; }
        if (character != '\'') { return false; }
        return index < 2 || !line[(index - 2)..index].Equals("AF", StringComparison.OrdinalIgnoreCase);
    }

    // Whether a name can start here: the line's start, or after a character that is not part of a name.
    private static bool StartsName(string line, int index) =>
        index == 0 || !(SourceText.IsNameCharacter(line[index - 1]) || line[index - 1] == ':');

    private static bool EndsWith(string token, string needle) =>
        token.Equals(needle, StringComparison.OrdinalIgnoreCase)
            || token.EndsWith($"::{needle}", StringComparison.OrdinalIgnoreCase);

    // Resolves a name where it is used, as going to its definition does, and tests whether that is a target.
    private static bool Resolves(
        SourceAnalysis analysis,
        IReadOnlyList<SourceAnalysis> sdk,
        string[] lines,
        (string Path, int Line) where,
        string token,
        IReadOnlyList<SymbolSite> targets)
    {
        IReadOnlyList<SymbolSite> sites = analysis.Find(token);
        if (sites.Count == 0 && SourceText.LocalDefinition(lines, token, where.Line) is { } local)
        {
            sites = [local with { Path = where.Path }];
        }

        if (sites.Count == 0) { sites = [.. sdk.SelectMany(source => source.Find(token)).Take(1)]; }
        return sites.Any(site => targets.Any(target => Same(site.Path, target.Path) && site.Line == target.Line));
    }

    private static bool Same(string left, string right) => string.Equals(left, right, StringComparison.OrdinalIgnoreCase);

    [GeneratedRegex(@"<(?<name>[A-Za-z_@.][A-Za-z0-9_@.$:]*)>")]
    private static partial Regex DocumentationLink();
}
