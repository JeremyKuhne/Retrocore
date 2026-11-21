// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Documentation;

/// <summary>
///  One item of an <c>Also:</c> section: a historical name the definition had, and the documents that give it,
///  as in <c>COUT (A2RM)</c>.
/// </summary>
/// <param name="Name">The historical name.</param>
/// <param name="Sources">The bibliography keys of the documents that use the name.</param>
public sealed record DocumentationAlso(string Name, IReadOnlyList<string> Sources)
{
    /// <summary>
    ///  Reads an <c>Also:</c> item.
    /// </summary>
    /// <param name="item">The item, such as <c>COUT (A2RM, IIETR)</c>.</param>
    /// <returns>The name and its sources, or null for an item not in the form NAME (KEY, ...).</returns>
    public static DocumentationAlso? Parse(string item)
    {
        string text = item.Trim();
        int open = text.IndexOf('(');
        string name = (open < 0 ? text : text[..open]).Trim();
        if (name.Length == 0 || !IsName(name)) { return null; }
        if (open < 0) { return new(name, []); }

        // The documents' keys end the item: an unclosed list, or text after it, is not an item.
        int close = text.LastIndexOf(')');
        if (close != text.Length - 1 || close < open) { return null; }
        string inside = text[(open + 1)..close];
        string[] sources = [.. inside.Split(',').Select(source => source.Trim()).Where(source => source.Length != 0)];
        return new(name, sources);
    }

    /// <summary>
    ///  Reads every item of a definition's <c>Also:</c> sections.
    /// </summary>
    /// <param name="sections">The definition's sections, from its comment or its topic.</param>
    /// <returns>The historical names, in source order.</returns>
    public static IEnumerable<DocumentationAlso> Of(IEnumerable<DocumentationSection> sections) =>
        sections
            .Where(section => section.Name == "Also")
            .SelectMany(section => section.Items)
            .Select(Parse)
            .OfType<DocumentationAlso>();

    private static bool IsName(string name)
    {
        if (!(char.IsAsciiLetter(name[0]) || name[0] == '_')) { return false; }
        foreach (char character in name)
        {
            if (!(char.IsAsciiLetterOrDigit(character) || character == '_')) { return false; }
        }

        return true;
    }
}
