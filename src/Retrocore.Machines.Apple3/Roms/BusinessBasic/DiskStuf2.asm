; retrocore: style=strict
; DISKSTUF2: the `OPEN` statement, the check every read and write makes that a file is open as the right type, and
; the open that `LOAD`, `SAVE`, `INVOKE` and `OPEN` share.
;
; A data file opens without knowing whether it is text or binary data: the first read or write decides, and sets the
; type of a new file.
;
; Names follow Apple's Business BASIC 1.3 listing (BB13), kept in each definition's `Also:`.

; ---------------------------------------------------------------------------------------------------------------------
; The type check
; ---------------------------------------------------------------------------------------------------------------------

; Files: the check that a file is open as the right type.
.scope Files continued

;; Checks, before a binary read or write, that the file is open and holds binary data, as <PrepareTextFile> does
;; for text.
;; In: FCBNDX = the file's control block index
;; Out: Y = the control block index
;; Uses: A, X, TYPSAV
;; See: <CheckWriteAccess>, <Statements::Open>
;; Also: PREBIN (BB13)
.proc PrepareDataFile
    lda #BINTIP
    .byte $2C                               ; BIT absolute skips PrepareTextFile's LDA
    ; Falls into PrepareTextFile.
.endproc

;; Checks, before a text read or write, that the file is open and holds text.
;;
;; The first read or write after `OPEN` completes the open. A file of unknown type gets the type asked for, which SOS
;; records in the file's information; a text file also gets SOS's new-line mode. Then the file moves to its record
;; (<LoadRecord>), and the type must match or the statement ends with a type mismatch.
;;
;; If the file has been given a type since it was opened, SOS's is left alone, but the control block still takes the
;; type asked for, so the check passes whatever the file holds.
;; In: FCBNDX = the file's control block index, A = the type asked for when <PrepareDataFile> skips the LDA
;; Out: Y = the control block index
;; Uses: A, X, TYPSAV
;; See: <CheckWriteAccess>, <Statements::Open>
;; Also: PRETXT (BB13)
.proc PrepareTextFile
    lda #TXTTYP
    sta TYPSAV
    ldy FCBNDX
    lda FCB+XRFNM,Y
    beq ToNotOpenError                      ; not open
    lda FCB+XFLGS,Y
    asl                                     ; bit 6, FLAG_OPENING: the open isn't complete
    bpl CheckType
    asl                                     ; clears the flags, as bit 6 was the only one
    sta FCB+XFLGS,Y
    lda FCB+XUID,Y
    and #TYPE_MASK
    cmp #UNKNTY
    bne FinishOpen
    jsr PointAtItem                         ; OPEN left the file's name in its buffer
    lda RWRFNM
    pha
    lda #<(NDXPTR)                          ; the name's address, through NDXPTR
    sta PTHPTR
    lda #>(NDXPTR+1)                        ; the same zero page as NDXPTR
    sta PTHPTR+1
    jsr GETFI
    lda FID
    cmp #UNKNTY
    bne RecordType                          ; it has a type already: leave it be
    jsr CheckWriteAccess                    ; setting the type is a write
    lda TYPSAV
    sta FID
    ldy #SFI
    jsr SETGO
    lda TYPSAV
    cmp #TXTTYP
    bne RecordType
    pla                                     ; the reference number, left on the stack
    pha
    sta RWRFNM
    jsr SetNewlineMode                      ; new-line mode, at RETURN

;; Records the type asked for in the file's control block, after the reference number is restored.
;; Also: GTTYP1 (BB13)
RecordType:
    pla
    sta RWRFNM
    ldy FCBNDX
    lda FCB+XUID,Y
    and #ACCESS_MASK
    ora TYPSAV
    sta FCB+XUID,Y

;; Finishes the open: moves the file to its record, which reads it.
;; Also: FINOPN (BB13)
FinishOpen:
    jsr LoadRecord
    ldy FCBNDX

;; Ends the statement with a type mismatch unless the file's type is the one in <TYPSAV>.
;; In: Y = the file's control block index
;; Also: CKTYP (BB13)
CheckType:
    lda FCB+XUID,Y
    eor TYPSAV
    and #TYPE_MASK
    bne ReportTypeMismatch
    rts
.endproc

;; Ends the statement with a type mismatch error.
;; See: <CHKERR>
;; Also: ERTYP (BB13)
.proc ReportTypeMismatch
    jmp CHKERR
.endproc

.endscope

; ---------------------------------------------------------------------------------------------------------------------
; OPEN
; ---------------------------------------------------------------------------------------------------------------------

; Statements: OPEN.
.scope Statements continued

