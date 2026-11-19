;; APPLE II APPLESOFT SIGNS, COMPARISON AND DECIMAL INPUT
;;
;; Sign and comparison return signed byte results; integer conversion and decimal input leave results in <FAC>.
;; <FIN> accumulates digits, tracks the decimal point and scales by a decimal exponent.
;;
;; Part of AppleSoft.asm; it follows AppleSoft.FloatMovement.asm.

; Sign and integer-to-floating-point conversion.

;; Returns the sign of <FAC> as -1, 0 or 1 in A.
;; Out: A = $FF for negative, 0 for zero or 1 for positive
SIGN:
    lda     FACEXP
    beq     SIGNRT

FCSIGN:
    lda     FACSGN

FCOMPS:
    rol     a
    lda     #$FF
    bcs     SIGNRT
    lda     #$01

SIGNRT:
    rts

;; Replaces <FAC> with its sign as a floating-point number.
;; See: <SIGN>, <FLOAT>
SGN:
    jsr     SIGN

;; Converts the signed byte in A to floating point in <FAC>.
;; In: A = signed byte
;; See: <FLOATS>
FLOAT:
    sta     FACHO
    lda     #$00
    sta     FACMOH
    ldx     #$88

;; Converts the signed 16-bit integer in <FACHO> and <FACMOH> to floating point.
;;
;; The lower two mantissa bytes are cleared and the signed value is normalized using X as the initial exponent.
;; In: FACHO = high byte of integer, FACMOH = low byte of integer, X = initial biased exponent
;; Entry: FLOATC = takes the sign complement in carry, FLOATB = uses A for the sign and rounding byte
FLOATS:
    lda     FACHO
    eor     #$FF
    rol     a

FLOATC:
    lda     #$00
    sta     FACLO
    sta     FACMO

FLOATB:
    stx     FACEXP
    sta     FACOV
    sta     FACSGN
    jmp     FADFLT

;; Makes <FAC> nonnegative by clearing the high bit of its sign byte.
ABS:
    lsr     FACSGN
    rts

; Comparison and floating-point-to-integer conversion.

;; Compares <FAC> to a packed number and returns an ordering byte in A.
;;
;; After the exponent and upper mantissa bytes match, it subtracts <FACLO> and bit 7 of <FACOV> from the packed
;; low byte. The zero result is tested without checking the borrow: if the packed low byte is $00, <FACLO> is $FF
;; and bit 7 of <FACOV> is set, this last subtraction wraps to zero and the routine reports equality.
;; In: A = low byte of packed operand address, Y = high byte of packed operand address
;; Out: A = normally 1 if FAC is greater, 0 if equal, $FF if less
FCOMP:
    sta     INDEX2

FCOMPN:
    sty     INDEX2+1
    ldy     #$00
    lda     (INDEX2),y
    iny
    tax
    beq     SIGN
    lda     (INDEX2),y
    eor     FACSGN
    bmi     FCSIGN

FOUTCP:
    cpx     FACEXP
    bne     FCOMPC
    lda     (INDEX2),y
    ora     #$80
    cmp     FACHO
    bne     FCOMPC
    iny
    lda     (INDEX2),y
    cmp     FACMOH
    bne     FCOMPC
    iny
    lda     (INDEX2),y
    cmp     FACMO
    bne     FCOMPC
    iny
    lda     #$7F
    cmp     FACOV
    lda     (INDEX2),y
    sbc     FACLO
    beq     QINTRT

FCOMPC:
    lda     FACSGN
    bcc     FCOMPD
    eor     #$FF

FCOMPD:
    jmp     FCOMPS

;; Aligns <FAC>'s mantissa to a four-byte integer in <FACHO> through <FACLO>.
;;
;; A negative value first has its mantissa and guard byte negated by <NEGFCH>; the subsequent right shifts use
;; sign extension, with <BITS> supplying whole-byte fill. The exponent and sign are not converted into an integer
;; representation. <INT> uses this intermediate integer to construct the floating-point greatest integer.
;; Magnitudes outside the signed four-byte range are not checked.
;; See: <INT>, <SHIFTR>
QINT:
    lda     FACEXP
    beq     CLRFAC
    sec
    sbc     #$A0
    bit     FACSGN
    bpl     QISHFT
    tax
    lda     #$FF
    sta     BITS
    jsr     NEGFCH
    txa

QISHFT:
    ldx     #FAC
    cmp     #$F9
    bpl     QINT1
    jsr     SHIFTR
    sty     BITS

QINTRT:
    rts

QINT1:
    tay
    lda     FACSGN
    and     #$80
    lsr     FACHO                   ; restore the sign bit before shifting the remaining bytes
    ora     FACHO
    sta     FACHO
    jsr     ROLSHF
    sty     BITS
    rts

