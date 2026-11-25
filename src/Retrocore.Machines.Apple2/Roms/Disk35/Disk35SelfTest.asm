; retrocore: style=strict
;; THE CARD'S SELF-TESTS ($8F00-$99FF): THE START-UP TEST AND THE DIAGNOSTICS' CARD SIDE
;;
;; <SelfTest::StartUp> ($9649) runs at every reset, from the main firmware's reset at $D11D (<CardReset>):
;;   1. copies the slot page's first 35 bytes ($Cn00-$Cn22) from the EPROM, so the host sees the SmartPort
;;      signature at once, and its entries wait on themselves (Boot::WaitForCard and SmartPortEntry::WaitForCard) until
;; the card is ready;
;;   2. the EPROM's checksum: the sum of every byte but $FFF9 is 0, and $FFF9 plus the carries is 0;
;;   3. the SWIM: as an IWM, its data register and three modes; as the ISM, its phases, its mode and its sixteen
;;      parameters; and as the IWM again;
;;   4. the RAM: the stack page with a rising and a falling count, and eight bytes from $0403 to $4003, for the
;;      address lines.
;; Then it turns the LED off and goes on to the main firmware's start-up at $D129 (<Startup>). On a failure it makes
;; every entry of the slot page jump to the Monitor, clears the SmartPort signature and blinks the LED for ever.
;;
;; <SelfTest::CardDiagnostics> ($8F00) runs when the host sends <COMMAND_DIAGNOSTICS>. It tests page zero, puts the
;; diagnostics' page zero and host code in place, sends the host to <Diagnostics::Start> (Disk35Diagnostics.asm) and
;; reports to it, through $0002, each of: the slot page ("Card pseudoROM"), the EPROM's CRCs, its checksum, the SWIM and
;; the RAM. Then it leaves a sum of its RAM for the host to check ("Host/Card shared data"), finds its units, and, only
;; with Apple's factory fixture in slot 1, writes and reads back a block on units 1 and 2. It then reads memory
;; until the host says to restart. A failure before the RAM's sum is reported to the host and blinks the LED until
;; the host says to restart.
;;
;; At the card's 2 MHz the start-up test takes about a quarter of a second, nearly all of it the checksum.

; The card's own 65C02, with the 65C02's instructions.
.cpu Wdc65C02

;; The next of <SelfTest::TestRam>'s 16-bit patterns: shifts <SelfTest::Pattern> left, and applies
;; <SelfTest::PATTERN_TAPS> when a bit falls out; then goes on at the label given.
;; Parameters:
;;   again = where to go on
.macro NextRamPattern again
    clc
    rol SelfTest::Pattern
    rol SelfTest::Pattern+1
    bcc again
    lda #<SelfTest::PATTERN_TAPS
    eor SelfTest::Pattern
    sta SelfTest::Pattern
    lda #>SelfTest::PATTERN_TAPS
    eor SelfTest::Pattern+1
    sta SelfTest::Pattern+1
    bra again
.endmacro

;; Starts a pass of <SelfTest::TestRam> at $0006 with the first pattern, 1.
.macro FirstRamPattern
    lda #6
    sta SelfTest::RamPointer
    stz SelfTest::RamPointer+1
    lda #1
    sta SelfTest::Pattern
    stz SelfTest::Pattern+1
.endmacro

;; One bit of <SelfTest::RomCrc>: shifts <SelfTest::Crc> left and takes the byte's next bit, lowest first, into
;; carry (from the EPROM for the first bit, then from Y); when the two differ, applies
;; <SelfTest::CRC_POLYNOMIAL>.
;; Parameters:
;;   first = 1 for the byte's first bit, read from the EPROM; 0 for the others, kept in Y
.macro CrcBit first
    .local High, Apply, Done
    clc
    rol SelfTest::Crc
    rol SelfTest::Crc+1
    bcs High
    .if first
        lda (SelfTest::RomPointer)
    .else
        tya
    .endif
    ror a
    tay
    bcc Done
Apply:
    lda #<SelfTest::CRC_POLYNOMIAL
    eor SelfTest::Crc
    sta SelfTest::Crc
    lda #>SelfTest::CRC_POLYNOMIAL
    eor SelfTest::Crc+1
    sta SelfTest::Crc+1
    bra Done
High:
    .if first
        lda (SelfTest::RomPointer)
    .else
        tya
    .endif
    ror a
    tay
    bcs Done
    bra Apply
Done:
.endmacro

;; Waits about outer times 2030 cycles: 1 ms at 2 MHz for each count. Uses X and A, and keeps the flags of neither.
;; Parameters:
;;   outer = the milliseconds, 1 to 255
.macro WaitMilliseconds outer
    .local again, wait
    ldx #outer
again:
    lda #$CB                        ; 203 times 10 cycles
wait:
    dec a
    bne *+2                         ; goes on either way
    nop
    bne wait
    dex
    bne again
.endmacro

;; The card's self-tests: the start-up test every reset runs, and the card's side of the built-in diagnostics.
.scope SelfTest

; The card's page zero, as the tests borrow it. The diagnostics' page zero has the main firmware's layout.

;; The card's page zero, whose first six bytes <CardDiagnostics> tests.
PageZero = $00

;; <TestRam>'s 16-bit pattern, low byte first.
Pattern = CardState

;; <TestRam>'s and <Idle>'s place in memory.
RamPointer = WriteProgress

;; <SumSharedRam>'s place in memory.
SumPointer = CardState

;; The diagnostics' report to the host of its last test (host $C802): <REPORT_PASSED> or <REPORT_FAILED>.
Report = CardCommand

;; The block <WriteTestBlock> and <ReadTestBlock> use, low byte first.
Block = ParameterLow

;; The block that failed, for the host (host $C807-$C808).
FailedBlock = ParameterHigh

;; Set to $FF for the test's reads: apparently, from the disk and not the cache.
ForceRead = CacheOption

;; <RomCrc>'s CRC, low byte first.
Crc = $FC

;; <RomChecksum>'s and <RomCrc>'s place in the EPROM, as is <StartUp>'s.
RomPointer = $FE