;; The `OPEN` statement: `OPEN #n [AS INPUT | AS OUTPUT | AS EXTENSION], name [, record length]`.
;;
;; A file that is open under that number is closed first. A file that doesn't exist is created, unless it is opened
;; `AS INPUT`. The file must be of unknown type, text or binary data; a directory opens as a catalog. A data file gets
;; a buffer of its record length from SOS; `AS EXTENSION` moves the file to its end.
;;
;; The access mode goes in the top of the control block's type byte (<Files::ACCESS_MASK>): <Files::ACCESS_READ> to
;; read only, <Files::ACCESS_WRITE> to write only, that and <Files::ACCESS_END> to write at the end, 0 for both.
;; See: <Files::OpenNamed>, <Files::PrepareDataFile>, <Directory::Prepare>, <Files::TakeRecordLength>
;; Also: DOPEN (BB13)
.proc Open
    .using Files

;; The search mode `FIND_SEG` takes for a segment anywhere in memory, across banks.
SEARCH_ANYWHERE = 2

;; The ID BASIC gives the segments it asks for files' buffers.
BUFFER_SEGMENT_ID = 18

;; The bit of an X-byte that says the pointer reaches through a bank pair.
XBYTE_ON = $80

;; What a segment's page, as `FIND_SEG` gives it, is above the page BASIC addresses it at.
BUFFER_PAGE_BIAS = $20

    jsr TakeFileNumber
    beq TakeMode                            ; not open under this number
    stx XSAV
    jsr CloseFile
    ldx XSAV
    jsr Files::TakeFileNumber::FromIndex

;; Looks for `AS INPUT`, `AS OUTPUT` or `AS EXTENSION`.
;; Also: DOP2 (BB13)
TakeMode:
    ldx #$00                                ; no AS
    lda #ASTKN
    jsr TRYESC
    bne SetMode
    jsr CHRGET
    cmp #INPTKN
    bne TryOutput
    ldx #ACCESS_READ                        ; INPUT: read only

;; Takes `AS OUTPUT` or `AS EXTENSION`, after `AS INPUT` was looked for.
;; In: A = the token after `AS`, X = <Files::ACCESS_READ> for `INPUT`, otherwise 0
;; Also: AS1 (BB13)
TryOutput:
    cmp #OUTTKN
    bne TryExtension
    ldx #ACCESS_WRITE                       ; `OUTPUT`: write only

;; Takes `AS EXTENSION`.
;; Also: AS2 (BB13)
TryExtension:
    lda #EXTKN
    jsr TRYESC
    bne CheckMode
    ldx #ACCESS_WRITE | ACCESS_END          ; EXTENSION: write, at the end

;; Ends the statement with a syntax error unless one of the modes followed `AS`, then steps over it.
;; In: X = the mode
;; Also: AS3 (BB13)
CheckMode:
    txa
    beq ToSyntaxError
    jsr CHRGET

;; Takes the mode into the control block and `OPEN`'s access (<Files::OPEN_READ> for `INPUT`, otherwise any or to
;; read and write), then the name and the record length.
;; In: X = the mode
;; Also: NOTAS (BB13)
SetMode:
    txa
    ldy FCBNDX
    sta FCB+XUID,Y
    lsr
    lsr
    lsr
    lsr
    cmp #OPEN_WRITE
    bcc StoreAccess
    lda #OPEN_READ_WRITE                    ; `OUTPUT` and `EXTENSION` read their records too
StoreAccess:
    sta INREQ
    jsr CHKCOM
    jsr TakeName
    jsr TakeRecordLength
    jmp OpenFile

;; Ends the statement with a syntax error.
;; See: <SNERR>
;; Also: GVERR (BB13)
ToSyntaxError:
    jmp SNERR

;; Closes a file of the wrong type and ends the statement with a type mismatch.
;; See: <Files::CloseControlBlock>, <Files::ToTypeMismatchError>
;; Also: GVTT (BB13)
WrongType:
    jsr CloseControlBlock
    jmp ToTypeMismatchError

;; Opens the file, creating it when it may, and fills in its control block.
;; Also: NOTAS2 (BB13)
OpenFile:
    lda #UNKNTY                             ; a new file's type is decided later
    sta TYPSAV
    jsr Files::OpenNamed::WithName
    ldy FCBNDX
    lda #FLAG_OPENING                       ; PrepareDataFile or PrepareTextFile finishes the open
    sta FCB+XFLGS,Y
    lda REFOUT
    sta FCB+XRFNM,Y
    lda FSTYP
    cmp #STORAGE_SUBDIRECTORY               ; a directory's storage type
    bcs ToDirectory
    lda FID
    cmp #UNKNTY
    beq AddType
    cmp #BINTIP
    beq AddType
    cmp #TXTTYP
    bne WrongType

