; SOS 1.3 kernel, block file manager: finding a file through its directories, finding and logging in volumes, and
; counting a volume's free blocks.

; ---------------------------------------------------------------------------------------------------------------------
; Finding files
; ---------------------------------------------------------------------------------------------------------------------

;; Finds the file the parsed pathname names and copies its directory entry to DFIL.
;; In:    PATHNML = the parsed pathname (from <SETPATH>)
;; Out:
;;   carry   = set for an error
;;   A       = 0, or the error from <LOOKFILE>
;;   DFIL    = the file's entry; for a volume directory, the made-up entry LOOKFILE gives with BADPATH
;; Uses:  X, Y, BLOKNML, BLOKNMH, GBUF
;; See:   <LOOKFILE>, <MOVENTRY>
FINDFILE:
    jsr LOOKFILE
    bcs NOFIND

;; Copies the directory entry at DRBUFPL to DFIL.
;; In:    DRBUFPL/DRBUFPH = the entry in GBUF, H_ENTLN = the entry length
;; Out:   A = 0, Y = $FF
;; Keeps: X
;; See:   <FINDFILE>
MOVENTRY:
    ldy H_ENTLN
MOVENT1:
    lda (DRBUFPL),y
    sta DFIL+D_STOR,y
    dey
    bpl MOVENT1
    lda #0
NOFIND:
    rts

;; Looks up the parsed pathname, directory by directory, and finds its last name's entry, or where a new entry
;; for it can go.
;;
;; It finds the volume and reads its root directory (<PREPROOT>). In each directory it reads block after block
;; (<LOOKNAM>) until the name is found or every file the header counts has been seen. A name before the last
;; must be a subdirectory, whose header block is then read; a directory a later SOS made incompatible gives
;; CPTERR. On the way it notes the first free entry it sees in the last directory, in D_ENTBLK and D_ENTNUM with
;; NOFREE set, for CREATE. When there is none and CFLAG is set, a full subdirectory is extended by a block,
;; and the parent's entry for it updated; the root directory's size is fixed.
;;
;; A pathname that names only a volume gives BADPATH, with a made-up entry for the volume directory in DFIL
;; that OPEN can use.
;; In:    PATHNML = the parsed pathname, CFLAG = nonzero to extend a full directory
;; Out:
;;   carry    = set for an error
;;   A        = the error: FNFERR (the last name is missing), PATHNOTFND, BADPATH, CPTERR, DIRERR, or one from
;;              the volume search or the device
;;   DRBUFPL  = the entry found, in GBUF
;;   D_ENTBLK = the block that holds the entry found or free
;;   D_ENTNUM = the entry's number in that block
;;   D_HEAD   = the directory's header block
;; Uses:  X, Y, TOTENT, ENTCNTL, ENTCNTH, CNTENT, NOFREE, BLOKNML, BLOKNMH, GBUF
;; See:   <PREPROOT>, <LOOKNAM>, <FINDFILE>, <CREATE>
LOOKFILE:
    jsr PREPROOT
    bcs FNDERR
    ldy #0
    lda (PATHNML),y
    bne LOOKFIL0
    lda #GBUF/256                   ; only the volume: make up an entry for its directory
    sta DRBUFPH
    lda #4
    sta DRBUFPL
    ldy #D_AUXID
PHANTM1:
    lda (DRBUFPL),y                 ; the dates, versions and attributes from the header
    sta DFIL,y
    dey
    cpy #D_CREDT-1
    bne PHANTM1
PHANTM2:
    lda ROOTSTUF-D_FILID,y          ; the type, key block, blocks used and size
    sta DFIL,y
    dey
    cpy #D_FILID-1
    bne PHANTM2
    lda #DIRTYP*$10
    sta DFIL+D_STOR
    lda #BADPATH
    rts

;; The made-up entry fields for a volume directory, from D_FILID to D_EOF: file type 0, key block 2, 4 blocks
;; used, and a size of $800 bytes.
;; See: <LOOKFILE>
ROOTSTUF:
    .byte 0, 2, 0, 4
    .byte 0, 0, 8, 0
LOOKFIL0:
    lda #0
    sta NOFREE
    sec                             ; the first block holds the header
