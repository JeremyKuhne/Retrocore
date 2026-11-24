; retrocore: style=strict
;; The Enhanced IIe's 80-column scrolling, clearing and column switching, $CBEB-$CDFD: scrolling up and down, the
;; clearing control characters, the 80-column line fill, 40 and 80 columns, MouseText on and off, leaving the
;; firmware with its hooks, the full windows, and the screen converted between 40 and 80 columns.

; Screen characters.

;; Bit 7 of a screen character: set for normal video, clear for inverse or flashing.
NORMAL_BIT = $80

; The text screen's size.

;; The columns of a 40-column line.
COLUMNS_40 = 40

;; The columns of an 80-column line.
COLUMNS_80 = 80

;; The lines of the text screen.
SCREEN_LINES = 24

;; The text screen's last line.
LAST_LINE = SCREEN_LINES - 1

;; The first of the four text lines that mixed graphics leave showing below the graphics.
MIXED_TEXT_TOP = 20

; Control: scrolling and clearing.
.scope Control continued

;; <Scroll>'s direction in Y: down, toward the bottom of the window.
SCROLL_DOWN = 0

;; <Scroll>'s direction in Y: up, toward the top of the window.
SCROLL_UP = 1

;; Control-W: scrolls the window up a line and clears its bottom line.
;; Keeps: X
;; Also: SCROLLUP (IIEROM82, IIETRM85), SCROLLUP80 (UNKN)
.proc ScrollUp
    ldy #SCROLL_UP
    ; Falls into Scroll.
.endproc

;; Scrolls the window a line, clears the line it leaves empty, and computes the cursor line's base.
;;
;; Each line is copied from its neighbor. In 80 columns the auxiliary and main halves of each line are copied
;; apart, with <WindowWidth> set for the while to the bytes of a half, which depend on whether <WindowLeft> and the
;; width are odd.
;; In: Y = <SCROLL_UP> or <SCROLL_DOWN>
;; Keeps: X
;; Also: SCROLL1 (IIEROM82), SCROLLIT (IIETRM85)
.proc Scroll

;; The direction, kept in <EightyColumns::SavedTextBase>, which the scroll borrows.
ScrollDirection = EightyColumns::SavedTextBase

    txa
    pha
    sty ScrollDirection
    lda WindowWidth
    pha
    bit Columns80State
    bpl Direction

    ; 80 columns: 80STORE on, and the half width. Overflow is set when the window's left edge is odd.
    sta Store80On
    lsr a
    tax
    lda WindowLeft
    lsr a
    clv
    bcc OddLeft
    bit OverflowByte

;; The half width is one less when the left edge and the width are both even.
;; Also: CHKRT (IIETRM85)
OddLeft:
    rol a
    eor WindowWidth
    lsr a
    bvs SetWidth
    bcs SetWidth
    dex

;; Also: GETST (IIETRM85)
SetWidth:
    stx WindowWidth
    lda Columns80State

;; Keeps the flags for each line: negative = 80 columns, and in 80 columns overflow = an odd left edge and carry = an
;; odd left edge plus width. Then the first line copied into: the window's top going up, its bottom line going down.
;; Also: GETST1 (IIETRM85)
Direction:
    php
    ldx WindowTop
    tya
    bne FirstLine
    ldx WindowBottom
    dex

;; Also: SETDBAS (IIETRM85)
FirstLine:
    txa
    jsr LineBase::Row

;; The line just computed is the next one copied into.
;; Also: SCRLIN (IIETRM85)
NextLine:
    lda TextBase
    sta ScrollBase
    lda TextBaseHigh
    sta ScrollBaseHigh
    lda ScrollDirection
    beq Down

    ; Up: the line below, until the window's bottom.
    inx
    cpx WindowBottom
    bcs Finish

;; The line copied from.
;; Also: SETSRC (IIETRM85)
SourceLine:
    txa
    jsr LineBase::Row
    ldy WindowWidth
    plp
    php
    bpl NextMain

    ; 80 columns: the auxiliary half first.
    lda Page2On
    tya
    beq AuxColumn0

;; Also: SCRLEVEN (IIETRM85)
CopyAux:
    lda (TextBase),y
    sta (ScrollBase),y
    dey
    bne CopyAux

;; Byte 0 of the auxiliary half, which is outside the window when its left edge is odd.
;; Also: SCRLFT (IIETRM85)
AuxColumn0:
    bvs MainHalf
    lda (TextBase),y
    sta (ScrollBase),y

