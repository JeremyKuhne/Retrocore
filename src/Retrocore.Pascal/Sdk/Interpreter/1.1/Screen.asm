; retrocore: style=strict
;; The 80-column screen on the two text pages: writing, control characters, scrolling, and moving the 40-column
;; view across it.
;;
;; Text page 1 shows 40 of the 80 columns, from <ViewLeft>, and text page 2 keeps the other 40: column c is at
;; (c - <ViewLeft>) in page 1 when that is 0-39, and otherwise at (c - <ViewLeft>) mod 80, less 40, in page 2.

; The screen.

;; The screen's columns.
SCREEN_COLUMNS = 80

;; The screen's rows.
SCREEN_ROWS = 24

;; Text page 1, which the view shows.
TEXT_PAGE_1 = $0400

;; Text page 2, which keeps the columns out of the view.
TEXT_PAGE_2 = $0800

;; The bits of a row, shifted right once, that give its page of the text page.
ROW_PAGE_BITS = %00000011

;; The bits of a row that give its third of the screen, each third 40 bytes on from the one above.
ROW_THIRD_BITS = %00011000

; Screen codes.

;; Bit 7 of a screen code: set for a normal character, clear for an inverse one.
SCREEN_NORMAL = $80

;; The bits of a screen code that give its character.
SCREEN_CHARACTER_BITS = $3F

;; A space, as a normal screen code.
SCREEN_SPACE = ' ' | SCREEN_NORMAL

; The control characters ScreenWrite acts on, besides CTRL_K and ASCII_LF.

; ScreenWrite's states, in EscapeState.

;; No sequence: <ScreenWrite> writes the character.
ESCAPE_NONE = 0

;; After ESC: <ScreenWrite> drops the character.
ESCAPE_DROP = 1

;; After GOTOXY's column: the character is its row.
ESCAPE_ROW = 2

;; After <CTRL_CARET>: the character is GOTOXY's column.
ESCAPE_COLUMN = 3

; Beeping.

;; The pause before <Beep>'s clicks, as <Wait> takes it.
BEEP_PAUSE = $40

;; Beep's clicks.
BEEP_CLICKS = 192

;; The time between <Beep>'s clicks, as <Wait> takes it.
BEEP_CLICK_TIME = $0C

; Following the cursor.

;; The cursor columns below this show the left half.
FOLLOW_LEFT_COLUMNS = 20

;; The cursor columns from this one show the right half.
FOLLOW_RIGHT_COLUMN = 77

;; The view's columns the cursor may be in before the view moves.
FOLLOW_VIEW_COLUMNS = 37

; The control characters' table.

;; Which column of <ScreenControlList> a <ScreenControl> entry gives: its code.
CONTROL_CODES = 0

;; Which column of <ScreenControlList> a <ScreenControl> entry gives: its routine's address.
CONTROL_ROUTINES = 1

;; One entry of <ScreenControls> or <ScreenControlRoutines>: a control character's code, or its routine.
;; Parameters:
;;   column = <CONTROL_CODES> or <CONTROL_ROUTINES>
;;   code = the control character
;;   routine = the routine <ScreenWrite> runs for it
.macro ScreenControl column, code, routine
    .if column = CONTROL_CODES
        .byte code
    .else
        .word routine
    .endif
.endmacro

;; The control characters <ScreenWrite> acts on, each with its routine, in the order of <ScreenControls> and
;; <ScreenControlRoutines>.
;; Parameters:
;;   column = <CONTROL_CODES> for <ScreenControls>, or <CONTROL_ROUTINES> for <ScreenControlRoutines>
.macro ScreenControlList column
    ScreenControl column, ASCII_ESC, ScreenEscape
    ScreenControl column, CTRL_CARET, ScreenGotoxy
    ScreenControl column, ASCII_CR, CarriageReturn
    ScreenControl column, ASCII_LF, LineFeed
    ScreenControl column, ASCII_BEL, Beep
    ScreenControl column, CTRL_UNDERSCORE, CursorUp
    ScreenControl column, CTRL_BACKSLASH, PutAndAdvance::CursorRight
    ScreenControl column, ASCII_BS, CursorLeft
    ScreenControl column, CTRL_L, ClearScreen
    ScreenControl column, CTRL_Y, HomeCursor
    ScreenControl column, CTRL_K, ClearToScreenEnd
    ScreenControl column, CTRL_RIGHT_BRACKET, ClearToLineEnd
    ScreenControl column, CTRL_R, InverseCapitalsOn
    ScreenControl column, CTRL_T, UpperCaseLock
