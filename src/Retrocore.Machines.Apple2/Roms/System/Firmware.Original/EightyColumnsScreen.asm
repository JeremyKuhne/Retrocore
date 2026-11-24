; retrocore: style=strict
;; The original IIe's 80-column control characters, $CBFD-$CDDA: the end of the carriage return, the cursor moves,
;; normal and inverse, the control characters' handler table, the line feed and scrolling, the clearing, and 40 and
;; 80 columns; then the full 80-column window and leaving the 80-column firmware.

; The masks <InverseMask> holds for the 80-column firmware.

;; <InverseMask> for normal text: the 80-column firmware stores characters as they are.
MASK_NORMAL = $FF

;; <InverseMask> for inverse text: the 80-column firmware stores characters with bit 7 clear.
MASK_INVERSE = $7F

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

; Control: the end of the carriage return, and the cursor moves.
.scope Control continued

;; <ScrollLines>'s direction in X, and the index of its <ScrollSteps> and <ScrollEdges> entries: down, toward
;; the bottom of the window.
SCROLL_DOWN = 0

;; <ScrollLines>'s direction in X: up, toward the top of the window.
SCROLL_UP = 1

;; Finishes a carriage return: column 0, then a line feed unless the Pascal protocol is active.
;;
;; <Perform> runs into it from the code that clears the rest of the line during BASIC's input.
;; Keeps: X
;; Also: X_CRPAS (IIEROM82)
.proc FinishReturn
    lda #0
    sta EightyColumns::CursorColumn

    ; Pascal does its own line feeds.
    lda EightyColumns::Mode
    and #MODE_PASCAL
    bne Done
    jsr LineFeed

;; Also: X_CRRET (IIEROM82)
Done:
    rts
.endproc

;; Control-Y: moves the cursor to the window's top line, column 0, and computes the line's base.
;; Out: A = 0
;; Keeps: X, Y
;; Also: X_EM (IIEROM82, IIETRM85), HOMECURSOR (UNKN)
.proc Home
    lda WindowTop
    sta EightyColumns::CursorLine
    lda #0
    sta EightyColumns::CursorColumn
    jmp LineBase
.endproc

;; Control-Z: clears the cursor's line across the window, in the current video.
;; Out: Y = $FF
;; Keeps: X
;; Also: X_SUB (IIEROM82, IIETRM85), CLRLINE80 (UNKN)
.proc ClearLine
    ldy WindowWidth
    dey

;; Stores a blank from column Y down to column 0.
;; In: Y = the column
;; Also: X_SUB80 (IIEROM82)
Blank:
    lda #' '

;; Also: X_SUBLP (IIEROM82)
Loop:
    jsr Screen::StoreCharacter
    dey
    bpl Loop
    rts
.endproc

;; Control-\: moves the cursor right; at the window's right edge, does a <CarriageReturn at X_CR> instead.
;; Keeps: X
;; Also: X_FS (IIEROM82, IIETRM85), FWDSPACE80 (UNKN)
.proc Right
    inc EightyColumns::CursorColumn
    lda EightyColumns::CursorColumn
    cmp WindowWidth
    bcc Done
    jsr CarriageReturn

;; Also: X_FSRET (IIEROM82, IIETRM85)
Done:
    rts
.endproc

;; Control-_: moves the cursor up a line, but not above the window's top line.
;; Keeps: X, Y
;; Also: X_US (IIEROM82, IIETRM85), UP80 (UNKN)
.proc Up
    dec EightyColumns::CursorLine
    bmi AtTop
    lda EightyColumns::CursorLine
    cmp WindowTop
    bcs SetBase

;; Undoes the step: the cursor was on the window's top line. On line 0 the line's base is already right.
;; Also: X_US1 (IIEROM82)
AtTop:
    inc EightyColumns::CursorLine
    beq Done

;; Also: X_US2 (IIEROM82)
SetBase:
    jsr LineBase

;; Also: X_USRET (IIEROM82)
Done:
    rts
.endproc

