;; THE DISPLAY HANDLER'S AND SCREEN EDITOR'S SHARED ROUTINES ($F913-$FCFB)
;;
;; Reserving screen memory and building the display list below RAMTOP; finding the screen address and pixel mask of
;; the cursor; checking the cursor's range; moving it on a column or a line, with the scrolling and line insertion
;; that writing past a line's end needs; the bit map that TABMAP and LOGMAP make together; moving, clearing and
;; scrolling lines; converting the internal character code to ATASCII; the measure of a logical line for the
;; editor's input; swapping in the split screen's text window; the click of the keyboard and the bell.
;;
;; The display handler's tables are in Tables.asm.

; The text screen's shape.

SCREEN_LAST_COLUMN = 39             ;; the last column of a text line, the largest RMARGN
SCREEN_LOGMAP_BIT = 120             ;; the number of LOGMAP's first bit, row 0, after TABMAP's 120 bits
SCREEN_PIXEL_MODE = 3               ;; GRAPHICS 3, the first mode whose screen holds pixels rather than characters
SCREEN_WIDE_MODE = 8                ;; GRAPHICS 8, the first mode whose columns can need two bytes

;; Reserves two bytes below ADRESS, for the address of the display list's closing JVB, which is written later.
;; Out: ADRESS = two bytes lower
;; Uses: A, SUBTMP
;; Keeps: X, Y
;; Errors: DSTAT = SCRMEM when the room reaches APPMHI
;; See: <SCREEN_RESERVE>
SCREEN_RESERVE_2:
    lda #2
    bne SCREEN_RESERVE                  ; always

;; Puts a byte of the display list, which is built downward from its end, and moves ADRESS down past it.
;;
;; Once DSTAT holds an error, it does nothing.
;; In: A = the byte, ADRESS = where it goes
;; Out: ADRESS = one byte lower
;; Uses: A, Y, SUBTMP
;; Keeps: X
;; Errors: DSTAT = SCRMEM when the room reaches APPMHI
;; See: <SCREEN_RESERVE>
SCREEN_PUT_BYTE:
    ldy DSTAT
    bmi SCREEN_RESERVE_DONE             ; an error already
    ldy #0
    sta (ADRESS),y

;; Reserves a byte below ADRESS.
;; Out: ADRESS = one byte lower
;; Uses: A, SUBTMP
;; Keeps: X, Y
;; Errors: DSTAT = SCRMEM when the room reaches APPMHI
;; See: <SCREEN_RESERVE>
SCREEN_RESERVE_1:
    lda #1

;; Moves ADRESS down by A bytes, reserving them for the screen or its display list, and checks that it stays above
;; APPMHI, the top of the application's memory.
;;
;; The screen's open reserves memory downward from RAMTOP with it. Once DSTAT holds an error, it does nothing.
;; In: A = the number of bytes, ADRESS = the lowest byte reserved so far
;; Out: ADRESS = A bytes lower
;; Uses: A, SUBTMP
;; Keeps: X, Y
;; Errors: DSTAT = SCRMEM when ADRESS is at or below APPMHI
SCREEN_RESERVE:
    sta SUBTMP
    lda DSTAT
    bmi SCREEN_RESERVE_DONE             ; an error already
    lda ADRESS
    sec
    sbc SUBTMP
    sta ADRESS
    bcs SCREEN_RESERVE_CHECK
    dec ADRESS+1
SCREEN_RESERVE_CHECK:
    lda APPMHI+1
    cmp ADRESS+1
    bcc SCREEN_RESERVE_DONE             ; still above APPMHI
    bne SCREEN_RESERVE_FULL
    lda APPMHI
    cmp ADRESS
    bcc SCREEN_RESERVE_DONE
SCREEN_RESERVE_FULL:
    lda #SCRMEM
    sta DSTAT
SCREEN_RESERVE_DONE:
    rts

;; Finds the screen address of the cursor's byte, and the mask of its pixel or character in that byte.
;;
;; The address is SAVMSC plus ROWCRS times the line's length, which is 10 shifted left by <MODE_LINE_SHIFTS>, plus
;; COLCRS shifted right by <MODE_PIXEL_SHIFTS>. The bits shifted out are the pixel's place in the byte, which picks
;; its mask in <PIXEL_MASKS>.
;; In: ROWCRS, COLCRS = the cursor, DINDEX = the display mode
;; Out:
;;   ADRESS = the byte's address
;;   OLDADR = the same
;;   Y      = 0
;;   DMASK  = the pixel's mask in the byte
;;   SHFAMT = the same mask, which callers shift right until its low bit leaves, to count the pixel's shift
;; Uses: A, X, TOADR, HOLD1, HOLD2, TMPLBT
;; Keeps: ROWCRS, COLCRS
SCREEN_LOCATE:
    lda ROWCRS
    pha
    lda COLCRS
    pha
    lda COLCRS+1
    pha
    jsr SCREEN_TOP_ADDRESS
    lda ROWCRS                          ; the row times 10: twice, plus eight times
    sta TOADR
    lda #0
    sta TOADR+1
    lda TOADR
    asl a
    rol TOADR+1
    sta HOLD1                           ; the row times 2
    ldy TOADR+1
    sty HOLD2
    asl a
    rol TOADR+1
    asl a
    rol TOADR+1                         ; times 8
    clc
    adc HOLD1
    sta TOADR
    lda TOADR+1
    adc HOLD2
    sta TOADR+1
    ldx DINDEX
    ldy MODE_LINE_SHIFTS,x
