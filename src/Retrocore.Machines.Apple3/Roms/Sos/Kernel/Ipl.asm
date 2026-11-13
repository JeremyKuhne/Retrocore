; IPL, interrupts and process launch. Every IRQ, BRK and NMI comes here. IRQ_RCVR saves the interrupted state on the
; SOS stack, passes a BRK, a SOS call, to SCMGR, and otherwise finds the device that interrupted and calls the
; interrupt handler that owns it; NMI_RCVR does the same for NMIs. Both finish in DISPATCH, which restores the state,
; runs any queued event the program should see, and resumes. Ipl2.asm, included at the end, holds the resource
; allocation, the I/O expansion ROM selection, NMI control and the event queue.
;
; Names follow Apple's SOS 1.3 listing.

ZZORG:

; ---------------------------------------------------------------------------------------------------------------------
; Constants and registers
; ---------------------------------------------------------------------------------------------------------------------

FALSE = $00                         ;; a free entry in SIRTABLE
BITON0 = $01                        ;; bit 0 alone
BITON1 = $02                        ;; bit 1 alone
BITON2 = $04                        ;; bit 2 alone
BITON4 = $10                        ;; bit 4 alone
BITON5 = $20                        ;; bit 5 alone
BITON6 = $40                        ;; bit 6 alone
BITON7 = $80                        ;; bit 7 alone
BITOFF3 = $F7                       ;; every bit but 3
BITOFF4 = $EF                       ;; every bit but 4
BITOFF5 = $DF                       ;; every bit but 5
BITOFF6 = $BF                       ;; every bit but 6
BITOFF7 = $7F                       ;; every bit but 7
BACKBIT = $20                       ;; the backup bit that BACKMASK keeps after a SOS call

;; The bank register: which bank of memory is at $2000-$9FFF.
B_REG = $FFEF

;; The environment register. Bit 7: 1 MHz; 6: I/O space at $C000-$CFFF; 5: screen on; 4: the RESET key's NMI enabled;
;; 3: $C000-$FFFF read-only; 2: the primary stack (page 1); 1: the ROM select line; 0: the boot ROM at $F000.
E_REG = $FFDF

;; The zero-page register: which page of memory is zero page. The stack, when not the primary one, is the page above.
Z_REG = $FFD0

D_IFR = $FFDD                       ;; the D VIA's interrupt flags
D_IER = $FFDE                       ;; the D VIA's interrupt enables
E_IORB = $FFE0                      ;; the E VIA's port B; at an NMI, bit 7 is set for the keyboard, clear for I/O
E_IFR = $FFED                       ;; the E VIA's interrupt flags
E_IER = $FFEE                       ;; the E VIA's interrupt enables
E_IORA = $FFEF                      ;; the E VIA's port A: bit 7 is the IRQ line, bits 5 and 4 low for slots 3 and 4

; ---------------------------------------------------------------------------------------------------------------------
; The interrupted state
;
; The receivers push A, X and Y on the interrupted code's stack, above the P and return address the CPU pushed. If
; that was not the primary stack, they save its stack pointer at $01FF and start the SOS stack below it, where they
; push the environment, zero-page and bank registers and the expansion slot.
; ---------------------------------------------------------------------------------------------------------------------

A_SAVE = $103                       ;; the interrupted A, indexed by the stack pointer after the three pushes
S_SAVE = $104                       ;; the interrupted status register, indexed the same way
SP_SAVE = $1FF                      ;; the interrupted stack pointer, when it was not the primary stack
E_SAVE = $1FE                       ;; the interrupted environment register
Z_SAVE = $1FD                       ;; the interrupted zero-page register
B_SAVE = $1FC                       ;; the interrupted bank register

;; The slot whose I/O expansion ROM is selected at $C800-$CFFF, or 0 for none.
;; See: <SELC800>
EXPNSLOT:
    .byte $00

; ---------------------------------------------------------------------------------------------------------------------
; Interrupt sources
; ---------------------------------------------------------------------------------------------------------------------

;; The ACIA's status register; bit 7 is set when the ACIA is interrupting.
ACIASTAT = $C0F1

;; The D VIA's interrupt flag that some slot is interrupting (its CA1).
ANYSLOT:
    .byte BITON1

SLOT1 = $C065                       ;; bit 7 is clear when slot 1 is interrupting
SLOT2 = $C064                       ;; bit 7 is clear when slot 2 is interrupting

;; The bit of <E_IORA> that is clear when slot 3 is interrupting.
SLOT3:
    .byte BITON5

;; The bit of <E_IORA> that is clear when slot 4 is interrupting.
SLOT4:
    .byte BITON4

