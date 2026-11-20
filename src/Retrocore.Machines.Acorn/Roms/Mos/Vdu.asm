;; THE VDU DRIVER ($C300-$D017)
;;
;; The VDU tables the Advanced User Guide lists at &C31F-&C4B9, then VDUCHR (<VDU_DRIVER>), which OSWRCH calls with
;; every character for the screen, and the handlers for the VDU control codes 0-31 and 127. The handlers here cover
;; the printer and VDU switches, cursor movement in the text window and at the graphics cursor, hardware and soft
;; scrolling, cursor editing's two cursors, the colours and palette, VDU 23's character definitions and 6845 writes,
;; the windows, and mode changes, with the 6845 and video ULA set up for each. PLOT and the graphics routines are in
;; Graphics.asm.
;;
;; Many routines take a byte of VDU workspace by its offset in page three, from <GRAPHICS_WINDOW> at &0300: the
;; source writes these offsets as the low byte of the variable's name, so `ldx #<TEXT_CURSOR_X` is offset &18.

; VDU_STATUS's bits, as VDU 2-6, 14, 15 and 21 and the VDU driver set them.

VDU_STATUS_PRINTER = %00000001      ;; VDU_STATUS bit 0: the printer is on (VDU 2)
VDU_STATUS_NO_SCROLL = %00000010    ;; VDU_STATUS bit 1: the text cursor wraps instead of scrolling
VDU_STATUS_PAGED = %00000100        ;; VDU_STATUS bit 2: paged mode (VDU 14)
VDU_STATUS_WINDOW = %00001000       ;; VDU_STATUS bit 3: a text window is set (VDU 28)
VDU_STATUS_GRAPHICS_TEXT = %00100000 ;; VDU_STATUS bit 5: text goes to the graphics cursor (VDU 5)
VDU_STATUS_EDITING = %01000000      ;; VDU_STATUS bit 6: cursor editing, with the copy and output cursors apart
VDU_STATUS_DISABLED = %10000000     ;; VDU_STATUS bit 7: the VDU driver is disabled (VDU 21)

; The VDU codes the driver tests for.

VDU_CODE_ENABLE = 6                 ;; VDU 6, which enables the VDU driver
VDU_CODE_DISABLE = 21               ;; VDU 21, which disables it
VDU_CODE_PAGED_OFF = 15             ;; VDU 15, which turns paged mode off
VDU_CODE_RETURN = $0D               ;; VDU 13, carriage return, which also ends cursor editing
VDU_CODE_DELETE = $7F               ;; VDU 127, delete, decoded in the slot after VDU 31

; The 6845 registers the VDU driver writes.

CRTC_VERTICAL_SYNC = 7              ;; register 7, the vertical sync position, which *TV moves
CRTC_INTERLACE = 8                  ;; register 8, the interlace mode, which *TV changes
CRTC_CURSOR_START = 10              ;; register 10, the cursor's start line and blink mode
CRTC_START_ADDRESS = 12             ;; registers 12 and 13, the screen's start address, high byte first
CRTC_CURSOR_ADDRESS = 14            ;; registers 14 and 15, the cursor's address, high byte first
CRTC_MODE_REGISTERS = 12            ;; the registers a mode sets from <CRTC_REGISTERS>: 0-11
CURSOR_OFF = %00100000              ;; a cursor start register value whose blink mode shows no cursor

; Other values.

MODE_TELETEXT = 7                   ;; the teletext mode
TELETEXT_BLOCK = $7F                ;; the teletext character for a solid block, the teletext output cursor
VDU_HANDLER_PAGE = $C3              ;; the page a <VDU_ROUTINES_HIGH> entry with parameters counts its handler from
TELETEXT_SAVED_CHARACTER = GRAPHICS_WORK + 16 ;; the teletext character under the output cursor while it shows
VDU_DISABLE_EOR = VDU_CODE_DISABLE ^ VDU_STATUS_DISABLED ;; what VDU 21 exclusive-ORs its code with to get its bit
VDU_PAGED_OFF_EOR = VDU_CODE_PAGED_OFF ^ (~VDU_STATUS_PAGED & $FF) ;; what VDU 15 exclusive-ORs its code with

;; One entry of <VDU_ROUTINES_HIGH>.
;;
;; A handler that takes no parameters has its high byte, which is &80 or more as every handler is in the ROM. One that
;; takes parameters has its page less <VDU_HANDLER_PAGE> in the high nibble and minus the number of parameters in the
;; low nibble: <VDU_DRIVER> ORs the low nibble with &F0 to give <VDU_QUEUE_COUNT>.
;; Parameters: handler = the code's handler, count = the parameters it takes, 0-9
.macro VDU_HIGH handler, count
.if count = 0
    .assert >(handler) >= $80, "A handler without parameters is in the ROM."
    .byte >(handler)
.else
    .assert >(handler) - VDU_HANDLER_PAGE < 8, "A handler with parameters is within &C300-&CAFF."
    .byte ((>(handler) - VDU_HANDLER_PAGE) << 4) | (-(count) & $0F)
.endif
.endmacro

;; One entry of <CLEAR_SCREEN_ENTRIES>: the low byte of the store in <CLEAR_SCREEN_STORES> that clears a page.
;; Parameters: page = the page, the high byte of a memory map type's screen start
.macro CLEAR_ENTRY page
    .byte <(CLEAR_SCREEN_STORES + 3 * ((page) - $30))
.endmacro

;; The VDU driver's start-up entry, which <RESET> calls: jumps to <RESET_VDU>.
;; In: A = the screen mode to start in, in its low three bits
;; Uses: A, X, Y
;; See: <RESET_VDU>
INITIALIZE_VDU:
    jmp RESET_VDU

;; The start-up message, four strings that <RESET> prints by their offsets from &C300, the VDU driver's page.
;;
;; The first is a carriage return and "BBC Computer ". A power-up or hard BREAK then prints "16K" or "32K" with a bell,
;; and every start ends with the last string, a backspace over the space and two carriage returns. Each string ends
;; with a zero; the last one's zero is the first byte of <FOUR_COLOUR_EXPANSION>.
;; See: <STARTUP_BANNER_16K>, <STARTUP_BANNER_32K>, <STARTUP_BANNER_END>
STARTUP_BANNER:
    .byte $0D, "BBC Computer ", 0
STARTUP_BANNER_16K:
    .byte "16K", 7, 0
STARTUP_BANNER_32K:
    .byte "32K", 7, 0
STARTUP_BANNER_END:
    .byte 8, $0D, $0D               ; its zero is FOUR_COLOUR_EXPANSION's first byte

;; Spreads four pixels of a character's shape into a four-colour screen byte, each set pixel in colour 3.
;;
;; Indexed by four bits of a font byte, the leftmost pixel highest; the entry has each set bit copied from the low
;; nibble into the high nibble, as a four-colour byte keeps a pixel's two bits four apart. <WRITE_FOUR_COLOUR_CHARACTER>
;; then masks the entry with the text colours.
FOUR_COLOUR_EXPANSION:
.repeat 16, PIXELS
    .byte PIXELS * $11
.endrepeat
    .assert FOUR_COLOUR_EXPANSION = $C31F, "The four-colour expansion table is at &C31F."

;; Spreads two pixels of a character's shape into a sixteen-colour screen byte, each set pixel in colour 15.
;;
;; Indexed by two bits of a font byte, the left pixel the higher. Sixteen-colour bytes interleave their two pixels'
;; bits, so the left pixel is &AA and the right &55. The sixteen-colour character writer in Graphics.asm uses it.
SIXTEEN_COLOUR_EXPANSION:
.repeat 4, PIXELS
    .byte PIXELS * $55
.endrepeat
    .assert SIXTEEN_COLOUR_EXPANSION = $C32F, "The sixteen-colour expansion table is at &C32F."

;; The low bytes of the VDU control codes' handlers, indexed by the code, with delete (127) as code 32.
;; See: <VDU_ROUTINES_HIGH>, <VDU_DRIVER>
VDU_ROUTINES_LOW:
    .byte <VDU_DO_NOTHING           ; 0: nothing
    .byte <VDU_PRINT_NEXT           ; 1: send the next character to the printer
    .byte <VDU_PRINTER_ON           ; 2: printer on
    .byte <VDU_PRINTER_OFF          ; 3: printer off
    .byte <VDU_TEXT_AT_TEXT_CURSOR  ; 4: text at the text cursor
    .byte <VDU_TEXT_AT_GRAPHICS_CURSOR ; 5: text at the graphics cursor
    .byte <VDU_DO_NOTHING           ; 6: enable the VDU driver, done in VDU_DRIVER_DISABLED
    .byte <SOUND_BELL                    ; 7: bell
    .byte <VDU_BACKSPACE            ; 8: back a character
    .byte <VDU_FORWARD              ; 9: forward a character
    .byte <VDU_LINE_FEED            ; 10: down a line
    .byte <VDU_CURSOR_UP            ; 11: up a line
    .byte <VDU_CLS                  ; 12: clear the text window
    .byte <VDU_RETURN               ; 13: carriage return
    .byte <VDU_PAGED_MODE_ON        ; 14: paged mode on
    .byte <VDU_PAGED_MODE_OFF       ; 15: paged mode off
    .byte <VDU_CLG                  ; 16: clear the graphics window
    .byte <VDU_COLOUR               ; 17: COLOUR
    .byte <VDU_GCOL                 ; 18: GCOL
    .byte <VDU_PALETTE              ; 19: set a palette entry
    .byte <VDU_DEFAULT_COLOURS      ; 20: default colours
    .byte <VDU_DISABLE              ; 21: disable the VDU driver
    .byte <VDU_MODE                 ; 22: MODE
    .byte <VDU_DEFINE_CHARACTER     ; 23: define a character, or the cursor and 6845
    .byte <VDU_GRAPHICS_WINDOW      ; 24: graphics window
    .byte <VDU_PLOT                 ; 25: PLOT
    .byte <VDU_DEFAULT_WINDOWS      ; 26: default windows
    .byte <VDU_DO_NOTHING           ; 27: nothing
    .byte <VDU_TEXT_WINDOW          ; 28: text window
    .byte <VDU_ORIGIN               ; 29: graphics origin
    .byte <VDU_HOME                 ; 30: home
    .byte <VDU_TAB                  ; 31: TAB(X,Y)
    .byte <VDU_DELETE               ; 127: delete
    .assert VDU_ROUTINES_LOW = $C333, "The VDU routine table is at &C333."

;; The high bytes of the VDU control codes' handlers, with the number of parameters each takes, indexed like
;; <VDU_ROUTINES_LOW>. <VDU_HIGH> describes an entry.
;; See: <VDU_ROUTINES_LOW>, <VDU_DRIVER>
VDU_ROUTINES_HIGH:
    VDU_HIGH VDU_DO_NOTHING, 0
    VDU_HIGH VDU_PRINT_NEXT, 1
    VDU_HIGH VDU_PRINTER_ON, 0
    VDU_HIGH VDU_PRINTER_OFF, 0
    VDU_HIGH VDU_TEXT_AT_TEXT_CURSOR, 0
    VDU_HIGH VDU_TEXT_AT_GRAPHICS_CURSOR, 0
    VDU_HIGH VDU_DO_NOTHING, 0
    VDU_HIGH SOUND_BELL, 0
    VDU_HIGH VDU_BACKSPACE, 0
    VDU_HIGH VDU_FORWARD, 0
    VDU_HIGH VDU_LINE_FEED, 0
    VDU_HIGH VDU_CURSOR_UP, 0
    VDU_HIGH VDU_CLS, 0
    VDU_HIGH VDU_RETURN, 0
    VDU_HIGH VDU_PAGED_MODE_ON, 0
    VDU_HIGH VDU_PAGED_MODE_OFF, 0
    VDU_HIGH VDU_CLG, 0
    VDU_HIGH VDU_COLOUR, 1
    VDU_HIGH VDU_GCOL, 2
    VDU_HIGH VDU_PALETTE, 5
    VDU_HIGH VDU_DEFAULT_COLOURS, 0
    VDU_HIGH VDU_DISABLE, 0
    VDU_HIGH VDU_MODE, 1
    VDU_HIGH VDU_DEFINE_CHARACTER, 9
    VDU_HIGH VDU_GRAPHICS_WINDOW, 8
    VDU_HIGH VDU_PLOT, 5
    VDU_HIGH VDU_DEFAULT_WINDOWS, 0
    VDU_HIGH VDU_DO_NOTHING, 0
    VDU_HIGH VDU_TEXT_WINDOW, 4
    VDU_HIGH VDU_ORIGIN, 4
    VDU_HIGH VDU_HOME, 0
    VDU_HIGH VDU_TAB, 2
    VDU_HIGH VDU_DELETE, 0

;; The offset from the screen's start of each character row in the 20K and 16K modes, 640 bytes apart: 32 entries, the
;; high byte of each first. The 10K and 8K modes use it halved, as <ROW_TABLE> says.
;; See: <ROW_TABLE>, <CALCULATE_TEXT_CURSOR>
ROW_OFFSETS_640:
.repeat 32, ROW
    .dbyt ROW * 640
.endrepeat
    .assert ROW_OFFSETS_640 = $C375, "The *640 table is at &C375."

;; The offset from the screen's start of each character row in teletext, 40 bytes apart: 25 entries, the high byte of
;; each first.
;; See: <ROW_TABLE>, <CALCULATE_TEXT_CURSOR>
ROW_OFFSETS_40:
.repeat 25, ROW
    .dbyt ROW * 40
.endrepeat
    .assert >ROW_OFFSETS_40 = >ROW_OFFSETS_640, "SET_MODE sets ROW_TABLE's high byte for both tables at once."

;; The last character row of each mode, 0-7: the rows less one.
MODE_LAST_ROW:
    .byte 31, 31, 31, 24, 31, 31, 24, 24
    .assert MODE_LAST_ROW = $C3E7, "The mode tables are at &C3E7."

;; The last character column of each mode, 0-7: the columns less one.
MODE_LAST_COLUMN:
    .byte 79, 39, 19, 79, 39, 19, 39, 39

;; The video ULA control register's value for each mode, 0-7: the cursor width (bits 5-7), the 2 MHz clock (bit 4),
;; the characters per line (bits 2-3) and teletext (bit 1).
;; See: <VIDEO_ULA_CONTROL>
MODE_ULA_CONTROL:
    .byte %10011100, %11011000, %11110100, %10011100, %10001000, %11000100, %10001000, %01001011

;; The screen bytes a character takes in each mode, 0-6: 8 for two colours, 16 for four, 32 for sixteen. Mode 7's
;; entry, 1, is the first byte of <PIXEL_MASKS>.
MODE_BYTES_PER_CHARACTER:
    .byte 8, 16, 32, 8, 8, 16, 8

;; The pixel masks, indexed by the pixels per byte less one (<PIXELS_PER_BYTE>) plus the pixel, 0 the leftmost.
;;
;; Its first byte is mode 7's entry of <MODE_BYTES_PER_CHARACTER>; then <SIXTEEN_COLOUR_MASKS> start at index 1,
;; <FOUR_COLOUR_MASKS> at 3 and <TWO_COLOUR_MASKS> at 7, whose last mask is the first byte of <MODE_COLOURS>. The
;; graphics code takes a point's <GRAPHICS_MASK> from it, and <SET_MODE> takes <RIGHT_COLOUR_MASK> from index twice the
;; pixels per byte less one.
PIXEL_MASKS:
    .byte 1

