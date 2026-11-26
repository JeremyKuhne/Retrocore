// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Documentation;
using System.Text.RegularExpressions;

namespace Retrocore.Pascal.Source;

/// <summary>
///  A documentation comment, <c>(** … *)</c>: a summary, remarks and sections, as the SDK's Pascal style describes.
/// </summary>
public sealed partial class PascalDocComment
{
    /// <summary>
    ///  The sections a documentation comment may have, in the order they are written.
    /// </summary>
    public static readonly IReadOnlyList<string> Sections = ["Parameters", "Returns", "Uses", "Errors", "See", "Also"];

    // Headings that are almost a section's: the assembly's own, and slips of Pascal's. Other words before a colon are
    // prose ("Note: ...").
    private static readonly HashSet<string> s_nearSections =
    [
        "In", "Out", "Keeps", "Entry", "Calls", "Cycles", "Stack", "Model", "Members", "Example", "Deprecated",
        "Inherit", "Include", "Param", "Params", "Parameter", "Return", "Result", "Results", "Global", "Globals",
        "Error", "Seealso"
    ];

    private PascalDocComment(PascalToken token, string summary, List<string> remarks, List<PascalDocSection> sections,
        List<(int Line, string Text)> unknown)
    {
        Token = token;
        Summary = summary;
        Remarks = remarks;
        DocSections = sections;
        UnknownSections = unknown;
    }

    /// <summary>
    ///  Gets the comment's token.
    /// </summary>
    public PascalToken Token { get; }

    /// <summary>
    ///  Gets the summary: the first paragraph.
    /// </summary>
    public string Summary { get; }

    /// <summary>
    ///  Gets the paragraphs after the summary, before the sections.
    /// </summary>
    public IReadOnlyList<string> Remarks { get; }

    /// <summary>
    ///  Gets the sections, in the order written.
    /// </summary>
    public IReadOnlyList<PascalDocSection> DocSections { get; }

    /// <summary>
    ///  Gets lines that look like a section's heading but name none of <see cref="Sections"/>.
    /// </summary>
    public IReadOnlyList<(int Line, string Text)> UnknownSections { get; }

    /// <summary>
    ///  Gets the historical names its <c>Also:</c> section gives, each with its documents' keys; null for an item that
    ///  is not written as <c>NAME (KEYS)</c>.
    /// </summary>
    public IEnumerable<(string Item, DocumentationAlso? Also)> Also =>
        DocSections.Where(section => section.Name == "Also")
            .SelectMany(section => section.Items)
            .Select(item => (item, DocumentationAlso.Parse(item)));

    /// <summary>
    ///  Gets the comment's links, <c>&lt;Name&gt;</c> or <c>&lt;text at Name&gt;</c>, where each is in the file.
    /// </summary>
    public IEnumerable<PascalDocLink> Links
    {
        get
        {
            string[] lines = PascalLexer.Lines(Token.Text);
            for (int index = 0; index < lines.Length; index++)
            {
                int offset = index == 0 ? Token.Column : 0;
                foreach (Match link in Link().Matches(lines[index]))
                {
                    yield return new(
                        link.Groups["target"].Value,
                        Token.Line + index,
                        offset + link.Index,
                        offset + link.Index + link.Length);
                }
            }
        }
    }

    /// <summary>
    ///  Gets a section by name.
    /// </summary>
    /// <param name="name">The section's name.</param>
    /// <returns>The section, or null.</returns>
    public PascalDocSection? Section(string name) => DocSections.FirstOrDefault(section => section.Name == name);

