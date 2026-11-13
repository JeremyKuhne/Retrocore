; The second part of IPL, included at the end of Ipl.asm: allocating and releasing system internal resources, selecting
; a slot's I/O expansion ROM, disabling and enabling NMI, the keyboard NMI's debugger entry, and queuing events.
;
; The system internal resources (SIRs), by number:
;
;   $00  the sound port, or an I/O device's NMI          $0C  the D VIA's CB2: CSP data I/O, ENSIO
;   $01  the ACIA                                        $0D  the D VIA's CB1: CSP clock, ENSEL, A/D select, switch 3
;   $02  the E VIA's CA2: the keyboard                   $0E  the D VIA's timer 2
;   $03  the E VIA's CA1: the clock                      $0F  the D VIA's timer 1
;   $04  the E VIA's shift register                      $10  the disk stepper, graphics scroll, character download
;   $05  the E VIA's CB2: vertical blanking, rising      $11  slot 1
;   $06  the E VIA's CB1: vertical blanking, falling     $12  slot 2
;   $07  the E VIA's timer 2                             $13  slot 3
;   $08  the E VIA's timer 1                             $14  slot 4
;   $09  the D VIA's CA2: CSP input flag, input switch 1 $15-$17  not assigned
;   $0A  the D VIA's CA1: any slot, kept for SOS
;   $0B  the D VIA's shift register: CSP data
;
; ALLOCSIR and DEALCSIR take a table of five-byte entries, one per resource: the resource number, the ID byte
; (which ALLOCSIR returns and DEALCSIR checks), and the address and bank of the resource's interrupt handler, or zero
; for none.

;; The ID byte the next allocation gets, $81-$FF in turn: bit 7 marks a resource allocated in <SIRTABLE>.
IDBYTE:
    .byte $81

;; Allocates system internal resources, all or none, recording each one's interrupt handler.
;;
;; Each resource must exist and be free. On success, each gets this allocation's ID byte, which is also written to the
;; table for the owner to give back to <DEALCSIR>. If any resource can't be had, those already taken are released.
;; Interrupts are off while the tables change, and the interrupt state is restored on return.
;; In: A = the table's length in bytes, X/Y = the table's address (low, high)
;; Out: carry = set when a resource couldn't be allocated, X = that resource's number
;; Uses: A, X, Y, SIRARGS, SIRARGSIZ, SIRTEMP
;; Keeps: interrupt
;; See: <DEALCSIR>, <SIRTABLE>, <IRQ_RCVR>
ALLOCSIR:
    clc
    php
    sei
    sta SIRARGSIZ
    lda E_REG
    sta SIRTEMP
    ora #BITON2                     ; the primary stack, and RAM writable
    and #BITOFF3
    sta E_REG
    lda SIRTEMP
    pha
    lda Z_REG
    pha
    lda #$00                        ; zero page at page 0
    sta Z_REG
    stx SIRARGS
    sty SIRARGS+1
    ldy #$00
ASIR010:
    lda (SIRARGS),y                 ; the resource number
    cmp #SIRTBLSIZ
    tax
    bcs ASIR020
    lda SIRTABLE,x
    bmi ASIR020                     ; already allocated
    lda IDBYTE
    sta SIRTABLE,x
    iny
    sta (SIRARGS),y                 ; give the owner the ID
    iny
    lda (SIRARGS),y
    sta SIRADR_L,x
    iny
    lda (SIRARGS),y
    sta SIRADR_H,x
    iny
    lda (SIRARGS),y
    sta SIRADR_B,x
    iny
    cpy SIRARGSIZ
    bcc ASIR010
    clc
    inc IDBYTE                      ; the next ID, $FF wrapping to $81
    bmi SIREXIT
    lda #$81
    sta IDBYTE
    bmi SIREXIT
ASIR020:
    stx SIRTEMP
ASIR030:
    sec                             ; release the entries before the bad one
    tya
    sbc #5
    tay
    bcc ASIR040
    lda (SIRARGS),y
    tax
    lda #FALSE
    sta SIRTABLE,x
    beq ASIR030
ASIR040:
    ldx SIRTEMP
    sec
SIREXIT:
    pla
    sta Z_REG
    pla
    sta E_REG
    bcc SIREXIT1
    pla                             ; set carry in the saved status
    ora #BITON0
    pha
SIREXIT1:
    plp
    rts

;; Releases system internal resources, all or none.
;;
;; Each resource must exist, be allocated, and have the ID byte its table entry gives; otherwise none is released.
;; In: A = the table's length in bytes, X/Y = the table's address (low, high)
;; Out: carry = set when a resource couldn't be released, X = that resource's number
;; Uses: A, X, Y, SIRARGS, SIRARGSIZ, SIRTEMP
;; Keeps: interrupt
;; See: <ALLOCSIR>, <SIRTABLE>
DEALCSIR:
    clc
    php
    sei
    sta SIRARGSIZ
    lda E_REG
    sta SIRTEMP
    ora #BITON2                     ; the primary stack, and RAM writable
    and #BITOFF3
    sta E_REG
    lda SIRTEMP
    pha
    lda Z_REG
    pha
    lda #$00                        ; zero page at page 0
    sta Z_REG
    stx SIRARGS
    sty SIRARGS+1
    ldy #$00
DSIR010:
    lda (SIRARGS),y                 ; check every entry first
    tax
    cpx #SIRTBLSIZ
    bcs DSIR030
    iny
    lda SIRTABLE,x
    bpl DSIR030
    cmp (SIRARGS),y
    bne DSIR030
    iny
    iny
    iny
    iny
    cpy SIRARGSIZ
    bcc DSIR010
    ldy SIRARGSIZ
