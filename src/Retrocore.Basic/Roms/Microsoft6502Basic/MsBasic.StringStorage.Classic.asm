; Derived from Microsoft's BASIC for 6502 (m6502.asm, MIT license; see LICENSE in this folder).
; MICROSOFT 6502 BASIC: UNLINKED STRING-SPACE ALLOCATION
;
; STRING_ALLOCATION invokes this unlinked body. BASIC 4 needs the separate linked implementation.

;; Emits the ordinary unlinked allocation and retry body after <GETSPA>.
;;
;; Equality with <STREND> is accepted. If a zero-length request initially fails the space check,
;; the zero after collection falls through into <GARBA2> a second time rather than retrying.
.macro UNLINKED_STRING_ALLOCATION
TRYAG2:
    pha
    eor #$FF
    sec
    adc FRETOP
    ldy FRETOP+1
    bcs TRYAG3
    dey

TRYAG3:
    cpy STREND+1
    bcc GARBAG
    bne STRFRE
    cmp STREND
    bcc GARBAG

STRFRE:
    sta FRETOP
    sty FRETOP+1
    sta FRESPC
    sty FRESPC+1
    tax
    pla
    rts

GARBAG:
    ldx #<ERROM
    lda GARBFL
    bmi ERRGO2
    jsr GARBA2
    lda #$80
    sta GARBFL
    pla
    bne TRYAG2
.endmacro
