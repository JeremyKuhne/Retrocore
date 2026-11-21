; retrocore: style=strict
;; The 80-column firmware's $C800-$C9FF, original IIe: Pascal 1.0's hooks at $C800, $C84D and $C9AA, BASIC's character
;; input and output through slot 3 (starting the firmware, printing, reading keys with escape mode and quotes), and
;; Pascal's status request.

; Characters.

;; A character's bits without its high bit: the code a control character or Pascal has.
ASCII_BITS = %01111111

;; A character's high bit, which the screen and the keyboard set on normal text.
TEXT_HIGH_BIT = %10000000

;; Clears a lowercase letter's bit 5, making it uppercase.
UPPERCASE_MASK = %11011111

; The screen.

;; The lines of the text screen.
TEXT_LINES = 24

;; The columns of the 40-column text screen.
TEXT_COLUMNS = 40

;; The first of the four text lines below a graphics screen, the window's top while graphics are shown.
GRAPHICS_TEXT_TOP = 20

;; Clears bit 0 of a window width, making it even, as 80 columns need.
EVEN_WIDTH_MASK = %11111110

; The Monitor and Pascal.

;; The Monitor's <ModelId> on the IIe, which the firmware checks the Monitor in the language card by.
MODEL_ID_IIE = $06

;; Pascal's status request for input: is a key waiting?
PASCAL_STATUS_INPUT = 1

;; The error a Pascal call returns in X for a request the firmware does not handle.
PASCAL_BAD_REQUEST = 3

;; What <Pascal::Read> returns in X for Pascal 1.0, slot 3's page, where Pascal 1.1 gets 0.
PASCAL10_READ_X = $C3

; The macro that builds the escape-mode tables.

;; One escape-mode key and the control code it performs, for <CharacterIo::EscapeKeys> and
;; <CharacterIo::EscapeCodes>.
;; Parameters:
;;   key = the key, as typed: its high bit is cleared
;;   code = the control code, with <CharacterIo::ESCAPE_STAY> to stay in escape mode after it
.macro EscapeEntry key, code
    .ident(.sprintf("ESCAPE_KEY_%d", ESCAPE_ENTRIES)) = (key) & ASCII_BITS
    .ident(.sprintf("ESCAPE_CODE_%d", ESCAPE_ENTRIES)) = code
    .set ESCAPE_ENTRIES, ESCAPE_ENTRIES + 1
.endmacro

; Pascal: Pascal 1.0's init hook, at the start of the $C800 ROM.
.scope Pascal continued

;; Pascal 1.0's init hook: goes to <Pascal::Init10>.
;;
;; At $C800. Apple's Enhanced IIe listing says the three hooks at $C800, $C84D and $C9AA are only used by Pascal
;; 1.0; the original IIe has them at the same addresses.
;; Also: C8ENTRY (UNKN)
.proc Init10Entry
.assert * = $C800, "Pascal::Init10Entry must stay at $C800."
    jmp Init10
.endproc

.endscope

; CharacterIo: starting the firmware for BASIC.
.scope CharacterIo continued

;; Starts the firmware for BASIC, for `PR#3`: makes sure the Monitor in the language card is the IIe's, then sets the
;; hooks, the 40-column window and the mode, and goes on to <CharacterIo::FinishInitialize>.
;;
;; A Monitor whose <ModelId> is not <MODEL_ID_IIE> is replaced by a copy of the ROM's; if it still differs, the
;; firmware hangs with interrupts off. The mode keeps only <MODE_INTERRUPTS>. The caller's A, Y, X and status are on
;; the stack.
;; In: EightyColumns::CurrentCharacter = the character to print once started
;; Entry:
;;   Hang = loops forever with interrupts off; <CharacterIo::InputOrOutput> jumps here
;; Also: BASICINIT (IIEROM82)
.proc Initialize
    ; The Monitor's version, with one try at copying the ROM's in.
    lda #MODEL_ID_IIE
    cmp ModelId
    beq SetHooks
    jsr CopyMonitorToRam
    cmp ModelId
    beq SetHooks
    sei

;; Loops forever with interrupts off: the Monitor is not the IIe's.
;; Also: HANG (IIEROM82)
Hang:
    jmp Hang

