; ---------------------------------------------------------------------------------------------------------------------
; Block file manager: READ and WRITE.
;
; Both move bytes between the caller's buffer and the file's data block buffer, a block at a time, moving the mark
; with <RDPOSN> between blocks. A long read of a tree file skips the buffer and reads whole blocks straight into the
; caller's buffer. A write allocates the blocks its position lacks, growing a seed into a sapling and a sapling into a
; tree as the file passes 512 bytes and 128K.
; ---------------------------------------------------------------------------------------------------------------------

;; READ: reads bytes from an open file into the caller's buffer, up to the count, the end of file or a newline.
;;
;; A count reaching past the end of file is cut to end there; a read at the end of file is EOFERR, through <SYSERR>.
;; With newline mode on (<NEWLINE>), the read also stops after the newline character. In a tree file, once the data
;; buffer is used up and two or more whole blocks remain, blocks go straight into the caller's buffer: the first
;; through <RDPOSN>, the rest with the device's repeat command, while each is an allocated block of the same index.
;; A missing (sparse) block reads as zeros. The count read is returned even after an error.
;; In: FCBPTR = the file's FCB, C_OUTBUF = the buffer, C_BYTES = the count, C_OUTCNT = where the count read goes
;; Out: carry = set on an error, A = the error code, the count read at C_OUTCNT
;; Uses: X, Y
;; See: <WRITE>, <READPART>, <DREAD>, <RDPOSN>
READ:
    clc
    ldy #FCBATTR
    lda (FCBPTR),y
    and #READEN
    bne READ1
    lda #ACCSERR
    sec
    rts
READ1:
    ldy #FCBMARK
    lda (FCBPTR),y
    sta TPOSLL
    adc C_BYTES
    sta SCRTCH                      ; SCRTCH = the mark plus the count
    iny
    lda (FCBPTR),y
    sta TPOSLH
    adc C_BYTES+1
    sta SCRTCH+1
    iny
    lda (FCBPTR),y
    sta TPOSHI
    adc #0
    sta SCRTCH+2
    ldy #FCBEOF+2
EOFTEST:
    lda SCRTCH-FCBEOF,y
    cmp (FCBPTR),y
    bcc READ2                       ; it ends before the end of file
    bne ADJSTCNT
    dey
    cpy #FCBEOF-1
    bne EOFTEST
ADJSTCNT:
    ldy #FCBEOF
    lda (FCBPTR),y
    sbc TPOSLL
    sta C_BYTES                     ; the count up to the end of file
    iny
    lda (FCBPTR),y
    sbc TPOSLH
    sta C_BYTES+1
    ora C_BYTES
    bne READ2
    lda #EOFERR
    jsr SYSERR
READ2:
    lda C_BYTES
    sta RWREQL
    bne READ3
    cmp C_BYTES+1
    bne READ3
    sta RWREQH
GORDDNE:
    jmp READONE                     ; nothing to read
READ3:
    lda C_BYTES+1
    sta RWREQH
    lda C_OUTBUF
    sta USRBUF
    ldx #C_OUTBUF
    jsr WRAPADJ
    sta USRBUF+1
    sty SISUSRBF
    ldy #FCBSTYP
    lda (FCBPTR),y
    cmp #TRETYP+1
    bcc TREAD
    jmp DREAD
TREAD:
    jsr RDPOSN
    bcc TREAD0
    jmp ERRFIX1
TREAD0:
    jsr PREPRW
    jsr READPART
    bvs GORDDNE                     ; the request is done
    bcs TREAD                       ; newline mode: a block at a time
    lda RWREQH
    lsr a
    beq TREAD                       ; under two blocks left
    sta BULKCNT
    ldy #FCBSTAT
    lda (FCBPTR),y
    and #DATMOD
    bne TREAD                       ; the buffer must be written first
    sta IOACCESS                    ; the first block goes through RDPOSN
    lda USRBUF
    sta DATPTR                      ; the caller's buffer serves as the data buffer
    lda USRBUF+1
    sta DATPTR+1
    lda SISUSRBF
    sta SISDATP
RDFAST:
    jsr RDPOSN
    bcs ERRFIX
RDFAST0:
    inc DATPTR+1
    inc DATPTR+1
    dec RWREQH
    dec RWREQH
    inc TPOSLH
    inc TPOSLH
    bne RDFAST1
    inc TPOSHI
    lda TPOSHI
    eor #1
    lsr a                           ; carry = set at a 128K boundary: another index
