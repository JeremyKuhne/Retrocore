; ---------------------------------------------------------------------------------------------------------------------
; Block file manager: NEWLINE, GET_FILE_INFO, SET_FILE_INFO, RENAME and DESTROY, and the BFM's work space: the
; directory header and directory entry the file calls work on, and scratch storage.
; ---------------------------------------------------------------------------------------------------------------------

;; NEWLINE: turns newline mode on or off for an open file, and sets its newline character.
;;
;; With newline mode on, a READ stops after the newline character.
;; In: FCBPTR = the file's FCB, C_ISNEWL = bit 7 set for on, C_NEWL = the character
;; Out: carry = clear
;; Uses: A, Y
;; See: <READ>, <READPART>
NEWLINE:
    ldy #FCBATTR
    lda C_ISNEWL
    bpl OFFNEWL
    lda #NLINEN
    ora (FCBPTR),y
    sta (FCBPTR),y
    ldy #FCBNEWL
    lda C_NEWL
    sta (FCBPTR),y
    clc
    rts
OFFNEWL:
    lda #$FF-NLINEN
    and (FCBPTR),y
    sta (FCBPTR),y
OFFRTS:
    clc                             ; GET_EOF ends here too
    rts

;; GET_FILE_INFO: returns a file's attributes, type, storage type, end of file, size and modification time.
;;
;; The bytes go to the caller's list in the call's order, as <INFTABL> maps them from the directory entry, as far as
;; the list's length asks. For a volume's root directory, the storage type is $F, the auxiliary type is the volume's
;; size in blocks and the size is the blocks in use, from a free count brought up to date first (<TSFRBLK>).
;; In: C_PATH = the pathname, C_FILIST = the list, C_FILSTLN = its length
;; Out: carry = set on an error, A = the error code
;; Uses: X, Y
;; See: <SETINFO>, <FINDFILE>
GETINFO:
    jsr FINDFILE
    bcc GTINFO1
    cmp #BADPATH                    ; a root directory?
    sec
    bne GINFOERR
    lda #$F0
    sta DFIL+D_STOR
    lda #0
    sta REQL
    sta REQH
    jsr TSFRBLK
    ldy #VCBTFRE+1
    lda (VCBPTR),y
    sta REQH
    dey
    lda (VCBPTR),y
    sta REQL                        ; the free blocks
    dey
    lda (VCBPTR),y
    sta DFIL+D_AUXID+1              ; the volume's size
    tax
    dey
    lda (VCBPTR),y
    sta DFIL+D_AUXID
    sec
    sbc REQL
    sta DFIL+D_USAGE                ; less the free blocks
    txa
    sbc REQH
    sta DFIL+D_USAGE+1
GTINFO1:
    ldy #0
GTINFO2:
    lda INFTABL,y
    bpl GTINFO3                     ; an entry's byte
    and #$7F
    beq GTINFO4                     ; the end of file's fourth byte, 0
    cmp #D_STOR+1
    bne GINFOEND                    ; the end of the table
    lda DFIL+D_STOR
    lsr a
    lsr a
    lsr a
    lsr a
    bpl GTINFO4
GTINFO3:
    tax
    lda DFIL,x
GTINFO4:
    sta (C_FILIST),y
    iny
    cpy C_FILSTLN
    bne GTINFO2
GINFOEND:
    clc
GINFOERR:
    rts

;; SET_FILE_INFO: changes a file's attributes, type and auxiliary type, and optionally its modification time.
;;
;; Attribute bits 2-4 cannot be set (ACCSERR). The list's bytes up to the storage type are stored in the entry; a list
;; of 15 bytes or more also gives the modification date and time, and otherwise the entry gets the current ones.
;; The backup bit <DREVISE> sets comes from BACKMASK, which a backup program can clear.
;; In: C_PATH = the pathname, C_FILIST = the list, C_FILSTLN = its length
;; Out: carry = set on an error, A = the error code
;; Uses: X, Y
;; See: <GETINFO>, <INFTABL>, <DREVISE>
SETINFO:
    jsr FINDFILE
    bcs SINFOERR
    lda C_FILSTLN
    beq SINFEND
    ldy #0
    lda (C_FILIST),y
    and #$1C
    beq SETINF1
    lda #ACCSERR
    sec
    rts
