;; DOS 3.3: THE BOOT LOADER (BOOTLDR)
;;
;; The two pages before RWTS, $B600-$B7FF where DOS runs ($3600-$37FF in the master image), hold the stages of
;; a boot that come after the Disk II's ROM, and the code that writes DOS to a disk for INIT. The boot chain:
;;
;; - BOOT 0, the controller's ROM at $Cn00 (Boot16.asm, docs/DiskII.md), reads track 0 sector 0 into $0800 and
;;   jumps to $0801 with X = slot * 16. Its sector reader, READ at $Cn5C, can be called again: it reads the
;;   sector in $3D into the page in $27 and comes back to $0801.
;; - BOOT 1 is that sector, a copy of the page at TRK0LDR. Running at $0800, it calls READ once for each of
;;   track 0's first ten sectors, reading them backwards into $BF00 down to $B600 (the master: $3F00 to $3600),
;;   then jumps to the page after its own copy: $B700, or the master's $3700.
;; - BOOT 2, DOSLODR, uses RWTS, which BOOT 1 has just loaded with it, to read the rest of DOS from tracks 0 to
;;   2: $9D00-$B5FF, or the master's $1B00-$35FF. It resets the screen and keyboard and ends at DI3.
;; - DI3 jumps to the relocator on a master (Relocator.asm), which moves DOS to the top of memory, or straight
;;   to DBINIT, DOS's cold start (DosInit.asm), on a disk INIT wrote. The relocator changes DI3 to DBINIT, so
;;   every disk INIT writes boots straight into DOS.
;;
;; Between BOOT 1 and the end of its page are patches made to DOS 3.3 later; after BOOT 2 come RWTS's small
;; helpers, the IOB and DCT that DOS passes to RWTS, and the layout of a track/sector list sector.

    ; leftover: the end of the page before, which Apple's source fills to the page boundary
    LEFTOVER $FD, $00
    LEFTOVER $FE, $00
    .assert <* = 0

