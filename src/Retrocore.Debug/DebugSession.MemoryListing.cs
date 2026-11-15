// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Isa;
using System.Globalization;
using System.Text.Json.Nodes;

namespace Retrocore.Debug;

// retro/memory/listing: Retrocore Memory's listing of the bytes as instructions and data.
internal sealed partial class DebugSession
{
    // How far back the listing looks for where an instruction starts.
    private const int ListingLookBack = 32;

    // The most bytes one listing request covers, and one data line shows.
    private const int ListingMaximum = 0x1000;
    private const int DataPerLine = 8;

    /// <summary>
    ///  Answers retro/memory/listing: the instructions and data in a range of a memory view's space.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   Instruction boundaries are ambiguous in memory nobody described, so the listing starts at the nearest known
    ///   boundary at or before <c>address</c>: the start of the debug file's statement there, a label, or one of
    ///   <c>starts</c>, which the editor's Decode from here adds; failing those, <c>address</c> itself. A label or
    ///   start farther back than the short look for a statement still counts, up to 4096 bytes back, so a correction
    ///   holds as the view scrolls. From there a statement the sources mark as data lists as <c>.byte</c>, eight
    ///   bytes a line, and anything else decodes as an instruction, except where one would run over a later
    ///   boundary, which lists as a byte so the boundary starts a line. A start in <c>starts</c> decodes an
    ///   instruction even in data. Lines that end before <c>address</c> are left out.
    ///  </para>
    ///  <para>
    ///   Each line has its <c>address</c>, <c>size</c> and <c>text</c>, its <c>kind</c> (<c>code</c> or <c>data</c>
    ///   from the sources, <c>unknown</c> where none describes it), the <c>label</c> at its address, the
    ///   <c>target</c> an operand names, which the text gives by label where it has one, and the source
    ///   <c>path</c> and <c>line</c>.
    ///  </para>
    /// </remarks>
    private JsonObject MemoryListing(JsonObject args)
    {
        MemoryReference(Required(args, "memoryReference"), out DebugMemoryBank? bank);
        int from = args.Int("address") ?? 0;
        int count = args.Int("count") ?? 256;
        if (from is < 0 or > 0xFFFF || count is < 1 or > ListingMaximum)
        {
            throw new ArgumentOutOfRangeException(nameof(args), "A listing covers 1 to 4096 bytes from $0000-$FFFF.");
        }

        HashSet<int> forced = [];
        if (args["starts"] is JsonArray starts)
        {
            foreach (JsonNode? start in starts)
            {
                if (start?.GetValue<int>() is int value and >= 0 and <= 0xFFFF) { forced.Add(value); }
            }
        }

        IDebugMemory memory = bank is null ? Target : new BankMemory(bank);
        InstructionSet set = bank?.InstructionSet ?? Target.InstructionSet;
        SortedDictionary<int, string> labels = LabelsIn(bank, constants: false);
        SortedDictionary<int, string> names = LabelsIn(bank, constants: true);
        bool Boundary(int address)
        {
            if (forced.Contains(address) || labels.ContainsKey(address)) { return true; }
            return _debug.Position(memory, (ushort)address) is { Start: { } start } && start == address;
        }

        int end = Math.Min(0x10000, from + count);
        int first = -1;
        if (_debug.Position(memory, (ushort)from) is { Start: { } covering } && covering <= from)
        {
            first = covering;
        }

        for (int back = from; back >= Math.Max(0, from - ListingLookBack); back--)
        {
            if (Boundary(back))
            {
                first = Math.Max(first, back);
                break;
            }
        }

        if (first < 0)
        {
            // A Decode from here start or a label farther back still anchors the listing.
            int farthest = Math.Max(0, from - ListingMaximum);
            first = forced.Concat(labels.Keys).Where(start => start >= farthest && start <= from).DefaultIfEmpty(from).Max();
        }

        List<JsonNode?> lines = [];
        Span<byte> bytes = stackalloc byte[LongestInstruction];
        int address = first;
        while (address < end)
        {
            DebugPosition? position = _debug.Position(memory, (ushort)address);
            string kind = position is null ? "unknown" : "code";
            int size;
            string text;
            int? target = null;
            int start = position?.Data == true ? position.Start ?? -1 : -1;
            int length = position?.Size ?? 0;
            if (start >= 0 && address < start + length && !forced.Contains(address))
            {
                // A data statement lists eight bytes a line, a line ending early where a later boundary starts.
                kind = "data";
                size = Math.Min(DataPerLine, Math.Min(start + length, 0x10000) - address);
                for (int index = 1; index < size; index++)
                {
                    if (Boundary(address + index))
                    {
                        size = index;
                        break;
                    }
                }

                text = DataText(memory, address, size);
            }
            else
            {
                int available = Math.Min(LongestInstruction, 0x10000 - address);
                for (int index = 0; index < available; index++)
                {
                    bytes[index] = memory.Peek((ushort)(address + index));
                }

                if (Disassembler.TryDecode(bytes[..available], (ushort)address, set, out DisassembledInstruction instruction)
                    && !RunsOver(address, instruction.Size, Boundary))
                {
                    size = instruction.Size;
                    target = OperandAddress(instruction);
                    text = Named(instruction.ToString(), target, names);
                }
                else
                {
                    size = 1;
                    text = DataText(memory, address, 1);
                }
            }

            if (address + size <= from)
            {
                address += size;
                continue;
            }

            SourceLine? source = position?.Chain[^1];
            lines.Add(new JsonObject
            {
                ["address"] = address,
                ["size"] = size,
                ["text"] = text,
                ["kind"] = kind,
                ["label"] = names.TryGetValue(address, out string? label) ? label : null,
                ["target"] = target,
                ["path"] = source?.Path,
                ["line"] = source?.Line
            });

            address += size;
        }

        return new JsonObject { ["lines"] = lines.ToJsonArray() };
    }

