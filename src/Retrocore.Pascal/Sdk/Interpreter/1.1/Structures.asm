; retrocore: style=strict
;; Indirection, records and arrays, and packed fields: the handlers for <IND at Pcodes::LoadIndirect>, INC,
;; <IXA at Pcodes::IndexArray>, <IXP at Pcodes::IndexPackedArray>, <LDP at Pcodes::LoadPackedField> and STP.

; Pcodes: LoadIndirect, IncrementField, IndexArray, IndexPackedArray, LoadPackedField and StorePackedField.
.scope Pcodes continued

;; <IND at Pcodes::LoadIndirect>: replaces the address on top of the stack with the word at that address plus its big
;; operand, a word offset.
;; Also: IND (A2POSRM, UCSD20, WK11)
.proc LoadIndirect

;; The word's address.
WordAddress = ProcedureNumber

    ; Add the operand's byte offset to the address.
    ldy #1
    jsr GetBig
    clc
    pla
    adc Offset
    sta WordAddress
    pla
    adc Offset+1
    sta WordAddress+1

    ; Push the word there.
    ldy #1
    lda (WordAddress),y
    pha
    dey
    lda (WordAddress),y
    pha
    jmp Fetch::Skip2
.endproc

;; INC: adds its big operand, a word offset, to the address on top of the stack, as a field's address.
;; Also: INC (A2POSRM, UCSD20, WK11)
.proc IncrementField
    ; Add the operand's byte offset to the address, and push it back.
    ldy #1
    jsr GetBig
    clc
    pla
    adc Offset
    tax
    pla
    adc Offset+1
    pha
    txa
    pha
    jmp Fetch::Skip2
.endproc

;; <IXA at Pcodes::IndexArray>: pops an index and an array's address below it, and pushes the element's address: the
;; array's address plus the index times its big operand, the element's size in words.
;; Also: IXA (A2POSRM, UCSD20, WK11)
.proc IndexArray

;; The index, which becomes the element's byte offset.
Index = Multiply::Multiplicand

;; The element's size in bytes, for <Multiply>.
ElementSize = Multiply::Multiplier

;; The element's address's low byte, kept while the high byte is worked out.
ElementLow = ProcedureNumber

    ; Pop the index, and read the element's size.
    pla
    sta Index
    pla
    sta Index+1
    ldy #1
    jsr GetBig

    ; Elements of one word, 2 bytes, take a shift instead of a multiply.
    lda Offset+1
    bne MultiplyIndex
    lda Offset
    cmp #2
    bne MultiplyIndex
    asl Index
    rol Index+1
    jmp AddIndex

    ; Multiply the index by the size in bytes.
MultiplyIndex:
    lda Offset
    sta ElementSize
    lda Offset+1
    sta ElementSize+1
    jsr Multiply
    lda Multiply::Product
    sta Index
    lda Multiply::Product+1
    sta Index+1

    ; Add the offset to the array's address, and push it.
AddIndex:
    clc
    pla
    adc Index
    sta ElementLow
    pla
    adc Index+1
    pha
    lda ElementLow
    pha
    jmp Fetch::Skip2
.endproc

;; <IXP at Pcodes::IndexPackedArray>: pops an index and the address of a packed array below it, and pushes what
;; <LDP at Pcodes::LoadPackedField> and STP take for the element: the address of the word holding it, the field's width
;; in bits, and the number of its lowest bit.
;;
;; Its operands are two bytes: the elements in each word, and their width in bits. The lowest bit's number is pushed in
;; both bytes of its word; <LDP at Pcodes::LoadPackedField> and STP read only the low byte.
;; Also: IXP (A2POSRM, UCSD20, WK11)
.proc IndexPackedArray

;; The elements in each word, the divisor.
ElementsPerWord = Divide::Divisor

;; The index, which <Divide> leaves as the element's place in its word.
Index = Divide::Remainder

;; The word's index in the array, as <Divide> leaves it.
WordIndex = Divide::Quotient

;; Each element's width in bits.
FieldWidth = Buffer

;; The word's address's low byte, kept while the high byte is worked out.
WordLow = ProcedureNumber

    ; Read the operands, as words.
    ldy #1
    lda (InstructionPointer),y
    sta ElementsPerWord
    ldy #2
    lda (InstructionPointer),y
    sta FieldWidth
    lda #0
    sta ElementsPerWord+1
    sta FieldWidth+1

    ; Pop the index, and divide it by the elements in each word.
    pla
    sta Index
    pla
    sta Index+1
    jsr Divide

    ; Push the address of the word: the array's address plus the word index times 2.
    asl WordIndex
    rol WordIndex+1
    clc
    pla
    adc WordIndex
    sta WordLow
    pla
    adc WordIndex+1
    pha
    lda WordLow
    pha

    ; Push the width.
    lda FieldWidth+1
    pha
    lda FieldWidth
    pha

    ; Push the lowest bit's number, the element's place in its word times the width, in both bytes. The sum stays
    ; below 16, so the carry stays clear.
    lda #0
    ldx Index
    beq PushBit
    clc
