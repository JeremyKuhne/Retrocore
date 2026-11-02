// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.Json.Nodes;

namespace Retrocore.Debug.Language;

/// <summary>
///  The parts of a request's or notification's params the handlers read, under the names LSP gives them.
/// </summary>
/// <param name="TextDocument">The document the request is about.</param>
/// <param name="Position">The cursor, for requests about a place.</param>
/// <param name="Context">What References should include.</param>
/// <param name="Query">What Go to Symbol in Workspace searches for.</param>
/// <param name="ContentChanges">
///  The texts a change notification carries; with full sync, the last is the whole text.
/// </param>
internal sealed record LspParams(
    TextDocumentItem TextDocument,
    Position Position,
    ReferenceContext Context,
    string Query,
    IReadOnlyList<string> ContentChanges)
{
    /// <summary>
    ///  Reads the params.
    /// </summary>
    /// <param name="parameters">The params, or null.</param>
    /// <returns>The parts; empty where a part is missing.</returns>
    public static LspParams From(JsonObject? parameters)
    {
        JsonObject? document = parameters.Object("textDocument");
        TextDocumentItem item = new(
            new DocumentUri(document.String("uri") ?? ""),
            document.String("languageId") ?? "",
            document.String("text") ?? "");

        List<string> changes = [];
        foreach (JsonNode? change in parameters.Array("contentChanges") ?? [])
        {
            if (change.String("text") is { } text) { changes.Add(text); }
        }

        return new(
            item,
            Position.From(parameters?["position"]),
            new ReferenceContext(parameters.Object("context").Bool("includeDeclaration") ?? false),
            parameters.String("query") ?? "",
            changes);
    }
}
