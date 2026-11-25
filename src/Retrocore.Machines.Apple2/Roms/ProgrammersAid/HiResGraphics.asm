; retrocore: style=strict
;; Programmer's Aid #1: high-resolution graphics ($D000-$D3FF)
;;
;; Steve Wozniak's hi-res graphics routines (1977), which Integer BASIC programs CALL: INIT clears a page and shows
;; it with four lines of text below, and then PLOT, LINE, DRAW (a shape from a shape table, scaled and rotated) and
;; FIND (where the last point plotted is) draw on it. The screen is 280 dots across (`X0`, 0 to 279) by 192 down (`Y0`,
;; 0 to 191).
;;
;; The routines BASIC calls, from $D2F9 on (POSN, PLOT, LINE, DRAW and the others), take their parameters from BASIC's
;; first variables, in the order a program must define them: `X0`, `Y0`, `COLR`, `SHAPE`, `ROT` and `SCALE`. They read
;; each variable's value at a fixed offset from <LOMEM>, so a program starts with a line such as
;; `0 X0 = Y0 = COLR = SHAPE = ROT = SCALE`. The routines under them take theirs in the 6502's registers, for
;; machine-language programs: <HiResGraphics::Position>, <HiResGraphics::Plot>, <HiResGraphics::Line>,
;; <HiResGraphics::Draw> and <HiResGraphics::DrawInverted>.
;;
;; Colors are a byte of dots: 0 black, 42 green, 85 violet, 127 white, 128 black with the high bit, 170 orange, 213
;; blue and 255 white. Each screen byte shows 7 dots, bit 0 leftmost, and its bit 7 shifts them half a dot, which
;; picks between the two pairs of colors. <HiResGraphics::Page> picks the page drawn on: $20 for $2000-$3FFF, the
;; default, or $40 for $4000-$5FFF.
;;
;; The listing's names are those of Apple's listing in the Programmer's Aid #1 manual (1978,
;; https://archive.org/details/programmers-aid-1); its UP, DOWN and RTS1 are given in prose, as here they would clash
;; with the Monitor's UP and with Music's and the RAM test's names. Part of ProgrammersAid.asm, which includes it
;; first.

.scope HiResGraphics

; Page zero: SWEET16's R13 and R14, which the graphics borrow.

;; The shape table address the drawing routines walk (2 bytes): the shape being drawn, or the page being filled.
;; Also: SHAPEL (PA1)
ShapePointer = Sweet16Registers + 13 * SWEET16_REGISTER_SIZE

;; The high byte of <ShapePointer>.
;; Also: SHAPEH (PA1)
ShapePointerHigh = ShapePointer + 1

;; The color byte being plotted: <Color>, its alternating dots flipped for odd bytes so the color's dots fall on the
;; right columns.
;; Also: HCOLOR1 (PA1)
ShiftedColor = Sweet16Registers + 14 * SWEET16_REGISTER_SIZE

;; The count of dots <Line> has left to draw (2 bytes, counting up to 0), with X as its low byte.
;; Also: COUNTH (PA1)
CountHigh = ShiftedColor + 1

; Page zero: the Monitor's bytes, under the names the graphics give them.

;; The address of the screen line being drawn on (2 bytes), which <Position> sets: <LowResBase>'s bytes.
;; Also: HBASL (PA1)
LineBase = LowResBase

;; The high byte of <LineBase>.
;; Also: HBASH (PA1)
LineBaseHigh = LowResBaseHigh

;; The bit of the screen byte the next dot is in, with bit 7 set, so that a plot keeps the color's bit 7:
;; <PlotColor>'s byte.
;; Also: HMASK (PA1)
DotMask = PlotColor

; Page zero: the start of Integer BASIC's noun stack, which the graphics borrow.

;; The line's horizontal distance (2 bytes) for <Line>, and the step along the shape's direction for <Draw>.
;; Also: DXL (PA1)
DistanceX = NOUNSTKL

;; The high byte of <DistanceX>.
;; Also: DXH (PA1)
DistanceXHigh = NOUNSTKL + 1

;; The bits of the shape byte <Draw> has left to draw, three at a time: the same byte as <DistanceXHigh>.
;; Also: SHAPEX (PA1)
ShapeBits = NOUNSTKL + 1

;; The line's vertical distance for <Line>, and the step at right angles to the shape's direction for <Draw>.
;; Also: DY (PA1)
DistanceY = NOUNSTKL + 2

;; The direction: the quadrant of a shape's rotation, or which way a line goes.
;; Also: QDRNT (PA1)
Direction = NOUNSTKL + 3

