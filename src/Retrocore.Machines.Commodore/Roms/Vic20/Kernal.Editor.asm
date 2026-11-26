; retrocore: style=strict
; COMMODORE VIC-20 KERNAL: THE SCREEN EDITOR AND THE KEYBOARD ($E500-$EE13)
;
; The screen is 23 rows of 22 columns, but the editor works in logical lines of up to four rows (88 characters): a
; line typed or printed past a row's end takes the row below. Editor::LineLinks holds one byte a row, which says
; whether the row starts a line and which page of screen memory it is in; Editor::Line points at the cursor's
; line, Editor::Column is the cursor's column in it, 0 to 87, and Editor::Row its row on the screen.

.scope Editor continued

; The editor's first part: its constants, the kernal calls SCREEN, PLOT and IOBASE, start-up, the keyboard input and
; the end of ScreenOut.


; Character codes (PETSCII) the editor acts on. A control code with bit 7 set is the same key with SHIFT: shifted DEL
; is INST, shifted cursor down is cursor up, and so on.

;; A space.
SPACE_CHARACTER = $20

;; The quote, which turns quote mode on and off.
QUOTE_CHARACTER = $22

;; DEL, which deletes the character left of the cursor. Shifted ($94), it is INST, which opens a space at the cursor.
DELETE_CHARACTER = $14

;; Cursor down. Shifted ($91), cursor up.
CURSOR_DOWN = $11

;; RVS ON: the characters after it print reversed. Shifted ($92), RVS OFF.
REVERSE_ON = $12

;; HOME: the cursor to the top left. Shifted ($93), CLR, which clears the screen too.
CURSOR_HOME = $13

;; Cursor right. Shifted ($9D), cursor left.
CURSOR_RIGHT = $1D

;; CHR$(14): switches the screen to the character set with lower case.
LOWER_CASE = $0E

;; CHR$(142): switches back to the set with upper case and graphics.
UPPER_CASE = $8E

;; CHR$(8): locks the character set, so SHIFT with C= no longer switches it.
LOCK_CASE = $08

;; CHR$(9): unlocks the character set.
UNLOCK_CASE = $09

;; The code the RUN/STOP key gives without SHIFT.
STOP_KEY = $03

;; The code shifted RUN/STOP gives: <Input> types LOAD and RUN for it.
RUN_KEY = $83

;; Pi, as programs print it and as CHRIN returns it.
PI_CHARACTER = $FF

;; Pi as <Input> first converts it from its screen code, before it becomes <PI_CHARACTER>.
PI_FROM_SCREEN = $DE

;; A character code's bit 7: the shifted half of the codes, $80-$FF.
SHIFTED_BIT = $80

;; A character code's bit 6: with bit 5 clear, the code is a letter, $40-$5F, or with bit 7 too a graphic, $C0-$DF.
LETTER_GROUP = $40

;; The first of the codes $60-$7F, which print the graphics of $C0-$DF.
FIRST_DUPLICATE = $60

;; Clears bit 5, which turns the codes $60-$7F into the screen codes $40-$5F.
DUPLICATE_MASK = $DF

;; A code's bits 0-5: a character's place in its group of 64, which its screen code shares.
CHARACTER_BITS = $3F

; Screen codes, the bytes screen memory holds.

;; A screen code's bit 7: the character reversed.
SCREEN_REVERSED = $80

;; A screen code's bit 6: the character set's second quarter, the shifted characters ($40-$7F).
SCREEN_SHIFTED = $40

;; Pi's screen code.
PI_SCREEN_CODE = $5E

;; The characters shifted RUN/STOP types, the length of <RunKeyText>.
RUN_KEY_TEXT_LENGTH = 9

; The line links in LineLinks.

;; A link's bit 7: the row starts a logical line; clear, it continues the row above.
LINE_START = $80

;; A link's bits 0-1: the low bits of the row's page in screen memory, which <ScreenPage> is ORed onto; the colour
;; RAM's page for the row takes them too.
LINK_PAGE = $03

;; The byte after the last link, <ClearScreen>'s end marker: a line start, so a search down for one stops there.
LINKS_END = $FF

; The VIC.

;; The VIC's registers, $9000-$900F, that <VicSetup> sets.
VIC_REGISTER_COUNT = 16

;; <ScreenPage>'s bit 1, the screen's address bit 9: set for a screen that starts half way into a kilobyte, as
;; $1E00 does.
SCREEN_ADDRESS_BIT_9 = $02

;; <VicScreenAndCharacters>' bit 7: the screen is in the processor's RAM at $0000-$1FFF, not at $8000-$9FFF.
VIC_SCREEN_IN_RAM = $80

;; <VicColumns>' bit 7: bit 9 of the screen's and the colour RAM's addresses.
VIC_ADDRESS_BIT_9 = $80

;; <VicScreenAndCharacters>' bit 1: the characters from $8800, the set with lower case, rather than from $8000.
LOWER_CASE_SET = $02

;; <CaseSwitchLock>'s bit 7: SHIFT with C= does not switch the character set.
CASE_LOCKED = $80

; The cursor.

;; Jiffies to the cursor's first blink at start-up. <Initialize> also puts it in <BlinkOff>, so the cursor does not
;; blink until input waits for a key.
BLINK_START = 12

;; Jiffies to the cursor's next blink after a character is put on the screen.
BLINK_AFTER_PRINT = 2

;; The colour codes in <ColourCodes>, one for each of the eight character colours.
COLOUR_CODE_COUNT = 8

; The keyboard. Its 64 keys are a matrix of 8 columns and 8 rows: KeyboardColumns drives the columns, a bit low
; for each column read, and KeyboardRows reads the rows, a bit low for each key down in those columns. A key's
; matrix code is its column times 8 plus its row.

;; The matrix code <KeyDown> and <LastKey> hold when no key is down, which each key table maps to $FF.
NO_KEY = 64

;; <KeyboardRows> with no key down.
NO_ROWS = $FF

;; A key table's entry for a key with no character, which is not put in the buffer.
NO_CHARACTER = $FF

;; <KeyboardColumns> with only column 0 driven, the first the scan reads.
FIRST_COLUMN = $FE

;; The rows each column has.
MATRIX_ROWS = 8

;; <ShiftKeys>' bit 0, and the left and right SHIFT keys' entry in <UnshiftedKeys>: SHIFT is down.
SHIFT_DOWN = 1

;; <ShiftKeys>' bit 1, and the C= key's entry: the Commodore key is down.
COMMODORE_DOWN = 2

;; <ShiftKeys>' bit 2, and the CTRL key's entry: CTRL is down.
CONTROL_DOWN = 4

;; <KeyboardColumns> with only column 2 driven: the column CTRL is in, at row 0.
CONTROL_COLUMN = $FB

;; <KeyboardRows> with only row 0 low: CTRL down, with nothing else in its column.
CONTROL_ALONE = $FE

;; <KeyboardColumns> with only column 3 driven: the column the STOP key is in, which <KernalTickClock> reads for
;; <StopKeyRow>.
STOP_COLUMN = $F7

;; <ControlKeys>' entry in <KeyTables>, which CTRL picks with or without the other shift keys.
CONTROL_TABLE = 3

;; The keyboard buffer's size at start-up, in <KeyboardBufferSize>. <Initialize> also starts <RepeatDelay> at it.
KEYBOARD_BUFFER_LENGTH = 10

;; Jiffies a new key is held before it starts to repeat.
REPEAT_DELAY_JIFFIES = 16

;; Jiffies between the repeats of a held key.
REPEAT_JIFFIES = 4

;; The kernal call IOBASE: X and Y are the address of VIA 1, $9110, so a program finds the I/O through the call
;; rather than by a fixed address.
;; Commodore's listing names it IOBASE (KV20), the name of <KernalIoBase>.
;; Out:   X = $10, the low byte, Y = $91, the high byte
;; Keeps: A
.proc IoBase
    ldx #<Via1PortB
    ldy #>Via1PortB
    rts
.endproc

;; The kernal call SCREEN: the screen's size, 22 columns by 23 rows.
;; Out:   X = 22, the columns, Y = 23, the rows
;; Keeps: A
;; Also: SCRORG (KV20)
.proc ScreenSize
    ldx #SCREEN_COLUMNS
    ldy #SCREEN_ROWS
    rts
.endproc

;; The kernal call PLOT: reads the cursor's place, or moves the cursor.
;;
;; With carry clear the cursor moves to row X, column Y, which are not checked, and returns them as <Plot::Read>
;; does, so Y then is the column in the logical line: Y plus 22 for each row of the line above row X.
;; Commodore's listing names it PLOT (KV20), the name of <KernalPlot>.
;; In:    carry = set to read the place, clear to move the cursor, X = the row, Y = the column (to move)
;; Out:   X = the cursor's row, 0-22, Y = its column in its logical line, 0-87
;; Keeps: carry
.proc Plot
    bcs Read
    stx Row
    sty Column
    jsr PlaceCursor

;; Reads the cursor's place back.
;; Also: PLOT10 (KV20)
Read:
    ldx Row
    ldy Column
    rts
.endproc

;; The kernal call CINT: resets the VIC, points it at the screen <ScreenPage> says, sets the editor's variables, and
;; clears the screen.
;;
;; <Startup::Reset> and the BRK and RESTORE handling call it.
;; In:    ScreenPage = the screen's page, $10 or $1E
;; Also: CINT (KV20)
.proc Initialize
    jsr ResetDevices

    ; The screen's address, without its bit 9, to the VIC's register 5, with the characters from $8000.
    lda ScreenPage
    and #<~SCREEN_ADDRESS_BIT_9
    asl a
    asl a
    ora #VIC_SCREEN_IN_RAM
    sta VicScreenAndCharacters

    ; Its bit 9 to the VIC's register 2.
    lda ScreenPage
    and #SCREEN_ADDRESS_BIT_9
    beq WholeKilobyte
    lda #VIC_ADDRESS_BIT_9
    ora VicColumns
    sta VicColumns

