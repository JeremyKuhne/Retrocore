; retrocore: style=strict
;; The Monitor's interrupt and BRK entries ($FA40-$FAD6), with the Apple II Monitor's instruction stepper around them
;; and, in the other Monitors, the reset handler and power-up.
;;
;; The Apple II Monitor has the first and second pieces of <Stepper> here, with <Interrupt>, <Break> and
;; <ShowBreak> between them. The Autostart and IIe Monitors have the same three routines at $FA40, then the first
;; piece of <Startup>: <Startup::Reset> and <Startup::PowerUp>.

.if MONITOR = MONITOR_II

; The opcodes the Stepper simulates instead of running them.

;; The opcode of JSR, which <Stepper::SimulateJsr> simulates.
OPCODE_JSR = $20

;; The opcode of RTS, which <Stepper::SimulateRts> simulates.
OPCODE_RTS = $60

;; The opcode of JMP, which <Stepper::SimulateJmp> simulates.
OPCODE_JMP = $4C

;; The opcode of JMP indirect, which <Stepper::SimulateJmp::Indirect> simulates.
OPCODE_JMP_INDIRECT = $6C

;; The opcode of RTI, which <Stepper::SimulateRti> simulates.
OPCODE_RTI = $40

; Running a branch in the run area.

;; The bits of an opcode that tell a relative branch: the low five.
BRANCH_OPCODE_MASK = $1F

;; The low five bits of every relative branch's opcode ($10, $30, ... $F0), and of no other opcode.
BRANCH_OPCODE_BITS = $10

;; The displacement a stepped branch runs with: from the byte after it in <Stepper::RunArea> to the jump to
;; <Stepper::TakenBranch> at the end of <Stepper::Trailer>.
TAKEN_DISPLACEMENT = 4

;; The bytes of <Stepper::Trailer>, copied after the instruction in <Stepper::RunArea>.
TRAILER_SIZE = 8
.else

; The reset handler's soft entry check.

;; What <SOFTEV>'s high byte is exclusive-ored with to give <PWREDUP> when the soft entry vector is valid.
SOFT_ENTRY_CHECK = $A5

; Looking for a disk controller.

;; The highest slot, the first one <Startup::PowerUp> tries.
LAST_SLOT = 7

;; The bytes of <BRKV>, <SOFTEV> and <PWREDUP>, which <Startup::PowerUp> sets from <Startup::PowerUpVectors>.
POWER_UP_VECTOR_BYTES = 5
.if ENHANCED

;; The offset in a slot's ROM of the last byte of <Startup::DiskSignature> that <Startup::PowerUp> compares:
;; $Cn05 on the Enhanced IIe, which compares three bytes.
SIGNATURE_LAST = 5
.else

;; The offset in a slot's ROM of the last byte of <Startup::DiskSignature> that <Startup::PowerUp> compares:
;; $Cn07, so the Autostart Monitor and the original IIe compare four bytes.
SIGNATURE_LAST = 7
.endif

; The internal firmware's functions.
.if ENHANCED

;; The internal firmware's function that resets its state on a reset: 9 on the Enhanced IIe.
FIRMWARE_RESET = $09
.else

;; The internal firmware's function that resets its state on a reset: 5 on the original IIe.
FIRMWARE_RESET = $05
.endif
.endif
.if MONITOR = MONITOR_II

    ; Apple II Monitor: three unused bytes before the Stepper.
    .byte $FF, $FF, $FF

;; The Apple II Monitor's S and T commands' engine, which runs a program one instruction at a time.
;;
;; <Stepper::RunInstruction> disassembles the instruction at <PCL>/<PCH> and runs it with the program's registers. Most
;; instructions run in <Stepper::RunArea>, followed by <Stepper::Trailer>; the instructions that would leave it are
;; simulated. Every way ends in <Stepper::Finish>, which shows the registers and returns to the command line. The scope
;; is in three pieces, around <Interrupt>, <Break>, <ShowBreak> and <ShowRegisters>.
.scope Stepper

; Page zero, under the names this scope gives it.

;; The low byte of the command line's return address while <RunInstruction> runs a user instruction.
;;
;; <RunInstruction> pops the address its caller left on the stack into it and <ReturnAddressHigh>, so the user's
;; instruction sees the user's stack, and <Finish> pushes it back. The same byte is <H2>.
;; Also: RTNL (A2RM78, A2RM79)
ReturnAddress = H2

;; The high byte of the return address at <ReturnAddress>. The same byte is <V2>.
;; Also: RTNH (A2RM78, A2RM79)
ReturnAddressHigh = V2

