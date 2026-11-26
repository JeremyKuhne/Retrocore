// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text;

namespace Retrocore.Basic;

/// <summary>
///  Level I BASIC, the TRS-80 Model I's first BASIC and the Model III's other ROM: Palo Alto Tiny BASIC with Radio
///  Shack's floating point, as the SDK's <c>Level1.asm</c> gives it.
/// </summary>
/// <remarks>
///  <para>
///   Level I keeps no tokens. A program runs from <c>$4200</c> up to <c>TXTUNF</c> (<c>$406C</c>), each line its
///   number, low byte first, then its text as typed after the number's digits, spaces and all, up to the carriage
///   return that ends it. The keyboard gives only uppercase letters, so <see cref="Tokenize"/> stores a lowercase
///   letter as uppercase. A line is typed in the 70 characters <c>GETLN</c>'s buffer holds, and its number is 1 to
///   32767.
///  </para>
///  <para>
///   Its words are found as the program runs: <c>EXEC</c> looks the text up in a table of the words that may come
///   there, so a word can be cut short with a period, <c>P.</c> for the first word in the table that starts with P
///   (PRINT among the statements, but POINT among the functions). <see cref="Crunch"/> gives the line in the
///   Microsoft form the other dialects' analysis reads, each word it finds as a token from $80 in the order of
///   <see cref="Keywords"/>, looked up as <c>EXEC</c> would in the table for its place. REM and DATA skip the rest
///   of the line, colons and all.
///  </para>
///  <para>
///   Its variables are fixed: A to Z, four bytes each from <c>$4000</c> in its floating point
///   (<see cref="Level1Numbers"/>), the strings A$ and B$, sixteen bytes each at <c>$4070</c> and <c>$4080</c>,
///   and the one array, A(n), whose element n is four bytes at <c>MEMTOP</c> less 4(n+1), counting down toward the
///   program.
///  </para>
/// </remarks>
internal sealed class Level1Dialect : BasicDialect
{
    /// <summary>
    ///  Where the program starts; no pointer holds it.
    /// </summary>
    internal const int ProgramStart = 0x4200;

    /// <summary>
    ///  The carriage return that ends each line.
    /// </summary>
    internal const byte EndOfLine = 0x0D;

    /// <summary>
    ///  The simple variables, A to Z.
    /// </summary>
    internal const int VariablesStart = 0x4000;

    /// <summary>
    ///  The bytes of a number.
    /// </summary>
    internal const int NumberSize = 4;

    /// <summary>
    ///  A$'s 16 bytes; B$'s follow.
    /// </summary>
    internal const int StringA = 0x4070;

    /// <summary>
    ///  The bytes each string has.
    /// </summary>
    internal const int StringSize = 16;

    /// <summary>
    ///  The top of memory (<c>MEMTOP</c>), from which A(n) counts down.
    /// </summary>
    internal const int MemoryTop = 0x406A;

    /// <summary>
    ///  The end of the program text (<c>TXTUNF</c>).
    /// </summary>
    internal const int TextEnd = 0x406C;

    /// <summary>
    ///  The innermost FOR loop's limit (<c>LOPLMT</c>), STEP (<c>LOPINC</c>), line (<c>LOPLN</c>), the text after its
    ///  FOR (<c>LOPPT</c>) and variable (<c>LOPVAR</c>, 0 for none).
    /// </summary>
    internal const int LoopLimit = 0x406E;

    /// <inheritdoc cref="LoopLimit"/>
    internal const int LoopStep = 0x4091;

    /// <inheritdoc cref="LoopLimit"/>
    internal const int LoopLine = 0x4093;

    /// <inheritdoc cref="LoopLimit"/>
    internal const int LoopText = 0x4095;

    /// <inheritdoc cref="LoopLimit"/>
    internal const int LoopVariable = 0x40A5;

    /// <summary>
    ///  A word kept across a call (<c>SCRATCH</c>): while INPUT waits, the stack under which it keeps the line running.
    /// </summary>
    internal const int Scratch = 0x409B;

    /// <summary>
    ///  The address of the line running (<c>CURRNT</c>), 0 in direct mode.
    /// </summary>
    internal const int CurrentLine = 0x409F;

    /// <summary>
    ///  The latest GOSUB's frame on the Z80's stack (<c>STKGOS</c>), 0 for none.
    /// </summary>
    internal const int GosubFrame = 0x40A3;

