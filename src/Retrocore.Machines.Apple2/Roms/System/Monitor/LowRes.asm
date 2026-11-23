; retrocore: style=strict
;; The Monitor's lo-res graphics routines, $F800-$F881: plotting blocks and lines, clearing the screen, the color,
;; and reading a block's color back.

;; The lo-res graphics routines, which share a row's base address calculation and their tails.
;;
;; The lo-res screen is text page one: each text line holds two rows of blocks, the even row in the low nibble of
;; each character and the odd row in the high nibble, so a block's color is a number from 0 to 15. <COLOR> holds the
;; current color in both nibbles, and <GBASL>/<GBASH> the address of the line being drawn on.
.scope LowRes

; The screen's size.

;; The rows of lo-res blocks on the full screen.
ROWS = 48

;; The rows above the four text lines of the mixed graphics and text screen.
MIXED_ROWS = 40

;; The columns of lo-res blocks.
COLUMNS = 40

; A text line's bytes.

;; The nibble of a screen byte that holds the even row's block, and the mask that keeps a color number.
LOW_NIBBLE = $0F

;; The nibble of a screen byte that holds the odd row's block.
HIGH_NIBBLE = $F0

;; Bits 1-2 of a text line's number, shifted down one: which of the screen's four pages of $100 bytes holds it.
PAGE_OF_LINE = $03

;; Bits 3-4 of a text line's number: which third of the screen, lines 0-7, 8-15 or 16-23, holds it.
THIRD_OF_LINE = $18

;; Where an odd text line starts in its page, after the even line before it.
ODD_LINE_OFFSET = $80

; Colors.

;; What <NextColor> adds to the color number.
COLOR_STEP = 3