SCREEN_LOCATE_ROWS:
    dey                                 ; then times the line's length over 10
    bmi SCREEN_LOCATE_COLUMN
    asl TOADR
    rol TOADR+1
    jmp SCREEN_LOCATE_ROWS
SCREEN_LOCATE_COLUMN:
    ldy MODE_PIXEL_SHIFTS,x
    lda COLCRS
    ldx #7
SCREEN_LOCATE_SHIFT:
    dey                                 ; the column over the pixels a byte
    bmi SCREEN_LOCATE_ADD
    dex
    lsr COLCRS+1
    ror a
    ror TMPLBT                          ; the pixel's place, into the top of TMPLBT
    jmp SCREEN_LOCATE_SHIFT
SCREEN_LOCATE_ADD:
    iny
    clc
    adc TOADR
    sta TOADR
    bcc SCREEN_LOCATE_MASK
    inc TOADR+1
SCREEN_LOCATE_MASK:
    sec                                 ; a 1 above the place, for the pixels a byte
SCREEN_LOCATE_MASK_SHIFT:
    ror TMPLBT                          ; down to the bottom: the index into PIXEL_MASKS
    clc
    dex
    bpl SCREEN_LOCATE_MASK_SHIFT
    ldx TMPLBT
    lda TOADR
    clc
    adc ADRESS
    sta ADRESS
    sta OLDADR
    lda TOADR+1
    adc ADRESS+1
    sta ADRESS+1
    sta OLDADR+1
    lda PIXEL_MASKS,x
    sta DMASK
    sta SHFAMT
    pla
    sta COLCRS+1
    pla
    sta COLCRS
    pla
    sta ROWCRS
    rts

;; Moves the cursor on one column without changing the screen, wrapping to the next line at the right margin.
;;
;; INSDAT = 0 says the cursor is only moving: it neither scrolls nor extends a logical line.
;; Out: INSDAT = 0, LOGCOL = the cursor's column in its logical line
;; Uses: A, X, Y, HOLD1, HOLD3, BITMSK, ADRESS
;; See: <SCREEN_ADVANCE_KEEP>
SCREEN_ADVANCE:
    lda #0
    beq SCREEN_ADVANCE_1                ; always

;; Moves the cursor on one column after writing a character, wrapping to the next line at the right margin.
;;
;; INSDAT = EOL says a character was written: at the bottom the screen scrolls, and a full logical line ends.
;; Out: INSDAT = EOL, LOGCOL = the cursor's column in its logical line
;; Uses: A, X, Y, HOLD1, HOLD3, BITMSK, ADRESS, SAVADR, TOADR, SCRFLG, BUFSTR
;; See: <SCREEN_ADVANCE_KEEP>
SCREEN_ADVANCE_WRITE:
    lda #EOL
SCREEN_ADVANCE_1:
    sta INSDAT

;; Moves the cursor on one column, wrapping to the next line at the right margin (GRAPHICS 0) or the screen's edge.
;;
;; A wrap in GRAPHICS 0 depends on INSDAT, which is zero when the cursor is only moving. A wrap off the third line of
;; a logical line, which can't grow further, starts a new logical line, and ends the line with an EOL when INSDAT is
;; nonzero. A wrap into a line that starts the next logical line inserts a blank line, to extend this logical line,
;; when INSDAT is nonzero. Wrapping off the bottom scrolls when INSDAT is nonzero (see <SCREEN_NEW_LINE>).
;;
;; In GRAPHICS 9-11 the cursor never wraps: their columns pass the test for GRAPHICS 8's two-byte columns, and stop
;; at 80, past the edge.
;; In: INSDAT = 0 to move only, or the character being written
;; Out: LOGCOL = the cursor's column in its logical line
;; Uses: A, X, Y, HOLD1, HOLD3, BITMSK, ADRESS, SAVADR, TOADR, SCRFLG, BUFSTR
;; See: <MODE_COLUMNS>
SCREEN_ADVANCE_KEEP:
    inc LOGCOL
    inc COLCRS
    bne SCREEN_ADVANCE_CHECK
    inc COLCRS+1