; ---------------------------------------------------------------------------------------------------------------------
; The interrupt zero page
;
; Interrupt handlers run with zero page at page 0. Each handler called gets 32 bytes of it, taken from the top down
; from $F8, so that nested interrupts each have their own.
; ---------------------------------------------------------------------------------------------------------------------

SIRARGS = $F9                       ;; ALLOCSIR's and DEALCSIR's pointer to their table (two bytes)
QEVARGS = $FB                       ;; QUEEVENT's pointer to the event (two bytes)
IRQADDR = $FD                       ;; the address of the interrupt handler being called (two bytes)
ZPGSP = $FF                         ;; a copy of ZPGSTACK
ZPGSTART = $F8                      ;; where the handlers' zero-page space starts, before any is taken
ZPGSTOP = $28                       ;; the lowest a handler's space can start
ZPGSPACE = $20                      ;; the bytes of zero page each handler gets

;; The start of the zero-page space of the handler called last; each nested handler takes the 32 bytes below.
ZPGSTACK:
    .byte ZPGSTART

; ---------------------------------------------------------------------------------------------------------------------
; The system internal resource (SIR) table
;
; Each interrupt source, and some other hardware, is a resource that a driver allocates with ALLOCSIR before using it
; (Ipl2.asm lists the numbers). The table holds, for each, an allocation byte and the address and bank of the
; handler for its interrupts. INIT clears it, so the initial contents are whatever was in memory when Apple built
; SOS.KERNEL.
; ---------------------------------------------------------------------------------------------------------------------

;; The number of resources, $00-$17.
SIRTBLSIZ = $18

;; Each resource's allocation: bit 7 set when it is allocated, the whole byte the ID that <ALLOCSIR> gave the owner.
SIRTABLE:
    .byte $A0, $D9, $A0, $A0, $A4, $A0, $A0, $CD, $A0, $A0, $94, $A0, $A0, $E5, $A0, $98
    .byte $A0, $A0, $A2, $A0, $A0, $84, $A0, $A0
    .assert * - SIRTABLE == SIRTBLSIZ

;; The low bytes of each resource's interrupt handler address.
SIRADR_L:
    .byte $AE, $D3, $D3, $A0, $C8, $A0, $A0, $A4, $A0, $A0, $81, $A0, $FF, $A1, $A0, $FF
    .byte $82, $A0, $94, $AA, $A0, $90, $A0, $A0
    .assert * - SIRADR_L == SIRTBLSIZ

;; A copy of resource 0's handler address low byte, set before each NMI is passed on, so that with the first byte of
;; <SIRADR_H> after it it makes the address for <CALLNMI>'s indirect jump. Its initial value is whatever was in memory
;; when Apple built SOS.KERNEL.
NMIADR_L:
    .res 1, $FD

;; The high bytes of each resource's interrupt handler address.
SIRADR_H:
    .byte $C5, $A0, $A0, $A5, $A0, $A0, $8D, $A0, $A0, $E5, $A0, $A0, $A5, $A0, $95, $A0
    .byte $A0, $A5, $A0, $A0, $F3, $A0, $A0, $A9
    .assert * - SIRADR_H == SIRTBLSIZ

;; The bank each resource's interrupt handler is in.
SIRADR_B:
    .byte $A0, $C3, $A0, $BD, $A0, $A0, $8F, $A0, $A0, $94, $A0, $A0, $D9, $A0, $A0, $9B
    .byte $A0, $A0, $9F, $A0, $86, $A0, $A0, $B1
    .assert * - SIRADR_B == SIRTBLSIZ

; ---------------------------------------------------------------------------------------------------------------------
; The event queue
;
; Events that drivers have seen but the program has not yet been given wait here (see QUEEVENT in Ipl2.asm). There are
; seven six-byte entries, each a link (the offset of the next entry in its list), then the priority, the ID, and the
; address and bank of the program's event handler. Entry 0 heads both lists: its link is the first active entry, its
; priority is 0, which ends the active list, and its third byte is the first free entry. INIT links the queue, so the
; initial contents are whatever was in memory when Apple built SOS.KERNEL.
; ---------------------------------------------------------------------------------------------------------------------

EVQ_SIZ = 6                         ;; the size of an entry
EVQ_CNT = $07                       ;; the number of entries, entry 0 included
EVQ_LEN = $2A                       ;; the size of the queue

