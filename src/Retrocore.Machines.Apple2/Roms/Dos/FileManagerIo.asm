;; DOS 3.3 AND 3.2 FILE MANAGER: INIT, AND READING AND WRITING A FILE'S SECTORS (FMTRWIO)
;;
;; The INIT request, which formats a disk and gives it an empty VTOC and catalog and a copy of DOS, and the
;; routines that move a file's sectors between its buffers and the disk: the data sector and the
;; track/sector list sector. Each disk access goes through DCBIO (FileLocateNextByte.asm), which fills in
;; RWTS's parameter list IOB from the work area and calls RWTS. Where DOS runs, the module occupies
;; $AE8E-$AFF6.
;;
;; An open file has three buffers, which the parameter list points to and MVFCBP, MVFCBD and MVFCBS select:
;; the work area, the current track/sector list sector, and the current data sector. Bits of DCBWRF say which
;; buffers have changed since they were read: bit 7 the track/sector list, bit 6 the data sector. DCBIO sets
;; bit 1 on every write, which CLOSE checks.
;;
;; A track/sector list sector (docs/Dos.md) holds the track and sector of the next list at +1 and +2 (FDLTRK,
;; FDLSEC; track 0 at the end), the file's relative sector number its first pair stands for at +5 and +6
;; (FDFRS), and from +$0C (FDENT) 122 pairs of track and sector, one for each data sector in turn.

;; The INIT request: formats the disk, writes a fresh VTOC and an empty catalog, and writes DOS to tracks 0
;; to 2.
;;
;; The new VTOC is the VTOC buffer as it stands, from the last VTOC DOS read (or as DOS was loaded), with the
;; volume number and the allocation start changed and the bit map rebuilt: tracks 3 to 34 free but for track
;; 17, 16 sectors each (13 in DOS 3.2). Only the bit map is cleared, so the catalog's track and sector, the
;; number of tracks and sectors and the rest of the header come from that buffer. The catalog is track 17's
;; sectors 15 down to 1 (12 down to 1 in DOS 3.2), each linked to the one below and the last to nothing; sector
;; 0 is the VTOC.
;; In:    CCBBSA = the first page of the DOS image to write, CCBVOL = the volume number, CCBDRV, CCBSLT =
;;          the disk
;; Out:   CCBSTA = 0
;; Errors: the disk errors of DCBIO
;; Uses:  A, X, Y, VTOC, VOLDIR
FFMT:
    jsr DCBSUP
    lda #IBFMT                      ; format every track
    jsr DCBIO2
    lda a:DCBVOL
    eor #$FF
    sta a:VVOLNO
    lda #17                         ; the last track allocated: the catalog's, so allocation starts next
    sta a:VALCA1                    ; to it
    lda #1                          ; and moves up the track numbers
    sta a:VALCA2
    ldx #VSECAL-VTOC                ; zero the bit map, to the end of the sector: every sector in use
    lda #0
NT1:
    sta a:VTOC,x
    inx
    bne NT1
; Free tracks 3 to 34 but 17: copy ALC10S, backward, into each track's four bytes, giving $FF $FF $00 $00,
; sectors 15 to 0 free (DOS 3.2: $FF $F8 $00 $00, sectors 12 to 0).
    ldx #3*4
NT2:
    cpx #35*4
    beq NT4
    ldy #3
NT3:
    lda a:ALC10S,y
    sta a:VSECAL,x
    inx
    dey
    bpl NT3
    cpx #17*4
    bne NT2
    ldx #18*4                       ; skip the catalog's track
    bne NT2                         ; always
NT4:
    jsr WRVTOC
; Write the catalog: VOLDIR zeroed, then for each sector from 15 (DOS 3.2: 12) down to 1 the link to the sector
; below.
    ldx #0
    txa
NT5:
    sta a:VOLDIR,x
    inx
    bne NT5
    jsr MVVDBA                      ; RWTS's buffer: VOLDIR
    lda #17
    ldy a:VNOSEC
    dey
    dey                             ; Y = the sector the first one written links to, 14 (DOS 3.2: 11)
    sta a:IBTRK
NT6:
    sta a:VDLTRK
NT7:
    sty a:VDLSEC
    iny                             ; write the sector above the one it links to
    sty a:IBSECT
    lda #IBCWTS
    jsr DCBIO2                      ; (DCBIO2 leaves IBTRK and IBSECT as they are)
    ldy a:VDLSEC
    dey
    bmi NT8                         ; sector 1, the last, has been written
    bne NT7
    tya                             ; sector 1 next: its link is track 0, sector 0, the end
    beq NT6                         ; always
NT8:
    jsr DLDSUP                      ; RWTS's buffer: the DOS image at CCBBSA
    jsr WBOOT                       ; write it to tracks 0 to 2
    jmp GOODIO

;; Points ZPGFCB at one of the open file's buffers, from the parameter list: the work area (MVFCBP), the
;; track/sector list sector (MVFCBD) or the data sector (MVFCBS).
;; In:    CCBFCB, CCBDBP, CCBSBP = the buffers' addresses
;; Out:   ZPGFCB = the buffer
;; Uses:  A, X
;; Keeps: Y
;; Entry: MVFCBD = the track/sector list buffer, MVFCBS = the data buffer, MVF1 = X = the field's offset
;;          from CFCBAD
MVFCBP:
    ldx #0                          ; CCBFCB
    beq MVF1                        ; always
MVFCBD:
    ldx #2                          ; CCBDBP
    bne MVF1                        ; always
