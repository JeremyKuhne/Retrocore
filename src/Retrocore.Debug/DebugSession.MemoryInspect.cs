// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Basic;
using Retrocore.Debug.Language;
using Retrocore.Documentation;
using Retrocore.Isa;
using System.Numerics;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;

namespace Retrocore.Debug;

// retro/memory/inspect: what Retrocore Memory's inspector says about the address at the cursor.
internal sealed partial class DebugSession
{
    // How far past a code label an address still reads as in it, such as COUT+3.
    private const int LabelReach = 0x100;

    // The most references the inspector lists; the count says how many there are.
    private const int ReferencesShown = 32;

    /// <summary>
    ///  Answers retro/memory/inspect: where an address of a memory view's space is and what the debugger knows of it.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   For a <c>memoryReference</c> and an <c>address</c>: the <c>region</c> of the machine's map it is in, such as
    ///   <c>Text page 1</c>, with its <c>kind</c> and the <c>detail</c> of where in it, such as <c>row 3, column 12</c>;
    ///   what the memory map does with it now, <c>mapped</c>, on a machine with banks; the <c>label</c> it is or is
    ///   in, with the <c>offset</c> past it and its documentation's <c>summary</c>; the source <c>path</c> and
    ///   <c>line</c> that emitted it; and the BASIC's floating point <c>values</c> starting there, each a
    ///   <c>label</c> and <c>value</c>. Anything unknown is null.
    ///  </para>
    ///  <para>
    ///   The <c>bits</c> of a byte whose name's documentation describes them, each its <c>bit</c>, the <c>name</c> of
    ///   the mask the documentation links to for it, if any, and its <c>meaning</c>; the <c>instruction</c> starting
    ///   at the address, where it is not data, with its <c>text</c>, <c>size</c>, <c>cycles</c> (and
    ///   <c>cyclesTaken</c> for a branch), the <c>flags</c> it changes and its <c>summary</c>; and the
    ///   <c>references</c> to the address from the code the session knows, each the <c>address</c> of the
    ///   instruction, its <c>text</c>, the <c>label</c> it is in and its <c>kind</c>, at most 32 of them, with their
    ///   <c>referenceCount</c>. Like the listing, it takes the editor's Decode from here <c>starts</c>.
    ///  </para>
    /// </remarks>
    private JsonObject MemoryInspect(JsonObject args)
    {
        MemoryReference(Required(args, "memoryReference"), out DebugMemoryBank? bank);
        int address = args.Int("address") ?? throw new ArgumentException("address is required.");
        if (address is < 0 or > 0xFFFF)
        {
            throw new ArgumentOutOfRangeException(nameof(args), "The address is in $0000-$FFFF.");
        }

        SpaceAnalysis analysis = AnalyzeSpace(bank, args);
        IDebugMemory memory = analysis.Memory;
        // A coprocessor's view, such as the SoftCard's Z80's, has addresses of its own, which the machine's regions
        // and memory map do not describe.
        bool own = bank?.InstructionSet is null;
        DebugRegion? region = own ? DebugRegion.At(Target.Regions, address) : null;

        // The name at the address, a constant such as CH included; else the code label it is in, as COUT+3.
        SortedDictionary<int, string> labels = analysis.Labels;
        SortedDictionary<int, string> names = analysis.Names;
        string? label = null;
        int offset = 0;
        if (names.TryGetValue(address, out string? named))
        {
            label = named;
        }
        else if (labels.Keys.LastOrDefault(start => start <= address, -1) is var start and >= 0 && address - start < LabelReach)
        {
            label = labels[start];
            offset = address - start;
        }

        string? summary = null;
        JsonArray? bits = null;
        if (label is not null && OwnerOf(label, address - offset, memory) is { } owner)
        {
            summary = SymbolSummary(owner, label);
            if (offset == 0) { bits = BitsOf(owner, label, summary); }
        }

        JsonArray references = ReferencesTo(analysis, address, out int referenceCount);

        SourceLine? source = analysis.Position(address)?.Chain[^1];
        return new JsonObject
        {
            ["address"] = address,
            ["region"] = region?.Name,
            ["kind"] = region?.Kind,
            ["detail"] = region?.Detail?.Invoke(address - region.Start),
            ["mapped"] = own ? Mapping(bank, (ushort)address) : null,
            ["label"] = label,
            ["offset"] = offset,
            ["summary"] = summary,
            ["path"] = source?.Path,
            ["line"] = source?.Line,
            ["values"] = Floats(bank, memory, address),
            ["bits"] = bits,
            ["instruction"] = InstructionAt(analysis, address),
            ["references"] = references,
            ["referenceCount"] = referenceCount
        };
    }