    // The run state CLEAR_RUN_STATE clears after a line is typed: STOPPT to LOPVAR.
    private const int RunState = 0x409D;
    private const int RunStateSize = 10;
    private const int StopText = 0x409D;
    private const int DataPointer = 0x40A1;

    // The statements a program runs (TABLE1 from NEXT, TABLE1_PROGRAM), in the table's order, which an abbreviation
    // takes the first of; then those typed only as commands. LPRINT and LLIST are the Model III's: one dialect serves
    // both models, so it takes them on the Model I too, where the ROM answers WHAT?.
    private static readonly string[] s_statements =
    [
        "NEXT", "LET", "INPUT", "IF", "ON", "GOTO", "GOSUB", "RESET", "RETURN", "READ", "RESTORE", "REM", "DATA", "FOR",
        "PRINT", "SET", "STOP", "END", "CLS", "LPRINT"
    ];

    private static readonly string[] s_commands = ["LIST", "LLIST", "RUN", "NEW", "CONT", "CLOAD", "CSAVE"];

    // The functions (TABLE3), and the words of one statement each: ON's (TABLE2), FOR's (TABLE4, TABLE5), PRINT's
    // (TABLE6) and IF's (TABLE8).
    private static readonly string[] s_functions = ["RND", "ABS", "MEM", "INT", "POINT"];
    private static readonly string[] s_onWords = ["GOTO", "GOSUB"];
    private static readonly string[] s_forWords = ["TO", "STEP"];
    private static readonly string[] s_printWords = ["TAB", "AT"];
    private static readonly string[] s_ifWords = ["THEN"];

    private static readonly string[] s_keywords =
    [
        .. s_commands, .. s_statements, .. s_ifWords, .. s_forWords, .. s_printWords, .. s_functions
    ];

    private Level1Dialect()
    {
    }

    /// <summary>
    ///  Gets the dialect.
    /// </summary>
    internal static Level1Dialect Instance { get; } = new();

    /// <inheritdoc/>
    public override string Name => "level1";

    /// <inheritdoc/>
    public override string DisplayName => "Level I BASIC";

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   These are the words of <see cref="Crunch"/>'s Microsoft form; Level I stores none of them as tokens.
    ///  </para>
    /// </remarks>
    public override IReadOnlyList<string> Keywords => s_keywords;

    /// <inheritdoc/>
    public override int MaximumLineNumber => 32767;

    /// <inheritdoc/>
    public override int DefaultLoadAddress => ProgramStart;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   Level I has no pointer to its program's start, which is always <c>$4200</c>, nor tables of variables:
    ///   <see cref="BasicPointers.ProgramStart"/> and the variable pointers are <c>TXTUNF</c>, where the program ends,
    ///   and the string pointers <c>MEMTOP</c>. <see cref="BasicPointers.CurrentLine"/> is <c>CURRNT</c>, the address
    ///   of the line running rather than its number.
    ///  </para>
    /// </remarks>
    public override BasicPointers Pointers { get; } = new()
    {
        ProgramStart = TextEnd,
        Variables = TextEnd,
        Arrays = TextEnd,
        FreeStart = TextEnd,
        StringBottom = MemoryTop,
        MemoryTop = MemoryTop,
        CurrentLine = CurrentLine,
        ContinueText = StopText,
        DataPointer = DataPointer
    };

    /// <inheritdoc/>
    public override int InputLimit => 70;

    /// <inheritdoc/>
    internal override int LineHeader => 2;

    /// <inheritdoc/>
    internal override int LineOverhead => 3;

    /// <inheritdoc/>
    internal override bool LinesHoldZero => true;

    /// <inheritdoc/>
    internal override byte RemToken => Token("REM");

    /// <inheritdoc/>
    internal override byte DataToken => Token("DATA");

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   DATA, like REM, goes on to the next line when it runs (<c>ST_REM</c>), so a colon after it starts nothing.
    ///  </para>
    /// </remarks>
    internal override bool IsRemark(byte token) => token == RemToken || token == DataToken;

    /// <inheritdoc/>
    internal override bool ListingSpaces => false;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   The line keeps what is typed after its number's digits, so the text form puts nothing between them.
    ///  </para>
    /// </remarks>
    internal override string LineNumberSeparator => "";

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   These are the line's characters as stored, lowercase letters made uppercase as the keyboard gives them. A
    ///   carriage return would end the line, so it cannot be in one.
    ///  </para>
    /// </remarks>
    public override byte[] Tokenize(string text)
    {
        ArgumentNullException.ThrowIfNull(text);
        int[] units = BasicText.Parse(text, zero: true);
        byte[] stored = new byte[units.Length];
        for (int index = 0; index < units.Length; index++)
        {
            int unit = units[index];
            byte value = unit >= BasicText.Raw ? (byte)unit : (byte)(unit is >= 'a' and <= 'z' ? unit - 0x20 : unit);
            if (value == EndOfLine)
            {
                throw new FormatException($"Column {index + 1}: a carriage return ends a Level I line, so a line cannot hold one.");
            }

            stored[index] = value;
        }

        return stored;
    }

