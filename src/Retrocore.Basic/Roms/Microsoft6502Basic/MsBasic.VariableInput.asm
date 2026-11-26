; retrocore: style=strict
; Derived from Microsoft's BASIC for 6502 (m6502.asm, MIT license; see LICENSE in this folder).

.include "MsBasic.Families.asm"

; MICROSOFT 6502 BASIC: READ AND VARIABLE INPUT
;
; VariableInput follows the platform's GET and INPUT entries. VariableInputMessages emits the
; immediately following warning strings. Both macros are emitted before NEXT.
;
; AppleSoft:           VariableInput 2, 1, 0, 0, 0, 1; VariableInputMessages 1, 0
; PET BASIC 1:         VariableInput 0, 0, 1, 1, 1, 0; VariableInputMessages 0, 1
; PET BASIC 2:         VariableInput 2, 0, 0, 0, 1, 0; VariableInputMessages 0, 1
; PET BASIC 4:         VariableInput 2, 0, 0, 0, 1, 0; VariableInputMessages 0, 0
;
; The early `BeginGetString` (GETSTR) helper is external: it stores the delimiter (0), advances the cursor, removes its
; JSR return address, and jumps back to AssignVariableList::StringAtCursor with A = 0. BASIC 1 supplies it in the
; editor-ROM patches.

; The values of <InputMode>, which says where AssignVariableList takes its values from.
;; <InputMode> for `INPUT`: the values come from the line the user types.
INPUT_MODE_INPUT = $00
;; <InputMode> for `GET`: bit 6 set, one character from the keyboard.
INPUT_MODE_GET = $40
;; <InputMode> for `READ`: bit 7 set, the values come from `DATA` statements.
;;
;; It is also the opcode of `TYA`. Where the input buffer is in page zero, `READ` ends in an `LDA` immediate opcode
;; that takes <AssignInputList>'s `TYA` as its operand, so `READ` loads this mode and the `TYA` never runs for it.
INPUT_MODE_READ = $98