;; Then the main half, one byte shorter when the left edge plus the width is odd.
;; Also: SKPLFT (IIETRM85)
MainHalf:
    lda Page2Off
    ldy WindowWidth
    bcs NextMain

;; The main half's bytes.
;; Also: SCRLODD (IIETRM85)
CopyMain:
    lda (TextBase),y
    sta (ScrollBase),y

;; The next byte of the main half.
;; Also: SKPRT (IIETRM85)
NextMain:
    dey
    bpl CopyMain
    bmi NextLine                    ; always

;; Down: the line above, until the window's top.
;; Also: SCRLDN (IIETRM85)
Down:
    dex
    cpx WindowTop
    bpl SourceLine

;; The width back, the empty line cleared, the cursor line's base, and X back.
;; Also: SCRLL3 (IIETRM85)
Finish:
    plp
    pla
    sta WindowWidth
    jsr ClearLine
    jsr LineBase
    pla
    tax
    rts
.endproc

;; Control-K: clears from the cursor to the end of its line, then each line below it in the window.
;; Keeps: X
;; Also: X_VT (IIEROM82, IIETRM85), CLREOP80 (UNKN)
.proc ClearToEndOfWindow
    jsr ClearToEndOfLine
    lda CV
    pha
    bpl CheckLine                   ; always: the line is 0-23

;; One line below.
;; Also: X_VTLOOP (IIEROM82, IIETRM85)
NextLine:
    jsr LineBase::Row
    jsr ClearLine

;; Also: X_VTNEXT (IIEROM82, IIETRM85)
CheckLine:
    inc CV
    lda CV
    cmp WindowBottom
    bcc NextLine

    ; The cursor's line back.
    pla
    sta CV
    jmp LineBase
.endproc

;; Control-L: homes the cursor and clears the window.
;; Keeps: X
;; Also: X_FF (IIEROM82, IIETRM85), CLRSCRN80 (UNKN)
.proc HomeAndClear
    jsr Home
    jmp ClearToEndOfWindow
.endproc

;; Control-Z: clears the cursor's line across the window.
;; Out: carry = set
;; Keeps: X
;; Also: X_SUB (IIEROM82, IIETRM85), CLRLINE80 (UNKN)
.proc ClearLine
    ldy #0
    beq ClearLineFrom               ; always
.endproc

;; Control-]: clears from the cursor to the end of its line.
;; Out: carry = set
;; Keeps: X
;; Also: X_GS (IIEROM82, IIETRM85), CLREOL80 (UNKN)
.proc ClearToEndOfLine
    ldy EightyColumns::CursorColumn
    ; Falls into ClearLineFrom.
.endproc

;; Stores blanks from column Y to the window's right edge: $A0, or $20 when <InverseMask> says inverse. In 80
;; columns <Fill80> stores them.
;;
;; In 40 columns it stores the first blank before it compares, so it stores one at Y even when Y is at the edge
;; or past it.
;; In: Y = the column
;; Out: carry = set
;; Keeps: X
;; Entry:
;;   Store40 = the 40-column loop, with A = the blank: Functions' 40-column clearing jumps here
;; Also: X_GSEOLZ (IIEROM82, IIETRM85)
.proc ClearLineFrom
    lda InverseMask
    and #NORMAL_BIT
    ora #' ' ^ NORMAL_BIT
    bit Columns80State
    bmi Fill80

;; Stores the blank in A from column Y to the window's right edge, in 40 columns.
;; In: A = the blank, Y = the column
;; Also: CLR40 (IIETRM85)
Store40:
    sta (TextBase),y
    iny
    cpy WindowWidth
    bcc Store40
    rts
.endproc

.endscope

;; The 80-column firmware's 40/80-column conversion: the screen converted between 40 and 80 columns, a line at a
;; time, when Control-Q or Control-R changes the width or the firmware quits.
;;
;; In 80 columns a line's even columns are in auxiliary memory and its odd ones in main memory, each half at byte
;; column/2, so <Columns::To80> spreads each 40-column line over both halves and blanks columns 40-79 with
;; <Columns::ClearRightHalf>, and <Columns::To40> gathers columns 0-39 back into main memory. Both end in
;; <Columns::Finish>, which computes the cursor line's base.
.scope Columns

