; retrocore: style=strict
; FILESTUF: the file commands `CREATE`, `SAVE`, `LOAD`, `RENAME`, `LOCK`, `UNLOCK` and `DELETE`, and the plumbing of
; record files: writing a record back, moving to a record, and turning SOS's errors into BASIC's.
;
; Each definition keeps the name Apple's Business BASIC 1.3 listing gives it in its `Also:` (BB13).

; ---------------------------------------------------------------------------------------------------------------------
; `CREATE`
; ---------------------------------------------------------------------------------------------------------------------

; Statements: `CREATE`.
.scope Statements continued

;; `CREATE`: makes a file; `CREATE name, CATALOG|TEXT|DATA [, size]`.
;;
;; `TEXT` makes a text file and `DATA` a BASIC data file, the size giving the record length, kept as the auxiliary
;; type (<Files::DEFAULT_RECORD_LENGTH> when it is left out). `CATALOG` makes a subdirectory, the size giving its first
;; end of file as well. A missing or different word is a syntax error.
;; See: <Files::TakeRecordLength>, <Files::CreateWithOptions>
;; Also: CREATE (BB13)
.proc Create
;; The file type X holds until a word gives one.
NO_TYPE = $FF

    jsr Files::TakeName
    jsr CheckComma
    ldy #Files::STORAGE_FILE
    ldx #NO_TYPE
    cmp #TOKEN_CATALOG
    bne NotCatalog
    ldx #Files::FILE_TYPE_DIRECTORY
    ldy #Files::STORAGE_SUBDIRECTORY

;; Takes `TEXT`.
;; Also: CR1 (BB13)
NotCatalog:
    cmp #TOKEN_TEXT
    bne NotText
    ldx #FILE_TYPE_TEXT

;; Takes `DATA`.
;; Also: CR2 (BB13)
NotText:
    cmp #TOKEN_DATA
    bne CheckWord
    ldx #FILE_TYPE_BASIC_DATA

;; Ends the statement with a syntax error unless a word gave a type, then takes the size and makes the file.
;; Also: CR3 (BB13)
CheckWord:
    txa
    bmi ToSyntaxError                       ; none of the three
    sty SosCalls::NewFileStorageType
    sta SosCalls::NewFileType
    jsr GetNextCharacter
    jsr Files::TakeRecordLength
    lda SosCalls::NewFileStorageType        ; a subdirectory: the size is its end of file
    beq Files::CreateFile
    lda SosCalls::NewFileAuxType
    sta SosCalls::NewFileEnd
    lda SosCalls::NewFileAuxType+1
    sta SosCalls::NewFileEnd+1
    jmp Files::CreateWithOptions

;; Ends the statement with a syntax error.
;; Also: CRSNR (BB13)
ToSyntaxError:
    jmp SyntaxError
.endproc

.endscope

; Files: making a file.
.scope Files continued

;; Makes the file named at <SosCalls::Pathname> as an ordinary file of no size, of the type in <SosCalls::NewFileType>.
;;
;; <OpenNamed> calls it to make a missing file for `SAVE` and `OPEN`; the auxiliary type is whatever
;; <SosCalls::NewFileAuxType> holds.
;; See: <CreateWithOptions>
;; Also: CRTDO (BB13)
.proc CreateFile
    lda #0
    sta SosCalls::NewFileStorageType
    sta SosCalls::NewFileEnd
    sta SosCalls::NewFileEnd+1
    ; Falls into CreateWithOptions.
.endproc

;; Makes the file named at <SosCalls::Pathname> from <SosCalls::NewFileOptions>: its type, auxiliary type, storage type
;; and first end of file; an error ends the statement.
;; See: <SosCalls::MakeFileCall>
;; Also: CRTDO2 (BB13)
.proc CreateWithOptions
;; The length of `CREATE`'s option list.
CREATE_OPTIONS = 8

    lda #<(SosCalls::NewFileOptions)
    sta SosCalls::CreateOptions
    lda #>(SosCalls::NewFileOptions)
    sta SosCalls::CreateOptions+1
    lda #CREATE_OPTIONS
    sta SosCalls::CreateOptionsLength
    ldy #SosCalls::CALL_CREATE
    sty SosCalls::NewFileEnd+2              ; SosCalls::CALL_CREATE is 0, which clears the size's top bytes
    sty SosCalls::NewFileEnd+3
    jmp SosCalls::MakeFileCall
