;; SOS .GRAFIX DRIVER, RELEASE 1.30
;;
;; The Apple III's graphics driver, as Business BASIC and other programs use it. A program opens .GRAFIX and writes
;; to it: printable characters are drawn on the graphics screen at the pen, in the current character set, and control
;; characters, with the bytes that follow them, set the mode, the viewport, the colors and the pen, and draw points,
;; lines, blocks of dots and clear the viewport. Reading .GRAFIX returns the color of the dot under the pen.
;;
;; The four graphics modes, each with an alternate pair of screen pages (modes 4-7):
;;
;; - 0: 280 by 192, black and white, one 8K page at $2000 ($4000 for mode 4).
;; - 1: 280 by 192, color: the dot page at $2000 and a page of foreground and background colors at $4000, each byte
;;   coloring seven dots ($6000 and $8000 for mode 5).
;; - 2: 560 by 192, black and white, the even bytes of each row at $2000 and the odd ones at $4000 ($6000/$8000).
;; - 3: 140 by 192, 16 colors, seven 4-bit dots in each group of four bytes, two at $2000 and two at $4000
;;   ($6000/$8000).
;;
;; The pages are in the system bank, which the driver reaches with extended addressing (<GRAPHICS_XBYTE>). SOS must
;; have set aside enough of it (GRSIZE); otherwise a write returns <XNOGRMEM>. Y counts up from the bottom row, as in
;; Business BASIC. Writing a dot goes through the transfer mode (store, OR, XOR or BIC, each optionally inverted) and,
;; once a program has changed it, the color operator table, which gives the color for each pair of pen color and
;; screen color.
;;
;; Requests (<GRAFIX_MAIN>): D_READ, D_WRITE, D_STATUS, D_CONTROL, D_OPEN, D_CLOSE and D_INIT. The status requests
;; are 0 (nothing), 1 (Preserve Status Table: the 150-byte <STATE>) and 2 (newline: always off); the control requests
;; are 0 (reset to the configuration block's defaults), 1 (Restore Status Table) and 2 (newline: ignored).
;;
;; Control codes written to the driver (<CODE_TABLE>, with the number of bytes each takes in <ARGCOUNTS>):
;;
;; - 1 Reset Viewport, 2 Set Viewport (left, right, bottom, top), 3 Character Set (address, width, height), 4 Drawblock.
;; - 10 Pen Line Feed, 13 Pen Return, 14 Turn Screen Off, 15 Turn Screen On, 16 Graphics Mode.
;; - 17 Reset Color Operator Table, 18 Set Color Operator Table, 19 Pen Color, 20 Fill Color, 21 Transfer Mode.
;; - 24 Draw Line, 25 Plot Point, 26 Move Pen (each to X, Y), 28 Clear Viewport.
;;
;; Every other control character is ignored. Characters 32-127 and 160-255 are drawn as they are; 128-159 are drawn
;; as the character set's characters 0-31.
;;
;; The DIB (<GRAFIX_DIB>) names the device .GRAFIX, type $62, subtype $01, release 1.30. The configuration block
;; (<DCB>) holds the settings <CONTROL_RESET> restores; the System Configuration Program can change them.
;;
;; The driver's data is laid out from <GRAFIX_DIB>, the code's address 0, which is where SOS relocates it from. Labels
;; and comments are ours: Apple published no source for this driver. The file is split into three: this one (the
;; DIB, the data and the requests), GrafixWrite.asm (writing: characters, control codes, clearing the viewport) and
;; GrafixDraw.asm (blocks of dots, line clipping, screen addresses and the dot routines).
;;
;; Maintained by hand; SOS driver tests check it assembles byte-identically to Apple's .GRAFIX 1.30.

.cpu Mos6502

; ---------------------------------------------------------------------------------------------------------------------
; The DIB's values
; ---------------------------------------------------------------------------------------------------------------------

;; The device type: a character device for graphics.
DEVTYPE = $62

;; The device subtype.
SUBTYPE = $01

;; The manufacturer: Apple.
MANID = $0001

;; The driver's release, 1.30.
RELEASE = $1300

; ---------------------------------------------------------------------------------------------------------------------
; SOS
; ---------------------------------------------------------------------------------------------------------------------

;; The screen mode: bit 7 set = the screen is on, bit 6 set = the graphics driver owns it, bits 0-2 = the display
;; mode switches (<VMODE0>, <VMODE1>, <VMODE2>) to touch.
SCRNMODE = $1906

;; The graphics memory set aside from $2000 in the system bank, in 256-byte pages: $20 for 8K, $40 for 16K, $80
;; for 32K.
GRSIZE = $1907

;; Returns an error to the caller of the request: A = the error code. It does not return here.
SYSERR = $1928

;; The X-bytes of the driver's zero page ($1800): extended addressing through a pointer at $18xx uses the byte at
;; SXPAGE plus the pointer's address plus 1.
SXPAGE = $1400

;; The environment register SOS restores when the request ends; bit 5 set = the screen on.
E_SAVE = $01FE

;; The X-byte that points a zero-page pointer at the system bank's graphics pages.
GRAPHICS_XBYTE = $8F

; ---------------------------------------------------------------------------------------------------------------------
; Errors
; ---------------------------------------------------------------------------------------------------------------------

;; Error: an unknown request.
XREQCODE = $20

;; Error: an unknown status or control code.
XCTLCODE = $21

;; Error: a status or control list of the wrong length.
XCTLPARM = $22

;; Error: the device is not open.
XNOTOPEN = $23

;; Error: the device is already open.
XNOTAVAIL = $24

;; Error: SOS has not set aside the graphics memory the mode needs (<GRSIZE>).
XNOGRMEM = $30

; ---------------------------------------------------------------------------------------------------------------------
; Requests and the request block
; ---------------------------------------------------------------------------------------------------------------------

D_READ = 0                                  ;; Read: the color under the pen.
D_WRITE = 1                                 ;; Write characters and control codes.
D_STATUS = 2                                ;; A status request.
D_CONTROL = 3                               ;; A control request.
D_OPEN = 6                                  ;; Open the device.
D_CLOSE = 7                                 ;; Close the device.
D_INIT = 8                                  ;; Initialize the driver, once, when SOS starts.

;; The request block, which SOS fills in zero page.
SOSINT = $C0

;; The request: <D_READ> to <D_INIT>.
REQCODE = SOSINT + $00

;; D_READ and D_WRITE: the buffer, through extended addressing.
BUFFER = SOSINT + $02

;; D_READ and D_WRITE: the number of bytes.
REQCNT = SOSINT + $04

;; D_READ: the pointer to where the number of bytes read goes.
RTNCNT = SOSINT + $08

;; D_WRITE: the number of bytes taken so far, kept where D_READ's <RTNCNT> is.
WRITTEN = SOSINT + $08

;; D_STATUS and D_CONTROL: the status or control code.
CTLSTAT = SOSINT + $02

;; D_STATUS and D_CONTROL: the pointer to the status or control list.
CSLIST = SOSINT + $03

; ---------------------------------------------------------------------------------------------------------------------
; The hardware
; ---------------------------------------------------------------------------------------------------------------------

;; Black and white when touched; color at VMODE0+1.
VMODE0 = $C050

;; 40 columns when touched; 80 columns at VMODE1+1.
VMODE1 = $C052

;; The first screen page when touched; the second at VMODE2+1.
VMODE2 = $C054

;; Text when touched; graphics at VMODE3+1.
VMODE3 = $C056

; ---------------------------------------------------------------------------------------------------------------------
; Zero page: the drawing position and settings, kept in ZPSAVE between requests
; ---------------------------------------------------------------------------------------------------------------------

;; The address of the current screen row in the first page; extended addressing reaches the graphics pages.
ROW_A = $CA

;; The address of the current screen row in the second page.
ROW_B = $CC

;; The byte of the row that holds the current dot.
COLUMN = $CE

;; The current dot's bits in its byte; in mode 3, its bits in the first page's byte.
MASK = $CF

;; Mode 3: the current dot's bits in the second page's byte.
MASK2 = $D0

;; Mode 3: which of the seven dots of a four-byte group the current dot is, as $F9-$FF.
PHASE = $D1

;; Mode 2: bit 7 set = the current dot's byte is in the second page.
HALF = $D2

;; The character set or block of dots being drawn, through extended addressing.
SOURCE = $D3

;; The screen layout, the graphics mode's low two bits: 0 = 280 black and white, 1 = 280 color, 2 = 560, 3 = 140.
SCREENTYPE = $D5

;; The transfer mode's operation: bits 7 and 6 = %00 store, %01 OR, %10 XOR, %11 BIC.
OPERATION = $D6

;; Bit 7 set = invert the color before the operation; bit 6 set = the color operator table is not the default.
DRAWFLAGS = $D7

;; Bit 7 set = the dots of each byte of the character set or block run from bit 7; clear = from bit 0.
BITORDER = $D8

;; The number of zero-page bytes from <ROW_A> kept in <ZPSAVE>.
ZPSAVE_LEN = $0F

; ---------------------------------------------------------------------------------------------------------------------
; Zero page: work areas
; ---------------------------------------------------------------------------------------------------------------------

;; A difference or other 16-bit work value.
DIFF = $D9

;; <SET_ROW>'s work byte.
TEMP = $D9

;; <TRACE_LINE>: bit 7 set = the line goes up the screen, bit 6 set = it goes left.
LINE_DIR = $D9

;; <TRACE_LINE>: the distance across, a 16-bit count of dots.
LINE_DX = $DD

;; <TRACE_LINE>: the distance up or down, in rows.
LINE_DY = $DB

;; <TRACE_LINE>: the number of dots left to draw.
STEPS = $E1

;; <TRACE_LINE>: the error term between the two directions.
LINE_ERR = $E3

;; <FIND_EDGE>: the bits shifted out when halving the X sum.
ROUNDX = $DB

;; <FIND_EDGE>: the bits shifted out when halving the Y sum.
ROUNDY = $DD

;; <FIND_EDGE>: the edges both ends of the segment are past.
INSIDE = $DF

;; <COPY_POINT>: the number of bytes left to copy.
COPYCOUNT = $E0

;; The points of <CLIP_LINE>, five bytes each: X, Y and the <OUTCODE>.
POINTS = $E1

;; The near end of the segment <FIND_EDGE> halves.
SEG_A = POINTS + 0

;; The far end of the segment <FIND_EDGE> halves.
SEG_B = POINTS + 5

;; The middle of the segment.
MIDPOINT = POINTS + 10

;; The line's start: X, Y and the outcode.
LINE_START = POINTS + 15

;; The line's end: X, Y and the outcode.
LINE_END = POINTS + 20

;; The color written to a 280 color byte's low nibble: the background.
BACKCOLOR = $DF

;; Mode 3: the current dot's color bits in its first-page byte.
PAGEA_BITS = $DF

;; The color written to a 280 color byte's high nibble: the foreground.
FORECOLOR = $E0

;; <OPERATE>: the screen color.
SCRNCOLOR = $DC

;; Mode 1: the column whose color byte was last written.
LASTCOL = $E5

;; Mode 1: bit 7 set once the color byte at <LASTCOL> on the current row is written; moving to another row clears it.
COLORDONE = $E7

;; The number of rows left to draw.
ROWS = $E8

;; The dot position at the start of each row: <COLUMN>, <MASK>, <MASK2>, <PHASE> and <HALF>.
ROWSTART = $E9

;; <CLEAR_VIEWPORT>: the dots left before the first whole byte group, as -1 less the count, counted up.
LEADPIX = $EE

;; <CLEAR_VIEWPORT>: the whole byte pairs left.
PAIRS = $F0

;; <CLEAR_VIEWPORT>: the dots left after the last whole byte group.
TRAILPIX = $F1

;; <CLEAR_VIEWPORT>: the left edge's byte.
LEFTCOL = $F2

;; <CLEAR_VIEWPORT>: each row's <LEADPIX>.
LEADCNT = $F3

;; <CLEAR_VIEWPORT>: each row's <PAIRS>.
PAIRCNT = $F5

;; <CLEAR_VIEWPORT>: each row's <TRAILPIX>.
TRAILCNT = $F6

;; <CLEAR_VIEWPORT>: the right edge's byte.
RIGHTCOL = $F7

;; <DRAW_BITMAP>: the X of the block's first visible dot.
BMX = $F5

;; <DRAW_BITMAP>: the Y of the block's top visible row.
BMY = $F7

;; <DRAW_BITMAP>: the byte of each source row holding the first visible dot.
FIRSTBYTE = $EE

;; <DRAW_BITMAP>: that dot's bit.
FIRSTBIT = $EF

;; <DRAW_BITMAP>: the byte holding the last visible dot.
LASTBYTE = $F0

;; <DRAW_BITMAP>: that dot's bit.
LASTBIT = $F1

;; <DRAW_BITMAP>: the source byte being drawn.
BYTEINDEX = $F2

;; <DRAW_BITMAP>: the bit being drawn.
BITINDEX = $F3

;; <DRAW_BITMAP>: the source byte, shifted to the bit being drawn.
SRCBITS = $F4

; ---------------------------------------------------------------------------------------------------------------------
; Macros
; ---------------------------------------------------------------------------------------------------------------------

;; The default color operator table: 16 rows of 8 bytes, each row's pen color in both nibbles of every byte, so the
;; pen's color replaces any screen color.
.macro DEFAULT_COLORS
.repeat 16, COLOR
    .res 8, COLOR * $11
.endrepeat
.endmacro

; ---------------------------------------------------------------------------------------------------------------------
; The comment record, then the driver
; ---------------------------------------------------------------------------------------------------------------------

DRIVER_COMMENT:
    .word $FFFF
    .word DRIVER_COMMENT_END - DRIVER_COMMENT - 4
    .byte "Copyright (C) 1983 Apple Computer, Inc.  Graphics Driver."
DRIVER_COMMENT_END:
    .logicalorg * - (DRIVER_COMMENT_END - DRIVER_COMMENT)

; ---------------------------------------------------------------------------------------------------------------------
; The device information block and the configuration block
; ---------------------------------------------------------------------------------------------------------------------

;; The device information block (DIB) for .GRAFIX.
GRAFIX_DIB:
    .word $0000                             ; the link to the next DIB: none
    .word GRAFIX_MAIN                       ; the entry point
    .byte 7                                 ; the name's length
    .byte ".GRAFIX        "
    .byte $80                               ; the DIB flags: the device is active
    .byte $00                               ; the slot number
    .byte $00                               ; the unit number
    .byte DEVTYPE
    .byte SUBTYPE
    .byte $00
    .word $0000                             ; the number of blocks: none, a character device
    .word MANID
    .word RELEASE

;; The configuration block's length, which the System Configuration Program reads.
CNFGBLK:
    .word DCB_LEN

;; The configuration block: the settings a reset (<CONTROL_RESET>) and D_OPEN start from, laid out as <STATE>.
DCB:
    .byte 0                                 ; the graphics mode: 280 by 192, black and white
    .byte 0                                 ; the transfer mode: store
    .word 0, 0                              ; the pen: X, Y
    .word 0, 279, 0, 191                    ; the viewport: left, right, bottom, top
    .byte 15                                ; the pen color: white
    .byte 0                                 ; the fill color: black
    .byte $00, $0C, $00                     ; the character set: $0C00 without extended addressing, the system's
    .byte 7, 8                              ; the character cell: width, height
    .byte $80                               ; the character set's bit order: from bit 7

;; The configuration block's default color operator table.
DCB_COLORS:
    DEFAULT_COLORS

;; The length of the configuration block and of <STATE>: 150 bytes.
DCB_LEN = * - DCB

;; The driver's zero page from <ROW_A>, kept here between requests (<LOAD_ZPAGE>, <SAVE_ZPAGE>).
ZPSAVE:
    .res ZPSAVE_LEN

; ---------------------------------------------------------------------------------------------------------------------
; The current settings: the status table, laid out as the configuration block
; ---------------------------------------------------------------------------------------------------------------------

;; The graphics mode, 0-7: the status table's first byte (<STATE>).
GMODE:
    .byte 0

;; The transfer mode, 0-7: store, OR, XOR, BIC, then the same with the color inverted.
XFERMODE:
    .byte 0

;; The pen's X, a signed 16-bit dot position.
PENX:
    .word 0

;; The pen's Y, a signed 16-bit row from the bottom of the screen.
PENY:
    .word 0

;; The viewport's left edge.
VPLEFT:
    .word 0

;; The viewport's right edge.
VPRIGHT:
    .word 279

;; The viewport's bottom edge.
VPBOTTOM:
    .word 0

;; The viewport's top edge.
VPTOP:
    .word 191

;; The pen color, 0-15.
PENCOLOR:
    .byte 15

;; The fill color, 0-15: for clearing the viewport and the 0 bits of characters and blocks.
FILLCOLOR:
    .byte 0

;; The character set's address: low, high and X-byte; $0C00 with X-byte 0 is the system character set.
FONT:
    .byte $00, $0C, $00

;; The character cell's width in dots.
CHARWIDTH:
    .byte 7

;; The character cell's height in rows.
CHARHEIGHT:
    .byte 8

;; The character set's bit order (<BITORDER>), which Apple's manual lists as unused; the system character set is
;; always drawn from bit 0.
FONTORDER:
    .byte $80

;; The color operator table: for each pen color, 8 bytes holding the result for each screen color, two to a byte,
;; the even color in the high nibble.
COLORTABLE:
    DEFAULT_COLORS

;; The status table Preserve Status Table returns and Restore Status Table takes: <GMODE> to the end of
;; <COLORTABLE>, <DCB_LEN> bytes.
STATE = GMODE

;; The copyright notice.
COPYRIGHT:
    .byte "(C) 1980 Apple Computer"

; ---------------------------------------------------------------------------------------------------------------------
; Variables
; ---------------------------------------------------------------------------------------------------------------------

;; Bit 7 set = the device is open.
OPENFLG:
    .byte $00

;; The high byte of the mode's first screen page (<PAGE_A_TABLE>).
PAGE_A:
    .byte $00

;; The high byte of the mode's second screen page (<PAGE_B_TABLE>).
PAGE_B:
    .byte $00

;; The number of bytes each character takes in the character set: <BM_ROWBYTES> times the height.
CHARSIZE:
    .word 8

;; The bytes that fill a byte group with the fill color: the first page's even byte, the second page's even byte,
;; then the odd bytes.
FILLBYTES:
    .res 4

;; The control code waiting for its bytes, or 0.
PENDING:
    .byte $00

;; The number of bytes of the pending control code taken so far, the code included.
ARGINDEX:
    .byte $00

;; The bytes that follow the pending control code.
ARGS:
    .res 32

;; The block of dots to draw (Drawblock, or a character): the bytes in each row of the source.
BM_ROWBYTES:
    .word 1

;; The dots to skip at the start of each source row.
BM_SKIPX:
    .word 0

;; The rows to skip at the top of the source.
BM_SKIPY:
    .word 0

;; The width of the block in dots.
BM_WIDTH:
    .word 7

;; The height of the block in rows.
BM_HEIGHT:
    .word 8

;; $F0 = draw a dot in the fill color; 0 = in the pen color.
USEFILL:
    .byte $00

;; Mode 1: the color byte to write, the foreground color in the high nibble and the background in the low.
COLORBYTE:
    .byte $00

;; Bit 7 set while drawing a block of dots, so mode 1 writes both colors of each color byte.
BITMAPFLG:
    .byte $00

; ---------------------------------------------------------------------------------------------------------------------
; Tables
; ---------------------------------------------------------------------------------------------------------------------

;; The low bytes of the largest X of each screen layout (<SCREENTYPE>).
XLIMIT_LO:
    .byte <279, <279, <559, <139

;; The low byte of the largest Y.
YLIMIT_LO:
    .byte <191

;; The high bytes of the largest X of each screen layout.
XLIMIT_HI:
    .byte >279, >279, >559, >139

;; The high byte of the largest Y.
YLIMIT_HI:
    .byte >191

;; For each group of eight screen rows, the bits of the rows' address high byte, before the page and the row
;; within the group.
ROWHI:
.repeat 24, GROUP
    .byte (GROUP & 7) >> 1
.endrepeat

;; For each group of eight screen rows, the low byte of the rows' address.
ROWLO:
.repeat 24, GROUP
    .byte ((GROUP & 1) << 7) + (GROUP >> 3) * $28
.endrepeat

;; The high byte of each graphics mode's first screen page.
PAGE_A_TABLE:
    .byte $20, $20, $20, $20, $40, $60, $60, $60

;; The high byte of each graphics mode's second screen page. It is also the graphics memory each mode needs, in
;; pages from $2000, which D_WRITE checks against <GRSIZE>.
PAGE_B_TABLE:
    .byte $20, $40, $40, $40, $40, $80, $80, $80

;; Mode 3: each of the seven dots of a group's bits in its second-page byte, then (searched as one run with the
;; tables after it) its bits in its first-page byte.
PIXEL140_B:
    .byte $00, $01, $1E, $60, $00, $07, $78