;; The sixteen-colour pixel masks, left pixel first: each is the byte with that pixel in colour 15 and the other 0.
SIXTEEN_COLOUR_MASKS:
    .byte %10101010, %01010101

;; The four-colour pixel masks, leftmost first: each is the byte with that pixel in colour 3 and the others 0.
FOUR_COLOUR_MASKS:
    .byte %10001000, %01000100, %00100010, %00010001

;; The two-colour pixel masks, leftmost first. The eighth, %00000001, is the first byte of <MODE_COLOURS>.
;;
;; <VDU_DEFINE_CHARACTER> also uses entries 1-7 as the bits of <FONT_FLAGS> for the font zones &20-&FF.
TWO_COLOUR_MASKS:
    .byte %10000000, %01000000, %00100000, %00010000, %00001000, %00000100, %00000010

;; The logical colours of each mode, 0-6, less one. Mode 7's entry, 0, is the first byte of <GCOL_EOR_SET>.
MODE_COLOURS:
    .byte 1, 3, 15, 1, 1, 3, 1

;; One of the four overlapping tables that turn a GCOL action, 0-4, into the masks that plot with it.
;;
;; <SET_GRAPHICS_MASKS> makes <GRAPHICS_OR_MASK> = (colour OR <GCOL_OR_SET>) EOR <GCOL_OR_FLIP> and <GRAPHICS_EOR_MASK>
;; = (colour OR GCOL_EOR_SET) EOR <GCOL_EOR_FLIP>, indexed by the action, and a screen byte becomes (byte OR the first)
;; EOR the second. That stores the colour (action 0), ORs it (1), ANDs it (2), exclusive-ORs it (3) or inverts the byte
;; (4). This table's entries are &00, &FF, &00, &00, &FF; its first is mode 7's entry of <MODE_COLOURS>.
;; See: <GCOL_OR_SET>, <GCOL_OR_FLIP>, <GCOL_EOR_FLIP>
GCOL_EOR_SET:
    .byte $00

;; Inherit: <GCOL_EOR_SET>
;; This table's entries are &FF, &00, &00, &FF, &FF.
GCOL_OR_SET:
    .byte $FF

;; Inherit: <GCOL_EOR_SET>
;; This table's entries are &00, &00, &FF, &FF, &FF.
GCOL_OR_FLIP:
    .byte $00, $00, $FF

;; Inherit: <GCOL_EOR_SET>
;; This table's entries are &FF, &FF, &FF, &00, &00; its last is the first byte of <TWO_COLOUR_BYTES>.
GCOL_EOR_FLIP:
    .byte $FF, $FF, $FF, $00

;; The two-colour mode's colours: for each logical colour, the screen byte that is all that colour.
;;
;; With <FOUR_COLOUR_BYTES> and <SIXTEEN_COLOUR_BYTES> it makes one table that <SET_COLOUR> indexes from the byte
;; before this one, by the colour plus (the colours less one) AND 7: 1-2 here, 3-6 for four colours and 7-22 for
;; sixteen.
TWO_COLOUR_BYTES:
    .byte %00000000, %11111111
    .assert TWO_COLOUR_BYTES = $C424, "The colour tables are at &C424."

;; The four-colour modes' colours: for each logical colour, the screen byte that is all that colour.
FOUR_COLOUR_BYTES:
    .byte %00000000, %00001111, %11110000, %11111111

;; The sixteen-colour mode's colours: for each logical colour, the screen byte that is all that colour.
SIXTEEN_COLOUR_BYTES:
    .byte %00000000, %00000011, %00001100, %00001111
    .byte %00110000, %00110011, %00111100, %00111111
    .byte %11000000, %11000011, %11001100, %11001111
    .byte %11110000, %11110011, %11111100, %11111111

;; The pixels in a screen byte in each mode, 0-7, less one, or 0 in a mode without graphics. Its last two entries are
;; the first bytes of <MODE_MAP_TYPE>.
MODE_PIXELS_PER_BYTE:
    .byte 7, 3, 1

;; The sound system's offsets to the tone channels' periods, at <SOUND_PERIOD_OFFSETS> + 4 + the channel.
;;
;; The tone generator in Keyboard.asm adds an entry to the period of channels 1-3, indexed by 4 plus the channel; the
;; bytes it reads, 0, 1 and 2, are the entries of <MODE_MAP_TYPE> for modes 2-4. This label is mode 3's entry of
;; <MODE_PIXELS_PER_BYTE>.
SOUND_PERIOD_OFFSETS:
    .byte 0, 7, 3

;; The memory map type of each mode, 0-7: 0 for 20K, 1 for 16K, 2 for 10K, 3 for 8K and 4 for teletext. Its first two
;; entries are the last two of <MODE_PIXELS_PER_BYTE>, and mode 7's is the first byte of <WINDOW_EDGE_OFFSETS>.
;; See: <MEMORY_MAP_TYPE>
MODE_MAP_TYPE:
    .byte 0, 0, 0, 1, 2, 2, 3

;; The offset in page three of the graphics window edge a clipped line heads for, indexed by its direction: the right
;; (4), left (0), top (6) and bottom (2) edges of <GRAPHICS_WINDOW>. The line code in Graphics.asm uses it.
WINDOW_EDGE_OFFSETS:
    .byte 4, 0, 6, 2

;; The value <SET_MODE> writes to the system VIA's addressable latch for its bit 5, one of the two that tell the
;; hardware how far to wrap screen addresses past &7FFF, indexed by the memory map type.
;;
;; A latch write is the bit number in bits 0-2 and the bit's value in bit 3: bit 5 is set for map types 0 and 2 and
;; clear for 1 and 3. The entry for teletext, the first of <SCREEN_WRAP_LATCH_B4>, writes bit 4 again instead.
;; See: <SCREEN_WRAP_LATCH_B4>, <WRITE_SYSTEM_LATCH>
SCREEN_WRAP_LATCH_B5:
    .byte $0D, $05, $0D, $05

;; The value <SET_MODE> writes to the system VIA's addressable latch for its bit 4, the other screen wrap bit,
;; indexed by the memory map type: set for map types 2 and 3, clear for the others.
;; See: <SCREEN_WRAP_LATCH_B5>
SCREEN_WRAP_LATCH_B4:
    .byte $04, $04, $0C, $0C, $04

;; Where <CLEAR_SCREEN> enters <CLEAR_SCREEN_STORES> for each memory map type: the low byte of the store that clears
;; the screen's first page.
CLEAR_SCREEN_ENTRIES:
    CLEAR_ENTRY $30
    CLEAR_ENTRY $40
    CLEAR_ENTRY $58
    CLEAR_ENTRY $60
    CLEAR_ENTRY $7C

;; The high byte of the screen's size for each memory map type; the low byte is zero.
;; See: <SCREEN_SIZE>
MAP_SCREEN_SIZE:
    .byte $50, $40, $28, $20, $04

;; The high byte of the screen's first address for each memory map type; the low byte is zero.
;; See: <SCREEN_BOTTOM>
MAP_SCREEN_START:
    .byte $30, $40, $58, $60, $7C

;; The low byte of the bytes in a character row: 40 for teletext, 320 for the 10K and 8K modes and 640 for the 20K
;; and 16K modes. <SET_MODE> indexes it by those three kinds, 0-2, which are also the rows' high bytes.
;; See: <BYTES_PER_ROW>
ROW_SIZE_LOW:
    .byte <40, <320, <640
    .assert (>40 = 0) && (>320 = 1) && (>640 = 2), "A row size's high byte is its index."

;; The low byte of <ROW_TABLE> for each kind of row that <ROW_SIZE_LOW> indexes: the *40 table for teletext and the
;; *640 table for the others.
ROW_TABLE_LOW:
    .byte <ROW_OFFSETS_40, <ROW_OFFSETS_640, <ROW_OFFSETS_640

;; The index in <CRTC_REGISTERS> of each memory map type's register 11, the last of its twelve.
CRTC_REGISTERS_LAST:
.repeat 5, MAP
    .byte MAP * CRTC_MODE_REGISTERS + CRTC_MODE_REGISTERS - 1
.endrepeat

;; The values of the 6845's registers 0-11 for each memory map type, twelve bytes each.
;;
;; <WRITE_CRTC_REGISTER> adds the *TV settings to registers 7 and 8 as it writes them, and one more to register 7.
CRTC_REGISTERS:
    .byte $7F, $50, $62, $28, $26, $00, $20, $22, $01, $07, $67, $08 ; 0: modes 0-2
    .byte $7F, $50, $62, $28, $1E, $02, $19, $1B, $01, $09, $67, $09 ; 1: mode 3
    .byte $3F, $28, $31, $24, $26, $00, $20, $22, $01, $07, $67, $08 ; 2: modes 4 and 5
    .byte $3F, $28, $31, $24, $1E, $02, $19, $1B, $01, $09, $67, $09 ; 3: mode 6
    .byte $3F, $28, $33, $24, $1E, $02, $19, $1B, $93, $12, $72, $13 ; 4: mode 7
    .assert CRTC_REGISTERS = $C46E, "The 6845 tables are at &C46E."

;; The line drawer's routines for a step along a line's major axis, two addresses, low byte first:
;; <DRAW_LINE_MAJOR_RIGHT> and <DRAW_LINE_MAJOR_UP>. The line code in Graphics.asm picks one by the line's direction,
;; reading the low byte here and the high byte at <LINE_MAJOR_STEPS_HIGH> with the same index.
;; See: <LINE_MAJOR_STEPS_HIGH>, <LINE_MINOR_STEPS_LOW>
LINE_MAJOR_STEPS:
    .byte <DRAW_LINE_MAJOR_RIGHT

;; The high bytes of <LINE_MAJOR_STEPS>, one byte on, which the line code reads with the same index.
LINE_MAJOR_STEPS_HIGH:
    .byte >DRAW_LINE_MAJOR_RIGHT, <DRAW_LINE_MAJOR_UP, >DRAW_LINE_MAJOR_UP

;; The low bytes of the line drawer's routines for a step along a line's minor axis: a pixel right, a pixel left, a
;; line up and a line down.
;; See: <LINE_MINOR_STEPS_HIGH>
LINE_MINOR_STEPS_LOW:
    .byte <DRAW_LINE_STEP_RIGHT, <DRAW_LINE_STEP_LEFT, <DRAW_LINE_STEP_UP, <DRAW_LINE_STEP_DOWN

;; The high bytes of <LINE_MINOR_STEPS_LOW>'s routines.
LINE_MINOR_STEPS_HIGH:
    .byte >DRAW_LINE_STEP_RIGHT, >DRAW_LINE_STEP_LEFT, >DRAW_LINE_STEP_UP, >DRAW_LINE_STEP_DOWN

;; The characters whose teletext codes differ: "#", "_" and the pound sign (&60), whose codes are at
;; <TELETEXT_CODES>, one byte on.
;;
;; The two tables overlap: each byte is a character's code and the next character. Writing translates # to &5F, _ to
;; &60 and the pound sign to &23; reading the screen translates back.
;; See: <TELETEXT_CODES>, <WRITE_TELETEXT_CHARACTER>
TELETEXT_TRANSLATION:
    .byte '#'

;; The teletext codes for the characters of <TELETEXT_TRANSLATION>, indexed the same: &5F, &60 and &23.
TELETEXT_CODES:
    .byte '_', '`', '#'

;; The font zones <EXPLODE_FONT> moves into RAM, in order, as indexes into <FONT_LOCATIONS>: &A0-&BF, &C0-&DF,
;; &E0-&FF, &20-&3F, &40-&5F and &60-&7F.
FONT_EXPLOSION_ZONES:
    .byte 4, 5, 6, 0, 1, 2

;; VDUCHR: the VDU driver, which OSWRCH calls with each character for the screen.
;;
;; A character 32-126 is drawn at the text cursor, or at the graphics cursor after VDU 5, and the cursor moves on. A
;; control code 0-31, or delete (127) in the slot after 31, is decoded through <VDU_ROUTINES_LOW> and
;; <VDU_ROUTINES_HIGH>. If it takes parameters, its handler goes in <VDU_JUMP> and <VDU_QUEUE_COUNT> becomes minus
;; their number; each later call queues one, so that the last always lands at <VDU_QUEUE_END>, and the handler runs
;; when it arrives.
;;
;; While the driver is disabled (VDU 21), only VDU 6 is obeyed, and VDU 1 still prints its character. While cursor
;; editing is on, the driver swaps the text cursor for the output cursor around each character, and a carriage return
;; ends the editing.
;;
;; Falls into <VDU_DO_NOTHING>.
;; In: A = the character
;; Out: carry = set when OSWRCH should send the character to the printer too: a printable character or VDU 8-13 while
;;   the printer is on (VDU 2), or VDU 8-13 while the driver is disabled
;; Uses: A, X, Y, VDU_TEMP
;; See: <VDU_ROUTINES_LOW>, <VDU_STATUS>, <VDU_QUEUE>
VDU_DRIVER:
    ldx VDU_QUEUE_COUNT
    bne VDU_DRIVER_QUEUE            ; a parameter for the code before
    bit VDU_STATUS
    bvc VDU_DRIVER_DECODE
    jsr SWAP_EDITING_CURSORS        ; editing: to the output cursor
    jsr REMOVE_OUTPUT_CURSOR        ; which keeps the flags of BIT VDU_STATUS
    bmi VDU_DRIVER_DECODE           ; the driver is disabled
    cmp #VDU_CODE_RETURN
    bne VDU_DRIVER_DECODE
    jsr END_CURSOR_EDITING                       ; a carriage return ends cursor editing
VDU_DRIVER_DECODE:
    cmp #VDU_CODE_DELETE
    beq VDU_DRIVER_DELETE
    cmp #' '
    bcc VDU_DRIVER_CONTROL
    bit VDU_STATUS
    bmi VDU_DRIVER_PRINTABLE_DONE   ; disabled: draw nothing
    jsr WRITE_CHARACTER
    jsr VDU_FORWARD
VDU_DRIVER_PRINTABLE_DONE:
    jmp VDU_DRIVER_TO_PRINTER
VDU_DRIVER_DELETE:
    lda #32                         ; delete's slot in the tables
VDU_DRIVER_CONTROL:
    tay
    lda VDU_ROUTINES_LOW,y
    sta VDU_JUMP
    lda VDU_ROUTINES_HIGH,y
    bmi VDU_DRIVER_NO_PARAMETERS
    tax
    ora #$F0                        ; minus the number of parameters
    sta VDU_QUEUE_COUNT
    txa
    lsr a
    lsr a
    lsr a
    lsr a
    clc
    adc #VDU_HANDLER_PAGE
    sta VDU_JUMP+1
    bit VDU_STATUS
    bvs VDU_DRIVER_SHOW_CURSOR
    clc

;; VDU 0, VDU 27, and VDU 6 while the driver is enabled: does nothing.
;;
;; It is also <VDU_DRIVER>'s return while it waits for a control code's parameters, with carry clear.
VDU_DO_NOTHING:
    rts

