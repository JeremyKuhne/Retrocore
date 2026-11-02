// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Media;

/// <summary>
///  A file to put on a DOS 3.2 or 3.3 disk.
/// </summary>
/// <param name="Name">The name, up to 30 characters.</param>
/// <param name="Type">The type.</param>
/// <param name="Contents">The bytes as DOS stores them, including any length or address at the start.</param>
/// <param name="Locked">Whether the file is locked.</param>
public sealed record DosFile(string Name, DosFileType Type, ReadOnlyMemory<byte> Contents, bool Locked = false)
{
    /// <summary>
    ///  Gets the longest name DOS stores.
    /// </summary>
    public const int MaximumNameLength = 30;

    /// <summary>
    ///  Creates a binary file, as BSAVE writes one: its load address, its length, then the bytes.
    /// </summary>
    /// <param name="name">The name.</param>
    /// <param name="address">Where BLOAD and BRUN put it.</param>
    /// <param name="data">The bytes, at most 32767.</param>
    /// <returns>The file.</returns>
    public static DosFile Binary(string name, int address, ReadOnlySpan<byte> data)
    {
        if (address is < 0 or > 0xFFFF) { throw new ArgumentOutOfRangeException(nameof(address)); }
        if (data.Length > 0x7FFF)
        {
            throw new ArgumentException("A binary file holds at most 32767 bytes.", nameof(data));
        }

        byte[] contents = new byte[data.Length + 4];
        contents[0] = (byte)address;
        contents[1] = (byte)(address >> 8);
        contents[2] = (byte)data.Length;
        contents[3] = (byte)(data.Length >> 8);
        data.CopyTo(contents.AsSpan(4));
        return new(name, DosFileType.Binary, contents);
    }

    /// <summary>
    ///  Creates an AppleSoft program file, as SAVE writes one: its length, then the tokenized program.
    /// </summary>
    /// <param name="name">The name.</param>
    /// <param name="program">The tokenized program, as it sits in memory from $0801.</param>
    /// <returns>The file.</returns>
    public static DosFile AppleSoft(string name, ReadOnlySpan<byte> program) =>
        new(name, DosFileType.AppleSoft, WithLength(program));

    /// <summary>
    ///  Creates an Integer BASIC program file, as SAVE writes one: its length, then the program.
    /// </summary>
    /// <param name="name">The name.</param>
    /// <param name="program">The program, as it sits in memory below HIMEM.</param>
    /// <returns>The file.</returns>
    public static DosFile IntegerBasic(string name, ReadOnlySpan<byte> program) =>
        new(name, DosFileType.IntegerBasic, WithLength(program));

    /// <summary>
    ///  Creates a text file: each character with bit 7 set, and a return ($8D) for each line ending.
    /// </summary>
    /// <param name="name">The name.</param>
    /// <param name="text">The text; carriage returns and line feeds both end lines.</param>
    /// <returns>The file.</returns>
    public static DosFile Text(string name, string text)
    {
        ArgumentNullException.ThrowIfNull(text);
        List<byte> contents = new(text.Length);
        for (int index = 0; index < text.Length; index++)
        {
            char character = text[index];
            if (character == '\r' && index + 1 < text.Length && text[index + 1] == '\n') { continue; }

            contents.Add(character is '\r' or '\n' ? (byte)0x8D : (byte)((character & 0x7F) | 0x80));
        }

        return new(name, DosFileType.Text, contents.ToArray());
    }

    // A program's length, then the program.
    private static byte[] WithLength(ReadOnlySpan<byte> program)
    {
        if (program.Length > 0xFFFF)
        {
            throw new ArgumentException("A program holds at most 65535 bytes.", nameof(program));
        }

        byte[] contents = new byte[program.Length + 2];
        contents[0] = (byte)program.Length;
        contents[1] = (byte)(program.Length >> 8);
        program.CopyTo(contents.AsSpan(2));
        return contents;
    }
}
