; retrocore: style=strict
;; DOS 3.3 and 3.2 command interpreter: the handlers that load, save and run programs
;;
;; The handlers that move programs between memory and disk, $A331-$A50F where DOS runs (in both versions): BSAVE, BLOAD
;; and BRUN for binary files, and SAVE, LOAD, RUN and CHAIN for BASIC programs, with the entries DOS puts in BASIC's RUN
;; vector. The command table <CommandHandlers> lists them; OpenClose.asm has the code that opens and closes files.
;;
;; Every file here holds a two-byte length, low byte first, then that many bytes of memory; a binary file has its
;; load address before the length. Each handler opens the file with the file type it expects and checks it
;; (<Commands::OpenAsType> or <Commands::MatchBasic>), writes the two-byte values a byte at a time (the file
;; manager's WRITE request with <TRANSFER_NEXT_BYTE>) or reads them as a two-byte range (READ with
;; <TRANSFER_NEXT_RANGE>), then moves the program in one range and closes the file. docs/Dos.md explains the file
;; manager's requests.
;;
;; Which BASIC is active decides where a program lives. <ActiveBasic> is 0 for Integer BASIC, $40 for Applesoft at $D000
;; (in ROM or a language card) and $80 for Applesoft loaded into lower RAM from the System Master's APPLESOFT file. An
;; Integer BASIC program sits just below HIMEM, from <IBSOP> to <IBHMEM>, and grows down towards LOMEM, <IBLMEM>. An
;; Applesoft program grows up from <ASSOP> (normally $0801) to <ASEOP>, where its variables, <ASEOP2>, begin, below
;; HIMEM, <ASHM1>. The BASIC entry points DOS uses (<BasicRun>, <BasicChain>, <BasicRelink>) are copied into DOS's BASIC
;; vector (DosInit.asm) from one of three images, one per BASIC. A program of the other BASIC's type makes DOS switch
;; BASICs first (<Commands::MatchBasic>, then <Commands::Fp> or <Commands::Int> in MiscCommands.asm).

; Commands: the handlers that load, save and run programs, at $A331.
.scope Commands continued

;; BSAVE: writes L bytes of memory from A to a binary file named in <FileName>: the address, the length, then the
;; bytes; then verifies the file (DOS 3.2 only closes it).
;;
;; At $A331 where DOS runs. Both A and L must be given; otherwise <Scanner::NotCommand> rejects the line as it does a
;; command it does not know.
;; In:    KeywordAddress = the address, KeywordLength = the length
;; Also: EBSV (DOS33, DOS31)
.proc BSave
.assert MASTER || * = $A331, "Commands::BSave is at $A331 where DOS runs."
    lda #OPTION_ADDRESS + OPTION_LENGTH
    and a:GivenKeywords
    cmp #OPTION_ADDRESS + OPTION_LENGTH
    beq BothGiven
    jmp Scanner::NotCommand

;; Opens the file as binary, writes the address and the length, then the bytes.
;; Also: EBSV1 (DOS33, DOS31)
BothGiven:
    lda #FILE_TYPE_BINARY
    jsr OpenAsType
    lda a:KeywordAddress+1
    ldy a:KeywordAddress
    jsr WriteWord
    lda a:KeywordLength+1
    ldy a:KeywordLength
    jsr WriteWord
    lda a:KeywordAddress+1
    ldy a:KeywordAddress
    jmp WriteRange
.endproc

;; BLOAD: reads a binary file named in <FileName> into memory at the address saved in it, or at A when A is given.
;;
;; At $A35D where DOS runs. It opens the file once to check that it is binary, then again through <OpenAsType>.
;; In:    KeywordAddress = the address, if the A option is given
;; Errors: FILE TYPE MISMATCH if the file is not binary
;; Also: EBLD (DOS33, DOS31)
.proc BLoad
.assert MASTER || * = $A35D, "Commands::BLoad is at $A35D where DOS runs."
    jsr OpenFile

