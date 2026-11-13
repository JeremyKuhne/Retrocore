; B3FINPM: reals to and from text. FIN reads a number into the FAC and FOUT writes the FAC as text; with them come
; the INT function, line number printing, and the ^ operator and SQR.
;
; A real is a binary floating-point number. In the FAC it is an exponent byte (FACEXP), four mantissa bytes (FACHO,
; FACMOH, FACMO, FACLO), the sign (bit 7 of FACSGN) and a rounding byte (FACOV). The exponent is biased by $80, and an
; exponent of 0 means the number is zero whatever the other bytes hold. The mantissa is a fraction from 1/2 to 1, its
; top bit always 1, so the value is mantissa * 2^(exponent - $80). In memory the top bit's place holds the sign
; instead: a real variable is four bytes, the exponent and then the mantissa's top three bytes, rounded; a constant in
; BASIC's own bank keeps the fourth mantissa byte as a fifth byte.
;
; Names follow Apple's Business BASIC 1.3 listing.

; The end of QINT, from B3MATHL: 8 or more places to shift go through SHFTR1, which shifts whole bytes first.
    jmp SHFTR1

;; Shifts FAC's mantissa right a few places for QINT, keeping a negative number's sign bits.
;; In: A = minus the count of places, X = FAC's address
QINT1:
    tay                                     ; the count
    lda FACSGN
    and #$80
    lsr FACHO
    ora FACHO                               ; the sign into the top bit
    sta FACHO
    jmp ROLSHF

; ---------------------------------------------------------------------------------------------------------------------
; INT
; ---------------------------------------------------------------------------------------------------------------------

;; The INT function: the greatest integer not above FAC.
;;
;; A real of 2^31 or more in size has no fraction bits and is returned as it is, leaving <INTEGR> alone.
;; In: FAC = the real
;; Out: FAC = its integer part, rounded down, INTEGR = the integer's low byte
;; See: <QINT>
INT:
    lda FACEXP
    cmp #$98+8
    bcs INTRTS                              ; already an integer
    jsr QINT
    sty FACOV                               ; Y = 0
    lda FACSGN
    sty FACSGN
    eor #$80                                ; the sign, inverted, into the carry for FADFLT
    rol
    lda #$98+8
    sta FACEXP
    lda FACLO
    sta INTEGR
    jmp FADFLT

;; Zeros FAC's mantissa, for QINT's zero.
;; In: A = 0
;; Out: Y = 0
CLRFAC:
    sta FACHO
    sta FACMOH
    sta FACMO
    sta FACLO
    tay

;; An RTS for <INT>.
INTRTS:
    rts

; ---------------------------------------------------------------------------------------------------------------------
; FIN: text to a real
; ---------------------------------------------------------------------------------------------------------------------

;; Reads a real from the text at TXTPTR into FAC.
;;
;; The number is an optional sign, digits with at most one period, and an optional exponent: `E` or `e`, an optional
;; sign and digits. The digits are gathered into FAC as an integer, counting those after the period in <DECCNT>; then
;; FAC is multiplied or divided by 10 as many times as the exponent less that count says. Only nine digits after the
;; period are taken; the rest are skipped. An exponent of 100 or more is an overflow error, even when the digits would
;; bring the number back in range; a negative one of that size is taken as -100.
;; In: TXTPTR = the number's first character
;; Out: FAC = the number, TXTPTR = the first character after it, ANYNUM = $FF when there were no digits
;; Errors: ERROV = the number or its exponent is too large
;; Uses: DECCNT, TENEXP, DPTFLG, EXPSGN, SGNFLG, CNTDIGS, ARG
;; See: <FOUT>, <LINP>
FIN:
    jsr CHRGOT
    ldy #0
    sty CNTDIGS                             ; no limit before the period
    sty ANYNUM                              ; no digits yet
    ldx #10

;; Zeros DECCNT, TENEXP, DPTFLG, EXPSGN and FAC with SGNFLG.
FINZLP:
    sty DECCNT,X
    dex
    bpl FINZLP
    bcc FINDGQ                              ; CHRGOT's carry: a digit
    cmp #$2D                                ; '-'
    bne QPLUS
    stx SGNFLG                              ; X = $FF: negative
    beq FINC                                ; always

