;; High-resolution graphics and shape statements ($F3D8-$F774).
;;
;; The graphics engine selects and clears pages, positions pixels, draws lines and processes rotated and scaled
;; shapes. BASIC statement handlers for coordinates, colors, plotting and shapes follow the drawing engine.
;; This module follows AppleSoft.AppleCommands.asm.

;; Group: High-resolution pixels and lines

;; Selects the full-screen second high-resolution page and clears it.
;; See: <HGR>, <HCLR>
HGR2:
    bit HISCR
    bit MIXCLR
    lda #$40
    bne HGR1

;; Selects mixed high-resolution graphics on the first page and clears it.
;; See: <HGR2>, <HCLR>
HGR:
    lda #$20
    bit LOWSCR
    bit MIXSET

HGR1:
    sta HPAG
    lda HIRES
    lda TXTCLR

;; Clears the selected high-resolution page to black.
HCLR:
    lda #0
    sta HCOLR2

;; Fills the selected high-resolution page using the pattern in <HCOLR2>.
;;
;; <LFTRT5> adjusts alternating byte patterns for the horizontal color phase.
BKGND:
    lda HPAG
    sta SHAPEH
    ldy #0
    sty SHAPEL

BKGND1:
    lda HCOLR2
    sta (SHAPEL),y
    jsr LFTRT5
    iny
    bne BKGND1
    inc SHAPEH
    lda SHAPEH
    and #$1F
    bne BKGND1
    rts

;; Positions the high-resolution graphics cursor at a pixel.
;;
;; It calculates the interleaved screen address in <GBASL>/<GBASH>, the byte index in <HNDX>, and the pixel mask
;; in <COLOR>. The current color pattern is adjusted for the byte's phase.
;; In: A = row, X = column low byte, Y = column high byte
;; Out: HGRX = column, HGRY = row, HNDX = byte index
HPOSN:
    sta HGRY
    stx HGRX
    sty HGRX+1
    pha
    and #$C0
    sta GBASL
    lsr a
    lsr a
    ora GBASL
    sta GBASL
    pla
    sta GBASH
    asl a
    asl a
    asl a
    rol GBASH
    asl a
    rol GBASH
    asl a
    ror GBASL
    lda GBASH
    and #$1F
    ora HPAG
    sta GBASH
    txa
    cpy #0
    beq HPOSN2
    ldy #$23
    adc #4

HPOSN1:
    iny

HPOSN2:
    sbc #7
    bcs HPOSN1
    sty HNDX
    tax
    lda MSKTBL-$F9,x                ; X is $F9-$FF after division by seven
    sta COLOR
    tya
    lsr a
    lda HCOLR1
    sta HCOLR2
    bcs LFTRT5
    rts

;; Positions and plots a single high-resolution pixel in the current color.
;; In: A = row, X = column low byte, Y = column high byte
HPLOT0:
    jsr HPOSN
    lda HCOLR2
    eor (GBASL),y
    and COLOR
    eor (GBASL),y
    sta (GBASL),y
    rts

;; Steps the high-resolution pixel mask horizontally, crossing byte boundaries when needed.
;;
;; The sign of A selects direction. On a byte crossing it adjusts <HNDX> and the phase of <HCOLR2>.
;; Entry: LFTRT5 = adjusts the color phase without moving the mask
LFTRT:
    bpl LFTRT7
    lda COLOR
    lsr a
    bcs LFTRT2
    eor #$C0

LFTRT1:
    sta COLOR
    rts

LFTRT2:
    dey
    bpl LFTRT3
    ldy #$27

LFTRT3:
    lda #$C0

LFTRT4:
    sta COLOR
    sty HNDX
    lda HCOLR2

LFTRT5:
    asl a
    cmp #$C0
    bpl LFTRT6
    lda HCOLR2
    eor #$7F
    sta HCOLR2

LFTRT6:
    rts

LFTRT7:
    lda COLOR
    asl a
    eor #$80
    bmi LFTRT1
    lda #$81
    iny
    cpy #$28
    bcc LFTRT4
    ldy #0
    bcs LFTRT4

;; Processes a shape step by XORing the pixel bits and counts initially clear pixels.
;;
;; The draw bit in <HGRDX>+1 determines whether to alter the pixel; the step's direction then selects <LFTRT>
;; or <UPDWN>. <XDRAW1> uses this operation.
DRWPNT:
    clc

