;; BBC MICRO MOS 1.20 ($C000-$FFFF)
;;
;; The Machine Operating System of the BBC Microcomputer Model B, version 1.20: the 16K ROM at &C000-&FFFF. It starts
;; the machine on power-up and BREAK, runs the screen, keyboard, sound, ADC and serial port from their interrupts,
;; provides the cassette filing system, and gives languages and paged ROMs the documented calls: OSWRCH, OSRDCH,
;; OSBYTE, OSWORD, OSCLI, the filing system calls and their vectors in page two. The ROM is in parts, each in its own
;; file in Mos, in the order they sit in the ROM:
;;
;; - Font.asm ($C000-$C2FF): the font for characters 32-127.
;; - Vdu.asm ($C300-$D017): the VDU tables, VDUCHR and the control codes, the text window, scrolling, the cursor and
;;   mode changes.
;; - Graphics.asm ($D018-$D93F): PLOT, lines, triangles, fills, the graphics window and reading points.
;; - Reset.asm ($D940-$DF0B): the default vectors and OS variables, the reset and BREAK code, the paged ROM calls,
;;   BRK and the interrupt handlers, and OSRDCH.
;; - Commands.asm ($DF0C-$E5B2): OSCLI and the * commands, OSWRCH, the printer, the buffers and *KEY.
;; - OsByte.asm ($E5B3-$EA0F): OSBYTE and OSWORD, their dispatch table and the calls behind them.
;; - Keyboard.asm ($EA10-$F18D): GSINIT and GSREAD, the keyboard, the sound system, the keyboard translation table
;;   and the paged ROM service calls.
;; - Cassette.asm ($F18E-$F68C): the cassette filing system's OSFILE, OSARGS, OSFIND, OSBGET and OSBPUT.
;; - CassetteFiles.asm ($F68D-$FBFF): *EXEC and *SPOOL, and reading and writing tape blocks.
;; - Vectors.asm ($FC00-$FFFF): the credits under FRED, JIM and SHEILA, the extended vector entries and the
;;   documented calls' entry points.
;;
;; Names follow Acorn's documentation where it gives them: the User Guide and the Advanced User Guide name the calls,
;; vectors, OSBYTE and OSWORD numbers, and describe the workspace that MosEquates.asm names. Other labels are named
;; after what the code does.
;;
;; Maintained by hand. BbcMosSourceTests check that it assembles byte-identically to MOS 1.20.

.cpu Mos6502

.include "MosEquates.asm"

.org $C000

.include "Mos/Font.asm"
.include "Mos/Vdu.asm"
.include "Mos/Graphics.asm"
.include "Mos/Reset.asm"
.include "Mos/Commands.asm"
.include "Mos/OsByte.asm"
.include "Mos/Keyboard.asm"
.include "Mos/Cassette.asm"
.include "Mos/CassetteFiles.asm"
.include "Mos/Vectors.asm"
