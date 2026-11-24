; retrocore: style=strict
;; The delay and range-stepping routines and the cassette's bit-level code, $FCA8-$FD0B. The Enhanced IIe keeps
;; only a stub of the cassette code here, which calls the internal firmware's, and uses the rest of the space for
;; its mini-assembler's entries and the command line's uppercase conversion.

; Text.

;; The mask that turns a lowercase letter into uppercase: it clears bit 5.
UPPERCASE_MASK = %11011111
.if .not ENHANCED

; Cassette timing: delay counts, each a loop of 5 cycles.

;; <Cassette::WriteHalfCycle>'s count for a half cycle of the header tone. The carry is set while it is written,
;; which adds <ONE_DELAY>, so the tone is lower than a 1 bit's.
HEADER_DELAY = $4B

;; The count for the first half cycle of the sync bit, shorter than a 0 bit's.
SYNC_DELAY = $21

;; The count a 1 bit's half cycle adds to a 0 bit's.
ONE_DELAY = $32

;; The count <Cassette::WriteHalfCycle> leaves in Y for the next half cycle; callers adjust it for the time
;; their own code takes.
NEXT_HALF_CYCLE_DELAY = $2C

;; The count <Cassette::ReadByte> starts each of its bits after the first at.
READ_BIT_START = $3A

;; The count at which <Cassette::ReadHalfCycle> tells a 1 from a 0: a bit long enough to count Y down past 0
;; leaves it at this or above.
READ_ONE_THRESHOLD = $80

;; How many bits <Cassette::ReadByte> reads.
BITS_PER_BYTE = 8
.endif

