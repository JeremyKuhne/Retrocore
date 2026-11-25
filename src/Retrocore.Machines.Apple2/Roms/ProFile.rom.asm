; retrocore: style=strict
; Copyright (c) 2025 Jeremy W Kuhne
; SPDX-License-Identifier: MIT
; See LICENSE file in the project root for full license information
;
; EMULATED PROFILE INTERFACE CARD FIRMWARE
;
; WHAT THIS FILE IS
;
; The 256-byte slot ROM of the emulator's ProFile interface card for the Apple II.
; It makes Apple's ProFile hard disk a ProDOS block device: it boots from it, and
; ProDOS reads, writes and asks the status of its blocks through it. It is our own
; firmware, not a copy of Apple's card's ROM, so its names are its own. Unlike the
; slot 7 block device, it does the card's work itself: it talks to the ProFile over
; the card's ports with the same handshakes as Apple's SOS driver for the Apple
; III's ProFile card (Apple3/Roms/Sos/Drivers/Profile), a byte at a time, and
; ProFileDrive in C# plays the ProFile's part.
;
; THE CARD
;
; The card's ports are at $C080 plus 16 times the slot, as on the Apple III's card
; for the first four, with its lines at the next four, since the Apple II's card
; keeps its $Cn00 page for this ROM:
;   +0  write: a byte to the ProFile (DataOut)
;   +1  read: a byte from the ProFile (DataIn)
;   +2  read: bit 7 set while BSY is low (the ProFile ready), bit 0 set when no
;       ProFile answers (CardStatus)
;   +3  write: clears a parity error (there are none)
;   +4  any access: CMD low (CommandOff)   +5  any access: CMD high (CommandOn)
;   +6  any access: reset the ProFile      +7  any access: let it go
;   +8  read: the ProFile's size in blocks, low byte (at most 65535) (BlockCount)
;   +9  read: its high byte (BlockCountHigh)
;
; THE PROFILE'S HANDSHAKE
;
; The card raises CMD; the ProFile raises BSY with a response on the port saying
; what it is ready for; the card answers $55 to go on, or $AA to refuse, and drops
; CMD; the ProFile does what it said and drops BSY. A read: response 1, then six
; command bytes (0 to read, the three-byte block number, a retry count and a
; sparing threshold); response 2, and the ProFile has four status bytes, then the
; block, ready to read. A write: response 1 and the command (1 to write); response
; 3, then the 512 bytes; response 6, when the ProFile writes the block, then the
; four status bytes. Bit 0 of the first status byte says the operation failed.
;
; STATUS reads the size from the card's ports +8 and +9, which Retrocore's card adds:
; Apple's ProFile tells its size only in its identification block, $FFFFFF, and
; reading that through the handshakes leaves no room in 256 bytes. FORMAT does
; nothing, since a ProFile comes formatted.
;
; ProDOS mailbox ABI:
;   $42 command: 0=status, 1=read, 2=write, 3=format (which does nothing).
;   $43 unit: drive bit 7 and slot bits 6..4. The card is one volume ($CnFE), so
;   ProDOS asks only for drive one, and the driver does not look at the drive bit.
;   $44/$45 buffer address, $46/$47 block number, both little endian.
;   A=0 and carry clear on success; A=error and carry set on failure ($27 an I/O
;   error, a failed block or a refused handshake, $28 no ProFile). Status returns
;   the block count in X (low) and Y (high); the card takes images of at most
;   65535 blocks, ProDOS's most.
;
; The ROM uses no absolute address inside itself, only branches, so the same bytes
; work in any slot. It is assembled at $C500. It runs on the 6502 of the II Plus
; and the original IIe, so it reaches the card's lines with LDA, not BIT abs,X.
; The ProFile emulated here answers at once, so the waits for BSY have no timeout.

.rom Retrocore.Machines.Apple2.ProFileRom, $C500, $100
.cpu Mos6502
.export Driver, DeviceInfo

; The ProDOS block-device mailbox in page zero, which the caller fills before calling <Driver>.

;; The ProDOS command: <COMMAND_STATUS>, <COMMAND_READ>, <COMMAND_WRITE> or <COMMAND_FORMAT>.
Command = $42