;; The error term (2 bytes) <Line> and <Draw> step by.
;; Also: EL (PA1)
ErrorTerm = NOUNSTKL + 4

;; The high byte of <ErrorTerm>.
;; Also: EH (PA1)
ErrorTermHigh = NOUNSTKL + 5

; The graphics' own variables, in page 3.

;; The X coordinate (2 bytes) of the last point plotted or the end of the last line, where the next line starts.
;; Also: X0L (PA1)
LastX = $0320

;; The high byte of <LastX>.
;; Also: X0H (PA1)
LastXHigh = $0321

;; The Y coordinate of the last point plotted or the end of the last line.
;; Also: Y0 (PA1)
LastY = $0322

;; Where the routines BASIC calls keep X, which BASIC needs back.
;; Also: BXSAV (PA1)
KeptX = $0323

;; The color, as a byte of dots, that <Plot> and <Line> draw with.
;; Also: HCOLOR (PA1)
Color = $0324

;; The byte of the screen line the next dot is in, 0 to 39.
;; Also: HNDX (PA1)
ByteIndex = $0325

;; The page drawn on: $20 for $2000-$3FFF (the default) or $40 for $4000-$5FFF.
;; Also: HPAG (PA1)
Page = $0326

;; How many times <Draw> repeats each step of a shape: its scale.
;; Also: SCALE (PA1)
Scale = $0327

;; The shape table's address (2 bytes), which <LoadShapes> sets.
;; Also: SHAPXL (PA1)
ShapeTable = $0328

;; The high byte of <ShapeTable>.
;; Also: SHAPXH (PA1)
ShapeTableHigh = $0329

;; The collision count of <Draw> and <DrawInverted>: the dots <Draw> found already its color, and those
;; <DrawInverted> found dark on its steps along the direction and already the color on its steps at right angles.
;; Also: COLLSN (PA1)
Collisions = $032A

; The screen.

;; <Page>'s value for page 1, $2000-$3FFF.
PAGE_1 = $20

;; The bytes in a screen line.
BYTES_PER_LINE = 40

;; The dots in a screen byte.
DOTS_PER_BYTE = 7

;; The screen's height, in lines.
SCREEN_HEIGHT = 192

;; The screen's width, in dots: 280, $0118.
SCREEN_WIDTH = BYTES_PER_LINE * DOTS_PER_BYTE

; Where each BASIC variable's value is, from LOMEM: its name, the byte after it and the 2-byte link come first.

;; `X0`'s value, the first variable's: its low byte.
X0_VALUE = $05

;; `Y0`'s value, the second variable's: its high byte, which must be 0.
Y0_VALUE_HIGH = $0D

;; `COLR`'s value, the third variable's: its high byte.
COLR_VALUE_HIGH = $16

;; `SHAPE`'s value, the fourth variable's: its high byte.
SHAPE_VALUE_HIGH = $20

;; `ROT`'s value, the fifth variable's: its high byte.
ROT_VALUE_HIGH = $28

;; `SCALE`'s value, the sixth variable's: its high byte.
SCALE_VALUE_HIGH = $32

;; INIT (CALL -12288): shows hi-res page 1 with four lines of text below, and clears page 1 to black.
;; Out: Page = page 1
;; Keeps: X
;; Also: SETHRL (PA1)
.proc ShowAndClear
.assert * = $D000, "HiResGraphics::ShowAndClear must stay at $D000, CALL -12288."
    lda #PAGE_1
    sta Page
    lda HiResOn
    lda MixedOn
    lda TextOff
    ; Falls into Clear.
.endproc

;; CLEAR (CALL -12274): clears the page drawn on to black.
;; Keeps: X
;; Also: HCLR (PA1)
.proc Clear
.assert * = $D00E, "HiResGraphics::Clear must stay at $D00E, CALL -12274."
    lda #0
    ; Falls into Fill.
.endproc

;; Fills the page drawn on with the color in A, its alternating dots flipped in every other byte, as a line of the
;; color shows them.
;; In: A = the color
;; Keeps: X
;; Also: BKGND0 (PA1)
.proc Fill
    sta ShiftedColor

;; Also: BKGND (PA1)
FillPage:
    lda Page
    sta ShapePointerHigh
    ldy #0
    sty ShapePointer

;; Also: BKGND1 (PA1)
NextFillByte:
    lda ShiftedColor
    sta (ShapePointer),y
    jsr StepHorizontal::AlternateColor
    iny
    bne NextFillByte
    inc ShapePointerHigh

    ; Up to the page's end, the next multiple of $2000.
    lda ShapePointerHigh
    and #$1F
    bne NextFillByte
    rts
