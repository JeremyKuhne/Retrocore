// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text;

namespace Retrocore.Basic;

/// <summary>
///  Apple Business BASIC, the Apple III's BASIC, as version 1.23 keeps and tokenizes programs.
/// </summary>
/// <remarks>
///  <para>
///   A line is its length (from its length byte to the next line's), its number, its tokens and a zero; a zero
///   length ends the program. Reserved words are one-byte tokens from $80, or $FF and a token from a second list,
///   from $80 again. The tokenizer is the interpreter's <c>CRUNCH</c>: a word is a reserved word only with a
///   separator (anything but a letter, a digit or a period) before and after it, or when it ends in one, so long
///   variable names can hold reserved words. Letters may be either case, spaces outside quotes are dropped, and
///   <c>?</c> is PRINT and <c>!</c> is REM.
///  </para>
///  <para>
///   Programs and variables live in the Apple III's switchable banks, which BASIC reaches through extended
///   addressing: each pointer is two bytes in BASIC's zero page, at <c>$1A00</c>, with an X-byte at <c>$1600</c>
///   beside its high byte. A pointer's page stays from $02 to $81, and BASIC's flat space runs on from page $81 of one
///   bank pair to page $02 of the next. This dialect reads such pointers as flat addresses from <see cref="Banked"/>
///   up, through <see cref="IBasicMemory.ReadFar(byte, int)"/>.
///  </para>
///  <para>
///   Text is tokenized as a program line is. Where BASIC would see a line number's last digit just before a
///   reserved word typed with no space after the number, as in <c>10PRINT</c>, this reads a separator.
///  </para>
/// </remarks>
internal sealed partial class BusinessBasicDialect : BasicDialect
{
    /// <summary>
    ///  Where BASIC's zero page is, while it runs.
    /// </summary>
    internal const int ZeroPage = 0x1A00;

    /// <summary>
    ///  How far a pointer's X-byte is below the pointer itself: the X-byte page, $1600, plus one for the high byte.
    /// </summary>
    internal const int XByteOffset = ZeroPage - 0x1601;

    /// <summary>
    ///  The first flat address of banked memory: below it, addresses are as the CPU maps them now.
    /// </summary>
    internal const int Banked = 0x10000;

    private const byte Escape = 0xFF;
    private const byte Rem = 0xC0;
    private const byte Data = 0xD4;
    private const byte PrintToken = 0xD9;
    private const byte DiskCommands = 0xD3;
    private const byte ImageToken = 0xD5;
    private const byte FnToken = 0x8D;
    private const byte ExfnToken = 0xA2;
    private const byte ExfnIntegerToken = 0xA3;
    private const int CopyBits = 0xC0;

    // The first list's words, tokens $80 to $E0; empty for the placeholders, which no text can match.
    private static readonly string[] s_statements =
    [
        "END", "FOR", "NEXT", "INPUT", "OUTPUT", "DIM", "READ", "WRITE", "OPEN", "CLOSE", "", "TEXT", "", "BYE", "", "",
        "", "", "", "WINDOW", "INVOKE", "PERFORM", "", "", "FRE", "HPOS", "VPOS", "ERRLIN", "ERR", "KBD", "EOF",
        "TIME$", "DATE$", "PREFIX$", "EXFN.", "EXFN%.", "OUTREC", "INDENT", "", "", "", "", "", "", "", "POP", "HOME",
        "", "SUB$(", "OFF", "TRACE", "NOTRACE", "NORMAL", "INVERSE", "SCALE(", "RESUME", "", "LET", "GOTO", "IF",
        "RESTORE", "SWAP", "GOSUB", "RETURN", "REM", "STOP", "ON", "", "LOAD", "SAVE", "DELETE", "RUN", "RENAME", "LOCK",
        "UNLOCK", "CREATE", "EXEC", "CHAIN", "", "", "", "CATALOG", "", "", "DATA", "IMAGE", "CAT", "DEF", "", "PRINT",
        "DEL", "ELSE", "CONT", "LIST", "CLEAR", "GET", "NEW"
    ];

