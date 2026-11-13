; SOS 1.3 kernel, block file manager: the CREATE call, writing directory entries back to disk, and the test for a
; SOS directory.

; ---------------------------------------------------------------------------------------------------------------------
; CREATE
; ---------------------------------------------------------------------------------------------------------------------

;; CREATE: makes a new file or subdirectory, allocating and clearing the blocks for its initial size.
;;
;; The pathname's last name must not exist, and its directory must have a free entry; a full subdirectory is
;; extended by a block (<LOOKFILE>, with <CFLAG> set). The option list, up to 9 bytes, gives the file type, the
;; auxiliary type, the storage type and the size to allocate, in that order; what it leaves out is 0, and the
;; storage type defaults to a file.
;;
;; For a file (a storage type below 4) the size picks the kind: one block or less is a seedling, up to 256
;; blocks a sapling with one index block, and more a tree with a master index. Every block is allocated and its
;; data blocks written with zeros. For a subdirectory (DIRTYP) the size, below 64K, gives the number of linked
;; directory blocks, at least one; the first holds the new directory's header. Other storage types give TYPERR.
;;
;; The new entry allows every access. It is written with the creation date, the parent's file count goes up by
;; one, and the volume's bitmap is written back.
;; In:
;;   PATHNML = the parsed pathname (from <SETPATH>)
;;   C_XLIST = the option list, C_XLEN = its length
;;   DATELO  = the date and time
;; Out:
;;   carry   = set for an error
;;   A       = the error: DUPERR, DIRFULL, BADLSTCNT, OVRERR, TYPERR, or one from the search or the device
;; Uses:  X, Y, DFIL, H_FCNT, GBUF, DATBLKL, DATBLKH, INDXBLK, LEVELS, REQL, REQH, TLINK, FLINK
;; See:   <LOOKFILE>, <SAPINDX>, <DREVISE>
CREATE:
    inc CFLAG                       ; lets LOOKFILE extend a full directory
    jsr LOOKFILE
    bcs TSTFNF
    lda #DUPERR
CRERR1:
    sec
    rts
TSTFNF:
    cmp #FNFERR
    bne CRERR1
    lda NOFREE
    bne CREAT1                      ; a free entry was found
    lda #DIRFULL
    sec
    rts
CREAT1:
    ldy #$9
    lda #0
ZERCALL:
    sta C_FILID,y                   ; the defaults: all 0
    dey
    bpl ZERCALL
    lda #SEEDTYP
    sta C_STOR
    ldy C_XLEN
    beq CRENAM
    dey
    cpy #$9
    bcc MOVPARM
    lda #BADLSTCNT
    rts
MOVPARM:
    lda (C_XLIST),y
    sta C_FILID,y
    dey
    bpl MOVPARM
CRENAM:
    ldy #0
    lda (PATHNML),y
    tay
CRENAM1:
    lda (PATHNML),y                 ; the name and its length into the new entry
    sta DFIL+D_STOR,y
    dey
    bpl CRENAM1
    lda C_FILID
    sta DFIL+D_FILID
    lda C_AUXID
    sta DFIL+D_AUXID
    lda C_AUXID+1
    sta DFIL+D_AUXID+1
    lda #READEN+WRITEN+RENAMEN+DSTROYEN
    sta DFIL+D_ATTR
    lda D_HEAD
    sta DFIL+D_DHDR
    lda D_HEAD+1
    sta DFIL+D_DHDR+1
    jsr TWRPROT1                    ; is the disk write-protected?
    bcs CRERR1
    lda C_STOR
    cmp #4
    bcc SEED
    jmp NOTREE
SEED:
    ldx #SEEDTYP                    ; X = the storage type, as worked out below
    lda C_EOFHH
    beq SEED1
OVFLOW:
    lda #OVRERR
    sec
    rts
SEED1:
    lda C_EOFHL                     ; the size in blocks: the size divided by 512, rounded up
    sta DFIL+D_EOF+2
    lsr a
    tay                             ; Y = the index blocks needed
    sta DATBLKH
    lda C_EOFLH
    sta DFIL+D_EOF+1
    ror a
    sta DATBLKL
    lda C_EOFLL
    sta DFIL+D_EOF
    bne INCDATA
    bcc TSTSAP
