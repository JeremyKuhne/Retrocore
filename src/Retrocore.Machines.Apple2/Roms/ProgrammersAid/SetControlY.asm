; retrocore: style=strict
;; Programmer's Aid #1: setting up Control-Y ($D5B0-$D5BB)
;;
;; The routine the Control-Y setups share: Relocate's (D4D5G), Tape Verify's (D52EG) and the RAM test's (D5BCG).
;; Apple's listings call it SETCTLY but do not include it. Part of ProgrammersAid.asm.

;; Points the Monitor's Control-Y command at a routine: writes JMP and the routine's address to <UserJump>, where the
;; Monitor jumps for Control-Y.
;; In: A = the routine's address, low byte, Y = its high byte
;; Uses: A
;; Keeps: X, Y
;; Also: SETCTLY (PA1)
.proc SetControlY
.assert * = $D5B0, "SetControlY must stay at $D5B0, where the Control-Y setups call it."

;; The 6502's JMP opcode, absolute.
OPCODE_JMP = $4C

    sta UserJump + 1
    sty UserJump + 2
    lda #OPCODE_JMP
    sta UserJump
    rts
.endproc
