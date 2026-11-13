; MEMMGR, the memory manager: the segment table and the six memory calls, REQUEST_SEG, FIND_SEG, CHANGE_SEG,
; GET_SEG_INFO, GET_SEG_NUM and RELEASE_SEG. The buffer manager calls it too, through <MMGR>.
;
; Callers name memory by bank and page. The switchable banks 0-$0E each show their 32K at pages $20-$9F, and two
; pieces of the system's own memory have pseudo-banks: bank $0F, pages $00-$1F ($0000-$1FFF), and bank $10, pages
; $A0-$FF ($A000-$FFFF). Inside, the memory manager numbers pages in one 16-bit sequence (<CNVRT_IBP>): page p of
; bank n is n*$80 + p-$20, so the banks' pages follow each other without gaps from 0 up to <VRT_LIM> (virtual
; memory), and the system pages are $0780-$079F and $0820-$087F.
;
; A segment is a run of pages owned by someone, named by an ID; IDs below $10 belong to the system. The segment
; table keeps the allocated segments in a list in order of address, highest first, and the free entries in a list of
; their own. This file holds the table, the parameter names, the dispatch, REQUEST_SEG and FIND_SEG; MemMgrB.asm and
; MemMgrC.asm hold the rest.
;
; Names follow Apple's SOS 1.3 listing.

ZZORG:                                  ;; the module's first address, for the length check at the end of MemMgrC.asm

; ---------------------------------------------------------------------------------------------------------------------
; The segment table.
; ---------------------------------------------------------------------------------------------------------------------

;; The head of the free entries' list: $80 plus the first free entry's number, or $80 alone when there is none.
;;
;; Its initial contents are whatever was in memory when Apple built SOS.KERNEL; MMGR_INIT sets it.
;; See: <ST_FLINK>, <GET_FREE>
ST_FREE:
    .res 1, $A0
;; The first allocated segment, the one at the highest address, or 0 when there are none.
;;
;; Its initial contents are whatever was in memory when Apple built SOS.KERNEL; MMGR_INIT sets it.
;; See: <ST_FLINK>, <ST_BLINK>
ST_ENTRY:
    .res 1, $A0
ST_SIZ = 7                              ;; bytes per segment table entry
ST_CNT = 32                             ;; segment table entries; entry 0 is not a segment
;; The segment table: for each segment number 1-31, seven fields, each its own 32-byte array.
;;
;; - <ST_BLINK>: the next segment up in memory, or 0 for the highest.
;; - <ST_FLINK>: the next segment down, or 0 for the lowest. In a free entry, bit 7 is set and the rest is the next
;;   free entry, 0 ending the list.
;; - <ST_BASEL>/<ST_BASEH>: the segment's first page, in the internal numbering.
;; - <ST_LIML>/<ST_LIMH>: its last page.
;; - <ST_ID>: its owner's ID.
;;
;; Its initial contents are whatever was in memory when Apple built SOS.KERNEL; MMGR_INIT links every entry into the
;; free list.
ST_TBL:
    .byte $A9, $A0, $C5, $AF, $A0, $A0, $E0, $A0, $C3, $A0, $A0, $BA, $D5, $A0, $D4, $A0
    .byte $A0, $C3, $A0, $A0, $90, $A0, $A0, $9E, $A0, $A0, $E0, $A0, $9D, $9E, $A0, $9F
    .byte $A0, $A0, $A7, $A0, $A0, $80, $A0, $A0, $F0, $A0, $D5, $EE, $AE, $A0, $A0, $D3
    .byte $A2, $A0, $A0, $A2, $A0, $A0, $A0, $A0, $A0, $B1, $A0, $A0, $D3, $A0, $A0, $A0
    .byte $A0, $C2, $A0, $A0, $A5, $A0, $A0, $99, $A0, $A0, $C8, $A0, $A0, $FD, $C7, $85
    .byte $A0, $CD, $8C, $A0, $CC, $96, $A0, $A0, $99, $C3, $D2, $CE, $C3, $C1, $C7, $CD
    .byte $8A, $A0, $A0, $F9, $A0, $A0, $E9, $A0, $80, $80, $A0, $FF, $A2, $A0, $95, $AA
    .byte $A0, $88, $A0, $A0, $F0, $A0, $CF, $90, $AE, $80, $82, $CF, $89, $9A, $A0, $C5
    .byte $A0, $A0, $C5, $A0, $A0, $D3, $A0, $A0, $D2, $A0, $80, $C8, $A0, $A0, $91, $A0
    .byte $88, $A0, $A0, $87, $A0, $A0, $F5, $A0, $A0, $91, $A0, $A0, $A2, $A0, $A0, $BF
    .byte $C7, $85, $A0, $A0, $A0, $A0, $C9, $F4, $A0, $A0, $A0, $A0, $A0, $C5, $A0, $AA
    .byte $C6, $A0, $85, $A0, $A0, $8A, $A0, $A0, $A0, $A0, $A0, $85, $A0, $A0, $82, $A0
    .byte $A6, $A0, $A0, $81, $A0, $C5, $9A, $A0, $A0, $CC, $AE, $C3, $8E, $AE, $D3, $C8
    .byte $A0, $A2, $A0, $A0, $C2, $A0, $A0, $D3, $A0, $A0, $90, $A0, $A0, $CC, $A0, $D3
    .assert * - ST_TBL == ST_SIZ*ST_CNT
