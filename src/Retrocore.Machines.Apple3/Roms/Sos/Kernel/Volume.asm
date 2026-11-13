; SOS 1.3 kernel, block file manager: the VOLUME call, which reports the volume in a device.

;; VOLUME: returns the name, size and free space of the volume in the named device, logging the volume in.
;;
;; It always reads the device's root directory (block 2). A SOS volume that is already known is used, swapped back
;; in if it was swapped out of this device; a known volume with no open files that was in another device moves to
;; this one. A new volume is logged in, swapping out the device's active volume, into a free VCB entry, one of this
;; device's, or one with no open files. The free block count is taken again from the bitmap each time.
;;
;; A disk that is not SOS gives NOTSOS, and marks the device's active volume, if it has open files, as switched
;; (<DSWITCH>) so it is checked before it is used again.
;;
;; The caller's buffers get the volume name (a length byte and characters) at C_OUTVOL, and the volume's total
;; and free block counts, two bytes each, at C_OUTBLK.
;; In:    C_DNAMP = the device name
;; Out:
;;   carry   = set for an error
;;   A       = the error: NOTBLKDEV, VNFERR, DUPVOL, NOTSOS, FCBFULL (every VCB entry has open files), XIOERROR,
;;             or one from the device
;;   VCBPTR  = the volume's VCB entry
;; Uses:  X, Y, DEVNUM, REQL, REQH, GBUF
;; See:   <GETDNUM>, <LOGVCB>, <TSFRBLK>
VOLUME:
    lda C_DNAMP
    sta DVNAMP
    lda C_DNAMP+1
    sta DVNAMP+1
    lda SISTER+C_DNAMP+1
    sta SISTER+DVNAMP+1
    jsr GETDNUM
    bcc VOL7
    rts
VOL7:
    bmi VOL2                        ; a block device
    lda #NOTBLKDEV
    jmp VOLERR
VOL2:
    lda SCRTCH+1
    sta DEVNUM
    lda #2                          ; the root directory's first block
    ldx #0
    jsr GETROT0
    lda #VNFERR
    bcc VOL8
    rts
VOL8:
    lda #<VCB
    sta VCBPTR
    lda #>VCB
    sta VCBPTR+1
    jsr TSTSOS
    bcc VLOGGED
    jmp VNOTSOS
VLOGGED:
    jsr CMPVCB                      ; look for a VCB entry with this volume's name
    bcc VFOUND
    jsr VNXTVCB
    bcc VLOGGED
    bcs VNEW
VFOUND:
    ldy #VCBSWAP
    lda (VCBPTR),y
    bpl VFOUND1
    ldy #VCBDEV                     ; swapped out: it must have been swapped out of this device
    lda (VCBPTR),y
    cmp DEVNUM
    beq VSWAPIN
    lda #DUPVOL
    jmp VOLERR
VSWAPIN:
    jsr SWAPIN
    jmp VINFO
VFOUND1:
    ldy #VCBDEV
    lda (VCBPTR),y
    cmp DEVNUM
    beq VINFO                       ; already logged in on this device
    ldy #VCBSTAT
    lda (VCBPTR),y
    bpl VFOUND2
    lda #DUPVOL                     ; in use on another device
    bne VOLERR
VFOUND2:
    ldy #VCBNML
    lda #0
    sta (VCBPTR),y                  ; forget it there, and log it in here
VNEW:
    lda DEVNUM
    jsr SWAPOUT                     ; swap out the device's active volume, if it has one
    bcc VNEW1
    lda #XIOERROR
    rts
VNEW1:
    lda #<VCB
    sta VCBPTR
    lda #>VCB
    sta VCBPTR+1
VFREE:
    ldy #VCBNML
    lda (VCBPTR),y
    beq VLOGIN                      ; a free entry
    ldy #VCBDEV
    lda (VCBPTR),y
    cmp DEVNUM
    bne VFREEX
    ldy #VCBSTAT
    lda (VCBPTR),y
    bpl VLOGIN                      ; this device's entry, with no open files
    lda DEVNUM
    jsr SWAPOUT
    bcc VFREEX
    lda #XIOERROR
    rts
VFREEX:
    jsr VNXTVCB
    bcc VFREE
VNFIL:
    ldy #VCBSTAT                    ; no free entry: take one with no open files
    lda (VCBPTR),y
    bpl VLOGIN
    jsr VNXTVCB
    bcc VNFIL
    lda #FCBFULL
    bne VOLERR
VLOGIN:
    jsr LOGVCB
VINFO:
    lda #0
    ldy #VCBTFRE
    sta (VCBPTR),y                  ; a free count of 0 makes TSFRBLK count the bitmap again
    iny
    sta (VCBPTR),y
    sta REQL
    sta REQH
    jsr TSFRBLK
    ldx VCBPTR
    ldy #0
VINFO1:
    lda VCB+VCBTBLK,x               ; the total and free block counts
    sta (C_OUTBLK),y
    inx
    iny
    cpy #4
    bne VINFO1
    ldy #0
    lda (VCBPTR),y
    tay
VINFO2:
    lda (VCBPTR),y                  ; the name and its length
    sta (C_OUTVOL),y
    dey
    bpl VINFO2
    clc
    bcc VOLRET
VOLERR:
    sec
VOLRET:
    rts
VNOTSOS:
    ldy #VCBDEV                     ; mark the device's volume with open files as switched
    lda (VCBPTR),y
    cmp DEVNUM
    bne VNS2
    ldy #VCBSTAT
    lda (VCBPTR),y
    bpl VNS2
    ora #DSWITCH
    sta (VCBPTR),y
VNS2:
    jsr VNXTVCB
    bcc VNOTSOS
    lda #NOTSOS
    bne VOLERR

;; Steps VCBPTR to the next VCB entry.
;; In:    VCBPTR = a VCB entry
;; Out:   VCBPTR = the next entry, carry = set when there are no more
;; Uses:  A
;; Keeps: X, Y
;; See:   <VCBSIZE>
VNXTVCB:
    lda VCBPTR
    clc
    adc #VCBSIZE
    sta VCBPTR
    rts
    .include "Create.asm"
