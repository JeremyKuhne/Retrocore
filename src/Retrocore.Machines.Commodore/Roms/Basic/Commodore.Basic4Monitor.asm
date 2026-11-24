; retrocore: style=strict
;; COMMODORE BASIC 4: THE MACHINE-LANGUAGE MONITOR
;;
;; The monitor in BASIC 4's $D000 chip, the same in both revisions. The kernal enters it at <Monitor::EnterByBreak>
;; after a `BRK`, or at <Monitor::EnterByCall> at reset when the diagnostic line is held low. It shows the registers,
;; then reads commands from the screen editor's line input, each a letter after the `.` prompt:
;;
;; - `R` shows the saved program counter, interrupt vector and registers, as a line to edit and re-enter with `;`;
;; - `M` shows memory from one address to another, eight bytes a line, as lines to edit and re-enter with `:`;
;; - `G` resumes the program, at its saved program counter or at a given address;
;; - `X` returns to BASIC;
;; - `L` and `S` load and save memory, with a filename, a device, and for `S` the start and end addresses.
;;
;; Any other letter goes through <MonitorUserCommandVector>. The names are those of Commodore's PET 4.0 kernal listing
;; (K4S79) and its reconstruction (HVK4).

;; Emits the monitor, <Monitor>.
.macro CommodoreBasic4Monitor

    ;; The machine-language monitor: its entries, its command loop and commands, and the helpers that read and print
    ;; hexadecimal. The commands are entered by <Monitor::Dispatch>, and none returns: `G` resumes the program
    ;; with `rti`, `X` goes back to <ReadyForCommand>, and the others go back to <Monitor::Prompt>. Its saved
    ;; registers and work bytes are the kernal's, in Commodore.Basic4SystemEquates.asm.
    .scope Monitor

    ; The entries and the command loop.

    ;; Enters the monitor with `C` as the entry letter.
    ;;
    ;; The kernal jumps here at reset when the diagnostic line is held low (the overlay's comment calls it the entry
    ;; after a `CALL`). The carry is not set up before <Monitor::SaveState>'s `adc #$FF`, which <Monitor::EnterByBreak>
    ;; prepares: with carry set, the saved program counter is the address on the stack itself; with it clear, one
    ;; less.
    ;; Also: CALLE (K4S79, HVK4)
    .proc EnterByCall
    lda #'C'
    sta MonitorCount
    bne SaveState
    .endproc

    ;; Enters the monitor after a `BRK`, with `B` as the entry letter, saving the interrupted program's registers.
    ;;
    ;; The 6502 pushed the return address and the status for the `BRK`, and the kernal's interrupt entry pushed A,
    ;; X and Y after them before jumping here. This pops Y, X, A and the status into the save area and clears the
    ;; carry for <Monitor::SaveState>, which then saves the address after the `BRK` instruction's opcode.
    ;; Also: BRKE (K4S79, HVK4)
    .proc EnterByBreak
    jsr KernalRestoreChannels
    lda #'B'
    sta MonitorCount
    cld

    ; The letter is even, so this clears the carry.
    lsr a
    pla
    sta SavedY
    pla
    sta SavedX
    pla
    sta SavedA
    pla
    sta SavedStatus
    ; Falls into SaveState.
    .endproc

    ;; Saves the program counter, the interrupt vector and the stack pointer, enables interrupts, and shows the
    ;; registers.
    ;;
    ;; It pops the address on top of the stack, adding $FFFF and the carry: with the carry clear, the address less one.
    ;; It prints the entry letter in <MonitorCount> and `*`, then runs `R`.
    ;; In: carry = clear to save the popped address less one, MonitorCount = the entry letter
    ;; Entry:
    ;;   ShowEntry = prints the entry letter and `*`, then runs `R`
    ;; Also: B3 (K4S79, HVK4)
    .proc SaveState
    pla
    adc #$FF
    sta ProgramCounter
    pla
    adc #$FF
    sta ProgramCounterHigh
    lda IrqVector
    sta SavedIrqVector
    lda IrqVector+1
    sta SavedIrqVectorHigh
    tsx
    stx SavedStackPointer
    cli

