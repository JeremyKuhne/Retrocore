; retrocore: style=strict
;; DOS 3.3 RWTS: reading an address field, moving the head
;;
;; <DiskII::ReadAddressField> reads the next address field that passes the head: the volume, track and sector that
;; say where the head is and which sector comes next. RWTS reads address fields until it finds the sector it wants,
;; then calls <DiskII::ReadDataField> or <DiskII::WriteDataField> for the data field behind it.
;; <DiskII::MoveHead> steps the head from half-track to half-track, speeding up and slowing down with the
;; <DiskII::OnTimes> and <DiskII::OffTimes> delays (MsWait.asm), and <DiskII::SetPhase> turns the stepper's phases
;; on and off. At $B944-$B9FC where DOS runs. docs/DiskII.md explains the address field, its 4-and-4 encoding and
;; the stepper motor.

; DiskII: the address field reader, the shared success exit and the head's stepper.
.scope DiskII continued

;; Reads the next address field into AddressField: the checksum, the sector, the track and the volume.
;;
;; It looks for the prologue D5 AA 96, reads the four 4-and-4 bytes, checks that they exclusive-or to zero, and checks
;; the epilogue's DE AA. It gives up after about 770 nibbles without finding a D5, about two sectors' worth of track:
;; <ReadAddressField::SearchCount> and Y count up from $FCFC. Once D5 AA has been seen, Y holds 3, so a wrong third
;; nibble restarts the low byte of the count.
;;
;; Each byte is two nibbles, `1 b7 1 b5 1 b3 1 b1` then `1 b6 1 b4 1 b2 1 b0`. ROL of the first, with the carry
;; set, gives `b7 1 b5 1 b3 1 b1 1`, and ANDing the second leaves the byte. The carry is set the first time by the
;; CMP that matched the 96, and after that by each ROL, which shifts out the nibble's top bit, always 1. The wait
;; loops and the delays between reads follow the same rules as <ReadDataField>'s. At $B944 where DOS runs.
;; In:    X = slot * 16, the card in read mode
;; Out:   carry = clear, AddressField = the checksum, AddressField+1 = the sector, AddressField+2 = the track,
;;   AddressField+3 = the volume, A = $AA, Y = 0
;; Errors: carry = set if no address field is found, or its checksum or epilogue is wrong
;; Uses:  A, Y
;; Keeps: X
;; Also: RDADR16 (DOS33), RDADR (DOS31)
.proc ReadAddressField

;; The count of nibbles left to search, high byte: counted up from <SEARCH_START> with Y as the low byte, failing
;; when it reaches zero.
;; Also: COUNT (DOS33, DOS31)
SearchCount = LowResBase

;; The first, odd-bits nibble of a 4-and-4 pair, shifted into place, while the second is read.
;; Also: LAST (DOS33, DOS31)
OddBits = LowResBase

;; The running checksum of the field: its bytes so far exclusive-ored together.
;; Also: CSUM (DOS33, DOS31)
Checksum = LowResBaseHigh

;; Both bytes of the search count start here: $FCFC, $0304 nibbles before it reaches zero.
SEARCH_START = $FC

;; The bytes of an address field: the volume, the track, the sector and the checksum.
FIELD_BYTES = 4

    ldy #SEARCH_START
    sty SearchCount

;; Counts the nibbles looked through, failing when the count runs out.
;; Also: RDASYN (DOS33, DOS31)
Search:
    iny
    bne WaitD5
    inc SearchCount
    beq Fail                        ; the count ran out

;; Waits for a nibble.
;; Also: RDA1 (DOS33, DOS31)
WaitD5:
    lda DataLatch,x
    bpl WaitD5

;; Is the nibble a D5? Also where a wrong second or third nibble is tested again.
;; Also: RDASN1 (DOS33, DOS31)
CheckD5:
    cmp #PROLOGUE_FIRST
    bne Search
    nop                             ; timing: too soon, the next read would see the D5 again

;; Waits for the prologue's AA.
;; Also: RDA2 (DOS33, DOS31)
WaitAA:
    lda DataLatch,x
    bpl WaitAA
    cmp #PROLOGUE_SECOND
    bne CheckD5                     ; not D5 AA, but this nibble may be a D5
    ldy #FIELD_BYTES - 1            ; four bytes, stored from AddressField+3 down; also the delay

;; Waits for the address mark, 96.
;; Also: RDA3 (DOS33, DOS31)
WaitAddressMark:
    lda DataLatch,x
    bpl WaitAddressMark
    cmp #ADDRESS_MARK
    bne CheckD5
    lda #0                          ; the checksum so far

;; Notes the checksum so far and reads the next byte.
;; Also: RDAFLD (DOS33, DOS31)
NextByte:
    sta Checksum

;; Waits for the byte's odd bits.
;; Also: RDA4 (DOS33, DOS31)
WaitOdd:
    lda DataLatch,x
    bpl WaitOdd
    rol a                           ; the odd bits, in place, with 1s between them
    sta OddBits

;; Waits for the byte's even bits.
;; Also: RDA5 (DOS33, DOS31)
WaitEven:
    lda DataLatch,x
    bpl WaitEven
    and OddBits                     ; and the even bits: the byte
    sta AddressField,y
    eor Checksum
    dey
    bpl NextByte
    tay                             ; all four bytes, the checksum included, exclusive-or to zero
    bne Fail

    ; The epilogue: DE AA. The EB that ends it is not checked.
;; Waits for the epilogue's DE.
;; Also: RDA6 (DOS33, DOS31)
WaitDE:
    lda DataLatch,x
    bpl WaitDE
    cmp #EPILOGUE_FIRST
    bne Fail
    nop                             ; timing, as after the D5

