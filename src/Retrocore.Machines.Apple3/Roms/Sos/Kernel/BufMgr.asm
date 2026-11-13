; BUFMGR, the buffer manager: the kernel's buffers in banked memory, such as the block file manager's buffers for
; open files. A buffer is a whole number of pages, up to 64 (16K), known by its number (1-16) in the buffer table.
; Floating buffers get their memory from the memory manager as segments, and are moved up to the top of free
; memory whenever one is released, so that free memory stays in one piece below them. Fixed buffers are memory the
; caller of OPEN supplies; they never move. Callers get a buffer's address as an extended pointer (<GETBUFADR>).
;
; A check byte guards each buffer against being overwritten by something else between SOS calls: at the end of a
; call, <CHKBUF> records each used buffer's first byte, and the first <GETBUFADR> for that buffer in a later call
; checks it, stopping the system if it changed.
;
; Names follow Apple's SOS 1.3 listing.

ZZORG:                                  ;; the module's first address, for the length check at the end
Z_REG = $FFD0                           ;; the zero-page register

; ---------------------------------------------------------------------------------------------------------------------
; The memory manager's call parameters, in the kernel's zero page at $60, which the buffer manager fills to call
; <MMGR>, and the buffer manager's own variables.
; ---------------------------------------------------------------------------------------------------------------------

M_TPARMX = $60                          ;; the first memory call parameter
REQCODE = M_TPARMX+$0                   ;; the memory call's request code
FINDSEG = $1                            ;; request code: FIND_SEG
SRCHMODE = M_TPARMX+$1                  ;; FIND_SEG's search mode
F_ID = M_TPARMX+$2                      ;; FIND_SEG's segment ID
F_PGCT = M_TPARMX+$3                    ;; FIND_SEG's pointer to the page count
;; FIND_SEG's page count, in and out, which <F_PGCT> points to.
;;
;; Its initial contents are whatever was in memory when Apple built SOS.KERNEL; SOS sets it at run time.
F_PGCTX:
    .byte $AA, $A0
F_BASE = M_TPARMX+$5                    ;; FIND_SEG's pointer to the base bank and page it returns
;; The base bank and page FIND_SEG returns, which <F_BASE> points to; then, after <CNVRT_ADR>, the extension byte
;; and high address byte.
;;
;; Its initial contents are whatever was in memory when Apple built SOS.KERNEL; SOS sets it at run time.
F_BASEX:
    .byte $A0, $A5
F_LIM = M_TPARMX+$7                     ;; FIND_SEG's pointer to the limit bank and page it returns
;; The limit bank and page FIND_SEG returns, which <F_LIM> points to; the buffer manager does not use it.
;;
;; Its initial contents are whatever was in memory when Apple built SOS.KERNEL; SOS sets it at run time.
F_LIMX:
    .byte $D0, $A0
F_NUM = M_TPARMX+$9                     ;; FIND_SEG's pointer to the segment number it returns
;; The segment number FIND_SEG returns, which <F_NUM> points to.
;;
;; Its initial contents are whatever was in memory when Apple built SOS.KERNEL; SOS sets it at run time.
F_NUMX:
    .res 1, $8E
RELSEG = $5                             ;; request code: RELEASE_SEG
RLS_NUM = M_TPARMX+$1                   ;; RELEASE_SEG's segment number
;; <REQBUF>'s page count; its initial contents are whatever was in memory when Apple built SOS.KERNEL.
RQB_PGCT:
    .res 1, $99
;; <REQBUF>'s new buffer number; its initial contents are whatever was in memory when Apple built SOS.KERNEL.
RQB_BNUM:
    .res 1, $BF
;; <REQFXBUF>'s page count; its initial contents are whatever was in memory when Apple built SOS.KERNEL.
RQFB_PGCT:
    .res 1, $D2
;; <REQFXBUF>'s new buffer number; its initial contents are whatever was in memory when Apple built SOS.KERNEL.
RQFB_BNUM:
    .res 1, $C7
