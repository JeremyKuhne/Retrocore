// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.Json.Nodes;

namespace Retrocore.Debug.Language;

/// <summary>
///  Another place a problem concerns, such as the macro invocation it was expanded from.
/// </summary>
internal sealed class DiagnosticRelatedInformation
{
    /// <summary>
    ///  Gets the place.
    /// </summary>
    public required LspLocation Location { get; init; }

    /// <summary>
    ///  Gets what it has to do with the problem.
    /// </summary>
    public required string Message { get; init; }

    /// <summary>
    ///  Writes the information.
    /// </summary>
    /// <returns>Its JSON.</returns>
    public JsonObject ToJson() => new() { ["location"] = Location.ToJson(), ["message"] = Message };
}