;; Adds the file's type to the control block and takes its record length, the auxiliary type,
;; <Files::DEFAULT_RECORD_LENGTH> when that is 0.
;; In: A = the file's type, Y = the control block index
;; Also: OPG2 (BB13)
AddType:
    and #TYPE_MASK
    ora FCB+XUID,Y
    sta FCB+XUID,Y
    lda FAUX
    sta FCB+XRECL,Y
    lda FAUX+1
    sta FCB+XRECL+1,Y
    ora FAUX
    bne CheckText
    lda #>DEFAULT_RECORD_LENGTH             ; 512
    sta FAUX+1
    sta FCB+XRECL+1,Y

;; Sends a text file to <TextFile>; any other file gets a buffer.
;; Also: RNDYSLAB (BB13)
CheckText:
    lda FID
    cmp #TXTTYP
    beq TextFile

;; Gets a buffer for a record from SOS with `FIND_SEG`, anywhere in memory, and if SOS has none frees that many pages
;; of BASIC's memory (<SCRUNCH>) and asks again.
;;
;; The record length also goes in <DVSR>, for <Files::RecordFromEnd> to find the end of the file `AS EXTENSION`.
;; Also: OPLP (BB13)
GetBuffer:
    ldy FAUX+1
    ldx FAUX
    stx DVSR
    sty DVSR+1
    beq FindSegment
    iny                                     ; a part page needs a page of its own

;; Makes the `FIND_SEG` call for Y pages.
;; Also: OPGD1 (BB13)
FindSegment:
    sty IOPGCN
    lda #0
    sta IOPGCN+1
    lda #SEARCH_ANYWHERE
    sta ISRCHMD
    lda #BUFFER_SEGMENT_ID
    sta ISEGID
    ldy #FND
    jsr SETUP
    jsr GOSOS
    beq Opened
    cmp #SOS_ERROR_SEGMENT_DENIED
    bne ToReportSosError
    ldy FAUX+1
    ldx FAUX
    beq FreePages
    iny
FreePages:
    tya
    jsr SCRUNCH
    jmp GetBuffer

;; Opens a directory as a catalog.
;; See: <Directory::Prepare>
;; Also: GTDIR (BB13)
ToDirectory:
    jmp Directory::Prepare

;; Ends the statement with the SOS error in A.
;; See: <ReportSosError>
;; Also: OPSHIT (BB13)
ToReportSosError:
    jmp ReportSosError

;; Sets new-line mode on a text file and marks it as having no buffer.
;; Also: GTTXT (BB13)
TextFile:
    jsr SetNewlineMode
    lda #TEXT_SEGMENT
    sta OSEGNM

;; Records the buffer and its segment in the control block, then, `AS EXTENSION`, moves the file to its end.
;;
;; The buffer's address goes in BASIC's form: the bank with bit 7 set, and the page less $20. <FIXSBC>'s result isn't
;; stored, so that call changes nothing; <Files::PointAtItem> adjusts the address when it adds the offset. A text file
;; has no buffer, and gets whatever <BSBNKP> holds.
;;
;; At the end of a binary data file, the last record is read and the offset set to its last byte, to write over the
;; record's end mark, or to a new record when the last one is full. A text file's mark is set to its end. Any other
;; file, other than a text file, gets its name copied into the buffer for <Files::PrepareTextFile> (<CopyName>).
;; Also: OPGOOD (BB13)
Opened:
    ldx FCBNDX
    lda BSBNKP
    ora #XBYTE_ON
    sta FCB+XBUFPT,X
    tay
    lda BSBNKP+1
    sec
    sbc #BUFFER_PAGE_BIAS
    sta FCB+XBUFPT+1,X
    jsr FIXSBC
    lda OSEGNM                              ; for CLOSE to release
    sta FCB+XSEGNM,X
    lda FCB+XRFNM,X
    sta RWRFNM
    lda FCB+XUID,X
    and #ACCESS_END                         ; AS EXTENSION?
    beq CopyName
    lda FID
    cmp #UNKNTY
    beq CopyName
    cmp #TXTTYP
    php
    lda #0                                  ; the open is complete
    sta FCB+XFLGS,X
    plp
    beq TextAtEnd
    jsr RecordFromEnd                       ; the last record, and the bytes in it
    lda RMNDR
    tay
    ora RMNDR+1
    beq ReadLast                            ; the last record is full: start a new one
    tya
    bne BackOne
    dec RMNDR+1
BackOne:
    dec RMNDR                               ; back to the record's end mark

;; Reads the last record and sets the buffer's offset to the place in <RMNDR>.
;; Also: OPGOT (BB13)
ReadLast:
    lda RMNDR+1
    pha
    lda RMNDR
    pha
    jsr LoadRecord
    ldy FCBNDX
    pla
    sta FCB+XBUFOFS,Y
    pla
    sta FCB+XBUFOFS+1,Y
    rts

