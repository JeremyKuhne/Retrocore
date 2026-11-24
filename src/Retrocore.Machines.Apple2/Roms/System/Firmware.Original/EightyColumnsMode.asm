; retrocore: style=strict
;; The original IIe's 40/80-column conversion and screen access, $CDDB-$CFFF: the screen converted between 40 and 80
;; columns, the cursor's column, reading and writing the screen at a column through 80STORE, the escape cursor, the
;; Monitor copied into the language card, Pascal's setup, and the tables at the top of the ROM, which interleave the
;; functions' handlers with the scrolling's steps and edges.

; Screen characters.

;; Bit 7 of a screen character: set for normal video, clear for inverse or flashing.
NORMAL_BIT = $80

;; How near the window's right edge the 80-column cursor must be for <SetCursorColumn> to give the Monitor a
;; column near 40 instead of 0.
EDGE_COLUMNS = 8

; Memory.

;; The page the Monitor's ROM starts at, $F800.
MONITOR_ROM_PAGE = $F8

;; The 80-column firmware's 40/80-column conversion: the screen converted between 40 and 80 columns, a line at a
;; time, when Control-Q or Control-R changes the width or the firmware quits.
;;
;; In 80 columns a line's even columns are in auxiliary memory and its odd ones in main memory, each half at byte
;; column/2, so <Columns::To80> spreads each 40-column line over both halves and blanks columns 40-79 with
;; <Columns::ClearRightHalf>, and <Columns::To40> gathers columns 0-39 back into main memory. Both end in
;; <Columns::Finish>, which computes the cursor line's base.
.scope Columns

;; The line <To40> and <To80> convert, from the last line up: <ScrollBase>, which they borrow.
Line = ScrollBase

;; The 80-column column the line conversions are at: <ScrollBaseHigh>, which they borrow.
Column = ScrollBaseHigh

;; Converts the screen from 80 to 40 columns, keeping each line's left 40 columns, then turns 80STORE and 80 columns
;; off.
;;
;; It converts from the last line up to line 0, or to line 20 when graphics are shown, and puts the cursor
;; back as it was.
;; Keeps: X
;; Also: SCRN84 (IIEROM82, IIETRM85), SCR80TO40 (UNKN)
.proc To40

    ; The cursor, for <Finish>.
    lda EightyColumns::CursorLine
    pha
    lda EightyColumns::CursorColumn
    pha

    lda #LAST_LINE
    sta Line
    sta Store80On

;; Also: SCR40 (IIEROM82), SCR1 (IIETRM85)
NextLine:
    lda Line
    jsr LineBase::Row
    jsr LineTo40
    dec Line
    bmi Done
    bit TextState
    bmi NextLine
    lda Line
    cmp #MIXED_TEXT_TOP
    bcs NextLine

;; Turns 80STORE and 80 columns off, then goes to <Finish>.
;; Also: SCR40RET (IIEROM82), SCR4 (IIETRM85)
Done:
    sta Store80Off
    sta Columns80Off
    jmp Finish
.endproc

;; Converts the line at <TextBase> from 80 to 40 columns, from column 39 down, with interrupts off.
;; Keeps: X
;; Also: ATEFOR (IIEROM82)
.proc LineTo40
    php
    sei
    ldy #COLUMNS_40
    sty Column
    bit Page2Off

    ; An odd column from main memory, then the even one before it from auxiliary memory.
;; Also: ATEFOR1 (IIEROM82)
NextColumn:
    jsr CopyColumnTo40
    bit Page2On
    jsr CopyColumnTo40
    ldy Column
    bne NextColumn
    plp
    rts
.endproc

;; Copies the 80-column character before <Column>, from the half of the line switched in, into main memory's
;; 40-column line at the same column, and moves <Column> back to it.
;;
;; Column c's byte is at c/2 in its half, so the copy, working down, never overwrites a byte it has still to read.
;; Out: Y = the new <Column>
;; Keeps: X
;; Also: GET84 (IIEROM82)
.proc CopyColumnTo40
    dec Column
    lda Column
    lsr a
    tay
    lda (TextBase),y
    ldy Column
    bit Page2Off
    sta (TextBase),y
    rts
