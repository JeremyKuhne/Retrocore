; LONGINT: Business BASIC's long integers. Reading and printing them, their arithmetic and comparisons, and the
; conversions between them, reals and strings (the CONV functions).
;
; A long integer is eight bytes of two's complement, most significant byte first, from -(2^63) to 2^63-1; a long
; variable's value is those eight bytes as they are, and VALTYP is $40 while one is in the FAC. The arithmetic works on
; three eight-byte numbers in BASIC's zero page: FAC (over the real FAC's bytes), ARG and RES, with the byte below
; RES (RES-1) catching a product's or quotient's overflow. Most routines reach their operands through PTR1, PTR2 and
; PTR3, which <LPTRS> points at FAC, ARG and FAC. A binary operator gets its left operand in ARG and its right in FAC.
;
; Names follow Apple's Business BASIC 1.3 listing.

; ---------------------------------------------------------------------------------------------------------------------
; Input
; ---------------------------------------------------------------------------------------------------------------------

;; Reads a long integer from the text at TXTPTR into FAC.
;;
;; An optional sign and then digits; a fraction after a period rounds the number to the nearest integer, an exact half
;; to the even one. There is no exponent.
;; In: TXTPTR = the number's first character
;; Out: FAC = the number, VALTYP = $40, TXTPTR = the first character after it
;; Errors: ERROV = the number is out of range
;; Uses: ARG, KIMY, YSAVE, PTR1, PTR2, PTR3
;; See: <FIN>, <LOUT>
LINP:
    lda #$40
    sta VALTYP
    lda #0
    sta KIMY                                ; bit 7 set for a minus sign
    ldx #7

;; Zeros FAC and ARG.
LZFAC1:
    sta FAC,X
    sta ARG,X
    dex
    bpl LZFAC1
    jsr CHRGOT
    bcc LISNUM                              ; a digit
    cmp #'+'
    beq LTRYN2
    cmp #'-'
    bne LTRYDOT
    lda #$FF
    eor KIMY
    sta KIMY
    jmp LTRYN2

;; Takes a digit into FAC: FAC = FAC * 10 + the digit.
;; In: A = the digit's character
LISNUM:
    and #$F
    sta YSAVE
    jsr LTIMES10
    jsr LZIPARG
    lda YSAVE
    sta ARG+7
    jsr LADDPTR                             ; FAC = FAC + ARG, through LTIMES10's pointers

;; Goes on to the next character, taking it if it is a digit.
LTRYN2:
    jsr CHRGET
    bcc LISNUM

;; Rounds by the fraction after a period, if any: up from a first digit above 5, or of 5 with any other digit after it.
LTRYDOT:
    cmp #'.'
    bne LNUMDON
    jsr CHRGET
    bcs LNUMDON
    cmp #'5'
    bcc LNUMSCN                             ; below .5: down
    bne LROUNDUP                            ; above .5: up

;; After a 5, looks for a digit other than 0, which rounds up; with none, the number rounds to even.
LTRYN3:
    jsr CHRGET
    bcs LRNDEVN                             ; exactly .5
    cmp #'1'
    bcc LTRYN3

;; Rounds up, then skips the fraction's other digits.
LROUNDUP:
    jsr LINCFAC

;; Skips the fraction's remaining digits.
LNUMSCN:
    jsr CHRGET
    bcc LNUMSCN
    bcs LNUMDON

;; Rounds exactly half to the even integer: up when FAC is odd.
LRNDEVN:
    lda FAC+7
    and #1
    beq LNUMDON
    jsr LINCFAC

;; Ends the number, negating it for a minus sign.
LNUMDON:
    lda KIMY
    bpl LDONE

;; Negates FAC.
;;
;; The overflow test in <LINCFAC> misfires here: negating $FF00000000000000 (-(2^56)) or $7F00000000000000 gives an
;; overflow error though the result fits, so -(2^56) can be neither printed nor converted to a real.
;; Out: FAC = -FAC
;; Errors: ERROV = see above
;; Uses: A, X
;; See: <TWOSCOMP>
LTWSCOMP:
    ldx #7

;; Complements FAC's bytes, before <LINCFAC> adds one.
LTWSONE:
    lda FAC,X
    eor #$FF
    sta FAC,X
    dex
    bpl LTWSONE

