; retrocore: style=strict
;; APPLE IIE INTERNAL FIRMWARE ($C100-$CFFF): THE FUNCTION NUMBERS
;;
;; The numbers of the functions the IIe's Monitor has the internal firmware run: the Monitor loads one into Y and
;; jumps to <Monitor:CallFirmware>, which switches the internal ROM in and enters the firmware at $C100. The two
;; models number the functions differently, so ENHANCED picks the set. The Monitor and both models' firmware include
;; this file, so the caller and the handler use the same number.

; The .asserts that tie each number to its handler's place in the firmware's dispatch tables are in the tables
; themselves (the FunctionHandler and Handler macros).
.if ENHANCED

;; The firmware function that prints a character in 80 columns, for <Monitor:ScreenOutByWidth>: 0 on the Enhanced IIe.
FIRMWARE_OUTPUT = $00

;; The firmware function that translates a key read in escape mode, for <Monitor:Escape::ReadEscapeKey>: 1 on the
;; Enhanced IIe.
FIRMWARE_ESCAPE_KEY = $01

;; The firmware function that computes the base address of a line, without the window's left edge: 2 on the
;; Enhanced IIe. The Monitor does not call it.
FIRMWARE_ROW_BASE = $02

;; The firmware function that waits for a key, as <Monitor:KeyboardIn> does: 3 on the Enhanced IIe.
FIRMWARE_KEYBOARD_IN = $03

;; The firmware function that sets <TextBase>/<TextBaseHigh> for a line, as <Monitor:SetLineBase> does: 4 on the
;; Enhanced IIe.
FIRMWARE_LINE_BASE = $04

;; The firmware function that clears the window and homes the cursor, as <Monitor:Home> does: 5 on the Enhanced IIe.
FIRMWARE_HOME = $05

;; The firmware function that scrolls the window up a line, as <Monitor:Scroll> does: 6 on the Enhanced IIe.
FIRMWARE_SCROLL = $06

;; The firmware function that clears from the cursor to the end of the line, as <Monitor:ClearToEndOfLine> does: 7
;; on the Enhanced IIe.
FIRMWARE_CLEAR_TO_END_OF_LINE = $07

;; The firmware function that clears from a column to the end of the line, as <Monitor:ClearLineFrom> does: 8 on the
;; Enhanced IIe.
FIRMWARE_CLEAR_LINE_FROM = $08

;; The firmware function that resets its state on a reset: 9 on the Enhanced IIe.
FIRMWARE_RESET = $09

;; The firmware function that clears from the cursor to the end of the window, as <Monitor:ClearToEndOfWindow> does:
;; $0A on the Enhanced IIe.
FIRMWARE_CLEAR_TO_END_OF_WINDOW = $0A

;; The firmware function that shows the cursor, in 40 or 80 columns, before <Monitor:ReadKey> reads a key: $0B on the
;; Enhanced IIe.
FIRMWARE_READ_KEY = $0B

;; The firmware function that sets the window's width and bottom for 40 or 80 columns and moves the cursor to the
;; bottom line: $0C on the Enhanced IIe.
FIRMWARE_SET_WINDOW = $0C

;; The firmware function that runs the mini-assembler for a line: the Enhanced IIe's "!" command, $0D.
FIRMWARE_MINI_ASSEMBLER = $0D

;; The firmware function that finishes a hook that <Monitor:SetHook> stored: the Enhanced IIe's page for slot 0,
;; and the 80-column firmware's hooks. $0E on the Enhanced IIe.
FIRMWARE_SET_HOOK = $0E

;; The firmware function that gets the character under the 80-column cursor, with its high bit set: $0F on the
;; Enhanced IIe.
FIRMWARE_CHARACTER_UNDER_CURSOR = $0F

;; The firmware function that finishes <Monitor:Disassembler::Decode>: the operand's length and the mnemonic hash.
;; $10 on the Enhanced IIe.
FIRMWARE_DECODE = $10
.else

;; The firmware function that clears from the cursor to the end of the window, as <Monitor:ClearToEndOfWindow> does:
;; 0 on the original IIe.
FIRMWARE_CLEAR_TO_END_OF_WINDOW = $00

;; The firmware function that clears the window and homes the cursor, as <Monitor:Home> does: 1 on the original IIe.
FIRMWARE_HOME = $01

;; The firmware function that scrolls the window up a line, as <Monitor:Scroll> does: 2 on the original IIe.
FIRMWARE_SCROLL = $02

;; The firmware function that clears from the cursor to the end of the line, as <Monitor:ClearToEndOfLine> does: 3
;; on the original IIe.
FIRMWARE_CLEAR_TO_END_OF_LINE = $03

;; The firmware function that clears from a column to the end of the line, as <Monitor:ClearLineFrom> does: 4 on the
;; original IIe.
FIRMWARE_CLEAR_LINE_FROM = $04

;; The firmware function that resets its state on a reset: 5 on the original IIe.
FIRMWARE_RESET = $05

;; The firmware function that waits for a key, as <Monitor:KeyboardIn> does: 6 on the original IIe.
FIRMWARE_KEYBOARD_IN = $06

;; The firmware function that translates a key read in escape mode, for <Monitor:Escape::ReadEscapeKey>: 7 on the
;; original IIe.
FIRMWARE_ESCAPE_KEY = $07

;; The firmware function that sets the window's width and bottom for 40 or 80 columns and moves the cursor to the
;; bottom line: 8 on the original IIe.
FIRMWARE_SET_WINDOW = $08
.endif
