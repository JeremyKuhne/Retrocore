; retrocore: style=strict
;; The 80-column firmware's $CA02-$CBFC, original IIe: the end of reading a key for BASIC, Pascal's init, read and
;; write, the keyboard wait, the card test and the line base, and the first control characters: performing one,
;; the bell, the cursor left and the start of the carriage return.

; CharacterIo: the end of finishing a key, which EightyColumnsEntry.asm starts.

;; Leaves quotes: clears <MODE_QUOTES>.
;; Also: B_CANLIT (IIEROM82)
LeaveQuotes:
    lda EightyColumns::Mode
    and #<~MODE_QUOTES
    sta EightyColumns::Mode

;; Makes a lowercase key uppercase while <MODE_UPPERCASE> is set and the line is outside quotes.
;; Also: B_FIXCHR (IIEROM82), UPSHIFT (UNKN), UPSHFT (IIETRM85)
Upshift:
    lda EightyColumns::Mode
    and #MODE_UPPERCASE
    beq Done
    lda EightyColumns::Mode
    and #MODE_QUOTES
    bne Done
    lda EightyColumns::CurrentCharacter
    ; From the backquote up: lowercase.
    cmp #'`'
    bcc Done
    and #UPPERCASE_MASK
    sta EightyColumns::CurrentCharacter

;; Returns the key through <CharacterIo::Finish>.
;; Also: B_INRET (IIEROM82)
Done:
    jmp Finish
.endproc

;; Reads the character left of the cursor, moving the cursor left and back.
;; Out: FirmwareScratch = the character, with its high bit set; zero = set when it is a quote, or when the
;;   cursor is at the screen's top left, where nothing is read
;; Keeps: Y
;; Also: GETPRIOR (IIEROM82)
.proc CharacterBefore
    lda EightyColumns::CursorLine
    ora EightyColumns::CursorColumn
    beq Done
    tya
    pha
    jsr Control::Left
    ldy EightyColumns::CursorColumn
    jsr Screen::ReadCharacter
    ora #TEXT_HIGH_BIT
    sta FirmwareScratch
    jsr Control::Right
    pla
    tay
    lda FirmwareScratch
    cmp #'"'

;; Returns.
;; Also: GPX (IIEROM82)
Done:
    rts
.endproc

.endscope

; Pascal.

;; The error <Pascal::Init> returns in X when no 80-column card answers.
PASCAL_NO_DEVICE = 9

;; What Pascal's GOTOXY adds to its column and line: they arrive as characters from the space up.
GOTOXY_BIAS = ' ' & ASCII_BITS

;; <EightyColumns::GotoXYColumn> while <Pascal::Write> waits for a GOTOXY's column.
GOTOXY_WAITING = $FF

; The card test.

;; The byte <TestAuxMemory> writes to auxiliary memory and reads back.
AUX_TEST_BYTE = $88

; The text screen's layout.

;; A text line's bits 1 and 2, once bit 0 is shifted out: which page of the screen's four the line is in.
TEXT_LINE_PAGE_BITS = %00000011

;; A text line's bits 3 and 4: which third of the screen the line is in, each third $28 bytes on from the last.
TEXT_LINE_THIRD_BITS = %00011000

;; What an odd text line adds to its base address: it is in the second half of its page.
TEXT_ODD_LINE = $80

; The bell.

;; The delay count before the bell's tone.
BELL_PAUSE = $40

;; The delay count between the speaker's toggles.
BELL_HALF_CYCLE = $0C

;; How many times the bell toggles the speaker.
BELL_TOGGLES = $C0

; Pascal: init, read and write.
.scope Pascal continued

;; Starts the firmware for Pascal 1.0: as <Pascal::Init>, with <MODE_PASCAL10> too.
;;
;; <Pascal::Init10Entry> jumps here.
;; Also: PINIT1_0 (IIEROM82, IIETRM85), C9PASINIT (UNKN)
.proc Init10
    lda #MODE_PASCAL | MODE_PASCAL10
    jmp Init::SetMode
.endproc