;; Prints a carriage return, the entry letter and `*`, then runs `R`.
;; Also: B5 (K4S79, HVK4)
ShowEntry:
    jsr PrintCarriageReturn
    ldx MonitorCount
    lda #'*'
    jsr PrintPair
    lda #'R'
    bne Dispatch
    .endproc

    ;; Prints the `.` prompt on a new line and reads a command letter, skipping periods and spaces.
    ;;
    ;; It stores 2 in <TextPointer>'s low byte, which the monitor itself never reads, and clears
    ;; <MonitorAddressWrapped>. It does not reset the stack pointer.
    ;; Entry:
    ;;   SkipSeparator = reads the next character, skipping periods and spaces
    ;; Also: STRT (K4S79, HVK4)
    .proc Prompt
    lda #$02
    sta TextPointer
    lda #$00
    sta MonitorAddressWrapped
    ldx #CARRIAGE_RETURN
    lda #'.'
    jsr PrintPair

;; Reads a character, skipping periods and spaces.
;; Also: ST1 (K4S79, HVK4)
SkipSeparator:
    jsr ReadCharacter
    cmp #'.'
    beq SkipSeparator
    cmp #' '
    beq SkipSeparator
    ; Falls into Dispatch.
    .endproc

    ;; Runs the command for a letter, or jumps through <MonitorUserCommandVector> for a letter it does not know.
    ;;
    ;; It stores the letter's index in <MonitorCommandIndex> and returns into the command, by pushing the command's
    ;; address less one from <Monitor::CommandsHigh> and <Monitor::CommandsLow>.
    ;; In: A = the command letter
    ;; Entry:
    ;;   Compare = compares A with the key at index X
    ;;   Next = tries the key before index X
    ;; Also: S0 (K4S79, HVK4)
    .proc Dispatch
    ldx #MONITOR_COMMAND_COUNT-1

;; Compares A with the command key at index X.
;; Also: S1 (K4S79, HVK4)
Compare:
    cmp CommandKeys,x
    bne Next
    stx MonitorCommandIndex
    lda CommandsHigh,x
    pha
    lda CommandsLow,x
    pha
    rts

;; Tries the key before index X, or the user's command vector after the first.
;; Also: S2 (K4S79, HVK4)
Next:
    dex
    bpl Compare
    jmp (MonitorUserCommandVector)
    .endproc

    ; The helpers of the commands.

    ;; Copies <MonitorAddress> to the saved program counter.
    ;; Out: ProgramCounter = the low byte of <MonitorAddress>, ProgramCounterHigh = its high byte, A = its high byte
    ;; Keeps: X, Y
    ;; Also: PUTP (K4S79, HVK4)
    .proc SetProgramCounter
    lda MonitorAddress
    sta ProgramCounter
    lda MonitorAddress+1
    sta ProgramCounterHigh
    rts
    .endproc

    ;; Prints A bytes from <MonitorAddress> in hexadecimal, each after a space, advancing the address past them.
    ;; In: A = the count, 0 for 256
    ;; Out: MonitorAddress = the address after the bytes, MonitorCount = 0, zero = set, Y = 0
    ;; Entry:
    ;;   NextByte = prints the next byte
    ;; Also: DM (K4S79, HVK4)
    .proc PrintBytes
    sta MonitorCount
    ldy #$00

;; Prints a space and the byte at <MonitorAddress>, and advances it.
;; Also: DM1 (K4S79, HVK4)
NextByte:
    jsr OutputSpace
    lda (MonitorAddress),y
    jsr PrintByte
    jsr NextAddress
    dec MonitorCount
    bne NextByte
    rts
    .endproc

    ;; Reads a hexadecimal byte and, when one is there, stores it at <MonitorAddress> and checks that it was
    ;; stored; then advances the address and counts <MonitorCount> down.
    ;;
    ;; A byte that does not read back as written (ROM, or no memory there) abandons the command: it discards its
    ;; own return address and goes to <Monitor::ShowError>.
    ;; In: MonitorAddress = where to store, MonitorCount = the bytes left
    ;; Out: MonitorAddress = the next address, MonitorCount = one less, zero = set when it reaches zero
    ;; Entry:
    ;;   Advance = advances <MonitorAddress> and counts <MonitorCount> down
    ;; Also: BYTE (K4S79, HVK4)
    .proc AlterByte
    jsr ReadByte
    bcc Advance
    ldx #$00
    sta (MonitorAddress,x)
    cmp (MonitorAddress,x)
    beq Advance
    pla
    pla
    jmp ShowError

