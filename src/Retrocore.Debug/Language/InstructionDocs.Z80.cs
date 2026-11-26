// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Isa;
using System.Globalization;

namespace Retrocore.Debug.Language;

internal static partial class InstructionDocs
{
    // What each Z80 instruction does; the flags it changes come from the description's effects lines, the
    // undocumented Y and X left out.
    private static readonly Dictionary<string, string> s_z80 = new(StringComparer.OrdinalIgnoreCase)
    {
        ["ADC"] = "Adds the operand and the carry to A, or a register pair and the carry to HL.",
        ["ADD"] = "Adds the operand to A, or a register pair to HL, IX or IY.",
        ["AND"] = "ANDs the operand into A.",
        ["BIT"] = "Tests a bit of a register or memory: Z is set when the bit is clear.",
        ["CALL"] = "Pushes the return address and jumps to a subroutine, optionally on a condition.",
        ["CCF"] = "Complements the carry; H takes the old carry.",
        ["CP"] = "Compares A with the operand (A - operand, result discarded).",
        ["CPD"] = "Compares A with [HL], then decrements HL and BC.",
        ["CPDR"] = "Repeats CPD until A matches [HL] or BC is zero.",
        ["CPI"] = "Compares A with [HL], then increments HL and decrements BC.",
        ["CPIR"] = "Repeats CPI until A matches [HL] or BC is zero.",
        ["CPL"] = "Complements A.",
        ["DAA"] = "Adjusts A to packed BCD after an addition or subtraction.",
        ["DEC"] = "Decrements a register, a register pair or memory; pairs change no flags.",
        ["DI"] = "Disables maskable interrupts.",
        ["DJNZ"] = "Decrements B and branches when it is not zero.",
        ["EI"] = "Enables maskable interrupts after the next instruction.",
        ["EX"] = "Exchanges DE with HL, AF with AF', or the top of the stack with HL, IX or IY.",
        ["EXX"] = "Exchanges BC, DE and HL with BC', DE' and HL'.",
        ["HALT"] = "Waits for an interrupt, executing NOPs.",
        ["IM"] = "Selects interrupt mode 0, 1 or 2.",
        ["IN"] = "Reads an I/O port into a register; IN [C] sets only the flags.",
        ["INC"] = "Increments a register, a register pair or memory; pairs change no flags.",
        ["IND"] = "Reads port C into [HL], then decrements HL and B.",
        ["INDR"] = "Repeats IND until B is zero.",
        ["INI"] = "Reads port C into [HL], then increments HL and decrements B.",
        ["INIR"] = "Repeats INI until B is zero.",
        ["JP"] = "Jumps to an address, optionally on a condition, or to HL, IX or IY.",
        ["JR"] = "Branches by a signed displacement, optionally on Z or C.",
        ["LD"] = "Copies the source operand to the destination; LD A,I and LD A,R set flags.",
        ["LDD"] = "Copies [HL] to [DE], then decrements HL, DE and BC.",
        ["LDDR"] = "Repeats LDD until BC is zero.",
        ["LDI"] = "Copies [HL] to [DE], then increments HL and DE and decrements BC.",
        ["LDIR"] = "Repeats LDI until BC is zero.",
        ["NEG"] = "Negates A (0 - A).",
        ["NOP"] = "Does nothing.",
        ["OR"] = "ORs the operand into A.",
        ["OTDR"] = "Repeats OUTD until B is zero.",
        ["OTIR"] = "Repeats OUTI until B is zero.",
        ["OUT"] = "Writes a register, A or zero to an I/O port.",
        ["OUTD"] = "Decrements B, writes [HL] to port C, then decrements HL.",
        ["OUTI"] = "Decrements B, writes [HL] to port C, then increments HL.",
        ["POP"] = "Pulls a register pair from the stack.",
        ["PUSH"] = "Pushes a register pair onto the stack.",
        ["RES"] = "Clears a bit of a register or memory.",
        ["RET"] = "Returns from a subroutine, optionally on a condition.",
        ["RETI"] = "Returns from a maskable interrupt, signalling Z80 peripherals.",
        ["RETN"] = "Returns from a non-maskable interrupt, restoring IFF1 from IFF2.",
        ["RL"] = "Rotates left through the carry.",
        ["RLA"] = "Rotates A left through the carry.",
        ["RLC"] = "Rotates left; bit 7 goes to the carry and bit 0.",
        ["RLCA"] = "Rotates A left; bit 7 goes to the carry and bit 0.",
        ["RLD"] = "Rotates the BCD digits of A's low nibble and [HL] left.",
        ["RR"] = "Rotates right through the carry.",
        ["RRA"] = "Rotates A right through the carry.",
        ["RRC"] = "Rotates right; bit 0 goes to the carry and bit 7.",
        ["RRCA"] = "Rotates A right; bit 0 goes to the carry and bit 7.",
        ["RRD"] = "Rotates the BCD digits of A's low nibble and [HL] right.",
        ["RST"] = "Calls a restart address: $00, $08, $10, $18, $20, $28, $30 or $38.",
        ["SBC"] = "Subtracts the operand and the carry from A, or a register pair and the carry from HL.",
        ["SCF"] = "Sets the carry.",
        ["SET"] = "Sets a bit of a register or memory.",
        ["SLA"] = "Shifts left; bit 7 goes to the carry and bit 0 is cleared.",
        ["SLL"] = "Shifts left; bit 7 goes to the carry and bit 0 is set (undocumented).",
        ["SRA"] = "Shifts right; bit 0 goes to the carry and bit 7 is kept.",
        ["SRL"] = "Shifts right; bit 0 goes to the carry and bit 7 is cleared.",
        ["SUB"] = "Subtracts the operand from A.",
        ["XOR"] = "Exclusive-ORs the operand into A."
    };

    // Lists a Z80 mnemonic's canonical encodings: its operands, opcode bytes with their fields, and T-states.
    private static string? DescribeZ80(string mnemonic, InstructionSet set) => DescribeEncoded(s_z80, mnemonic, set, "T-states");

    // Lists a mnemonic's canonical encodings from an instruction-set description: its operands, opcode bytes with
    // their fields, and clock cycles.
    private static string? DescribeEncoded(
        Dictionary<string, string> docs,
        string mnemonic,
        InstructionSet set,
        string cyclesHeading)
    {
        if (!docs.TryGetValue(mnemonic, out string? summary)) { return null; }
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
            string flags = EncodingFlags(set, encoding).Text;
            rows.Add($"| `{mnemonic.ToUpperInvariant()}{operands}`{note} | `{Bytes(value, form)}` | {cycles} | {flags} |");
        }

        string header = $"| Operands | Opcode | {cyclesHeading} | Flags |\n| --- | --- | --- | --- |";
        string table = rows.Count == 0 ? "" : $"\n\n{header}\n{string.Join('\n', rows)}";
        return $"**{mnemonic.ToUpperInvariant()}**: {summary}\n\nFlags: {MnemonicFlags(mnemonic, set).Text}{table}";
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

    // A bit number adds 8 per bit to the last opcode byte, a restart its address, and a restart number 8 per number.
    private static string Opcode(IsaEncoding encoding, OperandForm form, int index)
    {
        string hex = encoding.OpcodeByte(index).ToString("X2", CultureInfo.InvariantCulture);
        if (index != encoding.OpcodeLength - 1 || form.OpcodeField < 0) { return hex; }
        return form.Field(form.OpcodeField) switch
        {
            OperandFieldKind.BitNumber => $"{hex}+8b",
            OperandFieldKind.RestartNumber => $"{hex}+8n",
            _ => $"{hex}+p"
        };
    }
}
