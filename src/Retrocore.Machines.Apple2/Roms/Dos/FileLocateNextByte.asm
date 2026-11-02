;; DOS 3.3 AND 3.2 FILE MANAGER: DISK I/O AND THE NEXT BYTE OF A FILE (FLOCNXB)
;;
;; The file manager's lower half, part one. It reads and writes the VTOC and catalog sectors, turns a request
;; for a sector into a call to RWTS (DCBIO, which also turns RWTS's errors into the file manager's), and finds
;; the byte at a file's current position: LOCNXB brings in the right track/sector list and data sector, and
;; allocates new ones when a write runs past the end of the file. Small helpers advance the position and walk
;; a caller's buffer for block transfers.
;;
;; Where DOS runs, this is $AFF7-$B1C8. The requests that call it (OPEN, READ, WRITE and the rest) are in
;; FileOpenCloseReadWrite.asm and FileDeleteCatalog.asm; reading and writing the track/sector list and data
;; sector buffers is in FileManagerIo.asm; sector allocation, the catalog search and the exits (GOODIO,
;; ERRORB) are in FileLocateSector.asm; the buffers and the file control block are in FileManagerData.asm.
;; docs/Dos.md describes the VTOC, the catalog and track/sector lists.

;; Reads the VTOC, track DCBVTN sector 0, into the VTOC buffer.
;; In:    DCBVTN = the VTOC's track (17), DCBSLT/DCBDRV/DCBVOL = the disk
;; Out:   VTOC..VTOC+$FF = the sector
;; Errors: does not return on a disk error; DCBIO leaves the file manager through ERRORB
;; Uses:  A, X, Y
;; See:   <DCBIO>
RDVTOC:
    lda #IBCRTS
    bne VTIO                        ; always taken
;; Writes the VTOC buffer back to track DCBVTN sector 0.
;; In:    DCBVTN = the VTOC's track (17), DCBSLT/DCBDRV/DCBVOL = the disk
;; Errors: does not return on a disk error; DCBIO leaves the file manager through ERRORB
;; Uses:  A, X, Y
;; Entry: VTIO = the read or write, with the RWTS command in A
WRVTOC:
    lda #IBCWTS
VTIO:
    ldy AVTOC
    sty a:IBBUFP
    ldy AVTOC+1
    sty a:IBBUFP+1
    ldx a:DCBVTN
    ldy #0
    jmp DCBIO
;; Reads a catalog sector into the catalog buffer: the first one, or the one after the sector in the buffer.
;;
;; The VTOC must be in its buffer for the first sector, since it holds where the catalog starts. Each catalog
;; sector holds the track and sector of the next in its bytes 1 and 2 (VDLTRK, VDLSEC); a zero track ends the
;; chain.
;; In:    carry = clear for the first catalog sector, set for the next one
;; Out:   carry clear and the sector in VOLDIR, CVDTRK/CVDSEC = where it came from;
;;   carry set when there is no next sector (the buffer is unchanged)
;; Errors: does not return on a disk error; DCBIO leaves the file manager through ERRORB
;; Uses:  A, X, Y
RDVDIR:
    php
    jsr MVVDBA
    plp
    bcs RVDA
RVDC:
    ldy a:VDIRSC
    ldx a:VDIRTK
    bne RVDGO                       ; always taken: the catalog is never on track 0
RVDA:
    ldx a:VDLTRK
    bne RDVC
    sec                             ; no link: the end of the catalog
    rts
RDVC:
    ldy a:VDLSEC
RVDGO:
    stx a:CVDTRK                    ; remember the sector, for WRVDIR
    sty a:CVDSEC
    lda #IBCRTS
    jsr DCBIO
    clc
    rts
;; Writes the catalog buffer back to the sector it was read from.
;; In:    VOLDIR = the catalog sector, CVDTRK/CVDSEC = where it came from
;; Errors: does not return on a disk error; DCBIO leaves the file manager through ERRORB
;; Uses:  A, X, Y
WRVDIR:
    jsr MVVDBA
    ldx a:CVDTRK
    ldy a:CVDSEC
    lda #IBCWTS
    jmp DCBIO
;; Points RWTS's buffer pointer at the catalog buffer, VOLDIR.
;; Out:   IBBUFP = VOLDIR
;; Uses:  A
MVVDBA:
    lda AVOLDR
    sta a:IBBUFP
    lda AVOLDR+1
    sta a:IBBUFP+1
    rts
