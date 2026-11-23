; retrocore: style=strict
;; The disassembler's tables, $F962-$FA3F: each opcode's addressing mode and each mode's operand format, then the
;; operand characters and the packed mnemonics, which the Enhanced IIe's mini-assembler reads too.

; Disassembler, continued: the addressing modes and operand formats.
.scope Disassembler continued

;; The addressing modes, each the index of its format in <OperandFormats>.
;;
;; Members:
;;   INVALID = an opcode the 6502 does not have
;;   IMMEDIATE = #$nn
;;   ZERO_PAGE = $nn
;;   ABSOLUTE = $nnnn
;;   IMPLIED = no operand
;;   ACCUMULATOR = no operand either: the Monitor does not print "A"
;;   INDEXED_INDIRECT = ($nn,X)
;;   INDIRECT_INDEXED = ($nn),Y
;;   ZERO_PAGE_X = $nn,X
;;   ABSOLUTE_X = $nnnn,X
;;   ABSOLUTE_Y = $nnnn,Y
;;   INDIRECT = ($nnnn)
;;   ZERO_PAGE_Y = $nn,Y
;;   RELATIVE = $nnnn, the address a branch goes to
.enum AddressMode
    INVALID
    IMMEDIATE
    ZERO_PAGE
    ABSOLUTE
    IMPLIED
    ACCUMULATOR
    INDEXED_INDIRECT
    INDIRECT_INDEXED
    ZERO_PAGE_X
    ABSOLUTE_X
    ABSOLUTE_Y
    INDIRECT
    ZERO_PAGE_Y
    RELATIVE
.endenum

;; One row of <Disassembler::AddressingModes>: the modes of the even opcodes in one row of the opcode matrix, two
;; to a byte, the opcode with bit 1 clear in the low nibble and the one with it set in the high nibble.
;; Parameters:
;;   m0 = the mode of the row's opcode $x0
;;   m2 = $x2's
;;   m4 = $x4's
;;   m6 = $x6's
;;   m8 = $x8's
;;   mA = $xA's
;;   mC = $xC's
;;   mE = $xE's
.macro ModeRow m0, m2, m4, m6, m8, mA, mC, mE
    .byte AddressMode::m0 | AddressMode::m2 << 4, AddressMode::m4 | AddressMode::m6 << 4
    .byte AddressMode::m8 | AddressMode::mA << 4, AddressMode::mC | AddressMode::mE << 4
.endmacro

