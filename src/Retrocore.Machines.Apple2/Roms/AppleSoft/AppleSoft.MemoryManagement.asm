;; APPLESOFT: STACK AND BLOCK MANAGEMENT
;;
;; The interpreter keeps FOR and GOSUB frames on the 6502 stack. Program editing and array allocation move
;; blocks upward as they grow; string collection also uses the unchecked entry of the same backward copy.
;; These routines follow the tables in AppleSoft.asm.

;; Finds the active FOR frame for <FORPNT>, starting just above the caller's return and statement addresses.
;;
;; Consecutive FOR frames begin with <FORTK> and occupy <FORSIZ> bytes. A zero high byte in <FORPNT> selects
;; the first FOR frame and copies its variable pointer to <FORPNT>. A different frame kind ends the search.
;; A matching comparison leaves zero set; reaching another frame kind leaves it clear. A wrapped search
;; also leaves zero set, so callers rely on there being a non-FOR frame at the bottom of the stack.
;; Out: X = stack offset immediately below the frame, or $00 if the search wraps
;; See: <FOR>, <NEXT>
FNDFOR:
    tsx
    inx
    inx
    inx
    inx
FFLOOP:
    lda $0101,x                     ; frame marker
    cmp #FORTK
    bne FFRTS
    lda FORPNT+1
    bne CMPFOR
    lda $0102,x
    sta FORPNT
    lda $0103,x
    sta FORPNT+1
CMPFOR:
    cmp $0103,x
    bne ADDFRS
    lda FORPNT
    cmp $0102,x
    beq FFRTS
ADDFRS:
    txa
    clc
    adc #FORSIZ
    tax
    bne FFLOOP
FFRTS:
    rts

;; Makes room by copying a block toward higher addresses, checking its new end against string space.
;;
;; The source is <LOWTR> up to but not including <HIGHTR>; <HIGHDS> is the corresponding destination end.
;; Copying backward permits overlap. The checked entry tests the supplied end and sets <STREND> to it; the
;; collector enters at <BLTUC> instead because it manages string space itself.
;; In: A = destination end low byte, Y = destination end high byte, HIGHDS = destination end,
;;   LOWTR = source start, HIGHTR = source end
;; Out: STREND = destination end, LOWTR = unchanged, HIGHTR = source start minus $100,
;;   HIGHDS = destination start minus $100
;; Errors: OUT OF MEMORY if the destination end is not below <FRETOP> after collection
;; Entry: BLTUC = copies without the space check or updating <STREND>
;; See: <REASON>, <GARBA2>
BLTU:
    jsr REASON
    sta STREND
    sty STREND+1
BLTUC:
    sec
    lda HIGHTR
    sbc LOWTR
    sta INDEX
    tay
    lda HIGHTR+1
    sbc LOWTR+1
    tax
    inx
    tya
    beq DECBLT
    lda HIGHTR
    sec
    sbc INDEX
    sta HIGHTR
    bcs BLT1
    dec HIGHTR+1
    sec
BLT1:
    lda HIGHDS
    sbc INDEX
    sta HIGHDS
    bcs MOREN1
    dec HIGHDS+1
    bcc MOREN1
BLTLP:
    lda (HIGHTR),y
    sta (HIGHDS),y
MOREN1:
    dey
    bne BLTLP
    lda (HIGHTR),y
    sta (HIGHDS),y
DECBLT:
    dec HIGHTR+1
    dec HIGHDS+1
    dex
    bne MOREN1
    rts

;; Checks that the hardware stack has room for a requested number of two-byte entries and its reserve.
;;
;; Apple uses a $36-byte reserve here rather than the generic Microsoft build's <NUMLEV>-based calculation.
;; Recursive expression evaluation and permanent FOR and GOSUB frames call this before allocating stack space.
;; In: A = number of two-byte entries
;; Errors: OUT OF MEMORY if the reserve addition overflows or the resulting threshold exceeds the stack pointer
;; See: <FRMEVL>, <FOR>, <GOSUB>
GETSTK:
    asl a
    adc #$36
    bcs OMERR
    sta INDEX
    tsx
    cpx INDEX
    bcc OMERR
    rts

;; Checks that an address is below the bottom of allocated string space, collecting strings if necessary.
;;
;; If the address meets or exceeds <FRETOP>, <GARBA2> compacts strings. The address and the nine bytes of
;; shared floating-point and transfer scratch from <HIGHDS> through <LOWTR>+1 are saved across collection.
;; The save loop pushes Y first, then $9C down to $94. Its last load reads <TEMPF1> at $93 but is not pushed.
;; In: A = address low byte, Y = address high byte
;; Out: A = address low byte, Y = address high byte
;; Errors: OUT OF MEMORY if the address is still at or above <FRETOP>
REASON:
    cpy FRETOP+1
    bcc REARTS
    bne TRYMOR
    cmp FRETOP
    bcc REARTS
TRYMOR:
    pha
    ldx #$09
    tya
REASAV:
    pha
    lda TEMPF1,x
    dex
    bpl REASAV
    jsr GARBA2
    ldx #$F7
REASTO:
    pla
    sta FAC,x
    inx
    bmi REASTO
    pla
    tay
    pla
    cpy FRETOP+1
    bcc REARTS
    bne OMERR
    cmp FRETOP
    bcs OMERR
REARTS:
    rts
