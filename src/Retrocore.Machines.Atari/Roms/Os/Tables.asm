;; THE DISPLAY HANDLER'S, EDITOR'S AND KEYBOARD'S TABLES ($FE45-$FFBD)
;;
;; The display modes' tables, one byte for each GRAPHICS mode 0-11 in each: the memory a screen takes, its display
;; list's lines, ANTIC's mode, its rows and columns, and how a column becomes a byte and a pixel. Then the pixel
;; masks, the default colours, the screen editor's control codes, the conversions between ATASCII and the internal
;; character code, and the keyboard's definition, the ATASCII character for each key code.

; The display modes and the control codes.

MODE_COUNT = 12                     ;; the GRAPHICS modes the display handler opens, 0-11
CONTROL_CODE_COUNT = 16             ;; the control codes in CONTROL_CODES

; The key handler's codes in KEYBOARD_DEFINITIONS that are not characters.

KEYDEF_NONE = $80                   ;; no character: the key, or its combination with SHIFT or CTRL, is ignored
KEYDEF_INVERSE = $81                ;; the Atari key, which toggles inverse video (INVFLG)
KEYDEF_LOWER = $82                  ;; CAPS/LOWR, which selects lower case (SHFLOK = 0)
KEYDEF_UPPER = $83                  ;; SHIFT+CAPS/LOWR, which selects upper case (SHFLOK = $40)
KEYDEF_CONTROL = $84                ;; CTRL+CAPS/LOWR, which locks CTRL on (SHFLOK = $80)
KEYDEF_END_OF_FILE = $85            ;; CTRL+3, which ends the input with an end-of-file status

;; The screen memory each display mode takes, in 40-byte units, which the screen's open reserves below RAMTOP.
;;
;; GRAPHICS 0 takes its 24 lines. Each other mode takes its rows of pixels and 160 bytes more for a split screen's
;; text window, whether or not it is split; GRAPHICS 8-11 also reserve 16 bytes more, so that the 4K boundary the
;; screen crosses falls between two lines.
;; See: <MODE_LINE_SHIFTS>, <MODE_ROWS>
MODE_MEMORY_SIZES:
    .byte 24, 16, 10, 10, 16, 28, 52, 100, 196, 196, 196, 196   ; GRAPHICS 0-11
    .assert * - MODE_MEMORY_SIZES = MODE_COUNT, "Each display mode has a size."

;; The number of mode lines in each display mode's display list after the first one, which loads the screen's
;; address, for a full screen and then (from offset MODE_COUNT) for a split screen.
;;
;; GRAPHICS 8-11 load the address again at the 4K boundary, after 93 more lines; their counts are the lines after
;; that. A split screen's four text lines follow these.
;; See: <MODE_ANTIC_CODES>
MODE_LINE_COUNTS:
    .byte 23, 23, 11, 23, 47, 47, 95, 95, 97, 97, 97, 97        ; full screen, GRAPHICS 0-11
    .byte 19, 19, 9, 19, 39, 39, 79, 79, 65, 65, 65, 65         ; split screen
    .assert * - MODE_LINE_COUNTS = 2 * MODE_COUNT, "Each display mode has two line counts."

;; ANTIC's mode for each display mode, the instruction its display list repeats; 0 for none.
;;
;; GRAPHICS 9-11 are ANTIC's mode $F, with GTIA's modes selected in PRIOR (GPRIOR).
MODE_ANTIC_CODES:
    .byte $02, $06, $07, $08, $09, $0A, $0B, $0D, $0F, $0F, $0F, $0F   ; GRAPHICS 0-11
    .assert * - MODE_ANTIC_CODES = MODE_COUNT, "Each display mode has an ANTIC mode."

;; Nonzero for the display modes whose display list starts at the end of a fresh page, below the screen's, so that
;; the longer list doesn't cross a 1K boundary, which ANTIC can't follow.
MODE_LIST_PAGES:
    .byte 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1                    ; GRAPHICS 0-11
    .assert * - MODE_LIST_PAGES = MODE_COUNT, "Each display mode has a page flag."

;; How far to shift 10 left for each display mode's bytes per line: 40 for 2, 20 for 1 and 10 for 0.
;; See: <SCREEN_LOCATE>
MODE_LINE_SHIFTS:
    .byte 2, 1, 1, 0, 0, 1, 1, 2, 2, 2, 2, 2                    ; GRAPHICS 0-11
    .assert * - MODE_LINE_SHIFTS = MODE_COUNT, "Each display mode has a line length."

;; The number of columns in each display mode, the low byte for GRAPHICS 8's 320.
;; See: <SCREEN_CHECK_CURSOR>, <SCREEN_ADVANCE>
MODE_COLUMNS:
    .byte 40, 20, 20, 40, 80, 80, 160, 160, <320, 80, 80, 80     ; GRAPHICS 0-11
    .assert * - MODE_COLUMNS = MODE_COUNT, "Each display mode has a column count."

