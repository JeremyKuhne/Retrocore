; ---------------------------------------------------------------------------------------------------------------------
; Block file manager: swapping volumes, for when a disk with open files is taken out of its drive and another put in.
;
; A volume swapped out keeps its VCB, marked in VCBSWAP with a swap byte: $80 plus the VCB's offset in the VCB page
; divided by 16. Each open file on it gets the same byte in its FCB's FCBSWAP. When the files are used again, the
; operator is asked to put the volume back (<USRREQ>), and the marks are cleared. An operator who will not
; closes the volume's files instead (<CLOSEU>).
;
; The BFM module ends here, with the operator message <USRREQ> shows.
; ---------------------------------------------------------------------------------------------------------------------

;; Swaps out the volume logged in on a device, for another volume to be used there.
;;
;; A volume without open files is simply forgotten. Otherwise, when a bitmap buffer holds changes for the device, the
;; operator is asked to put the volume back if it is gone, and the bitmap is written; when the operator will not,
;; the volume's files are closed. Then the volume and its open files are marked swapped out.
;; In: A = the device number
;; Out: carry = set when the operator would not put the volume back
;; Uses: A, X, Y
;; Entry: SWAPOUTX = with DEVNUM set and the pointers saved by <SAVECBS> already
;; See: <SWAPIN>, <FCBSCAN>, <USRREQ>, <CLOSEU>
SWAPOUT:
    tax
    jsr SAVECBS
    stx DEVNUM
SWAPOUTX:
    jsr DEVVCB
    bcs SORTS                       ; no volume there
    ldy #VCBSTAT
    lda (VCBPTR),y
    bpl UNLOG                       ; no files open
    lda DEVNUM
    ldx #0
    cmp BMADEV,x
    beq FDIRBM
    ldx #6
    cmp BMADEV,x
    beq FDIRBM
    jmp MARKSWAP
FDIRBM:
    lda BMASTAT,x
    bpl MARKSWAP                    ; the bitmap has no changes
GETVOL:
    jsr VERFYVOL
    bcc VONLINE
    jsr USRREQ
    bcc GETVOL
    jsr CLOSEU
    jsr RESTCBS
    sec
    rts
VONLINE:
    ldx DEVNUM
    jsr UPBMAP
MARKSWAP:
    lda VCBPTR
    lsr a
    lsr a
    lsr a
    lsr a
    sec                             ; swapping out
    ora #$80                        ; the swap byte
    pha
    jsr FCBSCAN
    pla
    ldy #VCBSWAP
    sta (VCBPTR),y
SORTS:
    jsr RESTCBS
    clc
    rts
UNLOG:
    lda #0
    sta VCB,x                       ; the VCB is free
    beq SORTS

;; Swaps a volume back in, so that its open files can be used again.
;;
;; Nothing happens for a VCB that is free or not swapped out. Otherwise the volume now on the device is swapped out,
;; and the operator is asked for this one until it is there; when the operator will not, its files are closed. Then
;; the marks on the volume and its files are cleared, and a bitmap buffer kept for the device is dropped so that its
;; map is read again. <RESTCBS> runs twice on this path, both times putting back what <SAVECBS> saved.
;; In: VCBPTR = the volume's VCB
;; Out: carry = set when the operator would not put the volume back
;; Uses: A, X, Y
;; See: <SWAPOUT>, <FCBSCAN>, <USRREQ>, <CLEARBMS>
SWAPIN:
    jsr SAVECBS
    ldy #VCBNML
    lda (VCBPTR),y
    beq USRTS                       ; a free VCB
    ldy #VCBSWAP
    lda (VCBPTR),y
    beq USRTS                       ; not swapped out
    ldy #VCBDEV
    lda (VCBPTR),y
    sta DEVNUM
    pha
    jsr SWAPOUTX
    pla
    sta DEVNUM
SI1:
    jsr VERFYVOL
    bcc UNMARK
    jsr USRREQ
    bcc SI1
    jsr CLOSEU
    jsr RESTCBS
    sec
    rts
UNMARK:
    ldy #VCBSWAP
    lda (VCBPTR),y
    pha
    lda #0
    sta (VCBPTR),y
    pla
    clc                             ; swapping in
    jsr FCBSCAN
    lda DEVNUM
    jsr CLEARBMS
USRTS:
    jsr RESTCBS
    clc
    rts

;; Where <SAVECBS> keeps VCBPTR, FCBPTR and DEVNUM during a swap.
;;
;; Its initial contents are whatever was in memory when Apple built SOS.KERNEL; SOS sets it at run time.
SAVEPTRS:
    .byte $A0, $A0, $9A, $A0, $C9

