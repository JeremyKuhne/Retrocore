;; DOS 3.2 RWTS: READ OR WRITE A TRACK AND SECTOR
;;
;; RWTS, "read or write a track and sector", is the routine the rest of DOS calls for every disk access. The
;; caller describes the request in an IOB (input/output control block) and passes its address in A and Y. RWTS
;; starts the drive: it waits for another slot's drive to stop if the slot has changed, checks whether the
;; motor is already turning, turns it on, selects the drive, moves the head to the track and, if the motor was
;; off, waits for it to come up to speed. Then it reads address fields until it finds the sector, and reads or
;; writes its data field, or it formats the disk (Formatter32.asm). RWTS runs at $BD00-$BE9B where DOS runs. The
;; file manager, and programs using the vector at $03D9, call it through DISKIO (BootLoader32.asm), which disables
;; interrupts for the call; DOS's own IOB is at $B7E8 and its DCT at $B7FB.
;;
;; This is DOS 3.3's RWTS (its Rwts1.asm and Rwts2.asm) as it was before DOS 3.3 changed it: the names are DOS
;; 3.3's where the code is the same. DOS 3.2 differs in a few places. It reads the sector number the IOB gives
;; as the number on the disk, with no translation. It checks once, not eight times, whether the motor is
;; turning; it reads the motor's start-up count from both of the DCT's bytes; it recalibrates only once; and
;; its formatter is part of RWTS rather than a module of its own.
;;
;; The IOB, as RWTS uses it (offsets in hex):
;;
;; - 01: the slot times 16, such as $60 for slot 6.
;; - 02: the drive, 1 or 2.
;; - 03: the volume expected; 0 accepts any. For FORMAT, the volume to write.
;; - 04: the track, 0 to 34.
;; - 05: the sector, 0 to 12, as it is numbered on the disk.
;; - 06-07: the address of the DCT.
;; - 08-09: the address of the 256-byte buffer.
;; - 0C: the command: 0 seeks only, 1 reads, 2 writes, 4 formats.
;; - 0D: the return code RWTS stores: $10 write-protected, $20 wrong volume, $40 drive error or a format that
;;   failed, $80 the sector couldn't be found.
;; - 0E: the volume found on the disk, stored by RWTS.
;; - 0F, 10: the slot times 16 and the drive of the last access, which RWTS reads and updates.
;;
;; Byte 00 (the IOB's type, 1) and 0A-0B (a byte count) are not read by this RWTS.
;;
;; The DCT (device characteristics table) describes the drive. RWTS reads three of its four bytes: byte 01,
;; whose bit 0 set means each track is two half-track steps (1 for the Disk II), and bytes 02 and 03, the
;; motor's start-up count ($D8EF for the Disk II). Byte 00, the device type, 0, is not read.
;;
;; Several values live in screen holes, at the address given plus the slot (DRV1TRK, DRV2TRK) or at slot 0's
;; byte (the counters); see RwtsEquates.asm.

;; The start of the relocator's range ASC2 to AEC2: RWTS, the formatter and the patches after it ($BD00-$BFFE).
ASC2:

;; Inherit: <Dos33:MOTOROFF>
MOTOROFF = $C088

;; Inherit: <Dos33:MOTORON>
MOTORON = $C089

;; Inherit: <Dos33:DRV1EN>
DRV1EN = $C08A

;; Inherit: <Dos33:DRV2EN>
;; DOS 3.2's RWTS reads <DRV1EN> first and then this one to select drive 2.
DRV2EN = $C08B

DRV1TRK = $478                      ;; plus the slot: the half-track drive 1 of that slot's card is on
DRV2TRK = $4F8                      ;; plus the slot: the half-track drive 2 is on

;; Inherit: <Dos33:IOBPL>
IOBPL = $48

;; Inherit: <Dos33:IOBPH>
IOBPH = $49

SLOT = $5F8                         ;; slot * 16 for this call

;; Inherit: <Dos33:PTRSDEST>
PTRSDEST = $3C

;; Inherit: <Dos33:DEVCTBL>
DEVCTBL = PTRSDEST

;; Inherit: <Dos33:DRIVNO>
DRIVNO = $35

;; The motor-on count, <MONTIMEL> and <MONTIMEH>: it counts up to 0 in steps of 100 microseconds.
;;
;; DOS 3.2's <RWTS> sets both bytes from DCT bytes 02-03 ($D8EF for the Disk II) before it seeks. If the motor
;; was off, it then counts the rest up to 0 itself (<MOTOF>); <MSWAIT>, called while seeking, has already added
;; the seek's time.
;; See: <MONTIMEL>, <MONTIMEH>, <MSWAIT>, <DEVCTBL>
MONTIME = $46

;; The sector number in the address field just read, <CSSTV>'s second byte.
;;
;; DOS 3.2's RWTS compares it with IOB byte 05 as it is, since its sector numbers are the ones on the disk.
;; See: <CSSTV>, <TRACK>, <VOLUME>
SECT = CSSTV+1

;; Inherit: <Dos33:TRACK>
;; DOS 3.2's <MYSEEK> also borrows it for the half-track it seeks to.
TRACK = CSSTV+2

;; Inherit: <Dos33:VOLUME>
VOLUME = CSSTV+3

RECALCNT = $4F8                     ;; recalibrations left (slot 0's DRV2TRK byte)
RETRYCNT = $578                     ;; address fields, and seeks, left before giving up on the track

;; Reads, writes, seeks or formats as the IOB at A and Y says.
;;
;; If the slot differs from the last call's, it first waits for the old slot's drive to stop: the data latch
;; changes while a disk turns, so it waits until eight reads in a row see the same value. Then the same test,
;; once, on this slot tells whether its motor is already on; the answer stays on the stack, in the Z flag, until
;; after the seek, and a change of drive counts as off. A motor that was off gets its start-up time: MONTIME
;; starts at the DCT's count and counts up to zero, and the time SEEK spends counts toward it. It also uses the
;; zero page and screen-hole bytes RWTS's routines use.
;; In:    A = the IOB's address's high byte, Y = its low byte
;; Out:   carry = clear on success, with IOB 0D = A (see ALLDONE) and, after a read, the sector in the IOB's buffer
;; Errors: carry set, IOB 0D = the error: IBWPER, IBVMME, IBDERR or IBRERR (BootLoader32.asm)
;; Uses:  A, X, Y
RWTS:
    sty IOBPL
    sta IOBPH
    ldy #1
    lda (IOBPL),y                   ; the slot
    tax
    sty RECALCNT                    ; one recalibration
    ldy #$0F
    cmp (IOBPL),y                   ; the last call's slot
    beq SAMESLOT
    txa
    pha
    lda (IOBPL),y
    tax                             ; X = the old slot, to watch
    pla
    pha
    sta (IOBPL),y                   ; the new slot becomes the last one
    lda Q7L,x
STILLON:
    ldy #$08
    lda Q6L,x
NOTSURE:
    cmp Q6L,x
    bne STILLON                     ; it changed: still turning
    dey
    bne NOTSURE
    pla
    tax

; Is this slot's motor on? The latch is read, and read again a few cycles later: a turning disk changes it.
SAMESLOT:
    lda Q7L,x
    lda Q6L,x
    lda Q6L,x
    pha
    pla
    stx SLOT
    cmp Q6L,x
    php                             ; Z set if the motor is off
    lda MOTORON,x

; IOB bytes 06-09 to PTRSDEST: the DCT's address, then the buffer's in BUF.
    ldy #6
PTRMOV:
    lda (IOBPL),y
    sta PTRSDEST-6,y
    iny
    cpy #$0A
    bne PTRMOV

; If the drive isn't the last call's, it is recorded, and the motor counts as off.
    ldy #2
    lda (IOBPL),y                   ; the drive
    ldy #$10
    cmp (IOBPL),y
    beq OK
    sta (IOBPL),y
    plp
    ldy #$00                        ; Z set: off
    php
OK:
    ror a                           ; drive 1 sets the carry
    lda DRV1EN,x
    bcs DRVSEL
    lda DRV2EN,x
DRVSEL:
    ror DRIVNO                      ; bit 7: drive 1

; The start-up count, from DCT bytes 2 and 3, then the seek to the IOB's track.
    ldy #2
    lda (DEVCTBL),y
    sta MONTIME
    iny
    lda (DEVCTBL),y
    sta MONTIME+1
    iny
    lda (IOBPL),y                   ; the track
    jsr MYSEEK
    plp
    bne TRYTRK                      ; the motor was on

; The motor was off: waits for MONTIME to count up to 0, 100 microseconds a step.
MOTOF:
    ldy #$12
CONWAIT:
    dey
    bne CONWAIT
    inc MONTIME
    bne MOTOF
    inc MONTIME+1
    bne MOTOF

; The command: 0 seeks only, 4 formats, odd reads and even writes. A write's sector is prepared first, while
; nothing is waiting; the carry, read or write, waits on the stack.
TRYTRK:
    ldy #$0C
    lda (IOBPL),y
    beq GALLDONE
    cmp #$04
    beq FORMDSK
    ror a
    php
    bcs TRYTRK2
    jsr PRENIB13
TRYTRK2:
    ldy #$30                        ; 48 address fields
    sty RETRYCNT
TRYADR:
    ldx SLOT
    jsr RDADR13
    bcc RDRIGHT
TRYADR2:
    dec RETRYCNT
    bpl TRYADR

; No good address field in 48 tries: recalibrates. SETTRK records the head at track 48 (half-track 96), so
; the seek to track 0 steps out far enough to stop against track 0 whatever the head's real place, then it
; seeks the track again. The second time this happens, it's a drive error.
RECAL:
    lda CURTRK
    pha
    lda #$60
    jsr SETTRK
    dec RECALCNT
    bne DRVERR
    lda #$00
    jsr MYSEEK
    pla
RESEEK:
    jsr MYSEEK
    jmp TRYTRK2

; An address field: is the head on the right track? If not, the drive's record of the track is corrected to
; the one read, and it seeks again, counting the seeks against RETRYCNT too.
RDRIGHT:
    ldy TRACK
    cpy CURTRK
    beq RTTRK
    lda CURTRK
    pha
    tya
    jsr SETTRK
    pla
    dec RETRYCNT
    bpl RESEEK
    bmi TRYADR2                     ; always: on to recalibrating
DRVERR:
    pla
    lda #IBDERR
JMPTO1:
    plp
    jmp HNDLERR
GALLDONE:
    beq ALLDONE                     ; always
FORMDSK:
    ldy #3
    lda (IOBPL),y
    sta NVOL                        ; the volume to write
    jmp DSKFORM

; The right track. The volume found goes to IOB 0E; it must match the one asked for, unless that is 0.
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
    bne JMPTO1

; The right sector? If not, on to the next address field; after RETRYCNT of them, a read error.
CORRECTVOL:
    ldy #5
    lda SECT
    cmp (IOBPL),y
    beq GOTSECT
    dec RETRYCNT
    bpl TRYADR
    lda #IBRERR
    bne JMPTO1

; The sector is under the head: reads or writes its data field.
GOTSECT:
    plp
    bcc WRIT
    jsr READ13
    php
    bcs TRYADR2                     ; a bad read: tries again, the carry on the stack again
    plp
    jsr POSTNB13
    ldx SLOT

;; RWTS's exits: store A in IOB 0D as the return code, turn the motor off and return, with the carry clear
;; (ALLDONE) or set (HNDLERR).
;;
;; `.byte $24` is the opcode of BIT zero page: with the SEC that follows as its operand, it reads byte $38 and
;; skips the SEC, changing only N, V and Z. ALLDONE stores whatever A holds, which is 0 only for a seek: after a
;; read it is the sector's last byte, after a write a byte read from the card. The file manager reads IOB 0D
;; only when the carry is set.
;; In:    A = the return code, X = slot * 16
;; Out:   carry = clear at ALLDONE, set at HNDLERR
;; Uses:  A, Y
;; Entry: HNDLERR = the error exit
ALLDONE:
    clc
    .byte $24                       ; BIT $38: skips the SEC
HNDLERR:
    sec
    ldy #$0D
    sta (IOBPL),y
    lda MOTOROFF,x
    rts
WRIT:
    jsr WRITE13
    bcc ALLDONE
    lda #IBWPER
    bcs HNDLERR                     ; always

;; Seeks the drive in DRIVNO to track A, for a drive whose DCT says a track is one step or two.
;;
;; With two half-tracks to a track (the Disk II), the track is doubled for SEEK and CURTRK halved afterwards,
;; so that RWTS can compare it with the track an address field gives. It also uses SEEK's variables.
;; In:    A = the track, X = slot * 16, DEVCTBL, DRIVNO
;; Out:   CURTRK = the track
;; Uses:  A, Y
;; Keeps: X
MYSEEK:
    pha
    ldy #$01
    lda (DEVCTBL),y
    ror a                           ; bit 0 of DCT byte 1: two steps a track
    pla
    bcc MYSEEK2
    asl a
    jsr MYSEEK2
    lsr CURTRK
    rts

;; Seeks to half-track A, keeping a record of each drive's place. All four phases go off first. The drive's
;; record, DRV1TRK or DRV2TRK plus the slot, becomes CURTRK for SEEK and then the new half-track.
;;
;; It also uses SEEK's variables.
;; In:    A = the half-track, X = slot * 16, DRIVNO
;; Uses:  A, Y, TRACK
;; Keeps: X
MYSEEK2:
    sta TRACK                       ; held in the address field's byte while the phases go off
    lda PHASEOFF,x
    lda PHASEOFF+2,x
    lda PHASEOFF+4,x
    lda PHASEOFF+6,x
    jsr XTOY
    lda DRV1TRK,y
    bit DRIVNO
    bmi WASD0
    lda DRV2TRK,y
WASD0:
    sta CURTRK
    lda TRACK
    bit DRIVNO
    bmi ISDRV1
    sta DRV2TRK,y
    bpl GOSEEK                      ; always
ISDRV1:
    sta DRV1TRK,y
GOSEEK:
    jmp SEEK

;; Gives the slot number: slot * 16 shifted right four places.
;; In:    X = slot * 16
;; Out:   A = Y = the slot
;; Keeps: X
XTOY:
    txa
    lsr a
    lsr a
    lsr a
    lsr a
    tay
    rts

;; Records the drive in the IOB as being on track A, without moving it: the half-track, track * 2, goes in its
;; DRV1TRK or DRV2TRK byte.
;; In:    A = the track, X = slot * 16
;; Out:   DRIVNO = the IOB's drive
;; Uses:  A, Y
;; Keeps: X
SETTRK:
    pha
    ldy #$02
    lda (IOBPL),y
    ror a
    ror DRIVNO
    jsr XTOY
    pla
    asl a
    bit DRIVNO
    bmi ONDRV1
    sta DRV2TRK,y
    bpl SETRTS                      ; always
ONDRV1:
    sta DRV1TRK,y
SETRTS:
    rts
