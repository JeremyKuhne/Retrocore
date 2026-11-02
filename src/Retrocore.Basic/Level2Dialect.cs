// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text;

namespace Retrocore.Basic;

/// <summary>
///  Level II BASIC, Microsoft BASIC in the TRS-80 Model I's ROM.
/// </summary>
/// <remarks>
///  <para>
///   The tokenizer is the ROM's <c>CRUNCH</c>, as the SDK's <c>Level2.asm</c> gives it. Spaces are kept as typed,
///   and only <c>GOTO</c> may have spaces inside it. Lowercase letters outside strings, DATA and REM become
///   uppercase. <c>ELSE</c> is stored with a colon before it, and an apostrophe remark as a colon, <c>REM</c> and
///   the apostrophe token.
///  </para>
///  <para>
///   One space after the line number is dropped, so <c>10 PRINT</c> stores <c>PRINT</c> and <c>10  PRINT</c> stores
///   <c> PRINT</c>.
///  </para>
/// </remarks>
internal sealed class Level2Dialect : BasicDialect
{
    private const byte GotoToken = 0x8D;
    private const byte ElseToken = 0x95;
    private const byte PrintToken = 0xB2;
    private const byte ApostropheToken = 0xFB;
    private const int StackTop = 0x40A0;
    private const int StackRoom = 0x100;
    private const int DefaultTypes = 0x4101;
    private const int Letters = 26;
    private const byte SingleType = 4;
    private const int ErrorHandlerLine = 0x40F0;
    private const int ErrorHandlerActive = 0x40F2;

    private static readonly string[] s_keywords =
    [
        "END", "FOR", "RESET", "SET", "CLS", "CMD", "RANDOM", "NEXT", "DATA", "INPUT", "DIM", "READ", "LET", "GOTO",
        "RUN", "IF", "RESTORE", "GOSUB", "RETURN", "REM", "STOP", "ELSE", "TRON", "TROFF", "DEFSTR", "DEFINT",
        "DEFSNG", "DEFDBL", "LINE", "EDIT", "ERROR", "RESUME", "OUT", "ON", "OPEN", "FIELD", "GET", "PUT", "CLOSE",
        "LOAD", "MERGE", "NAME", "KILL", "LSET", "RSET", "SAVE", "SYSTEM", "LPRINT", "DEF", "POKE", "PRINT", "CONT",
        "LIST", "LLIST", "DELETE", "AUTO", "CLEAR", "CLOAD", "CSAVE", "NEW", "TAB(", "TO", "FN", "USING", "VARPTR",
        "USR", "ERL", "ERR", "STRING$", "INSTR", "POINT", "TIME$", "MEM", "INKEY$", "THEN", "NOT", "STEP", "+", "-",
        "*", "/", "[", "AND", "OR", ">", "=", "<", "SGN", "INT", "ABS", "FRE", "INP", "POS", "SQR", "RND", "LOG",
        "EXP", "COS", "SIN", "TAN", "ATN", "PEEK", "CVI", "CVS", "CVD", "EOF", "LOC", "LOF", "MKI$", "MKS$", "MKD$",
        "CINT", "CSNG", "CDBL", "FIX", "LEN", "STR$", "VAL", "ASC", "CHR$", "LEFT$", "RIGHT$", "MID$", "'"
    ];

    private Level2Dialect()
    {
    }

    /// <summary>
    ///  Gets the dialect.
    /// </summary>
    internal static Level2Dialect Instance { get; } = new();

    /// <inheritdoc/>
    public override string Name => "level2";

    /// <inheritdoc/>
    public override string DisplayName => "Level II BASIC";

    /// <inheritdoc/>
    public override IReadOnlyList<string> Keywords => s_keywords;

    /// <inheritdoc/>
    public override int MaximumLineNumber => 65529;

    /// <inheritdoc/>
    public override int DefaultLoadAddress => 0x42E9;

    /// <inheritdoc/>
    public override BasicPointers Pointers { get; } = new()
    {
        ProgramStart = 0x40A4,
        Variables = 0x40F9,
        Arrays = 0x40FB,
        FreeStart = 0x40FD,
        StringBottom = 0x40D6,
        MemoryTop = 0x40B1,
        CurrentLine = 0x40A2,
        ContinueText = 0x40F7,
        DataPointer = 0x40FF,
        StackTop = StackTop
    };

    /// <inheritdoc/>
    public override int InputLimit => 240;

    /// <inheritdoc/>
    internal override byte RemToken => 0x93;

    /// <inheritdoc/>
    internal override byte DataToken => 0x88;

    /// <inheritdoc/>
    internal override bool ListingSpaces => false;

    /// <inheritdoc/>
    internal override string AfterLineNumber(string line, int index) =>
        index < line.Length && line[index] == ' ' ? line[(index + 1)..] : line[index..];

    /// <inheritdoc/>
    internal override bool StartsSearch(byte value) => value is not (byte)' ' and not (byte)'"' and (< (byte)'0' or >= (byte)'<');

