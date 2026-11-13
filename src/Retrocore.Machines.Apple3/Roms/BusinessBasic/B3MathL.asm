; B3MATHL: the floating-point package's LOG, multiplication and division, the routines that move reals between the
; FAC, ARG and memory, rounding, SGN and ABS, comparison, and the start of QINT.
;
; The formats are described in B3MathK.asm. The constants here are five-byte reals in BASIC's own bank.
;
; Names follow Apple's Business BASIC 1.3 listing.

; ---------------------------------------------------------------------------------------------------------------------
; LOG
; ---------------------------------------------------------------------------------------------------------------------

;; 1.0.
FONE:
    .byte $81
    .byte 000
    .byte 000
    .byte 000
    .byte 0

;; The polynomial <LOG> uses for the base-2 logarithm of its fraction, in odd powers: the count of terms less one, then
;; the coefficients, highest power first: 0.43425594188, 0.57658454134, 0.96180075921 and 2.8853900728.
;; See: <POLYX>
LOGCN2:
    .byte 3
    .byte $7F                               ; 0.43425594188
    .byte $5E
    .byte $56
    .byte $CB
    .byte $79
    .byte $80                               ; 0.57658454134
    .byte $13
    .byte $9B
    .byte $0B
    .byte $64
    .byte $80                               ; 0.96180075921
    .byte $76
    .byte $38
    .byte $93
    .byte $16
    .byte $82                               ; 2.8853900728
    .byte $38
    .byte $AA
    .byte $3B
    .byte $20

;; The square root of 0.5.
SQR0_5:
    .byte $80
    .byte $35
    .byte $04
    .byte $F3
    .byte $34

;; The square root of 2.
SQR2_0:
    .byte $81
    .byte $35
    .byte $04
    .byte $F3
    .byte $34

;; -0.5.
NEGHLF:
    .byte $80
    .byte $80
    .byte 000
    .byte 000
    .byte 0

;; The natural logarithm of 2.
LOG2:
    .byte $80
    .byte $31
    .byte $72
    .byte $17
    .byte $F8

;; Gives LOG, the natural logarithm of the FAC.
;;
;; For a <FAC> of f times 2^n, with f from 0.5 to 1, it works out the base-2 logarithm of f from a polynomial in
;; (f - SQR(0.5)) / (f + SQR(0.5)), adds n and multiplies by the logarithm of 2. A FAC of zero or less is an illegal
;; quantity.
;; See: <LOGCN2>, <POLYX>, <FINLOG>
LOG:
    jsr SIGN
    beq LOGERR
    bpl LOG1

;; Ends the statement with ILLEGAL QUANTITY.
LOGERR:
    jmp FCERR

;; Takes the logarithm of a positive <FAC>, for <LOG>.
LOG1:
    lda FACEXP
    sbc #$7F                                ; the carry is clear: less $80, the bias
    pha                                     ; n
    lda #$80
    sta FACEXP                              ; f, from 0.5 to 1
    lda #<(SQR0_5)
    ldy #>(SQR0_5)
    jsr FADD
    lda #<(SQR2_0)
    ldy #>(SQR2_0)
    jsr FDIV
    lda #<(FONE)
    ldy #>(FONE)
    jsr FSUB                                ; 1 - SQR(2) / (f + SQR(0.5))
    lda #<(LOGCN2)
    ldy #>(LOGCN2)
    jsr POLYX
    lda #<(NEGHLF)
    ldy #>(NEGHLF)
    jsr FADD
    pla
    jsr FINLOG                              ; add n
    lda #<(LOG2)
    ldy #>(LOG2)
    ldx #SQR0B                              ; left over: FMULT sets X itself

; ---------------------------------------------------------------------------------------------------------------------
; Multiplication
; ---------------------------------------------------------------------------------------------------------------------

;; Multiplies the <FAC> by the five-byte real at A, Y.
;; In: A, Y = the real's address, in BASIC's own bank
;; See: <FMULTT>, <CONUPK>
FMULT:
    ldx #0
    jsr CONUPK

