// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Cpu.I8080;
using Retrocore.Cpu.M6809;
using Retrocore.Cpu.Z80;
using Retrocore.Isa;

namespace Retrocore.Debug.Language;

/// <summary>
///  What each 6502, 65C02, Z80, MC6809, 8080 and 8085 instruction does, and its encodings for a CPU.
/// </summary>
internal static partial class InstructionDocs
{
    private const int OpcodeCount = 256;

    // What each 6502 family instruction does; the flags it changes come from the description's effects lines.
    private static readonly Dictionary<string, string> s_docs = new(StringComparer.OrdinalIgnoreCase)
    {
        ["ADC"] = "Adds memory and the carry to A.",
        ["AND"] = "ANDs memory into A.",
        ["ASL"] = "Shifts A or memory left one bit; bit 7 goes to the carry.",
        ["BBR"] = "Branches when a bit of a zero-page byte is clear (Rockwell 65C02).",
        ["BBS"] = "Branches when a bit of a zero-page byte is set (Rockwell 65C02).",
        ["BCC"] = "Branches when the carry is clear.",
        ["BCS"] = "Branches when the carry is set.",
        ["BEQ"] = "Branches when Z is set (the result was zero).",
        ["BIT"] = "Tests memory against A: Z from A AND memory; N and V from memory's bits 7 and 6 (not for immediate).",
        ["BMI"] = "Branches when N is set (the result was negative).",
        ["BNE"] = "Branches when Z is clear (the result was not zero).",
        ["BPL"] = "Branches when N is clear.",
        ["BRA"] = "Branches always (65C02).",
        ["BRK"] = "Software interrupt: pushes PC+2 and P with B set, then jumps through $FFFE.",
        ["BVC"] = "Branches when V is clear.",
        ["BVS"] = "Branches when V is set.",
        ["CLC"] = "Clears the carry.",
        ["CLD"] = "Clears decimal mode.",
        ["CLI"] = "Clears the interrupt disable flag, allowing IRQs.",
        ["CLV"] = "Clears the overflow flag.",
        ["CMP"] = "Compares A with memory (A - memory, result discarded).",
        ["CPX"] = "Compares X with memory.",
        ["CPY"] = "Compares Y with memory.",
        ["DEC"] = "Decrements memory, or A on the 65C02.",
        ["DEX"] = "Decrements X.",
        ["DEY"] = "Decrements Y.",
        ["EOR"] = "Exclusive-ORs memory into A.",
        ["INC"] = "Increments memory, or A on the 65C02.",
        ["INX"] = "Increments X.",
        ["INY"] = "Increments Y.",
        ["JMP"] = "Jumps to an address.",
        ["JSR"] = "Pushes the return address minus one and jumps to a subroutine.",
        ["LDA"] = "Loads A from memory.",
        ["LDX"] = "Loads X from memory.",
        ["LDY"] = "Loads Y from memory.",
        ["LSR"] = "Shifts A or memory right one bit; bit 0 goes to the carry.",
        ["NOP"] = "Does nothing.",
        ["ORA"] = "ORs memory into A.",
        ["PHA"] = "Pushes A.",
        ["PHP"] = "Pushes P, with B set.",
        ["PHX"] = "Pushes X (65C02).",
        ["PHY"] = "Pushes Y (65C02).",
        ["PLA"] = "Pulls A.",
        ["PLP"] = "Pulls P.",
        ["PLX"] = "Pulls X (65C02).",
        ["PLY"] = "Pulls Y (65C02).",
        ["RMB"] = "Clears a bit of a zero-page byte (Rockwell 65C02).",
        ["ROL"] = "Rotates A or memory left through the carry.",
        ["ROR"] = "Rotates A or memory right through the carry.",
        ["RTI"] = "Returns from an interrupt: pulls P, then PC.",
        ["RTS"] = "Returns from a subroutine: pulls the address and adds one.",
        ["SBC"] = "Subtracts memory and the borrow (the inverted carry) from A.",
        ["SEC"] = "Sets the carry.",
        ["SED"] = "Sets decimal mode for ADC and SBC.",
        ["SEI"] = "Sets the interrupt disable flag, masking IRQs.",
        ["SMB"] = "Sets a bit of a zero-page byte (Rockwell 65C02).",
        ["STA"] = "Stores A to memory.",
        ["STP"] = "Stops the processor until reset (WDC 65C02).",
        ["STX"] = "Stores X to memory.",
        ["STY"] = "Stores Y to memory.",
        ["STZ"] = "Stores zero to memory (65C02).",
        ["TAX"] = "Copies A to X.",
        ["TAY"] = "Copies A to Y.",
        ["TRB"] = "Clears the bits of memory that are set in A; Z from A AND memory (65C02).",
        ["TSB"] = "Sets the bits of memory that are set in A; Z from A AND memory (65C02).",
        ["TSX"] = "Copies S to X.",
        ["TXA"] = "Copies X to A.",
        ["TXS"] = "Copies X to S.",
        ["TYA"] = "Copies Y to A.",
        ["WAI"] = "Waits for an interrupt (WDC 65C02)."
    };

