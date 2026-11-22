// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Documentation;

public static partial class DocumentationParser
{
    /// <summary>
    ///  The widest a line may be in a file that follows the style guide.
    /// </summary>
    public const int StyleLineLength = 120;

    private const int StyleIndent = 4;

    // The prefixes a disassembler puts before an address to make a name: L_F8C2, LF8C2, SUB_D253, D_0E50.
    private static readonly string[] s_addressPrefixes = ["L", "D", "V", "SUB", "LOC", "LAB", "DAT", "unref"];

    // The directives that emit data, which sit with the instructions.
    private static readonly string[] s_dataDirectives =
    [
        ".byte", ".word", ".res", ".dbyt", ".dword", ".asciiz", ".hiascii", ".addr", ".lobytes", ".hibytes",
        ".faraddr", ".byt", ".dw", ".db"
    ];

    // The directives that open or close a routine, family or macro, which sit at column 0.
    private static readonly string[] s_blockDirectives =
    [
        ".proc", ".endproc", ".scope", ".endscope", ".macro", ".endmacro", ".struct", ".endstruct", ".union", ".endunion",
        ".enum", ".endenum"
    ];

    // The lines that end a block, before which a comment may describe the code it follows.
    private static readonly string[] s_blockEnds =
    [
        ".endproc", ".endscope", ".endmacro", ".endrepeat", ".endif", ".else", ".endstruct", ".endunion", ".endenum"
    ];

    /// <summary>
    ///  Gets whether a source opts in to the style guide's checks, with <c>; retrocore: style=strict</c> on its
    ///  first line.
    /// </summary>
    /// <param name="text">The source text.</param>
    /// <returns>Whether it is checked.</returns>
    public static bool IsStrict(string text)
    {
        int end = text.IndexOfAny(['\r', '\n']);
        string first = (end < 0 ? text : text[..end]).Trim();
        return first.StartsWith("; retrocore:", StringComparison.OrdinalIgnoreCase) && first["; retrocore:".Length..]
            .Split([' ', '\t'], StringSplitOptions.RemoveEmptyEntries)
            .Any(word => word.Equals("style=strict", StringComparison.OrdinalIgnoreCase));
    }