SETINF1:
    lda BACKMASK
    sta BKBITFLG
SETINF1X:
    ldx INFTABL,y
    bmi SETINF2                     ; the storage type: the end of what may change
    lda (C_FILIST),y
    sta DFIL,x
    iny
    cpy C_FILSTLN
    bne SETINF1X
SINFEND:
    jmp DREVISE                     ; with the current time
SETINF2:
    ldy C_FILSTLN
    cpy #$F
    bcc SINFEND
    ldy #$B                         ; the modification date and time
SETINF3:
    ldx INFTABL,y
    bmi SINFEND1
    lda (C_FILIST),y
    sta DFIL,x
    iny
    cpy C_FILSTLN
    bne SETINF3
SINFEND1:
    jmp DREVISE1                    ; with the caller's time

;; The backup bit <DREVISE> sets in an entry's attributes: BKBITVAL for every call, BACKMASK for SET_FILE_INFO.
;;
;; Its initial contents are whatever was in memory when Apple built SOS.KERNEL; SOS sets it at run time.
;; See: <SETINFO>
BKBITFLG:
    .res 1, $A0

;; Where each byte of a GET_FILE_INFO or SET_FILE_INFO list is in the directory entry (an offset in DFIL).
;;
;; Bit 7 marks the special ones: D_STOR+1+$80 is the storage type, the high nibble of D_STOR; $80 is the end of
;; file's fourth byte, always 0; and $FF ends the table.
;; See: <GETINFO>, <SETINFO>
INFTABL:
    .byte D_ATTR, D_FILID, D_AUXID, D_AUXID+1
    .byte D_STOR+1+$80, D_EOF, D_EOF+1, D_EOF+2
    .byte $80, D_USAGE, D_USAGE+1, D_MODDT
    .byte D_MODDT+1, D_MODTM, D_MODTM+1, $FF

;; RENAME: gives a file, or a volume, a new name.
;;
;; A volume's new name must be a single name, and the volume must have no files open; the root directory's header and
;; the VCB get it. A file's new pathname must be on the same volume and in the same directory, and must not exist
;; yet (DUPERR). The file must not be open and its attributes must allow renaming. A directory's own header gets the
;; new name too.
;; In: C_PATH = the pathname, C_NWPATH = the new pathname
;; Out: carry = set on an error, A = the error code
;; Uses: X, Y
;; See: <RENPATH>, <MVROTNAM>, <LOOKFILE>, <DREVISE1>
RENAME:
    jsr LOOKFILE
    bcc RNAME0
    cmp #BADPATH                    ; a volume?
    bne RNAMERR
    jsr RENPATH
    bcs RNAMERR
    lda WRKPATH
    cmp PATHNML
    bne RNBADPTH                    ; more than a volume name
    ldy #VCBSTAT
    lda (VCBPTR),y
    bpl RNAMEVOL
    lda #FILBUSY
SINFOERR:
    rts                             ; carry is set
RNAMEVOL:
    ldy #0
    lda (WRKPATH),y
    tay
    ora #$F0
    jsr MVROTNAM
    bcs RNAMERR
    ldy #0
    lda (WRKPATH),y
    tay
RNMEVOL:
    lda (WRKPATH),y
    sta (VCBPTR),y
    dey
    bpl RNMEVOL
    clc
    rts
RNAME0:
    jsr RENPATH
    bcs RNAMERR
    ldy #0
    lda (PATHNML),y
    tay
TSTSMROT:
    lda (PATHNML),y
    cmp (VCBPTR),y
    bne RNBADPTH                    ; another volume
    dey
    bpl TSTSMROT
    jsr LOOKFILE
    bcs TSTFNF1
    lda #DUPERR
RNAMERR:
    sec
    rts
TSTFNF1:
    cmp #FNFERR
    bne RNAMERR
    ldx #2
SVENEWID:
    lda D_DEV,x
    sta NPATHDEV,x                  ; the directory the new name would go in
    dex
    bpl SVENEWID
    jsr SETPATH
    bcs RNAMERR
    jsr FINDFILE
    bcs RNAMERR
    jsr TSTOPEN
    lda #FILBUSY
    bcs RNAMERR
    lda DFIL+D_ATTR
    and #RENAMEN
    bne RNAME1
    lda #ACCSERR
    sec
    rts
