; MICROSOFT 6502 BASIC: RELATIONAL OPERATORS

;; Emits the numeric and string comparison entries.
;; Parameters: trueByte = $01 for a true result of one, $FF for a true result of minus one
.macro RELATIONAL_OPERATORS trueByte
    .assert trueByte = $01 || trueByte = $FF, "trueByte is $01 or $FF."

;; Compares numeric or string operands and applies the relation mask.
;; In: carry = set for an argument string or clear for a number, VALTYP = accumulator type,
;;   DOMASK = relation mask
;; Out: FAC = zero or the variant's true value
;; Errors: TYPE MISMATCH if the operand types differ
;; See: <STRCMP>, <FCOMP>
DOREL:
    jsr CHKVAL
    bcs STRCMP
    lda ARGSGN
    ora #$7F
    and ARGHO
    sta ARGHO
    lda #<ARGEXP
    ldy #$00
    jsr FCOMP
    tax
    jmp QCOMP

;; Compares bytes up to the shorter string's length, then compares lengths if needed.
;; In: ARGMO/ARGLO = argument descriptor address, FACMO/FACLO = accumulator descriptor address,
;;   DOMASK = relation mask
;; Out: FAC = zero or the variant's true value
STRCMP:
    lda #$00
    sta VALTYP
    dec OPMASK
    jsr FREFAC
    sta DSCTMP
    stx DSCTMP+1
    sty DSCTMP+2
    lda ARGMO
    ldy ARGLO
    jsr FRETMP
    stx ARGMO
    sty ARGLO
    tax
    sec
    sbc DSCTMP
    beq STASGN
    lda #$01
    bcc STASGN
    ldx DSCTMP
    lda #$FF
STASGN:
    sta FACSGN
    ldy #$FF
    inx
NXTCMP:
    iny
    dex
    bne GETCMP
    ldx FACSGN
QCOMP:
    bmi DOCMP
    clc
    bcc DOCMP
GETCMP:
    lda (ARGMO),y
    cmp (DSCTMP+1),y
    beq NXTCMP
    ldx #$FF
    bcs DOCMP
    ldx #$01
DOCMP:
    inx
    txa
    rol a
    and DOMASK
    beq GOFLOT
    lda #trueByte
GOFLOT:
    jmp FLOAT
.endmacro
