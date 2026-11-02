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
    ///  Writes the completion.
    /// </summary>
    /// <returns>Its JSON, without the properties it lacks.</returns>
    public JsonObject ToJson()
    {
        JsonObject item = new() { ["label"] = Label, ["kind"] = (int)Kind };
        if (Detail is not null) { item["detail"] = Detail; }
        if (Documentation is not null) { item["documentation"] = Documentation.ToJson(); }
        if (SortText is not null) { item["sortText"] = SortText; }
        return item;
    }
}