;; Advances <MonitorAddress> and counts <MonitorCount> down.
;; Also: BY3 (K4S79, HVK4)
Advance:
    jsr NextAddress
    dec MonitorCount
    rts
    .endproc

    ;; Points <MonitorAddress> at the five saved register bytes, from <SavedStatus>, for showing or altering them.
    ;; Out: MonitorAddress = the address of <SavedStatus>, A = 5, zero = clear
    ;; Keeps: X, Y
    ;; Also: SETR (K4S79, HVK4)
    .proc SelectRegisters
    lda #<SavedStatus
    sta MonitorAddress
    lda #>SavedStatus
    sta MonitorAddress+1
    lda #SAVED_REGISTER_COUNT
    rts
    .endproc

    ;; The number of saved register bytes `R` shows and `;` alters: the status, A, X, Y and the stack pointer.
    SAVED_REGISTER_COUNT = SavedStackPointer + 1 - SavedStatus
    .assert SAVED_REGISTER_COUNT = 5, "The status, A, X, Y and the stack pointer."

    ;; Prints two spaces.
    ;; Also: SPAC2 (K4S79, HVK4)
    .proc PrintTwoSpaces
    jsr OutputSpace
    ; Falls into OutputSpace.
    .endproc

    ;; Prints a space.
    ;; Also: SPACE (K4S79, HVK4)
    .proc OutputSpace
    lda #' '
    .byte $2C                   ; BIT absolute skips PrintCarriageReturn's lda #
    ; Falls into PrintCarriageReturn, past its first instruction.
    .endproc

    ;; Prints a carriage return.
    ;; Also: CRLF (K4S79, HVK4)
    .proc PrintCarriageReturn
    lda #CARRIAGE_RETURN
    jmp KernalOutputCharacter
    .endproc

    ;; Advances <MonitorAddress> by one, counting a wrap past $FFFF in <MonitorAddressWrapped>.
    ;; Out: MonitorAddress = one more, MonitorAddressWrapped = one more when the address wrapped to zero
    ;; Keeps: A, X, Y
    ;; Entry:
    ;;   Done = returns
    ;; Also: INCTMP (K4S79, HVK4)
    .proc NextAddress
    inc MonitorAddress
    bne Done
    inc MonitorAddress+1
    bne Done
    inc MonitorAddressWrapped

;; Returns.
;; Also: SETWR (K4S79, HVK4)
Done:
    rts
    .endproc

    ; The command table and the register heading.

    ;; The command letters, in the order of <Monitor::CommandsHigh> and <Monitor::CommandsLow>: `:` and `;` alter
    ;; memory and the registers, `R` and `M` show them, then `G`, `X`, `L` and `S`.
    ;; Also: CMDS (K4S79, HVK4)
CommandKeys:
    .byte ':', ';', 'R', 'M', 'G', 'X', 'L', 'S'
    .assert * - CommandKeys = MONITOR_COMMAND_COUNT, "One key per monitor command."

    ;; The index of `L` in <Monitor::CommandKeys>, which <MonitorCommandIndex> holds while it runs.
    LOAD_COMMAND = 6

    ;; The index of `S` in <Monitor::CommandKeys>.
    SAVE_COMMAND = 7

    ;; The high bytes of each command's address less one, which <Monitor::Dispatch> returns into.
    ;; Also: ADRH (K4S79, HVK4)
CommandsHigh:
    .byte >(AlterMemory-1), >(AlterRegisters-1), >(DisplayRegisters-1), >(DisplayMemory-1)
    .byte >(Go-1), >(Exit-1), >(LoadOrSave-1), >(LoadOrSave-1)

    ;; The low bytes of each command's address less one.
    ;; Also: ADRL (K4S79, HVK4)
