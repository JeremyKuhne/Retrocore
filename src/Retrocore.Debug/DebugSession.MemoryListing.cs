// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Isa;
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

    // The register that holds the page a one-byte memory operand is in, on a CPU that has one.
    private const string DirectPageRegister = "DP";

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

        // Code marked in the hints file starts instructions, as Decode from here's starts do.
        string space = HintSpace(bank);
        forced.UnionWith(_hints.Code(space));

        // Each byte is read once, and each address's position found once, as a long data statement's would otherwise
        // be checked against memory again at every byte of it.
        ListingMemory memory = new(bank is null ? Target : new BankMemory(bank), address => MemoryByte(bank, address));
        Dictionary<int, DebugPosition?> positions = [];
        DebugPosition? Position(int address)
        {
            if (!positions.TryGetValue(address, out DebugPosition? position))
            {
                position = _debug.Position(memory, (ushort)address);
                positions.Add(address, position);
            }

            return position;
        }

        InstructionSet set = bank?.InstructionSet ?? Target.InstructionSet;
        (SortedDictionary<int, string> labels, SortedDictionary<int, string> names) = LabelsAndNames(bank, memory);
        // Analysis guesses at the bytes no source describes, from the PC, the starts and the sources' code.
        MemoryGuesses guesses = Guess(
            bank,
            memory,
            set,
            GuessEntries(bank, labels.Keys.Where(label => Position(label) is { Data: false })),
            forced,
            Position,
            _hints.Data(space));

        // Data marked in the hints file, which analysis keeps as it is, so the listing's data there is no guess.
        IReadOnlyList<(int Start, int Length)> markedData = _hints.Data(space);
        bool Marked(int address) => markedData.Any(range => address >= range.Start && address < range.Start + range.Length);

        GuessKind Guessed(int address) => Position(address) is null ? guesses.Kinds[address] : GuessKind.Unknown;
        bool Boundary(int address)
        {
            if (forced.Contains(address) || labels.ContainsKey(address)) { return true; }
            DebugPosition? position = Position(address);
            // Where analysis guessed an instruction starts, or its guessed data does, as a pointer's first byte.
            if (position is null)
            {
                GuessKind kind = guesses.Kinds[address];
                return kind == GuessKind.Start || (kind == GuessKind.Data && (address == 0 || Guessed(address - 1) != GuessKind.Data));
            }

            return position is { Start: { } start } && start == address;
        }

        // A direct-page register makes a one-byte memory operand an offset in its page, as the 6809's DP does; the
        // page is known for the CPU's own memory, from its registers at the stop, and not for another CPU's.
        int? directPage = null;
        if (set.Description.Registers.Any(register => register.Name == DirectPageRegister))
        {
            bool own = ReferenceEquals(set.Description, Target.InstructionSet.Description);
            long? page = own ? Target.Registers.Value(Target.Frame, DirectPageRegister) : null;
            directPage = page is { } value ? (int)(value & 0xFF) : -1;
        }

        int end = Math.Min(0x10000, from + count);
        int first = -1;
        if (Position(from) is { Start: { } covering } && covering <= from)
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
            // Bytes that cannot be read, such as past a bank's end, list nothing, as the grid shows nothing there.
            if (!memory.Readable(address))
            {
                address++;
                continue;
            }

            DebugPosition? position = Position(address);
            GuessKind guess = position is null ? guesses.Kinds[address] : GuessKind.Unknown;
            bool guessed = guess is GuessKind.Start or GuessKind.Data;
            string kind = position is null ? guess switch
            {
                GuessKind.Start => "code",
                GuessKind.Data => "data",
                _ => "unknown"
            } : "code";

            int size;
            string text;
            int? target = null;
            int start = position?.Data == true ? position.Start ?? -1 : -1;
            int length = position?.Size ?? 0;
            if (guess == GuessKind.Data && !forced.Contains(address))
            {
                // Data analysis guessed lists eight bytes a line, a line ending where the guess or the bytes do.
                size = 1;
                while (size < DataPerLine
                    && address + size <= 0xFFFF
                    && Guessed(address + size) == GuessKind.Data
                    && memory.Readable(address + size)
                    && !Boundary(address + size))
                {
                    size++;
                }

                text = DataText(memory, address, size);
            }
            else if (start >= 0 && address < start + length && !forced.Contains(address))
            {
                // A data statement lists eight bytes a line, a line ending early where a later boundary starts.
                kind = "data";
                size = Math.Min(DataPerLine, Math.Min(start + length, 0x10000) - address);
                for (int index = 1; index < size; index++)
                {
                    if (!memory.Readable(address + index) || Boundary(address + index))
                    {
                        size = index;
                        break;
                    }
                }

                text = DataText(memory, address, size);
            }
            else
            {
                // An instruction decodes from the bytes that can be read, up to the first that cannot.
                int available = 0;
                while (available < Math.Min(LongestInstruction, 0x10000 - address) && memory.Readable(address + available))
                {
                    bytes[available] = memory.Peek((ushort)(address + available));
                    available++;
                }

                if (Disassembler.TryDecode(bytes[..available], (ushort)address, set, out DisassembledInstruction instruction)
                    && !RunsOver(address, instruction.Size, Boundary))
                {
                    size = instruction.Size;
                    (target, int? shown) = ListingOperands.OperandAddress(instruction, directPage);

                    // An operand outside the space, as JSR $FDED is in a view of main RAM, goes nowhere from it.
                    if (target is { } going && !memory.Readable(going)) { target = null; }
                    text = ListingOperands.Named(instruction.ToString(), target, shown, names);
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
                ["guess"] = guessed && position is null && !forced.Contains(address) && !Marked(address),
                ["comment"] = _hints.Comments(space).TryGetValue(address, out string? comment) ? comment : null,
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
}
