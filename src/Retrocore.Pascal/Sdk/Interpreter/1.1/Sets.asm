; retrocore: style=strict
;; Sets: the handlers for <INT at OpINT>, <DIF at OpDIF>, <UNI at OpUNI>, <ADJ at OpADJ>, <INN at OpINN>, <SGS at OpSGS>
;; and <SRS at OpSRS>, and the bit mask tables.
;;
;; A set on the stack is its bytes, element 0's byte first at the lowest address, with its length in words on top.
;; The set routines read only the length's low byte.

; Booleans, as the comparisons and INN push them.

;; Pascal's false, pushed as a word.
BOOLEAN_FALSE = 0

;; Pascal's true, pushed as a word whose high byte is 0.
BOOLEAN_TRUE = 1

; Set elements.

;; The bits of an element's high byte that must be 0: a set holds elements 0 to 511.
SET_ELEMENT_HIGH_MASK = $FE

;; The bits of an element that number its bit in its byte.
BYTE_BIT_MASK = $07

;; The bits of an element shifted right 3 that number its byte in the set, 0 to 63.
SET_BYTE_MASK = $3F

;; The bits of an element that number its bit in its word.
WORD_BIT_MASK = $0F

;; One entry of <BitMasks>: a byte with one bit set.
;; Parameters:
;;   bit = the bit, from 0 up; the entries go in order
.macro BitMask bit
    .assert * = BitMasks + bit, "BitMasks's entries are in bit order."
    .byte 1 << bit
.endmacro

;; One entry of <LowMasks>: a word with its low bits set.
;; Parameters:
;;   bits = how many, from 0 up; the entries go in order
.macro LowMask bits
    .assert * = LowMasks + 2 * bits, "LowMasks's entries are in order."
    .word (1 << bits) - 1
.endmacro

;; One entry of <HighMasks>: a word with its bits from one up to bit 15 set.
;; Parameters:
;;   bit = the lowest bit set, from 0 up; the entries go in order
.macro HighMask bit
    .assert * = HighMasks + 2 * bit, "HighMasks's entries are in order."
    .word $FFFF << bit & $FFFF
.endmacro

;; Pops the top set's length for <INT at OpINT>, <DIF at OpDIF> and <UNI at OpUNI>, and finds both sets. Their result
;; goes in place of the lower set.
;;
;; The sets are under its return address, so it pulls that, and returns by jumping to it plus 1.
;; Out:
;;   A = the lower set's size in bytes
;;   TopSize = the top set's size in bytes
;;   LowerLength = the stack index of the lower set's length word
;;   Y = the stack index of the lower set's first byte
;;   LowerSet = the same
;;   S = just below the top set's first byte, so PLA pulls it
;; Also: FIXSET (WK11)
.proc PopSetOperands

;; The return address, less 1, as JSR pushed it.
Return = Work4

;; The top set's size in bytes.
TopSize = Procedure

;; The stack index of the lower set's length word.
LowerLength = Mark

;; The stack index of the lower set's first byte.
LowerSet = Pointer

    ; Pull the return address.
    pla
    sta Return
    pla
    sta Return+1

    ; Pop the top set's length, as bytes.
    pla
    asl a
    sta TopSize
    pla

    ; Find the lower set's length, past the top set, and read it, as bytes.
    tsx
    txa
    clc
    adc TopSize
    tay
    iny
    sty LowerLength
    lda Stack,y
    asl a

    ; Find the lower set's first byte, past its length.
    iny
    iny
    sty LowerSet

    ; Return.
    inc Return
    bne Jump
    inc Return+1
Jump:
    jmp (Return)
.endproc

;; <INT at OpINT>: pops two sets and pushes their intersection, as long as the lower set.
;; Also: INT (A2POSRM, UCSD20, WK11)
.proc OpINT

;; How many of the lower set's bytes are past the top set's, which become 0.
Excess = Dictionary

    jsr PopSetOperands

    ; X = the bytes to AND: the top set's size, if the lower set is at least as long, and Excess = how much longer.
    ldx PopSetOperands::TopSize
    sec
    sbc PopSetOperands::TopSize
    bpl SetExcess

    ; If it is shorter, X = its own size, and Excess = 0.
    clc
    adc PopSetOperands::TopSize
    tax
    lda #0
