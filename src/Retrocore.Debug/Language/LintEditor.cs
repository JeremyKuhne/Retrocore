// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.Json.Nodes;
using Retrocore.Documentation;

namespace Retrocore.Debug.Language;

/// <summary>
///  The editor's side of the documentation lint: its diagnostics with their rule IDs as codes, the quick fixes that
///  write an <c>; retrocore: ignore=</c> exclusion, the rule IDs to complete after <c>ignore=</c>, and the rule
///  under the cursor.
/// </summary>
internal static class LintEditor
{
    /// <summary>
    ///  Gets a lint diagnostic as the editor shows it, with its rule's ID as its code and its name in its data.
    /// </summary>
    /// <param name="diagnostic">The diagnostic.</param>
    /// <param name="lineRange">The range of its line, for a diagnostic that has no column.</param>
    /// <param name="replacement">
    ///  The name the preferred quick fix writes: a historical name's current name, or what a <c>.using</c> makes it.
    /// </param>
    /// <param name="alternative">A second name a quick fix may write, for a shadowed historical name.</param>
    /// <returns>The editor's diagnostic.</returns>
    internal static Diagnostic ToDiagnostic(
        DocumentationDiagnostic diagnostic,
        LspRange lineRange,
        string? replacement,
        string? alternative = null)
    {
        JsonObject data = [];
        if (diagnostic.Name is { } name) { data["name"] = name; }
        if (replacement is not null) { data["replacement"] = replacement; }
        if (alternative is not null) { data["alternative"] = alternative; }
        return new Diagnostic
        {
            Range = diagnostic.Column is int column
                ? new LspRange(diagnostic.Line, column, diagnostic.Line, column + diagnostic.Length)
                : lineRange,
            Severity = diagnostic.Severity switch
            {
                DocumentationSeverity.Error => DiagnosticSeverity.Error,
                DocumentationSeverity.Information => DiagnosticSeverity.Information,
                _ => DiagnosticSeverity.Warning
            },
            Code = diagnostic.Rule,
            Source = "retrocore docs",
            Message = diagnostic.Message,
            Data = data.Count == 0 ? null : data
        };
    }

    /// <summary>
    ///  Gets the quick fixes for diagnostics: for each use of a historical name, one that writes the current name; for
    ///  each warning or information of a rule that can be ignored, ones that write an <c>ignore=</c> exclusion for
    ///  the line (or the <c>;;</c> comment) and for the file; and for each unlinked name, ones that add it to the
    ///  workspace's or the user's dictionary through the client's <c>retrocore.lint.addUnlinkedNameWord</c> command.
    /// </summary>
    /// <param name="uri">The document.</param>
    /// <param name="lines">Its lines.</param>
    /// <param name="diagnostics">The diagnostics, as the client sends them.</param>
    /// <returns>The code actions.</returns>
    internal static JsonArray Actions(string uri, string[] lines, JsonArray diagnostics)
    {
        JsonArray actions = [];
        foreach (JsonNode? node in diagnostics)
        {
            if (node is not JsonObject diagnostic || diagnostic["range"] is not JsonObject range) { continue; }
            string? code = diagnostic["code"] is JsonValue value && value.TryGetValue(out string? text) ? text : null;
            bool renames = code is DocumentationRules.HistoricalName or DocumentationRules.UsingShadow;
            if (renames && diagnostic["data"]?["replacement"]?.GetValue<string>() is { } replacement)
            {
                JsonObject edit = new() { ["range"] = range.DeepClone(), ["newText"] = replacement };
                actions.Add((JsonNode)Action($"Use {replacement}", uri, diagnostic, [edit], preferred: true));
            }

            // A shadowed historical name may also be meant as the old name's definition.
            if (renames && diagnostic["data"]?["alternative"]?.GetValue<string>() is { } alternative)
            {
                JsonObject edit = new() { ["range"] = range.DeepClone(), ["newText"] = alternative };
                actions.Add((JsonNode)Action($"Use {alternative}", uri, diagnostic, [edit], preferred: false));
            }

            // A plain term can go in the editor's dictionary, which the client keeps in its settings.
            if (code == DocumentationRules.UnlinkedName && diagnostic["data"]?["name"]?.GetValue<string>() is { } word)
            {
                actions.Add((JsonNode)Dictionary($"Add {word} to the workspace dictionary", word, "workspace", diagnostic));
                actions.Add((JsonNode)Dictionary($"Add {word} to the user dictionary", word, "user", diagnostic));
            }

            // Errors can't be ignored (DiagnosticSeverity.Error is 1).
            bool error = diagnostic["severity"] is JsonValue severity && severity.TryGetValue(out int level) && level == 1;
            if (error || code is null || DocumentationRules.Find(code) is not { Ignorable: true } rule) { continue; }

            // A name the pragma's words can't hold, such as a link target with a space, leaves the rule whole.
            string? name = rule.TakesNames ? diagnostic["data"]?["name"]?.GetValue<string>() : null;
            if (name is not null && name.Any(character => char.IsWhiteSpace(character) || character is ',' or '|'))
            {
                name = null;
            }

            string item = name is null ? rule.Id : $"{rule.Id}:{name}";
            int line = range["start"]?["line"]?.GetValue<int>() ?? 0;
            if (Here(lines, line, item) is { } here)
            {
                actions.Add((JsonNode)Action($"Ignore {item} {here.Where}", uri, diagnostic, [here.Edit], preferred: false));
            }

            actions.Add((JsonNode)Action($"Ignore {item} in this file", uri, diagnostic, [File(lines, item)], preferred: false));
        }

        return actions;
    }

