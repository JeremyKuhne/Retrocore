// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Documentation;

/// <summary>
///  Reads the <c>;;</c> documentation comments of a source file (see <c>docs/DocComments.md</c>).
/// </summary>
/// <remarks>
///  <para>
///   Parsing is textual and works for every dialect: a <c>;;</c> block documents the definition directly below
///   it (with only conditional-assembly lines between), and a trailing <c>;;</c> comment documents the
///   definition on its own line. Facts such as addresses and values come from the assembly, in
///   <c>AssemblyDocumentation</c>.
///  </para>
/// </remarks>
public static partial class DocumentationParser
{
    private const string Marker = ";;";

    // Keywords that start a free-standing topic, as in Natural Docs.
    private static readonly string[] s_topicKeywords = ["Section", "Title", "Group", "Topic", "Topics", "About"];

    /// <summary>
    ///  Parses a source file's documentation comments.
    /// </summary>
    /// <param name="text">The source text.</param>
    /// <param name="path">The source path, recorded in comments and diagnostics.</param>
    /// <returns>The comments and any placement problems.</returns>
    public static DocumentationFile Parse(string text, string path) => Parse(text, path, assembled: null);

    /// <summary>
    ///  Parses a source file's documentation comments, applying only the <c>.using</c> lines the assembler assembled.
    /// </summary>
    /// <param name="text">The source text.</param>
    /// <param name="path">The source path, recorded in comments and diagnostics.</param>
    /// <param name="assembled">What the assembler took from the file, or null when not known.</param>
    /// <returns>The comments and any placement problems.</returns>
    public static DocumentationFile Parse(string text, string path, DocumentationAssembled? assembled) =>
        Parse(text, path, assembled, style: true);

    /// <summary>
    ///  Parses a source file's documentation comments, optionally without the style checks.
    /// </summary>
    /// <param name="text">The source text.</param>
    /// <param name="path">The source path, recorded in comments and diagnostics.</param>
    /// <param name="assembled">What the assembler took from the file, or null when not known.</param>
    /// <param name="style">Whether to check a strict source against the style guide.</param>
    /// <returns>The comments and any placement problems.</returns>
    internal static DocumentationFile Parse(string text, string path, DocumentationAssembled? assembled, bool style)
    {
        string[] lines = text.Replace("\r\n", "\n").Split('\n');
        HashSet<string> dataMacros = DataMacros(lines);
        List<DocumentationComment> comments = [];
        List<DocumentationDiagnostic> diagnostics = [];
        List<(string Text, bool Not)> conditions = [];
        List<string?> containers = [];
        ScopeTracker tracker = new();
        List<string> scopes = tracker.Scopes;
        bool codeSeen = false;
        int index = 0;
        while (index < lines.Length)
        {
            string line = lines[index];
            if (line.TrimStart().StartsWith(Marker, StringComparison.Ordinal))
            {
                int start = index;
                List<(int, string)> body = [];
                while (index < lines.Length && lines[index].TrimStart().StartsWith(Marker, StringComparison.Ordinal))
                {
                    body.Add((index, Strip(lines[index])));
                    index++;
                }

                // Conditional lines may separate a comment from its definition.
                while (index < lines.Length && IsConditional(Split(lines[index]).Code))
                {
                    Condition(conditions, Split(lines[index]).Code);
                    index++;
                }

                string next = index < lines.Length ? lines[index] : "";
                string nextCode = Split(next).Code;
                bool separated = index >= lines.Length || next.Trim().Length == 0 || nextCode.Trim().Length == 0;
                if (Keyword(body) is { } keyword)
                {
                    comments.Add(Comment(
                        path,
                        start,
                        start,
                        keyword.Title,
                        DocumentationKind.Topic,
                        [.. body.Skip(1)],
                        keyword.Keyword,
                        tracker.Current.Usings));

                    continue;
                }

                if (!codeSeen && separated && comments.Count == 0)
                {
                    comments.Add(Comment(
                        path,
                        start,
                        start,
                        System.IO.Path.GetFileName(path),
                        DocumentationKind.File,
                        body,
                        keyword: null,
                        tracker.Current.Usings));

                    continue;
                }

                if (separated)
                {
                    diagnostics.Add(new(
                        "A documentation comment must be directly above the definition it documents.",
                        path,
                        start,
                        DocumentationSeverity.Error,
                        DocumentationRules.Placement));

                    continue;
                }

                // A continued scope is documented where it first opens.
                if (IsContinuedScope(nextCode))
                {
                    diagnostics.Add(new(
                        "Document a scope where it first opens; give a continued piece a plain ; comment.",
                        path,
                        start,
                        DocumentationSeverity.Error,
                        DocumentationRules.Placement));

                    continue;
                }

                if (Qualify(Define(nextCode, containers), scopes) is not { } definition)
                {
                    diagnostics.Add(new(
                        "A documentation comment must document a label, constant, macro or other definition.",
                        path,
                        start,
                        DocumentationSeverity.Error,
                        DocumentationRules.Placement));

                    continue;
                }

                // A definition documented by its own trailing comment is one of a group, and a block above the group is
                // its heading, which is a plain comment.
                if (Split(next).Comment is { } trailing && trailing.StartsWith(Marker, StringComparison.Ordinal))
                {
                    diagnostics.Add(new(
                        "A documentation comment cannot document a definition that has its own trailing documentation "
                            + "comment; write a heading above a group as a plain ; comment.",
                        path,
                        start,
                        DocumentationSeverity.Error,
                        DocumentationRules.Placement));

                    continue;
                }

                comments.Add(Documented(path, lines, start, index, definition, body, conditions, dataMacros, isTrailing: false, tracker.Current.Usings));
                continue;
            }

            (string code, string? comment) = Split(line);
            string trimmed = code.Trim();
            if (trimmed.Length != 0) { codeSeen = true; }
            if (comment is not null && comment.StartsWith(Marker, StringComparison.Ordinal) && trimmed.Length != 0)
            {
                if (Qualify(Define(code, containers), scopes) is { } definition)
                {
                    List<(int, string)> body = [(index, Strip(comment))];
                    comments.Add(Documented(path, lines, index, index, definition, body, conditions, dataMacros, isTrailing: true, tracker.Current.Usings));
                }
                else
                {
                    diagnostics.Add(new(
                        "A trailing documentation comment must follow a definition, such as a constant or member.",
                        path,
                        index,
                        DocumentationSeverity.Error,
                        DocumentationRules.Placement));
                }
            }

            if (IsConditional(trimmed))
            {
                Condition(conditions, trimmed);
            }
            else
            {
                Container(containers, trimmed);
                tracker.Advance(trimmed, index, assembled);
            }

            index++;
        }

        bool strict = IsStrict(text);
        if (strict && style) { Style(lines, path, diagnostics); }

        // Without the style checks this is not the lint, so there is nothing for exclusions to apply to.
        List<DocumentationExclusion> exclusions = style ? Exclusions(lines, path, diagnostics) : [];
        return new(path, comments, diagnostics) { Strict = strict, Exclusions = exclusions };
    }

