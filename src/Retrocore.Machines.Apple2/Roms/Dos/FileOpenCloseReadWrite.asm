;; DOS 3.3 AND 3.2 FILE MANAGER: OPEN, CLOSE, RENAME, READ AND WRITE (FOPCLRW)
;;
;; The file manager's requests for using a file's contents: OPEN, CLOSE, RENAME, and READ and WRITE with
;; their subcodes. DOSENT (FileManagerEntry.asm) reaches each through CMDVT; READ and WRITE go on through RVT
;; and WVT. Every request ends by jumping to GOODIO or one of the ERRORn routines (FileLocateSector.asm),
;; which save the work area back into the file's buffer and return to DOSENT's caller. Where DOS runs, the
;; module occupies $AB22-$ACEE.
;;
;; DOPEN, which every request on a named file starts with, works on the catalog (docs/Dos.md). Each catalog
;; sector holds seven 35-byte entries from VDFILE; an entry has the track and sector of the file's first
;; track/sector list at +0 and +1 (track 0 for an entry never used, $FF for a deleted file), the file type
;; at +2 (bit 7 set when locked), the name at +3 to +32 and the length in sectors at +33 and +34.
;;
;; Reading and writing go a byte at a time through LOCNXB (FileLocateNextByte.asm), which keeps the right
;; data sector in the file's data buffer, reading it, or for WRITE allocating it, when the position moves
;; into another sector.

;; The OPEN request: finds or creates the file and gets it ready for reading and writing.
;; In:    CCB = the OPEN request
;; Out:   CCBFUC = the file's type, CCBSTA = 0, or 6 when the file was created
;; Errors: carry = set with CCBSTA = an error code, see DOPEN
FOPEN:
    jsr DOPEN
    jmp GOODIO

;; Finds the file CCBFN1 names in the catalog, creating it if the command may, and sets up the work area for
;; it.
;;
;; A file is created only when the CMDSTB entry for CMDNO has its create flag (bit 0) set: for DOS's
;; commands that is INIT, SAVE, OPEN and BSAVE, and USERENT sets CMDNO to INIT's or LOAD's. A new file gets one
;; sector, an empty track/sector list, and the type in CCBFUC. Its name is already in the catalog entry:
;; FNDFIL puts it in the free entry it finds when the name is missing.
;;
;; On return the catalog sector holding the entry is in VOLDIR, at CVDTRK and CVDSEC on the disk, which lets
;; the requests that change the entry write it back with WRVDIR.
;; In:    CCBFN1 = address of the 30-character name, CCBRLN = record length (0 means 256), CCBVOL, CCBDRV,
;;          CCBSLT = the disk, CCBFUC = the type for a new file
;; Out:   carry = clear, TEMP1 = DCBVDI = the entry's offset in VDFILE, CCBFUC = DCBFUC = the file's type,
;;          the first track/sector list sector in the file's buffer, CCBSTA = CREFNF when the file was made
;; Errors: 6 (file not found) when the file is missing and may not be created, or 1 (language not
;;          available) instead when FP was looking for the APPLESOFT file; 9 when the disk is full; the disk
;;          errors of DCBIO
;; Uses:  A, X, Y, ZPGFCB, TEMP2, TEMP3, FCB (the work area), VTOC, VOLDIR
DOPEN:
    jsr DCBSUP
    lda #1                          ; RWTS moves 256 bytes a sector: DCBSDL = $0100
    sta a:DCBSDL+1
    ldx a:CCBRLN+1
    lda a:CCBRLN
    bne F02
    cpx #0
    bne F02
    inx                             ; a record length of 0 becomes $0100, 256
F02:
    sta a:DCBRCL
    stx a:DCBRCL+1
    jsr FNDFIL
    bcc F03                         ; found: X = its entry
; Not found: X is the free entry FNDFIL put the name in. Create the file if the command may.
    stx a:TEMP1
    ldx CMDNO
    lda CMDSTB,x
    ldx a:TEMP1
    lsr a                           ; the create flag, bit 0, into the carry
    bcs F02B
    lda ISTATE
    cmp #$C0                        ; FP looking for the RAM Applesoft (MiscCommands.asm, EAS2)
    bne F02A
    jmp ERROR1
F02A:
    jmp ERROR6
; Create it: one sector, the track/sector list, which also becomes the first and current list in the work
; area.
F02B:
    lda #0
    sta a:VDFILE+34,x
    lda #1
    sta a:VDFILE+33,x
    stx a:TEMP1
    jsr GETSEC                      ; A = the sector, DCBATK = its track
    ldx a:TEMP1
    sta a:VDFILE+1,x
    sta a:DCBFDS
    sta a:DCBCDS
    lda a:DCBATK
    sta a:VDFILE,x
    sta a:DCBFDT
    sta a:DCBCDT
    lda a:CCBFUC
    sta a:VDFILE+2,x
    jsr WRVDIR                      ; the catalog sector with the new entry
    jsr MVFCBD
    jsr CLRSEC                      ; an empty track/sector list...
    jsr WRFDGO                      ; ...written to the new sector
    ldx a:TEMP1
    lda #CREFNF                     ; report the file as not found, though it now exists
    sta a:CCBSTA