; The card's RAM.

;; Slot 1's first 16 bytes, which the host copies here (host $CBEE).
FixtureId = $03EE

;; A byte that varies, from the host (host $CBFE): <WriteTestBlock> picks its block from it.
RandomBlock = $03FE

;; The mailbox for the later steps (host $CBFF): the host writes <SIGNAL_GO>, <SIGNAL_STOP> or <SIGNAL_EXIT>; the
;; card answers 0 for a step done, <SIGNAL_STOP> for no more steps, or <SIGNAL_READ_WRITE_FAILED>.
Signal = $03FF

;; The 512 bytes <WriteTestBlock> wrote, $0400-$05FF.
SavedBlock = $0400

;; Plus $0400 to $4000: the bytes that test the address lines.
AddressCells = $0003

;; The complement of <SumSharedRam>'s sum, for the host to check.
SharedSum = $09FF

; The EPROM.

;; Makes the checksum's carries add up to 0.
RomCheckByte = $FFF9

;; The diagnostics' host code for $CA00-$CBFF, two pages.
DiagnosticsHostCode = DiagnosticsImage

;; The diagnostics' host code for $CC00-$CFFF, four pages.
DiagnosticsExpansion = DiagnosticsImage + $0200

;; The card's page zero for the diagnostics.
DiagnosticsZeroPage = DiagnosticsImage + $0600

; The host.

;; Inherit: <Monitor:Startup::ResetToMonitor>
;; At $FF59, in the host's ROM: where a failed card's slot page sends the host.
;; Also: OLDRST (A2RM79, IIEROM82, IIETRM85)
ResetToMonitor = $FF59

; The slot page's bytes the tests change.

;; $Cn05, the SmartPort signature's $03.
SlotSignature = SharedSlotPage + 5

;; Boot::WaitForCard's branch offset ($7B0C).
BootWait = SharedSlotPage + <Boot::WaitForCard + 1

;; <WaitForDiagnostics>'s branch offset ($7B18).
DiagnosticsWait = SharedSlotPage + <WaitForDiagnostics::Wait + 1

;; SmartPortEntry::WaitForCard's branch offset ($7B22).
CallWait = SharedSlotPage + <SmartPortEntry::Wait + 1

;; $Cn0D, where a released Boot::WaitForCard goes.
SlotDiagnostics = SharedSlotPage + <DiagnosticsEntry

;; $Cn23, where a released SmartPortEntry::WaitForCard goes.
SlotCall = SharedSlotPage + <Call

; Values.

;; A branch offset that waits on itself.
BRANCH_TO_SELF = $FE

;; <Report>: the card's test passed.
REPORT_PASSED = $A1

;; <Report>: the card's test failed.
REPORT_FAILED = $4F

;; <Signal>, from the host: take the next step.
SIGNAL_GO = $A1

;; <Signal>, from the host: stop; to the host: no more steps.
SIGNAL_STOP = $4F

;; <Signal>, from the host: restart.
SIGNAL_EXIT = $55

;; <Signal>, to the host: a read/write test failed.
SIGNAL_READ_WRITE_FAILED = $4E

;; <CardState> while the card waits for a command.
STATE_WAITING = $FF

;; The first of the buffers <FillBuffers> fills: $08-$1B, $1000-$37FF, a track's worth.
FIRST_BUFFER = $08

;; Past the last of them.
END_BUFFER = $1C

;; <FillBuffers>'s first pattern's first byte.
FIRST_SEED = $A5

;; <FillSecondPattern>'s first byte.
SECOND_SEED = $C3

;; <TestRam>'s pattern's feedback.
PATTERN_TAPS = $100B

;; The CCITT CRC-16's polynomial.
CRC_POLYNOMIAL = $1021

;; The 2 KB blocks <RomCrc> checks, $8000-$F7FF.
CRC_BLOCKS = 15

;; The EPROM's first page.
ROM_FIRST_PAGE = $80

;; The 6502's JMP opcode, which a failed start-up writes into the slot page.
OPCODE_JMP = $4C

;; The IWM's status: its low five bits are the mode.
IWM_MODE_BITS = $1F

;; Written to the IWM's mode with bit 6 set, clear, set and set again: switches the SWIM to the ISM.
ISM_SWITCH = $4F

;; Bit 6 of the mode, written as above: the ISM; written to <Ism::ClearMode>, back to the IWM.
ISM_MODE = $40

;; What the ISM's phase register reads after the switch.
ISM_PHASES = $F0

.assert SlotPageImage = $8100, "The slot page's image is at $8100."
.assert DiagnosticsZeroPage = $8E00, "The diagnostics' page zero is at $8E00."
.assert BootWait = $7B0C && DiagnosticsWait = $7B18 && CallWait = $7B22, "The slot page's waits moved."
.assert RomCrcs = $FFDA, "The EPROM's CRCs are at $FFDA."

.assert * = $8F00, "The diagnostics' card side starts at $8F00, where command $3D goes."

;; The diagnostics' card side, which the main firmware's <RunCommand> jumps to for <COMMAND_DIAGNOSTICS>. Tests page
;; zero's first six bytes, puts the diagnostics' page zero and the host's code at $CC00 in place, sends the host
;; there, and reports each test to it.
.proc CardDiagnostics
    sei
    cld
    ldx #$FF
    txs

    ; Page zero's first six bytes, with patterns and then their complements.
    ldx #5
WritePatterns:
    lda ZeroPagePatterns,x
    sta PageZero,x
    dex
    bpl WritePatterns
    ldx #5
CheckPatterns:
    lda ZeroPagePatterns,x
    cmp PageZero,x
    beq PatternKept
    jmp DiagnosticsFailed
PatternKept:
    dex
    bpl CheckPatterns
    ldx #5
WriteInverse:
    lda ZeroPageInverse,x
    sta PageZero,x
    dex
    bpl WriteInverse
    ldx #5
CheckInverse:
    lda ZeroPageInverse,x
    cmp PageZero,x
    beq InverseKept
    jmp DiagnosticsFailed
