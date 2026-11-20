// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text;

namespace Retrocore.Basic;

/// <summary>
///  BBC BASIC II, the BBC Micro's BASIC, as it keeps and tokenises programs.
/// </summary>
/// <remarks>
///  <para>
///   BBC BASIC is not a Microsoft BASIC. A program starts at PAGE with a carriage return; each line is its number, high
///   byte first, its length (from the number to the carriage return that ends it, inclusive) and its text; a line
///   whose number's high byte has bit 7 set, &amp;FF, ends the program, and TOP is the byte after it. Lines keep the
///   spaces they were typed with, so a listing is the stored text. A line number after GOTO, GOSUB, RESTORE, THEN,
///   ELSE and the like is &amp;8D and three bytes that hold its bits, so RENUMBER can find it.
///  </para>
///  <para>
///   The tokeniser is BASIC's <c>TOKENISE_LINE</c>: only capitals start a keyword, a keyword may be abbreviated with
///   a full stop, and each keyword's flags say whether a name may follow it, whether a statement or line numbers
///   follow, and whether the rest of the line is left as text (REM and DATA). PTR, PAGE, TIME, LOMEM and HIMEM have a second
///   token, &amp;40 higher, at the start of a statement.
///  </para>
/// </remarks>
internal sealed partial class BbcBasicDialect : BasicDialect
{
    /// <summary>
    ///  The token before a line number's three bytes.
    /// </summary>
    internal const byte LineNumberToken = 0x8D;

    /// <summary>
    ///  The carriage return that starts the program and ends each line.
    /// </summary>
    internal const byte CarriageReturn = 0x0D;

    private const byte Rem = 0xF4;
    private const byte Data = 0xDC;
    private const byte Else = 0x8B;
    private const byte Then = 0x8C;

    // The keyword flags, as the ROM's KEYWORD_ constants.
    private const int Conditional = 0x01;
    private const int MidStatement = 0x02;
    private const int StartStatement = 0x04;
    private const int NameFollows = 0x08;
    private const int LineNumbers = 0x10;
    private const int RestOfLine = 0x20;
    private const int PseudoVariable = 0x40;

