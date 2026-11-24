; Derived from Microsoft's BASIC for 6502 (m6502.asm, MIT license; see LICENSE in this folder).
; MICROSOFT 6502 BASIC: READ AND VARIABLE INPUT
;
; VARIABLE_INPUT follows the platform's GET and INPUT entries. VARIABLE_INPUT_MESSAGES emits the
; immediately following warning strings. Both macros are emitted before NEXT.
;
; AppleSoft:           VARIABLE_INPUT 2, 1, 0, 0, 0, 1; VARIABLE_INPUT_MESSAGES 1, 0
; PET BASIC 1:         VARIABLE_INPUT 0, 0, 1, 1, 1, 0; VARIABLE_INPUT_MESSAGES 0, 1
; PET BASIC 2:         VARIABLE_INPUT 2, 0, 0, 0, 1, 0; VARIABLE_INPUT_MESSAGES 0, 1
; PET BASIC 4:         VARIABLE_INPUT 2, 0, 0, 0, 1, 0; VARIABLE_INPUT_MESSAGES 0, 0
;
; The early GETSTR helper is external: it stores CHARAC, advances the cursor, removes its JSR return
; address, and jumps back to RESETC with A = 0. BASIC 1 supplies it in the editor-ROM patches.

;; Emits READ and the common GET, INPUT and READ variable-processing loop.
;; Parameters: bufferPage = the page containing <BUF>, maskGetBit7 = 1 to clear bit 7 of a GET character,
;;   getPointerYFirst = 1 to load the GET buffer pointer's high byte before its low byte,
;;   patchedGetString = 1 to use the early `GETSTR` patch, channelInput = 1 to honor input channels,
;;   blankNumericRetry = 1 to retry an empty terminal INPUT numeric value
.macro VARIABLE_INPUT bufferPage, maskGetBit7, getPointerYFirst, patchedGetString, channelInput, blankNumericRetry
    .assert bufferPage >= 0 && bufferPage <= 255, "bufferPage must fit in a byte."
    .assert BUF > 0 && BUF / 256 = bufferPage, "BUF must be in bufferPage and have a preceding byte."
    .assert maskGetBit7 = 0 || maskGetBit7 = 1, "maskGetBit7 must be 0 or 1."
    .assert getPointerYFirst = 0 || getPointerYFirst = 1, "getPointerYFirst must be 0 or 1."
    .assert patchedGetString = 0 || patchedGetString = 1, "patchedGetString must be 0 or 1."
    .assert channelInput = 0 || channelInput = 1, "channelInput must be 0 or 1."
    .assert blankNumericRetry = 0 || blankNumericRetry = 1, "blankNumericRetry must be 0 or 1."
    .assert patchedGetString = 0 || bufferPage = 0, "The early GETSTR patch requires a page-zero buffer."
.if getPointerYFirst
    .assert <(BUF-1) != 0, "The GET buffer pointer's low byte must make its branch unconditional."
.elseif bufferPage
    .assert >(BUF-1) != 0, "The GET buffer pointer's high byte must make its branch unconditional."
.endif

;; Reads values for a variable list from DATA, starting at the saved <DATPTR>.
;; In: decimal = clear
;; See: <INPCO1>, <DATLOP>, <RESTOR>
READ:
    ldx DATPTR
    ldy DATPTR+1
.if bufferPage
    lda #$98
    .byte $2C                   ; BIT absolute skips the INPUT flag load
.else
    .byte $A9                   ; LDA immediate consumes INPCON's TYA opcode as $98
.endif

;; Starts an INPUT variable list with X/Y pointing to its input buffer.
;; In: X = cursor low byte, Y = cursor high byte (zero for a page-zero buffer)
INPCON:
.if bufferPage
    lda #$00
.else
    tya
.endif

;; Assigns a GET, INPUT or READ value to each variable in the statement's list.
;;
;; <INPPTR> tracks the input cursor while <VARTXT> saves the variable-list position. GET obtains one
;; character when its sentinel is reached; READ searches subsequent DATA statements. A comma in the
;; variable list continues the loop. The early PET uses its `GETSTR` patch; AppleSoft masks GET characters
;; and retries an empty terminal numeric INPUT. A selected file channel suppresses terminal prompts and warnings.
;; In: A = source flag ($40 GET, $00 INPUT, $98 READ), X = cursor low byte, Y = cursor high byte,
;;   decimal = clear
;; See: <PTRGET>, <INPCOM>, <QINTGR>, <DATLOP>
INPCO1:
    sta INPFLG
    stx INPPTR
    sty INPPTR+1

;; Resolves the next variable, then switches from the variable list to the saved input cursor.
INLOOP:
    jsr PTRGET
    sta FORPNT
    sty FORPNT+1
    lda TXTPTR
    ldy TXTPTR+1
    sta VARTXT
    sty VARTXT+1
    ldx INPPTR
    ldy INPPTR+1
    stx TXTPTR
    sty TXTPTR+1
    jsr CHRGOT
    bne DATBK1
    bit INPFLG
    bvc QDATA
    jsr CZGETL
.if maskGetBit7
    and #$7F
.endif
    sta BUF
.if getPointerYFirst
    ldy #>(BUF-1)
    ldx #<(BUF-1)
    bne DATBK
.else
    ldx #<(BUF-1)
    ldy #>(BUF-1)
.if bufferPage
    bne DATBK
.else
    beq DATBK
.endif
.endif

