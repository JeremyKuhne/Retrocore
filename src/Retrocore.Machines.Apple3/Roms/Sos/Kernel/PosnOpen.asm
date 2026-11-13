; ---------------------------------------------------------------------------------------------------------------------
; Block file manager: GET_MARK, SET_MARK and OPEN, and positioning in a file.
;
; An open file has a 32-byte file control block (FCB), FCBPTR, and a buffer of four pages from the buffer manager:
; the data block at DATPTR and, after it at TINDX, the index block, its entries' low bytes in the first page and their
; high bytes in the second. A seed file is one data block, a sapling has one index block and a tree has a top index
; whose entries are sapling index blocks, so one index block covers 128K of the file. The FCB's status byte (FCBSTAT)
; says which buffered blocks have changes and which blocks the position needs that do not exist yet: <RDPOSN> leaves
; them missing, zeroed in the buffer, and WRITE allocates them.
;
; The device calls the BFM makes for whole blocks are here too (<DOFILEIO>, <FILEIO2>).
; ---------------------------------------------------------------------------------------------------------------------

;; GET_MARK: returns the open file's position, the mark, as four bytes.
;; In: FCBPTR = the file's FCB, C_MRKPTR = where the position goes
;; Out: carry = clear
;; Uses: A, Y
;; See: <SETMARK>
GETMARK:
    ldy #FCBMARK
GMARK1:
    lda (FCBPTR),y
    pha                             ; the mark's three bytes onto the stack
    iny
    cpy #FCBMARK+3
    bne GMARK1
    lda #0
    ldy #3
    pha                             ; and a zero top byte
MOVMRK:
    pla
    sta (C_MRKPTR),y
    dey
    bpl MOVMRK
    clc
    rts

;; SET_MARK: moves the open file's position, which must stay within the end of file.
;; In: FCBPTR = the file's FCB, C_BASE = what the position is relative to (see <ADJMARK>), C_MARK = the position
;; Out: carry = set on an error, A = the error code (POSNERR for a position beyond the end of file)
;; Uses: X, Y
;; See: <ADJMARK>, <RDPOSN>, <GETMARK>
SETMARK:
    jsr ADJMARK
    bcc SMARK1
    rts
SMARK1:
    ldx #2
    ldy #FCBEOF+2
CMPEOF:
    lda TPOSLL,x
    cmp (FCBPTR),y
    bcc CKSAMBLK                    ; below the end of file
    bne ERRMEOF
    dey
    dex
    bpl CMPEOF
    bmi CKSAMBLK                    ; at the end of file
ERRMEOF:
    lda #POSNERR
    rts

;; Works out the position a SET_MARK or SET_EOF call asks for, in TPOSLL, TPOSLH and TPOSHI.
;;
;; The call's position is a four-byte number whose top byte must be 0. By C_BASE, it is the position itself (0), a
;; distance back from the end of file (1), forward from the mark (2) or back from the mark (3). A result below 0 or
;; beyond three bytes is an error.
;; In: FCBPTR = the file's FCB, C_BASE = the base, C_MARK = the number
;; Out: carry = set on an error, A = POSNERR, TPOSLL/TPOSLH/TPOSHI = the position
;; Uses: X, Y
;; See: <SETMARK>, <SETEOF>
ADJMARK:
    lda C_MARK+3
    bne ERRPOSN
    ldx #$FD                        ; counts up to 0 over the three bytes
    ldy #FCBMARK
    lda C_BASE
    lsr a
    bcs SUBMARK                     ; 1 or 3: subtract
    beq ADJMRK                      ; 0: the position itself
ADDPOSN:
    lda (FCBPTR),y
    adc C_MARK+3,x                  ; C_MARK+3+$FD wraps round to C_MARK in page zero
    sta <(TPOSLL-$FD),x
    iny
    inx
    bne ADDPOSN
    bcs ERRPOSN
    beq ADJMRK1
SUBMARK:
    bne SUBPOSN                     ; 3: from the mark
    ldy #FCBEOF                     ; 1: from the end of file
SUBPOSN:
    lda (FCBPTR),y
    sbc C_MARK+3,x
    sta <(TPOSLL-$FD),x
    iny
    inx
    bne SUBPOSN
    bcs ADJMRK1
ERRPOSN:
    lda #POSNERR
    sec
    rts
ADJMRK:
    ldx #2
