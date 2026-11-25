; retrocore: style=strict
;; THE HOST'S FIRMWARE: THE SLOT PAGE, AND THE CODE AT $CA00-$CFFF
;;
;; The code the Apple II runs, which the card's 65C02 copies out of the EPROM at start-up: the slot page ($8100,
;; seen at $Cn00), the call and boot code ($8200-$83FF, which the card keeps at its $0200-$03FF and the host runs
;; at $CA00-$CBFF with bank 0 latched), and the transfers ($8400-$87FF, at $CC00-$CFFF). It is 6502 code that also
;; runs on the 65C02 and, on a IIgs, takes 65816 paths that move a block through any bank with the machine at full
;; speed. The 65816 instructions are written with the macros below, which give their bytes.
;;
;; THE SLOT PAGE
;;
;; $Cn01 = $20, $Cn03 = $00, $Cn05 = $03 and $Cn07 = $00 mark a SmartPort. $CnFB = $C0 (extended calls), $CnFC-$CnFD
;; = 0 (ask STATUS for the size), $CnFE = $BF (removable, not interruptible, four volumes, format, write, read and
;; status) and $CnFF = $1C: ProDOS calls $Cn1C and SmartPort $Cn1F. The page holds three waits, each a branch to
;; itself, whose offsets the card rewrites once it is ready: the boot's at $Cn0B (to $Cn23, as a call with overflow
;; set), the diagnostics' at $Cn17, and the calls' at $Cn21. Until then a boot or a call waits; a card that fails its
;; self-test writes JMP $FF59 over $Cn00, $Cn0D and $Cn23 instead, so each goes to the Monitor.
;;
;; A CALL
;;
;; A call saves page zero $40-$51 in the card's RAM, copies its parameters into page zero, checks the count, and
;; hands the command to the card through the card's own page zero, seen at $C800-$C80C and $C856 with bank 0
;; latched (<MailboxState> and the names after it). A block moves through one of the window's banks, 512 bytes at
;; $C800 or $CA00. On the way out the call puts page zero back and returns A = the error, carry set when it is not
;; 0, and X and Y = the bytes moved.
;;
;; The card's commands are the COMMAND_* values in Disk35Equates.asm: the SmartPort command less its extended bit
;; ($00-$0B), <COMMAND_BOOT> to read the boot block, <COMMAND_DIAGNOSTICS> to start the diagnostics, and
;; <COMMAND_NOT_IIGS> or <COMMAND_IIGS> to say whether the host is a IIgs.

.cpu Mos6502

.include "../System/IIeEquates.asm"
.include "../System/MonitorEntries.asm"

; The host's names that IIeEquates.asm and MonitorEntries.asm lack.

;; Inherit: <Monitor:LOC1>
LOC1 = $01

;; Inherit: <Monitor:ExpansionRomOff>
;; Also: CLRROM (A2RM79, IIEROM82, IIETRM85)
ExpansionRomOff = $CFFF

;; Inherit: <Monitor:BasicColdStart>
;; Also: BASIC (A2RM78, A2RM79, IIEROM82, IIETRM85)
BasicColdStart = $E000

;; The Autostart and IIe Monitors' power-up, whose scan for a disk controller the boot goes back to when it fails.
.scope Startup

;; The power-up routine that holds the scan.
.scope PowerUp

;; Inherit: <Monitor:Startup::PowerUp::NextSlot>
;; At $FABA: the Monitor's boot scan, which goes on to the next slot down.
;; Also: SLOOP (A2RM79, IIEROM82, IIETRM85)
NextSlot = $FABA

.endscope

.endscope

;; Inherit: <Monitor:SetText>
;; At $FB39.
;; Also: SETTXT (A2RM78, A2RM79, IIEROM82, IIETRM85)
SetText = $FB39

;; Inherit: <Monitor:MODEL_ID_IIE>
;; The enhanced IIe, the IIc and the IIgs have it too.
MODEL_ID_IIE = $06

;; Inherit: <Monitor:MODEL_ID_ENHANCED>
;; The IIc and the IIgs have it too.
MODEL_ID_ENHANCED = $E0

;; The byte at $FBC0, which with <ModelId> tells the models of the IIe's family apart: <MODEL_ID_ENHANCED> on the
;; enhanced IIe, the IIc and the IIgs.
;; Also: ZIDBYTE (UNKN)
SecondModelId = $FBC0

;; A routine that tells a IIgs: on a IIe it is an RTS (the end of the Monitor's <Monitor:Commands::SetMode>, which
;; leaves the carry as it came); on the IIgs it returns carry clear.
;; Also: IDROUTINE (UNKN)
IdentifyIIgs = $FE1F

;; The IIgs's shadowing register: 0 shadows every bank 0 and 1 display page in banks $E0 and $E1.
;; Also: SHADOW (IIGSFR87)
Shadow = $C035

;; The IIgs's speed register: bit 7 set for full speed.
;; Also: CYAREG (IIGSFR87)
SpeedRegister = $C036

;; The IIgs's state register, which holds what is written to it; a IIe has no register there.
;; Also: STATEREG (IIGSFR87)
StateRegister = $C068

;; The bit in <SpeedRegister> for full speed.
FULL_SPEED = $80

;; The bits of <StateRegister> the identification turns over and reads back.
STATE_TEST_BITS = $0E

;; How many times the identification turns them over.
STATE_TESTS = 10

; The host's other locations.

;; The stack page: a JSR's return address is there, just above the stack pointer.
StackPage = $0100

;; The card's I/O, at $C080 plus the slot times 16: any access at the address plus b latches the card's bank b in
;; the window at <CardWindow>.
BankLatch = $C080

;; The window on the card's RAM: $C800-$CBFF shows the bank last latched at <BankLatch>; $CC00-$CFFF always shows
;; the card's $7C00-$7FFF, where the code from the end of <Host::Dispatch> on runs.
CardWindow = $C800

;; Where a boot block is read, as ProDOS's own boot does.
BootBuffer = $0800

;; Where a boot block runs, after its first byte.
BootEntry = $0801

;; Where the host says why it did not boot: the text screen's second line (row 1), column 8.
MessageAt = $0488

; ProDOS's block-device call: the mailbox in page zero, <ProDos::Command> to <ProDos::BlockHigh>.
.include "../ProDosBlockDevice.asm"

