; retrocore: style=strict
;; Business BASIC: long integers
;;
;; Reading and printing them, their arithmetic and comparisons, and the conversions between them, reals and strings
;; (the `CONV` functions).
;;
;; A long integer is eight bytes of two's complement, most significant byte first, from -(2^63) to 2^63-1; a long
;; variable's value is those eight bytes as they are, and <ValueType> is <VALUE_TYPE_LONG_INTEGER> while one is in the
;; <Fac>. The arithmetic works on three eight-byte numbers in BASIC's zero page: <Fac> (over the real one's bytes),
;; <Arg> and <Result1>, with the byte below <Result1> (<Result1>-1) catching a product's overflow (in division it marks
;; the first subtraction). Most routines reach their operands through <LongOperand1Pointer>, <LongOperand2Pointer> and
;; <LongResultPointer>, which <LongInteger::PointAtOperands> points at <Fac>, <Arg> and <Fac>. A binary operator gets
;; its left operand in <Arg> and its right in <Fac>.
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

;; The bytes of the binary-coded decimal number <LongInteger::FacToDigits> builds in <Arg> and the two bytes after it.
DECIMAL_SIZE = SIZE + 2

;; The decimal digits <LongInteger::FacToDigits> makes, two to each of <DECIMAL_SIZE>'s bytes.
DECIMAL_DIGITS = 2 * DECIMAL_SIZE

; The relations <RelationMask> asks <LongInteger::Compare> for.

;; <Arg> is less than <Fac>.
RELATION_LESS = 4

;; <Arg> equals <Fac>.
RELATION_EQUAL = 2

;; <Arg> is greater than <Fac>.
RELATION_GREATER = 1

; ---------------------------------------------------------------------------------------------------------------------
; Input
; ---------------------------------------------------------------------------------------------------------------------

;; Reads a long integer from the text at <TextPointer> into <Fac>.
;;
;; An optional sign and then digits; a fraction after a period rounds the number to the nearest integer, an exact half
;; to the even one. There is no exponent. -(2^63) itself can't be read: its digits are an overflow before the sign is
;; applied.
;; In: TextPointer = the number's first character
;; Out: Fac = the number, ValueType = <VALUE_TYPE_LONG_INTEGER>, TextPointer = the first character after it
;; Errors: <ERROR_OVERFLOW> = the number is out of range
;; Uses: Arg, KeptY, SavedY, LongOperand1Pointer, LongOperand2Pointer, LongResultPointer
;; See: <Float::ReadNumber>, <LongInteger::FormatFac>
;; Also: LINP (BB13)
.proc ReadNumber
    lda #VALUE_TYPE_LONG_INTEGER
    sta ValueType
    lda #0
    sta KeptY                               ; bit 7 set for a minus sign
    ldx #SIZE - 1

;; Zeros <Fac> and <Arg>.
;; Also: LZFAC1 (BB13)
ClearLoop:
    sta Fac,X
    sta Arg,X
    dex
    bpl ClearLoop
    jsr GetCurrentCharacter
    bcc TakeDigit                           ; a digit
    cmp #'+'
    beq NextCharacter
    cmp #'-'
    bne CheckFraction
    lda #$FF
    eor KeptY
    sta KeptY
    jmp NextCharacter

;; Takes a digit into <Fac>: <Fac> = <Fac> * 10 + the digit.
;; In: A = the digit's character
;; Also: LISNUM (BB13)
TakeDigit:
    and #$0F
    sta SavedY
    jsr MultiplyFacByTen
    jsr ClearArg
    lda SavedY
    sta Arg+SIZE-1
    jsr AddAt                               ; Fac = Fac + Arg, through MultiplyFacByTen's pointers

;; Goes on to the next character, taking it if it is a digit.
;; Also: LTRYN2 (BB13)
NextCharacter:
    jsr GetNextCharacter
    bcc TakeDigit

;; Rounds by the fraction after a period, if any: up from a first digit above 5, or of 5 with any nonzero digit after
;; it.
;; Also: LTRYDOT (BB13)
CheckFraction:
    cmp #'.'
    bne ApplySign
    jsr GetNextCharacter
    bcs ApplySign
    cmp #'5'
    bcc SkipFraction                        ; below .5: down
    bne RoundUp                             ; above .5: up

;; After a 5, looks for a digit other than 0, which rounds up; with none, the number rounds to even.
;; Also: LTRYN3 (BB13)
SeekNonzeroDigit:
    jsr GetNextCharacter
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
    jsr GetNextCharacter
    bcc SkipFraction
    bcs ApplySign

;; Rounds exactly half to the even integer: up when <Fac> is odd.
;; Also: LRNDEVN (BB13)
RoundToEven:
    lda Fac+SIZE-1
    and #1
    beq ApplySign
    jsr IncrementFac

;; Ends the number, negating it for a minus sign.
;; Also: LNUMDON (BB13)
ApplySign:
    lda KeptY
    bpl IncrementFac::Done
    ; Falls into NegateFac.
.endproc

;; Negates <Fac>.
;;
;; The overflow test in <LongInteger::IncrementFac> misfires here: negating $FF00000000000000 (-(2^56)) or
;; $7F00000000000000 gives an overflow error though the result fits, so -(2^56) can be neither printed nor converted to
;; a real; and negating -(2^63), which doesn't fit, gives -(2^63) with no error.
;; Out: Fac = -<Fac>
;; Errors: <ERROR_OVERFLOW> = see above
;; Uses: A, X
;; Keeps: Y
;; See: <LongInteger::NegateAt>
;; Also: LTWSCOMP (BB13)
.proc NegateFac
    ldx #SIZE - 1

