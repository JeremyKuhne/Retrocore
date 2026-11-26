; retrocore: style=strict
;; Character devices: the BIOS's printer, remote and graphics calls and console output, and the card drivers they
;; share, by slot type.

; Characters.

; A CARD_SERIAL card's ACIA, as a 6850 reads its control and status bits.

;; The control value that resets the ACIA.
ACIA_RESET = $03

;; The control value <SerialInit> sets: the clock divided by 16, 8 data bits, no parity and 1 stop bit.
ACIA_MODE = $15

;; The status bit that is set when the ACIA has received a character. <SerialRead> tests it with LSR.
ACIA_RECEIVED = $01

;; The status bit that is set when the ACIA can take a character to send.
ACIA_SEND_READY = $02

; A CARD_PASCAL_FIRMWARE card's entries: the offset in its ROM page of each entry's low byte, in the same page.

;; Initializes the card.
;; Also: PASCALINIT (A2PBIOS)
FIRMWARE_INIT = $0D

;; Reads a character into A.
;; Also: PASCALREAD (A2PBIOS)
FIRMWARE_READ = $0E

;; Writes the character in A.
;; Also: PASCALWRITE (A2PBIOS)
FIRMWARE_WRITE = $0F

;; With A = <FIRMWARE_ASK_OUTPUT> or <FIRMWARE_ASK_INPUT>: sets carry when the card is ready.
;; Also: PASCALSTATUS (A2PBIOS)
FIRMWARE_STATUS = $10

;; The BIOS's printer init, for the card in the printer's slot: a <CARD_PARALLEL> card needs nothing, and any other
;; goes on into <CardInit>.
;; Out: X = <IO_OK>, or <IO_NO_DEVICE> for a card the BIOS cannot drive
;; Also: PINIT (A2PBIOS, WK11)
.proc PrinterInit
    ldy #PRINTER_SLOT * 16
    lda SlotTypes + PRINTER_SLOT - 1
    cmp #CARD_PARALLEL
    beq SerialInit::Done
.endproc

;; Initializes a card by its type.
;; In: A = the type, Y = the slot times 16
;; Out: X = <IO_OK>, <IO_NO_DEVICE> for a type the BIOS cannot drive, or what a <CARD_PASCAL_FIRMWARE> card's init
;;     returns
;; Also: GENIT (A2PBIOS)
.proc CardInit
    cmp #CARD_PASCAL_FIXED
    beq FixedRomInit
    cmp #CARD_SERIAL
    beq SerialInit
    cmp #CARD_PASCAL_FIRMWARE
    beq FirmwareInit
    ldx #IO_NO_DEVICE
    rts
.endproc

;; Runs a <CARD_PASCAL_FIRMWARE> card's init entry.
;; In: A = the A for the entry, Y = the slot times 16
;; Also: FINIT (WK11), FIRMINIT (A2PBIOS)
.proc FirmwareInit
    pha
    jsr SelectCardRom
    ldy #FIRMWARE_INIT
.endproc

;; Jumps to one of a <CARD_PASCAL_FIRMWARE> card's entries, with A from the stack, X = $Cn and Y = the slot times 16.
;; The entry returns to CallFirmware's caller.
;; In: Y = the entry: <FIRMWARE_INIT>, <FIRMWARE_READ>, <FIRMWARE_WRITE> or <FIRMWARE_STATUS>, CardPointer = $Cn00,
;;   X = $Cn, FirmwareSlot = the slot times 16, Stack = the entry's A, above the return address
;; Also: FVEC1 (A2PBIOS, WK11)
.proc CallFirmware
    lda (CardPointer),y
    sta CardPointer
    ldy FirmwareSlot
    pla
    jmp (CardPointer)
.endproc

;; The BIOS's graphics init: shows text, and leaves X as it was.
;; Keeps: X, Y
;; Also: GINIT (WK11), GRAFINIT (A2PBIOS)
.proc GraphicsInit
    lda TXTSET
    rts
