;; DOS 3.2 RWTS: MOVE THE HEAD, WAIT, AND THE NIBBLE-TO-VALUE TABLE
;;
;; SEEK steps the head from half-track to half-track, speeding up and slowing down with the ONTABLE and
;; OFFTABLE delays, and MSWAIT is the delay they use, which also counts time for the motor's start. After them
;; comes the used end of DNIBL, the table that turns a nibble back into its five-bit value. Runs at $BA1E-$BAFF
;; where DOS runs. docs/DiskII.md explains the stepper motor.

;; Moves the head from half-track CURTRK to half-track A, one half-track at a time.
;;
;; Each half-track lines the head up under one of the stepper's four phases, half-track n under phase n mod 4.
;; A step turns on the phase for the next half-track, waits ONTABLE's time, turns off the phase it left and
;; waits OFFTABLE's time. Both tables are indexed by Y, the smaller of the half-tracks moved so far and those
;; still to go after this step, at most 11: the first steps and the last are slow and those between fast, so
;; the head speeds up and slows down. At the end SEEK waits 25.5 milliseconds for the head to settle, leaving
;; the last phase on; MYSEEK (Rwts32.asm) turns the phases off before the next seek. MSWAIT adds the time spent
;; waiting to MONTIMEL/MONTIMEH, the count RWTS uses to know when a motor it started is up to speed.
;; In:    A = the half-track to go to, X = slot * 16, CURTRK = the half-track the head is on
;; Out:   CURTRK = TRKN = the new half-track
;; Uses:  A, Y, TRKCNT, PRIOR, TRKN, SLOTTEMP, MONTIMEL, MONTIMEH
;; Keeps: X
SEEK:
    sta TRKN
    cmp CURTRK
    beq SEEKRTS                     ; already there
    stx SLOTTEMP
    lda #$0
    sta TRKCNT
SEEK2:
    lda CURTRK
    sta PRIOR                       ; the half-track being left
    sec
    sbc TRKN
    beq SEEKEND                     ; arrived
    bcs OUT
    eor #$FF                        ; in: A = half-tracks still to go after this step
    inc CURTRK
    bcc MINTST                      ; always
OUT:
    adc #$FE                        ; out: A - 1 (the carry is set), half-tracks still to go after this step
    dec CURTRK
MINTST:
    cmp TRKCNT
    bcc MAXTST
    lda TRKCNT                      ; the smaller of the two
MAXTST:
    cmp #$C
    bcc STEP
    lda #$B                         ; at most 11
STEP:
    tay

; The phase's switches are PHASEOFF + phase * 2 (off) and the address after (on).
    lda CURTRK
    and #3
    asl a
    ora SLOTTEMP
    tax
    lda PHASEON,x                   ; the new half-track's phase on
    lda ONTABLE,y
    jsr MSWAIT
    lda PRIOR
    and #3
    asl a
    ora SLOTTEMP
    tax
    lda PHASEOFF,x                  ; the old one's off
    lda OFFTABLE,y
    jsr MSWAIT
    inc TRKCNT
    bne SEEK2                       ; always
SEEKEND:
    lda #$FF                        ; 255 times 100 microseconds, to settle
    jsr MSWAIT
    ldx SLOTTEMP
SEEKRTS:
    rts

;; Waits about A times 100 microseconds (A = 0 waits 256 times), adding A to the motor-on count.
;;
;; Each pass of the outer loop takes 101 cycles, about 100 microseconds at the Apple II's 1.02 MHz.
;; In:    A = the time, in hundreds of microseconds
;; Out:   A = 0, X = 0
;; Uses:  MONTIMEL, MONTIMEH
;; Keeps: Y
MSWAIT:
    ldx #$11
MSW1:
    dex
    bne MSW1
    inc MONTIMEL
    bne MSW2
    inc MONTIMEH
MSW2:
    sec
    sbc #$1
    bne MSWAIT

;; The end of the relocator's first code range in RWTS, which leaves out this last RTS: ASC1 to AEC1.
AEC1:
    rts

;; How long to wait, in hundreds of microseconds, after turning a phase on and after turning the old one off,
;; indexed by how far into or before the end of a seek the step is (SEEK).
ONTABLE:
    .byte 1, $30, $28
    .byte $24, $20, $1E
    .byte $1D, $1C, $1C
    .byte $1C, $1C, $1C
OFFTABLE:
    .byte $70, $2C, $26
    .byte $22, $1F, $1E
    .byte $1D, $1C, $1C
    .byte $1C, $1C, $1C

;; The table READ13 uses to turn a nibble back into its five-bit value, shifted left three places: entry n,
;; at DNIBL + n, for nibble n. Only the entries for the 32 nibbles $AB to $FF are used, so DNIBL starts in the
;; middle of RWTS's code, a page boundary $AB bytes before the first. The table's entries for bytes that are
;; not nibbles hold other values, which nothing uses.
XP = >(*)
DNIBL = 256*XP                      ;; $BA00 where DOS runs
    .byte $00, $00, $00             ; unused
    .assert * = DNIBL + $AB
    .byte $00, $01, $08, $10        ; $AB-$AE
    .byte $18, $02, $03, $04        ; $AF-$B2
    .byte $05, $06, $20, $28        ; $B3-$B6
    .byte $30, $07, $09, $38        ; $B7-$BA
    .byte $40, $0A, $48, $50        ; $BB-$BE
    .byte $58, $0B, $0C, $0D        ; $BF-$C2
    .byte $0E, $0F, $11, $12        ; $C3-$C6
    .byte $13, $14, $15, $16        ; $C7-$CA
    .byte $17, $19, $1A, $1B        ; $CB-$CE
    .byte $1C, $1D, $1E, $21        ; $CF-$D2
    .byte $22, $23, $24, $60        ; $D3-$D6
    .byte $68, $25, $26, $70        ; $D7-$DA
    .byte $78, $27, $80, $88        ; $DB-$DE
    .byte $90, $29, $2A, $2B        ; $DF-$E2
    .byte $2C, $2D, $2E, $2F        ; $E3-$E6
    .byte $31, $32, $33, $98        ; $E7-$EA
    .byte $A0, $34, $A8, $B0        ; $EB-$EE
    .byte $B8, $35, $36, $37        ; $EF-$F2
    .byte $39, $3A, $C0, $C8        ; $F3-$F6
    .byte $D0, $3B, $3C, $D8        ; $F7-$FA
    .byte $E0, $3E, $E8, $F0        ; $FB-$FE
    .byte $F8                       ; $FF