;; Complements <Fac>'s bytes, before <LongInteger::IncrementFac> adds one.
;; Also: LTWSONE (BB13)
ComplementLoop:
    lda Fac,X
    eor #$FF
    sta Fac,X
    dex
    bpl ComplementLoop
    ; Falls into IncrementFac.
.endproc

;; Adds one to <Fac>.
;;
;; When the carry reaches the top byte, the test for overflow looks at A rather than at <Fac>: from
;; <LongInteger::NegateFac>, A is the top byte before the increment, and an error comes when it was $00 or $80, which
;; is not the overflow case; from <LongInteger::ReadNumber>'s rounding, A is never zero there, so rounding
;; 9223372036854775807.5 up wraps to -(2^63) with no error.
;; Out: Fac = <Fac> + 1
;; Errors: <ERROR_OVERFLOW> = see above
;; Uses: X
;; Keeps: Y
;; Entry:
;;   ToOverflowError = ends with an overflow error; <LongInteger::MultiplyFacByTen> branches here
;;   Done = returns; <LongInteger::ReadNumber> branches here
;; Also: LINCFAC (BB13)
.proc IncrementFac
    ldx #SIZE - 1

;; Increments <Fac>'s bytes from the lowest while each carries.
;; Also: LTWSCO2 (BB13)
IncrementLoop:
    inc Fac,X
    bne Done
    dex
    bne IncrementLoop
    inc Fac
    and #$7F                                ; tests A, not Fac
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

;; Multiplies <Fac> by 10, as <Fac> * 2 + <Fac> * 8, and leaves <LongInteger::PointAtOperands>'s pointers set.
;; In: Fac = a positive number
;; Out: Fac = <Fac> * 10, Arg = <Fac> * 2
;; Errors: <ERROR_OVERFLOW> = the product is out of range
;; Uses: LongOperand1Pointer, LongOperand2Pointer, LongResultPointer
;; Also: LTIMES10 (BB13)
.proc MultiplyFacByTen
    jsr PointAtOperands
    lda #<(Fac)
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

;; Copies <Fac> to <Arg>.
;; Out: X = 0
;; Keeps: A, Y
;; Also: FACTOARG (BB13)
.proc CopyFacToArg
    pha
    ldx #SIZE

;; Copies <Fac>'s bytes to <Arg>, from the last.
;; Also: FAC2AR2 (BB13)
CopyLoop:
    lda Fac-1,X
    sta Arg-1,X
    dex
    bne CopyLoop
    pla
    rts
.endproc

; ---------------------------------------------------------------------------------------------------------------------
; Signs and results
; ---------------------------------------------------------------------------------------------------------------------

;; Makes the two operands positive for a multiply or divide, noting the result's sign.
;; In: LongOperand1Pointer, LongOperand2Pointer = the operands, in zero page
;; Out: InputMode = bit 7 set when the result is negative (the signs differ)
;; Uses: A, X, Y
;; See: <LongInteger::ReturnResult>
;; Also: LSGNPOS (BB13)
.proc MakeOperandsPositive
    ldy #0
    lda (LongOperand1Pointer),Y
    eor (LongOperand2Pointer),Y
    sta InputMode
    lda (LongOperand1Pointer),Y
    bpl SecondOperand
    lda LongOperand1Pointer
    jsr NegateAt

;; Makes the second operand positive.
;; Also: LSGNP2 (BB13)
SecondOperand:
    ldy #0
    lda (LongOperand2Pointer),Y
    bpl Done
    lda LongOperand2Pointer
    jsr NegateAt

;; Returns.
;; Also: LSGNP3 (BB13)
Done:
    rts
.endproc

;; Moves a product from <Result1> to <Fac> with its sign, or ends with an overflow error when it grew past <Result1>.
;; In: <Result1>-1, Result1 = the product's magnitude, InputMode = bit 7 set for a negative result
;; Out: Fac = the product
;; Errors: <ERROR_OVERFLOW> = the product is out of range
;; See: <LongInteger::Multiply>
;; Also: LRESPOS (BB13)
.proc ReturnProduct
    lda Result1-1
    bne OverflowError
    ; Falls into ReturnQuotient.
.endproc

;; Moves a quotient from <Result1> to <Fac> with its sign.
;; In: Result1 = the quotient's magnitude, InputMode = bit 7 set for a negative result
;; Out: Fac = the quotient
;; Errors: <ERROR_OVERFLOW> = the quotient is out of range
;; Also: LRESDIV (BB13)
.proc ReturnQuotient
    lda #<(Result1)
    sta LongResultPointer
    ; Falls into ReturnResult.
.endproc

;; Moves a result from (<LongResultPointer>) to <Fac>, negating it first when <InputMode> says the result is negative.
;;
;; Bit 7 of <Result1> is checked even when the result is elsewhere. A division makes at most 63 quotient bits, so only
;; `/`'s rounding can set it there; `DIV` and `MOD` never give the overflow. For a dividend of -(2^63) they can be wrong
;; instead: `-(2^63) DIV 1` gives -(2^63)+1 and `-(2^63) MOD 1` gives -1 (seen on the emulated Apple III).
;; In: LongResultPointer = the result's magnitude, in zero page, InputMode = bit 7 set for a negative result
;; Out: Fac = the result
;; Errors: <ERROR_OVERFLOW> = bit 7 of <Result1> is set
;; Also: LRESDV (BB13)
.proc ReturnResult
    lda #<(Fac)
    sta LongOperand1Pointer
    lda Result1
    bmi OverflowError
    lda InputMode
    bpl Copy
    lda LongResultPointer
    jsr NegateAt

;; Copies the eight bytes.
;; Also: LRESP2 (BB13)
Copy:
    ldy #SIZE - 1