INCDATA:
    inc DATBLKL
    bne TSTSAP
    iny
    inc DATBLKH
TSTSAP:
    tya
    bne SAPLING
    lda DATBLKL
    bne TSTSEED
    inc DATBLKL                     ; a size of 0 still gets one block
    bne CREALC
TSTSEED:
    cmp #1
    beq CREALC                      ; a seedling
    inx
    iny
    bne CREALC                      ; a sapling with one index block
SAPLING:
    inx
    cmp #1
    bne TREE
    lda DATBLKL
    beq CREALC                      ; exactly 256 blocks: still a sapling
TREE:
    iny                             ; a partly filled index block
    inx
    iny                             ; and the master index
CREALC:
    sty INDXBLK
    txa
    asl a
    asl a
    asl a
    asl a
    ora DFIL+D_STOR                 ; the storage type goes in the high nibble
    sta DFIL+D_STOR
    stx LEVELS
    tya
    clc
    adc DATBLKL
    sta DFIL+D_USAGE                ; the blocks used: index and data
    sta REQL
    lda DATBLKH
    adc #0
    sta DFIL+D_USAGE+1
    sta REQH
    ldx D_DEV
    jsr TSFRBLK
    bcs OVFLOW
    jsr ALC1BLK                     ; the key block
    bcs CRERR
    sta DFIL+D_FRST
    sta IDXADRL
    sty DFIL+D_FRST+1
    sty IDXADRH
    jsr ZERGBUF
    jsr GTTINDX                     ; a buffer for building index blocks
    jsr ZTMPIDX
    ldx LEVELS
    dex
    beq ENDCRE                      ; a seedling: its key block is its data, written as zeros
    dex
    beq SAPFILE
    ldy INDXBLK                     ; a tree: allocate its index blocks into the master index
    dey
    sty REQL
    sty INDXBLK
    jsr ALCIDXS
    bcs CRERR
    jsr WRTDFRST
    bcs CRERR
    lda #0
    sta TREPTR
FILLTREE:
    ldy TREPTR
    lda (TINDX),y                   ; the next index block's number, from the master index
    sta IDXADRL
    inc TINDX+1
    lda (TINDX),y
    sta IDXADRH
    dec TINDX+1
    dec INDXBLK
    beq LSTSAP
    lda #0                          ; a full index block: 256 data blocks
    sta REQL
    jsr SAPINDX
    bcs CRERR
    jsr WRTINDX
    bcs CRERR
    inc TREPTR
    jsr RDFRST                      ; the master index again
    bcc FILLTREE
CRERR:
    sec
    rts
SAPFILE:
LSTSAP:
    lda DATBLKL                     ; the last (or only) index block's data blocks
    sta REQL
    jsr SAPINDX
    bcs CRERR
ENDCRE:
    jsr WRTINDX
    bcs CRERR
    ldx #3
TRETIME:
    lda DATELO,x
    sta DFIL+D_CREDT,x
    dex
    bpl TRETIME
ENDCRE0:
    inc H_FCNT                      ; one more file in the directory
    bne ENDCRE1
    inc H_FCNT+1
    ldx #3                          ; only when the count's low byte wraps; DREVISE also sets it with a clock
ENDCRX:
    lda DATELO,x
    sta DFIL+D_MODDT,x
    dex
    bpl ENDCRX
ENDCRE1:
    ldx D_DEV
    jsr UPBMAP
    bcs CRERR2
    jsr DREVISE
    rts