MAXPGCT = 64                            ;; the largest buffer, in pages (16K)
F_TPARMX = $A0                          ;; the first file call parameter, in the kernel's zero page
OPEN_LIST = F_TPARMX+$5                 ;; OPEN's pointer to its option list, which holds the fixed buffer's pointer
;; The buffer <BUFCOMPACT> is moving; its initial contents are whatever was in memory when Apple built SOS.KERNEL.
BUFC_BNUM:
    .res 1, $A0
SOURCE = M_TPARMX+$10                   ;; a pointer to a buffer, for moving it and for reading its check byte
DEST = M_TPARMX+$12                     ;; a pointer to where a buffer moves to

; ---------------------------------------------------------------------------------------------------------------------
; The buffer table.
; ---------------------------------------------------------------------------------------------------------------------

BUF_SIZ = 5                             ;; bytes per buffer table entry
BUF_CNT = 17                            ;; buffer table entries; entry 0 is not a buffer
;; The buffer table: for each buffer number, five fields, each its own 17-byte array.
;;
;; - <PGCT_T>: bit 7 set when the entry is free, bit 6 set for a fixed buffer, bits 0-5 the page count less 1.
;; - <XBYTE_T>: the buffer's extension byte. Entry 0's is $FF, so that <BUFCOMPACT> sees it above every buffer.
;; - <ADRH_T>: the buffer's address, high byte.
;; - <SEG_T>: for a floating buffer, its segment number, the low address byte being 0; for a fixed buffer, the low
;;   address byte (<ADRL_T>).
;; - <CHK_T>: the check byte, the buffer's first byte when the last SOS call ended, or 0 for none.
;;
;; Its initial contents are whatever was in memory when Apple built SOS.KERNEL; BMGR_INIT marks every entry free.
BUF_TBL:
    .byte $FF, $A2, $A0, $A5, $AA, $A0, $88, $A0, $A0, $F0, $A0, $A0, $90, $A0, $80, $82
    .byte $A0, $89, $9A, $C5, $C5, $A0, $A0, $C5, $A0, $C3, $D3, $A0, $D3, $D2, $D2, $A0
    .byte $C8, $A0, $BA, $91, $A0, $88, $A0, $A0, $87, $A0, $A0, $F5, $A0, $A0, $91, $A0
    .byte $A0, $A2, $A0, $A0, $BF, $A0, $85, $A0, $A0, $A0, $A0, $A0, $C6, $A0, $A0, $A0
    .byte $A0, $D5, $C5, $AE, $AA, $C6, $A0, $85, $A0, $A0, $8A, $A0, $A0, $A0, $A0, $A0
    .byte $85, $A0, $A0, $82, $A0
    .assert * - BUF_TBL == BUF_SIZ*BUF_CNT
PGCT_T = BUF_TBL                        ;; each buffer's flags and page count less 1 (see <BUF_TBL>)
XBYTE_T = PGCT_T+BUF_CNT                ;; each buffer's extension byte ($7F stands for $8F)
ADRH_T = XBYTE_T+BUF_CNT                ;; each buffer's address, high byte
SEG_T = ADRH_T+BUF_CNT                  ;; each floating buffer's segment number
ADRL_T = SEG_T                          ;; each fixed buffer's address, low byte
CHK_T = ADRL_T+BUF_CNT                  ;; each buffer's check byte, 0 for none
ISFIXED = $40                           ;; <PGCT_T> flag: a fixed buffer
ISFREE = $80                            ;; <PGCT_T> flag: a free entry
BUFREF_CNT = 17                         ;; the size of <BUFREF>: the count and up to 16 buffer numbers
;; The buffers referenced during the current SOS call: a count, then that many buffer numbers.
;;
;; <GETBUFADR> adds a buffer the first time it is asked for it in a call, and <CHKBUF> empties the list at the end.
;; Its initial contents are whatever was in memory when Apple built SOS.KERNEL; BMGR_INIT empties it.
BUFREF:
    .byte $A0, $A0, $D2, $A2, $A0, $C3, $A2, $A0, $CC, $D3, $A0, $A0, $90, $A0, $A0, $A0
    .byte $A0
    .assert * - BUFREF == BUFREF_CNT