    // The second list's words, tokens $80 to $D3 after $FF.
    private static readonly string[] s_functions =
    [
        "TAB(", "TO", "SPC(", "USING", "THEN", "", "MOD", "STEP", "AND", "OR", "EXTENSION", "DIV", "", "FN", "NOT", "",
        "", "", "", "", "", "", "", "", "", "", "", "", "AS", "SGN(", "INT(", "ABS(", "", "TYP(", "REC(", "", "", "", "",
        "", "", "", "", "", "", "PDL(", "BUTTON(", "SQR(", "RND(", "LOG(", "EXP(", "COS(", "SIN(", "TAN(", "ATN(", "",
        "", "", "", "", "", "", "", "", "", "", "", "STR$(", "HEX$(", "CHR$(", "LEN(", "VAL(", "ASC(", "TEN(", "", "",
        "CONV(", "CONV&(", "CONV$(", "CONV%(", "LEFT$(", "RIGHT$(", "MID$(", "INSTR("
    ];

    private BusinessBasicDialect()
    {
    }

    /// <summary>
    ///  Gets the dialect.
    /// </summary>
    internal static BusinessBasicDialect Instance { get; } = new();

    /// <summary>
    ///  Gets the second list's reserved words, which follow a $FF byte, from token $80.
    /// </summary>
    internal static IReadOnlyList<string> Functions => s_functions;

    /// <inheritdoc/>
    public override string Name => "business";

    /// <inheritdoc/>
    public override string DisplayName => "Business BASIC";

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   The first list, tokens $80 to $E0, with the placeholders empty; <see cref="Functions"/> has the second.
    ///  </para>
    /// </remarks>
    public override IReadOnlyList<string> Keywords => s_statements;

    /// <inheritdoc/>
    public override int MaximumLineNumber => 63999;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   Lines hold lengths rather than links, so a program loads anywhere; this is where BASIC keeps it in its own
    ///   segment when there is one bank above SOS's, which no image depends on.
    ///  </para>
    /// </remarks>
    public override int DefaultLoadAddress => Banked + 0x0201;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   Each is the address of a pointer's low byte in BASIC's zero page; the pointer's X-byte is
    ///   <see cref="XByteOffset"/> below. The program runs from TXTTAB to ARYTAB: Business BASIC keeps its arrays
    ///   before its simple variables, which run from VARTAB to STREND.
    ///  </para>
    /// </remarks>
    public override BasicPointers Pointers { get; } = new()
    {
        ProgramStart = ZeroPage + 0x39,
        Variables = ZeroPage + 0x3B,
        Arrays = ZeroPage + 0x3D,
        FreeStart = ZeroPage + 0x3F,
        StringBottom = ZeroPage + 0x41,
        MemoryTop = ZeroPage + 0x49,
        CurrentLine = ZeroPage + 0x4B,
        ContinueText = ZeroPage + 0x4F,
        DataPointer = ZeroPage + 0x53
    };

    /// <inheritdoc/>
    public override int InputLimit => 255;

    /// <inheritdoc/>
    internal override int LineHeader => 3;

    /// <inheritdoc/>
    internal override int LineOverhead => 4;

    /// <inheritdoc/>
    internal override byte RemToken => Rem;

    /// <inheritdoc/>
    internal override byte DataToken => Data;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   As BASIC's LIST does, a listing has no space after a colon; reserved words get the spaces their separators
    ///   need from <see cref="AppendKeyword"/>.
    ///  </para>
    /// </remarks>
    internal override bool ListingSpaces => false;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   Business BASIC marks direct mode with $FF in the line number's high byte alone.
    ///  </para>
    /// </remarks>
    public override bool InDirectMode(IBasicMemory memory) => memory.Read(Pointers.CurrentLine + 1) == 0xFF;

