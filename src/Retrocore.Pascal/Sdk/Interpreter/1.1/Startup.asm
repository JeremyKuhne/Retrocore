; retrocore: style=strict
;; Startup: clears memory, identifies the slots' cards, and sets up the screen, the disks and the console's card.

; Memory and slots.

;; The 256-byte pages of RAM, $0000-$BFFF, below the I/O space at $C000.
RAM_PAGES = $C0

;; The highest slot <Startup> looks for a card in; it looks from there down to slot 1.
LAST_SLOT = 7

;; The page of $C000 that slot ROM pages count from: slot n's ROM is at page SLOT_ROM_BASE + n, $Cn00.
SLOT_ROM_BASE = $C0

;; The printer's slot, whose card <PrinterInit> and <PrinterWrite> drive.
PRINTER_SLOT = 1

;; The remote units' slot, whose card <RemoteInit>, <RemoteRead> and <RemoteWrite> drive.
REMOTE_SLOT = 2

;; The console's slot: when its card is <CARD_SERIAL>, <CARD_PASCAL_FIXED> or <CARD_PASCAL_FIRMWARE>, the console reads
;; and writes through it instead of the keyboard and the screen.
CONSOLE_SLOT = 3

; Identifying cards.

.assert CARD_UNKNOWN = CARD_DISK_II - 1, "Startup's loop over the card types leaves X = CARD_UNKNOWN for no match."

;; The offset in a slot's ROM of the first byte <Startup> identifies its card by, which it compares with
;; <Startup::CardId05>.
ROM_ID_1 = $05

;; The offset in a slot's ROM of the second byte, which it compares with <Startup::CardId07>.
ROM_ID_2 = $07

;; The offset in a <CARD_PASCAL_FIXED> card's ROM of the byte that is <FIRMWARE_CARD_ID> when the card has the firmware
;; entries, which makes it a <CARD_PASCAL_FIRMWARE> card.
ROM_FIRMWARE_ID = $0B

;; The byte at <ROM_FIRMWARE_ID> on a card with the firmware entries.
;; Also: SIGVALUE (A2PBIOS)
FIRMWARE_CARD_ID = 1

; The BIOS's results, which its calls return in X.

; Flags.

;; One entry of <Startup::CardId05> or <Startup::CardId07>: the byte a card type's slot ROM has at that table's offset.
;; Parameters:
;;   table = <Startup::CardId05> or <Startup::CardId07>
;;   type = the card type, from <CARD_DISK_II> up; the entries go in type order
;;   value = the byte
.macro CardId table, type, value
    .assert * = table + type - CARD_DISK_II, "A card ID table's entries are in card type order."
    .byte value
.endmacro

;; Four addresses <Startup> copies to <BiosPointersCopy>, where nothing reads them. The BIOS's attached-driver call
;; reads the first from here.
;; Also: JVECTRS (A2PBIOS), JVECTS (WK11)
BiosPointers:
    ; The attached drivers' JMPs, which the attached-driver call indexes.
    .word AttachedDrivers
    ; Unit 1's entry in UnitTable.
    .word UnitTable+2
    ; The BIOS's first stub.
    .word BiosConsoleRead
    ; The BIOS's first vector.
    .word VectorConsoleRead

;; Clears RAM $0000-$BFFF, records each slot's card type in <SlotTypes>, sets up the text screen, the disks and the
;; console's card, and goes on to <EnterRestart>, which switches bank 1 in and goes on to <Restart>.
;; Also: CLRMEM (WK11), START (A2PBIOS)
.proc Startup

;; The page <Startup> is clearing.
;; Also: ZEROH (A2PBIOS), ZEROL (A2PBIOS)
ClearPointer = FirstSector

;; $Cn00, the ROM of the slot <Startup> is identifying: <SumSlotRom> adds up the page it points at.
;; Also: CKPTRH (A2PBIOS), CKPTRL (A2PBIOS)
SlotRom = PartialDest + 1

;; The slot ROM's first sum, which the second must match.
;; Also: CHECKH (A2PBIOS), CHECKL (A2PBIOS)
RomSum = SectorDone

    cld
    sei

    ; Clear $0000-$BFFF, ClearPointer included: it is 0 while page 0 is cleared.
    lda #0
    sta ClearPointer
    sta ClearPointer+1
    tay
    tax

;; Clears a page of memory.
;; Also: ZERLP (A2PBIOS)
ClearPage:
    sta (ClearPointer),y
    iny
    bne ClearPage
    inc ClearPointer+1
    inx
    cpx #RAM_PAGES
    bne ClearPage

    ; Identify the slots' cards from slot 7 down. SlotRom's low byte is 0, from the clearing.
    ldy #SLOT_ROM_BASE + LAST_SLOT

;; Identifies the card in the next slot, from slot 7 down.
;; Also: NXTCRD (A2PBIOS)
NextSlot:
    sty SlotRom+1

    ; A card's ROM adds up to more than 255, and to the same twice; an empty slot reads what is on the bus.
    jsr SumSlotRom
    sta RomSum
    stx RomSum+1
    jsr SumSlotRom
    cpx #0
    beq SlotDone
    cmp RomSum
    bne SlotDone
    cpx RomSum+1
    bne SlotDone

    ; The sums match, so this always branches.
    beq Identify

