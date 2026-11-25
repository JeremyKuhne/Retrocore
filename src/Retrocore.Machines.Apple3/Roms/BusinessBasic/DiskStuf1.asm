; retrocore: style=strict
; DISKSTUF1: the console's line input and one-character output, the `TYP` and `REC` functions, the `CLOSE` statement,
; the `PDL` and `BUTTON` functions, and the routines that find a file's control block from its number, take a file
; name from the statement and move a file to a record.
;
; Names follow Apple's Business BASIC 1.3 listing (BB13), kept in each definition's `Also:`.

; ---------------------------------------------------------------------------------------------------------------------
; Character I/O
; ---------------------------------------------------------------------------------------------------------------------

;; The most characters a line read asks SOS for; a line this long is cancelled.
;; Also: INALLWD (BB13)
READ_LINE_LIMIT = 255

;; Prints a prompt, then reads a line into <InputBuffer> from the console or, while `EXEC` runs, from the `EXEC` file.
;;
;; Control-C is turned off for the read (<Console::AttentionOff>) and on again after it. A line that fills all
;; <READ_LINE_LIMIT> characters is cancelled: BASIC prints a backslash, moves to a new line and asks again. Otherwise it
;; clears the rest of the screen line and moves the cursor to the next one. When the `EXEC` file runs out, it is closed
;; and the line comes from the console instead.
;; In: X = the prompt character, 0 for none
;; Out: X = the index of the line's last character, its carriage return, in <InputBuffer>
;; Uses: A, Y, Temporary, TerminalPosition
;; Entry:
;;   FromConsole = reads the line, with the prompt already printed; <Files::ReadExecLine> comes back here
;;   CheckLength = takes the line SOS has read; <Files::ReadExecLine> comes back here with the `EXEC` file's line
;; See: <InputLine>, <WriteConsoleCharacter>, <Files::CloseExecFile>
;; Also: INPUTLIN (BB13)
.proc ReadLine
;; The character that marks a cancelled line.
BACKSLASH = $5C
;; The console's control code that clears from the cursor to the end of the line.
CLEAR_TO_LINE_END = 31
;; A carriage return.
CARRIAGE_RETURN = $0D
;; A line feed.
LINE_FEED = $0A

    txa
    sta Temporary                           ; the prompt, for a second try
    beq FromConsole
    jsr WriteConsoleCharacter

;; Reads the line from the console, or from the `EXEC` file while one is open.
;; Also: ILM (BB13)
FromConsole:
    ldx ExecFile
    bne Files::ReadExecLine                 ; `EXEC` is running
    jsr Console::AttentionOff
    brk                                     ; SOS's READ, from the console
    .byte SOS_READ
    .word Console::LineParameters
    bne Files::CloseExecFile::ToReportSosError
    sta TerminalPosition                    ; A = 0: the cursor is back at the left
    jsr Console::AttentionOn

;; Cancels a line that filled the whole read, or finishes it.
;; Also: IL4 (BB13)
CheckLength:
    ldx Console::LineLength
    lda #BACKSLASH                          ; should the line be cancelled
    cpx #READ_LINE_LIMIT
    dex                                     ; the index of the last character
    bcc ClearRestOfLine
    jsr WriteConsoleCharacter
    ldx Temporary
    jsr PrintNewline
    jmp ReadLine

;; Clears the rest of the screen line and starts the next: the control code, a carriage return and a line feed.
;; Also: CLR2EOL (BB13)
ClearRestOfLine:
    lda #CLEAR_TO_LINE_END
    jsr WriteConsoleCharacter
    lda #CARRIAGE_RETURN
    jsr WriteConsoleCharacter
    lda #LINE_FEED
    ; Falls into WriteConsoleCharacter.
.endproc

;; Writes one character to the console with SOS's `WRITE`, ending the statement if the write fails.
;; In: A = the character
;; Out: A = the character
;; See: <Console::CharacterParameters>, <Console::Character>
;; Also: PRNACHAR (BB13)
.proc WriteConsoleCharacter
;; The count of `WRITE`'s parameters.
WRITE_PARAMETERS = 3

    sta Console::Character
    lda #WRITE_PARAMETERS
    sta Console::CharacterParameters
    brk                                     ; SOS's WRITE
    .byte SOS_WRITE
    .word Console::CharacterParameters
    bne Files::CloseExecFile::ToReportSosError
    lda Console::Character
    rts
