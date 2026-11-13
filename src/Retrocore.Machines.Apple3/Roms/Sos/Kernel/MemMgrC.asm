; MEMMGR, continued: GET_SEG_INFO, GET_SEG_NUM and RELEASE_SEG, the bank and page conversions, and the segment
; table's free list.

;; GET_SEG_INFO: returns a segment's first and last bank and page, its page count and its ID.
;; In: GSI_NUM = the segment number, GSI_BASE, GSI_LIM, GSI_PGCT, GSI_ID = where the results go
;; Out: carry = clear, (GSI_BASE), (GSI_LIM) = the first and last bank and page, (GSI_PGCT) = the page count (two
;;   bytes), (GSI_ID) = the ID
;; Errors: BADSEGNUM
;; Uses: A, X, Y
;; See: <MMGR>, <CNVRT_XBP>
GET_SEG_INFO:
    ldx GSI_NUM
    beq GSI_ERR
    cpx #ST_CNT
    bcs GSI_ERR
    lda ST_FLINK,x
    bmi GSI_ERR                         ; a free entry
    ldy ST_BASEH,x
    lda ST_BASEL,x
    tax
    jsr CNVRT_XBP
    tya
    ldy #1
    sta (GSI_BASE),y
    dey
    txa
    sta (GSI_BASE),y
    ldx GSI_NUM
    ldy ST_LIMH,x
    lda ST_LIML,x
    tax
    jsr CNVRT_XBP
    tya
    ldy #1
    sta (GSI_LIM),y
    dey
    txa
    sta (GSI_LIM),y
    ldx GSI_NUM
    lda ST_ID,x
    sta (GSI_ID),y
    sec
    lda ST_LIML,x
    sbc ST_BASEL,x
    tay
    lda ST_LIMH,x
    sbc ST_BASEH,x
    tax
    iny                                 ; count = limit - base + 1
    bne GSI010
    inx
GSI010:
    tya
    ldy #0
    sta (GSI_PGCT),y
    iny
    txa
    sta (GSI_PGCT),y
    clc
    rts
GSI_ERR:
    lda #BADSEGNUM
    jsr SYSERR

;; GET_SEG_NUM: finds the segment that holds a bank and page.
;; In: GSN_BKPG = the bank and page, GSN_NUM = where the segment number goes
;; Out: carry = clear, (GSN_NUM) = the segment number
;; Errors: BADBKPG, SEGNOTFND
;; Uses: A, X, Y
;; See: <MMGR>, <CNVRT_IBP>
GET_SEG_NUM:
    ldx GSN_BKPG
    ldy GSN_BKPG+1
    jsr CNVRT_IBP
    bcs GSN_ERR
    stx GSN_BKPG
    sty GSN_BKPG+1
    lda ST_ENTRY
    beq GSN_ERR1
GSN010:
    tax
    lda ST_LIML,x
    cmp GSN_BKPG
    lda ST_LIMH,x
    sbc GSN_BKPG+1
    bcc GSN_ERR1                        ; above this segment, so in a gap between segments
    lda GSN_BKPG
    cmp ST_BASEL,x
    lda GSN_BKPG+1
    sbc ST_BASEH,x
    bcs GSN020                          ; found
    lda ST_FLINK,x
    beq GSN_ERR1
    jmp GSN010
GSN020:
    ldy #0
    txa
    sta (GSN_NUM),y
    clc
    rts
GSN_ERR:
    rts                                 ; CNVRT_IBP's SYSERR left the error and carry set
GSN_ERR1:
    lda #SEGNOTFND
    jsr SYSERR

;; RELEASE_SEG: frees a segment, or with segment number 0, every segment whose ID is $10 or more.
;;
;; System segments, with IDs below $10, survive a release of all.
;; In: RLS_NUM = the segment number, or 0
;; Out: carry = clear
;; Errors: BADSEGNUM
;; Uses: A, X, Y
;; See: <MMGR>, <REL_SEG>
RELEASE_SEG:
    ldx RLS_NUM
    beq RLS_ALL                         ; 0: every segment not the system's
    cpx #ST_CNT
    bcs RLS_ERR
    lda ST_FLINK,x
    bmi RLS_ERR
    bpl REL_SEG
