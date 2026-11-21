// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Documentation;

/// <summary>
///  The lint's rules, by ID (docs/DocComments.md, section 5). The IDs are a public contract: a rule may be split,
///  with the old ID still covering both, but not renamed.
/// </summary>
public static class DocumentationRules
{
    /// <summary>
    ///  A line over the style guide's width.
    /// </summary>
    public const string LineLength = "line-length";

    /// <summary>
    ///  A character outside plain ASCII.
    /// </summary>
    public const string Ascii = "ascii";

    /// <summary>
    ///  A trailing <c>;;</c> comment in a file that follows the style guide.
    /// </summary>
    public const string TrailingDoc = "trailing-doc";

    /// <summary>
    ///  A label with code after it on the same line.
    /// </summary>
    public const string LabelAlone = "label-alone";

    /// <summary>
    ///  A name that is only an address.
    /// </summary>
    public const string AddressName = "address-name";

    /// <summary>
    ///  A definition, label or block directive that is not at column 0.
    /// </summary>
    public const string ColumnZero = "column-zero";

    /// <summary>
    ///  An instruction, data or macro line at the wrong indentation.
    /// </summary>
    public const string Indent = "indent";

    /// <summary>
    ///  A comment line not indented like the code it describes.
    /// </summary>
    public const string CommentIndent = "comment-indent";

    /// <summary>
    ///  A documented definition that prose names without a link.
    /// </summary>
    public const string UnlinkedName = "unlinked-name";

    /// <summary>
    ///  A link to nothing.
    /// </summary>
    public const string Link = "link";

    /// <summary>
    ///  A link that names definitions in more than one place.
    /// </summary>
    public const string AmbiguousLink = "ambiguous-link";

    /// <summary>
    ///  An <c>Also:</c> section's form, documents or clashes.
    /// </summary>
    public const string Also = "also";

    /// <summary>
    ///  The form of a topic's sections, entries and <c>{name}</c> references.
    /// </summary>
    public const string Sections = "sections";

    /// <summary>
    ///  A use of a historical name in code.
    /// </summary>
    public const string HistoricalName = "historical-name";

    /// <summary>
    ///  A use of a deprecated definition.
    /// </summary>
    public const string Deprecated = "deprecated";

    /// <summary>
    ///  An exported name without documentation.
    /// </summary>
    public const string UndocumentedExport = "undocumented-export";

    /// <summary>
    ///  A <c>;;</c> comment that documents nothing it can: errors only.
    /// </summary>
    public const string Placement = "placement";

    /// <summary>
    ///  A problem with an exclusion itself, which an exclusion cannot turn off.
    /// </summary>
    public const string Exclusion = "exclusion";

    /// <summary>
    ///  Gets every rule, in the order the documentation lists them.
    /// </summary>
    public static IReadOnlyList<DocumentationRule> All { get; } =
    [
        new(LineLength, "A line is at most 120 columns.", TakesNames: false, Ignorable: true),
        new(Ascii, "Comments and strings are plain ASCII: 'times' rather than a multiplication sign, '-' rather than a dash.", TakesNames: false, Ignorable: true),
        new(TrailingDoc, "`;;` documentation goes above the definition, not after it.", TakesNames: false, Ignorable: true),
        new(LabelAlone, "A label is on its own line. Narrow it to labels: `label-alone:Loop`.", TakesNames: true, Ignorable: true),
        new(AddressName, "A definition is named for what it is, not for its address (`L_F8C2`). Narrow it to names: `address-name:L_F8C2`.", TakesNames: true, Ignorable: true),
        new(ColumnZero, "Definitions, labels and block directives are at column 0.", TakesNames: false, Ignorable: true),
        new(Indent, "Instructions and data are indented 4 columns, and a macro's body one level per block.", TakesNames: false, Ignorable: true),
        new(CommentIndent, "A comment line is indented like the code it describes.", TakesNames: false, Ignorable: true),
        new(UnlinkedName, "Prose that names a documented definition links it as `<Name>`. Narrow it to names: `unlinked-name:Run`.", TakesNames: true, Ignorable: true),
        new(Link, "A `<link>` names a definition, file or address. Narrow it to targets: `link:Name`.", TakesNames: true, Ignorable: true),
        new(AmbiguousLink, "A `<link>` names one definition; qualify one that several modules or models define. Narrow it to targets: `ambiguous-link:Name`.", TakesNames: true, Ignorable: true),
        new(Also, "An `Also:` section gives each historical name with the documents it comes from, and the name is not taken.", TakesNames: false, Ignorable: true),
        new(Sections, "The sections' form: `Entry:`, `Members:`, `Parameters:`, `Inherit:`, `Include:`, `Flags:`, register lists, `name = meaning` entries and `{name}` references.", TakesNames: false, Ignorable: true),
        new(HistoricalName, "Code uses a definition's current name, not a historical one from its `Also:` section. Narrow it to names: `historical-name:COUT`.", TakesNames: true, Ignorable: true),
        new(Deprecated, "Code does not use a definition with a `Deprecated:` section. Narrow it to names: `deprecated:Name`.", TakesNames: true, Ignorable: true),
        new(UndocumentedExport, "An exported name has `;;` documentation.", TakesNames: false, Ignorable: true),
        new(Placement, "A `;;` comment documents a definition directly below it. Its errors can't be ignored.", TakesNames: false, Ignorable: false),
        new(Exclusion, "An `ignore=` exclusion names known rules and turns something off. Its diagnostics can't be ignored.", TakesNames: false, Ignorable: false)
    ];

    private static readonly Dictionary<string, DocumentationRule> s_byId = All.ToDictionary(rule => rule.Id, StringComparer.Ordinal);

    /// <summary>
    ///  Finds a rule by its ID.
    /// </summary>
    /// <param name="id">The ID.</param>
    /// <returns>The rule, or null when no rule has that ID.</returns>
    public static DocumentationRule? Find(string id) => s_byId.TryGetValue(id, out DocumentationRule? rule) ? rule : null;
}
