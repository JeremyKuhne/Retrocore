;; THE VECTORS ($E400-$E4A5)
;;
;; The fixed addresses programs call the OS through: the vector tables of the five resident CIO handlers (E:, S:, K:,
;; P: and C:) at $E400-$E44F, the documented jump vectors at $E450-$E47F, and the defaults of page two's interrupt
;; vectors at $E480, which the OS copies to VDSLST-VVBLKD at start-up.

; The layout of a handler's vector table: six routines' addresses, each less 1 because CIO calls them by pushing the
; address and returning to it, then a JMP to the handler's initialization and a pad byte.

HANDLER_OPEN = $00                  ;; the offset of a handler's OPEN routine's address, less 1, in its vector table
HANDLER_CLOSE = $02                 ;; the offset of its CLOSE routine's address, less 1
HANDLER_GET = $04                   ;; the offset of its GET BYTE routine's address, less 1
HANDLER_PUT = $06                   ;; the offset of its PUT BYTE routine's address, less 1
HANDLER_STATUS = $08                ;; the offset of its STATUS routine's address, less 1
HANDLER_SPECIAL = $0A               ;; the offset of its SPECIAL routine's address, less 1, for commands $0E up
HANDLER_INIT = $0C                  ;; the offset of the JMP to its initialization (the address itself, not less 1)
HANDLER_TABLE_SIZE = $10            ;; the size of a resident handler's vector table, with its pad byte

; Rev. A and the PAL OS keep the checksum of the chip at $E000-$EFFF in the first two tables' pad bytes: the 16-bit
; sum of the chip's other bytes, its low byte at $E40F and its high byte at $E41F. Rev. B leaves both pads 0.

.if VERSION = VERSION_A
CHECKSUM_E000 = $F638               ;; the sum of $E000-$EFFF's bytes, the checksum's two excepted
.elseif VERSION = VERSION_PAL
CHECKSUM_E000 = $F6F9               ;; the sum of $E000-$EFFF's bytes, the checksum's two excepted
.else
CHECKSUM_E000 = $0000               ;; none: rev. B's pads are 0
.endif

;; Emits the six routine addresses of a handler's vector table, each less 1 for CIO's push-and-return call.
;; Parameters: open = the OPEN routine, close = the CLOSE routine, get = the GET BYTE routine, put = the PUT BYTE
;;   routine, status = the STATUS routine, special = the SPECIAL routine
;; See: <HANDLER_OPEN>, <CIO_CALL_HANDLER>
.macro HANDLER_VECTORS open, close, get, put, status, special
    .word open-1, close-1, get-1, put-1, status-1, special-1
.endmacro

;; The screen editor's (E:) vector table, which HATABS lists for E:.
;;
;; Its GET BYTE reads a logical line from the keyboard, echoing it; its PUT BYTE writes through the display; and its
;; SPECIAL does nothing, so CIO returns FNCNOT for it. STATUS and CLOSE share one routine. The start-up code calls
;; the initialization through EDITRV+HANDLER_INIT, as it does every handler's.
;; See: <HATABS>, <EDITOR_INIT>
EDITRV:
    HANDLER_VECTORS EDITOR_OPEN, DISPLAY_RETURN, EDITOR_GET, EDITOR_PUT, DISPLAY_RETURN, DISPLAY_IGNORE
    jmp EDITOR_INIT
    .byte <CHECKSUM_E000            ; pad: the checksum's low byte in rev. A and PAL

;; The display handler's (S:) vector table, which HATABS lists for S:.
;;
;; OPEN sets up a graphics mode from ICAX1 and ICAX2, GET BYTE and PUT BYTE read and plot at the cursor, and SPECIAL
;; runs DRAWTO ($11) and FILL ($12). It shares the screen editor's initialization.
;; See: <HATABS>, <SCREEN_SPECIAL>
SCRENV:
    HANDLER_VECTORS DISPLAY_OPEN, DISPLAY_RETURN, DISPLAY_GET, DISPLAY_PUT, DISPLAY_RETURN, SCREEN_SPECIAL
    jmp EDITOR_INIT
    .byte >CHECKSUM_E000            ; pad: the checksum's high byte in rev. A and PAL