;; A boot block's first byte: the number of blocks it is, which must be 1.
BOOT_BLOCK_COUNT = $01

; The call's page zero, which the call saves and restores.

;; The buffer, three bytes; first the caller's return address.
CallBuffer = $40

;; The command: bit 6 extended, bit 7 a ProDOS call.
CallCommand = $43

;; The SmartPort unit.
CallUnit = $44

;; The call's other parameters, $46-$4B.
CallParameters = $46

;; The parameter list; later the data in the window.
ParameterList = $4C

;; The bytes moved; first the parameter list's bank.
BytesMoved = $4E

;; The parameter count, then the error.
CallResult = $50

;; The slot times 16.
SlotTimes16 = $51

;; The first page-zero byte the call saves.
CallPageZeroStart = CallBuffer

;; The byte after the last page-zero byte the call saves.
CallPageZeroEnd = $52

;; How many rounds of 65536 the boot waits for a key.
BootTries = Address1

;; <CallCommand>'s bit for a ProDOS call.
CALL_PRODOS = $80

;; <CallCommand>'s bit for an extended SmartPort call.
CALL_EXTENDED = $40

;; The bytes the host gives the card: <CallCommand> to the end of <CallParameters>.
CALL_BYTES = CallParameters + 6 - CallCommand

;; Where ProDOS's calls start in the handler tables, after SmartPort's twelve: ProDOS's status.
PRODOS_HANDLERS = COMMAND_BOOT

;; ProDOS's calls: status, read, write and format.
PRODOS_CALLS = 4

;; How many handlers there are: SmartPort's twelve and ProDOS's four.
HANDLER_COUNT = PRODOS_HANDLERS + PRODOS_CALLS

;; The last byte of a standard parameter list, after its count: the block's high byte, or the last parameter.
STANDARD_LIST_LAST = 8

;; The last byte of an extended parameter list, after its count.
EXTENDED_LIST_LAST = 11

;; The most units a hook can serve.
LAST_HOOK_UNIT = 4

;; The most bytes command $0A takes.
SET_FORMAT_BYTES = 4

; The card's page zero, at <CardWindow> with bank 0 latched. Its names in the card's own code are in
; Disk35ZeroPage.asm.

;; Bit 7 set while the card waits; the command goes here.
MailboxState = CardWindow + CardState

;; Where the data is, or 0 for none; bit 7 set while the card works.
MailboxData = CardWindow + CardData

;; The call's $43-$4B.
MailboxCommand = CardWindow + CardCommand

;; The unit.
MailboxUnit = CardWindow + CardUnit

;; The call's $45, which the IIgs's writes use to pace the card.
MailboxProgress = CardWindow + WriteProgress

;; A count, low and high.
MailboxCount = CardWindow + Count

;; The error.
MailboxError = CardWindow + ErrorCode

.assert MailboxState = $C800 && MailboxCommand = $C802 && MailboxProgress = $C804, "The card's mailbox moved."
.assert MailboxCount = $C80B && MailboxError = $C856, "The card's mailbox moved."

;; What the host writes at <MailboxData> as it sends a command.
DATA_SENDING = $FF

;; What the host ORs into <MailboxData> once it has taken or left the data.
DATA_TAKEN = $F0

;; <MailboxData>'s bank and half.
DATA_WHERE = $1F

;; The command's bits that go to <MailboxState>: <CallCommand> less bits 7 and 6 (the ProDOS and extended bits)
;; and bit 5, which no command has.
COMMAND_BITS = $1F

;; <MailboxProgress> when the IIgs starts a write with interrupts off, and while it copies the block's first half.
PROGRESS_STARTED = $C0

;; <MailboxProgress> when the IIgs's write is all in the window.
PROGRESS_DONE = $D0

; The card's RAM at $0A00, at $CA00 with bank 2 latched.

;; Bit 7 set while a call runs. <Host::MarkCallRunning> sets it on every host once the card has named the host, since
;; the card's IIgs answer leaves <Host::Identity>'s bit 7 clear.
CallBusy = $CA00

;; <CallBusy>'s bit for a call that runs.
CALL_RUNNING = $80

;; Page zero $40-$51 while a call runs.
SavedCallPageZero = $CA02

;; The units' hooks, 32 bytes each, from unit 1: the card's $0B80-$0BFF, at $CB80 with bank 2 latched.
UnitHooks = $CB80

;; The size of a unit's hook.
UNIT_HOOK_SIZE = $20

; The window's banks.

;; The card's page zero, and this code at $CA00.
BANK_MAILBOX = 0

;; The busy flag and the saved page zero.
BANK_SAVE = 2

; The status byte of STATUS code 0, as ProDOS's status reads it.

;; The disk is in the drive.
STATUS_ONLINE = $10

;; The disk is write-protected.
STATUS_WRITE_PROTECTED = $04

;; The card did not answer: not a SmartPort error, only the boot's.
ERROR_NEVER_READY = $30

;; The diagnostics' code, once the card has put it in place of this.
DiagnosticsCode = $CC00

;; The Control-D a held key gives, with its high bit set: three ask the boot for the diagnostics.
KEY_CONTROL_D = $84

;; How many Control-Ds start the diagnostics. The boot also starts <BootTries> at it, so it is the key wait's rounds
;; too.
CONTROL_D_COUNT = 3

; The 65816's instructions, which the 6502 assembler does not take. On a 65C02, PHX and PLX are its own.

;; The 65816's m flag in <ClearStatusBits> and <SetStatusBits>: set, the accumulator and memory are 8 bits.
STATUS_MEMORY_8 = $20

;; The 65816's x flag: set, the index registers are 8 bits.
STATUS_INDEX_8 = $10

;; The 65816's XCE, which swaps carry with the emulation flag.
.macro ExchangeCarryAndEmulation
    .byte $FB
.endmacro

;; The 65816's REP: clears the status bits set in the mask.
;; Parameters:
;;   mask = the bits
.macro ClearStatusBits mask
    .byte $C2, mask
.endmacro

;; The 65816's SEP: sets the status bits set in the mask.
;; Parameters:
;;   mask = the bits
.macro SetStatusBits mask
    .byte $E2, mask
.endmacro