;; Blanks columns 40-79 of the 80-column line at <TextBase>, through <Fill80>: normal blanks, or inverse ones when
;; <InverseMask> says so.
;; Out: carry = set
;; Keeps: X
;; Also: CLRHALF (IIEROM82, IIETRM85), CLRRIGHT (UNKN)
.proc ClearRightHalf
    stx ScrollBase
    ldx #<-COLUMNS_40
    ldy #COLUMNS_40 / 2
    lda InverseMask
    and #' '
    jmp Fill80::Aux
.endproc

.endscope

;; Stores a character in an 80-column line's columns from Y to the window's right edge, alternating between the
;; auxiliary memory's even columns and the main memory's odd ones.
;;
;; At $CCBD. The columns are the window's, from <WindowLeft>; an odd left edge starts the line in main memory.
;; In: A = the character, Y = the column
;; Out: carry = set
;; Keeps: A, X
;; Entry:
;;   Aux = stores from an auxiliary byte: Y = the byte, X = minus the columns to store, ScrollBase = X to put back
;; Also: FILL80 (UNKN), CLR80 (IIETRM85)
.proc Fill80
.assert * = $CCBD, "Fill80 must stay at $CCBD."
    stx ScrollBase

    ; X counts the columns up to 0, and Y is the first column's byte.
    pha
    tya
    pha
    sec
    sbc WindowWidth
    tax
    tya
    lsr a
    tay

    ; The carry: the first column is odd on the screen, so in main memory. An odd left edge and an odd column put
    ; the first column's auxiliary byte one on.
    pla
    eor WindowLeft
    ror a
    bcs Start
    bpl Start
    iny

;; Also: CLR0 (IIETRM85)
Start:
    pla
    bcs Main

;; Stores in an auxiliary byte, then in the main byte after it.
;; In: A = the character, Y = the byte, X = minus the columns to store, ScrollBase = X to put back
;; Also: CLR2 (IIETRM85)
Aux:
    bit Page2On
    sta (TextBase),y
    bit Page2Off
    inx
    beq Done

;; Also: CLR1 (IIETRM85)
Main:
    sta (TextBase),y
    iny
    inx
    bne Aux

;; X back.
Done:
    ldx ScrollBase
    sec
    rts
.endproc

; Control: 40 and 80 columns, MouseText, and leaving the firmware.
.scope Control continued

;; Control-Q, unless the Pascal protocol is active: converts the screen to 40 columns if 80 columns are on, then
;; goes to <FinishColumns>.
;; Keeps: X
;; Entry:
;;   Convert = the same without the Pascal check: <QuitFirmware> enters here
;; Also: X_DC1 (IIEROM82, IIETRM85), SET40COL (UNKN)
.proc Columns40
    lda EightyColumns::Mode
    bmi SetWindowTop::Done

;; Converts the screen to 40 columns if 80 columns are on, whether or not the Pascal protocol is active.
;; Also: X_DC1A (IIETRM85)
Convert:
    jsr SetWindowTop
    bit Columns80State
    bpl FinishColumns
    jsr Columns::To40
    bcc FinishColumns               ; always: with the left edge on the screen, To40's line base adds no carry
.endproc

;; Control-R: when auxiliary memory answers and 80 columns are off, converts the screen to 80 columns, then goes
;; to <FinishColumns>.
;;
;; This source called it SET80COL, the name Apple's listings give the 80STORE switch, <Store80On>.
;; Keeps: X
;; Also: X_DC2 (IIEROM82, IIETRM85)
.proc Columns80
    jsr TestAuxMemory
    bne SetWindowTop::Done
    bit Columns80State
    bmi FinishColumns
    jsr Columns::To80
    ; Falls into FinishColumns.
.endproc

;; Finishes 40 or 80 columns: the window's left edge added into the cursor's column, which 40 columns keep at 39
;; at most, the Monitor's <::CursorColumn> to match, the line's base, and the full window and its top.
;; Keeps: X
;; Also: X_DC1B (IIETRM85)
.proc FinishColumns
    lda EightyColumns::CursorColumn
    clc
    adc WindowLeft
    bit Columns80State
    bmi StoreColumn
    cmp #COLUMNS_40
    bcc StoreColumn
    lda #COLUMNS_40 - 1