ST_BLINK = ST_TBL                       ;; each segment's link to the next one up in memory
ST_FLINK = ST_BLINK+ST_CNT              ;; each segment's link to the next one down; bit 7 set in a free entry
ST_BASEL = ST_FLINK+ST_CNT              ;; each segment's first page, low byte
ST_BASEH = ST_BASEL+ST_CNT              ;; each segment's first page, high byte
ST_LIML = ST_BASEH+ST_CNT               ;; each segment's last page, low byte
ST_LIMH = ST_LIML+ST_CNT                ;; each segment's last page, high byte
ST_ID = ST_LIMH+ST_CNT                  ;; each segment's owner ID

; ---------------------------------------------------------------------------------------------------------------------
; Memory regions, in the internal page numbering, and the memory manager's work area at $40 in the kernel's zero page.
; ---------------------------------------------------------------------------------------------------------------------

ZPAGE = $40                             ;; the memory manager's work area
VRT_BASE = $0                           ;; the first page of virtual memory, bank 0's page $20
VRT_LIM = ZPAGE+$0                      ;; the last page of virtual memory (two bytes), set from the memory size
PHY1BASE = $0780                        ;; the first page of pseudo-bank $0F, $0000
PHY1LIM = $079F                         ;; the last page of pseudo-bank $0F, $1F00
PHY2BASE = $0820                        ;; the first page of pseudo-bank $10, $A000
PHY2LIM = $087F                         ;; the last page of pseudo-bank $10, $FF00

; The memory calls' parameters, which SOS passes in its zero page from $60. Each call has its own names for them.

