// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Globalization;
using System.Text;

namespace Retrocore.Basic;

/// <summary>
///  The text form of BASIC: what can be typed as itself, and the escapes for the bytes that cannot.
/// </summary>
/// <remarks>
///  <para>
///   A printable ASCII character stands for itself, as if typed. <c>{{</c> is a typed <c>{</c>. <c>{CTRL-D}</c> is a
///   control character, and <c>{$84}</c> any byte. An escaped byte is stored exactly as given: it is never part of a
///   reserved word, and it does not start or end a string, DATA or REM.
///  </para>
/// </remarks>
public static class BasicText
{
    /// <summary>
    ///  Marks a unit of parsed text as a byte to store as it is, rather than a typed character.
    /// </summary>
    internal const int Raw = 0x100;

    private const int ControlOffset = 0x40;
    private const int FirstPrintable = 0x20;
    private const int LastPrintable = 0x7E;

    /// <summary>
    ///  Parses statement text into the units a tokenizer reads: typed characters, and escaped bytes marked with
    ///  <see cref="Raw"/>.
    /// </summary>
    /// <param name="text">The text.</param>
    /// <param name="columns">Receives the column each unit starts at, when given.</param>
    /// <returns>The units.</returns>
    /// <exception cref="FormatException">
    ///  The text has a character that cannot be typed, or an escape that is not one; the message gives its column.
    /// </exception>
    internal static int[] Parse(string text, List<int>? columns = null)
    {
        List<int> units = new(text.Length);
        for (int index = 0; index < text.Length; index++)
        {
            char character = text[index];
            columns?.Add(index);
            if (character == '{')
            {
                units.Add(Escape(text, ref index));
                continue;
            }

            if (character is < (char)FirstPrintable or > (char)LastPrintable)
            {
                throw new FormatException(string.Create(
                    CultureInfo.InvariantCulture,
                    $"Column {index + 1}: U+{(int)character:X4} cannot be typed; write it as an escape such as {{$84}}."));
            }

            units.Add(character);
        }

        return [.. units];
    }

    /// <summary>
    ///  Writes a byte as the text form shows it: itself when printable, else an escape.
    /// </summary>
    /// <param name="builder">The text being built.</param>
    /// <param name="value">The byte.</param>
    internal static void AppendCharacter(StringBuilder builder, byte value)
    {
        if (value == '{')
        {
            builder.Append("{{");
        }
        else if (value is >= FirstPrintable and <= LastPrintable)
        {
            builder.Append((char)value);
        }
        else
        {
            AppendEscape(builder, value);
        }
    }

    /// <summary>
    ///  Writes a byte as an escape.
    /// </summary>
    /// <param name="builder">The text being built.</param>
    /// <param name="value">The byte.</param>
    internal static void AppendEscape(StringBuilder builder, byte value)
    {
        if (value is > 0 and < FirstPrintable)
        {
            builder.Append("{CTRL-").Append((char)(value + ControlOffset)).Append('}');
        }
        else
        {
            builder.Append(CultureInfo.InvariantCulture, $"{{${value:X2}}}");
        }
    }

    /// <summary>
    ///  Finds the dialect a file names in its first line, as <c>REM retrocore applesoft</c> or <c>' retrocore level2</c>,
    ///  with or without a line number.
    /// </summary>
    /// <param name="line">The first line that is not blank.</param>
    /// <param name="numbered">Whether the pragma has a line number, so it is part of the program.</param>
    /// <returns>The dialect's name, or null when the line is not a pragma.</returns>
    public static string? Pragma(string line, out bool numbered)
    {
        ArgumentNullException.ThrowIfNull(line);
        ReadOnlySpan<char> text = line.AsSpan().Trim();
        int digits = 0;
        while (digits < text.Length && char.IsAsciiDigit(text[digits])) { digits++; }
        numbered = digits > 0;
        text = text[digits..].TrimStart();
        if (text.StartsWith("REM", StringComparison.OrdinalIgnoreCase))
        {
            text = text[3..];
        }
        else if (text.StartsWith('\''))
        {
            text = text[1..];
        }
        else
        {
            return null;
        }

        text = text.TrimStart();
        if (!text.StartsWith("retrocore", StringComparison.OrdinalIgnoreCase)) { return null; }
        text = text[9..];
        if (text.Length == 0 || !char.IsWhiteSpace(text[0])) { return null; }
        text = text.TrimStart();
        int end = 0;
        while (end < text.Length && !char.IsWhiteSpace(text[end])) { end++; }
        return end == 0 ? null : text[..end].ToString().ToLowerInvariant();
    }

    /// <summary>
    ///  Finds the dialect a file's double extension names, such as <c>game.applesoft.bas</c>.
    /// </summary>
    /// <param name="path">The file.</param>
    /// <returns>The dialect's name, or null when the name has no dialect extension.</returns>
    public static string? DialectOfPath(string path)
    {
        ArgumentNullException.ThrowIfNull(path);
        string name = Path.GetFileName(path);
        if (!name.EndsWith(".bas", StringComparison.OrdinalIgnoreCase)) { return null; }
        string stem = name[..^4];
        int dot = stem.LastIndexOf('.');
        return dot < 0 ? null : stem[(dot + 1)..].ToLowerInvariant();
    }

    // Parses the escape starting at text[index], leaving index on its last character.
    private static int Escape(string text, ref int index)
    {
        int start = index;
        if (index + 1 < text.Length && text[index + 1] == '{')
        {
            index++;
            return '{';
        }

        int close = text.IndexOf('}', index + 1);
        if (close < 0) { throw Bad(start, "an escape has no closing }; write a literal { as {{"); }
        string body = text[(index + 1)..close];
        index = close;
        if (body.Length == 3
            && body[0] == '$'
            && byte.TryParse(body.AsSpan(1), NumberStyles.AllowHexSpecifier, CultureInfo.InvariantCulture, out byte value))
        {
            if (value == 0) { throw Bad(start, "a line cannot hold a zero byte, which ends it"); }

            return Raw | value;
        }

        if (body.Length == 6 && body.StartsWith("CTRL-", StringComparison.OrdinalIgnoreCase))
        {
            int control = char.ToUpperInvariant(body[5]) - ControlOffset;
            if (control is > 0 and < FirstPrintable) { return Raw | control; }
        }

        throw Bad(start, $"{{{body}}} is not an escape; use {{$hh}} for a byte or {{CTRL-x}} for a control character");
    }

    private static FormatException Bad(int index, string message) =>
        new(string.Create(CultureInfo.InvariantCulture, $"Column {index + 1}: {message}."));
}
