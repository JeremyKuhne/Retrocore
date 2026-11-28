; retrocore: style=strict
; COMMODORE 1541 DOS: START-UP AND THE IDLE LOOP ($EA6E-$EC9D)
.scope Startup continued

;; The self-test's failure: blinks the LEDs the fault's number of times, pauses and repeats, for ever: once for zero
;; page (here, X = 0), twice the upper ROM, three times the lower, four the RAM. The count is kept in the stack pointer,
;; since RAM may be bad.
;; Entry:
;;   Numbered = X = TEMP, the failed test's number
;;   LedsLit = Where <BlinkFaultPatch> returns
;; Also: PEZRO (D1541)
.proc BlinkFault
    ldx #$00
    .byte $2C

;; X = TEMP, the failed test's number; PEZRO's `LDX #0` is followed by a `.byte $2C` (BIT) that skips this `LDX TEMP`,
;; as K-P3-Q4 documents for the kernal.
;; Also: PERR (D1541)
Numbered:
    ldx Temporary
    txs

;; The count again.
;; Also: PE20 (D1541)
Again:
    tsx

;; Both LEDs on, through <BlinkFaultPatch>.
;; Also: PE30 (D1541)
Blink:
    lda #$08
    ora DriveControl
    jmp BlinkFaultPatch

;; Where <BlinkFaultPatch> returns: waits with the LEDs lit.
;; Also: REA7D (D1541)
LedsLit:
    tya

;; 256 times...
;; Also: PD10 (D1541)
OnOuter:
    clc

;; ...256 counts.
;; Also: PD20 (D1541)
OnInner:
    adc #$01
    bne OnInner
    dey
    bne OnOuter
    lda DriveControl
    and #$F7
    sta DriveControl

;; The LEDs off: waits, and after the last blink waits three times more.
;; Also: PE40 (D1541)
Pause:
    tya

;; 256 times...
;; Also: PD11 (D1541)
OffOuter:
    clc

;; ...256 counts.
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

