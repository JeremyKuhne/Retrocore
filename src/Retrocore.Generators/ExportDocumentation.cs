// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Documentation;

namespace Retrocore.Generators;

/// <summary>
///  Turns the <c>;;</c> summaries of exported symbols into C# XML documentation.
/// </summary>
internal static class ExportDocumentation
{
    /// <summary>
    ///  Gets each documented export's summary as XML documentation text.
    /// </summary>
    /// <param name="text">The ROM source.</param>
    /// <param name="path">Its path.</param>
    /// <param name="rom">The assembly.</param>
    /// <returns>Summaries by export name.</returns>
    internal static Dictionary<string, string> Summaries(string text, string path, AssemblyResult rom)
    {
        Dictionary<string, string> summaries = new(StringComparer.Ordinal);
        DocumentationSet set = DocumentationSet.Create([DocumentationParser.Parse(text, path)], rom);
        foreach (string name in rom.Exports.Keys)
        {
            if ((set.Find(name) ?? set.FindRoutine(name)) is not { } topic) { continue; }
            string summary = topic.Summary;

            // A bare or named Inherit: takes the summary of the topic it names in this file.
            if (summary.Length == 0 && topic.Section("Inherit") is { } inherit)
            {
                List<DocumentationLink> links = DocumentationText.Links(inherit.Text);
                DocumentationTopic? source = links.Count != 0
                    ? set.Find(links[0].Target)
                    : set.Topics.FirstOrDefault(other => other != topic && other.EntryLabels.Contains(name));

                summary = source?.Summary ?? "";
            }

            if (summary.Length != 0) { summaries[name] = Xml(summary, rom); }
        }

        return summaries;
    }

    // Links become <see cref> for other exports and <c> otherwise; {references} and `code` become <c>.
    private static string Xml(string text, AssemblyResult rom)
    {
        List<string> pieces = [];
        int copied = 0;
        foreach (DocumentationLink link in DocumentationText.Links(text))
        {
            pieces.Add(Plain(text[copied..link.Start]));
            if (link.IsUrl)
            {
                pieces.Add($"<see href=\"{Escape(link.Target)}\">{Escape(link.Text)}</see>");
            }
            else if (rom.Exports.ContainsKey(link.Target) && link.Text == link.Target)
            {
                pieces.Add($"<see cref=\"{link.Target}\"/>");
            }
            else
            {
                pieces.Add($"<c>{Escape(link.Text)}</c>");
            }

            copied = link.Start + link.Length;
        }

        pieces.Add(Plain(text[copied..]));
        return string.Concat(pieces);
    }

    private static string Plain(string text)
    {
        string escaped = Escape(text);
        List<string> pieces = [];
        int index = 0;
        while (index < escaped.Length)
        {
            int open = escaped.IndexOfAny(['{', '`'], index);
            int close = open < 0 ? -1 : escaped.IndexOf(escaped[open] == '{' ? '}' : '`', open + 1);
            if (close < 0)
            {
                pieces.Add(escaped[index..]);
                break;
            }

            pieces.Add(escaped[index..open]);
            pieces.Add($"<c>{escaped[(open + 1)..close]}</c>");
            index = close + 1;
        }

        return string.Concat(pieces);
    }

    private static string Escape(string text) => text.Replace("&", "&amp;").Replace("<", "&lt;").Replace(">", "&gt;");
}