ADJMRK0:
    lda C_MARK,x
    sta TPOSLL,x
    dex
    bpl ADJMRK0
ADJMRK1:
    clc
    rts

;; Moves an open file's mark to TPOSLL/TPOSLH/TPOSHI, reading in the blocks the new position needs.
;;
;; A position in the data block already buffered only moves the mark. Otherwise the volume is checked first, when a
;; disk switch was seen, and the operator is asked for it if it is missing. The buffered data block, and the index
;; block if the position needs another, are written out if they have changes. Then the index blocks the file's
;; storage type calls for are followed down to the data block, which is read in. A block that has not been allocated
;; stops the walk: its bit (and those below it) is set in FCBSTAT and the buffers below it are zeroed, ready for
;; WRITE to allocate them. Directory files move a block at a time along their links instead (<DIRMARK>).
;;
;; The old mark is kept in <OLDMARK>, and POSPTR is set to the buffer page of the position.
;; In: FCBPTR = the file's FCB, TPOSLL/TPOSLH/TPOSHI = the position, DATPTR and TINDX = the file's buffers
;; Out: carry = set on an error, A = the error code, FCBMARK = the position, POSPTR = its page in the data buffer
;; Uses: X, Y, LEVELS, SCRTCH, CNTENT, DEVNUM, BLOKNML/BLOKNMH
;; See: <SETMARK>, <SVMARK>, <RFCBDAT>, <WFCBDAT>, <WFCBIDX>
RDPOSN:
CKSAMBLK:
    ldy #FCBMARK+1
    lda (FCBPTR),y
    and #$FE
    sta SCRTCH                      ; the 512-byte block the mark is in
    iny
    lda TPOSLH
    sec
    sbc SCRTCH
    sta SCRTCH                      ; how many pages on the new position is
    bcc TYPMARK
    cmp #2
    bcs TYPMARK
    lda TPOSHI
    cmp (FCBPTR),y
    bne TYPMARK
    jmp SVMARK                      ; the same block: only the mark moves
TYPMARK:
    ldy #FCBSTYP
    lda (FCBPTR),y
    beq FERRTYP                     ; no storage type: not a real FCB
    cmp #4
    bcc CHKDSKSW                    ; seed, sapling or tree
    jmp DIRMARK
CHKDSKSW:
    ldy #FCBDEVN
    lda (FCBPTR),y
    sta DEVNUM
    jsr TWRPROT1                    ; a status call notes a disk switch in DSWGLOB
    lda DSWGLOB
    beq TREPOS
CHKDSKS1:
    jsr VERFYVOL
    bcc TREPOS                      ; the volume is still there
    jsr USRREQ
    bcc CHKDSKS1
    lda #VNFERR
    rts
FERRTYP:
    ldy #FCBREFN
    sta (FCBPTR),y                  ; free the FCB
    lda #BADREFNUM
    sec
    rts
TREPOS:
    ldy #FCBSTYP
    lda (FCBPTR),y
    sta LEVELS                      ; 1 seed, 2 sapling, 3 tree
    ldy #FCBSTAT
    lda (FCBPTR),y
    and #DATMOD
    beq POSNEW1
    jsr WFCBDAT                     ; another data block: write this one first
    bcs POSERR
POSNEW1:
    ldy #FCBMARK+2
    lda (FCBPTR),y
    and #$FE
    sta SCRTCH
    lda TPOSHI
    sec
    sbc SCRTCH
    bcc POSNEW2
    cmp #2
    bcs POSNEW2                     ; another 128K: another index block
    ldx LEVELS
    dex
    bne DATLEVEL                    ; the index block in the buffer serves
TSTINY:
    lda TPOSLH
    lsr a
    ora TPOSHI
    bne NOIDXDAT                    ; a seed's position past its one block
    ldy #FCBFRST
    lda (FCBPTR),y
    sta BLOKNML
    iny
    lda (FCBPTR),y
    jmp RNEWPOS                     ; a seed's first block is its data
POSNEW2:
    ldy #FCBSTAT
    lda (FCBPTR),y
    and #IDXMOD
    beq POSNIDX
    jsr WFCBIDX
    bcs POSERR
