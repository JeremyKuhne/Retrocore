;; Cassette, interpreter and display helpers ($F775-$F7FF).
;;
;; Shape loading and array transfer use model-specific cassette support; enhanced IIe helpers also provide
;; uppercase tokenization and 80-column printing. The shared array lookup and <HTAB> finish the ROM.
;; <LASTWR> reserves $F800-$F863 for the Monitor, outside the Applesoft image. This module follows
;; AppleSoft.HighResolution.asm.

;; Group: Cassette shape loading and model-specific support

;; Loads a shape table from cassette.
;;
;; The enhanced IIe delegates to the internal slot 5 ROM; earlier models read the length, reserve memory below
;; <MEMSIZ>, then read the table. The enhanced entry sets carry to select <SHLOAD> before entering <CALLC5>.
SHLOAD:
.if ENHNCD
    sec
    .byte $90

;; Calls the enhanced IIe internal slot 5 ROM and restores the slot ROM selection.
;; Errors: out of memory if the ROM returns with carry set
CALLC5:
.else
    lda #0
    sta A1H
    sta A2H
    ldy #LINNUM
    sty A1L
    iny
    sty A2L
    jsr MREAD
.endif
    clc
.if ENHNCD
    sta SETINT
    jsr C5ROM
    sta SETSLO
    bcs CALLC1
    rts

CALLC1:
    jmp OMERR

;; Reads the next input-buffer character for enhanced IIe tokenization.
;;
;; If its high bit is set, the current character goes through <UPCASE>; otherwise it uses the next character.
UPNXT:
    lda BUF+1,x
    bpl UPBUF1

;; Uppercases input outside quoted strings and DATA on the enhanced IIe.
;;
;; The conversion path preserves the processor flags from loading the original buffer character.
;; Entry: UPBUF = converts the current buffer character, UPBUF1 = converts A
UPCASE:
    lda ENDCHR
    beq UPBUF5
    cmp #$22
    beq UPBUF5
    lda DORES
    cmp #(DATATK-':')
    beq UPBUF5

UPBUF:
    lda BUF,x

UPBUF1:
    php
    cmp #$61
    bcc UPBUF4
    and #$5F

UPBUF4:
    plp
    rts

UPBUF5:
    lda BUF,x
    rts

;; Prints a space followed by a line number on the enhanced IIe.
SPCLIN:
.else
    lda MEMSIZ
    tax
    dex
    stx A2L
    sbc LINNUM
.endif
    pha
.if ENHNCD
    lda #$20
    jsr OUTDO
.else
    lda MEMSIZ+1
    tay
    inx
    bne SHLOD1
    dey

SHLOD1:
    sty A2H
    sbc LINNUM+1
    cmp STREND+1
    bcc SHLOD2
    bne SHLOD3

SHLOD2:
    jmp OMERR

SHLOD3:
    sta MEMSIZ+1
    sta FRETOP+1
    sta A1H
    sta SHPTBL+1
.endif
    pla
.if ENHNCD
    jmp LINPRT

;; Compares the output column against the print-zone limit on the enhanced IIe.
;;
;; In 80-column mode it uses <OURCH> and 73; otherwise it uses <TRMPOS> and 33.
;; Out: carry = set when the column reaches the applicable limit
CHKCOL:
    lda TRMPOS
    cmp #$21
    bit RD80VI
    bpl CHKCO1
    lda OURCH
    cmp #$49

CHKCO1:
.else
    sta SHPTBL
    sta MEMSIZ
    sta FRETOP
    sta A1L
    jsr RD2BIT
    lda #3
    jmp MREAD+5

;; Sets the cassette transfer range for an array on unenhanced models.
;;
;; It uses the array descriptor at <LOWTR>, the stored length in <LINNUM>, and <FMAPT1> to locate the data.
SETA2:
    clc
    lda LOWTR
    adc LINNUM
    sta A2L
    lda LOWTR+1
    adc LINNUM+1
    sta A2H
    ldy #4
    lda (LOWTR),y
    jsr FMAPT1
    lda HIGHDS
    sta A1L
    lda HIGHDS+1
    sta A1H
.endif
    rts
.if ENHNCD

;; Computes the enhanced IIe print position relative to the current column.
;;
;; In 80-column mode it subtracts <OURCH> with the incoming carry; otherwise it updates and subtracts <TRMPOS>.
;; Entry: TRMSE1 = updates TRMPOS and subtracts it from X
;; Out: A = relative position, carry = set when no borrow occurs
TRMSET:
    txa
    bit RD80VI
    bmi TRMSE3
    .byte $2C                       ; BIT absolute skips the next two bytes

TRMSE1:
    sta TRMPOS
    sec
    txa
    sbc TRMPOS

TRMSE2:
    rts

TRMSE3:
    sbc OURCH
    rts
    .byte $00, $00, $00, $00
.else
.endif

;; Group: Array lookup and horizontal tab

;; Finds an array for cassette STORE or RECALL, then checks its type through <VARTIO>.
GETARY:
    lda #$40
    sta SUBFLG
    jsr PTRGET
    lda #0
    sta SUBFLG
    jmp VARTIO

;; Implements one-based HTAB, wrapping across screen lines as needed.
;;
;; The enhanced IIe uses the larger of 40 and the window width; earlier models wrap at 40.
HTAB:
    jsr GETBYT
    dex
.if ENHNCD

HTAB1:
    lda #$28
    cmp WNDWDT
    bcs HTAB12
    lda WNDWDT

HTAB12:
    jsr TRMSE1
    stx TRMPOS
    bcc TRMSE2
    tax
.else
    txa

HTAB11:
    cmp #$28
    bcc HTAB13
    sbc #$28
    pha
.endif
    jsr CRDO
.if ENHNCD
    bne HTAB1
.else
    pla
    jmp HTAB11

HTAB13:
    sta TRMPOS
    rts
    ; The final ROM byte differs on the II Plus.
    .byte $CB, $D2
.if APLPLS
    .byte $D7
.else
    .byte $78
.endif
.endif

; Monitor workspace follows the ROM.

;; The reserved 100-byte Monitor workspace following the $F7FF end of the Applesoft ROM.
LASTWR:
    .res 100
