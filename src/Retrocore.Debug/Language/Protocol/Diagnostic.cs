// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.Json.Nodes;

namespace Retrocore.Debug.Language;

/// <summary>
///  A problem in a document, for the Problems view.
/// </summary>
internal sealed class Diagnostic
{
    /// <summary>
    ///  Gets where it is.
    /// </summary>
    public required LspRange Range { get; init; }

    /// <summary>
    ///  Gets how serious it is.
    /// </summary>
    public DiagnosticSeverity Severity { get; init; }

    /// <summary>
    ///  Gets its code, or null.
    /// </summary>
    public string? Code { get; init; }

    /// <summary>
    ///  Gets what reports it, such as <c>retrocore</c>.
    /// </summary>
    public string? Source { get; init; }

    /// <summary>
    ///  Gets what is wrong.
    /// </summary>
    public required string Message { get; init; }

    /// <summary>
    ///  Gets the other places it concerns, or null.
    /// </summary>
    public IReadOnlyList<DiagnosticRelatedInformation>? RelatedInformation { get; init; }

    /// <summary>
    ///  Writes the diagnostic.
    /// </summary>
    /// <returns>Its JSON, without the properties it lacks.</returns>
    public JsonObject ToJson()
    {
        JsonObject diagnostic = new()
        {
            ["range"] = Range.ToJson(),
            ["severity"] = (int)Severity,
            ["message"] = Message
        };

        if (Code is not null) { diagnostic["code"] = Code; }
        if (Source is not null) { diagnostic["source"] = Source; }
        if (RelatedInformation is not null)
        {
            diagnostic["relatedInformation"] = RelatedInformation.Select(item => (JsonNode?)item.ToJson()).ToJsonArray();
        }

        return diagnostic;
    }
}
