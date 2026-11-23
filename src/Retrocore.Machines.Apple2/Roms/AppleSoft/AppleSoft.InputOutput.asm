;; APPLESOFT: GET, INPUT AND READ
;;
;; These statements share variable lookup and conversion but get their values from a key, an input line or
;; DATA statements. The string assignment and output helpers used here precede this module in
;; AppleSoft.Assignment.asm and AppleSoft.Print.asm.

;; Handles a malformed input value: retries INPUT, or reports a syntax error for READ or GET.
;;
;; For READ the reported line is the DATA line; GET is reported as direct. An active ONERR handler receives
;; error code $FE for the INPUT retry path.
;; See: <DOAGIN>, <DATLIN>, <SyntaxError>
TRMNOK:
    lda INPFLG
    beq DOAGIN
    bmi GETDTL
    ldy #$FF
    bne STCURL
GETDTL:
    lda DATLIN
    ldy DATLIN+1
STCURL:
    sta CURLIN
    sty CURLIN+1
SNERR4:
    jmp SNERR
SNERR6:
    pla
TRMNO1:

;; Prints ?REENTER and restores the current statement's text pointer, unless ONERR intercepts the retry.
DOAGIN:
    bit ERRFLG
    bpl TRMNO2
    ldx #$FE
    jmp HANDLE
TRMNO2:
    lda #<TRYAGN
    ldy #>TRYAGN
    jsr STROUT
    lda OLDTXT
    ldy OLDTXT+1
    sta TXTPTR
    sty TXTPTR+1
    rts

;; GET: reads individual keyboard characters into the variables in its list.
;; Errors: ILLEGAL DIRECT when used in direct mode
;; See: <AssignVariableList>, <CQINCH>
GET:
    jsr ERRDIR
GETTTY:
    ldx #$01
    ldy #$02
    lda #$00
    sta BUF+1
    lda #$40
    jsr INPCO1
    rts

;; INPUT: prints an optional quoted prompt and reads values for its variable list.
;;
;; A literal prompt must be followed by a semicolon. Without one INPUT prints a question mark.
;; Errors: ILLEGAL DIRECT when used in direct mode
;; See: <INLIN>, <AssignVariableList::NextVariable>
INPUT:
    cmp #'"'
    bne INPUT1
    jsr STRTXT
    lda #';'
    jsr SYNCHR
    jsr STRPRT
    jmp NOTQTI
INPUT1:
    jsr OUTQST
NOTQTI:
    jsr ERRDIR
    lda #','
    sta BUF-1

; A leading Control-C follows the same stop path as the statement loop.
GETAGN:
    jsr INLIN
    lda BUF
    cmp #$03
    bne INPCON
    jmp ISCCA1

;; Prints a question mark and reads another input line.
QINLIN:
    jsr OUTQST
GINLIN:
    jmp INLIN

.include "../Microsoft6502Basic/MsBasic.VariableInput.asm"
    VariableInput 2, 1, 0, 0, 0, 1
    VariableInputMessages 1, 0
