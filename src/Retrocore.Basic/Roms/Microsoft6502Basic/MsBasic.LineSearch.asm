; Derived from Microsoft's BASIC for 6502 (m6502.asm, MIT license; see LICENSE in this folder).
; MICROSOFT 6502 BASIC: PROGRAM LINE SEARCH

;; Finds the stored program line equal to or immediately after <LINNUM>.
;; In: LINNUM = line number to find
;; Out: LOWTR = link field of the matching or following line or the end marker, carry = set for an exact match
;; Entry: FNDLNC = searches from the line at A (low) and X (high)
FNDLIN:
    lda TXTTAB
    ldx TXTTAB+1

FNDLNC:
    ldy #$01
    sta LOWTR
    stx LOWTR+1
    lda (LOWTR),y
    beq FLINRT
    iny
    iny
    lda LINNUM+1
    cmp (LOWTR),y
    bcc FLNRTS
    beq FNDLO1
    dey
    bne AFFRTS

FNDLO1:
    lda LINNUM
    dey
    cmp (LOWTR),y
    bcc FLNRTS
    beq FLNRTS

AFFRTS:
    dey
    lda (LOWTR),y
    tax
    dey
    lda (LOWTR),y
    bcs FNDLNC

FLINRT:
    clc

FLNRTS:
    rts
