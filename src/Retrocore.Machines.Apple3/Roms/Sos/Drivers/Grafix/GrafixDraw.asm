;; .GRAFIX: blocks of dots, line clipping, screen addresses, lines and dots. Included by Grafix.asm.

; ---------------------------------------------------------------------------------------------------------------------
; Blocks of dots
; ---------------------------------------------------------------------------------------------------------------------

;; Drawblock (4): draws a block of dots from memory, its top-left corner at the pen, inside the viewport.
;;
;; A 1 bit is drawn in the pen color and a 0 bit in the fill color. The bits of each byte run as the character set's
;; (<FONTORDER>). The pen does not move.
;; In: ARGS = the block's address (low, high, X-byte), then, 16 bits each, the bytes in each row, the dots to skip at
;;   the start of each row, the rows to skip, the width and the height
;; Uses: A, X, Y, SOURCE, DIFF..BMY+1
;; See: <DRAW_BITMAP>
DRAWBLOCK:
    lda BITORDER
    pha
    lda a:FONTORDER
    sta BITORDER
    ldx #$09                            ; keep the character settings
DRAWBLOCK_1:
    lda BM_ROWBYTES,x
    pha
    lda ARGS+3,x
    sta BM_ROWBYTES,x
    dex
    bpl DRAWBLOCK_1
    lda ARGS
    sta SOURCE
    lda ARGS+1
    sta SOURCE+1
    lda ARGS+2
    sta SXPAGE+SOURCE+1
    jsr DRAW_BITMAP
    ldx #$00
DRAWBLOCK_2:
    pla
    sta BM_ROWBYTES,x
    inx
    cpx #$0A
    bcc DRAWBLOCK_2
    pla
    sta BITORDER
    rts

;; Draws a block of dots with its top-left corner at the pen, clipped to the viewport.
;;
;; The block is <BM_WIDTH> dots by <BM_HEIGHT> rows from <SOURCE>, <BM_ROWBYTES> bytes to a row, starting
;; <BM_SKIPY> rows and <BM_SKIPX> dots in. Each dot is drawn in the pen color for a 1 bit and the fill color for a 0.
;; In: SOURCE = the first row, with its X-byte, BM_ROWBYTES..BM_HEIGHT+1 = the block's shape, BITORDER = the bit order
;; Uses: A, X, Y, SOURCE, BM_SKIPX, BM_SKIPY, BM_WIDTH, BM_HEIGHT, DIFF..BMY+1
DRAW_BITMAP:
    ldx #$03
    lda #$F0
    sta BITMAPFLG
DRAW_BITMAP_1:
    lda a:PENX,x
    sta BMX,x
    dex
    bpl DRAW_BITMAP_1
    sec                                 ; clip the left edge
    lda a:VPLEFT
    sbc BMX
    sta DIFF
    lda a:VPLEFT+1
    sbc BMX+1
    sta DIFF+1
    bmi DRAW_BITMAP_2
    sec
    lda BM_WIDTH
    sbc DIFF
    sta BM_WIDTH
    lda BM_WIDTH+1
    sbc DIFF+1
    sta BM_WIDTH+1
    bmi DRAW_BITMAP_4
    lda a:VPLEFT
    sta BMX
    lda a:VPLEFT+1
    sta BMX+1
    bit BITORDER
    bpl DRAW_BITMAP_2
    clc
    lda BM_SKIPX
    adc DIFF
    sta BM_SKIPX
    lda BM_SKIPX+1
    adc DIFF+1
    sta BM_SKIPX+1
DRAW_BITMAP_2:
    clc                                 ; the right edge
    lda BMX
    adc BM_WIDTH
    sta DIFF
    lda BMX+1
    adc BM_WIDTH+1
    sta DIFF+1
    sec
    lda DIFF
    sbc a:VPRIGHT
    sta DIFF
    lda DIFF+1
    sbc a:VPRIGHT+1
    sta DIFF+1
    bmi DRAW_BITMAP_5
    inc BM_WIDTH
    bne DRAW_BITMAP_3
    inc BM_WIDTH+1
DRAW_BITMAP_3:
    sec
    lda BM_WIDTH
    sbc DIFF
    sta BM_WIDTH
    lda BM_WIDTH+1
    sbc DIFF+1
    sta BM_WIDTH+1
    bpl DRAW_BITMAP_5
DRAW_BITMAP_4:
    rts
DRAW_BITMAP_5:
    sec                                 ; the top edge
    lda BMY
    sbc a:VPTOP
    sta DIFF
    lda BMY+1
    sbc a:VPTOP+1
    sta DIFF+1
    bmi DRAW_BITMAP_7
    sec
    lda BM_HEIGHT
    sbc DIFF
    sta BM_HEIGHT
    lda BM_HEIGHT+1
    sbc DIFF+1
    sta BM_HEIGHT+1
    bmi DRAW_BITMAP_4
    bne DRAW_BITMAP_6
    lda BM_HEIGHT
    beq DRAW_BITMAP_4
DRAW_BITMAP_6:
    lda a:VPTOP
    sta BMY
    lda a:VPTOP+1
    sta BMY+1
    clc
    lda BM_SKIPY
    adc DIFF
    sta BM_SKIPY
    lda BM_SKIPY+1
    adc DIFF+1
    sta BM_SKIPY+1