;; Mode 3: each of the seven dots of a group's bits in its first-page byte.
PIXEL140_A:
    .byte $0F, $70, $00, $03, $3C, $40, $00

;; Seven whole nibbles, ending the run <CLEAR_VIEWPORT> searches.
NIBBLE140:
    .byte $0F, $0F, $0F, $0F, $0F, $0F, $0F

;; The bit for each of a byte's dots.
BITMASKS:
    .byte $01, $02, $04, $08, $10, $20, $40, $80

;; The dots left in a byte group after a position (<PHASE_PIXELS>).
TAILPIXELS:
    .byte 21, 14, 7, 0

;; The dots in a byte group (two bytes of each page) of each screen layout.
GROUPWIDTH:
    .byte 14, 14, 28, 7

;; The row-group bits of a row address's high byte, for BIT.
GROUP_BITS:
    .byte $03

;; The bit above them.
THIRD_BIT:
    .byte $04

;; The bits of a row address's high byte that count the rows within a group of eight, for BIT.
LINE_BITS:
    .byte $1C

; ---------------------------------------------------------------------------------------------------------------------
; The requests
; ---------------------------------------------------------------------------------------------------------------------

;; The driver's entry point: carries out the request in REQCODE.
;; In: REQCODE = the request, with its parameters after it
;; Errors: XREQCODE for an unknown request, and each request's own (through <SYSERR>)
;; See: <REQUEST_TABLE>
GRAFIX_MAIN:
    lda REQCODE
    cmp #D_INIT+1
    bcs BADREQ
    asl a
    tay
    lda REQUEST_TABLE+1,y               ; the routine, less 1, for RTS
    pha
    lda REQUEST_TABLE,y
    pha
    rts

