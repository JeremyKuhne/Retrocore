; retrocore: style=strict
;; Restart and <Initialize>, which load SYSTEM.PASCAL and start the p-machine. Restart copies itself and <Initialize> to
;; <COPY_ADDRESS> and runs <Initialize> there, since <Initialize> reads SYSTEM.PASCAL's segment 0 over them.

; The copy.

;; Where <Restart> copies itself and <Initialize> to, and <Initialize> runs.
COPY_ADDRESS = $6800

;; The 256-byte pages <Restart> copies.
COPY_PAGES = 4

; Units.

; SYSCOM.

;; The bytes at <SyscomExtra>, just after SYSCOM, that <Initialize> clears with it.
SYSCOM_EXTRA_SIZE = $20

; Reading SYSTEM.PASCAL.

;; Where <Initialize> reads the boot unit's directory, and then SYSTEM.PASCAL's segment dictionary.
BOOT_BUFFER = $6000

;; The directory's first block.
DIRECTORY_BLOCK = 2

;; The bytes of directory <Initialize> reads: 4 blocks.
DIRECTORY_SIZE = $0800

;; The size of a directory entry. The first is the volume's own, and the files' follow it.
DIRECTORY_ENTRY_SIZE = 26

;; Where a directory entry keeps its first block.
DIRECTORY_FIRST_BLOCK = 0

;; Where a directory entry keeps its name, as a Pascal string.
DIRECTORY_NAME = 6

;; The directory entries <Initialize> checks for SYSTEM.PASCAL: the volume's own and the first 76 files'.
DIRECTORY_ENTRIES_CHECKED = 77

;; The bytes of SYSTEM.PASCAL's first block, its segment dictionary, that <Initialize> reads: its segments' blocks and
;; sizes come first.
DICTIONARY_READ_SIZE = $0100

;; The segments a segment dictionary describes, 0-15.
DICTIONARY_SEGMENTS = 16

;; The size of a dictionary entry: the segment's first block, counted from the file's start, then its size in bytes.
DICTIONARY_ENTRY_SIZE = 4

;; Where a <SegmentTable> entry keeps the segment's first block.
SEGMENT_TABLE_BLOCK = 2

;; What ends <NoSystemMessage>.
MESSAGE_END = '#'

; Starting the system.

;; The segment <Initialize> reads first, just below <MemoryTop> and outside <SegmentUses>'s counts: SYSTEM.PASCAL's
;; segment 15, which its dictionary leaves unnamed.
UNNAMED_SEGMENT = 15

;; SYSTEM.PASCAL's segment 0, `PASCALSY`, whose procedure 1 runs the system.
KERNEL_SEGMENT = 0

;; Where <Initialize> loads segment 0 down from: just below <AttachedDrivers>, over <FreeStorage> and the boot code.
SEGMENT_0_TOP = $FE7C

;; The procedure of segment 0 that <Initialize> calls.
SYSTEM_PROCEDURE = 1

;; Where the heap starts: above text page 2, which the 80-column screen keeps its other columns in.
HEAP_START = $0C04

;; Where the heap starts when slot 3's card is the console, which does not need text page 2.
HEAP_START_CARD = $0804

;; The size of <CopiedTable>.
COPIED_TABLE_SIZE = 42

;; A Pascal string: its length, then its characters.
;; Parameters:
;;   text = the string
.macro PascalString text
    .byte .strlen(text), text
.endmacro

;; Addresses <Initialize> reads, a word each. <UCLEAR at UnitIo::CspUCLEAR> reads <BootSyscom> too, as BootAddresses+4.
BootAddresses:

;; <MemoryTop>'s address, where <KP> and <MP> start.
BootMemoryTop:
    .word MemoryTop

;; <SegmentTable>'s address.
BootSegmentTable:
    .word SegmentTable

;; SYSCOM's address.
BootSyscom:
    .word Syscom

;; <CspTable>'s address, whose high byte goes in <CspDispatch>'s JMP.
BootCspTable:
    .word CspTable

;; <OpcodeTable>'s address, whose high byte goes in <Dispatch>'s JMP.
BootOpcodeTable:
    .word OpcodeTable

