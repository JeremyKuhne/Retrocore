; retrocore: style=strict
;; Hardware: the SDK's Apple II soft switches, and the slot devices SYSTEM.APPLE drives.

    .include <Roms/System/IIeEquates.asm>    ; The keyboard, speaker, display and language card switches

;; Switches the slot ROMs' shared $C800-$CFFF space off, so that the next card to be selected switches its own in.
CLRROM = $CFFF

;; Game button 2, in bit 7. <ConsoleCheck> takes 0 as the shift key held down, as on an Apple II Plus with the shift
;; key modification.
Button2 = $C063

; The Disk II controller's switches, each reached with X or Y = the slot times 16. The DOS RWTS's names for them
; are PHASEOFF, PHASEON, Q6L, Q6H, Q7L and Q7H.

;; Turns stepper phase 0 off. Phase n's switch is 2n above, and the next address turns it on.
DiskPhase0Off = $C080

;; Turns stepper phase 1 off.
DiskPhase1Off = $C082

;; Turns stepper phase 2 off.
DiskPhase2Off = $C084

;; Turns stepper phase 3 off.
DiskPhase3Off = $C086

;; Turns the drive's motor off, after the drive's own delay of about a second.
DiskMotorOff = $C088

;; Turns the drive's motor on.
DiskMotorOn = $C089

;; Selects drive 1. The next address selects drive 2.
DiskSelect1 = $C08A

;; Reads the data latch (Q6 off), and shifts a loaded byte out when writing.
DiskLatch = $C08C

;; Q6 on: senses write protection, with <DiskReadMode>, or loads the write latch.
DiskLoad = $C08D

;; Q7 off: reading. On a communications card, the same address is its ACIA's status and control register.
DiskReadMode = $C08E

;; Q7 on: writing. On a communications card, the same address is its ACIA's data register.
DiskWriteMode = $C08F

; Cards at fixed slots.

;; Slot 1's first I/O address, where <ParallelWrite> stores the character.
ParallelData = $C090

;; A byte of slot 1's ROM page, whose bit 7 <ParallelWrite> waits on before storing.
ParallelBusy = $C1C1

;; The status register of a communications card in slot 3.
Slot3AciaStatus = $C0BE

;; The data register of a communications card in slot 3.
Slot3AciaData = $C0BF

; A CARD_PASCAL_FIXED card's routines, at fixed addresses in its $C800 ROM.

;; Initializes the card.
CardRomInit = $C800

;; Reads a character into the slot's <SlotCharacters> byte.
CardRomRead = $C84D

;; Writes the character in the slot's <SlotCharacters> byte.
CardRomWrite = $C9AA

;; Reading it maps the ROMs at $D000-$FFFF, with language card RAM write-protected; IIeEquates.asm names the other
;; switches of its kind, not this one.
LCROM1 = $C08A
