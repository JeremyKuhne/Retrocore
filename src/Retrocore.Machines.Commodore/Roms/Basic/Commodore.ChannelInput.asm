; retrocore: style=strict
; COMMODORE BASIC: GET AND INPUT CHANNELS

.include "../../Microsoft6502Basic/MsBasic.Families.asm"
.include "Commodore.Switches.asm"

;; Emits `GET`, `INPUT#` and the channel release: <Statements::Get>, <Statements::InputNumber> and <RestoreChannels>.
;; Parameters: bufferPage = zero for a page-zero input buffer, or the nonzero buffer page
.macro CommodoreChannelInput bufferPage
    .assert bufferPage >= 0 && bufferPage <= 255, "bufferPage must fit in a byte."

    .scope Statements continued

    ;; `GET`: reads characters into the variable list, from a numbered input channel when `#` follows. With
    ;; <STANDARD_KERNAL> (the VIC-20), it records the channel first and selects it through `CheckedSelectInput`.
    ;; Errors: ILLEGAL DIRECT when used in direct mode
    ;; Also: GET (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
    .proc Get
    jsr RejectDirectMode
    cmp #'#'
    bne ReadCharacters
    jsr GetNextCharacter
    jsr EvaluateByte
    lda #','
    jsr CheckCharacter
    .if STANDARD_KERNAL
        stx CurrentChannel
        jsr CheckedSelectInput
    .else
        jsr KernalSelectInput
        stx CurrentChannel
    .endif

;; Sets up an empty buffer, reads through the shared input code in GET mode, then releases a selected channel.
;; Also: GETTTY (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
ReadCharacters:
    ldx #<(InputBuffer+1)
    ldy #>(InputBuffer+1)
    .if bufferPage
        lda #$00
        sta InputBuffer+1
    .else
        sty InputBuffer+1
    .endif
    lda #INPUT_MODE_GET
    jsr AssignVariableList
    ldx CurrentChannel
    bne RestoreChannels::Release
    rts
    .endproc

    ;; `INPUT#`: selects the input channel, runs INPUT from its direct-mode check, then falls into <RestoreChannels>.
    ;; With <STANDARD_KERNAL> (the VIC-20), it records the channel first and selects it through `CheckedSelectInput`.
    ;; Also: INPUTN (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
    .proc InputNumber
    jsr EvaluateByte
    lda #','
    jsr CheckCharacter
    .if STANDARD_KERNAL
        stx CurrentChannel
        jsr CheckedSelectInput
    .else
        jsr KernalSelectInput
        stx CurrentChannel
    .endif
    jsr Statements::Input::CheckDirect
    ; Falls into RestoreChannels.
    .endproc

    .endscope

    ;; Restores the default channels after channel input or output, and clears <CurrentChannel>.
    ;; Entry:
    ;;   Release = restores the default channels and clears <CurrentChannel>; <Statements::Get> branches here after
    ;;     reading a channel
    ;; Also: IODONE (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
    .proc RestoreChannels
    lda CurrentChannel

;; Restores the default channels and clears <CurrentChannel>.
;; Also: IORELE (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
Release:
    jsr KernalResetChannels
    ldx #$00
    stx CurrentChannel
    rts
    .endproc
.endmacro

;; Emits the `INPUT` statement, <Statements::Input>, through its line reader, <PromptAndInputLine>.
;; Parameters: clearSuppression = 1 to clear the output-suppression flag at INPUT's start;
;;   statusMask = channel error bits;
;;   revisedEof = 1 to use the revised BASIC 4 end-of-file helper;
;;   editorPatch = 1 to use the BASIC 1 editor-ROM stop helper;
;;   localStopLabel = 1 to define the blank-line stop, `StopEmptyInput`, here (BASIC 4);
;;   blankSkips = optional, 1 (when given) for a blank terminal line to skip the rest of the statement rather than stop
;;   the program (the VIC-20's)
.macro CommodoreInputStatement clearSuppression, statusMask, revisedEof, editorPatch, localStopLabel, blankSkips
    .assert clearSuppression = 0 || clearSuppression = 1, "clearSuppression is 0 or 1."
    .assert statusMask = 2 || statusMask = 3, "statusMask is 2 or 3."
    .assert revisedEof = 0 || revisedEof = 1, "revisedEof is 0 or 1."
    .assert editorPatch = 0 || editorPatch = 1, "editorPatch is 0 or 1."
    .assert localStopLabel = 0 || localStopLabel = 1, "localStopLabel is 0 or 1."
    .assert editorPatch = 0 || localStopLabel = 0, "The stop entry is either local or in the editor ROM."

    .scope Statements continued

    ;; `INPUT`: reads values from the keyboard or the selected channel.
    ;;
    ;; An optional quoted prompt is printed first. Terminal input receives a question-mark prompt and a blank line stops
    ;; the program; a file error releases the channel and skips to the next statement. Where `revisedEof` is 1 (the
    ;; revised BASIC 4), its patch `HandleBlankInput`, in BASIC's patch area, takes the blank-line and end-of-file
    ;; handling. Where the build passes `blankSkips` (the VIC-20), a blank terminal line skips the rest of the statement
    ;; instead. With <STANDARD_KERNAL> (the VIC-20), the channel's status comes from `KernalReadStatus`.
    ;; Entry:
    ;;   CheckDirect = rejects direct mode and puts a comma before the buffer; <Statements::InputNumber> enters here
    ;;   ReadLine = reads a line and checks the channel's status; the revised BASIC 4's `HandleBlankInput` re-enters
    ;;     here
    ;; Errors: ILLEGAL DIRECT when used in direct mode; SYNTAX when a quoted prompt is not followed by a semicolon
    ;; Also: INPUT (M6502, HV1, HV1R, HV2, HV4, HV4R, CBM4S79, BV20)
    .proc Input
    .if clearSuppression
        lsr OutputSuppressed
    .endif
    cmp #'"'
    bne CheckDirect
    jsr ReadQuotedString
    lda #';'
    jsr CheckCharacter
    jsr PrintString

;; Rejects direct mode and puts a comma before the buffer.
;; Also: NOTQTI (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
CheckDirect:
    jsr RejectDirectMode
    lda #','
    sta InputBuffer-1

;; Reads a line and checks the channel's status: a file error releases the channel and skips the statement.
;; Also: GETAGN (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
ReadLine:
    jsr PromptAndInputLine
    lda CurrentChannel
    beq CheckEmpty
    .if STANDARD_KERNAL
        jsr KernalReadStatus
    .else
        lda IoStatus
    .endif
    and #statusMask
    beq CheckEmpty
    jsr RestoreChannels
    jmp Statements::Data

;; A nonempty line goes to the shared value parser; an empty one retries a channel, and from the terminal stops the
;; program or, where the build passes `blankSkips` (the VIC-20), skips the rest of the statement.
;; Also: BUFFUL (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
CheckEmpty:
    lda InputBuffer
    bne AssignInputList
    .if revisedEof
        jmp HandleBlankInput
        nop
    .else
        lda CurrentChannel
        bne ReadLine
    .endif
    .ifnblank blankSkips
        .assert blankSkips = 1, "blankSkips is 1 when given."
        .assert editorPatch + localStopLabel + revisedEof = 0, "A blank line either skips or stops."
        jsr FindStatementEnd
        jmp AdvanceTextPointer
    .elseif editorPatch
        jmp StopEmptyInput
    .elseif localStopLabel
        ; Falls into StopEmptyInput, except in the revised BASIC 4, which jumped to HandleBlankInput.
    .else
        clc
        jmp Statements::StopOrEnd::SaveLine
    .endif
    .endproc

    .endscope

    .if localStopLabel
        ;; Stops the program, as `END` does, after a blank terminal INPUT line.
        ;; Also: INPSTP (UNKN), PATCH1 (HV1, HV1R), BUFFU1 (HV4R)
        .proc StopEmptyInput
        clc
        jmp Statements::StopOrEnd::SaveLine
        .endproc
    .endif

    ;; Reads an input line, printing `? ` first only when the keyboard is selected.
    ;; Also: QINLIN (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
    .proc PromptAndInputLine
    lda CurrentChannel
    bne ToInputLine
    jsr PrintQuestionMark
    jsr PrintSpace

;; Jumps on to <InputLine>.
;; Also: GINLIN (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
ToInputLine:
    jmp InputLine
    .endproc
.endmacro

;; Emits the malformed-input handling, <HandleBadInput> and <RetryInput>, before the `GET` entry.
;; Parameters: editorPatch = 1 to select the earlier editor-ROM line-number helper
.macro CommodoreInputError editorPatch
    .assert editorPatch = 0 || editorPatch = 1, "editorPatch is 0 or 1."

    ;; Retries malformed terminal INPUT, or reports an error for READ, GET or file INPUT.
    ;;
    ;; READ reports the DATA line, GET reports a direct line, and file INPUT reports `FILE DATA` (`BAD DATA` in BASIC
    ;; 1). Terminal INPUT prints the retry message and restores <TextPointer> to the start of the current statement.
    ;; Where `editorPatch` is 1 (BASIC 1), the editor ROM's `GetDataLine` gives READ's line.
    ;; In: InputMode = the input's source, CurrentChannel = the selected channel
    ;; Out: TextPointer = the restored statement position when retrying, CurrentLine = the error's line for READ or GET
    ;; Errors: SYNTAX for READ or GET; `FILE DATA` (`BAD DATA` in BASIC 1) for file INPUT
    ;; Entry:
    ;;   ToSyntaxError = jumps to <SyntaxError>; <PrintTabOrSpace> branches here
    ;; Also: TRMNOK (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
    .proc HandleBadInput
    lda InputMode
    beq CheckChannel
    .if editorPatch
        jsr GetDataLine
        nop
    .else
        bmi UseDataLine
        ldy #$FF
        bne SetLine

;; READ: takes <DataLine> as the error's line.
;; Also: GETDTL (M6502, CBM4S79, HV2, HV4, HV4R, BV20)
UseDataLine:
        lda DataLine
        ldy DataLine+1
    .endif

;; Stores the error's line in <CurrentLine>.
;; Also: STCURL (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
SetLine:
    sta CurrentLine
    sty CurrentLine+1

;; Jumps on to <SyntaxError>.
;; Also: SNERR4 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
ToSyntaxError:
    jmp SyntaxError

;; INPUT: from a channel reports `FILE DATA` (`BAD DATA` in BASIC 1); from the keyboard retries.
;; Also: TRMNO1 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
CheckChannel:
    lda CurrentChannel
    beq RetryInput
    ldx #<ERROR_FILE_DATA
    jmp ReportError
    .endproc

    ;; Prints the retry message and restores <TextPointer> from <StoppedText>.
    ;; Also: DOAGIN (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
    .proc RetryInput
    lda #<RetryMessage
    ldy #>RetryMessage
    jsr PrintText
    lda StoppedText
    ldy StoppedText+1
    sta TextPointer
    sty TextPointer+1
    rts
    .endproc
.endmacro
