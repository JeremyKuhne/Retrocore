// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Cpu.M6809;
using Retrocore.Cpu.Z80;
using Retrocore.Isa;

namespace Retrocore.Debug.Language;

/// <summary>
///  What each 6502, 65C02, Z80 and MC6809 instruction does, and its encodings for a CPU.
/// </summary>
internal static partial class InstructionDocs
{
    private const int OpcodeCount = 256;

    private static readonly Dictionary<string, (string Summary, string Flags)> s_docs = new(StringComparer.OrdinalIgnoreCase)
    {
        ["ADC"] = ("Adds memory and the carry to A.", "N V Z C"),
        ["AND"] = ("ANDs memory into A.", "N Z"),
        ["ASL"] = ("Shifts A or memory left one bit; bit 7 goes to the carry.", "N Z C"),
        ["BBR"] = ("Branches when a bit of a zero-page byte is clear (Rockwell 65C02).", "none"),
        ["BBS"] = ("Branches when a bit of a zero-page byte is set (Rockwell 65C02).", "none"),
        ["BCC"] = ("Branches when the carry is clear.", "none"),
        ["BCS"] = ("Branches when the carry is set.", "none"),
        ["BEQ"] = ("Branches when Z is set (the result was zero).", "none"),
        ["BIT"] = ("Tests memory against A: Z from A AND memory; N and V from memory's bits 7 and 6 (not for immediate).", "N V Z"),
        ["BMI"] = ("Branches when N is set (the result was negative).", "none"),
        ["BNE"] = ("Branches when Z is clear (the result was not zero).", "none"),
        ["BPL"] = ("Branches when N is clear.", "none"),
        ["BRA"] = ("Branches always (65C02).", "none"),
        ["BRK"] = ("Software interrupt: pushes PC+2 and P with B set, then jumps through $FFFE.", "B I (65C02 also clears D)"),
        ["BVC"] = ("Branches when V is clear.", "none"),
        ["BVS"] = ("Branches when V is set.", "none"),
        ["CLC"] = ("Clears the carry.", "C"),
        ["CLD"] = ("Clears decimal mode.", "D"),
        ["CLI"] = ("Clears the interrupt disable flag, allowing IRQs.", "I"),
        ["CLV"] = ("Clears the overflow flag.", "V"),
        ["CMP"] = ("Compares A with memory (A - memory, result discarded).", "N Z C"),
        ["CPX"] = ("Compares X with memory.", "N Z C"),
        ["CPY"] = ("Compares Y with memory.", "N Z C"),
        ["DEC"] = ("Decrements memory, or A on the 65C02.", "N Z"),
        ["DEX"] = ("Decrements X.", "N Z"),
        ["DEY"] = ("Decrements Y.", "N Z"),
        ["EOR"] = ("Exclusive-ORs memory into A.", "N Z"),
        ["INC"] = ("Increments memory, or A on the 65C02.", "N Z"),
        ["INX"] = ("Increments X.", "N Z"),
        ["INY"] = ("Increments Y.", "N Z"),
        ["JMP"] = ("Jumps to an address.", "none"),
        ["JSR"] = ("Pushes the return address minus one and jumps to a subroutine.", "none"),
        ["LDA"] = ("Loads A from memory.", "N Z"),
        ["LDX"] = ("Loads X from memory.", "N Z"),
        ["LDY"] = ("Loads Y from memory.", "N Z"),
        ["LSR"] = ("Shifts A or memory right one bit; bit 0 goes to the carry.", "N Z C"),
        ["NOP"] = ("Does nothing.", "none"),
        ["ORA"] = ("ORs memory into A.", "N Z"),
        ["PHA"] = ("Pushes A.", "none"),
        ["PHP"] = ("Pushes P, with B set.", "none"),
        ["PHX"] = ("Pushes X (65C02).", "none"),
        ["PHY"] = ("Pushes Y (65C02).", "none"),
        ["PLA"] = ("Pulls A.", "N Z"),
        ["PLP"] = ("Pulls P.", "all"),
        ["PLX"] = ("Pulls X (65C02).", "N Z"),
        ["PLY"] = ("Pulls Y (65C02).", "N Z"),
        ["RMB"] = ("Clears a bit of a zero-page byte (Rockwell 65C02).", "none"),
        ["ROL"] = ("Rotates A or memory left through the carry.", "N Z C"),
        ["ROR"] = ("Rotates A or memory right through the carry.", "N Z C"),
        ["RTI"] = ("Returns from an interrupt: pulls P, then PC.", "all"),
        ["RTS"] = ("Returns from a subroutine: pulls the address and adds one.", "none"),
        ["SBC"] = ("Subtracts memory and the borrow (the inverted carry) from A.", "N V Z C"),
        ["SEC"] = ("Sets the carry.", "C"),
        ["SED"] = ("Sets decimal mode for ADC and SBC.", "D"),
        ["SEI"] = ("Sets the interrupt disable flag, masking IRQs.", "I"),
        ["SMB"] = ("Sets a bit of a zero-page byte (Rockwell 65C02).", "none"),
        ["STA"] = ("Stores A to memory.", "none"),
        ["STP"] = ("Stops the processor until reset (WDC 65C02).", "none"),
        ["STX"] = ("Stores X to memory.", "none"),
        ["STY"] = ("Stores Y to memory.", "none"),
        ["STZ"] = ("Stores zero to memory (65C02).", "none"),
        ["TAX"] = ("Copies A to X.", "N Z"),
        ["TAY"] = ("Copies A to Y.", "N Z"),
        ["TRB"] = ("Clears the bits of memory that are set in A; Z from A AND memory (65C02).", "Z"),
        ["TSB"] = ("Sets the bits of memory that are set in A; Z from A AND memory (65C02).", "Z"),
        ["TSX"] = ("Copies S to X.", "N Z"),
        ["TXA"] = ("Copies X to A.", "N Z"),
        ["TXS"] = ("Copies X to S.", "none"),
        ["TYA"] = ("Copies Y to A.", "N Z"),
        ["WAI"] = ("Waits for an interrupt (WDC 65C02).", "none")
    };

