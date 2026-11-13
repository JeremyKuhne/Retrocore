; SOSLDR, part E: setting up the built-in drives, initializing the kernel, and walking the kernel, interpreter and
; driver files.

;; Links the built-in Disk III driver's DIBs (.D1-.D4) for the given number of drives.
;;
;; DIB1 links to DIB2, DIB2 to DIB3 and DIB3 to DIB4, and the chain is cut after the last drive. A count of 0 counts
;; as 1, and more than 4 as 4.
;; In:    A = the number of drives
;; Out:   A = 0, Y = the number of drives
;; Keeps: X
;; See:   <LINK_INIT>
SET_DRIVES:
    tay
    lda #<DIB2
    sta DIB1
    lda #>DIB2
    sta DIB1+1
    lda #<DIB3
    sta DIB2
    lda #>DIB3
    sta DIB2+1
    lda #<DIB4
    sta DIB3
    lda #>DIB4
    sta DIB3+1
    lda #0
    cpy #2
    bcc STDR010
    beq STDR020
    cpy #4
    bcc STDR030
    bcs STDR040
STDR010:
    sta DIB1
    sta DIB1+1
    rts
STDR020:
    sta DIB2
    sta DIB2+1
    rts
STDR030:
    sta DIB3
    sta DIB3+1
    rts
STDR040:
    sta DIB4
    sta DIB4+1
    rts

;; Initializes the kernel's managers and the devices in the system device table.
;;
;; It switches I/O and the primary stack in and SOS's zero page, calls each manager's initialization in INIT, and
;; switches back to the caller's zero page and the alternate stack. If the block file manager's second
;; initialization fails, the loader stops with I/O ERROR.
;; Uses:  A, X, Y
;; See:   <INT_INIT>, <EVQ_INIT>, <BFM_INIT2>, <DMGR_INIT>, <CFMGR_INIT>, <MMGR_INIT>, <BMGR_INIT>, <BFM_INIT>,
;;        <CLK_INIT>
INIT_KRNL:
    lda E_REG
    ora #$44                        ; I/O and the primary stack
    sta E_REG
    lda #>SZPAGE
    sta Z_REG
    jsr INT_INIT
    jsr EVQ_INIT
    jsr BFM_INIT2
    bcs INITK_ERR
    jsr DMGR_INIT
    jsr CFMGR_INIT
    jsr MMGR_INIT
    jsr BMGR_INIT
    jsr BFM_INIT
    jsr CLK_INIT
    lda E_REG
    and #$BB                        ; no I/O, the alternate stack
    sta E_REG
    lda #>CZPAGE
    sta Z_REG
    rts
INITK_ERR:
    ldx #ERR0X
    ldy #ERR0L
    jmp ERROR