;; Adds one to FAC.
;;
;; When the carry reaches the top byte, the test for overflow looks at A rather than at FAC: from <LTWSCOMP>, A is the
;; top byte before the increment, and an error comes when it was $00 or $80, which is not the overflow case; from
;; LINP's rounding, A is never zero there, so rounding 9223372036854775807.5 up wraps to -(2^63) with no error.
;; Out: FAC = FAC + 1
;; Errors: ERROV = see above
;; Uses: X
LINCFAC:
    ldx #7

;; Increments FAC's bytes from the lowest while each carries.
LTWSCO2:
    inc FAC,X
    bne LDONE
    dex
    bne LTWSCO2
    inc FAC
    and #$7F                                ; tests A, not FAC
    bne LDONE

;; Ends with an overflow error.
LOVINP:
    jmp LOVERR

;; An RTS for the input routines.
LDONE:
    rts

;; Multiplies FAC by 10, as FAC * 2 + FAC * 8, and leaves <LPTRS>'s pointers set.
;; Errors: ERROV = the product is out of range
;; Uses: ARG, PTR1, PTR2, PTR3
LTIMES10:
    jsr LPTRS
    lda #<(FAC)
    jsr LSHFTL                              ; times 2
    bmi LOVINP
    jsr FACTOARG
    jsr LSHFTL                              ; times 4
    bmi LOVINP
    jsr LSHFTL                              ; times 8
    bmi LOVINP
    jsr LADDPTR
    rts

;; Copies FAC to ARG.
;; Keeps: A, Y
FACTOARG:
    pha
    ldx #8

;; Copies FAC's bytes to ARG, from the last.
FAC2AR2:
    lda FAC-1,X
    sta ARG-1,X
    dex
    bne FAC2AR2
    pla
    rts

; ---------------------------------------------------------------------------------------------------------------------
; Signs and results
; ---------------------------------------------------------------------------------------------------------------------

;; Makes the two operands positive for a multiply or divide, noting the result's sign.
;; In: PTR1, PTR2 = the operands, in zero page
;; Out: INPFLG = bit 7 set when the result is negative (the signs differ)
;; Uses: A, X, Y
;; See: <LRESDV>
LSGNPOS:
    ldy #0
    lda (PTR1),Y
    eor (PTR2),Y
    sta INPFLG
    lda (PTR1),Y
    bpl LSGNP2
    lda PTR1
    jsr TWOSCOMP

;; Makes the second operand positive.
LSGNP2:
    ldy #0
    lda (PTR2),Y
    bpl LSGNP3
    lda PTR2
    jsr TWOSCOMP

;; An RTS for <LSGNPOS>.
LSGNP3:
    rts

;; Moves a product from RES to FAC with its sign, or ends with an overflow error when it grew past RES.
;; See: <LMULT>
LRESPOS:
    lda RES-1
    bne LOVERR

;; Moves a quotient from RES to FAC with its sign.
LRESDIV:
    lda #<(RES)
    sta PTR3

;; Moves a result from (<PTR3>) to FAC, negating it first when <INPFLG> says the result is negative.
;; In: PTR3 = the result, in zero page, INPFLG = bit 7 set for a negative result
;; Out: FAC = the result
;; Errors: ERROV = bit 7 of RES is set (it is checked even when the result is elsewhere)
LRESDV:
    lda #<(FAC)
    sta PTR1
    lda RES
    bmi LOVERR
    lda INPFLG
    bpl LRESP2
    lda PTR3
    jsr TWOSCOMP

;; Copies the eight bytes.
LRESP2:
    ldy #7

;; Copies a byte, from the last.
LRES2F2:
    lda (PTR3),Y
    sta (PTR1),Y
    dey
    bpl LRES2F2
    rts

; ---------------------------------------------------------------------------------------------------------------------
; Utilities, addition and subtraction
; ---------------------------------------------------------------------------------------------------------------------

;; Zeros RES and the overflow byte below it.
;; Out: A = 0, X = $FF
LZIPRES:
    lda #0
    ldx #8

;; Zeros a byte, from the last.
LZIP2:
    sta RES-1,X
    dex
    bpl LZIP2
    rts

;; Stores FAC as a long integer in memory.
;; In: A = the address's low byte, Y = its high byte, X = its bank
;; Uses: INDEX, INDEXB, Y
;; See: <LDFACT>
STFACT:
    sta INDEX
    stx INDEXB
    sty INDEX+1
    ldy #7

