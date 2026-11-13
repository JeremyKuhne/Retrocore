// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text;
using Retrocore.Media;

namespace Retrocore.Pascal;

/// <summary>
///  The units a library code file (such as <c>SYSTEM.LIBRARY</c>) holds, read from their interface text: each unit's
///  segment number, its procedures in the order calls number them, and the enumerated types it declares.
/// </summary>
/// <remarks>
///  <para>
///   A unit's interface text is kept in the code file from the block its segment dictionary entry gives, as text pages
///   up to the word <c>IMPLEMENTATION</c>. Procedure 1 of a unit's segment is its initialization; the procedures and
///   functions its interface declares follow from 2.
///  </para>
/// </remarks>
public sealed class PascalLibrary
{
    private PascalLibrary(IReadOnlyList<PascalUnit> units) => Units = units;

    /// <summary>
    ///  Gets the units.
    /// </summary>
    public IReadOnlyList<PascalUnit> Units { get; }

    /// <summary>
    ///  Gets the unit whose code is a segment.
    /// </summary>
    /// <param name="segment">The segment number.</param>
    /// <returns>The unit, or null.</returns>
    public PascalUnit? Unit(int segment) => Units.FirstOrDefault(unit => unit.Segment == segment);

    /// <summary>
    ///  Reads a library code file.
    /// </summary>
    /// <param name="data">The code file's contents.</param>
    /// <returns>Its units; a segment without interface text is left out.</returns>
    /// <exception cref="InvalidDataException">The file is not a code file.</exception>
    public static PascalLibrary Read(ReadOnlySpan<byte> data)
    {
        PascalCodeFile file = PascalCodeFile.Read(data);
        List<PascalUnit> units = [];
        foreach (PascalSegment segment in file.Segments)
        {
            if (segment.TextBlock == 0 || segment.Kind == PascalSegmentKind.Data) { continue; }

            int start = segment.TextBlock * 512;
            if (start >= data.Length) { continue; }

            int end = segment.Block > segment.TextBlock ? Math.Min(data.Length, segment.Block * 512) : data.Length;
            string text = Text(data[start..end]);
            units.Add(PascalUnit.Parse(segment.Name, segment.Number, text));
        }

        return new PascalLibrary(units);
    }

    // Text pages, with DLE indentation, up to IMPLEMENTATION.
    private static string Text(ReadOnlySpan<byte> data)
    {
        StringBuilder builder = new();
        for (int index = 0; index < data.Length; index++)
        {
            byte value = data[index];
            if (value == 0x10 && index + 1 < data.Length)
            {
                builder.Append(' ', Math.Max(0, data[++index] - 32));
            }
            else if (value == 0x0D)
            {
                builder.Append('\n');
            }
            else if (value != 0)
            {
                builder.Append((char)(value & 0x7F));
            }
        }

        string text = builder.ToString();
        int implementation = text.IndexOf("IMPLEMENTATION", StringComparison.OrdinalIgnoreCase);
        return implementation < 0 ? text : text[..implementation];
    }
}
