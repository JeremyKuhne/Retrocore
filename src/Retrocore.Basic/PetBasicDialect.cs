// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text;

namespace Retrocore.Basic;

/// <summary>
///  Commodore BASIC for the PET and the VIC-20: BASIC 1, the 2001's first ROMs; BASIC 2, the 2001-N's and the upgrade
///  ROMs, and the VIC-20's; and BASIC 4, the 4000 series', with its disk commands. All derive from Microsoft's 6502 BASIC and use the shared
///  native interpreter or the corresponding <c>m6502.asm</c> MACRO-10 overlay.
/// </summary>
/// <remarks>
///  <para>
///   The tokenizer is the ROM's <c>CRUNCH</c>. Spaces are kept as typed; reserved words are found anywhere, so
///   <c>SCORE</c> is <c>SC</c>, <c>OR</c>, <c>E</c>; <c>?</c> is <c>PRINT</c>; and DATA, REM and strings are stored as
///   typed. BASIC 1 skips spaces inside reserved words, so <c>GO TO</c> is <c>GOTO</c> and <c>S TO P</c> is
///   <c>STOP</c>; BASIC 2 does not, and has <c>GO</c> as a word of its own, so <c>GO TO</c> is <c>GO</c>, a space and
///   <c>TO</c>. BASIC 4 tokenizes as BASIC 2 does, with fifteen disk commands after <c>GO</c>, from <c>CONCAT</c>
///   (<c>$CC</c>) to <c>DIRECTORY</c> (<c>$DA</c>); its <c>DS</c> and <c>DS$</c> are variables, not words.
///  </para>
///  <para>
///   The text is PETSCII. The keyboard types unshifted letters as uppercase ASCII, which is all <c>CRUNCH</c> takes
///   as reserved words, so lowercase letters outside strings, DATA and REM become uppercase; inside them they are
///   stored as typed. Cursor and screen codes, reverse video, graphics characters and pi (<c>$FF</c>) are written as
///   escapes, such as <c>{$93}</c> for clear screen.
///  </para>
///  <para>
///   Programs start at <c>$0401</c> on the PET; on the VIC-20 where its RAM puts them, <c>$1001</c> unexpanded, and
///   its page-zero pointers are three bytes above BASIC 2's. Variables are laid out as AppleSoft's are: two name
///   characters whose high bits give the type, and five-byte floats, two-byte integers high byte first, and three-byte
///   string descriptors.
///  </para>
/// </remarks>
internal sealed class PetBasicDialect : BasicDialect
{
    private const byte PrintToken = 0x99;

    // BASIC 2's words: BASIC 1's and GO.
    private const int Basic2Words = 76;

    // The reserved words in token order from $80: BASIC 1's, then GO, which BASIC 2 adds, then BASIC 4's disk
    // commands.
    private static readonly string[] s_keywords =
    [
        "END", "FOR", "NEXT", "DATA", "INPUT#", "INPUT", "DIM", "READ", "LET", "GOTO", "RUN", "IF", "RESTORE", "GOSUB",
        "RETURN", "REM", "STOP", "ON", "WAIT", "LOAD", "SAVE", "VERIFY", "DEF", "POKE", "PRINT#", "PRINT", "CONT",
        "LIST", "CLR", "CMD", "SYS", "OPEN", "CLOSE", "GET", "NEW", "TAB(", "TO", "FN", "SPC(", "THEN", "NOT", "STEP",
        "+", "-", "*", "/", "^", "AND", "OR", ">", "=", "<", "SGN", "INT", "ABS", "USR", "FRE", "POS", "SQR", "RND",
        "LOG", "EXP", "COS", "SIN", "TAN", "ATN", "PEEK", "LEN", "STR$", "VAL", "ASC", "CHR$", "LEFT$", "RIGHT$",
        "MID$", "GO", "CONCAT", "DOPEN", "DCLOSE", "RECORD", "HEADER", "COLLECT", "BACKUP", "COPY", "APPEND", "DSAVE",
        "DLOAD", "CATALOG", "RENAME", "SCRATCH", "DIRECTORY"
    ];

    // BASIC 1 keeps its input buffer, BUF, in page zero ahead of its pointers.
    private static readonly BasicPointers s_basic1Pointers = new()
    {
        ProgramStart = 0x7A,
        Variables = 0x7C,
        Arrays = 0x7E,
        FreeStart = 0x80,
        StringBottom = 0x82,
        MemoryTop = 0x86,
        CurrentLine = 0x88,
        ContinueText = 0x8C,
        DataPointer = 0x90
    };

