; COMMODORE BASIC: GET AND INPUT CHANNELS

;; Emits GET, INPUT# and channel-release entries.
;; Parameters: bufferPage = zero for a page-zero input buffer, or the nonzero buffer page
.macro COMMODORE_CHANNEL_INPUT bufferPage
    .assert bufferPage >= 0 && bufferPage <= 255, "bufferPage must fit in a byte."

;; Reads characters into the variable list, optionally from a numbered input channel.
;; Errors: ILLEGAL DIRECT when used in direct mode
GET:
    jsr ERRDIR
    cmp #'#'
    bne GETTTY
    jsr CHRGET
    jsr GETBYT
    lda #','
    jsr SYNCHR
    jsr CQOIN
    stx CHANNL

;; Starts GET with an empty input-buffer sentinel.
GETTTY:
    ldx #<(BUF+1)
    ldy #>(BUF+1)
.if bufferPage
    lda #$00
    sta BUF+1
.else
    sty BUF+1
.endif
    lda #$40
    jsr INPCO1
    ldx CHANNL
    bne IORELE
    rts

;; Reads an INPUT# variable list and then restores the default channels.
INPUTN:
    jsr GETBYT
    lda #','
    jsr SYNCHR
    jsr CQOIN
    stx CHANNL
    jsr NOTQTI

;; Restores the default channels after channel input or output.
IODONE:
    lda CHANNL

;; Restores the default channels and clears <CHANNL>.
IORELE:
    jsr CQCCHN
    ldx #$00
    stx CHANNL
    rts
.endmacro

;; Emits the INPUT statement through line acquisition.
;; Parameters: suppressWait = 1 to clear the output-wait flag, statusMask = channel error bits,
;;             revisedEof = 1 to use the revised BASIC 4 end-of-file helper,
;;             editorPatch = 1 to use the BASIC 1 editor-ROM stop helper,
;;             localStopLabel = 1 to expose the BASIC 4 stop entry
.macro COMMODORE_INPUT_STATEMENT suppressWait, statusMask, revisedEof, editorPatch, localStopLabel
    .assert suppressWait = 0 || suppressWait = 1, "suppressWait is 0 or 1."
    .assert statusMask = 2 || statusMask = 3, "statusMask is 2 or 3."
    .assert revisedEof = 0 || revisedEof = 1, "revisedEof is 0 or 1."
    .assert editorPatch = 0 || editorPatch = 1, "editorPatch is 0 or 1."
    .assert localStopLabel = 0 || localStopLabel = 1, "localStopLabel is 0 or 1."
    .assert editorPatch = 0 || localStopLabel = 0, "The stop entry is either local or in the editor ROM."

;; Reads values for an INPUT statement from the keyboard or the selected channel.
;;
;; An optional quoted prompt is printed first. Terminal input receives a question-mark prompt and a
;; blank line stops the program; a file error releases the channel and skips to the next statement.
;; The revised BASIC 4 ROM delegates blank-line and end-of-file handling to its editor-ROM helper.
INPUT:
.if suppressWait
    lsr CNTWFL
.endif
    cmp #'"'
    bne NOTQTI
    jsr STRTXT
    lda #';'
    jsr SYNCHR
    jsr STRPRT
NOTQTI:
    jsr ERRDIR
    lda #','
    sta BUF-1
GETAGN:
    jsr QINLIN
    lda CHANNL
    beq BUFFUL
    lda CQSTAT
    and #statusMask
    beq BUFFUL
    jsr IODONE
    jmp DATA
BUFFUL:
    lda BUF
    bne INPCON
.if revisedEof
    jmp INPNUL
    nop
.else
    lda CHANNL
    bne GETAGN
.endif
.if editorPatch
    jmp INPSTP
.else
.if localStopLabel
INPSTP:
.endif
    clc
    jmp STPEND
.endif

;; Reads an input line, prompting only when the keyboard is selected.
QINLIN:
    lda CHANNL
    bne GINLIN
    jsr OUTQST
    jsr OUTSPC
GINLIN:
    jmp INLIN
.endmacro

;; Emits malformed-input handling before the GET entry.
;; Parameters: editorPatch = 1 to select the earlier editor-ROM line-number helper
.macro COMMODORE_INPUT_ERROR editorPatch
    .assert editorPatch = 0 || editorPatch = 1, "editorPatch is 0 or 1."

;; Retries malformed terminal INPUT, or reports an error for READ, GET or file INPUT.
;;
;; READ reports the DATA line, GET reports a direct line, and file INPUT reports BAD DATA. Terminal
;; INPUT prints the retry message and restores <TXTPTR> to the start of the current statement.
;; In: INPFLG = input source, CHANNL = selected channel
;; Out: TXTPTR = restored statement position when retrying, CURLIN = error line for READ or GET
;; Errors: SYNTAX ERROR for READ or GET; BAD DATA for file INPUT
TRMNOK:
    lda INPFLG
    beq TRMNO1
.if editorPatch
    jsr GETDTL
    nop
.else
    bmi GETDTL
    ldy #$FF
    bne STCURL
GETDTL:
    lda DATLIN
    ldy DATLIN+1
.endif
STCURL:
    sta CURLIN
    sty CURLIN+1
SNERR4:
    jmp SNERR
TRMNO1:
    lda CHANNL
    beq DOAGIN
    ldx #<ERRBD
    jmp ERROR
DOAGIN:
    lda #<TRYAGN
    ldy #>TRYAGN
    jsr STROUT
    lda OLDTXT
    ldy OLDTXT+1
    sta TXTPTR
    sty TXTPTR+1
    rts
.endmacro
