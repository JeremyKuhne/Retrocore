; B3MATHK: the floating-point package's addition and subtraction, normalizing, negating, and the shifts the other
; operations share.
;
; A real variable is four bytes: the exponent, biased by $80, with 0 meaning the number is zero whatever the other
; bytes hold; then the mantissa, high byte first, with the sign in the top bit of its first byte. The mantissa is a
; fraction with the binary point to its left, and its leading 1, which the sign bit stands in for, is implied. The
; bytes 84 A0 00 00 are -10: $84 is an exponent of 4, and the mantissa is binary .101, 0.625, times 16.
;
; BASIC's own constants and its temporaries in its own bank have a fifth byte, more mantissa; the routines that load
; and store reals take a bank of 0 to mean the five-byte form.
;
; The FAC and ARG hold reals unpacked: the exponent, four mantissa bytes with the leading 1 present, then the sign
; byte, 0 for positive and $FF for negative (only its top bit counts). FACOV, below FACLO, holds the bits that are
; rounded off; ARISGN holds the sign of a product or quotient, ARG's sign exclusive-ored with the FAC's. A
; two-operand routine takes the left operand in ARG and the right in the FAC, and leaves the result in the FAC; the
; ones without T at the end of their names unpack the left operand from memory first, with <CONUPK>.
;
; Names follow Apple's Business BASIC 1.3 listing.

; ---------------------------------------------------------------------------------------------------------------------
; Addition and subtraction
; ---------------------------------------------------------------------------------------------------------------------

;; Adds a half to the FAC.
;; See: <FADD>, <FHALF>
FADDH:
    lda #<(FHALF)
    ldy #>(FHALF)
    jmp FADD

;; Subtracts the <FAC> from the five-byte real at A, Y: the FAC becomes that number less the FAC.
;; In: A, Y = the real's address, in BASIC's own bank
;; See: <FSUBT>, <CONUPK>
FSUB:
    ldx #0
    jsr CONUPK

;; Subtracts the <FAC> from <ARG>, into the FAC, by negating the FAC and adding.
;; See: <FADDT>
FSUBT:
    lda FACSGN
    eor #$FF
    sta FACSGN
    eor ARGSGN
    sta ARISGN
    lda FACEXP                              ; with zero set for a zero FAC, as FADDT wants
    jmp FADDT

;; Shifts the smaller operand right by more than seven bits, a byte at a time first, then adds.
FADD5:
    jsr SHIFTR
    bcc FADD4                               ; always

;; Adds the five-byte real at A, Y to the FAC.
;; In: A, Y = the real's address, in BASIC's own bank
;; See: <FADDT>, <CONUPK>
FADD:
    ldx #0
    jsr CONUPK

;; Adds <ARG> to the <FAC>: lines up the binary points by shifting the smaller number right, then adds the mantissas, or
;; subtracts them when the signs differ, and normalizes.
;; In: A = FACEXP, zero = set for a zero FAC, ARISGN = ARG's sign exclusive-ored with the FAC's
;; See: <FADDC>, <NORMAL>
FADDT:
    bne *+5
    jmp MOVFA                               ; a zero FAC: the sum is ARG
    ldx FACOV
    stx OLDOV
    ldx #ARGEXP                             ; shift ARG, unless the FAC is the smaller
    lda ARGEXP

;; Adds <ARG> to the <FAC>, taking A as ARG's exponent; a zero exponent leaves the FAC as it is.
;;
;; <MUL10> passes an exponent 2 above the FAC's, so the FAC, shifted, is added as four times itself.
;; In: A = ARG's exponent
;; See: <MUL10>
FADDC:
    tay
    bne *+3
    rts
    sec
    sbc FACEXP
    beq FADD4                               ; the same exponent: no shift
    bcc FADDA                               ; ARG is the smaller
    sty FACEXP                              ; ARG is the larger: its exponent and sign win
    ldy ARGSGN
    sty FACSGN
    eor #$FF                                ; the count, negated
    adc #0
    ldy #0
    sty OLDOV
    ldx #FAC                                ; and the FAC is the one to shift
    bne FADD1

;; Clears <FACOV>, for shifting ARG.
FADDA:
    ldy #0
    sty FACOV

;; Shifts the smaller operand, at X, right by minus A bits.
FADD1:
    cmp #$100-7                             ; more than 7 bits: shift bytes first
    bmi FADD5
    tay
    lda FACOV
    lsr 1,X                                 ; the top bit becomes 0
    jsr ROLSHF

;; Adds the mantissas when the signs match, and subtracts the smaller from the larger when they differ.
;; In: A = the shifted operand's rounding bits
FADD4:
    bit ARISGN
    bpl FADD2                               ; the same signs: add
    ldy #FACEXP                             ; the carry is clear
    cpx #ARGEXP
    beq SUBIT
    ldy #ARGEXP

;; Subtracts the shifted operand, at X, from the other, at Y, into the FAC.
SUBIT:
    sec
    eor #$FF
    adc OLDOV
    sta FACOV
    lda 3+1,Y
    sbc 3+1,X
    sta FACLO
    lda 2+1,Y
    sbc 2+1,X
    sta FACMO
    lda 2,Y
    sbc 2,X
    sta FACMOH
    lda 1,Y
    sbc 1,X
    sta FACHO

;; Negates the <FAC> when the carry is clear, then normalizes it.
;; In: carry = clear to negate it
;; See: <NEGFAC>, <NORMAL>
FADFLT:
    bcs NORMAL
    jsr NEGFAC

