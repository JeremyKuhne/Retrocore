; retrocore: style=strict
; COMMODORE 1541 DOS: START-UP AND THE IDLE LOOP ($EA6E-$EC9D)

; Start-up: what the reset vector runs, a self-test and the set-up of the DOS's tables, and the blinking of the LEDs
; when the self-test fails. The rest of Startup is in other pieces: the boot loader (Dos1541.Errors.asm) and the
; reset's patches, the NMI and the ROM checksum (Dos1541.Tables.asm).
.scope Startup continued

; The set-up's values.

;; The value for <Via1InterruptFlags> and <Via1InterruptEnable> that clears and enables ATN's interrupt: bit 1 is CA1,
;; which ATN drives, and bit 7 makes a write to the enable register set the bits rather than clear them.
ATN_INTERRUPT = %10000010

;; <Via1PortB>'s bits 5 and 6: the jumpers that add 0 to 3 to the device number.
DEVICE_JUMPERS = %01100000

;; <Serial::TalkAddress> with no jumper added: the TALK command, $40, with device number 8, the first disk drive's.
DEFAULT_TALK_ADDRESS = $48

;; The sectors <SectorInterleave> starts at between a file's blocks.
INITIAL_INTERLEAVE = 10

;; The tries <Jobs::Retries> starts at for a failed job.
INITIAL_RETRIES = 5

;; The self-test's failure: blinks the activity LED, for ever. The number of blinks says what failed: one for zero page,
;; two for the upper ROM, three for the lower, four for the RAM. The count is kept in the stack pointer, since the RAM
;; may be bad. After the blinks the LED stays dark for three more off-delays, each half a blink, and it starts again.
;;
;; It never returns: the drive stays here until it is reset. Zero page's failure comes in at the top, with X = 0; the
;; others at `Numbered`, with the failed test's number in <Temporary>.
;; Entry:
;;   Numbered = The failed test's number, from <Temporary>, becomes the count of blinks less one
;;   LedsLit = Where <BlinkFaultPatch> returns, with the LEDs on
;; Also: PEZRO (D1541)
.proc BlinkFault
    ldx #$00
    .byte OPCODE_BIT                ; skips Numbered's LDX, so zero page's count stays 0
    .assert * = Numbered, "BlinkFault's BIT must take Numbered's instruction as its operand."

;; The other tests' entry: the count is the test's number in <Temporary>, and goes into the stack pointer.
;; Also: PERR (D1541)
Numbered:
    ldx Temporary
    txs

;; Starts the blinks again, with the whole count.
;; Also: PE20 (D1541)
Again:
    tsx

;; One blink: lights the activity LED (<LED_DRIVE0>; <LED_DRIVE1> is 0 and adds nothing), through <BlinkFaultPatch>,
;; which also makes VIA 2's port B drive the LEDs.
;; Also: PE30 (D1541)
Blink:
    lda #LED_DRIVE0 + LED_DRIVE1
    ora DriveControl
    jmp BlinkFaultPatch

;; Where <BlinkFaultPatch> returns, the LEDs lit: waits with them on, a delay loop in which Y counts the outer passes
;; down to 0 and A the inner ones up to 256.
;; Also: REA7D (D1541)
LedsLit:
    tya

;; The delay, LEDs on: the first outer pass starts the inner count from Y, the later ones from 0...
;; Also: PD10 (D1541)
OnOuter:
    clc

;; ...and counts to 256. When the passes are done the LEDs go off.
;; Also: PD20 (D1541)
OnInner:
    adc #$01
    bne OnInner
    dey
    bne OnOuter
    lda DriveControl
    and #$FF - LED_DRIVE0 - LED_DRIVE1
    sta DriveControl

;; The same delay, LEDs off. It counts the blinks down in X as well: another blink while X stays 0 or more, then it
;; waits three more times (X down to $FC) before it starts over.
;; Also: PE40 (D1541)
Pause:
    tya

;; The delay, LEDs off: each outer pass...
;; Also: PD11 (D1541)
OffOuter:
    clc

;; ...counts to 256.
;; Also: PD21 (D1541)
OffInner:
    adc #$01
    bne OffInner
    dey
    bne OffOuter
    dex
    bpl Blink
    cpx #$FC
    bne Pause
    beq Again
