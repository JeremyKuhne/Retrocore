; retrocore: style=strict
;; The TRS-80's keyboard and screen, and Level II's documented ROM calls
;;
;; A project includes it as <machine.inc> on a TRS-80 with Level II: the Model I with Level II, and the Model III and
;; Model 4, whose ROM is Level II with its device drivers rewritten. The keyboard's matrix is read at $3800, a row for
;; each address bit, and the screen is 64 columns by 16 rows of video RAM from $3C00. The ROM's first page holds the
;; calls Radio Shack documented for programs, at the same address on each model; each inherits Level II's documentation
;; and keeps the name it is usually known by. The keyboard scan, display and printer calls pass through the ROM's device
;; control blocks, so a DOS can redirect them, and the key wait through the keyboard scan.

;; 1 when the target's ROM is Level II's: the Model I's with Level II, or the Model III's, which the Model 4 shares;
;; else 0. The Model 4P has only a boot ROM, which loads the Model III's from a disk.
LEVEL2_ROM = .defined(RC_MODEL_TRS80_MODEL1_LEVEL2) | .defined(RC_MODEL_TRS80_MODEL3) | .defined(RC_MODEL_TRS80_MODEL4)

.assert LEVEL2_ROM, "machine.inc for the TRS-80 is for its Level II ROMs."

; The hardware.

;; Inherit: <Level2:KEYBOARD>
;; Also: KEYBOARD (UNKN)
KeyboardMatrix = $3800

;; Inherit: <Level2:VIDEO>
;; Also: VIDEO (UNKN)
VideoRam = $3C00

;; The screen's width, in characters.
SCREEN_COLUMNS = 64

;; The screen's height, in rows.
SCREEN_ROWS = 16

; Level II's documented calls.

;; Inherit: <Level2:KBD_SCAN>
;; Also: KBD_SCAN (UNKN)
KeyboardScan = $002B

;; Inherit: <Level2:DISPLAY_CHAR>
;; Also: DISPLAY_CHAR (UNKN)
DisplayCharacter = $0033

;; Inherit: <Level2:PRINTER_CHAR>
;; Also: PRINTER_CHAR (UNKN)
PrinterCharacter = $003B

;; Inherit: <Level2:KBLINE>
;; Also: KBLINE (UNKN)
KeyboardLine = $0040

;; Inherit: <Level2:KBWAIT>
;; Also: KBWAIT (UNKN)
KeyboardWait = $0049

;; Inherit: <Level2:DELAY>
;; Also: DELAY (UNKN)
Delay = $0060

; Characters.

;; The character <DisplayCharacter> takes as Return, which ends a line, and <KeyboardWait> gives for ENTER.
RETURN = $0D
