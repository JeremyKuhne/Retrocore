; retrocore: style=strict
;; The text screen's output, $FBC1-$FCA7: line base addresses, the bell, the cursor moves, the escape commands,
;; clearing and scrolling, and on the IIe the glue around the internal firmware that does much of it.

; The text screen's layout.

;; A text line's bits 1 and 2, once bit 0 is shifted out: which page of the screen's four the line is in.
TEXT_LINE_PAGE_BITS = %00000011

;; A text line's bits 3 and 4: which third of the screen the line is in, each third $28 bytes on from the last.
TEXT_LINE_THIRD_BITS = %00011000

;; What an odd text line adds to its base address: it is in the second half of its page.
TEXT_ODD_LINE = $80

; The bell.

;; The delay count before the bell's tone, about 11 ms.
BELL_PAUSE = $40

;; The delay count between the speaker's toggles, about 0.5 ms, a tone of about 1 kHz.
BELL_HALF_CYCLE = $0C

;; How many times the bell toggles the speaker: 192, about 0.1 seconds of tone.
BELL_TOGGLES = $C0

; Escape commands.

;; Added with the carry set, takes 2 off the command: each step of <Escape::Command> checks two more letters.
COMMAND_PAIR_STEP = $100 - 3

; Slots.

;; The page of slot 1's ROM, the lowest page <ExpansionRomSlot> can name a slot by.
FIRST_SLOT_PAGE = $C1

.if MONITOR = MONITOR_IIE
.assert FIRMWARE_CLEAR_LINE_FROM = FIRMWARE_CLEAR_TO_END_OF_LINE + 1, "ClearLineFrom counts on this."
.endif