;; The 65816's (and 65C02's) PHX.
.macro PushX
    .byte $DA
.endmacro

;; The 65816's (and 65C02's) PLX.
.macro PullX
    .byte $FA
.endmacro

;; The 65816's LDA [dp],Y, through a three-byte pointer.
;; Parameters:
;;   pointer = the pointer's page-zero address
.macro LoadLongY pointer
    .byte $B7, pointer
.endmacro

;; The 65816's STA [dp],Y, through a three-byte pointer.
;; Parameters:
;;   pointer = the pointer's page-zero address
.macro StoreLongY pointer
    .byte $97, pointer
.endmacro

.logicalorg $C500
;; Boots the card's first drive. The four loads are the SmartPort identification at $Cn01-$Cn07. Overflow, set by
;; the addition, makes the call that follows a boot; until the card is ready the branch waits on itself.
;; Entry:
;;   WaitForCard = the branch the card rewrites, to <CallCard>, once it is ready
.proc Boot
    ldx #$20
    ldx #$00
    ldy #$03
    lda #$00
    sec
    adc #$7F
WaitForCard:
    bvs WaitForCard                 ; the card makes it BVS CallCard
.endproc
.assert * = $C50D, "The diagnostics' entry must stay at $Cn0D."

;; Starts the card's diagnostics, as Cn0DG does from the Monitor.
.proc DiagnosticsEntry
    php
    sei
    bit ExpansionRomOff
    jsr Host::AskForDiagnostics
    ; Falls into WaitForDiagnostics.
.endproc

;; Waits for the diagnostics' code, then runs it. The boot comes here with A = 0 for Control-D.
;; In: A = 0, the caller's status on the stack
;; Entry:
;;   Wait = the branch the card rewrites to fall through, once the code is in place
.proc WaitForDiagnostics
    plp
    tax
Wait:
    beq Wait                        ; the card makes it fall through once the code is there
    jmp DiagnosticsCode
.endproc
.assert * = $C51C, "The ProDOS entry must stay at $Cn1C."

;; The ProDOS block-device entry.
;; In: ProDos::Command = the command (<ProDos::COMMAND_STATUS> to <ProDos::COMMAND_FORMAT>),
;;   ProDos::UnitNumber = the unit, ProDos::Buffer/ProDos::BufferHigh = the buffer, ProDos::Block/ProDos::BlockHigh =
;;   the block
;; Out: A = 0 or the error, carry = set on an error; X and Y = the block count after status
.proc Disk35Driver
    clc
    bcc SmartPortEntry::WaitForCard ; always
.endproc
.assert * = $C51F, "The SmartPort entry must stay at $Cn1F."

;; The SmartPort entry: JSR $Cn1F, then the command and the parameter list's address (four bytes for an extended
;; command), which the call steps over.
;; Out: A = 0 or the error, carry = set on an error, X and Y = the bytes moved
;; Entry:
;;   WaitForCard = <Disk35Driver> comes here with carry clear
;;   Wait = the branch the card rewrites to fall through, once it is ready
.proc SmartPortEntry
    sec
WaitForCard:
    clv
Wait:
    bvc Wait                        ; the card makes it fall through
    ; Falls into CallCard.
.endproc

;; The common entry: finds the slot, saves page zero and runs a boot, a ProDOS call or a SmartPort call.
;; In: carry = set for SmartPort, overflow = set to boot
;; Out: A = 0 or the error, carry = set on an error, X and Y = the bytes moved; a boot that works does not return
.proc CallCard
    php
    sei
    lda ExpansionRomOff
    jsr Host::Dispatch::Return      ; leaves its return address's high byte, $Cn, just below the stack
    tsx
    lda StackPage,x
    sta ExpansionRomSlot
    tay
    ldx Host::SlotTimes16Table - $C1,y
    lda BankLatch + BANK_SAVE,x
    jsr Host::MarkCallRunning
    ldx #CallPageZeroEnd - CallPageZeroStart
SavePageZero:
    lda CallPageZeroStart - 1,x
    sta SavedCallPageZero - 1,x
    dex
    bne SavePageZero
    plp
    ldx Host::SlotTimes16Table - $C1,y
    lda BankLatch + BANK_MAILBOX,x
    bvc NotBoot
    jsr Host::BootFirstDrive
    beq WaitForDiagnostics          ; Control-D: the diagnostics
NotBoot:
    bit Host::Identity
    bpl Identified
    jsr Host::Identify
    ldy ExpansionRomSlot
Identified:
    bcc ProDosCall

    ; SmartPort: the command and the list follow the JSR.
    pla
    sta CallBuffer
    pla
    sta CallBuffer + 1
    ldy #1
    lda (CallBuffer),y
    sta CallResult
    iny
    lda (CallBuffer),y
    sta ParameterList
    iny
    lda (CallBuffer),y
    sta ParameterList + 1
    iny
    lda (CallBuffer),y              ; an extended list's bank
    dey
    bit CallResult
    bvc Bank0
    ldy #5
    bit Host::Identity
    bvs SetBank                     ; only the IIgs reaches other banks
Bank0:
    lda #0
SetBank:
    sta BytesMoved
    tya
    clc
    adc CallBuffer
    tax
    lda #0
    adc CallBuffer + 1
    pha
    txa
    pha                             ; returns past the command and list
    jsr Host::GetParameterList
    lda CallCommand
    and #$FF ^ CALL_EXTENDED
    cmp #PRODOS_HANDLERS
    bcc RunHandler
BadCommand:
    lda #ERROR_BAD_COMMAND
    bne ReturnResult                ; always
    lda #ERROR_BAD_UNIT             ; no code reaches this
    bne ReturnResult

ProDosCall:
    lda ProDos::Command
    cmp #PRODOS_CALLS
    bcs BadCommand
    jsr Host::ProDosToSmartPort
    lda CallCommand
    clc
    adc #<(PRODOS_HANDLERS - CALL_PRODOS) ; $80-$83 become $0C-$0F
RunHandler:
    jsr Host::Dispatch
    lda CallResult
ReturnResult:
    pha
    lda BytesMoved
    pha
    lda BytesMoved + 1
    pha
    ldy ExpansionRomSlot
    ldx Host::SlotTimes16Table - $C1,y
    lda BankLatch + BANK_SAVE,x
    ldx #0