RDFAST1:
    dec BULKCNT
    bne RDFAST2
    jsr FXDATPTR
    lda RWREQL
    ora RWREQH
    beq READONE
    bne TREAD                       ; the last part block
RDFAST2:
    bcs RDFAST
    lda TPOSHI
    lsr a
    lda TPOSLH
    ror a
    tay
    lda (TINDX),y
    sta BLOKNML
    inc TINDX+1
    cmp (TINDX),y
    bne REALRD
    cmp #0
    bne REALRD
    sta IOACCESS                    ; a sparse block: RDPOSN zeroes it, and the next goes through RDPOSN too
    beq NOSTUF
REALRD:
    lda (TINDX),y
    clc
NOSTUF:
    dec TINDX+1
    bcs RDFAST
    sta BLOKNMH
    lda IOACCESS
    beq RDFAST
    lda DATPTR+1
    sta DBUFPH
    jsr REPEATIO
    bcc RDFAST0
ERRFIX:
    pha
    jsr FXDATPTR
    pla
ERRFIX1:
    pha
    jsr READONE
    pla
    sec
    rts

;; Ends a READ: returns the count read, the call's count less what is left, and sets the mark to the position.
;; In: C_BYTES = the call's count, RWREQL/RWREQH = what is left, TPOSLL/TPOSLH/TPOSHI = the new position
;; Out: carry = set on an error, A = the error code
;; Uses: X, Y
;; See: <READ>, <RDPOSN>
READONE:
    ldy #0
    sec
    lda C_BYTES
    sbc RWREQL
    sta (C_OUTCNT),y
    iny
    lda C_BYTES+1
    sbc RWREQH
    sta (C_OUTCNT),y
    jmp RDPOSN

;; Gets ready to move bytes between the caller's buffer and the data buffer, from the position's byte in its page.
;;
;; USRBUF is lowered by TPOSLL, so that one index, Y, serves both buffers.
;; In: FCBPTR = the file's FCB, USRBUF = the caller's buffer, TPOSLL = the position's low byte, RWREQL = the count
;; Out: carry = set when newline mode is on, NLCHAR = the newline character, Y = TPOSLL, X = RWREQL,
;;   POSPTR = its page in the data buffer
;; Uses: A
;; See: <READPART>, <WRTPART>
PREPRW:
    sec
    lda USRBUF
    sbc TPOSLL
    sta USRBUF
    bcs PREPRW1
    dec USRBUF+1
PREPRW1:
    ldy #FCBATTR
    lda (FCBPTR),y
    and #NLINEN
    clc
    beq NONEWLIN
    sec
    ldy #FCBNEWL
    lda (FCBPTR),y
    sta NLCHAR
NONEWLIN:
    ldy TPOSLL
    lda DATPTR
    sta POSPTR
    ldx RWREQL
    rts

;; Copies bytes from the data buffer to the caller's buffer until the request is done, the newline character has
;; been copied, or the buffer's two pages are used up.
;;
;; It keeps the position (TPOSLL/TPOSLH/TPOSHI), the count left and USRBUF up to date. The loop is quickest with
;; newline mode off; the newline test only runs with carry set.
;; In: as <PREPRW> leaves them, carry = set for newline mode
;; Out: overflow = set when the request is done or the newline was read, clear when the buffer ran out,
;;   carry = as on entry, RWREQL/RWREQH = the count left
;; Uses: A, X, Y
;; See: <PREPRW>, <WRTPART>
READPART:
    txa
    bne RDPART0
    lda RWREQH
    beq SETRDNE
    dec RWREQH
RDPART0:
    dex
RDPART:
    lda (POSPTR),y
    sta (USRBUF),y
    txa
    beq ENDRQCHK                    ; the low count ran out
RDPART1:
    bcs TSTNEWL
RDPART2:
    dex
    iny
    bne RDPART
    lda POSPTR+1
    inc USRBUF+1
    inc TPOSLH
    bne RDPART3
    inc TPOSHI
RDPART3:
    inc POSPTR+1
    eor DATPTR+1                    ; was that the buffer's first page? carry is kept
    beq RDPART
    clv
    bvc RDPRTDNE
