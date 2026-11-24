; retrocore: style=strict
;; The 80-column firmware's $C9F0-$CBEA, Enhanced IIe: Pascal's write and GOTOXY, the disassembler's mnemonic index,
;; the slot 3 card and auxiliary memory tests, a text row's base address, and the control characters: performing
;; one, the handlers up to the line feed, and their tables.

; Pascal.

;; What Pascal's GOTOXY adds to its column and line: they arrive as characters from the space up.
GOTOXY_BIAS = ' ' & ASCII_BITS

;; <EightyColumns::GotoXYColumn> while <Pascal::GotoXY> waits for a GOTOXY's column.
GOTOXY_WAITING = $FF

; The disassembler's mnemonic hash, as the Monitor's.

;; TXA, TXS, TAX, TSX, DEX and NOP, and the opcodes $DA and $FA, as the Monitor's group bits keep them: they skip the
;; mnemonic hash's first step.
TXA_GROUP = $8A

;; The steps of the mnemonic hash, one for each of the opcode's bits 0-2.
HASH_STEPS = 3

;; The bit the mnemonic hash sets as it shifts, once the opcode's first 1 bit has shifted out.
HASH_GROUP_BIT = $20

; The card tests.

;; Inherit: <Monitor:CompareSlot3Rom>
CompareSlot3Rom = $F8B7

;; The byte <TestAuxMemory> writes to auxiliary memory and reads back.
AUX_TEST_BYTE = $88

; The text screen's layout.

;; A text line's bits 1 and 2, once bit 0 is shifted out: which page of the screen's four the line is in.
TEXT_LINE_PAGE_BITS = %00000011

;; A text line's bits 3 and 4: which third of the screen the line is in, each third $28 bytes on from the last.
TEXT_LINE_THIRD_BITS = %00011000

;; What an odd text line adds to its base address: it is in the second half of its page.
TEXT_ODD_LINE = $80

; The video and the bell.

;; <InverseMask> for normal text.
TEXT_NORMAL = $FF

;; <InverseMask> for inverse text in 80 columns: the alternate characters' inverse codes have bit 7 clear.
TEXT_INVERSE = $7F

;; The delay count before the bell's tone.
BELL_PAUSE = $40

;; The delay count between the speaker's toggles.
BELL_HALF_CYCLE = $0C

;; How many times the bell toggles the speaker.
BELL_TOGGLES = $C0

; The macros that build the control characters' handler tables.

;; One control code's handler, for <Control::HandlersLow> and <Control::HandlersHigh>: its address minus one, split
;; into a low byte and a page whose bit 7 is replaced by the flags.
;; Parameters:
;;   code = the control code
;;   handler = the routine, in a page from $80 up
;;   flags = <Control::RUNS_WHEN_DISABLED>, or 0
.macro ControlHandler code, handler, flags
    .assert >(handler - 1) >= $80, "A control handler's page must have bit 7 set."
    .ident(.sprintf("CONTROL_LOW_%d", code)) = <(handler - 1)
    .ident(.sprintf("CONTROL_HIGH_%d", code)) = (>(handler - 1) & $7F) | flags
.endmacro

;; A control code without a handler.
;; Parameters:
;;   code = the control code
.macro NoControlHandler code
    .ident(.sprintf("CONTROL_LOW_%d", code)) = 0
    .ident(.sprintf("CONTROL_HIGH_%d", code)) = 0
.endmacro

; Pascal: write and GOTOXY.
.scope Pascal continued

;; Pascal's write: takes a GOTOXY's column or line, performs a control character, or displays any other and moves
;; the cursor right, to the next line at the window's right edge. Then the line's base is saved and the cursor shown.
;;
;; <Pascal::WriteEntry at PASWRITE> jumps here.
;; In: A = the character
;; Out: X = 0
;; Entry:
;;   SaveBase = saves <TextBase>/<TextBaseHigh>, then shows the cursor; <Pascal::GotoXY>, <Pascal::WriteControl> and
;;     <Pascal::Init> go here
;;   ShowCursor = shows the cursor, X = 0; <Pascal::StoreGotoColumn> goes here
;; Also: PWRITE (IIEROM82, IIETRM85), PASPUTCHAR (UNKN)
.proc Write
    and #ASCII_BITS
    tax
    jsr Setup
    lda #MODE_GOTOXY
    bit EightyColumns::Mode
    bne GotoXY

    ; A control character has neither bit 5 nor bit 6, as RangeMask's $60 tests.
    txa
    bit RangeMask
    beq WriteControl

    ; Any other character, in Pascal's video.
    ldy EightyColumns::CursorColumn
    bit InverseMask
    bpl Store
    ora #TEXT_HIGH_BIT

