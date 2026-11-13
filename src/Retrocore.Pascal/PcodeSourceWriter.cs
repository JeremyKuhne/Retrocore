// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;
using Retrocore.Assembler;
using Retrocore.Cpu.M6502;
using Retrocore.Media;

namespace Retrocore.Pascal;

/// <summary>
///  Writes a code file as source for the native assembler that assembles back to the same bytes: p-code with
///  <c>Pcode.asm</c>'s macros under <c>.cpu Pcode</c>, and assembled procedures as 6502 code under <c>.cpu Mos6502</c>.
/// </summary>
/// <remarks>
///  <para>
///   The source lays out the whole file from address 0: the segment dictionary in block 0, then each segment from its
///   block. A segment and each of its procedures is a scope; jumps go to labels, and the self-relative words of jump
///   tables, attributes and procedure dictionaries are label arithmetic (<c>.word * - Label</c>), so code can move.
///   A backward jump, or one too far for a byte, goes through the procedure's jump table: <c>UJPT T0542</c> names
///   the table's word. The byte the Compiler skips to put an operand on a word is written as it is, since it holds
///   whatever its buffer had.
///  </para>
///  <para>
///   An assembled procedure's operands that its procedure-relative relocation list names are offsets from its entry,
///   written <c>Label - Entry</c> with <c>.w</c> so they stay absolute, and its relocation lists name those operands
///   by label. A segment the writer cannot read, such as a system stub whose procedures are elsewhere, is written as
///   data, with a note.
///  </para>
/// </remarks>
public static partial class PcodeSourceWriter
{
    private const int BlockSize = 512;
    private static readonly string[] s_comparisons = ["", "", "REAL", "", "STR", "", "BOOL", "", "POWR"];

    /// <summary>
    ///  Writes a code file as source.
    /// </summary>
    /// <param name="data">The code file's contents.</param>
    /// <param name="include">The include that defines the p-code macros, as <c>.include</c> names it.</param>
    /// <returns>The source, and notes on what it writes as data.</returns>
    /// <exception cref="InvalidDataException">The file is not a code file.</exception>
    public static PcodeSource Write(ReadOnlySpan<byte> data, string include = "<Pascal/Pcode.asm>") =>
        Write(data, new PcodeSourceOptions { Include = include ?? throw new ArgumentNullException(nameof(include)) });

