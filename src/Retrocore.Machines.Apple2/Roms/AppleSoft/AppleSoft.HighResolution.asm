; retrocore: style=strict
; APPLESOFT: HIGH-RESOLUTION GRAPHICS AND SHAPE STATEMENTS ($F3D8-$F774)
;
; The graphics engine, the scope HighRes, selects and clears pages, positions pixels, draws lines and draws rotated
; and scaled shapes. The statement handlers for coordinates, colors, plotting and shapes follow it. The engine borrows
; Monitor bytes: COLOR is its pixel mask, GBASL and GBASH the screen byte's address. This module follows
; AppleSoft.AppleCommands.asm.

;; The first high-resolution page's high byte.
HIGH_RES_PAGE1 = $20

;; The second high-resolution page's high byte.
HIGH_RES_PAGE2 = $40

;; Pixels in a screen byte.
PIXELS_PER_BYTE = 7

;; Screen bytes in a row.
HIGH_RES_ROW_BYTES = 40

;; High-resolution columns; a column must be below it.
HIGH_RES_COLUMNS = 280

;; High-resolution rows; a row must be below it.
HIGH_RES_ROWS = 192

;; The number of `HCOLOR=` colors.
HIGH_RES_COLORS = 8

;; The mask of a screen byte's first pixel, with the color-phase bit.
FIRST_PIXEL_MASK = $81

;; The mask of a screen byte's last pixel, with the color-phase bit.
LAST_PIXEL_MASK = $C0

;; A shape vector's plot bit, in its three bits.
SHAPE_PLOT_BIT = 4

; High-resolution pixels and lines

.scope Statements continued

;; `HGR2`: shows page 2 full screen and selects drawing page <HIGH_RES_PAGE2> through <HighRes::SelectPage>.
;; Also: HGR2 (ASTIL)
.proc HGr2
    bit HISCR
    bit MIXCLR
    lda #HIGH_RES_PAGE2
    bne HighRes::SelectPage
.endproc

;; `HGR`: shows page 1 mixed with text and falls into <HighRes::SelectPage> with page <HIGH_RES_PAGE1>.
;; Also: HGR (ASTIL)
.proc HGr
    lda #HIGH_RES_PAGE1
    bit LOWSCR
    bit MIXSET
    ; Falls into HighRes::SelectPage.
.endproc

.endscope

.scope HighRes

;; Stores the page's high byte in <HighResPage>, switches to high-resolution graphics, and falls into
;; <HighRes::Clear>.
;; In: A = the page's high byte
;; Also: HGR1 (UNKN)
.proc SelectPage
    sta HighResPage
    lda HIRES
    lda TXTCLR
    ; Falls into Clear.
.endproc

;; Sets <HighResColorByte> to black and falls into <HighRes::Fill>.
;; Also: HCLR (ASTIL)
.proc Clear
    lda #0
    sta HighResColorByte
    ; Falls into Fill.
.endproc

;; Fills the page <HighResPage> names with <HighResColorByte>, flipping its colored patterns for each byte's phase
;; through <HighRes::StepHorizontal::AdjustColor>.
;; Also: BKGND (ASTIL)
.proc Fill
    lda HighResPage
    sta ShapePointerHigh
    ldy #0
    sty ShapePointer

;; Stores the pattern, adjusts it for the next byte, and loops to the page's end.
;; Also: BKGND1 (UNKN)
NextByte:
    lda HighResColorByte
    sta (ShapePointer),y
    jsr StepHorizontal::AdjustColor
    iny
    bne NextByte
    inc ShapePointerHigh
    lda ShapePointerHigh
    and #$1F                        ; zero past the page's 8 KB
    bne NextByte
    rts
.endproc

;; Positions the cursor at a pixel: sets <GBASL> and <GBASH> to its row's address, <HighResByteIndex> to its byte, and
;; <COLOR> to its pixel mask, and puts <HighResColor> in phase for that byte in <HighResColorByte>.
;; In: A = the row, X = the column's low byte, Y = its high byte
;; Out: HighResX = the column, HighResY = the row, HighResByteIndex = the byte, Y = the byte
;; Also: HPOSN (ASTIL)
.proc Position
    sta HighResY
    stx HighResX
    sty HighResX+1
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
    ora HighResPage
    sta GBASH
    txa
    cpy #0
    beq Divide
    ldy #$23                        ; 256 is byte 36, pixel 4: Y counts on from 35
    adc #4

