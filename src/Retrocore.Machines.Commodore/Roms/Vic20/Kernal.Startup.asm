; retrocore: style=strict
; COMMODORE VIC-20 KERNAL: START-UP AND THE SYSTEM CALLS ($FD22-$FEA8)

; Start-up's part here: the reset, the cartridge test, the RAM vectors' defaults and the RAM test.
.scope Startup continued

; The values start-up uses.

;; The stack pointer at reset: the stack empty, so that the first byte pushed goes to $01FF.
STACK_TOP = $FF

;; The page the RAM test starts at. Its pointer is stepped before each test, so the first byte tested is $0401.
RAM_TEST_START_PAGE = $04

;; The page after the VIC-20's own 4K of RAM, $2000: a top below it means that RAM failed.
INTERNAL_RAM_END_PAGE = $20

;; The page RAM must reach for expansion RAM in block 1 to count, $2100: then the screen moves down to $1000.
EXPANSION_RAM_PAGE = $21

;; <ScreenPage> with the VIC-20's own RAM alone: the screen at $1E00, which is also the top of BASIC's RAM.
SCREEN_PAGE_UNEXPANDED = $1E

;; <ScreenPage> with RAM in block 1: the screen at <ScreenMemory>, $1000.
SCREEN_PAGE_EXPANDED = >ScreenMemory

;; BASIC's first page with RAM in block 1: $1200, after the screen's two pages.
BASIC_PAGE_EXPANDED = SCREEN_PAGE_EXPANDED + 2

;; The first page the lowest RAM may not be in: RAM must start below $1100, so that the screen's RAM is there.
LOWEST_RAM_LIMIT_PAGE = $11

;; The RAM test's first pattern, alternate bits set; rotating it right with carry set gives the second, $AA.
TEST_PATTERN = $55

;; The opcode of LDA immediate, written as a byte before an instruction that a path should skip: it takes the
;; instruction's opcode as its operand.
OPCODE_LDA_IMMEDIATE = $A9

;; VIA 1's peripheral control at start-up: CA1 (the RESTORE key) on a falling edge, CA2 held high (the cassette's
;; motor off), CB1 (RS-232's received data) on a rising edge, CB2 held high (RS-232's sent data idle).
VIA1_PERIPHERAL_SETUP = %11111110

