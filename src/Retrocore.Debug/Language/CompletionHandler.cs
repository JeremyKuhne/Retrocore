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
        // = and , ask only for an exclusion's rules, which BASIC has none of.
        bool ruleTrigger = request.TriggerCharacter is "=" or ",";
        if (_basic.Get(request.TextDocument.Uri) is { } basic)
        {
            if (ruleTrigger) { return Task.FromResult(new List<CompletionItem>()); }
            return Task.FromResult(BasicFeatures.Complete(basic, request.Position));
        }

        string path = LanguageHost.PathOf(request.TextDocument.Uri);
        string[] lines = _workspace.LinesOf(path);
        int line = request.Position.Line;
        string before = line < lines.Length ? lines[line][..Math.Min(request.Position.Character, lines[line].Length)] : "";
        List<CompletionItem>? rules = LintEditor.Complete(before, line);
        if (rules is not null) { return Task.FromResult(rules); }

        // In a comment, only an exclusion's rules complete; and the characters that ask for them ask for nothing else.
        if (SourceText.CommentStart(before) >= 0 || ruleTrigger)
        {
            return Task.FromResult(new List<CompletionItem>());
        }

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
            Dictionary<string, string> summaries = Summaries(analysis);
            items.AddRange(Names(analysis, macros: false, summaries));
            items.AddRange(UsedNames(analysis, path, line, summaries));
        }

        return Task.FromResult(items);
    }

    // The summary of each documented name in the analysis, with inherited summaries.
    private Dictionary<string, string> Summaries(SourceAnalysis analysis)
    {
        Dictionary<string, string> summaries = [with(StringComparer.Ordinal)];
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
                FilterText = AlsoNames(analysis, site.Name) is { Length: > 0 } also ? $"{site.Name} {also}" : null,
                Kind = site.Kind switch
                {
                    SymbolSiteKind.Macro => CompletionItemKind.Function,
                    SymbolSiteKind.Constant => CompletionItemKind.Constant,
                    _ => CompletionItemKind.Reference
                },
                Detail = Detail(site, AlsoNames(analysis, site.Name)),
                Documentation = summaries.TryGetValue(site.Name, out string? summary)
                    ? new MarkupContent { Kind = MarkupKind.Markdown, Value = summary }
                    : null
            });

    // The names the .using directives in effect make usable unqualified, listed after the other names.
    private static IEnumerable<CompletionItem> UsedNames(SourceAnalysis analysis, string path, int line, Dictionary<string, string> summaries)
    {
        HashSet<string> seen = [with(StringComparer.OrdinalIgnoreCase)];
        foreach ((string name, SymbolSite site) in analysis.UsedNames(path, line))
        {
            if (site.Kind == SymbolSiteKind.Macro || !seen.Add(name)) { continue; }
            MarkupContent? documentation = summaries.TryGetValue(site.Name, out string? summary)
                ? new MarkupContent { Kind = MarkupKind.Markdown, Value = summary }
                : null;

            yield return new CompletionItem
            {
                Label = name,
                Kind = site.Kind == SymbolSiteKind.Constant ? CompletionItemKind.Constant : CompletionItemKind.Reference,
                Detail = $"{Detail(site, AlsoNames(analysis, site.Name))}, {site.Name}",
                SortText = $"~{name}",
                Documentation = documentation
            };
        }
    }

    // The value, and the historical names typing finds the definition by: "$FDED, also COUT".
    private static string Detail(SymbolSite site, string also)
    {
        string detail = site.Value is { } value ? LanguageHost.Hex(value) : "macro";
        return also.Length == 0 ? detail : $"{detail}, also {also.Replace(" ", ", ", StringComparison.Ordinal)}";
    }

    // A definition's historical names, from its Also: sections, separated by spaces.
    private static string AlsoNames(SourceAnalysis analysis, string name) =>
        analysis.Documentation.Find(name) is { } topic
            ? string.Join(" ", DocumentationAlso.Of(topic.Sections).Select(also => also.Name))
            : "";
}
