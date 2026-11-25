; retrocore: style=strict
; Apple's CATALOG file: the `CATALOG` command, and the catalog lines it prints, which `INPUT#` also reads from a
; directory opened as a file. Each line is built in CatalogBuffer from the directory file's entries. Then the table of
; BASIC's routines for invokable modules.
;
; Names follow Apple's Business BASIC 1.3 listing (BB13), kept in each definition's `Also:`.

; ---------------------------------------------------------------------------------------------------------------------
; `CATALOG`
; ---------------------------------------------------------------------------------------------------------------------

;; One entry of <Directory::Stages>: a stage's routine, less one, for <Directory::NextLine>'s RTS.
;; Parameters:
;;   stage = the stage's number
;;   routine = the routine that makes the stage's line
.macro Stage stage, routine
    .assert * - Stages = 2 * stage, "Each stage's routine is at twice its number in Stages."
    .word routine - 1
.endmacro

;; Reading a directory as catalog lines, for `CATALOG` and for `INPUT#` from a directory opened as a file.
;;
;; A directory is a file of 512-byte blocks: each starts with two link words, to the blocks before and after it, then
;; 13 entries of 39 bytes; the first block's first entry is the directory's header. The catalog's control block
;; counts the stage it has reached in <FileControlBlock::FLAGS> and the lines in <FileControlBlock::RECORD_NUMBER>, and,
;; for a volume, keeps the volume's blocks in <FileControlBlock::RECORD_LENGTH> and those used in
;; <FileControlBlock::BLOCKS_USED>.
.scope Directory

;; Where each read of the directory goes, in the name buffer.
;; Also: CTPL (BB13)
EntryBuffer = NameBuffer

;; The column <WriteTwoDigits> writes from, kept in <EntryBuffer>'s third byte while the line is made.
DigitColumn = EntryBuffer+2

;; The size of a block's two link words.
BLOCK_LINKS = 4

;; The low byte of the control block's offset at a block's last byte, after its links and 13 entries.
BLOCK_LAST_BYTE = $FF

;; The bits of an entry's first byte that hold the name's length; the storage type is in the others.
NAME_LENGTH_MASK = $0F

;; The length of a catalog line, which a 0 ends.
LINE_LENGTH = 69

;; The length of a date as <WriteDate> writes it, MM/DD/YY.
DATE_LENGTH = 8

;; The length of each name in <TypeNames>.
TYPE_NAME_LENGTH = 6

;; The count of names in <TypeNames>: the SOS file types 0 to 21.
TYPE_NAME_COUNT = 22

;; The catalog's control block's index from <FileControlBlocks>: <CatalogControlBlock>, after the ten files'.
CATALOG_INDEX = FILE_CONTROL_BLOCK_SIZE*FILE_COUNT

;; The stage that makes the directory's name line.
STAGE_NAME = 0

;; The stage that makes the blank line after it.
STAGE_BLANK = 1

;; The stage that makes the headings.
STAGE_HEADINGS = 2

;; The stage that makes the files' lines.
STAGE_FILES = 3

;; The stage that makes a volume's summary line.
STAGE_SUMMARY = 4

;; The last stage, whose line is never printed.
STAGE_END = 5

;; The stage the catalog is done at.
STAGE_DONE = 6

;; A directory's file entry.
.struct FileEntry
    ;; The storage type in the high four bits, the name's length in the low four; 0 for a deleted entry.
    STORAGE_AND_NAME_LENGTH .byte
    NAME .res 15                            ;; The name.
    FILE_TYPE .byte                         ;; The file type.
    KEY_POINTER .word                       ;; The file's key block.
    BLOCKS_USED .word                       ;; The blocks the file takes.
    END_OF_FILE .res 3                      ;; The end of file, low byte first.
    CREATED_DATE .word                      ;; The date it was created.
    CREATED_TIME .word                      ;; The time it was created: the minute, then the hour.
    VERSION .byte                           ;; The version of SOS that made it.
    MINIMUM_VERSION .byte                   ;; The lowest version that can read it.
    ACCESS .byte                            ;; Its access: read, write, rename and destroy.
    AUXILIARY_TYPE .word                    ;; Its auxiliary type: a data file's record length.
    MODIFIED_DATE .word                     ;; The date it was last changed.
    MODIFIED_TIME .word                     ;; The time it was last changed.
    HEADER_POINTER .word                    ;; The block of its directory's header.
.endstruct
.assert .sizeof(FileEntry) = 39, "A directory's entries are 39 bytes."

;; A directory's header, its first entry.
.struct HeaderEntry
    ;; The storage type in the high four bits, the name's length in the low four.
    STORAGE_AND_NAME_LENGTH .byte
    NAME .res 15                            ;; The directory's name.
    RESERVED .res 8                         ;; Not used.
    CREATED_DATE .word                      ;; The date it was created.
    CREATED_TIME .word                      ;; The time it was created.
    VERSION .byte                           ;; The version of SOS that made it.
    MINIMUM_VERSION .byte                   ;; The lowest version that can read it.
    ACCESS .byte                            ;; Its access.
    ENTRY_LENGTH .byte                      ;; The length of its entries, which the catalog takes as 39.
    ENTRIES_PER_BLOCK .byte                 ;; The entries in each block, which the catalog takes as 13.
    FILE_COUNT .word                        ;; The files in it.
    BIT_MAP_POINTER .word                   ;; A volume's: the block of its bit map.
    TOTAL_BLOCKS .word                      ;; A volume's: its blocks.
