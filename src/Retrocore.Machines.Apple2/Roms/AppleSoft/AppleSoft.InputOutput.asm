;; APPLESOFT: GET, INPUT AND READ
;;
;; These statements share variable lookup and conversion but get their values from a key, an input line or
;; DATA statements. The string assignment and output helpers used here precede this module in
;; AppleSoft.Assignment.asm and AppleSoft.Print.asm.

;; Handles a malformed input value: retries INPUT, or reports a syntax error for READ or GET.
;;
;; For READ the reported line is the DATA line; GET is reported as direct. An active ONERR handler receives
;; error code $FE for the INPUT retry path.
;; See: <DOAGIN>, <DATLIN>, <SNERR>
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
;; See: <INPCO1>, <CQINCH>
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
;; See: <INLIN>, <INLOOP>
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

;; READ: assigns values from DATA statements, continuing from the saved <DATPTR>.
;; See: <DATLOP>, <RESTOR>
READ:
    ldx DATPTR
    ldy DATPTR+1
    lda #$98
    .byte $2C                       ; BIT absolute skips the INPUT flag load
INPCON:
    lda #$00

;; Shared GET, INPUT and READ loop, with A selecting the source and X/Y holding its cursor.
;;
;; <INPPTR> tracks the source while <VARTXT> saves the variable-list position. Each value is converted and
;; assigned according to the variable type; a comma advances to the next variable. GET starts at an empty sentinel.
;; In: A = source flag ($40 GET, $00 INPUT, $98 READ), X = source low byte, Y = source high byte
;; See: <PTRGET>, <INPCOM>, <QINTGR>
INPCO1:
    sta INPFLG
    stx INPPTR
    sty INPPTR+1
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
    jsr CQINCH
    and #$7F
    sta BUF
    ldx #$FF
    ldy #$01
    bne DATBK
QDATA:
    bmi DATLOP
    jsr OUTQST
GETNTH:
    jsr QINLIN
DATBK:
    stx TXTPTR
    sty TXTPTR+1
DATBK1:
    jsr CHRGET
    bit VALTYP
    bpl NOWGE2
    bit INPFLG
    bvc SETQUT
    inx
    stx TXTPTR
    lda #$00
    sta CHARAC
    beq RESETC
SETQUT:
    sta CHARAC
    cmp #'"'
    beq NOWGET
    lda #':'
    sta CHARAC
    lda #','
RESETC:
    clc
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
NOWGE2:
    pha
    lda BUF
    beq TRMOK1
NOWGE3:
    pla
NUMINS:
    jsr FIN
    lda INTFLG
    jsr QINTGR
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
TRMOK1:
    lda INPFLG
    bne NOWGE3
    jmp SNERR6

;; Searches forward for the next DATA statement, remembering each new line number in <DATLIN>.
;;
;; It uses <DATAN> to skip statements and reports OUT OF DATA at the end of the program.
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

;; Finishes a variable list: saves READ's position or warns when INPUT has extra characters.
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
    lda #<EXIGNT
    ldy #>EXIGNT
    jmp STROUT
INPRTS:
    rts

;; Zero-terminated warning for extra INPUT values.
EXIGNT:
    .byte "?EXTRA IGNORED", $0D, $00

;; Zero-terminated prompt for re-entering an INPUT line.
TRYAGN:
    .byte "?REENTER", $0D, $00
