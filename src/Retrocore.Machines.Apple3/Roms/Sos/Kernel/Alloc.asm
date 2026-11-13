; ---------------------------------------------------------------------------------------------------------------------
; Block file manager: block allocation.
;
; A volume's free space is a set of bitmap blocks, one bit for each block on the volume, set when the block is free.
; One 512-byte bitmap block covers 4096 blocks, and the bits go from bit 7 of the first byte, block 0, onward. The BFM
; keeps two bitmap buffers, A and B, in the space BFM.INIT2 ran from ($B800 and $BA00). Each has a six-byte table in
; the BFM's page zero (BMASTAT, BMADEV, BMAMADR, BMADADR and BMACMAP for A; the same at BMTABSZ further on for B):
; bit 7 of the status set when the buffer has changes not yet written, the device whose map it holds (0 for none),
; the buffer's page, the map's disk block and the map's number on its volume. BMTAB is 0 or BMTABSZ, the buffer in
; use. When a bitmap buffer is not needed for a map, it serves as a temporary index block buffer (GTTINDX).
;
; This file also holds the routines that move one block between a disk and a bitmap, index or general buffer.
; ---------------------------------------------------------------------------------------------------------------------

;; Frees a block: sets its bit in the volume's bitmap.
;;
;; A block whose high byte is above that of the volume's size is refused: it means that something that is not an
;; index block (data, say) was taken for one and its entries for blocks. When the block is in a
;; different bitmap block than the one in the buffer, the buffer is written out if it has changes and the right map
;; is read in, and VCBCMAP is set to it. The buffer is marked changed. The volume's free count is left to the caller.
;; In: A = the block's low byte, X = its high byte, VCBPTR = the volume's VCB, BMTAB = the volume's bitmap buffer
;; Out: carry = set on an error, A = the error code (BITMAPADR for an impossible block)
;; Uses: X, Y, BMCNT, BMPTR, HALF, NOFREE, BMADR
;; See: <ALC1BLK>, <FNDBMAP>, <GTBMAP>, <BMAPUP>
DEALLOC:
    stx BMCNT
    pha
    ldx VCBPTR
    lda VCB+VCBTBLK+1,x
    cmp BMCNT
    pla
    bcc DEALERR1                    ; the block is beyond the volume
    tax
    and #$7
    tay
    lda WHICHBIT,y
    sta NOFREE                      ; the block's bit in its byte
    txa
    lsr BMCNT
    ror a
    lsr BMCNT
    ror a
    lsr BMCNT
    ror a
    sta BMPTR                       ; the byte's offset in its half of the map
    lsr BMCNT
    rol HALF                        ; which half; BMCNT is now the map's number
    ldx BMTAB
    lda BMACMAP,x
    cmp BMCNT
    beq DEALL1                      ; the buffer holds that map already
    jsr BMAPUP
    bcs DEALERR
    lda BMCNT
    ldy #VCBCMAP
    sta (VCBPTR),y
    ldx BMTAB
    lda BMADEV,x
    jsr GTBMAP
    bcs DEALERR
DEALL1:
    ldy BMPTR
    lsr HALF
    bcc DEALL2
    inc BMADR+1                     ; the second half
DEALL2:
    lda NOFREE
    ora (BMADR),y
    sta (BMADR),y
    bcc DEALL3
    dec BMADR+1
DEALL3:
    ldx BMTAB
    lda #$80
    ora BMASTAT,x
    sta BMASTAT,x                   ; the map has changed
    clc
DEALERR:
    rts
DEALERR1:
    lda #BITMAPADR
    sec
    rts

;; The bit for each of a byte's eight blocks, indexed by the block number's low three bits: block 0 is bit 7.
;; See: <DEALLOC>
WHICHBIT:
    .byte $80, $40, $20, $10
    .byte 8, 4, 2, 1

