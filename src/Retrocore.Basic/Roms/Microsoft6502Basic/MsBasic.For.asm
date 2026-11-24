; Derived from Microsoft's BASIC for 6502 (m6502.asm, MIT license; see LICENSE in this folder).
; MICROSOFT 6502 BASIC: FOR
;
; The platform's next-statement entry follows <NXTCON>. NEXT and the FOR-frame
; search are in separate shared modules.

;; Assigns the initial value and builds a loop frame, replacing an earlier FOR for the same variable.
;;
;; From low to high addresses the <FORSIZ>-byte frame holds <FORTK>, the variable address, the five-byte step, its
;; sign, the five-byte packed limit, the line number and the text pointer after the FOR statement.
;; See: <FNDFOR>, <FORPSH>, <NEXT>
FOR:
    lda #$80
    sta SUBFLG
    jsr LET
    jsr FNDFOR
    bne NOTOL
    txa
    adc #(FORSIZ-3)
    tax
    txs

NOTOL:
    pla
    pla
    lda #(8+ADDITIONAL_PRECISION)
    jsr GETSTK
    jsr DATAN
    clc
    tya
    adc TXTPTR
    pha
    lda TXTPTR+1
    adc #$00
    pha
    lda CURLIN+1
    pha
    lda CURLIN
    pha
    lda #TOTK
    jsr SYNCHR
    jsr CHKNUM
    jsr FRMNUM
    lda FACSGN
    ora #$7F
    and FACHO
    sta FACHO
    lda #<LDFONE
    ldy #>LDFONE
    sta INDEX
    sty INDEX+1
    jmp FORPSH

;; Loads the default step of one, or evaluates the expression after STEP, and completes the FOR frame.
LDFONE:
    lda #<FONE
    ldy #>FONE
    jsr MOVFM
    jsr CHRGOT
    cmp #STEPTK
    bne ONEON
    jsr CHRGET
    jsr FRMNUM

ONEON:
    jsr SIGN
    jsr PUSHF
    lda FORPNT+1
    pha
    lda FORPNT
    pha

NXTCON:
    lda #FORTK
    pha