DRWPN1:
    lda HGRDX+1
    and #4
    beq XDRPN3
    lda #$7F
    and COLOR
    and (GBASL),y
    bne XDRPN2
    inc COLCNT
    lda #$7F
    and COLOR
    bpl XDRPN2

;; Processes a shape step by replacing the masked pixel with the current color and counts matching pixels.
;;
;; <DRAW1> uses this operation. Both operations share the direction calculation.
XDRPNT:
    clc

XDRPN1:
    lda HGRDX+1
    and #4
    beq XDRPN3
    lda (GBASL),y
    eor HCOLR2
    and COLOR
    bne XDRPN2
    inc COLCNT

XDRPN2:
    eor (GBASL),y
    sta (GBASL),y

XDRPN3:
    lda HGRDX+1
    adc HGRQUA
; The immediate operand of the following instruction is also read as data.
MASK03 = * + 1
    and #3
    cmp #2
    ror a
    bcs LFTRT

;; Steps the high-resolution cursor vertically through the Apple's interleaved screen layout.
;;
;; It adjusts <GBASL>/<GBASH>; the sign of A selects direction. If the final rotation sets carry, the following
;; code resets the coordinates and falls into <HGLIN>.
UPDWN:
    bmi UPDWN7
    clc
    lda GBASH
    bit MASK1C
    bne UPDWN5
    asl GBASL
    bcs UPDWN3
    bit MASK03
    beq UPDWN1
    adc #$1F
    sec
    bcs UPDWN4

UPDWN1:
    adc #$23
    pha
    lda GBASL
    adc #$B0
    bcs UPDWN2
    adc #$F0

UPDWN2:
    sta GBASL
    pla
    bcs UPDWN4

UPDWN3:
    adc #$1F

UPDWN4:
    ror GBASL

UPDWN5:
    adc #$FC

UPDWN6:
    sta GBASH
    rts
    .byte $18                       ; unused byte between entry points

UPDWN7:
    lda GBASH
; The immediate operand of the following instruction is also read as data.
MASK04 = * + 1
    adc #4
    bit MASK1C
    bne UPDWN6
    asl GBASL
    bcc UPDWN9
    adc #$E0
    clc
    bit MASK04
    beq UPDW10
    lda GBASL
    adc #$50
    eor #$F0
    beq UPDWN8
    eor #$F0

UPDWN8:
    sta GBASL
    lda HPAG
    bcc UPDW10

UPDWN9:
    adc #$E0

UPDW10:
    ror GBASL
    bcc UPDWN6
    pha
    lda #0
    sta HGRX
    sta HGRX+1
    sta HGRY
    pla

;; Draws a high-resolution line from the current cursor to the supplied endpoint.
;;
;; It computes the deltas and direction, then steps horizontally or vertically while accumulating the line error.
;; In: A = column low byte, X = column high byte, Y = row
;; Out: HGRX = endpoint column, HGRY = endpoint row
HGLIN:
    pha
    sec
    sbc HGRX
    pha
    txa
    sbc HGRX+1
    sta HGRQUA
    bcs HGLIN1
    pla
    eor #$FF
    adc #1
    pha
    lda #0
    sbc HGRQUA

HGLIN1:
    sta HGRDX+1
    sta HGRE+1
    pla
    sta HGRDX
    sta HGRE
    pla
    sta HGRX
    stx HGRX+1
    tya
    clc
    sbc HGRY
    bcc HGLIN2
    eor #$FF
    adc #$FE

HGLIN2:
    sta HGRDY
    sty HGRY
    ror HGRQUA
    sec
    sbc HGRDX
    tax
    lda #$FF
    sbc HGRDX+1
    sta HCOUNT
    ldy HNDX
    bcs HGLIN4

HGLIN3:
    asl a
    jsr LFTRT
    sec

HGLIN4:
    lda HGRE
    adc HGRDY
    sta HGRE
    lda HGRE+1
    sbc #0

HGLIN5:
    sta HGRE+1
    lda (GBASL),y
    eor HCOLR2
    and COLOR
    eor (GBASL),y
    sta (GBASL),y
    inx
    bne HGLIN6
    inc HCOUNT
    beq HFIND3