;; Stores the character and moves the cursor right, to the next line at the window's right edge.
;; Also: PWRI (IIETRM85)
Store:
    jsr Screen::WriteCharacter
    iny
    sty EightyColumns::CursorColumn
    cpy WindowWidth
    bcc SaveBase
    lda #0
    sta EightyColumns::CursorColumn
    jsr Control::LineFeed

;; Saves <TextBase>/<TextBaseHigh> for the next call, then shows the cursor.
;; Also: DOBASL (IIETRM85)
SaveBase:
    lda TextBase
    sta EightyColumns::SavedTextBase
    lda TextBaseHigh
    sta EightyColumns::SavedTextBaseHigh

;; Shows the cursor and returns X = 0.
;; Also: PWRITERET (IIETRM85)
ShowCursor:
    jsr Screen::FlipCursor
    ldx #0

;; The return, whose opcode, $60, is the mask the control character test uses.
;; Also: PRTS (IIETRM85)
RangeMask:
    rts
.endproc

;; A GOTOXY's next character, less <GOTOXY_BIAS>: its column first, then its line, which moves the cursor and ends
;; the GOTOXY.
;; In: X = the character
;; Also: PASGOTOXY (UNKN), GETX (IIETRM85)
.proc GotoXY
    jsr Screen::FlipCursor
    txa
    sec
    sbc #GOTOXY_BIAS
    bit EightyColumns::GotoXYColumn
    bmi StoreGotoColumn

    ; The line: the cursor moves to it and the column.
    sta EightyColumns::CursorLine
    sta CV
    jsr RowBase
    lda EightyColumns::GotoXYColumn
    sta EightyColumns::CursorColumn
    lda #<~MODE_GOTOXY
    and EightyColumns::Mode
    sta EightyColumns::Mode
    ; Always: the mode has MODE_PASCAL.
    bne Write::SaveBase
.endproc

;; Pascal's control characters: Control-^ starts a GOTOXY; any other is performed.
;; In: X = the code
;; Also: PCTL (IIETRM85)
.proc WriteControl
    jsr Screen::FlipCursor
    txa
    cmp #CONTROL_CARET
    beq StartGotoXY
    jsr Control::Perform
    jmp Write::SaveBase

;; Control-^: sets <MODE_GOTOXY>, with the column not yet received.
;; Also: STARTXY (IIETRM85)
StartGotoXY:
    lda #MODE_GOTOXY
    ora EightyColumns::Mode
    sta EightyColumns::Mode
    lda #GOTOXY_WAITING
    ; Falls into StoreGotoColumn.
.endproc

;; Stores A as the GOTOXY's column, then shows the cursor. <Pascal::GotoXY> branches here.
;; Also: PSETX (IIETRM85)
StoreGotoColumn:
    sta EightyColumns::GotoXYColumn
    jmp Write::ShowCursor

.endscope

;; Finishes decoding an opcode for the Monitor's disassembler: its mnemonic's index, by the mnemonic hash the other
;; Monitors compute themselves.
;;
;; <Functions::Decode at CXINSDS2> jumps here.
;; In: A = the opcode and the Monitor's group bits ($8F), ScrollBase = the opcode
;; Out: A = the mnemonic's index
;; Also: MNEMINDEX (UNKN), DOMN (IIETRM85)
.proc MnemonicIndex
    tax
    lda ScrollBase
    ldy #HASH_STEPS
    cpx #TXA_GROUP
    beq HashNext

;; One step of the mnemonic hash: shifts out the next of the opcode's bits 0-2, until one is 1.
HashStep:
    lsr a
    bcc HashNext
    lsr a

;; Shifts A right, setting <HASH_GROUP_BIT>, once for this step and each step left, then ends the hash.
;; Also: MNNDX2 (IIETRM85)
HashShift:
    lsr a
    ora #HASH_GROUP_BIT
    dey
    bne HashShift
    iny

;; Counts the steps down.
;; Also: MNNDX3 (IIETRM85)
HashNext:
    dey
    bne HashStep
    rts
.endproc