;; The ProDOS unit number: the drive in bit 7 (clear for drive 1) and the slot in bits 6-4.
UnitNumber = $43

;; The address of the caller's 512-byte buffer, low byte; <BufferHigh> is the high byte.
Buffer = $44

;; The high byte of <Buffer>.
BufferHigh = $45

;; The block number, low byte; <BlockHigh> is the high byte.
Block = $46

;; The high byte of <Block>.
BlockHigh = $47

; The ProDOS commands.

;; Returns the device's size in blocks.
COMMAND_STATUS = 0

;; Reads a block into the buffer.
COMMAND_READ = 1

;; Writes the buffer to a block.
COMMAND_WRITE = 2

;; Formats the device; commands above it don't exist, and the driver takes them as this one.
COMMAND_FORMAT = 3

; The ProDOS errors the driver returns.

;; An I/O error: the ProFile failed the operation or answered with a response the card didn't expect.
ERROR_IO = $27

;; No device connected: no ProFile answers.
ERROR_NO_DEVICE = $28

; The Monitor's locations and entries this firmware uses.

;; Inherit: <Monitor:SlotPointer>
SlotPointer = $00

;; Inherit: <Monitor:LOC1>
LOC1 = $01

;; The label inside the Monitor's <Monitor:SaveRegisters> that the firmware calls.
.scope SaveRegisters

;; An RTS at $FF58 in every Apple II Monitor, which the firmware calls to find its slot from the stack.
;;
;; Inherit: <Monitor:SaveRegisters::Return>
Return = $FF58

.endscope

;; The Autostart and IIe Monitors' power-up, whose scan for a disk controller the firmware goes back to when its boot
;; fails.
.scope Startup

;; The power-up routine that holds the scan.
.scope PowerUp

;; Tries the next slot down; past slot 1, starts BASIC. It points <SlotPointer>/<LOC1> at the slot it tries.
;;
;; The Apple II's original Monitor has no scan: it has a JSR at $FABA, not this LDY #.
;; Inherit: <Monitor:Startup::PowerUp::NextSlot>
NextSlot = $FABA

.endscope

.endscope

;; The opcode of LDY #, the first instruction of <Startup::PowerUp::NextSlot> in the Monitors that scan the slots.
OPCODE_LDY_IMMEDIATE = $A0

; Memory the boot uses.

;; The 6502's stack page.
StackPage = $0100

;; The page ProDOS's boot block is read to: $0800.
BOOT_PAGE = $08

;; Where the boot block's code starts, after its first byte.
BootEntry = $0801

; The card's ports: each is at this address plus 16 times the slot, which the driver keeps in X.

;; Write: sends a byte to the ProFile.
DataOut = $C080

;; Read: a byte from the ProFile.
DataIn = $C081

;; Read: bit 7 set while BSY is low (the ProFile ready), bit 0 set when no ProFile answers.
CardStatus = $C082

;; Any access: drops CMD.
CommandOff = $C084

;; Any access: raises CMD.
CommandOn = $C085

;; Read: the ProFile's size in blocks, low byte; <BlockCountHigh> is the high byte. Retrocore's card adds this port.
BlockCount = $C088

;; Read: the high byte of <BlockCount>.
BlockCountHigh = $C089

; The ProFile's responses, which say what it is ready for, and the card's answers.

;; Ready for a command's six bytes.
RESPONSE_COMMAND = 1

;; Read the block: its status and data are ready.
RESPONSE_READ = 2

;; Ready for a write's 512 bytes.
RESPONSE_WRITE_DATA = 3

;; Wrote the block: its status is ready.
RESPONSE_WRITTEN = 6

;; The card's answer to go on.
ANSWER_GO_ON = $55

;; The card's answer to refuse.
ANSWER_REFUSE = $AA

; The ProDOS device-capability bits at $CnFE.

;; Bits 5-4: the number of volumes less one.
ONE_VOLUME = %00000000

;; Formats.
CAPABILITY_FORMAT = %00001000

;; Writes.
CAPABILITY_WRITE = %00000100