;; Queues a control code's parameter: the rest of <VDU_DRIVER>, reached while <VDU_QUEUE_COUNT> is nonzero.
;;
;; The parameter goes at <VDU_QUEUE_END> less the parameters still to come. When it is the last, the handler in
;; <VDU_JUMP> runs, between swaps to the output cursor while cursor editing; while the driver is disabled, only VDU 1's
;; handler runs.
;;
;; Falls into <VDU_PRINT_NEXT>.
;; In: A = the parameter, X = <VDU_QUEUE_COUNT>, minus the parameters still awaited
;; Out: carry = clear, but with the driver disabled, VDU 1's parameter returns <VDU_PRINT_NEXT>'s carry: set while
;;   the printer is on
;; Uses: A, X, Y
VDU_DRIVER_QUEUE:
    sta VDU_QUEUE_END - $FF,x       ; X = -1 for the last parameter, which lands at VDU_QUEUE_END
    inx
    stx VDU_QUEUE_COUNT
    bne VDU_DRIVER_DONE             ; more to come
    bit VDU_STATUS
    bmi VDU_DRIVER_DISABLED_QUEUE
    bvs VDU_DRIVER_QUEUE_EDITING
    jsr CALL_VDU_JUMP
    clc
    rts
VDU_DRIVER_QUEUE_EDITING:
    jsr SWAP_EDITING_CURSORS
    jsr REMOVE_OUTPUT_CURSOR
    jsr CALL_VDU_JUMP
VDU_DRIVER_SHOW_CURSOR:
    jsr MARK_OUTPUT_CURSOR
VDU_DRIVER_DONE:
    clc
    rts
VDU_DRIVER_DISABLED_QUEUE:
    ldy VDU_JUMP+1
    cpy #>VDU_PRINT_NEXT            ; VDU 1 is the only code with parameters whose handler is in its page
    bne VDU_DRIVER_DONE

;; VDU 1: sends the next character to the printer, and only to the printer, while the printer is on (VDU 2).
;;
;; The driver runs it even while it is disabled.
;; In: A = the character, the parameter
;; Out: carry = clear when the printer is off
;; Uses: A, X, Y
VDU_PRINT_NEXT:
    tax
    lda VDU_STATUS
    lsr a                           ; carry = VDU_STATUS_PRINTER
    bcc VDU_DO_NOTHING
    txa
    jmp BUFFER_PRINTER_CHARACTER

;; Runs a control code that takes no parameters: the rest of <VDU_DRIVER>.
;;
;; Codes 8-13 (the cursor movements and carriage return) leave carry set for the printer test that follows. While
;; the driver is disabled, only VDU 6 is obeyed.
;;
;; Falls into <MARK_OUTPUT_CURSOR>.
;; In: A = the high byte of the handler, Y = the code, VDU_JUMP = the low byte of the handler
;; Out: carry = set when the character should go to the printer as well
;; Uses: A, X, Y
;; Entry: VDU_DRIVER_TO_PRINTER = sets carry from the printer bit and finishes, for a printable character
VDU_DRIVER_NO_PARAMETERS:
    sta VDU_JUMP+1
    tya
    cmp #8
    bcc VDU_DRIVER_RUN              ; carry = clear below 8
    eor #$FF
    cmp #$FF - $0D                  ; carry = set for 8-13: NOT A >= NOT 13
    eor #$FF
VDU_DRIVER_RUN:
    bit VDU_STATUS
    bmi VDU_DRIVER_DISABLED
    php
    jsr CALL_VDU_JUMP
    plp
    bcc VDU_DRIVER_FINISH
VDU_DRIVER_TO_PRINTER:
    lda VDU_STATUS
    lsr a                           ; carry = VDU_STATUS_PRINTER
VDU_DRIVER_FINISH:
    bit VDU_STATUS
    bvc VDU_DO_NOTHING

;; Shows the output cursor and swaps back to the copy cursor, for cursor editing.
;;
;; Falls into <SWAP_EDITING_CURSORS>.
;; Keeps: A, P
;; See: <DRAW_OUTPUT_CURSOR>, <SWAP_EDITING_CURSORS>
MARK_OUTPUT_CURSOR:
    jsr DRAW_OUTPUT_CURSOR

;; Swaps the text cursor with the other of cursor editing's two cursors, at <OUTPUT_CURSOR_X>, and moves the 6845's
;; cursor to it.
;;
;; At rest the text cursor is the copy cursor, which the cursor keys move and the hardware cursor shows, and
;; <OUTPUT_CURSOR_X> holds where output goes. Each swap also flips <VDU_STATUS_NO_SCROLL>, which is set while the copy
;; cursor is current.
;; Keeps: A, P
;; Uses: X, Y
SWAP_EDITING_CURSORS:
    php
    pha
    ldx #<TEXT_CURSOR_X
    ldy #<OUTPUT_CURSOR_X
    jsr SWAP_VDU_PAIR
    jsr CALCULATE_TEXT_CURSOR
    jsr SET_CRTC_CURSOR
    lda VDU_STATUS
    eor #VDU_STATUS_NO_SCROLL
    sta VDU_STATUS
    pla
    plp
    rts

;; Handles a control code while the driver is disabled: obeys VDU 6, which enables it again, and ignores the rest.
;; In: A = the code, carry = set for codes 8-13
;; Out: carry = as given
;; Uses: A
VDU_DRIVER_DISABLED:
    eor #VDU_CODE_ENABLE
    bne TEST_GRAPHICS_TEXT_DONE
    lda #~VDU_STATUS_DISABLED & $FF
    bcc CLEAR_VDU_STATUS            ; always: carry is clear for VDU 6

;; Tests whether text goes to the graphics cursor (VDU 5).
;; Out: A = <VDU_STATUS> AND <VDU_STATUS_GRAPHICS_TEXT>, zero = set when text goes to the text cursor
;; Keeps: X, Y
TEST_GRAPHICS_TEXT:
    lda VDU_STATUS
    and #VDU_STATUS_GRAPHICS_TEXT
TEST_GRAPHICS_TEXT_DONE:
    rts

;; VDU 14: turns paged mode on, with no lines yet printed.
;; Uses: A, Y
VDU_PAGED_MODE_ON:
    ldy #0
    sty PAGED_LINES
    lda #VDU_STATUS_PAGED
    bne SET_VDU_STATUS              ; always

;; VDU 2: turns the printer on, after telling the printer driver through UPTV.
;;
;; The printer driver is called with A = 2, the VDU code. Then the EOR that VDU 21 enters at turns &94 into
;; <VDU_STATUS_PRINTER>, so the two codes share the code that sets their bits.
;;
;; Falls into <VDU_DISABLE>.
;; Uses: A, X, Y
VDU_PRINTER_ON:
    jsr CALL_PRINTER_DRIVER
    lda #VDU_STATUS_PRINTER ^ VDU_DISABLE_EOR

;; VDU 21: disables the VDU driver, which then obeys only VDU 6.
;;
;; It enters with A = 21, the code, which the EOR turns into <VDU_STATUS_DISABLED>.
;;
;; Falls into <SET_VDU_STATUS>.
;; In: A = 21
;; Uses: A
VDU_DISABLE:
    eor #VDU_DISABLE_EOR

;; Sets bits of <VDU_STATUS>.
;; In: A = the bits to set
;; Out: A = the new <VDU_STATUS>
;; Keeps: X, Y
SET_VDU_STATUS:
    ora VDU_STATUS
    bne STORE_VDU_STATUS            ; always: a bit is set

;; VDU 3: turns the printer off, after telling the printer driver through UPTV.
;;
;; The printer driver is called with A = 3, the VDU code. Then the EOR that VDU 15 enters at turns &0A into a mask
;; without <VDU_STATUS_PRINTER>.
;;
;; Falls into <VDU_PAGED_MODE_OFF>.
;; Uses: A, X, Y
VDU_PRINTER_OFF:
    jsr CALL_PRINTER_DRIVER
    lda #(~VDU_STATUS_PRINTER & $FF) ^ VDU_PAGED_OFF_EOR

;; VDU 15: turns paged mode off.
;;
;; It enters with A = 15, the code, which the EOR turns into a mask without <VDU_STATUS_PAGED>.
;;
;; Falls into <CLEAR_VDU_STATUS>.
;; In: A = 15
;; Uses: A
VDU_PAGED_MODE_OFF:
    eor #VDU_PAGED_OFF_EOR

;; Clears bits of <VDU_STATUS>.
;; In: A = the bits to keep
;; Out: A = the new <VDU_STATUS>
;; Keeps: X, Y
;; Entry: STORE_VDU_STATUS = stores A as <VDU_STATUS>
CLEAR_VDU_STATUS:
    and VDU_STATUS
STORE_VDU_STATUS:
    sta VDU_STATUS
STORE_VDU_STATUS_DONE:
    rts

;; VDU 4: sends text to the text cursor again, and shows the cursor. A mode without graphics ignores it.
;; Uses: A, Y
VDU_TEXT_AT_TEXT_CURSOR:
    lda PIXELS_PER_BYTE
    beq STORE_VDU_STATUS_DONE
    jsr SHOW_CURSOR
    lda #~VDU_STATUS_GRAPHICS_TEXT & $FF
    bne CLEAR_VDU_STATUS            ; always

;; VDU 5: sends text to the graphics cursor, and hides the text cursor. A mode without graphics ignores it.
;; Uses: A, Y
VDU_TEXT_AT_GRAPHICS_CURSOR:
    lda PIXELS_PER_BYTE
    beq STORE_VDU_STATUS_DONE
    lda #CURSOR_OFF
    jsr SET_CURSOR_START
    bne SET_VDU_STATUS              ; always, with A = CURSOR_OFF = VDU_STATUS_GRAPHICS_TEXT
    .assert CURSOR_OFF = VDU_STATUS_GRAPHICS_TEXT, "VDU 5 sets its status bit with the cursor value."

;; VDU 8: moves the cursor back a character, to the end of the line above at the window's left edge.
;;
;; The text cursor's address moves back by a character's bytes, wrapping below the screen's start; at the left edge,
;; it falls into <TEXT_CURSOR_UP>. After VDU 5 the graphics cursor moves back instead.
;; Uses: A, X, Y, VDU_TEMP
VDU_BACKSPACE:
    jsr TEST_GRAPHICS_TEXT
    bne GRAPHICS_BACKSPACE
    dec TEXT_CURSOR_X
    ldx TEXT_CURSOR_X
    cpx TEXT_WINDOW_LEFT
    bmi VDU_BACKSPACE_WRAP
    lda TEXT_CURSOR_ADDRESS
    sec
    sbc BYTES_PER_CHARACTER
    tax
    lda TEXT_CURSOR_ADDRESS+1
    sbc #0
    cmp SCREEN_BOTTOM
    bcs VDU_BACKSPACE_SET
    adc SCREEN_SIZE                 ; below the screen: wrap to its end
VDU_BACKSPACE_SET:
    tay
    jmp SET_TEXT_CURSOR_ADDRESS
VDU_BACKSPACE_WRAP:
    lda TEXT_WINDOW_RIGHT
    sta TEXT_CURSOR_X

;; Moves the text cursor up a line, scrolling the window down at its top.
;;
;; The scroll is a hardware scroll of the whole screen, or a soft scroll when a text window is set; the line that
;; appears is cleared. <CHECK_SCROLL> may wrap the cursor to the bottom instead. It also counts the line back off
;; <PAGED_LINES>, without going below zero.
;; Uses: A, X, Y, VDU_TEMP
TEXT_CURSOR_UP:
    dec PAGED_LINES
    bpl TEXT_CURSOR_UP_1
    inc PAGED_LINES
TEXT_CURSOR_UP_1:
    ldx TEXT_CURSOR_Y
    cpx TEXT_WINDOW_TOP
    beq TEXT_CURSOR_UP_SCROLL
    dec TEXT_CURSOR_Y
    jmp SET_TEXT_CURSOR
TEXT_CURSOR_UP_SCROLL:
    clc                             ; moving up
    jsr CHECK_SCROLL
    lda #VDU_STATUS_WINDOW
    bit VDU_STATUS
    bne TEXT_CURSOR_UP_SOFT
    jsr HARDWARE_SCROLL_DOWN
    bne TEXT_CURSOR_UP_CLEAR        ; always
TEXT_CURSOR_UP_SOFT:
    jsr SCROLL_WINDOW_DOWN
TEXT_CURSOR_UP_CLEAR:
    jmp CLEAR_LINE_AND_SET_CURSOR

;; Moves the graphics cursor back a character, VDU 8 after VDU 5: left by 8, wrapping to the right edge of the graphics
;; window and up a line.
;;
;; Falls into <GRAPHICS_CURSOR_BACK>.
;; Uses: A, X, Y, VDU_TEMP
GRAPHICS_BACKSPACE:
    ldx #0

;; Moves the graphics cursor back by a character, 8 in internal co-ordinates, along one axis.
;;
;; Moving left past the graphics window wraps to its right edge, less 7, and moves up a line
;; (<GRAPHICS_CURSOR_ADVANCE>); moving down past it wraps to its top. A cursor already outside the window just
;; moves. It then updates <GRAPHICS_CURSOR> from <GRAPHICS_CURSOR_INTERNAL>.
;; In: X = 0 to move left, 2 to move down
;; Uses: A, X, Y, VDU_TEMP
;; Entry: GRAPHICS_CURSOR_DONE = only updates <GRAPHICS_CURSOR>
GRAPHICS_CURSOR_BACK:
    stx VDU_TEMP+1
    jsr CURSOR_WINDOW_CODE                       ; VDU_TEMP = nonzero when the cursor is outside the window
    ldx VDU_TEMP+1
    sec
    lda GRAPHICS_CURSOR_INTERNAL,x
    sbc #8
    sta GRAPHICS_CURSOR_INTERNAL,x
    bcs GRAPHICS_CURSOR_BACK_1
    dec GRAPHICS_CURSOR_INTERNAL+1,x
GRAPHICS_CURSOR_BACK_1:
    lda VDU_TEMP
    bne GRAPHICS_CURSOR_DONE        ; it was outside the window already
    jsr CURSOR_WINDOW_CODE
    beq GRAPHICS_CURSOR_DONE        ; still inside
    ldx VDU_TEMP+1
    lda GRAPHICS_WINDOW+4,x         ; the right edge, or the top
    cpx #1
    bcs GRAPHICS_CURSOR_BACK_WRAP
    sbc #6                          ; carry is clear: the right edge less 7
GRAPHICS_CURSOR_BACK_WRAP:
    sta GRAPHICS_CURSOR_INTERNAL,x
    lda GRAPHICS_WINDOW+5,x
    sbc #0
    sta GRAPHICS_CURSOR_INTERNAL+1,x
    txa
    beq GRAPHICS_CURSOR_UP          ; wrapped from the left: up a line
GRAPHICS_CURSOR_DONE:
    jmp UPDATE_EXTERNAL_CURSOR

;; VDU 11: moves the cursor up a line, scrolling at the top of the window (<TEXT_CURSOR_UP>). After VDU 5 the graphics
;; cursor moves up 8, wrapping to the bottom of the graphics window.
;; Uses: A, X, Y, VDU_TEMP
;; Entry: GRAPHICS_CURSOR_UP = moves the graphics cursor up a line
VDU_CURSOR_UP:
    jsr TEST_GRAPHICS_TEXT
    beq TEXT_CURSOR_UP
GRAPHICS_CURSOR_UP:
    ldx #2
    bne GRAPHICS_CURSOR_ADVANCE     ; always

