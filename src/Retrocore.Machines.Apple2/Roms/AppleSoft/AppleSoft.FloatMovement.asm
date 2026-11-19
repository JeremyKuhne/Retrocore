;; APPLE II APPLESOFT FLOATING-POINT MOVEMENT
;;
;; These routines pack and unpack five-byte numbers and move the unpacked <FAC>, ARG and arithmetic result.
;; Packing rounds <FAC> using <FACOV>; zero is identified by its exponent, not by the other bytes.
;;
;; Part of AppleSoft.asm; it follows AppleSoft.FloatArithmetic.asm.

;; Moves the four-byte arithmetic result to <FAC> and normalizes it.
;; See: <NORMAL>
MOVFR:
    lda     RESHO
    sta     FACHO
    lda     RESMOH
    sta     FACMOH
    lda     RESMO
    sta     FACMO
    lda     RESLO
    sta     FACLO
    jmp     NORMAL

;; Unpacks a five-byte memory value into <FAC> and clears <FACOV>.
;; In: A = low byte of packed value address, Y = high byte of packed value address
;; Out: A = FAC exponent, zero = set when the exponent is zero
MOVFM:
    sta     INDEX1
    sty     INDEX1+1
    ldy     #$04
    lda     (INDEX1),y
    sta     FACLO
    dey
    lda     (INDEX1),y
    sta     FACMO
    dey
    lda     (INDEX1),y
    sta     FACMOH
    dey
    lda     (INDEX1),y
    sta     FACSGN
    ora     #$80
    sta     FACHO
    dey
    lda     (INDEX1),y
    sta     FACEXP
    sty     FACOV
    rts

;; Rounds and packs <FAC> into the temporary at <TEMPF2>.
;; See: <MOVMF>
MOV2F:
    ldx     #TEMPF2
    .byte   $2C                     ; BIT absolute skips the following LDX immediate

;; Rounds and packs <FAC> into the temporary at <TEMPF1>.
;; See: <MOVMF>
MOV1F:
    ldx     #TEMPF1

MOVML:
    ldy     #$00
    beq     MOVMF

;; Rounds and packs <FAC> into the variable addressed by <FORPNT>.
;; See: <MOVMF>
MOVVF:
    ldx     FORPNT
    ldy     FORPNT+1

;; Rounds and packs <FAC> into five bytes at Y:X.
;; In: X = low byte of destination address, Y = high byte of destination address
;; Out: Y = 0, FACOV = 0
;; See: <ROUND>
MOVMF:
    jsr     ROUND
    stx     INDEX1
    sty     INDEX1+1
    ldy     #$04
    lda     FACLO
    sta     (INDEX1),y
    dey
    lda     FACMO
    sta     (INDEX1),y
    dey
    lda     FACMOH
    sta     (INDEX1),y
    dey
    lda     FACSGN
    ora     #$7F
    and     FACHO                   ; replace the implicit high bit with the sign bit
    sta     (INDEX1),y
    dey
    lda     FACEXP
    sta     (INDEX1),y
    sty     FACOV
    rts

;; Copies unpacked ARG to <FAC>, clearing <FACOV>.
;; Entry: MOVFA1 = uses A as the FAC sign instead of ARGSGN
MOVFA:
    lda     ARGSGN

MOVFA1:
    sta     FACSGN
    ldx     #$05

MOVFAL:
    lda     ARGEXP-1,x
    sta     FACEXP-1,x
    dex
    bne     MOVFAL
    stx     FACOV
    rts

;; Rounds <FAC> and copies it into ARG.
;; Entry: MOVEF = copies FAC without first rounding it
;; See: <ROUND>
MOVAF:
    jsr     ROUND

MOVEF:
    ldx     #$06

MOVAFL:
    lda     FACEXP-1,x
    sta     ARGEXP-1,x
    dex
    bne     MOVAFL
    stx     FACOV

MOVRTS:
    rts

;; Rounds the <FAC> mantissa upward when bit 7 of <FACOV> is set.
;;
;; A carry out of the mantissa shifts it right and increments the exponent. A zero exponent needs no rounding.
;; See: <INCFAC>, <RNDSHF>
ROUND:
    lda     FACEXP
    beq     MOVRTS
    asl     FACOV
    bcc     MOVRTS

INCRND:
    jsr     INCFAC
    bne     MOVRTS
    jmp     RNDSHF