InverseKept:
    dex
    bpl CheckInverse

    ; The diagnostics' page zero and host code, then the host sent to Diagnostics::Start.
    jsr CopyDiagnosticsZeroPage
    jsr VerifyZeroPage
    bcc ZeroPageCopied
    jmp DiagnosticsFailed
ZeroPageCopied:
    jsr CopyExpansion
    stz Report
    stz DiagnosticsWait             ; sends the host to Diagnostics::Start
    lda #BRANCH_TO_SELF
    sta BootWait
    sta CallWait

    ; Card pseudoROM: the slot page and the host's code.
    jsr VerifySlotPage
    bcc SlotPageOk
    jmp DiagnosticsFailed
SlotPageOk:
    jsr VerifyExpansion
    bcc ExpansionOk
    jmp DiagnosticsFailed
ExpansionOk:
    jsr ReportPass

    ; Card ROM CRC.
    jsr RomCrc
    bcc CrcOk
    jmp DiagnosticsFailed
CrcOk:
    jsr ReportPass

    ; Card ROM Checksum.
    jsr RomChecksum
    bcc ChecksumOk
    jmp DiagnosticsFailed
ChecksumOk:
    jsr ReportPass

    ; SWIM Regs.
    jsr TestSwim
    bcc SwimOk
    jmp DiagnosticsFailed
SwimOk:
    jsr ReportPass
    ; Falls into TestRam.
.endproc

;; Tests the RAM from $0006 to $7AFF, but for the I/O page ($0A00-$0AFF): writes a sequence of 16-bit patterns,
;; checks it, then does the same with their complements. The slot page and the host's $CC00 code are kept; the
;; host's $CA00 code is written over, and <SumSharedRam> puts it back. A difference goes to <DiagnosticsFailed>.
.proc TestRam

    ; The patterns.
    FirstRamPattern
Word:
    lda #>Iwm::Phase0Off
    cmp RamPointer+1
    bne NotIo
    lda #>Iwm::Phase0Off + 1
    sta RamPointer+1
NotIo:
    lda #>SharedSlotPage
    cmp RamPointer+1
    beq Check
    lda Pattern
    sta (RamPointer)
    inc RamPointer
    lda Pattern+1
    sta (RamPointer)
    inc RamPointer
    bne Step
    inc RamPointer+1
Step:
    NextRamPattern Word

    ; Checks them.
Check:
    FirstRamPattern
CheckWord:
    lda #>Iwm::Phase0Off
    cmp RamPointer+1
    bne CheckNotIo
    lda #>Iwm::Phase0Off + 1
    sta RamPointer+1
CheckNotIo:
    lda #>SharedSlotPage
    cmp RamPointer+1
    beq Inverse
    lda Pattern
    cmp (RamPointer)
    beq LowOk
    jmp DiagnosticsFailed
LowOk:
    inc RamPointer
    lda Pattern+1
    cmp (RamPointer)
    beq HighOk
    jmp DiagnosticsFailed
HighOk:
    inc RamPointer
    bne CheckStep
    inc RamPointer+1
CheckStep:
    NextRamPattern CheckWord

    ; Their complements.
Inverse:
    FirstRamPattern
InverseWord:
    lda #>Iwm::Phase0Off
    cmp RamPointer+1
    bne InverseNotIo
    lda #>Iwm::Phase0Off + 1
    sta RamPointer+1
InverseNotIo:
    lda #>SharedSlotPage
    cmp RamPointer+1
    beq CheckInverse
    lda Pattern
    eor #$FF
    sta (RamPointer)
    inc RamPointer
    lda Pattern+1
    eor #$FF
    sta (RamPointer)
    inc RamPointer
    bne InverseStep
    inc RamPointer+1
InverseStep:
    NextRamPattern InverseWord

    ; Checks them, and goes on to SumSharedRam.
CheckInverse:
    FirstRamPattern
CheckInverseWord:
    lda #>Iwm::Phase0Off
    cmp RamPointer+1
    bne CheckInverseNotIo
    lda #>Iwm::Phase0Off + 1
    sta RamPointer+1
CheckInverseNotIo:
    lda #>SharedSlotPage
    cmp RamPointer+1
    beq SumSharedRam
    lda Pattern
    eor #$FF
    cmp (RamPointer)
    beq InverseLowOk
    jmp DiagnosticsFailed
InverseLowOk:
    inc RamPointer
    lda Pattern+1
    eor #$FF
    cmp (RamPointer)
    beq InverseHighOk
    jmp DiagnosticsFailed
InverseHighOk:
    inc RamPointer
    bne CheckInverseStep
    inc RamPointer+1
CheckInverseStep:
    NextRamPattern CheckInverseWord
.endproc

;; Puts the host's $CA00-$CBFF code at $0200-$03FF, then sums the RAM the host can see, as
;; <Diagnostics::CheckSharedData> does, and leaves the sum's complement in <SharedSum>: $0006-$07FF, $0C00-$3FFF,
;; $7C00-$7FFE, $0B00-$0BFF, the slot page and $0800-$09FF. Reports "Card RAM" passed and waits for the host's check.
.proc SumSharedRam
    ldy #0
Copy:
    lda DiagnosticsHostCode,y
    sta HostCode,y
    lda DiagnosticsHostCode+$0100,y
    sta HostCode+$0100,y
    dey
    bne Copy

    ; Puts in the stack the return address that the JSR below will push, so that it changes no byte of the sum.
    lda #>(Await+2)
    pha
    lda #<(Await+2)
    pha
    pla
    pla

    ; $0006-$07FF.
    stz SumPointer
    stz SumPointer+1
    lda #0
    ldy #6
    stz SharedSum
AddLow:
    clc
    adc (SumPointer),y
    iny
    bne AddLow
    inc SumPointer+1
    ldx #$08
    cpx SumPointer+1
    bne AddLow

    ; $0C00-$3FFF, the window's banks 3 to 15.
    ldx #$0C
    stx SumPointer+1
