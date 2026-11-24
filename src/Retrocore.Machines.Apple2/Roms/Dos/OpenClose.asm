; retrocore: style=strict ignore=unlinked-name:PR -- the PR# command
;; DOS 3.3 and 3.2 command interpreter: the scanner's helpers and the handlers that open and close files
;;
;; The first of the three command handler modules, $A193-$A330 where DOS runs (in both versions). It starts with the
;; helpers the command scanner (CommandScan.asm) uses to read the command line in <InputBuffer>: the next character, the
;; next non-blank, and a decimal or $hex number. Then come the handlers for PR#, IN#, MON, NOMON, MAXFILES, DELETE,
;; LOCK, UNLOCK, VERIFY, RENAME, APPEND, OPEN and CLOSE, which the command table <CommandHandlers> lists, and the code
;; they and the other handlers share to open and close files.
;;
;; A handler finds the parsed command in the command interpreter's variables: the file names in <FileName> and
;; <SecondFileName>, the options given as bits in <GivenKeywords> and their values in <KeywordVolume>, <KeywordDrive>,
;; <KeywordSlot>, <KeywordLength>, <KeywordRecord>, <KeywordByte> and <KeywordAddress>, the C, I and O of MON and NOMON
;; in <EchoOptions>, and a number given after the command in <ParsedNumber>. It acts on files by filling in
;; <DosFileParameters>, the file manager's parameter list, and calling <RunFileRequest> (DosGoer.asm). That routine
;; deals with errors itself: it frees the file's buffer, prints the message and leaves to BASIC, so a handler only sees
;; calls that worked. docs/Dos.md explains the file manager's requests.
;;
;; Each open file has a DOS buffer, one of MAXFILES chained in high memory (BuildFileTables.asm), laid out as
;; <FileBuffer>. <WorkPointer> points at the buffer being worked on: at its file name, which is followed by the
;; addresses of its work area, track/sector list buffer and data buffer, then the next buffer's address. A first
;; name byte of 0 marks the buffer free; copying a name in claims it. LoadSave.asm and MiscCommands.asm hold the
;; other handlers; docs/Dos.md describes the command interpreter as a whole.

; Scanner: the helpers that read characters and numbers from the command line, at $A193.
.scope Scanner continued

;; Reads the next character of the command line and steps past it, unless it is the Return that ends the line.
;;
;; At $A193 where DOS runs.
;; In:    LineIndex = the index of the character in <InputBuffer>
;; Out:   A = the character, zero = set if it is a comma or the Return, LineIndex = past it unless it is the Return
;; Uses:  X
;; Keeps: Y
;; Also: GNXTC (DOS33, DOS31)
.proc NextCharacter
.assert MASTER || * = $A193, "Scanner::NextCharacter is at $A193 where DOS runs."
    ldx a:LineIndex
    lda InputBuffer,x

    ; The line ends in a Return: stay on it, so that every later call sees it again.
    cmp #KEY_RETURN
    beq Done
    inx
    stx a:LineIndex
    cmp #',' + $80

;; Returns, with zero set for a comma or the Return. <NextNonBlank> returns through it too.
;; Also: GNXTCR (DOS33, DOS31)
Done:
    rts
.endproc

;; Reads the next character of the command line that is not a space.
;;
;; At $A1A4 where DOS runs.
;; In:    LineIndex = the index of the next character in <InputBuffer>
;; Out:   A = the character, zero = set if it is a comma or the Return, LineIndex = past it unless it is the Return
;; Uses:  X
;; Keeps: Y
;; Also: GNBC (DOS33, DOS31)
.proc NextNonBlank
.assert MASTER || * = $A1A4, "Scanner::NextNonBlank is at $A1A4 where DOS runs."
    jsr NextCharacter
    beq NextCharacter::Done
    cmp #' ' + $80
    beq NextNonBlank
    rts
.endproc

;; Clears <DosFileParameters>, the file manager's parameter list, to zeros; <RunCommand> does it before every command.
;;
;; At $A1AE where DOS runs.
;; Out:   A = 0, Y = 0
;; Keeps: X
;; Also: CLRCCB (DOS33, DOS31)
.proc ClearParameterList
.assert MASTER || * = $A1AE, "Scanner::ClearParameterList is at $A1AE where DOS runs."
    lda #0
    ldy #FILE_PARAMETERS_SIZE

