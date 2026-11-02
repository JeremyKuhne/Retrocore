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
        bool compact = false;

        void Close()
        {
            if (name is null) { return; }
            sections.Add(Section(name, headingLine, content, compact));
            name = null;
            content = [];
        }

        foreach ((int line, string raw) in body)
        {
            string text = raw.TrimEnd();
            string trimmed = text.Trim();
            bool indented = text.Length - text.TrimStart().Length >= 2;
            if (trimmed.Length == 0)
            {
                if (name is not null && DocumentationSections.IsFreeText(name))
                {
                    content.Add("");
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
                if (compact) { content.Add(heading.Content); }
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

    private static DocumentationSection Section(string name, int line, List<string> content, bool compact)
    {
        while (content.Count != 0 && content[^1].Trim().Length == 0) { content.RemoveAt(content.Count - 1); }
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
                    if (Entry(part, line) is { } entry) { entries.Add(entry); }
                }
            }
            else
            {
                int offset = 1;
                foreach (string text in content)
                {
                    if (Entry(text.Trim(), line + offset) is { } entry)
                    {
                        entries.Add(entry);
                    }
                    else if (entries.Count != 0)
                    {
                        // A wrapped meaning continues the entry above.
                        DocumentationEntry previous = entries[^1];
                        entries[^1] = previous with { Meaning = $"{previous.Meaning} {text.Trim()}" };
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
            if (end > name && (equals || dash))
            {
                parts.Add(text[start..index]);
                start = index + 2;
            }
        }

        parts.Add(text[start..]);
        return parts;
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
