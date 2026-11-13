// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text;

namespace Retrocore.Basic;

/// <summary>
///  Apple II Integer BASIC programs: listing the tokenized form Integer BASIC keeps in memory and DOS 3.3 saves.
/// </summary>
/// <remarks>
///  <para>
///   Integer BASIC keeps its program from PP ($CA-$CB) up to HIMEM ($4C-$4D). Each line is its length (counting the
///   length byte), its number (two bytes, low first), its tokens and $01. A token below $80 is a keyword or an
///   operator; Integer BASIC tokenizes by its syntax, so the same text can have several tokens, such as the three
///   for <c>PRINT</c>. A constant is a digit with bit 7 set, then its 16-bit value; a variable's name, a string
///   between the quote tokens $28 and $29, and a remark after <c>REM</c> ($5D) are characters with bit 7 set.
///  </para>
///  <para>
///   Turning text into tokens takes Integer BASIC's own syntax tables, so the machine's ROM does it: see
///   <c>IntegerBasicTokenizer</c> in the Apple II machine.
///  </para>
/// </remarks>
public static class IntegerBasic
{
    private const byte EndOfLine = 0x01;
    private const byte OpenQuote = 0x28;
    private const byte CloseQuote = 0x29;
    private const byte Remark = 0x5D;

    // How Integer BASIC lists each token, as the ROM's LIST prints it alone in a line.
    private static readonly string[] s_tokens =
    [
        "HIMEM:", "?", "_", ":", "LOAD", "SAVE", "CON", "RUN",
        "RUN", "DEL", ",", "NEW", "CLR", "AUTO", ",", "MAN",
        "HIMEM:", "LOMEM:", "+", "-", "*", "/", "=", "#",
        ">=", ">", "<=", "<>", "<", "AND", "OR", "MOD",
        "^", "+", "(", ",", "THEN", "THEN", ",", ",",
        "\"", "\"", "(", "!", "!", "(", "PEEK", "RND",
        "SGN", "ABS", "PDL", "RNDX", "(", "+", "-", "NOT",
        "(", "=", "#", "LEN(", "ASC(", "SCRN(", ",", "(",
        "$", "$", "(", ",", ",", ";", ";", ";",
        ",", ",", ",", "TEXT", "GR", "CALL", "DIM", "DIM",
        "TAB", "END", "INPUT", "INPUT", "INPUT", "FOR", "=", "TO",
        "STEP", "NEXT", ",", "RETURN", "GOSUB", "REM", "LET", "GOTO",
        "IF", "PRINT", "PRINT", "PRINT", "POKE", ",", "COLOR=", "PLOT",
        ",", "HLIN", ",", "AT", "VLIN", ",", "AT", "VTAB",
        "=", "=", ")", ")", "LIST", ",", "LIST", "POP",
        "NODSP", "NODSP", "NOTRACE", "DSP", "DSP", "TRACE", "PR#", "IN#"
    ];

    // How Apple-1 BASIC lists each token, as its LIST prints it alone in a line: the same count down its own syntax
    // table. Tokens it has no keyword for print as what the count lands on; LIST never meets them.
    private static readonly string[] s_apple1Tokens =
    [
        "HIMEM=", "?", "_", ":", "LIST", ",", "LIST", "RUN",
        "RUN", "DEL", ",", "SCR", "CLR", "AUTO", ",", "OFF",
        "HIMEM=", "LOMEM=", "+", "-", "*", "/", "=", "#",
        ">=", ">", "<=", "<>", "<", "AND", "OR", "MOD",
        "^", "+", "(", ",", "THEN", "THEN", ",", ",",
        "\"", "\"", "(", "!", "!", "(", "PEEK", "RND",
        "SGN", "ABS", "USR", "RNDX", "(", "+", "-", "NOT",
        "(", "=", "#", "LEN(", "COLOR", "HIMEM", "LOMEM", "(",
        "$", "$", "(", ",", ",", ";", ";", ";",
        ",", ",", "!", "?", "?", "CALL", "DIM", "DIM",
        "TAB", "END", "INPUT", "INPUT", "INPUT", "FOR", "=", "TO",
        "STEP", "NEXT", ",", "RETURN", "GOSUB", "REM", "LET", "GOTO",
        "IF", "PRINT", "PRINT", "PRINT", "POKE", ",", "COLOR=", "PLOT",
        ",", "HLIN", ",", "AT", "_", ",", "+", "-",
        "=", "=", ")", ")", "_", ",", "+", "-"
    ];

