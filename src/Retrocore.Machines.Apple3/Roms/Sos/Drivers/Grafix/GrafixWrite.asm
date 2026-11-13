;; .GRAFIX: D_WRITE, the control codes, characters and clearing the viewport. Included by Grafix.asm.

; ---------------------------------------------------------------------------------------------------------------------
; D_WRITE
; ---------------------------------------------------------------------------------------------------------------------

;; D_WRITE: draws the buffer's characters and carries out its control codes.
;;
;; A control code's bytes may be split across writes: <PENDING> keeps the code until they have all arrived.
;; In: BUFFER = the buffer, through extended addressing, REQCNT = the number of bytes
;; Uses: A, X, Y, BUFFER, WRITTEN
;; Errors: XNOTOPEN, XNOGRMEM when <GRSIZE> does not reach the mode's second page
;; See: <WRITE_BYTE>
GR_WRITE:
    bit OPENFLG
    bmi GR_WRITE_1
    jmp NOTOPEN
GR_WRITE_1:
    ldx a:GMODE                         ; is the mode's memory set aside?
    lda GRSIZE
    cmp PAGE_B_TABLE,x
    bcs GR_WRITE_2
    lda #XNOGRMEM
    jsr SYSERR
GR_WRITE_2:
    jsr LOAD_ZPAGE
    lda #$00
    sta WRITTEN
    sta WRITTEN+1
GR_WRITE_3:
    lda WRITTEN+1
    cmp REQCNT+1
    bcc GR_WRITE_4
    lda WRITTEN
    cmp REQCNT
    bcc GR_WRITE_4
    jmp SAVE_ZPAGE
GR_WRITE_4:
    ldy #$00
    lda (BUFFER),y
    inc BUFFER
    bne GR_WRITE_5
    inc BUFFER+1                        ; past $FFFF: on to the next bank pair
    bne GR_WRITE_5
    ldx #$80
    stx BUFFER+1
    inc SXPAGE+BUFFER+1
GR_WRITE_5:
    inc WRITTEN
    bne GR_WRITE_6
    inc WRITTEN+1
GR_WRITE_6:
    jsr WRITE_BYTE
    jmp GR_WRITE_3

;; Takes one byte written to the driver: a byte of a pending control code, a control code, or a character to draw.
;; In: A = the byte
;; Uses: A, X, Y, PENDING, ARGINDEX, ARGS
;; See: <ARGCOUNTS>, <DISPATCH_CODE>, <DRAW_CHAR>
WRITE_BYTE:
    ldx PENDING
    beq WRITE_BYTE_2
    ldy ARGINDEX
    sta ARGS-1,y
    iny                                 ; all of the code's bytes?
    tya
    cmp ARGCOUNTS,x
    bcs WRITE_BYTE_1
    sty ARGINDEX
    rts
WRITE_BYTE_1:
    lda PENDING
    ldy #$00
    sty PENDING
    sty ARGINDEX
    jmp DISPATCH_CODE
WRITE_BYTE_2:
    cmp #$20
    bcc WRITE_BYTE_3
    jmp DRAW_CHAR
WRITE_BYTE_3:
    tax
    lda ARGCOUNTS,x
    beq WRITE_BYTE_4
    stx PENDING                         ; a code with bytes to come
    cmp #$01
    beq WRITE_BYTE_1
    lda #$01
    sta ARGINDEX
WRITE_BYTE_4:
    rts