;; Reads, writes or formats through RWTS, for the slot, drive and volume in the file control block.
;;
;; Fills in the rest of the IOB from the FCB and calls DISKIO. A write also sets bit 1 ($02, the value of
;; IBCWTS) in DCBWRF, which tells CLOSE the disk was changed and the catalog's sector count needs updating.
;; The caller sets the buffer, IBBUFP, first.
;;
;; DCBVOL holds the volume number complemented (DCBSUP stores it that way); it is complemented back here, so
;; IBVOL gets the volume the caller asked for, 0 meaning any.
;; In:    A = the RWTS command (IBCRTS, IBCWTS, IBFMT), X = track, Y = sector, IBBUFP = the buffer
;; Out:   CCBVOL = the volume number RWTS found on the disk, IBVOL = $FF
;; Errors: does not return on failure: leaves the file manager through ERRORB with CREVMM (volume mismatch),
;;   CREPRO (write protected) or CREIOE (any other error)
;; Uses:  A, X, Y
;; Entry: DCBIO2 = IBTRK and IBSECT already set
DCBIO:
    stx a:IBTRK
    sty a:IBSECT
DCBIO2:
    sta a:IBCMD
    cmp #IBCWTS
    bne DCBIO1
    ora a:DCBWRF                    ; a write: set bit 1 of DCBWRF
    sta a:DCBWRF
DCBIO1:
    lda a:DCBVOL
    eor #$FF
    sta a:IBVOL
    lda a:DCBSLT
    sta a:IBSLOT
    lda a:DCBDRV
    sta a:IBDRVN
    lda a:DCBSDL
    sta a:IBDLEN
    lda a:DCBSDL+1
    sta a:IBDLEN+1
    lda #1
    sta a:IBTYPE
    ldy AIOB
    lda AIOB+1
    jsr DISKIO
    lda a:IBSMOD                    ; the volume RWTS found, for the caller (CATALOG prints it)
    sta a:CCBVOL
    lda #$FF
    sta a:IBVOL
    bcs BADIO
    rts
; Turns RWTS's status into a file manager return code and leaves.
BADIO:
    lda a:IBSTAT
    ldy #CREVMM
    cmp #IBVMME
    beq BD2
    ldy #CREPRO
    cmp #IBWPER
    beq BD2
    ldy #CREIOE
BD2:
    tya
    jmp ERRORB
;; Makes the byte at the file's current position addressable, bringing its sector into the data buffer.
;;
;; The position is a relative sector (DCBCRS, counting from 0 at the start of the file) and a byte in it
;; (DCBCSB). If that sector is already in the buffer (DCBCMS), nothing is read. Otherwise the buffer is written
;; back if it was changed, and the track/sector list that covers the sector is found: each list covers DCBDMS
;; (122) sectors, from DCBDFS up to but not including DCBDNF. A sector before the list in memory makes RDFDIR
;; start again from the file's first list; one after it follows the chain. The sector's track and sector are
;; then taken from the list. A zero track means the sector was never written: a read ends there (end of
;; file), while a write allocates a new sector for it (GNWSEC), and RDFDIR likewise adds a new list when a
;; write runs past the last one.
;; In:    DCBCRS = the relative sector, DCBCSB = the byte in it, CCBREQ = the request (CRQWR allocates)
;; Out:   carry clear, ZPGFCB = the data sector buffer and Y = the byte's offset in it;
;;   carry set when reading past the end of the file
;; Errors: does not return on a disk error or a full disk
;; Uses:  A, X, Y
;; See:   <RDFDIR>, <LOCSEC>
LOCNXB:
    lda a:DCBCRS
    cmp a:DCBCMS
    bne LNB1
    lda a:DCBCRS+1
    cmp a:DCBCMS+1
    beq LNB8                        ; the sector is already in the buffer
LNB1:
    jsr WRSECT                      ; write the old one back if it was changed
; Is the sector covered by the track/sector list in memory? It must not be below DCBDFS...
LNB2:
    lda a:DCBCRS+1
    cmp a:DCBDFS+1
    bcc LNB4
    bne LNB3
    lda a:DCBCRS
    cmp a:DCBDFS
    bcc LNB4                        ; below: carry clear, so RDFDIR goes back to the first list
; ...and must be below DCBDNF.
LNB3:
    lda a:DCBCRS+1
    cmp a:DCBDNF+1
    bcc LNB6
    bne LNB4
    lda a:DCBCRS
    cmp a:DCBDNF
    bcc LNB6
; Here carry is clear to read the file's first list, set to read the next one.
LNB4:
    jsr RDFDIR
    bcc LNB2                        ; check the list just read
    rts                             ; no more lists: the end of the file
; Y = the offset of the sector's pair in the list: (DCBCRS - DCBDFS) * 2 + FDENT. The difference is under 122,
; so only the low bytes matter, and the ASL leaves carry clear for the ADC.
LNB6:
    sec
    lda a:DCBCRS
    sbc a:DCBDFS
    asl a
    adc #FDENT
    tay
    jsr MVFCBD
    lda (ZPGFCB),y                  ; the sector's track
    bne LNB7
    lda a:CCBREQ                    ; none: allocate one if writing, else it is the end of the file
    cmp #CRQWR
    beq LNB7A
    sec
    rts
