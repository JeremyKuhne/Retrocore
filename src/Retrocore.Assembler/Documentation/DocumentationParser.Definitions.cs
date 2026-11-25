// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Documentation;

public static partial class DocumentationParser
{
    // Data directives in every dialect: native and ca65, MACRO-10 and Merlin.
    private static readonly string[] s_data =
    [
        ".byte", ".byt", ".word", ".addr", ".dword", ".faraddr", ".dbyt", ".res", ".hiascii", ".asciiz",
        ".lobytes", ".hibytes", ".repeat", ".tag", ".incbin", ".align",
        "adr", "dt", "dci", "exp", "block", "xwd", "dc",
        "hex", "dfb", "db", "da", "dw", "ddb", "asc", "inv", "fls", "rev", "str", "ds"
    ];

    /// <summary>
    ///  Finds the definition on a line of code (without its comment), or null.
    /// </summary>
    private static Definition? Define(string code, List<string?> containers)
    {
        string text = code.TrimStart();
        if (text.Length == 0) { return null; }
        bool columnZero = !char.IsWhiteSpace(code[0]);

        // A member belongs to every named type around it, as the assembler scopes it: a named type opens a scope, and
        // an anonymous .struct or .union opens none, so its members are the enclosing type's.
        bool inType = containers.Count != 0;
        string joined = string.Join("::", containers.OfType<string>());
        string? container = joined.Length == 0 ? null : joined;
        string Nested(string name) => container is null ? name : $"{container}::{name}";
        string first = FirstWord(text);
        string rest = text[first.Length..].Trim();
        if (first.StartsWith('.'))
        {
            string name = FirstWord(rest);
            string after = rest[name.Length..].Trim();
            switch (first.ToLowerInvariant())
            {
                case ".macro":
                case ".mac":
                    return name.Length == 0 ? null : new(name, DocumentationKind.Macro, "", Words(after));
                case ".enum":
                    return name.Length == 0 ? null : new(Nested(name), DocumentationKind.Enum, "", []);
                case ".struct":
                case ".union":
                    return name.Length == 0 ? null : new(Nested(name), DocumentationKind.Struct, "", []);
                case ".scope" when after.Equals("continued", StringComparison.OrdinalIgnoreCase):
                    return null;
                case ".scope":
                    return name.Length == 0 ? null : new(name, DocumentationKind.Scope, "", []);

                // A .proc is a routine: its name is the address of its first statement.
                case ".proc":
                    return name.Length == 0 ? null : new(name, DocumentationKind.Routine, "", []);
                case ".define":
                    int open = rest.IndexOf('(');
                    string defined = open < 0 ? name : rest[..open].Trim();
                    int close = open < 0 ? -1 : rest.IndexOf(')', open);
                    IReadOnlyList<string> parameters = close < 0 ? [] : Words(rest[(open + 1)..close]);
                    return defined.Length == 0 ? null : new(defined, DocumentationKind.Definition, "", parameters);
                case ".set":
                    int comma = rest.IndexOf(',');
                    string variable = (comma < 0 ? name : rest[..comma]).Trim();
                    return variable.Length == 0 ? null : new(variable, DocumentationKind.Variable, "", []);
                default:
                    return null;
            }
        }

        if (first.Equals("DEFINE", StringComparison.OrdinalIgnoreCase))
        {
            string name = FirstWord(rest);
            return name.Length == 0 ? null : new(name, DocumentationKind.Macro, "", []);
        }

        int length = IdentifierLength(text);
        if (length == 0) { return null; }
        string identifier = text[..length];
        string tail = text[length..];
        string qualified = container is null ? identifier : $"{container}::{identifier}";
        if (tail.StartsWith(':') && !tail.StartsWith(":=", StringComparison.Ordinal))
        {
            // Name: .equ expr and Name: .set expr define a constant and a variable, not a label.
            string afterLabel = tail.TrimStart(':').Trim();
            DocumentationKind constant = inType ? DocumentationKind.Member : DocumentationKind.Constant;
            DocumentationKind? defined = ColonDefinition(tail) switch
            {
                ".equ" => constant,
                ".set" => DocumentationKind.Variable,
                _ => null,
            };

            return defined is { } kind
                ? new(qualified, kind, "", [])
                : new(identifier, DocumentationKind.Routine, afterLabel, []);
        }

        string spaced = tail.TrimStart();
        if (spaced.StartsWith('=') || spaced.StartsWith(":=", StringComparison.Ordinal))
        {
            return new(qualified, inType ? DocumentationKind.Member : DocumentationKind.Constant, "", []);
        }

        string word = FirstWord(spaced);
        if (word.Equals(".equ", StringComparison.OrdinalIgnoreCase) || word.Equals("EQU", StringComparison.OrdinalIgnoreCase))
        {
            return new(qualified, inType ? DocumentationKind.Member : DocumentationKind.Constant, "", []);
        }

        if (word.Equals(".set", StringComparison.OrdinalIgnoreCase))
        {
            return new(qualified, DocumentationKind.Variable, "", []);
        }

        if (inType && (spaced.Length == 0 || spaced.StartsWith('.')))
        {
            // An enumeration member, or a structure field such as "x .byte".
            return new(qualified, DocumentationKind.Member, "", []);
        }

        if (word.Equals("MAC", StringComparison.OrdinalIgnoreCase))
        {
            return new(identifier, DocumentationKind.Macro, "", []);
        }

        // A label without a colon, as Merlin writes them in column zero.
        return columnZero ? new(identifier, DocumentationKind.Routine, spaced, []) : null;
    }

