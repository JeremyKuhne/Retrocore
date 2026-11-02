// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Documentation;

/// <summary>
///  The documentation of one definition: its comments, merged across <c>.if</c> branches, with facts from the
///  assembly.
/// </summary>
public sealed class DocumentationTopic
{
    /// <summary>
    ///  Gets the documented name.
    /// </summary>
    public required string Name { get; init; }

    /// <summary>
    ///  Gets what is documented.
    /// </summary>
    public required DocumentationKind Kind { get; init; }

    /// <summary>
    ///  Gets the set the topic belongs to.
    /// </summary>
    public required DocumentationSet Set { get; init; }

    /// <summary>
    ///  Gets the comments, one per <c>.if</c> branch that documents the definition.
    /// </summary>
    public required IReadOnlyList<DocumentationComment> Comments { get; init; }

    /// <summary>
    ///  Gets the summary.
    /// </summary>
    public string Summary { get; init; } = "";

    /// <summary>
    ///  Gets the remarks, one entry per line, with empty entries between paragraphs.
    /// </summary>
    public IReadOnlyList<string> Remarks { get; init; } = [];

    /// <summary>
    ///  Gets the sections. Sections that differ between <c>.if</c> branches appear once per branch, each with its
    ///  <see cref="DocumentationSection.Condition"/>.
    /// </summary>
    public IReadOnlyList<DocumentationSection> Sections { get; init; } = [];

    /// <summary>
    ///  Gets the value: a label's address or a constant's value, when the assembly defines it.
    /// </summary>
    public long? Value { get; init; }

    /// <summary>
    ///  Gets the topic documentation was inherited from, after <c>DocumentationResolver.Effective</c>.
    /// </summary>
    public DocumentationTopic? InheritedFrom { get; init; }

    /// <summary>
    ///  Gets the first comment, which locates the topic.
    /// </summary>
    public DocumentationComment Primary => Comments[0];

    /// <summary>
    ///  Gets the source path.
    /// </summary>
    public string Path => Primary.Path;

    /// <summary>
    ///  Gets the zero-based line of the definition.
    /// </summary>
    public int Line => Primary.TargetLine;

    /// <summary>
    ///  Gets the condition the definition is under, when every comment shares it; otherwise null.
    /// </summary>
    public string? Condition => Comments.Count == 1 ? Primary.Condition : null;

    /// <summary>
    ///  Gets a section by its canonical name.
    /// </summary>
    /// <param name="name">The name, such as <c>Keeps</c>.</param>
    /// <returns>The first such section, or null.</returns>
    public DocumentationSection? Section(string name) =>
        Sections.FirstOrDefault(section => section.Name.Equals(name, StringComparison.OrdinalIgnoreCase));

    /// <summary>
    ///  Gets every section with a name, one per <c>.if</c> branch.
    /// </summary>
    /// <param name="name">The name, such as <c>Keeps</c>.</param>
    /// <returns>The sections.</returns>
    public IEnumerable<DocumentationSection> SectionsNamed(string name) =>
        Sections.Where(section => section.Name.Equals(name, StringComparison.OrdinalIgnoreCase));

    /// <summary>
    ///  Gets the labels listed as other ways into the routine: stacked labels and <c>Entry:</c> entries.
    /// </summary>
    public IEnumerable<string> EntryLabels =>
        Comments.SelectMany(comment => comment.Aliases)
            .Concat(SectionsNamed("Entry").SelectMany(section => section.Entries.Select(entry => entry.Name)))
            .Distinct(StringComparer.Ordinal);
}
