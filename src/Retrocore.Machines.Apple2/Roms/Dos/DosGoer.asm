; retrocore: style=strict ignore=unlinked-name:SYNTAX -- the SYNTAX ERROR message
;; DOS 3.3 and 3.2 command interpreter: file manager requests, errors and the file buffers' details
;;
;; The glue between the command handlers (OpenClose.asm, LoadSave.asm, MiscCommands.asm) and the file manager,
;; $A6A8-$A7D3 where DOS runs (in both versions). A handler fills in <DosFileParameters>, the file manager's parameter
;; list, and calls <RunFileRequest>, which calls the file manager (<CallFileManager::ForDos>) and deals with its errors.
;; <Errors::Report> prints any DOS error message and hands control back to BASIC. The rest finds and fills the file
;; buffers that <FileBuffers::Build> (BuildFileTables.asm) chains below DOS: <FileBuffers::Find> looks for the buffer of
;; the file named in <FileName>, and <FileBuffers::SetOpenParameters>, <FileBuffers::StoreName> and
;; <FileBuffers::CopyPointers> copy a buffer's details into the parameter list. <WorkPointer> points at the buffer being
;; worked on, at its <FileBuffer> header. docs/Dos.md explains the file manager's requests.
.if DOS32

;; Makes the file manager request in <DosFileParameters>, and handles any error.
;;
;; At $A6A8 where DOS runs. On any error, DOS 3.2 frees the buffer of the file named in <FileName>, so the file is
;; closed. END OF DATA is then not an error: this returns as if a 0 byte had been read. Any other error goes to
;; <Errors::Report>, which does not return.
;; In:    DosFileParameters = the request, filled in
;; Out:   DosFileParameters = as the file manager left it, DosFileParameters::Data = 0 at the end of the data
;; Also: DOSGO (DOS33, DOS31)
.proc RunFileRequest
.assert MASTER || * = $A6A8, "RunFileRequest is at $A6A8 where DOS runs."
    jsr CallFileManager::ForDos
    bcc Done

    ; An error: free the file's buffer, if it has one.
    jsr FileBuffers::Find
    bcs TestEndOfData
    lda #0
    tay
    sta (WorkPointer),y

;; Any error but END OF DATA is reported.
;; Also: DG2 (DOS31)
TestEndOfData:
    lda a:DosFileParameters::ReturnCode
    cmp #ERROR_END_OF_DATA
    bne Errors::Report

    ; The end of the data: a 0 byte.
    ldx #0
    stx a:DosFileParameters::Data

;; Also: DG3 (DOS33)
Done:
    rts
.endproc
.elseif REVISION_B

;; Makes the file manager request in <DosFileParameters>, and handles any error.
;;
;; At $A6A8 where DOS runs. END OF DATA is not an error here: <AppendFix::EndOfData> (BootLoader.asm) checks the file's
;; position, noting in <AppendFix::EndOfFile> whether the file has any data, and comes back to ReturnZero, which returns
;; as if a 0 byte had been read. Any other error frees the buffer of the file named in <FileName> and goes to
;; <Errors::Report> (<AppendFix::CloseOnError>, BootLoader.asm), which does not return.
;; In:    DosFileParameters = the request, filled in
;; Out:   DosFileParameters = as the file manager left it, DosFileParameters::Data = 0 at the end of the data
;; Entry: ReturnZero = after <AppendFix::EndOfData>, at the end of the data
;; Also: DOSGO (DOS33, DOS31)
.proc RunFileRequest
.assert MASTER || * = $A6A8, "RunFileRequest is at $A6A8 where DOS runs."
    jsr CallFileManager::ForDos
    bcc Done
    lda a:DosFileParameters::ReturnCode
    cmp #ERROR_END_OF_DATA
    beq EndOfData
    jmp AppendFix::CloseOnError

;; The end of the data: <AppendFix::EndOfData> deals with the file's position.
;; Also: YESEOF (DOS33)
EndOfData:
    jmp AppendFix::EndOfData
    nop                             ; not reached

;; Revision B: <AppendFix::ClearUnlessAppend> (MsWait.asm) clears <AppendFix::EndOfFile> unless the command is APPEND.
;; Then a 0 byte.
;; Also: DOSGO2A (DOS33)
ReturnZero:
.assert MASTER || * = $A6BB, "RunFileRequest::ReturnZero is at $A6BB where DOS runs."
    jsr AppendFix::ClearUnlessAppend
    ldx #0
    stx a:DosFileParameters::Data