M_TPARMX = $60                          ;; the first memory call parameter
M_RQCODE = M_TPARMX                     ;; the request code, 0-5: see <MMGR>
RQ_BASE = M_TPARMX+1                    ;; REQUEST_SEG: the first bank and page
RQ_LIM = M_TPARMX+3                     ;; REQUEST_SEG: the last bank and page
RQ_ID = M_TPARMX+5                      ;; REQUEST_SEG: the segment ID
RQ_NUM = M_TPARMX+6                     ;; REQUEST_SEG: the pointer to where the segment number goes
RQ_REGION = ZPAGE+$2                    ;; REQUEST_SEG: the first page's region, which the last page's must match
SRCHMODE = M_TPARMX+1                   ;; FIND_SEG: the search mode, 0-2 (see <NXTFRSEG>)
F_ID = M_TPARMX+2                       ;; FIND_SEG: the segment ID
F_PGCT = M_TPARMX+3                     ;; FIND_SEG: the pointer to the page count, in and out
FX_PGCT = ZPAGE+$3                      ;; FIND_SEG: the page count asked for (two bytes)
F_BASE = M_TPARMX+5                     ;; FIND_SEG: the pointer to where the first bank and page go
F_LIM = M_TPARMX+7                      ;; FIND_SEG: the pointer to where the last bank and page go
F_NUM = M_TPARMX+9                      ;; FIND_SEG: the pointer to where the segment number goes
F_ERR = ZPAGE+$5                        ;; FIND_SEG: <TRUE> when nothing large enough was found
TRUE = $80                              ;; a true flag
FALSE = $0                              ;; a false flag
CFS_PGCT = ZPAGE+$6                     ;; the free area being looked at: its page count (two bytes)
CFS_BASE = ZPAGE+$8                     ;; the free area being looked at: its first page (two bytes)
CFS_LIM = ZPAGE+$A                      ;; the free area being looked at: its last page (two bytes)
CFS_BLINK = ZPAGE+$C                    ;; the free area being looked at: the segment above it, 0 for none
CFS_BASE0 = ZPAGE+$D                    ;; the first page of the bank holding CFS_LIM (two bytes)
CFS_BASE1 = ZPAGE+$F                    ;; the first page of the bank below that, or 0 (two bytes)
CFS_NEXT = ZPAGE+$11                    ;; the next segment below the free page pointer, 0 for none
CFS_PREV = ZPAGE+$12                    ;; the segment above CFS_NEXT, 0 for none
CFS_PTR = ZPAGE+$13                     ;; the next free page to look down from, negative when none is left (two bytes)
BFS_PGCT = ZPAGE+$15                    ;; the largest free area so far: its page count (two bytes), then as CFS_PGCT
BFS_BASE = ZPAGE+$17                    ;; the largest free area so far: its first page (two bytes)
BFS_LIM = ZPAGE+$19                     ;; the largest free area so far: its last page (two bytes)
BFS_BLINK = ZPAGE+$1B                   ;; the largest free area so far: the segment above it
CHG_NUM = M_TPARMX+1                    ;; CHANGE_SEG: the segment number
CHG_MODE = M_TPARMX+2                   ;; CHANGE_SEG: 0 base up, 1 base down, 2 limit up, 3 limit down
CHG_PGCT = M_TPARMX+3                   ;; CHANGE_SEG: the pointer to the page count, in and out
CHG_PGCTX = ZPAGE+$1C                   ;; CHANGE_SEG: the page count asked for (two bytes)
CHG_NEW = ZPAGE+$1E                     ;; CHANGE_SEG: the segment's new first or last page (two bytes)
GSI_NUM = M_TPARMX+1                    ;; GET_SEG_INFO: the segment number
GSI_BASE = M_TPARMX+2                   ;; GET_SEG_INFO: the pointer to where the first bank and page go
GSI_LIM = M_TPARMX+4                    ;; GET_SEG_INFO: the pointer to where the last bank and page go
GSI_PGCT = M_TPARMX+6                   ;; GET_SEG_INFO: the pointer to where the page count goes
GSI_ID = M_TPARMX+8                     ;; GET_SEG_INFO: the pointer to where the ID goes
GSN_BKPG = M_TPARMX+1                   ;; GET_SEG_NUM: the bank and page
GSN_NUM = M_TPARMX+3                    ;; GET_SEG_NUM: the pointer to where the segment number goes
RLS_NUM = M_TPARMX+1                    ;; RELEASE_SEG: the segment number, 0 for every non-system segment
;; <REGION>'s copy of the page it checks.
;;
;; Its initial contents are whatever was in memory when Apple built SOS.KERNEL; SOS sets it at run time.
RGN_BKPG:
    .byte $A0, $91

; ---------------------------------------------------------------------------------------------------------------------
; The calls.
; ---------------------------------------------------------------------------------------------------------------------

