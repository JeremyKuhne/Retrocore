;; DOS 3.3 RWTS: READ OR WRITE A TRACK AND SECTOR, PART TWO (RWTSTWO)
;;
;; The rest of RWTS, after Rwts1.asm has started the drive and moved the head: it carries out the IOB's command.
;; For a read or write it reads address fields until it finds the sector, checking that the head is on the
;; right track and the disk has the right volume, then reads or writes the data field behind it. When it cannot
;; find the sector it moves the head again, and as a last resort recalibrates, driving the head out to track 0
;; to find out where it is. It ends by storing the return code in the IOB and turning the motor off. The helpers
;; after it (MYSEEK, XTOY, SETTRK) keep the position of each drive's head in the screen holes. Runs at
;; $BDAB-$BEAE where DOS runs. Formatting is in Formatter.asm.

;; Carries out the IOB's command once the head is on the track: seek only, read, write or format.
;;
;; For a write the sector is split into six-bit values first, as there is no time for it between the address
;; field and the data field. Then RWTS reads address fields, at most 49 tries for the track, counting failed
;; reads, other sectors and failed data reads alike. An address field from the wrong track means the head is not
;; where RWTS thought: it records where the head really is and seeks again, up to MAXSEEKS - 1 times; after that, or
;; when the tries run out, it recalibrates, once.
;;
;; The flags pushed after reading the command (carry set to read, clear to write) stay on the stack until the
;; sector is found; GOTSECT pulls them. Its results are as for RWTS.
;; In:    X = slot * 16, the IOB as for RWTS, the drive running on the track
TRYTRK:
    ldy #$0C
    lda (IOBPL),y                   ; IOB 0C: the command
    beq GALLDONE                    ; 0: seek only, done
    cmp #$04
    beq FORMDSK
    ror a                           ; bit 0 into the carry: 1 reads, 2 writes
    php
    bcs TRYTRK2
.if DIAGMODE
    ldy #TC7
    sty TL7
.endif
    jsr PRENIB16                    ; writing: split the caller's sector into NBUF1 and NBUF2 now
.if DIAGMODE
    ldy #SP
    sty TL7
.endif
TRYTRK2:
    ldy #$30
    sty RETRYCNT
TRYADR:
    ldx SLOT
.if DIAGMODE
    lda #TC4
    sta TL4
    lda #SP
    sta TL6
.endif
    jsr RDADR16
.if DIAGMODE
    lda #SP
    sta TL4
.endif
    bcc RDRIGHT
.if DIAGMODE
    lda #TC6
    sta TL6
.endif
TRYADR2:
    dec RETRYCNT
    bpl TRYADR
; Out of tries: recalibrate. Pretend the head is at half-track $C0, more than the disk has, and seek to track 0:
; the head steps out until it stops against track 0, wherever it was. Then seek to the track again.
RECAL:
    lda CURTRK
    pha                             ; the track wanted
    lda #$60
    jsr SETTRK
    dec RECALCNT
    beq DRVERR                      ; recalibrated once already
    lda #MAXSEEKS
    sta SEEKCNT
    lda #$00
    jsr MYSEEK
    pla
RESEEK:
    jsr MYSEEK
    jmp TRYTRK2
; An address field was read: is it from the track wanted? If not, note where the head really is and seek again.
RDRIGHT:
    ldy TRACK
    cpy CURTRK
    beq RTTRK
    lda CURTRK
    pha                             ; the track wanted
    tya
    jsr SETTRK                      ; the track the head is really on
    pla
    dec SEEKCNT
    bne RESEEK
    beq RECAL                       ; always
DRVERR:
    pla                             ; drop the track wanted
    lda #IBDERR
JMPTO1:
    plp                             ; drop the read/write flags
    jmp HNDLERR
GALLDONE:
    beq ALLDONE                     ; always: the command was 0
FORMDSK:
    jmp DSKFORM
; The right track. Store the volume found in IOB 0E, and check it against IOB 03 unless that is 0.
RTTRK:
    ldy #3
    lda (IOBPL),y
    pha
    lda VOLUME
    ldy #$0E
    sta (IOBPL),y
    pla
    beq CORRECTVOL
    cmp VOLUME
    beq CORRECTVOL
    lda #IBVMME
    bne JMPTO1                      ; always
; Is it the sector wanted? IOB 05 is DOS's sector number; INTRLEAV gives the number in the address field.
CORRECTVOL:
    ldy #5
    lda (IOBPL),y
    tay
    lda a:INTRLEAV,y
    cmp SECT
; The diagnostic build counts the wrong sectors that pass, once a first sector has been found.
.if DIAGMODE
    beq GOTSECT
    lda #TC5
    sta TL5
    lda SCOUNT
    beq NOLAT
    inc LCOUNT
NOLAT:
    jmp TRYADR2
.else
    bne TRYADR2
.endif
; Found: read or write its data field.
GOTSECT:
.if DIAGMODE
    lda #SP
    sta TL5
    inc SCOUNT
.endif
    plp                             ; carry set: read
    bcc WRIT
.if DIAGMODE
    lda #TC9
    sta TL9
    lda #SP
    sta TL10
.endif
    jsr READ16
.if DIAGMODE
    lda #SP
    sta TL9
.endif
; Push READ16's flags: on an error the carry is set, which says "read" again when GOTSECT pulls them next time.
    php
.if DIAGMODE
    bcc GOODREAD
    lda #TC10
    sta TL10
    jmp TRYADR2
GOODREAD:
.else
    bcs TRYADR2
