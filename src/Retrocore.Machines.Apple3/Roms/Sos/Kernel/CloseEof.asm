; ---------------------------------------------------------------------------------------------------------------------
; Block file manager: CLOSE, FLUSH, SET_EOF and GET_EOF.
;
; FLUSH writes what an open file has in its buffers, updates its directory entry from its FCB and writes out its
; volume's bitmap. CLOSE flushes the file and then gives up its buffer and FCB. Both take reference number 0 to mean
; every open file (CLOSE: those opened at or above the current file level); then an error does not stop the others,
; and the last one kept in <CFERR> is returned at the end.
; ---------------------------------------------------------------------------------------------------------------------

;; CLOSE: closes an open file, or with reference number 0 every file opened at or above the current file level.
;;
;; Each file is flushed (<FLUSH>), its buffer released and its FCB freed. Its volume's open count goes down, and the
;; volume is marked as having no files open when that reaches 0.
;; In: C_REFNUM = the reference number or 0
;; Out: carry = set on an error, A = the error code
;; Uses: X, Y
;; See: <FLUSH>, <OPEN>, <RELBUF>, <GLBERR>
CLOSE:
    lda C_REFNUM
    bne CLOSE1
    sta CFERR
    jsr GFCBADR
CLOSALL:
    lda #0
CLSALL1:
    sta FCBPTR
    ldy #FCBLEVL
    lda (FCBPTR),y
    cmp LEVEL
    bcc NXTCLOS                     ; opened below the current level: leave it open
    ldy #FCBREFN
    lda (FCBPTR),y
    beq NXTCLOS                     ; a free FCB
    jsr FLUSH2
    bcs CLOSERR
    jsr CLOSE2
    ldy C_REFNUM
    beq NXTCLOS
    bcs CLOSERR
NXTCLOS:
    lda FCBPTR
    clc
    adc #$20
    bcc CLSALL1
    lda FCBPTR+1
    inc FCBPTR+1
    cmp a:FCBADDRH
    beq CLOSALL                     ; on to the second page
    clc
    lda CFERR
    beq C3
    sec
C3:
    rts

;; The last error a CLOSE or FLUSH of every file met, or 0; returned when all the files are done.
;;
;; Its initial contents are whatever was in memory when Apple built SOS.KERNEL; SOS sets it at run time.
;; See: <GLBERR>, <CLOSE>, <FLUSH>
CFERR:
    .res 1, $C6
CLOSE1:
    jsr FLUSH1
    bcs CLOSERR

;; Frees an open file's buffer and FCB and counts it closed on its volume.
;; In: FCBPTR = the file's FCB
;; Out: carry = set on an error, A = the error code
;; Uses: X, Y, DEVNUM, VCBPTR
;; See: <CLOSE>, <DEVVCB>
CLOSE2:
    ldy #FCBBUFN
    lda (FCBPTR),y
    jsr RELBUF
    bcs CLOSERR
    lda #0
    ldy #FCBREFN
    sta (FCBPTR),y
    iny
    lda (FCBPTR),y
    sta DEVNUM
    jsr DEVVCB
    ldx VCBPTR
    dec VCB+VCBOPNC,x
    bne CLOSEND
    lda VCB+VCBSTAT,x
    and #$7F                        ; no files open on the volume
    sta VCB+VCBSTAT,x
CLOSEND:
    clc
    rts
CLOSERR:
    jmp GLBERR

;; FLUSH: writes an open file's buffers and directory entry to its volume, or with reference number 0 every open
;; file's.
;; In: C_REFNUM = the reference number or 0
;; Out: carry = set on an error, A = the error code
;; Uses: X, Y
;; See: <FLUSH2>, <CLOSE>, <GLBERR>
FLUSH:
    lda C_REFNUM
    bne FLUSH1
    sta CFERR
    jsr GFCBADR
FLSHALL:
    lda #0
FLSHAL1:
    sta FCBPTR
    ldy #FCBREFN
    lda (FCBPTR),y
    beq NXFLUSH
    jsr FLUSH2
    bcs FLSHERR
    bcs CLOSERR
