; MEMMGR, continued: the search for free memory that FIND_SEG uses, and CHANGE_SEG.

;; Starts a search of free virtual memory from the top, for <NXTFRSEG>.
;;
;; It skips the segments above virtual memory (those in the system's pseudo-banks) and, if the top page is taken,
;; the segments that fill the top, so that CFS_PTR is the highest free page and CFS_NEXT the segment below it.
;; Out: CFS_PTR = the highest free page, negative when there is none, CFS_NEXT = the segment below it, 0 for none,
;;   CFS_PREV = the segment above it, 0 for none
;; Uses: A, X
;; See: <NXTFRSEG>, <NXTFRPG>, <FIND_SEG>
NXTFRSEG_I:
    lda a:VRT_LIM
    sta CFS_PTR
    lda a:VRT_LIM+1
    sta CFS_PTR+1
    lda #0
    sta CFS_PREV
    ldx ST_ENTRY
    stx CFS_NEXT
FRSGI010:
    beq FRSGI_EXIT
    lda a:VRT_LIM
    cmp ST_LIML,x
    lda a:VRT_LIM+1
    sbc ST_LIMH,x
    bcs FRSGI020
    stx CFS_PREV
    lda ST_FLINK,x
    tax
    stx CFS_NEXT
    jmp FRSGI010
FRSGI020:
    lda ST_LIML,x
    cmp a:VRT_LIM
    lda ST_LIMH,x
    sbc a:VRT_LIM+1
    bcc FRSGI_EXIT
    jsr NXTFRPG
FRSGI_EXIT:
    rts

;; Returns the next free area of virtual memory, going down, shaped by FIND_SEG's search mode.
;;
;; The area runs from the free page at CFS_PTR down to the page above the next segment, or to page 0. The search mode
;; limits how far down it may reach: mode 0 keeps it inside the 32K bank holding its top page, mode 1 inside that
;; bank and the one below, and mode 2 does not limit it. The part an area leaves out is offered again as the next
;; area; in mode 1 the next area starts at the top of the bank below, so that areas overlap and every pair of
;; neighboring banks is tried. Then CFS_PTR moves down to the next free page.
;; In: SRCHMODE = the search mode, CFS_PTR = the next free page, CFS_NEXT = the segment below it, CFS_PREV = the
;;   segment above that, all as <NXTFRSEG_I> or the last call left them
;; Out: carry = set when no free memory is left, CFS_BASE = the area's first page, CFS_LIM = its last page,
;;   CFS_PGCT = its page count, CFS_BLINK = the segment above it
;; Uses: A, X, Y, CFS_BASE0, CFS_BASE1, CFS_PTR, CFS_NEXT, CFS_PREV
;; See: <FIND_SEG>, <NXTFRPG>
NXTFRSEG:
    lda CFS_PTR+1                       ; negative: nothing left
    bpl FRSG010
    sec
    rts
FRSG010:
    lda CFS_PREV
    sta CFS_BLINK
    lda CFS_PTR
    sta CFS_LIM
    lda CFS_PTR+1
    sta CFS_LIM+1
    lda CFS_NEXT
    bne FRSG020                         ; a segment below: the area starts above it
    lda #0
    sta CFS_BASE
    sta CFS_BASE+1
    beq FRSG030
FRSG020:
    ldx CFS_NEXT
    clc
    lda ST_LIML,x
    adc #1
    sta CFS_BASE
    lda ST_LIMH,x
    adc #0
    sta CFS_BASE+1
FRSG030:
    ldy CFS_LIM+1
    sty CFS_BASE0+1
    lda CFS_LIM
    and #$80                            ; the first page of the top page's bank
    sta CFS_BASE0
    sec
    sbc #$80                            ; and of the bank below
    sta CFS_BASE1
    tya
    sbc #0
    sta CFS_BASE1+1
    bcs FRSG035
    lda #0
    sta CFS_BASE1
    sta CFS_BASE1+1
FRSG035:
    lda CFS_BASE
    cmp CFS_BASE0
    lda CFS_BASE+1
    sbc CFS_BASE0+1
    bcs FRSG050
    lda SRCHMODE
    bne FRSG040                         ; mode 0: no lower than the bank's first page
    lda CFS_BASE0
    sta CFS_BASE
    lda CFS_BASE0+1
    sta CFS_BASE+1
    jmp FRSG050
FRSG040:
    lda CFS_BASE
    cmp CFS_BASE1
    lda CFS_BASE+1
    sbc CFS_BASE1+1
    bcs FRSG050
    lda SRCHMODE
    cmp #1                              ; mode 1: no lower than the first page of the bank below
    bne FRSG050
    lda CFS_BASE1
    sta CFS_BASE
    lda CFS_BASE1+1
    sta CFS_BASE+1
FRSG050:
    sec
    lda CFS_LIM
    sbc CFS_BASE
    sta CFS_PGCT
    lda CFS_LIM+1
    sbc CFS_BASE+1
    sta CFS_PGCT+1
    inc CFS_PGCT                        ; count = limit - base + 1
    bne FRSG052
    inc CFS_PGCT+1
FRSG052:
    lda SRCHMODE
    cmp #1
    bne FRSG060
    lda CFS_BASE
    cmp CFS_BASE0
    lda CFS_BASE+1
    sbc CFS_BASE0+1
    bcs FRSG060
    ldy CFS_BASE0+1
    ldx CFS_BASE0
    bne FRSG055
    dey
FRSG055:
    dex
    stx CFS_PTR
    sty CFS_PTR+1
    jmp FRSG070
FRSG060:
    sec
    lda CFS_BASE
    sbc #1                              ; the next free page is the one below the area
    sta CFS_PTR
    lda CFS_BASE+1
    sbc #0
    sta CFS_PTR+1
    bcc FRSG070
    lda CFS_NEXT
    beq FRSG070
    ldx CFS_NEXT
    lda ST_LIML,x
    cmp CFS_PTR
    lda ST_LIMH,x
    sbc CFS_PTR+1
    bcc FRSG070
    jsr NXTFRPG
FRSG070:
    clc
    rts

;; Moves CFS_PTR down past the segment CFS_NEXT, and past any segments directly below it, to the next free page.
;; Out: CFS_PTR = the free page, negative when there is none, CFS_NEXT = the segment below it, CFS_PREV = the one
;;   above
;; Uses: A, X
;; See: <NXTFRSEG>, <NXTFRSEG_I>
NXTFRPG:
    ldx CFS_NEXT
    sec
    lda ST_BASEL,x
    sbc #1
    sta CFS_PTR
    lda ST_BASEH,x
    sbc #0
    sta CFS_PTR+1
    bcc NFRPG_EXIT
    stx CFS_PREV
    lda ST_FLINK,x
    tax
    stx CFS_NEXT
    beq NFRPG_EXIT
    lda ST_LIML,x
    cmp CFS_PTR
    lda ST_LIMH,x
    sbc CFS_PTR+1
    bcs NXTFRPG
NFRPG_EXIT:
    rts

;; CHANGE_SEG: moves one end of a segment up or down by a number of pages, to grow or shrink it.
;;
;; The modes are 0, base up and 1, base down, which move the first page, and 2, limit up and 3, limit down, which
;; move the last. Shrinking stops with one page left. Growing stops at the edge of virtual memory and at the
;; neighboring segment. The page count the segment could actually move goes back to the caller; if it is less than
;; asked, the segment is left as it was and the error is SEGRQDN.
;; In: CHG_NUM = the segment number, CHG_MODE = 0-3, (CHG_PGCT) = the page count (two bytes)
;; Out: carry = clear, (CHG_PGCT) = the pages moved
;; Errors: BADSEGNUM, BADCHGMODE, SEGRQDN with (CHG_PGCT) = the pages it could move
;; Uses: A, X, Y, CHG_PGCTX, CHG_NEW
;; See: <MMGR>, <REGION>
CHG_SEG:
    ldy #0
    lda (CHG_PGCT),y
    sta CHG_PGCTX
    iny
    lda (CHG_PGCT),y
    sta CHG_PGCTX+1
    ldx CHG_NUM
    beq CHGS_ERR
    cpx #ST_CNT
    bcs CHGS_ERR
    lda ST_FLINK,x
    bpl CHGS005                         ; bit 7 clear: an allocated segment
CHGS_ERR:
    lda #BADSEGNUM
    jsr SYSERR
CHGS005:
    ldy CHG_MODE
    cpy #1
    bcc CHGS010
    beq CHGS020
    cpy #3
    bcc CHGS030
    beq CHGS040
    lda #BADCHGMODE
    jsr SYSERR
CHGS010:
    clc
    lda ST_BASEL,x
    adc CHG_PGCTX
    sta CHG_NEW
    lda ST_BASEH,x
    adc CHG_PGCTX+1
    sta CHG_NEW+1
    bcs CHGS014                         ; past the top: stop at the limit
    lda ST_LIML,x
    cmp CHG_NEW
    lda ST_LIMH,x
    sbc CHG_NEW+1
    bcs CHGS016
CHGS014:
    lda ST_LIML,x
    sta CHG_NEW
    lda ST_LIMH,x
    sta CHG_NEW+1
CHGS016:
    jmp CHGS_EXIT
CHGS020:
    sec
    lda ST_BASEL,x
    sbc CHG_PGCTX
    sta CHG_NEW
    lda ST_BASEH,x
    sbc CHG_PGCTX+1
    sta CHG_NEW+1
    bcs CHGS050
    bcc CHGS052                         ; below page 0: stop at virtual memory's bottom
CHGS030:
    clc
    lda ST_LIML,x
    adc CHG_PGCTX
    sta CHG_NEW
    lda ST_LIMH,x
    adc CHG_PGCTX+1
    sta CHG_NEW+1
    bcc CHGS050
    bcs CHGS052                         ; past the top: stop at virtual memory's top
CHGS040:
    sec
    lda ST_LIML,x
    sbc CHG_PGCTX
    sta CHG_NEW
    lda ST_LIMH,x
    sbc CHG_PGCTX+1
    sta CHG_NEW+1
    bcc CHGS044                         ; below page 0: stop at the base
    lda CHG_NEW
    cmp ST_BASEL,x
    lda CHG_NEW+1
    sbc ST_BASEH,x
    bcs CHGS046
CHGS044:
    lda ST_BASEL,x
    sta CHG_NEW
    lda ST_BASEH,x
    sta CHG_NEW+1
CHGS046:
    jmp CHGS_EXIT
CHGS050:
    ldx CHG_NEW
    ldy CHG_NEW+1
    jsr REGION                          ; the new end must be in virtual memory
    bcs CHGS052
    bne CHGS052
    beq CHGS100
CHGS052:
    lda CHG_MODE
    cmp #1
    bne CHGS054
    ldx #<VRT_BASE
    ldy #>VRT_BASE
    jmp CHGS056
CHGS054:
    ldx a:VRT_LIM
    ldy a:VRT_LIM+1
CHGS056:
    stx CHG_NEW
    sty CHG_NEW+1
CHGS100:
    ldx CHG_NUM
    lda CHG_MODE
    cmp #1
    bne CHGS200
    lda ST_FLINK,x                      ; base down: no lower than the segment below
    beq CHGS_EXIT
    tay
    lda ST_LIML,y
    tax
    lda ST_LIMH,y
    tay
    inx
    bne CHGS110
    iny
CHGS110:
    cpy CHG_NEW+1
    bcc CHGS_EXIT
    beq CHGS120
    bcs CHGS300
CHGS120:
    cpx CHG_NEW
    bcc CHGS_EXIT
    bcs CHGS300
CHGS200:
    lda ST_BLINK,x                      ; limit up: no higher than the segment above
    beq CHGS_EXIT
    tay
    lda ST_BASEL,y
    tax
    lda ST_BASEH,y
    tay
    txa
    bne CHGS210
    dey
CHGS210:
    dex
    cpy CHG_NEW+1
    bcc CHGS300
    beq CHGS220
    bcs CHGS_EXIT
CHGS220:
    cpx CHG_NEW
    bcs CHGS_EXIT
CHGS300:
    stx CHG_NEW
    sty CHG_NEW+1
CHGS_EXIT:
    ldx CHG_NUM
    ldy #0
    lda CHG_MODE
    cmp #1
    bcc CHGS500
    beq CHGS510
    cmp #3
    bcc CHGS520
    beq CHGS530
CHGS500:
    sec
    lda CHG_NEW
    sbc ST_BASEL,x
    sta (CHG_PGCT),y
    lda CHG_NEW+1
    sbc ST_BASEH,x
    jmp CHGS600
CHGS510:
    sec
    lda ST_BASEL,x
    sbc CHG_NEW
    sta (CHG_PGCT),y
    lda ST_BASEH,x
    sbc CHG_NEW+1
    jmp CHGS600
CHGS520:
    sec
    lda CHG_NEW
    sbc ST_LIML,x
    sta (CHG_PGCT),y
    lda CHG_NEW+1
    sbc ST_LIMH,x
    jmp CHGS600
CHGS530:
    sec
    lda ST_LIML,x
    sbc CHG_NEW
    sta (CHG_PGCT),y
    lda ST_LIMH,x
    sbc CHG_NEW+1
CHGS600:
    iny
    sta (CHG_PGCT),y
    tax
    dey
    lda (CHG_PGCT),y
    cmp CHG_PGCTX
    txa
    sbc CHG_PGCTX+1                     ; fewer pages than asked?
    bcs CHGS610
    lda #SEGRQDN
    jsr SYSERR
CHGS610:
    ldx CHG_NUM
    lda CHG_MODE
    cmp #2
    lda CHG_NEW
    ldy CHG_NEW+1
    bcs CHGS620
    sta ST_BASEL,x
    tya
    sta ST_BASEH,x
    clc
    rts
CHGS620:
    sta ST_LIML,x
    tya
    sta ST_LIMH,x
    clc
    rts
    .include "MemMgrC.asm"