    /// <summary>
    ///  Gets a flat address from an X-byte and an address, as BASIC's three-byte pointers hold them.
    /// </summary>
    /// <param name="xByte">The X-byte: bit 7 and a bank pair, or 0 for the address as mapped now.</param>
    /// <param name="address">The address.</param>
    /// <returns>The flat address: <see cref="Banked"/> and up for a banked one.</returns>
    internal static int Flat(byte xByte, int address) =>
        (xByte & 0x80) == 0 ? address : Banked + ((xByte & 0x0F) * 0x8000) + address;

    /// <summary>
    ///  Splits a flat address into an X-byte and an address, with the page from $02 to $81, as BASIC keeps it.
    /// </summary>
    /// <param name="flat">The flat address.</param>
    /// <returns>The X-byte, 0 for an address as mapped now, and the address.</returns>
    internal static (byte XByte, int Address) Split(int flat)
    {
        if (flat < Banked) { return (0, flat); }
        int offset = flat - Banked;
        int bank = Math.Max(0, (offset - 0x0200) >> 15);
        return ((byte)(0x80 | bank), offset - (bank * 0x8000));
    }

    /// <summary>
    ///  Reads one of BASIC's three-byte pointers as a flat address.
    /// </summary>
    /// <param name="memory">The memory.</param>
    /// <param name="pointer">The address of the pointer's low byte, in BASIC's zero page.</param>
    /// <returns>The flat address.</returns>
    internal static int Pointer(IBasicMemory memory, int pointer) =>
        Flat(memory.Read(pointer - XByteOffset), BasicProgram.Word(memory, pointer));

    /// <inheritdoc/>
    internal override string AfterLineNumber(string line, int index) => line[index..];

    /// <inheritdoc/>
    internal override bool StartsSearch(byte value) => value is (byte)'!' or >= (byte)'?';

