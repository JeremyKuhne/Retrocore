// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Documentation;

public static partial class DocumentationParser
{
    /// <summary>
    ///  Parses a comment's text lines (after <c>;;</c>) into its summary, remarks and sections.
    /// </summary>
    private static (string Summary, List<string> Remarks, List<DocumentationSection> Sections) Body(
        List<(int Line, string Text)> body)
    {
        List<string> summary = [];
        List<string> remarks = [];
        List<DocumentationSection> sections = [];
        bool inSummary = true;
        bool afterBlank = false;
        string? name = null;
        int headingLine = 0;
        List<string> content = [];
        List<int> depths = [];
        bool compact = false;

        void Close()
        {
            if (name is null) { return; }
            sections.Add(Section(name, headingLine, content, compact, depths));
            name = null;
            content = [];
            depths = [];
        }

        foreach ((int line, string raw) in body)
        {
            string text = raw.TrimEnd();
            string trimmed = text.Trim();
            bool indented = LeadingWhiteSpace(text, text.Length) >= 2;
            if (trimmed.Length == 0)
            {
                if (name is not null && DocumentationSections.IsFreeText(name))
                {
                    content.Add("");
                    depths.Add(0);
                }
                else
                {
                    Close();
                    if (!inSummary && remarks.Count != 0 && remarks[^1].Length != 0) { remarks.Add(""); }
                }

                if (summary.Count != 0) { inSummary = false; }
                afterBlank = true;
                continue;
            }

            if (!indented && Heading(trimmed, afterBlank) is { } heading)
            {
                Close();
                name = heading.Name;
                headingLine = line;
                compact = heading.Content.Length != 0;
                if (compact)
                {
                    content.Add(heading.Content);
                    depths.Add(0);
                }

                inSummary = false;
                afterBlank = false;
                continue;
            }

            afterBlank = false;
            if (name is not null)
            {
                if (DocumentationSections.IsFreeText(name) || indented)
                {
                    content.Add(DocumentationSections.IsFreeText(name) ? text : trimmed);
                    depths.Add(text.Length - text.TrimStart().Length);
                    continue;
                }

                Close();
            }

            if (inSummary)
            {
                summary.Add(trimmed);
            }
            else
            {
                remarks.Add(text.StartsWith(' ') ? text[1..] : text);
            }
        }

        Close();
        while (remarks.Count != 0 && remarks[^1].Length == 0) { remarks.RemoveAt(remarks.Count - 1); }
        return (string.Join(" ", summary), remarks, sections);
    }

    /// <summary>
    ///  Recognizes a section heading: a defined section name and a colon, or any line ending in a colon after a
    ///  blank line.
    /// </summary>
    private static (string Name, string Content)? Heading(string text, bool afterBlank)
    {
        int colon = text.IndexOf(':');
        if (colon > 0 && (colon + 1 == text.Length || text[colon + 1] is ' ' or '\t'))
        {
            string candidate = text[..colon].Trim();
            if (DocumentationSections.Canonical(candidate) is { } canonical)
            {
                return (canonical, text[(colon + 1)..].Trim());
            }
        }

        bool plain = afterBlank && text.EndsWith(':') && text.Length > 1 && !text.Contains("://", StringComparison.Ordinal);
        return plain ? (text[..^1].Trim(), "") : null;
    }

    private static DocumentationSection Section(string name, int line, List<string> content, bool compact, List<int> depths)
    {
        while (content.Count != 0 && IsBlank(content[^1])) { content.RemoveAt(content.Count - 1); }
        List<DocumentationEntry> entries = [];
        List<string> items = [];
        if (DocumentationSections.IsEntries(name))
        {
            string joined = string.Join(" ", content.Select(text => text.Trim()));
            if (compact && joined.IndexOf('=') < 0 && joined.IndexOf(" - ", StringComparison.Ordinal) < 0)
            {
                // A bare list of names, such as "In: CH, CV", documents what is read without saying more.
                foreach (string item in DocumentationText.SplitList(joined))
                {
                    if (item.IndexOf(' ') < 0) { entries.Add(new(item, "", line)); }
                }
            }
            else if (compact)
            {
                foreach (string part in SplitEntries(joined))
                {
                    AddEntries(entries, part, line);
                }
            }
            else
            {
                int offset = 1;
                int added = 0;
                int indent = -1;
                for (int index = 0; index < content.Count; index++)
                {
                    // Names that share a meaning start a line as an entry does; indented deeper, they are a wrapped
                    // meaning, as "bytes, carry = set" may be.
                    string text = content[index];
                    int depth = index < depths.Count ? depths[index] : 0;
                    int before = entries.Count;
                    AddEntries(entries, text.Trim(), line + offset, shared: indent < 0 || depth <= indent);
                    if (entries.Count != before)
                    {
                        added = entries.Count - before;
                        indent = indent < 0 ? depth : indent;
                    }
                    else if (entries.Count != 0)
                    {
                        // A wrapped meaning continues the entry above, each of its names where they share it.
                        for (int entry = entries.Count - added; entry < entries.Count; entry++)
                        {
                            string meaning = $"{entries[entry].Meaning} {text.Trim()}";
                            entries[entry] = entries[entry] with { Meaning = meaning };
                        }
                    }

                    offset++;
                }
            }
        }
        else if (DocumentationSections.IsList(name))
        {
            items.AddRange(DocumentationText.SplitList(string.Join(" ", content.Select(text => text.Trim()))));
        }
        else if (name == "Inherit")
        {
            // Inherit: <Target> In, Out: the target, then the sections to take.
            string text = string.Join(" ", content.Select(text => text.Trim()));
            List<DocumentationLink> links = DocumentationText.Links(text);
            string remainder = links.Count == 0 ? text : text.Remove(links[0].Start, links[0].Length);
            items.AddRange(DocumentationText.SplitList(remainder)
                .Select(item => DocumentationSections.Canonical(item) ?? item));
        }

        return new(name, line, content, entries, items);
    }