;; VDU 9: moves the cursor forward a character, to the start of the next line at the window's right edge.
;;
;; Inside the line, the text cursor's address moves on by a character's bytes; at the right edge, the cursor goes to the
;; left edge and down a line, as <TEXT_LINE_FEED>. After VDU 5 the graphics cursor moves on instead.
;; Uses: A, X, Y, VDU_TEMP
VDU_FORWARD:
    lda VDU_STATUS
    and #VDU_STATUS_GRAPHICS_TEXT
    bne GRAPHICS_FORWARD
    ldx TEXT_CURSOR_X
    cpx TEXT_WINDOW_RIGHT
    bcs VDU_FORWARD_WRAP
    inc TEXT_CURSOR_X
    lda TEXT_CURSOR_ADDRESS
    adc BYTES_PER_CHARACTER         ; carry is clear
    tax
    lda TEXT_CURSOR_ADDRESS+1
    adc #0
    jmp SET_TEXT_CURSOR_ADDRESS
VDU_FORWARD_WRAP:
    lda TEXT_WINDOW_LEFT
    sta TEXT_CURSOR_X

;; Moves the text cursor down a line, scrolling the window up at its bottom.
;;
;; First it pauses for paged mode or CTRL and SHIFT (<PAUSE_OUTPUT>). The scroll is a hardware scroll of the whole
;; screen, or a soft scroll when a text window is set, and the line that appears is cleared; <CHECK_SCROLL> may wrap the
;; cursor to the top instead.
;; Uses: A, X, Y, VDU_TEMP
;; Entry: CLEAR_LINE_AND_SET_CURSOR = clears the cursor's line and moves the 6845's cursor to the text cursor,
;;   SET_TEXT_CURSOR = only moves the 6845's cursor to the text cursor, recalculating its address
TEXT_LINE_FEED:
    clc
    jsr PAUSE_OUTPUT
    ldx TEXT_CURSOR_Y
    cpx TEXT_WINDOW_BOTTOM
    bcs TEXT_LINE_FEED_SCROLL
    inc TEXT_CURSOR_Y
    bcc SET_TEXT_CURSOR             ; always
TEXT_LINE_FEED_SCROLL:
    jsr CHECK_SCROLL                ; carry is set: moving down
    lda #VDU_STATUS_WINDOW
    bit VDU_STATUS
    bne TEXT_LINE_FEED_SOFT
    jsr HARDWARE_SCROLL_UP
    bne CLEAR_LINE_AND_SET_CURSOR   ; always
TEXT_LINE_FEED_SOFT:
    jsr SCROLL_WINDOW_UP
CLEAR_LINE_AND_SET_CURSOR:
    jsr CLEAR_TEXT_LINE
SET_TEXT_CURSOR:
    jsr CALCULATE_TEXT_CURSOR
    bcc UPDATE_CRTC_CURSOR          ; always

;; Moves the graphics cursor forward a character, VDU 9 after VDU 5: right by 8, wrapping to the left edge of the
;; graphics window and down a line.
;;
;; Falls into <GRAPHICS_CURSOR_ADVANCE>.
;; Uses: A, X, Y, VDU_TEMP
GRAPHICS_FORWARD:
    ldx #0

;; Moves the graphics cursor on by a character, 8 in internal co-ordinates, along one axis.
;;
;; Moving right past the graphics window wraps to its left edge and moves down a line (<GRAPHICS_CURSOR_BACK>); moving
;; up past it wraps to its bottom, plus 7. A cursor already outside the window just moves. It then updates
;; <GRAPHICS_CURSOR> from <GRAPHICS_CURSOR_INTERNAL>.
;; In: X = 0 to move right, 2 to move up
;; Uses: A, X, Y, VDU_TEMP
GRAPHICS_CURSOR_ADVANCE:
    stx VDU_TEMP+1
    jsr CURSOR_WINDOW_CODE                       ; VDU_TEMP = nonzero when the cursor is outside the window
    ldx VDU_TEMP+1
    clc
    lda GRAPHICS_CURSOR_INTERNAL,x
    adc #8
    sta GRAPHICS_CURSOR_INTERNAL,x
    bcc GRAPHICS_CURSOR_ADVANCE_1
    inc GRAPHICS_CURSOR_INTERNAL+1,x
GRAPHICS_CURSOR_ADVANCE_1:
    lda VDU_TEMP
    bne GRAPHICS_CURSOR_DONE        ; it was outside the window already
    jsr CURSOR_WINDOW_CODE
    beq GRAPHICS_CURSOR_DONE        ; still inside
    ldx VDU_TEMP+1
    lda GRAPHICS_WINDOW,x           ; the left edge, or the bottom
    cpx #1
    bcc GRAPHICS_CURSOR_ADVANCE_WRAP
    adc #6                          ; carry is set: the bottom plus 7
GRAPHICS_CURSOR_ADVANCE_WRAP:
    sta GRAPHICS_CURSOR_INTERNAL,x
    lda GRAPHICS_WINDOW+1,x
    adc #0
    sta GRAPHICS_CURSOR_INTERNAL+1,x
    txa
    beq GRAPHICS_LINE_FEED          ; wrapped from the right: down a line
    jmp UPDATE_EXTERNAL_CURSOR

;; VDU 10: moves the cursor down a line, scrolling at the bottom of the window (<TEXT_LINE_FEED>). After VDU 5 the
;; graphics cursor moves down 8, wrapping to the top of the graphics window.
;; Uses: A, X, Y, VDU_TEMP
;; Entry: GRAPHICS_LINE_FEED = moves the graphics cursor down a line
VDU_LINE_FEED:
    jsr TEST_GRAPHICS_TEXT
    beq TEXT_LINE_FEED
GRAPHICS_LINE_FEED:
    ldx #2
    jmp GRAPHICS_CURSOR_BACK

;; VDU 28: sets the text window from its left, bottom, right and top character positions.
;;
;; A window that does not fit the mode, or whose bottom is above its top or right left of its left, is ignored. A
;; cursor outside the new window goes to its top left (<VDU_HOME>).
;;
;; Falls into <UPDATE_CRTC_CURSOR>.
;; In: VDU_QUEUE+5 = the left column, VDU_QUEUE+6 = the bottom row, VDU_QUEUE+7 = the right column,
;;   VDU_QUEUE_END = the top row
;; Uses: A, X, Y, VDU_TEMP
VDU_TEXT_WINDOW:
    ldx SCREEN_MODE
    lda VDU_QUEUE+6                 ; the bottom
    cmp VDU_QUEUE_END
    bcc READ_PALETTE_DONE           ; above the top
    cmp MODE_LAST_ROW,x
    beq VDU_TEXT_WINDOW_1
    bcs READ_PALETTE_DONE           ; off the screen
VDU_TEXT_WINDOW_1:
    lda VDU_QUEUE+7                 ; the right
    tay
    cmp MODE_LAST_COLUMN,x
    beq VDU_TEXT_WINDOW_2
    bcs READ_PALETTE_DONE           ; off the screen
VDU_TEXT_WINDOW_2:
    sec
    sbc VDU_QUEUE+5
    bmi READ_PALETTE_DONE           ; left of the left
    tay
    jsr SET_TEXT_WINDOW_WIDTH
    lda #VDU_STATUS_WINDOW
    jsr SET_VDU_STATUS
    ldx #<(VDU_QUEUE + 5)
    ldy #<TEXT_WINDOW_LEFT
    jsr COPY_POINT                       ; the four parameters to the text window
    jsr CHECK_TEXT_CURSOR
    bcs VDU_HOME                    ; the cursor is outside the window

;; Moves the 6845's cursor to <TEXT_CURSOR_ADDRESS>, with the text cursor's cell as given (<SET_CRTC_CURSOR>).
;; In: A = the high byte of the text cell's address, X = its low byte
;; Uses: A, X, Y
UPDATE_CRTC_CURSOR:
    jmp SET_CRTC_CURSOR

;; OSWORD &09: reads the logical colour of a point on the screen, like BASIC's POINT.
;; In: OS_X/OS_Y = the parameter block: the point's X and Y co-ordinates in its first four bytes
;; Out: OS_X/OS_Y = the block, with the logical colour in its fifth byte, or &FF when the point is off the screen or
;;   outside the graphics window
;; Uses: A, X, Y, VDU_TEMP
READ_PIXEL:
    ldy #3
READ_PIXEL_COPY:
    lda (OS_X),y
    sta GRAPHICS_WORK,y
    dey
    bpl READ_PIXEL_COPY
    lda #<GRAPHICS_WORK
    jsr READ_POINT
    ldy #4
    bne READ_PALETTE_STORE          ; always

;; OSWORD &0B: reads a logical colour's entry in the palette.
;; In: A = the logical colour, the block's first byte, Y = 0, OS_X/OS_Y = the parameter block
;; Out: OS_X/OS_Y = the block, with the physical colour in its second byte and zeros in its third to fifth
;; Uses: A, X, Y
;; Entry: READ_PALETTE_DONE = only returns
READ_PALETTE:
    and COLOUR_COUNT
    tax
    lda PALETTE,x
READ_PALETTE_NEXT:
    iny
READ_PALETTE_STORE:
    sta (OS_X),y
    lda #0
    cpy #4
    bne READ_PALETTE_NEXT
READ_PALETTE_DONE:
    rts

;; VDU 12: clears the text window to the text background colour and homes the cursor.
;;
;; Without a text window it clears the whole screen and resets the hardware scroll (<CLEAR_SCREEN>); with one, it
;; clears it a line at a time. After VDU 5 it clears the graphics window instead and homes the graphics cursor.
;;
;; Falls into <VDU_HOME>.
;; Uses: A, X, Y, VDU_TEMP
VDU_CLS:
    jsr TEST_GRAPHICS_TEXT
    bne VDU_CLS_GRAPHICS
    lda VDU_STATUS
    and #VDU_STATUS_WINDOW
    bne VDU_CLS_WINDOW
    jmp CLEAR_SCREEN
VDU_CLS_WINDOW:
    ldx TEXT_WINDOW_TOP
VDU_CLS_LOOP:
    stx TEXT_CURSOR_Y
    jsr CLEAR_TEXT_LINE
    ldx TEXT_CURSOR_Y
    cpx TEXT_WINDOW_BOTTOM
    inx
    bcc VDU_CLS_LOOP

;; VDU 30: moves the cursor to the top left of the text window, or after VDU 5 the graphics cursor to the top left of
;; the graphics window.
;;
;; Falls into <VDU_TAB>.
;; Uses: A, X, Y, VDU_TEMP
VDU_HOME:
    jsr TEST_GRAPHICS_TEXT
    beq VDU_HOME_TEXT
    jmp HOME_GRAPHICS_CURSOR
VDU_HOME_TEXT:
    sta VDU_QUEUE_END               ; A = 0: as VDU 31,0,0
    sta VDU_QUEUE+7

;; VDU 31: moves the text cursor to a column and row of the text window, like BASIC's TAB(X,Y).
;;
;; A position outside the window leaves the cursor where it was. After VDU 5 it does nothing.
;; In: VDU_QUEUE+7 = the column, VDU_QUEUE_END = the row
;; Uses: A, X, Y
VDU_TAB:
    jsr TEST_GRAPHICS_TEXT
    bne READ_PALETTE_DONE
    jsr VDU_TAB_SWAP                ; keep the old position in GRAPHICS_WORK
    clc
    lda VDU_QUEUE+7
    adc TEXT_WINDOW_LEFT
    sta TEXT_CURSOR_X
    lda VDU_QUEUE_END
    clc
    adc TEXT_WINDOW_TOP
    sta TEXT_CURSOR_Y
    jsr CHECK_TEXT_CURSOR
    bcc UPDATE_CRTC_CURSOR          ; inside the window
VDU_TAB_SWAP:
    ldx #<TEXT_CURSOR_X             ; outside: put the old position back
    ldy #<GRAPHICS_WORK
    jmp SWAP_VDU_PAIR

;; VDU 13: moves the cursor to the left edge of the text window, or after VDU 5 the graphics cursor to the left edge
;; of the graphics window.
;; Uses: A, X, Y
VDU_RETURN:
    jsr TEST_GRAPHICS_TEXT
    beq VDU_RETURN_TEXT
    jmp GRAPHICS_CURSOR_TO_LEFT
VDU_RETURN_TEXT:
    jsr TEXT_CURSOR_TO_LEFT
    jmp SET_TEXT_CURSOR

;; Clears the graphics window and homes the graphics cursor: VDU 12 after VDU 5.
;;
;; Falls into <VDU_CLG>.
;; Uses: A, X, Y, VDU_TEMP
VDU_CLS_GRAPHICS:
    jsr HOME_GRAPHICS_CURSOR

;; VDU 16: clears the graphics window to the graphics background colour, with its plotting action.
;;
;; It copies the window to <GRAPHICS_WORK> and fills it with horizontal lines from the top down. A mode without
;; graphics ignores it.
;; Uses: A, X, Y, VDU_TEMP
VDU_CLG:
    lda PIXELS_PER_BYTE
    beq VDU_CLG_DONE
    ldx GRAPHICS_BACKGROUND
    ldy GRAPHICS_BACKGROUND_ACTION
    jsr SET_GRAPHICS_MASKS
    ldx #<GRAPHICS_WINDOW
    ldy #<GRAPHICS_WORK
    jsr COPY_POINTS                       ; the window to GRAPHICS_WORK..GRAPHICS_WORK+7
    sec
    lda GRAPHICS_WINDOW+6
    sbc GRAPHICS_WINDOW+2
    tay
    iny
    sty GRAPHICS_WORK+8             ; the window's height, the lines to fill
VDU_CLG_LOOP:
    ldx #<(GRAPHICS_WORK + 4)       ; from the right edge at the top line
    ldy #<GRAPHICS_WORK             ; to the left edge
    jsr FILL_HORIZONTAL_LINE
    lda GRAPHICS_WORK+6
    bne VDU_CLG_NEXT
    dec GRAPHICS_WORK+7
VDU_CLG_NEXT:
    dec GRAPHICS_WORK+6             ; down a line
    dec GRAPHICS_WORK+8
    bne VDU_CLG_LOOP
VDU_CLG_DONE:
    rts

;; VDU 17: sets a text colour, like BASIC's COLOUR: the foreground, or with 128 added the background.
;; In: VDU_QUEUE_END = the colour
;; Uses: A, X, Y, VDU_TEMP
VDU_COLOUR:
    ldy #0
    beq SET_COLOUR                  ; always

;; VDU 18: sets a graphics colour and its plotting action, like BASIC's GCOL: the foreground, or with 128 added the
;; background.
;;
;; Falls into <SET_COLOUR>.
;; In: VDU_QUEUE+7 = the action, 0-4, VDU_QUEUE_END = the colour
;; Uses: A, X, Y, VDU_TEMP
VDU_GCOL:
    ldy #2

;; Sets one of the four colours from <VDU_QUEUE_END>, the background when its bit 7 is set.
;;
;; The colour becomes the byte of that colour from <TWO_COLOUR_BYTES> or the tables after it. For a text colour it
;; also sets <TEXT_EOR_MASK> to the foreground inverted and <TEXT_OR_MASK> to that EOR the background, which turn a
;; font byte into colours (<WRITE_CHARACTER>). For a graphics colour it also stores the action from VDU_QUEUE+7 in
;; <GRAPHICS_FOREGROUND_ACTION> or <GRAPHICS_BACKGROUND_ACTION>. Teletext has no colours to set.
;; In: Y = 0 for text, 2 for graphics, VDU_QUEUE_END = the colour, VDU_QUEUE+7 = the action for graphics
;; Uses: A, X, Y, VDU_TEMP
SET_COLOUR:
    lda VDU_QUEUE_END
    bpl SET_COLOUR_1
    iny                             ; the background