;; The nine bytes, from <A1L>, where <RunInstruction> runs one user instruction: the instruction, padded with NOPs,
;; then <Trailer>'s jumps to <FellThrough> and <TakenBranch>.
;; Also: XQT (A2RM78, A2RM79)
RunArea = A1L

;; Runs one instruction of the program at <PCL>/<PCH> for the S and T commands, then shows the registers.
;;
;; At $FA43. It disassembles the instruction (<Disassembler::PrintInstruction>), then runs it with the program's
;; registers from <A5H>, <XREG>, <YREG> and <STATUS>. Most instructions are copied to <Stepper::RunArea> and run there,
;; followed by <Stepper::Trailer>: NOPs and a jump to <Stepper::FellThrough>, which saves the registers again and moves
;; <PCL>/<PCH> past the instruction. A relative branch is copied with a displacement of <TAKEN_DISPLACEMENT>, so that
;; when it is taken it lands on the trailer's jump to <Stepper::TakenBranch> instead, which applies the real
;; displacement. JSR, RTS, JMP, JMP indirect and RTI would leave the copy, so they are simulated
;; (<Stepper::SimulateJsr>, <Stepper::SimulateRts>, <Stepper::SimulateJmp>, <Stepper::SimulateRti>), and BRK stops in
;; <ShowBreak>. Every other way ends at <Stepper::Finish>, which shows the registers.
;;
;; The command line called it through <Commands::RunCommand>; its return address is moved to
;; <Stepper::ReturnAddress>/<Stepper::ReturnAddressHigh> while the instruction runs, so the instruction sees the
;; program's stack.
;; In: PCL/PCH = the instruction to run
;; Out: PCL/PCH = the next instruction to run
;; See: <Commands::Step>, <Commands::Trace>
;; Also: STEP (A2RM78, A2RM79)
.proc RunInstruction
.assert * = $FA43, "Stepper::RunInstruction must stay at $FA43."
    jsr Disassembler::PrintInstruction

    ; The command line's return address, out of the program's way.
    pla
    sta ReturnAddress
    pla
    sta ReturnAddressHigh
    ldx #TRAILER_SIZE

;; Copies <Stepper::Trailer> to <Stepper::RunArea> + 1 through + 8; the instruction overwrites the start of it.
;; Also: XQINIT (A2RM78, A2RM79)
FillTrailer:
    lda Trailer - 1,x
    sta RunArea,x
    dex
    bne FillTrailer

    ; The instructions that are simulated, by opcode; X = 0 here. RTS and JMP indirect leave the carry set.
    lda (PCL,x)
    beq ShowBreak
    ldy LENGTH
    cmp #OPCODE_JSR
    beq SimulateJsr
    cmp #OPCODE_RTS
    beq SimulateRts
    cmp #OPCODE_JMP
    beq SimulateJmp
    cmp #OPCODE_JMP_INDIRECT
    beq SimulateJmp::Indirect
    cmp #OPCODE_RTI
    beq SimulateRti

    ; A relative branch is the only opcode this gives TAKEN_DISPLACEMENT for, and that is its displacement in
    ; the copy.
    and #BRANCH_OPCODE_MASK
    eor #BRANCH_OPCODE_BITS ^ TAKEN_DISPLACEMENT
    cmp #TAKEN_DISPLACEMENT
    beq StoreByte

;; Copies the instruction to <Stepper::RunArea>, from its last byte (Y = <LENGTH>) down to its opcode.
;; Also: XQ1 (A2RM78)
CopyByte:
    lda (PCL),y

;; Stores a byte of the instruction; a branch enters with its displacement in A.
;; Also: XQ2 (A2RM78, A2RM79)
StoreByte:
    sta RunArea,y
    dey
    bpl CopyByte

    ; Runs it with the program's registers. It returns through FellThrough or TakenBranch.
    jsr RestoreRegisters
    jmp RunArea
.endproc

.endscope
.endif
.if ENHANCED

