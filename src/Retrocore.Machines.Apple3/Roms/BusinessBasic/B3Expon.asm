; B3EXPON: the EXP, RND, COS, SIN, TAN and ATN functions, and the polynomial evaluators they use.
;
; The constants here are reals in their five-byte form: an exponent byte, then four bytes of mantissa with the sign in
; the top bit (the mantissa's own top bit is always 1, so it is left out). Constants in BASIC's own bank are read with
; all five bytes; a variable keeps only the first four.
;
; Names follow Apple's Business BASIC 1.3 listing.

; ---------------------------------------------------------------------------------------------------------------------
; EXP
; ---------------------------------------------------------------------------------------------------------------------

;; The real 1.4426950407, log2(e), which turns a power of e into a power of 2.
LOGEB2:
    .byte $81
    .byte $38
    .byte $AA
    .byte $3B, $29

;; EXP's polynomial: 2^x for x from 0 to 1, as eight coefficients (a degree of 7), highest power first; they follow the
;; series of e^(x ln 2).
;; See: <POLY>
EXPCON:
    .byte 7                                 ; the degree
    .byte $71                               ; 0.0000214987636, for x^7
    .byte $34
    .byte $58
    .byte $3E
    .byte $56
    .byte $74                               ; 0.00014352314036, for x^6
    .byte $16
    .byte $7E
    .byte $B3
    .byte $1B
    .byte $77                               ; 0.0013422634824, for x^5
    .byte $2F
    .byte $EE
    .byte $E3
    .byte $85
    .byte $7A                               ; 0.0096140170119, for x^4
    .byte $1D
    .byte $84
    .byte $1C
    .byte $2A
    .byte $7C                               ; 0.055505126860, for x^3
    .byte $63
    .byte $59
    .byte $58
    .byte $0A
    .byte $7E                               ; 0.24022638462, for x^2
    .byte $75
    .byte $FD
    .byte $E7
    .byte $C6
    .byte $80                               ; 0.69314718608, ln 2, for x
    .byte $31
    .byte $72
    .byte $18
    .byte $10
    .byte $81                               ; 1.0
    .byte $00
    .byte $00
    .byte $00
    .byte $00

;; The EXP function: e to the power of FAC.
;;
;; e^x is 2^y, with y = x * log2(e). The integer part of y becomes the result's exponent, and <EXPCON>'s polynomial
;; gives 2 to the power of the fraction. A y of 128 or more in size is an overflow error when positive and gives 0 when
;; negative.
;; In: FAC = x
;; Out: FAC = e^x
;; Errors: ERROV = the result is too large
;; See: <LOG>, <FPWRT>
EXP:
    lda #<(LOGEB2)
    ldy #>(LOGEB2)
    jsr FMULT
    lda FACOV
    adc #$50
    bcc STOLD
    jsr INCRND                              ; round the product up

;; Keeps the product's extra low byte, biased by $50, while the product is copied to ARG unrounded.
STOLD:
    sta OLDOV
    jsr MOVEF
    lda FACEXP
    cmp #$88                                ; y of 128 or more in size
    bcc EXP1

;; Gives an overflow error, or 0 for a negative y, and returns from EXP.
GOMLDV:
    jsr MLDVEX

;; Splits y into its integer part, the scale, and its fraction, and raises 2 to the fraction.
EXP1:
    jsr INT
    lda INTEGR                              ; the integer part's low byte
    clc
    adc #$81
    beq GOMLDV                              ; -129: too small
    sec
    sbc #1
    pha                                     ; the scale, as an exponent byte
    ldx #4+1

;; Exchanges FAC and ARG: FAC = y again, ARG = INT(y).
SWAPLP:
    lda ARGEXP,X
    ldy FACEXP,X
    sta FACEXP,X
    sty ARGEXP,X
    dex
    bpl SWAPLP
    lda OLDOV
    sta FACOV
    jsr FSUBT                               ; INT(y) - y
    jsr NEGOP                               ; y - INT(y), from 0 to 1
    lda #<(EXPCON)
    ldy #>(EXPCON)
    jsr POLY
    lda #0
    sta ARISGN
    pla
    jsr MLDEXP                              ; add the scale to the exponent
    rts                                     ; a JSR, not a JMP: MLDEXP's underflow drops a return address

; ---------------------------------------------------------------------------------------------------------------------
; Polynomials
; ---------------------------------------------------------------------------------------------------------------------

;; Evaluates an odd polynomial of FAC: x * P(x^2), for SIN and ATN.
;;
;; The table is a degree byte, then degree + 1 five-byte coefficients, highest power first, so the terms run from
;; x^(2 * degree + 1) down to x.
;; In: FAC = x, A = the table's low byte, Y = its high byte
;; Out: FAC = the polynomial's value
;; Uses: TEMPF1, TEMPF2, POLYPT, DEGREE
;; See: <POLY>
POLYX:
    sta POLYPT
    sty POLYPT+1
    jsr MOV1F                               ; x into TEMPF1
    lda #TEMPF1
    jsr FMULT                               ; x^2
    jsr POLY1
    lda #TEMPF1
    ldy #>(TEMPF1)
    jmp FMULT                               ; times x

;; Evaluates a polynomial of FAC by Horner's rule.
;;
;; The table is a degree byte, then degree + 1 five-byte coefficients, highest power first.
;; In: FAC = x, A = the table's low byte, Y = its high byte
;; Out: FAC = the polynomial's value
;; Uses: TEMPF2, POLYPT, DEGREE
;; See: <POLYX>
POLY:
    sta POLYPT
    sty POLYPT+1

;; Evaluates the polynomial at <POLYPT> with x in FAC.
POLY1:
    jsr MOV2F                               ; x into TEMPF2
    sty POLYPTB                             ; the table is in bank 0
    lda (POLYPT),Y
    sta DEGREE
    ldy POLYPT
    iny
    tya
    bne POLY3
    inc POLYPT+1

;; Points at the first coefficient.
POLY3:
    sta POLYPT
    ldy POLYPT+1

;; Multiplies by x and adds the next coefficient, once for each degree.
POLY2:
    jsr FMULT
    lda POLYPT
    ldy POLYPT+1
    clc
    adc #4+1
    bcc POLY4
    iny

;; Steps to the next coefficient and adds it.
POLY4:
    sta POLYPT
    sty POLYPT+1
    jsr FADD
    lda #TEMPF2                             ; x, for the next multiply
    ldy #>(TEMPF2)
    dec DEGREE
    bne POLY2
    rts

; ---------------------------------------------------------------------------------------------------------------------
; RND
;
; The generator is the Lehmer "minimal standard": the seed, a long integer in RNDX, is multiplied by 16807 and
; reduced modulo 2^31-1, and RND gives the new seed times 2^-31, between 0 and 1. (Apple's comments describe
; Microsoft's older generator, which swapped bytes of the mantissa.)
; ---------------------------------------------------------------------------------------------------------------------

;; The long integer 2^31-1, the generator's modulus.
RMOD_C:
    .byte 0, 0, 0, 0
    .byte $7F, $FF, $FF, $FF

;; The long integer 16807, the generator's multiplier.
RMUL_C:
    .byte 0, 0, 0, 0
    .byte 0, 0, $41, $A7

;; The real 2^-31, which scales the seed to a number between 0 and 1.
RSMAL_C:
    .byte $62, $00, 0, 0
    .byte 0

;; The RND function: the next pseudo-random number, between 0 and 1.
;;
;; RND(0) repeats the last number. A negative argument starts a new sequence from it: its mantissa, with the exponent
;; forced between $90 and $9F, becomes the seed, which is put through the generator three times. A positive argument
;; puts the seed through once.
;; In: FAC = the argument
;; Out: FAC = the number, VALTYP = 0
;; See: <RNDAT>, <RNDX>
RND:
    lda FACEXP
    beq GETRND
    bit FACSGN
    bpl RNDMAK
    lsr FACSGN                              ; positive
    and #$1F                                ; the exponent from $90 to $9F
    ora #$90
    sta FACEXP
    jsr CONV2LNG
    jsr RNDAT                               ; the argument as the seed
    jsr RNDIT

;; Takes the next number.
RNDMAK:
    jsr RNDIT

;; Gives the seed as a real between 0 and 1.
GETRND:
    jsr RNDONE
    jsr LMAKFLT
    lda #<(RSMAL_C)
    ldy #>(RSMAL_C)
    ldx #0
    jmp FMULT

;; Loads the seed, <RNDX>, into FAC as a long integer.
RNDONE:
    lda #RNDX
    ldy #>(RNDX)
    ldx #RNDXB
    jmp LDFACT

;; Puts the seed in <RNDX> through the generator once.
RNDIT:
    jsr RNDONE

;; Puts the long integer in FAC through the generator, storing the result in <RNDX>: FAC * 16807 MOD (2^31-1).
;; Uses: ARG, RES
RNDAT:
    jsr FACTOARG
    lda #<(RMUL_C)
    ldy #>(RMUL_C)
    ldx #RNDXB
    jsr LDFACT
    jsr LMULT
    jsr FACTOARG
    lda #<(RMOD_C)
    ldy #>(RMOD_C)
    ldx #0
    jsr LDFACT
    jsr LREM
    lda #RNDX
    ldy #>(RNDX)
    ldx #RNDXB
    jmp STFACT

; ---------------------------------------------------------------------------------------------------------------------
; COS, SIN and TAN
; ---------------------------------------------------------------------------------------------------------------------

;; The COS function: the cosine of FAC, in radians, as SIN(x + pi/2).
;; See: <SIN>
COS:
    lda #<(PI2)
    ldy #>(PI2)
    jsr FADD

;; The SIN function: the sine of FAC, in radians.
;;
;; The angle is divided by 2 * pi and its integer part dropped, leaving a fraction of a turn. Symmetries fold that into
;; the quarter turn from -1/4 to 1/4, which <SINCON>'s polynomial takes. In the second and third quarters it flips
;; <TANSGN>, for TAN.
;; In: FAC = the angle
;; Out: FAC = the sine, TEMPF1 = the folded fraction of a turn
;; See: <COS>, <TAN>, <POLYX>
SIN:
    jsr MOVAF
    lda #<(TWOPI)
    ldy #>(TWOPI)
    ldx ARGSGN
    jsr FDIVF                               ; turns
    jsr MOVAF
    jsr INT
    lda #0
    sta ARISGN
    jsr FSUBT                               ; the fraction of a turn
    lda #<(FR4)
    ldy #>(FR4)
    jsr FSUB                                ; 1/4 - the fraction
    lda FACSGN
    pha
    bpl SIN1                                ; the first quarter
    jsr FADDH
    lda FACSGN
    bmi SIN2
    lda TANSGN
    eor #255
    sta TANSGN                              ; the second and third quarters

;; Negates FAC, the start of the fold.
SIN1:
    jsr NEGOP

;; Adds 1/4 and gives the folded fraction the quarter's sign.
SIN2:
    lda #<(FR4)
    ldy #>(FR4)
    jsr FADD
    pla
    bpl SIN3
    jsr NEGOP

;; Evaluates the sine polynomial on the folded fraction.
SIN3:
    lda #<(SINCON)
    ldy #>(SINCON)
    jmp POLYX

;; The TAN function: the tangent of FAC, in radians, as the sine over the cosine.
;;
;; After <SIN>, the folded fraction it leaves in TEMPF1 is folded again through <COSC> to give the cosine, with
;; <TANSGN> as its sign.
;; In: FAC = the angle
;; Out: FAC = the tangent
;; Errors: ERRDV0 = the cosine is zero
;; See: <SIN>, <COSC>
TAN:
    jsr MOV1F
    lda #0
    sta TANSGN
    jsr SIN
    ldx #TEMPF3
    lda #TEMPF3B
    ldy #>(TEMPF3)
    jsr MOVMF                               ; the sine into TEMPF3
    lda #TEMPF1
    ldx #TEMPF3B
    ldy #>(TEMPF1)
    jsr MOVFM                               ; the folded fraction from SIN
    lda #0
    sta FACSGN
    lda TANSGN
    jsr COSC
    lda #TEMPF3
    ldy #>(TEMPF3)
    jmp FDIV                                ; the sine over the cosine

;; Finishes the cosine for TAN through SIN's fold, with the sign in A.
;; In: FAC = the folded fraction's size, A = bit 7 set to negate the result
COSC:
    pha
    jmp SIN1

;; The real 1.5707963267, pi/2.
PI2:
    .byte $81
    .byte $49
    .byte $0F
    .byte $DA
    .byte $A2

;; The real 6.283185307, 2 * pi.
TWOPI:
    .byte $83
    .byte $49
    .byte $0F
    .byte $DA
    .byte $A2

;; The real 0.25, a quarter turn.
FR4:
    .byte $7F
    .byte $00
    .byte $00
    .byte $00
    .byte 0

;; SIN's polynomial: sin(2 * pi * x) for x from -1/4 to 1/4, as an odd polynomial of six coefficients (a degree of 5),
;; highest power first.
;;
;; The ten bytes after it are Microsoft's signature, which no code reads: `MICROSOFT!` backward, each byte
;; exclusive-ored with $87.
;; See: <POLYX>
SINCON:
    .byte 5                                 ; the degree
    .byte $84                               ; -14.381383816, for x^11
    .byte $E6
    .byte $1A
    .byte $2D
    .byte $1B
    .byte $86                               ; 42.07777095, for x^9
    .byte $28
    .byte $07
    .byte $FB
    .byte $F8
    .byte $87                               ; -76.704133676, for x^7
    .byte $99
    .byte $68
    .byte $89
    .byte $01
    .byte $87                               ; 81.605223690, for x^5
    .byte $23
    .byte $35
    .byte $DF
    .byte $E1
    .byte $86                               ; -41.34170209, for x^3
    .byte $A5
    .byte $5D
    .byte $E7
    .byte $28
    .byte $83                               ; 6.2831853070, 2 * pi, for x
    .byte $49
    .byte $0F
    .byte $DA
    .byte $A2
    .byte $A6                               ; the signature: "!TFOSORCIM" exclusive-ored with $87
    .byte $D3
    .byte $C1
    .byte $C8
    .byte $D4
    .byte $C8
    .byte $D5
    .byte $C4
    .byte $CE
    .byte $CA

; ---------------------------------------------------------------------------------------------------------------------
; ATN
; ---------------------------------------------------------------------------------------------------------------------

;; The ATN function: the arctangent of FAC, in radians.
;;
;; Uses ATN(-x) = -ATN(x) to work on a positive x, and ATN(x) = pi/2 - ATN(1/x) to bring an x of 1 or more below 1,
;; where <ATNCON>'s polynomial takes it.
;; In: FAC = x
;; Out: FAC = the angle, from -pi/2 to pi/2
;; See: <POLYX>
ATN:
    lda FACSGN
    pha                                     ; the sign, for the end
    bpl ATN1
    jsr NEGOP

;; Takes the reciprocal of an x of 1 or more.
ATN1:
    lda FACEXP
    pha                                     ; the size, for the end
    cmp #$81
    bcc ATN2                                ; below 1
    lda #<(FONE)
    ldy #>(FONE)
    jsr FDIV                                ; 1/x

;; Evaluates the arctangent polynomial.
ATN2:
    lda #<(ATNCON)
    ldy #>(ATNCON)
    jsr POLYX
    pla
    cmp #$81
    bcc ATN3                                ; x was below 1
    lda #<(PI2)
    ldy #>(PI2)
    jsr FSUB                                ; pi/2 - the result

;; Gives the result the argument's sign.
ATN3:
    pla
    bpl ATN4
    jmp NEGOP

;; An RTS for <ATN>.
ATN4:
    rts

;; ATN's polynomial: the arctangent of x for x from 0 to 1, as an odd polynomial of twelve coefficients (a degree of
;; 11), highest power first; they are close to the series x - x^3/3 + x^5/5 - ...
;; See: <POLYX>
ATNCON:
    .byte $0B                               ; the degree
    .byte $76                               ; -0.0006847939119, for x^23
    .byte $B3
    .byte $83
    .byte $BD
    .byte $D3
    .byte $79                               ; 0.004850942156, for x^21
    .byte $1E
    .byte $F4
    .byte $A6
    .byte $F5
    .byte $7B                               ; -0.01611170184, for x^19
    .byte $83
    .byte $FC
    .byte $B0
    .byte $10
    .byte $7C                               ; 0.03420963805, for x^17
    .byte $0C
    .byte $1F
    .byte $67
    .byte $CA
    .byte $7C                               ; -0.05427913276, for x^15
    .byte $DE
    .byte $53
    .byte $CB
    .byte $C1
    .byte $7D                               ; 0.07245719654, for x^13
    .byte $14
    .byte $64
    .byte $70
    .byte $4C
    .byte $7D                               ; -0.08980239538, for x^11
    .byte $B7
    .byte $EA
    .byte $51
    .byte $7A
    .byte $7D                               ; 0.1109324134, for x^9
    .byte $63
    .byte $30
    .byte $88
    .byte $7E
    .byte $7E                               ; -0.1428398077, for x^7
    .byte $92
    .byte $44
    .byte $99
    .byte $3A
    .byte $7E                               ; 0.1999991205, for x^5
    .byte $4C
    .byte $CC
    .byte $91
    .byte $C7
    .byte $7F                               ; -0.3333333157, for x^3
    .byte $AA
    .byte $AA
    .byte $AA
    .byte $13
    .byte $81                               ; 1.0, for x
    .byte $00
    .byte $00
    .byte $00
    .byte $00
