; retrocore: style=strict
; COMMODORE BASIC: OUTPUT CHANNEL SELECTION, CHARACTER OUTPUT AND PRINT SPACING

.include "../../Microsoft6502Basic/MsBasic.Families.asm"

;; The carriage return, which ends a line on every channel.
CARRIAGE_RETURN = $0D

;; The line feed, which follows a carriage return on the channels that take one.
LINE_FEED = $0A

;; The screen editor's cursor-right code, which the screen gets for a space.
CURSOR_RIGHT = $1D

;; The screen editor's cursor-left code.
CURSOR_LEFT = $9D

;; The screen editor's delete code, which moves the cursor back over the character before it.
DELETE_CHARACTER = $14

;; Emits the `PRINT#` and `CMD` channel-selection entries.
.macro CommodorePrintChannels

    .scope Statements continued

    ;; `PRINT#`: prints to a logical channel through <Statements::Cmd>, then restores the default channels.
    ;; Also: PRINTN (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc PrintNumber
    jsr Statements::Cmd
    jmp RestoreChannels
    .endproc

    ;; `CMD`: selects an output channel and prints any following items; the channel stays selected.
    ;; Out: CurrentChannel = the selected logical channel
    ;; See: <KernalSelectOutput>
    ;; Also: CMD (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc Cmd
    jsr EvaluateByte
    beq SelectChannel
    lda #','
    jsr CheckCharacter

;; Opens the channel for output, records it in <CurrentChannel> and enters PRINT.
;; Also: SAVEIT (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
SelectChannel:
    php
    jsr KernalSelectOutput
    stx CurrentChannel
    plp
    jmp Statements::Print
    .endproc

    .endscope
.endmacro

;; Emits the space, question-mark and character output entries: <PrintSpace>, <PrintQuestionMark> and
;; <PrintCharacter>.
;; Parameters: alwaysSkip = 1 to use the cursor-right code for every channel;
;;   localPosition = 1 to track the screen column in BASIC;
;;   honorSuppression = 1 to skip output while <OutputSuppressed> is set;
;;   returnAlias = 1 to define <PrintCharacter>'s `Return` at the return instruction
.macro CommodoreCharacterOutput alwaysSkip, localPosition, honorSuppression, returnAlias
    .assert alwaysSkip = 0 || alwaysSkip = 1, "alwaysSkip is 0 or 1."
    .assert localPosition = 0 || localPosition = 1, "localPosition is 0 or 1."
    .assert honorSuppression = 0 || honorSuppression = 1, "honorSuppression is 0 or 1."
    .assert returnAlias = 0 || returnAlias = 1, "returnAlias is 0 or 1."

    ;; Advances one space on the selected output channel: loads a space for a file, or <CURSOR_RIGHT> for the screen,
    ;; and skips <PrintQuestionMark>'s load, into <PrintCharacter>. Where `alwaysSkip` is 1 (BASIC 1), every channel
    ;; gets <CURSOR_RIGHT>.
    ;; Also: OUTSPC (M6502, CBM4S79, HV2, HV4, HV4R)
    .proc PrintSpace
    .if alwaysSkip

;; Loads the cursor-right code; HV1 and HV1R give BASIC 1's routine this name.
;; Also: CRTSKP (HV1, HV1R)
CursorRight:
    .else
        lda CurrentChannel
        beq CursorRight
        lda #' '
        .byte $2C                   ; BIT absolute skips the next LDA

;; Loads the cursor-right code.
;; Also: CRTSKP (M6502, CBM4S79, HV2, HV4, HV4R)
CursorRight:
    .endif
    lda #CURSOR_RIGHT
    .byte $2C                       ; BIT absolute skips PrintQuestionMark's LDA
    ; Falls into PrintQuestionMark, past its load.
    .endproc

    ;; Prints a question mark.
    ;; Also: OUTQST (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc PrintQuestionMark
    lda #'?'
    ; Falls into PrintCharacter.
    .endproc

    ;; Sends A to the selected output channel unless output is suppressed.
    ;;
    ;; Where `localPosition` is 1 (BASIC 1), it tracks the screen column itself and calls its editor-ROM patch on an
    ;; advance. Where `honorSuppression` is 0 (BASIC 4), output is never suppressed. Every build sets zero from A before
    ;; returning.
    ;; In: A = character
    ;; Out: A = the character if output is suppressed, else the output routine's result, zero = set when A is zero
    ;; See: <KernalCharacterOut>
    ;; Also: OUTDO (M6502, HV1, HV1R, HV2, HV4, HV4R, CBM4S79)
    .proc PrintCharacter
    .if honorSuppression
        bit OutputSuppressed
        bmi SetFlags
    .endif
    .if localPosition
        pha
        cmp #CURSOR_RIGHT
        beq Advance
        cmp #CURSOR_LEFT
        beq MoveLeft
        cmp #DELETE_CHARACTER
        bne CheckPrintable

;; Cursor-left or delete moves the screen column back, unless it is at 0 or a channel is selected.
;; Also: DECTRM (UNKN)
MoveLeft:
        lda TerminalPosition
        beq RestoreCharacter
        lda CurrentChannel
        bne RestoreCharacter
        dec TerminalPosition

;; Only printable characters advance the column.
;; Also: OUTDO2 (UNKN)
CheckPrintable:
        and #$7F
        cmp #' '
        bcc RestoreCharacter

;; Advances the column through the editor ROM's `INCTRM`.
;; Also: OUTDO1 (M6502, HV1, HV1R)
Advance:
        lda CurrentChannel
        jsr INCTRM
        nop

;; Recovers the character before sending it.
;; Also: TRYOUT (M6502, HV1, HV1R)
RestoreCharacter:
        pla
    .endif

;; Sends the character through <KernalCharacterOut>; nothing branches here, and the label is kept for its old name.
;; Also: OUTLOC (M6502)
Send:
    jsr KernalCharacterOut

;; Sets zero from A and returns; suppressed output branches here.
;; Also: OUTRTS (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
SetFlags:
    and #$FF
    .if returnAlias

;; Returns; nothing branches here, and the label is kept for its old name.
;; Also: GETRTS (M6502)
Return:
    .endif
    rts
    .endproc
.endmacro

;; Emits input-line completion and the newline entries: <FinishInputLine> and <PrintNewline>.
;; Parameters: bufferPage = zero for a page-zero input buffer, or the nonzero buffer page;
;;   localPosition = 1 to maintain <TerminalPosition> in BASIC rather than the editor;
;;   channelLineFeed = 1 to emit a line feed only for channels with bit 7 set;
;;   nullPadding = 1 to emit the configured NULL characters after a newline
.macro CommodoreLineEnd bufferPage, localPosition, channelLineFeed, nullPadding
    .assert bufferPage >= 0 && bufferPage <= 255, "bufferPage must fit in a byte."
    .assert localPosition = 0 || localPosition = 1, "localPosition is 0 or 1."
    .assert channelLineFeed = 0 || channelLineFeed = 1, "channelLineFeed is 0 or 1."
    .assert nullPadding = 0 || nullPadding = 1, "nullPadding is 0 or 1."

    ;; Terminates an input line, and prints a newline only for terminal input.
    ;; In: X = number of input bytes
    ;; Out: X = the low byte of the address before <InputBuffer>, Y = its high byte
    ;; Also: FININL (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc FinishInputLine
    .if bufferPage
        lda #$00
        sta InputBuffer,x
        ldx #<(InputBuffer-1)
        ldy #>(InputBuffer-1)
    .else
        ldy #$00
        sty InputBuffer,x
        ldx #<(InputBuffer-1)
    .endif
    lda CurrentChannel
    bne PrintNewline::Return
    ; Falls into PrintNewline.
    .endproc

    ;; Prints a carriage return and the line feed and padding this build needs.
    ;;
    ;; Where `localPosition` is 1 (BASIC 1), the screen's return also resets the column; where `channelLineFeed` is 1
    ;; (BASIC 4), only a channel with bit 7 set gets the line feed; where `nullPadding` is 1 (BASIC 1), it sends
    ;; <NullCount> zero bytes, and the other builds complement A instead.
    ;; Entry:
    ;;   Finish = finishes the newline (padding, column, or A complemented); the shared <PrintString> enters here
    ;;   Return = returns; <FinishInputLine> and the shared PRINT branch here
    ;; Also: CRDO (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc PrintNewline
    .if localPosition
        lda CurrentChannel
        bne SendReturn
        sta TerminalPosition
    .endif

;; Sends the carriage return.
;; Also: GOCR (M6502)
SendReturn:
    lda #CARRIAGE_RETURN
    jsr PrintCharacter
    .if channelLineFeed
        lda CurrentChannel
        bpl Finish
    .endif
    lda #LINE_FEED
    jsr PrintCharacter

;; Finishes the newline after a string's return or the newline itself.
;; Also: CRFIN (M6502, HV1, HV1R, HV2, HV4, HV4R, CBM4S79)
Finish:
    .if localPosition
        lda CurrentChannel
        bne Return
    .endif
    .if nullPadding
        txa
        pha
        ldx NullCount
        beq ResetColumn
        lda #$00

;; Sends the NULL count of zero bytes.
;; Also: PRTNUL (M6502, HV1, HV1R)
PadNulls:
        jsr PrintCharacter
        dex
        bne PadNulls

;; Clears <TerminalPosition> and restores X.
;; Also: CLRPOS (M6502, HV1, HV1R)
ResetColumn:
        stx TerminalPosition
        pla
        tax
    .else
        eor #$FF
    .endif

;; Returns.
;; Also: PRTRTS (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
Return:
    rts
    .endproc
.endmacro

;; Emits comma-zone, `TAB(` and `SPC(` handling: <PrintComma>, <PrintTabOrSpace> and <PrintSpaces>.
;; Parameters: tokenDispatch = 1 to distinguish TAB from SPC by the saved token and use the earlier space loop
.macro CommodorePrintSpacing tokenDispatch
    .assert tokenDispatch = 0 || tokenDispatch = 1, "tokenDispatch is 0 or 1."

    ;; PRINT's comma: prints spaces to the next <ZONE_WIDTH> zone from <TerminalPosition>.
    ;; Also: COMPRT (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc PrintComma
    lda TerminalPosition

;; Starts the zone's modulus; nothing branches here, and the label is kept for its old name.
;; Also: MORCOM (M6502)
Modulus:
    sec

;; Subtracts <ZONE_WIDTH> until the column goes negative, then negates it to the spaces needed.
;; Also: MORCO1 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
SubtractZone:
    sbc #ZONE_WIDTH
    bcs SubtractZone
    eor #$FF
    adc #$01
    bne PrintSpaces
    .endproc

    ;; `TAB(` or `SPC(`: reads the byte argument and the `)`, then prints spaces to the column (`TAB`) or the count
    ;; (`SPC`), and falls into <PrintSpaces>.
    ;;
    ;; Where `tokenDispatch` is 1 (BASIC 1), it tells them apart by the token it saved, and `SPC(0)` prints 256 spaces;
    ;; the later builds tell them apart by carry, and print none.
    ;; In: A = the token where `tokenDispatch` is 1; carry = set for `TAB`, clear for `SPC`, where it is 0
    ;; Errors: SYNTAX if the closing parenthesis is missing
    ;; Also: TABER (M6502, HV1, HV1R, HV2, HV4, HV4R, CBM4S79)
    .proc PrintTabOrSpace
    .if tokenDispatch
        pha
        jsr SkipAndEvaluateByte
        cmp #')'
        bne HandleBadInput::ToSyntaxError
        pla
        cmp #TOKEN_TAB
        bne PrintSpaces::CountInX
        txa
        sbc TerminalPosition
        bcc PrintSpaces::ContinuePrint
        beq PrintSpaces::ContinuePrint
    .else
        php
        jsr SkipAndEvaluateByte
        cmp #')'
        bne HandleBadInput::ToSyntaxError
        plp
        bcc PrintSpaces::CountInX
        txa
        sbc TerminalPosition
        bcc PrintSpaces::ContinuePrint
    .endif
    ; Falls into PrintSpaces.
    .endproc

    .if tokenDispatch
        ;; Prints A spaces, then continues PRINT; <PrintComma> branches here and <PrintTabOrSpace> falls into it.
        ;; Entry:
        ;;   CountInX = prints X spaces, 256 for zero; <PrintTabOrSpace>'s `SPC` enters here
        ;;   ContinuePrint = reads the next character and continues PRINT at <Statements::Print::Item> without
        ;;     a newline; the shared PRINT and <PrintTabOrSpace> branch here
        ;; Also: ASPAC (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
        .proc PrintSpaces
        tax

;; Prints X spaces, 256 for zero.
;; Also: XSPAC (M6502), XSPAC1 (HV1, HV1R)
CountInX:
        jsr PrintSpace

;; Counts down and loops.
;; Also: XSPAC2 (HV1, HV1R)
Next:
        dex
        bne CountInX

;; Reads the next character and continues PRINT without a newline.
;; Also: NOTABR (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
ContinuePrint:
        jsr GetNextCharacter
        jmp Statements::Print::Item
        .endproc
    .else
        ;; Prints A spaces, then continues PRINT; <PrintComma> branches here and <PrintTabOrSpace> falls into it.
        ;; Entry:
        ;;   CountInX = prints X spaces (zero prints none); <PrintTabOrSpace>'s `SPC` enters here
        ;;   ContinuePrint = reads the next character and continues PRINT at <Statements::Print::Item> without
        ;;     a newline; the shared PRINT and <PrintTabOrSpace> branch here
        ;; Also: ASPAC (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
        .proc PrintSpaces
        tax

;; Prints X spaces; zero prints none.
;; Also: XSPAC (M6502, CBM4S79, HV2, HV4, HV4R)
CountInX:
        inx

;; Counts down; zero goes on to `ContinuePrint`.
;; Also: XSPAC2 (M6502, CBM4S79, HV2, HV4, HV4R)
Next:
        dex
        bne One

;; Reads the next character and continues PRINT without a newline.
;; Also: NOTABR (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
ContinuePrint:
        jsr GetNextCharacter
        jmp Statements::Print::Item

;; Prints one space and loops.
;; Also: XSPAC1 (M6502, CBM4S79, HV2, HV4, HV4R)
One:
        jsr PrintSpace
        bne Next
        .endproc
    .endif
.endmacro