;; Allocates the data blocks of one index block and writes zeros to each of them.
;;
;; It clears the index buffer at TINDX, allocates the blocks into it (low bytes in its first page, high bytes in
;; its second), writes the cleared GBUF to the first block, and repeats that write for the others. A block number
;; of 0 in the index is fatal (ALCERR).
;; In:    REQL = the number of data blocks (0 for 256), GBUF = zeros, DEVNUM = the device
;; Out:   carry = set for an error, A = the error, TINDX = the filled index block
;; Uses:  X, Y, TLINK, SAPTR, BLOKNML, BLOKNMH
;; See:   <CREATE>, <REPEATIO>
SAPINDX:
    jsr ZTMPIDX
    lda REQL
    sta TLINK                       ; keep the count; ALCIDXS uses REQL up
    jsr ALCIDXS
    bcs CRERR
    ldy #0
    sty SAPTR
    lda (TINDX),y
    sta BLOKNML
    inc TINDX+1
    lda (TINDX),y
    sta BLOKNMH
    dec TINDX+1
    jsr WRTGBUF
    bcs CRERR
    lda TLINK
    sta REQL
DATINIT:
    ldy SAPTR
    iny
    dec REQL
    beq DATDONE
    sty SAPTR
    lda (TINDX),y
    sta BLOKNML
    inc TINDX+1
    tax
    bne DATIT1
    cmp (TINDX),y
    bne DATIT1
    lda #ALCERR                     ; both bytes 0: the allocation went wrong
    jsr SYSDEATH
DATIT1:
    lda (TINDX),y
    sta BLOKNMH
    dec TINDX+1
    lda #GBUF/256
    sta DBUFPH
    jsr REPEATIO
    bcc DATINIT
DATDONE:
    rts

;; Repeats the device's last read or write, at the block in BLOKNML/BLOKNMH.
;; In:    BLOKNML/BLOKNMH = the block, DEVNUM = the device
;; Out:   carry = set for an error, A = the error
;; Uses:  X, Y, DHPCMD, UNITNUM
;; See:   <RPTCMD>, <SAPINDX>
REPEATIO:
    lda #RPTCMD
    sta DHPCMD
    jmp RPEATIO1

;; Fills GBUF, the 512-byte general buffer, with zeros.
;; Out:   A = 0, Y = 0
;; Keeps: X
ZERGBUF:
    ldy #0
    tya
ZGBUF:
    sta GBUF,y
    sta GBUF+$100,y
    iny
    bne ZGBUF
    rts

;; Fills the 512-byte index buffer at TINDX with zeros.
;; In:    TINDX = the buffer, SSTIDXH = its bank byte
;; Out:   A = 0, Y = 0
;; Keeps: X
ZTMPIDX:
    ldy #0
    tya
ZINDX1:
    sta (TINDX),y
    iny
    bne ZINDX1
    inc TINDX+1
ZINDX2:
    sta (TINDX),y
    iny
    bne ZINDX2
    dec TINDX+1
CRERR2:
    rts
NOTREE:
    cmp #DIRTYP                     ; CREATE of something other than a file
    beq ISDIR
    jmp NOTDIR
ISDIR:
    lda C_EOFHH
    ora C_EOFHL
    beq ISDIR1
DIROVR:
    lda #OVRERR
    sec
    rts
ISDIR1:
    lda C_EOFLH                     ; the size in blocks, rounded up
    lsr a
    tay
    lda C_EOFLL
    bne DADD1
    bcc TSDIRSZ
DADD1:
    iny
TSDIRSZ:
    tya
    beq DADD1                       ; at least one block
    sta DFIL+D_USAGE
    sta REQL
    asl a
    sta DFIL+D_EOF+1                ; the size, a whole number of blocks
    lda #0
    sta DFIL+D_EOF
    sta DFIL+D_EOF+2
    sta REQH
    jsr TSFRBLK
    bcs DIROVR
    jsr ZERGBUF
    jsr ALC1BLK                     ; the key block, which holds the header
    bcs CRERR2
    sta DFIL+D_FRST
    sta TLINK
    sty DFIL+D_FRST+1
    sty TLINK+1
    lda SOSTMPL                     ; the backward link: 0 in a first block
    sta GBUF
    lda SOSTMPH
    sta GBUF+1
    ldy #4
    bne DRSTUF1
DRSTUF:
    lda D_ENTBLK,y                  ; the parent's entry block and entry number
    sta GBUF+HRBLK+4,y
