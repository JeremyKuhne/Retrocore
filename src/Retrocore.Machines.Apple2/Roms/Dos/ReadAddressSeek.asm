;; DOS 3.3 RWTS: READ AN ADDRESS FIELD, MOVE THE HEAD (RDADSEK)
;;
;; RDADR16 reads the next address field that passes the head: the volume, track and sector that say where the
;; head is and which sector comes next. RWTS reads address fields until it finds the sector it wants, then
;; calls READ16 or WRITE16 for the data field behind it. SEEK steps the head from half-track to half-track,
;; speeding up and slowing down with the ONTABLE and OFFTABLE delays (MsWait.asm). Runs at $B944-$B9FC where
;; DOS runs. docs/DiskII.md explains the address field, its 4-and-4 encoding and the stepper motor.

;; Reads the next address field into CSSTV: checksum, sector, track and volume.
;;
;; It looks for the prologue D5 AA 96, reads the four 4-and-4 bytes, checks that they exclusive-or to zero, and
;; checks the epilogue's DE AA. It gives up after about 770 nibbles without finding a D5, about two sectors'
;; worth of track: COUNT and Y count up from $FCFC. Once D5 AA has been seen, Y holds 3, so a wrong third
;; nibble restarts the low byte of the count.
;;
;; Each byte is two nibbles, `1 b7 1 b5 1 b3 1 b1` then `1 b6 1 b4 1 b2 1 b0`. ROL of the first, with the carry
;; set, gives `b7 1 b5 1 b3 1 b1 1`, and ANDing the second leaves the byte. The carry is set the first time by
;; the CMP that matched the 96, and after that by each ROL, which shifts out the nibble's top bit, always 1. The
;; wait loops and the delays between reads follow the same rules as READ16's.
;; In:    X = slot * 16, the card in read mode
;; Out:   carry clear, CSSTV = the checksum, CSSTV+1 = the sector, CSSTV+2 = the track, CSSTV+3 = the volume,
;;   A = $AA, Y = 0
;; Errors: carry set if no address field is found, or its checksum or epilogue is wrong
;; Uses:  A, Y, COUNT, LAST, CSUM
;; Keeps: X
RDADR16:
    ldy #$FC
    sty COUNT
RDASYN:
    iny
    bne RDA1
    inc COUNT
    beq RDERR                       ; the count ran out
RDA1:
    lda Q6L,x
    bpl RDA1
RDASN1:
    cmp #$D5
    bne RDASYN
    nop                             ; timing: too soon, the next read would see the D5 again
RDA2:
    lda Q6L,x
    bpl RDA2
    cmp #$AA
    bne RDASN1                      ; not D5 AA, but this nibble may be a D5
    ldy #$3                         ; four bytes, stored from CSSTV+3 down; also the delay
RDA3:
    lda Q6L,x
    bpl RDA3
    cmp #$96
    bne RDASN1
    lda #$0                         ; the checksum so far
RDAFLD:
    sta CSUM
RDA4:
    lda Q6L,x
    bpl RDA4
    rol a                           ; the odd bits, in place, with 1s between them
    sta LAST
RDA5:
    lda Q6L,x
    bpl RDA5
    and LAST                        ; and the even bits: the byte
    sta CSSTV,y
    eor CSUM
    dey
    bpl RDAFLD
    tay                             ; all four bytes, the checksum included, exclusive-or to zero
    bne RDERR
; The epilogue: DE AA. The EB that ends it is not checked.
RDA6:
    lda Q6L,x
    bpl RDA6
    cmp #$DE
    bne RDERR
    nop                             ; timing, as after the D5
RDA7:
    lda Q6L,x
    bpl RDA7
    cmp #$AA
    bne RDERR
;; The success exit of RDADR16 and READ16: returns with the carry clear.
;; Out:   carry = clear
RDEXIT:
    clc
    rts
;; Moves the head from half-track CURTRK to half-track A, one half-track at a time.
;;
;; Each half-track lines the head up under one of the stepper's four phases, half-track n under phase n mod 4.
;; A step turns on the phase for the next half-track, waits ONTABLE's time, turns off the phase it left and
;; waits OFFTABLE's time. Both tables are indexed by Y, the smaller of the half-tracks moved so far and those
;; still to go after this step, at most 11: the first steps and the last are slow and those between fast, so
;; the head speeds up and slows down. At the end SEEK waits 25.6 milliseconds for the head to settle and turns
;; the last phase off. MSWAIT adds the time spent waiting to MONTIMEL/MONTIMEH, the count RWTS uses to know
;; when a motor it started is up to speed.
;; In:    A = the half-track to go to, X = slot * 16, CURTRK = the half-track the head is on
;; Out:   CURTRK = TRKN = the new half-track, all phases off (unless the head was already there)
;; Uses:  A, Y, TRKCNT, PRIOR, TRKN, SLOTTEMP, MONTIMEL, MONTIMEH
;; Keeps: X
SEEK:
    stx SLOTTEMP
    sta TRKN
    cmp CURTRK
    beq SEEKRTS                     ; already there
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
    bcs STEP2                       ; 12 or more: keep Y as it was, 11
STEP:
    tay
STEP2:
    sec
    jsr SETPHASE                    ; the new half-track's phase on
    lda a:ONTABLE,y
    jsr MSWAIT
    lda PRIOR
    clc
    jsr CLRPHASE                    ; the old one's off
    lda a:OFFTABLE,y
    jsr MSWAIT
    inc TRKCNT
    bne SEEK2                       ; always
SEEKEND:
    jsr MSWAIT                      ; A = 0: 256 times 100 microseconds, to settle
    clc
;; Turns the stepper phase for half-track CURTRK on (carry set) or off (carry clear).
;;
;; The phase's switches are PHASEOFF + phase * 2 (off) and the address after (on), so the phase number shifted
;; left with the carry coming in as bit 0 picks the switch.
;; In:    carry = set for on, clear for off, CURTRK = the half-track, SLOTTEMP = slot * 16
;; Out:   X = SLOTTEMP
;; Uses:  A
;; Entry: CLRPHASE = for half-track A rather than CURTRK
SETPHASE:
    lda CURTRK
CLRPHASE:
    and #3                          ; the phase
    rol a                           ; times 2, plus the carry: on or off
    ora SLOTTEMP
    tax
    lda PHASEOFF,x
    ldx SLOTTEMP
SEEKRTS:
    rts