.endmacro

;; The control characters <ScreenWrite> acts on, a byte each.
;; Also: CCHTBL (WK11)
ScreenControls:
    ScreenControlList CONTROL_CODES

;; The routine for each of <ScreenControls>, in the same order.
ScreenControlRoutines:
    ScreenControlList CONTROL_ROUTINES
    .assert * - ScreenControlRoutines = 2 * (ScreenControlRoutines - ScreenControls), "Each control has a routine."

;; Writes a character to the 80-column screen at the cursor, or acts on it as a control character or as part of an
;; <ASCII_ESC> or GOTOXY sequence.
;; In: Character = the character, Y = <ConsoleColumn>
;; Also: VOUT2 (A2PBIOS, WK11)
.proc ScreenWrite

;; The character <ConsoleWrite> gives <ScreenWrite> to write, which <PutScreen> also reads.
Character = CardPointer

;; GOTOXY's column, kept until its row comes.
GotoColumn = CardPointer + 1

;; The address of the control character's routine, for the JMP indirect.
ControlRoutine = PagesLeft

    ; In a sequence?
    lda EscapeState
    beq Plain
    cmp #ESCAPE_ROW
    bcc NextState
    beq Row

    ; GOTOXY's column: less 32, or 0 when that is out of range.
    lda Character
    sec
    sbc #' '
    bmi FirstColumn
    cmp #SCREEN_COLUMNS
    bcc KeepColumn
FirstColumn:
    lda #0
KeepColumn:
    sta GotoColumn
    jmp NextState

    ; GOTOXY's row: less 32, or 0 when that is out of range. Move the cursor, and end the sequence.
Row:
    lda Character
    sec
    sbc #' '
    bmi FirstRow
    cmp #SCREEN_ROWS
    bcc KeepRow
FirstRow:
    lda #0
KeepRow:
    sta CursorRow
    jsr SetTextLine
    lda GotoColumn
    sta ConsoleColumn
    lda #ESCAPE_NONE
    sta EscapeState
    rts

    ; Go on to the sequence's next state: ESCAPE_COLUMN to ESCAPE_ROW, or ESCAPE_DROP to ESCAPE_NONE.
NextState:
    .assert ESCAPE_ROW = ESCAPE_COLUMN - 1 && ESCAPE_NONE = ESCAPE_DROP - 1, "ScreenWrite steps EscapeState down."
    dec EscapeState
    rts

    ; A printable character: raise lower case, and write it as a normal screen code.
Plain:
    lda Character
    and #ASCII_BITS
    cmp #' '
    bcc Control
    cmp #'`'
    bcc Upper
    sbc #'a' - 'A'
Upper:
    and #SCREEN_CHARACTER_BITS
    ora #SCREEN_NORMAL
    jmp PutAndAdvance

    ; A control character: find it in ScreenControls, or ignore it.
Control:
    ldx #ScreenControlRoutines - ScreenControls - 1
FindControl:
    cmp ScreenControls,x
    beq RunControl
    dex
    bpl FindControl
    rts

    ; Run its routine.
RunControl:
    txa
    asl a
    tax
    lda ScreenControlRoutines+1,x
    sta ControlRoutine+1
    lda ScreenControlRoutines,x
    sta ControlRoutine
    jmp (ControlRoutine)
.endproc

;; ESC: drops the next character.
;; Keeps: X, Y
;; Also: DOESC (WK11)
.proc ScreenEscape
    lda #ESCAPE_DROP
    sta EscapeState
    rts
.endproc

