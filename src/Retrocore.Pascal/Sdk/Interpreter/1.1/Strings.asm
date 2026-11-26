; retrocore: style=strict
;; Strings and packed arrays of characters: the handlers for <LPA at Pcodes::LoadPackedArrayAddress>,
;; <LSA at Pcodes::LoadStringAddress>, <SAS at Pcodes::AssignString> and <IXS at Pcodes::IndexString>.

; Pcodes: LoadPackedArrayAddress, LoadStringAddress, AssignString and IndexString.
.scope Pcodes continued

;; <LPA at Pcodes::LoadPackedArrayAddress>: pushes the address of the characters in its operand, a length byte and that
;; many characters, and steps <InstructionPointer> past them.
;; In: Y = 0, as <Fetch::Next> leaves it
;; Also: LPA (A2POSRM, WK11)
.proc LoadPackedArrayAddress
    ; Step past the opcode, and read the length.
    inc InstructionPointer
    bne ReadLength
    inc InstructionPointer+1
ReadLength:
    lda (InstructionPointer),y
    tax

    ; Step past the length, and push the characters' address.
    inc InstructionPointer
    bne PushAddress
    inc InstructionPointer+1
PushAddress:
    lda InstructionPointer+1
    pha
    lda InstructionPointer
    pha
    jmp Pcodes::LoadStringAddress::SkipCharacters
.endproc

;; <LSA at Pcodes::LoadStringAddress>: pushes the address of its operand, a string constant (a length byte and that many
;; characters), and steps <InstructionPointer> past it.
;; In: Y = 0, as <Fetch::Next> leaves it
;; Entry: SkipCharacters = steps <InstructionPointer> past X characters and runs the next p-code
;; Also: LCA (UCSD20), LSA (A2POSRM, WK11)
.proc LoadStringAddress
    ; Step past the opcode, and push the string's address.
    inc InstructionPointer
    bne PushAddress
    inc InstructionPointer+1
PushAddress:
    lda InstructionPointer+1
    pha
    lda InstructionPointer
    pha

    ; Read the length, and step past it.
    lda (InstructionPointer),y
    tax
    inc InstructionPointer
    bne SkipCharacters
    inc InstructionPointer+1

;; Steps <InstructionPointer> past X characters and runs the next p-code.
;; In: X = how many
SkipCharacters:
    clc
    txa
    adc InstructionPointer
    sta InstructionPointer
    bcc Next
    inc InstructionPointer+1
Next:
    jmp Fetch::Next
.endproc

;; <SAS at Pcodes::AssignString>: pops a string, or a character, and a string variable's address below it, and copies
;; the string into the variable, or makes the character a string of 1 there. Its operand is the variable's largest
;; length, and a longer string reports <ERROR_STRING_OVERFLOW>.
;;
;; A character is pushed as a word whose high byte is 0, which no string's address has.
;; Also: SAS (A2POSRM, UCSD20, WK11)
.proc AssignString
    ; Pop the string and the variable, and read the largest length.
    pla
    sta Source
    pla
    sta Source+1
    pla
    sta Target
    pla
    sta Target+1
    ldy #1
    lda (InstructionPointer),y

    ; A character: the variable must hold at least 1. Store a length of 1 and the character.
    ldx Source+1
    bne String
    cmp #1
    bcc Overflow
    lda #1
    ldy #0
    sta (Target),y
    lda Source
    iny
    sta (Target),y
    jmp Fetch::Skip2

    ; A string: it must fit. Copy it, the length byte first, then its characters from the last.
String:
    ldy #0
    cmp (Source),y
    bcc Overflow
    lda (Source),y
    sta (Target),y
    tay
    jmp CountDown
CopyByte:
    lda (Source),y
    sta (Target),y
    dey
CountDown:
    bne CopyByte
    jmp Fetch::Skip2

;; Reports a string overflow: the source is longer than the destination's size.
;; Also: JERR13 (WK11)
Overflow:
    jmp ExecutionError::StringOverflow
.endproc

;; <IXS at Pcodes::IndexString>: checks the index on top of the stack against the string whose address is below it,
;; leaving both there, and reports <ERROR_VALUE_RANGE> unless the index is from 1 to the string's length.
;; Also: IXS (A2POSRM, UCSD20, WK11)
.proc IndexString

;; The string.
StringAddress = Pointer

    ; The index's high byte must be 0, and its low byte not 0.
    tsx
    lda Stack+2,x
    bne OutOfRange
    lda Stack+1,x
    beq OutOfRange

    ; It must be no more than the length.
    ldy Stack+3,x
    sty StringAddress
    ldy Stack+4,x
    sty StringAddress+1
    ldy #0
    cmp (StringAddress),y
    bcc InRange
    beq InRange

OutOfRange:
    jmp ExecutionError::ValueRange

InRange:
    jmp Fetch::Skip1
.endproc
.endscope
