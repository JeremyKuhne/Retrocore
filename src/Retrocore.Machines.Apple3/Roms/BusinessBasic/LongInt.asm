; retrocore: style=strict
;; Business BASIC: long integers
;;
;; Reading and printing them, their arithmetic and comparisons, and the conversions between them, reals and strings
;; (the `CONV` functions).
;;
;; A long integer is eight bytes of two's complement, most significant byte first, from -(2^63) to 2^63-1; a long
;; variable's value is those eight bytes as they are, and <VALTYP> is <VALUE_TYPE_LONG_INTEGER> while one is in the
;; <FAC>. The arithmetic works on three eight-byte numbers in BASIC's zero page: <FAC> (over the real one's bytes),
;; <ARG> and <RES>, with the byte below RES (RES-1) catching a product's or quotient's overflow. Most routines reach
;; their operands through <PTR1>, <PTR2> and <PTR3>, which <LongInteger::PointAtOperands> points at <FAC>, <ARG> and
;; <FAC>. A binary operator gets its left operand in <ARG> and its right in <FAC>.
;;
;; Apple's listing calls this file LONGINT. Part of BusinessBasic.asm.

;; Business BASIC's long integers: their input and output, arithmetic, comparisons and conversions.
;;
;; The operators here are the long-integer column of the operator dispatch table, for `+`, `-`, `*`, `/`, `DIV`, `MOD`,
;; `AND`, `OR` and the relations.
.scope LongInteger

;; The bytes of a long integer.
SIZE = 8

;; The bits of a long integer.
BITS = 8 * SIZE

;; The bytes of the binary-coded decimal number <LongInteger::FacToDigits> builds in <ARG> and the two bytes after it.
DECIMAL_SIZE = SIZE + 2

;; The decimal digits <LongInteger::FacToDigits> makes, two to each of <DECIMAL_SIZE>'s bytes.
DECIMAL_DIGITS = 2 * DECIMAL_SIZE

; The relations <DOMASK> asks <LongInteger::Compare> for.

;; <ARG> is less than <FAC>.
RELATION_LESS = 4

;; <ARG> equals <FAC>.
RELATION_EQUAL = 2

;; <ARG> is greater than <FAC>.
RELATION_GREATER = 1

; ---------------------------------------------------------------------------------------------------------------------
; Input
; ---------------------------------------------------------------------------------------------------------------------

;; Reads a long integer from the text at <TXTPTR> into <FAC>.
;;
;; An optional sign and then digits; a fraction after a period rounds the number to the nearest integer, an exact half
;; to the even one. There is no exponent. -(2^63) itself can't be read: its digits are an overflow before the sign is
;; applied.
;; In: TXTPTR = the number's first character
;; Out: FAC = the number, VALTYP = <VALUE_TYPE_LONG_INTEGER>, TXTPTR = the first character after it
;; Errors: ERROV = the number is out of range
;; Uses: ARG, KIMY, YSAVE, PTR1, PTR2, PTR3
;; See: <FIN>, <LongInteger::FormatFac>
;; Also: LINP (BB13)
.proc ReadNumber
    lda #VALUE_TYPE_LONG_INTEGER
    sta VALTYP
    lda #0
    sta KIMY                                ; bit 7 set for a minus sign
    ldx #SIZE - 1

;; Zeros <FAC> and <ARG>.
;; Also: LZFAC1 (BB13)
ClearLoop:
    sta FAC,X
    sta ARG,X
    dex
    bpl ClearLoop
    jsr CHRGOT
    bcc TakeDigit                           ; a digit
    cmp #'+'
    beq NextCharacter
    cmp #'-'
    bne CheckFraction
    lda #$FF
    eor KIMY
    sta KIMY
    jmp NextCharacter

;; Takes a digit into <FAC>: <FAC> = <FAC> * 10 + the digit.
;; In: A = the digit's character
;; Also: LISNUM (BB13)
TakeDigit:
    and #$0F
    sta YSAVE
    jsr MultiplyFacByTen
    jsr ClearArg
    lda YSAVE
    sta ARG+SIZE-1
    jsr AddAt                               ; FAC = FAC + ARG, through MultiplyFacByTen's pointers

;; Goes on to the next character, taking it if it is a digit.
;; Also: LTRYN2 (BB13)
NextCharacter:
    jsr CHRGET
    bcc TakeDigit

;; Rounds by the fraction after a period, if any: up from a first digit above 5, or of 5 with any other digit after it.
;; Also: LTRYDOT (BB13)
CheckFraction:
    cmp #'.'
    bne ApplySign
    jsr CHRGET
    bcs ApplySign
    cmp #'5'
    bcc SkipFraction                        ; below .5: down
    bne RoundUp                             ; above .5: up

;; After a 5, looks for a digit other than 0, which rounds up; with none, the number rounds to even.
;; Also: LTRYN3 (BB13)
SeekNonzeroDigit:
    jsr CHRGET
    bcs RoundToEven                         ; exactly .5
    cmp #'1'
    bcc SeekNonzeroDigit

;; Rounds up, then skips the fraction's other digits.
;; Also: LROUNDUP (BB13)
RoundUp:
    jsr IncrementFac

;; Skips the fraction's remaining digits.
;; Also: LNUMSCN (BB13)
SkipFraction:
    jsr CHRGET
    bcc SkipFraction
    bcs ApplySign

;; Rounds exactly half to the even integer: up when <FAC> is odd.
;; Also: LRNDEVN (BB13)
RoundToEven:
    lda FAC+SIZE-1
    and #1
    beq ApplySign
    jsr IncrementFac

;; Ends the number, negating it for a minus sign.
;; Also: LNUMDON (BB13)
ApplySign:
    lda KIMY
    bpl IncrementFac::Done
    ; Falls into NegateFac.
.endproc