;; For each control character, the number of bytes it takes, itself included: 0 = ignored, 1 = carried out at once.
ARGCOUNTS:
    .byte 0                                 ; 0: ignored
    .byte 1                                 ; 1: Reset Viewport
    .byte 9                                 ; 2: Set Viewport, 8 bytes
    .byte 6                                 ; 3: Character Set, 5 bytes
    .byte 14                                ; 4: Drawblock, 13 bytes
    .byte 0                                 ; 5: ignored
    .byte 0                                 ; 6: ignored
    .byte 0                                 ; 7: ignored
    .byte 0                                 ; 8: ignored
    .byte 0                                 ; 9: ignored
    .byte 1                                 ; 10: Pen Line Feed
    .byte 0                                 ; 11: ignored
    .byte 0                                 ; 12: ignored
    .byte 1                                 ; 13: Pen Return
    .byte 1                                 ; 14: Turn Screen Off
    .byte 1                                 ; 15: Turn Screen On
    .byte 2                                 ; 16: Graphics Mode, 1 byte
    .byte 1                                 ; 17: Reset Color Operator Table
    .byte 6                                 ; 18: Set Color Operator Table, 5 bytes
    .byte 2                                 ; 19: Pen Color, 1 byte
    .byte 2                                 ; 20: Fill Color, 1 byte
    .byte 2                                 ; 21: Transfer Mode, 1 byte
    .byte 0                                 ; 22: ignored
    .byte 0                                 ; 23: ignored
    .byte 5                                 ; 24: Draw Line, 4 bytes
    .byte 5                                 ; 25: Plot Point, 4 bytes
    .byte 5                                 ; 26: Move Pen, 4 bytes
    .byte 0                                 ; 27: ignored
    .byte 1                                 ; 28: Clear Viewport
    .byte 0                                 ; 29: ignored
    .byte 0                                 ; 30: ignored
    .byte 0                                 ; 31: ignored

; ---------------------------------------------------------------------------------------------------------------------
; Characters
; ---------------------------------------------------------------------------------------------------------------------

;; Draws a character at the pen, its top-left corner at the pen, and moves the pen right by the cell's width.
;;
;; Characters 128-159 are drawn as the character set's 0-31.
;; In: A = the character, 32-255
;; Uses: A, X, Y, SOURCE, BM_WIDTH, BM_HEIGHT, PENX
;; See: <DRAW_BITMAP>
DRAW_CHAR:
    cmp #$A0                            ; 128-159 are the set's 0-31
    bcs DRAW_CHAR_1
    cmp #$80
    bcc DRAW_CHAR_1
    and #$7F
DRAW_CHAR_1:
    ldx a:CHARWIDTH
    stx BM_WIDTH
    ldx a:CHARHEIGHT
    stx BM_HEIGHT
    ldx #$00
    stx BM_WIDTH+1
    stx BM_HEIGHT+1
    ldx a:FONT
    stx SOURCE
    ldx a:FONT+1
    stx SOURCE+1
    ldx a:FONT+2
    stx SXPAGE+SOURCE+1
    tax                                 ; step to the character
    beq DRAW_CHAR_4
DRAW_CHAR_2:
    clc
    lda SOURCE
    adc CHARSIZE
    sta SOURCE
    lda SOURCE+1
    adc CHARSIZE+1
    sta SOURCE+1
    bcc DRAW_CHAR_3
    inc SXPAGE+SOURCE+1                 ; the next bank pair
    inc SXPAGE+SOURCE+1
DRAW_CHAR_3:
    dex
    bne DRAW_CHAR_2
DRAW_CHAR_4:
    jsr DRAW_BITMAP                     ; then move the pen past it
    clc
    lda a:PENX
    adc a:CHARWIDTH
    sta a:PENX
    lda a:PENX+1
    adc #$00
    sta a:PENX+1
    rts

; ---------------------------------------------------------------------------------------------------------------------
; The control codes
; ---------------------------------------------------------------------------------------------------------------------

;; Carries out a control code whose bytes have all arrived.
;; In: A = the code, 0-31, ARGS = its bytes
;; See: <CODE_TABLE>
DISPATCH_CODE:
    asl a
    tay
    lda CODE_TABLE+1,y
    pha
    lda CODE_TABLE,y
    pha
    rts