;; Where <GETBUFADR> put the pointer, kept while it searches <BUFREF>.
;;
;; Its initial contents are whatever was in memory when Apple built SOS.KERNEL; SOS sets it at run time.
ZPAGEX:
    .res 1, $A0

; ---------------------------------------------------------------------------------------------------------------------
; The buffer manager's calls.
; ---------------------------------------------------------------------------------------------------------------------

;; Makes a floating buffer of a number of pages, from a memory segment the memory manager finds.
;;
;; The segment comes from the top of free memory (<FSEG>). A buffer starting in bank 0's first page, which
;; <CNVRT_ADR> gives extension byte $8F, is recorded with $7F, so that <BUFCOMPACT> sees it as the lowest.
;; In: A = the page count, 1-64
;; Out: A = the buffer number, carry = clear
;; Errors: BUFTBLFULL or OUTOFMEM through SYSERR; a bad page count stops the system (BADBUFSIZ)
;; Uses: X, Y, RQB_PGCT, RQB_BNUM
;; See: <REQFXBUF>, <RELBUF>, <GETBUFADR>
REQBUF:
    tay
    beq RQB_ERR2
    cpy #MAXPGCT+1
    bcs RQB_ERR2
    sty RQB_PGCT
    jsr GETFREE
    bcs RQB_ERR
    stx RQB_BNUM
    lda RQB_PGCT
    jsr FSEG
    bcs RQB_ERR1
    ldx RQB_BNUM
    dec RQB_PGCT                        ; the table holds the count less 1
    lda RQB_PGCT
    sta PGCT_T,x
    ldx F_BASEX
    ldy F_BASEX+1
    jsr CNVRT_ADR
    cpx #$8F
    bne RQB010
    ldx #$7F                            ; $8F sorts lowest as $7F
RQB010:
    txa
    ldx RQB_BNUM
    sta XBYTE_T,x
    tya
    sta ADRH_T,x
    lda F_NUMX
    sta SEG_T,x
    lda #0
    sta CHK_T,x                         ; no check byte yet
    txa
    clc
    rts
RQB_ERR:
    lda #BUFTBLFULL
    jsr SYSERR
RQB_ERR1:
    lda #OUTOFMEM
    jsr SYSERR
RQB_ERR2:
    lda #BADBUFSIZ
    jsr SYSDEATH

;; Makes a fixed buffer of the memory the caller of OPEN supplied in its option list.
;;
;; The option list's bytes 2-3 must hold the address of an extended pointer in the caller's zero page (a byte
;; address, high byte 0). The pointer's extension byte must be a bank pair, $80-$8E, and its address not in page 0;
;; an address from $8100 up is moved down $8000 into the next bank pair. The memory is not the memory manager's, so
;; the buffer never moves and releasing it frees no memory.
;; In: A = the page count, 1-64, OPEN_LIST = OPEN's option list
;; Out: A = the buffer number, carry = clear
;; Errors: BUFTBLFULL or BADSYSBUF through SYSERR; a bad page count stops the system (BADBUFSIZ)
;; Uses: X, Y, RQFB_PGCT, RQFB_BNUM
;; See: <REQBUF>, <RELBUF>, <GETBUFADR>
REQFXBUF:
    tay
    beq RQFB_ERR2
    cpy #MAXPGCT+1
    bcs RQFB_ERR2
    sty RQFB_PGCT
    jsr GETFREE
    bcs RQFB_ERR
    stx RQFB_BNUM
    ldy #3
    lda (OPEN_LIST),y                   ; the pointer's address must be in zero page
    bne RQFB_ERR1
    dey
    lda (OPEN_LIST),y
    tay
    lda CXPAGE+1,y                      ; the pointer's extension byte
    bpl RQFB_ERR1
    cmp #$8F
    bcs RQFB_ERR1
    ldx RQFB_BNUM
    sta XBYTE_T,x
    lda CZPAGE+1,y
    beq RQFB_ERR1
    cmp #$81
    bcc RQFB010
    inc XBYTE_T,x                       ; the same memory, through the next bank pair
    and #$7F