.endproc

;; Converts the screen from 40 to 80 columns, then turns 80 columns on.
;;
;; It converts from the last line up to line 0, or to line 20 when graphics are shown, and puts the cursor
;; back as it was.
;; Keeps: X
;; Also: SCRN48 (IIEROM82, IIETRM85), SCR40TO80 (UNKN)
.proc To80

    ; The cursor, for <Finish>.
    lda EightyColumns::CursorLine
    pha
    lda EightyColumns::CursorColumn
    pha

    lda #LAST_LINE
    sta Line

;; Also: SCR80 (IIEROM82), SCR5 (IIETRM85)
NextLine:
    lda Line
    jsr LineBase::Row
    jsr LineTo80
    dec Line
    bmi Done
    bit TextState
    bmi NextLine
    lda Line
    cmp #MIXED_TEXT_TOP
    bcs NextLine

;; Turns 80 columns on.
;; Also: SCR80RET (IIEROM82), SCR9 (IIETRM85)
Done:
    sta Columns80On
    ; Falls into Finish.
.endproc

;; Finishes a conversion: puts the cursor back from the stack, where <To40> and <To80> push its line, then its
;; column, and computes its line's base.
;; Keeps: X, Y
;; Also: SCRNRET (IIEROM82, IIETRM85)
.proc Finish
    pla
    sta EightyColumns::CursorColumn
    pla
    sta EightyColumns::CursorLine
    jmp LineBase
.endproc

;; Converts the line at <TextBase> from 40 to 80 columns, the even columns into auxiliary memory and the odd ones
;; into main memory, then blanks the right half of the 80-column line, with interrupts off.
;;
;; Column c goes to byte c/2 of its half, so the conversion, working up, never overwrites a byte it has still to
;; read.
;; Keeps: X
;; Also: FORATE (IIEROM82)
.proc LineTo80
    php
    sei
    ldy #0
    sty Column
    sty Store80On
    bit Page2Off

;; An even column into auxiliary memory, then the odd one after it into main memory.
;; Also: FORATE1 (IIEROM82)
NextColumn:
    lda (TextBase),y
    bit Page2On
    jsr StoreColumn
    bit Page2Off
    lda (TextBase),y
    jsr StoreColumn
    cpy #COLUMNS_40
    bcc NextColumn

    ; Columns 40-79: the right half of each half.
    jsr ClearRightHalf
    bit Page2On
    jsr ClearRightHalf
    bit Page2Off
    plp
    rts
.endproc

;; Blanks bytes 20-39 of the line at <TextBase> in the half switched in, columns 40-79 of an 80-column line: normal
;; blanks, or inverse ones when <InverseMask> says so.
;; Keeps: X
;; Also: CLRHALF (IIEROM82, IIETRM85), CLRRIGHT (UNKN)
.proc ClearRightHalf
    ldy #COLUMNS_40 / 2
    lda #' '
    bit InverseMask
    bmi Loop
    and #MASK_INVERSE

;; Also: CLRHALF2 (IIEROM82)
Loop:
    sta (TextBase),y
    iny
    cpy #COLUMNS_40
    bne Loop
    rts
.endproc

;; Stores a character at byte Y/2 of the line at <TextBase>, in the half switched in, and moves <Column> on.
;; In: A = the character, Y = the 80-column column
;; Out: Y = the new <Column>
;; Keeps: A, X
;; Also: PUTCOL80 (UNKN)
.proc StoreColumn
    pha
    tya
    lsr a
    tay
    pla
    sta (TextBase),y
    inc Column
    ldy Column
    rts
.endproc

.endscope