.endproc

;; The BIOS's remote init, for the card in the remote units' slot.
;; Out: X = <IO_OK>, or <IO_NO_DEVICE> for a card the BIOS cannot drive
;; Also: RINIT (A2PBIOS, WK11)
.proc RemoteInit
    lda SlotTypes + REMOTE_SLOT - 1
    ldy #REMOTE_SLOT * 16

    ; Y is not 0, so this always branches.
    bne CardInit
.endproc

;; Resets a <CARD_SERIAL> card's ACIA and sets its mode.
;; In: Y = the slot times 16
;; Out: X = <IO_OK>
;; Keeps: Y
;; Also: ICOM (A2PBIOS, WK11)
.proc SerialInit

;; The ACIA's control register, at the slot's address with Y = the slot times 16.
AciaControl = DiskReadMode

    lda #ACIA_RESET
    sta AciaControl,y
    lda #ACIA_MODE
    sta AciaControl,y

;; Returns I/O result 0.
;; Also: CLRIO1 (A2PBIOS, WK11)
Done:
    ldx #IO_OK
    rts
.endproc

;; Runs a <CARD_PASCAL_FIXED> card's init routine, in its $C800 ROM.
;; In: Y = the slot times 16
;; Out: X = <IO_OK>
;; Also: ISER (A2PBIOS, WK11)
.proc FixedRomInit
    jsr SelectCardRom
    jsr CardRomInit
    ldx #IO_OK
    rts
.endproc

;; Points <CardPointer> at a slot's ROM page, keeps the slot in <FirmwareSlot>, and switches its card's $C800 ROM in by
;; reading <CLRROM> and then a byte of the slot's ROM page.
;; In: Y = the slot times 16
;; Out: X = $Cn, CardPointer = $Cn00, FirmwareSlot = Y
;; Keeps: Y
;; Also: SER1 (A2PBIOS, WK11)
.proc SelectCardRom
    sty FirmwareSlot

    ; Make $Cn from the slot times 16.
    tya
    lsr a
    lsr a
    lsr a
    lsr a
    ora #SLOT_ROM_BASE
    tax
    lda #0
    sta CardPointer
    stx CardPointer+1

    ; Switch the other cards' $C800 ROMs out, and this card's in.
    lda CLRROM
    lda (CardPointer),y
    rts
.endproc

;; The BIOS's console write: unless output is flushed, sends a character to the console's card, or to the 80-column
;; screen with the cursor hidden while <ScreenWrite> runs.
;; In: A = the character
;; Out: X = <IO_OK>, or what a <CARD_PASCAL_FIRMWARE> card's write returns
;; Also: CWRITE (A2PBIOS, WK11)
.proc ConsoleWrite
    jsr ConsoleCheck

    ; Drop the character while output is flushed.
    bit ConsoleFlags
    bvs Done

    ; Send it to the console's card, if it has one.
    tax
    ldy #CONSOLE_SLOT * 16
    lda SlotTypes + CONSOLE_SLOT - 1
    cmp #CARD_SERIAL
    beq SerialWrite
    cmp #CARD_PASCAL_FIXED
    beq FixedRomWrite
    cmp #CARD_PASCAL_FIRMWARE
    beq FirmwareWrite

    ; Or write it to the screen.
    txa
    sta ScreenWrite::Character
    jsr FlipCursor
    ldy ConsoleColumn
    jsr ScreenWrite
    jsr FlipCursor

;; Returns I/O result 0.
;; Also: CLRIO (A2PBIOS)
Done:
    ldx #IO_OK
    rts
.endproc

;; Waits until a <CARD_PASCAL_FIRMWARE> card is ready for output, then runs its write entry.
;; In: X = the character, Y = the slot times 16
;; Also: WFIRM (A2PBIOS, WK11)
.proc FirmwareWrite
    txa
    pha
    lda #FIRMWARE_ASK_OUTPUT
    jsr FirmwareWait
    jsr SelectCardRom
    ldy #FIRMWARE_WRITE
    jmp CallFirmware