RQFB010:
    sta ADRH_T,x
    lda CZPAGE,y
    sta ADRL_T,x
    dec RQFB_PGCT
    lda RQFB_PGCT
    ora #ISFIXED
    sta PGCT_T,x
    lda #0
    sta CHK_T,x
    txa
    clc
    rts
RQFB_ERR:
    lda #BUFTBLFULL
    jsr SYSERR
RQFB_ERR1:
    lda #BADSYSBUF
    jsr SYSERR
RQFB_ERR2:
    lda #BADBUFSIZ
    jsr SYSDEATH

;; Puts a buffer's address in a zero-page pointer, and checks the buffer has not been overwritten since the last call.
;;
;; The first time a buffer is asked for during a SOS call, it is added to <BUFREF>, and if it has a check byte, its
;; first byte must still match it. A bad buffer number, a free entry, a full BUFREF or a changed first byte stops the
;; system (BADBUFNUM).
;; In: A = the buffer number, X = the zero-page location for the pointer
;; Out: A = the buffer's page count, Y = the buffer number, carry = clear; the pointer at the zero-page location
;;   given in X, with its extension byte at SXPAGE+1 past it, holds the buffer's address
;; Uses: X, ZPAGEX, BUFREF
;; See: <CHKBUF>, <REQBUF>, <GETBUFADR1>
GETBUFADR:
    tay
    beq GTBF_ERR
    cpy #BUF_CNT
    bcs GTBF_ERR
    lda PGCT_T,y
    bmi GTBF_ERR
    jsr GETBUFADR1
    stx ZPAGEX
    tya
    ldx BUFREF
    beq GTBF020
GTBF010:
    cmp BUFREF,x                        ; already referenced in this call?
    beq GTBF030
    dex
    bne GTBF010
GTBF020:
    inc BUFREF
    ldx BUFREF
    cpx #BUFREF_CNT
    bcs GTBF_ERR
    sta BUFREF,x
    lda CHK_T,y
    beq GTBF030
    ldx ZPAGEX
    lda ($0,x)                          ; the buffer's first byte
    cmp CHK_T,y
    bne GTBF_ERR
GTBF030:
    lda PGCT_T,y
    and #$3F
    clc
    adc #1
    clc
    rts
GTBF_ERR:
    lda #BADBUFNUM
    jsr SYSDEATH

;; Builds a buffer's extended address in a zero-page pointer, from its buffer table entry.
;;
;; A floating buffer's low address byte is 0; a fixed one's is in <ADRL_T>. Setting bit 7 of the extension byte
;; turns a recorded $7F back into $8F.
;; In: A = the buffer's PGCT_T entry, X = the zero-page location, Y = the buffer number
;; Out: X,X+1 and SXPAGE+1,X = the buffer's extended address
;; Keeps: X, Y
;; See: <GETBUFADR>, <CHKBUF>
GETBUFADR1:
    and #$40
    bne GTB1010
    lda #0                              ; floating: page-aligned
    beq GTB1020
GTB1010:
    lda ADRL_T,y
GTB1020:
    sta 0,x
    lda ADRH_T,y
    sta 1,x
    lda XBYTE_T,y
    ora #$80
    sta SXPAGE+1,x
    rts

;; Records the first byte of each buffer used during this SOS call as its check byte, and empties <BUFREF>.
;;
;; It switches to the kernel's zero page ($18), where it builds each buffer's pointer.
;; Out: BUFREF = empty, Z_REG = $18 if any buffer was used
;; Uses: A, X, Y, SOURCE
;; See: <GETBUFADR>, <CHK_T>
CHKBUF:
    ldy BUFREF
    beq CHKB_EXIT
    lda #$18
    sta Z_REG
