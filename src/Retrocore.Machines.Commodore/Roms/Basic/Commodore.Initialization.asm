; retrocore: style=strict
; COMMODORE BASIC: COLD START AND RAM DISCOVERY
;
; ColdStart spans three macros: CommodoreInitialize opens it, CommodoreMemoryProbe continues it and
; CommodoreStartProgram closes it. A root emits them one after another.

;; Emits the start of <ColdStart>, which it opens: the workspace setup at the start of cold initialization.
;; Parameters: markDirect = 1 to mark the current line as direct,
;;   setLineWidth = 1 to initialize the terminal width and comma zones,
;;   delayedSize = 1 to set the descriptor size after clearing the flags,
;;   localPosition = 1 to initialize BASIC's terminal position,
;;   bufferPage = zero for a page-zero buffer, or the nonzero buffer page,
;;   diskStatus = 1 to initialize the disk-status descriptor instead of the output-suppression flag,
;;   earlyBuffer = 1 to restore the page-zero buffer's comma and print a newline
.macro CommodoreInitialize markDirect, setLineWidth, delayedSize, localPosition, bufferPage, diskStatus, earlyBuffer
    .assert markDirect = 0 || markDirect = 1, "markDirect is 0 or 1."
    .assert setLineWidth = 0 || setLineWidth = 1, "setLineWidth is 0 or 1."
    .assert delayedSize = 0 || delayedSize = 1, "delayedSize is 0 or 1."
    .assert localPosition = 0 || localPosition = 1, "localPosition is 0 or 1."
    .assert bufferPage >= 0 && bufferPage <= 255, "bufferPage must fit in a byte."
    .assert diskStatus = 0 || diskStatus = 1, "diskStatus is 0 or 1."
    .assert earlyBuffer = 0 || earlyBuffer = 1, "earlyBuffer is 0 or 1."

    ;; Cold-starts BASIC: sets the stack and the `USR` vector, copies the character reader, clears the workspace, finds
    ;; the top of memory, prints the sign-on and the free bytes, and enters <ReadyForCommand>.
    ;;
    ;; Where `markDirect` is 1 (BASIC 1), it marks the line number as direct. The memory probe that
    ;; <CommodoreMemoryProbe> emits next establishes BASIC's limit, and <CommodoreStartProgram> ends the routine.
    ;; Also: INIT (M6502, CBM4S79, K4S79, HV1, HV1R, HV2, HV4, HV4R, HVK4)
    .proc ColdStart
    ldx #<(STACK_END-$100)
    .if markDirect
        stx CurrentLine+1
    .endif
    txs
    lda #$4C                        ; the JMP opcode for the vectors
    sta FunctionJump
    sta UserVector
    lda #<IllegalQuantityError
    ldy #>IllegalQuantityError
    sta UserVector+1
    sty UserVector+2
    .if setLineWidth
        lda #LINE_LENGTH
        sta LineWidth
        lda #LAST_COMMA_COLUMN
        sta LastCommaColumn
    .endif
    ldx #<(RandomValue+4-GetNextCharacter)