    // The bits of a flag byte or soft switch, as its documentation names them: the masks it links to, such as
    // INIT0's <MMUEN> = $40, whose own documentation speaks of a bit, then what its summary says of a bit by number,
    // as RDRAMRD's "reports in bit 7 whether RAMRD is on" does. Only a constant's or variable's.
    private JsonArray? BitsOf(IDebugModule owner, string name, string? summary)
    {
        if (summary is null || owner.Documentation.Find(name) is not { } topic) { return null; }
        if (topic.Kind is not (DocumentationKind.Constant or DocumentationKind.Variable or DocumentationKind.Definition))
        {
            return null;
        }

        DocumentationSet[] sets = [.. _debug.Modules.Select(module => module.Documentation)];
        DocumentationTopic effective = new DocumentationResolver(owner.Documentation, sets).Effective(topic);
        string written = string.Join(" ", effective.Remarks.Prepend(effective.Summary));
        SortedDictionary<int, (string? Name, string Meaning)> found = [];
        DocumentationResolver resolver = new(owner.Documentation, sets);
        foreach (Match link in LinkPattern().Matches(written))
        {
            // The link as the documentation resolves it, a module's name included, as <Hardware:READY> is that
            // module's READY whatever this one calls READY.
            DocumentationTarget target = resolver.Resolve(topic, link.Groups[1].Value);
            if (!target.IsResolved || target.Topic is not { } linked) { continue; }
            long mask = target.Value ?? linked.Value ?? 0;
            if (mask is <= 0 or > 0x80 || !BitOperations.IsPow2(mask)) { continue; }
            string meaning = Plain(resolver.Effective(linked).Summary);
            if (meaning.Length == 0 || !BitWord().IsMatch(meaning)) { continue; }
            found.TryAdd(BitOperations.Log2((ulong)mask), (linked.Name, meaning));
        }

        foreach (Match numbered in NumberedBit().Matches(summary))
        {
            int bit = numbered.Groups[1].Value[0] - '0';
            if (BitClause(summary, numbered) is { } meaning) { found.TryAdd(bit, (null, meaning)); }
        }

        if (found.Count == 0) { return null; }
        JsonArray bits = [];
        foreach ((int bit, (string? Name, string Meaning) described) in found.Reverse())
        {
            JsonObject named = new()
            {
                ["bit"] = bit,
                ["name"] = described.Name,
                ["meaning"] = described.Meaning
            };

            bits.Add((JsonNode)named);
        }

        return bits;
    }

    // What a sentence says of a numbered bit: the words after it, as "bit 7 is set when a key is typed" says; or, where
    // it ends a clause, the clause before it, as "the timer's clock, in bit 5" says.
    private static string? BitClause(string text, Match match)
    {
        char[] stops = ['.', ';', ',', ':', '('];
        string after = text[(match.Index + match.Length)..];
        int stop = after.IndexOfAny(stops);
        string following = (stop < 0 ? after : after[..stop]).Trim();

        // Another byte's bit, as KBDSTRB's "clears bit 7 of KBD" or "KBD's bit 7" speaks of, is not this one's.
        if (following.StartsWith("of ", StringComparison.Ordinal)) { return null; }
        string leading = text[..match.Index].TrimEnd();
        if (leading.EndsWith("'s", StringComparison.Ordinal)) { return null; }
        if (following.Length > 0 && char.IsLetterOrDigit(following[0])) { return following; }

        string before = text[..match.Index].TrimEnd();
        foreach (string preposition in (string[])[" in", " at", " as"])
        {
            if (before.EndsWith(preposition, StringComparison.Ordinal)) { before = before[..^preposition.Length]; }
        }

        before = before.TrimEnd(',', ' ');
        string preceding = before[(before.LastIndexOfAny(stops) + 1)..].Trim();
        if (preceding.StartsWith("and ", StringComparison.Ordinal)) { preceding = preceding[4..]; }
        return preceding.Length == 0 ? null : preceding;
    }