ENDRQCHK:
    lda RWREQH
    beq RDRQDNE
    iny
    bne ENDRCHK1
    lda POSPTR+1
    eor DATPTR+1
    bne ENDRCHK2                    ; the end of the buffer: the next block takes the high count
ENDRCHK1:
    dec RWREQH
ENDRCHK2:
    dey
    jmp RDPART1
TSTNEWL:
    lda (POSPTR),y
    eor NLCHAR
    bne RDPART2
RDRQDNE:
    iny
    bne SETRDNE
    inc USRBUF+1
    inc TPOSLH
    bne SETRDNE
    inc TPOSHI
SETRDNE:
    bit SETVFLG                     ; sets overflow from the $60 of an RTS
RDPRTDNE:
    sty TPOSLL
    bvs RDONE1
    inx                             ; not done: the count is one too few
RDONE1:
    stx RWREQL
    php
    clc
    tya
    adc USRBUF
    sta USRBUF
    bcc RDPART4
    inc USRBUF+1
RDPART4:
    plp
SETVFLG:
    rts

;; After reading straight into the caller's buffer, points USRBUF past what was read and DATPTR back at the file's
;; own buffer.
;; In: DATPTR = the end of what was read, FCBPTR = the file's FCB
;; Out: carry = set on an error, A = the error code
;; Uses: X, Y
;; See: <READ>, <GETBUFADR>
FXDATPTR:
    lda DATPTR
    sta USRBUF
    lda DATPTR+1
    sta USRBUF+1
    lda SISDATP
    sta SISUSRBF
    ldy #FCBBUFN
    lda (FCBPTR),y
    ldx #DATPTR
    jmp GETBUFADR

;; Reads from a directory file, which goes a block at a time.
;;
;; Reading up to the directory's last byte is not an error: the mark stays at the end, and the data buffer is zeroed
;; and given the last block as its back link, with no current block, so that a later SET_MARK can move back.
;; In: as <READ> leaves them
;; Out: carry = set on an error, A = the error code
;; Uses: X, Y
;; See: <READ>, <DIRMARK>
DREAD:
    jsr RDPOSN
    bcs ERRDRD
    jsr PREPRW
    jsr READPART
    bvc DREAD
    jsr READONE
    bcc DREDONE
    cmp #EOFERR
    sec
    bne DREDERR
    jsr SVMARK
    jsr ZIPDATA
    ldy #FCBDATB+1
    lda (FCBPTR),y
    pha
    dey
    lda (FCBPTR),y
    pha
    lda #0
    sta (FCBPTR),y                  ; no current data block
    iny
    sta (FCBPTR),y
    tay
    pla
    sta (DATPTR),y                  ; the back link
    pla
    iny
    sta (DATPTR),y
DREDONE:
    clc
DREDERR:
    rts
ERRDRD:
    jmp ERRFIX1

;; WRITE: writes bytes from the caller's buffer to an open tree file, moving the end of file out if it passes it.
;;
;; The device must not be write-protected. For each block, the position is moved to it with <RDPOSN>, and the blocks
;; it lacks are allocated after checking that the volume has room for them all (<TSFRBLK>): a top index
;; (<TOPDOWN>), a sapling index (<SAPDOWN>) and the data block, which goes into the index. On an error, the old end of
;; file and mark are put back. Directory files cannot be written (ACCSERR).
;; In: FCBPTR = the file's FCB, C_OUTBUF = the buffer, C_BYTES = the count
;; Out: carry = set on an error, A = the error code
;; Uses: X, Y
;; See: <READ>, <WRTPART>, <ALCWBLK>, <TSTWPROT>
WRITE:
    clc
    ldy #FCBATTR
    lda (FCBPTR),y
    and #WRITEN
    bne WRITE1
ERRACCS:
    lda #ACCSERR
    sec
WPERROR:
    rts
WRITE1:
    jsr TSTWPROT
    bcs WPERROR
    ldy #FCBMARK
    lda (FCBPTR),y
    sta TPOSLL
    adc C_BYTES
    sta SCRTCH                      ; SCRTCH = the mark plus the count
    iny
    lda (FCBPTR),y
    sta TPOSLH
    adc C_BYTES+1
    sta SCRTCH+1
    iny
    lda (FCBPTR),y
    sta TPOSHI
    adc #0
    sta SCRTCH+2
    ldy #FCBEOF+2