;; Sets the 80-column firmware's cursor column, and the Monitor's <::CursorColumn> and
;; <EightyColumns::LastCursorColumn> to go with it.
;;
;; At $CEAF. In 40 columns the Monitor's column is the same. In 80 columns it is 0, or, when fewer than
;; <EDGE_COLUMNS> columns are left to the window's right edge, 40 less the columns left.
;; In: A = the column
;; Out: A = the column
;; Keeps: X, Y
;; Also: SETCH (IIEROM82)
.proc SetCursorColumn
.assert * = $CEAF, "SetCursorColumn must stay at $CEAF."
    sta EightyColumns::CursorColumn
    sta CursorColumn
    sta EightyColumns::LastCursorColumn
    bit Columns80State
    bpl Done

    ; 80 columns.
    lda #0
    sta CursorColumn
    sta EightyColumns::LastCursorColumn
    lda WindowWidth
    sec
    sbc EightyColumns::CursorColumn
    cmp #EDGE_COLUMNS
    bcs Done

    ; Near the edge: 40 less the columns left.
    sta CursorColumn
    lda #COLUMNS_40
    sec
    sbc CursorColumn
    sta CursorColumn
    sta EightyColumns::LastCursorColumn

;; Also: SETCHRTS (IIEROM82)
Done:
    lda EightyColumns::CursorColumn
    rts
.endproc

;; The 80-column firmware's access to the text screen: reading and writing the character at a column of the line at
;; <TextBase>, and the cursor drawn by flipping the character under it.
;;
;; In 80 columns an even column is in auxiliary memory, which <Page2On> switches in while 80STORE is on, and an odd
;; one in main memory. <Screen::ReadCharacter> and <Screen::StoreCharacter> are the entries the rest of the firmware
;; uses, and <Screen::OverflowByte> is the $60 that `bit` reads to set overflow. On the original IIe one routine
;; reads or writes, by the overflow flag; on the Enhanced IIe, with MouseText off, the writes put inverse capitals
;; where the alternate character set shows them, and the reads undo it.
.scope Screen

;; Page zero's $1F, where <Access> keeps the column it was given. IIEROM82's 80-column listing calls it YSAV1, a
;; name left out of Also: because it is <SavedOutputY>'s.
SavedColumn = $1F

;; Flips bit 7 of the character at the cursor, which shows or hides the cursor.
;; Keeps: A, X, Y
;; Also: INVERT (IIEROM82, IIETRM85)
.proc InvertCursor
    pha
    tya
    pha
    ldy EightyColumns::CursorColumn
    jsr ReadCharacter
    eor #NORMAL_BIT
    bit OverflowByte
    jsr Access
    pla
    tay
    pla
    rts
.endproc

;; Stores a character at column Y of the cursor's line, with bit 7 flipped when <InverseMask> says inverse. Falls
;; into <OverflowByte>.
;; In: A = the character, Y = the column
;; Out: overflow = set
;; Keeps: A, X, Y
;; Also: STORCHAR (IIEROM82, IIETRM85), PUTINV (UNKN)
.proc StoreCharacter
    pha
    bit InverseMask
    bmi Store
    eor #NORMAL_BIT

;; Writes the character: <OverflowByte> sets overflow for <Access>.
;; Also: STOR2 (IIEROM82, IIETRM85)
Store:
    bit OverflowByte
    jsr Access
    pla
    ; Falls into OverflowByte.
.endproc

;; <StoreCharacter>'s RTS, $60, which `bit OverflowByte` reads to set overflow: <Access>'s write.
;; Also: SEV (IIEROM82, IIETRM85)
OverflowByte:
    rts

;; Reads the character at column Y of the cursor's line.
;; In: Y = the column
;; Out: A = the character, overflow = clear
;; Keeps: X, Y
;; Also: PICK (IIEROM82, IIETRM85), GETSCRCHAR (UNKN)
.proc ReadCharacter
    clv
    jsr Access
    rts
