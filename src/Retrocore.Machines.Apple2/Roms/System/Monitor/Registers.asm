; retrocore: style=strict
;; The register display and the game paddle ($FAD7-$FB2E), with the data between them: the Apple II Monitor's
;; third piece of <Stepper>, or in the other Monitors the power-up data of <Startup> and the first piece of
;; <Escape>.

; The registers the Monitor saves and shows.

;; The registers <ShowRegisters> shows and <RegisterNames> names: A, X, Y, P and S, saved at <A5H>..<SPNT>.
REGISTER_COUNT = 5

;; Prints a carriage return, then the registers saved by <SaveRegisters> as "A=xx X=xx Y=xx P=xx S=xx".
;;
;; At $FAD7. In the Apple II Monitor, <Stepper::Finish> falls into it at the end of a step.
;; In: A5H..SPNT = the registers
;; Out: X = 0
;; Uses: A, A3L/A3H
;; Entry:
;;   NoReturn = prints the registers without the carriage return first, at $FADA; <ShowBreak> calls it
;; Also: REGDSP (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc ShowRegisters
.assert * = $FAD7, "ShowRegisters must stay at $FAD7."
    jsr PrintReturn

;; Prints the registers without the carriage return first; <ShowBreak> calls it.
;; Also: RGDSP1 (A2RM78, A2RM79, IIEROM82, IIETRM85)
NoReturn:
.assert * = $FADA, "ShowRegisters::NoReturn must stay at $FADA."
    lda #<A5H
    sta A3L
    lda #>A5H
    sta A3H

    ; X runs from -5 to -1 over the five registers.
    ldx #$100 - REGISTER_COUNT

;; Prints " r=xx" for one register; in page zero the saved byte's address wraps round to <A5H>, <XREG>,
;; <YREG>, <STATUS> and <SPNT>.
;; Also: RDSP1 (A2RM78, A2RM79, IIEROM82, IIETRM85)
Next:
    lda #' '
    jsr CharacterOut
    lda RegisterNames - ($100 - REGISTER_COUNT),x
    jsr CharacterOut
    lda #'='
    jsr CharacterOut
    lda A5H + REGISTER_COUNT,x
    jsr PrintHexByte
    inx
    bmi Next
    rts
.endproc
.if MONITOR = MONITOR_II

; Stepper: the ends of a stepped instruction, and the trailer copied after it.
.scope Stepper continued

;; The end of a taken branch run by <Stepper::RunInstruction>: moves <PCL>/<PCH> to the branch's target.
;;
;; The copied branch lands on the trailer's jump to here in <Stepper::RunArea> when it is taken. The target is the
;; branch's address plus the real displacement plus 2, the branch's length.
;; Also: BRANCH (A2RM78, A2RM79)
.proc TakenBranch
    ; PC plus the displacement.
    clc
    ldy #1
    lda (PCL),y
    jsr NextInstruction::AddA
    sta PCL
    tya

    ; Then plus LENGTH + 1 in SetPcHigh.
    sec
    bcs SimulateRts::SetPcHigh
.endproc

;; The end of an instruction run by <Stepper::RunInstruction> that did not branch: saves the registers and moves
;; <PCL>/<PCH> past the instruction (<Stepper::SimulateRts::AddLength>).
;; Also: NBRNCH (A2RM78, A2RM79)
.proc FellThrough
    jsr SaveRegisters
    sec
    bcs SimulateRts::AddLength
.endproc

;; What <Stepper::RunInstruction> puts after the instruction it copies to <Stepper::RunArea>: two NOPs, then a jump to
;; <Stepper::FellThrough> for an instruction that falls through and one to <Stepper::TakenBranch> for a taken
;; branch.
;;
;; The instruction overwrites as many of the NOPs as it has operand bytes.
;; Also: INITBL (A2RM78, A2RM79)
Trailer:
    nop
    nop
    jmp FellThrough
    jmp TakenBranch
.assert * - Trailer = TRAILER_SIZE, "The trailer is TRAILER_SIZE bytes."

.endscope
.else

; Startup: the power-up defaults, the disk signature and the title.
.scope Startup continued

;; The power-up defaults for $03F0-$03F4: <BRKV> = <ShowBreak>, <SOFTEV> = BASIC's cold start (<BasicColdStart>),
;; and <PWREDUP> to match.
;; Also: PWRCON (A2RM79, IIEROM82, IIETRM85)
PowerUpVectors:
    .word ShowBreak
    .word BasicColdStart
    .byte >BasicColdStart ^ SOFT_ENTRY_CHECK
.assert * - PowerUpVectors = POWER_UP_VECTOR_BYTES, "BRKV, SOFTEV and PWREDUP."

;; The disk controller signature <Startup::PowerUp> compares at $Cn01, $Cn03, $Cn05 and $Cn07: every other byte.
;;
;; The $FF bytes between are never compared, and the Enhanced IIe stops at $Cn05 (<SIGNATURE_LAST>).
;; Also: DISKID (A2RM79, IIEROM82, IIETRM85)
DiskSignature:
    .byte $20, $FF, $00, $FF, $03, $FF, $3C

;; The title <Startup::ShowTitle> shows: "Apple ][" on the original IIe, "APPLE ][" in the Autostart Monitor.
;;
;; The Enhanced IIe keeps it, but shows <Startup::TitleEnhanced> instead.
;; Also: TITLE (A2RM79, IIEROM82, IIETRM85)
Title:
.if MONITOR = MONITOR_IIE
    .byte "Apple ]["
.else
    .byte "APPLE ]["
.endif

.endscope

; Escape opens here in the Autostart and IIe Monitors. The Apple II Monitor has no escape keys I, J, K and M,
; so there it opens empty in Screen.asm, before Escape::Command (ESC1).

;; Escape mode: the escape commands, the cursor keys that keep escape mode on, and the loop that reads them.
;;
;; In the IIe Monitors it is in five pieces: <Escape::CursorKeyCommands> here, the cursor-key loop (<Escape::Perform>,
;; <Escape::CursorKey>, <Escape::NextKey>), the commands (<Escape::Command>), the IIe's key reader
;; (<Escape::ReadEscapeKey>), and the escape sequence's start (<Escape::Sequence>). The Autostart Monitor has the same
;; but the key reader. The Apple II Monitor has only the commands and the escape sequence's start.
.scope Escape

;; The cursor commands of the escape-mode keys I, J, K and M, for <Escape::CursorKey>: D (up), B (left),
;; A (right) and C (down).
;;
;; L's byte and the three after M are not used.
;; Also: XLTBL (A2RM79, IIEROM82, IIETRM85)
CursorKeyCommands:
    .byte "DBA", $FF, "C", $FF, $FF, $FF

.endscope
.endif

;; The register names <ShowRegisters> prints, "AXYPS", in the order it shows them.
;;
;; At $FB19. Apple's listing of the Apple II Monitor gives the table no name.
;; Also: RTBL (A2RM78, A2RM79, IIEROM82, IIETRM85)
RegisterNames:
.assert * = $FB19, "RegisterNames must stay at $FB19."
    .byte "AXYPS"
.assert * - RegisterNames = REGISTER_COUNT, "A name for each register."

;; Reads a game paddle: counts while its timer runs.
;;
;; At $FB1E. The count stops at 255.
;; In: X = the paddle, 0-3
;; Out: Y = its position, 0-255
;; Uses: A
;; Keeps: X, carry
;; Also: PREAD (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc ReadPaddle
.assert * = $FB1E, "ReadPaddle must stay at $FB1E."

    ; Starts the timers.
    lda PTRIG
    ldy #0
    nop
    nop

;; Counts while the paddle's timer runs.
;; Also: PREAD2 (A2RM78, A2RM79, IIEROM82, IIETRM85)
Count:
    lda PADDL0,x
    bpl Done
    iny
    bne Count

    ; Past 255: stays at 255.
    dey

;; Returns.
;; Also: RTS2D (A2RM78, A2RM79, IIEROM82, IIETRM85)
Done:
    rts
.endproc