RNAME1:
    ldx #2
SAMOWNR:
    lda D_DEV,x
    cmp NPATHDEV,x
    beq RNAME2
RNBADPTH:
    lda #BADPATH
    sec
    rts
RNAME2:
    dex
    bpl SAMOWNR
    jsr RENPATH
    bcs RNAMERR
    tya
    beq RNBADPTH
    dey                             ; the last name's length
RNAME3:
    lda (WRKPATH),y
    sta DFIL+D_STOR,y
    dey
    bne RNAME3
    lda DFIL+D_STOR
    and #$F0
    tax
    ora (WRKPATH),y
    sta DFIL+D_STOR                 ; the storage type with the new length
    cpx #DIRTYP*16
    bne RNAMDONE
    lda DFIL+D_FRST
    sta BLOKNML
    lda DFIL+D_FRST+1
    sta BLOKNMH
    jsr RDGBUF                      ; the directory's header block
    bcs RNAMERR
    ldy #0
    lda (WRKPATH),y
    tay
    ora #HEDTYP*16
    jsr MVROTNAM
    bcs RNAMERR
RNAMDONE:
    jmp DREVISE1

;; Puts a name in the header entry of the directory block in GBUF and writes the block back.
;; In: A = the storage type times 16 plus the name's length, Y = the length, WRKPATH = the name, a length byte first,
;;   BLOKNML/BLOKNMH = the block
;; Out: carry = set on an error, A = the error code
;; Uses: X, Y
;; See: <RENAME>, <WRTGBUF>
MVROTNAM:
    sta GBUF+4
MVHEDNAM:
    lda (WRKPATH),y
    sta GBUF+4,y
    dey
    bne MVHEDNAM
    jmp WRTGBUF

;; Checks the syntax of RENAME's new pathname, into PATHBUF.
;; In: C_NWPATH = the new pathname
;; Out: carry = set on an error, A = the error code, Y = the last name's length plus 1, WRKPATH = the last name
;;   (its length byte)
;; Uses: X
;; See: <SYNPATH>, <RENAME>
RENPATH:
    lda C_NWPATH
    sta TPATH
    lda C_NWPATH+1
    sta TPATH+1
    lda SSNWPATH
    sta SISTPATH
    jmp SYNPATH

;; Frees every block the index block in GBUF lists.
;; In: GBUF = the index block, BMTAB = the volume's bitmap buffer, VCBPTR = the volume's VCB
;; Out: carry = set on an error, A = the error code
;; Uses: X, Y, SAPTR
;; See: <DESTROY>, <DEALLOC>
DEALBLK:
    ldy #0
DALBLK1:
    sty SAPTR
    lda GBUF,y
    cmp GBUF+$100,y
    bne DALBLK2
    cmp #0
    beq DALBLK3                     ; no block there
DALBLK2:
    ldx GBUF+$100,y
    jsr DEALLOC
    bcs DALBLKERR
    ldy SAPTR
DALBLK3:
    iny
    bne DALBLK1
    clc
DALBLKERR:
    rts

;; DESTROY: deletes a file, freeing its blocks and its directory entry.
;;
;; The file must not be open, its attributes must allow it, and the device must not be write-protected. A seed's,
;; sapling's or tree's index blocks are walked and every block freed; a sapling is handled as a tree whose top index
;; lists only it. A directory must be empty, and its blocks are freed along their links. The entry is then marked
;; free, the directory's file count goes down, the bitmap is written out, the volume's free count goes up by the
;; file's size, and the next allocation searches from the volume's first bitmap.
;; In: C_PATH = the pathname
;; Out: carry = set on an error, A = the error code
;; Uses: X, Y
;; See: <DEALBLK>, <DEALLOC>, <GTTINDX>, <TSTOPEN>, <DREVISE>
DESTROY:
    jsr FINDFILE
    bcs DESTERR
    jsr TSTOPEN
    lda TOTENT
    beq DSTROY1
    lda #FILBUSY
    sec
    rts