WEOFTST:
    lda SCRTCH-FCBEOF,y
    cmp (FCBPTR),y
    bcc WRITE2                      ; it ends before the end of file
    bne WADJEOF
    dey
    cpy #FCBEOF-1
    bne WEOFTST
WADJEOF:
    clc
    ldy #FCBEOF
WRTADJEOF:
    lda (FCBPTR),y
    sta OLDEOF-FCBEOF,y             ; kept in case of an error
    lda SCRTCH-FCBEOF,y
    sta (FCBPTR),y                  ; the new end of file
    iny
    cpy #FCBEOF+3
    bne WRTADJEOF
WRITE2:
    lda C_BYTES
    sta RWREQL
    bne WRITE3
    cmp C_BYTES+1
    bne WRITE3
    sta RWREQH
    jmp WRITDONE                    ; nothing to write
WRITE3:
    lda C_BYTES+1
    sta RWREQH
    lda C_OUTBUF
    sta USRBUF
    lda C_OUTBUF+1
    sta USRBUF+1
    lda SISOUTBF
    sta SISUSRBF
    ldy #FCBSTYP
    lda (FCBPTR),y
    cmp #TRETYP+1
    bcc TWRITE
    jmp ERRACCS
TWRITE:
    jsr RDPOSN
    bcs WRITERROR
    ldy #FCBSTAT
    lda (FCBPTR),y
    and #DATALC+IDXALC+TOPALC
    beq TREWRT1                     ; every block is there
    ldy #0
TWRTALC:
    iny
    lsr a
    bne TWRTALC                     ; Y = the number of blocks missing
    sty REQL
    sta REQH
    jsr TSFRBLK
    bcs WRITERROR
    ldy #FCBSTAT
    lda (FCBPTR),y
    and #TOPALC
    beq TSTSAPWR
    jsr TOPDOWN
    bcc DBLOKALC
WRITERROR:
    pha
    ldy #FCBEOF
WRITERR01:
    lda OLDEOF-FCBEOF,y
    sta (FCBPTR),y
    iny
    cpy #FCBEOF+3
    bne WRITERR01
    ldy #FCBMARK
WRITERR02:
    lda OLDMARK-FCBMARK,y
    sta (FCBPTR),y
    iny
    cpy #FCBMARK+3
    bne WRITERR02
    pla
    sec
    rts
TWRITEGO:
    bvc TWRITE                      ; a step back for a branch out of range
TSTSAPWR:
    lda (FCBPTR),y
    and #IDXALC
    beq DBLOKALC
    jsr SAPDOWN
    bcs WRITERROR
DBLOKALC:
    jsr ALCWBLK
    bcs WRITERROR
    lda TPOSHI
    lsr a
    lda TPOSLH
    ror a
    tay                             ; the data block's entry in the index
    inc TINDX+1
    lda SCRTCH+1
    tax
    sta (TINDX),y
    dec TINDX+1
    lda SCRTCH
    sta (TINDX),y
    ldy #FCBDATB
    sta (FCBPTR),y
    iny
    txa
    sta (FCBPTR),y
    ldy #FCBSTAT
    lda (FCBPTR),y
    ora #IDXMOD
    and #$FF-DATALC-IDXALC-TOPALC
    sta (FCBPTR),y
TREWRT1:
    ldx #USRBUF
    jsr WRAPADJ
    jsr PREPRW
    jsr WRTPART
    bvc TWRITEGO                    ; the buffer is full: the next block
WRITDONE:
    jmp RDPOSN

;; Copies bytes from the caller's buffer to the data buffer until the request is done or the buffer's two pages are
;; full, and marks the data and the file's size changed.
;; In: as <PREPRW> leaves them
;; Out: overflow = set when the request is done, clear when the buffer is full, RWREQL/RWREQH = the count left
;; Uses: A, X, Y
;; See: <PREPRW>, <READPART>, <FCBUSED>
WRTPART:
    txa
    bne WRPART
    lda RWREQH
    beq SETWRDNE
    dec RWREQH
WRPART:
    dex
    lda (USRBUF),y
    sta (POSPTR),y
    txa
    beq ENDWQCHK
WRPART2:
    iny
    bne WRPART
    lda POSPTR+1
    inc USRBUF+1
    inc TPOSLH
    bne WRPART3
    inc TPOSHI
WRPART3:
    inc POSPTR+1
    eor DATPTR+1
    beq WRPART
    clv
    bvc WRPRTDNE
