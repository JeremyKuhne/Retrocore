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
///   EXTERNAL; the Linker matches the two by name. Each relocated operand or word is written as what it is relative to,
///   and the Assembler lists it again, in the order the code has it: a place in the procedure by label; another
///   procedure's entry by its name, and another place in one by a label that procedure defines (<c>.REF</c> and
///   <c>.DEF</c>); one of the host's globals by its name (<c>.PUBLIC</c>); and a place in the interpreter as
///   <c>.INTERP</c> and its offset, which only Apple Pascal 1.2's Assembler relocates, as its interpreter moves. An
///   absolute operand below $100 of a three-byte instruction is written as its bytes, as the Assembler would make it
///   zero page.
///  </para>
///  <para>
///   Code is decoded from the procedure's entry, its branches' targets, and the places a JSR or JMP reaches, from it or
///   from another procedure; the rest is data. Not written: data before a procedure's entry, which the Assembler starts
///   at its <c>.PROC</c>; and a segment-relative word to a place no procedure written here has, or to its own
///   procedure. Each is noted.
///  </para>
/// </remarks>
public static partial class PascalAssemblyWriter
{
    // Names the Assembler reads as other than a label.
    private static readonly HashSet<string> s_reserved = new(StringComparer.OrdinalIgnoreCase)
    {
        "A", "X", "Y", "ADC", "AND", "ASL", "BCC", "BCS", "BEQ", "BIT", "BMI", "BNE", "BPL", "BRK", "BVC", "BVS", "CLC",
        "CLD", "CLI", "CLV", "CMP", "CPX", "CPY", "DEC", "DEX", "DEY", "EOR", "INC", "INX", "INY", "JMP", "JSR", "LDA",
        "LDX", "LDY", "LSR", "NOP", "ORA", "PHA", "PHP", "PLA", "PLP", "ROL", "ROR", "RTI", "RTS", "SBC", "SEC", "SED",
        "SEI", "STA", "STX", "STY", "TAX", "TAY", "TSX", "TXA", "TXS", "TYA"
    };

    // The lists below a procedure's entry pointer, in the order they are read down from it.
    private const int BaseList = 0;
    private const int SegmentList = 1;
    private const int ProcedureList = 2;
    private const int InterpreterList = 3;

    // JSR and JMP, whose targets are code.
    private const byte Jsr = 0x20;
    private const byte Jmp = 0x4C;

    /// <summary>
    ///  Writes a segment's assembled procedures.
    /// </summary>
    /// <param name="segment">The segment.</param>
    /// <param name="procedures">Its assembled procedures to write, in order.</param>
    /// <param name="globals">
    ///  Names a base-relative word's value as the host's global and the bytes into it, for <c>.PUBLIC</c>; null
    ///  without a host. It returns null where no global has the word.
    /// </param>
    /// <returns>The source, and what it could not write as the code has it.</returns>
    public static PascalAssemblySource Write(
        PascalSegment segment,
        IReadOnlyList<PascalAssembledProcedure> procedures,
        Func<int, (string Name, int Bytes)?>? globals = null)
    {
        ArgumentNullException.ThrowIfNull(segment);
        ArgumentNullException.ThrowIfNull(procedures);
        List<string> notes = [];
        List<Parsed> parsed = [];
        foreach (PascalAssembledProcedure procedure in procedures)
        {
            if (segment.Procedure(procedure.Number) is { IsNative: true } code)
            {
                parsed.Add(Read(segment, code, procedure, notes));
            }
            else
            {
                notes.Add($"{segment.Name}.{procedure.Number} is not assembled code.");
            }
        }

        // Another procedure's JSR or JMP through the segment reaches code too.
        byte[] bytes = segment.Code;
        foreach (Parsed procedure in parsed)
        {
            foreach ((int word, int list) in procedure.Relocated)
            {
                int target = Word(bytes, word);
                if (list == SegmentList
                    && word > 0
                    && bytes[word - 1] is Jsr or Jmp
                    && parsed.FirstOrDefault(other => other != procedure && other.Entry <= target && target < other.Bottom) is { } owner)
                {
                    owner.Roots.Add(target);
                }
            }
        }

        foreach (Parsed procedure in parsed) { Decode(bytes, procedure); }
        Link(segment, parsed, globals, notes);
        List<string> lines = [];
        foreach (Parsed procedure in parsed) { Emit(lines, segment, procedure); }
        lines.Add(Line(label: null, ".END"));
        return new PascalAssemblySource(string.Join("\n", lines) + "\n", notes);
    }

