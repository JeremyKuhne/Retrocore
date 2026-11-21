; retrocore: style=strict
;; The Monitor's disassembler, $F882-$F961: decoding an opcode and printing an instruction, with the Enhanced
;; IIe's slot 3 check between the two, then the hex and blank printers and the next instruction's address that
;; the disassembler and the rest of the Monitor share. Its tables are in DisassemblerTables.asm.

;; The disassembler, which decodes the instruction at <ProgramCounter>/<ProgramCounterHigh> and prints it as the L
;; command lists it.
;;
;; <Disassembler::Decode> hashes an opcode twice. The first hash picks its addressing mode from
;; <Disassembler::AddressingModes>, and the mode picks its operand format from <Disassembler::OperandFormats>; the
;; second picks its mnemonic from <MnemonicsLeft> and <MnemonicsRight>. <Disassembler::PrintInstruction> then
;; prints the instruction's address, bytes, mnemonic and operand. The tables hold the 6502's instructions in every
;; build, the Enhanced IIe's included.
.scope Disassembler

; Decoding an opcode.

;; The opcode STA immediate would have: the 6502 has no such instruction, though its bits fit the ORA..SBC group's.
NO_STA_IMMEDIATE = $89

;; The bit <Decode> rotates an odd opcode's bit 0 into, as it shifts the opcode right two: it marks the ORA..SBC
;; group.
ODD_MARK = $80

;; The bits <Decode> keeps of an odd opcode it has shifted: <ODD_MARK>, and the opcode's bits 2-4, which pick the
;; mode.
ODD_MODE_BITS = ODD_MARK | $07

;; An opcode the 6502 does not have, whose mnemonic slot is "???": <Decode> decodes every invalid opcode as it.
INVALID_OPCODE = $80

;; The bits of an operand format that hold the operand's length, 0-2 bytes.
LENGTH_BITS = $03

;; The bits of an opcode that tell the mnemonic hash an opcode of <TXA_GROUP>: bit 7 and bits 0-3.
GROUP_BITS = $8F

;; TXA, TXS, TAX, TSX, DEX and NOP, and the invalid $DA and $FA, as <GROUP_BITS> keeps them: they skip the
;; mnemonic hash's first step, which puts them in slots 40-47.
TXA_GROUP = $8A

;; The steps of the mnemonic hash, one for each of the opcode's bits 0-2.
HASH_STEPS = 3

;; The bit the mnemonic hash sets as it shifts, once the opcode's first 1 bit has shifted out: it puts the slot at
;; 32 or above.
HASH_GROUP_BIT = $20

;; The Enhanced IIe's internal firmware function that finishes <Decode>: the operand's length and the mnemonic hash.
FUNCTION_DECODE = $10

; Printing an instruction.

;; The most bytes an instruction has: <PrintInstruction> leaves room for them all.
MAX_INSTRUCTION_BYTES = 3

;; The columns an instruction byte takes: two digits and a blank.
BYTE_COLUMNS = 3

;; The bits of a packed mnemonic letter.
LETTER_BITS = 5

;; The character a packed mnemonic letter counts from: 0 is "?", 2 is "A" and 27 is "Z".
LETTER_BASE = '?'

;; The positions of an operand format's character bits, from 6 for bit 7 ("$") down to 1 for bit 2 (",Y").
FORMAT_POSITIONS = 6

;; The format position at which the operand's bytes print: after "$", "($" and "#$", before ",X", ")" and ",Y".
OPERAND_POSITION = 3

; The page zero bytes the disassembler borrows.

;; The operand format of the instruction being decoded, which <PrintInstruction> shifts left as it prints it: the
;; lo-res routines' <PlotMask>.
;; Also: FORMAT (A2RM78, A2RM79, IIEROM82, IIETRM85)
FormatBits = PlotMask

;; The high byte of the packed mnemonic while <PrintInstruction> unpacks it: the lo-res lines' <HorizontalLineEnd>.
;; Also: LMNEM (A2RM78, A2RM79, IIEROM82, IIETRM85)
MnemonicHigh = HorizontalLineEnd

;; The low byte of the packed mnemonic while <PrintInstruction> unpacks it: the lo-res lines' <VerticalLineEnd>.
;; Also: RMNEM (A2RM78, A2RM79, IIEROM82, IIETRM85)
MnemonicLow = VerticalLineEnd

