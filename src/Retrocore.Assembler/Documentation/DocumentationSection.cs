// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Documentation;

/// <summary>
///  A section of a documentation comment, such as <c>In:</c> or <c>Keeps:</c>.
/// </summary>
public sealed class DocumentationSection
{
    /// <summary>
    ///  Creates a section.
    /// </summary>
    /// <param name="name">The canonical name for a recognized section, or the heading as written.</param>
    /// <param name="line">The zero-based line of its heading.</param>
    /// <param name="lines">Its content lines, without the heading.</param>
    /// <param name="entries">Its entries, for entry sections.</param>
    /// <param name="items">Its items, for list sections.</param>
    public DocumentationSection(
        string name,
        int line,
        IReadOnlyList<string> lines,
        IReadOnlyList<DocumentationEntry> entries,
        IReadOnlyList<string> items)
    {
        Name = name;
        Line = line;
        Lines = lines;
        Entries = entries;
        Items = items;
    }

    /// <summary>
    ///  Gets the section's name: <c>In</c>, <c>Keeps</c> and so on, or a plain heading's text.
    /// </summary>
    public string Name { get; }

    /// <summary>
    ///  Gets the zero-based line of the heading.
    /// </summary>
    public int Line { get; }

    /// <summary>
    ///  Gets the content, one entry per source line, with a compact section's content as the first line.
    /// </summary>
    public IReadOnlyList<string> Lines { get; }

    /// <summary>
    ///  Gets the entries of an entry section (<c>In</c>, <c>Out</c>, <c>Flags</c>, <c>Errors</c>, <c>Entry</c>,
    ///  <c>Parameters</c>, <c>Members</c>).
    /// </summary>
    public IReadOnlyList<DocumentationEntry> Entries { get; }

    /// <summary>
    ///  Gets the items of a list section (<c>Uses</c>, <c>Keeps</c>, <c>See</c>, <c>Calls</c>, and the section
    ///  names after an <c>Inherit</c> target).
    /// </summary>
    public IReadOnlyList<string> Items { get; }

    /// <summary>
    ///  Gets the condition under which the section applies, when topics from several branches of an
    ///  <c>.if</c> were merged; otherwise null.
    /// </summary>
    public string? Condition { get; init; }

    /// <summary>
    ///  Gets whether this is a section the format defines, rather than a plain heading.
    /// </summary>
    public bool IsKnown => DocumentationSections.IsKnown(Name);

    /// <summary>
    ///  Gets the content as one line of text.
    /// </summary>
    public string Text => string.Join(" ", Lines.Select(line => line.Trim()).Where(line => line.Length != 0));

    /// <summary>
    ///  Copies the section with a condition.
    /// </summary>
    /// <param name="condition">The condition.</param>
    /// <returns>The copy.</returns>
    public DocumentationSection WithCondition(string? condition) =>
        new(Name, Line, Lines, Entries, Items) { Condition = condition };
}
