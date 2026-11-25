// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Documentation;
using Retrocore.Isa;

namespace Retrocore.Debug.Language;

/// <summary>
///  Describes the name under the cursor: a symbol's value and comment, an instruction or a directive, and the
///  bytes the line assembled to.
/// </summary>
internal sealed class HoverHandler
{
    private const int MaximumBytesShown = 16;

    private readonly LanguageWorkspace _workspace;
    private readonly BasicDocuments _basic;

    /// <summary>
    ///  Creates the handler.
    /// </summary>
    /// <param name="workspace">The workspace.</param>
    /// <param name="basic">The open BASIC documents.</param>
    public HoverHandler(LanguageWorkspace workspace, BasicDocuments basic)
    {
        _workspace = workspace;
        _basic = basic;
    }

    /// <summary>
    ///  Answers <c>textDocument/hover</c>.
    /// </summary>
    /// <param name="request">The request's params.</param>
    /// <returns>The hover, or null when there is nothing to say.</returns>
    public Task<Hover?> Handle(LspParams request)
    {
        if (_basic.Get(request.TextDocument.Uri) is { } basic)
        {
            return Task.FromResult(BasicFeatures.Hover(basic, request.Position));
        }

        string path = LanguageHost.PathOf(request.TextDocument.Uri);
        string[] lines = _workspace.LinesOf(path);
        int line = request.Position.Line;
        Hover? none = null;
        if (line < lines.Length && LintEditor.RuleAt(lines[line], request.Position.Character) is { } excluded)
        {
            return Task.FromResult<Hover?>(new Hover
            {
                Contents = new MarkupContent
                {
                    Kind = MarkupKind.Markdown,
                    Value = $"**{excluded.Rule.Id}** (lint rule): {excluded.Rule.Description}"
                },
                Range = new LspRange(line, excluded.Start, line, excluded.Start + excluded.Rule.Id.Length)
            });
        }

        if (line >= lines.Length) { return Task.FromResult(none); }
        SourceAnalysis? analysis = _workspace.AnalysisOf(path);
        int comment = SourceText.CommentStart(lines[line]);
        if (comment >= 0 && request.Position.Character >= comment)
        {
            return Task.FromResult(LinkAt(analysis, lines, path, line, request.Position.Character, comment));
        }

        if (SourceText.WordAt(lines[line], request.Position.Character) is not { } word)
        {
            return Task.FromResult(none);
        }

        List<string> parts = [];
        bool operation = SourceText.IsOperation(lines[line][..word.Start]);
        // A line whose bytes a macro of that name wrote is the macro's, whatever .cpu the text before it shows: p-code's
        // LDA is Pcode.asm's macro, even where the .cpu Pcode that owns it is in that include.
        bool expanded = operation
            && analysis?.ExpandsMacro(path, line) == true
            && analysis.Find(word.Word, analysis.UsesMacro10(path)).Any(site => site.Kind == SymbolSiteKind.Macro);

        // A mnemonic's .w suffix forces absolute addressing; the instruction is the same.
        string mnemonic = word.Word.EndsWith(".w", StringComparison.OrdinalIgnoreCase) ? word.Word[..^2] : word.Word;
        string? instruction = operation && !expanded ? InstructionDocs.Describe(mnemonic, SourceText.InstructionSetOf(lines, line)) : null;
        IReadOnlyList<SymbolSite> sites = instruction is null ? LanguageHost.SitesAt(_workspace, path, request.Position) : [];
        if (instruction is not null)
        {
            parts.Add(instruction);
        }
        else if (sites.Count != 0)
        {
            // An old name found its definition through an Also: section: say so, so the new name is learned.
            string name = sites[0].Name;
            bool historical = !name.Equals(word.Word, StringComparison.OrdinalIgnoreCase) && IsAlso(sites[0], word.Word);
            parts.Add(historical
                ? $"`{word.Word}` is a historical name of `{name}`.\n\n{Describe(sites[0])}"
                : Describe(sites[0]));
        }
        else if (word.Word.StartsWith('.') && DirectiveDocs.Describe(word.Word) is { } directive)
        {
            parts.Add($"**{word.Word}**: {directive}");
        }

        if (analysis is not null && Assembled(analysis, path, line) is { } bytes) { parts.Add(bytes); }
        if (parts.Count == 0) { return Task.FromResult(none); }
        MarkupContent content = new() { Kind = MarkupKind.Markdown, Value = string.Join("\n\n---\n\n", parts) };
        Hover hover = new()
        {
            Contents = content,
            Range = new LspRange(line, word.Start, line, word.Start + word.Word.Length)
        };

        return Task.FromResult<Hover?>(hover);
    }

