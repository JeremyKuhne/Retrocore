// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Documentation;

/// <summary>
///  One <c>;;</c> documentation comment and the definition it documents.
/// </summary>
public sealed class DocumentationComment
{
    /// <summary>
    ///  Gets the source path.
    /// </summary>
    public required string Path { get; init; }

    /// <summary>
    ///  Gets the zero-based line where the comment starts.
    /// </summary>
    public required int Line { get; init; }

    /// <summary>
    ///  Gets the zero-based line of the definition it documents (its own line for a trailing comment and for a
    ///  free-standing topic).
    /// </summary>
    public required int TargetLine { get; init; }

    /// <summary>
    ///  Gets the documented name: the label, constant, macro or member, or a free-standing topic's title. A
    ///  member is qualified by its enumeration or structure (<c>AM::IMP</c>), and a file topic is named after
    ///  the file.
    /// </summary>
    public required string Name { get; init; }

    /// <summary>
    ///  Gets what is documented.
    /// </summary>
    public required DocumentationKind Kind { get; init; }

    /// <summary>
    ///  Gets a free-standing topic's keyword, such as <c>Group</c>; otherwise null.
    /// </summary>
    public string? Keyword { get; init; }

    /// <summary>
    ///  Gets the summary: the first sentence or paragraph.
    /// </summary>
    public string Summary { get; init; } = "";

    /// <summary>
    ///  Gets the remarks, one entry per source line, with empty entries between paragraphs.
    /// </summary>
    public IReadOnlyList<string> Remarks { get; init; } = [];

    /// <summary>
    ///  Gets the sections in source order.
    /// </summary>
    public IReadOnlyList<DocumentationSection> Sections { get; init; } = [];

    /// <summary>
    ///  Gets labels that directly follow the documented label and share its comment.
    /// </summary>
    public IReadOnlyList<string> Aliases { get; init; } = [];

    /// <summary>
    ///  Gets the macro or <c>.define</c> parameters declared by the definition.
    /// </summary>
    public IReadOnlyList<string> Parameters { get; init; } = [];

    /// <summary>
    ///  Gets the members of a documented enumeration or structure.
    /// </summary>
    public IReadOnlyList<string> Members { get; init; } = [];

    /// <summary>
    ///  Gets the <c>.if</c> conditions the definition is under, such as <c>ENHANCED</c> or <c>not ENHANCED</c>,
    ///  joined by <c>and</c>; null outside conditional code.
    /// </summary>
    public string? Condition { get; init; }

    /// <summary>
    ///  Gets whether the comment trails its definition on the same line.
    /// </summary>
    public bool IsTrailing { get; init; }

    /// <summary>
    ///  Gets a section by its canonical name.
    /// </summary>
    /// <param name="name">The name, such as <c>Keeps</c>.</param>
    /// <returns>The first such section, or null.</returns>
    public DocumentationSection? Section(string name) =>
        Sections.FirstOrDefault(section => section.Name.Equals(name, StringComparison.OrdinalIgnoreCase));
}