.endproc

;; Reads or writes the character at column Y of the line at <TextBase>.
;;
;; In 80 columns the even columns are in auxiliary memory, which <Page2On> switches in while 80STORE is on, and the
;; odd ones in main memory; interrupts are off while auxiliary memory may be in.
;; In: Y = the column, overflow = set to write A, clear to read, A = the character to write
;; Out: A = the character read; the character written when writing
;; Keeps: X, Y, overflow
;; Also: SCREENIT (IIEROM82)
.proc Access
    sty SavedColumn
    pha
    lda Columns80State
    bpl Column40

    ; 80 columns: byte Y/2, of the half the carry picks.
    lda SavedColumn
    lsr a
    tay
    bvs Write80
    php
    sei
    lda Page2On
    bcc Read80
    lda Page2Off

;; Reads the byte, then main memory back, and leaves the character on the stack.
;; Also: C8_SCRN2 (UNKN), SCRN2 (IIEROM82)
Read80:
    lda (TextBase),y
    tay
    lda Page2Off
    plp
    pla
    tya
    pha
    bvc Done                        ; always: the read left overflow clear

;; Writes the byte in its half, then main memory back.
;; Also: STOR80 (IIEROM82)
Write80:
    pla
    pha
    php
    sei
    pha
    lda Page2On
    bcc Write80Byte
    lda Page2Off

;; Also: SCRN3 (IIEROM82)
Write80Byte:
    pla
    sta (TextBase),y
    lda Page2Off
    plp
    bvs Done                        ; always: the write left overflow set

;; 40 columns: byte Y.
;; Also: SCRN40 (IIEROM82)
Column40:
    ldy SavedColumn
    bvs Write40
    pla
    lda (TextBase),y
    pha
    bvc Done                        ; always: this is the read

;; Also: STOR40 (IIEROM82)
Write40:
    pla
    pha
    sta (TextBase),y

;; The character from the stack, and the column back.
;; Also: STPKEXIT (IIEROM82)
Done:
    pla
    ldy SavedColumn
    rts
.endproc

;; Saves the character at the cursor in <EightyColumns::CurrentCharacter> and shows a "+" there in the opposite
;; video: the escape mode's cursor.
;; Keeps: A, X, Y
;; Also: ESCON (IIEROM82, IIETRM85), ESCCURSOR (UNKN)
.proc ShowEscapeCursor
    pha
    tya
    pha
    ldy EightyColumns::CursorColumn
    jsr ReadCharacter
    sta EightyColumns::CurrentCharacter

    ; The character's bit 7 flips the "+"'s.
    and #NORMAL_BIT
    eor #'+'
    jmp RestoreCharacter::Store
.endproc

;; Puts the character saved in <EightyColumns::CurrentCharacter> back at the cursor.
;; Keeps: A, X, Y
;; Entry:
;;   Store = writes A at column Y, with Y and A pushed: <ShowEscapeCursor> enters here
;; Also: ESCOFF (IIEROM82, IIETRM85), RESTCHAR (UNKN)
.proc RestoreCharacter
    pha
    tya
    pha
    ldy EightyColumns::CursorColumn
    lda EightyColumns::CurrentCharacter

;; Writes A at column Y, then takes Y and A back from the stack, where the caller pushed A, then Y.
;; In: A = the character, Y = the column
;; Also: ESCRET (IIEROM82, IIETRM85)
Store:
    bit OverflowByte
    jsr Access
    pla
    tay
    pla
    rts
.endproc

.endscope

