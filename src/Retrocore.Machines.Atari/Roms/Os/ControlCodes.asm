;; THE SCREEN EDITOR'S CONTROL CODES ($F779-$F912)
;;
;; The routines the screen editor runs for a control character it obeys rather than shows: escape, the cursor moves,
;; clear screen, backspace, tab, the tab stops, inserting and deleting characters and lines, and the bell. The editor
;; finds each through the control code table, <CONTROL_CODES>, and jumps to it; end of line ($9B) is the screen
;; handler's own, <SCREEN_NEW_LINE_EOL>.
;;
;; The editor's screen is 24 rows of 40 bytes, grouped into logical lines of up to three rows. LOGMAP has a bit for
;; each row that starts a logical line; it follows TABMAP's 120 bits, so the bit routines
;; (<SCREEN_MAP_WRITE>, <SCREEN_MAP_TEST>) reach a row's bit as bit $78 plus the row.

;; ESC ($1B): shows the next character, rather than obeying it.
;; Out: ESCFLG = $80
;; Uses: A
;; Keeps: X, Y
EDIT_ESCAPE:
    lda #$80
    sta ESCFLG
    rts

;; Cursor up ($1C): moves the cursor up a row, from the top row to the bottom one.
;;
;; The column stays. The cursor's logical line is found again, and BUFSTR pointed at its start.
;; Out: ROWCRS, LOGCOL, BUFSTR
;; Uses: A, X, BITMSK, HOLD1
;; See: <SCREEN_SET_BUFSTR>
EDIT_CURSOR_UP:
    dec ROWCRS
    bpl EDIT_CURSOR_UP_DONE
    ldx BOTSCR
    dex
EDIT_CURSOR_UP_ROW:
    stx ROWCRS
EDIT_CURSOR_UP_DONE:
    jmp SCREEN_SET_BUFSTR                      ; LOGCOL, and BUFSTR at the logical line's start

;; Cursor down ($1D): moves the cursor down a row, from the bottom row to the top one.
;;
;; The column stays. The cursor's logical line is found again, and BUFSTR pointed at its start.
;; Out: ROWCRS, LOGCOL, BUFSTR
;; Uses: A, X, BITMSK, HOLD1
;; See: <SCREEN_SET_BUFSTR>
EDIT_CURSOR_DOWN:
    inc ROWCRS
    lda ROWCRS
    cmp BOTSCR
    bcc EDIT_CURSOR_UP_DONE
    ldx #$00
    beq EDIT_CURSOR_UP_ROW          ; always

;; Cursor left ($1E): moves the cursor left a column, from the left margin to the right margin of the same row.
;; Out: COLCRS, LOGCOL
;; Uses: A, X, BITMSK, HOLD1
;; See: <SCREEN_FIND_LOGCOL>
EDIT_CURSOR_LEFT:
    dec COLCRS
    lda COLCRS
    bmi EDIT_CURSOR_LEFT_WRAP
    cmp LMARGN
    bcs EDIT_CURSOR_LEFT_DONE
EDIT_CURSOR_LEFT_WRAP:
    lda RMARGN
EDIT_CURSOR_LEFT_COLUMN:
    sta COLCRS
EDIT_CURSOR_LEFT_DONE:
    jmp SCREEN_FIND_LOGCOL                      ; LOGCOL

;; Cursor right ($1F): moves the cursor right a column, from the right margin to the left margin of the same row.
;; Out: COLCRS, LOGCOL
;; Uses: A, X, BITMSK, HOLD1
;; See: <SCREEN_FIND_LOGCOL>
EDIT_CURSOR_RIGHT:
    inc COLCRS
    lda COLCRS
    cmp RMARGN
    bcc EDIT_CURSOR_LEFT_DONE
    beq EDIT_CURSOR_LEFT_DONE
    lda LMARGN
    jmp EDIT_CURSOR_LEFT_COLUMN

;; Clear screen ($7D): clears the screen, makes every row a logical line of its own, and homes the cursor.
;;
;; The screen's open uses it too. It clears whole pages from SAVMSC until the page reaches RAMTOP, so it also
;; clears as many bytes past RAMTOP's page as SAVMSC is past a page boundary ($40 in mode 0).
;; Out: A = 0, the cursor at the top left (see <HOME_CURSOR>)
;; Uses: X, Y, ADRESS
EDIT_CLEAR_SCREEN:
    jsr SCREEN_TOP_ADDRESS                      ; ADRESS = SAVMSC
    ldy #$00
    tya