DRAW_BITMAP_7:
    sec                                 ; the bottom edge
    lda BMY
    sbc a:VPBOTTOM
    sta ROWS
    lda BMY+1
    sbc a:VPBOTTOM+1
    sta ROWS+1
    bmi DRAW_BITMAP_4
    sec
    lda BMY
    sbc BM_HEIGHT
    sta DIFF
    lda BMY+1
    sbc BM_HEIGHT+1
    sta DIFF+1
    sec
    lda DIFF
    sbc a:VPBOTTOM
    sta DIFF
    lda DIFF+1
    sbc a:VPBOTTOM+1
    sta DIFF+1
    bpl DRAW_BITMAP_8
    inc ROWS
    bne DRAW_BITMAP_9
DRAW_BITMAP_8:
    sec
    lda ROWS
    sbc DIFF
    sta ROWS
    lda ROWS+1
    sbc DIFF+1
    sta ROWS+1
DRAW_BITMAP_9:
    ldx #$0A
DRAW_BITMAP_10:
    lda ROW_A,x
    pha
    dex
    bpl DRAW_BITMAP_10
    lda BMY
    jsr SET_ROW
    lda BMX
    ldy BMX+1
    jsr SET_COLUMN
    ldx #$04
DRAW_BITMAP_11:
    lda COLUMN,x
    sta ROWSTART,x
    dex
    bpl DRAW_BITMAP_11
    clc                                 ; the visible bytes and bits of each source row
    lda BM_SKIPX
    adc BM_WIDTH
    sta DIFF
    lda BM_SKIPX+1
    adc BM_WIDTH+1
    sta DIFF+1
    lda BM_SKIPX
    and #$07
    sta FIRSTBIT
    lda DIFF
    and #$07
    sta LASTBIT
    lda BM_SKIPX
    ror BM_SKIPX+1
    ror a
    ror BM_SKIPX+1
    ror a
    ror BM_SKIPX+1
    ror a
    sta FIRSTBYTE
    lda DIFF
    ror DIFF+1
    ror a
    ror DIFF+1
    ror a
    ror DIFF+1
    ror a
    sta LASTBYTE
DRAW_BITMAP_12:
    lda BM_SKIPY                        ; skip the rows above the viewport
    bne DRAW_BITMAP_13
    lda BM_SKIPY+1
    beq DRAW_BITMAP_15
DRAW_BITMAP_13:
    clc
    lda SOURCE
    adc BM_ROWBYTES
    sta SOURCE
    lda SOURCE+1
    adc BM_ROWBYTES+1
    sta SOURCE+1
    bcc DRAW_BITMAP_14
    inc SXPAGE+SOURCE+1
    inc SXPAGE+SOURCE+1
DRAW_BITMAP_14:
    lda BM_SKIPY
    sec
    sbc #$01
    sta BM_SKIPY
    lda BM_SKIPY+1
    sbc #$00
    sta BM_SKIPY+1
    jmp DRAW_BITMAP_12
DRAW_BITMAP_15:
    ldx #$04                            ; each row
DRAW_BITMAP_16:
    lda ROWSTART,x
    sta COLUMN,x
    dex
    bpl DRAW_BITMAP_16
    ldy FIRSTBYTE
    sty BYTEINDEX
    lda (SOURCE),y
    ldx #$00
DRAW_BITMAP_17:
    cpx FIRSTBIT
    beq DRAW_BITMAP_18
    asl a
    inx
    bne DRAW_BITMAP_17
DRAW_BITMAP_18:
    sta SRCBITS
DRAW_BITMAP_19:
    stx BITINDEX
    cpx LASTBIT
    bne DRAW_BITMAP_20
    lda BYTEINDEX
    cmp LASTBYTE
    beq DRAW_BITMAP_24
DRAW_BITMAP_20:
    ldy COLUMN
    bit BITORDER
    bmi DRAW_BITMAP_21
    lsr SRCBITS
    bpl DRAW_BITMAP_22
DRAW_BITMAP_21:
    asl SRCBITS
DRAW_BITMAP_22:
    lda #$00                            ; a 1 bit in the pen color, a 0 bit in the fill color
    bcs DRAW_BITMAP_23
    lda #$F0
DRAW_BITMAP_23:
    sta USEFILL
    jsr PLOT_RIGHT
    ldx BITINDEX
    inx
    cpx #$08
    bne DRAW_BITMAP_19
    ldx #$00
    inc BYTEINDEX
    ldy BYTEINDEX
    lda (SOURCE),y
    sta SRCBITS
    jmp DRAW_BITMAP_19
DRAW_BITMAP_24:
    dec ROWS                            ; the next row
    beq DRAW_BITMAP_26
    jsr ROW_DOWN
    clc
    lda SOURCE
    adc BM_ROWBYTES
    sta SOURCE
    lda SOURCE+1
    adc BM_ROWBYTES+1
    sta SOURCE+1
    bcc DRAW_BITMAP_25
    inc SXPAGE+SOURCE+1
    inc SXPAGE+SOURCE+1
DRAW_BITMAP_25:
    jmp DRAW_BITMAP_15
DRAW_BITMAP_26:
    ldx #$00