;; The editor's variables; a screen on a kilobyte's boundary comes straight here, with bit 9 left clear.
;; Also: NOHALF (KV20)
WholeKilobyte:
    lda #0
    sta CaseSwitchLock
    sta CursorShown

    ; The shift keys pick the key tables through SelectKeyTable.
    lda #<SelectKeyTable
    sta KeyTableSetup
    lda #>SelectKeyTable
    sta KeyTableSetup+1

    ; The keyboard buffer's size and the key repeat's timing.
    lda #KEYBOARD_BUFFER_LENGTH
    sta KeyboardBufferSize
    sta RepeatDelay
    lda #COLOUR_BLUE
    sta TextColour
    lda #REPEAT_JIFFIES
    sta RepeatInterval

    ; The cursor does not blink until input waits.
    lda #BLINK_START
    sta BlinkCountdown
    sta BlinkOff
    ; Falls into ClearScreen.
.endproc

;; Clears the screen: makes every row a line of its own, fills every row with spaces in white, and homes the cursor.
;;
;; Called by CLR, shifted HOME.
;; In:    ScreenPage = the screen's page
;; Also: CLSR (KV20, MTV)
.proc ClearScreen
    lda ScreenPage
    ora #LINE_START
    tay
    lda #0
    tax

;; Each row's link: a line's start, in the page the row starts in. 24 links, the last for a row just below the
;; screen, where the cursor may be for a moment before the screen scrolls.
;; Also: LPS1 (KV20)
NextLink:
    sty LineLinks,x
    clc
    adc #SCREEN_COLUMNS
    bcc SamePage
    iny

;; The next row starts in the same page as this one.
;; Also: LPS2 (KV20)
SamePage:
    inx
    cpx #SCREEN_ROWS+1
    bne NextLink
    lda #LINKS_END
    sta LineLinks,x
    ldx #SCREEN_ROWS-1

;; Clears the rows, from the bottom one up.
;; Also: CLEAR1 (KV20)
NextRow:
    jsr ClearRow
    dex
    bpl NextRow
    ; Falls into Home.
.endproc

;; HOME: moves the cursor to the top left.
;; Out:   Row = 0, Column = 0, Line = the top row's address, LineLength = the line's last column
;; Also: NXTD (KV20)
.proc Home
    ldy #0
    sty Column
    sty Row
    ; Falls into PlaceCursor.
.endproc

;; Finds the logical line the cursor is in, from <Row> and <Column>: the line's first row, the cursor's column in the
;; line, and the line's length.
;; In:    Row = the cursor's row, Column = its column in that row, or in the line from that row
;; Out:   Line = the line's first row's address, Column = the cursor's column in the line, LineLength = the line's
;;          last column, 21, 43, 65 or 87, A = <LineLength>, X = the row after the line, negative = set, zero = clear
;; Also: STUPT (KV20)
.proc PlaceCursor
    ldx Row
    lda Column

;; Back up to the line's first row, adding 22 to the column for each row above the cursor's.
;; Also: FNDSTR (KV20)
FindLineStart:
    ldy LineLinks,x
    bmi LineStartFound
    clc
    adc #SCREEN_COLUMNS
    sta Column
    dex
    bpl FindLineStart

;; The line's first row is row X: <Line> = its address, from the page in its link and the low byte in <RowStarts>.
;; Also: STOK (KV20)
LineStartFound:
    lda LineLinks,x
    and #LINK_PAGE
    ora ScreenPage
    sta Line+1
    lda RowStarts,x
    sta Line
    lda #SCREEN_COLUMNS-1
    inx

;; On down the rows that continue the line, adding 22 to its length for each.
;; Also: FNDEND (KV20)
FindLineEnd:
    ldy LineLinks,x
    bmi Done
    clc
    adc #SCREEN_COLUMNS
    inx
    bpl FindLineEnd

;; <LineLength> = the line's last column.
;; Also: STDONE (KV20)
Done:
    sta LineLength
    rts
.endproc

;; Resets the devices and the VIC and homes the cursor, without clearing the screen.
;;
;; Nothing in the ROM calls it; the listing calls it the 'PANIC NMI ENTRY'.
;; Also: VPAN (KV20)
.proc ResetScreen
    jsr ResetDevices
    jmp Home
.endproc

;; Makes the screen the output device and the keyboard the input device, and resets the VIC's registers.
;; Out:   OutputDevice = 3, the screen, InputDevice = 0, the keyboard, X = 0
;; Keeps: Y
;; Also: PANIC (KV20)
.proc ResetDevices
    lda #DEVICE_SCREEN
    sta OutputDevice
    lda #DEVICE_KEYBOARD
    sta InputDevice
    ; Falls into InitializeVic.
.endproc

;; Loads the VIC's 16 registers from <VicSetup>.
;; Out:   X = 0
;; Keeps: Y
;; Also: INITV (KV20)
.proc InitializeVic
    ldx #VIC_REGISTER_COUNT

;; Each register, from the last.
;; Also: PX4 (KV20)
Next:
    lda VicSetup-1,x
    sta VicRegisters-1,x
    dex
    bne Next
    rts
.endproc

;; Takes the first key from the keyboard buffer and moves the others up.
;;
;; The buffer must hold a key. The caller masks interrupts, so the keyboard scan does not add a key meanwhile; this
;; enables them again.
;; In:    KeyboardBufferCount = the keys in the buffer, 1 or more, interrupt = set
;; Out:   A = the key, Y = the key, carry = clear, interrupt = clear
;; Also: LP2 (KV20, MTV)
.proc TakeKey
    ldy KeyboardBuffer
    ldx #0

;; Moves each key up one.
;; Also: LP1 (KV20)
Shift:
    lda KeyboardBuffer+1,x
    sta KeyboardBuffer,x
    inx
    cpx KeyboardBufferCount
    bne Shift
    dec KeyboardBufferCount
    tya
    cli
    clc
    rts
.endproc

;; CHRIN from the keyboard: the screen editor's line input.
;;
;; It prints each key typed (moving the cursor, editing the screen), until RETURN; then it reads the logical line the
;; cursor is in back from the screen, a character each call. The routine starts at the echo of a typed key; callers
;; enter at <Input::NextCharacter>, which saves X and Y for the return. When the cursor's line starts on <InputRow>,
;; as when INPUT's prompt is on it, the line is read from <InputColumn>, past the prompt; otherwise from its start.
;; Trailing spaces are left off. With the screen as the input device, <Channels::CharacterIn> sets <LineEnd> to the
;; line's last column, so that column comes back as RETURN.
;; In:    A = the key to print (at the start), InputRow = the row input started on, InputColumn = the column
;; Out:   A = the character, RETURN at the line's end, carry = clear
;; Keeps: X, Y
;; Entry:
;;   NextCharacter = CHRIN's entry: the line's next character, after waiting for the line to be typed if none is
;;     being read (<InputFromScreen> = 0).
;; Also: LOOP4 (KV20)
.proc Input
    jsr ScreenOut

;; Waits for a key in the buffer, with the cursor blinking; while it waits <ScrollDownOff> is 0, and with a key it is
;; non-zero, so a line typed past a row's end opens a new row below.
;; Also: LOOP3 (KV20)
WaitForKey:
    lda KeyboardBufferCount
    sta BlinkOff
    sta ScrollDownOff
    beq WaitForKey

    ; A key: the character under the cursor goes back, if the cursor is showing.
    sei
    lda CursorShown
    beq CursorRestored
    lda CharacterUnderCursor
    ldx ColourUnderCursor
    ldy #0
    sty CursorShown
    jsr Display

;; The cursor is off: takes the key.
;; Also: LP21 (KV20)
CursorRestored:
    jsr TakeKey
    cmp #RUN_KEY
    bne NotRun

    ; Shifted RUN/STOP: the buffer becomes LOAD and RUN, each with RETURN; any other keys in it are lost.
    ldx #RUN_KEY_TEXT_LENGTH
    sei
    stx KeyboardBufferCount

;; Copies <RunKeyText> into the buffer, from its last character, and waits again.
;; Also: LP23 (KV20)
TypeRun:
    lda RunKeyText-1,x
    sta KeyboardBuffer-1,x
    dex
    bne TypeRun
    beq WaitForKey

;; Any key but RETURN is printed, and the wait goes on.
;; Also: LP22 (KV20)
NotRun:
    cmp #CARRIAGE_RETURN
    bne Input
    ldy LineLength
    sty InputFromScreen

;; RETURN: back from the line's last column past the trailing spaces. Column 0 is not looked at.
;; Also: CLP5 (KV20)
FindLineEnd:
    lda (Line),y
    cmp #SPACE_CHARACTER
    bne LineEndFound
    dey
    bne FindLineEnd

;; <LineEnd> = the column after the last character. The line is then read from its start, or from <InputColumn> if
;; it is the line input started on.
;; Also: CLP6 (KV20)
LineEndFound:
    iny
    sty LineEnd
    ldy #0
    sty ScrollDownOff
    sty Column
    sty QuoteMode

    ; The input row has scrolled off the top (negative): from the start.
    lda InputRow
    bmi ReadScreen
    ldx Row
    jsr AdvanceCursor::FindLineStart
    cpx InputRow
    bne ReadScreen
    bne ReadScreen                  ; a second BNE, never taken: a slip the bytes keep
    lda InputColumn
    sta Column
    cmp LineEnd
    bcc ReadScreen
    bcs LineDone

;; CHRIN's entry: saves Y and X, then waits for a line unless one is being read.
;; Also: LOOP5 (KV20)
NextCharacter:
    tya
    pha
    txa
    pha
    lda InputFromScreen
    beq WaitForKey

