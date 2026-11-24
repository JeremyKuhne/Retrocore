; retrocore: style=strict
;; The 80-column firmware's $C800-$C9EF, Enhanced IIe: Pascal 1.0's hooks at $C800, $C84D and $C9AA, starting the
;; firmware for BASIC, the keyboard wait, BASIC's character input and output through slot 3 (printing, reading keys
;; with escape mode), the auxiliary RAM test, the letters the arrow keys become, and Pascal's init and read.

; Characters.

;; A character's bits without its high bit: the code a control character or Pascal has.
ASCII_BITS = %01111111

;; A character's high bit, which the screen and the keyboard set on normal text.
TEXT_HIGH_BIT = %10000000

; Pascal.

;; The error <Pascal::Init> returns in X when the IIe has no auxiliary memory.
PASCAL_NO_DEVICE = 9

;; What <Pascal::Read> returns in X for Pascal 1.0, slot 3's page, where Pascal 1.1 gets 0.
PASCAL10_READ_X = $C3

; The auxiliary RAM test.

;; The byte <TestAuxRam> writes to auxiliary memory.
AUX_RAM_TEST_BYTE = $EE

;; The auxiliary byte <TestAuxRam> writes and reads back.
AuxRamTestByte = $0C00

;; The other auxiliary byte <TestAuxRam> writes, 1K below <AuxRamTestByte>.
AuxRamTestOtherByte = $0800

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
;; At $C800. Apple's listing says the three hooks at $C800, $C84D and $C9AA are only used by Pascal 1.0.
;; Also: C8ENTRY (UNKN)
.proc Init10Entry
.assert * = $C800, "Pascal::Init10Entry must stay at $C800."
    jmp Init10
.endproc

.endscope

; CharacterIo: starting the firmware for BASIC.
.scope CharacterIo continued

;; Starts the firmware for BASIC, for `PR#3`: the Monitor in the language card made the IIe's, the hooks, the
;; 40-column window and the mode; with auxiliary memory, 80 columns. Then the alternate characters, the window homed
;; and cleared, and the character printed.
;;
;; <CharacterIo::Enter at C3ENTRY> jumps here, with the caller's Y and X on the stack.
;; In: EightyColumns::CurrentCharacter = the character to print once started
;; Also: BASICINIT (IIEROM82, IIETRM85), C3INIT (UNKN)
.proc Initialize
    jsr CopyMonitorToRam
    jsr SetSlot3Hooks
    jsr Control::Window40
    lda #MODE_MOUSETEXT_OFF
    sta EightyColumns::Mode

    ; 80 columns with auxiliary memory: the window twice as wide, 80STORE and 80VID on.
    jsr TestAuxMemory
    bne Clear
    asl WindowWidth
    sta Store80On
    sta Columns80On

;; Turns the alternate characters on and clears the window, then prints the character.
;; Also: CLEARIT (IIETRM85)
Clear:
    sta AlternateCharactersOn
    jsr Control::HomeAndClear
    ldy EightyColumns::CursorColumn
    jmp Print
.endproc

.endscope

;; Points the output hook at <BasicOutput at BASICOUT> and the input hook at <BasicInput at BASICIN>.
;; Keeps: X, Y
;; Entry:
;;   Input = points only the input hook; <Functions::Slot3Input at CXPORTC3> jumps here
;; Also: SETC3HOOKS (UNKN), C3HOOKS (IIETRM85)
.proc SetSlot3Hooks
    lda #<BasicOutput
    sta OutputHook
    lda #>BasicOutput
    sta OutputHookHigh

;; Points the input hook at <BasicInput at BASICIN>.
;; Also: C3IN (IIETRM85)
Input:
    lda #<BasicInput
    sta InputHook
    lda #>BasicInput
    sta InputHookHigh
    rts
.endproc

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

    ; Unused, up to Pascal 1.0's read hook.
    .byte $00, $00, $00
