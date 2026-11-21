; The mini disassembler's tables.
;
; INSDS2 hashes an opcode twice. The first hash picks its addressing mode from FMT1; the mode then
; picks FMT2's operand format. The second hash picks the mnemonic from MNEML/MNEMR.

;; Addressing modes, the FMT2 index of each. INVALID marks an opcode the 6502 does not have.
.enum AM
INVALID
IMM                                 ; #$nn
ZP                                  ; $nn
ABS                                 ; $nnnn
IMP                                 ; (nothing)
ACC                                 ; (nothing; the Monitor does not print "A")
INDX                                ; ($nn,X)
INDY                                ; ($nn),Y
ZPX                                 ; $nn,X
ABSX                                ; $nnnn,X
ABSY                                ; $nnnn,Y
IND                                 ; ($nnnn)
ZPY                                 ; $nn,Y
REL                                 ; $nnnn, the branch target
.endenum

;; Each opcode's addressing mode, two 4-bit modes per byte: the low nibble for the opcode with bit 1
;; clear, the high nibble for bit 1 set.
;; Even opcodes index the table by opcode/4, so each row below is the even columns of one row of the
;; opcode matrix. Odd opcodes (the ORA..SBC group) depend only on bits 2-4, and use the last four bytes.
;; Opcodes ending in binary 11, and $89, are invalid before the table is read.
.macro MODES m0, m2, m4, m6, m8, mA, mC, mE
    .byte AM::m0 | AM::m2 << 4, AM::m4 | AM::m6 << 4, AM::m8 | AM::mA << 4, AM::mC | AM::mE << 4
.endmacro

FMT1:
    MODES IMP, INVALID, INVALID, ZP, IMP, ACC, INVALID, ABS         ; $00-$0E BRK - - ASL PHP ASL - ASL
    MODES REL, INVALID, INVALID, ZPX, IMP, INVALID, INVALID, ABSX   ; $10-$1E BPL - - ASL CLC - - ASL
    MODES ABS, INVALID, ZP, ZP, IMP, ACC, ABS, ABS                  ; $20-$2E JSR - BIT ROL PLP ROL BIT ROL
    MODES REL, INVALID, INVALID, ZPX, IMP, INVALID, INVALID, ABSX   ; $30-$3E BMI - - ROL SEC - - ROL
    MODES IMP, INVALID, INVALID, ZP, IMP, ACC, ABS, ABS             ; $40-$4E RTI - - LSR PHA LSR JMP LSR
    MODES REL, INVALID, INVALID, ZPX, IMP, INVALID, INVALID, ABSX   ; $50-$5E BVC - - LSR CLI - - LSR
    MODES IMP, INVALID, INVALID, ZP, IMP, ACC, IND, ABS             ; $60-$6E RTS - - ROR PLA ROR JMP ROR
    MODES REL, INVALID, INVALID, ZPX, IMP, INVALID, INVALID, ABSX   ; $70-$7E BVS - - ROR SEI - - ROR
    MODES INVALID, INVALID, ZP, ZP, IMP, IMP, ABS, ABS              ; $80-$8E - - STY STX DEY TXA STY STX
    MODES REL, INVALID, ZPX, ZPY, IMP, IMP, INVALID, INVALID        ; $90-$9E BCC - STY STX TYA TXS - -
    MODES IMM, IMM, ZP, ZP, IMP, IMP, ABS, ABS                      ; $A0-$AE LDY LDX LDY LDX TAY TAX LDY LDX
    MODES REL, INVALID, ZPX, ZPY, IMP, IMP, ABSX, ABSY              ; $B0-$BE BCS - LDY LDX CLV TSX LDY LDX
    MODES IMM, INVALID, ZP, ZP, IMP, IMP, ABS, ABS                  ; $C0-$CE CPY - CPY DEC INY DEX CPY DEC
    MODES REL, INVALID, INVALID, ZPX, IMP, INVALID, INVALID, ABSX   ; $D0-$DE BNE - - DEC CLD - - DEC
    MODES IMM, INVALID, ZP, ZP, IMP, IMP, ABS, ABS                  ; $E0-$EE CPX - CPX INC INX NOP CPX INC
    MODES REL, INVALID, INVALID, ZPX, IMP, INVALID, INVALID, ABSX   ; $F0-$FE BEQ - - INC SED - - INC
    MODES INDX, ZP, IMM, ABS, INDY, ZPX, ABSY, ABSX                 ; $x1-$xD by bits 2-4: ORA..SBC

;; How PRADR prints each mode's operand: the operand length in bits 0-1, and which characters to print
;; around the operand bytes in bits 2-7 (CHAR1/CHAR2, from the top bit down: "$", "($", "#$", ",X",
;; ")", ",Y").
OPERAND_DOLLAR = $80

OPERAND_INDIRECT = $40              ;; prints "($" before the operand
OPERAND_IMMEDIATE = $20             ;; prints "#$" before the operand
OPERAND_X = $10                     ;; prints ",X" after the operand
OPERAND_CLOSE = $08                 ;; prints ")" after the operand
OPERAND_Y = $04                     ;; prints ",Y" after the operand