SCREEN_ADVANCE_CHECK:
    lda COLCRS
    ldx DINDEX
    cmp MODE_COLUMNS,x
    beq SCREEN_ADVANCE_EDGE
    cpx #0
    bne SCREEN_ADVANCE_DONE             ; graphics: not yet at the edge
    cmp RMARGN
    beq SCREEN_ADVANCE_DONE
    bcs SCREEN_ADVANCE_EDGE             ; past the right margin
SCREEN_ADVANCE_DONE:
    rts
SCREEN_ADVANCE_EDGE:
    cpx #SCREEN_WIDE_MODE
    bcc SCREEN_ADVANCE_WRAP
    lda COLCRS+1
    beq SCREEN_ADVANCE_DONE             ; only the low byte matched
SCREEN_ADVANCE_WRAP:
    lda DINDEX
    bne SCREEN_NEW_LINE                 ; graphics: the next row
    lda LOGCOL
    cmp #2 * DISPLAY_LINE_BYTES + 1
    bcc SCREEN_ADVANCE_NEXT             ; not off the logical line's third line
    lda INSDAT
    beq SCREEN_NEW_LINE
    jsr SCREEN_NEW_LINE_EOL
    jmp SCREEN_NEW_LINE_DONE
SCREEN_ADVANCE_NEXT:
    jsr SCREEN_NEW_LINE
    lda ROWCRS
    clc
    adc #SCREEN_LOGMAP_BIT
    jsr SCREEN_MAP_TEST
    bcc SCREEN_ADVANCE_FIND             ; the line continues this logical line
    lda INSDAT
    beq SCREEN_ADVANCE_FIND
    clc                                 ; the inserted line continues the logical line
    jsr INSERT_ROW
SCREEN_ADVANCE_FIND:
    jmp SCREEN_FIND_LOGCOL

    ; Not reached: it would load 0 into INSDAT and join SCREEN_NEW_LINE_EOL's store, a move to the next line
    ; without the EOL.
    .byte $A9, $00, $F0, $02

;; Ends the line with an EOL: moves the cursor to the start of the next line, which starts a new logical line, and
;; scrolls if it was the last.
;;
;; The screen editor's routine for EOL in <CONTROL_CODES>.
;; Out: INSDAT = EOL, ROWCRS, COLCRS = the start of the next line, LOGCOL = its column in its logical line
;; Uses: A, X, Y, HOLD1, HOLD3, BITMSK, ADRESS, SCRFLG, BUFSTR
;; See: <SCREEN_NEW_LINE>
SCREEN_NEW_LINE_EOL:
    lda #EOL
    sta INSDAT

;; Moves the cursor to the start of the next line, scrolling a text screen when it goes past the bottom and INSDAT is
;; nonzero.
;;
;; The bottom is the 24th line, the 4th of a split screen's text window when it is swapped in, or the mode's last row
;; (where the cursor is left out of range). Scrolling repeats until the top line starts a logical line, so whole
;; logical lines leave the screen; each scroll counts in SCRFLG and moves BUFSTR, the row the editor's input starts
;; on, up a line. The first line scrolled in starts a logical line when INSDAT is EOL, and continues the last one
;; otherwise.
;; In: INSDAT = 0 to move only, EOL to end the line, or the character being written
;; Out: ROWCRS, COLCRS = the start of the next line, LOGCOL = its column in its logical line
;; Uses: A, X, Y, HOLD1, HOLD3, BITMSK, ADRESS, SCRFLG, BUFSTR
SCREEN_NEW_LINE:
    jsr SCREEN_LEFT_COLUMN
    lda #0
    sta COLCRS+1
    inc ROWCRS
    ldx DINDEX
    ldy #DISPLAY_LINES
    bit SWPFLG
    bpl SCREEN_NEW_LINE_ROWS
    ldy #DISPLAY_WINDOW_LINES             ; the text window is swapped in
    tya
    bne SCREEN_NEW_LINE_BOTTOM          ; always
SCREEN_NEW_LINE_ROWS:
    lda MODE_ROWS,x
SCREEN_NEW_LINE_BOTTOM:
    cmp ROWCRS
    bne SCREEN_NEW_LINE_DONE
    sty HOLD3
    txa
    bne SCREEN_NEW_LINE_DONE            ; graphics
    lda INSDAT
    beq SCREEN_NEW_LINE_DONE            ; only moving
    cmp #EOL
    sec
    beq SCREEN_NEW_LINE_SCROLL
    clc
SCREEN_NEW_LINE_SCROLL:
    jsr SCREEN_SCROLL
    inc SCRFLG
    dec BUFSTR
    dec HOLD3
    lda LOGMAP
    sec                                 ; the next line scrolled in starts a logical line
    bpl SCREEN_NEW_LINE_SCROLL          ; the top line doesn't start one
    lda HOLD3
    sta ROWCRS
