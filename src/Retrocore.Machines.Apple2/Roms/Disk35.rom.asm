; Copyright (c) 2025 Jeremy W Kuhne
; SPDX-License-Identifier: MIT
; See LICENSE file in the project root for full license information
;
; EMULATED 3.5 DISK CONTROLLER CARD FIRMWARE
;
; WHAT THIS FILE IS
;
; The 256-byte slot ROM of the emulator's 3.5-inch disk controller, a card that
; answers as Apple's Apple II 3.5 Disk Controller Card does: a SmartPort with two
; drives that take 400K and 800K Apple disks and 720K and 1440K MFM disks. It is our
; own firmware, not a copy of Apple's: Apple's card has its own 65C02 that runs the
; drives and talks to the Apple II through shared RAM (Disk35/Disk35Controller.asm
; is its EPROM, for comparison). Here Apple2Disk35Card does the card's work in C#,
; and this ROM only carries each call across to it.
;
; HOW PROGRAMS FIND AND CALL IT
;
; As on Apple's card: $Cn01 = $20, $Cn03 = $00, $Cn05 = $03 and $Cn07 = $00 mark a
; SmartPort; $CnFB = $C0, $CnFC-$CnFD = 0 (ask STATUS for the size), $CnFE = $BF
; (removable, interruptible, four volumes, format, write, read, status) and $CnFF =
; $1C put the ProDOS entry at $Cn1C and the SmartPort entry at $Cn1F. $Cn00 boots
; the first drive. Apple's card starts its diagnostics from $Cn0D; this one has
; none, so $Cn0D returns.
;
; HOW A CALL CROSSES INTO C#
;
; Each entry goes to Call with carry set for SmartPort and overflow set to boot.
; Call keeps the caller's status on the stack, finds the slot with an RTS it writes
; at $06 for a moment, as Apple's mouse firmware does, and writes the stack pointer
; to the card's command port at $C080 plus 16 times the slot. That write runs the
; call in C#, which reads the caller's status and return address from the stack, the
; command and parameter list after a SmartPort JSR, and moves the return address past
; them. Call reads back A, X and Y, gives the caller back its interrupt flag, and
; returns with carry set when A is not 0.
;
; A boot reads block 0 of the first drive into $0800 and sets up ProDOS's page zero
; ($42-$47) as for that read; a block that starts with $01 and a nonzero byte runs at
; $0801 with X = the slot times 16. Otherwise the boot goes on to the next slot when
; the Monitor's scan brought it here, or says UNABLE TO BOOT and starts BASIC, as
; Apple's card does.
;
; Ports (offsets from $C080 + $n0); reading any of them changes nothing but +3:
;   +0  write: the stack pointer, which runs the call; read: the A to return
;   +1  read: the X to return
;   +2  read: the Y to return
;   +3  read: writes UNABLE TO BOOT on the screen
;
; The ROM uses no absolute address inside itself, only branches, so the same bytes
; work in any slot. It is assembled at $C500, the slot people often gave the card.

.rom Retrocore.Machines.Apple2.Disk35Rom, $C500, $100
.cpu Mos6502
.export PRODOS, SMARTPORT, DIAG, Signature

LOC0 = $00                          ; the Monitor's slot pointer, $Cn00 while it boots slot n
LOC1 = $01
ZeroPageRts = $06                   ; where Call puts an RTS for a moment
StackPage = $0100
BootBlock = $0801                   ; where a ProDOS boot block starts
CallPort = $C080
XPort = $C081
YPort = $C082
MessagePort = $C083
LCROM = $C082                       ; the language card's ROM, read
BASIC = $E000                       ; AppleSoft's cold start
SLOOP = $FABA                       ; the Monitor's boot scan, which goes on to the next slot
SETTXT = $FB39
HOME = $FC58
SETKBD = $FE89
SETVID = $FE93

;; Boots the first drive. The four loads are the SmartPort identification at $Cn01-$Cn07; overflow, set by the
;; addition, makes the call a boot.
Boot:
    ldx #$20
    ldx #$00
    ldy #$03
    lda #$00
    sec
    adc #$7F
    bvs Call                        ; always

.assert * == $C50D
;; Apple's card's diagnostics entry: this card has none.
DIAG:
    rts

    .res $C51C - *
.assert * == $C51C
;; The ProDOS block-device entry.
;; In:    $42 = the command (0 status, 1 read, 2 write, 3 format), $43 = the unit, $44/$45 = the buffer,
;;          $46/$47 = the block
;; Out:   A = 0 or the error, carry = set on an error; X/Y = the block count after status
PRODOS:
    clc
    bcc Plain                       ; always

.assert * == $C51F
;; The SmartPort entry: JSR $Cn1F, then the command and the parameter list's address (four bytes for an extended
;; command), which the call steps over.
;; Out:   A = 0 or the error, carry = set on an error, X/Y = the bytes moved
SMARTPORT:
    sec
Plain:
    clv

;; Carries a call to the card and returns what it gives back.
;; In:    carry = set for SmartPort, overflow = set to boot
;; Out:   A, X and Y = as the card returns them, carry = set when A is not 0
;; Keeps: interrupt
Call:
    php                             ; the caller's interrupt flag, and how it came
    sei
    ldy ZeroPageRts
    lda #$60                        ; RTS
    sta ZeroPageRts
    jsr ZeroPageRts                 ; leaves its return address's high byte, $Cn, just below the stack
    sty ZeroPageRts
    tsx
    lda StackPage,x
    asl a
    asl a
    asl a
    asl a
    tay                             ; $n0, the slot's port offset
    txa
    sta CallPort,y                  ; runs the call
    lda XPort,y
    tax
    lda CallPort,y
    pha
    lda YPort,y
    tay
    pla
    plp
    bvs Call_Boot
    cmp #1                          ; carry = an error
    ora #0
    rts
Call_Boot:
    ora #0
    bne Call_NoBoot
    jmp BootBlock                   ; X = $n0
Call_NoBoot:
    bit LCROM
    lda LOC0
    bne Call_Unable
    cpy LOC1                        ; Y = $Cn
    bne Call_Unable
    jmp SLOOP
Call_Unable:
    txa
    pha
    jsr SETVID
    jsr SETKBD
    jsr SETTXT
    jsr HOME
    pla
    tay
    lda MessagePort,y
    jmp BASIC

.assert * <= $C5FB
.org $C5FB
;; The SmartPort's identification after the entry points, as Apple's card gives it.
Signature:
    .byte $C0                       ; $CnFB: extended SmartPort calls
    .word 0                         ; $CnFC: ask STATUS for the block count
    .byte $BF                       ; $CnFE: removable, interruptible, four volumes, format, write, read, status
    .byte <PRODOS                   ; $CnFF: the ProDOS entry
.assert * == $C600
