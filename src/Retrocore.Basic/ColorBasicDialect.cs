// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text;

namespace Retrocore.Basic;

/// <summary>
///  Color BASIC, the TRS-80 Color Computer's Microsoft BASIC, with the words Extended and Disk Extended Color BASIC
///  add when their ROMs are fitted.
/// </summary>
/// <remarks>
///  <para>
///   The three ROMs share one token table, each adding to it: commands and operators from <c>$80</c>, and functions
///   as <c>$FF</c> and a token from <c>$80</c>. A machine crunches with the words its ROMs know, so a word a missing
///   ROM adds stays as its letters. The tokenizer is the ROM's <c>CRUNCH</c>, as the SDK's <c>ColorBasic.asm</c>
///   gives it: words match only in capitals; a letter starts a name, whose letters and digits are not searched for
///   words; spaces are kept; <c>?</c> is <c>PRINT</c>; and <c>ELSE</c> and the apostrophe get a colon before them.
///   <c>GOTO</c> and <c>GOSUB</c> are the words <c>GO</c> and <c>TO</c> or <c>SUB</c>.
///  </para>
///  <para>
///   The 6809 keeps words high byte first: line links, line numbers, pointers and string addresses.
///  </para>
/// </remarks>
internal sealed class ColorBasicDialect : BasicDialect
{
    private const byte PrintToken = 0x87;
    private const byte ElseToken = 0x84;
    private const byte ApostropheToken = 0x83;
    private const byte SubToken = 0xA6;
    private const int FunctionPrefixByte = 0xFF;
    private const int StringFloor = 0x21;
    private const int StackRoom = 0x100;

    // Color BASIC's commands and operators, then Extended BASIC's, then Disk BASIC's, in token order from $80.
    private static readonly string[] s_commands =
    [
        "FOR", "GO", "REM", "'", "ELSE", "IF", "DATA", "PRINT", "ON", "INPUT", "END", "NEXT", "DIM", "READ", "RUN",
        "RESTORE", "RETURN", "STOP", "POKE", "CONT", "LIST", "CLEAR", "NEW", "CLOAD", "CSAVE", "OPEN", "CLOSE",
        "LLIST", "SET", "RESET", "CLS", "MOTOR", "SOUND", "AUDIO", "EXEC", "SKIPF", "TAB(", "TO", "SUB", "THEN",
        "NOT", "STEP", "OFF", "+", "-", "*", "/", "^", "AND", "OR", ">", "=", "<",
        "DEL", "EDIT", "TRON", "TROFF", "DEF", "LET", "LINE", "PCLS", "PSET", "PRESET", "SCREEN", "PCLEAR", "COLOR",
        "CIRCLE", "PAINT", "GET", "PUT", "DRAW", "PCOPY", "PMODE", "PLAY", "DLOAD", "RENUM", "FN", "USING",
        "DIR", "DRIVE", "FIELD", "FILES", "KILL", "LOAD", "LSET", "MERGE", "RENAME", "RSET", "SAVE", "WRITE",
        "VERIFY", "UNLOAD", "DSKINI", "BACKUP", "COPY", "DSKI$", "DSKO$", "DOS"
    ];

    // Their functions, in token order from $FF $80.
    private static readonly string[] s_functions =
    [
        "SGN", "INT", "ABS", "USR", "RND", "SIN", "PEEK", "LEN", "STR$", "VAL", "ASC", "CHR$", "EOF", "JOYSTK",
        "LEFT$", "RIGHT$", "MID$", "POINT", "INKEY$", "MEM",
        "ATN", "COS", "TAN", "EXP", "FIX", "LOG", "POS", "SQR", "HEX$", "VARPTR", "INSTR", "TIMER", "PPOINT",
        "STRING$",
        "CVN", "FREE", "LOC", "LOF", "MKN$", "AS"
    ];

    private readonly string[] _commands;
    private readonly string[] _functions;

    private ColorBasicDialect(string displayName, int commands, int functions)
    {
        DisplayName = displayName;
        _commands = s_commands[..commands];
        _functions = s_functions[..functions];
    }

    /// <summary>
    ///  Gets Color BASIC alone.
    /// </summary>
    internal static ColorBasicDialect Color { get; } = new("Color BASIC", 53, 20);

    /// <summary>
    ///  Gets Color BASIC with Extended Color BASIC.
    /// </summary>
    internal static ColorBasicDialect Extended { get; } = new("Extended Color BASIC", 78, 34);

    /// <summary>
    ///  Gets Color and Extended BASIC with Disk Extended Color BASIC 1.0, which has no DOS.
    /// </summary>
    internal static ColorBasicDialect Disk10 { get; } = new("Disk Extended Color BASIC", 97, 40);

    /// <summary>
    ///  Gets Color and Extended BASIC with Disk Extended Color BASIC 1.1, every word.
    /// </summary>
    internal static ColorBasicDialect Disk { get; } = new("Disk Extended Color BASIC", 98, 40);

    /// <inheritdoc/>
    public override string Name => "colorbasic";

    /// <inheritdoc/>
    public override string DisplayName { get; }

    /// <inheritdoc/>
    public override IReadOnlyList<string> Keywords => _commands;

    /// <inheritdoc/>
    public override IReadOnlyList<string> Functions => _functions;

    /// <inheritdoc/>
    public override bool BigEndian => true;

    /// <inheritdoc/>
    public override int MaximumLineNumber => 63999;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   Extended BASIC's, after four graphics pages.
    ///  </para>
    /// </remarks>
    public override int DefaultLoadAddress => 0x1E01;