;; Also: DG3 (DOS33)
Done:
    rts
.endproc
.else

;; Makes the file manager request in <DosFileParameters>, and handles any error.
;;
;; At $A6A8 where DOS runs. END OF DATA is not an error here: <AppendFix::EndOfData> (BootLoader.asm) checks the file's
;; position, noting in <AppendFix::EndOfFile> whether the file has any data, and comes back to ReturnZero, which returns
;; as if a 0 byte had been read. Any other error frees the buffer of the file named in <FileName> and goes to
;; <Errors::Report> (<AppendFix::CloseOnError>, BootLoader.asm), which does not return.
;; In:    DosFileParameters = the request, filled in
;; Out:   DosFileParameters = as the file manager left it, DosFileParameters::Data = 0 at the end of the data
;; Also: DOSGO (DOS33, DOS31)
.proc RunFileRequest
.assert MASTER || * = $A6A8, "RunFileRequest is at $A6A8 where DOS runs."
    jsr CallFileManager::ForDos
    bcc Done
    lda a:DosFileParameters::ReturnCode
    cmp #ERROR_END_OF_DATA
    beq EndOfData
    jmp AppendFix::CloseOnError

;; The end of the data: <AppendFix::EndOfData> deals with the file's position.
;; Also: YESEOF (DOS33)
EndOfData:
    jmp AppendFix::EndOfData

    ; Two bytes no code reaches: where the 1983 DOS has its own unreached NOP and the first byte of its revision B
    ; call to AppendFix::ClearUnlessAppend.
    nop
    nop

;; Where <AppendFix::EndOfData> comes back at the end of the data: returns as if a 0 byte had been read.
;; Also: DOSGO2A (DOS33)
ReturnZero:
.assert MASTER || * = $A6BC, "RunFileRequest::ReturnZero is at $A6BC where DOS runs."
    nop
    nop
    ldx #0
    stx a:DosFileParameters::Data

;; Also: DG3 (DOS33)
Done:
    rts
.endproc
.endif

;; DOS's error report: the routines that load an error number and report it, and <Errors::Report>, which prints the
;; message and goes back to BASIC.
;;
;; The error numbers are the ERROR_ codes, 1 to 15, and the messages are in <EMSG>. In DosGoer.asm, $A6C4-$A719 where
;; DOS runs.
.scope Errors

;; Reports SYNTAX ERROR.
;;
;; At $A6C4 where DOS runs. It does not return.
;; Also: ESYNTX (DOS33, DOS31)
.proc Syntax
.assert MASTER || * = $A6C4, "Errors::Syntax is at $A6C4 where DOS runs."
    lda #ERROR_SYNTAX
    bne Report                      ; always
.endproc

;; Reports NO BUFFERS AVAILABLE.
;;
;; At $A6C8 where DOS runs. It does not return.
;; Also: ENFA (DOS33, DOS31)
.proc NoBuffers
.assert MASTER || * = $A6C8, "Errors::NoBuffers is at $A6C8 where DOS runs."
    lda #ERROR_NO_BUFFERS
    bne Report                      ; always
.endproc

;; Reports PROGRAM TOO LARGE.
;;
;; At $A6CC where DOS runs. It does not return.
;; Also: MFERR (DOS33, DOS31)
.proc ProgramTooLarge
.assert MASTER || * = $A6CC, "Errors::ProgramTooLarge is at $A6CC where DOS runs."
    lda #ERROR_PROGRAM_TOO_LARGE
    bne Report                      ; always
.endproc

;; Reports FILE TYPE MISMATCH.
;;
;; At $A6D0 where DOS runs. It does not return.
;; Also: ETYP (DOS33), ERNU1 (DOS33, DOS31)
.proc TypeMismatch
.assert MASTER || * = $A6D0, "Errors::TypeMismatch is at $A6D0 where DOS runs."
    lda #ERROR_FILE_TYPE_MISMATCH
    ; Falls into Report.
.endproc

;; Prints a DOS error message and returns to BASIC.
;;
;; At $A6D2 where DOS runs. It clears the input, output and RUN states. If Applesoft's `ONERR` GOTO is in force
;; (<ASONERR>), nothing is printed, so that the program's handler can deal with the error; otherwise a Return, the bell
;; and a Return, the message and a Return. Then, if a program is running, it goes to BASIC's error entry (through
;; <BasicError>) with the error number in X; in immediate mode, to BASIC's command level (through <BasicWarmStart>). The
;; BASIC vector is in DosInit.asm. It does not return to its caller.
;; In:    A = the error number, an ERROR_ code (1-15)
;; Also: ERROR (DOS33, DOS31)
.proc Report
.assert MASTER || * = $A6D2, "Errors::Report is at $A6D2 where DOS runs."