;; The number of rows in each display mode, for a full screen.
;; See: <SCREEN_CHECK_CURSOR>, <SCREEN_NEW_LINE>
MODE_ROWS:
    .byte 24, 24, 12, 24, 48, 48, 96, 96, 192, 192, 192, 192    ; GRAPHICS 0-11
    .assert * - MODE_ROWS = MODE_COUNT, "Each display mode has a row count."

;; How far to shift a column right for its byte in the line in each display mode: 0 for one character or pixel a
;; byte, 1 for two pixels, 2 for four and 3 for eight.
;; See: <SCREEN_LOCATE>, <PIXEL_MASKS>
MODE_PIXEL_SHIFTS:
    .byte 0, 0, 0, 2, 3, 2, 3, 2, 3, 1, 1, 1                    ; GRAPHICS 0-11
    .assert * - MODE_PIXEL_SHIFTS = MODE_COUNT, "Each display mode has a pixel shift."

;; The masks of a pixel in its byte, indexed by 2 to the power of the mode's pixel shift, plus the pixel's place in
;; the byte from the left.
;;
;; The first entry is unused; then one pixel a byte, two, four and eight. The eight one-bit masks are also
;; <BIT_MASKS>.
;; See: <SCREEN_LOCATE>, <MODE_PIXEL_SHIFTS>
PIXEL_MASKS:
    .byte %00000000                     ; unused
    .byte %11111111                     ; one pixel a byte
    .byte %11110000, %00001111          ; two pixels
    .byte %11000000, %00110000, %00001100, %00000011   ; four pixels

;; The masks of each bit of a byte, from bit 7 down to bit 0: the last eight <PIXEL_MASKS>, for eight pixels a
;; byte, and the masks of TABMAP's and LOGMAP's bits.
;; See: <SCREEN_MAP_POSITION>
BIT_MASKS:
    .byte %10000000, %01000000, %00100000, %00010000
    .byte %00001000, %00000100, %00000010, %00000001

;; The colours the screen's open puts in COLOR0-COLOR4: orange, light green, dark blue, red and black.
DEFAULT_COLOURS:
    .byte $28, $CA, $94, $46, $00

;; A control code the screen editor obeys: its ATASCII character and the address of the routine that obeys it.
;; Parameters:
;;   character = the ATASCII character
;;   routine = the routine's address, which the editor jumps to through ADRESS
.macro CONTROL_CODE character, routine
    .byte character
    .word routine
.endmacro

;; The control codes the screen editor obeys, unless ESC came before or DSPFLG is set, each a <CONTROL_CODE>.
;;
;; <SCREEN_FIND_CONTROL_CODE> searches it; the editor jumps to the routine with the character in ATACHR.
;; See: <SCREEN_FIND_CONTROL_CODE>
CONTROL_CODES:
    CONTROL_CODE $1B, EDIT_ESCAPE        ; ESC: show the next character rather than obey it
    CONTROL_CODE $1C, EDIT_CURSOR_UP        ; cursor up
    CONTROL_CODE $1D, EDIT_CURSOR_DOWN        ; cursor down
    CONTROL_CODE $1E, EDIT_CURSOR_LEFT        ; cursor left
    CONTROL_CODE $1F, EDIT_CURSOR_RIGHT        ; cursor right
    CONTROL_CODE $7D, EDIT_CLEAR_SCREEN        ; clear the screen
    CONTROL_CODE $7E, EDIT_BACKSPACE        ; backspace
    CONTROL_CODE $7F, EDIT_TAB        ; tab
    CONTROL_CODE $9B, SCREEN_NEW_LINE_EOL   ; EOL
    CONTROL_CODE $9C, EDIT_DELETE_LINE        ; delete the line
    CONTROL_CODE $9D, EDIT_INSERT_LINE        ; insert a line
    CONTROL_CODE $9E, EDIT_CLEAR_TAB        ; clear a tab stop
    CONTROL_CODE $9F, EDIT_SET_TAB        ; set a tab stop
    CONTROL_CODE $FD, EDIT_BELL        ; the bell
    CONTROL_CODE $FE, EDIT_DELETE_CHARACTER        ; delete the character
    CONTROL_CODE $FF, EDIT_INSERT_CHARACTER        ; insert a space
    .assert * - CONTROL_CODES = 3 * CONTROL_CODE_COUNT, "Each control code has a character and a routine."

;; What to OR into an ATASCII character, with its bits 5 and 6 cleared, for its internal code, indexed by those two
;; bits: $00-$1F become $40-$5F, $20-$3F become $00-$1F, $40-$5F become $20-$3F, and $60-$7F stay.
;; See: <INTERNAL_TO_ATASCII>
ATASCII_TO_INTERNAL:
    .byte $40, $00, $20, $60

