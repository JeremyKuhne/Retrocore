;; DOS 3.3 AND 3.2 FILE MANAGER: CATALOG SEARCH, SECTOR ALLOCATION AND EXITS (FLOCSEC)
;;
;; The file manager's lower half, part two. FNDFIL finds a file's entry in the catalog, or a free entry for a
;; new file. GETSEC hands out free sectors, FRETRK and FRESEC give them back to the VTOC's free-sector bit
;; map, and LOCSEC turns a record number and byte offset into a position in the file. The routines at the
;; end are the way out of every file manager request: GOODIO for success, ERROR1 to ERRR10 and ERRORB for the
;; return codes, all ending in RETURN, which hands the file control block back and returns to the caller.
;;
;; Where DOS runs, this is $B1C9-$B396. FileLocateNextByte.asm has the disk I/O routines used here (RDVTOC,
;; RDVDIR, DCBIO); FileManagerData.asm lays out the VTOC and catalog buffers and the file control block (the
;; DCB... fields). docs/Dos.md describes the VTOC, its bit map and the catalog.

;; Finds a file in the catalog by name or, failing that, claims a free catalog entry and puts the name in it.
;;
;; Reads the VTOC, then makes up to two passes along the chain of catalog sectors. TEMP2 is 1 on the first:
;; it compares the name with each entry in use, skipping deleted ones ($FF in the first byte), and stops at
;; the first entry never used (0), since every entry after it is unused too. TEMP2 is 0 on the second: it
;; starts again at the first catalog sector and takes the first entry that is deleted or never used, copying
;; the name into it in the buffer only; DOPEN decides whether to create the file and write the sector.
;;
;; DCBVDR counts the catalog sectors read, 1 for the first, so that CLOSE can read the entry's sector again.
;; In:    CCBFN1 = the address of the name, 30 characters padded with spaces
;; Out:   carry clear when found, set when a free entry now holds the name; either way X = TEMP1 = the
;;   entry's offset in VDFILE, VOLDIR = its catalog sector and DCBVDR = that sector's place in the chain
;; Errors: does not return when the catalog has no free entry (ERROR9, DISK FULL) or on a disk error
;; Uses:  A, X, Y, ZPGFCB, TEMP1, TEMP2
;; See:   <DOPEN>
FNDFIL:
    jsr RDVTOC
    lda a:CCBFN1
    sta ZPGFCB
    lda a:CCBFN1+1
    sta ZPGFCB+1
    lda #1                          ; the first pass
FF1:
    sta a:TEMP2                     ; A = 1 for the first pass, 0 for the second
    lda #0
    sta a:DCBVDR
    clc                             ; RDVDIR: the first catalog sector
FF2:
    inc a:DCBVDR
    jsr RDVDIR
    bcs FF4A                        ; no more catalog sectors
    ldx #0
; Each entry: X = its offset in VDFILE, kept in TEMP1.
FF3:
    stx a:TEMP1
    lda a:VDFILE,x
    beq FF6                         ; never used
    bmi FF7                         ; deleted
    ldy #0
    inx                             ; the name starts at the entry's byte 3
    inx
FF4:
    inx
    lda (ZPGFCB),y
    cmp a:VDFILE,x
    bne FF5
    iny
    cpy #30
    bne FF4
    ldx a:TEMP1                     ; all 30 match: found
    clc
    rts
FF5:
    jsr VDINC
    bcc FF3
    bcs FF2                         ; the end of this sector: carry set, so RDVDIR reads the next one
; A never-used entry: the first pass ends here and starts the second, with A = 0 from the entry; the second
; pass falls through to take the entry.
FF6:
    ldy a:TEMP2
    bne FF1
; A deleted entry: the first pass skips it, the second takes it.
FF7:
    ldy a:TEMP2
    bne FF5
;; Copies a file name into a catalog entry in the catalog buffer.
;;
;; FNDFIL falls into it to claim a free entry; RENAME calls it to put the new name in the file's entry.
;; In:    X = TEMP1 = the entry's offset in VDFILE, ZPGFCB = the address of the 30-character name
;; Out:   carry set, X = TEMP1
;; Uses:  A, Y
MVFN:
    ldy #0
    inx
    inx