;; Returns <XREQCODE>: the request is not one the driver carries out.
BADREQ:
    lda #XREQCODE
    jsr SYSERR

;; Returns <XNOTOPEN>: the device must be open for the request.
NOTOPEN:
    lda #XNOTOPEN
    jsr SYSERR

;; The routine for each request, less 1, for RTS.
REQUEST_TABLE:
    .word GR_READ-1                         ; D_READ
    .word GR_WRITE-1                        ; D_WRITE
    .word GR_STATUS-1                       ; D_STATUS
    .word GR_CONTROL-1                      ; D_CONTROL
    .word BADREQ-1                          ; 4 and 5: SOS answers them itself
    .word BADREQ-1
    .word GR_OPEN-1                         ; D_OPEN
    .word GR_CLOSE-1                        ; D_CLOSE
    .word GR_INIT-1                         ; D_INIT

;; D_INIT: marks the device closed.
;; Out: OPENFLG = 0
GR_INIT:
    lda #$00
    sta OPENFLG
    rts

;; D_OPEN: resets the settings to the configuration block's and marks the device open.
;; Out: OPENFLG = $80
;; Errors: XNOTAVAIL when the device is already open
;; See: <CONTROL_RESET>
GR_OPEN:
    bit OPENFLG
    bpl GR_OPEN_1
    lda #XNOTAVAIL
    jsr SYSERR