.endproc

;; The shared file machinery: finding a file's control block from its number, opening, the record buffer and its
;; items, reading and writing records, and loading and saving programs.
;;
;; BASIC keeps a control block of <FILE_CONTROL_BLOCK_SIZE> bytes in <FileControlBlocks> for each of its files, 1 to 10.
;; A data file is read and written a record at a time, through a buffer SOS gives it; a text file is read and written a
;; line at a time, through SOS's new-line mode.
.scope Files

;; <OutputFileNumber>'s value while output goes to the console: no file.
FILE_CONSOLE = $FF

;; The bits of a control block's <FileControlBlock::TYPE_AND_ACCESS> that hold the file's type.
TYPE_MASK = $0F

;; The bits of a control block's <FileControlBlock::TYPE_AND_ACCESS> that hold the access `OPEN` asked for; none means
;; any access.
ACCESS_MASK = $F0

;; <FileControlBlock::TYPE_AND_ACCESS>'s bit for a file opened `AS INPUT`, to read only.
ACCESS_READ = $10

;; <FileControlBlock::TYPE_AND_ACCESS>'s bit for a file opened `AS OUTPUT` or `AS EXTENSION`, to write only.
ACCESS_WRITE = $20

;; <FileControlBlock::TYPE_AND_ACCESS>'s bit for a file opened `AS EXTENSION`, at its end.
ACCESS_END = $40

;; <FileControlBlock::FLAGS>'s bit for a record buffer changed and not yet written.
FLAG_CHANGED = $80

;; <FileControlBlock::FLAGS>'s bit for an open not yet complete: the first read or write decides whether the file holds
;; text or data.
FLAG_OPENING = $40

;; The segment number <FileControlBlock::SEGMENT> holds for a text file, which has no buffer; a catalog's is 0.
TEXT_SEGMENT = $FF

;; The size of a file position (a mark or an end of file) in bytes.
POSITION_SIZE = 4

;; SOS's `OPEN` access, in <SosCalls::OpenAccess>: to read only.
OPEN_READ = 1

;; SOS's `OPEN` access: to write only.
OPEN_WRITE = 2

;; SOS's `OPEN` access: to read and write.
OPEN_READ_WRITE = 3

;; The storage type SOS's `CREATE` takes for an ordinary file.
STORAGE_FILE = 0

;; The storage type of a subdirectory.
STORAGE_SUBDIRECTORY = $0D

;; The storage type of a volume's directory.
STORAGE_VOLUME = $0F

;; The file type of a directory, which `CREATE`'s `CATALOG` makes.
FILE_TYPE_DIRECTORY = 15

;; The record length of a file that doesn't give one.
DEFAULT_RECORD_LENGTH = 512

;; The shortest record length `CREATE` and `OPEN` accept.
MINIMUM_RECORD_LENGTH = 3

;; A file's SOS access when it is locked: read only.
FILE_ACCESS_LOCKED = $01

;; A file's SOS access when it is unlocked: read, write, rename and destroy.
FILE_ACCESS_UNLOCKED = $C3

;; SOS's error for a position past the end of the file.
SOS_ERROR_POSITION = $4D

;; SOS's error for a memory segment it can't give.
SOS_ERROR_SEGMENT_DENIED = $E1

;; Reads a line from the `EXEC` file through <Console::LineParameters>, putting the console's reference number back
;; afterwards.
;;
;; When the read fails, the file is closed (<CloseExecFile>). At the end of the file the line is then read from the
;; console; any other error ends the statement.
;; In: X = the `EXEC` file's reference number, from <ExecFile>
;; Also: DSEXEC (BB13)
.proc ReadExecLine
    ldy Console::LineParameters+1           ; the console's reference number
    stx Console::LineParameters+1
    brk                                     ; SOS's READ, from the `EXEC` file
    .byte SOS_READ
    .word Console::LineParameters
    sty Console::LineParameters+1
    beq ReadLine::CheckLength
    jsr CloseExecFile
    beq ReadLine::FromConsole               ; always: CloseExecFile returns only at the end of the file