;; Waits for the epilogue's AA; it falls into <Succeed>.
;; Also: RDA7 (DOS33, DOS31)
WaitEpilogueAA:
    lda DataLatch,x
    bpl WaitEpilogueAA
    cmp #EPILOGUE_SECOND
    bne Fail
    ; Falls into Succeed.
.endproc

;; The success exit of <ReadAddressField> and <ReadDataField>: returns with the carry clear.
;; Out:   carry = clear
;; Also: RDEXIT (DOS33, DOS31)
.proc Succeed
    clc
    rts
.endproc

;; Moves the head from half-track CurrentTrack to half-track A, one half-track at a time.
;;
;; Each half-track lines the head up under one of the stepper's four phases, half-track n under phase n mod 4. A
;; step turns on the phase for the next half-track, waits <OnTimes>' time, turns off the phase it left and waits
;; <OffTimes>' time. Both tables are indexed by Y, the smaller of the half-tracks moved so far and those still to go
;; after this step, at most 11: the first steps and the last are slow and those between fast, so the head speeds up
;; and slows down. At the end it waits 25.6 milliseconds for the head to settle and turns the last phase off.
;; <Wait> adds the time spent waiting to <MotorTime>, the count RWTS uses to know when a motor it started is up to
;; speed. Falls into <SetPhase>.
;; In:    A = the half-track to go to, X = slot * 16, CurrentTrack = the half-track the head is on
;; Out:   CurrentTrack = TargetHalfTrack = the new half-track, all phases off (unless the head was already there)
;; Uses:  A, Y, TargetHalfTrack, MotorTime, MotorTimeHigh
;; Keeps: X
;; Also: SEEK (DOS33, DOS31)
.proc MoveHead

;; The number of half-tracks the head has moved so far, counted up from 0, which indexes <OnTimes> and <OffTimes>
;; while it is the smaller.
;; Also: TRKCNT (DOS33, DOS31)
StepsMoved = LowResBase

;; The half-track the head is leaving, whose phase goes off once the next one is on.
;; Also: PRIOR (DOS33, DOS31)
PriorHalfTrack = LowResBaseHigh

;; The slot times 16, kept while X indexes a phase's switch; <SetPhase> adds the phase number times 2 to it to
;; reach <Phase0Off> or <Phase0On> for that phase.
;; Also: SLOTTEMP (DOS33, DOS31)
SlotTimes16 = ScrollBaseHigh

    stx SlotTimes16
    sta TargetHalfTrack
    cmp CurrentTrack
    beq SetPhase::Return            ; already there
    lda #0
    sta StepsMoved

;; Takes the next step, or stops when the head has arrived.
;; Also: SEEK2 (DOS33, DOS31)
NextStep:
    lda CurrentTrack
    sta PriorHalfTrack              ; the half-track being left
    sec
    sbc TargetHalfTrack
    beq Settle                      ; arrived
    bcs Outward
    eor #$FF                        ; in: A = half-tracks still to go after this step
    inc CurrentTrack
    bcc TakeSmaller                 ; always

;; Moving out: the half-tracks still to go after this step.
;; Also: OUT (DOS33, DOS31)
Outward:
    adc #$FE                        ; A - 1 (the carry is set)
    dec CurrentTrack

;; Takes the smaller of the half-tracks moved and those left.
;; Also: MINTST (DOS33, DOS31)
TakeSmaller:
    cmp StepsMoved
    bcc Limit
    lda StepsMoved

;; Keeps Y at the tables' last entry, 11, once the smaller is 12 or more.
;; Also: MAXTST (DOS33, DOS31)
Limit:
    cmp #TIMES_COUNT
    bcs Pulse                       ; 12 or more: Y as it was, 11

;; Takes the smaller as the tables' index. Nothing branches here in DOS 3.3; the 1978 code did.
;; Also: STEP (DOS33, DOS31)
SetIndex:
    tay

;; Turns the new half-track's phase on, waits, turns the old one off and waits.
;; Also: STEP2 (DOS33)
Pulse:
    sec
    jsr SetPhase                    ; the new half-track's phase on
    lda a:OnTimes,y
    jsr Wait
    lda PriorHalfTrack
    clc
    jsr SetPhase::OfHalfTrack       ; the old one's off
    lda a:OffTimes,y
    jsr Wait
    inc StepsMoved
    bne NextStep                    ; always

;; Arrived: waits 256 times 100 microseconds for the head to settle, then turns the phase off.
;; Also: SEEKEND (DOS33, DOS31)
Settle:
    jsr Wait                        ; A = 0: 256 waits
    clc
    ; Falls into SetPhase.
.endproc

;; Turns the stepper phase for half-track CurrentTrack on (carry set) or off (carry clear).
;;
;; The phase's switches are <Phase0Off> + phase * 2 (off) and the address after (on), so the phase number shifted
;; left with the carry coming in as bit 0 picks the switch.
;; In:    carry = set for on, clear for off, CurrentTrack = the half-track, MoveHead::SlotTimes16 = slot * 16
;; Out:   X = MoveHead::SlotTimes16
;; Uses:  A
;; Keeps: Y
;; Entry: OfHalfTrack = for half-track A rather than CurrentTrack
;; Also: SETPHASE (DOS33)
.proc SetPhase
    lda CurrentTrack

;; Turns the phase of half-track A on or off.
;; Also: CLRPHASE (DOS33)
OfHalfTrack:
    and #3                          ; the phase
    rol a                           ; times 2, plus the carry: on or off
    ora MoveHead::SlotTimes16
    tax
    lda Phase0Off,x
    ldx MoveHead::SlotTimes16

;; Returns; <MoveHead> also returns here when the head is already on the half-track.
;; Also: SEEKRTS (DOS33), SEEKXIT (DOS31)
Return:
    rts
.endproc

.endscope
