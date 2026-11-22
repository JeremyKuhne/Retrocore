; MICROSOFT 6502 BASIC: ERROR FINISHING, PROGRAM EDITING AND TOKEN STORAGE

;; Emits the common error-message suffix and optional program line number.
.macro BASIC_ERROR_FINISH

;; Resets execution state and prints the standard error suffix.
;; See: <STKINI>, <ERRFIN>
TYPERR:
    jsr STKINI
    lda #<ERR
    ldy #>ERR

;; Prints the message at A/Y and the current line number unless execution is direct.
;; In: A = message address low byte, Y = message address high byte
;; See: <ERROR>, <STOP>, <STROUT>, <INPRT>, <READY>
ERRFIN:
    jsr STROUT
    ldy CURLIN+1
    iny
    beq READY
    jsr INPRT
.endmacro

;; Emits line-number parsing and the removal of an existing program line.
;; Parameters: source = the two-byte scratch pointer used for the move
.macro BASIC_DELETE_OLD_LINE source

;; Finds the numbered input line and removes its old version when present.
;;
;; No matching line leaves <LOWTR> at the insertion position.
;; See: <LINGET>, <CRUNCH>, <FNDLIN>
MAIN1:
    jsr LINGET
    jsr CRUNCH
    sty COUNT
    jsr FNDLIN
    bcc NODEL
    ldy #$01
    lda (LOWTR),y
    sta source+1
    lda VARTAB
    sta source
    lda LOWTR+1
    sta INDEX2+1
    lda LOWTR
    dey
    sbc (LOWTR),y
    clc
    adc VARTAB
    sta VARTAB
    sta INDEX2
    lda VARTAB+1
    adc #$FF
    sta VARTAB+1
    sbc LOWTR+1
    tax
    sec
    lda LOWTR
    sbc VARTAB
    tay
    bcs QDECT1
    inx
    dec INDEX2+1
QDECT1:
    clc
    adc source
    bcc MLOOP
    dec source+1
    clc
MLOOP:
    lda (source),y
    sta (INDEX2),y
    iny
    bne MLOOP
    inc source+1
    inc INDEX2+1
    dex
    bne MLOOP
.endmacro

;; Emits the common scan and link update for one stored line.
;; Parameters: addHighToY = 1 to add the old high byte to zero in Y instead of adding zero to A
.macro BASIC_LINK_LINE addHighToY
    .assert addHighToY = 0 || addHighToY = 1, "addHighToY is 0 or 1."

    ldy #$04
CZLOOP:
    iny
    lda (INDEX),y
    bne CZLOOP
    iny
    tya
    adc INDEX
    tax
    ldy #$00
    sta (INDEX),y
.if addHighToY
    tya
    adc INDEX+1
.else
    lda INDEX+1
    adc #$00
.endif
    iny
    sta (INDEX),y
    stx INDEX
    sta INDEX+1
    bcc CHEAD
.endmacro

;; Emits the shared token-storage and quoted-text copy paths.
;; Parameters: inputBase = indexed input buffer base; foldCase = 1 to call the platform's case folder
.macro BASIC_TOKEN_STORE inputBase, foldCase
    .assert foldCase = 0 || foldCase = 1, "foldCase is 0 or 1."

GETBPT:
    ldy BUFPTR
STUFFH:
    inx
    iny
    sta BUF-5,y
    lda BUF-5,y
    beq CRDONE
    sec
    sbc #':'
    beq COLIS
    cmp #(DATATK-':')
    bne NODATT
COLIS:
    sta DORES
NODATT:
    sec
    sbc #(REMTK-':')
    bne KLOOP
    sta ENDCHR
STR1:
.if foldCase
    jsr UPCASE
.else
    lda inputBase,x
.endif
    beq STUFFH
    cmp ENDCHR
    beq STUFFH
STRNG:
    iny
    sta BUF-5,y
    inx
    bne STR1
.endmacro
