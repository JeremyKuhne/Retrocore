// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text;

namespace Retrocore.Basic;

/// <summary>
///  Atari BASIC, the 400's and 800's cartridge, as its rev. C tokenizes and lists a program.
/// </summary>
/// <remarks>
///  <para>
///   Atari BASIC keeps a program in tables above LOMEM ($80) and its 256-byte token buffer: the variable name table
///   from VNTP ($82) to VNTD ($84), each name's last character with bit 7 set; the variable value table from VVTP
///   ($86), eight bytes a variable; and the statement table from STMTAB ($88), the lines in order and then the
///   immediate line, numbered 32768. STARP ($8C) follows, where the strings and arrays go, then the run-time stack
///   from RUNSTK ($8E) up to BASIC's MEMTOP ($90).
///  </para>
///  <para>
///   A line is its number, its length and its statements, each the offset of the next from the line's start, the
///   statement's token and its tokens. A variable is $80 and its number in the name table, so a line's tokens mean
///   nothing without the table; each program has its own dialect, which carries the names it numbers its variables
///   by (<see cref="Names"/>). Tokenizing a program's lines in order adds their names as typing them would.
///  </para>
///  <para>
///   <see cref="BasicDialect.Tokenize(string)"/> gives the stored tokens, checked as the ROM checks a typed line
///   (<see cref="AtariBasicSyntax"/>). For the analysis the other dialects share (sites, labels, statements,
///   expressions), <see cref="Crunch"/> gives the same line in the Microsoft form instead: each statement's name,
///   operator word and function as a token from $80, in the order of <see cref="Keywords"/>, and everything else as
///   plain characters.
///  </para>
/// </remarks>
internal sealed class AtariBasicDialect : BasicDialect
{
    /// <summary>
    ///  LOMEM: the token buffer, and BASIC's memory's start (2 bytes).
    /// </summary>
    internal const int Lomem = 0x80;

    /// <summary>
    ///  VNTP: the variable name table (2 bytes).
    /// </summary>
    internal const int Vntp = 0x82;

    /// <summary>
    ///  VNTD: the variable name table's end, its dummy zero byte (2 bytes).
    /// </summary>
    internal const int Vntd = 0x84;

    /// <summary>
    ///  VVTP: the variable value table (2 bytes).
    /// </summary>
    internal const int Vvtp = 0x86;

    /// <summary>
    ///  STMTAB: the statement table (2 bytes).
    /// </summary>
    internal const int Stmtab = 0x88;

    /// <summary>
    ///  STMCUR: the line being run or entered (2 bytes).
    /// </summary>
    internal const int Stmcur = 0x8A;

    /// <summary>
    ///  STARP: the string and array area (2 bytes).
    /// </summary>
    internal const int Starp = 0x8C;

    /// <summary>
    ///  RUNSTK: the run-time stack (2 bytes).
    /// </summary>
    internal const int Runstk = 0x8E;

    /// <summary>
    ///  BASIC's MEMTOP: the run-time stack's end (2 bytes).
    /// </summary>
    internal const int BasicMemtop = 0x90;

    /// <summary>
    ///  DATA_LINE: the line READ reads DATA from (2 bytes).
    /// </summary>
    internal const int DataLine = 0xB7;

    /// <summary>
    ///  DATA_ELEMENT: the next DATA element READ reads.
    /// </summary>
    internal const int DataElement = 0xB6;

    /// <summary>
    ///  STOPLN: where the program stopped (2 bytes).
    /// </summary>
    internal const int Stopln = 0xBA;

    /// <summary>
    ///  APPMHI: the OS's lowest address the screen may not take (2 bytes).
    /// </summary>
    internal const int Appmhi = 0x0E;

    /// <summary>
    ///  The OS's MEMTOP: the top of the memory BASIC may use (2 bytes).
    /// </summary>
    internal const int OsMemtop = 0x02E5;

    /// <summary>
    ///  The immediate line's number, after every program line.
    /// </summary>
    internal const int ImmediateLine = 0x8000;

    /// <summary>
    ///  The bytes before a line's statements: its number and length.
    /// </summary>
    internal const int Header = 3;