;; The type must be binary, the lock bit aside.
;; Also: EBLD2 (DOS33, DOS31)
CheckType:
    lda #~FILE_LOCKED & $FF
    and a:DosFileParameters::FileType
    cmp #FILE_TYPE_BINARY
    beq Binary
    jmp Errors::TypeMismatch

;; Opens the file as binary and reads the address saved in it, which A replaces.
;; Also: EBLD3 (DOS33, DOS31)
Binary:
    lda #FILE_TYPE_BINARY
    jsr OpenAsType
    jsr ReadWord
    tax
    lda a:GivenKeywords
    and #OPTION_ADDRESS
    bne ReadLength
    stx a:KeywordAddress
    sty a:KeywordAddress+1

;; Reads the length, left as the length of the range to read, then the bytes at A.
;; Also: EBLD1 (DOS33, DOS31)
ReadLength:
    jsr ReadWord
    ldx a:KeywordAddress
    ldy a:KeywordAddress+1
    jmp ReadRange
.endproc

;; BRUN: BLOADs the file, then jumps to the address it was loaded at.
;;
;; At $A38E where DOS runs. <ConnectDos> puts DOS's input and output hooks back, as DOS does whenever it leaves. The
;; program is entered with a JMP, so the return address on the stack is <Scanner::Execute>'s: a program that ends with
;; an RTS finishes the command as if BRUN itself had returned.
;; Also: EBRUN (DOS33, DOS31)
.proc BRun
.assert MASTER || * = $A38E, "Commands::BRun is at $A38E where DOS runs."
    jsr BLoad
    jsr ConnectDos
    jmp (KeywordAddress)
.endproc

;; SAVE: writes the BASIC program in memory to a file named in <FileName>: its length, then the program; then verifies
;; the file (DOS 3.2 only closes it).
;;
;; At $A397 where DOS runs. For Applesoft the file type is <FILE_TYPE_APPLESOFT> and the program is <ASSOP> up to
;; <ASEOP>; a program marked run-only (<ASRNX>) is refused with PROGRAM TOO LARGE. For Integer BASIC the type is
;; <FILE_TYPE_INTEGER> and the program is <IBSOP> up to HIMEM, <IBHMEM>. INIT ends here too, to save the greeting
;; program on the disk it has just formatted.
;; Errors: PROGRAM TOO LARGE for a run-only Applesoft program; FILE TYPE MISMATCH if the file exists as another type
;; Also: ESAVE (DOS33, DOS31)
.proc Save
.assert MASTER || * = $A397, "Commands::Save is at $A397 where DOS runs."
    lda a:ActiveBasic
    beq Integer
    lda ASRNX
    bpl Applesoft
    jmp Errors::ProgramTooLarge

;; Applesoft: the length is the program's end less its start.
;; Also: EASAV (DOS33)
Applesoft:
    lda #FILE_TYPE_APPLESOFT
    jsr OpenAsType
    sec
    lda ASEOP
    sbc ASSOP
    tay
    lda ASEOP+1
    sbc ASSOP+1
    jsr WriteWord
    lda ASSOP+1
    ldy ASSOP
    jmp WriteRange

;; Integer BASIC: the length is HIMEM less the program's start.
;; Also: EIBSV (DOS33, DOS31)
Integer:
    lda #FILE_TYPE_INTEGER
    jsr OpenAsType
    sec
    lda IBHMEM
    sbc IBSOP
    tay
    lda IBHMEM+1
    sbc IBSOP+1
    jsr WriteWord
    lda IBSOP+1
    ldy IBSOP
    jmp WriteRange
.endproc

;; Opens the file named in <FileName> as file type A and checks that its type is A.
;;
;; At $A3D5 where DOS runs. A new file is created with type A, if the command allows creating one; an existing file
;; must already have it, the lock bit aside.
;; In:    A = the file type, a FILE_TYPE_ code
;; Out:   WorkPointer = the file's buffer
;; Errors: FILE TYPE MISMATCH, after closing the file
;; Also: SV1 (DOS33, DOS31), SV1A (DOS33, DOS31)
.proc OpenAsType
.assert MASTER || * = $A3D5, "Commands::OpenAsType is at $A3D5 where DOS runs."
    sta a:DosFileParameters::FileType
    pha
    jsr OpenFile
    pla
    jmp CheckFileType