    /// <summary>
    ///  Splits compact entries: a new entry starts only at a comma and space followed by a name and
    ///  <c>=</c> (or <c>-</c>), so commas inside a meaning stay in it.
    /// </summary>
    private static List<string> SplitEntries(string text)
    {
        List<string> parts = [];
        int start = 0;
        for (int index = 0; index + 1 < text.Length; index++)
        {
            if (text[index] != ',' || text[index + 1] != ' ') { continue; }
            int name = index + 2;
            while (name < text.Length && text[name] == ' ') { name++; }
            int end = name;
            while (end < text.Length && text[end] != ' ' && text[end] != '=') { end++; }
            int separator = end;
            while (separator < text.Length && text[separator] == ' ') { separator++; }
            bool equals = separator < text.Length && text[separator] == '=';
            bool dash = separator + 1 < text.Length && text[separator] == '-' && text[separator + 1] == ' ' && separator > end;

            // Names that start the text share the meaning after them, as HL and DE do in "HL, DE = ...". Later in
            // the text, names before a comma stay in the meaning before them, as "normalised" does in "the fraction,
            // normalised, zero = ...", so a list of names there is not read as entries.
            bool shares = start == 0 && IsNames(text[..index]);
            if (end > name && !shares && (equals || dash))
            {
                parts.Add(text[start..index]);
                start = index + 2;
            }
        }

        parts.Add(text[start..]);
        return parts;
    }

    // Whether text is names, as a register, flag or symbol is written, separated by a comma and a space.
    private static bool IsNames(string text)
    {
        if (text.Length == 0) { return false; }
        bool start = true;
        for (int index = 0; index < text.Length; index++)
        {
            char character = text[index];
            if (character == ',' && !start && index + 1 < text.Length && text[index + 1] == ' ')
            {
                index++;
                start = true;
            }
            else if (char.IsLetterOrDigit(character) || character is '_' or '\'' or '.' or '$' or '+' or '[' or ']')
            {
                start = false;
            }
            else
            {
                return false;
            }
        }

        return !start;
    }

    // An entry, or where shared names are allowed, one per name when names share a meaning, as "HL, DE = past the
    // bytes" and "HL, DE - past the bytes" do.
    private static void AddEntries(List<DocumentationEntry> entries, string text, int line, bool shared = true)
    {
        if (Entry(text, line) is { } entry) { entries.Add(entry); }
        else if (shared && Shared(text, line) is { } names) { entries.AddRange(names); }
    }

    private static List<DocumentationEntry>? Shared(string text, int line)
    {
        // The first separator, of either kind, after names alone: "HL, DE - the names = x" shares at the dash.
        int equals = text.IndexOf(" = ", StringComparison.Ordinal);
        int dash = text.IndexOf(" - ", StringComparison.Ordinal);
        int separator = equals < 0 || (dash >= 0 && dash < equals) ? dash : equals;
        if (separator <= 0) { return null; }
        string[] names = text[..separator].Split(", ");
        if (names.Length < 2 || !IsNames(text[..separator])) { return null; }

        string meaning = text[(separator + 3)..].Trim();
        return [.. names.Select(name => new DocumentationEntry(name, meaning, line))];
    }

    private static DocumentationEntry? Entry(string text, int line)
    {
        int separator = text.IndexOf(" = ", StringComparison.Ordinal);
        int width = 3;
        if (separator < 0)
        {
            separator = text.IndexOf(" - ", StringComparison.Ordinal);
        }

        if (separator < 0)
        {
            separator = text.IndexOf('=');
            width = 1;
        }

        if (separator <= 0) { return null; }
        string name = text[..separator].Trim();
        return name.Length == 0 || name.IndexOf(' ') >= 0
            ? null
            : new DocumentationEntry(name, text[(separator + width)..].Trim(), line);
    }
}
