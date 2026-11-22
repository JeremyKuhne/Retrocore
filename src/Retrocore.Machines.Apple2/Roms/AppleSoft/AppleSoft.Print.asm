;; APPLESOFT: PRINT AND CHARACTER OUTPUT
;;
;; PRINT formats expressions, while the shared string and character output routines serve
;; error reporting, listing and other statements.

.include "../Microsoft6502Basic/MsBasic.Print.asm"

.if ENHNCD
    PRINT_CORE TABER, 1, 1, 0
.else
    PRINT_CORE LINCH1, 1, 1, 0
.endif
NCMPOS = $0E

;; Prints a carriage return, then complements A for the callers that test the result.
CRDO:
    lda #$0D
    jsr OUTDO
CRFIN:
    eor #$FF
PRTRTS:
    rts

;; Advances PRINT to the next comma zone, wrapping when necessary.
COMPRT:
.if ENHNCD
    jsr CHKCOL
    bmi LINCHK
.else
    lda TRMPOS
.endif
    cmp #$18
.if ENHNCD
    bcc LINCHK
.else
    bcc COMPR1
.endif
    jsr CRDO
    bne NOTABR
.if ENHNCD
LINCHK:
.else
COMPR1:
.endif
    adc #$10
.if ENHNCD
    and #$F0
    tax
    sec
    bcs TABER2
TABER:
.else
    ; These overlapping instructions implement comma, TAB and SPC entries in the original ROM.
    .byte $29
LINCHK:
    .byte $F0, $85, $24, $90, $19
LINCH1:
.endif
    php
.if ENHNCD
    jsr GTBYTC
    cmp #')'
    bne SNERR4
.else
    .byte $20, $F5
TABER:
    .byte $E6, $C9, $29
    beq TABER1
    jmp SNERR
.endif
TABER1:
    plp
    bcc XSPAC
    dex
.if ENHNCD
TABER2:
    jsr TRMSET
.else
    txa
    sbc TRMPOS
.endif
    bcc NOTABR
ASPAC:
    tax
XSPAC:
    inx
XSPAC2:
    dex
    bne XSPAC1
NOTABR:
    jsr CHRGET
    jmp PRINTC
XSPAC1:
    jsr OUTSPC
    bne XSPAC2
.include "../Microsoft6502Basic/MsBasic.StringOutput.asm"
;; Prints a space.
OUTSPC:
    lda #' '
    .byte $2C                       ; BIT absolute skips OUTQST's LDA

;; Prints a question mark.
OUTQST:
    lda #'?'

;; Sends a character to the Monitor output routine and applies the configured output delay.
;;
;; Printable characters also receive <FLASHB>; output is passed with bit 7 set.
;; In: A = character
;; Out: A = character returned by the Monitor, with bit 7 cleared
;; See: <OUTCH>, <MWAIT>, <SPEEDZ>
OUTDO:
    ora #$80
    cmp #$A0
    bcc OUTLOC
    ora FLASHB
TRYOUT:
OUTLOC:
    jsr OUTCH
    and #$7F
    pha
    lda SPEEDZ
    jsr MWAIT
    pla
GETRTS:
    rts