;; Allocates REQL blocks for a new index block, filling the index buffer from its first entry.
;;
;; After the first block, each search goes on from the bitmap byte where the last one stopped, so the map is not
;; scanned from its start for every block. An index buffer holds each entry's low byte in its first page and the
;; high byte in its second.
;; In: REQL = the number of blocks, TINDX = the index buffer, VCBPTR = the volume's VCB
;; Out: carry = set on an error, A = the error code
;; Uses: X, Y, SAPTR, SCRTCH, BMPTR, HALF, BASVAL
;; See: <ALC1BLK>
ALCIDXS:
    lda #0
    sta SAPTR
    jsr ALC1BLK
    bcs ERRALC1
ALIDX1:
    ldy SAPTR
    sta (TINDX),y                   ; the low byte in the first page
    inc TINDX+1
    lda SCRTCH+1
    sta (TINDX),y                   ; the high byte in the second
    dec TINDX+1
    dec REQL
    beq ALDXEND
    inc SAPTR
    ldy BMPTR
    lda HALF
    bne SECNDHAF
    jsr GETBITS1
    bcc ALIDX1
ERRALC1:
    rts
SECNDHAF:
    jsr GETBITS2
    bcc ALIDX1
ALDXEND:
    rts

;; Allocates one block: finds the first free block in the volume's bitmaps, clears its bit and counts it used.
;;
;; The search starts at the map VCBCMAP names and moves on through the volume's later maps (<NXTBMAP>) until a free
;; block turns up. The block number is the map's number times 4096, plus eight times the byte's offset, plus the
;; bit's position from the left. The buffer is marked changed and the VCB's free count goes down by one.
;; In: VCBPTR = the volume's VCB
;; Out: carry = set on an error, A = the block's low byte or the error code (OVRERR when the volume is full),
;;   Y = the block's high byte, SCRTCH/SCRTCH+1 = the block, BMPTR and HALF = where the search stopped
;; Uses: X, BASVAL, BMADR
;; Entry: SRCHFRE = searches the map in the buffer from its start, GETBITS1 = goes on from byte Y of the first half,
;;   GETBITS2 = goes on from byte Y of the second half
;; See: <ALCIDXS>, <DEALLOC>, <FNDBMAP>
ALC1BLK:
    jsr FNDBMAP
    bcs ERRALC1
SRCHFRE:
    ldy #0
    sty HALF
GETBITS1:
    lda (BMADR),y
    bne BITFOUND                    ; a set bit is a free block
    iny
    bne GETBITS1
    inc BMADR+1
    inc HALF
    inc BASVAL                      ; BASVAL counts 2048 blocks per half
GETBITS2:
    lda (BMADR),y
    bne BITFOUND
    iny
    bne GETBITS2
    dec BMADR+1
    inc BASVAL
    jsr NXTBMAP                     ; nothing free here: the volume's next map
    bcc SRCHFRE
    rts
BITFOUND:
    sty BMPTR
    lda BASVAL
    sta SCRTCH+1
    tya
    asl a
    rol SCRTCH+1
    asl a
    rol SCRTCH+1
    asl a
    rol SCRTCH+1
    tax                             ; the block number of the byte's bit 7
    lda (BMADR),y
    sec                             ; a marker that follows the bits round
ADCALC:
    rol a
    bcs BOUNCE                      ; the leftmost set bit is out
    inx
    bne ADCALC
BOUNCE:
    lsr a
    bcc BOUNCE                      ; shift back until the marker drops out, leaving the bit clear
    sta (BMADR),y
    stx SCRTCH
    ldx BMTAB
    lda #$80
    ora BMASTAT,x
    sta BMASTAT,x
    ldy #VCBTFRE
    lda (VCBPTR),y
    sbc #1                          ; carry is set from BOUNCE
    sta (VCBPTR),y
    bcs RET1BLK
    iny
    lda (VCBPTR),y
    sbc #0
    sta (VCBPTR),y
RET1BLK:
    clc
    lda SCRTCH
    ldy SCRTCH+1
    rts