;; Counts one more byte in Y while dividing the column by seven.
;; Also: HPOSN1 (UNKN)
CountByte:
    iny

;; Subtracts seven until it borrows; the remainder indexes <HighRes::PixelMasks>.
;; Also: HPOSN2 (UNKN)
Divide:
    sbc #PIXELS_PER_BYTE
    bcs CountByte
    sty HighResByteIndex
    tax
    lda PixelMasks-$F9,x            ; X is $F9-$FF after the division
    sta COLOR
    tya
    lsr a
    lda HighResColor
    sta HighResColorByte
    bcs StepHorizontal::AdjustColor
    rts
.endproc

;; Positions the cursor and sets the pixel to <HighResColorByte> under the mask in <COLOR>. Apple's Technical
;; Information Library calls this entry HPLOT, the name the statement has.
;; In: A = the row, X = the column's low byte, Y = its high byte
;; Also: HPLOT0 (UNKN)
.proc Plot
    jsr Position
    lda HighResColorByte
    eor (GBASL),y
    and COLOR
    eor (GBASL),y
    sta (GBASL),y
    rts
.endproc

;; Moves the pixel mask in <COLOR> one pixel left (negative set) or right, changing <HighResByteIndex> and wrapping
;; within the row (0 to 39) rather than stopping at its edge.
;; In: negative = set to step left, as the caller's load or shift of the direction leaves it, Y = <HighResByteIndex>
;; Entry:
;;   AdjustColor = flips <HighResColorByte>'s color bits when the pattern alternates, so the color stays in phase in
;;     the next byte; <HighRes::Fill> calls it and <HighRes::Position> branches to it
;; Also: LFTRT (UNKN)
.proc StepHorizontal
    bpl Right
    lda COLOR
    lsr a
    bcs PreviousByte
    eor #$C0                        ; clears the phase bit the shift moved into bit 6, and sets bit 7

;; Stores the new mask in <COLOR> and returns.
;; Also: LFTRT1 (UNKN)
SetMask:
    sta COLOR
    rts

;; Steps <HighResByteIndex> back a byte, from 0 to 39.
;; Also: LFTRT2 (UNKN)
PreviousByte:
    dey
    bpl LastPixel
    ldy #HIGH_RES_ROW_BYTES-1

;; Loads the mask for the byte's last pixel.
;; Also: LFTRT3 (UNKN)
LastPixel:
    lda #LAST_PIXEL_MASK

;; Stores the mask and <HighResByteIndex> for the new byte, and falls into `AdjustColor` with <HighResColorByte>.
;; Also: LFTRT4 (UNKN)
NewByte:
    sta COLOR
    sty HighResByteIndex
    lda HighResColorByte

;; Flips <HighResColorByte>'s color bits when the pattern alternates.
;; Also: LFTRT5 (UNKN)
AdjustColor:
    asl a
    cmp #$C0
    bpl Done
    lda HighResColorByte
    eor #$7F                        ; the color bits
    sta HighResColorByte

;; Returns.
;; Also: LFTRT6 (UNKN)
Done:
    rts

;; Moves the mask right; past the byte's last pixel, takes the next byte's first, from 39 to 0.
;; Also: LFTRT7 (UNKN)
Right:
    lda COLOR
    asl a
    eor #$80
    bmi SetMask
    lda #FIRST_PIXEL_MASK
    iny
    cpy #HIGH_RES_ROW_BYTES
    bcc NewByte
    ldy #0
    bcs NewByte
.endproc

;; <HighRes::XorDrawShape>'s step: where the vector's plot bit is set, toggles the pixel, counting it in
;; <CollisionCount> where it was clear, then moves along the vector through <HighRes::PlotStep::Move>. The overlay's
;; DRWPNT is this XDRAW step, and its XDRPNT the DRAW step: the names are the wrong way round for this code.
;; In: HighResDeltaX+1 = the shape byte, its vector in the low three bits
;; Entry:
;;   Across = the same with carry set, so the move is a quarter turn from the vector; <HighRes::XorDrawShape> calls
;;     it
;; Also: DRWPNT (UNKN)
.proc XorStep
    clc

;; The same with carry set.
;; Also: DRWPN1 (UNKN)
Across:
    lda HighResDeltaX+1
    and #SHAPE_PLOT_BIT
    beq PlotStep::Move
    lda #$7F                        ; the pixel bits
    and COLOR
    and (GBASL),y
    bne PlotStep::WritePixel
    inc CollisionCount
    lda #$7F
    and COLOR
    bpl PlotStep::WritePixel
