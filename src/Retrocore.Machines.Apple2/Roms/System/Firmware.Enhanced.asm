;; APPLE IIE INTERNAL FIRMWARE ($C100-$CFFF), ENHANCED IIE
;;
;; How the Enhanced IIe uses its internal $C100-$CFFF ROM, as far as the code shows:
;;   $C100-$C2FF  Monitor extensions. The Monitor's $FBB4 saves RDCXROM in the pushed flags, sets SETINTCXROM
;;                and jumps to $C100 with a function number in Y (see CXDISPATCH); the exit returns through
;;                the Monitor's $FEC5 (back to slot ROM) or $FEC8. Also the reset hook (RESETFW).
;;   $C300-$C3FF  Slot 3: BASICINT/BASICIN/BASICOUT for PR#3/IN#3, the Pascal 1.1 ID bytes and PASCALOFS
;;                ($C34A init, $C350 read, $C356 write, $C35C status), AUXMOVE, XFER, and the IRQ/BRK entry
;;                at $C3FA that the Monitor's IRQ vector code jumps to; it runs on into $C400.
;;   $C400-$C4FF  Interrupt bank-state save/restore and the mini-assembler's operand parser.
;;   $C500-$C5FF  The cassette routines behind the Monitor's HEADR, WRITE and READ, and the AppleSoft
;;                SHLOAD/STORE/RECALL helper at $C500 (called from AppleSoft's $F777).
;;   $C600-$C7FF  Self-test, run when the solid-apple key (BUTN1) is down at reset.
;;   $C800-$CFFF  80-column firmware: output, input with escape sequences, Pascal support, 40/80 screen
;;                conversion, and the rest of the mini-assembler ($CF3A-$CFFE). $C800, $C84D and $C9AA
;;                hold jumps to Pascal init/read/write code (apparently older Pascal entry points).
;; The 80-column state lives in text screen holes: $04FB mode bits, $057B cursor column, $05FB cursor row,
;; $047B the CH the firmware last set, $067B the current character, $06FB/$077B/$07FB scratch.
;; Several routines are reached only through computed RTS addresses (the dispatcher's CXFUNCTBL).
;;
;; Assembles byte-identically to the internal $C100-$CFFF ROM: the 80-column firmware in slot three's
;; space and $C800, and the routines the Monitor calls with internal ROM switched in. Names are Apple's
;; documented entry points; other labels are named after the routine they are in.
;; It includes IIeEquates.asm (the IIe's page zero, soft switches and keys), MonitorEntries.asm (the Monitor's
;; entry points) and FirmwareEquates.asm (the equates both firmware models share).
;;
;; Maintained by hand. The SystemSourceTests digests check that it assembles byte-identically.

.cpu Rockwell65C02

; Apple II text has bit 7 set, so this source's characters and strings assemble that way.
.repeat 128, character
.charmap character, character | $80
.endrepeat

; The IIe's page zero, soft switches and keys, the Monitor's entry points, and the equates both firmware models share.
.include "IIeEquates.asm"
.include "MonitorEntries.asm"
.include "FirmwareEquates.asm"

; AppleSoft's page zero, for the cassette and SHLOAD/STORE/RECALL helpers.
;; Applesoft's line number, which the cassette helper borrows for a length: of a shape table, or of an array.
;;
;; <BASTAPE> reads a shape table's two-byte length from the tape into <LINNUM>/<LINNUM>+1 for SHLOAD, and
;; <TAPEARRAY> adds an array's length, which Applesoft leaves here, to its address for STORE and RECALL.
;; See: <AppleSoft:LINNUM>, <BASTAPE>, <TAPEARRAY>
LINNUM = $50

;; Applesoft's end of the variables and arrays, the lowest address strings may grow down to.
;;
;; <BASTAPE> refuses a shape table that would reach below it, returning carry set so that Applesoft reports
;; that memory is full.
;; See: <AppleSoft:STREND>, <BASTAPE>, <MEMSIZ>
STREND = $6D

;; Applesoft's bottom of string space, where the next string is stored, just below the strings in use.
;;
;; <TAPESHLOAD> moves it down with HIMEM, <MEMSIZ>, to make room for the shape table it loads.
;; See: <AppleSoft:FRETOP>, <MEMSIZ>, <TAPESHLOAD>
FRETOP = $6F

;; Applesoft's HIMEM, the address just above the memory it uses.
;;
;; <BASTAPE> checks that a shape table fits below it, and <TAPESHLOAD> lowers it by the table's length and
;; loads the table there.
;; See: <AppleSoft:MEMSIZ>, <FRETOP>, <SHAPEPTR>, <TAPESHLOAD>
MEMSIZ = $73

;; Applesoft's block pointer, which the STORE and RECALL helper takes as the start of the array's data.
;;
;; <TAPEARRAY> copies it, as Applesoft's routine at $E0EF leaves it, to <A1L>/<A1H>, the start of the block the
;; Monitor then writes or reads.
;; See: <AppleSoft:HIGHDS>, <TAPEARRAY>, <LOWTR>
HIGHDS = $94

;; Applesoft's pointer to the array that STORE or RECALL names, from its search for the array.
;;
;; <TAPEARRAY> adds the array's length in <LINNUM> to it for <A2L>/<A2H>, the end of the block on tape, and
;; reads the header's fifth byte through it.
;; See: <AppleSoft:LOWTR>, <TAPEARRAY>, <HIGHDS>
LOWTR = $9B

;; Applesoft's pointer to the shape table that DRAW and XDRAW use.
;;
;; <TAPESHLOAD> sets it to the address where it loads the shape table, just below the new HIMEM.
;; See: <AppleSoft:SHPTBL>, <TAPESHLOAD>, <MEMSIZ>
SHAPEPTR = $E8

; A Monitor entry point not in MonitorEntries.asm, since DOS has a routine of its own by the name.
;; Inherit: <Monitor:GETNUM>
GETNUM = $FFA7

; Control codes with bit 7 clear, as DOCTRL and the Pascal entries take them.
CTRL_D = $04                        ;; Control-D: ESC Control-D disables control characters ($04FB bit 5)
CTRL_E = $05                        ;; Control-E: Pascal shows the cursor; ESC Control-E enables control characters
CTRL_F = $06                        ;; Control-F: Pascal hides the cursor
CTRL_G = $07                        ;; Control-G: bell
CTRL_H = $08                        ;; Control-H: cursor left (backspace)
CTRL_J = $0A                        ;; Control-J: cursor down (line feed)
CTRL_K = $0B                        ;; Control-K: clear to the end of the screen
CTRL_L = $0C                        ;; Control-L: clear the screen
CTRL_M = $0D                        ;; Control-M: return
CTRL_N = $0E                        ;; Control-N: normal text
CTRL_O = $0F                        ;; Control-O: inverse text
CTRL_Q = $11                        ;; Control-Q: 40 columns; ESC Control-Q quits the 80-column firmware
CTRL_R = $12                        ;; Control-R: 80 columns
CTRL_U = $15                        ;; Control-U: quit the 80-column firmware
CTRL_V = $16                        ;; Control-V: scroll down
CTRL_W = $17                        ;; Control-W: scroll up
CTRL_X = $18                        ;; Control-X: MouseText off
CTRL_Y = $19                        ;; Control-Y: home the cursor
CTRL_Z = $1A                        ;; Control-Z: clear the line
CTRL_ESC = $1B                      ;; Escape as a control code: MouseText on
CTRL_BACKSLASH = $1C                ;; Control-\: cursor right
CTRL_RBRACKET = $1D                 ;; Control-]: clear to the end of the line
CTRL_CARET = $1E                    ;; Pascal GOTOXY
CTRL_UNDERSCORE = $1F               ;; Control-_: cursor up

.org $C100

.include "Firmware.Enhanced/Functions.asm"
.include "Firmware.Enhanced/SlotEntry.asm"
.include "Firmware.Enhanced/Interrupts.asm"
.include "Firmware.Enhanced/SelfTest.asm"
.include "Firmware.Enhanced/EightyColumnsEntry.asm"
.include "Firmware.Enhanced/EightyColumnsControl.asm"
.include "Firmware.Enhanced/EightyColumnsScreen.asm"
.include "Firmware.Enhanced/EightyColumnsMode.asm"