LOOKFIL1:
    lda #0
    sta TOTENT
    jsr LOOKNAM
    bcc NAMFOJMP
    lda ENTCNTL                     ; take this block's files from those left to see
    sbc TOTENT
    bcc DCRENTH
    bne LOOKFIL2
    cmp ENTCNTH
    beq ERRFNF                      ; every file has been seen
    bne LOOKFIL2
DCRENTH:
    dec ENTCNTH
    bpl LOOKFIL2
ERRDIR:
    lda #DIRERR                     ; the file count and the blocks disagree
FNDERR:
    sec
    rts
NAMFOJMP:
    jmp NAMFOUND
LOOKFIL2:
    sta ENTCNTL
    lda #GBUF/256
    sta DRBUFPH
    lda GBUF+2                      ; the forward link
    bne NXTDIR0
    cmp GBUF+3
    beq ERRDIR
NXTDIR0:
    sta BLOKNML
    lda GBUF+3
    sta BLOKNMH
    jsr RDGBUF
    bcc LOOKFIL1
    rts
TELFREEX:
    jmp TELFREE
FNF0X:
    jmp FNF0

;; Nonzero while CREATE runs, so <LOOKFILE> extends a full directory.
;;
;; Its initial contents are whatever was in memory when Apple built SOS.KERNEL; <BFMGR> clears it for each call.
CFLAG:
    .res 1, $A0

;; The block number of the directory block being extended.
;;
;; Its initial contents are whatever was in memory when Apple built SOS.KERNEL; SOS sets it at run time.
TTSAVE:
    .res 2, $A0

;; The parent directory block that holds the entry of the directory being searched; 0 for the root directory.
;;
;; Its initial contents are whatever was in memory when Apple built SOS.KERNEL; <BFMGR> clears it for each call.
BLOKSAVE:
    .byte $C7, $A0
ERRFNF:
    lda NOFREE
    bne FNF0X                       ; a free entry was found
    lda GBUF+2
    bne TELFREEX
    cmp GBUF+3
    bne TELFREEX                    ; not the last block: its next block must have room
    lda CFLAG
    beq FNF0X
    lda BLOKSAVE
    ora BLOKSAVE+1
    beq FNF0X                       ; the root directory cannot grow
    lda TTLINK                      ; extend: link a new block to this one and write this one
    sta TLINK
    lda TTLINK+1
    sta TLINK+1
    jsr DIRWRT
    bcs FNF0
    lda TTLINK
    sta TTSAVE
    lda TTLINK+1
    sta TTSAVE+1
    lda GBUF+2
    sta BLOKNML
    lda GBUF+3
    sta BLOKNMH
    jsr ZERGBUF
    lda TTSAVE                      ; the new block: empty, linked back to this one
    sta GBUF
    lda TTSAVE+1
    sta GBUF+1
    jsr WRTGBUF
    bcs ERTS
    lda BLOKSAVE
    sta BLOKNML
    ldx BLOKSAVE+1
    stx BLOKNMH
    jsr RDGBUF                      ; the parent's entry: one more block, $200 more bytes
    ldy #D_USAGE
    lda (DEBUPTR),y
    sec
    adc #0
    sta (DEBUPTR),y
    iny
    lda (DEBUPTR),y
    adc #0
    sta (DEBUPTR),y
    ldy #D_EOF+1
    lda (DEBUPTR),y
    clc
    adc #2
    sta (DEBUPTR),y
    iny
    lda (DEBUPTR),y
    adc #0
    sta (DEBUPTR),y
    jsr WRTGBUF
    lda TTSAVE+1
    sta BLOKNMH
    lda TTSAVE
    sta BLOKNML
    jsr RDGBUF
    jmp ERRFNF                      ; now the new block follows
TELFREE:
    sta D_ENTBLK                    ; the next block's first entry is free
    lda GBUF+3
    sta D_ENTBLK+1
    lda #1
    sta D_ENTNUM
    sta NOFREE
FNF0:
    ldy #0
    lda (PATHNML),y
    tay
    iny
    lda (PATHNML),y                 ; another name after this one?
ERRPATH1:
    sec
    beq FNF1
    lda #PATHNOTFND
ERTS:
    rts
FNF1:
    lda #FNFERR
    rts