;; Reads the screen code at <Column> and converts it to a character code.
;; Also: LOP5 (KV20)
ReadScreen:
    ldy Column
    lda (Line),y

    ; The Japanese version converted its characters here: its instructions are NOPs now, in their sizes.
    .byte $EA, $EA, $EA
    .byte $EA, $EA
    .byte $EA, $EA
    .byte $EA, $EA, $EA
    .byte $EA, $EA
    .byte $EA
    .byte $EA
    .byte $EA, $EA
    .byte $EA, $EA
    .byte $EA, $EA, $EA
    .byte $EA, $EA

    ; The code's bits 0-5 stay. Shifted, Character gives the code's bit 7 (reversed) in carry, its bit 6 (shifted)
    ; in negative and its bit 5 in overflow; a shifted screen code is a shifted character.
    sta Character
    and #CHARACTER_BITS
    asl Character
    bit Character
    bpl CheckShift
    ora #SHIFTED_BIT

;; Inside quotes, a reversed screen code skips the letters' bit: $00-$1F come back as the control codes $00-$1F,
;; and $40-$5F as $80-$9F.
;; Also: LOP54 (KV20)
CheckShift:
    bcc CheckGraphic
    ldx QuoteMode
    bne Converted

;; Screen codes with bit 5 clear are the letters: $00-$1F become $40-$5F, and the shifted $40-$5F become $C0-$DF.
;; Codes with bit 5 set, $20-$3F and $60-$7F, become $20-$3F and $A0-$BF.
;; Also: LOP52 (KV20)
CheckGraphic:
    bvs Converted
    ora #LETTER_GROUP

;; The cursor moves on a column, and a quote turns quote mode on or off. The column at <LineEnd> comes back as RETURN.
;; Also: LOP53 (KV20)
Converted:
    inc Column
    jsr ToggleQuote
    cpy LineEnd
    bne Return

;; The line's end: reading from the screen is over. RETURN is printed if the screen is the input device, or if the
;; output goes elsewhere: not when the keyboard is the input and the screen the output.
;; Also: CLP2 (KV20)
LineDone:
    lda #0
    sta InputFromScreen
    lda #CARRIAGE_RETURN
    ldx InputDevice
    cpx #DEVICE_SCREEN
    beq EchoReturn
    ldx OutputDevice
    cpx #DEVICE_SCREEN
    beq EndOfLine

;; Prints RETURN.
;; Also: CLP2A (KV20)
EchoReturn:
    jsr ScreenOut

;; A = RETURN, to return.
;; Also: CLP21 (KV20)
EndOfLine:
    lda #CARRIAGE_RETURN

;; Restores X and Y and returns the character, with pi as <PI_CHARACTER>.
;; Also: CLP1 (KV20)
Return:
    sta Character
    pla
    tax
    pla
    tay
    lda Character
    cmp #PI_FROM_SCREEN
    bne NotPi
    lda #PI_CHARACTER

;; Carry clear, and returns.
;; Also: CLP7 (KV20)
NotPi:
    clc
    rts
.endproc

;; A quote turns quote mode on or off.
;; In:    A = the character
;; Out:   QuoteMode = toggled, for a quote
;; Keeps: A, X, Y
;; Also: QTSWC (KV20)
.proc ToggleQuote
    cmp #QUOTE_CHARACTER
    bne Done
    lda QuoteMode
    eor #1
    sta QuoteMode
    lda #QUOTE_CHARACTER

;; Returns.
;; Also: QTSWL (KV20)
Done:
    rts
.endproc

;; <ScreenOut>'s last step for a character with bit 7 set: adds <SCREEN_SHIFTED> to its screen code, then shows it as
;; <ShowCharacter::Unshifted> does.
;;
;; It is jumped to, inside <ScreenOut>, with its A, X and Y on the stack, and returns from it through
;; <ShowCharacter::Finish>.
;; In:    A = the character without bit 7, $20-$7F (at <ShowCharacter::Unshifted> and <ShowCharacter::Reversed>,
;;          the screen code)
;; Out:   A = the character <ScreenOut> was given, X = its X, Y = its Y, carry = clear, interrupt = clear
;; Entry:
;;   Unshifted = Shows the screen code as it is, reversed after RVS ON.
;;   Reversed = Shows the screen code reversed: a control code in quote mode or in an insert.
;;   Finish = <ScreenOut>'s return: restores Y, X and A, with carry clear and interrupts enabled; while inserts are
;;     open, quote mode is turned off. <ScreenOut> and the routines it jumps to end here.
;; Also: NXT33 (KV20)
.proc ShowCharacter
    ora #SCREEN_SHIFTED

;; Shows the screen code as it is, reversed after RVS ON.
;; Also: NXT3 (KV20)
Unshifted:
    ldx Reverse
    beq UseInsert

;; Shows the screen code reversed: a control code in quote mode or in an insert.
;; Also: NC3 (KV20)
Reversed:
    ora #SCREEN_REVERSED

;; A character typed into an insert uses one of the spaces it opened.
;; Also: NVS (KV20)
UseInsert:
    ldx Inserts
    beq Show
    dec Inserts

;; Puts it at the cursor in <TextColour>, and moves the cursor on.
;; Also: NVS1 (KV20)
Show:
    ldx TextColour
    jsr Display
    jsr AdvanceCursor

;; <ScreenOut>'s return: restores Y, X and A, with carry clear and interrupts enabled; while inserts are open, quote
;; mode is turned off. <ScreenOut> and the routines it jumps to end here.
;; Also: LOOP2 (KV20)
Finish:
    pla
    tay
    lda Inserts
    beq RestoreRegisters
    lsr QuoteMode

;; Restores X and A.
;; Also: LOP2 (KV20)
RestoreRegisters:
    pla
    tax
    pla
    clc
    cli
    rts
.endproc

;; Moves the cursor on after a character is put on the screen, growing the line by a row past its last column.
;;
;; A line grows up to four rows: while typing (<ScrollDownOff> non-zero) <InsertLine> opens a new row below;
;; otherwise, as when a program prints, the row below joins the line as it is, and the screen scrolls first if the
;; line is at the bottom. A line already 88 long ends, and the cursor goes to the next line.
;; In:    Column = the cursor's column, LineLength = the line's last column
;; Out:   Column = the cursor's new column, Row = its row, Line = its line's address, LineLength = the line's last
;;          column
;; Entry:
;;   JoinRow = Joins row X to the line above and makes the row below a line's start (<InsertLine> enters here).
;;   PatchReturn = <EndRowPatch>'s return: adds a row to <LineLength>, with A = <LineLength> and carry clear.
;;   FindLineStart = Points <Line> at the first row of row X's line (<Input> calls it).
;; Also: WLOGIC (KV20)
.proc AdvanceCursor
    jsr CheckRowForward
    inc Column
    lda LineLength
    cmp Column
    bcs Done
    cmp #LONGEST_LINE-1
    beq LineFull
    lda ScrollDownOff
    beq GrowLine
    jmp InsertLine::FindLastRow

;; The line takes the row below as it is; if the cursor has gone below the bottom row (to row 23), the screen
;; scrolls up first.
;; Also: WLOG20 (KV20)
GrowLine:
    ldx Row
    cpx #SCREEN_ROWS
    bcc JoinRow
    jsr ScrollUp
    dec Row
    ldx Row

;; Joins row X to the line above and makes the row below a line's start (<InsertLine> enters here).
;; Also: WLOG30 (KV20)
JoinRow:
    asl LineLinks,x
    lsr LineLinks,x
    jmp EndRowPatch

;; <EndRowPatch>'s return: adds a row to <LineLength>.
;; Also: PATOUT (KV20)
PatchReturn:
    adc #SCREEN_COLUMNS
    sta LineLength

;; Back to the first row of row X's line, which <SetLinePointer> points <Line> at (<Input> calls it). Row 0 is taken
;; as a start without looking at its link.
;; Also: FINDST (KV20)
FindLineStart:
    lda LineLinks,x
    bmi LineStartFound
    dex
    bne FindLineStart

;; <Line> = that row's address.
;; Also: FINX (KV20)
LineStartFound:
    jmp SetLinePointer

;; The line is already 88 characters: the cursor goes to the next line's start.
;; Also: WLOG10 (KV20)
LineFull:
    dec Row
    jsr NextLine
    lda #0
    sta Column

;; Returns.
;; Also: WLGRTS (KV20)
Done:
    rts
.endproc

;; Cursor left, or DEL, from the first column of a logical line: to the last column of the line above.
;;
;; On the top row it stays at column 0 and ends <ScreenOut>, dropping the caller's return.
;; In:    Row = the cursor's row
;; Out:   Row = the row above, Line = its line's address, LineLength = that line's last column, Column = the same,
;;          Y = the same
;; Also: BKLN (KV20)
.proc BackUpRow
    ldx Row
    bne Previous
    stx Column
    pla
    pla
    bne ShowCharacter::Finish       ; always: the return's high byte is not 0

;; The row above, at its line's last column.
;; Also: BKLN1 (KV20)
Previous:
    dex
    stx Row
    jsr PlaceCursor
    ldy LineLength
    sty Column
    rts
.endproc

.endscope