;; The relative mode's format is chosen so that shifted left three times it is $E8, which PRADR5 tests
;; for to print the branch target instead; its other bits never print.
FMT2:
    .byte 0                                                     ; INVALID
    .byte OPERAND_IMMEDIATE | 1                                 ; IMM  #$nn
    .byte OPERAND_DOLLAR | 1                                    ; ZP   $nn
    .byte OPERAND_DOLLAR | 2                                    ; ABS  $nnnn
    .byte 0                                                     ; IMP
    .byte 0                                                     ; ACC
    .byte OPERAND_INDIRECT | OPERAND_X | OPERAND_CLOSE | 1      ; INDX ($nn,X)
    .byte OPERAND_INDIRECT | OPERAND_CLOSE | OPERAND_Y | 1      ; INDY ($nn),Y
    .byte OPERAND_DOLLAR | OPERAND_X | 1                        ; ZPX  $nn,X
    .byte OPERAND_DOLLAR | OPERAND_X | 2                        ; ABSX $nnnn,X
    .byte OPERAND_DOLLAR | OPERAND_Y | 2                        ; ABSY $nnnn,Y
    .byte OPERAND_INDIRECT | OPERAND_CLOSE | 2                  ; IND  ($nnnn)
    .byte OPERAND_DOLLAR | OPERAND_Y | 1                        ; ZPY  $nn,Y
    .byte $9D                                                   ; REL  $nnnn

;; The operand characters, indexed from the end as PRADR shifts the format left: each entry prints
;; CHAR1's character, then CHAR2's unless it is zero.
CHAR1:
    .byte ",),#($"                                              ; ",Y" ")" ",X" "#$" "($" "$"

CHAR2:
    .byte "Y", 0, "X$$", 0

;; Mnemonics, three letters packed five bits each into 15 bits ("?" = 0, "A" = 2), shifted left one.
;; MNEML holds the high bytes and MNEMR the low bytes. INSDS2's second hash gives the slot:
;;   slots  0-31: opcodes $x0 and $x8, at opcode/8
;;   slots 32-39: the other $x4 and $xC opcodes, at 32 + opcode/32
;;   slots 40-47: TXA..NOP ($8A-$EA), at 32 + opcode/16
;;   slots 48-55: the other $x2, $x6, $xA and $xE opcodes, at 48 + opcode/32
;;   slots 56-63: the $x1-$xD group, at 56 + opcode/32
;; An invalid opcode gets slot 16, "???".
.macro MNEMONIC slot, name
    .ident(.sprintf("MNEMONIC_%d", slot)) = (.strat(name, 0) - '?') << 11 | (.strat(name, 1) - '?') << 6 | (.strat(name, 2) - '?') << 1
.endmacro

.macro MNEMONICS first, n0, n1, n2, n3, n4, n5, n6, n7
    MNEMONIC first, n0
    MNEMONIC first + 1, n1
    MNEMONIC first + 2, n2
    MNEMONIC first + 3, n3
    MNEMONIC first + 4, n4
    MNEMONIC first + 5, n5
    MNEMONIC first + 6, n6
    MNEMONIC first + 7, n7
.endmacro

    MNEMONICS 0, "BRK", "PHP", "BPL", "CLC", "JSR", "PLP", "BMI", "SEC"             ; opcodes $00-$38 by 8
    MNEMONICS 8, "RTI", "PHA", "BVC", "CLI", "RTS", "PLA", "BVS", "SEI"             ; opcodes $40-$78 by 8
    MNEMONICS 16, "???", "DEY", "BCC", "TYA", "LDY", "TAY", "BCS", "CLV"            ; opcodes $80-$B8 by 8 ($80 is invalid)
    MNEMONICS 24, "CPY", "INY", "BNE", "CLD", "CPX", "INX", "BEQ", "SED"            ; opcodes $C0-$F8 by 8
    MNEMONICS 32, "???", "BIT", "JMP", "JMP", "STY", "LDY", "CPY", "CPX"            ; $x4/$xC: -, BIT, JMP, JMP (), STY, LDY, CPY, CPX
    MNEMONICS 40, "TXA", "TXS", "TAX", "TSX", "DEX", "???", "NOP", "???"            ; $8A-$EA by 16
    MNEMONICS 48, "ASL", "ROL", "LSR", "ROR", "STX", "LDX", "DEC", "INC"            ; $x2-$xE: shifts, STX, LDX, DEC, INC
    MNEMONICS 56, "ORA", "AND", "EOR", "ADC", "STA", "LDA", "CMP", "SBC"            ; $x1-$xD

MNEML:
.repeat 64, slot
    .byte >.ident(.sprintf("MNEMONIC_%d", slot))
.endrepeat

MNEMR:
.repeat 64, slot
    .byte <.ident(.sprintf("MNEMONIC_%d", slot))
.endrepeat