;; Saves VCBPTR, FCBPTR and DEVNUM in <SAVEPTRS>.
;; Uses: A
;; Keeps: X, Y
;; See: <RESTCBS>
SAVECBS:
    lda VCBPTR
    sta SAVEPTRS
    lda VCBPTR+1
    sta SAVEPTRS+1
    lda FCBPTR
    sta SAVEPTRS+2
    lda FCBPTR+1
    sta SAVEPTRS+3
    lda DEVNUM
    sta SAVEPTRS+4
    rts

;; Puts back VCBPTR, FCBPTR and DEVNUM from <SAVEPTRS>.
;; Uses: A
;; Keeps: X, Y
;; See: <SAVECBS>
RESTCBS:
    lda SAVEPTRS
    sta VCBPTR
    lda SAVEPTRS+1
    sta VCBPTR+1
    lda SAVEPTRS+2
    sta FCBPTR
    lda SAVEPTRS+3
    sta FCBPTR+1
    lda SAVEPTRS+4
    sta DEVNUM
    rts

;; Marks the open files on a device as swapped out or back in.
;;
;; Swapping out, each open file of the device not already marked gets the swap byte; swapping in, each file with
;; that swap byte has it cleared.
;; In: A = the swap byte, carry = set to swap out, clear to swap in, DEVNUM = the device
;; Uses: A, X, Y, FCBPTR
;; See: <SWAPOUT>, <SWAPIN>, <FCBFETCH>
FCBSCAN:
    tax
    ldy a:FCBADDRH
    sty FCBPTR+1
    ldy #0
    sty FCBPTR
    bcs FCBOUT
FCBIN:
    jsr FCBFETCH
    bcs FCBRTS
    ldy #FCBSWAP
    txa
    cmp (FCBPTR),y
    bne FCBIN1
    lda #0
    sta (FCBPTR),y
FCBIN1:
    jsr NEXTFCB
    bcs FCBRTS
    jmp FCBIN
FCBOUT:
    jsr FCBFETCH
    bcs FCBRTS
    ldy #FCBSWAP
    lda (FCBPTR),y
    bne FCBOUT1                     ; swapped out already
    txa
    sta (FCBPTR),y
FCBOUT1:
    jsr NEXTFCB
    bcs FCBRTS
    jmp FCBOUT
FCBRTS:
    rts

;; Finds the next FCB, from FCBPTR on, of a file open on DEVNUM.
;; In: FCBPTR = the FCB to start at, DEVNUM = the device
;; Out: carry = clear when one was found, set at the end of the FCBs, FCBPTR = the FCB
;; Uses: A, Y
;; Keeps: X
;; See: <NEXTFCB>, <FCBSCAN>
FCBFETCH:
    ldy #FCBDEVN
    lda (FCBPTR),y
    cmp DEVNUM
    bne NEXTFCB
    ldy #FCBREFN
    lda (FCBPTR),y
    beq NEXTFCB
    clc
    rts

;; Finds the next FCB after FCBPTR of a file open on DEVNUM.
;; In: FCBPTR = the FCB to start after, DEVNUM = the device
;; Out: carry = clear when one was found, set at the end of the FCBs, FCBPTR = the FCB
;; Uses: A, Y
;; Keeps: X
;; See: <FCBFETCH>
NEXTFCB:
    lda FCBPTR
    clc
    adc #$20
    sta FCBPTR
    bcc FCBFETCH
    lda FCBPTR+1
    inc FCBPTR+1
    cmp a:FCBADDRH
    beq FCBFETCH                    ; on to the second page
NEXTEND:
    sec
    rts

;; Asks the operator to put a volume in its device, and checks that it is there.
;;
;; The message names the volume and the device, whose name comes from a D_INFO call to the device manager. It is
;; shown up to three times, until the right volume is found.
;; In: VCBPTR = the volume's VCB, DEVNUM = the device
;; Out: carry = clear when the volume is there, set when the operator did not put it there or the VCB is free
;; Uses: A, X, Y
;; See: <OPMSGRPLY>, <VERFYVOL>, <UMB>
USRREQ:
VNML = ZPGTEMP                      ;; the volume name's length, counted down while it is copied
    ldy #VCBNML
    lda (VCBPTR),y
    beq NEXTEND
    ldx #$E
    lda #$0
UR1:
    sta MDEV,x
    sta MVOL,x
    dex
    bpl UR1
    lda #5
    sta $C0                         ; a D_INFO call
    lda DEVNUM
    sta $C1                         ; for the device
    lda #<(MDEV-1)
    sta $C2                         ; the name goes to MDEV, its length byte before it
    lda #>(MDEV-1)
    sta $C3
    lda #$8F
    sta $14C3                       ; the name pointer's X-byte
    lda #0
    sta a:$14C2
    sta $C4
    sta $C5
    sta $C6
    sta URDERR
    jsr RPEATIO0
    lda #$20
    sta MDEV-1                      ; the space the length byte took
    ldy #VCBNML
    lda (VCBPTR),y
    sta VNML
    lda #0
    tax
    ldy #VCBNAM