;; Steps to the next piece of the kernel or interpreter file, and sets up a MOVE of it.
;;
;; Each piece has a header of its run address and its length, then its bytes. From one header, this skips the piece
;; to the next header, and points <SRC_P> at that piece's bytes.
;; In:    WORK_P = a piece's 4-byte header
;; Out:   WORK_P = the next piece's header, SRC_P = that piece's bytes (with WORK_P's X byte),
;;        DST_P = its run address (X byte 0), CNT = its length
;; Uses:  A, X, Y
;; See:   <MOVE>
ADVANCE:
    clc
    ldy #2
    lda WORK_P
    adc (WORK_P),y
    tax
    iny
    lda WORK_P+1
    adc (WORK_P),y
    pha
    txa
    adc #4
    sta WORK_P
    pla
    adc #0
    sta WORK_P+1
    clc
    lda WORK_P
    adc #<($0004)
    sta SRC_P
    lda WORK_P+1
    adc #>($0004)
    sta SRC_P+1
    lda CXPAGE+WORK_P+1
    sta CXPAGE+SRC_P+1
    ldy #0
    sty CXPAGE+DST_P+1
    lda (WORK_P),y
    sta DST_P
    iny
    lda (WORK_P),y
    sta DST_P+1
    iny
    lda (WORK_P),y
    sta CNT
    iny
    lda (WORK_P),y
    sta CNT+1
    rts

;; Rearranges the driver file's counts so the file can be walked from its end back to its start.
;;
;; Each field of a driver module (title, code, relocations) has its length in the word before it. This moves each
;; length to the word after its field, which is the next field's count word: the first count word gets $FFFF, to
;; mark the front, and the file's closing $FFFF gets the last field's length. Walking back is then a matter of
;; subtracting the length found (<DADD>). An empty file, a length of $8000 or more, or a field running past $FFFF
;; stops the loader with an error.
;; In:    the driver file at $80:FILE
;; Out:   WORK_P = the last count word, after the last module's relocation field
;; Uses:  A, X, Y, REV_SAVE
;; See:   <DADVANCE>
REVERSE:
    lda #<D_HDR_CNT                 ; skip the header to the first module's title count
    sta WORK_P
    lda #>D_HDR_CNT
    sta WORK_P+1
    lda #$80
    sta CXPAGE+WORK_P+1
    clc
    ldy #0
    lda WORK_P
    adc (WORK_P),y
    tax
    iny
    lda WORK_P+1
    adc (WORK_P),y
    pha
    txa
    adc #2
    sta WORK_P
    pla
    adc #0
    sta WORK_P+1
    lda (WORK_P),y
    dey
    and (WORK_P),y
    cmp #$FF
    bne REV010
    ldx #ERR10X
    ldy #ERR10L
    jsr ERROR
REV010:
    lda #$FF
    sta REV_SAVE
    sta REV_SAVE+1
REV020:
    lda REV_SAVE                    ; swap the carried length with this count word
    pha
    lda REV_SAVE+1
    pha
    ldy #0
    lda (WORK_P),y
    sta REV_SAVE
    iny
    lda (WORK_P),y
    sta REV_SAVE+1
    pla
    sta (WORK_P),y
    dey
    pla
    sta (WORK_P),y
    lda REV_SAVE
    and REV_SAVE+1
    cmp #$FF
    beq REV_EXIT                    ; that was the closing $FFFF
REV030:
    bit REV_SAVE+1
    bmi REV040
    clc
    lda WORK_P
    adc REV_SAVE
    tax
    lda WORK_P+1
    adc REV_SAVE+1
    pha
    bcs REV040
    txa
    adc #2
    sta WORK_P
    pla
    adc #0
    sta WORK_P+1
    bcc REV020
REV040:
    ldx #ERR5X
    ldy #ERR5L
    jsr ERROR
REV_EXIT:
    rts

;; Steps back to the next driver module (the one before the last processed) and sets up its relocation and move.
;; In:    WORK_P = the count word after the module's relocation field, as <REVERSE> or the last call left it
;; Out:   carry = set when no modules are left; otherwise REL_P = the relocation field's count word,
;;        CNT = the code field's length, SRC_P = the code field, WORK_P = the previous module's last count word
;; Uses:  A, X, Y
;; See:   <DADD>, <RELOC>
DADVANCE:
    ldy #0
    lda (WORK_P),y
    iny
    and (WORK_P),y
    cmp #$FF
    bne DADV010
    sec
    rts
DADV010:
    lda WORK_P
    sta REL_P
    lda WORK_P+1
    sta REL_P+1
    lda CXPAGE+WORK_P+1
    sta CXPAGE+REL_P+1
    jsr DADD                        ; to the code's count word
    ldy #0
    lda (WORK_P),y
    sta CNT
    iny
    lda (WORK_P),y
    sta CNT+1
    jsr DADD                        ; to the title's count word, just before the code
    clc
    lda WORK_P
    adc #2
    sta SRC_P
    lda WORK_P+1
    adc #0
    sta SRC_P+1
    lda CXPAGE+WORK_P+1
    sta CXPAGE+SRC_P+1
    jsr DADD                        ; to the previous module's last count word
    clc
    rts

;; Steps back over one field of the reversed driver file, to the count word before it.
;; In:    WORK_P = a count word, holding the length of the field before it
;; Out:   WORK_P = the count word before that field
;; Uses:  A, X, Y
;; See:   <REVERSE>
DADD:
    sec
    ldy #0
    lda WORK_P
    sbc (WORK_P),y
    tax
    iny
    lda WORK_P+1
    sbc (WORK_P),y
    pha
    txa
    sbc #2
    sta WORK_P
    pla
    sbc #0
    sta WORK_P+1
    rts

;; Reads a driver module's DIB flags: finds its active DIBs, chains them together, and notes page alignment.
;;
;; Inactive DIBs are left out of the chain: each active DIB's link becomes the offset (from the code field's start)
;; of the next active one, and the last active DIB's link its own offset, which <LINK> takes as the end. The links
;; are relocated with the code.
;; In:    SRC_P = the module's code field, which starts with its first DIB
;; Out:   overflow = set when every DIB is inactive (the module is skipped),
;;        FIRST_ADIB = the first active DIB's offset, PG_ALIGN = as <NEXT_DIB> sets it
;; Uses:  A, X, Y, DIB_P, PREV_ADIB_P
;; See:   <NEXT_DIB>, <LINK>
FLAGS:
    sec
