; retrocore: style=strict
;; The Monitor's text-mode, hook, `BASIC`, G, cassette and register routines, and the commands between them
;; ($FE75-$FF58).

; Text modes: the masks <INVFLG> holds. The normal one, TEXT_NORMAL, is in Monitor.asm.

;; <INVFLG> for inverse text: printable characters lose bits 6 and 7.
TEXT_INVERSE = $3F

; Hooks.

;; The bits of <A2L> that hold the slot number for `PR#` and `IN#`.
SLOT_NUMBER_MASK = $0F

; The internal firmware's functions, the numbers in Y for <CallFirmware>.

;; Runs the mini-assembler for a line: the Enhanced IIe's "!" command.
FIRMWARE_MINI_ASSEMBLER = $0D

;; Finishes a hook that <SetHook> stored: the Enhanced IIe's page for slot 0, and the 80-column firmware's hooks.
FIRMWARE_SET_HOOK = $0E

; Cassette lengths and timing. A header tone is a count of 256 half cycles of about 650 microseconds. The other
; values are Y's starting count for the next bit's timing, which differs from the count between bits within a
; byte to make up for the instructions that run between bytes.

;; The header tone <WriteCassette> writes before the data: about 10 seconds.
WRITE_HEADER_LENGTH = $40

;; How long <ReadCassette> lets the header play, as a header length, once it hears the tape: about 3.5 seconds.
READ_HEADER_DELAY = $16

;; The count before the first data byte <WriteCassette> writes.
WRITE_FIRST_COUNT = $27

;; The count before each later data byte.
WRITE_NEXT_COUNT = $1D

;; The count before the checksum byte.
WRITE_CHECKSUM_COUNT = $22

;; The half cycles <WriteCassette> writes for a byte: two for each bit, each counting X down once.
HALF_CYCLES_PER_BYTE = 16

;; The count that tells the sync bit from the header: a half cycle that ends before the bit reader counts Y down
;; past 0 from here is the sync bit's, and the header's are longer.
READ_SYNC_COUNT = $24

;; The count before the first data byte <ReadCassette> reads.
READ_FIRST_COUNT = $3B

;; The count before each later byte.
READ_NEXT_COUNT = $35

; How <ReadHexNumber> returns the character that ends a number: (character EOR "0") + KEY_CODE_OFFSET.

;; Added to a character EOR "0" when it is not a decimal digit, so that "A" to "F" become $FA to $FF and the
;; command characters the codes <Commands::Keys> holds.
KEY_CODE_OFFSET = $89

;; An apostrophe, with its high bit set.
KEY_QUOTE = $A7

;; The code of an apostrophe, which on the Enhanced IIe makes the character after it a number: 'A is $C1.
QUOTE_CODE = ((KEY_QUOTE ^ '0') + KEY_CODE_OFFSET) & $FF

;; Sets PC to A1 when the command gave an address: G, L and the Apple II Monitor's S.
;;
;; At $FE75.
;; In: X = 1 when the command gave an address, 0 when not, A1L/A1H = the address
;; Out: PCL/PCH = A1 when X was 1, X = $FF when it was
;; Keeps: Y
;; Entry:
;;   Loop = copies X + 1 bytes of A1 to PC: X = 1 for both
;; Also: A1PC (A2RM78, A2RM79, IIEROM82)
.proc SetPcFromA1
.assert * = $FE75, "SetPcFromA1 must stay at $FE75."
    txa
    beq Done

;; Copies X + 1 bytes of A1 to PC: X = 1 for both.
;;
;; $FE78 in every build, which the Enhanced IIe's mini-assembler calls.
;; In: X = the index of the last byte
;; Out: X = $FF
;; Also: A1PCLP (A2RM78, IIEROM82)
Loop:
.assert * = $FE78, "SetPcFromA1::Loop must stay at $FE78, where the Enhanced IIe's firmware calls it."
    lda A1L,x
    sta PCL,x
    dex
    bpl Loop

;; The return.
;; Also: A1PCRTS (A2RM78, A2RM79, IIEROM82, IIETRM85)
Done:
    rts
.endproc