RestorePageZero:
    ldy SavedCallPageZero,x
    sty CallPageZeroStart,x
    inx
    cpx #CallPageZeroEnd - CallPageZeroStart
    bcc RestorePageZero
    lda #0
    sta CallBusy
    pla
    tay
    pla
    tax
    pla
    cmp #1
    ora #0
    rts
.endproc

;; Copies the 16 bytes at $C100-$C10F to $CBEE-$CBFD, for the diagnostics, which look there for the factory
;; fixture's ROM in slot 1.
.proc CopySlot1Rom
    ldy #$0F
Loop:
    lda $C100,y
    bit ExpansionRomOff
    sta $CBEE,y
    dey
    bpl Loop
    rts
.endproc

    .byte 0, 0
.assert * = $C5F8, "The slot page's unused bytes moved."
    .byte 0, 0, 0

;; The SmartPort's identification after the entry points, as the end of every slot ROM gives it.
Signature:
    .byte $C0                       ; $CnFB: extended SmartPort calls
    .word 0                         ; $CnFC: ask STATUS for the block count
    ; $CnFE: removable, not interruptible, four volumes, format, write, read and status ($BF).
    .byte ProDos::CAPABILITY_REMOVABLE | ProDos::FOUR_VOLUMES | ProDos::CAPABILITY_EVERY_COMMAND
    .byte <Disk35Driver             ; $CnFF: the ProDOS entry
.assert * = $C600, "The slot page must end at $CnFF."

.logicalorg $CA00
;; The host's code in the card's RAM: the call's steps at $CA00-$CBFF (with bank 0 latched), the transfers and the
;; boot's end at $CC00-$CFFF.
.scope Host

;; Tells the card whether the host is a IIgs: one whose <StateRegister> holds what is written to it, whose Monitor
;; is the IIe's family's (<ModelId> = <MODEL_ID_IIE>, <SecondModelId> = <MODEL_ID_ENHANCED>), and whose
;; <IdentifyIIgs> returns carry clear. Waits for the card to take the answer. The card's bank 0 must be latched. Y is
;; kept on a host that is not a IIgs; a IIgs's <IdentifyIIgs> returns its ROM version in it.
;; Keeps: interrupt
.proc Identify
    php
    sei
    lda StateRegister
    pha
    ldx #STATE_TESTS
Toggle:
    eor #STATE_TEST_BITS
    sta StateRegister
    cmp StateRegister
    bne NoStateRegister
    dex
    bne Toggle
    pla
    sta StateRegister
    lda ModelId
    cmp #MODEL_ID_IIE
    bne NotIIgs
    lda SecondModelId
    cmp #MODEL_ID_ENHANCED
    bne NotIIgs
    sec
    jsr IdentifyIIgs
    bcs NotIIgs
    lda #COMMAND_IIGS
    bne Tell                        ; always
NoStateRegister:
    pla
NotIIgs:
    lda #COMMAND_NOT_IIGS
Tell:
    bit MailboxState
    bpl Tell
    sta MailboxState
WaitForAnswer:
    bit MailboxState
    bpl WaitForAnswer
    plp
    rts
.endproc

;; Copies the parameter list into page zero: a standard list's eight bytes after the count, or an extended list's
;; eleven, then moves the buffer to $40-$42, the command to $43 and the unit to $44.
;; In: ParameterList = the list, BytesMoved = its bank on a IIgs, CallResult = the command
;; Out: CallResult = the list's count
.proc GetParameterList
    bit CallResult
    bvs Extended
    ldy #STANDARD_LIST_LAST
NextStandard:
    tax
    lda (ParameterList),y
    dey
    bmi StandardDone
    cpy #3
    bcc StoreLow
    sta CallCommand,y               ; the parameters after the buffer go to $46-$4A
    bcs NextStandard                ; always
StoreLow:
    sta CallBuffer + 1,y            ; the unit and buffer go to $41-$43
    bcc NextStandard                ; always
StandardDone:
    iny
    sty CallUnit                    ; the buffer's bank: 0
    sty CallParameters + 5
    beq MoveBuffer                  ; always
Extended:
    ldy #EXTENDED_LIST_LAST
NextExtended:
    tax
    bit Identity
    bvs ReadLong
    lda (ParameterList),y
    bvc Got                         ; always
ReadLong:
    LoadLongY ParameterList
Got:
    dey
    bmi MoveBuffer
    sta CallBuffer + 1,y
    bpl NextExtended                ; always
MoveBuffer:
    ldy CallResult
    sta CallResult

    ; The list put the unit at $41 and the buffer at $42-$43: move them to their places.
    lda CallBuffer + 2
    sta CallBuffer
    lda CallBuffer + 3
    sta CallBuffer + 1
    lda CallUnit
    sta CallBuffer + 2
    stx CallUnit
    sty CallCommand
    rts
.endproc

;; Each command's handler, less one, low bytes: SmartPort's $00-$0B, then ProDOS's status, read, write and format.
HandlersLow:
    .byte <(ReceiveData - 1), <(ReadBlockCall - 1), <(WriteBlockCall - 1), <(CommandOnly - 1), <(ControlCall - 1)
    .byte <(Initialize - 1), <(CommandOnly - 1), <(CommandOnly - 1), <(ReceiveData - 1), <(Write - 1)
    .byte <(SetFormat - 1), <(ReceiveData - 1)
    .byte <(ProDosStatus - 1), <(ReadBlockCall - 1), <(WriteBlockCall - 1), <(CommandOnly - 1)

;; The high bytes, in the same order.
HandlersHigh:
    .byte >(ReceiveData - 1), >(ReadBlockCall - 1), >(WriteBlockCall - 1), >(CommandOnly - 1), >(ControlCall - 1)
    .byte >(Initialize - 1), >(CommandOnly - 1), >(CommandOnly - 1), >(ReceiveData - 1), >(Write - 1)
    .byte >(SetFormat - 1), >(ReceiveData - 1)
    .byte >(ProDosStatus - 1), >(ReadBlockCall - 1), >(WriteBlockCall - 1), >(CommandOnly - 1)

