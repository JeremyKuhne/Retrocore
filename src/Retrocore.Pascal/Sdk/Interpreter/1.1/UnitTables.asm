; retrocore: style=strict
;; The language card's free storage, the attached drivers' JMPs, the unit table, and BIOS call 19's routine.

; The attached drivers.

;; The size of an <AttachedDrivers> entry, a JMP.
DRIVER_JUMP_SIZE = 3

; The unit table.

;; An <AttachedDrivers> entry: a JMP for an attached unit, to 0 until a driver is attached. <UnitIo::CheckUnit> takes a
;; JMP whose address's high byte is 0 as no driver.
;; Parameters:
;;   unit = the attached unit, 0-15; the entries go in order
.macro DriverJump unit
    .assert * = AttachedDrivers + DRIVER_JUMP_SIZE * unit, "AttachedDrivers's entries are in unit order."
    .byte JMP_ABSOLUTE
    .word 0
.endmacro

;; A <UnitTable> entry for a unit that is not there.
;; Parameters:
;;   unit = the unit; the entries go in order
.macro NoUnit unit
    .assert * = UnitTable + UNIT_ENTRY_SIZE * unit, "UnitTable's entries are in unit order."
    .word 0
.endmacro

;; A <UnitTable> entry for a character device.
;; Parameters:
;;   unit = the unit; the entries go in order
.macro CharacterUnit unit
    .assert * = UnitTable + UNIT_ENTRY_SIZE * unit, "UnitTable's entries are in unit order."
    .word CHARACTER_DEVICE
.endmacro

;; A <UnitTable> entry for a Disk II drive: its drive number, whose high byte is 0.
;; Parameters:
;;   unit = the unit; the entries go in order
;;   drive = the drive number <DiskRead>, <DiskWrite> and <DiskInit> take: the slot's <DriveSlots> index times 2, plus 1
;;           for drive 2
.macro DiskUnit unit, drive
    .assert * = UnitTable + UNIT_ENTRY_SIZE * unit, "UnitTable's entries are in unit order."
    .word drive
.endmacro

;; Zeros that <Initialize> reads SYSTEM.PASCAL's segment 0 into, down from <SEGMENT_0_TOP>, over them and the boot code
;; below them.
FreeStorage:
    .res 2059

;; A JMP for each attached unit, 0-15, which attaching a driver fills in. <AttachedDriver> jumps to them, and
;; <UnitIo::CheckUnit> reads their addresses' high bytes. The last one's address is <UnitTable>'s unit 0 entry.
;; Also: UDJMPV (WK11), UDJMPVEC (A2PBIOS)
AttachedDrivers:
    DriverJump 0
    DriverJump 1
    DriverJump 2
    DriverJump 3
    DriverJump 4
    DriverJump 5
    DriverJump 6
    DriverJump 7
    DriverJump 8
    DriverJump 9
    DriverJump 10
    DriverJump 11
    DriverJump 12
    DriverJump 13
    DriverJump 14

    ; Unit 15's JMP, whose address is the first word of UnitTable.
    .assert * = AttachedDrivers + DRIVER_JUMP_SIZE * 15, "AttachedDrivers's entries are in unit order."
    .byte JMP_ABSOLUTE

;; Each unit's device, a word a unit from unit 0: <CHARACTER_DEVICE>, a drive number (with a high byte of 0) for a Disk
;; II drive, or else the address, less 1, of a driver that <UnitDriver> runs. Apple's DISKNUM and Kusche's DSKNUM start
;; at unit 1, at UnitTable+2 ($FEB0).
;; Also: DISKNUM (A2PBIOS), DSKNUM (WK11)
UnitTable:
    NoUnit 0
    CharacterUnit 1
    CharacterUnit 2
    CharacterUnit 3

    ; Units 4 and 5: slot 6's drives.
    DiskUnit 4, 0
    DiskUnit 5, 1
    CharacterUnit 6
    CharacterUnit 7
    CharacterUnit 8

    ; Units 9 and 10: slot 4's drives; units 11 and 12: slot 5's.
    DiskUnit 9, 4
    DiskUnit 10, 5
    DiskUnit 11, 2
    DiskUnit 12, 3
    .assert * = UnitTable + UNIT_ENTRY_SIZE * UNIT_COUNT, "UnitTable has an entry for each unit."

;; BIOS call 19's routine: jumps to an attached unit's <AttachedDrivers> entry, through <BiosPointers>'s first word.
;; In:
;;   A = the unit, with <ATTACHED_UNIT> set
;;   X, Stack = for the driver
;; Also: UDRWIS (A2PBIOS), URWIS (WK11)
.proc AttachedDriver
    ; Work out the entry's address: BiosPointers's first word, plus the unit times DRIVER_JUMP_SIZE.
    sta BiosSavedA
    and #<~ATTACHED_UNIT
    sta BiosVector
    asl a
    clc
    adc BiosVector
    adc BiosPointers
    sta BiosVector
    lda #0
    adc BiosPointers+1
    sta BiosVector+1

    ; Jump to it with the unit in A.
    lda BiosSavedA
    jmp (BiosVector)
.endproc
