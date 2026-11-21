// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.Json.Nodes;

namespace Retrocore.Debug.Language;

/// <summary>
///  Answers <c>textDocument/codeAction</c>: quick fixes for the diagnostics the client sends back.
/// </summary>
internal sealed class CodeActionHandler
{
    private readonly LanguageWorkspace _workspace;

    /// <summary>
    ///  Creates the handler.
    /// </summary>
    /// <param name="workspace">The workspace, for the document's lines.</param>
    public CodeActionHandler(LanguageWorkspace workspace) => _workspace = workspace;

    /// <summary>
    ///  Gets the quick fixes for a request (see <see cref="LintEditor.Actions"/>).
    /// </summary>
    /// <param name="parameters">The request's params: the document, the range and the diagnostics there.</param>
    /// <returns>The code actions.</returns>
    internal JsonNode? Handle(JsonObject? parameters)
    {
        if (parameters?["textDocument"]?["uri"]?.GetValue<string>() is not { } uri) { return new JsonArray(); }
        if (parameters["context"]?["diagnostics"] is not JsonArray diagnostics) { return new JsonArray(); }
        return LintEditor.Actions(uri, _workspace.LinesOf(LanguageHost.PathOf(new DocumentUri(uri))), diagnostics);
    }
}