GR_OPEN_1:
    jsr CONTROL_RESET
    lda #$80
    sta OPENFLG
    rts

;; D_CLOSE: marks the device closed.
;; Out: OPENFLG = 0
;; Errors: XNOTOPEN
GR_CLOSE:
    asl OPENFLG
    bcs GR_CLOSE_1
    jmp NOTOPEN
GR_CLOSE_1:
    rts

;; D_STATUS: carries out the status request in CTLSTAT.
;; In: CTLSTAT = the status code, CSLIST = the status list
;; Errors: XNOTOPEN, XCTLCODE for an unknown code
;; See: <STATUS_TABLE>
GR_STATUS:
    bit OPENFLG
    bmi GR_STATUS_1
    jmp NOTOPEN
GR_STATUS_1:
    lda CTLSTAT
    cmp #STATUS_TABLE_LEN
    bcs BADCODE
    asl a
    tay
    lda STATUS_TABLE+1,y
    pha
    lda STATUS_TABLE,y
    pha
    rts

;; Returns <XCTLCODE>: the status or control code is not one the driver knows.
BADCODE:
    lda #XCTLCODE
    jsr SYSERR

;; The routine for each status code, less 1, for RTS.
STATUS_TABLE:
    .word STATUS_NONE-1                     ; 0: the device's status
    .word STATUS_PRESERVE-1                 ; 1: Preserve Status Table
    .word STATUS_NEWLINE-1                  ; 2: the newline setting
