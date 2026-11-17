// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Isa;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;

namespace Retrocore.Debug;

// retro/memory/assemble: one line assembled at an address, for assembling in place in Retrocore Memory's listing.
internal sealed partial class DebugSession
{
    // The most bytes one line may assemble to.
    private const int AssembleMaximum = 16;

    // The Z80's and 8080's condition names, which are no symbols in an operand such as JP NZ,LOOP.
    private static readonly HashSet<string> s_conditions =
        [with(StringComparer.OrdinalIgnoreCase), "NZ", "Z", "NC", "C", "PO", "PE", "P", "M"];

    /// <summary>
    ///  Answers retro/memory/assemble: the bytes of one line assembled at an address of a memory view's space,
    ///  without writing them.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   For a <c>memoryReference</c>, an <c>address</c> and a <c>line</c> such as <c>LDA KBD</c> or
    ///   <c>JSR $FDED</c>, in the space's CPU's native syntax, with the session's symbols, the hints file's names in
    ///   the space first: the <c>bytes</c>, the <c>text</c> they decode to, and the CPU's <c>nop</c>, which pads a
    ///   shorter instruction. A line that does not assemble is an error with the assembler's message.
    ///  </para>
    /// </remarks>
    private JsonObject MemoryAssemble(JsonObject args)
    {
        MemoryReference(Required(args, "memoryReference"), out DebugMemoryBank? bank);
        int address = args.Int("address") ?? throw new ArgumentException("address is required.");
        if (address is < 0 or > 0xFFFF)
        {
            throw new ArgumentOutOfRangeException(nameof(args), "The address is in $0000-$FFFF.");
        }

        string line = Required(args, "line").Trim();
        if (line.Length == 0) { throw new ArgumentException("Type an instruction, such as NOP."); }
        IDebugMemory memory = bank is null ? Target : new BankMemory(bank);
        InstructionSet set = bank?.InstructionSet ?? Target.InstructionSet;
        byte[] bytes = AssembleLine(set, address, line, memory, HintSpace(bank));
        byte[] nop = AssembleLine(set, address, "NOP", memory, HintSpace(bank));
        string? text = null;
        if (Disassembler.TryDecode(bytes, (ushort)address, set, out DisassembledInstruction instruction) && instruction.Size == bytes.Length)
        {
            // Its operand by name, as the listing gives it.
            (_, SortedDictionary<int, string> names) = LabelsAndNames(bank, memory);
            (int? target, int? shown) = ListingOperands.OperandAddress(instruction, DirectPage(set));
            text = ListingOperands.Named(instruction.ToString(), target, shown, names);
        }

        JsonArray written = [];
        foreach (byte value in bytes)
        {
            written.Add((JsonNode)value);
        }

        JsonArray padding = [];
        foreach (byte value in nop)
        {
            padding.Add((JsonNode)value);
        }

        return new JsonObject { ["bytes"] = written, ["text"] = text, ["nop"] = padding };
    }

    // Assembles one line at an address, its names given by the session as constants, so LDA KBD reads $C000.
    private byte[] AssembleLine(InstructionSet set, int address, string line, IDebugMemory memory, string space)
    {
        Dictionary<string, long> symbols = [with(StringComparer.Ordinal)];
        IEnumerable<string> registerNames = set.Description.Registers.Select(register => register.Name);
        HashSet<string> registers = [with(StringComparer.OrdinalIgnoreCase), .. registerNames];
        int operands = line.IndexOfAny([' ', '\t']);
        if (operands > 0)
        {
            foreach (Match name in LineName().Matches(line[operands..]))
            {
                string value = name.Value;
                bool known = symbols.ContainsKey(value);
                if (known || registers.Contains(value) || s_conditions.Contains(value)) { continue; }
                try
                {
                    symbols[value] = _debug.Resolve(value, memory, space);
                }
                catch (FormatException)
                {
                    // Not one of the session's names: the assembler says so if it is not one of its own.
                }
            }
        }

        AssemblyOptions options = new(set.Name, address, Math.Min(AssembleMaximum, 0x10000 - address))
        {
            PredefinedSymbols = symbols
        };

        AssemblyResult result = new Assembler.Assembler().Assemble(new AssemblySource("    " + line + "\n", "line"), options);
        if (!result.Success)
        {
            throw new ArgumentException(result.Diagnostics[0].Message);
        }

        // The section is the image's size; the line's statements say how much of it they fill.
        AssemblySection? section = result.Sections.FirstOrDefault(found => found.Size > 0);
        int size = result.SourceMap.Sum(entry => entry.Size);
        if (section is null || section.Origin != address || size == 0)
        {
            throw new ArgumentException($"{line} assembles to no bytes.");
        }

        return section.Bytes[..Math.Min(size, section.Size)].ToArray();
    }

    // A name in an operand, such as KBD, COUT+1's COUT or Monitor.COUT; not a number such as $C0 or 1E.
    [GeneratedRegex(@"(?<![$%\w.])[A-Za-z_][\w.]*")]
    private static partial Regex LineName();
}
