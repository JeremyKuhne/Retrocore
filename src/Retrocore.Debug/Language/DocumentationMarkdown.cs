// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Documentation;

namespace Retrocore.Debug.Language;

/// <summary>
///  Renders documentation topics as Markdown for hover and completion.
/// </summary>
internal static class DocumentationMarkdown
{
    /// <summary>
    ///  Renders a topic's complete documentation.
    /// </summary>
    /// <param name="topic">The topic, with inheritance already merged.</param>
    /// <param name="resolver">Resolves its links.</param>
    /// <param name="href">Gets the address a resolved code link opens, or null to show it as code.</param>
    /// <returns>The Markdown.</returns>
    internal static string Render(DocumentationTopic topic, DocumentationResolver resolver, Func<DocumentationTarget, string?> href)
    {
        List<string> parts = [];
        if (topic.Summary.Length != 0) { parts.Add(Text(topic.Summary, topic, resolver, href)); }
        if (topic.Remarks.Count != 0) { parts.Add(Block(topic.Remarks, topic, resolver, href)); }
        foreach (DocumentationSection section in topic.Sections)
        {
            if (section.Name is "Inherit" or "Include") { continue; }
            string heading = section.Condition is { } condition
                ? $"**{Title(section.Name)}** _({Condition(condition)})_"
                : $"**{Title(section.Name)}**";

            if (section.Entries.Count != 0)
            {
                IEnumerable<string> entries = section.Entries
                    .Select(entry => $"- `{entry.Name}` — {Text(entry.Meaning, topic, resolver, href)}");

                parts.Add($"{heading}\n{string.Join("\n", entries)}");
            }
            else if (section.Items.Count != 0)
            {
                IEnumerable<string> items = section.Items.Select(item => Item(item, topic, resolver, href));
                parts.Add($"{heading}: {string.Join(", ", items)}");
            }
            else if (DocumentationSections.IsFreeText(section.Name) || section.Lines.Count > 1)
            {
                parts.Add($"{heading}\n\n{Block(section.Lines, topic, resolver, href)}");
            }
            else
            {
                parts.Add($"{heading}: {Text(section.Text, topic, resolver, href)}");
            }
        }

        if (topic.InheritedFrom is { } inherited && inherited.Kind != DocumentationKind.Topic)
        {
            parts.Add($"_Inherited from {Link(inherited.Name, resolver.Resolve(topic, inherited.Name), href)}._");
        }

        return string.Join("\n\n", parts);
    }

    /// <summary>
    ///  Renders the summary alone, for completion.
    /// </summary>
    /// <param name="topic">The topic.</param>
    /// <param name="resolver">Resolves its links.</param>
    /// <returns>The summary with links shown as their names.</returns>
    internal static string Summary(DocumentationTopic topic, DocumentationResolver resolver) =>
        Text(topic.Summary, topic, resolver, _ => null);

    /// <summary>
    ///  Describes a condition for readers: the IIe model it selects, or the condition itself.
    /// </summary>
    /// <param name="condition">The condition.</param>
    /// <returns>The description.</returns>
    internal static string Condition(string condition) =>
        DocumentationResolver.ModelOf(condition) switch
        {
            "Enhanced" => "Enhanced IIe",
            "Original" => "original IIe",
            _ => $"when {condition}"
        };

    private static string Title(string name) => name == "See" ? "See also" : name;

    private static string Item(
        string item,
        DocumentationTopic topic,
        DocumentationResolver resolver,
        Func<DocumentationTarget, string?> href)
    {
        return item.StartsWith('<') ? Text(item, topic, resolver, href) : $"`{item}`";
    }