.endproc

;; Writes a two-byte value to the open file, low byte first, and leaves it in <DosFileParameters::RangeLength>, the
;; length of the range to write next.
;;
;; At $A3E0 where DOS runs. RangeLength's high byte is the same byte as <DosFileParameters::FileType>, no longer
;; needed once the file is open; the second write reads the high byte back from there.
;; In:    Y = the low byte, A = the high byte, with the file open and its buffer in the parameter list
;; Out:   DosFileParameters::Request = <REQUEST_WRITE>, ready for <WriteRange>
;; Also: SV2 (DOS33, DOS31)
.proc WriteWord
.assert MASTER || * = $A3E0, "Commands::WriteWord is at $A3E0 where DOS runs."
    sty a:DosFileParameters::RangeLength
    sty a:DosFileParameters::Data
    sta a:DosFileParameters::RangeLength+1

    ; The low byte, then the high byte.
    lda #REQUEST_WRITE
    sta a:DosFileParameters::Request
    lda #TRANSFER_NEXT_BYTE
    sta a:DosFileParameters::Transfer
    jsr RunFileRequest
    lda a:DosFileParameters::RangeLength+1
    sta a:DosFileParameters::Data
    jmp RunFileRequest
.endproc
.if DOS32

;; Writes the range of memory starting at A,Y to the open file, then closes it.
;;
;; At $A3FF where DOS runs. The length is the one <WriteWord> left in <DosFileParameters::RangeLength>. DOS 3.2
;; stores the transfer and goes on into <CallAndClose>, which makes the request and closes the file, without
;; verifying it as DOS 3.3 does.
;; In:    Y = the low byte, A = the high byte of the address
;; Also: SV3 (DOS33, DOS31)
.proc WriteRange
.assert MASTER || * = $A3FF, "Commands::WriteRange is at $A3FF where DOS runs."
    sty a:DosFileParameters::RangeAddress
    sta a:DosFileParameters::RangeAddress+1
    lda #TRANSFER_NEXT_RANGE
    sta a:DosFileParameters::Transfer
    ; Falls into CallAndClose.
.endproc
.else

;; Writes the range of memory starting at A,Y to the open file, closes it and verifies it.
;;
;; At $A3FF where DOS runs. The length is the one <WriteWord> left in <DosFileParameters::RangeLength>. <SaveAndVerify>,
;; in the boot loader's page, stores the transfer and makes the request, then closes the file and ends in
;; <Verify>.
;; In:    Y = the low byte, A = the high byte of the address
;; Also: SV3 (DOS33, DOS31)
.proc WriteRange
.assert MASTER || * = $A3FF, "Commands::WriteRange is at $A3FF where DOS runs."
    sty a:DosFileParameters::RangeAddress
    sta a:DosFileParameters::RangeAddress+1
    lda #TRANSFER_NEXT_RANGE
    jmp SaveAndVerify
.endproc
.endif

;; Makes the file manager request already set up in the parameter list, then closes the file.
;;
;; At $A40A where DOS runs.
;; Also: GODOS (DOS33)
.proc CallAndClose
.assert MASTER || * = $A40A, "Commands::CallAndClose is at $A40A where DOS runs."
    jsr RunFileRequest
    jmp Close
.endproc

;; Reports FILE TYPE MISMATCH for LOAD, RUN or CHAIN of a file that is not a BASIC program.
;;
;; At $A410 where DOS runs.
;; Also: NBPER (DOS33, DOS31)
.proc NotBasicProgram
.assert MASTER || * = $A410, "Commands::NotBasicProgram is at $A410 where DOS runs."
    jmp Errors::TypeMismatch
.endproc

