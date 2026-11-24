; retrocore: style=strict
; COMMODORE BASIC 1: PATCHES IN THE SCREEN-EDITOR ROM

.include "../../Microsoft6502Basic/MsBasic.Families.asm"

;; Emits the BASIC 1 patches that follow its sign-on message in the editor ROM, then <InterpreterEnd>.
;;
;; BASIC 1's interpreter calls these from code that had no room for the change; Hoffmann-Vetter's reconstructions
;; number them PATCH1 to PATCH7 in ROM order.
.macro CommodoreBasic1EditorPatches

    ;; Stops the program, as `END` does, after a blank terminal INPUT line, without printing `BREAK`.
    ;; Also: INPSTP (UNKN), PATCH1 (HV1, HV1R), BUFFU1 (HV4R)
    .proc StopEmptyInput
    clc
    jmp Statements::StopOrEnd::SaveLine
    .endproc

    ;; Sends a string variable named `T` in the reserved variables' area back to <LoadVariableValue> as `TI$`.
    ;;
    ;; <LoadVariableValue> jumps here, so this routine's `rts` returns from the whole variable evaluation: an ordinary
    ;; string variable keeps the descriptor address <LoadVariableValue> left in <FacMantissa3> and <FacMantissa4>.
    ;; In: A = the name's first character, Y = its second, FacMantissa4 = the value's address (high byte), negative for
    ;;   a reserved variable
    ;; Also: TISTR (UNKN), PATCH2 (HV1, HV1R)
    .proc CheckClockString
    bit FacMantissa4
    bpl NotClock
    cmp #'T'
    bne NotClock
    jmp LoadVariableValue::MatchClockString

;; Not `TI$`: returns from the variable evaluation.
;; Also: TISTR2 (UNKN)
NotClock:
    rts
    .endproc

    ;; Sends a numeric variable on: an ordinary one to <LoadVariableValue::LoadFloat>, a reserved one named `T` to
    ;; <LoadVariableValue::MatchClockNumber> and any other to <LoadVariableValue::MatchStatus>.
    ;; In: A = the name's first character, Y = its second, FacMantissa4 = the value's address (high byte), negative for
    ;;   a reserved variable
    ;; Also: TINUM (UNKN), PATCH3 (HV1, HV1R)
    .proc RouteNumericVariable
    bit FacMantissa4
    bmi Reserved
    jmp LoadVariableValue::LoadFloat

;; A reserved variable: `T` is the clock, anything else goes to the status test.
;; Also: TINUM2 (UNKN)
Reserved:
    cmp #'T'
    beq ToClockNumber
    jmp LoadVariableValue::MatchStatus

;; Jumps on to <LoadVariableValue::MatchClockNumber>.
;; Also: TINUM3 (UNKN)
ToClockNumber:
    jmp LoadVariableValue::MatchClockNumber
    .endproc

    ;; `GET`'s string: stores A as the string's delimiter and advances X to the character, then goes on to
    ;; <ResumeGetString>, which does not return here.
    ;; In: A = the delimiter (0, so the string is the one character), X = <TextPointer>'s low byte, one before the
    ;;   character
    ;; Also: GETSTR (UNKN), PATCH4 (HV1, HV1R)
    .proc BeginGetString
    sta Delimiter
    inx
    jmp ResumeGetString
    .endproc

    ;; Gives the line an input error reports: <DataLine> for `READ`, or a direct line for `GET`.
    ;; In: negative = set for `READ` (from <InputMode>)
    ;; Out: A = <DataLine>'s low byte and Y = its high byte for `READ`; Y = $FF for `GET`
    ;; Also: GETDTL (UNKN), PATCH5 (HV1, HV1R)
    .proc GetDataLine
    bpl NotRead
    lda DataLine
    ldy DataLine+1
    rts

;; `GET`: Y = $FF, the high byte of a direct line.
;; Also: GETDT1 (UNKN)
NotRead:
    ldy #$FF
    rts
    .endproc

    ;; Advances BASIC's <TerminalPosition> for output to the screen only; when it wraps to zero, it restarts from the
    ;; editor's <EditorCursorColumn>.
    ;; In: zero = set when the output goes to the screen
    ;; Also: INCTRM (UNKN), PATCH6 (HV1, HV1R)
    .proc AdvanceTerminalPosition
    bne Done

;; Increments the column; a wrap to zero reloads it from <EditorCursorColumn> and increments again.
;; Also: INCTR1 (UNKN)
Increment:
    inc TerminalPosition
    bne Done
    lda EditorCursorColumn
    sta TerminalPosition
    bne Increment

;; Returns.
;; Also: INCTR2 (UNKN)
Done:
    rts
    .endproc

    ;; Finishes <BeginGetString>: points <TextPointer> at the character, drops the return address of the `jsr` to
    ;; <BeginGetString>, and goes on to <AssignVariableList::StringAtCursor> with A = Y, its ending delimiter.
    ;; In: X = the character's offset, Y = the ending delimiter (on `GET`'s path, the input cursor's high byte, which
    ;;   for BASIC 1's page-zero buffer is 0)
    ;; Also: GETST1 (UNKN), PATCH7 (HV1, HV1R)
    .proc ResumeGetString
    stx TextPointer
    pla
    pla
    tya
    jmp AssignVariableList::StringAtCursor
    .endproc

;; The address after BASIC 1's last patch in the editor ROM's spill (the array patch at $E7F3 comes later);
;; <Functions::Peek>'s ROM guard protects the pages from the ROM's start to the one before its page.
;; Also: LASTWR (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, K4S79, HVK4)
InterpreterEnd:
.endmacro

;; Emits BASIC 1's array-header step at $E7F3, at the end of the editor ROM.
.macro CommodoreBasic1ArrayPatch
    .assert * = $E7F3, "The BASIC 1 array patch must start at $E7F3."

    ;; Gives the size of an array's header, for the string collector's walk through the arrays: two bytes for each
    ;; dimension, plus five.
    ;;
    ;; The shift's carry, the dimension count's bit 7, is added in, as the code it replaces did.
    ;; In: A = the dimension count
    ;; Out: A = the header's size, Y = 0
    ;; Keeps: X
    ;; Also: ARYINC (UNKN)
    .proc ArrayHeaderSize
    asl a
    adc #.sizeof(ArrayHeader)
    ldy #$00
    rts
    .endproc
.endmacro