;; Stores a byte, from the last.
STFAC2:
    lda FAC,Y
    sta (INDEX),Y
    dey
    bpl STFAC2
    rts

;; Points PTR1 and PTR3 at FAC and PTR2 at ARG, all in zero page, for FAC = FAC op ARG.
;; Out: A = ARG's address, Y = 0
LPTRS:
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

;; The + operator for long integers: FAC = ARG + FAC.
;; Errors: ERROV = the sum is out of range
LADD:
    jsr LPTRS

;; Adds two long integers: (<PTR3>) = (<PTR1>) + (<PTR2>).
;; Errors: ERROV = the sum is out of range
LADDPTR:
    ldy #7
    clc

;; Adds a byte, from the last.
LADD2:
    lda (PTR1),Y
    adc (PTR2),Y
    sta (PTR3),Y
    dey
    bpl LADD2
    bvs LOVERR
    rts

;; Ends the statement with an overflow error.
LOVERR:
    ldx #ERROV
    jmp ERROR

;; Subtracts with the pointers set: FAC = ARG - FAC, with no overflow check.
;; Out: overflow = set when the result is out of range
LSUBB:
    jsr LPTRS

;; Subtracts two long integers: (<PTR3>) = (<PTR2>) - (<PTR1>), with no overflow check.
;; Out: carry = clear for a borrow, overflow = set when the result is out of range
LSUBER:
    ldy #7
    sec

;; Subtracts a byte, from the last.
LSUB2:
    lda (PTR2),Y
    sbc (PTR1),Y
    sta (PTR3),Y
    dey
    bpl LSUB2
    rts

;; The - operator for long integers: FAC = ARG - FAC.
;; Errors: ERROV = the difference is out of range
LSUB:
    jsr LSUBB
    bvs LOVERR
    rts

;; Negates a long integer in zero page.
;;
;; -(2^63) stays itself.
;; In: A = the number's zero page address
;; Uses: A, X, Y
;; See: <LTWSCOMP>
TWOSCOMP:
    tax
    ldy #7

;; Complements the bytes, from the first.
LEORIT:
    lda 0,X
    eor #$FF
    sta 0,X
    inx
    dey
    bpl LEORIT
    ldy #7

;; Adds one, from the last byte, while each carries.
INCPTR2:
    dex
    inc 0,X
    bne INCRT2
    dey
    bpl INCPTR2

;; An RTS for <TWOSCOMP>.
INCRT2:
    rts

; ---------------------------------------------------------------------------------------------------------------------
; Multiplication
; ---------------------------------------------------------------------------------------------------------------------

;; The * operator for long integers: FAC = ARG * FAC.
;;
;; Multiplies the magnitudes a byte by a byte into RES, skipping zero bytes, then gives the product its sign.
;; Errors: ERROV = the product is out of range
;; Uses: ARG, RES, INDEX, KIMY, INPFLG, PTR1, PTR2, PTR3
;; See: <LMULTBYT>, <LRESPOS>
LMULT:
    jsr LPTRS
    jsr LSGNPOS
    lda #<(FAC+7)
    sta PTR1                                ; the row: FAC's bytes, from the last
    lda #<(ARG+7)
    sta PTR2                                ; the column: ARG's bytes, from the last
    lda #<(RES+6)
    sta PTR3                                ; where the first byte product goes
    jsr LZIPRES

;; Multiplies the row's byte of FAC by each byte of ARG.
LMULT1:
    ldy #0
    lda (PTR1),Y
    beq LMULT3                              ; a zero byte: skip the row

;; Multiplies the row's byte by one byte of ARG, unless it is zero.
LMULT2:
    lda (PTR2),Y
    beq *+5
    jsr LMULTBYT
    dec PTR3                                ; the next product a byte higher
    dec PTR2
    lda PTR2
    cmp #ARG
    bcs LMULT2
    lda #<(ARG+7)
    sta PTR2                                ; back to ARG's last byte
    lda PTR3
    clc
    adc #8
    sta PTR3

;; Moves on to the next byte of FAC, a byte higher in RES.
LMULT3:
    dec PTR3
    dec PTR1
    lda PTR1
    cmp #FAC
    bcs LMULT1
    jmp LRESPOS