;; GOTOXY: takes the next two characters as the column and the row.
;; Keeps: X, Y
;; Also: DOH1E (WK11)
.proc ScreenGotoxy
    lda #ESCAPE_COLUMN
    sta EscapeState
    rts
.endproc

;; CR: moves the cursor to column 0.
;; Out: Y = 0
;; Keeps: A, X
;; Also: DOCR (WK11)
.proc CarriageReturn
    ldy #0
    sty ConsoleColumn
    rts
.endproc

;; LF: moves the cursor down a row, or scrolls the screen up when it is on the bottom row.
;; Also: DOLF (WK11)
.proc LineFeed
    lda CursorRow
    cmp #SCREEN_ROWS - 1
    beq ScrollUp

;; Moves the cursor down a row, without checking for the bottom.
;; Keeps: X, Y
CursorDown:
    inc CursorRow
    jmp SetTextLine
.endproc

;; Scrolls all 80 columns up a row and clears the bottom row, leaving the cursor on the bottom row in its column.
.proc ScrollUp

;; The row above's address in text page 1, which <SaveTextLine> sets.
AboveLine = DiskReturn + 1

;; The row above's address in text page 2, which <SaveTextLine> sets.
AboveLine2 = SectorsLeft

    lda ConsoleColumn
    pha

    ; Start at the top row.
    ldx #0
    stx CursorRow
    jsr SetTextLine

    ; Copy each row up to the one above it.
NextRow:
    jsr SaveTextLine
    inx
    stx CursorRow
    jsr SetTextLine
    ldy #PAGE_COLUMNS - 1
CopyRow:
    lda (TextLine),y
    sta (AboveLine),y
    lda (TextLine2),y
    sta (AboveLine2),y
    dey
    bpl CopyRow
    cpx #SCREEN_ROWS - 1
    bne NextRow

    ; Clear the bottom row, and put the cursor's column back.
    lda #0
    sta ConsoleColumn
    jsr ClearToLineEnd
    pla
    sta ConsoleColumn
    rts
.endproc

;; BEL: clicks the speaker 192 times, after a pause. <ConsoleCheck> also beeps when <TypeAhead> is full.
;; Out: Y = 0
;; Keeps: X
;; Also: BELL (A2PBIOS), DOBEL (WK11)
.proc Beep

    lda #BEEP_PAUSE
    jsr Wait
    ldy #BEEP_CLICKS
Click:
    lda #BEEP_CLICK_TIME
    jsr Wait
    lda SPKR
    dey
    bne Click

;; Returns after the last click.
;; Also: ANRTS (WK11)
Done:
    rts
.endproc

;; Control-_: moves the cursor up a row, unless it is on the top row.
;; Keeps: X, Y
;; Also: CURSUP (WK11)
.proc CursorUp
    lda CursorRow
    beq Beep::Done
    dec CursorRow
    jmp SetTextLine
.endproc

;; BS: moves the cursor left, unless it is in column 0.
;; In: Y = <ConsoleColumn>
;; Keeps: A, X, Y
;; Also: DOBS (WK11)
.proc CursorLeft
    cpy #0
    beq Done
    dec ConsoleColumn
Done:
    rts
.endproc

;; Control-L: moves the cursor to the top left and clears the screen.
;; Also: DOFF (WK11), FORM (A2PBIOS)
.proc ClearScreen
    jsr HomeCursor
    jmp ClearToScreenEnd
.endproc

;; Control-Y: moves the cursor to row 0, column 0.
;; Out: Y = 0
;; Keeps: X
;; Also: HOMEC (WK11)
.proc HomeCursor
    ldy #0
    sty CursorRow
    sty ConsoleColumn
    jmp SetTextLine
.endproc

;; Control-K: clears from the cursor to the end of the screen; the cursor stays where it is.
;; Also: DOVT (WK11)
.proc ClearToScreenEnd
    lda ConsoleColumn
    pha
    lda CursorRow
    pha

    ; Clear the rest of this row, and all of each row below it.