;; Reads.
CAPABILITY_READ = %00000010

;; Returns its status.
CAPABILITY_STATUS = %00000001

; The four signature bytes the Monitor and ProDOS look for in a disk controller's page, which Boot's first
; instructions carry as their operands.

;; At $Cn01: a disk controller.
SIGNATURE_01 = $20

;; At $Cn03: a disk controller.
SIGNATURE_03 = $00

;; At $Cn05: a disk controller.
SIGNATURE_05 = $03

;; At $Cn07: $3C, not $00: a ProDOS block device that is not a SmartPort.
SIGNATURE_07 = $3C

;; Boots the ProFile: reads block 0 to $0800 through <Driver>, which returns to <FinishBoot>.
;;
;; It finds its slot from the return address an RTS in the Monitor leaves on the stack, and pushes <FinishBoot> in
;; this slot's page as the driver's return address. It points <SlotPointer>/<LOC1> at this slot, as the startup scan
;; does, so that a failed boot can go on with the scan, however the card was started.
.proc Boot
    ; The signature: these loads are executed, but only their operands matter.
    ldx #SIGNATURE_01
    ldy #SIGNATURE_03
    ldx #SIGNATURE_05
    ldy #SIGNATURE_07

    ; The slot: the high byte of the return address the JSR leaves is this page, $Cn.
    jsr SaveRegisters::Return
    tsx
    lda StackPage,x
    sta LOC1
    pha                             ; the driver returns to FinishBoot in this page
    asl a
    asl a
    asl a
    asl a
    sta UnitNumber                  ; drive 1 in this slot
    lda #<(FinishBoot - 1)
    pha

    ; The request: read block 0 to $0800.
    lda #BOOT_PAGE
    sta BufferHigh
    lda #0
    sta SlotPointer
    sta Buffer
    sta Block
    sta BlockHigh
    lda #COMMAND_READ
    sta Command
    bne Driver
.endproc

;; Returns no device.
;; Out:   A = <ERROR_NO_DEVICE>, carry = set
.proc FailNoDevice
    lda #ERROR_NO_DEVICE
    sec
    rts
.endproc

;; Returns success.
;; Out:   A = 0, carry = clear
.proc Succeed
    lda #0
    clc
    rts
.endproc

;; The ProDOS block-device entry: performs the command in the zero-page mailbox.
;;
;; Its address's low byte is at $CnFF, where ProDOS finds it. A format, which a ProFile needs none of, and the
;; commands above it, which don't exist, succeed without doing anything.
;; In:    Command = <COMMAND_STATUS>, <COMMAND_READ>, <COMMAND_WRITE> or <COMMAND_FORMAT>; UnitNumber = the slot,
;;          Buffer/BufferHigh = the buffer, Block/BlockHigh = the block number
;; Out:   A = 0 or a ProDOS error code, carry = clear on success, set on error,
;;          X = the block count's low byte for status; otherwise the slot times 16,
;;          Y = the block count's high byte for status
;; Keeps: Command, UnitNumber, Buffer, BufferHigh, Block, BlockHigh
.proc Driver
    ; The card's ports, through X; with no ProFile, no device.
    lda UnitNumber
    and #$70
    tax
    lda CardStatus,x
    lsr a
    bcs FailNoDevice

    ; Status: the size from the card's ports.
    lda Command
    bne Transfer
    lda BlockCountHigh,x
    tay
    lda BlockCount,x
    tax
    bcc Succeed                     ; carry is clear from the status

    ; A read or a write starts with a handshake for the command.
Transfer:
    cmp #COMMAND_FORMAT
    bcs Succeed
    ldy #RESPONSE_COMMAND
    bne Handshake
.endproc

;; Sends the six command bytes after response 1: the command (0 to read, 1 to write), the block number, the retry
;; count and the sparing threshold; then makes the handshake for the read's result or the write's data.
;; In:    X = the slot times 16, carry = set
.proc SendCommand
    lda Command
    sbc #1
    sta DataOut,x
    lda #0
    sta DataOut,x                   ; the block number's high byte
    lda BlockHigh
    sta DataOut,x
    lda Block
    sta DataOut,x
    lda #0
    sta DataOut,x                   ; the retry count
    sta DataOut,x                   ; the sparing threshold
    ldy Command
    iny                             ; RESPONSE_READ for a read, RESPONSE_WRITE_DATA for a write
    bne Handshake