;; LOAD: closes every file except the EXEC file and reads the BASIC program named in <FileName> into memory.
;;
;; At $A413 where DOS runs. A file of the other BASIC's type makes DOS switch BASICs and carry out the command again
;; (<MatchBasic>). Applesoft programs are loaded at <ASSOP> and must end below HIMEM's page. Integer BASIC programs
;; are loaded to end at HIMEM and must start above LOMEM's page. Both checks compare high bytes only, so they can
;; refuse a program that would fit with less than a page to spare.
;;
;; An Applesoft load ends by jumping to <BasicRelink>, Applesoft's own entry for fixing up a program just loaded, and
;; does not come back here. An Integer BASIC load returns.
;; Errors: FILE TYPE MISMATCH if the file is not a BASIC program; PROGRAM TOO LARGE if it does not fit
;; Entry: KeepFiles = without closing the other files (CHAIN)
;; Also: ELOAD (DOS33, DOS31)
.proc Load
.assert MASTER || * = $A413, "Commands::Load is at $A413 where DOS runs."
    jsr CloseAll

;; Opens the file, leaving the other files open.
;; Also: ELOAD0 (DOS33)
KeepFiles:
.assert MASTER || * = $A416, "Commands::Load::KeepFiles is at $A416 where DOS runs."
    jsr OpenFile

;; Keeps the type bits of the two BASICs, and <FILE_TYPE_A>'s; none of them set is not a program. A file of type A
;; passes too, and then matches neither BASIC in <MatchBasic>.
;; Also: ELD1 (DOS33, DOS31)
CheckType:
    lda #FILE_TYPE_INTEGER | FILE_TYPE_APPLESOFT | FILE_TYPE_A
    and a:DosFileParameters::FileType
    beq NotBasicProgram

;; Leaves the file's type, the lock bit and the other types' bits cleared, for <MatchBasic>.
;; Also: ELD2 (DOS33)
StoreType:
    sta a:DosFileParameters::FileType
    lda a:ActiveBasic
    beq Integer

    ; Applesoft: the program goes at ASSOP and ends at ASSOP plus its length, which must be below HIMEM's page.
    lda #FILE_TYPE_APPLESOFT
    jsr MatchBasic
    jsr ReadWord
    clc
    adc ASSOP
    tax
    tya
    adc ASSOP+1
    cmp ASHM1+1
    bcs TooLarge

;; Sets the program's end, where the variables start, reads the program and has Applesoft fix it up.
;; Also: EASL1 (DOS33, DOS31)
SetEnd:
    sta ASEOP+1
    sta ASEOP2+1
    stx ASEOP
    stx ASEOP2
    ldx ASSOP
    ldy ASSOP+1
    jsr ReadRange
    jsr ConnectDos
    jmp (BasicRelink)

;; Integer BASIC: the program ends at HIMEM and starts its length below it, which must be above LOMEM's page.
;; Also: EIBL (DOS33, DOS31)
Integer:
    lda #FILE_TYPE_INTEGER
    jsr MatchBasic
    jsr ReadWord
    sec
    lda IBHMEM
    sbc a:FileHeaderWord
    tax
    lda IBHMEM+1
    sbc a:FileHeaderWord+1
    bcc TooLarge
    tay
    cpy IBLMEM+1
    bcc TooLarge
    beq TooLarge
    sty IBSOP+1
    stx IBSOP
    ; Falls into ReadRange.
.endproc

;; Reads the range of memory starting at X,Y from the open file, then closes it.
;;
;; At $A471 where DOS runs. The length and the request to read a range are the ones <ReadWord> left in the
;; parameter list.
;; In:    X = the low byte, Y = the high byte of the address
;; Also: LD3 (DOS33, DOS31)
.proc ReadRange
.assert MASTER || * = $A471, "Commands::ReadRange is at $A471 where DOS runs."
    stx a:DosFileParameters::RangeAddress
    sty a:DosFileParameters::RangeAddress+1
    jmp CallAndClose
.endproc

