// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Globalization;
using System.Text;

namespace Retrocore.Basic;

/// <summary>
///  The Apple II's Integer BASIC: Steve Wozniak's BASIC of 16-bit integers, in the II's ROM; and Apple-1 BASIC, the
///  same BASIC as it first was, for the Apple-1.
/// </summary>
/// <remarks>
///  <para>
///   Integer BASIC differs from the Microsoft BASICs in how it keeps a program. Its lines lie from PP ($CA) up to
///   HIMEM ($4C), the program growing down as lines are added; each is a length byte, the line number, its tokens and
///   $01. Its variables lie below, from LOMEM ($4A) up to PV ($CC). A token is below $80 and is a place in the syntax
///   tables, so one word has several (<see cref="IntegerBasicSyntax"/>); constants, names and string characters have
///   bit 7 set.
///  </para>
///  <para>
///   <see cref="BasicDialect.Tokenize(string)"/> gives those tokens, checked as the ROM checks a typed line. For the
///   analysis the other dialects share (sites, labels, statements, expressions), <see cref="Crunch"/> gives the same
///   line in the Microsoft form instead: each reserved word or operator as a token from $80, in the order of
///   <see cref="Keywords"/>, and everything else as plain characters.
///  </para>
///  <para>
///   Apple-1 BASIC keeps a program the same way, at the same page-zero locations, with tokens from its own syntax
///   table (<see cref="Apple1Basic"/>). Its variables and FOR stack are laid out differently.
///  </para>
/// </remarks>
internal sealed class IntegerBasicDialect : BasicDialect
{
    /// <summary>
    ///  The end-of-line token.
    /// </summary>
    internal const byte EndOfLine = 0x01;

    /// <summary>
    ///  The colon between statements.
    /// </summary>
    internal const byte Colon = 0x03;

    /// <summary>
    ///  The opening quote of a string constant.
    /// </summary>
    internal const byte OpenQuote = 0x28;

    /// <summary>
    ///  The closing quote of a string constant.
    /// </summary>
    internal const byte CloseQuote = 0x29;

    /// <summary>
    ///  REM.
    /// </summary>
    internal const byte Remark = 0x5D;

    /// <summary>
    ///  LOMEM, the start of the variables (2 bytes).
    /// </summary>
    internal const int LoMem = 0x4A;

    /// <summary>
    ///  HIMEM, just above the program (2 bytes).
    /// </summary>
    internal const int HiMem = 0x4C;

    /// <summary>
    ///  PP, the program's first line (2 bytes).
    /// </summary>
    internal const int Pp = 0xCA;

    /// <summary>
    ///  PV, just past the variables (2 bytes).
    /// </summary>
    internal const int Pv = 0xCC;

    /// <summary>
    ///  RUNFLAG: bit 7 set while a program runs.
    /// </summary>
    internal const int RunFlag = 0xD9;

    /// <summary>
    ///  PR, the address of the line running (2 bytes).
    /// </summary>
    internal const int Pr = 0xDC;

    /// <summary>
    ///  PX, the address of the token running (2 bytes).
    /// </summary>
    internal const int Px = 0xE0;

    /// <summary>
    ///  FORNDX, the count of active FOR loops.
    /// </summary>
    internal const int ForIndex = 0xFB;

    /// <summary>
    ///  GOSUBNDX, the count of active GOSUBs.
    /// </summary>
    internal const int GosubIndex = 0xFC;


    // The reserved words and operators of Crunch's Microsoft form, in token order from $80.
    private static readonly string[] s_keywords =
    [
        "HIMEM:", "LOMEM:", "LOAD", "SAVE", "CON", "RUN", "DEL", "NEW", "CLR", "AUTO", "MAN",
        "+", "-", "*", "/", "=", "#", ">=", ">", "<=", "<>", "<", "AND", "OR", "MOD", "^", "NOT",
        "THEN", "PEEK", "RND", "SGN", "ABS", "PDL", "RNDX", "LEN", "ASC", "SCRN", "TEXT", "GR", "CALL", "DIM",
        "TAB", "END", "INPUT", "FOR", "TO", "STEP", "NEXT", "RETURN", "GOSUB", "REM", "LET", "GOTO", "IF",
        "PRINT", "POKE", "COLOR=", "PLOT", "HLIN", "AT", "VLIN", "VTAB", "LIST", "POP", "NODSP", "NOTRACE",
        "DSP", "TRACE", "PR#", "IN#"
    ];

