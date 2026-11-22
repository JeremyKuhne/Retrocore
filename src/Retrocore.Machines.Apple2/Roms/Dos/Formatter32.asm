;; DOS 3.2 RWTS: FORMAT A DISK
;;
;; DSKFORM formats all 35 tracks for INIT, which RWTS reaches with command 4 (Rwts32.asm). Each track gets 13
;; address fields with self-sync bytes between them, but no data fields: where each sector's data field will
;; be, it writes $FF nibbles, and WRITE13 writes the data field the first time the sector is written. INIT
;; then writes DOS, the VTOC and the catalog. Runs at $BE9C-$BFD4 where DOS runs; DOS 3.3's formatter, in a
;; module of its own, writes data fields and checks every sector. docs/DiskII.md explains the fields and
;; self-sync bytes.

;; Formats the disk in the IOB's drive with volume NVOL, track 0 to track 34, and returns through RWTS's exits.
;;
;; It moves the head to track 0 by seeking from half-track 128, far enough out to stop against track 0 from
;; anywhere. Each track starts with about ten thousand self-sync bytes, more than a turn of the disk, which
;; erase it; the end of that run is the start of the track. Then come the sectors in the order 0, 10, 7, 4, 1,
;; 11, 8, 5, 2, 12, 9, 6, 3, each three less than the one before, modulo 13: for each, GAPLEN self-sync
;; bytes, an address field and $FF nibbles where the data field goes.
;;
;; After the track it waits, reads an address field, and expects sector 0, the first one written. If it finds
;; no address field or another sector's, it formats the track again with GAPLEN one less. It starts with GAPLEN
;; at 80 and adds 2 for each track after the first. It also uses SEEK's variables.
;; In:    X = slot * 16, FormatVolume = the volume, the drive running
;; Out:   carry = clear (ALLDONE)
;; Errors: carry set with IBDERR if the disk is write-protected (found after the first track) or GAPLEN would
;;   fall below 16
;; Uses:  A, Y, FormatTrack, FormatSector, GAPLEN, GAPCNT, FormatMask
DSKFORM:
    lda #$80
    sta CurrentTrack
    lda #0
    sta FormatTrack
    jsr SEEK
    lda #$AA
    sta FormatMask
    ldy #$50                        ; GAPLEN: 80 self-sync bytes before each address field

;; Formats track TRK, then the tracks after it.
;; In:    Y = GAPLEN, the head on track FormatTrack
FORMTRK:
    sty GAPLEN
    lda #$27                        ; after the first Y bytes, 38 runs of 256
    sta FormatSector
    lda LoadLatch,x
    lda ReadMode,x
    lda #$FF
    sta WriteMode,x                       ; write mode, $FF in the latch
    cmp DataLatch,x
    bit $00                         ; timing

; The self-sync bytes that erase the track: $FF every 36 cycles, which writes it with one 0 bit after it. NSECT
; counts the runs of 256 down to 0, the first sector's number. The BCS is always taken: no byte is above $FF.
FERASE:
    dey
    beq FERASE3
    pha
    pla
    nop
FERASE2:
    pha
    pla
    nop
    nop
    sta LoadLatch,x
    cmp DataLatch,x
    bcs FERASE                      ; always
FERASE3:
    dec FormatSector
    bne FERASE2

; Each sector: GAPLEN self-sync bytes, 36 cycles apart, then its address field.
    ldy GAPLEN
    nop
    nop
    bne FSYNC2                      ; always
FSYNC:
    pha
    pla
    pha
    pla
    cmp ($00,x)                     ; timing: 6 cycles
FSYNC2:
    nop
FSYNC3:
    sta LoadLatch,x
    cmp DataLatch,x
    dey
    bne FSYNC

