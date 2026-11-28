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
    internal static DocumentationFile Parse(string text, string path, DocumentationAssembled? assembled, bool style) =>
        Parse(Lines(text), path, assembled, style);

    /// <summary>
    ///  Parses a source file's documentation comments from its lines, as <see cref="Lines(string)"/> splits them.
    /// </summary>
    /// <param name="lines">The source's lines, which are only read.</param>
    /// <param name="path">The source path, recorded in comments and diagnostics.</param>
    /// <param name="assembled">What the assembler took from the file, or null when not known.</param>
    /// <param name="style">Whether to check a strict source against the style guide.</param>
    /// <param name="historicalNamesOnly">Whether to skip comments that cannot supply a historical name.</param>
    /// <returns>The comments and any placement problems.</returns>
    internal static DocumentationFile Parse(
        string[] lines, string path, DocumentationAssembled? assembled, bool style, bool historicalNamesOnly = false)
    {
        List<(int Line, string Name)> macros = MacroDefinitions(lines);
        HashSet<string> dataMacros = DataMacros(lines, macros);
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
            if (IsDocumentationLine(line))
            {
                int start = index;
                // Before the first code, keep the full comment sequence: it decides whether a block is file documentation.
                bool candidate = !historicalNamesOnly || !codeSeen;
                do
                {
                    candidate = candidate || lines[index].Contains("Also", StringComparison.OrdinalIgnoreCase);
                    index++;
                }
                while (index < lines.Length && IsDocumentationLine(lines[index]));

                int end = index;
                // Conditional lines may separate a comment from its definition.
                while (index < lines.Length && IsConditional(lines[index].AsSpan(0, CodeLength(lines[index]))))
                {
                    Condition(conditions, Split(lines[index]).Code);
                    index++;
                }

                if (!candidate) { continue; }
                List<(int, string)> body = [with(capacity: end - start)];
                for (int row = start; row < end; row++) { body.Add((row, Strip(lines[row]))); }

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

                comments.Add(Documented(path, lines, start, index, definition, body, conditions, dataMacros, isTrailing: false, tracker));
                continue;
            }

            // Read in place: most lines document nothing, so only a trailing ;; comment's line is copied out.
            int codeLength = CodeLength(line);
            ReadOnlySpan<char> trimmed = line.AsSpan(0, codeLength).Trim();
            if (trimmed.Length != 0) { codeSeen = true; }
            bool trailingMarker = codeLength + 1 < line.Length && line[codeLength + 1] == ';';
            if (trailingMarker
                && trimmed.Length != 0
                && (!historicalNamesOnly || line.AsSpan(codeLength).Contains("Also", StringComparison.OrdinalIgnoreCase)))
            {
                if (Qualify(Define(line[..codeLength], containers), scopes) is { } definition)
                {
                    List<(int, string)> body = [(index, Strip(line[codeLength..]))];
                    comments.Add(Documented(path, lines, index, index, definition, body, conditions, dataMacros, isTrailing: true, tracker));
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
                Condition(conditions, trimmed.ToString());
            }
            else
            {
                Container(containers, trimmed);
                tracker.Advance(trimmed, index, assembled);
            }

            index++;
        }

        bool strict = IsStrict(lines);
        if (strict && style) { Style(lines, path, diagnostics); }

        // Without the style checks this is not the lint, so there is nothing for exclusions to apply to.
        List<DocumentationExclusion> exclusions = style ? Exclusions(lines, path, diagnostics) : [];
        return new(path, comments, diagnostics)
        {
            Strict = strict,
            Exclusions = exclusions,
            Macros = MacroNames(macros)
        };
    }

    // The macros a source defines, in any dialect, in source order with their lines. Only a line that writes .macro,
    // .mac, Merlin's MAC or MACRO-10's DEFINE defines one, and each has "mac" or "define" in it, so no other line need
    // be classified.
    private static List<(int Line, string Name)> MacroDefinitions(string[] lines)
    {
        List<(int Line, string Name)> macros = [];
        List<string?> none = [];
        for (int index = 0; index < lines.Length; index++)
        {
            string line = lines[index];
            bool candidate = line.IndexOf("mac", StringComparison.OrdinalIgnoreCase) >= 0
                || line.IndexOf("define", StringComparison.OrdinalIgnoreCase) >= 0;

            if (candidate && Define(Split(line).Code, none) is { Kind: DocumentationKind.Macro } macro)
            {
                macros.Add((index, macro.Name));
            }
        }

        return macros;
    }

    private static List<string> MacroNames(List<(int Line, string Name)> macros)
    {
        List<string> names = [with(capacity: macros.Count)];
        foreach ((_, string name) in macros) { names.Add(name); }
        return names;
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
            string line = lines[index];
            ReadOnlySpan<char> trimmed = line.AsSpan(0, CodeLength(line)).Trim();
            if (trimmed.Length != 0 && !IsConditional(trimmed))
            {
                tracker.Advance(trimmed, index, assembled);
            }
        }

        return result;
    }

    /// <summary>
    ///  Splits a source's text into lines without their terminators, as the parser reads them.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   Only CRLF and LF end a line; a lone CR stays in its line. A terminating newline leaves an empty last line.
    ///  </para>
    /// </remarks>
    /// <param name="text">The text.</param>
    /// <returns>The lines.</returns>
    internal static string[] Lines(string text)
    {
        // As text.Replace("\r\n", "\n").Split('\n') splits it, without copying the whole text first: each line ends at
        // a LF, less the one CR before it.
        int count = 1;
        for (int at = text.IndexOf('\n'); at >= 0; at = text.IndexOf('\n', at + 1)) { count++; }

        string[] lines = new string[count];
        int start = 0;
        int line = 0;
        for (int at = text.IndexOf('\n'); at >= 0; at = text.IndexOf('\n', start))
        {
            int end = at > start && text[at - 1] == '\r' ? at - 1 : at;
            lines[line++] = text[start..end];
            start = at + 1;
        }

        lines[line] = text[start..];
        return lines;
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
        string[] lines = Lines(text);
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
        ScopeTracker tracker)
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
        (bool parameter, bool local) = tracker.Varies(definition.Name);
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
            Usings = tracker.Current.Usings,
            Macro = tracker.Macro,
            MacroLine = tracker.MacroLine,
            NamedByParameter = parameter,
            LocalToExpansion = local
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
    private static HashSet<string> DataMacros(string[] lines, List<(int Line, string Name)> definitions)
    {
        HashSet<string> macros = [with(StringComparer.OrdinalIgnoreCase)];
        foreach ((int index, string name) in definitions)
        {
            for (int body = index + 1; body < lines.Length; body++)
            {
                string code = Split(lines[body]).Code.Trim();
                if (code.Length == 0 || IsConditional(code)) { continue; }
                if (IsData(code, macros)) { macros.Add(name); }
                break;
            }
        }

        return macros;
    }

    // A type's members: its own, and those of the anonymous types nested in it, which the assembler puts in the
    // type's scope. A named nested type is a member (by its member's name when one opens it), and its own members are
    // in its scope.
    private static List<string> Members(string[] lines, int target)
    {
        List<string> members = [];

        // For each nested type open, whether it is named, and how many are.
        List<bool> nested = [];
        int named = 0;
        for (int index = target + 1; index < lines.Length; index++)
        {
            string code = Split(lines[index]).Code.Trim();
            (string? member, string word, string name) = TypeLine(code);
            bool direct = named == 0;
            if (word is ".endenum" or ".endstruct" or ".endunion")
            {
                if (nested.Count == 0) { break; }
                if (nested[^1]) { named--; }
                nested.RemoveAt(nested.Count - 1);
                continue;
            }

            if (word is ".enum" or ".struct" or ".union")
            {
                if (direct && member is not null) { members.Add(member); }
                if (direct && member is null && name.Length != 0) { members.Add(name); }
                nested.Add(name.Length != 0);
                if (name.Length != 0) { named++; }
                continue;
            }

            int length = IdentifierLength(code);
            if (direct && length != 0 && !code.StartsWith('.')) { members.Add(code[..length]); }
        }

        return members;
    }

    // Whether code can be a type directive. Each has "enum", "struct" or "union" in it, so a line without them is not
    // one; most lines aren't. No character other than ASCII's lowers to these letters, so ignoring case here finds
    // every line TypeLine's lowered comparison does.
    private static bool IsTypeCandidate(ReadOnlySpan<char> code) =>
        code.IndexOf("enum".AsSpan(), StringComparison.OrdinalIgnoreCase) >= 0
            || code.IndexOf("struct".AsSpan(), StringComparison.OrdinalIgnoreCase) >= 0
            || code.IndexOf("union".AsSpan(), StringComparison.OrdinalIgnoreCase) >= 0;

    // A line's type directive, in lower case, with the member it may name first ("WHERE .struct") and the type's name
    // after it; the directive is empty on any other line.
    private static (string? Member, string Directive, string Name) TypeLine(string code)
    {
        if (!IsTypeCandidate(code.AsSpan())) { return (null, "", ""); }
        string first = FirstWord(code);
        string? member = null;
        string rest = code[first.Length..].Trim();
        if (!first.StartsWith('.') && IdentifierLength(first) == first.Length && rest.StartsWith('.'))
        {
            member = first;
            first = FirstWord(rest);
            rest = rest[first.Length..].Trim();
        }

        string word = first.ToLowerInvariant();
        return word is ".enum" or ".struct" or ".union" or ".endenum" or ".endstruct" or ".endunion"
            ? (member, word, FirstWord(rest))
            : (null, "", "");
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

    // Container for code read in place, copied only when it can be a type directive, as TypeLine tells.
    private static void Container(List<string?> containers, ReadOnlySpan<char> code)
    {
        if (IsTypeCandidate(code)) { Container(containers, code.ToString()); }
    }

    private static void Container(List<string?> containers, string code)
    {
        (_, string word, string name) = TypeLine(code);
        if (word is ".enum" or ".struct" or ".union")
        {
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