EDIT_CLEAR_SCREEN_LOOP:
    sta (ADRESS),y
    iny
    bne EDIT_CLEAR_SCREEN_LOOP
    inc ADRESS+1
    ldx ADRESS+1
    cpx RAMTOP
    bcc EDIT_CLEAR_SCREEN_LOOP
    lda #$FF                        ; every row starts a logical line
EDIT_CLEAR_SCREEN_MAP:
    sta LOGMAP,y
    iny
    cpy #$04                        ; LOGMAP's 4 bytes
    bcc EDIT_CLEAR_SCREEN_MAP

;; Puts the cursor in the top row at the left margin, or at column 0 in a graphics mode, as the start of a logical
;; line.
;;
;; The screen handler uses it when the cursor is out of range.
;; Out: A = 0, ROWCRS = 0, COLCRS, LOGCOL and BUFSTR+1 = the column, BUFSTR = 0
;; Uses: X
;; See: <SCREEN_LEFT_COLUMN>
HOME_CURSOR:
    jsr SCREEN_LEFT_COLUMN                      ; COLCRS, and A = the column
    sta LOGCOL
    sta BUFSTR+1
    lda #$00
    sta ROWCRS
    sta COLCRS+1
    sta BUFSTR
    rts

;; Backspace ($7E): moves the cursor left and blanks the character there, going back to the end of the row above
;; from the start of a row.
;;
;; At the start of a logical line it does nothing. At the start of a later row of the logical line, that row is
;; deleted first when it's blank (<SCREEN_DROP_BLANK_LINE>).
;; Out: ROWCRS, COLCRS, LOGCOL, ATACHR = a space
;; Uses: A, X, Y
EDIT_BACKSPACE:
    lda LOGCOL
    cmp LMARGN
    beq EDIT_BACKSPACE_DONE         ; the start of the logical line
    lda COLCRS
    cmp LMARGN
    bne EDIT_BACKSPACE_LEFT
    jsr SCREEN_DROP_BLANK_LINE                      ; delete this row if it's blank
EDIT_BACKSPACE_LEFT:
    jsr EDIT_CURSOR_LEFT
    lda COLCRS
    cmp RMARGN
    bne EDIT_BACKSPACE_BLANK
    lda ROWCRS
    beq EDIT_BACKSPACE_BLANK
    jsr EDIT_CURSOR_UP              ; it wrapped: the end of the row above
EDIT_BACKSPACE_BLANK:
    lda #' '
    sta ATACHR
    jsr DISPLAY_PLOT                      ; put it at the cursor
EDIT_BACKSPACE_DONE:
    jmp SCREEN_FIND_LOGCOL                      ; LOGCOL

;; Tab ($7F): moves the cursor right to the next tab stop in its logical line, or to the start of the next logical
;; line.
;; Out: ROWCRS, COLCRS, LOGCOL
;; Uses: A, X, Y
;; See: <TABMAP>
EDIT_TAB:
    jsr EDIT_CURSOR_RIGHT
    lda COLCRS
    cmp LMARGN
    bne EDIT_TAB_TEST
    jsr SCREEN_NEW_LINE                      ; it wrapped: down to the next row
    jsr SCREEN_CURSOR_LINE_STARTS
    bcc EDIT_TAB_TEST
    bcs EDIT_TAB_DONE               ; always: the row starts a logical line
EDIT_TAB_TEST:
    lda LOGCOL
    jsr SCREEN_MAP_TEST                      ; carry = a tab stop here
    bcc EDIT_TAB
EDIT_TAB_DONE:
    jmp SCREEN_FIND_LOGCOL                      ; LOGCOL

;; Set tab ($9F): makes the cursor's column in its logical line a tab stop.
;; Uses: A, X, BITMSK
;; See: <TABMAP>
EDIT_SET_TAB:
    lda LOGCOL
    jmp SCREEN_MAP_SET

