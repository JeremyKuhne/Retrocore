; retrocore: style=strict
;; Multiple-word constants, loads and stores, bytes, and <MOV at Pcodes::MoveWords>.

;; The room <LDM at Pcodes::LoadMultiple> wants on the 6502 stack beyond the words it pushes, in bytes.
LDM_STACK_MARGIN = 8

; Pcodes: LoadMultipleConstant, LoadMultiple, StoreMultiple, LoadByte, StoreByte and MoveWords.
.scope Pcodes continued

;; <LDC at Pcodes::LoadMultipleConstant>: pushes a constant of several words, which follows the opcode's count byte at
;; the next even address. The words are pushed from the first, so the last ends on top. The count is at least 1.
;; In: Y = 0, as <Fetch> leaves it
;; Also: LDC (A2POSRM, UCSD20)
.proc LoadMultipleConstant

;; The bytes to step <InstructionPointer> over, once it is even: the opcode, the count and the words.
Length = Pointer

    ; Take the count, and the length.
    iny
    lda (InstructionPointer),y
    tax
    tay
    iny
    tya
    asl a
    sta Length

    ; Make InstructionPointer even, stepping over a pad byte when it is odd, so that the words start at
    ; InstructionPointer+2.
    lda InstructionPointer
    and #1
    beq PushWords
    inc InstructionPointer
    bne PushWords
    inc InstructionPointer+1

    ; Push each word, high byte first.
PushWords:
    ldy #3
PushWord:
    lda (InstructionPointer),y
    pha
    dey
    lda (InstructionPointer),y
    pha
    iny
    iny
    iny
    dex
    bne PushWord

    ; Step over the p-code.
    lda InstructionPointer
    clc
    adc Length
    sta InstructionPointer
    bcc Done
    inc InstructionPointer+1
Done:
    jmp Fetch::Next
.endproc

;; <LDM at Pcodes::LoadMultiple>: pops an address, and pushes the operand's count of words from it, the last first, so
;; the first ends on top. Reports a stack overflow unless the 6502 stack pointer is at least the bytes to push plus
;; <LDM_STACK_MARGIN>. The count is at least 1.
;; In: Y = 0, as <Fetch> leaves it
;; Also: LDM (A2POSRM, UCSD20)
.proc LoadMultiple

;; The count of words.
Words = Pointer

;; The count in bytes.
Bytes = Pointer2

    ; Take the count.
    iny
    lda (InstructionPointer),y
    sta Words
    asl a
    tay
    sta Bytes

    ; Is there room?
    tsx
    txa
    sec
    sbc Bytes
    bcc Overflow
    sbc #LDM_STACK_MARGIN
    bcc Overflow

    ; Pop the address, and push the words from the last.
    ldx Words
    dey
    pla
    sta Source
    pla
    sta Source+1
PushWord:
    lda (Source),y
    pha
    dey
    lda (Source),y
    pha
    dey
    dex
    bne PushWord
    jmp Fetch::Skip2

Overflow:
    jmp ExecutionError::ResetForOverflow
.endproc

;; <STM at Pcodes::StoreMultiple>: pops the operand's count of words, the top first, into consecutive words at the
;; address under them, and pops the address.
;; In: Y = 0, as <Fetch> leaves it
;; Also: STM (A2POSRM, UCSD20)
.proc StoreMultiple

;; The count of words.
Words = Pointer

    ; Take the count, and the address under the words.
    iny
    lda (InstructionPointer),y
    sta Words
    tsx
    txa
    clc
    adc Words
    adc Words
    tax
    lda Stack+1,x
    sta Target
    lda Stack+2,x
    sta Target+1

    ; Pop the words into it, from the first word there.
    dey
    ldx Words
    jmp CountWord
StoreWord:
    pla
    sta (Target),y
    iny
    pla
    sta (Target),y
    iny
    dex
CountWord:
    bne StoreWord

    ; Drop the address.
    pla
    pla
    jmp Fetch::Skip2
.endproc

;; <LDB at Pcodes::LoadByte>: pops an index, then a byte array's address, and pushes the byte at the index.
;; In: Y = 0, as <Fetch> leaves it
;; Also: LDB (A2POSRM, UCSD20)
.proc LoadByte

;; The index, then the byte's address.
Byte = Pointer

    ; Pop the index, and add the address to it.
    pla
    sta Byte
    pla
    sta Byte+1
    clc
    pla
    adc Byte
    sta Byte
    pla
    adc Byte+1
    sta Byte+1

    ; Push the byte, as a word.
    lda #0
    pha
    lda (Byte),y
    pha
    jmp Fetch::Skip1
.endproc

;; <STB at Pcodes::StoreByte>: pops a word, then an index, then a byte array's address, and stores the word's low byte
;; at the index.
;; In: Y = 0, as <Fetch> leaves it
;; Also: STB (A2POSRM, UCSD20, WK11)
.proc StoreByte

;; The index, then the byte's address.
Byte = Pointer

    ; Pop the word, keeping its low byte.
    pla
    tax
    pla

    ; Pop the index, and add the address to it.
    pla
    sta Byte
    pla
    sta Byte+1
    clc
    pla
    adc Byte
    sta Byte
    pla
    adc Byte+1
    sta Byte+1

    ; Store the byte.
    txa
    sta (Byte),y
    jmp Fetch::Skip1
.endproc

;; <MOV at Pcodes::MoveWords>: pops a source address, then a target address, and copies the big operand's count of words
;; from the source to the target, with <MoveBytes>.
;; Also: MOV (A2POSRM, UCSD20, WK11)
.proc MoveWords
    ; Pop the addresses.
    pla
    sta Source
    pla
    sta Source+1
    pla
    sta Target
    pla
    sta Target+1

    ; Take the count in bytes, and copy.
    ldy #1
    jsr GetBig
    jmp MoveBytes
.endproc
.endscope