;; Plots one lo-res block in the current color.
;;
;; At $F800.
;; In: A = the row (0-47), Y = the column (0-39), COLOR = the color in both nibbles
;; Out: carry = clear, GBASL/GBASH = the base address of the row's text line, MASK = the row's nibble of a byte
;; Keeps: X, Y
;; Entry:
;;   SameRow = plots a block in the row the last <Plot> set up, at another column
;; Also: PLOT (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc Plot
.assert * = $F800, "Plot must stay at $F800."

    ; The text line holds the row and the one after it; carry says which of the two it is.
    lsr a
    php
    jsr RowAddress
    plp

    ; An even row is the low nibble of the text byte, an odd row the high nibble.
    lda #LOW_NIBBLE
    bcc SetMask
    adc #HIGH_NIBBLE - LOW_NIBBLE - 1   ; carry is set

;; Stores the nibble mask for the row's half of each byte.
;; Also: RTMASK (A2RM78, A2RM79, IIEROM82, IIETRM85)
SetMask:
    sta MASK

;; Plots a block in the row the last <Plot> set up, at another column.
;;
;; At $F80E.
;; In: Y = the column (0-39), GBASL/GBASH = as <Plot> left them, MASK = as <Plot> left it,
;;   COLOR = the color in both nibbles
;; Keeps: X, Y, carry
;; Also: PLOT1 (A2RM78, A2RM79, IIEROM82)
SameRow:
.assert * = $F80E, "Plot::SameRow must stay at $F80E."

    ; Changes only the bits of the row's nibble to the color's.
    lda (GBASL),y
    eor COLOR
    and MASK
    eor (GBASL),y
    sta (GBASL),y
    rts
.endproc

;; Draws a horizontal lo-res line in the current color.
;;
;; At $F819. A line whose right end is left of its start plots only the start.
;; In: A = the row (0-47), Y = the leftmost column, H2 = the rightmost column, COLOR = the color in both nibbles
;; Out: Y = H2 (when it is right of the start), carry = set
;; Keeps: X
;; Also: HLINE (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc HorizontalLine
.assert * = $F819, "HorizontalLine must stay at $F819."
    jsr Plot

;; Plots the next column, until the rightmost.
;; Also: HLINE1 (A2RM78, A2RM79, IIEROM82)
Loop:
    cpy H2
    bcs VerticalLine::Done
    iny
    jsr Plot::SameRow
    bcc Loop                        ; always: the cpy above left carry clear, and SameRow keeps it
.endproc

;; The next row of <VerticalLine>'s line, which goes on into it; two bytes before its entry.
;;
;; In: A = the row just plotted, carry = clear
;; Also: VLINEZ (A2RM78, A2RM79, IIEROM82, IIETRM85)
NextVerticalRow:
    adc #1
    ; Falls into VerticalLine.

;; Draws a vertical lo-res line in the current color.
;;
;; At $F828. A line whose bottom is above its top plots only the top.
;; In: A = the top row, Y = the column (0-39), V2 = the bottom row, COLOR = the color in both nibbles
;; Out: A = V2 (when it is below the top), carry = set
;; Keeps: X, Y
;; Entry:
;;   Done = the return the lo-res lines share: <HorizontalLine> ends here too
;; Also: VLINE (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc VerticalLine
.assert * = $F828, "VerticalLine must stay at $F828."
    pha
    jsr Plot
    pla

    ; The next row, until the bottom one.
    cmp V2
    bcc NextVerticalRow

;; The return the lo-res lines share: <HorizontalLine> ends here too.
;; Also: RTS1 (A2RM78, A2RM79, IIEROM82, IIETRM85)
Done:
    rts
.endproc

;; Clears the whole lo-res screen, all 48 rows, to black.
;;
;; At $F832.
;; Out: COLOR = 0, V2 = 47, Y = $FF
;; Keeps: X
;; Also: CLRSCR (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc Clear
.assert * = $F832, "Clear must stay at $F832."
    ldy #ROWS - 1
    bne ClearTop::Rows              ; always
.endproc

;; Clears the top 40 lo-res rows to black, leaving the mixed screen's four text lines.
;;
;; At $F836.
;; Out: COLOR = 0, V2 = 39, Y = $FF
;; Keeps: X
;; Entry:
;;   Rows = clears rows 0 to Y to black, a column at a time; <Clear> enters here
;; Also: CLRTOP (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc ClearTop
.assert * = $F836, "ClearTop must stay at $F836."
    ldy #MIXED_ROWS - 1

;; Clears rows 0 to Y to black, a column at a time; <Clear> enters here.
;;
;; In: Y = the bottom row
;; Out: COLOR = 0, V2 = the bottom row, Y = $FF
;; Keeps: X
;; Also: CLRSC2 (A2RM78, A2RM79, IIEROM82, IIETRM85)
Rows:
    sty V2
    ldy #COLUMNS - 1

;; Draws one column's line in black, from the right edge to the left.
;; Also: CLRSC3 (A2RM78, A2RM79, IIEROM82, IIETRM85)
NextColumn:
    lda #0
    sta COLOR
    jsr VerticalLine
    dey
    bpl NextColumn
    rts
.endproc

;; Computes the base address of a text line on page one, for the lo-res routines.
;;
;; At $F847. <Plot> and <ReadColor> pass the row's line, half the row. A line's address is $400, plus
;; $80 for an odd line, $100 for each pair of lines in a group of eight, and $28 for each group of eight.
;; In: A = the text line (0-23)
;; Out: GBASL/GBASH = the line's base address, A = <GBASL>
;; Keeps: X, Y
;; Also: GBASCALC (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc RowAddress
.assert * = $F847, "RowAddress must stay at $F847."

    ; The high byte: page one's, plus the line's bits 1-2; carry = bit 0, whether the line is odd.
    pha
    lsr a
    and #PAGE_OF_LINE
    ora #>LINE1
    sta GBASH

    ; The low byte: the third times $28, plus $80 for an odd line.
    pla
    and #THIRD_OF_LINE
    bcc StoreLow
    adc #ODD_LINE_OFFSET - 1        ; carry is set

;; Adds four times the third, which makes it times $28 with the eight already there; the odd line's $80 shifts out.
;; Also: GBCALC (A2RM78, A2RM79, IIEROM82, IIETRM85)
StoreLow:
    sta GBASL
    asl a
    asl a
    ora GBASL
    sta GBASL
    rts
.endproc

;; Changes the lo-res color to the color number three higher, wrapping past 15 (so 15 becomes 2).
;;
;; At $F85F.
;; In: COLOR = the color in both nibbles
;; Out: COLOR = the next color in both nibbles, A = the same
;; Keeps: X, Y
;; Also: NXTCOL (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc NextColor
.assert * = $F85F, "NextColor must stay at $F85F."
    lda COLOR
    clc
    adc #COLOR_STEP
    ; Falls into SetColor, which keeps the low nibble.
.endproc

;; Sets the lo-res color.
;;
;; At $F864.
;; In: A = the color number (0-15; the high nibble is ignored)
;; Out: COLOR = the color in both nibbles, A = the same
;; Keeps: X, Y
;; Also: SETCOL (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc SetColor
.assert * = $F864, "SetColor must stay at $F864."
    and #LOW_NIBBLE
    sta COLOR
    asl a
    asl a
    asl a
    asl a
    ora COLOR
    sta COLOR
    rts
.endproc

;; Reads the color of one lo-res block.
;;
;; At $F871.
;; In: A = the row (0-47), Y = the column (0-39)
;; Out: A = the color number (0-15), GBASL/GBASH = the base address of the row's text line
;; Keeps: X, Y
;; Entry:
;;   Nibble = takes the high or low nibble of a byte; <Disassembler::Decode> uses it too
;; Also: SCRN (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc ReadColor
.assert * = $F871, "ReadColor must stay at $F871."
    lsr a
    php
    jsr RowAddress
    lda (GBASL),y
    plp

;; Takes the high or low nibble of a byte; the disassembler's <Disassembler::Decode> uses it too.
;;
;; In: A = the byte, carry = set for the high nibble, clear for the low
;; Out: A = the nibble (0-15), zero = set when it is 0
;; Keeps: X, Y
;; Also: SCRN2 (A2RM78, A2RM79, IIEROM82, IIETRM85)
Nibble:
    bcc LowNibble
    lsr a
    lsr a
    lsr a
    lsr a

;; Keeps the low nibble.
;; Also: RTMSKZ (A2RM78, A2RM79, IIEROM82, IIETRM85)
LowNibble:
    and #LOW_NIBBLE
    rts
.endproc

.endscope