    private Hover? LinkAt(SourceAnalysis? analysis, string[] lines, string path, int line, int column, int commentStart)
    {
        if (analysis is null) { return null; }
        string text = lines[line];
        DocumentationLink? link = DocumentationText.Links(text[commentStart..])
            .FirstOrDefault(link => column >= commentStart + link.Start && column < commentStart + link.Start + link.Length);

        if (link is null) { return null; }
        bool ContainsCursor(DocumentationComment comment) =>
            string.Equals(comment.Path, path, StringComparison.OrdinalIgnoreCase)
                && line >= comment.Line
                && line <= comment.TargetLine;

        DocumentationResolver resolver = _workspace.ResolverFor(analysis);
        DocumentationTopic? from = text.AsSpan(commentStart).StartsWith(";;")
            ? analysis.Documentation.Topics.FirstOrDefault(topic => topic.Comments.Any(ContainsCursor))
            : null;

        DocumentationComment? original = from?.Comments.FirstOrDefault(ContainsCursor);
        IReadOnlyList<DocumentationScopes> lexical = from is null ? [] : DocumentationParser.ScopesByLine(analysis.LinesOf(path));
        string localScope = line < lexical.Count ? lexical[line].Scope : "";
        DocumentationTarget[] targets = [.. analysis.ScopesAt(path, line).Select(scopes =>
        {
            if (from is not null && scopes.Scope == localScope)
            {
                return ResolveLink(analysis, resolver, from, original, scopes, link.Target);
            }

            string outer = localScope.Length == 0 ? scopes.Scope
                : scopes.Scope == localScope ? "" : scopes.Scope[..^(localScope.Length + 2)];

            IReadOnlyList<DocumentationUsing> usings = original is null ? scopes.Usings
                : [.. original.Usings.Select(directive => new DocumentationUsing(
                    outer.Length == 0 ? directive.Scope
                        : directive.Scope.Length == 0 ? outer : $"{outer}::{directive.Scope}", directive.Names, directive.Line))];

            string name = scopes.Scope.Length == 0 ? "__comment" : $"{scopes.Scope}::__comment";
            DocumentationComment context = new()
            {
                Path = path, Line = line, TargetLine = line, Name = name, Kind = DocumentationKind.Topic, Usings = usings
            };

            DocumentationTopic topic = new()
            {
                Name = name, Kind = DocumentationKind.Topic, Set = analysis.Documentation, Comments = [context]
            };

            return ResolveLink(analysis, resolver, topic, context, scopes, link.Target);
        }).Distinct()];

        if (targets.Length != 1) { return null; }
        DocumentationTarget target = targets[0];
        string? description;
        if (target.Kind == DocumentationTargetKind.Directive)
        {
            description = DirectiveDocs.Describe(target.Name) is { } directive ? $"**{target.Name}**: {directive}" : null;
        }
        else if (target.Kind == DocumentationTargetKind.Instruction)
        {
            InstructionSet? cpu = analysis.InstructionSetAt(path, line, out bool ambiguous);
            description = ambiguous ? null : InstructionDocs.Describe(target.Name, cpu ?? SourceText.InstructionSetOf(lines, line));
        }
        else if (target.Kind is DocumentationTargetKind.Document or DocumentationTargetKind.Url)
        {
            description = target.Address is { } address ? $"[{link.Text}]({DocumentationMarkdown.Uri(address)})" : null;
        }
        else if (target.Kind is DocumentationTargetKind.Topic or DocumentationTargetKind.Symbol)
        {
            SourceAnalysis? source = _workspace.AllAnalyses().Prepend(analysis)
                .FirstOrDefault(candidate => ReferenceEquals(candidate.Documentation, target.Set));

            bool macro10 = analysis.UsesMacro10(path)
                || (target.Topic is { } definition && source?.UsesMacro10(definition.Path) == true);

            IReadOnlyList<SymbolSite> sites = source?.Find(target.Name, macro10) ?? [];
            SymbolSite? site = sites.FirstOrDefault(candidate => candidate.Name.Equals(target.Name, StringComparison.Ordinal))
                ?? sites.FirstOrDefault(candidate => target.Topic?.Comments.Any(comment =>
                    comment.TargetLine == candidate.Line && string.Equals(comment.Path, candidate.Path, StringComparison.OrdinalIgnoreCase)) == true);

            DocumentationTopic? topic = target.Topic ?? (source is not null && site is not null
                ? source.Documentation.Topics.FirstOrDefault(candidate => candidate.Comments.Any(comment =>
                    comment.TargetLine == site.Line && string.Equals(comment.Path, site.Path, StringComparison.OrdinalIgnoreCase)))
                : null);

            if (topic is not null
                && site is not null
                && topic.Name != site.Name
                && topic.Comments.FirstOrDefault(comment => comment.Macro is null
                    && comment.TargetLine == site.Line
                    && string.Equals(comment.Path, site.Path, StringComparison.OrdinalIgnoreCase)) is { } own)
            {
                topic = new DocumentationTopic
                {
                    Name = site.Name,
                    Kind = own.Kind,
                    Set = topic.Set,
                    Comments = [own],
                    Summary = own.Summary,
                    Remarks = own.Remarks,
                    Sections = own.Sections,
                    Value = site.Value
                };
            }

            (DocumentationTopic Topic, DocumentationResolver Resolver)? documented = topic is not null && source is not null
                ? (topic, _workspace.ResolverFor(source)) : null;

            description = site is not null ? Describe(site, documented)
                : documented is { } found ? DescribeTopic(found.Topic, found.Resolver) : null;
        }
        else
        {
            description = null;
        }

        if (description is null) { return null; }
        return new Hover
        {
            Contents = new MarkupContent { Kind = MarkupKind.Markdown, Value = description },
            Range = new LspRange(line, commentStart + link.Start, line, commentStart + link.Start + link.Length)
        };
    }