    // The keyword table in the ROM's order, which the tokeniser searches up to WIDTH: each word, its token and flags.
    private static readonly (string Word, byte Token, int Flags)[] s_table =
    [
        ("AND", 0x80, 0), ("ABS", 0x94, 0), ("ACS", 0x95, 0), ("ADVAL", 0x96, 0), ("ASC", 0x97, 0), ("ASN", 0x98, 0),
        ("ATN", 0x99, 0), ("AUTO", 0xC6, LineNumbers), ("BGET", 0x9A, Conditional),
        ("BPUT", 0xD5, Conditional | MidStatement), ("COLOUR", 0xFB, MidStatement), ("CALL", 0xD6, MidStatement),
        ("CHAIN", 0xD7, MidStatement), ("CHR$", 0xBD, 0), ("CLEAR", 0xD8, Conditional),
        ("CLOSE", 0xD9, Conditional | MidStatement), ("CLG", 0xDA, Conditional), ("CLS", 0xDB, Conditional),
        ("COS", 0x9B, 0), ("COUNT", 0x9C, Conditional), ("DATA", Data, RestOfLine), ("DEG", 0x9D, 0), ("DEF", 0xDD, 0),
        ("DELETE", 0xC7, LineNumbers), ("DIV", 0x81, 0), ("DIM", 0xDE, MidStatement), ("DRAW", 0xDF, MidStatement),
        ("ENDPROC", 0xE1, Conditional), ("END", 0xE0, Conditional), ("ENVELOPE", 0xE2, MidStatement),
        ("ELSE", Else, StartStatement | LineNumbers), ("EVAL", 0xA0, 0), ("ERL", 0x9E, Conditional),
        ("ERROR", 0x85, StartStatement), ("EOF", 0xC5, Conditional), ("EOR", 0x82, 0), ("ERR", 0x9F, Conditional),
        ("EXP", 0xA1, 0), ("EXT", 0xA2, Conditional), ("FOR", 0xE3, MidStatement), ("FALSE", 0xA3, Conditional),
        ("FN", 0xA4, NameFollows), ("GOTO", 0xE5, MidStatement | LineNumbers), ("GET$", 0xBE, 0), ("GET", 0xA5, 0),
        ("GOSUB", 0xE4, MidStatement | LineNumbers), ("GCOL", 0xE6, MidStatement),
        ("HIMEM", 0x93, Conditional | MidStatement | PseudoVariable), ("INPUT", 0xE8, MidStatement),
        ("IF", 0xE7, MidStatement), ("INKEY$", 0xBF, 0), ("INKEY", 0xA6, 0), ("INT", 0xA8, 0), ("INSTR(", 0xA7, 0),
        ("LIST", 0xC9, LineNumbers), ("LINE", 0x86, 0), ("LOAD", 0xC8, MidStatement),
        ("LOMEM", 0x92, Conditional | MidStatement | PseudoVariable), ("LOCAL", 0xEA, MidStatement),
        ("LEFT$(", 0xC0, 0), ("LEN", 0xA9, 0), ("LET", 0xE9, StartStatement), ("LOG", 0xAB, 0), ("LN", 0xAA, 0),
        ("MID$(", 0xC1, 0), ("MODE", 0xEB, MidStatement), ("MOD", 0x83, 0), ("MOVE", 0xEC, MidStatement),
        ("NEXT", 0xED, MidStatement), ("NEW", 0xCA, Conditional), ("NOT", 0xAC, 0), ("OLD", 0xCB, Conditional),
        ("ON", 0xEE, MidStatement), ("OFF", 0x87, 0), ("OR", 0x84, 0), ("OPENIN", 0x8E, 0), ("OPENOUT", 0xAE, 0),
        ("OPENUP", 0xAD, 0), ("OSCLI", 0xFF, MidStatement), ("PRINT", 0xF1, MidStatement),
        ("PAGE", 0x90, Conditional | MidStatement | PseudoVariable),
        ("PTR", 0x8F, Conditional | MidStatement | PseudoVariable), ("PI", 0xAF, Conditional),
        ("PLOT", 0xF0, MidStatement), ("POINT(", 0xB0, 0), ("PROC", 0xF2, MidStatement | NameFollows),
        ("POS", 0xB1, Conditional), ("RETURN", 0xF8, Conditional), ("REPEAT", 0xF5, 0), ("REPORT", 0xF6, Conditional),
        ("READ", 0xF3, MidStatement), ("REM", Rem, RestOfLine), ("RUN", 0xF9, Conditional), ("RAD", 0xB2, 0),
        ("RESTORE", 0xF7, MidStatement | LineNumbers), ("RIGHT$(", 0xC2, 0), ("RND", 0xB3, Conditional),
        ("RENUMBER", 0xCC, LineNumbers), ("STEP", 0x88, 0), ("SAVE", 0xCD, MidStatement), ("SGN", 0xB4, 0),
        ("SIN", 0xB5, 0), ("SQR", 0xB6, 0), ("SPC", 0x89, 0), ("STR$", 0xC3, 0), ("STRING$(", 0xC4, 0),
        ("SOUND", 0xD4, MidStatement), ("STOP", 0xFA, Conditional), ("TAN", 0xB7, 0),
        ("THEN", Then, StartStatement | LineNumbers), ("TO", 0xB8, 0), ("TAB(", 0x8A, 0),
        ("TRACE", 0xFC, MidStatement | LineNumbers), ("TIME", 0x91, Conditional | MidStatement | PseudoVariable),
        ("TRUE", 0xB9, Conditional), ("UNTIL", 0xFD, MidStatement), ("USR", 0xBA, 0), ("VDU", 0xEF, MidStatement),
        ("VAL", 0xBB, 0), ("VPOS", 0xBC, Conditional), ("WIDTH", 0xFE, MidStatement)
    ];

    // The words by token from &80, the line number token's and &CE's empty; the pseudo-variables' statement tokens,
    // &CF-&D3, spell them as their function tokens do.
    private static readonly string[] s_keywords = Words();

    private BbcBasicDialect()
    {
    }

    /// <summary>
    ///  Gets the keyword table as the ROM searches it: each word, its token and its flags.
    /// </summary>
    internal static IReadOnlyList<(string Word, byte Token, int Flags)> Table => s_table;

    /// <summary>
    ///  Gets the dialect.
    /// </summary>
    internal static BbcBasicDialect Instance { get; } = new();

    /// <inheritdoc/>
    public override string Name => "bbcbasic";

    /// <inheritdoc/>
    public override string DisplayName => "BBC BASIC";

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   Tokens &amp;80 to &amp;FF; the line number token, &amp;8D, and the unused &amp;CE are empty.
    ///  </para>
    /// </remarks>
    public override IReadOnlyList<string> Keywords => s_keywords;