POSNIDX:
    ldx LEVELS
    cpx #3
    beq POSINDEX
    lda TPOSHI
    lsr a
    php
    lda #TOPALC+IDXALC+DATALC
    plp
    bne NODATA                      ; past 128K: a top index is needed
    jsr CLRSTATS
    dex
    beq TSTINY
    jsr RFCBFST                     ; a sapling's first block is its index
    bcs POSERR
    ldy #FCBIDXB
    lda BLOKNML
    sta (FCBPTR),y
    iny
    lda BLOKNMH
    sta (FCBPTR),y
    bcc DATLEVEL
POSERR:
    sec
    rts
POSINDEX:
    jsr CLRSTATS
    jsr RFCBFST                     ; a tree's first block is its top index
    bcs POSERR
    lda TPOSHI
    lsr a
    tay                             ; one entry for each 128K
    lda (TINDX),y
    inc TINDX+1
    cmp (TINDX),y
    bne SAPLEVEL
    cmp #0
    bne SAPLEVEL
    dec TINDX+1
NOIDXDAT:
    lda #IDXALC+DATALC
    jmp NODATA
SAPLEVEL:
    sta BLOKNML
    lda (TINDX),y
    sta BLOKNMH
    dec TINDX+1
    jsr RFCBIDX
    bcs POSERR
DATLEVEL:
    lda TPOSHI
    lsr a
    lda TPOSLH
    ror a
    tay                             ; the data block's entry in the index
    lda (TINDX),y
    inc TINDX+1
    cmp (TINDX),y
    bne POSNEW3
    cmp #0
    bne POSNEW3
    lda #DATALC                     ; no data block
    dec TINDX+1
NODATA:
    ldy #FCBSTAT
    ora (FCBPTR),y
    sta (FCBPTR),y
    lsr a
    lsr a                           ; carry = IDXALC: the index is missing too
    jsr ZIPDATA
    bcc SVMARK
ZIPIDX:
    sta (TINDX),y
    iny
    bne ZIPIDX
    inc TINDX+1
ZPIDX1:
    sta (TINDX),y
    iny
    bne ZPIDX1
    dec TINDX+1
    jmp SVMARK

;; Zeroes the data buffer, both pages at DATPTR.
;; In: DATPTR = the buffer
;; Out: A = 0, Y = 0
;; Keeps: X, carry
;; See: <RDPOSN>
ZIPDATA:
    lda #0
    tay
ZIPDAT0:
    sta (DATPTR),y
    iny
    bne ZIPDAT0
    inc DATPTR+1
ZPDAT1:
    sta (DATPTR),y
    iny
    bne ZPDAT1
    dec DATPTR+1
    rts
POSNEW3:
    sta BLOKNML
    lda (TINDX),y
    dec TINDX+1
RNEWPOS:
    sta BLOKNMH
    jsr RFCBDAT
    bcs PRITZ
    jsr CLRSTATS                    ; every level of the position exists

;; Sets the open file's mark to TPOSLL/TPOSLH/TPOSHI, keeping the old one in <OLDMARK>, and points POSPTR at the page
;; of the data buffer the position is in.
;; In: FCBPTR = the file's FCB, DATPTR = its data buffer
;; Out: carry = clear, POSPTR = the page
;; Uses: A, X, Y
;; See: <RDPOSN>
SVMARK:
    ldy #FCBMARK+2
    ldx #2
SVMRK1:
    lda (FCBPTR),y
    sta OLDMARK-FCBMARK,y
    lda TPOSLL,x
    sta (FCBPTR),y
    dey
    dex
    bpl SVMRK1
    clc
    lda DATPTR
    sta POSPTR
    lda TPOSLH
    and #1
    adc DATPTR+1
    sta POSPTR+1
    lda SISDATP
    sta SISPOSP
    rts
PRITZ:
    sec
    rts

;; Clears FCBSTAT's bits that say a data, index or top index block is missing for the position.
;; In: FCBPTR = the file's FCB
;; Uses: A, Y
;; Keeps: X, carry
;; See: <RDPOSN>
CLRSTATS:
    ldy #FCBSTAT
    lda (FCBPTR),y
    and #$FF-TOPALC-IDXALC-DATALC
    sta (FCBPTR),y
    rts

;; Positions a directory file, reading block by block along its links from the buffered block to the new one.
;;
;; Each directory block starts with the previous block's number and the next one's. Other storage types are not
;; compatible with this SOS and fail with CPTERR, through <SYSERR>. A missing link is EOFERR.
;; In: A = the storage type, SCRTCH = how many pages forward (negative for back) the position is
;; Out: carry = set on an error, A = the error code
;; See: <RDPOSN>
DIRMARK:
    cmp #DIRTYP
    beq DIRPOS
    lda #CPTERR
    jsr SYSERR