;; Multiplies the <FAC> by <ARG>, into the FAC: ARG's mantissa times each byte of the FAC's, the rounding byte first,
;; summed in RES.
;; In: A = FACEXP, zero = set for a zero FAC, ARISGN = the product's sign
;; See: <MULDIV>, <MLTPLY>, <MOVFR>
FMULTT:
    bne *+5
    jmp MULTRT                              ; a zero FAC is the product
    jsr MULDIV
    lda #0
    sta RESHO
    sta RESMOH
    sta RESMO
    sta RESLO
    lda FACOV
    jsr MLTPLY
    lda FACLO
    jsr MLTPLY
    lda FACMO
    jsr MLTPLY
    lda FACMOH
    jsr MLTPLY
    lda FACHO
    jsr MLTPL1
    jmp MOVFR

;; Adds <ARG> times the multiplier byte in A into <RES>, shifting RES right a bit for each of its bits; a zero byte just
;; shifts RES a byte.
;; In: A = the multiplier byte
;; See: <MULSHF>
MLTPLY:
    bne *+5
    jmp MULSHF

;; Multiplies by a non-zero byte, with a marker bit above it to count the eight bits.
MLTPL1:
    lsr
    ora #$80

;; Adds <ARG> to <RES> when the bit shifted out is set.
;; In: carry = the bit, A = the bits left
MLTPL2:
    tay
    bcc MLTPL3
    clc
    lda RESLO
    adc ARGLO
    sta RESLO
    lda RESMO
    adc ARGMO
    sta RESMO
    lda RESMOH
    adc ARGMOH
    sta RESMOH
    lda RESHO
    adc ARGHO
    sta RESHO

;; Shifts <RES> right a bit, into <FACOV>, and goes on while bits are left.
MLTPL3:
    ror RESHO
    ror RESMOH
    ror RESMO
    ror RESLO
    ror FACOV
    tya
    lsr
    bne MLTPL2

;; An RTS for the multiplication.
MULTRT:
    rts

; ---------------------------------------------------------------------------------------------------------------------
; Unpacking and exponents
; ---------------------------------------------------------------------------------------------------------------------

;; Unpacks a real from memory into <ARG>: five bytes from BASIC's own bank, or a variable's four from another.
;; In: A, Y = the real's address, X = its bank, 0 for BASIC's own
;; Out: ARG = the real, ARISGN = ARG's sign exclusive-ored with the FAC's, A = FACEXP, zero = set for a zero FAC
;; Uses: INDEX1
CONUPK:
    sta INDEX1
    stx INDEX1B
    sty INDEX1+1
    ldy #3+1
    lda (INDEX1),Y
    cpx #0
    beq *+4
    lda #0                                  ; a variable: no fifth byte
    sta ARGLO
    dey
    lda (INDEX1),Y
    sta ARGMO
    dey
    lda (INDEX1),Y
    sta ARGMOH
    dey
    lda (INDEX1),Y
    sta ARGSGN                              ; the sign is the top bit
    eor FACSGN
    sta ARISGN
    lda ARGSGN
    ora #$80                                ; the implied 1
    sta ARGHO
    dey
    lda (INDEX1),Y
    sta ARGEXP
    lda FACEXP
    rts

;; Adds <ARG>'s exponent to the <FAC>'s for a multiplication or division, and sets the result's sign.
;;
;; A result too small to hold makes the FAC zero and returns from the routine that called <MULDIV>; one too large ends
;; the statement with OVERFLOW.
;; Out: FACEXP = the sum, less the bias, FACSGN = ARISGN
;; See: <MLDEXP>
MULDIV:
    lda ARGEXP

;; Adds the exponent in A to the <FAC>'s, as <MULDIV> does.
;; In: A = the exponent
MLDEXP:
    beq ZEREMV                              ; times zero
    clc
    adc FACEXP
    bcc TRYOFF
    bmi GOOVER                              ; past $17F: too large
    clc
    .byte 44                                ; BIT abs, which skips TRYOFF's BPL

;; Takes a sum with no carry: below $80 is too small.
TRYOFF:
    bpl ZEREMV
    adc #$80                                ; the bias
    sta FACEXP
    bne *+5
    jmp ZEROML
    lda ARISGN
    sta FACSGN
    rts

