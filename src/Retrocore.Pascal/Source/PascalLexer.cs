// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal.Source;

/// <summary>
///  Splits Apple Pascal source into tokens, comments included.
/// </summary>
public static class PascalLexer
{
    private static readonly string[] s_pairs = [":=", "<=", ">=", "<>", ".."];

    /// <summary>
    ///  Splits a file's text into tokens.
    /// </summary>
    /// <param name="text">The text.</param>
    /// <param name="file">The file's path, which each token records.</param>
    /// <returns>The tokens, in order; an unclosed comment or string runs to the end.</returns>
    public static List<PascalToken> Tokenize(string text, string file)
    {
        ArgumentNullException.ThrowIfNull(text);
        string[] lines = Lines(text);
        List<PascalToken> tokens = [];
        int line = 0;
        int column = 0;
        while (line < lines.Length)
        {
            string current = lines[line];
            if (column >= current.Length)
            {
                line++;
                column = 0;
                continue;
            }

            char c = current[column];
            if (char.IsWhiteSpace(c))
            {
                column++;
                continue;
            }

            int startLine = line;
            int startColumn = column;
            if (c == '(' && column + 1 < current.Length && current[column + 1] == '*')
            {
                char third = column + 2 < current.Length ? current[column + 2] : ' ';
                char fourth = column + 3 < current.Length ? current[column + 3] : ' ';
                PascalTokenKind kind = PascalTokenKind.Comment;
                if (third == '$') { kind = PascalTokenKind.Option; }
                else if (third == '*' && fourth != ')') { kind = PascalTokenKind.DocComment; }

                (line, column) = Find(lines, line, column + 2, "*)");
                tokens.Add(Make(kind, lines, file, startLine, startColumn, line, column));
                continue;
            }

            if (c == '{')
            {
                (line, column) = Find(lines, line, column + 1, "}");
                tokens.Add(Make(PascalTokenKind.BraceComment, lines, file, startLine, startColumn, line, column));
                continue;
            }

            if (c == '\'')
            {
                column++;
                while (column < current.Length)
                {
                    if (current[column] == '\'')
                    {
                        if (column + 1 < current.Length && current[column + 1] == '\'')
                        {
                            column += 2;
                            continue;
                        }

                        column++;
                        break;
                    }

                    column++;
                }

                tokens.Add(Make(PascalTokenKind.String, lines, file, line, startColumn, line, column));
                continue;
            }

            if (char.IsLetter(c))
            {
                while (column < current.Length && (char.IsLetterOrDigit(current[column]) || current[column] == '_'))
                {
                    column++;
                }

                string word = current[startColumn..column];
                PascalTokenKind kind = PascalNames.IsKeyword(word)
                    ? PascalTokenKind.Keyword
                    : PascalTokenKind.Identifier;

                tokens.Add(new(kind, word, file, line, startColumn, line, column));
                continue;
            }

            if (char.IsDigit(c))
            {
                while (column < current.Length
                    && (char.IsLetterOrDigit(current[column]) || IsFraction(current, column)))
                {
                    column++;
                }

                tokens.Add(Make(PascalTokenKind.Number, lines, file, line, startColumn, line, column));
                continue;
            }

            string pair = column + 1 < current.Length ? current.Substring(column, 2) : "";
            column += Array.IndexOf(s_pairs, pair) >= 0 ? 2 : 1;
            tokens.Add(Make(PascalTokenKind.Symbol, lines, file, line, startColumn, line, column));
        }

        return tokens;
    }

    /// <summary>
    ///  Splits text into lines, as the tokens count them.
    /// </summary>
    /// <param name="text">The text.</param>
    /// <returns>Its lines, without their endings.</returns>
    public static string[] Lines(string text) =>
        text.Replace("\r\n", "\n", StringComparison.Ordinal).Replace('\r', '\n').Split('\n');

    // A decimal point inside a number: 1.5, but not the range 1..5.
    private static bool IsFraction(string line, int column) =>
        line[column] == '.' && column + 1 < line.Length && char.IsDigit(line[column + 1]);

    // Finds the end of a comment, returning the position after it, or the end of the text when it is never closed.
    private static (int Line, int Column) Find(string[] lines, int line, int column, string close)
    {
        while (line < lines.Length)
        {
            int at = lines[line].IndexOf(close, Math.Min(column, lines[line].Length), StringComparison.Ordinal);
            if (at >= 0) { return (line, at + close.Length); }
            line++;
            column = 0;
        }

        return (lines.Length - 1, lines[^1].Length);
    }

    private static PascalToken Make(
        PascalTokenKind kind,
        string[] lines,
        string file,
        int line,
        int column,
        int endLine,
        int endColumn)
    {
        string text = line == endLine
            ? lines[line][column..endColumn]
            : string.Join('\n', [lines[line][column..], .. lines[(line + 1)..endLine], lines[endLine][..endColumn]]);

        return new(kind, text, file, line, column, endLine, endColumn);
    }
}