    /// <inheritdoc/>
    public override string Detokenize(ReadOnlySpan<byte> line)
    {
        StringBuilder text = new(line.Length);
        foreach (byte value in line)
        {
            // A lowercase letter would be typed as uppercase, so it is kept as a byte.
            if (value is >= (byte)'a' and <= (byte)'z') { BasicText.AppendEscape(text, value); }
            else { BasicText.AppendCharacter(text, value); }
        }

        return text.ToString();
    }

    /// <inheritdoc/>
    internal override string AfterLineNumber(string line, int index) => line[index..];

    /// <inheritdoc/>
    internal override void AppendKeyword(StringBuilder builder, string keyword, out bool spaceAfter)
    {
        builder.Append(keyword);
        spaceAfter = false;
    }

    /// <inheritdoc/>
    internal override bool StartsSearch(byte value) => false;

    /// <inheritdoc/>
    public override bool InDirectMode(IBasicMemory memory) => LineAddress(memory) == 0;

    /// <summary>
    ///  Gets the address of the line running, 0 in direct mode.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   While INPUT reads from the keyboard, <c>CURRNT</c> holds a stand-in in the ROM, <c>INPUT_KEYBOARD</c>,
    ///   whose bytes read as a negative line number, so that an error in what is typed asks again (<c>INPERR</c>);
    ///   the line running is kept on the stack <c>SCRATCH</c> points at.
    ///  </para>
    ///  <para>
    ///   While READ stores a DATA item, <c>CURRNT</c> is 0 (<c>ST_READ_1</c>), and the line is only on the stack above
    ///   the call's return address, so memory alone reads as direct mode then, and the ROM reports an error in a DATA
    ///   item with no line. The debugger, which has the stack pointer, finds the READ line there.
    ///  </para>
    /// </remarks>
    /// <param name="memory">The memory.</param>
    /// <returns>The line's address.</returns>
    internal static int LineAddress(IBasicMemory memory)
    {
        int line = BasicProgram.Word(memory, CurrentLine);
        return line is 0 or >= ProgramStart ? line : BasicProgram.Word(memory, BasicProgram.Word(memory, Scratch));
    }

    /// <summary>
    ///  Gets the number of the line running, or 0 in direct mode and, as memory alone reads it, while READ stores a
    ///  DATA item (<see cref="LineAddress"/>).
    /// </summary>
    /// <param name="memory">The memory.</param>
    /// <returns>The line number.</returns>
    internal static int CurrentLineNumber(IBasicMemory memory) =>
        LineAddress(memory) is not 0 and var line ? BasicProgram.Word(memory, line) : 0;

    /// <summary>
    ///  Gets whether INPUT has its stand-in in <c>CURRNT</c>, so an error asks for the input again.
    /// </summary>
    /// <param name="memory">The memory.</param>
    /// <returns>Whether INPUT is reading the keyboard.</returns>
    internal static bool InputWaiting(IBasicMemory memory) => BasicProgram.Word(memory, CurrentLine) is not 0 and < ProgramStart;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   The program must end below <c>MEMTOP</c>, as typing a line checks.
    ///  </para>
    /// </remarks>
    internal override int WriteLimit(IBasicMemory memory) => BasicProgram.Word(memory, MemoryTop);

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   From <c>$4200</c> to <c>TXTUNF</c>; nothing when <c>TXTUNF</c> is not between there and <c>MEMTOP</c>, as
    ///   before Level I has started.
    ///  </para>
    /// </remarks>
    internal override (int Start, int End) ProgramBounds(IBasicMemory memory)
    {
        int end = BasicProgram.Word(memory, TextEnd);
        int top = BasicProgram.Word(memory, MemoryTop);
        return end >= ProgramStart && end <= top ? (ProgramStart, end) : (0, 0);
    }

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   As typing a line does (<c>CLEAR_RUN_STATE</c>): CONT's place, the current line, the DATA pointer, the GOSUBs
    ///   and the FOR loop are forgotten. Level I keeps its variables.
    ///  </para>
    /// </remarks>
    internal override void Clear(IBasicMemory memory)
    {
        for (int index = 0; index < RunStateSize; index++) { memory.Write(RunState + index, 0); }
    }