;; For a result whose exponent is out of range: too large when the <FAC> is positive, and zero when it is negative.
;; See: <EXP>
MLDVEX:
    lda FACSGN
    eor #$FF
    bmi GOOVER

;; Makes the <FAC> zero and returns from the routine that called the exponent check.
ZEREMV:
    pla
    pla
    jmp ZEROFC

;; Ends the statement with OVERFLOW.
GOOVER:
    jmp OVERR

;; Multiplies the <FAC> by 10: four times itself, plus itself, doubled.
;; Out: ARG = the FAC as it was, rounded
MUL10:
    jsr MOVAF
    tax
    beq MUL10R                              ; zero stays zero
    clc
    adc #2                                  ; four times
    bcs GOOVER
    ldx #0
    stx ARISGN
    jsr FADDC                               ; plus itself
    inc FACEXP                              ; doubled
    beq GOOVER

;; An RTS for <MUL10>.
MUL10R:
    rts

; ---------------------------------------------------------------------------------------------------------------------
; Division
; ---------------------------------------------------------------------------------------------------------------------

;; 10.0.
TEN_C:
    .byte $84
    .byte $20
    .byte 000
    .byte 000
    .byte 0

;; Divides the <FAC> by 10.
;;
;; The result is always positive: <FIN>, which uses it, sets the sign afterward.
DIV10:
    jsr MOVAF
    lda #<(TEN_C)
    ldy #>(TEN_C)
    ldx #0                                  ; the quotient's sign

;; Divides <ARG> by the five-byte real at A, Y, giving the quotient the sign in X.
;; In: A, Y = the divisor's address, X = the quotient's sign
FDIVF:
    stx ARISGN
    ldx #TEN_CB
    jsr MOVFM
    jmp FDIVT

;; Divides the five-byte real at A, Y by the <FAC>, into the FAC.
;; In: A, Y = the real's address, in BASIC's own bank
;; See: <FDIVT>, <CONUPK>
FDIV:
    ldx #0
    jsr CONUPK

;; Divides <ARG> by the <FAC>, into the FAC, a bit of the quotient at a time; a zero FAC ends the statement with
;; DIVISION BY ZERO.
;; In: A = FACEXP, zero = set for a zero FAC, ARISGN = the quotient's sign
;; See: <MULDIV>, <MOVFR>
FDIVT:
    bne NO0ERR
    jmp DV0ERR

;; Divides by a <FAC> that is not zero, for <FDIVT>.
NO0ERR:
    jsr ROUND
    lda #0                                  ; negate the FAC's exponent, so MULDIV subtracts it
    sec
    sbc FACEXP
    sta FACEXP
    jsr MULDIV
    inc FACEXP
    beq GOOVER
    ldx #$100-3-1                           ; RES's bytes, from RESHO
    lda #1                                  ; a marker bit, to count eight bits

;; Compares <ARG>'s mantissa with the <FAC>'s, the divisor.
DIVIDE:
    ldy ARGHO
    cpy FACHO
    bne SAVQUO
    ldy ARGMOH
    cpy FACMOH
    bne SAVQUO
    ldy ARGMO
    cpy FACMO
    bne SAVQUO
    ldy ARGLO
    cpy FACLO

;; Shifts the comparison's result, as the next bit of the quotient, into A; each full byte goes to <RES>, and the last
;; two bits to FACOV.
;; In: carry = set when the divisor goes into ARG
SAVQUO:
    php
    rol
    bcc QSHFT                               ; the byte is not full yet
    inx
    sta RESLO,X
    beq LD100                               ; RESLO is done: two more bits
    bpl DIVNRM                              ; the two more bits are done
    lda #1

;; Subtracts the divisor when it went into <ARG>, then shifts ARG left a bit.
QSHFT:
    plp
    bcs DIVSUB

;; Shifts <ARG> left a bit, then compares again; a bit carried out of ARG's top means the divisor goes in.
SHFARG:
    asl ARGLO
    rol ARGMO
    rol ARGMOH
    rol ARGHO
    bcs SAVQUO
    bmi DIVIDE
    bpl SAVQUO