LNB7A:
    jsr GNWSEC
    jmp LNBCON
LNB7:
    sta a:DCBTRK
    iny
    lda (ZPGFCB),y
    sta a:DCBSEC
    jsr RDSECT
LNBCON:
    lda a:DCBCRS                    ; this relative sector is now the one in the buffer
    sta a:DCBCMS
    lda a:DCBCRS+1
    sta a:DCBCMS+1
LNB8:
    jsr MVFCBS
    ldy a:DCBCSB
    clc
    rts
;; Allocates a new data sector for the track/sector list entry at Y and gives the file an empty buffer for it.
;;
;; Records the new track and sector in the list and in DCBTRK/DCBSEC, clears the data buffer, and marks both
;; the list ($80) and the data sector ($40) in DCBWRF as needing to be written.
;; In:    Y = the offset of the entry in the track/sector list buffer, ZPGFCB = that buffer
;; Out:   ZPGFCB = the data sector buffer, all zeros
;; Errors: does not return on a disk error or a full disk
;; Uses:  A, X, Y, TEMP2
;; See:   <GETSEC>
GNWSEC:
    sty a:TEMP2
    jsr GETSEC                      ; A = the sector, DCBATK = its track
    ldy a:TEMP2
    iny
    sta (ZPGFCB),y
    sta a:DCBSEC
    dey
    lda a:DCBATK
    sta (ZPGFCB),y
    sta a:DCBTRK
    jsr MVFCBS
    jsr CLRSEC
    lda #$C0
    ora a:DCBWRF
    sta a:DCBWRF
    rts
;; Reports the position of the byte just transferred and advances the position in the record by one.
;;
;; Copies the current record and byte in it (DCBCRR, DCBCRB) to the parameter list (CCBRRN, CCBBYT), so the
;; caller sees where the byte it read or wrote was. Then counts the byte; reaching the record length (DCBRCL)
;; starts the next record at byte 0. INCSCB advances the sector position to match.
;; Out:   CCBRRN/CCBBYT = the old position, DCBCRR/DCBCRB = the new one
;; Uses:  X, Y
INCRRB:
    ldx a:DCBCRR
    stx a:CCBRRN
    ldx a:DCBCRR+1
    stx a:CCBRRN+1
    ldx a:DCBCRB
    ldy a:DCBCRB+1
    stx a:CCBBYT
    sty a:CCBBYT+1
    inx                             ; YX = the byte in the record, plus 1
    bne INCR1
    iny
INCR1:
    cpy a:DCBRCL+1
    bne INCR2
    cpx a:DCBRCL
    bne INCR2
    ldx #0                          ; the end of the record: byte 0 of the next
    ldy #0
    inc a:DCBCRR
    bne INCR2
    inc a:DCBCRR+1
INCR2:
    stx a:DCBCRB
    sty a:DCBCRB+1
    rts
;; Advances the file position by one byte: the next byte of the sector, or the first of the next sector.
;; Out:   DCBCSB = the byte in the sector, DCBCRS = the relative sector
INCSCB:
    inc a:DCBCSB
    bne INCS2
    inc a:DCBCRS
    bne INCS2
    inc a:DCBCRS+1
INCS2:
    rts
;; Points ZPGFCB at the next byte of the caller's buffer for a block transfer, and advances the pointer.
;; In:    CCBBBA = the next byte of the caller's buffer
;; Out:   ZPGFCB = that byte's address, CCBBBA = the one after it
;; Uses:  X, Y
MIBDA:
    ldy a:CCBBBA
    ldx a:CCBBBA+1
    sty ZPGFCB
    stx ZPGFCB+1
    inc a:CCBBBA
    bne MIB1
    inc a:CCBBBA+1
MIB1:
    rts
;; Counts down a block transfer's length, and ends the request when it was already zero.
;;
;; While CCBBLN is not zero it is decremented and DTBLN returns; when it is zero, DTBLN does not return but
;; jumps to GOODIO, leaving the file manager. READ calls it before each byte and WRITE after each, so a block
;; read of length n transfers n bytes and a block write n + 1.
;; In:    CCBBLN = the bytes left
;; Out:   CCBBLN = one fewer
;; Uses:  X, Y
DTBLN:
    ldy a:CCBBLN
    bne DTB1
    ldx a:CCBBLN+1
    beq DTB2
    dec a:CCBBLN+1
DTB1:
    dec a:CCBBLN
    rts
DTB2:
    jmp GOODIO                      ; the block is done