    // A bit by number, such as "bit 7"; not "bit 15", which no byte has.
    [GeneratedRegex(@"\b[Bb]it ([0-7])\b")]
    private static partial Regex NumberedBit();

    // The word bit, in a mask's documentation.
    [GeneratedRegex(@"\bbit\b", RegexOptions.IgnoreCase)]
    private static partial Regex BitWord();

    // The instruction starting at an address where code is known to start, from a source's statement, analysis, a
    // Decode from here start or a mark, not elsewhere, as in I/O or a table: its text with operands named, size,
    // nominal cycles, the flags it changes and what it does.
    private JsonObject? InstructionAt(SpaceAnalysis analysis, int address)
    {
        if (!analysis.Forced.Contains(address))
        {
            if (analysis.Marked(address)) { return null; }
            DebugPosition? position = analysis.Position(address);
            bool known = analysis.Guesses.Kinds[address] == GuessKind.Start;
            if (position is not null) { known = position is { Data: false, Start: { } start } && start == address; }
            if (!known) { return null; }
        }

        if (!Accepted(analysis, address, out DisassembledInstruction instruction)) { return null; }

        (int Cycles, int Taken)? cycles = InstructionCycles.Of(instruction);
        (string Summary, string Flags)? brief = InstructionDocs.Brief(instruction.Mnemonic, analysis.Set);
        return new JsonObject
        {
            ["text"] = NamedText(analysis, instruction),
            ["size"] = instruction.Size,
            ["cycles"] = cycles?.Cycles,
            ["cyclesTaken"] = cycles is { } both && both.Taken != both.Cycles ? both.Taken : null,
            ["flags"] = InstructionDocs.FlagsOf(instruction),
            ["summary"] = brief?.Summary
        };
    }

    // Decodes the instruction at an address where the listing would list one: not in data the sources or the hints
    // file describe, or analysis guessed, unless a start says so; not inside a source's statement, nor inside a
    // marked instruction the listing keeps whole; nor running over a later boundary, a marked one only over another
    // start or data marked.
    private static bool Accepted(SpaceAnalysis analysis, int address, out DisassembledInstruction instruction)
    {
        instruction = default;
        if (!analysis.Forced.Contains(address))
        {
            if (analysis.Marked(address)) { return false; }
            DebugPosition? position = analysis.Position(address);
            if (position is { Data: true } || (position?.Start is { } start && start != address)) { return false; }
            GuessKind guess = position is null ? analysis.Guesses.Kinds[address] : GuessKind.Unknown;
            if (guess is GuessKind.Data or GuessKind.Operand) { return false; }
        }

        foreach ((int code, int size) in analysis.MarkedCode)
        {
            bool inside = code < address && code + size > address;
            if (inside && !RunsOver(code, size, analysis.MarkedCodeBoundary)) { return false; }
        }

        if (!Decode(analysis, address, out instruction)) { return false; }
        Func<int, bool> boundary = analysis.MarkedCode.ContainsKey(address) ? analysis.MarkedCodeBoundary : analysis.Boundary;
        return !RunsOver(address, instruction.Size, boundary);
    }