    // Apple-1 BASIC's, the same way.
    private static readonly string[] s_apple1Keywords =
    [
        "HIMEM=", "LOMEM=", "LIST", "RUN", "DEL", "SCR", "CLR", "AUTO", "OFF",
        "+", "-", "*", "/", "=", "#", ">=", ">", "<=", "<>", "<", "AND", "OR", "MOD", "^", "NOT",
        "THEN", "PEEK", "RND", "SGN", "ABS", "USR", "RNDX", "LEN", "COLOR", "HIMEM", "LOMEM", "CALL", "DIM",
        "TAB", "END", "INPUT", "FOR", "TO", "STEP", "NEXT", "RETURN", "GOSUB", "REM", "LET", "GOTO", "IF",
        "PRINT", "POKE", "COLOR=", "PLOT", "HLIN", "AT"
    ];

    private readonly string[] _keywords;
    private readonly Dictionary<string, int> _keywordIndex;
    private readonly string[] _spellings;

    private IntegerBasicDialect(string name, string displayName, string[] keywords, string[] spellings, IntegerSyntaxTables tables)
    {
        Name = name;
        DisplayName = displayName;
        _keywords = keywords;
        _keywordIndex = keywords
            .Select((word, index) => (word, index))
            .ToDictionary(entry => entry.word, entry => entry.index, StringComparer.Ordinal);

        _spellings = spellings;
        Tables = tables;
    }

    /// <summary>
    ///  Gets the Apple II's Integer BASIC.
    /// </summary>
    internal static IntegerBasicDialect Instance { get; } = new(
        "integer",
        "Integer BASIC",
        s_keywords,
        IntegerBasic.Spellings,
        IntegerBasicSyntax.Integer);

    /// <summary>
    ///  Gets Apple-1 BASIC.
    /// </summary>
    internal static IntegerBasicDialect Apple1Basic { get; } = new(
        "apple1",
        "Apple-1 BASIC",
        s_apple1Keywords,
        IntegerBasic.Apple1Spellings,
        IntegerBasicSyntax.Apple1);

    /// <inheritdoc/>
    public override string Name { get; }

    /// <inheritdoc/>
    public override string DisplayName { get; }

    /// <summary>
    ///  Gets whether this is Apple-1 BASIC, whose variables and FOR stack are laid out differently.
    /// </summary>
    internal bool IsApple1 => ReferenceEquals(this, Apple1Basic);

    /// <summary>
    ///  Gets the syntax tables the tokenizer matches lines against.
    /// </summary>
    internal IntegerSyntaxTables Tables { get; }

    /// <summary>
    ///  Gets how LIST spells a token.
    /// </summary>
    /// <param name="token">The token, below $80.</param>
    /// <returns>Its spelling, such as <c>PRINT</c> or <c>,</c>; <c>?</c> for a token the BASIC does not have.</returns>
    internal string Spelling(byte token) => (token & 0x7F) < _spellings.Length ? _spellings[token & 0x7F] : "?";

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   These are the tokens of <see cref="Crunch"/>'s Microsoft form. Integer BASIC's own tokens are below $80, and
    ///   several stand for each word.
    ///  </para>
    /// </remarks>
    public override IReadOnlyList<string> Keywords => _keywords;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   A typed line number stops at 32767, but Integer BASIC keeps 16-bit numbers, and programs such as the System
    ///   Master's have lines up to 65535, which it lists and runs.
    ///  </para>
    /// </remarks>
    public override int MaximumLineNumber => 65535;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   Integer BASIC's program ends at HIMEM rather than starting at a fixed place, and its lines hold no addresses,
    ///   so this is only where a 16K machine would start it.
    ///  </para>
    /// </remarks>
    public override int DefaultLoadAddress => 0x0800;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   Integer BASIC's program runs from PP up to HIMEM, so <see cref="BasicPointers.ProgramStart"/> is PP and
    ///   <see cref="BasicPointers.Variables"/>, the end of the program, is HIMEM. Its variables are LOMEM up to PV,
    ///   below the program. <see cref="BasicPointers.CurrentLine"/> is PR, the address of the line running rather than
    ///   its number.
    ///  </para>
    /// </remarks>
    public override BasicPointers Pointers { get; } = new()
    {
        ProgramStart = Pp,
        Variables = HiMem,
        Arrays = Pv,
        FreeStart = Pv,
        StringBottom = Pv,
        MemoryTop = HiMem,
        CurrentLine = Pr,
        ContinueText = Pr,
        DataPointer = Pv
    };

