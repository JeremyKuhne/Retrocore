;; The graphics side of the VDU driver (&D018-&D93F): PLOT and its points, lines, fills and triangles, the conversion
;; of co-ordinates, clipping to the graphics window, reading a point (OSWORD 9) and the character at the text cursor
;; (OSBYTE &87), and the cursor editing keys.
;;
;; External co-ordinates are the ones PLOT takes, 1280 by 1024 from the graphics origin. Internal co-ordinates count
;; pixels from the bottom left corner of the screen: the origin is added, and both are scaled to the mode's pixels, X
;; divided by 2, 4 or 8 and Y by 4. The graphics window, the cursors and the points being drawn are all internal.
;;
;; Most routines here take a point in page three as an offset in X or Y from <VDU_POINTS>: four bytes, the X
;; co-ordinate's low and high bytes, then the Y co-ordinate's. Page three starts a page, so a point's offset is the
;; low byte of its address, written #<NAME. The points are the graphics window's corners (<GRAPHICS_WINDOW>,
;; <WINDOW_TOP_RIGHT>), the cursors (<GRAPHICS_CURSOR>, <OLD_GRAPHICS_CURSOR>, <GRAPHICS_CURSOR_INTERNAL>), PLOT's
;; point (<NEW_POINT>) and the workspace in <GRAPHICS_WORK>.
;;
;; A point's window code, from <POINT_WINDOW_CODE>, says where it lies against the graphics window: zero inside, or
;; the bits <OUTSIDE_LEFT>, <OUTSIDE_RIGHT>, <OUTSIDE_BELOW> and <OUTSIDE_ABOVE>.

; ---------------------------------------------------------------------------------------------------------------------
; Constants
; ---------------------------------------------------------------------------------------------------------------------

; Page three, as the graphics routines index it.
VDU_POINTS = GRAPHICS_WINDOW        ;; the VDU variables in page three, which the routines here index by a point
WINDOW_TOP_RIGHT = GRAPHICS_WINDOW + 4 ;; the graphics window's right column and top row, as a point
PLOT_NUMBER = VDU_QUEUE + 4         ;; PLOT's first parameter, the PLOT number
NEW_POINT = VDU_QUEUE + 5           ;; PLOT's point, the last four bytes of the VDU queue

    .assert <VDU_POINTS = 0, "Page three's points are indexed by the low bytes of their addresses."

; DRAW_LINE's workspace.
DRAW_DELTAS = GRAPHICS_WORK         ;; the cursor less the new point, X then Y; then the minor axis's and the major's
DRAW_POINT = GRAPHICS_WORK + 4      ;; the point being drawn, kept up to date only while the line needs clipping
DRAW_END = GRAPHICS_WORK + 8        ;; the major axis co-ordinate the line ends at
DRAW_MINOR_STEP = GRAPHICS_WORK + 10 ;; the address of the routine that steps one pixel along the minor axis
DRAW_DOTS = GRAPHICS_WORK + 12      ;; bit 7 set when a dotted line leaves out its next point
DRAW_ERROR = GRAPHICS_WORK + 13     ;; the error term, which says when to step along the minor axis
DRAW_MINOR = GRAPHICS_WORK + 15     ;; the line's length along its minor axis
DRAW_MAJOR = GRAPHICS_WORK + 17     ;; the line's length along its major axis

; FILL_TRIANGLE's workspace, the same bytes as DRAW_LINE's.
LONG_EDGE = GRAPHICS_WORK           ;; the edge record of the triangle's edge from its lowest point to its highest
SHORT_EDGE = GRAPHICS_WORK + 11     ;; the edge record of the edge beside the part being filled
TRIANGLE_SAVE = GRAPHICS_WORK + 22  ;; the new point and the cursor, eight bytes, kept while the corners are sorted
TRIANGLE_ROWS = VDU_QUEUE           ;; minus the rows still to fill in the part being filled, two bytes

; The fields of an edge record, which <STEP_EDGE> walks up a row at a time.
EDGE_ERROR = 0                      ;; the error term, which says when to step along X
EDGE_WIDTH = 2                      ;; the edge's width, the difference of its ends' X co-ordinates, made positive
EDGE_HEIGHT = 4                     ;; the edge's height, made positive
EDGE_X = 6                          ;; the X co-ordinate the edge has reached
EDGE_Y = 8                          ;; the row the edge has reached
EDGE_DIRECTION = 10                 ;; bit 7 set when X falls as the edge goes up

; Window codes.
OUTSIDE_LEFT = %0001                ;; the window code bit for a point left of the graphics window
OUTSIDE_RIGHT = %0010               ;; the window code bit for a point right of the graphics window
OUTSIDE_BELOW = %0100               ;; the window code bit for a point below the graphics window
OUTSIDE_ABOVE = %1000               ;; the window code bit for a point above the graphics window

; PLOT numbers and plotting actions.
PLOT_ABSOLUTE = %00000100           ;; the PLOT number bit for absolute co-ordinates; clear for relative ones
PLOT_DOTTED = %00010000             ;; the PLOT number bit for a dotted line, PLOT 16-31
PLOT_MOVE_ABSOLUTE = 4              ;; PLOT 4, which only moves the cursor
PLOT_ACTION_INVERT = 4              ;; the GCOL action that inverts, for PLOT's logical inverse colour
PLOT_ACTION_NONE = 5                ;; an action beyond GCOL's 0-4 that leaves the screen alone, for moves

; ---------------------------------------------------------------------------------------------------------------------
; Text in sixteen colours, and finding a character's shape
; ---------------------------------------------------------------------------------------------------------------------

; The end of each font row in DRAW_CHARACTER_SIXTEEN_COLOURS: back four bytes and up a line, until all eight are done.
DRAW_CHARACTER_SIXTEEN_COLOURS_NEXT_ROW:
    tya
    sbc #$21                        ; carry is set: Y less 32 for the four bytes, less 1 for the line above
    bmi WRITE_CHARACTER_DONE
    tay

;; Draws a character in a sixteen colour mode, two pixels to a screen byte, so that each row of its shape takes four
;; bytes.
;;
;; Each pair of the shape's bits picks a byte of <SIXTEEN_COLOUR_EXPANSION>, which the text colour masks then colour.
;; The row byte is shifted out two bits at a time, with a 1 rotated in behind it: when that marker has been shifted
;; out, the row is done.
;; In: VDU_TEMP+4/VDU_TEMP+5 = the character's shape, from <FIND_CHARACTER_DEFINITION>, TEXT_CELL = the character's
;;   screen address, Y = 7, the bottom row
;; Uses: A, X, Y, VDU_TEMP+2
;; See: <TEXT_OR_MASK>, <TEXT_EOR_MASK>
DRAW_CHARACTER_SIXTEEN_COLOURS:
    lda (VDU_TEMP+4),y
    sta VDU_TEMP+2
    sec                             ; the marker
DRAW_CHARACTER_SIXTEEN_COLOURS_LOOP:
    lda #$00
    rol VDU_TEMP+2
    beq DRAW_CHARACTER_SIXTEEN_COLOURS_NEXT_ROW ; only the marker went out
    rol a
    asl VDU_TEMP+2
    rol a
    tax
    lda SIXTEEN_COLOUR_EXPANSION,x
    ora TEXT_OR_MASK
    eor TEXT_EOR_MASK
    sta (TEXT_CELL),y
    clc
    tya
    adc #$08                        ; the next byte to the right
    tay
    bcc DRAW_CHARACTER_SIXTEEN_COLOURS_LOOP ; always

;; Finds a character's shape: the address of its eight bytes, in ROM or wherever its zone of 32 has been put in RAM.
;;
;; Zones &20-&3F, &40-&5F and &60-&7F are in pages &C0-&C2 of <FONT>. When a zone's bit in <FONT_FLAGS> says it is
;; in RAM, the page is the zone's byte of <FONT_LOCATIONS> instead. The other zones have no shapes in ROM, and only
;; make sense in RAM.
;; In: A = the character
;; Out: VDU_TEMP+4/VDU_TEMP+5 = the address of the character's shape
;; Uses: A, X, Y
FIND_CHARACTER_DEFINITION:
    asl a                           ; A = the character's bits 4-0, 0, 7, 6
    rol a
    rol a
    sta VDU_TEMP+4
    and #$03
    rol a                           ; carry is clear: A = the zone, the character's bits 7-5
    tax
    and #$03
    adc #>FONT-1                    ; the zone's page in ROM
    tay
    lda TWO_COLOUR_MASKS,x          ; the zone's bit in FONT_FLAGS; zone 7's is the first byte of MODE_COLOURS, 1
    bit FONT_FLAGS
    beq FIND_CHARACTER_DEFINITION_PAGE
    ldy FONT_FLAGS,x                ; FONT_LOCATIONS-1,x: the zone's page in RAM
FIND_CHARACTER_DEFINITION_PAGE:
    sty VDU_TEMP+5
    lda VDU_TEMP+4
    and #$F8                        ; the character's bits 4-0, times eight
    sta VDU_TEMP+4
    rts

; ---------------------------------------------------------------------------------------------------------------------
; PLOT
; ---------------------------------------------------------------------------------------------------------------------

;; VDU 25: PLOT, which moves the graphics cursor, and draws a point, a line, a horizontal fill or a triangle.
;;
;; It converts the new point to internal co-ordinates, sets the colour masks from the PLOT number's low two bits (0 a
;; move, 1 the foreground colour, 2 the logical inverse, 3 the background colour), then picks the work from the rest:
;;
;; - 0-31: a line from the cursor; 8-15 and 24-31 plot the new point first, so that when the line inverts the point it
;;   is left out, and 16-31 are dotted.
;; - 32-63: reserved for the Graphics Extension ROM, and passed to VDUV, as are 96-255.
;; - 64-71: a point.
;; - 72-79: a horizontal line from the point left and right to the nearest pixels not in the background colour.
;; - 80-87: a triangle between the point and the last two positions of the cursor.
;; - 88-95: a horizontal line from the point right to the nearest pixel in the background colour.
;;
;; Moves (the low bits 0) go through the same work with masks that change nothing. Each PLOT ends with the cursor at
;; the new point and the old cursor where the cursor was, except that the fills leave the ends of their lines in the
;; two.
;; In: PLOT_NUMBER, NEW_POINT = the VDU queue's PLOT number and point, in external co-ordinates
;; Uses: A, X, Y, VDU_TEMP..VDU_TEMP+5, GRAPHICS_WORK
;; See: <FIND_CHARACTER_DEFINITION>, <DRAW_LINE>, <FILL_LEFT_RIGHT>, <FILL_TRIANGLE>, <VDUV>
PLOT:
    ldx #<NEW_POINT
    jsr CONVERT_PLOT_POINT
    lda PLOT_NUMBER
    cmp #PLOT_MOVE_ABSOLUTE
    beq MOVE_GRAPHICS_CURSOR
    ldy #PLOT_ACTION_NONE           ; a move: the colour in X does not matter
    and #$03
    beq PLOT_SET_MASKS
    lsr a
    bcs PLOT_COLOUR
    dey                             ; 2: invert
    bne PLOT_SET_MASKS              ; always