    /// <summary>
    ///  Writes a code file as source, naming its parts from a library, a listing and given names.
    /// </summary>
    /// <param name="data">The code file's contents.</param>
    /// <param name="options">The include, and where names come from.</param>
    /// <returns>The source, and notes on what it writes as data.</returns>
    /// <exception cref="InvalidDataException">The file is not a code file.</exception>
    public static PcodeSource Write(ReadOnlySpan<byte> data, PcodeSourceOptions options)
    {
        ArgumentNullException.ThrowIfNull(options);
        PascalCodeFile file = PascalCodeFile.Read(data);
        PcodeNaming naming = new(options, file);
        List<string> lines = [];
        List<string> notes = [];
        byte[] bytes = data.ToArray();
        lines.Add($"        .include {options.Include}");
        lines.Add("");
        int units = lines.Count;
        Dictionary();

        int at = BlockSize;
        foreach (PascalSegment segment in file.Segments.Where(segment => segment.Block != 0 && segment.Length != 0).OrderBy(segment => segment.Block))
        {
            int start = segment.Block * BlockSize;
            if (start < at) { throw new InvalidDataException($"Segment {segment.Name} overlaps the one before it."); }
            Data(lines, bytes.AsSpan(at, start - at), at, labels: null);

            int mark = lines.Count;
            try
            {
                Segment(lines, bytes, segment, naming);
            }
            catch (InvalidDataException exception)
            {
                lines.RemoveRange(mark, lines.Count - mark);
                notes.Add($"Segment {segment.Slot} ({segment.Name}) is written as data: {exception.Message}");
                lines.Add($";; Segment {segment.Slot}, {segment.Name}, as data: {exception.Message}");
                lines.Add($"Segment{segment.Slot}:");
                Data(lines, bytes.AsSpan(start, segment.Length), start, labels: null);
                lines.Add($"Segment{segment.Slot}End:");
                int end = start + segment.Length;
                Data(lines, bytes.AsSpan(end, Math.Min((BlockSize - (segment.Length % BlockSize)) % BlockSize, bytes.Length - end)), end, labels: null);
            }

            // A segment's source ends with its padding to the end of its block.
            at = Math.Min(bytes.Length, start + segment.Length + ((BlockSize - (segment.Length % BlockSize)) % BlockSize));
        }

        Data(lines, bytes.AsSpan(at), at, labels: null);

        // The units the calls name, each a scope of its segment and its procedures' numbers.
        List<string> definitions = [];
        foreach ((int segmentNumber, PascalUnit unit) in naming.Units)
        {
            string scope = PcodeNaming.UnitScope(unit);
            definitions.Add($";; {unit.UsesName}, a unit in the library: its segment and its procedures' numbers.");
            definitions.Add($".scope {scope}");
            definitions.Add($"Segment = {segmentNumber}");
            definitions.Add("Initialize = 1");
            HashSet<string> named = new(StringComparer.OrdinalIgnoreCase) { "Segment", "Initialize" };
            for (int index = 0; index < unit.Procedures.Count; index++)
            {
                string name = unit.Procedures[index].Name;
                if (named.Add(name)) { definitions.Add($"{name} = {index + 2}"); }
            }

            definitions.Add(".endscope");
            definitions.Add("");
        }

        lines.InsertRange(units, definitions);
        return new PcodeSource(string.Join('\n', lines) + "\n", notes);

        // The segment dictionary: each slot's block and length, its name, kind, interface text, and information.
        void Dictionary()
        {
            lines.Add(";; The segment dictionary: each segment's block and length, name, kind, interface text block and");
            lines.Add(";; information (number, machine type and version), then the intrinsic units the program uses.");
            for (int slot = 0; slot < 16; slot++)
            {
                int block = Word(bytes, slot * 4);
                int length = Word(bytes, (slot * 4) + 2);
                lines.Add(block != 0 && length != 0
                    ? $"        .word Segment{slot} / 512, Segment{slot}End - Segment{slot}"
                    : $"        .word {block}, {length}");
            }

            for (int slot = 0; slot < 16; slot++)
            {
                ReadOnlySpan<byte> name = bytes.AsSpan(64 + (slot * 8), 8);
                lines.Add(Printable(name) ? $"        .byte \"{Encoding.ASCII.GetString(name)}\"" : Bytes(name));
            }

            foreach (int table in (int[])[192, 224])
            {
                lines.Add("        .word " + string.Join(", ", Enumerable.Range(0, 16).Select(slot => Hex4(Word(bytes, table + (slot * 2))))));
            }

            // Each slot's information: its version, machine type and segment number.
            for (int slot = 0; slot < 16; slot++)
            {
                int information = Word(bytes, 256 + (slot * 2));
                int number = information & 0xFF;
                int machine = (information >> 8) & 0xF;
                int version = (information >> 13) & 7;
                PascalSegment? segment = file.Segments.FirstOrDefault(segment => segment.Slot == slot);
                bool exact = ((version << 13) | (machine << 8) | number) == information;
                lines.Add(segment is null || !exact
                    ? $"        .word {Hex4(information)}"
                    : $"        .word ({version} << 13) | ({machine} << 8) | {number}      ; {segment.Name}: version {version}, {(PascalMachineType)machine}, segment {number}, {segment.Kind}");
            }

            Data(lines, bytes.AsSpan(288, BlockSize - 288), 288, labels: null);
        }
    }

