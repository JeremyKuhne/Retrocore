// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Globalization;

namespace Retrocore.Assembler;

internal sealed partial class AssemblyPreprocessor
{
    /// <summary>
    ///  Evaluates ca65's token-list functions and the constant tests built on them.
    /// </summary>
    /// <param name="name">The lowercase function name.</param>
    /// <param name="args">The expanded argument text.</param>
    /// <returns>Replacement text, or null for a different function.</returns>
    /// <remarks>
    ///  <para>
    ///   As in ca65, a token list is either enclosed in braces or ends at the next comma (or the closing
    ///   parenthesis for the last list). <c>.match</c> compares token types only, so every integer matches every
    ///   other and <c>a</c>, <c>x</c> and <c>y</c> are distinct register tokens; <c>.xmatch</c> also compares
    ///   values. Lists returned by <c>.left</c>, <c>.right</c> and <c>.mid</c> keep their original spelling.
    ///  </para>
    /// </remarks>
    private string? Ca65TokenFunction(string name, string args)
    {
        switch (name)
        {
            case ".match":
            case ".xmatch":
                List<Ca65Token> tokens = Ca65Tokens(args);
                int index = 0;
                List<Ca65Token> first = Ca65TokenList(tokens, ref index, stopAtComma: true);
                if (index >= tokens.Count || tokens[index].Type != ",")
                {
                    throw new AssemblyError(0, $"{name} requires two token lists.");
                }

                index++;
                List<Ca65Token> second = Ca65TokenList(tokens, ref index, stopAtComma: false);
                Ca65EndOfList(tokens, index, name);
                return Ca65TokensMatch(first, second, values: name == ".xmatch") ? "1" : "0";
            case ".tcount":
            case ".blank":
                List<Ca65Token> all = Ca65Tokens(args);
                int position = 0;
                List<Ca65Token> list = Ca65TokenList(all, ref position, stopAtComma: false);
                Ca65EndOfList(all, position, name);
                return name == ".tcount" ? list.Count.ToString() : list.Count == 0 ? "1" : "0";
            case ".left":
            case ".right":
            case ".mid":
                return Ca65TokenSlice(name, args);
            case ".const":
                return Ca65IsConstant(args) ? "1" : "0";
            case ".strat":
                List<string> parts = Ca65Frontend.Split(args);
                if (parts.Count != 2) { throw new AssemblyError(0, ".strat requires a string and an index."); }
                string text = Ca65String(parts[0]);
                long at = Ca65Value(parts[1]);
                if (at < 0 || at >= text.Length) { throw new AssemblyError(0, ".strat index is outside the string."); }

                // As in ca65, the character passes through the current character map.
                return text[(int)at] > 255
                    ? throw new AssemblyError(0, "ca65 strings require byte characters.")
                    : Ca65.Characters[text[(int)at]].ToString();

            default:
                return null;
        }
    }

    private string Ca65TokenSlice(string name, string args)
    {
        // .left and .right take a count, .mid a start and a count; each value ends at a comma.
        int values = name == ".mid" ? 2 : 1;
        long[] numbers = new long[values];
        int offset = 0;
        for (int index = 0; index < values; index++)
        {
            int comma = Ca65TopLevelComma(args, offset);
            if (comma < 0) { throw new AssemblyError(0, $"{name} requires a count and a token list."); }
            numbers[index] = Ca65Value(args[offset..comma]);
            offset = comma + 1;
        }

        string listText = args[offset..];
        List<Ca65Token> tokens = Ca65Tokens(listText);
        int position = 0;
        List<Ca65Token> list = Ca65TokenList(tokens, ref position, stopAtComma: false);
        Ca65EndOfList(tokens, position, name);
        long start = name switch
        {
            ".left" => 0,
            ".right" => Math.Max(0, list.Count - numbers[0]),
            _ => numbers[0]
        };

        long count = name == ".mid" ? numbers[1] : numbers[0];
        if (start < 0 || count < 0) { throw new AssemblyError(0, $"{name} requires nonnegative values."); }
        long end = Math.Min(list.Count, start + count);
        return start >= end ? "" : listText[list[(int)start].Start..list[(int)end - 1].End];
    }

    private bool Ca65IsConstant(string expression)
    {
        try
        {
            return Ca65TryValue(expression) is not null;
        }
        catch (AssemblyError)
        {
            return false;
        }
        catch (OverflowException)
        {
            return false;
        }
    }

    private static bool Ca65TokensMatch(List<Ca65Token> first, List<Ca65Token> second, bool values)
    {
        if (first.Count != second.Count) { return false; }
        for (int index = 0; index < first.Count; index++)
        {
            bool same = first[index].Type == second[index].Type
                && (!values || string.Equals(first[index].Value, second[index].Value, StringComparison.Ordinal));

            if (!same) { return false; }
        }

        return true;
    }

