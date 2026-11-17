// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text;

namespace Retrocore.Basic;

/// <summary>
///  Microsoft's BASIC-80 5.21 for CP/M, MBASIC: its CRUNCH and LIST.
/// </summary>
/// <remarks>
///  <para>
///   Statements and operators are one-byte tokens from <c>$81</c>, and functions two bytes, <c>$FF</c> then the
///   function's number with bit 7 set. A reserved word followed by a letter or digit is part of a variable's name, so
///   words must be set apart (<c>FOR I</c>, not <c>FORI</c>), except <c>FN</c>, <c>USR</c>, <c>TAB(</c> and
///   <c>SPC(</c>. Variable names are stored in uppercase. <c>ELSE</c> is stored as <c>:ELSE</c>, an apostrophe as
///   <c>:REM'</c>, and <c>WHILE</c> with a plus after it, which LIST leaves out.
///  </para>
///  <para>
///   Unlike earlier Microsoft BASICs, CRUNCH stores numbers in binary: a line number after <c>GOTO</c>, <c>THEN</c>
///   and the other words that take one as <c>$0E</c> and a word (which RUN may turn into <c>$0D</c> and the line's
///   address), <c>&amp;O</c> and <c>&amp;H</c> constants as <c>$0B</c> and <c>$0C</c> and a word, an integer from 0
///   to 9 as <c>$11</c>-<c>$1A</c>, one to 255 as <c>$0F</c> and a byte, a larger one as <c>$1C</c> and a word, a
///   single-precision number as <c>$1D</c> and four bytes and a double-precision one as <c>$1F</c> and eight, in
///   Microsoft's binary format with the exponent last. LIST writes them back, a single with <c>!</c> and a double
///   with <c>#</c> when nothing else in it says its type.
///  </para>
/// </remarks>
internal sealed class MbasicDialect : BasicDialect
{
    private const byte OctalConstant = 0x0B;
    private const byte HexConstant = 0x0C;
    private const byte LinePointer = 0x0D;
    private const byte LineConstant = 0x0E;
    private const byte ByteConstant = 0x0F;
    private const byte FirstDigit = 0x11;
    private const byte IntegerConstant = 0x1C;
    private const byte SingleConstant = 0x1D;
    private const byte DoubleConstant = 0x1F;
    private const byte FunctionPrefixByte = 0xFF;
    private const byte DataTokenByte = 0x84;
    private const byte GotoToken = 0x89;
    private const byte GosubToken = 0x8D;
    private const byte RemTokenByte = 0x8F;
    private const byte PrintToken = 0x91;
    private const byte ElseToken = 0xA2;
    private const byte WhileToken = 0xB4;
    private const byte PlusToken = 0xF2;
    private const byte UsrToken = 0xD2;
    private const byte FnToken = 0xD3;
    private const byte ApostropheToken = 0xDB;
    private const byte FirstOperator = 0xEF;

    // The words by token from $80; an empty string is a token BASIC-80 5.21 does not use.
    private static readonly string[] s_keywords =
    [
        "", "END", "FOR", "NEXT", "DATA", "INPUT", "DIM", "READ", "LET", "GOTO", "RUN", "IF", "RESTORE", "GOSUB",
        "RETURN", "REM", "STOP", "PRINT", "CLEAR", "LIST", "NEW", "ON", "NULL", "WAIT", "DEF", "POKE", "CONT", "", "",
        "OUT", "LPRINT", "LLIST", "", "WIDTH", "ELSE", "TRON", "TROFF", "SWAP", "ERASE", "EDIT", "ERROR", "RESUME",
        "DELETE", "AUTO", "RENUM", "DEFSTR", "DEFINT", "DEFSNG", "DEFDBL", "LINE", "", "", "WHILE", "WEND", "CALL",
        "WRITE", "COMMON", "CHAIN", "OPTION", "RANDOMIZE", "", "SYSTEM", "", "OPEN", "FIELD", "GET", "PUT", "CLOSE",
        "LOAD", "MERGE", "FILES", "NAME", "KILL", "LSET", "RSET", "SAVE", "RESET", "", "TO", "THEN", "TAB(", "STEP",
        "USR", "FN", "SPC(", "NOT", "ERL", "ERR", "STRING$", "USING", "INSTR", "'", "VARPTR", "INKEY$", "", "", "", "",
        "", "", "", "", "", "", "", "", "", "", "", "", "", ">", "=", "<", "+", "-", "*", "/", "^", "AND", "OR",
        "XOR", "EQV", "IMP", "MOD", "\\", "", ""
    ];

