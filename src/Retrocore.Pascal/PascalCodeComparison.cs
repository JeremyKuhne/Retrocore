// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Media;

namespace Retrocore.Pascal;

/// <summary>
///  Compares two code files segment by segment: what the segment dictionary says of each, and its code.
/// </summary>
/// <remarks>
///  <para>
///   Where segments sit in the file, and the blocks of a unit's interface text, are left out: they follow from the
///   code's lengths. A difference in code is reported at its first byte, with the procedure it is in and the p-code
///   there in each file. The byte the Compiler skips to put an <c>LDC</c>'s or an <c>XJP</c>'s words on a word
///   boundary holds whatever its buffer last had, so no source decides it, and it is not compared.
///  </para>
/// </remarks>
public static class PascalCodeComparison
{
    /// <summary>
    ///  Compares two code files.
    /// </summary>
    /// <param name="expected">The code file to match, such as the original.</param>
    /// <param name="actual">The code file to check, such as a recompiled one.</param>
    /// <returns>The differences, each a line of text; none when the segments are the same.</returns>
    public static IReadOnlyList<string> Compare(PascalCodeFile expected, PascalCodeFile actual)
    {
        ArgumentNullException.ThrowIfNull(expected);
        ArgumentNullException.ThrowIfNull(actual);
        List<string> differences = [];
        int count = Math.Max(expected.Segments.Count, actual.Segments.Count);
        for (int index = 0; index < count; index++)
        {
            if (index >= expected.Segments.Count)
            {
                differences.Add($"An extra segment {actual.Segments[index].Name}.");
                continue;
            }

            if (index >= actual.Segments.Count)
            {
                differences.Add($"The segment {expected.Segments[index].Name} is missing.");
                continue;
            }

            Compare(expected.Segments[index], actual.Segments[index], differences);
        }

        if (expected.IntrinsicUnits != actual.IntrinsicUnits)
        {
            differences.Add($"The intrinsic units are ${expected.IntrinsicUnits:X8}, not ${actual.IntrinsicUnits:X8}.");
        }

        return differences;
    }

    private static void Compare(PascalSegment expected, PascalSegment actual, List<string> differences)
    {
        string name = expected.Name;
        Check(differences, name, "name", expected.Name, actual.Name);
        Check(differences, name, "kind", expected.Kind, actual.Kind);
        Check(differences, name, "number", expected.Number, actual.Number);
        Check(differences, name, "machine type", expected.MachineType, actual.MachineType);
        Check(differences, name, "version", expected.Version, actual.Version);
        Check(differences, name, "length", expected.Length, actual.Length);
        Check(differences, name, "procedure count", expected.Procedures.Count, actual.Procedures.Count);

        byte[] first = expected.Code;
        byte[] second = actual.Code;
        HashSet<int> padding = Padding(expected);
        int length = Math.Min(first.Length, second.Length);
        int at = 0;
        while (at < length && (first[at] == second[at] || padding.Contains(at))) { at++; }
        if (at == length && first.Length == second.Length) { return; }

        PascalProcedure? procedure = Containing(expected, at);
        string where = procedure is null ? "" : $" in {name}.{procedure.Index}";
        differences.Add($"{name}: the code differs from ${at:X4}{where}:");
        differences.Add($"  expected {Near(expected, procedure, at)}");
        differences.Add($"  actual   {Near(actual, Containing(actual, at), at)}");
    }

    // The bytes skipped to align p-code operands on a word, found by decoding each p-code procedure.
    private static HashSet<int> Padding(PascalSegment segment)
    {
        HashSet<int> padding = [];
        foreach (PascalProcedure procedure in segment.Procedures.Where(procedure => !procedure.IsNative))
        {
            IReadOnlyList<PcodeInstruction> instructions;
            try
            {
                instructions = PcodeDisassembler.Disassemble(segment, procedure);
            }
            catch (InvalidDataException)
            {
                continue;
            }

            foreach (PcodeInstruction instruction in instructions)
            {
                // LDC's count and XJP's opcode end where the operand's alignment starts.
                int aligned = instruction.Opcode.Operands switch
                {
                    PcodeOperands.Words => instruction.Offset + 2,
                    PcodeOperands.CaseJump => instruction.Offset + 1,
                    _ => -1
                };

                if (aligned >= 0 && (aligned & 1) != 0) { padding.Add(aligned); }
            }
        }

        return padding;
    }

    // The procedure whose code holds an offset: the one with the nearest entry at or below it.
    private static PascalProcedure? Containing(PascalSegment segment, int offset) =>
        segment.Procedures
            .Where(procedure => procedure.Entry <= offset && offset <= procedure.Attributes)
            .OrderByDescending(procedure => procedure.Entry)
            .FirstOrDefault();

    // The p-code at or just before an offset, or its bytes where there is none.
    private static string Near(PascalSegment segment, PascalProcedure? procedure, int offset)
    {
        if (procedure is { IsNative: false })
        {
            try
            {
                PcodeInstruction? found = PcodeDisassembler.Disassemble(segment, procedure).LastOrDefault(instruction => instruction.Offset <= offset);
                if (found is not null) { return $"${found.Offset:X4}: {found}"; }
            }
            catch (InvalidDataException)
            {
                // Code that does not decode is shown as bytes.
            }
        }

        byte[] code = segment.Code;
        return offset >= code.Length
            ? "the end of the segment"
            : string.Join(' ', code.AsSpan(offset, Math.Min(8, code.Length - offset)).ToArray().Select(value => $"${value:X2}"));
    }

    private static void Check<T>(List<string> differences, string segment, string what, T expected, T actual)
    {
        if (!EqualityComparer<T>.Default.Equals(expected, actual))
        {
            differences.Add($"{segment}: its {what} is {actual}, not {expected}.");
        }
    }
}