;; Skips a plus sign.
QPLUS:
    cmp #$2B                                ; '+'
    bne FIN1

;; Takes the next character; after the ninth digit past the period, skips the remaining digits.
FINC:
    jsr CHRGET
    dec CNTDIGS
    beq FINEND

;; Takes a digit.
FINDGQ:
    bcc FINDIG

;; Takes a character other than a digit: a period, an exponent, or the number's end.
FIN1:
    cmp #'.'
    beq FINDP
    eor #'E'
    and #$DF                                ; either case
    bne FINE
    sta CNTDIGS                             ; 0: no limit on the exponent's digits
    lda ANYNUM
    beq BADNMB                              ; an E with no digits before it
    jsr CHRGET
    bcc FNEDG1                              ; a digit
    cmp #'-'
    beq FINEC1
    cmp #'+'
    beq FINEC
    bne FINEC2

;; Notes a negative exponent.
FINEC1:
    ror EXPSGN                              ; the carry from the CMP: set

;; Takes the exponent's next character.
FINEC:
    jsr CHRGET

;; Takes an exponent digit.
FNEDG1:
    bcc FINEDG

;; Ends the exponent, negating it when its sign was minus.
FINEC2:
    bit EXPSGN
    bpl FINE
    lda #0
    sec
    sbc TENEXP
    jmp FINE1

;; Takes the period, with nine digits after it; a second period ends the number.
FINDP:
    ror DPTFLG                              ; bit 7 for the first, bit 6 too for a second
    lda #10
    sta CNTDIGS
    bit DPTFLG
    bvc FINC

;; Ends the number: scales FAC by the power of ten, then gives it its sign.
FINE:
    lda TENEXP

;; Scales FAC by 10 to the power of A less <DECCNT>.
FINE1:
    sec
    sbc DECCNT
    sta TENEXP
    beq FINQNG
    bpl FINMUL

;; Divides FAC by 10 for each negative power.
FINDIV:
    jsr DIV10
    inc TENEXP
    bne FINDIV
    beq FINQNG

;; Multiplies FAC by 10 for each positive power.
FINMUL:
    jsr MUL10
    dec TENEXP
    bne FINMUL

;; Checks for digits and gives FAC its sign.
FINQNG:
    lda ANYNUM
    beq BADNMB
    lda SGNFLG
    bmi NEGXQS
    rts

;; Negates FAC for a minus sign.
NEGXQS:
    jmp NEGOP

;; Marks the number as having no digits, setting <ANYNUM> to $FF.
BADNMB:
    lda #$FF
    sta ANYNUM
    rts

;; Skips a digit past the ninth after the period.
FINED1:
    jsr CHRGET

;; Skips the remaining digits, then takes the next character.
FINEND:
    bcc FINED1
    bcs FIN1

;; Takes a digit: FAC = FAC * 10 + the digit, counting it when after the period.
;; In: A = the digit's character
FINDIG:
    pha
    bit DPTFLG
    bpl FINDG1
    inc DECCNT                              ; a digit after the period

;; Multiplies by 10 and adds the digit.
FINDG1:
    jsr MUL10
    pla
    inc ANYNUM
    sec
    sbc #'0'
    jsr FINLOG
    jmp FINC

;; Adds a small integer to FAC.
;; In: A = the integer, from -128 to 127
;; Out: FAC = FAC + A
;; Uses: ARG
FINLOG:
    pha
    jsr MOVAF                               ; FAC to ARG
    pla
    jsr FLOAT
    lda ARGSGN
    eor FACSGN
    sta ARISGN
    ldx FACEXP
    jmp FADDT

;; Takes an exponent digit: TENEXP = TENEXP * 10 + the digit, with no more than two digits.
;; In: TXTPTR = the digit
;; Errors: ERROV = a positive exponent of 100 or more
FINEDG:
    lda TENEXP
    cmp #$A
    bcc MLEX10
    lda #$64                                ; 100, for a negative exponent
    bit EXPSGN
    bmi MLEXMI
    jmp OVERR

;; Multiplies the exponent by 10 and adds the digit.
MLEX10:
    asl
    asl
    clc
    adc TENEXP                              ; times 5
    asl                                     ; times 10
    clc
    ldy #0
    adc (TXTPTR),Y
    sec
    sbc #'0'

