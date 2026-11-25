;; THE FUNCTIONS ($DD40-$DFFF)
;;
;; The floating point package's polynomial evaluator (PLYEVL), its loads, stores and move (FLD0R-FMOVE), its
;; exponentials (EXP, EXP10) and logarithms (LOG, LOG10), and the constants they use, with the arctangent's
;; coefficients and pi/4, which the package itself never reads but programs such as Atari BASIC use by address.
;; The routines borrow AFP's variables for their own: PLYEVL counts in ESIGN, and EXP10 and LOG keep a power of ten
;; in DIGRT and a sign or flag in FCHRFLG.

; The polynomials' lengths, in coefficients.

EXP_COEFFICIENT_COUNT = 10          ;; the coefficients of <EXP_COEFFICIENTS>, for 10^(F/2)
LOG_COEFFICIENT_COUNT = 10          ;; the coefficients of <LOG_COEFFICIENTS>, for log10
ATN_COEFFICIENT_COUNT = 11          ;; the coefficients of <ATN_COEFFICIENTS>, for the arctangent

;; Evaluates a polynomial in FR0, from a table of coefficients highest power first.
;;
;; Works by Horner's rule, P(Z) = (...(A(n)*Z + A(n-1))*Z + ... + A(1))*Z + A(0), keeping Z in PLYARG and counting
;; the coefficients in ESIGN. It also uses whatever <FMUL> and <FADD> use. The manual's calling sequence; with one
;; coefficient it returns carry as it found it, and A = 0 counts as 256 coefficients.
;; In: FR0 = Z, X = the table's address, low byte, Y = its high byte, A = the number of coefficients
;; Out: FR0 = the polynomial's value, carry = set on overflow
;; Uses: A, X, Y, FR1, ESIGN, FPTR2, FLPTR, PLYARG
;; Errors: carry = set when a multiply or add is out of range
;; See: <FLD0R>, <FMUL>, <FADD>, <EXP_COEFFICIENTS>, <LOG_COEFFICIENTS>, <ATN_COEFFICIENTS>
PLYEVL:
    .assert PLYEVL = $DD40, "PLYEVL is at $DD40."
    stx FPTR2
    sty FPTR2+1
    sta ESIGN                       ; the coefficients left
    ldx #<PLYARG
    ldy #>PLYARG
    jsr FST0R                       ; keep Z
    jsr FMOVE                       ; FR1 = Z for the first multiply
    ldx FPTR2
    ldy FPTR2+1
    jsr FLD0R                       ; the sum starts as the first coefficient
    dec ESIGN
    beq PLYEVL_DONE
PLYEVL_LOOP:
    jsr FMUL                        ; sum * Z
    bcs PLYEVL_DONE
    clc
    lda FPTR2                       ; on to the next coefficient
    adc #FP_SIZE
    sta FPTR2
    bcc PLYEVL_ADD
    lda FPTR2+1
    adc #$00
    sta FPTR2+1
PLYEVL_ADD:
    ldx FPTR2
    ldy FPTR2+1
    jsr FLD1R
    jsr FADD                        ; sum * Z + the coefficient
    bcs PLYEVL_DONE
    dec ESIGN
    beq PLYEVL_DONE
    ldx #<PLYARG
    ldy #>PLYARG
    jsr FLD1R                       ; FR1 = Z again
    bmi PLYEVL_LOOP                 ; always: FLD1R leaves Y = $FF
PLYEVL_DONE:
    rts

;; Loads FR0 from the floating point number at X/Y.
;; In: X = the number's address, low byte, Y = its high byte
;; Out: FR0 = the number, FLPTR = its address, Y = $FF, negative = set
;; Uses: A
;; Keeps: X, carry
;; Entry: FLD0P = takes the address from FLPTR
;; See: <FLD1R>, <FST0R>
FLD0R:
    .assert FLD0R = $DD89, "FLD0R is at $DD89."
    stx FLPTR
    sty FLPTR+1
