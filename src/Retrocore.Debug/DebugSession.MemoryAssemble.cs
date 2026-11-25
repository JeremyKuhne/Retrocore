// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Cpu.I8080;
using Retrocore.Isa;
using System.Text;
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

    // Assembles one line at an address, its names given by the session as constants, so LDA KBD reads $C000. A
    // scoped name such as RamTest::GallopMaskHigh, which a constant cannot be called, stands in the line as an alias. A name
    // spelled as one of the CPU's registers or conditions, such as X or Z, is taken for the register first, and for
    // the session's name only where the line does not assemble without it.
    private byte[] AssembleLine(InstructionSet set, int address, string line, IDebugMemory memory, string space)
    {
        Dictionary<string, long> symbols = [with(StringComparer.Ordinal)];
        Dictionary<string, long> spelled = [with(StringComparer.Ordinal)];
        IEnumerable<string> registerNames = set.Description.Registers.Select(register => register.Name);
        HashSet<string> registers = [with(StringComparer.OrdinalIgnoreCase), .. registerNames];
        int operands = line.IndexOfAny([' ', '\t']);
        string text = line;
        if (operands > 0)
        {
            int aliases = 0;
            string Alias(Match name)
            {
                string value = name.Value;
                if (!value.Contains("::", StringComparison.Ordinal)) { return value; }
                if (TryResolve(value, memory, space) is not { } resolved) { return value; }
                // An alias no name in the line already is.
                string alias;
                do
                {
                    alias = $"__RETROCORE{aliases++}";
                }
                while (line.Contains(alias, StringComparison.Ordinal) || symbols.ContainsKey(alias));

                symbols[alias] = resolved;
                return alias;
            }

            // Names outside quoted text only, so .byte "RamTest::GallopMaskHigh" stays those characters.
            string written = line[operands..];
            StringBuilder operand = new();
            foreach ((int start, int end, bool quoted) in Pieces(written))
            {
                string piece = written[start..end];
                operand.Append(quoted ? piece : LineName().Replace(piece, Alias));
            }

            text = line[..operands] + operand;
            string aliased = operand.ToString();
            foreach ((int start, int end, bool quoted) in Pieces(aliased))
            {
                if (quoted) { continue; }
                foreach (Match name in LineName().Matches(aliased[start..end]))
                {
                    string value = name.Value;
                    if (symbols.ContainsKey(value) || spelled.ContainsKey(value)) { continue; }
                    if (TryResolve(value, memory, space) is not { } resolved) { continue; }
                    bool register = registers.Contains(value) || s_conditions.Contains(value);
                    (register ? spelled : symbols)[value] = resolved;
                }
            }
        }

        AssemblyResult result = AssembleText(set, address, text, symbols);
        if (!result.Success && spelled.Count > 0)
        {
            foreach ((string name, long value) in spelled)
            {
                symbols[name] = value;
            }

            AssemblyResult named = AssembleText(set, address, text, symbols);
            if (named.Success) { result = named; }
        }

        if (!result.Success && RestartNumber(set, address, text, symbols) is { } restart)
        {
            AssemblyResult numbered = AssembleText(set, address, restart, symbols);
            if (numbered.Success) { result = numbered; }
        }

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

    // An operand's pieces in order: quoted text, such as "HELLO" or 'A', and what is between. A quote that does not
    // close, as the Z80's AF' has, is no quote.
    private static List<(int Start, int End, bool Quoted)> Pieces(string operand)
    {
        List<(int Start, int End, bool Quoted)> pieces = [];
        int plain = 0;
        for (int index = 0; index < operand.Length; index++)
        {
            char character = operand[index];
            if (character is not ('\'' or '"')) { continue; }
            int close = operand.IndexOf(character, index + 1);
            if (close < 0) { continue; }
            if (index > plain) { pieces.Add((plain, index, false)); }
            pieces.Add((index, close + 1, true));
            plain = close + 1;
            index = close;
        }

        if (plain < operand.Length) { pieces.Add((plain, operand.Length, false)); }
        return pieces;
    }

    // The 8080's RST takes the restart's number, 0-7, where the listing names the address it calls, as RST 1 lists as
    // RST RESTART1 where $0008 is named: such a line as RST with the number, or null for any other.
    private static string? RestartNumber(InstructionSet set, int address, string text, Dictionary<string, long> symbols)
    {
        if (!ReferenceEquals(set.Description, I8080Isa.Description)) { return null; }
        int space = text.IndexOfAny([' ', '\t']);
        if (space < 0 || !string.Equals(text[..space], "RST", StringComparison.OrdinalIgnoreCase)) { return null; }

        // The operand's value, as the assembler reckons it at the address, as an equate, which writes no bytes, so
        // it fits at $FFFF; more than one operand is no equate.
        string name = "__RETROCOREVALUE";
        while (text.Contains(name, StringComparison.Ordinal) || symbols.ContainsKey(name)) { name += "_"; }
        AssemblyOptions options = new(set.Name, address, Math.Min(AssembleMaximum, 0x10000 - address))
        {
            PredefinedSymbols = symbols
        };

        string equate = $"{name} = {text[(space + 1)..].Trim()}\n";
        AssemblyResult value = new Assembler.Assembler().Assemble(new AssemblySource(equate, "line"), options);
        if (!value.Success || !value.Symbols.TryGetValue(name, out long target)) { return null; }
        return target is >= 0 and <= 0x38 && target % 8 == 0 ? $"RST {target / 8}" : null;
    }

    // A name's value from the session, or null where it has none; ::COUT is the outermost scope's COUT, which the
    // session knows as COUT.
    private long? TryResolve(string name, IDebugMemory memory, string space)
    {
        try
        {
            return _debug.Resolve(name.StartsWith("::", StringComparison.Ordinal) ? name[2..] : name, memory, space);
        }
        catch (FormatException)
        {
            // Not one of the session's names: the assembler says so if it is not one of its own.
            return null;
        }
    }

    // Assembles a line's text at an address with names as constants.
    private static AssemblyResult AssembleText(InstructionSet set, int address, string text, Dictionary<string, long> symbols)
    {
        AssemblyOptions options = new(set.Name, address, Math.Min(AssembleMaximum, 0x10000 - address))
        {
            PredefinedSymbols = symbols
        };

        return new Assembler.Assembler().Assemble(new AssemblySource("    " + text + "\n", "line"), options);
    }

    // A name in an operand, such as KBD, COUT+1's COUT, RamTest::GallopMaskHigh, Main::@again, ::COUT or z:CH's CH; not a number
    // such as $C0 or 1E, a width prefix such as z: or a:, nor an operator such as .mod, as a dot is never in a name.
    // A name's characters after its first are AssemblySyntax.IsWord's: letters, marks, digits and connectors, which
    // are \w's.
    [GeneratedRegex(@"(?<![$%\w.@])(?:::)?[A-Za-z_@]\w*(?:::(?:@|[A-Za-z_])\w*)*(?!:(?!:))")]
    private static partial Regex LineName();
}