    // The client's command writes the word to the retrocore.lint.unlinkedNameWords setting.
    private static JsonObject Dictionary(string title, string word, string scope, JsonObject diagnostic) => new()
    {
        ["title"] = title,
        ["kind"] = "quickfix",
        ["diagnostics"] = new JsonArray(diagnostic.DeepClone()),
        ["command"] = new JsonObject
        {
            ["title"] = title,
            ["command"] = "retrocore.lint.addUnlinkedNameWord",
            ["arguments"] = new JsonArray(word, scope)
        }
    };

    private static JsonObject Action(string title, string uri, JsonObject diagnostic, JsonObject[] edits, bool preferred)
    {
        JsonArray list = [];
        foreach (JsonObject edit in edits) { list.Add((JsonNode)edit); }
        JsonObject changes = new() { [uri] = list };
        return new JsonObject
        {
            ["title"] = title,
            ["kind"] = "quickfix",
            ["isPreferred"] = preferred,
            ["diagnostics"] = new JsonArray(diagnostic.DeepClone()),
            ["edit"] = new JsonObject { ["changes"] = changes }
        };
    }

    /// <summary>
    ///  Gets the edit that ignores a rule where a diagnostic is: on its line of code, as the line's trailing pragma,
    ///  or for its <c>;;</c> comment, as a pragma line above the block. An existing pragma there is extended.
    /// </summary>
    /// <param name="lines">The file's lines.</param>
    /// <param name="line">The diagnostic's zero-based line.</param>
    /// <param name="item">The rule, and the name after a colon.</param>
    /// <returns>Where it applies ("on this line" or "for this comment") and the edit, or null.</returns>
    internal static (string Where, JsonObject Edit)? Here(string[] lines, int line, string item)
    {
        if (line < 0 || line >= lines.Length) { return null; }
        string text = lines[line];
        if (text.TrimStart().StartsWith(";;", StringComparison.Ordinal))
        {
            int start = line;
            while (start > 0 && lines[start - 1].TrimStart().StartsWith(";;", StringComparison.Ordinal)) { start--; }

            // Line 0's pragma is the file's.
            if (start == 0) { return null; }
            string above = lines[start - 1];
            int comment = DocumentationParser.CommentStart(above);
            if (start - 1 != 0 && comment >= 0 && above[..comment].Trim().Length == 0 && DocumentationPragma.HasIgnore(above[comment..]))
            {
                return ("for this comment", Extend(above, start - 1, comment, item));
            }

            string indent = text[..(text.Length - text.TrimStart().Length)];
            return ("for this comment", Insert(start, 0, $"{indent}{DocumentationPragma.Prefix} {DocumentationPragma.IgnoreWord}{item}\n"));
        }

        int at = DocumentationParser.CommentStart(text);
        string code = at < 0 ? text : text[..at];
        if (code.Trim().Length == 0) { return null; }
        if (at < 0)
        {
            return ("on this line", Insert(line, text.Length, $" {DocumentationPragma.Prefix} {DocumentationPragma.IgnoreWord}{item}"));
        }

        // A line's one comment is its own; a pragma there takes one more rule, and any other comment leaves no room.
        return DocumentationPragma.HasIgnore(text[at..]) ? ("on this line", Extend(text, line, at, item)) : null;
    }

    /// <summary>
    ///  Gets the edit that ignores a rule in the whole file, in its first line's pragma.
    /// </summary>
    /// <param name="lines">The file's lines.</param>
    /// <param name="item">The rule, and the name after a colon.</param>
    /// <returns>The edit.</returns>
    internal static JsonObject File(string[] lines, string item)
    {
        string first = lines.Length == 0 ? "" : lines[0];
        int at = DocumentationParser.CommentStart(first);
        return at >= 0 && first[..at].Trim().Length == 0 && DocumentationPragma.Read(first[at..]) is not null
            ? Extend(first, 0, at, item)
            : Insert(0, 0, $"{DocumentationPragma.Prefix} {DocumentationPragma.IgnoreWord}{item}\n");
    }