;; Clear tab ($9E): stops the cursor's column in its logical line being a tab stop.
;; Uses: A, X, BITMSK
;; See: <TABMAP>
EDIT_CLEAR_TAB:
    lda LOGCOL
    jmp SCREEN_MAP_CLEAR

;; Insert character ($FF): moves the characters from the cursor to the end of its logical line right one place, and
;; blanks the cursor's place.
;;
;; A character moved past the end of a row moves to the next; when that row starts another logical line, a row is
;; inserted for it (<SCREEN_ADVANCE_KEEP>), so the logical line grows. The last character of a full logical line is
;; lost. The cursor stays where it was, less any rows the screen scrolled up to make room (counted in SCRFLG).
;; Uses: A, X, Y, INSDAT, SCRFLG, TMPROW, TMPCOL
EDIT_INSERT_CHARACTER:
    jsr SCREEN_SAVE_CURSOR                      ; keep the cursor
    jsr DISPLAY_READ
    sta INSDAT                      ; the character under it
    lda #$00
    sta SCRFLG
EDIT_INSERT_CHARACTER_LOOP:
    jsr DISPLAY_WRITE                      ; put A here
    lda LOGCOL
    pha
    jsr SCREEN_ADVANCE_KEEP                      ; next place, carrying INSDAT
    pla
    cmp LOGCOL
    bcs EDIT_INSERT_CHARACTER_END   ; moved into the next logical line
    lda INSDAT
    pha
    jsr DISPLAY_READ
    sta INSDAT                      ; the character here goes next
    pla
    jmp EDIT_INSERT_CHARACTER_LOOP
EDIT_INSERT_CHARACTER_END:
    jsr SCREEN_RESTORE_CURSOR                      ; back to the cursor
EDIT_INSERT_CHARACTER_SCROLLED:
    dec SCRFLG
    bmi EDIT_INSERT_CHARACTER_DONE
    dec ROWCRS                      ; up a row for each row scrolled off the top
    bne EDIT_INSERT_CHARACTER_SCROLLED
EDIT_INSERT_CHARACTER_DONE:
    jmp SCREEN_FIND_LOGCOL                      ; LOGCOL

;; Delete character ($FE): removes the character at the cursor, moving the rest of its logical line left one place.
;;
;; The place at the end of the logical line is blanked, and its last row is deleted when that leaves it blank
;; (<SCREEN_DROP_BLANK_LINE>), so the logical line shrinks. The cursor stays.
;; Uses: A, X, Y, ADRESS, SAVADR, INSDAT, TMPROW, TMPCOL
EDIT_DELETE_CHARACTER:
    jsr SCREEN_SAVE_CURSOR                      ; keep the cursor
EDIT_DELETE_CHARACTER_LOOP:
    jsr SCREEN_LOCATE                      ; ADRESS = this place
    lda ADRESS
    sta SAVADR
    lda ADRESS+1
    sta SAVADR+1
    lda LOGCOL
    pha
    jsr SCREEN_ADVANCE                      ; the next place
    pla
    cmp LOGCOL
    bcs EDIT_DELETE_CHARACTER_END   ; moved into the next logical line
    lda ROWCRS
    cmp BOTSCR
    bcs EDIT_DELETE_CHARACTER_END   ; moved off the bottom
    jsr DISPLAY_READ
    ldy #$00
    sta (SAVADR),y                  ; the character moves back a place
    beq EDIT_DELETE_CHARACTER_LOOP  ; always
EDIT_DELETE_CHARACTER_END:
    ldy #$00
    tya
    sta (SAVADR),y                  ; blank the last place
    jsr SCREEN_DROP_LAST_LINE                      ; delete the last row if it's blank
    jsr SCREEN_RESTORE_CURSOR                      ; back to the cursor
    jmp SCREEN_FIND_LOGCOL                      ; LOGCOL

;; Insert line ($9D): moves the cursor's row and those below it down a row, and blanks the cursor's row as the start
;; of a new logical line.
;; Out: COLCRS = LMARGN, LOGCOL
;; Uses: A, X, Y, ADRESS, SAVADR, TOADR, LINBUF
;; See: <INSERT_ROW>
EDIT_INSERT_LINE:
    sec