;; The routine for each control code, less 1, for RTS.
CODE_TABLE:
    .word IGNORE_CODE-1                     ; 0: ignored
    .word RESET_VIEWPORT-1                  ; 1: Reset Viewport
    .word SET_VIEWPORT-1                    ; 2: Set Viewport
    .word SET_FONT-1                        ; 3: Character Set
    .word DRAWBLOCK-1                       ; 4: Drawblock
    .word IGNORE_CODE-1                     ; 5: ignored
    .word IGNORE_CODE-1                     ; 6: ignored
    .word IGNORE_CODE-1                     ; 7: ignored
    .word IGNORE_CODE-1                     ; 8: ignored
    .word IGNORE_CODE-1                     ; 9: ignored
    .word PEN_LINEFEED-1                    ; 10: Pen Line Feed
    .word IGNORE_CODE-1                     ; 11: ignored
    .word IGNORE_CODE-1                     ; 12: ignored
    .word PEN_RETURN-1                      ; 13: Pen Return
    .word SCREEN_OFF-1                      ; 14: Turn Screen Off
    .word SCREEN_ON-1                       ; 15: Turn Screen On
    .word SET_GMODE-1                       ; 16: Graphics Mode
    .word RESET_COLORS-1                    ; 17: Reset Color Operator Table
    .word SET_COLORS-1                      ; 18: Set Color Operator Table
    .word SET_PENCOLOR-1                    ; 19: Pen Color
    .word SET_FILLCOLOR-1                   ; 20: Fill Color
    .word SET_XFER-1                        ; 21: Transfer Mode
    .word IGNORE_CODE-1                     ; 22: ignored
    .word IGNORE_CODE-1                     ; 23: ignored
    .word DRAW_LINE-1                       ; 24: Draw Line
    .word PLOT_POINT-1                      ; 25: Plot Point
    .word MOVE_PEN-1                        ; 26: Move Pen
    .word IGNORE_CODE-1                     ; 27: ignored
    .word CLEAR_VIEWPORT-1                  ; 28: Clear Viewport
    .word IGNORE_CODE-1                     ; 29: ignored
    .word IGNORE_CODE-1                     ; 30: ignored
    .word IGNORE_CODE-1                     ; 31: ignored

;; A control character the driver ignores.
IGNORE_CODE:
    rts

;; Graphics Mode (16): changes the graphics mode.
;; In: ARGS = the mode; bits 0-2 count
;; See: <APPLY_STATE>
SET_GMODE:
    lda ARGS
    sta a:GMODE
    jmp APPLY_STATE

;; Transfer Mode (21): changes the transfer mode.
;; In: ARGS = the mode: 0-3 store, OR, XOR, BIC; 4-7 the same with the color inverted
SET_XFER:
    lda ARGS
    sta a:XFERMODE
    jmp APPLY_STATE

;; Turn Screen Off (14): gives the screen to the graphics driver with the video off; the picture stays.
;; Uses: A, X, Y
SCREEN_OFF:
    lda a:GMODE
    and #$07
    ora #$40
    sta SCRNMODE
    jmp APPLY_STATE

;; Turn Screen On (15): gives the screen to the graphics driver and shows the graphics mode.
;; Uses: A, X, Y
SCREEN_ON:
    lda a:GMODE
    and #$07
    ora #$C0
    sta SCRNMODE
    jmp APPLY_STATE

;; Pen Line Feed (10): moves the pen down by the character cell's height.
;; Uses: A
PEN_LINEFEED:
    sec
    lda a:PENY
    sbc a:CHARHEIGHT
    sta a:PENY
    lda a:PENY+1
    sbc #$00
    sta a:PENY+1
    rts

;; Pen Return (13): moves the pen to the viewport's left edge.
;; Uses: A
PEN_RETURN:
    lda a:VPLEFT
    sta a:PENX
    lda a:VPLEFT+1
    sta a:PENX+1
    rts

;; Character Set (3): changes the character set.
;; In: ARGS = the address (low, high, X-byte), the cell's width, its height
SET_FONT:
    ldx #$04
SET_FONT_1:
    lda ARGS,x
    sta a:FONT,x
    dex
    bpl SET_FONT_1
    jmp APPLY_STATE

;; Reset Viewport (1): makes the viewport the whole screen. The pen does not move.
;; Uses: A, X
RESET_VIEWPORT:
    ldx SCREENTYPE
    lda #$00
    sta a:VPLEFT
    sta a:VPLEFT+1
    sta a:VPBOTTOM
    sta a:VPBOTTOM+1
    lda XLIMIT_LO,x
    sta a:VPRIGHT
    lda XLIMIT_HI,x
    sta a:VPRIGHT+1
    lda YLIMIT_LO
    sta a:VPTOP
    lda YLIMIT_HI
    sta a:VPTOP+1
    rts

;; Set Viewport (2): changes the viewport.
;; In: ARGS = the left, right, bottom and top edges, 16 bits each
SET_VIEWPORT:
    ldx #$08
SET_VIEWPORT_1:
    lda ARGS-1,x
    sta a:VPLEFT-1,x
    dex
    bne SET_VIEWPORT_1
    jmp APPLY_STATE

;; Reset Color Operator Table (17): goes back to the default table, in which the pen's color replaces any screen
;; color.
RESET_COLORS:
    ldx #$7F
