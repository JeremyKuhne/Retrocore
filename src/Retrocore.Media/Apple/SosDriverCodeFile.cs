// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text;

namespace Retrocore.Media;

/// <summary>
///  Reads a driver from a driver file the System Configuration Program installs from: an Apple Pascal code file
///  with the driver as its one assembled segment.
/// </summary>
/// <remarks>
///  <para>
///   Block 0 is the segment dictionary: for each of 16 segments, its block and length. A segment ends with its
///   procedure dictionary: the procedure count and segment number in its last word, then self-relative pointers
///   back to each procedure's attributes. Below the attributes is the procedure's entry pointer, and below that
///   the four relocation lists (base, segment, procedure and interpreter relative), each a count followed downward
///   by self-relative pointers to the words to relocate. A driver uses the procedure-relative list: the words SOS
///   adds the driver's load address to.
///  </para>
///  <para>
///   The code runs from the entry to its last relocated word, after which the assembler pads to a word. A driver
///   that has a comment starts with its comment record: $FFFF, the comment's length and its text.
///  </para>
/// </remarks>
public static class SosDriverCodeFile
{
    private const int BlockSize = 512;

    /// <summary>
    ///  Reads the driver in a driver code file.
    /// </summary>
    /// <param name="data">The file's contents.</param>
    /// <returns>The driver: its comment, code at origin 0, and relocations.</returns>
    /// <exception cref="InvalidDataException">The file is not a code file with one driver segment.</exception>
    public static SosDriver Read(ReadOnlySpan<byte> data)
    {
        if (data.Length < BlockSize)
        {
            throw new InvalidDataException("A code file starts with its segment dictionary.");
        }

        int start = -1;
        int length = 0;
        for (int segment = 0; segment < 16; segment++)
        {
            int size = Word(data, (segment * 4) + 2);
            if (size == 0) { continue; }
            if (start >= 0)
            {
                throw new InvalidDataException("The code file has more than one segment.");
            }

            start = Word(data, segment * 4) * BlockSize;
            length = size;
        }

        if (start < 0 || start + length > data.Length)
        {
            throw new InvalidDataException("The code file has no segment.");
        }

        ReadOnlySpan<byte> code = data.Slice(start, length);
        int attributes = (length - 4) - Word(code, length - 4);
        int pointer = attributes - 2;
        int entry = pointer - Word(code, pointer);
        List<int>[] lists = [[], [], [], []];
        foreach (List<int> list in lists)
        {
            pointer -= 2;
            int count = Word(code, pointer);
            for (int item = 0; item < count; item++)
            {
                pointer -= 2;
                list.Add(pointer - Word(code, pointer));
            }
        }

        int[] relocations = [.. lists[2].Order()];
        int end = relocations.Length == 0 ? pointer : relocations[^1] + 2;
        ReadOnlySpan<byte> driver = code[entry..end];
        string comment = "";
        int offset = 0;
        if (driver.Length >= 4 && driver[0] == 0xFF && driver[1] == 0xFF)
        {
            int size = Word(driver, 2);
            comment = Encoding.ASCII.GetString(driver.Slice(4, size));
            offset = 4 + size;
        }

        return new SosDriver(
            comment,
            driver[offset..].ToArray(),
            [.. relocations.Select(relocation => relocation - entry - offset)]);
    }

    private static int Word(ReadOnlySpan<byte> data, int offset) => data[offset] | (data[offset + 1] << 8);
}