;; Copies a byte, from the last.
;; Also: LRES2F2 (BB13)
CopyLoop:
    lda (LongResultPointer),Y
    sta (LongOperand1Pointer),Y
    dey
    bpl CopyLoop
    rts
.endproc

; ---------------------------------------------------------------------------------------------------------------------
; Utilities, addition and subtraction
; ---------------------------------------------------------------------------------------------------------------------

;; Zeros <Result1> and the overflow byte below it.
;; Out: A = 0, X = $FF
;; Keeps: Y
;; Also: LZIPRES (BB13)
.proc ClearResult
    lda #0
    ldx #SIZE

;; Zeros a byte, from the last.
;; Also: LZIP2 (BB13)
ClearLoop:
    sta Result1-1,X
    dex
    bpl ClearLoop
    rts
.endproc

;; Stores <Fac> as a long integer in memory.
;; In: A = the address's low byte, Y = its high byte, X = its bank
;; Uses: Pointer1, Pointer1XByte, Y
;; Keeps: X
;; See: <LongInteger::LoadFac>
;; Also: STFACT (BB13)
.proc StoreFac
    sta Pointer1
    stx Pointer1XByte
    sty Pointer1+1
    ldy #SIZE - 1

;; Stores a byte, from the last.
;; Also: STFAC2 (BB13)
StoreLoop:
    lda Fac,Y
    sta (Pointer1),Y
    dey
    bpl StoreLoop
    rts
.endproc

;; Points <LongOperand1Pointer> and <LongResultPointer> at <Fac> and <LongOperand2Pointer> at <Arg>, all in zero page,
;; for <Fac> = <Fac> op <Arg>.
;; Out: A = <Arg>'s address, Y = 0
;; Keeps: X
;; Also: LPTRS (BB13)
.proc PointAtOperands
    ldy #0
    sty LongOperand1Pointer+1
    sty LongOperand2Pointer+1
    sty LongResultPointer+1
    sty LongOperand1PointerXByte
    sty LongOperand2PointerXByte
    sty LongResultPointerXByte
    lda #<(Fac)
    sta LongOperand1Pointer
    sta LongResultPointer
    lda #<(Arg)
    sta LongOperand2Pointer
    rts
.endproc

;; The `+` operator for long integers: <Fac> = <Arg> + <Fac>.
;; Errors: <ERROR_OVERFLOW> = the sum is out of range
;; Also: LADD (BB13)
.proc Add
    jsr PointAtOperands
    ; Falls into AddAt.
.endproc

;; Adds two long integers: (<LongResultPointer>) = (<LongOperand1Pointer>) + (<LongOperand2Pointer>).
;; Errors: <ERROR_OVERFLOW> = the sum is out of range
;; Keeps: X
;; Also: LADDPTR (BB13)
.proc AddAt
    ldy #SIZE - 1
    clc

;; Adds a byte, from the last.
;; Also: LADD2 (BB13)
AddLoop:
    lda (LongOperand1Pointer),Y
    adc (LongOperand2Pointer),Y
    sta (LongResultPointer),Y
    dey
    bpl AddLoop
    bvs OverflowError
    rts
.endproc

;; Ends the statement with an overflow error.
;; Also: LOVERR (BB13)
.proc OverflowError
    ldx #ERROR_OVERFLOW
    jmp ReportError
.endproc

;; Subtracts with the pointers set: <Fac> = <Arg> - <Fac>, with no overflow check.
;; Out: overflow = set when the result is out of range
;; Also: LSUBB (BB13)
.proc SubtractUnchecked
    jsr PointAtOperands
    ; Falls into SubtractAt.
.endproc

;; Subtracts two long integers: (<LongResultPointer>) = (<LongOperand2Pointer>) - (<LongOperand1Pointer>), with no
;; overflow check.
;; Out: carry = clear for a borrow, overflow = set when the result is out of range
;; Keeps: X
;; Also: LSUBER (BB13)
.proc SubtractAt
    ldy #SIZE - 1
    sec

;; Subtracts a byte, from the last.
;; Also: LSUB2 (BB13)
SubtractLoop:
    lda (LongOperand2Pointer),Y
    sbc (LongOperand1Pointer),Y
    sta (LongResultPointer),Y
    dey
    bpl SubtractLoop
    rts
.endproc

;; The `-` operator for long integers: <Fac> = <Arg> - <Fac>.
;; Errors: <ERROR_OVERFLOW> = the difference is out of range
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

;; The `*` operator for long integers: <Fac> = <Arg> * <Fac>.
;;
;; Multiplies the magnitudes a byte by a byte into <Result1>, skipping zero bytes, then gives the product its sign.
;; Errors: <ERROR_OVERFLOW> = the product is out of range
;; Uses: Arg, Result1, Pointer1, KeptY, InputMode, LongOperand1Pointer, LongOperand2Pointer,
;;   LongResultPointer
;; See: <LongInteger::MultiplyBytes>, <LongInteger::ReturnProduct>
;; Also: LMULT (BB13)
.proc Multiply
    jsr PointAtOperands
    jsr MakeOperandsPositive
    lda #<(Fac+SIZE-1)
    sta LongOperand1Pointer                 ; the row: Fac's bytes, from the last
    lda #<(Arg+SIZE-1)
    sta LongOperand2Pointer                 ; the column: Arg's bytes, from the last
    lda #<(Result1+SIZE-2)
    sta LongResultPointer                   ; where the first byte product goes
    jsr ClearResult

;; Multiplies the row's byte of <Fac> by each byte of <Arg>.
;; Also: LMULT1 (BB13)
Row:
    ldy #0
    lda (LongOperand1Pointer),Y
    beq NextRow                             ; a zero byte: skip the row