FF8:
    inx
    lda (ZPGFCB),y
    sta a:VDFILE,x
    iny
    cpy #30
    bne FF8
    ldx a:TEMP1
    sec
    rts
;; Steps to the next of the seven 35-byte file entries in the catalog sector.
;; In:    TEMP1 = the offset of the current entry in VDFILE
;; Out:   X = the offset of the next entry, carry set when there is none in this sector
;; Uses:  A
VDINC:
    clc
    lda a:TEMP1
    adc #35
    tax
    cpx #VDFLEN
    rts
; The end of the catalog: after the first pass, start the second; after the second, the catalog is full.
FF4A:
    lda #0
    ldy a:TEMP2
    bne FF1
    jmp ERROR9
;; Allocates a free sector for the open file, from the track reserved for it or from a newly reserved track.
;;
;; The file manager reserves a whole track for a file at a time. It copies the track's 4-byte free-sector map
;; from the VTOC into DCBABM, marks the whole track used in the VTOC and writes the VTOC. Sectors are then
;; handed out from DCBABM without touching the disk, and CLOSE gives the unused ones back (FRETRK).
;;
;; Handing out: DCBALS counts down through the sector numbers, from VNOSEC - 1. Each step rotates the 32 bits
;; of DCBABM left by one, which brings the bit of sector DCBALS out into carry: the map's first byte holds
;; sectors 15 to 8 and its second 7 to 0, highest bit first (in DOS 3.2, 12 to 5 and 4 to 0). A set bit is a
;; free sector.
;;
;; Reserving: the VTOC remembers the last track it reserved (VALCA1) and the direction it was moving (VALCA2,
;; 1 or -1), and the search steps from there until it finds a track with a free sector, moving away from the
;; catalog on track 17. Running off the last track turns it round to go down from track 16; reaching track 0
;; turns it round to go up from track 18. Reaching track 0 a second time means every track has been looked
;; at, and the disk is full. Tracks 0 and 17 are never reserved.
;; In:    DCBATK = the reserved track, or 0 for none, DCBALS/DCBABM = what is left of it
;; Out:   A = the sector, DCBATK = its track, DCBNSA = one more sector in the file
;; Errors: does not return when the disk is full (ERROR9) or on a disk error
;; Uses:  A, X, Y, TEMP3
GETSEC:
    lda a:DCBATK
    beq GSS1                        ; no track reserved yet
GS0:
    dec a:DCBALS
    bmi CS2                         ; every sector of this track has been tried
    clc
    ldx #4
GS1:
    rol a:DCBABM-1,x                ; DCBABM+3 first, so the bit leaving DCBABM+0 lands in carry
    dex
    bne GS1
    bcc GS0                         ; that sector is in use
    inc a:DCBNSA
    bne GS1A
    inc a:DCBNSA+1
GS1A:
    lda a:DCBALS
    rts
CS2:
    lda #0
    sta a:DCBATK
; Reserve a new track. TEMP3 becomes 1 once the search has turned round at track 0.
GSS1:
    lda #0
    sta a:TEMP3
    jsr RDVTOC
GS2:
    clc
    lda a:VALCA1
    adc a:VALCA2                    ; the next track in the current direction
    beq GS3
    cmp a:VNOTRK
    bcc GS5
    lda #$FF                        ; past the last track: go down, from 16
    bne GS4
GS3:
    lda a:TEMP3                     ; at track 0: go up, from 18, unless that was done already
    bne ERR9
    lda #1
    sta a:TEMP3
GS4:
    sta a:VALCA2
    clc
    adc #17
GS5:
    sta a:VALCA1
    sta a:DCBATK
    tay                             ; (has no effect: Y is set again below)
    asl a
    asl a
    tay                             ; Y = the track * 4, its map's offset in VSECAL
    ldx #4
    clc
; Move the track's map into DCBABM, clearing it in the VTOC. Carry ends set if any sector was free.
GS6:
    lda a:VSECAL+3,y
    sta a:DCBABM-1,x
    beq GS7
    sec
    lda #0
    sta a:VSECAL+3,y
