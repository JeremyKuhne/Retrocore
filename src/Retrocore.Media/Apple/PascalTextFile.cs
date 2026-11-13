// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Media;

/// <summary>
///  Reads an Apple Pascal text file (<c>.TEXT</c>) as plain text.
/// </summary>
/// <remarks>
///  <para>
///   The file starts with a 1,024-byte page the Editor keeps its settings in, then pages of 1,024 bytes, each a run of
///   whole lines ending with RETURN and padded with zeros. A line's leading spaces are packed as DLE (<c>$10</c>)
///   followed by 32 plus their number.
///  </para>
/// </remarks>
public static class PascalTextFile
{
    private const int PageSize = 1024;
    private const byte Dle = 0x10;

    /// <summary>
    ///  Reads a text file's lines.
    /// </summary>
    /// <param name="data">The file's contents, with its header page.</param>
    /// <returns>The text, with a line feed after each line.</returns>
    public static string Read(ReadOnlySpan<byte> data)
    {
        char[] text = new char[Math.Max(0, data.Length) * 2];
        int length = 0;
        for (int index = Math.Min(PageSize, data.Length); index < data.Length; index++)
        {
            byte value = data[index];
            if (value == 0) { continue; }

            if (value == Dle && index + 1 < data.Length)
            {
                int spaces = Math.Max(0, data[++index] - 32);
                if (length + spaces > text.Length) { Array.Resize(ref text, (length + spaces) * 2); }
                text.AsSpan(length, spaces).Fill(' ');
                length += spaces;
                continue;
            }

            if (length == text.Length) { Array.Resize(ref text, (length + 1) * 2); }
            text[length++] = value == 0x0D ? '\n' : (char)(value & 0x7F);
        }

        return new string(text, 0, length);
    }
}
