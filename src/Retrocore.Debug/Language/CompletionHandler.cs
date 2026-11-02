// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Documentation;

namespace Retrocore.Debug.Language;

/// <summary>
///  Completes instructions, directives and macros where an operation goes, and the assembly's names in operands.
/// </summary>
internal sealed class CompletionHandler
{
    private readonly LanguageWorkspace _workspace;
    private readonly BasicDocuments _basic;

    /// <summary>
    ///  Creates the handler.
    /// </summary>
    /// <param name="workspace">The workspace.</param>
    /// <param name="basic">The open BASIC documents.</param>
    public CompletionHandler(LanguageWorkspace workspace, BasicDocuments basic)
    {
        _workspace = workspace;
        _basic = basic;
    }

    /// <summary>
    ///  Answers <c>textDocument/completion</c>.
    /// </summary>
    /// <param name="request">The request's params.</param>
    /// <returns>The completions.</returns>
    public Task<List<CompletionItem>> Handle(LspParams request)
    {
        if (_basic.Get(request.TextDocument.Uri) is { } basic)
        {
            return Task.FromResult(BasicFeatures.Complete(basic, request.Position));
        }

        string path = LanguageHost.PathOf(request.TextDocument.Uri);
        string[] lines = _workspace.LinesOf(path);
        int line = request.Position.Line;
        string before = line < lines.Length ? lines[line][..Math.Min(request.Position.Character, lines[line].Length)] : "";
        if (SourceText.CommentStart(before) >= 0) { return Task.FromResult(new List<CompletionItem>()); }

        SourceAnalysis? analysis = _workspace.AnalysisOf(path);
        List<CompletionItem> items = [];
        if (SourceText.IsOperation(before))
        {
            items.AddRange(InstructionDocs.MnemonicsFor(SourceText.InstructionSetOf(lines, line)).Select(mnemonic => new CompletionItem
            {
                Label = mnemonic.ToLowerInvariant(),
                Kind = CompletionItemKind.Keyword,
                Detail = "instruction"
            }));

            items.AddRange(DirectiveDocs.Native.Select(directive => new CompletionItem
            {
                Label = directive,
                Kind = CompletionItemKind.Keyword,
                Detail = DirectiveDocs.Describe(directive)
            }));

            if (analysis is not null) { items.AddRange(Names(analysis, macros: true, Summaries(analysis))); }
        }
        else if (analysis is not null)
        {
            items.AddRange(Names(analysis, macros: false, Summaries(analysis)));
        }

        return Task.FromResult(items);
    }

    // The summary of each documented name in the analysis, with inherited summaries.
    private Dictionary<string, string> Summaries(SourceAnalysis analysis)
    {
        Dictionary<string, string> summaries = new(StringComparer.Ordinal);
        DocumentationResolver resolver = _workspace.ResolverFor(analysis);
        foreach (DocumentationTopic topic in analysis.Documentation.Topics)
        {
            string summary = DocumentationMarkdown.Summary(resolver.Effective(topic), resolver);
            if (summary.Length != 0) { summaries.TryAdd(topic.Name, summary); }
        }

        return summaries;
    }

    private static IEnumerable<CompletionItem> Names(SourceAnalysis analysis, bool macros, Dictionary<string, string> summaries) =>
        analysis.Definitions
            .Where(site => macros ? site.Kind == SymbolSiteKind.Macro : site.Kind != SymbolSiteKind.Macro)
            .DistinctBy(site => site.Name)
            .Select(site => new CompletionItem
            {
                Label = site.Name,
                Kind = site.Kind switch
                {
                    SymbolSiteKind.Macro => CompletionItemKind.Function,
                    SymbolSiteKind.Constant => CompletionItemKind.Constant,
                    _ => CompletionItemKind.Reference
                },
                Detail = site.Value is { } value ? LanguageHost.Hex(value) : "macro",
                Documentation = summaries.TryGetValue(site.Name, out string? summary)
                    ? new MarkupContent { Kind = MarkupKind.Markdown, Value = summary }
                    : null
            });
}