.endproc

;; Moves to a point without plotting: sets <LineBase>, <ByteIndex> and <DotMask> for it, and keeps it in <LastX> and
;; <LastY>.
;;
;; The line's address interleaves Y's bits as the screen does: Y's bits 6 and 7 pick a third of the page (40 bytes
;; apart in each $80), bits 3 to 5 the $80 block in each $400, and bits 0 to 2 the $400 block.
;; In: A = Y, X = X's low byte, Y = X's high byte
;; Out: ShiftedColor = <Color>, flipped for an odd byte, Y = the byte index
;; Entry:
;;   SetColor = sets <ShiftedColor> to A, flipped when carry is set, for an odd byte
;; Also: HPOSN (PA1)
.proc Position
    sta LastY
    stx LastX
    sty LastXHigh

    ; LineBase = the line's address from Y = ABCDEFGH: low byte EABAB000, high byte page + FGHCD.
    pha
    and #$C0
    sta LineBase
    lsr
    lsr
    ora LineBase
    sta LineBase
    pla
    sta LineBaseHigh
    asl
    asl
    asl
    rol LineBaseHigh
    asl
    rol LineBaseHigh
    asl
    ror LineBase
    lda LineBaseHigh
    and #$1F
    ora Page
    sta LineBaseHigh

    ; X divided by 7: Y = the byte, A = the remainder - 7, 249 to 255. Past 255, start from 256 = 36 x 7 + 4.
    txa
    cpy #0
    beq Divide
    ldy #36 - 1
    adc #4

;; Also: HPOSN1 (PA1)
NextByte:
    iny

;; Also: HPOSN2 (PA1)
Divide:
    sbc #DOTS_PER_BYTE
    bcs NextByte
    sty ByteIndex
    tax
    lda PixelMasks - (256 - DOTS_PER_BYTE),x
    sta DotMask

    ; An odd byte's colors are flipped.
    tya
    lsr
    lda Color

;; Sets <ShiftedColor> to A, flipped when carry is set.
;; Also: HPOSN3 (PA1)
SetColor:
    sta ShiftedColor
    bcs StepHorizontal::AlternateColor
    rts
.endproc

;; Plots a point in <Color>.
;; In: A = Y, X = X's low byte, Y = X's high byte
;; Entry:
;;   AtPosition = plots at the point <Position> set, with Y = its byte index
;; Also: HPLOT (PA1)
.proc Plot
    jsr Position

;; Sets the dot's bit in the screen byte to <ShiftedColor>'s.
;; Also: HPLOT1 (PA1)
AtPosition:
    lda ShiftedColor
    eor (LineBase),y
    and DotMask
    eor (LineBase),y
    sta (LineBase),y
    rts
.endproc

;; Moves the point one dot left or right, into the next byte at an edge of one, wrapping around the line.
;;
;; Apple's listing calls the return at Done RTS1.
;; In: negative = set for left, clear for right, Y = the byte index
;; Out: Y = the byte index, DotMask = the new dot's mask, ByteIndex = its byte, ShiftedColor = the color for that byte
;; Keeps: X
;; Entry:
;;   AlternateColor = flips the color in A, <ShiftedColor>, into <ShiftedColor> for the next byte when its dots
;;     alternate (green, violet, orange, blue); black and white stay
;; Also: LFTRT (PA1)
.proc StepHorizontal
    bpl Right

;; Also: LEFT (PA1)
Left:
    lda DotMask
    lsr
    bcs PreviousByte
    eor #$C0

;; Also: LR1 (PA1)
StoreMask:
    sta DotMask
    rts

;; Also: LEFT1 (PA1)
PreviousByte:
    dey
    bpl LastDot
    ldy #BYTES_PER_LINE - 1

;; The byte's last dot, bit 6, with bit 7 set.
;; Also: LEFT2 (PA1)
LastDot:
    lda #$C0

;; Also: NEWNDX (PA1)
NewByte:
    sta DotMask
    sty ByteIndex

;; Also: CSHIFT (PA1)
ShiftColor:
    lda ShiftedColor

;; Flips <ShiftedColor> for the next byte when the color's dots alternate: then A shifted left is $40 to $BF.
;; Also: CSHFT2 (PA1)
AlternateColor:
    asl
    cmp #$C0
    bpl Done
    lda ShiftedColor
    eor #$7F
    sta ShiftedColor

Done:
    rts

;; Also: RIGHT (PA1)
Right:
    lda DotMask
    asl
    eor #$80
    bmi StoreMask

    ; The byte's first dot, bit 0, with bit 7 set.
    lda #$81
    iny
    cpy #BYTES_PER_LINE
    bcc NewByte
    ldy #0
    bcs NewByte