;; Copies the file's name, with its length first, from <NAMBUF> to the start of its buffer, unless it is a text file.
;; See: <Files::PrepareTextFile>
;; Also: NOEXT (BB13)
CopyName:
    jsr PointAtItem
    lda OSEGNM
    bmi Done                                ; a text file
    lda NAMBUF
    tax
    inx                                     ; the length byte as well
    ldy #0

;; Copies the name's next byte.
;; Also: NOX2 (BB13)
NextByte:
    sta (NDXPTR),Y
    iny
    lda NAMBUF,Y
    dex
    bne NextByte

;; Returns.
;; Also: XYZZY (BB13)
Done:
    rts

;; Sets a text file's mark to its end (`SET_MARK` from the end of file, by 0), then goes on as <CopyName>.
;;
;; The base is SOS's 1, a distance back from the end of file (SOS's ADJMARK).
;; Also: TXTEXT (BB13)
TextAtEnd:
    ldy #POSITION_SIZE
    lda #0

;; Clears the base and the four-byte displacement, from the top.
;; Also: TE1 (BB13)
ClearPosition:
    sta DSPLMNT-1,Y                         ; the base and the four-byte displacement
    dey
    bpl ClearPosition
    inc DSPLMNT-1                           ; base 1: back from the end of file
    ldy #STM
    jsr SETGO
    jmp CopyName
.endproc

.endscope

; ---------------------------------------------------------------------------------------------------------------------
; The shared open
; ---------------------------------------------------------------------------------------------------------------------

; Files: the open the file commands share.
.scope Files continued

;; Opens the file named in the statement, for `INVOKE`, `LOAD`, `SAVE`, `CATALOG` and `OPEN`, creating it when it
;; isn't there and the access isn't read only.
;;
;; A character device, which has no file information, opens as a text file. When SOS has no room to open the file,
;; BASIC frees 4 pages of its memory (<SCRUNCH>) and tries again. In 1.3, SOS's prefix becomes the program's
;; (`SETPROG`) before the name is looked up.
;; In: A = `OPEN`'s access: <OPEN_READ> to read (`LOAD`), <OPEN_WRITE> to write (`SAVE`), X = the type a new file
;;   gets
;; Out: A and RWRFNM = the file's reference number, FID = its type, FSTYP = its storage type, FAUX = its auxiliary
;;   type
;; Entry:
;;   WithName = takes the name already in <PTHPTR>, the access in <INREQ> and the type in <TYPSAV>
;; See: <TakeName>, <CreateFile>, <Statements::Open>
;; Also: OPNPRTB (BB13)
.proc OpenNamed
;; The count of `OPEN`'s options BASIC gives: the access alone.
OPEN_OPTIONS = 1

;; How many pages BASIC frees when SOS has no room to open a file.
OPEN_PAGES = 4

    sta INREQ
    stx TYPSAV
    jsr TakeName
.if VERSION >= 130
    jsr SETPROG                             ; 1.3: SOS's prefix becomes the program's
.endif

;; Takes the name already in <PTHPTR>, the access in <INREQ> and the type in <TYPSAV>.
;; Also: OPNP2 (BB13)
WithName:
    jsr PrepareGetFileInfo
    jsr SETUP
    jsr GOSOS                               ; GET_FILE_INFO
    beq Open
    cmp #SENBK
    bne NotFound
    lda #TXTTYP                             ; a character device: text
    sta FID
    sta FSTYP                               ; and a storage type that isn't a directory's
    bne Open

;; Creates the file when `GET_FILE_INFO` didn't find it and the access isn't read only; any other error ends the
;; statement.
;; In: A = the SOS error
;; Also: OPPP2 (BB13)
NotFound:
    cmp #SEFNF
    bne ToReportSosError
    ldx INREQ
    dex
    beq ToReportSosError                    ; read only: file not found
    lda TYPSAV
    sta INFLID
    jsr CreateFile
    jmp WithName

;; Makes the `OPEN` call with the access in <INREQ>.
;; Also: OPNP3 (BB13)
Open:
    lda #<(INREQ)
    sta OPNLST
    lda #>(INREQ)
    sta OPNLST+1
    lda #OPEN_OPTIONS                       ; the option list holds only the access
    sta OPNLNGTH
    ldy #OPN
    jsr SETUP
    jsr GOSOS
    beq Opened
    cmp #SEMEM
    bne ToReportSosError
    lda #OPEN_PAGES
    jsr SCRUNCH
    jmp Open

;; Copies the new reference number into <RWRFNM> for the calls that follow.
;; Also: OPNRTS (BB13)
Opened:
    lda REFOUT
    sta RWRFNM
    rts

;; Ends the statement with the SOS error in A.
;; See: <ReportSosError>
;; Also: CMPLAIN (BB13)
ToReportSosError:
    jmp ReportSosError
.endproc

.endscope