HGLIN6:
    lda HGRQUA
    bcs HGLIN3
    jsr UPDWN
    clc
    lda HGRE
    adc HGRDX
    sta HGRE
    lda HGRE+1
    adc HGRDX+1
    bvc HGLIN5

;; Pixel masks for the seven high-resolution pixels in a screen byte, including the color-phase bit.
MSKTBL:
    .byte $81, $82, $84, $88, $90
    .byte $A0, $C0

;; Mask used in the vertical screen-address step.
MASK1C:
    .byte $1C

;; Fixed-point cosine magnitudes used to rotate shape vectors; the final byte belongs to the table.
COSTBL:
    .byte $FF, $FE, $FA, $F4, $EC
    .byte $E1, $D4, $C5, $B4, $A1
    .byte $8D, $78, $61, $49, $31
    .byte $18, $FF

;; Reconstructs the high-resolution cursor coordinates from the screen address, byte index and pixel mask.
;; Out: HGRX = column, HGRY = row
HFIND:
    lda GBASL
    asl a
    lda GBASH
    and #3
    rol a
    ora GBASL
    asl a
    asl a
    asl a
    sta HGRY
    lda GBASH
    lsr a
    lsr a
    and #7
    ora HGRY
    sta HGRY
    lda HNDX
    asl a
    adc HNDX
    asl a
    tax
    dex
    lda COLOR
    and #$7F

HFIND1:
    inx
    lsr a
    bne HFIND1
    sta HGRX+1
    txa
    clc
    adc HNDX
    bcc HFIND2
    inc HGRX+1

HFIND2:
    sta HGRX

HFIND3:
    rts

;; Group: Rotated and scaled shapes

;; Draws a shape using its address and rotation, starting at the current graphics cursor.
;;
;; Each shape byte holds direction/draw fields consumed three bits at a time, low bits first; a zero byte ends the
;; shape. The two error accumulators step through a rotated vector according to <COSTBL> and <HSCALE>.
;; <COLCNT> counts pixels that already match the color.
;; In: A = rotation, X = shape address low byte, Y = shape address high byte
;; Entry: DRAW1 = shape address is already in SHAPEL/SHAPEH
DRAW0:
    stx SHAPEL
    sty SHAPEH

DRAW1:
    tax
    lsr a
    lsr a
    lsr a
    lsr a
    sta HGRQUA
    txa
    and #$0F
    tax
    ldy COSTBL,x
    sty HGRDX
    eor #$0F
    tax
    ldy COSTBL+1,x
    iny
    sty HGRDY
    ldy HNDX
    ldx #0
    stx COLCNT
    lda (SHAPEL,x)

DRAW11:
    sta HGRDX+1
    ldx #$80
    stx HGRE
    stx HGRE+1
    ldx HSCALE

DRAW12:
    lda HGRE
    sec
    adc HGRDX
    sta HGRE
    bcc DRAW13
    jsr XDRPNT
    clc

DRAW13:
    lda HGRE+1
    adc HGRDY
    sta HGRE+1
    bcc DRAW14
    jsr XDRPN1

DRAW14:
    dex
    bne DRAW12
    lda HGRDX+1
    lsr a
    lsr a
    lsr a
    bne DRAW11
    inc SHAPEL
    bne DRAW15
    inc SHAPEH

DRAW15:
    lda (SHAPEL,x)
    bne DRAW11
    rts

;; XOR-draws a shape using its address and rotation at the current graphics cursor.
;;
;; Like <DRAW0>, it interprets a zero-terminated sequence of packed shape vectors. <COLCNT> counts initially
;; clear pixels; the pixel bits are toggled instead of replaced with <HCOLR2>.
;; In: A = rotation, X = shape address low byte, Y = shape address high byte
;; Entry: XDRAW1 = shape address is already in SHAPEL/SHAPEH
XDRAW0:
    stx SHAPEL
    sty SHAPEH

XDRAW1:
    tax
    lsr a
    lsr a
    lsr a
    lsr a
    sta HGRQUA
    txa
    and #$0F
    tax
    ldy COSTBL,x
    sty HGRDX
    eor #$0F
    tax
    ldy COSTBL+1,x
    iny
    sty HGRDY
    ldy HNDX
    ldx #0
    stx COLCNT
    lda (SHAPEL,x)

