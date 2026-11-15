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
///   boundary holds whatever its buffer last had, so no source decides it, and it is not compared; nor is the byte
///   that puts a procedure's attributes on a word after its code, which Apple Pascal 1.0's Compiler leaves the same.
///  </para>
///  <para>
///   Segments are paired in the order of their numbers, leaving out those with no code and the system's outer block
///   that a program compiled as part of the system, <c>(*$U-*)</c>, is nested in. Apple built its system programs that
///   way, then copied out their own segments with the Librarian, which also puts them in other slots.
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
        List<PascalSegment> first = Compared(expected);
        List<PascalSegment> second = Compared(actual);
        int count = Math.Max(first.Count, second.Count);
        for (int index = 0; index < count; index++)
        {
            if (index >= first.Count)
            {
                differences.Add($"An extra segment {second[index].Name}.");
                continue;
            }

            if (index >= second.Count)
            {
                differences.Add($"The segment {first[index].Name} is missing.");
                continue;
            }

            Compare(first[index], second[index], differences);
        }

        if (expected.IntrinsicUnits != actual.IntrinsicUnits)
        {
            differences.Add($"The intrinsic units are ${expected.IntrinsicUnits:X8}, not ${actual.IntrinsicUnits:X8}.");
        }

        return differences;
    }

    // The segments to compare, by number: those with code, but the system's outer block, at lexical level -1.
    private static List<PascalSegment> Compared(PascalCodeFile file) =>
        [.. file.Segments
            .Where(segment => segment.Length > 0 && segment.Procedure(1)?.LexicalLevel is not < 0)
            .OrderBy(segment => segment.Number)];

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

            // So does the byte after a procedure's last p-code that puts its attributes, which follow, on a word:
            // Apple Pascal 1.0's Compiler leaves its buffer's byte there.
            int end = instructions.Select(instruction => instruction.Next).DefaultIfEmpty(0).Max();
            if ((end & 1) != 0) { padding.Add(end); }
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