;; Clears one byte, from the last down.
;; Also: CLC1 (DOS33, DOS31)
Loop:
    sta a:DosFileParameters - 1,y
    dey
    bne Loop
    rts
.endproc

;; Converts the number at <LineIndex> in the command line, decimal or, after a "$", hexadecimal, to 16 bits in
;; <ParsedNumber>.
;;
;; At $A1B9 where DOS runs. The number ends at a comma or the Return; spaces between its digits are skipped, and an
;; empty number gives 0.
;;
;; In decimal, a carry out of the last addition of a digit counts as too large (carry set, as for a character that is
;; not a digit), but the multiplications are not checked: the bits that the first and the last of a digit's three
;; doublings shift out of the top are added into the low byte by the addition that follows, and the middle one's is
;; lost, so a number past 65535 can come out as a wrong value instead of an error. In hexadecimal, digits beyond
;; four simply push the first ones out.
;; In:    LineIndex = the index of the first character in <InputBuffer>
;; Out:   carry = clear for a number, set if a character is not a digit, ParsedNumber = the number, X = its low
;;   byte, A = its high byte
;; Uses:  Y, LineIndex
;; Also: GETNUM (DOS33, DOS31)
.proc ParseNumber
.assert MASTER || * = $A1B9, "Scanner::ParseNumber is at $A1B9 where DOS runs."

;; What a letter's digit is less 10 above "9", after the "0" is taken off: "A" is 10.
LETTER_GAP = 'A' - '9' - 1

    lda #0
    sta ParsedNumber
    sta ParsedNumber+1

    ; The first character decides the base. Keep NextNonBlank's zero flag (a comma or the Return: no number) past
    ; the test for "$".
    jsr NextNonBlank
    php
    cmp #'$' + $80
    beq Hex
    plp
    jmp TestEnd

;; Reads the next decimal digit.
;; Also: GN2 (DOS33, DOS31)
NextDigit:
    jsr NextNonBlank

;; A comma or the Return ends the number, with the carry clear.
;; Also: GN2A (DOS33, DOS31)
TestEnd:
    bne DecimalDigit
    ldx ParsedNumber
    lda ParsedNumber+1
    clc
    rts

;; A decimal digit: the number times 10 plus the digit, made as the number times 2 plus the digit (kept in Y,X), plus
;; the number times 8.
;; Also: GN3 (DOS33, DOS31)
DecimalDigit:
    sec
    sbc #'0' + $80
    bmi NotDigit
    cmp #10
    bcs NotDigit
    jsr Double
    adc ParsedNumber
    tax
    lda #0
    adc ParsedNumber+1
    tay
    jsr Double
    jsr Double
    txa
    adc ParsedNumber
    sta ParsedNumber
    tya
    adc ParsedNumber+1
    sta ParsedNumber+1
    bcc NextDigit

;; Not a digit, or a decimal number too large: carry set.
;; Also: GN4 (DOS33, DOS31)
NotDigit:
    sec
    rts

;; Doubles <ParsedNumber>.
;; Out:   carry = the bit shifted out of the top
;; Keeps: A, X, Y
;; Also: GN5 (DOS33, DOS31)
Double:
    asl ParsedNumber
    rol ParsedNumber+1
    rts

;; A "$" came first: the digits that follow are hexadecimal, 0-9 and A-F. Drops the flags kept for the first
;; character.
;; Also: HEXNUM (DOS33, DOS31)
Hex:
    plp

;; Reads the next hexadecimal digit; a comma or the Return ends the number.
;; Also: HN0 (DOS33, DOS31)
NextHexDigit:
    jsr NextNonBlank
    beq TestEnd
    sec
    sbc #'0' + $80
    bmi NotDigit
    cmp #10
    bcc HexDigit

    ; A to F: the carry is set, so this takes off LETTER_GAP.
    sbc #LETTER_GAP
    bmi NotDigit
    cmp #16
    bcs NotDigit

;; Shifts the number four bits up and puts the digit in the low four.
;; Also: HN1 (DOS33, DOS31)
HexDigit:
    ldx #4

;; One of the four doublings.
;; Also: HN2 (DOS33)
Shift:
    jsr Double
    dex
    bne Shift
    ora ParsedNumber
    sta ParsedNumber
    jmp NextHexDigit