;; Normalizes the <FAC>: shifts the mantissa left until its top bit is set, lowering the exponent to match, a byte at a
;; time first. A FAC that is zero, or too small for the exponent, becomes zero.
;; See: <ZEROFC>
NORMAL:
    ldy #0
    tya
    clc

;; Shifts the mantissa left a byte while its high byte is zero, counting the bits in A.
NORM3:
    ldx FACHO
    bne NORM1
    ldx FACHO+1
    stx FACHO
    ldx FACMOH+1
    stx FACMOH
    ldx FACMO+1
    stx FACMO
    ldx FACOV
    stx FACLO
    sty FACOV
    adc #08
    cmp #$20                                ; all four bytes zero
    bne NORM3

;; Makes the <FAC> zero, positive.
ZEROFC:
    lda #0

;; Sets <FACEXP> and <FACSGN> to A.
ZEROF1:
    sta FACEXP

;; Sets <FACSGN> to A.
ZEROML:
    sta FACSGN
    rts

;; Adds the mantissas, the rounding bits too, then takes a carry out of the top into the exponent.
;; See: <SQUEEZ>
FADD2:
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

;; Shifts the mantissa left a bit, counting it in A.
NORM2:
    adc #1
    asl FACOV
    rol FACLO
    rol FACMO
    rol FACMOH
    rol FACHO

;; Shifts left until the top bit is set, then takes the count of bits from the exponent.
NORM1:
    bpl NORM2
    sec
    sbc FACEXP
    bcs ZEROFC                              ; below the smallest exponent: zero
    eor #$FF
    adc #1
    sta FACEXP

;; Takes a carry out of the mantissa's top: shifts it back in from the left and adds one to the exponent.
;; In: carry = set for a carry
SQUEEZ:
    bcc RNDRTS

;; Shifts the carry into the mantissa from the left and adds one to the exponent, ending the statement with OVERFLOW
;; when the exponent passes $FF.
RNDSHF:
    inc FACEXP
    beq OVERR
    ror FACHO
    ror FACMOH
    ror FACMO
    ror FACLO
    ror FACOV

;; An RTS for the addition.
RNDRTS:
    rts

;; Negates the <FAC>: its sign, and the mantissa and rounding bits as a two's complement.
;; Keeps: X, Y
NEGFAC:
    lda FACSGN
    eor #255
    sta FACSGN

;; Negates the <FAC>'s mantissa and rounding bits as a two's complement, leaving its sign.
;; Uses: DPTFLG
;; Keeps: X, Y
NEGFCH:
    stx DPTFLG
    ldx #3

;; Complements a byte of the mantissa, for <NEGFCH>.
NEGFCH1:
    lda FACHO,X
    eor #$FF
    sta FACHO,X
    dex
    bpl NEGFCH1
    ldx DPTFLG
    lda FACOV
    eor #255
    sta FACOV
    inc FACOV
    bne INCFRT                              ; no carry into the mantissa

;; Adds one to the <FAC>'s mantissa.
;; Out: zero = set when the mantissa carried out of its top
INCFAC:
    inc FACLO
    bne INCFRT
    inc FACMO
    bne INCFRT
    inc FACMOH
    bne INCFRT
    inc FACHO

;; An RTS for <INCFAC>.
INCFRT:
    rts

;; Ends the statement with OVERFLOW.
OVERR:
    ldx #ERROV
    jmp ERROR

; ---------------------------------------------------------------------------------------------------------------------
; Shifting right
; ---------------------------------------------------------------------------------------------------------------------

;; Shifts the multiplication's result, <RES>, right a byte, for a multiplier byte of zero.
;; See: <FMULTT>
MULSHF:
    ldx #RESHO-1
    ldy #0
    sty BITS

;; Shifts the mantissa at X+1 right a byte, filling with <BITS>, the low byte going to FACOV.
SHFTR2:
    ldy 3+1,X
    sty FACOV
    ldy 3,X
    sty 4,X
    ldy 2,X
    sty 3,X
    ldy 1,X
    sty 2,X
    ldy BITS
    sty 1,X

;; Shifts whole bytes while eight or more bits are left, then the rest a bit at a time.
SHFTR0:
    adc #8
    bmi SHFTR2
    beq SHFTR2
    sbc #8                                  ; works with the carry either way
    tay
    lda FACOV
    bcs SHFTRT                              ; no bits left

;; Shifts the high byte right a bit, copying its top bit, so that a negative number from <QINT> stays negative.
SHFTR3:
    asl 1,X
    bcc SHFTR4
    inc 1,X

SHFTR4:
    ror 1,X
    ror 1,X

;; Shifts the rest of the mantissa at X+2 right a bit, into the rounding bits in A, and loops for each count in Y.
;; In: X = the address before the mantissa, Y = minus the bits left, A = the rounding bits
ROLSHF:
    ror 2,X
    ror 3,X
    ror 4,X
    ror
    iny
    bne SHFTR3

;; Ends the shift with the carry clear.
;; Out: A = the bits shifted out, carry = clear
SHFTRT:
    clc
    rts

;; Shifts the mantissa of the number at X right by minus A bits, filling with zeros; the bits shifted out end up in A.
;; In: X = the number's exponent (FAC, ARGEXP or before RES), A = minus the count
;; Out: A = the bits shifted out, carry = clear
;; See: <SHFTR1>
SHIFTR:
    ldy #0
    sty BITS

;; Shifts as <SHIFTR> does, filling with <BITS>: <QINT> fills a negative number with ones.
SHFTR1:
    jmp SHFTR0