.endproc

;; Closes the `EXEC` file and stops `EXEC`, then ends the statement with the error that stopped it unless it was the
;; end of the file.
;; In: X = the `EXEC` file's reference number, A = the SOS error code
;; Out: zero = set (the error was the end of the file)
;; Entry:
;;   ToReportSosError = ends the statement with the SOS error in A; the console's read and write branch here
;; See: <ExecFile>, <CloseSosFile>
;; Also: EXCCLS (BB13)
.proc CloseExecFile
    stx SosCalls::Reference
    pha
    lda #0
    sta ExecFile
    jsr CloseSosFile
    pla
    cmp #SOS_ERROR_END_OF_FILE
    beq Return

;; Ends the statement with the SOS error in A.
;; Also: FUK1 (BB13)
ToReportSosError:
    jmp ReportSosError
Return:
    rts
.endproc

.endscope

; ---------------------------------------------------------------------------------------------------------------------
; `TYP` and `REC`
; ---------------------------------------------------------------------------------------------------------------------

; Functions: `TYP` and `REC`.
.scope Functions continued

;; The `TYP` function: what the next item read from a file will be.
;;
;; It returns 0 for a file of unknown type and 8 for a text file. For a data file it looks at the next item's
;; descriptor in the record buffer, reading on through records that are used up, and returns
;; <Files::DescriptorTypNumbers>'s value for it: 1 a real, 2 an integer, 3 a long integer, 4 a string, or 5 at the
;; end of the data.
;; In: Fac = the file number
;; See: <Rec>, <Files::DescriptorType>, <Files::PrepareDataFile>
;; Also: TYP (BB13)
.proc Typ
    jsr ConvertToByte
    jsr Files::TakeFileNumber::FromNumber
    beq Files::NotOpenError
    sec                                     ; this is a read, so the file must not grow
    ror FileAccessMode
    lda FileControlBlocks+FileControlBlock::TYPE_AND_ACCESS,Y
    and #Files::TYPE_MASK
    eor #FILE_TYPE_UNKNOWN
    beq ReturnByteValue                     ; unknown: 0
    eor #FILE_TYPE_UNKNOWN
    tay
    lda #Files::TYP_TEXT
    cpy #FILE_TYPE_TEXT
    beq ReturnByteValue
    jsr Files::PrepareDataFile

;; Looks at the next item's descriptor, reading on past the end of a record that held items.
;; Also: TYP1 (BB13)
NextItem:
    jsr Files::PointAtItem
    lda (DataBufferPointer),Y               ; the next item's descriptor
    bne Classify
    ldy FileControlBlockIndex
    lda FileControlBlocks+FileControlBlock::BUFFER_OFFSET,Y ; the end of the record: was anything read from it?
    ora FileControlBlocks+FileControlBlock::BUFFER_OFFSET+1,Y
    beq Classify                            ; no, so this is the end of the data
    jsr Files::NextRecord
    jmp NextItem

;; Gives the descriptor's `TYP` number.
;; Also: TYP2 (BB13)
Classify:
    jsr Files::DescriptorType
    lda a:Files::DescriptorTypNumbers,Y
    ; Falls into ReturnByteValue.
.endproc

;; Returns A as `TYP`'s or another function's value.
;; In: A = the value (0-255)
;; See: <ReturnByte>
;; Also: RTNVAL (BB13)
.proc ReturnByteValue
    tay
    jmp ReturnByte
.endproc

;; The `REC` function: the number of the record a file is at.
;;
;; For a text file, other than a catalog, the number is worked out from the file's mark first
;; (<Files::RecordFromMark>).
;; In: Fac = the file number
;; See: <Typ>, <Files::RecordFromMark>
;; Also: REC (BB13)
.proc Rec
    jsr ConvertToByte
    jsr Files::TakeFileNumber::FromNumber
    beq Files::NotOpenError
    lda FileControlBlocks+FileControlBlock::TYPE_AND_ACCESS,Y
    and #Files::TYPE_MASK
    cmp #FILE_TYPE_TEXT
    bne ReturnRecord
    lda FileControlBlocks+FileControlBlock::SEGMENT,Y
    beq ReturnRecord                        ; a catalog keeps its own count
    jsr Files::RecordFromMark