ENDWQCHK:
    lda RWREQH
    beq WRTRQDNE
    iny
    bne ENDWCHK1
    lda POSPTR+1
    eor DATPTR+1
    bne ENDWCHK2
ENDWCHK1:
    dec RWREQH
ENDWCHK2:
    dey
    jmp WRPART2
WRTRQDNE:
    iny
    bne SETWRDNE
    inc USRBUF+1
    inc TPOSLH
    bne SETWRDNE
    inc TPOSHI
SETWRDNE:
    bit SETVFLG                     ; sets overflow
WRPRTDNE:
    sty TPOSLL
    stx RWREQL
    php
    ldy #FCBSTAT
    lda (FCBPTR),y
    ora #DATMOD+USEMOD
    sta (FCBPTR),y
    clc
    lda TPOSLL
    adc USRBUF
    sta USRBUF
    bcc WRPART4
    inc USRBUF+1
WRPART4:
    jsr FCBUSED
    plp
    rts

;; Gives a file a top index for a position past 128K, making it a tree, and allocates the sapling index under it.
;;
;; The file's first block moves down a level (<SWAPDOWN>), twice for a seed. The new sapling index goes into the top
;; index's entry for the position and becomes the current index block. The top index is written, and the index
;; buffer is then zeroed for the new sapling index.
;; In: FCBPTR = the file's FCB, TPOSHI = the position's high byte, TINDX = the index buffer
;; Out: carry = set on an error, A = the error code
;; Uses: X, Y
;; Entry: TOPDWN1 = only allocates the sapling index, the top index in the buffer
;; See: <SAPDOWN>, <SWAPDOWN>, <WRITE>
TOPDOWN:
    jsr SWAPDOWN
    bcs TPDWNERR
    ldy #FCBSTYP
    lda (FCBPTR),y
    cmp #TRETYP
    beq TOPDWN1
    jsr SWAPDOWN                    ; it was a seed
    bcs TPDWNERR
TOPDWN1:
    jsr ALCWBLK
    bcs TPDWNERR
    lda TPOSHI
    lsr a
    tay
    lda SCRTCH
    tax
    sta (TINDX),y
    inc TINDX+1
    lda SCRTCH+1
    sta (TINDX),y
    dec TINDX+1
    ldy #FCBIDXB+1
    sta (FCBPTR),y
    txa
    dey
    sta (FCBPTR),y
    jsr WFCBFST
    bcs TPDWNERR
    jmp ZTMPIDX

;; Allocates a sapling index for a position that lacks one: a seed becomes a sapling, and a tree gets a new sapling
;; index under its top index.
;; In: FCBPTR = the file's FCB, TPOSHI = the position's high byte, TINDX = the index buffer
;; Out: carry = set on an error, A = the error code
;; Uses: X, Y
;; See: <TOPDOWN>, <SWAPDOWN>, <WRITE>
SAPDOWN:
    ldy #FCBSTYP
    lda (FCBPTR),y
    cmp #SEEDTYP
    beq SAPDWN1
    jsr RFCBFST
    bcc TOPDWN1
TPDWNERR:
    rts

SAPDWN1:                            ; a seed becomes a sapling

;; Moves a file down a level: a new block becomes its first block, an index whose entry 0 is the old first block.
;;
;; The new block is also the current index block, the index buffer is written to it, and the storage type goes up
;; one (seed to sapling, sapling to tree), marked changed in FCBSTAT.
;; In: FCBPTR = the file's FCB, TINDX = the index buffer, with the rest of its entries zero
;; Out: carry = set on an error, A = the error code
;; Uses: X, Y
;; See: <TOPDOWN>, <SAPDOWN>
SWAPDOWN:
    jsr ALCWBLK
    bcs SWAPERR
    ldy #FCBFRST
    lda (FCBPTR),y
    pha
    lda SCRTCH
    tax
    sta (FCBPTR),y
    iny
    lda (FCBPTR),y
    pha
    lda SCRTCH+1
    sta (FCBPTR),y
    ldy #FCBIDXB+1
    sta (FCBPTR),y
    txa
    dey
    sta (FCBPTR),y
    ldy #0
    inc TINDX+1
    pla
    sta (TINDX),y
    dec TINDX+1
    pla
    sta (TINDX),y
    jsr WFCBFST
    bcs SWAPERR
    ldy #FCBSTYP
    lda #1
    adc (FCBPTR),y                  ; carry is clear
    sta (FCBPTR),y
    ldy #FCBSTAT
    lda (FCBPTR),y
    ora #STPMOD
    sta (FCBPTR),y
    clc