    /// <inheritdoc/>
    public override bool BigEndian => false;

    /// <inheritdoc/>
    public override int MaximumLineNumber => 32767;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   PAGE with the DFS, &amp;1900. Lines hold lengths rather than links, so a program loads at any PAGE.
    ///  </para>
    /// </remarks>
    public override int DefaultLoadAddress => 0x1900;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   BBC BASIC's zero page: PAGE is a byte, the high byte at &amp;18, and the program runs from there to TOP
    ///   (&amp;12). The variables are on the heap from LOMEM (&amp;00) to its top (&amp;02); BASIC's stack grows down
    ///   from HIMEM (&amp;06), and its pointer is at &amp;04. BASIC keeps no current line: it is the line PTRA
    ///   (&amp;0B) is in, which <see cref="InDirectMode"/> reads. DATA's pointer is at &amp;1C.
    ///  </para>
    /// </remarks>
    public override BasicPointers Pointers { get; } = new()
    {
        ProgramStart = PageHigh,
        Variables = Lomem,
        Arrays = Lomem,
        FreeStart = Heap,
        StringBottom = BasicStack,
        MemoryTop = Himem,
        CurrentLine = PtrA,
        ContinueText = PtrA,
        DataPointer = DataPointerAddress
    };

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   OSWORD 0 reads at most 238 characters into the line buffer.
    ///  </para>
    /// </remarks>
    public override int InputLimit => 238;

    /// <inheritdoc/>
    internal override int LineHeader => 3;

    /// <inheritdoc/>
    internal override int LineOverhead => 4;

    /// <inheritdoc/>
    internal override bool LinesHoldZero => true;

    /// <inheritdoc/>
    internal override byte RemToken => Rem;

    /// <inheritdoc/>
    internal override byte DataToken => Data;

    /// <inheritdoc/>
    internal override bool ListingSpaces => false;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   DATA too: the rest of the line after it is its items, colons and all, as BASIC skips it.
    ///  </para>
    /// </remarks>
    internal override bool IsRemark(byte token) => token is Rem or Data;

    /// <inheritdoc/>
    internal override int StackForToken => -1;

    /// <inheritdoc/>
    internal override int StackGosubToken => -1;

    /// <summary>
    ///  Tests whether a statement starts after a word, as the tokeniser decides where a <c>*</c> command can begin.
    /// </summary>
    /// <param name="word">The word.</param>
    /// <param name="before">Whether one started before it.</param>
    /// <returns>
    ///  True after a word that starts a statement, such as THEN or ERROR; false after one that is in the middle of one,
    ///  such as PRINT; and as before for any other, such as REPEAT.
    /// </returns>
    internal static bool StatementStartsAfter(string word, bool before)
    {
        foreach ((string entry, _, int flags) in s_table)
        {
            if (entry != word) { continue; }
            if ((flags & StartStatement) != 0) { return true; }
            return (flags & MidStatement) == 0 && before;
        }

        return false;
    }

    /// <summary>
    ///  Tests whether a byte can be part of a name: a capital, a digit, <c>_</c>, <c>£</c> (&amp;60) or a small
    ///  letter, as the ROM's <c>IS_NAME_CHARACTER</c> has it.
    /// </summary>
    /// <param name="value">The byte.</param>
    /// <returns>Whether it can.</returns>
    internal static bool IsNameCharacter(int value) =>
        value is (>= 'A' and <= 'Z') or (>= '0' and <= '9') or (>= '_' and <= 'z');

    /// <summary>
    ///  Packs a line number into the three bytes that follow <see cref="LineNumberToken"/>.
    /// </summary>
    /// <param name="number">The line number, 0-32767.</param>
    /// <returns>The three bytes.</returns>
    internal static (byte First, byte Second, byte Third) PackLineNumber(int number)
    {
        int low = number & 0xFF;
        int high = (number >> 8) & 0xFF;
        byte first = (byte)((((low & 0xC0) | ((high & 0xC0) >> 2)) >> 2) ^ 0x54);
        return (first, (byte)((low & 0x3F) | 0x40), (byte)((high & 0x3F) | 0x40));
    }