.endproc

;; The reset vector's target, which the user command UJ also reaches: sets the processor up, tests the drive, sets its
;; tables up and runs the boot loader, and falls into the idle loop. It never returns.
;;
;; The tests are zero page (each byte takes its own address, counts up 256 times back to it and clears), both 8 KB ROMs
;; (each sums to its own first page) and the RAM to $07FF (an address-sensitive pattern, then its inverse). A failure
;; blinks the LEDs in <BlinkFault>. Then <Reset::Initialize> sets up the drive.
;;
;; With interrupts off and binary mode set it makes VIA 1's port A all outputs. In -05 and -06 that is done in a patch
;; (`ResetPatch`), which also sets up the bus lines for the self-test and returns at `SelfTest`.
;; Entry:
;;   SelfTest = The self-test, after port A's set-up
;;   Initialize = The tests passed, and where the NMI vector points, so <Reinitialize> comes here
;; Also: DSKINT (D1541)
.proc Reset
    sei
    cld
    ldx #$FF
.if LATE_PATCHES
    ; -05 and -06: the patch sets the port and returns to SelfTest.
    jmp ResetPatch
.else
    ; Before -05: only the port's directions.
    stx Via1DirectionA
.endif

;; The self-test, after port A's set-up: X is $FF, so it wraps to 0.
;; Also: DKIT10 (D1541)
SelfTest:
    inx
    ldy #$00
    ldx #$00

;; Fills zero page, each byte with its own address.
;; Also: PU10 (D1541)
FillZeroPage:
    txa
    sta $00,x
    inx
    bne FillZeroPage

;; Each byte: does it still hold its address? If not, the failure is zero page's, and blinks once.
;; Also: PU20 (D1541)
CheckZeroPageByte:
    txa
    cmp $00,x
    bne BlinkFault

;; Increments the byte 256 times, which must bring it back to the address; then zeroes it, and it must read 0.
;; Also: PU30 (D1541)
CountUp:
    inc $00,x
    iny
    bne CountUp
    cmp $00,x
    bne BlinkFault
    sty $00,x
    lda $00,x
    bne BlinkFault
    inx
    bne CheckZeroPageByte

;; Tests an 8 KB ROM, first the upper one, then the lower: counts <Temporary> up for the failure blinks, then sums the
;; ROM's bytes from the top page down, each carry added into the next byte. The sum, with the last carry, must equal the
;; ROM's first page, $E0 or $C0; the <UpperRomChecksum> byte makes it so for the upper and <LowerRomChecksum> for the
;; lower. After both it goes on.
;; Also: RM10 (D1541)
TestRom:
    inc Temporary
    stx Pointer+1
    lda #$00
    sta Pointer
    tay
    ldx #$20
    clc

;; Each page, downwards.
;; Also: RT10 (D1541)
NextPage:
    dec Pointer+1

;; Each byte of the page.
;; Also: RT20 (D1541)
AddByte:
    adc (Pointer),y
    iny
    bne AddByte
    dex
    bne NextPage
    adc #$00
    tax
    cmp Pointer+1
    bne ToBlinkFault
    cpx #$C0
    bne TestRom

    ; The RAM: <Temporary> counts up once more for its failure blinks; the pages from 1 to 7, with their count in X.
    lda #$01
    sta Pointer+1
    inc Temporary
    ldx #$07

;; Fills pages 1 to 7, each byte with its low address plus its page: a pattern in which no two bytes of a page share a
;; value.
;; Also: RA10 (D1541)
FillRam:
    tya
    clc
    adc Pointer+1
    sta (Pointer),y
    iny
    bne FillRam
    inc Pointer+1
    dex
    bne FillRam
    ldx #$07

;; Checks each page, downwards...
;; Also: RA30 (D1541)
CheckRamPage:
    dec Pointer+1

;; ...each byte, from the top: it must hold the pattern; then it gets the pattern's inverse, which must read back; then
;; it is left 0. Any difference blinks four times.
;; Also: RA40 (D1541)
CheckRamByte:
    dey
    tya
    clc
    adc Pointer+1
    cmp (Pointer),y
    bne ToBlinkFault
    eor #$FF
    sta (Pointer),y
    eor (Pointer),y
    sta (Pointer),y
    bne ToBlinkFault
    tya
    bne CheckRamByte
    dex
    bne CheckRamPage
    beq Initialize