;; Keeps the new exponent and takes the next character.
MLEXMI:
    sta TENEXP
    jmp FINEC

; ---------------------------------------------------------------------------------------------------------------------
; FOUT: a real to text
; ---------------------------------------------------------------------------------------------------------------------

;; The real 99999.94998: FOUT multiplies by 10 until the number is above it.
N_0999:
    .byte $91
    .byte $43
    .byte $4F
    .byte $F9
    .byte $99

;; The real 999999.5: FOUT divides by 10 until the number is no more than it. (Apple's comment says 999999.499.)
N_9999:
    .byte $94
    .byte $74
    .byte $23
    .byte $F8
    .byte $00

;; The real 1000000, which brings a number below 1 up for FOUT.
N_MIL:
    .byte $94
    .byte $74
    .byte $24
    .byte $00
    .byte 0

;; Prints " IN " and the current line number, after an error message.
;; See: <LINPRT>, <INTXT>
INPRT:
    lda #<(INTXT)
    ldy #>(INTXT)
    ldx #INTXTB
    jsr STROUTR
    lda CURLIN+1
    ldx CURLIN

;; Prints a 16-bit number from 0 to 65535, such as a line number, with no space before it.
;; In: A = the high byte, X = the low byte
;; See: <FOUT>
LINPRT:
    sta FACHO
    stx FACHO+1
    ldx #$90                                ; the exponent for a 16-bit integer
    sec                                     ; positive
    jsr FLOATC
    jsr FOUT
    jmp STROUTR

;; Writes FAC as text in <FBUFFR>, rounded to six significant digits.
;;
;; A negative number starts with a minus sign; a positive one has nothing before its digits. Trailing zeros are dropped,
;; and the period with them when nothing follows it. A number from 0.01 to below 999999.5 is written out, one below 0.1
;; as `.0` and its digits; any other is written with one digit before the period and a two-digit exponent with its
;; sign, as in `1.5E+07`. Zero is `0`.
;; In: FAC = the number
;; Out: FBUFFR = the text, ending in a zero, A = its address's low byte, Y = its high byte, X = 0, its bank,
;;   ISARA = 7 more than the power of ten of the last digit, for PRINT USING
;; Uses: DECCNT, TENEXP, FBUFPT, FDECPT, ARG
;; See: <FIN>, <LOUT>
FOUT:
    jsr ROUNDER
    ldy #1

;; Writes FAC as text from FBUFFR + Y - 1.
;; In: Y = one more than the place to start at
FOUTC:
    lda #$2D                                ; '-'
    dey
    bit FACSGN
    bpl FOUT1_1
    iny
    sta FBUFFR-1,Y

;; Makes FAC positive and checks for zero.
FOUT1_1:
    sta FACSGN                              ; $2D: positive
    sty FBUFPT
    iny
    lda #'0'
    ldx FACEXP
    bne *+5
    jmp FOUT19                              ; zero
    lda #0
    cpx #$80
    beq FOUT37                              ; from 1/2 to 1
    bcs FOUT7                               ; 1 or more

;; Multiplies a number below 1 by a million first.
FOUT37:
    lda #<(N_MIL)
    ldy #>(N_MIL)
    jsr FMULT
    lda #$100-6-0                           ; -6: the power of ten so far

;; Sets the power of ten so far.
FOUT7:
    sta DECCNT

;; Brings the number below 999999.5, dividing by 10.
FOUT4:
    lda #<(N_9999)
    ldx #N_MILB
    ldy #>(N_9999)
    jsr FCOMP
    beq BIGGES                              ; exactly 999999.5: no rounding
    bpl FOUT9                               ; above it: smaller

;; Brings the number above 99999.95, multiplying by 10.
FOUT3:
    lda #<(N_0999)
    ldx #N_MILB
    ldy #>(N_0999)
    jsr FCOMP
    beq FOUT38
    bpl FOUT5                               ; in range

;; Multiplies by 10, counting the power down.
FOUT38:
    jsr MUL10
    dec DECCNT
    bne FOUT3                               ; always

;; Divides by 10, counting the power up.
FOUT9:
    jsr DIV10
    inc DECCNT
    bne FOUT4                               ; always

;; Rounds to the nearest integer.
FOUT5:
    jsr FADDH

;; Takes the six-digit integer and decides where the period goes and whether there is an exponent.
BIGGES:
    jsr QINT
    ldx #1                                  ; one digit before the period, with an exponent
    lda DECCNT
    clc
    adc #0*1+7
    sta ISARA
    bmi FOUTPI                              ; below 0.01: an exponent
    cmp #0+$8
    bcs FOUT6                               ; 999999.5 or more: an exponent
    adc #$100-1
    tax                                     ; the digits before the period
    lda #2                                  ; no exponent

;; Sets the carry for the subtract.
FOUTPI:
    sec

;; Sets the exponent to write, then writes a leading period, or `.0`, when no digit comes before it.
FOUT6:
    sbc #2
    sta TENEXP
    stx DECCNT                              ; the digits before the period
    txa
    beq FOUT39
    bpl FOUT8

;; Writes the period before the digits, and a 0 after it for a number below 0.1.
FOUT39:
    ldy FBUFPT
    lda #'.'
    iny
    sta FBUFFR-1,Y
    txa
    beq FOUT16
    lda #'0'
    iny
    sta FBUFFR-1,Y

;; Keeps the place in the text.
FOUT16:
    sty FBUFPT

;; Writes the six digits, one for each power of ten in <FOUTBL>.
FOUT8:
    ldy #0
    ldx #$80

;; Takes one digit: adds the power of ten (subtracting for the negative ones) until the number's sign changes,
;; counting in X.
FOUT2:
    lda FACLO
    clc
    adc a:FOUTBL+2+1,Y
    sta FACLO
    lda FACMO
    adc a:FOUTBL+1+1,Y
    sta FACMO
    lda FACMOH
    adc a:FOUTBL+1,Y
    sta FACMOH
    lda FACHO
    adc a:FOUTBL,Y
    sta FACHO
    inx
    bcs FOUT41
    bpl FOUT2
    bmi FOUT40

;; Goes on adding until the sign changes.
FOUT41:
    bmi FOUT2

;; Turns the count into the digit: for a power that was subtracted, the count less one; for one added, 10 less it.
FOUT40:
    txa
    bcc FOUTYP
    eor #$FF
    adc #$A

;; Writes the digit, and the period after it when its place comes.
FOUTYP:
    adc #'0'-1
    iny
    iny
    iny
    iny                                     ; the next power
    sty FDECPT
    ldy FBUFPT
    iny
    tax
    and #$7F
    sta FBUFFR-1,Y
    dec DECCNT
    bne STXBUF
    lda #'.'
    iny
    sta FBUFFR-1,Y

;; Keeps the place in the text and flips the direction for the next power.
STXBUF:
    sty FBUFPT
    ldy FDECPT
    txa
    eor #$FF
    and #$80
    tax
    cpy #FDCEND-FOUTBL
    bne FOUT2
    ldy FBUFPT

;; Drops trailing zeros, and the period if it ends the number.
FOUT11:
    lda FBUFFR-1,Y
    dey
    cmp #'0'
    beq FOUT11
    cmp #'.'
    beq FOUT12
    iny                                     ; keep this character

;; Writes the exponent, if any: `E`, its sign and two digits.
FOUT12:
    lda #$2B                                ; '+'
    ldx TENEXP
    beq FOUT17
    bpl FOUT14
    lda #0
    sec
    sbc TENEXP
    tax
    lda #$2D                                ; '-'

;; Writes `E`, the sign and the exponent's two digits.
FOUT14:
    sta FBUFFR-1+2,Y
    lda #'E'
    sta FBUFFR-1+1,Y
    txa
    ldx #'0'-1
    sec

;; Counts the exponent's tens in X.
FOUT15:
    inx
    sbc #$A
    bcs FOUT15
    adc #'0'+$A
    sta FBUFFR-1+4,Y                        ; the ones digit
    txa
    sta FBUFFR-1+3,Y                        ; the tens digit
    lda #0
    sta FBUFFR-1+5,Y
    beq FOUT20                              ; always

;; Writes the one character in A, for zero.
FOUT19:
    sta FBUFFR-1,Y

;; Ends the text with a zero.
FOUT17:
    lda #0
    sta FBUFFR-1+1,Y

;; Returns the text's address.
FOUT20:
    lda #<(FBUFFR)
    ldx #0
    ldy #>(FBUFFR)
    rts

;; The real 0.5, five bytes, the last four shared with <ZERO>.
FHALF:
    .byte $80

;; Eight zero bytes: a real or long integer 0. <PTRGET> returns this for a variable that is read but was never set,
;; rather than making one.
ZERO:
    .byte 000
    .byte 000
    .byte 000
    .byte 0
    .byte 0, 0, 0, 0

;; The powers of ten for FOUT's digits, as 32-bit integers, most significant byte first: -100000, 10000, -1000, 100,
;; -10 and 1. Alternating the signs lets each digit be counted from where the last left the number, without restoring.
FOUTBL:
    .byte $FF, $FE, $79, $60                ; -100000
    .byte $0, 0, $27, $10                   ; 10000
    .byte $FF, $FF, $FC, $18                ; -1000
    .byte 0, 0, 0, $64                      ; 100
    .byte $FF, $FF, $FF, $F6                ; -10
    .byte 0, 0, 0, 1                        ; 1
FDCEND:

; ---------------------------------------------------------------------------------------------------------------------
; SQR and ^
; ---------------------------------------------------------------------------------------------------------------------

;; The SQR function: the square root of FAC, as FAC ^ 0.5.
;; Errors: ERRFC = FAC is negative
;; See: <FPWRT>
SQR:
    jsr MOVAF
    lda #<(FHALF)
    ldx #FHALFB
    ldy #>(FHALF)
    jsr MOVFM                               ; with the zero flag from 0.5's exponent

;; The ^ operator: ARG to the power of FAC, as EXP(FAC * LOG(ARG)).
;;
;; Anything to the power 0 is 1, even 0; 0 to any other power is 0. A negative ARG needs an integer power, else LOG
;; gives an illegal quantity error; the power of its size is negated when the power is odd. For a power of 2^31 or
;; more, <INT> leaves <INTEGR> alone, so whether it counts as odd comes from whatever INTEGR held.
;; In: ARG = the base, FAC = the power, zero = set for a zero power
;; Out: FAC = the result
;; Errors: ERRFC = a negative base with a power that is not an integer, ERROV = the result is too large
;; Uses: TEMPF3, KIMY
;; See: <EXP>, <LOG>, <SQR>
FPWRT:
    beq GOTOEXP                             ; a zero power: EXP(0)
    lda ARGEXP
    bne FPWRT1
    jmp ZEROF1                              ; a zero base

;; Saves the power, and checks a negative base's power is an integer.
FPWRT1:
    ldx #TEMPF3
    lda #TEMPF3B
    ldy #>(TEMPF3)
    jsr MOVMF                               ; the power into TEMPF3; Y = 0, an even power
    lda ARGSGN
    bpl FPWR1
    jsr INT
    ldx #5

;; Saves ARG, which FCOMP overwrites.
FPLP1:
    lda ARG,X
    pha
    dex
    bpl FPLP1
    lda #TEMPF3
    ldx #TEMPF3B
    ldy #>(TEMPF3)
    jsr FCOMP
    bne FPLP3                               ; not an integer: LOG will refuse the negative base
    tya                                     ; an integer: make the base positive
    ldy INTEGR                              ; and keep whether the power is odd

;; Takes the base's sign from A and restores ARG.
FPLP3:
    ldx #$FA                                ; -6
    sta KIMY

;; Restores a byte of ARG.
FPLP2:
    pla
    sta ARG+6,X
    inx
    bne FPLP2
    lda KIMY

;; Computes EXP(power * LOG(base)), then negates it for an odd power.
FPWR1:
    jsr MOVFA1                              ; the base into FAC, with the sign in A
    tya
    pha                                     ; bit 0 set for an odd power
    jsr LOG
    lda #TEMPF3
    ldy #>(TEMPF3)
    jsr FMULT
    jsr EXP
    pla
    lsr
    bcc NEGRTS                              ; even

;; Negates FAC, unless it is zero.
NEGOP:
    lda FACEXP
    beq NEGRTS
    lda FACSGN
    eor #255
    sta FACSGN

;; An RTS for <NEGOP> and <FPWRT>.
NEGRTS:
    rts

;; Gives EXP(0), 1, for a zero power.
GOTOEXP:
    jmp EXP