NextRow:
    jsr ClearToLineEnd
    jsr CarriageReturn
    jsr LineFeed::CursorDown
    lda CursorRow
    cmp #SCREEN_ROWS
    bcc NextRow

    ; Put the cursor back.
    pla
    sta CursorRow
    pla
    sta ConsoleColumn
    jmp SetTextLine
.endproc

;; Control-]: clears from the cursor to column 79; the cursor stays where it is.
.proc ClearToLineEnd
    ldx ConsoleColumn
Clear:
    lda #SCREEN_SPACE
    jsr PutAndAdvance
    bcc Clear
    stx ConsoleColumn
    rts
.endproc

;; Writes a screen code at the cursor, and moves the cursor right unless it is in column 79.
;; In: A = the screen code
;; Out: carry = set when the cursor was in column 79, Y = <ConsoleColumn>
;; Keeps: X
;; Also: WCADVC (WK11)
.proc PutAndAdvance
    jsr PutScreen

;; Control-\: moves the cursor right, unless it is in column 79.
;; Out: carry = set when the cursor was in column 79, Y = <ConsoleColumn>
;; Keeps: A, X
;; Also: ADVC (WK11)
CursorRight:
    ldy ConsoleColumn
    cpy #SCREEN_COLUMNS - 1
    bcs Done
    iny
    sty ConsoleColumn
Done:
    rts
.endproc

;; Writes a screen code at the cursor, in text page 1 when its column is in the view and in page 2 when not, or with
;; A = 0 inverts the code there. While <InverseCapitals>' bit 7 is set, a capital letter goes in inverse.
;; In: A = the screen code, or 0 to invert, ScreenWrite::Character = the character, for the capital letter test
;; Keeps: X
;; Also: WRCH2S (WK11)
.proc PutScreen
    pha

    ; Make a capital letter inverse, if InverseCapitals says so.
    cmp #0
    beq Place
    bit InverseCapitals
    bpl Place
    lda ScreenWrite::Character
    and #ASCII_BITS
    cmp #'A'
    bcc Place
    cmp #'Z' + 1
    bcs Place
    pla
    eor #SCREEN_NORMAL
    pha

    ; Find the column in the view.
Place:
    lda ConsoleColumn
    sec
    sbc ViewLeft
    bmi LeftOfView
    cmp #PAGE_COLUMNS
    bcs RightOfView

    ; In the view: text page 1.
    tay
    pla
    bne Store
    lda (TextLine),y
    eor #SCREEN_NORMAL
Store:
    sta (TextLine),y
    rts

    ; Out of the view: text page 2, 40 columns round from the view.
LeftOfView:
    clc
    adc #PAGE_COLUMNS
    jmp InPage2
RightOfView:
    sec
    sbc #PAGE_COLUMNS
InPage2:
    tay
    pla
    bne Store2
    lda (TextLine2),y
    eor #SCREEN_NORMAL
Store2:
    sta (TextLine2),y
    rts
.endproc

;; Inverts the screen code at the cursor, which shows or hides the cursor.
;; Keeps: X
;; Also: INVERT (A2PBIOS, WK11)
.proc FlipCursor
    lda #0
    jmp PutScreen
.endproc

;; Points <TextLine> and <TextLine2> at the cursor's row in text pages 1 and 2.
;; Keeps: X, Y
;; Also: CVP2SP (WK11)
.proc SetTextLine
    ; The page: the row's bits 1-2.
    lda CursorRow
    lsr a
    and #ROW_PAGE_BITS
    ora #>TEXT_PAGE_1
    sta TextLine+1

    ; The low byte: $80 for an odd row (the carry from LSR, added with $7F), plus 40 for each third.
    lda CursorRow
    and #ROW_THIRD_BITS
    bcc EvenRow
    adc #$7F
EvenRow:
    sta TextLine
    asl a
    asl a
    ora TextLine
    sta TextLine

    ; Page 2's row is the same distance on.
    sta TextLine2
    lda TextLine+1
    clc
    adc #>(TEXT_PAGE_2 - TEXT_PAGE_1)
    sta TextLine2+1
    rts
.endproc