CHKB010:
    ldx #<SOURCE
    lda BUFREF,y
    tay
    lda PGCT_T,y
    jsr GETBUFADR1
    lda ($0,x)
    sta CHK_T,y
    dec BUFREF
    ldy BUFREF
    bne CHKB010
CHKB_EXIT:
    rts

;; Frees a buffer; for a floating buffer, releases its segment and packs the other floating buffers upward.
;;
;; A bad buffer number, a free entry or an error from the memory manager stops the system (BADBUFNUM).
;; In: A = the buffer number
;; Out: carry = clear
;; Uses: A, X, Y
;; See: <BUFCOMPACT>, <REQBUF>, <REQFXBUF>
RELBUF:
    tay
    beq RLBF_ERR
    cpy #BUF_CNT
    bcs RLBF_ERR
    lda PGCT_T,y
    bmi RLBF_ERR
    ora #ISFREE
    sta PGCT_T,y
    and #ISFIXED
    bne RLBF_EXIT                       ; a fixed buffer has no segment
    lda #RELSEG
    sta REQCODE
    lda SEG_T,y
    sta RLS_NUM
    jsr MMGR
    bcs RLBF_ERR
    jsr BUFCOMPACT
RLBF_EXIT:
    clc
    rts
RLBF_ERR:
    lda #BADBUFNUM
    jsr SYSDEATH

;; Moves floating buffers up into the highest free memory, lowest buffer first, until none can move higher.
;;
;; Each pass takes the floating buffer at the lowest address and asks the memory manager for a segment of its size
;; at the top of free memory. If that segment is above the buffer, the buffer's pages are copied there, its entry
;; updated and its old segment released, and the next pass begins; if not, the new segment is released and the
;; compaction ends. An error the memory manager reports while looking is cleared from SERR. A buffer moved to bank
;; 0's first page keeps extension byte $8F here, where <REQBUF> would record $7F.
;; Out: carry = clear, SERR = 0
;; Uses: A, X, Y, SOURCE, DEST, BUFC_BNUM, the FIND_SEG results
;; See: <RELBUF>, <FSEG>
BUFCOMPACT:
BUFC010:
    ldy #0                              ; entry 0's $FF extension byte is above everything
    ldx #BUF_CNT-1
BUFC020:
    lda PGCT_T,x
    and #$C0
    bne BUFC030                         ; free or fixed
    lda ADRH_T,x
    cmp ADRH_T,y
    lda XBYTE_T,x
    sbc XBYTE_T,y
    bcs BUFC030
    txa                                 ; lower: the new candidate
    tay
BUFC030:
    dex
    bne BUFC020
    tya
    bne BUFC040
    jmp BUFC_EXIT
BUFC040:
    sty BUFC_BNUM
    lda PGCT_T,y
    and #$3F
    clc
    adc #1
    jsr FSEG
    bcs BUFC_EXIT
    ldx F_BASEX
    ldy F_BASEX+1
    jsr CNVRT_ADR
    stx F_BASEX
    sty F_BASEX+1
    ldy BUFC_BNUM
    lda ADRH_T,y
    sta SOURCE+1
    cmp F_BASEX+1
    lda XBYTE_T,y
    sta SXPAGE+SOURCE+1
    sbc F_BASEX
    bcs BUFC_EXIT1                      ; the new segment is not higher: done
    ldx F_BASEX
    stx SXPAGE+DEST+1
    ldy F_BASEX+1
    sty DEST+1
    lda #0
    sta SOURCE
    sta DEST
    tay
    ldx F_PGCTX                         ; copy that many pages