;; The Monitor's interrupt entry: saves A in <A5H> and goes to the internal firmware's interrupt handler.
;;
;; At $FA40. The 6502's IRQ vector points at the firmware's handler, <IRQHANDLER>, so only code that jumps here by
;; address comes this way. The firmware handles BRK and hands it back at <BreakFromFirmware>.
;; In: A = the interrupted program's A
;; Also: IRQ (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc Interrupt
.assert * = $FA40, "Interrupt must stay at $FA40."
    sta A5H
    lda A5H
    jmp IRQHANDLER
.endproc

;; The internal firmware's way back to the Monitor for a BRK: switches slot ROM in, saves A in <A5H> and handles
;; the BRK (<Break>).
;;
;; At $FA47, which the firmware jumps to.
;; In: A = the program's A, the stack as the BRK left it
.proc BreakFromFirmware
.assert * = $FA47, "BreakFromFirmware is at $FA47."
    sta SETSLOTCXROM
    sta A5H
    ; Falls into Break.
.endproc
.else

;; The interrupt and BRK entry: saves A in <A5H>, then handles a BRK (<Break>) or goes to the program's
;; interrupt handler through <IRQLOC>.
;;
;; At $FA40; in the Apple II Monitor, $FA86. The 6502's IRQ vector points here.
;; In: A = the interrupted program's A, the stack as the interrupt left it
;; Also: IRQ (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc Interrupt
.if MONITOR = MONITOR_II
    .assert * = $FA86, "Interrupt (IRQ) is at $FA86 in the Apple II Monitor."
.else
    .assert * = $FA40, "Interrupt must stay at $FA40."
.endif
    sta A5H

    ; The pushed status's break flag (bit 4) into bit 7.
    pla
    pha
    asl a
    asl a
    asl a
    bmi Break
    jmp (IRQLOC)
.endproc
.endif

;; Handles BRK: saves A, X, Y, P and S (<SaveRegisters::ExceptA>), sets <PCL>/<PCH> from the return address on the
;; stack, then jumps through <BRKV>, normally to <ShowBreak>.
;;
;; At $FA4C; in the Apple II Monitor, $FA92. The return address a BRK pushes is two past the BRK, so that is
;; where they point. The Apple II Monitor has no <BRKV>: it falls into <ShowBreak>.
;; In: A5H = the program's A, the stack as the BRK left it
;; Out: A5H..STATUS = the program's registers, SPNT = its S less 4 (its return address and the JSR's still on the
;;   stack), PCL/PCH = the address after the BRK and its signature byte
;; Also: BREAK (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc Break
.if MONITOR = MONITOR_II
    .assert * = $FA92, "Break (BREAK) is at $FA92 in the Apple II Monitor."
.else
    .assert * = $FA4C, "Break must stay at $FA4C."
.endif

    ; The program's status back, then all its registers saved.
    plp
    jsr SaveRegisters::ExceptA

    ; The return address.
    pla
    sta PCL
    pla
    sta PCH
.if MONITOR != MONITOR_II

    ; To the BRK handler; the Apple II Monitor has none, and falls into ShowBreak.
    jmp (BRKV)
.endif
.endproc

;; The default BRK handler: prints the address at <PCL>/<PCH> (decoding its instruction without printing it), shows
;; the registers on the same line, and enters the Monitor.
;;
;; At $FA59, reached through <BRKV>; in the Apple II Monitor, $FA9C, which <Break> falls into and
;; <Stepper::RunInstruction> jumps to when the instruction to run is a BRK.
;; In: PCL/PCH = the address to show, A5H..SPNT = the registers to show
;; Also: XBRK (A2RM78, A2RM79), OLDBRK (A2RM79, IIEROM82, IIETRM85)
.proc ShowBreak
.if MONITOR = MONITOR_II
    .assert * = $FA9C, "ShowBreak (XBRK) is at $FA9C in the Apple II Monitor."
.else
    .assert * = $FA59, "ShowBreak must stay at $FA59."
.endif
    jsr Disassembler::PrintPcAndDecode
    jsr ShowRegisters::NoReturn
    jmp EnterMonitor
.endproc
.if MONITOR = MONITOR_II

; Stepper: the simulated RTI, RTS, JSR and JMP, and the end of a step.
.scope Stepper continued

;; Simulates RTI for <Stepper::RunInstruction>: pulls the status, then the return address
;; (<Stepper::SimulateRts>).
;;
;; The carry is cleared so the address is used as it is, where RTS adds one.
;; Out: STATUS = the pulled status
;; Also: XRTI (A2RM78, A2RM79)
.proc SimulateRti
    clc
    pla
    sta STATUS
    ; Falls into SimulateRts.
.endproc

;; Simulates RTS for <Stepper::RunInstruction>: pulls the return address into <PCL>/<PCH> and adds one.
;;
;; <Stepper::RunInstruction> enters with the carry set from its compare, which adds the one;
;; <Stepper::SimulateRti> enters with it clear.
;; In: carry = set to add one to the pulled address
;; Entry:
;;   SetPcHigh = sets <PCH>, then moves the PC past the instruction (<Stepper::SimulateRts::AddLength>)
;;   AddLength = adds <LENGTH> and the carry to <PCL>/<PCH>; <Stepper::FellThrough> enters here
;; Also: XRTS (A2RM78, A2RM79)
.proc SimulateRts
    pla
    sta PCL
    pla

;; Sets <PCH>, then moves the PC past the instruction (<Stepper::SimulateRts::AddLength>).
;; Also: PCINC2 (A2RM78, A2RM79)
SetPcHigh:
    sta PCH

;; Adds <LENGTH> and the carry to <PCL>/<PCH>; <Stepper::FellThrough> enters here.
;; Also: PCINC3 (A2RM78, A2RM79)
AddLength:
    lda LENGTH
    jsr NextInstruction::AddA
    sty PCH
    clc
    bcc SimulateJmp::SetPcLow
.endproc

;; Simulates JSR for <Stepper::RunInstruction>: pushes the address of the JSR's last byte, as JSR does, then jumps
;; to its target (<Stepper::SimulateJmp>).
;; Also: XJSR (A2RM78, A2RM79)
.proc SimulateJsr
    ; PC + LENGTH, the JSR's last byte, high byte first.
    clc
    jsr NextInstruction::AddLength
    tax
    tya
    pha
    txa
    pha

    ; The offset of the operand's high byte.
    ldy #2
    ; Falls into SimulateJmp.
.endproc

;; Simulates JMP for <Stepper::RunInstruction>: loads <PCL>/<PCH> from the instruction's operand.
;;
;; JMP indirect enters at <Stepper::SimulateJmp::Indirect> with the carry set: the first pass loads the pointer, and the
;; second, from the start with Y = 1, loads the address it points to.
;; In: Y = the offset of the operand's high byte
;; Entry:
;;   Indirect = loads the operand at PC+Y-1 into <PCL>/<PCH>, and with the carry set loads again from there
;;   SetPcLow = sets <PCL>, then loads again for JMP indirect, or ends the step
;; Also: XJMP (A2RM78, A2RM79)
.proc SimulateJmp
    clc

;; Loads the operand at PC+Y-1 into <PCL>/<PCH>, and with the carry set loads again from there.
;; Also: XJMPAT (A2RM78, A2RM79)
Indirect:
    lda (PCL),y
    tax
    dey
    lda (PCL),y
    stx PCH

;; Sets <PCL>, then loads again for JMP indirect, or ends the step.
;; Also: NEWPCL (A2RM78, A2RM79)
SetPcLow:
    sta PCL
    bcs SimulateJmp
    ; Falls into Finish.
.endproc

;; Ends <Stepper::RunInstruction>: pushes back the command line's return address, then shows the registers
;; (<ShowRegisters>) and returns to the command line.
;; Also: RTNJMP (A2RM78)
.proc Finish
    lda ReturnAddressHigh
    pha
    lda ReturnAddress
    pha
    ; Falls into ShowRegisters.
.endproc

.endscope
.else

;; Taking the machine from reset or power-up to a program: the reset handler, power-up and their data, and the
;; older reset sequence to the Monitor.
;;
;; The Enhanced IIe has it in five pieces: <Startup::Reset> and <Startup::PowerUp> here, the power-up data
;; (<Startup::PowerUpVectors>, <Startup::DiskSignature>, <Startup::Title>), <Startup::ShowTitle>, the Enhanced
;; title, and the older reset (<Startup::ResetToMonitor>). The Autostart and original IIe Monitors have the same four
;; without the Enhanced title, and the Apple II Monitor has only the last.
.scope Startup

;; The reset handler: restores the screen and keyboard, then continues the program that set the soft entry
;; vector, or powers up.
;;
;; At $FA62, where the 6502's reset vector points. It restores normal video, text mode, a full window and the screen and
;; keyboard hooks, turns annunciators 0 and 1 off, lets the internal firmware reset its state, releases any $C800 ROM
;; and clears the keyboard strobe, then beeps. When <PWREDUP> shows the soft entry vector (<SOFTEV>) was set by a
;; program, it jumps through it; the first time it holds BASIC's cold start (<BasicColdStart>, $E000) it is changed
;; to $E003 so later resets warm-start BASIC. Otherwise this is a power-up (<Startup::PowerUp>).
;;
;; The Autostart Monitor reads <CLRAN2> and <CLRAN3> in place of the firmware call, as it has no internal firmware to
;; reset. The Apple II Monitor has no Reset: its reset vector points at <Startup::ResetToMonitor>.
;; Entry:
;;   FixSoftEntry = makes <SOFTEV> BASIC's warm start, so the next reset keeps the program, then cold-starts
;;     BASIC
;; Also: RESET (A2RM79, IIEROM82, IIETRM85)
.proc Reset
.assert * = $FA62, "Startup::Reset must stay at $FA62."

    ; The screen and the hooks.
    cld
    jsr SetNormal
    jsr InitDisplay
    jsr SetScreen
    jsr SetKeyboard

;; Turns annunciators 0 and 1 off, then resets the firmware's state or, on the Autostart Monitor, turns
;; annunciators 2 and 3 off too.
;; Also: INITAN (A2RM79, IIEROM82, IIETRM85)
Annunciators:
    lda CLRAN0
    lda CLRAN1
.if MONITOR = MONITOR_AUTOSTART
    lda CLRAN2
    lda CLRAN3
.else
    ldy #FIRMWARE_RESET
    jsr CallFirmware
    ; Keeps the code at the Autostart Monitor's addresses.
    nop
.endif

    ; No $C800 ROM, and no key waiting.
    lda CLRROM
    bit KBDSTRB

;; Beeps, then warm-starts through <SOFTEV> when <PWREDUP> matches it, or powers up.
;; Also: NEWMON (A2RM79, IIEROM82, IIETRM85)
CheckSoftEntry:
    cld
    jsr Beep
    lda SOFTEV+1
    eor #SOFT_ENTRY_CHECK
    cmp PWREDUP
    bne PowerUp

    ; BASIC's cold start, $E000, the first time only.
    lda SOFTEV
    bne WarmStart
    lda #>BasicColdStart
    cmp SOFTEV+1
    bne WarmStart

;; Makes <SOFTEV> BASIC's warm start, so the next reset keeps the program, then cold-starts BASIC.
;; <Startup::PowerUp> comes here when it finds no disk.
;; Also: FIXSEV (A2RM79, IIEROM82, IIETRM85)
FixSoftEntry:
    ldy #<BasicWarmStart
    sty SOFTEV
    jmp BasicColdStart

;; Warm reset: continues at the program's soft entry vector, <SOFTEV>.
;; Also: NOFIX (A2RM79, IIEROM82, IIETRM85)
WarmStart:
    jmp (SOFTEV)
.endproc

;; Power-up: shows the title, sets the vectors to their defaults, then starts the disk controller in the highest
;; slot that has one, or else BASIC.
;;
;; At $FAA6. It sets <BRKV>, <SOFTEV> and <PWREDUP> from <Startup::PowerUpVectors>, then looks for a bootable disk
;; controller from slot 7 down to slot 1 by its signature bytes (<Startup::DiskSignature>), and starts the first
;; one found at $Cn00. With none, it starts BASIC through <Startup::Reset::FixSoftEntry>.
;; Also: PWRUP (A2RM79, IIEROM82, IIETRM85)
.proc PowerUp
.assert * = $FAA6, "Startup::PowerUp must stay at $FAA6."
    jsr ShowTitle

;; Sets <BRKV>, <SOFTEV> and <PWREDUP> from <Startup::PowerUpVectors>.
;; Also: SETPG3 (A2RM79, IIEROM82, IIETRM85)
SetVectors:
    ldx #POWER_UP_VECTOR_BYTES

;; Copies a byte of the defaults, from the last.
;; Also: SETPLP (A2RM79, IIEROM82, IIETRM85)
CopyVector:
    lda PowerUpVectors - 1,x
    sta BRKV - 1,x
    dex
    bne CopyVector

    ; LOC0/LOC1 points above slot 7's ROM.
    lda #SLOT_ROM_PAGE + LAST_SLOT + 1
    stx LOC0
    sta LOC1

;; Tries the next slot down; past slot 1, starts BASIC.
;; Also: SLOOP (A2RM79, IIEROM82, IIETRM85)
NextSlot:
    ldy #SIGNATURE_LAST
    dec LOC1
    lda LOC1
    cmp #SLOT_ROM_PAGE
    beq Reset::FixSoftEntry
    sta MSLOT

;; Compares every other byte of the slot's ROM with <Startup::DiskSignature>, from the last down to $Cn01.
;; Also: NXTBYT (A2RM79, IIEROM82, IIETRM85)
CompareByte:
    lda (LOC0),y
    cmp DiskSignature - 1,y
    bne NextSlot
    dey
    dey
    bpl CompareByte

    ; A disk controller: boots it.
    jmp (LOC0)

.if ENHANCED

    ; Two unused bytes.
    .byte $00, $00
.else

    ; Two unused bytes.
    .byte $EA, $EA
.endif
.endproc

.endscope
.endif