.endstruct
.assert .sizeof(HeaderEntry) = 39, "A directory's header is an entry's size."

;; What the catalog's first read takes: the first block's links and the header.
.struct FirstRead
    LINKS .res BLOCK_LINKS                  ;; The blocks before and after.
    HEADER .tag HeaderEntry                 ;; The directory's header.
.endstruct

.endscope

; Statements: `CATALOG`.
.scope Statements continued

;; `CATALOG`: lists a directory, or the prefix's when no name is given; `CATALOG [name]`.
;;
;; The directory opens for reading in <CatalogControlBlock>, the control block after the ten files', and
;; <Directory::NextLine> makes its lines one at a time. A file that is not a directory is a bad path error.
;; In: zero = set when no name follows
;; See: <Directory::Prepare>, <Directory::NextLine>
;; Also: CATALOG (BB13)
.proc Catalog
    bne Named
    brk                                     ; SOS's GET_PREFIX, into NameBuffer
    .byte SOS_GET_PREFIX
    .word CatalogPrefixList
    ldx NameBuffer
    lda #Files::OPEN_READ
    sta SosCalls::OpenAccess                ; read only, for OpenNamed::WithName
    ldy #0
    txa
    jsr Files::SetNameLength::AtY           ; SosCalls::Pathname at NameBuffer
    jsr Files::OpenNamed::WithName
    jmp Opened

;; Opens the directory named.
;; Also: ISANAM (BB13)
Named:
    lda #Files::OPEN_READ                   ; read only
    jsr Files::OpenNamed

;; Checks the file is a directory.
;; Also: CG0 (BB13)
Opened:
    ldy #FILE_CONTROL_BLOCK_SIZE
    lda SosCalls::FileStorageType
    cmp #Files::STORAGE_SUBDIRECTORY
    beq ClearBlock
    cmp #Files::STORAGE_VOLUME
    bne NotDirectory

;; Clears the catalog's control block and sets it up.
;; Also: CG1 (BB13)
ClearBlock:
    lda #0
    sta CatalogControlBlock-1,Y
    dey
    bne ClearBlock
    ldy #Directory::CATALOG_INDEX
    sty FileControlBlockIndex
    jsr Directory::Prepare
    lda SosCalls::Reference
    sta FileControlBlocks+FileControlBlock::REFERENCE_NUMBER,Y

;; Prints the next line, until the catalog is done.
;; Also: CG2 (BB13)
NextLine:
    jsr PrintNewline
    ldy #Directory::CATALOG_INDEX
    sty FileControlBlockIndex
    lda FileControlBlocks+FileControlBlock::REFERENCE_NUMBER,Y
    sta SosCalls::Reference
    jsr Directory::NextLine
    bcs Done
    lda #<(CatalogBuffer)
    ldy #>(CatalogBuffer)
    ldx #0                                  ; in BASIC's own bank
    jsr PrintText
    jmp NextLine

;; Closes the file and ends the statement with SOS's bad path error, <SOS_ERROR_BAD_PATH>.
;; Also: CATERR (BB13)
NotDirectory:
    lda #SOS_ERROR_BAD_PATH
    jmp Files::CloseWithError

;; Prints a blank line and closes the directory.
;; Also: CATDON (BB13)
Done:
    jsr PrintNewline                        ; a blank line at the end
    ldy #Directory::CATALOG_INDEX
    jmp Files::CloseControlBlock
.endproc
.assert FileControlBlocks + Directory::CATALOG_INDEX = CatalogControlBlock, "The catalog's block follows the files'."

.endscope

; Directory: the catalog's lines.
.scope Directory continued

;; Sets a control block up to read a directory as catalog lines: a read-only text file, at stage 0, with no buffer
;; segment.
;;
;; For a volume directory, the record length holds the volume's total blocks and <FileControlBlock::BLOCKS_USED> the
;; blocks used, from the directory's file information, for the summary line; for a subdirectory they are left as they
;; are.
;; In: FileControlBlockIndex = the control block's index,
;;   SosCalls::FileStorageType/SosCalls::FileAuxType/SosCalls::FileBlocks = the directory's information
;; Out: Y = <FileControlBlockIndex>
;; Uses: A, X
;; See: <SummaryLine>
;; Also: SETCAT (BB13)
.proc Prepare
    ldy FileControlBlockIndex
    lda #FILE_TYPE_TEXT | Files::ACCESS_READ ; text, read only
    sta FileControlBlocks+FileControlBlock::TYPE_AND_ACCESS,Y
    lda #0
    sta FileControlBlocks+FileControlBlock::FLAGS,Y
    sta FileControlBlocks+FileControlBlock::SEGMENT,Y
    ldx SosCalls::FileStorageType
    cpx #Files::STORAGE_VOLUME
    bne Done                                ; not a volume directory
    lda SosCalls::FileAuxType               ; a volume's auxiliary type is its total blocks
    sta FileControlBlocks+FileControlBlock::RECORD_LENGTH,Y
    lda SosCalls::FileAuxType+1
    sta FileControlBlocks+FileControlBlock::RECORD_LENGTH+1,Y
    lda SosCalls::FileBlocks
    sta FileControlBlocks+FileControlBlock::BLOCKS_USED,Y
    lda SosCalls::FileBlocks+1
    sta FileControlBlocks+FileControlBlock::BLOCKS_USED+1,Y