.endproc

;; <HighRes::DrawShape>'s step: where the plot bit is set, sets the pixel to <HighResColorByte>, counting it in
;; <CollisionCount> where it already matched, then moves along the vector and falls into <HighRes::StepVertical> for a
;; vertical move.
;; In: HighResDeltaX+1 = the shape byte, its vector in the low three bits
;; Entry:
;;   Across = the same with carry set, so the move is a quarter turn from the vector; <HighRes::DrawShape> calls it
;;   WritePixel = writes the masked change into the screen byte; <HighRes::XorStep> branches here
;;   Move = adds <HighResQuadrant> and carry to the vector's direction and steps horizontally or vertically;
;;     <HighRes::XorStep> branches here
;; Also: XDRPNT (UNKN)
.proc PlotStep
    clc

;; The same with carry set.
;; Also: XDRPN1 (UNKN)
Across:
    lda HighResDeltaX+1
    and #SHAPE_PLOT_BIT
    beq Move
    lda (GBASL),y
    eor HighResColorByte
    and COLOR
    bne WritePixel
    inc CollisionCount

;; Writes the masked change into the screen byte.
;; Also: XDRPN2 (UNKN)
WritePixel:
    eor (GBASL),y
    sta (GBASL),y

;; Adds <HighResQuadrant> and carry to the vector's direction and steps horizontally or, falling through, vertically.
;; Also: XDRPN3 (UNKN)
Move:
    lda HighResDeltaX+1
    adc HighResQuadrant

;; The `and`'s operand, 3, which <HighRes::StepVertical>'s `bit` also reads to test the high byte's bits 0 and 1.
;; Also: MASK03 (UNKN)
LowTwoBitsMask = * + 1
    and #3
    cmp #2
    ror a
    bcs StepHorizontal
    ; Falls into StepVertical.
.endproc

;; Moves the cursor's <GBASL> and <GBASH> one row up (negative clear) or down through the interleaved screen layout.
;;
;; The 10 bytes after its last `bcc` are unreachable: that branch is always taken, since the `asl` clears bit 0 of
;; <GBASL> and the `ror` moves it into carry. They would zero <HighResX> and <HighResY> and fall into
;; <HighRes::Line>, drawing a line from (0,0).
;; In: negative = set to step down, as the caller's load or shift of the direction leaves it
;; Also: UPDWN (UNKN)
.proc StepVertical
    bmi Down
    clc
    lda GBASH
    bit RowInGroupMask
    bne UpRow
    asl GBASL
    bcs UpGroup
    bit PlotStep::LowTwoBitsMask
    beq UpThird
    adc #$1F
    sec
    bcs UpRotate

;; Moving up out of a third of the screen: adjusts the high byte and moves <GBASL> back across the third.
;; Also: UPDWN1 (UNKN)
UpThird:
    adc #$23
    pha
    lda GBASL
    adc #$B0
    bcs UpThirdStore
    adc #$F0

;; Stores the adjusted <GBASL>.
;; Also: UPDWN2 (UNKN)
UpThirdStore:
    sta GBASL
    pla
    bcs UpRotate

;; Moving up into the previous group of eight rows, where the group bit was set.
;; Also: UPDWN3 (UNKN)
UpGroup:
    adc #$1F

;; Rotates the group bit back into <GBASL>.
;; Also: UPDWN4 (UNKN)
UpRotate:
    ror GBASL

;; Subtracts 4 from the high byte: the previous row in the group.
;; Also: UPDWN5 (UNKN)
UpRow:
    adc #$FC

;; Stores the high byte and returns.
;; Also: UPDWN6 (UNKN)
StoreHigh:
    sta GBASH
    rts
    .byte $18                       ; unused

;; Moving down: adds 4 to the high byte, the next row in the group, crossing groups and thirds when it overflows.
;; Also: UPDWN7 (UNKN)
Down:
    lda GBASH

;; The `adc`'s operand, 4, which the later `bit BitTwoMask` also reads to test bit 2 of the high byte.
;; Also: MASK04 (UNKN)
BitTwoMask = * + 1
    adc #4
    bit RowInGroupMask
    bne StoreHigh
    asl GBASL
    bcc DownGroup
    adc #$E0
    clc
    bit BitTwoMask
    beq DownRotate
    lda GBASL
    adc #$50
    eor #$F0
    beq DownThirdStore
    eor #$F0

