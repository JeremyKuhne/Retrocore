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
; firmware, not a copy of Apple's card's ROM. Unlike the slot 7 block device, it
; does the card's work itself: it talks to the ProFile over the card's ports with
; the same handshakes as Apple's SOS driver for the Apple III's ProFile card
; (Apple3/Roms/Sos/Drivers/Profile), a byte at a time, and ProFileDrive in C#
; plays the ProFile's part.
;
; THE CARD
;
; The card's ports are at $C080 plus 16 times the slot, as on the Apple III's card
; for the first four, with its lines at the next four, since the Apple II's card
; keeps its $Cn00 page for this ROM:
;   +0  write: a byte to the ProFile
;   +1  read: a byte from the ProFile
;   +2  read: bit 7 set while BSY is low (the ProFile ready), bit 0 set when no
;       ProFile answers
;   +3  write: clears a parity error (there are none)
;   +4  any access: CMD low          +5  any access: CMD high
;   +6  any access: reset the ProFile +7  any access: let it go
;   +8  read: the ProFile's size in blocks, low byte (at most 65535)
;   +9  read: its high byte
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
;   error, a failed block or a refused handshake, $28 no ProFile). Status returns the block count in X (low) and Y (high); the card takes
;   images of at most 65535 blocks, ProDOS's most.
;
; The ROM uses no absolute address inside itself, only branches, so the same bytes
; work in any slot. It is assembled at $C500. It runs on the 6502 of the II Plus
; and the original IIe, so it reaches the card's lines with LDA, not BIT abs,X.
; The ProFile emulated here answers at once, so the waits for BSY have no timeout.

.rom Retrocore.Machines.Apple2.ProFileRom, $C500, $100
.cpu Mos6502
.export Driver, DeviceInfo

Command = $42
Unit = $43
BufferLow = $44
BufferHigh = $45
BlockLow = $46
BlockHigh = $47
IORTS = $FF58                       ; an RTS in every Apple II Monitor
StackPage = $0100
BootPage = $08                      ; ProDOS's boot block goes to $0800 and starts at $0801
BootEntry = $0801

; The Autostart Monitor's startup scan: LOC0/LOC1 point at the slot it is trying, and SLOOP tries the next lower one,
; going on to BASIC after slot 1. The II's original Monitor has no scan; it has a JSR at $FABA, not SLOOP's LDY #.
LOC0 = $00
LOC1 = $01
SLOOP = $FABA
LdyImmediate = $A0

DataOut = $C080
DataIn = $C081
Status = $C082
CommandLow = $C084
CommandHigh = $C085
BlocksLow = $C088
BlocksHigh = $C089

; The ProFile's responses and the card's answers.
ReadyResponse = 1
ReadResponse = 2
WriteResponse = 3
WrittenResponse = 6
Acknowledge = $55
Refuse = $AA

; The ProDOS command that formats, and above it those there are not.
FormatCommand = 3

; ProDOS errors.
IoError = $27
NoDevice = $28

; ProDOS device-capability bits at $CnFE.
OneVolume = %00000000
FormatCapabilityMask = %00001000
WriteCapabilityMask = %00000100
ReadCapabilityMask = %00000010
StatusCapabilityMask = %00000001

;; Boots the ProFile: reads block 0 to $0800 through <Driver>, which returns to <BootRead>.
;;
;; It finds its slot from the return address an RTS in the Monitor leaves on the stack, and pushes <BootRead> in this
;; slot's page as the driver's return address. It points LOC0/LOC1 at this slot, as the startup scan does, so that a
;; failed boot can go on with the scan, however the card was started.
Boot:
    ldx #$20                        ; $Cn01 = $20, $Cn03 = $00, $Cn05 = $03: a ProDOS block device
    ldy #$00
    ldx #$03
    ldy #$3C                        ; $Cn07 = $3C, not $00: no SmartPort
    jsr IORTS
    tsx
    lda StackPage,x                 ; $Cn, the high byte of the return address
    sta LOC1
    pha                             ; the driver returns to BootRead in this page
    asl a
    asl a
    asl a
    asl a
    sta Unit                        ; drive 1 in this slot
    lda #<(BootRead - 1)
    pha
    lda #BootPage
    sta BufferHigh
    lda #0
    sta LOC0
    sta BufferLow
    sta BlockLow
    sta BlockHigh
    lda #1
    sta Command
    bne Driver

;; Returns no device.
NoDrive:
    lda #NoDevice
    sec
    rts

;; Returns success.
Done:
    lda #0
    clc
    rts