;; A ROM or RAM failure: on to <BlinkFault::Numbered>, with the test's number in <Temporary>.
;; Also: PERR2 (D1541)
ToBlinkFault:
    jmp BlinkFault::Numbered

;; The tests passed, and the NMI vector points here (<Reinitialize> jumps through it), so a reinitialization comes with
;; no self-test. It sets up everything the DOS keeps in RAM, in this order:
;;
;; - the stack, the LEDs off, and the ATN interrupt on VIA 1's CA1; - the drive's talk and listen addresses, from the
;; device jumpers: <DEFAULT_TALK_ADDRESS> with the jumpers' number; - the buffers' pointers, <BufferPositions>, from
;; <BufferPages>, and those of the command and error buffers; - the channels and secondary addresses, free, with the
;; command and error channels taken; - the buffers' use, the disk changed flags, the user commands' vectors, the use
;; order of the channels, the
;;   controller and its mechanism, the NMI vector, the sector interleave and the retries;
;; - message 73, the DOS version, as the error channel's first message; - the bus lines: in -05 and -06 released and
;; then driven, before -05 and in the 1540 driven and then released; - the boot loader, and then the idle loop.
;;
;; It does not return: it falls into the idle loop.
;; Also: DIAGOK (D1541)
Initialize:
    ; The stack, and the LEDs off.
    ldx #Controller::OVERFLOW_SIZE
    txs
    lda DriveControl
    and #$FF - LED_DRIVE0 - LED_DRIVE1
    sta DriveControl

    ; ATN's interrupt: CA1's edge selected, its flag cleared and the interrupt enabled.
    lda #$01
    sta Via1PeripheralControl
    lda #ATN_INTERRUPT
    sta Via1InterruptFlags
    sta Via1InterruptEnable

    ; The talk address: the jumpers' bits 5 and 6, rotated down to bits 0 and 1 and ORed into the default; the listen
    ; address is the talk address with the TALK command's bit exchanged for LISTEN's, $40 for $20, by exclusive OR.
    lda Via1PortB
    and #DEVICE_JUMPERS
    asl
    rol
    rol
    rol
    ora #DEFAULT_TALK_ADDRESS
    sta Serial::TalkAddress
    eor #$60
    sta Serial::ListenAddress

    ; The buffers' pointers: the low byte 0 and the page of each data buffer...
    ldx #$00
    ldy #$00

;; Each data buffer's pointer, its page from <BufferPages>; then the command and error buffers' pointers.
;; Also: INTT1 (D1541)
NextBuffer:
    lda #$00
    sta BufferPositions,x
    inx
    lda BufferPages,y
    sta BufferPositions,x
    inx
    iny
    cpy #BUFFER_COUNT
    bne NextBuffer
    lda #<CommandBuffer
    sta BufferPositions,x
    inx
    lda #>CommandBuffer
    sta BufferPositions,x
    inx
    lda #<ErrorBuffer
    sta BufferPositions,x
    inx
    lda #>ErrorBuffer
    sta BufferPositions,x
    lda #$FF
    ldx #LAST_SECONDARY

;; Marks every secondary address as having no channel, $FF in <SecondaryChannels>.
;; Also: DSKIN1 (D1541)
ClearChannelTable:
    sta SecondaryChannels,x
    dex
    bpl ClearChannelTable
    ldx #CHANNEL_COUNT-1