;; VIA 2's peripheral control at start-up: CA1 (the cassette's read line) on a falling edge, CA2 held high (the
;; serial bus's CLK pulled), CB1 (the bus's SRQ) on a rising edge, CB2 held low (the bus's DATA released).
VIA2_PERIPHERAL_SETUP = %11011110

;; The processor's reset vector's target: starts an auto-start cartridge, or else the VIC-20 itself and BASIC.
;;
;; The stack is emptied, interrupts are held off and binary arithmetic is set. A cartridge whose signature
;; <FindCartridge> finds is started at once through <CartridgeColdStart>, with nothing else set up: it must call
;; <TestMemory>, <RestoreVectors>, <InitializeIo> and <Editor::Initialize> itself. Otherwise those four run here, then
;; interrupts are let in and BASIC starts cold through <BasicColdStart>. Neither returns.
;; Also: START (KV20, MTV)
.proc Reset
    ldx #STACK_TOP
    sei
    txs
    cld

    ; A cartridge with the signature is started before anything else.
    jsr FindCartridge
    bne NoCartridge
    jmp (CartridgeColdStart)

;; No cartridge: the VIC-20's own start-up, at $FD2F (64815), which a program can jump to to start again without the
;; cartridge test.
;; Also: START1 (KV20)
NoCartridge:
    jsr TestMemory
    jsr RestoreVectors
    jsr InitializeIo
    jsr Editor::Initialize
    cli
    jmp (BasicColdStart)
.endproc

;; Tells whether an auto-start cartridge is in block 5: zero set when the five bytes at <CartridgeSignatureArea>
;; are <CartridgeSignature>'s.
;;
;; <Reset> asks at start-up, and the NMI handler when the RESTORE key is pressed.
;; Out: zero = set when the signature is there, X = 0 then, or else the place (5 to 1) of the first byte that
;;   differs, counting from the last
;; Keeps: Y
;; Also: A0INT (KV20)
.proc FindCartridge
    ldx #CARTRIDGE_SIGNATURE_LENGTH

;; Compares each byte, from the last.
;; Also: A0IN1 (KV20)
Next:
    lda CartridgeSignature-1,x
    cmp CartridgeSignatureArea-1,x
    bne Done
    dex
    bne Next

;; Returns: zero set if every byte matched, clear at the first that differs.
;; Also: A0IN2 (KV20)
Done:
    rts
.endproc

;; The signature of an auto-start cartridge, at $A004 after its two start addresses: A0, then CBM with each letter's
;; high bit set ($41 $30 $C3 $C2 $CD).
;; Also: TBLA0R (KV20)
CartridgeSignature:
    .byte "A0", 'C' | $80, 'B' | $80, 'M' | $80

;; The cartridge signature's length, 5 bytes.
;; Also: TBLA0E (KV20)
CARTRIDGE_SIGNATURE_LENGTH = * - CartridgeSignature
.assert CARTRIDGE_SIGNATURE_LENGTH = 5, "A0 and CBM: five bytes."

;; RESTOR's target: puts every RAM vector back to the kernal's own routine, from <DefaultVectors>, falling into
;; <RestoreVectors::Copy> with carry clear.
;;
;; Start-up comes here, and so do STOP-RESTORE and BRK before BASIC's warm start.
;; Commodore's listing names it RESTOR (KV20), the name of <KernalRestoreVectors>.
;; Out: IrqVector..SaveVector+1 = <DefaultVectors>
;; Entry:
;;   Copy = VECTOR's target: with carry set, reads the 16 RAM vectors into the 32 bytes at X/Y; with carry clear,
;;     sets them from those bytes.
.proc RestoreVectors
    ldx #<DefaultVectors
    ldy #>DefaultVectors
    clc

;; VECTOR's target: copies the 16 RAM vectors, <IrqVector> to <SaveVector>, to or from the 32 bytes at X/Y.
;;
;; With carry set the vectors are read into the bytes at X/Y, and written back to themselves unchanged; with carry
;; clear the bytes at X/Y are written into the vectors, and back to themselves. A program changes a vector by reading
;; them all, changing its copy, and setting them all from it. Interrupts are not held off: with them on, an IRQ that
;; comes between the writes of <IrqVector>'s two bytes goes through a vector half changed.
;; Commodore's listing names it VECTOR (KV20), the name of <KernalCopyVectors>.
;; In: carry = set to read the vectors, clear to set them, X/Y = the address of the 32 bytes
;; Keeps: X, carry
Copy:
    stx Temporary
    sty Temporary+1
    ldy #RAM_VECTORS_SIZE-1

;; Each byte, from the last: from the RAM vectors with carry set, from the bytes at X/Y with carry clear.
;; Also: MOVOS1 (KV20)
Next:
    lda IrqVector,y
    bcs Store
    lda (Temporary),y

;; Stores the byte both at X/Y and in the RAM vectors.
;; Also: MOVOS2 (KV20)
Store:
    sta (Temporary),y
    sta IrqVector,y
    dey
    bpl Next
    rts
.endproc

;; The RAM vectors' defaults, in their order from <IrqVector> to <SaveVector>: the jiffy interrupt, BRK, the NMI, the
;; channel routines, BRK's again for the 15th vector at $032E, which the kernal does not use, then LOAD and SAVE.
;; Also: VECTSS (KV20)
DefaultVectors:
    .word Interrupts::Jiffy                 ; IrqVector
    .word Interrupts::NmiHandler::Break     ; BreakVector
    .word Interrupts::NmiHandler            ; NmiVector
    .word Channels::Open                    ; OpenVector
    .word Channels::Close                   ; CloseVector
    .word Channels::SelectInput             ; SelectInputVector
    .word Channels::SelectOutput            ; SelectOutputVector
    .word Channels::ResetChannels           ; ResetChannelsVector
    .word Channels::CharacterIn             ; CharacterInVector
    .word Channels::CharacterOut            ; CharacterOutVector
    .word Channels::TestStopKey             ; TestStopKeyVector
    .word Channels::GetInput                ; GetInputVector
    .word Channels::CloseAll                ; CloseAllFilesVector
    .word Interrupts::NmiHandler::Break     ; $032E, not used
    .word Channels::Load                    ; LoadVector
    .word Channels::Save                    ; SaveVector

;; The RAM vectors' size, 32 bytes: 16 vectors.
;; Also: VECTSE (KV20)
RAM_VECTORS_SIZE = * - DefaultVectors
.assert RAM_VECTORS_SIZE = SaveVector + 2 - IrqVector, "One default for each RAM vector."

;; Clears the system's pages and tests the RAM, to place BASIC's RAM and the screen.
;;
;; Pages 0, 2 and 3 are cleared, the RAM vectors with them (<RestoreVectors> sets those next), and <TapeBuffer> is
;; pointed at the tape buffer. The test then tries each byte from $0401 up with <TestByte>: the first that holds is
;; the bottom of BASIC's RAM, and the first after it that fails is the top. If RAM ends below $2100, the VIC-20 has
;; only its own 4K (and perhaps 3K at $0400): the screen is at $1E00 and BASIC's RAM ends there. If RAM goes on past
;; $2100, there is RAM in block 1: the screen moves to $1000, BASIC's RAM starts at $1200 whatever is below, and it
;; ends at the top found. If the lowest RAM is at $1100 or above, or RAM ends below $2000, the VIC-20's own RAM has
;; failed: the routine sets the VIC up and hangs, with no message.
;; Out: MemoryStart = the bottom of BASIC's RAM, MemoryEnd = its top, plus one, ScreenPage = the screen's page,
;;   TapeBuffer = the tape buffer's address
;; Also: RAMTAS (KV20)
.proc TestMemory
    lda #0
    tax

;; Zeroes pages 0, 2 and 3.
;; Also: RAMTZ0 (KV20)
ClearPages:
    sta $00,x
    sta $200,x
    sta $300,x
    inx
    bne ClearPages

    ; The tape buffer's pointer.
    ldx #<TapeBufferArea
    ldy #>TapeBufferArea
    stx TapeBuffer
    sty TapeBuffer+1

    ; Seeking the bottom first (SavedX = 0), from $0400, with Y = 0 for the test's index.
    sta Pointer
    sta SavedX
    sta MemoryStart
    tay
    lda #RAM_TEST_START_PAGE
    sta Pointer+1

;; The next byte.
;; Also: RAMTZ1 (KV20)
NextAddress:
    inc Pointer
    bne Check
    inc Pointer+1

;; Tests the byte, then goes on by what is sought: the bottom while <SavedX> is 0, the top after.
;; Also: RAMTZ2 (KV20)
Check:
    jsr TestByte
    lda SavedX
    beq SeekingBottom
    bcs NextAddress

    ; The top is found: where it is places the screen.
    ldy Pointer+1
    ldx Pointer
    cpy #INTERNAL_RAM_END_PAGE
    bcc NoSystemRam
    cpy #EXPANSION_RAM_PAGE
    bcs ScreenAtBottom

    ; The VIC-20's own RAM alone: the screen at $1E00, and BASIC's top there too, as Y is now its page.
    ldy #SCREEN_PAGE_UNEXPANDED
    sty ScreenPage

;; Sets <MemoryEnd> from X/Y: $1E00, or the first byte that failed.
;; Also: RAMTZ3 (KV20)
SetTop:
    jmp MemoryTop::SetTop

;; RAM in block 1: the screen at $1000, BASIC from $1200, and its top as found.
;; Also: RAMTZ4 (KV20)
ScreenAtBottom:
    lda #BASIC_PAGE_EXPANDED
    sta MemoryStart+1
    lda #SCREEN_PAGE_EXPANDED
    sta ScreenPage
    bne SetTop

;; Seeking the bottom: on until a byte holds. Its page is <MemoryStart>'s, and goes in <SavedX> too, so that the top
;; is sought next.
;; Also: RAMTZ5 (KV20)
SeekingBottom:
    bcc NextAddress
    lda Pointer+1
    sta MemoryStart+1
    sta SavedX
    cmp #LOWEST_RAM_LIMIT_PAGE
    bcc NextAddress
    ; The lowest RAM is above $10FF: falls into NoSystemRam.

;; The VIC-20's own RAM failed: loads the VIC's registers, again and again, and never returns.
;; Also: BADRAM (KV20)
NoSystemRam:
    jsr Editor::InitializeVic
    jmp NoSystemRam
.endproc

.endscope

; The tape's part here: its table of interrupt routines.
.scope Tape continued

;; The interrupt routines the tape points <IrqVector> at, as <SetIrqVector> picks them by X: <WriteLeader> for a
;; leader or trailer, <WriteData::Interrupt> for a block's bytes, <Interrupts::Jiffy> again at the end, and
;; <ReadInterrupt> for reading.
;; Also: BSIT (KV20)
InterruptHandlers:
    .word WriteLeader, WriteData::Interrupt, Interrupts::Jiffy, ReadInterrupt
.endscope

; Start-up's part here: the VIAs' set-up.
.scope Startup continued

;; Sets both VIAs up for the VIC-20's devices, and starts the jiffy interrupt.
;;
;; Every interrupt source is turned off first. Both VIAs' timer 1 is set free-running and timer 2 one-shot, and the
;; handshake lines as <VIA1_PERIPHERAL_SETUP> and <VIA2_PERIPHERAL_SETUP> say. VIA 1's port B (the user port) and VIA
;; 2's port A (the keyboard's rows) are inputs, VIA 2's port B (the columns) outputs, and VIA 1's port A all inputs
;; but the serial bus's ATN, which is released. The bus's CLK is released and then pulled again, as the listing has
;; it; the RESTORE key's NMI is turned on; and <InitializeIo::StartJiffyTimer> follows.
;; Keeps: Y
;; Entry:
;;   StartJiffyTimer = turns VIA 2's timer 1 interrupt on and starts it at 60 a second (the tape routines come here
;;     when they finish)
;; Also: IOINIT (KV20)
.proc InitializeIo
    lda #VIA_INTERRUPTS_ALL
    sta Via1InterruptEnable
    sta Via2InterruptEnable

    ; The timers and the handshake lines.
    lda #VIA_TIMER1_FREE_RUNNING
    sta Via2AuxiliaryControl
    lda #VIA_TIMER1_FREE_RUNNING
    sta Via1AuxiliaryControl
    lda #VIA1_PERIPHERAL_SETUP
    sta Via1PeripheralControl
    lda #VIA2_PERIPHERAL_SETUP
    sta Via2PeripheralControl

    ; The ports' directions.
    ldx #VIA_ALL_INPUTS
    stx Via1DirectionB
    ldx #VIA_ALL_OUTPUTS
    stx Via2DirectionB
    ldx #VIA_ALL_INPUTS
    stx Via2DirectionA
    ldx #VIA1_SERIAL_ATN
    stx Via1DirectionA

    ; ATN released, and CLK; then the RESTORE key's NMI on, and CLK pulled again.
    ldx #0
    stx Via1PortA
    jsr Serial::ReleaseClock
    lda #VIA_INTERRUPTS_ON | VIA_INTERRUPT_CA1
    sta Via1InterruptEnable
    jsr Serial::PullClock