; Copy what the entry says about the file into the work area.
F03:
    lda a:VDFILE,x
    sta a:DCBFDT
    lda a:VDFILE+1,x
    sta a:DCBFDS
    lda a:VDFILE+2,x
    sta a:CCBFUC
    sta a:DCBFUC
    lda a:VDFILE+33,x
    sta a:DCBNSA
    lda a:VDFILE+34,x
    sta a:DCBNSA+1
    stx a:DCBVDI
    lda #255                        ; no data sector in the buffer yet
    sta a:DCBCMS
    sta a:DCBCMS+1
    lda a:VTDMS                     ; sectors one track/sector list covers, 122
    sta a:DCBDMS
    clc                             ; read the first track/sector list
    jmp RDFDIR

;; Clears the work area and fills in the disk to use from the parameter list.
;;
;; The volume number is kept complemented in DCBVOL; DCBIO complements it again for RWTS, so 0, any volume,
;; is $FF here.
;; In:    CCBVOL, CCBDRV, CCBSLT = the disk
;; Out:   the work area FCB zeroed but for DCBVOL, DCBDRV, DCBSLT = slot * 16 and DCBVTN = 17, the VTOC's
;;          track
;; Uses:  A, X
DCBSUP:
    lda #0
    tax
F01:
    sta a:FCBDCB,x
    inx
    cpx #DCBLEN
    bne F01
    lda a:CCBVOL
    eor #$FF
    sta a:DCBVOL
    lda a:CCBDRV
    sta a:DCBDRV
    lda a:CCBSLT
    asl a
    asl a
    asl a
    asl a
    tax
; F01A is a label with no use.
F01A:
    stx a:DCBSLT
    lda #17
    sta a:DCBVTN
    rts

;; The CLOSE request: writes out what is waiting in the file's buffers and brings the catalog up to date.
;;
;; The data sector and the track/sector list are written if changed, and the sectors still reserved on the
;; track the file was being given go back to the VTOC (FRETRK). If anything at all was written to the disk,
;; which DCBIO marks with bit 1 of DCBWRF, the file's length in sectors is copied into its catalog entry. To
;; get the entry's sector back, CLOSE reads the VTOC for the catalog's start and then follows the catalog's
;; links DCBVDR times, the count FNDFIL kept when it found the file.
;; In:    FCB = the file's work area
;; Out:   CCBSTA = 0
;; Errors: carry = set with CCBSTA = a disk error code
FCLOSE:
    jsr WRSECT
    jsr WRFDIR
    jsr FRETRK
    lda #IBCWTS                     ; bit 1: something was written
    and a:DCBWRF
    beq FC2
    jsr RDVTOC
    lda #0                          ; (RDVDIR takes nothing in A)
    clc                             ; the catalog's first sector, then each next one
FC1:
    jsr RDVDIR
    sec
    dec a:DCBVDR
    bne FC1
    ldx a:DCBVDI
    lda a:DCBNSA
    sta a:VDFILE+33,x
    lda a:DCBNSA+1
    sta a:VDFILE+34,x
    jsr WRVDIR
FC2:
    jmp GOODIO

;; The RENAME request: gives the file CCBFN1 names the name CCBFN2 points to.
;;
;; The new name is not checked against the names already in the catalog.
;; In:    CCBFN1 = address of the old name, CCBFN2 = address of the new one, 30 characters each, and the disk
;;          as for OPEN
;; Out:   CCBSTA = 0
;; Errors: 10 when the file is locked, and those of DOPEN
FRNME:
    jsr DOPEN
    lda a:DCBFUC
    bmi ER10                        ; locked
    lda a:CCBFN2
    sta ZPGFCB
    lda a:CCBFN2+1
    sta ZPGFCB+1
    ldx a:TEMP1
    jsr MVFN                        ; into the entry, in the catalog sector DOPEN left in VOLDIR
    jsr WRVDIR
    jmp GOODIO

;; The READ request: goes to the routine for the subcode in CCBRQM through RVT.
;; In:    CCBRQM = the subcode, 0 to 4
;; Errors: 3 when the subcode is 5 or more
FREAD:
    lda a:CCBRQM
    cmp #CRMMAX
    bcs ERR3A
    asl a
    tax
    lda RVT+1,x                     ; push the routine's address less 1, and "return" to it
    pha
    lda RVT,x
    pha
    rts
;; Returns error code 3, bad subcode.
ERR3A:
    jmp ERROR3
;; Returns error code 10, file locked.
ER10:
    jmp ERRR10

;; The WRITE request: checks the file isn't locked and goes to the routine for the subcode through WVT.
;; In:    CCBRQM = the subcode, 0 to 4
;; Errors: 10 when the file is locked, 3 when the subcode is 5 or more
FWRITE:
    lda a:DCBFUC
    bmi ER10
    lda a:CCBRQM
    cmp #CRMMAX
    bcs ERR3A
    asl a
    tax
    lda WVT+1,x
    pha
    lda WVT,x
    pha
    rts