;; What A holds for BASIC's error entry: Control-C's code, without bit 7. Applesoft's entry (<ASBRK1>) goes to the
;; `ONERR` GOTO handler, with X as the error number, if one is in force; otherwise it compares A with Control-C and
;; stops the program with BREAK and the line's number, as Control-C does. Integer BASIC's entry (<IBBRK>) ignores A.
CONTROL_C = 3

    ; The error number, and no READ, WRITE or RUN in progress (DosPatches.asm).
    sta a:HookA
    jsr ClearAllStates

    ; No message while Applesoft's `ONERR` GOTO is in force.
    lda a:ActiveBasic
    beq PrintMessages
    lda ASONERR
    bmi ToBasic

;; Prints a Return, the bell and a Return (message 0), the error's message, and a Return.
;; Also: ERNAS (DOS33, DOS31)
PrintMessages:
    ldx #0
    jsr PrintMessage
    ldx a:HookA
    jsr PrintMessage
    jsr OutputReturn

;; Reconnects DOS and goes to BASIC: its error entry while a program runs, its command level otherwise.
;; Also: ERRTN (DOS33, DOS31)
ToBasic:
    jsr ConnectDos
    jsr TestProgramRunning
    ldx a:HookA
    lda #CONTROL_C
    bcs ToCommandLevel
    jmp (BasicError)

;; Immediate mode: BASIC's command level.
;; Also: ERRTN1 (DOS33)
ToCommandLevel:
    jmp (BasicWarmStart)
.endproc

;; Prints error message X through the real output routine.
;;
;; At $A702 where DOS runs. <ErrorMessageOffsets> gives each error number's offset in <ErrorMessages>, whose messages
;; are written with <MarkedText>: only a message's last character has bit 7 set. Each character is printed with bit 7
;; set.
;; In:    X = the error number, or 0 for a Return, the bell and a Return
;; Uses:  A, X, InterpreterScratch
;; Also: EMPR (DOS33, DOS31)
.proc PrintMessage
.assert MASTER || * = $A702, "Errors::PrintMessage is at $A702 where DOS runs."

;; Bit 7 of a character, set in the Apple II's normal text.
HIGH_BIT = $80

    lda a:ErrorMessageOffsets,x
    tax

;; Prints the character at offset X in <ErrorMessages>, until the message's last.
;; Also: EMPR1 (DOS33, DOS31)
FromOffset:
    stx a:InterpreterScratch
    lda a:ErrorMessages,x
    pha
    ora #HIGH_BIT
    jsr CallRealOutput
    ldx a:InterpreterScratch
    inx
    pla
    bpl FromOffset
    rts
.endproc

.endscope

;; The DOS file buffers: building their chain below DOS, walking it, finding the buffer of a named file, and copying
;; a buffer's details into DOS's parameter list.
;;
;; Each buffer is laid out as <FileBuffer>, and <WorkPointer> points at the one being worked on. In DosGoer.asm
;; ($A71A-$A75A and $A764-$A7C3 where DOS runs) and BuildFileTables.asm ($A7D4-$A850).
.scope FileBuffers

;; Fills in the parameter list for opening a file: the volume, drive and slot from the command's options and the
;; address of <FileName>, and notes the buffer in <CurrentFileBuffer>.
;;
;; At $A71A where DOS runs.
;; In:    WorkPointer = the file's buffer, KeywordVolume = the volume, KeywordDrive = the drive, KeywordSlot = the slot
;; Uses:  A
;; Keeps: X, Y
;; Also: OPNSUP (DOS33, DOS31)
.proc SetOpenParameters
.assert MASTER || * = $A71A, "FileBuffers::SetOpenParameters is at $A71A where DOS runs."
    lda a:KeywordVolume
    sta a:DosFileParameters::Volume
    lda a:KeywordDrive
    sta a:DosFileParameters::Drive
    lda a:KeywordSlot
    sta a:DosFileParameters::Slot
    lda FileNameAddress
    sta a:DosFileParameters::Name
    lda FileNameAddress+1
    sta a:DosFileParameters::Name+1
    lda WorkPointer
    sta a:CurrentFileBuffer
    lda WorkPointer+1
    sta a:CurrentFileBuffer+1
    rts