PLOT_COLOUR:
    tax                             ; 1: the foreground, 3: the background
    ldy GRAPHICS_FOREGROUND_ACTION,x
    lda GRAPHICS_FOREGROUND,x
    tax
PLOT_SET_MASKS:
    jsr SET_GRAPHICS_MASKS
    lda PLOT_NUMBER
    bmi PLOT_UNRECOGNISED           ; 128-255
    asl a
    bpl PLOT_LINE                   ; 0-63
    and #$F0
    asl a                           ; A = the PLOT number's bits 5-3
    beq PLOT_POINT                  ; 64-71
    eor #$40
    beq PLOT_TRIANGLE               ; 80-87
    pha
    jsr SET_GRAPHICS_CURSOR
    pla
    eor #$60
    beq PLOT_FILL_LEFT_RIGHT        ; 72-79
    cmp #$40
    bne PLOT_UNRECOGNISED           ; 96-127, with the internal cursor already at the point
    lda #$02                        ; 88-95: fill right over pixels not in the background colour
    sta VDU_TEMP+2
    jmp FILL_RIGHT
PLOT_TRIANGLE:
    jmp FILL_TRIANGLE
PLOT_UNRECOGNISED:
    jmp UNKNOWN_PLOT
PLOT_FILL_LEFT_RIGHT:
    sta VDU_TEMP+2                  ; zero: fill over pixels in the background colour
    jmp FILL_LEFT_RIGHT

;; Sets the graphics colour masks for a colour and a plotting action, which every point plotted then applies.
;;
;; A screen byte becomes (byte OR <GRAPHICS_OR_MASK>) EOR <GRAPHICS_EOR_MASK>, under the point's pixel mask. The four
;; tables from <GCOL_EOR_SET> give each action the bytes to OR into the colour and then EOR with it: for action 0 the
;; masks are &FF and the colour inverted, which store the colour; for 1, the colour and 0 (OR); for 2, the colour
;; inverted for both (AND); for 3, 0 and the colour (EOR); for 4, 0 and &FF (invert); and for 5, 0 and 0 (no change).
;; In: X = the colour, as a byte of that colour, Y = the action, 0-5
;; Out: GRAPHICS_OR_MASK, GRAPHICS_EOR_MASK
;; Uses: A
;; Keeps: X, Y
SET_GRAPHICS_MASKS:
    txa
    ora GCOL_OR_SET,y
    eor GCOL_OR_FLIP,y
    sta GRAPHICS_OR_MASK
    txa
    ora GCOL_EOR_SET,y
    eor GCOL_EOR_FLIP,y
    sta GRAPHICS_EOR_MASK
    rts

; PLOT 0-63, still in PLOT.
PLOT_LINE:
    asl a
    bmi PLOT_UNRECOGNISED           ; 32-63
    asl a
    asl a
    bpl PLOT_LINE_DRAW              ; bit 3 clear: the last point is drawn
    jsr PLOT_NEW_POINT
PLOT_LINE_DRAW:
    jsr DRAW_LINE
    jmp MOVE_GRAPHICS_CURSOR
PLOT_POINT:
    jsr PLOT_NEW_POINT

;; Moves the graphics cursor to the new point, making the cursor the old cursor.
;; In: NEW_POINT = the new point, GRAPHICS_CURSOR_INTERNAL = the cursor
;; Out: OLD_GRAPHICS_CURSOR = the cursor, GRAPHICS_CURSOR_INTERNAL = the new point
;; Uses: A, X, Y, VDU_TEMP
;; Entry:
;;   SET_GRAPHICS_CURSOR = only copies the new point to the cursor
;;   COPY_NEW_POINT = copies the new point to the point at Y
MOVE_GRAPHICS_CURSOR:
    jsr SWAP_GRAPHICS_CURSORS
SET_GRAPHICS_CURSOR:
    ldy #<GRAPHICS_CURSOR_INTERNAL
COPY_NEW_POINT:
    ldx #<NEW_POINT
    jmp COPY_POINT

;; Plots the graphics cursor's point, if it is inside the graphics window, as VDU 5 text does for each pixel.
;; Out: GRAPHICS_CELL, GRAPHICS_MASK, GRAPHICS_LINE = the cursor's pixel, when it is inside
;; Uses: A, X, Y, VDU_TEMP
PLOT_AT_CURSOR:
    ldx #<GRAPHICS_CURSOR_INTERNAL
    jsr FIND_POINT
    beq PLOT_PIXEL
    rts

;; Plots the new point, if it is inside the graphics window.
;;
;; It falls through into <PLOT_PIXEL>.
;; Out: GRAPHICS_CELL, GRAPHICS_MASK, GRAPHICS_LINE = the point's pixel, when it is inside
;; Uses: A, X, Y, VDU_TEMP
PLOT_NEW_POINT:
    jsr FIND_NEW_POINT
    bne PLOT_PIXEL_DONE

;; Plots the pixels of a screen byte that GRAPHICS_MASK selects, with the graphics colour masks.
;; In: GRAPHICS_CELL, GRAPHICS_LINE, GRAPHICS_MASK = the pixels
;; Out: Y = GRAPHICS_LINE
;; Uses: A, VDU_TEMP
;; Keeps: X
;; Entry: PLOT_PIXEL_AT_Y = plots in the byte at GRAPHICS_CELL + Y
;; See: <SET_GRAPHICS_MASKS>
PLOT_PIXEL:
    ldy GRAPHICS_LINE
PLOT_PIXEL_AT_Y:
    lda GRAPHICS_MASK
    and GRAPHICS_OR_MASK
    ora (GRAPHICS_CELL),y
    sta VDU_TEMP
    lda GRAPHICS_EOR_MASK
    and GRAPHICS_MASK
    eor VDU_TEMP
    sta (GRAPHICS_CELL),y
PLOT_PIXEL_DONE:
    rts

;; Plots every pixel of a screen byte with the graphics colour masks.
;; In: GRAPHICS_CELL = the byte's cell, Y = its offset in the cell
;; Uses: A
;; Keeps: X, Y
PLOT_BYTE:
    lda (GRAPHICS_CELL),y
    ora GRAPHICS_OR_MASK
    eor GRAPHICS_EOR_MASK
    sta (GRAPHICS_CELL),y
    rts

; ---------------------------------------------------------------------------------------------------------------------
; The graphics window and co-ordinates
; ---------------------------------------------------------------------------------------------------------------------

;; Finds the graphics cursor's window code, as <POINT_WINDOW_CODE> does.
;; Out: A, VDU_TEMP = the window code, zero = set when the cursor is inside the window, X = its offset
;; Uses: Y
CURSOR_WINDOW_CODE:
    ldx #<GRAPHICS_CURSOR_INTERNAL

;; Finds a point's window code, which says where it lies against the graphics window: zero inside, or the bits
;; <OUTSIDE_LEFT>, <OUTSIDE_RIGHT>, <OUTSIDE_BELOW> and <OUTSIDE_ABOVE>.
;; In: X = the point's offset
;; Out: A, VDU_TEMP = the window code, zero = set when the point is inside
;; Uses: Y
;; Keeps: X
POINT_WINDOW_CODE:
    ldy #$00
    sty VDU_TEMP
    ldy #$02                        ; Y first: below or above
    jsr AXIS_WINDOW_CODE
    asl VDU_TEMP
    asl VDU_TEMP
    dex                             ; then X: left or right
    dex
    ldy #$00
    jsr AXIS_WINDOW_CODE
    inx
    inx
    lda VDU_TEMP
    rts

;; Adds one co-ordinate's part of a window code to VDU_TEMP: 1 when it is below the window's lower edge on that axis,
;; 2 when it is beyond the upper edge.
;; In: X = the point's offset less 2 for its X co-ordinate, or its offset for Y, Y = 0 for X or 2 for Y
;; Out: VDU_TEMP = the code so far, plus 0, 1 or 2
;; Uses: A
;; Keeps: X, Y
AXIS_WINDOW_CODE:
    lda VDU_POINTS+2,x
    cmp GRAPHICS_WINDOW,y
    lda VDU_POINTS+3,x
    sbc GRAPHICS_WINDOW+1,y
    bmi AXIS_WINDOW_CODE_BELOW
    lda GRAPHICS_WINDOW+4,y
    cmp VDU_POINTS+2,x
    lda GRAPHICS_WINDOW+5,y
    sbc VDU_POINTS+3,x
    bpl AXIS_WINDOW_CODE_DONE
    inc VDU_TEMP
AXIS_WINDOW_CODE_BELOW:
    inc VDU_TEMP
AXIS_WINDOW_CODE_DONE:
    rts

;; Converts a point from absolute external co-ordinates to internal ones, as <CONVERT_POINT> does, for VDU 24 and
;; OSWORD 9.
;; In: X = the point's offset
;; Out: X = the offset less 2, GRAPHICS_CURSOR = the point in external co-ordinates
;; Uses: A, Y, VDU_TEMP
CONVERT_ABSOLUTE_POINT:
    lda #$FF                        ; PLOT_ABSOLUTE is set
    bne CONVERT_POINT               ; always

;; Converts the point at X from external co-ordinates to internal ones, absolute or relative as the PLOT number says.
;;
;; It falls through into <CONVERT_POINT>.
;; In: X = the point's offset, PLOT_NUMBER
;; Out: X = the offset less 2, GRAPHICS_CURSOR = the point in absolute external co-ordinates
;; Uses: A, Y, VDU_TEMP
CONVERT_PLOT_POINT:
    lda PLOT_NUMBER

;; Converts a point from external co-ordinates to internal ones, in place.
;;
;; A relative point is first added to <GRAPHICS_CURSOR>. The absolute point is stored in GRAPHICS_CURSOR, added to the
;; graphics origin, and scaled: Y is divided by four, and X by eight, four or two to give the mode's pixels.
;; In: X = the point's offset, A = a PLOT number, whose <PLOT_ABSOLUTE> bit says whether the point is absolute
;; Out: X = the offset less 2, GRAPHICS_CURSOR = the point in absolute external co-ordinates
;; Uses: A, Y, VDU_TEMP
CONVERT_POINT:
    sta VDU_TEMP
    ldy #$02                        ; Y: divided by 4
    jsr CONVERT_COORDINATE
    jsr HALVE_COORDINATE
    ldy #$00                        ; X: divided by 2, 4 or 8
    dex
    dex
    jsr CONVERT_COORDINATE
    ldy PIXELS_PER_BYTE
    cpy #$03
    beq CONVERT_POINT_FOUR_COLOURS
    bcs CONVERT_POINT_40_COLUMNS    ; two colours
    jsr HALVE_COORDINATE            ; sixteen colours
CONVERT_POINT_FOUR_COLOURS:
    jsr HALVE_COORDINATE
CONVERT_POINT_40_COLUMNS:
    lda MEMORY_MAP_TYPE
    bne HALVE_COORDINATE            ; a mode with 320-byte rows has half the pixels
    rts