;; Returns.
;; Also: NTROOT (BB13)
Done:
    rts
.endproc

;; Makes the catalog's next line in <CatalogBuffer>, by the stage in the control block's flags.
;;
;; The line starts as <LINE_LENGTH> spaces and a 0, and the control block's record number counts the lines. The
;; stages give the directory's name line, a blank line, the headings, a line for each file, a volume's summary line,
;; and the end.
;; In: FileControlBlockIndex = the catalog's control block, SosCalls::Reference = the directory's reference number
;; Out: carry = set when the catalog is done
;; See: <Stages>
;; Also: NCLN (BB13)
.proc NextLine
    ldy #LINE_LENGTH+1
    lda #' '

;; Fills the line with spaces.
;; Also: NCL1 (BB13)
Blank:
    sta CatalogBuffer-1,Y
    dey
    bne Blank
    sty CatalogBuffer+LINE_LENGTH
    ldx FileControlBlockIndex
    inc FileControlBlocks+FileControlBlock::RECORD_NUMBER,X
    bne Dispatch
    inc FileControlBlocks+FileControlBlock::RECORD_NUMBER+1,X

;; Goes to the stage's routine, through an RTS.
;; Also: NCL2 (BB13)
Dispatch:
    lda FileControlBlocks+FileControlBlock::FLAGS,X
    asl                                     ; the stage's routine, through an RTS
    tay
    lda a:Stages+1,Y
    pha
    lda a:Stages,Y
    pha
    rts
.endproc

;; Each stage's routine, less one, for <NextLine>'s RTS.
;;
;; The second blank line's stage is never printed: by the time <BlankLine> moves past it, the stage is <STAGE_DONE>
;; and the catalog is done.
;; Also: CTDP (BB13)
Stages:
    Stage STAGE_NAME, NameLine
    Stage STAGE_BLANK, BlankLine
    Stage STAGE_HEADINGS, HeadingLine
    Stage STAGE_FILES, FileLine
    Stage STAGE_SUMMARY, SummaryLine
    Stage STAGE_END, BlankLine
.assert * - Stages = 2 * STAGE_DONE, "A routine for each stage before STAGE_DONE."

;; Makes the catalog's first line from the directory's header: its name, its creation date in parentheses, and its
;; version.
;;
;; The first read takes the block's two link words and the header entry, <FirstRead>.
;; In: X = the catalog's control block index, from <FileControlBlockIndex>
;; Out: carry = clear
;; Also: CATL1 (BB13)
.proc NameLine
;; Where the first read puts the header.
Header = EntryBuffer+FirstRead::HEADER

;; The column of the creation date, after its parenthesis.
DATE_COLUMN = 18

;; The column of the version's V.
VERSION_COLUMN = 28

    inc FileControlBlocks+FileControlBlock::FLAGS,X
    lda #.sizeof(FirstRead)
    jsr ReadBytes
    lda Header+HeaderEntry::STORAGE_AND_NAME_LENGTH
    and #NAME_LENGTH_MASK
    tay

;; Copies the name, from its end.
;; Also: CL12 (BB13)
CopyName:
    lda Header+HeaderEntry::NAME-1,Y
    sta CatalogBuffer,Y
    dey
    bne CopyName
    lda #'('
    sta CatalogBuffer+DATE_COLUMN-1
    lda #')'
    sta CatalogBuffer+DATE_COLUMN+DATE_LENGTH
    lda Header+HeaderEntry::CREATED_DATE+1  ; the creation date
    ldx Header+HeaderEntry::CREATED_DATE
    ldy #DATE_COLUMN
    jsr WriteDate
    lda #'V'
    sta CatalogBuffer+VERSION_COLUMN
    ldy Header+HeaderEntry::VERSION         ; the version
    jsr ReturnByte
    jsr Float::FormatFac
    ldy #$FF

;; Copies the version's digits, then finishes through <CheckDone>.
;; Also: TPL (BB13)
CopyVersion:
    iny
    lda NumberBuffer,Y
    beq CheckDone
    sta CatalogBuffer+VERSION_COLUMN+1,Y
    bne CopyVersion
    ; Never falls through: the loop ends at the branch to CheckDone. BlankLine follows.
.endproc