;; <OpXIT>'s address, which <Initialize> puts in <ResetHandler>, so that RESET leaves the system.
BootResetHandler:
    .word OpXIT

;; The reset vector as it was before <Initialize>'s NoSystemFile changed it.
SavedResetVector:
    .res 2

;; Not 0 once <Initialize>'s NoSystemFile has pointed the reset vector at <Boot>.
ResetPatched:
    .res 1

;; The character of <NoSystemMessage> that <Initialize>'s NoSystemFile is writing.
MessageIndex:
    .res 1

;; The file the system boots.
SystemFileName:
    PascalString "SYSTEM.PASCAL"

;; What <Initialize>'s NoSystemFile writes when the boot unit has no SYSTEM.PASCAL, up to its <MESSAGE_END>.
NoSystemMessage:
    .byte ASCII_CR
    .byte "Insert boot disk with SYSTEM.PASCAL", ASCII_CR
    .byte ASCII_LF, "on it, then press RESET", MESSAGE_END

;; Unit 1's entry in <UnitWriters>, which <Initialize> puts in <WritersPointer>.
BootWritersPointer:
    .word UnitWriters+2

;; Unit 1's entry in <UnitReaders>, which <Initialize> puts in <ReadersPointer>.
BootReadersPointer:
    .word UnitReaders+2

;; Where <Restart> copies from: <Restart> itself.
RestartAddress:
    .word Restart

;; Copies itself and <Initialize>, <COPY_PAGES> pages, to <COPY_ADDRESS>, and runs <Initialize> there.
.proc Restart

;; Where the copy reads from. Zero page's first bytes have no other use at this point.
From = $00

;; Where the copy writes to.
To = $02

    ; Copy from here to COPY_ADDRESS, a page at a time.
    .assert <COPY_ADDRESS = 0, "Restart's TAX and TAY take the 0 of COPY_ADDRESS's low byte."
    lda RestartAddress
    sta From
    lda RestartAddress+1
    sta From+1
    lda #>COPY_ADDRESS
    sta To+1
    lda #<COPY_ADDRESS
    sta To
    tax
    tay
CopyByte:
    lda (From),y
    sta (To),y
    iny
    bne CopyByte
    inc From+1
    inc To+1
    inx
    cpx #COPY_PAGES
    bne CopyByte

    ; Run the copy.
    jmp Initialize
.endproc

;; Initialize's bytes in the language card, which <Restart> copies, with <Restart> before them, to <COPY_ADDRESS>. From
;; here on the code is assembled for the copy's addresses.
InitializeImage:
    .logicalorg $6827
    .assert * = COPY_ADDRESS + InitializeImage - Restart, "Initialize is assembled where Restart copies it."

;; Sets up the BIOS's and the p-machine's state, finds SYSTEM.PASCAL on the boot unit, reads its segments' places into
;; <SegmentTable>, loads segments 15 and 0, and runs segment 0's procedure 1. Runs at <COPY_ADDRESS> + $27, and does not
;; return.
.proc Initialize

;; The directory entry being checked: the buffer's start, then the entry's name, then the entry's start.
Entry = Result

;; SYSTEM.PASCAL's first block, from its directory entry.
FirstBlock = Buffer

;; The <SegmentTable> entry being filled.
TableEntry = Pointer

;; The segment dictionary entry being read.
DictionaryEntry = Pointer2

;; <KP> below segment 15, kept while segment 0 is loaded elsewhere.
SavedKp = Comparison

;; Where <CopiedTableImage>'s bytes are while <Initialize> runs: in the language card, where <Restart> copied them from.
CopiedTableSource = CopiedTableImage - Initialize + InitializeImage