.endproc

;; Takes one step of a shape for <DrawInverted>: inverts the dot first when the vector plots, counting it in
;; <Collisions> when it was dark; then moves the point one dot in the vector's direction.
;;
;; A shape's vectors are 3 bits each: bit 2 says to plot, and bits 0 and 1 are the direction, 0 up, 1 right, 2 down
;; and 3 left, to which <Direction>'s quadrant and the carry add. The carry is clear for the step along the
;; direction, and set for the step at right angles to it. Apple's listing calls the move up UP, and the move down DOWN;
;; nothing in Programmer's Aid enters DOWN.
;; In: ShapeBits = the vector in bits 0 to 2, Y = the byte index
;; Out: Y = the byte index
;; Keeps: X
;; Entry:
;;   Draw = the same for <Draw>: plots the dot in <ShiftedColor> when the vector plots, counting it in <Collisions>
;;     when it was already that color, then moves along the direction
;;   DrawTurned = <Draw>'s, with the carry set, which moves at right angles; <DrawInverted> uses it too, so its
;;     turned steps plot in the color instead of inverting
;;   UpOrDown = moves one line up, or down when negative is set and the carry clear, as <Line> steps
;; Also: LRUDX1 (PA1)
.proc Step
    clc

;; Also: LRUDX2 (PA1)
Invert:
    lda ShapeBits
    and #4
    beq Move
    lda #$7F
    and DotMask
    and (LineBase),y
    bne StoreDot
    inc Collisions
    lda #$7F
    and DotMask
    bpl StoreDot

;; Clears the carry for <Draw>'s step along the direction.
;; Also: LRUD1 (PA1)
Draw:
    clc

;; Plots the dot in <ShiftedColor> when the vector plots.
;; Also: LRUD2 (PA1)
DrawTurned:
    lda ShapeBits
    and #4
    beq Move
    lda (LineBase),y
    eor ShiftedColor
    and DotMask
    bne StoreDot
    inc Collisions

;; Also: LRUD3 (PA1)
StoreDot:
    eor (LineBase),y
    sta (LineBase),y

;; Moves the point in the vector's direction plus the quadrant and the carry: bit 0 picks left and right or up and
;; down, bit 1 which way.
;; Also: LRUD4 (PA1)
Move:
    lda ShapeBits
    adc Direction
    and #3

;; The byte 3, the operand above, which BIT tests for bits 0 and 1 of a line's high byte, its $100 block.
;; Also: EQ3 (PA1)
MaskBits0And1 = * - 1
    cmp #2
    ror

;; Also: LRUD (PA1)
MoveLeftOrRight:
    bcs StepHorizontal

;; Moves up, or down when negative is set.
;; Also: UPDWN (PA1)
UpOrDown:
    bmi DownFromA

;; Moves up a line. Apple's listing calls it UP.
Up:
    clc
    lda LineBaseHigh
    bit MaskBits2To4
    bne UpPlain
    asl LineBase
    bcs UpWrap
    bit MaskBits0And1
    beq UpInGroup
    adc #$1F
    sec
    bcs UpRotate

;; Also: UP1 (PA1)
UpInGroup:
    adc #$23
    pha
    lda LineBase
    adc #$B0
    bcs StoreUpLow
    adc #$F0

;; Also: UP5 (PA1)
StoreUpLow:
    sta LineBase
    pla
    bcs UpRotate

;; Also: UP2 (PA1)
UpWrap:
    adc #$1F

;; Also: UP3 (PA1)
UpRotate:
    ror LineBase

;; Also: UP4 (PA1)
UpPlain:
    adc #$FC

;; Also: UPDWN1 (PA1)
StoreHigh:
    sta LineBaseHigh
    rts

;; Moves down a line. Apple's listing calls it DOWN.
Down:
    clc

;; Moves down a line, with the carry clear.
;; Also: DOWN4 (PA1)
DownFromA:
    lda LineBaseHigh
    adc #4

;; The byte 4, the operand above, which BIT tests for bit 2.
;; Also: EQ4 (PA1)
MaskBit2 = * - 1
    bit MaskBits2To4
    bne StoreHigh
    asl LineBase
    bcc DownWrap
    adc #$E0
    clc
    bit MaskBit2
    beq DownRotate
    lda LineBase
    adc #$50
    eor #$F0
    beq StoreDownLow
    eor #$F0

;; Also: DOWN3 (PA1)
StoreDownLow:
    sta LineBase
    lda Page
    bcc DownRotate