;; The reset vector's target (and UJ's): interrupts off, binary mode, `ResetPatch`; tests zero page, both ROMs'
;; checksums and RAM to $07FF, then sets the drive up (Initialize) and falls into the idle loop.
;; Entry:
;;   SelfTest = Where `ResetPatch` returns
;;   Initialize = The tests passed (and VNMI's target, so <Reinitialize> comes here)
;; Also: DSKINT (D1541)
.proc Reset
    sei
    cld
    ldx #$FF
.if LATE_PATCHES
    jmp ResetPatch
.else
    stx Via1DirectionA
.endif

;; Where `ResetPatch` returns: the self-test.
;; Also: DKIT10 (D1541)
SelfTest:
    inx
    ldy #$00
    ldx #$00

;; Each zero-page byte = its address.
;; Also: PU10 (D1541)
FillZeroPage:
    txa
    sta $00,x
    inx
    bne FillZeroPage

;; Each byte: still its address?
;; Also: PU20 (D1541)
CheckZeroPageByte:
    txa
    cmp $00,x
    bne BlinkFault

;; Incremented 256 times, it must come back; then zeroed, it must read 0.
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

;; An 8 KB ROM, from its top: the bytes summed with each carry added in must equal its first page, $E0 then $C0
;; (<UpperRomChecksum> makes it so).
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

;; Each byte.
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
    lda #$01
    sta Pointer+1
    inc Temporary
    ldx #$07

;; Pages 1-7, each byte its low address plus its page.
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

;; Each page, downwards...
;; Also: RA30 (D1541)
CheckRamPage:
    dec Pointer+1

;; ...each byte its pattern, then its inverse, then left 0.
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

;; On to <BlinkFault::Numbered>.
;; Also: PERR2 (D1541)
ToBlinkFault:
    jmp BlinkFault::Numbered

;; The tests passed (and VNMI's target, so <Reinitialize> comes here): the stack, the LEDs off, ATN's interrupt on VIA
;; 1's CA1, TLKADR and LSNADR from the jumpers on PB5 and PB6 ($48 and $28 for device 8), BUFTAB, the channels and
;; buffers free, the command and error channels, the user table, the LRU table, the controller (CNTINT), VNMI, SECINC,
;; REVCNT, message 73, the bus lines released, and BOOT.
;; Also: DIAGOK (D1541)
Initialize:
    ldx #Controller::OVERFLOW_SIZE
    txs
    lda DriveControl
    and #$F7
    sta DriveControl
    lda #$01
    sta Via1PeripheralControl
    lda #$82
    sta Via1InterruptFlags
    sta Via1InterruptEnable
    lda Via1PortB
    and #$60
    asl
    rol
    rol
    rol
    ora #$48
    sta Serial::TalkAddress
    eor #$60
    sta Serial::ListenAddress
    ldx #$00
    ldy #$00

;; Each buffer's pointer, page from <BufferPages>; then the command and error buffers'.
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

;; LINTAB's entries $FF: no secondary address has a channel.
;; Also: DSKIN1 (D1541)
ClearChannelTable:
    sta SecondaryChannels,x
    dex
    bpl ClearChannelTable
    ldx #CHANNEL_COUNT-1

;; Each channel's BUF0, BUF1 and SS $FF: no buffer.
;; Also: DSKIN2 (D1541)
FreeBuffers:
    sta ChannelBuffer,x
    sta ChannelSecondBuffer,x
    sta ChannelSideSector,x
    dex
    bpl FreeBuffers
    lda #BUFFER_COUNT
    sta $AB
    lda #BUFFER_COUNT+1
    sta $AC
    lda #$FF
    sta $AD
    sta $B4
    lda #MESSAGE_CHANNEL
    sta $023B
    lda #COMMAND_CHANNEL+128
    sta $023A
    lda #FREE_CHANNELS
    sta FreeChannels
    lda #CHANNEL_LISTEN
    sta $F6
    lda #CHANNEL_TALK
    sta $F7
    lda #$E0
    sta BuffersInUse
    lda #$FF
    sta BuffersInUse+1
    lda #$01
    sta DiskChanged
    sta DiskChanged+1
    jsr Commands::User::Reset
    jsr Files::ResetUseOrder
    jsr Controller::Initialize
    lda #<Initialize
    sta NmiVector
    lda #>Initialize
    sta NmiVector+1
    lda #$0A
    sta SectorInterleave
    lda #$05
    sta Jobs::Retries
    lda #$73
    jsr Errors::SetMessageWithoutBlock
.if LATE_PATCHES
    lda #$00
    sta Via1PortB
    lda #$1A
    sta Via1DirectionB
.else
    lda #$1A
    sta Via1DirectionB
    lda #$00
    sta Via1PortB
.endif
    jsr Boot
.endproc
.endscope
.scope Idle continued

;; Releases CLK, DATA and ATNA, runs a waiting command (CMDWAT: PARSXQ), then loops: HandleAtn when ATNPND is set; the
;; activity LED on while a file is open or a job runs; the error LED's flashing. Reset falls into it.
;; Also: IDLE (D1541)
.proc Loop
    cli
    lda Via1PortB
    and #$E5
    sta Via1PortB
    lda CommandWaiting
    beq NextPass
    lda #$00
    sta CommandWaiting
    sta NmiDebounce
    jsr Commands::Execute

;; Each pass: ATN pending?
;; Also: IDL1 (D1541)
NextPass:
    cli
    lda AtnPending
    beq CountActive
    jmp Serial::HandleAtn

;; TEMP and TEMP+1 count each drive's open files and jobs.
;; Also: IDL01 (D1541)
CountActive:
    cli
    lda #$0E
    sta Temporary+3
    lda #$00
    sta Temporary
    sta Temporary+1

;; Each LINTAB entry: a file open on which drive (LSTJOB)?
;; Also: IDL2 (D1541)
NextChannel:
    ldx Temporary+3
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

;; The next.
;; Also: IDL3 (D1541)
SkipChannel:
    dec Temporary+3
    bpl NextChannel
    ldy #BUFFER_COUNT-1

;; Each job still running, by its drive bit.
;; Also: IDL4 (D1541)
NextJob:
    lda a:JobQueue,y
    bpl SkipJob
    and #$01
    tax
    inc Temporary,x

;; The next; then drive 0: active, its channels closed (CLDCHN) if WPSW is set.
;; Also: IDL5 (D1541)
SkipJob:
    dey
    bpl NextJob
    sei
    lda DriveControl
    and #$F7
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

;; LED0 on.
;; Also: IDL6 (D1541)
LightDrive0:
    pla
    ora #LED_DRIVE0
    pha

;; Drive 1, as drive 0 (LED1 is 0).
;; Also: IDL7 (D1541)
Drive1:
    inc DriveNumber
    lda Temporary+1
    beq CheckFlashing
    lda DiskChanged+1
    beq LightDrive1
    jsr Files::FreeDriveChannels

;; LED1 on.
;; Also: IDL8 (D1541)
LightDrive1:
    pla
    ora #LED_DRIVE1
    pha

;; DRVNUM back; flashing while ERWORD is set (its $80 test is never true, Q10).
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

;; Each count waits for VIA 1's timer 1 (TIMER1) to fall below $8000, about 8 ms from $A0xx.
;; Also: IDL10 (D1541)
Timing:
    ldx Via1Timer1High
    bmi SetLeds
    ldx #$A0
    stx Via1Timer1High

;; ERWORD down one; at 0 the LED toggles (ERLED) and the count starts again at 16.
;; Also: IDL11 (D1541)
CountDown:
    dec ErrorFlash
    bne SetLeds
    eor ErrorLed
    ldx #$10
    stx ErrorFlash

;; Writes LEDPRT, and the next pass.
;; Also: IDL12 (D1541)
SetLeds:
    sta DriveControl
    jmp NextPass
.endproc
.endscope