    // The style guide's line rules (docs/AssemblyStyle.md): layout, labels, names and plain text.
    private static void Style(string[] lines, string path, List<DocumentationDiagnostic> diagnostics)
    {
        void Warn(string message, int line) => diagnostics.Add(new(message, path, line, DocumentationSeverity.Warning));

        bool inMacro = false;
        int macroDepth = 0;

        // How many types are open: a type's members are one level in, and each nested type's one more.
        int typeDepth = 0;
        for (int index = 1; index < lines.Length; index++)
        {
            string line = lines[index];
            if (line.Length > StyleLineLength) { Warn($"Line is over {StyleLineLength} columns.", index); }
            if (line.Any(character => character > '\x7F'))
            {
                Warn("Write plain ASCII: 'times' rather than a multiplication sign, '-' rather than a dash.", index);
            }

            (string code, string? comment) = Split(line);
            string trimmed = code.Trim();
            int indent = code.Length - code.TrimStart().Length;
            if (trimmed.Length == 0)
            {
                if (comment is not null) { CommentIndent(lines, index, indent, inMacro, Warn); }
                continue;
            }

            // A member of a type may have a trailing ;; comment instead of a block above it; a type's own lines may not.
            (_, string typeDirective, _) = TypeLine(trimmed);
            if (comment is not null && comment.StartsWith(Marker, StringComparison.Ordinal) && (typeDepth == 0 || typeDirective.Length != 0))
            {
                Warn("Put ;; documentation above the definition, not after it.", index);
            }

            // A label with code after it is one problem, not also the code's indentation.
            if (LabelWithCode(trimmed) is { } labeled)
            {
                Warn($"Put the label {labeled} on its own line.", index);
                continue;
            }

            string? defined = DefinedName(trimmed);

            if (defined is not null && IsAddressName(defined))
            {
                Warn($"Name {defined} for what it is: a name that is only an address says nothing.", index);
            }

            string directive = Directive(trimmed);
            if (directive is ".endmacro") { inMacro = false; }

            // Inside a macro, each body is one level in, and a .repeat or .if body one more.
            if (inMacro)
            {
                if (directive is ".endrepeat" or ".endif" or ".else" or ".elseif") { macroDepth--; }
                int expected = StyleIndent * (1 + macroDepth);
                bool label = IsLabelOnly(trimmed);
                if (indent != expected && !(label && indent == 0))
                {
                    Warn($"Indent this line of the macro {expected} columns.", index);
                }

                if (directive is ".repeat" or ".else" or ".elseif" || directive.StartsWith(".if", StringComparison.Ordinal))
                {
                    macroDepth++;
                }

                continue;
            }

            if (directive is ".macro")
            {
                inMacro = true;
                macroDepth = 0;
            }

            // Inside a type, each member is one level in, and a nested type's .struct or .union line is at its
            // parent's member level, with its own members one more.
            bool opens = typeDirective is ".struct" or ".union" or ".enum";
            bool closes = typeDirective is ".endstruct" or ".endunion" or ".endenum";
            if (closes && typeDepth != 0) { typeDepth--; }
            if (typeDepth != 0)
            {
                int expected = StyleIndent * typeDepth;
                if (indent != expected)
                {
                    Warn($"Indent this line {expected} columns: a type's members one level in, a nested type's one more.", index);
                }
            }

            // A cheap-local or anonymous label is a label too, though it defines no name of its own.
            else if (s_blockDirectives.Contains(directive) || defined is not null || IsLabelOnly(trimmed))
            {
                if (indent != 0) { Warn("Put definitions, labels and block directives at column 0.", index); }
            }
            else if (directive.Length == 0 || s_dataDirectives.Contains(directive))
            {
                if (indent != StyleIndent) { Warn($"Indent instructions and data {StyleIndent} columns.", index); }
            }

            if (opens) { typeDepth++; }
        }
    }

    // A comment line is indented like the code it describes: the next line of code, the line after a label, or,
    // before the end of a block, the code it follows.
    private static void CommentIndent(string[] lines, int index, int indent, bool inMacro, Action<string, int> warn)
    {
        int next = index + 1;
        while (next < lines.Length && Split(lines[next]).Code.Trim().Length == 0)
        {
            // A blank line ends what the comment describes.
            if (lines[next].Trim().Length == 0) { return; }
            next++;
        }

        if (next >= lines.Length) { return; }
        HashSet<int> allowed = [Indentation(lines[next])];
        string code = Split(lines[next]).Code.Trim();

        // Before a conditional directive, the comment may also describe the code the condition chooses: the first line
        // after the directives that is not one.
        if (IsConditionalDirective(code) && CodeAfterConditionals(lines, next) is int chosen)
        {
            allowed.Add(Indentation(lines[chosen]));
        }

        if (IsLabelOnly(code) && next + 1 < lines.Length && Split(lines[next + 1]).Code.Trim().Length != 0)
        {
            allowed.Add(Indentation(lines[next + 1]));
        }

        if (s_blockEnds.Contains(Directive(code)))
        {
            for (int previous = index - 1; previous >= 0; previous--)
            {
                if (Split(lines[previous]).Code.Trim().Length == 0) { continue; }
                allowed.Add(Indentation(lines[previous]));
                break;
            }
        }

        if (inMacro && allowed.Count == 0) { return; }
        if (!allowed.Contains(indent))
        {
            warn($"Indent this comment like the code it describes ({string.Join(" or ", allowed.OrderBy(column => column))} columns).", index);
        }
    }