;; Control-N: normal video: clears <MODE_INVERSE> and sets <InverseMask> to <MASK_NORMAL>.
;; Keeps: X
;; Also: X_SO (IIEROM82, IIETRM85), NORMAL80 (UNKN)
.proc Normal
    lda EightyColumns::Mode
    and #MODE_INVERSE ^ $FF
    ldy #MASK_NORMAL
    bne StoreVideo                  ; always: the mask is not 0
.endproc

;; Control-O: inverse video: sets <MODE_INVERSE> and sets <InverseMask> to <MASK_INVERSE>.
;; Keeps: X
;; Also: X_SI (IIEROM82, IIETRM85), INVERSE80 (UNKN)
.proc Inverse
    lda EightyColumns::Mode
    ora #MODE_INVERSE
    ldy #MASK_INVERSE
    ; Falls into StoreVideo.
.endproc

;; Stores the mode byte and the inverse mask.
;; In: A = the mode, Y = the mask
;; Keeps: A, X, Y
;; Also: STUFFINV (IIEROM82, IIETRM85), SETINVFLG (UNKN)
.proc StoreVideo
    sta EightyColumns::Mode
    sty InverseMask
    rts
.endproc

;; The handlers <ControlHandler> and <NoControlHandler> have defined so far: at the end, the length of
;; <HandlersLow> and <HandlersHigh>.
.set HandlerCount, 0

;; One control character's handler: CONTROL_HANDLER_n, the routine's address minus one, which <Control::Jump> pushes so
;; that its RTS lands on the routine.
;; Parameters:
;;   code = the control character, with bit 7 clear: the next one after the last entry's, from Control-G
;;   routine = the handler
.macro ControlHandler code, routine
    .assert code = CONTROL_G + HandlerCount, "Each handler sits at its control character's place."
    .ident(.sprintf("CONTROL_HANDLER_%d", HandlerCount)) = routine - 1
    .set HandlerCount, HandlerCount + 1
.endmacro

;; A control character with no handler: its CONTROL_HANDLER_n is 0, whose high byte <Control::Perform> takes as none.
.macro NoControlHandler
    .ident(.sprintf("CONTROL_HANDLER_%d", HandlerCount)) = 0
    .set HandlerCount, HandlerCount + 1