    /// <inheritdoc/>
    internal override void AppendKeyword(StringBuilder builder, string keyword, out bool spaceAfter)
    {
        if (builder.Length > 0 && SpaceBefore(builder[^1])) { builder.Append(' '); }
        builder.Append(keyword);
        spaceAfter = !Separates(keyword[^1]) && keyword is not "REM" and not "DATA" and not "IMAGE" and not "CAT";
    }

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   Takes a second-list token, $FF and its number, and the first list's placeholders, which only an escape
    ///   spells.
    ///  </para>
    /// </remarks>
    internal override bool ExpandSpecial(ReadOnlySpan<byte> line, ref int index, StringBuilder builder, out bool startsRemark)
    {
        startsRemark = false;
        byte value = line[index];
        if (value == Escape && index + 1 < line.Length && Function(line[index + 1]) is { Length: > 0 } function)
        {
            AppendKeyword(builder, function, out bool spaceAfter);
            index++;
            if (spaceAfter && index + 1 < line.Length && SpacesAfterWord(line[index + 1])) { builder.Append(' '); }
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
    ///  Gets the second list's reserved word for a token after $FF.
    /// </summary>
    /// <param name="token">The token.</param>
    /// <returns>The word, empty for a placeholder, or null when the list has no such token.</returns>
    internal static string? Function(byte token) =>
        token >= FirstToken && token - FirstToken < s_functions.Length ? s_functions[token - FirstToken] : null;

    /// <inheritdoc/>
    internal override CrunchOutput Crunch(ReadOnlySpan<int> text)
    {
        CrunchOutput output = new(text.Length + 1);
        int x = 0;

        // DORES: bit 7 copies characters as they are; a colon, or a comma with bit 6 clear, turns tokenizing on.
        int dores = 3;
        while (true)
        {
            int unit = At(text, x);
            if (unit >= BasicText.Raw)
            {
                output.Add(unit, x);
                x++;
                continue;
            }

            if (unit == 0) { break; }
            int character = unit & 0x7F;
            if (character == ':' || (character == ',' && (dores & 0x40) == 0))
            {
                dores = character;
            }

            int stored;
            int at = x;
            bool function = false;
            if ((dores & 0x80) != 0)
            {
                stored = character;
            }
            else if (character < 0x21)
            {
                x++;
                continue;
            }
            else if (character == '!')
            {
                stored = Rem;
            }
            else if (character < '?')
            {
                stored = character;
            }
            else if (character == '?')
            {
                stored = PrintToken;
            }
            else
            {
                stored = Search(text, ref x, out function);
            }

            // STUFIT: a second-list token is $FF and its number, and checks nothing after.
            if (function)
            {
                output.Add(Escape, at);
                output.Add(stored, at);
                stored = 0;
            }
            else
            {
                output.Add(stored, at);
            }

            // NXCHR.
            x++;
            if (stored == Rem)
            {
                CopyLiteral(text, ref x, output, 0);
                break;
            }

            if (stored == '"')
            {
                if (!CopyLiteral(text, ref x, output, '"')) { break; }
                output.Add('"', x);
                x++;
                continue;
            }

            // DATA, IMAGE and CAT copy up to the next colon.
            if (stored is Data or ImageToken or ImageToken + 1)
            {
                dores = CopyBits | (dores >> 2);
            }
        }

        return output;
    }

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   As BASIC's LIST does: before a letter, a digit, a period or another reserved word, which the tokenizer would
    ///   otherwise read as part of the word.
    ///  </para>
    /// </remarks>
    internal override bool SpacesAfterWord(byte next) => next >= FirstToken || !Separates(next);

    // Whether a listing puts a space before a reserved word after this character.
    private static bool SpaceBefore(char previous) => !Separates(previous) || previous is '"' or ')' or '$' or '%' or '&';

    // CKSEP: anything but a letter, a digit or a period separates words.
    private static bool Separates(int character) => !(char.IsAsciiLetterOrDigit((char)character) || character == '.');

    // DOQUOT: copies characters as they are, up to the end character or the line's end, leaving x on the end
    // character. Returns false at the line's end.
    private static bool CopyLiteral(ReadOnlySpan<int> text, ref int x, CrunchOutput output, int endChar)
    {
        while (true)
        {
            int unit = At(text, x);
            if (unit == 0) { return false; }
            if (unit < BasicText.Raw && unit == endChar) { return true; }
            output.Add(unit, x);
            x++;
        }
    }

    // The reserved word search, NPRNT to YMTCH: the first word of either list that the text spells from x, with
    // separators around it. Leaves x on the word's last character and returns its token, or the character itself.
    private static int Search(ReadOnlySpan<int> text, ref int x, out bool function)
    {
        int start = x;
        for (int list = 0; list < 2; list++)
        {
            string[] words = list == 0 ? s_statements : s_functions;
            for (int count = 0; count < words.Length; count++)
            {
                string word = words[count];
                if (word.Length == 0 || !Spells(text, start, word, out int end)) { continue; }
                int token = FirstToken + count;
                int before = start == 0 ? ' ' : At(text, start - 1);
                if (!EndsWord(word, list, token, At(text, end)) || before >= BasicText.Raw || !Separates(before & 0x7F))
                {
                    continue;
                }

                x = end - 1;
                function = list == 1;
                return token;
            }
        }

        function = false;
        return At(text, start) & 0x7F;
    }

    // Whether a matched word ends there: a separator follows it, it ends in one, or it is EXFN., EXFN%. or FN, which a
    // name follows directly.
    private static bool EndsWord(string word, int list, int token, int after)
    {
        if (after < BasicText.Raw && Separates(after & 0x7F)) { return true; }
        if (Separates(word[^1])) { return true; }
        return list == 0 ? token is ExfnToken or ExfnIntegerToken : token == FnToken;
    }

    // Whether the text spells a word from start, either case, spaces inside it skipped; end is one past the last
    // character matched.
    private static bool Spells(ReadOnlySpan<int> text, int start, string word, out int end)
    {
        int at = start;
        for (int index = 0; index < word.Length; index++)
        {
            while (At(text, at) is > 0 and < 0x21) { at++; }
            int unit = At(text, at);
            if (unit >= BasicText.Raw || Fold(unit & 0x7F) != word[index])
            {
                end = at;
                return false;
            }

            at++;
        }

        end = at;
        return true;
    }
}
