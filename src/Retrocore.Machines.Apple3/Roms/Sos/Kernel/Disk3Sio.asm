; DISK3, continued: reading or writing one sector, with its seeks, retries and recalibration, and finding a sector.

;; Reads or writes one sector of the selected drive, seeking, retrying and recalibrating as needed.
;;
;; It seeks to the sector's track unless the head is there already, first waiting 100 milliseconds when another
;; external drive was just stopped (<SEEKWAIT>). It waits out the rest of the motor's spin-up, then finds the sector
;; (<FINDSECT>) and reads it with the ROM's READ and decodes it with POSTNIB at 2 MHz, or writes it with WRITE (the
;; caller has encoded it). The system VIA's vertical-blanking interrupts are off while the sector moves, and other
;; interrupts are let in as the caller allows (<FIXIRQ>). An interrupt during the transfer retries the sector. After
;; 4 read errors (<R_IOERR>), or when the sector cannot be found, the head is recalibrated once (<R_RECAL>) and it
;; all starts again. While it runs, <E1908> is nonzero, which keeps the mouse
;; driver from interrupting.
;; In: TRACK, SECTOR = the sector, BUF = the buffer, D_COMMAND = 0 to read or 1 to write, D_UNITNUM = the drive,
;;   MONTIMEL/MONTIMEH = the spin-up time left, as <UNITSEL> set it
;; Out: carry = clear and A = 0 on success, carry = set and A = XIOERROR or XNOWRITE on an error, X = 0
;; Uses: A, X, Y, the driver's page-zero work area, VBLSAVE
;; See: <FINDSECT>, <RECAL>, <MYSEEK>, <MAIN>, <WRITEREQ>
SECTORIO:
    lda #R_RECAL
    sta RECALCNT
    nop                                 ; a spare byte
    sta E1908                           ; nonzero: the mouse driver must not interrupt now
    ldy D_UNITNUM
    lda TRACK
    cmp DRVTRACK,y
    beq SOUGHT                          ; already on the track
    lda SEEKWAIT
    beq GOSEEK
    lda #0
    sta SEEKWAIT
    lda #4                              ; wait 4 x 25 ms before stepping, and count it as motor time
    jsr ADDTIME
    tay
SEEKDEL:
    lda #0
    jsr MSWAIT
    dey
    bne SEEKDEL
GOSEEK:
    lda TRACK
    jsr MYSEEK
SOUGHT:
    lda IRQMASK                         ; the ROM routines respect the caller's interrupt mask
    sta IMASK
    lda #R_IRQ
    sta INTRTRY
    lda #R_IOERR
    sta RETRYCNT
MDELAY:
    lda MONTIMEH                        ; wait until the motor is up to speed
    bpl FINDIT
    lda #1
    jsr ADDTIME
    lda #0
    jsr MSWAIT
    jmp MDELAY
FINDIT:
    php
    sei
    lda E_IER
    and #$18                            ; the vertical-blanking interrupts that are on
    sta E_IER                           ; turn them off
    ora #$80
    sta VBLSAVE                         ; and keep the value that turns them back on
    plp
    jsr FINDSECT                        ; leaves interrupts masked when it finds the sector
    bcs TRYRECAL
    ldx #$60
    lda D_COMMAND
    bne SIOWRITE
    jsr READ
    jsr FIXIRQ
    lda VBLSAVE
    sta E_IER
    bcs BADIO                           ; an interrupt or a read error
    lda E_REG
    and #$7F                            ; 2 MHz to decode
    sta E_REG
    jsr POSTNIB
    bcs IORETRY                         ; a bad checksum
    jmp SIOGOOD
SIOWRITE:
    jsr WRITE
    jsr FIXIRQ
    lda VBLSAVE
    sta E_IER
    bcc SIOGOOD
    bvc SIOWPROT                        ; overflow clear: write-protected; set: an interrupt
BADIO:
    .if .not REV0ROM
    bvs FINDIT                          ; the ROM counted the interrupt; try the sector again
    .else
    bvc IORETRY                         ; the first ROM leaves the interrupt count to the driver
    lda a:ROMREV
    bne FINDIT
    lda INTRTRY
    bpl BADIO2
    sta IMASK                           ; out of interrupts: keep them masked from now on
BADIO2:
    dec INTRTRY
    jmp FINDIT
    .endif
IORETRY:
    dec RETRYCNT
    bne FINDIT
TRYRECAL:
    lda VBLSAVE
    sta E_IER
    dec RECALCNT
    bmi SIOERR                          ; recalibrated already: give up
    jsr RECAL
    ldy D_UNITNUM
    lda TRACK
    cmp DRVTRACK,y
    bne NOTSAME
    jmp SOUGHT
NOTSAME:
    jmp GOSEEK
SIOERR:
    lda #XIOERROR
    sec
    bcs SIORET
SIOWPROT:
    lda #XNOWRITE
    sec
    bcs SIORET
SIOGOOD:
    lda #0
    clc
SIORET:
    ldx #0
    stx E1908                           ; the mouse driver may interrupt again
    rts

;; Reads address fields until it finds the sector in <SECTOR> on the track in <TRACK>.
;;
;; It reads up to 48 address fields, three revolutions (<R_FIND>). An address field from another track ends the
;; search at once, so that the caller recalibrates. The first time it sees another sector it adds the time the wanted
;; one will take to come round, 25 milliseconds for each two sectors, to the motor times (<ADDTIME>). Between tries
;; it waits about a millisecond, long enough for the data field's mark to pass: the ROM's RDADR, called sooner, would
;; take that mark for a bad address field. RDADR leaves the volume number in MONTIMEH, which shares its byte, so
;; that byte is cleared on the way out.
;; Out: carry = clear when found, with interrupts masked; carry = set when not, with interrupts as the caller allows
;; Uses: A, X, Y, TEMP, RETRYADR, CSSTV, MONTIMEH
;; See: <SECTORIO>, <RECAL>
FINDSECT:
    lda #R_FIND*16
    sta RETRYADR
    lsr TEMP                            ; bit 7 clear: the wait not yet counted
FINDSEC2:
    ldx #$60
    jsr RDADR
    bcs RDADERR
    lda TRACK
    cmp CSSTV+2
    bne FINDERR                         ; the wrong track
    lda SECTOR
    cmp CSSTV+1
    beq FINDGOOD
    lda TEMP
    bmi RDADERR
    lda SECTOR
    sec
    ror TEMP                            ; bit 7 set: counted
    sbc CSSTV+1
    and #$0F                            ; sectors to go, around the track
    lsr a
    jsr ADDTIME
RDADERR:
    jsr FIXIRQ
    dec RETRYADR
    beq FINDERR
    ldy #200                            ; about 1 ms, past the data mark
ADRDELAY:
    dey
    bne ADRDELAY
    jmp FINDSEC2
FINDGOOD:
    lda #0
    sta MONTIMEH                        ; clear the volume number out of the motor time
    clc
    rts
FINDERR:
    jsr FIXIRQ
    lda #0
    sta MONTIMEH
    sec
    rts
    .include "Disk3USel.asm"
