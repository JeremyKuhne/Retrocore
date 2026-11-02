// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.Json.Nodes;

namespace Retrocore.Debug.Language;

/// <summary>
///  A place in a document: a zero-based line, and a zero-based column counted in UTF-16 code units, as LSP counts.
/// </summary>
/// <param name="Line">The line.</param>
/// <param name="Character">The column.</param>
internal sealed record Position(int Line, int Character)
{
    /// <summary>
    ///  Reads a position.
    /// </summary>
    /// <param name="node">The position's JSON, or null.</param>
    /// <returns>The position; the document's start when there is none.</returns>
    public static Position From(JsonNode? node) => new(node.Int("line") ?? 0, node.Int("character") ?? 0);

    /// <summary>
    ///  Writes the position.
    /// </summary>
    /// <returns>Its JSON.</returns>
    public JsonObject ToJson() => new() { ["line"] = Line, ["character"] = Character };
}
