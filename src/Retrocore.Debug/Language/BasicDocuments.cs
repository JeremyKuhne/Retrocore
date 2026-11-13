// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Collections.Concurrent;
using Retrocore.Basic;

namespace Retrocore.Debug.Language;

/// <summary>
///  The open BASIC documents, by URI, which need not be files: the machine's program is one. Each is analyzed as it
///  changes and its problems published.
/// </summary>
internal sealed class BasicDocuments
{
    private readonly ILanguageClient _server;
    private readonly ConcurrentDictionary<string, BasicDocument> _open = new(StringComparer.Ordinal);

    /// <summary>
    ///  Creates the store.
    /// </summary>
    /// <param name="server">The server, to publish diagnostics.</param>
    public BasicDocuments(ILanguageClient server) => _server = server;

    /// <summary>
    ///  Gets the dialect a BASIC language means, or null for the general language that a pragma or the file name
    ///  decides.
    /// </summary>
    /// <param name="languageId">The VS Code language.</param>
    /// <returns>The dialect.</returns>
    internal static BasicDialect? DialectOf(string languageId) => languageId switch
    {
        LanguageHost.AppleSoftId => BasicDialect.AppleSoft,
        LanguageHost.Level2Id => BasicDialect.Level2,
        LanguageHost.IntegerId => BasicDialect.Integer,
        LanguageHost.BusinessId => BasicDialect.BusinessBasic,
        LanguageHost.Apple1Id => BasicDialect.Apple1,
        _ => null
    };

    /// <summary>
    ///  Gets an open BASIC document.
    /// </summary>
    /// <param name="uri">The document.</param>
    /// <returns>The document, or null when it is not an open BASIC document.</returns>
    internal BasicDocument? Get(DocumentUri uri) => _open.GetValueOrDefault(uri.ToString());

    /// <summary>
    ///  Opens or updates a document.
    /// </summary>
    /// <param name="uri">The document.</param>
    /// <param name="languageId">Its language.</param>
    /// <param name="text">Its text.</param>
    internal void Update(DocumentUri uri, string languageId, string text)
    {
        BasicDocument document = Analyze(uri, languageId, text);
        _open[uri.ToString()] = document;
        _server.PublishDiagnostics(uri, document.Source.Diagnostics.Select(diagnostic => Convert(document, diagnostic)));
    }

    /// <summary>
    ///  Updates an open document's text.
    /// </summary>
    /// <param name="uri">The document.</param>
    /// <param name="text">Its text.</param>
    /// <returns>Whether it is an open BASIC document.</returns>
    internal bool Change(DocumentUri uri, string text)
    {
        if (Get(uri) is not { } document) { return false; }
        Update(uri, document.LanguageId, text);
        return true;
    }

    /// <summary>
    ///  Closes a document and clears its problems.
    /// </summary>
    /// <param name="uri">The document.</param>
    /// <returns>Whether it was an open BASIC document.</returns>
    internal bool Close(DocumentUri uri)
    {
        if (!_open.TryRemove(uri.ToString(), out _)) { return false; }
        _server.PublishDiagnostics(uri, []);
        return true;
    }

    private static BasicDocument Analyze(DocumentUri uri, string languageId, string text)
    {
        if (languageId == LanguageHost.Level1Id)
        {
            BasicSource none = BasicSource.Analyze("", BasicDialect.Level2);
            return new(uri, languageId, text, none, "Level I BASIC is not supported yet.");
        }

        return new(uri, languageId, text, BasicSource.Analyze(text, DialectOf(languageId), uri.Path), Note: null);
    }

    private static Diagnostic Convert(BasicDocument document, BasicDiagnostic diagnostic)
    {
        int length = diagnostic.Line < document.Source.Lines.Count ? document.Source.Lines[diagnostic.Line].Length : 0;
        int end = diagnostic.End < 0 ? Math.Max(length, diagnostic.Start) : diagnostic.End;
        return new Diagnostic
        {
            Range = new LspRange(diagnostic.Line, diagnostic.Start, diagnostic.Line, end),
            Severity = diagnostic.Severity == BasicSeverity.Error ? DiagnosticSeverity.Error : DiagnosticSeverity.Warning,
            Source = "retrocore",
            Message = diagnostic.Message
        };
    }
}