SET_COLOUR_1:
    and COLOUR_COUNT
    sta VDU_TEMP
    lda COLOUR_COUNT
    beq SET_COLOUR_DONE             ; teletext
    and #7
    clc
    adc VDU_TEMP
    tax
    lda TWO_COLOUR_BYTES - 1,x      ; 1-2 for two colours, 3-6 for four, 7-22 for sixteen
    sta TEXT_FOREGROUND,y
    cpy #2
    bcs SET_COLOUR_ACTION
    lda TEXT_FOREGROUND
    eor #$FF
    sta TEXT_EOR_MASK
    eor TEXT_BACKGROUND
    sta TEXT_OR_MASK
SET_COLOUR_DONE:
    rts
SET_COLOUR_ACTION:
    lda VDU_QUEUE+7
    sta GRAPHICS_FOREGROUND,y       ; Y = 2 or 3: GRAPHICS_FOREGROUND_ACTION or GRAPHICS_BACKGROUND_ACTION
    rts

;; Makes the teletext background a space, the byte that clears a teletext screen.
;; Uses: A
DEFAULT_TELETEXT_COLOURS:
    lda #' '
    sta TEXT_BACKGROUND
    rts

;; VDU 20: restores the default colours and palette.
;;
;; The foregrounds become the mode's white (colour 7 in sixteen colours, the last colour otherwise) and the
;; backgrounds and actions zero, and each logical colour's physical colour becomes its default: 0-15 in sixteen
;; colours, black, red, yellow and white in four, and black and white in two.
;;
;; Falls into <VDU_PALETTE>.
;; Uses: A, X, Y, OS_SCRATCH
VDU_DEFAULT_COLOURS:
    ldx #5
    lda #0
VDU_DEFAULT_COLOURS_CLEAR:
    sta TEXT_FOREGROUND,x           ; the colours and actions, TEXT_FOREGROUND..GRAPHICS_BACKGROUND_ACTION
    dex
    bpl VDU_DEFAULT_COLOURS_CLEAR
    ldx COLOUR_COUNT
    beq DEFAULT_TELETEXT_COLOURS
    lda #$FF
    cpx #15
    bne VDU_DEFAULT_COLOURS_WHITE
    lda #%00111111                  ; colour 7 in sixteen colours
VDU_DEFAULT_COLOURS_WHITE:
    sta TEXT_FOREGROUND
    sta GRAPHICS_FOREGROUND
    eor #$FF
    sta TEXT_OR_MASK
    sta TEXT_EOR_MASK
    stx VDU_QUEUE+4                 ; the logical colour, from the last
    cpx #3
    beq VDU_DEFAULT_COLOURS_FOUR
    bcc VDU_DEFAULT_COLOURS_TWO
    stx VDU_QUEUE+5                 ; sixteen colours: each its own physical colour
VDU_DEFAULT_COLOURS_SIXTEEN:
    jsr VDU_PALETTE
    dec VDU_QUEUE+5
    dec VDU_QUEUE+4
    bpl VDU_DEFAULT_COLOURS_SIXTEEN
    rts
VDU_DEFAULT_COLOURS_FOUR:
    ldx #7                          ; white, yellow, red, black for 3, 2, 1, 0
    stx VDU_QUEUE+5
VDU_DEFAULT_COLOURS_FOUR_LOOP:
    jsr VDU_PALETTE
    lsr VDU_QUEUE+5
    dec VDU_QUEUE+4
    bpl VDU_DEFAULT_COLOURS_FOUR_LOOP
    rts
VDU_DEFAULT_COLOURS_TWO:
    ldx #7                          ; white for 1
    jsr VDU_DEFAULT_COLOURS_SET
    ldx #0                          ; black for 0
    stx VDU_QUEUE+4
VDU_DEFAULT_COLOURS_SET:
    stx VDU_QUEUE+5

;; VDU 19: sets the physical colour a logical colour shows, in <PALETTE> and the video ULA's palette.
;;
;; Falls into <PROGRAM_PALETTE>.
;; In: VDU_QUEUE+4 = the logical colour, VDU_QUEUE+5 = the physical colour, 0-15
;; Uses: A, X, Y, OS_SCRATCH
VDU_PALETTE:
    php
    sei
    lda VDU_QUEUE+4
    and COLOUR_COUNT
    tax
    lda VDU_QUEUE+5

;; Sets a logical colour's physical colour in <PALETTE> and in each video ULA palette entry that shows it, then pulls
;; the flags its caller pushed.
;;
;; The ULA's palette has an entry for each four-bit pixel value: one shows the logical colour in sixteen colours,
;; four in four colours and eight in two. It shifts the logical colour's bits into the top of the value, then writes
;; the value with each combination of the low bits, swapping bits 5 and 6 in four-colour modes. Each write is the
;; pixel value in the high nibble and the physical colour in the low (<WRITE_PALETTE_REGISTER_A>).
;; In: A = the physical colour, X = the logical colour, STACK = the caller's flags, pushed with PHP
;; Uses: A, X, Y, OS_SCRATCH
PROGRAM_PALETTE:
    and #$0F
    sta PALETTE,x
    tay
    lda COLOUR_COUNT
    sta OS_SCRATCH
    cmp #3
    php                             ; zero = set in four-colour modes
    txa
PROGRAM_PALETTE_SHIFT:
    ror a                           ; a bit of the logical colour into OS_SCRATCH for each bit of COLOUR_COUNT
    ror OS_SCRATCH
    bcs PROGRAM_PALETTE_SHIFT
    asl OS_SCRATCH
    tya
    ora OS_SCRATCH
    tax
    ldy #0
PROGRAM_PALETTE_LOOP:
    plp
    php
    bne PROGRAM_PALETTE_ENTRY       ; not four colours
    and #%01100000
    beq PROGRAM_PALETTE_SAME
    cmp #%01100000
    beq PROGRAM_PALETTE_SAME
    txa
    eor #%01100000                  ; bits 5 and 6 differ: swap them
    bne PROGRAM_PALETTE_ENTRY
PROGRAM_PALETTE_SAME:
    txa
PROGRAM_PALETTE_ENTRY:
    jsr WRITE_PALETTE_REGISTER_A
    tya
    sec
    adc COLOUR_COUNT                ; the next combination of the low bits
    tay
    txa
    adc #$10
    tax
    cpy #16
    bcc PROGRAM_PALETTE_LOOP
    plp
    plp                             ; the caller's flags
    rts

;; OSWORD &0C: writes a logical colour's entry in the palette.
;; In: A = the logical colour, the block's first byte, Y = 0, OS_X/OS_Y = the parameter block, whose second byte is
;;   the physical colour
;; Uses: A, X, Y, OS_SCRATCH
WRITE_PALETTE:
    php
    and COLOUR_COUNT
    tax
    iny
    lda (OS_X),y
    jmp PROGRAM_PALETTE

;; VDU 22: changes the screen mode, like BASIC's MODE.
;; In: VDU_QUEUE_END = the mode
;; Uses: A, X, Y, VDU_TEMP, OS_SCRATCH
VDU_MODE:
    lda VDU_QUEUE_END
    jmp SET_MODE

;; VDU 23: defines a character's shape, or with a first parameter of 0-31 controls the cursor and the 6845.
;;
;; A character 32-255 takes the eight bytes of its shape, top line first, into its font zone's page in RAM. A zone of
;; characters whose shapes are still read from the ROM (its bit of <FONT_FLAGS> clear) is first copied from the ROM to
;; the page <FONT_LOCATIONS> gives it, and marked as in RAM.
;; In: VDU_QUEUE = the character or the control number, VDU_QUEUE+1..VDU_QUEUE_END = the eight bytes
;; Uses: A, X, Y, VDU_TEMP
VDU_DEFINE_CHARACTER:
    lda VDU_QUEUE
    cmp #' '
    bcc VDU_23_CONTROL
    pha
    lsr a
    lsr a
    lsr a
    lsr a
    lsr a
    tax                             ; the font zone, 1-7 for &20-&FF
    lda TWO_COLOUR_MASKS,x          ; its bit of FONT_FLAGS, %01000000 down to %00000001
    bit FONT_FLAGS
    bne VDU_DEFINE_CHARACTER_STORE  ; the zone is in RAM
    ora FONT_FLAGS
    sta FONT_FLAGS
    txa
    and #3
    clc
    adc #>FONT - 1
    sta VDU_TEMP+5                  ; the zone's page in the ROM, &C0-&C2
    lda FONT_LOCATIONS - 1,x
    sta VDU_TEMP+3                  ; the zone's page in RAM
    ldy #0
    sty VDU_TEMP+2
    sty VDU_TEMP+4
VDU_DEFINE_CHARACTER_COPY:
    lda (VDU_TEMP+4),y
    sta (VDU_TEMP+2),y
    dey
    bne VDU_DEFINE_CHARACTER_COPY
VDU_DEFINE_CHARACTER_STORE:
    pla
    jsr FIND_CHARACTER_DEFINITION                       ; VDU_TEMP+4 = the character's shape
    ldy #7
VDU_DEFINE_CHARACTER_LOOP:
    lda VDU_QUEUE+1,y
    sta (VDU_TEMP+4),y
    dey
    bpl VDU_DEFINE_CHARACTER_LOOP
    rts
    pla                             ; not reached
VDU_DEFINE_CHARACTER_DONE:
    rts

;; Passes a PLOT the MOS does not handle to VDUV, with A = its code from VDU_QUEUE+4 and carry clear: one with a code
;; it does not know, or any PLOT in a mode without graphics.
;; Calls: VDUV
;; Entry: CALL_VDUV = passes A and carry to VDUV as they are
UNKNOWN_PLOT:
    lda VDU_QUEUE+4
    clc
CALL_VDUV:
    jmp (VDUV)

;; VDU 23,0-31: VDU 23,0 writes a 6845 register, VDU 23,1 turns the cursor off (0) or on, and VDU 23,2-31 go to VDUV
;; with carry set.
;;
;; VDU 23,1 does nothing after VDU 5, which keeps the cursor off.
;;
;; Falls into <SHOW_CURSOR>.
;; In: A = the control number, VDU_QUEUE+1 = its first parameter, the register for VDU 23,0, VDU_QUEUE+2 = the value
;; Uses: A, Y
VDU_23_CONTROL:
    cmp #1
    bcc VDU_23_CRTC
    bne CALL_VDUV                   ; 2-31, with carry set
    jsr TEST_GRAPHICS_TEXT
    bne VDU_DEFINE_CHARACTER_DONE
    lda #CURSOR_OFF
    ldy VDU_QUEUE+1
    beq SET_CURSOR_START

;; Shows the text cursor again, setting the 6845's cursor start register from <CURSOR_START>.
;;
;; Falls into <SET_CURSOR_START>.
;; Uses: A, Y
SHOW_CURSOR:
    lda CURSOR_START

;; Writes the 6845's cursor start register, which can hide the cursor (<CURSOR_OFF>).
;; In: A = the value
;; Out: zero = clear
;; Uses: Y
SET_CURSOR_START:
    ldy #CRTC_CURSOR_START
    bne WRITE_CRTC_REGISTER_NOW     ; always

;; VDU 23,0: writes a 6845 register, as <WRITE_CRTC_REGISTER> adjusts it.
;;
;; Falls into <WRITE_CRTC_REGISTER>.
;; Uses: A, Y
VDU_23_CRTC:
    lda VDU_QUEUE+2
    ldy VDU_QUEUE+1

;; Writes a 6845 register, adjusting the registers the MOS keeps track of.
;;
;; Register 7, the vertical sync position, has *TV's adjustment added, and one more from the carry the compare
;; leaves. Register 8, the interlace, has its bit 0 flipped by *TV's interlace setting unless the value's bit 7 is set.
;; Register 10, the cursor start, is remembered in <CURSOR_START>, but after VDU 5 is not written, which keeps the
;; cursor hidden.
;; In: A = the value, Y = the register
;; Uses: A, Y
;; Entry: WRITE_CRTC_REGISTER_NOW = writes A to register Y as it is
WRITE_CRTC_REGISTER:
    cpy #CRTC_VERTICAL_SYNC
    bcc WRITE_CRTC_REGISTER_NOW
    bne WRITE_CRTC_REGISTER_1
    adc TV_VERTICAL_ADJUST          ; carry is set: one more
WRITE_CRTC_REGISTER_1:
    cpy #CRTC_INTERLACE
    bne WRITE_CRTC_REGISTER_2
    ora #0
    bmi WRITE_CRTC_REGISTER_2
    eor TV_INTERLACE
WRITE_CRTC_REGISTER_2:
    cpy #CRTC_CURSOR_START
    bne WRITE_CRTC_REGISTER_NOW
    sta CURSOR_START
    tay
    lda VDU_STATUS
    and #VDU_STATUS_GRAPHICS_TEXT
    php
    tya
    ldy #CRTC_CURSOR_START
    plp
    bne WRITE_CRTC_REGISTER_DONE
WRITE_CRTC_REGISTER_NOW:
    sty CRTC_ADDRESS
    sta CRTC_DATA
WRITE_CRTC_REGISTER_DONE:
    rts

;; VDU 25: PLOT, like BASIC's PLOT, through Graphics.asm, or through VDUV (<UNKNOWN_PLOT>) in a mode without
;; graphics.
;; In: VDU_QUEUE+4 = the PLOT code, VDU_QUEUE+5..VDU_QUEUE_END = the X and Y co-ordinates
;; Uses: A, X, Y, VDU_TEMP
VDU_PLOT:
    ldx PIXELS_PER_BYTE
    beq UNKNOWN_PLOT
    jmp PLOT

;; Scrolls the whole screen down a line in hardware: moves the screen's start back a row, wrapping below the screen's
;; first address, and tells the 6845.
;; Uses: A, X, Y, VDU_TEMP
HARDWARE_SCROLL_DOWN:
    ldx SCREEN_START
    lda SCREEN_START+1
    jsr SUBTRACT_ROW
    bcs SET_SCREEN_START
    adc SCREEN_SIZE                 ; below the screen: wrap to its end
    bcc SET_SCREEN_START            ; always

;; Scrolls the whole screen up a line in hardware: moves the screen's start on a row, wrapping past &7FFF, and tells
;; the 6845.
;; Out: zero = clear
;; Uses: A, X, Y, VDU_TEMP
;; Entry: SET_SCREEN_START = stores A and X as <SCREEN_START> and tells the 6845
HARDWARE_SCROLL_UP:
    ldx SCREEN_START
    lda SCREEN_START+1
    jsr ADD_ROW
    bpl SET_SCREEN_START
    sec
    sbc SCREEN_SIZE
SET_SCREEN_START:
    sta SCREEN_START+1
    stx SCREEN_START
    ldy #CRTC_START_ADDRESS
    bne WRITE_CRTC_ADDRESS          ; always

;; VDU 26: restores the default text and graphics windows, the whole screen, and homes the text cursor.
;;
;; It clears the VDU variables from <GRAPHICS_WINDOW> to GRAPHICS_WORK+4, which also zeroes the origin and the cursors,
;; sets the text window to the mode's size, and sets the graphics window to 0,0-1279,1023 through
;; <VDU_GRAPHICS_WINDOW>.
;;
;; Falls into <SET_TEXT_CURSOR_ADDRESS>.
;; Uses: A, X, Y, VDU_TEMP
VDU_DEFAULT_WINDOWS:
    lda #0
    ldx #<(GRAPHICS_WORK + 4)