    /// <summary>
    ///  A variable value table entry's size.
    /// </summary>
    internal const int ValueSize = 8;

    /// <summary>
    ///  The header SAVE writes: LOMEM to STARP, each less LOMEM.
    /// </summary>
    internal const int SaveHeaderSize = 14;

    /// <summary>
    ///  The statement tokens of REM and DATA, which keep their text as typed.
    /// </summary>
    internal const byte RemStatement = 0x00;

    /// <summary>
    ///  DATA's statement token.
    /// </summary>
    internal const byte DataStatement = 0x01;

    /// <summary>
    ///  The token of a numeric constant: then its six bytes.
    /// </summary>
    internal const byte NumberToken = 0x0E;

    /// <summary>
    ///  The token of a string constant: then its length and characters.
    /// </summary>
    internal const byte StringToken = 0x0F;

    /// <summary>
    ///  The token that ends a line.
    /// </summary>
    internal const byte LineEnd = 0x16;

    /// <summary>
    ///  The first function's token, STR$.
    /// </summary>
    internal const byte FirstFunction = 0x3D;

    private const int TokenBuffer = 0x100;
    private const byte NameEnd = 0x80;
    private const byte GoToStatement = 0x0B;

    // The statement and operator names, from the ROM's tables: statements by token from 0, operators from $10.
    private static readonly string[] s_statementNames = StatementNamesFromTables();
    private static readonly string[] s_operatorNames = OperatorNamesFromTables();

    // The reserved words of Crunch's Microsoft form, in token order from $80: the statements by their tokens (without
    // the implied LET and ERROR-), the operator words and symbols, then the functions by their tokens. A test checks
    // the statements and functions against the ROM's name tables.
    private static readonly string[] s_keywords =
    [
        "REM", "DATA", "INPUT", "COLOR", "LIST", "ENTER", "LET", "IF", "FOR", "NEXT", "GOTO", "GO TO", "GOSUB", "TRAP",
        "BYE", "CONT", "COM", "CLOSE", "CLR", "DEG", "DIM", "END", "NEW", "OPEN", "LOAD", "SAVE", "STATUS", "NOTE",
        "POINT", "XIO", "ON", "POKE", "PRINT", "RAD", "READ", "RESTORE", "RETURN", "RUN", "STOP", "POP", "?", "GET",
        "PUT", "GRAPHICS", "PLOT", "POSITION", "DOS", "DRAWTO", "SETCOLOR", "LOCATE", "SOUND", "LPRINT", "CSAVE",
        "CLOAD",
        "TO", "STEP", "THEN", "NOT", "OR", "AND", "<=", "<>", ">=", "<", ">", "=", "^", "*", "+", "-", "/",
        "STR$", "CHR$", "USR", "ASC", "VAL", "LEN", "ADR", "ATN", "COS", "PEEK", "SIN", "RND", "FRE", "EXP", "LOG",
        "CLOG", "SQR", "SGN", "ABS", "INT", "PADDLE", "STICK", "PTRIG", "STRIG"
    ];

    /// <summary>
    ///  Gets the statements' names, by token, as the ROM's statement name table spells them.
    /// </summary>
    internal static IReadOnlyList<string> StatementNames => s_statementNames;

    /// <summary>
    ///  Gets the operators' and functions' names, by token from $10, as the ROM's operator name table spells them.
    /// </summary>
    internal static IReadOnlyList<string> OperatorNames => s_operatorNames;

    private static readonly Dictionary<string, int> s_keywordIndex = s_keywords
        .Select((word, index) => (word, index))
        .GroupBy(entry => entry.word, StringComparer.Ordinal)
        .ToDictionary(group => group.Key, group => group.First().index, StringComparer.Ordinal);

    private readonly List<string> _names;

    private AtariBasicDialect(List<string> names) => _names = names;

    /// <summary>
    ///  Gets Atari BASIC, with no variables of its own: tokenizing with it numbers a line's variables from 0.
    /// </summary>
    internal static AtariBasicDialect Instance { get; } = new([]);

