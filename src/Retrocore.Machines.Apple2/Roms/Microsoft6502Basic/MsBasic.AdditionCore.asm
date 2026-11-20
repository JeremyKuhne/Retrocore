;; Emits the addition and subtraction entries that can precede platform-specific code.
.macro ADD_ENTRIES

;; Adds one half to <FAC>.
;; See: <FADD>, <FHALF>
FADDH:
    lda #<FHALF
    ldy #>FHALF
    jmp FADD

;; Subtracts <FAC> from a packed number, leaving the result in <FAC>.
;; In: A = low byte of packed operand address, Y = high byte of packed operand address
;; Entry: FSUBT = subtracts <FAC> from the unpacked argument accumulator
FSUB:
    jsr CONUPK

FSUBT:
    lda FACSGN
    eor #$FF
    sta FACSGN
    eor ARGSGN
    sta ARISGN
    lda FACEXP
    jmp FADDT

.endmacro

;; Emits floating-point addition, normalization and shifting for five-byte precision.
.macro ADD_AND_NORMALIZE

FADD5:
    jsr SHIFTR
    bcc FADD4

;; Adds a packed number to <FAC>, leaving the result in <FAC>.
;;
;; The smaller mantissa is shifted to align exponents; equal signs add and opposite signs subtract. The result
;; is normalized, with low shifted bits retained in <FACOV>.
;; In: A = low byte of packed operand address, Y = high byte of packed operand address
;; Entry: FADDT = adds the unpacked argument accumulator to <FAC>, with zero set from <FACEXP> and <ARISGN>
;;   already set
;; See: <CONUPK>, <NORMAL>
FADD:
    jsr CONUPK

FADDT:
    bne *+5                         ; skip the three-byte jump when FAC is nonzero
    jmp MOVFA
    ldx FACOV
    stx OLDOV
    ldx #ARGEXP
    lda ARGEXP

;; Aligns and adds <FAC> and the argument accumulator using A as the exponent of the second operand.
;;
;; <MUL10> uses this entry after setting up the operands and their common sign.
FADDC:
    tay
    beq ZERRTS
    sec
    sbc FACEXP
    beq FADD4
    bcc FADDA                       ; the argument accumulator has the smaller exponent
    sty FACEXP
    ldy ARGSGN
    sty FACSGN
    eor #$FF
    adc #$00
    ldy #$00
    sty OLDOV
    ldx #FAC
    bne FADD1

FADDA:
    ldy #$00
    sty FACOV

FADD1:
    cmp #$F9                        ; a shift of eight or more starts with whole bytes
    bmi FADD5
    tay
    lda FACOV
    lsr 1,x
    jsr ROLSHF

;; Adds or subtracts aligned mantissas according to <ARISGN>.
FADD4:
    bit ARISGN
    bpl FADD2

; Opposite signs: subtract the smaller magnitude from the larger.
FADD3:
    ldy #FACEXP
    cpx #ARGEXP
    beq SUBIT
    ldy #ARGEXP

SUBIT:
    sec
    eor #$FF
    adc OLDOV
    sta FACOV
    lda 4,y
    sbc 4,x
    sta FACLO
    lda 3,y
    sbc 3,x
    sta FACMO
    lda 2,y
    sbc 2,x
    sta FACMOH
    lda 1,y
    sbc 1,x
    sta FACHO

;; Normalizes <FAC>, negating its mantissa and sign first if carry is clear.
;; In: carry = clear to negate <FAC> before normalization
;; See: <NORMAL>, <NEGFAC>
FADFLT:
    bcs NORMAL
    jsr NEGFAC

;; Normalizes <FAC> after addition, multiplication or division.
;;
;; Whole zero bytes are shifted first, then individual bits. An exponent underflow produces zero;
;; a carry out of addition shifts the result right and increments the exponent.
;; See: <ZEROFC>, <RNDSHF>
NORMAL:
    ldy #$00
    tya
    clc

