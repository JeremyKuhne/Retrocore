; DISK3, continued: helpers for motor sensing and timing, recalibration, seeking, block-to-sector conversion and
; interrupts.

;; Tells whether a Disk III motor is turning, by watching the controller's data latch for changes.
;;
;; A turning disk keeps changing the latch; a stopped one leaves it fixed. A loose input can make the latch flicker
;; now and then on a stopped drive, so it takes three passes in a row that each see a change among eight reads to
;; call the motor turning; any pass that sees eight equal reads calls it stopped.
;; Out: zero = clear when a motor is turning, set when none is
;; Uses: A, X
;; Keeps: Y
;; See: <UNITSEL>, <MAIN>
CHKDRV:
    ldx #3
CHKD1:
    lda Q6L+$60
    cmp Q6L+$60
    bne CHANGED
    cmp Q6L+$60
    bne CHANGED
    cmp Q6L+$60
    bne CHANGED
    cmp Q6L+$60
    bne CHANGED
    cmp Q6L+$60
    bne CHANGED
    cmp Q6L+$60
    bne CHANGED
    cmp Q6L+$60
    bne CHANGED
    rts                                 ; fixed for eight reads: stopped
CHANGED:
    dex
    bne CHKD1
    dex                                 ; X = $FF: zero clear
    rts

;; Adds time to the motor time of every selected drive, stopping at just over a second.
;;
;; Each unit is about 25 milliseconds, the high byte of the ROM's motor-on count. Once a time passes <T1SEC> the
;; motor is up to speed for anything, so the count stays at T1SEC+1.
;; In: A = the time to add, in units of about 25 ms
;; Out: Y = 0
;; Keeps: A, X
;; See: <UPTIME>, <DRIVESEL>, <MTIMES>
ADDTIME:
    pha
    ldy #4
ADD2:
    lda DRIVESEL-1,y
    beq ADD3
    pla
    pha
    clc
    adc UPTIME-1,y
    cmp #T1SEC+2
    bcc ADD2A
    lda #T1SEC+1
ADD2A:
    sta UPTIME-1,y
ADD3:
    dey
    bne ADD2
    pla
    rts

;; Recalibrates the selected drive's head: moves it back to track 0 without banging it against the stop more than
;; needed.
;;
;; It does this twice. Each time it reads an address field (two tries) to learn which track the head is on, and
;; seeks to track 0 from three tracks beyond it, so that it surely gets there. When no address field can be read
;; the head may be anywhere, even past the last track, so it seeks as if from track 48, which always brings it
;; back onto the disk; the second pass then reaches track 0 from where it is known. The motor-on count is cleared
;; first, so that the seek's time is counted in the motor times.
;; Uses: A, X, Y, DRVTRACK, MONTIMEL/MONTIMEH
;; See: <SECTORIO>, <MYSEEK>
RECAL:
    lda #2
RECAL1:
    pha
    ldx #$60
    jsr RDADR
    bcc RECAL2
    jsr RDADR
    bcc RECAL2
    lda #48                             ; lost: seek as if from track 48
    jmp RECAL3
RECAL2:
    lda CSSTV+2                         ; the track the head is on, plus three
    clc
    adc #3
RECAL3:
    ldy D_UNITNUM
    sta DRVTRACK,y
    jsr FIXIRQ
    lda #0
    sta MONTIMEH
    sta MONTIMEL
    jsr MYSEEK                          ; to track 0
    pla
    tay
    dey
    tya
    bne RECAL1
    rts

;; Seeks the drive used last to a track, for code outside the driver.
;;
;; BFMINIT2 uses it to step through tracks of the boot disk. The motor must be on, and the system at 1 MHz with the
;; ROM and I/O space on.
;; In: A = the track
;; Uses: A, X, Y, D_UNITNUM
;; See: <MYSEEK>
SEEKDSK3:
    ldy PREVUNIT
    sty D_UNITNUM
    jsr MYSEEK
    rts

