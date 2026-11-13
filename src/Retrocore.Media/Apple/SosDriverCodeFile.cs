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
    /// <summary>
    ///  Reads the driver in a driver code file.
    /// </summary>
    /// <param name="data">The file's contents.</param>
    /// <returns>The driver: its comment, code at origin 0, and relocations.</returns>
    /// <exception cref="InvalidDataException">The file is not a code file with one driver segment.</exception>
    public static SosDriver Read(ReadOnlySpan<byte> data)
    {
        PascalCodeFile file = PascalCodeFile.Read(data);
        PascalSegment[] segments = [.. file.Segments.Where(segment => segment.Code.Length != 0)];
        if (segments.Length != 1)
        {
            throw new InvalidDataException(segments.Length == 0 ? "The code file has no segment." : "The code file has more than one segment.");
        }

        PascalSegment segment = segments[0];
        PascalProcedure procedure = segment.Procedure(1)
            ?? throw new InvalidDataException("The driver's segment has no procedure.");

        if (!procedure.IsNative) { throw new InvalidDataException("The driver's procedure is not assembled code."); }

        // Below the entry pointer are the four lists, each a count and its pointers.
        int listEnd = procedure.Attributes - 2 - (2 * (procedure.Relocations.Count + procedure.Relocations.Sum(list => list.Count)));
        int entry = procedure.Entry;
        int[] relocations = [.. procedure.Relocations[2].Order()];
        int end = relocations.Length == 0 ? listEnd : relocations[^1] + 2;
        ReadOnlySpan<byte> driver = segment.Code.AsSpan(entry..end);
        string comment = "";
        int offset = 0;
        if (driver.Length >= 4 && driver[0] == 0xFF && driver[1] == 0xFF)
        {
            int size = driver[2] | (driver[3] << 8);
            comment = Encoding.ASCII.GetString(driver.Slice(4, size));
            offset = 4 + size;
        }

        return new SosDriver(
            comment,
            driver[offset..].ToArray(),
            [.. relocations.Select(relocation => relocation - entry - offset)]);
    }
}