DRSTUF1:
    lda SOSVER,y                    ; the version, attributes, entry length and entries per block
    sta GBUF+HVER+4,y
    dey
    bpl DRSTUF
    lda H_ENTLN
    sta GBUF+HRELN+4                ; the parent's entry length
    lda DFIL+D_STOR
    tay
    ora #HEDTYP*16
    sta GBUF+HNLEN+4
    tya
    ora #DIRTYP*16
    sta DFIL+D_STOR
MVHNAME:
    lda DFIL+D_STOR,y               ; the header takes the directory's name
    sta GBUF+HNLEN+4,y
    dey
    bne MVHNAME
    ldx #3
CRETIME:
    lda DATELO,x
    sta GBUF+HCRDT+4,x
    sta DFIL+D_CREDT,x
    dex
    bpl CRETIME
    lda #$76
    sta GBUF+HPENAB+4               ; the password-enable byte SOS gives a new directory
    dec REQL
    beq DIRCREND
    jsr DIRWRT
    bcs DERROR
    jsr ZERGBUF
CRNXTDIR:
    lda TLINK                       ; the block just written is the next one's backward link
    sta GBUF
    lda TLINK+1
    sta GBUF+1
    lda FLINK
    sta TLINK
    lda FLINK+1
    sta TLINK+1
    dec REQL
    beq DIRCREND
    jsr DIRWRT
    bcs DERROR
    lda #0
    sta GBUF+2
    sta GBUF+3
    beq CRNXTDIR
DIRCREND:
    jsr DIRWRT1                     ; the last block, with no forward link
    bcs DERROR
    jmp ENDCRE0

;; Allocates a directory's next block, links GBUF's block to it, and writes GBUF to block TLINK.
;;
;; The new block's number goes in GBUF's forward link (bytes 2 and 3) and in FLINK.
;; In:    GBUF = the directory block, TLINK = its block number, DEVNUM = the device
;; Out:   carry = set for an error, A = the error, FLINK = the new block
;; Uses:  X, Y, BLOKNML, BLOKNMH
;; See:   <DIRWRT1>, <CREATE>
DIRWRT:
    jsr ALC1BLK
    bcs DERROR
    sta GBUF+2
    sty GBUF+3
    sta FLINK
    sty FLINK+1

;; Writes GBUF to block TLINK.
;; In:    GBUF = the block's contents, TLINK = the block number, DEVNUM = the device
;; Out:   carry = set for an error, A = the error
;; Uses:  X, Y, BLOKNML, BLOKNMH
DIRWRT1:
    lda TLINK
    sta BLOKNML
    lda TLINK+1
    sta BLOKNMH
    jmp WRTGBUF
ERRGBUF:
DERROR:
    rts

;; The SOS stamp: the two bytes that start the first block of every SOS directory, its backward link of 0.
;; See: <TSTSOS>
SOSTMPL:
    .byte $0

;; The SOS stamp's second byte.
;; See: <SOSTMPL>
SOSTMPH:
    .byte $0

;; The header bytes for a new subdirectory, from HVER on: the version of SOS that made it (0), the oldest that
;; can read it (0), the attributes (0), the entry length ($27, 39 bytes) and the entries per block (13).
;; See: <CREATE>
SOSVER:
    .byte 0, 0, 0, $27, 13
RNDTAB:                             ; another name for ENTCALC's address, which nothing uses

;; Points DRBUFPL/DRBUFPH at the directory entry D_ENTNUM in GBUF.
;;
;; Entries start 4 bytes into the block, after its links, and are H_ENTLN bytes long; entry 1 is the first.
;; In:    D_ENTNUM = the entry's number, H_ENTLN = the entry length
;; Out:   DRBUFPL/DRBUFPH = the entry
;; Uses:  A, X
;; Keeps: Y
ENTCALC:
    lda #GBUF/256
    sta DRBUFPH
    lda #4
    ldx D_ENTNUM
ECALC0:
    clc