;; Stores <GBASL> for the next third, or the page's top, and reloads <HighResPage>.
;; Also: UPDWN8 (UNKN)
DownThirdStore:
    sta GBASL
    lda HighResPage
    bcc DownRotate

;; Moving down into the next group, where the group bit was clear.
;; Also: UPDWN9 (UNKN)
DownGroup:
    adc #$E0

;; Rotates the group bit back into <GBASL>, then returns through `StoreHigh`.
;; Also: UPDW10 (UNKN)
DownRotate:
    ror GBASL
    bcc StoreHigh
    ; Unreachable: zeroes HighResX and HighResY and falls into Line.
    pha
    lda #0
    sta HighResX
    sta HighResX+1
    sta HighResY
    pla
    ; Falls into Line.
.endproc

;; Draws a line from the cursor to the point, stepping by the error term, and leaves the cursor there. Apple's
;; Technical Information Library calls this entry HLIN, the name the low-resolution statement has.
;; In: A = the column's low byte, X = its high byte, Y = the row
;; Out: HighResX = the column, HighResY = the row
;; Also: HGLIN (UNKN)
.proc Line
    pha
    sec
    sbc HighResX
    pha
    txa
    sbc HighResX+1
    sta HighResQuadrant
    bcs SetDeltaX
    pla
    eor #$FF
    adc #1
    pha
    lda #0
    sbc HighResQuadrant

;; Stores the column distance in <HighResDeltaX> and the error term in <HighResError>.
;; Also: HGLIN1 (UNKN)
SetDeltaX:
    sta HighResDeltaX+1
    sta HighResError+1
    pla
    sta HighResDeltaX
    sta HighResError
    pla
    sta HighResX
    stx HighResX+1
    tya
    clc
    sbc HighResY
    bcc SetDeltaY
    eor #$FF
    adc #$FE

;; Stores the row distance, negative, in <HighResDeltaY>, the new row, the directions in <HighResQuadrant>, and the
;; step count.
;; Also: HGLIN2 (UNKN)
SetDeltaY:
    sta HighResDeltaY
    sty HighResY
    ror HighResQuadrant
    sec
    sbc HighResDeltaX
    tax
    lda #$FF
    sbc HighResDeltaX+1
    sta HighResLineCount
    ldy HighResByteIndex
    bcs AddDeltaY

;; Steps horizontally through <HighRes::StepHorizontal>.
;; Also: HGLIN3 (UNKN)
Horizontal:
    asl a
    jsr StepHorizontal
    sec

;; Adds <HighResDeltaY> to the error term.
;; Also: HGLIN4 (UNKN)
AddDeltaY:
    lda HighResError
    adc HighResDeltaY
    sta HighResError
    lda HighResError+1
    sbc #0

;; Sets the pixel to <HighResColorByte> and counts the step, ending through <HighRes::FindCoordinates::Done>.
;; Also: HGLIN5 (UNKN)
PlotPoint:
    sta HighResError+1
    lda (GBASL),y
    eor HighResColorByte
    and COLOR
    eor (GBASL),y
    sta (GBASL),y
    inx
    bne ChooseStep
    inc HighResLineCount
    beq FindCoordinates::Done

;; Steps horizontally on carry, else vertically, then adds <HighResDeltaX> to the error term.
;; Also: HGLIN6 (UNKN)
ChooseStep:
    lda HighResQuadrant
    bcs Horizontal
    jsr StepVertical
    clc
    lda HighResError
    adc HighResDeltaX
    sta HighResError
    lda HighResError+1
    adc HighResDeltaX+1
    bvc PlotPoint
.endproc

;; The seven pixel masks of a screen byte, each with bit 7, the color-phase bit, set; <HighRes::Position> indexes it
;; from PixelMasks - $F9.
;; Also: MSKTBL (UNKN)
PixelMasks:
    .byte $81, $82, $84, $88, $90
    .byte $A0, $C0

;; The byte <HighRes::StepVertical>'s `bit` tests: the high byte's bits for the row within its group of eight.
;; Also: MASK1C (UNKN)
RowInGroupMask:
    .byte $1C

