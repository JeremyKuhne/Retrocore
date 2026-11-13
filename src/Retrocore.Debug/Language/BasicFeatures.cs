// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.RegularExpressions;
using Retrocore.Basic;

namespace Retrocore.Debug.Language;

/// <summary>
///  The language features of BASIC documents: hover, definitions, references, completion and the outline.
/// </summary>
internal static partial class BasicFeatures
{
    /// <summary>
    ///  Describes what is under the cursor: a reserved word's help, a line, or a variable as BASIC names it.
    /// </summary>
    /// <param name="document">The document.</param>
    /// <param name="position">The cursor.</param>
    /// <returns>The hover, or null.</returns>
    internal static Hover? Hover(BasicDocument document, Position position)
    {
        BasicSource source = document.Source;
        if (source.Dialect is not { } dialect || source.SiteAt(position.Line, position.Character) is not { } site)
        {
            return null;
        }

        string? text = site.Kind switch
        {
            BasicSiteKind.Keyword => BasicKeywordHelp.Markdown(dialect, KeywordOf(dialect, site)),
            BasicSiteKind.LineNumber => LineUses(source, site),
            BasicSiteKind.Label => $"Label for line {site.Number}. {LineUses(source, site)}",
            BasicSiteKind.LineReference => source.LineNumbered(site.Number) is { } target
                ? $"```\n{source.Lines[target.Line].Trim()}\n```"
                : $"There is no line {site.Number}.",
            _ => Name(source, site)
        };

        return text is null ? null : new Hover
        {
            Contents = new MarkupContent { Kind = MarkupKind.Markdown, Value = text },
            Range = Range(site)
        };
    }

    // The reserved word a keyword site is, as the dialect spells it.
    private static string KeywordOf(BasicDialect dialect, BasicSite site) =>
        site.Word.Length > 0 ? site.Word : dialect.Keyword(site.Token) ?? site.Text;

    /// <summary>
    ///  Finds where a line reference or a function is defined: its line, or its DEF FN.
    /// </summary>
    /// <param name="document">The document.</param>
    /// <param name="position">The cursor.</param>
    /// <returns>The definitions.</returns>
    internal static IEnumerable<LspLocation> Definition(BasicDocument document, Position position)
    {
        BasicSource source = document.Source;
        if (source.SiteAt(position.Line, position.Character) is not { } site) { return []; }
        if (site.Kind == BasicSiteKind.LineReference && !char.IsAsciiDigit(site.Text[0]))
        {
            // A label names the line: go to the label.
            return source.Sites.Where(other => other.Kind == BasicSiteKind.Label && other.Number == site.Number)
                .Select(other => Location(document, other));
        }

        if (site.Kind is BasicSiteKind.LineReference or BasicSiteKind.LineNumber or BasicSiteKind.Label)
        {
            return source.LineNumbered(site.Number) is { } line
                ? [Location(document, line.Line, line.Start, line.End)]
                : [];
        }

        return site.Kind == BasicSiteKind.Function
            ? source.Sites.Where(other => other.Kind == BasicSiteKind.Function && other.Key == site.Key && Defines(source, other))
                .Select(other => Location(document, other))
            : [];
    }

    /// <summary>
    ///  Finds every use of a line, variable or function.
    /// </summary>
    /// <param name="document">The document.</param>
    /// <param name="position">The cursor.</param>
    /// <param name="includeDeclaration">Whether to include a line's own number.</param>
    /// <returns>The uses.</returns>
    internal static IEnumerable<LspLocation> References(BasicDocument document, Position position, bool includeDeclaration) =>
        document.Source.SiteAt(position.Line, position.Character) is { } site
            ? document.Source.References(site, includeDeclaration).Select(other => Location(document, other))
            : [];