STATUS_TABLE_LEN = (* - STATUS_TABLE) / 2

;; Status 0: the device's status, of which there is nothing to report.
STATUS_NONE:
    rts

;; Status 1, Preserve Status Table: copies the settings (<STATE>) to the status list.
;;
;; The list's first byte, the room the list has, must be at least <DCB_LEN>; it becomes DCB_LEN, and the table
;; follows it.
;; In: CSLIST = the list
;; Uses: A, Y
;; Errors: XCTLPARM when the room is too small
STATUS_PRESERVE:
    ldy #$00
    lda (CSLIST),y
    cmp #DCB_LEN
    bcs STATUS_PRESERVE_1
    lda #XCTLPARM
    jsr SYSERR
STATUS_PRESERVE_1:
    lda #DCB_LEN
    sta (CSLIST),y
    tay
STATUS_PRESERVE_2:
    lda a:STATE-1,y
    sta (CSLIST),y
    dey
    bne STATUS_PRESERVE_2
    rts

;; Status 2: the newline setting, which is always off: the list's first byte becomes 0.
;; In: CSLIST = the list
;; Uses: A, Y
STATUS_NEWLINE:
    ldy #$00
    lda #$00
    sta (CSLIST),y
    rts

;; D_CONTROL: carries out the control request in CTLSTAT.
;; In: CTLSTAT = the control code, CSLIST = the control list
;; Errors: XNOTOPEN, XCTLCODE for an unknown code
;; See: <CONTROL_TABLE>
GR_CONTROL:
    bit OPENFLG
    bmi GR_CONTROL_1
    jmp NOTOPEN