CommandsLow:
    .byte <(AlterMemory-1), <(AlterRegisters-1), <(DisplayRegisters-1), <(DisplayMemory-1)
    .byte <(Go-1), <(Exit-1), <(LoadOrSave-1), <(LoadOrSave-1)
    .assert * - CommandsHigh = 2 * MONITOR_COMMAND_COUNT, "Two address bytes per monitor command."

    ;; A carriage return and the heading `R` prints over the registers.
    ;; Also: REGK (K4S79, HVK4)
RegisterHeading:
    .byte CARRIAGE_RETURN, "     PC  IRQ  SR AC XR YR SP"

    ;; The length of <Monitor::RegisterHeading>, with its carriage return.
    HEADING_LENGTH = * - RegisterHeading
    .assert HEADING_LENGTH = 29, "The register heading is 29 bytes."

    ;; Starts a line to edit and re-enter: a carriage return, `.`, the command letter, and two spaces.
    ;; In: Y = the command letter
    ;; Also: ALTRIT (K4S79, HVK4)
    .proc StartLine
    tya
    pha
    jsr PrintCarriageReturn
    pla
    ldx #'.'
    jsr PrintPair
    jmp PrintTwoSpaces
    .endproc

    ; The commands.

    ;; `R`: prints the heading, then a `;` line of the saved program counter, interrupt vector and the five register
    ;; bytes, and goes back to the prompt.
    ;; Entry:
    ;;   PrintHeading = prints the heading's character at X
    ;; Also: DSPLYR (K4S79, HVK4)
    .proc DisplayRegisters
    ldx #$00

;; Prints the heading's character at X.
;; Also: D2 (K4S79, HVK4)
PrintHeading:
    lda RegisterHeading,x
    jsr KernalOutputCharacter
    inx
    cpx #HEADING_LENGTH
    bne PrintHeading
    ldy #';'
    jsr StartLine
    lda ProgramCounterHigh
    jsr PrintByte
    lda ProgramCounter
    jsr PrintByte
    jsr OutputSpace
    lda SavedIrqVectorHigh
    jsr PrintByte
    lda SavedIrqVector
    jsr PrintByte
    jsr SelectRegisters

    ; PrintBytes returns with zero set.
    jsr PrintBytes
    beq ToPrompt
    .endproc

    ;; `M`: reads a start and an end address and prints a `:` line of eight bytes for each start address up to the
    ;; end, stopping early for the `STOP` key or a wrap past $FFFF; then goes back to the prompt.
    ;; Entry:
    ;;   NextRow = checks `STOP`, the wrap and the end, then prints a row
    ;; Also: DSPLYM (K4S79, HVK4)
    .proc DisplayMemory
    jsr ReadCharacter
    jsr ReadAddress
    bcc ToShowError
    jsr SwapAddresses
    jsr ReadCharacter
    jsr ReadAddress
    bcc ToShowError
    jsr SwapAddresses

;; Stops for `STOP`, a wrap or an address past the end; otherwise prints a row of eight bytes.
;; Also: DSP1 (K4S79, HVK4)
NextRow:
    jsr KernalTestStopKey
    beq ToPrompt
    ldx MonitorAddressWrapped
    bne ToPrompt
    sec
    lda MonitorEndAddress
    sbc MonitorAddress
    lda MonitorEndAddress+1
    sbc MonitorAddress+1
    bcc ToPrompt
    ldy #':'
    jsr StartLine
    jsr PrintAddress
    lda #BYTES_PER_ROW
    jsr PrintBytes

    ; PrintBytes returns with zero set, so this always loops.
    beq NextRow
    .endproc

    ;; The bytes `M` shows on a line, and the most a `:` line alters.
    BYTES_PER_ROW = 8

;; Jumps on to <Monitor::Prompt>; the commands branch here.
;; Also: BEQS1 (K4S79, HVK4)
ToPrompt:
    jmp Prompt