XDRAW2:
    sta HGRDX+1
    ldx #$80
    stx HGRE
    stx HGRE+1
    ldx HSCALE

XDRAW3:
    lda HGRE
    sec
    adc HGRDX
    sta HGRE
    bcc XDRAW4
    jsr DRWPNT
    clc

XDRAW4:
    lda HGRE+1
    adc HGRDY
    sta HGRE+1
    bcc XDRAW5
    jsr DRWPN1

XDRAW5:
    dex
    bne XDRAW3
    lda HGRDX+1
    lsr a
    lsr a
    lsr a
    bne XDRAW2
    inc SHAPEL
    bne XDRAW6
    inc SHAPEH

XDRAW6:
    lda (SHAPEL,x)
    bne XDRAW2
    rts

;; Group: High-resolution and shape statements

;; Reads a high-resolution coordinate pair from the BASIC text.
;; Out: X = column low byte, Y = column high byte, A = row
;; Errors: illegal quantity for a column above 279 or a row above 191
HFNS:
    jsr FRMNUM
    jsr GETADR
    ldy LINNUM+1
    ldx LINNUM
    cpy #1
    bcc HFNS1
    bne HFNS11
    cpx #$18
    bcs HFNS11

HFNS1:
    txa
    pha
    tya
    pha
    lda #','
    jsr SYNCHR
    jsr GETBYT
    cpx #$C0
    bcs HFNS11
    stx FACEXP
    pla
    tay
    pla
    tax
    lda FACEXP
    rts

HFNS11:
    jmp PLOTF1

;; Implements HCOLOR=, selecting one of eight patterns in <COLTBL>.
HCOLOR:
    jsr GETBYT
    cpx #8
    bcs HFNS11
    lda COLTBL,x
    sta HCOLR1

HCOLO1:
    rts

;; The eight high-resolution color byte patterns indexed by HCOLOR=.
COLTBL:
    .byte $00, $2A, $55, $7F, $80
    .byte $AA, $D5, $FF

;; Implements HPLOT and HPLOT TO for a point or a chain of lines.
;;
;; A leading TO continues from the current graphics cursor; otherwise the first coordinate is plotted.
HPLOT:
    cmp #TOTK
    beq HPLOT2
    jsr HFNS
    jsr HPLOT0

HPLOT1:
    jsr CHRGOT
    cmp #TOTK
    bne HCOLO1

HPLOT2:
    jsr SYNCHR
    jsr HFNS
    sty FACEXP
    tay
    txa
    ldx FACEXP
    jsr HGLIN
    jmp HPLOT1

;; Implements ROT=, storing the shape rotation in <HROT>.
ROT:
    jsr GETBYT
    stx HROT
    rts

;; Implements SCALE=, storing the shape scale in <HSCALE>.
SCALE:
    jsr GETBYT
    stx HSCALE
    rts

;; Reads a shape number and resolves its offset from <SHPTBL> into <SHAPEL>/<SHAPEH>.
;;
;; An optional AT coordinate positions the cursor. The table's first byte is the number of shapes; the two-byte
;; offsets are relative to the table. The returned A is the rotation.
;; Errors: illegal quantity for a shape number above the table count
SHNUM:
    jsr GETBYT
    lda SHPTBL
    sta SHAPEL
    lda SHPTBL+1
    sta SHAPEH
    txa
    ldx #0
    cmp (SHAPEL,x)
    beq SHNUM1
    bcs HFNS11

SHNUM1:
    asl a
    bcc SHNUM2
    inc SHAPEH
    clc

SHNUM2:
    tay
    lda (SHAPEL),y
    adc SHAPEL
    tax
    iny
    lda (SHAPEL),y
    adc SHPTBL+1
    sta SHAPEH
    stx SHAPEL
    jsr CHRGOT
    cmp #ATTK
    bne SHNUM3
    jsr SYNCHR
    jsr HFNS
    jsr HPOSN

SHNUM3:
    lda HROT
    rts

;; Implements DRAW using <SHNUM> and <DRAW1>.
DRAW:
    jsr SHNUM
    jmp DRAW1

;; Implements XDRAW using <SHNUM> and <XDRAW1>.
XDRAW:
    jsr SHNUM
    jmp XDRAW1