;; CHROUT to the screen: prints a character at the cursor, or carries out a control code: the cursor keys, HOME and
;; CLR, DEL and INST, RVS ON and OFF, the colours and the character sets.
;;
;; Inside quotes, and in the spaces INST opens, the control codes print as reversed characters instead, so a program
;; line can hold them. RETURN and shifted RETURN always act, and end quote mode, reverse and the inserts; DEL acts in
;; quote mode but not in an insert, and INST in an insert but not in quote mode.
;; It and the routines it jumps to end through <Editor::ShowCharacter::Finish>.
;; In:    A = the character
;; Out:   Editor::InputFromScreen = 0, carry = clear, interrupt = clear
;; Keeps: A, X, Y
;; Also: PRT (KV20)
.proc ScreenOut
.using Editor
    pha
    sta Character
    txa
    pha
    tya
    pha
    lda #0
    sta InputFromScreen
    ldy Column
    lda Character
    bpl *+5                         ; over the JMP: bit 7 clear
    jmp Shifted
    cmp #CARRIAGE_RETURN
    bne NotReturn
    jmp CarriageReturn

;; Not RETURN: a code below a space is a control code; the others print.
;; Also: NJT1 (KV20)
NotReturn:
    cmp #SPACE_CHARACTER
    bcc Control
    cmp #FIRST_DUPLICATE
    bcc ToScreenCode
    and #DUPLICATE_MASK
    bne Show                        ; always

;; $20-$5F become the screen codes $20-$3F and $00-$1F.
;; Also: NJT8 (KV20)
ToScreenCode:
    and #CHARACTER_BITS

;; A quote turns quote mode on or off, and the character is shown.
;; Also: NJT9 (KV20)
Show:
    jsr ToggleQuote
    jmp Editor::ShowCharacter::Unshifted

;; A control code: with an insert open it prints reversed.
;; Also: NTCN (KV20)
Control:
    ldx Inserts
    beq NoInserts
    jmp Editor::ShowCharacter::Reversed

;; DEL, or another control code. DEL from the line's first column goes to the end of the line above.
;;
;; There the space goes in that line's last column, but its colour goes through <Editor::ColourLine>, which
;; <Editor::BackUpRow> does not move: it still points where it last did, normally at the line the cursor left, so
;; the colour lands in that line. This looks like a slip in the original.
;; Also: CNC3X (KV20)
NoInserts:
    cmp #DELETE_CHARACTER
    bne NotDelete
    tya
    bne Delete
    jsr BackUpRow
    jmp BlankLast

;; DEL: the cursor goes back one, up a row from a row's first column, and the rest of the line closes up.
;; Also: BAK1UP (KV20)
Delete:
    jsr CheckRowBack
    dey
    sty Column
    jsr SetColourPointer

;; Moves each character and its colour one left, to the line's end.
;; Also: BK15 (KV20)
CloseUp:
    iny
    lda (Line),y
    dey
    sta (Line),y
    iny
    lda (ColourLine),y
    dey
    sta (ColourLine),y
    iny
    cpy LineLength
    bne CloseUp

;; A space in <TextColour> at the line's end.
;; Also: BK2 (KV20)
BlankLast:
    lda #SPACE_CHARACTER
    sta (Line),y
    lda TextColour
    sta (ColourLine),y
    bpl DownDone                    ; always: a colour is below $80

;; Any other control code, in quote mode, prints reversed.
;; Also: NTCN1 (KV20)
NotDelete:
    ldx QuoteMode
    beq NotQuoted
    jmp Editor::ShowCharacter::Reversed

;; RVS ON turns <Editor::Reverse> on. Each test below fails for a code that one before it carried out.
;; Also: NC3W (KV20)
NotQuoted:
    cmp #REVERSE_ON
    bne NotReverseOn
    sta Reverse

;; HOME. <Editor::Home> leaves A = the line's length, which none of the codes tested after it is.
;; Also: NC1 (KV20)
NotReverseOn:
    cmp #CURSOR_HOME
    bne NotHome
    jsr Home

;; Cursor right: a column on, or past the line's end to the next line's start.
;; Also: NC2 (KV20)
NotHome:
    cmp #CURSOR_RIGHT
    bne NotRight
    iny
    jsr CheckRowForward
    sty Column
    dey
    cpy LineLength
    bcc RightDone
    dec Row
    jsr NextLine
    ldy #0

;; <Editor::Column> = Y.
;; Also: JPL4 (KV20)
SetColumn:
    sty Column

;; Cursor right is done.
;; Also: NCZ2 (KV20)
RightDone:
    jmp Editor::ShowCharacter::Finish

;; Cursor down: a row on in the line, or from its last row to the same column of the next line's first row.
;; Also: NCX2 (KV20)
NotRight:
    cmp #CURSOR_DOWN
    bne Colour
    clc
    tya
    adc #SCREEN_COLUMNS
    tay
    inc Row
    cmp LineLength
    bcc SetColumn
    beq SetColumn
    dec Row

;; The column in its row: the column less 22 until it would go below 0.
;; Also: CURS10 (KV20)
DownColumn:
    sbc #SCREEN_COLUMNS
    bcc DownToNextLine
    sta Column
    bne DownColumn

;; To the next logical line.
;; Also: GOTDWN (KV20)
DownToNextLine:
    jsr NextLine

;; Cursor down is done.
;; Also: JPL3 (KV20)
DownDone:
    jmp Editor::ShowCharacter::Finish

;; A colour code sets the colour; any code, through <Editor::CaseCodes>, may be one of the character set's.
;; Also: COLR1 (KV20)
Colour:
    jsr CheckColour
    jmp CaseCodes

;; A character with bit 7 set: a shifted character, or a shifted control code.
;; Also: NXTX (KV20)
Shifted:
    ; The Japanese version's kana codes were here: NOPs now, in their instructions' sizes.
    .byte $EA, $EA, $EA
    .byte $EA, $EA
    .byte $EA, $EA
    .byte $EA, $EA, $EA
    .byte $EA, $EA
    .byte $EA
    .byte $EA
    .byte $EA, $EA
    .byte $EA, $EA
    .byte $EA, $EA, $EA
    and #<~SHIFTED_BIT
    cmp #PI_CHARACTER ^ SHIFTED_BIT
    bne NotPi
    lda #PI_SCREEN_CODE

;; <PI_CHARACTER> prints as its screen code. $A0-$FE print as the shifted screen codes, $40-$7F; $80-$9F are
;; control codes.
;; Also: NXTX1 (KV20)
NotPi:
    ; More of the kana code's NOPs.
    .byte $EA, $EA
    .byte $EA, $EA
    .byte $EA, $EA
    cmp #SPACE_CHARACTER
    bcc ShiftedControl
    jmp ShowCharacter

;; Shifted RETURN goes to the next line too, as RETURN does, even in quote mode.
;; Also: UHUH (KV20)
ShiftedControl:
    cmp #CARRIAGE_RETURN
    bne ShiftedNotReturn
    jmp CarriageReturn

;; In quote mode a shifted control code prints reversed. INST opens a space at the cursor.
;; Also: UP5 (KV20)
ShiftedNotReturn:
    ldx QuoteMode
    bne ShowShifted
    cmp #DELETE_CHARACTER
    bne NotInsert
    ldy LineLength
    lda (Line),y
    cmp #SPACE_CHARACTER
    bne InsertRow
    cpy Column
    bne OpenGap

;; The line's last column holds a character, or the cursor is on it: the line grows a row first, unless it already
;; has four, when INST does nothing.
;; Also: INS3 (KV20)
InsertRow:
    cpy #LONGEST_LINE-1
    beq InsertDone
    jsr InsertLine

;; Moves the rest of the line one right, from its end.
;; Also: INS1 (KV20)
OpenGap:
    ldy LineLength
    jsr SetColourPointer

;; Each character and its colour, from the line's end back to the cursor.
;; Also: INS2 (KV20)
MoveRight:
    dey
    lda (Line),y
    iny
    sta (Line),y
    dey
    lda (ColourLine),y
    iny
    sta (ColourLine),y
    dey
    cpy Column
    bne MoveRight

    ; A space in the text colour at the cursor, and one more insert open.
    lda #SPACE_CHARACTER
    sta (Line),y
    lda TextColour
    sta (ColourLine),y
    inc Inserts

;; INST is done.
;; Also: INSEXT (KV20)
InsertDone:
    jmp Editor::ShowCharacter::Finish

;; With inserts open, a shifted control code prints reversed too.
;; Also: UP9 (KV20)
NotInsert:
    ldx Inserts
    beq NotInsertMode

;; Prints it reversed, as the shifted screen code it is under.
;; Also: UP6 (KV20)
ShowShifted:
    ora #SCREEN_SHIFTED
    jmp Editor::ShowCharacter::Reversed

;; Cursor up: a row up in the line, or from its first row to the line above. Nothing on the top row.
;; Also: UP2 (KV20)
NotInsertMode:
    cmp #CURSOR_DOWN
    bne NotUp
    ldx Row
    beq ShiftedDone
    dec Row
    lda Column
    sec
    sbc #SCREEN_COLUMNS
    bcc UpToPreviousLine
    sta Column
    bpl ShiftedDone                 ; always

;; Up past the line's first row: <Editor::PlaceCursor> finds the line above and the column in it.
;; Also: UPALIN (KV20)
UpToPreviousLine:
    jsr PlaceCursor
    bne ShiftedDone                 ; always: PlaceCursor returns zero clear

;; RVS OFF.
;; Also: NXT2 (KV20)
NotUp:
    cmp #REVERSE_ON
    bne NotReverseOff
    lda #0
    sta Reverse

;; Cursor left: a column back, up a row from a row's first column, or from the line's first column to the line
;; above's end.
;; Also: NXT6 (KV20)
NotReverseOff:
    cmp #CURSOR_RIGHT
    bne NotLeft
    tya
    beq LeftToPreviousRow
    jsr CheckRowBack
    dey
    sty Column
    jmp Editor::ShowCharacter::Finish

;; From the line's first column, to the end of the line above.
;; Also: BAKBAK (KV20)
LeftToPreviousRow:
    jsr BackUpRow
    jmp Editor::ShowCharacter::Finish