.endproc

.endscope

;; The command handlers, one for each of DOS's 28 commands and named for its word (<Commands::Catalog>,
;; <Commands::PrNumber>), and the code they share to open, read, write and close files.
;;
;; The command table <CommandHandlers> lists the handlers; the scanner (<Scanner>) has left the command's file names,
;; options and number in the command interpreter's variables when one runs. A handler acts on files by filling in
;; <DosFileParameters> and calling <RunFileRequest>, mostly through <Commands::FileRequest>, which lends the file a DOS
;; buffer (<FileBuffers>). The handlers are in OpenClose.asm, LoadSave.asm and MiscCommands.asm, $A229-$A60D where DOS
;; runs, and <Commands::CheckFileType> is at $A7C4 (DosGoer.asm). docs/Dos.md describes the commands.
.scope Commands

;; PR#: sends output to the slot the scanner left in <ParsedNumber> (0-7), through the Monitor's <SetOutput>.
;;
;; At $A229 where DOS runs. While DOS carries out a command, the Monitor's output and input hooks hold the real output
;; and input routines (DOS put them back when it took the command), so the Monitor changes the device DOS passes
;; characters on to. When DOS leaves, <ConnectDos> saves the new routine and puts DOS's own hooks back in front of
;; it.
;; In:    ParsedNumber = the slot
;; Also: EPR (DOS33, DOS31)
.proc PrNumber
.assert MASTER || * = $A229, "Commands::PrNumber is at $A229 where DOS runs."
    lda ParsedNumber
    jmp SetOutput
.endproc

;; IN#: takes input from the slot the scanner left in <ParsedNumber> (0-7), through the Monitor's <SetInput>.
;;
;; At $A22E where DOS runs. As with PR#, the Monitor changes the routine that DOS's input hook passes on to.
;; In:    ParsedNumber = the slot
;; Also: EIN (DOS33, DOS31)
.proc InNumber
.assert MASTER || * = $A22E, "Commands::InNumber is at $A22E where DOS runs."
    lda ParsedNumber
    jmp SetInput
.endproc

;; MON: turns on the echo of commands (C), disk input (I) or disk output (O), as <EchoOptions> gives them.
;;
;; At $A233 where DOS runs.
;; In:    EchoOptions = <ECHO_COMMANDS>, <ECHO_INPUT> and <ECHO_OUTPUT> for the C, I and O given
;; Out:   EchoFlags = with those bits set
;; Keeps: X, Y
;; Also: EMON (DOS33, DOS31)
.proc Mon
.assert MASTER || * = $A233, "Commands::Mon is at $A233 where DOS runs."
    lda a:EchoFlags
    ora a:EchoOptions
    sta a:EchoFlags
    rts
.endproc

;; NOMON: turns off the echoes <EchoOptions> gives.
;;
;; At $A23D where DOS runs. With C, it first prints a Return: the command's own line was echoed while MON C was on,
;; but its Return is echoed only on the way out (<EndCommand>), which no longer happens once C is off.
;; In:    EchoOptions = <ECHO_COMMANDS>, <ECHO_INPUT> and <ECHO_OUTPUT> for the C, I and O given
;; Out:   EchoFlags = with those bits clear
;; Also: ENOMON (DOS33, DOS31)
.proc NoMon
.assert MASTER || * = $A23D, "Commands::NoMon is at $A23D where DOS runs."

    ; Overflow is bit 6 of EchoOptions: ECHO_COMMANDS, the C.
    bit a:EchoOptions
    bvc ClearBits
    jsr OutputReturn

;; Keeps the echo bits that were not given.
;; Also: ENM1 (DOS33, DOS31)
ClearBits:
    lda #ECHO_COMMANDS + ECHO_INPUT + ECHO_OUTPUT
    eor a:EchoOptions
    and a:EchoFlags
    sta a:EchoFlags
    rts
.endproc