AddBanks:
    clc
    adc (SumPointer),y
    iny
    bne AddBanks
    inc SumPointer+1
    ldx #$40
    cpx SumPointer+1
    bne AddBanks

    ; $7C00-$7FFE, the host's $CC00-$CFFE.
    ldx #>SharedExpansion
    stx SumPointer+1
AddExpansion:
    clc
    adc (SumPointer),y
    iny
    bne AddExpansion
    inc SumPointer+1
    ldx #$7F
    cpx SumPointer+1
    bne AddExpansion
AddLast:
    clc
    adc (SumPointer),y
    iny
    cpy #$FF                        ; not $7FFF, the host's $CFFF
    bne AddLast

    ; $0B00-$0BFF.
    iny
    ldx #$0B
    stx SumPointer+1
AddPageB:
    clc
    adc (SumPointer),y
    iny
    bne AddPageB

    ; The slot page.
    ldx #>SharedSlotPage
    stx SumPointer+1
AddSlot:
    clc
    adc (SumPointer),y
    iny
    bne AddSlot

    ; $0800-$09FF, bank 2 but for the I/O page.
    ldx #$08
    stx SumPointer+1
AddWindow:
    clc
    adc (SumPointer),y
    iny
    bne AddWindow
    inc SumPointer+1
    ldx #$0A
    cpx SumPointer+1
    bne AddWindow

    ; Card RAM passed.
    eor #$FF
    sta SharedSum
    lda #REPORT_PASSED
    sta Report
Await:
    jsr AwaitHost
    ; Falls into TestUnits.
.endproc

;; Finds the units, lets the host list them, and tests units 1 and 2 if Apple's factory fixture is in slot 1.
;; Ends in <Idle>.
.proc TestUnits
    jsr ColdStart
    lda #STATE_WAITING
    sta CardState
    stz Signal                      ; done: the host lists the units
    jsr AwaitHost

    ; The fixture's ROM, which the host copied from slot 1.
    ldy #15
Compare:
    lda FixtureId,y
    cmp FixtureSignature,y
    bne Stop
    dey
    bpl Compare
    jmp Fixture
Stop:
    lda #SIGNAL_STOP
    sta Signal
    jmp Idle

    ; Units 1 and 2.
Fixture:
    lda UnitCount
    bne Some
    jmp Stop
Some:
    lda #1
    sta CardUnit
    jsr TestUnit
    lda UnitCount
    cmp #2
    bcc Done
    lda #2
    sta CardUnit
    jsr TestUnit
Done:
    lda #SIGNAL_STOP
    sta Signal
    jmp Idle
.endproc

;; Writes a block of a unit with a pattern and reads it back, then again with another, and tells the host; on a
;; failure, tells the host the block and goes to <Idle>. The second read's result is not checked.
;; In: CardUnit = the unit
.proc TestUnit
    jsr FillBuffers
    jsr WriteTestBlock
    bcs Failed
    jsr ReadTestBlock
    bcs Failed
    jsr FillSecondPattern
    jsr WriteTestBlock
    bcs Failed
    jsr ReadTestBlock
    stz Signal                      ; done
    lda Iwm::MotorOff
    jsr AwaitHost
    rts
Failed:
    lda Block
    sta FailedBlock
    lda Block+1
    sta FailedBlock+1
    lda #SIGNAL_READ_WRITE_FAILED
    sta Signal
    lda Iwm::MotorOff
    jmp Idle
.endproc

;; Writes the block the host's byte chooses (twice the byte, plus its bit 0: 0-511) from the last buffer, and keeps
;; a copy of what it wrote at <SavedBlock>.
;; In: CardUnit = the unit
;; Out: carry = set on an error
.proc WriteTestBlock
    jsr Swim::UseGcr
    lda #COMMAND_WRITE_BLOCK
    sta CardCommand

    ; The block: the byte shifted left, with its bit 0 shifted in.
    lda RandomBlock
    lsr a
    lda RandomBlock
    stz Block+1
    rol a
    sta Block
    rol Block+1

    ; The write, to the disk at once.
    lda #DATA_SENDING
    sta CardData
    sta TestCall
    lda #COMMAND_WRITE_BLOCK
    sta CardState
    jsr RunCommand
    stz TestCall
    bcs Done
    lda #STATE_WAITING
    sta CardState
Done:
    lda ErrorCode
    beq Keep
    sec
    rts

    ; The copy.
Keep:
    lda BufferCode
    jsr Cache::PointAtBuffer
    ldy #0
Copy:
    lda (BufferPointer),y
    sta SavedBlock,y
    lda (SecondBufferPointer),y
    sta SavedBlock+$0100,y
    iny
    bne Copy
    clc
    rts
.endproc

;; Reads the block <WriteTestBlock> wrote and compares it with the copy at <SavedBlock>.
;; In: CardUnit = the unit
;; Out: carry = set on an error or a difference
.proc ReadTestBlock
    jsr Swim::UseGcr
    lda #COMMAND_READ_BLOCK
    sta CardCommand

    ; The block, as WriteBlock chose it.
    lda RandomBlock
    lsr a
    lda RandomBlock
    stz Block+1
    rol a
    sta Block
    rol Block+1

    ; The read, from the disk.
    lda #DATA_SENDING
    sta CardData
    sta ForceRead
    lda #COMMAND_READ_BLOCK
    sta CardState
    jsr RunCommand
    lda #STATE_WAITING - 1          ; $FE: bit 7 set, so the card still waits
    sta CardState
    lda BufferCode
    jsr Cache::PointAtBuffer
    lda #DATA_SENDING
    sta CardData
    lda ErrorCode
    beq Compare
Failed:
    sec
    rts

    ; The comparison.
Compare:
    ldy #0
Byte:
    lda (BufferPointer),y
    cmp SavedBlock,y
    bne Failed
    lda (SecondBufferPointer),y
    cmp SavedBlock+$0100,y
    bne Failed
    iny
    bne Byte
    clc
    rts
.endproc

;; Fills the track's buffers with the second pattern, from <SECOND_SEED>.
;; Out: A = <END_BUFFER>
.proc FillSecondPattern
    ldy #SECOND_SEED
    bra FillBuffers::Seed
