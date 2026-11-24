; retrocore: style=strict
;; The Enhanced IIe's firmware functions, $C100-$C2FF: <DispatchFunction>, which the Monitor's <Monitor:CallFirmware>
;; jumps to with a function number in Y, the dispatcher it goes on to, and the handlers that dispatcher reaches: the
;; screen functions in their 40- and 80-column versions, the reset function, the key wait, the escape-key translation,
;; the line bases, the hooks, the mini-assembler and the disassembler's mnemonic, with the exit they share.

;; Performs the firmware function in Y for the Monitor: goes on to the Enhanced IIe's dispatcher,
;; <Functions::Dispatch>.
;;
;; At $C100, where <Monitor:CallFirmware> jumps with the internal ROM switched in. The stack holds a status whose
;; negative flag is <InternalCxRomState> from before the call, which <Functions::Return> pulls.
;; In: Y = the function number; the other registers as the function takes them
;; Also: B_FUNC (IIEROM82, IIETRM85)
.proc DispatchFunction
.assert * = $C100, "DispatchFunction must stay at $C100."
    jmp Functions::Dispatch
.endproc

;; The handlers of the firmware's functions, which <DispatchFunction> performs for the Monitor by the number in Y
;; (FirmwareFunctions.asm's FIRMWARE_ constants), and the exits they share.
;;
;; The dispatcher reaches most handlers by RTS through a table of their addresses minus one, so each of them starts in
;; page $C1, after its first byte. A screen function has two handlers: a 40-column one, and an 80-column one that runs
;; while the 80-column firmware is active. Every function but the reset, when it starts the self-test, leaves through
;; <Functions::Return>, which puts the ROM back as <Monitor:CallFirmware> found it.
.scope Functions

; The handlers.

;; The page every handler in <Handlers> is in: <Dispatch> pushes it as the high byte of the handler's address minus one.
;; Apple's BFUNCPG is the address $C100, the page's start.
;; Also: CXFUNC_PAGE (UNKN), BFUNCPG (IIEROM82, IIETRM85)
HANDLER_PAGE = $C1

;; The first function <Handlers> holds; <Dispatch> counts the ones below it down to their own handlers.
TABLE_FIRST_FUNCTION = FIRMWARE_HOME

;; The bits of <EightyColumns::Mode> that send the functions from 5 up to the first half of <Handlers>, the 40-column
;; and shared handlers: Pascal's bits (<MODE_PASCAL>, <MODE_CURSOR_OFF>, <MODE_INVERSE>, <MODE_PASCAL10>) and bit 6,
;; which the firmware never sets, so that <MODE_INACTIVE> has it. Apple's listing writes the mask
;; M.PASCAL+M.6+M.4+M.2+M.1: "if any of these 5 bits is on, then the mode is not video firmware" (IIETRM85).
HANDLERS40_MODE_BITS = MODE_PASCAL | %01000000 | MODE_CURSOR_OFF | MODE_INVERSE | MODE_PASCAL10
.assert HANDLERS40_MODE_BITS = $D6, "Apple's mask is $D6."


; The window.

;; The window's width in 40 columns.
WIDTH_40 = 40

;; The line below the full window: the screen's 24 lines.
FULL_WINDOW_BOTTOM = 24

;; The screen's last line, where <SetWindow40> puts the cursor.
LAST_LINE = FULL_WINDOW_BOTTOM - 1

; Characters on the screen.

;; The bits of a screen character that <ShowCursor40> keeps: its character, without the bits that pick normal,
;; flashing or inverse.
CHARACTER_BITS = %00111111

;; The bit that makes a screen character, with its high bit clear, flash.
FLASHING = %01000000

;; An inverse space, which <ClearColumns40> stores with the alternate characters on and inverse text.
INVERSE_SPACE = $20

;; The high bit, which the Monitor's characters have set.
HIGH_BIT = $80

; The key wait.

;; The block <GetKey40> shows for the cursor, alternating with the character under it.
CURSOR_BLOCK = $FF

;; The bit of <RandomSeedHigh> whose every change makes <GetKey40> blink.
BLINK_BIT = $40

; The reset.

;; Where <ResetFirmware> starts spoiling memory: the offset of the first of the two bytes it changes in page
;; <SPOIL_FIRST_PAGE>. The offset goes down one a page, so page 3's bytes are $03F3 and $03F4.
SPOIL_FIRST_OFFSET = $B0

;; The highest page <ResetFirmware> spoils.
SPOIL_FIRST_PAGE = $BF

;; The page below the last one <ResetFirmware> spoils.
SPOIL_END_PAGE = $01

; The disassembler.

;; The bits of an operand format that hold the operand's length, 0-2 bytes.
LENGTH_BITS = $03

;; The bits of an opcode that <MnemonicIndex>'s mnemonic hash starts from: bit 7 and bits 0-3.
GROUP_BITS = $8F

; The Monitor's arguments, in page-zero bytes it borrows.

;; The line the Monitor passes <BaseOfRow> and <BaseOfLine>.
PassedLine = TextBase

;; The column the Monitor's <ClearLineFrom> passes <ClearLineFrom40> and <ClearLineFrom80>.
PassedColumn = ScrollBase

;; The opcode the Monitor's <Decode at Monitor:Disassembler::Decode> passes <Decode>.
PassedOpcode = ScrollBase

;; Function $0A, 40 columns and while the 80-column firmware is inactive: clears from the cursor to the end of the
;; window.
;;
;; Clears from <CursorColumn> to the end of the line, then every line below it to the window's bottom, and sets the
;; cursor line's base address.
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
    jsr LineBase::Row
    jsr ClearColumns40
    ldy #0
    pla
    ; ClearColumns40 leaves the carry set, so this adds one.
    adc #0
    cmp WindowBottom
    bcc FromLine
    bcs CursorLineBase
.endproc

;; Function 5, 40 columns: moves the cursor to the window's top left and clears the window.
;; Out: CV = <WindowTop>, CursorColumn = 0
;; Also: F_HOME (IIEROM82, IIETRM85), HOME40 (UNKN)
.proc Home40
    lda WindowTop
    sta CV
    ldy #0
    sty CursorColumn
    beq ClearToEndOfWindow40::FromLine
.endproc

;; Function 6, 40 columns: scrolls the window up a line.
;;
;; Copies each line of the window to the line above it, from the second line down, then clears the bottom line.
;; Also: F_SCROLL (IIEROM82, IIETRM85), SCROLL40 (UNKN)
.proc Scroll40
    lda WindowTop
    pha
    jsr LineBase::Row

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
    ; The carry is clear, from the line base or the line count's compare.
    adc #1
    cmp WindowBottom
    bcs ClearBottom
    pha
    jsr LineBase::Row

;; Copies the line, right to left.
;; Also: SCRL2 (IIEROM82, IIETRM85)
CopyByte:
    lda (TextBase),y
    sta (ScrollBase),y
    dey
    bpl CopyByte
    bmi NextLine

;; Clears the bottom line.
;; Also: SCRL3 (IIEROM82, IIETRM85)
ClearBottom:
    ldy #0
    jsr ClearColumns40
    ; Falls into CursorLineBase.
.endproc

;; Sets the cursor line's base address: <ClearToEndOfWindow40> branches here and <Scroll40> falls in.
;; Also: GVTZ (IIETRM85)
CursorLineBase:
    lda CV
    ; Falls into RowLineBase.

;; Sets the base address of line A, with the window's left edge, and returns: <SetWindow40> branches here.
;; Also: GVTZ2 (IIETRM85)
RowLineBase:
    jmp LineBase::Row

;; Function $0C, 40 columns: makes the window full width and 24 lines deep, and moves the cursor to the last line.
;;
;; The Monitor's <SetWindow> has set the window's top and left. <SetWindowWidth> runs it for the 80-column firmware too.
;; Out: WindowWidth, WindowBottom, CV = the last line, TextBase/TextBaseHigh = its base address
;; Also: F_SETWND (IIEROM82, IIETRM85), SETWNDREST (UNKN)
.proc SetWindow40
    lda #WIDTH_40
    sta WindowWidth
    lda #FULL_WINDOW_BOTTOM
    sta WindowBottom
    lda #LAST_LINE
    sta CV
    ; Always: the line is not 0.
    bne RowLineBase
.endproc

;; Function 8, 40 columns: clears from the column the Monitor left in <PassedColumn> to the end of the line.
;; Also: F_CLEOLZ (IIEROM82), CLREOLZ40 (UNKN), F_CLREOLZ (IIETRM85)
.proc ClearLineFrom40
    ldy PassedColumn
    jmp ClearColumns40
.endproc

;; Function 6, 80 columns: scrolls the window up a line.
;; Also: B_SCROLL (IIEROM82, IIETRM85), CXSCROLL80 (UNKN)
.proc Scroll80
    jmp Control::ScrollUp
.endproc

;; Function 7, 80 columns: clears from the firmware's cursor to the end of the line.
;; Also: B_CLREOL (IIEROM82, IIETRM85), CXCLREOL80 (UNKN)
.proc ClearToEndOfLine80
    jmp Control::ClearToEndOfLine
.endproc

;; Function 8, 80 columns: clears from the column the Monitor left in <PassedColumn> to the end of the line.
;; Also: B_CLEOLZ (IIEROM82), CXCLREOLZ80 (UNKN), B_CLREOLZ (IIETRM85)
.proc ClearLineFrom80
    ldy PassedColumn
    jmp Control::ClearLineFrom
.endproc

;; Function $0A, 80 columns: clears from the firmware's cursor to the end of the window.
;; Also: B_CLREOP (IIEROM82, IIETRM85), CXCLREOP80 (UNKN)
.proc ClearToEndOfWindow80
    jmp Control::ClearToEndOfWindow
.endproc

;; Function $0C, 80 columns: goes on in <SetWindowWidth>.
;; Also: B_SETWND (IIEROM82, IIETRM85), CXSETWND80 (UNKN)
.proc SetWindow80
    jmp SetWindowWidth
.endproc

;; Function 9, which the Monitor's reset calls, in both halves of <Handlers>: goes on in <ResetFirmware>.
;; Also: B_RESET (IIEROM82, IIETRM85), CXRESET (UNKN)
.proc Reset
    jmp ResetFirmware
.endproc

;; Function $0B, 80 columns: goes on in <ShowCursorWhen40>.
;; Also: CXRDKEY80 (UNKN), B_RDKEY (IIETRM85)
.proc ShowCursor80
    jmp ShowCursorWhen40
.endproc

;; Function 5, 80 columns: moves the cursor to the window's top left and clears the window.
;;
;; Then gives the Monitor the firmware's cursor column, in <CursorColumn> and <EightyColumns::LastCursorColumn>, and
;; sets the cursor line's base address.
;; Also: B_HOME (IIEROM82, IIETRM85), CXHOME80 (UNKN)
.proc Home80
    jsr Control::HomeAndClear
    lda EightyColumns::CursorColumn
    sta CursorColumn
    sta EightyColumns::LastCursorColumn
    jmp LineBase
.endproc

;; Function $0E with the 80-column firmware active: finishes a hook that the Monitor's <SetHook at Monitor:SetHook>
;; stored at X.
;;
;; A slot's hook, low byte 0, is left as it is. A hook with <KeyboardIn>'s low byte, while output goes to slot 3's
;; page, goes back to slot 3's input entry instead (<Slot3Input>). Any other hook first turns the 80-column firmware off
;; (<QuitFirmware>), then gets the Monitor's page as in <SetHook40>.
;; In: X = the hook's address in page zero
;; Also: CXPORT80 (UNKN), B_QUIT (IIETRM85)
.proc SetHook80
    ldy SlotPointer,x
    beq SetHook40::Done
    cpy #<KeyboardIn
    beq Slot3Input
    jsr QuitFirmware
    ; Falls into SetHook40.
.endproc

;; Function $0E while the 80-column firmware is inactive: finishes a hook that the Monitor's
;; <SetHook at Monitor:SetHook> stored at X, giving a hook that is not a slot's the Monitor's page.
;; In: X = the hook's address in page zero
;; Out: A = the hook's high byte
;; Entry:
;;   MonitorPage = gives the hook the Monitor's page; <Slot3Input> branches here
;;   Done = loads the hook's high byte; <SetHook80> branches here
;; Also: CXPORT40 (UNKN), F_QUIT (IIETRM85)
.proc SetHook40
    ldy SlotPointer,x
    beq Done

;; Gives the hook the page of the Monitor's <KeyboardIn> and <ScreenOut>.
;; Also: F8HOOK (IIETRM85)
MonitorPage:
    lda #>KeyboardIn
    sta LOC1,x

;; Loads the hook's high byte.
;; Also: NOT0 (IIETRM85)
Done:
    lda LOC1,x
    rts
.endproc

;; Puts the input hook back on slot 3's <BasicInput> while the output hook is in slot 3's page, <BasicOutput>'s;
;; otherwise gives the hook the Monitor's page, as <SetHook40> does.
;; Also: CXPORTC3 (UNKN), IS0 (IIETRM85)
.proc Slot3Input
    lda OutputHookHigh
    cmp #>BasicOutput
    bne SetHook40::MonitorPage
    jmp SetSlot3Hooks::Input
.endproc

;; Function $0B, 40 columns: shows the cursor before the Monitor's <ReadKey> reads a key, by making the character under
;; it flash.
;; Out: A = the character under the cursor, as it was
;; Also: RDKEY40 (UNKN), F_RDKEY (IIETRM85)
.proc ShowCursor40
    ldy CursorColumn
    lda (TextBase),y
    pha
    and #CHARACTER_BITS
    ora #FLASHING
    sta (TextBase),y
    pla                             ; F.NOCUR in Apple's listing
    rts
.endproc

;; Function 2: sets the base address of the line the Monitor left in <PassedLine>, without the window's left edge.
;;
;; The Monitor does not call it.
;; In: A = the caller's Y
;; Out: TextBase/TextBaseHigh = the line's base address
;; Also: CXBASCALC (UNKN), F_BASCALC (IIETRM85)
.proc BaseOfRow
    tay
    lda PassedLine
    jsr RowBase
    ; Always: <RowBase> leaves the carry clear.
    bcc Return
.endproc

;; Function 1, which the Monitor calls after reading a key in escape mode: makes a letter uppercase, and the arrow keys
;; I, J, K and M.
;;
;; Left, right, down and up (<ArrowKeys>) become J, K, M and I (<ArrowLetters>).
;; In: A = the key
;; Out: A = the key, translated
;; Also: B_ESCFIX (IIEROM82, IIETRM85), CXESCKEY (UNKN)
.proc EscapeKey
    jsr Upshift
    ldy #ARROW_COUNT - 1            ; B.ESCFIX1 in Apple's listing

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
    bmi Return
.endproc

;; Function 0, which the Monitor's <Monitor:ScreenOutByWidth> calls in 80 columns: prints a character through the
;; 80-column firmware.
;; In: A = the character
;; Also: CXCOUT80 (UNKN), F_BOUT (IIETRM85)
.proc Output80
    jsr CharacterIo::Output
    jmp Return
.endproc

;; Function $10, which finishes the Monitor's <Decode at Monitor:Disassembler::Decode>: the operand's length, then the
;; mnemonic's index from <MnemonicIndex>.
;; In: X = the operand format, PassedOpcode = the opcode
;; Out: A = the mnemonic's index, OperandLength = the operand's length
;; Also: CXINSDS2 (UNKN), MNNDX (IIETRM85)
.proc Decode
    txa
    and #LENGTH_BITS
    sta OperandLength
    lda PassedOpcode
    and #GROUP_BITS
    jmp MnemonicIndex
.endproc

;; Function $0D, the Monitor's "!" command: runs the mini-assembler, then gives the Monitor X as its command position.
;; Out: CommandPosition = X
;; Also: CXMINIASM (UNKN), GOMINI (IIETRM85)
.proc RunMiniAssembler

;; The Monitor's <ReadLine at Monitor:MiniAssembler::ReadLine>, which prompts with "!", reads a line and assembles
;; it; MonitorEntries.asm does not have it.
ReadLine = $FCF0

    jsr ReadLine
    txa
    sta CommandPosition
    rts
.endproc

;; Function $0F, for the Monitor's line input when the right arrow copies a character in 80 columns: gets the
;; character under the firmware's cursor.
;; In: TextBase/TextBaseHigh = the cursor line
;; Out: A = the character, with its high bit set
;; Also: CXSCRNCHAR (UNKN), FIXPICK (IIETRM85)
.proc CharacterUnderCursor
    ldy EightyColumns::CursorColumn
    jsr Screen::ReadCharacter
    ora #HIGH_BIT
    rts
.endproc

;; Function 7, 40 columns: clears from the cursor to the end of the line.
;; Also: F_CLREOL (IIEROM82, IIETRM85), CLREOL40 (UNKN), X_CLREOL (IIETRM85)
.proc ClearToEndOfLine40
    ldy CursorColumn
    ; Falls into ClearColumns40.
.endproc

;; Clears a line of the 40-column screen from a column to the window's right edge.
;;
;; The blank is a space, or an inverse space with the alternate characters on and <InverseMask> making inverse text.
;; In: Y = the column, TextBase/TextBaseHigh = the line
;; Also: X_CLEOLZ (IIEROM82), CLRLINE40 (UNKN), X_CLREOLZ (IIETRM85)
.proc ClearColumns40
    lda #' '
    bit AlternateCharactersState
    bpl Store
    bit InverseMask
    bmi Store
    lda #INVERSE_SPACE

;; Stores the blank in each column, in the 40-column clearing's loop.
;; Also: X_CLREOL2 (IIETRM85)
Store:
    jmp Control::ClearLineFrom::Store40
.endproc

;; Function 4, which the Monitor's <SetLineBase> calls: sets the base address of the line the Monitor left in
;; <PassedLine>, with the window's left edge.
;; In: A = the caller's Y
;; Out: TextBase/TextBaseHigh = the line's base address
;; Also: CXVTABZ (UNKN), F_VTABZ (IIETRM85)
.proc BaseOfLine
    tay
    lda PassedLine
    jsr LineBase::Row
    ; Falls into Return.
.endproc

;; The exit every function leaves through: pulls the status <Monitor:CallFirmware> pushed, and returns through
;; <SelectSlotRom>, which switches slot ROM in, unless internal ROM was in before the call.
;; Also: F_RETURN (IIEROM82, IIETRM85), CXEXIT (UNKN)
.proc Return
    plp
    bmi ReturnInternal              ; F.RET2 in Apple's listing
    jmp SelectSlotRom
.endproc

;; The exit when internal ROM was in before the call: returns through <SelectSlotRom>'s return,
;; <Monitor:SelectSlotRom::Done>, leaving the ROM as it is.
;; Also: F_RET1 (IIEROM82, IIETRM85), CXEXITINT (UNKN)
ReturnInternal:
    ; SelectSlotRom's first instruction, sta InternalCxRomOff, is three bytes.
    jmp SelectSlotRom + 3

;; Performs the firmware function in Y: the Enhanced IIe's dispatcher, which <DispatchFunction> jumps to.
;;
;; Functions 0-4 have one handler each: <Output80>, <EscapeKey>, <BaseOfRow>, <GetKey> and <BaseOfLine>. For the
;; functions from 5 up it pushes <Return>'s address minus one, so the handler's RTS goes there, and runs the handler
;; from <Handlers>: from its first half when <EightyColumns::Mode> has any of <HANDLERS40_MODE_BITS> set, and otherwise
;; from its second, the 80-column firmware's, after <SyncCursor> and <LineBase> have taken the Monitor's cursor.
;; In: Y = the function number; the other registers as the function takes them
;; Also: CXDISPATCH (UNKN), DISPATCH (IIETRM85)
.proc Dispatch
    ; Functions 0-4.
    dey
    bmi Output80
    dey
    bmi EscapeKey
    dey
    bmi BaseOfRow
    dey
    bmi GetKey
    dey
    bmi BaseOfLine

    ; The rest return to Return.
    lda #>(Return - 1)
    pha
    lda #<(Return - 1)
    pha

    ; With the 80-column firmware active, the second half, and the Monitor's cursor.
    lda EightyColumns::Mode
    and #HANDLERS40_MODE_BITS
    bne ByTable
    tya
    clc
    adc #HANDLER_COUNT
    pha
    jsr SyncCursor
    jsr LineBase
    pla
    tay

;; Runs the handler: the table holds its address minus one, so the RTS lands on it.
;; Also: GETFUNC (IIETRM85)
ByTable:
    lda #HANDLER_PAGE
    pha
    lda Handlers,y
    pha
    rts
.endproc

; Dispatch counts down to the functions with their own handlers, then indexes Handlers from the first one it holds.
.assert FIRMWARE_OUTPUT = 0 && FIRMWARE_ESCAPE_KEY = 1 && FIRMWARE_ROW_BASE = 2, "Dispatch counts these down."
.assert FIRMWARE_KEYBOARD_IN = 3 && FIRMWARE_LINE_BASE = 4, "Dispatch counts these down."
.assert TABLE_FIRST_FUNCTION = 5, "Dispatch indexes Handlers after five counts."

;; One entry of <Functions::Handlers>: a handler's address minus one, its low byte, at its function's place in either
;; half.
;; Parameters:
;;   function = the function's number, a FIRMWARE_ constant from FirmwareFunctions.asm
;;   handler = the handler, which must start after the first byte of page <Functions::HANDLER_PAGE>
.macro Handler function, handler
    .assert (* - Handlers) .mod HANDLER_COUNT = function - TABLE_FIRST_FUNCTION, "A handler is out of its place."
    .assert >(handler - 1) = HANDLER_PAGE, "A function handler must follow the first byte of page $C1."
    .byte <(handler - 1)
.endmacro

;; The handlers of the functions from 5 up, for <Dispatch>: their addresses minus one, low bytes, in page
;; <HANDLER_PAGE>.
;;
;; The first half is used with the 80-column firmware inactive, or working for Pascal: the 40-column handlers and the
;; ones both halves share. The second half is the active 80-column firmware's.
;; Also: CXFUNCTBL (UNKN), F_TABLE (IIEROM82, IIETRM85)
Handlers:
    Handler FIRMWARE_HOME, Home40
    Handler FIRMWARE_SCROLL, Scroll40
    Handler FIRMWARE_CLEAR_TO_END_OF_LINE, ClearToEndOfLine40
    Handler FIRMWARE_CLEAR_LINE_FROM, ClearLineFrom40
    Handler FIRMWARE_RESET, Reset
    Handler FIRMWARE_CLEAR_TO_END_OF_WINDOW, ClearToEndOfWindow40
    Handler FIRMWARE_READ_KEY, ShowCursor40
    Handler FIRMWARE_SET_WINDOW, SetWindow40
    Handler FIRMWARE_MINI_ASSEMBLER, RunMiniAssembler
    Handler FIRMWARE_SET_HOOK, SetHook40
    Handler FIRMWARE_CHARACTER_UNDER_CURSOR, CharacterUnderCursor
    Handler FIRMWARE_DECODE, Decode

;; The handlers in each half of <Handlers>, one for each function from 5 up.
;; Also: CXFUNCS (UNKN), TABLEN (IIETRM85)
HANDLER_COUNT = * - Handlers
    Handler FIRMWARE_HOME, Home80
    Handler FIRMWARE_SCROLL, Scroll80
    Handler FIRMWARE_CLEAR_TO_END_OF_LINE, ClearToEndOfLine80
    Handler FIRMWARE_CLEAR_LINE_FROM, ClearLineFrom80
    Handler FIRMWARE_RESET, Reset
    Handler FIRMWARE_CLEAR_TO_END_OF_WINDOW, ClearToEndOfWindow80
    Handler FIRMWARE_READ_KEY, ShowCursor80
    Handler FIRMWARE_SET_WINDOW, SetWindow80
    Handler FIRMWARE_MINI_ASSEMBLER, RunMiniAssembler
    Handler FIRMWARE_SET_HOOK, SetHook80
    Handler FIRMWARE_CHARACTER_UNDER_CURSOR, CharacterUnderCursor
    Handler FIRMWARE_DECODE, Decode
.assert HANDLER_COUNT = FIRMWARE_DECODE - TABLE_FIRST_FUNCTION + 1, "A handler for each function from 5 up."
.assert * - Handlers = 2 * HANDLER_COUNT, "Both halves of Handlers need the same functions."

;; Function 3, the Enhanced IIe's <KeyboardIn>: waits for a key, through the 80-column firmware in 80 columns and
;; <GetKey40> otherwise.
;; In: A = the character under the cursor
;; Out: A = the key
;; Entry:
;;   ToReturn = returns; <GetKey40> branches here
;; Also: B_KEYIN (IIEROM82, IIETRM85), CXKEYIN (UNKN)
.proc GetKey
    bit Columns80State
    bpl GetKey40
    jsr CharacterIo::InputKey

;; Returns; <GetKey40> branches here.
;; Also: GOF_RET (IIETRM85)
ToReturn:
    jmp Return
.endproc

;; Waits for a key in 40 columns with a blinking cursor, then clears the keyboard strobe.
;;
;; The cursor is a block, <CURSOR_BLOCK>, that alternates with the character under it each time <BLINK_BIT> of
;; <RandomSeedHigh> changes while <RandomSeed>/<RandomSeedHigh> count up; the character is put back once the key
;; comes.
;; In: A = the character under the cursor
;; Out: A = the key, with its high bit set
;; Keeps: X
;; Also: KEYIN40 (UNKN), B_KEYIN1 (IIETRM85)
.proc GetKey40
    ; X, then the character twice: once to put back, once as the one shown.
    tay
    txa
    pha
    tya
    pha
    pha

;; Picks what to show next: the block after the character, the character after the block.
;; Also: NEW_CUR (IIETRM85)
NextBlink:
    pla
    cmp #CURSOR_BLOCK
    beq Character
    lda #CURSOR_BLOCK
    bne Show

;; The character, from under the shown one on the stack.
;; Also: NEW_CUR1 (IIETRM85)
Character:
    pla
    pha

;; Shows it, keeping it on the stack.
;; Also: NEW_CUR2 (IIETRM85)
Show:
    pha
    ldy CursorColumn
    sta (TextBase),y

;; Counts the random seed, blinking each time its blink bit changes.
;; Also: WAITKEY1 (IIETRM85)
Wait:
    inc RandomSeed
    bne CheckKey
    lda RandomSeedHigh
    inc RandomSeedHigh
    eor RandomSeedHigh
    and #BLINK_BIT
    bne NextBlink

;; Reads the keyboard; with a key, puts the character back, restores X, and reads the key and clears the strobe.
;; Also: WAITKEY4 (IIETRM85)
CheckKey:
    lda Keyboard
    bpl Wait
    pla
    pla
    ldy CursorColumn
    sta (TextBase),y
    pla
    tax
    lda Keyboard
    sta KeyboardStrobe
    ; Always: the key has its high bit set.
    bmi GetKey::ToReturn
.endproc

;; Makes the window full width and 24 lines deep, 80 columns when the display is, and moves the cursor to the last
;; line, for function $0C in 80 columns.
;; Out: WindowWidth, WindowBottom, CV = the last line, TextBase/TextBaseHigh = its base address,
;;      EightyColumns::CursorLine = <CV>
;; Also: B_SETWNDX (IIEROM82, IIETRM85), SETWND80 (UNKN)
.proc SetWindowWidth
    jsr SetWindow40
    bit Columns80State
    bpl CopyLine
    ; Twice 40.
    asl WindowWidth

;; Gives the firmware the cursor line.
;; Also: SKPSHFT (IIETRM85)
CopyLine:
    lda CV
    sta EightyColumns::CursorLine
    rts
.endproc

;; Function 9: resets the 80-column firmware, for the Monitor's reset.
;;
;; Marks the firmware inactive and switches annunciators 2 and 3 on. With Solid-Apple (<Button1>) held, runs the
;; self-test. With Open-Apple (<Button0>) held, it spoils memory first: two bytes of every page from $BF down to $02
;; get a space, the offset going down one a page from $B0, so that page 3's are <SoftEntryVector>'s high byte and
;; <SoftEntryCheck>, and the Monitor's reset starts afresh instead of returning to a program. Then it switches slot 3's
;; ROM in, and the internal one instead when <TestSlot3Card> says to.
;; Entry:
;;   Done = returns; <ShowCursorWhen40> branches here
;; Also: B_RESETX (IIEROM82, IIETRM85), RESETFW (UNKN)
.proc ResetFirmware
    lda #MODE_INACTIVE
    sta EightyColumns::Mode
    lda Annunciator2On
    lda Annunciator3On
    lda Button1
    bpl CheckOpenApple
    jmp SelfTest::Run

;; Solid-Apple is not held: spoils memory when Open-Apple is.
;; Also: NODIAGS (IIETRM85)
CheckOpenApple:
    lda Button0
    bpl ChooseSlot3Rom

    ; From the top page down.
    ldy #SPOIL_FIRST_OFFSET
    lda #0
    sta Address1
    lda #SPOIL_FIRST_PAGE
    sec

;; Stores a space in two bytes of the page, the second one lower.
;; Also: BLAST (IIEROM82, IIETRM85)
SpoilPage:
    sta Address1High
    pha
    lda #' '
    sta (Address1),y
    dey
    sta (Address1),y
    pla
    sbc #1
    cmp #SPOIL_END_PAGE
    bne SpoilPage

;; Switches slot 3's ROM in, then the internal one instead when <TestSlot3Card> says to.
;; Also: RESETRET (IIEROM82, IIETRM85)
ChooseSlot3Rom:
    sta SlotC3RomOn
    jsr TestSlot3Card
    bne Done
    sta SlotC3RomOff

;; Returns; <ShowCursorWhen40> branches here.
;; Also: GORETN1 (IIETRM85)
Done:
    rts
.endproc

;; The arrow keys <EscapeKey> translates: left, right, down and up.
;; Also: ESCIN (IIEROM82, IIETRM85), ARROWKEYS (UNKN)
ArrowKeys:
    .byte KEY_BACKSPACE, KEY_RIGHT_ARROW, KEY_LINE_FEED, KEY_CONTROL_K

;; The arrow keys in <ArrowKeys> and <ArrowLetters>.
;; Also: ARROWS (UNKN)
ARROW_COUNT = * - ArrowKeys

;; Shows the cursor for function $0B with the 80-column firmware active: in 40 columns, by inverting the character
;; under the firmware's cursor (<Screen::InvertCursor>); in 80 columns it leaves the screen as it is.
;; Out: A = the character under the cursor
;; Also: RDKEY80 (UNKN), B_RDKEYX (IIETRM85)
.proc ShowCursorWhen40
    ldy CursorColumn
    lda (TextBase),y
    bit Columns80State
    bmi ResetFirmware::Done
    jmp Screen::InvertCursor
.endproc

    ; Unused.
    .res 2, 0

.endscope