;; Turns VIA 2's timer 1 interrupt on and starts the timer at 60 a second, with <JIFFY_TIMER_COUNT> (the tape
;; routines come here when they finish).
;; Keeps: X, Y
;; Also: IOKEYS (KV20)
StartJiffyTimer:
    lda #VIA_INTERRUPTS_ON | VIA_INTERRUPT_TIMER1
    sta Via2InterruptEnable
    lda #<JIFFY_TIMER_COUNT
    sta Via2Timer1
    lda #>JIFFY_TIMER_COUNT
    sta Via2Timer1High
    rts
.endproc

.endscope

; The channels' part here: the calls that set a file's name and numbers, and read the status.
.scope Channels continued

;; SETNAM's target: sets the file name for the next OPEN, LOAD or SAVE.
;; Commodore's listing names it SETNAM (KV20), the name of <KernalSetFileName>.
;; In: A = the name's length, 0 for none, X/Y = its address
;; Out: FileNameLength = A, FileName = X/Y
;; Keeps: A, X, Y
.proc SetFileName
    sta FileNameLength
    stx FileName
    sty FileName+1
    rts
.endproc

;; SETLFS's target: sets the logical file number, the device and the secondary address for the next OPEN, LOAD or
;; SAVE.
;; Commodore's listing names it SETLFS (KV20), the name of <KernalSetFile>.
;; In: A = the logical file number, X = the device, Y = the secondary address, $FF for none
;; Out: LogicalFile = A, Device = X, SecondaryAddress = Y
;; Keeps: A, X, Y
.proc SetFile
    sta LogicalFile
    stx Device
    sty SecondaryAddress
    rts