    /// <summary>
    ///  Follows a source's scopes and <c>.using</c> directives, so a name on a line can be looked up as the assembler
    ///  would look it up there.
    /// </summary>
    /// <param name="lines">The source's lines.</param>
    /// <returns>For each line, the scope it is in and the <c>.using</c> directives in effect on it.</returns>
    public static IReadOnlyList<DocumentationScopes> ScopesByLine(IReadOnlyList<string> lines) =>
        ScopesByLine(lines, assembled: null);

    /// <summary>
    ///  Follows a source's scopes and the <c>.using</c> directives the assembler assembled.
    /// </summary>
    /// <param name="lines">The source's lines.</param>
    /// <param name="assembled">What the assembler took from the file, or null when not known.</param>
    /// <returns>For each line, the scope it is in and the <c>.using</c> directives in effect on it.</returns>
    public static IReadOnlyList<DocumentationScopes> ScopesByLine(IReadOnlyList<string> lines, DocumentationAssembled? assembled)
    {
        ScopeTracker tracker = new();
        DocumentationScopes[] result = new DocumentationScopes[lines.Count];
        for (int index = 0; index < lines.Count; index++)
        {
            result[index] = tracker.Current;
            string trimmed = Split(lines[index]).Code.Trim();
            if (trimmed.Length != 0 && !IsConditional(trimmed))
            {
                tracker.Advance(trimmed, index, assembled);
            }
        }

        return result;
    }

    /// <summary>
    ///  Parses a documentation text file for <c>Include:</c>: topics in Natural Docs form, each starting with a
    ///  keyword line such as <c>Routine: Name</c> or <c>Topic: Name</c>.
    /// </summary>
    /// <param name="text">The file's text.</param>
    /// <param name="path">Its path.</param>
    /// <returns>The topics, named by their titles.</returns>
    public static IReadOnlyList<DocumentationComment> ParseTopics(string text, string path)
    {
        string[] lines = text.Replace("\r\n", "\n").Split('\n');
        List<DocumentationComment> topics = [];
        (string Keyword, string Title, int Line)? current = null;
        List<(int, string)> body = [];
        for (int index = 0; index <= lines.Length; index++)
        {
            (string, string)? heading = index < lines.Length ? TextKeyword(lines[index]) : null;
            if (index < lines.Length && heading is null)
            {
                if (current is not null) { body.Add((index, lines[index])); }
                continue;
            }

            if (current is { } open)
            {
                topics.Add(Comment(path, open.Line, open.Line, open.Title, DocumentationKind.Topic, body, open.Keyword, usings: []));
            }

            body = [];
            current = heading is { } found ? (found.Item1, found.Item2, index) : null;
        }

        return topics;
    }

