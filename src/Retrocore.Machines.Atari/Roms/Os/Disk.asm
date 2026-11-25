;; THE RESIDENT DISK HANDLER
;;
;; DISKIV's initialization and DSKINV's handler, which turns the device control block a caller sets up (the drive,
;; the command, the buffer and the sector) into an SIO call, filling in the bus ID, the data direction, the byte
;; count and the timeout. It isn't a CIO handler: DOS's file manager and the disk boot call it directly.

; The commands the handler treats differently.

DISK_FORMAT = '!'                   ;; format the disk, returning the bad sectors' numbers
DISK_PUT_VERIFY = 'W'               ;; write a sector and read it back to check it
DISK_READ = 'R'                     ;; read a sector
DISK_STATUS = 'S'                   ;; read the drive's 4-byte status into DVSTAT

DISK_FORMAT_TIMEOUT = $A0           ;; DSKTIM's first value: 160 seconds, for a format
DISK_TIMEOUT = 7                    ;; the timeout for every command but a format, in seconds
DISK_SECTOR_SIZE = 128              ;; the bytes in a sector, and in the drive's answer to every command but a status
DISK_STATUS_SIZE = 4                ;; the bytes in a status, as DVSTAT holds them
DISK_STATUS_TIMEOUT = 2             ;; the offset in a status of the format timeout, in seconds
DISK_BAD_SECTORS_END = $FF          ;; both bytes of the word that ends a format's list of bad sectors

;; Initializes the disk handler, through DISKIV: sets the format timeout, DSKTIM, to 160 seconds.
;; Out: A = DISK_FORMAT_TIMEOUT
;; Keeps: X, Y
;; See: <DISK_HANDLER>
DISK_INIT:
    lda #DISK_FORMAT_TIMEOUT
    sta DSKTIM
    rts

;; Runs a disk command, through DSKINV: completes the device control block for the drive and calls SIO.
;;
;; The caller sets DUNIT, DCOMND, the buffer (DBUFLO/DBUFHI) and the sector (DAUX1/DAUX2). Every command but a write
;; with verify ('W') receives 128 bytes, so a plain write ('P') isn't supported. A status ('S') reads 4 bytes into
;; DVSTAT, whatever the buffer, and keeps the drive's format timeout from it in DSKTIM. A format ('!') waits DSKTIM
;; seconds, and afterwards DBYTLO/DBYTHI count the bytes of the list of bad sectors at the start of the buffer, the
;; words before the $FFFF that ends it. Every other command waits 7 seconds.
;; In: DUNIT = the drive (1-4), DCOMND = the command, DBUFLO/DBUFHI = the buffer, DAUX1/DAUX2 = the sector
;; Out: Y = the status, also in DSTATS, negative = set on an error
;; Uses: A, X, DDEVIC, DTIMLO, DBYTLO/DBYTHI, BUFADR, DVSTAT (status)
;; Errors: Y = SIO's status: BRKABT, or TIMOUT to DERROR
;; See: <DISK_INIT>, <DSKINV>, <SIOV>
DISK_HANDLER:
    lda #DISK_ID
    sta DDEVIC
    lda DSKTIM
    ldx DCOMND
    cpx #DISK_FORMAT
    beq DISK_HANDLER_1
    lda #DISK_TIMEOUT
DISK_HANDLER_1:
    sta DTIMLO
    ldx #DCB_RECEIVE
    ldy #DISK_SECTOR_SIZE
    lda DCOMND
    cmp #DISK_PUT_VERIFY
    bne DISK_HANDLER_2
    ldx #DCB_SEND
DISK_HANDLER_2:
    cmp #DISK_STATUS
    bne DISK_HANDLER_3
    lda #<DVSTAT                        ; a status always goes to DVSTAT
    sta DBUFLO
    lda #>DVSTAT
    sta DBUFHI
    ldy #DISK_STATUS_SIZE
DISK_HANDLER_3:
    stx DSTATS
    sty DBYTLO
    lda #$00
    sta DBYTHI
    jsr SIOV
    bpl DISK_HANDLER_STATUS
    rts                                 ; an error
DISK_HANDLER_STATUS:
    lda DCOMND
    cmp #DISK_STATUS
    bne DISK_HANDLER_FORMAT
    jsr DISK_POINT_BUFFER
    ldy #DISK_STATUS_TIMEOUT
    lda (BUFADR),y
    sta DSKTIM                          ; the drive's own format timeout
DISK_HANDLER_FORMAT:
    lda DCOMND
    cmp #DISK_FORMAT
    bne DISK_HANDLER_DONE
    jsr DISK_POINT_BUFFER
    ldy #$FE                            ; -2: the first pass steps to the first word
DISK_HANDLER_NEXT:
    iny
    iny
DISK_HANDLER_LOW:
    lda (BUFADR),y
    cmp #DISK_BAD_SECTORS_END
    bne DISK_HANDLER_NEXT               ; a sector number's low byte
    iny
    lda (BUFADR),y
    iny                                 ; the next word's low byte
    cmp #DISK_BAD_SECTORS_END
    bne DISK_HANDLER_LOW                ; $xxFF: a sector, not the end
    dey
    dey                                 ; the end word's offset: the list's length
    sty DBYTLO
    lda #$00
    sta DBYTHI
DISK_HANDLER_DONE:
    ldy DSTATS
    rts

;; Points BUFADR at the device control block's buffer.
;; Out: BUFADR = DBUFLO/DBUFHI
;; Uses: A
;; Keeps: X, Y
DISK_POINT_BUFFER:
    lda DBUFLO
    sta BUFADR
    lda DBUFHI
    sta BUFADR+1
    rts
