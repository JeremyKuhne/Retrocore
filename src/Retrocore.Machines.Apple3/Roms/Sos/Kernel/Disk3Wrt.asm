; DISK3, continued: writes, the status and init requests, and the exit every request leaves by.

;; Writes the request's blocks, two sectors each, for <MAIN>.
;;
;; Each sector is encoded (PRENIB) at 2 MHz, and <SECTORIO> writes it at 1 MHz.
;; In: BLKTEMP, BUFTEMP, BLKCOUNT = the first block, its buffer and the block count, set by MAIN
;; Out: A = 0 or the error code, passed to <EXIT>
;; See: <MAIN>, <SECTORIO>, <BLK2SECT>
WRITEREQ:
    jsr BLK2SECT
    lda E_REG
    and #$7F                            ; 2 MHz to encode the sector
    sta E_REG
    jsr PRENIB
    jsr SECTORIO
    bcs WRITERR
    inc SECTOR                          ; the block's second sector, two on
    inc SECTOR
    inc BUF+1
    lda E_REG
    and #$7F
    sta E_REG
    jsr PRENIB
    jsr SECTORIO
    bcs WRITERR
    jsr MOREBLKS
    bne WRITEREQ
    lda #0
    jmp EXIT
WRITERR:
    jmp EXIT

;; Does status request 0 for <MAIN>: reports whether the disk is write-protected.
;;
;; It stores $02 in the first byte of the caller's status list for a write-protected disk, or 0.
;; In: D_STATBUF = the status list's address, the drive selected and running
;; Out: A = 0, passed to <EXIT>
;; See: <MAIN>
STATUS:
    ldx #$60
    lda Q6H,x                           ; sense write protection
    lda Q7L,x
    asl a                               ; carry = the write-protect bit
    lda Q6L,x                           ; back to read mode
    lda #0
    rol a
    rol a                               ; carry into bit 1: $02 when protected
    ldy #0
    sta (D_STATBUF),y
    lda #0
    jmp EXIT

;; Does the init request for <MAIN>: sets the driver up the first time it is called, and does nothing later.
;;
;; It points the ROM routines at slot 6 ($60 in IBSLOT) and clears the drive tables. In SOS it then takes over the
;; boot loader's use of .D1: .D1 becomes the selected drive, at the track where the boot ROM's routines left it
;; (their CURTRK in page 3, the ROM's zero page), and if its motor still turns it counts as up to speed for reads.
;; A test build skips that. A build for the first boot ROM revision (REV0ROM) also tells the two ROMs apart by the
;; byte at $F1B9, where the later ROM's RDADR starts with LDY ($A0) and the first ROM's READ ends with RTS ($60),
;; and copies that ROM's addresses into JMPTAB; any other byte fails the init.
;; Out: carry = clear and A = 0, passed to <EXIT>; with REV0ROM, carry = set when the ROM is not known
;; Uses: A, X, Y
;; See: <MAIN>, <INITFLAG>, <DRIVESEL>, <UPTIME>, <DRVTRACK>
INIT:
    lda INITFLAG                        ; already done?
    bmi GOODINIT
    lda #$60
    sta IBSLOT
    lda #$FF
    sta INITFLAG
    lda #0
    sta PREVUNIT                        ; the boot loader just used .D1
    ldy #4
CLRDRVS:
    lda #0
    sta DRIVESEL-1,y
    sta UPTIME-1,y
    sta DRVTRACK-1,y
    dey
    bne CLRDRVS
    .if .not TEST
    lda E_REG
    ora #$80                            ; 1 MHz to look at the drive
    sta E_REG
    jsr CHKDRV
    beq INIT2                           ; .D1's motor has stopped
    lda #T200MS                         ; still turning: ready for reads
    sta UPTIME+0
INIT2:
    lda #1
    sta DRIVESEL+0
    lda $0300+CURTRK                    ; the boot ROM's track for .D1
    sta DRVTRACK+0
    .endif
    .if REV0ROM
    lda a:$F1B9
    cmp #$A0
    beq INITREV1
    cmp #$60
    bne INITERR
    ldy #0
    beq INITVECT
INITREV1:
    ldy #VSIZE
INITVECT:
    sty a:ROMREV
    ldx #VSIZE
MOVEVECT:
    lda a:REV0,y
    sta a:JMPTAB,y
    iny
    dex
    bne MOVEVECT
    .endif
GOODINIT:
    lda #0
    clc
    bcc EXIT
    .if REV0ROM
INITERR:
    sec                                 ; A is the unknown byte, which EXIT reports as the error
    .endif

;; Ends every request: counts the transfer's time, restores the caller's environment, and returns or reports an error.
;;
;; A read or write adds 50 milliseconds to each selected drive's motor time (<ADDTIME>) for the transfer itself. The
;; caller's environment comes back with the screen bit as it is now; interrupts are allowed again if the caller had
;; them, and the motors' turn-off delay starts. In SOS a nonzero code goes to SYSERR, which returns to the driver's
;; caller with carry set; a test build returns the code in A.
;; In: A = 0 or an error code, D_COMMAND = the request
;; Out: carry = clear and A = 0 on success
;; See: <MAIN>, <FIXIRQ>
EXIT:
    pha
    lda D_COMMAND
    cmp #2
    bcs EXIT2                           ; status and init take no transfer time
    lda #2                              ; two units of about 25 ms
    jsr ADDTIME
EXIT2:
    lda E_REG
    and #$20                            ; the screen bit as it is now
    ora ESAVE                           ; with the rest as the caller had it
    sta E_REG
    jsr FIXIRQ
    lda MOTOROFF                        ; the motor stops in about a second unless used again
    pla
    .if TEST
    rts
    .else
    bne GOERR
    clc
    rts
GOERR:
    jsr SYSERR
    .endif
    .include "Disk3Sio.asm"