;; Also: DOWN1 (PA1)
DownWrap:
    adc #$E0

;; Also: DOWN2 (PA1)
DownRotate:
    ror LineBase
    ; Always taken: the ASL above left bit 0 clear, and nothing since sets it.
    bcc StoreHigh
.endproc

;; Draws a line from the point <Position> or the last line left, as if it were (0,0), to the point that many dots from
;; it: <Line> with <LastX> and <LastY> cleared, which then hold the offset, not where the line ends.
;; In: A = the X offset's low byte, X = its high byte, Y = the Y offset
;; Also: HLINRL (PA1)
.proc LineFromOrigin
    pha
    lda #0
    sta LastX
    sta LastXHigh
    sta LastY
    pla
    ; Falls into Line.
.endproc

;; Draws a line in <Color> from the last point plotted (<LastX>, <LastY>) to a point, which becomes the last.
;;
;; It plots the dot it is at, then moves one dot, along X or up or down as the error term says, until it has plotted
;; |dx| + |dy| + 1 dots, both ends included; it ends through <FindCoordinates::Return>.
;; In: A = the X's low byte, X = its high byte, Y = the Y, ByteIndex = the last point's byte, LineBase = its line,
;;   DotMask = its mask, ShiftedColor = the color for its byte, as <Position> or the last line left them
;; Also: HLIN (PA1)
.proc Line
    pha
    sec
    sbc LastX
    pha
    txa
    sbc LastXHigh
    sta Direction
    bcs StoreDistanceX

    ; Leftward: the distance's magnitude.
    pla
    eor #$FF
    adc #1
    pha
    lda #0
    sbc Direction

;; Also: HLIN2 (PA1)
StoreDistanceX:
    sta DistanceXHigh
    sta ErrorTermHigh
    pla
    sta DistanceX
    sta ErrorTerm
    pla
    sta LastX
    stx LastXHigh
    tya
    clc
    sbc LastY
    bcc StoreDistanceY
    eor #$FF
    adc #$FE

;; DistanceY = -|the change in Y| - 1.
;; Also: HLIN3 (PA1)
StoreDistanceY:
    sta DistanceY
    sty LastY
    ror Direction
    sec
    sbc DistanceX
    tax
    lda #$FF
    sbc DistanceXHigh
    sta CountHigh
    ldy ByteIndex
    bcs StepY

;; Also: MOVEX (PA1)
MoveX:
    asl
    jsr StepHorizontal
    sec

;; Also: MOVEX2 (PA1)
StepY:
    lda ErrorTerm
    adc DistanceY
    sta ErrorTerm
    lda ErrorTermHigh
    sbc #0

;; Also: HCOUNT (PA1)
PlotDot:
    sta ErrorTermHigh
    lda (LineBase),y
    eor ShiftedColor
    and DotMask
    eor (LineBase),y
    sta (LineBase),y
    inx
    bne NextDot
    inc CountHigh
    beq FindCoordinates::Return

;; Also: HLIN4 (PA1)
NextDot:
    lda Direction
    bcs MoveX
    jsr Step::UpOrDown
    clc
    lda ErrorTerm
    adc DistanceX
    sta ErrorTerm
    lda ErrorTermHigh
    adc DistanceXHigh
    ; Always taken.
    bvc PlotDot
.endproc

;; Each dot's bit in a screen byte, from bit 0, the leftmost, to bit 6, with bit 7 set.
;; Also: MSKTBL (PA1)
PixelMasks:
    .byte $81, $82, $84, $88, $90, $A0, $C0
.assert * - PixelMasks = DOTS_PER_BYTE, "A mask for each of a byte's 7 dots."

;; The byte $1C, which BIT tests for bits 2 to 4 of a line's high byte, its $400 block.
;; Also: EQ1C (PA1)
MaskBits2To4:
    .byte $1C

;; The cosines of each 16th of a quarter turn, times 256: $FF for 0 down to $18, then $FF again. For a rotation n
;; 16ths into its quadrant, <Draw> takes the step along the direction from entry n, and the step at right angles from
;; entry 16 - n, plus 1, which makes it 0 for n = 0.
;; Also: COS (PA1)
Cosines:
    .byte $FF, $FE, $FA, $F4, $EC, $E1, $D4, $C5, $B4
    .byte $A1, $8D, $78, $61, $49, $31, $18, $FF
.assert * - Cosines = 17, "Sixteen steps of a quarter turn, and one more."