    // The functions by their byte after $FF, from $80.
    private static readonly string[] s_functions =
    [
        "", "LEFT$", "RIGHT$", "MID$", "SGN", "INT", "ABS", "SQR", "RND", "SIN", "LOG", "EXP", "COS", "TAN", "ATN",
        "FRE", "INP", "POS", "LEN", "STR$", "VAL", "ASC", "CHR$", "PEEK", "SPACE$", "OCT$", "HEX$", "LPOS", "CINT",
        "CSNG", "CDBL", "FIX", "", "", "", "", "", "", "", "", "", "", "", "CVI", "CVS", "CVD", "", "EOF", "LOC",
        "LOF", "MKI$", "MKS$", "MKD$"
    ];

    // The reserved word tables, ALPTAB's, in their order: each letter's words and their tokens, where one below $80
    // is a function's.
    private static readonly (string Word, byte Token)[][] s_letters =
    [
        [("AUTO", 0xAB), ("AND", 0xF7), ("ABS", 0x06), ("ATN", 0x0E), ("ASC", 0x15)],
        [],
        [
            ("CLOSE", 0xC3), ("CONT", 0x9A), ("CLEAR", 0x92), ("CINT", 0x1C), ("CSNG", 0x1D), ("CDBL", 0x1E),
            ("CVI", 0x2B), ("CVS", 0x2C), ("CVD", 0x2D), ("COS", 0x0C), ("CHR$", 0x16), ("CALL", 0xB6),
            ("COMMON", 0xB8), ("CHAIN", 0xB9)
        ],
        [
            ("DELETE", 0xAA), ("DATA", 0x84), ("DIM", 0x86), ("DEFSTR", 0xAD), ("DEFINT", 0xAE), ("DEFSNG", 0xAF),
            ("DEFDBL", 0xB0), ("DEF", 0x98)
        ],
        [
            ("ELSE", 0xA2), ("END", 0x81), ("ERASE", 0xA6), ("EDIT", 0xA7), ("ERROR", 0xA8), ("ERL", 0xD6),
            ("ERR", 0xD7), ("EXP", 0x0B), ("EOF", 0x2F), ("EQV", 0xFA)
        ],
        [("FOR", 0x82), ("FIELD", 0xC0), ("FILES", 0xC6), ("FN", 0xD3), ("FRE", 0x0F), ("FIX", 0x1F)],
        [("GOTO", 0x89), ("GO TO", 0x89), ("GOSUB", 0x8D), ("GET", 0xC1)],
        [("HEX$", 0x1A)],
        [("INPUT", 0x85), ("IF", 0x8B), ("INSTR", 0xDA), ("INT", 0x05), ("INP", 0x10), ("IMP", 0xFB), ("INKEY$", 0xDD)],
        [],
        [("KILL", 0xC8)],
        [
            ("LPRINT", 0x9E), ("LLIST", 0x9F), ("LPOS", 0x1B), ("LET", 0x88), ("LINE", 0xB1), ("LOAD", 0xC4),
            ("LSET", 0xC9), ("LIST", 0x93), ("LOG", 0x0A), ("LOC", 0x30), ("LEN", 0x12), ("LEFT$", 0x01),
            ("LOF", 0x31)
        ],
        [("MERGE", 0xC5), ("MOD", 0xFC), ("MKI$", 0x32), ("MKS$", 0x33), ("MKD$", 0x34), ("MID$", 0x03)],
        [("NEXT", 0x83), ("NULL", 0x96), ("NAME", 0xC7), ("NEW", 0x94), ("NOT", 0xD5)],
        [("OPEN", 0xBF), ("OUT", 0x9D), ("ON", 0x95), ("OR", 0xF8), ("OCT$", 0x19), ("OPTION", 0xBA)],
        [("PRINT", 0x91), ("PUT", 0xC2), ("POKE", 0x99), ("POS", 0x11), ("PEEK", 0x17)],
        [],
        [
            ("RETURN", 0x8E), ("READ", 0x87), ("RUN", 0x8A), ("RESTORE", 0x8C), ("REM", 0x8F), ("RESUME", 0xA9),
            ("RSET", 0xCA), ("RIGHT$", 0x02), ("RND", 0x08), ("RENUM", 0xAC), ("RESET", 0xCC), ("RANDOMIZE", 0xBB)
        ],
        [
            ("STOP", 0x90), ("SWAP", 0xA5), ("SAVE", 0xCB), ("SPC(", 0xD4), ("STEP", 0xD1), ("SGN", 0x04),
            ("SQR", 0x07), ("SIN", 0x09), ("STR$", 0x13), ("STRING$", 0xD8), ("SPACE$", 0x18), ("SYSTEM", 0xBD)
        ],
        [("THEN", 0xCF), ("TRON", 0xA3), ("TROFF", 0xA4), ("TAB(", 0xD0), ("TO", 0xCE), ("TAN", 0x0D)],
        [("USING", 0xD9), ("USR", 0xD2)],
        [("VAL", 0x14), ("VARPTR", 0xDC)],
        [("WIDTH", 0xA1), ("WAIT", 0x97), ("WHILE", 0xB4), ("WEND", 0xB5), ("WRITE", 0xB7)],
        [("XOR", 0xF9)],
        [],
        []
    ];