;; Points the output hook at <BasicOutput at BASICOUT> and the input hook at <BasicInput at BASICIN>, and sets the
;; 40-column window.
;; Also: BINIT1 (IIEROM82)
SetHooks:
    ; BasicInput and BasicOutput share page $C3.
    lda #>BasicInput
    sta OutputHookHigh
    sta InputHookHigh
    lda #<BasicInput
    sta InputHook
    lda #<BasicOutput
    sta OutputHook

    ; The window: the whole screen, from line 20 while graphics are shown.
    lda #0
    sta WindowLeft
    lda #0
    bit TextState
    bmi SetTop
    lda #GRAPHICS_TEXT_TOP

;; Stores the window's top and the rest of the 40-column window.
;; Also: BINIT1A (IIEROM82)
SetTop:
    sta WindowTop
    lda #TEXT_LINES
    sta WindowBottom
    lda #TEXT_COLUMNS
    sta WindowWidth

    ; The cursor's column as the firmware's last, and the mode with only the interrupt bit.
    lda CursorColumn
    sta EightyColumns::LastCursorColumn
    lda #MODE_INTERRUPTS
    and EightyColumns::Mode
    sta EightyColumns::Mode
    jmp FinishInitialize

    ; Unused, up to Pascal 1.0's read hook.
    .byte $00, $00
.endproc

.endscope

; Pascal: Pascal 1.0's read hook, in the middle of starting the firmware for BASIC.
.scope Pascal continued

;; Pascal 1.0's read hook: goes to <Pascal::ReadEntry at JPREAD>.
;;
;; At $C84D, which Apple's Enhanced IIe listing labels Pascal 1.0's input hook. The original IIe's source called it
;; unreferenced, as nothing in this ROM jumps here.
.proc Read10Entry
.assert * = $C84D, "Pascal::Read10Entry must stay at $C84D."
    jmp ReadEntry
.endproc

.endscope

; CharacterIo: the rest of starting the firmware, and BASIC's input and output.
.scope CharacterIo continued

;; Finishes starting the firmware for BASIC: 80 columns when a card answers, the alternate characters, the window
;; homed and cleared, then the character printed as output. The caller's A, Y, X and status are on the stack.
;; In: EightyColumns::CurrentCharacter = the character
;; Also: BINIT2 (IIEROM82)
.proc FinishInitialize
    ; 80 columns with a card: the window twice as wide, 80STORE and 80VID on.
    jsr TestAuxMemory
    bne Clear
    asl WindowWidth
    sta Store80On
    sta Columns80On

;; Turns the alternate characters on and clears the window.
;; Also: CLEARIT (IIEROM82)
Clear:
    sta AlternateCharactersOn
    jsr Control::HomeAndClear

    ; The saved status with the carry clear, so the character is printed.
    plp
    clc
    php
    ; Falls into InputOrOutput.
.endproc

;; The shared path of BASIC's input and output: 80STORE on and the width even in 80 columns, the cursor's column
;; adopted if a program changed it, the Monitor checked again, then <CharacterIo::Input> or
;; <CharacterIo::Output> by the saved carry.
;;
;; <CharacterIo::Enter at BASICENT> jumps here for the hooks, with the caller's A, Y, X and status on the stack, the
;; status's carry set for input.
;; Also: C8BASIC (IIEROM82)
.proc InputOrOutput
    bit Columns80State
    bpl AdoptColumn
    sta Store80On
    lda WindowWidth
    and #EVEN_WIDTH_MASK
    sta WindowWidth

;; Takes <CursorColumn> as the firmware's column unless it is the one the firmware stored last.
;; Also: C8B2 (IIEROM82)
AdoptColumn:
    lda CursorColumn
    cmp EightyColumns::LastCursorColumn
    beq CheckVersion
    sta EightyColumns::CursorColumn

;; Checks that the Monitor is the IIe's, with one try at copying the ROM's in, and hangs if it still is not.
;; Also: C8B3 (IIEROM82)
CheckVersion:
    lda #MODEL_ID_IIE
    cmp ModelId
    beq ByCarry
    jsr CopyMonitorToRam
    cmp ModelId
    beq ByCarry
    jmp Initialize::Hang

;; Pulls the saved status and goes to input when its carry is set, to output when it is clear.
;; Also: C8B4 (IIEROM82)
ByCarry:
    plp
    bcc Output
    jmp Input
.endproc

;; BASIC's output: clears <MODE_INPUT>, then prints the character.
;; Also: BOUT (IIEROM82)
.proc Output
    lda EightyColumns::Mode
    and #<~MODE_INPUT
    sta EightyColumns::Mode
    jmp Print
.endproc

