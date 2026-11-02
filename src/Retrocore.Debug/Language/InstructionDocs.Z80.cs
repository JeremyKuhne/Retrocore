// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Globalization;
using Retrocore.Isa;

namespace Retrocore.Debug.Language;

internal static partial class InstructionDocs
{
    // What each Z80 instruction does, and the flags it changes (S Z H PV N C; Y and X follow the result).
    private static readonly Dictionary<string, (string Summary, string Flags)> s_z80 = new(StringComparer.OrdinalIgnoreCase)
    {
        ["ADC"] = ("Adds the operand and the carry to A, or a register pair and the carry to HL.", "S Z H PV N C"),
        ["ADD"] = ("Adds the operand to A, or a register pair to HL, IX or IY.", "S Z H PV N C (pairs: H N C)"),
        ["AND"] = ("ANDs the operand into A.", "S Z H PV N C"),
        ["BIT"] = ("Tests a bit of a register or memory: Z is set when the bit is clear.", "S Z H PV N"),
        ["CALL"] = ("Pushes the return address and jumps to a subroutine, optionally on a condition.", "none"),
        ["CCF"] = ("Complements the carry; H takes the old carry.", "H N C"),
        ["CP"] = ("Compares A with the operand (A - operand, result discarded).", "S Z H PV N C"),
        ["CPD"] = ("Compares A with [HL], then decrements HL and BC.", "S Z H PV N"),
        ["CPDR"] = ("Repeats CPD until A matches [HL] or BC is zero.", "S Z H PV N"),
        ["CPI"] = ("Compares A with [HL], then increments HL and decrements BC.", "S Z H PV N"),
        ["CPIR"] = ("Repeats CPI until A matches [HL] or BC is zero.", "S Z H PV N"),
        ["CPL"] = ("Complements A.", "H N"),
        ["DAA"] = ("Adjusts A to packed BCD after an addition or subtraction.", "S Z H PV C"),
        ["DEC"] = ("Decrements a register, a register pair or memory; pairs change no flags.", "S Z H PV N"),
        ["DI"] = ("Disables maskable interrupts.", "none"),
        ["DJNZ"] = ("Decrements B and branches when it is not zero.", "none"),
        ["EI"] = ("Enables maskable interrupts after the next instruction.", "none"),
        ["EX"] = ("Exchanges DE with HL, AF with AF', or the top of the stack with HL, IX or IY.", "none (AF,AF' swaps them)"),
        ["EXX"] = ("Exchanges BC, DE and HL with BC', DE' and HL'.", "none"),
        ["HALT"] = ("Waits for an interrupt, executing NOPs.", "none"),
        ["IM"] = ("Selects interrupt mode 0, 1 or 2.", "none"),
        ["IN"] = ("Reads an I/O port into a register; IN [C] sets only the flags.", "S Z H PV N (none for IN A,[n])"),
        ["INC"] = ("Increments a register, a register pair or memory; pairs change no flags.", "S Z H PV N"),
        ["IND"] = ("Reads port C into [HL], then decrements HL and B.", "S Z H PV N C"),
        ["INDR"] = ("Repeats IND until B is zero.", "S Z H PV N C"),
        ["INI"] = ("Reads port C into [HL], then increments HL and decrements B.", "S Z H PV N C"),
        ["INIR"] = ("Repeats INI until B is zero.", "S Z H PV N C"),
        ["JP"] = ("Jumps to an address, optionally on a condition, or to HL, IX or IY.", "none"),
        ["JR"] = ("Branches by a signed displacement, optionally on Z or C.", "none"),
        ["LD"] = ("Copies the source operand to the destination; LD A,I and LD A,R set flags.", "none (LD A,I/R: S Z H PV N)"),
        ["LDD"] = ("Copies [HL] to [DE], then decrements HL, DE and BC.", "H PV N"),
        ["LDDR"] = ("Repeats LDD until BC is zero.", "H PV N"),
        ["LDI"] = ("Copies [HL] to [DE], then increments HL and DE and decrements BC.", "H PV N"),
        ["LDIR"] = ("Repeats LDI until BC is zero.", "H PV N"),
        ["NEG"] = ("Negates A (0 - A).", "S Z H PV N C"),
        ["NOP"] = ("Does nothing.", "none"),
        ["OR"] = ("ORs the operand into A.", "S Z H PV N C"),
        ["OTDR"] = ("Repeats OUTD until B is zero.", "S Z H PV N C"),
        ["OTIR"] = ("Repeats OUTI until B is zero.", "S Z H PV N C"),
        ["OUT"] = ("Writes a register, A or zero to an I/O port.", "none"),
        ["OUTD"] = ("Decrements B, writes [HL] to port C, then decrements HL.", "S Z H PV N C"),
        ["OUTI"] = ("Decrements B, writes [HL] to port C, then increments HL.", "S Z H PV N C"),
        ["POP"] = ("Pulls a register pair from the stack.", "none (POP AF: all)"),
        ["PUSH"] = ("Pushes a register pair onto the stack.", "none"),
        ["RES"] = ("Clears a bit of a register or memory.", "none"),
        ["RET"] = ("Returns from a subroutine, optionally on a condition.", "none"),
        ["RETI"] = ("Returns from a maskable interrupt, signalling Z80 peripherals.", "none"),
        ["RETN"] = ("Returns from a non-maskable interrupt, restoring IFF1 from IFF2.", "none"),
        ["RL"] = ("Rotates left through the carry.", "S Z H PV N C"),
        ["RLA"] = ("Rotates A left through the carry.", "H N C"),
        ["RLC"] = ("Rotates left; bit 7 goes to the carry and bit 0.", "S Z H PV N C"),
        ["RLCA"] = ("Rotates A left; bit 7 goes to the carry and bit 0.", "H N C"),
        ["RLD"] = ("Rotates the BCD digits of A's low nibble and [HL] left.", "S Z H PV N"),
        ["RR"] = ("Rotates right through the carry.", "S Z H PV N C"),
        ["RRA"] = ("Rotates A right through the carry.", "H N C"),
        ["RRC"] = ("Rotates right; bit 0 goes to the carry and bit 7.", "S Z H PV N C"),
        ["RRCA"] = ("Rotates A right; bit 0 goes to the carry and bit 7.", "H N C"),
        ["RRD"] = ("Rotates the BCD digits of A's low nibble and [HL] right.", "S Z H PV N"),
        ["RST"] = ("Calls a restart address: $00, $08, $10, $18, $20, $28, $30 or $38.", "none"),
        ["SBC"] = ("Subtracts the operand and the carry from A, or a register pair and the carry from HL.", "S Z H PV N C"),
        ["SCF"] = ("Sets the carry.", "H N C"),
        ["SET"] = ("Sets a bit of a register or memory.", "none"),
        ["SLA"] = ("Shifts left; bit 7 goes to the carry and bit 0 is cleared.", "S Z H PV N C"),
        ["SLL"] = ("Shifts left; bit 7 goes to the carry and bit 0 is set (undocumented).", "S Z H PV N C"),
        ["SRA"] = ("Shifts right; bit 0 goes to the carry and bit 7 is kept.", "S Z H PV N C"),
        ["SRL"] = ("Shifts right; bit 0 goes to the carry and bit 7 is cleared.", "S Z H PV N C"),
        ["SUB"] = ("Subtracts the operand from A.", "S Z H PV N C"),
        ["XOR"] = ("Exclusive-ORs the operand into A.", "S Z H PV N C")
    };