NXFLUSH:
    lda FCBPTR
    clc
    adc #$20
    bcc FLSHAL1
    lda FCBPTR+1
    inc FCBPTR+1
    cmp a:FCBADDRH
    beq FLSHALL
FLUSHEND:
    clc
    lda CFERR
    beq F3
    sec
F3:
    rts
FLSHERR:
    jmp GLBERR

;; Flushes one open file: writes its changed data and index blocks, updates its directory entry and writes out its
;; volume's bitmap if it has changes.
;;
;; A file opened only for reading, or not written since it was opened, needs nothing. A disk switch seen first
;; returns XDISKSW, so that the BFM checks the volume and makes the call again. The entry gets the file's size, end of
;; file, first block and storage type, which a write may have changed, and <DREVISE> writes it with the time.
;; In: FCBPTR = the file's FCB
;; Out: carry = set on an error, A = the error code
;; Uses: X, Y
;; Entry: FLUSH1 = finds the FCB for C_REFNUM first, FLUSH2A = with the buffers and VCB already found
;; See: <FLUSH>, <WFCBDAT>, <WFCBIDX>, <DREVISE>, <FNDFCBUF>
FLUSH2:
    jsr FNDFCBUF
    bcc FLUSH2A
    jmp GLBERR
FLUSH1:
    lda #0
    sta CFERR
    jsr FINDFCB
    bcs FLSHERR
FLUSH2A:
    ldy #FCBATTR
    lda (FCBPTR),y
    and #WRITEN
    beq FLUSHEND                    ; read only
    ldy #FCBDIRTY
    lda (FCBPTR),y
    bmi FLUSH2B                     ; the entry needs updating
    ldy #FCBSTAT
    lda (FCBPTR),y
    and #USEMOD+EOFMOD+DATMOD
    beq FLUSHEND                    ; nothing written
FLUSH2B:
    jsr TWRPROT1
    lda DSWGLOB
    beq FLUSH2C
    lda #XDISKSW
    sec
    rts
FLUSH2C:
    ldy #FCBSTAT
    lda (FCBPTR),y
    and #DATMOD
    beq FLUSH3
    jsr WFCBDAT
    bcs FLSHERR
FLUSH3:
    ldy #FCBSTAT
    lda (FCBPTR),y
    and #IDXMOD
    beq FLUSH4
    jsr WFCBIDX
    bcs FLSHERR
FLUSH4:
    ldy #FCBENTN
OWNRMOV:
    lda (FCBPTR),y
    sta D_DEV-FCBDEVN,y             ; the entry's place, in the FCB's order
    dey
    cpy #FCBDEVN-1
    bne OWNRMOV
    lda D_HEAD
    sta BLOKNML
    lda D_HEAD+1
    sta BLOKNMH
    lda D_DEV
    sta DEVNUM
    jsr RDGBUF                      ; the directory's header block
    bcs FLSHERR
    jsr MOVHED0
    lda D_ENTBLK
    ldy D_ENTBLK+1
    cmp D_HEAD
    bne FLSHEBLK
    cpy D_HEAD+1
    beq FLUSH5                      ; the entry is in the header block
FLSHEBLK:
    sta BLOKNML
    sty BLOKNMH
    jsr RDGBUF                      ; the entry's block
FLUSH5:
    jsr ENTCALC
    jsr MOVENTRY
    ldy #FCBUSE
    lda (FCBPTR),y
    sta DFIL+D_USAGE
    iny
    lda (FCBPTR),y
    sta DFIL+D_USAGE+1
    ldy #FCBEOF
EOFUPDTE:
    lda (FCBPTR),y
    sta DFIL+D_EOF-FCBEOF,y
    iny
    cpy #FCBEOF+3
    bne EOFUPDTE
    ldy #FCBFRST
    lda (FCBPTR),y
    iny
    sta DFIL+D_FRST
    lda (FCBPTR),y
    sta DFIL+D_FRST+1
    ldy #FCBSTYP
    lda (FCBPTR),y
    asl a
    asl a
    asl a
    asl a
    sta SCRTCH
    lda DFIL+D_STOR
    and #$F                         ; the name's length
    ora SCRTCH                      ; under the storage type
    sta DFIL+D_STOR
    jsr DREVISE
    bcs FLUSHERR
    ldy #FCBDIRTY
    lda (FCBPTR),y
    and #$FF-FCBMOD
    sta (FCBPTR),y
    ldx #0
    lda D_DEV
    cmp BMADEV
    beq BMAPUP
    ldx #BMTABSZ
    cmp BMBDEV
    bne FLSHEND1