;; Each opcode's addressing mode, two modes to a byte.
;;
;; <Disassembler::Decode> reads an even opcode's at opcode / 4, so each of the first 16 rows is the even columns of
;; one row of the opcode matrix. The odd opcodes, the ORA..SBC group, take their mode from bits 2-4 alone, from the
;; last row. Decode finds the opcodes ending in binary 11, and $89, invalid before it reads the table.
;; Also: FMT1 (A2RM78, A2RM79, IIEROM82, IIETRM85)
AddressingModes:
    ; $00-$0E: BRK - - ASL PHP ASL - ASL
    ModeRow IMPLIED, INVALID, INVALID, ZERO_PAGE, IMPLIED, ACCUMULATOR, INVALID, ABSOLUTE
    ; $10-$1E: BPL - - ASL CLC - - ASL
    ModeRow RELATIVE, INVALID, INVALID, ZERO_PAGE_X, IMPLIED, INVALID, INVALID, ABSOLUTE_X
    ; $20-$2E: JSR - BIT ROL PLP ROL BIT ROL
    ModeRow ABSOLUTE, INVALID, ZERO_PAGE, ZERO_PAGE, IMPLIED, ACCUMULATOR, ABSOLUTE, ABSOLUTE
    ; $30-$3E: BMI - - ROL SEC - - ROL
    ModeRow RELATIVE, INVALID, INVALID, ZERO_PAGE_X, IMPLIED, INVALID, INVALID, ABSOLUTE_X
    ; $40-$4E: RTI - - LSR PHA LSR JMP LSR
    ModeRow IMPLIED, INVALID, INVALID, ZERO_PAGE, IMPLIED, ACCUMULATOR, ABSOLUTE, ABSOLUTE
    ; $50-$5E: BVC - - LSR CLI - - LSR
    ModeRow RELATIVE, INVALID, INVALID, ZERO_PAGE_X, IMPLIED, INVALID, INVALID, ABSOLUTE_X
    ; $60-$6E: RTS - - ROR PLA ROR JMP ROR
    ModeRow IMPLIED, INVALID, INVALID, ZERO_PAGE, IMPLIED, ACCUMULATOR, INDIRECT, ABSOLUTE
    ; $70-$7E: BVS - - ROR SEI - - ROR
    ModeRow RELATIVE, INVALID, INVALID, ZERO_PAGE_X, IMPLIED, INVALID, INVALID, ABSOLUTE_X
    ; $80-$8E: - - STY STX DEY TXA STY STX
    ModeRow INVALID, INVALID, ZERO_PAGE, ZERO_PAGE, IMPLIED, IMPLIED, ABSOLUTE, ABSOLUTE
    ; $90-$9E: BCC - STY STX TYA TXS - -
    ModeRow RELATIVE, INVALID, ZERO_PAGE_X, ZERO_PAGE_Y, IMPLIED, IMPLIED, INVALID, INVALID
    ; $A0-$AE: LDY LDX LDY LDX TAY TAX LDY LDX
    ModeRow IMMEDIATE, IMMEDIATE, ZERO_PAGE, ZERO_PAGE, IMPLIED, IMPLIED, ABSOLUTE, ABSOLUTE
    ; $B0-$BE: BCS - LDY LDX CLV TSX LDY LDX
    ModeRow RELATIVE, INVALID, ZERO_PAGE_X, ZERO_PAGE_Y, IMPLIED, IMPLIED, ABSOLUTE_X, ABSOLUTE_Y
    ; $C0-$CE: CPY - CPY DEC INY DEX CPY DEC
    ModeRow IMMEDIATE, INVALID, ZERO_PAGE, ZERO_PAGE, IMPLIED, IMPLIED, ABSOLUTE, ABSOLUTE
    ; $D0-$DE: BNE - - DEC CLD - - DEC
    ModeRow RELATIVE, INVALID, INVALID, ZERO_PAGE_X, IMPLIED, INVALID, INVALID, ABSOLUTE_X
    ; $E0-$EE: CPX - CPX INC INX NOP CPX INC
    ModeRow IMMEDIATE, INVALID, ZERO_PAGE, ZERO_PAGE, IMPLIED, IMPLIED, ABSOLUTE, ABSOLUTE
    ; $F0-$FE: BEQ - - INC SED - - INC
    ModeRow RELATIVE, INVALID, INVALID, ZERO_PAGE_X, IMPLIED, INVALID, INVALID, ABSOLUTE_X
    ; $x1-$xD, ORA..SBC, by bits 2-4.
    ModeRow INDEXED_INDIRECT, ZERO_PAGE, IMMEDIATE, ABSOLUTE, INDIRECT_INDEXED, ZERO_PAGE_X, ABSOLUTE_Y, ABSOLUTE_X
.assert * - AddressingModes = 17 * 4, "Sixteen rows of the opcode matrix, then the odd opcodes' row."

; The bits of an operand format, from the top: what <PrintInstruction> prints around the operand's bytes, from
; <FormatCharacter1> and <FormatCharacter2>. Bits 0-1 are the operand's length.

;; Prints "$" before the operand.
OPERAND_DOLLAR = $80

;; Prints "($" before the operand.
OPERAND_INDIRECT = $40

;; Prints "#$" before the operand.
OPERAND_IMMEDIATE = $20

;; Prints ",X" after the operand.
OPERAND_X = $10

;; Prints ")" after the operand.
OPERAND_CLOSE = $08

;; Prints ",Y" after the operand.
OPERAND_Y = $04