NAMFOUND:
    lda (PATHNML),y                 ; Y = 0
    sec
    adc PATHNML
    tay
    clc
    lda PATHBUF,y
    beq FILFOUND                    ; that was the last name
    sty PATHNML
    lda DRBUFPL
    sta DEBUPTR
    lda DRBUFPH
    sta DEBUPTR+1
    lda BLOKNML
    sta BLOKSAVE
    lda BLOKNMH
    sta BLOKSAVE+1
    ldy #D_STOR
    lda (DRBUFPL),y
    and #$F0
    cmp #DIRTYP*16
    bne ERRPATH1                    ; not a subdirectory
    ldy #D_FRST
    lda (DRBUFPL),y
    sta BLOKNML
    iny
    sta D_HEAD
    lda (DRBUFPL),y
    sta BLOKNMH
    sta D_HEAD+1
    jsr RDGBUF
    bcs FNDERR1
    lda GBUF+HCENT+4
    sta ENTCNTL
    lda GBUF+HCENT+5
    sta ENTCNTH
    lda GBUF+HCMP+4
    beq MOVHEAD
ERRCOMP:
    lda #CPTERR
NONAME:
FNDERR1:
    sec
    rts
MOVHEAD:
    jsr MOVHED0
    jmp LOOKFIL0

;; Copies a directory header's fields, from its creation date to its file count, from GBUF to H_CREDT on.
;; In:    GBUF = the directory's header block
;; Out:   H_CREDT..H_FCNT+1 = the header's fields, X = $FF
;; Keeps: Y
;; See:   <LOOKFILE>
MOVHED0:
    ldx #$A
MOVHED1:
    lda GBUF+HCRDT+4,x
    sta H_CREDT,x
    dex
    bpl MOVHED1
    rts

;; Records where the current directory entry is: its block and its number in the block.
;;
;; LOOKFILE comes here when it finds the last name, and LOOKNAM calls it at ENTADR for the first free entry.
;; In:    CNTENT = the entries left in the block, counting this one, BLOKNML/BLOKNMH = the block
;; Out:   D_ENTNUM = the entry's number, D_ENTBLK = the block, carry = clear
;; Uses:  A
;; Keeps: X, Y
;; Entry: ENTADR = the same code, the name LOOKNAM calls
FILFOUND:
ENTADR:
    lda H_MAXENT
    sec
    sbc CNTENT
    adc #0                          ; the carry is set: the number counts from 1
    sta D_ENTNUM
    lda BLOKNML
    sta D_ENTBLK
    lda BLOKNMH
    sta D_ENTBLK+1
    clc
    rts

;; Looks for the current name in one directory block in GBUF.
;;
;; It counts the used entries it passes in TOTENT, and records the first free entry it sees, if none has been
;; recorded yet (NOFREE), with <ENTADR>.
;; In:    GBUF = the directory block, PATHNML = the name, carry = set to skip the header entry
;; Out:   carry = clear when the name was found, DRBUFPL/DRBUFPH = its entry, Y = 0
;; Uses:  A, Y, CNTENT, TOTENT, NOFREE
;; Keeps: X
;; See:   <LOOKFILE>
LOOKNAM:
    lda H_MAXENT
    sta CNTENT
    lda #GBUF/256
    sta DRBUFPH
    lda #4
LOKNAM1:
    sta DRBUFPL
    bcs LOKNAM2
    ldy #D_STOR
    lda (DRBUFPL),y
    bne ISNAME
    lda NOFREE
    bne LOKNAM2
    jsr ENTADR
    inc NOFREE
    bne LOKNAM2
ISNAME:
    and #$F                         ; the name's length
    inc TOTENT
    cmp (PATHNML),y
    bne LOKNAM2
    tay
CMPNAME:
    lda (DRBUFPL),y
    cmp (PATHNML),y
    bne LOKNAM2
    dey
    bne CMPNAME
    clc
    rts
LOKNAM2:
    dec CNTENT
    beq NONAME
    lda H_ENTLN
    clc
    adc DRBUFPL
    bcc LOKNAM1
    inc DRBUFPH
    clc
    bcc LOKNAM1