;; Frees each channel's buffers: $FF in <ChannelBuffer>, <ChannelSecondBuffer> and <ChannelSideSector>, for the six
;; channels.
;; Also: DSKIN2 (D1541)
FreeBuffers:
    sta ChannelBuffer,x
    sta ChannelSecondBuffer,x
    sta ChannelSideSector,x
    dex
    bpl FreeBuffers

    ; The command and error channels take their buffers, numbers 5 and 6, and the BAM's channel has none.
    lda #BUFFER_COUNT
    sta ChannelBuffer + COMMAND_CHANNEL
    lda #BUFFER_COUNT+1
    sta ChannelBuffer + MESSAGE_CHANNEL
    lda #$FF
    sta ChannelBuffer + BAM_CHANNEL
    sta ChannelSecondBuffer + BAM_CHANNEL

    ; Secondary address 15 is the command channel, for writing (bit 7); the internal secondary address 16 is the error
    ; channel, which reading 15 is switched to.
    lda #MESSAGE_CHANNEL
    sta SecondaryChannels + MESSAGE_SECONDARY
    lda #COMMAND_CHANNEL + $80
    sta SecondaryChannels + COMMAND_SECONDARY
    lda #FREE_CHANNELS
    sta FreeChannels

    ; The command channel is ready to listen, the error channel ready to talk.
    lda #CHANNEL_LISTEN
    sta ChannelStatus + COMMAND_CHANNEL
    lda #CHANNEL_TALK
    sta ChannelStatus + MESSAGE_CHANNEL

    ; The buffers in use: bits 5 to 15 set, since there are five, and each drive's disk "changed", so that it is read
    ; before its first use.
    lda #$E0
    sta BuffersInUse
    lda #$FF
    sta BuffersInUse+1
    lda #$01
    sta DiskChanged
    sta DiskChanged+1

    ; The user commands' vectors, the channels' use order and the controller.
    jsr Commands::User::Reset
    jsr Files::ResetUseOrder
    jsr Controller::Initialize

    ; The NMI vector: back to here, so UI alone reinitializes the drive.
    lda #<Initialize
    sta NmiVector
    lda #>Initialize
    sta NmiVector+1

    ; The interleave and the retries, and the error channel's first message: 73, the DOS version.
    lda #INITIAL_INTERLEAVE
    sta SectorInterleave
    lda #INITIAL_RETRIES
    sta Jobs::Retries
    lda #ERROR_DOS_VERSION
    jsr Errors::SetMessageWithoutBlock

; The bus: CLK, DATA and ATNA released, and port B's ATNA, CLK and DATA bits made outputs.
.if LATE_PATCHES
    ; -05 and -06 release the lines first, then set the directions, which `ResetPatch` has set already.
    lda #$00
    sta Via1PortB
    lda #Serial::ATN_ACKNOWLEDGE | Serial::CLOCK_OUT | Serial::DATA_OUT
    sta Via1DirectionB
.else
    ; Before -05 the directions come first, then the lines are released.
    lda #Serial::ATN_ACKNOWLEDGE | Serial::CLOCK_OUT | Serial::DATA_OUT
    sta Via1DirectionB
    lda #$00
    sta Via1PortB
.endif

    ; The boot loader, which before -05 runs a utility if a clip is on the bus and in -05 and -06 returns at once.
    jsr Boot
    ; Falls into Idle::Loop.
    .assert * = Idle::Loop, "Reset falls into the idle loop."
.endproc
.endscope

; The idle loop itself, which the reset falls into.
.scope Idle continued

;; The idle loop, which the DOS runs when the bus and the controller have nothing for it. Entering it at `Loop` releases
;; CLK, DATA and ATNA and runs a command that is waiting in the command channel. Every pass ends by jumping to
;; <Idle::Loop::NextPass>, so only that entry does those two things. Each pass serves ATN when the interrupt has left it
;; pending (<Serial::HandleAtn>, which ends in this loop again), lights the activity LED for a drive while a file is
;; open or a job runs on it, and flashes the error LED. It never returns.
;; Also: IDLE (D1541)
.proc Loop
    ; Releases the bus lines, and runs a command that the command channel has completed.
    cli
    lda Via1PortB
    and #$FF - Serial::ATN_ACKNOWLEDGE - Serial::CLOCK_OUT - Serial::DATA_OUT
    sta Via1PortB
    lda CommandWaiting
    beq NextPass
    lda #$00
    sta CommandWaiting
    sta NmiDebounce
    jsr Commands::Execute

;; Each pass starts here: has ATN set <AtnPending>? Then the computer wants the bus.
;; Also: IDL1 (D1541)
NextPass:
    cli
    lda AtnPending
    beq CountActive
    jmp Serial::HandleAtn