;; Subtracts the divisor from ARG.
;; In: carry = set
DIVSUB:
    tay
    lda ARGLO
    sbc FACLO
    sta ARGLO
    lda ARGMO
    sbc FACMO
    sta ARGMO
    lda ARGMOH
    sbc FACMOH
    sta ARGMOH
    lda ARGHO
    sbc FACHO
    sta ARGHO
    tya
    jmp SHFARG

;; Sets the marker bit for the last two bits of the quotient.
LD100:
    lda #$40
    bne QSHFT                               ; always

;; Puts the last two bits of the quotient at the top of <FACOV>, then moves the quotient into the FAC.
DIVNRM:
    ror
    ror
    ror
    and #$C0
    sta FACOV
    plp
    jmp MOVFR

;; Ends the statement with DIVISION BY ZERO.
DV0ERR:
    ldx #ERRDV0
    jmp ERROR

; ---------------------------------------------------------------------------------------------------------------------
; Moving reals
; ---------------------------------------------------------------------------------------------------------------------

;; Moves the result of a multiplication or division, <RES>, into the <FAC>'s mantissa and normalizes it.
;; See: <NORMAL>
MOVFR:
    lda RESHO
    sta FACHO
    lda RESMOH
    sta FACMOH
    lda RESMO
    sta FACMO
    lda RESLO
    sta FACLO
    jmp NORMAL

;; Unpacks a real from memory into the <FAC>: five bytes from BASIC's own bank, or a variable's four from another.
;; In: A, Y = the real's address, X = its bank, 0 for BASIC's own
;; Out: A = FACEXP, zero = set for a zero FAC, FACOV = 0, Y = 0
;; Uses: INDEX1
MOVFM:
    sta INDEX1
    stx INDEXB
    sty INDEX1+1
    ldy #4
    lda #0
    cpx #0
    bne *+4                                 ; a variable: no fifth byte
    lda (INDEX),Y
    sta FACLO
    dey
    lda (INDEX1),Y
    sta FACMO
    dey
    lda (INDEX1),Y
    sta FACMOH
    dey
    lda (INDEX1),Y
    sta FACSGN                              ; the sign is the top bit
    ora #$80                                ; the implied 1
    sta FACHO
    dey
    lda (INDEX1),Y
    sta FACEXP
    sty FACOV
    rts

;; Packs the <FAC> into <TEMPF2>, five bytes.
;; See: <MOVMF>
MOV2F:
    ldx #TEMPF2
    .byte 44                                ; BIT abs, which skips MOV1F's LDX

;; Packs the <FAC> into <TEMPF1>, five bytes.
;; See: <MOVMF>
MOV1F:
    ldx #TEMPF1
    ldy #0
    tya
    beq MOVMF                               ; always

;; Packs the <FAC> into the variable <FORPNT> points to.
;; See: <MOVMF>
MOVVF:
    ldx FORPNT
    lda FORPNTB
    ldy FORPNT+1

;; Rounds the <FAC> and packs it into memory: five bytes in BASIC's own bank, or a variable's four, rounded to three
;; mantissa bytes, in another.
;; In: X, Y = the address, A = the bank, 0 for BASIC's own
;; Out: Y = 0, FACOV = 0
;; Uses: INDEX1
;; See: <ROUNDER>
MOVMF:
    stx INDEX1
    sty INDEX1+1
    sta INDEX1B

;; Stores the <FAC>'s five or four bytes, for <MOVMF>.
FOURBYT:
    ldy #4
    tax
    bne FURBYT                              ; a variable
    jsr ROUND
    lda FACLO
    sta (INDEX),Y                           ; the fifth byte
    bne *+5                                 ; FURBYT's rounding is not needed

;; Rounds the <FAC> to a variable's three mantissa bytes, then stores the first four bytes.
FURBYT:
    jsr ROUNDER
    dey
    lda FACMO
    sta (INDEX),Y
    dey
    lda FACMOH
    sta (INDEX),Y
    dey
    lda FACSGN                              ; the sign, in place of the implied 1
    ora #$7F
    and FACHO
    sta (INDEX),Y
    dey
    lda FACEXP
    sta (INDEX),Y
    sty FACOV
    rts