;; Loads FR0 from the floating point number FLPTR points to.
;; In: FLPTR = the number's address
;; Out: FR0 = the number, Y = $FF, negative = set
;; Uses: A
;; Keeps: X, carry
;; See: <FLD0R>
FLD0P:
    .assert FLD0P = $DD8D, "FLD0P is at $DD8D."
    ldy #FP_SIZE-1
FLD0P_LOOP:
    lda (FLPTR),y
    sta FR0,y
    dey
    bpl FLD0P_LOOP
    rts

;; Loads FR1 from the floating point number at X/Y.
;; In: X = the number's address, low byte, Y = its high byte
;; Out: FR1 = the number, FLPTR = its address, Y = $FF, negative = set
;; Uses: A
;; Keeps: X, carry
;; Entry: FLD1P = takes the address from FLPTR
;; See: <FLD0R>, <FMOVE>
FLD1R:
    .assert FLD1R = $DD98, "FLD1R is at $DD98."
    stx FLPTR
    sty FLPTR+1
;; Loads FR1 from the floating point number FLPTR points to.
;; In: FLPTR = the number's address
;; Out: FR1 = the number, Y = $FF, negative = set
;; Uses: A
;; Keeps: X, carry
;; See: <FLD1R>
FLD1P:
    .assert FLD1P = $DD9C, "FLD1P is at $DD9C."
    ldy #FP_SIZE-1
FLD1P_LOOP:
    lda (FLPTR),y
    sta FR1,y
    dey
    bpl FLD1P_LOOP
    rts

;; Stores FR0 at X/Y.
;; In: FR0 = the number, X = where it goes, low byte, Y = the high byte
;; Out: FLPTR = the address, Y = $FF, negative = set
;; Uses: A
;; Keeps: X, carry
;; Entry: FST0P = takes the address from FLPTR
;; See: <FLD0R>
FST0R:
    .assert FST0R = $DDA7, "FST0R is at $DDA7."
    stx FLPTR
    sty FLPTR+1
;; Stores FR0 where FLPTR points.
;; In: FR0 = the number, FLPTR = where it goes
;; Out: Y = $FF, negative = set
;; Uses: A
;; Keeps: X, carry
;; See: <FST0R>
FST0P:
    .assert FST0P = $DDAB, "FST0P is at $DDAB."
    ldy #FP_SIZE-1
FST0P_LOOP:
    lda FR0,y
    sta (FLPTR),y
    dey
    bpl FST0P_LOOP
    rts

;; Copies FR0 to FR1.
;; In: FR0 = the number
;; Out: FR1 = the number, X = $FF, negative = set
;; Uses: A
;; Keeps: Y, carry, FR0
;; See: <FLD1R>
FMOVE:
    .assert FMOVE = $DDB6, "FMOVE is at $DDB6."
    ldx #FP_SIZE-1
FMOVE_LOOP:
    lda FR0,x
    sta FR1,x
    dex
    bpl FMOVE_LOOP
    rts

;; Raises e to the power in FR0.
;;
;; Multiplies by log10(e) and goes on into <EXP10>, as e^X = 10^(X * log10(e)).
;; In: FR0 = the power, X
;; Out: FR0 = e^X, carry = set on overflow
;; Uses: A, X, Y, FR1, DIGRT, FCHRFLG, ESIGN, FPTR2, FLPTR, PLYARG, FPSCR
;; Errors: carry = set when the result is out of range
;; See: <EXP10>, <LOG>
EXP:
    .assert EXP = $DDC0, "EXP is at $DDC0."
    ldx #<FP_LOG10_E
    ldy #>FP_LOG10_E
    jsr FLD1R
    jsr FMUL
    bcs EXP10_OVERFLOW