    private static DocumentationTarget ResolveLink(
        SourceAnalysis analysis,
        DocumentationResolver resolver,
        DocumentationTopic from,
        DocumentationComment? context,
        DocumentationScopes scopes,
        string name)
    {
        bool absolute = name.StartsWith("::", StringComparison.Ordinal);
        string target = absolute ? name[2..] : name;
        string path = context?.Path ?? from.Path;
        string[] components = target.Split("::");
        bool names = components.All(part => part.Length != 0 && part.All(character => char.IsAsciiLetterOrDigit(character) || character == '_'));
        if (names && analysis.UsesMacro10(path))
        {
            string last = components[^1];
            string significant = target[..^last.Length] + last[..Math.Min(last.Length, 6)].ToUpperInvariant();
            DocumentationScopes lookup = absolute ? DocumentationScopes.Root : scopes;
            List<SymbolSite>? found = analysis.Bound(significant, path, lookup, exact: true)
                ?? analysis.Bound(significant, path, lookup, exact: false);

            if (found is not null)
            {
                List<SymbolSite> bound = [.. found.Where(site => site.Kind != SymbolSiteKind.Macro
                    && site.Name[(site.Name.LastIndexOf(':') + 1)..] == significant[(significant.LastIndexOf(':') + 1)..])];

                if (bound.Count > 1) { return new(DocumentationTargetKind.Ambiguous, name); }
                if (bound.Count == 1)
                {
                    SymbolSite site = bound[0];
                    DocumentationTopic? documented = analysis.Documentation.Topics.FirstOrDefault(topic =>
                        topic.Comments.Any(comment => comment.TargetLine == site.Line
                            && string.Equals(comment.Path, site.Path, StringComparison.OrdinalIgnoreCase)));

                    return new(DocumentationTargetKind.Symbol, site.Name)
                    {
                        Set = analysis.Documentation, Topic = documented, Value = site.Value
                    };
                }
            }
        }

        if (target.Split("::").All(part => part.Length != 0
            && part.All(character => char.IsAsciiLetterOrDigit(character) || character == '_')))
        {
            for (string scope = absolute ? "" : scopes.Scope;;)
            {
                string qualified = scope.Length == 0 ? target : $"{scope}::{target}";
                DocumentationTarget found = resolver.Resolve(from, $"::{qualified}", context);
                if (found.Set == analysis.Documentation && found.Name == qualified) { return found; }

                List<DocumentationComment> matching = [.. analysis.Documentation.Topics
                    .SelectMany(topic => topic.Comments)
                    .Where(comment => comment.Kind == DocumentationKind.Scope
                        && analysis.Result.SkippedLines?.IsAssembled(comment.Path, comment.TargetLine) != false
                        && analysis.ScopesAt(comment.Path, comment.TargetLine).Any(at =>
                            (at.Scope.Length == 0 ? "" : $"{at.Scope}::")
                                + comment.Name[(comment.Name.LastIndexOf(':') + 1)..] == qualified))];

                if (matching.Count == 1)
                {
                    DocumentationComment comment = matching[0];
                    DocumentationTopic topic = new()
                    {
                        Name = qualified, Kind = comment.Kind, Set = analysis.Documentation, Comments = [comment],
                        Summary = comment.Summary, Remarks = comment.Remarks, Sections = comment.Sections
                    };

                    return new(DocumentationTargetKind.Topic, qualified)
                    {
                        Topic = topic, Set = analysis.Documentation
                    };
                }

                if (matching.Count > 1) { return new(DocumentationTargetKind.Ambiguous, name); }
                if (scope.Length == 0) { break; }
                int separator = scope.LastIndexOf("::", StringComparison.Ordinal);
                scope = separator < 0 ? "" : scope[..separator];
            }
        }

        return resolver.Resolve(from, name, context);
    }

