// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.Json.Nodes;

namespace Retrocore.Debug.Language;

/// <summary>
///  Text for a hover or a completion's documentation, plain or Markdown.
/// </summary>
internal sealed class MarkupContent
{
    /// <summary>
    ///  Gets how the text renders.
    /// </summary>
    public MarkupKind Kind { get; init; }

    /// <summary>
    ///  Gets the text.
    /// </summary>
    public required string Value { get; init; }

    /// <summary>
    ///  Writes the content.
    /// </summary>
    /// <returns>Its JSON.</returns>
    public JsonObject ToJson() => new()
    {
        ["kind"] = Kind == MarkupKind.Markdown ? "markdown" : "plaintext",
        ["value"] = Value
    };
}
