// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.Json.Nodes;

namespace Retrocore.Debug.Language;

/// <summary>
///  A range in a document.
/// </summary>
internal sealed class LspLocation
{
    /// <summary>
    ///  Gets the document.
    /// </summary>
    public required DocumentUri Uri { get; init; }

    /// <summary>
    ///  Gets the range.
    /// </summary>
    public required LspRange Range { get; init; }

    /// <summary>
    ///  Writes the location.
    /// </summary>
    /// <returns>Its JSON.</returns>
    public JsonObject ToJson() => new() { ["uri"] = Uri.Text, ["range"] = Range.ToJson() };
}