;; <UnitTable>'s entry for the boot unit.
BootUnitEntry = UnitTable + UNIT_ENTRY_SIZE * UNIT_BOOT_DISK

    ; Empty the 6502's stack, and leave decimal mode.
    ldx #$FF
    txs
    cld

    ; Give the console driver ExecutionError::Interrupted for the break key, and have RESET leave the system.
    lda BreakHandler
    sta BreakAddress
    lda BreakHandler+1
    sta BreakAddress+1
    lda BootResetHandler
    sta ResetHandler
    lda BootResetHandler+1
    sta ResetHandler+1

    ; Record SYSCOM's address, and BootValues, which nothing in SYSTEM.APPLE reads.
    lda BootSyscom
    sta SyscomAddress
    lda BootSyscom+1
    sta SyscomAddress+1
    lda #2
    sta BootValues
    lda #1
    sta BootValues+1

    ; Point WritersPointer and ReadersPointer at unit 1's entries.
    lda BootWritersPointer
    sta WritersPointer
    lda BootWritersPointer+1
    sta WritersPointer+1
    lda BootReadersPointer
    sta ReadersPointer
    lda BootReadersPointer+1
    sta ReadersPointer+1

    ; Copy CopiedTableImage to CopiedTable, and record where it is.
    ldy #COPIED_TABLE_SIZE - 1
CopyTable:
    lda CopiedTableSource,y
    sta CopiedTable,y
    dey
    bpl CopyTable
    lda #<CopiedTable
    sta CopiedTablePointer
    lda #>CopiedTable
    sta CopiedTablePointer+1

    ; Initialize the boot unit: with its driver, when its UnitTable entry is one.
    lda BootUnitEntry+1
    beq InitializeDisk
    ldx #REQUEST_CLEAR
    lda #UNIT_BOOT_DISK
    ldy #UNIT_BOOT_DISK * UNIT_ENTRY_SIZE
    jsr BiosUnitDriver

    ; CLC leaves carry clear, so this always branches.
    clc
    bcc ClearSyscom

;; The bytes <Initialize> copies to <CopiedTable>, which it reads where they are in the language card,
;; <CopiedTableSource>.
CopiedTableImage:
    .byte $C0, $D2, $5C, $D5, $7A, $D3, $0F, $D2, $20, $B3, $B3, $A5, $46, $85, $4C, $B3
    .byte $B3, $4C, $B3, $B3, $0E, $49, $AB, $45, $CD, $48, $4A, $68, $2A, $C9, $04, $2A
    .byte $85, $46, $60, $A4, $46, $24, $00, $4C, $10, $D3
    .assert * - CopiedTableImage = COPIED_TABLE_SIZE, "CopiedTableImage is COPIED_TABLE_SIZE bytes."

    ; A Disk II drive. DiskInit only checks that the drive's slot holds a Disk II, and Initialize ignores what it
    ; finds. It passes UNIT_BOOT_DISK, not the unit's drive number, so slot 4 is the one checked.
InitializeDisk:
    lda #UNIT_BOOT_DISK
    jsr BiosDiskInit

    ; Clear SYSCOM, and the SYSCOM_EXTRA_SIZE bytes after it.
ClearSyscom:
    ldx #0
    lda #0
ClearSyscomByte:
    sta Syscom,x
    inx
    bne ClearSyscomByte
ClearExtraByte:
    sta SyscomExtra,x
    inx
    cpx #SYSCOM_EXTRA_SIZE
    bne ClearExtraByte

    ; Read the boot unit's directory into BOOT_BUFFER. Push the read's arguments, the last first: the control word
    ; and the drive's high byte, 0.
ReadDirectory:
    lda #0
    pha
    pha
    pha

    ; The drive: the unit, for its driver, or else its drive number.
    lda BootUnitEntry+1
    beq DirectoryDriveNumber
    lda #UNIT_BOOT_DISK

    ; UNIT_BOOT_DISK is positive, so this always branches.
    bpl PushDirectoryDrive
DirectoryDriveNumber:
    lda BootUnitEntry
PushDirectoryDrive:
    pha

    ; The buffer, which Entry starts at.
    lda #>BOOT_BUFFER
    pha
    sta Entry+1
    lda #<BOOT_BUFFER
    pha
    sta Entry

    ; The byte count, and the block.
    .assert <DIRECTORY_SIZE = 0 && >DIRECTORY_BLOCK = 0, "One 0 is the count's low byte and the block's high byte."
    lda #>DIRECTORY_SIZE
    pha
    lda #0
    pha
    pha
    lda #<DIRECTORY_BLOCK
    pha

    ; Read it, with the unit's driver or DiskRead.
    lda BootUnitEntry+1
    beq ReadDirectoryDisk
    ldx #REQUEST_READ
    lda #UNIT_BOOT_DISK
    ldy #UNIT_BOOT_DISK * UNIT_ENTRY_SIZE
    jsr BiosUnitDriver

    ; CLC leaves carry clear, so this always branches.
    clc
    bcc FindSystemFile