;; Reads the next two bytes of the open file into <FileHeaderWord> and leaves them in <DosFileParameters::RangeLength>,
;; as the length of the range to read next.
;;
;; At $A47A where DOS runs. The value is an address for a binary file's first two bytes, a length otherwise; it goes
;; in RangeLength either way, and BLOAD's second call replaces the address with the length.
;; Out:   A = the low byte, Y = the high byte, DosFileParameters::Request = <REQUEST_READ>,
;;   DosFileParameters::Transfer = <TRANSFER_NEXT_RANGE>, ready for <ReadRange>
;; Also: LD2 (DOS33, DOS31)
.proc ReadWord
.assert MASTER || * = $A47A, "Commands::ReadWord is at $A47A where DOS runs."

    ; Two bytes into SVBL.
    lda LoadFieldAddress
    sta a:DosFileParameters::RangeAddress
    lda LoadFieldAddress+1
    sta a:DosFileParameters::RangeAddress+1
    lda #0
    sta a:DosFileParameters::RangeLength+1
    lda #2
    sta a:DosFileParameters::RangeLength
    lda #REQUEST_READ
    sta a:DosFileParameters::Request
    lda #TRANSFER_NEXT_RANGE
    sta a:DosFileParameters::Transfer
    jsr RunFileRequest

    ; The value becomes the next range's length.
    lda a:FileHeaderWord+1
    sta a:DosFileParameters::RangeLength+1
    tay
    lda a:FileHeaderWord
    sta a:DosFileParameters::RangeLength
    rts
.endproc

;; Closes the file and reports PROGRAM TOO LARGE.
;;
;; At $A4AB where DOS runs.
;; Also: MFULL (DOS33, DOS31)
.proc TooLarge
.assert MASTER || * = $A4AB, "Commands::TooLarge is at $A4AB where DOS runs."
    jsr Close
    jmp Errors::ProgramTooLarge
.endproc

;; Returns if the open file is a program for the active BASIC; otherwise switches to the other BASIC and has the
;; command carried out again.
;;
;; At $A4B1 where DOS runs. The command goes in <PendingCommand>. Once the new BASIC has started and asks for its first
;; input, DOS's input hook finishes starting DOS (<FinishStart>), sees <PendingCommand> and runs the command again. For
;; Applesoft the file name is copied to <SecondFileName> as well: if Applesoft has to be loaded into RAM, loading the
;; APPLESOFT file replaces <FileName>, and <FinishStart> copies the name back.
;; In:    A = the type of the active BASIC's programs, <FILE_TYPE_INTEGER> or <FILE_TYPE_APPLESOFT>,
;;   DosFileParameters::FileType = the file's type
;; Also: LD1 (DOS33, DOS31)
.proc MatchBasic
.assert MASTER || * = $A4B1, "Commands::MatchBasic is at $A4B1 where DOS runs."
    cmp a:DosFileParameters::FileType
    beq Done
    ldx a:CommandOffset
    stx a:PendingCommand

    ; Shifting FILE_TYPE_APPLESOFT down leaves FILE_TYPE_INTEGER: under Applesoft, switch to Integer BASIC.
    lsr a
    beq ToApplesoft
    jmp Int

;; Integer BASIC is active, and the file wants Applesoft: keeps the name in <SecondFileName>.
;; Also: LD1A (DOS33, DOS31)
ToApplesoft:
    ldx #CATALOG_NAME_LENGTH - 1

;; Copies one character of the name, from the last down.
;; Also: LD1B (DOS33, DOS31)
CopyName:
    lda a:FileName,x
    sta a:SecondFileName,x
    dex
    bpl CopyName
    jmp Fp

;; The types match.
;; Also: LD1C (DOS33, DOS31)
Done:
    rts
.endproc

;; RUN: LOADs the program named in <FileName> and runs it in the active BASIC.
;;
;; At $A4D1 where DOS runs. Under Applesoft the load does not come back (it ends in <BasicRelink>), so <RunPending> is
;; set first: when Applesoft next prints, DOS's output hook sees <RunPending> and carries on at AfterLoad
;; (<Output::FinishRun>).
;; Entry: AfterLoad = after the load, where <Output::FinishRun> picks up an Applesoft RUN
;; Also: ERUN (DOS33, DOS31)
.proc Run
.assert MASTER || * = $A4D1, "Commands::Run is at $A4D1 where DOS runs."
    lda a:ActiveBasic
    beq LoadProgram
    sta a:RunPending