GR_CONTROL_1:
    lda CTLSTAT
    cmp #CONTROL_TABLE_LEN
    bcs GR_CONTROL_2
    asl a
    tay
    lda CONTROL_TABLE+1,y
    pha
    lda CONTROL_TABLE,y
    pha
    rts
GR_CONTROL_2:
    jmp BADCODE

;; The routine for each control code, less 1, for RTS.
CONTROL_TABLE:
    .word CONTROL_RESET-1                   ; 0: Reset
    .word CONTROL_RESTORE-1                 ; 1: Restore Status Table
    .word CONTROL_NEWLINE-1                 ; 2: the newline setting
CONTROL_TABLE_LEN = (* - CONTROL_TABLE) / 2

;; Control 0 and D_OPEN: resets the settings to the configuration block's (<DCB>) and makes them take effect.
;; Uses: A, X, Y, STATE
;; See: <APPLY_STATE>
CONTROL_RESET:
    jsr LOAD_ZPAGE
    ldx #DCB_LEN
CONTROL_RESET_1:
    lda a:DCB-1,x
    sta a:STATE-1,x
    dex
    bne CONTROL_RESET_1
    jsr APPLY_STATE
    jsr SAVE_ZPAGE
    rts

;; Control 1, Restore Status Table: takes the settings from the control list and makes them take effect.
;; In: CSLIST = the list: <DCB_LEN>, then a table from Preserve Status Table (<STATUS_PRESERVE>)
;; Uses: A, X, Y, STATE
;; Errors: XCTLPARM when the list's first byte is not DCB_LEN
CONTROL_RESTORE:
    ldy #$00
    lda (CSLIST),y
    cmp #DCB_LEN
    beq CONTROL_RESTORE_1
    lda #XCTLPARM
    jsr SYSERR
CONTROL_RESTORE_1:
    jsr LOAD_ZPAGE
    ldy #DCB_LEN
CONTROL_RESTORE_2:
    lda (CSLIST),y
    dey
    sta a:STATE,y
    bne CONTROL_RESTORE_2
    jsr APPLY_STATE
    jsr SAVE_ZPAGE
    rts

;; Control 2: the newline setting, which the driver does not have; ignored.
CONTROL_NEWLINE:
    rts

;; D_READ: returns the color of the dot under the pen.
;;
;; The byte is the color, 0-15, plus $40, or $80 when the pen is off the screen. The black and white modes give 0 or
;; 15. The count, 1, is stored in the request block's <RTNCNT> itself, not where it points.
;; In: BUFFER = the buffer, which gets the byte
;; Uses: A, X, Y
;; Errors: XNOTOPEN
;; See: <READ_PIXEL>
GR_READ:
    bit OPENFLG
    bmi GR_READ_1
    jmp NOTOPEN
