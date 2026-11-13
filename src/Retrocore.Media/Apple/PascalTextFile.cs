// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Media;

/// <summary>
///  Reads and writes an Apple Pascal text file (<c>.TEXT</c>) as plain text.
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

    /// <summary>
    ///  Writes text as a text file, as the Editor saves it: an empty header page, then the lines in pages, each line
    ///  ending with RETURN and its leading spaces packed.
    /// </summary>
    /// <param name="text">The text; lines end with a line feed, a RETURN or both.</param>
    /// <returns>The file's contents, a whole number of pages.</returns>
    /// <exception cref="ArgumentException">A line is longer than a page.</exception>
    public static byte[] Write(string text)
    {
        ArgumentNullException.ThrowIfNull(text);
        string[] lines = text.Replace("\r\n", "\n", StringComparison.Ordinal).Replace('\r', '\n').Split('\n');
        int count = lines.Length;
        if (count > 0 && lines[^1].Length == 0) { count--; }

        List<byte> file = [.. new byte[PageSize]];
        List<byte> page = new(PageSize);
        for (int index = 0; index < count; index++)
        {
            string line = lines[index].TrimEnd();
            int spaces = line.Length - line.TrimStart(' ').Length;
            List<byte> encoded = [];
            if (spaces > 0)
            {
                encoded.Add(Dle);
                encoded.Add((byte)(32 + Math.Min(spaces, 223)));
                line = new string(' ', Math.Max(0, spaces - 223)) + line[spaces..];
            }

            foreach (char character in line) { encoded.Add((byte)(character & 0x7F)); }
            encoded.Add(0x0D);

            // A page ends with at least one zero, and a line never crosses into the next page.
            if (encoded.Count >= PageSize)
            {
                throw new ArgumentException($"Line {index + 1} is longer than a page.", nameof(text));
            }

            if (page.Count + encoded.Count >= PageSize)
            {
                Flush(file, page);
            }

            page.AddRange(encoded);
        }

        if (page.Count > 0 || file.Count == PageSize) { Flush(file, page); }
        return [.. file];
    }

    private static void Flush(List<byte> file, List<byte> page)
    {
        file.AddRange(page);
        file.AddRange(new byte[PageSize - page.Count]);
        page.Clear();
    }
}