DSTROY1:
    lda #0
    sta REQL
    sta REQH
    jsr TSFRBLK                     ; brings the free count up to date
    bcc DSTROY2
    cmp #OVRERR
    sec
    bne DESTERR
DSTROY2:
    lda DFIL+D_ATTR
    and #DSTROYEN
    bne DSTROY3
    lda #ACCSERR
    jsr SYSERR
DSTROY3:
    jsr TWRPROT1
    bcs DESTERR
    lda DFIL+D_STOR
    and #$F0
    cmp #((TRETYP+1)*$10)
    bcc DSTREE
    jmp DSTDIR
DSTREE:
    jsr GTTINDX
    bcs DESTERR
    lda DFIL+D_STOR
    and #$F0
    cmp #TRETYP*$10
    bne DSTSAP
    jsr RDFRST                      ; a tree's top index
    bcc DSTRE2
DESTERR:
    rts
DSTSAP:
    cmp #SAPTYP*$10
    bne DSTLAST                     ; a seed: only its one block
    jsr ZTMPIDX
    lda DFIL+D_FRST                 ; a top index that lists the sapling's index
    ldy #0
    sta (TINDX),y
    inc TINDX+1
    lda DFIL+D_FRST+1
    sta (TINDX),y
    dec TINDX+1
DSTRE2:
    ldy #0
DSTNXT:
    sty TREPTR
    lda (TINDX),y
    inc TINDX+1
    cmp (TINDX),y
    bne DSTRE3
    cmp #0
    beq DSTRE4                      ; no index there; carry is set
DSTRE3:
    clc
    sta BLOKNML
    lda (TINDX),y
    sta BLOKNMH
DSTRE4:
    dec TINDX+1
    bcs DSTNXT1
    jsr RDGBUF
    bcs DESTERR
    jsr DEALBLK                     ; its data blocks
    bcs DESTERR
    ldy TREPTR
    inc TINDX+1
    lda (TINDX),y
    tax
    dec TINDX+1
    lda (TINDX),y
    jsr DEALLOC                     ; and the index itself
    bcs DESTERR
    ldy TREPTR
DSTNXT1:
    iny
    bne DSTNXT
DSTLAST:
    lda DFIL+D_FRST
    ldx DFIL+D_FRST+1
    jsr DEALLOC
    bcs DESTERR
    lda #0
    sta DFIL+D_STOR                 ; the entry is free
    cmp H_FCNT
    bne DST1
    dec H_FCNT+1
DST1:
    dec H_FCNT
    ldx BMTAB
    jsr BMAPUP
    bcs DESTERR
    ldy #VCBTFRE
    lda DFIL+D_USAGE
    adc (VCBPTR),y
    sta (VCBPTR),y
    iny
    lda DFIL+D_USAGE+1
    adc (VCBPTR),y
    sta (VCBPTR),y
    lda #0
    ldy #VCBCMAP
    sta (VCBPTR),y
    jmp DREVISE
DSTDIR:
    cmp #DIRTYP*16
    beq DSDIR1
    lda #CPTERR
    jsr SYSERR
DSDIR1:
    jsr FNDBMAP
    bcs DSDIRERR
    lda DFIL+D_FRST
    sta BLOKNML
    lda DFIL+D_FRST+1
    sta BLOKNMH
    jsr RDGBUF
    bcs DSDIRERR
    lda GBUF+HCENT+4
    bne DSDIRACC                    ; it has files
    lda GBUF+HCENT+5
    beq DSDIR2
DSDIRACC:
    lda #ACCSERR
    jsr SYSERR
DSDIR2:
    lda GBUF+2
    cmp GBUF+3
    bne DSDIR3
    cmp #0
    beq DSTLAST                     ; no next block: free the first
DSDIR3:
    ldx GBUF+3
    jsr DEALLOC
    bcs DSDIRERR
    lda GBUF+2
    sta BLOKNML
    lda GBUF+3
    sta BLOKNMH
    jsr RDGBUF
    bcc DSDIR2
DSDIRERR:
    rts

; ---------------------------------------------------------------------------------------------------------------------
; The work space. Its initial contents are whatever was in memory when Apple built SOS.KERNEL; SOS sets it at run
; time.
; ---------------------------------------------------------------------------------------------------------------------

