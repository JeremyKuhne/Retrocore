// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.Json.Nodes;

namespace Retrocore.Debug.Language;

/// <summary>
///  What a hover shows, and the range it is about.
/// </summary>
internal sealed class Hover
{
    /// <summary>
    ///  Gets the text.
    /// </summary>
    public required MarkupContent Contents { get; init; }

    /// <summary>
    ///  Gets the range the hover is about, or null for the word under the cursor.
    /// </summary>
    public LspRange? Range { get; init; }

    /// <summary>
    ///  Writes the hover.
    /// </summary>
    /// <returns>Its JSON.</returns>
    public JsonObject ToJson() => new() { ["contents"] = Contents.ToJson(), ["range"] = Range?.ToJson() };
}