;; FIND (CALL -11780): works out the last point drawn from the screen position, and puts it in <LastX> and <LastY>,
;; where BASIC can read it.
;; Out: LastX/LastXHigh = X, LastY = Y
;; Keeps: Y
;; Also: HFIND (PA1)
.proc FindCoordinates
.assert * = $D1FC, "HiResGraphics::FindCoordinates must stay at $D1FC, CALL -11780."

    ; Y from the line's address, undoing <Position>'s interleave.
    lda LineBase
    asl
    lda LineBaseHigh
    and #3
    rol
    ora LineBase
    asl
    asl
    asl
    sta LastY
    lda LineBaseHigh
    lsr
    lsr
    and #7
    ora LastY
    sta LastY

    ; X = the byte index x 7, plus the dot's bit number.
    lda ByteIndex
    asl
    adc ByteIndex
    asl
    tax
    dex
    lda DotMask
    and #$7F

;; Also: HFIND1 (PA1)
CountBit:
    inx
    lsr
    bne CountBit
    sta LastXHigh
    txa
    clc
    adc ByteIndex
    bcc StoreX
    inc LastXHigh

;; Also: HFIND2 (PA1)
StoreX:
    sta LastX

;; Also: RTS2 (PA1)
Return:
    rts
.endproc

;; Draws a shape in <ShiftedColor>, rotated and scaled by <Scale>, at the point <Position> set, counting in
;; <Collisions> the dots already that color.
;;
;; Each byte of the shape holds up to three vectors, from bits 0 to 2 up; a byte of 0 ends it.
;; In: X = the shape's address, low byte, Y = its high byte, A = the rotation, 0 to 63 (16 is a quarter turn)
;; Also: DRAW (PA1)
.proc Draw
    stx ShapePointer
    sty ShapePointerHigh

;; Splits the rotation into its quadrant and the steps for its 16th of a quarter turn.
;; Also: DRAW1 (PA1)
Rotate:
    tax
    lsr
    lsr
    lsr
    lsr
    sta Direction
    txa
    and #$0F
    tax
    ldy Cosines,x
    sty DistanceX
    eor #$0F
    tax
    ldy Cosines + 1,x
    iny
    sty DistanceY

;; Also: DRAW2 (PA1)
Start:
    ldy ByteIndex
    ldx #0
    stx Collisions
    lda (ShapePointer,x)

;; Also: DRAW3 (PA1)
NextVector:
    sta ShapeBits
    ldx #$80
    stx ErrorTerm
    stx ErrorTermHigh
    ldx Scale

;; Takes the vector's steps, <Scale> times: along the direction when <ErrorTerm> carries, and at right angles when its
;; high byte does.
;; Also: DRAW4 (PA1)
Repeat:
    lda ErrorTerm
    sec
    adc DistanceX
    sta ErrorTerm
    bcc TurnedStep
    jsr Step::Draw
    clc

;; Also: DRAW5 (PA1)
TurnedStep:
    lda ErrorTermHigh
    adc DistanceY
    sta ErrorTermHigh
    bcc NextRepeat
    jsr Step::DrawTurned

;; Also: DRAW6 (PA1)
NextRepeat:
    dex
    bne Repeat
    lda ShapeBits
    lsr
    lsr
    lsr
    bne NextVector
    inc ShapePointer
    bne NextShapeByte
    inc ShapePointerHigh

;; Also: DRAW7 (PA1)
NextShapeByte:
    lda (ShapePointer,x)
    bne NextVector
    rts
.endproc

;; Draws a shape as <Draw> does, but inverts the dots of its steps along the direction instead of setting them, so
;; drawing it again erases those; its steps at right angles go through <Step::DrawTurned>, which sets them.
;; In: X = the shape's address, low byte, Y = its high byte, A = the rotation, 0 to 63 (16 is a quarter turn)
;; Also: XDRAW (PA1)
.proc DrawInverted
    stx ShapePointer
    sty ShapePointerHigh

;; Also: XDRAW1 (PA1)
Rotate:
    tax
    lsr
    lsr
    lsr
    lsr
    sta Direction
    txa
    and #$0F
    tax
    ldy Cosines,x
    sty DistanceX
    eor #$0F
    tax
    ldy Cosines + 1,x
    iny
    sty DistanceY

;; Also: XDRAW2 (PA1)
Start:
    ldy ByteIndex
    ldx #0
    stx Collisions
    lda (ShapePointer,x)

;; Also: XDRAW3 (PA1)
NextVector:
    sta ShapeBits
    ldx #$80
    stx ErrorTerm
    stx ErrorTermHigh
    ldx Scale

;; Also: XDRAW4 (PA1)
Repeat:
    lda ErrorTerm
    sec
    adc DistanceX
    sta ErrorTerm
    bcc TurnedStep
    jsr Step
    clc

