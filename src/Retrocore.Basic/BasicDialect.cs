// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text;

namespace Retrocore.Basic;

/// <summary>
///  A BASIC interpreter's program format: its reserved words and tokens, how it tokenizes a typed line, and where it
///  keeps the program in memory.
/// </summary>
/// <remarks>
///  <para>
///   Each dialect's tokenizer follows its ROM's <c>CRUNCH</c> step by step, quirks included, so text tokenizes to
///   the bytes the machine would store had the line been typed. <see cref="Detokenize(ReadOnlySpan{byte})"/> always
///   gives text that tokenizes back to the same bytes.
///  </para>
/// </remarks>
public abstract partial class BasicDialect
{
    /// <summary>
    ///  The first token.
    /// </summary>
    internal const int FirstToken = 0x80;

    private static readonly BasicDialect[] s_named =
    [
        AppleSoftDialect.Enhanced,
        Level2Dialect.Instance,
        IntegerBasicDialect.Instance,
        IntegerBasicDialect.Apple1Basic,
        BusinessBasicDialect.Instance,
        ColorBasicDialect.Disk,
        MbasicDialect.Instance,
        PetBasicDialect.Basic4,
        BbcBasicDialect.Instance,
        AtariBasicDialect.Instance
    ];

    /// <summary>
    ///  Gets AppleSoft as the Enhanced IIe's ROM tokenizes it: lowercase outside strings, DATA and REM becomes
    ///  uppercase.
    /// </summary>
    public static BasicDialect AppleSoft => AppleSoftDialect.Enhanced;

    /// <summary>
    ///  Gets AppleSoft as the original IIe's ROM tokenizes it, which leaves lowercase as typed.
    /// </summary>
    public static BasicDialect AppleSoftOriginal => AppleSoftDialect.Original;

    /// <summary>
    ///  Gets the TRS-80 Model I's Level II BASIC.
    /// </summary>
    public static BasicDialect Level2 => Level2Dialect.Instance;

    /// <summary>
    ///  Gets the Apple II's Integer BASIC.
    /// </summary>
    public static BasicDialect Integer => IntegerBasicDialect.Instance;

    /// <summary>
    ///  Gets Apple Business BASIC 1.23, the Apple III's.
    /// </summary>
    public static BasicDialect BusinessBasic => BusinessBasicDialect.Instance;

    /// <summary>
    ///  Gets BBC BASIC II, the BBC Micro's.
    /// </summary>
    public static BasicDialect BbcBasic => BbcBasicDialect.Instance;

    /// <summary>
    ///  Gets Apple-1 BASIC, the first form of Integer BASIC.
    /// </summary>
    public static BasicDialect Apple1 => IntegerBasicDialect.Apple1Basic;

    /// <summary>
    ///  Gets the TRS-80 Color Computer's BASIC with every word its ROMs add: Color, Extended and Disk Extended Color
    ///  BASIC 1.1.
    /// </summary>
    public static BasicDialect ColorBasic => ColorBasicDialect.Disk;

    /// <summary>
    ///  Gets MBASIC, Microsoft's BASIC-80 5.21 for CP/M.
    /// </summary>
    public static BasicDialect Mbasic => MbasicDialect.Instance;

    /// <summary>
    ///  Gets Atari BASIC, as rev. C tokenizes it.
    /// </summary>
    public static BasicDialect AtariBasic => AtariBasicDialect.Instance;

    /// <summary>
    ///  Gets the Color Computer's BASIC as the ROMs fitted know it, which crunch only their own words.
    /// </summary>
    /// <param name="extended">Whether Extended Color BASIC is fitted.</param>
    /// <param name="disk">Disk Extended Color BASIC's version, 10 or 11, or 0 for none.</param>
    /// <returns>The dialect.</returns>
    public static BasicDialect ColorBasicWith(bool extended, int disk) => (extended, disk) switch
    {
        (false, _) => ColorBasicDialect.Color,
        (true, 0) => ColorBasicDialect.Extended,
        (true, 10) => ColorBasicDialect.Disk10,
        _ => ColorBasicDialect.Disk
    };

    /// <summary>
    ///  Gets the Commodore PET's BASIC 2, the 2001-N's and the upgrade ROMs'.
    /// </summary>
    public static BasicDialect PetBasic => PetBasicDialect.Basic2;

    /// <summary>
    ///  Gets the PET 2001's first BASIC, BASIC 1, which skips spaces inside reserved words and has no <c>GO</c>.
    /// </summary>
    public static BasicDialect PetBasic1 => PetBasicDialect.Basic1;

