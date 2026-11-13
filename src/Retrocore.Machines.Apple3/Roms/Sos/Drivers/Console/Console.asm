;; SOS .CONSOLE DRIVER
;;
;; The Apple III's console driver for SOS: the keyboard and the text screen as one character device, .CONSOLE. It is
;; one of the drivers in SOS.DRIVER, which SOS relocates into memory at boot. Reading takes keystrokes from a
;; type-ahead buffer that the keyboard interrupt fills; writing puts characters in a text viewport and carries out
;; the screen control codes $00-$1F.
;;
;; The requests (<CREQSW>):
;;
;; - Read (0), <CNSLREAD>. In console mode it returns text, up to the count or the new-line character. With echo on
;;   it shows what is typed and lets the line be edited: Control-H deletes a character, Control-X the whole line, and
;;   the right arrow copies the character under the cursor from the screen. Escape starts escape mode, where letters
;;   and the arrow keys move the cursor, set the viewport and clear the screen. In keyboard mode it returns two bytes
;;   per key, the character and the keyboard's modifier byte, with no echo or editing.
;; - Write (1), <CNSLWRIT>: characters and control codes, through <PRINT>.
;; - Status (2) and control (3), <CNSLSTAT> and <CNSLCNTL>: the codes 0-18 in <CSTATSW> and <CCNTLSW>. They read and
;;   set the console state table, the new-line character, the mode, the buffer size, the attention and any-key events,
;;   the echo and editing switches and the cursor position; they read the screen, save and restore the viewport's
;;   contents, and download a whole character set (control 16) or up to eight characters (control 17).
;; - Open (6), close (7) and initialize (8), which SOS makes itself: <CNSLOPEN>, <CNSLCLOS> and <CNSLINIT>. Requests 4
;;   and 5, and any above 8, are errors.
;;
;; The keyboard interrupt, <KYBDMIH>, translates each key through the keyboard layout table at <XFORMTBL>, queues the
;; attention and any-key events, and buffers the key. With Control held, the special keys 5 to 9 are the console's
;; own commands, which take effect at once: 5 turns the video off or on, 6 empties the type-ahead buffer, 7 suspends
;; screen output until it is pressed again, 8 shows control characters instead of carrying them out, and 9 starts or
;; stops throwing screen output away.
;;
;; The device information block, <IDBLK>, names the device .CONSOLE, a character device of type $61, subtype $01, made
;; by Apple, version <RELEASE>, with no configuration block. What a program can configure is the console state table
;; (<CONSTTBL>), which control code 0 resets from <DFLTVAL>: console mode, echo and editing on, escape mode on, an 80
;; by 24 viewport in black and white with white text on black, scrolling, automatic return and automatic advance, and
;; no cursor until a read shows one.
;;
;; One source builds two releases of the driver. By default it builds 1.31, from the System Utilities disk. With
;; <RELEASE_130> set to 1 it builds 1.30, from the Business BASIC 1.23 disk, which differs only in its version number
;; and in how <VERIFY> sets the video switches.
;;
;; Labels follow Apple's listing, "Apple /// Console Driver 1.31 Source Code Listing"; the comments are our own.
;;
;; Maintained by hand; SOS driver tests check it assembles byte-identically to Apple's .CONSOLE 1.31 and 1.30.

.cpu Mos6502

;; Set to 1 to build release 1.30 of the driver, from the Business BASIC 1.23 disk; 0, the default, builds 1.31.
.ifndef RELEASE_130
RELEASE_130 = 0
.endif

DEVTYPE = $61                       ;; the device type in the DIB: a character device, the console
SUBTYPE = $01                       ;; the device subtype in the DIB
APPLE = $01                         ;; the manufacturer in the DIB: Apple

;; The driver's version in the DIB, in BCD: $1310 for 1.31, $1300 for 1.30.
.if RELEASE_130
RELEASE = $1300
.else
RELEASE = $1310
.endif

;; Jumps through a table of routine addresses, indexed by a value from 0 to 127.
;;
;; The table holds each routine's address less one, which the macro pushes so that an RTS enters it. With a bound,
;; an index above it skips the jump and leaves carry set. With * as the fourth argument the macro only pushes the
;; address, so the caller can do more before its own RTS jumps there.
;; Parameters: p1 = where to load the index from, or blank when it is already in A,
;;   p2 = the highest valid index, or blank for no check, p3 = the table, p4 = * to push without jumping
;; Uses: A, Y
.macro SWITCH p1, p2, p3, p4
    .ifnblank p1
    lda p1
    .endif
    .ifnblank p2
    cmp #<(p2+$01)
    bcs :+
    .endif
    asl a
    tay
    lda p3+$01,y
    pha
    lda p3,y
    pha
    .if .not .xmatch({p4}, {*})
    rts
    .endif
    .ifnblank p2
:
    .endif
.endmacro

    .include "ConsDat1.asm"
    .include "ConsDat2.asm"
    .include "ConsDat3.asm"
    .include "ConsMain.asm"
    .include "ConsRead.asm"
    .include "ConsWrit.asm"
    .include "ConsFctn.asm"
    .include "ConsStat.asm"
    .include "ConsCntl.asm"
    .include "ConsDnld.asm"
    .include "ConsMisc.asm"
    .include "ConsUtl1.asm"
    .include "ConsUtl2.asm"