;; Finds the volume the parsed pathname starts with and reads its root directory into GBUF.
;;
;; It looks first among the logged-in volumes (<FINDVOL>), then in every block device (<LOOKVOL>). When the
;; volume has open files but its drive holds another disk, it asks for the volume to be put back. It clears the
;; directory variables (D_DEV on), copies the volume's status and the root header's fields (V_STATUS on), and
;; steps PATHNML past the volume name.
;; In:    PATHNML = the parsed pathname
;; Out:
;;   carry   = set for an error
;;   A       = the error: VNFERR, DUPVOL, XIOERROR, or one from the device
;;   VCBPTR  = the volume's VCB entry
;;   DEVNUM  = its device, also in D_DEV
;;   D_HEAD  = the root directory's first block, also in BLOKNML/BLOKNMH
;;   PATHNML = the next name
;;   ENTCNTL/ENTCNTH = the number of files in the root directory
;; Uses:  X, Y, GBUF
;; See:   <LOOKFILE>, <CHKROOT>
PREPROOT:
    jsr FINDVOL
    bcc ROOT1
ROOT0:
    jsr LOOKVOL
    bcs SRITZ
ROOT1:
    lda #0
    ldy #42
CLRDSP:
    sta D_DEV,y
    dey
    bpl CLRDSP
    ldy #VCBDEV
    lda (VCBPTR),y
    sta DEVNUM
    sta D_DEV
    iny
    lda (VCBPTR),y
    sta V_STATUS
    ldy #VCBROOT
    lda (VCBPTR),y
    sta BLOKNML
    sta D_HEAD
    iny
    lda (VCBPTR),y
    sta BLOKNMH
    sta D_HEAD+1
    jsr RDGBUF
    bcc ROOT2
    pha
    ldy #VCBSTAT
    lda (VCBPTR),y
    asl a                           ; carry = files are open
    pla
    bcs ROOTERR                     ; report the error for a volume in use
    bne ROOT0                       ; otherwise look in the other devices
ROOT2:
    jsr CHKROOT
    beq ROOT3
    ldy #VCBSTAT
    lda (VCBPTR),y
    bpl ROOT0
    jsr USRREQ                      ; files are open: ask for the volume
    bcc ROOT1
    lda #VNFERR
SRITZ:
    rts
ROOT3:
    ldy #$F
ROOTINFO:
    lda GBUF+HCRDT+3,y
    sta V_STATUS,y
    dey
    bne ROOTINFO
    lda H_FCNT
    sta ENTCNTL
    lda H_FCNT+1
    sta ENTCNTH
    txa                             ; X = the volume name's length, from CHKROOT
    sec
    adc PATHNML
    sta PATHNML
    clc
ROOTERR:
    rts

;; Compares the name at PATHNML with the directory name in the header in GBUF.
;; In:    PATHNML = the name, GBUF = a directory's first block
;; Out:   zero = set when they match, X = the name's length
;; Uses:  A, Y
;; See:   <PREPROOT>, <LOOKVOL>
CHKROOT:
    ldy #0
    lda (PATHNML),y
    tay
    tax
    eor GBUF+4
    and #$F
    bne NOTROOT
CKROOT1:
    lda (PATHNML),y
    cmp GBUF+4,y
    bne NOTROOT
    dey
    bne CKROOT1
NOTROOT:
    rts

; ---------------------------------------------------------------------------------------------------------------------
; Finding and logging in volumes
; ---------------------------------------------------------------------------------------------------------------------

;; Looks for the volume named at PATHNML among the VCB entries, swapping it in if it was swapped out.
;; In:    PATHNML = the volume name
;; Out:
;;   carry   = set when it is not there, or with A = XIOERROR when it was not put back
;;   VCBPTR  = its VCB entry, also in X
;;   D_DEV   = 0
;; Uses:  A, Y
;; See:   <PREPROOT>, <LOOKVOL>
FINDVOL:
    lda #VCB/256
    sta VCBPTR+1
    lda #0
    sta D_DEV
    sta VCBPTR
FNDVOL1:
    pha
    tax
    ldy #0
    lda VCB,x
    beq NXTVCB
    cmp (PATHNML),y
    bne NXTVCB
    clc
    tay
    txa
    adc VCB,x
    tax                             ; compare from the last character back
VOLNAM:
    lda (PATHNML),y
    cmp VCB,x
    bne NXTVCB
    dex
    dey
    bne VOLNAM
    pla
    sta VCBPTR
    tax
    lda VCB+VCBSWAP,x
    beq FOUNDVOL
    jsr SWAPIN
    bcc FOUNDVOL
    lda #XIOERROR
    rts
FOUNDVOL:
    clc
    rts
NXTVCB:
    pla
    clc
    adc #VCBSIZE
    bcc FNDVOL1
    rts