;; READ subcodes 3 and 1: reads one byte into CCBDAT, at the position CCBRRN and CCBBYT give (subcode 3,
;; RSPBYT) or the next one (subcode 1, RNXBYT).
;; In:    CCBRRN = record number, CCBBYT = byte offset (RSPBYT only)
;; Out:   CCBDAT = the byte, CCBRRN and CCBBYT = its position
;; Errors: 5 at the end of the file
;; Entry: RNXBYT = reads the next byte, without positioning
RSPBYT:
    jsr LOCSEC
RNXBYT:
    jsr GETBYT
    sta a:CCBDAT
    jmp GOODIO

;; READ subcodes 4 and 2: reads CCBBLN bytes into memory at CCBBBA, at the position CCBRRN and CCBBYT give
;; (subcode 4, RSPBLK) or from the next byte (subcode 2, RNXBLK).
;;
;; The loop has no exit of its own: DTBLN jumps to GOODIO once the count is used up.
;; In:    CCBBBA = where to put the bytes, CCBBLN = how many, CCBRRN and CCBBYT = the position (RSPBLK)
;; Out:   CCBBBA = one past the last byte stored, CCBBLN = 0
;; Errors: 5 at the end of the file, with the bytes before it stored
;; Entry: RNXBLK = reads from the next byte, without positioning
RSPBLK:
    jsr LOCSEC
RNXBLK:
    jsr DTBLN                       ; count one off, or finish
    jsr GETBYT
    pha                             ; held while ZPGFCB is moved from the data buffer to the destination
    jsr MIBDA                       ; ZPGFCB = CCBBBA, and CCBBBA advanced
    ldy #0
    pla
    sta (ZPGFCB),y
    jmp RNXBLK

;; Reads the byte at the file's position and moves the position on.
;; Out:   A = the byte, CCBRRN and CCBBYT = its position
;; Errors: 5 at the end of the file: the position is in no sector the track/sector lists name
;; Uses:  X, Y, ZPGFCB (set to the data buffer)
GETBYT:
    jsr LOCNXB                      ; ZPGFCB = the data buffer, Y = the byte's offset in it
    bcs EOFIN
    lda (ZPGFCB),y
    pha
    jsr INCRRB                      ; next record byte
    jsr INCSCB                      ; next byte of the file
    pla
    rts
;; Returns error code 5, end of data.
EOFIN:
    jmp ERROR5

;; WRITE subcodes 3 and 1: writes the byte in CCBDAT at the position CCBRRN and CCBBYT give (subcode 3,
;; WSPBYT) or the next one (subcode 1, WNXBYT).
;; In:    CCBDAT = the byte, CCBRRN = record number and CCBBYT = byte offset (WSPBYT only)
;; Out:   CCBRRN/CCBBYT = the byte's position
;; Errors: 9 when the disk is full, and the disk errors of DCBIO
;; Entry: WNXBYT = writes at the next byte, without positioning
WSPBYT:
    jsr LOCSEC
WNXBYT:
    lda a:CCBDAT
    jsr PUTBYT
    jmp GOODIO

;; WRITE subcodes 4 and 2: writes bytes from memory at CCBBBA, at the position CCBRRN and CCBBYT give
;; (subcode 4, WSPBLK) or from the next byte (subcode 2, WNXBLK).
;;
;; Unlike the read loop, this one writes a byte before counting, so it writes CCBBLN + 1 bytes and callers
;; must pass the length less 1. SAVE and BSAVE pass the length itself (LoadSave.asm, SV2), so they write one
;; byte more than the length they record at the start of the file.
;; In:    CCBBBA = the bytes, CCBBLN = how many less 1, CCBRRN and CCBBYT = the position (WSPBLK)
;; Out:   CCBBBA = one past the last byte written, CCBBLN = 0
;; Errors: 9 when the disk is full, and the disk errors of DCBIO
;; Entry: WNXBLK = writes from the next byte, without positioning
WSPBLK:
    jsr LOCSEC
WNXBLK:
    jsr MIBDA                       ; ZPGFCB = CCBBBA, and CCBBBA advanced
    ldy #0
    lda (ZPGFCB),y
    jsr PUTBYT
    jsr DTBLN                       ; count one off, or finish
    jmp WNXBLK

;; Writes a byte at the file's position and moves the position on.
;;
;; The byte goes into the data buffer, which is marked to be written to the disk (bit 6 of DCBWRF) before
;; another sector replaces it, or at CLOSE.
;; In:    A = the byte
;; Out:   CCBRRN/CCBBYT = its position
;; Errors: 9 when a new sector is needed and the disk is full
;; Uses:  A, X, Y, ZPGFCB (set to the data buffer)
PUTBYT:
    pha
    jsr LOCNXB                      ; ZPGFCB = the data buffer, Y = the byte's offset in it
; PB0 is a label with no use.
PB0:
    pla
    sta (ZPGFCB),y
    lda #$40                        ; the data sector has changed
    ora a:DCBWRF
    sta a:DCBWRF
    jsr INCRRB
    jmp INCSCB