;; Returns the record number in the file's control block as `REC`'s value.
;; In: Y = the file's control block index
;; Also: GTREC (BB13)
ReturnRecord:
    lda FileControlBlocks+FileControlBlock::RECORD_NUMBER+1,Y
    pha
    lda FileControlBlocks+FileControlBlock::RECORD_NUMBER,Y
    tay
    pla
    jmp ReturnSignedWord
.endproc

.endscope

; Files: a file that isn't open, and a record number from a position.
.scope Files continued

;; Ends the statement with SOS's file-not-open error.
;; See: <SOS_ERROR_BAD_REFERENCE_NUMBER>
;; Also: NOTOPN (BB13)
.proc NotOpenError
    lda #SOS_ERROR_BAD_REFERENCE_NUMBER
    jmp ReportSosError
.endproc

;; Sets a file's record number from its mark: the mark (from `GET_MARK`) divided by <Divisor>.
;;
;; Nothing here sets <Divisor>; it holds the record length of whichever file was last positioned (<RecordPosition>) or
;; opened.
;; In: FileControlBlockIndex = the file's control block index
;; Out: the file's record number in its control block, Remainder = the offset in that record, Y =
;;   <FileControlBlockIndex>
;; Uses: A, X, Dividend, Quotient
;; See: <RecordFromEnd>, <Divide>
;; Also: GETRN (BB13)
.proc RecordFromMark
    ldy FileControlBlockIndex
    lda FileControlBlocks+FileControlBlock::REFERENCE_NUMBER,Y
    sta SosCalls::Reference
    ldy #SosCalls::CALL_GET_MARK
    jsr SosCalls::MakeFileCall
    ldy #POSITION_SIZE                      ; the mark is the dividend

;; Copies the mark's bytes.
;; Also: GTRN0 (BB13)
CopyMark:
    lda SosCalls::Mark-1,Y
    sta Dividend-1,Y
    dey
    bne CopyMark
    beq RecordFromEnd::DivideByLength
.endproc

;; Sets a file's record number from its end of file, as <RecordFromMark> does from the mark: the end of file in
;; <SosCalls::FileEnd> divided by <Divisor>.
;; In: FileControlBlockIndex = the file's control block index, SosCalls::FileEnd = the end of file, Divisor = the record
;;   length
;; Out: the file's record number in its control block, Remainder = the bytes in its last record, Y =
;;   <FileControlBlockIndex>
;; Uses: A, X, Dividend, Quotient
;; Entry:
;;   DivideByLength = divides the position already in <Dividend>; <RecordFromMark> branches here
;; See: <Statements::Open>
;; Also: GETRN1 (BB13)
.proc RecordFromEnd
    ldy #POSITION_SIZE

;; Copies the end of file's bytes.
;; Also: GTRN2 (BB13)
CopyEnd:
    lda SosCalls::FileEnd-1,Y
    sta Dividend-1,Y
    dey
    bne CopyEnd

;; Divides the position by the record length into the record number.
;; Also: GTRN3 (BB13)
DivideByLength:
    jsr Divide
    ldy FileControlBlockIndex
    lda Quotient
    sta FileControlBlocks+FileControlBlock::RECORD_NUMBER,Y
    lda Quotient+1
    sta FileControlBlocks+FileControlBlock::RECORD_NUMBER+1,Y
    rts
.endproc

.endscope

; ---------------------------------------------------------------------------------------------------------------------
; CLOSE
; ---------------------------------------------------------------------------------------------------------------------

; Statements: CLOSE.
.scope Statements continued