    // SPCTAB: the characters that are operators.
    private static readonly (char Character, byte Token)[] s_operators =
    [
        ('+', 0xF2), ('-', 0xF3), ('*', 0xF4), ('/', 0xF5), ('^', 0xF6), ('\\', 0xFD), ('\'', ApostropheToken),
        ('>', 0xEF), ('=', 0xF0), ('<', 0xF1)
    ];

    // LINRES: the words a line number follows.
    private static readonly byte[] s_lineWords =
        [0x8C, 0xAB, 0xAC, 0xAA, 0xA7, 0xA9, 0xD6, ElseToken, 0x8A, 0x93, 0x9F, GotoToken, 0x8E, 0xCF, GosubToken];

    private MbasicDialect()
    {
    }

    /// <summary>
    ///  Gets the dialect.
    /// </summary>
    internal static MbasicDialect Instance { get; } = new();

    /// <inheritdoc/>
    public override string Name => "mbasic";

    /// <inheritdoc/>
    public override string DisplayName => "MBASIC (BASIC-80 5.21)";

    /// <inheritdoc/>
    public override IReadOnlyList<string> Keywords => s_keywords;

    /// <inheritdoc/>
    public override IReadOnlyList<string> Functions => s_functions;

    /// <inheritdoc/>
    public override int MaximumLineNumber => 65529;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   Where MBASIC's program text starts on a 64K CP/M system with its three default file buffers.
    ///  </para>
    /// </remarks>
    public override int DefaultLoadAddress => MbasicMemory.ProgramStart;

    /// <inheritdoc/>
    public override BasicPointers Pointers { get; } = new()
    {
        ProgramStart = MbasicMemory.TXTTAB,
        Variables = MbasicMemory.VARTAB,
        Arrays = MbasicMemory.ARYTAB,
        FreeStart = MbasicMemory.STREND,
        StringBottom = MbasicMemory.FRETOP,
        MemoryTop = MbasicMemory.MEMSIZ,
        CurrentLine = MbasicMemory.CURLIN,
        ContinueText = MbasicMemory.OLDTXT,
        DataPointer = MbasicMemory.DATPTR,
        StackTop = MbasicMemory.SAVSTK
    };

    /// <inheritdoc/>
    public override int InputLimit => 255;

    /// <inheritdoc/>
    internal override byte RemToken => RemTokenByte;

    /// <inheritdoc/>
    internal override byte DataToken => DataTokenByte;

    /// <inheritdoc/>
    internal override int FunctionPrefix => FunctionPrefixByte;

    /// <inheritdoc/>
    internal override bool ListingSpaces => false;

    /// <inheritdoc/>
    internal override bool IsRemark(byte token) => token is RemTokenByte or ApostropheToken;

    /// <inheritdoc/>
    internal override string AfterLineNumber(string line, int index) => line[index..].TrimStart(' ');

    /// <inheritdoc/>
    internal override bool StartsSearch(byte value) => value is not (byte)' ' and not (byte)'"' and not (>= (byte)'0' and <= (byte)'9');