;; What to OR into an internal code, with its bits 5 and 6 cleared, for its ATASCII character, indexed by those two
;; bits: the reverse of <ATASCII_TO_INTERNAL>.
;; See: <SCREEN_TO_ATASCII>
INTERNAL_TO_ATASCII:
    .byte $20, $40, $00, $60

;; The keyboard's definition: the ATASCII character for each key code, 64 alone, then 64 with SHIFT, then 64 with
;; CTRL. The keyboard handler takes CTRL+SHIFT combinations as none.
;;
;; The key code's bits 0-5 are the key, bit 6 SHIFT and bit 7 CTRL. The keys, eight codes to a row, with (none)
;; for the codes no key gives:
;;
;; > $00: L J ; (none) (none) K + *
;; > $08: O (none) P U RETURN I - =
;; > $10: V (none) C (none) (none) B X Z
;; > $18: 4 (none) 3 6 ESC 5 2 1
;; > $20: , SPACE . N (none) M / ATARI
;; > $28: R (none) E Y TAB T W Q
;; > $30: 9 (none) 0 7 BACK-S 8 < >
;; > $38: F H D (none) CAPS/LOWR G S A
;;
;; The codes $80-$85 are the keyboard handler's own, <KEYDEF_NONE> to <KEYDEF_END_OF_FILE>. CTRL+1 never gets here:
;; the keyboard interrupt toggles SSFLAG for it.
KEYBOARD_DEFINITIONS:
    .byte $6C, $6A, $3B, $80, $80, $6B, $2B, $2A    ; l j ; none none k + *
    .byte $6F, $80, $70, $75, $9B, $69, $2D, $3D    ; o none p u EOL i - =
    .byte $76, $80, $63, $80, $80, $62, $78, $7A    ; v none c none none b x z
    .byte $34, $80, $33, $36, $1B, $35, $32, $31    ; 4 none 3 6 ESC 5 2 1
    .byte $2C, $20, $2E, $6E, $80, $6D, $2F, $81    ; , SPACE . n none m / INVERSE
    .byte $72, $80, $65, $79, $7F, $74, $77, $71    ; r none e y TAB t w q
    .byte $39, $80, $30, $37, $7E, $38, $3C, $3E    ; 9 none 0 7 BACKSPACE 8 < >
    .byte $66, $68, $64, $80, $82, $67, $73, $61    ; f h d none LOWER g s a
; With SHIFT.
    .byte $4C, $4A, $3A, $80, $80, $4B, $5C, $5E    ; L J : none none K \ ^
    .byte $4F, $80, $50, $55, $9B, $49, $5F, $7C    ; O none P U EOL I _ |
    .byte $56, $80, $43, $80, $80, $42, $58, $5A    ; V none C none none B X Z
    .byte $24, $80, $23, $26, $1B, $25, $22, $21    ; $ none # & ESC % " !
    .byte $5B, $20, $5D, $4E, $80, $4D, $3F, $81    ; [ SPACE ] N none M ? INVERSE
    .byte $52, $80, $45, $59, $9F, $54, $57, $51    ; R none E Y SET-TAB T W Q
    .byte $28, $80, $29, $27, $9C, $40, $7D, $9D    ; ( none ) ' DELETE-LINE @ CLEAR INSERT-LINE
    .byte $46, $48, $44, $80, $83, $47, $53, $41    ; F H D none UPPER G S A
; With CTRL.
    .byte $0C, $0A, $7B, $80, $80, $0B, $1E, $1F    ; CTRL-L CTRL-J spade none none CTRL-K LEFT RIGHT
    .byte $0F, $80, $10, $15, $9B, $09, $1C, $1D    ; CTRL-O none CTRL-P CTRL-U EOL CTRL-I UP DOWN
    .byte $16, $80, $03, $80, $80, $02, $18, $1A    ; CTRL-V none CTRL-C none none CTRL-B CTRL-X CTRL-Z
    .byte $80, $80, $85, $80, $1B, $80, $FD, $80    ; none none EOF none ESC none BELL none
    .byte $00, $20, $60, $0E, $80, $0D, $80, $81    ; heart SPACE diamond CTRL-N none CTRL-M none INVERSE
    .byte $12, $80, $05, $19, $9E, $14, $17, $11    ; CTRL-R none CTRL-E CTRL-Y CLEAR-TAB CTRL-T CTRL-W CTRL-Q
    .byte $80, $80, $80, $80, $FE, $80, $7D, $FF    ; none none none none DELETE none CLEAR INSERT
    .byte $06, $08, $04, $80, $84, $07, $13, $01    ; CTRL-F CTRL-H CTRL-D none CTRL-LOCK CTRL-G CTRL-S CTRL-A
    .assert * - KEYBOARD_DEFINITIONS = 3 * 64, "Each key code has a character alone, with SHIFT and with CTRL."