VDU_DEFAULT_WINDOWS_CLEAR:
    sta GRAPHICS_WINDOW,x
    dex
    bpl VDU_DEFAULT_WINDOWS_CLEAR
    ldx SCREEN_MODE
    ldy MODE_LAST_COLUMN,x
    sty TEXT_WINDOW_RIGHT
    jsr SET_TEXT_WINDOW_WIDTH
    ldy MODE_LAST_ROW,x
    sty TEXT_WINDOW_BOTTOM
    ldy #3                          ; VDU 24's top, &03FF, and right, &04FF
    sty VDU_QUEUE_END
    iny
    sty VDU_QUEUE+6
    dec VDU_QUEUE+7
    dec VDU_QUEUE+5
    jsr VDU_GRAPHICS_WINDOW
    lda #~VDU_STATUS_WINDOW & $FF
    jsr CLEAR_VDU_STATUS
    ldx SCREEN_START
    lda SCREEN_START+1

;; Moves the text cursor's address and tells the 6845, wrapping the cell's address into screen memory.
;;
;; <TEXT_CURSOR_ADDRESS> keeps the address as given, which can be past &7FFF as the 6845 counts; <TEXT_CELL> gets the
;; address in memory.
;;
;; Falls into <SET_CRTC_CURSOR>.
;; In: A = the high byte of the address, X = its low byte
;; Uses: A, X, Y, VDU_TEMP
SET_TEXT_CURSOR_ADDRESS:
    stx TEXT_CURSOR_ADDRESS
    sta TEXT_CURSOR_ADDRESS+1
    bpl SET_CRTC_CURSOR
    sec
    sbc SCREEN_SIZE

;; Sets <TEXT_CELL> and moves the 6845's cursor to <TEXT_CURSOR_ADDRESS>.
;;
;; Falls into <WRITE_CRTC_ADDRESS>.
;; In: A = the high byte of the text cell's address, X = its low byte
;; Uses: A, X, Y, VDU_TEMP
SET_CRTC_CURSOR:
    stx TEXT_CELL
    sta TEXT_CELL+1
    ldx TEXT_CURSOR_ADDRESS
    lda TEXT_CURSOR_ADDRESS+1
    ldy #CRTC_CURSOR_ADDRESS

;; Writes a screen address to a pair of 6845 address registers, the start or the cursor.
;;
;; The 6845 counts characters, not bytes: in modes 0-6 it takes the address divided by 8. In teletext it takes the
;; address less &7400 with bit 13 flipped, which the video ULA reads as teletext memory.
;; In: A = the high byte of the address, X = its low byte, Y = the first register, <CRTC_START_ADDRESS> or
;;   <CRTC_CURSOR_ADDRESS>
;; Out: A = the high byte written, X = the low byte
;; Uses: Y, VDU_TEMP
;; Entry: WRITE_CRTC_PAIR = writes A and X to registers Y and Y + 1 as they are
WRITE_CRTC_ADDRESS:
    pha
    lda SCREEN_MODE
    cmp #MODE_TELETEXT
    pla
    bcs WRITE_CRTC_ADDRESS_TELETEXT
    stx VDU_TEMP
    lsr a
    ror VDU_TEMP
    lsr a
    ror VDU_TEMP
    lsr a
    ror VDU_TEMP
    ldx VDU_TEMP
    jmp WRITE_CRTC_PAIR
WRITE_CRTC_ADDRESS_TELETEXT:
    sbc #$74                        ; carry is set
    eor #$20
WRITE_CRTC_PAIR:
    sty CRTC_ADDRESS
    sta CRTC_DATA
    iny
    sty CRTC_ADDRESS
    stx CRTC_DATA
    rts

;; VDU 24: sets the graphics window from its left, bottom, right and top co-ordinates, relative to the origin.
;;
;; A window whose right is left of its left or whose top is below its bottom, or one that is off the screen once
;; converted to internal co-ordinates, is ignored. The conversion (<CONVERT_ABSOLUTE_POINT>) records each point as the
;; graphics cursor, so the real <GRAPHICS_CURSOR> waits in <GRAPHICS_WORK> meanwhile.
;; In: VDU_QUEUE+1..VDU_QUEUE+4 = the left and bottom, VDU_QUEUE+5..VDU_QUEUE_END = the right and top, two bytes each
;; Uses: A, X, Y, VDU_TEMP
VDU_GRAPHICS_WINDOW:
    jsr VDU_GRAPHICS_WINDOW_SWAP
    ldx #<(VDU_QUEUE + 1)
    ldy #<(GRAPHICS_WORK + 4)
    jsr POINT_DELTAS                       ; the width and height
    ora GRAPHICS_WORK+5
    bmi VDU_GRAPHICS_WINDOW_SWAP    ; either is negative
    ldx #<(VDU_QUEUE + 5)
    jsr CONVERT_ABSOLUTE_POINT                       ; the top right to internal co-ordinates
    ldx #<(VDU_QUEUE + 1)
    jsr CONVERT_ABSOLUTE_POINT                       ; the bottom left
    lda VDU_QUEUE+4
    ora VDU_QUEUE+2
    bmi VDU_GRAPHICS_WINDOW_SWAP    ; below or left of the screen
    lda VDU_QUEUE_END
    bne VDU_GRAPHICS_WINDOW_SWAP    ; above the screen
    ldx SCREEN_MODE
    lda VDU_QUEUE+6
    sta VDU_TEMP
    lda VDU_QUEUE+5
    lsr VDU_TEMP
    ror a
    lsr VDU_TEMP
    bne VDU_GRAPHICS_WINDOW_SWAP    ; right of the screen
    ror a
    lsr a                           ; the right edge's character column
    cmp MODE_LAST_COLUMN,x
    beq VDU_GRAPHICS_WINDOW_SET
    bpl VDU_GRAPHICS_WINDOW_SWAP    ; right of the screen
VDU_GRAPHICS_WINDOW_SET:
    ldy #<GRAPHICS_WINDOW
    ldx #<(VDU_QUEUE + 1)
    jsr COPY_POINTS
VDU_GRAPHICS_WINDOW_SWAP:
    ldx #<GRAPHICS_CURSOR
    ldy #<GRAPHICS_WORK
    jmp SWAP_VDU_POINTS

;; Sets <TEXT_WINDOW_WIDTH> from the window's columns less one: the columns times the bytes per character.
;; In: Y = the last column less the first
;; Uses: A, Y
SET_TEXT_WINDOW_WIDTH:
    iny
    tya
    ldy #0
    sty TEXT_WINDOW_WIDTH+1
    sta TEXT_WINDOW_WIDTH
    lda BYTES_PER_CHARACTER
    lsr a
    beq SET_TEXT_WINDOW_WIDTH_DONE  ; teletext: one byte each
SET_TEXT_WINDOW_WIDTH_LOOP:
    asl TEXT_WINDOW_WIDTH
    rol TEXT_WINDOW_WIDTH+1
    lsr a
    bcc SET_TEXT_WINDOW_WIDTH_LOOP
SET_TEXT_WINDOW_WIDTH_DONE:
    rts

;; VDU 29: sets the graphics origin, and recalculates the graphics cursor relative to it.
;; In: VDU_QUEUE+5..VDU_QUEUE_END = the origin's X and Y co-ordinates, two bytes each
;; Uses: A, X, Y, VDU_TEMP
VDU_ORIGIN:
    ldx #<(VDU_QUEUE + 5)
    ldy #<GRAPHICS_ORIGIN
    jsr COPY_POINT
    jmp UPDATE_EXTERNAL_CURSOR

;; VDU 127: delete. Moves the cursor back a character and erases the character there.
;;
;; It draws a space from the font in the text colours, or a teletext space; after VDU 5 it plots character 127, a
;; solid block, in the graphics background colour at the graphics cursor.
;; Uses: A, X, Y, VDU_TEMP
VDU_DELETE:
    jsr VDU_BACKSPACE
    jsr TEST_GRAPHICS_TEXT
    bne VDU_DELETE_GRAPHICS
    ldx COLOUR_COUNT
    beq VDU_DELETE_TELETEXT
    sta VDU_TEMP+4                  ; A = 0 = <FONT: the space's shape
    lda #>FONT
    sta VDU_TEMP+5
    jmp WRITE_CHARACTER_SHAPE
    .assert <FONT = 0, "The space's shape starts a page."
VDU_DELETE_TELETEXT:
    lda #' '
    jmp WRITE_TELETEXT_CHARACTER
VDU_DELETE_GRAPHICS:
    lda #VDU_CODE_DELETE
    jsr FIND_CHARACTER_DEFINITION                       ; character 127's shape
    ldx GRAPHICS_BACKGROUND
    ldy #0
    jmp PLOT_CHARACTER_IN_COLOUR

;; Adds a character row's bytes to a screen address.
;; In: A = the high byte of the address, X = its low byte
;; Out: A = the high byte of the sum, X = its low byte, negative = set when it is past &7FFF
;; Keeps: Y
ADD_ROW:
    pha
    txa
    clc
    adc BYTES_PER_ROW
    tax
    pla
    adc BYTES_PER_ROW+1
    rts

;; Restarts the paged mode count while CTRL and SHIFT stop the output, then falls into <PAUSE_OUTPUT>.
;; Uses: A, X, Y
PAUSE_OUTPUT_RESTART:
    jsr PAUSE_OUTPUT_RESET

;; Pauses output while CTRL and SHIFT are held, and in paged mode when the text window has filled since the last pause,
;; until SHIFT is pressed; then counts a line in <PAGED_LINES>.
;;
;; A page is full when <PAGED_LINES>, plus the cursor's row over 4, plus one and the window's top, reaches the window's
;; bottom, so it pauses when about three quarters of the window has gone by, keeping the rest of the page before in
;; view. Paged mode does not pause while cursor editing or while scrolling is off. While it waits,
;; <REFLECT_KEYBOARD_STATUS> lights the CAPS LOCK and SHIFT LOCK lights.
;; In: carry = clear
;; Uses: A, X, Y
PAUSE_OUTPUT:
    jsr REFLECT_KEYBOARD_STATUS                       ; carry = CTRL, negative = SHIFT
    bcc PAUSE_OUTPUT_PAGED
    bmi PAUSE_OUTPUT_RESTART        ; CTRL and SHIFT: wait
PAUSE_OUTPUT_PAGED:
    lda VDU_STATUS
    eor #VDU_STATUS_PAGED
    and #VDU_STATUS_EDITING | VDU_STATUS_PAGED | VDU_STATUS_NO_SCROLL
    bne PAUSE_OUTPUT_DONE           ; not paged, or editing or not scrolling
    lda PAGED_LINES
    bmi PAUSE_OUTPUT_COUNT
    lda TEXT_CURSOR_Y
    cmp TEXT_WINDOW_BOTTOM
    bcc PAUSE_OUTPUT_COUNT
    lsr a
    lsr a
    sec
    adc PAGED_LINES
    adc TEXT_WINDOW_TOP
    cmp TEXT_WINDOW_BOTTOM
    bcc PAUSE_OUTPUT_COUNT
    clc
PAUSE_OUTPUT_WAIT:
    jsr REFLECT_KEYBOARD_STATUS                       ; carry set after the first: light the lock lights
    sec
    bpl PAUSE_OUTPUT_WAIT           ; until SHIFT
PAUSE_OUTPUT_RESET:
    lda #$FF
    sta PAGED_LINES
PAUSE_OUTPUT_COUNT:
    inc PAGED_LINES
PAUSE_OUTPUT_DONE:
    rts

;; Resets the VDU driver: clears the VDU workspace and the VDU status, implodes the font, and selects a mode.
;;
;; Falls into <SET_MODE>.
;; In: A = the mode, in its low three bits
;; Uses: A, X, Y, VDU_TEMP, OS_SCRATCH
RESET_VDU:
    pha
    ldx #$7F
    lda #0
    sta VDU_STATUS
RESET_VDU_CLEAR:
    sta GRAPHICS_WINDOW - 1,x       ; &0300-&037E
    dex
    bne RESET_VDU_CLEAR
    jsr EXPLODE_FONT                ; X = 0: implode
    pla
    ldx #TELETEXT_BLOCK
    stx TELETEXT_CURSOR

;; Selects a screen mode: sets the mode's variables, the hardware and the 6845, then the default colours and windows,
;; and clears the screen.
;;
;; A machine with 16K of RAM gives modes 4-7 for modes 0-3. The mode's tables give its colours, the bytes per
;; character, the pixels per byte and the pixel masks, and its memory map type gives the screen's size and start, the
;; screen wrap latch bits, the row table and the row size. The paged, window, VDU 5 and disabled bits of
;; <VDU_STATUS> are cleared.
;;
;; Falls into <CLEAR_SCREEN>.
;; In: A = the mode
;; Uses: A, X, Y, VDU_TEMP, OS_SCRATCH
SET_MODE:
    bit AVAILABLE_RAM
    bmi SET_MODE_1                  ; 32K
    ora #4
SET_MODE_1:
    and #7
    tax
    stx SCREEN_MODE
    lda MODE_COLOURS,x
    sta COLOUR_COUNT
    lda MODE_BYTES_PER_CHARACTER,x
    sta BYTES_PER_CHARACTER
    lda MODE_PIXELS_PER_BYTE,x
    sta PIXELS_PER_BYTE
    bne SET_MODE_MASKS
    lda #7                          ; no graphics: the two-colour masks
SET_MODE_MASKS:
    asl a
    tay
    lda PIXEL_MASKS,y               ; the rightmost pixel's mask
    sta RIGHT_COLOUR_MASK
SET_MODE_LEFT_MASK:
    asl a
    bpl SET_MODE_LEFT_MASK          ; to the leftmost pixel's
    sta LEFT_COLOUR_MASK
    ldy MODE_MAP_TYPE,x
    sty MEMORY_MAP_TYPE
    lda SCREEN_WRAP_LATCH_B4,y
    jsr WRITE_SYSTEM_LATCH
    lda SCREEN_WRAP_LATCH_B5,y
    jsr WRITE_SYSTEM_LATCH
    lda MAP_SCREEN_SIZE,y
    sta SCREEN_SIZE
    lda MAP_SCREEN_START,y
    sta SCREEN_BOTTOM
    tya
    adc #2                          ; carry is clear
    eor #7
    lsr a
    tax                             ; 0 for teletext, 1 for 10K and 8K, 2 for 20K and 16K
    lda ROW_TABLE_LOW,x
    sta ROW_TABLE
    lda #>ROW_OFFSETS_640
    sta ROW_TABLE+1
    lda ROW_SIZE_LOW,x
    sta BYTES_PER_ROW
    stx BYTES_PER_ROW+1
    lda #VDU_STATUS_EDITING | VDU_STATUS_NO_SCROLL | VDU_STATUS_PRINTER
    jsr CLEAR_VDU_STATUS
    ldx SCREEN_MODE
    lda MODE_ULA_CONTROL,x
    jsr SET_VIDEO_ULA_CONTROL
    php
    sei
    ldx CRTC_REGISTERS_LAST,y
    ldy #CRTC_MODE_REGISTERS - 1
