// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.Json.Nodes;

namespace Retrocore.Debug.Language;

/// <summary>
///  A symbol in a document's outline, with the symbols under it.
/// </summary>
internal sealed class DocumentSymbol
{
    /// <summary>
    ///  Gets the name.
    /// </summary>
    public required string Name { get; init; }

    /// <summary>
    ///  Gets the detail shown beside it, or null.
    /// </summary>
    public string? Detail { get; init; }

    /// <summary>
    ///  Gets what it is.
    /// </summary>
    public SymbolKind Kind { get; init; }

    /// <summary>
    ///  Gets everything it spans.
    /// </summary>
    public required LspRange Range { get; init; }

    /// <summary>
    ///  Gets what the outline selects for it, such as its name.
    /// </summary>
    public required LspRange SelectionRange { get; init; }

    /// <summary>
    ///  Gets the symbols under it, or null.
    /// </summary>
    public IReadOnlyList<DocumentSymbol>? Children { get; init; }

    /// <summary>
    ///  Writes the symbol and its children.
    /// </summary>
    /// <returns>Its JSON.</returns>
    public JsonObject ToJson()
    {
        JsonObject symbol = new()
        {
            ["name"] = Name,
            ["kind"] = (int)Kind,
            ["range"] = Range.ToJson(),
            ["selectionRange"] = SelectionRange.ToJson()
        };

        if (Detail is not null) { symbol["detail"] = Detail; }
        if (Children is not null)
        {
            symbol["children"] = Children.Select(child => (JsonNode?)child.ToJson()).ToJsonArray();
        }

        return symbol;
    }
}