;; Multiplies the byte at (<PTR1>) by the byte at (<PTR2>) and adds the 16-bit product into RES at (<PTR3>).
;; In: Y = 0, PTR3 = where the product's high byte goes
;; Out: Y = 0
;; Errors: ERROV = the product or its carry would go above RES-1
;; Uses: A, X, INDEX, KIMY
LMULTBYT:
    sty INDEX                               ; the product: INDEX high, INDEX+1 low
    sty INDEX+1
    lda (PTR1),Y
    sta KIMY
    ldx #8

;; Adds the multiplicand for each 1 bit of the multiplier, shifting the product right.
LMULTB2:
    ror KIMY
    bcc LMULTB3
    lda (PTR2),Y
    clc
    adc INDEX
    sta INDEX

;; Shifts the product right a bit, with the carry from the add.
LMULTB3:
    ror INDEX
    ror INDEX+1
    dex
    bne LMULTB2
    lda PTR3
    cmp #RES-1
    bcs *+5

;; Ends with an overflow error.
LMULTOV:
    jmp LOVERR
    ldx PTR3
    lda INDEX+1
    clc
    adc 1,X
    sta 1,X
    lda INDEX
    adc 0,X
    sta 0,X
    bcc LMULTBR

;; Carries into the bytes above, as far as RES-1.
LMULTB4:
    dex
    cpx #RES-1
    bcc LMULTOV
    inc 0,X
    beq LMULTB4

;; An RTS for <LMULTBYT>.
LMULTBR:
    rts

; ---------------------------------------------------------------------------------------------------------------------
; Shifts
; ---------------------------------------------------------------------------------------------------------------------

;; Shifts a long integer in zero page left one bit, a 0 in.
;; In: A = the number's zero page address
;; Out: Y = the new top byte, negative = its bit 7, carry = the bit shifted out
;; Uses: X
;; Keeps: A
LSHFTL:
    clc

;; Shifts a long integer in zero page left one bit, the carry in.
;; In: A = the number's zero page address, carry = the bit to shift in
;; Out: Y = the new top byte, negative = its bit 7, carry = the bit shifted out
;; Uses: X
;; Keeps: A
LSHFTLC:
    tax
    ldy #8

;; Rotates a byte, from the last.
LSHFT2:
    rol 7,X
    dex
    dey
    bne LSHFT2
    ldy 8,X
    rts

;; Shifts a long integer in zero page right one bit, a 0 in.
;; In: A = the number's zero page address
;; Out: carry = the bit shifted out
;; Uses: X, Y
;; Keeps: A
LSHFTR:
    clc
    tax
    ldy #8

;; Rotates a byte, from the first.
LSHFTR2:
    ror 0,X
    inx
    dey
    bne LSHFTR2
    rts

;; Shifts FAC left eight bits, a byte at a time.
;; Out: X = 0
LSHLEIGT:
    ldx #0

;; Moves a byte up.
LSHLE2:
    lda FAC+1,X
    sta FAC,X
    inx
    cpx #7
    bcc LSHLE2
    ldx #0
    stx FAC+7
    rts

; ---------------------------------------------------------------------------------------------------------------------
; Division
; ---------------------------------------------------------------------------------------------------------------------

;; Divides the magnitude of ARG by that of FAC, the work of DIV, / and MOD.
;;
;; FAC, the divisor, is shifted left until its top 1 bit is bit 62, KIMY times. The dividend in ARG is then compared
;; with it and shifted left KIMY + 1 times, the divisor subtracted whenever it fits, and each step's quotient bit
;; shifted into RES. RES-1 has bit 7 set from the first subtraction on; RES is not shifted before it, as its bits are
;; all zero.
;; Out: RES = the quotient's magnitude, ARG = the remainder shifted left KIMY + 1 bits,
;;   carry = set when twice the remainder is at least the divisor, INPFLG = bit 7 set for a negative result
;; Errors: ERRDV0 = FAC is zero
;; Uses: YSAVE, PTR1, PTR2, PTR3
;; See: <LDIV>, <LDIVT>, <LREM>
LDIVER:
    jsr LPTRS
    jsr LZIPRES
    jsr LSGNPOS
    jsr LNRMFAC
    ldx KIMY
    stx YSAVE
    lda #<(ARG)
    sta PTR3                                ; differences go to ARG
    inc YSAVE                               ; KIMY + 1 steps
    bne LDIVCOM                             ; always