SET_MODE_CRTC:
    lda CRTC_REGISTERS,x
    jsr WRITE_CRTC_REGISTER
    dex
    dey
    bpl SET_MODE_CRTC
    plp
    jsr VDU_DEFAULT_COLOURS
    jsr VDU_DEFAULT_WINDOWS

;; Clears the whole screen to the text background colour, resets the hardware scroll and homes the text cursor.
;;
;; It enters <CLEAR_SCREEN_STORES> at the store for the screen's first page, through <VDU_JUMP>, and runs it 256
;; times.
;; Uses: A, X, Y, VDU_TEMP
CLEAR_SCREEN:
    ldx #0
    lda SCREEN_BOTTOM
    stx SCREEN_START
    sta SCREEN_START+1
    jsr SET_TEXT_CURSOR_ADDRESS
    ldy #CRTC_START_ADDRESS
    jsr WRITE_CRTC_PAIR             ; the start, as the cursor was just sent
    lda TEXT_BACKGROUND
    ldx MEMORY_MAP_TYPE
    ldy CLEAR_SCREEN_ENTRIES,x
    sty VDU_JUMP
    ldy #>CLEAR_SCREEN_STORES
    sty VDU_JUMP+1
    ldx #0
    stx PAGED_LINES
    stx TEXT_CURSOR_X
    stx TEXT_CURSOR_Y
    jmp (VDU_JUMP)

;; OSWORD &0A: reads a character's shape.
;; In: A = the character, the block's first byte, OS_X/OS_Y = the parameter block
;; Out: OS_X/OS_Y = the block, with the shape in its second to ninth bytes, top line first
;; Uses: A, X, Y, VDU_TEMP
READ_CHARACTER_DEFINITION:
    jsr FIND_CHARACTER_DEFINITION
    ldy #0
READ_CHARACTER_DEFINITION_LOOP:
    lda (VDU_TEMP+4),y
    iny
    sta (OS_X),y
    cpy #8
    bne READ_CHARACTER_DEFINITION_LOOP
    rts

;; Stores A in the same byte of each page of screen memory, &3000-&7FFF: <CLEAR_SCREEN> runs it from the screen's
;; first page with X = 0-255, through <CALL_VDU_JUMP>.
;; In: A = the byte, X = the offset in each page
;; See: <CLEAR_SCREEN_ENTRIES>
CLEAR_SCREEN_STORES:
.repeat $50, PAGE
    sta $3000 + PAGE * $100,x
.endrepeat
    .assert >CLEAR_SCREEN_STORES = >*, "CLEAR_SCREEN enters the stores with one high byte."
    inx
    beq CHECK_SCROLL_RETURN         ; all 256

;; Jumps through <VDU_JUMP>: <VDU_DRIVER> calls a control code's handler with it, and <CLEAR_SCREEN_STORES> loop
;; through it.
CALL_VDU_JUMP:
    jmp (VDU_JUMP)

;; Subtracts a character row's bytes from a screen address, and compares it with the screen's first address.
;; In: A = the high byte of the address, X = its low byte
;; Out: A = the high byte of the difference, X = its low byte, carry = clear when it is below <SCREEN_BOTTOM>
;; Keeps: Y
;; Entry: SUBTRACT_ROW_RETURN = only returns
SUBTRACT_ROW:
    pha
    txa
    sec
    sbc BYTES_PER_ROW
    tax
    pla
    sbc BYTES_PER_ROW+1
    cmp SCREEN_BOTTOM
SUBTRACT_ROW_RETURN:
    rts

;; OSBYTE &14: explodes the font, giving font zones their own pages of RAM from <PRIMARY_OSHWM> up, or implodes it.
;;
;; Every zone starts at page &0C, <FONT_RAM>, and zones &80-&FF are marked as in RAM. Then the first X zones of
;; <FONT_EXPLOSION_ZONES>, at most six, take a page each, and OSHWM moves above them. Paged ROMs are told with service
;; call &11, the font change warning, with Y = the new OSHWM.
;; In: X = the zones to explode: 0 implodes, 6 or more explodes them all
;; Uses: A, X, Y
EXPLODE_FONT:
    lda #%00001111                  ; zones &80-&FF are in RAM
    sta FONT_FLAGS
    lda #>FONT_RAM
    ldy #6
EXPLODE_FONT_IMPLODE:
    sta FONT_LOCATIONS,y
    dey
    bpl EXPLODE_FONT_IMPLODE
    cpx #7
    bcc EXPLODE_FONT_1
    ldx #6
EXPLODE_FONT_1:
    stx FONT_EXPLOSION
    lda PRIMARY_OSHWM
    ldx #0
EXPLODE_FONT_LOOP:
    cpx FONT_EXPLOSION
    bcs EXPLODE_FONT_DONE
    ldy FONT_EXPLOSION_ZONES,x
    sta FONT_LOCATIONS,y
    adc #1                          ; carry is clear
    inx
    bne EXPLODE_FONT_LOOP           ; always
EXPLODE_FONT_DONE:
    sta OSHWM
    tay
    beq SUBTRACT_ROW_RETURN
    ldx #$11                        ; service call &11: font implosion or explosion
    jmp ISSUE_SERVICE_CALL

;; Decides what happens when the text cursor would scroll the window: continues the scroll, or wraps the cursor.
;;
;; With scrolling off and no cursor editing, the cursor wraps to the other edge of the window and the caller is
;; abandoned for <SET_TEXT_CURSOR>. While cursor editing, the scroll goes ahead and the other cursor, at
;; <OUTPUT_CURSOR_X>, moves with the text, unless it is on the edge row the text leaves.
;; In: carry = set when moving down, clear when moving up
;; Uses: A
;; Entry: CHECK_SCROLL_RETURN = only returns
CHECK_SCROLL:
    lda #VDU_STATUS_NO_SCROLL
    bit VDU_STATUS
    bne CHECK_SCROLL_1
    bvc REMOVE_OUTPUT_CURSOR_DONE           ; scrolling, not editing
CHECK_SCROLL_1:
    lda TEXT_WINDOW_BOTTOM
    bcc CHECK_SCROLL_EDGE
    lda TEXT_WINDOW_TOP
CHECK_SCROLL_EDGE:
    bvs CHECK_SCROLL_EDITING
    sta TEXT_CURSOR_Y               ; wrap to the other edge
    pla
    pla                             ; and abandon the caller
    jmp SET_TEXT_CURSOR
CHECK_SCROLL_EDITING:
    php
    cmp OUTPUT_CURSOR_Y
    beq REMOVE_OUTPUT_CURSOR_FLAGS        ; on the edge the text leaves: it stays there
    plp
    bcc CHECK_SCROLL_DOWN
    dec OUTPUT_CURSOR_Y             ; the text moves up
CHECK_SCROLL_RETURN:
    rts
CHECK_SCROLL_DOWN:
    inc OUTPUT_CURSOR_Y             ; the text moves down
    rts

;; Removes the output cursor that <DRAW_OUTPUT_CURSOR> drew at the text cursor, for cursor editing.
;;
;; In teletext it puts back the character the cursor covered; otherwise it inverts the cell again.
;; Keeps: A, X, P
;; Uses: Y, VDU_TEMP
REMOVE_OUTPUT_CURSOR:
    php
    pha
    ldy BYTES_PER_CHARACTER
    dey
    bne INVERT_TEXT_CELL
    lda TELETEXT_SAVED_CHARACTER
    sta (TEXT_CELL),y
REMOVE_OUTPUT_CURSOR_PULL:
    pla
REMOVE_OUTPUT_CURSOR_FLAGS:
    plp
REMOVE_OUTPUT_CURSOR_DONE:
    rts

;; Draws the output cursor at the text cursor, for cursor editing.
;;
;; In teletext it saves the character there in <TELETEXT_SAVED_CHARACTER> and shows <TELETEXT_CURSOR>; otherwise it
;; inverts the character cell.
;; Keeps: A, X, P
;; Uses: Y, VDU_TEMP
DRAW_OUTPUT_CURSOR:
    php
    pha
    ldy BYTES_PER_CHARACTER
    dey
    bne INVERT_TEXT_CELL
    lda (TEXT_CELL),y
    sta TELETEXT_SAVED_CHARACTER
    lda TELETEXT_CURSOR
    sta (TEXT_CELL),y
    jmp REMOVE_OUTPUT_CURSOR_PULL

;; Inverts the text cursor's character cell, then pulls A and the flags: the rest of <REMOVE_OUTPUT_CURSOR> and
;; <DRAW_OUTPUT_CURSOR>.
;;
;; In the sixteen-colour mode it leaves each pixel's top colour bit alone, so flashing colours do not change.
;; In: Y = the bytes per character less one, STACK = the flags and A, pushed in that order
;; Uses: Y, VDU_TEMP
INVERT_TEXT_CELL:
    lda #$FF
    cpy #31
    bne INVERT_TEXT_CELL_1
    lda #%00111111                  ; sixteen colours: the low three bits of each pixel
INVERT_TEXT_CELL_1:
    sta VDU_TEMP
INVERT_TEXT_CELL_LOOP:
    lda (TEXT_CELL),y
    eor VDU_TEMP
    sta (TEXT_CELL),y
    dey
    bpl INVERT_TEXT_CELL_LOOP
    bmi REMOVE_OUTPUT_CURSOR_PULL           ; always

;; Scrolls the text window down a line in software, copying each row from the one above, from the bottom up.
;;
;; A row that crosses the end of screen memory is copied a character at a time, each address wrapping; others are
;; copied as one run of bytes. The cursor is kept in <GRAPHICS_WORK> meanwhile, and a window one line high is not
;; copied at all.
;;
;; Falls into <SWAP_SAVED_TEXT_CURSOR>.
;; Uses: A, X, Y, VDU_TEMP
SCROLL_WINDOW_DOWN:
    jsr START_WINDOW_SCROLL
    lda TEXT_WINDOW_BOTTOM
    sta TEXT_CURSOR_Y
    jsr CALCULATE_TEXT_CURSOR
SCROLL_WINDOW_DOWN_LOOP:
    jsr SUBTRACT_ROW                ; the row above, the source
    bcs SCROLL_WINDOW_DOWN_SOURCE
    adc SCREEN_SIZE                 ; wrapped: carry is clear afterwards
SCROLL_WINDOW_DOWN_SOURCE:
    sta VDU_TEMP+1
    stx VDU_TEMP
    sta VDU_TEMP+2
    bcs SCROLL_WINDOW_DOWN_FAST
SCROLL_WINDOW_DOWN_SLOW:
    jsr COPY_ROW_BY_CHARACTER
    jmp SCROLL_WINDOW_DOWN_NEXT
SCROLL_WINDOW_DOWN_FAST:
    jsr SUBTRACT_ROW
    bcc SCROLL_WINDOW_DOWN_SLOW     ; the row above that is below the screen's start
    jsr COPY_ROW_FAST
SCROLL_WINDOW_DOWN_NEXT:
    lda VDU_TEMP+2
    ldx VDU_TEMP
    sta TEXT_CELL+1                 ; the source is the next destination
    stx TEXT_CELL
    dec VDU_TEMP+4
    bne SCROLL_WINDOW_DOWN_LOOP

;; Swaps the text cursor with the copy of it in <GRAPHICS_WORK>: saves it before a soft scroll and restores it after.
;;
;; Falls into <SWAP_VDU_PAIR>.
;; Uses: A, X, Y, VDU_TEMP
SWAP_SAVED_TEXT_CURSOR:
    ldx #<GRAPHICS_WORK
    ldy #<TEXT_CURSOR_X

;; Swaps two bytes of VDU workspace with two others.
;; In: X, Y = their offsets in page three
;; Uses: A, X, Y, VDU_TEMP
SWAP_VDU_PAIR:
    lda #2
    bne SWAP_VDU_BYTES              ; always

;; Swaps the graphics cursor, <GRAPHICS_CURSOR_INTERNAL>, with the previous one, <OLD_GRAPHICS_CURSOR>.
;;
;; Falls into <SWAP_WITH_OLD_GRAPHICS_CURSOR>.
;; Uses: A, X, Y, VDU_TEMP
SWAP_GRAPHICS_CURSORS:
    ldx #<GRAPHICS_CURSOR_INTERNAL

;; Swaps a point in VDU workspace with <OLD_GRAPHICS_CURSOR>.
;;
;; Falls into <SWAP_VDU_POINTS>.
;; In: X = the point's offset in page three
;; Uses: A, X, Y, VDU_TEMP
SWAP_WITH_OLD_GRAPHICS_CURSOR:
    ldy #<OLD_GRAPHICS_CURSOR

;; Swaps a point, four bytes of VDU workspace, with another.
;;
;; Falls into <SWAP_VDU_BYTES>.
;; In: X, Y = their offsets in page three
;; Uses: A, X, Y, VDU_TEMP
SWAP_VDU_POINTS:
    lda #4

;; Swaps bytes of VDU workspace with others.
;; In: A = the number of bytes, X, Y = their offsets in page three
;; Uses: A, X, Y, VDU_TEMP
SWAP_VDU_BYTES:
    sta VDU_TEMP
SWAP_VDU_BYTES_LOOP:
    lda GRAPHICS_WINDOW,x
    pha
    lda GRAPHICS_WINDOW,y
    sta GRAPHICS_WINDOW,x
    pla
    sta GRAPHICS_WINDOW,y
    inx
    iny
    dec VDU_TEMP
    bne SWAP_VDU_BYTES_LOOP
    rts

;; Scrolls the text window up a line in software, copying each row from the one below, from the top down.
;;
;; As <SCROLL_WINDOW_DOWN>, a row that crosses the end of screen memory is copied a character at a time.
;; Uses: A, X, Y, VDU_TEMP
SCROLL_WINDOW_UP:
    jsr START_WINDOW_SCROLL
    ldy TEXT_WINDOW_TOP
    sty TEXT_CURSOR_Y
    jsr CALCULATE_TEXT_CURSOR
SCROLL_WINDOW_UP_LOOP:
    jsr ADD_ROW                     ; the row below, the source
    bpl SCROLL_WINDOW_UP_SOURCE
    sec
    sbc SCREEN_SIZE                 ; wrapped: carry is set afterwards
SCROLL_WINDOW_UP_SOURCE:
    sta VDU_TEMP+1
    stx VDU_TEMP
    sta VDU_TEMP+2
    bcc SCROLL_WINDOW_UP_FAST
SCROLL_WINDOW_UP_SLOW:
    jsr COPY_ROW_BY_CHARACTER
    jmp SCROLL_WINDOW_UP_NEXT
SCROLL_WINDOW_UP_FAST:
    jsr ADD_ROW
    bmi SCROLL_WINDOW_UP_SLOW       ; the row below that is past &7FFF
    jsr COPY_ROW_FAST
SCROLL_WINDOW_UP_NEXT:
    lda VDU_TEMP+2
    ldx VDU_TEMP
    sta TEXT_CELL+1                 ; the source is the next destination
    stx TEXT_CELL
    dec VDU_TEMP+4
    bne SCROLL_WINDOW_UP_LOOP
    beq SWAP_SAVED_TEXT_CURSOR      ; always

;; Copies a row of the text window as one run of <TEXT_WINDOW_WIDTH> bytes: whole pages first, then the rest from
;; the end back.
;; In: VDU_TEMP = the source, TEXT_CELL = the destination
;; Uses: A, X, Y, TEXT_CELL, VDU_TEMP
COPY_ROW_FAST:
    ldx TEXT_WINDOW_WIDTH+1
    beq COPY_ROW_FAST_REST
    ldy #0
