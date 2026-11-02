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

    private static readonly BasicDialect[] s_named = [AppleSoftDialect.Enhanced, Level2Dialect.Instance, IntegerBasicDialect.Instance];

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
    ///  Gets the REM token.
    /// </summary>
    internal abstract byte RemToken { get; }

    /// <summary>
    ///  Gets the DATA token.
    /// </summary>
    internal abstract byte DataToken { get; }

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
        return Crunch(BasicText.Parse(text)).ToArray();
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
    ///  Formats a stored line the way the text form writes it: its number, a space and its statements.
    /// </summary>
    /// <param name="line">The line.</param>
    /// <returns>The text.</returns>
    public string FormatLine(BasicLine line) => $"{line.Number} {Detokenize(line.Tokens.Span)}";

    /// <summary>
    ///  Tokenizes text units as the ROM's <c>CRUNCH</c> does.
    /// </summary>
    /// <param name="text">The units, as <see cref="BasicText.Parse(string, List{int})"/> gives them.</param>
    /// <returns>The stored bytes, without the zero that ends the line, with the unit each came from.</returns>
    internal abstract CrunchOutput Crunch(ReadOnlySpan<int> text);

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