;; Inserts a blank row at the cursor's row, moving it and the rows below it down; the bottom row is lost.
;;
;; The rows move whole, 40 bytes at a time, from the left margin of each row through the next row's margin, so a
;; row's bytes left of the margin move with the row above. The blank row is the 40 bytes from the left margin. The
;; rows move as far as row 23, whatever BOTSCR says.
;;
;; The screen handler uses it with carry clear when a logical line grows into the row below.
;; In: carry = set for the new row to start a logical line, clear for it to continue the one above
;; Out: COLCRS = LMARGN, LOGCOL
;; Uses: A, X, Y, ADRESS, SAVADR, TOADR, LINBUF
;; See: <SCREEN_INSERT_LOGMAP>, <SCREEN_PUSH_LINE>, <SCREEN_CLEAR_LINE>
INSERT_ROW:
    jsr SCREEN_INSERT_LOGMAP                      ; LOGMAP's bits move down with the rows
    lda LMARGN
    sta COLCRS
    jsr SCREEN_LOCATE
    lda ADRESS                      ; from this row ...
    sta SAVADR
    clc
    adc #DISPLAY_LINE_BYTES            ; ... to the next
    sta TOADR
    lda ADRESS+1
    sta SAVADR+1
    adc #$00
    sta TOADR+1
    ldx ROWCRS
    cpx #(DISPLAY_LINES - 1)
    beq INSERT_ROW_BLANK
INSERT_ROW_LOOP:
    jsr SCREEN_PUSH_LINE                      ; move a row down, keeping the one it covers in LINBUF
    inx
    cpx #(DISPLAY_LINES - 1)
    bne INSERT_ROW_LOOP
INSERT_ROW_BLANK:
    jsr SCREEN_CLEAR_LINE                      ; blank the cursor's row
    jmp SCREEN_FIND_LOGCOL                      ; LOGCOL

;; Delete line ($9C): deletes the cursor's logical line, moving the screen below it up, and puts the cursor at its
;; start.
;; Out: ROWCRS, COLCRS = LMARGN, LOGCOL
;; Uses: A, X, Y, ADRESS, BITMSK, HOLD1
;; See: <DELETE_ROWS>
EDIT_DELETE_LINE:
    jsr SCREEN_FIND_LOGCOL                      ; HOLD1 = the logical line's first row
    ldy HOLD1
    sty ROWCRS

;; Deletes the cursor's row, and the rows after it up to the next logical line, moving the screen below up a row
;; each time.
;;
;; Each new bottom row is blank and starts a logical line. The screen handler uses it to delete a blank row that
;; continues a logical line.
;; Out: COLCRS = LMARGN, LOGCOL
;; Uses: A, X, Y, ADRESS, BITMSK, HOLD1
;; See: <SCREEN_SCROLL_FROM>
DELETE_ROWS:
    ldy ROWCRS
DELETE_ROWS_MAP:
    tya
    sec
    jsr SCREEN_ROW_STARTS_PLUS                      ; carry = the next row starts a logical line
    php
    tya
    clc
    adc #SCREEN_LOGMAP_BIT
    plp
    jsr SCREEN_MAP_WRITE                      ; ... so this one does
    iny
    cpy #(DISPLAY_LINES - 1) + 1
    bne DELETE_ROWS_MAP
    lda LOGMAP+2
    ora #$01                        ; row 23 starts a logical line
    sta LOGMAP+2
    lda LMARGN
    sta COLCRS
    jsr SCREEN_LOCATE
    jsr SCREEN_SCROLL_FROM                      ; move the screen up a row
    jsr SCREEN_CURSOR_LINE_STARTS
    bcc DELETE_ROWS                 ; the row still continues the logical line
    jmp SCREEN_FIND_LOGCOL                      ; LOGCOL

;; Bell ($FD): sounds the console speaker, as 33 key clicks.
;;
;; The editor also rings it when the cursor reaches column $71 of a logical line, seven from its end.
;; Uses: X, Y
;; See: <SCREEN_CLICK>
EDIT_BELL:
    ldy #$20
EDIT_BELL_LOOP:
    jsr SCREEN_CLICK                      ; a click
    dey
    bpl EDIT_BELL_LOOP
    rts