FLAG010:
    jsr NEXT_DIB                    ; find the first active DIB
    bvc FLAG015
    bcc FLAG010
    rts
FLAG015:
    php
    sec
    lda DIB_P
    sbc SRC_P
    sta FIRST_ADIB
    lda DIB_P+1
    sbc SRC_P+1
    sta FIRST_ADIB+1
    lda DIB_P
    sta PREV_ADIB_P
    lda DIB_P+1
    sta PREV_ADIB_P+1
    lda CXPAGE+DIB_P+1
    sta CXPAGE+PREV_ADIB_P+1
    plp
    bcs FLAG100
FLAG020:
    jsr NEXT_DIB
    php
    ldy #0
    bvc FLAG025
    sec                             ; inactive: for now, the last active DIB links to itself
    lda PREV_ADIB_P
    sbc SRC_P
    sta (PREV_ADIB_P),y
    iny
    lda PREV_ADIB_P+1
    sbc SRC_P+1
    sta (PREV_ADIB_P),y
    jmp FLAG050
FLAG025:
    sec                             ; active: the last active DIB links to this one
    lda DIB_P
    sbc SRC_P
    sta (PREV_ADIB_P),y
    iny
    lda DIB_P+1
    tax
    sbc SRC_P+1
    sta (PREV_ADIB_P),y
    stx PREV_ADIB_P+1
    lda DIB_P
    sta PREV_ADIB_P
FLAG050:
    plp
    bcc FLAG020
FLAG100:
    clv
    rts

;; Steps to a driver module's first or next DIB, and reads its flags.
;;
;; A DIB's link, in the file, is the next DIB's offset from the code field's start, or 0 after the last. When an
;; active DIB asks for page alignment (flag bit 6), PG_ALIGN is set from the module's first DIB: $22 plus its DCB
;; length, the part of the module that must come before a page boundary.
;;
;; Overflow is set for an inactive DIB and cleared for a page-aligned one; for other active DIBs it is left as the
;; arithmetic before the call left it, which is normally clear.
;; In:    carry = set for the first DIB, SRC_P = the code field, DIB_P = the previous DIB (when carry is clear)
;; Out:   DIB_P = the DIB, overflow = set when it is inactive, carry = set when it is the last,
;;        PG_ALIGN = 0 when the first DIB is read, or its alignment
;; Uses:  A, X, Y
;; See:   <FLAGS>, <NEWDST>
NEXT_DIB:
    ldy #0
    bcc NXTD010
    sty PG_ALIGN
    sty PG_ALIGN+1
    lda SRC_P
    sta DIB_P
    lda SRC_P+1
    sta DIB_P+1
    lda CXPAGE+SRC_P+1
    sta CXPAGE+DIB_P+1
    jmp NXTD020
NXTD010:
    lda SRC_P
    adc (DIB_P),y
    tax
    iny
    lda SRC_P+1
    adc (DIB_P),y
    sta DIB_P+1
    stx DIB_P
NXTD020:
    ldy #DIB_FLAGS
    lda (DIB_P),y
    bmi NXTD030                     ; active
    bit NXTD999                     ; an RTS ($60) has bit 6 set: this sets overflow for inactive
    bvs NXTD040
NXTD030:
    and #$40
    beq NXTD040
    clc
    lda #DIB_DCB+2
    tay
    dey
    dey
    adc (SRC_P),y
    sta PG_ALIGN
    iny
    lda #0
    adc (SRC_P),y
    sta PG_ALIGN+1
    clv
NXTD040:
    ldy #0
    lda (DIB_P),y
    iny
    ora (DIB_P),y
    bne NXTD998
    sec
    bcs NXTD999
NXTD998:
    clc
NXTD999:
    rts
    .include "SosLdrF.asm"