.endproc

;; READST's target: returns the status of the last input or output, <IoStatus>, or for device 2 RS-232's.
;;
;; For RS-232 it clears <Rs232::Status>, but loads 0 over the status before it returns, so it always returns 0 for
;; device 2 (901486-06 and -07 alike): a program reads <Rs232::Status> itself instead. <IoStatus> is not cleared.
;; In: Device = the current device
;; Out: A = <IoStatus>, or 0 for device 2, zero = set when A is 0, negative = A's bit 7
;; Keeps: X, Y
;; Entry:
;;   SetMessages = SETMSG's target: sets <MessageMode> from A, then returns <IoStatus> in A
;;   SetStatus = adds A's bits to <IoStatus> and returns the result in A: how the serial bus, the tape and LOAD report
;;     what went wrong
;; Also: READSS (KV20)
.proc ReadStatus
    lda Device
    cmp #DEVICE_RS232
    bne ReadIoStatus
    lda Rs232::Status
    lda #0
    sta Rs232::Status
    rts

;; SETMSG's target: sets which messages the kernal prints, and falls into <ReadStatus::ReadIoStatus>.
;; Commodore's listing names it SETMSG (KV20), the name of <KernalSetMessages>.
;; In: A = the messages: bit 7 the control messages, bit 6 the error messages
;; Out: MessageMode = A, A = <IoStatus>
;; Keeps: X, Y
SetMessages:
    sta MessageMode