;; Continues READ at the next DATA statement or obtains another INPUT line.
QDATA:
    bmi DATLOP
.if channelInput
    lda CHANNL
    bne GETNTH
.endif
    jsr OUTQST
GETNTH:
    jsr QINLIN
DATBK:
    stx TXTPTR
    sty TXTPTR+1

;; Starts conversion of the next string or numeric value at the input cursor.
DATBK1:
    jsr CHRGET
    bit VALTYP
.if blankNumericRetry
    bpl NOWGE2
.else
    bpl NUMINS
.endif
    bit INPFLG
    bvc SETQUT
.if patchedGetString
    lda #$00
    jsr GETSTR
    nop
.else
    inx
    stx TXTPTR
    lda #$00
    sta CHARAC
    beq RESETC
.endif

;; Sets quote delimiters, or colon and comma delimiters for an unquoted string.
SETQUT:
    sta CHARAC
    cmp #'"'
    beq NOWGET
    lda #':'
    sta CHARAC
    lda #','

;; Uses the current text position as the start of an unquoted or single-character GET string.
;; In: A = ending delimiter, TXTPTR = first character
RESETC:
    clc

;; Builds and assigns a string from the input cursor.
;;
;; Carry set skips an opening quote; carry clear starts at the current character. <STRLT2> makes the
;; descriptor, <ST2TXT> advances the input cursor, and <INPCOM> assigns the result.
;; In: A = ending delimiter, TXTPTR = text position, carry = set to skip a quote, decimal = clear
NOWGET:
    sta ENDCHR
    lda TXTPTR
    ldy TXTPTR+1
    adc #$00
    bcc NOWGE1
    iny
NOWGE1:
    jsr STRLT2
    jsr ST2TXT
    jsr INPCOM
    jmp STRDN2

.if blankNumericRetry
;; Saves the numeric character while checking whether the input buffer starts with zero.
NOWGE2:
    pha
    lda BUF
    beq TRMOK1
NOWGE3:
    pla
.endif

;; Converts and assigns a numeric value, including integer variables.
NUMINS:
    jsr FIN
    lda INTFLG
    jsr QINTGR

;; Validates the input terminator and restores the variable-list cursor.
;;
;; A zero or colon is accepted by <CHRGOT>'s zero flag; a comma is also accepted. Otherwise the
;; platform's malformed-input handler decides whether to retry or report an error.
STRDN2:
    jsr CHRGOT
    beq TRMOK
    cmp #','
    beq TRMOK
    jmp TRMNOK
TRMOK:
    lda TXTPTR
    ldy TXTPTR+1
    sta INPPTR
    sty INPPTR+1
    lda VARTXT
    ldy VARTXT+1
    sta TXTPTR
    sty TXTPTR+1
    jsr CHRGOT
    beq VAREND
    jsr CHKCOM
    jmp INLOOP
.if blankNumericRetry

;; Retries an empty numeric INPUT, or restores the saved character for READ and GET.
;; See: <SNERR6>, <NOWGE3>
TRMOK1:
    lda INPFLG
    bne NOWGE3
    jmp SNERR6
.endif

;; Searches forward for a DATA statement, remembering each new line number in <DATLIN>.
;;
;; <DATAN> skips statements, including quoted colons. A zero high byte in the next line link reports OUT OF DATA.
;; See: <DATBK1>
DATLOP:
    jsr DATAN
    iny
    tax
    bne NOWLIN
    ldx #ERROD
    iny
    lda (TXTPTR),y
    beq ERRGO5
    iny
    lda (TXTPTR),y
    sta DATLIN
    iny
    lda (TXTPTR),y
    iny
    sta DATLIN+1
NOWLIN:
    lda (TXTPTR),y
    tax
    jsr ADDON
    cpx #DATATK
    bne DATLOP
    jmp DATBK1

;; Saves READ's cursor or warns about extra terminal INPUT characters.
;;
;; Channel input suppresses the warning. A zero at the input cursor needs no warning.
VAREND:
    lda INPPTR
    ldy INPPTR+1
    ldx INPFLG
    bpl VARY0
    jmp RESFIN
VARY0:
    ldy #$00
    lda (INPPTR),y
    beq INPRTS
.if channelInput
    lda CHANNL
    bne INPRTS
.endif
    lda #<EXIGNT
    ldy #>EXIGNT
    jmp STROUT
INPRTS:
    rts
.endmacro

;; Emits the extra-input warning and retry messages immediately after VARIABLE_INPUT.
;; Parameters: shortRetry = 1 for "?REENTER", 0 for "?REDO FROM START";
;;   lineFeed = 1 to follow each carriage return with a line feed
.macro VARIABLE_INPUT_MESSAGES shortRetry, lineFeed
    .assert shortRetry = 0 || shortRetry = 1, "shortRetry must be 0 or 1."
    .assert lineFeed = 0 || lineFeed = 1, "lineFeed must be 0 or 1."

;; Zero-terminated warning for extra terminal INPUT values.
EXIGNT:
    .byte "?EXTRA IGNORED", $0D
.if lineFeed
    .byte $0A
.endif
    .byte $00

;; Zero-terminated prompt for retrying malformed terminal INPUT.
TRYAGN:
.if shortRetry
    .byte "?REENTER", $0D
.else
    .byte "?REDO FROM START", $0D
.endif
.if lineFeed
    .byte $0A
.endif
    .byte $00
.endmacro