    /// <summary>
    ///  Unpacks the line number in the three bytes after <see cref="LineNumberToken"/>, as the ROM's
    ///  <c>UNPACK_LINE_NUMBER</c> does.
    /// </summary>
    /// <param name="first">The first byte.</param>
    /// <param name="second">The second.</param>
    /// <param name="third">The third.</param>
    /// <returns>The line number.</returns>
    internal static int UnpackLineNumber(byte first, byte second, byte third)
    {
        int shifted = (first << 2) & 0xFF;
        int low = (shifted & 0xC0) ^ second;
        int high = ((shifted << 2) & 0xFF) ^ third;
        return (low | (high << 8)) & 0xFFFF;
    }

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   BBC BASIC keeps the spaces after a line's number as part of its text.
    ///  </para>
    /// </remarks>
    internal override string AfterLineNumber(string line, int index) => line[index..];

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   Nothing: the line keeps the spaces typed after its number, so <c>10 PRINT</c> lists as it was typed.
    ///  </para>
    /// </remarks>
    internal override string LineNumberSeparator => "";

    /// <inheritdoc/>
    internal override bool StartsSearch(byte value) =>
        value is (>= (byte)'A' and <= (byte)'W') or (>= (byte)'0' and <= (byte)'9');

    /// <inheritdoc/>
    internal override void AppendKeyword(StringBuilder builder, string keyword, out bool spaceAfter)
    {
        builder.Append(keyword);
        spaceAfter = false;
    }

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   Takes a line number, &amp;8D and three bytes, as its digits; REM and DATA, after which the rest of the line is
    ///   text; and the tokens no word has, which only an escape spells.
    ///  </para>
    /// </remarks>
    internal override bool ExpandSpecial(ReadOnlySpan<byte> line, ref int index, StringBuilder builder, out bool startsRemark)
    {
        startsRemark = false;
        byte value = line[index];
        if (value == LineNumberToken && index + 3 < line.Length)
        {
            builder.Append(UnpackLineNumber(line[index + 1], line[index + 2], line[index + 3]));
            index += 3;
            return true;
        }

        if (value is Rem or Data)
        {
            builder.Append(Keyword(value));
            startsRemark = true;
            return true;
        }

        if (value >= FirstToken && Keyword(value) is not { Length: > 0 })
        {
            BasicText.AppendEscape(builder, value);
            return true;
        }

        return false;
    }

    /// <summary>
    ///  Tokenises an expression, as the tokeniser does in the middle of a statement: numbers are numbers, not lines.
    /// </summary>
    /// <param name="text">The expression, in the text form.</param>
    /// <returns>The bytes.</returns>
    /// <exception cref="FormatException">The text has a character that cannot be typed, or a bad escape.</exception>
    internal static byte[] TokenizeExpression(string text) =>
        Crunch(BasicText.Parse(text, zero: true), middle: true, lineNumbers: false).ToArray();

    /// <inheritdoc/>
    internal override CrunchOutput Crunch(ReadOnlySpan<int> text) => Crunch(text, middle: false, lineNumbers: true);

    // Tokenises from a state: after a typed line number, the start of a statement, with line numbers on.
    private static CrunchOutput Crunch(ReadOnlySpan<int> text, bool middle, bool lineNumbers)
    {
        CrunchOutput output = new(text.Length + 4);
        int x = 0;
        while (x < text.Length)
        {
            int unit = text[x];
            if (unit >= BasicText.Raw)
            {
                output.Add(unit, x);
                x++;
                middle = true;
                lineNumbers = false;
                continue;
            }

            if (unit == CarriageReturn) { break; }
            switch (unit)
            {
                case ' ' or ',':
                    output.Add(unit, x++);
                    continue;
                case '&':
                    output.Add(unit, x++);
                    while (At(text, x) is int hex and ((>= '0' and <= '9') or (>= 'A' and <= 'F')))
                    {
                        output.Add(hex, x++);
                    }

                    continue;
                case '"':
                    output.Add(unit, x++);
                    while (true)
                    {
                        int character = At(text, x);
                        if (character == 0 || character == CarriageReturn)
                        {
                            CopyRest(text, x, output);
                            return output;
                        }

                        output.Add(character, x++);
                        if (character == '"') { break; }
                    }

                    continue;
                case ':':
                    output.Add(unit, x++);
                    middle = false;
                    lineNumbers = false;
                    continue;
                case '*' when !middle:
                    // A * command: the rest of the line is for OSCLI.
                    CopyRest(text, x, output);
                    return output;
                case '.':
                    x = SkipNumber(text, x, output);
                    middle = true;
                    lineNumbers = false;
                    continue;
            }

            if (unit is >= '0' and <= '9')
            {
                if (lineNumbers && LineNumber(text, x, output) is int next)
                {
                    x = next;
                    continue;
                }

                x = SkipNumber(text, x, output);
                middle = true;
                lineNumbers = false;
                continue;
            }

            if (unit < 'A' || (unit >= 'X' && !IsNameCharacter(unit)))
            {
                output.Add(unit, x++);
                middle = true;
                lineNumbers = false;
                continue;
            }

            if (unit >= 'X' || Search(text, x) is not { } found)
            {
                x = SkipName(text, x, output);
                middle = true;
                lineNumbers = false;
                continue;
            }

            (int index, int length) = found;
            (string _, byte token, int flags) = s_table[index];
            if ((flags & Conditional) != 0 && IsNameCharacter(At(text, x + length)))
            {
                x = SkipName(text, x, output);
                middle = true;
                lineNumbers = false;
                continue;
            }

            if ((flags & PseudoVariable) != 0 && !middle) { token += 0x40; }
            output.Add(token, x);
            x += length;
            if ((flags & MidStatement) != 0)
            {
                middle = true;
                lineNumbers = false;
            }

            if ((flags & StartStatement) != 0)
            {
                middle = false;
                lineNumbers = false;
            }

            if ((flags & NameFollows) != 0)
            {
                while (At(text, x) is int name && name < BasicText.Raw && IsNameCharacter(name))
                {
                    output.Add(name, x++);
                }
            }

            if ((flags & LineNumbers) != 0) { lineNumbers = true; }
            if ((flags & RestOfLine) != 0)
            {
                CopyRest(text, x, output);
                return output;
            }
        }

        return output;
    }