NORM3:
    ldx FACHO
    bne NORM1
    ; Move whole zero bytes out of the high end before shifting individual bits.
    ldx FACMOH
    stx FACHO
    ldx FACMO
    stx FACMOH
    ldx FACLO
    stx FACMO
    ldx FACOV
    stx FACLO
    sty FACOV
    adc #$08
    cmp #$20
    bne NORM3

;; Sets the <FAC> exponent and sign to zero; its mantissa need not be cleared.
;; Entry: ZEROF1 = stores A in the exponent and sign, ZEROML = stores A in the sign only
ZEROFC:
    lda #$00

ZEROF1:
    sta FACEXP

ZEROML:
    sta FACSGN
    rts

FADD2:
    ; Equal signs: add the mantissas and their low guard bits.
    adc OLDOV
    sta FACOV
    lda FACLO
    adc ARGLO
    sta FACLO
    lda FACMO
    adc ARGMO
    sta FACMO
    lda FACMOH
    adc ARGMOH
    sta FACMOH
    lda FACHO
    adc ARGHO
    sta FACHO
    jmp SQUEEZ

NORM2:
    adc #$01
    asl FACOV
    rol FACLO
    rol FACMO
    rol FACMOH
    rol FACHO

NORM1:
    bpl NORM2
    sec
    sbc FACEXP
    bcs ZEROFC
    eor #$FF
    adc #$01
    sta FACEXP

SQUEEZ:
    bcc RNDRTS

;; Shifts <FAC> right after a mantissa carry and increments its exponent.
;; Errors: overflow = jumps to <OVERR> if the exponent wraps
RNDSHF:
    inc FACEXP
    beq OVERR
    ror FACHO
    ror FACMOH
    ror FACMO
    ror FACLO
    ror FACOV

RNDRTS:
    rts

;; Complements the <FAC> sign and negates its mantissa and rounding byte.
;; Entry: NEGFCH = negates only the mantissa and rounding byte
NEGFAC:
    lda FACSGN
    eor #$FF
    sta FACSGN

NEGFCH:
    lda FACHO
    eor #$FF
    sta FACHO
    lda FACMOH
    eor #$FF
    sta FACMOH
    lda FACMO
    eor #$FF
    sta FACMO
    lda FACLO
    eor #$FF
    sta FACLO
    lda FACOV
    eor #$FF
    sta FACOV
    inc FACOV
    bne INCFRT

;; Increments the <FAC> mantissa, propagating a carry from its low byte.
;; See: <ROUND>
INCFAC:
    inc FACLO
    bne INCFRT
    inc FACMO
    bne INCFRT
    inc FACMOH
    bne INCFRT
    inc FACHO

INCFRT:
    rts

;; Reports the floating-point overflow error through <ERROR>.
OVERR:
    ldx #ERROV
    jmp ERROR

; Mantissa negation, overflow, and the shared arithmetic shifter.

;; Shifts the multiplication result right by a byte, then continues through <SHIFTR>.
MULSHF:
    ldx #(RESHO-1)

SHFTR2:
    ldy 4,x
    sty FACOV
    ldy 3,x
    sty 4,x
    ldy 2,x
    sty 3,x
    ldy 1,x
    sty 2,x
    ldy BITS
    sty 1,x

;; Shifts the four bytes at X+1 through X+4 right by the negative count in A.
;;
;; Whole-byte shifts fill from <BITS>; bit shifts preserve the high byte's sign and shift low bits into A.
;; In: X = byte before the high byte, A = negative shift count, carry = clear
;; Out: A = shifted-out low bits, carry = clear
;; Entry: ROLSHF = rotates the lower three bytes and A with the carry supplied by the caller
SHIFTR:
    adc #$08
    bmi SHFTR2
    beq SHFTR2
    sbc #$08
    tay
    lda FACOV
    bcs SHFTRT

SHFTR3:
    asl 1,x
    bcc SHFTR4
    inc 1,x

SHFTR4:
    ror 1,x
    ror 1,x

ROLSHF:
    ror 2,x
    ror 3,x
    ror 4,x
    ror a

SHFTR7:
    iny
    bne SHFTR3

SHFTRT:
    clc
    rts

.endmacro