    private static readonly Dictionary<ProcessorVariant, Dictionary<string, List<(AddressMode Mode, byte Code)>>> s_encodings = [];

    /// <summary>
    ///  Gets every documented mnemonic.
    /// </summary>
    internal static IEnumerable<string> Mnemonics =>
        s_docs.Keys.Union(s_z80.Keys, StringComparer.OrdinalIgnoreCase)
            .Union(s_m6809.Keys, StringComparer.OrdinalIgnoreCase);

    /// <summary>
    ///  Gets whether a name is a mnemonic of some CPU, including numbered bit instructions such as BBR3.
    /// </summary>
    /// <param name="name">The name.</param>
    /// <returns>Whether it is a mnemonic.</returns>
    internal static bool IsMnemonic(string name) =>
        s_docs.ContainsKey(name.Length == 4 && char.IsAsciiDigit(name[3]) ? name[..3] : name)
            || s_z80.ContainsKey(name)
            || s_m6809.ContainsKey(name);

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
    /// <returns>Markdown text.</returns>
    internal static string? Describe(string mnemonic, InstructionSet set) =>
        ReferenceEquals(set.Description, Z80Isa.Description)
            ? DescribeZ80(mnemonic, set)
            : ReferenceEquals(set.Description, M6809Isa.Description)
                ? DescribeM6809(mnemonic, set)
                : DescribeM6502(mnemonic, M6502Isa.VariantOf(set));

    private static string? DescribeM6502(string mnemonic, ProcessorVariant variant)
    {
        string key = mnemonic.Length == 4 && char.IsAsciiDigit(mnemonic[3]) ? mnemonic[..3] : mnemonic;
        if (!s_docs.TryGetValue(key, out (string Summary, string Flags) doc)) { return null; }
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
    /// <returns>The mnemonics.</returns>
    internal static IEnumerable<string> MnemonicsFor(InstructionSet set) =>
        ReferenceEquals(set.Description, Z80Isa.Description)
            ? Enumerable.Range(0, set.MnemonicCount).Select(set.MnemonicName)
            : ReferenceEquals(set.Description, M6809Isa.Description)
                ? Enumerable.Range(0, set.MnemonicCount).Select(set.MnemonicName)
                    .Concat(["LSL", "LSLA", "LSLB", "BHS", "BLO", "LBHS", "LBLO"])
                : MnemonicsFor(M6502Isa.VariantOf(set));

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

            table = new(StringComparer.OrdinalIgnoreCase);
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