;; Raises 10 to the power in FR0.
;;
;; Splits |X| into an integer I, which <FPI> rounds to the nearest, and a fraction F = |X| - I (from -0.5 to 0.5),
;; or takes I = 0 and F = |X| when |X| is below 1. 10^F is the square of <EXP_COEFFICIENTS>' polynomial, which
;; approximates 10^(F/2); 10^I is a number made with I/2 as its power of 100 and a mantissa of 1 or 10. A negative X
;; then takes the reciprocal. It also uses whatever the arithmetic routines use.
;;
;; A result too large for the format, from X about 98 up, is reported as an overflow, and so is X from about -128
;; down, whose power of 100 overflows. A result too small, from X about -99 to -127, comes back as 0 without an
;; error, since the reciprocal is taken last. FPI's failure isn't checked: from 65536 up, a negative X can come back
;; as a wrong, tiny number without an error (-65536 and -100000 do).
;; In: FR0 = the power, X
;; Out: FR0 = 10^X, carry = set on overflow
;; Uses: A, X, Y, FR1, DIGRT, FCHRFLG, ESIGN, FPTR2, FLPTR, PLYARG, FPSCR
;; Errors: carry = set when the result is out of range
;; See: <EXP>, <LOG10>
EXP10:
    .assert EXP10 = $DDCC, "EXP10 is at $DDCC."
    lda #$00
    sta DIGRT                       ; I = 0
    lda FR0
    sta FCHRFLG                     ; keep X's sign
    and #<~FP_SIGN
    sta FR0                         ; FR0 = |X|
    sec
    sbc #FP_EXPONENT_BIAS
    bmi EXP10_FRACTION              ; below 1: all fraction
    cmp #$04
    bpl EXP10_OVERFLOW              ; 100^4 or more
    ldx #<FPSCR
    ldy #>FPSCR
    jsr FST0R                       ; keep |X|
    jsr FPI                         ; I, rounded; its carry is not checked, and a failure can leave FR0+1 zero
    lda FR0
    sta DIGRT
    lda FR0+1
    bne EXP10_OVERFLOW              ; 256 or more
    jsr IFP
    jsr FMOVE                       ; FR1 = I
    ldx #<FPSCR
    ldy #>FPSCR
    jsr FLD0R
    jsr FSUB                        ; F = |X| - I
EXP10_FRACTION:
    lda #EXP_COEFFICIENT_COUNT
    ldx #<EXP_COEFFICIENTS
    ldy #>EXP_COEFFICIENTS
    jsr PLYEVL                      ; 10^(F/2)
    jsr FMOVE
    jsr FMUL                        ; squared, 10^F
    lda DIGRT
    beq EXP10_SIGN
    clc                             ; FR1 = 10^I: 100^(I/2), times 10 when I is odd
    ror A
    sta FR1
    lda #$01
    bcc EXP10_MANTISSA
    lda #$10
EXP10_MANTISSA:
    sta FR1+1
    ldx #FP_SIZE-2
    lda #$00
EXP10_CLEAR:
    sta FR1+2,x
    dex
    bpl EXP10_CLEAR
    lda FR1
    clc
    adc #FP_EXPONENT_BIAS
    bcs EXP10_OVERFLOW
    bmi EXP10_OVERFLOW              ; 100^64 or more
    sta FR1
    jsr FMUL                        ; 10^F * 10^I
EXP10_SIGN:
    lda FCHRFLG
    bpl EXP10_DONE
    jsr FMOVE                       ; X was negative: take 1 / 10^|X|
    ldx #<FP_ONE
    ldy #>FP_ONE
    jsr FLD0R
    jsr FDIV
EXP10_DONE:
    rts
EXP10_OVERFLOW:
    sec
    rts