    /// <summary>
    ///  Gets the variable names this program's tokens number, in the order of the variable name table.
    /// </summary>
    internal IReadOnlyList<string> Names => _names;

    /// <summary>
    ///  Gets a dialect for a new program, whose lines number their variables as they are tokenized, in order.
    /// </summary>
    /// <returns>The dialect.</returns>
    internal static AtariBasicDialect Fresh() => new([]);

    /// <summary>
    ///  Gets a dialect for a program whose variables are already named.
    /// </summary>
    /// <param name="names">The names, in the variable name table's order.</param>
    /// <returns>The dialect.</returns>
    internal static AtariBasicDialect WithNames(IEnumerable<string> names) => new([.. names]);

    /// <inheritdoc/>
    public override string Name => "atari";

    /// <inheritdoc/>
    public override string DisplayName => "Atari BASIC";

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   These are the tokens of <see cref="Crunch"/>'s Microsoft form. Atari BASIC's own statement tokens are from 0,
    ///   its operators' and functions' from $10, and its variables' from $80.
    ///  </para>
    /// </remarks>
    public override IReadOnlyList<string> Keywords => s_keywords;

    /// <inheritdoc/>
    public override int MaximumLineNumber => 32767;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   Atari BASIC's tables start a page above LOMEM, which is the OS's MEMLO: $0700 with no DOS loaded.
    ///  </para>
    /// </remarks>
    public override int DefaultLoadAddress => 0x0800;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   The program is the statement table from STMTAB, so <see cref="BasicPointers.ProgramStart"/> is STMTAB, and
    ///   STARP ends it. <see cref="BasicPointers.CurrentLine"/> is STMCUR, the address of the line running rather than
    ///   its number; <see cref="BasicPointers.DataPointer"/> is DATA_LINE, the line READ reads.
    ///  </para>
    /// </remarks>
    public override BasicPointers Pointers { get; } = new()
    {
        ProgramStart = Stmtab,
        Variables = Starp,
        Arrays = Starp,
        FreeStart = Runstk,
        StringBottom = BasicMemtop,
        MemoryTop = OsMemtop,
        CurrentLine = Stmcur,
        ContinueText = Stmcur,
        DataPointer = DataLine
    };

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   The screen editor's logical line: three rows of 40 columns, less the margin.
    ///  </para>
    /// </remarks>
    public override int InputLimit => 114;

    /// <inheritdoc/>
    internal override int LineHeader => Header;

    /// <inheritdoc/>
    internal override int LineOverhead => Header;

    /// <inheritdoc/>
    internal override byte RemToken => (byte)(FirstToken + s_keywordIndex["REM"]);

    /// <inheritdoc/>
    internal override byte DataToken => (byte)(FirstToken + s_keywordIndex["DATA"]);

    /// <inheritdoc/>
    internal override bool ListingSpaces => true;

    /// <summary>
    ///  Gets a statement's name, as LIST spells it.
    /// </summary>
    /// <param name="token">The statement's token.</param>
    /// <returns>The name; the implied LET's is empty, and an unknown token's is <c>?</c>.</returns>
    internal static string StatementName(byte token) => token < s_statementNames.Length ? s_statementNames[token] : "?";