SWAPERR:
    rts

;; Allocates a block for an open file and counts it in the file's size.
;; In: FCBPTR = the file's FCB, VCBPTR = its volume's VCB
;; Out: carry = set on an error, A = the error code, SCRTCH/SCRTCH+1 = the block
;; Uses: X, Y
;; See: <ALC1BLK>
ALCWBLK:
    jsr ALC1BLK
    bcs ALUSERR
    ldy #FCBUSE
    lda (FCBPTR),y
    clc
    adc #1
    sta (FCBPTR),y
    bcc INCUSG1
    iny
    lda (FCBPTR),y
    adc #0
    sta (FCBPTR),y
INCUSG1:
    ldy #FCBSTAT
    lda (FCBPTR),y
    ora #USEMOD
    sta (FCBPTR),y
    clc
ALUSERR:
    rts

;; Checks that an open file's device is not write-protected, unless the file has been written since it was opened.
;; In: FCBPTR = the file's FCB
;; Out: carry = set when the device is write-protected or on an error, A = the error code (XNOWRITE when
;;   write-protected)
;; Uses: X, Y, DEVNUM
;; See: <TWRPROT1>
TSTWPROT:
    ldy #FCBSTAT
    lda (FCBPTR),y
    and #USEMOD+DATMOD+IDXMOD+EOFMOD
    clc
    bne ALUSERR                     ; written already: the device was fine
    ldy #FCBDEVN
    lda (FCBPTR),y
    sta DEVNUM

;; Asks a block device for its status, to learn whether it is write-protected and whether its disk was changed.
;;
;; A disk-switch error from the driver is not an error here: it is noted in <DSWGLOB>, for the BFM to check the volume.
;; In: DEVNUM = the device
;; Out: carry = set when the device is write-protected or on an error, clear after a disk switch,
;;   A = XNOWRITE after a status, or the error code
;; Uses: X, Y
;; See: <TSTWPROT>, <DMGR>
TWRPROT1:
    lda #STATCMD
    sta DHPCMD
    lda #STATSUB
    sta DSTATREQ
    lda #<TWRCODE
    sta DSTATBFL
    lda #>TWRCODE
    sta DSTATBFH
    lda #0
    sta SISDSTAT
    sta SERR
    lda DEVNUM
    sta UNITNUM
    jsr DMGR
    bcs WPROTRET
    lda TWRCODE
    lsr a
    lsr a                           ; bit 1, write-protected, into carry
    lda #XNOWRITE
    rts
WPROTRET:
    cmp #XDISKSW
    bne WPROT1
    sta DSWGLOB
    clc
    rts
WPROT1:
    sec
    rts

;; Non-zero when a status call saw the disk switched, during the current BFM call; the BFM's dispatcher clears it.
;;
;; Its initial contents are whatever was in memory when Apple built SOS.KERNEL; SOS sets it at run time.
;; See: <TWRPROT1>, <RDPOSN>, <FLUSH>
DSWGLOB:
    .res 1, $85

;; The status byte <TWRPROT1> asks the device for.
;;
;; Its initial contents are whatever was in memory when Apple built SOS.KERNEL; SOS sets it at run time.
TWRCODE:
    .res 1, $A0

;; Moves an extended pointer whose high byte is $82 or more down by $8000 into the next bank pair, where it names
;; the same memory, so that a block transfer from it does not run off the end of its bank pair.
;;
;; Pointers without bit 7 of their X-byte set, and those with X-byte $8F, are left as they are.
;; In: X = the pointer's address in page zero, its X-byte at SISTER+1,X
;; Out: A = the pointer's high byte, Y = its X-byte
;; Keeps: X
;; See: <FILEIO1>, <READ>, <WRITE>
WRAPADJ:
    lda 1,x
    ldy SISTER+1,x
    bpl WRAPDNE                     ; not an extended pointer
    cmp #$82
    bcc WRAPDNE
    cpy #$8F
    bcs WRAPDNE
    and #$7F
    sta 1,x
    inc SISTER+1,x
    iny
WRAPDNE:
    rts
    .include "CloseEof.asm"