    /// <summary>
    ///  Reads the program from <c>$4200</c> up to <c>TXTUNF</c>.
    /// </summary>
    /// <param name="memory">The memory.</param>
    /// <returns>The program.</returns>
    /// <exception cref="InvalidDataException">BASIC is not set up, or a line has no carriage return.</exception>
    internal BasicProgram Read(IBasicMemory memory)
    {
        (int start, int end) = ProgramBounds(memory);
        if (start == 0)
        {
            throw new InvalidDataException(
                $"Level I BASIC is not set up: its program ends at ${BasicProgram.Word(memory, TextEnd):X4}.");
        }

        byte[] bytes = new byte[end - start];
        for (int index = 0; index < bytes.Length; index++) { bytes[index] = memory.Read(start + index); }
        return FromImage(bytes);
    }

    /// <summary>
    ///  Reads a program as Level I keeps it and CSAVE records it: each line's number, its text and a carriage return.
    /// </summary>
    /// <param name="bytes">The lines.</param>
    /// <returns>The program.</returns>
    /// <exception cref="InvalidDataException">
    ///  A line has no carriage return, or its number is not one typing makes: from 1 to 32767, each above the last.
    ///  Machine code that CLOAD loaded from <c>$4200</c> reads so.
    /// </exception>
    internal BasicProgram FromImage(ReadOnlySpan<byte> bytes)
    {
        List<BasicLine> lines = [];
        int at = 0;
        int previous = 0;
        while (at < bytes.Length)
        {
            int end = at + LineHeader <= bytes.Length ? bytes[(at + LineHeader)..].IndexOf(EndOfLine) : -1;
            if (end < 0)
            {
                throw new InvalidDataException($"The line at offset {at} has no carriage return to end it.");
            }

            int number = bytes[at] | (bytes[at + 1] << 8);
            if (number <= previous || number > MaximumLineNumber)
            {
                throw new InvalidDataException(
                    $"The bytes at offset {at} are not a Level I line: line {number} cannot follow line {previous}.");
            }

            previous = number;
            lines.Add(new(number, bytes.Slice(at + LineHeader, end).ToArray()));
            at += LineHeader + end + 1;
        }

        return new(this, lines);
    }

    /// <summary>
    ///  Tests whether a file's bytes are a program as Level I keeps it rather than a text listing.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   An image holds no zero byte when its line numbers hold none, as from line 1000 up, so it is told by its line
    ///   numbers: below line 8192 a line number's high byte is a control character. Bytes with a control character
    ///   other than a tab, carriage return or line feed, which text holds, are an image; otherwise, they are one when
    ///   they read as lines whose numbers are all below 8192, as a text line's second character, which would be the
    ///   high byte, is not a control character. An image whose lines are all from 8192 up, with no control character
    ///   in them, reads as text.
    ///  </para>
    /// </remarks>
    /// <param name="bytes">The file's bytes.</param>
    /// <returns>Whether they are an image.</returns>
    internal static bool IsImage(ReadOnlySpan<byte> bytes)
    {
        foreach (byte value in bytes)
        {
            if (value is < (byte)' ' and not ((byte)'\t' or (byte)'\r' or (byte)'\n')) { return true; }
        }

        if (bytes.IsEmpty) { return false; }
        for (int at = 0; at < bytes.Length;)
        {
            int end = at + Instance.LineHeader <= bytes.Length ? bytes[(at + Instance.LineHeader)..].IndexOf(EndOfLine) : -1;
            if (end < 0 || bytes[at + 1] >= (byte)' ') { return false; }
            at += Instance.LineHeader + end + 1;
        }

        try
        {
            Instance.FromImage(bytes);
            return true;
        }
        catch (InvalidDataException)
        {
            return false;
        }
    }

    /// <summary>
    ///  Gets a program as Level I keeps it from <c>$4200</c>.
    /// </summary>
    /// <param name="program">The program.</param>
    /// <returns>The bytes.</returns>
    internal static byte[] Image(BasicProgram program)
    {
        List<byte> bytes = [];
        foreach (BasicLine line in program.Lines)
        {
            bytes.Add((byte)line.Number);
            bytes.Add((byte)(line.Number >> 8));
            bytes.AddRange(line.Tokens.Span);
            bytes.Add(EndOfLine);
        }

        return [.. bytes];
    }

