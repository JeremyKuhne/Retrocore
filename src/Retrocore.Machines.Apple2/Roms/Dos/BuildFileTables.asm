;; DOS 3.3 AND 3.2 COMMAND INTERPRETER: BUILD THE FILE BUFFERS (BLDFTAB)
;;
;; BLDFTB sets up the file buffers, as many as MAXFILES asks for (3 at boot), in a chain going down in memory
;; from just below DOS, and lowers BASIC's HIMEM to below the last. Each open file uses one buffer. MAXFILES
;; (EMAXF, OpenClose.asm) and DOS's start (INITC, DosInit.asm) call it. FILSRC, TSINIT and TSNXT
;; (DosGoer.asm) walk the chain.
;;
;; Each buffer is 595 bytes. From the top down:
;;
;; - a 38-byte header, the address the chain links: the name of the file open in it, 30 bytes, its first byte 0
;;   while the buffer is free; then four pointers, to the parts below and to the next buffer's header ($0000 in
;;   the last). MVBUFP copies the pointers into the file manager's parameter list (CCBFCB on).
;; - 45 bytes (FCBLEN) of work area where the file manager keeps the open file's state (its FCB).
;; - a 256-byte buffer for the file's track/sector list sector.
;; - a 256-byte buffer for its data sector.
;;
;; Where DOS runs at $9D00, the first header is at $9CD3 (FTAB) and three buffers end at $9600, BASIC's HIMEM.
;;
;; The file also holds MVCSW, which hooks DOS into the Monitor's input and output (see DosHook.asm). Runs at
;; $A7D4-$A883 where DOS runs.

;; Builds the chain of CNFTBS file buffers below DOS, all free, and sets BASIC's HIMEM below the last.
;;
;; Any file open in a buffer is forgotten, which is why EMAXF closes all files first.
;; In:    CNFTBS = the number of buffers, 1-16; ASIBSW = 0 if Integer BASIC is active, else Applesoft
;; Out:   ZPGWRK = the last buffer's header; Integer BASIC's HIMEM ($4C) and program start ($CA), or Applesoft's
;;        HIMEM ($73) and string space ($6F), = the last buffer's data sector buffer
;; Uses:  A, X, Y, TEMP1A
BLDFTB:
    sec
    lda FTAB
    sta ZPGWRK
    lda FTAB+1
    sta ZPGWRK+1                    ; the first header
    lda a:CNFTBS
    sta a:TEMP1A                    ; buffers still to build
BFT1:
    ldy #0
    tya
    sta (ZPGWRK),y                  ; name's first byte 0: free
    ; The three pointers, at header bytes 30-35. The low byte is the same in all three: each part is 256 bytes
    ; below the last, after the work area, so the high byte drops by one each time.
    ldy #30
    sec
    lda ZPGWRK
    sbc #FCBLEN
    sta (ZPGWRK),y                  ; the work area: the header less 45
    pha
    lda ZPGWRK+1
    sbc #0
    iny
    sta (ZPGWRK),y
    tax
    dex
    pla
    pha
    iny
    sta (ZPGWRK),y                  ; the track/sector list buffer: 256 below the work area
    txa
    iny
    sta (ZPGWRK),y
    tax
    dex
    pla
    pha
    iny
    sta (ZPGWRK),y                  ; the data buffer: 256 below that
    iny
    txa
    sta (ZPGWRK),y
    dec a:TEMP1A
    beq BFT2
    ; The next header is 38 bytes below the data buffer: link to it and go on there.
    tax
    pla
    sec
    sbc #38
    iny
    sta (ZPGWRK),y
    pha
    txa
    sbc #0
    iny
    sta (ZPGWRK),y
    sta ZPGWRK+1
    pla
    sta ZPGWRK
    jmp BFT1
BFT2:
    pha                             ; the data buffer's address, low byte below, high byte on top
    lda #0
    iny
    sta (ZPGWRK),y                  ; the last link is $0000
    iny
    sta (ZPGWRK),y
    lda a:ASIBSW
    beq BFTIB
    pla
    sta ASHM1+1                     ; Applesoft's HIMEM
    sta ASHM2+1                     ; and the bottom of its string space, which grows down from HIMEM
    pla
    sta ASHM1
    sta ASHM2
    rts
BFTIB:
    pla
    sta IBHMEM+1                    ; Integer BASIC's HIMEM
    sta IBSOP+1                     ; and its program start, which grows down from HIMEM
    pla
    sta IBHMEM
    sta IBSOP
    rts

;; Hooks DOS into the Monitor's input and output: puts CHRIN in KSW (INSW) and CHROUT in CSW (OUTSW), first
;; saving whatever is there in SVINS and SVOUTS as the real input and output routines.
;;
;; Called each time DOS gives control back, since BASIC, PR# and IN# replace the hooks. A hook already
;; pointing into DOS's page is left alone: only the high bytes are compared. DOS's page 3 vector $03EA jumps
;; here, so programs can reconnect DOS after changing the hooks.
;; Uses:  A
;; Entry: MVOSW = the output hook only
MVCSW:
    lda INSW+1
    cmp CINA+1
    beq MVOSW
    sta a:SVINS+1
    lda INSW
    sta a:SVINS
    lda CINA
    sta INSW
    lda CINA+1
    sta INSW+1
MVOSW:
    lda OUTSW+1
    cmp COUTA+1
    beq MVSRTN
    sta a:SVOUTS+1
    lda OUTSW
    sta a:SVOUTS
    lda COUTA
    sta OUTSW
    lda COUTA+1
    sta OUTSW+1
MVSRTN:
    rts
