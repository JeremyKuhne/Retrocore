// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Globalization;
using System.Text.RegularExpressions;

namespace Retrocore.Pascal;

/// <summary>
///  An Apple Pascal compiler listing: where each source line's code is, the segments' and procedures' names, and the
///  variables they declare.
/// </summary>
/// <remarks>
///  <para>
///   Each line of a listing is a source line with its line number, segment number and procedure number, then
///   <c>D</c> for a declaration or the statement's nesting depth, then an offset, as in
///   <c>    9   1    1:2    13 SHOW(I)</c>. A statement's offset is where its code starts, in bytes from the
///   procedure's entry; a declaration's is the word its variables start at. Other lines, such as page headings and
///   errors, are left out.
///  </para>
///  <para>
///   A segment is named by the first <c>PROGRAM</c>, <c>UNIT</c> or <c>SEGMENT</c> heading in it, and a procedure by
///   its heading, as the compiler names them: the first eight characters, in capitals, are what a code file keeps.
///  </para>
/// </remarks>
public sealed partial class PascalListing
{
    private readonly Dictionary<int, string> _segments = [];
    private readonly Dictionary<(int Segment, int Procedure), string> _procedures = [];
    private readonly Dictionary<(int Segment, int Procedure), List<PascalListingLine>> _statements = [];
    private readonly Dictionary<(int Segment, int Procedure), List<PascalVariable>> _variables = [];
    private readonly Dictionary<int, PascalListingLine> _lines = [];

    private PascalListing(List<PascalListingLine> lines)
    {
        Lines = lines;
        foreach (PascalListingLine line in lines)
        {
            _lines.TryAdd(line.Line, line);
            (int, int) procedure = (line.Segment, line.Procedure);
            if (!line.IsDeclaration)
            {
                if (!_statements.TryGetValue(procedure, out List<PascalListingLine>? statements))
                {
                    _statements[procedure] = statements = [];
                }

                statements.Add(line);
                continue;
            }

            if (Heading().Match(Code(line.Text)) is { Success: true } heading)
            {
                string name = heading.Groups["name"].Value;
                _procedures.TryAdd(procedure, name);
                if (heading.Groups["segment"].Success || heading.Groups["kind"].Value is "PROGRAM" or "UNIT")
                {
                    _segments.TryAdd(line.Segment, name);
                }
            }
        }

        foreach (List<PascalListingLine> statements in _statements.Values)
        {
            statements.Sort((first, second) => first.Offset != second.Offset ? first.Offset.CompareTo(second.Offset) : first.Line.CompareTo(second.Line));
        }

        Declarations(lines);
    }

    /// <summary>
    ///  Gets the listing's lines, in order.
    /// </summary>
    public IReadOnlyList<PascalListingLine> Lines { get; }

    /// <summary>
    ///  Reads a listing.
    /// </summary>
    /// <param name="text">The listing, as plain text.</param>
    /// <returns>The listing.</returns>
    public static PascalListing Parse(string text)
    {
        ArgumentNullException.ThrowIfNull(text);
        List<PascalListingLine> lines = [];
        foreach (string line in text.Split('\n'))
        {
            if (Entry().Match(line.TrimEnd('\r')) is not { Success: true } match) { continue; }

            string depth = match.Groups["depth"].Value;
            lines.Add(new PascalListingLine(
                Number(match.Groups["line"].Value),
                Number(match.Groups["segment"].Value),
                Number(match.Groups["procedure"].Value),
                depth is "D" or "d" ? null : Number(depth),
                Number(match.Groups["offset"].Value),
                match.Groups["text"].Value));
        }

        return new PascalListing(lines);
    }

    /// <summary>
    ///  Gets the name of a segment the listing compiles, such as a program's.
    /// </summary>
    /// <param name="segment">The segment's number.</param>
    /// <returns>The name, or null.</returns>
    public string? SegmentName(int segment) => _segments.GetValueOrDefault(segment);

    /// <summary>
    ///  Gets the segment numbers the listing names.
    /// </summary>
    public IEnumerable<int> Segments => _segments.Keys;