;; The event queue's entries.
EV_QUEUE:
    .byte $FF, $A2, $A0, $A5, $AA, $A0, $88, $A0, $A0, $F0, $A0, $A0, $FD, $CE, $80, $82
    .byte $C6, $89, $9A, $C5, $C5, $A0, $A0, $C5, $A0, $A0, $D3, $A0, $BA, $D2, $A0, $A0
    .byte $C8, $A0, $A0, $A5, $A0, $88, $A0, $A0, $A5, $A0
    .assert * - EV_QUEUE == EVQ_LEN

EVQ_FREE = EV_QUEUE+2               ;; entry 0's third byte: the first free entry
EVQ_LINK = EV_QUEUE+0               ;; an entry's link; entry 0's is the first active entry
EVQ_PRI = EV_QUEUE+1                ;; an entry's priority
EVQ_ID = EV_QUEUE+2                 ;; an entry's ID byte
EVQ_ADRL = EV_QUEUE+3               ;; an entry's handler address, low byte
EVQ_ADRH = EV_QUEUE+4               ;; an entry's handler address, high byte
EVQ_BANK = EV_QUEUE+5               ;; an entry's handler bank

; ---------------------------------------------------------------------------------------------------------------------
; The general interrupt receiver
; ---------------------------------------------------------------------------------------------------------------------

;; The IRQ and BRK handler: saves the interrupted state, then carries out a SOS call or calls the interrupting
;; device's handler, and resumes through <DISPATCH>.
;;
;; It saves A, X and Y on the interrupted stack, sets up SOS's environment (2 MHz, I/O space on, the primary stack,
;; RAM at $F000 and writable, the screen and NMI settings kept), and switches to the SOS stack if it was not on it.
;; There it saves the environment, zero-page and bank registers and the expansion slot, and deselects the expansion
;; ROM.
;;
;; A BRK is a SOS call, which only a program, not SOS, may make. IRQ_RCVR switches the I/O space out, enables
;; interrupts and calls <SCMGR>. Afterwards it hands the error code back in the program's A, with zero set for no
;; error and negative from the code, and resumes the program.
;;
;; Otherwise it polls for the interrupting device: the ACIA, the E VIA's flags, then the D VIA's flags, and when the
;; D VIA says a slot is interrupting, slots 1-4. The device's resource number picks the handler from the SIR table.
;; The handler is called with zero page at page 0, its own 32 bytes of it, and its bank selected. An IRQ that has gone
;; by the time it is polled is counted in IRQCNTR and ignored.
;;
;; Fatal errors (through <SYSDEATH>): STKOVFL when the interrupted stack is too full, BADBRK for a BRK inside SOS,
;; BADINT1 when no allocated device is interrupting (X then holds the resource number it stopped at), and BADINT2
;; when interrupts nest too deep for the zero page.
;; Calls: the interrupt handler at SIRADR_L/SIRADR_H, with X = the start of its zero-page space
;; See: <DISPATCH>, <SCMGR>, <NMI_RCVR>, <ALLOCSIR>
IRQ_RCVR:
    pha
    txa
    pha
    tya
    pha
    tsx
    cpx #$FA                        ; room for what is pushed next?
    bcc GIR005
    lda #<STKOVFL
    jsr SYSDEATH
GIR005:
    ldy S_SAVE,x                    ; Y = the interrupted status register
    cld
    lda E_REG
    tax
    and #BITON5+BITON4              ; keep the screen and NMI settings
    ora #BITON6+BITON2              ; I/O space on, primary stack
    sta E_REG
    txa
    and #BITON2
    bne GIR010
    txa                             ; from another stack: save its pointer and start the SOS stack
    tsx
    stx SP_SAVE
    ldx #<E_SAVE
    txs
    tax
GIR010:
    txa
    pha
    lda Z_REG
    pha
    lda B_REG
    pha
    lda EXPNSLOT
    pha
    bit a:$CFFF                     ; deselect the expansion ROM
    bit a:$C020
    lda #$00
    sta EXPNSLOT
    tya
    and #BITON4                     ; the break flag
    beq POLL_IO
    tsx                             ; a SOS call: only from outside SOS, so with the SOS stack otherwise empty
    cpx #<(B_SAVE-2)
    beq GIR020
    lda #<BADBRK
    jsr SYSDEATH
GIR020:
    lda E_REG                       ; RAM at $C000-$CFFF
    and #BITOFF6
    sta E_REG
    cli
    jsr SCMGR
    lda #BACKBIT
    sta BACKMASK
    jsr CHKBUF
    sei
    ldx SP_SAVE
    lda Z_SAVE                      ; zero page at the caller's stack page, to reach its saved A and P
    eor #BITON0
    sta Z_REG
    lda SERR                        ; the caller's A = the error code
    sta <(A_SAVE),x
    php
    lda <(S_SAVE),x                 ; and its negative and zero flags from it
    and #$7D
    sta <(S_SAVE),x
    pla
    and #$82
    ora <(S_SAVE),x
    sta <(S_SAVE),x
    jmp DISPATCH
