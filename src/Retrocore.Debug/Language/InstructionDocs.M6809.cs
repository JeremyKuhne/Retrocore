// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Isa;
using System.Globalization;

namespace Retrocore.Debug.Language;

internal static partial class InstructionDocs
{
    // What each MC6809 instruction does; the flags it changes come from the description's effects lines.
    private static readonly Dictionary<string, string> s_m6809 = new(StringComparer.OrdinalIgnoreCase)
    {
        ["ABX"] = "Adds unsigned B to X.",
        ["ADCA"] = "Adds memory and the carry to A.",
        ["ADCB"] = "Adds memory and the carry to B.",
        ["ADDA"] = "Adds memory to A.",
        ["ADDB"] = "Adds memory to B.",
        ["ADDD"] = "Adds a 16-bit value to D.",
        ["ANDA"] = "ANDs memory into A.",
        ["ANDB"] = "ANDs memory into B.",
        ["ANDCC"] = "ANDs an immediate mask into CC, clearing flags.",
        ["ASL"] = "Shifts memory left one bit; bit 7 goes to C.",
        ["ASLA"] = "Shifts A left one bit; bit 7 goes to C.",
        ["ASLB"] = "Shifts B left one bit; bit 7 goes to C.",
        ["ASR"] = "Arithmetic right shift of memory; bit 7 is kept and bit 0 goes to C.",
        ["ASRA"] = "Arithmetic right shift of A; bit 7 is kept and bit 0 goes to C.",
        ["ASRB"] = "Arithmetic right shift of B; bit 7 is kept and bit 0 goes to C.",
        ["BCC"] = "Branches when C is clear (higher or same, unsigned).",
        ["BCS"] = "Branches when C is set (lower, unsigned).",
        ["BEQ"] = "Branches when Z is set.",
        ["BGE"] = "Branches when N equals V (greater or equal, signed).",
        ["BGT"] = "Branches when Z is clear and N equals V (greater, signed).",
        ["BHI"] = "Branches when C and Z are clear (higher, unsigned).",
        ["BHS"] = "Branches when C is clear (synonym of BCC).",
        ["BITA"] = "Tests memory against A (A AND memory, result discarded).",
        ["BITB"] = "Tests memory against B (B AND memory, result discarded).",
        ["BLE"] = "Branches when Z is set or N differs from V (less or equal, signed).",
        ["BLO"] = "Branches when C is set (synonym of BCS).",
        ["BLS"] = "Branches when C or Z is set (lower or same, unsigned).",
        ["BLT"] = "Branches when N differs from V (less, signed).",
        ["BMI"] = "Branches when N is set.",
        ["BNE"] = "Branches when Z is clear.",
        ["BPL"] = "Branches when N is clear.",
        ["BRA"] = "Branches always (8-bit signed displacement).",
        ["BRN"] = "Branches never (three-cycle two-byte no-op).",
        ["BSR"] = "Pushes PC onto S and branches to a subroutine (8-bit displacement).",
        ["BVC"] = "Branches when V is clear.",
        ["BVS"] = "Branches when V is set.",
        ["CLR"] = "Clears memory to zero.",
        ["CLRA"] = "Clears A to zero.",
        ["CLRB"] = "Clears B to zero.",
        ["CMPA"] = "Compares A with memory (A - memory).",
        ["CMPB"] = "Compares B with memory (B - memory).",
        ["CMPD"] = "Compares D with a 16-bit value.",
        ["CMPS"] = "Compares S with a 16-bit value.",
        ["CMPU"] = "Compares U with a 16-bit value.",
        ["CMPX"] = "Compares X with a 16-bit value.",
        ["CMPY"] = "Compares Y with a 16-bit value.",
        ["COM"] = "One's-complements memory and sets C.",
        ["COMA"] = "One's-complements A and sets C.",
        ["COMB"] = "One's-complements B and sets C.",
        ["CWAI"] = "ANDs CC with immediate, sets E, stacks all registers on S, and waits for an interrupt.",
        ["DAA"] = "Decimal-adjusts A after packed BCD addition.",
        ["DEC"] = "Decrements memory.",
        ["DECA"] = "Decrements A.",
        ["DECB"] = "Decrements B.",
        ["EORA"] = "Exclusive-ORs memory into A.",
        ["EORB"] = "Exclusive-ORs memory into B.",
        ["EXG"] = "Exchanges two registers of equal width.",
        ["INC"] = "Increments memory.",
        ["INCA"] = "Increments A.",
        ["INCB"] = "Increments B.",
        ["JMP"] = "Jumps to the effective address.",
        ["JSR"] = "Pushes PC onto S and jumps to a subroutine.",
        ["LBCC"] = "Long branch when C is clear.",
        ["LBCS"] = "Long branch when C is set.",
        ["LBEQ"] = "Long branch when Z is set.",
        ["LBGE"] = "Long branch when N equals V.",
        ["LBGT"] = "Long branch when Z is clear and N equals V.",
        ["LBHI"] = "Long branch when C and Z are clear.",
        ["LBHS"] = "Long branch when C is clear (synonym of LBCC).",
        ["LBLE"] = "Long branch when Z is set or N differs from V.",
        ["LBLO"] = "Long branch when C is set (synonym of LBCS).",
        ["LBLS"] = "Long branch when C or Z is set.",
        ["LBLT"] = "Long branch when N differs from V.",
        ["LBMI"] = "Long branch when N is set.",
        ["LBNE"] = "Long branch when Z is clear.",
        ["LBPL"] = "Long branch when N is clear.",
        ["LBRA"] = "Long branch always (16-bit displacement).",
        ["LBRN"] = "Long branch never.",
        ["LBSR"] = "Pushes PC onto S and branches to a subroutine (16-bit displacement).",
        ["LBVC"] = "Long branch when V is clear.",
        ["LBVS"] = "Long branch when V is set.",
        ["LDA"] = "Loads A from memory.",
        ["LDB"] = "Loads B from memory.",
        ["LDD"] = "Loads D (A:B) from memory.",
        ["LDS"] = "Loads S from memory and arms NMI.",
        ["LDU"] = "Loads U from memory.",
        ["LDX"] = "Loads X from memory.",
        ["LDY"] = "Loads Y from memory.",
        ["LEAS"] = "Loads S with the indexed effective address and arms NMI.",
        ["LEAU"] = "Loads U with the indexed effective address.",
        ["LEAX"] = "Loads X with the indexed effective address.",
        ["LEAY"] = "Loads Y with the indexed effective address.",
        ["LSL"] = "Logical left shift of memory (synonym of ASL).",
        ["LSLA"] = "Logical left shift of A (synonym of ASLA).",
        ["LSLB"] = "Logical left shift of B (synonym of ASLB).",
        ["LSR"] = "Logical right shift of memory; 0 enters bit 7 and bit 0 goes to C.",
        ["LSRA"] = "Logical right shift of A; 0 enters bit 7 and bit 0 goes to C.",
        ["LSRB"] = "Logical right shift of B; 0 enters bit 7 and bit 0 goes to C.",
        ["MUL"] = "Unsigned 8x8 multiply: D = A * B; C takes bit 7 of B.",
        ["NEG"] = "Two's-complements memory (0 - memory).",
        ["NEGA"] = "Two's-complements A.",
        ["NEGB"] = "Two's-complements B.",
        ["NOP"] = "Does nothing.",
        ["ORA"] = "ORs memory into A.",
        ["ORB"] = "ORs memory into B.",
        ["ORCC"] = "ORs an immediate mask into CC, setting flags.",
        ["PSHS"] = "Pushes selected registers onto the system stack S.",
        ["PSHU"] = "Pushes selected registers onto the user stack U.",
        ["PULS"] = "Pulls selected registers from the system stack S.",
        ["PULU"] = "Pulls selected registers from the user stack U (arms NMI when S is pulled).",
        ["ROL"] = "Rotates memory left through C.",
        ["ROLA"] = "Rotates A left through C.",
        ["ROLB"] = "Rotates B left through C.",
        ["ROR"] = "Rotates memory right through C.",
        ["RORA"] = "Rotates A right through C.",
        ["RORB"] = "Rotates B right through C.",
        ["RTI"] = "Returns from an interrupt: pulls CC, then all registers if E is set, then PC.",
        ["RTS"] = "Returns from a subroutine: pulls PC from S.",
        ["SBCA"] = "Subtracts memory and borrow C from A.",
        ["SBCB"] = "Subtracts memory and borrow C from B.",
        ["SEX"] = "Sign-extends B into D. V is unchanged, though the datasheet says cleared.",
        ["STA"] = "Stores A to memory.",
        ["STB"] = "Stores B to memory.",
        ["STD"] = "Stores D to memory.",
        ["STS"] = "Stores S to memory.",
        ["STU"] = "Stores U to memory.",
        ["STX"] = "Stores X to memory.",
        ["STY"] = "Stores Y to memory.",
        ["SUBA"] = "Subtracts memory from A.",
        ["SUBB"] = "Subtracts memory from B.",
        ["SUBD"] = "Subtracts a 16-bit value from D.",
        ["SWI"] = "Software interrupt: sets E, stacks all registers on S, sets I and F, and vectors via $FFFA.",
        ["SWI2"] = "Software interrupt 2: sets E, stacks all registers on S, and vectors via $FFF4.",
        ["SWI3"] = "Software interrupt 3: sets E, stacks all registers on S, and vectors via $FFF2.",
        ["SYNC"] = "Stops the processor until an interrupt line is asserted.",
        ["TFR"] = "Copies one register to another of equal width.",
        ["TST"] = "Tests memory for negative or zero.",
        ["TSTA"] = "Tests A for negative or zero.",
        ["TSTB"] = "Tests B for negative or zero.",
        ["X18"] = "Undocumented: shifts each CC flag up one place, masked by the next byte, and clears C.",
        ["XADDD"] = "Undocumented: adds a 16-bit value to D for the flags only; D is unchanged.",
        ["XADDU"] = "Undocumented: adds a 16-bit value to U with its high byte as $FF, for the flags only.",
        ["XANDCC"] = "Undocumented: ANDCC one cycle slower.",
        ["XCLRA"] = "Undocumented: clears A, leaving C unchanged.",
        ["XCLRB"] = "Undocumented: clears B, leaving C unchanged.",
        ["XDEC"] = "Undocumented: DEC that clears C when memory was zero and sets it otherwise.",
        ["XDECA"] = "Undocumented: DECA that clears C when A was zero and sets it otherwise.",
        ["XDECB"] = "Undocumented: DECB that clears C when B was zero and sets it otherwise.",
        ["XFIRQ"] = "Undocumented: stacks every register, CC without setting E, and jumps through the FIRQ vector.",
        ["XHCF"] = "Undocumented: halt and catch fire; reads up through memory a byte a cycle until RESET.",
        ["XNC"] = "Undocumented: NEG of memory when C is clear, COM when C is set.",
        ["XNCA"] = "Undocumented: NEGA when C is clear, COMA when C is set.",
        ["XNCB"] = "Undocumented: NEGB when C is clear, COMB when C is set.",
        ["XRES"] = "Undocumented: stacks every register, CC without setting E, and jumps through the reset vector.",
        ["XSTA"] = "Undocumented store immediate: reads its operand and stores nothing.",
        ["XSTB"] = "Undocumented store immediate: reads its operand and stores nothing.",
        ["XSTS"] = "Undocumented store immediate: writes S's low byte over the operand's low byte.",
        ["XSTU"] = "Undocumented store immediate: writes U's low byte over the operand's low byte.",
        ["XSTX"] = "Undocumented store immediate: writes X's low byte over the operand's low byte.",
        ["XSTY"] = "Undocumented store immediate: writes Y's low byte over the operand's low byte.",
        ["XSWI2"] = "Undocumented: SWI2 without setting E in the stacked CC."
    };

