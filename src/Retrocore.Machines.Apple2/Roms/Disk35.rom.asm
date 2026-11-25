; retrocore: style=strict
; Copyright (c) 2025 Jeremy W Kuhne
; SPDX-License-Identifier: MIT
; See LICENSE file in the project root for full license information

;; THE EMULATED 3.5 DISK CONTROLLER CARD'S FIRMWARE
;;
;; WHAT THIS FILE IS
;;
;; The 256-byte slot ROM of the emulator's 3.5-inch disk controller, a card that answers as Apple's Apple II 3.5 Disk
;; Controller Card does: a SmartPort with two drives that take 400K and 800K Apple disks and 720K and 1440K MFM disks.
;; It is the SDK's own firmware, not a copy of Apple's: Apple's card has its own 65C02 that runs the drives and talks
;; to the Apple II through shared RAM (Disk35/Disk35Controller.asm is its EPROM, for comparison). Here
;; Apple2Disk35Card does the card's work in C#, and this ROM only carries each call across to it. Its names are the
;; SDK's; where Apple's card has the same entry, the two sources give it the same name.
;;
;; HOW PROGRAMS FIND AND CALL IT
;;
;; As on Apple's card: $Cn01 = $20, $Cn03 = $00, $Cn05 = $03 and $Cn07 = $00 mark a SmartPort; $CnFB = $C0,
;; $CnFC-$CnFD = 0 (ask STATUS for the size), $CnFE = $BF (removable, not interruptible, four volumes, format, write,
;; read, status) and $CnFF = $1C put the ProDOS entry at $Cn1C and the SmartPort entry at $Cn1F. $Cn00 boots the
;; first drive. Apple's card starts its diagnostics from $Cn0D; this one has none, so $Cn0D returns.
;;
;; HOW A CALL CROSSES INTO C#
;;
;; Each entry goes to <Call> with carry set for SmartPort and overflow set to boot. <Call> keeps the caller's status on
;; the stack, finds the slot with an RTS it writes at $06 for a moment, as Apple's mouse firmware does, and writes the
;; stack pointer to the card's command port at $C080 plus 16 times the slot. That write runs the call in C#, which reads
;; the caller's status and return address from the stack, the command and parameter list after a SmartPort JSR, and
;; moves the return address past them. <Call> reads back A, X and Y, gives the caller back its interrupt flag, and
;; returns with carry set when A is not 0.
;;
;; A boot reads block 0 of the first drive into $0800 and sets up ProDOS's page zero ($42-$47) as for that read; a
;; block that starts with $01 and a nonzero byte runs at $0801 with X = the slot times 16. Otherwise the boot goes on to
;; the next slot when the Monitor's scan brought it here, or says UNABLE TO BOOT and starts BASIC, as Apple's card
;; does.
;;
;; The ROM uses no absolute address inside itself, only branches, so the same bytes work in any slot. It is assembled
;; at $C500, the slot people often gave the card.

.rom Retrocore.Machines.Apple2.Disk35Rom, $C500, $100
.cpu Mos6502
.export ProDosEntry, SmartPortEntry, DiagnosticsEntry, Signature

; The Monitor's and the IIe's names this ROM uses. The source generator assembles this file alone, so it defines
; them here rather than including IIeEquates.asm and MonitorEntries.asm.

;; Inherit: <Monitor:SlotPointer>
;; Also: LOC0 (A2RM78, A2RM79, IIEROM82, IIETRM85)
SlotPointer = $00

;; Inherit: <Monitor:LOC1>
LOC1 = $01

;; Inherit: <Monitor:LanguageCardRomOnly>
;; Also: LCROM (UNKN)
LanguageCardRomOnly = $C082

;; Inherit: <Monitor:BasicColdStart>
;; Also: BASIC (A2RM78, A2RM79, IIEROM82, IIETRM85)
BasicColdStart = $E000

;; Inherit: <Monitor:Startup::PowerUp::NextSlot>
;; Also: SLOOP (A2RM79, IIEROM82, IIETRM85)
NextSlot = $FABA

;; Inherit: <Monitor:SetText>
;; Also: SETTXT (A2RM78, A2RM79, IIEROM82, IIETRM85)
SetText = $FB39

;; Inherit: <Monitor:Home>
;; Also: HOME (A2RM78, A2RM79, IIEROM82, IIETRM85)
Home = $FC58

;; Inherit: <Monitor:SetKeyboard>
;; Also: SETKBD (A2RM78, A2RM79, IIEROM82, IIETRM85)
SetKeyboard = $FE89

;; Inherit: <Monitor:SetScreen>
;; Also: SETVID (A2RM78, A2RM79, IIEROM82, IIETRM85)
SetScreen = $FE93