;; Prints <EightyColumns::CurrentCharacter>: performs a control character, displays any other.
;;
;; A return while Control-S waits in the keyboard pauses until another key; a Control-C is left in the keyboard
;; for BASIC to find.
;; Also: BPRINT (IIEROM82)
.proc Print
    ; A return with Control-S typed: wait for the next key.
    lda EightyColumns::CurrentCharacter
    cmp #KEY_RETURN
    bne NoWait
    ldy Keyboard
    bpl NoWait
    cpy #KEY_CONTROL_S
    bne NoWait
    bit KeyboardStrobe

;; Waits for the key after Control-S, and clears it unless it is Control-C.
;; Also: C8_KBDWAIT (UNKN), KBDWAIT (IIEROM82)
WaitForResume:
    ldy Keyboard
    bpl WaitForResume
    cpy #KEY_CONTROL_C
    beq NoWait
    bit KeyboardStrobe

;; Performs a control character, below the space, or displays any other.
;; Also: C8_NOWAIT (UNKN), NOWAIT (IIEROM82)
NoWait:
    and #ASCII_BITS
    cmp #' ' & ASCII_BITS
    bcs Display
    jsr Control::Perform
    jmp Finish
.endproc

;; Displays <EightyColumns::CurrentCharacter> at the cursor, in the current video, and moves the cursor right,
;; starting a new line (<Control::CarriageReturn>) at the window's right edge.
;; Also: BPNCTL (IIEROM82)
.proc Display
    ldy EightyColumns::CursorColumn
    lda EightyColumns::CurrentCharacter
    jsr Screen::StoreCharacter
    inc EightyColumns::CursorColumn
    lda EightyColumns::CursorColumn
    cmp WindowWidth
    bcc Finish
    jsr Control::CarriageReturn
    ; Falls into Finish.
.endproc

;; The common exit of BASIC's input and output: the cursor to the Monitor's <CursorColumn> and <Monitor:CV>, the
;; caller's X and Y back, and A = <EightyColumns::CurrentCharacter>. The caller's A, Y and X are on the stack.
;; Out: A = the character or key, X and Y = the caller's
;; Also: BIORET (IIEROM82)
.proc Finish
    lda EightyColumns::CursorColumn
    jsr SetCursorColumn
    lda EightyColumns::CursorLine
    sta CV

    ; X, Y and the caller's A, which the character replaces.
    pla
    tax
    pla
    tay
    pla
    lda EightyColumns::CurrentCharacter
    rts
.endproc

;; BASIC's input: sets <MODE_INPUT>, puts back the character the Monitor's cursor replaced, then reads a key with
;; the cursor shown. The escape key enters <CharacterIo::EscapeMode>; any other key goes to
;; <CharacterIo::FinishKey>.
;; In: EightyColumns::CurrentCharacter = the character under the Monitor's cursor
;; Entry:
;;   NextKey = reads the next key; <CharacterIo::EscapeMode> returns here
;; Also: BINPUT (IIEROM82)
.proc Input
    lda EightyColumns::Mode
    ora #MODE_INPUT
    sta EightyColumns::Mode
    lda EightyColumns::CurrentCharacter
    ldy CursorColumn
    sta (TextBase),y

;; Reads a key, with the character at the firmware's cursor inverted while it waits.
;; Also: B_INPUT (IIEROM82)
NextKey:
    jsr Screen::InvertCursor
    jsr WaitForKey
    sta EightyColumns::CurrentCharacter
    jsr Screen::InvertCursor
    cmp #KEY_ESCAPE
    beq EscapeMode
    jmp FinishKey
.endproc

;; Escape mode: shows the escape cursor, reads a key, makes a letter uppercase and performs its code from
;; <CharacterIo::EscapeCodes>, staying in escape mode when the code has <CharacterIo::ESCAPE_STAY>.
;;
;; Of the keys not in <CharacterIo::EscapeKeys>, Control-Q quits the firmware and returns Control-X as the key, R and
;; T turn <MODE_UPPERCASE> on and off, and any other ends escape mode.
;; Also: ESCAPING (IIEROM82)
.proc EscapeMode
    jsr Screen::ShowEscapeCursor
    jsr WaitForKey
    jsr Screen::RestoreCharacter
    and #ASCII_BITS
    cmp #'`' & ASCII_BITS
    bcc Lookup
    and #UPPERCASE_MASK