;; Prints the address of the instruction at <ProgramCounter>/<ProgramCounterHigh>, then decodes its opcode.
;;
;; At $F882. It prints a Return, the address as "AAAA-" and three blanks, then falls into <Decode>.
;; In: ProgramCounter/ProgramCounterHigh = the instruction
;; Inherit: <Decode> Out
;; Also: INSDS1 (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc PrintPcAndDecode
.assert * = $F882, "PrintPcAndDecode must stay at $F882."
    ldx ProgramCounter
    ldy ProgramCounterHigh
    jsr PrintAddress::YX
    jsr PrintThreeBlanks
    ; Falls into Decode with X = 0.
.endproc
.if ENHANCED

;; Decodes the opcode of the instruction at <ProgramCounter>/<ProgramCounterHigh>: its operand's length and format, and
;; its mnemonic.
;;
;; At $F88C, and $F88E with the opcode in A (<Decode::Opcode>). The Enhanced IIe looks up the mode
;; and the format here, then hands the opcode to the internal firmware, whose function $10 computes the length and
;; the mnemonic hash as the other builds do here; that frees $F8B7-$F8CF for <CompareSlot3Rom>.
;; In: X = 0, ProgramCounter/ProgramCounterHigh = the instruction
;; Out: A = the mnemonic's slot in <MnemonicsLeft> and <MnemonicsRight>, OperandLength = the operand's bytes (0-2),
;;   PlotMask = the operand format, Y = 0
;; Entry:
;;   Opcode = decodes the opcode in A; the Enhanced IIe firmware's mini-assembler calls it at $F88E
;; Also: INSDS2 (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc Decode
.assert * = $F88C, "Decode must stay at $F88C."
    lda (ProgramCounter,x)

;; Decodes the opcode in A; the Enhanced IIe firmware's mini-assembler calls it at $F88E.
;;
;; DOS's relocator calls the same address by the name `INSDS2`.
;; In: A = the opcode
;; Inherit: <Decode> Out
Opcode:
.assert * = $F88E, "Decode::Opcode must stay at $F88E, where the firmware calls it."

    ; An even opcode's mode is at opcode / 4, in the nibble its bit 1 picks.
    tay
    lsr a
    bcc LookUpMode

    ; An odd one ending in binary 11 is invalid, and so is $89.
    ror a
    bcs Invalid
    cmp #ODD_MARK | NO_STA_IMMEDIATE >> 2
    beq Invalid

    ; The rest are the ORA..SBC group, whose mode only bits 2-4 pick: the last four bytes of the table.
    and #ODD_MODE_BITS

;; Looks up the mode in <AddressingModes>, from opcode / 4 or the odd group's bits, with carry picking the nibble.
;; Also: IEVEN (A2RM78, A2RM79, IIEROM82, IIETRM85)
LookUpMode:
    lsr a
    tax
    lda AddressingModes,x
    jsr LowRes::ReadColor::Nibble
    bne Format

;; An invalid opcode: the invalid mode, and the mnemonic "???".
;; Also: ERR (A2RM78, A2RM79, IIEROM82, IIETRM85)
Invalid:
    ldy #INVALID_OPCODE
    lda #AddressMode::INVALID

;; Looks up the mode's operand format in <OperandFormats>.
;; Also: GETFMT (A2RM78, A2RM79, IIEROM82, IIETRM85)
Format:
    tax
    lda OperandFormats,x
    sta FormatBits

    ; The firmware takes the format in X and the opcode in BAS2L.
    tax
    sty ScrollBase
    ldy #FUNCTION_DECODE
    jmp CallFirmware
.endproc

.endscope

;; Compares slot 3's ROM, Y times, with the bytes that identify a Pascal 1.1 firmware card: $38 at $C305 and $18
;; at $C307.
;;
;; At $F8B7, which the internal firmware's <Firmware:SLOT3CHECK> calls; only the Enhanced IIe has it. It
;; switches the slots' ROMs in, compares <BASICIN> and the byte two after it with the $38 and $18 of the sec and clc
;; that start the Monitor's <ClearToEndOfLine> and <ClearLineFrom>, and switches the internal ROM back. Why it compares
;; more than once is not in the code: presumably so that a slot whose reads float does not match by chance.
;; In: Y = the times to compare (0 for 256)
;; Out: zero = set when every comparison matched, and Y = 0 then
.proc CompareSlot3Rom
.assert * = $F8B7, "CompareSlot3Rom must stay at $F8B7, where the firmware calls it."
    sta InternalCxRomOff

    ; Compares $C307, then $C305.
Repeat:
    ldx #2
NextByte:
    lda BASICIN,x
    cmp ClearToEndOfLine,x
    bne Done
    dex
    dex
    bpl NextByte

    ; Again, Y times.
    dey
    bne Repeat

    ; The internal ROM again, keeping the flags.
Done:
    sta InternalCxRomOn
    rts

    ; An unused byte, $F8CF.
    .byte $00
.endproc

; Disassembler, piece 2 of 3: printing an instruction, after the Enhanced IIe's CompareSlot3Rom.
.scope Disassembler continued
.else

;; Decodes the opcode of the instruction at <ProgramCounter>/<ProgramCounterHigh>: its operand's length and format, and
;; its mnemonic.
;;
;; At $F88C, and $F88E with the opcode in A (<Decode::Opcode>).
;; In: X = 0, ProgramCounter/ProgramCounterHigh = the instruction
;; Out: A = the mnemonic's slot in <MnemonicsLeft> and <MnemonicsRight>, OperandLength = the operand's bytes (0-2),
;;   PlotMask = the operand format, X = the opcode's <GROUP_BITS>, Y = 0
;; Entry:
;;   Opcode = decodes the opcode in A; the Enhanced IIe firmware's mini-assembler calls it at $F88E
;; Also: INSDS2 (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc Decode
.assert * = $F88C, "Decode must stay at $F88C."
    lda (ProgramCounter,x)

;; Decodes the opcode in A; the Enhanced IIe firmware's mini-assembler calls it at $F88E.
;;
;; DOS's relocator calls the same address by the name `INSDS2`.
;; In: A = the opcode
;; Inherit: <Decode> Out
Opcode:
.assert * = $F88E, "Decode::Opcode must stay at $F88E, where the firmware calls it."

    ; An even opcode's mode is at opcode / 4, in the nibble its bit 1 picks.
    tay
    lsr a
    bcc LookUpMode

    ; An odd one ending in binary 11 is invalid, and so is $89.
    ror a
    bcs Invalid
    cmp #ODD_MARK | NO_STA_IMMEDIATE >> 2
    beq Invalid

    ; The rest are the ORA..SBC group, whose mode only bits 2-4 pick: the last four bytes of the table.
    and #ODD_MODE_BITS

;; Looks up the mode in <AddressingModes>, from opcode / 4 or the odd group's bits, with carry picking the nibble.
;; Also: IEVEN (A2RM78, A2RM79, IIEROM82, IIETRM85)
LookUpMode:
    lsr a
    tax
    lda AddressingModes,x
    jsr LowRes::ReadColor::Nibble
    bne Format

;; An invalid opcode: the invalid mode, and the mnemonic "???".
;; Also: ERR (A2RM78, A2RM79, IIEROM82, IIETRM85)
Invalid:
    ldy #INVALID_OPCODE
    lda #AddressMode::INVALID

;; Looks up the mode's operand format in <OperandFormats>, and the operand's length in it.
;; Also: GETFMT (A2RM78, A2RM79, IIEROM82, IIETRM85)
Format:
    tax
    lda OperandFormats,x
    sta FormatBits
    and #LENGTH_BITS
    sta OperandLength

    ; The mnemonic's slot, from the opcode: TXA's group skips the first step.
    tya
    and #GROUP_BITS
    tax
    tya
    ldy #HASH_STEPS
    cpx #TXA_GROUP
    beq HashNext

;; One step of the mnemonic hash: shifts out the next of the opcode's bits 0-2, until one is 1.
;; Also: MNNDX1 (A2RM78, A2RM79, IIEROM82, IIETRM85)
HashStep:
    lsr a
    bcc HashNext
    lsr a

;; Shifts A right, setting <HASH_GROUP_BIT>, once for this step and each step left, then ends the hash.
;; Also: MNNDX2 (A2RM78, A2RM79, IIEROM82, IIETRM85)
HashShift:
    lsr a
    ora #HASH_GROUP_BIT
    dey
    bne HashShift
    iny

;; Counts the steps down.
;; Also: MNNDX3 (A2RM78, A2RM79, IIEROM82, IIETRM85)
HashNext:
    dey
    bne HashStep
    rts
.endproc

    ; Three unused bytes, $F8CD-$F8CF.
    .byte $FF, $FF, $FF
.endif

;; Disassembles the instruction at <ProgramCounter>/<ProgramCounterHigh> and prints it.
;;
;; At $F8D0. It prints a Return, the address as "AAAA-", the instruction's bytes in hex, its mnemonic,
;; and its operand, with a branch's operand printed as the address it goes to.
;; In: ProgramCounter/ProgramCounterHigh = the instruction
;; Out: OperandLength = the operand's bytes (0-2)
;; Entry:
;;   Operand = prints the operand's bytes, the last first, or for a branch the address it goes to
;; Also: INSTDSP (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc PrintInstruction
.assert * = $F8D0, "PrintInstruction must stay at $F8D0."
    jsr PrintPcAndDecode
    pha

;; Prints one of the instruction's bytes, from Y = 0, and a blank.
;; Also: PRNTOP (A2RM78, A2RM79, IIEROM82, IIETRM85)
NextByte:
    lda (ProgramCounter),y
    jsr PrintHexByte
    ldx #1

;; Prints the blanks after a byte, or for a byte the instruction does not have, so the mnemonics line up.
;; Also: PRNTBL (A2RM78, A2RM79, IIEROM82, IIETRM85)
PadBytes:
    jsr PrintBlanks
    cpy OperandLength
    iny
    bcc NextByte
    ldx #BYTE_COLUMNS
    cpy #MAX_INSTRUCTION_BYTES + 1
    bcc PadBytes

    ; The mnemonic: X is BYTE_COLUMNS, three, which is also its letters.
    pla
    tay
    lda MnemonicsLeft,y
    sta MnemonicHigh
    lda MnemonicsRight,y
    sta MnemonicLow

;; Prints the mnemonic's next letter.
;; Also: PRMN1 (A2RM78, A2RM79, IIEROM82, IIETRM85)
NextLetter:
    lda #0
    ldy #LETTER_BITS

;; Shifts one bit of the packed mnemonic into A.
;; Also: PRMN2 (A2RM78, A2RM79, IIEROM82, IIETRM85)
ShiftLetter:
    asl MnemonicLow
    rol MnemonicHigh
    rol a
    dey
    bne ShiftLetter
    adc #LETTER_BASE                ; carry is clear: rol shifted a 0 out of A
    jsr CharacterOut
    dex
    bne NextLetter

    ; The operand, after three blanks: Y = the operand byte to print, X = the format position.
    jsr PrintThreeBlanks
    ldy OperandLength
    ldx #FORMAT_POSITIONS

;; Goes on to the operand's bytes at their position, or to the format's next character bit.
;; Also: PRADR1 (A2RM78, A2RM79, IIEROM82, IIETRM85)
NextFormatBit:
    cpx #OPERAND_POSITION
    beq Operand

;; Prints the characters of the format's next bit, when it is set, from <FormatCharacter1> and <FormatCharacter2>.
;; Also: PRADR2 (A2RM78, A2RM79, IIEROM82, IIETRM85)
FormatCharacter:
    asl FormatBits
    bcc NextCharacter
    lda FormatCharacter1 - 1,x
    jsr CharacterOut
    lda FormatCharacter2 - 1,x
    beq NextCharacter
    jsr CharacterOut

;; Goes on to the next format position, until the last.
;; Also: PRADR3 (A2RM78, A2RM79, IIEROM82, IIETRM85)
NextCharacter:
    dex
    bne NextFormatBit
    rts

;; Steps down to the next operand byte and prints the one <PrintInstruction::Operand> loaded, or, when none is
;; left, goes on to the format's characters after the operand.
;; Also: PRADR4 (A2RM78, A2RM79, IIEROM82, IIETRM85)
OperandByte:
    dey
    bmi FormatCharacter
    jsr PrintHexByte

;; Prints the operand's bytes, the last first, or for a branch the address it goes to.
;;
;; The format has shifted left once for each position above the operand's by now, and only the relative mode's
;; is then as high as <RELATIVE_FORMAT> shifted as far.
;; Also: PRADR5 (A2RM78, A2RM79, IIEROM82, IIETRM85)
Operand:
    lda FormatBits
    cmp #<(RELATIVE_FORMAT << (FORMAT_POSITIONS - OPERAND_POSITION))
    lda (ProgramCounter),y
    bcc OperandByte

;; Prints a branch's target: the address after the branch, plus the displacement in A, sign-extended.
;; Also: RELADR (A2RM78, A2RM79, IIEROM82, IIETRM85)
BranchTarget:
    ; Carry is set, so this is the address plus one, plus the displacement; X and Y then have it plus two.
    jsr NextInstruction::AddA
    tax
    inx
    bne PrintYX
    iny
    ; Falls into PrintYX.
.endproc

.endscope

;; Prints Y, then X, as four hex digits.
;;
;; At $F940.
;; In: Y = the high byte, X = the low byte
;; Keeps: X, Y
;; Also: PRNTYX (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc PrintYX
.assert * = $F940, "PrintYX must stay at $F940."
    tya
    ; Falls into PrintAX.
.endproc

;; Prints A, then X, as four hex digits.
;;
;; At $F941.
;; In: A = the high byte, X = the low byte
;; Keeps: X, Y
;; Also: PRNTAX (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc PrintAX
.assert * = $F941, "PrintAX must stay at $F941."
    jsr PrintHexByte
    ; Falls into PrintX.
.endproc

;; Prints X as two hex digits.
;;
;; At $F944.
;; In: X = the byte
;; Keeps: X, Y
;; Also: PRNTX (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc PrintX
.assert * = $F944, "PrintX must stay at $F944."
    txa
    jmp PrintHexByte
.endproc

;; Prints three blanks.
;;
;; At $F948.
;; Out: X = 0
;; Keeps: Y
;; Also: PRBLNK (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc PrintThreeBlanks
.assert * = $F948, "PrintThreeBlanks must stay at $F948."
    ldx #3
    ; Falls into PrintBlanks.
.endproc

;; Prints X blanks.
;;
;; At $F94A.
;; In: X = the count (1-255, or 0 for 256)
;; Out: X = 0, A = a blank
;; Keeps: Y
;; Also: PRBL2 (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc PrintBlanks
.assert * = $F94A, "PrintBlanks must stay at $F94A."
    lda #' '

;; Prints a blank and counts it.
;; Also: PRBL3 (A2RM78, A2RM79, IIEROM82, IIETRM85)
Print:
    jsr CharacterOut
    dex
    bne PrintBlanks
    rts
.endproc

;; Computes the address of the instruction after the one at <ProgramCounter>/<ProgramCounterHigh>.
;;
;; At $F953. <ProgramCounter>/<ProgramCounterHigh> are not changed.
;; In: OperandLength = the instruction's operand bytes, as <Disassembler::Decode> leaves it
;; Out: A = the address's low byte, Y = its high byte, X = OperandLength
;; Entry:
;;   AddLength = the same, adding the carry as given instead of one
;;   AddA = adds A, sign-extended, and the carry to <ProgramCounter>/<ProgramCounterHigh>
;; Also: PCADJ (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc NextInstruction
.assert * = $F953, "NextInstruction must stay at $F953."
    sec

;; The same, adding the carry as given instead of one.
;;
;; In: OperandLength = the instruction's operand bytes, carry = set to add one more
;; Out: A = the address's low byte, Y = its high byte, X = OperandLength
;; Also: PCADJ2 (A2RM78, A2RM79, IIEROM82, IIETRM85)
AddLength:
    lda OperandLength

;; Adds A, sign-extended, and the carry to <ProgramCounter>/<ProgramCounterHigh>.
;;
;; In: A = the signed amount to add, carry = set to add one more
;; Out: A = the sum's low byte, Y = its high byte, X = the amount
;; Also: PCADJ3 (A2RM78, A2RM79, IIEROM82, IIETRM85)
AddA:
    ldy ProgramCounterHigh
    tax
    bpl AddLow
    dey

;; Adds the low bytes, carrying into Y.
;; Also: PCADJ4 (A2RM78, A2RM79, IIEROM82, IIETRM85)
AddLow:
    adc ProgramCounter
    bcc Done
    iny

;; Returns.
;; Also: RTS2 (A2RM78, A2RM79, IIEROM82, IIETRM85)
Done:
    rts
.endproc