;; CLR clears the screen.
;; Also: NXT61 (KV20)
NotLeft:
    cmp #CURSOR_HOME
    bne ShiftedColour
    jsr ClearScreen

;; The shifted code is done.
;; Also: JPL2 (KV20)
ShiftedDone:
    jmp Editor::ShowCharacter::Finish

;; With bit 7 back, a colour code sets the colour; any code, through <Editor::CaseCodes::Shifted>, may be one of the
;; character set's.
;; Also: SCCL (KV20)
ShiftedColour:
    ora #SHIFTED_BIT
    jsr CheckColour
    jmp Editor::CaseCodes::Shifted
.endproc

.scope Editor continued

; The editor's second part: moving between lines, scrolling, and the screen's pointers.

;; Moves the cursor to the first row of the next logical line, scrolling the screen up when there is none below.
;;
;; <InputRow> is halved on the way (LSR), which turns a row that has scrolled off ($FF) into one no line starts on
;; ($7F); it halves an input row on the screen too, which looks unintended.
;; In:    Row = the cursor's row, Column = its column in its row (the callers set it)
;; Out:   Row = the next line's first row, Line = its address, LineLength = its last column, as <PlaceCursor> sets them
;; Also: NXLN (KV20)
.proc NextLine
    lsr InputRow
    ldx Row

;; The next row; past the bottom, the screen scrolls up and X is the row after the cursor's line.
;; Also: NXLN2 (KV20)
NextRow:
    inx
    cpx #SCREEN_ROWS
    bne CheckRow
    jsr ScrollUp

;; On until a row that starts a line.
;; Also: NXLN1 (KV20)
CheckRow:
    lda LineLinks,x
    bpl NextRow
    stx Row
    jmp PlaceCursor
.endproc

;; RETURN, and shifted RETURN: ends inserts, reverse and quote mode, and goes to the next line's start; then ends
;; <ScreenOut>.
;; It is entered with <ScreenOut>'s A, X and Y still on the stack.
;; Also: NXT1 (KV20)
.proc CarriageReturn
    ldx #0
    stx Inserts
    stx Reverse
    stx QuoteMode
    stx Column
    jsr NextLine
    jmp ShowCharacter::Finish
.endproc

;; When the cursor is on the first column of one of its line's rows (0, 22, 44 or 66), <Row> moves up one, for a
;; cursor about to move back a column.
;; In:    Column = the cursor's column in its line
;; Out:   Row = one less at a row's first column
;; Keeps: Y
;; Also: CHKBAK (KV20)
.proc CheckRowBack
    ldx #ROWS_PER_LINE
    lda #0

;; Each row's first column.
;; Also: CHKLUP (KV20)
Next:
    cmp Column
    beq Back
    clc
    adc #SCREEN_COLUMNS
    dex
    bne Next
    rts

;; Up a row.
;; Also: BACK (KV20)
Back:
    dec Row
    rts
.endproc

;; When the cursor is on the last column of one of its line's rows (21, 43, 65 or 87), <Row> moves down one, for a
;; cursor about to move on a column.
;;
;; From the bottom row it goes to 23, below the screen, which the caller scrolls
;; or steps back from; from 23 it stays.
;; In:    Column = the cursor's column in its line
;; Out:   Row = one more at a row's last column
;; Keeps: Y
;; Also: CHKDWN (KV20)
.proc CheckRowForward
    ldx #ROWS_PER_LINE
    lda #SCREEN_COLUMNS-1

;; Each row's last column.
;; Also: DWNCHK (KV20)
Next:
    cmp Column
    beq Down
    clc
    adc #SCREEN_COLUMNS
    dex
    bne Next
    rts

;; Down a row, unless already below the screen.
;; Also: DNLINE (KV20)
Down:
    ldx Row
    cpx #SCREEN_ROWS
    beq Done
    inc Row

;; Returns.
;; Also: DWNBYE (KV20)
Done:
    rts
.endproc

;; A colour code sets <TextColour> to its colour; any other code is left alone.
;; In:    A = the code
;; Out:   TextColour = the colour, 0-7, for a colour code, X = the colour, or $FF for another code
;; Keeps: A, Y
;; Also: CHKCOL (KV20)
.proc CheckColour
    ldx #COLOUR_CODE_COUNT-1

;; Each of the eight codes, from yellow's.
;; Also: CHK1A (KV20)
Next:
    cmp ColourCodes,x
    beq Found
    dex
    bpl Next
    rts

;; <TextColour> = the code's place in the table, which is its colour.
;; Also: CHK1B (KV20)
Found:
    stx TextColour
    rts
.endproc

;; The eight colour codes, by colour: black, white, red, cyan, purple, green, blue and yellow, which CTRL with 1 to 8
;; types.
;;
;; The Japanese version's conversion table follows, 38 pairs of character codes that nothing reads now.
;; Also: COLTAB (KV20)
ColourCodes:
    .byte $90, $05, $1C, $9F, $9C, $1E, $1F, $9E
    ; The Japanese version's conversion table.
    .byte $EF, $A1
    .byte $DF, $A6
    .byte $E1, $B1
    .byte $E2, $B2
    .byte $E3, $B3
    .byte $E4, $B4
    .byte $E5, $B5
    .byte $E6, $B6
    .byte $E7, $B7
    .byte $E8, $B8
    .byte $E9, $B9
    .byte $FA, $BA
    .byte $FB, $BB
    .byte $FC, $BC
    .byte $EC, $BD
    .byte $FE, $BE
    .byte $84, $BF
    .byte $F7, $C0
    .byte $F8, $DB
    .byte $F9, $DD
    .byte $EA, $DE
    .byte $5E, $E0
    .byte $5B, $E1
    .byte $5D, $E2
    .byte $40, $B0
    .byte $61, $B1
    .byte $78, $DB
    .byte $79, $DD
    .byte $66, $B6
    .byte $77, $C0
    .byte $70, $F0
    .byte $71, $F1
    .byte $72, $F2
    .byte $73, $F3
    .byte $74, $F4
    .byte $75, $F5
    .byte $76, $F6
    .byte $7D, $FD

;; Scrolls the screen up by the top logical line, characters, colours and links, and clears the rows it frees.
;;
;; <InputRow> moves up with the text; <Row> and <LinkSave> move up one row less, so a one-row scroll leaves them as
;; they were, and a caller on row 23, below the screen, steps back to the bottom row itself. Holding CTRL slows the
;; scroll and empties the keyboard buffer.
;; In:    Row = the cursor's row
;; Out:   X = <Row>, KeyboardColumns = only the STOP key's column driven
;; Keeps: StartAddress, StartAddressHigh, EndAddress, EndAddressHigh
;; Also: SCROL (KV20)
.proc ScrollUp
    lda StartAddress
    pha
    lda StartAddressHigh
    pha
    lda EndAddress
    pha
    lda EndAddressHigh
    pha

;; Up one row; again while the new top row continues a line.
;; Also: SCRO0 (KV20)
Again:
    ldx #$FF                        ; the first INX makes it row 0
    dec Row
    dec InputRow
    dec LinkSave

;; Copies each row from the row below it.
;; Also: SCR10 (KV20)
NextRow:
    inx
    jsr SetLinePointer
    cpx #SCREEN_ROWS-1
    bcs ClearBottom
    lda RowStarts+1,x
    sta StartAddress
    lda LineLinks+1,x
    jsr CopyRow
    bmi NextRow                     ; always: CopyRow returns Y = $FF

;; Clears the bottom row.
;; Also: SCR41 (KV20)
ClearBottom:
    jsr ClearRow
    ldx #0

;; Moves each row's line start bit up a row; its page bits stay.
;; Also: SCRL5 (KV20)
NextLink:
    lda LineLinks,x
    and #<~LINE_START
    ldy LineLinks+1,x
    bpl StoreLink
    ora #LINE_START

;; Stores the link.
;; Also: SCRL3 (KV20)
StoreLink:
    sta LineLinks,x
    inx
    cpx #SCREEN_ROWS-1
    bne NextLink

    ; The cleared bottom row is a line of its own.
    lda LineLinks+SCREEN_ROWS-1
    ora #LINE_START
    sta LineLinks+SCREEN_ROWS-1
    lda LineLinks
    bpl Again
    inc Row
    inc LinkSave

    ; Is CTRL down, alone in its column? Column 3 is driven again after, for the STOP key's test.
    lda #CONTROL_COLUMN
    sta KeyboardColumns
    lda KeyboardRows
    cmp #CONTROL_ALONE
    php
    lda #STOP_COLUMN
    sta KeyboardColumns
    plp
    bne Done
    ldy #0

;; CTRL is down: a delay of about 256 by 256 loops, and the keyboard buffer emptied.
;; Also: MLP4 (KV20)
Delay:
    nop
    dex
    bne Delay
    dey
    bne Delay
    sty KeyboardBufferCount

;; Restores the pointers the copies used.
;; Also: MLP42 (KV20)
Done:
    ldx Row
    pla
    sta EndAddressHigh
    pla
    sta EndAddress
    pla
    sta StartAddressHigh
    pla
    sta StartAddress
    rts
.endproc

;; Opens a new row below the cursor's logical line, for the line to grow into: the rows below move down a row, the
;; bottom line falling off the screen, and the new row joins the line.
;;
;; When the line ends on the bottom row, the screen scrolls up instead.
;; In:    Row = the cursor's row
;; Out:   Line = the line's first row's address, LineLength = 22 more, LinkSave = the new row
;; Keeps: StartAddress, StartAddressHigh, EndAddress, EndAddressHigh
;; Entry:
;;   FindLastRow = Opens the row below the line row X is in (<AdvanceCursor> enters here, with X = <Row>).
;; Also: NEWLIN (KV20)
.proc InsertLine
    ldx Row

