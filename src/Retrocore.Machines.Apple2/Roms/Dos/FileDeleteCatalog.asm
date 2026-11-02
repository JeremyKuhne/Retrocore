;; DOS 3.3 AND 3.2 FILE MANAGER: LOCK, POSITION, VERIFY, DELETE AND CATALOG (FDELCAT)
;;
;; The file manager's requests that work on a file as a whole, LOCK and UNLOCK, POSITION, VERIFY, DELETE and
;; CATALOG, which DOSENT (FileManagerEntry.asm) reaches through CMDVT, and the two routines that move a
;; file's work area between the file's buffer and FCB, CLCFCB at every entry and RTNFCB at every exit. Where
;; DOS runs, the module occupies $ACEF-$AE8D.
;;
;; A catalog entry has the track and sector of the file's first track/sector list at +0 and +1, the type at
;; +2 with bit 7 set when the file is locked, the name at +3 to +32 and the length in sectors at +33 and +34
;; (see FileOpenCloseReadWrite.asm). docs/Dos.md describes the catalog and the track/sector lists.

;; The LOCK request: sets bit 7 of the file's type in its catalog entry, which stops WRITE, RENAME and
;; DELETE.
;; In:    CCBFN1 = address of the name, and the disk as for OPEN
;; Out:   CCBSTA = 0
;; Errors: those of DOPEN
FLOCK:
    lda #$80                        ; the bit to leave in the type
    sta a:TEMP3
    bne LCKGO                       ; always
;; The UNLOCK request: clears bit 7 of the file's type in its catalog entry.
;; In:    CCBFN1 = address of the name, and the disk as for OPEN
;; Out:   CCBSTA = 0
;; Errors: those of DOPEN
FUNLCK:
    lda #00
    sta a:TEMP3
; Both: DOPEN leaves the entry's catalog sector in VOLDIR and its offset in TEMP1.
LCKGO:
    jsr DOPEN
    ldx a:TEMP1
    lda a:VDFILE+2,x
    and #$7F
    ora a:TEMP3
    sta a:VDFILE+2,x
    jsr WRVDIR
GOGOOD:
    jmp GOODIO

;; The POSITION request: sets the file's position from the record number and byte offset, ready for the
;; next READ or WRITE. Nothing is read from the disk until then.
;; In:    CCBRRN = record number, CCBBYT = byte offset into the record
;; Out:   CCBSTA = 0
FPOSTN:
    jsr LOCSEC
    jmp GOODIO

;; The VERIFY request: reads every data sector of the file, to show that each can be read.
;;
;; It steps the work area's relative sector, DCBCRS, from the file's first sector and lets LOCNXB read each
;; one, until LOCNXB finds a sector the track/sector lists don't name: the end of the file, or the first gap
;; in a random-access file.
;; In:    CCBFN1 = address of the name, and the disk as for OPEN
;; Out:   CCBSTA = 0
;; Errors: those of DOPEN, and the disk errors of DCBIO
FVAR:
    jsr DOPEN
VAR1:
    jsr LOCNXB
    bcs GOGOOD                      ; past the last sector
    inc a:DCBCRS
    bne VAR1
    inc a:DCBCRS+1
    jmp VAR1

;; The DELETE request: removes a file from the catalog and gives its sectors back to the VTOC.
;;
;; The catalog entry is marked deleted with $FF in its track byte, and the track it held is kept in the
;; last character of the name (+32). Then each track/sector list is read in turn: every data sector it
;; names, and the list's own sector, are marked free in the VTOC in memory, which is written once at the
;; end.
;; In:    CCBFN1 = address of the name, and the disk as for OPEN
;; Out:   CCBSTA = 0
;; Errors: 10 when the file is locked, those of DOPEN, and the disk errors of DCBIO
FDEL:
    jsr DOPEN
FD2:
    ldx a:TEMP1
    lda a:VDFILE+2,x
    bpl FD3
    jmp ERRR10                      ; locked
FD3:
    ldx a:TEMP1
    lda a:VDFILE,x                  ; the first track/sector list's track...
    sta a:DCBFDT
    sta a:VDFILE+32,x               ; ...kept over the name's last character
    lda #$FF                        ; deleted
    sta a:VDFILE,x
    ldy a:VDFILE+1,x
    sty a:DCBFDS
    jsr WRVDIR
    clc                             ; the first list, then (carry set) each next one
FD4:
    jsr RDFDIR
    bcs FD7                         ; no more lists
    jsr MVFCBD                      ; ZPGFCB = the list
    ldy #FDENT                      ; its first track/sector pair
FD5:
    sty a:TEMP1
    lda (ZPGFCB),y                  ; the track: 0 for no sector, so skip it, and skip one of $80 or more
    bmi FD6
    beq FD6
    pha
    iny
    lda (ZPGFCB),y
    tay
    pla
    jsr FDSUB
FD6:
    ldy a:TEMP1
    iny
    iny
    bne FD5                         ; until Y wraps past the last pair
    lda a:DCBCDT                    ; then the list's own sector
    ldy a:DCBCDS
    jsr FDSUB
    sec
    bcs FD4                         ; always
FD7:
    jsr WRVTOC
    jmp GOODIO

;; Marks one sector free in the VTOC in memory.
;;
;; FRESEC builds the sector's bit in the work area's four-byte map at DCBABM and merges it into the track's
;; entry in the VTOC; FDSUB then clears the map, with DCBALS and DCBATK, so the next sector starts from
;; nothing. All four bytes are cleared, as many as a track of 32 sectors would need; DOS 3.2 clears two, enough
;; for a track of 13 sectors.
;; In:    A = track, Y = sector
;; Uses:  A, X, Y, DCBALS, DCBATK, DCBABM
FDSUB:
    sec                             ; the bit FRESEC shifts in: free
    jsr FRESEC
    lda #0