    /// <inheritdoc/>
    internal override void AppendKeyword(StringBuilder builder, string keyword, out bool spaceAfter)
    {
        builder.Append(keyword);
        spaceAfter = false;
    }

    /// <inheritdoc/>
    public override string Detokenize(ReadOnlySpan<byte> line)
    {
        if (List(line, escapes: false) is { } text && TokenizesTo(text, line)) { return text; }
        if (List(line, escapes: true) is { } escaped && TokenizesTo(escaped, line)) { return escaped; }
        StringBuilder raw = new();
        foreach (byte value in line) { BasicText.AppendEscape(raw, value); }
        return raw.ToString();
    }

    // LIST's PLOOP: expands a line, spacing words as LIST does, or null for a constant cut short or a line pointer,
    // which only memory can turn back into a number.
    private static string? List(ReadOnlySpan<byte> line, bool escapes)
    {
        StringBuilder builder = new(line.Length * 2);

        // What came last: 0 a special character, 1 a name or number, -1 a reserved word.
        int last = 0;
        bool quoted = false, data = false, remark = false;
        for (int index = 0; index < line.Length; index++)
        {
            byte value = line[index];
            if (remark)
            {
                BasicText.AppendCharacter(builder, value);
                continue;
            }

            if (value == '"') { quoted = !quoted; }
            if (quoted || data)
            {
                if (value == ':' && !quoted) { data = false; }
                AppendText(builder, value, escapes);
                last = 0;
                continue;
            }

            if (value is >= OctalConstant and < 0x20 and not 0x10 and not 0x1B and not 0x1E)
            {
                string? number = Constant(line, ref index);
                if (number is null) { return null; }
                if (last == -1) { builder.Append(' '); }
                builder.Append(number);
                last = 1;
                continue;
            }

            if (value < 0x80)
            {
                bool named = value == '.' || char.IsAsciiLetterOrDigit((char)value);
                if (named && last == -1) { builder.Append(' '); }
                last = named ? 1 : 0;
                if (value == ':' && index + 1 < line.Length && line[index + 1] == ElseToken) { continue; }
                if (value == ':' && index + 2 < line.Length && line[index + 1] == RemTokenByte && line[index + 2] == ApostropheToken)
                {
                    builder.Append('\'');
                    index += 2;
                    remark = true;
                    continue;
                }

                AppendText(builder, value, escapes);
                continue;
            }

            string? word = value == FunctionPrefixByte && index + 1 < line.Length
                ? (line[index + 1] - FirstToken is >= 0 and var function && function < s_functions.Length ? s_functions[function] : null)
                : s_keywords[value - FirstToken];

            if (string.IsNullOrEmpty(word))
            {
                BasicText.AppendEscape(builder, value);
                last = 0;
                continue;
            }

            if (value == FunctionPrefixByte) { index++; }

            if (value >= FirstOperator && value != FunctionPrefixByte)
            {
                last = 0;
            }
            else if (value is FnToken or UsrToken)
            {
                if (last != 0) { builder.Append(' '); }
                last = 0;
            }
            else
            {
                if (last != 0) { builder.Append(' '); }
                last = word.EndsWith('(') ? 0 : -1;
            }

            builder.Append(word);
            if (value == WhileToken && index + 1 < line.Length && line[index + 1] == PlusToken) { index++; }
            if (value == DataTokenByte) { data = true; }
            if (value == RemTokenByte) { remark = true; }
        }

        return builder.ToString();
    }

    private static void AppendText(StringBuilder builder, byte value, bool escapes)
    {
        if (escapes && value >= 0x80) { BasicText.AppendEscape(builder, value); }
        else { BasicText.AppendCharacter(builder, value); }
    }