DRAW_BITMAP_27:
    pla
    sta ROW_A,x
    inx
    cpx #$0B
    bne DRAW_BITMAP_27
    lda #$00
    sta USEFILL
    sta BITMAPFLG
    rts

; ---------------------------------------------------------------------------------------------------------------------
; Clipping lines to the viewport
; ---------------------------------------------------------------------------------------------------------------------

;; Clips a line to the viewport.
;; In: LINE_START = the start's X and Y, LINE_END = the end's
;; Out: carry = set when no part of the line is inside the viewport; clear with LINE_START and LINE_END moved to the
;;   ends of the part inside
;; Uses: A, X, Y, POINTS..LINE_END+4
;; See: <OUTCODE>, <FIND_EDGE>
CLIP_LINE:
    ldy #LINE_START-POINTS
    jsr OUTCODE
    sta LINE_START+4
    ldy #LINE_END-POINTS
    jsr OUTCODE
    sta LINE_END+4
CLIP_LINE_1:
    lda LINE_END+4                      ; both inside?
    ora LINE_START+4
    and #$0F
    bne CLIP_LINE_2
    clc
    rts
CLIP_LINE_2:
    lda LINE_START+4                    ; both beyond one edge?
    and LINE_END+4
    and #$0F
    beq CLIP_LINE_4
    sec
CLIP_LINE_3:
    rts
CLIP_LINE_4:
    lda LINE_START+4                    ; move the start in
    and #$0F
    beq CLIP_LINE_5
    ldx #SEG_A-POINTS
    ldy #LINE_START-POINTS
    jsr COPY_POINT
    ldx #SEG_B-POINTS
    ldy #LINE_END-POINTS
    jsr COPY_POINT
    jsr FIND_EDGE
    bcs CLIP_LINE_3
    ldx #LINE_START-POINTS
    ldy #MIDPOINT-POINTS
    jsr COPY_POINT
    beq CLIP_LINE_1
CLIP_LINE_5:
    lda LINE_END+4                      ; move the end in
    and #$0F
    beq CLIP_LINE_1
    ldx #SEG_A-POINTS
    ldy #LINE_END-POINTS
    jsr COPY_POINT
    ldx #SEG_B-POINTS
    ldy #LINE_START-POINTS
    jsr COPY_POINT
    jsr FIND_EDGE
    bcs CLIP_LINE_3
    ldx #LINE_END-POINTS
    ldy #MIDPOINT-POINTS
    jmp COPY_POINT

;; Finds where a segment from a point outside the viewport enters it, by halving the segment.
;;
;; It returns, carry clear, as soon as both ends are beyond the same edge, leaving MIDPOINT outside, so that
;; <CLIP_LINE> rejects the line.
;; In: SEG_A = the end outside, SEG_B = the other end, each with its <OUTCODE>
;; Out: carry = set when the segment never enters, MIDPOINT = the point on the edge when carry is clear
;; Uses: A, X, Y, SEG_A, SEG_B, MIDPOINT, ROUNDX, ROUNDY, INSIDE
FIND_EDGE:
    lda SEG_A+4
    eor SEG_B+4
    and SEG_A+4
    asl a
    asl a
    asl a
    asl a
    sta INSIDE
    and SEG_B+4
    beq FIND_EDGE_2
    lda SEG_B+4
    and #$0F
    bne FIND_EDGE_1
    ldx #MIDPOINT-POINTS
    ldy #SEG_B-POINTS
    clc
    jmp COPY_POINT
FIND_EDGE_1:
    sec
    rts
FIND_EDGE_2:
    sta ROUNDX
    sta ROUNDY
FIND_EDGE_3:
    rol ROUNDX                          ; MIDPOINT = (SEG_A + SEG_B) / 2, X then Y
    lda SEG_A
    adc SEG_B
    sta MIDPOINT
    lda SEG_A+1
    adc SEG_B+1
    bvs FIND_EDGE_4
    cmp #$80
FIND_EDGE_4:
    ror a
    sta MIDPOINT+1
    ror MIDPOINT
    ror ROUNDX
    rol ROUNDY
    lda SEG_A+2
    adc SEG_B+2
    sta MIDPOINT+2
    lda SEG_A+3
    adc SEG_B+3
    bvs FIND_EDGE_5
    cmp #$80
FIND_EDGE_5:
    ror a
    sta MIDPOINT+3
    ror MIDPOINT+2
    ror ROUNDY
    ldy #MIDPOINT-POINTS
    jsr OUTCODE
    sta MIDPOINT+4
    and SEG_A+4
    and #$0F
    beq FIND_EDGE_7
    ldx #SEG_A-POINTS
    jsr COPY_POINT
    lda SEG_A+4
    and SEG_B+4
    and #$0F
    beq FIND_EDGE_3
FIND_EDGE_6:
    clc
    rts
FIND_EDGE_7:
    lda MIDPOINT+4
    and INSIDE
    bne FIND_EDGE_6
    ldx #SEG_B-POINTS
    jsr COPY_POINT
    beq FIND_EDGE_3

