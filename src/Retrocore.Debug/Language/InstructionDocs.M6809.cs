// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Globalization;
using Retrocore.Isa;

namespace Retrocore.Debug.Language;

internal static partial class InstructionDocs
{
    private static readonly Dictionary<string, (string Summary, string Flags)> s_m6809 = new(StringComparer.OrdinalIgnoreCase)
    {
        ["ABX"] = ("Adds unsigned B to X.", "none"),
        ["ADCA"] = ("Adds memory and the carry to A.", "H N Z V C"),
        ["ADCB"] = ("Adds memory and the carry to B.", "H N Z V C"),
        ["ADDA"] = ("Adds memory to A.", "H N Z V C"),
        ["ADDB"] = ("Adds memory to B.", "H N Z V C"),
        ["ADDD"] = ("Adds a 16-bit value to D.", "N Z V C"),
        ["ANDA"] = ("ANDs memory into A.", "N Z V"),
        ["ANDB"] = ("ANDs memory into B.", "N Z V"),
        ["ANDCC"] = ("ANDs an immediate mask into CC, clearing flags.", "all"),
        ["ASL"] = ("Shifts memory left one bit; bit 7 goes to C.", "N Z V C"),
        ["ASLA"] = ("Shifts A left one bit; bit 7 goes to C.", "N Z V C"),
        ["ASLB"] = ("Shifts B left one bit; bit 7 goes to C.", "N Z V C"),
        ["ASR"] = ("Arithmetic right shift of memory; bit 7 is kept and bit 0 goes to C.", "N Z C"),
        ["ASRA"] = ("Arithmetic right shift of A; bit 7 is kept and bit 0 goes to C.", "N Z C"),
        ["ASRB"] = ("Arithmetic right shift of B; bit 7 is kept and bit 0 goes to C.", "N Z C"),
        ["BCC"] = ("Branches when C is clear (higher or same, unsigned).", "none"),
        ["BCS"] = ("Branches when C is set (lower, unsigned).", "none"),
        ["BEQ"] = ("Branches when Z is set.", "none"),
        ["BGE"] = ("Branches when N equals V (greater or equal, signed).", "none"),
        ["BGT"] = ("Branches when Z is clear and N equals V (greater, signed).", "none"),
        ["BHI"] = ("Branches when C and Z are clear (higher, unsigned).", "none"),
        ["BHS"] = ("Branches when C is clear (synonym of BCC).", "none"),
        ["BITA"] = ("Tests memory against A (A AND memory, result discarded).", "N Z V"),
        ["BITB"] = ("Tests memory against B (B AND memory, result discarded).", "N Z V"),
        ["BLE"] = ("Branches when Z is set or N differs from V (less or equal, signed).", "none"),
        ["BLO"] = ("Branches when C is set (synonym of BCS).", "none"),
        ["BLS"] = ("Branches when C or Z is set (lower or same, unsigned).", "none"),
        ["BLT"] = ("Branches when N differs from V (less, signed).", "none"),
        ["BMI"] = ("Branches when N is set.", "none"),
        ["BNE"] = ("Branches when Z is clear.", "none"),
        ["BPL"] = ("Branches when N is clear.", "none"),
        ["BRA"] = ("Branches always (8-bit signed displacement).", "none"),
        ["BRN"] = ("Branches never (three-cycle two-byte no-op).", "none"),
        ["BSR"] = ("Pushes PC onto S and branches to a subroutine (8-bit displacement).", "none"),
        ["BVC"] = ("Branches when V is clear.", "none"),
        ["BVS"] = ("Branches when V is set.", "none"),
        ["CLR"] = ("Clears memory to zero.", "N Z V C"),
        ["CLRA"] = ("Clears A to zero.", "N Z V C"),
        ["CLRB"] = ("Clears B to zero.", "N Z V C"),
        ["CMPA"] = ("Compares A with memory (A - memory).", "N Z V C"),
        ["CMPB"] = ("Compares B with memory (B - memory).", "N Z V C"),
        ["CMPD"] = ("Compares D with a 16-bit value.", "N Z V C"),
        ["CMPS"] = ("Compares S with a 16-bit value.", "N Z V C"),
        ["CMPU"] = ("Compares U with a 16-bit value.", "N Z V C"),
        ["CMPX"] = ("Compares X with a 16-bit value.", "N Z V C"),
        ["CMPY"] = ("Compares Y with a 16-bit value.", "N Z V C"),
        ["COM"] = ("One's-complements memory and sets C.", "N Z V C"),
        ["COMA"] = ("One's-complements A and sets C.", "N Z V C"),
        ["COMB"] = ("One's-complements B and sets C.", "N Z V C"),
        ["CWAI"] = ("ANDs CC with immediate, sets E, stacks all registers on S, and waits for an interrupt.", "all"),
        ["DAA"] = ("Decimal-adjusts A after packed BCD addition.", "N Z V C"),
        ["DEC"] = ("Decrements memory.", "N Z V"),
        ["DECA"] = ("Decrements A.", "N Z V"),
        ["DECB"] = ("Decrements B.", "N Z V"),
        ["EORA"] = ("Exclusive-ORs memory into A.", "N Z V"),
        ["EORB"] = ("Exclusive-ORs memory into B.", "N Z V"),
        ["EXG"] = ("Exchanges two registers of equal width.", "none (CC when named)"),
        ["INC"] = ("Increments memory.", "N Z V"),
        ["INCA"] = ("Increments A.", "N Z V"),
        ["INCB"] = ("Increments B.", "N Z V"),
        ["JMP"] = ("Jumps to the effective address.", "none"),
        ["JSR"] = ("Pushes PC onto S and jumps to a subroutine.", "none"),
        ["LBCC"] = ("Long branch when C is clear.", "none"),
        ["LBCS"] = ("Long branch when C is set.", "none"),
        ["LBEQ"] = ("Long branch when Z is set.", "none"),
        ["LBGE"] = ("Long branch when N equals V.", "none"),
        ["LBGT"] = ("Long branch when Z is clear and N equals V.", "none"),
        ["LBHI"] = ("Long branch when C and Z are clear.", "none"),
        ["LBHS"] = ("Long branch when C is clear (synonym of LBCC).", "none"),
        ["LBLE"] = ("Long branch when Z is set or N differs from V.", "none"),
        ["LBLO"] = ("Long branch when C is set (synonym of LBCS).", "none"),
        ["LBLS"] = ("Long branch when C or Z is set.", "none"),
        ["LBLT"] = ("Long branch when N differs from V.", "none"),
        ["LBMI"] = ("Long branch when N is set.", "none"),
        ["LBNE"] = ("Long branch when Z is clear.", "none"),
        ["LBPL"] = ("Long branch when N is clear.", "none"),
        ["LBRA"] = ("Long branch always (16-bit displacement).", "none"),
        ["LBRN"] = ("Long branch never.", "none"),
        ["LBSR"] = ("Pushes PC onto S and branches to a subroutine (16-bit displacement).", "none"),
        ["LBVC"] = ("Long branch when V is clear.", "none"),
        ["LBVS"] = ("Long branch when V is set.", "none"),
        ["LDA"] = ("Loads A from memory.", "N Z V"),
        ["LDB"] = ("Loads B from memory.", "N Z V"),
        ["LDD"] = ("Loads D (A:B) from memory.", "N Z V"),
        ["LDS"] = ("Loads S from memory and arms NMI.", "N Z V"),
        ["LDU"] = ("Loads U from memory.", "N Z V"),
        ["LDX"] = ("Loads X from memory.", "N Z V"),
        ["LDY"] = ("Loads Y from memory.", "N Z V"),
        ["LEAS"] = ("Loads S with the indexed effective address and arms NMI.", "none"),
        ["LEAU"] = ("Loads U with the indexed effective address.", "none"),
        ["LEAX"] = ("Loads X with the indexed effective address.", "Z"),
        ["LEAY"] = ("Loads Y with the indexed effective address.", "Z"),
        ["LSL"] = ("Logical left shift of memory (synonym of ASL).", "N Z V C"),
        ["LSLA"] = ("Logical left shift of A (synonym of ASLA).", "N Z V C"),
        ["LSLB"] = ("Logical left shift of B (synonym of ASLB).", "N Z V C"),
        ["LSR"] = ("Logical right shift of memory; 0 enters bit 7 and bit 0 goes to C.", "N Z C"),
        ["LSRA"] = ("Logical right shift of A; 0 enters bit 7 and bit 0 goes to C.", "N Z C"),
        ["LSRB"] = ("Logical right shift of B; 0 enters bit 7 and bit 0 goes to C.", "N Z C"),
        ["MUL"] = ("Unsigned 8x8 multiply: D = A * B; C takes bit 7 of B.", "Z C"),
        ["NEG"] = ("Two's-complements memory (0 - memory).", "N Z V C"),
        ["NEGA"] = ("Two's-complements A.", "N Z V C"),
        ["NEGB"] = ("Two's-complements B.", "N Z V C"),
        ["NOP"] = ("Does nothing.", "none"),
        ["ORA"] = ("ORs memory into A.", "N Z V"),
        ["ORB"] = ("ORs memory into B.", "N Z V"),
        ["ORCC"] = ("ORs an immediate mask into CC, setting flags.", "all"),
        ["PSHS"] = ("Pushes selected registers onto the system stack S.", "none"),
        ["PSHU"] = ("Pushes selected registers onto the user stack U.", "none"),
        ["PULS"] = ("Pulls selected registers from the system stack S.", "none (CC when pulled)"),
        ["PULU"] = ("Pulls selected registers from the user stack U (arms NMI when S is pulled).", "none (CC when pulled)"),
        ["ROL"] = ("Rotates memory left through C.", "N Z V C"),
        ["ROLA"] = ("Rotates A left through C.", "N Z V C"),
        ["ROLB"] = ("Rotates B left through C.", "N Z V C"),
        ["ROR"] = ("Rotates memory right through C.", "N Z C"),
        ["RORA"] = ("Rotates A right through C.", "N Z C"),
        ["RORB"] = ("Rotates B right through C.", "N Z C"),
        ["RTI"] = ("Returns from an interrupt: pulls CC, then all registers if E is set, then PC.", "all"),
        ["RTS"] = ("Returns from a subroutine: pulls PC from S.", "none"),
        ["SBCA"] = ("Subtracts memory and borrow C from A.", "N Z V C"),
        ["SBCB"] = ("Subtracts memory and borrow C from B.", "N Z V C"),
        ["SEX"] = ("Sign-extends B into D. V is unchanged, though the datasheet says cleared.", "N Z"),
        ["STA"] = ("Stores A to memory.", "N Z V"),
        ["STB"] = ("Stores B to memory.", "N Z V"),
        ["STD"] = ("Stores D to memory.", "N Z V"),
        ["STS"] = ("Stores S to memory.", "N Z V"),
        ["STU"] = ("Stores U to memory.", "N Z V"),
        ["STX"] = ("Stores X to memory.", "N Z V"),
        ["STY"] = ("Stores Y to memory.", "N Z V"),
        ["SUBA"] = ("Subtracts memory from A.", "N Z V C"),
        ["SUBB"] = ("Subtracts memory from B.", "N Z V C"),
        ["SUBD"] = ("Subtracts a 16-bit value from D.", "N Z V C"),
        ["SWI"] = ("Software interrupt: sets E, stacks all registers on S, sets I and F, and vectors via $FFFA.", "E F I"),
        ["SWI2"] = ("Software interrupt 2: sets E, stacks all registers on S, and vectors via $FFF4.", "E"),
        ["SWI3"] = ("Software interrupt 3: sets E, stacks all registers on S, and vectors via $FFF2.", "E"),
        ["SYNC"] = ("Stops the processor until an interrupt line is asserted.", "none"),
        ["TFR"] = ("Copies one register to another of equal width.", "none (CC when destination)"),
        ["TST"] = ("Tests memory for negative or zero.", "N Z V"),
        ["TSTA"] = ("Tests A for negative or zero.", "N Z V"),
        ["TSTB"] = ("Tests B for negative or zero.", "N Z V"),
        ["X18"] = ("Undocumented: shifts each CC flag up one place, masked by the next byte, and clears C.", "all"),
        ["XADDD"] = ("Undocumented: adds a 16-bit value to D for the flags only; D is unchanged.", "N Z V C"),
        ["XADDU"] = ("Undocumented: adds a 16-bit value to U with its high byte as $FF, for the flags only.", "N Z V C"),
        ["XANDCC"] = ("Undocumented: ANDCC one cycle slower.", "all"),
        ["XCLRA"] = ("Undocumented: clears A, leaving C unchanged.", "N Z V"),
        ["XCLRB"] = ("Undocumented: clears B, leaving C unchanged.", "N Z V"),
        ["XDEC"] = ("Undocumented: DEC that clears C when memory was zero and sets it otherwise.", "N Z V C"),
        ["XDECA"] = ("Undocumented: DECA that clears C when A was zero and sets it otherwise.", "N Z V C"),
        ["XDECB"] = ("Undocumented: DECB that clears C when B was zero and sets it otherwise.", "N Z V C"),
        ["XFIRQ"] = ("Undocumented: stacks every register, CC without setting E, and jumps through the FIRQ vector.", "none"),
        ["XHCF"] = ("Undocumented: halt and catch fire; reads up through memory a byte a cycle until RESET.", "none"),
        ["XNC"] = ("Undocumented: NEG of memory when C is clear, COM when C is set.", "N Z V C"),
        ["XNCA"] = ("Undocumented: NEGA when C is clear, COMA when C is set.", "N Z V C"),
        ["XNCB"] = ("Undocumented: NEGB when C is clear, COMB when C is set.", "N Z V C"),
        ["XRES"] = ("Undocumented: stacks every register, CC without setting E, and jumps through the reset vector.", "none"),
        ["XSTA"] = ("Undocumented store immediate: reads its operand and stores nothing.", "N Z V"),
        ["XSTB"] = ("Undocumented store immediate: reads its operand and stores nothing.", "N Z V"),
        ["XSTS"] = ("Undocumented store immediate: writes S's low byte over the operand's low byte.", "N Z V"),
        ["XSTU"] = ("Undocumented store immediate: writes U's low byte over the operand's low byte.", "N Z V"),
        ["XSTX"] = ("Undocumented store immediate: writes X's low byte over the operand's low byte.", "N Z V"),
        ["XSTY"] = ("Undocumented store immediate: writes Y's low byte over the operand's low byte.", "N Z V"),
        ["XSWI2"] = ("Undocumented: SWI2 without setting E in the stacked CC.", "none")
    };

    private static string? DescribeM6809(string mnemonic, InstructionSet set)
    {
        if (!s_m6809.TryGetValue(mnemonic, out (string Summary, string Flags) doc)) { return null; }
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

            rows.Add($"| {mode} | `{M6809Bytes(value, form)}` | {cycles} |");
        }

        string table = rows.Count == 0 ? "" : $"\n\n| Mode | Opcode | Cycles |\n| --- | --- | --- |\n{string.Join('\n', rows)}";
        return $"**{mnemonic.ToUpperInvariant()}**: {doc.Summary}\n\nFlags: {doc.Flags}{table}";
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