;; The coefficients of 10^(F/2) for F from -0.5 to 1, highest power first, for <EXP10>, which squares the result.
;; See: <EXP10>, <PLYEVL>
EXP_COEFFICIENTS:
    FP_NUMBER FP_POSITIVE, -3, $17, $94, $19, $00, $00 ; 0.0000179419
    FP_NUMBER FP_POSITIVE, -3, $57, $33, $05, $00, $00 ; 0.0000573305
    FP_NUMBER FP_POSITIVE, -2, $05, $54, $76, $62, $00 ; 0.0005547662
    FP_NUMBER FP_POSITIVE, -2, $32, $19, $62, $27, $00 ; 0.0032196227
    FP_NUMBER FP_POSITIVE, -1, $01, $68, $60, $30, $36 ; 0.0168603036
    FP_NUMBER FP_POSITIVE, -1, $07, $32, $03, $27, $41 ; 0.0732032741
    FP_NUMBER FP_POSITIVE, -1, $25, $43, $34, $56, $75 ; 0.2543345675
    FP_NUMBER FP_POSITIVE, -1, $66, $27, $37, $30, $50 ; 0.6627373050
    FP_NUMBER FP_POSITIVE, 0, $01, $15, $12, $92, $55 ; 1.151292550, ln(10)/2
    FP_NUMBER FP_POSITIVE, -1, $99, $99, $99, $99, $99 ; 0.9999999999
    .assert * - EXP_COEFFICIENTS = EXP_COEFFICIENT_COUNT * FP_SIZE, "EXP10's polynomial has 10 coefficients."

;; log10(e), 0.4342944819, which turns a power of e into a power of 10 and a common logarithm into a natural one.
;; See: <EXP>, <LOG>
FP_LOG10_E:
    FP_NUMBER FP_POSITIVE, -1, $43, $42, $94, $48, $19

;; 1.0, which <EXP10> divides to take a reciprocal.
;; See: <EXP10>
FP_ONE:
    .assert FP_ONE = $DE8F, "1.0 is at $DE8F."
    FP_NUMBER FP_POSITIVE, 0, $01, $00, $00, $00, $00

;; Gives (x - c) / (x + c), for x in FR0 and the constant c at X/Y.
;;
;; <LOG> uses it with sqrt(10); with <FP_ONE>, it gives the (x - 1) / (x + 1) that brings an arctangent's argument
;; below 1, to go with <FP_PI_OVER_4> and <ATN_COEFFICIENTS>. The add's and subtract's errors are not checked.
;; In: FR0 = x, X = c's address, low byte, Y = its high byte
;; Out: FR0 = (x - c) / (x + c), carry = set when the divide is out of range
;; Uses: A, X, Y, FR1, FPTR2, FLPTR, PLYARG, FPSCR
;; See: <LOG>
FP_DIFFERENCE_OVER_SUM:
    .assert FP_DIFFERENCE_OVER_SUM = $DE95, "(x - c) / (x + c) is at $DE95."
    stx FPTR2
    sty FPTR2+1
    ldx #<PLYARG
    ldy #>PLYARG
    jsr FST0R                       ; keep x
    ldx FPTR2
    ldy FPTR2+1
    jsr FLD1R
    jsr FADD
    ldx #<FPSCR
    ldy #>FPSCR
    jsr FST0R                       ; keep x + c
    ldx #<PLYARG
    ldy #>PLYARG
    jsr FLD0R
    ldx FPTR2
    ldy FPTR2+1
    jsr FLD1R
    jsr FSUB                        ; x - c
    ldx #<FPSCR
    ldy #>FPSCR
    jsr FLD1R
    jsr FDIV                        ; (x - c) / (x + c)
    rts

;; Takes the natural logarithm of FR0.
;;
;; Takes the common logarithm, as <LOG10> describes, and divides it by log10(e).
;; In: FR0 = the number
;; Out: FR0 = its natural logarithm, carry = set for a negative number
;; Uses: A, X, Y, FR1, DIGRT, FCHRFLG, ESIGN, FPTR2, FLPTR, PLYARG, FPSCR
;; Errors: carry = set for a negative number
;; See: <LOG10>, <EXP>
LOG:
    .assert LOG = $DECD, "LOG is at $DECD."
    lda #$01                        ; natural
    bne LOG_COMMON