    // The instructions in the code the session knows, from the sources and analysis, that read, write, call or jump
    // to an address, in address order, the first of them; count is how many there are.
    private JsonArray ReferencesTo(SpaceAnalysis analysis, int address, out int count)
    {
        SortedSet<(int Source, DisassemblyReferenceKind Kind)> found = [];
        foreach (DisassemblyReference reference in analysis.Guesses.References[address])
        {
            // Not from an instruction the listing would not list; a vector's source is a pointer, not an instruction.
            bool vector = reference.Kind == DisassemblyReferenceKind.Vector;
            if (vector || Accepted(analysis, reference.Source, out _))
            {
                found.Add((reference.Source, reference.Kind));
            }
        }

        // A Decode from here start the listing keeps whose instruction analysis skipped, as one overlapping an earlier
        // start's, still refers to what its operand names.
        foreach (int start in analysis.Forced)
        {
            if (found.Any(reference => reference.Source == start)) { continue; }
            if (!Accepted(analysis, start, out DisassembledInstruction instruction)) { continue; }
            foreach ((int target, DisassemblyReferenceKind kind) in ReferencesOf(instruction))
            {
                if (target == address) { found.Add((start, kind)); }
            }
        }

        count = found.Count;
        JsonArray references = [];
        foreach ((int source, DisassemblyReferenceKind kind) in found.Take(ReferencesShown))
        {
            // A vector's source is the pointer, not an instruction.
            string? text = null;
            if (kind != DisassemblyReferenceKind.Vector && Decode(analysis, source, out DisassembledInstruction instruction))
            {
                text = NamedText(analysis, instruction);
            }

            int start = analysis.Labels.Keys.LastOrDefault(label => label <= source, -1);
            string? label = null;
            if (start >= 0 && source - start < LabelReach)
            {
                label = source == start ? analysis.Labels[start] : $"{analysis.Labels[start]}+{source - start}";
            }

            JsonObject reference = new()
            {
                ["address"] = source,
                ["text"] = text,
                ["label"] = label,
                ["kind"] = ReferenceKind(kind)
            };

            references.Add((JsonNode)reference);
        }

        return references;
    }

    // The addresses an instruction refers to and how, as analysis records them (AnalysisEngine.AddReferences): a
    // jump's, call's or branch's target, and the memory its operand reads or writes, so BBR0 $10,LOOP both reads $10
    // and branches to LOOP.
    private static List<(int Target, DisassemblyReferenceKind Kind)> ReferencesOf(in DisassembledInstruction instruction)
    {
        List<(int Target, DisassemblyReferenceKind Kind)> references = [];
        if (instruction.DirectTarget is { } direct)
        {
            DisassemblyReferenceKind flow = instruction.Flow switch
            {
                DisassemblyFlow.Call => DisassemblyReferenceKind.Call,
                DisassemblyFlow.Jump => DisassemblyReferenceKind.Jump,
                _ => DisassemblyReferenceKind.Branch
            };

            references.Add((direct, flow));
        }

        OperandForm form = instruction.Form;
        DisassemblyReferenceKind access = instruction.InstructionSet.EncodingAccess(instruction.EncodingId) switch
        {
            MemoryAccess.Write => DisassemblyReferenceKind.Write,
            MemoryAccess.ReadWrite => DisassemblyReferenceKind.ReadWrite,
            _ => DisassemblyReferenceKind.Read
        };

        if (form.HasPostbyte)
        {
            PostbyteReference postbyte = instruction.PostbyteReference;
            if (postbyte == PostbyteReference.None) { return references; }
            if (instruction.Flow == DisassemblyFlow.IndirectJump)
            {
                references.Add((instruction.Operand, DisassemblyReferenceKind.IndirectJump));
            }
            else if (postbyte == PostbyteReference.Pointer)
            {
                references.Add((instruction.Operand, DisassemblyReferenceKind.Read));
            }
            else if (instruction.DirectTarget is null)
            {
                references.Add((instruction.Operand, access));
            }

            return references;
        }

        if (instruction.Flow == DisassemblyFlow.IndirectJump)
        {
            if (form.FieldCount != 0) { references.Add((instruction.Operand, DisassemblyReferenceKind.IndirectJump)); }
        }
        else if (form.Role == OperandRole.Pointer)
        {
            references.Add((instruction.Operand, DisassemblyReferenceKind.Read));
        }
        else if (form.Role == OperandRole.Memory && (instruction.RelativeTarget is not null || instruction.DirectTarget is null))
        {
            references.Add((instruction.Operand, access));
        }

        return references;
    }