;; Sixteen fractions, the cosine at 0 to 84 degrees in steps of 90/16, that scale a rotated shape vector along and
;; across it, and a 17th byte, $FF, read as CosineTable+1,x for rotation 0, so that its `iny` makes the sine 0.
;; Also: COSTBL (UNKN)
CosineTable:
    .byte $FF, $FE, $FA, $F4, $EC
    .byte $E1, $D4, $C5, $B4, $A1
    .byte $8D, $78, $61, $49, $31
    .byte $18, $FF

;; Rebuilds <HighResX> and <HighResY> from <GBASL> and <GBASH>, <HighResByteIndex> and the pixel mask in <COLOR>.
;; Out: HighResX = the column, HighResY = the row
;; Entry:
;;   Done = returns; <HighRes::Line> branches here
;; Also: HFIND (ASTIL)
.proc FindCoordinates
    lda GBASL
    asl a
    lda GBASH
    and #3
    rol a
    ora GBASL
    asl a
    asl a
    asl a
    sta HighResY
    lda GBASH
    lsr a
    lsr a
    and #7
    ora HighResY
    sta HighResY
    lda HighResByteIndex
    asl a
    adc HighResByteIndex
    asl a
    tax
    dex
    lda COLOR
    and #$7F                        ; the pixel bits

;; Counts pixels in the column until the mask shifts out.
;; Also: HFIND1 (UNKN)
CountPixel:
    inx
    lsr a
    bne CountPixel
    sta HighResX+1
    txa
    clc
    adc HighResByteIndex
    bcc StoreColumn
    inc HighResX+1

;; Stores the column's low byte in <HighResX>.
;; Also: HFIND2 (UNKN)
StoreColumn:
    sta HighResX

;; Returns.
;; Also: HFIND3 (UNKN)
Done:
    rts
.endproc

; Rotated and scaled shapes

;; Stores the shape's address in <ShapePointer> and <ShapePointerHigh> and falls into <HighRes::DrawShape>. Apple's
;; Technical Information Library calls this entry DRAW, the name the statement has.
;; In: A = the rotation, X = the shape's address (low byte), Y = its high byte
;; Also: DRAW0 (UNKN)
.proc Draw
    stx ShapePointer
    sty ShapePointerHigh
    ; Falls into DrawShape.
.endproc

;; Draws the shape at <ShapePointer> with rotation A, <ShapeScale> steps per vector (256 for 0), through
;; <HighRes::PlotStep>; <CollisionCount> counts pixels that already had the color.
;;
;; Each shape byte holds vectors three bits at a time, low bits first; a zero byte ends the shape. The two error terms
;; step along and across a rotated vector by <HighRes::CosineTable>.
;; In: A = the rotation
;; Also: DRAW1 (UNKN)
.proc DrawShape
    tax
    lsr a
    lsr a
    lsr a
    lsr a
    sta HighResQuadrant
    txa
    and #$0F
    tax
    ldy CosineTable,x
    sty HighResDeltaX
    eor #$0F
    tax
    ldy CosineTable+1,x
    iny
    sty HighResDeltaY
    ldy HighResByteIndex
    ldx #0
    stx CollisionCount
    lda (ShapePointer,x)

;; Takes the next three-bit vector and starts its error terms and scale count.
;; Also: DRAW11 (UNKN)
NextVector:
    sta HighResDeltaX+1
    ldx #$80                        ; one half
    stx HighResError
    stx HighResError+1
    ldx ShapeScale

;; Adds the cosine to the first error term and steps along the vector on carry.
;; Also: DRAW12 (UNKN)
AlongStep:
    lda HighResError
    sec
    adc HighResDeltaX
    sta HighResError
    bcc AcrossStep
    jsr PlotStep
    clc

;; Adds the sine to the second error term and steps across the vector on carry.
;; Also: DRAW13 (UNKN)
AcrossStep:
    lda HighResError+1
    adc HighResDeltaY
    sta HighResError+1
    bcc CountScale
    jsr PlotStep::Across

;; Repeats for the scale, then shifts to the byte's next vector.
;; Also: DRAW14 (UNKN)
CountScale:
    dex
    bne AlongStep
    lda HighResDeltaX+1
    lsr a
    lsr a
    lsr a
    bne NextVector
    inc ShapePointer
    bne NextByte
    inc ShapePointerHigh

;; Reads the next shape byte; zero ends the shape.
;; Also: DRAW15 (UNKN)
NextByte:
    lda (ShapePointer,x)
    bne NextVector
    rts
.endproc

