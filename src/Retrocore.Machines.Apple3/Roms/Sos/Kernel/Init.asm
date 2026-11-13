; INIT: the kernel managers' initialization routines. The loader assembles INIT into the space it keeps at
; INITMODULE ($28F8) and calls these from INIT_KRNL, with SOS's zero page selected and I/O switched in. Once the
; loader is done the space is not needed again.

ZZORG:                              ; INIT's first byte
TRUE = $80                          ;; a true flag: bit 7 set
FALSE = $00                         ;; a false flag
BITON6 = $40                        ;; bit 6
BITON7 = $80                        ;; bit 7
E_REG = $FFDF                       ;; the environment register
Z_REG = $FFD0                       ;; the zero-page register
D_DDRB = $FFD2                      ;; the D 6522's port B direction register
D_DDRA = $FFD3                      ;; the D 6522's port A direction register
D_ACR = $FFDB                       ;; the D 6522's auxiliary control register
D_PCR = $FFDC                       ;; the D 6522's peripheral control register
D_IFR = $FFDD                       ;; the D 6522's interrupt flag register
D_IER = $FFDE                       ;; the D 6522's interrupt enable register
E_IORB = $FFE0                      ;; the E 6522's port B, which drives the sound output
E_DDRB = $FFE2                      ;; the E 6522's port B direction register
E_DDRA = $FFE3                      ;; the E 6522's port A direction register
E_ACR = $FFEB                       ;; the E 6522's auxiliary control register
E_PCR = $FFEC                       ;; the E 6522's peripheral control register
E_IFR = $FFED                       ;; the E 6522's interrupt flag register
E_IER = $FFEE                       ;; the E 6522's interrupt enable register
ACIASTAT = $C0F1                    ;; the serial port's status register; writing it resets the ACIA

;; Sets up the interrupt system: masks interrupts, sets up the 6522s and the ACIA, and clears the SIR table.
;;
;; The 6522s' interrupts are all disabled except the D 6522's CA1. The E 6522's port B (the sound port) is set to
;; $FF, and graphics scrolling, character set loading, ENSEL and ENSIO are switched off or to input. SIR $0A is
;; marked taken so no driver can claim it. The RAM vectors at $FFFA-$FFFF (NMI, reset, IRQ) and the JMPs at
;; $FFCA-$FFCF are pointed at SOS's handlers.
;; Out:   interrupt = set (masked)
;; Uses:  A, X, Y
;; See:   <NMI_RCVR>, <IRQ_RCVR>, <COLDSTRT>, <SIRTABLE>
INT_INIT:
    sei
    lda #<ZPGSTART
    sta ZPGSTACK
    lda E_REG
    pha
    ora #BITON7+BITON6              ; 1 MHz and I/O
    sta E_REG
    sta ACIASTAT
    lda #$FF
    sta D_DDRB
    sta D_DDRA
    lda #$00
    sta D_ACR
    lda #$76
    sta D_PCR
    lda #$7F
    sta D_IFR
    sta D_IER
    lda #$82
    sta D_IER
    lda #$3F
    sta E_DDRB
    lda #$0F
    sta E_DDRA
    lda #$00
    sta E_ACR
    lda #$63
    sta E_PCR
    lda #$7F
    sta E_IFR
    sta E_IER
    lda #$FF
    sta E_IORB
    bit a:$C0D8                     ; no graphics scrolling
    bit a:$C0DA                     ; no character set loading
    bit a:$C0DC                     ; ENSEL off
    bit a:$C0DE                     ; ENSIO for input
    pla
    sta E_REG
    lda #FALSE
    sta NMIFLAG
    ldy #<(SIRTBLSIZ-1)
INTI010:
    sta SIRTABLE,y
    dey
    bpl INTI010
    lda #TRUE
    sta SIRTABLE+$0A
    ldx #$05
INTI020:
    lda RAMVECT,x
    sta a:$FFFA,x
    lda RAMJMPS,x
    sta a:$FFCA,x
    dex
    bpl INTI020
    rts