;; Decides whether slot 3's own ROM is used: a card in slot 3 whose ROM has the Pascal 1.1 bytes (by
;; <CompareSlot3Rom>) keeps its ROM; otherwise the internal ROM is used when auxiliary memory answers.
;;
;; The reset function calls it.
;; Out: zero = set to use the internal slot 3 ROM
;; Also: SLOT3CHECK (UNKN), TSTROMCRD (IIETRM85)
.proc TestSlot3Card
    jsr CompareSlot3Rom
    bne TestAuxMemory
    ; A card with the bytes: Y is 0, and 1 clears zero.
    iny
    rts
.endproc

;; Tests for auxiliary memory: writes <AUX_TEST_BYTE> to <TextPage1>'s first byte in auxiliary memory, through
;; 80STORE and PAGE2, and reads it back, then restores the byte, PAGE2 and 80STORE.
;; Out: A = the byte read back; zero = set when it is <AUX_TEST_BYTE>, auxiliary memory answered
;; Keeps: X
;; Also: TESTCARD (IIEROM82, IIETRM85), AUXPRESENT (UNKN)
.proc TestAuxMemory
    ; PAGE2's state in the carry, 80STORE's in negative, both saved.
    lda Page2State
    asl a
    lda #AUX_TEST_BYTE
    bit Store80State
    sta Store80On
    php

    ; The test, with page two selecting the auxiliary text page.
    sta Page2On
    ldy TextPage1
    sta TextPage1
    lda TextPage1
    sty TextPage1

    ; PAGE2 off unless it was on.
    plp
    bcs Restore80Store
    sta Page2Off

;; 80STORE off unless it was on.
;; Also: STAY2 (IIEROM82, IIETRM85)
Restore80Store:
    bmi Compare
    sta Store80Off

;; Compares the byte read back with the one written.
;; Also: STAY80 (IIETRM85)
Compare:
    cmp #AUX_TEST_BYTE
    rts
.endproc

;; Sets <TextBase>/<TextBaseHigh> to a text row's address on page one, without the window.
;; In: A = the row, 0-23
;; Out: A = the address's low byte, carry = clear
;; Keeps: X, Y
;; Also: ROWBASE (UNKN), BASCALC (IIETRM85)
.proc RowBase
    ; The high byte: page one's, plus the row's page.
    pha
    lsr a
    and #TEXT_LINE_PAGE_BITS
    ora #>TextPage1
    sta TextBaseHigh

    ; The low byte: $80 for an odd row (bit 0, now in the carry), plus $28 for each third.
    pla
    and #TEXT_LINE_THIRD_BITS
    bcc StoreLow
    ; The carry is set, so this adds TEXT_ODD_LINE.
    adc #TEXT_ODD_LINE - 1

;; Stores the low byte and multiplies its third by five.
;; Also: BSCLC2 (IIETRM85)
StoreLow:
    sta TextBase
    asl a
    asl a
    ora TextBase
    sta TextBase
    rts
.endproc