    private static string? DescribeM6809(string mnemonic, InstructionSet set)
    {
        if (!s_m6809.TryGetValue(mnemonic, out string? summary)) { return null; }
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
            string mode = M6809ModeText(form);
            string cycles = value.Cycles == value.CyclesTaken
                ? form.HasVariableSize
                    ? $"{value.Cycles}+"
                    : form.FieldCount == 1 && form.Field(0) is OperandFieldKind.SystemStackMask or OperandFieldKind.UserStackMask
                        ? $"{value.Cycles}+n"
                        : value.Cycles.ToString(CultureInfo.InvariantCulture)
                : $"{value.CyclesTaken}/{value.Cycles}";

            rows.Add($"| {mode} | `{M6809Bytes(value, form)}` | {cycles} | {EncodingFlags(set, encoding).Text} |");
        }

        string header = "| Mode | Opcode | Cycles | Flags |\n| --- | --- | --- | --- |";
        string table = rows.Count == 0 ? "" : $"\n\n{header}\n{string.Join('\n', rows)}";
        return $"**{mnemonic.ToUpperInvariant()}**: {summary}\n\nFlags: {MnemonicFlags(mnemonic, set).Text}{table}";
    }

    private static string M6809ModeText(OperandForm form) => form.Name switch
    {
        "Implied" => "inherent",
        "Immediate8" => "immediate `#n`",
        "Immediate16" => "immediate `#nn`",
        "Direct" => "direct `<dp`",
        "Indexed" => "indexed `,R` / `[...]`",
        "Extended" => "extended `>addr`",
        "Relative8" => "relative `label`",
        "Relative16" => "long relative `label`",
        "Pair" => "register pair `R1,R2`",
        "SystemStack" => "register list `CC,A,...,PC`",
        "UserStack" => "register list `CC,A,...,PC`",
        _ => form.Name
    };

    private static string M6809Bytes(IsaEncoding encoding, OperandForm form)
    {
        List<string> parts = [];
        for (int index = 0; index < encoding.OpcodeLength; index++)
        {
            parts.Add(encoding.OpcodeByte(index).ToString("X2", CultureInfo.InvariantCulture));
        }

        foreach (OperandFieldKind field in form.Fields)
        {
            parts.Add(field switch
            {
                OperandFieldKind.Byte => "n",
                OperandFieldKind.Word => "nn nn",
                OperandFieldKind.Relative8 => "dd",
                OperandFieldKind.Relative16 => "dd dd",
                OperandFieldKind.IndexedPostbyte => "pb [..]",
                OperandFieldKind.RegisterPair => "r1:r2",
                _ => "mask"
            });
        }

        return string.Join(' ', parts);
    }
}