.endproc

;; Sends the block's 512 bytes after response 3, then waits for the ProFile to write them.
;; In:    X = the slot times 16
.proc SendData
    ldy #0
FirstPage:
    lda (Buffer),y
    sta DataOut,x
    iny
    bne FirstPage
    inc BufferHigh
SecondPage:
    lda (Buffer),y
    sta DataOut,x
    iny
    bne SecondPage
    dec BufferHigh
    ldy #RESPONSE_WRITTEN
    ; Falls into Handshake.
.endproc

;; Makes a handshake and goes on from the response: the command after response 1, the data after response 3, and
;; the result after responses 2 and 6.
;; In:    Y = the response expected, X = the slot times 16
.proc Handshake
    lda CommandOn,x
WaitForResponse:
    lda CardStatus,x
    bmi WaitForResponse             ; until BSY is high, the response on the port
    tya
    cmp DataIn,x
    bne Refuse
    lda #ANSWER_GO_ON
    sta DataOut,x
    lda CommandOff,x
WaitForDone:
    lda CardStatus,x
    bpl WaitForDone                 ; until BSY is low again

    ; Goes on from the response.
    dey
    beq SendCommand                 ; RESPONSE_COMMAND
    dey
    dey
    beq SendData                    ; RESPONSE_WRITE_DATA
    ; Falls into ReadResult.
.endproc

;; Reads the four status bytes after response 2 or 6, then for a read the block.
;; In:    X = the slot times 16
.proc ReadResult
    lda DataIn,x
    lsr a
    bcs Fail                        ; the operation failed
    ldy #3
OtherStatus:
    lda DataIn,x
    dey
    bne OtherStatus

    ; A read's block.
    lda Command
    lsr a
    bcc Done                        ; a write
FirstPage:
    lda DataIn,x
    sta (Buffer),y
    iny
    bne FirstPage
    inc BufferHigh
SecondPage:
    lda DataIn,x
    sta (Buffer),y
    iny
    bne SecondPage
    dec BufferHigh
Done:
    lda #0
    clc
    rts
.endproc

;; Refuses a response the card did not expect, which leaves the ProFile waiting for a command, and returns an I/O
;; error.
;; In:    X = the slot times 16
.proc Refuse
    lda #ANSWER_REFUSE
    sta DataOut,x
    lda CommandOff,x
    ; Falls into Fail.
.endproc

;; Returns an I/O error.
;; Out:   A = <ERROR_IO>, carry = set
.proc Fail
    lda #ERROR_IO
    sec
    rts
.endproc

;; Where <Driver> returns at boot: runs block 0 at $0801 when it was read, with X = the slot times 16. Otherwise, as
;; when the scan finds no disk in a slot, it goes on with the Monitor's startup scan from the next lower slot, or
;; stops here with the II's original Monitor, which has no scan to go back to.
;; In:    carry = set when the read failed, X = the slot times 16
.proc FinishBoot
    bcs Failed
    jmp BootEntry
Failed:
    lda Startup::PowerUp::NextSlot
    cmp #OPCODE_LDY_IMMEDIATE
Stop:
    bne Stop                        ; the original Monitor
    jmp Startup::PowerUp::NextSlot
.endproc

.assert * <= $C5FC
.org $C5FC
    ; The ProDOS identification trailer: the block count at $CnFC (0, so ProDOS asks STATUS), the capability byte
    ; at $CnFE and the low byte of Driver at $CnFF.
    .word 0

;; The ProDOS device-capability byte at $CnFE, followed by the low byte of <Driver> at $CnFF: one volume that
;; reads, writes, formats and returns its status.
DeviceInfo:
    .byte ONE_VOLUME | CAPABILITY_FORMAT | CAPABILITY_WRITE | CAPABILITY_READ | CAPABILITY_STATUS
    .byte <Driver
.assert * == $C600
