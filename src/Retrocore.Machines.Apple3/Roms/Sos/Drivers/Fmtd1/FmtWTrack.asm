; Writing and verifying a track. Included by Fmtd1.asm.

;; Writes a track's sixteen sectors and verifies them, rewriting it up to <DCB_TRKRETRY> times.
;;
;; The first write leaves 128 self-sync nibbles before sector 0, more than any gap, so that the whole track is
;; erased; the other gaps get NSYNC. The verify waits out the gap after sector 15, then expects sector 0's address
;; field: when another sector comes first, the gaps were too large for the drive's speed, so NSYNC shrinks by one and
;; the track is written again. It then reads every sector's data field, each once. A rewrite starts just after sector
;; 15, to put sector 0 back where it was. Capping the rewrites keeps the track from creeping round the disk, which
;; could move a bad spot out of a gap and into a sector.
;; In: TRK = the track, NSYNC = the gap's self-sync nibbles, the head on the track, the sector image encoded
;; Out: carry = set if the disk is write-protected, the track won't verify, or NSYNC fell below <DCB_MINSYNC>,
;;   NSYNC = the gap that fit
;; Uses: A, X, Y, NSECT, RETRYCNT, TRKRETRY, FOUND
WT16:
    lda a:DCB_TRKRETRY
    sta TRKRETRY

;; Writes the track from sector 0, with a 128-nibble gap before it.
WTRETRY:
    ldy #128
    lda #$00
    sta NSECT
    jmp WSECT0

;; Writes the next sector, with a gap of NSYNC self-sync nibbles.
WSECT:
    ldy NSYNC
WSECT0:
    ldx #$60
    jsr WADR16
    bcc WSECT0_010
    jmp WEXIT2                          ; write-protected
WSECT0_010:
    ldx #$60
    jsr WRITE16
    bcc WSECT0_020
    jmp WEXIT2                          ; write-protected
WSECT0_020:
    inc NSECT
    lda NSECT
    cmp #16
    bcc WSECT
    ldy #16-$01                         ; verify: sixteen sectors to find
    sty NSECT
    lda a:DCB_SECTRETRY
    sta RETRYCNT

;; Marks every sector not found yet: <FOUND> gets the retry count, which is positive.
CLRFOUND:
    sta a:FOUND,y
    dey
    bpl CLRFOUND
    lda NSYNC
    sec
    sbc #$05                            ; two nibbles have passed, and five are left for the read to sync
    tay

;; Waits 40 cycles for each self-sync nibble of the gap after sector 15, so that a gap too small to be found shows.
S0DELAY:
    jsr WEXIT2
    jsr WEXIT2
    pha
    pla
    nop
    nop
    dey
    bne S0DELAY
    ldx #$60
    jsr RDADR16
    bcs REWRITE
    lda SECT
    beq VDATA                           ; sector 0 came first
    dec NSYNC                           ; the gaps are too large: shrink them
    lda NSYNC
    cmp a:DCB_MINSYNC
    bcs REWRITE
    sec                                 ; too small: the drive is too fast
    rts

;; Reads the next address field, to verify its sector.
VSECT:
    ldx #$60
    jsr RDADR16
    bcs VERR1

;; Reads a sector's data field and marks the sector found, until all sixteen are.
VDATA:
    ldx #$60
    jsr READ16
    bcs VERR1
    ldy SECT
    lda a:FOUND,y
    bmi VERR1                           ; found already
    lda #$FF
    sta a:FOUND,y
    dec NSECT
    bpl VSECT

;; Returns: the track is good.
;; Out: carry = clear
WEXIT1:
    clc
    rts

;; Counts a failed read: retries while reads are left, then rewrites the track while rewrites are left.
VERR1:
    dec RETRYCNT
    bne VSECT
    dec TRKRETRY
    bne REWRITE
    sec                                 ; the track won't verify
    rts

;; Finds sector 15, to rewrite the track starting just after it.
REWRITE:
    lda a:DCB_SECTRETRY
    asl a
    sta RETRYCNT

;; Reads address fields until sector 15's.
S15LOC:
    ldx #$60
    jsr RDADR16
    bcs NOTS15
    lda SECT
    cmp #15
    beq PASS15
NOTS15:
    dec RETRYCNT
    bne S15LOC
    sec                                 ; sector 15 wasn't found

;; Returns; also 12 cycles of delay when called.
WEXIT2:
    rts

;; Waits while most of sector 15's data field passes, then writes the track again.
PASS15:
    ldx #<(342-128)

;; Waits 32 cycles a pass.
VFYDELAY:
    jsr WEXIT2
    jsr WEXIT2
    bit $00
    dex
    bne VFYDELAY
    jmp WTRETRY