;; Gets a temporary index block buffer: the bitmap buffer that does not hold the volume's map.
;;
;; The volume's map is read into one of the buffers first if neither holds it. The other buffer is written out if it
;; has changes, and given up (its device set to 0) so that it can hold index entries.
;; In: VCBPTR = the volume's VCB
;; Out: carry = set on an error, A = the error code, TINDX = the free buffer, BMTAB and BMADR = the volume's map
;;   buffer, SSTIDXH and SISBMADR = the buffers' bank
;; Uses: X, Y, NOFREE, ZPGTEMP
;; See: <FNDBMAP>, <WRTBMAP>
GTTINDX:
    ldy #VCBDEV
    ldx #0
    lda (VCBPTR),y
    cmp BMADEV
    beq FREEBE                      ; the map is in A: B is free
    cmp BMBDEV
    beq FREEA                       ; the map is in B: A is free
    jsr FNDBMAP
    bcc GTTINDX
    rts
FREEBE:
    ldx #BMTABSZ
FREEA:
    stx NOFREE
    ldy BMASTAT,x
    bpl USEBUF
    stx ZPGTEMP
    jsr WRTBMAP
    bcs SOMERR1
    ldx ZPGTEMP
    lda #0
    sta BMASTAT,x
USEBUF:
    ldx NOFREE
    lda #0
    sta BMADEV,x
    sta TINDX
    sta BMADR
    lda a:BMAMADR,x
    sta TINDX+1
    txa
    eor #BMTABSZ                    ; the other buffer holds the map
    sta BMTAB
    tax
    lda a:BMAMADR,x
    sta BMADR+1
    lda BMBUFBNK
    sta SSTIDXH
    sta SISBMADR
    clc
SOMERR1:
    rts

;; Moves on to the volume's next bitmap block, for an allocation that found no free block in the current one.
;;
;; The current map is written out if it has changes and the next one is read in.
;; In: VCBPTR = the volume's VCB
;; Out: carry = set on an error, A = the error code (OVRERR when the current map was the last), VCBCMAP = the next map
;; Uses: X, Y
;; See: <ALC1BLK>, <UPBMAP>, <FNDBMAP>
NXTBMAP:
    ldy #VCBTBLK+1
    lda (VCBPTR),y
    lsr a
    lsr a
    lsr a
    lsr a                           ; the number of the volume's last map
    ldy #VCBCMAP
    cmp (VCBPTR),y
    beq NOMORBIT
    lda (VCBPTR),y
    clc
    adc #1
    sta (VCBPTR),y
    ldy #VCBDEV
    lda (VCBPTR),y
    tax
    jsr UPBMAP
    jmp FNDBMAP
GETA_BUF:
    ldx #0                          ; take buffer A
    beq FRESHMAP
GETB_BUF:
    ldx #BMTABSZ                    ; take buffer B
    bne FRESHMAP

;; Makes sure the volume's current bitmap is in a bitmap buffer, and points BMADR at it.
;;
;; When a buffer already belongs to the volume's device and has changes, it is used as it is; when it has none, the
;; map is read again, in case the disk was changed. When neither buffer belongs to the device, an unchanged one is
;; taken, the one used less recently first; when both have changes, the one used less recently is written out first.
;; In: VCBPTR = the volume's VCB
;; Out: carry = set on an error, A = the error code, BMTAB = the buffer, BMADR = its address, SISBMADR = its bank,
;;   BASVAL = the map's number times 2
;; Uses: X, Y, ZPGTEMP
;; See: <GTBMAP>, <ALC1BLK>, <GTTINDX>
FNDBMAP:
    ldy #VCBDEV
    lda (VCBPTR),y
    ldx #0
FNDMAP1:
    cmp BMADEV,x
    bne TRYMAP2
FRESHMAP:
    stx BMTAB
    ldy BMASTAT,x
    bmi BMFOUND                     ; it has changes: use it as it is
    jsr GTBMAP
    bcc BMFOUND
    rts
TRYMAP2:
    dex
    bpl FRBMBUF                     ; neither buffer belongs to the device
    ldx #BMTABSZ
    jmp FNDMAP1
BMFOUND:
    ldx BMTAB
    ldy #VCBCMAP
    lda (VCBPTR),y
    asl a
    sta BASVAL
    lda a:BMAMADR,x
    sta BMADR+1
    lda BMBUFBNK
    sta SISBMADR
    lda #0
    sta BMADR
    clc
    rts