RESET_COLORS_1:
    lda a:DCB_COLORS,x
    sta a:COLORTABLE,x
    dex
    bpl RESET_COLORS_1
    jmp APPLY_STATE

;; Set Color Operator Table (18): sets the result for each pair of a pen color and a screen color in two masks.
;; In: ARGS = the pen colors, a 16-bit mask with its high byte first (bit 15 for color 15), ARGS+2 = the screen colors,
;;   ARGS+4 = the result color
;; Uses: A, X, Y, ARGS
SET_COLORS:
    lda ARGS+4
    and #$0F
    sta ARGS+4
    asl a
    asl a
    asl a
    asl a
    ora ARGS+4
    sta ARGS+4
    clv                                 ; overflow clear: the BVCs below always branch
    ldx #$0F
    lda ARGS                            ; pen colors 15-8, then 7-0
SET_COLORS_1:
    asl a
    bcc SET_COLORS_7
    pha
    ldy #$0F
    lda ARGS+2                          ; screen colors 15-8, then 7-0
SET_COLORS_2:
    asl a
    bcc SET_COLORS_5
    pha
    sty ARGS
    txa
    pha
    asl a
    asl a
    asl a
    lsr ARGS                            ; even screen colors in the high nibble
    ora ARGS
    tax
    lda a:COLORTABLE,x
    eor ARGS+4
    bcs SET_COLORS_3
    and #$0F
    bcc SET_COLORS_4
SET_COLORS_3:
    and #$F0
SET_COLORS_4:
    eor ARGS+4
    sta a:COLORTABLE,x
    pla
    tax
    pla
SET_COLORS_5:
    dey
    bmi SET_COLORS_6
    cpy #$07
    bne SET_COLORS_2
    lda ARGS+3
    bvc SET_COLORS_2
SET_COLORS_6:
    pla
SET_COLORS_7:
    dex
    bmi SET_COLORS_8
    cpx #$07
    bne SET_COLORS_1
    lda ARGS+1
    bvc SET_COLORS_1
SET_COLORS_8:
    jmp APPLY_STATE

;; Pen Color (19): changes the pen color.
;; In: ARGS = the color; bits 0-3 count
;; Uses: A
SET_PENCOLOR:
    lda ARGS
    and #$0F
    sta a:PENCOLOR
    rts

;; Fill Color (20): changes the fill color.
;; In: ARGS = the color; bits 0-3 count
SET_FILLCOLOR:
    lda ARGS
    and #$0F
    sta a:FILLCOLOR
    jmp APPLY_STATE

;; Move Pen (26): moves the pen without drawing.
;; In: ARGS = X, then Y, 16 bits each
;; Uses: A, X
MOVE_PEN:
    ldx #$03
MOVE_PEN_1:
    lda ARGS,x
    sta a:PENX,x
    dex
    bpl MOVE_PEN_1
    rts

;; Plot Point (25): moves the pen and draws a dot there, when it is inside the viewport.
;; In: ARGS = X, then Y, 16 bits each
;; Uses: A, X, Y, PENX, PENY, ROW_A..HALF, DIFF..LINE_END+4
PLOT_POINT:
    ldx #$03
PLOT_POINT_1:
    lda ARGS,x
    sta a:PENX,x
    sta LINE_END,x                      ; a dot is a line from the point to itself
    sta LINE_START,x
    dex
    bpl PLOT_POINT_1
    jsr CLIP_LINE
    bcs PLOT_POINT_2
    jmp PLOT_AT
PLOT_POINT_2:
    rts

;; Draw Line (24): draws a line from the pen to a point, the part inside the viewport, and moves the pen there.
;; In: ARGS = X, then Y, 16 bits each
;; Uses: A, X, Y, PENX, PENY, ROW_A..HALF, DIFF..LINE_END+4
;; See: <CLIP_LINE>, <TRACE_LINE>
DRAW_LINE:
    ldx #$03
DRAW_LINE_1:
    lda a:PENX,x
    sta LINE_START,x
    lda ARGS,x
    sta a:PENX,x
    sta LINE_END,x
    dex
    bpl DRAW_LINE_1
    jsr CLIP_LINE
    bcs DRAW_LINE_2
    jsr PLOT_AT
    jmp TRACE_LINE
DRAW_LINE_2:
    rts

; ---------------------------------------------------------------------------------------------------------------------
; Clear Viewport
; ---------------------------------------------------------------------------------------------------------------------