;; MAXFILES: closes every file, the EXEC file too, and rebuilds the chain of file buffers with <ParsedNumber> (1-16)
;; buffers.
;;
;; At $A251 where DOS runs. <FileBuffers::Build> also moves BASIC's HIMEM to just below the new buffers; under Integer
;; BASIC, whose program sits just below HIMEM, that leaves no program.
;; In:    ParsedNumber = the number of buffers
;; Also: EMAXF (DOS33, DOS31)
.proc MaxFiles
.assert MASTER || * = $A251, "Commands::MaxFiles is at $A251 where DOS runs."

    ; No EXEC, so that CloseAll closes its file as well.
    lda #0
    sta a:ExecState
    lda ParsedNumber
    pha
    jsr CloseAll

    ; The new count, and the new chain.
    pla
    sta a:FileBufferCount
    jmp FileBuffers::Build
.endproc

;; DELETE: has the file manager delete the file named in <FileName>, then frees the buffer <FileRequest> lent it.
;;
;; At $A263 where DOS runs. Like LOCK, UNLOCK, VERIFY and RENAME, DELETE goes through <FileRequest>, which claims a
;; buffer for the file manager to work in. The file manager is not asked to close the file; the buffer is simply
;; marked free again.
;; Also: EDEL (DOS33, DOS31)
.proc Delete
.assert MASTER || * = $A263, "Commands::Delete is at $A263 where DOS runs."
    lda #REQUEST_DELETE
    jsr FileRequest

    ; Find the buffer that holds the name, and free it.
    jsr FileBuffers::Find
    ldy #0
    tya
    sta (WorkPointer),y
    rts
.endproc

;; LOCK: has the file manager lock the file named in <FileName>, then closes it.
;;
;; At $A271 where DOS runs.
;; Also: ELOCK (DOS33, DOS31)
.proc Lock
.assert MASTER || * = $A271, "Commands::Lock is at $A271 where DOS runs."
    lda #REQUEST_LOCK
    bne RequestAndClose             ; always
.endproc

;; UNLOCK: has the file manager unlock the file named in <FileName>, then closes it.
;;
;; At $A275 where DOS runs.
;; Also: EUNLK (DOS33, DOS31)
.proc Unlock
.assert MASTER || * = $A275, "Commands::Unlock is at $A275 where DOS runs."
    lda #REQUEST_UNLOCK
    ; Falls into RequestAndClose.
.endproc

;; Makes file manager request A for the file named in <FileName> through <FileRequest>, then closes the file, giving
;; the buffer back: the end LOCK, UNLOCK and VERIFY share.
;;
;; At $A277 where DOS runs.
;; In:    A = the request, a REQUEST_ code
;; Also: ELGO (DOS33, DOS31)
RequestAndClose:
.assert MASTER || * = $A277, "Commands::RequestAndClose is at $A277 where DOS runs."
    jsr FileRequest
    jmp Close

;; VERIFY: has the file manager read every sector of the file named in <FileName>, then closes it.
;;
;; At $A27D where DOS runs. In DOS 3.3, SAVE and BSAVE end here too (<SaveAndVerify>), to check what they wrote; DOS
;; 3.2, which has no <SaveAndVerify>, does not verify them.
;; Also: EVAR (DOS33, DOS31)
.proc Verify
.assert MASTER || * = $A27D, "Commands::Verify is at $A27D where DOS runs."
    lda #REQUEST_VERIFY
    bne RequestAndClose             ; always
.endproc

;; RENAME: has the file manager rename the file named in <FileName> to the name in <SecondFileName>, then closes it.
;;
;; At $A281 where DOS runs. The new name's address goes in <DosFileParameters::NewName>, the bytes that
;; <FileRequest> would otherwise fill with the record length, so this enters it at <FileRequest::KeepLength>,
;; after that step.
;; Also: EREN (DOS33, DOS31)
.proc Rename
.assert MASTER || * = $A281, "Commands::Rename is at $A281 where DOS runs."
    lda SecondNameAddress
    sta a:DosFileParameters::NewName
    lda SecondNameAddress+1
    sta a:DosFileParameters::NewName+1
    lda #REQUEST_RENAME
    sta a:InterpreterScratch
    jsr FileRequest::KeepLength
    jmp Close
.endproc
.if DOS32

;; APPEND: opens a text file and reads it to its end, so that the next WRITE adds to it.
;;
;; At $A298 where DOS runs. A text file ends at its first zero byte, and <RunFileRequest> also hands back a zero
;; when the file manager reports the end of the data. DOS 3.2 ends with the file manager's POSITION request that
;; READ and WRITE make (<FindAndPosition::CallPosition>), with the parameter list as the reads left it, so the
;; record number is not corrected as DOS 3.3's patch corrects it.
;; Also: EAPND (DOS33, DOS31)
.proc Append
.assert MASTER || * = $A298, "Commands::Append is at $A298 where DOS runs."
    jsr Open

