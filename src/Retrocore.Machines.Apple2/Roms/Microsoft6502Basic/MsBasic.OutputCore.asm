;; Emits the line-number and decimal-output routines.
;; Parameters: omitPositiveSpace = 1 to omit the leading space for positive values, otherwise 0
;;   includeTime = 1 to use the time-conversion table, otherwise 0
.macro DECIMAL_OUTPUT omitPositiveSpace, includeTime

    .assert omitPositiveSpace = 0 || omitPositiveSpace = 1, "omitPositiveSpace is 0 or 1."
    .assert includeTime = 0 || includeTime = 1, "includeTime is 0 or 1."

; Line-number printing and floating-point formatting.

;; Prints the line-number prefix and the current line number.
;; See: <LINPRT>, <INTXT>
INPRT:
    lda #<INTXT
    ldy #>INTXT
    jsr STROU2
    lda CURLIN+1
    ldx CURLIN

;; Prints the unsigned line number in A:X.
;; In: A = high byte of line number, X = low byte of line number
;; See: <FOUT>, <STROUT>
LINPRT:
    sta FACHO
    stx FACMOH
    ldx #$90
    sec
    jsr FLOATC
    jsr FOUT

;; Prints the string addressed by Y:A through <STROUT>.
STROU2:
    jmp STROUT

;; Formats <FAC> as a zero-terminated decimal string in <FBUFFR>.
;;
;; It scales the magnitude between the thresholds, rounds by adding one half, and converts the integer with
;; <FOUTBL>. It suppresses trailing fractional zeroes and emits a signed, two-digit E exponent when needed.
;; <FAC> is changed.
;; The positive sign is either a space or omitted, according to the variant.
;; <FOUTC> also serves STR$: with Y = 0 its string begins one byte earlier at <LOFBUF>.
;; Out: A = low byte of <FBUFFR>, Y = high byte of <FBUFFR>
;; Entry: FOUTC = uses the caller's Y to select the initial output position
FOUT:
    ldy #$01

FOUTC:
.if omitPositiveSpace
    lda #'-'
    dey
    bit FACSGN
    bpl FOUT13
    iny

FOUT1:
    sta FBUFFR-1,y

FOUT13:
.else
    lda #' '
    bit FACSGN
    bpl FOUT1
    lda #'-'

FOUT1:
    sta FBUFFR-1,y
.endif
    sta FACSGN
    sty FBUFPT
    iny
    lda #'0'
    ldx FACEXP
    bne *+5                         ; skip the zero-output jump for a nonzero exponent
    jmp FOUT19
    lda #$00
    cpx #$80
    beq FOUT37
    bcs FOUT7

FOUT37:
    lda #<NZMIL
    ldy #>NZMIL
    jsr FMULT
    lda #$F7

FOUT7:
    sta DECCNT

FOUT4:
    ; Scale the magnitude into the nine-digit range, keeping the decimal scale in <DECCNT>.
    lda #<NZ9999
    ldy #>NZ9999
    jsr FCOMP
    beq BIGGES
    bpl FOUT9

FOUT3:
    lda #<NZ0999
    ldy #>NZ0999
    jsr FCOMP
    beq FOUT38
    bpl FOUT5

FOUT38:
    jsr MUL10
    dec DECCNT
    bne FOUT3

FOUT9:
    jsr DIV10
    inc DECCNT
    bne FOUT4

FOUT5:
    jsr FADDH

BIGGES:
    jsr QINT
    ldx #$01
    lda DECCNT
    clc
    adc #$0A
    bmi FOUTPI
    cmp #$0B
    bcs FOUT6
    adc #$FF
    tax
    lda #$02

FOUTPI:
    sec

FOUT6:
    sbc #$02
    sta TENEXP                      ; zero selects fixed-point output
    stx DECCNT
    txa
    beq FOUT39
    bpl FOUT8

FOUT39:
    ldy FBUFPT
    lda #'.'
    iny
    sta FBUFFR-1,y
    txa
    beq FOUT16
    lda #'0'
    iny
    sta FBUFFR-1,y

FOUT16:
    sty FBUFPT

FOUT8:
    ldy #$00

FOUTIM:
    ldx #$80

;; Extracts one decimal digit by repeated addition of an alternating signed power of ten.
FOUT2:
    lda FACLO
    clc
    adc FOUTBL+3,y
    sta FACLO
    lda FACMO
    adc FOUTBL+2,y
    sta FACMO
    lda FACMOH
    adc FOUTBL+1,y
    sta FACMOH
    lda FACHO
    adc FOUTBL,y
    sta FACHO
    inx
    bcs FOUT41
    bpl FOUT2
    bmi FOUT40

FOUT41:
    bmi FOUT2

FOUT40:
    txa
    bcc FOUTYP
    eor #$FF
    adc #$0A

FOUTYP:
    adc #('0'-1)
    iny
    iny
    iny
    iny
    sty FDECPT
    ldy FBUFPT
    iny
    tax
    and #$7F
    sta FBUFFR-1,y
    dec DECCNT
    bne STXBUF
    lda #'.'
    iny
    sta FBUFFR-1,y

STXBUF:
    sty FBUFPT
    ldy FDECPT

FOUTCM:
    txa
    eor #$FF
    and #$80
    tax
    cpy #(FDCEND-FOUTBL)
.if includeTime
    beq FOULDY
    cpy #(TIMEND-FOUTBL)
.endif
    bne FOUT2

FOULDY:
    ldy FBUFPT

;; Removes trailing fractional zeroes and an unnecessary decimal point before emitting any exponent.
FOUT11:
    lda FBUFFR-1,y
    dey
    cmp #'0'
    beq FOUT11
    cmp #'.'
    beq FOUT12
    iny

FOUT12:
    lda #'+'
    ldx TENEXP
    beq FOUT17
    bpl FOUT14
    lda #$00
    sec
    sbc TENEXP
    tax
    lda #'-'

FOUT14:
    sta FBUFFR+1,y
    lda #'E'
    sta FBUFFR,y
    txa
    ldx #('0'-1)
    sec

FOUT15:
    inx
    sbc #$0A
    bcs FOUT15
    adc #('0'+10)
    sta FBUFFR+3,y
    txa
    sta FBUFFR+2,y
    lda #$00
    sta FBUFFR+4,y
    beq FOUT20

FOUT19:
    sta FBUFFR-1,y

FOUT17:
    lda #$00
    sta FBUFFR,y

FOUT20:
    lda #<FBUFFR
    ldy #>FBUFFR

FPWRRT:
    rts

.endmacro