    private static readonly Dictionary<ProcessorVariant, Dictionary<string, List<(AddressMode Mode, byte Code)>>> s_encodings = [];

    /// <summary>
    ///  Gets every documented mnemonic.
    /// </summary>
    internal static IEnumerable<string> Mnemonics =>
        s_docs.Keys.Union(s_z80.Keys, StringComparer.OrdinalIgnoreCase)
            .Union(s_m6809.Keys, StringComparer.OrdinalIgnoreCase)
            .Union(s_i8080.Keys, StringComparer.OrdinalIgnoreCase);

    /// <summary>
    ///  Gets whether a name is a mnemonic of some CPU, including numbered bit instructions such as BBR3.
    /// </summary>
    /// <param name="name">The name.</param>
    /// <returns>Whether it is a mnemonic.</returns>
    internal static bool IsMnemonic(string name) =>
        s_docs.ContainsKey(name.Length == 4 && char.IsAsciiDigit(name[3]) ? name[..3] : name)
            || s_z80.ContainsKey(name)
            || s_m6809.ContainsKey(name)
            || s_i8080.ContainsKey(name);

    /// <summary>
    ///  Gets an instruction's description, or null when the name is not a mnemonic.
    /// </summary>
    /// <param name="mnemonic">The mnemonic, such as LDA or BBR3.</param>
    /// <param name="variant">The CPU whose encodings to list.</param>
    /// <returns>Markdown text.</returns>
    internal static string? Describe(string mnemonic, ProcessorVariant variant) => Describe(mnemonic, M6502Isa.Get(variant));

    /// <summary>
    ///  Gets an instruction's description for any CPU, or null when the name is not one of its family's mnemonics.
    /// </summary>
    /// <param name="mnemonic">The mnemonic, such as LDA, BBR3 or LDIR.</param>
    /// <param name="set">The CPU's instruction set, whose encodings to list.</param>
    /// <returns>
    ///  Markdown text; null for a macro-only CPU, such as <c>Pcode</c>, whose macros say what they are.
    /// </returns>
    internal static string? Describe(string mnemonic, InstructionSet set) => set switch
    {
        { IsMacroOnly: true } => null,
        _ when ReferenceEquals(set.Description, Z80Isa.Description) => DescribeZ80(mnemonic, set),
        _ when ReferenceEquals(set.Description, M6809Isa.Description) => DescribeM6809(mnemonic, set),
        _ when ReferenceEquals(set.Description, I8080Isa.Description) => DescribeI8080(mnemonic, set),
        _ => DescribeM6502(mnemonic, M6502Isa.VariantOf(set))
    };

    /// <summary>
    ///  Gets what an instruction does and the flags it changes, in a line each, for any CPU.
    /// </summary>
    /// <param name="mnemonic">The mnemonic, such as LDA, BBR3 or LDIR.</param>
    /// <param name="set">The CPU's instruction set.</param>
    /// <returns>The summary and flags, or null where the CPU's mnemonics have no documentation.</returns>
    internal static (string Summary, string Flags)? Brief(string mnemonic, InstructionSet set)
    {
        if (set.IsMacroOnly) { return null; }
        Dictionary<string, (string Summary, string Flags)>? docs = null;
        if (ReferenceEquals(set.Description, Z80Isa.Description)) { docs = s_z80; }
        else if (ReferenceEquals(set.Description, M6809Isa.Description)) { docs = s_m6809; }
        else if (ReferenceEquals(set.Description, I8080Isa.Description)) { docs = s_i8080; }

        if (docs is not null)
        {
            return docs.TryGetValue(mnemonic, out (string Summary, string Flags) doc) ? doc : null;
        }

        string key = mnemonic.Length == 4 && char.IsAsciiDigit(mnemonic[3]) ? mnemonic[..3] : mnemonic;
        return s_docs.TryGetValue(key, out string? summary) ? (summary, M6502Flags(mnemonic, set)) : null;
    }

