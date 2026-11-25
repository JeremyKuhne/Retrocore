; retrocore: style=strict
;; Programmer's Aid #1: music ($D717-$D7FB)
;;
;; Gary J. Shannon's music routine: CALL -10473 (<Music::PlayNote>) plays one note on the speaker. A program pokes the
;; note, its length and its timbre first, which the manual names after the BASIC variables it uses:
;;
;; - `PITCH` (767, <Music::Pitch>): 1 to 50, a semitone apart, 32 being about middle C, or 0 for a rest;
;; - `TIME` (766, <Music::Duration>): the length, 1 to 255, 170 being about a second;
;; - `TIMBRE` (765, <Music::Timbre>): 2, 8, 16, 32 or 64, which sets how unevenly each cycle is split between the
;;   speaker's two positions, and so the tone's color. The manual recommends 32, which keeps every note in tune.
;;
;; Each cycle toggles the speaker after <Music::FirstHalfCount> loops, then after <Music::SecondHalfCount> loops, both
;; from the note's entry in <Music::NotePeriods>; the paths through the loops all take the same time, so the pitch
;; holds whatever the duty cycle.
;;
;; The listing's names are those of Apple's listing in the Programmer's Aid #1 manual (1978,
;; https://archive.org/details/programmers-aid-1). Part of ProgrammersAid.asm.

.scope Music

;; The loops in the cycle's second half: SWEET16's R0, low byte, which Music borrows.
;; Also: DOWNTIME (PA1)
SecondHalfCount = Sweet16Registers

;; The loops in the cycle's first half: R0's high byte.
;; Also: UPTIME (PA1)
FirstHalfCount = Sweet16Registers + 1

;; The note's remaining length (2 bytes), counting up to 0: R1. Apple's listing calls it LENGTH, which here would
;; clash with the Monitor's LENGTH, <OperandLength>.
NoteLength = Sweet16Registers + 1 * SWEET16_REGISTER_SIZE

;; `TIMBRE` (POKE 765): the duty cycle, 2 to 64, which <LookUp> shifts the note's period by.
;; Also: VOICE (PA1)
Timbre = $02FD

;; `TIME` (POKE 766): the note's length, 1 to 255.
;; Also: LONG (PA1)
Duration = $02FE

;; `PITCH` (POKE 767): the note, 1 to 50, or 0 for a rest.
;; Also: NOTE (PA1)
Pitch = $02FF

;; One entry of <Music::NotePeriods>: a note's period, as two loop counts.
;; Parameters:
;;   first = the loops <Music::LookUp> splits between the cycle's halves as <Music::Timbre> says
;;   second = the loops it adds to the second half, with 1 more
.macro NotePeriod first, second
    .byte first, second
.endmacro

;; CALL -10473: plays the note <Pitch> for the time <Duration>, in the timbre <Timbre>.
;; In: Pitch = the note, 0 to 50, Duration = its length, Timbre = its duty cycle
;; Keeps: X
;; Also: ENTRY (PA1)
.proc PlayNote
.assert * = $D717, "Music::PlayNote must stay at $D717, CALL -10473."
    jmp LookUp
.endproc

;; Plays the note <LookUp> set up: toggles the speaker after <FirstHalfCount> loops and again after <SecondHalfCount>,
;; counting <NoteLength> up once a loop, and returns when it reaches 0.
;;
;; The paths through a loop take nearly the same time: where <NoteLength>'s low byte does not carry, a NOP and a JMP
;; stand for the INC of its high byte, and the JMPs to the next line stand for a taken branch; the carry, once in 256
;; loops, takes 2 cycles more. Apple's listing calls the
;; second half DOWN, which here would clash with <HiResGraphics::Step::Down>'s.
;; In: FirstHalfCount = the loops of the first half, SecondHalfCount = of the second, NoteLength = the length, as a
;;   negative count
;; Keeps: X
;; Also: PLAY (PA1)
.proc Play

    ; The first half of a cycle.
    ldy FirstHalfCount
    lda Speaker

;; Also: PLAY2 (PA1)
FirstHalfLoop:
    inc NoteLength
    bne FirstNotCarried
    inc NoteLength + 1
    bne CountFirstHalf
    ; The note is over.
    rts

;; Also: PATH1 (PA1)
FirstNotCarried:
    nop
    jmp CountFirstHalf

;; Also: PATH2 (PA1)
CountFirstHalf:
    dey
    beq SecondHalf
    jmp NextFirstHalf

;; Also: PATH3 (PA1)
NextFirstHalf:
    ; Always taken, as long as the branch to SecondHalf.
    bne FirstHalfLoop

SecondHalf:
    ldy SecondHalfCount
    lda Speaker