    /// <summary>
    ///  Gets whether code that follows a label is data rather than an instruction.
    /// </summary>
    private static bool IsData(string code, HashSet<string> dataMacros)
    {
        string word = FirstWord(code.Trim());
        if (word.Length == 0) { return false; }
        int parenthesis = word.IndexOf('(');
        if (parenthesis > 0) { word = word[..parenthesis]; }
        return Array.IndexOf(s_data, word.ToLowerInvariant()) >= 0 || dataMacros.Contains(word);
    }

    /// <summary>
    ///  Gets whether a line is a conditional-assembly directive.
    /// </summary>
    private static bool IsConditional(string code) => IsConditional(code.AsSpan());

    /// <summary>
    ///  Gets whether a line's code is a conditional-assembly directive, without copying it.
    /// </summary>
    private static bool IsConditional(ReadOnlySpan<char> code)
    {
        ReadOnlySpan<char> word = FirstWord(code.Trim());
        return StartsLowered(word, ".if") || IsLowered(word, ".else") || IsLowered(word, ".elseif") || IsLowered(word, ".endif");
    }

    // Whether the text lowered with ToLowerInvariant is the ASCII lower-case word, lowering one character at a time
    // instead of a copy. Invariant lowering maps each character alone and keeps the length, so this is exact.
    private static bool IsLowered(ReadOnlySpan<char> text, string word) =>
        text.Length == word.Length && StartsLowered(text, word);

    // Whether the text lowered with ToLowerInvariant starts with the ASCII lower-case word.
    private static bool StartsLowered(ReadOnlySpan<char> text, string word)
    {
        if (text.Length < word.Length) { return false; }
        for (int index = 0; index < word.Length; index++)
        {
            if (char.ToLowerInvariant(text[index]) != word[index]) { return false; }
        }

        return true;
    }

    // Whether a line is a documentation comment line, ;; after any whitespace, as TrimStart().StartsWith(";;") reads it.
    private static bool IsDocumentationLine(string line)
    {
        int start = 0;
        while (start < line.Length && char.IsWhiteSpace(line[start])) { start++; }
        return start + 1 < line.Length && line[start] == ';' && line[start + 1] == ';';
    }