DIRPOS:
    lda SCRTCH
    lsr a
    sta CNTENT                      ; the blocks to move
    ldy #FCBMARK+1
    lda (FCBPTR),y
    cmp TPOSLH
    bcc DIRFWRD
DIRVRSE:
    ldy #0                          ; the previous block's link
    jsr DIRPOS1
    bcs DRPOSERR
    inc CNTENT                      ; counts up to $80
    bpl DIRVRSE
    bmi SVMARK
DIRFWRD:
    ldy #2                          ; the next block's link
    jsr DIRPOS1
    bcs DRPOSERR
    dec CNTENT
    bne DIRFWRD
    beq SVMARK
DIRPOS1:
    lda (DATPTR),y
    sta BLOKNML
    iny
    cmp (DATPTR),y
    bne DIRPOS2
    cmp #0
    bne DIRPOS2
    lda #EOFERR                     ; no block there
DRPOSERR:
    sec
    rts
DIRPOS2:
    lda (DATPTR),y
    sta BLOKNMH

;; Reads block BLOKNML/BLOKNMH into the open file's data buffer and makes it the FCB's current data block.
;; In: FCBPTR = the file's FCB, DATPTR = its data buffer, BLOKNML/BLOKNMH = the block
;; Out: carry = set on an error, A = the error code
;; Uses: X, Y
;; See: <RFCBIDX>, <FILEIO1>
RFCBDAT:
    lda #RDCMD
    sta DHPCMD
    ldx #DATPTR
    jsr FILEIO1
    ldy #FCBDATB
    bcc FCBLOKNM
    rts

;; Reads block BLOKNML/BLOKNMH into the open file's index buffer and makes it the FCB's current index block.
;; In: FCBPTR = the file's FCB, TINDX = its index buffer, BLOKNML/BLOKNMH = the block
;; Out: carry = set on an error, A = the error code
;; Uses: X, Y
;; See: <RFCBDAT>, <FILEIO1>
RFCBIDX:
    lda #RDCMD
    sta DHPCMD
    ldx #TINDX
    jsr FILEIO1
    bcs RDFCBERR
    ldy #FCBIDXB
FCBLOKNM:
    lda BLOKNML
    sta (FCBPTR),y
    iny
    lda BLOKNMH
    sta (FCBPTR),y
    clc
RDFCBERR:
    rts

;; Reads the open file's first block (its key block) into the index buffer.
;; In: FCBPTR = the file's FCB, TINDX = its index buffer
;; Out: carry = set on an error, A = the error code, BLOKNML/BLOKNMH = the block
;; Uses: X, Y
;; See: <DOFILEIO>, <WFCBFST>
RFCBFST:
    ldx #TINDX
    ldy #FCBFRST
    lda #RDCMD

;; Reads or writes one of an open file's blocks, whose number is in its FCB, through one of its buffers.
;;
;; Block 0 is never a file's block: finding it means the FCB is broken, and SOS stops with ALCERR (<SYSDEATH>).
;; In: A = the command, X = the page-zero pointer to the buffer (DATPTR or TINDX), Y = the block number's offset in
;;   the FCB, FCBPTR = the file's FCB
;; Out: carry = set on an error, A = the error code, BLOKNML/BLOKNMH = the block
;; Uses: X, Y
;; See: <FILEIO1>, <WFCBDAT>, <WFCBIDX>, <WFCBFST>
DOFILEIO:
    sta DHPCMD
    lda (FCBPTR),y
    sta BLOKNML
    iny
    cmp (FCBPTR),y
    bne FILEIO
    cmp #0
    bne FILEIO
    lda #ALCERR
    jsr SYSDEATH
FILEIO:
    lda (FCBPTR),y
    sta BLOKNMH

;; Reads or writes block BLOKNML/BLOKNMH of an open file's device through a buffer a page-zero pointer names.
;;
;; The pointer is first moved into the next bank pair if it would cross out of its own (<WRAPADJ>).
;; In: X = the page-zero pointer to the buffer, DHPCMD = the command, BLOKNML/BLOKNMH = the block, FCBPTR = the FCB
;; Out: carry = set on an error, A = the error code
;; Uses: X, Y, DEVNUM
;; See: <FILEIO2>, <WRAPADJ>
FILEIO1:
    lda 0,x
    sta DBUFPL
    jsr WRAPADJ
    lda 1,x
    sta DBUFPH
    lda SISTER+1,x
    sta SISBPH
    ldy #FCBDEVN
    lda (FCBPTR),y
    sta DEVNUM