;; Negates <FAC>.
;;
;; The overflow test in <LongInteger::IncrementFac> misfires here: negating $FF00000000000000 (-(2^56)) or
;; $7F00000000000000 gives an overflow error though the result fits, so -(2^56) can be neither printed nor converted to
;; a real; and negating -(2^63), which doesn't fit, gives -(2^63) with no error.
;; Out: FAC = -<FAC>
;; Errors: ERROV = see above
;; Uses: A, X
;; Keeps: Y
;; See: <LongInteger::NegateAt>
;; Also: LTWSCOMP (BB13)
.proc NegateFac
    ldx #SIZE - 1

;; Complements <FAC>'s bytes, before <LongInteger::IncrementFac> adds one.
;; Also: LTWSONE (BB13)
ComplementLoop:
    lda FAC,X
    eor #$FF
    sta FAC,X
    dex
    bpl ComplementLoop
    ; Falls into IncrementFac.
.endproc

;; Adds one to <FAC>.
;;
;; When the carry reaches the top byte, the test for overflow looks at A rather than at <FAC>: from
;; <LongInteger::NegateFac>, A is the top byte before the increment, and an error comes when it was $00 or $80, which
;; is not the overflow case; from <LongInteger::ReadNumber>'s rounding, A is never zero there, so rounding
;; 9223372036854775807.5 up wraps to -(2^63) with no error.
;; Out: FAC = <FAC> + 1
;; Errors: ERROV = see above
;; Uses: X
;; Keeps: Y
;; Entry:
;;   ToOverflowError = ends with an overflow error; <LongInteger::MultiplyFacByTen> branches here
;;   Done = returns; <LongInteger::ReadNumber> branches here
;; Also: LINCFAC (BB13)
.proc IncrementFac
    ldx #SIZE - 1

;; Increments <FAC>'s bytes from the lowest while each carries.
;; Also: LTWSCO2 (BB13)
IncrementLoop:
    inc FAC,X
    bne Done
    dex
    bne IncrementLoop
    inc FAC
    and #$7F                                ; tests A, not FAC
    bne Done

;; Ends with an overflow error.
;; Also: LOVINP (BB13)
ToOverflowError:
    jmp OverflowError

;; Returns.
;; Also: LDONE (BB13)
Done:
    rts
.endproc

;; Multiplies <FAC> by 10, as <FAC> * 2 + <FAC> * 8, and leaves <LongInteger::PointAtOperands>'s pointers set.
;; In: FAC = a positive number
;; Out: FAC = <FAC> * 10, ARG = <FAC> * 2
;; Errors: ERROV = the product is out of range
;; Uses: PTR1, PTR2, PTR3
;; Also: LTIMES10 (BB13)
.proc MultiplyFacByTen
    jsr PointAtOperands
    lda #<(FAC)
    jsr ShiftLeft                           ; times 2
    bmi IncrementFac::ToOverflowError
    jsr CopyFacToArg
    jsr ShiftLeft                           ; times 4
    bmi IncrementFac::ToOverflowError
    jsr ShiftLeft                           ; times 8
    bmi IncrementFac::ToOverflowError
    jsr AddAt
    rts
.endproc

;; Copies <FAC> to <ARG>.
;; Out: X = 0
;; Keeps: A, Y
;; Also: FACTOARG (BB13)
.proc CopyFacToArg
    pha
    ldx #SIZE

;; Copies <FAC>'s bytes to <ARG>, from the last.
;; Also: FAC2AR2 (BB13)
CopyLoop:
    lda FAC-1,X
    sta ARG-1,X
    dex
    bne CopyLoop
    pla
    rts
.endproc

; ---------------------------------------------------------------------------------------------------------------------
; Signs and results
; ---------------------------------------------------------------------------------------------------------------------

;; Makes the two operands positive for a multiply or divide, noting the result's sign.
;; In: PTR1, PTR2 = the operands, in zero page
;; Out: INPFLG = bit 7 set when the result is negative (the signs differ)
;; Uses: A, X, Y
;; See: <LongInteger::ReturnResult>
;; Also: LSGNPOS (BB13)
.proc MakeOperandsPositive
    ldy #0
    lda (PTR1),Y
    eor (PTR2),Y
    sta INPFLG
    lda (PTR1),Y
    bpl SecondOperand
    lda PTR1
    jsr NegateAt

;; Makes the second operand positive.
;; Also: LSGNP2 (BB13)
SecondOperand:
    ldy #0
    lda (PTR2),Y
    bpl Done
    lda PTR2
    jsr NegateAt

;; Returns.
;; Also: LSGNP3 (BB13)
Done:
    rts
.endproc

;; Moves a product from <RES> to <FAC> with its sign, or ends with an overflow error when it grew past RES.
;; In: RES-1, RES = the product's magnitude, INPFLG = bit 7 set for a negative result
;; Out: FAC = the product
;; Errors: ERROV = the product is out of range
;; See: <LongInteger::Multiply>
;; Also: LRESPOS (BB13)
.proc ReturnProduct
    lda RES-1
    bne OverflowError
    ; Falls into ReturnQuotient.
.endproc

;; Moves a quotient from <RES> to <FAC> with its sign.
;; In: RES = the quotient's magnitude, INPFLG = bit 7 set for a negative result
;; Out: FAC = the quotient
;; Errors: ERROV = the quotient is out of range
;; Also: LRESDIV (BB13)
.proc ReturnQuotient
    lda #<(RES)
    sta PTR3
    ; Falls into ReturnResult.
.endproc

;; Moves a result from (<PTR3>) to <FAC>, negating it first when <INPFLG> says the result is negative.
;;
;; Bit 7 of <RES> is checked even when the result is elsewhere, so <LongInteger::Mod> gives an overflow error whenever
;; the quotient's magnitude is 2^63 (`-(2^63) MOD 1`), though the remainder fits.
;; In: PTR3 = the result's magnitude, in zero page, INPFLG = bit 7 set for a negative result
;; Out: FAC = the result
;; Errors: ERROV = bit 7 of RES is set
;; Also: LRESDV (BB13)
.proc ReturnResult
    lda #<(FAC)
    sta PTR1
    lda RES
    bmi OverflowError
    lda INPFLG
    bpl Copy
    lda PTR3
    jsr NegateAt