    /// <summary>
    ///  Gets an operator's or a function's name, as LIST spells it.
    /// </summary>
    /// <param name="token">The token, from $10.</param>
    /// <returns>The name, or <c>?</c> for a token Atari BASIC does not have.</returns>
    internal static string OperatorName(byte token) =>
        token >= 0x10 && token - 0x10 < s_operatorNames.Length ? s_operatorNames[token - 0x10] : "?";

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   Atari BASIC runs a program while STMCUR is a program line, rather than the immediate line, numbered 32768.
    ///  </para>
    /// </remarks>
    public override bool InDirectMode(IBasicMemory memory)
    {
        int line = BasicProgram.Word(memory, BasicProgram.Word(memory, Stmcur));
        return line >= ImmediateLine;
    }

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   These are the stored bytes after the line's number and length: each statement's offset from the line's
    ///   start, its token and its tokens. Variables are numbered by <see cref="Names"/>, and new ones are added to
    ///   them; <see cref="Instance"/> keeps none and numbers each line's from 0. A line the ROM refuses throws
    ///   <see cref="BasicSyntaxException"/>.
    ///  </para>
    /// </remarks>
    public override byte[] Tokenize(string text)
    {
        ArgumentNullException.ThrowIfNull(text);
        List<string> names = ReferenceEquals(this, Instance) ? [] : _names;
        AtariSyntaxResult result = AtariBasicSyntax.Tokenize(Atascii(BasicText.Parse(text)), names);
        if (result.Error is { } error) { throw new BasicSyntaxException(error, result.Column); }
        return result.Tokens;
    }

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   The line as LIST writes it: each statement's name and a space, then its tokens, an operator that is a word
    ///   spaced on both sides, without the trailing spaces.
    ///  </para>
    /// </remarks>
    public override string Detokenize(ReadOnlySpan<byte> line)
    {
        StringBuilder text = new(line.Length * 2);
        int at = 0;
        while (at < line.Length)
        {
            int next = line[at] - Header;
            if (next <= at || next > line.Length) { next = line.Length; }
            ListStatement(line, at + 1, next, text);
            at = next;
        }

        return text.ToString().TrimEnd();
    }

    /// <summary>
    ///  Reads the program from STMTAB up to the immediate line, with the variable name table's names.
    /// </summary>
    /// <param name="memory">The memory.</param>
    /// <returns>The program.</returns>
    /// <exception cref="InvalidDataException">The pointers or a line's length do not describe a program.</exception>
    internal BasicProgram Read(IBasicMemory memory)
    {
        int vntp = BasicProgram.Word(memory, Vntp);
        int vntd = BasicProgram.Word(memory, Vntd);
        int start = BasicProgram.Word(memory, Stmtab);
        int end = BasicProgram.Word(memory, Starp);
        if (vntp == 0 || vntd < vntp || start < vntd || end < start)
        {
            throw new InvalidDataException($"{DisplayName} is not set up: STMTAB is ${start:X4} and STARP ${end:X4}.");
        }

        byte[] names = new byte[vntd - vntp];
        for (int index = 0; index < names.Length; index++) { names[index] = memory.Read(vntp + index); }
        byte[] lines = new byte[end - start];
        for (int index = 0; index < lines.Length; index++) { lines[index] = memory.Read(start + index); }
        return new BasicProgram(WithNames(ParseNames(names)), ParseLines(lines));
    }

    /// <summary>
    ///  Reads a program as SAVE writes it: the header of LOMEM to STARP, each less LOMEM, then the tables.
    /// </summary>
    /// <param name="bytes">The file.</param>
    /// <returns>The program.</returns>
    /// <exception cref="InvalidDataException">The bytes are not a saved program.</exception>
    internal static BasicProgram FromImage(ReadOnlySpan<byte> bytes)
    {
        if (bytes.Length < SaveHeaderSize)
        {
            throw new InvalidDataException("A saved Atari BASIC program starts with a 14-byte header.");
        }

        int vntp = HeaderWord(bytes, Vntp);
        int vntd = HeaderWord(bytes, Vntd);
        int stmtab = HeaderWord(bytes, Stmtab);
        int starp = HeaderWord(bytes, Starp);
        int data = bytes.Length - SaveHeaderSize;
        if (HeaderWord(bytes, Lomem) != 0 || vntp != TokenBuffer || vntd < vntp || stmtab < vntd || starp < stmtab || starp - vntp > data)
        {
            throw new InvalidDataException("The header is not a saved Atari BASIC program's.");
        }

        ReadOnlySpan<byte> tables = bytes[SaveHeaderSize..];
        return new BasicProgram(
            WithNames(ParseNames(tables[..(vntd - vntp)])),
            ParseLines(tables[(stmtab - vntp)..(starp - vntp)]));
    }

    // A pointer's offset in SAVE's header.
    private static int HeaderWord(ReadOnlySpan<byte> bytes, int pointer) => bytes[pointer - Lomem] | (bytes[pointer - Lomem + 1] << 8);