;; Classifies a point against the viewport.
;; In: Y = the point's offset from <POINTS>
;; Out: A = bit 0: left of the viewport, 1: right of it, 2: below it, 3: above it, 4: on the left edge, 5: on the
;;   right edge, 6: on the bottom edge, 7: on the top edge
;; Uses: X
OUTCODE:
    lda #$00
    ldx POINTS+1,y
    bmi OUTCODE_6
    cpx a:VPLEFT+1
    bcc OUTCODE_6
    bne OUTCODE_2
    ldx POINTS,y
    cpx a:VPLEFT
    bcc OUTCODE_6
    beq OUTCODE_5
OUTCODE_1:
    ldx POINTS+1,y
OUTCODE_2:
    cpx a:VPRIGHT+1
    bcc OUTCODE_7
    bne OUTCODE_3
    ldx POINTS,y
    cpx a:VPRIGHT
    bcc OUTCODE_7
    beq OUTCODE_4
OUTCODE_3:
    ora #$02
    bne OUTCODE_7
OUTCODE_4:
    ora #$20
    bne OUTCODE_7
OUTCODE_5:
    ora #$10
    bne OUTCODE_1
OUTCODE_6:
    ora #$01
OUTCODE_7:
    ldx POINTS+3,y
    bmi OUTCODE_12
    bne OUTCODE_9
    ldx POINTS+2,y
    cpx a:VPBOTTOM
    bcc OUTCODE_12
    beq OUTCODE_11
OUTCODE_8:
    cpx a:VPTOP
    beq OUTCODE_10
    bcc OUTCODE_13
OUTCODE_9:
    ora #$08
    rts
OUTCODE_10:
    ora #$80
    rts
OUTCODE_11:
    ora #$40
    bne OUTCODE_8
OUTCODE_12:
    ora #$04
OUTCODE_13:
    rts

;; Copies a five-byte point.
;; In: X = the destination's offset from <POINTS>, Y = the source's
;; Out: zero = set
;; Uses: A, X, Y, COPYCOUNT
COPY_POINT:
    lda #$05
    sta COPYCOUNT
COPY_POINT_1:
    lda a:POINTS,y
    sta POINTS,x
    inx
    iny
    dec COPYCOUNT
    bne COPY_POINT_1
    rts

; ---------------------------------------------------------------------------------------------------------------------
; Screen addresses
; ---------------------------------------------------------------------------------------------------------------------

;; Points <ROW_A> and <ROW_B> at the screen row for a Y.
;; In: A = Y, 0-191, counting up from the bottom
;; Out: COLORDONE = the row's group, bit 7 clear
;; Uses: A, X, Y, TEMP
SET_ROW:
    sta TEMP
    sec
    lda #$BF                            ; the row from the top
    sbc TEMP
    tay
    lsr a
    lsr a
    lsr a
    tax
    tya                                 ; the row within its group of eight
    asl a
    asl a
    and #$1C
    ora ROWHI,x
    tay
    ora PAGE_A
    sta ROW_A+1
    tya
    ora PAGE_B
    sta ROW_B+1
    lda ROWLO,x
    sta ROW_A
    sta ROW_B
    stx COLORDONE
    rts

;; Finds the byte and bits of an X on the current row.
;; In: A = X's low byte, Y = its high byte, 0-559
;; Out: A = COLUMN, COLUMN/MASK/HALF/MASK2/PHASE = the dot (HALF for mode 2, MASK2 and PHASE for mode 3)
;; Uses: X, Y
SET_COLUMN:
    sec                                 ; divide X by 7: A = the remainder - 7, Y = the quotient
    beq SET_COLUMN_3
    dey
    beq SET_COLUMN_1
    ldy #$48
    adc #$01
    bcc SET_COLUMN_2
SET_COLUMN_1:
    ldy #$23
    adc #$04
    bcc SET_COLUMN_2
    iny
    sbc #$07
SET_COLUMN_2:
    iny
SET_COLUMN_3:
    sbc #$07
    bcs SET_COLUMN_2
    tax
    tya
    ldy BITMASKS-$F9,x                  ; the dot's bit
    sty MASK
    ldy SCREENTYPE
    cpy #$02
    sty HALF
    bcc SET_COLUMN_4
    beq SET_COLUMN_5
    asl a                               ; mode 3: two bytes to each seven dots
    ldy a:PIXEL140_B-$F9,x
    sty MASK2
    ldy PIXEL140_A-$F9,x
    sty MASK
    stx PHASE
    cpx #$FC
    adc #$00
SET_COLUMN_4:
    sta COLUMN
    rts
SET_COLUMN_5:
    lsr a                               ; mode 2: even bytes in the first page, odd in the second
    sta COLUMN
    ror HALF
    rts

;; Moves <ROW_A> and <ROW_B> one screen row up or down.
;; In: negative = set to move up, clear to move down
;; Out: COLORDONE = bit 7 clear
;; Uses: A, X
;; Keeps: Y
;; See: <ROW_DOWN>
ROW_STEP:
    bpl ROW_DOWN
    clc                                 ; up
    lda ROW_A+1
    bit LINE_BITS
    bne ROW_STEP_5
    asl ROW_A
    bcs ROW_STEP_3
    bit GROUP_BITS
    beq ROW_STEP_1
    adc #$1F
    sec
    bcs ROW_STEP_4
ROW_STEP_1:
    adc #$23
    pha
    lda ROW_A
    adc #$B0
    bcs ROW_STEP_2
    adc #$F0