.endproc

; Pascal: Pascal 1.0's read hook.
.scope Pascal continued

;; Pascal 1.0's read hook: goes to <Pascal::ReadEntry at PASREAD>.
;;
;; At $C84D.
;; Also: C8PASREAD (UNKN)
.proc Read10Entry
.assert * = $C84D, "Pascal::Read10Entry must stay at $C84D."
    jmp ReadEntry
.endproc

.endscope

;; Brings the firmware's cursor up to date with the Monitor's: the line from <Monitor:CV>, the column from
;; <CursorColumn> unless it is the one the firmware stored last, and the column 0 when it is outside the window.
;; Out: Y = <EightyColumns::CursorColumn>
;; Keeps: X
;; Also: SYNCCH (UNKN), CSETUP (IIETRM85)
.proc SyncCursor
    lda CV
    sta EightyColumns::CursorLine
    ldy CursorColumn
    cpy EightyColumns::LastCursorColumn
    beq CheckColumn
    sty EightyColumns::CursorColumn

;; The column 0 unless it is inside the window.
;; Also: CS2 (IIETRM85)
CheckColumn:
    lda WindowWidth
    clc
    sbc EightyColumns::CursorColumn
    bcs Done
    ldy #0
    sty EightyColumns::CursorColumn

    ; Y = the column.
;; Also: CS3 (IIETRM85)
Done:
    ldy EightyColumns::CursorColumn
    rts
.endproc

; CharacterIo: BASIC's input and output.
.scope CharacterIo continued

;; The 80-column output, function 0 (<FIRMWARE_OUTPUT>): prints the character in A, with Y back from
;; <SavedOutputY>, as <CharacterIo::InputKey> does.
;; In: A = the character
;; Out: A = the character
;; Also: BOUT (IIEROM82, IIETRM85), CHARIO80 (UNKN)
.proc Output
    ldy SavedOutputY
    clc
    ; A bcs, never taken: it skips InputKey's sec.
    .byte $B0
    ; Falls into InputKey.
.endproc

;; Reads a key for the Monitor's <KeyboardIn> with 80VID on: saves the character, Y and X, then
;; <CharacterIo::InputOrOutput> with the carry set.
;; In: A = the character under the cursor
;; Out: A = the key
;; Also: BIN (IIETRM85)
.proc InputKey
    sec
    sta EightyColumns::CurrentCharacter
    tya
    pha
    txa
    pha
    ; Falls into InputOrOutput.
.endproc

;; The shared path of the hooks and the functions: <CharacterIo::Input> with the carry set, else
;; <CharacterIo::Print>.
;;
;; <CharacterIo::Enter at C3ENTRY> jumps here, with the caller's Y and X on the stack.
;; Also: C8BASIC (IIEROM82, IIETRM85)
.proc InputOrOutput
    bcs Input
    ; Falls into Print.
.endproc

;; Prints <EightyColumns::CurrentCharacter>: performs a control character, unless they are off, or displays any
;; other.
;;
;; A return while Control-S waits in the keyboard pauses until another key; a Control-C is left in the keyboard
;; for BASIC to find. <CharacterIo::Initialize> jumps here.
;; Also: BPRINT (IIEROM82, IIETRM85)
.proc Print
    jsr SyncCursor

    ; A return with Control-S typed: wait for the next key.
    lda EightyColumns::CurrentCharacter
    cmp #KEY_RETURN
    bne NoWait
    ldx Keyboard
    bpl NoWait
    cpx #KEY_CONTROL_S
    bne NoWait
    bit KeyboardStrobe

;; Waits for the key after Control-S, and clears it unless it is Control-C.
;; Also: C8_KBDWAIT (UNKN), KBDWAIT (IIEROM82, IIETRM85)
WaitForResume:
    ldx Keyboard
    bpl WaitForResume
    cpx #KEY_CONTROL_C
    beq NoWait
    bit KeyboardStrobe

