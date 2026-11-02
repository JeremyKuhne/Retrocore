// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Buffers;
using System.Globalization;
using System.Runtime.InteropServices;

namespace Retrocore.Assembler;

/// <summary>
///  Allocation-free native syntax matching shared by the runtime and source generator.
/// </summary>
/// <remarks>
///  <para>
///   References may be root- or scope-qualified and segments may start with @. Definitions stay
///   unqualified; exports and generated C# names use the plain identifier grammar.
///  </para>
/// </remarks>
internal static class AssemblySyntax
{
    private const int StackBufferSize = 256;

    /// <summary>
    ///  Matches a native identifier, retaining the existing Unicode word-character rules.
    /// </summary>
    /// <param name="text">The identifier.</param>
    /// <returns>Whether the entire span is an identifier.</returns>
    internal static bool IsIdentifier(ReadOnlySpan<char> text) =>
        text.Length != 0 && IdentifierLength(text) == text.Length;

    /// <summary>
    ///  Matches an unqualified ordinary identifier suitable for an export or metadata name.
    /// </summary>
    /// <param name="text">The identifier.</param>
    /// <returns>Whether every character belongs to a plain identifier.</returns>
    internal static bool IsPlainIdentifier(ReadOnlySpan<char> text) =>
        text.Length != 0 && text[0] != '@' && IdentifierSegmentLength(text) == text.Length;

    /// <summary>
    ///  Matches an unqualified ordinary or cheap-local definition.
    /// </summary>
    /// <param name="text">The definition name.</param>
    /// <returns>Whether the entire span is one segment.</returns>
    internal static bool IsDefinitionIdentifier(ReadOnlySpan<char> text) =>
        text.Length != 0 && IdentifierSegmentLength(text) == text.Length;

    /// <summary>
    ///  Finds the length of an identifier at the start of a span.
    /// </summary>
    /// <param name="text">The syntax.</param>
    /// <returns>The identifier length, or zero.</returns>
    internal static int IdentifierLength(ReadOnlySpan<char> text)
    {
        int length = text.Length > 1 && text[0] == ':' && text[1] == ':' ? 2 : 0;
        int segment = IdentifierSegmentLength(text[length..]);
        if (segment == 0) { return 0; }
        length += segment;
        while (length + 2 < text.Length && text[length] == ':' && text[length + 1] == ':')
        {
            segment = IdentifierSegmentLength(text[(length + 2)..]);
            if (segment == 0) { break; }
            length += 2 + segment;
        }

        return length;
    }

    /// <summary>
    ///  Finds one ordinary or cheap-local identifier segment.
    /// </summary>
    /// <param name="text">The syntax.</param>
    /// <returns>The segment length, or zero.</returns>
    internal static int IdentifierSegmentLength(ReadOnlySpan<char> text)
    {
        if (text.IsEmpty || !IsIdentifierStart(text[0])) { return 0; }
        if (text[0] == '@' && (text.Length == 1 || !IsWord(text[1]))) { return 0; }
        int length = 1;
        while (length < text.Length && IsWord(text[length])) { length++; }
        return length;
    }

    /// <summary>
    ///  Matches the first character of an identifier.
    /// </summary>
    /// <param name="value">The character.</param>
    /// <returns>Whether it can start a native identifier.</returns>
    internal static bool IsIdentifierStart(char value) => char.IsAsciiLetter(value) || value is '_' or '@';

    /// <summary>
    ///  Matches a character in a native word.
    /// </summary>
    /// <param name="value">The character.</param>
    /// <returns>Whether it is a word character.</returns>
    internal static bool IsWord(char value) =>
        char.IsAsciiLetterOrDigit(value)
            || value == '_'
            || (value > 127 && char.GetUnicodeCategory(value) switch
                {
                    UnicodeCategory.UppercaseLetter => true,
                    UnicodeCategory.LowercaseLetter => true,
                    UnicodeCategory.TitlecaseLetter => true,
                    UnicodeCategory.ModifierLetter => true,
                    UnicodeCategory.OtherLetter => true,
                    UnicodeCategory.NonSpacingMark => true,
                    UnicodeCategory.DecimalDigitNumber => true,
                    UnicodeCategory.ConnectorPunctuation => true,
                    _ => false
                });

