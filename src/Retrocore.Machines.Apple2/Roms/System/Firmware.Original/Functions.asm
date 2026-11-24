; retrocore: style=strict
;; The original IIe's firmware functions, $C100-$C2FF: <DispatchFunction>, which the Monitor's <Monitor:CallFirmware>
;; jumps to with a function number in Y, and the handlers it reaches: the screen functions in their 40- and 80-column
;; versions, the reset function, the key wait and the escape-key translation, with the exit they share.

;; Performs the firmware function in Y for the Monitor: the original IIe's dispatcher.
;;
;; At $C100, where <Monitor:CallFirmware> jumps with the internal ROM switched in and interrupts disabled. Functions
;; 6 (<Functions::GetKey>) and 7 (<Functions::EscapeKey>) have one version. The screen functions, 0-5 and 8, have a
;; 40-column version, through <Functions::Dispatch40>, and an 80-column one, through <Functions::Prepare80>: the
;; 80-column one when <TestAuxMemory> finds auxiliary memory and <EightyColumns::Mode> has none of
;; <Functions::HANDLERS40_MODE_BITS> set, which is when the 80-column firmware is active and neither working for Pascal
;; nor waiting for a GOTOXY. Every function leaves through <Functions::Return>. The stack holds the caller's status and,
;; above it, a status whose negative flag is <InternalCxRomState> from before the call.
;; In: Y = the function number, A = the character under the cursor (function 6) or the key (function 7)
;; Also: B_FUNC (IIEROM82, IIETRM85)
.proc DispatchFunction
.assert * = $C100, "DispatchFunction must stay at $C100."
    cpy #FIRMWARE_KEYBOARD_IN
    bne NotGetKey
    jmp Functions::GetKey

;; Y is not the key wait's number: tests for the escape-key function's.
;; Also: B_FUNCNK (IIEROM82)
NotGetKey:
    cpy #FIRMWARE_ESCAPE_KEY
    bne ChooseWidth
    jmp Functions::EscapeKey

;; A screen function: the 80-column version with an 80-column card and the firmware ready for it, else the 40-column
;; one.
;; Also: B_FUNCNE (IIEROM82)
ChooseWidth:
    ; The function number is kept on the stack, since TESTCARD uses Y.
    tya
    pha
    jsr TestAuxMemory
    bne Functions::Dispatch40
    lda EightyColumns::Mode
    and #Functions::HANDLERS40_MODE_BITS
    bne Functions::Dispatch40
    jmp Functions::Prepare80
.endproc