;; Copies the eight bytes.
;; Also: LRESP2 (BB13)
Copy:
    ldy #SIZE - 1

;; Copies a byte, from the last.
;; Also: LRES2F2 (BB13)
CopyLoop:
    lda (PTR3),Y
    sta (PTR1),Y
    dey
    bpl CopyLoop
    rts
.endproc

; ---------------------------------------------------------------------------------------------------------------------
; Utilities, addition and subtraction
; ---------------------------------------------------------------------------------------------------------------------

;; Zeros <RES> and the overflow byte below it.
;; Out: A = 0, X = $FF
;; Keeps: Y
;; Also: LZIPRES (BB13)
.proc ClearResult
    lda #0
    ldx #SIZE

;; Zeros a byte, from the last.
;; Also: LZIP2 (BB13)
ClearLoop:
    sta RES-1,X
    dex
    bpl ClearLoop
    rts
.endproc

;; Stores <FAC> as a long integer in memory.
;; In: A = the address's low byte, Y = its high byte, X = its bank
;; Uses: INDEX, INDEXB, Y
;; Keeps: X
;; See: <LongInteger::LoadFac>
;; Also: STFACT (BB13)
.proc StoreFac
    sta INDEX
    stx INDEXB
    sty INDEX+1
    ldy #SIZE - 1

;; Stores a byte, from the last.
;; Also: STFAC2 (BB13)
StoreLoop:
    lda FAC,Y
    sta (INDEX),Y
    dey
    bpl StoreLoop
    rts
.endproc

;; Points <PTR1> and <PTR3> at <FAC> and <PTR2> at <ARG>, all in zero page, for <FAC> = <FAC> op <ARG>.
;; Out: A = <ARG>'s address, Y = 0
;; Keeps: X
;; Also: LPTRS (BB13)
.proc PointAtOperands
    ldy #0
    sty PTR1+1
    sty PTR2+1
    sty PTR3+1
    sty PTR1B
    sty PTR2B
    sty PTR3B
    lda #<(FAC)
    sta PTR1
    sta PTR3
    lda #<(ARG)
    sta PTR2
    rts
.endproc

;; The `+` operator for long integers: <FAC> = <ARG> + <FAC>.
;; Errors: ERROV = the sum is out of range
;; Also: LADD (BB13)
.proc Add
    jsr PointAtOperands
    ; Falls into AddAt.
.endproc

;; Adds two long integers: (<PTR3>) = (<PTR1>) + (<PTR2>).
;; Errors: ERROV = the sum is out of range
;; Keeps: X
;; Also: LADDPTR (BB13)
.proc AddAt
    ldy #SIZE - 1
    clc

;; Adds a byte, from the last.
;; Also: LADD2 (BB13)
AddLoop:
    lda (PTR1),Y
    adc (PTR2),Y
    sta (PTR3),Y
    dey
    bpl AddLoop
    bvs OverflowError
    rts
.endproc

;; Ends the statement with an overflow error.
;; Also: LOVERR (BB13)
.proc OverflowError
    ldx #ERROV
    jmp ERROR
.endproc

;; Subtracts with the pointers set: <FAC> = <ARG> - <FAC>, with no overflow check.
;; Out: overflow = set when the result is out of range
;; Also: LSUBB (BB13)
.proc SubtractUnchecked
    jsr PointAtOperands
    ; Falls into SubtractAt.
.endproc

;; Subtracts two long integers: (<PTR3>) = (<PTR2>) - (<PTR1>), with no overflow check.
;; Out: carry = clear for a borrow, overflow = set when the result is out of range
;; Keeps: X
;; Also: LSUBER (BB13)
.proc SubtractAt
    ldy #SIZE - 1
    sec

;; Subtracts a byte, from the last.
;; Also: LSUB2 (BB13)
SubtractLoop:
    lda (PTR2),Y
    sbc (PTR1),Y
    sta (PTR3),Y
    dey
    bpl SubtractLoop
    rts
.endproc

;; The `-` operator for long integers: <FAC> = <ARG> - <FAC>.
;; Errors: ERROV = the difference is out of range
;; Also: LSUB (BB13)
.proc Subtract
    jsr SubtractUnchecked
    bvs OverflowError
    rts
.endproc

;; Negates a long integer in zero page.
;;
;; -(2^63) stays itself.
;; In: A = the number's zero page address
;; Uses: A, X, Y
;; See: <LongInteger::NegateFac>
;; Also: TWOSCOMP (BB13)
.proc NegateAt
    tax
    ldy #SIZE - 1

;; Complements the bytes, from the first.
;; Also: LEORIT (BB13)
ComplementLoop:
    lda 0,X
    eor #$FF
    sta 0,X
    inx
    dey
    bpl ComplementLoop
    ldy #SIZE - 1

;; Adds one, from the last byte, while each carries.
;; Also: INCPTR2 (BB13)
IncrementLoop:
    dex
    inc 0,X
    bne Done
    dey
    bpl IncrementLoop

;; Returns.
;; Also: INCRT2 (BB13)
Done:
    rts
.endproc

; ---------------------------------------------------------------------------------------------------------------------
; Multiplication
; ---------------------------------------------------------------------------------------------------------------------

;; The `*` operator for long integers: <FAC> = <ARG> * <FAC>.
;;
;; Multiplies the magnitudes a byte by a byte into <RES>, skipping zero bytes, then gives the product its sign.
;; Errors: ERROV = the product is out of range
;; Uses: ARG, RES, INDEX, KIMY, INPFLG, PTR1, PTR2, PTR3
;; See: <LongInteger::MultiplyBytes>, <LongInteger::ReturnProduct>
;; Also: LMULT (BB13)
.proc Multiply
    jsr PointAtOperands
    jsr MakeOperandsPositive
    lda #<(FAC+SIZE-1)
    sta PTR1                                ; the row: FAC's bytes, from the last
    lda #<(ARG+SIZE-1)
    sta PTR2                                ; the column: ARG's bytes, from the last
    lda #<(RES+SIZE-2)
    sta PTR3                                ; where the first byte product goes
    jsr ClearResult