;; Emits `READ` and the common `GET`, `INPUT` and `READ` variable-processing loop.
;; Parameters: bufferPage = the page containing <InputBuffer>, maskGetBit7 = 1 to clear bit 7 of a `GET` character,
;;   getPointerYFirst = 1 to load the `GET` buffer pointer's high byte before its low byte,
;;   patchedGetString = 1 to use the early `BeginGetString` patch, channelInput = 1 to honor input channels,
;;   blankNumericRetry = 1 to retry an empty terminal `INPUT` numeric value;
;;   space = optional, 1 (when given) for `READ`'s search to find a `DATA` after spaces, reading each statement's
;;   first character through <GetCurrentCharacter> (the VIC-20's)
.macro VariableInput bufferPage, maskGetBit7, getPointerYFirst, patchedGetString, channelInput, blankNumericRetry, space
    .assert bufferPage >= 0 && bufferPage <= 255, "bufferPage must fit in a byte."
    .assert InputBuffer > 0 && InputBuffer / 256 = bufferPage, "InputBuffer must be in bufferPage, after a byte."
    .assert maskGetBit7 = 0 || maskGetBit7 = 1, "maskGetBit7 must be 0 or 1."
    .assert getPointerYFirst = 0 || getPointerYFirst = 1, "getPointerYFirst must be 0 or 1."
    .assert patchedGetString = 0 || patchedGetString = 1, "patchedGetString must be 0 or 1."
    .assert channelInput = 0 || channelInput = 1, "channelInput must be 0 or 1."
    .assert blankNumericRetry = 0 || blankNumericRetry = 1, "blankNumericRetry must be 0 or 1."
    .assert patchedGetString = 0 || bufferPage = 0, "The early BeginGetString patch requires a page-zero buffer."
    .if getPointerYFirst
        .assert <(InputBuffer-1) != 0, "The GET buffer pointer's low byte must make its branch unconditional."
    .elseif bufferPage
        .assert >(InputBuffer-1) != 0, "The GET buffer pointer's high byte must make its branch unconditional."
    .endif

    .scope Statements continued

    ;; Reads values for a variable list from `DATA`, starting at the saved <DataPointer>.
    ;; In: decimal = clear
    ;; See: <AssignVariableList>, <AssignVariableList::SearchData>, <Statements::Restore>
    ;; Also: READ (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc Read
    ldx DataPointer
    ldy DataPointer+1
    .if bufferPage
        lda #INPUT_MODE_READ
        .byte $2C                   ; BIT absolute skips the INPUT mode's load
    .else
        .assert INPUT_MODE_READ = $98, "READ's mode must be the TYA opcode its LDA immediate takes."
        .byte $A9                   ; LDA immediate takes AssignInputList's TYA opcode as INPUT_MODE_READ
    .endif
    ; Falls into AssignInputList.
    .endproc
    .endscope

    ;; Starts an `INPUT` variable list with X/Y pointing to its input buffer.
    ;;
    ;; It sets A to <INPUT_MODE_INPUT>: with `LDA` where the buffer is outside page zero, or from Y where it is in page
    ;; zero.
    ;; In: X = cursor low byte, Y = cursor high byte (zero for a page-zero buffer)
    ;; Also: INPCON (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc AssignInputList
    .if bufferPage
        lda #INPUT_MODE_INPUT
    .else
        tya
    .endif
    ; Falls into AssignVariableList.
    .endproc

    ;; Assigns a `GET`, `INPUT` or `READ` value to each variable in the statement's list.
    ;;
    ;; <InputPointer> tracks the input cursor while <VariableListPointer> saves the variable-list position. `GET`
    ;; obtains one character when its sentinel is reached; `READ` searches subsequent `DATA` statements. A comma in the
    ;; variable list continues the loop. BASIC 1 uses its `BeginGetString` patch; AppleSoft masks `GET` characters and
    ;; retries an empty terminal numeric `INPUT`. On the PET, a selected file channel suppresses terminal prompts and
    ;; warnings.
    ;; In: A = <INPUT_MODE_GET>, <INPUT_MODE_INPUT> or <INPUT_MODE_READ>, X = cursor low byte, Y = cursor high byte,
    ;;   decimal = clear
    ;; Errors: OUT OF DATA when `READ` finds no more `DATA`, and the vendor's handling of a malformed value
    ;;   (<HandleBadInput>)
    ;; Entry:
    ;;   StringAtCursor = clears carry so the string starts at the current character; BASIC 1's `ResumeGetString`
    ;;     patch jumps back here
    ;; See: <FindVariable>, <AssignString>, <StoreNumber>, <AssignVariableList::SearchData>
    ;; Also: INPCO1 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc AssignVariableList
    sta InputMode
    stx InputPointer
    sty InputPointer+1

;; Resolves the next variable, then switches from the variable list to the saved input cursor.
;; Also: INLOOP (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
NextVariable:
    jsr FindVariable
    sta AssignedVariable
    sty AssignedVariable+1
    lda TextPointer
    ldy TextPointer+1
    sta VariableListPointer
    sty VariableListPointer+1
    ldx InputPointer
    ldy InputPointer+1
    stx TextPointer
    sty TextPointer+1
    jsr GetCurrentCharacter
    bne NextValue
    bit InputMode
    bvc SourceEmpty
    jsr GetCharacter
    .if maskGetBit7
        and #$7F
    .endif
    sta InputBuffer
    .if getPointerYFirst
        ldy #>(InputBuffer-1)
        ldx #<(InputBuffer-1)
        bne SetCursor
    .else
        ldx #<(InputBuffer-1)
        ldy #>(InputBuffer-1)
        .if bufferPage
            bne SetCursor
        .else
            beq SetCursor
        .endif
    .endif

;; Continues `READ` at the next `DATA` statement or obtains another `INPUT` line.
;; Also: QDATA (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
SourceEmpty:
    bmi SearchData
    .if channelInput
        lda CurrentChannel
        bne ReadAnotherLine
    .endif
    jsr PrintQuestionMark
;; Reads a line with <PromptAndInputLine>.
;; Also: GETNTH (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
ReadAnotherLine:
    jsr PromptAndInputLine
;; Sets <TextPointer> to X/Y.
;; Also: DATBK (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
SetCursor:
    stx TextPointer
    sty TextPointer+1

;; Starts conversion of the next string or numeric value at the input cursor.
;; Also: DATBK1 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
NextValue:
    jsr GetNextCharacter
    bit ValueType
    .if blankNumericRetry
        bpl CheckEmptyLine
    .else
        bpl ConvertNumber
    .endif
    bit InputMode
    bvc SetDelimiters
    .if patchedGetString
        lda #$00
        jsr BeginGetString
        nop
    .else
        inx
        stx TextPointer
        lda #$00
        sta Delimiter
        beq StringAtCursor
    .endif

;; Sets quote delimiters, or colon and comma delimiters for an unquoted string.
;; Also: SETQUT (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
SetDelimiters:
    sta Delimiter
    cmp #'"'
    beq MakeString
    lda #':'
    sta Delimiter
    lda #','

;; Uses the current text position as the start of an unquoted or single-character `GET` string.
;; In: A = ending delimiter, TextPointer = first character
;; Also: RESETC (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
StringAtCursor:
    clc

;; Builds and assigns a string from the input cursor.
;;
;; Carry set skips an opening quote; carry clear starts at the current character. <Strings::FromTextUntil> makes the
;; descriptor, <SetTextPointer> advances the input cursor, and <AssignString> assigns the result.
;; In: A = ending delimiter, TextPointer = text position, carry = set to skip a quote, decimal = clear
;; Also: NOWGET (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
MakeString:
    sta EndDelimiter
    lda TextPointer
    ldy TextPointer+1
    adc #$00
    bcc HaveAddress
    iny
;; Text address in A/Y: makes and assigns the string.
;; Also: NOWGE1 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
HaveAddress:
    jsr Strings::FromTextUntil
    jsr SetTextPointer
    jsr AssignString
    jmp CheckTerminator

    .if blankNumericRetry
;; Saves the numeric character while checking whether the input line is empty.
CheckEmptyLine:
        pha
        lda InputBuffer
        beq EmptyNumber
;; Pulls the saved character back.
RestoreCharacter:
        pla
    .endif

;; Converts and assigns a numeric value, including integer variables.
;; Also: NUMINS (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
ConvertNumber:
    jsr Float::ReadNumber
    lda IntegerType
    jsr StoreNumber

;; Validates the input terminator and restores the variable-list cursor.
;;
;; A zero or colon is accepted by <GetCurrentCharacter>'s zero flag; a comma is also accepted. Otherwise the
;; platform's malformed-input handler decides whether to retry or report an error.
;; Also: STRDN2 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
CheckTerminator:
    jsr GetCurrentCharacter
    beq TerminatorOk
    cmp #','
    beq TerminatorOk
    jmp HandleBadInput
;; Saves the input cursor, returns to the variable list and continues after a comma.
;; Also: TRMOK (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
TerminatorOk:
    lda TextPointer
    ldy TextPointer+1
    sta InputPointer
    sty InputPointer+1
    lda VariableListPointer
    ldy VariableListPointer+1
    sta TextPointer
    sty TextPointer+1
    jsr GetCurrentCharacter
    beq ListDone
    jsr CheckComma
    jmp NextVariable
    .if blankNumericRetry

;; Retries an empty numeric `INPUT`, or restores the saved character for `READ` and `GET`.
;; See: <DiscardAndRetryInput>, <AssignVariableList::RestoreCharacter>
EmptyNumber:
        lda InputMode
        bne RestoreCharacter
        jmp DiscardAndRetryInput
    .endif

;; Searches forward for a `DATA` statement, remembering each new line number in <DataLine>.
;;
;; <FindStatementEnd> skips statements, including quoted colons. A zero high byte in the next line link reports OUT OF
;; DATA.
;; See: <AssignVariableList::NextValue>
;; Also: DATLOP (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
SearchData:
    jsr FindStatementEnd
    iny
    tax
    bne CheckStatement
    ldx #ERROR_OUT_OF_DATA
    iny
    lda (TextPointer),y
    beq Statements::Next::ToError
    iny
    lda (TextPointer),y
    sta DataLine
    iny
    lda (TextPointer),y
    iny
    sta DataLine+1
;; Reads the statement's first token and loops until it is `DATA`.
;; Also: NOWLIN (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
CheckStatement:
    .ifnblank space
        .assert space = 1, "space is 1 when given."
        jsr AdvanceTextPointer
        jsr GetCurrentCharacter
        tax
    .else
        lda (TextPointer),y
        tax
        jsr AdvanceTextPointer
    .endif
    cpx #TOKEN_DATA
    bne SearchData
    jmp NextValue

;; Saves `READ`'s cursor or warns about extra terminal `INPUT` characters.
;;
;; Channel input suppresses the warning. A zero at the input cursor needs no warning.
;; Also: VAREND (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
ListDone:
    lda InputPointer
    ldy InputPointer+1
    ldx InputMode
    bpl CheckExtra
    jmp Statements::Restore::SetDataPointer
;; Prints EXTRA IGNORED when input remains, except on a PET's input channel.
;; Also: VARY0 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
CheckExtra:
    ldy #$00
    lda (InputPointer),y
    beq Done
    .if channelInput
        lda CurrentChannel
        bne Done
    .endif
    lda #<ExtraIgnoredMessage
    ldy #>ExtraIgnoredMessage
    jmp PrintText
;; Returns.
;; Also: INPRTS (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
Done:
    rts
    .endproc
.endmacro

;; Emits the extra-input warning and retry messages immediately after <VariableInput>.
;; Parameters: shortRetry = 1 for "?REENTER", 0 for "?REDO FROM START";
;;   lineFeed = 1 to follow each carriage return with a line feed
.macro VariableInputMessages shortRetry, lineFeed
    .assert shortRetry = 0 || shortRetry = 1, "shortRetry must be 0 or 1."
    .assert lineFeed = 0 || lineFeed = 1, "lineFeed must be 0 or 1."

;; Zero-terminated warning for extra terminal `INPUT` values.
;; Also: EXIGNT (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
ExtraIgnoredMessage:
    .byte "?EXTRA IGNORED", $0D
    .if lineFeed
        .byte $0A
    .endif
    .byte $00

;; Zero-terminated prompt for retrying malformed terminal `INPUT`.
;; Also: TRYAGN (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
RetryMessage:
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
