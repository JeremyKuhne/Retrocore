// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text;

namespace Retrocore.Basic;

/// <summary>
///  The TRS-80 Model 100's BASIC, Microsoft's BASIC in the Model 100's and Tandy 102's ROM.
/// </summary>
/// <remarks>
///  <para>
///   The keywords are the ROM's table at <c>$0080</c>, one token each from <c>$80</c> (<c>END</c>) to <c>$FF</c>
///   (<c>'</c>); numbers and line numbers stay as their digits. The tokenizer stores lines as the ROM does when they
///   are typed, checked against the Model 100's ROM: spaces are kept as typed, and only <c>GOTO</c> may have spaces
///   inside it; lowercase letters become uppercase, except in strings, DATA and remarks; <c>?</c> is <c>PRINT</c>;
///   <c>ELSE</c> is stored with a colon before it, and an apostrophe remark as a colon, <c>REM</c> and the apostrophe
///   token; and one space after the line number is dropped.
///  </para>
///  <para>
///   A program is a file in RAM: the <c>.BA</c> file BASIC has open, or its unsaved program, with the other files
///   after it. Writing one moves the files after it, as the ROM does when a line is typed (see
///   <see cref="Model100Files"/>).
///  </para>
/// </remarks>
internal sealed class Model100Dialect : BasicDialect
{
    private const int StackTop = 0xF678;
    private const int RunningName = 0xFDD9;
    private const int RunningNameLength = 9;
    private const byte GotoToken = 0x88;
    private const byte ElseToken = 0x91;
    private const byte PrintToken = 0xA3;
    private const byte ApostropheToken = 0xFF;

    private static readonly string[] s_keywords =
    [
        "END", "FOR", "NEXT", "DATA", "INPUT", "DIM", "READ", "LET", "GOTO", "RUN", "IF", "RESTORE", "GOSUB", "RETURN",
        "REM", "STOP", "WIDTH", "ELSE", "LINE", "EDIT", "ERROR", "RESUME", "OUT", "ON", "DSKO$", "OPEN", "CLOSE",
        "LOAD", "MERGE", "FILES", "SAVE", "LFILES", "LPRINT", "DEF", "POKE", "PRINT", "CONT", "LIST", "LLIST", "CLEAR",
        "CLOAD", "CSAVE", "TIME$", "DATE$", "DAY$", "COM", "MDM", "KEY", "CLS", "BEEP", "SOUND", "LCOPY", "PSET",
        "PRESET", "MOTOR", "MAX", "POWER", "CALL", "MENU", "IPL", "NAME", "KILL", "SCREEN", "NEW", "TAB(", "TO",
        "USING", "VARPTR", "ERL", "ERR", "STRING$", "INSTR", "DSKI$", "INKEY$", "CSRLIN", "OFF", "HIMEM", "THEN", "NOT",
        "STEP", "+", "-", "*", "/", "^", "AND", "OR", "XOR", "EQV", "IMP", "MOD", "\\", ">", "=", "<", "SGN", "INT",
        "ABS", "FRE", "INP", "LPOS", "POS", "SQR", "RND", "LOG", "EXP", "COS", "SIN", "TAN", "ATN", "PEEK", "EOF", "LOC",
        "LOF", "CINT", "CSNG", "CDBL", "FIX", "LEN", "STR$", "VAL", "ASC", "CHR$", "SPACE$", "LEFT$", "RIGHT$", "MID$",
        "'"
    ];

    private Model100Dialect()
    {
    }

    /// <summary>
    ///  Gets the dialect.
    /// </summary>
    internal static Model100Dialect Instance { get; } = new();

    /// <inheritdoc/>
    public override string Name => "model100";

    /// <inheritdoc/>
    public override string DisplayName => "Model 100 BASIC";

    /// <inheritdoc/>
    public override IReadOnlyList<string> Keywords => s_keywords;