;; Shifts the quotient bit in the carry into RES, once a subtraction has been made, and the dividend left.
LDECYSAV:
    lda RES-1
    bpl LRESOK
    lda #<(RES)
    jsr LSHFTLC

;; Shifts the dividend left.
LRESOK:
    lda #<(ARG)
    jsr LSHFTL

;; Compares the dividend with the divisor and subtracts it when it fits, until the steps are done.
LDIVCOM:
    jsr LCOMP
    dec YSAVE
    bmi LGOTRES                             ; done: the carry is the next bit, for rounding
    bcc LDECYSAV                            ; doesn't fit: a 0 bit
    jsr LSUBER
    lda #$80
    sta RES-1                               ; a subtraction made
    bcs LDECYSAV                            ; always: a 1 bit

;; An RTS for <LDIVER>.
LGOTRES:
    rts

;; The / operator for long integers: FAC = ARG / FAC, rounded to the nearest integer, an exact half to the even one.
;; Errors: ERRDV0 = FAC is zero, ERROV = the quotient is out of range
;; See: <LDIVER>, <LDIV>
LDIVT:
    jsr LDIVER
    bcc LNOROUND                            ; under a half: no rounding
    jsr LSUBER                              ; ARG = 0 when exactly a half
    lda #<(ARG)
    ldx #0
    ldy #>(ARG)
    jsr LORALL
    sta YSAVE
    lda RES+7
    and #$1
    ora YSAVE
    beq LNOROUND                            ; exactly a half, and the quotient is even
    ldx #8

;; Adds one to the quotient in RES, from the last byte.
LINCBYT:
    inc RES-1,X
    bne LNOROUND
    dex
    bne LINCBYT

;; Moves the quotient to FAC with its sign.
LNOROUND:
    jmp LRESDIV

;; Shifts FAC left until its top 1 bit is bit 62, counting the shifts.
;;
;; A negative FAC, only ever -(2^63), is shifted right once instead.
;; In: FAC = a positive number
;; Out: KIMY = the bits shifted left, -1 for the one right
;; Errors: ERRDV0 = FAC is zero
LNRMFAC:
    ldy #0
    sty KIMY

;; Shifts a byte at a time while the top byte is zero.
LDIVE2:
    lda FAC
    bne LDIVE3
    jsr LSHLEIGT
    lda KIMY
    clc
    adc #8
    sta KIMY
    cmp #64
    bcc LDIVE2
    jmp DV0ERR                              ; all 64 bits zero

;; Shifts a bit at a time until bit 6 of the top byte is set.
LDIVE3:
    lda #<(FAC)
    bit FAC
    bmi LDIVTOFAR
    bvs LDIVOK
    jsr LSHFTL
    inc KIMY
    bne LDIVE3                              ; always

;; Shifts the one bit right that went too far.
LDIVTOFAR:
    jsr LSHFTR
    dec KIMY

;; An RTS for <LNRMFAC>.
LDIVOK:
    rts

;; Compares ARG with FAC as unsigned numbers.
;; Out: carry = set when ARG >= FAC, zero = set when they are equal
;; Uses: A, X
LCOMP:
    ldx #0

;; Compares from the byte at X on.
;; In: X = the first byte to compare
;; Out: carry = set when ARG >= FAC, zero = set when they are equal
LCMP2:
    lda ARG,X
    cmp FAC,X
    bne LCMP3
    inx
    cpx #8
    bcc LCMP2

;; An RTS for <LCOMP>.
LCMP3:
    rts

;; The DIV operator for long integers: FAC = ARG / FAC, the fraction dropped.
;; Errors: ERRDV0 = FAC is zero, ERROV = the quotient is out of range
;; See: <LDIVER>, <LDIVT>
LDIV:
    jsr LDIVER
    jmp LRESDIV

;; The MOD operator for long integers: FAC = the remainder of ARG / FAC.
;;
;; The remainder of the two sizes is made negative when exactly one operand is, as a quotient would be, rather than
;; taking the dividend's sign: -7 MOD 2 and 7 MOD -2 are both -1, and -7 MOD -2 is 1.
;; Errors: ERRDV0 = FAC is zero
;; See: <LDIVER>
LREM:
    jsr LDIVER
    ldy #0
    lda #<(ARG)