    /// <summary>
    ///  Says whether the listing compiles a segment a code file names, comparing the first eight characters as the
    ///  compiler keeps them.
    /// </summary>
    /// <param name="segment">The segment's number.</param>
    /// <param name="name">Its name in the code file, such as <c>PASCALSY</c>.</param>
    /// <returns>True when the listing's segment of that number has that name.</returns>
    public bool Compiles(int segment, string name) =>
        _segments.TryGetValue(segment, out string? own) && string.Equals(CodeName(own), CodeName(name), StringComparison.Ordinal);

    /// <summary>
    ///  Gets a procedure's name.
    /// </summary>
    /// <param name="segment">The segment's number.</param>
    /// <param name="procedure">The procedure's number.</param>
    /// <returns>The name, or null.</returns>
    public string? ProcedureName(int segment, int procedure) => _procedures.GetValueOrDefault((segment, procedure));

    /// <summary>
    ///  Gets the statement line a source line's code starts at, if it has code.
    /// </summary>
    /// <param name="line">The source line's number.</param>
    /// <returns>The listing's line, or null for a line that declares or that the listing does not have.</returns>
    public PascalListingLine? Statement(int line) =>
        _lines.TryGetValue(line, out PascalListingLine? found) && !found.IsDeclaration ? found : null;

    /// <summary>
    ///  Gets the source line a p-code of a procedure is in: the last statement whose code starts at or before it.
    /// </summary>
    /// <param name="segment">The segment's number.</param>
    /// <param name="procedure">The procedure's number.</param>
    /// <param name="offset">The p-code's offset from the procedure's entry.</param>
    /// <returns>The line, or null when the listing has none of the procedure's statements.</returns>
    public PascalListingLine? LineAt(int segment, int procedure, int offset)
    {
        if (!_statements.TryGetValue((segment, procedure), out List<PascalListingLine>? statements)) { return null; }

        PascalListingLine? found = null;
        foreach (PascalListingLine line in statements)
        {
            if (line.Offset > offset) { break; }

            // Of the lines that start at one offset, a BEGIN and the statement after it, the statement.
            if (found is null || line.Offset > found.Offset || line.Depth >= found.Depth) { found = line; }
        }

        return found;
    }

    /// <summary>
    ///  Gets the variables and parameters a procedure declares whose words the listing shows.
    /// </summary>
    /// <param name="segment">The segment's number.</param>
    /// <param name="procedure">The procedure's number.</param>
    /// <returns>The variables, by word.</returns>
    public IReadOnlyList<PascalVariable> Variables(int segment, int procedure) =>
        _variables.TryGetValue((segment, procedure), out List<PascalVariable>? variables) ? variables : [];

    /// <summary>
    ///  Gets the name a code file keeps for a segment or procedure: its first eight characters, in capitals.
    /// </summary>
    /// <param name="name">The name.</param>
    /// <returns>The code file's name.</returns>
    public static string CodeName(string name)
    {
        ArgumentNullException.ThrowIfNull(name);
        string upper = name.ToUpperInvariant();
        return upper.Length > 8 ? upper[..8] : upper;
    }