;; The `CLOSE` statement: closes the file given, or with no file number every file.
;;
;; A record waiting to be written is written first. If that fails, the file is still closed and the error ends the
;; statement afterwards.
;; In: zero = set when the statement ends after `CLOSE`
;; Entry:
;;   Finish = ends the statement with the write error <Files::CloseFile> kept in <SubscriptMode>, if there was one;
;;     <Files::CloseAll> ends here
;; See: <Files::CloseFile>, <Files::CloseAll>
;; Also: DCLOSE (BB13)
.proc Close
    beq Files::CloseAll
    jsr Files::TakeFileNumber
    lda #0
    sta SubscriptMode                       ; no write error yet
    jsr Files::CloseFile

;; Ends the statement with the write error <Files::CloseFile> kept in <SubscriptMode>, if there was one, and clears it.
;; Also: CLSDONE (BB13)
Finish:
    ldx #0
    lda SubscriptMode
    stx SubscriptMode
    beq Return
    jmp ReportSosError
Return:
    rts
.endproc

.endscope

; Files: closing files.
.scope Files continued

;; Closes every open file, 10 down to 1, then ends the statement with a write error if closing one gave one.
;; See: <CloseFile>
;; Also: CLSALL (BB13)
.proc CloseAll
    lda #0
    sta SubscriptMode
    lda #FILE_COUNT-1                       ; file 10's index

;; Closes the file whose number less one is in A, if it is open.
;; Also: CLSA1 (BB13)
NextFile:
    pha
    tax
    jsr TakeFileNumber::FromIndex
    beq Skip                                ; not open
    jsr CloseFile

;; Steps to the file before.
;; Also: CLSAL2 (BB13)
Skip:
    pla
    sec
    sbc #1
    bpl NextFile
    jmp Statements::Close::Finish
.endproc

;; Closes one file: writes its record if it was changed, frees its buffer, clears its control block and closes it.
;;
;; Closing the `OUTPUT#` file sends output back to the console. A write error is kept in <SubscriptMode> for
;; <Statements::Close::Finish>; a file that isn't open ends the statement with an error.
;; In: X = the file number less one, Y and FileControlBlockIndex = the file's control block index
;; See: <CloseControlBlock>, <WriteRecord>
;; Also: CLOSEM (BB13)
.proc CloseFile
    cpx OutputFileNumber+1
    bne WriteBack
    lda #FILE_CONSOLE                       ; this is the `OUTPUT#` file: back to the console
    sta OutputFileNumber+1
    sta OutputFileNumber

;; Writes the record back, keeping a write error, then frees the buffer.
;; Also: DNTCLS (BB13)
WriteBack:
    sty SavedY
    jsr WriteRecord
    beq Written
    sta SubscriptMode                       ; the write failed
Written:
    ldy SavedY
    lda FileControlBlocks+FileControlBlock::REFERENCE_NUMBER,Y
    bne IsOpen
    jmp NotOpenError
IsOpen:
    lda FileControlBlocks+FileControlBlock::SEGMENT,Y
    beq CloseControlBlock                   ; a catalog has no buffer
    cmp #TEXT_SEGMENT
    beq CloseControlBlock                   ; nor does a text file
    sta SosCalls::ReleasedSegment
    ldy #SosCalls::CALL_RELEASE_SEG
    jsr SosCalls::MakeFileCall
    ldy SavedY
    lda #0
    sta FileControlBlocks+FileControlBlock::SEGMENT,Y
    ; Falls into CloseControlBlock.
.endproc

;; Closes a file in SOS and clears its control block.
;; In: Y = the file's control block index
;; See: <CloseSosFile>
;; Also: CLOSEM2 (BB13)
.proc CloseControlBlock
    lda FileControlBlocks+FileControlBlock::REFERENCE_NUMBER,Y
    sta SosCalls::Reference
    ldx #FILE_CONTROL_BLOCK_SIZE
    lda #0

;; Clears the control block's next byte.
;; Also: CLS3 (BB13)
Clear:
    sta FileControlBlocks,Y
    iny
    dex
    bne Clear
    ; Falls into CloseSosFile.
.endproc