SetExcess:
    sta Excess

    ; AND the top set's bytes into the lower set's.
    cpx #0
    beq ClearExcess
AndByte:
    pla
    and Stack,y
    sta Stack,y
    iny
    dex
    bne AndByte

    ; Clear the lower set's bytes past the top set's.
ClearExcess:
    ldx Excess
    beq Done
    bmi Done
    lda #0
ClearByte:
    sta Stack,y
    iny
    dex
    bne ClearByte

    ; Drop the rest of the top set, leaving the lower set and its length.
Done:
    ldx PopSetOperands::LowerLength
    dex
    txs
    jmp Fetch::Skip1
.endproc

;; <DIF at OpDIF>: pops two sets and pushes the lower one without the top one's elements, as long as the lower set.
;; Also: DIF (A2POSRM, WK11)
.proc OpDIF
    jsr PopSetOperands

    ; Clear bits in the shorter set's size in bytes.
    ldx PopSetOperands::TopSize
    cmp PopSetOperands::TopSize
    bpl Clear
    tax
Clear:
    cpx #0
    beq Done
ClearBits:
    pla
    eor #$FF
    and Stack,y
    sta Stack,y
    iny
    dex
    bne ClearBits

    ; Drop the rest of the top set, leaving the lower set and its length.
Done:
    ldx PopSetOperands::LowerLength
    dex
    txs
    jmp Fetch::Skip1
.endproc

;; <UNI at OpUNI>: pops two sets and pushes their union, as long as the longer of the two.
;; Also: UNI (A2POSRM, UCSD20, WK11)
.proc OpUNI

;; The lower set's size in bytes, when it is the shorter.
LowerSize = Buffer

;; A count of bytes.
Count = ProcedureNumber

    jsr PopSetOperands

    ; Is the top set the longer?
    cmp PopSetOperands::TopSize
    bmi TopLonger

    ; No: OR its bytes into the lower set's.
    ldx PopSetOperands::TopSize
    cpx #0
    beq Done
OrIntoLower:
    pla
    ora Stack,y
    sta Stack,y
    iny
    dex
    bne OrIntoLower

    ; Drop the rest of the top set, leaving the lower set and its length.
Done:
    ldx PopSetOperands::LowerLength
    dex
    txs
    jmp Fetch::Skip1

    ; Yes: OR the lower set's bytes into the top set's.
TopLonger:
    sta LowerSize
    cmp #0
    bne OrIntoTop
    beq MoveTop
OrIntoTop:
    tsx
    inx
    ldy PopSetOperands::LowerSet
    lda LowerSize
    sta Count
    lda LowerSize+1
    sta Count+1
OrByte:
    lda Stack,y
    ora Stack,x
    sta Stack,x
    iny
    inx
    dec Count
    bne OrByte

    ; Move the top set up, last byte first, to end where the lower set ended.
MoveTop:
    lda PopSetOperands::LowerSet
    clc
    adc LowerSize
    tax
    dex
    lda PopSetOperands::TopSize
    sta Count
    lda PopSetOperands::TopSize+1
    sta Count+1
    ldy PopSetOperands::LowerLength
    dey
MoveByte:
    lda Stack,y
    sta Stack,x
    dey
    dex
    dec Count
    bne MoveByte
    txs

    ; Push its length in words. Its high byte is TopSize+1, which nothing here sets.
    lsr PopSetOperands::TopSize
    lda PopSetOperands::TopSize+1
    pha
    lda PopSetOperands::TopSize
    pha
    jmp Fetch::Skip1
.endproc

;; <ADJ at OpADJ>: pops a set's length and makes its bytes as many words as its operand says: cuts bytes off its end, or
;; adds zeros. The set stays on the stack without its length.
;; Also: ADJ (A2POSRM, UCSD20)
.proc OpADJ

;; The set's size in bytes.
SetSize = Result+2

;; The size it must have, in bytes.
WantedSize = Result+4

;; How many bytes of zeros it needs.
Extra = Work1

    ; Read the wanted size, and pop the set's size, as bytes. Are they the same?
    ldy #1
    lda (IPC),y
    asl a
    sta WantedSize
    pla
    sta SetSize
    pla
    sta SetSize+1
    asl SetSize
    rol SetSize+1
    lda SetSize
    cmp WantedSize
    bne Change
    jmp Fetch::Skip2

    ; Too long: move the first bytes it keeps up, last byte first, to end where the set ended.