; Memory.

;; Where <Call> puts an RTS for a moment, to find its own page.
ZeroPageRts = $06

;; The 6502's stack.
StackPage = $0100

;; Where a ProDOS boot block starts running, one byte into the block read at $0800.
BootBlock = $0801

; The card's ports, at $C080 + $n0. Reading any of them changes nothing but <MessagePort>.

;; Write: the stack pointer, which runs the call in C#. Read: the A to return.
CallPort = $C080

;; Read: the X to return.
ReturnXPort = $C081

;; Read: the Y to return.
ReturnYPort = $C082

;; Read: writes UNABLE TO BOOT on the screen.
MessagePort = $C083

; Values.

;; The RTS opcode, which <Call> writes at <ZeroPageRts>.
OPCODE_RTS = $60

;; Boots the first drive. The four loads are the SmartPort identification at $Cn01-$Cn07; overflow, set by the
;; addition, makes the call a boot.
.proc Boot
    ldx #$20
    ldx #$00
    ldy #$03
    lda #$00
    sec
    adc #$7F
    bvs Call                        ; always
.endproc

;; Apple's card's diagnostics entry, $Cn0D: this card has none, so it returns.
.proc DiagnosticsEntry
.assert * = $C50D, "DiagnosticsEntry must stay at $Cn0D."
    rts
.endproc

    .res $C51C - *

;; The ProDOS block-device entry, $Cn1C.
;; In: $42 = the command (0 status, 1 read, 2 write, 3 format), $43 = the unit, $44/$45 = the buffer, $46/$47 = the
;;   block
;; Out: A = 0 or the error, carry = set on an error, X and Y = the block count after a status call
;; Keeps: interrupt
.proc ProDosEntry
.assert * = $C51C, "ProDosEntry must stay at $Cn1C."
    clc
    bcc SmartPortEntry::Plain       ; always
.endproc

;; The SmartPort entry, $Cn1F: JSR $Cn1F, then the command and the parameter list's address (four bytes for an
;; extended command), which the call steps over.
;; Out: A = 0 or the error, carry = set on an error, X and Y = the bytes moved
;; Keeps: interrupt
;; Entry:
;;   Plain = a ProDOS call, with carry clear
.proc SmartPortEntry
.assert * = $C51F, "SmartPortEntry must stay at $Cn1F."
    sec
Plain:
    clv
    ; Falls into Call.
.endproc

;; Carries a call to the card and returns what it gives back. A boot that succeeds runs the boot block instead.
;; In: carry = set for SmartPort, overflow = set to boot
;; Out: A, X and Y = as the card returns them, carry = set when A is not 0, zero and negative = from A
;; Keeps: interrupt
.proc Call
    php                             ; the caller's interrupt flag, and how it came
    sei

    ; An RTS at ZeroPageRts leaves its return address's high byte, $Cn, just below the stack.
    ldy ZeroPageRts
    lda #OPCODE_RTS
    sta ZeroPageRts
    jsr ZeroPageRts
    sty ZeroPageRts
    tsx
    lda StackPage,x
    asl a
    asl a
    asl a
    asl a
    tay                             ; $n0, the slot's port offset

    ; The write runs the call; then A, X and Y come back.
    txa
    sta CallPort,y
    lda ReturnXPort,y
    tax
    lda CallPort,y
    pha
    lda ReturnYPort,y
    tay
    pla
    plp
    bvs Booting
    cmp #1                          ; carry = an error
    ora #0
    rts

    ; A boot: 0 runs the block, with X = $n0.
Booting:
    ora #0
    bne NoBoot
    jmp BootBlock

    ; No boot: on to the next slot when the Monitor's scan came here, else UNABLE TO BOOT and BASIC.
NoBoot:
    bit LanguageCardRomOnly
    lda SlotPointer
    bne Unable
    cpy LOC1                        ; Y = $Cn
    bne Unable
    jmp NextSlot
Unable:
    txa
    pha
    jsr SetScreen
    jsr SetKeyboard
    jsr SetText
    jsr Home
    pla
    tay
    lda MessagePort,y
    jmp BasicColdStart
.endproc

.assert * <= $C5FB, "The code must end before the signature at $CnFB."
.org $C5FB

;; The SmartPort's identification after the entry points, as Apple's card gives it.
Signature:
    .byte $C0                       ; $CnFB: extended SmartPort calls
    .word 0                         ; $CnFC: ask STATUS for the block count
    .byte $BF                       ; $CnFE: removable, not interruptible, four volumes, format, write, read, status
    .byte <ProDosEntry              ; $CnFF: the ProDOS entry
.assert * = $C600, "The ROM must fill its page."