    // Whether a name is one of the definition's historical names.
    private bool IsAlso(SymbolSite site, string name)
    {
        if (_workspace.TopicOf(site) is not { } documented) { return false; }
        return documented.Topic.Set.AlsoOf(documented.Topic, site.Name).Any(also => also.Name == name);
    }

    private string Describe(SymbolSite site, (DocumentationTopic Topic, DocumentationResolver Resolver)? documented = null)
    {
        string kind = site.Kind switch
        {
            SymbolSiteKind.Label => "label",
            SymbolSiteKind.Constant => "constant",
            _ => "macro"
        };

        string value = site.Value is { } number ? $" = {LanguageHost.Hex(number)}" : "";
        string where = $"{Path.GetFileName(site.Path)}:{site.Line + 1}";
        string header = $"```\n({kind}) {site.Name}{value}\n```\n{where}";
        documented ??= _workspace.TopicOf(site);
        if (documented is { } found)
        {
            string text = DescribeTopic(found.Topic, found.Resolver);
            return text.Length == 0 ? header : $"{header}\n\n{text}";
        }

        // Without a ;; comment, the plain comment above the definition still says what it is.
        string[] lines = _workspace.LinesOf(site.Path);
        List<string> comment = SourceText.CommentFor(lines, site.Line);
        return comment.Count == 0 ? header : $"{header}\n\n{string.Join("  \n", comment)}";
    }

    private string DescribeTopic(DocumentationTopic topic, DocumentationResolver resolver) =>
        DocumentationMarkdown.Render(resolver.Effective(topic), resolver, target => _workspace.Href(target, topic.Path));

    private static string? Assembled(SourceAnalysis analysis, string path, int line)
    {
        List<AssemblySourceMapEntry> entries = [.. analysis.Emitted(path, line)];
        if (entries.Count == 0) { return null; }
        AssemblySourceMapEntry first = entries[0];
        List<string> bytes = [];
        int total = 0;
        foreach (AssemblySourceMapEntry entry in entries)
        {
            ReadOnlySpan<byte> emitted = analysis.Result.Sections[entry.Section].Bytes.Span.Slice(entry.Offset, entry.Size);
            foreach (byte value in emitted)
            {
                if (bytes.Count < MaximumBytesShown) { bytes.Add($"{value:X2}"); }
            }

            total += entry.Size;
        }

        string more = total > MaximumBytesShown ? " …" : "";
        return $"`${first.Address:X4}`: `{string.Join(' ', bytes)}{more}` ({total} byte{(total == 1 ? "" : "s")})";
    }
}