;; Replaces <FAC> with the greatest integer not greater than <FAC>.
;;
;; For exponents below $A0, <QINT> aligns the signed integer and this routine normalizes it back to floating point;
;; the integer's low byte is also saved in <INTEGR>. Values with an exponent at least $A0 already have no
;; fractional bits at <FAC> precision.
;; See: <QINT>
INT:
    lda     FACEXP
    cmp     #$A0
    bcs     INTRTS
    jsr     QINT
    sty     FACOV
    lda     FACSGN
    sty     FACSGN
    eor     #$80
    rol     a
    lda     #$A0
    sta     FACEXP
    lda     FACLO
    sta     INTEGR
    jmp     FADFLT

;; Clears the <FAC> mantissa and Y when the exponent is zero.
CLRFAC:
    sta     FACHO
    sta     FACMOH
    sta     FACMO
    sta     FACLO
    tay

INTRTS:
    rts

; Decimal text input.

;; Reads a decimal number from BASIC text into <FAC>.
;;
;; Digits are accumulated by multiplying by ten and adding; <DECCNT> counts fractional digits and <TENEXP>
;; holds the decimal exponent. An optional exponent accepts either ASCII signs or BASIC sign tokens. The final
;; scale is applied by <MUL10> or <DIV10>, then the original sign is applied.
;; In: A = first character, TXTPTR = address of first character, carry = clear if it is a digit
;; See: <CHRGET>, <FINLOG>
FIN:
    ldy     #$00
    ldx     #$0A

FINZLP:
    ; Clear the decimal counters, sign flags and FAC workspace without changing carry.
    sty     DECCNT,x
    dex
    bpl     FINZLP
    bcc     FINDGQ
    cmp     #'-'
    bne     QPLUS
    stx     SGNFLG
    beq     FINC

QPLUS:
    cmp     #'+'
    bne     FIN1

FINC:
    jsr     CHRGET

FINDGQ:
    bcc     FINDIG

FIN1:
    cmp     #'.'
    beq     FINDP
    cmp     #'E'
    bne     FINE
    jsr     CHRGET
    bcc     FNEDG1
    cmp     #MINUTK
    beq     FINEC1
    cmp     #'-'
    beq     FINEC1
    cmp     #PLUSTK
    beq     FINEC
    cmp     #'+'
    beq     FINEC
    bne     FINEC2

FINEC1:
    ror     EXPSGN

FINEC:
    jsr     CHRGET

FNEDG1:
    bcc     FINEDG

FINEC2:
    bit     EXPSGN
    bpl     FINE
    lda     #$00
    sec
    sbc     TENEXP
    jmp     FINE1

FINDP:
    ror     DPTFLG
    bit     DPTFLG
    bvc     FINC

FINE:
    lda     TENEXP

FINE1:
    sec
    sbc     DECCNT                  ; account for digits accumulated after the decimal point
    sta     TENEXP
    beq     FINQNG
    bpl     FINMUL

FINDIV:
    jsr     DIV10
    inc     TENEXP
    bne     FINDIV
    beq     FINQNG

FINMUL:
    jsr     MUL10
    dec     TENEXP
    bne     FINMUL

FINQNG:
    lda     SGNFLG
    bmi     NEGXQS
    rts

NEGXQS:
    jmp     NEGOP

FINDIG:
    pha
    bit     DPTFLG
    bpl     FINDG1
    inc     DECCNT

FINDG1:
    jsr     MUL10
    pla
    sec
    sbc     #'0'
    jsr     FINLOG
    jmp     FINC

;; Adds the signed byte in A to <FAC>, converting it to floating point first.
;; In: A = signed byte
FINLOG:
    pha
    jsr     MOVAF
    pla
    jsr     FLOAT
    lda     ARGSGN
    eor     FACSGN
    sta     ARISGN
    ldx     FACEXP
    jmp     FADDT

;; Accumulates a decimal exponent digit into <TENEXP>.
;;
;; When the accumulated exponent is already at least ten, a positive exponent signals overflow and a negative
;; exponent is set to 100 before scanning continues.
FINEDG:
    lda     TENEXP
    cmp     #$0A
    bcc     MLEX10
    lda     #$64
    bit     EXPSGN
    bmi     MLEXMI
    jmp     OVERR

MLEX10:
    asl     a
    asl     a
    clc
    adc     TENEXP
    asl     a
    clc
    ldy     #$00
    adc     (TXTPTR),y
    sec
    sbc     #'0'

MLEXMI:
    sta     TENEXP
    jmp     FINEC
