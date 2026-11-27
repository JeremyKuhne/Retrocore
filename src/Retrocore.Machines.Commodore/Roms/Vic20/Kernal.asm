; retrocore: style=strict
;; COMMODORE VIC-20 KERNAL ROM 901486-06 FOR NTSC AND 901486-07 FOR 50 HZ TELEVISION
;;
;; The kernal is the VIC-20's operating system, in the last 7,044 bytes of the chip at $E000-$FFFF, from $E47C
;; (BASIC's last part is the chip's first 1148 bytes, to $E47B). It holds the screen editor, which draws the 22 by 23
;; screen and reads the keyboard; the devices behind BASIC's OPEN, CLOSE, GET#, INPUT#, PRINT#, CMD, LOAD, SAVE and
;; VERIFY: the keyboard (0), the Datasette (1), RS-232 on the user port (2), the screen (3) and the serial bus
;; (4-31), where the disk drives and printers are; the jiffy clock; start-up, with the RAM test that places the
;; screen and BASIC by the RAM fitted; and the interrupts.
;;
;; THE LAYOUT
;;
;; - $E4A0: the patch area, routines Commodore moved here for room (Kernal.PatchArea.asm).
;; - $E500: the screen editor and the keyboard scan, with the IRQ's jiffy routine (Kernal.Editor.asm).
;; - $EE14: the serial bus (Kernal.Serial.asm).
;; - $EFA3: RS-232's sending, receiving, channels and buffers (Kernal.Rs232.asm).
;; - $F174: the messages, the channels, OPEN and CLOSE, LOAD and SAVE, the clock and the errors
;;   (Kernal.Channels.asm).
;; - $F7AF: the tape: headers, buffers, the motor and the interrupt routines that read and write the pulses
;;   (Kernal.Tape.asm).
;; - $FD22: start-up, the RAM test and the small system calls (Kernal.Startup.asm).
;; - $FEA9: the NMI, with RS-232's bit timing, and the IRQ's entry (Kernal.Interrupts.asm).
;; - $FF8A: the jump table and the processor's vectors (Kernal.JumpTable.asm).
;;
;; Programs call the kernal through the jump table (<KernalOpen> and the other `Kernal` names), and 12 of its 36
;; entries go through the RAM vectors at $0314-$0333 (<IrqVector> to <SaveVector>; LOAD and SAVE after taking their
;; addresses), which a program may point at its own code; <Startup::RestoreVectors> sets them back.
;;
;; THE NAMES
;;
;; The code is arranged in families, scopes spread through the ROM: `Editor`, `Serial`, `Rs232`, `Channels`,
;; `Clock`, `Tape`, `Startup` and `Interrupts`. The jump table, the RAM vectors, the hardware and the variables that
;; several families or programs use are top level. Commodore's names from its kernal listing of 1980 (KV20), and the
;; names *Mapping the VIC* (MTV) and the Programmer's Reference Guide (V20PRG) give, are kept in each definition's
;; `Also:`; docs/conversions/Vic20KernalRenames.md has every old name with its new one, and Vic20.md the decisions.
;;
;; Assembles byte-identically to 901486-06 with PAL = 0 and to 901486-07 with PAL = 1, from $E47C; with BASIC's
;; source, which ends at $E47B, they make the whole chip. Maintained by hand; Vic20RomSourceTests pins both builds by
;; digest.

.cpu Mos6502

.ifndef PAL
;; 1 for the PAL kernal, 901486-07, for 50 Hz television (the screen's place, the jiffy timer and the baud rates);
;; 0 for the NTSC kernal, 901486-06.
PAL = 0
.endif

.include "Kernal.Equates.asm"

    .org $E47C

    ; BASIC's part of the chip ends at $E47B; the chip is blank up to the patch area.
    .res $E4A0 - *, $FF

.include "Kernal.PatchArea.asm"
.include "Kernal.Editor.asm"
.include "Kernal.Serial.asm"
.include "Kernal.Rs232.asm"
.include "Kernal.Channels.asm"
.include "Kernal.Tape.asm"
.include "Kernal.Startup.asm"
.include "Kernal.Interrupts.asm"
.include "Kernal.JumpTable.asm"

.assert * = $10000, "The kernal ends at the processor's vectors."