;; The keyboard handler's (K:) vector table, which HATABS lists for K:.
;;
;; Only GET BYTE does anything: OPEN, CLOSE and STATUS share the screen editor's routine, which returns the display
;; handler's status, and PUT BYTE and SPECIAL return at once, so CIO reports FNCNOT for them.
;; See: <HATABS>, <KEYBOARD_GET>
KEYBDV:
    HANDLER_VECTORS DISPLAY_RETURN, DISPLAY_RETURN, KEYBOARD_GET, DISPLAY_IGNORE, DISPLAY_RETURN, DISPLAY_IGNORE
    jmp EDITOR_INIT
    .byte $00                       ; pad

;; The printer handler's (P:) vector table, which HATABS lists for P:.
;;
;; GET BYTE and SPECIAL return at once, so CIO reports FNCNOT for them.
;; See: <HATABS>, <PRINTER_INIT>
PRINTV:
    HANDLER_VECTORS PRINTER_OPEN, PRINTER_CLOSE, PRINTER_STATUS_DONE, PRINTER_PUT, PRINTER_STATUS, PRINTER_STATUS_DONE
    jmp PRINTER_INIT
    .byte $00                       ; pad

;; The cassette handler's (C:) vector table, which HATABS lists for C:.
;;
;; SPECIAL returns at once, so CIO reports FNCNOT for it.
;; See: <HATABS>, <CASSETTE_INIT>
CASETV:
    HANDLER_VECTORS CASSETTE_OPEN, CASSETTE_CLOSE, CASSETTE_GET, CASSETTE_PUT, CASSETTE_STATUS, CASSETTE_SPECIAL
    jmp CASSETTE_INIT
    .byte $00                       ; pad

    .assert EDITRV = $E400, "The screen editor's vectors are at $E400."
    .assert SCRENV = EDITRV + HANDLER_TABLE_SIZE, "The display handler's vectors are at $E410."
    .assert KEYBDV = SCRENV + HANDLER_TABLE_SIZE, "The keyboard handler's vectors are at $E420."
    .assert PRINTV = KEYBDV + HANDLER_TABLE_SIZE, "The printer handler's vectors are at $E430."
    .assert CASETV = PRINTV + HANDLER_TABLE_SIZE, "The cassette handler's vectors are at $E440."

;; Initializes the disk handler (an OS-internal vector).
;; See: <DISK_INIT>
DISKIV:
    jmp DISK_INIT

;; Reads or writes a disk sector, or gets a drive's status, as the device control block says.
;; See: <DISK_HANDLER>, <DDEVIC>
DSKINV:
    jmp DISK_HANDLER

;; CIO's entry: carries out the command in the IOCB that X selects.
;; See: <CIO_MAIN>
CIOV:
    jmp CIO_MAIN

;; SIO's entry: carries out the serial bus operation the device control block describes.
;; See: <SIO_MAIN>, <DDEVIC>
SIOV:
    jmp SIO_MAIN

;; Sets a system timer, or the vertical blank vectors, safely during a vertical blank.
;; See: <SET_VBLANK_VECTOR>
SETVBV:
    jmp SET_VBLANK_VECTOR

;; The vertical blank's first stage, which VVBLKI points to by default; a program's own VVBLKI routine jumps here when
;; it is done.
;; See: <SYSTEM_VBLANK>, <VVBLKI>
SYSVBV:
    jmp SYSTEM_VBLANK

;; The vertical blank's exit, which VVBLKD points to by default; a program's own VVBLKD routine jumps here when it is
;; done.
;; See: <EXIT_VBLANK>, <VVBLKD>
XITVBV:
    jmp EXIT_VBLANK

;; Initializes SIO (an OS-internal vector).
;; See: <SIO_INIT>
SIOINV:
    jmp SIO_INIT

;; Enables POKEY's serial output interrupts to send (an OS-internal vector).
;; See: <SIO_SEND_ENABLE>
SENDEV:
    jmp SIO_SEND_ENABLE