;; Shifts the remainder back right KIMY + 1 bits.
LREM2:
    jsr LSHFTR
    dec KIMY
    bpl LREM2
    sta PTR3
    jmp LRESDV

;; Tells whether a long integer is zero, by ORing its bytes.
;; In: A = the address's low byte, Y = its high byte, X = its bank
;; Out: A = 0 and zero = set when all eight bytes are zero
;; Uses: Y, INDEX, INDEXB
;; Keeps: X, overflow
LORALL:
    sta INDEX
    stx INDEXB
    sty INDEX+1
    lda #0
    ldy #7

;; ORs in a byte, from the last, stopping at the first nonzero one.
LORAL2:
    ora (INDEX),Y
    bne LGOTOR
    dey
    bpl LORAL2
    tay                                     ; the zero flag set

;; An RTS for <LORALL>.
LGOTOR:
    rts

; ---------------------------------------------------------------------------------------------------------------------
; Output
; ---------------------------------------------------------------------------------------------------------------------

;; Turns FAC's long integer into decimal digits in NUMSTR, for <LOUT> and PRINT USING.
;;
;; The magnitude is converted to 20 binary-coded decimal digits by doubling: each bit, from the top 1 bit down, doubles
;; the decimal number in ARG..ARG+9 and adds the bit. <UUNPACK> then spreads the digits out, one a byte, dropping the
;; leading zeros.
;; In: FAC = the number
;; Out: NUMSTR+2.. = the digits, values 0 to 9, ISARA = twice the count of digits, plus 1 for a negative number,
;;   FACSGN = bit 7 set for a negative number
;; Errors: ERROV = FAC is -(2^56), from <LTWSCOMP>
;; Uses: ARG, KIMY
;; See: <LOUT>, <UUNPACK>
LUNPACK:
    lda FACEXP                              ; FAC's top byte
    cmp #$80
    lda #20
    rol
    sta ISARA                               ; 40, or 41 for a negative number
    lda FAC
    pha
    bpl *+5
    jsr LTWSCOMP
    lda #<(FAC)
    ldx #0
    ldy #>(FAC)
    jsr LORALL
    beq *+5                                 ; zero: no 1 bit to find
    jsr LNRMFAC
    lda #64
    sec
    sbc KIMY
    sta KIMY                                ; the bits to convert, from bit 63
    jsr LZIPARG

;; Converts one bit: shifts it out of FAC and doubles the decimal number with the bit added.
LCONVBCD:
    lda #<(FAC)
    jsr LSHFTL
    ldx #10
    sed

;; Doubles a byte of the decimal number with the carry, from the last.
LADDBCD:
    lda ARG-1,X
    adc ARG-1,X
    sta ARG-1,X
    dex
    bne LADDBCD
    cld
    dec KIMY
    bne LCONVBCD
    ldx #10

;; Copies the decimal number to FACT, where <UUNPACK> reads it.
LABCD2:
    lda ARG-1,X
    sta FACT-1,X
    dex
    bne LABCD2
    jsr UUNPACK
    pla
    sta FACSGN
    rts

;; Zeros ARG and the two bytes after it, RES-1 and RES.
;; Out: A = 0, X = 0
LZIPARG:
    lda #0
    ldx #10

;; Zeros a byte, from the last.
LZIPAR2:
    sta ARG-1,X
    dex
    bne LZIPAR2
    rts

;; Writes FAC's long integer as text in NUMSTR: a minus sign if negative, then the digits, then a zero.
;; In: FAC = the number
;; Out: NUMSTR = the text, LENUM = its length, X = its length
;; See: <LUNPACK>, <CONV2STR>
LOUT:
    jsr LUNPACK
    ldx #0
    lda #'0'
    sta NUMSTR                              ; for zero, which has no digits
    lsr ISARA                               ; the count of digits
    ldy #1

;; Takes the next digit, ending when there are no more.
LLOOKLUP:
    iny
    dec ISARA
    bmi LISZERO
    lda NUMSTR,Y
    cpx #0
    beq LOUT3                               ; the first digit: the sign goes before it

;; Writes a digit as its character.
LOUT5:
    ora #'0'
    sta NUMSTR,X
    inx
    bne LLOOKLUP