    // The name a line defines: a block's (.proc Name), a constant's (Name = value) or a label's (Name:).
    private static string? DefinedName(string code)
    {
        string directive = Directive(code);
        if (directive is ".proc" or ".scope" or ".macro" or ".struct" or ".enum")
        {
            string rest = code[directive.Length..].TrimStart();
            int length = IdentifierLength(rest, 0);
            return length == 0 ? null : rest[..length];
        }

        int end = IdentifierLength(code, 0);
        if (end == 0) { return null; }
        string after = code[end..].TrimStart();
        bool constant = after.StartsWith('=') && !after.StartsWith("==", StringComparison.Ordinal);
        bool variable = after.StartsWith(".set", StringComparison.OrdinalIgnoreCase);
        return constant || variable || IsLabelOnly(code) ? code[..end] : null;
    }

    // A label followed by code on the same line, such as "Loop: lda (Pointer),y": the label, or null.
    private static string? LabelWithCode(string code)
    {
        int end = LabelLength(code);
        if (end < 0 || end >= code.Length || code[end] != ':' || (end == 0 && code.StartsWith("::", StringComparison.Ordinal)))
        {
            return null;
        }

        string rest = code[(end + 1)..];
        return rest.Length != 0 && rest[0] != ':' && rest.Trim().Length != 0 ? code[..(end == 0 ? 1 : end)] : null;
    }

    private static bool IsLabelOnly(string code)
    {
        // An anonymous label is a ':' alone.
        int end = LabelLength(code);
        return end >= 0 && end == code.Length - 1 && code[end] == ':';
    }

    // The length of a label's name at a line's start: an ordinary or cheap-local (@) name, or 0 for an anonymous ':'.
    private static int LabelLength(string code)
    {
        if (!code.StartsWith('@')) { return IdentifierLength(code, 0); }
        int length = IdentifierLength(code, 1);
        return length == 0 ? -1 : length + 1;
    }

    // Whether a name is only an address, as a disassembler makes it.
    private static bool IsAddressName(string name)
    {
        string rest = name.StartsWith("B2_", StringComparison.Ordinal) ? name[3..] : name;
        foreach (string prefix in s_addressPrefixes)
        {
            if (!rest.StartsWith(prefix, StringComparison.Ordinal)) { continue; }
            string address = rest[prefix.Length..];
            bool separated = address.StartsWith('_');
            if (separated) { address = address[1..]; }

            // A one-letter prefix before four hex letters can be a word (LACED, DECAF): without the separator, an
            // address has a digit.
            bool word = prefix.Length == 1 && !separated && !address.Any(char.IsAsciiDigit);
            if (address.Length == 4 && address.All(Uri.IsHexDigit) && !word) { return true; }
        }

        return false;
    }

    // The length of the identifier at a position, or 0.
    private static int IdentifierLength(string text, int start)
    {
        if (start >= text.Length || !(char.IsAsciiLetter(text[start]) || text[start] == '_')) { return 0; }
        int end = start + 1;
        while (end < text.Length && (char.IsAsciiLetterOrDigit(text[end]) || text[end] == '_')) { end++; }
        return end - start;
    }

    private static bool IsConditionalDirective(string code)
    {
        string directive = Directive(code);
        return directive.StartsWith(".if", StringComparison.Ordinal) || directive is ".else" or ".elseif" or ".endif";
    }

    // The first line of code after a run of conditional directives, or null.
    private static int? CodeAfterConditionals(string[] lines, int start)
    {
        for (int index = start; index < lines.Length; index++)
        {
            string code = Split(lines[index]).Code.Trim();
            if (code.Length == 0) { return null; }
            if (!IsConditionalDirective(code)) { return index; }
        }

        return null;
    }

    private static int Indentation(string line)
    {
        string code = Split(line).Code;
        return code.Length - code.TrimStart().Length;
    }

    // The directive a line starts with, in lower case, or empty.
    private static string Directive(string code)
    {
        if (code.Length == 0 || code[0] != '.') { return ""; }
        int end = 1;
        while (end < code.Length && (char.IsLetterOrDigit(code[end]) || code[end] == '_')) { end++; }
        return code[..end].ToLowerInvariant();
    }
}