Change:
    bmi Extend
    tsx
    txa
    clc
    adc WantedSize
    tay
    txa
    clc
    adc SetSize
    tax
MoveUp:
    lda Stack,y
    sta Stack,x
    dey
    dex
    dec WantedSize
    bne MoveUp
    txs
    jmp Fetch::Skip2

    ; Too short: an empty set only needs room for the zeros. X would be 0 only if the stack had wrapped, so the
    ; BNE always branches.
Extend:
    lda WantedSize
    sec
    sbc SetSize
    sta Extra
    cmp WantedSize
    bne MoveDown
    tsx
    txa
    sec
    sbc Extra
    tax
    txs
    inx
    bne Zeros

    ; Make room for the zeros, and move the set's bytes down into it, first byte first.
MoveDown:
    tsx
    txa
    tay
    iny
    sec
    sbc Extra
    tax
    txs
    inx
MoveByte:
    lda Stack,y
    sta Stack,x
    iny
    inx
    dec SetSize
    bne MoveByte

    ; Add the zeros after the set's bytes.
Zeros:
    ldy Extra
    lda #0
StoreZero:
    sta Stack,x
    inx
    dey
    bne StoreZero
    jmp Fetch::Skip2
.endproc

;; <INN at OpINN>: pops a set and the element below it, and pushes true when the element is in the set.
;; Also: INN (A2POSRM, UCSD20, WK11)
.proc OpINN

;; The set's size in bytes.
SetSize = Result+2

;; The element.
Element = Procedure

;; The stack pointer once the set and the element are popped.
;; Also: SPTEMP (WK11)
SavedStack = Scratch

;; The element's byte in the set.
ByteIndex = Pointer

;; The element's bit in its byte.
BitIndex = Pointer+1

    ; Pop the set's size, as bytes, and read the element past the set.
    pla
    sta SetSize
    pla
    sta SetSize+1
    asl SetSize
    rol SetSize+1
    tsx
    txa
    clc
    adc SetSize
    tay
    iny
    lda Stack,y
    sta Element
    iny
    lda Stack,y
    sta Element+1
    sty SavedStack

    ; An element of 512 or more is in no set.
    and #SET_ELEMENT_HIGH_MASK
    bne NotIn

    ; Find its bit and its byte. Past the set's end, it is not in it.
    lda Element
    and #BYTE_BIT_MASK
    sta BitIndex
    ror Element+1
    lda Element
    ror a
    ror a
    ror a
    and #SET_BYTE_MASK
    sta ByteIndex
    cmp SetSize
    bpl NotIn

    ; Test the bit. The compare left the carry clear for the add.
    tsx
    inx
    txa
    adc ByteIndex
    tax
    lda Stack,x
    ldy BitIndex
    and BitMasks,y
    beq NotIn

    ; Drop the set and the element, and push true.
    ldx SavedStack
    txs
    lda #0
    pha
    lda #BOOLEAN_TRUE
    pha
    jmp Fetch::Skip1

    ; Drop the set and the element, and push false.
NotIn:
    ldx SavedStack
    txs
    lda #BOOLEAN_FALSE
    pha
    pha
    jmp Fetch::Skip1
.endproc

;; A byte with each bit set, for <INN at OpINN>.
;; Also: BITTBL (WK11)
BitMasks:
    BitMask 0
    BitMask 1
    BitMask 2
    BitMask 3
    BitMask 4
    BitMask 5
    BitMask 6
    BitMask 7

;; <SGS at OpSGS>: pops an element and pushes the set of just that element, by pushing it twice and going on into
;; <OpSRS>.
;; Also: SGS (A2POSRM, UCSD20, WK11)
.proc OpSGS

;; The element.
Element = Result

    ; Push the element as both bounds.
    pla
    sta Element
    pla
    sta Element+1
    lda Element+1
    pha
    lda Element
    pha
    lda Element+1
    pha
    lda Element
    pha
.endproc

;; <SRS at OpSRS>: pops an upper and a lower bound, and pushes the set of the elements from one to the other, or the
;; empty set when the lower is the greater. A negative lower bound, or an upper one above 511, pushes the empty set and
;; reports <ERROR_VALUE_RANGE>.
;; Also: SRS (A2POSRM, UCSD20, WK11)
.proc OpSRS

;; The upper bound, which was on top.
Upper = Buffer

