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
    public static bool IsStrict(string text) => ReadPragma(text)?.Strict == true;

    // IsStrict from the lines Lines splits: they end at CRLF and LF, and the pragma's line ends at a lone CR too.
    private static bool IsStrict(string[] lines)
    {
        string first = lines.Length == 0 ? "" : lines[0];
        int end = first.IndexOf('\r');
        return DocumentationPragma.Read(end < 0 ? first : first[..end])?.Strict == true;
    }

    // The style guide's line rules (docs/AssemblyStyle.md): layout, labels, names and plain text.
    private static void Style(string[] lines, string path, List<DocumentationDiagnostic> diagnostics)
    {
        void Warn(string rule, string message, int line, string? name = null)
        {
            diagnostics.Add(new(message, path, line, DocumentationSeverity.Warning, rule) { Name = name });
        }

        bool inMacro = false;
        int macroDepth = 0;

        // How many types are open: a type's members are one level in, and each nested type's one more.
        int typeDepth = 0;
        for (int index = 1; index < lines.Length; index++)
        {
            string line = lines[index];
            if (line.Length > StyleLineLength)
            {
                Warn(DocumentationRules.LineLength, $"Line is over {StyleLineLength} columns.", index);
            }

            if (!IsAscii(line))
            {
                Warn(
                    DocumentationRules.Ascii,
                    "Write plain ASCII: 'times' rather than a multiplication sign, '-' rather than a dash.",
                    index);
            }

            // Read in place: only a line with code is copied, trimmed, once.
            int codeLength = CodeLength(line);
            bool hasComment = codeLength < line.Length;
            int indent = LeadingWhiteSpace(line, codeLength);
            if (indent == codeLength)
            {
                if (hasComment && CommentIndent(lines, index, indent, inMacro) is { } misplaced)
                {
                    Warn(DocumentationRules.CommentIndent, misplaced, index);
                }

                continue;
            }

            string trimmed = TrimmedCode(line, codeLength, indent);

            // A member of a type may have a trailing ;; comment instead of a block above it; a type's own lines may not.
            // A member that opens a nested type ("NEST .struct Named") is a member line too; a directive such as .org
            // is not a member.
            (string? typeMember, string typeDirective, _) = TypeLine(trimmed);
            bool memberLine = typeDepth != 0 && (typeMember is not null || typeDirective.Length == 0 && !trimmed.StartsWith('.'));
            if (codeLength + 1 < line.Length && line[codeLength + 1] == ';' && !memberLine)
            {
                Warn(DocumentationRules.TrailingDoc, "Put ;; documentation above the definition, not after it.", index);
            }

            // A label with code after it is one problem, not also the code's indentation.
            if (LabelWithCode(trimmed) is { } labeled)
            {
                Warn(DocumentationRules.LabelAlone, $"Put the label {labeled} on its own line.", index, labeled);
                continue;
            }

            string? defined = DefinedName(trimmed);

            if (defined is not null && IsAddressName(defined))
            {
                Warn(DocumentationRules.AddressName, $"Name {defined} for what it is: a name that is only an address says nothing.", index, defined);
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
                    Warn(DocumentationRules.Indent, $"Indent this line of the macro {expected} columns.", index);
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
                    Warn(DocumentationRules.Indent, $"Indent this line {expected} columns: a type's members one level in, a nested type's one more.", index);
                }
            }

            // A cheap-local or anonymous label is a label too, though it defines no name of its own.
            else if (s_blockDirectives.Contains(directive) || defined is not null || IsLabelOnly(trimmed))
            {
                if (indent != 0)
                {
                    Warn(DocumentationRules.ColumnZero, "Put definitions, labels and block directives at column 0.", index);
                }
            }
            else if (directive.Length == 0 || s_dataDirectives.Contains(directive))
            {
                if (indent != StyleIndent)
                {
                    Warn(DocumentationRules.Indent, $"Indent instructions and data {StyleIndent} columns.", index);
                }
            }

            if (opens) { typeDepth++; }
        }
    }

    // A comment line is indented like the code it describes: the next line of code, the line after a label, or,
    // before the end of a block, the code it follows. Gets the warning when it is not, or null.
    private static string? CommentIndent(string[] lines, int index, int indent, bool inMacro)
    {
        int next = index + 1;
        while (next < lines.Length && IsBlankCode(lines[next]))
        {
            // A blank line ends what the comment describes.
            if (IsBlank(lines[next])) { return null; }
            next++;
        }

        if (next >= lines.Length) { return null; }

        // The columns the comment may be at, each once: at most the four below.
        Span<int> allowed = stackalloc int[4];
        int count = 0;
        void Allow(Span<int> columns, int column)
        {
            if (columns[..count].IndexOf(column) < 0) { columns[count++] = column; }
        }

        Allow(allowed, Indentation(lines[next]));
        string code = TrimmedCode(lines[next]);

        // Before a conditional directive, the comment may also describe the code the condition chooses: the first line
        // after the directives that is not one.
        if (IsConditionalDirective(code) && CodeAfterConditionals(lines, next) is int chosen)
        {
            Allow(allowed, Indentation(lines[chosen]));
        }

        if (IsLabelOnly(code) && next + 1 < lines.Length && !IsBlankCode(lines[next + 1]))
        {
            Allow(allowed, Indentation(lines[next + 1]));
        }

        if (s_blockEnds.Contains(Directive(code)))
        {
            for (int previous = index - 1; previous >= 0; previous--)
            {
                if (IsBlankCode(lines[previous])) { continue; }
                Allow(allowed, Indentation(lines[previous]));
                break;
            }
        }

        if (inMacro && count == 0) { return null; }
        if (allowed[..count].IndexOf(indent) < 0)
        {
            int[] columns = allowed[..count].ToArray();
            Array.Sort(columns);
            return $"Indent this comment like the code it describes ({string.Join(" or ", columns)} columns).";
        }

        return null;
    }

    // The name a line defines: a block's (.proc Name), a constant's (Name = value or Name: .equ value), a variable's
    // (Name .set value or Name: .set value) or a label's (Name:).
    private static string? DefinedName(string code)
    {
        string directive = Directive(code);
        if (directive is ".proc" or ".scope" or ".macro" or ".struct" or ".union" or ".enum")
        {
            string rest = code[directive.Length..].TrimStart();
            int length = IdentifierLength(rest, 0);
            return length == 0 ? null : rest[..length];
        }

        int end = IdentifierLength(code, 0);
        if (end == 0) { return null; }
        // Read in place: every line of code with a name or mnemonic first comes here.
        ReadOnlySpan<char> after = code.AsSpan(end).TrimStart();
        bool equals = after.StartsWith("=".AsSpan(), StringComparison.Ordinal) && !after.StartsWith("==".AsSpan(), StringComparison.Ordinal);
        bool constant = equals || after.StartsWith(":=".AsSpan(), StringComparison.Ordinal);
        bool variable = after.StartsWith(".set".AsSpan(), StringComparison.OrdinalIgnoreCase);

        // ColonDefinition finds nothing unless the name is followed by a colon.
        bool colonDefinition = end < code.Length && code[end] == ':' && ColonDefinition(code[end..]).Length != 0;
        return constant || variable || colonDefinition || IsLabelOnly(code) ? code[..end] : null;
    }

    // A label followed by code on the same line, such as "Loop: lda (Pointer),y": the label, or null.
    private static string? LabelWithCode(string code)
    {
        int end = LabelLength(code);
        if (end < 0 || end >= code.Length || code[end] != ':' || (end == 0 && code.StartsWith("::", StringComparison.Ordinal)))
        {
            return null;
        }

        // Name: .equ value and Name: .set value are a constant and a variable, not a label.
        if (end != 0 && ColonDefinition(code[end..]).Length != 0) { return null; }

        // Name:=value is a constant, not a label.
        string rest = code[(end + 1)..];
        return rest.Length != 0 && rest[0] is not (':' or '=') && rest.Trim().Length != 0 ? code[..(end == 0 ? 1 : end)] : null;
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
            if (IsBlankCode(lines[index])) { return null; }
            if (!IsConditionalDirective(TrimmedCode(lines[index]))) { return index; }
        }

        return null;
    }

    // The whitespace before a line's code, as long as its code is when it has nothing else.
    private static int Indentation(string line) => LeadingWhiteSpace(line, CodeLength(line));

    // How many whitespace characters, as Trim reads them, start the text before the end.
    private static int LeadingWhiteSpace(string text, int end)
    {
        int start = 0;
        while (start < end && char.IsWhiteSpace(text[start])) { start++; }
        return start;
    }

    // Whether a line is only whitespace, as line.Trim().Length == 0 tells.
    private static bool IsBlank(string line) => LeadingWhiteSpace(line, line.Length) == line.Length;

    // Whether a line has no code before its comment, as Split(line).Code.Trim().Length == 0 tells.
    private static bool IsBlankCode(string line)
    {
        int codeLength = CodeLength(line);
        return LeadingWhiteSpace(line, codeLength) == codeLength;
    }

    // A line's code without its comment, trimmed, as Split(line).Code.Trim() gives it, copied once.
    private static string TrimmedCode(string line)
    {
        int codeLength = CodeLength(line);
        return TrimmedCode(line, codeLength, LeadingWhiteSpace(line, codeLength));
    }

    private static string TrimmedCode(string line, int codeLength, int start)
    {
        int end = codeLength;
        while (end > start && char.IsWhiteSpace(line[end - 1])) { end--; }
        return line[start..end];
    }

    // Whether every character is ASCII.
    private static bool IsAscii(string line)
    {
        foreach (char character in line)
        {
            if (character > '\x7F') { return false; }
        }

        return true;
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