ROW_STEP_2:
    sta ROW_A
    pla
    bcs ROW_STEP_4
ROW_STEP_3:
    adc #$1F
ROW_STEP_4:
    ror ROW_A
    ldx ROW_A
    stx ROW_B
ROW_STEP_5:
    adc #$FC
ROW_STEP_6:
    sta ROW_A+1
    and #$1F
    sta COLORDONE
    ora PAGE_B
    sta ROW_B+1
    rts

;; Moves <ROW_A> and <ROW_B> one screen row down.
;; Out: COLORDONE = bit 7 clear
;; Uses: A, X
;; Keeps: Y
ROW_DOWN:
    clc                                 ; the next row of the group
    lda ROW_A+1
    adc #$04
    bit LINE_BITS
    bne ROW_STEP_6
    asl ROW_A
    bcc ROW_DOWN_2
    adc #$E0
    clc
    bit THIRD_BIT
    beq ROW_DOWN_3
    lda ROW_A
    adc #$50
    eor #$F0
    beq ROW_DOWN_1
    eor #$F0
ROW_DOWN_1:
    sta ROW_A
    lda ROW_A+1
    and #$E0
    bcc ROW_DOWN_3
ROW_DOWN_2:
    adc #$E0
ROW_DOWN_3:
    ror ROW_A
    ldx ROW_A
    stx ROW_B
    bcc ROW_STEP_6

;; Moves the current dot one left or right.
;; In: overflow = set to move left, clear to move right, Y = COLUMN
;; Out: Y = COLUMN
;; Uses: A, X, MASK, MASK2, PHASE, HALF
COLUMN_STEP:
    bvs PIXEL_LEFT
    jmp PIXEL_RIGHT

;; Moves the current dot one left; at the left edge of the screen it stays.
;; In: Y = COLUMN
;; Out: Y = COLUMN, COLUMN/MASK/HALF/MASK2/PHASE = the new dot
;; Uses: A, X
PIXEL_LEFT:
    ldx SCREENTYPE
    cpx #$02
    beq PIXEL_LEFT_5
    bcs PIXEL_LEFT_6
    lsr MASK
    bcc PIXEL_LEFT_4
    dey
    bpl PIXEL_LEFT_3
PIXEL_LEFT_1:
    rol MASK
    iny
    sty COLUMN
    rts
PIXEL_LEFT_2:
    ldy #$27
PIXEL_LEFT_3:
    lda #$40
    sta MASK
    sty COLUMN
PIXEL_LEFT_4:
    rts
PIXEL_LEFT_5:
    lsr MASK
    bcc PIXEL_LEFT_4
    lda #$40
    sta MASK
    asl a
    eor HALF
    sta HALF
    bpl PIXEL_LEFT_4
    dey
    sty COLUMN
    bpl PIXEL_LEFT_4
    lsr HALF
    sec
    bcs PIXEL_LEFT_1
PIXEL_LEFT_6:
    ldx PHASE
    cpx #$FC
    bne PIXEL_LEFT_7
    dey
PIXEL_LEFT_7:
    dex
    cpx #$F9
    bcs PIXEL_LEFT_8
    ldx #$FF
    dey
    bpl PIXEL_LEFT_8
    iny
    ldx #$F9
PIXEL_LEFT_8:
    sty COLUMN
    stx PHASE
    lda PIXEL140_A-$F9,x
    sta MASK
    lda a:PIXEL140_B-$F9,x
    sta MASK2
    rts

;; Moves the current dot one right; at the right edge of the screen it stays.
;; In: Y = COLUMN
;; Out: Y = COLUMN, COLUMN/MASK/HALF/MASK2/PHASE = the new dot
;; Uses: A, X
PIXEL_RIGHT:
    ldx SCREENTYPE
    cpx #$02
    beq PIXEL_RIGHT_3
    bcs PIXEL_RIGHT_4
    asl MASK
    bpl PIXEL_RIGHT_2
    iny
    cpy #$28
    bcc PIXEL_RIGHT_1
    jmp PIXEL_LEFT_2
PIXEL_RIGHT_1:
    lda #$01
    sta MASK
    sty COLUMN
PIXEL_RIGHT_2:
    rts
PIXEL_RIGHT_3:
    asl MASK
    bpl PIXEL_RIGHT_2
    lda #$01
    sta MASK
    lda #$FF
    eor HALF
    sta HALF
    bmi PIXEL_RIGHT_2
    iny
    sty COLUMN
    cpy #$28
    bcc PIXEL_RIGHT_2
    ror HALF
    jmp PIXEL_LEFT_2
PIXEL_RIGHT_4:
    ldx PHASE
    cpx #$FB
    bne PIXEL_RIGHT_5
    iny
PIXEL_RIGHT_5:
    inx
    bne PIXEL_RIGHT_6
    ldx #$F9
    iny
    cpy #$28
    bcc PIXEL_RIGHT_6
    ldx #$FF
    ldy #$27
PIXEL_RIGHT_6:
    sty COLUMN
    stx PHASE
    lda a:PIXEL140_B-$F9,x
    sta MASK2
    lda PIXEL140_A-$F9,x
    sta MASK
    rts