    // Whether an instruction would run over a later boundary, which must start a line of its own.
    private static bool RunsOver(int address, int size, Func<int, bool> boundary)
    {
        for (int index = 1; index < size; index++)
        {
            if (boundary(address + index)) { return true; }
        }

        return false;
    }

    // Bytes as a .byte line.
    private static string DataText(IDebugMemory memory, int address, int size) =>
        ".byte " + string.Join(", ", Enumerable.Range(0, size).Select(index => $"${memory.Peek((ushort)(address + index)):X2}"));

    // The address an instruction's operand names, for going there: a memory or pointer operand, a branch's target,
    // or a postbyte's pointer or PC-relative address; null for values, registers and offsets from a register.
    private static int? OperandAddress(in DisassembledInstruction instruction)
    {
        OperandForm form = instruction.Form;
        if (form.FieldCount == 0) { return null; }
        if (form.HasPostbyte)
        {
            return instruction.PostbyteReference == PostbyteReference.None ? null : instruction.Field(0);
        }

        if (instruction.RelativeTarget is { } relative) { return relative; }
        return form.Role == OperandRole.None ? null : instruction.Operand;
    }

    // An instruction's text with the address its operand names given by its label, as LDA KBD for LDA $C000.
    private static string Named(string text, int? target, SortedDictionary<int, string> names)
    {
        if (target is not { } address || !names.TryGetValue(address, out string? name)) { return text; }
        for (int position = text.IndexOf('$'); position >= 0; position = text.IndexOf('$', position + 1))
        {
            int digits = position + 1;
            while (digits < text.Length && char.IsAsciiHexDigit(text[digits])) { digits++; }
            if (digits > position + 1
                && int.TryParse(text.AsSpan(position + 1, digits - position - 1), NumberStyles.HexNumber, CultureInfo.InvariantCulture, out int value)
                && value == address)
            {
                return string.Concat(text.AsSpan(0, position), name, text.AsSpan(digits));
            }
        }

        return text;
    }
}
