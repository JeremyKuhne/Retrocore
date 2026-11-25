; retrocore: style=strict
;; THE APPLE II 3.5 DISK CONTROLLER CARD'S OWN FIRMWARE ($D000-$FFFF)
;;
;; What the card's 65C02 runs: it waits for the host's commands in its page zero, and answers ProDOS and
;; SmartPort calls for up to two 3.5 drives on its own port (the Apple 3.5 Drive, GCR 400K and 800K, and the
;; Apple FDHD, which adds MFM 720K and 1440K) and for SmartPort bus devices such as the UniDisk 3.5 on its
;; second port, which it passes their calls to. Assembles byte-identically as part of Disk35Controller.asm; this
;; file holds the start-up, the command loop and the ROM's last page, and includes the subject files between.
;;
;; THE UNITS
;;
;; Unit 0 is the controller. Units 1 and 2 are the 3.5 drives found at startup (drive 2 only if drive 1 is
;; there), and the bus devices follow, up to unit 4. <DeviceKinds> holds each unit's device, <UnitCount> their
;; number.
;;
;; THE MAILBOX
;;
;; The host writes its command at <CardState> ($00) once bit 7 there says the card waits, after setting <CardData>
;; to $FF and copying its command, unit and parameters to $02-$0A. <RunCommand> runs it. Data moves through 512-byte
;; buffers in the card's RAM, named by a code: the card address divided by $200, which is the host's bank (code / 2)
;; and half (code & 1) of its $C800-$CBFF window. A handler that has data for the host, or wants data from it,
;; puts the buffer's code in <CardData> and waits for the host to OR in $F0; a handler that is done puts 0 there with
;; the error in <ErrorCode> ($56). <MainLoop> then sets <CardState> to $FF again.
;;
;;   Code 6 ($0C00-$0DFF)        status lists, control lists, a block being written, READ/WRITE's 524 bytes
;;   Codes $08-$19 ($1000-$33FF) the sector cache: a track's 18 slots, one per sector
;;
;; THE COMMANDS AT CARDSTATE
;;
;;   $00-$0B  SmartPort's command less its extended bit ($40); a ProDOS call arrives as SmartPort's 0-3 with
;;            <CardCommand> bit 7 set
;;   $0C      the slot ROM's boot: read block 0 of unit 1
;;   $0D/$0E  READAHEAD and READSPAN, which the slot ROM does not use
;;   $3D      run the diagnostics at $8F00
;;   $7E/$7F  the host is not / is a IIgs (the host's <Host::Identity>)

; The host's code, which the card copies out and then changes to release the host.

;; Where in the slot page the boot's wait, <Boot::WaitForCard>, keeps its branch offset.
BOOT_WAIT_OFFSET = <(Boot::WaitForCard + 1)

;; The offset that sends the boot's wait on to the host's <Call>, which the card writes once it is ready.
BOOT_WAIT_TO_CALL = <(Call - Boot::WaitForCard - 2)
.assert BOOT_WAIT_TO_CALL = $16, "The boot's wait branches $16 bytes on, to Call."

;; Where in the slot page the calls' wait, <SmartPortEntry::Wait>, keeps its branch offset; 0 there releases the calls.
CALL_WAIT_OFFSET = <(SmartPortEntry::Wait + 1)

;; Where in the host's $CC00 page its <Host::Identity> is: bit 7 not yet known, bit 6 a IIgs.
HOST_TYPE_OFFSET = <Host::Identity
.assert Host::Identity = $CC00 + HOST_TYPE_OFFSET, "Host::Identity is in the host's $CC00 page."

;; The host type's bit 6: the host is a IIgs.
HOST_IIGS = $40

;; The 65C02's RTS, which the card puts at each unit's hook.
OPCODE_RTS = $60

; The card's RAM.

;; A GCR sector's nibbles for <WRITEDATAGCR>: the first of three 175-byte lanes.
NibbleLane1 = $0100

;; A sector's 12 tag bytes, as <READDATAGCR> reads them.
TagBytes = $01B2

;; The host's $C800 code, which the host runs at $CA00-$CBFF with bank 0 latched.
HostCode = $0200

;; FORMAT's sector order; READSPAN's count and buffer codes.
InterleaveMap = $0600

;; A track's sectors: $40 done, 0 wanted, $C0 not wanted.
SectorFlags = $0620

;; The second lane of a GCR sector's nibbles.
NibbleLane2 = $0640

;; The third lane of a GCR sector's nibbles.
NibbleLane3 = $0741

;; Each cache slot's cylinder, indexed from slot 1.
CacheCylinders = $0B00

;; Each cache slot's sector, indexed from slot 1.
CacheSectors = $0B20

;; Each cache slot's owner: its drive, <CACHE_EMPTY>, $8E not a 3.5 sector, $8F filling, or <CACHE_KEPT>.
CacheOwners = $0B40

;; The host's hook for unit 1, an RTS until something is loaded there.
UnitHook1 = $0B80

;; The host's hook for unit 2.
UnitHook2 = $0BA0

;; The host's hook for unit 3.
UnitHook3 = $0BC0

;; The host's hook for unit 4.
UnitHook4 = $0BE0

;; Buffer code 6, where lists and single blocks move.
TransferBuffer = $0C00

; The cache's owners, besides a drive number.

;; A cache slot that holds nothing.
CACHE_EMPTY = $80

;; A cache byte past the slots, which <ClearCache> marks as kept, so nothing claims it.
CACHE_KEPT = $40

;; The cache's slots, one for each sector of the longest track.
CACHE_SLOTS = 18

;; The bytes of each of the cache's tables that <ClearCache> clears.
CACHE_TABLE_SIZE = 32

; Values the start-up and the command loop use.

;; <Bus::Initialize>'s A for a cold start: number the bus's devices afresh.
BUS_INIT_COLD = $00

;; <Bus::Initialize>'s A for a warm start: keep the units the devices have.
BUS_INIT_WARM = $80

;; The unit <FirstBusUnit> holds when the bus devices are the only units: there are no 3.5 drives.
FIRST_UNIT = 1

;; How long <ColdStart> lets the SWIM settle, in 2 ms units: 300 ms.
SWIM_SETTLE_TIME = 150

;; The passes of 65536 that <MainLoop> waits between polls of the drives.
POLL_PASSES = 3

;; The 6-and-2 GCR encode table: the 64 valid disk bytes, four times over, so that a byte's low six bits
;; need not be masked.
GcrEncodeTable:
.repeat 4
    .byte $96, $97, $9A, $9B, $9D, $9E, $9F, $A6, $A7, $AB, $AC, $AD, $AE, $AF, $B2, $B3
    .byte $B4, $B5, $B6, $B7, $B9, $BA, $BB, $BC, $BD, $BE, $BF, $CB, $CD, $CE, $CF, $D3
    .byte $D6, $D7, $D9, $DA, $DB, $DC, $DD, $DE, $DF, $E5, $E6, $E7, $E9, $EA, $EB, $EC
    .byte $ED, $EE, $EF, $F2, $F3, $F4, $F5, $F6, $F7, $F9, $FA, $FB, $FC, $FD, $FE, $FF
.endrepeat

;; The card's fixed entry points at $D100, for the diagnostics and the self-test.
CardVectors:
.assert * = $D100, "The card's vectors must stay at $D100."
    jmp Drives::MotorOn
    jmp Drives::Recalibrate
    jmp Drives::Seek
    jmp Drives::WaitReady
    jmp SelectReadHead
    jmp Control::Eject

;; SmartPort INIT ($05), and the <InitializeVector>'s routine: releases the bus and the drives, then restarts the
;; card from its reset, which runs the power-on test again. The host waits for the card to come back ready.
.proc InitializeCard
    jsr Swim::SelectBusPort
    jsr DelayMillisecond
    bit Iwm::MotorOff
    stz CardData
    ; Falls into CardReset.
.endproc

;; The 65C02's reset (and NMI) entry, at $D11D: clears the state byte, so the host waits, and runs the power-on test
;; (<SelfTest::StartUp>), which comes back to <Startup>.
;; In: EjectDrive = a drive whose eject a reset cut short, or bit 7 set
.proc CardReset
.assert * = $D11D, "The self-test names the card's reset as $D11D."
    cld
    sei
    ldx #$FF
    txs
    stz CardState
    lda EjectDrive
    jmp SelfTest::StartUp
.endproc

;; Starts the card after the power-on test, at $D129: copies the host's code into the shared RAM, then either starts
;; cold (finds the drives and the bus devices) or, if page zero still holds <WarmSignature>, warm (keeps them, and
;; reads each drive's disk again). Then finishes an eject a reset cut short, and falls into <MainLoop>.
;; In: EjectDrive = a drive whose eject a reset cut short, or bit 7 set
.proc Startup
.assert * = $D129, "The self-test names the card's start-up as $D129."
    lda EjectDrive
    jsr CopyHostCode

    ; Page zero is warm if it still holds the signature's four bytes.
    ldx #$04
CheckSignature:
    dex
    bmi WarmStart
    lda ZeroPageImage + WarmSignature,x
    cmp WarmSignature,x
    beq CheckSignature
    jsr ColdStart
    bra FinishEject

    ; A warm start keeps the units, but empties the cache and sets the SWIM and the bus up again.
WarmStart:
    jsr ClearCache
    ldx #$FF
    stx Drive
    jsr Swim::Initialize
    jsr Swim::UseGcr
    ldx FirstBusUnit
    beq ReadDisks
    lda #BUS_INIT_WARM
    jsr Bus::Initialize
    lda #IWM_MODE
    jsr Swim::SetIwmMode

    ; Find each 3.5 drive's disk again; with the bus devices at unit 1 there are none.
ReadDisks:
    lda FirstBusUnit
    cmp #FIRST_UNIT
    beq FinishEject
    ldx UnitCount
NextUnit:
    dex
    bmi DisksRead
    bit DeviceKinds,x
    bmi NextUnit
    stx SavedDrive
    stx Drive
    jsr Swim::SelectDrivePort
    ldx SavedDrive
    jsr Drives::CheckDisk
    phx
    clc
    jsr Drives::IdentifyMedia
    jsr Swim::UseGcr
    ldx SavedDrive
    jsr Drives::Release
    plx
    bra NextUnit
DisksRead:
    jsr Swim::SelectDrivePort

    ; An eject that a reset cut short is finished now.
FinishEject:
    bit EjectDrive
    bmi MainLoop
    ldx #$FF
    stx Drive
    jsr Swim::SelectDrivePort
    ldx EjectDrive
    lda Iwm::SelectDrive1,x
    bit Iwm::MotorOn
    jsr EjectDisk
    ; Falls into MainLoop.
.endproc

;; Waits for the host's commands and runs them, forever. The card is ready while <CardState> ($00) has bit 7 set; the
;; host writes the command there. After about 3 x 65536 passes without a command (about 1.3 seconds) it polls the
;; drives for a disk's removal (<Drives::Poll>). Each command is logged at <LastCommand>: <CardState>,
;; <CardCommand>, <CardUnit>, <ParameterLow> and <ParameterMiddle>.
.proc MainLoop
    lda #$FF
    sta CardData
    sta CardState

    ; Wait for a command, polling the drives now and then.
    ldx #POLL_PASSES
Wait:
    dec WorkPointer
    bne CheckState
    dec WorkPointer + 1
    bne CheckState
    dex
    bne CheckState
    jsr Drives::Poll
    ldx #POLL_PASSES
CheckState:
    lda CardState
    bmi Wait

    ; Log the command.
    sta LastCommand
    lda CardCommand
    sta LastCommand + 1
    lda CardUnit
    sta LastCommand + 2
    lda ParameterLow
    sta LastCommand + 3
    lda ParameterMiddle
    sta LastCommand + 4

    ; Run it. A handler that returns with carry set has left the card waiting for the host, so the state stays;
    ; a state with bit 7 clear after it is a command to run.
Run:
    jsr CommandVector
    bcs Ran
    lda #$FF
    sta CardState
Ran:
    stz WorkPointer + 1
    stz SavedDrive
    jsr Swim::UseGcr
    lda CardState
    bpl Run
    bit Iwm::MotorOff
    ldx #POLL_PASSES
    bra Wait
.endproc

;; Runs the command in <CardState>, at $D1E7: the <CommandVector>'s routine. Commands $00-$0E go to the handler for
;; the unit, or, for a bus device's unit and a command below $0D, to the bus; $3D jumps to the diagnostics, and
;; $7E/$7F name the host (not a IIgs, a IIgs) in the host's <Host::Identity>; others answer <ERROR_BAD_COMMAND>. An
;; extended STATUS with code 0 may name a unit with bit 7 set, which is taken without the bit and noted in
;; <UnitWithHighBit>.
;; Out: carry = clear when the card is ready for another command, set when the handler left it waiting;
;;      ErrorCode ($56) = the error, CardData = 0 when the result is final
;; Entry:
;;   CallHandler = runs the handler for <CardState> on the 3.5 drives' port; <BootRead> comes here
;;   PassToBus = passes the command to the bus device in <CardUnit>; <BootRead> comes here
;;   Done = returns with carry clear; <FormatHook> points here until something changes it
.proc RunCommand
.assert * = $D1E7, "The self-test names the card's command routine as $D1E7."
    stz ErrorCode
    stz Retries
    stz TagCall
    stz SwimState
    lda #$FF
    sta Sector
    sta Cylinder
    sta Track

    ; The card's own commands.
    lda CardState
    cmp #COMMAND_READ_SPAN + 1
    bcc CheckUnit
    cmp #COMMAND_NOT_IIGS
    bcc StartDiagnostics
    eor #COMMAND_NOT_IIGS
    beq SetHostType
    lda #HOST_IIGS
SetHostType:
    sta SharedExpansion + HOST_TYPE_OFFSET
    clc
    rts
StartDiagnostics:
    cmp #COMMAND_DIAGNOSTICS
    bne BadCommand
    jmp SelfTest::CardDiagnostics

    ; The unit: one there is, or an extended STATUS of code 0 with bit 7 set on one there is.
CheckUnit:
    stz UnitWithHighBit
CompareUnit:
    lda UnitCount
    cmp CardUnit
    bcs UnitFound
    lda CardState
    ora ParameterLow
    bne BadUnit
    bit CardCommand
    bvc BadUnit
    lda CardUnit
    bpl BadUnit
    sta UnitWithHighBit
    and #$7F
    sta CardUnit
    bne CompareUnit
BadUnit:
    lda #ERROR_BAD_UNIT
    bra SetError

    ; Unit 0 and the 3.5 drives have handlers here; a bus device takes the commands below READAHEAD.
UnitFound:
    ldx CardUnit
    dex
    stx Drive
    bmi CallHandler
    lda DeviceKinds,x
    bpl CallHandler
    lda CardState
    cmp #COMMAND_READ_AHEAD
    bcc PassToBus
BadCommand:
    bra FailBadCommand

CallHandler:
    lda #IWM_MODE
    jsr Swim::SetIwmMode
    jsr Swim::SelectDrivePort
    lda CardState
    asl a
    tax
    jmp (CommandHandlers,x)

    ; The bus device's call, with Drive = its unit; then the 3.5 drives' port again, unless every unit is on the bus.
PassToBus:
    ldx #$FF
    stx Drive
    jsr Swim::SelectBusPort
    jsr Swim::UseGcr
    ldx CardUnit
    stx Drive
    jsr Bus::PassCommand
    lda FirstBusUnit
    cmp #FIRST_UNIT
    beq Done
    lda #$FF
    sta Drive
    jsr Swim::SelectDrivePort
Done:
    clc
    rts
.endproc

;; Each command's handler, by the command at <CardState> ($00-$0E).
CommandHandlers:
    .word Status::Run, ReadBlock, WriteBlock, Format::Command ; $00-$03: STATUS, READBLOCK, WRITEBLOCK, FORMAT
    .word Control::Run, InitializeCard, FailBadCommand, FailBadCommand ; $04-$07: CONTROL, INIT, OPEN, CLOSE
    .word ReadWriteTagged, ReadWriteTagged, FormatOptions::Set, FormatOptions::List ; $08-$0B: READ, WRITE, SETFORMAT, FORMATOPTIONS
    .word BootRead, ReadAhead, ReadSpan ; $0C-$0E: the boot read, READAHEAD, READSPAN
.assert * - CommandHandlers = (COMMAND_READ_SPAN + 1) * 2, "A handler for each command, $00-$0E."

;; Ends a command with <ERROR_BAD_COMMAND> and no data.
;; Out: carry = clear, A = ErrorCode = ERROR_BAD_COMMAND, CardData = 0
;; Keeps: X, Y
.proc FailBadCommand
    lda #ERROR_BAD_COMMAND
    ; Falls into SetError.
.endproc

;; Ends a command with an error code and no data.
;; In: A = the error
;; Out: carry = clear, ErrorCode = A, CardData = 0
;; Keeps: A, X, Y
.proc SetError
    clc
    sta ErrorCode
    stz CardData
    rts
.endproc

;; Ends a command with <ERROR_BAD_CONTROL_PARAMETER>, a bad parameter (a wrong byte count).
;; Out: carry = clear, A = ErrorCode = ERROR_BAD_CONTROL_PARAMETER, CardData = 0
;; Keeps: X, Y
.proc FailBadParameter
    lda #ERROR_BAD_CONTROL_PARAMETER
    bra SetError
.endproc

;; Starts the card cold, at $D2A1: page zero from the ROM, the SWIM set up, the bus reset, the drives found and the
;; SmartPort bus devices numbered after them, then the signature and an empty cache. <FormatHook> starts at
;; <RunCommand::Done>, which returns with carry clear.
;; Out: UnitCount = the units, FirstBusUnit = the first bus unit or 0, DeviceKinds = each unit's kind, Drive = 0
.proc ColdStart
.assert * = $D2A1, "The self-test names the card's cold start as $D2A1."
    jsr CopyZeroPage
    lda #>RunCommand::Done
    sta FormatHook + 1
    lda #<RunCommand::Done
    sta FormatHook

    ; The SWIM, after 300 ms, and a reset of the bus.
    lda #$FF
    sta Drive
    jsr Swim::Initialize
    lda #SWIM_SETTLE_TIME
    jsr DelayMillisecondPairs
    lda #IWM_MODE
    jsr Swim::SetIwmMode
    jsr Swim::SelectBusPort
    jsr Bus::ResetDevices
    jsr Swim::SelectDrivePort
    jsr DelayMillisecond
    jsr Swim::SelectBusPort

    ; The 3.5 drives, then the bus devices after them.
    jsr Drives::Find
    stz FirstBusUnit
    ldx UnitCount
    inx
    lda #BUS_INIT_COLD
    jsr Bus::Initialize
    beq NoBus
    ldx UnitCount
    inx
    stx FirstBusUnit
    clc
    adc UnitCount
    sta UnitCount
NoBus:
    stz Drive
    jsr CopySignature
    ; Falls into ClearCache.
.endproc

;; Empties the sector cache: every slot's cylinder and sector 0, slots 1 to <CACHE_SLOTS> (indexes 0-$11)
;; <CACHE_EMPTY>, and the table bytes past them <CACHE_KEPT>, so nothing takes them.
;; Out: X = $FF
;; Keeps: Y
.proc ClearCache
    ldx #CACHE_TABLE_SIZE - 1
    lda #CACHE_KEPT
Loop:
    stz CacheCylinders,x
    stz CacheSectors,x
    sta CacheOwners,x
    cpx #CACHE_SLOTS
    bne Next
    lda #CACHE_EMPTY
Next:
    dex
    bpl Loop
    rts
.endproc

;; Copies the ROM's page-zero image, $8001-$80BB, to $01-$BB; <CardState> at $00 is the host's to write.
;; Out: X = 0
;; Keeps: Y
.proc CopyZeroPage
    ldx #<WarmSignature - 1
Loop:
    lda ZeroPageImage,x
    sta CardState,x
    dex
    bne Loop
    rts
.endproc

;; Copies the warm-start signature, $80BC-$80BF, to <WarmSignature> ($BC-$BF), once the rest of page zero is ready.
;; Out: X = $BB
;; Keeps: Y
.proc CopySignature
    ldx #<WarmSignature + 3
Loop:
    lda ZeroPageImage,x
    sta CardState,x
    dex
    cpx #<WarmSignature - 1
    bne Loop
    rts
.endproc

;; Copies the host's slot page to $7B00, its $C800 code to <HostCode> ($0200-$03FF) and its $CC00 code to
;; <SharedExpansion> ($7C00-$7FFF), then points the boot's wait at the host's <Call> and releases the calls' wait,
;; and puts an RTS at each unit's hook (<UnitHook1> to <UnitHook4>).
;; Out: Y = 0
.proc CopyHostCode
    ldy #$00
CopySlotPage:
    lda SlotPageImage,y
    sta SharedSlotPage,y
    iny
    bne CopySlotPage
CopyCode:
    lda SlotPageImage + $100,y
    sta HostCode,y
    lda SlotPageImage + $200,y
    sta HostCode + $100,y
    lda SlotPageImage + $300,y
    sta SharedExpansion,y
    lda SlotPageImage + $400,y
    sta SharedExpansion + $100,y
    lda SlotPageImage + $500,y
    sta SharedExpansion + $200,y
    lda SlotPageImage + $600,y
    sta SharedExpansion + $300,y
    iny
    bne CopyCode

    ; Release the host's waits, and empty the hooks.
    lda #BOOT_WAIT_TO_CALL
    sta SharedSlotPage + BOOT_WAIT_OFFSET
    stz SharedSlotPage + CALL_WAIT_OFFSET
    lda #OPCODE_RTS
    sta UnitHook1
    sta UnitHook2
    sta UnitHook3
    sta UnitHook4
    rts
.endproc

.include "Disk35Drives.asm"
.include "Disk35Cache.asm"
.include "Disk35Blocks.asm"
.include "Disk35Gcr.asm"
.include "Disk35Mfm.asm"
.include "Disk35Control.asm"
.include "Disk35Format.asm"
.include "Disk35Bus.asm"

;; The IRQ and BRK handler, at $F931: blinks the LED forever, on and off in turn.
.proc Fatal
    ldx #$FF
Toggle:
    inx
    bit LedOn,x
    ldy #$00
Outer:
    lda #$00
Inner:
    dec a
    bne Pause
Pause:
    bne Inner
    dey
    bne Outer
    txa
    beq Toggle
    bra Fatal
.endproc

    ; The rest is unused, up to the self-test's CRCs.
    .res $FFDA - *

;; The CRCs <SelfTest::RomCrc> checks, one word for each of the first fifteen 2 KB blocks of the ROM, $8000-$F7FF, low
;; byte first.
RomCrcs:
.assert * = $FFDA, "The self-test reads the CRCs at $FFDA."
    .word $C850, $B8A7, $67EC, $4686, $0000, $0000, $0000, $0000, $0000, $0000, $89CA, $C2F6, $7319, $B19A, $9E81

;; The ROM's check word: its high byte, at $FFF9, makes the self-test's checksum of the ROM come out to 0.
RomCheckWord:
    .word $7378

;; The 65C02's vectors.
CpuVectors:
    .word CardReset                 ; NMI
    .word CardReset                 ; reset
    .word Fatal                     ; IRQ and BRK