;; Counts, for each drive, its open files and its running jobs: drive 0's in <Temporary>, drive 1's in <Temporary1>. The
;; secondary addresses go first, 14 down to 0, counted in <Temporary3>.
;; Also: IDL01 (D1541)
CountActive:
    cli
    lda #COMMAND_SECONDARY-1
    sta Temporary3
    lda #$00
    sta Temporary
    sta Temporary1

;; Each <SecondaryChannels> entry that is not $FF is a file open: its channel's active buffer's last job (<LastJobs>)
;; says which drive it is on.
;; Also: IDL2 (D1541)
NextChannel:
    ldx Temporary3
    lda SecondaryChannels,x
    cmp #$FF
    beq SkipChannel
    and #$3F
    sta Channel
    jsr Files::GetActiveBuffer
    tax
    lda LastJobs,x
    and #$01
    tax
    inc Temporary,x

;; The next secondary address; then the jobs.
;; Also: IDL3 (D1541)
SkipChannel:
    dec Temporary3
    bpl NextChannel
    ldy #BUFFER_COUNT-1

;; Each job in the queue with its top bit set is still running: its drive bit says which drive it is for.
;; Also: IDL4 (D1541)
NextJob:
    lda a:JobQueue,y
    bpl SkipJob
    and #$01
    tax
    inc Temporary,x

;; The next job. Then the LEDs, with interrupts off, since an interrupt changes <DriveControl>: the new value is built
;; on the stack, from the current one less the drive's LED, and <DriveNumber> is kept in <Work0>. Drive 0 is busy if
;; <Temporary> is nonzero; if its <DiskChanged> flag is also set, its channels are closed first
;; (<Files::FreeDriveChannels>).
;; Also: IDL5 (D1541)
SkipJob:
    dey
    bpl NextJob
    sei
    lda DriveControl
    and #$FF - LED_DRIVE0
    pha
    lda DriveNumber
    sta Work0
    lda #$00
    sta DriveNumber
    lda Temporary
    beq Drive1
    lda DiskChanged
    beq LightDrive0
    jsr Files::FreeDriveChannels

;; The busy drive's LED on.
;; Also: IDL6 (D1541)
LightDrive0:
    pla
    ora #LED_DRIVE0
    pha

;; Drive 1, the same with its own counter and flag; its LED bit is 0, since the 1541 has no second drive.
;; Also: IDL7 (D1541)
Drive1:
    inc DriveNumber
    lda Temporary1
    beq CheckFlashing
    lda DiskChanged+1
    beq LightDrive1
    jsr Files::FreeDriveChannels

;; The busy drive's LED on (a bit that is 0).
;; Also: IDL8 (D1541)
LightDrive1:
    pla
    ora #LED_DRIVE1
    pha

;; Puts <DriveNumber> back, and takes the LEDs from the stack. While <ErrorFlash> is nonzero the error LED is flashing,
;; and the LEDs' current state is used instead, so the flash is not lost. The listing's special case, a count of $80,
;; the flash's first pass, never happens: <Errors::StartFlashing> starts the count at $50, so the test always goes on to
;; the timer.
;; Also: IDL9 (D1541)
CheckFlashing:
    lda Work0
    sta DriveNumber
    pla
    ldx ErrorFlash
    beq SetLeds
    lda DriveControl
    cpx #$80
    bne Timing
    jmp CountDown

;; Times one unit of the flash: VIA 1's timer 1, started at $A0xx, takes about 8 milliseconds to fall below $8000. While
;; it is still above, nothing counts; once it has fallen, it is started again and one unit counts.
;; Also: IDL10 (D1541)
Timing:
    ldx Via1Timer1High
    bmi SetLeds
    ldx #$A0
    stx Via1Timer1High

;; One unit counted off <ErrorFlash>. When it reaches 0 the error LED's bit (<ErrorLed>) is toggled, and the count
;; starts again from 16 units.
;; Also: IDL11 (D1541)
CountDown:
    dec ErrorFlash
    bne SetLeds
    eor ErrorLed
    ldx #$10
    stx ErrorFlash

;; Sets the LEDs in <DriveControl>, and starts the next pass.
;; Also: IDL12 (D1541)
SetLeds:
    sta DriveControl
    jmp NextPass
.endproc
.endscope
