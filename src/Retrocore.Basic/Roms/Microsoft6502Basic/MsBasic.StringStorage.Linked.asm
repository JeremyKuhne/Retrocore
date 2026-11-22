; COMMODORE BASIC 4: LINKED STRING-SPACE ALLOCATION
;
; STRING_ALLOCATION invokes this BASIC 4 body before the BASIC 4 linked collector.
; It is not interchangeable with the ordinary Microsoft collector.

;; Emits BASIC 4's linked allocation and retry body after <GETSPA>.
;;
;; A nonempty string gets a link containing its length followed by $FF, marking it as garbage until
;; assignment. Equality with <STREND> is accepted. A zero-length request returns immediately with
;; X = 0 and Y unchanged, without changing <FRETOP> or <FRESPC> or creating a link.
.macro LINKED_STRING_ALLOCATION
TRYAG2:
    tax
    beq GETRTS
    pha
    lda FRETOP
    sec
    sbc #$02
    ldy FRETOP+1
    bcs TRYAG3
    dey

TRYAG3:
    sta INDEX
    sty INDEX+1
    txa
    eor #$FF
    sec
    adc INDEX
    bcs TRYAG4
    dey

TRYAG4:
    cpy STREND+1
    bcc GARBAG
    bne STRFRE
    cmp STREND
    bcc GARBAG

STRFRE:
    sta FRESPC
    sty FRESPC+1
    ldy #$01
    lda #$FF
    sta (INDEX),y
    dey
    pla
    sta (INDEX),y
    ldx FRESPC
    ldy FRESPC+1
    stx FRETOP
    sty FRETOP+1

GETRTS:
    rts

GARBAG:
    ldx #<ERROM
    lda GARBFL
    bmi ERRGO2
    jsr GARBA2
    sec
    ror GARBFL
    pla
    bne TRYAG2
.endmacro