    /// <summary>
    ///  Gets the flags one decoded instruction changes, where its mnemonic's depend on its operands, as ADD HL,BC
    ///  changes only H, N and C, or BIT #$80 only Z.
    /// </summary>
    /// <param name="instruction">The instruction.</param>
    /// <returns>The flags, or null where its mnemonic has no documentation.</returns>
    internal static string? FlagsOf(in DisassembledInstruction instruction)
    {
        InstructionSet set = instruction.InstructionSet;

        // The 6502 family's come from its effects lines, undocumented instructions' too.
        if (ReferenceEquals(set.Description, M6502Isa.Description) && instruction.Effects is { IsKnown: true } effects)
        {
            return FlagText((byte)(effects.FlagsWritten | effects.FlagsMayWrite), set.Description);
        }

        if (Brief(instruction.Mnemonic, set) is not { } brief) { return null; }
        string mnemonic = instruction.Mnemonic.ToUpperInvariant();
        string text = instruction.ToString().ToUpperInvariant();
        int space = text.IndexOf(' ', StringComparison.Ordinal);
        string[] operands = space < 0 ? [] : [.. text[(space + 1)..].Split(',', StringSplitOptions.TrimEntries)];
        string first = operands.Length > 0 ? operands[0] : "";
        string second = operands.Length > 1 ? operands[1] : "";
        bool pair = first is "BC" or "DE" or "HL" or "SP" or "IX" or "IY";
        bool namesCc = operands.Contains("CC");
        if (ReferenceEquals(set.Description, Z80Isa.Description))
        {
            return mnemonic switch
            {
                "ADD" => pair ? "H N C" : "S Z H PV N C",
                "INC" or "DEC" => pair ? "none" : brief.Flags,
                "EX" => first == "AF" ? "all (swapped with AF')" : "none",
                "IN" => second.StartsWith('[') && second != "[C]" ? "none" : "S Z H PV N",
                "LD" => first == "A" && second is "I" or "R" ? "S Z H PV N" : "none",
                "POP" => first == "AF" ? "all" : "none",
                _ => brief.Flags
            };
        }

        if (ReferenceEquals(set.Description, I8080Isa.Description))
        {
            return mnemonic == "POP" ? first == "PSW" ? "all" : "none" : brief.Flags;
        }

        if (ReferenceEquals(set.Description, M6809Isa.Description))
        {
            return mnemonic switch
            {
                "EXG" or "PULS" or "PULU" => namesCc ? "all" : "none",
                "TFR" => second == "CC" ? "all" : "none",
                _ => brief.Flags
            };
        }

        return brief.Flags;
    }

    // The flags a 6502 family mnemonic's encodings change, from the effects lines: the set's, or where the set lacks
    // the mnemonic, the first family set that has it, so a hover still says what it would do.
    private static string M6502Flags(string mnemonic, InstructionSet set)
    {
        int id = set.GetMnemonic(mnemonic);
        if (id == InstructionSet.UnknownMnemonic)
        {
            ReadOnlySpan<ProcessorVariant> variants = [ProcessorVariant.Mos6502, ProcessorVariant.Wdc65C02, ProcessorVariant.Rockwell65C02];
            foreach (ProcessorVariant variant in variants)
            {
                set = M6502Isa.Get(variant);
                id = set.GetMnemonic(mnemonic);
                if (id != InstructionSet.UnknownMnemonic) { break; }
            }
        }

        byte flags = 0;
        for (int encoding = 0; id != InstructionSet.UnknownMnemonic && encoding < set.Encodings.Count; encoding++)
        {
            if (set.GetEncoding(encoding).Mnemonic != id) { continue; }
            InstructionEffects effects = set.Effects(encoding);
            flags |= (byte)(effects.FlagsWritten | effects.FlagsMayWrite);
        }

        return FlagText(flags, set.Description);
    }

    // Flag letters in the flags line's order, or "none" or "all"; B is no flag, only a bit of the byte BRK and PHP push.
    private static string FlagText(byte flags, IsaDescription description)
    {
        byte all = 0;
        List<string> letters = [];
        foreach (IsaFlag flag in description.Flags)
        {
            all |= (byte)(1 << flag.Bit);
            if ((flags & (1 << flag.Bit)) != 0) { letters.Add(flag.Name); }
        }

        return flags == 0 ? "none" : flags == all ? "all" : string.Join(' ', letters);
    }

    private static string? DescribeM6502(string mnemonic, ProcessorVariant variant)
    {
        string key = mnemonic.Length == 4 && char.IsAsciiDigit(mnemonic[3]) ? mnemonic[..3] : mnemonic;
        if (!s_docs.TryGetValue(key, out string? summary)) { return null; }
        (string Summary, string Flags) doc = (summary, M6502Flags(mnemonic, M6502Isa.Get(variant)));
        List<string> modes = [.. Encodings(variant, mnemonic).Select(encoding => $"| {Syntax(encoding.Mode)} | ${encoding.Code:X2} |")];
        string rows = string.Join('\n', modes);
        string table = modes.Count == 0 ? $"\n\nNot an instruction of the {variant}." : $"\n\n| Mode | Opcode |\n| --- | --- |\n{rows}";
        return $"**{mnemonic.ToUpperInvariant()}**: {doc.Summary}\n\nFlags: {doc.Flags}{table}";
    }