MVFCBS:
    ldx #4                          ; CCBSBP
MVF1:
    lda a:CFCBAD,x
    sta ZPGFCB
    lda a:CFCBAD+1,x
    sta ZPGFCB+1
    rts

;; Writes the data buffer to its sector if it has changed (bit 6 of DCBWRF), and marks it written.
;; Out:   DCBWRF = bit 6 clear
;; Errors: the disk errors of DCBIO
;; Uses:  A, X, Y
;; Entry: WRSGO = writes it whether changed or not
WRSECT:
    bit a:DCBWRF
    bvs WRSGO
    rts
WRSGO:
    jsr MVSBA
    lda #IBCWTS
    jsr DCBIO
    lda #$BF
    and a:DCBWRF
    sta a:DCBWRF
    rts

;; Writes the track/sector list buffer to its sector if it has changed (bit 7 of DCBWRF), and marks it
;; written.
;; Out:   DCBWRF = bit 7 clear
;; Errors: the disk errors of DCBIO
;; Uses:  A, X, Y
;; Entry: WRFDGO = writes it whether changed or not
WRFDIR:
    lda a:DCBWRF
    bmi WRFDGO
    rts
WRFDGO:
    jsr MVFDBA
    lda #IBCWTS
    jsr DCBIO
    lda #$7F
    and a:DCBWRF
    sta a:DCBWRF
    rts

;; Points RWTS's buffer at the track/sector list buffer, and gets the current list's track and sector.
;; Out:   IBBUFP = CCBDBP, X = DCBCDT, the track, Y = DCBCDS, the sector
;; Uses:  A
MVFDBA:
    lda a:CFCBDR
    sta a:IBBUFP
    lda a:CFCBDR+1
    sta a:IBBUFP+1
    ldx a:DCBCDT
    ldy a:DCBCDS
    rts

;; Reads the file's first track/sector list sector (carry clear), or the next one (carry set), into the list
;; buffer.
;;
;; The list in the buffer is written first if it has changed. When there is no next list and the request is
;; WRITE, a sector is allocated for one: the old list is linked to it and written, and the new one, empty
;; but for the relative sector its first pair stands for, is written to the disk. Either way the work area
;; learns the range of relative sectors the list covers.
;; In:    carry = clear for the first list, DCBFDT/DCBFDS; set for the one the current list links to
;; Out:   carry = clear, ZPGFCB = the list buffer, DCBCDT/DCBCDS = its track and sector, DCBDFS = the relative
;;          sector of its first pair, DCBDNF = one past its last
;; Errors: carry = set when there is no next list and the request is not WRITE; 9 when the disk is full; the
;;          disk errors of DCBIO
;; Uses:  A, X, Y
RDFDIR:
    php
    jsr WRFDIR
    jsr MVFDBA
    jsr MVFCBD
    plp
    bcs RFDNXT
    ldx a:DCBFDT
    ldy a:DCBFDS
    jmp RFDIO1
RFDNXT:
    ldy #FDLTRK
    lda (ZPGFCB),y
    beq RFDNL                       ; no link: this was the last list
    tax
    iny
    lda (ZPGFCB),y
    tay
    jmp RFDIO1
RFDNL:
    lda a:CCBREQ
    cmp #CRQWR
    beq RFDNL1
    sec
    rts
; Writing past the last list: add one.
RFDNL1:
    jsr GETSEC                      ; A = sector, DCBATK = track
    ldy #FDLSEC
    sta (ZPGFCB),y                  ; link the old list to it
    pha
    dey
    lda a:DCBATK
    sta (ZPGFCB),y
    pha
    jsr WRFDGO                      ; write the old list
    jsr CLRSEC                      ; and start the new one empty
    ldy #FDFRS
    lda a:DCBDNF                    ; its first pair follows the old list's last
    sta (ZPGFCB),y
    iny
    lda a:DCBDNF+1
    sta (ZPGFCB),y
    pla
    tax
    pla
    tay
    lda #IBCWTS
    bne RFDIO2                      ; always
RFDIO1:
    lda #IBCRTS
RFDIO2:
    stx a:DCBCDT
    sty a:DCBCDS
    jsr DCBIO
; The relative sectors this list covers: DCBDFS up to DCBDNF, DCBDMS (122) further on.
RDFDC:
    ldy #FDFRS
    lda (ZPGFCB),y
    sta a:DCBDFS
    clc
    adc a:DCBDMS
    sta a:DCBDNF
    iny
    lda (ZPGFCB),y
    sta a:DCBDFS+1
    adc a:DCBDMS+1
    sta a:DCBDNF+1
    clc
    rts

;; Reads the data sector at DCBTRK and DCBSEC into the file's data buffer.
;; In:    DCBTRK, DCBSEC = the sector
;; Errors: the disk errors of DCBIO
;; Uses:  A, X, Y
RDSECT:
    jsr MVSBA
    lda #IBCRTS
    jmp DCBIO

;; Points RWTS's buffer at the data buffer, and gets the data sector's track and sector.
;; Out:   IBBUFP = CCBSBP, X = DCBTRK, the track, Y = DCBSEC, the sector
;; Uses:  A
;; Entry: MSB1 = A/Y = the buffer's address (high/low) instead; not used
MVSBA:
    ldy a:CFCBSB
    lda a:CFCBSB+1
MSB1:
    sty a:IBBUFP
    sta a:IBBUFP+1
    ldx a:DCBTRK
    ldy a:DCBSEC
    rts