;; The relative mode's format: "$", then the branch's target, which <PrintInstruction> prints instead of the
;; operand byte.
;;
;; Its ",X", ")" and ",Y" bits never print, because the target ends the line. They are set so that the format,
;; shifted left past the "$", "($" and "#$" bits, is $E8, which no other format reaches: that is how
;; <PrintInstruction::Operand> tells a branch.
RELATIVE_FORMAT = OPERAND_DOLLAR | OPERAND_X | OPERAND_CLOSE | OPERAND_Y | 1

;; One entry of <Disassembler::OperandFormats>, checked to sit at its mode's index.
;; Parameters:
;;   mode = the addressing mode, a member of <Disassembler::AddressMode>
;;   format = its format: the <Disassembler::OPERAND_DOLLAR> and other bits, and the operand's length
.macro OperandFormat mode, format
    .assert * - OperandFormats = AddressMode::mode, "Each format sits at its mode's index."
    .byte format
.endmacro

;; Each addressing mode's operand format: the characters to print around the operand, and its length.
;; Also: FMT2 (A2RM78, A2RM79, IIEROM82, IIETRM85)
OperandFormats:
    OperandFormat INVALID, 0
    OperandFormat IMMEDIATE, OPERAND_IMMEDIATE | 1
    OperandFormat ZERO_PAGE, OPERAND_DOLLAR | 1
    OperandFormat ABSOLUTE, OPERAND_DOLLAR | 2
    OperandFormat IMPLIED, 0
    OperandFormat ACCUMULATOR, 0
    OperandFormat INDEXED_INDIRECT, OPERAND_INDIRECT | OPERAND_X | OPERAND_CLOSE | 1
    OperandFormat INDIRECT_INDEXED, OPERAND_INDIRECT | OPERAND_CLOSE | OPERAND_Y | 1
    OperandFormat ZERO_PAGE_X, OPERAND_DOLLAR | OPERAND_X | 1
    OperandFormat ABSOLUTE_X, OPERAND_DOLLAR | OPERAND_X | 2
    OperandFormat ABSOLUTE_Y, OPERAND_DOLLAR | OPERAND_Y | 2
    OperandFormat INDIRECT, OPERAND_INDIRECT | OPERAND_CLOSE | 2
    OperandFormat ZERO_PAGE_Y, OPERAND_DOLLAR | OPERAND_Y | 1
    OperandFormat RELATIVE, RELATIVE_FORMAT

.endscope

;; The first character of each operand format bit, in the order <Disassembler::PrintInstruction> counts the bits down.
;;
;; At $F9B4. Entry n is the character for format position n + 1: ",Y", ")", ",X", "#$", "($" and
;; "$" have these firsts; <FormatCharacter2> has the seconds.
;; Also: CHAR1 (A2RM78, A2RM79, IIEROM82, IIETRM85)
FormatCharacter1:
.assert * = $F9B4, "FormatCharacter1 must stay at $F9B4, where the mini-assemblers read it."
    .byte ",),#($"

;; The second character of each operand format bit, or 0 for none, in the order of <FormatCharacter1>.
;;
;; At $F9BA.
;; Also: CHAR2 (A2RM78, A2RM79, IIEROM82, IIETRM85)
FormatCharacter2:
.assert * = $F9BA, "FormatCharacter2 must stay at $F9BA, where the mini-assemblers read it."
    .byte "Y", 0, "X$$", 0

;; Packs one mnemonic into the 16-bit constant MNEMONIC_slot, for <MnemonicsLeft> and <MnemonicsRight>.
;;
;; Each letter is five bits, counted from <Disassembler::LETTER_BASE>, and the three are shifted left one.
;; Parameters:
;;   slot = the mnemonic's slot, 0-63
;;   name = the mnemonic, three letters, or "???"
.macro Mnemonic slot, name
    MnemonicBits .set (.strat(name, 0) - Disassembler::LETTER_BASE) << 11
    MnemonicBits .set MnemonicBits | (.strat(name, 1) - Disassembler::LETTER_BASE) << 6
    .ident(.sprintf("MNEMONIC_%d", slot)) = MnemonicBits | (.strat(name, 2) - Disassembler::LETTER_BASE) << 1
.endmacro