    /// <summary>
    ///  Matches a namespace-qualified metadata type name.
    /// </summary>
    /// <param name="text">The type name.</param>
    /// <returns>Whether it contains at least two valid identifier segments.</returns>
    internal static bool IsQualifiedIdentifier(ReadOnlySpan<char> text)
    {
        bool qualified = false;
        while (!text.IsEmpty)
        {
            int length = IdentifierSegmentLength(text);
            if (length == 0) { return false; }
            if (text[0] == '@') { return false; }
            if (length == text.Length) { return qualified; }
            if (text[length] != '.') { return false; }
            qualified = true;
            text = text[(length + 1)..];
        }

        return false;
    }

    /// <summary>
    ///  Determines whether a data operand is one double-quoted string with no embedded quote.
    /// </summary>
    /// <param name="text">The trimmed data operand.</param>
    /// <returns>Whether the operand supplies one data element per character.</returns>
    internal static bool IsStringLiteral(ReadOnlySpan<char> text) =>
        text.Length >= 2 && text[0] == '"' && text[^1] == '"' && text[1..^1].IndexOf('"') < 0;

    /// <summary>
    ///  Measures a <c>.w</c> mnemonic suffix that forces absolute addressing.
    /// </summary>
    /// <param name="text">The text immediately after the mnemonic.</param>
    /// <returns>The suffix length, or zero when the text does not start with a complete suffix.</returns>
    internal static int WideSuffixLength(ReadOnlySpan<char> text) =>
        text.Length >= 2 && text[0] == '.' && text[1] is 'w' or 'W' && (text.Length == 2 || char.IsWhiteSpace(text[2]))
            ? 2 : 0;

    /// <summary>
    ///  Measures an <c>a:</c> or <c>!</c> operand prefix that forces absolute addressing.
    /// </summary>
    /// <param name="text">The compact operand.</param>
    /// <returns>The prefix length, or zero when the operand has no width prefix.</returns>
    internal static int AbsolutePrefixLength(ReadOnlySpan<char> text) =>
        text.Length >= 2 && text[0] is 'a' or 'A' && text[1] == ':' && (text.Length == 2 || text[2] != ':')
            ? 2 : !text.IsEmpty && text[0] == '!' ? 1 : 0;

    /// <summary>
    ///  Measures a z: prefix requiring zero-page addressing, without consuming a qualified name.
    /// </summary>
    /// <param name="text">The compact operand.</param>
    /// <returns>The prefix length, or zero.</returns>
    internal static int ZeroPagePrefixLength(ReadOnlySpan<char> text) =>
        text.Length >= 2 && text[0] is 'z' or 'Z' && text[1] == ':' && (text.Length == 2 || text[2] != ':') ? 2 : 0;

    /// <summary>
    ///  Determines whether the opening parenthesis closes at the final character, as indirect operands require.
    /// </summary>
    /// <param name="text">The compact operand or its leading portion.</param>
    /// <returns>Whether the text is one group; false for <c>(A)+(B)</c>, whose first group closes early.</returns>
    internal static bool IsParenthesized(ReadOnlySpan<char> text)
    {
        if (text.Length < 2 || text[0] != '(' || text[^1] != ')') { return false; }
        int depth = 0;
        char quote = '\0';
        for (int index = 0; index < text.Length; index++)
        {
            char value = text[index];
            if (TogglesQuote(text, index, quote)) { quote = quote == '\0' ? value : '\0'; }
            if (quote != '\0') { continue; }
            if (value == '(') { depth++; }
            else if (value == ')' && --depth == 0) { return index == text.Length - 1; }
        }

        return false;
    }