;; Reads or writes one 512-byte block through the device manager, its command, buffer and block already set.
;;
;; A disk-switch error (XDISKSW) from the driver repeats the request with the parameters saved in <RPTBLOK>; other
;; errors are returned. IOACCESS is set, to say that a full request has gone to the device, so that later blocks may
;; use the repeat command. The count of bytes read goes to <TRASH>.
;; In: DHPCMD = the command, DBUFPL/DBUFPH and SISBPH = the buffer, BLOKNML/BLOKNMH = the block, DEVNUM = the device
;; Out: carry = set on an error, A = the error code
;; Uses: Y
;; Entry: RPEATIO1 = only sets the unit from DEVNUM, the count and buffer already set, RPEATIO0 = calls the device
;;   manager with the parameters at DEVICE as they are
;; See: <DMGR>, <DOFILEIO>
FILEIO2:
    lda #2
    sta RQCNTH                      ; 512 bytes
    sta IOACCESS
    lda #<TRASH
    sta BRDPTR
    lda #>TRASH
    sta BRDPTR+1
    lda #0
    sta RQCNTL
    sta SSBRDPH
RPEATIO1:
    lda DEVNUM
    sta UNITNUM
RPEATIO0:
    ldy #$9
SAVPRMS:
    lda DEVICE,y
    sta RPTBLOK,y                   ; keep the request to repeat it
    dey
    bpl SAVPRMS
DMGRGO:
    lda #0
    sta SERR
    jsr DMGR
    bcc RRITZ
    cmp #XDISKSW
    beq RPEATIO2
    sec
RRITZ:
    rts
RPEATIO2:
    ldy #$9
GETPRMS:
    lda RPTBLOK,y
    sta DEVICE,y
    dey
    bpl GETPRMS
    jmp DMGRGO

;; Where block transfers put the device manager's count of bytes read, which the BFM does not need.
;;
;; Its initial contents are whatever was in memory when Apple built SOS.KERNEL; SOS sets it at run time.
;; See: <FILEIO2>
TRASH:
    .byte $D4, $D1

;; A copy of the ten device-call parameters at DEVICE ($C0-$C9), to repeat a request after a disk switch.
;;
;; Its initial contents are whatever was in memory when Apple built SOS.KERNEL; SOS sets it at run time.
;; See: <FILEIO2>
RPTBLOK:
    .byte $A0, $85, $A0, $A0, $8D, $A0, $80, $A0, $A0, $84

;; Writes the index buffer to the open file's first block, after making sure the device's bitmap is on the disk.
;; In: FCBPTR = the file's FCB, TINDX = its index buffer
;; Out: carry = set on an error, A = the error code
;; Uses: X, Y
;; See: <UPBMAP>, <DOFILEIO>, <RFCBFST>
WFCBFST:
    ldy #FCBDEVN
    lda (FCBPTR),y
    tax
    jsr UPBMAP
    ldx #TINDX
    ldy #FCBFRST
    lda #WRTCMD
    jmp DOFILEIO

;; Writes the open file's data buffer to its current data block and clears the changed bit, DATMOD.
;; In: FCBPTR = the file's FCB, DATPTR = its data buffer
;; Out: carry = set on an error, A = the error code
;; Uses: X, Y
;; See: <WFCBIDX>, <DOFILEIO>
WFCBDAT:
    ldx #DATPTR
    ldy #FCBDATB
    lda #WRTCMD
    jsr DOFILEIO
    bcs FILIOERR
    lda #$FF-DATMOD
    jmp FCBUPDAT

;; Writes the open file's index buffer to its current index block and clears the changed bit, IDXMOD.
;;
;; The device's bitmap is written out first, so that a block the index names is never free on the disk.
;; In: FCBPTR = the file's FCB, TINDX = its index buffer
;; Out: carry = set on an error, A = the error code
;; Uses: X, Y
;; See: <WFCBDAT>, <UPBMAP>, <DOFILEIO>
WFCBIDX:
    ldy #FCBDEVN
    lda (FCBPTR),y
    tax
    jsr UPBMAP
    ldx #TINDX
    ldy #FCBIDXB
    lda #WRTCMD
    jsr DOFILEIO
    bcs FILIOERR
    lda #$FF-IDXMOD