;; Copies <TextLine> and <TextLine2> to <ScrollUp>'s <ScrollUp::AboveLine> and <ScrollUp::AboveLine2>.
;; Keeps: X, Y
.proc SaveTextLine
    lda TextLine+1
    sta ScrollUp::AboveLine+1
    lda TextLine2+1
    sta ScrollUp::AboveLine2+1
    lda TextLine
    sta ScrollUp::AboveLine
    sta ScrollUp::AboveLine2
Done:
    rts
.endproc

;; Moves the 40-column view across the 80-column screen by some columns, rotating every row's 80 columns between
;; text pages 1 and 2 through <ScratchBuffer>, and adds them to <ViewLeft>.
;; In: A = the columns to move the view right, -40 to 40; 0 does nothing
.proc ScrollView
    tax
    beq SaveTextLine::Done
    lda CursorRow
    pha
    txa
    pha

    ; ScratchBuffer will hold a row in view order, and the moved view's column j is its column (j + A) mod 80.
    ; Keep (A - 40) mod 80, one past the column that becomes page 1's last.
    sec
    sbc #PAGE_COLUMNS
    bpl KeepStart
    clc
    adc #SCREEN_COLUMNS
KeepStart:
    pha

    ; From the bottom row up.
    lda #SCREEN_ROWS - 1
    sta CursorRow
NextRow:
    jsr SetTextLine

    ; Copy the row's 80 columns to ScratchBuffer, in view order: page 1, then page 2.
    ldy #PAGE_COLUMNS - 1
Gather:
    lda (TextLine),y
    sta ScratchBuffer,y
    lda (TextLine2),y
    sta ScratchBuffer + PAGE_COLUMNS,y
    dey
    bpl Gather

    ; Fill page 1 from its last column down, counting X down from there and round from 0 to 79.
    pla
    pha
    tax
    ldy #PAGE_COLUMNS - 1
Page1:
    dex
    bpl Page1Column
    ldx #SCREEN_COLUMNS - 1
Page1Column:
    lda ScratchBuffer,x
    sta (TextLine),y
    dey
    bpl Page1

    ; Then page 2 from its last column down, the view's columns 79 to 40, counting X on down.
    ldy #PAGE_COLUMNS - 1
Page2:
    dex
    bpl Page2Column
    ldx #SCREEN_COLUMNS - 1
Page2Column:
    lda ScratchBuffer,x
    sta (TextLine2),y
    dey
    bpl Page2
    dec CursorRow
    bpl NextRow

    ; Move ViewLeft, and put the cursor's row back.
    pla
    pla
    clc
    adc ViewLeft
    sta ViewLeft
    pla
    sta CursorRow
    jmp SetTextLine
.endproc

;; Moves the view to the cursor, when <ConsoleFlags>' <CONSOLE_FOLLOW> is set: to the left half for columns 0-19 and the
;; right half for 77-79; otherwise, when the cursor is left of the view, so that the view starts at it, and when it
;; is in or right of the view's column 37, so that it is in the view's column 36.
;; Also: ADJUST (A2PBIOS)
.proc FollowCursor
    lda ConsoleFlags
    lsr a
    bcc Done

    ; The left half?
    lda ConsoleColumn
    cmp #FOLLOW_LEFT_COLUMNS
    bcs NotLeftHalf
    jmp ViewHalf::ShowLeft

    ; In the view's first 37 columns?
NotLeftHalf:
    sec
    sbc ViewLeft
    bmi LeftOfView
    cmp #FOLLOW_VIEW_COLUMNS
    bcs RightOfView
Done:
    rts

    ; Right of them: the right half, or the view moved to put the cursor in its last one.
RightOfView:
    ldy ConsoleColumn
    cpy #FOLLOW_RIGHT_COLUMN
    bcs RightHalf
    sec
    sbc #FOLLOW_VIEW_COLUMNS - 1
    jmp ScrollView
RightHalf:
    jmp ViewHalf::ShowRight

    ; Left of the view: move it left to the cursor.
LeftOfView:
    jmp ScrollView
.endproc