.endproc

;; Writes a character with a <CARD_PASCAL_FIXED> card's write routine, which takes it from the slot's <SlotCharacters>
;; byte.
;; In: X = the character, Y = the slot times 16
;; Out: X = <IO_OK>
;; Also: WSER (A2PBIOS, WK11)
.proc FixedRomWrite
    jsr ConsoleCheck
    txa
    pha
    jsr SelectCardRom
    pla
    sta CardCharacter,x
    jsr CardRomWrite
    ldx #IO_OK
    rts
.endproc

;; The BIOS's remote write, to the card in the remote units' slot.
;; In: A = the character
;; Out: X = <IO_OK>, or <IO_NO_DEVICE> for a card the BIOS cannot drive
;; Also: RWRITE (A2PBIOS, WK11)
.proc RemoteWrite
    tax
    lda SlotTypes + REMOTE_SLOT - 1
    ldy #REMOTE_SLOT * 16

    ; Y is not 0, so this always branches.
    bne CardWrite
.endproc

;; Writes a character to a <CARD_PARALLEL> card, which must be in slot 1: waits while <ParallelBusy>'s bit 7 is set,
;; then stores it at <ParallelData>.
;; In: X = the character
;; Out: X = <IO_OK>
;; Keeps: Y
;; Also: WPRN (A2PBIOS)
.proc ParallelWrite
    jsr ConsoleCheck
    lda ParallelBusy
    bmi ParallelWrite
    stx ParallelData
    ldx #IO_OK
    rts
.endproc

;; Writes a character to a <CARD_SERIAL> card, once its ACIA can take it.
;; In: X = the character, Y = the slot times 16
;; Out: X = <IO_OK>
;; Keeps: Y
;; Also: WCOM (A2PBIOS, WK11)
.proc SerialWrite

;; The ACIA's status register, at the slot's address with Y = the slot times 16.
AciaStatus = DiskReadMode

;; The ACIA's data register, at the slot's address with Y = the slot times 16.
AciaData = DiskWriteMode

    jsr ConsoleCheck
    lda AciaStatus,y
    and #ACIA_SEND_READY
    beq SerialWrite
    txa
    sta AciaData,y
    ldx #IO_OK
    rts
.endproc

;; The BIOS's printer write, to the card in the printer's slot: drops line feeds when <PrinterOptions>' bit 7 is set,
;; and goes on into <CardWrite> for a card other than <CARD_PARALLEL>.
;; In: A = the character
;; Out: X = <IO_OK>, or <IO_NO_DEVICE> for a card the BIOS cannot drive
;; Also: PWRITE (A2PBIOS, WK11)
.proc PrinterWrite
    tax

    ; Drop a line feed if PrinterOptions says so.
    lda PrinterOptions
    bpl Send
    cpx #ASCII_LF
    beq ConsoleWrite::Done

;; Sends the character by the card's type.
;; Also: LFPASS (A2PBIOS)
Send:
    ldy #PRINTER_SLOT * 16
    lda SlotTypes + PRINTER_SLOT - 1
    cmp #CARD_PARALLEL
    beq ParallelWrite
.endproc

;; Writes a character with a card, by its type.
;; In: A = the type, X = the character, Y = the slot times 16
;; Out: X = <IO_OK>, <IO_NO_DEVICE> for a type the BIOS cannot drive, or what a <CARD_PASCAL_FIRMWARE> card's write
;;     returns
;; Also: GENW2 (A2PBIOS)
.proc CardWrite
    cmp #CARD_PASCAL_FIXED
    beq FixedRomWrite
    cmp #CARD_SERIAL
    beq SerialWrite
    cmp #CARD_PASCAL_FIRMWARE
    beq FirmwareWrite

;; Returns no device: the slot has no card the BIOS can write to.
;; Also: OFFLINE (A2PBIOS)
NoCard:
    ldx #IO_NO_DEVICE
    rts