;; Writes out a bitmap buffer if it has changes, and marks it unchanged.
;; In: X = the buffer (0 for A, BMTABSZ for B)
;; Out: carry = set on an error, A = the error code, BMTAB = the buffer when it was written
;; Uses: X, Y
;; See: <WRTBMAP>, <DEALLOC>, <DESTROY>
BMAPUP:
    lda BMASTAT,x
    bpl FLSHEND1
    stx BMTAB
    jsr WRTBMAP
    bcs FLUSHERR
    ldx BMTAB
    lda #0
    sta BMASTAT,x
FLSHEND1:
    clc
    rts

;; Returns an error from CLOSE or FLUSH: at once for one file, or for every file kept in <CFERR> with carry clear,
;; so that the others are still done.
;; In: A = the error code, C_REFNUM = the call's reference number
;; Out: carry = set for one file, clear for every file
;; See: <CLOSE>, <FLUSH>
FLUSHERR:
GLBERR:
    ldx C_REFNUM
    bne GLBERR1
    clc
    sta CFERR
GLBERR1:
    rts

;; Points FCBPTR's high byte and bank at the FCB pages, for a scan of every FCB.
;; Uses: A
;; Keeps: X, Y
;; See: <CLOSE>, <FLUSH>
GFCBADR:
    lda FCBANKNM
    sta SISFCBP
    lda a:FCBADDRH
    sta FCBPTR+1
    rts

;; Returns ACCSERR from SET_EOF.
;; Out: carry = set, A = ACCSERR
;; See: <SETEOF>
SETERR:
    lda #ACCSERR
    sec
EOFRETN:
    rts

;; SET_EOF: moves an open file's end of file, freeing the blocks past a lower one in a sapling file.
;;
;; Only seed, sapling and tree files opened for writing, on a device that is not write-protected, qualify; otherwise
;; the error is ACCSERR. The new end of file is worked out as SET_MARK's position is (<ADJMARK>), and a mark beyond it
;; moves to it. When it is lower than before, a sapling file's data blocks after the one holding its last byte are
;; freed and its size set to the blocks left plus the index. A seed has nothing to free, and a tree's blocks are not
;; freed.
;; In: FCBPTR = the file's FCB, C_BASE = the base, C_NEWEOF = the position (C_MARK's place)
;; Out: carry = set on an error, A = the error code, C_NEWEOF = the new end of file
;; Uses: X, Y
;; See: <ADJMARK>, <PURLBLKS>, <GETEOF>
SETEOF:
    ldy #FCBSTYP
    lda (FCBPTR),y
    cmp #TRETYP+1
    bcs SETERR
    ldy #FCBATTR
    lda (FCBPTR),y
    and #WRITEN
    beq SETERR
    jsr TSTWPROT
    bcs SETERR
    ldy #FCBEOF+2
    ldx #2
SETSAVE:
    lda (FCBPTR),y
    sta OLDEOF,x
    dey
    dex
    bpl SETSAVE
    jsr ADJMARK
    bcs EOFRETN
    ldx #2
NEOFPOS:
    lda TPOSLL,x
    sta C_NEWEOF,x
    dex
    bpl NEOFPOS
    ldy #FCBMARK+2
    ldx #2
NEOFTST:
    lda (FCBPTR),y
    cmp C_NEWEOF,x
    bcc SETEOF1                     ; the mark is below the new end of file
    bne SETEOF0
    dey
    dex
    bpl NEOFTST
SETEOF0:
    jsr RDPOSN                      ; move the mark to the new end of file
    bcs EOFRETN