;; Stores the shape's address in <ShapePointer> and <ShapePointerHigh> and falls into <HighRes::XorDrawShape>.
;; Apple's Technical Information Library calls this entry XDRAW, the name the statement has.
;; In: A = the rotation, X = the shape's address (low byte), Y = its high byte
;; Also: XDRAW0 (UNKN)
.proc XorDraw
    stx ShapePointer
    sty ShapePointerHigh
    ; Falls into XorDrawShape.
.endproc

;; Toggles the shape at <ShapePointer> with rotation A, <ShapeScale> steps per vector (256 for 0), through
;; <HighRes::XorStep>; <CollisionCount> counts pixels that were clear before it toggled them.
;; In: A = the rotation
;; Also: XDRAW1 (UNKN)
.proc XorDrawShape
    tax
    lsr a
    lsr a
    lsr a
    lsr a
    sta HighResQuadrant
    txa
    and #$0F
    tax
    ldy CosineTable,x
    sty HighResDeltaX
    eor #$0F
    tax
    ldy CosineTable+1,x
    iny
    sty HighResDeltaY
    ldy HighResByteIndex
    ldx #0
    stx CollisionCount
    lda (ShapePointer,x)

;; Takes the next three-bit vector and starts its error terms and scale count.
;; Also: XDRAW2 (UNKN)
NextVector:
    sta HighResDeltaX+1
    ldx #$80                        ; one half
    stx HighResError
    stx HighResError+1
    ldx ShapeScale

;; Adds the cosine to the first error term and steps along the vector on carry.
;; Also: XDRAW3 (UNKN)
AlongStep:
    lda HighResError
    sec
    adc HighResDeltaX
    sta HighResError
    bcc AcrossStep
    jsr XorStep
    clc

;; Adds the sine to the second error term and steps across the vector on carry.
;; Also: XDRAW4 (UNKN)
AcrossStep:
    lda HighResError+1
    adc HighResDeltaY
    sta HighResError+1
    bcc CountScale
    jsr XorStep::Across

;; Repeats for the scale, then shifts to the byte's next vector.
;; Also: XDRAW5 (UNKN)
CountScale:
    dex
    bne AlongStep
    lda HighResDeltaX+1
    lsr a
    lsr a
    lsr a
    bne NextVector
    inc ShapePointer
    bne NextByte
    inc ShapePointerHigh

;; Reads the next shape byte; zero ends the shape.
;; Also: XDRAW6 (UNKN)
NextByte:
    lda (ShapePointer,x)
    bne NextVector
    rts
.endproc

.endscope

; High-resolution and shape statements

;; Reads a column below <HIGH_RES_COLUMNS> and, after a comma, a row below <HIGH_RES_ROWS>. The Technical Information
;; Library gives Y as the row's most significant byte; it is the column's high byte.
;; Out: X = the column's low byte, Y = its high byte, A = the row
;; Errors: ILLEGAL QUANTITY for a column above 279 or a row above 191
;; Also: HFNS (ASTIL)
.proc ReadHighResCoordinates
    jsr EvaluateNumber
    jsr ConvertToAddress
    ldy LineNumber+1
    ldx LineNumber
    cpy #>HIGH_RES_COLUMNS
    bcc ReadRow
    bne RejectHighResArgument
    cpx #<HIGH_RES_COLUMNS
    bcs RejectHighResArgument

;; Saves the column, requires a comma and reads the row.
;; Also: HFNS1 (UNKN)
ReadRow:
    txa
    pha
    tya
    pha
    lda #','
    jsr CheckCharacter
    jsr EvaluateByte
    cpx #HIGH_RES_ROWS
    bcs RejectHighResArgument
    stx FacExponent
    pla
    tay
    pla
    tax
    lda FacExponent
    rts
.endproc

;; Jumps on to <ToIllegalQuantity>, for out-of-range coordinates, colors and shape numbers.
;; Also: HFNS11 (UNKN)
.proc RejectHighResArgument
    jmp ToIllegalQuantity
.endproc

.scope Statements continued

;; `HCOLOR=`: reads the color and falls into <HighRes::SetColor>.
;; Also: HCOLOR (AS82)
.proc HColor
    jsr EvaluateByte
    ; Falls into HighRes::SetColor.
.endproc

.endscope

.scope HighRes continued