;; The column, for the firmware and the Monitor.
;; Also: X_DC1C (IIETRM85)
StoreColumn:
    sta EightyColumns::CursorColumn
    sta CursorColumn
    lda CV
    jsr RowBase
    bit Columns80State
    bpl Window40
    jsr FullWindow80                ; DO80 in Apple's listing
    beq SetWindowTop                ; always: FullWindow80 leaves A = 0
.endproc

;; Sets the full 40-column window, below the graphics when graphics are shown.
;; Keeps: X, Y
;; Also: DO40 (IIETRM85)
.proc Window40
    jsr FullWindow40
    ; Falls into SetWindowTop.
.endproc

;; Sets the window's top line: line 0, or line 20 when graphics are shown.
;; Keeps: X, Y
;; Entry:
;;   Done = the return <Columns40> and <Columns80> share
;; Also: SETTOP (IIETRM85)
.proc SetWindowTop
    lda #0
    bit TextState
    bmi StoreTop
    lda #MIXED_TEXT_TOP

;; Stores the top line.
;; Also: DO40A (IIETRM85)
StoreTop:
    sta WindowTop

;; The return <Columns40> and <Columns80> share.
;; Also: X_DC1RTS (IIETRM85)
Done:
    rts
.endproc

;; Control-X: MouseText off, <MODE_MOUSETEXT_OFF>.
;; Keeps: X, Y
;; Also: MOUSEOFF (IIETRM85), MTEXTOFF (UNKN)
.proc MouseTextOff
    lda EightyColumns::Mode
    ora #MODE_MOUSETEXT_OFF
    bne MouseTextOn::StoreMode      ; always: the mode is not 0
.endproc

;; The escape key's code as a control character, Control-[: MouseText on, <MODE_MOUSETEXT_OFF> clear.
;; Keeps: X, Y
;; Entry:
;;   StoreMode = stores A as the mode: <MouseTextOff> enters here
;; Also: MTEXTON (UNKN), MOUSEON (IIETRM85)
.proc MouseTextOn
    lda EightyColumns::Mode
    and #MODE_MOUSETEXT_OFF ^ $FF

;; Stores A as the mode.
;; In: A = the mode
;; Also: SMOUSE (IIETRM85)
StoreMode:
    sta EightyColumns::Mode
    rts
.endproc

;; Control-U, unless the Pascal protocol is active: the full 40-column window, <QuitFirmware>, and the Monitor's
;; screen and keyboard hooks.
;; Keeps: X
;; Entry:
;;   SetInputHook = sets the input hook to the Monitor's <KeyboardIn>: CharacterIo's entry calls it
;; Also: X_NAK (IIEROM82, IIETRM85), QUIT80 (UNKN)
.proc Quit
    lda EightyColumns::Mode
    bmi SetOutputHook::Done
    jsr Window40
    jsr QuitFirmware
    jsr SetOutputHook

;; Sets the input hook to the Monitor's <KeyboardIn>.
;; Keeps: X, Y
;; Also: SETKEYIN (IIETRM85)
SetInputHook:
    lda #>KeyboardIn
    sta InputHookHigh
    lda #<KeyboardIn
    sta InputHook
    rts
.endproc

;; Sets the output hook to the Monitor's <ScreenOut>.
;; Keeps: X, Y
;; Entry:
;;   Done = the return <Quit> branches to in the Pascal protocol
;; Also: CSWTOCOUT1 (UNKN), SETCOUT1 (IIETRM85)
.proc SetOutputHook
    lda #>ScreenOut
    sta OutputHookHigh
    lda #<ScreenOut
    sta OutputHook

;; The return <Quit> branches to in the Pascal protocol.
;; Also: SKRTS (IIETRM85)
Done:
    rts
.endproc

.endscope

;; Sets the window to the whole 40-column screen: 40 columns by 24 lines from the top left.
;;
;; At $CD6D.
;; Out: A = 0, zero = set
;; Keeps: X, Y
;; Also: FULLWND (UNKN), FULL40 (IIETRM85)
.proc FullWindow40
.assert * = $CD6D, "FullWindow40 must stay at $CD6D."
    lda #COLUMNS_40
    bne FullWindow80::Store         ; always
.endproc

;; Sets the window to the whole 80-column screen: 80 columns by 24 lines from the top left.
;;
;; At $CD71.
;; Out: A = 0, zero = set
;; Keeps: X, Y
;; Entry:
;;   Store = sets the window A columns wide: <FullWindow40> enters here
;; Also: FULL80 (IIEROM82, IIETRM85)
.proc FullWindow80
.assert * = $CD71, "FullWindow80 must stay at $CD71."
    lda #COLUMNS_80