    // Paragraphs, with code lines (">" or "(start code)" ... "(end)") as fenced blocks.
    private static string Block(
        IReadOnlyList<string> lines,
        DocumentationTopic topic,
        DocumentationResolver resolver,
        Func<DocumentationTarget, string?> href)
    {
        List<string> output = [];
        List<string> paragraph = [];
        bool code = false;
        void Flush()
        {
            if (paragraph.Count == 0) { return; }
            output.Add(Text(string.Join(" ", paragraph), topic, resolver, href));
            paragraph.Clear();
        }

        foreach (string raw in lines)
        {
            string line = raw.TrimEnd();
            string trimmed = line.Trim();
            if (code)
            {
                if (trimmed.StartsWith("(end", StringComparison.OrdinalIgnoreCase))
                {
                    output.Add("```");
                    code = false;
                }
                else
                {
                    output.Add(line);
                }

                continue;
            }

            bool starts = trimmed.Equals("(start code)", StringComparison.OrdinalIgnoreCase)
                || trimmed.Equals("(code)", StringComparison.OrdinalIgnoreCase);

            if (starts)
            {
                Flush();
                output.Add("```asm");
                code = true;
            }
            else if (trimmed.StartsWith('>'))
            {
                Flush();
                output.Add($"```asm\n{trimmed[1..]}\n```");
            }
            else if (trimmed.Length == 0)
            {
                Flush();
                output.Add("");
            }
            else if (trimmed[0] is '-' or '*' or '+' && trimmed.Length > 1 && trimmed[1] == ' ')
            {
                Flush();
                output.Add($"- {Text(trimmed[2..], topic, resolver, href)}");
            }
            else
            {
                paragraph.Add(trimmed);
            }
        }

        Flush();
        if (code) { output.Add("```"); }
        return string.Join("\n", output).Replace("```\n```asm\n", "", StringComparison.Ordinal);
    }

    /// <summary>
    ///  Renders inline text: links, <c>{references}</c>, <c>*bold*</c> and backticked code.
    /// </summary>
    private static string Text(
        string text,
        DocumentationTopic topic,
        DocumentationResolver resolver,
        Func<DocumentationTarget, string?> href)
    {
        List<DocumentationLink> links = DocumentationText.Links(text);
        List<string> pieces = [];
        int copied = 0;
        foreach (DocumentationLink link in links)
        {
            pieces.Add(Inline(text[copied..link.Start]));
            DocumentationTarget target = resolver.Resolve(topic, link.Target);
            string shown = link.Text == link.Target && target.Kind is DocumentationTargetKind.Topic or DocumentationTargetKind.Symbol
                ? target.Name
                : link.Text;

            pieces.Add(Link(shown, target, href));
            copied = link.Start + link.Length;
        }

        pieces.Add(Inline(text[copied..]));
        return string.Concat(pieces);
    }

    private static string Link(string shown, DocumentationTarget target, Func<DocumentationTarget, string?> href)
    {
        switch (target.Kind)
        {
            case DocumentationTargetKind.Url:
            case DocumentationTargetKind.Document:
                return target.Address is { } address ? $"[{shown}]({Uri(address)})" : shown;
            case DocumentationTargetKind.Topic:
            case DocumentationTargetKind.Symbol:
                return href(target) is { } location ? $"[`{shown}`]({location})" : $"`{shown}`";
            case DocumentationTargetKind.Directive:
            case DocumentationTargetKind.Instruction:
                return $"`{shown}`";
            default:
                return shown;
        }
    }

    private static string Uri(string address) =>
        address.StartsWith("http", StringComparison.OrdinalIgnoreCase) ? address : new Uri(address.Split('#')[0]).AbsoluteUri;

    // {NAME} references render as code, *bold* as Markdown bold; backticks pass through.
    private static string Inline(string text)
    {
        foreach ((string name, int start, int length) in DocumentationText.References(text).AsEnumerable().Reverse())
        {
            text = string.Concat(text.AsSpan(0, start), $"`{name}`", text.AsSpan(start + length));
        }

        List<string> pieces = [];
        int index = 0;
        while (index < text.Length)
        {
            int open = text.IndexOf('*', index);
            int close = open < 0 ? -1 : text.IndexOf('*', open + 1);
            bool bold = open >= 0 && close > open + 1 && !char.IsWhiteSpace(text[open + 1]) && !char.IsWhiteSpace(text[close - 1]);
            if (!bold)
            {
                pieces.Add(text[index..]);
                break;
            }

            pieces.Add(text[index..open]);
            pieces.Add($"**{text[(open + 1)..close]}**");
            index = close + 1;
        }

        return string.Concat(pieces);
    }
}
