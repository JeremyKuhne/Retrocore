// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Globalization;

namespace Retrocore.Assembler;

/// <summary>
///  Merlin column syntax and non-structural directive translation.
/// </summary>
internal static class MerlinFrontend
{
    private static readonly HashSet<string> s_stringDirectives =
        new(["ASC", "DCI", "INV", "FLS", "REV", "STR"], StringComparer.OrdinalIgnoreCase);

    /// <summary>
    ///  Splits source using column-zero labels and reference-compatible operand whitespace.
    /// </summary>
    /// <param name="text">The physical line.</param>
    /// <param name="label">The optional column-zero label.</param>
    /// <param name="operation">The opcode or directive.</param>
    /// <param name="operand">The operand without its trailing comment.</param>
    internal static void Split(ReadOnlySpan<char> text, out string label, out string operation, out string operand)
    {
        label = operation = operand = "";
        if (text.Length == 0 || text[0] is '*' or ';') { return; }
        int position = 0;
        if (!char.IsWhiteSpace(text[0])) { label = Word(text, ref position); }
        while (position < text.Length && char.IsWhiteSpace(text[position])) { position++; }
        if (position == text.Length || text[position] == ';') { return; }
        operation = Word(text, ref position);
        int end = position;
        char quote = '\0';
        bool stringDirective = s_stringDirectives.Contains(operation);
        for (; end < text.Length; end++)
        {
            char character = text[end];
            if (quote != '\0')
            {
                if (character == quote) { quote = '\0'; }
            }
            else if (character is '"' or '\'' || (stringDirective && end == position))
            {
                quote = character;
            }
            else if (character == ';' && (end == position || char.IsWhiteSpace(text[end - 1])))
            {
                break;
            }
        }

        operand = text[position..end].TrimEnd().ToString();
    }

    /// <summary>
    ///  Reads the word at a position and skips the whitespace after it.
    /// </summary>
    /// <param name="text">The line.</param>
    /// <param name="position">The word's start, advanced past it and its trailing whitespace.</param>
    /// <returns>The word.</returns>
    private static string Word(ReadOnlySpan<char> text, ref int position)
    {
        int start = position;
        while (position < text.Length && !char.IsWhiteSpace(text[position])) { position++; }
        string word = text[start..position].ToString();
        while (position < text.Length && char.IsWhiteSpace(text[position])) { position++; }
        return word;
    }

    /// <summary>
    ///  Emits equivalent native strings and trailing hexadecimal bytes.
    /// </summary>
    /// <param name="operation">The Merlin string directive.</param>
    /// <param name="operand">Delimited source and optional hex trailer.</param>
    /// <param name="equate">Raw EQU substitutions used in hexadecimal trailers.</param>
    /// <returns>A native byte list.</returns>
    internal static string StringData(string operation, string operand, Func<string, string> equate)
    {
        ReadOnlySpan<char> source = operand;
        List<byte> bytes = [];
        int position = 0;
        while (position < operand.Length)
        {
            if (char.IsWhiteSpace(operand[position]) || operand[position] == ',')
            {
                position++;
                continue;
            }

            char delimiter = operand[position];
            bool quoted = delimiter is '\'' or '"' || !char.IsLetterOrDigit(delimiter);
            if (!quoted)
            {
                int start = position;
                while (position < operand.Length && operand[position] != ',' && !char.IsWhiteSpace(operand[position]))
                {
                    position++;
                }

                bytes.AddRange(Hex(equate(operand[start..position])));
                continue;
            }

            int close = operand.IndexOf(delimiter, position + 1);
            if (close < 0) { throw new AssemblyError(0, "Unterminated Merlin string."); }
            if (operation == "REV" && operand[(close + 1)..].Trim().Length != 0)
            {
                throw new AssemblyError(0, "REV takes one string without trailers.");
            }

            List<byte> part = [];
            foreach (char character in source[(position + 1)..close])
            {
                if (character > 127) { throw new AssemblyError(0, "Merlin string characters must be ASCII."); }
                byte value = (byte)(character | (delimiter < '\'' ? 0x80 : 0));
                if (operation == "INV") { value = (byte)(character & 0x3F); }
                if (operation == "FLS") { value = (byte)((character & 0x3F) | 0x40); }
                part.Add(value);
            }

            if (operation == "REV") { part.Reverse(); }
            bytes.AddRange(part);
            position = close + 1;
        }

        if (operation == "DCI" && bytes.Count != 0) { bytes[^1] ^= 0x80; }
        if (operation == "STR")
        {
            if (bytes.Count > 255) { throw new AssemblyError(0, "STR length exceeds one byte."); }
            bytes.Insert(0, (byte)bytes.Count);
        }

        return $".byte {string.Join(",", bytes)}";
    }

    /// <summary>
    ///  Decodes a Merlin hexadecimal data list.
    /// </summary>
    /// <param name="operand">Pairs of hex digits with optional commas and spaces.</param>
    /// <returns>The owned byte array.</returns>
    internal static byte[] Hex(string operand)
    {
        string digits = new([.. operand.Where(character => !char.IsWhiteSpace(character) && character != ',')]);
        if (digits.Length % 2 != 0) { throw new AssemblyError(0, "HEX requires pairs of hexadecimal digits."); }
        byte[] bytes = new byte[digits.Length / 2];
        for (int index = 0; index < bytes.Length; index++)
        {
            if (!byte.TryParse(digits.Substring(index * 2, 2), NumberStyles.HexNumber, CultureInfo.InvariantCulture, out bytes[index]))
            {
                throw new AssemblyError(0, "Invalid Merlin hexadecimal data.");
            }
        }

        return bytes;
    }
}