;; Multiplies the row's byte of <FAC> by each byte of <ARG>.
;; Also: LMULT1 (BB13)
Row:
    ldy #0
    lda (PTR1),Y
    beq NextRow                             ; a zero byte: skip the row

;; Multiplies the row's byte by one byte of <ARG>, unless it is zero.
;; Also: LMULT2 (BB13)
Column:
    lda (PTR2),Y
    beq *+5
    jsr MultiplyBytes
    dec PTR3                                ; the next product a byte higher
    dec PTR2
    lda PTR2
    cmp #ARG
    bcs Column
    lda #<(ARG+SIZE-1)
    sta PTR2                                ; back to ARG's last byte
    lda PTR3
    clc
    adc #SIZE
    sta PTR3

;; Moves on to the next byte of <FAC>, a byte higher in <RES>.
;; Also: LMULT3 (BB13)
NextRow:
    dec PTR3
    dec PTR1
    lda PTR1
    cmp #FAC
    bcs Row
    jmp ReturnProduct
.endproc

;; Multiplies the byte at (<PTR1>) by the byte at (<PTR2>) and adds the 16-bit product into <RES> at (<PTR3>).
;; In: Y = 0, PTR3 = where the product's high byte goes
;; Out: Y = 0
;; Errors: ERROV = the product or its carry would go above RES-1
;; Uses: A, X, INDEX, KIMY
;; Keeps: Y
;; Also: LMULTBYT (BB13)
.proc MultiplyBytes
    sty INDEX                               ; the product: INDEX high, INDEX+1 low
    sty INDEX+1
    lda (PTR1),Y
    sta KIMY
    ldx #8

;; Adds the multiplicand for each 1 bit of the multiplier, shifting the product right.
;; Also: LMULTB2 (BB13)
BitLoop:
    ror KIMY
    bcc ShiftProduct
    lda (PTR2),Y
    clc
    adc INDEX
    sta INDEX

;; Shifts the product right a bit, with the carry from the add.
;; Also: LMULTB3 (BB13)
ShiftProduct:
    ror INDEX
    ror INDEX+1
    dex
    bne BitLoop
    lda PTR3
    cmp #RES-1
    bcs *+5

;; Ends with an overflow error.
;; Also: LMULTOV (BB13)
ToOverflowError:
    jmp OverflowError
    ldx PTR3
    lda INDEX+1
    clc
    adc 1,X
    sta 1,X
    lda INDEX
    adc 0,X
    sta 0,X
    bcc Done

;; Carries into the bytes above, as far as RES-1.
;; Also: LMULTB4 (BB13)
CarryLoop:
    dex
    cpx #RES-1
    bcc ToOverflowError
    inc 0,X
    beq CarryLoop

;; Returns.
;; Also: LMULTBR (BB13)
Done:
    rts
.endproc

; ---------------------------------------------------------------------------------------------------------------------
; Shifts
; ---------------------------------------------------------------------------------------------------------------------

;; Shifts a long integer in zero page left one bit, a 0 in.
;; In: A = the number's zero page address
;; Out: Y = the new top byte, negative = its bit 7, carry = the bit shifted out
;; Uses: X
;; Keeps: A
;; Also: LSHFTL (BB13)
.proc ShiftLeft
    clc
    ; Falls into ShiftLeftWithCarry.
.endproc

;; Shifts a long integer in zero page left one bit, the carry in.
;; In: A = the number's zero page address, carry = the bit to shift in
;; Out: Y = the new top byte, negative = its bit 7, carry = the bit shifted out
;; Uses: X
;; Keeps: A
;; Also: LSHFTLC (BB13)
.proc ShiftLeftWithCarry
    tax
    ldy #SIZE

;; Rotates a byte, from the last.
;; Also: LSHFT2 (BB13)
RotateLoop:
    rol SIZE-1,X
    dex
    dey
    bne RotateLoop
    ldy SIZE,X
    rts
.endproc

;; Shifts a long integer in zero page right one bit, a 0 in.
;; In: A = the number's zero page address
;; Out: carry = the bit shifted out
;; Uses: X, Y
;; Keeps: A
;; Also: LSHFTR (BB13)
.proc ShiftRight
    clc
    tax
    ldy #SIZE

;; Rotates a byte, from the first.
;; Also: LSHFTR2 (BB13)
RotateLoop:
    ror 0,X
    inx
    dey
    bne RotateLoop
    rts
.endproc

;; Shifts <FAC> left eight bits, a byte at a time.
;; Out: X = 0
;; Keeps: Y
;; Also: LSHLEIGT (BB13)
.proc ShiftFacLeftByte
    ldx #0

;; Moves a byte up.
;; Also: LSHLE2 (BB13)
MoveLoop:
    lda FAC+1,X
    sta FAC,X
    inx
    cpx #SIZE - 1
    bcc MoveLoop
    ldx #0
    stx FAC+SIZE-1
    rts
.endproc

; ---------------------------------------------------------------------------------------------------------------------
; Division
; ---------------------------------------------------------------------------------------------------------------------

;; Divides the magnitude of <ARG> by that of <FAC>, the work of `DIV`, `/` and `MOD`.
;;
;; <FAC>, the divisor, is shifted left until its top 1 bit is bit 62, <KIMY> times. The dividend in <ARG> is then
;; compared with it and shifted left <KIMY> + 1 times, the divisor subtracted whenever it fits, and each step's quotient
;; bit shifted into <RES>. RES-1 has bit 7 set from the first subtraction on; RES is not shifted before it, as its bits
;; are all zero.
;; Out: RES = the quotient's magnitude, ARG = the remainder shifted left <KIMY> + 1 bits,
;;   carry = set when twice the remainder is at least the divisor, INPFLG = bit 7 set for a negative result
;; Errors: ERRDV0 = <FAC> is zero
;; Uses: YSAVE, PTR1, PTR2, PTR3
;; See: <LongInteger::Div>, <LongInteger::Divide>, <LongInteger::Mod>
;; Also: LDIVER (BB13)
.proc DivideMagnitudes
    jsr PointAtOperands
    jsr ClearResult
    jsr MakeOperandsPositive
    jsr NormalizeFac
    ldx KIMY
    stx YSAVE
    lda #<(ARG)
    sta PTR3                                ; differences go to ARG
    inc YSAVE                               ; KIMY + 1 steps
    bne Step                                ; always

