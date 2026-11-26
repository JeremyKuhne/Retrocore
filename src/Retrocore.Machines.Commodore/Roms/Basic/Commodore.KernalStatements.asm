; retrocore: style=strict
;; COMMODORE BASIC: THE STANDARD KERNAL'S CALLS AND BASIC'S OWN I/O STATEMENTS
;;
;; With the VIC-20's kernal (<STANDARD_KERNAL> = 1), BASIC calls the kernal through small wrappers that report the
;; error a kernal routine returns with carry set, and parses `LOAD`, `SAVE`, `VERIFY`, `OPEN` and `CLOSE` itself,
;; handing the file's name, number, device and secondary address to the kernal's SETNAM and SETLFS. `SYS` is here
;; too: it loads the registers from the bytes at $030C, which it keeps them in after the call. The floating-point
;; package emits <CommodoreKernalStatements> after `RND`, where the VIC-20's ROM has this code. Including this file
;; emits no bytes.
;;
;; Commodore's names, from its listing of the VIC-20's BASIC (BV20), are kept in each definition's `Also:`.

;; Emits the kernal calls' error check and wrappers, `SYS`, `SAVE`, `VERIFY`, `LOAD`, `OPEN` and `CLOSE`, and the
;; parsing of their parameters.
.macro CommodoreKernalStatements

    ;; The logical file number that `OPEN` and `CLOSE` parse, and in `LOAD` and `SAVE` the device: the first byte of
    ;; <AssignedVariable>, which `WAIT` uses for its AND mask.
    FileParameter = WaitAndMask

    ;; The device number that `OPEN` parses: the second byte of <AssignedVariable>, `WAIT`'s exclusive-OR mask.
    DeviceParameter = WaitXorMask

    ;; <LoadVerifyFlag> and <KernalLoad>'s A for a load.
    LOAD_MODE_LOAD = 0

    ;; <LoadVerifyFlag> and <KernalLoad>'s A for a verify.
    LOAD_MODE_VERIFY = 1

    ;; Reports the error a kernal routine returned with carry set, or, for RS-232's moved top of memory, takes the new
    ;; top and clears the variables as `CLR` does, without closing the files.
    ;;
    ;; Error 0, a call the STOP key ended, is reported as BREAK; the kernal's errors 1 to 9 are BASIC's errors of the
    ;; same numbers.
    ;; In: A = the kernal's error number, or <KERNAL_MEMORY_TOP_MOVED> with the new top of memory in X/Y
    ;; Errors: the error numbered A, or BREAK for 0
    ;; Entry:
    ;;   ReportCode = reports error A
    ;; See: <ReportError>, <ClearVariables::AfterClose>
    ;; Also: EREXIT (BV20)
    .proc ReportKernalError
    cmp #KERNAL_MEMORY_TOP_MOVED
    bne ReportCode
    sty MemoryTop+1
    stx MemoryTop
    jmp ClearVariables::AfterClose

;; Reports error A, taking 0 as BREAK.
;; Also: EREXIX (BV20)
ReportCode:
    tax
    bne Report
    ldx #ERROR_BREAK