GS7:
    dey
    dex
    bne GS6
    bcc GS2                         ; nothing free on this track
    jsr WRVTOC
    lda a:VNOSEC
    sta a:DCBALS
    bne GS0                         ; always taken
ERR9:
    jmp ERROR9
;; Gives the sectors the file did not use on its reserved track back to the VTOC, and writes the VTOC.
;;
;; CLOSE calls it. The reservation is dropped (DCBATK = 0), so the next write reserves a track again.
;; In:    DCBATK = the reserved track, or 0 for none (then nothing happens), DCBALS/DCBABM = what is left of it
;; Out:   DCBATK = 0
;; Errors: does not return on a disk error
;; Uses:  A, X, Y
;; See:   <GETSEC>, <FRESEC>
FRETRK:
    lda a:DCBATK
    bne FT1
    rts
FT1:
    pha
    jsr RDVTOC
    ldy a:DCBALS
    pla
    clc                             ; shift in zeros: the sectors handed out stay in use
    jsr FRESEC
    lda #0
    sta a:DCBATK
    jmp WRVTOC
;; Shifts a sector map in DCBABM into place and marks its sectors free in the VTOC buffer.
;;
;; The map is rotated right once for each sector number from Y up to VNOSEC - 1, taking carry in at the top
;; the first time. Two callers use it two ways:
;; - FRETRK, with carry clear and Y = DCBALS, undoes GETSEC's left rotations, so that only the sectors not yet
;;   handed out are freed.
;; - DELETE (FDSUB), with DCBABM all zeros, carry set and Y = a sector, builds a map of that one sector.
;;
;; The map is then ORed into the track's bit map in the VTOC buffer; the caller writes the VTOC. Track 0, the
;; DOS image, is never changed.
;; In:    A = the track, Y = the sector, carry = the first bit to shift in, DCBABM = the map
;; Out:   VSECAL = the track's bit map, updated
;; Uses:  A, X, Y
FRESEC:
FS1:
    ldx #252                        ; X = 252..255 walks DCBABM+0..+3, ending at 0
FS2:
    ror a:DCBABM-252,x
    inx
    bne FS2
    iny
    cpy a:VNOSEC
    bne FS1
    asl a
    asl a
    tay                             ; Y = the track * 4, its map's offset in VSECAL
    beq FS4
    ldx #4
FS3:
    lda a:DCBABM-1,x
    ora a:VSECAL+3,y
    sta a:VSECAL+3,y
    dey
    dex
    bne FS3
FS4:
    rts
