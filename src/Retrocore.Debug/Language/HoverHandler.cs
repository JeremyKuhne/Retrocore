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
        if (line >= lines.Length || SourceText.WordAt(lines[line], request.Position.Character) is not { } word)
        {
            return Task.FromResult(none);
        }

        SourceAnalysis? analysis = _workspace.AnalysisOf(path);
        if (FlagAt(analysis, lines, path, line, request.Position.Character) is { } flag)
        {
            return Task.FromResult<Hover?>(flag);
        }

        List<string> parts = [];
        bool operation = SourceText.IsOperation(lines[line][..word.Start]);
        // A line whose bytes a macro of that name wrote is the macro's, whatever .cpu the text before it shows: p-code's
        // LDA is Pcode.asm's macro, even where the .cpu Pcode that owns it is in that include.
        bool expanded = operation
            && analysis?.ExpandsMacro(path, line) == true
            && analysis.Find(word.Word).Any(site => site.Kind == SymbolSiteKind.Macro);

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
            parts.Add(Describe(sites[0]));
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

    // A flag's word in a ;; comment, as "Out: carry = found" names it: the word, the CPU's letter and its meaning.
    private static Hover? FlagAt(SourceAnalysis? analysis, string[] lines, string path, int line, int column)
    {
        string text = lines[line];
        int comment = text.IndexOf(";;", StringComparison.Ordinal);
        if (comment < 0 || column <= comment + 1) { return null; }

        // Words are letters joined by hyphens, as in half-carry.
        int start = Math.Min(column, text.Length);
        while (start > comment + 2 && (char.IsAsciiLetter(text[start - 1]) || text[start - 1] == '-')) { start--; }
        int end = Math.Min(column, text.Length);
        while (end < text.Length && (char.IsAsciiLetter(text[end]) || text[end] == '-')) { end++; }
        string word = text[start..end].Trim('-');
        if (word.Length == 0) { return null; }
        start = text.IndexOf(word, start, StringComparison.Ordinal);

        IsaDescription cpu = analysis?.Documentation.CpuAt(path, line) ?? SourceText.InstructionSetOf(lines, line).Description;
        if (DocumentationCpu.For(cpu).Flag(word) is not { } flag) { return null; }
        return new Hover
        {
            Contents = new MarkupContent { Kind = MarkupKind.Markdown, Value = DocumentationCpu.Describe(word, flag) },
            Range = new LspRange(line, start, line, start + word.Length)
        };
    }

    private string Describe(SymbolSite site)
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
        if (_workspace.TopicOf(site) is { } documented)
        {
            string text = DocumentationMarkdown.Render(documented.Topic, documented.Resolver, _workspace.Href);
            return text.Length == 0 ? header : $"{header}\n\n{text}";
        }

        // Without a ;; comment, the plain comment above the definition still says what it is.
        string[] lines = _workspace.LinesOf(site.Path);
        List<string> comment = SourceText.CommentFor(lines, site.Line);
        return comment.Count == 0 ? header : $"{header}\n\n{string.Join("  \n", comment)}";
    }

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