;; Converts one co-ordinate of a point to absolute, stores it in GRAPHICS_CURSOR, adds the origin and halves it.
;;
;; It falls through into <HALVE_COORDINATE>.
;; In: X = the point's offset less 2 for its X co-ordinate, or its offset for Y, Y = 0 for X or 2 for Y,
;;   VDU_TEMP = the PLOT number
;; Out: GRAPHICS_CURSOR,Y = the absolute external co-ordinate
;; Uses: A
;; Keeps: X, Y
CONVERT_COORDINATE:
    clc
    lda VDU_TEMP
    and #PLOT_ABSOLUTE
    beq CONVERT_COORDINATE_RELATIVE
    lda VDU_POINTS+2,x
    pha
    lda VDU_POINTS+3,x
    bcc CONVERT_COORDINATE_STORE    ; always
CONVERT_COORDINATE_RELATIVE:
    lda VDU_POINTS+2,x
    adc GRAPHICS_CURSOR,y
    pha
    lda VDU_POINTS+3,x
    adc GRAPHICS_CURSOR+1,y
    clc
CONVERT_COORDINATE_STORE:
    sta GRAPHICS_CURSOR+1,y
    adc GRAPHICS_ORIGIN+1,y
    sta VDU_POINTS+3,x
    pla
    sta GRAPHICS_CURSOR,y
    clc
    adc GRAPHICS_ORIGIN,y
    sta VDU_POINTS+2,x
    bcc HALVE_COORDINATE
    inc VDU_POINTS+3,x

;; Halves a signed co-ordinate, rounding down.
;; In: X = the offset of the co-ordinate less 2
;; Uses: A
;; Keeps: X, Y
HALVE_COORDINATE:
    lda VDU_POINTS+3,x
    asl a                           ; carry = the sign
    ror VDU_POINTS+3,x
    ror VDU_POINTS+2,x
    rts

;; Converts the graphics cursor from internal co-ordinates back to external ones, in <GRAPHICS_CURSOR>, the reverse of
;; <CONVERT_POINT>.
;; In: GRAPHICS_CURSOR_INTERNAL
;; Out: GRAPHICS_CURSOR = the cursor in external co-ordinates
;; Uses: A, X, Y, VDU_TEMP
UPDATE_EXTERNAL_CURSOR:
    ldy #<GRAPHICS_CURSOR
    jsr COPY_CURSOR
    ldx #$02                        ; Y: times 4
    ldy #$02
    jsr UPDATE_EXTERNAL_CURSOR_SCALE
    ldx #$00                        ; X: times 2, 4 or 8
    ldy #$04
    lda PIXELS_PER_BYTE
UPDATE_EXTERNAL_CURSOR_COUNT:
    dey                             ; one shift fewer for each bit of the pixels per byte
    lsr a
    bne UPDATE_EXTERNAL_CURSOR_COUNT
    lda MEMORY_MAP_TYPE
    beq UPDATE_EXTERNAL_CURSOR_SCALE
    iny                             ; a mode with 320-byte rows has half the pixels
UPDATE_EXTERNAL_CURSOR_SCALE:
    asl GRAPHICS_CURSOR,x
    rol GRAPHICS_CURSOR+1,x
    dey
    bne UPDATE_EXTERNAL_CURSOR_SCALE
    sec
    jsr UPDATE_EXTERNAL_CURSOR_ORIGIN
    inx
UPDATE_EXTERNAL_CURSOR_ORIGIN:
    lda GRAPHICS_CURSOR,x
    sbc GRAPHICS_ORIGIN,x
    sta GRAPHICS_CURSOR,x
    rts

; ---------------------------------------------------------------------------------------------------------------------
; Lines
; ---------------------------------------------------------------------------------------------------------------------