;; Also: PLAY3 (PA1)
SecondHalfLoop:
    inc NoteLength
    bne SecondNotCarried
    inc NoteLength + 1
    bne CountSecondHalf
    rts

;; Also: PATH4 (PA1)
SecondNotCarried:
    nop
    jmp CountSecondHalf

;; Also: PATH5 (PA1)
CountSecondHalf:
    dey
    beq Play
    jmp NextSecondHalf

;; Also: PATH6 (PA1)
NextSecondHalf:
    ; Always taken.
    bne SecondHalfLoop
.endproc

;; Looks the note up: splits its period between <FirstHalfCount> and <SecondHalfCount> as <Timbre> says, and sets
;; <NoteLength> from <Duration>; then plays it, or a rest for note 0.
;;
;; The second half gets the period's first byte shifted right once for each bit <Timbre> is shifted to reach 0, plus
;; the period's second byte, plus 1, the carry the subtraction leaves; the first half gets the first byte less the
;; shifted part.
;; In: Pitch = the note, Duration = its length, Timbre = its duty cycle
;; Keeps: X
;; Also: LOOKUP (PA1)
.proc LookUp
    lda Pitch
    asl
    tay
    lda NotePeriods,y
    sta SecondHalfCount
    lda Timbre

;; Shifts the period right once for each bit the timbre still has.
;; Also: SHIFT (PA1)
ShiftByTimbre:
    lsr
    beq SplitPeriod
    lsr SecondHalfCount
    bne ShiftByTimbre

;; Apple's listing calls it DONE, which here would clash with <Renumber::Append::Done>.
SplitPeriod:
    lda NotePeriods,y
    sec
    sbc SecondHalfCount
    sta FirstHalfCount
    iny
    lda NotePeriods,y
    adc SecondHalfCount
    sta SecondHalfCount

    ; The length counts up from -Duration x 256 to 0.
    lda #0
    sec
    sbc Duration
    sta NoteLength + 1
    lda #0
    sta NoteLength
    lda FirstHalfCount
    ; Note 0's first half is 0.
    bne Play
    ; Falls into Rest.
.endproc

;; Note 0: waits as long as a note would, silently.
;; In: NoteLength = the length, as a negative count
;; Keeps: X
;; Also: REST (PA1)
.proc Rest
    nop
    nop
    jmp CountRest

;; Also: REST2 (PA1)
CountRest:
    inc NoteLength
    bne RestNotCarried
    inc NoteLength + 1
    bne NextRest
    rts

;; Also: REST3 (PA1)
RestNotCarried:
    nop
    jmp NextRest

;; Also: REST4 (PA1)
NextRest:
    ; Always taken.
    bne Rest
.endproc

;; Each note's period, as two loop counts that <LookUp> splits into the cycle's halves: note 0's, then the scale's 50.
;; Also: NOTES (PA1)
NotePeriods:
    NotePeriod $00, $00
    NotePeriod $F6, $F6
    NotePeriod $E8, $E8
    NotePeriod $DB, $DB
    NotePeriod $CF, $CF
    NotePeriod $C3, $C3
    NotePeriod $B8, $B8
    NotePeriod $AE, $AE
    NotePeriod $A4, $A4
    NotePeriod $9B, $9B
    NotePeriod $92, $92
    NotePeriod $8A, $8A
    NotePeriod $82, $82
    NotePeriod $7B, $7B
    NotePeriod $74, $74
    NotePeriod $6D, $6E
    NotePeriod $67, $68
    NotePeriod $61, $62
    NotePeriod $5C, $5C
    NotePeriod $57, $57
    NotePeriod $52, $52
    NotePeriod $4D, $4E
    NotePeriod $49, $49
    NotePeriod $45, $45
    NotePeriod $41, $41
    NotePeriod $3D, $3E
    NotePeriod $3A, $3A
    NotePeriod $36, $37
    NotePeriod $33, $34
    NotePeriod $30, $31
    NotePeriod $2E, $2E
    NotePeriod $2B, $2C
    NotePeriod $29, $29
    NotePeriod $26, $27
    NotePeriod $24, $25
    NotePeriod $22, $23
    NotePeriod $20, $21
    NotePeriod $1E, $1F
    NotePeriod $1D, $1D
    NotePeriod $1B, $1C
    NotePeriod $1A, $1A
    NotePeriod $18, $19
    NotePeriod $17, $17
    NotePeriod $15, $16
    NotePeriod $14, $15
    NotePeriod $13, $14
    NotePeriod $12, $12
    NotePeriod $11, $11
    NotePeriod $10, $10
    NotePeriod $0F, $10
    NotePeriod $0E, $0F
.assert * - NotePeriods = 51 * 2, "Note 0 and the scale's 50 notes, 2 bytes each."

.endscope