    /// <summary>
    ///  Gets a program as SAVE writes it, with an empty immediate line, the variables cleared.
    /// </summary>
    /// <param name="program">The program.</param>
    /// <returns>The file's bytes.</returns>
    internal static byte[] Image(BasicProgram program)
    {
        byte[] tables = Tables(program, out int vntd, out int vvtp, out int stmtab, out int stmcur, out int starp);
        List<byte> bytes = [with(SaveHeaderSize + tables.Length)];
        foreach (int offset in (ReadOnlySpan<int>)[0, TokenBuffer, vntd, vvtp, stmtab, stmcur, starp])
        {
            bytes.Add((byte)offset);
            bytes.Add((byte)(offset >> 8));
        }

        bytes.AddRange(tables);
        return [.. bytes];
    }

    /// <summary>
    ///  Writes a program into memory as LOAD leaves one: the tables a page above LOMEM, an empty immediate line, and
    ///  the variables cleared, as CLR leaves them.
    /// </summary>
    /// <param name="program">The program.</param>
    /// <param name="memory">The memory.</param>
    /// <exception cref="InvalidOperationException">The program does not fit below the OS's MEMTOP.</exception>
    internal static void Write(BasicProgram program, IBasicMemory memory)
    {
        byte[] tables = Tables(program, out int vntd, out int vvtp, out int stmtab, out int stmcur, out int starp);
        int lomem = BasicProgram.Word(memory, Lomem);
        int top = BasicProgram.Word(memory, OsMemtop);
        int vntp = lomem + TokenBuffer;
        if (lomem == 0 || vntp + tables.Length >= top)
        {
            throw new InvalidOperationException(
                $"ERROR- 19: the program needs {tables.Length} bytes from ${vntp:X4}, and MEMTOP is ${top:X4}.");
        }

        for (int index = 0; index < tables.Length; index++) { memory.Write(vntp + index, tables[index]); }
        BasicProgram.WriteWord(memory, Vntp, vntp);
        BasicProgram.WriteWord(memory, Vntd, lomem + vntd);
        BasicProgram.WriteWord(memory, Vvtp, lomem + vvtp);
        BasicProgram.WriteWord(memory, Stmtab, lomem + stmtab);
        BasicProgram.WriteWord(memory, Stmcur, lomem + stmcur);
        BasicProgram.WriteWord(memory, Starp, lomem + starp);
        Instance.Clear(memory);
    }

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   The program's lines as the statement table holds them from STMTAB, without the immediate line after them.
    ///  </para>
    /// </remarks>
    internal override byte[] MemoryImage(BasicProgram program, int start)
    {
        List<byte> bytes = [];
        foreach (BasicLine line in program.Lines)
        {
            bytes.Add((byte)line.Number);
            bytes.Add((byte)(line.Number >> 8));
            bytes.Add((byte)(line.Tokens.Length + Header));
            bytes.AddRange(line.Tokens.Span);
        }

        return [.. bytes];
    }

    /// <inheritdoc/>
    internal override int WriteLimit(IBasicMemory memory) => BasicProgram.Word(memory, OsMemtop);

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   From STMTAB to the immediate line, which follows every program line.
    ///  </para>
    /// </remarks>
    internal override (int Start, int End) ProgramBounds(IBasicMemory memory)
    {
        int start = BasicProgram.Word(memory, Stmtab);
        int end = BasicProgram.Word(memory, Starp);
        int at = start;
        while (at + Header <= end && BasicProgram.Word(memory, at) < ImmediateLine)
        {
            int length = memory.Read(at + 2);
            if (length < Header) { break; }
            at += length;
        }

        return (start, at);
    }

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   As CLR does: every variable's value is zero and its DIMension gone, the strings and arrays freed, the run-time
    ///   stack empty, and READ back at the first DATA.
    ///  </para>
    /// </remarks>
    internal override void Clear(IBasicMemory memory)
    {
        int end = BasicProgram.Word(memory, Stmtab);
        for (int at = BasicProgram.Word(memory, Vvtp); at + ValueSize <= end; at += ValueSize)
        {
            memory.Write(at, (byte)(memory.Read(at) & ~0x01));
            for (int index = 2; index < ValueSize; index++) { memory.Write(at + index, 0); }
        }

        int starp = BasicProgram.Word(memory, Starp);
        BasicProgram.WriteWord(memory, Runstk, starp);
        BasicProgram.WriteWord(memory, BasicMemtop, starp);
        BasicProgram.WriteWord(memory, Appmhi, starp);
        BasicProgram.WriteWord(memory, DataLine, 0);
        memory.Write(DataElement, 0);
    }