;; Moves to the next stage, leaving the line blank.
;; Out: carry = set when the catalog is done
;; Also: CBL (BB13)
.proc BlankLine
    ldx FileControlBlockIndex
    inc FileControlBlocks+FileControlBlock::FLAGS,X
    ; Falls into CheckDone.
.endproc

;; Tells whether the catalog is done: the stage has reached <STAGE_DONE>.
;; Out: carry = set when it is done
;; Also: TPRTS (BB13)
.proc CheckDone
    ldy FileControlBlockIndex
    lda FileControlBlocks+FileControlBlock::FLAGS,Y
    cmp #STAGE_DONE
    rts
.endproc

;; Makes the headings line, which its line feed follows with a blank one.
;; Out: carry = clear
;; Also: CHDG (BB13)
.proc HeadingLine
    ldy #HEADINGS_LENGTH

;; Copies the headings, from their end.
;; Also: CHD2 (BB13)
Copy:
    lda a:Headings-1,Y
    sta CatalogBuffer,Y
    dey
    bne Copy
    beq BlankLine                           ; always
.endproc

;; The catalog's headings, and a line feed for a blank line after them.
;; Also: HDMSG (BB13)
Headings:
    .byte " TYPE   BLKS  NAME            MODIFIED"
    .byte " TIME  CREATED  TIME   EOF"
    .byte $0A

;; The length of <Headings>.
;; Also: HDGLEN (BB13)
HEADINGS_LENGTH = *-Headings

;; Makes the line for the directory's next file: its access, type, blocks, name, the dates and times it was modified
;; and created, and its end of file.
;;
;; Deleted entries, with a name length of 0, are skipped. The access shows `*` for read only, nothing for full
;; access, and `+` for anything else. A type beyond <TypeNames> shows as `TYP=` and two hex digits, or `PRO=` for
;; ProDOS's types, from $E0. At the directory's end it moves to the next stage.
;; Out: carry = clear for a line made, or as <BlankLine> leaves it
;; See: <ReadEntry>, <WriteDate>, <WriteTime>
;; Also: CMP (BB13)
.proc FileLine
;; The column of the access's mark.
ACCESS_COLUMN = 1

;; The column of the type's name.
TYPE_COLUMN = 2

;; The first of the blocks' five columns.
BLOCKS_COLUMN = 9

;; The digits of the blocks' column.
BLOCKS_DIGITS = 5

;; The column of the name.
NAME_COLUMN = 15

;; The column of the date modified.
MODIFIED_DATE_COLUMN = 31

;; The column of the time modified.
MODIFIED_TIME_COLUMN = 40

;; The column of the date created.
CREATED_DATE_COLUMN = 46

;; The column of the time created.
CREATED_TIME_COLUMN = 55

;; The column of the end of file.
END_OF_FILE_COLUMN = 62

;; The first of ProDOS's file types.
PRODOS_TYPES = $E0

    jsr ReadEntry
    bcs BlankLine                           ; the end of the directory
    lda EntryBuffer+FileEntry::STORAGE_AND_NAME_LENGTH
    and #NAME_LENGTH_MASK
    beq FileLine                            ; 0: a deleted entry
    lda EntryBuffer+FileEntry::ACCESS
    and #Files::FILE_ACCESS_UNLOCKED
    cmp #Files::FILE_ACCESS_LOCKED          ; read only: locked
    bne NotLocked
    lda #'*'
    bne StoreAccess

;; Shows nothing for full access, `+` for anything but read only.
;; Also: NTLKD (BB13)
NotLocked:
    cmp #Files::FILE_ACCESS_UNLOCKED        ; everything: unlocked
    beq CopyName
    lda #'+'                                ; anything else

;; Stores the access's mark.
;; Also: STUFACS (BB13)
StoreAccess:
    sta CatalogBuffer+ACCESS_COLUMN

;; Copies the name, then the type's name.
;; Also: ALLOK (BB13)
CopyName:
    lda EntryBuffer+FileEntry::STORAGE_AND_NAME_LENGTH
    and #NAME_LENGTH_MASK
    tay

;; Copies the name's next character, from its end.
;; Also: CMP1 (BB13)
NameCharacter:
    lda EntryBuffer+FileEntry::NAME-1,Y
    sta CatalogBuffer+NAME_COLUMN-1,Y
    dey
    bne NameCharacter
    lda EntryBuffer+FileEntry::FILE_TYPE
    cmp #TYPE_NAME_COUNT
    bcs OtherType
    asl                                     ; times 6
    asl
    adc EntryBuffer+FileEntry::FILE_TYPE
    adc EntryBuffer+FileEntry::FILE_TYPE
    tax

;; Copies the type's name from <TypeNames>.
;; Also: CMP2 (BB13)
TypeName:
    lda a:TypeNames,X
    sta CatalogBuffer+TYPE_COLUMN,Y
    lda #0                                  ; and clear the Fac for the end of file
    sta Fac,Y
    inx
    iny
    cpy #TYPE_NAME_LENGTH
    bcc TypeName
    bcs EndOfFile