;; Looks for the volume named at PATHNML in every block device, logging in what each device holds.
;;
;; It goes through the block device list (BLKDLST, copied to SCRTCH), skipping D_DEV, the device already tried.
;; A device with a logged-in volume that has no open files is read again and logged in again; one whose volume
;; has open files is only checked for a switched disk holding the volume wanted (<SNSWIT1>). A device with no
;; volume gets a free VCB entry, or one with no open files (<FREEVCB>). A device that cannot be read loses its
;; VCB entry. When every VCB entry has open files it returns with carry set but no error code in A.
;; In:    PATHNML = the volume name, D_DEV = a device to skip, or 0
;; Out:
;;   carry   = set for an error
;;   A       = the error: VNFERR, DUPVOL, NOTSOS, XIOERROR, or one from the device
;;   VCBPTR  = the volume's VCB entry
;;   DEVNUM  = its device
;; Uses:  X, Y, SCRTCH, TOTDEVS, GBUF
;; See:   <PREPROOT>, <LOGVCB>, <CHKROOT>
LOOKVOL:
    ldx #12
LOOKVOL1:
    lda BLKDLST,x
    sta SCRTCH,x
    dex
    bpl LOOKVOL1
    sta TOTDEVS                     ; the count, from the list's first byte
    inx
LOKDEV1:
    inx
    stx SCRTCH                      ; SCRTCH is now the index of the device being tried
    lda SCRTCH,x
    cmp D_DEV
    beq NXTDEV
    sta DEVNUM
    jsr DEVVCB
    bcc LOKVOL1
    lda #0
ENTVCB:
    tax
    lda VCB,x
    beq FREEVCB                     ; a free entry
    txa
    clc
    adc #VCBSIZE
    bcc ENTVCB
    lda #0
ENTVCB2:
    tax
    lda VCB+VCBSTAT,x
    beq FREEVCB                     ; an entry with no open files
    txa
    clc
    adc #VCBSIZE
    bcc ENTVCB2
    rts                             ; no entry can be used: carry set
CHKVLOG:
    ldy #0
    lda (VCBPTR),y
    bne FOUNDVOL                    ; it was logged in
    lda #DUPVOL                     ; it was not, for an open volume of the same name
    sec
    rts

;; Logs in the volume in device DEVNUM at VCB entry X, then checks whether it is the volume PATHNML names,
;; going on with <LOOKVOL>'s search of the devices when it is not.
;;
;; <SRCHDEV> uses it with a device list of one, after pointing PATHNML at the entry's own name.
;; In:    X = the VCB entry, DEVNUM = the device, SCRTCH/TOTDEVS = the device list's position and count
;; Inherit: <LOOKVOL> Out
;; Uses:  X, Y, GBUF
FREEVCB:
    stx VCBPTR
    lda #2                          ; the root directory starts at block 2
    ldx #0
    beq GETROOT
LOKVOL1:
    ldy #VCBSTAT
    lda (VCBPTR),y
    bmi SNSWIT                      ; files are open on it
    ldy #VCBROOT+1
    lda (VCBPTR),y
    tax
    dey
    lda (VCBPTR),y
GETROOT:
    jsr GETROT0
    bcc LOKVOL2
    lda #0
    tay
    sta (VCBPTR),y                  ; unreadable: the entry is freed
    beq NXTDEV
LOKVOL2:
    jsr LOGVCB
    bcs NXTDEV                      ; not a SOS volume
    jsr CHKROOT
    beq CHKVLOG
NXTDEV:
    ldx SCRTCH
    cpx TOTDEVS
    bcc LOKDEV1
    lda #VNFERR
    rts
SNSWIT:
    ldy #VCBDEV
    lda (VCBPTR),y
    sta DEVNUM
    jsr TWRPROT1                    ; also notes a disk switch in DSWGLOB
    lda DSWGLOB
    beq NXTDEV
    jsr VERFYVOL
    bcc NXTDEV                      ; still the same volume
    jsr CHKROOT
    bne NXTDEV                      ; not the volume wanted
    ldx #0
    jsr SNSWIT1
    bcs NXTDEV
    jmp CHKVLOG