    private static List<Ca65Token> Ca65TokenList(List<Ca65Token> tokens, ref int index, bool stopAtComma)
    {
        List<Ca65Token> list = [];
        if (index < tokens.Count && tokens[index].Type == "{")
        {
            // Braces end at the first closing brace, as in ca65; they do not nest.
            for (index++; index < tokens.Count && tokens[index].Type != "}"; index++) { list.Add(tokens[index]); }
            if (index == tokens.Count) { throw new AssemblyError(0, "Unterminated token list."); }
            index++;
            return list;
        }

        while (index < tokens.Count && !(stopAtComma && tokens[index].Type == ","))
        {
            list.Add(tokens[index++]);
        }

        return list;
    }

    private static void Ca65EndOfList(List<Ca65Token> tokens, int index, string name)
    {
        if (index != tokens.Count) { throw new AssemblyError(0, $"Unexpected text after the {name} token list."); }
    }

    private static int Ca65TopLevelComma(string text, int start)
    {
        int depth = 0;
        for (int index = start; index < text.Length; index++)
        {
            char character = text[index];
            if (character is '"' or '\'')
            {
                int close = text.IndexOf(character, index + 1);
                if (close < 0) { return -1; }
                index = close;
            }
            else if (character is '(' or '{')
            {
                depth++;
            }
            else if (character is ')' or '}')
            {
                depth--;
            }
            else if (character == ',' && depth == 0)
            {
                return index;
            }
        }

        return -1;
    }

    /// <summary>
    ///  Splits text into ca65 tokens whose type decides .match and whose value decides .xmatch.
    /// </summary>
    /// <param name="text">The token text.</param>
    /// <returns>The tokens with their source spans.</returns>
    private static List<Ca65Token> Ca65Tokens(string text)
    {
        ReadOnlySpan<char> source = text;
        List<Ca65Token> tokens = [];
        int index = 0;
        while (index < text.Length)
        {
            char character = text[index];
            if (char.IsWhiteSpace(character))
            {
                index++;
                continue;
            }

            int start = index;
            string type;
            string value;
            if (character is '"' or '\'')
            {
                int close = text.IndexOf(character, index + 1);
                if (close < 0) { throw new AssemblyError(0, "Unterminated string in a token list."); }
                index = close + 1;
                type = character == '"' ? "string" : "char";
                value = text[(start + 1)..close];
            }
            else if (IsNumberStart(text, index))
            {
                index++;
                while (index < text.Length && (char.IsAsciiLetter(text[index]) || char.IsAsciiDigit(text[index])))
                {
                    index++;
                }

                type = "int";
                value = Ca65IntegerToken(text[start..index]);
            }
            else if (character == '.' && index + 1 < text.Length && char.IsAsciiLetter(text[index + 1]))
            {
                index++;
                while (index < text.Length && AssemblySyntax.IsWord(text[index])) { index++; }
                type = text[start..index].ToUpperInvariant();
                value = type;
            }
            else if (AssemblySyntax.IsIdentifierStart(character))
            {
                index += Math.Max(1, AssemblySyntax.IdentifierSegmentLength(source[index..]));
                value = text[start..index];
                type = value.Length == 1 ? Ca65SingleLetterType(char.ToLowerInvariant(value[0]), text, index) : "ident";
                if (type[^1] == ':') { index++; }
                if (type != "ident") { value = type; }
            }
            else
            {
                index += Ca65OperatorLength(text, index);
                type = text[start..index];
                value = type;
            }

            tokens.Add(new(start, index, type, value));
        }

        return tokens;
    }

    private static bool IsNumberStart(string text, int index)
    {
        char character = text[index];
        bool binary = character == '%' && index + 1 < text.Length && text[index + 1] is '0' or '1';
        return binary || character == '$' || char.IsAsciiDigit(character);
    }

    // As in ca65, a, x and y are register tokens, and a:, z: and f: are address-size overrides.
    private static string Ca65SingleLetterType(char letter, string text, int next)
    {
        bool colon = next < text.Length && text[next] == ':';
        bool doubleColon = colon && next + 1 < text.Length && text[next + 1] == ':';
        return letter switch
        {
            'a' or 'z' or 'f' when colon && !doubleColon => $"{letter}:",
            'a' => "register a",
            'x' => "register x",
            'y' => "register y",
            _ => "ident"
        };
    }

    private static int Ca65OperatorLength(string text, int index)
    {
        if (index + 1 >= text.Length) { return 1; }
        char first = text[index];
        char second = text[index + 1];
        return (first, second) switch
        {
            (':', ':') or (':', '=') or ('<', '>') or ('<', '=') or ('>', '=') => 2,
            ('<', '<') or ('>', '>') or ('&', '&') or ('|', '|') => 2,
            _ => 1
        };
    }

    // Integer tokens compare by value, so $10, %10000 and 16 are the same value for .xmatch.
    private static string Ca65IntegerToken(string text)
    {
        try
        {
            long value = text[0] switch
            {
                '$' => Convert.ToInt64(text[1..], 16),
                '%' => Convert.ToInt64(text[1..], 2),
                _ => long.Parse(text, NumberStyles.None, CultureInfo.InvariantCulture)
            };

            return value.ToString();
        }
        catch (FormatException)
        {
            throw new AssemblyError(0, $"Invalid number '{text}'.");
        }
        catch (OverflowException)
        {
            throw new AssemblyError(0, $"Number '{text}' is too large.");
        }
    }
}