;; Looks the key up in <CharacterIo::EscapeKeys>, from the end.
;;
;; The search starts one past the last key, at <CharacterIo::EscapeCodes>' first byte, Control-L's code: so an
;; escape Control-L matches it, and performs the byte after the codes ($AA, <Pascal::Status>' first) as code $2A,
;; for which <Control::Perform> reads past its tables.
;; Also: C8_ESC1 (UNKN), ESC1 (IIEROM82)
Lookup:
    ldy #EscapeCodes - EscapeKeys

;; Compares the key with one entry.
;; Also: ESC2 (IIEROM82)
Compare:
    cmp EscapeKeys,y
    beq Perform
    dey
    bpl Compare
    bmi Special

;; Performs the entry's code, then stays in escape mode or reads the next key.
;; Also: ESC3 (IIEROM82)
Perform:
    lda EscapeCodes,y
    and #ASCII_BITS
    jsr Control::Perform
    lda EscapeCodes,y
    bmi EscapeMode
    jmp Input::NextKey

;; Control-Q: quits the firmware, and returns Control-X as the key.
;; Also: ESCSPEC (IIEROM82)
Special:
    cmp #CONTROL_Q
    bne UppercaseOn
    jsr QuitFirmware
    lda #KEY_CONTROL_X
    sta EightyColumns::CurrentCharacter
    jmp Finish

;; R: sets <MODE_UPPERCASE>.
;; Also: ESCSPEC2 (IIEROM82)
UppercaseOn:
    cmp #'R' & ASCII_BITS
    bne UppercaseOff
    lda EightyColumns::Mode
    ora #MODE_UPPERCASE
    sta EightyColumns::Mode

;; Leaves escape mode for the next key.
;; Also: ESCNONE (IIEROM82)
Done:
    jmp Input::NextKey

;; T: clears <MODE_UPPERCASE>; any other key just leaves escape mode.
;; Also: ESCSPEC3 (IIEROM82)
UppercaseOff:
    cmp #'T' & ASCII_BITS
    bne Done
    lda EightyColumns::Mode
    and #<~MODE_UPPERCASE
    sta EightyColumns::Mode
    jmp Input::NextKey
.endproc

; The escape-mode keys and their codes.

;; On a code in <CharacterIo::EscapeCodes>: escape mode goes on after it.
;; Also: ESC_STAY (UNKN)
ESCAPE_STAY = $80

;; The escape keys <EscapeEntry> has added so far.
.set ESCAPE_ENTRIES, 0

    EscapeEntry '@', CONTROL_L                                  ; home and clear the window
    EscapeEntry 'A', CONTROL_BACKSLASH                          ; right
    EscapeEntry 'B', CONTROL_H                                  ; left
    EscapeEntry 'C', CONTROL_J                                  ; down
    EscapeEntry 'D', CONTROL_UNDERSCORE                         ; up
    EscapeEntry 'E', CONTROL_RIGHT_BRACKET                      ; clear to the end of the line
    EscapeEntry 'F', CONTROL_K                                  ; clear to the end of the window
    EscapeEntry 'I', CONTROL_UNDERSCORE | ESCAPE_STAY           ; up
    EscapeEntry 'J', CONTROL_H | ESCAPE_STAY                    ; left
    EscapeEntry 'K', CONTROL_BACKSLASH | ESCAPE_STAY            ; right
    EscapeEntry 'M', CONTROL_J | ESCAPE_STAY                    ; down
    EscapeEntry '4', CONTROL_Q                                  ; 40 columns
    EscapeEntry '8', CONTROL_R                                  ; 80 columns
    EscapeEntry KEY_BACKSPACE, CONTROL_H | ESCAPE_STAY          ; the left arrow
    EscapeEntry KEY_LINE_FEED, CONTROL_J | ESCAPE_STAY          ; the down arrow
    EscapeEntry KEY_CONTROL_K, CONTROL_UNDERSCORE | ESCAPE_STAY ; the up arrow
    EscapeEntry KEY_RIGHT_ARROW, CONTROL_BACKSLASH | ESCAPE_STAY ; the right arrow

;; The escape-mode keys, with their high bits clear, which <CharacterIo::EscapeMode> looks up.
;; Also: ESCTAB (IIEROM82)
EscapeKeys:
.repeat ESCAPE_ENTRIES, index
    .byte .ident(.sprintf("ESCAPE_KEY_%d", index))
.endrepeat

;; The control code each of <CharacterIo::EscapeKeys> performs, with <CharacterIo::ESCAPE_STAY>.
;; Also: ESCCHAR (IIEROM82)
EscapeCodes:
.repeat ESCAPE_ENTRIES, index
    .byte .ident(.sprintf("ESCAPE_CODE_%d", index))
.endrepeat

.endscope

; Pascal: the status request, around Pascal 1.0's write hook.
.scope Pascal continued

;; Pascal's status request: request 0 (ready for output) is always ready, request 1 (input) is ready when a key
;; waits, and any other is an error.
;;
;; <Pascal::StatusEntry at JPSTAT> jumps here.
;; In: A = the request
;; Out: X = 0, or <PASCAL_BAD_REQUEST> for a request other than 0 and 1; carry = set when ready
;; Also: PSTATUS (IIEROM82)
.proc Status
    tax
    jsr Setup
    txa
    bne OtherRequest
    sec
    bcs KeyStatus::Ready

;; Request 1 goes to <Pascal::KeyStatus>; any other is an error, with the carry clear.
;; Also: PSTATUS2 (IIEROM82)
OtherRequest:
    cmp #PASCAL_STATUS_INPUT
    beq KeyStatus
    ldx #PASCAL_BAD_REQUEST
    clc
    rts

    ; Unused, up to Pascal 1.0's write hook.
    .byte $00, $00, $00, $00
.endproc

;; Pascal 1.0's write hook: writes <EightyColumns::CurrentCharacter> through <Pascal::WriteEntry at JPWRITE>.
;;
;; At $C9AA.
;; Also: C9ENTRY (UNKN)
.proc Write10Entry
.assert * = $C9AA, "Pascal::Write10Entry must stay at $C9AA."
    lda EightyColumns::CurrentCharacter
    jmp WriteEntry
.endproc

;; Pascal's status request 1: ready when a key waits.
;; Out: X = 0, carry = set when a key waits
;; Entry:
;;   Ready = returns X = 0 with the carry as it is; <Pascal::Status> branches here for request 0
;; Also: PSTATUS3 (IIEROM82)
.proc KeyStatus
    lda Keyboard
    asl a

;; Returns X = 0.
;; Also: PSTATUS4 (IIEROM82)
Ready:
    ldx #0
    rts
.endproc

.endscope

; CharacterIo: finishing a key BASIC's input read, and the character before the cursor.
.scope CharacterIo continued

;; Finishes a key BASIC's input read: the right arrow (Control-U) takes the character under the cursor; quotes are
;; tracked in <MODE_QUOTES>; outside them, lowercase becomes uppercase while <MODE_UPPERCASE> is set. Then
;; <CharacterIo::Finish> returns the key.
;;
;; Outside quotes, a quote or a backspace over one enters them; inside, a quote, Control-X, a return or a backspace
;; over a quote leaves them.
;; In: A = <EightyColumns::CurrentCharacter> = the key
;; Also: NOESC (IIEROM82)
.proc FinishKey
    cmp #KEY_RIGHT_ARROW
    bne TrackQuotes
    ldy EightyColumns::CursorColumn
    jsr Screen::ReadCharacter
    ora #TEXT_HIGH_BIT
    sta EightyColumns::CurrentCharacter

;; Outside quotes: a quote, or a backspace over one, enters them.
;; Also: B_NOPICK (IIEROM82)
TrackQuotes:
    lda EightyColumns::Mode
    and #MODE_QUOTES
    bne InQuotes
    lda EightyColumns::CurrentCharacter
    cmp #'"'
    beq ToggleQuotes
    cmp #KEY_BACKSPACE
    bne Upshift
    jsr CharacterBefore
    bne Upshift
    beq ToggleQuotes

;; Inside quotes: a quote, Control-X, a return, or a backspace over a quote leaves them.
;; Also: B_CHKCAN (IIEROM82)
InQuotes:
    lda EightyColumns::CurrentCharacter
    cmp #'"'
    beq LeaveQuotes
    cmp #KEY_CONTROL_X
    beq LeaveQuotes
    cmp #KEY_RETURN
    beq LeaveQuotes
    cmp #KEY_BACKSPACE
    bne Upshift
    jsr CharacterBefore
    bne Upshift

;; Flips <MODE_QUOTES>.
;; Also: B_FLIP (IIEROM82)
ToggleQuotes:
    lda EightyColumns::Mode
    eor #MODE_QUOTES
    sta EightyColumns::Mode
    jmp Upshift
    ; The routine goes on in EightyColumnsControl.asm, at $CA02.
