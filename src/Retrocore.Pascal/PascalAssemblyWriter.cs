// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Globalization;
using System.Text.RegularExpressions;
using Retrocore.Assembler;
using Retrocore.Cpu.M6502;
using Retrocore.Media;

namespace Retrocore.Pascal;

/// <summary>
///  Writes a segment's assembled procedures as source for Apple Pascal's own Assembler, which assembles it to the same
///  code and relocation lists for the Linker to link into a host.
/// </summary>
/// <remarks>
///  <para>
///   Each procedure is a <c>.PROC</c> or <c>.FUNC</c> with its name and its parameters' words, as the host declares it
///   EXTERNAL; the Linker matches the two by name. An operand or word the procedure-relative list names is written by
///   label, and the Assembler lists it again, in the order the code has it. An absolute operand below $100 of a
///   three-byte instruction is written as its bytes, as the Assembler would make it zero page.
///  </para>
///  <para>
///   Not written: data before a procedure's entry, which the Assembler starts at its <c>.PROC</c>, and words relative
///   to the interpreter, the segment or the host's globals (<c>.INTERP</c>, <c>.DEF</c> and <c>.REF</c>, and
///   <c>.PUBLIC</c>), whose names the code does not keep; a procedure with them is noted.
///  </para>
/// </remarks>
public static partial class PascalAssemblyWriter
{
    private static readonly string[] s_relocations = ["base", "segment", "procedure", "interpreter"];

    // Names the Assembler reads as other than a label.
    private static readonly HashSet<string> s_reserved = new(StringComparer.OrdinalIgnoreCase)
    {
        "A", "X", "Y", "ADC", "AND", "ASL", "BCC", "BCS", "BEQ", "BIT", "BMI", "BNE", "BPL", "BRK", "BVC", "BVS", "CLC",
        "CLD", "CLI", "CLV", "CMP", "CPX", "CPY", "DEC", "DEX", "DEY", "EOR", "INC", "INX", "INY", "JMP", "JSR", "LDA",
        "LDX", "LDY", "LSR", "NOP", "ORA", "PHA", "PHP", "PLA", "PLP", "ROL", "ROR", "RTI", "RTS", "SBC", "SEC", "SED",
        "SEI", "STA", "STX", "STY", "TAX", "TAY", "TSX", "TXA", "TXS", "TYA"
    };

    /// <summary>
    ///  Writes a segment's assembled procedures.
    /// </summary>
    /// <param name="segment">The segment.</param>
    /// <param name="procedures">Its assembled procedures to write, in order.</param>
    /// <returns>The source, and what it could not write as the code has it.</returns>
    public static PascalAssemblySource Write(PascalSegment segment, IReadOnlyList<PascalAssembledProcedure> procedures)
    {
        ArgumentNullException.ThrowIfNull(segment);
        ArgumentNullException.ThrowIfNull(procedures);
        List<string> lines = [];
        List<string> notes = [];
        foreach (PascalAssembledProcedure procedure in procedures)
        {
            if (segment.Procedure(procedure.Number) is { IsNative: true } code)
            {
                Procedure(lines, notes, segment, code, procedure);
            }
            else
            {
                notes.Add($"{segment.Name}.{procedure.Number} is not assembled code.");
            }
        }

        lines.Add(Line(label: null, ".END"));
        return new PascalAssemblySource(string.Join("\n", lines) + "\n", notes);
    }