    // The keyword the text spells from x, as TOKENISE_WORD searches: the first entry, in the table's order up to WIDTH,
    // whose letters all match, or whose first letters match and then a full stop. Returns its index in the table and
    // the length of the text it takes, or null for a name.
    private static (int Index, int Length)? Search(ReadOnlySpan<int> text, int x)
    {
        int first = text[x];
        for (int index = 0; index < s_table.Length; index++)
        {
            string word = s_table[index].Word;
            if (first < word[0]) { return null; }
            if (first == word[0])
            {
                int at = 1;
                while (true)
                {
                    if (at == word.Length) { return (index, at); }
                    int character = At(text, x + at);
                    if (character == word[at])
                    {
                        at++;
                        continue;
                    }

                    if (character == '.') { return (index, at + 1); }
                    break;
                }
            }

            if (s_table[index].Token == 0xFE) { return null; }
        }

        return null;
    }

    // A line number while line numbers are on, as TOKENISE_LINE_NUMBER: the digits become the token and three bytes,
    // unless the number is 32768 or more. Returns where the digits end, or null to leave them as they are.
    private static int? LineNumber(ReadOnlySpan<int> text, int x, CrunchOutput output)
    {
        int at = x;
        int value = 0;
        while (At(text, at) is int digit and >= '0' and <= '9')
        {
            value = (value * 10) + (digit - '0');
            if (value > 0x7FFF) { return null; }
            at++;
        }

        (byte first, byte second, byte third) = PackLineNumber(value);
        output.Add(LineNumberToken, x);
        output.Add(first, x);
        output.Add(second, x);
        output.Add(third, x);
        return at;
    }

    // Digits and points, copied as they are.
    private static int SkipNumber(ReadOnlySpan<int> text, int x, CrunchOutput output)
    {
        while (At(text, x) is int character and ((>= '0' and <= '9') or '.')) { output.Add(character, x++); }
        return x;
    }

    // A name, copied as it is so that no keyword is found inside it.
    private static int SkipName(ReadOnlySpan<int> text, int x, CrunchOutput output)
    {
        while (At(text, x) is int character && character < BasicText.Raw && IsNameCharacter(character))
        {
            output.Add(character, x++);
        }

        return x;
    }

    // The rest of the line, copied as it is.
    private static void CopyRest(ReadOnlySpan<int> text, int x, CrunchOutput output)
    {
        output.StartRest();
        for (; x < text.Length; x++) { output.Add(text[x], x); }
    }

    private static string[] Words()
    {
        string[] words = new string[0x80];
        Array.Fill(words, "");
        foreach ((string word, byte token, _) in s_table) { words[token - FirstToken] = word; }
        foreach (string word in (string[])["PTR", "PAGE", "TIME", "LOMEM", "HIMEM"])
        {
            int token = s_table.First(entry => entry.Word == word).Token;
            words[token + 0x40 - FirstToken] = word;
        }

        return words;
    }
}
