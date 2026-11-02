;; PROGRAMMER'S AID #1: MUSIC ($D717-$D7FB)
;;
;; Gary J. Shannon's music routine: CALL -10473 (<Music::ENTRY>) plays one note on the speaker. A program pokes the
;; note, its length and its timbre first, which the manual names after the BASIC variables it uses:
;;
;; - PITCH (767, <Music::NOTE>): 1 to 50, a semitone apart, 32 being about middle C, or 0 for a rest;
;; - TIME (766, <Music::LONG>): the length, 1 to 255, 170 being about a second;
;; - TIMBRE (765, <Music::VOICE>): 2, 8, 16, 32 or 64, which sets how unevenly each cycle is split between the
;;   speaker's two positions, and so the tone's color. The manual recommends 32, which keeps every note in tune.
;;
;; Each cycle toggles the speaker after <Music::UPTIME> loops, then after <Music::DOWNTIME> loops, both from the
;; note's entry in <Music::NOTES>; the paths through the loops all take the same time, so the pitch holds whatever the
;; duty cycle.
;;
;; Names follow Apple's listing in the Programmer's Aid #1 manual (1978,
;; https://archive.org/details/programmers-aid-1). Part of ProgrammersAid.asm.

.scope Music

DOWNTIME = $00                      ;; the loops in the cycle's second half
UPTIME = $01                        ;; the loops in its first half
LENGTH = $02                        ;; the note's remaining length (2 bytes), counting up to 0

;; TIMBRE: the duty cycle, 2 to 64, which <LOOKUP> shifts the note's period by.
VOICE = $02FD

;; TIME: the note's length.
LONG = $02FE

;; PITCH: the note, 1 to 50, or 0 for a rest.
NOTE = $02FF

;; Inherit: <Monitor:SPKR>
SPEAKER = $C030

;; CALL -10473: plays the note <NOTE> for the time <LONG>, in the timbre <VOICE>.
ENTRY:
    jmp LOOKUP                      ; $D717

PLAY:
    ldy UPTIME                      ; $D71A the first half of a cycle
    lda SPEAKER                     ; $D71C

PLAY2:
    inc LENGTH                      ; $D71F
    bne PATH1                       ; $D721
    inc LENGTH+1                    ; $D723
    bne PATH2                       ; $D725
    rts                             ; $D727 the note is over

PATH1:
    nop                             ; $D728 as long as the other path
    jmp PATH2                       ; $D729

PATH2:
    dey                             ; $D72C
    beq DOWN                        ; $D72D
    jmp PATH3                       ; $D72F

PATH3:
    bne PLAY2                       ; $D732 always, taking as long as the branch to DOWN

DOWN:
    ldy DOWNTIME                    ; $D734 the second half
    lda SPEAKER                     ; $D736

PLAY3:
    inc LENGTH                      ; $D739
    bne PATH4                       ; $D73B
    inc LENGTH+1                    ; $D73D
    bne PATH5                       ; $D73F
    rts                             ; $D741

PATH4:
    nop                             ; $D742
    jmp PATH5                       ; $D743

PATH5:
    dey                             ; $D746
    beq PLAY                        ; $D747
    jmp PATH6                       ; $D749

PATH6:
    bne PLAY3                       ; $D74C always

;; Looks the note up: splits its period between <UPTIME> and <DOWNTIME> as <VOICE> says, and sets <LENGTH> from
;; <LONG>; plays it, or a rest for note 0.
LOOKUP:
    lda NOTE                        ; $D74E
    asl                             ; $D751
    tay                             ; $D752
    lda NOTES,y                     ; $D753
    sta DOWNTIME                    ; $D756
    lda VOICE                       ; $D758

SHIFT:
    lsr                             ; $D75B DOWNTIME = the period shifted by the timbre
    beq DONE                        ; $D75C
    lsr DOWNTIME                    ; $D75E
    bne SHIFT                       ; $D760

DONE:
    lda NOTES,y                     ; $D762
    sec                             ; $D765
    sbc DOWNTIME                    ; $D766
    sta UPTIME                      ; $D768 UPTIME = the period less DOWNTIME
    iny                             ; $D76A
    lda NOTES,y                     ; $D76B
    adc DOWNTIME                    ; $D76E
    sta DOWNTIME                    ; $D770 DOWNTIME = the second byte plus DOWNTIME
    lda #$00                        ; $D772
    sec                             ; $D774
    sbc LONG                        ; $D775
    sta LENGTH+1                    ; $D778
    lda #$00                        ; $D77A
    sta LENGTH                      ; $D77C
    lda UPTIME                      ; $D77E
    bne PLAY                        ; $D780 not note 0

;; Note 0: waits as long as a note would, silently.
REST:
    nop                             ; $D782
    nop                             ; $D783
    jmp REST2                       ; $D784

REST2:
    inc LENGTH                      ; $D787
    bne REST3                       ; $D789
    inc LENGTH+1                    ; $D78B
    bne REST4                       ; $D78D
    rts                             ; $D78F

REST3:
    nop                             ; $D790
    jmp REST4                       ; $D791

REST4:
    bne REST                        ; $D794 always

;; Each note's period, as two loop counts that <LOOKUP> splits into the cycle's halves: note 0's, then the scale's 50.
NOTES:
    .byte $00, $00, $F6, $F6, $E8, $E8, $DB, $DB    ; $D796
    .byte $CF, $CF, $C3, $C3, $B8, $B8, $AE, $AE    ; $D79E
    .byte $A4, $A4, $9B, $9B, $92, $92, $8A, $8A    ; $D7A6
    .byte $82, $82, $7B, $7B, $74, $74, $6D, $6E    ; $D7AE
    .byte $67, $68, $61, $62, $5C, $5C, $57, $57    ; $D7B6
    .byte $52, $52, $4D, $4E, $49, $49, $45, $45    ; $D7BE
    .byte $41, $41, $3D, $3E, $3A, $3A, $36, $37    ; $D7C6
    .byte $33, $34, $30, $31, $2E, $2E, $2B, $2C    ; $D7CE
    .byte $29, $29, $26, $27, $24, $25, $22, $23    ; $D7D6
    .byte $20, $21, $1E, $1F, $1D, $1D, $1B, $1C    ; $D7DE
    .byte $1A, $1A, $18, $19, $17, $17, $15, $16    ; $D7E6
    .byte $14, $15, $13, $14, $12, $12, $11, $11    ; $D7EE
    .byte $10, $10, $0F, $10, $0E, $0F              ; $D7F6

.endscope