;; Also: XDRAW5 (PA1)
TurnedStep:
    lda ErrorTermHigh
    adc DistanceY
    sta ErrorTermHigh
    bcc NextRepeat
    jsr Step::DrawTurned

;; Also: XDRAW6 (PA1)
NextRepeat:
    dex
    bne Repeat
    lda ShapeBits
    lsr
    lsr
    lsr
    bne NextVector
    inc ShapePointer
    bne NextShapeByte
    inc ShapePointerHigh

;; Also: XDRAW7 (PA1)
NextShapeByte:
    lda (ShapePointer,x)
    bne NextVector
    rts
.endproc

;; POSN (CALL -11527): moves to (`X0`, `Y0`) in the color `COLR` without plotting.
;; Out: Y = the byte index
;; Keeps: X
;; Also: BPOSN (PA1)
.proc BasicPosition
.assert * = $D2F9, "HiResGraphics::BasicPosition must stay at $D2F9, CALL -11527."
    jsr ReadColor
    sta Color
    jsr ReadY
    pha
    jsr ReadX
    pla
    jsr Position
    ldx KeptX
    rts
.endproc

;; PLOT (CALL -11506): plots (`X0`, `Y0`) in the color `COLR`.
;; Keeps: X
;; Also: BPLOT (PA1)
.proc BasicPlot
.assert * = $D30E, "HiResGraphics::BasicPlot must stay at $D30E, CALL -11506."
    jsr BasicPosition
    jmp Plot::AtPosition
.endproc

;; LINE (CALL -11500): draws a line in the color `COLR` from the last point to (`X0`, `Y0`).
;; Keeps: X
;; Also: BLIN1 (PA1)
.proc BasicLine
.assert * = $D314, "HiResGraphics::BasicLine must stay at $D314, CALL -11500."

    ; The color, flipped for the last point's byte when it is odd.
    lda ByteIndex
    lsr
    jsr ReadColor
    jsr Position::SetColor

;; Also: BLINE (PA1)
ToPoint:
    jsr ReadX
    txa
    pha
    tya
    tax
    jsr ReadY
    tay
    pla
    jsr Line
    ldx KeptX
    rts
.endproc

;; BKGND (CALL -11471): fills the page drawn on with the color `COLR`.
;; Keeps: X
;; Also: BGND (PA1)
.proc BasicFill
.assert * = $D331, "HiResGraphics::BasicFill must stay at $D331, CALL -11471."
    jsr ReadColor
    jmp Fill
.endproc

;; DRAW (CALL -11465): moves to (`X0`, `Y0`), then draws shape number `SHAPE` as <BasicDraw> does.
;; Keeps: X
;; Also: BDRAW1 (PA1)
.proc BasicMoveAndDraw
.assert * = $D337, "HiResGraphics::BasicMoveAndDraw must stay at $D337, CALL -11465."
    jsr BasicPosition
    ; Falls into BasicDraw.
.endproc

;; DRAW1 (CALL -11462): draws shape number `SHAPE` at the last point, rotated by `ROT` and scaled by `SCALE`.
;; Keeps: X
;; Also: BDRAW (PA1)
.proc BasicDraw
.assert * = $D33A, "HiResGraphics::BasicDraw must stay at $D33A, CALL -11462."
    jsr ShapeParameters
    jsr Draw
    ldx KeptX
    rts
.endproc

;; Moves to (`X0`, `Y0`), then draws shape number `SHAPE` as <BasicDrawInverted> does.
;; Keeps: X
;; Also: BXDRW1 (PA1)
.proc BasicMoveAndDrawInverted
    jsr BasicPosition
    ; Falls into BasicDrawInverted.
.endproc

;; Draws shape number `SHAPE` at the last point as <DrawInverted> does.
;; Keeps: X
;; Also: BXDRAW (PA1)
.proc BasicDrawInverted
    jsr ShapeParameters
    jsr DrawInverted
    ldx KeptX
    rts
.endproc

;; Reads the shape's parameters from BASIC's variables: sets <Scale> from `SCALE`, and finds shape number `SHAPE` in the
;; table at <ShapeTable>; RANGE ERR if a value is over 255, or the shape is 0 or past the table's count.
;; In: X = BASIC's X, which it keeps in <KeptX>
;; Out: A = the rotation, `ROT`, X = the shape's address, low byte, Y = its high byte
;; Also: BDRAWX (PA1)
.proc ShapeParameters
    stx KeptX
    ldy #SCALE_VALUE_HIGH
    jsr ReadByteVariable
    sta Scale
    ldy #ROT_VALUE_HIGH
    jsr ReadByteVariable
    pha
    lda ShapeTable
    sta ShapePointer
    lda ShapeTableHigh
    sta ShapePointerHigh
    ldy #SHAPE_VALUE_HIGH
    jsr ReadByteVariable
    beq ReadX::RangeError

    ; The table's first byte is its count of shapes.
    ldx #0
    cmp (ShapePointer,x)
    beq FindShape
    bcs ReadX::RangeError