.endmacro

    ; The handlers, Control-G to Control-_ in order.
    ControlHandler CONTROL_G, Bell
    ControlHandler CONTROL_H, Left
    ; Control-I.
    NoControlHandler
    ControlHandler CONTROL_J, LineFeed
    ControlHandler CONTROL_K, ClearToEndOfWindow
    ControlHandler CONTROL_L, HomeAndClear
    ControlHandler CONTROL_M, CarriageReturn
    ControlHandler CONTROL_N, Normal
    ControlHandler CONTROL_O, Inverse
    ; Control-P.
    NoControlHandler
    ControlHandler CONTROL_Q, Columns40
    ControlHandler CONTROL_R, Columns80
    ; Control-S and Control-T.
    NoControlHandler
    NoControlHandler
    ControlHandler CONTROL_U, Quit
    ControlHandler CONTROL_V, ScrollDown
    ControlHandler CONTROL_W, ScrollUp
    ; Control-X.
    NoControlHandler
    ControlHandler CONTROL_Y, Home
    ControlHandler CONTROL_Z, ClearLine
    ; Control-[.
    NoControlHandler
    ControlHandler CONTROL_BACKSLASH, Right
    ControlHandler CONTROL_RIGHT_BRACKET, ClearToEndOfLine
    ; Control-^.
    NoControlHandler
    ControlHandler CONTROL_UNDERSCORE, Up
.assert HandlerCount = CONTROL_UNDERSCORE - CONTROL_G + 1, "The tables cover Control-G to Control-_."

;; The low bytes of each control character's handler address minus one, Control-G to Control-_: <Perform> reads
;; the entry for code Y at HandlersLow - <CONTROL_G> + Y.
;; Also: CTLADL (IIEROM82, IIETRM85), CTRLLOW (UNKN)
HandlersLow:
.repeat HandlerCount, index
    .byte <.ident(.sprintf("CONTROL_HANDLER_%d", index))
.endrepeat

;; The high bytes of each control character's handler address minus one; 0 where the character has none.
;; Also: CTLADH (IIEROM82, IIETRM85), CTRLPAGE (UNKN)
HandlersHigh:
.repeat HandlerCount, index
    .byte >.ident(.sprintf("CONTROL_HANDLER_%d", index))
.endrepeat

;; Control-J, a line feed: moves the cursor down a line; on the window's bottom line, scrolls the window up instead.
;; Keeps: X
;; Also: X_LF (IIEROM82, IIETRM85), LF80 (UNKN)
.proc LineFeed
    inc EightyColumns::CursorLine
    lda EightyColumns::CursorLine
    cmp WindowBottom
    bcs AtBottom
    jmp ToLineBase

;; Puts the cursor back on the window's bottom line, then scrolls up.
;; Also: X_LF2 (IIEROM82, IIETRM85), SCROLL80 (UNKN)
AtBottom:
    ldy WindowBottom
    dey
    sty EightyColumns::CursorLine
    ; Falls into ScrollUp.
.endproc

;; Control-W: scrolls the window up a line and clears its bottom line.
;; Keeps: X
;; Also: SCROLLUP (IIEROM82, IIETRM85), SCROLLUP80 (UNKN)
.proc ScrollUp
    txa
    pha
    ldx #SCROLL_UP
    bne Scroll                      ; always: SCROLL_UP is not 0
.endproc

;; Control-V: scrolls the window down a line and clears its top line.
;; Keeps: X
;; Also: SCROLLDN (IIEROM82, IIETRM85), SCROLLDN80 (UNKN)
.proc ScrollDown
    txa
    pha
    ldx #SCROLL_DOWN
    ; Falls into Scroll.
.endproc

;; Scrolls the window a line, then goes to <FinishScroll>.
;;
;; In 80 columns, it scrolls main memory's half of each line and then auxiliary memory's, with <WindowWidth>
;; halved while it does.
;; X as the caller had it is on the stack, for <FinishScroll>.
;; In: X = <SCROLL_UP> or <SCROLL_DOWN>
;; Also: SCROLL1 (IIEROM82), SCROLLIT (IIETRM85)
.proc Scroll
    bit Columns80State
    bpl Lines

    ; 80 columns: each half of a line is half as wide.
    lda WindowWidth
    pha
    lsr WindowWidth

;; Scrolls main memory's half, the whole line in 40 columns.
;; Also: SCROLL2 (IIEROM82)
Lines:
    jsr ScrollLines
    bit Columns80State
    bpl FinishScroll

    ; Then auxiliary memory's half, with interrupts off while it is switched in.
    php
    sei
    lda Page2On
    jsr ScrollLines
    lda Page2Off
    plp

    ; The width back.
    pla
    sta WindowWidth
    bne FinishScroll                ; always: the width is not 0
.endproc

;; Moves the window's lines a line up or down in the text memory switched in, from the edge <ScrollEdges> gives
;; by the step <ScrollSteps> gives.
;;
;; Scrolling down copies one line more at the end, the window's top line into the one below it.
;; In: X = <SCROLL_UP> or <SCROLL_DOWN>
;; Keeps: X
;; Also: SCRLSUB (IIEROM82)
.proc ScrollLines

;; Page zero, which <ScrollEdges>' entries index.
PageZero = SlotPointer

    ldy ScrollEdges,x
    lda a:PageZero,y
    cpx #SCROLL_UP
    bcs Start

    ; Down: from the line above the window's bottom (the carry is clear, so this takes one off).
    sbc #0

;; Also: MSCRL0 (IIEROM82)
Start:
    pha
    jsr LineBase::Row

;; The line just computed is the next one copied into.
;; Also: MSCRL1 (IIEROM82)
NextLine:
    lda TextBase
    sta ScrollBase
    lda TextBaseHigh
    sta ScrollBaseHigh
    ldy WindowWidth
    dey

    ; The line copied from, until it is the window's edge: <WindowTop> going down, <WindowBottom> going up.
    pla
    clc
    adc ScrollSteps,x
    cmp WindowTop,x
    beq LastLine
    pha
    jsr LineBase::Row

;; Also: MSCRL2 (IIEROM82)
CopyByte:
    lda (TextBase),y
    sta (ScrollBase),y
    dey
    bpl CopyByte
    bmi NextLine                    ; always

;; Going down, the window's top line is the last copied.
;; Also: MSCRLRET (IIEROM82)
LastLine:
    cpx #SCROLL_DOWN
    bne Done
    jsr LineBase::Row

;; Also: ONEMORE (IIEROM82)
CopyLast:
    lda (TextBase),y
    sta (ScrollBase),y
    dey
    bpl CopyLast

;; Also: MSCRLRTS (IIEROM82)
Done:
    rts
.endproc

;; Finishes a scroll: clears the line it left empty, the bottom line going up and the top line going down, puts X
;; back, and computes the cursor line's base. Falls into <ToLineBase>.
;; X as the caller of <ScrollUp> or <ScrollDown> had it is on the stack.
;; In: X = <SCROLL_UP> or <SCROLL_DOWN>
;; Also: X_SCRLRET (IIEROM82)
.proc FinishScroll
    ldy WindowTop,x
    txa
    beq ClearEmpty

    ; Up: <WindowTop>,X was <WindowBottom>, the line below the window.
    dey

;; Also: X_SCRLRET2 (IIEROM82)
ClearEmpty:
    tya
    jsr LineBase::Row
    pla
    tax
    jsr ClearLine
    ; Falls into ToLineBase.
.endproc

;; Computes the base of the cursor's line, the exit <LineFeed> and <ClearToEndOfWindow> branch to.
;; Also: X_LFRET (IIEROM82)
ToLineBase:
    jmp LineBase

;; Control-K: clears from the cursor to the end of its line, then each line below it in the window.
;; Keeps: X
;; Also: X_VT (IIEROM82, IIETRM85), CLREOP80 (UNKN)
.proc ClearToEndOfWindow
    jsr ClearToEndOfLine
    lda EightyColumns::CursorLine
    pha
    bpl CheckLine                   ; always: the line is 0-23

;; Also: X_VTLOOP (IIEROM82, IIETRM85)
NextLine:
    jsr LineBase
    jsr ClearLine

;; Also: X_VTNEXT (IIEROM82, IIETRM85)
CheckLine:
    inc EightyColumns::CursorLine
    lda EightyColumns::CursorLine
    cmp WindowBottom
    bcc NextLine

    ; The cursor's line back.
    pla
    sta EightyColumns::CursorLine
    bpl ToLineBase                  ; always
.endproc

;; Control-L: homes the cursor and clears the window.
;; Keeps: X
;; Also: X_FF (IIEROM82, IIETRM85), CLRSCRN80 (UNKN)
.proc HomeAndClear
    jsr Home
    jmp ClearToEndOfWindow
.endproc

;; Control-]: clears from the cursor to the end of its line.
;; Out: Y = <WindowWidth>
;; Keeps: X
;; Also: X_GS (IIEROM82, IIETRM85), CLREOL80 (UNKN)
.proc ClearToEndOfLine
    ldy EightyColumns::CursorColumn
    jmp ClearLineFrom::Check
