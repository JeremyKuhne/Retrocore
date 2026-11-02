// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug.Language;

/// <summary>
///  Finds all references to a label, constant or macro: in the assemblies of the open files, the files they
///  include, and the SDK's ROM sources.
/// </summary>
internal sealed class ReferencesHandler
{
    private readonly LanguageWorkspace _workspace;
    private readonly BasicDocuments _basic;

    /// <summary>
    ///  Creates the handler.
    /// </summary>
    /// <param name="workspace">The workspace.</param>
    /// <param name="basic">The open BASIC documents.</param>
    public ReferencesHandler(LanguageWorkspace workspace, BasicDocuments basic)
    {
        _workspace = workspace;
        _basic = basic;
    }

    /// <summary>
    ///  Answers <c>textDocument/references</c>.
    /// </summary>
    /// <param name="request">The request's params.</param>
    /// <returns>The references, or null when the cursor is not on a defined name.</returns>
    public async Task<IEnumerable<LspLocation>?> Handle(LspParams request)
    {
        if (_basic.Get(request.TextDocument.Uri) is { } basic)
        {
            return BasicFeatures.References(basic, request.Position, request.Context.IncludeDeclaration);
        }

        string path = LanguageHost.PathOf(request.TextDocument.Uri);
        await _workspace.AnalysisOfAsync(path, CancellationToken.None).ConfigureAwait(continueOnCapturedContext: false);
        string[] lines = _workspace.LinesOf(path);
        if (request.Position.Line >= lines.Length
            || SourceText.WordAt(lines[request.Position.Line], request.Position.Character) is not { } word)
        {
            return null;
        }

        IReadOnlyList<SymbolSite> targets = LanguageHost.SitesAt(_workspace, path, request.Position);
        if (targets.Count == 0) { return null; }
        List<SymbolSite> references = SymbolReferences.Find(
            word.Word,
            targets,
            _workspace.AllAnalyses(),
            [.. _workspace.SdkAnalyses()],
            request.Context.IncludeDeclaration);

        return references.Select(site => new LspLocation
        {
            Uri = DocumentUri.FromFileSystemPath(site.Path),
            Range = new LspRange(site.Line, site.Column, site.Line, site.Column + site.Name.Length)
        });
    }
}