;; Takes the common (base 10) logarithm of FR0.
;;
;; Divides the number Z by 10^Y, the largest power of 10 not above it, leaving F from 1 to 10. With t = (F - sqrt(10))
;; / (F + sqrt(10)), log10(F) = 0.5 + t * P(t^2), where P is <LOG_COEFFICIENTS>' polynomial, and log10(Z) = Y +
;; log10(F). It also uses whatever the arithmetic routines use.
;;
;; As the manual says, zero is no error: it gives about -129.5. Unlike the manual, the code never reports an overflow;
;; it returns carry clear for any number not negative, whatever the arithmetic reported.
;; In: FR0 = the number
;; Out: FR0 = its common logarithm, carry = set for a negative number
;; Uses: A, X, Y, FR1, DIGRT, FCHRFLG, ESIGN, FPTR2, FLPTR, PLYARG, FPSCR
;; Errors: carry = set for a negative number
;; See: <LOG>, <EXP10>
LOG10:
    .assert LOG10 = $DED1, "LOG10 is at $DED1."
    lda #$00                        ; common
LOG_COMMON:
    sta FCHRFLG                     ; nonzero for the natural logarithm
    lda FR0
    bpl LOG_POSITIVE
    sec
    rts
LOG_POSITIVE:
    lda FR0
    sta FR1                         ; FR1 = 10^Y: Z's power of 100...
    sec
    sbc #FP_EXPONENT_BIAS
    asl A
    sta DIGRT                       ; Y = twice the power of 100...
    lda FR0+1
    and #$F0
    bne LOG_ODD_POWER
    lda #$01                        ; ...with a mantissa of 1
    bne LOG_POWER_MANTISSA
LOG_ODD_POWER:
    inc DIGRT                       ; ...plus 1 when Z's first byte is 10 or more
    lda #$10                        ; ...with a mantissa of 10
LOG_POWER_MANTISSA:
    sta FR1+1
    ldx #FP_SIZE-2
    lda #$00
LOG_CLEAR:
    sta FR1+2,x
    dex
    bpl LOG_CLEAR
    jsr FDIV                        ; F = Z / 10^Y
    ldx #<FP_SQRT10
    ldy #>FP_SQRT10
    jsr FP_DIFFERENCE_OVER_SUM      ; t
    ldx #<FPSCR
    ldy #>FPSCR
    jsr FST0R                       ; keep t
    jsr FMOVE
    jsr FMUL                        ; t^2
    lda #LOG_COEFFICIENT_COUNT
    ldx #<LOG_COEFFICIENTS
    ldy #>LOG_COEFFICIENTS
    jsr PLYEVL                      ; P(t^2)
    ldx #<FPSCR
    ldy #>FPSCR
    jsr FLD1R
    jsr FMUL                        ; t * P(t^2)
    ldx #<FP_HALF
    ldy #>FP_HALF
    jsr FLD1R
    jsr FADD                        ; log10(F)
    jsr FMOVE
    lda #$00                        ; Y as a number: |Y| through IFP, then its sign
    sta FR0+1
    lda DIGRT
    sta FR0
    bpl LOG_POWER
    eor #$FF
    clc
    adc #$01
    sta FR0
LOG_POWER:
    jsr IFP
    bit DIGRT
    bpl LOG_ADD_POWER
    lda #FP_SIGN
    ora FR0
    sta FR0
LOG_ADD_POWER:
    jsr FADD                        ; Y + log10(F)
    lda FCHRFLG
    beq LOG_DONE
    ldx #<FP_LOG10_E
    ldy #>FP_LOG10_E
    jsr FLD1R
    jsr FDIV                        ; ln(Z) = log10(Z) / log10(e)
LOG_DONE:
    clc
    rts

;; sqrt(10), 3.16227766, the middle of <LOG10>'s range of F, 1 to 10.
;; See: <LOG10>
FP_SQRT10:
    FP_NUMBER FP_POSITIVE, 0, $03, $16, $22, $77, $66

;; 0.5, log10(sqrt(10)), which <LOG10> adds to its polynomial's value.
;; See: <LOG10>
FP_HALF:
    FP_NUMBER FP_POSITIVE, -1, $50, $00, $00, $00, $00

