// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Globalization;

/// <summary>
///  Reads the numbers and strings of a <c>.dat</c> file in turn.
/// </summary>
/// <param name="text">The file's text.</param>
internal sealed class DatReader(string text)
{
    private int _position;

    /// <summary>
    ///  Reads the next number.
    /// </summary>
    /// <returns>The number.</returns>
    /// <exception cref="InvalidDataException">The next item is not a number.</exception>
    internal int Number()
    {
        SkipSpace();
        int start = _position;
        if (_position < text.Length && text[_position] == '-') { _position++; }
        while (_position < text.Length && char.IsAsciiDigit(text[_position])) { _position++; }
        if (!int.TryParse(text.AsSpan(start, _position - start), NumberStyles.AllowLeadingSign, CultureInfo.InvariantCulture, out int value))
        {
            throw new InvalidDataException($"A number was expected at line {Line(start)}.");
        }

        return value;
    }

    /// <summary>
    ///  Reads the next quoted string, which may span lines; a <c>`</c> in it stands for a quotation mark.
    /// </summary>
    /// <returns>The string, with its line breaks as <c>\n</c>.</returns>
    /// <exception cref="InvalidDataException">The next item is not a quoted string.</exception>
    internal string Text()
    {
        SkipSpace();
        if (_position >= text.Length || text[_position] != '"')
        {
            throw new InvalidDataException($"A quoted string was expected at line {Line(_position)}.");
        }

        int start = ++_position;
        int end = text.IndexOf('"', start);
        if (end < 0) { throw new InvalidDataException($"The string at line {Line(start)} has no closing quote."); }
        _position = end + 1;
        return text[start..end].Replace("\r\n", "\n", StringComparison.Ordinal).Replace('\r', '\n').Replace('`', '"');
    }

    private void SkipSpace()
    {
        while (_position < text.Length && char.IsWhiteSpace(text[_position])) { _position++; }
    }

    private int Line(int position) => text.AsSpan(0, Math.Min(position, text.Length)).Count('\n') + 1;
}
