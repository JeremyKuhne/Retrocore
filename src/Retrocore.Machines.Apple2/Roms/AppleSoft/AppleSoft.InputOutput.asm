; retrocore: style=strict
; APPLESOFT: GET, INPUT AND READ
;
; These statements share variable lookup and conversion but get their values from a key, an input line or
; DATA statements. The string assignment and output helpers used here precede this module in
; AppleSoft.Assignment.asm and AppleSoft.Print.asm.

.include "../Microsoft6502Basic/MsBasic.Families.asm"

;; Handles a malformed input value: retries INPUT, or reports a syntax error for READ or GET.
;;
;; For READ the reported line is the DATA line; GET is reported as direct. An active `ONERR` handler receives
;; error code $FE for the INPUT retry path.
;; In: InputMode = the statement's mode (<INPUT_MODE_INPUT>, <INPUT_MODE_GET> or <INPUT_MODE_READ>)
;; Entry:
;;   ToSyntaxError = jumps to <SyntaxError>; the enhanced IIe's <PrintTabOrSpace> branches here
;; See: <RetryInput>, <DataLine>, <SyntaxError>
;; Also: TRMNOK (M6502)
.proc HandleBadInput
    lda InputMode
    beq RetryInput
    bmi UseDataLine
    ldy #$FF
    bne SetLine

;; READ: takes <DataLine> as the error's line.
;; Also: GETDTL (M6502)
UseDataLine:
    lda DataLine
    ldy DataLine+1

;; Stores the error's line in <CurrentLine>.
;; Also: STCURL (M6502)
SetLine:
    sta CurrentLine
    sty CurrentLine+1

;; Jumps on to <SyntaxError>.
;; Also: SNERR4 (M6502)
ToSyntaxError:
    jmp SyntaxError
.endproc

;; Drops a stacked byte and falls into <RetryInput>; the shared INPUT code enters here.
;; Also: SNERR6 (UNKN)
.proc DiscardAndRetryInput
    pla
    ; Falls into RetryInput.
.endproc

;; Prints ?REENTER and restores the current statement's text pointer from <StoppedText>, unless `ONERR` intercepts the
;; retry with error code $FE.
;; Also: DOAGIN (M6502), TRMNO1 (M6502)
.proc RetryInput
    bit OnErrorActive
    bpl PrintRetry
    ldx #$FE
    jmp TrapError

;; No `ONERR` handler is active: prints the retry message and restores <TextPointer> from <StoppedText>.
;; Also: TRMNO2 (UNKN)
PrintRetry:
    lda #<RetryMessage
    ldy #>RetryMessage
    jsr PrintText
    lda StoppedText
    ldy StoppedText+1
    sta TextPointer
    sty TextPointer+1
    rts
.endproc

.scope Statements continued

;; GET: reads individual keyboard characters into the variables in its list.
;; Errors: ILLEGAL DIRECT when used in direct mode
;; See: <AssignVariableList>, <CQINCH>
;; Also: GET (M6502)
.proc Get
    jsr RejectDirectMode

;; Sets up an empty buffer and enters the shared input code in GET mode; <Statements::Get> falls into it, and
;; nothing branches here.
;; Also: GETTTY (M6502)
ReadCharacters:
    ldx #<(BUF+1)
    ldy #>(BUF+1)
    lda #$00
    sta BUF+1
    lda #INPUT_MODE_GET
    jsr AssignVariableList
    rts
.endproc

;; INPUT: prints an optional quoted prompt and reads values for its variable list.
;;
;; A literal prompt must be followed by a semicolon. Without one INPUT prints a question mark. A line that starts with
;; Control-C stops the program as the statement loop does, through <HandleBreak>.
;; Errors: ILLEGAL DIRECT when used in direct mode; SYNTAX when a quoted prompt is not followed by a semicolon
;; See: <InputLine>, <AssignVariableList::NextVariable>
;; Also: INPUT (M6502)
.proc Input
    cmp #'"'
    bne NoPrompt
    jsr ReadQuotedString
    lda #';'
    jsr CheckCharacter
    jsr PrintString
    jmp CheckDirect

;; No quoted prompt: prints a question mark.
;; Also: INPUT1 (UNKN)
NoPrompt:
    jsr PrintQuestionMark

;; Rejects direct mode and puts a comma before the buffer.
;; Also: NOTQTI (M6502)
CheckDirect:
    jsr RejectDirectMode
    lda #','
    sta BUF-1

;; Reads the line; one that starts with Control-C goes to <HandleBreak>. Nothing branches here, and the label is kept
;; for its old name.
;; Also: GETAGN (M6502)
ReadLine:
    jsr InputLine
    lda BUF
    cmp #CONTROL_C
    bne AssignInputList
    jmp HandleBreak
.endproc

.endscope

;; Prints a question mark and reads another input line.
;; Also: QINLIN (M6502)
.proc PromptAndInputLine
    jsr PrintQuestionMark

;; Jumps on to <InputLine>; <PromptAndInputLine> falls into it, and nothing branches here.
;; Also: GINLIN (M6502)
ToInputLine:
    jmp InputLine
.endproc

.include "../Microsoft6502Basic/MsBasic.VariableInput.asm"
    VariableInput 2, 1, 0, 0, 0, 1
    VariableInputMessages 1, 0