;; Copies the character reader and the random seed to page zero.
;; Also: MOVCHG (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
CopyCharacterReader:
    lda CharacterReaderTemplate-1,x
    sta GetNextCharacter-1,x
    dex
    bne CopyCharacterReader
    .if .not delayedSize
        lda #DESCRIPTOR_SIZE
        sta CollectorStep
    .endif
    txa
    sta ShiftFill
    sta CurrentChannel
    sta LastTemporary+1
    .if NULL_COMMAND
        sta NullCount
    .endif
    .if localPosition
        sta TerminalPosition
    .endif
    .if diskStatus
        sta DiskStatusDescriptor
        pha
    .else
        pha
        sta OutputSuppressed
    .endif
    .if delayedSize
        lda #DESCRIPTOR_SIZE
        sta CollectorStep
    .endif
    .if earlyBuffer
        lda #','
        sta LineNumber+1
        jsr PrintNewline
    .endif
    .if bufferPage
        inx                         ; the bytes before the buffer nonzero, for the line chaining
        stx InputBuffer-3
        stx InputBuffer-4
    .endif
    ldx #TemporaryDescriptors
    stx NextTemporary
.endmacro

;; Emits <ColdStart>'s RAM probe, which saves the upper memory limit it finds.
;; Parameters: explicitZero = 1 to load zero before setting the initial RAM address,
;;   explicitIndex = 1 to load zero into Y instead of copying A,
;;   saveProgramStart = 1 to initialize <ProgramStart> before probing,
;;   diskFallback = 1 to retain BASIC 4's unreachable ROM-location fallback,
;;   screenStop = 1 for the early screen-boundary check,
;;   probeByte = first value written when testing RAM
.macro CommodoreMemoryProbe explicitZero, explicitIndex, saveProgramStart, diskFallback, screenStop, probeByte
    .assert explicitZero = 0 || explicitZero = 1, "explicitZero is 0 or 1."
    .assert explicitIndex = 0 || explicitIndex = 1, "explicitIndex is 0 or 1."
    .assert saveProgramStart = 0 || saveProgramStart = 1, "saveProgramStart is 0 or 1."
    .assert diskFallback = 0 || diskFallback = 1, "diskFallback is 0 or 1."
    .assert screenStop = 0 || screenStop = 1, "screenStop is 0 or 1."
    .assert probeByte >= 0 && probeByte <= 255, "probeByte must fit in a byte."

    .if explicitZero
        lda #$00
    .endif
    ldy #>RAM_ORIGIN
    .if saveProgramStart
        sta ProgramStart
        sty ProgramStart+1
    .endif
    sta LineNumber
    sty LineNumber+1
    .if explicitIndex
        ldy #$00
    .else
        tay
    .endif
    .if diskFallback
        lda #$80                    ; nonzero, so the branch is always taken
        bne ProbeMemory
        lda #<ROMLOC
        ldy #>ROMLOC
        jmp SetMemoryTop
    .endif

;; Steps to the next address, stopping at the screen's $8000.
;; Also: LOOPMM (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
ProbeMemory:
    inc LineNumber
    bne TestByte
    inc LineNumber+1
    .if screenStop
        lda LineNumber+1
        cmp #$80                    ; the screen's page
        beq FoundMemoryTop
    .else
        bmi FoundMemoryTop
    .endif

;; Writes and checks the probe byte and its shift; a mismatch ends the probe.
;; Also: LOOPM1 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
TestByte:
    lda #probeByte
    sta (LineNumber),y
    cmp (LineNumber),y
    bne FoundMemoryTop
    asl a
    sta (LineNumber),y
    cmp (LineNumber),y
    beq ProbeMemory

;; Takes the failing address as the top of memory.
;; Also: USEDEC (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
FoundMemoryTop:
    lda LineNumber
    ldy LineNumber+1

;; Sets <MemoryTop> and <StringsBottom> from A and Y.
;; Also: USEDEF (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
SetMemoryTop:
    sta MemoryTop
    sty MemoryTop+1
    sta StringsBottom
    sty StringsBottom+1
.endmacro

;; Emits the end of <ColdStart>, which it closes: the empty program's setup and the sign-on. Microsoft's ASKAGN
;; shares the address of its first label, and no document gives it here.
;; Parameters: reloadProgramStart = 1 to load the initial program address again,
;;   carryProgramStart = 1 to carry an increment into its high byte,
;;   checkRoom = 1 to call <CheckFreeMemory>,
;;   carriageFirst = 1 to print a carriage return instead of a separate sign-on,
;;   banner = sign-on string when carriageFirst is 0
.macro CommodoreStartProgram reloadProgramStart, carryProgramStart, checkRoom, carriageFirst, banner
    .assert reloadProgramStart = 0 || reloadProgramStart = 1, "reloadProgramStart is 0 or 1."
    .assert carryProgramStart = 0 || carryProgramStart = 1, "carryProgramStart is 0 or 1."
    .assert checkRoom = 0 || checkRoom = 1, "checkRoom is 0 or 1."
    .assert carriageFirst = 0 || carriageFirst = 1, "carriageFirst is 0 or 1."
    .assert carryProgramStart = 0 || checkRoom = 1, "The carry branch needs the room-check entry."

;; Puts the zero before the first line and advances <ProgramStart> past it; nothing branches here, and the label is
;; kept for its old name.
;; Also: TTYW (M6502)
StartProgram:
    .if reloadProgramStart
        ldx #<RAM_ORIGIN
        ldy #>RAM_ORIGIN
        stx ProgramStart
        sty ProgramStart+1
    .endif
    ldy #$00
    tya
    sta (ProgramStart),y
    inc ProgramStart
    .if carryProgramStart
        bne CheckRoom
        inc ProgramStart+1
    .endif
    .if checkRoom

;; Checks room for the program from <ProgramStart>.
;; Also: QROOM (M6502), INIT20 (HV1, HV1R)
CheckRoom:
        lda ProgramStart
        ldy ProgramStart+1
        jsr CheckFreeMemory
    .endif
    .if carriageFirst
        jsr PrintNewline
    .else
        lda #<banner
        ldy #>banner
        jsr PrintText
    .endif
    lda MemoryTop
    sec
    sbc ProgramStart
    tax
    lda MemoryTop+1
    sbc ProgramStart+1
    jsr Float::PrintDecimalAX
    lda #<BytesFreeMessage
    ldy #>BytesFreeMessage
    jsr PrintText
    jsr EraseProgram
    jmp ReadyForCommand
    .endproc
.endmacro

;; The screen's home code, which BASIC 1's sign-on starts with.
CURSOR_HOME = $13

;; The screen's cursor-down code, which ends BASIC 1's sign-on.
CURSOR_DOWN = $11

;; Emits the startup messages, <BytesFreeMessage> and <SignOnMessage>.
;; Parameters: earlyBanner = 1 for BASIC 1's home-and-cursor-down sign-on
.macro CommodoreStartMessages earlyBanner
    .assert earlyBanner = 0 || earlyBanner = 1, "earlyBanner is 0 or 1."

;; The free-memory count's suffix, `BYTES FREE`. BASIC 2 and 4 end it with a carriage return; BASIC 1 goes on, in
;; the same string, with the cursor home, its sign-on and three cursor-downs.
;; Also: WORDS (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
BytesFreeMessage:
    .byte " BYTES FREE"
    .if earlyBanner

;; BASIC 1's sign-on, which goes on from <BytesFreeMessage> in the same string.
;; Also: FREMES (HV1, HV1R)
SignOnMessage:
        .byte CURSOR_HOME, "*** COMMODORE BASIC ***", CURSOR_DOWN, CURSOR_DOWN, CURSOR_DOWN, $00
    .else
        .byte CARRIAGE_RETURN, $00

;; The sign-on BASIC 2 prints before the free-memory count; BASIC 4 assembles it but prints its own `SIGNON`.
;; Also: FREMES (M6502, CBM4S79, HV2, HV4, HV4R)
SignOnMessage:
        .byte "### COMMODORE BASIC ###", CARRIAGE_RETURN, CARRIAGE_RETURN, $00
    .endif
.endmacro