;; Loads the program; under Integer BASIC, the load returns.
;; Also: ERUN0 (DOS33)
LoadProgram:
    jsr Load

;; Ends the command's line, reconnects DOS and runs the program through the BASIC vector.
;; Also: ERUN1 (DOS33)
AfterLoad:
.assert MASTER || * = $A4DC, "Commands::Run::AfterLoad is at $A4DC where DOS runs."
    jsr OutputReturn
    jsr ConnectDos
    jmp (BasicRun)
.endproc

;; Integer BASIC's RUN entry as DOS sets it: clears the variables, then runs the program from its CHAIN entry, which
;; keeps them.
;;
;; At $A4E5 where DOS runs. Setting <IBSOV>, the end of Integer BASIC's variables, back to LOMEM leaves no variables.
;; Also: IBRUN (DOS33, DOS31)
.proc IntegerRun
.assert MASTER || * = $A4E5, "Commands::IntegerRun is at $A4E5 where DOS runs."
    lda IBLMEM
    sta IBSOV
    lda IBLMEM+1
    sta IBSOV+1
    jmp (BasicChain)
.endproc

;; CHAIN: loads the program named in <FileName> without closing open files, and runs it keeping the variables.
;;
;; At $A4F0 where DOS runs. CHAIN is an Integer BASIC command: the CHAIN vector goes to Integer BASIC's own entry,
;; <IBCHN>, which runs a program without clearing its variables. In Applesoft's vector images CHAIN is the same as
;; RUN.
;; Also: ECHAIN (DOS33, DOS31)
.proc Chain
.assert MASTER || * = $A4F0, "Commands::Chain is at $A4F0 where DOS runs."
    jsr Load::KeepFiles
    jsr OutputReturn
    jsr ConnectDos
    jmp (BasicChain)
.endproc

;; Applesoft's RUN (and CHAIN) entry as DOS sets it, for Applesoft in ROM.
;;
;; At $A4FC where DOS runs. It readies the program to run from its start and clears its variables
;; (<ApplesoftRomRun::ResetProgram>), sets <PromptCharacter> and <ASONERR> to the 0 that call leaves in A, so that
;; ONERR is off and <TestProgramRunning> sees a running program, and starts the program running
;; (<ApplesoftRomRun::Execute>).
;; Also: ASRUN1 (DOS33, DOS31)
.proc ApplesoftRomRun
.assert MASTER || * = $A4FC, "Commands::ApplesoftRomRun is at $A4FC where DOS runs."

;; ROM Applesoft's RUNC: points the text pointer before the program's first line, clears the variables, the strings
;; and the stack, and leaves A = 0.
ResetProgram = $D665

;; ROM Applesoft's <AppleSoft:NXTCO1>: runs statements from the text pointer on.
Execute = $D7D2

    jsr ResetProgram
    sta PromptCharacter
    sta ASONERR
    jmp Execute
.endproc

;; Applesoft's RUN (and CHAIN) entry as DOS sets it, for Applesoft in RAM: as <ApplesoftRomRun>, at RAM Applesoft's
;; addresses.
;;
;; At $A506 where DOS runs.
;; Also: ASRUN2 (DOS33, DOS31)
.proc ApplesoftRamRun
.assert MASTER || * = $A506, "Commands::ApplesoftRamRun is at $A506 where DOS runs."

;; RAM Applesoft's RUNC, as <ApplesoftRomRun::ResetProgram>.
ResetProgram = $0E65

;; RAM Applesoft's <AppleSoft:NXTCO1>, as <ApplesoftRomRun::Execute>.
Execute = $0FD4

    jsr ResetProgram
    sta PromptCharacter
    sta ASONERR
    jmp Execute
.endproc

.endscope
