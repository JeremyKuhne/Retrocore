; retrocore: style=strict
; Copyright (c) 2025 Jeremy W Kuhne
; SPDX-License-Identifier: MIT
; See LICENSE file in the project root for full license information

;; EMULATED MOUSE CARD FIRMWARE
;;
;; WHAT THIS FILE IS
;;
;; The 256-byte slot ROM of the emulator's mouse card. It answers the calls that Apple's AppleMouse II
;; documentation gives programs, at the places it gives them, so programs written for that card find and drive this
;; one. It is the SDK's own firmware, not a copy of Apple's: the card's work (tracking the pointer, clamping it,
;; raising interrupts, formatting BASIC's input line) is done in C# by Apple2MouseCard, and this ROM only carries
;; each call across to it. Apple's own firmware is in Mouse/MouseInterface.asm, for comparison; docs/Apple2.md lists
;; where the two differ. Apple2MouseTests pins its bytes by digest.
;;
;; HOW PROGRAMS FIND AND CALL IT
;;
;; A program looks for the card's identification bytes: $38 at $Cn05, $18 at $Cn07, $01 at $Cn0B and $20 (an X-Y
;; pointing device, the mouse) at $Cn0C, and $D6 at $CnFB. The byte at $Cn12 to $Cn19 is each mouse routine's offset
;; in the page: <SetMouse>, <ServeMouse>, <ReadMouse>, <ClearMouse>, <PositionMouse>, <ClampMouse>, <HomeMouse> and
;; <InitializeMouse>. The program calls $Cn00 plus the offset with X = $Cn and Y = $n0, and the routine returns carry
;; clear, or carry set for an error (or, from <ServeMouse>, when the interrupt was not the mouse's).
;;
;; The routines share the text screen's holes in slot n's column:
;;   $0478+n/$0578+n  X position low/high    $04F8+n/$05F8+n  Y position low/high
;;   $0778+n          status: bit 7 button down, 6 down at the last read, 5 moved
;;                    since the last read, 3/2/1 interrupt from VBL/button/movement
;;   $07F8+n          mode: bit 0 on, 1/2/3 interrupt on movement/button/VBL,
;;                    7 set by BASIC
;; <ClampMouse> takes its bounds from slot 0's column: the minimum in $0478/$0578 and the maximum in $04F8/$05F8.
;;
;; BASIC reads the card after `IN#n`: the card writes the line "X,Y,B" into the input buffer and returns a RETURN, so
;; INPUT takes three numbers and nothing is echoed. It turns the mouse on or off after `PR#n` as the low bit of each
;; character printed says, as CHR$(1) and CHR$(0) do. As on Apple's card, the Pascal 1.1 entries at $Cn0D-$Cn10
;; answer error 3. Of the entries at $Cn1A-$Cn1F, Apple documents two of its card's, reading a clamping bound's byte
;; ($Cn1A) and setting the interrupt rate ($Cn1C); this card has neither, and every one returns carry set
;; (<FactoryEntry>).
;;
;; HOW A CALL CROSSES INTO C#
;;
;; Each entry pushes A and goes to <CallCard> with its command number, whose upper bits say how to find the slot, as
;; Apple's firmware does: the mouse routines from X = $Cn, as their callers must give it; <ServeMouse> from an RTS it
;; writes at $06, since an interrupt handler may run with the language card's RAM over the Monitor; and BASIC's
;; entries from the Monitor's <SaveRegisters::Return>. <CallCard> saves P, X and Y, then writes the caller's A and X
;; to the card's ports and the command to its command port, at $C080 plus 16 times the slot; that write runs the
;; command in C#, which reads and writes the screen holes and RAM as Apple's firmware would. <CallCard> reads back the
;; A, X and carry the command returns and gives the caller back its Y and interrupt flag.
;;
;; Ports (offsets from $C080 + $n0); reading any of them changes nothing:
;;   +0  write: the command, which runs at once; read: the carry it returns (0 or 1)
;;   +1  write: the caller's A; read: the A to return
;;   +2  write: the caller's X; read: the X to return
;;
;; The ROM uses no absolute address inside itself, only branches, so the same bytes work in any slot. It is
;; assembled at $C400, a slot people often give a mouse.
;;
;; NAMES
;;
;; The mouse routines' old names are the calls Apple's documents give programs: its Mouse Technical Notes (MOUSETN)
;; and the IIc Technical Reference's second edition (IICTRM89), which documents the calls for the AppleMouse card as
;; well as the IIc. Every other name is the SDK's own.

.rom Retrocore.Machines.Apple2.MouseRom, $C400, $100
.cpu Mos6502
.export SetMouse, ServeMouse, ReadMouse, ClearMouse, PositionMouse, ClampMouse, HomeMouse, InitializeMouse, Signature

;; The label inside the Monitor's <Monitor:SaveRegisters> that this firmware calls.
.scope SaveRegisters

;; Inherit: <Monitor:SaveRegisters::Return>
;; At $FF58, an RTS in every Apple II Monitor. BASIC's entries call it to find the slot.
;; Also: IORTS (IIEROM82)
Return = $FF58

.endscope

;; Where <ServeMouse> puts an RTS for a moment, as Apple's firmware does.
ZeroPageRts = $06

;; The 6502's stack page: <CallCard> finds the bytes it pushed at `Stack+1,x` and up after a TSX.
Stack = $0100

; The card's ports, indexed by Y = $n0.

;; Write: the command, which runs at once in C#; read: the carry it returns, 0 or 1.
CommandPort = $C080

;; Write: the caller's A; read: the A to return.
ValuePort = $C081

;; Write: the caller's X; read: the X to return.
XPort = $C082

; The bytes the firmware is found by.

;; The opcode of CLC, which programs look for at $Cn07: <BasicInput>'s branch offset.
OPCODE_CLC = $18

;; The opcode of RTS, which <ServeMouse> writes at <ZeroPageRts>.
OPCODE_RTS = $60

;; $Cn0B: a firmware card with the generic Pascal 1.1 signature.
PASCAL_GENERIC = $01

;; $Cn0C: the card's device class: an X-Y pointing device, the mouse.
DEVICE_MOUSE = $20

;; $CnFB: the byte mouse programs check, after the Pascal bytes, to know the card is a mouse.
MOUSE_ID = $D6

;; The error the Pascal entries answer, in X.
PASCAL_ERROR = 3

; How CallCard finds the slot, in the command's upper bits; Apple2MouseCard masks them off.

;; Bit 7: from the return address of an RTS written at <ZeroPageRts>.
FIND_SLOT_FROM_ZERO_PAGE = $80

;; Bit 6: from the return address of the Monitor's <SaveRegisters::Return>.
FIND_SLOT_FROM_MONITOR = $40

;; The carry bit of the status register.
CARRY = $01

; The commands, as Apple2MouseCard numbers them.

;; <SetMouse>'s.
COMMAND_SET_MOUSE = 1

;; <ServeMouse>'s.
COMMAND_SERVE_MOUSE = 2 | FIND_SLOT_FROM_ZERO_PAGE

;; <ReadMouse>'s.
COMMAND_READ_MOUSE = 3

;; <ClearMouse>'s.
COMMAND_CLEAR_MOUSE = 4

;; <PositionMouse>'s.
COMMAND_POSITION_MOUSE = 5

;; <ClampMouse>'s.
COMMAND_CLAMP_MOUSE = 6

;; <HomeMouse>'s.
COMMAND_HOME_MOUSE = 7

;; <InitializeMouse>'s.
COMMAND_INITIALIZE_MOUSE = 8

;; <BasicEntry>'s: the card works out which hook brought it.
COMMAND_BASIC = 9 | FIND_SLOT_FROM_MONITOR

;; <WriteBasicLine>'s.
COMMAND_BASIC_INPUT = 10 | FIND_SLOT_FROM_MONITOR

;; <WriteBasicCharacter>'s.
COMMAND_BASIC_OUTPUT = 11 | FIND_SLOT_FROM_MONITOR

;; An entry: keeps the caller's A on the stack and goes to <CallCard> with the command.
;; Parameters:
;;   command = the command, a COMMAND_* value, which is never 0
.macro EnterCommand command
    pha
    lda #command
    bne CallCard
.endmacro

;; BASIC's entry, where `PR#n` or `IN#n` points the output or input hook: the card tells which hook brought it here,
;; moves that hook to $Cn05 or $Cn07, and reads or writes as that entry does.
;; In:    A = the character to print, or the character under the cursor for input
;; Out:   A = the character printed, or RETURN for input, with the line in the input buffer and X = its length
;; Keeps: Y
.proc BasicEntry
    EnterCommand COMMAND_BASIC
.endproc

;; BASIC's input entry ($Cn05, the SEC programs look for): writes "X,Y,B" into the input buffer.
;;
;; The branch's offset, $18, is also a CLC: <BasicOutput>, at $Cn07, which then takes the BCC below and turns the
;; mouse on or off, keeping A, X and Y.
;; In:    A = the character under the cursor
;; Out:   A = RETURN, X = the line's length, $11
;; Keeps: Y
.proc BasicInput
.assert * = $C405, "BasicInput must stay at $Cn05."
    sec
    bcs WriteBasicLine              ; the offset is $18: BasicOutput's CLC
.assert WriteBasicLine - * = OPCODE_CLC, "BasicInput's branch offset must be the CLC at $Cn07."

    ; From BasicOutput's CLC.
    bcc WriteBasicCharacter
.endproc

;; BASIC's output entry ($Cn07, the CLC programs look for): <BasicInput>'s branch offset, which clears carry and
;; goes on to the BCC after it, to <WriteBasicCharacter>.
;; In:    A = the character to print
;; Out:   A = the character printed
;; Keeps: X, Y
BasicOutput = BasicInput + 2

    .byte 0                         ; unused

; The Pascal 1.1 identification and the routines' offsets.
.assert * = $C40B, "The identification must start at $Cn0B."
    .byte PASCAL_GENERIC
    .byte DEVICE_MOUSE
    .byte <PascalEntry, <PascalEntry, <PascalEntry, <PascalEntry ; INIT, READ, WRITE and STATUS: no Pascal driver
    .byte $00                       ; $Cn11: the mouse's own entries follow
.assert * = $C412, "The mouse routines' offsets must start at $Cn12."
    .byte <SetMouse, <ServeMouse, <ReadMouse, <ClearMouse
    .byte <PositionMouse, <ClampMouse, <HomeMouse, <InitializeMouse
    .byte <FactoryEntry, <FactoryEntry, <FactoryEntry, <FactoryEntry, <FactoryEntry, <FactoryEntry ; $Cn1A-$Cn1F

;; Writes BASIC's line from the card, for <BasicInput>.
;; In:    A = the character under the cursor
;; Out:   A = RETURN, X = the line's length, $11
;; Keeps: Y
.proc WriteBasicLine
.assert * = $C420, "WriteBasicLine must stay where BasicInput's branch offset points."
    EnterCommand COMMAND_BASIC_INPUT
.endproc

;; Writes a BASIC character to the card, for <BasicOutput>: turns the mouse on or off as its low bit says.
;; In:    A = the character
;; Out:   A = the character
;; Keeps: X, Y
.proc WriteBasicCharacter
    EnterCommand COMMAND_BASIC_OUTPUT
.endproc

;; Sets the mouse's mode: bit 0 on, bits 1, 2 and 3 interrupt on movement, the button and vertical blanking.
;; In:    A = the mode, X = $Cn, Y = $n0
;; Out:   carry = set if the mode is above $0F
;; Keeps: Y
;; Also: SETMOUSE (MOUSETN, IICTRM89)
.proc SetMouse
    EnterCommand COMMAND_SET_MOUSE
.endproc

;; Called from an interrupt handler: tells whether the mouse interrupted, and why, in the status hole's bits 1-3.
;; Out:   carry = clear if the interrupt was the mouse's
;; Keeps: Y
;; Also: SERVEMOUSE (MOUSETN, IICTRM89)
.proc ServeMouse
    EnterCommand COMMAND_SERVE_MOUSE
.endproc

;; Copies the position, button and movement into the screen holes, if the mouse is on, clearing the status hole's
;; interrupt bits; a pending interrupt stays pending until <ServeMouse>.
;; In:    X = $Cn, Y = $n0
;; Out:   carry = clear
;; Keeps: Y
;; Also: READMOUSE (MOUSETN, IICTRM89)
.proc ReadMouse
    EnterCommand COMMAND_READ_MOUSE
.endproc

;; Sets the position to 0, 0, and the holes with it.
;; In:    X = $Cn, Y = $n0
;; Out:   carry = clear
;; Keeps: Y
;; Also: CLEARMOUSE (MOUSETN, IICTRM89)
.proc ClearMouse
    EnterCommand COMMAND_CLEAR_MOUSE
.endproc

;; Sets the position from the screen holes.
;; In:    X = $Cn, Y = $n0
;; Out:   carry = clear
;; Keeps: Y
;; Also: POSMOUSE (MOUSETN, IICTRM89)
.proc PositionMouse
    EnterCommand COMMAND_POSITION_MOUSE
.endproc

;; Sets the bounds of one axis from slot 0's holes and keeps the position within them.
;; In:    A = 0 for X, 1 for Y, X = $Cn, Y = $n0
;; Out:   carry = clear
;; Keeps: Y
;; Also: CLAMPMOUSE (MOUSETN, IICTRM89)
.proc ClampMouse
    EnterCommand COMMAND_CLAMP_MOUSE
.endproc

;; Moves the position to the bounds' minimums, the upper left.
;; In:    X = $Cn, Y = $n0
;; Out:   carry = clear
;; Keeps: Y
;; Also: HOMEMOUSE (IICTRM89)
.proc HomeMouse
    EnterCommand COMMAND_HOME_MOUSE
.endproc

;; Turns the mouse off and resets its position to 0, 0 and its bounds to 0-1023.
;; In:    X = $Cn, Y = $n0
;; Out:   carry = clear
;; Keeps: Y
;; Also: INITMOUSE (MOUSETN, IICTRM89)
.proc InitializeMouse
    EnterCommand COMMAND_INITIALIZE_MOUSE
.endproc

;; Pascal's INIT, READ, WRITE and STATUS: the card has no Pascal driver.
;; Out:   X = 3, carry = set
.proc PascalEntry
    ldx #PASCAL_ERROR
    ; Falls into FactoryEntry.
.endproc

;; The entries at $Cn1A-$Cn1F, which this card does not have.
;;
;; On Apple's card every one of them returns carry clear: TimeData at $Cn1C, as Mouse Technical Note #2 documents,
;; and GetClamp at $Cn1A and the factory's own, as the card's EPROM does. On this card all six return carry set.
;; Out:   carry = set
;; Keeps: X, Y
.proc FactoryEntry
    sec
    rts
.endproc

;; Carries a call to the card: finds the slot, passes A and X, runs the command and returns what it gives back.
;; In:    A = the command; the stack holds the caller's A
;; Out:   A/X = as the command returns them, carry = as the command returns it
;; Keeps: Y, interrupt
.proc CallCard
    php                             ; the caller's interrupt flag, and the carry slot for the result
    sei                             ; nothing may push over the return address read below
    pha                             ; the command
    txa
    pha
    tya
    pha                             ; the stack: A, P, command, X, Y

    ; The slot's page, $Cn, as the command's upper bits say: from the caller's X, ...
    tsx
    lda Stack + 3,x
    bmi FromZeroPage
    asl a
    bmi FromMonitor
    lda Stack + 2,x                 ; the caller's X, $Cn
    bne HaveSlot                    ; always: X = $Cn is never 0

    ; ... from an RTS at ZeroPageRts, whose JSR leaves its return address's high byte just below the stack, ...
FromZeroPage:
    ldy ZeroPageRts
    lda #OPCODE_RTS
    sta ZeroPageRts
    jsr ZeroPageRts
    sty ZeroPageRts
    tsx
    lda Stack,x
    bne HaveSlot                    ; always

    ; ... or the same, through the Monitor.
FromMonitor:
    jsr SaveRegisters::Return
    tsx
    lda Stack,x

    ; The ports, at $C080 + $n0.
HaveSlot:
    asl a
    asl a
    asl a
    asl a
    tay
    lda Stack + 5,x
    sta ValuePort,y                 ; the caller's A
    lda Stack + 2,x
    sta XPort,y                     ; the caller's X
    lda Stack + 3,x
    sta CommandPort,y               ; runs the command

    ; What the command returns, in place of what the caller gave.
    lda ValuePort,y
    sta Stack + 5,x                 ; the A to return
    lda XPort,y
    sta Stack + 2,x                 ; the X to return
    lda Stack + 4,x
    and #<~CARRY
    ora CommandPort,y
    sta Stack + 4,x                 ; the carry to return, with the caller's other flags
    pla
    tay
    pla
    tax
    pla                             ; the command
    plp
    pla
    rts
.endproc

.assert * <= $C4FB, "The firmware must end before the identification byte at $CnFB."
.org $C4FB

;; The byte at $CnFB that mouse programs check, after the Pascal bytes, to know the card is a mouse.
Signature:
    .byte MOUSE_ID
    .byte $FF, $FF, $FF, $01        ; as on Apple's card
.assert * = $C500, "The firmware must fill its page."