;; Copies the Monitor, $F800-$FFFF, from ROM into the language card's RAM, then puts back the bank and the memory
;; it read.
;;
;; At $CF78. It reads the ROM while it writes the RAM, with interrupts off. It puts back bank 2 or bank 1, reading
;; RAM or ROM as before, but not whether RAM could be written. It copies through <OutputHook>, whose low byte it
;; puts back and whose high byte it leaves at $C3, slot 3's page.
;; Keeps: A
;; Also: COPYROM (IIEROM82, IIETRM85), LCMONCOPY (UNKN)
.proc CopyMonitorToRam
.assert * = $CF78, "CopyMonitorToRam must stay at $CF78."
    pha
    php
    sei

    ; The bank and whether RAM was being read.
    lda LanguageCardBank2State
    pha
    ldx LanguageCardRamState

    ; ROM read, RAM written (two reads).
    lda LanguageCardRomWriteBank2
    lda LanguageCardRomWriteBank2

    ; The pointer, from $F800.
    ldy #0
    lda #MONITOR_ROM_PAGE
    sta OutputHookHigh
    lda OutputHook
    pha
    lda #0
    sta OutputHook

;; Also: COPYROM2 (IIEROM82, IIETRM85)
CopyByte:
    lda (OutputHook),y
    sta (OutputHook),y
    iny
    bne CopyByte
    inc OutputHookHigh
    bne CopyByte

    ; The hook back, as slot 3's.
    pla
    sta OutputHook
    lda #>BasicOutput
    sta OutputHookHigh

    ; The bank back: bank 2, RAM read.
    pla
    bpl Bank1
    txa
    bpl Bank2Rom
    lda LanguageCardBank2ReadOnly
    jmp Done

;; Bank 2, ROM read.
;; Also: LCB2ROM (IIEROM82)
Bank2Rom:
    lda LanguageCardRomWriteBank2
    jmp Done

;; Bank 1, RAM read.
;; Also: LCB1 (IIEROM82)
Bank1:
    txa
    bpl Bank1Rom
    lda LanguageCardBank1ReadOnly
    jmp Done

;; Bank 1, ROM read.
;; Also: LCB1ROM (IIEROM82)
Bank1Rom:
    lda LanguageCardRomWriteBank1

;; Also: COPYRET (IIEROM82), ROMOK (IIETRM85)
Done:
    plp
    pla
    rts
.endproc

; Pascal: the setup before each call.
.scope Pascal continued

;; Sets up a Pascal call: the full 80-column window unless <MODE_TRANSPARENT> is set, <InverseMask> from
;; <MODE_INVERSE>, and <TextBase> from <EightyColumns::SavedTextBase>.
;; Keeps: X, Y
;; Also: PSETUP (IIEROM82, IIETRM85), PASRESTORE (UNKN)
.proc Setup
    lda EightyColumns::Mode
    and #MODE_TRANSPARENT
    bne SetVideo
    jsr FullWindow80

;; Normal video, or inverse with <MODE_INVERSE>: <MASK_NORMAL> shifted right is <MASK_INVERSE>.
;; Also: PSETUP2 (IIEROM82)
SetVideo:
    lda #MASK_NORMAL
    sta InverseMask
    lda EightyColumns::Mode
    and #MODE_INVERSE
    beq RestoreBase
    lsr InverseMask

;; Also: PSETUPRET (IIEROM82, IIETRM85)
RestoreBase:
    lda EightyColumns::SavedTextBase
    sta TextBase
    lda EightyColumns::SavedTextBaseHigh
    sta TextBaseHigh
    rts
.endproc

.endscope

; Functions: the 40-column handlers' table, among Control's scrolling tables.
.scope Functions continued

;; One entry of <Functions::Handlers40> or <Functions::Handlers80>: the low byte of a handler's address minus one,
;; at its function's number. The dispatchers push page $C1, <DispatchFunction>'s, then the entry, and return into the
;; handler.
;; Parameters:
;;   table = the table, <Functions::Handlers40> or <Functions::Handlers80>
;;   number = the function's number, a FIRMWARE_ constant
;;   handler = the routine, in page $C1 after its first byte
.macro FunctionHandler table, number, handler
    .assert * - table = number, "Each handler sits at its function's number."
    .assert >(handler - 1) = >DispatchFunction, "A function handler must follow the first byte of page $C1."
    .byte <(handler - 1)