    /// <summary>
    ///  Gets the PET 4000 series' BASIC 4, which adds the disk commands; <c>petbasic</c> names it, since it has every
    ///  word of the others.
    /// </summary>
    public static BasicDialect PetBasic4 => PetBasicDialect.Basic4;

    /// <summary>
    ///  Gets the PET's BASIC by its version.
    /// </summary>
    /// <param name="version">1 for the PET 2001's first ROMs, 4 for the 4000 series', else BASIC 2.</param>
    /// <returns>The dialect.</returns>
    public static BasicDialect PetBasicVersion(int version) => version switch
    {
        1 => PetBasicDialect.Basic1,
        4 => PetBasicDialect.Basic4,
        _ => PetBasicDialect.Basic2
    };

    /// <summary>
    ///  Gets the name pragmas, extensions and settings use, such as <c>applesoft</c>.
    /// </summary>
    public abstract string Name { get; }

    /// <summary>
    ///  Gets the name to show, such as <c>AppleSoft</c>.
    /// </summary>
    public abstract string DisplayName { get; }

    /// <summary>
    ///  Gets the reserved words in token order: the first is token $80.
    /// </summary>
    public abstract IReadOnlyList<string> Keywords { get; }

    /// <summary>
    ///  Gets the functions that are stored as <see cref="FunctionPrefix"/> and a token, in token order from $80; none
    ///  in a dialect whose functions are one byte, among its <see cref="Keywords"/>.
    /// </summary>
    public virtual IReadOnlyList<string> Functions => [];

    /// <summary>
    ///  Gets every reserved word: the <see cref="Keywords"/>, then the <see cref="Functions"/>.
    /// </summary>
    public IEnumerable<string> AllKeywords => Keywords.Concat(Functions);

    /// <summary>
    ///  Gets whether the machine keeps words high byte first, as the 6809 does, rather than low byte first.
    /// </summary>
    public virtual bool BigEndian => false;

    /// <summary>
    ///  Gets the highest line number the interpreter accepts.
    /// </summary>
    public abstract int MaximumLineNumber { get; }

    /// <summary>
    ///  Gets where the interpreter normally puts a program's first line.
    /// </summary>
    public abstract int DefaultLoadAddress { get; }

    /// <summary>
    ///  Gets where the interpreter keeps its pointers.
    /// </summary>
    public abstract BasicPointers Pointers { get; }

    /// <summary>
    ///  Gets the most characters the interpreter lets you type in one line.
    /// </summary>
    public abstract int InputLimit { get; }

    /// <summary>
    ///  Gets the bytes before a line's tokens in memory: the Microsoft BASICs' link and number.
    /// </summary>
    internal virtual int LineHeader => 4;

    /// <summary>
    ///  Gets the bytes of a line in memory besides its tokens: its header and the byte that ends it.
    /// </summary>
    internal virtual int LineOverhead => 5;

    /// <summary>
    ///  Gets whether a line can hold a zero byte, as one ended by its length and a carriage return can; a line a zero
    ///  ends cannot.
    /// </summary>
    internal virtual bool LinesHoldZero => false;

    /// <summary>
    ///  Gets the REM token.
    /// </summary>
    internal abstract byte RemToken { get; }

    /// <summary>
    ///  Gets the DATA token.
    /// </summary>
    internal abstract byte DataToken { get; }

    /// <summary>
    ///  Tests whether a token starts a remark that runs to the line's end: REM, and in Color BASIC the apostrophe.
    /// </summary>
    /// <param name="token">The token.</param>
    /// <returns>Whether it starts a remark.</returns>
    internal virtual bool IsRemark(byte token) => token == RemToken;

    /// <summary>
    ///  Gets the byte before a <see cref="Functions"/> token, or -1 when the dialect has none.
    /// </summary>
    internal virtual int FunctionPrefix => -1;

    /// <summary>
    ///  Gets the token that marks a FOR entry on BASIC's stack.
    /// </summary>
    internal virtual int StackForToken => FirstToken + Keywords.ToList().IndexOf("FOR");

    /// <summary>
    ///  Gets the token that marks a GOSUB entry on BASIC's stack.
    /// </summary>
    internal virtual int StackGosubToken => FirstToken + Keywords.ToList().IndexOf("GOSUB");