;; Reads bytes until the zero that ends the text.
;; Also: AP1 (DOS33, DOS31)
ReadToEnd:
    jsr TextFile::ReadByte
    bne ReadToEnd
    jmp FindAndPosition::CallPosition
.endproc
.else

;; APPEND: opens a text file and reads it to its end, so that the next WRITE adds to it.
;;
;; At $A298 where DOS runs. A text file ends at its first zero byte, and <RunFileRequest> also hands back a zero when
;; the file manager reports the end of the data. <AppendFix::NextRecord>, a patch in the boot loader's page
;; (BootLoader.asm), then steps the record number on when the end flag <AppendFix::EndOfFile> is set, and finishes: in
;; the 1980 DOS with the file manager's POSITION request, in the 1983 DOS through <AppendFix::Finish>, which sets the
;; file's position itself.
;; Also: EAPND (DOS33, DOS31)
.proc Append
.assert MASTER || * = $A298, "Commands::Append is at $A298 where DOS runs."
    jsr Open

;; Reads bytes until the zero that ends the text.
;; Also: AP1 (DOS33, DOS31)
ReadToEnd:
    jsr TextFile::ReadByte
    bne ReadToEnd
    jmp AppendFix::NextRecord
.endproc
.endif

;; OPEN: opens the file named in <FileName> as a text file, creating it if it is missing.
;;
;; At $A2A3 where DOS runs. <FILE_TYPE_TEXT> goes in the file type, and <OpenAsType> opens the file and checks that
;; its type matches, giving FILE TYPE MISMATCH if not. The L option gives the record length, 1 by default.
;; Also: EOPEN (DOS33, DOS31)
.proc Open
.assert MASTER || * = $A2A3, "Commands::Open is at $A2A3 where DOS runs."
    lda #FILE_TYPE_TEXT
    jmp OpenAsType
.endproc

;; Opens the file named in <FileName> through the file manager's OPEN request.
;;
;; At $A2A8 where DOS runs. Whether a missing file is created depends on the command: the file manager checks
;; <SYNTAX_CREATES> in the command's <CommandSyntax> entry (CommandTables.asm).
;; Also: EOPN1 (DOS33)
.proc OpenFile
.assert MASTER || * = $A2A8, "Commands::OpenFile is at $A2A8 where DOS runs."
    lda #REQUEST_OPEN
    ; Falls into FileRequest.
.endproc

;; Makes file manager request A for the file named in <FileName> in a free DOS buffer: the common code of the handlers
;; that work on a named file, and of CATALOG and INIT.
;;
;; At $A2AA where DOS runs. It closes the file first if it is open, claims a free buffer by copying the name into
;; it, fills in the parameter list (the record length, then the volume, drive, slot and name's address in
;; <FileBuffers::SetOpenParameters>) and calls the file manager. The buffer stays claimed; <CloseBuffer> gives it
;; back. For a command that takes no file name, such as CATALOG, the scanner leaves a 0 in <FileName>'s first
;; character, so the buffer is lent to the request without being claimed.
;; In: A = the request, a REQUEST_ code; <FileName>, <KeywordVolume>, <KeywordDrive>, <KeywordSlot> and <KeywordLength>
;;     as the scanner left them
;; Out:   WorkPointer = the buffer, CurrentFileBuffer = the same
;; Errors: NO BUFFERS AVAILABLE when every buffer is in use; any file manager error, through RunFileRequest
;; Entry: KeepLength = with the request already in <InterpreterScratch> and parameter bytes 2-3 already set (RENAME)
;; Also: OPEN (DOS33, DOS31)
.proc FileRequest
.assert MASTER || * = $A2AA, "Commands::FileRequest is at $A2AA where DOS runs."
    sta a:InterpreterScratch

    ; No L given: records of one byte.
    lda a:KeywordLength
    bne SetLength
    lda a:KeywordLength+1
    bne SetLength
    lda #1
    sta a:KeywordLength