RLS_ALL:
    ldx ST_ENTRY
    beq RLS0_EXIT
    stx RLS_NUM
RLS0_LOOP:
    lda ST_ID,x
    cmp #$10                            ; IDs below $10 are the system's, which stay
    lda ST_FLINK,x
    pha                                 ; the next one, before the entry is freed
    bcc RLS006
    jsr REL_SEG
RLS006:
    pla
    beq RLS0_EXIT
    sta RLS_NUM
    tax
    bne RLS0_LOOP
RLS0_EXIT:
    clc
    rts

;; Takes a segment out of the segment list and puts its entry at the head of the free list.
;; In: X = the segment number, also in RLS_NUM, A = its ST_FLINK entry
;; Out: carry = clear
;; Uses: A, X, Y
;; See: <RELEASE_SEG>, <GET_FREE>
REL_SEG:
    tay
    lda ST_BLINK,x
    tax
    beq RLS010                          ; no segment above: this one was first
    tya
    sta ST_FLINK,x
    jmp RLS020
RLS010:
    sty ST_ENTRY
    tya
RLS020:
    beq RLS030                          ; no segment below
    txa
    sta ST_BLINK,y
RLS030:
    lda ST_FREE
    ldx RLS_NUM
    sta ST_FLINK,x
    txa
    ora #$80                            ; free entries are marked with bit 7
    sta ST_FREE
    clc
    rts
RLS_ERR:
    lda #BADSEGNUM
    jsr SYSERR

;; Turns a caller's bank and page into the memory manager's internal page number, and finds its region.
;;
;; Banks 0-$0E take pages $20-$9F, bank $0F pages $00-$1F and bank $10 pages $A0-$FF. The internal number is the
;; bank shifted right one bit in the high byte, with the bank's low bit in bit 7 of the low byte and the page's
;; offset in its bank in bits 0-6. Anything else, or a virtual page past <VRT_LIM>, is an error, which SYSERR
;; returns to this routine's caller.
;; In: X = the bank, Y = the page
;; Out: X = the internal page number's low byte, Y = its high byte, A = the region (as <REGION>), carry = clear
;; Errors: BADBKPG
;; See: <CNVRT_XBP>, <REGION>
CNVRT_IBP:
    tya
    cpx #$F
    beq CNVI010                         ; bank $0F: pages $00-$1F
    bcs CNVI020                         ; bank $10: pages $A0-$FF
    cmp #$20
    bcc CNVI_ERR1
    cmp #$A0
    bcs CNVI_ERR1
    sec
    sbc #$20                            ; banks 0-$0E: pages $20-$9F
    jmp CNVI030
CNVI010:
    cmp #$20
    bcs CNVI_ERR1
    clc
    adc #$80                            ; bank $0F's pages follow at $80 in its half
    jmp CNVI030
CNVI020:
    cpx #$10
    bne CNVI_ERR1
    cmp #$A0
    bcc CNVI_ERR1
    sec
    sbc #$80                            ; bank $10's pages start at $20 in its half
CNVI030:
    tay
    txa
    lsr a                               ; the bank's low bit goes into bit 7 of the page byte
    tax
    tya
    bcc CNVI040
    ora #$80
CNVI040:
    pha
    txa
    tay
    pla
    tax
    jsr REGION
    bcs CNVI_ERR1
    rts
CNVI_ERR1:
    lda #BADBKPG
    jsr SYSERR