    /// <inheritdoc/>
    internal override void AppendKeyword(StringBuilder builder, string keyword, out bool spaceAfter)
    {
        builder.Append(keyword);
        spaceAfter = false;
    }

    /// <inheritdoc/>
    internal override bool ExpandSpecial(ReadOnlySpan<byte> line, ref int index, StringBuilder builder, out bool startsRemark)
    {
        startsRemark = false;
        if (line[index] != ':' || index + 1 >= line.Length) { return false; }

        // CRUNCH stores ELSE as :ELSE.
        if (line[index + 1] == ElseToken)
        {
            builder.Append("ELSE");
            index++;
            return true;
        }

        // And an apostrophe as :REM'.
        if (index + 2 < line.Length && line[index + 1] == RemToken && line[index + 2] == ApostropheToken)
        {
            builder.Append('\'');
            index += 2;
            startsRemark = true;
            return true;
        }

        return false;
    }

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   The stack grows down from string space toward the variables, so a page is left for it.
    ///  </para>
    /// </remarks>
    internal override int WriteLimit(IBasicMemory memory) => BasicProgram.Word(memory, StackTop) - StackRoom;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   Level II's <c>CLEARC</c> also makes every letter single precision and turns off ON ERROR.
    ///  </para>
    /// </remarks>
    internal override void Clear(IBasicMemory memory)
    {
        base.Clear(memory);
        for (int letter = 0; letter < Letters; letter++) { memory.Write(DefaultTypes + letter, SingleType); }
        memory.Write(ErrorHandlerActive, 0);
        BasicProgram.WriteWord(memory, ErrorHandlerLine, 0);
    }

    /// <inheritdoc/>
    internal override CrunchOutput Crunch(ReadOnlySpan<int> text)
    {
        // CRUNCH changes the first letter of a reserved word search to uppercase in the line itself.
        int[] line = text.ToArray();
        CrunchOutput output = new(line.Length + 2);
        int x = 0;
        bool data = false;
        while (true)
        {
            int unit = At(line, x);
            if (unit >= BasicText.Raw)
            {
                output.Add(unit, x);
                x++;
                continue;
            }

            int stored;
            int at = x;
            if (unit == ' ')
            {
                stored = unit;
            }
            else if (unit == '"')
            {
                // KRUNCH_15: copy the string; the closing quote goes through STUFFH.
                output.Add(unit, x);
                x++;
                if (!CopyLiteral(line, ref x, output, '"')) { break; }
                stored = '"';
                at = x;
            }
            else if (unit == 0)
            {
                break;
            }
            else if (data)
            {
                stored = unit;
            }
            else if (unit == '?')
            {
                stored = PrintToken;
            }
            else if (unit is >= '0' and < '<')
            {
                stored = unit;
            }
            else
            {
                stored = Search(line, ref x);
                if (stored == ElseToken)
                {
                    output.Add(':', at);
                }
                else if (stored == ApostropheToken)
                {
                    output.Add(':', at);
                    output.Add(RemToken, at);
                    output.Add(ApostropheToken, at);
                    x++;
                    CopyLiteral(line, ref x, output, endChar: -1);
                    break;
                }
            }

            // STUFFH.
            output.Add(stored, at);
            x++;
            if (stored == ':')
            {
                data = false;
            }
            else if (stored == DataToken)
            {
                data = true;
            }

            if (stored == RemToken)
            {
                CopyLiteral(line, ref x, output, endChar: -1);
                break;
            }
        }

        return output;
    }

    // STR1: copies typed characters unchanged up to the end character, leaving x on it. Returns false at the end of
    // the line.
    private static bool CopyLiteral(int[] line, ref int x, CrunchOutput output, int endChar)
    {
        while (true)
        {
            int unit = At(line, x);
            if (unit == 0) { return false; }
            if (unit == endChar) { return true; }
            output.Add(unit, x);
            x++;
        }
    }

    // MUSTCR: the reserved word search. Leaves x on the last character used and returns the byte to store.
    private static int Search(int[] line, ref int x)
    {
        int first = line[x];
        if (first is >= 'a' and <= 'z')
        {
            first &= 0x5F;
            line[x] = first;
        }

        for (int count = 0; count < s_keywords.Length; count++)
        {
            string keyword = s_keywords[count];
            if (keyword[0] != first) { continue; }
            int at = x;
            bool matched = true;
            for (int index = 1; index < keyword.Length; index++)
            {
                // GOTO may have spaces, tabs and line feeds between its letters (RST $10).
                if (count + FirstToken == GotoToken)
                {
                    while (At(line, at + 1) is ' ' or '\t' or '\n') { at++; }
                }

                at++;
                int unit = At(line, at);
                if (unit >= BasicText.Raw || Fold(unit) != keyword[index])
                {
                    matched = false;
                    break;
                }
            }

            if (matched)
            {
                x = at;
                return FirstToken + count;
            }
        }

        return first;
    }
}