;; The handlers of the firmware's functions, which <DispatchFunction> performs for the Monitor by the number in Y
;; (FirmwareFunctions.asm's FIRMWARE_ constants), and the exits they share.
;;
;; The dispatcher reaches most handlers by RTS through a table of their addresses minus one, so each of them starts in
;; page $C1, after its first byte. A screen function has two handlers: a 40-column one, and an 80-column one that runs
;; while the 80-column firmware is active. Every function leaves through <Functions::Return>, which puts the ROM back
;; as <Monitor:CallFirmware> found it.
.scope Functions

; The handlers.

;; The page every handler is in: <Dispatch40> and <Dispatch80> push it as the high byte of the handler's address minus
;; one.
HANDLER_PAGE = $C1

;; The bits of <EightyColumns::Mode> that send the screen functions to their 40-column versions even with an 80-column
;; card: bit 5, Pascal's, and bit 3, a GOTOXY waiting for its column and line. Both are set while the firmware is
;; inactive ($FF).
HANDLERS40_MODE_BITS = $28

; The window.

;; The window's width in 40 columns.
WIDTH_40 = 40

;; The window's width in 80 columns.
WIDTH_80 = 80

;; The line below the full window: the screen's 24 lines.
FULL_WINDOW_BOTTOM = 24

;; The screen's last line, where <SetWindow40> and <SetWindowWidth> put the cursor.
LAST_LINE = FULL_WINDOW_BOTTOM - 1

; The key wait.

;; The block <GetKey> shows for the cursor, alternating with the character under it.
CURSOR_BLOCK = $FF

;; How long <PollKeyboard> polls when it lets interrupts in on every poll, in 256s of polls.
POLLS_WITH_INTERRUPTS = $0C

;; How long <PollKeyboard> polls otherwise, in 256s of polls.
POLLS_WITHOUT_INTERRUPTS = $31

; The reset.

;; Where <ResetFirmware> starts spoiling memory: the offset of the first of the two bytes it changes in page
;; <SPOIL_FIRST_PAGE>. The offset goes down one a page, so page 3's bytes are $03F3 and $03F4.
SPOIL_FIRST_OFFSET = $B0

;; The highest page <ResetFirmware> spoils.
SPOIL_FIRST_PAGE = $BF

;; The page below the last one <ResetFirmware> spoils.
SPOIL_END_PAGE = $01

; The escape key.

;; The bit that a lowercase letter has and its uppercase letter lacks.
LOWERCASE_BIT = $20

; The Monitor's arguments.

;; The page-zero byte the Monitor's <ClearLineFrom at Monitor:ClearLineFrom> leaves the column in, on the original IIe.
PassedColumn = $1F

; The function numbers the dispatcher takes apart. Handlers40 and Handlers80 hold the screen functions by number,
; six entries each; function 8 reads past them, into the tables that follow (see <SetWindow40>).
.assert FIRMWARE_KEYBOARD_IN = 6 && FIRMWARE_ESCAPE_KEY = 7, "DispatchFunction tests for 6 and 7."
.assert FIRMWARE_RESET = 5, "Both handler tables end with Reset."

;; Runs a screen function's 40-column version through <Handlers40>.
;;
;; The function number is on the stack, above the two statuses <Monitor:CallFirmware> pushed. The table holds the
;; handler's address minus one, so the RTS lands on it.
;; Also: B_OLDFUNC (IIEROM82)
.proc Dispatch40
    pla
    tay
    lda #HANDLER_PAGE
    pha
    lda Handlers40,y
    pha
    rts
.endproc

;; Function 0, 40 columns: clears from the cursor to the end of the window.
;;
;; Clears from <CursorColumn> to the end of the line, then every line below it to the window's bottom.
;; Out: TextBase/TextBaseHigh = the cursor line's base address
;; Entry:
;;   FromLine = clears from column Y of line A down; <Home40> branches here
;; Also: F_CLREOP (IIEROM82, IIETRM85), CLREOP40 (UNKN)
.proc ClearToEndOfWindow40
    ldy CursorColumn
    lda CV

;; Clears from column Y of line A to the end of the window.
;; Also: CLEOP1 (IIEROM82, IIETRM85)
FromLine:
    pha
    jsr SetLineBase
    jsr ClearColumns40
    ldy #0
    pla
    ; ClearColumns40 leaves the carry set, so this adds one.
    adc #0
    cmp WindowBottom
    bcc FromLine

    ; The cursor line's base again.
    jsr VerticalTab
    jmp Return
.endproc

;; Function 1, 40 columns: moves the cursor to the window's top left and clears the window.
;; Out: CV = <WindowTop>, CursorColumn = 0
;; Also: F_HOME (IIEROM82, IIETRM85), HOME40 (UNKN)
.proc Home40
    lda WindowTop
    sta CV
    ldy #0
    sty CursorColumn
    beq ClearToEndOfWindow40::FromLine
.endproc

;; Function 2, 40 columns: scrolls the window up a line.
;;
;; Copies each line of the window to the line above it, from the second line down, then clears the bottom line.
;; Also: F_SCROLL (IIEROM82, IIETRM85), SCROLL40 (UNKN)
.proc Scroll40
    lda WindowTop
    pha
    jsr SetLineBase

;; Makes the line just copied the destination, and the next line the source.
;; Also: SCRL1 (IIEROM82, IIETRM85)
NextLine:
    lda TextBase
    sta ScrollBase
    lda TextBaseHigh
    sta ScrollBaseHigh
    ldy WindowWidth
    dey
    pla
    ; The carry is clear, from SetLineBase or the line count's compare.
    adc #1
    cmp WindowBottom
    bcs ClearBottom
    pha
    jsr SetLineBase

;; Copies the line, right to left.
;; Also: SCRL2 (IIEROM82, IIETRM85)
CopyByte:
    lda (TextBase),y
    sta (ScrollBase),y
    dey
    bpl CopyByte
    bmi NextLine

;; Clears the bottom line, then sets the cursor line's base again.
;; Also: SCRL3 (IIEROM82, IIETRM85)
ClearBottom:
    ldy #0
    jsr ClearColumns40
    jsr VerticalTab
    jmp Return
.endproc

;; Function 3, 40 columns: clears from the cursor to the end of the line.
;; Also: F_CLREOL (IIEROM82, IIETRM85), CLREOL40 (UNKN)
.proc ClearToEndOfLine40
    ldy CursorColumn
    lda #' '

;; Stores a space in each column up to the window's right edge.
;; Also: CLEOL2 (IIEROM82)
NextColumn:
    sta (TextBase),y
    iny
    cpy WindowWidth
    bcc NextColumn
    bcs ClearDone
.endproc

;; Function 8, 40 columns: makes the window full width and 24 lines deep, and moves the cursor to the last line.
;;
;; The Monitor's <SetWindow> has set the window's top and left. Nothing branches here, but <Dispatch40> reaches it for
;; function 8: <Handlers40> holds functions 0-5 only, and its ninth byte is <Control::ScrollSteps>'s third, $89, this
;; routine's address minus one.
;; Out: WindowWidth, WindowBottom, CV = the last line, TextBase/TextBaseHigh = its base address
;; Also: F_SETWND (IIEROM82, IIETRM85), SETWNDREST (UNKN)
.proc SetWindow40
    lda #WIDTH_40
    sta WindowWidth
    lda #FULL_WINDOW_BOTTOM
    sta WindowBottom
    lda #LAST_LINE
    sta CV
    jsr VerticalTab
    jmp Return
.endproc

;; Function 4, 40 columns: clears from the column the Monitor left in <PassedColumn> to the end of the line.
;; Also: F_CLEOLZ (IIEROM82), CLREOLZ40 (UNKN), F_CLREOLZ (IIETRM85)
.proc ClearLineFrom40
    ldy PassedColumn
    jsr ClearColumns40
    ; Falls into ClearDone.
.endproc

;; The exit <ClearToEndOfLine40> branches to and <ClearLineFrom40> falls into.
;; Also: F_GORET (IIEROM82)
ClearDone:
    jmp Return

;; Prepares the 80-column firmware for a screen function, then runs the function's 80-column version.
;;
;; Mode bit 0, <MODE_INTERRUPTS>, gets the interrupt state of the Monitor's caller: set when its status, the lower of
;; the two <Monitor:CallFirmware> pushed, had interrupts enabled. <CV> becomes the firmware's cursor line.
;; Also: B_FUNC0 (IIEROM82)
.proc Prepare80

;; The status that says whether internal ROM was in before the call, set aside while the caller's status is read.
SavedStatus = FirmwareScratch

    ; The function number back, then mode bit 0 clear.
    pla
    tay
    lda EightyColumns::Mode
    and #<~MODE_INTERRUPTS
    sta EightyColumns::Mode

    ; The caller's status, put back under the other: three shifts move its interrupt flag, bit 2, into the carry.
    pla
    sta SavedStatus
    pla
    pha
    lsr a
    lsr a
    lsr a
    lda SavedStatus
    pha
    bcs CopyLine
    lda EightyColumns::Mode
    ora #MODE_INTERRUPTS
    sta EightyColumns::Mode

;; The cursor line, then the dispatch.
;; Also: NOI (IIEROM82)
CopyLine:
    lda CV
    sta EightyColumns::CursorLine
    jmp Dispatch80
.endproc

;; Function 2, 80 columns: scrolls the window up a line.
;; Also: B_SCROLL (IIEROM82, IIETRM85), CXSCROLL80 (UNKN)
.proc Scroll80
    jsr Control::ScrollUp
    jmp Return
.endproc

;; Function 3, 80 columns: clears from the cursor to the end of the line.
;; Also: B_CLREOL (IIEROM82, IIETRM85), CXCLREOL80 (UNKN)
.proc ClearToEndOfLine80
    jsr Control::ClearToEndOfLine
    jmp Return
.endproc

;; Function 4, 80 columns: clears from the column the Monitor left in <PassedColumn> to the end of the line.
;; Also: B_CLEOLZ (IIEROM82), CXCLREOLZ80 (UNKN), B_CLREOLZ (IIETRM85)
.proc ClearLineFrom80
    ldy PassedColumn
    jsr Control::ClearLineFrom
    jmp Return
.endproc

;; Function 0, 80 columns: clears from the cursor to the end of the window.
;; Also: B_CLREOP (IIEROM82, IIETRM85), CXCLREOP80 (UNKN)
.proc ClearToEndOfWindow80
    jsr Control::ClearToEndOfWindow
    jmp Return
.endproc

;; Function 8, 80 columns: goes on in <SetWindowWidth>.
;;
;; Nothing branches here, but <Dispatch80> reaches it for function 8: <Handlers80> holds functions 0-5 only, and its
;; ninth byte is <Control::ScrollEdges>'s third, $E6, this routine's address minus one.
;; Also: B_SETWND (IIEROM82, IIETRM85), CXSETWND80 (UNKN)
.proc SetWindow80
    jmp SetWindowWidth
.endproc

;; Function 5, which the Monitor's reset calls, in both tables: goes on in <ResetFirmware>.
;; Also: B_RESET (IIEROM82, IIETRM85), CXRESET (UNKN)
.proc Reset
    jmp ResetFirmware
.endproc

;; Function 1, 80 columns: moves the cursor to the window's top left and clears the window.
;;
;; Then gives the Monitor the firmware's cursor: its column in <CursorColumn> and
;; <EightyColumns::LastCursorColumn>, its line in <CV> and the line's base address.
;; Also: B_HOME (IIEROM82, IIETRM85), CXHOME80 (UNKN)
.proc Home80
    jsr Control::HomeAndClear
    lda EightyColumns::CursorColumn
    sta CursorColumn
    sta EightyColumns::LastCursorColumn
    lda EightyColumns::CursorLine
    sta CV
    ; Always: the line is 0-23.
    bpl BaseAndReturn
.endproc

;; Runs a screen function's 80-column version through <Handlers80>, after <Prepare80>.
;;
;; Sets the cursor line's base address. <CursorColumn> becomes the firmware's column when 80 columns are off, or when it
;; differs from the column the firmware last gave it, which means a program moved the cursor.
;; In: Y = the function number
;; Also: B_VECTOR (IIEROM82)
.proc Dispatch80
    jsr LineBase
    lda CursorColumn
    bit Columns80State
    bpl AdoptColumn
    cmp EightyColumns::LastCursorColumn
    beq ByTable

;; Takes <CursorColumn> as the firmware's column.
;; Also: B_GETCH (IIEROM82)
AdoptColumn:
    sta EightyColumns::CursorColumn

;; Runs the handler: the table holds its address minus one, so the RTS lands on it.
;; Also: B_FUNC1 (IIEROM82)
ByTable:
    lda #HANDLER_PAGE
    pha
    lda Handlers80,y
    pha
    rts
.endproc

;; Makes the window full width, 80 columns or 40 as the display is, and 24 lines deep, and moves the cursor to the
;; last line, for function 8 in 80 columns.
;; Out: WindowWidth, WindowBottom, CV = the last line, TextBase/TextBaseHigh = its base address
;; Also: B_SETWNDX (IIEROM82, IIETRM85), SETWND80 (UNKN)
.proc SetWindowWidth
    lda #WIDTH_80
    bit Columns80State
    bmi StoreWidth
    ; Half: 40.
    lsr a

;; Stores the width, the bottom and the cursor line.
;; Also: B_SETWND2 (IIEROM82)
StoreWidth:
    sta WindowWidth
    lda #FULL_WINDOW_BOTTOM
    sta WindowBottom
    lda #LAST_LINE
    sta EightyColumns::CursorLine
    sta CV
    ; Falls into BaseAndReturn.
.endproc

;; Sets the firmware's cursor line's base address, then returns: <Home80> branches here and <SetWindowWidth> falls in.
;; Also: GOBACK (IIEROM82)
BaseAndReturn:
    jsr LineBase
    jmp Return

;; Resets the 80-column firmware, for the Monitor's reset.
;;
;; Marks the firmware inactive and switches annunciators 2 and 3 on. With Solid-Apple (<Button1>) held, runs the
;; self-test. With Open-Apple (<Button0>) held, it spoils memory first: two bytes of every page from $BF down to $02 get
;; the page's number, the offset going down one a page from $B0, so that page 3's are <SoftEntryVector>'s high byte and
;; <SoftEntryCheck>, and the Monitor's reset starts afresh instead of returning to a program. Then, when <TestAuxMemory>
;; finds no auxiliary memory, slot 3's own ROM is switched in.
;; Also: B_RESETX (IIEROM82, IIETRM85), RESETFW (UNKN)
.proc ResetFirmware
    lda #MODE_INACTIVE
    sta EightyColumns::Mode
    lda Annunciator2On
    lda Annunciator3On
    lda Button1
    bmi ToSelfTest
    lda Button0
    bpl ChooseSlot3Rom

    ; Open-Apple: from the top page down.
    ldy #SPOIL_FIRST_OFFSET
    lda #0
    sta Address1
    lda #SPOIL_FIRST_PAGE
    sec

;; Stores the page's number in two bytes of it, the second one lower.
;; Also: BLAST (IIEROM82, IIETRM85)
SpoilPage:
    sta Address1High
    sta (Address1),y
    dey
    sta (Address1),y
    sbc #1
    cmp #SPOIL_END_PAGE
    bne SpoilPage
    beq ChooseSlot3Rom

;; Solid-Apple: the self-test.
;; Also: DIAGS (IIEROM82)
ToSelfTest:
    jmp SelfTest::Run

;; Switches slot 3's own ROM in when <TestAuxMemory> finds no auxiliary memory, then returns.
;; Also: RESETRET (IIEROM82, IIETRM85)
ChooseSlot3Rom:
    jsr TestAuxMemory
    beq ToReturn
    sta SlotC3RomOn
    ; Always: TESTCARD's result was not zero.
    bne ToReturn
.endproc

;; Function 7, which the Monitor calls after reading a key in escape mode: makes a letter uppercase, and the arrow keys
;; I, J, K and M.
;;
;; Clears bit 5 of any key, not only a letter's; then left, right, down and up (<ArrowKeys>) become J, K, M and I
;; (<ArrowLetters>).
;; In: A = the key
;; Out: A = the key, translated
;; Also: B_ESCFIX (IIEROM82, IIETRM85), CXESCKEY (UNKN)
.proc EscapeKey
    and #<~LOWERCASE_BIT
    ldy #ARROW_COUNT - 1

;; Compares the key with an arrow key, and takes its letter when they match.
;; Also: B_ESCFIX2 (IIEROM82, IIETRM85)
Compare:
    cmp ArrowKeys,y
    bne Next
    lda ArrowLetters,y

;; The next arrow key, down to the first.
;; Also: B_ESCFIX3 (IIEROM82, IIETRM85)
Next:
    dey
    bpl Compare
    ; Falls into ToReturn.
.endproc

;; Returns: <ResetFirmware> branches here and <EscapeKey> falls in.
;; Also: GORETN (IIEROM82)
ToReturn:
    jmp Return

;; The arrow keys <EscapeKey> translates: left, right, down and up.
;; Also: ESCIN (IIEROM82, IIETRM85), ARROWKEYS (UNKN)
ArrowKeys:
    .byte KEY_BACKSPACE, KEY_RIGHT_ARROW, KEY_LINE_FEED, KEY_CONTROL_K

;; The arrow keys in <ArrowKeys> and <ArrowLetters>.
ARROW_COUNT = * - ArrowKeys

;; The letters <EscapeKey> makes the arrow keys: J, K, M and I.
;; Also: ESCOUT (IIEROM82, IIETRM85), ARROWLETTERS (UNKN)
ArrowLetters:
    .byte "JKMI"
.assert * - ArrowLetters = ARROW_COUNT, "A letter for each arrow key."

;; Function 6, the original IIe's <KeyboardIn>: waits for a key with a blinking cursor, then clears the keyboard
;; strobe.
;;
;; The cursor is a block, <CURSOR_BLOCK>, that alternates with the character under it, which is put back once the key
;; comes. <PollKeyboard> counts <RandomSeed>/<RandomSeedHigh> while it waits. When the Monitor's caller had
;; interrupts enabled (its status is the lower of the two <Monitor:CallFirmware> pushed), <PollKeyboard> has
;; <RestoreAfterFirmware> let them in on every poll, and polls fewer times for each half of the blink.
;; In: A = the character under the cursor
;; Out: A = the key, with its high bit set
;; Keeps: X
;; Also: B_KEYIN (IIEROM82, IIETRM85), CXKEYIN (UNKN)
.proc GetKey

;; The character under the cursor.
Character = FirmwareScratch

    ; The caller's status, put back under the other: three shifts move its interrupt flag into the carry.
    sta Character
    pla
    tay
    pla
    pha
    ror a
    ror a
    ror a
    tya
    pha
    txa
    pha

    ; Overflow set: interrupts were enabled, so PollKeyboard lets them in. SEV is an RTS, whose bit 6 BIT copies.
    clv
    bcs Blink
    bit Screen::OverflowByte

;; Shows the block and waits, then the character and waits, until a key comes.
;; Also: B_KEYIN2 (IIEROM82)
Blink:
    lda #CURSOR_BLOCK
    ldy CursorColumn
    sta (TextBase),y
    jsr PollKeyboard
    bcs GotKey
    lda Character
    ldy CursorColumn
    sta (TextBase),y
    jsr PollKeyboard
    bcs GotKey
    bcc Blink

;; Puts the character back, then reads the key and clears the strobe.
;; Also: GOTKEY (IIEROM82)
GotKey:
    lda Character
    ldy CursorColumn
    sta (TextBase),y
    pla
    tax
    lda Keyboard
    sta KeyboardStrobe
    ; Always: the key has its high bit set.
    bmi Return
.endproc

;; Polls the keyboard for one half of <GetKey>'s blink, counting <RandomSeed>/<RandomSeedHigh>.
;;
;; With overflow set it calls <RestoreAfterFirmware> on every poll, to let interrupts in, and polls
;; <POLLS_WITH_INTERRUPTS> times 256; otherwise <POLLS_WITHOUT_INTERRUPTS> times 256.
;; In: overflow = set to let interrupts in
;; Out: A = the last read of <Keyboard>, the key with its high bit set when one is waiting, carry = set when a key is
;;      waiting, clear when the time ran out
;; Keeps: overflow
;; Also: KEYDLY (IIEROM82)
.proc PollKeyboard
    ldx #POLLS_WITH_INTERRUPTS
    bvs Outer
    ldx #POLLS_WITHOUT_INTERRUPTS

;; 256 polls.
;; Also: IK1 (IIEROM82)
Outer:
    ldy #0

;; One poll, letting interrupts in first with overflow set.
;; Also: IK2 (IIEROM82)
Inner:
    bvc StirSeed
    php
    jsr RestoreAfterFirmware
    plp

;; Counts the random seed.
;; Also: IK2A (IIEROM82)
StirSeed:
    inc RandomSeed
    bne ReadKeyboard
    inc RandomSeedHigh

;; Reads the keyboard.
;; Also: IK3 (IIEROM82)
ReadKeyboard:
    lda Keyboard
    bmi KeyWaiting
    dey
    bne Inner
    dex
    bne Outer

;; No key: carry clear. Nothing branches here.
;; Also: KDRETN (IIEROM82)
NoKey:
    clc
    bcc Done

;; A key: carry set.
;; Also: KDRETY (IIEROM82)
KeyWaiting:
    sec

;; Returns.
;; Also: KDRET (IIEROM82)
Done:
    rts
.endproc

;; The exit every function leaves through: pulls the status <Monitor:CallFirmware> pushed last, and returns through
;; <SlotRomReturn>, which switches slot ROM in, unless internal ROM was in before the call.
;; Also: F_RETURN (IIEROM82, IIETRM85), CXEXIT (UNKN)
.proc Return
    plp
    bmi ReturnInternal
    jmp SlotRomReturn
.endproc

;; The exit when internal ROM was in before the call: returns through <SlotRomReturn> past its switch, at
;; <Monitor:SlotRomReturn::PullStatus>, leaving the ROM as it is.
;; Also: F_RET1 (IIEROM82, IIETRM85), CXEXITINT (UNKN)
ReturnInternal:
    ; SlotRomReturn's first instruction, sta InternalCxRomOff, is three bytes.
    jmp SlotRomReturn + 3

;; Clears a line of the 40-column screen from a column to the window's right edge.
;; In: Y = the column, TextBase/TextBaseHigh = the line
;; Out: A = a space, Y = <WindowWidth> when the column was inside the window, carry = set
;; Keeps: X
;; Also: X_CLEOLZ (IIEROM82), CLRLINE40 (UNKN), X_CLREOLZ (IIETRM85)
.proc ClearColumns40
    lda #' '

;; Stores a space in each column.
;; Also: X_CLEOL2 (IIEROM82)
NextColumn:
    sta (TextBase),y
    iny
    cpy WindowWidth
    bcc NextColumn
    rts
.endproc

    ; Unused.
    .res 2, 0

.endscope