.if DOS32
    ldx #3
.else
    ldx #5
.endif
FDS1:
    sta a:DCBALS,x
    dex
    bpl FDS1
    rts

;; The CATALOG request: prints the disk's volume number and a line for each file in the catalog.
;;
;; Each line is a "*" for a locked file or a space, the type's letter, the length in sectors as three
;; digits, and the name. Output goes through COUT, and so through CSW, and PRCR waits for a key each time a
;; screenful has been printed. The volume asked for is set to 0, any, and the number printed is the one RWTS
;; found on the disk.
;; In:    CCBDRV, CCBSLT = the disk
;; Out:   CCBSTA = 0, CCBVOL = the disk's volume number
;; Errors: the disk errors of DCBIO
;; Uses:  A, X, Y, CNUM, TEMP1, TEMP2, VTOC, VOLDIR
RDIR:
    jsr DCBSUP
    lda #$FF                        ; any volume (DCBVOL is complemented)
    sta a:DCBVOL
    jsr RDVTOC                      ; for the catalog's first track and sector
    lda #22                         ; lines before the first pause
    sta a:TEMP2
    jsr PRCR
    jsr PRCR
    ldx #VML                        ; "DISK VOLUME ", stored backward
RD0:
    lda a:VOLMES,x
    jsr PRINT
    dex
    bpl RD0
    stx CNUM+1                      ; $FF, but PRNUM doesn't look at the high byte
    lda a:IBSMOD                    ; the volume RWTS read from the disk
    sta CNUM
    jsr PRNUM
    jsr PRCR
    jsr PRCR
    clc                             ; the first catalog sector, then each next one
; Each catalog sector.
RD1:
    jsr RDVDIR
    bcs RD5                         ; no more sectors
    ldx #0
; Each entry.
RD2:
    stx a:TEMP1
    lda a:VDFILE,x
    beq RD5                         ; never used: the end of the catalog
    bmi RD4                         ; deleted
    ldy #$A0                        ; a space, or a "*" when locked
    lda a:VDFILE+2,x
    bpl RD2A
    ldy #'*'+$80
RD2A:
    tya
    jsr PRINT
; The type's letter. The type has one bit set, or none for a text file: find the highest of bits 6 to 0, as
; Y = 7 to 1, and print FTTAB,Y: B A R S B A I, or T when no bit is set (Y = 0).
    lda a:VDFILE+2,x
    and #$7F
    ldy #7
    asl a                           ; drop bit 7
RD2B:
    asl a
    bcs RD2C
    dey
    bne RD2B
RD2C:
    lda a:FTTAB,y
    jsr PRINT
    lda #$A0
    jsr PRINT
    lda a:VDFILE+33,x
    sta CNUM
    lda a:VDFILE+34,x
    sta CNUM+1
    jsr PRNUM                       ; three digits: a length of 256 or more is shown less 256s
    lda #$A0
    jsr PRINT
    inx                             ; to the name
    inx
    inx
    ldy #29
RD3:
    lda a:VDFILE,x
    jsr PRINT
    inx
    dey
    bpl RD3
RD3A:
    jsr PRCR
RD4:
    jsr VDINC                       ; X = the next entry, carry set past the sector's last
    bcc RD2
    bcs RD1
RD5:
    jmp GOODIO

;; Prints a carriage return for CATALOG, and waits for a key when the screen is full.
;;
;; TEMP2 counts the lines left: 22 for the first screen, which holds the heading, then 21.
;; Uses:  A, TEMP2
PRCR:
    lda #$8D
    jsr PRINT
    dec a:TEMP2
    bne PRCR1
    jsr GETKEY
    lda #21
    sta a:TEMP2
PRCR1:
    rts

;; Prints the low byte of CNUM as three decimal digits, with leading zeros.
;;
;; Each digit is counted by subtracting its power of ten, from CVTAB, until the low byte is less than it.
;; Only the low byte is compared, so a number of 256 or more prints as itself less a multiple of 256.
;; In:    CNUM = the number
;; Uses:  A, Y, CNUM
PRNUM:
    ldy #2                          ; hundreds, tens, ones
PRN1:
    lda #0                          ; the digit, kept on the stack
    pha
PRN2:
    lda CNUM
    cmp a:CVTAB,y
    bcc PRN3
    sbc a:CVTAB,y
    sta CNUM
    lda CNUM+1
    sbc #0
    sta CNUM+1
    pla
    adc #0                          ; the carry is set here: one more
    pha
    jmp PRN2
PRN3:
    pla
    ora #$B0                        ; the digit "0" to "9"
    jsr PRINT
    dey
    bpl PRN1
    rts

;; Copies the open file's work area from its buffer into FCB, and clears CCBSTA.
;;
;; DOSENT calls it at every entry, so CCBFCB must point at a 45-byte work area for every request, even those
;; that use no file.
;; In:    CCBFCB = address of the file's work area
;; Out:   carry = clear, CCBSTA = 0, ZPGFCB = CCBFCB
;; Uses:  A, X, Y
CLCFCB:
    jsr MVFCBP
    ldy #0
    sty a:CCBSTA
CF3:
    lda (ZPGFCB),y
    sta a:FCB,y
    iny
    cpy #FCBLEN
    bne CF3
    clc
    rts

;; Copies FCB back into the open file's work area, keeping the file manager's state for the next request.
;; RETURN calls it on every exit.
;; In:    CCBFCB = address of the file's work area
;; Out:   ZPGFCB = CCBFCB
;; Uses:  A, X, Y
RTNFCB:
    jsr MVFCBP
    ldy #0
RF1:
    lda a:FCB,y
    sta (ZPGFCB),y
    iny
    cpy #FCBLEN
    bne RF1
    rts