.endproc

;; Fills the track's buffers (<FIRST_BUFFER> up to <END_BUFFER>) with the first pattern, from <FIRST_SEED>, so that
;; a read must come from the disk.
;; Entry:
;;   Seed = fills them with the pattern that starts with Y
;; Out: A = <END_BUFFER>
;; Keeps: Y
.proc FillBuffers
    ldy #FIRST_SEED
Seed:
    lda #FIRST_BUFFER
Next:
    jsr FillBuffer
    inc a
    cmp #END_BUFFER
    bcc Next
    rts
.endproc

;; Fills a 512-byte buffer with Y rotated left through carry, set at first, a bit more at each byte.
;; In: A = the buffer's code, Y = the first byte
;; Keeps: A, Y
.proc FillBuffer
    pha
    jsr Cache::PointAtBuffer
    tya
    sec
    phy
    ldy #0
Byte:
    sta (BufferPointer),y
    sta (SecondBufferPointer),y
    rol a
    iny
    bne Byte
    ply
    pla
    rts
.endproc

;; The diagnostics' end: reads all of memory over and over, but for the SWIM's registers, whose reads have side
;; effects, until the host says to restart.
.proc Idle
    ldy #0
    sty RamPointer
    sty RamPointer+1
Byte:
    lda #>Iwm::Phase0Off
    cmp RamPointer+1
    bne Read
    tya
    and #$C0                        ; $0A00-$0A3F
    bne Read
    bra Next
Read:
    lda (RamPointer),y
Next:
    iny
    bne Byte
    inc RamPointer+1
    bne Byte
    lda Signal
    cmp #SIGNAL_EXIT
    bne Idle
    ; Falls into Restart.
.endproc

;; Tells the host the card is restarting, turns the LED on and restarts the card from its reset.
.proc Restart
    lda #0
    sta Signal
    sta LedOn
    nop
    nop
    nop
    nop
    jmp CardReset
.endproc

;; Waits for the host to let the card take its next step. If the host says to stop, goes to <Idle> instead, with
;; the caller's return address dropped.
;; Out: A = <SIGNAL_GO>
;; Keeps: X, Y
.proc AwaitHost
    lda Signal
    cmp #SIGNAL_GO
    bne NotGo
    rts
NotGo:
    cmp #SIGNAL_STOP
    bne AwaitHost
    pla
    pla
    jmp Idle
.endproc

;; Reports a test passed to the host, and waits for the host to see it.
;; Out: A = 0
;; Keeps: X, Y
.proc ReportPass
    lda #REPORT_PASSED
    sta Report
Wait:
    lda Report
    bne Wait
    rts
.endproc

;; Tests the SWIM. As the IWM, with the drives off: the data register reads $FF, and the mode register holds $1F,
;; $00 and $0F. Then as the ISM: the phases read <ISM_PHASES>, the mode shows the ISM, and the sixteen parameters
;; hold a walking one and a walking zero. Then as the IWM again.
;; Out: carry = set on a failure
.proc TestSwim

    ; The IWM, idle: reading, the phases and the motor off.
    bit Iwm::ReadMode
    bit Iwm::DataLatch
    bit Iwm::Phase0Off
    bit Iwm::Phase1Off
    bit Iwm::Phase2Off
    bit Iwm::Phase3Off
    bit Iwm::MotorOff
    lda Iwm::ReadMode               ; Q6 and Q7 off: the data register
    cmp #$FF
    beq DataOk
    sec
    rts

    ; Its mode, written and read back as $1F, $00 and $0F.
DataOk:
    lda #$1F
    bit Iwm::LoadLatch
    sta Iwm::WriteMode              ; Q6 and Q7 on: writes the mode
    eor Iwm::ReadMode               ; Q6 on and Q7 off: reads the status, the mode in its low five bits
    and #IWM_MODE_BITS
    beq Mode1F
    sec
    rts
Mode1F:
    lda #$00
    sta Iwm::WriteMode
    eor Iwm::ReadMode
    and #IWM_MODE_BITS
    beq Mode00
    sec
    rts
Mode00:
    lda #$0F
    bit Iwm::LoadLatch
    sta Iwm::WriteMode
    eor Iwm::ReadMode
    and #IWM_MODE_BITS
    beq Mode0F
    sec
    rts

    ; The ISM: its phases and its mode.
Mode0F:
    lda #ISM_SWITCH                 ; bit 6 written 1, 0, 1, 1: the ISM
    bit Iwm::LoadLatch
    sta Iwm::WriteMode
    eor #ISM_MODE
    sta Iwm::WriteMode
    eor #ISM_MODE
    sta Iwm::WriteMode
    sta Iwm::WriteMode
    lda #5
Settle:
    dec a
    bne Settle
    lda Ism::ReadPhase
    cmp #ISM_PHASES
    bne Failed
    lda Ism::ReadMode
    and #$C0
    cmp #ISM_MODE
    bne Failed

    ; Its parameters, a walking one and a walking zero.
    stz Ism::ClearMode              ; clears nothing, but starts the parameters again
    lda #$01
WriteOne:
    sta Ism::WriteParameter
    asl a
    bcc WriteOne
    lda #$FE
WriteZero:
    sta Ism::WriteParameter
    rol a
    bcs WriteZero
    stz Ism::ClearMode
    lda #$01
ReadOne:
    cmp Ism::ReadParameter
    bne Failed
    asl a
    bcc ReadOne
    lda #$FE
ReadZero:
    cmp Ism::ReadParameter
    bne Failed
    sec
    rol a
    bcs ReadZero
    bra BackToIwm
Failed:
    sec
    rts

    ; The IWM again, idle, and its mode.
BackToIwm:
    lda #$F8                        ; clears bit 6: the IWM again
    sta Ism::ClearMode
    bit Iwm::ReadMode
    bit Iwm::DataLatch
    bit Iwm::Phase0Off
    bit Iwm::Phase1Off
    bit Iwm::Phase2Off
    bit Iwm::Phase3Off
    bit Iwm::MotorOff
    lda Iwm::ReadMode
    cmp #$FF
    beq AgainDataOk
    sec
    rts