;; The byte at <ROM_ID_1> in each card type's ROM, by type from <CARD_DISK_II>.
;; Also: CN05BYTS (A2PBIOS), CN05T (WK11)
CardId05:
    CardId CardId05, CARD_DISK_II, $03
    CardId CardId05, CARD_SERIAL, $18
    CardId CardId05, CARD_PASCAL_FIXED, $38
    CardId CardId05, CARD_PARALLEL, $48

;; The byte at <ROM_ID_2> in each card type's ROM, by type from <CARD_DISK_II>.
;; Also: CN07BYTS (A2PBIOS), CN07T (WK11)
CardId07:
    CardId CardId07, CARD_DISK_II, $3C
    CardId CardId07, CARD_SERIAL, $38
    CardId CardId07, CARD_PASCAL_FIXED, $18
    CardId CardId07, CARD_PARALLEL, $48

;; Finds the type whose two bytes the ROM has, from CARD_PARALLEL down; no match leaves X = CARD_UNKNOWN.
;; Also: SKIPIORTS (A2PBIOS)
Identify:
    ldx #CARD_PARALLEL

;; Compares the ROM's two identifying bytes with a card type's.
;; Also: NXTYP (A2PBIOS)
CompareType:
    ldy #ROM_ID_1
    lda (SlotRom),y
    cmp CardId05-CARD_DISK_II,x
    bne NextType
    ldy #ROM_ID_2
    lda (SlotRom),y
    cmp CardId07-CARD_DISK_II,x
    beq Matched

;; Tries the next card type down.
;; Also: TRYNXT (A2PBIOS)
NextType:
    dex
    cpx #CARD_DISK_II
    bcs CompareType

;; Takes a Pascal card with the firmware byte as one with the firmware entries.
;; Also: STOR (A2PBIOS)
Matched:
    cpx #CARD_PASCAL_FIXED
    bne Record
    ldy #ROM_FIRMWARE_ID
    lda (SlotRom),y
    cmp #FIRMWARE_CARD_ID
    bne Record
    ldx #CARD_PASCAL_FIRMWARE

;; Records the type: slot n's is at SlotTypes + n - 1.
;; Also: STOR1 (A2PBIOS)
Record:
    ldy SlotRom+1
    txa
    sta SlotTypes - SLOT_ROM_BASE - 1,y

;; Goes on down to slot 1.
;; Also: NOPROM (A2PBIOS)
SlotDone:
    ldy SlotRom+1
    dey
    cpy #SLOT_ROM_BASE
    bne NextSlot

    ; Y is SLOT_ROM_BASE, so this always branches.
    beq InstallHook

;; The 4 bytes <Startup> copies to <ConsoleCheckHook>: a JSR to the BIOS's <ConsoleCheck> stub, and an RTS.
ConsoleCheckImage:
    jsr BiosConsoleCheck
    rts

    ; Copy ConsoleCheckImage to ConsoleCheckHook, and BiosPointers to BiosPointersCopy.
InstallHook:
    ldy #InstallHook - ConsoleCheckImage - 1
CopyHook:
    lda ConsoleCheckImage,y
    sta ConsoleCheckHook,y
    dey
    bpl CopyHook
    ldy #Startup - BiosPointers - 1
CopyPointers:
    lda BiosPointers,y
    sta BiosPointersCopy,y
    dey
    bpl CopyPointers

    ; Lock the keyboard in upper case.
    lda #KEYBOARD_UPPER
    sta KeyboardCase

    ; Show text page 1 on the whole screen (with hi-res, which text hides), and clear the keyboard's strobe.
    lda TXTSET
    lda MIXCLR
    lda LOWSCR
    lda HIRES
    lda KBDSTRB

    ; Clear the screen and show the cursor, and reset the disks.
    jsr ClearScreen
    jsr FlipCursor
    jsr ResetDiskState

    ; Initialize the console's card, and note in ConsoleCardFlag that it did.
    lda SlotTypes + CONSOLE_SLOT - 1
    ldy #CONSOLE_SLOT * 16
    jsr CardInit
    cpx #IO_OK
    bne Done
    lda #CONSOLE_CARD_READY
    sta ConsoleCardFlag

;; Goes on to Restart.
;; Also: STARTUP (A2PBIOS)
Done:
    jmp EnterRestart
.endproc

;; Adds up the 256 bytes of a slot's ROM.
;; In: Startup::SlotRom = $Cn00
;; Out: A = the sum's low byte, X = its high byte, Y = 0
;; Also: CKPAGE (A2PBIOS, WK11)
.proc SumSlotRom
    lda #0
    tax
    tay

;; Adds a byte of the ROM.
;; Also: CKNX (A2PBIOS, WK11)
Add:
    clc
    adc (Startup::SlotRom),y
    bcc NoCarry
    inx

;; Steps to the next byte.
;; Also: NOCRY (A2PBIOS, WK11)
NoCarry:
    iny
    bne Add
    rts
.endproc

;; Waits about (26 + 27A + 5A^2) / 2 microseconds, with the same code as the Monitor's WAIT.
;; In: A = the delay, 1-255, or 0 for 256
;; Out: A = 0
;; Keeps: X, Y
;; Also: TDELAY (WK11)
.proc Wait
    sec
Outer:
    pha
Inner:
    sbc #1
    bne Inner
    pla
    sbc #1
    bne Outer
    rts
.endproc