    /// <inheritdoc/>
    internal override CrunchOutput Crunch(ReadOnlySpan<int> text)
    {
        // The tokenizer's names: this program's, then the line's new ones, which the program keeps no record of.
        List<string> names = [.. _names];
        AtariSyntaxResult result = AtariBasicSyntax.Tokenize(Atascii(text), names);
        if (result.Error is not null) { return Approximate(text); }
        CrunchOutput output = new(result.Tokens.Length * 2);
        byte[] tokens = result.Tokens;
        int[] sources = result.Sources;
        int at = 0;
        while (at < tokens.Length)
        {
            int next = tokens[at] - Header;
            if (next <= at || next > tokens.Length) { next = tokens.Length; }
            CrunchStatement(tokens, sources, at + 1, next, names, output);
            at = next;
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
    ///  Gets the offset in a line's stored tokens where each of its statements starts: its offset byte.
    /// </summary>
    /// <param name="tokens">The stored tokens, after the line's number and length.</param>
    /// <returns>The offsets.</returns>
    internal static List<int> StatementOffsets(ReadOnlySpan<byte> tokens)
    {
        List<int> offsets = [];
        int at = 0;
        while (at < tokens.Length)
        {
            offsets.Add(at);
            int next = tokens[at] - Header;
            if (next <= at) { break; }
            at = next;
        }

        return offsets;
    }

    /// <summary>
    ///  Turns the units of a line's text into the ATASCII bytes the line editor would have in its buffer.
    /// </summary>
    /// <param name="units">The units.</param>
    /// <returns>The bytes.</returns>
    internal static byte[] Atascii(ReadOnlySpan<int> units)
    {
        byte[] bytes = new byte[units.Length];
        for (int index = 0; index < units.Length; index++)
        {
            int unit = units[index];
            bytes[index] = (unit & BasicText.Raw) != 0 ? (byte)unit : unit < 0x80 ? (byte)unit : (byte)'?';
        }

        return bytes;
    }

    // The names in a variable name table's bytes: each to its character with bit 7 set.
    private static List<string> ParseNames(ReadOnlySpan<byte> bytes)
    {
        List<string> names = [];
        int start = 0;
        for (int at = 0; at < bytes.Length && bytes[at] != 0; at++)
        {
            if ((bytes[at] & NameEnd) == 0) { continue; }
            names.Add(Text(bytes[start..(at + 1)], 0));
            start = at + 1;
        }

        return names;
    }

    // The lines in a statement table's bytes, to the immediate line.
    private static List<BasicLine> ParseLines(ReadOnlySpan<byte> bytes)
    {
        List<BasicLine> lines = [];
        int at = 0;
        while (at + Header <= bytes.Length)
        {
            int number = bytes[at] | (bytes[at + 1] << 8);
            if (number >= ImmediateLine) { break; }
            int length = bytes[at + 2];
            if (length < Header || at + length > bytes.Length)
            {
                throw new InvalidDataException($"Line {number} at offset {at} is not an Atari BASIC line.");
            }

            lines.Add(new(number, bytes.Slice(at + Header, length - Header).ToArray()));
            at += length;
        }

        return lines;
    }

    // The tables from VNTP, with the offsets from LOMEM SAVE gives them: the names and their dummy zero, the values,
    // the lines and an empty immediate line.
    private static byte[] Tables(BasicProgram program, out int vntd, out int vvtp, out int stmtab, out int stmcur, out int starp)
    {
        IReadOnlyList<string> names = program.Dialect is AtariBasicDialect atari ? atari.Names : [];
        List<byte> bytes = [];
        foreach (string name in names)
        {
            for (int index = 0; index < name.Length; index++)
            {
                bytes.Add((byte)(name[index] | (index == name.Length - 1 ? NameEnd : 0)));
            }
        }

        vntd = TokenBuffer + bytes.Count;
        bytes.Add(0);
        vvtp = TokenBuffer + bytes.Count;
        for (int number = 0; number < names.Count; number++)
        {
            byte type = names[number].EndsWith('$') ? (byte)0x80 : names[number].EndsWith('(') ? (byte)0x40 : (byte)0;
            bytes.AddRange([type, (byte)number, 0, 0, 0, 0, 0, 0]);
        }

        stmtab = TokenBuffer + bytes.Count;
        foreach (BasicLine line in program.Lines)
        {
            bytes.Add((byte)line.Number);
            bytes.Add((byte)(line.Number >> 8));
            bytes.Add((byte)(line.Tokens.Length + Header));
            bytes.AddRange(line.Tokens.Span);
        }

        stmcur = TokenBuffer + bytes.Count;
        bytes.AddRange([0x00, 0x80, Header]);
        starp = TokenBuffer + bytes.Count;
        return [.. bytes];
    }

    // LIST_STATEMENT: the statement whose token is at an index, to the next statement's offset.
    private void ListStatement(ReadOnlySpan<byte> line, int token, int next, StringBuilder text)
    {
        if (token >= next) { return; }
        byte statement = line[token];
        if (statement != AtariBasicSyntax.ImpliedLet)
        {
            text.Append(StatementName(statement)).Append(' ');
            if (statement is RemStatement or DataStatement or AtariBasicSyntax.ErrorToken)
            {
                for (int at = token + 1; at < next && line[at] != AtariNumbers.EndOfLine; at++)
                {
                    BasicText.AppendCharacter(text, line[at]);
                }

                return;
            }
        }

        for (int at = token + 1; at < next; at++)
        {
            byte value = line[at];
            if (value >= 0x80)
            {
                string name = VariableName(value);
                text.Append(name);
                if (name.EndsWith('(')) { at++; }
            }
            else if (value == StringToken && at + 1 < next)
            {
                int length = line[++at];
                text.Append('"');
                for (int index = 0; index < length && at + 1 < next; index++)
                {
                    BasicText.AppendCharacter(text, line[++at]);
                }

                text.Append('"');
            }
            else if (value < StringToken)
            {
                if (at + AtariNumbers.Size >= next) { break; }
                text.Append(AtariNumbers.Format(line.Slice(at + 1, AtariNumbers.Size)));
                at += AtariNumbers.Size;
            }
            else if (value != LineEnd)
            {
                string name = OperatorName(value);
                bool word = value < FirstFunction && name.Length > 0 && char.IsAsciiLetter(name[0]);
                text.Append(word ? $" {name} " : name);
            }
        }
    }

    private string VariableName(byte token) =>
        (token & 0x7F) < _names.Count ? _names[token & 0x7F] : $"{{V{token & 0x7F}}}";

    // A statement in the Microsoft form, each character at the place it came from.
    private static void CrunchStatement(
        byte[] tokens,
        int[] sources,
        int token,
        int next,
        List<string> names,
        CrunchOutput output)
    {
        if (token >= next) { return; }
        byte statement = tokens[token];
        int source = Math.Max(0, sources[token]);
        if (statement != AtariBasicSyntax.ImpliedLet)
        {
            string word = statement == GoToStatement ? "GOTO" : StatementName(statement);
            if (s_keywordIndex.TryGetValue(word, out int index)) { output.Add(FirstToken + index, source); }
            if (statement is RemStatement or DataStatement or AtariBasicSyntax.ErrorToken)
            {
                for (int at = token + 1; at < next && tokens[at] != AtariNumbers.EndOfLine; at++)
                {
                    output.Add(tokens[at], Math.Max(0, sources[at]));
                }

                return;
            }
        }

        for (int at = token + 1; at < next; at++)
        {
            byte value = tokens[at];
            source = Math.Max(0, sources[at]);
            if (value >= 0x80)
            {
                string name = (value & 0x7F) < names.Count ? names[value & 0x7F] : "V";
                for (int index = 0; index < name.Length; index++) { output.Add(name[index], source + index); }
                if (name.EndsWith('(')) { at++; }
            }
            else if (value == StringToken && at + 1 < next)
            {
                int length = tokens[++at];
                output.Add('"', source);
                for (int index = 0; index < length && at + 1 < next; index++)
                {
                    at++;
                    output.Add(tokens[at], Math.Max(0, sources[at]));
                }

                output.Add('"', source + length + 1);
            }
            else if (value < StringToken)
            {
                if (at + AtariNumbers.Size >= next) { break; }
                string digits = AtariNumbers.Format(tokens.AsSpan(at + 1, AtariNumbers.Size));
                for (int index = 0; index < digits.Length; index++) { output.Add(digits[index], source + index); }
                at += AtariNumbers.Size;
            }
            else if (value == LineEnd)
            {
                break;
            }
            else
            {
                string name = value switch
                {
                    0x17 => "GOTO",
                    0x18 => "GOSUB",
                    _ => OperatorName(value)
                };

                if (s_keywordIndex.TryGetValue(name, out int index))
                {
                    output.Add(FirstToken + index, source);
                }
                else
                {
                    foreach (char character in name) { output.Add(character, source); }
                }
            }
        }
    }

    // A refused line's statements in the Microsoft form, by its words alone, so a line being typed still has sites.
    private static CrunchOutput Approximate(ReadOnlySpan<int> text)
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
            if (char.IsAsciiLetter((char)Fold(unit)) && (at == 0 || !char.IsAsciiLetterOrDigit((char)Fold(text[at - 1]))))
            {
                foreach (string word in s_keywords)
                {
                    if (Starts(text, at, word) && word.Length > (matched?.Length ?? 0)) { matched = word; }
                }
            }
            else
            {
                foreach (string word in s_keywords.Where(word => !char.IsAsciiLetter(word[0])))
                {
                    if (Starts(text, at, word) && word.Length > (matched?.Length ?? 0)) { matched = word; }
                }
            }

            if (matched is null)
            {
                output.Add(Fold(unit), at++);
                continue;
            }

            output.Add(FirstToken + s_keywordIndex[matched], at);
            at += matched.Length;
            if (matched is "REM" or "DATA")
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

    // The statement name table's names, by token: after each entry's rule address, its characters to the one with
    // bit 7 set.
    private static string[] StatementNamesFromTables()
    {
        List<string> names = [];
        int at = 0;
        byte[] tables = AtariBasicSyntax.Tables;
        while (names.Count <= AtariBasicSyntax.ErrorToken)
        {
            at += 2;
            int start = at;
            while ((tables[at++] & NameEnd) == 0) { }
            names.Add(Text(tables.AsSpan(start, at - start), 1).TrimEnd());
        }

        return [.. names];
    }

    // The operator name table's names, by token from $10, to the zero that ends the table; the line's end lists as
    // nothing.
    private static string[] OperatorNamesFromTables()
    {
        List<string> names = [];
        byte[] tables = AtariBasicSyntax.Tables;
        int at = AtariBasicSyntax.OperatorNames - AtariBasicSyntax.TablesStart;
        while (at < tables.Length && tables[at] != 0)
        {
            int start = at;
            while ((tables[at++] & NameEnd) == 0) { }
            names.Add(Text(tables.AsSpan(start, at - start), 0x20));
        }

        return [.. names];
    }

    // A name's characters without their bit 7, leaving out those below a limit.
    private static string Text(ReadOnlySpan<byte> bytes, int lowest)
    {
        Span<char> characters = stackalloc char[bytes.Length];
        int length = 0;
        foreach (byte value in bytes)
        {
            if ((value & 0x7F) >= lowest) { characters[length++] = (char)(value & 0x7F); }
        }

        return new string(characters[..length]);
    }
}