.endif
    plp
    ldx #0
    stx T0                          ; all 256 bytes
.if DIAGMODE
    lda #TC11
    sta TL11
.endif
    jsr POSTNB16
.if DIAGMODE
    lda #SP
    sta TL11
.endif
    ldx SLOT
;; RWTS's exits: store A in IOB 0D as the return code, turn the motor off and return, with the carry clear
;; (ALLDONE) or set (HNDLERR).
;;
;; `.byte $24` is the opcode of BIT zero page: with the SEC that follows as its operand, it reads byte $38 and
;; skips the SEC, changing only N, V and Z. ALLDONE stores whatever A holds, which is 0 only for a seek: after a
;; read it is the sector's last byte, after a write a byte read from the card. The file manager reads IOB 0D
;; only when the carry is set.
;; In:    A = the return code, X = slot * 16, IOBPL/IOBPH = the IOB
;; Out:   carry = clear from ALLDONE, set from HNDLERR
;; Entry: HNDLERR = the error exit
ALLDONE:
    clc
    .byte $24                       ; BIT $38: skips the SEC
HNDLERR:
    sec
    ldy #$0D
    sta (IOBPL),y                   ; IOB 0D: the return code
    lda MOTOROFF,x
; The diagnostic build shows LCOUNT / SCOUNT, the average number of wrong sectors before the right one, as a
; hex digit, and clears the ^.
.if DIAGMODE
    lda LCOUNT
    ldy #0
DIVIDE:
    cmp SCOUNT
    bcc PRTLAT
    sbc SCOUNT
    iny
    bne DIVIDE
PRTLAT:
    tya
    and #$0F
    ora #$B0                        ; "0" to "9"...
    cmp #$BA
    bcc PRTL2
    adc #6                          ; ...or "A" to "F" (the carry adds 1)
PRTL2:
    sta TL12
    lda #SP
    sta TL1
.endif
    rts
; Write the data field, from NBUF1 and NBUF2. WRITE16 fails only on a write-protected disk.
WRIT:
.if DIAGMODE
    lda #TC8
    sta TL8
.endif
    jsr WRITE16
.if DIAGMODE
    lda #SP
    sta TL8
.endif
    bcc ALLDONE
    lda #IBWPER
    bcs HNDLERR                     ; always
;; Moves the head of the selected drive to track A, and records it as that drive's position.
;;
;; When bit 0 of DCT 01 is set, as for the Disk II, a track is two half-tracks: MYSEEK doubles A, seeks, and
;; halves CURTRK again, so that CURTRK is the track number. Otherwise A goes to SEEK as it is. It also uses what
;; SEEK uses.
;; In:    A = the track, X = slot * 16, DRIVNO = the drive, DEVCTBL = the DCT
;; Out:   CURTRK = the track, DRV1TRK or DRV2TRK + slot = its half-track
;; Uses:  A, Y, TRKN
;; Keeps: X
MYSEEK:
    pha
.if DIAGMODE
    lda #TC3
    sta TL3
.endif
    ldy #$01
    lda (DEVCTBL),y                 ; DCT 01
    ror a                           ; bit 0 into the carry
    pla
    bcc MYSEEK2
    asl a                           ; the track's half-track
    jsr MYSEEK2
    lsr CURTRK                      ; back to a track
.if DIAGMODE
    lda #SP
    sta TL3
.endif
    rts
;; Seeks the selected drive's head to half-track A from the position recorded for it, recording A as its new one.
;;
;; It also uses what SEEK uses.
;; In:    A = the half-track, X = slot * 16, DRIVNO = the drive
;; Out:   CURTRK = A, DRV1TRK or DRV2TRK + slot = A
;; Uses:  A, Y, TRKN
;; Keeps: X
MYSEEK2:
    sta TRKN
    jsr XTOY
    lda DRV1TRK,y
    bit DRIVNO
    bmi WASD0                       ; drive 1
    lda DRV2TRK,y
WASD0:
    sta CURTRK                      ; where the head is now
    lda TRKN
    bit DRIVNO
    bmi ISDRV1
    sta DRV2TRK,y                   ; where it will be
    bpl GOSEEK                      ; always
ISDRV1:
    sta DRV1TRK,y
GOSEEK:
    jmp SEEK
;; Turns slot * 16 in X into the slot number in Y.
;; In:    X = slot * 16
;; Out:   Y = A = the slot
;; Keeps: X
XTOY:
    txa
    lsr a
    lsr a
    lsr a
    lsr a
    tay
    rts
;; Records that the head of the drive in IOB 02 is on track A: stores A times 2, the half-track, in DRV1TRK or
;; DRV2TRK + slot.
;;
;; It also sets DRIVNO from IOB 02.
;; In:    A = the track, X = slot * 16, IOBPL/IOBPH = the IOB
;; Out:   DRIVNO = bit 7 set for drive 1
;; Uses:  A, Y
;; Keeps: X
;; Entry: SETTRK2 = stores A as it is, for the drive in DRIVNO, with Y = the slot
SETTRK:
    pha
    ldy #$02
    lda (IOBPL),y                   ; IOB 02: the drive
    ror a
    ror DRIVNO                      ; bit 0 of the drive number into bit 7: set for drive 1
    jsr XTOY
    pla
    asl a                           ; the half-track
SETTRK2:
    bit DRIVNO
    bmi ONDRV1
    sta DRV2TRK,y
    bpl SETRTS                      ; always
ONDRV1:
    sta DRV1TRK,y
SETRTS:
    rts