;; The parameter count each command needs: SmartPort's, then $FF for ProDOS's calls, which have no count.
ParameterCounts:
    .byte 3, 3, 3, 1, 3, 1, 1, 1, 4, 4, 3, 3   ; STATUS to $0B
    .byte $FF, $FF, $FF, $FF                    ; ProDOS's calls have no count
.assert HandlersHigh - HandlersLow = HANDLER_COUNT && ParameterCounts - HandlersHigh = HANDLER_COUNT, "A handler each."
.assert * - ParameterCounts = HANDLER_COUNT, "A count for each handler."

;; Boots: waits for the card, or starts the diagnostics after three Control-Ds, then has the card read the boot block
;; into <BootBuffer> and runs it with X = the slot times 16, as ProDOS expects. A block that does not start with
;; <BOOT_BLOCK_COUNT> and a nonzero byte is not a boot block.
;; In: X = the slot times 16, bank 0 latched
;; Out: zero = set for the diagnostics, with the caller's status and return address back on the stack; otherwise
;;   it does not return
.proc BootFirstDrive
    stx SlotTimes16
    jsr Identify
    lda #0
    sta BytesMoved
    sta BytesMoved + 1
    ldx #CONTROL_D_COUNT
    stx BootTries
    ldy ModelId
    cpy #MODEL_ID_IIE
    beq Strobe
    lda Keyboard                    ; a II or II Plus: no key held to look for
    ora #$80
    bmi Key                         ; always
Strobe:
    bit KeyboardStrobe
    bpl Ready                       ; no key down
    bmi Look                        ; always
Next:
    sta KeyboardStrobe
Look:
    lda Keyboard
    bmi Key
    cpy #MODEL_ID_IIE
    bne CountWait
    bit KeyboardStrobe
    bpl Ready
CountWait:
    inc BytesMoved
    bne Look
    inc BytesMoved + 1
    bne Look
    dec BootTries
    bne Look
    beq Ready                       ; always
Key:
    cmp #KEY_CONTROL_D
    bne Ready
    dex
    bne Next

    ; The diagnostics: put the caller's status back above its return address and ask the card.
    php
    sei
    pla
    tay
    pla
    sta BytesMoved
    pla
    sta BytesMoved + 1
    tya
    pha
    lda BytesMoved + 1
    pha
    lda BytesMoved
    pha
    jmp AskForDiagnostics

Ready:
    ldx #3
Wait:
    lda MailboxState
    bmi Read
    inc BytesMoved
    bne Wait
    inc BytesMoved + 1
    bne Wait
    dex
    bne Wait
    lda #ERROR_NEVER_READY
    sta CallResult
    bne Fail                        ; always
Read:
    lda #DATA_SENDING
    sta MailboxData
    lda #0
    sta MailboxUnit
    lda #CALL_PRODOS | COMMAND_READ_BLOCK ; a ProDOS read, so errors are ProDOS's
    sta CallCommand
    lda #COMMAND_BOOT
    sta MailboxState
    lda #>BootBuffer
    sta CallBuffer + 1
    lda #<BootBuffer
    sta CallBuffer
    sta CallBuffer + 2
    jsr ReceiveBlock
    ldx SlotTimes16
    cmp #1
    bcs Fail

    ; ProDOS's page zero, as for a read of block 0.
    lda #COMMAND_READ_BLOCK
    sta ProDos::Command
    stx ProDos::UnitNumber
    lda #>BootBuffer
    sta ProDos::BufferHigh
    lda #<BootBuffer
    sta ProDos::Buffer
    sta ProDos::Block
    sta ProDos::BlockHigh
    lda BootBuffer
    cmp #BOOT_BLOCK_COUNT
    bne Fail
    lda BootEntry
    beq Fail
    lda #0
    bit Identity
    bvc Run
    sta Shadow
Run:
    jmp BootEntry
Fail:
    stx SlotTimes16
    jmp NoBoot
.endproc

;; Turns a ProDOS call's error into one of ProDOS's: 0, <ERROR_WRITE_PROTECTED>, <ERROR_NO_DRIVE> and
;; <ERROR_OFFLINE> stand, <ERROR_BAD_UNIT> becomes <ERROR_NO_DRIVE> and the rest <ERROR_IO>. SmartPort's errors
;; stand.
;; In: A = the error
;; Out: A = the error to return
;; Keeps: X, Y
.proc MapProDosError
    bit CallCommand
    bpl Done
    cmp #0
    beq Done
    cmp #ERROR_WRITE_PROTECTED
    beq Done
    cmp #ERROR_NO_DRIVE
    beq Done
    cmp #ERROR_OFFLINE
    beq Done
    cmp #ERROR_BAD_UNIT
    bne Io
    lda #ERROR_NO_DRIVE
    rts
Io:
    lda #ERROR_IO
Done:
    rts
.endproc

;; Sets ProDOS status's error from the status byte: none for a disk that is in and writable,
;; <ERROR_WRITE_PROTECTED> for one that is write-protected, <ERROR_OFFLINE> for none.
;; In: Y = the status byte's <STATUS_ONLINE> and <STATUS_WRITE_PROTECTED> bits, bank 0 latched
;; Keeps: X, Y
.proc SetProDosStatusError
    cpy #STATUS_ONLINE
    beq Done
    lda #ERROR_WRITE_PROTECTED
    cpy #STATUS_ONLINE | STATUS_WRITE_PROTECTED
    beq Set
    lda #ERROR_OFFLINE
Set:
    sta MailboxError
Done:
    rts
.endproc

    .res 26

;; Gives a call the wrong parameter count's error.
.proc BadParameterCount
    lda #ERROR_BAD_PARAMETER_COUNT
    sta CallResult
    rts
.endproc

;; Checks a command's parameter count and goes to its handler, with bank 0 latched once the card is waiting.
;; In: A = the command: $00-$0B, or $0C-$0F for ProDOS's
;; Its last instruction, the RTS at Return, is what <CallCard> calls to find its slot.
.proc Dispatch
    ldy ExpansionRomSlot
    ldx SlotTimes16Table - $C1,y
    stx SlotTimes16
    tax
    lda ParameterCounts,x
    bmi Go
    cmp CallResult
    bne BadParameterCount
Go:
    lda HandlersHigh,x
    pha
    lda HandlersLow,x
    pha
    lda #0
    sta CallResult
    sta BytesMoved + 1
    sta BytesMoved
    ldx SlotTimes16
    jsr RunUnitHook