; ---------------------------------------------------------------------------------------------------------------------
; Lines
; ---------------------------------------------------------------------------------------------------------------------

;; Draws a line's dots after its first, which must be the current dot.
;;
;; It steps along the longer direction one dot at a time, stepping the other when the error term runs out. The line
;; must fit the screen, so its rows fit in a byte.
;; In: LINE_START/LINE_END = the clipped line, Y = COLUMN
;; Uses: A, X, Y, LINE_DIR, LINE_DX, LINE_DY, STEPS, LINE_ERR
TRACE_LINE:
    sec
    lda LINE_END
    sbc LINE_START
    pha
    lda LINE_END+1
    sbc LINE_START+1
    sta LINE_DIR
    bcs TRACE_LINE_1
    pla
    eor #$FF
    adc #$01
    pha
    lda #$00
    sbc LINE_DIR
TRACE_LINE_1:
    sta LINE_DX+1
    pla
    sta LINE_DX
    sec
    lda LINE_END+2
    sbc LINE_START+2
    bcs TRACE_LINE_2
    eor #$FF
    adc #$01
TRACE_LINE_2:
    sta LINE_DY
    ror LINE_DIR
    ldy COLUMN
    ldx LINE_DX+1
    bne TRACE_LINE_3
    cmp LINE_DX
    bcs TRACE_LINE_7
TRACE_LINE_3:
    stx STEPS+1
    txa
    lsr a
    sta LINE_ERR+1
    lda LINE_DX
    bne TRACE_LINE_4
    dec STEPS+1
TRACE_LINE_4:
    sta STEPS
    ror a
    sta LINE_ERR
TRACE_LINE_5:
    lda LINE_ERR                        ; mostly across
    sec
    sbc LINE_DY
    sta LINE_ERR
    bcs TRACE_LINE_6
    dec LINE_ERR+1
    bpl TRACE_LINE_6
    adc LINE_DX
    sta LINE_ERR
    lda LINE_ERR+1
    adc LINE_DX+1
    sta LINE_ERR+1
    lda LINE_DIR
    jsr ROW_STEP
TRACE_LINE_6:
    bit LINE_DIR
    jsr COLUMN_STEP
    jsr PLOT_PIXEL
    dec STEPS
    bne TRACE_LINE_5
    dec STEPS+1
    bpl TRACE_LINE_5
    rts
TRACE_LINE_7:
    sta STEPS                           ; mostly up or down
    tax
    beq TRACE_LINE_10
    lsr a
    sta LINE_ERR+1
TRACE_LINE_8:
    lda LINE_ERR+1
    sec
    sbc LINE_DX
    sta LINE_ERR+1
    bcs TRACE_LINE_9
    adc LINE_DY
    sta LINE_ERR+1
    bit LINE_DIR
    jsr COLUMN_STEP
TRACE_LINE_9:
    lda LINE_DIR
    jsr ROW_STEP
    jsr PLOT_PIXEL
    dec STEPS
    bne TRACE_LINE_8
TRACE_LINE_10:
    rts

; ---------------------------------------------------------------------------------------------------------------------
; Drawing dots
; ---------------------------------------------------------------------------------------------------------------------

;; Draws the dot at <LINE_START>.
;; Out: Y = COLUMN
;; Uses: A, X
PLOT_AT:
    lda LINE_START+2
    jsr SET_ROW
    lda LINE_START
    ldy LINE_START+1
    jsr SET_COLUMN
    tay

;; Draws the current dot in the pen color, or the fill color when <USEFILL> is $F0, through the transfer mode and
;; the color operator table.
;; In: Y = COLUMN
;; Uses: A, X
PLOT_PIXEL:
    bit DRAWFLAGS                       ; overflow = use the color operator table
    ldx SCREENTYPE
    dex
    beq PLOT_COLOR280
    lda USEFILL
    asl a
    lda a:PENCOLOR
    bcc PLOT_PIXEL_1
    lda a:FILLCOLOR
PLOT_PIXEL_1:
    cpx #$02
    bne PLOT_PIXEL_2
    jmp PLOT_140
PLOT_PIXEL_2:
    bvc PLOT_PIXEL_3
    jsr OPERATE_BW
PLOT_PIXEL_3:
    cmp #$00
    beq PLOT_PIXEL_4
    lda MASK
PLOT_PIXEL_4:
    jmp TRANSFER

;; Mode 1: sets or clears the dot's bit and writes its byte's color byte.
;;
;; A dot in the pen color sets its bit and writes the color byte's foreground nibble; one in the fill color clears it
;; and writes the background nibble. While drawing a block of dots (<BITMAPFLG>) both nibbles are written. The color
;; byte is worked out again only when the column or row changes (<LASTCOL>, <COLORDONE>).
;; In: Y = COLUMN, overflow = set to use the color operator table
;; Uses: A, X, BACKCOLOR, FORECOLOR, COLORBYTE
PLOT_COLOR280:
    bit COLORDONE
    bpl PLOT_COLOR280_1
    cpy LASTCOL
    beq PLOT_COLOR280_3