ECALC1:
    dex
    beq ECALC2
    adc H_ENTLN
    bcc ECALC1
    inc DRBUFPH
    bcs ECALC0
ECALC2:
    sta DRBUFPL
    rts
DERROR2:
    rts

;; Writes the entry in DFIL back to its directory block, and the directory's file count and attributes to its
;; header, setting the modification date when the clock gives one.
;;
;; The entry is marked as needing a backup when BKBITFLG says so. The entry's block (D_ENTBLK) is read into GBUF,
;; the entry copied over entry D_ENTNUM and the block written; then the header block (D_HEAD) gets H_FCNT and
;; H_ATTR, read first when it is another block.
;; In:
;;   DFIL     = the entry
;;   D_DEV    = the device
;;   D_ENTBLK = the directory block that holds the entry
;;   D_ENTNUM = the entry's number in that block
;;   D_HEAD   = the directory's header block
;;   DATELO   = the date, or 0 when there is no clock
;; Out:   carry = set for an error, A = the error
;; Uses:  X, Y, DEVNUM, BLOKNML, BLOKNMH, DRBUFPL, DRBUFPH, GBUF
;; See:   <DREVISE1>, <ENTCALC>
DREVISE:
    lda DATELO
    beq DREVISE1                    ; no clock: keep the old date
    ldx #3
MODTIME:
    lda DATELO,x
    sta DFIL+D_MODDT,x
    dex
    bpl MODTIME

;; Writes the entry in DFIL back to its directory, and updates the header, without setting the modification date.
;; In:
;;   DFIL     = the entry
;;   D_DEV    = the device
;;   D_ENTBLK = the directory block that holds the entry
;;   D_ENTNUM = the entry's number in that block
;;   D_HEAD   = the directory's header block
;; Out:   carry = set for an error, A = the error
;; Uses:  X, Y, DEVNUM, BLOKNML, BLOKNMH, DRBUFPL, DRBUFPH, GBUF
;; See:   <DREVISE>
DREVISE1:
    lda DFIL+D_ATTR
    ora BKBITFLG
    sta DFIL+D_ATTR
    lda D_DEV
    sta DEVNUM
    lda D_ENTBLK
    sta BLOKNML
    lda D_ENTBLK+1
    sta BLOKNMH
    jsr RDGBUF
    bcs ERRGBUF
    jsr ENTCALC
    ldy H_ENTLN
    dey
MVDENT:
    lda DFIL+D_STOR,y
    sta (DRBUFPL),y
    dey
    bpl MVDENT
    lda D_HEAD
    cmp BLOKNML
    bne SVENTDIR
    lda D_HEAD+1
    cmp BLOKNMH
    beq UPHEAD                      ; the header is in the same block
SVENTDIR:
    jsr WRTGBUF
    bcs DERROR2
    lda D_HEAD
    sta BLOKNML
    lda D_HEAD+1
    sta BLOKNMH
    jsr RDGBUF
    bcs DERROR2
UPHEAD:
    ldy #1
UPHED1:
    lda H_FCNT,y
    sta GBUF+HCENT+4,y
    dey
    bpl UPHED1
    lda H_ATTR
    sta GBUF+HATTR+4
    jsr WRTGBUF
DERROR1:
    rts
NOTDIR:
    lda #TYPERR                     ; neither a file nor a directory
TSTERR:
    sec
    rts

;; Tests whether GBUF holds the first block of a SOS directory: the SOS stamp, then a header entry.
;;
;; The header's storage type must be $E (a subdirectory) or $F (a volume directory).
;; In:    GBUF = the block
;; Out:   carry = set when it is not a SOS directory
;; Uses:  A
;; Keeps: X, Y
;; See:   <SOSTMPL>, <LOGVCB>
TSTSOS:
    lda GBUF
    cmp SOSTMPL
    bne TSTERR
    lda GBUF+1
    cmp SOSTMPH
    bne TSTERR
    lda GBUF+4
    and #$E0
    cmp #HEDTYP*16
    bne TSTERR
    clc
    rts
    .include "FndFil.asm"