    /// <summary>
    ///  Gets the mnemonics a CPU can assemble, including numbered bit instructions.
    /// </summary>
    /// <param name="variant">The CPU.</param>
    /// <returns>The mnemonics.</returns>
    internal static IEnumerable<string> MnemonicsFor(ProcessorVariant variant) => Table(variant).Keys;

    /// <summary>
    ///  Gets the mnemonics any CPU can assemble.
    /// </summary>
    /// <param name="set">The CPU's instruction set.</param>
    /// <returns>The mnemonics; none for a macro-only CPU, whose macros complete as macros.</returns>
    internal static IEnumerable<string> MnemonicsFor(InstructionSet set) => set switch
    {
        { IsMacroOnly: true } => [],
        _ when ReferenceEquals(set.Description, Z80Isa.Description) || ReferenceEquals(set.Description, I8080Isa.Description) =>
            Enumerable.Range(0, set.MnemonicCount).Select(set.MnemonicName),
        _ when ReferenceEquals(set.Description, M6809Isa.Description) => Enumerable.Range(0, set.MnemonicCount)
            .Select(set.MnemonicName)
            .Concat(["LSL", "LSLA", "LSLB", "BHS", "BLO", "LBHS", "LBLO"]),
        _ => MnemonicsFor(M6502Isa.VariantOf(set))
    };

    private static List<(AddressMode Mode, byte Code)> Encodings(ProcessorVariant variant, string mnemonic) =>
        Table(variant).TryGetValue(mnemonic, out List<(AddressMode Mode, byte Code)>? list) ? list : [];

    private static Dictionary<string, List<(AddressMode Mode, byte Code)>> Table(ProcessorVariant variant)
    {
        lock (s_encodings)
        {
            if (s_encodings.TryGetValue(variant, out Dictionary<string, List<(AddressMode Mode, byte Code)>>? table))
            {
                return table;
            }

            table = [with(StringComparer.OrdinalIgnoreCase)];
            Span<byte> bytes = stackalloc byte[3];
            for (int code = 0; code < OpcodeCount; code++)
            {
                bytes[0] = (byte)code;
                if (!Disassembler.TryDecode(bytes, 0, variant, out DisassembledInstruction instruction)) { continue; }
                if (instruction.IsUndocumented) { continue; }

                // Unassigned 65C02 encodings decode as NOPs of other sizes.
                bool nop = instruction.OpCode.Instruction == Instruction.NOP;
                if (nop && instruction.OpCode.Code != InstructionEncodingNop) { continue; }
                string mnemonic = instruction.Mnemonic;
                if (!table.TryGetValue(mnemonic, out List<(AddressMode Mode, byte Code)>? list))
                {
                    list = [];
                    table[mnemonic] = list;
                }

                list.Add((instruction.OpCode.AddressMode, (byte)code));
            }

            s_encodings[variant] = table;
            return table;
        }
    }

    private const byte InstructionEncodingNop = 0xEA;

    private static string Syntax(AddressMode mode) => mode switch
    {
        AddressMode.Absolute => "absolute `addr`",
        AddressMode.AbsoluteIndexedIndirect => "indexed indirect `(addr,x)`",
        AddressMode.AbsoluteIndexedX => "absolute,X `addr,x`",
        AddressMode.AbsoluteIndexedY => "absolute,Y `addr,y`",
        AddressMode.AbsoluteIndirect => "indirect `(addr)`",
        AddressMode.Accumulator => "accumulator `a`",
        AddressMode.Immediate => "immediate `#value`",
        AddressMode.Implied => "implied",
        AddressMode.ProgramCounterRelative => "relative `label`",
        AddressMode.Stack => "stack",
        AddressMode.ZeroPage => "zero page `zp`",
        AddressMode.ZeroPageIndexedIndirect => "(zp,X) `(zp,x)`",
        AddressMode.ZeroPageIndexedX => "zero page,X `zp,x`",
        AddressMode.ZeroPageIndexedY => "zero page,Y `zp,y`",
        AddressMode.ZeroPageIndirect => "(zp) `(zp)`",
        AddressMode.ZeroPageIndirectIndexedY => "(zp),Y `(zp),y`",
        AddressMode.ZeroPageRelative => "zero page, relative `zp,label`",
        _ => mode.ToString()
    };
}
