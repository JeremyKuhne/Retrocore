// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.Json.Nodes;

namespace Retrocore.Debug.Language;

/// <summary>
///  One completion.
/// </summary>
internal sealed class CompletionItem
{
    /// <summary>
    ///  Gets the text the completion inserts and shows.
    /// </summary>
    public required string Label { get; init; }

    /// <summary>
    ///  Gets what it completes.
    /// </summary>
    public CompletionItemKind Kind { get; init; }

    /// <summary>
    ///  Gets the short detail shown beside it, or null.
    /// </summary>
    public string? Detail { get; init; }

    /// <summary>
    ///  Gets its documentation, or null.
    /// </summary>
    public MarkupContent? Documentation { get; init; }

    /// <summary>
    ///  Gets the text it sorts by, instead of its label, or null.
    /// </summary>
    public string? SortText { get; init; }

    /// <summary>
    ///  Gets the text the client filters on, when it differs from the label: the name and its historical names.
    /// </summary>
    public string? FilterText { get; init; }

    /// <summary>
    ///  Gets the range the item replaces, for text the editor's words don't cover, such as a hyphenated rule ID.
    /// </summary>
    public LspRange? Range { get; init; }

    /// <summary>
    ///  Writes the completion.
    /// </summary>
    /// <returns>Its JSON, without the properties it lacks.</returns>
    public JsonObject ToJson()
    {
        JsonObject item = new() { ["label"] = Label, ["kind"] = (int)Kind };
        if (Detail is not null) { item["detail"] = Detail; }
        if (Documentation is not null) { item["documentation"] = Documentation.ToJson(); }
        if (SortText is not null) { item["sortText"] = SortText; }
        if (FilterText is not null) { item["filterText"] = FilterText; }
        if (Range is not null)
        {
            item["textEdit"] = new JsonObject { ["range"] = Range.ToJson(), ["newText"] = Label };
        }

        return item;
    }
}
