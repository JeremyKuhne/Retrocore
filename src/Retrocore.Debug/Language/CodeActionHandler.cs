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
    private readonly BasicDocuments _basic;
    private readonly PascalDocuments? _pascal;

    /// <summary>
    ///  Creates the handler.
    /// </summary>
    /// <param name="workspace">The workspace, for the document's lines.</param>
    /// <param name="basic">The open BASIC documents, which have no assembly quick fixes.</param>
    /// <param name="pascal">The open Pascal documents, which have none either; or null for none.</param>
    public CodeActionHandler(LanguageWorkspace workspace, BasicDocuments basic, PascalDocuments? pascal = null)
    {
        _workspace = workspace;
        _basic = basic;
        _pascal = pascal;
    }

    /// <summary>
    ///  Gets the quick fixes for a request (see <see cref="LintEditor.Actions"/>).
    /// </summary>
    /// <param name="parameters">The request's params: the document, the range and the diagnostics there.</param>
    /// <returns>The code actions.</returns>
    internal JsonNode? Handle(JsonObject? parameters)
    {
        if (parameters?["textDocument"]?["uri"]?.GetValue<string>() is not { } uri) { return new JsonArray(); }
        if (parameters["context"]?["diagnostics"] is not JsonArray diagnostics) { return new JsonArray(); }

        // A BASIC or Pascal document, or one that is not a file (such as a machine's program), has no assembly lint to
        // fix: the assembly's exclusions are not Pascal.
        DocumentUri document = new(uri);
        if (_basic.Get(document) is not null || _pascal?.IsOpen(document) is true || !Uri.TryCreate(uri, UriKind.Absolute, out Uri? parsed) || !parsed.IsFile)
        {
            return new JsonArray();
        }

        return LintEditor.Actions(uri, _workspace.LinesOf(LanguageHost.PathOf(document)), diagnostics);
    }
}