.endproc

;; Stores blanks in the current video from column Y to the window's right edge.
;;
;; It stores the first blank before it compares, so it stores one at Y even when Y is at the edge or past it.
;; In: Y = the column
;; Out: Y = the column after the last blank, <WindowWidth> when Y was inside the window, carry = set
;; Keeps: X
;; Entry:
;;   Check = stores nothing when Y is at the edge or past it: <ClearToEndOfLine> enters here
;; Also: X_GSEOLZ (IIEROM82, IIETRM85)
.proc ClearLineFrom
    lda #' '
    jsr Screen::StoreCharacter
    iny

;; Stores blanks from column Y to the window's right edge, but none when Y is at the edge or past it.
;; In: Y = the column
;; Also: X_GS2 (IIEROM82)
Check:
    cpy WindowWidth
    bcc ClearLineFrom
    rts
.endproc

;; Control-Q: sets the full 40-column window, below the graphics when graphics are shown, and converts the screen
;; with <Columns::To40> if 80 columns are on.
;; Keeps: X
;; Also: X_DC1 (IIEROM82, IIETRM85), SET40COL (UNKN)
.proc Columns40
    lda #0
    sta WindowLeft
    bit TextState
    bmi SetTop
    lda #MIXED_TEXT_TOP

;; Also: X_DC1B (IIEROM82)
SetTop:
    sta WindowTop
    lda #SCREEN_LINES
    sta WindowBottom
    lda #COLUMNS_40
    sta WindowWidth
    bit Columns80State
    bpl Done
    jsr Columns::To40