;; Closes the file whose reference number is in <SosCalls::Reference>, ending the statement if `CLOSE` fails.
;; See: <SosCalls::MakeFileCall>
;; Also: CLSEND (BB13)
.proc CloseSosFile
    ldy #SosCalls::CALL_CLOSE
    jmp SosCalls::MakeFileCall
.endproc

; ---------------------------------------------------------------------------------------------------------------------
; Finding files
; ---------------------------------------------------------------------------------------------------------------------

;; Takes a file number, `#` and an expression, from the statement and finds its control block.
;;
;; The number must be 1 to 10, or the statement ends with an illegal quantity error.
;; Out: X = the file number less one, Y = the control block index, also in <FileControlBlockIndex>, A = the file's
;;   reference number, also in <SosCalls::Reference>, zero = set when the file is not open
;; Uses: CurrentFileNumber, ForVariableType
;; Entry:
;;   FromNumber = takes the file number in X
;;   FromIndex = takes the file number less one in X
;; See: <FileControlBlocks>, <TakeFileAndRecord>
;; Also: GTFLNO (BB13)
.proc TakeFileNumber
    jsr CheckNumberSign
    jsr EvaluateByte

;; Takes the file number in X.
;; Also: GTFLNO0 (BB13)
FromNumber:
    dex

;; Takes the file number less one in X.
;; Also: GTFLNO1 (BB13)
FromIndex:
    txa
    bmi ToIllegalQuantityError
    cpx #FILE_COUNT
    bcs ToIllegalQuantityError
    stx CurrentFileNumber
    ldy #FILE_CONTROL_BLOCK_SIZE-1          ; the index is the number times FILE_CONTROL_BLOCK_SIZE
    sta ForVariableType

;; Adds the number in once for each byte of a control block.
;; Also: FCBMUL (BB13)
Multiply:
    adc ForVariableType
    dey
    bne Multiply
    tay
    sty FileControlBlockIndex
    lda FileControlBlocks+FileControlBlock::REFERENCE_NUMBER,Y
    sta SosCalls::Reference
    rts
.endproc

;; Ends the statement with an illegal quantity error.
;; See: <IllegalQuantityError>
;; Also: BADBOY1 (BB13)
.proc ToIllegalQuantityError
    jmp IllegalQuantityError
.endproc

.endscope

; ---------------------------------------------------------------------------------------------------------------------
; The joystick
; ---------------------------------------------------------------------------------------------------------------------

; Functions: `PDL` and `BUTTON`.
.scope Functions continued

;; How many paddles `PDL` reads, and how many buttons `BUTTON` reads: 0 to 3.
JOYSTICK_INPUTS = 4

;; The index of the X axis in the `JOYSTICK` call's result, after the two switches; the Y axis follows it.
JOYSTICK_AXES = 2

;; The `PDL` function: reads an axis of a joystick, 0-255, with SOS's `JOYSTICK` call.
;;
;; `PDL(0)` and `PDL(1)` read the X and Y axes with the mode's port bit clear (port B), `PDL(2)` and `PDL(3)` with it
;; set (port A): the modes 1, 2, 5 and 6.
;; In: Fac = the paddle number, 0-3
;; See: <Button>, <ReadJoystick>
;; Also: PDLHNDL (BB13)
.proc Pdl
    jsr ConvertToByte
    cpx #JOYSTICK_INPUTS
    bcs Files::ToIllegalQuantityError
    txa
    pha
    eor #1                                  ; carry = 1 for X (an even number), 0 for Y
    lsr
    pla
    rol                                     ; the mode: twice the number, plus that bit
    sta SosCalls::JoystickMode
    txa
    and #1                                  ; the result's index: 2 for X, 3 for Y
    ora #JOYSTICK_AXES
    ; Falls into ReadJoystick.
.endproc

;; Makes the `JOYSTICK` call with the mode in <SosCalls::JoystickMode> and returns one byte of its result as the
;; function's value.
;; In: A = the byte's index in the result: 0-1 the switches, 2-3 the axes
;; See: <Pdl>, <Button>
;; Also: READJOY (BB13)
.proc ReadJoystick
    pha
    ldy #SosCalls::CALL_JOYSTICK
    jsr SosCalls::MakeFileCall
    pla
    tax
    lda SosCalls::JoystickMode+1,X
    tay
    jmp ReturnByte