;; The lower bound.
Lower = Procedure

;; The upper bound less the lower, for its sign.
Span = Mark

;; The lower bound's word in the set.
LowerWord = Pointer

;; The lower bound's bit in its word, times 2, to index <HighMasks>.
LowerBit = Pointer+1

;; The upper bound's word in the set.
UpperWord = Pointer2

;; The upper bound's bit in its word, times 2, to index <LowMasks>.
UpperBit = Pointer2+1

;; The word being pushed.
Bits = ProcedureNumber

    ; Pop the bounds. The lower must not be negative, and the upper not above 511.
    pla
    sta Upper
    pla
    sta Upper+1
    pla
    sta Lower
    pla
    sta Lower+1
    lda Lower+1
    bpl CheckUpper
    jmp OutOfRange
CheckUpper:
    lda Upper+1
    and #SET_ELEMENT_HIGH_MASK
    beq CheckOrder
    jmp OutOfRange

    ; If the lower is the greater, the set is empty.
CheckOrder:
    sec
    lda Upper
    sbc Lower
    sta Span
    lda Upper+1
    sbc Lower+1
    sta Span+1
    lda Span+1
    bpl FindLower
    jmp Empty

    ; Find the lower bound's word and bit.
FindLower:
    lda Lower
    and #WORD_BIT_MASK
    asl a
    sta LowerBit
    lda Lower
    ldx #4
ShiftLower:
    ror Lower+1
    ror a
    dex
    bne ShiftLower
    sta LowerWord

    ; Find the upper bound's word and bit.
    lda Upper
    and #WORD_BIT_MASK
    asl a
    sta UpperBit
    lda Upper
    ldx #4
ShiftUpper:
    ror Upper+1
    ror a
    dex
    bne ShiftUpper
    sta UpperWord

    ; The upper word has its bits up to the upper bound set. X = the words from the lower bound's to the upper's.
    sec
    lda UpperWord
    sbc LowerWord
    tax
    ldy UpperBit
    lda LowMasks+2,y
    sta Bits
    lda LowMasks+3,y
    sta Bits+1

    ; If they are different words, push the upper word, then a word of all bits for each word between.
    cpx #0
    beq PushLowerWord
    lda Bits+1
    pha
    lda Bits
    pha
    lda #$FF
    sta Bits
    sta Bits+1
    bne CountWord
PushFull:
    lda Bits+1
    pha
    lda Bits
    pha
CountWord:
    dex
    bne PushFull

    ; Push the lower bound's word, without the bits below the lower bound.
PushLowerWord:
    lda Bits
    ldy LowerBit
    and HighMasks,y
    sta Bits
    lda Bits+1
    and HighMasks+1,y
    sta Bits+1
    lda Bits+1
    pha
    lda Bits
    pha

    ; Push an empty word for each word below it.
    lda #0
    sta Bits
    sta Bits+1
    ldx LowerWord
    beq PushLength
PushEmpty:
    lda Bits+1
    pha
    lda Bits
    pha
    dex
    bne PushEmpty

    ; Push the length: up to the upper bound's word.
PushLength:
    lda #0
    pha
    clc
    lda UpperWord
    adc #1
    pha
    jmp Fetch::Skip1

    ; Push the empty set: a length of 0.
Empty:
    lda #0
    pha
    pha
    jmp Fetch::Skip1

OutOfRange:
    lda #0
    pha
    pha
    jmp ExecutionError::ValueRange
.endproc

;; Words with their low bits set, from none to all 16, for packed fields and subrange sets.
LowMasks:
    LowMask 0
    LowMask 1
    LowMask 2
    LowMask 3
    LowMask 4
    LowMask 5
    LowMask 6
    LowMask 7
    LowMask 8
    LowMask 9
    LowMask 10
    LowMask 11
    LowMask 12
    LowMask 13
    LowMask 14
    LowMask 15
    LowMask 16

;; Words with their bits from bit 0, 1 .. 15 up to bit 15 set, for subrange sets.
HighMasks:
    HighMask 0
    HighMask 1
    HighMask 2
    HighMask 3
    HighMask 4
    HighMask 5
    HighMask 6
    HighMask 7
    HighMask 8
    HighMask 9
    HighMask 10
    HighMask 11
    HighMask 12
    HighMask 13
    HighMask 14
    HighMask 15