;; Writes a minus sign before the first digit of a negative number.
LOUT3:
    sta KIMY
    bit FACSGN
    bpl LLOKLUP
    lda #'-'
    sta NUMSTR,X
    inx

;; Takes the first digit back to write it.
LLOKLUP:
    lda KIMY
    bne LOUT5                               ; always: the first digit is not 0

;; Ends the text with a zero, keeping at least the one character, `0`.
LISZERO:
    cpx #1
    bcs *+4
    ldx #1
    stx LENUM
    lda #0
    sta NUMSTR,X
    rts

; ---------------------------------------------------------------------------------------------------------------------
; Loads and stores
; ---------------------------------------------------------------------------------------------------------------------

;; Sets FAC to the long integer 0.
;; Out: A = 0, X = $FF
LONGST0:
    lda #0
    ldx #7

;; Fills FAC's bytes up to X with A.
;; In: A = the byte, X = the last byte's index
LONGST:
    sta FAC,X
    dex
    bpl LONGST
    rts

;; Sets FAC to the long integer 1.
LONGST1:
    jsr LONGST0
    lda #1
    sta FAC+7
    rts

;; Loads a long integer from memory into FAC.
;; In: A = the address's low byte, Y = its high byte, X = its bank
;; Out: FAC = the number
;; Uses: Y, INDEX, INDEXB
;; See: <STFACT>
DMOVFM:
LDFACT:
    sta INDEX
    stx INDEXB
    sty INDEX+1
    ldy #7

;; Loads a byte, from the last.
LDFAC2:
    lda (INDEX),Y
    sta FAC,Y
    dey
    bpl LDFAC2
    rts

; ---------------------------------------------------------------------------------------------------------------------
; Conversions
; ---------------------------------------------------------------------------------------------------------------------

;; The CONV function: the FAC's value as a real.
;;
;; A string is read as VAL reads it; a long integer is converted; a real stays as it is.
;; In: FAC = the value, VALTYP = its type
;; Out: FAC = the real, VALTYP = 0
;; See: <LMAKFLT>, <VAL>
CONV2FLT:
    bit VALTYP
    bmi STR2FLT
    bvc CONV2RTS                            ; already a real

;; Converts FAC's long integer to a real.
;;
;; The real takes the magnitude's top 40 bits, the last 8 of them in FACOV, so it is rounded when it is next stored.
;; Out: FAC = the real, VALTYP = 0
;; Errors: ERROV = FAC is -(2^56), from <LTWSCOMP>
;; Uses: KIMY
;; See: <CONV2LNG>
LMAKFLT:
    lda FAC
    pha                                     ; the sign
    bpl *+5
    jsr LTWSCOMP
    lda #<(FAC)
    ldx #0
    ldy #>(FAC)
    jsr LORALL
    bne *+6
    pla
    jmp GIVE0                               ; zero
    jsr LNRMFAC                             ; the top 1 bit to bit 62
    jsr LSHFTL                              ; and to bit 63, which KIMY does not count
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
    lda #$80+$3F                            ; bit 63 is 2^63: an exponent of 64, less the shifts
    sec
    sbc KIMY
    sta FACEXP
    pla
    sta FACSGN
    lda #0
    sta VALTYP                              ; a real

;; An RTS for the conversions.
CONV2RTS:
    rts

;; Reads a string as a real, as VAL does.
STR2FLT:
    jmp VAL

;; The CONV& function: the FAC's value as a long integer.
;;
;; A real is rounded to the nearest integer, a half upward; a string is read as a long integer, as VAL reads a real.
;; In: FAC = the value, VALTYP = its type
;; Out: FAC = the long integer, VALTYP = $40
;; Errors: ERROV = a real of 2^63 or more in size
;; Uses: ARG, YSAVE
;; See: <LINP>, <LMAKFLT>
CONV2LNG:
    bit VALTYP
    bmi STR2LNG
    bvs CONV2RT2                            ; already a long integer
    jsr QINTRN
    jsr LZIPARG
    lda FACSGN
    pha
    lda FACEXP
    sec
    sbc #$80                                ; the integer's count of bits
    bmi GTFACNA                             ; none: zero
    sta YSAVE
    cmp #$40
    bcc *+5
    jmp OVERR
    lda #<(ARG)