;; Writes a type beyond <TypeNames> as `TYP=` and two hex digits, or `PRO=` from $E0, through <OtherTypeText> and
;; <ProDosTypeText>.
;; Also: FORNFILE (BB13)
OtherType:
    ldx #2
    lda EntryBuffer+FileEntry::FILE_TYPE    ; the low digit first
    and #$0F

;; Makes a hex digit.
;; Also: FRNLP2 (BB13)
HexDigit:
    ora #'0'
    cmp #'9'+1
    bcc StoreDigit
    adc #'A'-'9'-2                          ; A to F, with the carry set

;; Stores the digit in both texts.
;; Also: FRNLP1 (BB13)
StoreDigit:
    sta a:OtherTypeText+3,X                 ; into both texts
    sta a:ProDosTypeText+3,X
    dex
    beq CopyOtherType
    lda EntryBuffer+FileEntry::FILE_TYPE    ; then the high digit
    lsr
    lsr
    lsr
    lsr
    jmp HexDigit

;; Copies the text for the type.
;; Also: FRNFL (BB13)
CopyOtherType:
    lda EntryBuffer+FileEntry::FILE_TYPE
    cmp #PRODOS_TYPES                       ; ProDOS's types
    lda a:ProDosTypeText,Y
    bcs StoreTypeCharacter
    lda a:OtherTypeText,Y

;; Stores the text's next character.
;; Also: ISPRO (BB13)
StoreTypeCharacter:
    sta CatalogBuffer+TYPE_COLUMN,Y
    lda #0                                  ; and clear the Fac for the end of file
    sta Fac,Y
    iny
    cpy #TYPE_NAME_LENGTH
    bcc CopyOtherType

;; Writes the end of file, as a long integer through <LongInteger::FormatFac>.
;; Also: NOWEOF (BB13)
EndOfFile:
    lda EntryBuffer+FileEntry::END_OF_FILE  ; the end of file, as a long integer
    sta Fac+7
    lda EntryBuffer+FileEntry::END_OF_FILE+1
    sta Fac+6
    lda EntryBuffer+FileEntry::END_OF_FILE+2
    sta Fac+5
    jsr LongInteger::FormatFac
    ldy #0

;; Copies the end of file's next digit, and its 0.
;; Also: OEOF (BB13)
CopyEndOfFile:
    lda LongText,Y
    sta CatalogBuffer+END_OF_FILE_COLUMN,Y
    beq Blocks
    iny
    bne CopyEndOfFile

;; Writes the blocks used, right-aligned in five columns with zeros to the left.
;; Also: NMREOF (BB13)
Blocks:
    ldy EntryBuffer+FileEntry::BLOCKS_USED  ; the blocks used
    lda EntryBuffer+FileEntry::BLOCKS_USED+1
    jsr ReturnSignedWord
    jsr Float::FormatFac
    ldy #$FF

;; Finds the last digit.
;; Also: CNTLN (BB13)
FindLastDigit:
    iny
    lda NumberBuffer+1,Y
    bne FindLastDigit
    ldx #BLOCKS_DIGITS

;; Copies the digits, from the last.
;; Also: MVBCNT (BB13)
CopyBlocks:
    lda NumberBuffer,Y
    sta CatalogBuffer+BLOCKS_COLUMN-1,X
    dex
    dey
    bpl CopyBlocks
    lda #'0'                                ; zeros to the left

;; Pads the columns to the left with zeros.
;; Also: ZBC (BB13)
PadZeros:
    dex
    bmi Dates
    sta CatalogBuffer+BLOCKS_COLUMN,X
    bpl PadZeros

;; Writes the dates and times.
;; Also: CMP3 (BB13)
Dates:
    lda EntryBuffer+FileEntry::MODIFIED_DATE+1
    ldx EntryBuffer+FileEntry::MODIFIED_DATE
    ldy #MODIFIED_DATE_COLUMN
    jsr WriteDate
    lda EntryBuffer+FileEntry::CREATED_DATE+1
    ldx EntryBuffer+FileEntry::CREATED_DATE
    ldy #CREATED_DATE_COLUMN
    jsr WriteDate
    lda EntryBuffer+FileEntry::MODIFIED_TIME+1
    ldx EntryBuffer+FileEntry::MODIFIED_TIME
    ldy #MODIFIED_TIME_COLUMN
    jsr WriteTime
    lda EntryBuffer+FileEntry::CREATED_TIME+1
    ldx EntryBuffer+FileEntry::CREATED_TIME
    ldy #CREATED_TIME_COLUMN
    jsr WriteTime
    clc
    rts
.endproc

;; Makes a volume directory's summary line: its blocks free, used and in total.
;;
;; A subdirectory, with no total in its control block, has no summary: the stage moves on twice and the catalog is
;; done.
;; In: X = the catalog's control block index, from <FileControlBlockIndex>
;; Out: carry = clear for the summary, set for none
;; See: <Prepare>, <WriteNumber>
;; Also: CEND (BB13)
.proc SummaryLine
;; The column of the blocks free.
FREE_COLUMN = 14