    // Reads a procedure's entry and relocation lists.
    private static Parsed Read(PascalSegment segment, PascalProcedure procedure, PascalAssembledProcedure written, List<string> notes)
    {
        byte[] code = segment.Code;
        int attributes = procedure.Attributes;
        Parsed parsed = new(procedure, written) { Entry = (attributes - 2) - Word(code, attributes - 2) };

        // The lists, read down from the entry pointer: each a count, then self-relative pointers to the words.
        int pointer = attributes - 2;
        for (int list = 0; list < 4; list++)
        {
            pointer -= 2;
            int count = Word(code, pointer);
            for (int item = 0; item < count; item++)
            {
                pointer -= 2;
                parsed.Relocated[pointer - Word(code, pointer)] = list;
            }
        }

        parsed.Bottom = pointer;
        parsed.Roots.Add(parsed.Entry);
        parsed.Used.Add(parsed.Name);
        int start = segment.Procedures
            .Where(other => other.Attributes < attributes)
            .Select(other => other.Attributes + 2)
            .DefaultIfEmpty(0)
            .Max();

        if (parsed.Entry > start && code.AsSpan(start, parsed.Entry - start).ContainsAnyExcept((byte)0))
        {
            notes.Add($"{segment.Name}.{procedure.Index} has data before its entry, which the source leaves out.");
        }

        return parsed;
    }

    // Decodes 6502 instructions from each root until data, which a relocated word, an instruction that does not decode
    // or overlaps one decoded, or the end of a routine marks; a branch's target, and a JSR's or JMP's in the procedure,
    // is a root too. Then the places the code refers to are its targets.
    private static void Decode(byte[] code, Parsed procedure)
    {
        Queue<int> roots = new(procedure.Roots.Order());
        while (roots.TryDequeue(out int root))
        {
            int at = root;
            while (at >= procedure.Entry && at < procedure.Bottom && !procedure.Starts.ContainsKey(at) && procedure.Within(at) < 0)
            {
                if (at != root && procedure.Relocated.ContainsKey(at)) { break; }
                if (!Disassembler.TryDecode(code.AsSpan(at, procedure.Bottom - at), (ushort)at, ProcessorVariant.Mos6502, out DisassembledInstruction instruction)
                    || instruction.IsUndocumented
                    || Overlaps(at, instruction.Size))
                {
                    break;
                }

                procedure.Starts[at] = instruction;
                if (instruction.RelativeTarget is { } branch)
                {
                    procedure.Targets.Add(branch);
                    roots.Enqueue(branch);
                }
                else if (instruction.Size == 3
                    && code[at] is Jsr or Jmp
                    && procedure.Relocated.TryGetValue(at + 1, out int list)
                    && list == ProcedureList)
                {
                    roots.Enqueue(procedure.Entry + Word(code, at + 1));
                }

                at += instruction.Size;
                if (instruction.Flow is DisassemblyFlow.Return or DisassemblyFlow.Jump or DisassemblyFlow.IndirectJump or DisassemblyFlow.Break)
                {
                    break;
                }
            }
        }

        foreach ((int word, int list) in procedure.Relocated)
        {
            if (list == ProcedureList) { procedure.Targets.Add(procedure.Entry + Word(code, word)); }
        }

        // An instruction overlaps one decoded, or holds a relocated word other than its operand.
        bool Overlaps(int at, int size)
        {
            for (int next = at + 1; next < at + size; next++)
            {
                bool operand = size == 3 && next == at + 1;
                if (procedure.Starts.ContainsKey(next) || (procedure.Relocated.ContainsKey(next) && !operand))
                {
                    return true;
                }
            }

            return false;
        }
    }