;; Packs eight mnemonics, in slots from first on, with <Mnemonic>.
;; Parameters:
;;   first = the first one's slot
;;   n0 = the mnemonic in slot first
;;   n1 = in first + 1
;;   n2 = in first + 2
;;   n3 = in first + 3
;;   n4 = in first + 4
;;   n5 = in first + 5
;;   n6 = in first + 6
;;   n7 = in first + 7
.macro MnemonicRow first, n0, n1, n2, n3, n4, n5, n6, n7
    Mnemonic first, n0
    Mnemonic first + 1, n1
    Mnemonic first + 2, n2
    Mnemonic first + 3, n3
    Mnemonic first + 4, n4
    Mnemonic first + 5, n5
    Mnemonic first + 6, n6
    Mnemonic first + 7, n7
.endmacro

    ; Slots 0-7: opcodes $00-$38, by 8.
    MnemonicRow 0, "BRK", "PHP", "BPL", "CLC", "JSR", "PLP", "BMI", "SEC"
    ; Slots 8-15: opcodes $40-$78, by 8.
    MnemonicRow 8, "RTI", "PHA", "BVC", "CLI", "RTS", "PLA", "BVS", "SEI"
    ; Slots 16-23: opcodes $80-$B8, by 8 ($80 is invalid).
    MnemonicRow 16, "???", "DEY", "BCC", "TYA", "LDY", "TAY", "BCS", "CLV"
    ; Slots 24-31: opcodes $C0-$F8, by 8.
    MnemonicRow 24, "CPY", "INY", "BNE", "CLD", "CPX", "INX", "BEQ", "SED"
    ; Slots 32-39: the other $x4 and $xC opcodes, by $20: -, BIT, JMP, JMP (), STY, LDY, CPY, CPX.
    MnemonicRow 32, "???", "BIT", "JMP", "JMP", "STY", "LDY", "CPY", "CPX"
    ; Slots 40-47: $8A-$FA, by $10.
    MnemonicRow 40, "TXA", "TXS", "TAX", "TSX", "DEX", "???", "NOP", "???"
    ; Slots 48-55: the other $x2, $x6, $xA and $xE opcodes, by $20: the shifts, STX, LDX, DEC, INC.
    MnemonicRow 48, "ASL", "ROL", "LSR", "ROR", "STX", "LDX", "DEC", "INC"
    ; Slots 56-63: the odd opcodes, by $20.
    MnemonicRow 56, "ORA", "AND", "EOR", "ADC", "STA", "LDA", "CMP", "SBC"

;; The packed mnemonics' high bytes, by slot.
;;
;; At $F9C0. Each mnemonic is three letters of five bits, counted from "?" (0) and "A" (2), in the top
;; 15 bits of its two bytes; <MnemonicsRight> holds the low bytes. <Disassembler::Decode>'s second hash gives the
;; slot:
;;
;; - slots 0-31: opcodes $x0 and $x8, at opcode / 8;
;; - slots 32-39: the other $x4 and $xC opcodes, at 32 + opcode / 32;
;; - slots 40-47: TXA..NOP ($8A-$FA), at 32 + opcode / 16;
;; - slots 48-55: the other $x2, $x6, $xA and $xE opcodes, at 48 + opcode / 32;
;; - slots 56-63: the odd opcodes, at 56 + opcode / 32.
;;
;; An invalid opcode gets slot 16, "???".
;; Also: MNEML (A2RM78, A2RM79, IIEROM82, IIETRM85)
MnemonicsLeft:
.assert * = $F9C0, "MnemonicsLeft must stay at $F9C0, where the mini-assemblers read it."
.repeat 64, slot
    .byte >.ident(.sprintf("MNEMONIC_%d", slot))
.endrepeat

;; The packed mnemonics' low bytes, by slot, as <MnemonicsLeft> describes.
;;
;; At $FA00.
;; Also: MNEMR (A2RM78, A2RM79, IIEROM82, IIETRM85)
MnemonicsRight:
.assert * = $FA00, "MnemonicsRight must stay at $FA00, where the mini-assemblers read it."
.repeat 64, slot
    .byte <.ident(.sprintf("MNEMONIC_%d", slot))
.endrepeat