SETEOF1:
    ldx #2
    ldy #FCBEOF+2
SETEOF2:
    lda C_NEWEOF,x
    sta (FCBPTR),y
    dey
    dex
    bpl SETEOF2
    jsr FCBUSED
    ldx #2
PURTEST:
    lda OLDEOF,x
    cmp C_NEWEOF,x
    bcc PURTEST1
    bne PURGE                       ; the end of file moved back
    dex
    bpl PURTEST
PURTEST1:
    jmp FLSHEND1
TRELEAS1:
    jmp TRELEASE
PURGE:
    ldy #FCBSTYP
    lda (FCBPTR),y
    cmp #SEEDTYP
    beq EOFOUT
    cmp #TRETYP
    beq TRELEAS1
    jsr FNDBMAP
    ldx TPOSHI
    ldy TPOSLH
    lda TPOSLL
    bne PUR1
    cpy #0
    bne PUR2
    cpx #0
    beq PUR1
    dex
PUR2:
    dey                             ; the last byte is in the block before
PUR1:
    txa
    lsr a
    tya
    ror a                           ; the index entry of the block holding the last byte
    jsr PURLBLKS
    ldy #FCBSTAT
    lda (FCBPTR),y
    ora #IDXMOD
    sta (FCBPTR),y
    lda PURUSE
    clc
    adc #2                          ; the blocks kept and the index
    ldy #FCBUSE
    sta (FCBPTR),y
    iny
    lda #0
    bcc PURHI
    lda #1
PURHI:
    sta (FCBPTR),y
EOFOUT:
    clc
    rts

;; Frees the data blocks a sapling's index lists after a given entry, clears their entries and counts them free in
;; the VCB.
;; In: A = the entry of the last block to keep, TINDX = the index buffer, VCBPTR = the volume's VCB
;; Out: PURUSE = the entry kept
;; Uses: A, X, Y, PURPLACE
;; See: <SETEOF>, <DEALLOC>
PURLBLKS:
    tay
    sty PURUSE
PURLOOP:
    iny
    beq PURLRTS                     ; the end of the index
    inc TINDX+1
    lda (TINDX),y
    tax
    lda #0
    sta (TINDX),y
    txa
    dec TINDX+1
    ora (TINDX),y
    beq PURLOOP                     ; no block there
    lda (TINDX),y
    pha
    lda #0
    sta (TINDX),y
    pla
    sty PURPLACE
    jsr DEALLOC
    ldy #VCBTFRE
    clc
    lda (VCBPTR),y
    adc #1
    sta (VCBPTR),y
    iny
    lda (VCBPTR),y
    adc #0
    sta (VCBPTR),y
    ldy PURPLACE
    jmp PURLOOP
PURLRTS:
    rts

;; The entry of the last block <PURLBLKS> keeps, which gives the file's new size.
;;
;; Its initial contents are whatever was in memory when Apple built SOS.KERNEL; SOS sets it at run time.
PURUSE:
    .res 1, $90

;; The entry <PURLBLKS> is at while <DEALLOC> runs.
;;
;; Its initial contents are whatever was in memory when Apple built SOS.KERNEL; SOS sets it at run time.
PURPLACE:
    .res 1, $C3

;; Where SET_EOF would free a tree file's blocks; it frees none.
;; Out: carry = clear
;; See: <SETEOF>
TRELEASE:
    jmp EOFOUT

;; GET_EOF: returns an open file's end of file, three bytes.
;;
;; The loop ends at OFFRTS, NEWLINE's return in Destroy.asm.
;; In: FCBPTR = the file's FCB, C_OUTEOF = where the end of file goes
;; Out: carry = clear
;; Uses: A, X, Y, C_OUTEOF
;; See: <SETEOF>
GETEOF:
    ldy #FCBEOF
    ldx #0
OUTEOF:
    lda (FCBPTR),y
    sta (C_OUTEOF,x)
    iny
    cpy #FCBEOF+3
    beq OFFRTS
    inc C_OUTEOF
    bne OUTEOF
    inc C_OUTEOF+1
    bne OUTEOF
    .include "Destroy.asm"