;; Starts the firmware for Pascal: the mode, the full 80-by-24 window and Pascal's video; with an 80-column card,
;; 80 columns, the alternate characters, the window cleared and the cursor shown.
;;
;; <Pascal::InitEntry at JPINIT> jumps here.
;; Out: X = 0, or <PASCAL_NO_DEVICE> when no card answers
;; Entry:
;;   SetMode = starts with the mode in A; <Pascal::Init10> jumps here
;; Also: PINIT (IIEROM82, IIETRM85)
.proc Init
    lda #MODE_PASCAL

;; Stores the mode from A, then starts.
;; Also: PINIT2 (IIEROM82, IIETRM85)
SetMode:
    sta EightyColumns::Mode
    jsr FullWindow80
    jsr Setup
    jsr TestAuxMemory
    beq CardPresent
    ldx #PASCAL_NO_DEVICE
    rts

;; A card answered: 80 columns, the window cleared and the cursor shown.
;; Also: PIGOOD (IIEROM82, IIETRM85)
CardPresent:
    sta Store80On
    sta Columns80On
    sta AlternateCharactersOn
    jsr Control::HomeAndClear
    jsr Screen::InvertCursor
    ldx #0
    rts
.endproc

;; Pascal's read: waits for a key and returns it with its high bit clear.
;;
;; <Pascal::ReadEntry at JPREAD> jumps here.
;; Out: A = <EightyColumns::CurrentCharacter> = the key, with its high bit clear; X = 0, or <PASCAL10_READ_X> for
;;   Pascal 1.0
;; Also: C8_PREAD (UNKN), PREAD (IIEROM82, IIETRM85), PASGETKEY (UNKN)
.proc Read
    jsr Setup
    jsr WaitForKey
    and #ASCII_BITS
    sta EightyColumns::CurrentCharacter
    ldx #0
    lda EightyColumns::Mode
    and #MODE_PASCAL10
    beq Done
    ldx #PASCAL10_READ_X

;; Returns the key.
;; Also: PREADRET2 (IIEROM82, IIETRM85)
Done:
    lda EightyColumns::CurrentCharacter
    rts
.endproc

;; Pascal's write: with the cursor hidden meanwhile, takes a GOTOXY's column or line, performs a control character
;; or displays any other.
;;
;; Control-^ starts a GOTOXY: the next two characters, less <GOTOXY_BIAS>, are its column and line. A displayed
;; character moves the cursor right; at the window's right edge it stays on the last column while
;; <MODE_TRANSPARENT> is set, else goes to the next line. <Pascal::WriteEntry at JPWRITE> jumps here.
;; In: A = the character
;; Out: X = 0
;; Also: PWRITE (IIEROM82, IIETRM85), PASPUTCHAR (UNKN)
.proc Write
    sta EightyColumns::CurrentCharacter
    jsr Setup
    jsr Screen::InvertCursor
    lda EightyColumns::Mode
    and #MODE_GOTOXY
    beq NotGotoXY

;; A GOTOXY's next character: its column first.
;; Also: PWRITE2 (IIEROM82)
GotoXY:
    lda EightyColumns::GotoXYColumn
    bpl Row
    lda EightyColumns::CurrentCharacter
    sec
    sbc #GOTOXY_BIAS
    sta EightyColumns::GotoXYColumn
    jmp Done

;; The GOTOXY's line, then the cursor moved to it and the column, ending the GOTOXY.
;; Also: GETY (IIEROM82)
Row:
    lda EightyColumns::CurrentCharacter
    sec
    sbc #GOTOXY_BIAS
    sta EightyColumns::CursorLine
    jsr LineBase
    lda EightyColumns::GotoXYColumn
    sta EightyColumns::CursorColumn
    lda EightyColumns::Mode
    and #<~MODE_GOTOXY
    sta EightyColumns::Mode
    ; Always: the mode has MODE_PASCAL.
    bne Done

;; Not in a GOTOXY: Control-^ starts one, another control character is performed, and any other is displayed.
;; Also: PWRITE3 (IIEROM82)
NotGotoXY:
    lda EightyColumns::CurrentCharacter
    cmp #CONTROL_CARET
    beq StartGotoXY
    cmp #' ' & ASCII_BITS
    bcs Printable
    jsr Control::Perform
    jmp Done