;; Reports error X.
;; Also: EREXIY (BV20)
Report:
    jmp ReportError
    .endproc

    ;; Writes a character to the output channel through <KernalCharacterOut>, reporting its error.
    ;; In: A = the character
    ;; Errors: the kernal's, through <ReportKernalError>
    ;; Also: OUTCH (BV20)
    .proc CheckedCharacterOut
    jsr KernalCharacterOut
    bcs ReportKernalError
    rts
    .endproc

    ;; Reads a character from the input channel through <KernalCharacterIn>, reporting its error.
    ;; Out: A = the character
    ;; Errors: the kernal's, through <ReportKernalError>
    ;; Also: INCHR (BV20)
    .proc CheckedCharacterIn
    jsr KernalCharacterIn
    bcs ReportKernalError
    rts
    .endproc

    ;; Makes a logical file the output channel through <KernalSelectOutput>, reporting its error.
    ;; In: X = the logical file number
    ;; Errors: the kernal's, through <ReportKernalError>
    ;; Also: COOUT (BV20)
    .proc CheckedSelectOutput
    jsr KernalSelectOutput
    bcs ReportKernalError
    rts
    .endproc

    ;; Makes a logical file the input channel through <KernalSelectInput>, reporting its error.
    ;; In: X = the logical file number
    ;; Errors: the kernal's, through <ReportKernalError>
    ;; Also: COIN (BV20)
    .proc CheckedSelectInput
    jsr KernalSelectInput
    bcs ReportKernalError
    rts
    .endproc

    ;; Gets a character from the input channel without waiting, through <KernalGetInput>, reporting its error: `GET`'s
    ;; character.
    ;; Out: A = the character, 0 when there is none
    ;; Errors: the kernal's, through <ReportKernalError>
    ;; Also: CZGETL (M6502), CGETL (CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
    .proc GetCharacter
    jsr KernalGetInput
    bcs ReportKernalError
    rts
    .endproc

    .scope Statements continued

    ;; `SYS`: calls machine code at an address, with A, X, Y and the status register loaded from <SysAccumulator>,
    ;; <SysX>, <SysY> and <SysStatus>, and stores the registers there again when it returns.
    ;; Errors: TYPE MISMATCH, ILLEGAL QUANTITY for an address outside 0-65535
    ;; Entry:
    ;;   Returned = where the called routine's RTS comes back to
    ;; See: <ConvertToAddress>
    ;; Also: CSYS (BV20)
    .proc Sys
    jsr EvaluateNumber
    jsr ConvertToAddress

    ; Push the return address, then the status, and load the registers.
    lda #>ReturnAddress
    pha
    lda #<ReturnAddress
    pha
    lda SysStatus
    pha
    lda SysAccumulator
    ldx SysX
    ldy SysY
    plp
    jmp (LineNumber)

;; Where the called routine returns: keeps the registers for the next `SYS` and for a program to read.
Returned:
    php
    sta SysAccumulator
    stx SysX
    sty SysY
    pla
    sta SysStatus
    rts

    ;; The address the called routine's RTS takes, one before <Statements::Sys::Returned>.
    ;; Also: CSYSRZ (BV20)
    ReturnAddress = Returned - 1
    .endproc

    ;; `SAVE`: saves the program, from <ProgramStart> to <VariablesStart>, to the file its parameters name.
    ;; Errors: the kernal's, through <ReportKernalError>; those of <ParseLoadSave>
    ;; Also: CSAVE (BV20)
    .proc Save
    jsr ParseLoadSave
    ldx VariablesStart
    ldy VariablesStart+1
    lda #ProgramStart               ; the zero-page pointer to the start
    jsr KernalSave
    bcs ReportKernalError
    rts
    .endproc

    ;; `VERIFY`: compares the program with the file its parameters name, through <Statements::Load>'s code.
    ;;
    ;; The `BIT` absolute opcode after its first instruction makes `LOAD`'s first instruction an operand, so it goes on
    ;; with <LoadVerifyFlag> 1.
    ;; Errors: VERIFY for a difference; the kernal's, through <ReportKernalError>
    ;; Also: CVERF (BV20)
    .proc Verify
    lda #LOAD_MODE_VERIFY
    .byte $2C                       ; BIT absolute skips Load's LDA
    .endproc
    .assert Load = Verify + 3, "VERIFY's BIT must skip LOAD's first instruction."

    ;; `LOAD`: loads a program from the file its parameters name, at <ProgramStart> unless the secondary address is
    ;; nonzero, or, with <LoadVerifyFlag> 1, verifies it.
    ;;
    ;; Typed directly, a load sets the program's end, prints READY. and relinks the program. In a program, it puts the
    ;; text pointer back to the program's start and relinks it, keeping the variables, so that the program runs from
    ;; its start with the variables it had. A verify that matches prints OK, which the code means for direct mode;
    ;; but it tests the text pointer's low byte, not its page (unlike the load's test), so it prints OK whenever that
    ;; byte is not 2, in a program too.
    ;; Errors: LOAD for a status other than the end of the file, VERIFY for a difference; the kernal's, through
    ;;   <ReportKernalError>
    ;; Entry:
    ;;   Return = returns
    ;; See: <ParseLoadSave>, <RelinkLoadedProgram>
    ;; Also: CLOAD (BV20)
    .proc Load
    lda #LOAD_MODE_LOAD
    sta LoadVerifyFlag
    jsr ParseLoadSave

