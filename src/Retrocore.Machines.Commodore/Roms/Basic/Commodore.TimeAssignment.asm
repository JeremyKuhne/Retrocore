; COMMODORE BASIC: CLOCK-STRING ASSIGNMENT
;
; This block follows the shared <INPCOM> entry and falls through to <GETSPT>
; when the destination is an ordinary string variable.

;; Emits the TI$ assignment entry for a six-digit hours, minutes and seconds string.
;;
;; It converts the string to 60 Hz clock ticks and stores the low three bytes in <CQTIMR>. The
;; interrupt-disabled store prevents the clock interrupt from observing a partially updated value.
;; Parameters: longLengthError = 1 to use an absolute jump for a wrong length, 0 to use a nearby error branch
;; In: FORPNT = destination variable, FACMO/FACLO = string descriptor
;; Errors: ILLEGAL QUANTITY if the length is not six or a character is not a decimal digit
.macro TIME_STRING_ASSIGNMENT longLengthError
    .assert longLengthError = 0 || longLengthError = 1, "longLengthError must be 0 or 1."

    ldy FORPNT+1
    cpy #>ZERO
    bne GETSPT
    jsr FREFAC
    cmp #$06
.if longLengthError
    beq *+5
    jmp FCERR
.else
    bne FCERR2
.endif
    ldy #$00
    sty FACEXP
    sty FACSGN

TIMELP:
    sty FBUFPT
    jsr TIMNUM
    jsr MUL10
    inc FBUFPT
    ldy FBUFPT
    jsr TIMNUM
    jsr MOVAF
    tax
    beq NOML6
    inx
    txa
    jsr FINML6

NOML6:
    ldy FBUFPT
    iny
    cpy #$06
    bne TIMELP
    jsr MUL10
    jsr QINT
    ldx #$02
    sei

TIMEST:
    lda FACMOH,x
    sta CQTIMR,x
    dex
    bpl TIMEST
    cli
    rts

;; Adds the decimal digit at <INDEX>+Y to <FAC>.
;; In: INDEX = string characters, Y = character offset
;; Errors: ILLEGAL QUANTITY if the character is not a decimal digit
TIMNUM:
    lda (INDEX),y
    jsr QNUM
    bcc GOTNUM

FCERR2:
    jmp FCERR

GOTNUM:
    sbc #('0'-1)
    jmp FINLOG

.endmacro