    // Keywords a documentation text file may start a topic with.
    private static (string Keyword, string Title)? TextKeyword(string line)
    {
        int colon = line.IndexOf(':');
        if (colon <= 0 || char.IsWhiteSpace(line[0])) { return null; }
        string keyword = line[..colon].Trim();
        string title = line[(colon + 1)..].Trim();
        string[] keywords = [.. s_topicKeywords, "Routine", "Function", "Table", "Constant", "Constants", "Variable", "Macro", "Enum", "Struct", "File"];
        foreach (string candidate in keywords)
        {
            if (candidate.Equals(keyword, StringComparison.OrdinalIgnoreCase) && title.Length != 0)
            {
                return (candidate, title);
            }
        }

        return null;
    }

    private static DocumentationComment Documented(
        string path,
        string[] lines,
        int start,
        int target,
        Definition definition,
        List<(int Line, string Text)> body,
        List<(string Text, bool Not)> conditions,
        HashSet<string> dataMacros,
        bool isTrailing,
        IReadOnlyList<DocumentationUsing> usings)
    {
        DocumentationKind kind = definition.Kind;
        List<string> aliases = [];
        if (kind == DocumentationKind.Routine)
        {
            // A label after a .proc line is inside the procedure, not another name stacked on it.
            bool procedure = Split(lines[target]).Code.TrimStart().StartsWith(".proc", StringComparison.OrdinalIgnoreCase);
            kind = LabelKind(lines, target, definition.Rest, dataMacros, procedure ? [] : aliases)
                ? DocumentationKind.Table
                : DocumentationKind.Routine;
        }

        (string summary, List<string> remarks, List<DocumentationSection> sections) = Body(body);
        return new DocumentationComment
        {
            Path = path,
            Line = start,
            TargetLine = target,
            Name = definition.Name,
            Kind = kind,
            Summary = summary,
            Remarks = remarks,
            Sections = sections,
            Aliases = aliases,
            Parameters = definition.Parameters,
            Members = kind is DocumentationKind.Enum or DocumentationKind.Struct ? Members(lines, target) : [],
            Condition = ConditionText(conditions),
            IsTrailing = isTrailing,
            Usings = usings
        };
    }

    private static DocumentationComment Comment(
        string path,
        int start,
        int target,
        string name,
        DocumentationKind kind,
        List<(int Line, string Text)> body,
        string? keyword,
        IReadOnlyList<DocumentationUsing> usings)
    {
        (string summary, List<string> remarks, List<DocumentationSection> sections) = Body(body);
        return new DocumentationComment
        {
            Path = path,
            Line = start,
            TargetLine = target,
            Name = name,
            Kind = kind,
            Keyword = keyword,
            Summary = summary,
            Remarks = remarks,
            Sections = sections,
            Usings = usings
        };
    }

    /// <summary>
    ///  Decides whether a label is data, and collects the labels stacked directly below it.
    /// </summary>
    private static bool LabelKind(string[] lines, int target, string rest, HashSet<string> dataMacros, List<string> aliases)
    {
        if (rest.Length != 0) { return IsData(rest, dataMacros); }
        bool stacked = true;
        for (int index = target + 1; index < lines.Length; index++)
        {
            string code = Split(lines[index]).Code;
            string trimmed = code.Trim();
            if (trimmed.Length == 0)
            {
                stacked = false;
                continue;
            }

            if (IsConditional(trimmed)) { continue; }
            if (LabelOnly(code) is { } label)
            {
                if (stacked) { aliases.Add(label); }
                continue;
            }

            stacked = false;
            int length = IdentifierLength(trimmed);
            bool labeled = length != 0 && trimmed.Length > length && trimmed[length] == ':';
            return IsData(labeled ? trimmed[(length + 1)..].TrimStart(':') : trimmed, dataMacros);
        }

        return false;
    }