;; The record length, from L.
;; Also: EO1 (DOS33, DOS31)
SetLength:
    lda a:KeywordLength
    sta a:DosFileParameters::RecordLength
    lda a:KeywordLength+1
    sta a:DosFileParameters::RecordLength+1

;; Closes the file if it is open, which also leaves ParsedNumber = a free buffer (<FileBuffers::Find>'s).
;; Also: EO3 (DOS33, DOS31)
KeepLength:
.assert MASTER || * = $A2C8, "Commands::FileRequest::KeepLength is at $A2C8 where DOS runs."
    jsr Close

;; A high byte of 0 means no buffer is free.
;; Also: EO4 (DOS33, DOS31)
TakeFreeBuffer:
    lda ParsedNumber+1
    bne UseBuffer
    jmp Errors::NoBuffers

;; Works on the free buffer.
;; Also: EO5 (DOS33, DOS31)
UseBuffer:
    sta WorkPointer+1
    lda ParsedNumber
    sta WorkPointer

;; The name claims the buffer, its work areas go in the parameter list, and the request is made.
;; Also: EO6 (DOS33, DOS31)
ClaimBuffer:
    jsr FileBuffers::StoreName
    jsr FileBuffers::CopyPointers
    jsr FileBuffers::SetOpenParameters
    lda a:InterpreterScratch
    sta a:DosFileParameters::Request
    jmp RunFileRequest
.endproc

;; CLOSE: closes the file named in <FileName> or, with no name, every file except the EXEC file.
;;
;; At $A2EA where DOS runs. The search starts over after each close, so it closes every buffer that holds the name.
;; When none is left, <FileBuffers::Find> has also left the address of a free buffer, if any, in <ParsedNumber>,
;; which <FileRequest> relies on.
;; Out:   ParsedNumber = a free buffer (its high byte 0 if none), when a name was given
;; Also: ECLOSE (DOS33, DOS31)
.proc Close
.assert MASTER || * = $A2EA, "Commands::Close is at $A2EA where DOS runs."
    lda a:FileName
    cmp #' ' + $80
    beq CloseAll
    jsr FileBuffers::Find
    bcs CloseAll::Done
    jsr CloseBuffer
    jmp Close
.endproc

;; Closes the file whose buffer <WorkPointer> points at, and frees the buffer.
;;
;; At $A2FC where DOS runs. If the buffer is the EXEC file's, EXEC stops. The name is cleared before the request, so
;; the buffer is free even if the file manager fails.
;; In:    WorkPointer = the buffer
;; Also: CLOSE (DOS33, DOS31)
.proc CloseBuffer
.assert MASTER || * = $A2FC, "Commands::CloseBuffer is at $A2FC where DOS runs."

    ; Zero set: this is EXEC's buffer, so EXEC ends.
    jsr FileBuffers::TestExec
    bne FreeBuffer
    lda #0
    sta a:ExecState

;; Frees the buffer, then has the file manager close the file.
;; Also: CLX (DOS33, DOS31)
FreeBuffer:
    ldy #0
    tya
    sta (WorkPointer),y
    jsr FileBuffers::CopyPointers
    lda #REQUEST_CLOSE
    sta a:DosFileParameters::Request
    jmp RunFileRequest
.endproc

;; Closes every open file except the EXEC file, so that a program EXEC runs can use LOAD, RUN and the rest.
;;
;; At $A316 where DOS runs. After each close it starts again from the first buffer. <ReportDiskFull at ERROR9X>
;; (DosPatches.asm) calls it too.
;; Also: CLALL (DOS33, DOS31)
.proc CloseAll
.assert MASTER || * = $A316, "Commands::CloseAll is at $A316 where DOS runs."
    jsr FileBuffers::First
    bne TestBuffer                  ; always

;; Moves on to the next buffer, until the end of the chain.
;; Also: CL0 (DOS33, DOS31)
NextBuffer:
    jsr FileBuffers::Next
    beq Done

;; Closes the buffer's file, unless the buffer is EXEC's or free.
;; Also: CL1 (DOS33, DOS31)
TestBuffer:
    jsr FileBuffers::TestExec
    beq NextBuffer
    jsr FileBuffers::TestInUse
    beq NextBuffer
    jsr CloseBuffer
    jmp CloseAll

;; Returns. <Close> returns through it too.
;; Also: CL2 (DOS33, DOS31)
Done:
    rts
.endproc

.endscope