;; Performs a control character, below the space, or displays any other.
;; Also: C8_NOWAIT (UNKN), NOWAIT (IIEROM82, IIETRM85)
NoWait:
    and #ASCII_BITS
    cmp #' ' & ASCII_BITS
    bcs Display
    jsr Control::PerformUnlessDisabled
    jmp EndOutput
.endproc

;; Displays <EightyColumns::CurrentCharacter> at the cursor, in the current video, and moves the cursor right,
;; starting a new line (<Control::CarriageReturn>) at the window's right edge.
;; In: Y = <EightyColumns::CursorColumn>
;; Also: BPNCTL (IIEROM82, IIETRM85), PRINT80 (UNKN)
.proc Display
    lda EightyColumns::CurrentCharacter
    jsr Screen::StoreCharacter
    iny
    sty EightyColumns::CursorColumn
    cpy WindowWidth
    bcc EndOutput
    jsr Control::CarriageReturn
    ; Falls into EndOutput.
.endproc

;; Ends an output: clears <MODE_ESCAPES>.
;; Also: CTLON (IIETRM85)
.proc EndOutput
    lda EightyColumns::Mode
    and #<~MODE_ESCAPES
    sta EightyColumns::Mode
    ; Falls into Finish.
.endproc

;; The common exit of BASIC's input and output: the Monitor's <CursorColumn> and the firmware's last from the
;; firmware's column, or 0 in 80 columns; the caller's X and Y back, and A = <EightyColumns::CurrentCharacter>.
;; Out: A = the character or key, X and Y = the caller's
;; Also: BIORET (IIEROM82, IIETRM85)
.proc Finish
    lda EightyColumns::CursorColumn
    bit Columns80State
    bpl StoreColumn
    lda #0

;; Stores the column in <CursorColumn> and <EightyColumns::LastCursorColumn>, then returns.
;; Also: SETALL (IIETRM85)
StoreColumn:
    sta CursorColumn
    sta EightyColumns::LastCursorColumn
    pla
    tax
    pla
    tay
    lda EightyColumns::CurrentCharacter
    rts
.endproc

;; BASIC's input: puts back the character the Monitor's cursor replaced, then reads a key with the cursor shown.
;;
;; Without <MODE_ESCAPES> the key is returned as it is. With it, a return clears the bit, the right arrow
;; (Control-U) returns the character under the cursor, and the escape key enters <CharacterIo::EscapeMode>.
;; In: EightyColumns::CurrentCharacter = the character under the Monitor's cursor
;; Entry:
;;   NextKey = reads the next key; <CharacterIo::EscapeMode> returns here
;; Also: BINPUT (IIEROM82, IIETRM85), INPUT80 (UNKN)
.proc Input
    ldy CursorColumn
    lda EightyColumns::CurrentCharacter
    sta (TextBase),y
    jsr SyncCursor

;; Reads a key, with the cursor shown while it waits.
;; Also: B_INPUT (IIEROM82, IIETRM85)
NextKey:
    jsr Screen::InvertCursor
    jsr WaitForKey
    sta EightyColumns::CurrentCharacter
    jsr Screen::InvertCursor
    tay
    lda EightyColumns::Mode
    and #MODE_ESCAPES
    beq Finish
    cpy #KEY_RETURN
    bne NotReturn
    lda EightyColumns::Mode
    and #<~MODE_ESCAPES
    sta EightyColumns::Mode

;; The escape key enters escape mode; the right arrow takes the character under the cursor.
;; Also: NOTACR (IIETRM85)
NotReturn:
    cpy #KEY_ESCAPE
    beq EscapeMode
    cpy #KEY_RIGHT_ARROW
    bne Finish
    ldy EightyColumns::CursorColumn
    jsr Screen::ReadCharacter
    ora #TEXT_HIGH_BIT
    sta EightyColumns::CurrentCharacter
    ; Always: the high bit is set.
    bne Finish
