// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text;

namespace Retrocore.Basic;

/// <summary>
///  AppleSoft II, Microsoft BASIC in the Apple IIe's ROM.
/// </summary>
/// <remarks>
///  <para>
///   The tokenizer is the ROM's <c>CRUNCH</c> with Apple's changes, as the SDK's <c>applesoft.mac</c> gives them.
///   Spaces outside strings, DATA and REM are dropped, even inside reserved words. Reserved words are found
///   anywhere, so <c>SCORE</c> is <c>SC</c>, <c>OR</c>, <c>E</c>; <c>AT</c> is not taken before <c>N</c>
///   (<c>ATN</c>) or <c>O</c> (<c>A TO</c>). On the Enhanced IIe, lowercase outside strings, DATA and REM is made
///   uppercase.
///  </para>
/// </remarks>
internal sealed class AppleSoftDialect : BasicDialect
{
    private const int DataMode = 0x49;
    private const int DataBit = 0x40;
    private const byte PrintToken = 0xBA;
    private const byte AtToken = 0xC5;

    private static readonly string[] s_keywords =
    [
        "END", "FOR", "NEXT", "DATA", "INPUT", "DEL", "DIM", "READ", "GR", "TEXT", "PR#", "IN#", "CALL", "PLOT", "HLIN",
        "VLIN", "HGR2", "HGR", "HCOLOR=", "HPLOT", "DRAW", "XDRAW", "HTAB", "HOME", "ROT=", "SCALE=", "SHLOAD",
        "TRACE", "NOTRACE", "NORMAL", "INVERSE", "FLASH", "COLOR=", "POP", "VTAB", "HIMEM:", "LOMEM:", "ONERR",
        "RESUME", "RECALL", "STORE", "SPEED=", "LET", "GOTO", "RUN", "IF", "RESTORE", "&", "GOSUB", "RETURN", "REM",
        "STOP", "ON", "WAIT", "LOAD", "SAVE", "DEF", "POKE", "PRINT", "CONT", "LIST", "CLEAR", "GET", "NEW", "TAB(",
        "TO", "FN", "SPC(", "THEN", "AT", "NOT", "STEP", "+", "-", "*", "/", "^", "AND", "OR", ">", "=", "<", "SGN",
        "INT", "ABS", "USR", "FRE", "SCRN(", "PDL", "POS", "SQR", "RND", "LOG", "EXP", "COS", "SIN", "TAN", "ATN",
        "PEEK", "LEN", "STR$", "VAL", "ASC", "CHR$", "LEFT$", "RIGHT$", "MID$"
    ];

    private readonly bool _fold;

    private AppleSoftDialect(bool fold) => _fold = fold;

    /// <summary>
    ///  Gets the Enhanced IIe's AppleSoft.
    /// </summary>
    internal static AppleSoftDialect Enhanced { get; } = new(fold: true);

    /// <summary>
    ///  Gets the original IIe's AppleSoft.
    /// </summary>
    internal static AppleSoftDialect Original { get; } = new(fold: false);

    /// <inheritdoc/>
    public override string Name => "applesoft";

    /// <inheritdoc/>
    public override string DisplayName => _fold ? "AppleSoft" : "AppleSoft (original IIe)";

    /// <inheritdoc/>
    public override IReadOnlyList<string> Keywords => s_keywords;

    /// <inheritdoc/>
    public override int MaximumLineNumber => 63999;

    /// <inheritdoc/>
    public override int DefaultLoadAddress => 0x0801;

    /// <inheritdoc/>
    public override BasicPointers Pointers { get; } = new()
    {
        ProgramStart = 0x67,
        Variables = 0x69,
        Arrays = 0x6B,
        FreeStart = 0x6D,
        StringBottom = 0x6F,
        MemoryTop = 0x73,
        CurrentLine = 0x75,
        ContinueText = 0x79,
        DataPointer = 0x7D,
        ProgramEnd = 0xAF
    };

    /// <inheritdoc/>
    public override int InputLimit => 239;

    /// <inheritdoc/>
    internal override byte RemToken => 0xB2;

    /// <inheritdoc/>
    internal override byte DataToken => 0x83;

    /// <inheritdoc/>
    internal override bool ListingSpaces => true;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   AppleSoft marks direct mode with $FF in the line number's high byte alone.
    ///  </para>
    /// </remarks>
    public override bool InDirectMode(IBasicMemory memory) => memory.Read(Pointers.CurrentLine + 1) == 0xFF;