;; Clear Viewport (28): fills the viewport with the fill color. The pen does not move.
;;
;; With the store transfer mode and the default color operator table, each row's whole byte groups are written from
;; <FILLBYTES>, and only the dots before and after them one at a time; otherwise every dot is drawn.
;; Uses: A, X, Y, ROWS..RIGHTCOL
CLEAR_VIEWPORT:
    ldx #$0A
CLEAR_VIEWPORT_1:
    lda ROW_A,x
    pha
    dex
    bpl CLEAR_VIEWPORT_1
    lda #$F0                            ; draw in the fill color
    sta USEFILL
    lda a:VPTOP
    jsr SET_ROW
    sec
    lda a:VPTOP
    sbc a:VPBOTTOM
    sta ROWS
    inc ROWS
    lda #$00
    sta PAIRCNT
    sta TRAILCNT
    lda a:VPLEFT
    ldy a:VPLEFT+1
    jsr SET_COLUMN
    sta LEFTCOL
    ldx SCREENTYPE
    cpx #$03
    beq CLEAR_VIEWPORT_2
    lda #$0F
    sta MASK2
CLEAR_VIEWPORT_2:
    ldx #$04
CLEAR_VIEWPORT_3:
    lda COLUMN,x
    sta ROWSTART,x
    dex
    bpl CLEAR_VIEWPORT_3
    lda DRAWFLAGS                       ; any transfer mode but store, or a changed table?
    ora OPERATION
    beq CLEAR_VIEWPORT_5
    clc                                 ; then every dot: LEADCNT = -1 - the width
    lda a:VPLEFT
    sbc a:VPRIGHT
    sta LEADCNT
    lda a:VPLEFT+1
    sbc a:VPRIGHT+1
    sta LEADCNT+1
    dec LEADCNT
    bne CLEAR_VIEWPORT_4
    dec LEADCNT+1
CLEAR_VIEWPORT_4:
    jmp CLEAR_VIEWPORT_19
CLEAR_VIEWPORT_5:
    stx LEADCNT                         ; the left edge: dots before the first whole group
    stx LEADCNT+1
    lda MASK
    ldx SCREENTYPE
    cpx #$03
    bne CLEAR_VIEWPORT_6
    eor #$0F
CLEAR_VIEWPORT_6:
    cmp #$02
    jsr BYTE_PHASE
    beq CLEAR_VIEWPORT_9
    inc LEFTCOL
    and #$03
    lsr a
    bne CLEAR_VIEWPORT_7
    inc LEFTCOL
CLEAR_VIEWPORT_7:
    rol a
    jsr PHASE_PIXELS
    eor #$FF
    sta LEADCNT
    txa
    ldx #$15
    cmp #$03
    bne CLEAR_VIEWPORT_8
    ldx #$07
CLEAR_VIEWPORT_8:
    dex
    dec LEADCNT
    lda PIXEL140_A,x
    cmp MASK
    bne CLEAR_VIEWPORT_8
    lda PIXEL140_B,x
    cmp MASK2
    bne CLEAR_VIEWPORT_8
CLEAR_VIEWPORT_9:
    lda a:VPRIGHT                       ; the right edge: dots after the last whole group
    ldy a:VPRIGHT+1
    jsr SET_COLUMN
    sta RIGHTCOL
    ldx SCREENTYPE
    cpx #$02
    beq CLEAR_VIEWPORT_10
    sec
    ror HALF
CLEAR_VIEWPORT_10:
    cpx #$03
    bcc CLEAR_VIEWPORT_11
    lda MASK2
    cmp #$78
    jmp CLEAR_VIEWPORT_12
CLEAR_VIEWPORT_11:
    lda MASK
    cmp #$40
CLEAR_VIEWPORT_12:
    jsr BYTE_PHASE
    eor #$07
    tay
    bne CLEAR_VIEWPORT_13
    inc RIGHTCOL
    bpl CLEAR_VIEWPORT_14
CLEAR_VIEWPORT_13:
    and #$02
    bne CLEAR_VIEWPORT_14
    dec RIGHTCOL
CLEAR_VIEWPORT_14:
    tya
    beq CLEAR_VIEWPORT_16
    and #$03
    jsr PHASE_PIXELS
    sta TRAILCNT
    txa
    ldx #$0D
    cmp #$03
    bne CLEAR_VIEWPORT_15
    ldx #$FF
