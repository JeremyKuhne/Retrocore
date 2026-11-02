// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

/// <summary>
///  Walks reference tokens without visiting quoted text, comments or numeric digits.
/// </summary>
internal ref struct AssemblyNameReferences
{
    private readonly ReadOnlyMemory<char> _text;
    private readonly bool _qualified;
    private int _next;

    /// <summary>
    ///  Creates a cursor over an operand or macro line.
    /// </summary>
    /// <param name="text">The original text.</param>
    /// <param name="qualified">
    ///  Whether scoped names form one reference token rather than individual substitution tokens.
    /// </param>
    internal AssemblyNameReferences(ReadOnlyMemory<char> text, bool qualified = true)
    {
        _text = text;
        _qualified = qualified;
    }

    /// <summary>
    ///  Gets the current reference token, including an optional :: or dot prefix.
    /// </summary>
    internal ReadOnlyMemory<char> Current { get; private set; }

    /// <summary>
    ///  Gets the token's offset in the original text.
    /// </summary>
    internal int Start { get; private set; }

    /// <summary>
    ///  Advances to the next identifier, unnamed-label reference or named operator.
    /// </summary>
    /// <returns>Whether a token was found.</returns>
    internal bool MoveNext()
    {
        ReadOnlySpan<char> text = _text.Span;
        while (_next < text.Length)
        {
            int start = _next;
            char character = text[_next++];
            if (character == ';') { return false; }
            if (character is '\'' or '"')
            {
                while (_next < text.Length && text[_next] != character) { _next++; }
                if (_next < text.Length) { _next++; }
                continue;
            }

            if (character is '$' or '%' || char.IsAsciiDigit(character))
            {
                while (_next < text.Length && AssemblySyntax.IsWord(text[_next])) { _next++; }
                continue;
            }

            int length;
            if (character == '.')
            {
                while (_next < text.Length && AssemblySyntax.IsWord(text[_next])) { _next++; }
                length = _next - start;
                if (length == 1) { continue; }
            }
            else if (character == ':' && _next < text.Length && text[_next] is '+' or '-')
            {
                char sign = text[_next++];
                while (_next < text.Length && text[_next] == sign) { _next++; }
                length = _next - start;
            }
            else
            {
                length = _qualified
                    ? AssemblySyntax.IdentifierLength(text[start..])
                    : AssemblySyntax.IdentifierSegmentLength(text[start..]);

                if (length == 0) { continue; }
                _next = start + length;
            }

            Start = start;
            Current = _text.Slice(start, length);
            return true;
        }

        return false;
    }
}