COPY_ROW_FAST_PAGE:
    lda (VDU_TEMP),y
    sta (TEXT_CELL),y
    iny
    bne COPY_ROW_FAST_PAGE
    inc TEXT_CELL+1
    inc VDU_TEMP+1
    dex
    bne COPY_ROW_FAST_PAGE
COPY_ROW_FAST_REST:
    ldy TEXT_WINDOW_WIDTH
    beq COPY_ROW_FAST_DONE
COPY_ROW_FAST_LOOP:
    dey
    lda (VDU_TEMP),y
    sta (TEXT_CELL),y
    tya
    bne COPY_ROW_FAST_LOOP
COPY_ROW_FAST_DONE:
    rts

;; Prepares a soft scroll: saves the text cursor (<SWAP_SAVED_TEXT_CURSOR>), counts the rows to copy into VDU_TEMP+4,
;; and moves the cursor to the window's left edge.
;;
;; A window one line high has nothing to copy: it restores the cursor and returns from its caller too.
;; Out: VDU_TEMP+4 = the window's height less one, carry = set
;; Uses: A, X, Y, VDU_TEMP
START_WINDOW_SCROLL:
    jsr SWAP_SAVED_TEXT_CURSOR
    sec
    lda TEXT_WINDOW_BOTTOM
    sbc TEXT_WINDOW_TOP
    sta VDU_TEMP+4
    bne TEXT_CURSOR_TO_LEFT
    pla
    pla                             ; abandon the caller
    jmp SWAP_SAVED_TEXT_CURSOR

;; Moves the text cursor to the left edge of the text window, without recalculating its address.
;; Out: carry = set
;; Keeps: X, Y
TEXT_CURSOR_TO_LEFT:
    lda TEXT_WINDOW_LEFT
    bpl CLEAR_TEXT_LINE_SET_X       ; always

;; Copies a row of the text window a character at a time, wrapping both addresses past &7FFF.
;; In: VDU_TEMP = the source, TEXT_CELL = the destination
;; Out: VDU_TEMP = as given
;; Uses: A, X, Y, TEXT_CELL, VDU_TEMP+1, VDU_TEMP+5
COPY_ROW_BY_CHARACTER:
    lda VDU_TEMP
    pha
    sec
    lda TEXT_WINDOW_RIGHT
    sbc TEXT_WINDOW_LEFT
    sta VDU_TEMP+5                  ; the characters less one
COPY_ROW_BY_CHARACTER_NEXT:
    ldy BYTES_PER_CHARACTER
    dey
COPY_ROW_BY_CHARACTER_COPY:
    lda (VDU_TEMP),y
    sta (TEXT_CELL),y
    dey
    bpl COPY_ROW_BY_CHARACTER_COPY
    ldx #2                          ; VDU_TEMP, then TEXT_CELL, on a character
COPY_ROW_BY_CHARACTER_ADVANCE:
    clc
    lda TEXT_CELL,x
    adc BYTES_PER_CHARACTER
    sta TEXT_CELL,x
    lda TEXT_CELL+1,x
    adc #0
    bpl COPY_ROW_BY_CHARACTER_WRAP
    sec
    sbc SCREEN_SIZE
COPY_ROW_BY_CHARACTER_WRAP:
    sta TEXT_CELL+1,x
    dex
    dex
    beq COPY_ROW_BY_CHARACTER_ADVANCE
    dec VDU_TEMP+5
    bpl COPY_ROW_BY_CHARACTER_NEXT
    pla
    sta VDU_TEMP
    rts

;; Clears the text cursor's line of the text window to the text background colour, leaving the cursor where it was.
;; Out: carry = set
;; Uses: A, X, Y, VDU_TEMP+2
;; Entry: CLEAR_TEXT_LINE_SET_X = only sets <TEXT_CURSOR_X> from A, CLEAR_TEXT_LINE_SET_CARRY = only sets carry
CLEAR_TEXT_LINE:
    lda TEXT_CURSOR_X
    pha
    jsr TEXT_CURSOR_TO_LEFT
    jsr CALCULATE_TEXT_CURSOR
    sec
    lda TEXT_WINDOW_RIGHT
    sbc TEXT_WINDOW_LEFT
    sta VDU_TEMP+2                  ; the characters less one
CLEAR_TEXT_LINE_NEXT:
    lda TEXT_BACKGROUND
    ldy BYTES_PER_CHARACTER
CLEAR_TEXT_LINE_FILL:
    dey
    sta (TEXT_CELL),y
    bne CLEAR_TEXT_LINE_FILL
    txa
    clc
    adc BYTES_PER_CHARACTER
    tax
    lda TEXT_CELL+1
    adc #0
    bpl CLEAR_TEXT_LINE_WRAP
    sec
    sbc SCREEN_SIZE
CLEAR_TEXT_LINE_WRAP:
    stx TEXT_CELL
    sta TEXT_CELL+1
    dec VDU_TEMP+2
    bpl CLEAR_TEXT_LINE_NEXT
    pla
CLEAR_TEXT_LINE_SET_X:
    sta TEXT_CURSOR_X
CLEAR_TEXT_LINE_SET_CARRY:
    sec
    rts

;; Checks that the text cursor is inside the text window, and if so calculates its address (<CALCULATE_TEXT_CURSOR>).
;;
;; Falls into <CALCULATE_TEXT_CURSOR>.
;; Out: carry = set when it is outside; otherwise as <CALCULATE_TEXT_CURSOR>
;; Uses: A, X, Y
CHECK_TEXT_CURSOR:
    ldx TEXT_CURSOR_X
    cpx TEXT_WINDOW_LEFT
    bmi CLEAR_TEXT_LINE_SET_CARRY
    cpx TEXT_WINDOW_RIGHT
    beq CHECK_TEXT_CURSOR_ROW
    bpl CLEAR_TEXT_LINE_SET_CARRY
CHECK_TEXT_CURSOR_ROW:
    ldx TEXT_CURSOR_Y
    cpx TEXT_WINDOW_TOP
    bmi CLEAR_TEXT_LINE_SET_CARRY
    cpx TEXT_WINDOW_BOTTOM
    beq CALCULATE_TEXT_CURSOR
    bpl CLEAR_TEXT_LINE_SET_CARRY

;; Calculates the text cursor's address from its column and row: <TEXT_CURSOR_ADDRESS> as the 6845 counts it, and
;; <TEXT_CELL> wrapped into screen memory.
;;
;; The row's offset comes from <ROW_TABLE>, halved for the 10K and 8K modes, and the column is multiplied by the bytes
;; per character with shifts.
;; Out: A = the high byte of <TEXT_CELL>, X = its low byte, carry = clear
;; Uses: Y
CALCULATE_TEXT_CURSOR:
    lda TEXT_CURSOR_Y
    asl a
    tay
    lda (ROW_TABLE),y
    sta TEXT_CELL+1
    iny
    lda #%00000010                  ; map types 2 and 3: 10K and 8K
    and MEMORY_MAP_TYPE
    php
    lda (ROW_TABLE),y
    plp
    beq CALCULATE_TEXT_CURSOR_ADD
    lsr TEXT_CELL+1
    ror a
CALCULATE_TEXT_CURSOR_ADD:
    adc SCREEN_START
    sta TEXT_CELL
    lda TEXT_CELL+1
    adc SCREEN_START+1
    tay
    lda TEXT_CURSOR_X
    ldx BYTES_PER_CHARACTER
    dex
    beq CALCULATE_TEXT_CURSOR_COLUMN ; teletext: one byte
    cpx #15
    beq CALCULATE_TEXT_CURSOR_16
    bcc CALCULATE_TEXT_CURSOR_8
    asl a                           ; 32
CALCULATE_TEXT_CURSOR_16:
    asl a
CALCULATE_TEXT_CURSOR_8:
    asl a
    asl a
    bcc CALCULATE_TEXT_CURSOR_4
    iny
    iny
CALCULATE_TEXT_CURSOR_4:
    asl a
    bcc CALCULATE_TEXT_CURSOR_SUM
    iny
CALCULATE_TEXT_CURSOR_COLUMN:
    clc
CALCULATE_TEXT_CURSOR_SUM:
    adc TEXT_CELL
    sta TEXT_CELL
    sta TEXT_CURSOR_ADDRESS
    tax
    tya
    adc #0
    sta TEXT_CURSOR_ADDRESS+1
    bpl CALCULATE_TEXT_CURSOR_DONE
    sec
    sbc SCREEN_SIZE
CALCULATE_TEXT_CURSOR_DONE:
    sta TEXT_CELL+1
    clc
    rts

;; Plots a character at the graphics cursor in the graphics foreground colour and action: text after VDU 5.
;;
;; Each set pixel of the shape is plotted as a point (<PLOT_AT_CURSOR>), from the cursor rightwards and down. The
;; graphics cursor is put back afterwards.
;; In: VDU_TEMP+4 = the character's shape
;; Uses: A, X, Y, VDU_TEMP
;; Entry: PLOT_CHARACTER_IN_COLOUR = plots in colour X with action Y
PLOT_CHARACTER:
    ldx GRAPHICS_FOREGROUND
    ldy GRAPHICS_FOREGROUND_ACTION
PLOT_CHARACTER_IN_COLOUR:
    jsr SET_GRAPHICS_MASKS
    jsr COPY_CURSOR_TO_WORK                       ; keep the cursor in GRAPHICS_WORK
    ldy #0
PLOT_CHARACTER_ROW:
    sty VDU_TEMP+2
    ldy VDU_TEMP+2
    lda (VDU_TEMP+4),y
    beq PLOT_CHARACTER_NEXT_ROW
    sta VDU_TEMP+3
PLOT_CHARACTER_PIXEL:
    bpl PLOT_CHARACTER_RIGHT
    jsr PLOT_AT_CURSOR
PLOT_CHARACTER_RIGHT:
    inc GRAPHICS_CURSOR_INTERNAL
    bne PLOT_CHARACTER_SHIFT
    inc GRAPHICS_CURSOR_INTERNAL+1
PLOT_CHARACTER_SHIFT:
    asl VDU_TEMP+3
    bne PLOT_CHARACTER_PIXEL        ; while pixels are left
PLOT_CHARACTER_NEXT_ROW:
    ldx #<GRAPHICS_WORK
    ldy #<GRAPHICS_CURSOR_INTERNAL
    jsr COPY_COORDINATE                       ; back to the left
    ldy GRAPHICS_CURSOR_INTERNAL+2
    bne PLOT_CHARACTER_DOWN
    dec GRAPHICS_CURSOR_INTERNAL+3
PLOT_CHARACTER_DOWN:
    dec GRAPHICS_CURSOR_INTERNAL+2
    ldy VDU_TEMP+2
    iny
    cpy #8
    bne PLOT_CHARACTER_ROW
    ldx #<GRAPHICS_WORK
    ldy #<GRAPHICS_CURSOR_INTERNAL
    jmp COPY_POINT

;; Moves the graphics cursor to the top left of the graphics window.
;; Uses: A, X, Y, VDU_TEMP
;; Entry: GRAPHICS_CURSOR_TO_LEFT = moves it to the window's left edge only
HOME_GRAPHICS_CURSOR:
    ldx #<(GRAPHICS_WINDOW + 6)
    ldy #<(GRAPHICS_CURSOR_INTERNAL + 2)
    jsr COPY_COORDINATE
GRAPHICS_CURSOR_TO_LEFT:
    ldx #<GRAPHICS_WINDOW
    ldy #<GRAPHICS_CURSOR_INTERNAL
    jsr COPY_COORDINATE
    jmp UPDATE_EXTERNAL_CURSOR

;; Draws a character at the text cursor in the text colours, or at the graphics cursor after VDU 5.
;;
;; Each byte of the shape becomes a screen byte (two colours), two (four colours, <WRITE_FOUR_COLOUR_CHARACTER>) or
;; four (sixteen colours, in Graphics.asm), as (expansion OR <TEXT_OR_MASK>) EOR <TEXT_EOR_MASK>. Teletext stores the
;; character itself.
;; In: A = the character
;; Uses: A, X, Y, VDU_TEMP
;; Entry: WRITE_CHARACTER_SHAPE = draws the shape at VDU_TEMP+4
WRITE_CHARACTER:
    ldx COLOUR_COUNT
    beq WRITE_TELETEXT_CHARACTER
    jsr FIND_CHARACTER_DEFINITION                       ; VDU_TEMP+4 = the shape
WRITE_CHARACTER_SHAPE:
    ldx COLOUR_COUNT
    lda VDU_STATUS
    and #VDU_STATUS_GRAPHICS_TEXT
    bne PLOT_CHARACTER
    ldy #7
    cpx #3
    beq WRITE_FOUR_COLOUR_CHARACTER
    bcs DRAW_CHARACTER_SIXTEEN_COLOURS                       ; sixteen colours
WRITE_TWO_COLOUR_CHARACTER:
    lda (VDU_TEMP+4),y
    ora TEXT_OR_MASK
    eor TEXT_EOR_MASK
    sta (TEXT_CELL),y
    dey
    bpl WRITE_TWO_COLOUR_CHARACTER
    rts

;; Stores a character at the text cursor in teletext, translating the three characters whose teletext codes differ.
;; In: A = the character, X = 0
;; Uses: A, Y
;; See: <TELETEXT_TRANSLATION>
WRITE_TELETEXT_CHARACTER:
    ldy #2
WRITE_TELETEXT_CHARACTER_FIND:
    cmp TELETEXT_TRANSLATION,y
    beq WRITE_TELETEXT_CHARACTER_TRANSLATE
    dey
    bpl WRITE_TELETEXT_CHARACTER_FIND
WRITE_TELETEXT_CHARACTER_STORE:
    sta (TEXT_CELL,x)
    rts
WRITE_TELETEXT_CHARACTER_TRANSLATE:
    lda TELETEXT_CODES,y
    bne WRITE_TELETEXT_CHARACTER_STORE ; always

;; Draws a character's shape at the text cursor in a four-colour mode: each byte of the shape becomes two screen bytes,
;; its left four pixels in the cell's left column and its right four eight bytes on.
;;
;; The subtraction that steps back to the next line borrows one more, as carry is clear, which also counts the line.
;; In: Y = 7, VDU_TEMP+4 = the shape
;; Uses: A, X, Y
;; Entry: WRITE_CHARACTER_DONE = only returns, which the sixteen-colour writer in Graphics.asm also does
WRITE_FOUR_COLOUR_CHARACTER:
    lda (VDU_TEMP+4),y
    pha
    lsr a
    lsr a
    lsr a
    lsr a
    tax
    lda FOUR_COLOUR_EXPANSION,x
    ora TEXT_OR_MASK
    eor TEXT_EOR_MASK
    sta (TEXT_CELL),y
    tya
    clc
    adc #8
    tay
    pla
    and #$0F
    tax
    lda FOUR_COLOUR_EXPANSION,x
    ora TEXT_OR_MASK
    eor TEXT_EOR_MASK
    sta (TEXT_CELL),y
    tya
    sbc #8                          ; carry is clear: back 9, to the line above
    tay
    bpl WRITE_FOUR_COLOUR_CHARACTER
WRITE_CHARACTER_DONE:
    rts