;; Turns an internal page number back into a bank and page; the number must be valid.
;; In: X = the internal page number's low byte, Y = its high byte
;; Out: X = the bank, Y = the page
;; Uses: A
;; See: <CNVRT_IBP>
CNVRT_XBP:
    txa
    asl a                               ; bit 7 of the low byte is the bank's low bit
    txa
    and #$7F
    tax
    tya
    rol a
    tay
    txa
    cpy #$F
    beq CNVX020                         ; bank $0F: the page as is
    bcs CNVX010
    clc
    adc #$20                            ; banks 0-$0E
    jmp CNVX020
CNVX010:
    clc
    adc #$80                            ; bank $10
CNVX020:
    pha
    tya
    tax
    pla
    tay
    rts

;; Tells which region of memory an internal page number is in, or that it is in none.
;;
;; Region 0 is virtual memory, pages 0 to <VRT_LIM>; region 1 is pseudo-bank $0F (<PHY1BASE>-<PHY1LIM>); region 2
;; is pseudo-bank $10 (<PHY2BASE>-<PHY2LIM>).
;; In: X = the internal page number's low byte, Y = its high byte
;; Out: carry = set when the page is in no region; otherwise A = the region, zero = set for virtual memory
;; Uses: RGN_BKPG
;; Keeps: X, Y
;; See: <CNVRT_IBP>, <CHG_SEG>
REGION:
    stx RGN_BKPG
    sty RGN_BKPG+1
    lda #<PHY2LIM
    cmp RGN_BKPG
    lda #>PHY2LIM
    sbc RGN_BKPG+1
    bcc RGN_ERR                         ; above the second pseudo-bank
    lda RGN_BKPG
    cmp #<PHY2BASE
    lda RGN_BKPG+1
    sbc #>PHY2BASE
    bcc RGN010
    lda #2
    bne RGN040
RGN010:
    lda #<PHY1LIM
    cmp RGN_BKPG
    lda #>PHY1LIM
    sbc RGN_BKPG+1
    bcc RGN_ERR                         ; between the pseudo-banks
    lda RGN_BKPG
    cmp #<PHY1BASE
    lda RGN_BKPG+1
    sbc #>PHY1BASE
    bcc RGN020
    lda #1
    bne RGN040
RGN020:
    lda a:VRT_LIM
    cmp RGN_BKPG
    lda a:VRT_LIM+1
    sbc RGN_BKPG+1
    bcc RGN_ERR                         ; past the end of virtual memory
    lda #0
RGN040:
    clc
    rts
RGN_ERR:
    sec
    rts

;; Takes an entry off the free list and links it into the segment list below a given segment.
;;
;; The new entry's base, limit and ID are for the caller to fill in. A full table is an error, which SYSERR returns
;; to this routine's caller.
;; In: A = the segment the new one goes below, 0 to make it the first
;; Out: A = the new entry's number, carry = clear
;; Errors: SEGTBLFULL
;; Uses: X, Y
;; See: <REQ_SEG>, <FIND_SEG>, <REL_SEG>
GET_FREE:
    tax
    lda ST_FREE
    cmp #$80                            ; $80 alone: no free entries
    beq GTFR_ERR
    and #$7F
    tay
    lda ST_FLINK,y
    sta ST_FREE                         ; take the first free entry off the free list
    cpx #0
    bne GTFR010                         ; after the previous segment, or first
    lda ST_ENTRY
    sta ST_FLINK,y
    lda #0
    sta ST_BLINK,y
    sty ST_ENTRY
    jmp GTFR020
GTFR010:
    lda ST_FLINK,x
    sta ST_FLINK,y
    txa
    sta ST_BLINK,y
    tya
    sta ST_FLINK,x
GTFR020:
    lda ST_FLINK,y
    beq GTFR030
    lda ST_FLINK,y
    tax
    tya
    sta ST_BLINK,x
GTFR030:
    tya
    clc
    rts
GTFR_ERR:
    lda #SEGTBLFULL
    jsr SYSERR
ZZEND:                                  ;; the end of the module
ZZLEN = ZZEND-ZZORG                     ;; the module's length, which must match LENMEMMG in SosOrg.asm
    .assert ZZLEN == LENMEMMG, "SOSORG gives the module another length"