;; Multiplies the row's byte by one byte of <Arg>, unless it is zero.
;; Also: LMULT2 (BB13)
Column:
    lda (LongOperand2Pointer),Y
    beq *+5
    jsr MultiplyBytes
    dec LongResultPointer                   ; the next product a byte higher
    dec LongOperand2Pointer
    lda LongOperand2Pointer
    cmp #Arg
    bcs Column
    lda #<(Arg+SIZE-1)
    sta LongOperand2Pointer                 ; back to Arg's last byte
    lda LongResultPointer
    clc
    adc #SIZE
    sta LongResultPointer

;; Moves on to the next byte of <Fac>, a byte higher in <Result1>.
;; Also: LMULT3 (BB13)
NextRow:
    dec LongResultPointer
    dec LongOperand1Pointer
    lda LongOperand1Pointer
    cmp #Fac
    bcs Row
    jmp ReturnProduct
.endproc

;; Multiplies the byte at (<LongOperand1Pointer>) by the byte at (<LongOperand2Pointer>) and adds the 16-bit product
;; into <Result1> at (<LongResultPointer>).
;; In: Y = 0, LongResultPointer = where the product's high byte goes
;; Out: Y = 0
;; Errors: <ERROR_OVERFLOW> = the product or its carry would go above <Result1>-1
;; Uses: A, X, Pointer1, KeptY
;; Keeps: Y
;; Also: LMULTBYT (BB13)
.proc MultiplyBytes
    sty Pointer1                            ; the product: Pointer1 high, Pointer1+1 low
    sty Pointer1+1
    lda (LongOperand1Pointer),Y
    sta KeptY
    ldx #8

;; Adds the multiplicand for each 1 bit of the multiplier, shifting the product right.
;; Also: LMULTB2 (BB13)
BitLoop:
    ror KeptY
    bcc ShiftProduct
    lda (LongOperand2Pointer),Y
    clc
    adc Pointer1
    sta Pointer1

;; Shifts the product right a bit, with the carry from the add.
;; Also: LMULTB3 (BB13)
ShiftProduct:
    ror Pointer1
    ror Pointer1+1
    dex
    bne BitLoop
    lda LongResultPointer
    cmp #Result1-1
    bcs *+5

;; Ends with an overflow error.
;; Also: LMULTOV (BB13)
ToOverflowError:
    jmp OverflowError
    ldx LongResultPointer
    lda Pointer1+1
    clc
    adc 1,X
    sta 1,X
    lda Pointer1
    adc 0,X
    sta 0,X
    bcc Done

;; Carries into the bytes above, as far as <Result1>-1.
;; Also: LMULTB4 (BB13)
CarryLoop:
    dex
    cpx #Result1-1
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

;; Shifts <Fac> left eight bits, a byte at a time.
;; Out: X = 0
;; Keeps: Y
;; Also: LSHLEIGT (BB13)
.proc ShiftFacLeftByte
    ldx #0

;; Moves a byte up.
;; Also: LSHLE2 (BB13)
MoveLoop:
    lda Fac+1,X
    sta Fac,X
    inx
    cpx #SIZE - 1
    bcc MoveLoop
    ldx #0
    stx Fac+SIZE-1
    rts
.endproc

; ---------------------------------------------------------------------------------------------------------------------
; Division
; ---------------------------------------------------------------------------------------------------------------------

;; Divides the magnitude of <Arg> by that of <Fac>, the work of `DIV`, `/` and `MOD`.
;;
;; <Fac>, the divisor, is shifted left until its top 1 bit is bit 62, <KeptY> times. The dividend in <Arg> is then
;; compared with it and shifted left <KeptY> + 1 times, the divisor subtracted whenever it fits, and each step's
;; quotient bit shifted into <Result1>. <Result1>-1 has bit 7 set from the first subtraction on; <Result1> is not
;; shifted before it, as its bits are all zero.
;;
;; A divisor of -(2^63) is the exception: its magnitude, $80 00 ..., already has bit 63 set, so <NormalizeFac> shifts
;; it right once and leaves <KeptY> -1. The step count is then 0, the branch to Step is not taken, and the dividend is
;; shifted once before the first comparison. What that gives for such a divisor has not been checked.
;; Out: Result1 = the quotient's magnitude, Arg = the remainder shifted left <KeptY> + 1 bits (1 bit for a
;;   divisor of -(2^63)), carry = set when twice the remainder is at least the divisor, InputMode = bit 7 set for a
;;   negative result
;; Errors: <ERROR_DIVISION_BY_ZERO> = <Fac> is zero
;; Uses: SavedY, LongOperand1Pointer, LongOperand2Pointer, LongResultPointer
;; See: <LongInteger::Div>, <LongInteger::Divide>, <LongInteger::Mod>
;; Also: LDIVER (BB13)
.proc DivideMagnitudes
    jsr PointAtOperands
    jsr ClearResult
    jsr MakeOperandsPositive
    jsr NormalizeFac
    ldx KeptY
    stx SavedY
    lda #<(Arg)
    sta LongResultPointer                   ; differences go to Arg
    inc SavedY                              ; KeptY + 1 steps
    bne Step                                ; always, but for a divisor of -(2^63) (see above)

;; Shifts the quotient bit in the carry into <Result1>, once a subtraction has been made, and the dividend left.
;; Also: LDECYSAV (BB13)
ShiftQuotient:
    lda Result1-1
    bpl ShiftDividend
    lda #<(Result1)
    jsr ShiftLeftWithCarry

;; Shifts the dividend left.
;; Also: LRESOK (BB13)
ShiftDividend:
    lda #<(Arg)
    jsr ShiftLeft