    // Macros whose body starts with data make the labels they follow tables.
    private static HashSet<string> DataMacros(string[] lines)
    {
        HashSet<string> macros = [with(StringComparer.OrdinalIgnoreCase)];
        List<string?> none = [];
        for (int index = 0; index < lines.Length; index++)
        {
            if (Define(Split(lines[index]).Code, none) is not { Kind: DocumentationKind.Macro } macro) { continue; }
            for (int body = index + 1; body < lines.Length; body++)
            {
                string code = Split(lines[body]).Code.Trim();
                if (code.Length == 0 || IsConditional(code)) { continue; }
                if (IsData(code, macros)) { macros.Add(macro.Name); }
                break;
            }
        }

        return macros;
    }

    private static List<string> Members(string[] lines, int target)
    {
        List<string> members = [];
        int depth = 0;
        for (int index = target + 1; index < lines.Length; index++)
        {
            string code = Split(lines[index]).Code.Trim();
            string word = FirstWord(code).ToLowerInvariant();
            if (word is ".endenum" or ".endstruct" or ".endunion")
            {
                if (depth == 0) { break; }
                depth--;
                continue;
            }

            if (word is ".enum" or ".struct" or ".union")
            {
                depth++;
                continue;
            }

            int length = IdentifierLength(code);
            if (depth == 0 && length != 0 && !code.StartsWith('.')) { members.Add(code[..length]); }
        }

        return members;
    }

    // Whether a line is ".scope Name continued", which goes on with a scope opened earlier.
    private static bool IsContinuedScope(string code)
    {
        string[] words = code.Split([' ', '\t'], StringSplitOptions.RemoveEmptyEntries);
        return words.Length == 3
            && words[0].Equals(".scope", StringComparison.OrdinalIgnoreCase)
            && words[2].Equals("continued", StringComparison.OrdinalIgnoreCase);
    }

    // Names inside .proc and .scope are qualified by them, as the assembler qualifies their symbols.
    private static Definition? Qualify(Definition? definition, List<string> scopes) =>
        definition is null || scopes.Count == 0 || definition.Kind is DocumentationKind.Macro or DocumentationKind.Definition
            ? definition
            : definition with { Name = $"{string.Join("::", scopes)}::{definition.Name}" };

    private static void Container(List<string?> containers, string code)
    {
        string word = FirstWord(code).ToLowerInvariant();
        if (word is ".enum" or ".struct" or ".union")
        {
            string name = FirstWord(code[word.Length..].Trim());
            containers.Add(name.Length == 0 ? null : name);
        }
        else if (word is ".endenum" or ".endstruct" or ".endunion" && containers.Count != 0)
        {
            containers.RemoveAt(containers.Count - 1);
        }
    }

    private static void Condition(List<(string Text, bool Not)> conditions, string code)
    {
        string trimmed = code.Trim();
        string word = FirstWord(trimmed).ToLowerInvariant();
        string operand = trimmed[word.Length..].Trim();
        switch (word)
        {
            case ".endif":
                if (conditions.Count != 0) { conditions.RemoveAt(conditions.Count - 1); }
                break;
            case ".else":
                if (conditions.Count != 0) { conditions[^1] = (conditions[^1].Text, !conditions[^1].Not); }
                break;
            case ".elseif":
                if (conditions.Count != 0) { conditions[^1] = Test(operand); }
                break;
            case ".ifdef":
                conditions.Add(($"defined {operand}", false));
                break;
            case ".ifndef":
                conditions.Add(($"defined {operand}", true));
                break;
            default:
                conditions.Add(word == ".if" ? Test(operand) : ($"{word[1..]} {operand}".Trim(), false));
                break;
        }
    }

    private static (string Text, bool Not) Test(string operand) =>
        operand.StartsWith(".not ", StringComparison.OrdinalIgnoreCase)
            ? (operand[5..].Trim(), true)
            : operand.StartsWith('!') ? (operand[1..].Trim(), true) : (operand, false);

    private static string? ConditionText(List<(string Text, bool Not)> conditions) =>
        conditions.Count == 0 ? null : string.Join(" and ", conditions.Select(item => item.Not ? $"not {item.Text}" : item.Text));

    private static (string Keyword, string Title)? Keyword(List<(int Line, string Text)> body)
    {
        string first = body.Count == 0 ? "" : body[0].Text.Trim();
        int colon = first.IndexOf(':');
        if (colon <= 0) { return null; }
        string keyword = first[..colon].Trim();
        string title = first[(colon + 1)..].Trim();
        foreach (string candidate in s_topicKeywords)
        {
            if (candidate.Equals(keyword, StringComparison.OrdinalIgnoreCase) && title.Length != 0)
            {
                return (candidate, title);
            }
        }

        return null;
    }

    // The text after ";;" and one space.
    private static string Strip(string line)
    {
        string text = line.TrimStart();
        text = text[Marker.Length..];
        return text.StartsWith(' ') ? text[1..] : text;
    }
}