;; Control-^: sets <MODE_GOTOXY>, with the column not yet received.
;; Also: STARTXY (IIEROM82, IIETRM85)
StartGotoXY:
    lda EightyColumns::Mode
    ora #MODE_GOTOXY
    sta EightyColumns::Mode
    lda #GOTOXY_WAITING
    sta EightyColumns::GotoXYColumn
    bmi Done

;; Displays the character, in Pascal's current video, and moves the cursor right.
;; Also: PWRITE4 (IIEROM82)
Printable:
    ora #TEXT_HIGH_BIT
    ldy EightyColumns::CursorColumn
    jsr Screen::StoreCharacter
    inc EightyColumns::CursorColumn
    lda EightyColumns::CursorColumn
    cmp WindowWidth
    bcc Done
    lda EightyColumns::Mode
    and #MODE_TRANSPARENT
    beq Wrap
    dec EightyColumns::CursorColumn
    ; Always: the window is wider than one column.
    bne Done

;; At the window's right edge: a return and a line feed.
;; Also: PWWRAP (IIEROM82)
Wrap:
    jsr Control::CarriageReturn
    jsr Control::LineFeed

;; Shows the cursor again.
;; Also: PWRITERET (IIEROM82, IIETRM85)
Done:
    jsr Screen::InvertCursor
    ldx #0
    rts
.endproc

.endscope

;; Waits for a key, counting <RandomSeed>/<RandomSeedHigh> up meanwhile, then clears the keyboard strobe.
;; Out: A = the key, with its high bit set
;; Keeps: X, Y
;; Also: GETKEY80 (UNKN), GETKEY (IIEROM82, IIETRM85), GETKEYRND (UNKN)
.proc WaitForKey
    inc RandomSeed
    bne Poll
    inc RandomSeedHigh

;; Reads the keyboard.
;; Also: GETK2 (IIEROM82, IIETRM85)
Poll:
    lda Keyboard
    bpl WaitForKey
    sta KeyboardStrobe
    rts
.endproc

;; Tests for an 80-column card: with interrupts off, writes <AUX_TEST_BYTE> to <TextPage1>'s first byte in
;; auxiliary memory, through 80STORE and PAGE2, and reads it back, then restores the byte, PAGE2, 80STORE and the
;; interrupt flag.
;; Out: A = the byte read back; zero = set when it is <AUX_TEST_BYTE>, a card answered
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
    sei
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
    bmi RestoreInterrupts
    sta Store80Off

;; The interrupt flag back.
;; Also: STAY80 (IIEROM82)
RestoreInterrupts:
    plp

;; Compares the byte read back with the one written.
;; Also: TESTFAIL (IIEROM82)
Compare:
    cmp #AUX_TEST_BYTE
    rts
.endproc

;; Sets <TextBase>/<TextBaseHigh>, and their copies <EightyColumns::SavedTextBase>/
;; <EightyColumns::SavedTextBaseHigh>, to the firmware's line's address plus the window's left edge, which counts
;; half in 80 columns.
;;
;; When the caller of the BASIC entries allowed interrupts (<MODE_INTERRUPTS>), outside Pascal, it then calls
;; <RestoreAfterFirmware> to let them in.
;; In: EightyColumns::CursorLine = the line
;; Keeps: A, X, Y
;; Entry:
;;   Row = takes the line in A
;; Also: C8_BASCALC (UNKN), BASCALC (IIEROM82), VTAB80 (UNKN)
.proc LineBase
    clc
    bcc Calculate

;; The same for the line in A.
;; Also: BASCALC2 (IIEROM82)
Row:
    sec

;; Picks the line: A with the carry set, the firmware's otherwise.
;; Also: BSCLC1 (IIEROM82)
Calculate:
    pha
    bcs FromA
    lda EightyColumns::CursorLine