GR_READ_1:
    jsr LOAD_ZPAGE
    lda a:PENX+1
    bmi GR_READ_3
    ldx SCREENTYPE
    lda XLIMIT_LO,x
    cmp a:PENX
    lda XLIMIT_HI,x
    sbc a:PENX+1
    bcc GR_READ_3
    lda a:PENY+1
    bmi GR_READ_3
    lda YLIMIT_LO
    cmp a:PENY
    lda YLIMIT_HI
    sbc a:PENY+1
    bcc GR_READ_3
    lda a:PENY
    jsr SET_ROW
    lda a:PENX
    ldy a:PENX+1
    jsr SET_COLUMN
    jsr READ_PIXEL
    ora #$40
GR_READ_2:
    ldy #$00
    sta (BUFFER),y
    sty RTNCNT+1
    iny
    sty RTNCNT
    jmp SAVE_ZPAGE
GR_READ_3:
    lda #$80
    bne GR_READ_2                       ; always

; ---------------------------------------------------------------------------------------------------------------------
; The zero page and the settings
; ---------------------------------------------------------------------------------------------------------------------

;; Brings the driver's zero page back from <ZPSAVE> and points <ROW_A> and <ROW_B> at the graphics pages.
;;
;; The other X-bytes of $CA-$FF are cleared, so the other pointers address memory normally until set.
;; Out: ROW_A..BITORDER, SXPAGE+ROW_A..SXPAGE+$FF
;; Uses: A, X
LOAD_ZPAGE:
    ldx #ZPSAVE_LEN-1
LOAD_ZPAGE_1:
    lda a:ZPSAVE,x
    sta ROW_A,x
    dex
    bpl LOAD_ZPAGE_1
    ldx #$FF-ROW_A
    lda #$00
LOAD_ZPAGE_2:
    sta SXPAGE+ROW_A,x
    dex
    bpl LOAD_ZPAGE_2
    lda #GRAPHICS_XBYTE                 ; the graphics pages, for ROW_A and ROW_B
    sta SXPAGE+ROW_A+1
    sta SXPAGE+ROW_B+1
    rts

;; Keeps the driver's zero page in <ZPSAVE> until the next request.
;; Uses: A, X
SAVE_ZPAGE:
    ldx #ZPSAVE_LEN-1
SAVE_ZPAGE_1:
    lda ROW_A,x
    sta a:ZPSAVE,x
    dex
    bpl SAVE_ZPAGE_1
    rts

;; Makes the settings in <STATE> take effect.
;;
;; - The graphics mode is cut to 0-7, and gives <SCREENTYPE>, <PAGE_A> and <PAGE_B>.
;; - The fill color gives <FILLBYTES>.
;; - The transfer mode is cut to 0-7, and gives <OPERATION> and <DRAWFLAGS>; BIC is AND with the color inverted.
;; - DRAWFLAGS bit 6 is set when the color operator table differs from the default.
;; - The character set gives <BM_ROWBYTES> and <CHARSIZE>, and <BITORDER>. The system character set ($0C00, X-byte
;;   0) is always 7 by 8, from bit 0.
;; - A negative viewport edge becomes 0, an edge past the screen becomes the screen's, and a left edge right of the
;;   right one, or a bottom above the top, is swapped with it.
;; - When the graphics driver has the screen (<SCRNMODE> bit 6), the screen is turned on or off as SCRNMODE bit 7
;;   says, in <E_SAVE>, and when on, the display switches are set as SCRNMODE's bits 0-2 say.
;; Uses: A, X, Y, STATE, MASK2
APPLY_STATE:
    lda a:GMODE
    and #$07
    sta a:GMODE
    tay
    and #$03                            ; the four screen layouts
    sta SCREENTYPE
    tax
    lda PAGE_A_TABLE,y
    sta PAGE_A
    lda PAGE_B_TABLE,y
    sta PAGE_B
    lda #$00
    sta USEFILL
    sta BITMAPFLG
    lda #$F0
    sta MASK2
    lda a:FILLCOLOR                     ; the fill color in both nibbles
    asl a
    asl a
    asl a
    asl a
    ora a:FILLCOLOR
    pha
    beq APPLY_STATE_1
    cpx #$03
    beq APPLY_STATE_2
    dex
    txa
    beq APPLY_STATE_1
    lda #$FF
APPLY_STATE_1:
    ldx #$03                            ; the fill bits for each byte, seven to a byte
APPLY_STATE_2:
    tay
    lsr a
    sta FILLBYTES,x
    tya
    ror a
    tay
    dex
    bpl APPLY_STATE_2
    pla
    ldx SCREENTYPE                      ; mode 1: the color bytes get both nibbles
    dex
    bne APPLY_STATE_3
    sta FILLBYTES+1
    sta FILLBYTES+3
APPLY_STATE_3:
    ldx #$00
    stx OPERATION
    stx DRAWFLAGS
    stx BITORDER
    lda a:XFERMODE                      ; the transfer mode: bits 0-1 the operation
    and #$07
    sta a:XFERMODE
    lsr a
    ror OPERATION
    lsr a
    ror OPERATION
    bit OPERATION                       ; BIC: invert the color, then AND
    bvc APPLY_STATE_4
    bpl APPLY_STATE_4
    eor #$01