    /// <summary>
    ///  Gets the string for a range of characters, reusing the underlying string when the range is all of it.
    /// </summary>
    /// <param name="text">The characters.</param>
    /// <returns>The string.</returns>
    internal static string AsString(ReadOnlyMemory<char> text)
    {
        bool found = MemoryMarshal.TryGetString(text, out string? owner, out int start, out int length);
        return found && owner is not null && start == 0 && length == owner.Length ? owner : text.ToString();
    }

    /// <summary>
    ///  Gets whether a character opens or closes a quoted literal.
    /// </summary>
    /// <param name="text">The text.</param>
    /// <param name="index">The character's index.</param>
    /// <param name="quote">The open quote, or <c>'\0'</c> outside a literal.</param>
    /// <returns>
    ///  Whether it toggles the literal. An apostrophe right after a letter, as in the Z80's <c>AF'</c>, is a
    ///  prime rather than a quote, since no literal starts there.
    /// </returns>
    [System.Runtime.CompilerServices.MethodImpl(System.Runtime.CompilerServices.MethodImplOptions.AggressiveInlining)]
    internal static bool TogglesQuote(ReadOnlySpan<char> text, int index, char quote)
    {
        // Most characters are neither quote, so that test comes first.
        char value = text[index];
        return value is ('\'' or '"')
            && (quote != '\0' ? value == quote : value == '"' || index == 0 || !char.IsAsciiLetter(text[index - 1]));
    }

    /// <summary>
    ///  Removes a comment without copying quoted literals or line content.
    /// </summary>
    /// <param name="text">The source line.</param>
    /// <returns>The non-comment portion.</returns>
    internal static ReadOnlySpan<char> WithoutComment(ReadOnlySpan<char> text)
    {
        char quote = '\0';
        for (int index = 0; index < text.Length; index++)
        {
            char value = text[index];
            if (quote == '\0' && value == ';') { return text[..index]; }

            // Only the active quote kind closes a literal; a semicolon inside either literal is data.
            if (TogglesQuote(text, index, quote)) { quote = quote == '\0' ? value : '\0'; }
        }

        return text;
    }

    /// <summary>
    ///  Removes only unquoted whitespace, allocating storage only when compaction is necessary.
    /// </summary>
    /// <param name="text">The original operand.</param>
    /// <returns>The original string or its compact form.</returns>
    internal static string Compact(string text) => AsString(Compact(text.AsMemory()));

    /// <summary>
    ///  Removes only unquoted whitespace, allocating storage only when compaction is necessary.
    /// </summary>
    /// <param name="operand">The original operand.</param>
    /// <returns>The original characters or their compact form.</returns>
    internal static ReadOnlyMemory<char> Compact(ReadOnlyMemory<char> operand)
    {
        ReadOnlySpan<char> text = operand.Span;
        int first = 0;
        char quote = '\0';
        for (; first < text.Length; first++)
        {
            char value = text[first];
            if (TogglesQuote(text, first, quote)) { quote = quote == '\0' ? value : '\0'; }
            if (quote == '\0' && char.IsWhiteSpace(value)) { break; }
        }

        // Most operands are already compact, so avoid both a buffer rental and a replacement string.
        if (first == text.Length) { return operand; }
        char[]? rented = null;
        Span<char> buffer = text.Length <= StackBufferSize ? stackalloc char[StackBufferSize]
            : (rented = ArrayPool<char>.Shared.Rent(text.Length));

        try
        {
            // The prefix needs no changes. Resume after the first removable space without losing quoted spaces.
            text[..first].CopyTo(buffer);
            int length = first;
            for (int index = first + 1; index < text.Length; index++)
            {
                char value = text[index];
                if (TogglesQuote(text, index, quote)) { quote = quote == '\0' ? value : '\0'; }
                if (quote != '\0' || !char.IsWhiteSpace(value)) { buffer[length++] = value; }
            }

            return buffer[..length].ToString().AsMemory();
        }
        finally
        {
            if (rented is not null) { ArrayPool<char>.Shared.Return(rented); }
        }
    }
}
