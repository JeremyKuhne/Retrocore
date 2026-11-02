// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug.Language;

/// <summary>
///  Goes to where a label, constant or macro is defined, in any file of the assembly.
/// </summary>
internal sealed class DefinitionHandler
{
    private readonly LanguageWorkspace _workspace;
    private readonly BasicDocuments _basic;

    /// <summary>
    ///  Creates the handler.
    /// </summary>
    /// <param name="workspace">The workspace.</param>
    /// <param name="basic">The open BASIC documents.</param>
    public DefinitionHandler(LanguageWorkspace workspace, BasicDocuments basic)
    {
        _workspace = workspace;
        _basic = basic;
    }

    /// <summary>
    ///  Answers <c>textDocument/definition</c>.
    /// </summary>
    /// <param name="request">The request's params.</param>
    /// <returns>The definitions; none when the cursor is not on a defined name.</returns>
    public Task<IEnumerable<LspLocation>> Handle(LspParams request)
    {
        if (_basic.Get(request.TextDocument.Uri) is { } basic)
        {
            return Task.FromResult(BasicFeatures.Definition(basic, request.Position));
        }

        string path = LanguageHost.PathOf(request.TextDocument.Uri);
        IReadOnlyList<SymbolSite> sites = LanguageHost.SitesAt(_workspace, path, request.Position);
        return Task.FromResult(sites.Select(site => new LspLocation
        {
            Uri = DocumentUri.FromFileSystemPath(site.Path),
            Range = new LspRange(site.Line, site.Column, site.Line, site.Column + site.Name.Length)
        }));
    }
}