    // How a reference uses its address, in the inspector's words.
    private static string ReferenceKind(DisassemblyReferenceKind kind) => kind switch
    {
        DisassemblyReferenceKind.Branch => "branches",
        DisassemblyReferenceKind.Jump => "jumps",
        DisassemblyReferenceKind.Call => "calls",
        DisassemblyReferenceKind.Write => "writes",
        DisassemblyReferenceKind.ReadWrite => "changes",
        DisassemblyReferenceKind.IndirectJump => "jumps through",
        DisassemblyReferenceKind.Vector => "vector",
        _ => "reads"
    };

    // Decodes the instruction at an address from the bytes that can be read there.
    private static bool Decode(SpaceAnalysis analysis, int address, out DisassembledInstruction instruction)
    {
        Span<byte> bytes = stackalloc byte[LongestInstruction];
        int available = 0;
        while (available < Math.Min(LongestInstruction, 0x10000 - address) && analysis.Memory.Readable(address + available))
        {
            bytes[available] = analysis.Memory.Peek((ushort)(address + available));
            available++;
        }

        return Disassembler.TryDecode(bytes[..available], (ushort)address, analysis.Set, out instruction);
    }

    // An instruction's text with its operand named, as the listing writes it.
    private string NamedText(SpaceAnalysis analysis, in DisassembledInstruction instruction)
    {
        (int? target, int? shown) = ListingOperands.OperandAddress(instruction, DirectPage(analysis.Set));
        return ListingOperands.Named(instruction.ToString(), target, shown, analysis.Names);
    }

    // The module whose symbol the name an address has is there, chosen as the names are, so a label from the module
    // whose code is at its address, as a program's own COUT is not the ROM's, and a constant such as CH from a module
    // whose code is in memory; none for a hints file's name.
    private IDebugModule? OwnerOf(string name, int value, IDebugMemory memory)
    {
        ushort address = (ushort)value;
        bool Defines(IDebugModule module) => module.TryResolve(name, out long resolved) && resolved == value;
        bool Applies(IDebugModule module)
        {
            if (!Defines(module)) { return false; }
            if (DebugInfo.Active(module, memory, address) && module.LabelApplies(memory, address)) { return true; }
            return module.InMemory(memory) && module.AddressConstants.Any(constant => constant.Name == name && constant.Value == value);
        }

        return _debug.Modules.FirstOrDefault(Applies) ?? _debug.Modules.FirstOrDefault(Defines);
    }

    // What the memory map does with an address now, on a machine with banks: in the CPU's view, what it reads and
    // writes there; in a bank's, whether the CPU reaches the bank there.
    private string? Mapping(DebugMemoryBank? bank, ushort address)
    {
        if (Target.Banks.Count == 0) { return null; }
        Enum read = Target.ReadArea(address), write = Target.WriteArea(address);
        if (bank is null)
        {
            return read.Equals(write) ? $"Reads and writes {AreaName(read)}" : $"Reads {AreaName(read)}, writes {AreaName(write)}";
        }

        if (bank.AreaOf(address) is null) { return $"{bank.Label} has no byte here"; }
        bool reads = bank.ReadBy(Target, address), writes = bank.WrittenBy(Target, address);
        return (reads, writes) switch
        {
            (true, true) => "The CPU reads and writes it here now",
            (true, false) => $"The CPU reads it here now, and writes {AreaName(write)}",
            (false, true) => $"The CPU writes it here now, and reads {AreaName(read)}",
            _ => $"Not mapped now: the CPU reads {AreaName(read)} here"
        };
    }

    // An area as a sentence names it: the label of a bank that is that area alone, such as slot 6 ROM (Disk II boot);
    // else its own name in words, such as main language card, as a bank of several areas names them all.
    private string AreaName(Enum area)
    {
        if (Target.Banks.FirstOrDefault(bank => bank.Areas.Count == 1 && bank.Areas[0].Equals(area)) is { } owner)
        {
            string text = owner.Label;
            return text.Length > 1 && char.IsLower(text[1]) ? char.ToLowerInvariant(text[0]) + text[1..] : text;
        }

        return string.Join(' ', AreaWords().Split(area.ToString()).Select(word => word switch
        {
            "Ram" => "RAM",
            "Rom" => "ROM",
            "Io" => "I/O",
            "None" => "nothing",
            _ => word.ToLowerInvariant()
        }));
    }