.endproc

;; The BIOS's remote read, from the card in the remote units' slot, by its type.
;; Out: A = the character, X = <IO_OK>; or X = <IO_NO_DEVICE> for a card the BIOS cannot drive
;; Also: RREAD (A2PBIOS, WK11)
.proc RemoteRead
    lda SlotTypes + REMOTE_SLOT - 1
    ldy #REMOTE_SLOT * 16
    cmp #CARD_PASCAL_FIXED
    beq FixedRomRead
    cmp #CARD_SERIAL
    beq SerialRead
    cmp #CARD_PASCAL_FIRMWARE
    beq FirmwareReadWait

    ; A is not CARD_PASCAL_FIRMWARE, so this always branches.
    bne CardWrite::NoCard
.endproc

;; Reads a character from a <CARD_SERIAL> card, once its ACIA has received one.
;; In: Y = the slot times 16
;; Out: A = the character, X = <IO_OK>
;; Keeps: Y
;; Also: RCOM (A2PBIOS, WK11)
.proc SerialRead

;; The ACIA's status register, at the slot's address with Y = the slot times 16.
AciaStatus = DiskReadMode

;; The ACIA's data register, at the slot's address with Y = the slot times 16.
AciaData = DiskWriteMode

    .assert ACIA_RECEIVED = $01, "SerialRead shifts the ACIA's received bit into carry."
    jsr ConsoleCheck
    lda AciaStatus,y
    lsr a
    bcc SerialRead
    lda AciaData,y
    ldx #IO_OK
    rts
.endproc

;; Waits until a <CARD_PASCAL_FIRMWARE> card has input, then goes on into <FirmwareRead>.
;; In: Y = the slot times 16
;; Out: A = the character
;; Also: RFIRM (A2PBIOS, WK11)
.proc FirmwareReadWait
    lda #FIRMWARE_ASK_INPUT
    jsr FirmwareWait
.endproc

;; Reads a character with a <CARD_PASCAL_FIRMWARE> card's read entry.
;; In: Y = the slot times 16
;; Out: A = the character
;; Also: FREAD1 (A2PBIOS, WK11)
.proc FirmwareRead
    jsr SelectCardRom
    pha
    ldy #FIRMWARE_READ
    jmp CallFirmware
.endproc

;; Reads a character with a <CARD_PASCAL_FIXED> card's read routine, which leaves it in the slot's <SlotCharacters>
;; byte.
;; In: Y = the slot times 16
;; Out: A = the character, X = <IO_OK>
;; Also: RSER (A2PBIOS, WK11)
.proc FixedRomRead
    jsr ConsoleCheck
    jsr SelectCardRom
    jsr CardRomRead

    ; Take the character from SlotCharacters by X = $Cn, from SelectCardRom, which the card's routine leaves.
    lda CardCharacter,x
    ldx #IO_OK
    rts
.endproc

;; Asks a <CARD_PASCAL_FIRMWARE> card with its status entry whether it is ready.
;; In: A = <FIRMWARE_ASK_OUTPUT> or <FIRMWARE_ASK_INPUT>, Y = the slot times 16
;; Out: carry = set when it is ready
;; Also: FIRMSTATUS (A2PBIOS)
.proc FirmwareStatus
    pha
    jsr SelectCardRom
    ldy #FIRMWARE_STATUS
    jmp CallFirmware
.endproc

;; Polls the console and asks a <CARD_PASCAL_FIRMWARE> card whether it is ready, until it is.
;; In: A = <FIRMWARE_ASK_OUTPUT> or <FIRMWARE_ASK_INPUT>, Y = the slot times 16
;; Keeps: A
;; Also: IOWAIT (A2PBIOS, WK11)
.proc FirmwareWait
    jsr ConsoleCheck
    pha
    jsr FirmwareStatus
    pla
    bcc FirmwareWait
    rts
.endproc
