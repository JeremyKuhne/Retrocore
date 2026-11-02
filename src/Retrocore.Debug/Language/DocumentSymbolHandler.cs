// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug.Language;

/// <summary>
///  Lists a file's labels, constants and macros for the outline and breadcrumbs.
/// </summary>
internal sealed class DocumentSymbolHandler
{
    private readonly LanguageWorkspace _workspace;
    private readonly BasicDocuments _basic;

    /// <summary>
    ///  Creates the handler.
    /// </summary>
    /// <param name="workspace">The workspace.</param>
    /// <param name="basic">The open BASIC documents.</param>
    public DocumentSymbolHandler(LanguageWorkspace workspace, BasicDocuments basic)
    {
        _workspace = workspace;
        _basic = basic;
    }

    /// <summary>
    ///  Answers <c>textDocument/documentSymbol</c>: the document's outline.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   Waits for a newly opened file's first assembly: VS Code keeps the outline it gets as the file opens until
    ///   the file changes, so answering before the assembly would leave it empty.
    ///  </para>
    /// </remarks>
    /// <param name="request">The request's params.</param>
    /// <returns>The outline, or null before the document is analyzed.</returns>
    public async Task<IReadOnlyList<DocumentSymbol>?> Handle(LspParams request)
    {
        if (_basic.Get(request.TextDocument.Uri) is { } basic)
        {
            return BasicFeatures.Symbols(basic);
        }

        string path = LanguageHost.PathOf(request.TextDocument.Uri);
        List<DocumentSymbol>? result = null;
        if (await _workspace.AnalysisOfAsync(path, CancellationToken.None).ConfigureAwait(continueOnCapturedContext: false) is { } analysis)
        {
            List<DocumentSymbol> symbols = [];
            foreach (SymbolSite site in analysis.Definitions.OrderBy(site => site.Line))
            {
                if (string.Equals(site.Path, path, StringComparison.OrdinalIgnoreCase)) { symbols.Add(Symbol(site)); }
            }

            result = symbols;
        }

        return result;
    }

    private static DocumentSymbol Symbol(SymbolSite site)
    {
        LspRange range = new(site.Line, site.Column, site.Line, site.Column + site.Name.Length);
        return new DocumentSymbol
        {
            Name = site.Name,
            Detail = site.Value is { } value ? LanguageHost.Hex(value) : null,
            Kind = LanguageHost.KindOf(site),
            Range = range,
            SelectionRange = range
        };
    }
}