    /// <summary>
    ///  Parses a documentation comment's token.
    /// </summary>
    /// <param name="token">The token, a <see cref="PascalTokenKind.DocComment"/>.</param>
    /// <returns>The comment.</returns>
    public static PascalDocComment Parse(PascalToken token)
    {
        ArgumentNullException.ThrowIfNull(token);
        string body = token.Text;
        body = body.StartsWith("(**", StringComparison.Ordinal) ? body[3..] : body;
        int close = 0;
        if (body.EndsWith("**)", StringComparison.Ordinal)) { close = 3; }
        else if (body.EndsWith("*)", StringComparison.Ordinal)) { close = 2; }

        body = body[..^close];
        string[] lines = PascalLexer.Lines(body);

        // The first line follows "(**"; the others keep their indentation, measured from the least indented.
        int indent = lines.Skip(1).Where(line => line.Trim().Length > 0)
            .Select(line => line.Length - line.TrimStart().Length)
            .DefaultIfEmpty(0)
            .Min();

        List<string> paragraphs = [];
        List<PascalDocSection> sections = [];
        List<(int, string)> unknown = [];
        List<string> current = [];
        (string Name, int Line, List<string> Lines)? section = null;
        for (int index = 0; index < lines.Length; index++)
        {
            string raw = index > 0 && lines[index].Length >= indent ? lines[index][indent..] : lines[index].TrimStart();
            int line = token.Line + index;
            string trimmed = raw.Trim();
            if (SectionHeading().Match(raw) is { Success: true } heading)
            {
                string name = heading.Groups["name"].Value;
                if (Sections.Contains(name))
                {
                    Flush();
                    if (section is { } open) { sections.Add(new(open.Name, open.Line, string.Join(' ', open.Lines))); }
                    section = (name, line, [heading.Groups["rest"].Value.Trim()]);
                    continue;
                }

                if (s_nearSections.Contains(name)) { unknown.Add((line, name)); }
            }

            if (section is { } inSection)
            {
                // A section goes on over lines indented two or more spaces.
                if (trimmed.Length > 0 && raw.StartsWith("  ", StringComparison.Ordinal))
                {
                    inSection.Lines.Add(trimmed);
                    continue;
                }

                sections.Add(new(inSection.Name, inSection.Line, string.Join(' ', inSection.Lines)));
                section = null;
            }

            if (trimmed.Length == 0) { Flush(); }
            else { current.Add(trimmed); }
        }

        if (section is { } last) { sections.Add(new(last.Name, last.Line, string.Join(' ', last.Lines))); }
        Flush();
        return new(token, paragraphs.Count > 0 ? paragraphs[0] : "", [.. paragraphs.Skip(1)], sections, unknown);

        void Flush()
        {
            if (current.Count > 0) { paragraphs.Add(string.Join(' ', current)); }
            current.Clear();
        }
    }

    /// <summary>
    ///  Splits a list section into its items, at commas outside parentheses.
    /// </summary>
    /// <param name="text">The section's text.</param>
    /// <returns>The items.</returns>
    internal static IEnumerable<string> SplitItems(string text)
    {
        int depth = 0;
        int start = 0;
        for (int index = 0; index < text.Length; index++)
        {
            if (text[index] is '(' or '<') { depth++; }
            else if (text[index] is ')' or '>') { depth--; }
            else if (text[index] == ',' && depth == 0)
            {
                if (text[start..index].Trim() is { Length: > 0 } item) { yield return item; }
                start = index + 1;
            }
        }

        if (text[start..].Trim() is { Length: > 0 } rest) { yield return rest; }
    }

    /// <summary>
    ///  Splits <c>Parameters:</c> into its <c>Name = meaning</c> entries: a new entry starts at a name and <c>=</c>
    ///  after a comma.
    /// </summary>
    /// <param name="text">The section's text.</param>
    /// <returns>The entries.</returns>
    internal static IEnumerable<string> SplitEntries(string text) =>
        EntryStart().Split(text).Select(entry => entry.Trim().TrimEnd(',')).Where(entry => entry.Length > 0);

    [GeneratedRegex(@"^\s*(?<name>[A-Z][A-Za-z]+):(?<rest>.*)$")]
    private static partial Regex SectionHeading();

    [GeneratedRegex(@"<(?:[^<>]* at )?(?<target>[A-Za-z][A-Za-z0-9]*(?:\.[A-Za-z][A-Za-z0-9]*)*)>")]
    private static partial Regex Link();

    [GeneratedRegex(@",\s+(?=[A-Za-z][A-Za-z0-9]*\s*=)")]
    private static partial Regex EntryStart();
}