SCREEN_NEW_LINE_DONE:
    jmp SCREEN_FIND_LOGCOL

;; Subtracts ENDPT from DRAWTO's row or column accumulator.
;; In: X = 0 for ROWAC, 2 for COLAC
;; Uses: A
;; Keeps: X, Y
SCREEN_SUBTRACT_ENDPT:
    sec
    lda ROWAC,x
    sbc ENDPT
    sta ROWAC,x
    lda ROWAC+1,x
    sbc ENDPT+1
    sta ROWAC+1,x
    rts

;; Checks the cursor before a screen editor operation, first reopening a full screen in GRAPHICS 0 when it is in
;; another mode.
;;
;; A split screen's text window is left as it is.
;; Out: DSTAT = SUCCES
;; Uses: A, X, Y, BRKKEY
;; Errors: as <SCREEN_CHECK_CURSOR>'s
;; See: <EDITOR_OPEN>
SCREEN_EDITOR_CHECK:
    lda BOTSCR
    cmp #DISPLAY_WINDOW_LINES
    beq SCREEN_CHECK_CURSOR             ; a split screen
    lda DINDEX
    beq SCREEN_CHECK_CURSOR
    jsr EDITOR_OPEN

;; Checks that the cursor is on the screen and that BREAK hasn't been pressed, and if not returns to the handler's
;; caller with an error.
;;
;; It first limits RMARGN to 39. A cursor out of range is moved home (<HOME_CURSOR>). On an error it drops its caller's
;; return address, swaps a swapped-in text window back, and leaves through the handlers' return, <DISPLAY_RETURN>, with
;; the status in Y.
;; Out: DSTAT = SUCCES, BRKKEY = $80
;; Uses: A, X
;; Errors: DSTAT, Y = CRSROR when the cursor is out of range, BRKABT when BREAK was pressed; the return is to the
;;   caller's caller
SCREEN_CHECK_CURSOR:
    lda #SCREEN_LAST_COLUMN
    cmp RMARGN
    bcs SCREEN_CHECK_CURSOR_ROW
    sta RMARGN
SCREEN_CHECK_CURSOR_ROW:
    ldx DINDEX
    lda MODE_ROWS,x
    cmp ROWCRS
    bcc SCREEN_CHECK_CURSOR_OUT
    beq SCREEN_CHECK_CURSOR_OUT
    cpx #SCREEN_WIDE_MODE
    bne SCREEN_CHECK_CURSOR_NARROW
    lda COLCRS+1                        ; GRAPHICS 8: columns 0-319
    beq SCREEN_CHECK_CURSOR_IN
    cmp #1
    bne SCREEN_CHECK_CURSOR_OUT
    beq SCREEN_CHECK_CURSOR_COLUMN      ; always
SCREEN_CHECK_CURSOR_NARROW:
    lda COLCRS+1
    bne SCREEN_CHECK_CURSOR_OUT
SCREEN_CHECK_CURSOR_COLUMN:
    lda MODE_COLUMNS,x
    cmp COLCRS
    bcc SCREEN_CHECK_CURSOR_OUT
    beq SCREEN_CHECK_CURSOR_OUT
SCREEN_CHECK_CURSOR_IN:
    lda #SUCCES
    sta DSTAT
    lda #BRKABT                         ; also nonzero for BRKKEY
    ldx BRKKEY
    sta BRKKEY
    beq SCREEN_CHECK_CURSOR_ERROR       ; BREAK was pressed
    rts
SCREEN_CHECK_CURSOR_OUT:
    jsr HOME_CURSOR
    lda #CRSROR
SCREEN_CHECK_CURSOR_ERROR:
    sta DSTAT
    pla
    pla
    lda SWPFLG
    bpl SCREEN_CHECK_CURSOR_RETURN
    jsr SCREEN_SWAP_WINDOW
SCREEN_CHECK_CURSOR_RETURN:
    jmp DISPLAY_RETURN

;; Takes the cursor off the screen, putting back the character it covered.
;; In: OLDCHR = the character, OLDADR = its address
;; Out: Y = 0
;; Uses: A
;; Keeps: X
SCREEN_ERASE_CURSOR:
    ldy #0
    lda OLDCHR
    sta (OLDADR),y
    rts

;; Finds a bit of the map that TABMAP and LOGMAP make together: bits 0-119 are TABMAP's tab stops, one for each
;; column of a logical line, and bits 120-143 are LOGMAP's, one for each row that starts a logical line.
;;
;; Each byte's bit 7 comes first.
;; In: A = the bit's number
;; Out: A, X = the byte's offset from TABMAP, BITMSK = the bit's mask
;; Keeps: Y
;; See: <BIT_MASKS>
SCREEN_MAP_POSITION:
    pha
    and #7
    tax
    lda BIT_MASKS,x
    sta BITMSK
    pla
    lsr a
    lsr a
    lsr a
    tax
    rts