;; Loads or verifies. Commodore's listing has a wait for the STOP key here, commented out.
;; Also: CLD10 (BV20)
CallLoad:
    lda LoadVerifyFlag
    ldx ProgramStart
    ldy ProgramStart+1
    jsr KernalLoad
    bcs Close::ToReportKernalError
    lda LoadVerifyFlag
    beq Loaded

    ; A verify: a mismatch is an error.
    ldx #ERROR_VERIFY
    jsr KernalReadStatus
    and #STATUS_SECOND_PASS_ERROR
    beq Verified
    jmp ReportError

;; The file matched: prints OK, meant for direct mode.
Verified:
    lda TextPointer                 ; the low byte, where the page was meant
    cmp #INPUT_BUFFER_PAGE
    beq Return
    lda #<OkMessage
    ldy #>OkMessage
    jmp PrintText

;; Returns.
;; Also: CLD20 (BV20)
Return:
    rts

;; A load: any status but the end of the file is an error.
;; Also: CLD50 (BV20)
Loaded:
    jsr KernalReadStatus
    and #<~STATUS_END_OF_FILE
    beq CheckDirect
    ldx #ERROR_LOAD
    jmp ReportError

;; In direct mode, the end of the load is the program's end: sets <VariablesStart>, prints READY. and relinks.
;; Also: CLD60 (BV20)
CheckDirect:
    lda TextPointer+1
    cmp #INPUT_BUFFER_PAGE
    bne InProgram
    stx VariablesStart
    sty VariablesStart+1
    lda #<ReadyMessage
    ldy #>ReadyMessage
    jsr PrintText
    jmp ClearAndRelink

;; In a program: goes back to the program's start and relinks it, keeping the variables.
;; Also: CLD70 (BV20)
InProgram:
    jsr RewindTextPointer
    jmp RelinkLoadedProgram
    .endproc

    ;; `OPEN`: opens the file its parameters describe.
    ;; Errors: the kernal's, through <ReportKernalError>; those of <ParseOpenClose>
    ;; Also: COPEN (BV20)
    .proc Open
    jsr ParseOpenClose
    jsr KernalOpen
    bcs Close::ToReportKernalError
    rts
    .endproc

    ;; `CLOSE`: closes the logical file its parameter names.
    ;; Errors: the kernal's, through <ReportKernalError>, where RS-232's moved top of memory is taken as `CLR` takes
    ;;   it; those of <ParseOpenClose>
    ;; Entry:
    ;;   ToReportKernalError = jumps on to <ReportKernalError>
    ;; Also: CCLOS (BV20)
    .proc Close
    jsr ParseOpenClose
    lda FileParameter
    jsr KernalClose
    bcc Load::Return