;; Draws a line from the graphics cursor to the new point, clipped to the graphics window, for PLOT 0-31.
;;
;; The line's major axis is the one it is longer along. It is drawn from the end with the lower co-ordinate on that
;; axis, one pixel at a time along it, stepping along the minor axis whenever the error term <DRAW_ERROR> runs out
;; (Bresenham's method). Both ends are drawn. A step along the major axis goes through <VDU_JUMP> to
;; <DRAW_LINE_MAJOR_RIGHT> or <DRAW_LINE_MAJOR_UP>, and one along the minor axis through <DRAW_MINOR_STEP> to
;; <DRAW_LINE_STEP_UP>, <DRAW_LINE_STEP_DOWN>, <DRAW_LINE_STEP_RIGHT> or <DRAW_LINE_STEP_LEFT>; the steps move the
;; screen address and pixel mask without working them out again.
;;
;; A line whose ends are both beyond the same side of the window draws nothing, and one that ends beyond the window's
;; far side on the major axis stops at that side. A line that starts inside stops when it leaves the window on the
;; minor axis. One that starts outside is followed one point at a time in <DRAW_POINT>, checking each against the
;; window. A dotted line, PLOT 16-31, draws every other point.
;; In: GRAPHICS_CURSOR_INTERNAL, NEW_POINT = the ends, PLOT_NUMBER, GRAPHICS_OR_MASK, GRAPHICS_EOR_MASK
;; Uses: A, X, Y, VDU_TEMP..VDU_TEMP+5, VDU_JUMP, GRAPHICS_CELL, GRAPHICS_MASK, GRAPHICS_LINE,
;;   GRAPHICS_WORK..GRAPHICS_WORK+18
;; Entry:
;;   DRAW_LINE_STEP_UP = (through DRAW_MINOR_STEP) steps up a pixel
;;   DRAW_LINE_STEP_DOWN = (through DRAW_MINOR_STEP) steps down a pixel
;;   DRAW_LINE_STEP_RIGHT = (through DRAW_MINOR_STEP) steps right a pixel
;;   DRAW_LINE_STEP_LEFT = (through DRAW_MINOR_STEP) steps left a pixel
;;   DRAW_LINE_MAJOR_UP = (through VDU_JUMP) steps up a pixel and counts the point
;;   DRAW_LINE_MAJOR_RIGHT = (through VDU_JUMP) steps right a pixel and counts the point
;; See: <LINE_MAJOR_STEPS>, <LINE_MINOR_STEPS_LOW>, <DRAW_LINE_SETUP>
DRAW_LINE:
    jsr CURSOR_DELTAS
    lda DRAW_DELTAS+3
    eor DRAW_DELTAS+1
    bmi DRAW_LINE_OPPOSITE_SIGNS
    lda DRAW_DELTAS+2               ; the same signs: compare Y less X
    cmp DRAW_DELTAS
    lda DRAW_DELTAS+3
    sbc DRAW_DELTAS+1
    jmp DRAW_LINE_CHOOSE_AXIS
DRAW_LINE_OPPOSITE_SIGNS:
    lda DRAW_DELTAS                 ; opposite signs: compare Y plus X
    clc
    adc DRAW_DELTAS+2
    lda DRAW_DELTAS+1
    adc DRAW_DELTAS+3
DRAW_LINE_CHOOSE_AXIS:
    ror a
    ldx #$00                        ; X major
    eor DRAW_DELTAS+3
    bpl DRAW_LINE_MAJOR_AXIS
    ldx #$02                        ; Y major
DRAW_LINE_MAJOR_AXIS:
    stx VDU_TEMP+4                  ; the major axis: 0 for X, 2 for Y
    lda LINE_MAJOR_STEPS,x
    sta VDU_JUMP
    lda LINE_MAJOR_STEPS_HIGH,x
    sta VDU_JUMP+1
    lda DRAW_DELTAS+1,x
    bpl DRAW_LINE_FROM_NEW_POINT
    ldx #<GRAPHICS_CURSOR_INTERNAL  ; the new point is further along the major axis: start at the cursor
    bne DRAW_LINE_START             ; always
DRAW_LINE_FROM_NEW_POINT:
    ldx #<NEW_POINT
DRAW_LINE_START:
    stx VDU_TEMP+5                  ; the start
    ldy #<DRAW_POINT
    jsr COPY_POINT
    lda VDU_TEMP+5
    eor #<GRAPHICS_CURSOR_INTERNAL ^ <NEW_POINT
    sta VDU_TEMP+3                  ; the end
    ora VDU_TEMP+4
    tax
    jsr COPY_TO_DRAW_END
    lda PLOT_NUMBER
    and #PLOT_DOTTED
    asl a
    asl a
    asl a
    sta VDU_TEMP+1                  ; bit 7 set for a dotted line
    ldx #<DRAW_POINT
    jsr POINT_WINDOW_CODE
    sta VDU_TEMP+2
    beq DRAW_LINE_START_INSIDE
    lda #$40                        ; bit 6 set when the start is outside the window
    ora VDU_TEMP+1
    sta VDU_TEMP+1
DRAW_LINE_START_INSIDE:
    ldx VDU_TEMP+3
    jsr POINT_WINDOW_CODE
    bit VDU_TEMP+2
    beq DRAW_LINE_VISIBLE
    rts                             ; both ends are beyond the same side

DRAW_LINE_VISIBLE:
    ldx VDU_TEMP+4
    beq DRAW_LINE_CLIP_END
    lsr a                           ; Y major: the code's bits for Y
    lsr a
DRAW_LINE_CLIP_END:
    and #OUTSIDE_RIGHT              ; beyond the far side on the major axis: right of the window, or above it
    beq DRAW_LINE_SET_UP
    txa
    ora #<WINDOW_TOP_RIGHT
    tax
    jsr COPY_TO_DRAW_END            ; end at the window's right column or top row
DRAW_LINE_SET_UP:
    jsr DRAW_LINE_SETUP
    lda VDU_TEMP+4
    eor #$02
    tax
    tay                             ; X, Y = the minor axis
    lda DRAW_DELTAS+1
    eor DRAW_DELTAS+3
    bpl DRAW_LINE_MINOR_ROUTINE
    inx                             ; opposite signs: down or left
DRAW_LINE_MINOR_ROUTINE:
    lda LINE_MINOR_STEPS_LOW,x
    sta DRAW_MINOR_STEP
    lda LINE_MINOR_STEPS_HIGH,x
    sta DRAW_MINOR_STEP+1
    lda #$7F
    sta DRAW_DOTS                   ; the first point is drawn
    bit VDU_TEMP+1
    bvs DRAW_LINE_CLIPPED
    lda WINDOW_EDGE_OFFSETS,x                     ; the window's edge the minor axis heads for
    tax
    sec
    lda GRAPHICS_WINDOW,x
    sbc DRAW_POINT,y
    sta VDU_TEMP
    lda GRAPHICS_WINDOW+1,x
    sbc DRAW_POINT+1,y
    ldy VDU_TEMP
    tax
    bpl DRAW_LINE_EDGE_DISTANCE
    jsr NEGATE
DRAW_LINE_EDGE_DISTANCE:
    tax
    iny
    bne DRAW_LINE_EDGE_HIGH
    inx
DRAW_LINE_EDGE_HIGH:
    txa
    beq DRAW_LINE_EDGE_STEPS
    ldy #$00                        ; 256 or more: as many as the line can take
DRAW_LINE_EDGE_STEPS:
    sty VDU_TEMP+5                  ; the minor steps the line takes before it leaves the window
    beq DRAW_LINE_FIRST_POINT
    ; Otherwise this runs on into the clipped line's set-up with X = 0, which sets VDU_TEMP+4 to the minor axis. Only
    ; the clipped line reads it.
DRAW_LINE_CLIPPED:
    txa
    lsr a
    ror a                           ; bit 7 = bit 0 of the step's index: set for down or left
    ora #$02
    eor VDU_TEMP+4
    sta VDU_TEMP+4                  ; the minor axis, with bit 7 set when it goes down or left
DRAW_LINE_FIRST_POINT:
    ldx #<DRAW_POINT
    jsr FIND_POINT_ADDRESS
    ldx VDU_TEMP+2                  ; X, VDU_TEMP+3 = minus the points to draw, counting up to zero
    bne DRAW_LINE_COUNT_LOW
    dec VDU_TEMP+3
DRAW_LINE_COUNT_LOW:
    dex
DRAW_LINE_LOOP:
    lda VDU_TEMP+1
    beq DRAW_LINE_PLOT
    bpl DRAW_LINE_CHECK             ; not dotted, but clipped
    bit DRAW_DOTS
    bpl DRAW_LINE_DOT
    dec DRAW_DOTS
    bne DRAW_LINE_ERROR             ; always: leave this point out
DRAW_LINE_DOT:
    inc DRAW_DOTS
    asl a
    bpl DRAW_LINE_PLOT              ; not clipped
DRAW_LINE_CHECK:
    stx VDU_TEMP+2
    ldx #<DRAW_POINT
    jsr FIND_POINT
    ldx VDU_TEMP+2
    ora #$00                        ; the flags for the window code again, after the LDX
    bne DRAW_LINE_ERROR
DRAW_LINE_PLOT:
    lda GRAPHICS_MASK
    and GRAPHICS_OR_MASK
    ora (GRAPHICS_CELL),y
    sta VDU_TEMP
    lda GRAPHICS_EOR_MASK
    and GRAPHICS_MASK
    eor VDU_TEMP
    sta (GRAPHICS_CELL),y
DRAW_LINE_ERROR:
    sec
    lda DRAW_ERROR
    sbc DRAW_MINOR
    sta DRAW_ERROR
    lda DRAW_ERROR+1
    sbc DRAW_MINOR+1
    bcs DRAW_LINE_STEP
    sta VDU_TEMP
    lda DRAW_ERROR
    adc DRAW_MAJOR
    sta DRAW_ERROR
    lda VDU_TEMP
    adc DRAW_MAJOR+1
    clc                             ; carry clear: a step along the minor axis
DRAW_LINE_STEP:
    sta DRAW_ERROR+1
    php
    bcs DRAW_LINE_MAJOR_STEP
    jmp (DRAW_MINOR_STEP)

; DRAW_LINE's minor axis steps, reached through DRAW_MINOR_STEP, then the jump to the major axis step.
DRAW_LINE_STEP_UP:
    dey
    bpl DRAW_LINE_MAJOR_STEP
    jsr GRAPHICS_ROW_UP
DRAW_LINE_MAJOR_STEP:
    jmp (VDU_JUMP)
DRAW_LINE_STEP_DOWN:
    iny
    cpy #$08
    bne DRAW_LINE_MAJOR_STEP
    clc                             ; the character row below
    lda GRAPHICS_CELL
    adc BYTES_PER_ROW
    sta GRAPHICS_CELL
    lda GRAPHICS_CELL+1
    adc BYTES_PER_ROW+1
    bpl DRAW_LINE_STEP_DOWN_WRAPPED
    sec                             ; past &7FFF: wrap round to the start of the screen
    sbc SCREEN_SIZE
DRAW_LINE_STEP_DOWN_WRAPPED:
    sta GRAPHICS_CELL+1
    ldy #$00
    jmp (VDU_JUMP)
DRAW_LINE_STEP_RIGHT:
    lsr GRAPHICS_MASK
    bcc DRAW_LINE_MAJOR_STEP
    jsr GRAPHICS_CELL_RIGHT
    jmp (VDU_JUMP)
DRAW_LINE_STEP_LEFT:
    asl GRAPHICS_MASK
    bcc DRAW_LINE_MAJOR_STEP
    jsr GRAPHICS_CELL_LEFT
    jmp (VDU_JUMP)

; DRAW_LINE's major axis steps, reached through VDU_JUMP, then the count of the points left.
DRAW_LINE_MAJOR_UP:
    dey
    bpl DRAW_LINE_NEXT_POINT
    jsr GRAPHICS_ROW_UP
    bne DRAW_LINE_NEXT_POINT        ; always: Y = 7
DRAW_LINE_MAJOR_RIGHT:
    lsr GRAPHICS_MASK
    bcc DRAW_LINE_NEXT_POINT
    jsr GRAPHICS_CELL_RIGHT
DRAW_LINE_NEXT_POINT:
    plp                             ; carry clear when the minor axis stepped
    inx
    bne DRAW_LINE_TRACK
    inc VDU_TEMP+3
    beq DRAW_LINE_DONE
DRAW_LINE_TRACK:
    bit VDU_TEMP+1
    bvs DRAW_LINE_MOVE_POINT
    bcs DRAW_LINE_AGAIN
    dec VDU_TEMP+5
    bne DRAW_LINE_AGAIN
DRAW_LINE_DONE:
    rts                             ; the last point, or the line left the window

DRAW_LINE_MOVE_POINT:
    lda VDU_TEMP+4                  ; clipped: move DRAW_POINT with the pixel
    stx VDU_TEMP+2
    and #$02
    tax
    bcs DRAW_LINE_MOVE_MAJOR
    bit VDU_TEMP+4
    bmi DRAW_LINE_MINOR_BACK
    inc DRAW_POINT,x
    bne DRAW_LINE_MOVE_MAJOR
    inc DRAW_POINT+1,x
    bcc DRAW_LINE_MOVE_MAJOR        ; always
DRAW_LINE_MINOR_BACK:
    lda DRAW_POINT,x
    bne DRAW_LINE_MINOR_BACK_LOW
    dec DRAW_POINT+1,x
DRAW_LINE_MINOR_BACK_LOW:
    dec DRAW_POINT,x
DRAW_LINE_MOVE_MAJOR:
    txa
    eor #$02
    tax
    inc DRAW_POINT,x
    bne DRAW_LINE_MOVED
    inc DRAW_POINT+1,x
DRAW_LINE_MOVED:
    ldx VDU_TEMP+2
DRAW_LINE_AGAIN:
    jmp DRAW_LINE_LOOP

;; Moves the graphics point's screen address up a character row, to the bottom line of the cell above, wrapping round
;; from the start of screen memory to its end.
;; Out: GRAPHICS_CELL, Y = 7
;; Uses: A
;; Keeps: X
GRAPHICS_ROW_UP:
    sec
    lda GRAPHICS_CELL
    sbc BYTES_PER_ROW
    sta GRAPHICS_CELL
    lda GRAPHICS_CELL+1
    sbc BYTES_PER_ROW+1
    cmp SCREEN_BOTTOM
    bcs GRAPHICS_ROW_UP_WRAPPED
    adc SCREEN_SIZE
GRAPHICS_ROW_UP_WRAPPED:
    sta GRAPHICS_CELL+1
    ldy #$07
    rts

;; Moves the graphics point to the leftmost pixel of the next screen byte to the right.
;; In: carry = set, as the shift that ran off the byte leaves it
;; Out: GRAPHICS_CELL, GRAPHICS_MASK = <LEFT_COLOUR_MASK>
;; Uses: A
;; Keeps: X, Y
GRAPHICS_CELL_RIGHT:
    lda LEFT_COLOUR_MASK
    sta GRAPHICS_MASK
    lda GRAPHICS_CELL
    adc #$07                        ; plus the carry: 8
    sta GRAPHICS_CELL
    bcc GRAPHICS_CELL_RIGHT_DONE
    inc GRAPHICS_CELL+1
GRAPHICS_CELL_RIGHT_DONE:
    rts

;; Moves the graphics point to the rightmost pixel of the next screen byte to the left.
;;
;; GRAPHICS_CELL is a multiple of eight, so the high byte only needs lowering when the low byte is zero.
;; In: carry = set, as the shift that ran off the byte leaves it
;; Out: GRAPHICS_CELL, GRAPHICS_MASK = <RIGHT_COLOUR_MASK>
;; Uses: A
;; Keeps: X, Y
GRAPHICS_CELL_LEFT:
    lda RIGHT_COLOUR_MASK
    sta GRAPHICS_MASK
    lda GRAPHICS_CELL
    bne GRAPHICS_CELL_LEFT_LOW
    dec GRAPHICS_CELL+1
GRAPHICS_CELL_LEFT_LOW:
    sbc #$08
    sta GRAPHICS_CELL
    rts

;; Works out the graphics cursor less the new point, into <DRAW_DELTAS>.
;; Out: DRAW_DELTAS = the X difference, DRAW_DELTAS+2 = the Y difference
;; Uses: A, X, Y
CURSOR_DELTAS:
    ldy #<DRAW_DELTAS
    ldx #<NEW_POINT

;; Works out the difference between two points: the point at X + 4 less the point at X.
;; In: X = the first point's offset, Y = where the difference goes
;; Out: X, Y = each plus 2
;; Uses: A
;; Entry: SUBTRACT_COORDINATE = works out only the X co-ordinates' difference
POINT_DELTAS:
    jsr SUBTRACT_COORDINATE
    inx
    inx
    iny
    iny
SUBTRACT_COORDINATE:
    sec
    lda VDU_POINTS+4,x
    sbc VDU_POINTS,x
    sta VDU_POINTS,y
    lda VDU_POINTS+5,x
    sbc VDU_POINTS+1,x
    sta VDU_POINTS+1,y
    rts

;; Sets up <DRAW_LINE>'s counts: the points to draw, the error term and the line's lengths along its two axes.
;; In: VDU_TEMP+4 = the major axis, 0 for X or 2 for Y, DRAW_DELTAS, DRAW_POINT, DRAW_END
;; Out: VDU_TEMP+2/VDU_TEMP+3 = minus the major axis distance from DRAW_POINT to DRAW_END,
;;   DRAW_MINOR/DRAW_MAJOR = the lengths, made positive, DRAW_ERROR = half DRAW_MAJOR,
;;   DRAW_DELTAS = the minor difference, then the major one
;; Uses: A, X, Y, VDU_TEMP
DRAW_LINE_SETUP:
    lda VDU_TEMP+4
    bne DRAW_LINE_SETUP_ORDERED
    ldx #<DRAW_DELTAS               ; X major: put the minor axis first
    ldy #<(DRAW_DELTAS+2)
    jsr SWAP_VDU_PAIR
DRAW_LINE_SETUP_ORDERED:
    ldx #<DRAW_DELTAS
    ldy #<DRAW_MINOR
    jsr COPY_POINT
    sec
    ldx VDU_TEMP+4
    lda DRAW_END
    sbc DRAW_POINT,x
    tay
    lda DRAW_END+1
    sbc DRAW_POINT+1,x
    bmi DRAW_LINE_SETUP_COUNT
    jsr NEGATE
DRAW_LINE_SETUP_COUNT:
    sta VDU_TEMP+3
    sty VDU_TEMP+2
    ldx #<DRAW_ERROR

;; Makes the two co-ordinates after the one at X positive, and sets the one at X to half the second of them: for a
;; line's or an edge's error term, width and height.
;; In: X = the offset of the error term
;; Out: X = the offset less 2, A/Y = the first co-ordinate, high and low bytes
;; Uses: none
;; Entry: ABSOLUTE_COORDINATE = only makes the co-ordinate at X + 4 positive
ABSOLUTE_DELTAS:
    jsr ABSOLUTE_COORDINATE
    lsr a
    sta VDU_POINTS+1,x
    tya
    ror a
    sta VDU_POINTS,x
    dex
    dex
ABSOLUTE_COORDINATE:
    ldy VDU_POINTS+4,x
    lda VDU_POINTS+5,x
    bpl ABSOLUTE_COORDINATE_DONE
    jsr NEGATE
    sta VDU_POINTS+5,x
    pha
    tya
    sta VDU_POINTS+4,x
    pla
ABSOLUTE_COORDINATE_DONE:
    rts

;; Copies two points, eight bytes, in page three.
;; In: X = the offset to copy from, Y = the offset to copy to
;; Out: X, Y = each plus the bytes copied, VDU_TEMP = 0
;; Uses: A
;; Entry:
;;   COPY_TO_DRAW_END = copies a co-ordinate, two bytes, to DRAW_END
;;   COPY_COORDINATE = copies a co-ordinate, two bytes
;;   COPY_CURSOR_TO_WORK = copies the graphics cursor to GRAPHICS_WORK
;;   COPY_CURSOR = copies the graphics cursor to the point at Y
;;   COPY_POINT = copies a point, four bytes
;;   COPY_BYTES = copies the number of bytes in A
COPY_POINTS:
    lda #$08
    bne COPY_BYTES                  ; always
COPY_TO_DRAW_END:
    ldy #<DRAW_END
COPY_COORDINATE:
    lda #$02
    bne COPY_BYTES                  ; always
COPY_CURSOR_TO_WORK:
    ldy #<GRAPHICS_WORK
COPY_CURSOR:
    ldx #<GRAPHICS_CURSOR_INTERNAL
COPY_POINT:
    lda #$04
COPY_BYTES:
    sta VDU_TEMP
COPY_BYTES_LOOP:
    lda VDU_POINTS,x
    sta VDU_POINTS,y
    inx
    iny
    dec VDU_TEMP
    bne COPY_BYTES_LOOP
    rts

;; Negates a 16-bit number.
;; In: A/Y = the number, high and low bytes
;; Out: A/Y = minus the number
;; Uses: none
NEGATE:
    pha
    tya
    eor #$FF
    tay
    pla
    eor #$FF
    iny
    bne NEGATE_DONE
    clc
    adc #$01
NEGATE_DONE:
    rts

; ---------------------------------------------------------------------------------------------------------------------
; Horizontal line fills, PLOT 72-79 and 88-95
; ---------------------------------------------------------------------------------------------------------------------

;; Finds the new point's pixel and how its screen byte differs from the graphics background colour, for the fills.
;;
;; When the point is outside the graphics window it does not return: it drops its caller's return address and ends
;; the PLOT through <FILL_NOTHING>.
;; Out: VDU_TEMP = the byte EORed with <GRAPHICS_BACKGROUND>, with 1 bits where a pixel is not in that colour,
;;   GRAPHICS_CELL, GRAPHICS_MASK, GRAPHICS_LINE, Y = GRAPHICS_LINE
;; Uses: A, X
FILL_FIND_POINT:
    jsr FIND_NEW_POINT
    bne FILL_OUTSIDE
    lda (GRAPHICS_CELL),y
    eor GRAPHICS_BACKGROUND
    sta VDU_TEMP
    rts

FILL_OUTSIDE:
    pla
    pla

;; Ends a fill that fills nothing: the cursor goes to the new point, and the old cursor to the point one row above it.
;; Uses: A, X, Y, VDU_TEMP
FILL_NOTHING:
    inc GRAPHICS_CURSOR_INTERNAL+2
    jmp FILL_FINISH

;; PLOT 72-79: fills a horizontal line left and right from the new point to the nearest pixels that are not in the
;; graphics background colour, or to the window's edges.
;;
;; It scans left from the point a pixel at a time, a byte at a time where the whole byte is background, plotting as
;; it goes; then it plots from the point to the right, through <FILL_RIGHT>. The old cursor ends at the left end of
;; the line, and the cursor at the right end. PLOT 72 and 76 plot with masks that change nothing, so only the cursors
;; move. A point that is not in the background colour fills nothing.
;; In: NEW_POINT, GRAPHICS_CURSOR_INTERNAL = the new point, VDU_TEMP+2 = 0
;; Uses: A, X, Y, VDU_TEMP..VDU_TEMP+5, GRAPHICS_CELL, GRAPHICS_MASK, GRAPHICS_LINE
;; See: <READ_GRAPHICS_CURSORS>
FILL_LEFT_RIGHT:
    jsr FILL_FIND_POINT
    and GRAPHICS_MASK
    bne FILL_NOTHING
    ldx #<GRAPHICS_WINDOW
    jsr FILL_DISTANCE
    beq FILL_LEFT_END               ; at the window's left edge
    ldy GRAPHICS_LINE
    asl GRAPHICS_MASK               ; the pixel to the left
    bcs FILL_LEFT_BYTE
    jsr FILL_LEFT_PIXELS
    bcc FILL_LEFT_END
FILL_LEFT_BYTE:
    jsr GRAPHICS_CELL_LEFT
    lda (GRAPHICS_CELL),y
    eor GRAPHICS_BACKGROUND
    sta VDU_TEMP
    bne FILL_LEFT_LAST_BYTE
    sec                             ; all background: count the whole byte
    txa
    adc PIXELS_PER_BYTE
    bcc FILL_LEFT_WHOLE_BYTE
    inc VDU_TEMP+1
    bpl FILL_LEFT_LAST_BYTE         ; it reaches the window's edge
FILL_LEFT_WHOLE_BYTE:
    tax
    jsr PLOT_BYTE
    sec
    bcs FILL_LEFT_BYTE              ; always
FILL_LEFT_LAST_BYTE:
    jsr FILL_LEFT_PIXELS
FILL_LEFT_END:
    ldy #<GRAPHICS_WINDOW
    jsr FILL_END_POINT
    ldy #<NEW_POINT                 ; the left end to the cursor, the point back to NEW_POINT
    ldx #<GRAPHICS_CURSOR_INTERNAL
    jsr SWAP_VDU_POINTS

;; PLOT 88-95, and the second half of PLOT 72-79: fills a horizontal line right from the new point, to the nearest
;; pixel in the graphics background colour (or, for 72-79, to the nearest pixel that is not), or to the window's edge.
;;
;; It scans a pixel at a time, or for 72-79 a byte at a time where the whole byte is background. The cursor ends at
;; the right end of the line. PLOT 89 and 93 plot with masks that change nothing, so only the cursors move.
;; In: NEW_POINT = the new point, VDU_TEMP+2 = 2 for PLOT 88-95, 0 for 72-79
;; Uses: A, X, Y, VDU_TEMP..VDU_TEMP+5, GRAPHICS_CELL, GRAPHICS_MASK, GRAPHICS_LINE
;; See: <READ_GRAPHICS_CURSORS>
FILL_RIGHT:
    jsr FILL_FIND_POINT
    ldx #<WINDOW_TOP_RIGHT
    jsr FILL_DISTANCE
    txa                             ; one more, for the point itself
    bne FILL_RIGHT_COUNT
    dec VDU_TEMP+1
FILL_RIGHT_COUNT:
    dex
FILL_RIGHT_PIXEL_LOOP:
    jsr FILL_RIGHT_PIXELS
    bcc FILL_RIGHT_END
FILL_RIGHT_BYTE:
    jsr GRAPHICS_CELL_RIGHT
    lda (GRAPHICS_CELL),y
    eor GRAPHICS_BACKGROUND
    sta VDU_TEMP
    lda VDU_TEMP+2
    bne FILL_RIGHT_PIXEL_LOOP       ; PLOT 88-95 goes a pixel at a time
    lda VDU_TEMP
    bne FILL_RIGHT_LAST_BYTE
    sec                             ; all background: count the whole byte
    txa
    adc PIXELS_PER_BYTE
    bcc FILL_RIGHT_WHOLE_BYTE
    inc VDU_TEMP+1
    bpl FILL_RIGHT_LAST_BYTE        ; it reaches the window's edge
FILL_RIGHT_WHOLE_BYTE:
    tax
    jsr PLOT_BYTE
    sec
    bcs FILL_RIGHT_BYTE             ; always
FILL_RIGHT_LAST_BYTE:
    jsr FILL_RIGHT_PIXELS
FILL_RIGHT_END:
    ldy #<WINDOW_TOP_RIGHT
    jsr FILL_END_POINT

;; Ends a PLOT that fills: moves the old cursor to the cursor, the cursor to NEW_POINT, and works out the external
;; cursor.
;; Uses: A, X, Y, VDU_TEMP
FILL_FINISH:
    jsr MOVE_GRAPHICS_CURSOR
    jmp UPDATE_EXTERNAL_CURSOR

;; Plots pixels rightwards within a screen byte from the one in GRAPHICS_MASK, while they can be filled, counting them.
;;
;; A pixel can be filled when it is in the background colour, or for PLOT 88-95 when it is not: the code flips the
;; zero flag on the stack with VDU_TEMP+2, since bit 1 of the processor status is the zero flag.
;; In: GRAPHICS_MASK = the first pixel, VDU_TEMP = the byte's pixels not in the background colour,
;;   VDU_TEMP+2 = 2 for PLOT 88-95, 0 for 72-79, X/VDU_TEMP+1 = minus the pixels left before the window's edge
;; Out: carry = set when every pixel to the byte's right end could be filled, clear when the fill stopped,
;;   X/VDU_TEMP+1 = the count, GRAPHICS_MASK = the pixels plotted, Y = GRAPHICS_LINE
;; Uses: A
FILL_RIGHT_PIXELS:
    lda GRAPHICS_MASK
    pha
    clc
    bcc FILL_RIGHT_PIXELS_TEST      ; always
FILL_RIGHT_PIXELS_NEXT:
    pla
    inx
    bne FILL_RIGHT_PIXELS_MOVE
    inc VDU_TEMP+1
    bpl FILL_PLOT_PIXELS            ; the window's edge
FILL_RIGHT_PIXELS_MOVE:
    lsr GRAPHICS_MASK
    bcs FILL_PLOT_PIXELS            ; past the byte's right end
    ora GRAPHICS_MASK
    pha
FILL_RIGHT_PIXELS_TEST:
    lda GRAPHICS_MASK
    bit VDU_TEMP                    ; zero = the pixel is in the background colour
    php
    pla
    eor VDU_TEMP+2                  ; for PLOT 88-95, zero = the pixel is not
    pha
    plp
    beq FILL_RIGHT_PIXELS_NEXT
    pla
    eor GRAPHICS_MASK               ; leave out the pixel that stopped the fill

;; Plots the pixels in A, the end of both fills' pixel scans.
;; In: A = the pixels
;; Out: GRAPHICS_MASK = A, Y = GRAPHICS_LINE
;; Uses: A, VDU_TEMP
;; Keeps: X
FILL_PLOT_PIXELS:
    sta GRAPHICS_MASK
    jmp PLOT_PIXEL

;; Plots pixels leftwards within a screen byte from the one in GRAPHICS_MASK, while they are in the background colour,
;; counting them.
;; In: GRAPHICS_MASK = the first pixel, VDU_TEMP = the byte's pixels not in the background colour,
;;   X/VDU_TEMP+1 = minus the pixels left before the window's edge
;; Out: carry = set when every pixel to the byte's left end was background, clear when the fill stopped,
;;   X/VDU_TEMP+1 = the count, GRAPHICS_MASK = the pixels plotted, Y = GRAPHICS_LINE
;; Uses: A
FILL_LEFT_PIXELS:
    lda #$00
    clc
    bcc FILL_LEFT_PIXELS_TEST       ; always
FILL_LEFT_PIXELS_NEXT:
    inx
    bne FILL_LEFT_PIXELS_MOVE
    inc VDU_TEMP+1
    bpl FILL_PLOT_PIXELS            ; the window's edge
FILL_LEFT_PIXELS_MOVE:
    asl a
    bcs FILL_LEFT_PIXELS_FULL       ; past the byte's left end
FILL_LEFT_PIXELS_TEST:
    ora GRAPHICS_MASK
    bit VDU_TEMP
    beq FILL_LEFT_PIXELS_NEXT
    eor GRAPHICS_MASK               ; leave out the pixel that stopped the fill
    lsr a
    bcc FILL_PLOT_PIXELS            ; always
FILL_LEFT_PIXELS_FULL:
    ror a
    sec
    bcs FILL_PLOT_PIXELS            ; always

;; Works out the distance from the new point to one of the graphics window's edges, as a negative count for the fills.
;; In: X = the offset of the window's corner: GRAPHICS_WINDOW for the left edge, WINDOW_TOP_RIGHT for the right
;; Out: X/VDU_TEMP+1 = minus the distance, low and high bytes, zero = set when the point is on the edge
;; Uses: A, Y
FILL_DISTANCE:
    lda VDU_POINTS,x
    sec
    sbc NEW_POINT
    tay
    lda VDU_POINTS+1,x
    sbc NEW_POINT+1
    bmi FILL_DISTANCE_NEGATIVE
    jsr NEGATE
FILL_DISTANCE_NEGATIVE:
    sta VDU_TEMP+1
    tya
    tax
    ora VDU_TEMP+1
    rts

;; Puts where a fill stopped into the new point's X co-ordinate: the window's edge, moved back by the count of pixels
;; that <FILL_DISTANCE> started and the scan counted up.
;; In: Y = the offset of the window's corner: GRAPHICS_WINDOW for the left edge, WINDOW_TOP_RIGHT for the right,
;;   X/VDU_TEMP+1 = the count, taken as zero above when VDU_TEMP+1 is not negative
;; Out: NEW_POINT = the X co-ordinate of the fill's last pixel
;; Uses: A, X, Y, VDU_TEMP
FILL_END_POINT:
    sty VDU_TEMP
    txa
    tay
    lda VDU_TEMP+1
    bmi FILL_END_POINT_COUNT
    lda #$00
FILL_END_POINT_COUNT:
    ldx VDU_TEMP
    bne FILL_END_POINT_ADD
    jsr NEGATE                      ; the left edge: add minus the count
FILL_END_POINT_ADD:
    pha
    clc
    tya
    adc VDU_POINTS,x
    sta NEW_POINT
    pla
    adc VDU_POINTS+1,x
    sta NEW_POINT+1
    rts

;; OSWORD 13: reads the last two graphics cursor positions, in external co-ordinates: the old cursor's four bytes at
;; XY+0, then the cursor's at XY+4.
;; In: OS_X/OS_Y = the parameter block
;; Uses: A, X, Y, VDU_TEMP
;; Entry: READ_GRAPHICS_CURSORS_ONE = A = the offset of the last byte to write: swaps the cursors and writes
;;   the one now in GRAPHICS_CURSOR_INTERNAL
READ_GRAPHICS_CURSORS:
    lda #$03
    jsr READ_GRAPHICS_CURSORS_ONE
    lda #$07
READ_GRAPHICS_CURSORS_ONE:
    pha
    jsr SWAP_GRAPHICS_CURSORS
    jsr UPDATE_EXTERNAL_CURSOR
    ldx #$03
    pla
    tay
READ_GRAPHICS_CURSORS_LOOP:
    lda GRAPHICS_CURSOR,x
    sta (OS_X),y
    dey
    dex
    bpl READ_GRAPHICS_CURSORS_LOOP
    rts

; ---------------------------------------------------------------------------------------------------------------------
; Triangles, PLOT 80-87
; ---------------------------------------------------------------------------------------------------------------------

;; PLOT 80-87: fills a triangle between the new point and the last two positions of the graphics cursor.
;;
;; It sorts the corners by height, so that NEW_POINT is the lowest, OLD_GRAPHICS_CURSOR the middle one and
;; GRAPHICS_CURSOR_INTERNAL the highest. <LONG_EDGE> runs from the lowest to the highest. The triangle is filled a row
;; at a time between it and the short edge, first the lower part from the lowest corner up to the middle one, then the
;; upper part from there to the highest, whose top row it includes. Then the points are put back and the cursor moves
;; to the new point.
;; In: NEW_POINT, GRAPHICS_CURSOR_INTERNAL, OLD_GRAPHICS_CURSOR, GRAPHICS_OR_MASK, GRAPHICS_EOR_MASK
;; Uses: A, X, Y, VDU_TEMP..VDU_TEMP+5, VDU_QUEUE..VDU_QUEUE+1, GRAPHICS_WORK..GRAPHICS_WORK+29
;; See: <FILL_TRIANGLE_PART>, <STEP_EDGE>
FILL_TRIANGLE:
    ldx #<NEW_POINT
    ldy #<TRIANGLE_SAVE
    jsr COPY_POINTS
    jsr SORT_NEW_AND_OLD_POINTS
    ldx #<OLD_GRAPHICS_CURSOR
    ldy #<GRAPHICS_CURSOR_INTERNAL
    jsr SORT_POINTS_BY_Y
    jsr SORT_NEW_AND_OLD_POINTS
    ldx #<NEW_POINT
    ldy #<(LONG_EDGE+EDGE_WIDTH)
    jsr POINT_DELTAS
    lda LONG_EDGE+EDGE_WIDTH+1
    sta LONG_EDGE+EDGE_DIRECTION
    ldx #<LONG_EDGE
    jsr ABSOLUTE_DELTAS
    ldy #<(LONG_EDGE+EDGE_X)
    jsr COPY_NEW_POINT
    jsr SWAP_GRAPHICS_CURSORS                       ; the cursor is the middle corner
    clc
    jsr FILL_TRIANGLE_PART
    jsr SWAP_GRAPHICS_CURSORS                       ; the cursor is the highest corner again
    ldx #<NEW_POINT
    jsr SWAP_WITH_OLD_GRAPHICS_CURSOR                       ; the new point is the middle corner
    sec
    jsr FILL_TRIANGLE_PART
    ldx #<TRIANGLE_SAVE
    ldy #<NEW_POINT
    jsr COPY_POINTS
    jmp MOVE_GRAPHICS_CURSOR

;; Sorts the new point and the old cursor by height, as <SORT_POINTS_BY_Y> does.
;; Uses: A, X, Y, VDU_TEMP
SORT_NEW_AND_OLD_POINTS:
    ldx #<NEW_POINT
    ldy #<OLD_GRAPHICS_CURSOR

;; Sorts two points by height, exchanging them unless the point at X is lower than the one at Y.
;; In: X, Y = the points' offsets
;; Uses: A, X, Y, VDU_TEMP
SORT_POINTS_BY_Y:
    lda VDU_POINTS+2,x
    cmp VDU_POINTS+2,y
    lda VDU_POINTS+3,x
    sbc VDU_POINTS+3,y
    bmi READ_TEXT_CURSOR_DONE       ; in order: return
    jmp SWAP_VDU_POINTS

;; OSBYTE &86: reads the text cursor's position (POS and VPOS), measured from the text window's top left corner.
;; Out: X = the column, Y = the row
;; Uses: A
READ_TEXT_CURSOR:
    lda TEXT_CURSOR_X
    sec
    sbc TEXT_WINDOW_LEFT
    tax
    lda TEXT_CURSOR_Y
    sec
    sbc TEXT_WINDOW_TOP
    tay
READ_TEXT_CURSOR_DONE:
    rts

;; Fills one part of a triangle a row at a time, from NEW_POINT's row up to the graphics cursor's, between the long
;; edge and a short edge from NEW_POINT to the cursor.
;; In: NEW_POINT, GRAPHICS_CURSOR_INTERNAL = the short edge's ends, LONG_EDGE, carry = set to fill the cursor's row too
;; Uses: A, X, Y, VDU_TEMP..VDU_TEMP+5, TRIANGLE_ROWS
FILL_TRIANGLE_PART:
    php
    ldx #<NEW_POINT
    ldy #<(SHORT_EDGE+EDGE_WIDTH)
    jsr POINT_DELTAS
    lda SHORT_EDGE+EDGE_WIDTH+1
    sta SHORT_EDGE+EDGE_DIRECTION
    ldx #<SHORT_EDGE
    jsr ABSOLUTE_DELTAS
    ldy #<(SHORT_EDGE+EDGE_X)
    jsr COPY_NEW_POINT
    sec
    lda NEW_POINT+2
    sbc GRAPHICS_CURSOR_INTERNAL+2
    sta TRIANGLE_ROWS
    lda NEW_POINT+3
    sbc GRAPHICS_CURSOR_INTERNAL+3
    sta TRIANGLE_ROWS+1
    ora TRIANGLE_ROWS
    beq FILL_TRIANGLE_PART_LAST
FILL_TRIANGLE_PART_LOOP:
    jsr FILL_TRIANGLE_ROW
    ldx #<SHORT_EDGE
    jsr STEP_EDGE
    ldx #<LONG_EDGE
    jsr STEP_EDGE
    inc TRIANGLE_ROWS
    bne FILL_TRIANGLE_PART_LOOP
    inc TRIANGLE_ROWS+1
    bne FILL_TRIANGLE_PART_LOOP
FILL_TRIANGLE_PART_LAST:
    plp
    bcc READ_TEXT_CURSOR_DONE       ; return

;; Fills one row of a triangle, between the points its two edges have reached.
;;
;; It falls through into <FILL_HORIZONTAL_LINE>.
;; Uses: A, X, Y, VDU_TEMP..VDU_TEMP+5
FILL_TRIANGLE_ROW:
    ldx #<(SHORT_EDGE+EDGE_X)
    ldy #<(LONG_EDGE+EDGE_X)

;; Fills a horizontal line between two points on the same row, clipped to the graphics window, with the graphics
;; colour masks, as the triangle fill and CLG do.
;;
;; It plots the right end's byte a pixel at a time, then whole bytes leftwards, then the left end's pixels, moving Y
;; down by eight a byte and GRAPHICS_CELL down a page when Y wraps.
;; In: X, Y = the ends' offsets, either way round
;; Uses: A, X, Y, VDU_TEMP..VDU_TEMP+5, GRAPHICS_CELL, GRAPHICS_MASK, GRAPHICS_LINE
FILL_HORIZONTAL_LINE:
    stx VDU_TEMP+4                  ; the left end, unless the compare finds otherwise
    lda VDU_POINTS,x
    cmp VDU_POINTS,y
    lda VDU_POINTS+1,x
    sbc VDU_POINTS+1,y
    bmi FILL_HORIZONTAL_LINE_ORDERED
    tya
    ldy VDU_TEMP+4
    tax
    stx VDU_TEMP+4
FILL_HORIZONTAL_LINE_ORDERED:
    sty VDU_TEMP+5                  ; the right end
    lda VDU_POINTS,y                ; kept, to put back after clipping
    pha
    lda VDU_POINTS+1,y
    pha
    ldx VDU_TEMP+5
    jsr POINT_WINDOW_CODE
    beq FILL_HORIZONTAL_LINE_RIGHT
    cmp #OUTSIDE_RIGHT
    bne FILL_HORIZONTAL_LINE_DONE
    ldx #<WINDOW_TOP_RIGHT          ; only right of the window: end at its right column
    ldy VDU_TEMP+5
    jsr COPY_COORDINATE
    ldx VDU_TEMP+5
FILL_HORIZONTAL_LINE_RIGHT:
    jsr FIND_POINT_ADDRESS
    ldx VDU_TEMP+4
    jsr POINT_WINDOW_CODE
    lsr a                           ; carry = OUTSIDE_LEFT
    bne FILL_HORIZONTAL_LINE_DONE
    bcc FILL_HORIZONTAL_LINE_LEFT
    ldx #<GRAPHICS_WINDOW           ; left of the window: start at its left column
FILL_HORIZONTAL_LINE_LEFT:
    ldy VDU_TEMP+5
    sec
    lda VDU_POINTS,y
    sbc VDU_POINTS,x
    sta VDU_TEMP+2                  ; the pixels left of the right end's
    lda VDU_POINTS+1,y
    sbc VDU_POINTS+1,x
    sta VDU_TEMP+3
    lda #$00
FILL_HORIZONTAL_LINE_RIGHT_BYTE:
    asl a                           ; add the pixel to the left
    ora GRAPHICS_MASK
    ldy VDU_TEMP+2
    bne FILL_HORIZONTAL_LINE_COUNT
    dec VDU_TEMP+3
    bpl FILL_HORIZONTAL_LINE_COUNT
    sta GRAPHICS_MASK               ; the line ends in this byte
    jsr PLOT_PIXEL
FILL_HORIZONTAL_LINE_DONE:
    ldx VDU_TEMP+5
    pla
    sta VDU_POINTS+1,x
    pla
    sta VDU_POINTS,x
    rts

FILL_HORIZONTAL_LINE_COUNT:
    dec VDU_TEMP+2
    tax
    bpl FILL_HORIZONTAL_LINE_RIGHT_BYTE ; until the byte's leftmost pixel is in
    sta GRAPHICS_MASK
    jsr PLOT_PIXEL
    ldx VDU_TEMP+2
    inx
    bne FILL_HORIZONTAL_LINE_BYTES
    inc VDU_TEMP+3
FILL_HORIZONTAL_LINE_BYTES:
    txa                             ; the pixels left, divided by the pixels in a byte
    pha
    lsr VDU_TEMP+3
    ror a
    ldy PIXELS_PER_BYTE
    cpy #$03
    beq FILL_HORIZONTAL_LINE_DIVIDE
    bcc FILL_HORIZONTAL_LINE_WHOLE  ; sixteen colours: two pixels
    lsr VDU_TEMP+3                  ; two colours: eight pixels
    ror a
FILL_HORIZONTAL_LINE_DIVIDE:
    lsr VDU_TEMP+3
    lsr a
FILL_HORIZONTAL_LINE_WHOLE:
    ldy GRAPHICS_LINE
    tax
    beq FILL_HORIZONTAL_LINE_LAST
FILL_HORIZONTAL_LINE_LOOP:
    tya
    sec
    sbc #$08                        ; the byte to the left
    tay
    bcs FILL_HORIZONTAL_LINE_PLOT
    dec GRAPHICS_CELL+1
FILL_HORIZONTAL_LINE_PLOT:
    jsr PLOT_BYTE
    dex
    bne FILL_HORIZONTAL_LINE_LOOP
FILL_HORIZONTAL_LINE_LAST:
    pla
    and PIXELS_PER_BYTE             ; the pixels left over, at the right of the last byte
    beq FILL_HORIZONTAL_LINE_DONE
    tax
    lda #$00
FILL_HORIZONTAL_LINE_MASK:
    asl a
    ora RIGHT_COLOUR_MASK
    dex
    bne FILL_HORIZONTAL_LINE_MASK
    sta GRAPHICS_MASK
    tya
    sec
    sbc #$08
    tay
    bcs FILL_HORIZONTAL_LINE_PIXELS
    dec GRAPHICS_CELL+1
FILL_HORIZONTAL_LINE_PIXELS:
    jsr PLOT_PIXEL_AT_Y
    jmp FILL_HORIZONTAL_LINE_DONE

;; Moves a triangle's edge up a row: the row goes up by one, and the X co-ordinate moves towards the edge's top end
;; as far as the error term says (Bresenham's method).
;; In: X = the offset of the edge record, <LONG_EDGE> or <SHORT_EDGE>
;; Uses: A
;; Keeps: X, Y
STEP_EDGE:
    inc VDU_POINTS+EDGE_Y,x
    bne STEP_EDGE_ERROR
    inc VDU_POINTS+EDGE_Y+1,x
STEP_EDGE_ERROR:
    sec
    lda VDU_POINTS+EDGE_ERROR,x
    sbc VDU_POINTS+EDGE_WIDTH,x
    sta VDU_POINTS+EDGE_ERROR,x
    lda VDU_POINTS+EDGE_ERROR+1,x
    sbc VDU_POINTS+EDGE_WIDTH+1,x
    sta VDU_POINTS+EDGE_ERROR+1,x
    bpl STEP_EDGE_DONE
STEP_EDGE_MOVE:
    lda VDU_POINTS+EDGE_DIRECTION,x
    bmi STEP_EDGE_LEFT
    inc VDU_POINTS+EDGE_X,x
    bne STEP_EDGE_HEIGHT
    inc VDU_POINTS+EDGE_X+1,x
    jmp STEP_EDGE_HEIGHT

STEP_EDGE_LEFT:
    lda VDU_POINTS+EDGE_X,x
    bne STEP_EDGE_LEFT_LOW
    dec VDU_POINTS+EDGE_X+1,x
STEP_EDGE_LEFT_LOW:
    dec VDU_POINTS+EDGE_X,x
STEP_EDGE_HEIGHT:
    clc
    lda VDU_POINTS+EDGE_ERROR,x
    adc VDU_POINTS+EDGE_HEIGHT,x
    sta VDU_POINTS+EDGE_ERROR,x
    lda VDU_POINTS+EDGE_ERROR+1,x
    adc VDU_POINTS+EDGE_HEIGHT+1,x
    sta VDU_POINTS+EDGE_ERROR+1,x
    bmi STEP_EDGE_MOVE
STEP_EDGE_DONE:
    rts

; ---------------------------------------------------------------------------------------------------------------------
; Reading the screen
; ---------------------------------------------------------------------------------------------------------------------

;; OSBYTE &87: reads the character at the text cursor, and the screen mode.
;;
;; In teletext it reads the screen byte and undoes the three translations <TELETEXT_TRANSLATION> makes. In the other
;; modes it reads the character cell as a pattern of foreground and background pixels and looks for the character
;; from 32 to 255 whose shape matches, leaving out 127.
;; Out: X = the character, or 0 when none matches, zero = set when it is 0, Y = the screen mode
;; Uses: A, VDU_TEMP..VDU_TEMP+5, GRAPHICS_WORK..GRAPHICS_WORK+7
READ_CHARACTER:
    ldy COLOUR_COUNT
    bne READ_CHARACTER_GRAPHICS
    lda (TEXT_CELL),y               ; teletext
    ldy #$02
READ_CHARACTER_TRANSLATE:
    cmp TELETEXT_CODES,y                     ; the codes TELETEXT_TRANSLATION writes
    bne READ_CHARACTER_TRANSLATE_NEXT
    lda TELETEXT_TRANSLATION,y      ; the character they stand for
    dey                             ; skip the next pair, which would translate it back
READ_CHARACTER_TRANSLATE_NEXT:
    dey
    bpl READ_CHARACTER_TRANSLATE
READ_CHARACTER_DONE:
    ldy SCREEN_MODE
    tax
    rts

READ_CHARACTER_GRAPHICS:
    jsr READ_CELL_PATTERN
    ldx #' '
READ_CHARACTER_ZONE:
    txa
    pha
    jsr FIND_CHARACTER_DEFINITION
    pla
    tax
READ_CHARACTER_COMPARE:
    ldy #$07
READ_CHARACTER_COMPARE_LOOP:
    lda GRAPHICS_WORK,y
    cmp (VDU_TEMP+4),y
    bne READ_CHARACTER_NEXT
    dey
    bpl READ_CHARACTER_COMPARE_LOOP
    txa
    cpx #$7F                        ; DELETE is never the answer
    bne READ_CHARACTER_DONE
READ_CHARACTER_NEXT:
    inx
    lda VDU_TEMP+4
    clc
    adc #$08
    sta VDU_TEMP+4
    bne READ_CHARACTER_COMPARE      ; the same page
    txa
    bne READ_CHARACTER_ZONE         ; a new page, which may be in another zone's place
    beq READ_CHARACTER_DONE         ; always: none matched, A = 0

;; Reads the character cell at the text cursor as a character shape: eight bytes, bit 7 the leftmost pixel, with 1 for
;; each pixel not in the text background colour.
;; In: TEXT_CELL = the cell's address
;; Out: GRAPHICS_WORK..GRAPHICS_WORK+7 = the pattern, top row first
;; Uses: A, Y, VDU_TEMP..VDU_TEMP+2
;; Keeps: X
READ_CELL_PATTERN:
    ldy #$07
READ_CELL_PATTERN_ROW:
    sty VDU_TEMP
    lda #$01                        ; a marker, shifted out when eight pixels are in
    sta VDU_TEMP+1
READ_CELL_PATTERN_BYTE:
    lda LEFT_COLOUR_MASK
    sta VDU_TEMP+2
    lda (TEXT_CELL),y
    eor TEXT_BACKGROUND
    clc
READ_CELL_PATTERN_PIXEL:
    bit VDU_TEMP+2
    beq READ_CELL_PATTERN_BIT
    sec
READ_CELL_PATTERN_BIT:
    rol VDU_TEMP+1
    bcs READ_CELL_PATTERN_STORE
    lsr VDU_TEMP+2                  ; the next pixel to the right
    bcc READ_CELL_PATTERN_PIXEL
    tya
    adc #$07                        ; plus the carry: the next byte to the right
    tay
    bcc READ_CELL_PATTERN_BYTE
READ_CELL_PATTERN_STORE:
    ldy VDU_TEMP
    lda VDU_TEMP+1
    sta GRAPHICS_WORK,y
    dey
    bpl READ_CELL_PATTERN_ROW
    rts

;; Reads the logical colour of a point, for OSWORD 9 and BASIC's POINT.
;;
;; It collects the bits of the point's screen byte that its pixel mask selects, leftmost first.
;; In: A = the offset of the point, in absolute external co-ordinates, which it converts in place
;; Out: A = the logical colour, or &FF when the point is outside the graphics window, GRAPHICS_CURSOR = the point
;; Uses: X, Y, VDU_TEMP, GRAPHICS_CELL, GRAPHICS_MASK, GRAPHICS_LINE
;; Entry: READ_POINT_DONE = an RTS
READ_POINT:
    pha
    tax
    jsr CONVERT_ABSOLUTE_POINT
    pla
    tax
    jsr FIND_POINT
    bne READ_POINT_OUTSIDE
    lda (GRAPHICS_CELL),y
READ_POINT_BIT:
    asl a
    rol VDU_TEMP
    asl GRAPHICS_MASK
    php
    bcs READ_POINT_KEEP
    lsr VDU_TEMP                    ; not the pixel's bit: take it back out
READ_POINT_KEEP:
    plp
    bne READ_POINT_BIT
    lda VDU_TEMP
    and COLOUR_COUNT
    rts

READ_POINT_OUTSIDE:
    lda #$FF
READ_POINT_DONE:
    rts

;; Finds the new point's screen byte and pixel, as <FIND_POINT> does.
;; Out: A = the window code, zero = set when the point is inside, and then GRAPHICS_CELL, GRAPHICS_MASK,
;;   GRAPHICS_LINE, Y = GRAPHICS_LINE
;; Uses: VDU_TEMP
FIND_NEW_POINT:
    ldx #<NEW_POINT

;; Finds a point's screen byte and pixel, if it is inside the graphics window.
;; In: X = the point's offset
;; Out: A = the window code, zero = set when the point is inside, and then GRAPHICS_CELL, GRAPHICS_MASK,
;;   GRAPHICS_LINE, Y = GRAPHICS_LINE
;; Uses: Y, VDU_TEMP
;; Keeps: X
FIND_POINT:
    jsr POINT_WINDOW_CODE
    bne READ_POINT_DONE

;; Works out a point's screen byte and pixel.
;;
;; The row is 255 less Y: its low three bits are the line in the character cell, and the rest index the row table at
;; <ROW_TABLE>, halved for 320-byte rows, to which the screen's start is added. X picks the pixel's mask from
;; <SIXTEEN_COLOUR_MASKS>, <FOUR_COLOUR_MASKS> or <TWO_COLOUR_MASKS>, and its byte, eight bytes to a cell. An
;; address past &7FFF wraps round to the start of screen memory.
;; In: X = the point's offset
;; Out: GRAPHICS_CELL = the address of the top line of its character cell, GRAPHICS_LINE, Y = the line in the cell,
;;   GRAPHICS_MASK = the pixel, A = 0, zero = set
;; Uses: VDU_TEMP
;; Keeps: X
;; Entry: FIND_POINT_ADDRESS_DONE = returns 0 in A, with zero set
FIND_POINT_ADDRESS:
    lda VDU_POINTS+2,x
    eor #$FF                        ; the row from the top
    tay
    and #$07
    sta GRAPHICS_LINE
    tya
    lsr a
    lsr a
    lsr a
    asl a
    tay
    lda (ROW_TABLE),y               ; the high byte first
    sta VDU_TEMP
    iny
    lda (ROW_TABLE),y
    ldy MEMORY_MAP_TYPE
    beq FIND_POINT_ADDRESS_ROW
    lsr VDU_TEMP                    ; 320-byte rows
    ror a
FIND_POINT_ADDRESS_ROW:
    adc SCREEN_START
    sta GRAPHICS_CELL
    lda VDU_TEMP
    adc SCREEN_START+1
    sta GRAPHICS_CELL+1
    lda VDU_POINTS+1,x
    sta VDU_TEMP
    lda VDU_POINTS,x
    pha
    and PIXELS_PER_BYTE
    adc PIXELS_PER_BYTE             ; the masks for N pixels to a byte start N-1 bytes after PIXEL_MASKS
    tay
    lda PIXEL_MASKS,y
    sta GRAPHICS_MASK
    pla
    ldy PIXELS_PER_BYTE
    cpy #$03
    beq FIND_POINT_ADDRESS_FOUR_COLOURS
    bcs FIND_POINT_ADDRESS_COLUMN   ; two colours: X AND &F8 is the byte's offset
    asl a                           ; sixteen colours: X times 4
    rol VDU_TEMP
FIND_POINT_ADDRESS_FOUR_COLOURS:
    asl a                           ; four colours: X times 2
    rol VDU_TEMP
FIND_POINT_ADDRESS_COLUMN:
    and #$F8
    clc
    adc GRAPHICS_CELL
    sta GRAPHICS_CELL
    lda VDU_TEMP
    adc GRAPHICS_CELL+1
    bpl FIND_POINT_ADDRESS_WRAPPED
    sec                             ; past &7FFF: wrap round to the start of the screen
    sbc SCREEN_SIZE
FIND_POINT_ADDRESS_WRAPPED:
    sta GRAPHICS_CELL+1
    ldy GRAPHICS_LINE
FIND_POINT_ADDRESS_DONE:
    lda #$00
    rts

; ---------------------------------------------------------------------------------------------------------------------
; Cursor editing
; ---------------------------------------------------------------------------------------------------------------------

;; Moves the cursor for a cursor key, &88-&8B, starting cursor editing if it has not started.
;;
;; Editing starts by making the cursor blink fast, copying the text cursor to the output cursor (<OUTPUT_CURSOR_X>),
;; showing it (<DRAW_OUTPUT_CURSOR>) and setting <VDU_STATUS> bit 1. Then the key less &80, VDU 8-11, goes to the VDU
;; driver with bit 6 cleared, so that it moves the text cursor. When the VDU driver is waiting for parameters, is
;; disabled (VDU 21) or writes text at the graphics cursor (VDU 5), the key does nothing.
;; In: A = the key
;; Out: A = the key, when it does nothing
;; Uses: A, X, Y
;; See: <COPY_CHARACTER>, <END_CURSOR_EDITING>
MOVE_EDITING_CURSOR:
    pha
    lda #%10100000                  ; VDU 21 (bit 7) and VDU 5 (bit 5)
    ldx VDU_QUEUE_COUNT
    bne MOVE_EDITING_CURSOR_IGNORE
    bit VDU_STATUS
    bne MOVE_EDITING_CURSOR_IGNORE
    bvs MOVE_EDITING_CURSOR_MOVE    ; already editing
    lda CURSOR_START
    and #%10011111                  ; the 6845's cursor blink bits
    ora #%01000000                  ; blink fast
    jsr SET_CURSOR_START
    ldx #<TEXT_CURSOR_X
    ldy #<OUTPUT_CURSOR_X
    jsr COPY_COORDINATE
    jsr DRAW_OUTPUT_CURSOR
    lda #%00000010
    jsr SET_VDU_STATUS
MOVE_EDITING_CURSOR_MOVE:
    lda #%10111111                  ; clear bit 6, cursor editing, for the move
    jsr CLEAR_VDU_STATUS
    pla
    and #$7F
    jsr VDU_DRIVER
    lda #%01000000                  ; and set it again
    jmp SET_VDU_STATUS

;; Reads the character under the cursor for the COPY key, and moves the cursor on past it.
;; Out: A = the character, or 0 when not editing, when writing text at the graphics cursor, or when the character is
;;   not recognized, zero = set when it is 0
;; Uses: X, Y, VDU_TEMP..VDU_TEMP+5, GRAPHICS_WORK..GRAPHICS_WORK+7
;; See: <READ_CHARACTER>, <MOVE_EDITING_CURSOR>
COPY_CHARACTER:
    lda #%00100000                  ; VDU 5
    bit VDU_STATUS
    bvc FIND_POINT_ADDRESS_DONE     ; not editing: A = 0
    bne FIND_POINT_ADDRESS_DONE
    jsr READ_CHARACTER
    beq MOVE_EDITING_CURSOR_DONE
    pha
    jsr VDU_FORWARD
MOVE_EDITING_CURSOR_IGNORE:
    pla
MOVE_EDITING_CURSOR_DONE:
    rts

;; Ends cursor editing, when RETURN is written while the cursors are apart: clears <VDU_STATUS> bits 6 and 1 and puts
;; the 6845's cursor back as <CURSOR_START> has it.
;; Out: A = &0D, carriage return
;; Uses: X, Y
END_CURSOR_EDITING:
    lda #%10111101
    jsr CLEAR_VDU_STATUS
    jsr SHOW_CURSOR
    lda #$0D
    rts

;; OSBYTE &84: reads the bottom of display memory (HIMEM) for the current screen mode.
;;
;; It falls through into <READ_MODE_HIMEM>.
;; Out: X/Y = the address, low and high bytes
;; Uses: A
READ_HIMEM:
    ldx SCREEN_MODE

;; OSBYTE &85: reads the bottom of display memory (HIMEM) for a screen mode.
;;
;; On a 16K machine the screen is in the top of 16K, so the address is ANDed with &3FFF, and modes 0-3, which do not
;; fit, give 0.
;; In: X = the mode
;; Out: X/Y = the address, low and high bytes
;; Uses: A
;; Entry: READ_MODE_HIMEM_DONE = an RTS
READ_MODE_HIMEM:
    txa
    and #$07
    tay
    ldx MODE_MAP_TYPE,y
    lda MAP_SCREEN_START,x
    ldx #$00
    bit AVAILABLE_RAM
    bmi READ_MODE_HIMEM_HIGH        ; 32K
    and #$3F
    cpy #$04
    bcs READ_MODE_HIMEM_HIGH
    txa
READ_MODE_HIMEM_HIGH:
    tay
READ_MODE_HIMEM_DONE:
    rts