;; Rounds the <FAC> to the three mantissa bytes a variable keeps, to the nearest, a half to even, and clears FACLO.
;; See: <ROUND>
ROUNDER:
    jsr ROUND
    lda FACLO
    bpl RONDRTS                             ; below a half: down
    asl
    sta TEMP
    lda FACMO
    and #1
    ora TEMP                                ; above a half, or a half with FACMO odd: up
    beq RONDRTS
    lda #$FF
    sta FACLO
    jsr INCRND

;; Clears <FACLO>, for <ROUNDER>.
RONDRTS:
    lda #0
    sta FACLO
    rts

;; Moves <ARG> into the FAC.
;; Out: X = 0, FACOV = 0
MOVFA:
    lda ARGSGN

;; Moves <ARG>'s exponent and mantissa into the <FAC>, with A as its sign.
;; In: A = the sign
;; Out: X = 0, FACOV = 0
MOVFA1:
    sta FACSGN
    ldx #4+1

;; Moves a byte, for <MOVFA1>.
MOVFAL:
    lda ARGEXP-1,X
    sta FACEXP-1,X
    dex
    bne MOVFAL
    stx FACOV
    rts

;; Rounds the <FAC> and copies it, with its sign, into ARG.
;; Out: A = FACEXP, zero = set for a zero FAC, X = 0, FACOV = 0
;; See: <ROUND>
MOVAF:
    jsr ROUND

;; Copies the <FAC>, with its sign, into <ARG> without rounding it.
;; Out: A = FACEXP, zero = set for a zero FAC, X = 0, FACOV = 0
MOVEF:
    ldx #5+1

;; Copies a byte, for <MOVEF>.
MOVAFL:
    lda FACEXP-1,X
    sta ARGEXP-1,X
    dex
    bne MOVAFL
    stx FACOV
    rts

;; Rounds the <FAC>'s mantissa by the top bit of <FACOV>, taking a carry out of the top into the exponent.
;; Uses: A
ROUND:
    lda FACEXP
    beq RONRTS                              ; zero
    asl FACOV
    bcc RONRTS                              ; below a half

;; Adds one to the <FAC>'s mantissa, taking a carry out of the top into the exponent.
;; See: <INCFAC>, <RNDSHF>
INCRND:
    jsr INCFAC
    bne RONRTS
    jsr RNDSHF

;; An RTS for <ROUND>.
RONRTS:
    rts

; ---------------------------------------------------------------------------------------------------------------------
; Signs
; ---------------------------------------------------------------------------------------------------------------------

;; Gives the <FAC>'s sign.
;; Out: A = 0 for zero, 1 for positive, $FF for negative
SIGN:
    lda FACEXP
    beq SIGNRT

;; Gives the sign of <FACSGN>, as a non-zero <FAC>'s.
;; Out: A = 1 for positive, $FF for negative, carry = set for negative
FCSIGN:
    lda FACSGN

;; Gives 1 or $FF by the top bit of A.
;; In: A = the sign
;; Out: A = 1 for positive, $FF for negative, carry = set for negative
FCOMPS:
    rol
    lda #$100-1
    bcs SIGNRT
    lda #1

;; An RTS for <SIGN>.
SIGNRT:
    rts

;; Gives SGN, replacing the <FAC> with its sign: -1, 0 or 1.
;; See: <SIGN>, <FLOAT>
SGN:
    jsr SIGN

;; Floats the signed byte in A into the FAC.
;; In: A = the byte
FLOAT:
    sta FACHO
    lda #0
    sta FACHO+1
    ldx #$88

;; Floats the signed 16-bit number in <FACHO> and FACHO+1, high byte first, into the FAC.
;; In: X = the exponent: $90 for an integer
FLOATS:
    lda FACHO
    eor #$FF
    rol                                     ; the carry is set for positive