    /// <summary>
    ///  Finds a dialect by its <see cref="Name"/>.
    /// </summary>
    /// <param name="name">The name, in any case.</param>
    /// <returns>The dialect, or null when there is none of that name.</returns>
    public static BasicDialect? FromName(string? name) =>
        s_named.FirstOrDefault(dialect => string.Equals(dialect.Name, name, StringComparison.OrdinalIgnoreCase));

    /// <summary>
    ///  Gets the reserved word a token stands for.
    /// </summary>
    /// <param name="token">The token.</param>
    /// <returns>The word, or null when the byte is not one of this dialect's tokens.</returns>
    public string? Keyword(byte token) => token >= FirstToken && token - FirstToken < Keywords.Count ? Keywords[token - FirstToken] : null;

    /// <summary>
    ///  Gets the reserved word a whole token stands for: a byte, or a <see cref="Functions"/> token as the prefix in
    ///  the high byte and the token in the low.
    /// </summary>
    /// <param name="token">The token.</param>
    /// <returns>The word, or null when it is not one of this dialect's tokens.</returns>
    public string? Word(int token)
    {
        if (token <= 0xFF) { return Keyword((byte)token); }
        int function = (token & 0xFF) - FirstToken;
        return token >> 8 == FunctionPrefix && function >= 0 && function < Functions.Count ? Functions[function] : null;
    }

    /// <summary>
    ///  Reads the reserved word at a place in a crunched line, one byte or a function's two.
    /// </summary>
    /// <param name="line">The crunched line.</param>
    /// <param name="index">Where the token starts.</param>
    /// <param name="length">The token's length in bytes: 2 for a function's, else 1.</param>
    /// <returns>The word, or null when the byte starts none.</returns>
    public string? KeywordAt(ReadOnlySpan<byte> line, int index, out int length)
    {
        length = 1;
        if (line[index] == FunctionPrefix && index + 1 < line.Length)
        {
            length = 2;
            return Word((line[index] << 8) | line[index + 1]);
        }

        return Keyword(line[index]);
    }

    /// <summary>
    ///  Tokenizes a line's statements as the interpreter would when they are typed after a line number.
    /// </summary>
    /// <param name="text">The text after the line number, in the text form.</param>
    /// <returns>The stored bytes, without the zero that ends the line.</returns>
    /// <exception cref="FormatException">
    ///  The text has a character that cannot be typed, or a bad escape; or, for a dialect that checks its syntax as it
    ///  tokenizes, a <see cref="BasicSyntaxException"/> saying where the line is wrong.
    /// </exception>
    public virtual byte[] Tokenize(string text)
    {
        ArgumentNullException.ThrowIfNull(text);
        return Crunch(BasicText.Parse(text, zero: LinesHoldZero)).ToArray();
    }

    /// <summary>
    ///  Gives a line's statements as text that tokenizes back to the same bytes.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   The text reads as a listing would. Bytes that typing could not have produced are written as escapes, as
    ///   few as it takes for the line to tokenize back exactly.
    ///  </para>
    /// </remarks>
    /// <param name="line">The stored bytes, without the zero that ends the line.</param>
    /// <returns>The text.</returns>
    public virtual string Detokenize(ReadOnlySpan<byte> line)
    {
        foreach (BasicExpansion expansion in (ReadOnlySpan<BasicExpansion>)[BasicExpansion.Listing, BasicExpansion.EscapeLiterals])
        {
            string text = Expand(line, expansion);
            if (RoundTrips(line, text)) { return text; }
        }

        StringBuilder raw = new();
        foreach (byte value in line) { BasicText.AppendEscape(raw, value); }
        return raw.ToString();
    }

    /// <summary>
    ///  Splits a typed line into its line number and the text the tokenizer sees.
    /// </summary>
    /// <param name="line">The line, starting with its number after any spaces.</param>
    /// <param name="number">The line number, or -1 when the line does not start with one.</param>
    /// <returns>The text after the number.</returns>
    public string SplitLineNumber(string line, out int number)
    {
        ArgumentNullException.ThrowIfNull(line);
        int index = 0;
        while (index < line.Length && line[index] == ' ') { index++; }
        int start = index;
        long value = 0;
        while (index < line.Length && char.IsAsciiDigit(line[index]))
        {
            value = Math.Min(value * 10 + (line[index] - '0'), int.MaxValue);
            index++;
        }

        number = index == start ? -1 : (int)value;
        return AfterLineNumber(line, index);
    }

    /// <summary>
    ///  Formats a stored line the way the text form writes it: its number, a space and its statements; in BBC BASIC,
    ///  which keeps the spaces after the number, its number and its text.
    /// </summary>
    /// <param name="line">The line.</param>
    /// <returns>The text.</returns>
    public string FormatLine(BasicLine line) => $"{line.Number}{LineNumberSeparator}{Detokenize(line.Tokens.Span)}";