    private static void Procedure(List<string> lines, List<string> notes, PascalSegment segment, PascalProcedure procedure, PascalAssembledProcedure written)
    {
        byte[] code = segment.Code;
        int number = procedure.Index;
        int attributes = procedure.Attributes;
        int entry = (attributes - 2) - Word(code, attributes - 2);
        string key = $"{segment.Name}.{number}";

        // The lists, read down from the entry pointer: each a count, then self-relative pointers to the words.
        Dictionary<int, int> relocated = [];
        int pointer = attributes - 2;
        for (int list = 0; list < 4; list++)
        {
            pointer -= 2;
            int count = Word(code, pointer);
            for (int item = 0; item < count; item++)
            {
                pointer -= 2;
                relocated[pointer - Word(code, pointer)] = list;
            }

            if (list != 2 && count > 0)
            {
                notes.Add($"{key} has {count} {s_relocations[list]}-relative words, which the source writes as numbers.");
            }
        }

        int bottom = pointer;
        int start = segment.Procedures
            .Where(other => other.Attributes < attributes)
            .Select(other => other.Attributes + 2)
            .DefaultIfEmpty(0)
            .Max();

        if (entry > start && code.AsSpan(start, entry - start).ContainsAnyExcept((byte)0))
        {
            notes.Add($"{key} has data before its entry, which the source leaves out.");
        }

        // Its code: 6502 instructions from the entry until data, which a relocated word, an instruction that does not
        // decode, or the end of a routine that no branch goes past marks.
        List<(int At, DisassembledInstruction Instruction)> instructions = [];
        HashSet<int> targets = [];
        int at = entry;
        while (at < bottom)
        {
            if (at != entry && relocated.ContainsKey(at)) { break; }
            if (!Disassembler.TryDecode(code.AsSpan(at, bottom - at), (ushort)at, ProcessorVariant.Mos6502, out DisassembledInstruction instruction)
                || instruction.IsUndocumented)
            {
                break;
            }

            instructions.Add((at, instruction));
            if (instruction.RelativeTarget is { } branch) { targets.Add(branch); }
            at += instruction.Size;
            if (instruction.Flow is DisassemblyFlow.Return or DisassemblyFlow.Jump or DisassemblyFlow.IndirectJump or DisassemblyFlow.Break
                && !targets.Contains(at))
            {
                break;
            }
        }

        int codeEnd = at;
        foreach ((int word, int list) in relocated)
        {
            if (list == 2) { targets.Add(entry + Word(code, word)); }
        }

        // Labels: the hints' names where they make labels, else L and the offset from the entry; a target inside an
        // instruction, or inside a relocated word, is named from where that starts.
        Dictionary<int, string> labels = [];
        Dictionary<int, string> inside = [];
        HashSet<string> used = new(StringComparer.Ordinal);
        foreach (int target in targets.Order())
        {
            int container = instructions
                .Where(item => item.At < target && target < item.At + item.Instruction.Size)
                .Select(item => item.At)
                .DefaultIfEmpty(-1)
                .First();

            if (container < 0 && relocated.ContainsKey(target - 1) && target - 1 >= codeEnd) { container = target - 1; }
            if (container >= 0)
            {
                inside[target] = $"{Label(container)}+{target - container}";
            }
            else if (target < entry || target >= bottom)
            {
                inside[target] = target < entry ? $"{Label(entry)}-{entry - target}" : $"{Label(entry)}+{target - entry}";
            }
            else
            {
                Label(target);
            }
        }

        string Label(int offset)
        {
            if (labels.TryGetValue(offset, out string? label)) { return label; }

            string fallback = $"L{offset - entry:X4}";
            label = written.Names.TryGetValue(offset - entry, out string? given) ? new string([.. given.Where(char.IsAsciiLetterOrDigit)]) : fallback;
            string upper = label.ToUpperInvariant();
            string significant = upper.Length > 8 ? upper[..8] : upper;
            if (label.Length == 0 || !char.IsAsciiLetter(label[0]) || s_reserved.Contains(significant) || used.Contains(significant))
            {
                label = fallback;
                significant = fallback.ToUpperInvariant();
            }

            used.Add(significant);
            labels[offset] = significant;
            return significant;
        }

        string Reference(int target) => inside.TryGetValue(target, out string? within) ? within : Label(target);

        if (written.Comment is { } about) { lines.Add($"; {about}"); }
        string name = written.Name.ToUpperInvariant();
        string directive = written.IsFunction ? ".FUNC" : ".PROC";
        string parameters = written.ParameterWords > 0 ? $",{written.ParameterWords}" : "";
        lines.Add(Line(label: null, $"{directive,-8}{(name.Length > 8 ? name[..8] : name)}{parameters}"));
        foreach ((int instructionAt, DisassembledInstruction instruction) in instructions)
        {
            Comment(instructionAt);
            lines.Add(Line(labels.GetValueOrDefault(instructionAt), Instruction(instructionAt, instruction)));
        }

        // Data to the relocation lists, which the Assembler writes; a relocated word by its label.
        int position = codeEnd;
        while (position < bottom)
        {
            Comment(position);
            if (relocated.TryGetValue(position, out int list) && list == 2 && position + 1 < bottom)
            {
                lines.Add(Line(labels.GetValueOrDefault(position), $".WORD   {Reference(entry + Word(code, position))}"));
                position += 2;
                continue;
            }

            int next = position + 1;
            while (next < bottom && next - position < 8 && !relocated.ContainsKey(next) && !labels.ContainsKey(next))
            {
                next++;
            }

            lines.Add(Line(labels.GetValueOrDefault(position), $".BYTE   {Bytes(code, position, next)}"));
            position = next;
        }

        void Comment(int offset)
        {
            if (written.Comments.TryGetValue(offset - entry, out string? text)) { lines.Add($"; {text}"); }
        }

        // An instruction in the Assembler's syntax: hexadecimal without $, its procedure-relative operand by label.
        string Instruction(int instructionAt, DisassembledInstruction instruction)
        {
            string text = instruction.ToString();
            int space = text.IndexOf(' ', StringComparison.Ordinal);
            string mnemonic = space < 0 ? text : text[..space];
            string operand = space < 0 ? "" : text[(space + 1)..];
            if (instruction.RelativeTarget is { } branch)
            {
                operand = HexNumber().Replace(operand, _ => Reference(branch), 1);
            }
            else if (instruction.Size == 3 && relocated.TryGetValue(instructionAt + 1, out int list) && list == 2)
            {
                operand = HexNumber().Replace(operand, _ => Reference(entry + Word(code, instructionAt + 1)), 1);
            }
            else if (instruction.Size == 3 && Word(code, instructionAt + 1) < 0x100)
            {
                // The Assembler would make it zero page.
                return $".BYTE   {Bytes(code, instructionAt, instructionAt + 3)}    ; {text}";
            }
            else
            {
                operand = HexNumber().Replace(operand, match => Hex(Number(match.Value)));
            }

            return operand.Length == 0 ? mnemonic : $"{mnemonic,-8}{operand}";
        }
    }

    private static string Bytes(byte[] code, int from, int to) => string.Join(",", code[from..to].Select(Hex));

    // A line: its label in the first eight columns, which are all the Assembler reads of one, then its text.
    private static string Line(string? label, string text) => $"{label ?? "",-8} {text}";

    // A number as the Assembler reads one: hexadecimal, from a digit.
    private static string Hex(byte value) => Hex((int)value);

    private static string Hex(int value)
    {
        string hex = value.ToString("X", CultureInfo.InvariantCulture);
        return char.IsAsciiLetter(hex[0]) ? $"0{hex}" : hex;
    }

    // A number the disassembler writes, $ and hexadecimal.
    private static int Number(string text) => int.Parse(text.AsSpan(1), NumberStyles.HexNumber, CultureInfo.InvariantCulture);

    private static int Word(byte[] data, int offset) => data[offset] | (data[offset + 1] << 8);

    [GeneratedRegex(@"\$[0-9A-Fa-f]+")]
    private static partial Regex HexNumber();
}
