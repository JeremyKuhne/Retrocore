; retrocore: style=strict
;; Memory below $C000 that SYSTEM.APPLE uses for its own: the stack page, the disk driver's pages 2 and 3, the
;; type-ahead buffer, the slots' screen holes, and the BIOS's area at $BF00.

;; The 6502 stack, which is also the p-machine's evaluation stack: a word is pushed high byte first.
;; Also: P1BASE (WK11)
Stack = $0100

; The Disk II driver's buffers and variables.

;; Page 2 as working storage: the top six bits of a sector being written, a read's partial last page, and a row
;; <ScrollView> rotates.
;; Also: BUFF6B (WK11), BUFFER (A2PBIOS)
ScratchBuffer = $0200

;; A sector's low bit pairs, three to a byte, in 86 bytes ($0300-$0355), for <WriteSector> and <ReadSector>.
;; Also: BUFF2B (WK11)
TwoBitParts = $0300

;; Slot times 16 for the drive being transferred.
;; Also: SLOTNO (WK11)
DiskSlot = $03A1

;; The drive being transferred, 1 or 2.
;; Also: DRVNO (WK11)
DiskDrive = $03A2

;; The volume number the disk must have, or 0 for any. <ResetDiskState> sets 0, and nothing in SYSTEM.APPLE changes
;; it.
WantedVolume = $03A3

;; The track being transferred, advancing a track at a time.
DiskTrack = $03A4

;; When writing: the sector whose data <PrenibbleSector> has ready, waiting for its address field, or $FF for none.
PreparedSector = $03A5

;; The transfer's buffer, its page advancing a track at a time.
;; Also: XFRADR (WK11)
DiskBuffer = $03A8

;; 1 to read, 2 to write.
;; Also: RDWRFL (WK11)
DiskCommand = $03AC

;; <TransferTrack>'s result: with carry set, one of the DISK_ERROR_ values; with carry clear, <SECTOR_DONE>.
DiskError = $03AD

;; The volume of the last address field on the right track.
LastVolume = $03AE

;; Slot times 16 for the drive last used. Before using another slot, <TransferTrack> waits for its motor to stop.
;; Also: PRVSLT (WK11)
CurrentSlot = $03AF

;; The drive last selected, 1 or 2. A change counts as a stopped motor.
;; Also: PRVDRV (WK11)
CurrentDrive = $03B0

; The console.

;; The type-ahead buffer: keys at TypeAhead+0 to +77, by <TypeAheadIn> and <TypeAheadOut>.
;; Also: CONBUF (A2PBIOS)
TypeAhead = $03B1

; The slots' screen holes: bytes of the text page's unused rows that each slot keeps for its own.

;; Each Disk II arm's half-track: ArmTracks+slot for drive 1, and ArmTracks+$80+slot for drive 2.
ArmTracks = $0478

;; The screen holes at $0678 + slot, through which a <CARD_PASCAL_FIXED> card's <CardRomRead> and <CardRomWrite> take
;; the character.
SlotCharacters = $0678

;; <SlotCharacters> indexed by $Cn rather than by slot: with X = $Cn, CardCharacter,X is $0678 + n.
CardCharacter = SlotCharacters - $C0

;; Slot times 16 for the card being called, which <CallFirmware> passes in Y.
FirmwareSlot = $06F8

; The BIOS's area, $BF00-$BFFF.

;; 4 bytes <Startup> fills with JSR <BiosConsoleCheck> and RTS, reaching <ConsoleCheck> from RAM. Nothing in
;; SYSTEM.APPLE calls it.
;; Also: CONCKVECTOR (A2PBIOS)
ConsoleCheckHook = $BF0A

;; Startup sets bit 2 when slot 3's card initializes as the console. Initialize then starts the heap at $0804
;; rather than $0C04, since the 80-column screen does not need text page 2.
;; Also: SCRMODE (A2PBIOS)
ConsoleCardFlag = $BF0E

;; Bit 7 set: <PrinterWrite> drops line feeds. Nothing in SYSTEM.APPLE sets it.
;; Also: LFFLAG (A2PBIOS, WK11)
PrinterOptions = $BF0F

;; The first of the 80 columns that text page 1 shows: 0 or 40, or between when the view follows the cursor.
;; Also: NLEFT (A2PBIOS)
ViewLeft = $BF11