;; Down to the row after the line's last: the row to open, in <LinkSave> (<AdvanceCursor> enters here).
;; Also: BMT1 (KV20)
FindLastRow:
    inx
    lda LineLinks,x
    bpl FindLastRow
    stx LinkSave
    cpx #SCREEN_ROWS-1
    beq ScrollDown
    bcc ScrollDown

    ; The line ends on the bottom row: the screen scrolls up, and the row below the line joins it.
    jsr ScrollUp
    ldx LinkSave
    dex
    dec Row
    jmp AdvanceCursor::JoinRow

;; Saves the pointers the copies use, then moves the rows below down.
;; Also: NEWLX (KV20)
ScrollDown:
    lda StartAddress
    pha
    lda StartAddressHigh
    pha
    lda EndAddress
    pha
    lda EndAddressHigh
    pha
    ldx #SCREEN_ROWS

;; Each row from the row above it, from the bottom up to the row to open.
;; Also: SCD10 (KV20)
NextRow:
    dex
    jsr SetLinePointer
    cpx LinkSave
    bcc ClearOpenedRow
    beq ClearOpenedRow
    lda RowStarts-1,x
    sta StartAddress
    lda LineLinks-1,x
    jsr CopyRow
    bmi NextRow                     ; always: CopyRow returns Y = $FF

;; Clears the opened row.
;; Also: SCR40 (KV20)
ClearOpenedRow:
    jsr ClearRow
    ldx #SCREEN_ROWS-2

;; Moves each row's line start bit down a row, from the bottom, to the opened row; its page bits stay.
;; Also: SCRD21 (KV20)
NextLink:
    cpx LinkSave
    bcc Done
    lda LineLinks+1,x
    and #<~LINE_START
    ldy LineLinks,x
    bpl StoreLink
    ora #LINE_START

;; Stores the link.
;; Also: SCRD19 (KV20)
StoreLink:
    sta LineLinks+1,x
    dex
    bne NextLink

;; Joins the opened row to the line, and restores the pointers.
;; Also: SCRD22 (KV20)
Done:
    ldx LinkSave
    jsr AdvanceCursor::JoinRow
    pla
    sta EndAddressHigh
    pla
    sta EndAddress
    pla
    sta StartAddressHigh
    pla
    sta StartAddress
    rts
.endproc

;; Copies a row's 22 characters and their colours to the row <Line> points at.
;; In:    A = the source row's link, StartAddress = the low byte of its address, Line = the destination's address
;; Out:   StartAddress = the source row's address, EndAddress = its colour's address, ColourLine = the
;;          destination's colour address, Y = $FF, negative = set
;; Keeps: X
;; Also: SCRLIN (KV20)
.proc CopyRow
    and #LINK_PAGE
    ora ScreenPage
    sta StartAddress+1
    jsr ColourPointers
    ldy #SCREEN_COLUMNS-1

;; Each column, from the last.
;; Also: SCD20 (KV20)
Next:
    lda (StartAddress),y
    sta (Line),y
    lda (EndAddress),y
    sta (ColourLine),y
    dey
    bpl Next
    rts
.endproc

;; Points <ColourLine> and <EndAddress> at the colour RAM for <Line> and for <StartAddress>, for a row copy.
;; In:    Line = the destination row's address, StartAddress = the source row's
;; Out:   ColourLine = the colour RAM address for <Line>, EndAddress = the one for <StartAddress>
;; Keeps: X, Y
;; Also: TOFROM (KV20)
.proc ColourPointers
    jsr SetColourPointer
    lda StartAddress
    sta EndAddress
    lda StartAddress+1
    and #LINK_PAGE
    ora #>ColourMemory
    sta EndAddress+1
    rts
.endproc

;; Points <Line> at row X: the low byte from <RowStarts>, the page from the row's link.
;; In:    X = the row
;; Out:   Line = the row's address
;; Keeps: X, Y
;; Also: SETPNT (KV20)
.proc SetLinePointer
    lda RowStarts,x
    sta Line
    lda LineLinks,x
    and #LINK_PAGE
    ora ScreenPage
    sta Line+1
    rts
.endproc

;; Clears row X to spaces in white.
;; In:    X = the row
;; Out:   Line = the row's address, ColourLine = its colour's address, Y = $FF
;; Keeps: X
;; Also: CLRLN (KV20)
.proc ClearRow
    ldy #SCREEN_COLUMNS-1
    jsr SetLinePointer
    jsr SetColourPointer

;; Each column, from the last.
;; Also: CLR10 (KV20)
Next:
    lda #SPACE_CHARACTER
    sta (Line),y
    lda #COLOUR_WHITE
    sta (ColourLine),y
    dey
    bpl Next
    rts
.endproc

;; Puts a screen code at the cursor in a colour, and restarts the cursor's blink, which comes back
;; <BLINK_AFTER_PRINT> jiffies later.
;; In:    A = the screen code, X = the colour, Line = the cursor's line, Column = the cursor's column
;; Out:   ColourLine = the line's colour RAM address, A = the colour, Y = <Column>
;; Keeps: X
;; Entry:
;;   AtCursor = Puts it there without touching the blink, with <ColourLine> already set (<Interrupts::Jiffy> blinks
;;     the cursor through it).
;; Also: DSPP (KV20)
.proc Display
    tay
    lda #BLINK_AFTER_PRINT
    sta BlinkCountdown
    jsr SetColourPointer
    tya

;; Puts it there without touching the blink, with <ColourLine> already set (<Interrupts::Jiffy> blinks the cursor
;; through it).
;; Also: DSPP2 (KV20)
AtCursor:
    ldy Column
    sta (Line),y
    txa
    sta (ColourLine),y
    rts
.endproc

;; Points <ColourLine> at the colour RAM for <Line>: the same offset, in the colour RAM's page for the screen's.
;; In:    Line = a row's address in screen memory
;; Out:   ColourLine = its colour's address
;; Keeps: X, Y
;; Also: SCOLOR (KV20)
.proc SetColourPointer
    lda Line
    sta ColourLine
    lda Line+1
    and #LINK_PAGE
    ora #>ColourMemory
    sta ColourLine+1
    rts
.endproc

.endscope

.scope Interrupts

; The interrupts' first part: the IRQ's jiffy routine, which the editor's file holds.

;; The cursor's blink: jiffies between its changes, 3 a second.
BLINK_JIFFIES = 20

;; <Via1PeripheralControl>'s bit 1: the level of CA2, which drives the cassette motor; high turns the motor off.
CASSETTE_MOTOR_OFF = $02

;; <IrqVector>'s default, the IRQ routine, 60 times a second from VIA 2's timer 1: it ticks the clock, blinks the
;; cursor, runs or stops the cassette motor as the Datasette's keys say, and scans the keyboard.
;;
;; <Interrupts::Irq> pushed A, X and Y before coming here through the vector; this restores them and returns from
;; the interrupt. A program that takes the vector over can end with a jump here, to keep the kernal's work.
;; Out:   A = the interrupted program's A, X = its X, Y = its Y, from the stack
;; Also: KEY (KV20)
.proc Jiffy
    jsr KernalTickClock

    ; The cursor blinks while input waits (BlinkOff = 0): each BLINK_JIFFIES it shows or hides.
    lda Editor::BlinkOff
    bne Cassette
    dec Editor::BlinkCountdown
    bne Cassette
    lda #BLINK_JIFFIES
    sta Editor::BlinkCountdown
    ldy Editor::Column
    lsr Editor::CursorShown
    ldx Editor::ColourUnderCursor
    lda (Editor::Line),y
    bcs Blink

    ; Showing: the character and its colour are saved, and it is shown reversed in the text colour.
    inc Editor::CursorShown
    sta Editor::CharacterUnderCursor
    jsr Editor::SetColourPointer
    lda (Editor::ColourLine),y
    sta Editor::ColourUnderCursor
    ldx TextColour
    lda Editor::CharacterUnderCursor

;; Reverses the character under the cursor: reversed to show the cursor, or back, in its own colour, to hide it.
;; Also: KEY5 (KV20)
Blink:
    eor #Editor::SCREEN_REVERSED
    jsr Editor::Display::AtCursor

;; The cassette: with none of its keys down, <CassetteMotorMode> is cleared and the motor turned off.
;; Also: KEY4 (KV20)
Cassette:
    lda Via1PortA
    and #Tape::CASSETTE_SENSE
    beq PlayDown
    ldy #0
    sty CassetteMotorMode
    lda Via1PeripheralControl
    ora #CASSETTE_MOTOR_OFF
    bne SetMotor                    ; always

;; A key is down: the motor runs, unless a tape routine has it (<CassetteMotorMode> non-zero).
;; Also: KEY3 (KV20)
PlayDown:
    lda CassetteMotorMode
    bne Scan
    lda Via1PeripheralControl
    and #<~CASSETTE_MOTOR_OFF