;; The NMI, reset and IRQ vectors <INT_INIT> copies to $FFFA-$FFFF.
RAMVECT:
    .word NMI_RCVR
    .word COLDSTRT
    .word IRQ_RCVR

;; The JMPs to the NMI and IRQ handlers that <INT_INIT> copies to $FFCA-$FFCF.
RAMJMPS:
    jmp NMI_RCVR
    jmp IRQ_RCVR

;; Empties the event queue: clears every entry and links all but the first into the free list.
;;
;; The first entry, at offset 0, heads the list of queued events, which starts empty.
;; Uses:  A, X, Y
;; See:   <EV_QUEUE>, <QUEEVENT>
EVQ_INIT:
    ldy #<EVQ_LEN
    lda #0
EVQI010:
    sta EV_QUEUE-1,y
    dey
    bne EVQI010
    ldx #<(EVQ_CNT-2)
    lda #<EVQ_SIZ
    sta EVQ_FREE
EVQI020:
    tay
    clc
    adc #<EVQ_SIZ
    sta EVQ_LINK,y
    dex
    bne EVQI020
    rts

PCLK = $F0                          ;; CLK_INIT's pointer to the saved clock (3 bytes, with its X byte)
CKSUM = $F2                         ;; CLK_INIT's running checksum
CLKICR = $11                        ;; the clock chip's interrupt control register, selected through Z_REG
CLKSTBY = $16                       ;; the clock chip's standby interrupt register, selected through Z_REG
CLOCK = $C070                       ;; the clock chip's data address

;; Sets the pseudo clock from the copy saved in the RAM under the D 6522, and turns off the clock chip's interrupts.
;;
;; The saved copy is 10 bytes at $FFD0 in the hidden RAM ($8F:FFD0), then a checksum byte: $A5 exclusive-ORed with
;; each of the 10. If the checksum is wrong the pseudo clock is cleared. The clock chip's register is chosen by the
;; zero-page register's value while it is accessed at <CLOCK>.
;; Uses:  A, X, Y
;; See:   <PCLOCK>
CLK_INIT:
    lda #$D0
    sta PCLK
    lda #$FF
    sta PCLK+1
    lda #$8F
    sta SXPAGE+PCLK+1
    lda #$A5
    sta CKSUM
    ldy #$00
CLK010:
    lda (PCLK),y
    sta PCLOCK,y
    eor CKSUM
    sta CKSUM
    iny
    cpy #$0A
    bcc CLK010
    cmp (PCLK),y
    beq CLK030
    lda #$00
CLK020:
    dey
    sta PCLOCK,y
    bne CLK020
CLK030:
    lda E_REG
    pha
    ora #$80                        ; 1 MHz for the clock chip
    sta E_REG
    lda #$00
    ldy Z_REG
    ldx #CLKICR
    stx Z_REG
    sta CLOCK                       ; no clock interrupts
    ldx #CLKSTBY
    stx Z_REG
    sta CLOCK                       ; no standby interrupt
    sty Z_REG
    pla
    sta E_REG
    rts

;; Marks every character file control block free.
;; Uses:  A, X
;; Keeps: Y
;; See:   <CFCB_DEV>
CFMGR_INIT:
    lda #$80
    ldx #CFCB_MAX-1
CFINIT010:
    sta CFCB_DEV,x
    dex
    bpl CFINIT010
    rts

D_TPARMX = $C0                      ;; the device manager's parameters in SOS's zero page
REQCODE = D_TPARMX+$00              ;; the device request code
DNUM = D_TPARMX+$01                 ;; the device number

;; DMGR_INIT's count of devices left to initialize.
;;
;; Its initial value is whatever was in memory when Apple built SOS.KERNEL; DMGR_INIT sets it at run time.
DNUM_TEMP:
    .res 1, $C3