;; Jumps on to <Monitor::ShowError>; the commands branch here.
;; Also: ERRS1 (K4S79, HVK4)
ToShowError:
    jmp ShowError

    ;; `;`: reads an edited register line: an optional program counter, an optional interrupt vector, then up to five
    ;; register bytes, and goes back to the prompt.
    ;;
    ;; It reads past the blank field after the command letter first, and past the space between the two addresses.
    ;; Entry:
    ;;   ReadVector = reads an optional interrupt vector
    ;;   AlterSaved = alters the five saved register bytes
    ;; Also: ALTR (K4S79, HVK4)
    .proc AlterRegisters
    jsr ReadByte
    jsr ReadAddress
    bcc ReadVector
    jsr SetProgramCounter

;; Reads the separating space and an optional interrupt vector.
;; Also: AL2 (K4S79, HVK4)
ReadVector:
    jsr KernalInputCharacter
    jsr ReadAddress
    bcc AlterSaved
    lda MonitorAddress
    sta SavedIrqVector
    lda MonitorAddress+1
    sta SavedIrqVectorHigh

;; Alters the five saved register bytes.
;; Also: AL3 (K4S79, HVK4)
AlterSaved:
    jsr SelectRegisters
    bne AlterBytes
    .endproc

    ;; `:`: reads an edited memory line, an address and up to eight bytes to store from it, and goes back to the
    ;; prompt.
    ;;
    ;; It reads past the blank field after the command letter first.
    ;; Also: ALTM (K4S79, HVK4)
    .proc AlterMemory
    jsr ReadByte
    jsr ReadAddress
    bcc ToShowError
    lda #BYTES_PER_ROW
    ; Falls into AlterBytes.
    .endproc

    ;; Alters up to A bytes from <MonitorAddress>, one per field read, until the count runs out; then goes back to the
    ;; prompt. A carriage return ends the line early, through <Monitor::ReadCharacter>.
    ;; In: A = the count, MonitorAddress = the first address
    ;; Entry:
    ;;   NextByte = alters the next byte
    ;;   Done = goes back to the prompt
    ;; Also: A4 (K4S79, HVK4)
    .proc AlterBytes
    sta MonitorCount

;; Reads the separating character and alters the next byte.
;; Also: A5 (K4S79, HVK4)
NextByte:
    jsr ReadCharacter
    jsr AlterByte
    bne NextByte

;; Goes back to the prompt.
;; Also: A9 (K4S79, HVK4)
Done:
    beq ToPrompt
    .endproc

    ;; `G`: resumes the program with the saved registers, at the saved program counter or, after a space, at an
    ;; address that follows.
    ;;
    ;; Basic4.mac spells it MGO. Commodore's kernal listing and its reconstruction (K4S79, HVK4) call it `GO`,
    ;; which BASIC 4 gives its `GO` statement, so their name is here in prose.
    ;; Entry:
    ;;   Resume = restores the saved stack pointer, interrupt vector and registers, and returns into the program
    ;; Also: MGO (UNKN)
    .proc Go
    jsr KernalInputCharacter
    cmp #CARRIAGE_RETURN
    beq Resume
    cmp #' '
    bne ToShowError
    jsr ReadAddress
    bcc Resume
    jsr SetProgramCounter

;; Restores the saved stack pointer, interrupt vector, status and registers, and returns into the program at the
;; saved program counter.
;; Also: G1 (K4S79, HVK4)
Resume:
    ldx SavedStackPointer
    txs
    sei
    lda SavedIrqVectorHigh
    sta IrqVector+1
    lda SavedIrqVector
    sta IrqVector
    lda ProgramCounterHigh
    pha
    lda ProgramCounter
    pha
    lda SavedStatus
    pha
    lda SavedA
    ldx SavedX
    ldy SavedY
    rti
    .endproc

    ;; `X`: restores the saved stack pointer and goes back to BASIC's <ReadyForCommand>.
    ;; Also: EXIT (K4S79, HVK4)
    .proc Exit
    ldx SavedStackPointer
    txs
    jmp ReadyForCommand
    .endproc

