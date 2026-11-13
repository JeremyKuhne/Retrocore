// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Globalization;
using System.Text.Json.Nodes;

namespace Retrocore.Debug.Language;

/// <summary>
///  Runs the retrocore language server over standard input and output, and holds what its handlers share.
/// </summary>
internal static class LanguageHost
{
    /// <summary>
    ///  The VS Code language the server serves.
    /// </summary>
    internal const string LanguageId = "retrocore-asm";

    /// <summary>
    ///  The VS Code language of MACRO-10 sources (<c>.mac</c>), served as assembly; a language of their own gives
    ///  them their own icon.
    /// </summary>
    internal const string Macro10Id = "retrocore-macro10";

    /// <summary>
    ///  The VS Code language of AppleSoft documents.
    /// </summary>
    internal const string AppleSoftId = "retrocore-applesoft";

    /// <summary>
    ///  The VS Code language of Level II BASIC documents.
    /// </summary>
    internal const string Level2Id = "retrocore-level2";

    /// <summary>
    ///  The VS Code language of Integer BASIC documents.
    /// </summary>
    internal const string IntegerId = "retrocore-integer";

    /// <summary>
    ///  The VS Code language of Business BASIC documents.
    /// </summary>
    internal const string BusinessId = "retrocore-business";

    /// <summary>
    ///  The VS Code language of Apple-1 BASIC documents.
    /// </summary>
    internal const string Apple1Id = "retrocore-apple1";

    /// <summary>
    ///  The VS Code language of Level I BASIC documents.
    /// </summary>
    internal const string Level1Id = "retrocore-level1";

    /// <summary>
    ///  The VS Code language of a BASIC document whose pragma or file name gives its dialect.
    /// </summary>
    internal const string BasicId = "retrocore-basic";

    private const int ByteMaximum = 0xFF;
    private const int WordMaximum = 0xFFFF;

    /// <summary>
    ///  Tests whether a language is one of the BASIC languages.
    /// </summary>
    /// <param name="languageId">The language.</param>
    /// <returns>Whether it is BASIC.</returns>
    internal static bool IsBasic(string languageId) =>
        languageId is AppleSoftId or Level2Id or IntegerId or Apple1Id or BusinessId or Level1Id or BasicId;

    /// <summary>
    ///  Serves until the client disconnects.
    /// </summary>
    /// <returns>The task.</returns>
    internal static async Task Run()
    {
        JsonRpcServer server = new(Console.OpenStandardInput(), Console.OpenStandardOutput());
        LanguageWorkspace workspace = new(server);
        BasicDocuments basic = new(server);
        DocumentSyncHandler sync = new(workspace, basic);
        DefinitionHandler definition = new(workspace, basic);
        ReferencesHandler references = new(workspace, basic);
        HoverHandler hover = new(workspace, basic);
        CompletionHandler completion = new(workspace, basic);
        DocumentSymbolHandler documentSymbols = new(workspace, basic);
        WorkspaceSymbolHandler workspaceSymbols = new(workspace);

        server.OnRequest("initialize", _ => Capabilities());
        server.OnRequest("shutdown", (JsonObject? _) => (JsonNode?)null);
        server.OnNotification("initialized", _ => { });
        server.OnNotification("textDocument/didOpen", parameters => sync.Open(LspParams.From(parameters)));
        server.OnNotification("textDocument/didChange", parameters => sync.Change(LspParams.From(parameters)));
        server.OnNotification("textDocument/didClose", parameters => sync.Close(LspParams.From(parameters)));
        server.OnRequest("textDocument/definition", parameters => Answer(definition.Handle, parameters, Locations));
        server.OnRequest("textDocument/references", parameters => Answer(references.Handle, parameters, Locations));
        server.OnRequest("textDocument/hover", parameters => Answer(hover.Handle, parameters, found => found?.ToJson()));
        server.OnRequest(
            "textDocument/completion",
            parameters => Answer(completion.Handle, parameters, items => Array(items, item => item.ToJson())));

        server.OnRequest(
            "textDocument/documentSymbol",
            parameters => Answer(documentSymbols.Handle, parameters, symbols => Array(symbols, symbol => symbol.ToJson())));

        server.OnRequest(
            "workspace/symbol",
            parameters => Answer(workspaceSymbols.Handle, parameters, symbols => Array(symbols, symbol => symbol.ToJson())));

        server.OnRequest("retrocore/basic/renumber", parameters => BasicFiles.Renumber(parameters ?? []));
        server.OnRequest("retrocore/basic/list", parameters => BasicFiles.List(parameters ?? []));
        server.OnRequest("retrocore/basic/store", parameters => BasicFiles.Store(parameters ?? []));

        await server.Run().ConfigureAwait(continueOnCapturedContext: false);
    }