;; Not while RS-232 is sending (VIA 1's timer 1 interrupt enabled): its NMI rewrites this register for each bit, as
;; CB2 is its send line, and a write here could put back an old bit.
;; Also: KL24 (KV20)
SetMotor:
    bit Via1InterruptEnable
    bvs Scan
    sta Via1PeripheralControl

;; Scans the keyboard, clears the timer's interrupt by reading its low byte, restores the registers and returns from
;; the interrupt.
;; Also: KL2 (KV20)
Scan:
    jsr Editor::ScanKeyboard
    bit Via2Timer1
    pla
    tay
    pla
    tax
    pla
    rti
.endproc

.endscope

.scope Editor continued

; The editor's third part: the keyboard scan, the key tables and the character set codes.

;; The kernal call SCNKEY: scans the keyboard's matrix and puts a new key, or a held key's repeat, in the keyboard
;; buffer.
;;
;; It finds the shift keys down (<ShiftKeys>) and the last other key down (<KeyDown>), then jumps through
;; <KeyTableSetup>, normally to <SelectKeyTable>, which picks the key table for the shift keys and comes back at
;; <ScanKeyboard::Decode>. A new key starts the delay before repeating; a held key repeats as <KeyRepeat> says:
;; bit 7 set, every key; bit 6 set, none; otherwise only the space, DEL and INST, and the cursor keys. A repeat goes
;; in only when the buffer is empty, and no key goes in a full buffer. <Interrupts::Jiffy> calls it each jiffy; a
;; program that turns the IRQ off can call it through the jump table.
;; Commodore's listing names it SCNKEY (KV20), the name of <KernalScanKeyboard>.
;; Out:   LastKey = this scan's key, LastShiftKeys = its shift keys (both left alone while SHIFT and C= stay down),
;;          KeyboardColumns = only the STOP key's column driven
;; Entry:
;;   Decode = Looks the key up in <KeyTable> and buffers it, as new or repeating (<SelectKeyTable> comes back here).
;;   Done = Drives the STOP key's column for <KernalTickClock>'s test, and returns (<SelectKeyTable> ends here while
;;     SHIFT and C= stay down).
.proc ScanKeyboard
    lda #0
    sta ShiftKeys
    ldy #NO_KEY
    sty KeyDown

    ; Every column driven: no row low means no key at all.
    sta KeyboardColumns
    ldx KeyboardRows
    cpx #NO_ROWS
    beq ToStoreKey

    ; From column 0, the keys' codes through the unshifted table, where the shift keys have their bits.
    lda #FIRST_COLUMN
    sta KeyboardColumns
    ldy #0
    lda #<UnshiftedKeys
    sta KeyTable
    lda #>UnshiftedKeys
    sta KeyTable+1

;; Reads a column's rows, until two reads agree.
;; Also: SCN20 (KV20)
NextColumn:
    ldx #MATRIX_ROWS
    lda KeyboardRows
    cmp KeyboardRows
    bne NextColumn

;; Each row, from row 0: a bit low is a key down. A shift key adds its bit to <ShiftKeys>; the STOP key and the
;; codes above CTRL's are keys.
;; Also: SCN30 (KV20)
NextRow:
    lsr a
    bcs NextKey
    pha
    lda (KeyTable),y
    cmp #CONTROL_DOWN+1
    bcs KeyFound
    cmp #STOP_KEY
    beq KeyFound
    ora ShiftKeys
    sta ShiftKeys
    bpl RowDone                     ; always

;; A key that isn't a shift key: <KeyDown> = its code; the last found wins.
;; Also: SPCK2 (KV20)
KeyFound:
    sty KeyDown

;; Takes the rows back.
;; Also: CKUT (KV20)
RowDone:
    pla

;; The next of the 64 keys, and the next column after a column's eighth row. The scan stops at code 65, a row into
;; a ninth pass that drives no column.
;; Also: CKIT (KV20)
NextKey:
    iny
    cpy #NO_KEY+1
    bcs Shifts
    dex
    bne NextRow
    sec
    rol KeyboardColumns
    bne NextColumn                  ; always: a 1 shifts in

;; Through <KeyTableSetup>, to pick the table for the shift keys.
;; Also: CKIT1 (KV20)
Shifts:
    jmp (KeyTableSetup)

;; The key's character from <KeyTable>. A new key starts the delay before it repeats, and goes in the buffer.
;; Also: REKEY (KV20)
Decode:
    ldy KeyDown
    lda (KeyTable),y
    tax
    cpy LastKey
    beq SameKey
    ldy #REPEAT_DELAY_JIFFIES
    sty RepeatDelay
    bne StoreKey                    ; always

;; The same key as at the last scan: it repeats if <KeyRepeat> says every key does, never if it says none do.
;; Also: RPT10 (KV20)
SameKey:
    and #<~SHIFTED_BIT
    bit KeyRepeat
    bmi Repeat
    bvs Done
    cmp #NO_CHARACTER & <~SHIFTED_BIT

;; No key at all, still: on to <StoreKey>, which forgets the last key. Otherwise only the space, DEL and INST, and
;; the cursor keys repeat, shifted or not.
;; Also: SCNOUT (KV20)
ToStoreKey:
    beq StoreKey
    cmp #DELETE_CHARACTER
    beq Repeat
    cmp #SPACE_CHARACTER
    beq Repeat
    cmp #CURSOR_RIGHT
    beq Repeat
    cmp #CURSOR_DOWN
    bne Done

;; A held key that repeats: first the delay counts down.
;; Also: RPT20 (KV20)
Repeat:
    ldy RepeatDelay
    beq CountInterval
    dec RepeatDelay
    bne Done

;; Then <RepeatInterval> counts down, and at 0 the key goes in again, if the buffer is empty.
;; Also: RPT40 (KV20)
CountInterval:
    dec RepeatInterval
    bne Done
    ldy #REPEAT_JIFFIES
    sty RepeatInterval
    ldy KeyboardBufferCount
    dey
    bpl Done

;; Remembers the key and the shift keys, and puts the character in the buffer, if it is one and there is room.
;; Also: CKIT2 (KV20)
StoreKey:
    ldy KeyDown
    sty LastKey
    ldy ShiftKeys
    sty LastShiftKeys
    cpx #NO_CHARACTER
    beq Done
    txa
    ldx KeyboardBufferCount
    cpx KeyboardBufferSize
    bcs Done
    sta KeyboardBuffer,x
    inx
    stx KeyboardBufferCount

;; Drives the STOP key's column, for <KernalTickClock>'s test, and returns.
;; Also: SCNRTS (KV20)
Done:
    lda #STOP_COLUMN
    sta KeyboardColumns
    rts
.endproc

;; <KeyTableSetup>'s default, which <ScanKeyboard> jumps to: SHIFT with C= switches the character set, once each time
;; they go down, unless <CaseSwitchLock> locks it; otherwise the shift keys pick <KeyTable>.
;;
;; It ends with a jump to <ScanKeyboard::Decode>, or to <ScanKeyboard::Done> while SHIFT and C= stay down, as a
;; replacement must. CTRL picks <ControlKeys> whatever else is down. With SHIFT and C= down, the key is looked up
;; unshifted.
;; In:    ShiftKeys = the shift keys down, LastShiftKeys = those at the last scan, KeyTable = <UnshiftedKeys>
;; Out:   KeyTable = the table for the shift keys
;; Also: SHFLOG (KV20)
.proc SelectKeyTable
    lda ShiftKeys
    cmp #SHIFT_DOWN | COMMODORE_DOWN
    bne NotCaseSwitch
    cmp LastShiftKeys
    beq ScanKeyboard::Done
    lda CaseSwitchLock
    bmi Done

    ; The Japanese version's code was here: NOPs now, in its instructions' sizes.
    .byte $EA, $EA
    .byte $EA, $EA
    .byte $EA, $EA
    .byte $EA, $EA, $EA
    .byte $EA, $EA, $EA
    .byte $EA, $EA
    .byte $EA, $EA, $EA
    .byte $EA, $EA

    ; Switches the character set.
    lda VicScreenAndCharacters
    eor #LOWER_CASE_SET
    sta VicScreenAndCharacters
    .byte $EA, $EA
    .byte $EA, $EA
    jmp Done

;; The table's entry is the shift keys times 2; with CTRL down, it is CTRL's, the fourth.
;; Also: KEYLG2 (KV20)
NotCaseSwitch:
    asl a
    cmp #CONTROL_DOWN * 2
    bcc NotControl
    lda #CONTROL_TABLE * 2
    .byte $EA, $EA

;; The Japanese version's kana modes were here, NOPs now; then the table's address goes in <KeyTable>.
;; Also: NCTRL (KV20)
NotControl:
    .byte $EA, $EA, $EA
    .byte $EA, $EA
    .byte $EA, $EA, $EA
    .byte $EA, $EA
    .byte $EA, $EA
    .byte $EA, $EA, $EA
    .byte $EA, $EA
    .byte $EA, $EA, $EA
    .byte $EA, $EA
    .byte $EA, $EA, $EA
    .byte $EA, $EA
    .byte $EA, $EA, $EA
    .byte $EA, $EA
    tax
    lda KeyTables,x
    sta KeyTable
    lda KeyTables+1,x
    sta KeyTable+1

;; Back to <ScanKeyboard::Decode>.
;; Also: SHFOUT (KV20)
Done:
    jmp ScanKeyboard::Decode
.endproc

;; The key tables, by the shift keys down (<ShiftKeys> times 2): none, SHIFT, C=, and CTRL's, then the Japanese
;; version's eight more.
;;
;; <SelectKeyTable> reaches only the first four: SHIFT with C= switches the character set instead, and CTRL with any
;; others picks the fourth. Of the others, three point at <SpareKeys> and one at <CaseCodes>' code, which the Japanese
;; version had a table at.
;; Also: KEYCOD (KV20)
KeyTables:
    .word UnshiftedKeys
    .word ShiftedKeys
    .word CommodoreKeys
    .word ControlKeys
    .word UnshiftedKeys
    .word ShiftedKeys
    .word SpareKeys
    .word ControlKeys
    .word CaseCodes
    .word SpareKeys
    .word SpareKeys
    .word ControlKeys

;; The 64 keys' characters with no shift key down, by matrix code: a line for each column, its rows 0 to 7, then
;; <NO_CHARACTER> for <NO_KEY>.
;;
;; The shift keys hold their bits, and RUN/STOP its code, as <ScanKeyboard> reads them.
;; Also: MODE1 (KV20)
UnshiftedKeys:
    .byte $31, $33, $35, $37, $39, $2B, $5C, $14
    .byte $5F, $57, $52, $59, $49, $50, $2A, $0D
    .byte CONTROL_DOWN, $41, $44, $47, $4A, $4C, $3B, $1D
    .byte STOP_KEY, SHIFT_DOWN, $58, $56, $4E, $2C, $2F, $11
    .byte $20, $5A, $43, $42, $4D, $2E, SHIFT_DOWN, $85
    .byte COMMODORE_DOWN, $53, $46, $48, $4B, $3A, $3D, $86
    .byte $51, $45, $54, $55, $4F, $40, $5E, $87
    .byte $32, $34, $36, $38, $30, $2D, $13, $88
    .byte NO_CHARACTER

;; The characters with SHIFT down, laid out as <UnshiftedKeys>.
;; Also: MODE2 (KV20)
ShiftedKeys:
    .byte $21, $23, $25, $27, $29, $DB, $A9, $94
    .byte $5F, $D7, $D2, $D9, $C9, $D0, $C0, $8D
    .byte CONTROL_DOWN, $C1, $C4, $C7, $CA, $CC, $5D, $9D
    .byte RUN_KEY, SHIFT_DOWN, $D8, $D6, $CE, $3C, $3F, $91
    .byte $A0, $DA, $C3, $C2, $CD, $3E, SHIFT_DOWN, $89
    .byte COMMODORE_DOWN, $D3, $C6, $C8, $CB, $5B, $3D, $8A
    .byte $D1, $C5, $D4, $D5, $CF, $BA, $DE, $8B
    .byte $22, $24, $26, $28, $30, $DD, $93, $8C
    .byte NO_CHARACTER

;; The characters with C= down, laid out as <UnshiftedKeys>: the graphics on the keys' left.
;; Also: MODE3 (KV20)
CommodoreKeys:
    .byte $21, $23, $25, $27, $29, $A6, $A8, $94
    .byte $5F, $B3, $B2, $B7, $A2, $AF, $DF, $8D
    .byte CONTROL_DOWN, $B0, $AC, $A5, $B5, $B6, $5D, $9D
    .byte RUN_KEY, SHIFT_DOWN, $BD, $BE, $AA, $3C, $3F, $91
    .byte $A0, $AD, $BC, $BF, $A7, $3E, SHIFT_DOWN, $89
    .byte COMMODORE_DOWN, $AE, $BB, $B4, $A1, $5B, $3D, $8A
    .byte $AB, $B1, $A3, $B8, $B9, $A4, $DE, $8B
    .byte $22, $24, $26, $28, $30, $DC, $93, $8C
    .byte NO_CHARACTER

;; The character set codes, from <ScreenOut>, which jumps here with every control code it has not carried out:
;; CHR$(14) switches the screen to the set with lower case.
;;
;; Each code, and any other, ends <ScreenOut>. The codes act whether or not <CaseSwitchLock> locks SHIFT with C=.
;; In:    A = the code, the stack = <ScreenOut>'s A, X and Y
;; Entry:
;;   Shifted = CHR$(142) switches back to the set with upper case and graphics; CHR$(8) locks the switch and CHR$(9)
;;     unlocks it (<ScreenOut> enters here with a shifted code).
;; Also: LOWER (KV20)
.proc CaseCodes
    cmp #LOWER_CASE
    bne Shifted
    lda #LOWER_CASE_SET
    ora VicScreenAndCharacters
    sta VicScreenAndCharacters
    jmp ShowCharacter::Finish

;; CHR$(142) switches back to the set with upper case and graphics; CHR$(8) locks the switch and CHR$(9) unlocks it
;; (<ScreenOut> enters here with a shifted code).
;; Also: UPPER (KV20)
Shifted:
    cmp #UPPER_CASE
    bne Lock
    lda #<~LOWER_CASE_SET
    and VicScreenAndCharacters
    sta VicScreenAndCharacters

;; Ends <ScreenOut>, through <ShowCharacter::Finish>.
;; Also: OUTHRE (KV20)
Done:
    jmp ShowCharacter::Finish

;; CHR$(8): <CaseSwitchLock>'s bit 7 set, locking the switch.
;; Also: LOCK (KV20)
Lock:
    cmp #LOCK_CASE
    bne Unlock
    lda #CASE_LOCKED
    ora CaseSwitchLock
    sta CaseSwitchLock
    bmi Done                        ; always

;; CHR$(9): its bit 7 cleared.
;; Also: UNLOCK (KV20)
Unlock:
    cmp #UNLOCK_CASE
    bne Done
    lda #<~CASE_LOCKED
    and CaseSwitchLock
    sta CaseSwitchLock
    bpl Done                        ; always
.endproc

;; A patch to <AdvanceCursor::JoinRow>: the row below the row being joined becomes a line's start, in case it
;; continued the line that row belonged to.
;;
;; Then it goes back to <AdvanceCursor::PatchReturn>.
;; In:    X = the row being joined
;; Out:   A = <LineLength>, carry = clear
;; Also: PATCHX (KV20)
.proc EndRowPatch
    inx
    lda LineLinks,x
    ora #LINE_START
    sta LineLinks,x
    dex
    lda LineLength
    clc
    jmp AdvanceCursor::PatchReturn
.endproc

;; A key table the Japanese version used, perhaps for its graphics, which <KeyTables>' unreachable entries point at.
;;
;; Nine bytes of $FF fill up to $ED72. From there its lines match the other tables' columns 2 to 7 and their end
;; byte, as if the table started 16 bytes before $ED72, inside <EndRowPatch>; the pointers give $ED69.
;; Also: CCTTA3 (KV20)
SpareKeys:
    .res $ED72 - *, $FF
    .byte CONTROL_DOWN, $FF, $FF, $FF, $FF, $FF, $E2, $9D
    .byte RUN_KEY, SHIFT_DOWN, $FF, $FF, $FF, $FF, $FF, $91
    .byte $A0, $FF, $FF, $FF, $FF, $EE, SHIFT_DOWN, $89
    .byte COMMODORE_DOWN, $FF, $FF, $FF, $FF, $E1, $FD, $8A
    .byte $FF, $FF, $FF, $FF, $FF, $B0, $E0, $8B
    .byte $F2, $F4, $F6, $FF, $F0, $ED, $93, $8C
    .byte NO_CHARACTER

;; The characters with CTRL down, laid out as <UnshiftedKeys>: the eight colours on 1 to 8, RVS ON on 9 and R, and
;; RVS OFF on 0.
;;
;; The left-arrow key gives $06, which the editor does nothing with; the other keys give none.
;; Also: CONTRL (KV20)
ControlKeys:
    .byte $90, $1C, $9C, $1F, $12, $FF, $FF, $FF
    .byte $06, $FF, $12, $FF, $FF, $FF, $FF, $FF
    .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
    .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
    .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
    .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
    .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
    .byte $05, $9F, $1E, $9E, $92, $FF, $FF, $FF
    .byte NO_CHARACTER

;; The VIC's 16 registers at start-up, for <InitializeVic>: the screen's left and top edges for NTSC or <PAL>
;; television, 22 columns and 23 rows of 8 by 8 characters, the screen at $1000 with the characters from $8000 (which
;; <Initialize> then sets from <ScreenPage>), the sound off, and a white background in a cyan border.
;; Also: TVIC (KV20)
VicSetup:
.if PAL
    .byte $0C, $26
.else
    .byte $05, $19
.endif
    .byte $16, $2E, $0, $C0, $0, 0
    .byte 0, 0, 0, 0, 0, 0, 0, $1B

;; What shifted RUN/STOP types: LOAD, RETURN, RUN, RETURN.
;; Also: RUNTB (KV20)
RunKeyText:
    .byte "LOAD", $D, "RUN", $D
.assert * - RunKeyText = RUN_KEY_TEXT_LENGTH, "RUN_KEY_TEXT_LENGTH must be RunKeyText's length."

;; The low byte of each row's address in screen memory; the row's link in <LineLinks> has its page.
;;
;; A screen at $1E00 starts at a page's start as one at $1000 does, so the same low bytes serve both.
;; Also: LDTB2 (KV20, MTV)
RowStarts:
    .byte <(ScreenMemory + 0 * SCREEN_COLUMNS)
    .byte <(ScreenMemory + 1 * SCREEN_COLUMNS)
    .byte <(ScreenMemory + 2 * SCREEN_COLUMNS)
    .byte <(ScreenMemory + 3 * SCREEN_COLUMNS)
    .byte <(ScreenMemory + 4 * SCREEN_COLUMNS)
    .byte <(ScreenMemory + 5 * SCREEN_COLUMNS)
    .byte <(ScreenMemory + 6 * SCREEN_COLUMNS)
    .byte <(ScreenMemory + 7 * SCREEN_COLUMNS)
    .byte <(ScreenMemory + 8 * SCREEN_COLUMNS)
    .byte <(ScreenMemory + 9 * SCREEN_COLUMNS)
    .byte <(ScreenMemory + 10 * SCREEN_COLUMNS)
    .byte <(ScreenMemory + 11 * SCREEN_COLUMNS)
    .byte <(ScreenMemory + 12 * SCREEN_COLUMNS)
    .byte <(ScreenMemory + 13 * SCREEN_COLUMNS)
    .byte <(ScreenMemory + 14 * SCREEN_COLUMNS)
    .byte <(ScreenMemory + 15 * SCREEN_COLUMNS)
    .byte <(ScreenMemory + 16 * SCREEN_COLUMNS)
    .byte <(ScreenMemory + 17 * SCREEN_COLUMNS)
    .byte <(ScreenMemory + 18 * SCREEN_COLUMNS)
    .byte <(ScreenMemory + 19 * SCREEN_COLUMNS)
    .byte <(ScreenMemory + 20 * SCREEN_COLUMNS)
    .byte <(ScreenMemory + 21 * SCREEN_COLUMNS)
    .byte <(ScreenMemory + 22 * SCREEN_COLUMNS)
.endscope