;; I: sets inverse text.
;;
;; At $FE80.
;; Out: Y = <INVFLG>
;; Keeps: A, X
;; Also: SETINV (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc SetInverse
.assert * = $FE80, "SetInverse must stay at $FE80."
    ldy #TEXT_INVERSE
    bne SetNormal::Store
.endproc

;; N: sets normal text.
;;
;; At $FE84.
;; Out: Y = <INVFLG>
;; Keeps: A, X
;; Entry:
;;   Store = sets <INVFLG> to Y
;; Also: SETNORM (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc SetNormal
.assert * = $FE84, "SetNormal must stay at $FE84."
    ldy #TEXT_NORMAL

;; Sets <INVFLG> to Y.
;; In: Y = the mask
;; Also: SETIFLG (A2RM78, A2RM79, IIEROM82, IIETRM85)
Store:
    sty INVFLG
    rts
.endproc

;; Sets the input hook to the keyboard, <KeyboardIn>.
;;
;; At $FE89.
;; Also: SETKBD (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc SetKeyboard
.assert * = $FE89, "SetKeyboard must stay at $FE89."
    lda #0
    ; Falls into SetInput.
.endproc

;; Sets the input hook to a slot's ROM, $Cn00, or for slot 0 to the keyboard: `IN#`.
;;
;; At $FE8B.
;; In: A = the slot, in bits 0-3
;; Entry:
;;   FromA2 = control-K: sets the input hook to the slot in <A2L>, the number before it
;; Also: INPORT (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc SetInput
.assert * = $FE8B, "SetInput must stay at $FE8B."
    sta A2L

;; Control-K: sets the input hook to the slot in <A2L>, the number before it.
;; In: A2L = the slot
;; Also: INPRT (A2RM78, A2RM79, IIEROM82, IIETRM85)
FromA2:
    ldx #KSWL
    ldy #<KeyboardIn
    bne SetHook
.endproc

;; Sets the output hook to the screen, <ScreenOut>.
;;
;; At $FE93.
;; Also: SETVID (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc SetScreen
.assert * = $FE93, "SetScreen must stay at $FE93."
    lda #0
    ; Falls into SetOutput.
.endproc

;; Sets the output hook to a slot's ROM, $Cn00, or for slot 0 to the screen: `PR#`.
;;
;; At $FE95.
;; In: A = the slot, in bits 0-3
;; Entry:
;;   FromA2 = control-P: sets the output hook to the slot in <A2L>, the number before it
;; Also: OUTPORT (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc SetOutput
.assert * = $FE95, "SetOutput must stay at $FE95."
    sta A2L

;; Control-P: sets the output hook to the slot in <A2L>, the number before it.
;; In: A2L = the slot
;; Also: OUTPRT (A2RM78, A2RM79, IIEROM82, IIETRM85)
FromA2:
    ldx #CSWL
    ldy #<ScreenOut
    ; Falls into SetHook.
.endproc

; The keyboard's and the screen's routines share a page, which SetHook stores for slot 0 (on the Enhanced IIe, the
; firmware's function $0E stores it).
.assert >KeyboardIn = >ScreenOut, "KeyboardIn and ScreenOut must share a page."

;; Sets the hook at X to the ROM of the slot in <A2L>, $Cn00, or for slot 0 to the Monitor's routine whose low byte
;; is in Y.
;;
;; At $FE9B. For slot 0 the Apple II's Monitors and the original IIe store the page of the Monitor's keyboard and
;; screen routines. The Enhanced IIe stores a high byte of 0 instead, and the internal firmware's function $0E puts
;; in the page: it turns the 80-column firmware off first when it is on, but keeps input at slot 3 while output goes
;; there.
;; In: X = the hook's address in page zero, <CSWL> or <KSWL>, Y = the Monitor routine's low byte, A2L = the slot
;; Also: IOPRT (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc SetHook
.assert * = $FE9B, "SetHook must stay at $FE9B."
    lda A2L
    and #SLOT_NUMBER_MASK
.if ENHANCED
    beq Store
.else
    beq Default
.endif

    ; A slot: $Cn00.
    ora #SLOT_ROM_PAGE
    ldy #0
.if .not ENHANCED
    beq Store

;; Slot 0: the page of the Monitor's keyboard and screen routines.
;; Also: IOPRT1 (A2RM78, A2RM79, IIEROM82)
Default:
    lda #>ScreenOut
.endif

;; Stores the hook, which on the Enhanced IIe the firmware then finishes.
;; Also: IOPRT2 (A2RM78, A2RM79, IIEROM82)
Store:
    sty LOC0,x
    sta LOC1,x
.if ENHANCED
    ldy #FIRMWARE_SET_HOOK
    jmp CallFirmware
.else
    rts
.endif
.endproc

    ; An unused byte.
    .byte $EA

;; A byte no code runs: $D1 on the original IIe, $00 on the Enhanced IIe, and an unused $EA on the Apple II's.
;;
;; At $FEAF. Its IIe name says it is there to make the ROM's checksum come out right. On the original IIe, the
;; self-test's second ROM checksum (<Firmware:ROMSUM2@Original>) adds $E000-$FFFF, this byte among them, and compares
;; the sum with the byte at $F7FF.
;; Also: CKSUMFIX (IIEROM82, IIETRM85)
ChecksumFix:
.assert * = $FEAF, "ChecksumFix must stay at $FEAF."
.if ENHANCED
    .byte $00
.elseif MONITOR = MONITOR_IIE
    .byte $D1
.else
    .byte $EA
.endif

; Commands: the BASIC, G, Control-E, T and S handlers, after the hook routines.
.scope Commands continued

;; Control-B: starts `BASIC` from scratch, clearing its program.
;;
;; $E000 starts whichever `BASIC` the machine's ROMs hold, Integer `BASIC` or Applesoft.
;; Also: XBASIC (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc StartBasic
    jmp BasicColdStart
.endproc

;; Control-C: continues `BASIC`, keeping its program.
;; Also: BASCONT (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc ContinueBasic
    jmp BasicWarmStart
.endproc

;; G: restores the registers and runs the program at A1, or at PC when the command gave no address.
;;
;; The program returns to the command line with rts.
;; In: X = 1 when the command gave an address, 0 when not, A1L/A1H = the address
;; Also: GO (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc Go
    jsr SetPcFromA1
    jsr RestoreRegisters
    jmp (PCL)
.endproc

;; Control-E: shows the saved registers (<ShowRegisters>), from page $FE, where every handler must be.
;; Also: REGZ (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc Registers
    jmp ShowRegisters
.endproc
.if MONITOR = MONITOR_II

;; T: traces the program without end, from A1 when the command gave an address, showing each instruction and
;; the registers.
;;
;; It moves <YSAV> back onto the T, so that after each step (<Commands::Step>, which it falls into) the command
;; line runs the T again. A BRK in the program, or reset, stops it.
;; Also: TRACE (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc Trace
    dec YSAV
    ; Falls into Step.
.endproc

;; S: runs one instruction, at A1 when the command gave an address, and shows it and the registers.
;;
;; <RunInstruction at Stepper::RunInstruction> runs it.
;; In: X = 1 when the command gave an address, 0 when not, A1L/A1H = the address
;; Also: STEPZ (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc Step
    jsr SetPcFromA1
    jmp Stepper::RunInstruction
.endproc
.else

;; Does nothing: what is left of the Apple II Monitor's T command, which traced a program.
;;
;; Its entry in the key table is a Control-Y that a later Control-Y entry hides; the Enhanced IIe gave the
;; entry to the "!" command.
;; Also: TRACE (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc Trace
    rts

    ; An unused byte.
    .byte $EA
.endproc

;; Does nothing: what is left of the Apple II Monitor's S command, which stepped a program.
;;
;; Its entry in the key table became the last Control-Y, which wins: in the Autostart Monitor it points at the
;; five NOPs after the rts, which run into <Commands::User>, and in the original IIe at the text that replaced
;; them (<Commands::UserText>), which runs into it too. The
;; Enhanced IIe gave the entry to its own S command, which searches memory.
;; Also: STEPZ (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc Step
    rts
.if MONITOR = MONITOR_AUTOSTART

    ; The Control-Y entry: five NOPs into User.
    nop
    nop
    nop
    nop
    nop
.endif
.endproc
.if MONITOR = MONITOR_IIE && .not ENHANCED

;; Control-Y on the original IIe: the text "Bryan", whose bytes run as code and fall into <Commands::User>.
;;
;; The key table's last Control-Y entry, left from the S command, points here and wins, since <CommandLine>
;; searches from the end. $C2 $F2 is a two-byte NOP, an undocumented opcode of the NMOS 6502, and $F9 $E1 $EE is
;; SBC $EEE1,Y, which changes A and the flags; nothing else changes.
;; Also: SLOTRTS (UNKN)
.proc UserText
    .byte "Bryan"
    ; Falls into User.
.endproc
.endif
.endif

.endscope
.if ENHANCED

;; Switches slot ROM in at $C100-$CFFF and returns: the way back from the internal firmware.
;;
;; $FEC5 on the Enhanced IIe. The firmware returns through it, or through its rts at $FEC8 when the internal ROM
;; was in before the call; <WriteHeader at Cassette::WriteHeader> does too.
;; Entry:
;;   Done = the return, which the firmware jumps to at $FEC8
;; Also: SLOTRTS (UNKN)
.proc SelectSlotRom
.assert * = $FEC5, "SelectSlotRom must stay at $FEC5, where the firmware returns through it."
    sta SETSLOTCXROM

;; The return, which the firmware jumps to at $FEC8.
Done:
.assert * = $FEC8, "SelectSlotRom::Done must stay at $FEC8, where the firmware jumps to it."
    rts

    ; An unused byte.
    .byte $EA
.endproc
.endif

; Commands: the Control-Y handler, after the Enhanced IIe's SelectSlotRom.
.scope Commands continued

;; Control-Y: runs the user's routine, through the jump a program puts at <USRADR>.
;; Also: USR (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc User
    jmp USRADR
.endproc

.endscope
.if ENHANCED

;; W: writes the bytes from A1 to A2 to the cassette, with the internal firmware's routine.
;;
;; At $FECD. Integer `BASIC` calls $FECF, after the lda, with its own header length in A.
;; In: A1L/A1H = the first address, A2L/A2H = the last
;; Also: WRITE (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc WriteCassette
.assert * = $FECD, "WriteCassette must stay at $FECD."
    lda #WRITE_HEADER_LENGTH
    sta SETINTCXROM
    jsr WRITETAPE

    ; WRITETAPE returns with zero set, so this always beeps.
    beq ReadCassette::Finish
.endproc
.else

;; W: writes the bytes from A1 to A2 to the cassette: a header tone, the bytes, then a checksum byte, their
;; exclusive-or with $FF.
;;
;; At $FECD. Integer `BASIC` calls $FECF, after the lda, with its own header length in A.
;; In: A1L/A1H = the first address, A2L/A2H = the last
;; Out: A1L/A1H = the address after A2
;; Also: WRITE (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc WriteCassette
.assert * = $FECD, "WriteCassette must stay at $FECD."
    lda #WRITE_HEADER_LENGTH
    jsr Cassette::WriteHeader

    ; Cassette::WriteHeader leaves A at $FF, where the checksum starts.
    ldy #WRITE_FIRST_COUNT

;; Writes the byte at A1, keeping the checksum on the stack, and steps A1 to the next until it passes A2.
;; Also: WR1 (A2RM78, A2RM79, IIEROM82)
NextByte:
    ldx #0
    eor (A1L,x)
    pha
    lda (A1L,x)
    jsr Byte
    jsr NextInRange
    ldy #WRITE_NEXT_COUNT
    pla
    bcc NextByte

    ; Then the checksum. Byte returns with zero set, so this always beeps.
    ldy #WRITE_CHECKSUM_COUNT
    jsr Byte
    beq Beep

;; Writes the 8 bits of A, high bit first.
;; In: A = the byte, Y = the count for the first bit
;; Out: X = 0, zero = set
;; Also: WRBYTE (A2RM78, A2RM79, IIEROM82)
Byte:
    ldx #HALF_CYCLES_PER_BYTE

;; Writes one bit, from the carry.
;; Also: WRBYT2 (A2RM78, A2RM79, IIEROM82)
NextBit:
    asl a
    jsr Cassette::WriteBit
    bne NextBit
    rts
.endproc
.endif

; Commands: the Return handler, after WriteCassette, and on the Enhanced IIe the S and "!" handlers before it.
.scope Commands continued
.if ENHANCED

;; S: prints the address of each place from A1 to A2 that holds the byte in <A4L>, or with <A4H> not 0, those two
;; bytes.
;;
;; A4 is set with "<": 41<300.3FFS finds each $41 from $300 to $3FF.
;; In: A1L/A1H = the first address, A2L/A2H = the last, A4L/A4H = the value
;; Out: A1L/A1H = the address after A2
;; Also: MEMFIND (UNKN)
.proc Search
    ; A4H, when it is not 0, must be in the second byte.
    ldy #1
    lda A4H
    beq CompareLow
    cmp (A1L),y
    bne Next
CompareLow:
    dey
    lda A4L
    cmp (A1L),y
    bne Next
    jsr PrintAddress
Next:
    jsr NextInRange
    bcc Search
    rts
.endproc

;; "!": runs the internal firmware's mini-assembler, then ends the command line as <Commands::Return> does.
;; Also: MINIASM (UNKN)
.proc Assemble
    ldy #FIRMWARE_MINI_ASSEMBLER
    jsr CallFirmware
    ; Falls into Return.
.endproc
.endif

;; A carriage return: ends the command line, after examining the next line when it was alone, and prompts again.
;;
;; It drops the return address of the command line's call to <Commands::RunCommand>, and its high byte, $FF,
;; makes the branch always taken.
;; In: A = the waiting command, or 0, X = 1 after a number, 0 when none, Y = 0
;; Also: CRMON (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc Return
    jsr ExamineNextOrBlank
    pla
    pla
    bne CommandLine
.endproc

.endscope

.if ENHANCED

;; R: reads the bytes from A1 to A2 from the cassette with the internal firmware's routine, then beeps, or prints
;; ERR when the checksum is wrong.
;;
;; At $FEFD.
;; In: A1L/A1H = the first address, A2L/A2H = the last
;; Entry:
;;   Finish = switches slot ROM back in and reports: <Beep> when zero is set, or <PrintError>
;; Also: READ (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc ReadCassette
.assert * = $FEFD, "ReadCassette must stay at $FEFD."
    sta SETINTCXROM
    jsr READTAPE

;; Switches slot ROM back in and reports: <Beep> when zero is set, or <PrintError>.
;; In: zero = set when the checksum matched
Finish:
    sta SETSLOTCXROM
    beq Beep
    bne PrintError
.endproc

; Startup: the Enhanced IIe's title, after ReadCassette.
.scope Startup continued

;; The Enhanced IIe's title, which <ShowTitle at Startup::ShowTitle> shows at the top of the screen.
;; Also: TITLE2E (UNKN)
TitleEnhanced:
    .byte "Apple //e"

.endscope

;; Reads the next character of the input line that is not a blank, in uppercase.
;;
;; $FF13 on the Enhanced IIe, which the firmware's mini-assembler calls.
;; In: Y = the index in <IN>
;; Out: A = the character, Y = the index after it
;; Also: SKIPBLNK (UNKN)
.proc SkipBlanks
.assert * = $FF13, "SkipBlanks must stay at $FF13, where the Enhanced IIe's firmware calls it."
    jsr NextInputCharacter
    cmp #' '
    beq SkipBlanks
    rts
.endproc

; Commands: the Enhanced IIe's end of a hexadecimal number, after SkipBlanks.
.scope Commands continued

;; Ends a number at a character that is not a decimal digit: A to F are digits, and an apostrophe makes the
;; character after it the number's next 8 bits, its code as typed.
;;
;; <ReadHexNumber> jumps here on the Enhanced IIe. An apostrophe before a carriage return clears the number instead. Any
;; other character ends the number, and <ReadHexNumber> returns with it.
;; In: A = the character's code, as <ReadHexNumber> returns it, carry = set for A to F, Y = the index after it
;; Out: A = the code, when the number ends
.proc LetterOrQuote
    bcs ShiftDigit
    cmp #QUOTE_CODE
    bne RestoreRegisters::Done

    ; The next character's 8 bits, unless it is a carriage return, which starts the number again.
    lda IN,y
    ldx #7
    cmp #KEY_CR
    beq ReadHexNumber
    iny
    bne ShiftDigit::NextBit
.endproc

.endscope
.else

;; R: reads the bytes from A1 to A2 from the cassette, then beeps, or prints ERR when the checksum is wrong.
;;
;; At $FEFD.
;; In: A1L/A1H = the first address, A2L/A2H = the last
;; Out: A1L/A1H = the address after A2
;; Also: READ (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc ReadCassette
.assert * = $FEFD, "ReadCassette must stay at $FEFD."

;; The checksum of the bytes read: <MASK>'s byte.
;; Also: CHKSUM (A2RM78, A2RM79, IIEROM82)
Checksum = MASK
    ; Waits for the tape's tone, then lets the header play.
    jsr Cassette::ReadBit
    lda #READ_HEADER_DELAY
    jsr Cassette::WriteHeader

    ; Cassette::WriteHeader leaves A at $FF, where the checksum starts.
    sta Checksum
    jsr Cassette::ReadBit

;; Waits out the header's half cycles for the shorter one of the sync bit.
;; Also: RD2 (A2RM78, A2RM79, IIEROM82)
FindSync:
    ldy #READ_SYNC_COUNT
    jsr Cassette::ReadHalfCycle
    bcs FindSync
    jsr Cassette::ReadHalfCycle
    ldy #READ_FIRST_COUNT

;; Reads a byte into A1, keeping the checksum in <Checksum>, and steps A1 to the next until it passes A2.
;; Also: RD3 (A2RM78, A2RM79, IIEROM82)
NextByte:
    jsr Cassette::ReadByte
    ; Cassette::ReadByte leaves X at 0.
    sta (A1L,x)
    eor Checksum
    sta Checksum
    jsr NextInRange
    ldy #READ_NEXT_COUNT
    bcc NextByte

    ; Then the checksum byte.
    jsr Cassette::ReadByte
    cmp Checksum
    beq Beep
    ; Falls into PrintError.
.endproc
.endif

;; Prints "ERR" and beeps.
;;
;; At $FF2D. The second R is whatever the output hook leaves in A. The screen's leaves the R as it stored it, so in
;; inverse or flashing text the second R shows as the first does; another hook may leave something else.
;; Also: PRERR (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc PrintError
.assert * = $FF2D, "PrintError must stay at $FF2D."
    lda #'E'
    jsr CharacterOut
    lda #'R'
    jsr CharacterOut
    jsr CharacterOut
    ; Falls into Beep.
.endproc

;; Beeps, by printing Control-G.
;;
;; At $FF3A.
;; Also: BELL (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc Beep
.assert * = $FF3A, "Beep must stay at $FF3A."
    lda #KEY_BELL
    jmp CharacterOut
.endproc

;; Restores A, X, Y and P from the registers <SaveRegisters> saved.
;;
;; At $FF3F.
;; Out: A = <A5H>, X = <XREG>, Y = <YREG>, P = <STATUS>
;; Entry:
;;   Done = the return, which the Enhanced IIe's <Commands::LetterOrQuote> returns through too
;; Also: RESTORE (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc RestoreRegisters
.assert * = $FF3F, "RestoreRegisters must stay at $FF3F."
    lda STATUS
    pha
    lda A5H

;; Restores X and Y, then P from the stack.
;; In: P = on the stack
;; Also: RESTR1 (A2RM78, A2RM79, IIEROM82)
ExceptA:
    ldx XREG
    ldy YREG
    plp

;; The return, which the Enhanced IIe's <Commands::LetterOrQuote> returns through too.
Done:
    rts
.endproc

;; Saves A, X, Y, P and S, then clears decimal mode.
;;
;; At $FF4A. Its rts, at $FF58, is the one other sources call as a routine that does nothing.
;; Out: A5H = A, XREG = X, YREG = Y, STATUS = P, SPNT = S less 2 (its return address still on the stack), A = P,
;;   X = SPNT
;; Keeps: Y
;; Entry:
;;   ExceptA = saves X, Y, P and S, then clears decimal mode
;; Also: SAVE (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc SaveRegisters
.assert * = $FF4A, "SaveRegisters must stay at $FF4A."
    sta A5H

;; Saves X, Y, P and S, then clears decimal mode.
;; Also: SAV1 (A2RM78, A2RM79, IIEROM82, IIETRM85)
ExceptA:
    stx XREG
    sty YREG
    php
    pla
    sta STATUS
    tsx
    stx SPNT
    cld
    rts
.endproc
