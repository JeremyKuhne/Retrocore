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
    ///  Gets data the client sends back with a code action request, such as a historical name's replacement.
    /// </summary>
    public JsonObject? Data { get; init; }

    /// <summary>
    ///  Gets whether the diagnostic marks code that is not needed, which an editor fades.
    /// </summary>
    public bool IsUnnecessary { get; init; }

    /// <summary>
    ///  Makes an information diagnostic that marks its code as unnecessary.
    /// </summary>
    /// <returns>The diagnostic.</returns>
    public Diagnostic Unnecessary() => new()
    {
        Range = Range,
        Severity = DiagnosticSeverity.Information,
        Code = Code,
        Source = Source,
        Message = Message,
        RelatedInformation = RelatedInformation,
        Data = Data,
        IsUnnecessary = true
    };

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
        if (Data is not null) { diagnostic["data"] = Data.DeepClone(); }

        // DiagnosticTag.Unnecessary.
        if (IsUnnecessary) { diagnostic["tags"] = new JsonArray(1); }
        if (RelatedInformation is not null)
        {
            diagnostic["relatedInformation"] = RelatedInformation.Select(item => (JsonNode?)item.ToJson()).ToJsonArray();
        }

        return diagnostic;
    }
}