;; Waits about (26 + 27A + 5A^2) / 2 microseconds.
;;
;; At $FCA8.
;; In: A = the count, 1-255, or 0 for 256
;; Out: A = 0, carry = set
;; Keeps: X, Y
;; Also: WAIT (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc Delay
.assert * = $FCA8, "Delay must stay at $FCA8."
    sec

;; Counts A down once for each time the inner loop runs.
;; Also: WAIT2 (A2RM78, A2RM79, IIEROM82, IIETRM85)
Outer:
    pha

;; Counts down from the outer count.
;; Also: WAIT3 (A2RM78, IIEROM82, IIETRM85)
Inner:
    sbc #1
    bne Inner
    pla
    sbc #1
    bne Outer
    rts
.endproc

;; Steps <Address4>/<Address4High> as well as A1, for the commands that copy or compare one range with another.
;;
;; At $FCB4.
;; Out: carry = set when A1 was at or past A2, the range finished
;; Keeps: X, Y
;; Also: NXTA4 (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc NextInRangeAndTarget
.assert * = $FCB4, "NextInRangeAndTarget must stay at $FCB4."
    inc Address4
    bne NextInRange
    inc Address4High
    ; Falls into NextInRange.
.endproc

;; Compares <Address1>/<Address1High> with <Address2>/<Address2High>, then steps A1.
;;
;; At $FCBA.
;; Out: carry = set when A1 was at or past A2, the range finished
;; Keeps: X, Y
;; Also: NXTA1 (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc NextInRange
.assert * = $FCBA, "NextInRange must stay at $FCBA."
    lda Address1
    cmp Address2
    lda Address1High
    sbc Address2High
    inc Address1
    bne Done
    inc Address1High

;; Also: RTS4B (A2RM78, A2RM79, IIEROM82, IIETRM85)
Done:
    rts
.endproc
.if ENHANCED

;; The cassette routines. The Enhanced IIe keeps them in its internal firmware, and only this stub here.
.scope Cassette

;; Writes a cassette header tone, through the internal firmware's <TAPEHEADR>.
;;
;; At $FCC9.
;; In: A = the tone's length, in 256 half cycles
;; Also: HEADR (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc WriteHeader
.assert * = $FCC9, "Cassette::WriteHeader must stay at $FCC9."
    sta InternalCxRomOn
    jsr TAPEHEADR
    jmp SelectSlotRom
.endproc

.endscope

;; The entries the internal firmware's mini-assembler jumps to by address, which reach the Monitor's
;; disassembler and line input.
.scope MiniAssembler

;; Shows where the line went wrong: X blanks, a caret and the bell, then reads the line again.
;;
;; At $FCD2.
;; In: X = how many blanks, to put the caret under the error
.proc ShowError
.assert * = $FCD2, "MiniAssembler::ShowError must stay at $FCD2."
    sta InternalCxRomOff
    jsr PrintBlanks
    lda #'^'
    jsr CharacterOut
    jsr Beep
    jmp ReadLine
.endproc

;; Shows the instruction just assembled, moves PC past it, then reads the next line.
;;
;; At $FCE3.
.proc ShowInstruction
.assert * = $FCE3, "MiniAssembler::ShowInstruction must stay at $FCE3."
    sta InternalCxRomOff
    jsr Disassembler::PrintInstruction
    jsr NextInstruction
    sty ProgramCounterHigh
    sta ProgramCounter
    ; Falls into ReadLine.
.endproc

;; Prompts with "!", reads a line, and has the firmware's <MINILINE> assemble it.
;;
;; At $FCF0.
.proc ReadLine
.assert * = $FCF0, "MiniAssembler::ReadLine must stay at $FCF0."
    lda #'!'
    sta PromptCharacter
    jsr GetLineAfterReturn
    sta InternalCxRomOn
    jmp MINILINE
.endproc

.endscope

;; Takes the next character of the input line, made uppercase.
;;
;; At $FCFD.
;; In: Y = its position in <InputBuffer>
;; Out: A = the character, Y = the next position
;; Keeps: X
;; Also: UPMON (IIETRM85)
.proc NextInputCharacter
.assert * = $FCFD, "NextInputCharacter must stay at $FCFD."
    lda InputBuffer,y
    iny

    ; a-z become A-Z.
    cmp #'a'
    bcc Done
    cmp #'z' + 1
    bcs Done
    and #UPPERCASE_MASK
Done:
    rts
.endproc
.else

;; The cassette's bit-level routines: tones and bits written as timed half cycles, bits read by timing the
;; transitions between them. <WriteCassette> and <ReadCassette> call them.
.scope Cassette

; Page zero, under the name this scope gives it.

;; The tape input's last level, which <ReadHalfCycle> compares the input with: <OperandLength>'s byte.
;; Also: LASTIN (A2RM78, A2RM79, IIEROM82)
LastLevel = OperandLength

;; Writes a cassette header tone, then the sync bit.
;;
;; At $FCC9.
;; In: A = the tone's length, about A x 256 half cycles; carry = set (clear makes it 256 fewer)
;; Also: HEADR (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc WriteHeader
.assert * = $FCC9, "Cassette::WriteHeader must stay at $FCC9."
    ; WriteHalfCycle counts X down: 256 half cycles a round.
    ldy #HEADER_DELAY
    jsr WriteHalfCycle
    bne WriteHeader

    ; With the carry set, takes one off A, until it passes 0 and clears the carry.
    adc #$100 - 2
    bcs WriteHeader

    ; The sync bit: a 0 with a shorter first half.
    ldy #SYNC_DELAY
    ; Falls into WriteBit.
.endproc

;; Writes a bit as two half cycles.
;;
;; At $FCD6.
;; In: carry = the bit, Y = the first half cycle's count
;; Out: Y = <NEXT_HALF_CYCLE_DELAY>, X = two less, zero = X reached 0
;; Keeps: A, carry
;; Also: WRBIT (A2RM78, A2RM79, IIEROM82)
.proc WriteBit
.assert * = $FCD6, "Cassette::WriteBit must stay at $FCD6."
    jsr WriteHalfCycle

    ; The second half: a little longer, for the time this takes.
    iny
    iny
    ; Falls into WriteHalfCycle.
.endproc

;; Waits a half cycle, longer for a 1, then toggles the cassette output.
;;
;; At $FCDB.
;; In: carry = the bit, Y = the count
;; Out: Y = <NEXT_HALF_CYCLE_DELAY>, X = one less, zero = X reached 0
;; Keeps: A, carry
;; Also: ZERDLY (A2RM78, A2RM79, IIEROM82)
.proc WriteHalfCycle
.assert * = $FCDB, "Cassette::WriteHalfCycle must stay at $FCDB."
    dey
    bne WriteHalfCycle
    bcc Toggle

    ; A 1 takes longer.
    ldy #ONE_DELAY

;; The extra wait for a 1.
;; Also: ONEDLY (A2RM78, A2RM79, IIEROM82)
OneDelay:
    dey
    bne OneDelay

;; Toggles the output by reading <CassetteOut>, and counts the half cycle in X.
;; Also: WRTAPE (A2RM78, A2RM79, IIEROM82)
Toggle:
    ldy CassetteOut
    ldy #NEXT_HALF_CYCLE_DELAY
    dex
    rts
.endproc

;; Reads a byte from the cassette, high bit first.
;;
;; At $FCEC.
;; In: Y = the first bit's starting count
;; Out: A = the byte, X = 0
;; Also: RDBYTE (A2RM78, A2RM79, IIEROM82)
.proc ReadByte
.assert * = $FCEC, "Cassette::ReadByte must stay at $FCEC."
    ldx #BITS_PER_BYTE

;; Reads a bit and shifts it in.
;; Also: RDBYT2 (A2RM78, A2RM79, IIEROM82)
NextBit:
    pha
    jsr ReadBit
    pla
    rol a
    ldy #READ_BIT_START
    dex
    bne NextBit
    rts
.endproc

;; Reads a bit by timing two transitions of the cassette input.
;;
;; At $FCFA. <LastLevel> holds the input's last level.
;; In: Y = the starting count
;; Out: carry = the bit: set for a 1, whose half cycles count Y down past 0
;; Keeps: X
;; Also: RD2BIT (A2RM78, A2RM79, IIEROM82)
.proc ReadBit
.assert * = $FCFA, "Cassette::ReadBit must stay at $FCFA."
    jsr ReadHalfCycle
    ; Falls into ReadHalfCycle.
.endproc

;; Waits for the next transition of the cassette input, counting Y down meanwhile.
;;
;; At $FCFD.
;; In: Y = the count so far
;; Out: Y = the count, carry = set when it is <READ_ONE_THRESHOLD> or above
;; Keeps: X
;; Also: RDBIT (A2RM78, A2RM79, IIEROM82)
.proc ReadHalfCycle
.assert * = $FCFD, "Cassette::ReadHalfCycle must stay at $FCFD."
    ; Until the input's level differs from the last one.
    dey
    lda CassetteIn
    eor LastLevel
    bpl ReadHalfCycle

    ; The new level is the last one now.
    eor LastLevel
    sta LastLevel
    cpy #READ_ONE_THRESHOLD
    rts
.endproc

.endscope
.endif