.endproc

;; Copies <FileName> into a buffer's name, which marks the buffer as in use by that file.
;;
;; At $A743 where DOS runs.
;; In:    WorkPointer = the buffer
;; Out:   Y = $FF
;; Uses:  A
;; Keeps: X
;; Also: MVFN1 (DOS33, DOS31)
.proc StoreName
.assert MASTER || * = $A743, "FileBuffers::StoreName is at $A743 where DOS runs."
    ldy #CATALOG_NAME_LENGTH - 1

;; Copies one character, from the last down.
;; Also: MVFN1A (DOS33, DOS31)
Loop:
    lda a:FileName,y
    sta (WorkPointer),y
    dey
    bpl Loop
    rts
.endproc

;; Copies a buffer's four addresses into the parameter list, from <DosFileParameters::WorkArea> on: its work area,
;; track/sector list buffer and data buffer, and the next buffer's, which lands in the spare bytes after them.
;;
;; At $A74E where DOS runs.
;; In:    WorkPointer = the buffer
;; Out:   Y = <FILE_BUFFER_HEADER_SIZE>
;; Uses:  A
;; Keeps: X
;; Also: MVBUFP (DOS33, DOS31)
.proc CopyPointers
.assert MASTER || * = $A74E, "FileBuffers::CopyPointers is at $A74E where DOS runs."
    ldy #FileBuffer::WORK_AREA

;; Copies one byte.
;; Also: MVBP1 (DOS33, DOS31)
Loop:
    lda (WorkPointer),y
    sta a:DosFileParameters::WorkArea - FileBuffer::WORK_AREA,y
    iny
    cpy #FILE_BUFFER_HEADER_SIZE
    bne Loop
    rts
.endproc

.endscope

;; Clears the input and output states: no READ, no WRITE, and the next character printed starts a line.
;;
;; At $A75B where DOS runs. <ClearAllStates> (DosPatches.asm) clears the RUN state too.
;; Out:   Y = 0, InputState = 0, OutputState = 0
;; Keeps: A, X
;; Also: CLRSTS (DOS33, DOS31)
.proc ClearStates
.assert MASTER || * = $A75B, "ClearStates is at $A75B where DOS runs."
    ldy #0
    sty a:InputState
    sty a:OutputState
    rts
.endproc

; FileBuffers: finding a file's buffer and walking the chain, at $A764.
.scope FileBuffers continued

;; Looks for the buffer of the file named in <FileName>, noting a free one on the way.
;;
;; At $A764 where DOS runs. The chain goes down in memory, so the last free buffer passed is the lowest of those
;; passed. In DOS 3.3, `AppendFix::CloseOnError` (BootLoader.asm) calls it too.
;; Out:   carry = clear if the file is open, set if not, WorkPointer = the file's buffer, if it is open, ParsedNumber
;;   = the last free buffer before the file's, or before the end of the chain if the file is not open, with its
;;   high byte 0 if there is none
;; Uses:  A, X, Y
;; Also: FILSRC (DOS33, DOS31)
.proc Find
.assert MASTER || * = $A764, "FileBuffers::Find is at $A764 where DOS runs."
    lda #0
    sta ParsedNumber+1
    jsr First
    jmp TestBuffer

;; Moves on to the next buffer, until the end of the chain.
;; Also: FLS1 (DOS33, DOS31)
NextBuffer:
    jsr Next
    beq NotFound

;; A free buffer is noted; one in use has its name compared.
;; Also: FLS1A (DOS33, DOS31)
TestBuffer:
    jsr TestInUse
    bne CompareName
    lda WorkPointer
    sta ParsedNumber
    lda WorkPointer+1
    sta ParsedNumber+1
    bne NextBuffer                  ; always: a buffer is never in page 0

;; Also: FLS2 (DOS33, DOS31)
CompareName:
    ldy #CATALOG_NAME_LENGTH - 1

;; Compares one character, from the last down; the whole name matches: carry clear.
;; Also: FLS3 (DOS33, DOS31)
CompareCharacter:
    lda (WorkPointer),y
    cmp a:FileName,y
    bne NextBuffer
    dey
    bpl CompareCharacter
    clc
    rts

;; The end of the chain: carry set.
;; Also: FLS4 (DOS33, DOS31)
NotFound:
    sec
    rts
.endproc

