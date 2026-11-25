;; ATARI 400/800 OPERATING SYSTEM ($E000-$FFFF), REV. A, REV. B AND PAL
;;
;; The operating system of the Atari 400 and 800: the two 4K chips at $E000-$FFFF, with the floating point package's
;; chip below them at $D800 (FloatingPoint.asm). It starts the machine on power-up and SYSTEM RESET, boots the disk or
;; the cassette or starts a cartridge, runs the interrupts and the vertical blank, and gives programs CIO with its
;; handlers (E:, S:, K:, P:, C:), SIO and the resident disk handler through the documented vectors at $E450. The ROM is
;; in parts, each in its own file in Os, in the order they sit in the ROM:
;;
;; - CharacterSet.asm ($E000-$E3FF): the 128 characters, in ANTIC's internal order.
;; - Vectors.asm ($E400-$E4A5): the handlers' vector tables, the documented jump vectors and the default interrupt
;;   vectors.
;; - Cio.asm ($E4A6-$E6D4): CIO.
;; - Interrupts.asm ($E6D5-$E943): the IRQ and NMI handlers, the vertical blank and SETVBV.
;; - Sio.asm ($E944-$EDE9): SIO, the serial bus and the cassette's records.
;; - Disk.asm ($EDEA-$EE77): the resident disk handler, DSKINV.
;; - Printer.asm ($EE78-$EF40): the printer handler, P:.
;; - Cassette.asm ($EF41-$F0E2): the cassette handler, C:.
;; - Reset.asm ($F0E3-$F3E3): power-up and SYSTEM RESET, the boots and Memo Pad.
;; - Editor.asm ($F3E4-$F6E1): the display handler's open and the screen editor's get and put.
;; - Keyboard.asm ($F6E2-$F778): the keyboard handler, K:.
;; - ControlCodes.asm ($F779-$F912): the screen editor's control characters.
;; - Screen.asm ($F913-$FCFB): the display handler's and screen editor's shared routines.
;; - Draw.asm ($FCFC-$FE44): DRAWTO and FILL.
;; - Tables.asm ($FE45-$FFBD): the display modes' tables, the control codes and the keyboard's definitions.
;; - KeyboardInterrupt.asm ($FFBE-$FFFF): the keyboard interrupt, the checksum and the 6502's vectors.
;;
;; VERSION selects the build: VERSION_B (the default) for rev. B, the last 400/800 OS (co12499b and co14599b);
;; VERSION_A for rev. A, the first (co12499a and co14599a); and VERSION_PAL for the PAL machines' OS (co15199 and
;; co15299), which is rev. A with the cassette's and SIO's timing for PAL's 50 Hz, 312-line frames. Every part starts
;; at the same address in all three. Rev. B changed rev. A in these ways:
;;
;; - The IRQ handler scans a table of POKEY's interrupts, and gives the BREAK key a vector, BRKKY. Rev. A's timer 4
;;   never reached VTIMR4, and its BRK test read a P pushed by PHP, so every unclaimed IRQ went to VBREAK.
;; - SETVBV waits for the end of a scan line, where rev. A turned the NMIs off (and left display list interrupts
;;   off) and ran a missed vertical blank itself. A JMP at rev. A's SETVBV routine's address reaches the new one.
;; - The vertical blank enables IRQs after copying the display shadows, not before.
;; - SIO tests for a frame's end with one 16-bit comparison, and sets TIMFLG after starting its timer.
;; - The memory test no longer decrements CART when no cartridge is there, which in rev. A took 1 from RAM in the
;;   left slot on each SYSTEM RESET.
;; - The reset vector points at COLD_START itself, and the chips' checksums are dropped. Rev. A keeps the $E000
;;   chip's in two handler tables' pad bytes, which rev. B zeroes, and the $F000 chip's at $FFF8, where rev. B's word
;;   is no sum of the chip's bytes.
;;
;; Names follow Atari's documentation where it gives them: the OS User's Manual names the vectors and the database,
;; and the Hardware Manual the registers, which OsEquates.asm defines. Other labels are named after what the code
;; does.
;;
;; Maintained by hand. AtariOsSourceTests check that each build assembles byte-identically to its chips.

.cpu Mos6502

VERSION_A = 1                       ;; rev. A, NTSC
VERSION_B = 2                       ;; rev. B, NTSC
VERSION_PAL = 3                     ;; rev. A for PAL

.ifndef VERSION
VERSION = VERSION_B
.endif
.assert (VERSION = VERSION_A) | (VERSION = VERSION_B) | (VERSION = VERSION_PAL), "VERSION is A, B or PAL."

.include "OsEquates.asm"

.org $E000

.include "Os/CharacterSet.asm"
.include "Os/Vectors.asm"
.include "Os/Cio.asm"
.include "Os/Interrupts.asm"
.include "Os/Sio.asm"
.include "Os/Disk.asm"
.include "Os/Printer.asm"
.include "Os/Cassette.asm"
.include "Os/Reset.asm"
.include "Os/Editor.asm"
.include "Os/Keyboard.asm"
.include "Os/ControlCodes.asm"
.include "Os/Screen.asm"
.include "Os/Draw.asm"
.include "Os/Tables.asm"
.include "Os/KeyboardInterrupt.asm"