;; Jumps on to <Monitor::ShowError>, within branch range of <Monitor::LoadOrSave>'s checks.
;; Also: ERRL (K4S79, HVK4)
LoadOrSaveFail:
    jmp ShowError

    ;; `L` and `S`: reads `"name",device` and, for `S`, `,start,end`, then loads from or saves to the device; then
    ;; goes back to the prompt.
    ;;
    ;; The name may be left out, and has at most 15 characters: the 16th fails. The device defaults to 1, the first
    ;; cassette; 0 (the keyboard) and 3 (the screen) are refused. `L` takes no addresses and `S` needs them; a load
    ;; that sets <STATUS_LOAD_ERROR> in <IoStatus> fails. A failure shows `?`. Many of the labels are branches that
    ;; relay a failure to <Monitor::LoadOrSaveFail> out of range, while testing something themselves.
    ;; Entry:
    ;;   SkipSpaces = skips spaces before the name
    ;;   ToFail = fails unless zero is set
    ;;   NextNameCharacter = reads the next character of the name
    ;;   CheckLength = fails at the name's 16th character
    ;;   Perform = loads, for `L`, when the line ends
    ;;   RequireLoad = fails unless zero is set
    ;;   CheckLoadError = fails on a load error, else goes back to the prompt
    ;;   AfterName = reads a carriage return or a comma and the device
    ;;   RequireComma = fails unless zero is set
    ;;   RejectKeyboard = fails for device 0
    ;;   RejectScreen = fails for device 3
    ;;   ReadStart = reads the start address
    ;;   ReadEnd = reads the end address
    ;;   SkipTrailingSpaces = skips spaces after the end address
    ;;   RequireSave = saves, for `S`
    ;; Also: LD (K4S79, HVK4)
    .proc LoadOrSave
    ; The cassette, then one less for the zeros below.
    .assert DEVICE_CASSETTE = 1, "LoadOrSave's dey makes zero from the cassette's device number."
    ldy #DEVICE_CASSETTE
    sty DeviceNumber
    dey
    sty FilenameLength
    sty IoStatus
    sty LoadVerifyFlag
    lda #>MonitorFilename
    sta FilenamePointer+1
    lda #<MonitorFilename
    sta FilenamePointer

;; Skips spaces; the line may end, or a quoted name follow.
;; Also: L1 (K4S79, HVK4)
SkipSpaces:
    jsr KernalInputCharacter
    cmp #' '
    beq SkipSpaces
    cmp #CARRIAGE_RETURN
    beq Perform
    cmp #'"'

;; Fails unless the character tested is the one expected.
;; Also: L2 (K4S79, HVK4)
ToFail:
    bne LoadOrSaveFail

;; Reads a character of the name, up to the closing quote or the line's end.
;; Also: L3 (K4S79, HVK4)
NextNameCharacter:
    jsr KernalInputCharacter
    cmp #'"'
    beq AfterName
    cmp #CARRIAGE_RETURN
    beq Perform
    sta (FilenamePointer),y
    inc FilenameLength
    iny
    cpy #FILENAME_LIMIT

;; Fails when the name reaches 16 characters, else reads on.
;; Also: L4 (K4S79, HVK4)
CheckLength:
    beq LoadOrSaveFail
    bne NextNameCharacter

;; At the line's end: only `L` may stop here; loads, and fails on a load error.
;; Also: L5 (K4S79, HVK4)
Perform:
    lda MonitorCommandIndex
    cmp #LOAD_COMMAND

;; Fails unless the command is `L`.
;; Also: L6 (K4S79, HVK4)
RequireLoad:
    bne ToFail
    jsr KernalMonitorLoad
    jsr KernalWaitForTape
    lda IoStatus
    and #STATUS_LOAD_ERROR

;; Fails on a load error, else goes back to the prompt.
;; Also: L7 (K4S79, HVK4)
CheckLoadError:
    bne RequireLoad
    jmp Prompt

;; After the name: the line ends, or a comma and the device follow.
;; Also: L8 (K4S79, HVK4)
AfterName:
    jsr KernalInputCharacter
    cmp #CARRIAGE_RETURN
    beq Perform
    cmp #','

;; Fails unless a comma follows.
;; Also: L9 (K4S79, HVK4)
RequireComma:
    bne CheckLoadError
    jsr ReadByte
    and #$0F

;; Fails for device 0, the keyboard.
;; Also: L10 (K4S79, HVK4)
RejectKeyboard:
    beq CheckLength
    cmp #DEVICE_SCREEN