    // The names words other than procedure-relative ones take: a segment-relative word another procedure's entry by its
    // name, .REF, or a place in it by a label it defines, .DEF; a base-relative word the host's global, .PUBLIC; and an
    // interpreter-relative word .INTERP and its offset.
    private static void Link(PascalSegment segment, List<Parsed> procedures, Func<int, (string Name, int Bytes)?>? globals, List<string> notes)
    {
        byte[] code = segment.Code;
        HashSet<string> global = new(procedures.Select(procedure => procedure.Name), StringComparer.Ordinal);
        Dictionary<int, string> defined = [];
        foreach (Parsed procedure in procedures)
        {
            string key = $"{segment.Name}.{procedure.Code.Index}";
            foreach ((int word, int list) in procedure.Relocated.OrderBy(pair => pair.Key))
            {
                int value = Word(code, word);
                switch (list)
                {
                    case InterpreterList:
                        procedure.Expressions[word] = value == 0 ? ".INTERP" : $".INTERP+{Hex(value)}";
                        break;
                    case BaseList:
                        if (globals?.Invoke(value) is ({ } name, int bytes) && Label(name) is { } shared)
                        {
                            procedure.Publics.Add(shared);
                            procedure.Used.Add(shared);
                            procedure.Expressions[word] = bytes == 0 ? shared : $"{shared}+{Hex(bytes)}";
                        }
                        else
                        {
                            notes.Add($"{key} refers to the host's globals at ${value:X4}, which no global of the host names.");
                        }

                        break;
                    case SegmentList:
                        if (Segment(procedure, value) is { } reference) { procedure.Expressions[word] = reference; }
                        break;
                    default:
                        break;
                }
            }

            string? Segment(Parsed from, int target)
            {
                Parsed? owner = procedures.FirstOrDefault(other => other.Entry <= target && target < other.Bottom);
                if (owner is null)
                {
                    notes.Add($"{key} refers to ${target:X4} in its segment, in no procedure written here.");
                    return null;
                }

                if (owner == from)
                {
                    notes.Add($"{key} refers to itself through the segment, at ${target:X4}, which the source writes as a number.");
                    return null;
                }

                // Its entry is its name; another place a label it defines, from where an instruction there starts.
                if (target == owner.Entry)
                {
                    from.Referred.Add(owner.Name);
                    return owner.Name;
                }

                int container = owner.Within(target) is int start and >= 0 ? start : target;
                if (!defined.TryGetValue(container, out string? name))
                {
                    string? given = owner.Written.Names.TryGetValue(container - owner.Entry, out string? hint) ? Label(hint) : null;
                    name = given is not null && !global.Contains(given) ? given : $"D{container:X4}";
                    global.Add(name);
                    defined[container] = name;
                    owner.Defined.Add(name);
                    owner.Labels[container] = name;
                    owner.Used.Add(name);
                }

                from.Referred.Add(name);
                from.Used.Add(name);
                return container == target ? name : $"{name}+{Hex(target - container)}";
            }
        }
    }

    // A name as the Assembler takes a label: letters and digits from a letter, its eight letters, and no register or
    // mnemonic; null where it makes none.
    private static string? Label(string name)
    {
        string letters = new([.. name.Where(char.IsAsciiLetterOrDigit)]);
        string significant = Significant(letters);
        bool label = significant.Length > 0 && char.IsAsciiLetter(significant[0]) && !s_reserved.Contains(significant);
        return label ? significant : null;
    }

    private static string Significant(string name)
    {
        string upper = name.ToUpperInvariant();
        return upper.Length > 8 ? upper[..8] : upper;
    }

