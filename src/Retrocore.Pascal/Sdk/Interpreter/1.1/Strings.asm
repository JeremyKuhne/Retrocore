; retrocore: style=strict
;; Strings and packed arrays of characters: the handlers for <LPA at OpLPA>, <LSA at OpLSA>, <SAS at OpSAS> and
;; <IXS at OpIXS>.

;; <LPA at OpLPA>: pushes the address of the characters in its operand, a length byte and that many characters, and
;; steps <IPC> past them.
;; In: Y = 0, as <Fetch::Next> leaves it
.proc OpLPA
    ; Step past the opcode, and read the length.
    inc IPC
    bne ReadLength
    inc IPC+1
ReadLength:
    lda (IPC),y
    tax

    ; Step past the length, and push the characters' address.
    inc IPC
    bne PushAddress
    inc IPC+1
PushAddress:
    lda IPC+1
    pha
    lda IPC
    pha
    jmp OpLSA::SkipCharacters
.endproc

;; <LSA at OpLSA>: pushes the address of its operand, a string constant (a length byte and that many characters), and
;; steps <IPC> past it.
;; In: Y = 0, as <Fetch::Next> leaves it
;; Entry: SkipCharacters = steps <IPC> past X characters and runs the next p-code
.proc OpLSA
    ; Step past the opcode, and push the string's address.
    inc IPC
    bne PushAddress
    inc IPC+1
PushAddress:
    lda IPC+1
    pha
    lda IPC
    pha

    ; Read the length, and step past it.
    lda (IPC),y
    tax
    inc IPC
    bne SkipCharacters
    inc IPC+1

;; Steps <IPC> past X characters and runs the next p-code.
;; In: X = how many
SkipCharacters:
    clc
    txa
    adc IPC
    sta IPC
    bcc Next
    inc IPC+1
Next:
    jmp Fetch::Next
.endproc

;; <SAS at OpSAS>: pops a string, or a character, and a string variable's address below it, and copies the string into
;; the variable, or makes the character a string of 1 there. Its operand is the variable's largest length, and a longer
;; string reports <ERROR_STRING_OVERFLOW>.
;;
;; A character is pushed as a word whose high byte is 0, which no string's address has.
.proc OpSAS
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
    lda (IPC),y

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

    ; A string: it must fit. Copy it, the length byte last.
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

Overflow:
    jmp ExecutionError::StringOverflow
.endproc

;; <IXS at OpIXS>: checks the index on top of the stack against the string whose address is below it, leaving both
;; there, and reports <ERROR_VALUE_RANGE> unless the index is from 1 to the string's length.
.proc OpIXS

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