ReadDirectoryDisk:
    jsr BiosDiskRead

    ; Look through the directory for SystemFileName, from the volume's own entry: point Entry at its name.
FindSystemFile:
    ldx #DIRECTORY_ENTRIES_CHECKED + 1
    clc
    lda Entry
    adc #DIRECTORY_NAME
    sta Entry
    bcc CountEntry
    inc Entry+1

    ; Step to the next entry's name.
NextEntry:
    clc
    lda Entry
    adc #DIRECTORY_ENTRY_SIZE
    sta Entry
    bcc CountEntry
    inc Entry+1

    ; Compare its name, unless every entry has been checked.
CountEntry:
    dex
    bne CompareName

    ; There is no SYSTEM.PASCAL. Initialize the console as UCLEAR does: clear units 1 and 2's DLE states, and give
    ; ConsoleInit the break key's address and SYSCOM's.
NoSystemFile:
    lda #0
    sta DleFlags+1
    sta DleFlags+2
    lda BreakHandler+1
    pha
    lda BreakHandler
    pha
    lda BootSyscom+1
    pha
    lda BootSyscom
    pha
    jsr BiosConsoleInit

    ; Write NoSystemMessage, up to its MESSAGE_END.
    ldy #0
    sty MessageIndex
NextCharacter:
    lda NoSystemMessage,y
    cmp #MESSAGE_END
    bne WriteCharacter

    ; At its end, wait for RESET. Unless it is done already, first point the reset vector at Boot, keeping the old
    ; one, so that RESET boots again.
    lda ResetPatched
WaitPatched:
    bne WaitPatched
    lda ResetVector
    sta SavedResetVector
    lda ResetVector+1
    sta SavedResetVector+1
    lda BootVector
    sta ResetVector
    lda BootVector+1
    sta ResetVector+1
    inc ResetPatched
WaitForReset:
    bne WaitForReset

WriteCharacter:
    jsr BiosConsoleWrite
    inc MessageIndex
    ldy MessageIndex

    ; CLC leaves carry clear, so this always branches.
    clc
    bcc NextCharacter

    ; Compare the entry's name, its length byte included, with SystemFileName.
CompareName:
    ldy SystemFileName
CompareNameByte:
    lda (Entry),y
    cmp SystemFileName,y
    bne NextEntry
    dey
    bpl CompareNameByte

    ; Found. Read SYSTEM.PASCAL's first block, its segment dictionary, into BOOT_BUFFER: point Entry back at the
    ; entry's start, and take the file's first block.
ReadSegmentDictionary:
    lda Entry
    sec
    sbc #DIRECTORY_NAME
    sta Entry
    bcs TakeFirstBlock
    dec Entry+1
TakeFirstBlock:
    ldy #DIRECTORY_FIRST_BLOCK
    lda (Entry),y
    sta FirstBlock
    iny
    lda (Entry),y
    sta FirstBlock+1

    ; Push the read's arguments, the last first: the control word and the drive's high byte, 0.
    lda #0
    pha
    pha
    pha

    ; The drive: the unit, for its driver, or else its drive number.
    lda BootUnitEntry+1
    beq DictionaryDriveNumber
    lda #UNIT_BOOT_DISK

    ; UNIT_BOOT_DISK is positive, so this always branches.
    bpl PushDictionaryDrive
DictionaryDriveNumber:
    lda BootUnitEntry
PushDictionaryDrive:
    pha

    ; The buffer, the byte count, and the block.
    lda #>BOOT_BUFFER
    pha
    lda #<BOOT_BUFFER
    pha
    lda #>DICTIONARY_READ_SIZE
    pha
    lda #<DICTIONARY_READ_SIZE
    pha
    lda FirstBlock+1
    pha
    lda FirstBlock
    pha

    ; Read it, with the unit's driver or DiskRead.
    lda BootUnitEntry+1
    beq ReadDictionaryDisk
    ldx #REQUEST_READ
    lda #UNIT_BOOT_DISK
    ldy #UNIT_BOOT_DISK * UNIT_ENTRY_SIZE
    jsr BiosUnitDriver

    ; CLC leaves carry clear, so this always branches.
    clc
    bcc BuildSegmentTable
