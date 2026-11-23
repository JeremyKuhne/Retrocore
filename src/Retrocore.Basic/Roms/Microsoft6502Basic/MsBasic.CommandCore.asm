; retrocore: style=strict
; Derived from Microsoft's BASIC for 6502 (m6502.asm, MIT license; see LICENSE in this folder).

.include "MsBasic.Families.asm"

; MICROSOFT 6502 BASIC: ERROR FINISHING, PROGRAM EDITING AND TOKEN STORAGE

;; Emits the common error-message suffix and optional program line number.
.macro ErrorFinish

;; Resets execution state and prints the standard error suffix.
;; See: <ResetStack>, <ReportMessage>
TYPERR:
    jsr ResetStack
    lda #<ERR
    ldy #>ERR

    ;; Prints the message at A/Y and the current line number unless execution is direct.
    ;; In: A = message address low byte, Y = message address high byte
    ;; See: <ERROR>, <Statements::Stop>, <STROUT>, <Float::PrintInLineNumber>, <READY>
    ;; Also: ERRFIN (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc ReportMessage
    jsr STROUT
    ldy CurrentLine+1
    iny
    beq READY
    jsr Float::PrintInLineNumber
    .endproc
.endmacro

;; Emits line-number parsing and the removal of an existing program line.
;; Parameters: source = the two-byte scratch pointer used for the move
.macro DeleteOldLine source

;; Finds the numbered input line and removes its old version when present.
;;
;; No matching line leaves <SourceStart> at the insertion position.
;; See: <ReadLineNumber>, <CRUNCH>, <FindLine>
MAIN1:
    jsr ReadLineNumber
    jsr CRUNCH
    sty Counter
    jsr FindLine
    bcc NODEL
    ldy #$01
    lda (SourceStart),y
    sta source+1
    lda VariablesStart
    sta source
    lda SourceStart+1
    sta Pointer2+1
    lda SourceStart
    dey
    sbc (SourceStart),y
    clc
    adc VariablesStart
    sta VariablesStart
    sta Pointer2
    lda VariablesStart+1
    adc #$FF
    sta VariablesStart+1
    sbc SourceStart+1
    tax
    sec
    lda SourceStart
    sbc VariablesStart
    tay
    bcs QDECT1
    inx
    dec Pointer2+1
QDECT1:
    clc
    adc source
    bcc MLOOP
    dec source+1
    clc
MLOOP:
    lda (source),y
    sta (Pointer2),y
    iny
    bne MLOOP
    inc source+1
    inc Pointer2+1
    dex
    bne MLOOP
.endmacro

;; Emits the common scan and link update for one stored line.
;; Parameters: addHighToY = 1 to add the old high byte to zero in Y instead of adding zero to A
.macro LinkLine addHighToY
    .assert addHighToY = 0 || addHighToY = 1, "addHighToY is 0 or 1."

    ldy #$04
CZLOOP:
    iny
    lda (Pointer1),y
    bne CZLOOP
    iny
    tya
    adc Pointer1
    tax
    ldy #$00
    sta (Pointer1),y
    .if addHighToY
        tya
        adc Pointer1+1
    .else
        lda Pointer1+1
        adc #$00
    .endif
    iny
    sta (Pointer1),y
    stx Pointer1
    sta Pointer1+1
    bcc CHEAD
.endmacro

;; Emits the shared token-storage and quoted-text copy paths.
;; Parameters: inputBase = indexed input buffer base; foldCase = 1 to call the platform's case folder
.macro TokenStore inputBase, foldCase
    .assert foldCase = 0 || foldCase = 1, "foldCase is 0 or 1."

GETBPT:
    ldy TokenizePointer
STUFFH:
    inx
    iny
    sta BUF-5,y
    lda BUF-5,y
    beq CRDONE
    sec
    sbc #':'
    beq COLIS
    cmp #(TOKEN_DATA-':')
    bne NODATT
COLIS:
    sta TokenizeState
NODATT:
    sec
    sbc #(TOKEN_REM-':')
    bne KLOOP
    sta EndDelimiter
STR1:
    .if foldCase
        jsr UPCASE
    .else
        lda inputBase,x
    .endif
    beq STUFFH
    cmp EndDelimiter
    beq STUFFH
STRNG:
    iny
    sta BUF-5,y
    inx
    bne STR1
.endmacro