    private static void Segment(List<string> lines, byte[] bytes, PascalSegment segment, PcodeNaming naming)
    {
        byte[] code = segment.Code;
        int length = code.Length;
        int count = code[^1];
        int dictionary = length - 2 - (count * 2);
        if (dictionary < 0) { throw new InvalidDataException("its procedure dictionary is larger than the segment."); }

        List<(int Number, int Attributes)> procedures = [];
        for (int number = 1; number <= count; number++)
        {
            int pointer = length - 2 - (number * 2);
            int value = Word(code, pointer);
            if (value == 0) { continue; }
            int attributes = pointer - value;
            if (attributes < 0 || attributes + 2 > dictionary)
            {
                throw new InvalidDataException($"procedure {number}'s attributes are outside it.");
            }

            procedures.Add((number, attributes));
        }

        procedures.Sort((first, second) => first.Attributes.CompareTo(second.Attributes));
        lines.Add("");
        lines.Add($";; Segment {segment.Slot}: {segment.Name}, segment {segment.Number}, {segment.Kind}, {segment.MachineType}.");
        lines.Add($"Segment{segment.Slot}:");
        if (naming.Comment(segment.Name) is { } comment) { lines.Add($";; {comment}"); }
        lines.Add($".scope {naming.Segment(segment)}");
        int start = 0;
        HashSet<int> written = [];
        foreach ((int number, int attributes) in procedures)
        {
            if (attributes < start)
            {
                throw new InvalidDataException($"procedure {number}'s attributes are inside another's code.");
            }

            if (!written.Add(attributes))
            {
                throw new InvalidDataException($"two procedures share attributes at ${attributes:X4}.");
            }

            if (code[attributes] == 0)
            {
                NativeProcedure(lines, code, number, start, attributes, segment, naming);
            }
            else
            {
                PcodeProcedure(lines, code, number, start, attributes, segment, naming);
            }

            start = attributes + 2;
        }

        Data(lines, code.AsSpan(start, dictionary - start), start, labels: null);
        lines.Add(";; The procedure dictionary: a self-relative word to each procedure's attributes, the last first.");
        for (int number = count; number >= 1; number--)
        {
            int value = Word(code, length - 2 - (number * 2));
            lines.Add(value != 0 && procedures.Any(procedure => procedure.Number == number)
                ? $"        .word * - {naming.Procedure(segment, number)}::Attributes"
                : $"        .word {Hex4(value)}");
        }

        lines.Add($"        .byte {code[^2]}, {count}                     ; the segment's number and its procedures");
        lines.Add(".endscope");
        lines.Add($"Segment{segment.Slot}End:");
        int padding = (BlockSize - (length % BlockSize)) % BlockSize;
        int end = (segment.Block * BlockSize) + length;
        Data(lines, bytes.AsSpan(end, Math.Min(padding, bytes.Length - end)), end, labels: null);
    }

    private static int Word(ReadOnlySpan<byte> data, int offset) => data[offset] | (data[offset + 1] << 8);

    private static string Hex4(int value) => $"${value:X4}";

    private static bool Printable(ReadOnlySpan<byte> text)
    {
        foreach (byte value in text)
        {
            if (value is < 32 or >= 127 or (byte)'"') { return false; }
        }

        return true;
    }

    private static string Bytes(ReadOnlySpan<byte> data) =>
        "        .byte " + string.Join(", ", data.ToArray().Select(value => $"${value:X2}"));

    // Bytes as data, a row of up to 12 at a time, printable runs as text, with labels where the labels name offsets.
    private static void Data(List<string> lines, ReadOnlySpan<byte> data, int offset, Dictionary<int, string>? labels)
    {
        int at = 0;
        while (at < data.Length)
        {
            if (labels is not null && labels.TryGetValue(offset + at, out string? label)) { lines.Add($"{label}:"); }

            int end = at;
            while (end < data.Length && Printable(data.Slice(end, 1)) && (labels is null || end == at || !labels.ContainsKey(offset + end)))
            {
                end++;
            }

            if (end - at >= 4)
            {
                lines.Add($"        .byte \"{Encoding.ASCII.GetString(data[at..end])}\"");
                at = end;
                continue;
            }

            end = at + 1;
            while (end < data.Length && end - at < 12 && (labels is null || !labels.ContainsKey(offset + end)))
            {
                int run = end;
                while (run < data.Length && Printable(data.Slice(run, 1))) { run++; }
                if (run - end >= 4) { break; }
                end++;
            }

            lines.Add(Bytes(data[at..end]));
            at = end;
        }
    }

    // A "big" number at an offset: one byte below 128, otherwise two; and whether it took two for a number below 128.
    private static int Big(byte[] code, ref int at, ref bool long_)
    {
        int first = code[at++];
        if (first < 0x80) { return first; }
        int value = ((first & 0x7F) << 8) | code[at++];
        long_ |= value < 0x80;
        return value;
    }

    [GeneratedRegex(@"\$[0-9A-Fa-f]+")]
    private static partial Regex HexOperand();

    private static string Invariant(int value) => value.ToString(CultureInfo.InvariantCulture);

    // The 6502 disassembler's form for an instruction at an offset of a segment, decoded at that offset.
    private static bool TryDecode(byte[] code, int at, int end, out DisassembledInstruction instruction) =>
        Disassembler.TryDecode(code.AsSpan(at, end - at), (ushort)at, ProcessorVariant.Mos6502, out instruction);
}