;; Compares the dividend with the divisor and subtracts it when it fits, until the steps are done.
;; Also: LDIVCOM (BB13)
Step:
    jsr CompareMagnitudes
    dec SavedY
    bmi Done                                ; done: the carry is the next bit, for rounding
    bcc ShiftQuotient                       ; doesn't fit: a 0 bit
    jsr SubtractAt
    lda #$80
    sta Result1-1                           ; a subtraction made
    bcs ShiftQuotient                       ; always: a 1 bit

;; Returns.
;; Also: LGOTRES (BB13)
Done:
    rts
.endproc

;; The `/` operator for long integers: <Fac> = <Arg> / <Fac>, rounded to the nearest integer, an exact half to the
;; even one.
;; Errors: <ERROR_DIVISION_BY_ZERO> = <Fac> is zero, <ERROR_OVERFLOW> = the quotient is out of range
;; See: <LongInteger::DivideMagnitudes>, <LongInteger::Div>
;; Also: LDIVT (BB13)
.proc Divide
    jsr DivideMagnitudes
    bcc Finish                              ; under a half: no rounding
    jsr SubtractAt                          ; Arg = 0 when exactly a half
    lda #<(Arg)
    ldx #0
    ldy #>(Arg)
    jsr IsZero
    sta SavedY
    lda Result1+SIZE-1
    and #$1
    ora SavedY
    beq Finish                              ; exactly a half, and the quotient is even
    ldx #SIZE

;; Adds one to the quotient in <Result1>, from the last byte.
;; Also: LINCBYT (BB13)
IncrementLoop:
    inc Result1-1,X
    bne Finish
    dex
    bne IncrementLoop

;; Moves the quotient to <Fac> with its sign.
;; Also: LNOROUND (BB13)
Finish:
    jmp ReturnQuotient
.endproc

;; Shifts <Fac> left until its top 1 bit is bit 62, counting the shifts.
;;
;; A negative <Fac>, only ever -(2^63), is shifted right once instead.
;; In: Fac = a positive number
;; Out: KeptY = the bits shifted left, -1 for the one right
;; Errors: <ERROR_DIVISION_BY_ZERO> = <Fac> is zero
;; Also: LNRMFAC (BB13)
.proc NormalizeFac
    ldy #0
    sty KeptY

;; Shifts a byte at a time while the top byte is zero.
;; Also: LDIVE2 (BB13)
ByteLoop:
    lda Fac
    bne BitLoop
    jsr ShiftFacLeftByte
    lda KeptY
    clc
    adc #8
    sta KeptY
    cmp #BITS
    bcc ByteLoop
    jmp Float::DivideArg::DivisionByZero    ; all 64 bits zero

;; Shifts a bit at a time until bit 6 of the top byte is set.
;; Also: LDIVE3 (BB13)
BitLoop:
    lda #<(Fac)
    bit Fac
    bmi TooFar
    bvs Done
    jsr ShiftLeft
    inc KeptY
    bne BitLoop                             ; always

;; Shifts the one bit right that went too far.
;; Also: LDIVTOFAR (BB13)
TooFar:
    jsr ShiftRight
    dec KeptY

;; Returns.
;; Also: LDIVOK (BB13)
Done:
    rts
.endproc

;; Compares <Arg> with <Fac> as unsigned numbers.
;; Out: carry = set when <Arg> >= <Fac>, zero = set when they are equal
;; Uses: A, X
;; Keeps: Y
;; Entry:
;;   FromByte = compares from the byte at X on; <LongInteger::Compare> calls it with X = 1
;; Also: LCOMP (BB13)
.proc CompareMagnitudes
    ldx #0

;; Compares from the byte at X on.
;; In: X = the first byte to compare
;; Out: carry = set when <Arg> >= <Fac>, zero = set when they are equal
;; Also: LCMP2 (BB13)
FromByte:
    lda Arg,X
    cmp Fac,X
    bne Done
    inx
    cpx #SIZE
    bcc FromByte

;; Returns.
;; Also: LCMP3 (BB13)
Done:
    rts
.endproc

;; The `DIV` operator for long integers: <Fac> = <Arg> / <Fac>, the fraction dropped.
;; Errors: <ERROR_DIVISION_BY_ZERO> = <Fac> is zero
;; See: <LongInteger::DivideMagnitudes>, <LongInteger::Divide>
;; Also: LDIV (BB13)
.proc Div
    jsr DivideMagnitudes
    jmp ReturnQuotient
.endproc

;; The `MOD` operator for long integers: <Fac> = the remainder of <Arg> / <Fac>.
;;
;; The remainder of the two sizes is made negative when exactly one operand is, as a quotient would be, rather than
;; taking the dividend's sign: `-7 MOD 2` and `7 MOD -2` are both -1, and `-7 MOD -2` is 1.
;; Errors: <ERROR_DIVISION_BY_ZERO> = <Fac> is zero
;; See: <LongInteger::DivideMagnitudes>
;; Also: LREM (BB13)
.proc Mod
    jsr DivideMagnitudes
    ldy #0
    lda #<(Arg)

;; Shifts the remainder back right <KeptY> + 1 bits: once when <KeptY> is -1, for a divisor of -(2^63).
;; Also: LREM2 (BB13)
ShiftBack:
    jsr ShiftRight
    dec KeptY
    bpl ShiftBack
    sta LongResultPointer
    jmp ReturnResult
.endproc

;; Tells whether a long integer is zero, by ORing its bytes.
;; In: A = the address's low byte, Y = its high byte, X = its bank
;; Out: A = 0 and zero = set when all eight bytes are zero
;; Uses: Y, Pointer1, Pointer1XByte
;; Keeps: X, overflow
;; Also: LORALL (BB13)
.proc IsZero
    sta Pointer1
    stx Pointer1XByte
    sty Pointer1+1
    lda #0
    ldy #SIZE - 1