;; Stores the pattern of the color, below <HIGH_RES_COLORS>, from <HighRes::ColorPatterns> in <HighResColor>.
;; In: X = the color
;; Errors: ILLEGAL QUANTITY for a color of 8 or more
;; Entry:
;;   Done = returns; <Statements::HPlot> branches here
;; Also: SETHCOL (ASTIL)
.proc SetColor
    cpx #HIGH_RES_COLORS
    bcs RejectHighResArgument
    lda ColorPatterns,x
    sta HighResColor

;; Returns.
;; Also: HCOLO1 (UNKN)
Done:
    rts
.endproc

;; The byte patterns of the eight colors, by `HCOLOR=` number.
;; Also: COLTBL (UNKN)
ColorPatterns:
    .byte $00, $2A, $55, $7F, $80
    .byte $AA, $D5, $FF

.endscope

.scope Statements continued

;; `HPLOT`: plots the first point unless the statement starts with `TO`, then draws a line to each `TO` point. The
;; Technical Information Library's HPLOT is <HighRes::Plot>.
;; Also: HPLOT (UNKN)
.proc HPlot
    cmp #<TOKEN_TO
    beq LineTo
    jsr ReadHighResCoordinates
    jsr HighRes::Plot

;; Returns unless the next token is `TO`.
;; Also: HPLOT1 (UNKN)
NextTo:
    jsr GetCurrentCharacter
    cmp #<TOKEN_TO
    bne HighRes::SetColor::Done

;; Skips `TO`, reads the point and draws <HighRes::Line> to it.
;; Also: HPLOT2 (UNKN)
LineTo:
    jsr CheckCharacter
    jsr ReadHighResCoordinates
    sty FacExponent
    tay
    txa
    ldx FacExponent
    jsr HighRes::Line
    jmp NextTo
.endproc

;; `ROT=`: reads a byte into <ShapeRotation>, the shapes' rotation.
;; Also: ROT (AS82)
.proc Rot
    jsr EvaluateByte
    stx ShapeRotation
    rts
.endproc

;; `SCALE=`: reads a byte into <ShapeScale>, the shapes' scale.
;; Also: SCALE (UNKN)
.proc Scale
    jsr EvaluateByte
    stx ShapeScale
    rts
.endproc

;; Reads a shape number no larger than the table's count, points <ShapePointer> at that shape, positions the cursor
;; at an optional `AT` point, and returns the rotation. Shape number 0 is accepted: it reads the table's count byte
;; and the unused byte after it as an offset.
;; Out: A = <ShapeRotation>
;; Errors: ILLEGAL QUANTITY for a shape number above the table's count, or an `AT` point outside the screen
;; Also: SHNUM (UNKN)
.proc ReadShapeNumber
    jsr EvaluateByte
    lda ShapeTable
    sta ShapePointer
    lda ShapeTable+1
    sta ShapePointerHigh
    txa
    ldx #0
    cmp (ShapePointer,x)
    beq Index
    bcs RejectHighResArgument

;; Doubles the number for the offset's index, carrying into <ShapePointerHigh>.
;; Also: SHNUM1 (UNKN)
Index:
    asl a
    bcc AddOffset
    inc ShapePointerHigh
    clc

;; Adds the shape's offset to the table's address, then positions at `AT` if it is there.
;; Also: SHNUM2 (UNKN)
AddOffset:
    tay
    lda (ShapePointer),y
    adc ShapePointer
    tax
    iny
    lda (ShapePointer),y
    adc ShapeTable+1
    sta ShapePointerHigh
    stx ShapePointer
    jsr GetCurrentCharacter
    cmp #<TOKEN_AT
    bne Rotation
    jsr CheckCharacter
    jsr ReadHighResCoordinates
    jsr HighRes::Position

;; Loads <ShapeRotation> and returns.
;; Also: SHNUM3 (UNKN)
Rotation:
    lda ShapeRotation
    rts
.endproc

;; `DRAW`: reads the shape number and draws it through <HighRes::DrawShape>. The Technical Information Library's DRAW
;; is <HighRes::Draw>.
;; Also: DRAW (UNKN)
.proc Draw
    jsr ReadShapeNumber
    jmp HighRes::DrawShape
.endproc

;; `XDRAW`: reads the shape number and toggles it through <HighRes::XorDrawShape>. The Technical Information
;; Library's XDRAW is <HighRes::XorDraw>.
;; Also: XDRAW (UNKN)
.proc XDraw
    jsr ReadShapeNumber
    jmp HighRes::XorDrawShape
.endproc

.endscope