    // A constant's text, as LIST writes it, moving the index to its last byte; null for one cut short or a pointer.
    private static string? Constant(ReadOnlySpan<byte> line, ref int index)
    {
        byte type = line[index];
        int length = type switch
        {
            >= FirstDigit and <= FirstDigit + 9 => 0,
            ByteConstant => 1,
            SingleConstant => 4,
            DoubleConstant => 8,
            LinePointer => -1,
            _ => 2
        };

        if (length < 0 || index + length >= line.Length) { return null; }
        ReadOnlySpan<byte> bytes = line.Slice(index + 1, length);
        index += length;
        int word = length == 2 ? bytes[0] | (bytes[1] << 8) : 0;
        return type switch
        {
            >= FirstDigit and <= FirstDigit + 9 => ((char)('0' + type - FirstDigit)).ToString(),
            ByteConstant => bytes[0].ToString(System.Globalization.CultureInfo.InvariantCulture),
            OctalConstant => "&O" + Convert.ToString(word, 8),
            HexConstant => "&H" + word.ToString("X", System.Globalization.CultureInfo.InvariantCulture),
            LineConstant => word.ToString(System.Globalization.CultureInfo.InvariantCulture),
            IntegerConstant => ((short)word).ToString(System.Globalization.CultureInfo.InvariantCulture),
            SingleConstant => Shortest(type, bytes, '!', isDouble: false),
            _ => Shortest(type, bytes, '#', isDouble: true)
        };
    }

    // A single or double in the fewest digits that crunch back to its bytes, from as many as LIST writes (six for a
    // single, sixteen for a double), which do not always: LIST writes 1234567 as 1.23457E+06.
    private static string Shortest(byte type, ReadOnlySpan<byte> bytes, char indicator, bool isDouble)
    {
        double value = BasicNumbers.ReadFloat(bytes, exponentFirst: false);
        int first = isDouble ? 16 : 6;
        string listed = "";
        for (int digits = first; digits <= first + 3; digits++)
        {
            string number = Fraction(value, digits) ?? BasicNumbers.Format(value, digits);
            string text = Typed(isDouble ? number.Replace('E', 'D') : number, indicator, isDouble);
            if (digits == first) { listed = text; }
            int[] units = [.. text.Select(character => (int)character)];
            int x = 0;
            byte[] crunched = MbasicNumbers.Crunch(units, ref x);
            if (x == units.Length && crunched[0] == type && crunched.AsSpan(1).SequenceEqual(bytes)) { return text; }
        }

        return listed;
    }

    // A number below .01 without an exponent, as LIST writes one whose zeros and digits fit (.001), or null.
    private static string? Fraction(double value, int digits)
    {
        if (value is <= 0 or >= 0.01) { return null; }
        string scientific = value.ToString($"E{digits - 1}", System.Globalization.CultureInfo.InvariantCulture);
        int exponent = int.Parse(scientific[(scientific.IndexOf('E', StringComparison.Ordinal) + 1)..], System.Globalization.CultureInfo.InvariantCulture);
        string significant = scientific[..scientific.IndexOf('E', StringComparison.Ordinal)].Replace(".", "", StringComparison.Ordinal).TrimEnd('0');
        int zeros = -exponent - 1;
        return zeros + significant.Length <= digits ? "." + new string('0', zeros) + significant : null;
    }

    // A single or double as LIST writes it: its type character unless a point (for a single) or exponent says it.
    private static string Typed(string number, char indicator, bool isDouble)
    {
        bool exponent = number.Contains('E', StringComparison.Ordinal) || number.Contains('D', StringComparison.Ordinal);
        bool said = exponent || (!isDouble && number.Contains('.', StringComparison.Ordinal));
        return said ? number : number + indicator;
    }

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   A constant's bytes are stepped over, outside strings, remarks and DATA, as they may be zero.
    ///  </para>
    /// </remarks>
    internal override int TerminatorIn(ReadOnlySpan<byte> tokens)
    {
        bool quoted = false, data = false, remark = false;
        for (int index = 0; index < tokens.Length; index++)
        {
            byte value = tokens[index];
            if (value == 0) { return index; }
            if (remark) { continue; }
            if (value == '"') { quoted = !quoted; }
            if (quoted) { continue; }
            if (data)
            {
                data = value != ':';
                continue;
            }

            if (value is RemTokenByte or ApostropheToken) { remark = true; }
            else if (value == DataTokenByte) { data = true; }
            else { index += ConstantLength(value); }
        }

        return -1;
    }

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   RUN turns the line numbers after GOTO and the others into <c>$0D</c> and the address of the byte before
    ///   the line; they go back to <c>$0E</c> and the line's number, as LIST and SAVE put them back.
    ///  </para>
    /// </remarks>
    internal override byte[] FromMemory(byte[] tokens, IBasicMemory memory)
    {
        if (!tokens.Contains(LinePointer)) { return tokens; }
        byte[] result = [.. tokens];
        bool quoted = false, data = false, remark = false;
        for (int index = 0; index < result.Length; index++)
        {
            byte value = result[index];
            if (remark) { continue; }
            if (value == '"') { quoted = !quoted; }
            if (quoted) { continue; }
            if (data)
            {
                data = value != ':';
                continue;
            }

            if (value is RemTokenByte or ApostropheToken) { remark = true; }
            else if (value == DataTokenByte) { data = true; }
            else if (value == LinePointer && index + 2 < result.Length)
            {
                int pointer = result[index + 1] | (result[index + 2] << 8);
                int number = memory.Read(pointer + 3) | (memory.Read(pointer + 4) << 8);
                result[index] = LineConstant;
                result[index + 1] = (byte)number;
                result[index + 2] = (byte)(number >> 8);
            }

            index += ConstantLength(value);
        }

        return result;
    }