;; Logs the volume whose root directory is in GBUF into the first free VCB entry from X on, swapping out the
;; device's active volume.
;;
;; The device's old volume has open files, so it is swapped out (<SWAPOUT>), which may ask for its disk; then the
;; new volume's disk is asked for again if it is not in the drive.
;; In:    X = the VCB entry to start from, GBUF = the volume's first directory block, DEVNUM = the device
;; Out:
;;   carry   = set for an error, including when no entry is free
;;   A       = the error: NOTSOS, DUPVOL, XIOERROR, VNFERR
;;   VCBPTR  = the new entry
;; Uses:  X, Y, DUPLFLAG
;; See:   <SRCHDEV>, <LOGVCB1>
SNSWIT1:
    lda VCB,x
    beq SNSWIT2
    txa
    clc
    adc #VCBSIZE
    tax
    bcc SNSWIT1
    rts
SNSWIT2:
    lda #0
    sta DUPLFLAG
    stx VCBPTR
    jsr LOGVCB1
    bcs NONSOS
    lda DUPLFLAG
    bne SNSWIT6
    ldy #VCBSWAP
    lda #1
    sta (VCBPTR),y                  ; so SWAPOUT passes over the new entry
    lda DEVNUM
    jsr SWAPOUT
    bcc SNSWIT3
    lda #XIOERROR
    rts
SNSWIT3:
    ldy #VCBSWAP
    lda #0
    sta (VCBPTR),y
SNSWIT4:
    jsr VERFYVOL
    bcc SNSWIT5
    jsr USRREQ
    bcc SNSWIT4
    lda #VNFERR
SNSWIT5:
    rts
SNSWIT6:
    lda #DUPVOL
    sec
    rts
NONSOS:
    lda #NOTSOS
    rts

;; Finds the logged-in VCB entry for device DEVNUM, passing over swapped-out volumes.
;; In:    DEVNUM = the device, VCBPTR+1 = the VCB page
;; Out:   carry = clear when found, VCBPTR = the entry, X = the same
;; Uses:  A
;; Keeps: Y
;; See:   <LOOKVOL>
DEVVCB:
    lda #0
DVCB1:
    tax
    lda VCB,x
    beq DVCB2
    lda VCB+VCBSWAP,x
    bne DVCB2
    lda VCB+VCBDEV,x
    cmp DEVNUM
    beq FOUNDEV
DVCB2:
    txa
    clc
    adc #VCBSIZE
    bcc DVCB1
    rts

;; Looks for another VCB entry with the name of the volume in GBUF, before that volume is logged in at VCBPTR.
;;
;; Such an entry with no open files is freed. One with open files stops the login: DUPLFLAG is set and the entry
;; is kept in VCBENTRY.
;; In:    VCBPTR = the entry being logged in, GBUF = the volume's first directory block
;; Out:   carry = set for a duplicate with open files, VCBPTR = unchanged
;; Uses:  A, Y, DUPLFLAG, VCBENTRY
;; Keeps: X
;; See:   <LOGVCB>
TSTDUPVOL:
    ldx VCBPTR
    lda #0
TSDUPV1:
    sta VCBPTR
    jsr CMPVCB
    bcs TSDUPV2
    ldy #VCBSTAT
    lda (VCBPTR),y
    bmi FOUNDDUP
    lda #0
    tay
    sta (VCBPTR),y                  ; no open files: forget the old one
    beq NODUPVOL
TSDUPV2:
    lda VCBPTR
    clc
    adc #VCBSIZE
    bcc TSDUPV1
NODUPVOL:
FOUNDEV:
    clc
FNDDUP1:
    stx VCBPTR
    rts
FOUNDDUP:
    sta DUPLFLAG
    sec
    lda VCBPTR
    sta VCBENTRY
    bcs FNDDUP1

;; Logs the volume whose root directory is in GBUF into the VCB entry at VCBPTR, unless it is already there.
;;
;; The entry gets the volume's name, device, size, root block and bitmap block, and the device's unchanged
;; bitmap buffers are dropped (CLEARBMS). When an open volume of the same name is on the same device, that entry
;; is used instead and swapped in, VCBPTR pointing at it; when it is on another device, the entry is left free
;; and DUPLFLAG set.
;; In:    VCBPTR = the entry, GBUF = the root directory's first block, BLOKNML/BLOKNMH = its block number,
;;        DEVNUM = the device
;; Out:   carry = set when it is not a SOS volume, VCBPTR = the volume's entry
;; Uses:  A, X, Y, DUPLFLAG, VCBENTRY, PATHNML (for a duplicate)
;; See:   <LOGVCB1>, <TSTDUPVOL>, <TSTSOS>
LOGVCB:
    ldy #VCBNML
    lda (VCBPTR),y
    beq LOGVCB1
    jsr CMPVCB
    bcc VCBLOGD                     ; already this volume