    /// <inheritdoc/>
    internal override string AfterLineNumber(string line, int index) => line[index..];

    /// <inheritdoc/>
    internal override bool StartsSearch(byte value) => value is not (byte)'"' and (< (byte)'0' or >= (byte)'<');

    /// <inheritdoc/>
    internal override void AppendKeyword(StringBuilder builder, string keyword, out bool spaceAfter)
    {
        bool word = char.IsAsciiLetter(keyword[0]);
        if (word && builder.Length > 0 && SeparatesWords(builder[^1])) { builder.Append(' '); }
        builder.Append(keyword);
        spaceAfter = word && char.IsAsciiLetter(keyword[^1]) && keyword is not "REM" and not "DATA";
    }

    /// <inheritdoc/>
    internal override CrunchOutput Crunch(ReadOnlySpan<int> text)
    {
        CrunchOutput output = new(text.Length + 1);
        int x = 0;
        int dores = 4;
        int endChar = ' ';
        while (true)
        {
            int unit = At(text, x);
            if (unit >= BasicText.Raw)
            {
                output.Add(unit, x);
                x++;
                continue;
            }

            // KLOOP: the Enhanced IIe folds case except in a string, a remark or DATA.
            int character = _fold && endChar is not (0 or '"') && dores != DataMode ? Fold(unit) : unit;
            if ((dores & DataBit) == 0 && character == ' ')
            {
                x++;
                continue;
            }

            endChar = character;
            int stored;
            int at = x;
            if (character == '"')
            {
                // STRNG: copy up to the closing quote, which STUFFH stores.
                output.Add(character, x);
                x++;
                if (!CopyLiteral(text, ref x, output, endChar)) { break; }
                stored = '"';
                at = x;
            }
            else if ((dores & DataBit) != 0)
            {
                stored = character;
            }
            else if (character == '?')
            {
                stored = PrintToken;
            }
            else if (character is >= '0' and < '<')
            {
                stored = character;
            }
            else
            {
                stored = Search(text, ref x);
            }

            // STUFFH.
            output.Add(stored, at);
            x++;
            if (stored == 0) { break; }
            if (stored == ':')
            {
                dores = 0;
            }
            else if (stored == DataToken)
            {
                dores = DataMode;
            }

            if (stored == RemToken)
            {
                endChar = 0;
                CopyLiteral(text, ref x, output, endChar);
                break;
            }
        }

        // The line's terminating zero is not part of its statements.
        output.RemoveLast();
        return output;
    }

    // A space goes before a reserved word that follows a name, a number, a string or a closing parenthesis.
    private static bool SeparatesWords(char previous) => char.IsAsciiLetterOrDigit(previous) || previous is '"' or ')' or '$' or '%' or '.';

    // STR1: copies typed characters unchanged up to the end character, leaving x on it. Returns false at the end of
    // the line, having stored the terminating zero.
    private static bool CopyLiteral(ReadOnlySpan<int> text, ref int x, CrunchOutput output, int endChar)
    {
        while (true)
        {
            int unit = At(text, x);
            if (unit == 0)
            {
                output.Add(0, x);
                return false;
            }

            if (unit < BasicText.Raw && unit == endChar) { return true; }
            output.Add(unit, x);
            x++;
        }
    }

    // MUSTCR: the reserved word search. Leaves x on the last character used and returns the byte to store.
    private int Search(ReadOnlySpan<int> text, ref int x)
    {
        int start = x;
        for (int count = 0; count < s_keywords.Length; count++)
        {
            string keyword = s_keywords[count];
            int at = start;
            bool matched = true;
            for (int index = 0; index < keyword.Length; index++)
            {
                if (index > 0) { at++; }

                // RESPU1: spaces inside a reserved word are skipped.
                while (At(text, at) == ' ') { at++; }
                int unit = At(text, at);
                if (unit >= BasicText.Raw || (_fold ? Fold(unit) : unit) != keyword[index])
                {
                    matched = false;
                    break;
                }
            }

            if (!matched) { continue; }
            int token = FirstToken + count;
            if (token == AtToken)
            {
                // ATN and A TO: the character right after AT, spaces not skipped.
                int next = At(text, at + 1);
                next = _fold ? Fold(next) : next;
                if (next is 'N' or 'O') { continue; }
            }

            x = at;
            return token;
        }

        // Not a reserved word: store the character, made uppercase on the Enhanced IIe (UPBUF).
        x = start;
        int character = At(text, start);
        return _fold ? Fold(character) : character;
    }
}