    // Lists a Z80 mnemonic's canonical encodings: its operands, opcode bytes with their fields, and T-states.
    private static string? DescribeZ80(string mnemonic, InstructionSet set)
    {
        if (!s_z80.TryGetValue(mnemonic, out (string Summary, string Flags) doc)) { return null; }
        int id = set.GetMnemonic(mnemonic);
        List<string> rows = [];
        for (int encoding = 0; encoding < set.Encodings.Count; encoding++)
        {
            IsaEncoding value = set.GetEncoding(encoding);
            if (value.Mnemonic != id || !set.TryGet(id, value.Form, out int canonical) || canonical != encoding)
            {
                continue;
            }

            OperandForm form = set.GetForm(value.Form);
            string operands = form.Patterns[0].Length == 0 ? "" : $" {form.Name}";
            string cycles = value.Cycles == value.CyclesTaken
                ? value.Cycles.ToString(CultureInfo.InvariantCulture)
                : $"{value.CyclesTaken}/{value.Cycles}";

            string note = value.Undocumented ? " (undocumented)" : "";
            rows.Add($"| `{mnemonic.ToUpperInvariant()}{operands}`{note} | `{Bytes(value, form)}` | {cycles} |");
        }

        string table = rows.Count == 0 ? "" : $"\n\n| Operands | Opcode | T-states |\n| --- | --- | --- |\n{string.Join('\n', rows)}";
        return $"**{mnemonic.ToUpperInvariant()}**: {doc.Summary}\n\nFlags: {doc.Flags}{table}";
    }

    // The opcode bytes in order with their operand fields: d a displacement, n a byte, nn a word, e a branch.
    private static string Bytes(IsaEncoding encoding, OperandForm form)
    {
        List<string> parts = [];
        for (int index = 0; index < encoding.OpcodeBytesBeforeOperands; index++)
        {
            parts.Add(Opcode(encoding, form, index));
        }

        foreach (OperandFieldKind field in form.Fields)
        {
            string? text = field switch
            {
                OperandFieldKind.Byte => "n",
                OperandFieldKind.Word => "nn nn",
                OperandFieldKind.Relative8 => "e",
                OperandFieldKind.Displacement8 => "d",
                _ => null
            };

            if (text is not null) { parts.Add(text); }
        }

        for (int index = encoding.OpcodeBytesBeforeOperands; index < encoding.OpcodeLength; index++)
        {
            parts.Add(Opcode(encoding, form, index));
        }

        return string.Join(' ', parts);
    }

    // A bit number adds 8 per bit to the last opcode byte, and a restart adds its address.
    private static string Opcode(IsaEncoding encoding, OperandForm form, int index)
    {
        string hex = encoding.OpcodeByte(index).ToString("X2", CultureInfo.InvariantCulture);
        if (index != encoding.OpcodeLength - 1 || form.OpcodeField < 0) { return hex; }
        return form.Field(form.OpcodeField) == OperandFieldKind.BitNumber ? $"{hex}+8b" : $"{hex}+p";
    }
}