;; Fails for device 3, the screen.
;; Also: L11 (K4S79, HVK4)
RejectScreen:
    beq RejectKeyboard
    sta DeviceNumber
    jsr KernalInputCharacter
    cmp #CARRIAGE_RETURN
    beq Perform
    cmp #','

;; Fails unless a comma follows; reads the start address into <MonitorEndAddress>.
;; Also: L12 (K4S79, HVK4)
ReadStart:
    bne RequireComma
    jsr ReadAddress
    jsr SwapAddresses
    jsr KernalInputCharacter
    cmp #','

;; Fails unless a comma follows; reads the end address into <EndAddress>, and the start back into
;; <MonitorAddress>.
;; Also: L13 (K4S79, HVK4)
ReadEnd:
    bne ReadStart
    jsr ReadAddress
    lda MonitorAddress
    sta EndAddress
    lda MonitorAddress+1
    sta EndAddressHigh
    jsr SwapAddresses

;; Skips spaces after the end address, up to the line's end.
;; Also: L20 (K4S79, HVK4)
SkipTrailingSpaces:
    jsr KernalInputCharacter
    cmp #' '
    beq SkipTrailingSpaces
    cmp #CARRIAGE_RETURN

;; Fails unless the line ends and the command is `S`; saves.
;; Also: L14 (K4S79, HVK4)
RequireSave:
    bne ReadEnd
    lda MonitorCommandIndex
    cmp #SAVE_COMMAND
    bne RequireSave
    jsr KernalMonitorSave
    jmp Prompt
    .endproc

    ;; The device `L` and `S` use when none is given: the first cassette.
    DEVICE_CASSETTE = 1

    ;; The screen, a device `L` and `S` refuse.
    DEVICE_SCREEN = 3

    ;; The filename length at which `L` and `S` fail, so a name has at most 15 characters.
    FILENAME_LIMIT = 16

    ; Printing and reading hexadecimal.

    ;; Prints <MonitorAddress> as four hexadecimal digits.
    ;; Entry:
    ;;   PrintHigh = prints the byte at X, then the one below it
    ;; Also: WROA (K4S79, HVK4)
    .proc PrintAddress
    ldx #$01

;; Prints the address's high byte, keeping the low one for <Monitor::PrintByte>.
;; Also: WROA1 (K4S79, HVK4)
PrintHigh:
    lda MonitorAddress-1,x
    pha
    lda MonitorAddress,x
    jsr PrintByte
    pla
    ; Falls into PrintByte.
    .endproc

    ;; Prints A as two hexadecimal digits.
    ;; In: A = the byte
    ;; Also: WROB (K4S79, HVK4)
    .proc PrintByte
    pha
    lsr a
    lsr a
    lsr a
    lsr a
    jsr HexDigit
    tax
    pla
    and #$0F
    jsr HexDigit
    ; Falls into PrintPair.
    .endproc

    ;; Prints the character in X, then the one in A.
    ;; In: X = the first character, A = the second
    ;; Also: WRTWO (K4S79, HVK4)
    .proc PrintPair
    pha
    txa
    jsr KernalOutputCharacter
    pla
    jmp KernalOutputCharacter
    .endproc

    ;; Converts a nibble to its hexadecimal digit, 0 to 9 or A to F.
    ;; In: A = the nibble, 0 to 15
    ;; Out: A = the digit's character, carry = set for 0 to 9
    ;; Keeps: X, Y
    ;; Entry:
    ;;   Digit = adds the base of the digits
    ;; Also: ASCII (K4S79, HVK4)
    .proc HexDigit
    clc
    adc #$F6
    bcc Digit
    adc #$06

;; Adds the base of the digits: `0` for 0 to 9, or, after the adjustment above, `A` for 10 to 15.
;; Also: ASC1 (K4S79, HVK4)
Digit:
    adc #$3A
    rts
    .endproc

    ;; Exchanges <MonitorAddress> and <MonitorEndAddress>.
    ;; Out: X = 0, zero = set
    ;; Keeps: Y
    ;; Entry:
    ;;   NextByte = exchanges the bytes at X - 1
    ;; Also: T2T2 (K4S79, HVK4)
    .proc SwapAddresses
    ldx #$02