;; Jumps on to <ReportKernalError>.
;; Also: JERXIT (BV20)
ToReportKernalError:
    jmp ReportKernalError
    .endproc
    .endscope

    ;; Parses `LOAD`'s, `SAVE`'s and `VERIFY`'s parameters, an optional name, device and secondary address, and gives
    ;; them to the kernal: no name, the tape and secondary address 0 unless given.
    ;; Errors: SYNTAX for a comma with nothing after it, TYPE MISMATCH for a name that is not a string, ILLEGAL
    ;;   QUANTITY for a number outside 0-255
    ;; Also: PLSV (BV20)
    .proc ParseLoadSave
    lda #0                          ; no name
    jsr KernalSetFileName
    ldx #DEVICE_TAPE
    ldy #0
    jsr KernalSetFile
    jsr ReturnIfEnd
    jsr ParseOpenClose::Name
    jsr ReturnIfEnd
    jsr ParseCommaByte
    ldy #0
    stx FileParameter
    jsr KernalSetFile
    jsr ReturnIfEnd
    jsr ParseCommaByte
    txa
    tay
    ldx FileParameter
    jmp KernalSetFile
    .endproc

    ;; Reads a comma and the byte after it.
    ;; Out: X = the byte
    ;; Errors: SYNTAX without the comma or with nothing after it, ILLEGAL QUANTITY for a number outside 0-255
    ;; Also: PLSV7 (BV20)
    .proc ParseCommaByte
    jsr RequireCommaAndValue
    jmp EvaluateByte
    .endproc

    ;; Returns from its caller, as well as itself, at the end of the statement, so that the parameters not given keep
    ;; their defaults.
    ;; Out: A = the current character, when it returns to its caller
    ;; Entry:
    ;;   Return = returns
    ;; Also: PAOC20 (BV20)
    .proc ReturnIfEnd
    jsr GetCurrentCharacter
    bne Return
    pla
    pla

;; Returns.
;; Also: PAOCX (BV20)
Return:
    rts
    .endproc

    ;; Requires a comma followed by more of the statement.
    ;; Out: A = the character after the comma
    ;; Errors: SYNTAX without the comma or at the end of the statement
    ;; Entry:
    ;;   Value = requires more of the statement, without a comma
    ;; Also: PAOC30 (BV20)
    .proc RequireCommaAndValue
    jsr CheckComma

;; Requires more of the statement.
;; Also: PAOC32 (BV20)
Value:
    jsr GetCurrentCharacter
    bne ReturnIfEnd::Return

;; Nothing follows: a syntax error.
;; Also: PAOC40 (BV20)
Fail:
    jmp SyntaxError
    .endproc

    ;; Parses `OPEN`'s and `CLOSE`'s parameters, a logical file number, then an optional device, secondary address
    ;; and name, and gives them to the kernal: no name, the tape, and secondary address 0, or $FF for a device from the
    ;; screen up, unless given.
    ;; Out: <FileParameter> = the logical file number
    ;; Errors: SYNTAX for a missing file number or a comma with nothing after it, TYPE MISMATCH for a name that is not
    ;;   a string, ILLEGAL QUANTITY for a number outside 0-255
    ;; Entry:
    ;;   Name = evaluates a name and gives it to <KernalSetFileName>
    ;; Also: PAOC (BV20)
    .proc ParseOpenClose
    lda #0                          ; no name
    jsr KernalSetFileName
    jsr RequireCommaAndValue::Value
    jsr EvaluateByte
    stx FileParameter
    txa
    ldx #DEVICE_TAPE
    ldy #0
    jsr KernalSetFile
    jsr ReturnIfEnd

    ; The device, with its default secondary address.
    jsr ParseCommaByte
    stx DeviceParameter
    ldy #0
    lda FileParameter
    cpx #DEVICE_SCREEN
    bcc SetDevice
    dey                             ; $FF for the screen and the serial bus

;; Gives the file, the device and the default secondary address to the kernal.
;; Also: PAOC5 (BV20)
SetDevice:
    jsr KernalSetFile
    jsr ReturnIfEnd

    ; The secondary address.
    jsr ParseCommaByte
    txa
    tay
    ldx DeviceParameter
    lda FileParameter
    jsr KernalSetFile

;; The name, after a comma.
;; Also: PAOC7 (BV20)
CommaAndName:
    jsr ReturnIfEnd
    jsr RequireCommaAndValue

;; Evaluates a string and gives it to <KernalSetFileName>.
;; Also: PAOC15 (BV20)
Name:
    jsr EvaluateExpression
    jsr Strings::ReleaseFacString
    ldx Pointer1
    ldy Pointer1+1
    jmp KernalSetFileName
    .endproc
.endmacro