;; The column of the blocks used.
USED_COLUMN = 33

;; The column of the total.
TOTAL_COLUMN = 53

    lda FileControlBlocks+FileControlBlock::RECORD_LENGTH,X ; a total, for a volume directory?
    ora FileControlBlocks+FileControlBlock::RECORD_LENGTH+1,X
    beq NoSummary
    ldy #SUMMARY_LENGTH

;; Copies the summary's words, from their end.
;; Also: CEN2 (BB13)
CopyWords:
    lda a:Summary-1,Y
    sta CatalogBuffer,Y
    dey
    bne CopyWords
    lda FileControlBlocks+FileControlBlock::RECORD_LENGTH,X ; the total
    tay
    lda FileControlBlocks+FileControlBlock::RECORD_LENGTH+1,X
    ldx #TOTAL_COLUMN
    jsr WriteNumber
    ldx FileControlBlockIndex
    lda FileControlBlocks+FileControlBlock::BLOCKS_USED,X ; the blocks used
    tay
    lda FileControlBlocks+FileControlBlock::BLOCKS_USED+1,X
    ldx #USED_COLUMN
    jsr WriteNumber
    ldx FileControlBlockIndex
    lda FileControlBlocks+FileControlBlock::RECORD_LENGTH,X ; the blocks free: the total less those used
    sec
    sbc FileControlBlocks+FileControlBlock::BLOCKS_USED,X
    tay
    lda FileControlBlocks+FileControlBlock::RECORD_LENGTH+1,X
    sbc FileControlBlocks+FileControlBlock::BLOCKS_USED+1,X
    ldx #FREE_COLUMN
    jsr WriteNumber
    ldx FileControlBlockIndex
    dec FileControlBlocks+FileControlBlock::FLAGS,X ; cancels the next INC: one stage on, not two

;; Moves the stage on, twice without a summary.
;; Also: CEND2 (BB13)
NoSummary:
    inc FileControlBlocks+FileControlBlock::FLAGS,X
    jmp BlankLine
.endproc

;; The text for a SOS file type beyond <TypeNames>; <FileLine::OtherType> writes its two hex digits in for each such
;; file.
;; Also: FRNTYP (BB13)
OtherTypeText:
    .byte "TYP=  "

;; The text for a ProDOS file type, $E0 and up; <FileLine::OtherType> writes its two hex digits in for each such file.
;; Also: PROTYP (BB13)
ProDosTypeText:
    .byte "PRO=  "

;; The six-character name of each SOS file type, 0 to 21.
;; Also: TYPTB (BB13)
TypeNames:
    .byte "UNKNWN"
    .byte "BAD   "
    .byte "PASCOD"
    .byte "PASTXT"
    .byte "TEXT  "
    .byte "PASDTA"
    .byte "BINARY"
    .byte "FONT  "
    .byte "FOTO  "
    .byte "BASIC "
    .byte "DATA  "
    .byte "WPTEXT"
    .byte "SYSTEM"
    .byte "RESERV"
    .byte "RESERV"
    .byte "CAT   "
    .byte "RPSDAT"
    .byte "RPSIDX"
    .byte "AFDISC"
    .byte "ASMOD "
    .byte "AFRPT "
    .byte "SCNLIB"
.assert * - TypeNames = TYPE_NAME_COUNT * TYPE_NAME_LENGTH, "A name of TYPE_NAME_LENGTH for each type."

; ---------------------------------------------------------------------------------------------------------------------
; Reading the directory
; ---------------------------------------------------------------------------------------------------------------------

;; Reads the directory's next file entry, <FileEntry>, into <EntryBuffer>.
;;
;; At the end of a 512-byte block, after its four link bytes and 13 entries, the offset's low byte is
;; <BLOCK_LAST_BYTE>; the block's last byte and the next block's links are read first. The code counts on 39-byte
;; entries, 13 to a block, rather than taking the header's entry length and count.
;; In: FileControlBlockIndex = the catalog's control block
;; Out: carry = set at the end of the directory
;; See: <ReadBytes>
;; Also: RDCAT (BB13)
.proc ReadEntry
    ldy FileControlBlockIndex
    lda FileControlBlocks+FileControlBlock::REFERENCE_NUMBER,Y
    sta SosCalls::Reference
    lda FileControlBlocks+FileControlBlock::BUFFER_OFFSET,Y
    cmp #BLOCK_LAST_BYTE                    ; the end of a block?
    bne ReadFull
    lda #1+BLOCK_LINKS                      ; its last byte and the next block's links
    jsr ReadBytes
    bcs ReadBytes::EndOfDirectory

;; Reads the entry.
;; Also: RDCAT3 (BB13)
ReadFull:
    lda #.sizeof(FileEntry)
    ; Falls into ReadBytes.
.endproc