;; Exchanges the two addresses' bytes at X - 1.
;; Also: T2T21 (K4S79, HVK4)
NextByte:
    lda MonitorAddress-1,x
    pha
    lda MonitorEndAddress-1,x
    sta MonitorAddress-1,x
    pla
    sta MonitorEndAddress-1,x
    dex
    bne NextByte
    rts
    .endproc

    ;; Reads two hexadecimal fields into <MonitorAddress>, high byte first; a blank field leaves its byte as it was.
    ;; Out: carry = set when the low byte was given
    ;; Entry:
    ;;   LowByte = reads the low byte
    ;;   Done = returns
    ;; Also: RDOA (K4S79, HVK4)
    .proc ReadAddress
    jsr ReadByte
    bcc LowByte
    sta MonitorAddress+1

;; Reads the low byte.
;; Also: RDOA2 (K4S79, HVK4)
LowByte:
    jsr ReadByte
    bcc Done
    sta MonitorAddress

;; Returns.
;; Also: RDEXIT (K4S79, HVK4)
Done:
    rts
    .endproc

    ;; Reads a hexadecimal field: two digits, or a space and one digit, or two spaces for a blank field.
    ;;
    ;; It does not check the digits: <Monitor::HexValue> converts whatever it reads.
    ;; Out: A = the byte and carry = set, or A = a space and carry = clear for a blank field;
    ;;   MonitorHexByte = the high digit times 16, or 0
    ;; Entry:
    ;;   CheckBlank = tests the first character for a space
    ;;   HighDigit = reads the high digit and then the low one
    ;;   LowDigit = converts the low digit and combines it with the high one
    ;; Also: RDOB (K4S79, HVK4)
    .proc ReadByte
    lda #$00
    sta MonitorHexByte
    jsr ReadCharacter

;; Tests the first character for a space.
;; Also: RDOB1 (K4S79, HVK4)
CheckBlank:
    cmp #' '
    bne HighDigit
    jsr ReadCharacter
    cmp #' '
    bne LowDigit
    clc
    rts

;; Converts the high digit and reads the low one.
;; Also: RDOB2 (K4S79, HVK4)
HighDigit:
    jsr HexValue
    asl a
    asl a
    asl a
    asl a
    sta MonitorHexByte
    jsr ReadCharacter

;; Converts the low digit and combines it with the high one.
;; Also: RDOB3 (K4S79, HVK4)
LowDigit:
    jsr HexValue
    ora MonitorHexByte
    sec
    rts
    .endproc

    ;; Converts a hexadecimal digit to its value, without checking it.
    ;; In: A = `0` to `9` or `A` to `F`
    ;; Out: A = the value, 0 to 15, carry = clear
    ;; Keeps: X, Y
    ;; Also: HEXIT (K4S79, HVK4)
    .proc HexValue
    cmp #'9' + 1
    php
    and #$0F
    plp
    bcc Return
    adc #$08
    ; Falls into Return.
    .endproc

;; Returns, for <Monitor::HexValue> and <Monitor::ReadCharacter>.
;; Also: HEX09 (K4S79, HVK4)
Return:
    rts

    ;; Reads a character from the screen editor's line, abandoning the command for the prompt at the line's end.
    ;;
    ;; At a carriage return it discards only its own return address before going to <Monitor::Prompt>, which does
    ;; not reset the stack pointer, so a line that ends inside a nested read leaves the callers' return addresses on
    ;; the stack.
    ;; Out: A = the character, not a carriage return, zero = clear
    ;; Also: RDOC (K4S79, HVK4)
    .proc ReadCharacter
    jsr KernalInputCharacter
    cmp #CARRIAGE_RETURN
    bne Return
    pla
    pla
    jmp Prompt
    .endproc

    ;; Prints `?` and goes back to the prompt.
    ;; Also: ERROPR (K4S79, HVK4)
    .proc ShowError
    lda #'?'
    jsr KernalOutputCharacter
    jmp Prompt
    .endproc

    .endscope
.endmacro