;; Moves LOGMAP's bits up a row, for a scroll, with carry as the bottom row's.
;; In: carry = set when the bottom row starts a logical line
;; Keeps: A, X, Y
SCREEN_SCROLL_LOGMAP:
    rol LOGMAP+2
    rol LOGMAP+1
    rol LOGMAP
    rts

;; Sets or clears a bit of the tab and logical line map, as carry says.
;; In: A = the bit's number, carry = set to set it, clear to clear it
;; Uses: A, X, BITMSK
;; Keeps: Y
;; See: <SCREEN_MAP_POSITION>
SCREEN_MAP_WRITE:
    bcc SCREEN_MAP_CLEAR

;; Sets a bit of the tab and logical line map, such as a tab stop.
;; In: A = the bit's number
;; Uses: A, X, BITMSK
;; Keeps: Y
;; See: <SCREEN_MAP_POSITION>
SCREEN_MAP_SET:
    jsr SCREEN_MAP_POSITION
    lda TABMAP,x
    ora BITMSK
    sta TABMAP,x
    rts

;; Clears a bit of the tab and logical line map, such as a tab stop.
;; In: A = the bit's number
;; Uses: A, X, BITMSK
;; Keeps: Y
;; See: <SCREEN_MAP_POSITION>
SCREEN_MAP_CLEAR:
    jsr SCREEN_MAP_POSITION
    lda BITMSK
    eor #$FF
    and TABMAP,x
    sta TABMAP,x
    rts

;; Tests whether the cursor's row starts a logical line.
;; Out: carry = set when it does
;; Uses: A, X, BITMSK
;; Keeps: Y
SCREEN_CURSOR_LINE_STARTS:
    lda ROWCRS

;; Tests whether a row starts a logical line.
;; In: A = the row
;; Out: carry = set when it does
;; Uses: A, X, BITMSK
;; Keeps: Y
SCREEN_ROW_STARTS:
    clc

;; Tests whether a row, plus carry, starts a logical line: with carry set, the row after A.
;; In: A = the row, carry = set for the next row
;; Out: carry = set when it starts a logical line
;; Uses: A, X, BITMSK
;; Keeps: Y
SCREEN_ROW_STARTS_PLUS:
    adc #SCREEN_LOGMAP_BIT

;; Tests a bit of the tab and logical line map.
;; In: A = the bit's number
;; Out: carry = set when the bit is set
;; Uses: A, X, BITMSK
;; Keeps: Y
;; See: <SCREEN_MAP_POSITION>
SCREEN_MAP_TEST:
    jsr SCREEN_MAP_POSITION
    clc
    lda TABMAP,x
    and BITMSK
    beq SCREEN_MAP_TEST_DONE
    sec
SCREEN_MAP_TEST_DONE:
    rts

;; Converts the internal code in CHAR to ATASCII, in ATACHR; in the pixel modes, from GRAPHICS 3, the value is copied
;; as it is.
;; In: CHAR = the internal code or pixel value, DINDEX = the display mode
;; Out: A, ATACHR = the ATASCII character or pixel value
;; Uses: X, Y
;; See: <INTERNAL_TO_ATASCII>
SCREEN_TO_ATASCII:
    lda CHAR
    ldy DINDEX
    cpy #SCREEN_PIXEL_MODE
    bcs SCREEN_TO_ATASCII_DONE
    rol a                               ; bits 5 and 6 to bits 0 and 1
    rol a
    rol a
    rol a
    and #%00000011
    tax
    lda CHAR
    and #%10011111
    ora INTERNAL_TO_ATASCII,x
SCREEN_TO_ATASCII_DONE:
    sta ATACHR
    rts

;; Moves a line down a line, as one step of inserting a line: the line at TOADR takes the one at SAVADR, and its own
;; goes to LINBUF to move down in the next step.
;;
;; Called again, it moves the line in LINBUF to the line after, and so on down the screen.
;; In: SAVADR = the line to move, TOADR = the line it replaces
;; Out: SAVADR = LINBUF, TOADR = the next line
;; Uses: A, Y, ADRESS, TMPCHR
;; Keeps: X
SCREEN_PUSH_LINE:
    lda #>LINBUF
    sta ADRESS+1
    lda #<LINBUF
    sta ADRESS
    ldy #DISPLAY_LINE_BYTES - 1
SCREEN_PUSH_LINE_LOOP:
    lda (TOADR),y
    sta TMPCHR
    lda (SAVADR),y
    sta (TOADR),y
    lda TMPCHR
    sta (ADRESS),y
    dey
    bpl SCREEN_PUSH_LINE_LOOP
    lda ADRESS+1
    sta SAVADR+1
    lda ADRESS
    sta SAVADR
    clc
    lda TOADR
    adc #DISPLAY_LINE_BYTES
    sta TOADR
    bcc SCREEN_PUSH_LINE_DONE
    inc TOADR+1