;; Points <WorkPointer> at the first file buffer, the one <FileBuffersAddress> gives.
;;
;; At $A792 where DOS runs.
;; Out:   WorkPointer = the first buffer, A = its high byte, X = the same, zero = clear
;; Keeps: Y
;; Also: TSINIT (DOS33, DOS31)
.proc First
.assert MASTER || * = $A792, "FileBuffers::First is at $A792 where DOS runs."
    lda FileBuffersAddress
    ldx FileBuffersAddress+1
    bne Next::Point                 ; always: a buffer is never in page 0
.endproc

;; Points <WorkPointer> at the next file buffer, from the link in the buffer's header.
;;
;; At $A79A where DOS runs.
;; In:    WorkPointer = a buffer
;; Out:   zero = set at the end of the chain (WorkPointer then unchanged), WorkPointer = the next buffer otherwise,
;;   A = its high byte, X = the same
;; Uses:  Y
;; Entry: Point = with X,A = the buffer's address (<First>'s)
;; Also: TSNXT (DOS33, DOS31)
.proc Next
.assert MASTER || * = $A79A, "FileBuffers::Next is at $A79A where DOS runs."

    ; A high byte of 0: no next buffer.
    ldy #FileBuffer::NEXT + 1
    lda (WorkPointer),y
    beq Done
    tax
    dey
    lda (WorkPointer),y

;; Stores the address, and gives A = X = the high byte, which is never 0: zero clear.
;; Also: TSST (DOS33, DOS31)
Point:
.assert MASTER || * = $A7A4, "FileBuffers::Next::Point is at $A7A4 where DOS runs."
    stx WorkPointer+1
    sta WorkPointer
    txa

;; Also: TSR (DOS33, DOS31)
Done:
    rts
.endproc

;; Tests whether a buffer is in use.
;;
;; At $A7AA where DOS runs.
;; In:    WorkPointer = the buffer
;; Out:   A = the first byte of its file name, zero = set if the buffer is free, Y = 0
;; Keeps: X
;; Also: TSTOPN (DOS33, DOS31)
.proc TestInUse
.assert MASTER || * = $A7AA, "FileBuffers::TestInUse is at $A7AA where DOS runs."
    ldy #FileBuffer::NAME
    lda (WorkPointer),y
    rts
.endproc

;; Tests whether a buffer is the one the EXEC file is using.
;;
;; At $A7AF where DOS runs. With no EXEC file, the answer "no" gets its clear zero flag from a DEX, so it is right
;; only when X is not 1 on entry. <Commands::CloseAll> and <Commands::Close> call it after this scope's routines,
;; which leave X = a buffer's high byte. Through <Commands::CloseBuffer>, TextFile's routines call it with X as
;; <RunFileRequest> or <TestProgramRunning> left it; if that is 1 the answer is wrong, but harmlessly so: CloseBuffer
;; then only clears <ExecState>, which is 0 already.
;; In:    WorkPointer = the buffer, X = anything but 1
;; Out:   zero = set if an EXEC file is open in this buffer
;; Uses:  A, X
;; Keeps: Y
;; Also: TSTEXC (DOS33, DOS31)
.proc TestExec
.assert MASTER || * = $A7AF, "FileBuffers::TestExec is at $A7AF where DOS runs."
    lda a:ExecState
    beq No
    lda a:ExecFileBuffer
    cmp WorkPointer
    bne Done                        ; zero clear: another buffer
    lda a:ExecFileBuffer+1
    cmp WorkPointer+1
    beq Done                        ; zero set: this one

;; Also: TXC1 (DOS33, DOS31)
No:
    dex

;; Also: TXC2 (DOS33, DOS31)
Done:
    rts
.endproc

.endscope

; Commands: checking an opened file's type, at $A7C4.
.scope Commands continued

;; Checks that the file just opened is of the type the command wants, the lock bit aside; on a mismatch closes it
;; and reports FILE TYPE MISMATCH.
;;
;; At $A7C4 where DOS runs. It returns only if the types match.
;; In:    A = the type wanted, a FILE_TYPE_ code, DosFileParameters::FileType = the file's type, from the file
;;   manager
;; Keeps: X, Y
;; Also: TSTFUC (DOS33, DOS31)
.proc CheckFileType
.assert MASTER || * = $A7C4, "Commands::CheckFileType is at $A7C4 where DOS runs."
    eor a:DosFileParameters::FileType
    beq Done
    and #~FILE_LOCKED & $FF
    beq Done
    jsr Close
    jmp Errors::TypeMismatch

;; Also: TFUCR (DOS33, DOS31)
Done:
    rts
.endproc

.endscope