;; Logs the volume whose root directory is in GBUF into the VCB entry at VCBPTR, clearing the entry first.
;; Inherit: <LOGVCB>
LOGVCB1:
    lda #0
    ldy #VCBSIZE-1
ZERVCB:
    sta (VCBPTR),y
    dey
    bpl ZERVCB
    jsr TSTSOS
    bcs VCBLOGD
    jsr TSTDUPVOL
    bcs NOTLOG0
    lda GBUF+4
    and #$F
    tay
    pha
MOVOLNM:
    lda GBUF+4,y
    sta (VCBPTR),y
    dey
    bne MOVOLNM
    pla
    sta (VCBPTR),y
    ldy #VCBDEV
    lda DEVNUM
    sta (VCBPTR),y
    jsr CLEARBMS
    lda GBUF+VTBLK+4
    ldy #VCBTBLK
    sta (VCBPTR),y
    lda GBUF+VTBLK+5
    iny
    sta (VCBPTR),y
    ldy #VCBROOT
    lda BLOKNML
    sta (VCBPTR),y
    iny
    lda BLOKNMH
    sta (VCBPTR),y
    ldy #VCBDMAP
    lda GBUF+VBMAP+4
    sta (VCBPTR),y
    lda GBUF+VBMAP+5
    iny
    sta (VCBPTR),y
    clc
VCBLOGD:
    rts
NOTLOG0:
    jmp NOTLOG1

;; Compares the volume name in the root directory header in GBUF with the VCB entry at VCBPTR.
;; In:    GBUF = the root directory's first block, VCBPTR = the entry
;; Out:   carry = clear when they match
;; Uses:  A, Y
;; Keeps: X
;; See:   <VERFYVOL>, <LOGVCB>
CMPVCB:
    lda GBUF+4
    and #$F
    ldy #VCBNML
    cmp (VCBPTR),y
    bne NOTSAME
    tay
VCBCMP1:
    lda GBUF+4,y
    cmp (VCBPTR),y
    bne NOTSAME
    dey
    bne VCBCMP1
    clc
    rts

;; Checks that the volume at VCBPTR is the one in device DEVNUM, by reading its root directory (block 2).
;; In:    VCBPTR = the volume's VCB entry, DEVNUM = the device
;; Out:   carry = clear when it is; when not, A = VNFERR if the block could not be read, 0 if it holds another
;;        volume
;; Uses:  X, Y, BLOKNML, BLOKNMH, GBUF
;; See:   <CMPVCB>, <BFMGR>
VERFYVOL:
    ldx #0
    lda #2
    jsr GETROT0
    bcs NOVRFY1
    jsr CMPVCB
    bcc NOVRFY
    lda #0
NOVRFY:
    rts
NOVRFY1:
    lda #VNFERR
    rts

;; Reads a block of device DEVNUM into GBUF.
;; In:    A = the block number's low byte, X = its high byte, DEVNUM = the device
;; Out:   carry = set for an error, A = the error
;; Uses:  X, Y, BLOKNML, BLOKNMH
;; See:   <RDGBUF>
GETROT0:
    sta BLOKNML
    stx BLOKNMH
    jsr RDGBUF
    bcc RETROT2
NOTSAME:
    sec
RETROT2:
    rts
NOTLOG1:
    ldx VCBPTR                      ; an open volume of this name is at VCBENTRY
    lda VCBENTRY
    sta VCBPTR
    stx VCBENTRY
    ldy #VCBDEV
    lda DEVNUM
    cmp (VCBPTR),y
    bne NOTLOG2
    jsr SWAPIN                      ; on this device: it is this volume
    lda #0
    sta DUPLFLAG
    lda VCBPTR
    sta PATHNML                     ; for SRCHDEV, whose name check then reads the entry's own name
    clc
    rts
NOTLOG2:
    lda VCBENTRY                    ; on another device: leave the new entry free
    sta VCBPTR
    clc
    rts

; ---------------------------------------------------------------------------------------------------------------------
; Free blocks
; ---------------------------------------------------------------------------------------------------------------------

