;; DOS 3.3 RWTS: FORMAT A DISK (FORMATR)
;;
;; RWTS's FORMAT command (IOB 0C = 4), which INIT uses: it writes all 35 tracks with 16 sectors each, every
;; sector an address field (WADR16, WriteAddress.asm) and a data field of zeros (WRITE16, WriteSector.asm), and
;; reads each track back to check it. Between sectors it writes a gap of self-sync nibbles set by NSYNC, which
;; starts at 40 and is cut whenever a check finds a sector other than 0 first after the end of the writing. Runs
;; at $BEAF-$BFB7 where DOS runs, followed by INTRLEAV, the table RWTS uses to number sectors. It writes no VTOC
;; or catalog: the file manager's FFMT (FileManagerIo.asm), which calls it, writes those afterwards.
;; docs/DiskII.md explains the fields and self-sync nibbles.

;; The number of self-sync nibbles, less one, that the formatter writes before each sector after the first.
;;
;; <DSKFORM> starts it at 40. When the check after writing a track (<VTRACK>) finds that sector 0 is not the
;; first to come round, the gaps were too long for the track: it cuts NSYNC by 1, or 2 above 16, and rewrites
;; the track, and gives up below 5. After track 0 checks, it is cut by 2 more while it is 16 or more.
;; See: <DSKFORM>, <WTRACK16>, <VTRACK>
NSYNC = $45

;; Formats the disk in the IOB's slot and drive with volume number IOB 03, and turns the motor off.
;;
;; RWTS jumps here, so the RTS at the end returns from RWTS. It first records the head as being at half-track
;; $A0, further in than any track, so the first seek, to track 0, steps the head out until it stops against
;; track 0. For each track it seeks, writes and checks the track (WTRACK16), then finds sector 0 and reads it
;; once more: so every track's writing starts a fixed time after sector 0 of the track before has passed. It also
;; uses what the routines it calls use.
;; In:    X = slot * 16, IOB 03 = the volume, the drive running
;; Out:   carry = clear on success, with the motor off and IOB 0D not written
;; Errors: carry set and IOB 0D = 8 when a track cannot be written or checked; if sector 0 cannot then be found,
;;   IOB 0D gets whatever A holds (see FINDS0)
;; Uses:  A, Y, NVOL, AA, TRK, NSECT, NSYNC, RETRYCNT, NBUF1, NBUF2, FOUND
DSKFORM:
; The diagnostic build leaves the formatter out; DSKFORM is then the address of INTRLEAV.
.if DIAGMODE
.else
    ldy #3
    lda (IOBPL),y                   ; IOB 03: the volume
    sta NVOL
    lda #$AA
    sta AA                          ; for WADR16's timing
    ldy #$56
    lda #0
    sta TRK
; Every sector is written as 256 zeros: clear NBUF2 and NBUF1.
CLRNBUF2:
    sta NBUF2-1,y
    dey
    bne CLRNBUF2
CLRNBUF1:
    sta NBUF1,y
    dey
    bne CLRNBUF1
    lda #$50
    jsr SETTRK                      ; pretend the head is at half-track $A0
    lda #$28
    sta NSYNC                       ; 40 self-sync nibbles between sectors, to start with
FORMTRK:
    lda TRK
    jsr MYSEEK
    jsr WTRACK16
FORMERR1:
    lda #8                          ; the return code for a failed format
    bcs FORMERR
    lda #$30
    sta RETRYCNT
; Find sector 0 and read its data field. If 47 tries fail, FORMERR stores A as the return code, but A then
; holds whatever the last RDADR16, READ16 or LDA SECT left in it, not 8.
FINDS0:
    sec
    dec RETRYCNT
    beq FORMERR
    jsr RDADR16
    bcs FINDS0
    lda SECT
    bne FINDS0
    jsr READ16
    bcs FINDS0
    inc TRK
    lda TRK
    cmp #$23                        ; 35 tracks
    bcc FORMTRK
    clc
    bcc FORMDONE                    ; always
FORMERR:
    ldy #$0D
    sta (IOBPL),y                   ; IOB 0D: the return code
    sec
FORMDONE:
    lda MOTOROFF,x
    rts
;; Writes the 16 sectors of track TRK, then checks them (VTRACK); rewrites the track until it checks or cannot be
;; fixed.
;;
;; Sector 0 comes after 129 self-sync nibbles and the others after NSYNC + 1. Each sector is an address field
;; and a data field from NBUF1 and NBUF2. It also uses what the routines it calls use.
;; In:    X = slot * 16, TRK, NVOL, NSYNC, AA = $AA, NBUF1 and NBUF2 = the data, the head on the track
;; Out:   carry = clear if the track was written and checked
;; Errors: carry set if the disk is write-protected or the track would not check
;; Uses:  A, Y, NSECT, NSYNC, RETRYCNT, FOUND, CSSTV
;; Keeps: X
WTRACK16:
    lda #0
    sta NSECT
    ldy #128
    bne WSECT0                      ; always
