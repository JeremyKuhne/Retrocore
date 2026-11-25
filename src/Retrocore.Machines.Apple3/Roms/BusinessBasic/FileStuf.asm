; retrocore: style=strict
; FILESTUF: the file commands `CREATE`, `SAVE`, `LOAD`, `RENAME`, `LOCK`, `UNLOCK` and `DELETE`, and the plumbing of
; record files: writing a record back, moving to a record, and turning SOS's errors into BASIC's.
;
; Names follow Apple's Business BASIC 1.3 listing (BB13), kept in each definition's `Also:`.

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
    jsr CHKCOM
    ldy #Files::STORAGE_FILE
    ldx #NO_TYPE
    cmp #CATATK
    bne NotCatalog
    ldx #Files::FILE_TYPE_DIRECTORY
    ldy #Files::STORAGE_SUBDIRECTORY

;; Takes `TEXT`.
;; Also: CR1 (BB13)
NotCatalog:
    cmp #TEXTTK
    bne NotText
    ldx #TXTTYP

;; Takes `DATA`.
;; Also: CR2 (BB13)
NotText:
    cmp #DATATK
    bne CheckWord
    ldx #BINTIP

;; Ends the statement with a syntax error unless a word gave a type, then takes the size and makes the file.
;; Also: CR3 (BB13)
CheckWord:
    txa
    bmi ToSyntaxError                       ; none of the three
    sty INSTRTYP
    sta INFLID
    jsr CHRGET
    jsr Files::TakeRecordLength
    lda INSTRTYP                            ; a subdirectory: the size is its end of file
    beq Files::CreateFile
    lda INAUXID
    sta INEOF
    lda INAUXID+1
    sta INEOF+1
    jmp Files::CreateWithOptions

;; Ends the statement with a syntax error.
;; Also: CRSNR (BB13)
ToSyntaxError:
    jmp SNERR
.endproc

.endscope

; Files: making a file.
.scope Files continued

;; Makes the file named at <PTHPTR> as an ordinary file of no size, of the type in <INFLID>.
;;
;; <OpenNamed> calls it to make a missing file for `SAVE` and `OPEN`; the auxiliary type is whatever <INAUXID> holds.
;; See: <CreateWithOptions>
;; Also: CRTDO (BB13)
.proc CreateFile
    lda #0
    sta INSTRTYP
    sta INEOF
    sta INEOF+1
    ; Falls into CreateWithOptions.
.endproc

;; Makes the file named at <PTHPTR> from <CRTTBL>: its type, auxiliary type, storage type and first end of file;
;; an error ends the statement.
;; See: <SETGO>
;; Also: CRTDO2 (BB13)
.proc CreateWithOptions
;; The length of `CREATE`'s option list.
CREATE_OPTIONS = 8

    lda #<(CRTTBL)
    sta CRTLST
    lda #>(CRTTBL)
    sta CRTLST+1
    lda #CREATE_OPTIONS
    sta INLNGTH
    ldy #CRT
    sty INEOF+2                             ; CRT is 0, which clears the size's top bytes
    sty INEOF+3
    jmp SETGO
.assert CRT = 0, "CreateWithOptions clears the end of file's top bytes with CREATE's index."
.endproc

; ---------------------------------------------------------------------------------------------------------------------
; `SAVE` and `LOAD`
;
; A program file (type $09) holds two zero bytes, then the program as it is in memory from TXTTAB up to ARYTAB, its
; banks run together. The length is not stored: `LOAD` takes it from the end of file.
; ---------------------------------------------------------------------------------------------------------------------

;; The two bytes before the program in its file, which `SAVE` writes as zeros (<ProgramLength> clears them) and
;; `LOAD` reads and ignores.
ProgramHeader = BCDSTR

;; The size of <ProgramHeader>.
PROGRAM_HEADER_SIZE = 2

;; Whether <TransferProgram> reads or writes: <TRANSFER_READ> for `LOAD`, 0 for `SAVE`.
TransferDirection = BCDSTR