;; Checks that the volume at VCBPTR has REQL/REQH free blocks, counting them in its bitmap first if it must.
;;
;; A free count of 0 in the VCB entry means it is not known. Then it writes back the bitmap in memory (UPBMAP),
;; reads each of the volume's bitmap blocks into GBUF and counts its set bits, and stores the count and the first
;; bitmap block with free space (VCBCMAP) in the entry. Each bitmap block covers 4096 blocks.
;; In:    VCBPTR = the volume, REQL/REQH = the blocks wanted
;; Out:   carry = set for an error, A = OVRERR when there are too few, or an error from the device
;; Uses:  X, Y, SCRTCH, BMCNT, NOFREE, BLOKNML, BLOKNMH, GBUF
;; See:   <COUNT>, <VCBTFRE>
TSFRBLK:
    ldy #VCBTFRE+1
    lda (VCBPTR),y
    dey
    ora (VCBPTR),y
    bne CMPFREB
    dey
    lda (VCBPTR),y
    tax
    dey
    lda (VCBPTR),y
    bne TSFR01
    dex
TSFR01:
    txa
    lsr a
    lsr a
    lsr a
    lsr a
    sta BMCNT                       ; the bitmap blocks, less one
    lda #0
    sta SCRTCH
    sta SCRTCH+1
    lda #$FF
    sta NOFREE                      ; no bitmap block with space found yet
    ldy #VCBDEV
    lda (VCBPTR),y
    tax
    jsr UPBMAP
    bcs TFBERR
    ldy #VCBDMAP
    lda (VCBPTR),y
    sta BLOKNML
    iny
    lda (VCBPTR),y
    sta BLOKNMH
BMAPRD:
    jsr RDGBUF
    bcs TFBERR
    jsr COUNT
    dec BMCNT
    bmi CHGVCB
    inc BLOKNML                     ; the bitmap blocks follow each other
    bne BMAPRD
    inc BLOKNMH
    jmp BMAPRD
CHGVCB:
    ldy #VCBCMAP
    lda NOFREE
    bmi DSKFULL                     ; no free blocks at all
    sta (VCBPTR),y
    ldy #VCBTFRE+1
    lda SCRTCH+1
    sta (VCBPTR),y
    dey
    lda SCRTCH
    sta (VCBPTR),y
CMPFREB:
    lda (VCBPTR),y
    sec
    sbc REQL
    iny
    lda (VCBPTR),y
    sbc REQH
    bcc DSKFULL
    clc
    rts
DSKFULL:
    lda #OVRERR
    sec
TFBERR:
    rts

;; Adds the set bits of the bitmap block in GBUF, its free blocks, to the count in SCRTCH, and records in NOFREE
;; the first bitmap block that has any.
;; In:    GBUF = the bitmap block, SCRTCH/SCRTCH+1 = the count so far, BMCNT = the bitmap blocks left after this
;; Out:   SCRTCH/SCRTCH+1 = the new count, NOFREE = the first bitmap block with space, once there is one
;; Uses:  A, X, Y
;; See:   <TSFRBLK>, <CNTFREE>
COUNT:
    ldy #0
FRCONT:
    lda GBUF,y
    beq FRCNT1
    jsr CNTFREE
FRCNT1:
    lda GBUF+$100,y
    beq FRCNT2
    jsr CNTFREE
FRCNT2:
    iny
    bne FRCONT
    bit NOFREE
    bpl FRCNT3                      ; already recorded
    lda SCRTCH
    ora SCRTCH+1
    beq FRCNT3
    ldy #VCBTBLK+1
    lda (VCBPTR),y
    sec
    sbc #$01
    lsr a
    lsr a
    lsr a
    lsr a
    sec
    sbc BMCNT                       ; this bitmap block's number
    sta NOFREE
FRCNT3:
    rts

;; Adds the number of set bits in A to the count in SCRTCH.
;; In:    A = the byte, SCRTCH/SCRTCH+1 = the count
;; Out:   SCRTCH/SCRTCH+1 = the new count, A = 0, X = 0
;; Keeps: Y
CNTFREE:
    asl a
    bcc CFREE1
    inc SCRTCH
    bne CFREE1
    inc SCRTCH+1
CFREE1:
    tax
    bne CNTFREE
    rts
    .include "Alloc.asm"