    // BASIC 2 and 4 keep BUF at $0200.
    private static readonly BasicPointers s_basic2Pointers = new()
    {
        ProgramStart = 0x28,
        Variables = 0x2A,
        Arrays = 0x2C,
        FreeStart = 0x2E,
        StringBottom = 0x30,
        MemoryTop = 0x34,
        CurrentLine = 0x36,
        ContinueText = 0x3A,
        DataPointer = 0x3E
    };

    // The VIC-20's BASIC 2 keeps the same pointers three bytes higher, after its kernal's page zero.
    private static readonly BasicPointers s_vic20Pointers = new()
    {
        ProgramStart = 0x2B,
        Variables = 0x2D,
        Arrays = 0x2F,
        FreeStart = 0x31,
        StringBottom = 0x33,
        MemoryTop = 0x37,
        CurrentLine = 0x39,
        ContinueText = 0x3D,
        DataPointer = 0x41
    };

    private readonly string[] _keywords;
    private readonly bool _spacesInWords;

    private PetBasicDialect(int version, bool vic20 = false)
    {
        IsVic20 = vic20;
        Version = version;
        _spacesInWords = version == 1;
        _keywords = version switch
        {
            1 => s_keywords[..(Basic2Words - 1)],
            2 => s_keywords[..Basic2Words],
            _ => s_keywords
        };

        DisplayName = vic20 ? "Commodore BASIC 2 (VIC-20)" : $"Commodore BASIC {version} (PET)";
        Pointers = vic20 ? s_vic20Pointers : version == 1 ? s_basic1Pointers : s_basic2Pointers;
    }

    /// <summary>
    ///  Gets BASIC 1, the PET 2001's first ROMs.
    /// </summary>
    internal static PetBasicDialect Basic1 { get; } = new(version: 1);

    /// <summary>
    ///  Gets BASIC 2, the 2001-N's ROMs and the 2001's upgrade.
    /// </summary>
    internal static PetBasicDialect Basic2 { get; } = new(version: 2);

    /// <summary>
    ///  Gets BASIC 4, the 4000 series' ROMs.
    /// </summary>
    internal static PetBasicDialect Basic4 { get; } = new(version: 4);

    /// <summary>
    ///  Gets the VIC-20's BASIC 2, whose words and tokens are the PET's BASIC 2's, its page zero moved.
    /// </summary>
    internal static PetBasicDialect Vic20 { get; } = new(version: 2, vic20: true);

    /// <summary>
    ///  Gets whether this is the VIC-20's BASIC rather than a PET's.
    /// </summary>
    internal bool IsVic20 { get; }

    /// <summary>
    ///  Gets the version: 1, 2 or 4.
    /// </summary>
    internal int Version { get; }

    /// <summary>
    ///  Gets whether each string in string space ends with two link bytes, as BASIC 4's garbage collector needs: a
    ///  pointer back to its descriptor, or for garbage its length and 255.
    /// </summary>
    internal bool LinksStrings => Version == 4;

    /// <summary>
    ///  Gets whether a name is one the ROM answers itself rather than from the variable table: <c>ST</c>, the I/O
    ///  status, and <c>TI</c> and <c>TI$</c>, the jiffy clock, and on BASIC 4 <c>DS</c> and <c>DS$</c>, the disk
    ///  status. BASIC keeps a name's first two letters, so <c>STATUS</c> is <c>ST</c>.
    /// </summary>
    /// <param name="name">The name, with its type suffix.</param>
    /// <returns>Whether it is reserved.</returns>
    internal bool IsReservedVariable(string name)
    {
        bool text = name.EndsWith('$');
        string letters = name.TrimEnd('$', '%').ToUpperInvariant();
        if (name.EndsWith('%') || letters.Length < 2) { return false; }
        return letters[..2] switch
        {
            "ST" => !text,
            "TI" => true,
            "DS" => Version == 4,
            _ => false
        };
    }

    /// <summary>
    ///  The address of BASIC 4's <c>DSDESC</c>, the disk status string <c>DS$</c>'s descriptor: its length, then where
    ///  it is.
    /// </summary>
    internal const int DiskStatusDescriptor = 0x0D;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   BASIC 4's <c>CLEARC</c> also forgets the disk status, whose string was in the space it frees.
    ///  </para>
    /// </remarks>
    internal override void Clear(IBasicMemory memory)
    {
        base.Clear(memory);
        if (LinksStrings) { memory.Write(DiskStatusDescriptor, 0); }
    }

    /// <inheritdoc/>
    public override string Name => "petbasic";

    /// <inheritdoc/>
    public override string DisplayName { get; }