;; ORs in a byte, from the last, stopping at the first nonzero one.
;; Also: LORAL2 (BB13)
OrLoop:
    ora (Pointer1),Y
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

;; Turns <Fac>'s long integer into decimal digits in <LongText>, for <LongInteger::FormatFac> and `PRINT USING`.
;;
;; The magnitude is converted to <DECIMAL_DIGITS> binary-coded decimal digits by doubling: each bit, from the top 1 bit
;; down, doubles the decimal number in <Arg> and the two bytes after it and adds the bit. <PrintUsing::UnpackDecimal>
;; then spreads the digits out, one a byte, dropping the leading zeros. <Fac> is used up. For zero, no 1 bit is found
;; and the count of bits is left from <KeptY>'s last value, which only changes how many times the zero is doubled.
;; In: Fac = the number
;; Out: LongText+2.. = the digits, values 0 to 9, ArrayElementFound = twice the count of digits, plus 1 for a negative
;;   number,
;;   FacSign = bit 7 set for a negative number
;; Errors: <ERROR_OVERFLOW> = <Fac> is -(2^56), from <LongInteger::NegateFac>
;; Uses: Arg, KeptY
;; See: <LongInteger::FormatFac>, <PrintUsing::UnpackDecimal>
;; Also: LUNPACK (BB13)
.proc FacToDigits
    lda FacExponent                         ; Fac's top byte
    cmp #$80
    lda #DECIMAL_DIGITS
    rol
    sta ArrayElementFound                   ; 40, or 41 for a negative number
    lda Fac
    pha
    bpl *+5
    jsr NegateFac
    lda #<(Fac)
    ldx #0
    ldy #>(Fac)
    jsr IsZero
    beq *+5                                 ; zero: no 1 bit to find
    jsr NormalizeFac
    lda #BITS
    sec
    sbc KeptY
    sta KeptY                               ; the bits to convert, from bit 63
    jsr ClearArg

;; Converts one bit: shifts it out of <Fac> and doubles the decimal number with the bit added.
;; Also: LCONVBCD (BB13)
ConvertBit:
    lda #<(Fac)
    jsr ShiftLeft
    ldx #DECIMAL_SIZE
    sed

;; Doubles a byte of the decimal number with the carry, from the last.
;; Also: LADDBCD (BB13)
DoubleLoop:
    lda Arg-1,X
    adc Arg-1,X
    sta Arg-1,X
    dex
    bne DoubleLoop
    cld
    dec KeptY
    bne ConvertBit
    ldx #DECIMAL_SIZE

;; Copies the decimal number to <FacDecimalDigits>, where <PrintUsing::UnpackDecimal> reads it.
;; Also: LABCD2 (BB13)
CopyLoop:
    lda Arg-1,X
    sta FacDecimalDigits-1,X
    dex
    bne CopyLoop
    jsr PrintUsing::UnpackDecimal
    pla
    sta FacSign
    rts
.endproc

;; Zeros <Arg> and the two bytes after it, <Result1>-1 and <Result1>.
;; Out: A = 0, X = 0
;; Keeps: Y
;; Also: LZIPARG (BB13)
.proc ClearArg
    lda #0
    ldx #DECIMAL_SIZE

;; Zeros a byte, from the last.
;; Also: LZIPAR2 (BB13)
ClearLoop:
    sta Arg-1,X
    dex
    bne ClearLoop
    rts
.endproc

;; Writes <Fac>'s long integer as text in <LongText>: a minus sign if negative, then the digits, then a zero.
;; In: Fac = the number
;; Out: LongText = the text, LongTextLength = its length, X = its length
;; Errors: <ERROR_OVERFLOW> = <Fac> is -(2^56), from <LongInteger::NegateFac>
;; See: <LongInteger::FacToDigits>, <Functions::ConvString>
;; Also: LOUT (BB13)
.proc FormatFac
    jsr FacToDigits
    ldx #0
    lda #'0'
    sta LongText                            ; for zero, which has no digits
    lsr ArrayElementFound                   ; the count of digits
    ldy #1

;; Takes the next digit, ending when there are no more.
;; Also: LLOOKLUP (BB13)
NextDigit:
    iny
    dec ArrayElementFound
    bmi Finish
    lda LongText,Y
    cpx #0
    beq WriteSign                           ; the first digit: the sign goes before it

;; Writes a digit as its character.
;; Also: LOUT5 (BB13)
WriteDigit:
    ora #'0'
    sta LongText,X
    inx
    bne NextDigit

;; Writes a minus sign before the first digit of a negative number.
;; Also: LOUT3 (BB13)
WriteSign:
    sta KeptY
    bit FacSign
    bpl WriteFirstDigit
    lda #'-'
    sta LongText,X
    inx

;; Takes the first digit back to write it.
;; Also: LLOKLUP (BB13)
WriteFirstDigit:
    lda KeptY
    bne WriteDigit                          ; always: the first digit is not 0

;; Ends the text with a zero, keeping at least the one character, `0`.
;; Also: LISZERO (BB13)
Finish:
    cpx #1
    bcs *+4
    ldx #1
    stx LongTextLength
    lda #0
    sta LongText,X
    rts
.endproc

; ---------------------------------------------------------------------------------------------------------------------
; Loads and stores
; ---------------------------------------------------------------------------------------------------------------------

;; Sets <Fac> to the long integer 0.
;; Out: A = 0, X = $FF
;; Keeps: Y
;; Also: LONGST0 (BB13)
.proc SetFacToZero
    lda #0
    ldx #SIZE - 1