    /// <summary>
    ///  Completes reserved words and the program's variables, or its line numbers after GOTO and the like.
    /// </summary>
    /// <param name="document">The document.</param>
    /// <param name="position">The cursor.</param>
    /// <returns>The items.</returns>
    internal static List<CompletionItem> Complete(BasicDocument document, Position position)
    {
        BasicSource source = document.Source;
        if (source.Dialect is not { } dialect || position.Line >= source.Lines.Count) { return []; }
        string line = source.Lines[position.Line];
        string before = line[..Math.Min(position.Character, line.Length)];
        if (before.Count(character => character == '"') % 2 == 1 || RemarkBefore().IsMatch(before)) { return []; }
        if (JumpBefore().IsMatch(before))
        {
            List<CompletionItem> targets =
            [
                .. source.Sites.Where(site => site.Kind == BasicSiteKind.Label).Select(site => new CompletionItem
                {
                    Label = site.Text.TrimEnd(':'),
                    Kind = CompletionItemKind.Reference,
                    Detail = $"line {site.Number}",
                    SortText = $"0{site.Text}"
                })
            ];

            targets.AddRange(source.NumberedLines.Select(numbered => new CompletionItem
            {
                Label = numbered.Number.ToString(System.Globalization.CultureInfo.InvariantCulture),
                Kind = CompletionItemKind.Reference,
                Detail = source.Lines[numbered.Line].Trim(),
                SortText = numbered.Number.ToString("D5", System.Globalization.CultureInfo.InvariantCulture)
            }));

            return targets;
        }

        List<CompletionItem> items =
        [
            .. dialect.Keywords.Where(keyword => keyword.Length > 0 && char.IsAsciiLetter(keyword[0])).Select(keyword => new CompletionItem
            {
                Label = keyword,
                Kind = CompletionItemKind.Keyword,
                Documentation = BasicKeywordHelp.Markdown(dialect, keyword) is { } help
                    ? new MarkupContent { Kind = MarkupKind.Markdown, Value = help }
                    : null
            })
        ];

        items.AddRange(source.Sites
            .Where(site => site.Kind == BasicSiteKind.Variable)
            .Select(site => site.Name)
            .Distinct(StringComparer.Ordinal)
            .Select(name => new CompletionItem { Label = name, Kind = CompletionItemKind.Variable }));

        return items;
    }

    /// <summary>
    ///  Outlines the program: each section a remark starts, and the subroutines GOSUB calls inside it.
    /// </summary>
    /// <param name="document">The document.</param>
    /// <returns>The outline.</returns>
    internal static List<DocumentSymbol> Symbols(BasicDocument document)
    {
        BasicSource source = document.Source;
        if (source.Dialect is not { } dialect) { return []; }
        HashSet<int> called = [.. source.Sites.Where(site => site.Via == "GOSUB").Select(site => site.Number)];
        Dictionary<int, BasicSite> labels = [];
        foreach (BasicSite label in source.Sites.Where(site => site.Kind == BasicSiteKind.Label))
        {
            labels.TryAdd(label.Number, label);
        }

        List<(int Start, BasicSourceLine Line, string Name)> sections = [];
        List<(BasicSourceLine Line, string Name)> subroutines = [];
        foreach (BasicSourceLine line in source.NumberedLines)
        {
            string? remark = Remark(source, dialect, line);
            if (labels.TryGetValue(line.Number, out BasicSite label))
            {
                // A label starts a section, at its own line.
                sections.Add((label.Line, line, label.Text.TrimEnd(':')));
            }
            else if (remark is not null)
            {
                sections.Add((line.Line, line, remark.Length == 0 ? $"Line {line.Number}" : remark));
            }
            else if (called.Contains(line.Number))
            {
                subroutines.Add((line, $"GOSUB {line.Number}"));
            }
        }

        int last = source.Lines.Count - 1;
        List<DocumentSymbol> calls = [];
        foreach ((BasicSourceLine line, string name) in subroutines)
        {
            calls.Add(Symbol(source, line, name, SymbolKind.Function, line.Line, Called(line)));
        }

        if (sections.Count == 0) { return calls; }
        List<DocumentSymbol> outline = [];
        for (int index = 0; index < sections.Count; index++)
        {
            int end = index + 1 < sections.Count ? sections[index + 1].Start - 1 : last;
            (int start, BasicSourceLine line, string name) = sections[index];
            DocumentSymbol[] children = [.. calls.Where(call => call.Range.Start.Line > line.Line && call.Range.Start.Line <= end)];

            // A section GOSUB calls is a subroutine.
            SymbolKind kind = called.Contains(line.Number) ? SymbolKind.Function : SymbolKind.Namespace;
            outline.Add(Symbol(source, line, name, kind, end, Called(line), children, start));
        }

        // Subroutines before the first section stand alone.
        outline.InsertRange(0, calls.Where(call => call.Range.Start.Line < sections[0].Start));
        return outline;

        string Called(BasicSourceLine line) => called.Contains(line.Number)
            ? $"GOSUB {line.Number}"
            : line.Number.ToString(System.Globalization.CultureInfo.InvariantCulture);
    }