;; Reads A bytes of the directory into <EntryBuffer>, and moves the control block's offset past them.
;; In: A = the count, FileControlBlockIndex = the catalog's control block, SosCalls::Reference = the directory's
;;   reference number
;; Out: carry = set at the end of the directory
;; Errors: any other error closes the directory and ends the statement
;; Entry:
;;   EndOfDirectory = returns with carry set; <ReadEntry> branches here
;; See: <Files::AdvanceOffset>
;; Also: RDCAT2 (BB13)
.proc ReadBytes
    sta SosCalls::Request
    sta DataItemLength
    lda #0
    sta SosCalls::Request+1
    lda #<(EntryBuffer)
    sta SosCalls::Buffer
    lda #>(EntryBuffer)
    sta SosCalls::Buffer+1
    ldy #SosCalls::CALL_READ
    jsr SosCalls::SetUp
    jsr SosCalls::Call
    beq Read
    cmp #SOS_ERROR_END_OF_FILE
    bne ToCloseWithError

;; Returns with carry set: the end of the directory.
;; Also: NMCAT (BB13)
EndOfDirectory:
    sec
    rts

;; Moves the offset past the bytes read.
;; Also: OKCAT (BB13)
Read:
    jmp Files::AdvanceOffset

;; Closes the directory and ends the statement with the error.
;; Also: CTR2 (BB13)
ToCloseWithError:
    jmp Files::CloseWithError
.endproc

; ---------------------------------------------------------------------------------------------------------------------
; Dates, times and numbers
; ---------------------------------------------------------------------------------------------------------------------

;; Writes a SOS date into <CatalogBuffer> as MM/DD/YY, from column Y.
;;
;; The date's 16 bits are, from the top, 7 of year, 4 of month and 5 of day. The first three bytes of <EntryBuffer>
;; serve as scratch.
;; In: A = the date's high byte, X = its low byte, Y = the column
;; Uses: A, X, Y
;; See: <WriteTwoDigits>
;; Also: GENDATE (BB13)
.proc WriteDate
;; The date's low byte, while it is taken apart.
DateLow = EntryBuffer

;; The date's high byte.
DateHigh = EntryBuffer+1

;; The bits of the date's low byte that hold the day.
DAY_MASK = $1F

;; Where the month goes, from the column.
MONTH_OFFSET = 0

;; Where the day goes, after the month and a slash.
DAY_OFFSET = 3

;; Where the year goes, after the day and a slash.
YEAR_OFFSET = 6

    sta DateHigh
    stx DateLow
    sty DigitColumn
    txa                                     ; the day
    and #DAY_MASK
    tay
    lda #DAY_OFFSET
    jsr WriteTwoDigits
    lda DateHigh                            ; the year
    lsr
    ror DateLow                             ; the month's top bit into the low byte
    tay
    lda #YEAR_OFFSET
    jsr WriteTwoDigits
    lda DateLow                             ; the month
    lsr
    lsr
    lsr
    lsr
    tay
    lda #MONTH_OFFSET
    jsr WriteTwoDigits
    lda #'/'
    sta CatalogBuffer+DAY_OFFSET-1,Y        ; WriteTwoDigits left Y at the column
    sta CatalogBuffer+YEAR_OFFSET-1,Y
    rts
.endproc

;; Writes a number from 0 to 99 as two digits into <CatalogBuffer>, A columns after the column in <DigitColumn>.
;;
;; A one-digit number gets a leading 0.
;; In: A = the offset, Y = the number
;; Out: Y = the column written
;; Uses: A, X
;; Also: G2DIGS (BB13)
.proc WriteTwoDigits
    pha
    jsr ReturnByte
    jsr Float::FormatFac
    pla
    clc
    adc DigitColumn
    tay
    lda NumberBuffer                        ; the first digit in both places
    sta CatalogBuffer,Y
    sta CatalogBuffer+1,Y
    lda NumberBuffer+1
    beq LeadingZero                         ; one digit: a 0 before it
    sta CatalogBuffer+1,Y
    rts

;; Puts a 0 before a one-digit number.
;; Also: AZERH (BB13)
LeadingZero:
    lda #'0'
    sta CatalogBuffer,Y
    rts
.endproc

;; Writes a SOS time into <CatalogBuffer> as HH:MM, from column Y.
;; In: A = the hour, X = the minute, Y = the column
;; Uses: A, X, Y
;; See: <WriteTwoDigits>
;; Also: GENTIME (BB13)
.proc WriteTime
;; The minute, while the hour is written.
Minute = EntryBuffer

;; Where the hour goes, from the column.
HOUR_OFFSET = 0

;; Where the minute goes, after the hour and a colon.
MINUTE_OFFSET = 3

    stx Minute
    sty DigitColumn
    tay
    lda #HOUR_OFFSET
    jsr WriteTwoDigits
    lda #':'
    sta CatalogBuffer+MINUTE_OFFSET-1,Y
    ldy Minute
    lda #MINUTE_OFFSET
    jmp WriteTwoDigits
.endproc