;; Returns <IoStatus> in A, through <ReadStatus::SetStatus> with its own bits.
;; Commodore's listing names it READST (KV20), the name of <KernalReadStatus>.
;; Out: A = <IoStatus>
;; Keeps: X, Y
ReadIoStatus:
    lda IoStatus

;; Adds A's bits to <IoStatus>: the serial bus, the tape and LOAD report what went wrong here, with the STATUS_*
;; bits.
;; In: A = the bits to add
;; Out: IoStatus = IoStatus or A, A = IoStatus
;; Keeps: X, Y
;; Also: UDST (KV20)
SetStatus:
    ora IoStatus
    sta IoStatus
    rts
.endproc

.endscope

; The serial bus's part here: SETTMO.
.scope Serial continued

;; SETTMO's target: stores A in <Serial::TimeoutFlag>, the PET's IEEE-488 timeout switch, which the VIC-20's serial
;; routines never read.
;; Commodore's listing names it SETTMO (KV20), the name of <KernalSetTimeout>.
;; In: A = the switch
;; Keeps: A, X, Y
.proc SetTimeout
    sta TimeoutFlag
    rts
.endproc

.endscope

; Start-up's part here: the calls for the memory's top and bottom, and the RAM test's byte test.
.scope Startup continued

;; MEMTOP's target: reads or sets the top of BASIC's RAM, <MemoryEnd>.
;; Commodore's listing names it MEMTOP (KV20), the name of <KernalMemoryTop>.
;; In: carry = set to read, clear to set, X/Y = the new top, to set it
;; Out: X/Y = <MemoryEnd>
;; Keeps: A, carry
;; Entry:
;;   Read = reads <MemoryEnd> into X/Y, and stores it back (OPEN and CLOSE use it for RS-232's buffers)
;;   SetTop = sets <MemoryEnd> from X/Y (the RAM test and OPEN use it)
.proc MemoryTop
    bcc SetTop

;; Reads <MemoryEnd> into X/Y, falling into <MemoryTop::SetTop>, which stores it back (OPEN and CLOSE use it for
;; RS-232's buffers).
;; Out: X/Y = <MemoryEnd>
;; Keeps: A, carry
;; Also: GETTOP (KV20)
Read:
    ldx MemoryEnd
    ldy MemoryEnd+1

;; Sets <MemoryEnd> from X/Y.
;; In: X/Y = the top of BASIC's RAM, plus one
;; Out: MemoryEnd = X/Y
;; Keeps: A, X, Y, carry
;; Also: SETTOP (KV20)
SetTop:
    stx MemoryEnd
    sty MemoryEnd+1
    rts
.endproc

;; MEMBOT's target: reads or sets the bottom of BASIC's RAM, <MemoryStart>.
;; Commodore's listing names it MEMBOT (KV20), the name of <KernalMemoryBottom>.
;; In: carry = set to read, clear to set, X/Y = the new bottom, to set it
;; Out: X/Y = <MemoryStart>
;; Keeps: A, carry
.proc MemoryBottom
    bcc SetBottom
    ldx MemoryStart
    ldy MemoryStart+1

;; Sets <MemoryStart> from X/Y.
;; Also: SETBOT (KV20)
SetBottom:
    stx MemoryStart
    sty MemoryStart+1
    rts
.endproc

;; Tells whether the byte at (<Pointer>),Y is RAM: it must hold <TEST_PATTERN>, $55, and then $AA. The byte's own
;; value is put back either way.
;; In: Pointer = the address, less Y, Y = the index (0 from the RAM test)
;; Out: carry = set if the byte is RAM, A = X = the byte's value, zero and negative = from it
;; Keeps: Y
;; Also: CHKMEM (KV20)
.proc TestByte
    lda (Pointer),y
    tax

    ; $55, then $AA: rotating with the carry the equal compare set.
    lda #TEST_PATTERN
    sta (Pointer),y
    cmp (Pointer),y
    bne NoRam
    ror a
    sta (Pointer),y
    cmp (Pointer),y
    bne NoRam
    .byte OPCODE_LDA_IMMEDIATE      ; skips the CLC: RAM returns with carry set

;; Not RAM: carry clear. Both paths then put the byte's value back.
;; Also: NOMEM (KV20)
NoRam:
    clc
    txa
    sta (Pointer),y
    rts
.endproc

.endscope