POLL_IO:
    bit E_IORA                      ; is the IRQ line still low?
    bpl PIO006
    inc IRQCNTR                     ; no: count a false IRQ
    bne PIO004
    inc IRQCNTR+1
PIO004:
    jmp DISPATCH
PIO006:
    lda #0                          ; the interrupt zero page
    sta Z_REG
    lda E_REG
    ora #BITON7                     ; the ACIA's status is read at 1 MHz
    sta E_REG
    and #BITOFF7
    ldx #$01                        ; resource 1, the ACIA
    ldy ACIASTAT
    sta E_REG
    bmi PIO070
    lda E_IFR
    bpl PIO020
    and E_IER
    ldy #7
    ldx #$02                        ; resources 2-8, the E VIA's flags from bit 0
PIO010:
    lsr a
    bcs PIO070
    inx
    dey
    bne PIO010
    beq PIO035
PIO020:
    lda D_IFR
    bpl PIO035
    and D_IER
    bit ANYSLOT
    bne PIO040
    ldy #7
    ldx #$09                        ; resources 9-$0F, the D VIA's flags from bit 0
PIO030:
    lsr a
    bcs PIO070
    inx
    dey
    bne PIO030
PIO035:
    ldx #$10                        ; nothing found
    bne PIO050
PIO040:
    ldx #$11                        ; resources $11-$14, slots 1-4
    bit SLOT1
    bpl PIO070
    inx
    bit SLOT2
    bpl PIO070
    lda E_IORA
    inx
    bit SLOT3
    beq PIO070
    inx
    bit SLOT4
    beq PIO070
    ldx #$0A                        ; no slot found
PIO050:
    lda #<BADINT1
    jsr SYSDEATH
PIO060:
    lda #<BADINT2
    jsr SYSDEATH

;; Jumps to the interrupt handler at IRQADDR, so that IRQ_RCVR can call it with JSR.
CALLMIH:
    jmp (IRQADDR)
PIO070:
    lda SIRTABLE,x                  ; X = the resource: is it allocated?
    bpl PIO050
    lda SIRADR_L,x
    sta IRQADDR
    ora SIRADR_H,x                  ; and has a handler?
    beq PIO050
    lda SIRADR_H,x
    sta IRQADDR+1
    lda SIRADR_B,x
    sta B_REG
    lda ZPGSTACK                    ; take 32 bytes of zero page for the handler
    cmp #ZPGSTOP+ZPGSPACE
    bcc PIO060
    sbc #ZPGSPACE
    sta ZPGSTACK
    sta ZPGSP
    tax
    jsr CALLMIH
    sei
    lda #$00
    sta Z_REG
    clc
    lda ZPGSTACK                    ; and give them back
    adc #ZPGSPACE
    sta ZPGSTACK
    sta ZPGSP
    lda #BITON1                     ; clear the D VIA's slot flag
    sta D_IFR
    jmp DISPATCH

; ---------------------------------------------------------------------------------------------------------------------
; The NMI receiver
; ---------------------------------------------------------------------------------------------------------------------

;; The NMI handler: saves the interrupted state as <IRQ_RCVR> does, calls the keyboard's NMI routine or the I/O
;; device's, and resumes through <DISPATCH>.
;;
;; An NMI comes from the keyboard (the RESET key) or from the I/O device that has allocated resource 0. A keyboard NMI
;; calls KYBDNMI, in SOS's bank, a jump in the system global data to the handler set for it; an I/O NMI calls
;; resource 0's handler. Either runs with zero page at page 0. An I/O NMI with resource 0 not allocated is fatal:
;; BADINT1, through <SYSDEATH>. So is a stack too full: STKOVFL.
;; Calls: KYBDNMI, or resource 0's handler through <CALLNMI>
;; See: <DISPATCH>, <IRQ_RCVR>, <NMIDBUG>
NMI_RCVR:
    pha
    txa
    pha
    tya
    pha
    tsx
    cpx #$FA
    bcc NMI005
    lda #<STKOVFL
    jsr SYSDEATH
NMI005:
    cld
    lda E_REG
    tax
    and #BITON5+BITON4              ; keep the screen and NMI settings
    ora #BITON6+BITON2              ; I/O space on, primary stack
    sta E_REG
    txa
    and #BITON2
    bne NMI010
    txa                             ; from another stack: save its pointer and start the SOS stack
    tsx
    stx SP_SAVE
    ldx #<E_SAVE
    txs
    tax