;; Fills <Fac>'s bytes up to X with A.
;; Also: LONGST (BB13)
FillLoop:
    sta Fac,X
    dex
    bpl FillLoop
    rts
.endproc

;; Sets <Fac> to the long integer 1.
;; Out: A = 1, X = $FF
;; Keeps: Y
;; Also: LONGST1 (BB13)
.proc SetFacToOne
    jsr SetFacToZero
    lda #1
    sta Fac+SIZE-1
    rts
.endproc

;; Loads a long integer from memory into <Fac>.
;; In: A = the address's low byte, Y = its high byte, X = its bank
;; Out: Fac = the number
;; Uses: Y, Pointer1, Pointer1XByte
;; Keeps: X
;; See: <LongInteger::StoreFac>
;; Also: LDFACT (BB13), DMOVFM (BB13)
.proc LoadFac
    sta Pointer1
    stx Pointer1XByte
    sty Pointer1+1
    ldy #SIZE - 1

;; Loads a byte, from the last.
;; Also: LDFAC2 (BB13)
LoadLoop:
    lda (Pointer1),Y
    sta Fac,Y
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

;; The `CONV` function: the <Fac>'s value as a real.
;;
;; A string is read as `VAL` reads it; a long integer is converted; a real stays as it is.
;; In: Fac = the value, ValueType = its type
;; Out: Fac = the real, ValueType = 0
;; See: <LongInteger::ToReal>, <Val>
;; Also: CONV2FLT (BB13)
.proc Conv
    bit ValueType
    bmi LongInteger::StringToReal
    bvc LongInteger::ToReal::Done           ; already a real
    ; Falls into LongInteger::ToReal.
.endproc

.endscope

; The conversions between long integers and reals.
.scope LongInteger continued

;; Converts <Fac>'s long integer to a real.
;;
;; The real takes the magnitude's top 40 bits, the last 8 of them in <FacExtension>, so it is rounded when it is next
;; stored.
;; Out: Fac = the real, ValueType = 0
;; Errors: <ERROR_OVERFLOW> = <Fac> is -(2^56), from <LongInteger::NegateFac>
;; Uses: KeptY
;; Entry:
;;   Done = returns; <Functions::Conv> branches here for a real
;; See: <Functions::ConvLong>
;; Also: LMAKFLT (BB13)
.proc ToReal
    lda Fac
    pha                                     ; the sign
    bpl *+5
    jsr NegateFac
    lda #<(Fac)
    ldx #0
    ldy #>(Fac)
    jsr IsZero
    bne *+6
    pla
    jmp Operators::And::LoadFalse           ; zero
    jsr NormalizeFac                        ; the top 1 bit to bit 62
    jsr ShiftLeft                           ; and to bit 63, which KeptY does not count
    lda Fac+4
    sta FacExtension
    lda Fac+3
    sta FacMantissa4
    lda Fac+2
    sta FacMantissa3
    lda Fac+1
    sta FacMantissa2
    lda Fac
    sta FacMantissa1
    lda #$80 + BITS - 1                     ; bit 63 is 2^63: an exponent of 64, less the shifts
    sec
    sbc KeptY
    sta FacExponent
    pla
    sta FacSign
    lda #0
    sta ValueType                           ; a real

;; Returns.
;; Also: CONV2RTS (BB13)
Done:
    rts
.endproc

;; Reads a string as a real, as `VAL` does, for <Functions::Conv>.
;; Also: STR2FLT (BB13)
.proc StringToReal
    jmp Functions::Val
.endproc

.endscope

; `CONV&`.
.scope Functions continued

;; The `CONV&` function: the <Fac>'s value as a long integer.
;;
;; A real is rounded to the nearest integer, a half upward; a string is read as a long integer, as `VAL` reads a real.
;;
;; <LongInteger::LoadFac> is called to move the integer from <Arg> without Y, the address's high byte, being set. After
;; the bit loop Y is <Arg>'s top byte, as <LongInteger::ShiftLeftWithCarry> leaves it, which is 0 only for a size below
;; 2^56: from 2^56 on, the eight bytes are read from that page instead of from <Arg>, and the result is wrong. For a
;; zero, which skips the loop, Y is what <Int> left.
;; In: Fac = the value, ValueType = its type
;; Out: Fac = the long integer, ValueType = <VALUE_TYPE_LONG_INTEGER> (for an empty string, a real 0)
;; Errors: <ERROR_OVERFLOW> = a real of 2^63 or more in size
;; Uses: Arg, SavedY
;; See: <LongInteger::ReadNumber>, <LongInteger::ToReal>
;; Also: CONV2LNG (BB13)
.proc ConvLong
    bit ValueType
    bmi LongInteger::StringToLong
    bvs LongInteger::ShiftRealLeft::Done    ; already a long integer
    jsr Float::RoundToInteger
    jsr LongInteger::ClearArg
    lda FacSign
    pha
    lda FacExponent
    sec
    sbc #$80                                ; the integer's count of bits
    bmi Finish                              ; none: zero
    sta SavedY
    cmp #LongInteger::BITS
    bcc *+5
    jmp Float::OverflowError
    lda #<(Arg)

;; Moves the integer's bits from the real's mantissa into <Arg>, one at a time.
;; Also: PASSABIT (BB13)
MoveBit:
    jsr LongInteger::ShiftRealLeft
    jsr LongInteger::ShiftLeftWithCarry
    dec SavedY
    bne MoveBit

;; Moves the magnitude in <Arg> to <Fac> and gives it the real's sign.
;; Also: GTFACNA (BB13)
Finish:
    lda #VALUE_TYPE_LONG_INTEGER
    sta ValueType
    lda #<(Arg)
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

