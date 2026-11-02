// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Documentation;

/// <summary>
///  The sections the documentation format defines, and how each is parsed.
/// </summary>
public static class DocumentationSections
{
    private static readonly string[] s_entries = ["In", "Out", "Flags", "Errors", "Entry", "Parameters", "Members"];
    private static readonly string[] s_lists = ["Uses", "Keeps", "See", "Calls"];
    private static readonly string[] s_text = ["Cycles", "Stack", "Model", "Inherit", "Include"];
    private static readonly string[] s_free = ["Example", "Deprecated"];

    /// <summary>
    ///  Gets the canonical name of a recognized section heading, such as <c>See</c> for <c>See also</c>.
    /// </summary>
    /// <param name="heading">The heading without its colon.</param>
    /// <returns>The canonical name, or null when the format does not define it.</returns>
    public static string? Canonical(string heading)
    {
        if (heading.Equals("See also", StringComparison.OrdinalIgnoreCase)) { return "See"; }
        foreach (string[] names in (string[][])[s_entries, s_lists, s_text, s_free])
        {
            foreach (string name in names)
            {
                if (name.Equals(heading, StringComparison.OrdinalIgnoreCase)) { return name; }
            }
        }

        return null;
    }

    /// <summary>
    ///  Gets whether the format defines a section.
    /// </summary>
    /// <param name="name">The canonical name.</param>
    /// <returns>Whether it is recognized.</returns>
    public static bool IsKnown(string name) => Canonical(name) is not null;

    /// <summary>
    ///  Gets whether a section holds <c>name = meaning</c> entries.
    /// </summary>
    /// <param name="name">The canonical name.</param>
    /// <returns>Whether it is an entry section.</returns>
    public static bool IsEntries(string name) => Array.IndexOf(s_entries, name) >= 0;

    /// <summary>
    ///  Gets whether a section holds a comma list.
    /// </summary>
    /// <param name="name">The canonical name.</param>
    /// <returns>Whether it is a list section.</returns>
    public static bool IsList(string name) => Array.IndexOf(s_lists, name) >= 0;

    /// <summary>
    ///  Gets whether a section is free text that runs to the next recognized section, including unindented
    ///  lines and paragraphs.
    /// </summary>
    /// <param name="name">The canonical name, or a plain heading.</param>
    /// <returns>Whether it is free text.</returns>
    public static bool IsFreeText(string name) => Array.IndexOf(s_free, name) >= 0 || !IsKnown(name);
}
