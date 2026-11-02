// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Documentation;

/// <summary>
///  Finds links and references in documentation text.
/// </summary>
public static class DocumentationText
{
    /// <summary>
    ///  Finds the links in a piece of text: <c>&lt;Target&gt;</c>, <c>&lt;text at Target&gt;</c> and bare URLs.
    /// </summary>
    /// <param name="text">The text.</param>
    /// <returns>The links in order.</returns>
    /// <remarks>
    ///  <para>
    ///   A <c>&lt;</c> followed by a space, a digit or <c>=</c> is a comparison, not a link, so text such as
    ///   <c>A &lt; 10</c> or <c>X &lt;= Y</c> stays plain.
    ///  </para>
    /// </remarks>
    public static List<DocumentationLink> Links(string text)
    {
        List<DocumentationLink> links = [];
        for (int index = 0; index < text.Length; index++)
        {
            if (text[index] == '<')
            {
                int close = text.IndexOf('>', index + 1);
                int nested = text.IndexOf('<', index + 1);
                if (close < 0 || (nested >= 0 && nested < close)) { continue; }
                string inner = text.Substring(index + 1, close - index - 1);
                if (inner.Length == 0 || char.IsWhiteSpace(inner[0]) || char.IsDigit(inner[0]) || inner[0] == '=')
                {
                    continue;
                }

                int at = inner.LastIndexOf(" at ", StringComparison.Ordinal);
                string target = at < 0 ? inner : inner[(at + 4)..].Trim();
                string shown = at < 0 ? inner : inner[..at].Trim();
                links.Add(new(shown, target, index, close - index + 1));
                index = close;
                continue;
            }

            if (StartsUrl(text, index) && (index == 0 || !char.IsLetterOrDigit(text[index - 1])))
            {
                int end = index;
                while (end < text.Length && !char.IsWhiteSpace(text[end]) && text[end] is not ('>' or '"')) { end++; }

                // Sentence punctuation after a URL is not part of it.
                while (end > index && text[end - 1] is '.' or ',' or ';' or ')' or ':') { end--; }
                string url = text[index..end];
                links.Add(new(url, url, index, end - index));
                index = end - 1;
            }
        }

        return links;
    }

    /// <summary>
    ///  Finds <c>{NAME}</c> references to a comment's own entries.
    /// </summary>
    /// <param name="text">The text.</param>
    /// <returns>Each name with its index and length (including the braces).</returns>
    public static List<(string Name, int Start, int Length)> References(string text)
    {
        List<(string, int, int)> references = [];
        for (int index = 0; index < text.Length; index++)
        {
            if (text[index] != '{') { continue; }
            int close = text.IndexOf('}', index + 1);
            if (close < 0) { break; }
            string name = text.Substring(index + 1, close - index - 1);
            if (name.Length != 0 && IsName(name)) { references.Add((name, index, close - index + 1)); }
            index = close;
        }

        return references;
    }

    /// <summary>
    ///  Splits a comma list, ignoring commas inside links, parentheses, braces and quotes.
    /// </summary>
    /// <param name="text">The list.</param>
    /// <returns>The trimmed, non-empty items.</returns>
    public static List<string> SplitList(string text)
    {
        List<string> items = [];
        int depth = 0;
        int start = 0;
        char quote = '\0';
        for (int index = 0; index < text.Length; index++)
        {
            char character = text[index];
            if (quote != '\0')
            {
                if (character == quote) { quote = '\0'; }
                continue;
            }

            switch (character)
            {
                case '"':
                case '`':
                    quote = character;
                    break;
                case '<':
                case '(':
                case '{':
                case '[':
                    depth++;
                    break;
                case '>':
                case ')':
                case '}':
                case ']':
                    depth = Math.Max(0, depth - 1);
                    break;
                case ',' when depth == 0:
                    Add(items, text[start..index]);
                    start = index + 1;
                    break;
            }
        }

        Add(items, text[start..]);
        return items;
    }

    private static void Add(List<string> items, string item)
    {
        item = item.Trim();
        if (item.Length != 0) { items.Add(item); }
    }

    private static bool StartsUrl(string text, int index) =>
        string.Compare(text, index, "http://", 0, 7, StringComparison.OrdinalIgnoreCase) == 0
            || string.Compare(text, index, "https://", 0, 8, StringComparison.OrdinalIgnoreCase) == 0;

    private static bool IsName(string name)
    {
        foreach (char character in name)
        {
            if (!char.IsLetterOrDigit(character) && character is not ('_' or '@' or '.' or ':')) { return false; }
        }

        return true;
    }
}