.assert * = $CC00, "The transfers must start at $CC00."
    lda BankLatch + BANK_MAILBOX,x

    ; Wait for the card to wait for a command, then go to the handler.
WaitForCard:
    lda MailboxState
    bpl WaitForCard
Return:
    rts
.endproc

;; Bit 7 set until the host is identified; bit 6 set on a IIgs, whose transfers take the 65816 paths. The card keeps
;; it.
Identity:
    .byte $80

;; FORMAT, OPEN, CLOSE and ProDOS's format: the card does all of it.
.proc CommandOnly
    jsr SendCommand
    clc
    jmp Finish
.endproc

;; ProDOS's status: the card's status 0, then the block count in X and Y, with <ERROR_WRITE_PROTECTED> for a
;; write-protected disk and <ERROR_OFFLINE> for none.
.proc ProDosStatus
    lda #0
    sta CallParameters              ; status code 0
    jsr SendCommand
Wait:
    lda MailboxData
    bmi Wait
    beq Done
    jsr LatchData
    ldy #2
    lda (ParameterList),y
    sta BytesMoved + 1
    dey
    lda (ParameterList),y
    sta BytesMoved
    dey
    lda (ParameterList),y
    and #STATUS_ONLINE | STATUS_WRITE_PROTECTED
    tay
    ldx SlotTimes16
    lda BankLatch + BANK_MAILBOX,x
    jsr SetProDosStatusError
Done:
    jmp FinishNow
.endproc

;; STATUS, READ and command $0B: the card sends what it read and its length.
;; In: CallParameters = the status code or byte count
.proc ReceiveData
    lda CallParameters
    sta MailboxCount
    lda CallParameters + 1
    sta MailboxCount + 1
    jsr SendCommand
Wait:
    lda MailboxData
    bmi Wait
    beq Done
    ldx MailboxCount
    stx BytesMoved
    ldx MailboxCount + 1
    stx BytesMoved + 1
    jsr LatchData
    ldx BytesMoved + 1
    beq Bytes
    sec
    jsr CopyToBuffer                ; the whole pages
Bytes:
    ldx BytesMoved
    beq Done
    clc
    jsr CopyToBuffer                ; the rest
Done:
    jmp FinishNow
.endproc

;; Copies from the window to the buffer.
;; In: carry = set to copy X pages, clear to copy X bytes; ParameterList = the window, CallBuffer = the buffer
;; Out: ParameterList, CallBuffer = past what was copied, for pages; for bytes, Y = X and the pointers unchanged
.proc CopyToBuffer
    ldy #0
Loop:
    lda (ParameterList),y
    bit Identity
    bvc Short
    StoreLongY CallBuffer
    bvs Stored                      ; always
Short:
    sta (CallBuffer),y
Stored:
    iny
    bcc CountBytes
    bne Loop
    inc ParameterList + 1
    inc CallBuffer + 1
    bne CountBytes
    inc CallBuffer + 2
CountBytes:
    dex
    bne Loop
    rts
.endproc

;; WRITE: the card takes the bytes from the buffer.
;; In: CallParameters = the byte count
.proc Write
    lda CallParameters
    sta MailboxCount
    pha
    lda CallParameters + 1
    sta MailboxCount + 1
    pha
    jmp SendData
.endproc

;; CONTROL: the control list starts with its length, which the card takes, then the list.
.proc ControlCall
    ldy #0
    bit Identity
Length:
    bvc Short
    LoadLongY CallBuffer
    bvs Got                         ; always
Short:
    lda (CallBuffer),y
Got:
    sta MailboxCount,y
    pha
    iny
    cpy #1
    beq Length
    lda CallBuffer
    clc
    adc #2
    sta CallBuffer
    bcc SendData
    inc CallBuffer + 1
    bne SendData
    inc CallBuffer + 2
    ; Falls into SendData.
.endproc

;; Sends the command, then the bytes counted on the stack, high byte on top.
.proc SendData
    jsr SendCommand
Wait:
    lda MailboxData
    bmi Wait
    beq Failed
    jsr LatchData
    pla
    tax
    beq Bytes
    sec
    jsr CopyFromBuffer
Bytes:
    pla
    tax
    beq Done
    clc
    jsr CopyFromBuffer
Done:
    clc
    jmp Finish
Failed:
    pla
    pla
    jmp FinishNow
.endproc

;; Copies from the buffer to the window.
;; In: carry = set to copy X pages, clear to copy X bytes; CallBuffer = the buffer, ParameterList = the window
;; Out: ParameterList, CallBuffer = past what was copied, for pages; for bytes, Y = X and the pointers unchanged
.proc CopyFromBuffer
    ldy #0
Loop:
    bit Identity
    bvc Short
    LoadLongY CallBuffer
    bvs Got                         ; always
Short:
    lda (CallBuffer),y
Got:
    sta (ParameterList),y
    iny
    bcc CountBytes
    bne Loop
    inc ParameterList + 1
    inc CallBuffer + 1
    bne CountBytes
    inc CallBuffer + 2
CountBytes:
    dex
    bne Loop
    rts
.endproc

;; Command $0A, <COMMAND_SET_FORMAT>: sends up to four bytes from the buffer in $46-$49, as many as $46 says.
;; In: CallParameters = the count
.proc SetFormat
    lda #0
    ldx CallParameters
    sta CallParameters
    sta CallParameters + 1
    sta CallParameters + 2
    sta CallParameters + 3
    beq Initialize
    cpx #SET_FORMAT_BYTES + 1
    bcc Copy
    ldx #SET_FORMAT_BYTES
Copy:
    ldy #0
Next:
    bit Identity
    bvc Short
    LoadLongY CallBuffer
    bvs Got                         ; always
Short:
    lda (CallBuffer),y
Got:
    sta a:CallParameters,y
    iny
    dex
    bne Next
    ; Falls into Initialize.
.endproc

;; INIT: the card does all of it.
.proc Initialize
    jsr SendCommand
    clc
    jmp Finish
.endproc