.endproc

;; The `BUTTON` function: reads a joystick's switch, 255 when it is pressed and 0 when not.
;;
;; `BUTTON(0)` and `BUTTON(1)` read the two switches with the mode's port bit clear (port B), `BUTTON(2)` and
;; `BUTTON(3)` with it set (port A).
;; In: Fac = the button number, 0-3
;; See: <Pdl>, <ReadJoystick>
;; Also: BUTTON (BB13)
.proc Button
    jsr ConvertToByte
    cpx #JOYSTICK_INPUTS
    bcs Files::ToIllegalQuantityError
    txa
    and #$FE
    asl                                     ; the mode: 0 or 4, the port bit alone
    sta SosCalls::JoystickMode
    txa
    and #01                                 ; the result's index: the switch
    jmp ReadJoystick
.endproc

.endscope

; ---------------------------------------------------------------------------------------------------------------------
; File names
; ---------------------------------------------------------------------------------------------------------------------

; Files: file names, and moving to a record.
.scope Files continued

;; Takes a file name from the statement into <NameBuffer>, with its length first as SOS wants it, and points
;; <SosCalls::Pathname> at it.
;;
;; In a program, and in immediate mode when the name starts with a quote or a token, the name is a string expression
;; (<TakeNameExpression>). Otherwise, in immediate mode, it is the text up to the next colon, comma, space or end of
;; line, as typed. Nothing checks the name fits <NameBuffer>.
;; In: X = where the name's length goes in <NameBuffer>, for AtIndex; from the top, the name goes first
;; Out: X = the index of the name's last character in <NameBuffer>, one more for a name as typed
;; Uses: Y, AssignedVariable
;; Entry:
;;   AtIndex = takes the name's place in X, for a second name
;; See: <Statements::Rename>, <OpenNamed>
;; Also: GETNAME (BB13)
.proc TakeName

    ldx #0

;; Takes the name's place in X.
;; Also: GETNAM2 (BB13)
AtIndex:
    ldy CurrentLine+1
    stx AssignedVariable                    ; where the length goes
    iny
    bne TakeNameExpression                  ; a program is running
    jsr GetCurrentCharacter
    cmp #FIRST_TOKEN
    bcs TakeNameExpression                  ; a token
    cmp #'"'
    beq TakeNameExpression                  ; a quote
    dey                                     ; Y = $FF, X = the length's place

;; Copies the name's next character as typed.
;; Also: GTNM (BB13)
NextCharacter:
    iny
    inx
    lda (TextPointer),Y
    sta NameBuffer,X
    beq EndOfName
    cmp #':'                                ; a colon,
    beq EndOfName
    cmp #' '                                ; a space
    beq EndOfName
    cmp #','                                ; or a comma ends it
    bne NextCharacter

;; Steps the text pointer over a name taken as typed.
;; In: Y = the name's length
;; Also: GOTNAM (BB13)
EndOfName:
    tya
    pha
    jsr AdvanceTextPointer
    pla
    ; Falls into SetNameLength.
.endproc

;; Puts the name's length before it in <NameBuffer>, at the place in <AssignedVariable>, and points <SosCalls::Pathname>
;; at it.
;; In: A = the length
;; Out: A = the next character of the statement, from <GetCurrentCharacter>
;; Entry:
;;   AtY = takes the place in Y; <Statements::Catalog> enters here for the prefix
;; Also: GOTN2 (BB13)
.proc SetNameLength
    ldy AssignedVariable

;; Takes the place in Y.
;; Also: GOTN22 (BB13)
AtY:
    sta NameBuffer,Y
    clc
    tya
    adc #<(NameBuffer)
    sta SosCalls::Pathname
    lda #0
    adc #>(NameBuffer)
    sta SosCalls::Pathname+1
    jmp GetCurrentCharacter
.endproc