;; Computes a text line's base address on page one.
;;
;; At $FBC1.
;; In: A = the line, 0-23
;; Out: TextBase/TextBaseHigh = the line's address, A = its low byte, carry = clear
;; Keeps: X, Y
;; Also: BASCALC (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc BaseAddress
.assert * = $FBC1, "BaseAddress must stay at $FBC1."
    pha

    ; The high byte: page one's, plus the line's page.
    lsr a
    and #TEXT_LINE_PAGE_BITS
    ora #>TextPage1
    sta TextBaseHigh

    ; The low byte: $80 for an odd line (bit 0, now in the carry), plus $28 for each third.
    pla
    and #TEXT_LINE_THIRD_BITS
    bcc StoreLow
    ; The carry is set, so this adds TEXT_ODD_LINE.
    adc #TEXT_ODD_LINE - 1

    ; Times five for the third's $28: the value, plus itself shifted left twice.
;; Stores the low byte and multiplies its third by five.
;; Also: BASCLC2 (A2RM79, IIEROM82, IIETRM85)
StoreLow:
    sta TextBase
    asl a
    asl a
    ora TextBase
    sta TextBase
    rts
.endproc

;; Rings the bell when A is Control-G: about 0.1 seconds at about 1 kHz.
;;
;; At $FBD9. <ScreenOutDirect> sends every control character it does not perform here, and the others are
;; ignored.
;; In: A = the character
;; Keeps: X
;; Also: BELL1 (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc RingBell
.assert * = $FBD9, "RingBell must stay at $FBD9."
    cmp #KEY_BELL
    bne Done

    ; From here the bell rings whatever A held: a pause, then the tone.
    lda #BELL_PAUSE
    jsr Delay
    ldy #BELL_TOGGLES

;; Toggles the speaker once.
;; Also: BELL2 (A2RM78, A2RM79, IIEROM82, IIETRM85)
Cycle:
    lda #BELL_HALF_CYCLE
    jsr Delay
    lda Speaker
    dey
    bne Cycle

;; Also: RTS2B (A2RM78, A2RM79, IIEROM82, IIETRM85)
Done:
    rts
.endproc

;; Stores a character at the cursor, then moves the cursor right.
;;
;; At $FBF0.
;; In: A = the character, as the screen shows it
;; Also: STORADV (A2RM79, IIEROM82, IIETRM85)
.proc StoreAndAdvance
.assert * = $FBF0, "StoreAndAdvance must stay at $FBF0."
    ldy CursorColumn
    sta (TextBase),y
    ; Falls into AdvanceCursor.
.endproc

;; Moves the cursor right; at the window's right edge, starts a new line.
;;
;; At $FBF4.
;; Entry:
;;   Done = the return that <Backspace>, and on the Enhanced IIe <CursorUp> and <Escape::Command>, share
;; Also: ADVANCE (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc AdvanceCursor
.assert * = $FBF4, "AdvanceCursor must stay at $FBF4."
    inc CursorColumn
    lda CursorColumn
    cmp WindowWidth
    bcs CarriageReturn

;; The return that <Backspace>, and on the Enhanced IIe <CursorUp> and <Escape::Command>, share.
;; Also: RTS3 (A2RM78, A2RM79, IIEROM82, IIETRM85)
Done:
    rts
.endproc

;; Prints a character at the cursor, or performs Return, line feed, backspace or the bell.
;;
;; At $FBFD. Characters below $80 are stored as they are (inverse and flashing); other control characters
;; go to <RingBell>, which ignores all but Control-G.
;; In: A = the character
;; Also: VIDOUT (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc ScreenOutDirect
.assert * = $FBFD, "ScreenOutDirect must stay at $FBFD."
    ; Printable characters, and those below $80, go on the screen.
    cmp #' '
    bcs StoreAndAdvance
    tay
    bpl StoreAndAdvance

    ; The control characters.
    cmp #KEY_CR
    beq CarriageReturn
    cmp #KEY_LF
    beq LineFeed
    cmp #KEY_BS
    bne RingBell
    ; Falls into Backspace.
.endproc

;; Moves the cursor left; at the window's left edge, to the end of the line above.
;;
;; At $FC10.
;; Also: BS (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc Backspace
.assert * = $FC10, "Backspace must stay at $FC10."
    dec CursorColumn
    bpl AdvanceCursor::Done

    ; The window's last column, on the line above.
    lda WindowWidth
    sta CursorColumn
    dec CursorColumn
    ; Falls into CursorUp.
.endproc

;; Moves the cursor up a line unless it is on the window's top line.
;;
;; At $FC1A.
;; Also: UP (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc CursorUp
.assert * = $FC1A, "CursorUp must stay at $FC1A."
    lda WindowTop
    cmp CV
.if ENHANCED
    bcs AdvanceCursor::Done
.else
    bcs SetLineBase::Done
.endif
    dec CV
    ; Falls into VerticalTab.
.endproc

;; Sets <TextBase>/<TextBaseHigh> for the cursor's line, <CV>.
;;
;; At $FC22.
;; Also: VTAB (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc VerticalTab
.assert * = $FC22, "VerticalTab must stay at $FC22."
    lda CV
    ; Falls into SetLineBase.
.endproc

.if ENHANCED

;; Sets <TextBase>/<TextBaseHigh> for a line, offset by the window's left edge.
;;
;; At $FC24. The Enhanced IIe has the internal firmware compute it (function 4), for 40 or 80 columns.
;; In: A = the line
;; Out: TextBase/TextBaseHigh
;; Entry:
;;   ToFirmware = goes to the firmware function in Y; <ClearToEndOfWindow> and <Scroll> branch here too
;; Also: VTABZ (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc SetLineBase
.assert * = $FC24, "SetLineBase must stay at $FC24."
    ; The firmware takes the line in BASL and the caller's Y in A.
    sta TextBase
    tya
    ldy #FIRMWARE_LINE_BASE

;; Goes to the firmware function in Y; <ClearToEndOfWindow> and <Scroll> branch here too.
ToFirmware:
    bne CallFirmware

    ; Unused.
    .byte $00
.endproc
.else

;; Sets <TextBase>/<TextBaseHigh> for a line, offset by the window's left edge.
;;
;; At $FC24.
;; In: A = the line
;; Out: TextBase/TextBaseHigh, A = the low byte
;; Keeps: X, Y
;; Entry:
;;   Done = the return that <CursorUp> and <Escape::Command> share
;; Also: VTABZ (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc SetLineBase
.assert * = $FC24, "SetLineBase must stay at $FC24."
    ; BaseAddress returns with the carry clear.
    jsr BaseAddress
    adc WindowLeft
    sta TextBase

;; The return that <CursorUp> and <Escape::Command> share.
;; Also: RTS4 (A2RM78, A2RM79, IIEROM82)
Done:
    rts
.endproc
.endif

; The Apple II Monitor has no earlier piece of Escape, so the scope opens here, empty, in its build; every build
; then continues it.
.if MONITOR = MONITOR_II

;; Escape mode: the keys typed after the Escape key, which move the cursor and clear the screen.
.scope Escape
.endscope
.endif

; Escape: the commands, @ and A-F.
.scope Escape continued

;; Performs an escape command: @ clears the window (<Home>), A, B, C and D move the cursor right, left, down
;; and up, E clears to the end of the line and F to the end of the window. Other keys do nothing.
;;
;; At $FC2C.
;; In: A = the key, carry = set
;; Also: ESC1 (A2RM78, IIEROM82, IIETRM85)
.proc Command
.assert * = $FC2C, "Escape::Command must stay at $FC2C."
    eor #'@'
    beq Home

    ; A and B: each step takes 2 off, so the first letter is below 0 and the second 0.
    adc #COMMAND_PAIR_STEP
    bcc AdvanceCursor
    beq Backspace

    ; C and D.
    adc #COMMAND_PAIR_STEP
    bcc LineFeed
    beq CursorUp

    ; E and F; F falls into ClearToEndOfWindow.
    adc #COMMAND_PAIR_STEP
    bcc ClearToEndOfLine
.if ENHANCED
    bne AdvanceCursor::Done
.else
    bne SetLineBase::Done
.endif
.endproc

.endscope
.if MONITOR = MONITOR_IIE
.if ENHANCED

;; Clears from the cursor to the end of the window, through the internal firmware.
;;
;; At $FC42.
;; Also: CLREOP (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc ClearToEndOfWindow
.assert * = $FC42, "ClearToEndOfWindow must stay at $FC42."
    ldy #FIRMWARE_CLEAR_TO_END_OF_WINDOW
    bne SetLineBase::ToFirmware
.endproc

;; Prints a character on the screen: in 80 columns through the internal firmware, otherwise with the
;; Control-S pause (<ScreenOutPausing>). The end of <ScreenOutNoInverse>.
;;
;; At $FC46.
;; In: A = the character as given, Y = the character to print, SavedOutputY = the caller's Y
;; Out: Y = SavedOutputY
.proc ScreenOutByWidth
.assert * = $FC46, "ScreenOutByWidth must stay at $FC46."
    bit Columns80State
    bpl FortyColumns

    ; 80 columns: the firmware prints A.
    ldy #FIRMWARE_OUTPUT
    beq Home::ToFirmware

;; Prints Y's character with the Control-S pause, then restores the caller's Y.
FortyColumns:
    tya
    pha
    jsr ScreenOutPausing
    pla
    ldy SavedOutputY
    rts
.endproc

;; Clears the window and puts the cursor at its top left, through the internal firmware.
;;
;; At $FC58.
;; Entry:
;;   ToFirmware = goes to the firmware function in Y; <ScreenOutByWidth> branches here too
;; Also: HOME (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc Home
.assert * = $FC58, "Home must stay at $FC58."
    ldy #FIRMWARE_HOME

;; Goes to the firmware function in Y; <ScreenOutByWidth> branches here too.
ToFirmware:
    jmp CallFirmware

    ; Unused.
    .byte $53, $5C, $5C, $00, $00
.endproc
.else

;; Clears from the cursor to the end of the window, through the internal firmware.
;;
;; At $FC42.
;; Also: CLREOP (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc ClearToEndOfWindow
.assert * = $FC42, "ClearToEndOfWindow must stay at $FC42."
    ldy #FIRMWARE_CLEAR_TO_END_OF_WINDOW
    beq Scroll::ToFirmware

    ; Unused bytes, holding the copyright notice.
    .byte "(C) 1981-82, APPLE"
.endproc

;; Clears the window and puts the cursor at its top left, through the internal firmware.
;;
;; At $FC58.
;; Also: HOME (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc Home
.assert * = $FC58, "Home must stay at $FC58."
    ldy #FIRMWARE_HOME
    bne Scroll::ToFirmware

    ; Unused bytes, going on with the copyright notice's name.
    .byte "RICK A"
.endproc
.endif
.else

;; Clears from the cursor to the end of the window, a line at a time, then sets <TextBase>/<TextBaseHigh> for the
;; cursor's line again.
;;
;; At $FC42.
;; Keeps: X
;; Entry:
;;   NextLine = clears line A from column Y, then the lines below it from column 0; <Home> enters here
;; Also: CLREOP (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc ClearToEndOfWindow
.assert * = $FC42, "ClearToEndOfWindow must stay at $FC42."
    ; The first line clears from the cursor.
    ldy CursorColumn
    lda CV

;; Clears line A from column Y, then the lines below it from column 0; <Home> enters here.
;; In: A = the line, Y = the column
;; Also: CLEOP1 (A2RM78, A2RM79, IIEROM82, IIETRM85)
NextLine:
    pha
    jsr SetLineBase
    ; ClearLineFrom returns with the carry set.
    jsr ClearLineFrom
    ldy #0
    pla
    ; The next line: the carry adds the one.
    adc #0
    cmp WindowBottom
    bcc NextLine
    bcs VerticalTab
.endproc

;; Clears the window and puts the cursor at its top left.
;;
;; At $FC58.
;; Keeps: X
;; Also: HOME (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc Home
.assert * = $FC58, "Home must stay at $FC58."
    lda WindowTop
    sta CV
    ldy #0
    sty CursorColumn
    beq ClearToEndOfWindow::NextLine
.endproc
.endif

;; Moves the cursor to the start of the next line.
;;
;; At $FC62.
;; Also: CR (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc CarriageReturn
.assert * = $FC62, "CarriageReturn must stay at $FC62."
    lda #0
    sta CursorColumn
    ; Falls into LineFeed.
.endproc

;; Moves the cursor down a line, scrolling the window at its bottom.
;;
;; At $FC66.
;; Also: LF (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc LineFeed
.assert * = $FC66, "LineFeed must stay at $FC66."
    inc CV
    lda CV
    cmp WindowBottom
    bcc SetLineBase

    ; The bottom line: the cursor stays on it.
    dec CV
    ; Falls into Scroll.
.endproc
.if MONITOR = MONITOR_IIE
.if ENHANCED

;; Scrolls the text window up one line and clears the bottom line, through the internal firmware.
;;
;; At $FC70.
;; Also: SCROLL (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc Scroll
.assert * = $FC70, "Scroll must stay at $FC70."
    ldy #FIRMWARE_SCROLL
    bne SetLineBase::ToFirmware
.endproc

;; Runs the user's interrupt handler: switches slot ROM in and jumps through <UserIrqVector>. The firmware's
;; interrupt code calls it.
;;
;; At $FC74.
;; Also: IRQUSER (IIETRM85)
.proc CallUserIrq
.assert * = $FC74, "CallUserIrq must stay at $FC74."
    sta InternalCxRomOff
    jmp (UserIrqVector)
.endproc

;; After the user's interrupt handler, selects again the $C800 ROM of the slot <ExpansionRomSlot> names, then goes on
;; in the firmware's interrupt code (<RestoreInterruptedState>).
;;
;; At $FC7A. The firmware jumps here with the saved <ExpansionRomSlot> on the stack.
;; Also: IRQDONE2 (IIETRM85)
.proc SelectInterruptRom
.assert * = $FC7A, "SelectInterruptRom must stay at $FC7A."
    pla
    sta ExpansionRomSlot
    cmp #FIRST_SLOT_PAGE
    bcc NoSlot

    ; A slot's page: releasing every $C800 ROM, then reading the slot's page, selects the slot's. LOC1 is
    ; pointed at the page for the read, and put back.
    sta ExpansionRomOff
    ldy #0
    ldx LOC1
    sta LOC1
    lda (SlotPointer),y
    stx LOC1

;; Switches internal ROM back in and goes on in the firmware.
;; Also: IRQNOSLT (IIETRM85)
NoSlot:
    sta InternalCxRomOn
    jmp RestoreInterruptedState
.endproc

;; The printable path of <ScreenOut>: applies <InverseMask> to a printable character, then prints it.
;;
;; At $FC95.
;; In: A = the character, carry = clear for a control character; the character pushed
;; Also: DOCOUT1 (IIETRM85)
.proc ApplyInverse
.assert * = $FC95, "ApplyInverse must stay at $FC95."
    bcc Print
    and InverseMask

;; Prints it, its push already done.
;; Also: DOCOUT2 (IIETRM85)
Print:
    jmp ScreenOutNoInverse::Pushed
.endproc
.else

;; Scrolls the text window up one line and clears the bottom line, through the internal firmware.
;;
;; At $FC70.
;; Entry:
;;   ToFirmware = goes to the firmware function in Y, for the screen routines around it
;; Also: SCROLL (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc Scroll
.assert * = $FC70, "Scroll must stay at $FC70."
    ldy #FIRMWARE_SCROLL

;; Goes to the firmware function in Y, for the screen routines around it.
;; Also: XGOTOCX (IIEROM82)
ToFirmware:
    jmp CallFirmware
.endproc

;; Lets a pending interrupt run with slot ROM switched in, from inside the internal firmware, then restores
;; the ROM and the displayed page.
;;
;; At $FC75. The firmware's keyboard wait calls it when its caller had interrupts enabled. With 80STORE on,
;; page one is displayed meanwhile (page two would switch the screen's memory to the auxiliary bank).
;; Keeps: A, X, Y
;; Also: VIDSYNC (UNKN), SNIFFIRQ (IIEROM82)
.proc RestoreAfterFirmware
.assert * = $FC75, "RestoreAfterFirmware must stay at $FC75."
    ; The carry = 80STORE on, then negative = page two displayed; both saved.
    pha
    lda Store80State
    asl a
    pla
    bit Page2State
    php
    bcc SelectSlotRom
    sta Page2Off

;; Notes whether internal ROM was in, switches slot ROM in and lets an interrupt in.
;; Also: RDCX (IIEROM82)
SelectSlotRom:
    bit InternalCxRomState
    sta InternalCxRomOff
    cli
    sei
    bpl RestorePage
    sta InternalCxRomOn

;; Pulls the saved flags and displays page two again if it was displayed under 80STORE.
;; Also: ISSLOTS (IIEROM82)
RestorePage:
    plp
    bcc Done
    bpl Done
    bit Page2On

;; Also: ISPAGE1 (IIEROM82)
Done:
    rts

    ; Unused.
    .byte $EA, $EA
.endproc
.endif
.else

;; Scrolls the text window up one line and clears the bottom line.
;;
;; At $FC70. From the window's top line down, each line gets a copy of the one below it, from the window's right edge to
;; its left; then the bottom line is cleared and <TextBase>/<TextBaseHigh> set for the cursor's line again.
;; Keeps: X
;; Also: SCROLL (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc Scroll
.assert * = $FC70, "Scroll must stay at $FC70."
    ; The stack holds the line being read.
    lda WindowTop
    pha
    jsr SetLineBase

;; The line just read becomes the one to fill, and the next line down the one to read.
;; Also: SCRL1 (A2RM78, A2RM79, IIEROM82, IIETRM85)
NextLine:
    lda TextBase
    sta ScrollBase
    lda TextBaseHigh
    sta ScrollBaseHigh
    ldy WindowWidth
    dey
    pla
    adc #1
    cmp WindowBottom
    bcs ClearBottom
    pha
    jsr SetLineBase

;; Copies a character up a line.
;; Also: SCRL2 (A2RM78, A2RM79, IIEROM82, IIETRM85)
CopyCharacter:
    lda (TextBase),y
    sta (ScrollBase),y
    dey
    bpl CopyCharacter
    bmi NextLine

;; Clears the bottom line, which BASL/BASH still hold.
;; Also: SCRL3 (A2RM78, A2RM79, IIEROM82, IIETRM85)
ClearBottom:
    ldy #0
    ; ClearLineFrom returns with the carry set.
    jsr ClearLineFrom
    bcs VerticalTab
.endproc
.endif
.if MONITOR = MONITOR_IIE
.if ENHANCED

;; Clears from the cursor to the end of the line, through the internal firmware.
;;
;; At $FC9C. With the carry set, it goes on past <ClearLineFrom>'s first byte.
;; Also: CLREOL (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc ClearToEndOfLine
.assert * = $FC9C, "ClearToEndOfLine must stay at $FC9C."
    sec
    ; A bcc, never taken: it skips ClearLineFrom's clc.
    .byte $90
.endproc

;; Clears a line from a column to its end, through the internal firmware.
;;
;; At $FC9E.
;; In: Y = the column, TextBase/TextBaseHigh = the line
;; Also: CLREOLZ (IIEROM82, IIETRM85), CLEOLZ (A2RM78, A2RM79)
.proc ClearLineFrom
.assert * = $FC9E, "ClearLineFrom must stay at $FC9E."
    clc

    ; The firmware takes the column from BAS2L. ClearToEndOfLine (the carry set) is the function before.
    sty ScrollBase
    ldy #FIRMWARE_CLEAR_TO_END_OF_LINE
    bcs KeyboardIn::ToFirmware
    iny
    bne KeyboardIn::ToFirmware
.endproc
.else

;; Clears from the cursor to the end of the line, through the internal firmware.
;;
;; At $FC9C. With the carry clear, it goes on past <ClearLineFrom>'s first byte.
;; Also: CLREOL (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc ClearToEndOfLine
.assert * = $FC9C, "ClearToEndOfLine must stay at $FC9C."
    clc
    ; A bcs, never taken: it skips ClearLineFrom's sec.
    .byte $B0
.endproc

;; Clears a line from a column to its end, through the internal firmware.
;;
;; At $FC9E.
;; In: Y = the column, TextBase/TextBaseHigh = the line
;; Also: CLREOLZ (IIEROM82, IIETRM85), CLEOLZ (A2RM78, A2RM79)
.proc ClearLineFrom
.assert * = $FC9E, "ClearLineFrom must stay at $FC9E."

;; The page-zero byte the original IIe's firmware takes the column from.
Column = $1F

    sec

    ; ClearToEndOfLine (the carry clear) is the function before.
    sty Column
    ldy #FIRMWARE_CLEAR_TO_END_OF_LINE
    bcc Scroll::ToFirmware
    iny
    bne Scroll::ToFirmware
.endproc
.endif
.else

;; Clears from the cursor to the end of the line.
;;
;; At $FC9C.
;; Out: carry = set
;; Keeps: X
;; Also: CLREOL (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc ClearToEndOfLine
.assert * = $FC9C, "ClearToEndOfLine must stay at $FC9C."
    ldy CursorColumn
    ; Falls into ClearLineFrom.
.endproc

;; Clears a line from a column to the window's right edge.
;;
;; At $FC9E.
;; In: Y = the column, TextBase/TextBaseHigh = the line
;; Out: carry = set
;; Keeps: X
;; Also: CLREOLZ (IIEROM82, IIETRM85), CLEOLZ (A2RM78, A2RM79)
.proc ClearLineFrom
.assert * = $FC9E, "ClearLineFrom must stay at $FC9E."
    lda #' '

;; Stores one blank.
;; Also: CLEOL2 (A2RM78, A2RM79, IIEROM82, IIETRM85)
Loop:
    sta (TextBase),y
    iny
    cpy WindowWidth
    bcc Loop
    rts
.endproc
.endif
