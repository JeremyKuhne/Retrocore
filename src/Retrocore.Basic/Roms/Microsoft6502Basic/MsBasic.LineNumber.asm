; MICROSOFT 6502 BASIC: DECIMAL LINE NUMBERS

;; Reads a decimal line number from the current text position, rejecting values at or above 64000.
;; In: A = current character, carry = clear for a digit
;; Out: LINNUM = line number, TXTPTR = terminating character, A = terminating character, carry = set
LINGET:
    ldx #$00
    stx LINNUM
    stx LINNUM+1

MORLIN:
    bcs ONGRTS
    sbc #('0'-1)
    sta CHARAC
    lda LINNUM+1
    sta INDEX
    cmp #$19
    bcs SNERR3
    lda LINNUM
    asl a
    rol INDEX
    asl a
    rol INDEX
    adc LINNUM
    sta LINNUM
    lda INDEX
    adc LINNUM+1
    sta LINNUM+1
    asl LINNUM
    rol LINNUM+1
    lda LINNUM
    adc CHARAC
    sta LINNUM
    bcc NXTLGC
    inc LINNUM+1

NXTLGC:
    jsr CHRGET
    jmp MORLIN