.endproc

;; Escape mode: shows the escape cursor, reads a key, makes it uppercase and performs its code from
;; <CharacterIo::EscapeCodes>, staying in escape mode when the code has <CharacterIo::ESCAPE_STAY>.
;;
;; Of the keys not in <CharacterIo::EscapeKeys>, Control-Q quits the firmware and returns Control-X as the key,
;; Control-E and Control-D turn the control characters on and off (<MODE_CONTROLS_OFF>), and any other ends escape
;; mode.
;; Also: ESCAPING (IIEROM82, IIETRM85)
.proc EscapeMode
    jsr Screen::ShowEscapeCursor
    jsr WaitForKey
    jsr Screen::RestoreCharacter
    jsr Upshift
    and #ASCII_BITS
    ldy #ESCAPE_COUNT - 1

;; Compares the key with one entry, from the end.
;; Also: ESC2 (IIEROM82, IIETRM85)
Compare:
    cmp EscapeKeys,y
    beq Perform
    dey
    bpl Compare
    bmi Special

;; Performs the entry's code, then stays in escape mode or reads the next key.
;; Also: ESC3 (IIEROM82, IIETRM85)
Perform:
    lda EscapeCodes,y
    and #ASCII_BITS
    jsr Control::Perform
    lda EscapeCodes,y
    bmi EscapeMode
    bpl Input::NextKey

;; Control-Q: quits the firmware, and returns Control-X as the key.
;; Also: ESCSPEC (IIEROM82, IIETRM85)
Special:
    tay
    lda EightyColumns::Mode
    cpy #CONTROL_Q
    bne ControlsOn
    jsr Control::Quit
    lda #KEY_CONTROL_X
    sta EightyColumns::CurrentCharacter
    jmp Finish

;; Control-E: turns the control characters on.
;; Also: ESCSP1 (IIETRM85)
ControlsOn:
    cpy #CONTROL_E
    bne ControlsOff
    and #<~MODE_CONTROLS_OFF

;; Stores the mode.
;; Also: ESCSP2 (IIETRM85)
StoreMode:
    sta EightyColumns::Mode

;; Leaves escape mode for the next key.
;; Also: ESCNONE (IIEROM82), ESCSP3 (IIETRM85)
Done:
    jmp Input::NextKey

;; Control-D: turns the control characters off; any other key just leaves escape mode.
;; Also: ESCSP4 (IIETRM85)
ControlsOff:
    cpy #CONTROL_D
    bne Done
    ora #MODE_CONTROLS_OFF
    ; Always: the mode is not 0 now.
    bne StoreMode
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

;; How many escape keys there are: the length of <CharacterIo::EscapeKeys> and <CharacterIo::EscapeCodes>.
;; Also: ESCNUM (IIETRM85)
ESCAPE_COUNT = ESCAPE_ENTRIES

;; The control code each of <CharacterIo::EscapeKeys> performs, with <CharacterIo::ESCAPE_STAY>.
;; Also: ESCCHAR (IIEROM82, IIETRM85), ESCCODES (UNKN)
EscapeCodes:
.repeat ESCAPE_ENTRIES, index
    .byte .ident(.sprintf("ESCAPE_CODE_%d", index))
.endrepeat

;; The escape-mode keys, with their high bits clear, which <CharacterIo::EscapeMode> looks up.
;; Also: ESCTAB (IIEROM82, IIETRM85), ESCKEYS (UNKN)
EscapeKeys:
.repeat ESCAPE_ENTRIES, index
    .byte .ident(.sprintf("ESCAPE_KEY_%d", index))
.endrepeat

.endscope

