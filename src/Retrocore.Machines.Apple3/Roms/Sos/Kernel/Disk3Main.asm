; DISK3, continued: the driver's entry point, which checks the request, selects the drive and reads blocks.

;; The Disk III driver's entry point for every request to .D1-.D4, named in each of its DIBs.
;;
;; It saves the caller's environment, locks out NMI and RESET, turns on the ROM and I/O space and turns off smooth
;; scrolling, and remembers whether the caller had interrupts masked, which the driver then respects throughout.
;; Then it checks the request. Read and write need a block number below 280 and a byte count that is a whole
;; number of 512-byte blocks ending at or before the disk's end; status takes only code 0, which reports write
;; protection; init sets the driver up once; repeat does the unit's last read or write again, with this call's
;; parameters. Any other request is refused.
;;
;; Before the transfer it switches to 1 MHz and selects and starts the drive (<UNITSEL>). If no motor seems to
;; turn, it seeks the head to track 0 and looks again: a motor that turns now means the disk was switched; one
;; that still does not means there is no drive. The seek also leaves the head where the file manager reads the
;; directory next. Reads go two sectors per block through
;; <SECTORIO>, adding 512 to the caller's count of bytes read after each block; writes continue at <WRITEREQ>.
;; In: D_COMMAND, D_UNITNUM, D_BUFL/D_BUFH, D_BYTES, D_BLOCK, D_BYTRD = the request (see Disk3.asm)
;; Out: carry = clear and A = 0 on success; an error leaves through SYSERR with its code
;; Uses: A, X, Y, the driver's page-zero work area
;; Errors: XREQCODE, XBADOP, XCTLCODE, XBLKNUM, XBYTECNT, XNODRIVE, XDISKSW, XIOERROR, XNOWRITE
;; See: <DIB1>, <EXIT>, <SECTORIO>, <UNITSEL>
MAIN:
    lda E_REG
    and #$FF-$20                        ; keep the caller's environment, all but the screen bit
    sta ESAVE
    .if .not TEST
    lda E_REG
    and #$FF-$10                        ; lock out NMI and RESET (a test build leaves them on)
    .endif
    ora #$03                            ; ROM and I/O space on
    sta E_REG
    lda NOSCROLL
    php
    pla
    ror a
    ror a
    ror a
    ror a                               ; four rotations through carry move the interrupt mask bit to bit 7
    sta IRQMASK
    lda D_COMMAND
    bmi BADCMD
    beq IOSETUP                         ; 0: read
    cmp #10
    bcs BADCMD
    cmp #9
    bne CMD1
    lda PREVUNIT                        ; 9: repeat, only for the same unit and only a read or write
    cmp D_UNITNUM
    bne BADOP
    lda PREVCMD
    beq RPTOK
    cmp #1
    bne BADOP
RPTOK:
    sta D_COMMAND                       ; the repeat becomes the earlier request
    cmp #0
    beq IOSETUP
CMD1:
    cmp #1
    bne CMD2
    jmp IOSETUP                         ; 1: write
CMD2:
    cmp #2
    bne CMD3
    lda D_STATCODE                      ; 2: status, which takes only code 0
    beq GOSTAT
    lda #XCTLCODE
    jmp EXIT
GOSTAT:
    jmp DRVSETUP
CMD3:
    cmp #8
    bne BADOP
    jmp INIT                            ; 8: init
BADOP:
    lda #XBADOP                         ; a request code this driver does not do
    jmp EXIT
BADCMD:
    lda #XREQCODE                       ; a request code beyond any driver's
    jmp EXIT
IOSETUP:
    lda D_BLOCK+1                       ; the block must be below 280
    beq CHKBYTE
    cmp #2
    bcs BADBLOCK
    lda D_BLOCK
    cmp #280-256
    bcc CHKBYTE
BADBLOCK:
    lda #XBLKNUM
    jmp EXIT
CHKBYTE:
    lda D_BYTES                         ; the count must be a multiple of 512
    bne BADCOUNT
    lda D_BYTES+1
    lsr a
    bcs BADCOUNT
    sta BLKCOUNT
    lda BLKCOUNT                        ; and the last block must not pass the disk's end
    clc
    adc D_BLOCK
    ldx D_BLOCK+1
    bne BLKG255
    bcc DRVSETUP
    bcs CHKLO
BLKG255:
    bcs BADCOUNT
CHKLO:
    cmp #280-256+1
    bcc DRVSETUP
BADCOUNT:
    lda #XBYTECNT
    jmp EXIT
DRVSETUP:
    lda D_COMMAND                       ; remember the request for a later repeat
    sta PREVCMD
    lda D_UNITNUM
    sta PREVUNIT
    lda E_REG
    ora #$80                            ; 1 MHz from here on, for the disk's timing
    sta E_REG
    jsr UNITSEL
    jsr CHKDRV
    bne DOIO                            ; the motor turns
    ldx D_UNITNUM
    inc DRVTRACK,x                      ; pretend the head is two tracks out, so the seek to 0 really steps
    inc DRVTRACK,x
    lda #0
    jsr MYSEEK
    jsr CHKDRV
    bne DSWITCH                         ; stepping started it: a disk was switched in
    lda #0
    ldy D_UNITNUM
    sta DRIVESEL,y                      ; still nothing: no drive, so it is no longer selected
    lda #XNODRIVE
    jmp EXIT
DSWITCH:
    lda #XDISKSW
    jmp EXIT
DOIO:
    lda D_BUFL                          ; copy the buffer and block to the work area
    sta BUFTEMP
    lda D_BUFH
    sta BUFTEMP+1
    lda $1400+D_BUFH                    ; the buffer's extension byte, in SXPAGE
    sta $1400+BUFTEMP+1
    lda D_BLOCK
    sta BLKTEMP
    lda D_BLOCK+1
    sta BLKTEMP+1
    lda D_COMMAND
    cmp #2
    bne DOIO2
    jmp STATUS
DOIO2:
    ldy BLKCOUNT
    beq READOK                          ; a count of 0 succeeds at once
    cmp #0
    beq READREQ
    jmp WRITEREQ
READREQ:
    lda #0                              ; no bytes read yet
    ldy #0
    sta (D_BYTRD),y
    iny
    sta (D_BYTRD),y
READREQ2:
    jsr BLK2SECT
    jsr SECTORIO                        ; the block's first sector
    bcs READERR
    inc SECTOR
    inc SECTOR
    inc BUF+1
    jsr SECTORIO                        ; and its second, two sectors on
    bcs READERR
    ldy #1
    lda (D_BYTRD),y                     ; 512 more bytes read
    clc
    adc #2
    sta (D_BYTRD),y
    jsr MOREBLKS
    bne READREQ2
READOK:
    lda #0
    jmp EXIT
READERR:
    jmp EXIT
    .include "Disk3Wrt.asm"