;; Shifts the quotient bit in the carry into <RES>, once a subtraction has been made, and the dividend left.
;; Also: LDECYSAV (BB13)
ShiftQuotient:
    lda RES-1
    bpl ShiftDividend
    lda #<(RES)
    jsr ShiftLeftWithCarry

;; Shifts the dividend left.
;; Also: LRESOK (BB13)
ShiftDividend:
    lda #<(ARG)
    jsr ShiftLeft

;; Compares the dividend with the divisor and subtracts it when it fits, until the steps are done.
;; Also: LDIVCOM (BB13)
Step:
    jsr CompareMagnitudes
    dec YSAVE
    bmi Done                                ; done: the carry is the next bit, for rounding
    bcc ShiftQuotient                       ; doesn't fit: a 0 bit
    jsr SubtractAt
    lda #$80
    sta RES-1                               ; a subtraction made
    bcs ShiftQuotient                       ; always: a 1 bit

;; Returns.
;; Also: LGOTRES (BB13)
Done:
    rts
.endproc

;; The `/` operator for long integers: <FAC> = <ARG> / <FAC>, rounded to the nearest integer, an exact half to the
;; even one.
;; Errors: ERRDV0 = <FAC> is zero, ERROV = the quotient is out of range
;; See: <LongInteger::DivideMagnitudes>, <LongInteger::Div>
;; Also: LDIVT (BB13)
.proc Divide
    jsr DivideMagnitudes
    bcc Finish                              ; under a half: no rounding
    jsr SubtractAt                          ; ARG = 0 when exactly a half
    lda #<(ARG)
    ldx #0
    ldy #>(ARG)
    jsr IsZero
    sta YSAVE
    lda RES+SIZE-1
    and #$1
    ora YSAVE
    beq Finish                              ; exactly a half, and the quotient is even
    ldx #SIZE

;; Adds one to the quotient in <RES>, from the last byte.
;; Also: LINCBYT (BB13)
IncrementLoop:
    inc RES-1,X
    bne Finish
    dex
    bne IncrementLoop

;; Moves the quotient to <FAC> with its sign.
;; Also: LNOROUND (BB13)
Finish:
    jmp ReturnQuotient
.endproc

;; Shifts <FAC> left until its top 1 bit is bit 62, counting the shifts.
;;
;; A negative <FAC>, only ever -(2^63), is shifted right once instead.
;; In: FAC = a positive number
;; Out: KIMY = the bits shifted left, -1 for the one right
;; Errors: ERRDV0 = <FAC> is zero
;; Also: LNRMFAC (BB13)
.proc NormalizeFac
    ldy #0
    sty KIMY

;; Shifts a byte at a time while the top byte is zero.
;; Also: LDIVE2 (BB13)
ByteLoop:
    lda FAC
    bne BitLoop
    jsr ShiftFacLeftByte
    lda KIMY
    clc
    adc #8
    sta KIMY
    cmp #BITS
    bcc ByteLoop
    jmp DV0ERR                              ; all 64 bits zero

;; Shifts a bit at a time until bit 6 of the top byte is set.
;; Also: LDIVE3 (BB13)
BitLoop:
    lda #<(FAC)
    bit FAC
    bmi TooFar
    bvs Done
    jsr ShiftLeft
    inc KIMY
    bne BitLoop                             ; always

;; Shifts the one bit right that went too far.
;; Also: LDIVTOFAR (BB13)
TooFar:
    jsr ShiftRight
    dec KIMY

;; Returns.
;; Also: LDIVOK (BB13)
Done:
    rts
.endproc

;; Compares <ARG> with <FAC> as unsigned numbers.
;; Out: carry = set when <ARG> >= <FAC>, zero = set when they are equal
;; Uses: A, X
;; Keeps: Y
;; Entry:
;;   FromByte = compares from the byte at X on; <LongInteger::Compare> calls it with X = 1
;; Also: LCOMP (BB13)
.proc CompareMagnitudes
    ldx #0

;; Compares from the byte at X on.
;; In: X = the first byte to compare
;; Out: carry = set when <ARG> >= <FAC>, zero = set when they are equal
;; Also: LCMP2 (BB13)
FromByte:
    lda ARG,X
    cmp FAC,X
    bne Done
    inx
    cpx #SIZE
    bcc FromByte

;; Returns.
;; Also: LCMP3 (BB13)
Done:
    rts
.endproc

;; The `DIV` operator for long integers: <FAC> = <ARG> / <FAC>, the fraction dropped.
;; Errors: ERRDV0 = <FAC> is zero, ERROV = the quotient is out of range
;; See: <LongInteger::DivideMagnitudes>, <LongInteger::Divide>
;; Also: LDIV (BB13)
.proc Div
    jsr DivideMagnitudes
    jmp ReturnQuotient
.endproc

;; The `MOD` operator for long integers: <FAC> = the remainder of <ARG> / <FAC>.
;;
;; The remainder of the two sizes is made negative when exactly one operand is, as a quotient would be, rather than
;; taking the dividend's sign: `-7 MOD 2` and `7 MOD -2` are both -1, and `-7 MOD -2` is 1.
;; Errors: ERRDV0 = <FAC> is zero, ERROV = the quotient's magnitude is 2^63 (<LongInteger::ReturnResult>)
;; See: <LongInteger::DivideMagnitudes>
;; Also: LREM (BB13)
.proc Mod
    jsr DivideMagnitudes
    ldy #0
    lda #<(ARG)