    /// <summary>
    ///  Gets what the text form puts between a line's number and its statements: a space, or nothing in a dialect
    ///  that keeps the spaces typed after the number in the line.
    /// </summary>
    internal virtual string LineNumberSeparator => " ";

    /// <summary>
    ///  Tokenizes text units as the ROM's <c>CRUNCH</c> does.
    /// </summary>
    /// <param name="text">The units, as <see cref="BasicText.Parse(string, List{int}, bool)"/> gives them.</param>
    /// <returns>The stored bytes, without the zero that ends the line, with the unit each came from.</returns>
    internal abstract CrunchOutput Crunch(ReadOnlySpan<int> text);

    /// <summary>
    ///  Finds the zero that ends a line's tokens, which a dialect that stores numbers in binary does not take from
    ///  inside a number.
    /// </summary>
    /// <param name="tokens">The bytes from the line's first token.</param>
    /// <returns>The zero's index, or -1 for none.</returns>
    internal virtual int TerminatorIn(ReadOnlySpan<byte> tokens) => tokens.IndexOf((byte)0);

    /// <summary>
    ///  Turns a line's tokens as the interpreter keeps them in memory back into those CRUNCH made, such as line
    ///  pointers back into line numbers.
    /// </summary>
    /// <param name="tokens">The tokens.</param>
    /// <param name="memory">The machine's memory.</param>
    /// <returns>The tokens CRUNCH made.</returns>
    internal virtual byte[] FromMemory(byte[] tokens, IBasicMemory memory) => tokens;

    /// <summary>
    ///  Gets whether the interpreter rewrites lines in memory as it runs (<see cref="FromMemory"/> changes them), so
    ///  that the program's identity must come from the lines read back rather than the bytes.
    /// </summary>
    internal virtual bool RewritesLines => false;

    /// <summary>
    ///  Gets the text the tokenizer sees after the line number's digits.
    /// </summary>
    /// <param name="line">The typed line.</param>
    /// <param name="index">Where the digits end.</param>
    /// <returns>The text.</returns>
    internal abstract string AfterLineNumber(string line, int index);

    /// <summary>
    ///  Writes a reserved word into the text being built.
    /// </summary>
    /// <param name="builder">The text.</param>
    /// <param name="keyword">The word.</param>
    /// <param name="spaceAfter">Set when a space should separate the word from what follows.</param>
    internal abstract void AppendKeyword(StringBuilder builder, string keyword, out bool spaceAfter);

    /// <summary>
    ///  Expands the dialect's special token sequences, such as Level II's <c>:ELSE</c>, at a position.
    /// </summary>
    /// <param name="line">The stored line.</param>
    /// <param name="index">The position; on return, the last byte used.</param>
    /// <param name="builder">The text.</param>
    /// <param name="startsRemark">Set when what follows is remark text.</param>
    /// <returns>Whether the position held a special sequence.</returns>
    internal virtual bool ExpandSpecial(ReadOnlySpan<byte> line, ref int index, StringBuilder builder, out bool startsRemark)
    {
        startsRemark = false;
        return false;
    }

    /// <summary>
    ///  Tests whether a literal character outside strings would start a reserved word search when typed, so it must
    ///  be escaped to be stored as itself.
    /// </summary>
    /// <param name="value">The character.</param>
    /// <returns>Whether it is searched.</returns>
    internal abstract bool StartsSearch(byte value);

    /// <summary>
    ///  Folds a character to uppercase as the ROM's case folding does: any character from <c>a</c> up.
    /// </summary>
    /// <param name="value">The character.</param>
    /// <returns>The folded character.</returns>
    internal static int Fold(int value) => value is >= 'a' and < BasicText.Raw ? value & 0x5F : value;

    /// <summary>
    ///  Gets a text unit, or zero past the end, as the input buffer's terminating zero.
    /// </summary>
    /// <param name="text">The units.</param>
    /// <param name="index">The position.</param>
    /// <returns>The unit.</returns>
    internal static int At(ReadOnlySpan<int> text, int index) => index < text.Length ? text[index] : 0;

    private bool RoundTrips(ReadOnlySpan<byte> line, string text)
    {
        try
        {
            return Tokenize(text).AsSpan().SequenceEqual(line);
        }
        catch (FormatException)
        {
            return false;
        }
    }
}