;; Moves the integer's bits from the real's mantissa into ARG, one at a time.
PASSABIT:
    jsr ASLFAC
    jsr LSHFTLC
    dec YSAVE
    bne PASSABIT

;; Moves the magnitude in ARG to FAC and gives it the real's sign.
GTFACNA:
    lda #$40
    sta VALTYP
    lda #<(ARG)
    ldx #0
    jsr LDFACT
    pla
    bpl *+5
    jsr LTWSCOMP
    rts

;; Shifts the real FAC's mantissa left one bit, FACOV included.
;; Out: carry = the bit shifted out of FACHO
ASLFAC:
    asl FACOV
    rol FACLO
    rol FACMO
    rol FACMOH
    rol FACHO

;; An RTS for the conversions.
CONV2RT2:
    rts

;; Reads a string as a long integer, through VAL's code with <LINP>.
STR2LNG:
    lda #<(LINP)
    ldy #>(LINP)
    jmp VALSTR

;; The CONV% function: the FAC's value rounded to an integer, as a real.
;; In: FAC = the value, VALTYP = its type
;; Out: FAC = the rounded real, VALTYP = 0
;; See: <CONV2FLT>
CONV2INT:
    jsr CONV2FLT

;; Rounds the real FAC to the nearest integer, a half upward: INT(FAC + .5).
QINTRN:
    jsr FADDH
    jmp INT

;; The CONV$ function: the FAC's value as a string, as STR$ writes it.
;; In: FAC = the value, VALTYP = its type
;; Out: FAC = the string
;; See: <STRS>, <LOUT>
CONV2STR:
    bit VALTYP
    bmi CONV2RT2                            ; already a string
    bvs CONWASL
    jmp STRS

;; Makes a long integer's text a string.
CONWASL:
    jsr LOUT
    lda #<(NUMSTR)
    ldx #NUMSTRB
    ldy #>(NUMSTR)
    jmp STRLIT

; ---------------------------------------------------------------------------------------------------------------------
; Logic and comparison
; ---------------------------------------------------------------------------------------------------------------------

;; The AND operator for long integers: 1 when ARG and FAC are both nonzero, else 0.
LAND:
    lda #<(FAC)
    ldx #0
    ldy #>(FAC)
    jsr LORALL
    bne *+3
    rts                                     ; FAC is 0: so is the result
    lda #<(ARG)
    ldx #0
    ldy #>(ARG)
    jsr LORALL

;; Sets FAC to 1 when the zero flag is clear, or to 0 when it is set.
;; In: zero = set for 0
LGIVM1:
    beq *+5
    jmp LONGST1

;; Sets FAC to 0.
LGIVM0:
    jmp LONGST0

;; The OR operator for long integers: 1 when ARG or FAC is nonzero, else 0.
;;
;; The first test reads FAC with whatever X the operator's dispatch left, an index below $80, which selects no bank.
LONGOR:
    lda #<(FAC)
    ldy #>(FAC)
    jsr LORALL
    sta KIMY
    lda #<(ARG)
    ldy #>(ARG)
    ldx #0
    jsr LORALL
    ora KIMY
    beq LGIVM0
    jmp LONGST1

;; The relational operators for long integers: 1 when the comparison of ARG with FAC holds, else 0.
;;
;; The top bytes are compared by the sign of their difference, which is wrong when they differ by $80 or more: 2^62
;; then reads as less than -(2^62). The call to <LCMP2> is redundant, as <LCOMP> compares all the bytes again.
;; In: DOMASK = the relations that are true: 4 for less, 2 for equal, 1 for greater
;; Out: FAC = 1 or 0
LDOCOMP:
    lda ARG
    cmp FAC
    bmi LISL
    bne LISG
    ldx #1
    jsr LCMP2
    jsr LCOMP
    beq LISEQ
    bcs LISG

;; ARG is less than FAC.
LISL:
    lda #4
    .byte 44                                ; BIT abs, which skips the next LDA

;; ARG equals FAC.
LISEQ:
    lda #2
    .byte 44                                ; BIT abs, which skips the next LDA

;; ARG is greater than FAC.
LISG:
    lda #1
    and DOMASK
    bne LGIVM1                              ; the relation holds: 1
    beq LGIVM0                              ; always: 0