    /// <summary>
    ///  Writes a program into memory from <c>$4200</c>, sets <c>TXTUNF</c> and forgets the run state, as typing it
    ///  would.
    /// </summary>
    /// <param name="program">The program.</param>
    /// <param name="memory">The memory.</param>
    /// <exception cref="InvalidOperationException">The program does not fit below <c>MEMTOP</c>.</exception>
    internal void Write(BasicProgram program, IBasicMemory memory)
    {
        byte[] image = Image(program);
        int top = BasicProgram.Word(memory, MemoryTop);
        int end = ProgramStart + image.Length;
        if (top <= ProgramStart || end >= top)
        {
            throw new InvalidOperationException(
                $"SORRY: the program needs {image.Length} bytes from $4200, but memory ends at ${top:X4}.");
        }

        for (int index = 0; index < image.Length; index++) { memory.Write(ProgramStart + index, image[index]); }
        BasicProgram.WriteWord(memory, TextEnd, end);
        Clear(memory);
    }

    /// <summary>
    ///  Gets the offset in a stored line where each of its statements starts: the first, and each after a colon
    ///  outside quotes, up to a REM or DATA.
    /// </summary>
    /// <param name="line">The line's text, without its number and carriage return.</param>
    /// <returns>The offsets.</returns>
    internal static List<int> StatementOffsets(ReadOnlySpan<byte> line)
    {
        List<int> offsets = [0];
        bool quoted = false;
        bool start = true;
        for (int at = 0; at < line.Length; at++)
        {
            byte value = line[at];
            if (quoted)
            {
                quoted = value != '"';
                continue;
            }

            if (value == ' ') { continue; }
            if (start)
            {
                start = false;
                int[] units = [.. line[at..].ToArray().Select(character => (int)character)];
                if (Match(units, 0, s_statements, out _) is "REM" or "DATA") { break; }
            }

            if (value == '"')
            {
                quoted = true;
            }
            else if (value == ':')
            {
                offsets.Add(at + 1);
                start = true;
            }
        }

        return offsets;
    }

    /// <summary>
    ///  Tests whether a place in a stored line is in its READ list, as the place READ keeps on the stack while it stores
    ///  a DATA item.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   The place is in a READ list when the last statement word before it, in its statement and outside quotes, is
    ///   READ: the statement's own, or the one after an IF's condition. A FOR loop's place, after its FOR statement,
    ///   has FOR last, after an IF's condition too. Level I's other words, the functions and FOR's, PRINT's and IF's
    ///   words, are read first and passed over: cut short, as <c>R.</c> for RND or <c>I.</c> for INT, they would read
    ///   as statements, and in full none holds a statement word. Neither READ nor FOR is cut short to one of them.
    ///  </para>
    /// </remarks>
    /// <param name="memory">The memory.</param>
    /// <param name="line">The line's address.</param>
    /// <param name="place">The place in it.</param>
    /// <returns>Whether the place is after READ.</returns>
    internal static bool InReadList(IBasicMemory memory, int line, int place)
    {
        const int MaximumLine = 256;
        int text = line + Instance.LineHeader;
        int end = text;
        while (end - text < MaximumLine && end < 0x10000 && memory.Read(end) != EndOfLine) { end++; }
        if (place <= text || place > end) { return false; }
        int[] units = new int[end - text];
        for (int index = 0; index < units.Length; index++) { units[index] = memory.Read(text + index); }
        int before = place - text;
        byte[] bytes = [.. units.Select(unit => (byte)unit)];
        string? last = null;
        bool quoted = false;
        for (int x = StatementOffsets(bytes).Last(offset => offset < before); x < before; x++)
        {
            if (quoted)
            {
                quoted = units[x] != '"';
            }
            else if (units[x] == '"')
            {
                quoted = true;
            }
            else if (OtherWord(units, x, out int past))
            {
                x = past - 1;
            }
            else if (Match(units, x, s_statements, out int after) is { } word)
            {
                last = word;
                x = after - 1;
            }
        }

        return last == "READ";
    }

    // Whether a function or one statement's word (FOR's TO and STEP, PRINT's TAB and AT, IF's THEN) is at a place,
    // in full or cut short, and where it ends.
    private static bool OtherWord(ReadOnlySpan<int> text, int x, out int end)
    {
        foreach (string[] table in (string[][])[s_functions, s_forWords, s_printWords, s_ifWords])
        {
            if (Match(text, x, table, out end) is not null) { return true; }
        }

        end = x;
        return false;
    }