    // The text of a remark that starts a line, or null when the line does not start with one.
    private static string? Remark(BasicSource source, BasicDialect dialect, BasicSourceLine line)
    {
        BasicSite? first = source.Sites
            .Where(site => site.Line == line.Line && site.Kind != BasicSiteKind.LineNumber)
            .Cast<BasicSite?>()
            .FirstOrDefault();

        if (first is null) { return null; }
        BasicSite keyword = first.Value;
        bool remark = keyword.Kind == BasicSiteKind.Keyword && dialect.Keyword(keyword.Token) is "REM" or "'";
        if (!remark) { return null; }

        string text = source.Lines[line.Line];
        int start = keyword.End;
        return start < text.Length ? text[start..].Trim() : "";
    }

    private static DocumentSymbol Symbol(
        BasicSource source,
        BasicSourceLine line,
        string name,
        SymbolKind kind,
        int end,
        string detail,
        DocumentSymbol[]? children = null,
        int? start = null) => new()
    {
        Name = name,
        Children = children is { Length: > 0 } ? children : null,
        Detail = detail,
        Kind = kind,
        Range = new LspRange(start ?? line.Line, 0, end, source.Lines[end].Length),
        SelectionRange = start is { } first && first != line.Line
            ? new LspRange(first, 0, first, source.Lines[first].Length)
            : new LspRange(line.Line, line.Start, line.Line, Math.Max(line.End, line.Start))
    };

    // A line number's uses: how many statements name it.
    private static string LineUses(BasicSource source, BasicSite site)
    {
        string[] uses = [.. source.References(site, includeDefinition: false).Select(use => use.Via ?? "a statement")];
        return uses.Length == 0
            ? $"Line {site.Number}: no statement jumps to it."
            : $"Line {site.Number}: named by {Counts(uses)}.";
    }

    // Such as "2 GOSUB, 1 GOTO".
    private static string Counts(string[] uses) =>
        string.Join(", ", uses.GroupBy(use => use).Select(group => $"{group.Count()} {group.Key}"));

    // A variable or function: its type, what BASIC calls it, and its other spellings in the program.
    private static string Name(BasicSource source, BasicSite site)
    {
        string kind = BasicSource.Describe(site, source.Dialect);
        string stored = site.Key.TrimEnd('(');
        string[] spellings = [.. source.References(site).Select(other => other.Name).Distinct(StringComparer.Ordinal)];
        string article = kind[0] is 'a' or 'e' or 'i' or 'o' or 'u' ? "an" : "a";
        string text = site.Kind == BasicSiteKind.Function ? $"**FN {site.Name}**: a function" : $"**{site.Name}**: {article} {kind}";
        if (site.Name != stored || spellings.Length > 1)
        {
            text += $". BASIC keeps only the first two characters and the type, so it is **{stored}**";
            string[] others = [.. spellings.Where(name => name != site.Name)];
            if (others.Length > 0) { text += $"; the program also writes it as {string.Join(", ", others)}"; }
        }

        return text + ".";
    }

    // Whether a function site is the one DEF FN names.
    private static bool Defines(BasicSource source, BasicSite site)
    {
        int index = source.Sites.ToList().IndexOf(site);
        return index >= 2
            && source.Sites[index - 1].Kind == BasicSiteKind.Keyword
            && source.Sites[index - 2] is { Kind: BasicSiteKind.Keyword, Text: var definition }
            && definition.Equals("DEF", StringComparison.OrdinalIgnoreCase);
    }

    private static LspLocation Location(BasicDocument document, BasicSite site) => Location(document, site.Line, site.Start, site.End);

    private static LspLocation Location(BasicDocument document, int line, int start, int end) =>
        new() { Uri = document.Uri, Range = new LspRange(line, start, line, end) };

    private static LspRange Range(BasicSite site) => new(site.Line, site.Start, site.Line, site.End);

    [GeneratedRegex(@"(?i)(GO\s*TO|GOSUB|THEN|ELSE|RUN|LIST|LLIST|DEL|DELETE|RESUME|EDIT)\s*(\d+\s*[,-]\s*)*\d*$")]
    private static partial Regex JumpBefore();

    [GeneratedRegex(@"(?i)(^\s*\d+\s*(REM|')|:\s*(REM|')|\bREM\b)")]
    private static partial Regex RemarkBefore();
}