.assert SosCalls::CALL_CREATE = 0, "CreateWithOptions clears the end of file's top bytes with CREATE's index."
.endproc

; ---------------------------------------------------------------------------------------------------------------------
; `SAVE` and `LOAD`
;
; A program file (type $09) holds two zero bytes, then the program as it is in memory from ProgramStart up to
; ArraysStart, its banks run together. The length is not stored: `LOAD` takes it from the end of file.
; ---------------------------------------------------------------------------------------------------------------------

;; The two bytes before the program in its file, which `SAVE` writes as zeros (<ProgramLength> clears them) and
;; `LOAD` reads and ignores.
ProgramHeader = UsingDigits

;; The size of <ProgramHeader>.
PROGRAM_HEADER_SIZE = 2

;; Whether <TransferProgram> reads or writes: <TRANSFER_READ> for `LOAD`, 0 for `SAVE`.
TransferDirection = UsingDigits

;; <TransferDirection>'s value to read.
TRANSFER_READ = 1

;; The four-byte count of the program's bytes still to move, low byte first; its top byte is always 0.
LengthLeft = UsingDigits+2

;; The base `SET_MARK` and `SET_EOF` count the displacement forward from the mark with (SOS's `ADJMARK`).
BASE_FORWARD_FROM_MARK = 2

;; The most bytes one `READ` or `WRITE` of the program moves, $7FFF, as four bytes for <SubtractPart>'s 32-bit
;; subtract.
;; See: <TransferProgram>
;; Also: BYTBLOCK (BB13)
ProgramPartSize:
    .dword $7FFF

.endscope

; Statements: `SAVE`.
.scope Statements continued

;; `SAVE`: writes the program to a BASIC program file (type $09), making it if need be; `SAVE name`.
;;
;; The file gets two zero bytes, then the program's bytes from <ProgramStart> up to <ArraysStart>, and its end of file
;; is set at the end of them. The two bytes are where earlier versions of BASIC kept the program's length; this one
;; skips them and takes the length from the end of file, so it loads those files too, but they cannot load its. In 1.3
;; the program's prefix is used for the name (`SETPROG`), and BASIC's own put back after (`SETSOS`).
;; See: <Load>, <Files::ProgramLength>, <Files::TransferProgram>
;; Also: SAVE (BB13)
.proc Save
    .using Files
    lda #0
    sta ProgramLoading
.if VERSION >= 130
    jsr ProgramPrefix::UseProgram           ; 1.3: use the program's prefix
.endif
    lda #OPEN_WRITE                         ; to write: OpenNamed makes the file if it is missing
    ldx #FILE_TYPE_BASIC_PROGRAM
    jsr OpenOfType
    jsr ProgramLength
    lda #PROGRAM_HEADER_SIZE                ; write the header's two zero bytes
    sta SosCalls::Request
    lda #0
    sta SosCalls::Request+1
    lda #<(ProgramHeader)
    sta SosCalls::Buffer
    lda #>(ProgramHeader)
    sta SosCalls::Buffer+1
    jsr WriteBlock
    lda ProgramStart                        ; then the program, from ProgramStart
    sta Pointer1
    lda ProgramStart+1
    sta Pointer1+1
    lda ProgramStartXByte
    sta Pointer1XByte
    jsr TransferProgram
    ldy #POSITION_SIZE-1                    ; set the end of file at the mark: 0 forward from it
    lda #0

;; Clears the displacement's next byte.
;; Also: DSP0LUP (BB13)
ClearDisplacement:
    sta SosCalls::Displacement,Y
    dey
    bpl ClearDisplacement
    lda #BASE_FORWARD_FROM_MARK
    sta SosCalls::Displacement-1
    ldy #SosCalls::CALL_SET_EOF
    jsr SosCalls::MakeFileCall
    jsr CloseSosFile
.if VERSION >= 130
    jsr ProgramPrefix::UseSos               ; 1.3: back to BASIC's own prefix
.endif
    rts
.endproc

.endscope

; Files: opening and loading a program.
.scope Files continued

;; Opens the named file through <OpenNamed>, and closes it with a type mismatch unless its type is the one asked for.
;; In: A = the access: <OPEN_READ> to read, or <OPEN_WRITE> to write, making the file if it is missing; X = the file
;;   type
;; Out: SosCalls::Reference = the file's reference number, SosCalls::FileEnd = its end of file
;; See: <WrongTypeError>
;; Also: OPENIT (BB13)
.proc OpenOfType
    stx ForVariableType
    jsr OpenNamed
    ldx ForVariableType
    cpx SosCalls::FileType
    beq Done
    jmp WrongTypeError
Done:
    rts
.endproc

;; Opens the named BASIC program for reading and loads it through <LoadProgram>.
;; See: <Statements::Load>
;; Also: DOLOAD (BB13)
.proc OpenAndLoadProgram
    lda #OPEN_READ
    ldx #FILE_TYPE_BASIC_PROGRAM
    jsr OpenOfType
    ; Falls into LoadProgram.
.endproc

;; Loads the program from the open file in <SosCalls::Reference> into memory at <ProgramStart>, setting <ArraysStart> to
;; its end, and closes the file.
;;
;; The two bytes at the start are read and ignored, which saves a `SET_MARK`; the length is the end of file, from the
;; file's information, less 2. A program that would reach <MemoryTop> in the top bank is an out-of-memory error before
;; anything more is read, and the file is left open.
;;
;; <ProgramLengthFromEnd> takes the 2 from the end of file's low byte only, without the borrow, so an end of file
;; whose low byte is 0 or 1 gives a length 256 too long. The read stops at the end of file, but <ArraysStart> lands 256
;; bytes past the program, and those bytes are saved with it next time, which repeats the fault on the next load.
;; See: <TransferProgram>, <Statements::Chain>
;; Also: DOLD2 (BB13)
.proc LoadProgram
    jsr ClearHandlers
    lda #<(ProgramHeader)                   ; read the two bytes at the start
    sta SosCalls::Buffer
    lda #>(ProgramHeader)
    sta SosCalls::Buffer+1
    lda #0
    sta SosCalls::Request+1
    lda #PROGRAM_HEADER_SIZE
    sta SosCalls::Request
    jsr ReadBlock
    jsr ProgramLengthFromEnd                ; the length, into LengthLeft
    ldy ProgramStartXByte                   ; work out the program's end, ArraysStart

;; Takes 64K at a time off the length, as a bank and a bank's pages.
;; Also: SVLP1 (BB13)
TakeBanks:
    lda LengthLeft+2                        ; 64K or more?
    beq AddRest
    dec LengthLeft+2                        ; take 64K off: 32K onto the page byte,
    clc
    lda LengthLeft+1
    adc #POINTER_PAGE_LIMIT-POINTER_PAGE_FIRST
    sta LengthLeft+1
    iny                                     ; and 32K as a bank
    bcc TakeBanks
    iny                                     ; the page byte overflowed: two banks more
    iny
    bcs TakeBanks

;; Adds the rest to <ProgramStart> and checks the end is below <MemoryTop>.
;; Also: SVLP2 (BB13)
AddRest:
    clc                                     ; add what is left to ProgramStart
    lda LengthLeft
    adc ProgramStart
    tax
    lda LengthLeft+1
    adc ProgramStart+1
    jsr Memory::NormalizeAfterAdd           ; keep the page between POINTER_PAGE_FIRST and POINTER_PAGE_LIMIT
    cpy MemoryTopXByte                      ; below the top bank: it fits
    bcc Fits
    bne ToOutOfMemoryError
    cpx MemoryTop                           ; in the top bank: below MemoryTop?
    pha
    sbc MemoryTop+1
    pla
    bcs ToOutOfMemoryError

;; Sets <ArraysStart> to the program's end and reads the program.
;; Also: SVLDPP (BB13)
Fits:
    stx ArraysStart
    sta ArraysStart+1
    sty ArraysStartXByte
    jsr ProgramLengthFromEnd                ; the length again, for the read
    lda ProgramStart
    sta Pointer1
    lda ProgramStart+1
    sta Pointer1+1
    lda ProgramStartXByte
    sta Pointer1XByte
    lda #TRANSFER_READ                      ; read, for ReadOrWriteBlock
    sta TransferDirection
    jsr TransferProgram
    jmp CloseSosFile
.endproc

;; Closes the file, then ends the statement with a type mismatch: the file is not of the type asked for, such as a
;; BASIC program.
;; Also: NBP (BB13)
.proc WrongTypeError
    jsr CloseSosFile
    jmp ToTypeMismatchError
.endproc

;; Returns, for <ReadBlock>'s branch.
;; Also: SLRTS (BB13)
.proc TransferDone
    rts
.endproc

;; Ends the statement with an out-of-memory error.
;; Also: OUTOFM (BB13)
.proc ToOutOfMemoryError
    jmp ReportOutOfMemory
.endproc

.endscope

; Statements: `LOAD`.
.scope Statements continued

;; `LOAD`: loads a BASIC program and returns to the prompt; `LOAD name`.
;;
;; The variables are cleared, but open files stay open (<ClearVariables::KeepFiles>, not <ClearVariables>), and `TRACE`
;; goes off. In 1.3 the program's prefix is used for the name (`SETPROG`), and BASIC's own put back after (`SETSOS`).
;; See: <Files::OpenAndLoadProgram>, <Save>
;; Also: LOAD (BB13)
.proc Load
    lda #0
    sta ProgramLoading
.if VERSION >= 130
    jsr ProgramPrefix::UseProgram           ; 1.3: use the program's prefix
.endif
    jsr Files::OpenAndLoadProgram
    jsr ClearVariables::KeepFiles
    lsr TraceMode                           ; TRACE off
.if VERSION >= 130
    jsr ProgramPrefix::UseSos               ; 1.3: back to BASIC's own prefix
.endif
    jmp CommandLoop
.endproc

.endscope

; Files: moving the program's bytes.
.scope Files continued

;; Reads or writes the next part of the program, by <TransferDirection>: <TRANSFER_READ> for `LOAD`, 0 for `SAVE`.
;; See: <TransferProgram>
;; Also: RDWRT (BB13)
.proc ReadOrWriteBlock
    lda TransferDirection
    bne ReadBlock
    ; Falls into WriteBlock.
.endproc

;; Writes from the parameters in <SosCalls::Parameters>; an error closes the file and ends the statement.
;; Also: SVWRT (BB13)
.proc WriteBlock
    ldy #SosCalls::CALL_WRITE
    .byte $2C                               ; BIT absolute skips ReadBlock's LDY
    ; Falls into ReadBlock.
.endproc

;; Reads from the parameters in <SosCalls::Parameters>, or writes from them when entered from <WriteBlock>; an error
;; closes the file and ends the statement.
;; In: Y = `WRITE`'s index, from <WriteBlock>
;; Also: LDRED (BB13)
.proc ReadBlock
    ldy #SosCalls::CALL_READ
    jsr SosCalls::SetUp
    jsr SosCalls::Call
    beq TransferDone
    jmp CloseWithError
.endproc

;; Reads or writes the program's bytes from <Pointer1> on, in parts of at most <ProgramPartSize> bytes, until the length
;; in <LengthLeft> is done.
;;
;; The buffer address SOS gets is <Pointer1>'s own: a zero-page pointer with its bank in <Pointer1XByte>, which SOS
;; follows as an extended address.
;; In: Pointer1/Pointer1XByte = the program's start, TransferDirection = <TRANSFER_READ> to read or 0 to write,
;;   LengthLeft = the length
;; See: <ReadOrWriteBlock>, <SubtractPart>
;; Also: SAVE1 (BB13)
.proc TransferProgram
    lda LengthLeft+2                        ; LengthLeft+3 is always 0
    beq LastParts

;; Moves a full part and takes it off the length.
;; Also: LOOPAGIN (BB13)
FullPart:
    lda ProgramPartSize
    sta SosCalls::Request
    lda ProgramPartSize+1
    sta SosCalls::Request+1
    lda #<(Pointer1)
    sta SosCalls::Buffer
    lda #>(Pointer1)
    sta SosCalls::Buffer+1
    jsr ReadOrWriteBlock
    lda Pointer1                            ; move Pointer1 past it
    clc
    adc ProgramPartSize
    sta Pointer1
    lda Pointer1+1
    adc ProgramPartSize+1
    ldy Pointer1XByte
    jsr Memory::NormalizeAfterAdd
    sty Pointer1XByte
    sta Pointer1+1
    jsr SubtractPart
    jmp TransferProgram

;; Under 64K left: moves a full part while more than one is left, then the rest.
;; Also: somewhere (BB13)
LastParts:
    lda ProgramPartSize+1
    cmp LengthLeft+1                        ; more than a part left?
    bcc FullPart
    lda LengthLeft+1                        ; no: the rest
    sta SosCalls::Request+1
    lda LengthLeft
    sta SosCalls::Request
    lda #<(Pointer1)
    sta SosCalls::Buffer
    lda #>(Pointer1)
    sta SosCalls::Buffer+1
    jsr ReadOrWriteBlock
    rts
.endproc

;; Sets the program's length in <LengthLeft> from the end of file in <SosCalls::FileEnd>, less the two bytes before the
;; program.
;;
;; Only the low byte takes the 2 off, without the borrow; <LoadProgram> says what that does.
;; Uses: A, Y
;; Keeps: X
;; Also: LOOP1 (BB13)
.proc ProgramLengthFromEnd
    ldy #POSITION_SIZE-1                    ; the top three bytes as they are

;; Copies the end of file's next byte.
;; Also: LOOP1A (BB13)
CopyByte:
    lda SosCalls::FileEnd,Y
    sta LengthLeft,Y
    dey
    bne CopyByte
    lda SosCalls::FileEnd,Y                 ; the low byte less 2
    sec
    sbc #PROGRAM_HEADER_SIZE
    sta LengthLeft,Y
    rts
.endproc

.endscope

; ---------------------------------------------------------------------------------------------------------------------
; `RENAME`, `LOCK`, `UNLOCK` and `DELETE`
; ---------------------------------------------------------------------------------------------------------------------

; Statements: `RENAME`, `UNLOCK`, `LOCK` and `DELETE`.
.scope Statements continued

;; `RENAME`: renames a file; `RENAME old, new`. Both names go in <NameBuffer>, the new one after the old.
;; Also: RENAME (BB13)
.proc Rename
    jsr Files::TakeName
    lda SosCalls::Pathname                  ; keep the old name's address
    pha
    lda SosCalls::Pathname+1
    pha
    jsr CheckComma
    inx                                     ; the new name goes after it
    jsr Files::TakeName::AtIndex
    lda SosCalls::Pathname
    sta SosCalls::NewPathname
    lda SosCalls::Pathname+1
    sta SosCalls::NewPathname+1
    pla
    sta SosCalls::Pathname+1
    pla
    sta SosCalls::Pathname
    ldy #SosCalls::CALL_RENAME
    jmp SosCalls::MakeFileCall
.endproc

;; `UNLOCK`: lets a file be read, written, renamed and destroyed (<Files::FILE_ACCESS_UNLOCKED>); `UNLOCK name`.
;; See: <Lock>
;; Also: UNLOCK (BB13)
.proc Unlock
    lda #Files::FILE_ACCESS_UNLOCKED
    .byte $2C                               ; BIT absolute skips Lock's LDA
    ; Falls into Lock.
.endproc

;; `LOCK`: lets a file only be read (<Files::FILE_ACCESS_LOCKED>); `LOCK name`.
;;
;; `SET_FILE_INFO` gets a one-byte list, so only the access changes.
;; In: A = the access, at <Unlock>
;; See: <Unlock>
;; Also: LOCK (BB13)
.proc Lock
;; The length of `SET_FILE_INFO`'s list: the access alone.
ACCESS_ONLY = 1

    lda #Files::FILE_ACCESS_LOCKED
    sta SosCalls::FileAccess
    jsr Files::TakeName
    lda #<(SosCalls::FileAccess)
    sta SosCalls::InformationAddress
    lda #>(SosCalls::FileAccess)
    sta SosCalls::InformationAddress+1
    lda #ACCESS_ONLY                        ; the list's one byte
    sta SosCalls::CreateOptionsLength
    ldy #SosCalls::CALL_SET_FILE_INFO
    jmp SosCalls::MakeFileCall
.endproc

;; `DELETE`: destroys a file; `DELETE name`.
;; Also: DDELETE (BB13)
.proc Delete
    jsr Files::TakeName
    ldy #SosCalls::CALL_DESTROY
    jmp SosCalls::MakeFileCall
.endproc

.endscope

; ---------------------------------------------------------------------------------------------------------------------
; The program's length
; ---------------------------------------------------------------------------------------------------------------------

; Files: the program's length, a record length, and records.
.scope Files continued

;; Works out the program's length, <ArraysStart> less <ProgramStart>, as a 32-bit number in <LengthLeft>.
;;
;; Each bank the program crosses adds $80 pages (32K), as a pointer's page runs from <POINTER_PAGE_FIRST> to
;; <POINTER_PAGE_LIMIT> in each bank.
;; Out: ProgramHeader = two zeros, TransferDirection = 0 (to write), LengthLeft = the length
;; Uses: A, Y
;; Keeps: X
;; See: <Statements::Save>
;; Also: PGMLEN (BB13)
.proc ProgramLength
    ldy #PROGRAM_HEADER_SIZE+POSITION_SIZE-1 ; clear all six bytes
    lda #0

;; Clears the next byte.
;; Also: PGMLEN1 (BB13)
Clear:
    sta UsingDigits,Y
    dey
    bpl Clear
    lda ArraysStart
    sec
    sbc ProgramStart
    sta LengthLeft
    lda ArraysStart+1
    sbc ProgramStart+1
    ldy ArraysStartXByte
    cpy ProgramStartXByte                   ; in another bank?
    beq StorePages
    clc
    adc #POINTER_PAGE_LIMIT-POINTER_PAGE_FIRST ; yes: one bank's pages
    dey

;; Stores the pages' count.
;; Also: PGMLEN2 (BB13)
StorePages:
    sta LengthLeft+1

;; Adds a bank's pages for each bank more.
;; Also: PGMLEN3 (BB13)
NextBank:
    cpy ProgramStartXByte
    beq Done
    lda LengthLeft+1
    clc
    adc #POINTER_PAGE_LIMIT-POINTER_PAGE_FIRST
    sta LengthLeft+1
    lda LengthLeft+2
    adc #$0
    sta LengthLeft+2
    dey
    jmp NextBank

;; Returns.
;; Also: SZRTS (BB13)
Done:
    rts
.endproc

;; Takes <ProgramPartSize> from the length in <LengthLeft>, after a part of the program has been moved.
;;
;; The borrow is kept on the stack across the loop's compare.
;; Uses: A, Y
;; Keeps: X
;; See: <TransferProgram>
;; Also: DOSUB (BB13)
.proc SubtractPart
    ldy #0
    sec
    php

;; Subtracts the next byte.
;; Also: LOOP (BB13)
NextByte:
    plp
    lda LengthLeft,Y
    sbc ProgramPartSize,Y
    sta LengthLeft,Y
    php
    iny
    cpy #POSITION_SIZE
    bne NextByte
    plp
    rts
.endproc

;; Reads an optional record length after a comma into <SosCalls::NewFileAuxType>, <DEFAULT_RECORD_LENGTH> when there is
;; none.
;; Errors: an illegal quantity below <MINIMUM_RECORD_LENGTH> or above 32767
;; See: <Statements::Create>
;; Also: GRECLN (BB13)
.proc TakeRecordLength
    lda #<DEFAULT_RECORD_LENGTH
    sta SosCalls::NewFileAuxType
    lda #>DEFAULT_RECORD_LENGTH
    sta SosCalls::NewFileAuxType+1
    jsr GetCurrentCharacter
    beq Done
    jsr CheckComma
    jsr EvaluateNumber
    jsr FacToNonnegativeInteger
    ldx FacMantissa4
    lda FacMantissa3
    bmi BadLength
    bne Store
    cpx #MINIMUM_RECORD_LENGTH
    bcs Store

;; Ends the statement with an illegal quantity error.
;; Also: BUMSIZ (BB13)
BadLength:
    jmp IllegalQuantityError

;; Keeps the record length.
;; Also: GRC2 (BB13)
Store:
    sta SosCalls::NewFileAuxType+1
    stx SosCalls::NewFileAuxType

;; Returns.
;; Also: GRCRTS (BB13)
Done:
    rts
.endproc

; ---------------------------------------------------------------------------------------------------------------------
; Records
; ---------------------------------------------------------------------------------------------------------------------

;; Writes the file's record back if it changed, ending the statement on an error.
;; Out: A = 0, zero = set
;; Entry:
;;   NoError = returns with A = 0 and zero set; <WriteRecord> branches here for a record unchanged
;; See: <WriteRecord>
;; Also: WRTRCD2 (BB13)
.proc WriteRecordOrFail
    jsr WriteRecord
    bne Failed

;; Returns with A = 0 and zero set: no error.
;; Also: IDNUMR (BB13)
NoError:
    lda #0
    rts
Failed:
    jmp ReportSosError
.endproc

;; Writes the file's buffer back to its record when it has changed: the items, and the end-of-record mark when the
;; record has room for it.
;;
;; The write goes to the record's start (<SeekRecord>) and covers the buffer up to its offset, plus the 0 after. With
;; nothing in the buffer the positioning is skipped, and the `WRITE` goes out with a count of 0, or 1 from the carry it
;; came in with, and whatever else <SosCalls::Parameters> holds.
;; Out: A = the SOS error code, zero = set for none
;; See: <WriteRecordOrFail>, <MarkChanged>, <SetRecordTransfer>
;; Also: WRTRCD (BB13)
.proc WriteRecord
    ldy FileControlBlockIndex
    lda FileControlBlocks+FileControlBlock::FLAGS,Y
    bpl WriteRecordOrFail::NoError          ; unchanged
    lda FileControlBlocks+FileControlBlock::BUFFER_OFFSET+1,Y
    pha
    lda FileControlBlocks+FileControlBlock::BUFFER_OFFSET,Y
    pha
    ora FileControlBlocks+FileControlBlock::BUFFER_OFFSET+1,Y
    beq SetCount                            ; nothing in it
    jsr EndMarkFits                         ; carry = set when the end mark is there
    php
    jsr SeekRecord
    jsr SetRecordTransfer
    plp

;; Sets the count: the offset, and one more for the end mark.
;; Also: IDNUM2 (BB13)
SetCount:
    pla
    adc #0                                  ; one more for the end mark
    sta SosCalls::Request
    pla
    adc #0
    sta SosCalls::Request+1
    ldy #SosCalls::CALL_WRITE
    jsr SosCalls::SetUp
    jmp SosCalls::Call
.endproc

;; Moves to the file's next record: writes the current one back if it changed, then positions to the next and reads
;; it in.
;; See: <LoadRecord>
;; Also: NXRCD (BB13)
.proc NextRecord
    jsr WriteRecordOrFail
    ldx FileControlBlockIndex
    inc FileControlBlocks+FileControlBlock::RECORD_NUMBER,X
    bne Load
    inc FileControlBlocks+FileControlBlock::RECORD_NUMBER+1,X

;; Moves to the record and reads it.
;; Also: NXR2 (BB13)
Load:
    jmp LoadRecord
.endproc

;; Sets <SosCalls::Parameters> up to read or write the file's whole record through its buffer, with the buffer's offset
;; at 0.
;;
;; The buffer address SOS gets is <DataBufferPointer>'s own, a zero-page pointer with its bank in
;; <DataBufferPointerXByte>.
;; In: FileControlBlockIndex = the file's index in <FileControlBlocks>
;; Out: Y = FileControlBlockIndex, SosCalls::Request = the record length, SosCalls::Reference = the file's reference
;;   number
;; See: <PointAtItem>
;; Also: SETPARMS (BB13)
.proc SetRecordTransfer
    lda #0
    ldy FileControlBlockIndex
    sta FileControlBlocks+FileControlBlock::BUFFER_OFFSET,Y
    sta FileControlBlocks+FileControlBlock::BUFFER_OFFSET+1,Y
    jsr PointAtItem
    lda #<(DataBufferPointer)
    sta SosCalls::Buffer
    lda #>(DataBufferPointer)
    sta SosCalls::Buffer+1
    ldy FileControlBlockIndex
    lda FileControlBlocks+FileControlBlock::RECORD_LENGTH,Y
    sta SosCalls::Request
    lda FileControlBlocks+FileControlBlock::RECORD_LENGTH+1,Y
    sta SosCalls::Request+1
    lda FileControlBlocks+FileControlBlock::REFERENCE_NUMBER,Y
    sta SosCalls::Reference
    rts
.endproc

.endscope

; ---------------------------------------------------------------------------------------------------------------------
; Errors and positions
; ---------------------------------------------------------------------------------------------------------------------

;; Ends the statement with BASIC's error for the SOS error in A, from <SosErrors>.
;;
;; The search stops at the first entry above the code, so the table must be in ascending order. A code it lacks gives
;; BASIC's SOS error, <ERROR_SOS_CALL>, with the code kept in <SosError>.
;; In: A = the SOS error code
;; See: <ReportError>
;; Also: SERROR (BB13)
.proc ReportSosError
    ldx #0

;; Compares the code with the table's next entry.
;; Also: FNDAER1 (BB13)
Search:
    cmp SosErrors,X
    beq Found
    inx
    inx
    bcs Search                              ; the code is above this entry
    ldx #ERROR_SOS_CALL
    sta SosError
    jmp ReportError

;; Gives BASIC's error for the entry found.
;; Also: FOUNAR1 (BB13)
Found:
    inx
    lda SosErrors,X
    tax
    jmp ReportError
.endproc

; Files: the file information call, and records' positions.
.scope Files continued

;; Sets <SosCalls::Parameters> up for `GET_FILE_INFO` into <SosCalls::FileAccess>, all 11 bytes of it; the caller makes
;; the call.
;; Out: Y = the call's index, <SosCalls::CALL_GET_FILE_INFO>
;; Keeps: X
;; See: <SosCalls::GetFileInfo>, <SosCalls::SetUp>
;; Also: GETFISET (BB13)
.proc PrepareGetFileInfo
;; The length of `GET_FILE_INFO`'s list.
FILE_INFO_LENGTH = $B

    lda #<(SosCalls::FileAccess)
    sta SosCalls::InformationAddress
    lda #>(SosCalls::FileAccess)
    sta SosCalls::InformationAddress+1
    lda #FILE_INFO_LENGTH
    sta SosCalls::CreateOptionsLength
    ldy #SosCalls::CALL_GET_FILE_INFO
    rts
.endproc

;; Works out the start of the file's current record, the record number times the record length, as the displacement
;; from the start of the file for `SET_MARK` or `SET_EOF`, and sets the buffer's offset to 0.
;; In: FileControlBlockIndex = the file's index in <FileControlBlocks>
;; Out: SosCalls::Displacement..Displacement+3 = the position, SosCalls::MarkBase = 0, Y = 0
;; Uses: A, X
;; Entry:
;;   Return = returns; <SeekRecord> branches here
;; See: <Multiply>, <SeekRecord>
;; Also: SETDSP (BB13)
.proc RecordPosition
    ldy FileControlBlockIndex
    lda #0
    sta FileControlBlocks+FileControlBlock::BUFFER_OFFSET,Y
    sta FileControlBlocks+FileControlBlock::BUFFER_OFFSET+1,Y
    lda FileControlBlocks+FileControlBlock::RECORD_NUMBER,Y
    sta Multiplier
    lda FileControlBlocks+FileControlBlock::RECORD_NUMBER+1,Y
    sta Multiplier+1
    lda FileControlBlocks+FileControlBlock::RECORD_LENGTH,Y
    sta Multiplicand
    lda FileControlBlocks+FileControlBlock::RECORD_LENGTH+1,Y
    sta Multiplicand+1
    jsr Multiply
    ldy #POSITION_SIZE

;; Copies the product's next byte.
;; Also: QTIP (BB13)
CopyPosition:
    lda Product-1,Y
    sta SosCalls::Displacement-1,Y
    dey
    bne CopyPosition
    sty SosCalls::MarkBase                  ; base 0: from the start of the file

;; Returns; <SeekRecord> branches here.
;; Also: PPRTS (BB13)
Return:
    rts
.endproc

;; Moves the file's mark to the start of its current record.
;;
;; A character device, which has no mark, is let be. Past the end of file, reading ends the data: a 0 goes at the
;; buffer's start and <Handlers::EndOfFile> takes over. Writing moves the end of file to the end of that record, then
;; sets the mark again.
;; See: <RecordPosition>, <LoadRecord>
;; Also: POSREC (BB13)
.proc SeekRecord
    jsr RecordPosition
    ldy #SosCalls::CALL_SET_MARK
    jsr SosCalls::SetUp
    jsr SosCalls::Call
    beq RecordPosition::Return
    cmp #SOS_ERROR_NOT_BLOCK_DEVICE         ; not a block device
    beq RecordPosition::Return
    cmp #SOS_ERROR_POSITION_OUT_OF_RANGE    ; a position past the end of file
    beq PastEnd
    jmp ReportSosError
PastEnd:
    bit FileAccessMode
    bmi EndOfData                           ; reading
    jsr CheckWriteAccess
    ldx FileControlBlockIndex               ; the end of file at the next record's start
    inc FileControlBlocks+FileControlBlock::RECORD_NUMBER,X
    bne SetEnd
    inc FileControlBlocks+FileControlBlock::RECORD_NUMBER+1,X
SetEnd:
    jsr RecordPosition
    ldy #SosCalls::CALL_SET_EOF
    jsr SosCalls::MakeFileCall
    ldx FileControlBlockIndex               ; and the record number back
    lda FileControlBlocks+FileControlBlock::RECORD_NUMBER,X
    bne Back
    dec FileControlBlocks+FileControlBlock::RECORD_NUMBER+1,X
Back:
    dec FileControlBlocks+FileControlBlock::RECORD_NUMBER,X
    jmp SeekRecord

;; Leaves an empty record and goes to the end-of-file handling.
;; Also: PSRERR (BB13)
EndOfData:
    jsr PointAtItem
    tya                                     ; A = 0, an empty record
    sta (DataBufferPointer),Y
    jmp Handlers::EndOfFile
.endproc

.endscope