    /// <summary>
    ///  Gets whether a line holds only a label, which shares the comment of a label just above it.
    /// </summary>
    private static string? LabelOnly(string code)
    {
        string text = code.Trim();
        int length = IdentifierLength(text);
        if (length == 0) { return null; }
        string tail = text[length..];
        return tail is ":" or "::" ? text[..length] : null;
    }

    private static int IdentifierLength(string text) => IdentifierLength(text.AsSpan());

    private static int IdentifierLength(ReadOnlySpan<char> text)
    {
        int index = 0;
        if (index < text.Length && (char.IsLetter(text[index]) || text[index] is '_' or '@' or ']' or '.' or '?'))
        {
            index++;
        }
        else
        {
            return 0;
        }

        while (index < text.Length)
        {
            char character = text[index];
            if (char.IsLetterOrDigit(character) || character is '_' or '@' or '.' or '$' or '?' or '%')
            {
                index++;
            }
            else if (character == ':' && index + 2 < text.Length && text[index + 1] == ':' && char.IsLetter(text[index + 2]))
            {
                index += 2;
            }
            else
            {
                break;
            }
        }

        return index;
    }

    // The directive after a name and one colon that makes it a constant or variable rather than a label, as in
    // "Name: .equ expr" or "Name: .set expr": ".equ" or ".set", or "" when the colon is a label's.
    private static string ColonDefinition(string afterName)
    {
        if (!afterName.StartsWith(':') || afterName.StartsWith("::", StringComparison.Ordinal)) { return ""; }

        // The directive ends where the assembler ends it, at a space, a parenthesis or a comment: ".equ,3" is not
        // one, ".equ(3)" is.
        string rest = afterName[1..].TrimStart();
        int end = OperationLength(rest);
        int comment = rest.IndexOf(';', 0, end);
        if (comment >= 0) { end = comment; }
        string word = rest[..end].ToLowerInvariant();
        return word is ".equ" or ".set" ? word : "";
    }

    // Where the assembler ends a line's operation (AssemblySyntax.OperationLength, which the source generator does not
    // compile): at whitespace, or for a directive, also at an opening parenthesis.
    private static int OperationLength(ReadOnlySpan<char> text)
    {
        bool directive = text.Length != 0 && text[0] == '.';
        int end = 0;
        while (end < text.Length && !char.IsWhiteSpace(text[end]) && !(directive && text[end] == '(')) { end++; }
        return end;
    }

    private static string FirstWord(string text) => text[..FirstWordLength(text.AsSpan())];

    // The first word as a slice of the text.
    private static ReadOnlySpan<char> FirstWord(ReadOnlySpan<char> text) => text[..FirstWordLength(text)];

    private static int FirstWordLength(ReadOnlySpan<char> text)
    {
        // A directive's name ends at a parenthesis too, as the assembler reads it.
        int end = OperationLength(text);
        int comma = text[..end].IndexOf(',');
        return comma >= 0 ? comma : end;
    }

    private static IReadOnlyList<string> Words(string text) =>
        [.. text.Split([',', ' ', '\t'], StringSplitOptions.RemoveEmptyEntries)];

    /// <summary>
    ///  Splits a line into its code and its comment, ignoring semicolons in quotes.
    /// </summary>
    private static (string Code, string? Comment) Split(string line)
    {
        int end = CodeLength(line);
        return end == line.Length ? (line, null) : (line[..end], line[end..]);
    }

    // Where a line's comment starts, as Split finds it, or the line's length when it has none.
    private static int CodeLength(string line)
    {
        char quote = '\0';
        for (int index = 0; index < line.Length; index++)
        {
            char character = line[index];
            if (quote != '\0')
            {
                if (character == quote) { quote = '\0'; }
                continue;
            }

            if (character == '"') { quote = character; }

            // A character literal such as ';' is three characters; any other apostrophe is not a quote.
            if (character == '\'' && index + 2 < line.Length && line[index + 2] == '\'')
            {
                index += 2;
                continue;
            }

            if (character == ';') { return index; }
        }

        return line.Length;
    }
}