UR2:
    lda (VCBPTR),y
    sta MVOL,x
    inx
    iny
    dec VNML
    bne UR2
URDU:
    ldx #<UMB
    ldy #>UMB
    jsr OPMSGRPLY
    jsr VERFYVOL
    bcs URDU1
    rts
URDU1:
    inc URDERR
    lda URDERR
    cmp #3
    bcc URDU
    rts

;; Closes every open file of a volume whatever state it is in, and forgets the volume, for an operator who would not
;; put it back.
;;
;; Each FCB of the device marked with the volume's swap byte has its buffer released and is freed. Nothing is written.
;; In: VCBPTR = the volume's VCB
;; Uses: A, Y, DEVNUM, FCBPTR
;; See: <USRREQ>, <SWAPOUT>, <SWAPIN>
CLOSEU:
VSWA = ZPGTEMP                      ;; the volume's swap byte
    ldy #VCBDEV
    lda (VCBPTR),y
    sta DEVNUM
    ldy #VCBSWAP
    lda (VCBPTR),y
    sta VSWA
    lda #0
    ldy #VCBNML
    sta (VCBPTR),y                  ; the VCB is free
    ldy #VCBSWAP
    sta (VCBPTR),y
    ldy a:FCBADDRH
    sty FCBPTR+1
    ldy #0
    sty FCBPTR
VFCBLOP:
    ldy #FCBDEVN
    lda (FCBPTR),y
    cmp DEVNUM
    bne VFCBNXT
    ldy #FCBREFN
    lda (FCBPTR),y
    beq VFCBNXT
    ldy #FCBSWAP
    lda (FCBPTR),y
    cmp VSWA
    bne VFCBNXT                     ; another volume's file
    ldy #FCBBUFN
    lda (FCBPTR),y
    jsr RELBUF
    ldy #FCBSWAP
    lda #0
    sta (FCBPTR),y
    ldy #FCBREFN
    sta (FCBPTR),y
VFCBNXT:
    lda FCBPTR
    clc
    adc #$20
    sta FCBPTR
    bcc VFCBLOP
    lda FCBPTR+1
    inc FCBPTR+1
    cmp a:FCBADDRH
    beq VFCBLOP
    rts

;; Marks an open file's directory entry as needing an update, which FLUSH and CLOSE make.
;; In: FCBPTR = the file's FCB
;; Uses: ZPGTEMP
;; Keeps: A, X, Y, carry
;; See: <FLUSH2>
FCBUSED:
    sty ZPGTEMP
    pha
    ldy #FCBDIRTY
    lda (FCBPTR),y
    ora #FCBMOD
    sta (FCBPTR),y
    pla
    ldy ZPGTEMP
    rts

;; How many times <USRREQ> has shown its message without the volume turning up.
;;
;; Its initial contents are whatever was in memory when Apple built SOS.KERNEL; SOS sets it at run time.
URDERR:
    .res 1, $CC

;; The operator message <USRREQ> shows: "Insert volume: ", the volume's name, "in device: " and the device's name on
;; the next line, and "then press the ALPHA LOCK key twice" on the last, ending in $FF.
;;
;; The name fields, <MVOL> and <MDEV>, are 15 bytes each; their initial contents are whatever was in memory when
;; Apple built SOS.KERNEL, and USRREQ fills them.
;; See: <OPMSGRPLY>
UMB:
    .byte $49, $6E, $73, $65, $72, $74, $20 ; "Insert "
    .byte $76, $6F, $6C, $75, $6D, $65      ; "volume"
    .byte $3A, $20                          ; ": "
MVOL:                               ;; the volume's name in the message
    .byte $A0, $A0, $96, $A0, $A0, $9E, $A0, $A0, $9F, $A0, $9D, $9E, $CE, $A4, $A0
    .byte $0D
    .byte $20, $20, $20, $20, $69, $6E, $20 ; "    in "
    .byte $64, $65, $76, $69, $63, $65      ; "device"
    .byte $3A, $20                          ; ": "
MDEV:                               ;; the device's name in the message
    .byte $A0, $A0, $AC, $A0, $8E, $BF, $A0, $E8, $A0, $A0, $86, $A0, $A0, $C9, $A0
    .byte $0D
    .byte $74, $68, $65, $6E, $20, $70, $72 ; "then pr"
    .byte $65, $73, $73, $20, $74, $68, $65, $20 ; "ess the "
    .byte $41, $4C, $50, $48, $41, $20, $4C ; "ALPHA L"
    .byte $4F, $43, $4B, $20, $6B, $65, $79 ; "OCK key"
    .byte $20, $74, $77, $69, $63, $65      ; " twice"
    .byte $FF                               ; the end of the message
ZZLEN = * - ZZORG                   ;; the BFM module's length, which must be SosOrg.asm's LENBFM
ZZEND:                              ; the end of the BFM module
    .assert ZZLEN == LENBFM, "SOSORG gives the module another length"