NOMORBIT:
    lda #OVRERR
    sec
    rts
FRBMBUF:
    sec
    ldx BMTAB
    beq CHKBMB                      ; A was used last: try B first
    clc
    bit BMASTAT
    bpl GETA_BUF
CHKBMB:
    bit BMBSTAT
    bcc FREBUF1                     ; B was used last and A has changes: write A
    bpl GETB_BUF
    bit BMASTAT
    bpl GETA_BUF
FREBUF1:
    ldx #0
    bcc FREBUFA
    ldx #BMTABSZ
FREBUFA:
    stx ZPGTEMP
    jsr WRTBMAP
    bcs NOGO
    ldx ZPGTEMP
    lda #0
    sta BMASTAT,x
    bcc FNDBMAP                     ; and look again
NOGO:
    rts

;; Writes a device's bitmap out if a buffer holds it with changes.
;;
;; After a write, the buffer is marked unchanged and <FNDBMAP> reads the current map of VCBPTR's volume.
;; In: X = the device number, VCBPTR = a volume's VCB
;; Out: carry = set on an error, A = the error code
;; Uses: X, Y, ZPGTEMP
;; See: <FNDBMAP>, <WRTBMAP>, <BMAPUP>
UPBMAP:
    cpx BMADEV
    bne UPBM1
    clc                             ; buffer A
    bit BMASTAT
    bmi FREBUF1
    rts
UPBM1:
    cpx BMBDEV
    bne NOUPDAT
    bit BMBSTAT
    bmi FREBUF1                     ; buffer B; carry is set
NOUPDAT:
    clc
    rts

;; Forgets the map a bitmap buffer holds for a device, so that it is read again; for a volume newly logged in there.
;;
;; Only the first buffer the device owns is checked, and one with changes is kept.
;; In: A = the device number
;; Uses: Y
;; Keeps: A, X
;; See: <SWAPIN>
CLEARBMS:
    ldy #0
    cmp BMADEV
    bne CLRBM1
    bit BMASTAT
    bmi CLRBM2                      ; it has changes: keep it
    sty BMADEV
CLRBM2:
    rts
CLRBM1:
    cmp BMBDEV
    bne CLRBM2
    bit BMBSTAT
    bmi CLRBM2
    sty BMBDEV
    rts

;; Reads a volume's current bitmap block into a bitmap buffer.
;;
;; The buffer's table gets the device, the map's number (VCBCMAP) and its disk block (the volume's first map block,
;; VCBDMAP, plus the number).
;; In: A = the device number, X = the buffer (0 for A, BMTABSZ for B), VCBPTR = the volume's VCB
;; Out: carry = set on an error, A = the error code, BMADR+1 = the buffer's page, SISBMADR = its bank
;; Uses: X, Y
;; See: <DOBMAP>, <FNDBMAP>
GTBMAP:
    sta BMADEV,x
    lda a:BMAMADR,x
    sta BMADR+1
    lda BMBUFBNK
    sta SISBMADR
    ldy #VCBCMAP
    lda (VCBPTR),y
    sta BMACMAP,x
    clc
    ldy #VCBDMAP
    adc (VCBPTR),y
    sta BMADADR,x
    iny
    lda (VCBPTR),y
    adc #0
    sta BMADADR+1,x
    lda #RDCMD

;; Reads or writes the bitmap block a bitmap buffer's table names.
;;
;; DEVNUM is kept: the transfer goes to the buffer's own device, and the caller's device number is put back after.
;; In: A = the command (RDCMD or WRTCMD), X = the buffer (0 or BMTABSZ)
;; Out: carry = set on an error, A = the error code
;; Uses: X, Y
;; See: <WRTBMAP>, <GTBMAP>, <DOBITMAP>
DOBMAP:
    sta DHPCMD
    lda DEVNUM
    pha
    lda BMADEV,x
    sta DEVNUM
    lda BMADADR,x
    sta BLOKNML
    lda BMADADR+1,x
    sta BLOKNMH
    lda a:BMAMADR,x
    ldx BMBUFBNK
    jsr DOBITMAP
    pla
    sta DEVNUM
    rts