;; Initializes every device in the system device table, the last first, with the D_INIT request (8).
;;
;; It also makes <MAX_DNUM> one more than the highest device number, as the device manager expects.
;; Uses:  A, X, Y, DNUM_TEMP
;; See:   <DMGR>
DMGR_INIT:
    ldx MAX_DNUM
    inc MAX_DNUM
    stx DNUM_TEMP
DMI110:
    lda #8
    sta REQCODE
    lda DNUM_TEMP
    sta DNUM
    jsr DMGR
    dec DNUM_TEMP
    bne DMI110
    rts

;; Marks every entry of the buffer table free, and empties the buffer reference table.
;;
;; Entry 0's X byte is set to $FF, which the buffer manager relies on when it looks for the lowest buffer.
;; Out:   carry = clear
;; Uses:  A, X
;; Keeps: Y
;; See:   <PGCT_T>, <XBYTE_T>, <BUFREF>
BMGR_INIT:
    lda #$FF
    sta XBYTE_T
    ldx #BUF_CNT-1
    lda #$80
BUFI010:
    sta PGCT_T,x
    dex
    bne BUFI010
    stx BUFREF
    clc
    rts

;; Empties the memory manager's segment table and works out how much bank-switched memory there is.
;;
;; The segment table's entries are all linked into the free list. <VRT_LIM> becomes the number of pages of
;; bank-switched memory less 1: (MEMSIZE - 4) * 64 + 127. With less than 64K (MEMSIZE under 4), it stops with
;; SYSDEATH.
;; Out:   carry = clear
;; Uses:  A, Y
;; Keeps: X
;; See:   <MEMSIZE>, <ST_FLINK>
MMGR_INIT:
    lda #0
    sta ST_ENTRY
    lda #$81
    sta ST_FREE
    ldy #ST_CNT-1
    lda #$80                        ; the last entry's link is null
    sta ST_FLINK,y
MEMI010:
    tya
    ora #$80
    dey
    sta ST_FLINK,y
    bne MEMI010
    sec
    lda MEMSIZE
    sbc #4
    bcc MEMI_ERR
    lsr a
    lsr a
    sta a:VRT_LIM+1
    lda #$FE
    ror a                           ; $7F, or $FF when the second shift carried out a 1
    sta a:VRT_LIM
    clc
    rts
MEMI_ERR:
    lda #MEM2SML
    jsr SYSDEATH

SISTER = $1400                      ;; the block file manager's extend page (SOS's)

;; Sets up the block file manager's buffers and zero page.
;;
;; It points the two FCB pointers at the file control block pages, clears the pathname buffer, the volume control
;; block, both FCB pages, the first $40 bytes of SOS's zero page and the work space, and sets the prefix pointer,
;; the FCB page and the two bitmap pages.
;; Out:   carry = clear
;; Uses:  A, X, Y
;; See:   <BFM_INIT2>
BFM_INIT:
    lda #BFMFCB1
    sta <(FCBZPP+1)
    lda #BFMFCB2
    sta <(FCBZPP+3)
    lda #0
    sta <(FCBZPP)
    sta <(FCBZPP+2)
    sta SISTER+FCBZPP+1
    sta SISTER+FCBZPP+3
    tay
CLRBUFFS:
    sta PATHBUF,y
    sta VCB,y
    sta (<(FCBZPP)),y
    sta (<(FCBZPP+2)),y
    iny
    bne CLRBUFFS
    ldx #$3F
CLRZWRK:
    sta 0,x
    sta WORKSPC,x
    dex
    bpl CLRZWRK
    lda #>PATHBUF
    sta a:PFIXPTR+1
    lda #BFMFCB1
    sta a:FCBADDRH
    lda #BMAPAGE
    sta a:BMAMADR
    lda #BMBPAGE
    sta a:BMBMADR
    clc
    rts
ZZEND:                              ; INIT's end
ZZLEN = ZZEND-ZZORG
    .assert ZZLEN == LENINIT, "SOSORG gives the module another length"