;; The ProDOS block-device entry: performs the command in the zero-page mailbox.
;; In:    Command = 0 for status, 1 to read, 2 to write, 3 (or above) to format; Unit = the slot,
;;          BufferLow/BufferHigh = the buffer, BlockLow/BlockHigh = the block number
;; Out:   A = 0 or a ProDOS error code, carry = clear on success, set on error; X/Y = the block count, for status;
;;          otherwise X = the slot times 16
;; Uses:  A, X, Y
Driver:
    lda Unit
    and #$70
    tax
    lda Status,x
    lsr a
    bcs NoDrive                     ; no ProFile
    lda Command
    bne Driver_Block
    lda BlocksHigh,x
    tay
    lda BlocksLow,x
    tax
    bcc Done                        ; carry is clear from the status
Driver_Block:
    cmp #FormatCommand
    bcs Done                        ; format, which a ProFile needs none of
    ldy #ReadyResponse
    bne Handshake

;; Sends the six command bytes after response 1: the command (0 to read, 1 to write), the block number, the retry
;; count and the sparing threshold.
;; In:    X = the slot times 16, carry = set
SendCommand:
    lda Command
    sbc #1
    sta DataOut,x
    lda #0
    sta DataOut,x                   ; the block number's high byte
    lda BlockHigh
    sta DataOut,x
    lda BlockLow
    sta DataOut,x
    lda #0
    sta DataOut,x                   ; the retry count
    sta DataOut,x                   ; the sparing threshold
    ldy Command
    iny                             ; response 2 for a read, 3 for a write
    bne Handshake

;; Sends the block's 512 bytes after response 3, then waits for the ProFile to write them.
;; In:    X = the slot times 16
SendData:
    ldy #0
SendData_Low:
    lda (BufferLow),y
    sta DataOut,x
    iny
    bne SendData_Low
    inc BufferHigh
SendData_High:
    lda (BufferLow),y
    sta DataOut,x
    iny
    bne SendData_High
    dec BufferHigh
    ldy #WrittenResponse

;; Makes a handshake and goes on from the response: the command after response 1, the data after response 3, and
;; the result after responses 2 and 6.
;; In:    Y = the response expected, X = the slot times 16
Handshake:
    lda CommandHigh,x
Handshake_Busy:
    lda Status,x
    bmi Handshake_Busy              ; until BSY is high, the response on the port
    tya
    cmp DataIn,x
    bne Refused
    lda #Acknowledge
    sta DataOut,x
    lda CommandLow,x
Handshake_Ready:
    lda Status,x
    bpl Handshake_Ready             ; until BSY is low again
    dey
    beq SendCommand                 ; response 1
    dey
    dey
    beq SendData                    ; response 3

;; Reads the four status bytes after response 2 or 6, then for a read the block.
;; In:    X = the slot times 16
Result:
    lda DataIn,x
    lsr a
    bcs Failed                      ; the operation failed
    ldy #3
Result_Status:
    lda DataIn,x                    ; the other status bytes
    dey
    bne Result_Status
    lda Command
    lsr a
    bcc Result_Done                 ; a write
Result_Low:
    lda DataIn,x
    sta (BufferLow),y
    iny
    bne Result_Low
    inc BufferHigh
Result_High:
    lda DataIn,x
    sta (BufferLow),y
    iny
    bne Result_High
    dec BufferHigh
Result_Done:
    lda #0
    clc
    rts

;; Refuses a response the card did not expect, which leaves the ProFile waiting for a command, and returns an I/O
;; error.
;; In:    X = the slot times 16
Refused:
    lda #Refuse
    sta DataOut,x
    lda CommandLow,x

;; Returns an I/O error.
Failed:
    lda #IoError
    sec
    rts

;; Where <Driver> returns at boot: runs block 0 at $0801 when it was read, with X = the slot times 16. Otherwise, as
;; when the scan finds no disk in a slot, it goes on with the Monitor's startup scan from the next lower slot, or
;; stops here with the II's original Monitor, which has no scan to go back to.
;; In:    carry = set when the read failed, X = the slot times 16
BootRead:
    bcs BootRead_Failed
    jmp BootEntry
BootRead_Failed:
    lda SLOOP
    cmp #LdyImmediate
BootRead_Stop:
    bne BootRead_Stop               ; the original Monitor
    jmp SLOOP

.assert * <= $C5FC
.org $C5FC
;; The ProDOS identification trailer: the block count at $CnFC (0, so ProDOS asks STATUS), the capability byte at
;; $CnFE and the low byte of <Driver> at $CnFF.
    .word 0
DeviceInfo:
    .byte OneVolume | FormatCapabilityMask | WriteCapabilityMask | ReadCapabilityMask | StatusCapabilityMask
    .byte <Driver
.assert * == $C600