;; Moves the request's drive's head to a track with the ROM's SEEK, and counts the seek's time as motor time.
;;
;; The drive's last track comes from <DRVTRACK>, in half-tracks for the ROM. The vertical-blanking interrupts are
;; off while the head moves: an interrupt that holds up the stepping can leave the head between tracks, and those
;; come often. Other interrupts are left as they were.
;; In: A = the track, D_UNITNUM = the drive, 1 MHz
;; Out: DRVTRACK,Y = the track
;; Uses: A, X, Y, TRKN, CURTRK, TEMP, VBLSAVE
;; See: <SEEKDSK3>, <RECAL>, <SECTORIO>, <ADDTIME>
MYSEEK:
    sta TRKN
    ldy D_UNITNUM
    lda DRVTRACK,y
    asl a                               ; half-tracks for the ROM's SEEK
    sta CURTRK
    ldx #$60
    lda MONTIMEH
    sta TEMP                            ; the motor count before the seek
    php
    sei
    lda E_IER
    and #$18                            ; the vertical-blanking interrupts that are on
    sta VBLSAVE
    sta E_IER                           ; turn them off
    plp
    lda TRKN
    sta DRVTRACK,y
    asl a
    jsr SEEK
    lda VBLSAVE
    ora #$80
    sta E_IER                           ; and back on
    lda MONTIMEH
    sec
    sbc TEMP                            ; the seek's time, in 25 ms units
    jsr ADDTIME
    rts

;; Works out the track and first sector of the block in <BLKTEMP>, and sets up <BUF> for it.
;;
;; A track holds eight blocks, so the track is the block divided by 8. The block's first sector is <SECTABLE>'s entry
;; for the block's position on the track and its second is two further on. When the buffer is addressed through a
;; bank pair (extension byte $80-$8E) at $8200 or above, the address is moved down $8000 into the next bank pair,
;; the same memory, so that the 512 bytes cannot run past $FFFF; extension byte $8F, which maps memory differently,
;; is left alone.
;; In: BLKTEMP = the block, BUFTEMP = its buffer (extension byte in SXPAGE)
;; Out: TRACK, SECTOR = the block's track and first sector, BUF = BUFTEMP, adjusted, with its extension byte
;; Uses: A, Y
;; See: <MAIN>, <WRITEREQ>, <MOREBLKS>
BLK2SECT:
    lda BLKTEMP+1
    ror a                               ; bit 8 of the block into carry
    lda BLKTEMP
    ror a
    lsr a
    lsr a
    sta TRACK
    lda BLKTEMP
    and #7
    tay
    lda SECTABLE,y
    sta SECTOR
    lda BUFTEMP+1
    ldy $1400+BUFTEMP+1
    cmp #$82
    bcc NOADJ
    cpy #$80
    bcc NOADJ                           ; not a bank pair
    cpy #$8F
    beq NOADJ
    and #$7F
    sta BUFTEMP+1
    inc $1400+BUFTEMP+1                 ; the next bank pair
NOADJ:
    lda BUFTEMP+1
    sta BUF+1
    lda BUFTEMP
    sta BUF
    lda $1400+BUFTEMP+1
    sta $1400+BUF+1
    rts
;; The sector each block on a track starts at, by the block's position on the track; its second sector is two on.
;;
;; The sector numbers are those in the address fields. Blocks 0-3 use the even sectors and blocks 4-7 the odd ones.
;; See: <BLK2SECT>
SECTABLE:
    .byte $00, $04, $08, $0C, $01, $05, $09, $0D

;; Moves on to the next block of a request: 512 bytes further in the buffer, the next block, one fewer to go.
;; Out: zero = set when no blocks are left
;; Keeps: A, X, Y
;; See: <MAIN>, <WRITEREQ>, <BLK2SECT>
MOREBLKS:
    inc BUFTEMP+1
    inc BUFTEMP+1
    inc BLKTEMP
    bne MORE2
    inc BLKTEMP+1
MORE2:
    dec BLKCOUNT
    rts

;; Allows interrupts again, unless the driver's caller had them masked.
;; Keeps: A, X, Y
;; See: <IRQMASK>, <EXIT>, <SECTORIO>
FIXIRQ:
    pha
    lda IRQMASK
    bmi FIXRET
    cli
FIXRET:
    pla
    rts
    .include "Disk3Data.asm"