;; The shape's offset is the table's word at 2 x its number.
;; Also: BDRWX1 (PA1)
FindShape:
    asl
    bcc ShapeAddress
    inc ShapePointerHigh
    clc

;; Also: BDRWX2 (PA1)
ShapeAddress:
    tay
    lda (ShapePointer),y
    adc ShapePointer
    tax
    iny
    lda (ShapePointer),y
    adc ShapeTableHigh
    tay
    pla
    rts
.endproc

;; Reads `COLR`, BASIC's third variable, as a byte; RANGE ERR if it is over 255.
;; Out: A = the color
;; Keeps: X
;; Also: PCOLR (PA1)
.proc ReadColor
    ldy #COLR_VALUE_HIGH
    ; Falls into ReadByteVariable.
.endproc

;; Reads a BASIC variable as a byte; RANGE ERR if it is over 255.
;; In: Y = the offset of its value's high byte from <LOMEM>
;; Out: A = the value, zero = set when it is 0
;; Keeps: X
;; Also: PBYTE (PA1)
.proc ReadByteVariable
    lda (LOMEM),y
    bne ReadX::RangeError
    dey
    lda (LOMEM),y

;; Also: RTSB (PA1)
Return:
    rts
.endproc

;; Reads `X0`, BASIC's first variable; RANGE ERR if it is over 279.
;; In: X = BASIC's X, which it keeps in <KeptX>
;; Out: X = its low byte, Y = its high byte
;; Entry:
;;   RangeError = Integer BASIC's RANGE ERR, for a BASIC variable out of range
;; Also: GETX0 (PA1)
.proc ReadX
    stx KeptX
    ldy #X0_VALUE
    lda (LOMEM),y
    tax
    iny
    lda (LOMEM),y
    tay

    ; Below 280: the compare's borrow with the high byte's.
    cpx #<SCREEN_WIDTH
    sbc #>SCREEN_WIDTH
    bcc ReadByteVariable::Return

;; Also: RERR1 (PA1)
RangeError:
    jmp RANGERR
.endproc

;; Reads `Y0`, BASIC's second variable; RANGE ERR if it is over 191.
;; Out: A = `Y0`
;; Keeps: X
;; Also: GETY0 (PA1)
.proc ReadY
    ldy #Y0_VALUE_HIGH
    jsr ReadByteVariable
    cmp #SCREEN_HEIGHT
    bcs ReadX::RangeError
    rts
.endproc

;; SHLOAD (CALL -11335): loads a shape table from tape to $0800, after a 2-byte length, and moves <LOMEM> above it;
;; MEM FULL if it would reach the program.
;; Out: ShapeTable/ShapeTableHigh = $0800
;; Keeps: X
;; Also: SHLOAD (PA1)
.proc LoadShapes
.assert * = $D3B9, "HiResGraphics::LoadShapes must stay at $D3B9, CALL -11335."

;; The page the shape table loads at.
SHAPE_TABLE_PAGE = $08

;; The header wait for the table, which follows the length on the tape: 3, where <ReadCassette> waits $16.
SHAPE_HEADER_DELAY = $03

    stx KeptX

    ; The length, as Integer BASIC's LOAD reads it.
    jsr SETHDR
    jsr ReadCassette

    ; A1 = $0800, A2 = $0800 + the length, which must stay below PP.
    lda #0
    sta Address1
    sta ShapeTable
    clc
    adc ACL
    tay
    lda #SHAPE_TABLE_PAGE
    sta Address1High
    sta ShapeTableHigh
    adc ACH
    bcs MemoryFull
    cpy PP
    pha
    sbc PPH
    pla
    bcs MemoryFull
    sty Address2
    sta Address2High

    ; LOMEM and PV = the byte after the table.
    iny
    bne SetLomem
    adc #1

;; Also: SHLOD1 (PA1)
SetLomem:
    sty LOMEM
    sta LOMEMH
    sty PV
    sta PVH
    jsr Cassette::ReadBit
    lda #SHAPE_HEADER_DELAY
    jsr ReadCassetteFromHeader
    ldx KeptX
    rts

;; Also: MFULL1 (PA1)
MemoryFull:
    jmp MEMFULL
.endproc

.endscope