;; Latches the bank the card's data is in and points <ParameterList> at it.
;; In: A = <MailboxData>: bits 1-4 the bank, bit 0 the half
;; Out: X = the slot times 16 plus the bank, ParameterList = $C800 or $CA00
;; Keeps: Y
.proc LatchData
    and #DATA_WHERE
    lsr a
    php
    clc
    adc SlotTimes16
    tax
    lda BankLatch,x
    lda #0
    sta ParameterList
    plp
    rol a
    asl a
    adc #>CardWindow
    sta ParameterList + 1
    rts
.endproc

;; READBLOCK and ProDOS's read: 512 bytes from the card.
.proc ReadBlockCall
    jsr SendCommand
    ; Falls into ReceiveBlock.
.endproc

;; Takes a block from the card into the buffer.
;; Out: A = what <Host::Finish> returns: the error, mapped for a ProDOS call
.proc ReceiveBlock
    lda MailboxData
    bmi ReceiveBlock
    bne Data
    lda MailboxError
    jmp Done
Data:
    jsr LatchData
    ldx #2
    ldy #0
    bit Identity
    bvs Long
Copy:
    lda (ParameterList),y
    sta (CallBuffer),y
    iny
    bne Copy
    inc ParameterList + 1
    inc CallBuffer + 1
    dex
    bne Copy
Done:
    sec
    jmp FinishBlock

Long:
    ; The IIgs: native mode at full speed, 16 bits at a time through a long pointer.
    clc
    ExchangeCarryAndEmulation
    php
    lda SpeedRegister
    pha
    ora #FULL_SPEED
    sta SpeedRegister
    lda #%00000010                  ; bit 1 of the window's page: $CA
    bit ParameterList + 1
    ClearStatusBits STATUS_MEMORY_8
    bne UpperHalf
FirstPage:
    lda CardWindow,y
    StoreLongY CallBuffer
    iny
    iny
    lda CardWindow,y
    StoreLongY CallBuffer
    iny
    iny
    bne FirstPage
    inc CallBuffer + 1
SecondPage:
    lda CardWindow + $100,y
    StoreLongY CallBuffer
    iny
    iny
    lda CardWindow + $100,y
    StoreLongY CallBuffer
    iny
    iny
    bne SecondPage
    beq Back                        ; always
UpperHalf:
    lda CardWindow + $200,y
    StoreLongY CallBuffer
    iny
    iny
    lda CardWindow + $200,y
    StoreLongY CallBuffer
    iny
    iny
    bne UpperHalf
    inc CallBuffer + 1
FourthPage:
    lda CardWindow + $300,y
    StoreLongY CallBuffer
    iny
    iny
    lda CardWindow + $300,y
    StoreLongY CallBuffer
    iny
    iny
    bne FourthPage
Back:
    SetStatusBits STATUS_MEMORY_8 | STATUS_INDEX_8
    pla
    sta SpeedRegister
    plp
    ExchangeCarryAndEmulation
    sec
    jmp FinishBlock
.endproc

;; WRITEBLOCK and ProDOS's write: 512 bytes to the card. With <MailboxProgress>'s bit 7 set the copy runs with
;; interrupts off.
.proc WriteBlockCall
    jsr SendCommand
Wait:
    ldx MailboxData
    bmi Wait
    bne Data
    jmp FinishNow
Data:
    lda MailboxProgress
    php
    bpl Window
    sei
    lda #PROGRESS_STARTED
    sta MailboxProgress
Window:
    txa
    jsr LatchData
    ldy #0
    bit Identity
    bvs Long
    plp
    ldx #2
Copy:
    lda (CallBuffer),y
    sta (ParameterList),y
    iny
    bne Copy
    inc CallBuffer + 1
    inc ParameterList + 1
    dex
    bne Copy
    jmp FinishWrite

Long:
    ; The IIgs: each page in turn, telling the card through MailboxProgress as each is ready.
    clc
    ExchangeCarryAndEmulation
    php
    lda SpeedRegister
    pha
    ora #FULL_SPEED
    sta SpeedRegister
    PushX
    lda #%00000010                  ; bit 1 of the window's page: $CA
    bit ParameterList + 1
    ClearStatusBits STATUS_MEMORY_8
    bne UpperHalf
FirstPage:
    LoadLongY CallBuffer
    sta CardWindow,y
    iny
    iny
    LoadLongY CallBuffer
    sta CardWindow,y
    iny
    iny
    bne FirstPage
    inc CallBuffer + 1
    SetStatusBits STATUS_MEMORY_8
    ldx SlotTimes16
    lda BankLatch + BANK_MAILBOX,x
    inc MailboxProgress
    PullX
    lda BankLatch,x
    ClearStatusBits STATUS_MEMORY_8
SecondPage:
    LoadLongY CallBuffer
    sta CardWindow + $100,y
    iny
    iny
    LoadLongY CallBuffer
    sta CardWindow + $100,y
    iny
    iny
    bne SecondPage
    beq Back                        ; always
UpperHalf:
    LoadLongY CallBuffer
    sta CardWindow + $200,y
    iny
    iny
    LoadLongY CallBuffer
    sta CardWindow + $200,y
    iny
    iny
    bne UpperHalf
    inc CallBuffer + 1
    SetStatusBits STATUS_MEMORY_8
    ldx SlotTimes16
    lda BankLatch + BANK_MAILBOX,x
    inc MailboxProgress
    PullX
    lda BankLatch,x
    ClearStatusBits STATUS_MEMORY_8
FourthPage:
    LoadLongY CallBuffer
    sta CardWindow + $300,y
    iny
    iny
    LoadLongY CallBuffer
    sta CardWindow + $300,y
    iny
    iny
    bne FourthPage
Back:
    SetStatusBits STATUS_MEMORY_8 | STATUS_INDEX_8
    pla
    sta SpeedRegister
    plp
    ExchangeCarryAndEmulation
    ldx SlotTimes16
    lda BankLatch + BANK_MAILBOX,x
    lda #PROGRESS_DONE
    sta MailboxProgress
    plp
    ; Falls into FinishWrite.
.endproc

;; A block has gone to the card: waits for the card to finish.
.proc FinishWrite
    clc
    ; Falls into FinishBlock.
.endproc

;; A block has moved: counts 512 bytes and finishes.
;; In: carry = set to finish without waiting for the card
.proc FinishBlock
    lda #>512
    sta BytesMoved + 1
    bne Finish                      ; always
.endproc