; The address field: D5 AA B5, the volume, track, sector and their checksum in 4-and-4, and DE AA EB, each
; nibble 32 cycles after the one before.
    lda #$D5
    jsr WNIBLA
    lda #$AA
    jsr WNIBLB2
    lda #$B5
    jsr WNIBLB2
    lda FormatVolume
    jsr WBYTE
    lda FormatTrack
    jsr WBYTE
    lda FormatSector
    jsr WBYTE
    lda FormatVolume
    eor FormatTrack
    eor FormatSector                       ; the checksum, written as WBYTE would, inline
    pha
    lsr a
    ora FormatMask
    sta LoadLatch,x
    cmp DataLatch,x
    pla
    ora #$AA
    jsr WNIBLA
    lda #$DE
    jsr WNIBLB2
    lda #$AA
    jsr WNIBLB2
    lda #$EB
    jsr WNIBLB2
    lda #$FF
    jsr WNIBLB2

; Where the data field goes: $FF nibbles, 32 cycles apart, $AD then 256 of them.
    ldy #2
    sty GAPCNT
    ldy #$AD
    bne FDATA2                      ; always
FDATA:
    dey
    beq FDATA3
    pha
    pla
    nop
FDATA2:
    pha
    pla
    sta LoadLatch,x
    cmp DataLatch,x
    bcs FDATA                       ; always
FDATA3:
    dec GAPCNT
    bne FDATA2
    ldy GAPLEN
    clc
    bit $00                         ; timing
    sta LoadLatch,x
    lda DataLatch,x

; The next sector: NSECT + 10, less 13 if that is 13 or more. Reaching 13 exactly means sector 3, the last,
; is done. The carry is clear, so the SBC subtracts 13.
    lda FormatSector
    adc #$0A
    sta FormatSector
    sbc #$0C
    beq FTRKEND
    bcs FNEXT
    .byte $2C                       ; BIT absolute: skips the STA, keeping NSECT + 10
FNEXT:
    sta FormatSector
    lda #$FF
    jmp FSYNC3

; The track is written. Back to read mode; if the disk is write-protected, that is an error now.
FTRKEND:
    pha
    pla
    ldy GAPLEN
    lda LoadLatch,x
    lda ReadMode,x
    bmi FERR
    dey
FWAIT:
    pha
    pla
    nop
    nop
    bit $00
    pha
    pla
    dey
    bne FWAIT

; The first address field read must be sector 0's.
    jsr RDADR13
    bcs FSHORTER
    lda SECT
    beq FNEXTTRK
FSHORTER:
    ldy GAPLEN
    dey
    cpy #$10
    bcc FERR
    jmp FORMTRK

; On to the next track, with two more self-sync bytes in each gap.
FNEXTTRK:
    inc FormatTrack
    lda FormatTrack
    cmp #$23
    bcs FDONE                       ; all 35 done
    asl a                           ; the half-track
    jsr SEEK
    ldy GAPLEN
    iny
    iny
    sty GAPLEN
    jmp FORMTRK
FERR:
    lda #RWTS_DRIVE_ERROR
    jmp HNDLERR
FDONE:
    jmp ALLDONE

;; Writes the byte in A as two 4-and-4 nibbles, its odd bits then its even bits, 32 cycles apart.
;;
;; The first nibble is the byte shifted right with every other bit set, through AA, the zero-page byte that
;; holds $AA: an `ORA zp` takes the 3 cycles the timing needs where `ORA #$AA` takes 2.
;; In:    A = the byte, X = slot * 16, FormatMask = $AA, the card in write mode
;; Uses:  A
;; Keeps: X, Y
WBYTE:
    pha
    lsr a
    ora FormatMask
    sta LoadLatch,x
    cmp DataLatch,x
    pla
    cmp ($00,x)                     ; timing: 6 cycles
    ora #$AA

;; Writes the nibble in A, 32 cycles after the last store when the caller's code between them is an
;; `LDA #nibble` and a JSR to WNIBLB2.
;; In:    A = the nibble, X = slot * 16, the card in write mode
;; Keeps: A, X, Y
;; Entry: WNIBLB2 = 2 cycles less delay
WNIBLA:
    nop
WNIBLB2:
    pha
    pla
    nop
    sta LoadLatch,x
    cmp DataLatch,x
    rts

; Unused: nothing calls this code. With X = $FF it goes on to EPOS, the POSITION command (MiscCommands.asm);
; otherwise it returns.
CHKPOSITION:
    inx
    beq CHKPOSITION_1
    rts
CHKPOSITION_1:
    jmp EPOS
