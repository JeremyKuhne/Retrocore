// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug.Language;

/// <summary>
///  Finds labels, constants and macros across the open assemblies and the SDK's ROM sources.
/// </summary>
internal sealed class WorkspaceSymbolHandler
{
    private const int MaximumResults = 500;

    private readonly LanguageWorkspace _workspace;

    /// <summary>
    ///  Creates the handler.
    /// </summary>
    /// <param name="workspace">The workspace.</param>
    public WorkspaceSymbolHandler(LanguageWorkspace workspace) => _workspace = workspace;

    /// <summary>
    ///  Answers <c>workspace/symbol</c>.
    /// </summary>
    /// <param name="request">The request's params.</param>
    /// <returns>The symbols whose names hold the query, the closest first.</returns>
    public Task<IEnumerable<WorkspaceSymbol>> Handle(LspParams request)
    {
        string query = request.Query;
        IEnumerable<WorkspaceSymbol> symbols = _workspace.AllAnalyses()
            .SelectMany(analysis => analysis.Definitions)
            .Where(site => site.Name.Contains(query, StringComparison.OrdinalIgnoreCase))
            .DistinctBy(site => (site.Name, site.Path, site.Line))
            .OrderBy(site => Rank(site.Name, query))
            .ThenBy(site => site.Name, StringComparer.OrdinalIgnoreCase)
            .Take(MaximumResults)
            .Select(site => new WorkspaceSymbol
            {
                Name = site.Name,
                Kind = LanguageHost.KindOf(site),
                ContainerName = Path.GetFileName(site.Path),
                Location = new LspLocation
                {
                    Uri = DocumentUri.FromFileSystemPath(site.Path),
                    Range = new LspRange(site.Line, site.Column, site.Line, site.Column + site.Name.Length)
                }
            });

        return Task.FromResult(symbols);
    }

    // Exact names first, then names that start with the query.
    private static int Rank(string name, string query)
    {
        if (name.Equals(query, StringComparison.OrdinalIgnoreCase)) { return 0; }
        return name.StartsWith(query, StringComparison.OrdinalIgnoreCase) ? 1 : 2;
    }
}
