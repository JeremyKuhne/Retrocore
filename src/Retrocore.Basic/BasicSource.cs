// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Basic;

/// <summary>
///  BASIC text as the interpreter reads it: its lines, the reserved words, line numbers, variables and functions
///  in them with their columns, and its problems.
/// </summary>
/// <remarks>
///  <para>
///   Each line is tokenized as the ROM would, so a name is what BASIC makes of it: in <c>SCORE</c>, BASIC finds
///   <c>OR</c>, so the variable is <c>SC</c>. Two names are the same variable when their first two characters,
///   their type and whether they are arrays agree. Integer BASIC keeps the whole name, and one variable for it.
///  </para>
/// </remarks>
public sealed partial class BasicSource
{
    private readonly Dictionary<int, BasicSourceLine> _numbered = [];

    private BasicSource(string[] lines, BasicParseResult parse)
    {
        Lines = lines;
        Parse = parse;
    }

    /// <summary>
    ///  Gets the dialect the text was read as; null when none was given or named.
    /// </summary>
    public BasicDialect? Dialect => Parse.Dialect;

    /// <summary>
    ///  Gets the text's lines.
    /// </summary>
    public IReadOnlyList<string> Lines { get; }

    /// <summary>
    ///  Gets the program the text holds, and the problems that keep it from being stored.
    /// </summary>
    public BasicParseResult Parse { get; }

    /// <summary>
    ///  Gets the numbered lines, in text order.
    /// </summary>
    public IReadOnlyList<BasicSourceLine> NumberedLines { get; private set; } = [];

    /// <summary>
    ///  Gets every reserved word, line number, variable and function, in text order.
    /// </summary>
    public IReadOnlyList<BasicSite> Sites { get; private set; } = [];

    /// <summary>
    ///  Gets every problem: those that keep the program from being stored, and warnings about what BASIC will make of
    ///  the text.
    /// </summary>
    public IReadOnlyList<BasicDiagnostic> Diagnostics { get; private set; } = [];

    /// <summary>
    ///  Reads BASIC text.
    /// </summary>
    /// <param name="text">The text.</param>
    /// <param name="dialect">The dialect when the text and path do not name one.</param>
    /// <param name="path">The file the text came from, for its extension.</param>
    /// <returns>The analysis.</returns>
    public static BasicSource Analyze(string text, BasicDialect? dialect = null, string? path = null)
    {
        ArgumentNullException.ThrowIfNull(text);
        string[] lines = text.ReplaceLineEndings("\n").Split('\n');
        BasicSource source = new(lines, BasicProgram.Parse(text, dialect, path));
        if (source.Dialect is { } basic) { source.Scan(basic); }
        else { source.Diagnostics = source.Parse.Diagnostics; }
        return source;
    }

    /// <summary>
    ///  Finds what is at a position.
    /// </summary>
    /// <param name="line">The zero-based line.</param>
    /// <param name="column">The column.</param>
    /// <returns>The site, or null.</returns>
    public BasicSite? SiteAt(int line, int column)
    {
        BasicSite? found = null;
        foreach (BasicSite site in Sites)
        {
            if (site.Line > line) { break; }
            if (site.Line != line || !site.Contains(column)) { continue; }

            // Just past one site and on the next: the next.
            found = site;
            if (column < site.End) { break; }
        }

        return found;
    }

    /// <summary>
    ///  Finds the line with a number.
    /// </summary>
    /// <param name="number">The line number.</param>
    /// <returns>The line, or null when there is none.</returns>
    public BasicSourceLine? LineNumbered(int number) => _numbered.GetValueOrDefault(number);

    /// <summary>
    ///  Finds every place that means the same as a site: a line's number and each reference to it, or each use of a
    ///  variable or function.
    /// </summary>
    /// <param name="site">The site.</param>
    /// <param name="includeDefinition">Whether to include the line's own number.</param>
    /// <returns>The sites, in text order.</returns>
    public IEnumerable<BasicSite> References(BasicSite site, bool includeDefinition = true) => site.Kind switch
    {
        BasicSiteKind.LineNumber or BasicSiteKind.LineReference or BasicSiteKind.Label =>
            Sites.Where(other => SameLine(other, site, includeDefinition)),
        BasicSiteKind.Variable or BasicSiteKind.Function => Sites.Where(other => other.Kind == site.Kind && other.Key == site.Key),
        _ => []
    };

    // Whether a site is the line a line site names: a reference to it, or its own number.
    private static bool SameLine(BasicSite other, BasicSite site, bool includeDefinition)
    {
        if (other.Number != site.Number) { return false; }
        return other.Kind == BasicSiteKind.LineReference
            || (includeDefinition && other.Kind is BasicSiteKind.LineNumber or BasicSiteKind.Label);
    }

    /// <summary>
    ///  Describes a variable's or function's type, as its suffix and parentheses give it.
    /// </summary>
    /// <param name="site">The variable or function.</param>
    /// <param name="dialect">The dialect; Integer BASIC's numbers are integers, and it has no string arrays.</param>
    /// <returns>Such as "string array" or "integer variable".</returns>
    public static string Describe(BasicSite site, BasicDialect? dialect = null)
    {
        if (site.Kind == BasicSiteKind.Function) { return "function"; }
        if (dialect == BasicDialect.Integer)
        {
            return site.Key.EndsWith('$') ? "string variable" : site.Subscripted ? "integer array" : "integer variable";
        }

        string type = site.Key.TrimEnd('(')[^1] switch
        {
            '$' => "string",
            '%' => "integer",
            '!' => "single-precision",
            '#' => "double-precision",
            _ => "numeric"
        };

        return site.Key.EndsWith('(') ? $"{type} array" : $"{type} variable";
    }
}
