// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;

namespace Retrocore.Pascal;

public static partial class PcodeSourceWriter
{
    // What a relocation list's words are relative to, in the order the lists are below an assembled procedure's entry
    // pointer: the interpreter's globals (base), the segment, the procedure, and the interpreter.
    private static readonly string[] s_relocations = ["base", "segment", "procedure", "interpreter"];

    // An assembled procedure: 6502 code from its entry, its data, its four relocation lists, its entry pointer and its
    // attributes (procedure 0). An operand the procedure-relative list names is an offset from the entry.
    private static void NativeProcedure(List<string> lines, byte[] code, int number, int start, int attributes)
    {
        int entry = (attributes - 2) - Word(code, attributes - 2);

        // The lists, read down from the entry pointer: each a count, then self-relative pointers to the words.
        Dictionary<int, int> relocated = [];
        List<List<int>> lists = [];
        int pointer = attributes - 2;
        for (int list = 0; list < 4; list++)
        {
            pointer -= 2;
            int count = Word(code, pointer);
            List<int> words = [];
            for (int item = 0; item < count; item++)
            {
                pointer -= 2;
                int word = pointer - Word(code, pointer);
                words.Add(word);
                relocated[word] = list;
            }

            lists.Add(words);
        }

        int bottom = pointer;
        if (entry < start || entry >= bottom)
        {
            throw new InvalidDataException($"procedure {number}'s entry is outside its code.");
        }


        // Its code: 6502 instructions from the entry until data, which a relocated word, an instruction that does
        // not decode, or the end of a routine that no branch goes past marks.
        Dictionary<int, string> labels = new() { [entry] = "Entry" };
        List<(int At, DisassembledInstruction Instruction)> instructions = [];
        int at = entry;
        HashSet<int> targets = [];
        while (at < bottom)
        {
            if (at != entry && relocated.ContainsKey(at)) { break; }
            if (!TryDecode(code, at, bottom, out DisassembledInstruction instruction)
                || instruction.IsUndocumented
                || at + instruction.Size > bottom)
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
        HashSet<int> starts = [.. instructions.Select(item => item.At)];
        Dictionary<int, int> sizes = instructions.ToDictionary(item => item.At, item => item.Instruction.Size);

        // Labels: branch targets, the targets of procedure-relative operands and words, and each relocated operand's
        // instruction.
        // A target inside an instruction, or inside a relocated word of data, is named from where that starts.
        Dictionary<int, string> inside = [];
        foreach (int target in targets) { Name(target); }
        foreach ((int word, int list) in relocated)
        {
            if (list == 2 && word + 1 < code.Length && entry + Word(code, word) is int target && target >= start && target < bottom)
            {
                Name(target);
            }

            int instructionAt = OperandOf(word);
            labels.TryAdd(instructionAt, Label(instructionAt));
        }

        void Name(int target)
        {
            int container = instructions
                .Where(item => item.At < target && target < item.At + item.Instruction.Size)
                .Select(item => item.At)
                .DefaultIfEmpty(-1)
                .First();

            if (container < 0 && target > 0 && relocated.ContainsKey(target - 1) && !starts.Contains(target - 1))
            {
                container = target - 1;
            }

            if (container < 0)
            {
                labels.TryAdd(target, Label(target));
                return;
            }

            labels.TryAdd(container, Label(container));
            inside[target] = $"{labels[container]} + {target - container}";
        }

        lines.Add("        .cpu Mos6502");
        lines.Add($";; Procedure {number}, assembled: 6502 code whose relocated operands are offsets from Entry.");
        lines.Add($".scope P{number}");
        DataWithWords(start, entry);
        foreach ((int instructionAt, DisassembledInstruction instruction) in instructions)
        {
            if (labels.TryGetValue(instructionAt, out string? label)) { lines.Add($"{label}:"); }
            lines.Add($"        {Instruction(instructionAt, instruction)}");
        }

        DataWithWords(codeEnd, bottom);

        // The relocation lists, the last read lowest: each list's words, then its count.
        for (int list = 3; list >= 0; list--)
        {
            List<int> words = lists[list];
            for (int item = words.Count - 1; item >= 0; item--)
            {
                int word = words[item];
                int instructionAt = OperandOf(word);
                lines.Add(instructionAt == word ? $"        .word * - {Operand(Reference(word))}" : $"        .word * - ({labels[instructionAt]} + 1)");
            }

            lines.Add($"        .word {words.Count}                       ; {s_relocations[list]}-relative words");
        }

        lines.Add("        .word * - Entry");
        lines.Add($"Attributes: .byte 0, {code[attributes + 1]}       ; procedure 0: assembled");
        lines.Add(".endscope");
        lines.Add("        .cpu Pcode");

        // The instruction whose operand word a relocated word is, or the word itself when it is data.
        int OperandOf(int word) => sizes.TryGetValue(word - 1, out int size) && size == 3 ? word - 1 : word;

        // An instruction, its branch target or procedure-relative operand by label; absolute operands stay absolute.
        string Instruction(int instructionAt, DisassembledInstruction instruction)
        {
            string text = instruction.ToString();
            int space = text.IndexOf(' ', StringComparison.Ordinal);
            string mnemonic = (space < 0 ? text : text[..space]).ToLowerInvariant();
            string operand = space < 0 ? "" : text[(space + 1)..];
            if (instruction.RelativeTarget is { } branch)
            {
                string label = Reference(branch);
                operand = HexOperand().Replace(operand, _ => label, 1);
            }
            else if (instruction.Size == 3 && relocated.TryGetValue(instructionAt + 1, out int list))
            {
                int value = Word(code, instructionAt + 1);
                string expression = Relocated(list, value);
                operand = HexOperand().Replace(operand, _ => expression, 1);
                if (!operand.StartsWith('(')) { mnemonic += ".w"; }
            }
            else if (instruction.Size == 3 && Word(code, instructionAt + 1) < 0x100 && !operand.StartsWith('('))
            {
                mnemonic += ".w";
            }

            operand = operand.Replace(",X", ",x", StringComparison.Ordinal).Replace(",Y", ",y", StringComparison.Ordinal);
            if (operand == "A") { operand = "a"; }
            return operand.Length == 0 ? mnemonic : $"{mnemonic} {operand}";
        }

        // A relocated word's value: a label for a procedure-relative offset inside the procedure.
        string Relocated(int list, int value)
        {
            if (list != 2) { return Hex4(value); }
            if (inside.TryGetValue(entry + value, out string? within)) { return $"{within} - Entry"; }
            return labels.TryGetValue(entry + value, out string? target) ? $"{target} - Entry" : Hex4(value);
        }

        string Reference(int target)
        {
            if (inside.TryGetValue(target, out string? within)) { return within; }
            if (labels.TryGetValue(target, out string? name)) { return name; }
            return target < entry ? $"Entry - {entry - target}" : $"Entry + {target - entry}";
        }

        // Data between two offsets, with labels, and a relocated word as its value's expression.
        void DataWithWords(int from, int to)
        {
            int position = from;
            while (position < to)
            {
                if (relocated.TryGetValue(position, out int list) && position + 1 < to)
                {
                    if (labels.TryGetValue(position, out string? wordLabel)) { lines.Add($"{wordLabel}:"); }
                    lines.Add($"        .word {Relocated(list, Word(code, position))}");
                    position += 2;
                    continue;
                }

                int next = position + 1;
                while (next < to && !relocated.ContainsKey(next) && !labels.ContainsKey(next)) { next++; }
                Data(lines, code.AsSpan(position, next - position), position, labels);
                position = next;
            }
        }
    }
}