    // The bytes a constant's token is followed by.
    private static int ConstantLength(byte value) => value switch
    {
        ByteConstant => 1,
        OctalConstant or HexConstant or LinePointer or LineConstant or IntegerConstant => 2,
        SingleConstant => 4,
        DoubleConstant => 8,
        _ => 0
    };

    /// <inheritdoc/>
    internal override void Clear(IBasicMemory memory)
    {
        base.Clear(memory);
        for (int letter = 0; letter < 26; letter++) { memory.Write(MbasicMemory.DEFTBL + letter, 4); }
        memory.Write(MbasicMemory.ONEFLG, 0);
        BasicProgram.WriteWord(memory, MbasicMemory.ONELIN, 0);
    }

    private static bool TokenizesTo(string text, ReadOnlySpan<byte> line)
    {
        try
        {
            return Instance.Tokenize(text).AsSpan().SequenceEqual(line);
        }
        catch (FormatException)
        {
            return false;
        }
    }

    /// <inheritdoc/>
    internal override CrunchOutput Crunch(ReadOnlySpan<int> text)
    {
        int[] line = text.ToArray();
        CrunchOutput output = new(line.Length + 8);

        // DORES: in a DATA statement, copying as typed; DONUM: 1 where a line number may come, 0 where a number may,
        // -1 in a name, where digits are part of it.
        bool data = false;
        int numbers = 0;
        int x = 0;
        while (true)
        {
            int unit = At(line, x);
            if (unit == 0) { break; }
            if (unit >= BasicText.Raw)
            {
                output.Add(unit, x);
                x++;
                continue;
            }

            if (unit == '"')
            {
                output.Add(unit, x);
                x++;
                if (!CopyTo(line, ref x, output, '"')) { break; }
                output.Add('"', x);
                x++;
                continue;
            }

            if (unit == ' ' || data)
            {
                Stuff(unit, x, output, ref data, ref numbers);
                x++;
                continue;
            }

            if (unit >= 0x80)
            {
                // A character with bit 7 set is dropped.
                x++;
                continue;
            }

            if (unit == '?')
            {
                Word(PrintToken, x, output, ref data, ref numbers);
                x++;
                continue;
            }

            int upper = Fold(unit);
            if (upper is >= 'A' and <= 'Z')
            {
                if (Search(line, x, upper) is ({ } token, int end))
                {
                    if (token < 0x80)
                    {
                        output.Add(FunctionPrefixByte, x);
                        output.Add(token | 0x80, x);
                        numbers = 0;
                    }
                    else
                    {
                        Word((byte)token, x, output, ref data, ref numbers);
                        if (token == RemTokenByte)
                        {
                            CopyTo(line, ref end, output, -1);
                            break;
                        }
                    }

                    x = end;
                    continue;
                }

                // A name: letters, digits and dots, in uppercase.
                numbers = -1;
                while (Fold(At(line, x)) is >= 'A' and <= 'Z' or >= '0' and <= '9' or '.')
                {
                    output.Add(Fold(line[x]), x);
                    x++;
                }

                continue;
            }

            if (unit == '.' || unit is >= '0' and <= '9')
            {
                if (numbers < 0 || (numbers > 0 && unit == '.'))
                {
                    Stuff(unit, x, output, ref data, ref numbers);
                    x++;
                }
                else if (numbers > 0)
                {
                    int at = x;
                    int number = LineNumber(line, ref x);
                    output.Add(LineConstant, at);
                    output.Add(number & 0xFF, at);
                    output.Add(number >> 8, at);
                }
                else
                {
                    int at = x;
                    byte[] constant = MbasicNumbers.Crunch(line, ref x);
                    foreach (byte value in constant) { output.Add(value, at); }
                }

                continue;
            }

            if (Operator(unit) is { } operatorToken)
            {
                if (numbers < 0) { numbers = 0; }
                if (operatorToken == ApostropheToken)
                {
                    output.Add(':', x);
                    output.Add(RemTokenByte, x);
                    output.Add(ApostropheToken, x);
                    x++;
                    CopyTo(line, ref x, output, -1);
                    break;
                }

                Stuff(operatorToken, x, output, ref data, ref numbers);
                x++;
                continue;
            }

            if (unit == '&')
            {
                int at = x;
                int next = x + 1;
                while (At(line, next) == ' ') { next++; }
                bool hex = Fold(At(line, next)) == 'H';
                x = hex ? next + 1 : x + (Fold(At(line, next)) == 'O' ? next - x + 1 : 1);
                int value = MbasicNumbers.Radix(line, ref x, hex ? 16 : 8);
                output.Add(hex ? HexConstant : OctalConstant, at);
                output.Add(value & 0xFF, at);
                output.Add((value >> 8) & 0xFF, at);
                continue;
            }

            // Another character: control characters but tab and line feed become spaces.
            if (unit < ' ' && unit is not '\t' and not '\n') { unit = ' '; }
            if (numbers < 0) { numbers = 0; }
            Stuff(unit, x, output, ref data, ref numbers);
            x++;
        }

        return output;
    }