;; Writes a 16-bit number into <CatalogBuffer>, from column X.
;; In: A = the high byte, Y = the low byte, X = the column
;; Out: X = the column after it
;; Uses: A, Y
;; Also: DONUM (BB13)
.proc WriteNumber
    stx SavedX
    jsr ReturnSignedWord
    jsr Float::FormatFac
    ldy #0
    ldx SavedX

;; Copies the next digit.
;; Also: DONUM2 (BB13)
CopyDigit:
    lda NumberBuffer,Y
    beq Done
    sta CatalogBuffer,X
    iny
    inx
    bne CopyDigit                           ; always

;; Returns.
;; Also: DONUMR (BB13)
Done:
    rts
.endproc

;; The summary line's words; <SummaryLine> puts the numbers after them.
;; Also: SMMSG (BB13)
Summary:
    .byte "BLOCKS FREE:       BLOCKS USED:       TOTAL BLOCKS:      "

;; The length of <Summary>.
;; Also: SUMML (BB13)
SUMMARY_LENGTH = *-Summary

.endscope

; ---------------------------------------------------------------------------------------------------------------------
; Routines for invokable modules
; ---------------------------------------------------------------------------------------------------------------------

;; What an address in BASIC's banked memory, $2000-$9FFF, is above the same byte's address as a pointer through a
;; bank pair, as BASIC gives modules its data.
BANK_PAIR_OFFSET = $2000

;; One entry of <ModuleRoutines>: a routine's address, or a table's, at its number.
;; Parameters:
;;   number = the number modules call it by
;;   address = the routine or the table
.macro ModuleRoutine number, address
    .assert * - ModuleRoutines = 2 * number, "Each routine's entry is at twice its number in ModuleRoutines."
    .word address
.endmacro

;; The routines BASIC lends invokable modules and `PERFORM`, by number: <Modules::CallBasic> calls entry n for routine
;; n.
;;
;; Modules use the numbers, so no entry may move. Three entries are data rather than routines, the two keyword
;; lists, <ReservedWords> and <ExtendedReservedWords>, and <NumberBuffer>, given <BANK_PAIR_OFFSET> lower than BASIC's
;; own addresses. The last entry is the table's own address. The table must end where <Modules::CallBasic> starts, as
;; <Modules::CallBasic> takes that for the table's end and refuses a number past it.
;; Also: JMPRTAB (BB13)
ModuleRoutines:
    ModuleRoutine 0, EvaluateSubexpression
    ModuleRoutine 1, FindVariable
    ModuleRoutine 2, OpenGap
    ModuleRoutine 3, CloseGap
    ModuleRoutine 4, MoveRangeUp::Unchecked
    ModuleRoutine 5, RejectDirectMode
    ModuleRoutine 6, ReadLineNumber
    ModuleRoutine 7, Statements::GoTo::ToLineNumber
    ModuleRoutine 8, ConvertToAddress
    ModuleRoutine 9, FindLine::FromLine
    ModuleRoutine 10, FindLine
    ModuleRoutine 11, Console::Initialize
    ModuleRoutine 12, ReservedWords-BANK_PAIR_OFFSET
    ModuleRoutine 13, Strings::FindFromDescriptor
    ModuleRoutine 14, ReportError
    ModuleRoutine 15, ReportSosError
    ModuleRoutine 16, Segments::Shrink
    ModuleRoutine 17, Segments::Grow
    ModuleRoutine 18, Strings::ReleaseFac
    ModuleRoutine 19, Strings::FreeSpaceIfReleased
    ModuleRoutine 20, Strings::FreeFacTemporary
    ModuleRoutine 21, Strings::FreeSpace
    ModuleRoutine 22, Files::OpenOfType
    ModuleRoutine 23, SosCalls::Call
    ModuleRoutine 24, Files::CloseAll
    ModuleRoutine 25, ReturnSignedWord
    ModuleRoutine 26, FacToNonnegativeInteger
    ModuleRoutine 27, Float::ReadNumber
    ModuleRoutine 28, NextStatement::SavePlace
    ModuleRoutine 29, FindVariable::ValidFirst
    ModuleRoutine 30, Variables::SimpleVariableOffset
    ModuleRoutine 31, Variables::VariableOffset::ArrayElement
    ModuleRoutine 32, FindStatementEnd
    ModuleRoutine 33, Strings::CopyText
    ModuleRoutine 34, AssignString
    ModuleRoutine 35, AssignFac
    ModuleRoutine 36, Float::FormatFac
    ModuleRoutine 37, ExecuteStatement::StatementReturn
    ModuleRoutine 38, Modules::CallModule
    ModuleRoutine 39, Functions::Int
    ModuleRoutine 40, NumberBuffer-BANK_PAIR_OFFSET
    ModuleRoutine 41, ExtendedReservedWords-BANK_PAIR_OFFSET
    ModuleRoutine 42, SosCalls::SetUp
    ModuleRoutine 43, SosCalls::MakeFileCall
    ModuleRoutine 44, Functions::ConvString
    ModuleRoutine 45, ModuleRoutines
.assert * = Modules::CallBasic, "ModuleRoutines must end where SWCHGO starts: SWCHGO takes that as the table's end."