DSIR020:
    sec                             ; then release them, last first
    tya
    sbc #5
    tay
    bcc SIREXIT
    lda (SIRARGS),y
    tax
    lda #FALSE
    sta SIRTABLE,x
    beq DSIR020
DSIR030:
    sec
    bcs SIREXIT

;; Selects a slot's I/O expansion ROM at $C800-$CFFF.
;;
;; It touches $CFFF to deselect every slot's ROM, then a location in the slot's $Cn00 page, which selects that slot's;
;; slot 0 selects none. The operand of the BIT at CNADDR is changed to reach the slot's page.
;; In: A = the slot, 0-4
;; Out: carry = set when the slot number is not valid, and nothing changes, EXPNSLOT = the slot
;; Uses: A
;; Keeps: X, Y, interrupt
;; See: <EXPNSLOT>, <DISPATCH>
SELC800:
    cmp #$05
    bcs SC8EXIT
    php
    sei
    sta EXPNSLOT
    ora #$C0
    sta CNADDR+2                    ; the slot's page
    bit a:$C020
    bit a:$CFFF
CNADDR:
    bit a:$C0FF
    plp
SC8EXIT:
    rts

;; Disables NMI (and the RESET key's interrupt), first waiting for an NMI in progress to finish.
;;
;; While NMIFLAG says an NMI is pending, it waits at 1 MHz, counting in NMICNTR; if the NMI hasn't finished after
;; 65536 tries, the machine stops with NMIHANG (through <SYSDEATH>). The speed goes back as it was.
;; Out: X = the environment register as it was
;; Uses: A, NMICNTR
;; See: <NMIENBL>
NMIDSBL:
    ldx E_REG
    bit NMIFLAG
    bpl NDS020
    txa
    ora #BITON7                     ; 1 MHz
    sta E_REG
    lda #$00
    sta NMICNTR
    sta NMICNTR+1
NDS010:
    bit NMIFLAG
    bpl NDS020
    inc NMICNTR
    bne NDS010
    inc NMICNTR+1
    bne NDS010
    lda #<NMIHANG
    jsr SYSDEATH
NDS020:
    txa
    and #BITOFF4
    sta E_REG
    rts

;; Enables NMI (and the RESET key's interrupt).
;; Uses: A
;; Keeps: X, Y
;; See: <NMIDSBL>
NMIENBL:
    lda E_REG
    ora #BITON4
    sta E_REG
    rts

;; A keyboard NMI handler that enters the boot ROM's monitor, for debugging.
;;
;; SOS's NMI jump, KYBDNMI, can be pointed here. It saves the stack pointer in NMISPSV, selects the monitor's zero page
;; (page 3) and the ROM, and calls the monitor at $F901. The monitor goes back by running <NMICONT>.
;; See: <NMICONT>, <NMI_RCVR>
NMIDBUG:
    tsx
    stx NMISPSV
    lda #$03
    sta Z_REG
    lda E_REG
    ora #$03                        ; the ROM at $F000
    sta E_REG
    jsr $F901

;; Returns from <NMIDBUG> to the NMI receiver: selects the primary stack again and restores the stack pointer that
;; NMIDBUG saved.
;; See: <NMIDBUG>
NMICONT:
    lda E_REG
    ora #BITON2
    sta E_REG
    ldx NMISPSV
    txs
    rts

;; Puts an event in the event queue, after the active events of its priority or higher, to be run by <DISPATCH>.
;;
;; The event is five bytes: its priority, its ID, and the address and bank of its handler. An event of priority 0 is
;; ignored. A full queue stops the machine with EVQOVFL (through <SYSDEATH>). Interrupts are off while the queue
;; changes, and the interrupt state is restored on return.
;; In: X/Y = the event's address (low, high)
;; Out: carry = clear
;; Uses: A, X, Y, QEVARGS, QEVTEMP, QEV_THIS, QEV_LAST
;; Keeps: interrupt
;; See: <DISPATCH>, <DO_EVENT>, <EV_QUEUE>
QUEEVENT:
    clc
    php
    sei
    lda E_REG
    sta QEVTEMP
    ora #BITON2                     ; the primary stack, and RAM writable
    and #BITOFF3
    sta E_REG
    lda QEVTEMP
    pha
    lda Z_REG
    pha
    lda #0                          ; zero page at page 0
    sta Z_REG
    stx QEVARGS
    sty QEVARGS+1
    ldy #0
    lda (QEVARGS),y
    beq Q_EXIT
    ldx EVQ_FREE                    ; take the first free entry
    beq Q_FULL
    stx QEV_THIS
    lda EVQ_LINK,x
    sta EVQ_FREE
    ldy #EVQ_SIZ-2
QEV010:
    lda (QEVARGS),y                 ; copy the event into it, last byte first
    sta EVQ_BANK,x
    dex
    dey
    bpl QEV010
    ldx QEV_THIS
    ldy #0
QEV020:
    sty QEV_LAST                    ; find the first active entry of a lower priority
    lda EVQ_LINK,y
    tay
    lda EVQ_PRI,y
    cmp EVQ_PRI,x
    bcs QEV020
    tya                             ; and link the new entry in before it
    sta EVQ_LINK,x
    txa
    ldy QEV_LAST
    sta EVQ_LINK,y
Q_EXIT:
    pla
    sta Z_REG
    pla
    sta E_REG
    plp
    rts
Q_FULL:
    lda #<EVQOVFL
    jsr SYSDEATH
ZZEND:
ZZLEN = ZZEND-ZZORG
    .assert ZZLEN == LENIPL, "SOSORG gives the module another length"