    /// <summary>
    ///  Gets the statement word a statement starts with, as <c>EXEC</c> finds it, or null for an implied LET.
    /// </summary>
    /// <param name="memory">The memory.</param>
    /// <param name="address">The statement's first byte.</param>
    /// <returns>The word.</returns>
    internal static string? StatementWord(IBasicMemory memory, int address)
    {
        int[] units = new int[16];
        int at = address;
        while (memory.Read(at & 0xFFFF) == ' ' && at < address + 64) { at++; }
        for (int index = 0; index < units.Length; index++) { units[index] = memory.Read((at + index) & 0xFFFF); }
        return Match(units, 0, s_statements, out _);
    }

    /// <inheritdoc/>
    internal override CrunchOutput Crunch(ReadOnlySpan<int> text)
    {
        CrunchOutput output = new(text.Length);
        int x = 0;
        bool start = true;
        string? statement = null;
        while (x < text.Length)
        {
            int unit = text[x];
            if (unit >= BasicText.Raw)
            {
                output.Add(unit, x++);
                start = false;
                continue;
            }

            if (unit == ' ')
            {
                output.Add(unit, x++);
                continue;
            }

            if (unit == '"')
            {
                // QTSTG prints to the closing quote, or the end of the line.
                output.Add(unit, x++);
                while (x < text.Length && text[x] != '"') { output.Add(text[x], x++); }
                if (x < text.Length) { output.Add('"', x++); }
                start = false;
                continue;
            }

            if (unit == ':')
            {
                output.Add(unit, x++);
                start = true;
                statement = null;
                continue;
            }

            if (start)
            {
                start = false;
                if (Match(text, x, s_statements, out int end) is { } word)
                {
                    output.Add(Token(word), x);
                    x = end;
                    statement = word;
                    if (word is "REM" or "DATA") { break; }
                    continue;
                }
            }

            int folded = Fold(unit);
            if (folded is >= 'A' and <= 'Z' && ContextWord(text, x, statement, out int after) is { } inner)
            {
                output.Add(Token(inner), x);
                x = after;

                // THEN is followed by a line number, which is a GOTO, or a statement; IF's condition can be followed
                // by a statement without THEN, whose own words are looked up after it.
                if (inner == "THEN") { start = true; }
                else if (statement == "IF" && s_statements.Contains(inner)) { statement = inner; }
                if (statement is "REM" or "DATA") { break; }
                continue;
            }

            output.Add(folded, x++);
        }

        // REM and DATA skip the rest of the line, which is kept as it is.
        while (x < text.Length) { output.Add(text[x], x++); }
        return output;
    }

    // The word at x that may come inside a statement: its own words, then a function, then, after IF's condition,
    // any statement. A function but MEM is followed by its parenthesis.
    private static string? ContextWord(ReadOnlySpan<int> text, int x, string? statement, out int end)
    {
        string[] own = statement switch
        {
            "IF" => s_ifWords,
            "FOR" => s_forWords,
            "PRINT" or "LPRINT" => s_printWords,
            "ON" => s_onWords,
            _ => []
        };

        if (Match(text, x, own, out end) is { } word) { return word; }
        if (Match(text, x, s_functions, out end) is { } function)
        {
            int at = end;
            while (at < text.Length && text[at] == ' ') { at++; }
            if (function == "MEM" || (at < text.Length && text[at] == '(')) { return function; }
        }

        if (statement == "IF" && Match(text, x, s_statements, out end) is { } next) { return next; }
        end = x;
        return null;
    }

    // EXEC: the word at x from a table, whole or cut short with a period; null when none, as for the table's default.
    private static string? Match(ReadOnlySpan<int> text, int x, string[] table, out int end)
    {
        foreach (string word in table)
        {
            int at = x;
            int index = 0;
            while (index < word.Length && Unit(text, at) == word[index])
            {
                at++;
                index++;
            }

            if (index == word.Length)
            {
                end = at;
                return word;
            }

            if (index > 0 && Unit(text, at) == '.')
            {
                end = at + 1;
                return word;
            }
        }

        end = x;
        return null;
    }

    private static int Unit(ReadOnlySpan<int> text, int at) => at < text.Length && text[at] < BasicText.Raw ? Fold(text[at]) : -1;

    private static byte Token(string word) => (byte)(FirstToken + Array.IndexOf(s_keywords, word));
}