    /// <inheritdoc/>
    public override IReadOnlyList<string> Keywords => _keywords;

    /// <inheritdoc/>
    public override int MaximumLineNumber => 63999;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   BASIC's RAM starts at <c>$0400</c>, whose zero comes before the first line. On the VIC-20 the unexpanded
    ///   machine's starts at <c>$1000</c>; its BASIC reads where from <c>TXTTAB</c>, which the RAM decides.
    ///  </para>
    /// </remarks>
    public override int DefaultLoadAddress => IsVic20 ? 0x1001 : 0x0401;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   BASIC 1 keeps its input buffer in page zero, so its pointers are higher there than BASIC 2's and 4's; the
    ///   VIC-20's are three bytes above BASIC 2's.
    ///  </para>
    /// </remarks>
    public override BasicPointers Pointers { get; }

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   The screen editor's logical line: two rows of 40 columns, or on the VIC-20 four rows of 22.
    ///  </para>
    /// </remarks>
    public override int InputLimit => IsVic20 ? 88 : 80;

    /// <inheritdoc/>
    internal override byte RemToken => 0x8F;

    /// <inheritdoc/>
    internal override byte DataToken => 0x83;

    /// <inheritdoc/>
    internal override bool ListingSpaces => false;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   BASIC marks direct mode with <c>$FF</c> in the line number's high byte alone.
    ///  </para>
    /// </remarks>
    public override bool InDirectMode(IBasicMemory memory) => memory.Read(Pointers.CurrentLine + 1) == 0xFF;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   The line number is read with <c>CHRGET</c>, which skips the spaces after it.
    ///  </para>
    /// </remarks>
    internal override string AfterLineNumber(string line, int index) => line[index..].TrimStart(' ');

    /// <inheritdoc/>
    internal override bool StartsSearch(byte value) => value is not (byte)' ' and not (byte)'"' and (< (byte)'0' or >= (byte)'<');

    /// <inheritdoc/>
    internal override void AppendKeyword(StringBuilder builder, string keyword, out bool spaceAfter)
    {
        builder.Append(keyword);
        spaceAfter = false;
    }

    /// <inheritdoc/>
    internal override CrunchOutput Crunch(ReadOnlySpan<int> text)
    {
        CrunchOutput output = new(text.Length + 1);
        int x = 0;
        bool data = false;
        while (true)
        {
            int unit = At(text, x);
            if (unit >= BasicText.Raw)
            {
                output.Add(unit, x);
                x++;
                continue;
            }

            // The zero that ends the line is not part of its statements.
            if (unit == 0) { break; }

            // KLOOP: spaces are stored; lowercase is made uppercase except in DATA.
            int character = data ? unit : FoldLetter(unit);
            int stored;
            int at = x;
            if (character == ' ')
            {
                stored = character;
            }
            else if (character == '"')
            {
                // STRNG: copy up to the closing quote, which STUFFH stores.
                output.Add(character, x);
                x++;
                if (!CopyLiteral(text, ref x, output, '"')) { break; }
                stored = '"';
                at = x;
            }
            else if (data)
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
                CopyLiteral(text, ref x, output, endChar: 0);
                break;
            }
        }

        return output;
    }

    // Only the letters a-z become uppercase; the other characters from $60 up are PETSCII graphics.
    private static int FoldLetter(int unit) => unit is >= 'a' and <= 'z' ? unit & 0x5F : unit;

    // STR1: copies typed characters unchanged up to the end character, leaving x on it. Returns false at the end of
    // the line.
    private static bool CopyLiteral(ReadOnlySpan<int> text, ref int x, CrunchOutput output, int endChar)
    {
        while (true)
        {
            int unit = At(text, x);
            if (unit == 0) { return false; }
            if (unit == endChar) { return true; }
            output.Add(unit, x);
            x++;
        }
    }

    // MUSTCR: the reserved word search, each word in token order; the first the text starts with. Leaves x on the last
    // character used and returns the byte to store.
    private int Search(ReadOnlySpan<int> text, ref int x)
    {
        int start = x;
        for (int count = 0; count < _keywords.Length; count++)
        {
            string keyword = _keywords[count];
            int at = start;
            bool matched = true;
            for (int index = 0; index < keyword.Length; index++)
            {
                if (index > 0) { at++; }

                // RESCON: BASIC 1 skips spaces inside a reserved word.
                while (_spacesInWords && At(text, at) == ' ') { at++; }
                int unit = At(text, at);
                if (unit >= BasicText.Raw || FoldLetter(unit) != keyword[index])
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

        // Not a reserved word: the character itself.
        x = start;
        return FoldLetter(At(text, start));
    }
}