CLEAR_VIEWPORT_15:
    inx
    inc TRAILCNT
    lda PIXEL140_A,x
    cmp MASK
    bne CLEAR_VIEWPORT_15
    lda PIXEL140_B,x
    cmp MASK2
    bne CLEAR_VIEWPORT_15
CLEAR_VIEWPORT_16:
    sec                                 ; the whole groups between
    lda RIGHTCOL
    sbc LEFTCOL
    bmi CLEAR_VIEWPORT_17
    lsr a
    sta PAIRCNT
    bne CLEAR_VIEWPORT_19
    sec
    lda LEADCNT
    bcs CLEAR_VIEWPORT_18
CLEAR_VIEWPORT_17:
    lda LEADCNT
    ldx SCREENTYPE
    adc GROUPWIDTH,x
CLEAR_VIEWPORT_18:
    sbc TRAILCNT
    sta LEADCNT
    lda #$00
    sta TRAILCNT
CLEAR_VIEWPORT_19:
    ldx #$04                            ; each row
CLEAR_VIEWPORT_20:
    lda LEADCNT,x
    sta LEADPIX,x
    lda ROWSTART,x
    sta COLUMN,x
    dex
    bpl CLEAR_VIEWPORT_20
    tay
CLEAR_VIEWPORT_21:
    inc LEADPIX
    bne CLEAR_VIEWPORT_22
    inc LEADPIX+1
    bne CLEAR_VIEWPORT_22
    jmp CLEAR_VIEWPORT_23
CLEAR_VIEWPORT_22:
    jsr PLOT_RIGHT
    jmp CLEAR_VIEWPORT_21
CLEAR_VIEWPORT_23:
    dec PAIRS                           ; the whole groups
    bmi CLEAR_VIEWPORT_25
    ldx #$00
CLEAR_VIEWPORT_24:
    lda FILLBYTES,x
    sta (ROW_A),y
    lda FILLBYTES+1,x
    sta (ROW_B),y
    iny
    inx
    inx
    cpx #$02
    beq CLEAR_VIEWPORT_24
    bne CLEAR_VIEWPORT_23
CLEAR_VIEWPORT_25:
    sty COLUMN                          ; the dots after them
    dec TRAILPIX
    bmi CLEAR_VIEWPORT_26
    jsr PLOT_RIGHT
    jmp CLEAR_VIEWPORT_25
CLEAR_VIEWPORT_26:
    dec ROWS
    beq CLEAR_VIEWPORT_27
    jsr ROW_DOWN
    jmp CLEAR_VIEWPORT_19
CLEAR_VIEWPORT_27:
    ldx #$00                            ; put back the zero page
CLEAR_VIEWPORT_28:
    pla
    sta ROW_A,x
    inx
    cpx #$0B
    bne CLEAR_VIEWPORT_28
    lda #$00
    sta USEFILL
    rts

;; Gives a dot's place in its byte group as three bits.
;;
;; It rotates COLUMN and HALF through A, so they must be put back after; <CLEAR_VIEWPORT> takes them from <ROWSTART>.
;; In: A = the dot's bits in its byte, carry = set when the dot is not the byte's first (or for the right edge, is its
;;   last)
;; Out: A = bit 2: carry, bit 1: the column is odd, bit 0: the byte is in the second page; zero = set for 0
;; Uses: COLUMN, HALF
BYTE_PHASE:
    rol a
    ror COLUMN
    rol a
    rol HALF
    rol a
    and #$07
    rts

;; Gives the number of dots of a byte group in the bytes after a dot's byte.
;; In: A = the dot's place, bits 0-1 of <BYTE_PHASE>'s, X = SCREENTYPE
;; Out: A = 21, 14, 7 or 0; mode 3 always 0
;; Uses: Y
PHASE_PIXELS:
    tay
    cpx #$02
    beq PHASE_PIXELS_1
    ldy #$03
    bcs PHASE_PIXELS_1
    cmp #$02
    bcs PHASE_PIXELS_1
    dey
PHASE_PIXELS_1:
    lda TAILPIXELS,y
    rts

;; Draws the current dot, then moves right one dot.
;; In: Y = COLUMN
;; Out: Y = COLUMN
;; Uses: A, X
PLOT_RIGHT:
    jsr PLOT_PIXEL
    jsr PIXEL_RIGHT
    rts