SCREEN_PUSH_LINE_DONE:
    rts

;; Moves LOGMAP's bits from the cursor's row down a row, for an inserted line, with carry as the inserted row's.
;; In: ROWCRS = the inserted row, carry = set when it starts a logical line
;; Uses: A, X, Y, BITMSK
SCREEN_INSERT_LOGMAP:
    php
    ldy #DISPLAY_LINES - 1
SCREEN_INSERT_LOGMAP_LOOP:
    tya
    jsr SCREEN_ROW_STARTS
    php
    tya
    clc
    adc #SCREEN_LOGMAP_BIT + 1          ; the next row's bit takes this row's
    plp
    jsr SCREEN_MAP_WRITE
    dey
    bmi SCREEN_INSERT_LOGMAP_ROW
    cpy ROWCRS
    bcs SCREEN_INSERT_LOGMAP_LOOP
SCREEN_INSERT_LOGMAP_ROW:
    lda ROWCRS
    clc
    adc #SCREEN_LOGMAP_BIT
    plp
    jmp SCREEN_MAP_WRITE

;; Clears the cursor's line, 40 bytes from its left margin.
;;
;; From a margin above 0, the 40 bytes run into the next line's margin.
;; Out: COLCRS = LMARGN, ADRESS = the line's address at the margin, Y = $FF
;; Uses: A, X, OLDADR, DMASK, SHFAMT, TOADR, HOLD1, HOLD2, TMPLBT
;; See: <SCREEN_LOCATE>
SCREEN_CLEAR_LINE:
    lda LMARGN
    sta COLCRS
    jsr SCREEN_LOCATE
    ldy #DISPLAY_LINE_BYTES - 1
    lda #0
SCREEN_CLEAR_LINE_LOOP:
    sta (ADRESS),y
    dey
    bpl SCREEN_CLEAR_LINE_LOOP
    rts

;; Scrolls the screen up a line, with carry saying whether the new bottom line starts a logical line.
;;
;; Every byte from SAVMSC up to RAMTOP takes the byte a line after it; the last line's are cleared.
;; In: carry = set when the bottom line starts a logical line
;; Out: LOGCOL = the cursor's column in its logical line, HOLD1 = the row its logical line starts on
;; Uses: A, X, Y, ADRESS, BITMSK
;; Entry: SCREEN_SCROLL_FROM = moves the lines up from ADRESS only, without LOGMAP
SCREEN_SCROLL:
    jsr SCREEN_SCROLL_LOGMAP
    lda SAVMSC
    sta ADRESS
    lda SAVMSC+1
    sta ADRESS+1
SCREEN_SCROLL_FROM:
    ldy #DISPLAY_LINE_BYTES
    lda (ADRESS),y
    ldx RAMTOP
    dex
    cpx ADRESS+1
    bne SCREEN_SCROLL_STORE
    ldx #$100 - DISPLAY_LINE_BYTES - 1
    cpx ADRESS
    bcs SCREEN_SCROLL_STORE
    lda #0                              ; the last line, below RAMTOP
SCREEN_SCROLL_STORE:
    ldy #0
    sta (ADRESS),y
    inc ADRESS
    bne SCREEN_SCROLL_FROM
    inc ADRESS+1
    lda ADRESS+1
    cmp RAMTOP
    bne SCREEN_SCROLL_FROM
    jmp SCREEN_FIND_LOGCOL

;; Works out LOGCOL, the cursor's column in its logical line, from the rows above it back to the row the logical
;; line starts on.
;; Out: LOGCOL = 40 for each row above the cursor's in the logical line, plus COLCRS; HOLD1 = the logical line's first
;;   row
;; Uses: A, X, BITMSK
;; Keeps: Y
SCREEN_FIND_LOGCOL:
    lda #0
    sta LOGCOL
    lda ROWCRS
    sta HOLD1
SCREEN_FIND_LOGCOL_LOOP:
    lda HOLD1
    jsr SCREEN_ROW_STARTS
    bcs SCREEN_FIND_LOGCOL_ADD
    lda LOGCOL
    clc
    adc #DISPLAY_LINE_BYTES
    sta LOGCOL
    dec HOLD1
    jmp SCREEN_FIND_LOGCOL_LOOP
SCREEN_FIND_LOGCOL_ADD:
    clc
    lda LOGCOL
    adc COLCRS
    sta LOGCOL
    rts