AgainDataOk:
    lda #$1F
    bit Iwm::LoadLatch
    sta Iwm::WriteMode
    eor Iwm::ReadMode
    and #IWM_MODE_BITS
    beq AgainMode1F
    sec
    rts
AgainMode1F:
    lda #$00
    sta Iwm::WriteMode
    eor Iwm::ReadMode
    and #IWM_MODE_BITS
    beq AgainMode00
    sec
    rts
AgainMode00:
    lda #$0F
    bit Iwm::LoadLatch
    sta Iwm::WriteMode
    eor Iwm::ReadMode
    and #IWM_MODE_BITS
    bne AgainFailed
    clc
    rts
AgainFailed:
    sec
    rts
.endproc

;; Checks the EPROM's checksum: the sum of every byte but <RomCheckByte> is 0, and that byte plus the sum's carries
;; is 0. A wrong sum goes to <StartUpFailed>, as at start-up, and does not report to the host.
;; Out: carry = set when the carries are wrong
.proc RomChecksum
    stz RomPointer
    lda #ROM_FIRST_PAGE
    sta RomPointer+1
    lda #0
    tax
    tay

    ; Every page but the last, counting the carries in X.
Add:
    clc
    adc (RomPointer),y
    bcc NoCarry
    inx
NoCarry:
    iny
    bne Add
    inc RomPointer+1
    tay
    lda RomPointer+1
    inc a
    beq LastPage
    tya
    ldy #0
    bra Add

    ; The last page, but for the check byte.
LastPage:
    tya
    ldy #0
AddLast:
    clc
    adc (RomPointer),y
    bcc LastNoCarry
    inx
LastNoCarry:
    iny
    beq Sum
    cpy #<RomCheckByte
    bne AddLast
    iny
    bra AddLast

    ; The sum, then the carries.
Sum:
    tay
    beq SumOk
    jmp StartUpFailed
SumOk:
    txa
    clc
    adc RomCheckByte
    beq Ok
    sec
    rts
Ok:
    clc
    rts
.endproc