;; The BFM's work space: the header of the directory being worked on, the directory entry being worked on, and
;; scratch storage.
;;
;; The header part follows the order of a directory header from its creation date on, so that it can be copied in
;; one move; the entry part, from <D_DEV> to <D_ENTNUM>, follows an FCB's order from FCBDEVN to FCBENTN.
;; See: <DFIL>, <MOVHED0>
WORKSPC:
V_STATUS:                           ;; the volume's status: bit 7 set when it has files open
    .res 1, $A0

;; The directory's creation date (two bytes), followed by its creation time (two), the SOS version that made it and
;; the oldest version it works with.
H_CREDT:
    .res 2, $A0
    .byte $F9, $A0                  ; the creation time
    .res 1, $95                     ; the version that made it
    .res 1, $A1                     ; the oldest compatible version
H_ATTR:                             ;; the directory's attributes
    .res 1, $AE
H_ENTLN:                            ;; the length of each entry in the directory
    .res 1, $A0
H_MAXENT:                           ;; the number of entries in each directory block
    .res 1, $A0

;; The number of files in the directory, followed by the volume's first bitmap block, the volume's size in blocks
;; and five reserved bytes.
H_FCNT:
    .byte $CC, $D3
    .byte $80, $B6                  ; the first bitmap block
    .byte $E5, $A0                  ; the volume's size
    .byte $81, $9A, $A0, $D3, $A0   ; reserved
D_DEV:                              ;; the device the entry's volume is on
    .res 1, $94
D_HEAD:                             ;; the header block of the entry's directory
    .byte $A0, $D2
D_ENTBLK:                           ;; the directory block that holds the entry
    .byte $A0, $D5
D_ENTNUM:                           ;; the entry's number in its block, from 1
    .res 1, $88

;; The directory entry being worked on, as it is on the disk; the D_ names are offsets in it.
;; See: <INFTABL>, <MOVENTRY>, <DREVISE>
DFIL:
D_STOR = * - DFIL                   ;; the storage type times 16 plus the name's length
    .res 1, $A0
    .byte $D5, $98, $A0, $F0, $99, $D3, $CC, $A0, $BA, $A0, $A0, $C6, $A0, $A0, $C5 ; the name, 15 bytes
D_FILID = * - DFIL                  ;; the file's type
    .res 1, $A0
D_FRST = * - DFIL                   ;; the file's first block, its key block
    .byte $CF, $D3
D_USAGE = * - DFIL                  ;; the blocks the file uses
    .byte $A0, $CC
D_EOF = * - DFIL                    ;; the end of file, three bytes
    .byte $A0, $C9, $A4
D_CREDT = * - DFIL                  ;; the creation date, then the creation time and the version that made the file
    .byte $96, $A0
    .byte $D3, $AE                  ; the creation time
    .res 1, $C3                     ; the version that made the file
D_COMP = * - DFIL                   ;; the oldest version the file works with; this SOS opens only 0
    .res 1, $C8
D_ATTR = * - DFIL                   ;; the access attributes: destroy, rename, backup, write and read enables
    .res 1, $AA
D_AUXID = * - DFIL                  ;; the auxiliary type
    .res 2, $A0
D_MODDT = * - DFIL                  ;; the date of the last change
    .byte $A0, $C5
D_MODTM = * - DFIL                  ;; the time of the last change
    .byte $85, $A0
D_DHDR = * - DFIL                   ;; the header block of the directory the entry is in
    .res 2, $A0
CMDADR:                             ;; the address of the routine for the BFM call being made
    .byte $8E, $AE

;; Scratch storage: the block <ALC1BLK> allocates, the mark plus the count in READ and WRITE, and other passing
;; values.
SCRTCH:
    .byte $BF, $A0, $A0, $CD, $A0, $C9, $C1, $A0, $9A, $A0, $A0, $FF, $84
OLDEOF:                             ;; the end of file before a WRITE or SET_EOF, to put back after an error
    .byte $A0, $FF, $BF
OLDMARK:                            ;; the mark before <RDPOSN> last moved it, for WRITE to put back after an error
    .byte $9A, $A0, $CE
SCRHIGH = >(SCRTCH)                 ;; the page SCRTCH is in
    .include "SwapOutIn.asm"