;; Finishes a call without waiting for the card.
.proc FinishNow
    sec
    ; Falls into Finish.
.endproc

;; Tells the card the data is taken, waits for it unless carry is set, and takes its error.
;; In: carry = set not to wait
;; Out: CallResult = the error, mapped for ProDOS
;; Keeps: Y
.proc Finish
    ldx SlotTimes16
    lda BankLatch + BANK_MAILBOX,x
    lda MailboxData
    ora #DATA_TAKEN
    sta MailboxData
    bcs Error
Wait:
    lda MailboxState
    bpl Wait
Error:
    lda MailboxError
    jsr MapProDosError
    sta CallResult
    ldx #0
    stx MailboxError
    rts
.endproc

;; Sends the command in page zero: waits for the card, gives it $43-$4B and then the command.
;; Keeps: X, Y
.proc SendCommand
    lda MailboxState
    bpl SendCommand
    lda #DATA_SENDING
    sta MailboxData
    txa
    pha
    ldx #CALL_BYTES - 1
Copy:
    lda CallCommand,x
    sta MailboxCommand,x
    dex
    bpl Copy
    pla
    tax
    lda MailboxCommand
    and #COMMAND_BITS
    sta MailboxState
    rts
.endproc

;; Each slot's number times 16, for slots 1 to 7, indexed by $Cn less $C1.
SlotTimes16Table:
    .byte $10, $20, $30, $40, $50, $60, $70

;; Turns a ProDOS call into SmartPort's: the command with bit 7 set, the buffer in $40-$42, a three-byte block, and
;; the unit. A unit in this slot is SmartPort unit 1 or 2 by its drive bit; one ProDOS mapped to slot 2 is unit 3 or
;; 4, and one mapped to any other slot 5 or 6. Unit 0 for slot 0.
;; In: A = the ProDOS command, ProDos::UnitNumber = the ProDOS unit, Y = $Cn
;; Keeps: Y
.proc ProDosToSmartPort
    ora #CALL_PRODOS
    ldx ProDos::UnitNumber
    sta CallCommand
    lda ProDos::Buffer
    sta CallBuffer
    lda ProDos::BufferHigh
    sta CallBuffer + 1
    lda #0
    sta CallBuffer + 2
    sta CallParameters + 2
    sta CallParameters + 3
    txa
    and #$70
    beq Unit
    lsr a
    lsr a
    lsr a
    lsr a
    ora #$C0
    sta CallUnit
    lda #0
    cpy CallUnit
    beq AddDriveBit
    lda #$C0
    eor CallUnit
    cmp #2
    beq AddDriveBit
    lda #4
AddDriveBit:
    cpx #$80
    adc #1
Unit:
    sta CallUnit
    rts
.endproc

;; Asks the card for its diagnostics, finding the slot from the caller's return address.
;; Out: A = 0, ExpansionRomSlot = $Cn
.proc AskForDiagnostics
    tsx
    lda StackPage + 2,x
    sta ExpansionRomSlot
    tay
    ldx SlotTimes16Table - $C1,y
    lda BankLatch + BANK_MAILBOX,x
Wait:
    bit MailboxState
    bpl Wait
    lda #COMMAND_DIAGNOSTICS
    sta MailboxState
    lda #0
    rts
.endproc

;; The boot failed: goes on to the next slot when the Monitor's scan brought it here, else says why and starts BASIC.
;; In: CallResult = <ERROR_NEVER_READY> when the card did not answer
.proc NoBoot
    bit LanguageCardRomOnly
    lda SlotPointer
    bne Say
    lda LOC1
    cmp ExpansionRomSlot
    bne Say
    jmp Startup::PowerUp::NextSlot
Say:
    jsr SetScreen
    jsr SetKeyboard
    jsr SetText
    jsr Home
    ldy #0
    lda CallResult
    cmp #ERROR_NEVER_READY
    bne Print
    ldy #NeverReadyText - UnableToBootText
Print:
    ldx #0
Next:
    lda UnableToBootText,y
    beq Done
    sta MessageAt,x
    iny
    inx
    bne Next                        ; always
Done:
    jmp BasicColdStart
.endproc

;; What the host says when it cannot boot, in ASCII with the high bit set, the screen's normal characters, ending
;; with 0.
UnableToBootText:
    .hiascii "UNABLE TO BOOT"
    .byte 0

;; What it says when the card never answered.
NeverReadyText:
    .hiascii "CONTROLLER NEVER READY"
    .byte 0

;; Runs the unit's hook in the card's RAM at <UnitHooks> with bank 2 latched, for units 1 to 4. The card puts an RTS
;; in each.
;; In: X = the slot times 16
;; Keeps: X, Y
.proc RunUnitHook
    lda CallUnit
    beq Done
    cmp #LAST_HOOK_UNIT + 1
    bcs Done
    tya
    pha
    txa
    pha
    lda BankLatch + BANK_SAVE,x
    jsr Go
    pla
    tax
    lda BankLatch + BANK_MAILBOX,x
    pla
    tay
Done:
    rts
Go:
    lda #>UnitHooks
    pha
    ldx CallUnit
    lda Hooks - 1,x
    pha
    rts
Hooks:
    .byte <(UnitHooks - 1), <(UnitHooks + UNIT_HOOK_SIZE - 1), <(UnitHooks + 2 * UNIT_HOOK_SIZE - 1)
    .byte <(UnitHooks + 3 * UNIT_HOOK_SIZE - 1)
.endproc

;; Marks a call as running, or refuses a second one while the first runs. A boot, or a call before the host is
;; identified, clears the mark instead.
;; In: overflow = set for a boot, bank 2 latched
;; Out: A = 1 and carry = set, returned from the call itself, for a second call
;; Keeps: X, Y
.proc MarkCallRunning
    bvs Clear
    bit Identity
    bpl Mark
Clear:
    lda #0
    sta CallBusy
    rts
Mark:
    bit CallBusy
    bmi Busy
    lda #CALL_RUNNING
    sta CallBusy
    rts
Busy:
    pla
    pla
    lda #1
    plp
    sec
    rts
.endproc

    .res 7
.assert * = $CFFF, "The host's code must leave $CFFF, which releases the window, for its last byte."
    .byte 0

.endscope
.logicalorg