    // Writes a procedure: its heading, the names it shares, then its code and data from its entry.
    private static void Emit(List<string> lines, PascalSegment segment, Parsed procedure)
    {
        byte[] code = segment.Code;
        int entry = procedure.Entry;
        PascalAssembledProcedure written = procedure.Written;
        Dictionary<int, string> labels = procedure.Labels;
        Dictionary<int, string> inside = procedure.Inside;

        // Labels: the hints' names where they make labels, else L and the offset from the entry; a target inside an
        // instruction, or inside a relocated word of data, is named from where that starts.
        foreach (int target in procedure.Targets.Order())
        {
            int container = procedure.Within(target);
            if (container < 0
                && procedure.Relocated.ContainsKey(target - 1)
                && !procedure.Starts.ContainsKey(target - 1)
                && procedure.Within(target - 1) < 0)
            {
                container = target - 1;
            }

            if (container >= 0)
            {
                inside[target] = $"{Local(container)}+{Hex(target - container)}";
            }
            else if (target < entry || target >= procedure.Bottom)
            {
                inside[target] = target < entry ? $"{Local(entry)}-{Hex(entry - target)}" : $"{Local(entry)}+{Hex(target - entry)}";
            }
            else
            {
                Local(target);
            }
        }

        string Local(int offset)
        {
            if (labels.TryGetValue(offset, out string? label)) { return label; }

            string fallback = $"L{offset - entry:X4}";
            label = written.Names.TryGetValue(offset - entry, out string? given) ? Label(given) ?? fallback : fallback;
            if (procedure.Used.Contains(label)) { label = fallback; }
            procedure.Used.Add(label);
            labels[offset] = label;
            return label;
        }

        string Reference(int target) => inside.TryGetValue(target, out string? within) ? within : Local(target);

        if (written.Comment is { } about) { lines.Add($"; {about}"); }
        string directive = written.IsFunction ? ".FUNC" : ".PROC";
        string parameters = written.ParameterWords > 0 ? $",{written.ParameterWords}" : "";
        lines.Add(Line(label: null, $"{directive,-8}{procedure.Name}{parameters}"));
        Names(".DEF", procedure.Defined);
        Names(".REF", procedure.Referred);
        Names(".PUBLIC", procedure.Publics);

        // Code and data, in the order they are, to the relocation lists, which the Assembler writes.
        int position = entry;
        while (position < procedure.Bottom)
        {
            if (written.Comments.TryGetValue(position - entry, out string? text)) { lines.Add($"; {text}"); }
            if (procedure.Starts.TryGetValue(position, out DisassembledInstruction instruction))
            {
                lines.Add(Line(labels.GetValueOrDefault(position), Instruction(position, instruction)));
                position += instruction.Size;
                continue;
            }

            if (procedure.Relocated.TryGetValue(position, out int list)
                && position + 1 < procedure.Bottom
                && Relocated(position, list) is { } word)
            {
                lines.Add(Line(labels.GetValueOrDefault(position), $".WORD   {word}"));
                position += 2;
                continue;
            }

            int next = position + 1;
            while (next < procedure.Bottom
                && next - position < 8
                && !procedure.Relocated.ContainsKey(next)
                && !procedure.Starts.ContainsKey(next)
                && !labels.ContainsKey(next))
            {
                next++;
            }

            lines.Add(Line(labels.GetValueOrDefault(position), $".BYTE   {Bytes(code, position, next)}"));
            position = next;
        }

        void Names(string shares, SortedSet<string> names)
        {
            if (names.Count > 0) { lines.Add(Line(label: null, $"{shares,-8}{string.Join(",", names)}")); }
        }

        // A relocated word's expression: a label for a procedure-relative one, as Link names the others.
        string? Relocated(int word, int list) => list == ProcedureList
            ? Reference(entry + Word(code, word))
            : procedure.Expressions.GetValueOrDefault(word);

        // An instruction in the Assembler's syntax: hexadecimal without $, a relocated operand by its label or name.
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
            else if (instruction.Size == 3
                && procedure.Relocated.TryGetValue(instructionAt + 1, out int list)
                && Relocated(instructionAt + 1, list) is { } expression)
            {
                operand = HexNumber().Replace(operand, _ => expression, 1);
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

            // The Assembler writes an indirect JMP's operand after @: it takes no parentheses there.
            if (instruction.Flow is DisassemblyFlow.IndirectJump && operand.StartsWith('(') && operand.EndsWith(')'))
            {
                operand = $"@{operand[1..^1]}";
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