FCBUPDAT:
    ldy #FCBSTAT
    and (FCBPTR),y                  ; carry is kept
    sta (FCBPTR),y
FILIOERR:
    rts

;; OPEN: opens a file on a block device and returns its reference number.
;;
;; A file another FCB has open for writing, or one to be opened for writing while it is open, is FILBUSY. The FCB gets
;; the file's directory entry place, storage type, access, first block, end of file and size. The access the open
;; list asks for must be one the file's attributes allow (by default, the attributes' read and write bits), and a
;; directory is only read. The file must be compatible with this SOS (D_COMP = 0) and a seed, sapling, tree or
;; directory file. The open list may give a buffer of its own (at least four pages, two for a directory); otherwise the
;; buffer manager gives one. A tree file's mark is then set to 0, which reads its first data block; a directory's first
;; block is read. The volume's open count goes up and its VCB is marked as having files open.
;; In: C_PATH = the pathname, C_OPLIST/C_OPLSTLN = the open list and its length, C_OUTREF = where the number goes
;; Out: carry = set on an error, A = the error code, the reference number at C_OUTREF
;; Uses: X, Y
;; See: <TSTOPEN>, <RDPOSN>, <REQBUF>, <REQFXBUF>, <CLOSE>
OPEN:
    jsr FINDFILE
    bcc OPEN0
    cmp #BADPATH                    ; a volume's root directory may be opened
    bne ERROPN
OPEN0:
    jsr TSTOPEN
    bcc OPEN1
ERRBUSY:
    lda #FILBUSY
ERROPN:
    sec
    rts
OPEN1:
    lda DATPTR                      ; the free FCB TSTOPEN found
    sta FCBPTR
    lda DATPTR+1
    sta FCBPTR+1
    bne ASGNFCB
    lda #FCBFULL
    sec
    rts
ASGNFCB:
    ldy #$1F
    lda #0
CLRFCB:
    sta (FCBPTR),y
    dey
    bpl CLRFCB
    ldy #FCBENTN
FCBOWNR:
    lda D_DEV-1,y                   ; D_DEV..D_ENTNUM are in the FCB's order
    sta (FCBPTR),y
    dey
    bne FCBOWNR
    lda DFIL+D_STOR
    lsr a
    lsr a
    lsr a
    lsr a
    tax                             ; the storage type, without the name's length
    ldy #FCBSTYP
    sta (FCBPTR),y
    lda C_OPLSTLN
    beq DEFOPEN
    ldy #0
    lda (C_OPLIST),y
    beq DEFOPEN
    and DFIL+D_ATTR
    cmp (C_OPLIST),y
    beq SVATTRB
    lda #ACCSERR
    sec
    rts
DEFOPEN:
    lda DFIL+D_ATTR
    and #READEN+WRITEN
SVATTRB:
    ldy #FCBATTR
    cpx #DIRTYP
    bne SVATTR1
    and #READEN
SVATTR1:
    sta (FCBPTR),y
    and #WRITEN
    beq OPEN2
    lda TOTENT
    bne ERRBUSY                     ; open elsewhere: no writing
OPEN2:
    lda DFIL+D_COMP
    beq OPEN3
ERRCMPAT:
    lda #CPTERR
    sec
    rts
OPEN3:
    cpx #TRETYP+1
    bcc OPEN4
    cpx #DIRTYP
    bne ERRCMPAT
OPEN4:
    ldy #FCBFRST
    lda DFIL+D_FRST
    sta (FCBPTR),y
    sta BLOKNML
    iny
    lda DFIL+D_FRST+1
    sta (FCBPTR),y
    sta BLOKNMH
    ldy #FCBEOF
EOFCBMV:
    lda DFIL+D_EOF-FCBEOF,y
    sta (FCBPTR),y
    iny
    cpy #FCBEOF+3
    bne EOFCBMV
    lda DFIL+D_USAGE
    sta (FCBPTR),y
    iny
    lda DFIL+D_USAGE+1
    sta (FCBPTR),y
    lda C_OPLSTLN
    beq DEFBUFR
    cmp #1
    beq DEFBUFR                     ; only the access
    cmp #4
    beq UBUFSPEC                    ; the access, a page count and an address
    lda #BADLSTCNT
    sec
    rts
