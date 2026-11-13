// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text;

namespace Retrocore.Pascal;

public static partial class PcodeSourceWriter
{
    // A p-code procedure: its p-codes from where the one before it ended, its jump table, then its words below its
    // attributes (data size, parameter size, exit and entry) and the attributes (number and lexical level).
    private static void PcodeProcedure(List<string> lines, byte[] code, int number, int start, int attributes)
    {
        int entry = (attributes - 2) - Word(code, attributes - 2);
        int exit = (attributes - 4) - Word(code, attributes - 4);

        // A p-code procedure's attributes give its own number, and its entry and exit are in its code; a system
        // stub's procedures, which are elsewhere, have none of that.
        if (code[attributes] != number || entry < start || entry >= attributes || exit < entry || exit >= attributes)
        {
            throw new InvalidDataException($"procedure {number}'s attributes do not describe code in the segment.");
        }

        Dictionary<int, string> labels = new() { [entry] = "Entry" };
        HashSet<int> inline = [];
        List<(int At, int End, string? Text, Func<string>? Late)> items = [];
        int tableLow = attributes - 8;
        List<int> starts = [];
        HashSet<int> startSet = [];
        int at = start;
        while (at < tableLow)
        {
            // An odd byte before the table, which starts on a word, is padding.
            if (at + 1 == tableLow && (at & 1) != 0) { break; }

            int instruction = at;
            byte op = code[at++];
            PcodeOpcode opcode = Pcode.Opcode(op);
            string mnemonic = op == 210 ? "NOP210" : opcode.Mnemonic;
            bool long_ = false;
            string? text = null;
            Func<string>? late = null;
            switch (opcode.Operands)
            {
                case PcodeOperands.None when op < 128:
                    text = $"SLDC {op}";
                    break;
                case PcodeOperands.None:
                    text = mnemonic;
                    break;
                case PcodeOperands.Byte:
                    text = $"{mnemonic} {code[at++]}";
                    break;
                case PcodeOperands.StandardProcedure:
                    {
                        int number2 = code[at++];
                        string name = Pcode.StandardProcedure(number2);
                        text = char.IsAsciiDigit(name[0]) ? $"{mnemonic}N {number2}" : $"{mnemonic} {name}";
                        break;
                    }

                case PcodeOperands.Big:
                    text = $"{mnemonic} {Invariant(Big(code, ref at, ref long_))}";
                    break;
                case PcodeOperands.LevelBig or PcodeOperands.SegmentBig:
                    {
                        int level = code[at++];
                        text = $"{mnemonic} {level}, {Invariant(Big(code, ref at, ref long_))}";
                        break;
                    }

                case PcodeOperands.TwoBytes:
                    text = $"{mnemonic} {code[at]}, {code[at + 1]}";
                    at += 2;
                    break;
                case PcodeOperands.Word:
                    text = $"{mnemonic} {Invariant((short)Word(code, at))}";
                    at += 2;
                    break;
                case PcodeOperands.Jump:
                    {
                        int jump = (sbyte)code[at++];
                        if (jump >= 0)
                        {
                            int target = at + jump;
                            labels.TryAdd(target, Label(target));
                            late = () => $"{mnemonic} {Reference(target)}";
                        }
                        else
                        {
                            int tableEntry = attributes + jump;
                            tableLow = Math.Min(tableLow, tableEntry);
                            text = $"{mnemonic}T T{tableEntry:X4}";
                        }

                        break;
                    }

                case PcodeOperands.String or PcodeOperands.Bytes:
                    {
                        int count = code[at++];
                        ReadOnlySpan<byte> characters = code.AsSpan(at, count);
                        at += count;
                        text = count > 0 && Printable(characters) ? $"{mnemonic} \"{Encoding.ASCII.GetString(characters)}\"" : null;
                        long_ = text is null;
                        break;
                    }

                case PcodeOperands.Words:
                    {
                        int count = code[at++];
                        int pad = (at & 1) != 0 ? code[at++] : 0;
                        string words = string.Join(", ", Enumerable.Range(0, count).Select(index => Hex4(Word(code, at + (index * 2)))));
                        at += count * 2;
                        text = count == 0 ? $"{mnemonic} 0, ${pad:X2}" : $"{mnemonic} {count}, ${pad:X2}\n        .word {words}";
                        break;
                    }

                case PcodeOperands.CaseJump:
                    {
                        int pad = (at & 1) != 0 ? code[at++] : 0;
                        short low = (short)Word(code, at);
                        short high = (short)Word(code, at + 2);
                        at += 4;
                        int ujp = at;
                        int jump = (sbyte)code[at + 1];
                        at += 2;
                        labels.TryAdd(ujp, Label(ujp));
                        inline.Add(ujp);
                        string? otherwise = null;
                        int outside = at + jump;
                        if (jump >= 0)
                        {
                            labels.TryAdd(outside, Label(outside));
                        }
                        else
                        {
                            tableLow = Math.Min(tableLow, attributes + jump);
                            otherwise = $"UJPT T{attributes + jump:X4}";
                        }

                        List<int> arms = [];
                        for (int index = low; index <= high; index++)
                        {
                            int arm = at - Word(code, at);
                            arms.Add(arm);
                            labels.TryAdd(arm, Label(arm));
                            at += 2;
                        }

                        late = () =>
                        {
                            StringBuilder builder = new($"{mnemonic} {low}, {high}, ${pad:X2}\n{labels[ujp]}: {otherwise ?? $"UJP {Reference(outside)}"}");
                            foreach (int arm in arms)
                            {
                                builder.Append($"\n        .word * - {Operand(Reference(arm))}");
                            }

                            return builder.ToString();
                        };

                        break;
                    }

                case PcodeOperands.Comparison:
                    {
                        int type = code[at++];
                        text = type switch
                        {
                            2 or 4 or 6 or 8 => mnemonic + s_comparisons[type],
                            10 or 12 => $"{mnemonic}{(type == 10 ? "BYT" : "WORD")} {Invariant(Big(code, ref at, ref long_))}",
                            _ => null
                        };

                        long_ |= text is null;
                        break;
                    }

                default:
                    break;
            }

            // A form the macros would write otherwise, such as a two-byte number below 128, is written as its bytes.
            if (long_) { (text, late) = (null, null); }
            items.Add((instruction, at, text, late));
        }

        // The jump table's words start on a word boundary; a byte before them is padding.
        int first = at + (at & 1);
        if (first > tableLow) { first = tableLow; }
        List<(int At, int Target)> entries = [];
        for (int word = first; word < attributes - 8; word += 2)
        {
            int target = word - Word(code, word);
            if (target < start || target >= attributes)
            {
                throw new InvalidDataException($"procedure {number}'s jump table leads outside it.");
            }

            labels.TryAdd(target, Label(target));
            entries.Add((word, target));
        }

        starts.AddRange(items.Select(item => item.At));
        starts.Add(at);
        startSet.UnionWith(starts);
        foreach (int target in labels.Keys.Where(target => !startSet.Contains(target) && !inline.Contains(target) && target != entry).ToList())
        {
            labels.Remove(target);
        }

        lines.Add($".scope P{number}");
        Dictionary<string, string> texts = [];
        foreach ((int itemAt, int end, string? text, Func<string>? late) in items)
        {
            if (late is not null) { texts[Invariant(itemAt)] = late(); }
        }

        // Every reference is worked out before anything is written, so the labels it needs are written.
        List<string> table = [.. entries.Select(entry2 => $"T{entry2.At:X4}:  .word * - {Operand(Reference(entry2.Target))}")];

        foreach ((int itemAt, int end, string? text, Func<string>? _) in items)
        {
            if (labels.TryGetValue(itemAt, out string? label)) { lines.Add($"{label}:"); }
            if (itemAt == exit && exit != entry) { lines.Add("Exit:"); }
            string? written = text ?? (texts.TryGetValue(Invariant(itemAt), out string? delayed) ? delayed : null);
            if (written is null)
            {
                lines.Add(Bytes(code.AsSpan(itemAt, end - itemAt)));
            }
            else
            {
                // The first line is the p-code; any after it are written in full.
                string[] parts = written.Split('\n');
                lines.Add($"        {parts[0]}");
                lines.AddRange(parts.Skip(1));
            }
        }

        if (labels.TryGetValue(at, out string? last)) { lines.Add($"{last}:"); }
        if (first > at) { lines.Add(Bytes(code.AsSpan(at, first - at))); }
        lines.AddRange(table);

        lines.Add($"        .word {Word(code, attributes - 8)}, {Word(code, attributes - 6)}       ; data and parameter sizes");
        lines.Add($"        .word * - {(exit != entry ? "Exit" : "Entry")}, * - Entry");
        lines.Add($"Attributes: .byte {code[attributes]}, {code[attributes + 1]}       ; procedure {code[attributes]}, lexical level {(sbyte)code[attributes + 1]}");
        lines.Add(".endscope");

        // A target that is not where a p-code starts, as an XJP's missing cases are, is named from the one before it.
        string Reference(int target)
        {
            if (labels.TryGetValue(target, out string? name) && (startSet.Contains(target) || inline.Contains(target) || target == entry))
            {
                return name;
            }

            int index = starts.BinarySearch(target);
            if (index < 0) { index = ~index - 1; }
            if (index < 0) { return $"Entry - {entry - target}"; }
            int start = starts[index];
            labels.TryAdd(start, Label(start));
            return $"{labels[start]} + {target - start}";
        }
    }

    private static string Label(int offset) => $"L{offset:X4}";

    // A reference as the operand of a subtraction: in parentheses when it is a sum, such as L0565 + 33.
    private static string Operand(string reference) => reference.Contains(' ', StringComparison.Ordinal) ? $"({reference})" : reference;
}