    /// <summary>
    ///  Gets how Integer BASIC lists each token.
    /// </summary>
    internal static string[] Spellings => s_tokens;

    /// <summary>
    ///  Gets how Apple-1 BASIC lists each token.
    /// </summary>
    internal static string[] Apple1Spellings => s_apple1Tokens;

    /// <summary>
    ///  Tests whether a statement calls machine code, with CALL, up to the colon or line end after it.
    /// </summary>
    /// <param name="tokens">The stored tokens from the statement's first.</param>
    /// <returns>Whether the statement has a CALL.</returns>
    internal static bool CallsMachine(ReadOnlySpan<byte> tokens)
    {
        const byte Call = 0x4D;
        bool inName = false;
        for (int at = 0; at < tokens.Length; at++)
        {
            byte token = tokens[at];
            if (token >= 0x80)
            {
                if (token is >= 0xB0 and <= 0xB9 && !inName) { at += 2; }
                else { inName = true; }
                continue;
            }

            inName = false;
            if (token is EndOfLine or IntegerBasicDialect.Colon or Remark) { return false; }
            if (token == Call) { return true; }
            if (token == OpenQuote)
            {
                while (at + 1 < tokens.Length && tokens[at + 1] != CloseQuote) { at++; }
                at++;
            }
        }

        return false;
    }

    /// <summary>
    ///  Lists a program: one line of text for each of its lines, such as <c>10 PRINT "HI";A1+23</c>.
    /// </summary>
    /// <param name="program">The program's bytes, from PP up to HIMEM, as a DOS 3.3 <c>I</c> file holds them.</param>
    /// <returns>The listing, its lines ending in a line feed.</returns>
    /// <exception cref="InvalidDataException">A line's length runs past the end, or it does not end in $01.</exception>
    public static string List(ReadOnlySpan<byte> program)
    {
        StringBuilder text = new();
        int at = 0;
        while (at < program.Length)
        {
            int length = program[at];
            if (length < 4 || at + length > program.Length || program[at + length - 1] != EndOfLine)
            {
                throw new InvalidDataException($"The line at offset {at} is not an Integer BASIC line.");
            }

            text.Append(program[at + 1] | (program[at + 2] << 8)).Append(' ');
            ListLine(program.Slice(at + 3, length - 4), text);
            text.Append('\n');
            at += length;
        }

        return text.ToString();
    }

    /// <summary>
    ///  Gets the line numbers of a program, in order.
    /// </summary>
    /// <param name="program">The program's bytes.</param>
    /// <returns>Each line's number.</returns>
    public static IReadOnlyList<int> LineNumbers(ReadOnlySpan<byte> program)
    {
        List<int> numbers = [];
        for (int at = 0; at + 3 <= program.Length && program[at] >= 4; at += program[at])
        {
            numbers.Add(program[at + 1] | (program[at + 2] << 8));
        }

        return numbers;
    }

    // A line's tokens: keywords set off by spaces, operators and punctuation without.
    private static void ListLine(ReadOnlySpan<byte> tokens, StringBuilder text)
    {
        int at = 0;
        bool inName = false;

        // A keyword ending in a letter is followed by a space, written once something follows it.
        bool space = false;
        while (at < tokens.Length)
        {
            byte token = tokens[at++];
            if (space)
            {
                text.Append(' ');
                space = false;
            }

            if (token >= 0x80)
            {
                // A digit not in a name is a constant: its 16-bit value follows.
                if (token is >= 0xB0 and <= 0xB9 && !inName && at + 1 < tokens.Length)
                {
                    text.Append(tokens[at] | (tokens[at + 1] << 8));
                    at += 2;
                    continue;
                }

                text.Append((char)(token & 0x7F));
                inName = true;
                continue;
            }

            inName = false;
            if (token == OpenQuote)
            {
                text.Append('"');
                while (at < tokens.Length && tokens[at] != CloseQuote) { text.Append((char)(tokens[at++] & 0x7F)); }
                if (at < tokens.Length) { at++; }
                text.Append('"');
                continue;
            }

            string word = s_tokens[token];
            bool keyword = char.IsAsciiLetter(word[0]);
            if (keyword && text.Length > 0 && text[^1] != ' ') { text.Append(' '); }
            text.Append(word);
            if (token == Remark)
            {
                while (at < tokens.Length) { text.Append((char)(tokens[at++] & 0x7F)); }
                break;
            }

            space = keyword && char.IsAsciiLetter(word[^1]);
        }
    }
}