UBUFSPEC:
    ldy #1
    lda (C_OPLIST),y
    beq DEFBUFR                     ; no pages: the buffer manager's buffer
    cpx #TRETYP+1
    bcc ONEKTST
    cmp #2
    bcs FIXDBUF
ERRBTS:
    lda #BTSERR
    sec
    rts
ONEKTST:
    cmp #4
    bcc ERRBTS
FIXDBUF:
    jsr REQFXBUF
    bcc FCBUFFER
ERROPN1:
    rts
DEFBUFR:
    lda #4
    cpx #TRETYP+1
    bcc BUFREQST
    lda #2
BUFREQST:
    jsr REQBUF
    bcs ERROPN1
FCBUFFER:
    ldy #FCBBUFN
    sta (FCBPTR),y
    jsr GTBUFFRS
    bcs ERROPEN2
    ldy #FCBREFN
    lda CNTENT
    sta (FCBPTR),y                  ; the reference number claims the FCB
    ldy #FCBLEVL
    lda LEVEL
    sta (FCBPTR),y
    ldy #FCBSTYP
    lda (FCBPTR),y
    cmp #TRETYP+1
    bcs OPNDIR
    lda #$FF
    ldy #FCBMARK
OPNPOS:
    sta (FCBPTR),y                  ; a mark no block holds, so the next position reads one
    iny
    cpy #FCBMARK+3
    bne OPNPOS
    ldy #2
    lda #0
OPNPOS1:
    sta TPOSLL,y
    dey
    bpl OPNPOS1
    jsr RDPOSN
    bcc OPENDONE
ERROPEN2:
    pha
    ldy #FCBBUFN
    lda (FCBPTR),y
    jsr RELBUF
    ldy #FCBREFN
    lda #0
    sta (FCBPTR),y
    pla
    sec
    rts
OPNDIR:
    jsr RFCBDAT
    bcs ERROPEN2
OPENDONE:
    ldy #VCBOPNC
    lda (VCBPTR),y
    clc
    adc #1
    sta (VCBPTR),y
    ldy #VCBSTAT
    lda (VCBPTR),y
    ora #$80                        ; the volume has files open
    sta (VCBPTR),y
    ldy #FCBREFN
    lda (FCBPTR),y
    ldy #0
    sta (C_OUTREF),y
    clc
    rts

;; Looks through the FCBs for the first free one and for others that have the file in D_DEV..D_ENTNUM open.
;;
;; The FCBs fill two pages at FCBADDRH, 32 bytes each; a reference number is an FCB's place, from 1. FCBs whose volume
;; is swapped out do not count. The scan stops at the first FCB that has the file open for writing.
;; In: D_DEV..D_ENTNUM = the file's directory entry place
;; Out: carry = set when an FCB has the file open for writing, DATPTR = the free FCB (high byte 0 for none),
;;   CNTENT = its reference number, TOTENT = the number of FCBs found with the file open
;; Uses: A, X, Y, FCBPTR
;; See: <OPEN>, <DESTROY>, <RENAME>
TSTOPEN:
    lda a:FCBADDRH
    sta FCBPTR+1
    lda FCBANKNM
    sta SISFCBP
    lda #0
    sta DATPTR+1
    sta CNTENT
    sta TOTENT
TSTOPN1:
    sta FCBPTR
    ldx DATPTR+1
    bne TSTOPN2
    inc CNTENT                      ; no free FCB yet: count its place
TSTOPN2:
    ldy #FCBREFN
    lda (FCBPTR),y
    bne CHKACTV
    txa
    bne TSNXFCB
    lda FCBPTR
    sta DATPTR
    lda FCBPTR+1
    sta DATPTR+1
    jmp TSNXFCB
CHKACTV:
    ldy #FCBSWAP
    lda (FCBPTR),y
    bne TSNXFCB
    ldy #FCBENTN
WHOWNS:
    lda (FCBPTR),y
    cmp D_DEV-1,y
    bne TSNXFCB
    dey
    bne WHOWNS
    inc TOTENT
    ldy #FCBATTR
    lda (FCBPTR),y
    and #WRITEN
    beq TSNXFCB
    sec
    rts
TSNXFCB:
    lda FCBPTR
    clc
    adc #$20
    bcc TSTOPN1
    ldx FCBPTR+1
    inc FCBPTR+1
    cpx a:FCBADDRH
    beq TSTOPN1                     ; on to the second page
    clc
    rts
    .include "ReadWrite.asm"