;; Shifts the remainder back right <KIMY> + 1 bits.
;; Also: LREM2 (BB13)
ShiftBack:
    jsr ShiftRight
    dec KIMY
    bpl ShiftBack
    sta PTR3
    jmp ReturnResult
.endproc

;; Tells whether a long integer is zero, by ORing its bytes.
;; In: A = the address's low byte, Y = its high byte, X = its bank
;; Out: A = 0 and zero = set when all eight bytes are zero
;; Uses: Y, INDEX, INDEXB
;; Keeps: X, overflow
;; Also: LORALL (BB13)
.proc IsZero
    sta INDEX
    stx INDEXB
    sty INDEX+1
    lda #0
    ldy #SIZE - 1

;; ORs in a byte, from the last, stopping at the first nonzero one.
;; Also: LORAL2 (BB13)
OrLoop:
    ora (INDEX),Y
    bne Done
    dey
    bpl OrLoop
    tay                                     ; the zero flag set

;; Returns.
;; Also: LGOTOR (BB13)
Done:
    rts
.endproc

; ---------------------------------------------------------------------------------------------------------------------
; Output
; ---------------------------------------------------------------------------------------------------------------------

;; Turns <FAC>'s long integer into decimal digits in <NUMSTR>, for <LongInteger::FormatFac> and `PRINT USING`.
;;
;; The magnitude is converted to <DECIMAL_DIGITS> binary-coded decimal digits by doubling: each bit, from the top 1 bit
;; down, doubles the decimal number in <ARG> and the two bytes after it and adds the bit. <UUNPACK> then spreads the
;; digits out, one a byte, dropping the leading zeros. <FAC> is used up. For zero, no 1 bit is found and the count of
;; bits is left from <KIMY>'s last value, which only changes how many times the zero is doubled.
;; In: FAC = the number
;; Out: NUMSTR+2.. = the digits, values 0 to 9, ISARA = twice the count of digits, plus 1 for a negative number,
;;   FACSGN = bit 7 set for a negative number
;; Errors: ERROV = <FAC> is -(2^56), from <LongInteger::NegateFac>
;; Uses: ARG, KIMY
;; See: <LongInteger::FormatFac>, <UUNPACK>
;; Also: LUNPACK (BB13)
.proc FacToDigits
    lda FACEXP                              ; FAC's top byte
    cmp #$80
    lda #DECIMAL_DIGITS
    rol
    sta ISARA                               ; 40, or 41 for a negative number
    lda FAC
    pha
    bpl *+5
    jsr NegateFac
    lda #<(FAC)
    ldx #0
    ldy #>(FAC)
    jsr IsZero
    beq *+5                                 ; zero: no 1 bit to find
    jsr NormalizeFac
    lda #BITS
    sec
    sbc KIMY
    sta KIMY                                ; the bits to convert, from bit 63
    jsr ClearArg

;; Converts one bit: shifts it out of <FAC> and doubles the decimal number with the bit added.
;; Also: LCONVBCD (BB13)
ConvertBit:
    lda #<(FAC)
    jsr ShiftLeft
    ldx #DECIMAL_SIZE
    sed

;; Doubles a byte of the decimal number with the carry, from the last.
;; Also: LADDBCD (BB13)
DoubleLoop:
    lda ARG-1,X
    adc ARG-1,X
    sta ARG-1,X
    dex
    bne DoubleLoop
    cld
    dec KIMY
    bne ConvertBit
    ldx #DECIMAL_SIZE

;; Copies the decimal number to <FACT>, where <UUNPACK> reads it.
;; Also: LABCD2 (BB13)
CopyLoop:
    lda ARG-1,X
    sta FACT-1,X
    dex
    bne CopyLoop
    jsr UUNPACK
    pla
    sta FACSGN
    rts
.endproc

;; Zeros <ARG> and the two bytes after it, RES-1 and <RES>.
;; Out: A = 0, X = 0
;; Keeps: Y
;; Also: LZIPARG (BB13)
.proc ClearArg
    lda #0
    ldx #DECIMAL_SIZE

;; Zeros a byte, from the last.
;; Also: LZIPAR2 (BB13)
ClearLoop:
    sta ARG-1,X
    dex
    bne ClearLoop
    rts
.endproc

;; Writes <FAC>'s long integer as text in <NUMSTR>: a minus sign if negative, then the digits, then a zero.
;; In: FAC = the number
;; Out: NUMSTR = the text, LENUM = its length, X = its length
;; Errors: ERROV = <FAC> is -(2^56), from <LongInteger::NegateFac>
;; See: <LongInteger::FacToDigits>, <Functions::ConvString>
;; Also: LOUT (BB13)
.proc FormatFac
    jsr FacToDigits
    ldx #0
    lda #'0'
    sta NUMSTR                              ; for zero, which has no digits
    lsr ISARA                               ; the count of digits
    ldy #1

;; Takes the next digit, ending when there are no more.
;; Also: LLOOKLUP (BB13)
NextDigit:
    iny
    dec ISARA
    bmi Finish
    lda NUMSTR,Y
    cpx #0
    beq WriteSign                           ; the first digit: the sign goes before it

;; Writes a digit as its character.
;; Also: LOUT5 (BB13)
WriteDigit:
    ora #'0'
    sta NUMSTR,X
    inx
    bne NextDigit

;; Writes a minus sign before the first digit of a negative number.
;; Also: LOUT3 (BB13)
WriteSign:
    sta KIMY
    bit FACSGN
    bpl WriteFirstDigit
    lda #'-'
    sta NUMSTR,X
    inx

;; Takes the first digit back to write it.
;; Also: LLOKLUP (BB13)
WriteFirstDigit:
    lda KIMY
    bne WriteDigit                          ; always: the first digit is not 0

;; Ends the text with a zero, keeping at least the one character, `0`.
;; Also: LISZERO (BB13)
Finish:
    cpx #1
    bcs *+4
    ldx #1
    stx LENUM
    lda #0
    sta NUMSTR,X
    rts
.endproc