;; The coefficients of P, where log10(F) = 0.5 + t * P(t^2) and t = (F - sqrt(10)) / (F + sqrt(10)), for F from 1 to
;; 10, highest power first.
;; See: <LOG10>, <PLYEVL>
LOG_COEFFICIENTS:
    FP_NUMBER FP_POSITIVE, -1, $49, $15, $57, $11, $08 ; 0.4915571108
    FP_NUMBER FP_NEGATIVE, -1, $51, $70, $49, $47, $08 ; -0.5170494708
    FP_NUMBER FP_POSITIVE, -1, $39, $20, $57, $61, $95 ; 0.3920576195
    FP_NUMBER FP_NEGATIVE, -1, $04, $39, $63, $03, $55 ; -0.0439630355
    FP_NUMBER FP_POSITIVE, -1, $10, $09, $30, $12, $64 ; 0.1009301264
    FP_NUMBER FP_POSITIVE, -1, $09, $39, $08, $04, $60 ; 0.0939080460
    FP_NUMBER FP_POSITIVE, -1, $12, $42, $58, $47, $42 ; 0.1242584742
    FP_NUMBER FP_POSITIVE, -1, $17, $37, $12, $06, $08 ; 0.1737120608
    FP_NUMBER FP_POSITIVE, -1, $28, $95, $29, $71, $17 ; 0.2895297117
    FP_NUMBER FP_POSITIVE, -1, $86, $85, $88, $96, $44 ; 0.8685889644, 2 * log10(e)
    .assert * - LOG_COEFFICIENTS = LOG_COEFFICIENT_COUNT * FP_SIZE, "LOG10's polynomial has 10 coefficients."

;; The coefficients of P, where atan(x) = x * P(x^2) for x from -1 to 1, highest power first.
;;
;; The package never reads them; Atari BASIC reads them by address for its ATN. An argument beyond 1 can be brought
;; below it with (x - 1) / (x + 1), adding <FP_PI_OVER_4>. The last is 0.9999999999, as in <EXP_COEFFICIENTS>.
;; See: <PLYEVL>, <FP_PI_OVER_4>, <FP_DIFFERENCE_OVER_SUM>
ATN_COEFFICIENTS:
    .assert ATN_COEFFICIENTS = $DFAE, "The arctangent's coefficients are at $DFAE."
    FP_NUMBER FP_POSITIVE, -2, $16, $05, $44, $49, $00 ; 0.0016054449
    FP_NUMBER FP_NEGATIVE, -2, $95, $68, $38, $45, $00 ; -0.0095683845
    FP_NUMBER FP_POSITIVE, -1, $02, $68, $79, $94, $16 ; 0.0268799416
    FP_NUMBER FP_NEGATIVE, -1, $04, $92, $78, $90, $80 ; -0.0492789080
    FP_NUMBER FP_POSITIVE, -1, $07, $03, $15, $20, $00 ; 0.0703152000
    FP_NUMBER FP_NEGATIVE, -1, $08, $92, $29, $12, $44 ; -0.0892291244
    FP_NUMBER FP_POSITIVE, -1, $11, $08, $40, $09, $11 ; 0.1108400911
    FP_NUMBER FP_NEGATIVE, -1, $14, $28, $31, $56, $04 ; -0.1428315604
    FP_NUMBER FP_POSITIVE, -1, $19, $99, $98, $77, $44 ; 0.1999987744
    FP_NUMBER FP_NEGATIVE, -1, $33, $33, $33, $31, $13 ; -0.3333333113
    FP_NUMBER FP_POSITIVE, -1, $99, $99, $99, $99, $99 ; 0.9999999999
    .assert * - ATN_COEFFICIENTS = ATN_COEFFICIENT_COUNT * FP_SIZE, "The arctangent has 11 coefficients."

;; pi/4, 0.7853981634, atan(1), for an arctangent of an argument beyond 1; the package never reads it.
;; See: <ATN_COEFFICIENTS>
FP_PI_OVER_4:
    .assert FP_PI_OVER_4 = $DFF0, "pi/4 is at $DFF0."
    FP_NUMBER FP_POSITIVE, -1, $78, $53, $98, $16, $34

; Unused to the end of the chip; nothing reads these bytes. The first three repeat the end of pi/4, as if left from
; an earlier layout of the tables; the other seven are no number and no code.
    .byte $98, $16, $34, $FC, $E0, $32, $50, $D9, $68, $11
