; Copyright (c) 2025 Jeremy W Kuhne
; SPDX-License-Identifier: MIT
; See LICENSE file in the project root for full license information
;
; EMULATED MOUSE CARD FIRMWARE
;
; WHAT THIS FILE IS
;
; The 256-byte slot ROM of the emulator's mouse card. It answers the calls that
; Apple's AppleMouse II documentation gives programs, at the places it gives them,
; so programs written for that card find and drive this one. It is our own
; firmware, not a copy of Apple's: the card's work (tracking the pointer, clamping
; it, raising interrupts, formatting BASIC's input line) is done in C# by
; Apple2MouseCard, and this ROM only carries each call across to it. Apple's own
; firmware is in Mouse/MouseInterface.asm, for comparison; docs/Apple2.md lists
; where the two differ.
;
; HOW PROGRAMS FIND AND CALL IT
;
; A program looks for the card's identification bytes: $38 at $Cn05, $18 at $Cn07,
; $01 at $Cn0B and $20 (an X-Y pointing device, the mouse) at $Cn0C, and $D6 at
; $CnFB. The byte at $Cn12 to $Cn19 is each mouse routine's offset in the page:
; SETMOUSE, SERVEMOUSE, READMOUSE, CLEARMOUSE, POSMOUSE, CLAMPMOUSE, HOMEMOUSE
; and INITMOUSE. The program calls $Cn00 plus the offset with X = $Cn and Y = $n0,
; and the routine returns carry clear, or carry set for an error (or, from
; SERVEMOUSE, when the interrupt was not the mouse's).
;
; The routines share the text screen's holes in slot n's column:
;   $0478+n/$0578+n  X position low/high    $04F8+n/$05F8+n  Y position low/high
;   $0778+n          status: bit 7 button down, 6 down at the last read, 5 moved
;                    since the last read, 3/2/1 interrupt from VBL/button/movement
;   $07F8+n          mode: bit 0 on, 1/2/3 interrupt on movement/button/VBL,
;                    7 set by BASIC
; CLAMPMOUSE takes its bounds from slot 0's column: the minimum in $0478/$0578 and
; the maximum in $04F8/$05F8.
;
; BASIC reads the card after IN#n: the card writes the line "X,Y,B" into the input
; buffer and returns a RETURN, so INPUT takes three numbers and nothing is echoed. It
; turns the mouse on or off after PR#n as the low bit of each character printed
; says, as CHR$(1) and CHR$(0) do. As on Apple's card, the Pascal 1.1 entries at
; $Cn0D-$Cn10 answer error 3, and the factory's own entries at $Cn1A-$Cn1F do nothing.
;
; HOW A CALL CROSSES INTO C#
;
; Each entry pushes A and goes to Common with its command number, whose upper bits
; say how to find the slot, as Apple's firmware does: the mouse routines from X =
; $Cn, as their callers must give it; SERVEMOUSE from an RTS it writes at $06, since
; an interrupt handler may run with the language card's RAM over the Monitor; and
; BASIC's entries from the Monitor's IORTS. Common saves P, X and Y, then writes the
; caller's A and X to the card's ports and the command to its command port, at $C080
; plus 16 times the slot; that write runs the command in C#, which reads and writes
; the screen holes and RAM as Apple's firmware would. Common reads back the A, X and
; carry the command returns and gives the caller back its Y and interrupt flag.
;
; Ports (offsets from $C080 + $n0); reading any of them changes nothing:
;   +0  write: the command, which runs at once; read: the carry it returns (0 or 1)
;   +1  write: the caller's A; read: the A to return
;   +2  write: the caller's X; read: the X to return
;
; The ROM uses no absolute address inside itself, only branches, so the same bytes
; work in any slot. It is assembled at $C400, a slot people often give a mouse.

.rom Retrocore.Machines.Apple2.MouseRom, $C400, $100
.cpu Mos6502
.export SETMOUSE, SERVEMOUSE, READMOUSE, CLEARMOUSE, POSMOUSE, CLAMPMOUSE, HOMEMOUSE, INITMOUSE, Signature

IORTS = $FF58                       ; an RTS in every Apple II Monitor
ZeroPageRts = $06                   ; where SERVEMOUSE puts an RTS for a moment, as Apple's does
StackPage = $0100
CommandPort = $C080
ValuePort = $C081
XPort = $C082

; How Common finds the slot, in the command's upper bits; Apple2MouseCard masks them off.
FromZeroPage = $80
FromMonitor = $40

; The commands, as Apple2MouseCard numbers them.
SetMouseCommand = 1
ServeMouseCommand = 2 | FromZeroPage
ReadMouseCommand = 3
ClearMouseCommand = 4
PosMouseCommand = 5
ClampMouseCommand = 6
HomeMouseCommand = 7
InitMouseCommand = 8
BasicCommand = 9 | FromMonitor
BasicInputCommand = 10 | FromMonitor
BasicOutputCommand = 11 | FromMonitor

; An entry: keeps the caller's A on the stack and goes to Common with the command.
.macro Entry command
    pha
    lda #command
    bne Common
.endmacro

;; BASIC's entry, where PR#n or IN#n points the output or input hook: the card tells which hook brought it here,
;; moves that hook to $Cn05 or $Cn07, and reads or writes as that entry does.
;; In:    A = the character to print, or the character under the cursor for input
;; Out:   A = the character printed, or RETURN for input, with the line in the input buffer and X = its length
;; Keeps: Y
BASIC:
    Entry BasicCommand
.assert * == $C405

;; BASIC's input entry ($Cn05, the SEC programs look for): writes "X,Y,B" into the input buffer.
;;
;; The branch's offset, $18, is also a CLC: BASIC's output entry at $Cn07, which then takes the BCC below and turns
;; the mouse on or off, keeping A, X and Y.
;; In:    A = the character under the cursor
;; Out:   A = RETURN, X = the line's length, $11
;; Keeps: Y
BASICIN_ENTRY:
    sec
    bcs BASICIN                     ; the offset is $18: the CLC at $Cn07
.assert BASICIN == $C420
    bcc BASICOUT                    ; from $Cn07's CLC
    .byte 0

; The Pascal 1.1 identification and the routines' offsets.
.assert * == $C40B
    .byte $01                       ; $Cn0B: a firmware card with the generic signature
    .byte $20                       ; $Cn0C: an X-Y pointing device: the mouse
    .byte <PASCAL, <PASCAL, <PASCAL, <PASCAL ; INIT, READ, WRITE and STATUS: no Pascal driver, as on Apple's card
    .byte $00                       ; $Cn11: the mouse's own entries follow
.assert * == $C412
    .byte <SETMOUSE, <SERVEMOUSE, <READMOUSE, <CLEARMOUSE
    .byte <POSMOUSE, <CLAMPMOUSE, <HOMEMOUSE, <INITMOUSE
    .byte <NOTHING, <NOTHING, <NOTHING, <NOTHING, <NOTHING, <NOTHING ; $Cn1A-$Cn1F: Apple's factory entries

.assert * == $C420
;; Writes BASIC's line from the card.
BASICIN:
    Entry BasicInputCommand

;; Writes a BASIC character to the card.
BASICOUT:
    Entry BasicOutputCommand

;; Sets the mouse's mode: bit 0 on, bits 1, 2 and 3 interrupt on movement, the button and vertical blanking.
;; In:    A = the mode, X = $Cn, Y = $n0
;; Out:   carry = set if the mode is above $0F
SETMOUSE:
    Entry SetMouseCommand

;; Called from an interrupt handler: tells whether the mouse interrupted, and why, in the status hole's bits 1-3.
;; Out:   carry = clear if the interrupt was the mouse's
SERVEMOUSE:
    Entry ServeMouseCommand

;; Copies the position, button and movement into the screen holes and clears the interrupt bits, if the mouse is on.
;; In:    X = $Cn, Y = $n0
;; Out:   carry = clear
READMOUSE:
    Entry ReadMouseCommand

;; Sets the position to 0, 0, and the holes with it.
;; In:    X = $Cn, Y = $n0
;; Out:   carry = clear
CLEARMOUSE:
    Entry ClearMouseCommand

;; Sets the position from the screen holes.
;; In:    X = $Cn, Y = $n0
;; Out:   carry = clear
POSMOUSE:
    Entry PosMouseCommand

;; Sets the bounds of one axis from slot 0's holes and keeps the position within them.
;; In:    A = 0 for X, 1 for Y, X = $Cn, Y = $n0
;; Out:   carry = clear
CLAMPMOUSE:
    Entry ClampMouseCommand

;; Moves the position to the bounds' minimums, the upper left.
;; In:    X = $Cn, Y = $n0
;; Out:   carry = clear
HOMEMOUSE:
    Entry HomeMouseCommand

;; Turns the mouse off and resets its position to 0, 0 and its bounds to 0-1023.
;; In:    X = $Cn, Y = $n0
;; Out:   carry = clear
INITMOUSE:
    Entry InitMouseCommand

;; Pascal's INIT, READ, WRITE and STATUS: the card has no Pascal driver.
;; Out:   X = 3, carry = set
PASCAL:
    ldx #3
;; The factory's entries at $Cn1A-$Cn1F, which this card does not have.
;; Out:   carry = set
NOTHING:
    sec
    rts

;; Carries a call to the card: finds the slot, passes A and X, runs the command and returns what it gives back.
;; In:    A = the command; the stack holds the caller's A
;; Out:   A, X and carry = as the command returns them
;; Keeps: Y, interrupt
Common:
    php                             ; the caller's interrupt flag, and the carry slot for the result
    sei                             ; nothing may push over the return address read below
    pha                             ; the command
    txa
    pha
    tya
    pha                             ; the stack: A, P, command, X, Y
    tsx
    lda StackPage+3,x
    bmi Common_ZeroPage
    asl a
    bmi Common_Monitor
    lda StackPage+2,x               ; the caller's X, $Cn
    bne Common_Slot                 ; always
Common_ZeroPage:
    ldy ZeroPageRts
    lda #$60                        ; RTS
    sta ZeroPageRts
    jsr ZeroPageRts                 ; leaves its return address's high byte, $Cn, just below the stack
    sty ZeroPageRts
    tsx
    lda StackPage,x
    bne Common_Slot                 ; always
Common_Monitor:
    jsr IORTS                       ; the same, through the Monitor
    tsx
    lda StackPage,x
Common_Slot:
    asl a
    asl a
    asl a
    asl a
    tay                             ; $n0, the slot's port offset
    lda StackPage+5,x
    sta ValuePort,y                 ; the caller's A
    lda StackPage+2,x
    sta XPort,y                     ; the caller's X
    lda StackPage+3,x
    sta CommandPort,y               ; runs the command
    lda ValuePort,y
    sta StackPage+5,x               ; the A to return
    lda XPort,y
    sta StackPage+2,x               ; the X to return
    lda StackPage+4,x
    and #$FE
    ora CommandPort,y
    sta StackPage+4,x               ; the carry to return, with the caller's other flags
    pla
    tay
    pla
    tax
    pla                             ; the command
    plp
    pla
    rts

.assert * <= $C4FB
.org $C4FB
;; The byte at $CnFB that mouse programs check, after the Pascal bytes, to know the card is a mouse.
Signature:
    .byte $D6
    .byte $FF, $FF, $FF, $01        ; as on Apple's card
.assert * == $C500