    /// <summary>
    ///  Gets the rule IDs to complete where the cursor is after <c>ignore=</c> or a comma in a pragma comment.
    /// </summary>
    /// <param name="before">The line up to the cursor.</param>
    /// <param name="line">The cursor's zero-based line, for the range each completion replaces.</param>
    /// <returns>The completions, or null when the cursor is not in an exclusion's list of rules.</returns>
    internal static List<CompletionItem>? Complete(string before, int line)
    {
        if (RuleListStart(before) is not int start) { return null; }

        // Past a colon come names, not rules.
        string typed = before[start..].Split(',')[^1];
        if (typed.Contains(':', StringComparison.Ordinal)) { return null; }

        // The editor's words stop at a hyphen, so each item replaces the whole of the rule typed so far.
        LspRange range = new(line, before.Length - typed.Length, line, before.Length);
        return [.. DocumentationRules.All.Where(rule => rule.Ignorable).Select(rule => new CompletionItem
        {
            Label = rule.Id,
            Kind = CompletionItemKind.Keyword,
            Detail = "lint rule",
            Documentation = new MarkupContent { Kind = MarkupKind.Markdown, Value = rule.Description },
            Range = range
        })];
    }

    /// <summary>
    ///  Gets the rule ID under a column of a pragma comment's <c>ignore=</c> list.
    /// </summary>
    /// <param name="line">The line.</param>
    /// <param name="column">The zero-based column.</param>
    /// <returns>The rule and where its ID starts, or null.</returns>
    internal static (DocumentationRule Rule, int Start)? RuleAt(string line, int column)
    {
        if (column > line.Length) { return null; }
        int start = column;
        while (start > 0 && IsRuleCharacter(line[start - 1])) { start--; }
        int end = column;
        while (end < line.Length && IsRuleCharacter(line[end])) { end++; }
        if (end == start || RuleListStart(line[..start]) is not int list) { return null; }

        // A name after a colon is not a rule.
        if (line[list..start].Split(',')[^1].Contains(':', StringComparison.Ordinal)) { return null; }
        return DocumentationRules.Find(line[start..end]) is { } rule ? (rule, start) : null;
    }

    private static bool IsRuleCharacter(char character) => char.IsAsciiLetterLower(character) || character == '-';

    // Where the list of rules starts when text ends inside one, after "ignore=" in a "; retrocore:" comment.
    private static int? RuleListStart(string before)
    {
        int at = DocumentationParser.CommentStart(before);
        if (at < 0) { return null; }
        string comment = before[at..];
        if (!comment.StartsWith(DocumentationPragma.Prefix, StringComparison.OrdinalIgnoreCase)) { return null; }
        if (comment.Contains(DocumentationPragma.ReasonSeparator, StringComparison.Ordinal)) { return null; }
        int space = comment.LastIndexOfAny([' ', '\t']);
        string word = comment[(space + 1)..];
        return word.StartsWith(DocumentationPragma.IgnoreWord, StringComparison.OrdinalIgnoreCase)
            ? at + space + 1 + DocumentationPragma.IgnoreWord.Length
            : null;
    }

    // Adds a rule to the pragma comment at a column of a line: to its ignore= word, or as a new one before the reason.
    private static JsonObject Extend(string text, int line, int comment, string item)
    {
        string pragma = text[comment..];
        int reason = pragma.IndexOf(DocumentationPragma.ReasonSeparator, StringComparison.Ordinal);
        string words = reason < 0 ? pragma : pragma[..reason];
        int position = DocumentationPragma.Prefix.Length;
        while (position < words.Length)
        {
            while (position < words.Length && char.IsWhiteSpace(words[position])) { position++; }
            int end = position;
            while (end < words.Length && !char.IsWhiteSpace(words[end])) { end++; }
            if (words[position..end].StartsWith(DocumentationPragma.IgnoreWord, StringComparison.OrdinalIgnoreCase))
            {
                bool empty = end - position == DocumentationPragma.IgnoreWord.Length;
                return Insert(line, comment + end, empty ? item : $",{item}");
            }

            position = end;
        }

        return Insert(line, comment + words.TrimEnd().Length, $" {DocumentationPragma.IgnoreWord}{item}");
    }

    private static JsonObject Insert(int line, int character, string text)
    {
        JsonObject position = new() { ["line"] = line, ["character"] = character };
        return new JsonObject
        {
            ["range"] = new JsonObject { ["start"] = position, ["end"] = position.DeepClone() },
            ["newText"] = text
        };
    }
}