;; Tests auxiliary RAM, unless auxiliary memory is already read: writes <AUX_RAM_TEST_BYTE> to auxiliary
;; <AuxRamTestByte> and <AuxRamTestOtherByte>, leaving auxiliary memory read and written, and compares the first.
;;
;; <SelfTest::RamTest at RAMTEST> calls it.
;; Out: zero = set when the byte held; when auxiliary memory was already read, nothing is written and zero is what
;;   BIT left
;; Keeps: X, Y
;; Also: AUXRAMTEST (UNKN), STAUX (IIETRM85)
.proc TestAuxRam
    bit AuxReadState
    bmi Done
    lda #AUX_RAM_TEST_BYTE
    sta AuxWriteOn
    sta AuxReadOn
    sta AuxRamTestByte
    sta AuxRamTestOtherByte
    cmp AuxRamTestByte

;; Returns.
;; Also: XSTAUX (IIETRM85)
Done:
    rts
.endproc

; Functions: the letters the arrow keys become, among the 80-column firmware.
.scope Functions continued

;; The letters J, K, M and I that <Functions::EscapeKey at CXESCKEY> makes of the arrow keys in
;; <Functions::ArrowKeys at ARROWKEYS>.
;; Also: ESCOUT (IIEROM82, IIETRM85), ARROWLETTERS (UNKN)
ArrowLetters:
    .byte "JKMI"
.assert * - ArrowLetters = ARROW_COUNT, "Each arrow key needs a letter."

    ; Unused, up to Pascal 1.0's write hook.
    .byte $00, $00

.endscope

; Pascal: Pascal 1.0's write hook, init and read.
.scope Pascal continued

;; Pascal 1.0's write hook: writes <EightyColumns::CurrentCharacter> through <Pascal::WriteEntry at PASWRITE>.
;;
;; At $C9AA.
;; Also: C9ENTRY (UNKN)
.proc Write10Entry
.assert * = $C9AA, "Pascal::Write10Entry must stay at $C9AA."
    lda EightyColumns::CurrentCharacter
    jmp WriteEntry
.endproc

;; Starts the firmware for Pascal 1.0: as <Pascal::Init>, with <MODE_PASCAL10> too.
;;
;; <Pascal::Init10Entry> jumps here.
;; Out: X = 0, or <PASCAL_NO_DEVICE> without auxiliary memory
;; Also: PINIT1_0 (IIEROM82, IIETRM85), C9PASINIT (UNKN)
.proc Init10
    lda #MODE_PASCAL | MODE_PASCAL10 | MODE_MOUSETEXT_OFF
    ; Always: the mode is not 0.
    bne Init::SetMode
.endproc

;; Starts the firmware for Pascal: with auxiliary memory, the mode, 80 columns, the alternate characters, Pascal's
;; video and the window cleared, then the cursor shown.
;;
;; <Pascal::InitEntry at PASINIT> jumps here.
;; Out: X = 0, or <PASCAL_NO_DEVICE> without auxiliary memory
;; Entry:
;;   SetMode = starts with the mode in A; <Pascal::Init10> branches here
;; Also: PINIT (IIEROM82, IIETRM85)
.proc Init
    lda #MODE_PASCAL | MODE_MOUSETEXT_OFF

;; Starts with the mode in A, unless there is no auxiliary memory.
;; Also: PINIT2 (IIEROM82, IIETRM85)
SetMode:
    pha
    jsr TestAuxMemory
    beq CardPresent
    pla
    ldx #PASCAL_NO_DEVICE
    rts

;; Auxiliary memory answered: the mode, 80 columns and the window cleared, then the cursor shown through
;; <Pascal::Write::SaveBase>.
;; Also: PIGOOD (IIEROM82, IIETRM85)
CardPresent:
    pla
    sta EightyColumns::Mode
    sta Store80On
    sta Columns80On
    sta AlternateCharactersOn
    jsr Setup
    jsr Control::HomeAndClear
    jmp Write::SaveBase
.endproc

;; Pascal's read: waits for a key and returns it with its high bit clear.
;;
;; <Pascal::ReadEntry at PASREAD> jumps here.
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

.endscope