NMI010:
    txa
    pha
    lda Z_REG
    pha
    lda B_REG
    pha
    lda EXPNSLOT
    pha
    bit a:$CFFF                     ; deselect the expansion ROM
    bit a:$C020
    lda #$00
    sta EXPNSLOT
    lda #0                          ; the interrupt zero page
    sta Z_REG
    lda E_IORB                      ; the keyboard or an I/O device?
    bmi NMI030
    lda SIRTABLE                    ; an I/O device: resource 0 must be allocated
    bpl NMI020
    jsr CALLNMI
    sei
    jmp DISPATCH

;; Jumps to resource 0's NMI handler, in its bank, so that NMI_RCVR can call it with JSR.
;; See: <NMIADR_L>
CALLNMI:
    lda SIRADR_L
    sta NMIADR_L
    lda SIRADR_B
    sta B_REG
    jmp (NMIADR_L)
NMI020:
    lda #<BADINT1
    jsr SYSDEATH
NMI030:
    lda SYSBANK                     ; the keyboard
    sta B_REG
    jsr KYBDNMI
    sei
    jmp DISPATCH

; ---------------------------------------------------------------------------------------------------------------------
; The dispatcher
; ---------------------------------------------------------------------------------------------------------------------

;; Restores the interrupted state that a receiver saved and resumes the interrupted code, first running any event it
;; should see.
;;
;; IRQ_RCVR and NMI_RCVR jump here, with the SOS stack as they left it. When SOS itself was interrupted, it simply
;; resumes. When a program was, its stack is restored, and while the highest-priority active event has a priority
;; above CEVPRI, the event fence, DISPATCH runs the event's handler at that priority (<DO_EVENT>). The screen's
;; on/off setting is taken from SCRNMODE rather than from the saved environment, so a change made meanwhile stays.
;; See: <IRQ_RCVR>, <NMI_RCVR>, <QUEEVENT>
DISPATCH:
    sei
    lda E_REG
    ora #BITON6                     ; I/O space on, for the expansion ROM switch
    sta E_REG
    pla
    jsr SELC800                     ; reselect the interrupted code's expansion ROM
    pla
    sta B_REG
    pla
    sta Z_REG
    pla                             ; the saved environment, with the screen as SCRNMODE says
    ora #BITON5
    bit SCRNMODE
    bmi DSP005
    and #BITOFF5
DSP005:
    tay
    and #BITON2
    beq DSP010
    sty E_REG                       ; SOS was interrupted: resume it
    bne DSP030
DSP010:
    pla                             ; a program: back to its stack
    tax
    txs
    sty E_REG
DSP020:
    lda CEVPRI                      ; an active event above the fence?
    ldx EVQ_LINK
    cmp EVQ_PRI,x
    bcs DSP030
    lda E_REG
    pha
    lda Z_REG
    pha
    lda B_REG
    pha
    lda CEVPRI
    pha
    jsr DO_EVENT
    sei
    pla
    sta CEVPRI
    pla
    sta B_REG
    pla
    sta Z_REG
    pla
    ora #BITON5
    bit SCRNMODE
    bmi DSP025
    and #BITOFF5
DSP025:
    sta E_REG
    jmp DSP020
DSP030:
    pla
    tay
    pla
    tax
    pla
    rti

;; Runs the highest-priority active event: moves its entry to the free list, raises the fence to its priority and
;; enters its handler.
;;
;; The handler is entered by an RTI, in its bank, with interrupts enabled and A = the event's ID; its RTS returns
;; to DO_EVENT's caller.
;; Out: CEVPRI = the event's priority, A = the event's ID
;; See: <DISPATCH>, <QUEEVENT>
DO_EVENT:
    ldy E_REG
    tya
    and #BITOFF3                    ; make the queue writable
    sta E_REG
    ldx EVQ_LINK                    ; unlink the first active entry
    lda EVQ_LINK,x
    sta EVQ_LINK
    lda EVQ_FREE                    ; and put it at the head of the free list
    sta EVQ_LINK,x
    stx EVQ_FREE
    lda EVQ_PRI,x
    sta CEVPRI
    sty E_REG
    lda EVQ_BANK,x
    sta B_REG
    lda EVQ_ADRH,x
    pha
    lda EVQ_ADRL,x
    pha
    ldy EVQ_ID,x
    php                             ; a status with interrupts enabled
    pla
    and #$82
    pha
    tya
    rti
    .include "Ipl2.asm"