    // What the server does, in its answer to initialize: whole-document sync, and the features the handlers serve.
    // The client sends only the retrocore languages' documents.
    private static JsonObject Capabilities() => new()
    {
        ["capabilities"] = new JsonObject
        {
            ["textDocumentSync"] = new JsonObject
            {
                ["openClose"] = true,
                ["change"] = 1,
                ["save"] = new JsonObject { ["includeText"] = false }
            },
            ["definitionProvider"] = true,
            ["referencesProvider"] = true,
            ["hoverProvider"] = true,
            ["completionProvider"] = new JsonObject
            {
                ["triggerCharacters"] = new JsonArray("."),
                ["resolveProvider"] = false
            },
            ["documentSymbolProvider"] = true,
            ["workspaceSymbolProvider"] = true
        },
        ["serverInfo"] = new JsonObject { ["name"] = "retrocore" }
    };

    // Runs a handler on a request's params and writes what it finds.
    private static async Task<JsonNode?> Answer<T>(
        Func<LspParams, Task<T>> handler,
        JsonObject? parameters,
        Func<T, JsonNode?> write)
    {
        T found = await handler(LspParams.From(parameters)).ConfigureAwait(continueOnCapturedContext: false);
        return write(found);
    }

    // Items as an LSP array, or null for none.
    private static JsonArray? Array<T>(IEnumerable<T>? items, Func<T, JsonObject> write) =>
        items?.Select(item => (JsonNode?)write(item)).ToJsonArray();

    // Locations as LSP lists them, or null for none.
    private static JsonArray? Locations(IEnumerable<LspLocation>? locations) => Array(locations, location => location.ToJson());

    /// <summary>
    ///  Gets a document's full path.
    /// </summary>
    /// <param name="uri">The document.</param>
    /// <returns>The path.</returns>
    internal static string PathOf(DocumentUri uri) => Path.GetFullPath(uri.GetFileSystemPath());

    /// <summary>
    ///  Formats a value as the sources write it.
    /// </summary>
    /// <param name="value">The value.</param>
    /// <returns>Hex for addresses and bytes, decimal otherwise.</returns>
    internal static string Hex(long value) => value switch
    {
        >= 0 and <= ByteMaximum => $"${value:X2}",
        >= 0 and <= WordMaximum => $"${value:X4}",
        _ => value.ToString(CultureInfo.InvariantCulture)
    };

    /// <summary>
    ///  Gets the outline kind for a definition.
    /// </summary>
    /// <param name="site">The definition.</param>
    /// <returns>The kind.</returns>
    internal static SymbolKind KindOf(SymbolSite site) => site.Kind switch
    {
        SymbolSiteKind.Constant => SymbolKind.Constant,
        SymbolSiteKind.Macro => SymbolKind.Method,
        _ => SymbolKind.Function
    };

    /// <summary>
    ///  Finds the definitions of the name under the cursor.
    /// </summary>
    /// <param name="workspace">The workspace.</param>
    /// <param name="path">The document.</param>
    /// <param name="position">The cursor.</param>
    /// <returns>The definitions; none when the cursor is not on a defined name.</returns>
    internal static IReadOnlyList<SymbolSite> SitesAt(LanguageWorkspace workspace, string path, Position position)
    {
        string[] lines = workspace.LinesOf(path);
        if (position.Line >= lines.Length || SourceText.WordAt(lines[position.Line], position.Character) is not { } word)
        {
            return [];
        }

        if (workspace.AnalysisOf(path)?.Find(word.Word) is { Count: > 0 } sites) { return sites; }

        // A local label: the nearest line in this file that defines it.
        if (SourceText.LocalDefinition(lines, word.Word, position.Line) is { } local)
        {
            return [local with { Path = path }];
        }

        // A name the SDK's ROM sources define.
        return [.. workspace.SdkAnalyses().SelectMany(analysis => analysis.Find(word.Word)).Take(1)];
    }
}