;; BOOT 1: the boot sector, track 0 sector 0, which BOOT 0 loads at $0800 and enters at $0801. DOS keeps this
;; copy of it at $B600 so that INIT can write it to new disks; it only runs at $0800, where its absolute
;; addresses (LOADADDR, BGRPGC, TABLE) point into the copy at $0800.
;;
;; The first byte, 1, tells BOOT 0 to read just this sector. On the first entry, which it knows because the
;; ROM left the page pointer at $09, BOOT 1 makes $3E-$3F point at READ in the ROM, and LOADADDR at the last
;; page to fill: GRSPG (the boot page's own page number, $B6) plus GRPGC (9). Each entry after that reads
;; the next sector down, until all ten are in; the last is sector 0 again, this sector, into $B600.
;; In:    X = slot * 16; $27 = the page after the last one read
TRK0LDR:
.assert <(TRK0LDR) = 0

;; The pointer to the page the ROM's sector reader fills, the ROM's <Boot16:BUFFER> (2 bytes).
;;
;; BOOT 1 sets its high byte to each page in turn, down from $BF, before it calls READ. On the first entry the
;; ROM has left it at $09, the page after the boot sector, which is how BOOT 1 knows it has just started.
;; See: <BSECTR>, <BTEMP>, <Boot16:BUFFER>
POINTA = $26

;; The slot times 16, which the boot ROM keeps here as <Boot16:SLOTX16>.
;;
;; BOOT 1 makes READ's address, $Cn5C, from it, and passes it on in X, to READ and to BOOT 2.
;; See: <BTEMP>, <Boot16:SLOTX16>
BSLOT = $2B

;; The sector the ROM's sector reader reads next, the ROM's <Boot16:SECTOR>.
;;
;; BOOT 1 sets it from <TABLE> before each call, reading DOS's sectors backwards from the last page down.
;; See: <POINTA>, <TABLE>, <Boot16:SECTOR>
BSECTR = $3D

;; The address of the ROM's sector reader, READ at $Cn5C, which BOOT 1 calls with JMP (BTEMP) (2 bytes).
;;
;; BOOT 1 sets it on its first entry from <BSLOT> and <BRETRY>. READ returns to $0801, BOOT 1's own entry.
;; See: <BSLOT>, <BRETRY>
BTEMP = $3E

BRETRY = $5C                        ;; READ's offset in the ROM's page: READ is at $Cn5C
MONINIT = $FB2F                     ;; the Monitor's INIT: text mode, full-screen window
BHERE3 = <(*)                       ;; offsets in the page, turned into addresses at $0800
BOOTCNT = $800+BHERE3               ;; the count of sectors BOOT 0 reads
    .byte 01
    lda POINTA+1
    cmp #09
    bne READNEXT                    ; called back by READ: read the next sector

; First entry: points BTEMP at READ, $Cn5C, and LOADADDR at the last page to fill.
    lda BSLOT
    lsr a
    lsr a
    lsr a
    lsr a
    ora #$C0
    sta BTEMP+1
    lda #BRETRY
    sta BTEMP
    clc
    lda a:LOADADDR+1
    adc a:BGRPGC
    sta a:LOADADDR+1

; BGRPGC counts DOS's logical sectors down from 9 to 0; TABLE gives the physical sector to read for each. The
; ROM returns to $0801, which comes back here.
READNEXT:
    ldx a:BGRPGC
    bmi GOLOADER                    ; past sector 0: all read
    lda a:TABLE,x
    sta BSECTR
    dec a:BGRPGC
    lda a:LOADADDR+1
    sta POINTA+1
    dec a:LOADADDR+1
    ldx BSLOT
    jmp (BTEMP)

; LOADADDR has gone one page below the boot page; two more make it BOOT 2's page. The input and output hooks
; go back to the keyboard and screen, in case BOOT 0 was started with IN# or PR#.
GOLOADER:
    inc a:LOADADDR+1
    inc a:LOADADDR+1
    jsr SETKBD
    jsr SETVID
    jsr MONINIT
    ldx BSLOT
    jmp (LOADADDR)

;; The physical sector holding each of DOS's logical sectors 0 to 15 on track 0. The address field of each
;; sector holds its physical number, which READ looks for; DOS numbers sectors in a different order, so that
;; sectors it reads one after another are spread around the track.
BHERE2 = <(*)
TABLE = $800+BHERE2
    .byte $00, 13, 11
    .byte 09, 07, 05
    .byte 03, 01, 14
    .byte 12, 10, 08
    .byte 06, 04, 02, 15

; Patches to the APPEND and SAVE commands, from DOS 3.3's revisions, in the space left in the boot page. From
; SC3 to EC3 is a code range for the relocator (Relocator.asm's CDETAB).

;; Set by EOFFIX when a read reaches the end of a file whose position isn't 0; the end of APPEND (BUMPER)
;; then moves the record number on by one.
SC3:
EOFFLAG:
    .byte 0

;; For a file manager call from DOSGO that fails with an error other than END OF DATA: frees the current
;; file's buffer (FILSRC finds it), clears EOFFLAG, and reports the error.
CLOSFILE:
    jsr FILSRC
    bcs NOTFOUND                    ; no buffer
    lda #0
    tay
    sta EOFFLAG
    sta (ZPGWRK),y                  ; a buffer whose name starts with 0 is free
NOTFOUND:
    lda CCBSTA
    jmp ERROR

;; The end of APPEND, once it has read to the end of the file: if EOFFLAG is set, moves the record number in
;; the parameter list on by one; then clears the flag and finishes in FIXIT2.
BUMPER:
    lda EOFFLAG
    beq GOBACK
    inc CCBRRN
    bne GOBACK
    inc CCBRRN+1
GOBACK:
    lda #0
    sta EOFFLAG

.if DOS33B
; In the 1983 DOS, FIXIT2, the patch's last part, is after MSWAIT (MsWait.asm), not in this page.
    jmp FIXIT2
.else
; The 1980 DOS goes straight on to POSITION's file manager call in READ and WRITE (MiscCommands.asm).
    jmp RWP3
.endif

;; The end of SAVE and BSAVE: writes the file through DOSGO, closes it, and then checks it as VERIFY does.
;; In:    A = the request modifier to store in the parameter list
VPATCH:
    sta CCBRQM
    jsr DOSGO
    jsr ECLOSE
    jmp EVAR

;; For a file manager call from DOSGO that ends with END OF DATA. If the file's position is not 0 (bytes $13
;; to $16 of its control block, at ZPGFCB: the sector and byte), sets EOFFLAG. If it is 0, the file is empty:
;; the record number and byte offset in the control block are copied to the parameter list. Either way it goes
;; back to DOSGO2A, which returns a zero data byte.
EOFFIX:
    ldy #$13
CHKFILE:
    lda (ZPGFCB),y
    bne FIXIT
    iny
    cpy #$17
    bne CHKFILE
    ldy #$19
MOVE:
    lda (ZPGFCB),y
    sta CCBRRN-$19,y
    iny
    cpy #$1D
    bne MOVE
BACK:
    jmp DOSGO2A
FIXIT:
    ldx #$FF
    stx EOFFLAG
    bne BACK                        ; always

; A build option Apple's source has (ULC = 1): a routine that turns the input line's lowercase letters,
; outside quotes, into capitals. The 1983 DOS was built without it.
.if ULC
UPRCASE:
LUP1:
    lda LBUFF,x
    cmp #'"'+$80
    bne CHK4UC
LUP2:
    inx
    lda LBUFF,x
    cmp #'"'+$80
    beq NEXTCHR
    cmp #$8D
    bne LUP2
ULFINI:
    ldy #$FF
    sty CMDNO
    rts
CHK4UC:
    cmp #$E0
    bcc CHK4CR
    and #$DF
    sta LBUFF,x
CHK4CR:
    cmp #$8D
    beq ULFINI
NEXTCHR:
    inx
    bne LUP1
.endif

; Zeros up to the boot page's last three bytes. In Apple's listing FIXIT2 is here; the master has it elsewhere.
BHERE1 = <(*)
.if YEAR = 1983
    .res $FD-BHERE1,0
.else
    ; leftover: what the 1980 master holds here
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $20, $58, $FC
    .byte $A9, $C2, $20, $ED, $FD, $A9, $01, $20, $DA, $FD, $A9, $AD, $20, $ED, $FD, $A9
    .byte $00, $20, $DA, $FD, $60, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
.endif

; The boot page's last three bytes are BOOT 1's variables. LOADADDR, read as a word, is the page BOOT 1 loads
; into next and finally BOOT 2's address; its high byte starts as GRSPG.
BHERE4 = <(*)
LOADADDR = $800+BHERE4              ;; BOOT 1's load address (2 bytes, the high byte GRSPG)
    .byte 0

;; The page of TRK0LDR: where BOOT 1 loads track 0's sectors, from this page up. WBOOT sets it to where the
;; running DOS is, so a disk takes its loader to the same place.
GRSPG:
    .byte >(TRK0LDR)
BHERE5 = <(*)
BGRPGC = $800+BHERE5                ;; GRPGC as BOOT 1 sees it at $0800

;; The last logical sector BOOT 1 reads, 9: it reads sectors 9 down to 0, ten pages from TRK0LDR to the end
;; of DOS.
GRPGC:
    .byte >(ENDOFDOS-TRK0LDR-$100)

;; BOOT 2, entered from BOOT 1 at $B700 (the master: $3700). It reads the rest of DOS through RWTS, NDPGS
;; pages from track 2 sector 4 backwards to track 0 sector 12 (the master: sector 10), into the pages from just
;; below TRK0LDR down. BOOT 1 left RWTS and this page in place.
;;
;; It records the boot slot and drive 1 in the IOB, and tells RWTS that the drive's head is on track 0
;; (RWTS keeps each drive's track at $478 + slot and $4F8 + slot; BOOT 0 left the head on track 0).
;; In:    X = slot * 16
DOSLODR:
.assert <(DOSLODR) = 0
    stx a:IBSLOT
    stx a:IBPSLT
    lda #1
    sta a:IBPDRV
    sta a:IBDRVN
    lda a:NDPGS
    sta a:BRWCNT
    lda #2
    sta a:IBTRK
    lda #4
    sta a:IBSECT
    ldy a:ADOSLD+1
    dey
    sty a:IBBUFP+1                  ; the page below TRK0LDR first
    lda #IBCRTS
    sta a:IBCMD
    txa
    lsr a
    lsr a
    lsr a
    lsr a
    tax
    lda #0
    sta $4F8,x
    sta $478,x
    jsr BOOTIO

;; DOS is in memory: starts it. A new stack, IBVOL set to $FF as the file manager leaves it, the screen and
;; language card reset (RCPATCH, in DosPatches.asm, which comes back to RCBACK), the keyboard as input, then
;; on to DI3.
DOSINT:
    ldx #$FF
    txs
    stx a:IBVOL
    jmp RCPATCH
RCBACK:
    jsr SETKBD

;; The end of a boot: jumps to the relocator on a master. The relocator rewrites it to jump to DBINIT; in the
;; running build DOSREL is DBINIT itself.
DI3:
    jmp DOSREL

;; Writes DOS to tracks 0 to 2 of a disk, for INIT, once DLDSUP has set the IOB's buffer to DOS's first page.
;;
;; First the pages from there up to TRK0LDR, from track 2 sector 4 backwards (the last page first). Then the
;; ten pages from TRK0LDR to the end of DOS, to track 0 sectors 9 down to 0: the boot sector, BOOT 2 and RWTS.
;; Before that, GRSPG is set to this DOS's TRK0LDR page and GRPGC to 9, so the boot sector written loads to
;; where this DOS is. The first pass leaves IBTRK at 0 for the second.
;; Errors: carry = set if RWTS failed on the last sector (BOOTIO doesn't stop on an error)
WBOOT:
    lda a:ADOSLD+1
    sec
    sbc a:IBBUFP+1
    sta a:BRWCNT
    lda a:ADOSLD+1
    sta a:IBBUFP+1
    dec a:IBBUFP+1
    lda #2
    sta a:IBTRK
    lda #4
    sta a:IBSECT
    lda #2                          ; IBCWTS: write
    sta a:IBCMD
    jsr BOOTIO
    lda a:ADOSLD+1
    sta GRSPG
    clc
    adc #9
    sta a:IBBUFP+1
    lda #10
    sta a:BRWCNT
    sec
    sbc #1
    sta GRPGC
    sta a:IBSECT
    jsr BOOTIO
    rts
    .res 6,0                        ; unused

;; Reads or writes BRWCNT pages through RWTS, as the IOB says, from the page and sector it gives backwards:
;; after each page, one page lower in memory and one sector lower on the disk, from sector 0 to sector 15 of
;; the track before. It doesn't stop on an error: the carry it returns is that of the last page.
BOOTIO:
    lda a:BAIOB+1
    ldy a:BAIOB
    jsr DISKIO
    ldy a:IBSECT
    dey
    bpl BIO1
    ldy #15
    nop
    nop
    dec a:IBTRK
BIO1:
    sty a:IBSECT
    dec a:IBBUFP+1
    dec a:BRWCNT
    bne BOOTIO
    rts

;; Calls RWTS with interrupts off: RWTS's timing can't be interrupted. DOS's $3D9 entry comes here.
;; In:    A = the IOB's address's high byte, Y = its low byte
;; Out:   carry = clear if the call succeeded, set if not (the error in the IOB's IBSTAT)
DISKIO:
    php
    sei
    jsr RWTS
    bcs DSKERR

; PLP brings back the caller's interrupt flag, and its carry too: the carry is set again after it.
    plp
    clc
    rts
DSKERR:
    plp
    sec
    rts

;; Prepares the IOB for WBOOT: the buffer at the page in CCBBSA (DOS's first page, which INIT takes from
;; ASTART), and the volume from DCBVOL, which holds it inverted.
DLDSUP:
    lda CCBBSA
    sta a:IBBUFP+1
    lda #0
    sta a:IBBUFP
    lda DCBVOL
    eor #$FF
    sta a:IBVOL
    rts

;; Zeros the page at ZPGFCB.
;; Out:   A = 0, Y = 0
CLRSEC:
    lda #0
    tay
CS1:
    sta (ZPGFCB),y
    iny
    bne CS1
    rts
    brk                             ; unused

;; The number of pages BOOT 2 reads: from BEGIN up to TRK0LDR, 25 ($19) where DOS runs, 27 ($1B) on the
;; master, which includes the relocator.
EC3:
NDPGS:
    .byte >(TRK0LDR-BEGIN)

;; Pages left for BOOTIO to read or write.
BRWCNT:
    LEFTOVER $00, $02

; Two bytes no code reads: $0A (10) and $1B (27).
    .byte $0A
    .byte $1B

;; The IOB's address, for BOOTIO.
BAIOB:
    .word IOB

;; The address of the boot page, TRK0LDR: BOOT 2 loads DOS below it and WBOOT writes from it.
ADOSLD:
    .word TRK0LDR

;; The IOB, the parameter list for a call to RWTS: DOS's own, which BOOT 2, the file manager and INIT fill in.
;; Beneath Apple DOS chapter 6 describes it field by field.
IOB:
IBTYPE:
    .byte 1                         ; the IOB's type, always 1
IBSLOT:
    .byte 6*16                      ; slot * 16
IBDRVN:
    .byte 1                         ; drive, 1 or 2
IBVOL:
    .byte $00                       ; the volume expected, 0 for any
IBTRK:
    .byte 0                         ; track, 0 to 34
IBSECT:
    LEFTOVER $00, $01               ; sector, 0 to 15 (logical)
IBDCTP:
    .word DCT                       ; the address of the drive's DCT
IBBUFP:
    LEFTOVER $00, $00               ; the address of the 256-byte buffer
    LEFTOVER $00, $37
IBDLEN:
    LEFTOVER $00, $00               ; data length
    LEFTOVER $01, $00
IBCMD:
    LEFTOVER $00, $02               ; the command
IBCNUL = 0                          ;; command: seek only
IBCRTS = 1                          ;; command: read a sector
IBCWTS = 2                          ;; command: write a sector
IBFMT = 4                           ;; command: format the disk
IBBOOT = 8                          ;; command: write the boot tracks; no code here uses it
IBSTAT:
    LEFTOVER $00, $07               ; the error, when RWTS returns with the carry set
IBRERR = $80                        ;; error: a sector couldn't be read
IBDERR = $40                        ;; error: the drive failed
IBVMME = $20                        ;; error: the disk's volume isn't the one expected
IBWPER = $10                        ;; error: the disk is write-protected
IBSMOD:
    LEFTOVER $00, $FE               ; the volume RWTS found
IBPSLT:
    .byte 6*16                      ; the slot * 16 of the previous call
IBPDRV:
    .byte 1                         ; the drive of the previous call
IBSPAR:
    .res 2,0                        ; spare

;; The DCT, the device characteristics table: device type 0, one phase per track, and the motor-on time
;; ($D8EF, low byte first).
DCT:
    .byte 0, 1, $EF, $D8
    .res 1,0                        ; unused, the page's last byte

.dum 0

;; The layout of a track/sector list sector, which Apple's names call a file directory: offsets into it.
;; Bytes 1 and 2 link to the next such sector, bytes 5 and 6 give the file's sector number of the first pair
;; here, and the track and sector pairs start at FDENT. Code reads the fields with Y = an offset.
FILDIR:
FDUCDE:
    .res 1
FDLTRK:
    .res 1
FDLSEC:
    .res 1
FDNSA:
    .res 1
FDLSDL:
    .res 1
FDFRS:
    .res 2
FDSPAR:
    .res 5
FDENT:
    .res 1
FDTRK = 0                           ;; in a pair: the track
FDSEC = 1                           ;; in a pair: the sector
FDLAST = FILDIR+256                 ;; the end of the sector
.dend