AddWidth:
    adc FieldWidth
    dex
    bne AddWidth
PushBit:
    pha
    pha
    jmp Fetch::Skip3
.endproc

;; <LDP at Pcodes::LoadPackedField>: pops a packed field's lowest bit number, its width and its word's address, as
;; <IXP at Pcodes::IndexPackedArray> pushes them, and pushes the field's value.
;; Also: LDP (A2POSRM, UCSD20, WK11)
.proc LoadPackedField

;; The number of the field's lowest bit, 0-15.
RightBit = Procedure

;; The field's width in bits.
Width = Buffer

;; The address of the word that holds the field.
WordAddress = ProcedureNumber

;; The word, shifted until the field is at its bottom.
Field = Mark

    ; Pop the bit number, the width and the address.
    pla
    sta RightBit
    pla
    sta RightBit+1
    pla
    sta Width
    pla
    sta Width+1
    pla
    sta WordAddress
    pla
    sta WordAddress+1

    ; Read the word.
    ldy #0
    lda (WordAddress),y
    sta Field
    iny
    lda (WordAddress),y
    sta Field+1

    ; For a bit number of 8 or more, swap the bytes, and shift right 8 fewer bits.
    lda RightBit
    sec
    sbc #8
    bmi FewerThan8
    tax
    lda Field
    ldy Field+1
    sty Field
    sta Field+1
    cpx #0
    bne ShiftRight
    beq Mask
FewerThan8:
    adc #8
    tax
    beq Mask

    ; Shift the field down to bit 0. What comes in above it is masked off.
ShiftRight:
    ror Field+1
    ror Field
    dex
    bne ShiftRight

    ; Keep the width's bits, and push them.
Mask:
    lda Width
    asl a
    tax
    lda Field
    and LowMasks,x
    sta Field
    lda Field+1
    and LowMasks+1,x
    pha
    lda Field
    pha
    jmp Fetch::Skip1
.endproc

;; STP: pops a value, then a packed field's lowest bit number, its width and its word's address, as
;; <IXP at Pcodes::IndexPackedArray> pushes them, and stores the value's low bits in the field.
;; Also: STP (A2POSRM, UCSD20, WK11)
.proc StorePackedField

;; The value, cut to the width and shifted to the field's place.
Value = Pointer

;; The field's bits in the word: the width's low bits, shifted the same way.
FieldMask = Pointer2

;; The number of the field's lowest bit, 0-15.
RightBit = Procedure

;; The field's width in bits.
Width = Buffer

;; The address of the word that holds the field.
WordAddress = ProcedureNumber

;; The word, with the field replaced.
Word = Mark

    ; Pop the value, the bit number and the width.
    pla
    sta Value
    pla
    sta Value+1
    pla
    sta RightBit
    pla
    sta RightBit+1
    pla
    sta Width
    pla
    sta Width+1

    ; Make the mask of the width's low bits, and cut the value to it.
    lda Width
    asl a
    tax
    lda LowMasks,x
    sta FieldMask
    and Value
    sta Value
    lda LowMasks+1,x
    sta FieldMask+1
    and Value+1
    sta Value+1

    ; For a bit number of 8 or more, swap the bytes of the value and of the mask, whose high bytes are 0 when the
    ; field fits in the word, and shift left 8 fewer bits.
    lda RightBit
    sec
    sbc #8
    bmi FewerThan8
    tax
    lda Value
    ldy Value+1
    sta Value+1
    sty Value
    lda FieldMask
    ldy FieldMask+1
    sta FieldMask+1
    sty FieldMask
    cpx #0
    bne ShiftLeft
    beq Store
FewerThan8:
    adc #8
    tax
    beq Store

    ; Shift the value and the mask up to the field's place.
ShiftLeft:
    asl Value
    rol Value+1
    asl FieldMask
    rol FieldMask+1
    dex
    bne ShiftLeft

    ; Pop the address, and read the word.
Store:
    pla
    sta WordAddress
    pla
    sta WordAddress+1
    ldy #0
    lda (WordAddress),y
    sta Word
    iny
    lda (WordAddress),y
    sta Word+1

    ; Replace the field's bits with the value's.
    lda FieldMask
    eor #$FF
    and Word
    ora Value
    sta Word
    lda FieldMask+1
    eor #$FF
    and Word+1
    ora Value+1
    sta Word+1

    ; Write the word back.
    ldy #0
    lda Word
    sta (WordAddress),y
    iny
    lda Word+1
    sta (WordAddress),y
    jmp Fetch::Skip1
.endproc
.endscope