;; Checks the CCITT CRC-16 (from 0, each byte's bits lowest first) of each 2 KB block of $8000-$F7FF against
;; <RomCrcs>. The last block holds the CRCs, so has none.
;; Out: carry = set on a failure
.proc RomCrc
    stz RomPointer
    lda #ROM_FIRST_PAGE
    sta RomPointer+1
NextBlock:
    stz Crc
    stz Crc+1
Byte:
    CrcBit 1
    CrcBit 0
    CrcBit 0
    CrcBit 0
    CrcBit 0
    CrcBit 0
    CrcBit 0
    CrcBit 0
    inc RomPointer
    beq Page
    jmp Byte
Page:
    inc RomPointer+1
    lda RomPointer+1
    sec
    sbc #ROM_FIRST_PAGE
    tax
    and #$07
    beq BlockDone
    jmp Byte

    ; A block's CRC against the table's.
BlockDone:
    txa                             ; pages done, 8 times the blocks
    clc
    ror a
    ror a
    ror a
    dec a
    asl a
    tax
    lda RomCrcs,x
    cmp Crc
    beq LowOk
Failed:
    sec
    rts
LowOk:
    lda RomCrcs+1,x
    cmp Crc+1
    bne Failed
    cpx #2 * (CRC_BLOCKS - 1)
    beq Ok
    jmp NextBlock
Ok:
    clc
    rts
.endproc

;; Checks that the slot page is the EPROM's, but for <WaitForDiagnostics>'s offset, which must be 0.
;; Out: carry = set on a difference
.proc VerifySlotPage
    ldx #0
Byte:
    cpx #<WaitForDiagnostics::Wait + 1
    bne Image
    lda #0
    bra Compare
Image:
    lda SlotPageImage,x
Compare:
    cmp SharedSlotPage,x
    bne Failed
    dex
    bne Byte
    clc
    rts
Failed:
    sec
    rts
.endproc

;; Copies the diagnostics' host code for $CC00-$CFFF to <SharedExpansion>.
;; Out: X = 0
.proc CopyExpansion
    ldx #0
Page0:
    lda DiagnosticsExpansion,x
    sta SharedExpansion,x
    dex
    bne Page0
Page1:
    lda DiagnosticsExpansion+$0100,x
    sta SharedExpansion+$0100,x
    dex
    bne Page1
Page2:
    lda DiagnosticsExpansion+$0200,x
    sta SharedExpansion+$0200,x
    dex
    bne Page2
Page3:
    lda DiagnosticsExpansion+$0300,x
    sta SharedExpansion+$0300,x
    dex
    bne Page3
    rts
.endproc

;; Checks the copy <CopyExpansion> made.
;; Out: carry = set on a difference
.proc VerifyExpansion
    ldx #0
Page0:
    lda DiagnosticsExpansion,x
    cmp SharedExpansion,x
    bne Failed
    dex
    bne Page0
Page1:
    lda DiagnosticsExpansion+$0100,x
    cmp SharedExpansion+$0100,x
    bne Failed
    dex
    bne Page1
Page2:
    lda DiagnosticsExpansion+$0200,x
    cmp SharedExpansion+$0200,x
    bne Failed
    dex
    bne Page2
Page3:
    lda DiagnosticsExpansion+$0300,x
    cmp SharedExpansion+$0300,x
    bne Failed
    dex
    bne Page3
    clc
    rts
Failed:
    sec
    rts
.endproc

;; Copies the diagnostics' page zero in.
;; Out: X = 0
.proc CopyDiagnosticsZeroPage
    ldx #0
Byte:
    lda DiagnosticsZeroPage,x
    sta PageZero,x
    dex
    bne Byte
    rts
.endproc

;; Checks the copy <CopyDiagnosticsZeroPage> made.
;; Out: carry = set on a difference
.proc VerifyZeroPage
    ldx #0
Byte:
    lda DiagnosticsZeroPage,x
    cmp PageZero,x
    bne Failed
    dex
    bne Byte
    clc
    rts
Failed:
    sec
    rts
.endproc

;; A failure of the diagnostics' own tests: reports it to the host, then blinks the LED, a long flash and two short
;; ones, until the host says to restart.
.proc DiagnosticsFailed
    lda #REPORT_FAILED
    sta Report
Blink:
    sta LedOff
    ldx #0                          ; off about 0.39 s (65536 times 12 cycles)
Off:
    lda #0
OffWait:
    dec a
    bne *+2                         ; goes on either way
    nop
    nop
    bne OffWait
    dex
    bne Off
    sta LedOn
    ldx #0                          ; on about 0.82 s (65536 times 25 cycles)
On:
    lda #0
OnWait:
    dec a
    bne *+2
    bne *+2
    bne *+2
    bne *+2
    bne *+2
    bne *+2
    nop
    bne OnWait
    dex
    bne On
    sta LedOff
    WaitMilliseconds $FF           ; off about 0.26 s
    sta LedOn
    WaitMilliseconds $96           ; on about 0.15 s
    sta LedOff
    WaitMilliseconds $FF
    sta LedOn
    WaitMilliseconds $96
    sta LedOff
    lda Signal
    cmp #SIGNAL_EXIT
    bne Blink
    jmp Restart
.endproc

.assert * = $9649, "The start-up test is at $9649, where the main firmware's reset goes."

;; The start-up test, which the main firmware's reset (<CardReset>) jumps to. Puts the slot page's start in place,
;; and checks the EPROM's checksum, the SWIM and some of the RAM; then turns the LED off and goes on with the main
;; firmware's start-up, <Startup>. A failure goes to <StartUpFailed>.
.proc StartUp

    ; The slot page's start, through SmartPortEntry::WaitForCard's offset.
    ldy #<SmartPortEntry::Wait + 1
Slot:
    lda SlotPageImage,y
    sta SharedSlotPage,y
    dey
    bpl Slot

    ; The EPROM's checksum, as RomChecksum does it.
    stz RomPointer
    lda #ROM_FIRST_PAGE
    sta RomPointer+1
    lda #0
    tax
    tay
Add:
    clc
    adc (RomPointer),y
    bcc NoCarry
    inx
NoCarry:
    iny
    bne Add
    inc RomPointer+1
    tay
    lda RomPointer+1
    inc a
    beq LastPage
    tya
    ldy #0
    bra Add
LastPage:
    tya
    ldy #0
AddLast:
    clc
    adc (RomPointer),y
    bcc LastNoCarry
    inx
LastNoCarry:
    iny
    beq Sum
    cpy #<RomCheckByte
    bne AddLast
    iny
    bra AddLast
Sum:
    tay
    beq SumOk
    jmp StartUpFailed
SumOk:
    txa
    clc
    adc RomCheckByte
    beq TestSwim
    jmp StartUpFailed

    ; The SWIM, as TestSwim tests it.
TestSwim:
    bit Iwm::ReadMode
    bit Iwm::DataLatch
    bit Iwm::Phase0Off
    bit Iwm::Phase1Off
    bit Iwm::Phase2Off
    bit Iwm::Phase3Off
    bit Iwm::MotorOff
    lda Iwm::ReadMode
    cmp #$FF
    beq DataOk
    jmp StartUpFailed
DataOk:
    lda #$1F
    bit Iwm::LoadLatch
    sta Iwm::WriteMode
    eor Iwm::ReadMode
    and #IWM_MODE_BITS
    beq Mode1F
    jmp StartUpFailed
Mode1F:
    lda #$00
    sta Iwm::WriteMode
    eor Iwm::ReadMode
    and #IWM_MODE_BITS
    beq Mode00
    jmp StartUpFailed
Mode00:
    lda #$0F
    bit Iwm::LoadLatch
    sta Iwm::WriteMode
    eor Iwm::ReadMode
    and #IWM_MODE_BITS
    beq Mode0F
    jmp StartUpFailed
Mode0F:
    lda #ISM_SWITCH                 ; bit 6 written 1, 0, 1, 1: the ISM
    bit Iwm::LoadLatch
    sta Iwm::WriteMode
    eor #ISM_MODE
    sta Iwm::WriteMode
    eor #ISM_MODE
    sta Iwm::WriteMode
    sta Iwm::WriteMode
    lda #5
Settle:
    dec a
    bne Settle
    lda Ism::ReadPhase
    cmp #ISM_PHASES
    bne SwimFailed
    lda Ism::ReadMode
    and #$C0
    cmp #ISM_MODE
    bne SwimFailed
    stz Ism::ClearMode
    lda #$01
WriteOne:
    sta Ism::WriteParameter
    asl a
    bcc WriteOne
    lda #$FE
WriteZero:
    sta Ism::WriteParameter
    rol a
    bcs WriteZero
    stz Ism::ClearMode
    lda #$01
ReadOne:
    cmp Ism::ReadParameter
    bne SwimFailed
    asl a
    bcc ReadOne
    lda #$FE
ReadZero:
    cmp Ism::ReadParameter
    bne SwimFailed
    sec
    rol a
    bcs ReadZero
    bra BackToIwm
SwimFailed:
    jmp StartUpFailed
BackToIwm:
    lda #$F8                        ; clears bit 6: the IWM again
    sta Ism::ClearMode
    bit Iwm::ReadMode
    bit Iwm::DataLatch
    bit Iwm::Phase0Off
    bit Iwm::Phase1Off
    bit Iwm::Phase2Off
    bit Iwm::Phase3Off
    bit Iwm::MotorOff
    lda Iwm::ReadMode
    cmp #$FF
    beq AgainDataOk
    jmp StartUpFailed
AgainDataOk:
    lda #$1F
    bit Iwm::LoadLatch
    sta Iwm::WriteMode
    eor Iwm::ReadMode
    and #IWM_MODE_BITS
    beq AgainMode1F
    jmp StartUpFailed
AgainMode1F:
    lda #$00
    sta Iwm::WriteMode
    eor Iwm::ReadMode
    and #IWM_MODE_BITS
    beq AgainMode00
    jmp StartUpFailed
AgainMode00:
    lda #$0F
    bit Iwm::LoadLatch
    sta Iwm::WriteMode
    eor Iwm::ReadMode
    and #IWM_MODE_BITS
    beq Ram
    jmp StartUpFailed

    ; The stack page, a rising count, and a byte in each of eight pages, for the address lines.
Ram:
    lda #0
    tax
FillStack:
    sta StackPage,x
    inc a
    inx
    bne FillStack
    lda #$01
    sta AddressCells+$0400
    asl a
    sta AddressCells+$0500
    asl a
    sta AddressCells+$0600
    asl a
    sta AddressCells+$0800
    asl a
    sta AddressCells+$1000
    asl a
    sta AddressCells+$1200
    asl a
    sta AddressCells+$2000
    asl a
    sta AddressCells+$4000
    lda #$01
    cmp AddressCells+$0400
    beq Cell0500
    jmp StartUpFailed
Cell0500:
    asl a
    cmp AddressCells+$0500
    beq Cell0600
    jmp StartUpFailed
Cell0600:
    asl a
    cmp AddressCells+$0600
    beq Cell0800
    jmp StartUpFailed
Cell0800:
    asl a
    cmp AddressCells+$0800
    beq Cell1000
    jmp StartUpFailed
Cell1000:
    asl a
    cmp AddressCells+$1000
    beq Cell1200
    jmp StartUpFailed
Cell1200:
    asl a
    cmp AddressCells+$1200
    beq Cell2000
    jmp StartUpFailed
Cell2000:
    asl a
    cmp AddressCells+$2000
    beq Cell4000
    jmp StartUpFailed
Cell4000:
    asl a
    cmp AddressCells+$4000
    beq CheckStack
    jmp StartUpFailed

    ; The rising count.
CheckStack:
    lda #0
    tax
CheckRising:
    cmp StackPage,x
    bne StackFailed
    inc a
    inx
    bne CheckRising
    bra Falling
StackFailed:
    jmp StartUpFailed

    ; A falling count.
Falling:
    lda #$FF
    ldx #0
FillFalling:
    sta StackPage,x
    dec a
    inx
    bne FillFalling
    lda #$FF
    ldx #0
CheckFalling:
    cmp StackPage,x
    bne FallingFailed
    dec a
    inx
    bne CheckFalling
    bra Recheck
FallingFailed:
    jmp StartUpFailed

    ; The eight bytes again, which writing the stack page must not have changed.
Recheck:
    lda #$01
    cmp AddressCells+$0400
    beq Recheck0500
    jmp StartUpFailed
Recheck0500:
    asl a
    cmp AddressCells+$0500
    beq Recheck0600
    jmp StartUpFailed
Recheck0600:
    asl a
    cmp AddressCells+$0600
    beq Recheck0800
    jmp StartUpFailed
Recheck0800:
    asl a
    cmp AddressCells+$0800
    beq Recheck1000
    jmp StartUpFailed
Recheck1000:
    asl a
    cmp AddressCells+$1000
    beq Recheck1200
    jmp StartUpFailed
Recheck1200:
    asl a
    cmp AddressCells+$1200
    beq Recheck2000
    jmp StartUpFailed
Recheck2000:
    asl a
    cmp AddressCells+$2000
    beq Recheck4000
    jmp StartUpFailed
Recheck4000:
    asl a
    cmp AddressCells+$4000
    bne StartUpFailed

    ; Passed.
    sta LedOff
    jmp Startup
.endproc

;; A failure of the start-up test: makes the slot page's start, its diagnostics entry and its call jump to the host's
;; Monitor (<ResetToMonitor>), releases Boot::WaitForCard and SmartPortEntry::WaitForCard into those jumps, clears the
;; SmartPort signature's $03 and the rest of the page, and blinks the LED, a long flash and a short one, for ever.
.proc StartUpFailed

    ; JMP ResetToMonitor at $Cn00, $Cn0D and $Cn23.
    stz SlotSignature
    lda #OPCODE_JMP
    sta SharedSlotPage
    sta SlotDiagnostics
    sta SlotCall
    lda #<ResetToMonitor
    sta SharedSlotPage+1
    sta SlotDiagnostics+1
    sta SlotCall+1
    lda #>ResetToMonitor
    sta SharedSlotPage+2
    sta SlotDiagnostics+2
    sta SlotCall+2

    ; The waits released, and the rest of the page cleared.
    stz BootWait
    stz CallWait
    ldx #<Call + 3
Clear:
    stz SharedSlotPage,x
    inx
    bne Clear

    ; The LED.
Blink:
    sta LedOff
    ldx #0                          ; off about 0.39 s
Off:
    lda #0
OffWait:
    dec a
    bne *+2                         ; goes on either way
    nop
    nop
    bne OffWait
    dex
    bne Off
    sta LedOn
    ldx #0                          ; on about 0.82 s
On:
    lda #0
OnWait:
    dec a
    bne *+2
    bne *+2
    bne *+2
    bne *+2
    bne *+2
    bne *+2
    nop
    bne OnWait
    dex
    bne On
    sta LedOff
    WaitMilliseconds $FF           ; off about 0.26 s
    sta LedOn
    WaitMilliseconds $96           ; on about 0.15 s
    sta LedOff
    jmp Blink
.endproc

;; <CardDiagnostics>'s patterns for page zero's first six bytes.
ZeroPagePatterns:
    .byte $00, $FF, $55, $AA, $CC, $33

;; Their complements.
ZeroPageInverse:
    .byte $FF, $00, $AA, $55, $33, $CC

;; The first 16 bytes of the ROM of Apple's factory fixture, in slot 1: a JMP to the Monitor, then its maker's name.
FixtureSignature:
    .byte OPCODE_JMP, <ResetToMonitor, >ResetToMonitor
    .byte "AVEX Manufact"
.assert * - FixtureSignature = 16, "The fixture's signature is 16 bytes."

    .res 217                        ; unused

.endscope