;; Floats the number in <FACHO> and FACHO+1 into the <FAC>, negating it when the carry is clear.
;; In: X = the exponent, carry = set for a positive number
;; See: <FADFLT>
FLOATC:
    lda #0
    sta FACLO
    sta FACMO
    stx FACEXP
    sta FACOV
    sta FACSGN
    jmp FADFLT

;; Gives ABS, making the <FAC> positive.
ABS:
    lsr FACSGN
    rts

; ---------------------------------------------------------------------------------------------------------------------
; Comparison
; ---------------------------------------------------------------------------------------------------------------------

;; Compares <ARG> with the <FAC>, taking them as equal when they match to 24 bits.
;;
;; It subtracts the FAC from ARG and calls them equal when the difference's exponent is at least 25 below the FAC's.
;; The FAC is kept, but ARG and <FACOV> are not.
;; Out: A = 1 when ARG is less, 0 when equal, $FF when ARG is greater
;; Uses: KIMY, TEMP
;; See: <FCOMP>
FCOMPARG:
    lda #25
    sta KIMY

;; Compares, with <KIMY> bits that must match.
;; In: KIMY = the bits that must match, plus one
FCOMPA1:
    lda FACSGN
    eor ARGSGN
    bmi FCSIGN                              ; the signs differ: the FAC's sign is the answer
    ldx #5

;; Saves the <FAC> on the stack.
PHFAC34:
    lda FAC,X
    pha
    dex
    bpl PHFAC34
    jsr FSUBT
    ldy FACSGN                              ; the difference's sign
    lda FACEXP
    sta TEMP
    ldx #$FA                                ; -6

;; Restores the <FAC> from the stack.
PHFAC35:
    pla
    sta FAC+6,X                             ; FAC to FAC+5, as zero page wraps
    inx
    bne PHFAC35
    lda TEMP
    beq ISEQU37                             ; no difference
    lda FACEXP
    sec
    sbc TEMP
    bcc NTEQU36                             ; the difference is larger than the FAC
    cmp KIMY
    bcs ISEQU37                             ; so small it counts as none

;; Gives the result by the difference's sign.
;; In: Y = the difference's sign
NTEQU36:
    tya
    eor #$FF
    jmp FCOMPS

;; Gives 0, equal.
ISEQU37:
    lda #0
    rts

;; Compares a five-byte real in BASIC's own bank, at <INDEX2>'s low byte and the page in Y, with the <FAC>, for NEXT.
;; In: Y = the page, 1 for a FOR entry on the stack
;; See: <FCOMP>
FCOMPN:
    lda INDEX2
    ldx #0

;; Compares the real at A, Y with the <FAC>, taking them as equal when they match to 32 bits.
;; In: A, Y = the real's address, X = its bank, 0 for BASIC's own
;; Out: A = 1 when the real is less, 0 when equal, $FF when it is greater
;; See: <FCOMPARG>, <CONUPK>
FCOMP:
    jsr CONUPK
    lda #33
    sta KIMY
    jmp FCOMPA1

; ---------------------------------------------------------------------------------------------------------------------
; Integer part
; ---------------------------------------------------------------------------------------------------------------------

;; Turns the <FAC> into a signed 32-bit integer in <FACHO>, <FACMOH>, <FACMO> and <FACLO>, high byte first: the greatest
;; integer not above it.
;;
;; The FAC must be below 2^31 in size, an exponent below $A0; callers check. A negative number is negated into two's
;; complement first, then shifted with ones coming in from the left. <QINT> goes on in B3FinpM.asm.
;; Uses: BITS
;; See: <INT>, <SHFTR1>
QINT:
    lda #0
    sta BITS                                ; zeros come in for a positive number
    lda FACEXP
    beq CLRFAC
    sec
    sbc #$A0                                ; minus the bits to shift
    bit FACSGN
    bpl QISHFT
    tax
    lda #$FF
    sta BITS                                ; ones come in for a negative number
    jsr NEGFCH
    txa

;; Shifts the integer into place: a byte at a time with <SHFTR1>, or by up to seven bits with <QINT1>.
QISHFT:
    ldx #FAC
    cmp #$100-7
    bpl QINT1