.endmacro

;; The 40-column handlers of functions 0-5, which <Dispatch40> reads at Handlers40 + Y.
;;
;; Functions 6 and 7 never reach it, and function 8, <FIRMWARE_SET_WINDOW>, reads its entry from <Control::ScrollSteps>'
;; third byte.
;; Also: F_TABLE (IIEROM82)
Handlers40:
    FunctionHandler Handlers40, FIRMWARE_CLEAR_TO_END_OF_WINDOW, ClearToEndOfWindow40
    FunctionHandler Handlers40, FIRMWARE_HOME, Home40
    FunctionHandler Handlers40, FIRMWARE_SCROLL, Scroll40
    FunctionHandler Handlers40, FIRMWARE_CLEAR_TO_END_OF_LINE, ClearToEndOfLine40
    FunctionHandler Handlers40, FIRMWARE_CLEAR_LINE_FROM, ClearLineFrom40
    FunctionHandler Handlers40, FIRMWARE_RESET, Reset

.endscope

; Control: the scrolling's steps, whose third byte is the 40-column handler of function 8.
.scope Control continued

;; The line step for each direction of <ScrollLines>: -1 for <SCROLL_DOWN>, +1 for <SCROLL_UP>.
;;
;; Its third byte is <Functions::Handlers40>' entry for function 8, <FIRMWARE_SET_WINDOW>, as functions 6 and 7
;; never read theirs.
;; Also: PLUSMINUS1 (IIEROM82)
ScrollSteps:
    .byte <-1, 1
.assert * - ScrollSteps = SCROLL_UP + 1, "One step for each direction."
    FunctionHandler Functions::Handlers40, FIRMWARE_SET_WINDOW, Functions::SetWindow40

.endscope

; Functions: the 80-column handlers' table, between Control's scrolling tables.
.scope Functions continued

;; The 80-column handlers of functions 0-5, which <Dispatch80> reads at Handlers80 + Y.
;;
;; Functions 6 and 7 never reach it, and function 8, <FIRMWARE_SET_WINDOW>, reads its entry from <Control::ScrollEdges>'
;; third byte.
;; Also: B_TABLE (IIEROM82)
Handlers80:
    FunctionHandler Handlers80, FIRMWARE_CLEAR_TO_END_OF_WINDOW, ClearToEndOfWindow80
    FunctionHandler Handlers80, FIRMWARE_HOME, Home80
    FunctionHandler Handlers80, FIRMWARE_SCROLL, Scroll80
    FunctionHandler Handlers80, FIRMWARE_CLEAR_TO_END_OF_LINE, ClearToEndOfLine80
    FunctionHandler Handlers80, FIRMWARE_CLEAR_LINE_FROM, ClearLineFrom80
    FunctionHandler Handlers80, FIRMWARE_RESET, Reset

.endscope

; Control: the scrolling's edges, whose third byte is the 80-column handler of function 8.
.scope Control continued

;; The page-zero address of the edge each direction of <ScrollLines> starts from: <WindowBottom> for
;; <SCROLL_DOWN>, <WindowTop> for <SCROLL_UP>.
;;
;; Its third byte is <Functions::Handlers80>' entry for function 8, <FIRMWARE_SET_WINDOW>, as functions 6 and 7
;; never read theirs. Nothing reads the three bytes after it.
;; Also: WNDTAB (IIEROM82)
ScrollEdges:
    .byte WindowBottom, WindowTop
.assert * - ScrollEdges = SCROLL_UP + 1, "One edge for each direction."
    FunctionHandler Functions::Handlers80, FIRMWARE_SET_WINDOW, Functions::SetWindow80
    .byte 0, 0, 0

.endscope

    ; The ROM's last byte, at $CFFF, where <ExpansionRomOff> reads release the slots' $C800 ROMs.
    .byte 0