    /// <inheritdoc/>
    public override int InputLimit => 239;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   Integer BASIC's line is its length and its number before the tokens.
    ///  </para>
    /// </remarks>
    internal override int LineHeader => 3;

    /// <inheritdoc/>
    internal override int LineOverhead => 4;

    /// <inheritdoc/>
    internal override byte RemToken => (byte)(FirstToken + _keywordIndex["REM"]);

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   Integer BASIC has no DATA, so no token is it.
    ///  </para>
    /// </remarks>
    internal override byte DataToken => 0xFF;

    /// <inheritdoc/>
    internal override bool ListingSpaces => true;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   Integer BASIC runs a program while bit 7 of RUNFLAG is set.
    ///  </para>
    /// </remarks>
    public override bool InDirectMode(IBasicMemory memory) => (memory.Read(RunFlag) & 0x80) == 0;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   These are the stored tokens, without the length, the number and the $01 that frame them, as the ROM stores a
    ///   typed line. A line the ROM refuses throws <see cref="BasicSyntaxException"/>.
    ///  </para>
    /// </remarks>
    public override byte[] Tokenize(string text)
    {
        ArgumentNullException.ThrowIfNull(text);
        IntegerSyntaxResult result = Typed(BasicText.Parse(text));
        if (result.Error is { } error)
        {
            throw new BasicSyntaxException(Message(error), Math.Max(0, result.Column - 1));
        }

        return result.Tokens[3..^1];
    }