; ---------------------------------------------------------------------------------------------------------------------
; Loads and stores
; ---------------------------------------------------------------------------------------------------------------------

;; Sets <FAC> to the long integer 0.
;; Out: A = 0, X = $FF
;; Keeps: Y
;; Also: LONGST0 (BB13)
.proc SetFacToZero
    lda #0
    ldx #SIZE - 1

;; Fills <FAC>'s bytes up to X with A.
;; Also: LONGST (BB13)
FillLoop:
    sta FAC,X
    dex
    bpl FillLoop
    rts
.endproc

;; Sets <FAC> to the long integer 1.
;; Out: A = 1, X = $FF
;; Keeps: Y
;; Also: LONGST1 (BB13)
.proc SetFacToOne
    jsr SetFacToZero
    lda #1
    sta FAC+SIZE-1
    rts
.endproc

;; Loads a long integer from memory into <FAC>.
;; In: A = the address's low byte, Y = its high byte, X = its bank
;; Out: FAC = the number
;; Uses: Y, INDEX, INDEXB
;; Keeps: X
;; See: <LongInteger::StoreFac>
;; Also: LDFACT (BB13), DMOVFM (BB13)
.proc LoadFac
    sta INDEX
    stx INDEXB
    sty INDEX+1
    ldy #SIZE - 1

;; Loads a byte, from the last.
;; Also: LDFAC2 (BB13)
LoadLoop:
    lda (INDEX),Y
    sta FAC,Y
    dey
    bpl LoadLoop
    rts
.endproc

.endscope

; ---------------------------------------------------------------------------------------------------------------------
; Conversions
; ---------------------------------------------------------------------------------------------------------------------

; `CONV`.
.scope Functions continued

;; The `CONV` function: the <FAC>'s value as a real.
;;
;; A string is read as `VAL` reads it; a long integer is converted; a real stays as it is.
;; In: FAC = the value, VALTYP = its type
;; Out: FAC = the real, VALTYP = 0
;; See: <LongInteger::ToReal>, <VAL>
;; Also: CONV2FLT (BB13)
.proc Conv
    bit VALTYP
    bmi LongInteger::StringToReal
    bvc LongInteger::ToReal::Done           ; already a real
    ; Falls into LongInteger::ToReal.
.endproc

.endscope

; The conversions between long integers and reals.
.scope LongInteger continued

;; Converts <FAC>'s long integer to a real.
;;
;; The real takes the magnitude's top 40 bits, the last 8 of them in <FACOV>, so it is rounded when it is next stored.
;; Out: FAC = the real, VALTYP = 0
;; Errors: ERROV = <FAC> is -(2^56), from <LongInteger::NegateFac>
;; Uses: KIMY
;; Entry:
;;   Done = returns; <Functions::Conv> branches here for a real
;; See: <Functions::ConvLong>
;; Also: LMAKFLT (BB13)
.proc ToReal
    lda FAC
    pha                                     ; the sign
    bpl *+5
    jsr NegateFac
    lda #<(FAC)
    ldx #0
    ldy #>(FAC)
    jsr IsZero
    bne *+6
    pla
    jmp GIVE0                               ; zero
    jsr NormalizeFac                        ; the top 1 bit to bit 62
    jsr ShiftLeft                           ; and to bit 63, which KIMY does not count
    lda FAC+4
    sta FACOV
    lda FAC+3
    sta FACLO
    lda FAC+2
    sta FACMO
    lda FAC+1
    sta FACMOH
    lda FAC
    sta FACHO
    lda #$80 + BITS - 1                     ; bit 63 is 2^63: an exponent of 64, less the shifts
    sec
    sbc KIMY
    sta FACEXP
    pla
    sta FACSGN
    lda #0
    sta VALTYP                              ; a real

;; Returns.
;; Also: CONV2RTS (BB13)
Done:
    rts
.endproc

;; Reads a string as a real, as `VAL` does, for <Functions::Conv>.
;; Also: STR2FLT (BB13)
.proc StringToReal
    jmp VAL
.endproc

.endscope

; `CONV&`.
.scope Functions continued

;; The `CONV&` function: the <FAC>'s value as a long integer.
;;
;; A real is rounded to the nearest integer, a half upward; a string is read as a long integer, as `VAL` reads a real.
;;
;; <LongInteger::LoadFac> is called to move the integer from <ARG> without Y, the address's high byte, being set. After
;; the bit loop Y is <ARG>'s top byte, as <LongInteger::ShiftLeftWithCarry> leaves it, which is 0 only for a size below
;; 2^56: from 2^56 on, the eight bytes are read from that page instead of from <ARG>, and the result is wrong. For a
;; zero, which skips the loop, Y is what <INT> left.
;; In: FAC = the value, VALTYP = its type
;; Out: FAC = the long integer, VALTYP = <VALUE_TYPE_LONG_INTEGER>
;; Errors: ERROV = a real of 2^63 or more in size
;; Uses: ARG, YSAVE
;; See: <LongInteger::ReadNumber>, <LongInteger::ToReal>
;; Also: CONV2LNG (BB13)
.proc ConvLong
    bit VALTYP
    bmi LongInteger::StringToLong
    bvs LongInteger::ShiftRealLeft::Done    ; already a long integer
    jsr Float::RoundToInteger
    jsr LongInteger::ClearArg
    lda FACSGN
    pha
    lda FACEXP
    sec
    sbc #$80                                ; the integer's count of bits
    bmi Finish                              ; none: zero
    sta YSAVE
    cmp #LongInteger::BITS
    bcc *+5
    jmp OVERR
    lda #<(ARG)

;; Moves the integer's bits from the real's mantissa into <ARG>, one at a time.
;; Also: PASSABIT (BB13)
MoveBit:
    jsr LongInteger::ShiftRealLeft
    jsr LongInteger::ShiftLeftWithCarry
    dec YSAVE
    bne MoveBit