;; Measures the logical line the editor returns after RETURN, from BUFSTR to its end without trailing blanks.
;;
;; It moves a copy of the cursor from BUFSTR until it enters the next logical line or reaches the bottom of the
;; screen, then back over blanks. The cursor itself is kept.
;; In: BUFSTR = the row and column the line starts on
;; Out: BUFCNT = the number of characters to return, plus 1
;; Uses: A, X, Y, INSDAT, HOLD1, HOLD3, BITMSK, TMPROW, TMPCOL, ADRESS, OLDADR, DMASK, SHFAMT, CHAR
;; Keeps: ROWCRS, COLCRS, LOGCOL
SCREEN_MEASURE_LINE:
    jsr SCREEN_SAVE_CURSOR
    lda LOGCOL
    pha
    lda BUFSTR
    sta ROWCRS
    lda BUFSTR+1
    sta COLCRS
    lda #1
    sta BUFCNT
SCREEN_MEASURE_LINE_LOOP:
    ldx #DISPLAY_LINES - 1
    lda SWPFLG
    bpl SCREEN_MEASURE_LINE_BOTTOM
    ldx #DISPLAY_WINDOW_LINES - 1
SCREEN_MEASURE_LINE_BOTTOM:
    cpx ROWCRS
    bne SCREEN_MEASURE_LINE_STEP
    lda COLCRS
    cmp RMARGN
    bne SCREEN_MEASURE_LINE_STEP
    inc BUFCNT                          ; the screen's last place
    jmp SCREEN_MEASURE_LINE_TRIM
SCREEN_MEASURE_LINE_STEP:
    jsr SCREEN_ADVANCE
    inc BUFCNT
    lda LOGCOL
    cmp LMARGN
    bne SCREEN_MEASURE_LINE_LOOP        ; still in the logical line
    dec ROWCRS
    jsr EDIT_CURSOR_LEFT                          ; back to its last place
SCREEN_MEASURE_LINE_TRIM:
    jsr DISPLAY_READ
    bne SCREEN_MEASURE_LINE_DONE        ; not a blank
    dec BUFCNT
    lda LOGCOL
    cmp LMARGN
    beq SCREEN_MEASURE_LINE_DONE
    jsr EDIT_CURSOR_LEFT
    lda COLCRS
    cmp RMARGN
    bne SCREEN_MEASURE_LINE_NEXT
    dec ROWCRS                          ; wrapped back to the line above
SCREEN_MEASURE_LINE_NEXT:
    lda BUFCNT
    bne SCREEN_MEASURE_LINE_TRIM
SCREEN_MEASURE_LINE_DONE:
    pla
    sta LOGCOL
    jsr SCREEN_RESTORE_CURSOR
    rts

;; Makes the start of the cursor's logical line the start of the editor's input, in BUFSTR, after the cursor moves up
;; or down.
;; Out: BUFSTR = the logical line's first row, BUFSTR+1 = LMARGN, LOGCOL = the cursor's column in its logical line
;; Uses: A, X, HOLD1, BITMSK
;; Keeps: Y
SCREEN_SET_BUFSTR:
    jsr SCREEN_FIND_LOGCOL
    lda HOLD1
    sta BUFSTR
    lda LMARGN
    sta BUFSTR+1
    rts

;; Deletes the last line of the logical line before the cursor's when it has become blank, after a character was
;; deleted.
;;
;; When the cursor is at the start of a logical line, it moves up to the line before, then joins
;; <SCREEN_DROP_BLANK_LINE>.
;; Uses: A, X, Y, ROWCRS, ADRESS, OLDADR, DMASK, SHFAMT, TOADR, HOLD1, HOLD2, TMPLBT
;; See: <SCREEN_DROP_BLANK_LINE>
SCREEN_DROP_LAST_LINE:
    lda LOGCOL
    cmp LMARGN
    bne SCREEN_DROP_LAST_LINE_1
    dec ROWCRS
SCREEN_DROP_LAST_LINE_1:
    jsr SCREEN_FIND_LOGCOL

;; Deletes the cursor's line when it is blank, unless it is the first line of its logical line.
;;
;; It checks RMARGN - LMARGN + 1 bytes from the cursor, which is at the left margin when the editor calls it. The
;; deletion is the editor's delete line, from <DELETE_ROWS>, which shortens the logical line.
;; Uses: A, X, Y, ADRESS, OLDADR, DMASK, SHFAMT, TOADR, HOLD1, HOLD2, TMPLBT
SCREEN_DROP_BLANK_LINE:
    lda LOGCOL
    cmp LMARGN
    beq SCREEN_DROP_BLANK_LINE_DONE     ; the logical line's first line
    jsr SCREEN_LOCATE
    lda RMARGN
    sec
    sbc LMARGN
    tay
SCREEN_DROP_BLANK_LINE_LOOP:
    lda (ADRESS),y
    bne SCREEN_DROP_BLANK_LINE_DONE     ; not blank
    dey
    bpl SCREEN_DROP_BLANK_LINE_LOOP
    jmp DELETE_ROWS