;; <ScreenWrite>'s sequence state: 0 for none, 1 after <ASCII_ESC> (the next character is dropped), and 3 then 2 after
;; $1E (GOTOXY's column, then its row).
;; Also: ESCFLG (WK11), ESCNT (A2PBIOS)
EscapeState = $BF12

;; A 16-bit count of <ConsoleCheck>'s calls: the seed of the system's built-in random function, Apple's BIOS document
;; says (A2PBIOS). Nothing in SYSTEM.APPLE reads it.
;; Also: RANDH (A2PBIOS), RANDL (A2PBIOS), RANDNO (WK11)
PollCount = $BF13

;; Bit 7: output is stopped, and <ConsoleCheck> waits for the stop key again; bit 6: output is flushed, and
;; <ConsoleWrite> drops it; bit 0: the view follows the cursor (Control-Z sets it, and Control-A clears it and switches
;; halves).
;; Also: CNFLGS (WK11), CONFLGS (A2PBIOS)
ConsoleFlags = $BF15

;; Where the break key goes, from <ConsoleInit>: <BreakJump> switches bank 1 in and jumps through it.
;; Also: BREAK (A2PBIOS, WK11)
ConsoleBreakVector = $BF16

;; The <TypeAhead> index <ConsoleRead> last took a key from: <TypeAheadIn> when the buffer is empty.
;; Also: RPTR (A2PBIOS, WK11)
TypeAheadOut = $BF18

;; The <TypeAhead> index <ConsoleCheck> last stored a key at.
;; Also: WPTR (A2PBIOS, WK11)
TypeAheadIn = $BF19

;; The stub caller's return address, kept while <BiosCall> runs a vector.
;; Also: RETH (A2PBIOS), RETL (A2PBIOS)
BiosCaller = $BF1A

;; Bits 4-5 of a <UNITREAD at StandardProcedures::UnitRead> or <UNITWRITE at StandardProcedures::UnitWrite> control
;; word, as bits 0-1. Bit 0 makes <ConsoleCheck> skip Control-K, Control-A, Control-Z and the case keys; bit 1, the
;; stop, break and flush keys.
;; Also: SPCHAR (A2PBIOS, WK11)
IoControl = $BF1C

;; <BreakHandler>, which <Initialize> puts here for the console driver.
;; Also: IBREAK (A2PBIOS), IBRK (WK11)
BreakAddress = $BF1D

;; SYSCOM's address, which <Initialize> puts here.
;; Also: ISYSC (WK11), ISYSCOM (A2PBIOS)
SyscomAddress = $BF1F

;; Two bytes <Initialize> sets to 2 and 1. Apple's BIOS document and Kusche's listing call the second FLAVOR (A2PBIOS,
;; WK11).
;; Also: VER (WK11), VERSION (A2PBIOS)
BootValues = $BF21

;; <CopiedTable>'s address, which <Initialize> puts here.
CopiedTablePointer = $BF23

;; Each slot's card type, from <Startup>, slots 1-7 at SlotTypes+0 to +6: 0 for none, 1 for an unknown ROM, or one of
;; the CARD_ types. Slot 1 is the printer's slot, slot 2 the remote units', and slot 3 the console's when its type is
;; <CARD_SERIAL>, <CARD_PASCAL_FIXED> or <CARD_PASCAL_FIRMWARE>. Apple's SLTTYPS and Kusche's SLTYPS start a byte lower,
;; at slot 0, which this table leaves out: their slot n is at SLTTYPS+n, which is SlotTypes+n-1.
;; Also: SLTTYPS (A2PBIOS), SLTYPS (WK11)
SlotTypes = $BF28

;; Where <Reset> goes: <Pcodes::ExitSystem>, which <Initialize> sets, so RESET leaves the system.
;; Also: XITLOC (A2PBIOS, WK11)
ResetHandler = $BF2F

;; 42 bytes <Initialize> copies from <Initialize::CopiedTableImage>, filling $BF56-$BF7F, which Apple's BIOS document
;; gives to "FORTRAN PROTECTION" (A2PBIOS). What they are for is not known: 1.2 and 1.3 copy the same bytes, and nothing
;; in SYSTEM.APPLE or on the 1.1 disks reads them or <CopiedTablePointer>.
CopiedTable = $BF56