;; The memory manager's entry point: does the memory call whose request code is in <M_RQCODE>.
;;
;; The system call manager passes the six memory calls here, and the buffer manager calls it directly. Each call
;; returns with carry clear, or with carry set and the error in SERR (through SYSERR).
;; In: M_RQCODE = the request code: 0 REQUEST_SEG, 1 FIND_SEG, 2 CHANGE_SEG, 3 GET_SEG_INFO, 4 GET_SEG_NUM,
;;   5 RELEASE_SEG; the call's parameters follow it
;; Out: carry = set on an error
;; Errors: BADSCNUM for a request code above 5, and each call's own
;; Uses: A, X, Y, ZPAGE
;; See: <REQ_SEG>, <FIND_SEG>, <CHG_SEG>, <GET_SEG_INFO>, <GET_SEG_NUM>, <RELEASE_SEG>
MMGR:
    lda M_RQCODE
    beq MMGR010
    cmp #1
    beq MMGR020
    cmp #2
    beq MMGR030
    cmp #3
    beq MMGR040
    cmp #4
    beq MMGR050
    cmp #5
    beq MMGR060
    lda #BADSCNUM
    jsr SYSERR
MMGR010:
    jmp REQ_SEG
MMGR020:
    jmp FIND_SEG
MMGR030:
    jmp CHG_SEG
MMGR040:
    jmp GET_SEG_INFO
MMGR050:
    jmp GET_SEG_NUM
MMGR060:
    jmp RELEASE_SEG

;; REQUEST_SEG: allocates a segment at the banks and pages the caller names, if they are free.
;;
;; Both ends must be valid, in the same region, and in order. The segment list is walked from the top to find the
;; gap the new segment would go in; if it overlaps a segment, the request is denied.
;; In: RQ_BASE, RQ_LIM = the first and last bank and page, RQ_ID = the ID, RQ_NUM = where the segment number goes
;; Out: carry = clear, (RQ_NUM) = the new segment's number
;; Errors: BADBKPG, SEGRQDN, SEGTBLFULL
;; Uses: A, X, Y, RQ_REGION
;; See: <MMGR>, <CNVRT_IBP>, <GET_FREE>
REQ_SEG:
    ldx RQ_BASE
    ldy RQ_BASE+1
    jsr CNVRT_IBP
    bcc RQ005
RQ_ERR:
    rts                                 ; CNVRT_IBP's SYSERR left the error and carry set
RQ005:
    stx RQ_BASE
    sty RQ_BASE+1
    sta RQ_REGION
    ldx RQ_LIM
    ldy RQ_LIM+1
    jsr CNVRT_IBP
    bcs RQ_ERR
    stx RQ_LIM
    sty RQ_LIM+1
    cmp RQ_REGION
    bne RQ_ERR1                         ; the ends are in different regions
    lda RQ_LIM
    cmp RQ_BASE
    lda RQ_LIM+1
    sbc RQ_BASE+1
    bcc RQ_ERR1                         ; the last page is below the first
    ldx #0                              ; X = the segment above, Y = the one below
    ldy ST_ENTRY
    beq RQ030                           ; no segments yet
    lda ST_LIML,y
    cmp RQ_BASE
    lda ST_LIMH,y
    sbc RQ_BASE+1
    bcc RQ030                           ; above every segment
RQ010:
    tya
    tax
    lda ST_FLINK,y
    tay
    bne RQ020
    lda RQ_LIM                          ; below the lowest segment, if it ends under it
    cmp ST_BASEL,x
    lda RQ_LIM+1
    sbc ST_BASEH,x
    bcc RQ030
    bcs RQ_ERR2
RQ020:
    lda RQ_LIM
    cmp ST_BASEL,x
    lda RQ_LIM+1
    sbc ST_BASEH,x
    bcs RQ_ERR2                         ; reaches into the segment above
    lda ST_LIML,y
    cmp RQ_BASE
    lda ST_LIMH,y
    sbc RQ_BASE+1
    bcs RQ010                           ; the segment below reaches it: look further down
RQ030:
    txa
    jsr GET_FREE
    bcs RQ_ERR3
    tax
    lda RQ_BASE
    sta ST_BASEL,x
    lda RQ_BASE+1
    sta ST_BASEH,x
    lda RQ_LIM
    sta ST_LIML,x
    lda RQ_LIM+1
    sta ST_LIMH,x
    lda RQ_ID
    sta ST_ID,x
    ldy #0
    txa
    sta (RQ_NUM),y
    clc
    rts
RQ_ERR1:
    lda #BADBKPG
    jsr SYSERR
RQ_ERR2:
    lda #SEGRQDN
    jsr SYSERR