;; Writes a bitmap buffer's map to its disk block.
;; In: X = the buffer (0 or BMTABSZ)
;; Out: carry = set on an error, A = the error code
;; Uses: X, Y
;; See: <DOBMAP>
WRTBMAP:
    lda #WRTCMD
    jmp DOBMAP

;; Writes the general buffer, GBUF, to block BLOKNML/BLOKNMH.
;; In: BLOKNML/BLOKNMH = the block, DEVNUM = the device
;; Out: carry = set on an error, A = the error code, TTLINK = the block
;; Uses: X, Y
;; See: <RDGBUF>
WRTGBUF:
    lda #WRTCMD
    bne SVGCMD

;; Reads block BLOKNML/BLOKNMH into the general buffer, GBUF.
;;
;; The block's number is kept in <TTLINK>, for extending a directory.
;; In: BLOKNML/BLOKNMH = the block, DEVNUM = the device
;; Out: carry = set on an error, A = the error code, TTLINK = the block
;; Uses: X, Y
;; See: <WRTGBUF>
RDGBUF:
    lda #RDCMD
SVGCMD:
    sta DHPCMD
    lda BLOKNML
    sta TTLINK
    lda BLOKNMH
    sta TTLINK+1
    lda #GBUF/256
    ldx #0                          ; GBUF is not in a bank

;; Reads or writes block BLOKNML/BLOKNMH through a page-aligned buffer.
;; In: A = the buffer's page, X = its bank byte, DHPCMD = the command, BLOKNML/BLOKNMH = the block, DEVNUM = the device
;; Out: carry = set on an error, A = the error code
;; Uses: X, Y
;; See: <FILEIO2>
DOBITMAP:
DOIDX:
    sta DBUFPH
    stx SISBPH
    lda #0
    sta DBUFPL
    jmp FILEIO2

;; The block the general buffer last read or wrote, for extending a directory.
;;
;; Its initial contents are whatever was in memory when Apple built SOS.KERNEL; SOS sets it at run time.
;; See: <RDGBUF>, <WRTGBUF>
TTLINK:
    .byte $A0, $85

;; Writes the index buffer, TINDX, to the index block IDXADRL/IDXADRH.
;; In: IDXADRL/IDXADRH = the block, DEVNUM = the device, TINDX = the buffer
;; Out: carry = set on an error, A = the error code
;; Uses: X, Y
;; See: <DOFRST>
WRTINDX:
    lda #WRTCMD
    ldx IDXADRL
    ldy IDXADRH

;; Reads or writes a block through the index buffer, TINDX.
;; In: A = the command, X = the block's low byte, Y = its high byte, DEVNUM = the device
;; Out: carry = set on an error, A = the error code
;; Uses: X, Y
;; See: <WRTINDX>, <RDFRST>, <WRTDFRST>
DOFRST:
    sta DHPCMD
    stx BLOKNML
    sty BLOKNMH
    lda TINDX+1
    ldx SSTIDXH
    jmp DOIDX

;; Writes the index buffer to the first block of the file in the directory entry buffer (DFIL+D_FRST), for CREATE.
;; In: DFIL = the file's entry, DEVNUM = the device, TINDX = the buffer
;; Out: carry = set on an error, A = the error code
;; Uses: X, Y
;; See: <RDFRST>, <DOFRST>
WRTDFRST:
    lda #WRTCMD
    bne FADDR

;; Reads the first block of the file in the directory entry buffer (DFIL+D_FRST) into the index buffer.
;; In: DFIL = the file's entry, DEVNUM = the device, TINDX = the buffer
;; Out: carry = set on an error, A = the error code
;; Uses: X, Y
;; See: <WRTDFRST>, <DOFRST>
RDFRST:
    lda #RDCMD
FADDR:
    ldx DFIL+D_FRST
    ldy DFIL+D_FRST+1
    jmp DOFRST
    .include "PosnOpen.asm"