    /// <inheritdoc/>
    public override int MaximumLineNumber => 65529;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   The first file's address in a 32 KB machine. A smaller machine's file area starts higher; the ROM links a
    ///   <c>.BA</c> file again where it goes, as Retrocore does when it writes one.
    ///  </para>
    /// </remarks>
    public override int DefaultLoadAddress => Model100Files.FileArea + 1;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   The program pointer is the open file's (<c>$F67C</c>), and the variables start past every file in RAM
    ///   (<c>$FBB2</c>), so a program's own end is its zero link.
    ///  </para>
    /// </remarks>
    public override BasicPointers Pointers { get; } = new()
    {
        ProgramStart = 0xF67C,
        Variables = 0xFBB2,
        Arrays = 0xFBB4,
        FreeStart = 0xFBB6,
        StringBottom = 0xFB8C,
        MemoryTop = 0xFB67,
        CurrentLine = 0xF67A,
        ContinueText = 0xFBAC,
        DataPointer = 0xFBB8,
        StackTop = StackTop
    };

    /// <inheritdoc/>
    public override int InputLimit => 255;

    /// <inheritdoc/>
    internal override byte RemToken => 0x8E;

    /// <inheritdoc/>
    internal override byte DataToken => 0x83;

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
    ///   The program ends at its zero link, as other files follow it; a program pointer at no .BA file or unsaved
    ///   program, or at one whose lines do not end, gives no bounds.
    ///  </para>
    /// </remarks>
    internal override (int Start, int End) ProgramBounds(IBasicMemory memory)
    {
        int start = BasicProgram.Word(memory, Pointers.ProgramStart);
        if (!new Model100Files(memory).HoldsProgram(start)) { return (0, 0); }
        try
        {
            return (start, Model100Files.BasicEnd(memory, start));
        }
        catch (InvalidDataException)
        {
            return (0, 0);
        }
    }

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   The current line is $FFFF at the menu and in the ROM's other programs too, so BASIC is at its prompt only
    ///   when it is also the program running: the name at <c>$FDD9</c> is BASIC's, or the <c>.BA</c> file it has
    ///   open, where TEXT and TELCOM put theirs, ADDRSS <c>ADRS.DO</c>, and the menu a zero.
    ///  </para>
    /// </remarks>
    public override bool InDirectMode(IBasicMemory memory) => base.InDirectMode(memory) && InBasic(memory);

    /// <summary>
    ///  Writes a program over the one BASIC has open, moving the files after it, and clears the variables.
    /// </summary>
    /// <param name="program">The program.</param>
    /// <param name="memory">The memory.</param>
    /// <exception cref="InvalidOperationException">
    ///  The program does not fit, or BASIC's program pointer is not at a program.
    /// </exception>
    /// <exception cref="InvalidDataException">The program in RAM has a line with no end.</exception>
    internal void Write(BasicProgram program, IBasicMemory memory)
    {
        int start = BasicProgram.Word(memory, Pointers.ProgramStart);
        Model100Files files = new(memory);
        if (!files.HoldsProgram(start))
        {
            throw new InvalidOperationException(
                $"BASIC's program pointer, ${start:X4}, is not at a .BA file or BASIC's unsaved program; enter BASIC from the menu first.");
        }

        files.Replace(start, Model100Files.BasicEnd(memory, start) - start, program.ToImage(start));
        Clear(memory);
    }

    // Whether BASIC is the program running, by the name the ROM keeps for it.
    private static bool InBasic(IBasicMemory memory)
    {
        Span<char> name = stackalloc char[RunningNameLength];
        int length = 0;
        while (length < RunningNameLength && memory.Read(RunningName + length) is var value and not 0)
        {
            name[length++] = (char)value;
        }

        ReadOnlySpan<char> running = name[..length];
        return running.SequenceEqual("BASIC") || running.EndsWith(".BA", StringComparison.Ordinal);
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
                // Copy the string; the closing quote is stored as any other character.
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

    // Copies typed characters unchanged up to the end character, leaving x on it. Returns false at the end of the line.
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

    // The reserved word search, in token order. Leaves x on the last character used and returns the byte to store.
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
                // GOTO may have spaces, tabs and line feeds between its letters.
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