;; Sets the window A columns wide, 24 lines, from the top left.
;; In: A = the width
;; Also: SAVWDTH (IIETRM85)
Store:
    sta WindowWidth
    lda #SCREEN_LINES
    sta WindowBottom
    lda #0
    sta WindowTop
    sta WindowLeft
    rts
.endproc

;; Leaves the 80-column firmware: the screen converted to 40 columns if 80 columns are on, the primary character
;; set, and <MODE_INACTIVE>.
;;
;; At $CD80.
;; Keeps: X
;; Also: QUIT (IIEROM82, IIETRM85), OFF80 (UNKN)
.proc QuitFirmware
.assert * = $CD80, "QuitFirmware must stay at $CD80."
    bit Columns80State
    bpl Off
    jsr Control::Columns40::Convert

;; The primary character set, and the firmware off.
;; Also: QUIT2 (IIETRM85)
Off:
    sta AlternateCharactersOff
    lda #MODE_INACTIVE
    sta EightyColumns::Mode
    rts
.endproc

; Columns: the 40/80-column conversion.
.scope Columns continued

;; The column the conversions are at: <ScrollBase>, which they borrow.
Column = ScrollBase

;; Converts the screen from 80 to 40 columns, keeping columns 0-39 of each line, then turns 80STORE and 80 columns
;; off.
;;
;; It converts from the last line up to the window's top line, then computes the cursor line's base.
;; Keeps: X
;; Also: SCRN84 (IIEROM82, IIETRM85), SCR80TO40 (UNKN)
.proc To40
    txa
    pha
    ldx #LAST_LINE
    sta Store80On

;; Also: SCR40 (IIEROM82), SCR1 (IIETRM85)
NextLine:
    txa
    jsr RowBase
    ldy #COLUMNS_40 - 1

;; Column Y's byte is at Y/2: an even column's in auxiliary memory.
;; Also: SCR2 (IIETRM85)
NextColumn:
    sty Column
    tya
    lsr a
    bcs Main
    bit Page2On

;; Also: SCR3 (IIETRM85)
Main:
    tay
    lda (TextBase),y
    bit Page2Off
    ldy Column
    sta (TextBase),y
    dey
    bpl NextColumn
    dex
    bmi Done
    cpx WindowTop
    bcs NextLine

;; Turns 80STORE and 80 columns off, then goes to <Finish>.
;; Also: SCR40RET (IIEROM82), SCR4 (IIETRM85)
Done:
    sta Store80Off
    sta Columns80Off
    jmp Finish
.endproc

;; Converts the screen from 40 to 80 columns, spreading columns 0-39 of each line over both halves and blanking
;; columns 40-79 with <ClearRightHalf>, then turns 80 columns on.
;;
;; It converts from the last line up to the window's top line, then computes the cursor line's base.
;; Keeps: X
;; Also: SCRN48 (IIEROM82, IIETRM85), SCR40TO80 (UNKN)
.proc To80
    txa
    pha
    ldx #LAST_LINE

;; Also: SCR80 (IIEROM82), SCR5 (IIETRM85)
NextLine:
    txa
    jsr RowBase
    ldy #0
    sta Store80On

;; Column Y goes to byte Y/2: an even column's in auxiliary memory.
;; Also: SCR6 (IIETRM85)
NextColumn:
    lda (TextBase),y
    sty Column                      ; SCR8 in Apple's listing
    pha
    tya
    lsr a
    bcs Main
    sta Page2On

;; Also: SCR7 (IIETRM85)
Main:
    tay
    pla
    sta (TextBase),y
    sta Page2Off
    ldy Column
    iny
    cpy #COLUMNS_40
    bcc NextColumn
    jsr ClearRightHalf
    dex
    bmi Done
    cpx WindowTop
    bcs NextLine

;; Turns 80 columns on.
;; Also: SCR80RET (IIEROM82), SCR9 (IIETRM85)
Done:
    sta Columns80On
    ; Falls into Finish.
.endproc

;; Finishes a conversion: computes the cursor line's base and takes X back from the stack, where <To40> and <To80>
;; push it.
;; Keeps: Y
;; Also: SCRNRET (IIEROM82, IIETRM85)
.proc Finish
    jsr LineBase
    pla
    tax
    rts
.endproc

.endscope