WSECT:
    ldy NSYNC
WSECT0:
    jsr WADR16
    bcs WEXIT2                      ; write-protected
    jsr WRITE16
    bcs WEXIT2
    inc NSECT
    lda NSECT
    cmp #$10
    bcc WSECT
;; Checks the track just written: the first address field to pass must be sector 0's, and all 16 sectors must
;; read correctly within about 48 tries.
;;
;; Writing ended just after sector 15's data field. After waiting 50 cycles for each of NSYNC, it reads the next
;; address field. If that is not sector 0, the gaps are shortened, NSYNC cut by 1, or by 2 while it is above 16,
;; and the track is rewritten; below 5 the format fails. Otherwise it reads sectors, marking each in FOUND,
;; until all 16 have been read. After track 0 checks, NSYNC is cut by 2 if it is still 16 or more.
;;
;; To rewrite a track, it waits for sector 15 to pass and branches back to WTRACK16, so the new sector 0 starts
;; just after the old sector 15's data field.
;; In:    X = slot * 16, TRK, NSYNC
;; Out:   carry = clear if the track checked
;; Errors: carry set if it did not and could not be rewritten
VTRACK:
    ldy #$F
    sty NSECT                       ; sectors still to find, less 1
    lda #$30
    sta RETRYCNT
CLRFOUND:
    sta a:FOUND,y                   ; $30: not found yet
    dey
    bpl CLRFOUND
; 50 cycles for each of NSYNC: three calls to an RTS take 36.
    ldy NSYNC
S0DELAY:
    jsr WEXIT2
    jsr WEXIT2
    jsr WEXIT2
    pha
    pla
    nop
    dey
    bne S0DELAY
    jsr RDADR16
    bcs S15LOC
    lda SECT
    beq VDATA                       ; sector 0 first: check the data
    lda #$10
    cmp NSYNC                       ; carry set if NSYNC is 16 or less...
    lda NSYNC
    sbc #1                          ; ...subtracting 1, else 2
    sta NSYNC
    cmp #5
    bcs S15LOC
VERR:
    sec                             ; gaps this short: give up
    rts
VSECT:
    jsr RDADR16
    bcs VERR1
VDATA:
    jsr READ16
    bcc SECTOK
VERR1:
    dec RETRYCNT
    bne VSECT
; Find sector 15 and read its data field, then rewrite the track from there. Up to RETRYCNT tries: 256 when the
; check above ran out of its own.
S15LOC:
    jsr RDADR16
    bcs NOTS15
    lda SECT
    cmp #$F
    bne NOTS15
    jsr READ16
    bcc WTRACK16
NOTS15:
    dec RETRYCNT
    bne S15LOC
    sec
WEXIT2:
    rts
; A sector read correctly. A sector read a second time counts as a failed try.
SECTOK:
    ldy SECT
    lda a:FOUND,y
    bmi VERR1                       ; found already
    lda #$FF
    sta a:FOUND,y
    dec NSECT
    bpl VSECT
    lda TRK
    bne WEXIT1
    lda NSYNC
    cmp #$10
    bcc WEXIT2                      ; carry clear: success
    dec NSYNC
    dec NSYNC
WEXIT1:
    clc
    rts
;; The end of the relocator's range ASC2 to AEC2; FOUND and INTRLEAV hold no addresses.
;;
;; FOUND: one byte per sector while a track is checked, negative once the sector has been read.
AEC2:
FOUND:
.if YEAR = 1983
    .byte 0, 0, 0, 0
    .byte 0, 0, 0, 0
    .byte 0, 0, 0, 0
    .byte 0, 0, 0, 0
.else
    ; leftover: what the 1980 master holds here
    .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
.endif
.endif
;; The sector number on the disk (physical) for each sector number DOS asks for in IOB 05 (logical).
;;
;; The formatter numbers the sectors on a track 0 to 15 in order. Logical 0 and 15 keep their numbers; logical
;; sectors 14 down to 1 are physical 2, 4, ... 14, then 1, 3, ... 13: read in descending order, each comes two
;; physical sectors after the one before (three where the order wraps round), not right behind it.
INTRLEAV:
    .byte $00, $0D, $0B, $09
    .byte $07, $05, $03, $01
    .byte $0E, $0C, $0A, $08
    .byte $06, $04, $02, $0F