PLOT_COLOR280_1:
    lda a:FILLCOLOR
    sta BACKCOLOR
    lda a:PENCOLOR
    sta FORECOLOR
    bit DRAWFLAGS
    bvc PLOT_COLOR280_2
    lda USEFILL
    pha
    lda #$F0
    sta USEFILL
    sec
    jsr OPERATE_COLOR280
    sta BACKCOLOR
    lda #$00
    sta USEFILL
    clc
    jsr OPERATE_COLOR280
    sta FORECOLOR
    pla
    sta USEFILL
PLOT_COLOR280_2:
    lda FORECOLOR
    asl a
    asl a
    asl a
    asl a
    ora BACKCOLOR
    sta COLORBYTE
PLOT_COLOR280_3:
    ldx MASK                            ; the color byte's nibble
    lda USEFILL
    asl a
    lda #$F0
    bcc PLOT_COLOR280_4
    lda #$0F
PLOT_COLOR280_4:
    sta MASK
    and COLORBYTE
    jsr TRANSFER_B
    bit BITMAPFLG
    bpl PLOT_COLOR280_6
    lda USEFILL
    asl a
    lda #$0F
    bcc PLOT_COLOR280_5
    lda #$F0
PLOT_COLOR280_5:
    sta MASK
    lda MASK
    and COLORBYTE
    jsr TRANSFER_B
PLOT_COLOR280_6:
    stx MASK                            ; then the dot's bit
    lda (ROW_A),y
    ora MASK
    ldx USEFILL
    beq PLOT_COLOR280_7
    eor MASK
PLOT_COLOR280_7:
    sta (ROW_A),y
    lda #$F0
    sta COLORDONE
    sty LASTCOL
    rts

;; Mode 3: writes the dot's four color bits into its two bytes.
;; In: A = the color, Y = COLUMN, overflow = set to use the color operator table
;; Uses: A, X, PAGEA_BITS
PLOT_140:
    bvc PLOT_140_1
    jsr OPERATE_140
PLOT_140_1:
    jsr SPLIT_140
    tax
    lda MASK
    beq PLOT_140_2
    lda PAGEA_BITS
    jsr TRANSFER_A
PLOT_140_2:
    lda MASK
    pha
    lda MASK2
    beq PLOT_140_4
    sta MASK
    cmp #$60                            ; a dot split across the group's first two bytes
    php
    bne PLOT_140_3
    dey
PLOT_140_3:
    txa
    jsr TRANSFER_B
    plp
    bne PLOT_140_4
    iny
PLOT_140_4:
    pla
    sta MASK
    rts

;; Writes bits of the current dot's byte, in the page <HALF> chooses, through the transfer mode.
;; In: A = the bits; only <MASK>'s count, Y = COLUMN
;; Uses: A
TRANSFER:
    bit HALF
    bmi TRANSFER_B

;; Writes bits of the current byte in the first page, through the transfer mode.
;; In: A = the bits; only MASK's count, Y = COLUMN
;; Uses: A
TRANSFER_A:
    bit DRAWFLAGS                       ; invert
    bpl TRANSFER_A_1
    eor MASK
TRANSFER_A_1:
    bit OPERATION                       ; store, OR, XOR or BIC
    bmi TRANSFER_A_5
    bvs TRANSFER_A_4
    eor (ROW_A),y
    and MASK
TRANSFER_A_2:
    eor (ROW_A),y
TRANSFER_A_3:
    sta (ROW_A),y
    rts
TRANSFER_A_4:
    ora (ROW_A),y
    bvs TRANSFER_A_3
TRANSFER_A_5:
    bvc TRANSFER_A_2
    eor #$FF
    eor MASK
    and (ROW_A),y
    bvs TRANSFER_A_3

;; Writes bits of the current byte in the second page, through the transfer mode.
;; In: A = the bits; only MASK's count, Y = COLUMN
;; Uses: A
TRANSFER_B:
    bit DRAWFLAGS
    bpl TRANSFER_B_1
    eor MASK
TRANSFER_B_1:
    bit OPERATION
    bmi TRANSFER_B_5
    bvs TRANSFER_B_4
    eor (ROW_B),y
    and MASK
TRANSFER_B_2:
    eor (ROW_B),y
TRANSFER_B_3:
    sta (ROW_B),y
    rts
TRANSFER_B_4:
    ora (ROW_B),y
    bvs TRANSFER_B_3
TRANSFER_B_5:
    bvc TRANSFER_B_2
    eor #$FF
    eor MASK
    and (ROW_B),y
    bvs TRANSFER_B_3

; ---------------------------------------------------------------------------------------------------------------------
; Reading dots
; ---------------------------------------------------------------------------------------------------------------------

;; Reads the color of the current dot.
;; Out: A = the color: 0 or 15 in the black and white modes, the foreground or background nibble in mode 1
;; Uses: X, Y
READ_PIXEL:
    ldy COLUMN
    ldx SCREENTYPE
    cpx #$03
    beq READ_140
    lda MASK
    bit HALF
    bmi READ_PIXEL_1
    and (ROW_A),y
    bcc READ_PIXEL_2
READ_PIXEL_1:
    and (ROW_B),y
READ_PIXEL_2:
    beq READ_PIXEL_3
    lda #$0F
READ_PIXEL_3:
    cpx #$01
    beq READ_PIXEL_4
    rts