    // The variables of each procedure, from its declarations: a heading's parameters, then its VAR sections. A
    // name's word follows the one before it on the line when that one's size is known; otherwise the line's names
    // after it are left out.
    private void Declarations(List<PascalListingLine> lines)
    {
        Dictionary<(int, int), string> sections = [];
        foreach (PascalListingLine line in lines.Where(line => line.IsDeclaration))
        {
            (int, int) procedure = (line.Segment, line.Procedure);
            string code = Code(line.Text).Trim();
            string section = sections.GetValueOrDefault(procedure, "");
            string groups = "";
            int word = line.Offset;
            bool parameters = false;
            if (Heading().Match(code) is { Success: true } heading)
            {
                section = "";
                string kind = heading.Groups["kind"].Value;
                string rest = code[heading.Length..];
                int open = rest.IndexOf('(', StringComparison.Ordinal);
                int close = rest.LastIndexOf(')');
                if (kind != "PROGRAM" && open >= 0 && close > open)
                {
                    groups = rest[(open + 1)..close];
                    parameters = true;
                }

                // A function's result is in the words before its parameters.
                if (kind == "FUNCTION" && line.Offset > 1)
                {
                    string result = close >= 0 ? rest[(close + 1)..] : rest;
                    int colon = result.IndexOf(':', StringComparison.Ordinal);
                    string type = colon < 0 ? "" : result[(colon + 1)..].Trim().TrimEnd(';').Trim();
                    Add(procedure, new PascalVariable(heading.Groups["name"].Value, 1, line.Offset - 1, type));
                }
            }
            else if (Section().Match(code) is { Success: true } keyword)
            {
                section = keyword.Groups["keyword"].Value.ToUpperInvariant();
                groups = section == "VAR" ? code[keyword.Length..] : "";
            }
            else if (section == "VAR")
            {
                groups = code;
            }

            sections[procedure] = section;
            bool known = true;
            foreach (string group in groups.Split(';'))
            {
                if (!known) { break; }

                int colon = group.IndexOf(':', StringComparison.Ordinal);
                if (colon < 0) { continue; }

                string names = group[..colon].Trim();
                bool reference = parameters && names.StartsWith("VAR ", StringComparison.OrdinalIgnoreCase);
                if (reference) { names = names[4..]; }
                string type = group[(colon + 1)..].Trim();
                int size = reference ? 1 : Size(type, parameters);
                foreach (string name in names.Split(','))
                {
                    if (!Identifier().IsMatch(name.Trim())) { continue; }

                    Add(procedure, new PascalVariable(name.Trim(), word, Math.Max(size, 0), type));
                    known = size > 0;
                    if (!known) { break; }
                    word += size;
                }
            }
        }
    }

    private void Add((int, int) procedure, PascalVariable variable)
    {
        if (!_variables.TryGetValue(procedure, out List<PascalVariable>? variables))
        {
            _variables[procedure] = variables = [];
        }

        if (!variables.Exists(known => known.Word == variable.Word)) { variables.Add(variable); }
    }

    // The words a type takes, or 0 when the listing cannot tell: a named type, an array, a record or a set. A
    // structured value parameter's size is not known either.
    private static int Size(string type, bool parameter)
    {
        string upper = type.ToUpperInvariant().Replace(" ", "", StringComparison.Ordinal);
        if (upper is "INTEGER" or "CHAR" or "BOOLEAN"
            || upper.StartsWith('^')
            || upper.Contains("..", StringComparison.Ordinal)
            || (upper.StartsWith('(') && upper.EndsWith(')')))
        {
            return 1;
        }

        if (parameter) { return 0; }
        if (upper == "REAL") { return 2; }
        if (upper == "STRING") { return 41; }
        return StringOf().Match(upper) is { Success: true } sized ? (Number(sized.Groups["length"].Value) + 2) / 2 : 0;
    }

    // A line's code, without its comments.
    private static string Code(string text) => Comment().Replace(text, " ");

    private static int Number(string text) => int.Parse(text, NumberStyles.None, CultureInfo.InvariantCulture);

    [GeneratedRegex(@"^\s*(?<line>\d+)\s+(?<segment>\d+)\s+(?<procedure>\d+):(?<depth>[Dd]|\d+)\s+(?<offset>\d+) ?(?<text>.*)$")]
    private static partial Regex Entry();

    [GeneratedRegex(@"^\s*(?<segment>SEGMENT\s+)?(?<kind>PROGRAM|PROCEDURE|FUNCTION|UNIT)\s+(?<name>[A-Za-z][A-Za-z0-9_]*)", RegexOptions.IgnoreCase)]
    private static partial Regex Heading();

    [GeneratedRegex(@"^(?<keyword>VAR|TYPE|CONST|LABEL|BEGIN|USES|INTERFACE|IMPLEMENTATION)\b", RegexOptions.IgnoreCase)]
    private static partial Regex Section();

    [GeneratedRegex(@"^\s*[A-Za-z][A-Za-z0-9_]*\s*$")]
    private static partial Regex Identifier();

    [GeneratedRegex(@"^STRING\[(?<length>\d+)\]$")]
    private static partial Regex StringOf();

    [GeneratedRegex(@"\(\*.*?\*\)|\{.*?\}")]
    private static partial Regex Comment();
}