;; The high byte: page one's, plus the line's page.
;; Also: BSCLC1A (IIEROM82)
FromA:
    pha
    lsr a
    and #TEXT_LINE_PAGE_BITS
    ora #>TextPage1
    sta TextBaseHigh
    sta EightyColumns::SavedTextBaseHigh

    ; The low byte: $80 for an odd line (bit 0, now in the carry), plus $28 for each third.
    pla
    and #TEXT_LINE_THIRD_BITS
    bcc StoreLow
    ; The carry is set, so this adds TEXT_ODD_LINE.
    adc #TEXT_ODD_LINE - 1

;; Stores the low byte and multiplies its third by five.
;; Also: BSCLC2 (IIEROM82, IIETRM85)
StoreLow:
    sta TextBase
    asl a
    asl a
    ora TextBase
    sta TextBase

    ; The window's left edge, halved in 80 columns, with the carry kept for the add.
    lda WindowLeft
    php
    bit Columns80State
    bpl AddLeft
    lsr a

;; Adds the left edge, then lets interrupts in when the caller allowed them, outside Pascal.
;; Also: BASCLC3 (IIEROM82), VTAB40 (IIETRM85)
AddLeft:
    plp
    adc TextBase
    sta TextBase
    sta EightyColumns::SavedTextBase
    lda EightyColumns::Mode
    and #MODE_INTERRUPTS
    beq Done
    lda EightyColumns::Mode
    and #MODE_PASCAL
    bne Done
    jsr RestoreAfterFirmware

;; A back.
;; Also: BASCLCX (IIEROM82)
Done:
    pla
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

;; Performs a control character at the firmware's cursor, through its handler in <HandlersLow at CTLADL> and
;; <HandlersHigh at CTLADH>.
;;
;; Control-G to Control-_ have entries; a 0 in <HandlersHigh> means no handler. A code above $1F reads past the
;; tables.
;; In: A = the code, $00-$1F
;; Out: carry = clear when a handler ran, set when the code has none
;; Keeps: A, Y
;; Also: CTLCHAR (IIEROM82, IIETRM85)
.proc Perform
    sta FirmwareScratch
    pha
    tya
    pha
    ldy FirmwareScratch
    cpy #CONTROL_G
    bcc NotHandled
    lda HandlersHigh - CONTROL_G,y
    bne Handle

;; No handler: the carry set.
;; Also: CTLCHARX (IIEROM82, IIETRM85)
NotHandled:
    sec
    bcs Done

;; Runs the handler, then the carry clear.
;; Also: CTLGO (IIEROM82), CTLGO0 (IIETRM85)
Handle:
    jsr Jump
    clc

;; Y and A back.
;; Also: CTLRET (IIEROM82, IIETRM85)
Done:
    pla
    tay
    pla
    rts
.endproc

;; Goes to the handler of control character Y: pushes its page from A and its low byte minus one from
;; <HandlersLow at CTLADL>, and returns into it.
;; In: A = the handler's page, Y = the code
;; Also: CTLXFER (IIEROM82, IIETRM85), CTRLJUMP (UNKN)
.proc Jump
    pha
    lda HandlersLow - CONTROL_G,y
    pha
    rts
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

;; The last column of the line above.
;; Also: BS40 (IIEROM82)
PreviousLine:
    sta EightyColumns::CursorColumn
    dec EightyColumns::CursorColumn
    jsr Up

;; Returns.
;; Also: BSDONE (IIEROM82, IIETRM85)
Done:
    rts
.endproc

;; Control-M: a carriage return. While BASIC's input reads a line (<MODE_INPUT>, outside Pascal), it clears the rest
;; of the line first; then the cursor goes to the first column and, outside Pascal, down a line.
;; Also: X_CR (IIEROM82, IIETRM85), CR80 (UNKN)
.proc CarriageReturn
    lda EightyColumns::Mode
    and #MODE_PASCAL
    bne FinishReturn
    lda EightyColumns::Mode
    and #MODE_INPUT
    beq FinishReturn
    jsr ClearToEndOfLine
    ; Falls into FinishReturn, the rest of the routine, at the start of EightyColumnsScreen.asm.
.endproc

.endscope