ReadDictionaryDisk:
    jsr BiosDiskRead

    ; Clear SegmentUses: no segment is in use.
BuildSegmentTable:
    ldx #0
    lda #0
ClearUses:
    sta SegmentUses,x
    inx
    cpx #SegmentKp - SegmentUses
    bne ClearUses

    ; Fill SegmentTable's first DICTIONARY_SEGMENTS entries from the dictionary.
    lda BootSegmentTable
    sta TableEntry
    lda BootSegmentTable+1
    sta TableEntry+1
    lda #>BOOT_BUFFER
    sta DictionaryEntry+1
    lda #<BOOT_BUFFER
    sta DictionaryEntry
    ldx #DICTIONARY_SEGMENTS

    ; The segment's unit, UNIT_BOOT_DISK.
NextSegment:
    ldy #0
    lda #<UNIT_BOOT_DISK
    sta (TableEntry),y
    iny
    lda #>UNIT_BOOT_DISK
    sta (TableEntry),y
    lda TableEntry
    clc
    adc #SEGMENT_TABLE_BLOCK
    sta TableEntry
    bcc CopyBlockAndSize
    inc TableEntry+1

    ; Its first block, the file's first block plus the dictionary's, and its size, as the dictionary gives it.
CopyBlockAndSize:
    ldy #0
    clc
    lda (DictionaryEntry),y
    adc FirstBlock
    sta (TableEntry),y
    iny
    lda (DictionaryEntry),y
    adc FirstBlock+1
    sta (TableEntry),y
    iny
    lda (DictionaryEntry),y
    sta (TableEntry),y
    iny
    lda (DictionaryEntry),y
    sta (TableEntry),y

    ; Step to the next entries.
    lda TableEntry
    clc
    adc #SEGMENT_TABLE_ENTRY_SIZE - SEGMENT_TABLE_BLOCK
    sta TableEntry
    bcc StepDictionary
    inc TableEntry+1
StepDictionary:
    lda DictionaryEntry
    clc
    adc #DICTIONARY_ENTRY_SIZE
    sta DictionaryEntry
    bcc CountSegment
    inc DictionaryEntry+1
CountSegment:
    dex
    bne NextSegment

    ; Start KP and MP at MemoryTop, and record it in SYSCOM.
StartSystem:
    lda BootMemoryTop
    sta KP
    sta MP
    sta SysMemoryTop
    lda BootMemoryTop+1
    sta KP+1
    sta MP+1
    sta SysMemoryTop+1

    ; Read segment UNNAMED_SEGMENT in below KP, NP's high byte 0 leaving ReadSegment room for it.
    lda #0
    sta NP+1
    lda #UNNAMED_SEGMENT
    jsr ReadSegment

    ; Load segment 0 down from SEGMENT_0_TOP, keeping KP below segment 15. LoadSegment leaves SegmentNumber at 0.
    lda KP
    sta SavedKp
    lda KP+1
    sta SavedKp+1
    lda #>SEGMENT_0_TOP
    sta KP+1
    lda #<SEGMENT_0_TOP
    sta KP
    lda #KERNEL_SEGMENT
    jsr LoadSegment
    lda SavedKp
    sta KP
    lda SavedKp+1
    sta KP+1

    ; Call its procedure 1 as CXP does: FindProcedureIn builds its frame below KP, and sets MP, JTAB, SEG and IPC.
    lda #SYSTEM_PROCEDURE
    sta ProcedureNumber
    jsr FindProcedureIn

    ; Make the frame the outer block's: BASE, and its own static and dynamic links.
    .assert MSCW_DYNAMIC_LINK = MSCW_STATIC_LINK + 2, "DEY steps from the dynamic link to the static link's high byte."
    ldy #MSCW_STATIC_LINK
    lda MP
    sta BASE
    sta (MP),y
    ldy #MSCW_DYNAMIC_LINK
    sta (MP),y
    lda MP+1
    sta BASE+1
    dey
    sta (MP),y
    ldy #MSCW_DYNAMIC_LINK + 1
    sta (MP),y

    ; Its first global, just after the frame: SYSCOM's address.
    ldy #MSCW_SIZE
    lda BootSyscom
    sta (MP),y
    iny
    lda BootSyscom+1
    sta (MP),y

    ; Start the heap at HEAP_START, or HEAP_START_CARD when slot 3's card is the console.
    .assert <HEAP_START = <HEAP_START_CARD, "The heap's two starts share their low byte."
    lda ConsoleCardFlag
    and #CONSOLE_CARD_READY
    beq NoConsoleCard
    lda #>HEAP_START_CARD
    sta NP+1

    ; The page is positive, so this always branches.
    bpl HeapLowByte