BUFC200:
    lda (SOURCE),y
    sta (DEST),y
    dey
    bne BUFC200
    inc SOURCE+1
    inc DEST+1
    dex
    bne BUFC200
    ldy BUFC_BNUM
    lda F_BASEX
    sta XBYTE_T,y
    lda F_BASEX+1
    sta ADRH_T,y
    ldx SEG_T,y
    lda F_NUMX
    sta SEG_T,y
    stx RLS_NUM                         ; release the old segment
    lda #RELSEG
    sta REQCODE
    jsr MMGR
    bcs BUFC_ERR
    jmp BUFC010
BUFC_EXIT1:
    ldx F_NUMX                          ; release the segment just found
    stx RLS_NUM
    lda #RELSEG
    sta REQCODE
    jsr MMGR
    bcs BUFC_ERR
BUFC_EXIT:
    lda #0
    sta SERR
    clc
    rts
BUFC_ERR:
    lda #BADBUFNUM
    jsr SYSDEATH

;; Asks the memory manager for a segment of a number of pages, as high in memory as it will fit (FIND_SEG).
;;
;; It uses search mode 2, which lets the segment cross bank boundaries, and segment ID 4. The results are left in
;; <F_PGCTX>, <F_BASEX>, <F_LIMX> and <F_NUMX>.
;; In: A = the page count
;; Out: carry = set when no free memory is large enough, A = F_PGCTX: the page count, or on an error the largest
;;   free segment's
;; Uses: X, Y, the memory call parameters
;; See: <MMGR>, <REQBUF>, <BUFCOMPACT>
FSEG:
    sta F_PGCTX
    lda #FINDSEG
    sta REQCODE
    lda #2
    sta SRCHMODE
    lda #4
    sta F_ID
    lda #<F_PGCTX
    sta F_PGCT
    lda #>F_PGCTX
    sta F_PGCT+1
    lda #<F_BASEX
    sta F_BASE
    lda #>F_BASEX
    sta F_BASE+1
    lda #<F_LIMX
    sta F_LIM
    lda #>F_LIMX
    sta F_LIM+1
    lda #<F_NUMX
    sta F_NUM
    lda #>F_NUMX
    sta F_NUM+1
    lda #0
    sta F_PGCTX+1
    sta SXPAGE+F_PGCT+1                 ; plain pointers, not extended
    sta SXPAGE+F_BASE+1
    sta SXPAGE+F_LIM+1
    sta SXPAGE+F_NUM+1
    jsr MMGR
    lda F_PGCTX
    rts

;; Finds a free entry in the buffer table.
;; Out: X = the buffer number, carry = clear
;; Errors: BUFTBLFULL through SYSERR, which returns to the caller with carry set
;; Keeps: Y
;; See: <REQBUF>, <REQFXBUF>
GETFREE:
    ldx #BUF_CNT-1
GFR010:
    lda PGCT_T,x
    bmi GFR_EXIT
    dex
    bne GFR010
    lda #BUFTBLFULL
    jsr SYSERR
GFR_EXIT:
    clc
    rts

;; Turns a memory manager bank and page into an extension byte and high address byte for an extended pointer.
;;
;; Page p of bank n ($20-$9F) is address (p-$20)*256 in bank pair $80+n. The first page of a bank is instead given as
;; $8000 in the bank pair below, $80+n-1, and bank 0's first page as $2000 with extension byte $8F.
;; In: X = the bank, Y = the page
;; Out: X = the extension byte, Y = the address's high byte
;; See: <REQBUF>, <BUFCOMPACT>, <MEMMGR::CNVRT_XBP>
CNVRT_ADR:
    cpy #$20
    bne CNVA020
    txa
    bne CNVA010
    ldx #$8F
    bmi CNVA_EXIT
CNVA010:
    ora #$80
    tax
    dex
    ldy #$80
    bmi CNVA_EXIT
CNVA020:
    txa
    ora #$80
    tax
    sec
    tya
    sbc #$20
    tay
CNVA_EXIT:
    rts
ZZEND:                                  ;; the end of the module
ZZLEN = ZZEND-ZZORG                     ;; the module's length, which must match LENBUFMG in SosOrg.asm
    .assert ZZLEN == LENBUFMG, "SOSORG gives the module another length"