;; Sets the file's position from a record number and a byte offset: record * record length + offset.
;;
;; A 16-by-16-bit shift-and-add multiply. The record number starts in DCBCRS:DCBCSB as the multiplier; on each
;; of 16 steps its low bit decides whether the record length is added to the top half, then the whole of
;; A:DCBCRS+1:DCBCRS:DCBCSB shifts right, moving the product in as the multiplier moves out. The byte offset
;; is then added. The low byte of the result is the byte in the sector (DCBCSB) and the next two the relative
;; sector (DCBCRS); the top byte, in A, is dropped. The next LOCNXB reads the sector.
;;
;; The 1982 revision (DOS33B) adds the CLC before the addition. Without it, the carry left by the last shift
;; (the record number's top bit) is added too, so a record number of $8000 or more lands one byte too far:
;; with a record length of 1, any position past $7FFF. It also carries into DCBCRS+1 with a branch, which
;; leaves room for the CLC; two zero bytes pad it to the old length, so nothing after it moves. DOS 3.2, which
;; came before the revision, lacks the CLC too.
;; In:    CCBRRN = the record number, CCBBYT = the byte offset, DCBRCL = the record length
;; Out:   DCBCRS = the relative sector, DCBCSB = the byte in it, DCBCRR = the record number,
;;   DCBCRB = the byte offset
;; Uses:  A, X, Y
LOCSEC:
    lda a:CCBRRN
    sta a:DCBCSB
    sta a:DCBCRR
    lda a:CCBRRN+1
    sta a:DCBCRS
    sta a:DCBCRR+1
    lda #0
    sta a:DCBCRS+1
    ldy #16
LS1:
    tax                             ; X = the product's top byte, while A tests the multiplier
    lda a:DCBCSB
    lsr a
    bcs LS1A
    txa
    bcc LS2                         ; always taken
LS1A:
    clc
    lda a:DCBCRS+1                  ; add the record length to the top half
    adc a:DCBRCL
    sta a:DCBCRS+1
    txa
    adc a:DCBRCL+1
LS2:
    ror a
    ror a:DCBCRS+1
    ror a:DCBCRS
    ror a:DCBCSB
    dey
    bne LS1
.if DOS33B
    clc
.endif
    lda a:CCBBYT
    sta a:DCBCRB
    adc a:DCBCSB
    sta a:DCBCSB
    lda a:CCBBYT+1
    sta a:DCBCRB+1
    adc a:DCBCRS
    sta a:DCBCRS
.if DOS33B
    bcc DONTINC
    inc a:DCBCRS+1
DONTINC:
    rts
    .res 2,$00
.else
    lda #0
    adc a:DCBCRS+1
    sta a:DCBCRS+1
    rts
.endif
; The file manager's exits. Each ERROR entry loads a return code (FileManagerData.asm lists them; the command
; interpreter's message for each is in CommandTables.asm) and goes to ERRORA.

;; Leaves the file manager with return code 1, CREFUN: LANGUAGE NOT AVAILABLE in DOS's messages.
ERROR1:
    lda #CREFUN
    bne ERRORA
;; Leaves the file manager with return code 2, CRERR: the request code is out of range.
ERROR2:
    lda #CRERR
    bne ERRORA
;; Leaves the file manager with return code 3, CREMRE: the READ or WRITE subcode is out of range.
ERROR3:
    lda #CREMRE
    bne ERRORA
;; Leaves the file manager with return code 4, CREPRO: WRITE PROTECTED.
ERROR4:
    lda #CREPRO
    bne ERRORA
;; Leaves the file manager with return code 5, CREEOF: END OF DATA.
ERROR5:
    lda #CREEOF
    bne ERRORA
;; Leaves the file manager with return code 6, CREFNF: FILE NOT FOUND.
ERROR6:
    lda #CREFNF
    bne ERRORA
;; Leaves the file manager with return code 9, DISK FULL, through ERROR9X, which first closes the open files.
;;
;; The jump and NOP fill the same four bytes as the other entries, so the routines after keep their addresses.
;; See:   <ERROR9X>
ERROR9:
    jmp ERROR9X
    nop
;; Leaves the file manager with return code 10, CREFLK: FILE LOCKED.
ERRR10:
    lda #CREFLK
    bne ERRORA
;; Ends a file manager request successfully: returns to the file manager's caller with carry clear.
;;
;; The return code is whatever is already in CCBSTA: 0, which the entry sets, or CREFNF from DOPEN when it
;; has just created the file.
;; Out:   A = CCBSTA, carry = clear
GOODIO:
    lda a:CCBSTA
    clc
    bcc RETURN                      ; always taken
;; Ends a file manager request with an error: returns to the file manager's caller with carry set.
;;
;; RETURN, shared with GOODIO, stores the return code, clears $48, copies the file control block back to the
;; caller's workarea (RTNFCB), and returns to whoever called the file manager by restoring the stack pointer
;; saved on entry (ENTSTK), however deep the request was. RWTS keeps its IOB pointer at $48-$49; $48 is also
;; where the Monitor keeps the processor status that its G command loads, so it is cleared rather than left
;; holding part of an address.
;; In:    A = the return code
;; Out:   CCBSTA = A, carry = set
;; Entry: ERRORB = the same, RETURN = with carry already set or clear
ERRORA:
ERRORB:
    sec
RETURN:
    php
    sta a:CCBSTA
    lda #0
    sta $48
    jsr RTNFCB
    plp
    ldx a:ENTSTK
    txs
    rts
;; The end of the relocator's second code range, USERENT to here: the file manager's code. The relocator
;; adjusts addresses only inside its code ranges; the buffers that follow hold none.
EC2:
