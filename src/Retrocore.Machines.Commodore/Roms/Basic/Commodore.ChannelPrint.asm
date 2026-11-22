; COMMODORE BASIC: OUTPUT CHANNEL SELECTION

;; Emits the PRINT# and CMD channel-selection entries.
.macro COMMODORE_PRINT_CHANNELS

;; Prints to a logical channel, then restores the default channels.
PRINTN:
    jsr CMD
    jmp IODONE

;; Selects an output channel and prints any following items; CMD leaves the channel selected.
;; Out: CHANNL = selected logical channel
;; See: <CQOOUT>
CMD:
    jsr GETBYT
    beq SAVEIT
    lda #','
    jsr SYNCHR
SAVEIT:
    php
    jsr CQOOUT
    stx CHANNL
    plp
    jmp PRINT
.endmacro

;; Emits the space, question-mark and character output entries.
;; Parameters: alwaysSkip = 1 to use the cursor-right code for every channel;
;;   localPosition = 1 to track the screen column in BASIC;
;;   suppressOutput = 1 to honor the output-suppression flag;
;;   returnAlias = 1 to define GETRTS at the return instruction
.macro COMMODORE_CHARACTER_OUTPUT alwaysSkip, localPosition, suppressOutput, returnAlias
    .assert alwaysSkip = 0 || alwaysSkip = 1, "alwaysSkip is 0 or 1."
    .assert localPosition = 0 || localPosition = 1, "localPosition is 0 or 1."
    .assert suppressOutput = 0 || suppressOutput = 1, "suppressOutput is 0 or 1."
    .assert returnAlias = 0 || returnAlias = 1, "returnAlias is 0 or 1."

;; Advances one space on the selected output channel.
;;
;; The earlier version always sends cursor-right; later versions send a space to a file.
OUTSPC:
.if alwaysSkip
    lda #$1D
.else
    lda CHANNL
    beq CRTSKP
    lda #' '
    .byte $2C                   ; BIT absolute skips the next LDA
CRTSKP:
    lda #$1D
.endif
    .byte $2C                   ; BIT absolute skips the next LDA

;; Prints a question mark.
OUTQST:
    lda #'?'

;; Sends A to the selected output channel unless output is suppressed.
;;
;; The earlier version tracks screen-column changes locally and calls its editor spill patch on advance.
;; BASIC 4 does not suppress output. All versions set zero from A before returning.
;; In: A = character
;; Out: A = input character if suppressed or the output routine's result, zero = set when A is zero
;; See: <OUTCH>
OUTDO:
.if suppressOutput
    bit CNTWFL
    bmi OUTRTS
.endif
.if localPosition
    pha
    cmp #$1D
    beq OUTDO1
    cmp #$9D
    beq DECTRM
    cmp #$14
    bne OUTDO2
DECTRM:
    lda TRMPOS
    beq TRYOUT
    lda CHANNL
    bne TRYOUT
    dec TRMPOS
OUTDO2:
    and #$7F
    cmp #$20
    bcc TRYOUT
OUTDO1:
    lda CHANNL
    jsr INCTRM
    nop
TRYOUT:
    pla
.endif
OUTLOC:
    jsr OUTCH
OUTRTS:
    and #$FF
.if returnAlias
GETRTS:
.endif
    rts
.endmacro

;; Emits input-line completion and the Commodore newline entries.
;; Parameters: bufferPage = zero for a page-zero input buffer, or the nonzero buffer page;
;;   localPosition = 1 to maintain <TRMPOS> in BASIC rather than the editor;
;;   channelLineFeed = 1 to emit a line feed only for channels with bit 7 set;
;;   nullPadding = 1 to emit the configured NULL characters after a newline
.macro COMMODORE_LINE_END bufferPage, localPosition, channelLineFeed, nullPadding
    .assert bufferPage >= 0 && bufferPage <= 255, "bufferPage must fit in a byte."
    .assert localPosition = 0 || localPosition = 1, "localPosition is 0 or 1."
    .assert channelLineFeed = 0 || channelLineFeed = 1, "channelLineFeed is 0 or 1."
    .assert nullPadding = 0 || nullPadding = 1, "nullPadding is 0 or 1."

;; Terminates an input line and prints a newline only for terminal input.
;; In: X = number of input bytes
;; Out: X = low byte of <BUF>-1, Y = high byte of <BUF>-1
FININL:
.if bufferPage
    lda #$00
    sta BUF,x
    ldx #<(BUF-1)
    ldy #>(BUF-1)
.else
    ldy #$00
    sty BUF,x
    ldx #<(BUF-1)
.endif
    lda CHANNL
    bne PRTRTS

;; Prints a carriage return and the line feed and padding required by this variant.
CRDO:
.if localPosition
    lda CHANNL
    bne GOCR
    sta TRMPOS
.endif
GOCR:
    lda #$0D
    jsr OUTDO
.if channelLineFeed
    lda CHANNL
    bpl CRFIN
.endif
    lda #$0A
    jsr OUTDO

;; Finishes carriage-return handling after a string character or the newline entry.
CRFIN:
.if localPosition
    lda CHANNL
    bne PRTRTS
.endif
.if nullPadding
    txa
    pha
    ldx NULCNT
    beq CLRPOS
    lda #$00
PRTNUL:
    jsr OUTDO
    dex
    bne PRTNUL
CLRPOS:
    stx TRMPOS
    pla
    tax
.else
    eor #$FF
.endif
PRTRTS:
    rts
.endmacro

;; Emits comma-zone, TAB and SPC handling.
;; Parameters: tokenDispatch = 1 to distinguish TAB from SPC by the saved token and use the earlier space loop
.macro COMMODORE_PRINT_SPACING tokenDispatch
    .assert tokenDispatch = 0 || tokenDispatch = 1, "tokenDispatch is 0 or 1."

;; Advances to the next comma zone using the current terminal position.
;; In: TRMPOS = current column
COMPRT:
    lda TRMPOS
MORCOM:
    sec
MORCO1:
    sbc #CLMWID
    bcs MORCO1
    eor #$FF
    adc #$01
    bne ASPAC

;; Parses a TAB or SPC argument and emits the required spacing.
;;
;; The earlier token-based path prints 256 spaces for SPC(0); the later carry-based path prints none.
;; In: A = TAB or SPC token, carry = set for TAB or clear for SPC when using carry-based dispatch
;; Errors: SYNTAX ERROR if the closing parenthesis is missing
TABER:
.if tokenDispatch
    pha
    jsr GTBYTC
    cmp #')'
    bne SNERR4
    pla
    cmp #TABTK
    bne XSPAC
    txa
    sbc TRMPOS
    bcc NOTABR
    beq NOTABR
ASPAC:
    tax
XSPAC:
    jsr OUTSPC
    dex
    bne XSPAC
NOTABR:
    jsr CHRGET
    jmp PRINTC
.else
    php
    jsr GTBYTC
    cmp #')'
    bne SNERR4
    plp
    bcc XSPAC
    txa
    sbc TRMPOS
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
.endif
.endmacro