;; Moves the magnitude in <ARG> to <FAC> and gives it the real's sign.
;; Also: GTFACNA (BB13)
Finish:
    lda #VALUE_TYPE_LONG_INTEGER
    sta VALTYP
    lda #<(ARG)
    ldx #0
    jsr LongInteger::LoadFac
    pla
    bpl *+5
    jsr LongInteger::NegateFac
    rts
.endproc

.endscope

; The real's shift and the string conversion.
.scope LongInteger continued

;; Shifts the real <FAC>'s mantissa left one bit, <FACOV> included.
;; Out: carry = the bit shifted out of <FACHO>
;; Keeps: A, X, Y
;; Entry:
;;   Done = returns; <Functions::ConvLong> and <Functions::ConvString> branch here for a value already of their type
;; Also: ASLFAC (BB13)
.proc ShiftRealLeft
    asl FACOV
    rol FACLO
    rol FACMO
    rol FACMOH
    rol FACHO

;; Returns.
;; Also: CONV2RT2 (BB13)
Done:
    rts
.endproc

;; Reads a string as a long integer, through `VAL`'s code (<VALSTR>) with <LongInteger::ReadNumber>.
;; Also: STR2LNG (BB13)
.proc StringToLong
    lda #<(ReadNumber)
    ldy #>(ReadNumber)
    jmp VALSTR
.endproc

.endscope

; `CONV%`.
.scope Functions continued

;; The `CONV%` function: the <FAC>'s value rounded to an integer, as a real.
;; In: FAC = the value, VALTYP = its type
;; Out: FAC = the rounded real, VALTYP = 0
;; See: <Functions::Conv>
;; Also: CONV2INT (BB13)
.proc ConvInteger
    jsr Conv
    ; Falls into Float::RoundToInteger.
.endproc

.endscope

; Rounding a real.
.scope Float continued

;; Rounds the real <FAC> to the nearest integer, a half upward, as `INT(x + .5)` does.
;; Also: QINTRN (BB13)
.proc RoundToInteger
    jsr FADDH
    jmp INT
.endproc

.endscope

; `CONV$`.
.scope Functions continued

;; The `CONV$` function: the <FAC>'s value as a string, as `STR$` writes it.
;; In: FAC = the value, VALTYP = its type
;; Out: FAC = the string
;; See: <STRS>, <LongInteger::FormatFac>
;; Also: CONV2STR (BB13)
.proc ConvString
    bit VALTYP
    bmi LongInteger::ShiftRealLeft::Done    ; already a string
    bvs FromLong
    jmp STRS

;; Makes a long integer's text a string.
;; Also: CONWASL (BB13)
FromLong:
    jsr LongInteger::FormatFac
    lda #<(NUMSTR)
    ldx #NUMSTRB
    ldy #>(NUMSTR)
    jmp STRLIT
.endproc

.endscope

; ---------------------------------------------------------------------------------------------------------------------
; Logic and comparison
; ---------------------------------------------------------------------------------------------------------------------

; The logical and relational operators.
.scope LongInteger continued

;; The `AND` operator for long integers: 1 when <ARG> and <FAC> are both nonzero, else 0.
;; Also: LAND (BB13)
.proc And
    lda #<(FAC)
    ldx #0
    ldy #>(FAC)
    jsr IsZero
    bne *+3
    rts                                     ; FAC is 0: so is the result
    lda #<(ARG)
    ldx #0
    ldy #>(ARG)
    jsr IsZero
    ; Falls into SetFacToTruth.
.endproc

;; Sets <FAC> to 1 when the zero flag is clear, or to 0 when it is set.
;; In: zero = set for 0
;; Entry:
;;   ToSetFacToZero = sets <FAC> to 0; <LongInteger::Or> and <LongInteger::Compare> branch here
;; Also: LGIVM1 (BB13)
.proc SetFacToTruth
    beq *+5
    jmp SetFacToOne

;; Sets <FAC> to 0.
;; Also: LGIVM0 (BB13)
ToSetFacToZero:
    jmp SetFacToZero
.endproc

;; The `OR` operator for long integers: 1 when <ARG> or <FAC> is nonzero, else 0.
;;
;; The first test reads <FAC> with whatever X the operator's dispatch left, an index below $80, which selects no bank.
;; Also: LONGOR (BB13)
.proc Or
    lda #<(FAC)
    ldy #>(FAC)
    jsr IsZero
    sta KIMY
    lda #<(ARG)
    ldy #>(ARG)
    ldx #0
    jsr IsZero
    ora KIMY
    beq SetFacToTruth::ToSetFacToZero
    jmp SetFacToOne
.endproc

;; The relational operators for long integers: 1 when the comparison of <ARG> with <FAC> holds, else 0.
;;
;; The top bytes are compared by the sign of their difference, which is wrong when they differ by $80 or more: 2^62
;; then reads as less than -(2^62). The call to <LongInteger::CompareMagnitudes::FromByte> is redundant, as
;; <LongInteger::CompareMagnitudes> compares all the bytes again.
;; In: DOMASK = the relations that are true: <RELATION_LESS>, <RELATION_EQUAL> and <RELATION_GREATER>
;; Out: FAC = 1 or 0
;; Also: LDOCOMP (BB13)
.proc Compare
    lda ARG
    cmp FAC
    bmi Less
    bne Greater
    ldx #1
    jsr CompareMagnitudes::FromByte
    jsr CompareMagnitudes
    beq Equal
    bcs Greater

;; <ARG> is less than <FAC>.
;; Also: LISL (BB13)
Less:
    lda #RELATION_LESS
    .byte 44                                ; BIT abs, which skips the next LDA

;; <ARG> equals <FAC>.
;; Also: LISEQ (BB13)
Equal:
    lda #RELATION_EQUAL
    .byte 44                                ; BIT abs, which skips the next LDA

;; <ARG> is greater than <FAC>.
;; Also: LISG (BB13)
Greater:
    lda #RELATION_GREATER
    and DOMASK
    bne SetFacToTruth                       ; the relation holds: 1
    beq SetFacToTruth::ToSetFacToZero       ; always: 0
.endproc

.endscope