;; <TransferDirection>'s value to read.
TRANSFER_READ = 1

;; The four-byte count of the program's bytes still to move, low byte first; its top byte is always 0.
LengthLeft = BCDSTR+2

;; The base `SET_MARK` and `SET_EOF` count the displacement forward from the mark with (SOS's ADJMARK).
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
;; The file gets two zero bytes, then the program's bytes from <TXTTAB> up to <ARYTAB>, and its end of file is set
;; at the end of them. The two bytes are where earlier versions of BASIC kept the program's length; this one skips
;; them and takes the length from the end of file, so it loads those files too, but they cannot load its. In 1.3 the
;; program's prefix is used for the name (`SETPROG`), and BASIC's own put back after (`SETSOS`).
;; See: <Load>, <Files::ProgramLength>, <Files::TransferProgram>
;; Also: SAVE (BB13)
.proc Save
    .using Files
    lda #0
    sta CMDFLG
.if VERSION >= 130
    jsr SETPROG                             ; 1.3: use the program's prefix
.endif
    lda #OPEN_WRITE                         ; to write: OpenNamed makes the file if it is missing
    ldx #PRGTY
    jsr OpenOfType
    jsr ProgramLength
    lda #PROGRAM_HEADER_SIZE                ; write the header's two zero bytes
    sta INBYTES
    lda #0
    sta INBYTES+1
    lda #<(ProgramHeader)
    sta SBFPTR
    lda #>(ProgramHeader)
    sta SBFPTR+1
    jsr WriteBlock
    lda TXTTAB                              ; then the program, from TXTTAB
    sta INDEX
    lda TXTTAB+1
    sta INDEX+1
    lda TXTTABB
    sta INDEXB
    jsr TransferProgram
    ldy #POSITION_SIZE-1                    ; set the end of file at the mark: 0 forward from it
    lda #0

;; Clears the displacement's next byte.
;; Also: DSP0LUP (BB13)
ClearDisplacement:
    sta DSPLMNT,Y
    dey
    bpl ClearDisplacement
    lda #BASE_FORWARD_FROM_MARK
    sta DSPLMNT-1
    ldy #STE
    jsr SETGO
    jsr CloseSosFile
.if VERSION >= 130
    jsr SETSOS                              ; 1.3: back to BASIC's own prefix
.endif
    rts
.endproc

.endscope

; Files: opening and loading a program.
.scope Files continued

;; Opens the named file through <OpenNamed>, and closes it with a type mismatch unless its type is the one asked for.
;; In: A = the access: <OPEN_READ> to read, or <OPEN_WRITE> to write, making the file if it is missing; X = the file
;;   type
;; Out: RWRFNM = the file's reference number, FEOF = its end of file
;; See: <WrongTypeError>
;; Also: OPENIT (BB13)
.proc OpenOfType
    stx TEMPFOR
    jsr OpenNamed
    ldx TEMPFOR
    cpx FID
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
    ldx #PRGTY
    jsr OpenOfType
    ; Falls into LoadProgram.
.endproc

;; Loads the program from the open file in <RWRFNM> into memory at <TXTTAB>, setting <ARYTAB> to its end, and closes
;; the file.
;;
;; The two bytes at the start are read and ignored, which saves a `SET_MARK`; the length is the end of file, from the
;; file's information, less 2. A program that would reach <MEMSIZ> in the top bank is an out-of-memory error before
;; anything more is read, and the file is left open.
;;
;; <ProgramLengthFromEnd> takes the 2 from the end of file's low byte only, without the borrow, so an end of file
;; whose low byte is 0 or 1 gives a length 256 too long. The read stops at the end of file, but <ARYTAB> lands 256 bytes
;; past the program, and those bytes are saved with it next time, which repeats the fault on the next load.
;; See: <TransferProgram>, <Statements::Chain>
;; Also: DOLD2 (BB13)
.proc LoadProgram
    jsr CLEARONS
    lda #<(ProgramHeader)                   ; read the two bytes at the start
    sta SBFPTR
    lda #>(ProgramHeader)
    sta SBFPTR+1
    lda #0
    sta INBYTES+1
    lda #PROGRAM_HEADER_SIZE
    sta INBYTES
    jsr ReadBlock
    jsr ProgramLengthFromEnd                ; the length, into LengthLeft
    ldy TXTTABB                             ; work out the program's end, ARYTAB

;; Takes 64K at a time off the length, as a bank and a bank's pages.
;; Also: SVLP1 (BB13)
TakeBanks:
    lda LengthLeft+2                        ; 64K or more?
    beq AddRest
    dec LengthLeft+2                        ; take 64K off: 32K onto the page byte,
    clc
    lda LengthLeft+1
    adc #MAXPG-MINPG
    sta LengthLeft+1
    iny                                     ; and 32K as a bank
    bcc TakeBanks
    iny                                     ; the page byte overflowed: two banks more
    iny
    bcs TakeBanks

;; Adds the rest to <TXTTAB> and checks the end is below <MEMSIZ>.
;; Also: SVLP2 (BB13)
AddRest:
    clc                                     ; add what is left to TXTTAB
    lda LengthLeft
    adc TXTTAB
    tax
    lda LengthLeft+1
    adc TXTTAB+1
    jsr FIXADC                              ; keep the page between MINPG and MAXPG
    cpy HIMEMB                              ; below the top bank: it fits
    bcc Fits
    bne ToOutOfMemoryError
    cpx MEMSIZ                              ; in the top bank: below MEMSIZ?
    pha
    sbc MEMSIZ+1
    pla
    bcs ToOutOfMemoryError

;; Sets <ARYTAB> to the program's end and reads the program.
;; Also: SVLDPP (BB13)
Fits:
    stx ARYTAB
    sta ARYTAB+1
    sty ARYTABB
    jsr ProgramLengthFromEnd                ; the length again, for the read
    lda TXTTAB
    sta INDEX
    lda TXTTAB+1
    sta INDEX+1
    lda TXTTABB
    sta INDEXB
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
    jmp OMERR
.endproc

.endscope

; Statements: `LOAD`.
.scope Statements continued

;; `LOAD`: loads a BASIC program and returns to the prompt; `LOAD name`.
;;
;; The variables are cleared, but open files stay open (<CLEARL>, not <CLEARC>), and `TRACE` goes off. In 1.3 the
;; program's prefix is used for the name (`SETPROG`), and BASIC's own put back after (`SETSOS`).
;; See: <Files::OpenAndLoadProgram>, <Save>
;; Also: LOAD (BB13)
.proc Load
    lda #0
    sta CMDFLG
.if VERSION >= 130
    jsr SETPROG                             ; 1.3: use the program's prefix
.endif
    jsr Files::OpenAndLoadProgram
    jsr CLEARL
    lsr TRFLAG                              ; TRACE off
.if VERSION >= 130
    jsr SETSOS                              ; 1.3: back to BASIC's own prefix
.endif
    jmp MAIN
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

;; Writes from the parameters in <SOSTBL>; an error closes the file and ends the statement.
;; Also: SVWRT (BB13)
.proc WriteBlock
    ldy #WRT
    .byte $2C                               ; BIT absolute skips ReadBlock's LDY
    ; Falls into ReadBlock.
.endproc

;; Reads from the parameters in <SOSTBL>, or writes from them when entered from <WriteBlock>; an error closes the
;; file and ends the statement.
;; In: Y = `WRITE`'s index, from <WriteBlock>
;; Also: LDRED (BB13)
.proc ReadBlock
    ldy #RED
    jsr SETUP
    jsr GOSOS
    beq TransferDone
    jmp CloseWithError
.endproc

;; Reads or writes the program's bytes from <INDEX> on, in parts of at most <ProgramPartSize> bytes, until the length
;; in <LengthLeft> is done.
;;
;; The buffer address SOS gets is <INDEX>'s own: a zero-page pointer with its bank in <INDEXB>, which SOS follows as an
;; extended address.
;; In: INDEX/INDEXB = the program's start, TransferDirection = <TRANSFER_READ> to read or 0 to write,
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
    sta INBYTES
    lda ProgramPartSize+1
    sta INBYTES+1
    lda #<(INDEX)
    sta SBFPTR
    lda #>(INDEX)
    sta SBFPTR+1
    jsr ReadOrWriteBlock
    lda INDEX                               ; move INDEX past it
    clc
    adc ProgramPartSize
    sta INDEX
    lda INDEX+1
    adc ProgramPartSize+1
    ldy INDEXB
    jsr FIXADC
    sty INDEXB
    sta INDEX+1
    jsr SubtractPart
    jmp TransferProgram

;; Under 64K left: moves a full part while more than one is left, then the rest.
;; Also: somewhere (BB13)
LastParts:
    lda ProgramPartSize+1
    cmp LengthLeft+1                        ; more than a part left?
    bcc FullPart
    lda LengthLeft+1                        ; no: the rest
    sta INBYTES+1
    lda LengthLeft
    sta INBYTES
    lda #<(INDEX)
    sta SBFPTR
    lda #>(INDEX)
    sta SBFPTR+1
    jsr ReadOrWriteBlock
    rts
.endproc

;; Sets the program's length in <LengthLeft> from the end of file in <FEOF>, less the two bytes before the program.
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
    lda FEOF,Y
    sta LengthLeft,Y
    dey
    bne CopyByte
    lda FEOF,Y                              ; the low byte less 2
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

;; `RENAME`: renames a file; `RENAME old, new`. Both names go in <NAMBUF>, the new one after the old.
;; Also: RENAME (BB13)
.proc Rename
    jsr Files::TakeName
    lda PTHPTR                              ; keep the old name's address
    pha
    lda PTHPTR+1
    pha
    jsr CHKCOM
    inx                                     ; the new name goes after it
    jsr Files::TakeName::AtIndex
    lda PTHPTR
    sta NWPTHNM
    lda PTHPTR+1
    sta NWPTHNM+1
    pla
    sta PTHPTR+1
    pla
    sta PTHPTR
    ldy #RNM
    jmp SETGO
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
    sta FATRB
    jsr Files::TakeName
    lda #<(FATRB)
    sta FLSTPTR
    lda #>(FATRB)
    sta FLSTPTR+1
    lda #ACCESS_ONLY                        ; the list's one byte
    sta INLNGTH
    ldy #SFI
    jmp SETGO
.endproc

;; `DELETE`: destroys a file; `DELETE name`.
;; Also: DDELETE (BB13)
.proc Delete
    jsr Files::TakeName
    ldy #DST
    jmp SETGO
.endproc

.endscope

; ---------------------------------------------------------------------------------------------------------------------
; The program's length
; ---------------------------------------------------------------------------------------------------------------------

; Files: the program's length, a record length, and records.
.scope Files continued

;; Works out the program's length, <ARYTAB> less <TXTTAB>, as a 32-bit number in <LengthLeft>.
;;
;; Each bank the program crosses adds $80 pages (32K), as a pointer's page runs from <MINPG> to <MAXPG> in each bank.
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
    sta BCDSTR,Y
    dey
    bpl Clear
    lda ARYTAB
    sec
    sbc TXTTAB
    sta LengthLeft
    lda ARYTAB+1
    sbc TXTTAB+1
    ldy ARYTABB
    cpy TXTTABB                             ; in another bank?
    beq StorePages
    clc
    adc #MAXPG-MINPG                        ; yes: one bank's pages
    dey

;; Stores the pages' count.
;; Also: PGMLEN2 (BB13)
StorePages:
    sta LengthLeft+1

;; Adds a bank's pages for each bank more.
;; Also: PGMLEN3 (BB13)
NextBank:
    cpy TXTTABB
    beq Done
    lda LengthLeft+1
    clc
    adc #MAXPG-MINPG
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

;; Reads an optional record length after a comma into <INAUXID>, <DEFAULT_RECORD_LENGTH> when there is none.
;; Errors: an illegal quantity below <MINIMUM_RECORD_LENGTH> or above 32767
;; See: <Statements::Create>
;; Also: GRECLN (BB13)
.proc TakeRecordLength
    lda #<DEFAULT_RECORD_LENGTH
    sta INAUXID
    lda #>DEFAULT_RECORD_LENGTH
    sta INAUXID+1
    jsr CHRGOT
    beq Done
    jsr CHKCOM
    jsr FRMNUM
    jsr POSINT
    ldx FACLO
    lda FACMO
    bmi BadLength
    bne Store
    cpx #MINIMUM_RECORD_LENGTH
    bcs Store

;; Ends the statement with an illegal quantity error.
;; Also: BUMSIZ (BB13)
BadLength:
    jmp FCERR

;; Keeps the record length.
;; Also: GRC2 (BB13)
Store:
    sta INAUXID+1
    stx INAUXID

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
;; came in with, and whatever else <SOSTBL> holds.
;; Out: A = the SOS error code, zero = set for none
;; See: <WriteRecordOrFail>, <MarkChanged>, <SetRecordTransfer>
;; Also: WRTRCD (BB13)
.proc WriteRecord
    ldy FCBNDX
    lda FCB+XFLGS,Y
    bpl WriteRecordOrFail::NoError          ; unchanged
    lda FCB+XBUFOFS+1,Y
    pha
    lda FCB+XBUFOFS,Y
    pha
    ora FCB+XBUFOFS+1,Y
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
    sta INBYTES
    pla
    adc #0
    sta INBYTES+1
    ldy #WRT
    jsr SETUP
    jmp GOSOS
.endproc

;; Moves to the file's next record: writes the current one back if it changed, then positions to the next and reads
;; it in.
;; See: <LoadRecord>
;; Also: NXRCD (BB13)
.proc NextRecord
    jsr WriteRecordOrFail
    ldx FCBNDX
    inc FCB+XRNUM,X
    bne Load
    inc FCB+XRNUM+1,X

;; Moves to the record and reads it.
;; Also: NXR2 (BB13)
Load:
    jmp LoadRecord
.endproc

;; Sets <SOSTBL> up to read or write the file's whole record through its buffer, with the buffer's offset at 0.
;;
;; The buffer address SOS gets is <NDXPTR>'s own, a zero-page pointer with its bank in <NDXPTRB>.
;; In: FCBNDX = the file's index in <FCB>
;; Out: Y = FCBNDX, INBYTES = the record length, RWRFNM = the file's reference number
;; See: <PointAtItem>
;; Also: SETPARMS (BB13)
.proc SetRecordTransfer
    lda #0
    ldy FCBNDX
    sta FCB+XBUFOFS,Y
    sta FCB+XBUFOFS+1,Y
    jsr PointAtItem
    lda #<(NDXPTR)
    sta SBFPTR
    lda #>(NDXPTR)
    sta SBFPTR+1
    ldy FCBNDX
    lda FCB+XRECL,Y
    sta INBYTES
    lda FCB+XRECL+1,Y
    sta INBYTES+1
    lda FCB+XRFNM,Y
    sta RWRFNM
    rts
.endproc

.endscope

; ---------------------------------------------------------------------------------------------------------------------
; Errors and positions
; ---------------------------------------------------------------------------------------------------------------------

;; Ends the statement with BASIC's error for the SOS error in A, from <ERRTBL>.
;;
;; The search stops at the first entry above the code, so the table must be in ascending order. A code it lacks gives
;; BASIC's SOS error, <SSSSSS>, with the code kept in <SOSLOC>.
;; In: A = the SOS error code
;; See: <ERROR>
;; Also: SERROR (BB13)
.proc ReportSosError
    ldx #0

;; Compares the code with the table's next entry.
;; Also: FNDAER1 (BB13)
Search:
    cmp ERRTBL,X
    beq Found
    inx
    inx
    bcs Search                              ; the code is above this entry
    ldx #SSSSSS
    sta SOSLOC
    jmp ERROR

;; Gives BASIC's error for the entry found.
;; Also: FOUNAR1 (BB13)
Found:
    inx
    lda ERRTBL,X
    tax
    jmp ERROR
.endproc

; Files: the file information call, and records' positions.
.scope Files continued

;; Sets <SOSTBL> up for `GET_FILE_INFO` into <FATRB>, all 11 bytes of it; the caller makes the call.
;; Out: Y = the call's index, <GFI>
;; Keeps: X
;; See: <GETFI>, <SETUP>
;; Also: GETFISET (BB13)
.proc PrepareGetFileInfo
;; The length of `GET_FILE_INFO`'s list.
FILE_INFO_LENGTH = $B

    lda #<(FATRB)
    sta FLSTPTR
    lda #>(FATRB)
    sta FLSTPTR+1
    lda #FILE_INFO_LENGTH
    sta INLNGTH
    ldy #GFI
    rts
.endproc

;; Works out the start of the file's current record, the record number times the record length, as the displacement
;; from the start of the file for `SET_MARK` or `SET_EOF`, and sets the buffer's offset to 0.
;; In: FCBNDX = the file's index in <FCB>
;; Out: DSPLMNT..DSPLMNT+3 = the position, BASE = 0, Y = 0
;; Uses: A, X
;; Entry:
;;   Return = returns; <SeekRecord> branches here
;; See: <Multiply>, <SeekRecord>
;; Also: SETDSP (BB13)
.proc RecordPosition
    ldy FCBNDX
    lda #0
    sta FCB+XBUFOFS,Y
    sta FCB+XBUFOFS+1,Y
    lda FCB+XRNUM,Y
    sta MLTPLR
    lda FCB+XRNUM+1,Y
    sta MLTPLR+1
    lda FCB+XRECL,Y
    sta MLTPLR2
    lda FCB+XRECL+1,Y
    sta MLTPLR2+1
    jsr Multiply
    ldy #POSITION_SIZE

;; Copies the product's next byte.
;; Also: QTIP (BB13)
CopyPosition:
    lda RSLT-1,Y
    sta DSPLMNT-1,Y
    dey
    bne CopyPosition
    sty BASE                                ; base 0: from the start of the file

;; Returns; <SeekRecord> branches here.
;; Also: PPRTS (BB13)
Return:
    rts
.endproc

;; Moves the file's mark to the start of its current record.
;;
;; A character device, which has no mark, is let be. Past the end of file, reading ends the data: a 0 goes at the
;; buffer's start and <CHKEOF> takes over. Writing moves the end of file to the end of that record, then sets the mark
;; again.
;; See: <RecordPosition>, <LoadRecord>
;; Also: POSREC (BB13)
.proc SeekRecord
    jsr RecordPosition
    ldy #STM
    jsr SETUP
    jsr GOSOS
    beq RecordPosition::Return
    cmp #SENBK                              ; not a block device
    beq RecordPosition::Return
    cmp #SOS_ERROR_POSITION                 ; a position past the end of file
    beq PastEnd
    jmp ReportSosError
PastEnd:
    bit IOFLG
    bmi EndOfData                           ; reading
    jsr CheckWriteAccess
    ldx FCBNDX                              ; the end of file at the next record's start
    inc FCB+XRNUM,X
    bne SetEnd
    inc FCB+XRNUM+1,X
SetEnd:
    jsr RecordPosition
    ldy #STE
    jsr SETGO
    ldx FCBNDX                              ; and the record number back
    lda FCB+XRNUM,X
    bne Back
    dec FCB+XRNUM+1,X
Back:
    dec FCB+XRNUM,X
    jmp SeekRecord

;; Leaves an empty record and goes to the end-of-file handling.
;; Also: PSRERR (BB13)
EndOfData:
    jsr PointAtItem
    tya                                     ; A = 0, an empty record
    sta (NDXPTR),Y
    jmp CHKEOF
.endproc

.endscope