;; Initializes the interrupt handlers' hardware: the PIA and the NMIs (an OS-internal vector).
;; See: <INIT_INTERRUPTS>
INTINV:
    jmp INIT_INTERRUPTS

;; Initializes CIO, marking every IOCB closed (an OS-internal vector).
;; See: <CIO_INIT>
CIOINV:
    jmp CIO_INIT

;; The blackboard (memo pad) mode, which reads and echoes lines from the screen editor for ever.
;;
;; The start-up code reads this JMP's operand, at BLKBDV+1, to point DOSVEC at the memo pad when nothing else
;; booted.
;; See: <MEMO_PAD>, <DOSVEC>
BLKBDV:
    jmp MEMO_PAD

;; The warm start, as SYSTEM RESET does.
;; See: <WARM_START>
WARMSV:
    jmp WARM_START

;; The cold start, as power-up does; the 6502's reset vector points here.
;; See: <COLD_START>
COLDSV:
    jmp COLD_START

;; Reads a block from the cassette (an OS-internal vector).
;; See: <CASSETTE_READ_BLOCK>
RBLOKV:
    jmp CASSETTE_READ_BLOCK

;; Opens the cassette for reading (an OS-internal vector), as the cassette boot does.
;; See: <CASSETTE_OPEN_READ>
CSOPIV:
    jmp CASSETTE_OPEN_READ

    .assert DISKIV = $E450, "DISKIV is at $E450."
    .assert DSKINV = $E453, "DSKINV is at $E453."
    .assert CIOV = $E456, "CIOV is at $E456."
    .assert SIOV = $E459, "SIOV is at $E459."
    .assert SETVBV = $E45C, "SETVBV is at $E45C."
    .assert SYSVBV = $E45F, "SYSVBV is at $E45F."
    .assert XITVBV = $E462, "XITVBV is at $E462."
    .assert SIOINV = $E465, "SIOINV is at $E465."
    .assert SENDEV = $E468, "SENDEV is at $E468."
    .assert INTINV = $E46B, "INTINV is at $E46B."
    .assert CIOINV = $E46E, "CIOINV is at $E46E."
    .assert BLKBDV = $E471, "BLKBDV is at $E471."
    .assert WARMSV = $E474, "WARMSV is at $E474."
    .assert COLDSV = $E477, "COLDSV is at $E477."
    .assert RBLOKV = $E47A, "RBLOKV is at $E47A."
    .assert CSOPIV = $E47D, "CSOPIV is at $E47D."

;; The defaults of page two's interrupt vectors and system timers, VDSLST-VVBLKD, which the start-up code copies there.
;;
;; The handlers that do nothing return at once: the display list interrupt's with an RTI, the IRQ sources' with a PLA
;; and an RTI, since the IRQ handler pushed A before dispatching. The timers start stopped, at zero.
;; See: <VDSLST>, <VVBLKD>
DEFAULT_INTERRUPT_VECTORS:
    .word IGNORE_NMI                ; VDSLST: none, an RTI
    .word IGNORE_IRQ                ; VPRCED: none
    .word IGNORE_IRQ                ; VINTER: none
    .word IGNORE_IRQ                ; VBREAK: none
    .word KEYBOARD_IRQ              ; VKEYBD: the keyboard
    .word SIO_INPUT_READY           ; VSERIN: SIO's serial input
    .word SIO_OUTPUT_NEEDED         ; VSEROR: SIO's serial output
    .word SIO_OUTPUT_FINISHED       ; VSEROC: SIO's serial output finished
    .word IGNORE_IRQ                ; VTIMR1: none
    .word IGNORE_IRQ                ; VTIMR2: none
    .word IGNORE_IRQ                ; VTIMR4: none
    .word IRQ_HANDLER               ; VIMIRQ: the IRQ handler
    .word 0, 0, 0, 0, 0             ; CDTMV1-CDTMV5: stopped
    .word SYSTEM_VBLANK             ; VVBLKI: the first stage, as SYSVBV
    .word EXIT_VBLANK               ; VVBLKD: the exit
    .assert * - DEFAULT_INTERRUPT_VECTORS = VVBLKD + 2 - VDSLST, "The defaults cover VDSLST-VVBLKD."