SCREEN_DROP_BLANK_LINE_DONE:
    rts

;; Looks ATACHR up in the screen editor's control codes.
;; In: ATACHR = the character
;; Out: zero = set when it is a control code, X = its entry's offset in CONTROL_CODES
;; Uses: A
;; Keeps: Y
;; See: <CONTROL_CODES>
SCREEN_FIND_CONTROL_CODE:
    ldx #(CONTROL_CODE_COUNT - 1) * 3
SCREEN_FIND_CONTROL_CODE_LOOP:
    lda CONTROL_CODES,x
    cmp ATACHR
    beq SCREEN_FIND_CONTROL_CODE_DONE
    dex
    dex
    dex
    bpl SCREEN_FIND_CONTROL_CODE_LOOP
SCREEN_FIND_CONTROL_CODE_DONE:
    rts

;; Saves the cursor's row and column in TMPROW and TMPCOL.
;; Out: X = $FF
;; Uses: A
;; Keeps: Y
;; See: <SCREEN_RESTORE_CURSOR>
SCREEN_SAVE_CURSOR:
    ldx #COLCRS + 1 - ROWCRS
SCREEN_SAVE_CURSOR_LOOP:
    lda ROWCRS,x
    sta TMPROW,x
    dex
    bpl SCREEN_SAVE_CURSOR_LOOP
    rts

;; Puts back the cursor's row and column from TMPROW and TMPCOL.
;; Out: X = $FF
;; Uses: A
;; Keeps: Y
;; See: <SCREEN_SAVE_CURSOR>
SCREEN_RESTORE_CURSOR:
    ldx #COLCRS + 1 - ROWCRS
SCREEN_RESTORE_CURSOR_LOOP:
    lda TMPROW,x
    sta ROWCRS,x
    dex
    bpl SCREEN_RESTORE_CURSOR_LOOP
    rts

;; Swaps the split screen's text window in or out, then returns as the handlers do.
;; Out: Y = DSTAT, the status, A = ATACHR, DSTAT = SUCCES
;; Uses: X
;; See: <SCREEN_SWAP_WINDOW>, <DISPLAY_RETURN>
SCREEN_SWAP_RETURN:
    jsr SCREEN_SWAP_WINDOW
    jmp DISPLAY_RETURN

;; Swaps the split screen's text window's cursor and screen variables (TXTROW to TXTOLD) with the main ones
;; (ROWCRS to OLDADR), and turns SWPFLG over; on a full screen it does nothing.
;;
;; The editor works on the text window by swapping its variables in, and swaps them out again before it returns.
;; Uses: A, X, SWPFLG
;; Keeps: Y
SCREEN_SWAP_WINDOW:
    lda BOTSCR
    cmp #DISPLAY_LINES
    beq SCREEN_SWAP_WINDOW_DONE         ; a full screen
    ldx #OLDADR + 1 - ROWCRS
SCREEN_SWAP_WINDOW_LOOP:
    lda ROWCRS,x
    pha
    lda TXTROW,x
    sta ROWCRS,x
    pla
    sta TXTROW,x
    dex
    bpl SCREEN_SWAP_WINDOW_LOOP
    lda SWPFLG
    eor #$FF
    sta SWPFLG
SCREEN_SWAP_WINDOW_DONE:
    rts

;; Clicks the speaker in CONSOL, for a key and, 33 times over, the bell.
;;
;; Over 128 scan lines X counts down and is written to CONSOL, whose bit 3, the speaker, turns over every 8.
;; Out: X = $FF
;; Keeps: A, Y
SCREEN_CLICK:
    ldx #$7F
SCREEN_CLICK_LOOP:
    stx CONSOL
    stx WSYNC
    dex
    bpl SCREEN_CLICK_LOOP
    rts

;; Moves the cursor to the left margin, or to column 0 in a graphics mode; COLCRS+1 is unchanged.
;; Out: A, COLCRS = the column
;; Uses: X
;; Keeps: Y
SCREEN_LEFT_COLUMN:
    lda #0
    ldx SWPFLG
    bne SCREEN_LEFT_COLUMN_MARGIN       ; the text window is swapped in
    ldx DINDEX
    bne SCREEN_LEFT_COLUMN_SET
SCREEN_LEFT_COLUMN_MARGIN:
    lda LMARGN
SCREEN_LEFT_COLUMN_SET:
    sta COLCRS
    rts

;; Points ADRESS at the screen's top left corner, SAVMSC.
;; Out: A = SAVMSC's high byte, ADRESS = SAVMSC
;; Keeps: X, Y
SCREEN_TOP_ADDRESS:
    lda SAVMSC
    sta ADRESS
    lda SAVMSC+1
    sta ADRESS+1
    rts