APPLY_STATE_4:
    lsr a                               ; bit 2: invert
    ror DRAWFLAGS
    lda #$FF                            ; compare the table with the default
    ldx #$7F
APPLY_STATE_5:
    ldy #$08
APPLY_STATE_6:
    cmp a:COLORTABLE,x
    bne APPLY_STATE_7
    dex
    dey
    bne APPLY_STATE_6
    sec
    sbc #$11
    bcs APPLY_STATE_5
    bcc APPLY_STATE_8
APPLY_STATE_7:
    lda DRAWFLAGS                       ; not the default
    ora #$40
    sta DRAWFLAGS
APPLY_STATE_8:
    lda #$00
    ldx #$09
APPLY_STATE_9:
    sta BM_ROWBYTES,x
    dex
    bpl APPLY_STATE_9
    sta CHARSIZE
    sta CHARSIZE+1
    lda a:FONT+2                        ; the character set
    sta SXPAGE+SOURCE+1
    lda a:FONT+1
    cmp #$0C
    bne APPLY_STATE_10
    lda a:FONT+2
    bne APPLY_STATE_10
    sta BITORDER                        ; the system set: from bit 0
    bne APPLY_STATE_11                  ; never
    ldx #$07
    stx a:CHARWIDTH
    inx
    stx a:CHARHEIGHT
    jmp APPLY_STATE_11
APPLY_STATE_10:
    lda a:FONTORDER
    sta BITORDER
APPLY_STATE_11:
    ldx a:CHARWIDTH                     ; the bytes in a row of a character
    beq APPLY_STATE_12
    dex
    txa
    lsr a
    lsr a
    lsr a
    tax
    inx
    stx BM_ROWBYTES
APPLY_STATE_12:
    ldx a:CHARHEIGHT                    ; the bytes in a character
    beq APPLY_STATE_14
APPLY_STATE_13:
    clc
    lda BM_ROWBYTES
    adc CHARSIZE
    sta CHARSIZE
    lda CHARSIZE+1
    adc #$00
    sta CHARSIZE+1
    dex
    bne APPLY_STATE_13
APPLY_STATE_14:
    ldx #$06                            ; negative viewport edges become 0
APPLY_STATE_15:
    lda a:VPLEFT+1,x
    bpl APPLY_STATE_16
    lda #$00
    sta a:VPLEFT,x
    sta a:VPLEFT+1,x
APPLY_STATE_16:
    dex
    dex
    bpl APPLY_STATE_15
    ldx #$06                            ; edges past the screen become its edges
    ldy #$04
APPLY_STATE_17:
    lda XLIMIT_LO,y
    cmp a:VPLEFT,x
    lda XLIMIT_HI,y
    sbc a:VPLEFT+1,x
    bcs APPLY_STATE_18
    lda XLIMIT_LO,y
    sta a:VPLEFT,x
    lda XLIMIT_HI,y
    sta a:VPLEFT+1,x
APPLY_STATE_18:
    dex
    dex
    bmi APPLY_STATE_19
    cpx #$04
    bcs APPLY_STATE_17
    ldy SCREENTYPE
    bcc APPLY_STATE_17
APPLY_STATE_19:
    ldx #$04                            ; swap reversed edges
APPLY_STATE_20:
    lda a:VPRIGHT,x
    cmp a:VPLEFT,x
    lda a:VPRIGHT+1,x
    sbc a:VPLEFT+1,x
    bcs APPLY_STATE_21
    ldy a:VPLEFT,x
    lda a:VPRIGHT,x
    sta a:VPLEFT,x
    tya
    sta a:VPRIGHT,x
    ldy a:VPLEFT+1,x
    lda a:VPRIGHT+1,x
    sta a:VPLEFT+1,x
    tya
    sta a:VPRIGHT+1,x
APPLY_STATE_21:
    dex
    dex
    dex
    dex
    bpl APPLY_STATE_20
    bit SCRNMODE                        ; does the graphics driver have the screen?
    bvc APPLY_STATE_29
    bmi APPLY_STATE_22
    lda E_SAVE
    and #$DF
    sta E_SAVE
    jmp APPLY_STATE_29
APPLY_STATE_22:
    lda E_SAVE                          ; on: set the switches as SCRNMODE says
    ora #$20
    sta E_SAVE
    lda SCRNMODE
    lsr a
    bcs APPLY_STATE_23
    bit VMODE0
    bcc APPLY_STATE_24
APPLY_STATE_23:
    bit VMODE0+1
APPLY_STATE_24:
    lsr a
    bcs APPLY_STATE_25
    bit VMODE1
    bcc APPLY_STATE_26
APPLY_STATE_25:
    bit VMODE1+1
APPLY_STATE_26:
    lsr a
    bcs APPLY_STATE_27
    bit VMODE2
    bcc APPLY_STATE_28
APPLY_STATE_27:
    bit VMODE2+1
APPLY_STATE_28:
    bit VMODE3+1
APPLY_STATE_29:
    rts

    .include "GrafixWrite.asm"
    .include "GrafixDraw.asm"