;; Takes the name as a string expression and copies it into <NameBuffer>, freeing the string if it was a temporary one.
;; In: AssignedVariable = where the length goes
;; Out: X = the index of the name's last character in <NameBuffer>
;; Entry:
;;   Return = returns; <TakeFileAndRecord> branches here
;; Also: DFRD (BB13)
.proc TakeNameExpression
    ldy #VALUE_TYPE_STRING                  ; a string is wanted
    sty ValueType
    jsr EvaluateExpression
    jsr Strings::FindFacString              ; A = its length, Pointer1 = its address
    ldx AssignedVariable
    pha
    jsr SetNameLength
    pla
    sta AssignedVariable                    ; now the count to copy
    beq Copied
    ldy #$FF

;; Copies the string's next character.
;; Also: DFRD2 (BB13)
CopyCharacter:
    iny
    inx
    lda (Pointer1),Y
    sta NameBuffer,X
    dec AssignedVariable
    bne CopyCharacter

;; Frees the string.
;; Also: DFRD3 (BB13)
Copied:
    stx AssignedVariable
    jsr Strings::FreeFacTemporary
    ldx AssignedVariable

;; Returns; <TakeFileAndRecord> branches here.
;; Also: RTSQ7 (BB13)
Return:
    rts
.endproc

; ---------------------------------------------------------------------------------------------------------------------
; Records
; ---------------------------------------------------------------------------------------------------------------------

;; Takes `#n` and, after a comma, a record number from a file statement; with a record number, writes out the record
;; in hand if it was changed and moves the file to the new one (<LoadRecord>).
;;
;; A file that isn't open ends the statement with an error.
;; Out: FileControlBlockIndex = the file's control block index, CurrentFileNumber = the file number less one
;; See: <TakeFileNumber>, <LoadRecord>
;; Also: FILNUM (BB13)
.proc TakeFileAndRecord
    jsr TakeFileNumber
    bne IsOpen
    jmp NotOpenError
IsOpen:
    jsr GetCurrentCharacter
    cmp #','
    bne TakeNameExpression::Return          ; no record number
    jsr CheckComma
    jsr EvaluateNumber
    jsr FacToNonnegativeInteger
    jsr WriteRecordOrFail
    ldy FileControlBlockIndex
    lda FacMantissa4
    sta FileControlBlocks+FileControlBlock::RECORD_NUMBER,Y
    lda FacMantissa3
    sta FileControlBlocks+FileControlBlock::RECORD_NUMBER+1,Y
    ; Falls into LoadRecord.
.endproc

;; Moves a file to the record in its control block and, for a data file whose open is complete, reads the record into
;; its buffer.
;;
;; A read that finds the end of the file leaves an empty record: a <DATA_ITEM_END_OF_RECORD> at the buffer's start.
;; In: FileControlBlockIndex = the file's control block index
;; See: <SeekRecord>, <SetRecordTransfer>, <NextRecord>
;; Also: RPOSN (BB13)
.proc LoadRecord
    jsr SeekRecord
    ldy FileControlBlockIndex
    lda FileControlBlocks+FileControlBlock::TYPE_AND_ACCESS,Y
    and #TYPE_MASK
    cmp #FILE_TYPE_TEXT
    beq Done                                ; a text file has no record buffer
    jsr SetRecordTransfer
    lda FileControlBlocks+FileControlBlock::FLAGS,Y
    asl
    bmi Done                                ; FLAG_OPENING: read nothing yet
    ldy #SosCalls::CALL_READ
    jsr SosCalls::SetUp
    jsr SosCalls::Call
    beq Done
    cmp #SOS_ERROR_END_OF_FILE
    beq EndOfFile
    jmp ReportSosError

;; Leaves an empty record at the end of the file.
;; Also: READ25 (BB13)
EndOfFile:
    jsr PointAtItem
    lda #DATA_ITEM_END_OF_RECORD
    ldy #0
    sta (DataBufferPointer),Y

;; Returns.
;; Also: RDGE (BB13)
Done:
    rts
.endproc

;; Ends the statement with a file-not-open error, for <PrepareTextFile>'s branch.
;; See: <NotOpenError>
;; Also: DUMSHIT (BB13)
.proc ToNotOpenError
    jmp NotOpenError
.endproc

.endscope