    /// <inheritdoc/>
    public override BasicPointers Pointers { get; } = new()
    {
        ProgramStart = 0x19,
        Variables = 0x1B,
        Arrays = 0x1D,
        FreeStart = 0x1F,
        StringBottom = 0x23,
        MemoryTop = 0x27,
        CurrentLine = 0x68,
        ContinueText = 0x2D,
        DataPointer = 0x33
    };

    /// <inheritdoc/>
    public override int InputLimit => 250;

    /// <inheritdoc/>
    internal override byte RemToken => 0x82;

    /// <inheritdoc/>
    internal override byte DataToken => 0x86;

    /// <inheritdoc/>
    internal override int FunctionPrefix => FunctionPrefixByte;

    /// <inheritdoc/>
    internal override int StackGosubToken => SubToken;

    /// <inheritdoc/>
    internal override bool ListingSpaces => false;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   The line number is read as BASIC reads it, skipping the spaces after it.
    ///  </para>
    /// </remarks>
    internal override string AfterLineNumber(string line, int index) => line[index..].TrimStart(' ');

    /// <inheritdoc/>
    internal override bool StartsSearch(byte value) => value is not (byte)' ' and not (byte)'"' and (< (byte)'0' or > (byte)';');

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
        byte value = line[index];
        if (value == FunctionPrefixByte && index + 1 < line.Length && Word(0xFF00 | line[index + 1]) is { } function)
        {
            builder.Append(function);
            index++;
            return true;
        }

        if (value != ':' || index + 1 >= line.Length) { return false; }

        // CRUNCH stores ELSE as :ELSE and an apostrophe as :'.
        if (line[index + 1] == ElseToken)
        {
            builder.Append("ELSE");
            index++;
            return true;
        }

        if (line[index + 1] == ApostropheToken)
        {
            builder.Append('\'');
            index++;
            startsRemark = true;
            return true;
        }

        return false;
    }

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   The stack grows down from the bottom of string space, <c>FRETOP</c>, so a page is left for it.
    ///  </para>
    /// </remarks>
    internal override int WriteLimit(IBasicMemory memory) => BasicProgram.Word(memory, StringFloor) - StackRoom;

    /// <inheritdoc/>
    internal override int VariableLimit(IBasicMemory memory) => WriteLimit(memory);

    /// <inheritdoc/>
    internal override int StringFloorOf(IBasicMemory memory) => BasicProgram.Word(memory, StringFloor);

    /// <inheritdoc/>
    internal override CrunchOutput Crunch(ReadOnlySpan<int> text)
    {
        int[] line = text.ToArray();
        CrunchOutput output = new(line.Length + 2);
        int x = 0;
        bool name = false;
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

            if (unit == 0) { break; }
            int at = x;
            x++;
            if (name)
            {
                // A name's letters and digits are copied, not searched for words.
                if (IsLetter(unit) || unit is >= '0' and <= '9')
                {
                    output.Add(unit, at);
                    continue;
                }

                name = false;
            }

            if (unit == ' ' || (data && unit != '"'))
            {
                Store(unit, at);
                continue;
            }

            if (unit == '"')
            {
                output.Add(unit, at);
                CopyLiteral(line, ref x, output, '"');
                continue;
            }

            if (unit == '?')
            {
                Store(PrintToken, at);
                continue;
            }

            if (unit == '\'')
            {
                output.Add(':', at);
                output.Add(ApostropheToken, at);
                CopyLiteral(line, ref x, output, endChar: -1);
                break;
            }

            if (unit is >= '0' and <= ';')
            {
                Store(unit, at);
                continue;
            }

            if (Search(line, at, out int token, out int length))
            {
                x = at + length;
                if (token > 0xFF)
                {
                    output.Add(FunctionPrefixByte, at);
                    output.Add(token & 0xFF, at);
                    continue;
                }

                if (token == ElseToken) { output.Add(':', at); }
                output.Add(token, at);
                if (token == DataToken) { data = true; }
                if (token == RemToken)
                {
                    CopyLiteral(line, ref x, output, endChar: -1);
                    break;
                }

                continue;
            }

            output.Add(unit, at);
            name = IsLetter(unit);
        }

        return output;

        // CRUNCH_STORE: a colon starts a statement, out of DATA.
        void Store(int value, int position)
        {
            output.Add(value, position);
            if (value == ':') { data = false; }
        }
    }

    // ISLETC: only capitals are letters.
    private static bool IsLetter(int unit) => unit is >= 'A' and <= 'Z';

    // CRUNCH_RAW: copies typed characters unchanged up to and including the end character, or to the line's end.
    private static void CopyLiteral(int[] line, ref int x, CrunchOutput output, int endChar)
    {
        while (true)
        {
            int unit = At(line, x);
            if (unit == 0) { return; }
            output.Add(unit, x);
            x++;
            if (unit == endChar) { return; }
        }
    }

    // CRUNCH_WORD: the commands' tables, then the functions', each in order; the first word the text starts with.
    private bool Search(int[] line, int at, out int token, out int length)
    {
        if (Find(_commands, line, at, out int index, out length))
        {
            token = FirstToken + index;
            return true;
        }

        if (Find(_functions, line, at, out index, out length))
        {
            token = 0xFF00 | (FirstToken + index);
            return true;
        }

        token = 0;
        return false;
    }

    private static bool Find(string[] words, int[] line, int at, out int index, out int length)
    {
        for (index = 0; index < words.Length; index++)
        {
            string word = words[index];
            int matched = 0;
            while (matched < word.Length && At(line, at + matched) == word[matched]) { matched++; }
            if (matched == word.Length)
            {
                length = word.Length;
                return true;
            }
        }

        length = 0;
        return false;
    }
}