RQ_ERR3:
    lda #SEGTBLFULL
    jsr SYSERR

;; FIND_SEG: allocates a segment of a number of pages wherever virtual memory has room, as high as it fits.
;;
;; It looks at the free areas from the top of virtual memory down (<NXTFRSEG>), as the search mode allows, and takes
;; the first one large enough, allocating the segment at that area's top. If none is large enough, it returns the
;; largest it saw instead, with segment number 0, and the error SEGRQDN.
;; In: SRCHMODE = 0-2, F_ID = the ID, (F_PGCT) = the page count (two bytes), F_BASE, F_LIM, F_NUM = where the results
;;   go
;; Out: carry = clear, (F_NUM) = the segment number, (F_PGCT) = its page count, (F_BASE) and (F_LIM) = its first
;;   and last bank and page
;; Errors: BADPGCNT for a count of 0, BADSRCHMODE, SEGTBLFULL, SEGRQDN
;; Uses: A, X, Y, ZPAGE
;; See: <MMGR>, <NXTFRSEG>, <NXTFRSEG_I>, <GET_FREE>, <CNVRT_XBP>
FIND_SEG:
    ldy #0
    lda (F_PGCT),y
    sta FX_PGCT
    iny
    lda (F_PGCT),y
    sta FX_PGCT+1
    bne FIND001
    lda FX_PGCT
    bne FIND001
    lda #BADPGCNT
    jsr SYSERR
FIND001:
    lda #FALSE
    sta F_ERR
    lda SRCHMODE
    cmp #3
    bcc FIND005
    lda #BADSRCHMODE
    jsr SYSERR
FIND005:
    jsr NXTFRSEG_I
    lda #0
    sta BFS_PGCT
    sta BFS_PGCT+1
FIND010:
    jsr NXTFRSEG
    bcc FIND015
    lda #TRUE                           ; no more free areas: report the largest
    sta F_ERR
    ldx #0
    jmp FIND070
FIND015:
    lda BFS_PGCT
    cmp CFS_PGCT
    lda BFS_PGCT+1
    sbc CFS_PGCT+1
    bcs FIND030
    ldx #6                              ; a larger area: keep it
FIND020:
    lda CFS_PGCT,x
    sta BFS_PGCT,x
    dex
    bpl FIND020
FIND030:
    lda BFS_PGCT
    cmp FX_PGCT
    lda BFS_PGCT+1
    sbc FX_PGCT+1
    bcc FIND010                         ; not large enough yet
    lda BFS_LIM                         ; take the top of it: base = limit - count + 1
    sbc FX_PGCT
    sta BFS_BASE
    lda BFS_LIM+1
    sbc FX_PGCT+1
    sta BFS_BASE+1
    inc BFS_BASE
    bne FIND050
    inc BFS_BASE+1
FIND050:
    lda FX_PGCT
    sta BFS_PGCT
    lda FX_PGCT+1
    sta BFS_PGCT+1
    lda BFS_BLINK
    jsr GET_FREE
    bcc FIND060
    rts
FIND060:
    tax
    lda F_ID
    sta ST_ID,x
    lda BFS_BASE
    sta ST_BASEL,x
    lda BFS_BASE+1
    sta ST_BASEH,x
    lda BFS_LIM
    sta ST_LIML,x
    lda BFS_LIM+1
    sta ST_LIMH,x
FIND070:
    ldy #0
    txa
    sta (F_NUM),y
    lda BFS_PGCT
    sta (F_PGCT),y
    iny
    lda BFS_PGCT+1
    sta (F_PGCT),y
    ldx BFS_BASE
    ldy BFS_BASE+1
    jsr CNVRT_XBP
    tya
    ldy #1
    sta (F_BASE),y
    dey
    txa
    sta (F_BASE),y
    ldx BFS_LIM
    ldy BFS_LIM+1
    jsr CNVRT_XBP
    tya
    ldy #1
    sta (F_LIM),y
    dey
    txa
    sta (F_LIM),y
    lda F_ERR
    bne FIND_ERR
    clc
    rts
FIND_ERR:
    lda #SEGRQDN
    jsr SYSERR
    .include "MemMgrB.asm"
