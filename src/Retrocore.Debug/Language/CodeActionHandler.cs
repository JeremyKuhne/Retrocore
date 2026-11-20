// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.Json.Nodes;

namespace Retrocore.Debug.Language;

/// <summary>
///  Answers <c>textDocument/codeAction</c>: quick fixes for the diagnostics the client sends back.
/// </summary>
internal static class CodeActionHandler
{
    /// <summary>
    ///  Gets the quick fixes for a request: for each use of a historical name, one that writes the current name.
    /// </summary>
    /// <param name="parameters">The request's params: the document, the range and the diagnostics there.</param>
    /// <returns>The code actions.</returns>
    internal static JsonNode? Handle(JsonObject? parameters)
    {
        JsonArray actions = [];
        if (parameters?["textDocument"]?["uri"]?.GetValue<string>() is not { } uri) { return actions; }
        if (parameters["context"]?["diagnostics"] is not JsonArray diagnostics) { return actions; }
        foreach (JsonNode? node in diagnostics)
        {
            if (node is not JsonObject diagnostic
                || diagnostic["code"]?.GetValue<string>() != LanguageWorkspace.HistoricalNameCode
                || diagnostic["data"]?["replacement"]?.GetValue<string>() is not { } replacement
                || diagnostic["range"] is not JsonObject range)
            {
                continue;
            }

            JsonObject edit = new() { ["range"] = range.DeepClone(), ["newText"] = replacement };
            JsonObject changes = new() { [uri] = new JsonArray(edit) };
            JsonObject action = new()
            {
                ["title"] = $"Use {replacement}",
                ["kind"] = "quickfix",
                ["isPreferred"] = true,
                ["diagnostics"] = new JsonArray(diagnostic.DeepClone()),
                ["edit"] = new JsonObject { ["changes"] = changes }
            };

            actions.Add((JsonNode)action);
        }

        return actions;
    }
}