    // The words of an area's name, such as Slot 1 Rom in Slot1Rom.
    [GeneratedRegex("(?<=[a-z])(?=[A-Z0-9])|(?<=[0-9])(?=[A-Z])")]
    private static partial Regex AreaWords();

    // The BASIC's floating point numbers that start at an address, in each of its formats; see FloatFormats.
    private JsonArray Floats(DebugMemoryBank? bank, IDebugMemory memory, int address)
    {
        JsonArray values = [];
        foreach ((string label, int length, bool exponentFirst, int digits) in FloatFormats())
        {
            // Only bytes the space has: a bank's gaps read as $FF, which are no number.
            if (address + length > 0x10000
                || (bank is not null && Enumerable.Range(address, length).Any(at => bank.AreaOf((ushort)at) is null)))
            {
                continue;
            }

            byte[] bytes = [.. Enumerable.Range(address, length).Select(at => memory.Peek((ushort)at))];
            values.Add((JsonNode)new JsonObject
            {
                ["label"] = label,
                ["value"] = BasicNumbers.Format(BasicNumbers.ReadFloat(bytes, exponentFirst), digits)
            });
        }

        return values;
    }

    // The BASIC's floating point formats: AppleSoft's and Color BASIC's five bytes and Business BASIC's four,
    // exponent first; Level II's single and double, exponent last. None for an integer BASIC.
    private IEnumerable<(string Label, int Length, bool ExponentFirst, int Digits)> FloatFormats()
    {
        BasicDialect? basic = Target.Basic;
        if (basic is null || ReferenceEquals(basic, BasicDialect.Integer) || ReferenceEquals(basic, BasicDialect.Apple1))
        {
            return [];
        }

        if (ReferenceEquals(basic, BasicDialect.Level2))
        {
            return [("Single, 4 bytes", 4, false, 6), ("Double, 8 bytes", 8, false, 16)];
        }

        return ReferenceEquals(basic, BasicDialect.BusinessBasic)
            ? [("Real, 4 bytes", 4, true, 6)]
            : [("Float, 5 bytes", 5, true, 9)];
    }

    /// <summary>
    ///  Answers retro/memory/numbers: a number's bytes in each of the BASIC's floating point formats, which Find
    ///  looks for.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   For a <c>memoryReference</c> and a <c>value</c>, as BASIC writes numbers: <c>formats</c>, each with the
    ///   <c>label</c> the inspector gives it and the <c>bytes</c> in memory order, rounded as BASIC stores the value.
    ///   None in a coprocessor's view, for a value a format cannot hold, or with an integer BASIC.
    ///  </para>
    /// </remarks>
    private JsonObject MemoryNumbers(JsonObject args)
    {
        MemoryReference(Required(args, "memoryReference"), out DebugMemoryBank? bank);
        string value = Required(args, "value");
        if (!BasicNumbers.TryParse(value, out double parsed) || !double.IsFinite(parsed))
        {
            throw new ArgumentException("The value is not a number.");
        }

        JsonArray formats = [];
        if (bank?.InstructionSet is not null) { return new JsonObject { ["formats"] = formats }; }
        foreach ((string label, int length, bool exponentFirst, _) in FloatFormats())
        {
            byte[] bytes;
            try
            {
                // From the text, so Level II's double keeps the bits a double would lose.
                bytes = BasicNumbers.WriteFloat(value, length, exponentFirst);
            }
            catch (OverflowException)
            {
                continue;
            }

            JsonArray list = [];
            foreach (byte part in bytes) { list.Add((JsonNode)part); }
            formats.Add((JsonNode)new JsonObject { ["label"] = label, ["bytes"] = list });
        }

        return new JsonObject { ["formats"] = formats };
    }
}