;; Shifts the real <Fac>'s mantissa left one bit, <FacExtension> included.
;; Out: carry = the bit shifted out of <FacMantissa1>
;; Keeps: A, X, Y
;; Entry:
;;   Done = returns; <Functions::ConvLong> and <Functions::ConvString> branch here for a value already of their type
;; Also: ASLFAC (BB13)
.proc ShiftRealLeft
    asl FacExtension
    rol FacMantissa4
    rol FacMantissa3
    rol FacMantissa2
    rol FacMantissa1

;; Returns.
;; Also: CONV2RT2 (BB13)
Done:
    rts
.endproc

;; Reads a string as a long integer, through `VAL`'s code (<Functions::ParseStringWith>) with <LongInteger::ReadNumber>.
;; Also: STR2LNG (BB13)
.proc StringToLong
    lda #<(ReadNumber)
    ldy #>(ReadNumber)
    jmp Functions::ParseStringWith
.endproc

.endscope

; `CONV%`.
.scope Functions continued

;; The `CONV%` function: the <Fac>'s value rounded to an integer, as a real.
;; In: Fac = the value, ValueType = its type
;; Out: Fac = the rounded real, ValueType = 0
;; See: <Functions::Conv>
;; Also: CONV2INT (BB13)
.proc ConvInteger
    jsr Conv
    ; Falls into Float::RoundToInteger.
.endproc

.endscope

; Rounding a real.
.scope Float continued

;; Rounds the real <Fac> to the nearest integer, a half upward, as `INT(x + .5)` does.
;; Also: QINTRN (BB13)
.proc RoundToInteger
    jsr AddHalf
    jmp Functions::Int
.endproc

.endscope

; `CONV$`.
.scope Functions continued

;; The `CONV$` function: the <Fac>'s value as a string, as `STR$` writes it.
;; In: Fac = the value, ValueType = its type
;; Out: Fac = the string
;; See: <Str>, <LongInteger::FormatFac>
;; Also: CONV2STR (BB13)
.proc ConvString
    bit ValueType
    bmi LongInteger::ShiftRealLeft::Done    ; already a string
    bvs FromLong
    jmp Str

;; Makes a long integer's text a string.
;; Also: CONWASL (BB13)
FromLong:
    jsr LongInteger::FormatFac
    lda #<(LongText)
    ldx #LONG_TEXT_X_BYTE
    ldy #>(LongText)
    jmp Strings::FromText
.endproc

.endscope

; ---------------------------------------------------------------------------------------------------------------------
; Logic and comparison
; ---------------------------------------------------------------------------------------------------------------------

; The logical and relational operators.
.scope LongInteger continued

;; The `AND` operator for long integers: 1 when <Arg> and <Fac> are both nonzero, else 0.
;; Also: LAND (BB13)
.proc And
    lda #<(Fac)
    ldx #0
    ldy #>(Fac)
    jsr IsZero
    bne *+3
    rts                                     ; Fac is 0: so is the result
    lda #<(Arg)
    ldx #0
    ldy #>(Arg)
    jsr IsZero
    ; Falls into SetFacToTruth.
.endproc

;; Sets <Fac> to 1 when the zero flag is clear, or to 0 when it is set.
;; In: zero = set for 0
;; Entry:
;;   ToSetFacToZero = sets <Fac> to 0; <LongInteger::Or> and <LongInteger::Compare> branch here
;; Also: LGIVM1 (BB13)
.proc SetFacToTruth
    beq *+5
    jmp SetFacToOne

;; Sets <Fac> to 0.
;; Also: LGIVM0 (BB13)
ToSetFacToZero:
    jmp SetFacToZero
.endproc

;; The `OR` operator for long integers: 1 when <Arg> or <Fac> is nonzero, else 0.
;;
;; The first test reads <Fac> with whatever X the operator's dispatch left, an index below $80, which selects no bank.
;; Also: LONGOR (BB13)
.proc Or
    lda #<(Fac)
    ldy #>(Fac)
    jsr IsZero
    sta KeptY
    lda #<(Arg)
    ldy #>(Arg)
    ldx #0
    jsr IsZero
    ora KeptY
    beq SetFacToTruth::ToSetFacToZero
    jmp SetFacToOne
.endproc

;; The relational operators for long integers: 1 when the comparison of <Arg> with <Fac> holds, else 0.
;;
;; The top bytes are compared by the sign of their difference, which is wrong when they differ by $80 or more: 2^62
;; then reads as less than -(2^62). The call to <LongInteger::CompareMagnitudes::FromByte> is redundant, as
;; <LongInteger::CompareMagnitudes> compares all the bytes again.
;; In: RelationMask = the relations that are true: <RELATION_LESS>, <RELATION_EQUAL> and <RELATION_GREATER>
;; Out: Fac = 1 or 0
;; Also: LDOCOMP (BB13)
.proc Compare
    lda Arg
    cmp Fac
    bmi Less
    bne Greater
    ldx #1
    jsr CompareMagnitudes::FromByte
    jsr CompareMagnitudes
    beq Equal
    bcs Greater

;; <Arg> is less than <Fac>.
;; Also: LISL (BB13)
Less:
    lda #RELATION_LESS
    .byte 44                                ; BIT abs, which skips the next LDA

;; <Arg> equals <Fac>.
;; Also: LISEQ (BB13)
Equal:
    lda #RELATION_EQUAL
    .byte 44                                ; BIT abs, which skips the next LDA

;; <Arg> is greater than <Fac>.
;; Also: LISG (BB13)
Greater:
    lda #RELATION_GREATER
    and RelationMask
    bne SetFacToTruth                       ; the relation holds: 1
    beq SetFacToTruth::ToSetFacToZero       ; always: 0
.endproc

.endscope