    // STUFFH: stores a byte, a colon ending a DATA statement and a DATA token starting one.
    private static void Stuff(int value, int at, CrunchOutput output, ref bool data, ref int numbers)
    {
        output.Add(value, at);
        if (value == ':')
        {
            data = false;
            numbers = 0;
        }
        else if (value == DataTokenByte)
        {
            data = true;
            numbers = 1;
        }
    }

    // A statement word: a line number may follow the words in LINRES, ELSE has a colon before it.
    private static void Word(byte token, int at, CrunchOutput output, ref bool data, ref int numbers)
    {
        numbers = s_lineWords.Contains(token) ? 1 : 0;
        if (token == ElseToken) { output.Add(':', at); }
        Stuff(token, at, output, ref data, ref numbers);

        // WHILE's condition starts with a plus, so a number after it is not read as a line number's.
        if (token == WhileToken) { output.Add(PlusToken, at); }
    }

    private static byte? Operator(int unit)
    {
        foreach ((char character, byte token) in s_operators)
        {
            if (character == unit) { return token; }
        }

        return null;
    }

    // The reserved word at x, and the index after it, if one is there and set apart from what follows.
    private static (int Token, int End)? Search(int[] line, int x, int first)
    {
        foreach ((string word, byte token) in s_letters[first - 'A'])
        {
            int at = x + 1;
            bool matched = true;
            for (int index = 1; index < word.Length; index++, at++)
            {
                int unit = At(line, at);
                if (unit >= BasicText.Raw || Fold(unit) != word[index])
                {
                    matched = false;
                    break;
                }
            }

            if (!matched) { continue; }

            // A word followed by a letter, digit or dot is a name's start, unless it is FN, USR, TAB( or SPC(.
            int next = Fold(At(line, at));
            bool named = next is >= 'A' and <= 'Z' or >= '0' and <= '9' or '.';
            bool apart = word[^1] == '(' || token is FnToken or UsrToken || !named;
            return apart ? (token, at) : null;
        }

        return null;
    }

    // LINGET: a line number's digits, spaces between them skipped, leaving x after the last digit.
    private static int LineNumber(int[] line, ref int x)
    {
        int value = 0;
        int end = x;
        while (true)
        {
            int unit = At(line, x);
            if (unit is >= '0' and <= '9')
            {
                value = (value * 10) + (unit - '0');
                if (value > 65529) { throw new FormatException("?Syntax error: a line number is at most 65529."); }
                x++;
                end = x;
            }
            else if (unit == ' ')
            {
                x++;
            }
            else
            {
                break;
            }
        }

        x = end;
        return value;
    }

    // Copies typed characters up to the end character, leaving x on it; false at the end of the line.
    private static bool CopyTo(int[] line, ref int x, CrunchOutput output, int endChar)
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
}