;; Also: X_DC1RTS (IIEROM82)
Done:
    rts
.endproc

;; Control-R: when auxiliary memory answers, sets the full 80-column window, below the graphics when graphics are
;; shown, and converts the screen with <Columns::To80> unless 80STORE is already on.
;; Keeps: X
;; Also: X_DC2 (IIEROM82, IIETRM85)
.proc Columns80
    jsr TestAuxMemory
    bne Quit::Done
    jsr FullWindow80
    bit TextState
    bmi CheckStore80
    lda #MIXED_TEXT_TOP
    sta WindowTop

;; Converts the screen only while 80STORE is off.
;; Also: X_DC2B (IIEROM82)
CheckStore80:
    bit Store80State
    bmi Quit::Done
    jmp Columns::To80
.endproc

;; Control-U: leaves the 80-column firmware with <QuitFirmware>, unless the Pascal protocol is active.
;; Entry:
;;   Done = the return <Columns80> shares
;; Also: X_NAK (IIEROM82, IIETRM85), QUIT80 (UNKN)
.proc Quit
    lda EightyColumns::Mode
    and #MODE_PASCAL
    bne Done
    jsr QuitFirmware

;; The return <Columns80> shares.
;; Also: X_NAKRET (IIEROM82), X_DC2RET (IIEROM82)
Done:
    rts
.endproc

.endscope

;; Sets the window to the whole 80-column screen: 80 columns by 24 lines from the top left.
;;
;; At $CD9B.
;; Out: A = 24
;; Keeps: X, Y
;; Also: FULL80 (IIEROM82, IIETRM85)
.proc FullWindow80
.assert * = $CD9B, "FullWindow80 must stay at $CD9B."
    lda #0
    sta WindowTop
    sta WindowLeft
    lda #COLUMNS_80
    sta WindowWidth
    lda #SCREEN_LINES
    sta WindowBottom
    rts
.endproc

;; Leaves the 80-column firmware: the full 40-column window, the screen converted to 40 columns if 80 columns are
;; on, the cursor on the last line at column 0, the primary character set, <MODE_INACTIVE>, and the Monitor's
;; screen and keyboard hooks back.
;;
;; At $CDAA.
;; Also: QUIT (IIEROM82, IIETRM85), OFF80 (UNKN)
.proc QuitFirmware
.assert * = $CDAA, "QuitFirmware must stay at $CDAA."
    lda #0
    sta WindowTop
    sta WindowLeft
    lda #SCREEN_LINES
    sta WindowBottom
    lda #COLUMNS_40
    sta WindowWidth
    bit Columns80State
    bpl HomeBottom
    jsr Columns::To40

;; The cursor on the last line, at column 0.
;; Also: QUIT2 (IIEROM82)
HomeBottom:
    lda #LAST_LINE
    sta EightyColumns::CursorLine
    jsr LineBase
    lda #0
    sta EightyColumns::CursorColumn

    ; The primary character set, the firmware off, and the Monitor's hooks.
    sta AlternateCharactersOff
    lda #MODE_INACTIVE
    sta EightyColumns::Mode
    jsr SetScreen
    jmp SetKeyboard
.endproc