;; The control characters the 80-column firmware performs, $00-$1F with bit 7 clear: <Control::Perform> runs a
;; code's handler through the tables <Control::HandlersLow> and <Control::HandlersHigh> (the handler's address minus
;; one, split into its low byte and its page), and the handlers move the cursor, ring the bell, clear, scroll, set the
;; video and the 40 or 80 columns, and quit the firmware.
;;
;; BASIC's output, Pascal's write and escape mode perform their codes here. Other code calls many handlers directly,
;; as the 80-column functions call <Control::ScrollUp> and <Control::ClearToEndOfLine>. On the Enhanced IIe,
;; <Control::PerformUnlessDisabled> skips the codes without <Control::RUNS_WHEN_DISABLED> while escape mode or
;; escape Control-D turns them off, and Control-E, Control-F, Control-X and Control-[ show and hide Pascal's cursor
;; and turn MouseText off and on.
.scope Control

;; The first control code with a handler, Control-E: <Control::HandlersLow> starts there.
;; Also: CTRL_FIRST (UNKN)
FIRST_CODE = CONTROL_E

;; How many control codes there are, $00-$1F.
CODE_COUNT = 32

;; In <Control::HandlersHigh>: the handler runs even while <MODE_CONTROLS_OFF> or <MODE_ESCAPES> turns the control
;; characters off. It takes the place of the handler's page's bit 7.
;; Also: CTRL_ALWAYS (UNKN)
RUNS_WHEN_DISABLED = $80

;; Performs a control character for BASIC's output: as <Control::Perform>, but while <MODE_CONTROLS_OFF> or
;; <MODE_ESCAPES> is set only the codes with <Control::RUNS_WHEN_DISABLED>.
;; In: A = the code, $00-$1F
;; Out: carry = clear when a handler ran, set when the code has none or is off
;; Keeps: A, Y
;; Also: DOCTRL (UNKN), CTLCHAR0 (IIETRM85)
.proc PerformUnlessDisabled
    ; Overflow set: the mode decides.
    bit OverflowByte
    ; A bvc, never taken: it skips Perform's clv.
    .byte $50
    ; Falls into Perform.
.endproc

;; Performs a control character at the firmware's cursor, through its handler in <Control::HandlersLow> and
;; <Control::HandlersHigh>; a 0 in <Control::HandlersHigh> means no handler.
;; In: A = the code, $00-$1F
;; Out: carry = clear when a handler ran, set when the code has none
;; Keeps: A, Y
;; Also: CTLCHAR (IIEROM82, IIETRM85)
.proc Perform

;; The code, then the handler's page while the mode is checked: <EightyColumns::SavedTextBase>, borrowed.
Code = EightyColumns::SavedTextBase

    clv
    sta Code
    pha
    tya
    pha
    ldy Code
    cpy #FIRST_CODE
    bcc NotHandled
    lda HandlersHigh,y
    beq NotHandled

    ; Overflow clear, or a code that always runs: the handler; otherwise only when the mode allows.
    bvc Handle
    bmi Handle
    sta Code
    lda EightyColumns::Mode
    and #MODE_ESCAPES | MODE_CONTROLS_OFF
    beq Reload

;; No handler, or the control characters are off: the carry set.
;; Also: CTLCHARX (IIEROM82, IIETRM85)
NotHandled:
    sec
    bcs Done

    ; The page back.
Reload:
    lda Code

;; Runs the handler, with its page's bit 7 back, then the carry clear.
;; Also: CTLGO (IIEROM82, IIETRM85)
Handle:
    ora #RUNS_WHEN_DISABLED
    jsr Jump
    clc

;; Y and A back.
;; Also: CTLRET (IIEROM82, IIETRM85)
Done:
    pla
    tay
    pla
    ; Falls into OverflowByte, Perform's return.
.endproc

;; The return of <Control::Perform>, whose opcode, $60, has bit 6 set: BIT on it sets overflow.
;; Also: SEV1 (IIETRM85)
OverflowByte:
    rts

;; Goes to the handler of control code Y: pushes its page from A and its low byte minus one from
;; <Control::HandlersLow>, and returns into it.
;; In: A = the handler's page, Y = the code, <Control::FIRST_CODE> or above
;; Also: CTLXFER (IIEROM82, IIETRM85), CTRLJUMP (UNKN)
.proc Jump
    pha
    lda HandlersLow - FIRST_CODE,y
    pha
    rts
.endproc

;; Control-E: shows Pascal's cursor, clearing <MODE_CURSOR_OFF>; outside Pascal it does nothing.
;; Keeps: X, Y
;; Entry:
;;   StoreMode = stores A as the mode; <Control::CursorOff> branches here
;;   Done = returns; <Control::CursorOff> branches here
;; Also: CURSORON (UNKN), X_CUR_ON (IIETRM85)
.proc CursorOn
    lda EightyColumns::Mode
    bpl Done
    and #<~MODE_CURSOR_OFF

;; Stores A as the mode.
StoreMode:
    sta EightyColumns::Mode

;; Returns.
;; Also: CURON_X (IIETRM85)
Done:
    rts
.endproc

;; Control-F: hides Pascal's cursor, setting <MODE_CURSOR_OFF>; outside Pascal it does nothing.
;; Keeps: X, Y
;; Also: CURSOROFF (UNKN), X_CUR_OFF (IIETRM85)
.proc CursorOff
    lda EightyColumns::Mode
    bpl CursorOn::Done
    ora #MODE_CURSOR_OFF
    ; Always: the mode is not 0 now.
    bne CursorOn::StoreMode
.endproc

;; Control-G: rings the bell, a pause and then <BELL_TOGGLES> toggles of the speaker.
;; Keeps: X
;; Also: X_BELL (IIEROM82, IIETRM85), BELL80 (UNKN)
.proc Bell
    lda #BELL_PAUSE
    jsr Pause
    ldy #BELL_TOGGLES

;; Toggles the speaker once.
;; Also: C8_BELL2 (UNKN), BELL2 (IIEROM82, IIETRM85)
Click:
    lda #BELL_HALF_CYCLE
    jsr Pause
    lda Speaker
    dey
    bne Click
    rts
.endproc

;; Waits, as long as the Monitor's <Delay> does for the same A, of which it is a copy.
;;
;; Apple's listing calls it WAIT, the Monitor's name for <Delay>.
;; In: A = the count
;; Out: A = 0
;; Keeps: X, Y
;; Also: C8_WAIT (UNKN), DELAYA (UNKN)
.proc Pause
    sec

;; The outer count.
;; Also: C8_WAIT2 (UNKN), WAIT2 (IIEROM82, IIETRM85)
Outer:
    pha

;; The inner count.
;; Also: C8_WAIT3 (UNKN), WAIT3 (IIEROM82, IIETRM85)
Inner:
    sbc #1
    bne Inner
    pla
    sbc #1
    bne Outer
    rts
.endproc

;; Control-H: moves the cursor left; from the first column, to the last of the line above.
;; Also: X_BS (IIEROM82, IIETRM85), BACKSPC80 (UNKN)
.proc Left
    dec EightyColumns::CursorColumn
    bpl Done
    lda WindowWidth
    sta EightyColumns::CursorColumn
    dec EightyColumns::CursorColumn
    jsr Up

;; Returns.
;; Also: BSDONE (IIEROM82, IIETRM85)
Done:
    rts
.endproc

;; Control-M: a carriage return: the cursor to the first column and, outside Pascal, down a line.
;; Also: X_CR (IIEROM82, IIETRM85), CR80 (UNKN)
.proc CarriageReturn
    lda #0
    sta EightyColumns::CursorColumn
    lda EightyColumns::Mode
    bmi Done
    jsr LineFeed

    ; Returns.
Done:
    rts
.endproc

;; Control-Y: homes the cursor, to the window's top line and the first column.
;; Also: X_EM (IIEROM82, IIETRM85), HOMECURSOR (UNKN)
.proc Home
    lda WindowTop
    sta CV
    lda #0
    sta EightyColumns::CursorColumn
    jmp LineBase
.endproc

;; Control-\: moves the cursor right, to the next line at the window's right edge.
;; Also: X_FS (IIEROM82, IIETRM85), FWDSPACE80 (UNKN)
.proc Right
    inc EightyColumns::CursorColumn
    lda EightyColumns::CursorColumn
    cmp WindowWidth
    bcc Done
    jsr CarriageReturn

    ; Returns.
;; Also: X_FSRET (IIEROM82)
Done:
    rts
.endproc

;; Control-_: moves the cursor up a line, unless it is on the window's top line.
;; Also: X_US (IIEROM82, IIETRM85), UP80 (UNKN)
.proc Up
    lda WindowTop
    cmp CV
    bcs StoreVideo::Done
    dec CV
    jmp LineBase
.endproc

;; Control-N: normal text, and in Pascal <MODE_INVERSE> cleared.
;; Keeps: X
;; Also: X_SO (IIEROM82, IIETRM85), NORMAL80 (UNKN)
.proc Normal
    lda EightyColumns::Mode
    bpl SetNormal
    and #<~MODE_INVERSE

;; The normal mask.
;; Also: X_SO1 (IIETRM85)
SetNormal:
    ldy #TEXT_NORMAL
    ; Always: the mask is not 0.
    bne StoreVideo
.endproc

;; Control-O: inverse text, and in Pascal <MODE_INVERSE> set.
;; Keeps: X
;; Also: X_SI (IIEROM82, IIETRM85), INVERSE80 (UNKN)
.proc Inverse
    lda EightyColumns::Mode
    bpl SetInverse
    ora #MODE_INVERSE

;; The inverse mask.
;; Also: X_SI1 (IIETRM85)
SetInverse:
    ldy #TEXT_INVERSE
    ; Falls into StoreVideo.
.endproc

;; Stores the mode and <InverseMask>.
;; In: A = the mode, Y = the mask
;; Keeps: X
;; Entry:
;;   Done = returns; <Control::Up> branches here
;; Also: STUFFINV (IIEROM82, IIETRM85), SETINVFLG (UNKN)
.proc StoreVideo
    sta EightyColumns::Mode
    sty InverseMask

;; Returns.
Done:
    rts
.endproc

; The handler tables.

    ControlHandler CONTROL_E, CursorOn, 0                           ; Pascal: show the cursor
    ControlHandler CONTROL_F, CursorOff, 0                          ; Pascal: hide the cursor
    ControlHandler CONTROL_G, Bell, RUNS_WHEN_DISABLED              ; bell
    ControlHandler CONTROL_H, Left, RUNS_WHEN_DISABLED              ; left
    NoControlHandler $09
    ControlHandler CONTROL_J, LineFeed, RUNS_WHEN_DISABLED          ; down (line feed)
    ControlHandler CONTROL_K, ClearToEndOfWindow, 0                           ; clear to the end of the window
    ControlHandler CONTROL_L, HomeAndClear, 0                          ; home and clear the window
    ControlHandler CONTROL_M, CarriageReturn, RUNS_WHEN_DISABLED    ; return
    ControlHandler CONTROL_N, Normal, 0                             ; normal text
    ControlHandler CONTROL_O, Inverse, 0                            ; inverse text
    NoControlHandler $10
    ControlHandler CONTROL_Q, Columns40, 0                           ; 40 columns
    ControlHandler CONTROL_R, Columns80, 0                           ; 80 columns
    NoControlHandler $13
    NoControlHandler $14
    ControlHandler CONTROL_U, Quit, 0                             ; quit the 80-column firmware
    ControlHandler CONTROL_V, ScrollDown, 0                         ; scroll down
    ControlHandler CONTROL_W, ScrollUp, 0                         ; scroll up
    ControlHandler CONTROL_X, MouseTextOff, 0                           ; MouseText off
    ControlHandler CONTROL_Y, Home, 0                               ; home the cursor
    ControlHandler CONTROL_Z, ClearLine, 0                          ; clear the line
    ControlHandler CONTROL_ESCAPE, MouseTextOn, 0                       ; MouseText on
    ControlHandler CONTROL_BACKSLASH, Right, 0                      ; right
    ControlHandler CONTROL_RIGHT_BRACKET, ClearToEndOfLine, 0               ; clear to the end of the line
    NoControlHandler CONTROL_CARET
    ControlHandler CONTROL_UNDERSCORE, Up, 0                        ; up

;; The handlers' low bytes, less one, from <Control::FIRST_CODE>. The last five of them, the low bytes for
;; Control-[ to Control-_, are <Control::HandlersHigh>' first bytes.
;; Also: CTLADL (IIEROM82, IIETRM85), CTRLLOW (UNKN)
HandlersLow:
.repeat CODE_COUNT - 2 * FIRST_CODE, index
    .byte .ident(.sprintf("CONTROL_LOW_%d", FIRST_CODE + index))
.endrepeat

;; The handlers' pages, with <Control::RUNS_WHEN_DISABLED> for bit 7, for codes $00-$1F; 0 means no handler. The
;; first <Control::FIRST_CODE> bytes, for codes without handlers, are never read as pages: they end
;; <Control::HandlersLow>.
;; Also: CTLADH (IIEROM82, IIETRM85), CTRLPAGE (UNKN)
HandlersHigh:
.repeat FIRST_CODE, index
    .byte .ident(.sprintf("CONTROL_LOW_%d", CODE_COUNT - FIRST_CODE + index))
.endrepeat
.repeat CODE_COUNT - FIRST_CODE, index
    .byte .ident(.sprintf("CONTROL_HIGH_%d", FIRST_CODE + index))
.endrepeat

;; Control-V: scrolls the window down a line.
;; Also: SCROLLDN (IIEROM82, IIETRM85), SCROLLDN80 (UNKN)
.proc ScrollDown
    ; Y = 0: down. Always: Y is 0.
    ldy #0
    beq Scroll
.endproc

;; Control-J: moves the cursor down a line, scrolling the window up from its bottom line.
;; Also: X_LF (IIEROM82, IIETRM85), LF80 (UNKN)
.proc LineFeed
    inc CV
    lda CV
    sta EightyColumns::CursorLine
    cmp WindowBottom
    bcs AtBottom
    jmp LineBase::Row

;; Below the window: back to its bottom line, then the window scrolled up.
;; Also: X_LF2 (IIEROM82, IIETRM85), SCROLL80 (UNKN)
AtBottom:
    dec EightyColumns::CursorLine
    dec CV
    ; Falls into SCROLLUP80, Control::ScrollUp, at the start of EightyColumnsScreen.asm.
.endproc

.endscope
