; retrocore: style=strict
; Derived from Microsoft's BASIC for 6502 (m6502.asm, MIT license; see LICENSE in this folder).

.include "MsBasic.Families.asm"

; MICROSOFT 6502 BASIC: RESTORE, STOP, END, CONT, RUN, GOSUB, GOTO AND RETURN
;
; RUN through RETURN are emitted consecutively before DATA. RESTORE and STOP/CONT can be separated by a
; platform's interrupt handling. The macros select their platform-specific entry points and early quirks.

;; Emits the RESTORE entry.
.macro RestoreStatement
    .scope Statements continued

    ;; Positions the DATA reader before the first program line.
    ;; Entry:
    ;;   SetDataPointer = Stores A/Y in <DataPointer>; `READ`'s finish enters here
    ;;   Done = returns; the statement dispatcher, except BASIC 1's early one, returns through it at end of statement
    ;; See: <Statements::Read>, <DataPointer>
    ;; Also: RESTOR (M6502, ASTIL, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
    .proc Restore
    sec
    lda ProgramStart
    sbc #$01
    ldy ProgramStart+1
    bcs SetDataPointer
    dey
;; Stores A/Y in <DataPointer>; `READ`'s finish enters here.
;; Also: RESFIN (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
SetDataPointer:
    sta DataPointer
    sty DataPointer+1
;; Returns; the statement dispatcher, except BASIC 1's early one, returns through it at end of statement.
;; Also: ISCRTS (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
Done:
    rts
    .endproc
    .endscope

.endmacro

;; Emits STOP, END and CONT.
;; Parameters: lineNumberDirect = 1 to detect direct execution through <CurrentLine>, 0 through the text-pointer page;
;;   clearOutput = 1 to clear the output-suppression flag as the program stops, with or without the break message;
;;   stopTest = optional, the operating system's STOP-key test, for a <CheckStop> of BASIC's own that calls it and
;;   falls into `STOP` (the VIC-20's)
.macro StopAndContinue lineNumberDirect, clearOutput, stopTest
    .assert lineNumberDirect = 0 || lineNumberDirect = 1, "lineNumberDirect is 0 or 1."
    .assert clearOutput = 0 || clearOutput = 1, "clearOutput is 0 or 1."

    .ifnblank stopTest
        ;; Tests the STOP key, between statements, and falls into <Statements::Stop>: with the key down, the program
        ;; stops at BREAK. The kernal's test leaves zero set while the key is down, and carry set then too.
        ;; See: <Statements::StopOrEnd>
        ;; Also: ISCNTC (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
        .proc CheckStop
        jsr stopTest
        ; Falls into Statements::Stop.
        .endproc
    .endif

    .scope Statements continued

    ;; Stops the program with the BREAK message.
    ;;
    ;; The statement dispatcher arrives with carry set unless a digit follows, and the Control-C check with carry set
    ;; by its comparison; a set carry goes on to <Statements::StopOrEnd>, which reports BREAK, and a clear one falls
    ;; into <Statements::End>. In BASIC 4, Commodore's kernal listing (K4S79) and Martin Hoffmann-Vetter's
    ;; reconstruction of the kernal (HVK4) call this entry `BSTOP`, an equate of the kernal's.
    ;; In: carry = set for BREAK, zero = set at the end of the statement
    ;; See: <Statements::End>, <Statements::Cont>
    ;; Also: STOP (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
    .proc Stop
    bcs StopOrEnd
    .endproc
    ;; Ends the program without a message: clears carry and falls into <Statements::StopOrEnd>.
    ;; In: zero = set at the end of the statement
    ;; Also: END (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
    .proc End
    clc
    .endproc
    ;; Stops the program. With text after the statement it returns, and the dispatcher reports the syntax error. In a
    ;; program it saves <TextPointer> and <CurrentLine> in <StoppedText> and <StoppedLine> for `CONT`. Then it drops
    ;; the statement loop's return address and reports BREAK, with carry set, or goes to <ReadyForCommand>.
    ;; In: carry = set for BREAK, zero = set at the end of the statement
    ;; Entry:
    ;;   SaveLine = saves <CurrentLine> in <StoppedLine>; the PET's `INPUT` stop paths enter here
    ;;   Finish = reports BREAK through <ReportMessage> with carry set, or goes to <ReadyForCommand>; the dispatchers
    ;;     enter here at the end of the program
    ;; Also: STOPC (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
    .proc StopOrEnd
    bne Cont::Done
    lda TextPointer
    ldy TextPointer+1
    .if lineNumberDirect
        ldx CurrentLine+1
        inx
    .endif
    beq DiscardReturn
    sta StoppedText
    sty StoppedText+1
;; Saves <CurrentLine> in <StoppedLine>; the PET's `INPUT` stop paths enter here.
;; Also: STPEND (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
SaveLine:
    lda CurrentLine
    ldy CurrentLine+1
    sta StoppedLine
    sty StoppedLine+1
;; Drops the statement loop's return address.
;; Also: DIRIS (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
DiscardReturn:
    pla
    pla
;; Reports BREAK through <ReportMessage> with carry set, or goes to <ReadyForCommand>; the dispatchers enter here at
;; the end of the program.
;; Also: ENDCON (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
Finish:
    lda #<BreakMessage
    ldy #>BreakMessage
    .if clearOutput
        ldx #$00
        stx OutputSuppressed
    .endif
    bcc ToReady
    jmp ReportMessage
;; Jumps to <ReadyForCommand>.
;; Also: GORDY (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
ToReady:
    jmp ReadyForCommand
    .endproc

    ;; Resumes at the saved line and text position, or reports CAN'T CONTINUE.
    ;; Entry:
    ;;   Done = returns; STOP and END (through <Statements::StopOrEnd>), NULL, BASIC 1's CLEAR and its early
    ;;     dispatcher return through it
    ;; See: <Statements::Stop>, <ResetStack>
    ;; Also: CONT (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
    .proc Cont
    bne Done
    ldx #ERROR_CANT_CONTINUE
    ldy StoppedText+1
    bne Resume
    jmp ReportError
;; Copies <StoppedText> and <StoppedLine> back.
Resume:
    lda StoppedText
    sta TextPointer
    sty TextPointer+1
    lda StoppedLine
    ldy StoppedLine+1
    sta CurrentLine
    sty CurrentLine+1
;; Returns; STOP and END (through <Statements::StopOrEnd>), NULL, BASIC 1's CLEAR and its early dispatcher return
;; through it.
;; Also: CONTRT (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
Done:
    rts
    .endproc
    .endscope

.endmacro

;; Emits the <Statements::Run> statement entry.
;; Parameters: setMessages = optional, the operating system's message switch, called with 0 to turn its messages off
;;   while the program runs (the VIC-20's)
.macro RunStatement setMessages

    .scope Statements continued

    ;; Clears variables and runs from the beginning or the specified line.
    ;; In: zero = set at the end of the statement; any other text, even one that is not a line number, goes to the
    ;;   line <ReadLineNumber> reads there (line 0 when it reads no digits) after clearing the variables
    ;; Errors: UNDEF'D STATEMENT if the program lacks that line, line 0 included
    ;; See: <ResetProgramState>, <ClearVariables>, <Statements::GoSub::Transfer>
    ;; Also: RUN (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
    .proc Run
    .ifnblank setMessages
        php
        lda #$00                    ; no messages
        jsr setMessages
        plp
    .endif
    bne WithLine
    jmp ResetProgramState

;; Clears variables and goes to the line, as GOTO does.
WithLine:
    jsr ClearVariables
    jmp GoSub::Transfer
    .endproc
    .endscope

.endmacro

;; Emits the <Statements::GoSub> and <Statements::GoTo> entries.
;; Parameters: nextStatement = entry that resumes the statement loop after the transfer;
;;   wholeLineCompare = optional, 1 to search on from the current line whenever the target is above it (the VIC-20's)
.macro GosubAndGoto nextStatement, wholeLineCompare

    .scope Statements continued

    ;; Saves the caller and transfers to its target line.
    ;;
    ;; From low to high addresses the five-byte stack frame holds <TOKEN_GOSUB>, the current line number and the text
    ;; pointer at the target's line number, on its first digit. <Statements::Return> later skips the saved number.
    ;; Entry:
    ;;   Transfer = <GetCurrentCharacter>, <Statements::GoTo>, jmp to the statement loop; RUN with a line enters here
    ;; See: <Statements::GoTo>, <CheckStack>
    ;; Also: GOSUB (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
    .proc GoSub
    lda #$03
    jsr CheckStack
    lda TextPointer+1
    pha
    lda TextPointer
    pha
    lda CurrentLine+1
    pha
    lda CurrentLine
    pha
    lda #TOKEN_GOSUB
    pha
;; <GetCurrentCharacter>, <Statements::GoTo>, jmp to the statement loop; RUN with a line enters here.
;; Also: RUNC2 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
Transfer:
    jsr GetCurrentCharacter
    jsr GoTo
    jmp nextStatement
    .endproc

    ;; Finds the requested line and points <TextPointer> just before its link field.
    ;;
    ;; It searches from just after the current statement's line when the target's high byte is greater than the
    ;; current line's, a later block of 256 line numbers; otherwise, a forward jump within the same block included,
    ;; it searches from <ProgramStart>. Where `wholeLineCompare` is 1 (the VIC-20), it compares the whole line numbers
    ;; instead, so it searches on from the current line whenever the target is greater.
    ;; Errors: UNDEF'D STATEMENT if the line is absent
    ;; Entry:
    ;;   Done = returns; RETURN with trailing text returns through it
    ;; See: <ReadLineNumber>, <FindLine::FromAddress>
    ;; Also: GOTO (M6502, ASTIL, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
    .proc GoTo
    jsr ReadLineNumber
    jsr FindLineEnd
    .ifnblank wholeLineCompare
        .if wholeLineCompare
            sec
            lda CurrentLine
            sbc LineNumber
            lda CurrentLine+1
            sbc LineNumber+1
        .else
            lda CurrentLine+1
            cmp LineNumber+1
        .endif
    .else
        lda CurrentLine+1
        cmp LineNumber+1
    .endif
    bcs SearchFromStart
    tya
    sec
    adc TextPointer
    ldx TextPointer+1
    bcc Search
    inx
    bcs Search
;; A/X = <ProgramStart>.
;; Also: LUK4IT (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
SearchFromStart:
    lda ProgramStart
    ldx ProgramStart+1
;; <FindLine::FromAddress>.
;; Also: LUKALL (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
Search:
    jsr FindLine::FromAddress
;; Not found: UNDEF'D STATEMENT.
;; Also: QFOUND (M6502)
CheckFound:
    bcc Return::UndefinedStatement
    lda SourceStart
    sbc #$01
    sta TextPointer
    lda SourceStart+1
    sbc #$00
    sta TextPointer+1
;; Returns; RETURN with trailing text returns through it.
;; Also: GORTS (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
Done:
    rts
    .endproc
    .endscope

.endmacro

;; Emits the <Statements::Return> entry.
;; Parameters: searchLow = 1 to set <AssignedVariable>'s low byte before searching, 0 to set its high byte;
;;   popEntry = 1 to include the POP test and unwind branch
.macro ReturnStatement searchLow, popEntry
    .assert searchLow = 0 || searchLow = 1, "searchLow must be 0 or 1."
    .assert popEntry = 0 || popEntry = 1, "popEntry must be 0 or 1."

    .scope Statements continued

    ;; Searches past FOR frames and restores the <Statements::GoSub> caller's line and text position.
    ;;
    ;; Where `searchLow` is 1 (AppleSoft, and PET BASIC 1 by default) the search sets the low byte of <AssignedVariable>
    ;; to $FF; where it is 0 (PET BASIC 2 and 4) it sets the high byte instead. The low-byte search can still match a
    ;; FOR variable ending in $FF, or select the first frame if the previous high byte is zero.
    ;;
    ;; Where `popEntry` is 1 (AppleSoft), `POP` enters here too, and Y tells them apart: for `POP` the routine
    ;; discards the frame through AppleSoft's POP finish instead of returning to the caller.
    ;; In: zero = set at the end of the statement, Y = the statement token's offset in the dispatch table
    ;; Errors: RETURN WITHOUT GOSUB if there is no GOSUB frame or, where `searchLow` is 1, if the search stops at a
    ;;   FOR frame it matched; a matched frame whose variable address ends in the GOSUB token raises no error, and
    ;;   RETURN restores the caller from that FOR frame's bytes
    ;; Entry:
    ;;   UndefinedStatement = reports UNDEF'D STATEMENT through <ReportError> (RETURN's error skips its load);
    ;;     <Statements::GoTo> enters here
    ;;   ToSyntaxError = jumps to <SyntaxError>; <Statements::On> enters here
    ;; See: <Statements::GoSub>, <FindForFrame>
    ;; Also: RETURN (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
    .proc Return
    bne GoTo::Done
    lda #$FF
    sta AssignedVariable+1-searchLow
    jsr FindForFrame
    txs
    cmp #TOKEN_GOSUB
    beq RestoreCaller
    ldx #ERROR_RETURN_WITHOUT_GOSUB
    .byte $2C                   ; BIT absolute skips the following LDX on the RETURN error path
;; Reports UNDEF'D STATEMENT through <ReportError> (RETURN's error skips its load); <Statements::GoTo> enters here.
;; Also: USERR (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
UndefinedStatement:
    ldx #ERROR_UNDEFINED_STATEMENT
    jmp ReportError
;; Jumps to <SyntaxError>; <Statements::On> enters here.
;; Also: SNERR2 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
ToSyntaxError:
    jmp SyntaxError
;; Pops the frame into <CurrentLine> and <TextPointer> (POP: to AppleSoft's POP finish), falls into <Statements::Data>
;; to skip the rest.
;; Also: RETU1 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
RestoreCaller:
    pla
    pla
    .if popEntry
        cpy #((TOKEN_POP-TOKEN_END)*2)
        beq PopFinish
    .endif
    sta CurrentLine
    pla
    sta CurrentLine+1
    pla
    sta TextPointer
    pla
    sta TextPointer+1
    .endproc
    .endscope

.endmacro
