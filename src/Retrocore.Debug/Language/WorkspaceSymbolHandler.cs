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
            .SelectMany(analysis => analysis.Definitions.Select(site => (Site: site, Name: Matched(analysis, site, query))))
            .Where(found => found.Name is not null)
            .DistinctBy(found => (found.Site.Name, found.Site.Path, found.Site.Line))
            .OrderBy(found => Rank(found.Name ?? "", query))
            .ThenBy(found => found.Site.Name, StringComparer.OrdinalIgnoreCase)
            .Take(MaximumResults)
            .Select(found => new WorkspaceSymbol
            {
                // A definition found by a historical name shows it, so the client's own filter keeps it.
                Name = found.Name == found.Site.Name ? found.Site.Name : $"{found.Site.Name} ({found.Name})",
                Kind = LanguageHost.KindOf(found.Site),
                ContainerName = Path.GetFileName(found.Site.Path),
                Location = new LspLocation
                {
                    Uri = DocumentUri.FromFileSystemPath(found.Site.Path),
                    Range = new LspRange(
                        found.Site.Line,
                        found.Site.Column,
                        found.Site.Line,
                        found.Site.Column + (found.Site.SourceLength ?? found.Site.Name.Length))
                }
            });

        return Task.FromResult(symbols);
    }

    // The name the query matched: the definition's own, else one of its historical names; null when neither.
    private static string? Matched(SourceAnalysis analysis, SymbolSite site, string query)
    {
        if (site.Name.Contains(query, StringComparison.OrdinalIgnoreCase)) { return site.Name; }
        if (query.Length == 0 || analysis.Documentation.FindSymbol(site.Name) is not { } topic) { return null; }
        return analysis.Documentation.AlsoOf(topic)
            .Select(also => also.Name)
            .Where(name => name.Contains(query, StringComparison.OrdinalIgnoreCase))
            .OrderBy(name => Rank(name, query))
            .FirstOrDefault();
    }

    // Exact names first, then names that start with the query.
    private static int Rank(string name, string query)
    {
        if (name.Equals(query, StringComparison.OrdinalIgnoreCase)) { return 0; }
        return name.StartsWith(query, StringComparison.OrdinalIgnoreCase) ? 1 : 2;
    }
}