READ_PIXEL_4:
    tax
    lda (ROW_B),y
    cpx #$00
    beq READ_PIXEL_5
    lsr a
    lsr a
    lsr a
    lsr a
READ_PIXEL_5:
    and #$0F
    rts

;; Mode 3: reads the current dot's four color bits from its two bytes.
;; In: Y = COLUMN
;; Out: A = the color
;; Uses: X, PAGEA_BITS
READ_140:
    lda (ROW_A),y
    and MASK
    sta PAGEA_BITS
    lda MASK2
    cmp #$60
    php
    bne READ_140_1
    dey
READ_140_1:
    and (ROW_B),y
    plp
    bne READ_140_2
    iny
READ_140_2:
    ldx PHASE
    inx
    bne READ_140_3
    lsr a
    lsr a
    lsr a
    rts
READ_140_3:
    inx
    bne READ_140_4
    rol PAGEA_BITS
    rol PAGEA_BITS
    rol a
    rts
READ_140_4:
    inx
    bne READ_140_5
    lda PAGEA_BITS
    lsr a
    lsr a
    rts
READ_140_5:
    inx
    bne READ_140_6
    rol a
    rol a
    rol PAGEA_BITS
    rol a
    rol PAGEA_BITS
    lda PAGEA_BITS
    rts
READ_140_6:
    inx
    bne READ_140_7
    lsr a
    rts
READ_140_7:
    inx
    bne READ_140_8
    asl PAGEA_BITS
    asl PAGEA_BITS
    rol a
    asl PAGEA_BITS
    rol a
    asl PAGEA_BITS
    rol a
    rts
READ_140_8:
    lda PAGEA_BITS
    rts

;; Mode 3: spreads a color over the current dot's bits of its two bytes.
;; In: A = the color, 0-15
;; Out: PAGEA_BITS = the bits for the first page's byte, A = those for the second's
;; Uses: X
SPLIT_140:
    ldx PHASE
    inx
    bne SPLIT_140_1
    stx PAGEA_BITS
    asl a
    asl a
    asl a
    rts
SPLIT_140_1:
    inx
    bne SPLIT_140_2
    lsr a
    tax
    lda #$00
    ror a
    ror a
    sta PAGEA_BITS
    txa
    rts
SPLIT_140_2:
    inx
    bne SPLIT_140_3
    asl a
    asl a
    sta PAGEA_BITS
    txa
    rts
SPLIT_140_3:
    inx
    bne SPLIT_140_4
    stx PAGEA_BITS
    lsr a
    ror PAGEA_BITS
    lsr a
    ror PAGEA_BITS
    lsr PAGEA_BITS
    tax
    lda PAGEA_BITS
    stx PAGEA_BITS
    rts
SPLIT_140_4:
    inx
    bne SPLIT_140_5
    asl a
    stx PAGEA_BITS
    rts
SPLIT_140_5:
    inx
    bne SPLIT_140_6
    stx PAGEA_BITS
    lsr a
    ror PAGEA_BITS
    lsr a
    ror PAGEA_BITS
    lsr a
    ror PAGEA_BITS
    lsr PAGEA_BITS
    rts
SPLIT_140_6:
    sta PAGEA_BITS
    lda #$00
    rts

; ---------------------------------------------------------------------------------------------------------------------
; The color operator table
; ---------------------------------------------------------------------------------------------------------------------

;; Black and white modes: the color operator table's result for the current dot.
;; In: Y = COLUMN
;; Out: A = the color to draw
;; Uses: X, SCRNCOLOR
OPERATE_BW:
    lda MASK
    bit HALF
    bmi OPERATE_BW_1
    and (ROW_A),y
    bpl OPERATE_BW_2
OPERATE_BW_1:
    and (ROW_B),y
OPERATE_BW_2:
    beq OPERATE
    lda #$0F
    bne OPERATE

;; Mode 1: the color operator table's result for one nibble of the current color byte.
;; In: carry = set for the background nibble, clear for the foreground, Y = COLUMN
;; Out: A = the color to write
;; Uses: X, SCRNCOLOR
OPERATE_COLOR280:
    lda (ROW_B),y
    bcs OPERATE_COLOR280_1
    lsr a
    lsr a
    lsr a
    lsr a
OPERATE_COLOR280_1:
    and #$0F
    bpl OPERATE

;; Mode 3: the color operator table's result for the current dot.
;; In: Y = COLUMN
;; Out: A = the color to draw
;; Uses: X, SCRNCOLOR, PAGEA_BITS
OPERATE_140:
    jsr READ_140

;; Looks up the color operator table for the pen color, or the fill color when USEFILL is $F0, over a screen color.
;; In: A = the screen color
;; Out: A = the color to draw
;; Uses: X, SCRNCOLOR
OPERATE:
    sta SCRNCOLOR
    lda USEFILL
    bpl OPERATE_1
    lda a:FILLCOLOR
    jmp OPERATE_2
OPERATE_1:
    lda a:PENCOLOR
OPERATE_2:
    asl a
    asl a
    asl a
    lsr SCRNCOLOR
    ora SCRNCOLOR
    tax
    lda a:COLORTABLE,x
    bcs OPERATE_3
    lsr a
    lsr a
    lsr a
    lsr a
OPERATE_3:
    and #$0F
    rts