    /// <inheritdoc/>
    public override string Detokenize(ReadOnlySpan<byte> line)
    {
        StringBuilder text = new(line.Length * 2);
        int at = 0;
        bool inName = false;
        bool space = false;
        while (at < line.Length)
        {
            byte token = line[at++];
            if (space)
            {
                text.Append(' ');
                space = false;
            }

            if (token >= 0x80)
            {
                if (token is >= 0xB0 and <= 0xB9 && !inName && at + 1 < line.Length)
                {
                    // A constant: its value, with the zero it was typed with when that was its first digit.
                    int value = line[at] | (line[at + 1] << 8);
                    if (token == 0xB0 && value != 0) { text.Append('0'); }
                    text.Append(value.ToString(CultureInfo.InvariantCulture));
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
                while (at < line.Length && line[at] != CloseQuote)
                {
                    // A quote inside a string cannot be typed, as it ends the string; it is shown as a byte.
                    if (line[at] == 0xA2) { BasicText.AppendEscape(text, line[at++]); }
                    else { AppendLiteral(text, line[at++]); }
                }

                if (at < line.Length) { at++; }
                text.Append('"');
                continue;
            }

            string word = Spelling(token);
            bool keyword = char.IsAsciiLetter(word[0]);
            if (keyword && text.Length > 0 && text[^1] != ' ') { text.Append(' '); }
            text.Append(word);
            if (token == Remark)
            {
                while (at < line.Length) { AppendLiteral(text, line[at++]); }
                break;
            }

            space = (keyword && char.IsAsciiLetter(word[^1])) || token == Colon;
        }

        return text.ToString();
    }

    /// <summary>
    ///  Reads the program from PP up to HIMEM.
    /// </summary>
    /// <param name="memory">The memory.</param>
    /// <returns>The program.</returns>
    /// <exception cref="InvalidDataException">The pointers or a line's length do not describe a program.</exception>
    internal BasicProgram Read(IBasicMemory memory)
    {
        int start = BasicProgram.Word(memory, Pp);
        int end = BasicProgram.Word(memory, HiMem);
        if (start == 0 || end < start)
        {
            throw new InvalidDataException($"{DisplayName} is not set up: its program is at ${start:X4} and HIMEM is ${end:X4}.");
        }

        byte[] bytes = new byte[end - start];
        for (int index = 0; index < bytes.Length; index++) { bytes[index] = memory.Read(start + index); }
        return FromImage(bytes);
    }

    /// <summary>
    ///  Reads a program as Integer BASIC keeps it, as a DOS 3.3 <c>I</c> file holds it after its length.
    /// </summary>
    /// <param name="bytes">The lines.</param>
    /// <returns>The program.</returns>
    /// <exception cref="InvalidDataException">A line's length runs past the end, or it does not end in $01.</exception>
    internal BasicProgram FromImage(ReadOnlySpan<byte> bytes)
    {
        List<BasicLine> lines = [];
        int at = 0;
        while (at < bytes.Length)
        {
            int length = bytes[at];
            if (length < LineOverhead || at + length > bytes.Length || bytes[at + length - 1] != EndOfLine)
            {
                throw new InvalidDataException($"The line at offset {at} is not an Integer BASIC line.");
            }

            lines.Add(new(bytes[at + 1] | (bytes[at + 2] << 8), bytes.Slice(at + 3, length - LineOverhead).ToArray()));
            at += length;
        }

        return new(this, lines);
    }

    /// <summary>
    ///  Gets a program as Integer BASIC keeps it: each line's length, number, tokens and $01.
    /// </summary>
    /// <param name="program">The program.</param>
    /// <returns>The bytes, as they lie from PP up to HIMEM.</returns>
    internal static byte[] Image(BasicProgram program)
    {
        List<byte> bytes = [];
        foreach (BasicLine line in program.Lines)
        {
            bytes.Add((byte)(line.Tokens.Length + Instance.LineOverhead));
            bytes.Add((byte)line.Number);
            bytes.Add((byte)(line.Number >> 8));
            bytes.AddRange(line.Tokens.Span);
            bytes.Add(EndOfLine);
        }

        return [.. bytes];
    }

    /// <summary>
    ///  Writes a program into memory so it ends at HIMEM, as typing it would leave it, and clears the variables.
    /// </summary>
    /// <param name="program">The program.</param>
    /// <param name="memory">The memory.</param>
    /// <exception cref="InvalidOperationException">The program does not fit between LOMEM and HIMEM.</exception>
    internal void Write(BasicProgram program, IBasicMemory memory)
    {
        byte[] image = Image(program);
        int top = BasicProgram.Word(memory, HiMem);
        int bottom = BasicProgram.Word(memory, LoMem);
        int start = top - image.Length;
        if (top == 0 || start < bottom)
        {
            throw new InvalidOperationException(
                $"The program needs {image.Length} bytes below HIMEM (${top:X4}), but LOMEM is ${bottom:X4}.");
        }

        for (int index = 0; index < image.Length; index++) { memory.Write(start + index, image[index]); }
        BasicProgram.WriteWord(memory, Pp, start);
        Clear(memory);
    }

    /// <inheritdoc/>
    internal override int WriteLimit(IBasicMemory memory) => BasicProgram.Word(memory, HiMem);

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   As CLR does: the variables end at LOMEM again, and the FOR and GOSUB stacks are empty.
    ///  </para>
    /// </remarks>
    internal override void Clear(IBasicMemory memory)
    {
        BasicProgram.WriteWord(memory, Pv, BasicProgram.Word(memory, LoMem));
        memory.Write(ForIndex, 0);
        memory.Write(GosubIndex, 0);
    }

    /// <inheritdoc/>
    internal override CrunchOutput Crunch(ReadOnlySpan<int> text)
    {
        IntegerSyntaxResult result = Typed(text);
        if (result.Error is not null) { return Approximate(text); }

        CrunchOutput output = new(result.Tokens.Length * 2);
        byte[] tokens = result.Tokens;
        int[] sources = result.Sources;
        bool inName = false;

        // The line number's marker and value, which the typed prefix added, come first.
        for (int at = 3; at < tokens.Length; at++)
        {
            byte token = tokens[at];
            int source = Math.Max(0, sources[at] - 1);
            if (token >= 0x80)
            {
                if (token is >= 0xB0 and <= 0xB9 && !inName && at + 2 < tokens.Length)
                {
                    string digits = (tokens[at + 1] | (tokens[at + 2] << 8)).ToString(CultureInfo.InvariantCulture);
                    int first = Math.Max(0, Math.Max(0, sources[at + 2] - 1) - digits.Length + 1);
                    for (int digit = 0; digit < digits.Length; digit++) { output.Add(digits[digit], first + digit); }
                    at += 2;
                    continue;
                }

                output.Add(token & 0x7F, source);
                inName = true;
                continue;
            }

            inName = false;
            if (token == EndOfLine) { break; }
            if (token == OpenQuote)
            {
                output.Add('"', source);
                while (at + 1 < tokens.Length && tokens[at + 1] != CloseQuote)
                {
                    at++;
                    output.Add(tokens[at] & 0x7F, Math.Max(0, sources[at] - 1));
                }

                if (at + 1 < tokens.Length)
                {
                    at++;
                    output.Add('"', Math.Max(0, sources[at] - 1));
                }

                continue;
            }

            string word = Spelling(token);
            if (token == Remark)
            {
                output.Add(RemToken, Math.Max(0, source - 2));
                while (at + 1 < tokens.Length && tokens[at + 1] != EndOfLine)
                {
                    at++;
                    output.Add(tokens[at] & 0x7F, Math.Max(0, sources[at] - 1));
                }

                continue;
            }

            AddWord(output, word, source);
        }

        return output;
    }

    /// <inheritdoc/>
    internal override string AfterLineNumber(string line, int index) => line[index..];

    /// <inheritdoc/>
    internal override void AppendKeyword(StringBuilder builder, string keyword, out bool spaceAfter)
    {
        builder.Append(keyword);
        spaceAfter = char.IsAsciiLetter(keyword[^1]);
    }

    /// <inheritdoc/>
    internal override bool StartsSearch(byte value) => false;

    /// <summary>
    ///  Gets the offset in a line's stored tokens where each of its statements starts: the first, and each after a
    ///  colon ($03).
    /// </summary>
    /// <param name="tokens">The stored tokens, without the length, number and $01.</param>
    /// <returns>The offsets.</returns>
    internal static List<int> StatementOffsets(ReadOnlySpan<byte> tokens)
    {
        List<int> offsets = [0];
        bool inName = false;
        for (int at = 0; at < tokens.Length; at++)
        {
            byte token = tokens[at];
            if (token >= 0x80)
            {
                if (token is >= 0xB0 and <= 0xB9 && !inName)
                {
                    at += 2;
                    continue;
                }

                inName = true;
                continue;
            }

            inName = false;
            if (token == OpenQuote)
            {
                while (at + 1 < tokens.Length && tokens[at + 1] != CloseQuote) { at++; }
                at++;
            }
            else if (token == Remark)
            {
                break;
            }
            else if (token == Colon && at + 1 < tokens.Length)
            {
                offsets.Add(at + 1);
            }
        }

        return offsets;
    }

    /// <summary>
    ///  Gets a line's tokens with every constant's marker made 0.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   A constant's marker is the first digit it was typed with, which nothing reads; RENUMBER changes a line
    ///   number's value and leaves its marker, so no text types those tokens back exactly. Two lines are the same
    ///   program when they are the same without their markers.
    ///  </para>
    /// </remarks>
    /// <param name="tokens">The tokens.</param>
    /// <returns>The tokens, the markers $B0.</returns>
    internal static byte[] WithoutMarkers(ReadOnlySpan<byte> tokens)
    {
        byte[] result = tokens.ToArray();
        bool inName = false;
        for (int at = 0; at < result.Length; at++)
        {
            byte token = result[at];
            if (token >= 0x80)
            {
                if (token is >= 0xB0 and <= 0xB9 && !inName)
                {
                    result[at] = 0xB0;
                    at += 2;
                    continue;
                }

                inName = true;
                continue;
            }

            inName = false;
            if (token == OpenQuote)
            {
                while (at + 1 < result.Length && result[at + 1] != CloseQuote) { at++; }
                at++;
            }
            else if (token == Remark)
            {
                break;
            }
        }

        return result;
    }

    /// <summary>
    ///  Gets the message for a line the tokenizer refuses: what the BASIC prints, and what it means.
    /// </summary>
    /// <param name="error">The error.</param>
    /// <returns>The message.</returns>
    internal string Message(IntegerSyntaxError error) => error switch
    {
        IntegerSyntaxError.TooLarge => "*** >32767 ERR: a number is above 32767.",
        IntegerSyntaxError.TooLong => "*** TOO LONG ERR: the line is too long or too deeply nested.",
        _ => $"*** SYNTAX ERR: {DisplayName} refuses this statement."
    };

    // Tokenizes statements as they would be typed after a line number, the number 0. The tokenizer skips blanks
    // outside strings and remarks, so they are left out, leaving the most room in the input buffer for a line a
    // listing has spaced out; the positions it reports are mapped back to the statements' own.
    private IntegerSyntaxResult Typed(ReadOnlySpan<int> text)
    {
        List<int> line = new(text.Length + 1) { '0' };
        List<int> map = new(text.Length + 1) { 0 };
        bool quoted = false;
        bool remark = false;
        for (int index = 0; index < text.Length; index++)
        {
            int unit = text[index];
            if (unit == '"') { quoted = !quoted; }
            if (unit == ' ' && !quoted && !remark) { continue; }
            line.Add(unit);
            map.Add(index + 1);
            remark |= !quoted && line.Count >= 4 && IsRem(line[^3], line[^2], line[^1]);
        }

        IntegerSyntaxResult result = IntegerBasicSyntax.Tokenize(line.ToArray(), Tables);
        int end = text.Length + 1;
        int Back(int at) => at < map.Count ? map[at] : end;
        return result with
        {
            Sources = [.. result.Sources.Select(Back)],
            Column = result.Error is null ? 0 : Back(result.Column)
        };

        static bool IsRem(int r, int e, int m) => Fold(r) == 'R' && Fold(e) == 'E' && Fold(m) == 'M';
    }

    // A refused line's statements in the Microsoft form, by its words alone, so a line being typed still has sites.
    private CrunchOutput Approximate(ReadOnlySpan<int> text)
    {
        CrunchOutput output = new(text.Length);
        int at = 0;
        while (at < text.Length)
        {
            int unit = text[at];
            if (unit == '"')
            {
                output.Add('"', at++);
                while (at < text.Length && text[at] != '"') { output.Add(text[at], at++); }
                if (at < text.Length) { output.Add('"', at++); }
                continue;
            }

            if (unit == ' ')
            {
                at++;
                continue;
            }

            string? matched = null;
            foreach (string word in _keywords)
            {
                if (Starts(text, at, word) && word.Length > (matched?.Length ?? 0)) { matched = word; }
            }

            if (matched is null)
            {
                output.Add(Fold(unit), at++);
                continue;
            }

            output.Add(FirstToken + _keywordIndex[matched], at);
            at += matched.Length;
            if (matched == "REM")
            {
                while (at < text.Length) { output.Add(text[at], at++); }
            }
        }

        return output;
    }

    private static bool Starts(ReadOnlySpan<int> text, int at, string word)
    {
        if (at + word.Length > text.Length) { return false; }
        for (int index = 0; index < word.Length; index++)
        {
            if (Fold(text[at + index]) != word[index]) { return false; }
        }

        return true;
    }

    // A reserved word or operator as its token, or punctuation as itself; a word ending in a parenthesis is the word
    // then the parenthesis.
    private void AddWord(CrunchOutput output, string word, int source)
    {
        int start = Math.Max(0, source - word.Length + 1);
        string bare = word.Length > 1 && word[^1] == '(' ? word[..^1] : word;
        if (_keywordIndex.TryGetValue(bare, out int index))
        {
            output.Add(FirstToken + index, start);
            if (bare.Length != word.Length) { output.Add('(', source); }
            return;
        }

        for (int character = 0; character < word.Length; character++)
        {
            output.Add(word[character], start + character);
        }
    }

    // A string's or remark's character as the text form writes it.
    private static void AppendLiteral(StringBuilder text, byte value)
    {
        if (value < 0x80)
        {
            BasicText.AppendEscape(text, value);
            return;
        }

        BasicText.AppendCharacter(text, (byte)(value & 0x7F));
    }
}