NoConsoleCard:
    lda #>HEAP_START
    sta NP+1
HeapLowByte:
    lda #<HEAP_START
    sta NP

    ; Set UnreadFlag, and clear every unit's DLE state.
    lda #1
    sta UnreadFlag
    ldx #0
    lda #0
ClearDleFlag:
    sta DleFlags,x
    inx
    cpx #UNIT_COUNT
    bne ClearDleFlag

    ; Write JMP (OpcodeTable) at Dispatch and JMP (CspTable) at CspDispatch. Fetch and OpCSP set the low bytes.
    lda #JMP_INDIRECT
    sta CspDispatch
    sta Dispatch
    lda BootOpcodeTable+1
    sta Dispatch+2
    lda BootCspTable+1
    sta CspDispatch+2

    ; Record the boot unit.
    lda #UNIT_BOOT_DISK
    sta SysBootUnit

    ; If NoSystemFile pointed the reset vector at Boot, put the old one back.
    lda ResetPatched
    beq RunSystem
    lda SavedResetVector
    sta ResetVector
    lda SavedResetVector+1
    sta ResetVector+1

    ; Run the system, from procedure 1's first p-code.
RunSystem:
    jmp Fetch::Next

.endproc

;; Never run or read: bytes an earlier build left at the end of the image.
InitTail:
    .res 9
    .byte $70, $25, $00, $00, $02, $00, $01, $01

    ; ReadDirectory's last instructions to ReadSegmentDictionary's first, as assembled with other addresses for
    ; BreakHandler and the BIOS's stubs.
    .byte $A0, $08, $20, $3C, $FF, $18, $90, $03, $20, $12, $FF, $A2, $4E, $18, $A5
    .byte $80, $69, $06, $85, $80, $90, $0D, $E6, $81, $18, $A5, $80, $69, $1A, $85, $80
    .byte $90, $02, $E6, $81, $CA, $D0, $53, $A9, $00, $85, $97, $85, $98, $AD, $AB, $EE
    .byte $48, $AD, $AA, $EE, $48, $AD, $18, $F2, $48, $AD, $17, $F2, $48, $20, $06, $FF
    .byte $A0, $00, $8C, $22, $F2, $B9, $31, $F2, $C9, $23, $D0, $22, $AD, $21, $F2, $D0
    .byte $FE, $AD, $FC, $FF, $8D, $1F, $F2, $AD, $FD, $FF, $8D, $20, $F2, $AD, $F8, $FF
    .byte $8D, $FC, $FF, $AD, $F9, $FF, $8D, $FD, $FF, $EE, $21, $F2, $D0, $FE, $20, $03
    .byte $FF, $EE, $22, $F2, $AC, $22, $F2, $18, $90, $CB, $AC, $23, $F2, $B1, $80, $D9
    .byte $23, $F2, $D0, $95, $88, $10, $F6, $A5, $80

    ; Two 16-byte records naming THISISIT, then spaces and zeros.
    .byte "THISISIT", $0B, $00, $01, $00, $00, $00, $00, $00
    .byte "THISISIT", $06, $00, $01, $00, $00, $00, $00, $00
    .byte "        "
    .res 77
    .assert * = COPY_ADDRESS + COPY_PAGES * 256, "Restart copies the image to its end."

    .logicalorg
