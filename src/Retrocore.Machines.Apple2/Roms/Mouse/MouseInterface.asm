;; APPLE MOUSE INTERFACE CARD FIRMWARE (341-0270-C)
;;
;; The 6502 firmware of Apple's mouse card for the II, II Plus and IIe (the AppleMouse II), in its 2 KB EPROM.
;; The card has no $C800 ROM: its 6821 PIA's port B bits 1-3 drive the EPROM's A8-A10, so the firmware switches
;; eight 256-byte banks through its own page, $Cn00-$CnFF, while it runs. A 68705 microcontroller (341-0269) does
;; the card's real work: it counts the mouse's quadrature pulses, keeps the position within its bounds, times
;; vertical blanking and pulls the slot's IRQ line. The firmware only passes bytes to and from it through the PIA.
;;
;; Assembles byte-identically to the 341-0270-C EPROM (2048 bytes, SHA-1 3a9d881a8a8d30f55b9719aceebbcf717f829d6f).
;; Maintained by hand; MouseInterfaceSourceTests pins it by digest. It is a reference for the emulator's own mouse
;; firmware, Mouse.rom.asm, which answers the same calls without a microcontroller; the emulator does not run it.
;;
;; THE BANKS
;;
;;   0  Identification, the entry points, and the dispatch every call starts and ends in.
;;   1  The copyright message ($Cn1B), and a request that sends slot 0's holes and reads a byte back ($Cn1A).
;;   2  INITMOUSE: resets the microcontroller and synchronizes its clock with vertical blanking.
;;   3  Sends one command byte: SETMOUSE, CLEARMOUSE, HOMEMOUSE and SERVEMOUSE, which also reads one back.
;;   4  BASIC's IN# and PR#: the hooks, turning the mouse on or off, and reading the position for INPUT.
;;   5  Writes BASIC's "X,Y,B" line into the input buffer.
;;   6  Sends or receives one byte, and READMOUSE's five.
;;   7  Sends a command with its parameters: POSMOUSE and CLAMPMOUSE.
;;
;; Every bank holds the same few instructions at $Cn70 (BANKn_SWITCH): they put the bank number from MOUBANK on
;; port B, which switches the EPROM under the 6502 as it runs, then pull an entry code that the new bank, at the
;; same address, acts on: zero for the bank's main routine at $Cn00, others for its other routines, and a negative
;; one to return through an address pushed earlier. A routine that must come back to the bank that called it finds
;; that bank in MOUMODE's upper nibble, which the caller set: 2 for bank 1, 4 for bank 2 and 8 for bank 4.
;;
;; THE CALLS
;;
;; The mouse routines ($Cn12-$Cn19) are called with X = $Cn and Y = $n0, and use them throughout: X to reach the
;; slot's screen holes, Y the PIA. They return carry clear, or set for an error; A is not kept. Only SERVEMOUSE,
;; which an interrupt handler may call with the language card's RAM over the Monitor, finds the slot itself, with an
;; RTS it writes at $06 rather than the Monitor's IORTS. BASIC's entries find it with IORTS, keep A, X and Y, and
;; leave MSLOT = $Cn. The Pascal entries all answer error 3, and $Cn1A-$Cn1F are the factory's own.
;;
;; The microcontroller's commands, as the firmware sends them (MOUARG holds the command on its way):
;;   $00-$0F  SETMOUSE's mode              $10  read status, Y and X (five bytes back)
;;   $20      read the interrupt status    $30  clear the position     $40  set the position (X and Y follow)
;;   $50      reset; then again as vertical blanking starts         $60/$61  clamp X/Y (minimum and maximum follow)
;;   $70      home                         $80  BASIC mode on (from PR#; $00 turns it off)
;;   $90-$9F, $A0, $B0-$BF, $C0, $F0/$F1  the factory entries' own

.cpu Mos6502

.include "../System/IIeEquates.asm"
.include "../System/MonitorEntries.asm"

CLRROM = $CFFF                      ;; releases the $C800 expansion ROM; its read here also latches the video byte
COUT = $FDED                        ;; the Monitor's character output, through CSW

;; X holds $Cn, so a screen hole's base less $C0, indexed by X, is slot n's own hole.
CN = $C0

; The screen holes: slot 0's column holds CLAMPMOUSE's bounds, each slot's its own mouse.
MOUXL = $0478                       ;; X position, low byte; slot 0's: CLAMPMOUSE's minimum, low byte
MOUYL = $04F8                       ;; Y position, low byte; slot 0's: CLAMPMOUSE's maximum, low byte
MOUXH = $0578                       ;; X position, high byte; slot 0's: CLAMPMOUSE's minimum, high byte
MOUYH = $05F8                       ;; Y position, high byte; slot 0's: CLAMPMOUSE's maximum, high byte
MOUBANK = $0678                     ;; the firmware's own: port B's bank bits for the next switch (bank times 2)
MOUARG = $06F8                      ;; the firmware's own: the command being sent, the byte read, or a byte count
MOUSTAT = $0778                     ;; status: 7 button down, 6 down at the last read, 5 moved, 3/2/1 interrupt by VBL/button/movement
MOUMODE = $07F8                     ;; mode: 0 on, 1/2/3 interrupt on movement/button/VBL, 7 BASIC; 4-6 the bank to return to

; The PIA, indexed by Y = $n0. Control register bit 2 selects the data register, clear selects the direction one.
PIADATAA = $C080                    ;; port A: the byte to or from the microcontroller
PIACTLA = $C081
PIADATAB = $C082                    ;; port B: 0 sync latch, 1-3 the EPROM bank, 4-7 to and from the microcontroller
PIACTLB = $C083
DATAREG = $04                       ;; control register bit 2: the port's data register, not its direction

; Port B's handshake with the microcontroller.
ACK = $10                           ;; PB4, out: the 6502 has taken the byte the microcontroller offered
STROBE = $20                        ;; PB5, out: the 6502 has put a byte on port A
OFFERED = $40                       ;; PB6, in: the microcontroller has put a byte on port A
BUSY = $80                          ;; PB7, in: the microcontroller is taking a byte

; Page zero and the input buffer, which the firmware borrows and puts back.
MOUPTR = $06                        ;; a pointer, or a counter's low byte; SERVEMOUSE's RTS
MOUCOUNT = $08                      ;; the high byte of INITMOUSE's three-byte counter
NUMBERH = $0220                     ;; the number being written as decimal, high byte
NUMBERL = $0221                     ;; and low byte
SAVEY = $0222                       ;; Y during BASIC's input

; The two marks INITMOUSE puts in hi-res page 1, the last bytes the II Plus's video reads before vertical blanking.
HGRMARK1 = $3FD0
HGRMARK2 = $3FE0

; Bank 0: identification, the entry points, and the dispatch every call starts and ends in.
.logicalorg $C400

;; BASIC's entry, where PR#n or IN#n points a hook: BIT sets overflow, which says neither input nor output yet.
;; In:    A = the character to print, or the character under the cursor
;; Out:   A = the character read, for input
;; Keeps: X, Y (input returns X = the line's length)
BASIC:
    bit IORTS                       ; IORTS is an RTS, $60: overflow set
    bvs BASICCALL

;; BASIC's input entry ($Cn05), with carry set. The BCC's offset, $18, is the CLC of the output entry.
BASICIN:
    sec
    .byte $90                       ; BCC BASICCALL, never taken from here

;; BASIC's output entry ($Cn07), with carry clear.
BASICOUT:
    clc
    clv
    bvc BASICCALL

.assert * == $C40B
    .byte $01                       ; $Cn0B: the generic Pascal 1.1 signature
    .byte $20                       ; $Cn0C: an X-Y pointing device, the mouse
    .byte <PASCAL, <PASCAL, <PASCAL, <PASCAL ; INIT, READ, WRITE and STATUS all answer error 3
    .byte $00                       ; $Cn11: more entries follow
    .byte <SETMOUSE, <SERVEMOUSE, <READMOUSE, <CLEARMOUSE
    .byte <POSMOUSE, <CLAMPMOUSE, <HOMEMOUSE, <INITMOUSE
    .byte <MCUREQUEST, <COPYRIGHT, <MCUCOMMAND9, <MCUCOMMANDA, <MCUCOMMANDB, <MCUCOMMANDC

;; Finds the slot for BASIC's entries, keeps the registers and MSLOT, and goes to bank 4 as overflow and carry say.
;; In:    overflow = set from $Cn00, else carry = set for input, clear for output
;; Out:   MSLOT = $Cn
BASICCALL:
    php
    sei
    sta MSLOT                       ; A, for a moment
    pha
    tya
    pha
    txa
    pha
    jsr IORTS                       ; leaves its return address's high byte, $Cn, just below the stack
    tsx
    lda $0100,x
    tax                             ; X = $Cn
    php
    asl a
    asl a
    asl a
    asl a
    plp
    tay                             ; Y = $n0
    lda MSLOT
    stx MSLOT
    pha                             ; the character, for bank 4
    lda #4*2                        ; bank 4
    bvs ENTERBANK                   ; $Cn00: bank 4 works out the hook
    bcc CALLBANK                    ; output: entry code 1
    bcs CALLBANK2                   ; input: entry code 2

;; $Cn1A, the factory's: sends command $F0 or $F1 with slot 0's holes and returns a byte in MOUXH (slot 0's).
;; In:    A = 0 or 1, X = $Cn, Y = $n0
MCUREQUEST:
    and #$01
    ora #$F0
    sta MOUARG-CN,x
    lda #1*2                        ; bank 1, entry code 1
    bne CALLBANK

;; $Cn1C, the factory's: sends command $90-$9F with parameters.
;; In:    A = the low nibble, X = $Cn, Y = $n0
MCUCOMMAND9:
    and #$0F
    ora #$90
    bne SENDPARAMETERS
    .byte $FF, $FF

;; Readies port B, with bits 1-5 as outputs, and switches to the bank in MOUBANK, which pulls its entry code.
;; In:    MOUBANK = the bank times 2, the stack = the entry code
SWITCHBANK:
    lda PIACTLB,y
    and #<~DATAREG
    sta PIACTLB,y
    lda #$3E
    sta PIADATAB,y                  ; direction: the bank bits and the strobes out, the rest in
    lda PIACTLB,y
    ora #DATAREG
    sta PIACTLB,y
.assert * == $C470
BANK0_SWITCH:
    lda PIADATAB,y
    and #$C1                        ; a new bank, with ACK and STROBE down
    ora MOUBANK-CN,x
    sta PIADATAB,y                  ; bank 0 again, from wherever the call went
    pla
    beq RETURNOK                    ; 0: done
    ror a
    bcc RETURNERROR                 ; 2: done, with an error
    pla                             ; 1: a BASIC call, done: its registers back
    tax
    pla
    tay
    pla
    plp
    rts

RETURNOK:
    clc
RETURN:
    rts

;; Bounds X (A = 0) or Y (A = 1) to slot 0's MOUXL/MOUXH (minimum) and MOUYL/MOUYH (maximum).
;; In:    X = $Cn, Y = $n0
;; Out:   carry = clear
CLAMPMOUSE:
    and #$01
    ora #$60
;; Sends the command in A with its parameters, through bank 7.
SENDPARAMETERS:
    sta MOUARG-CN,x
    lda #7*2
;; Enters a bank with entry code 1.
CALLBANK:
    sta MOUBANK-CN,x
    lda #1
CALLBANK_1:
    pha
    bne SWITCHBANK

;; Copies the status and position into the screen holes, if the mouse is on.
;; In:    X = $Cn, Y = $n0
;; Out:   carry = clear
READMOUSE:
    lda #6*2
;; Enters a bank with entry code 2.
CALLBANK2:
    sta MOUBANK-CN,x
    lda #2
    bne CALLBANK_1

;; Sets the position to 0, 0, and the holes with it.
;; In:    X = $Cn, Y = $n0
;; Out:   carry = clear
CLEARMOUSE:
    lda #$30
;; Sends the one-byte command in A, through bank 3.
SENDCOMMAND:
    sta MOUARG-CN,x
    lda #3*2
;; Enters a bank at its main routine, entry code 0.
ENTERBANK:
    sta MOUBANK-CN,x
    lda #0
    pha
    beq SWITCHBANK

;; Sets the mode: bit 0 on, bits 1, 2 and 3 interrupt on movement, the button and vertical blanking.
;; In:    A = the mode, X = $Cn, Y = $n0
;; Out:   carry = set if the mode is above $0F
SETMOUSE:
    cmp #$10
    bcs RETURN
    sta MOUMODE-CN,x
    bcc SENDCOMMAND

;; Resets the microcontroller: the mouse off at 0, 0 within 0-1023, its clock set by vertical blanking.
;; In:    X = $Cn, Y = $n0
;; Out:   carry = clear
INITMOUSE:
    lda #2*2
    bne ENTERBANK

;; Sets the position from the slot's holes.
;; In:    X = $Cn, Y = $n0
;; Out:   carry = clear
POSMOUSE:
    lda #$40
    bne SENDPARAMETERS

;; Called from an interrupt handler: finds the slot without the Monitor, which the language card may hide, and puts
;; the interrupt's cause in MOUSTAT's bits 1-3.
;; Out:   carry = clear if the mouse interrupted, X = $Cn, Y = $n0
SERVEMOUSE:
    ldy MOUPTR
    lda #$60                        ; RTS
    sta MOUPTR
    jsr MOUPTR
    sty MOUPTR
    tsx
    lda $0100,x                     ; $Cn, from the JSR
    tax
    asl a
    asl a
    asl a
    asl a
    tay
    lda #$20
    bne SENDCOMMAND

;; Moves the position to the bounds' minimums.
;; In:    X = $Cn, Y = $n0
;; Out:   carry = clear
HOMEMOUSE:
    lda #$70
    bne SENDCOMMAND

;; $Cn1D, the factory's: sends command $A0 with A.
MCUCOMMANDA:
    pha
    lda #$A0
    bne SENDPARAMETERS

;; $Cn1E, the factory's: sends command $B0-$BF.
MCUCOMMANDB:
    and #$0F
    ora #$B0
    bne SENDCOMMAND

;; $Cn1F, the factory's: sends command $C0.
MCUCOMMANDC:
    lda #$C0
    bne SENDCOMMAND

;; $Cn1B: clears the screen and prints the copyright message, from bank 1.
COPYRIGHT:
    lda #1*2
    bne ENTERBANK

;; Pascal's INIT, READ, WRITE and STATUS: the card has no Pascal driver.
;; Out:   X = 3, carry = set
PASCAL:
    ldx #3
RETURNERROR:
    sec
    rts
    .byte $FF, $FF, $FF
.assert * == $C4FB
    .byte $D6                       ; $CnFB: the mouse's own identification byte
    .byte $FF, $FF, $FF, $01
.assert * == $C500

; Bank 1: the copyright message, and $Cn1A's request.
.logicalorg $C400

;; Clears the screen and prints COPYRIGHTTEXT, then goes back to bank 0.
;; In:    X = $Cn, Y = $n0
;; Keeps: Y, MOUPTR
SHOWCOPYRIGHT:
    tya
    pha
    lda MOUPTR
    pha
    lda MOUPTR+1
    pha
    stx MOUPTR+1
    lda #<COPYRIGHTTEXT
    sta MOUPTR
    jsr HOME
    ldy #0
SHOWCOPYRIGHT_1:
    lda (MOUPTR),y
    beq SHOWCOPYRIGHT_2
    jsr COUT
    iny
    bne SHOWCOPYRIGHT_1
SHOWCOPYRIGHT_2:
    pla
    sta MOUPTR+1
    pla
    sta MOUPTR
    pla
    tay
    bne BANK1_DONE
COPYRIGHTTEXT:
    .hiascii "AppleMouse"
    .byte $8D
    .hiascii "Copyright 1983 by Apple Computer, Inc."
    .byte $8D, $8D
    .hiascii "Bachman/Marks/MacKay"
    .byte $8D, $00

.assert * == $C470
BANK1_SWITCH:
    lda PIADATAB,y
    and #$F1
    ora MOUBANK-CN,x
    sta PIADATAB,y
    pla
    bmi BANK1_RETURN                ; negative: return through the address pushed earlier
    beq SHOWCOPYRIGHT               ; 0
    bne MCUREQUEST1                 ; 1
;; Goes back to bank 0, done.
BANK1_DONE:
    lda #0
    sta MOUBANK-CN,x
    pha
    beq BANK1_SWITCH
BANK1_RETURN:
    rts

;; $Cn1A's request: sends the command in MOUARG and slot 0's MOUXL and MOUYL, one byte at a time through bank 6;
;; then for $F1 slot 0's MOUXH too, and for $F0 reads a byte back into slot 0's MOUXH.
;; In:    MOUARG = $F0 or $F1, X = $Cn, Y = $n0
MCUREQUEST1:
    lda MOUMODE-CN,x
    and #$0F
    ora #$20                        ; come back to bank 1
    sta MOUMODE-CN,x
    txa
    pha                             ; $Cn: the high byte of each address to come back through
    pha
    pha
    pha
    lda #<(MCUREQUEST1_1-1)
    pha
    lda MOUARG-CN,x
;; Sends A through bank 6, which comes back through the address on the stack.
MCUREQUEST1_SEND:
    pha
    lda #6*2
    sta MOUBANK-CN,x
    lda #0
    pha
    beq BANK1_SWITCH
MCUREQUEST1_1:
    lda #<(MCUREQUEST1_2-1)
    pha
    lda MOUXL
    clc
    bcc MCUREQUEST1_SEND
MCUREQUEST1_2:
    lda #<(MCUREQUEST1_3-1)
    pha
    lda MOUYL
    clc
    bcc MCUREQUEST1_SEND
MCUREQUEST1_3:
    lda #<(BANK1_DONE-1)
    pha
    ror MOUARG-CN,x                 ; $F1 sends MOUXH, $F0 reads it
    bcc MCUREQUEST1_4
    lda MOUXH
    bcs MCUREQUEST1_SEND
;; Reads a byte through bank 6 into MOUARG, coming back to MCUREQUEST1_5.
MCUREQUEST1_4:
    txa
    pha
    lda #<(MCUREQUEST1_5-1)
    pha
    lda #6*2
    sta MOUBANK-CN,x
    lda #1
    pha
    bne BANK1_SWITCH
MCUREQUEST1_5:
    lda MOUARG-CN,x
    sta MOUXH
    rts                             ; to BANK1_DONE
    .res 31, $FF
    .byte $C2
.assert * == $C500

; Bank 2: INITMOUSE.
.logicalorg $C400

;; Resets the microcontroller with command $50, reads its answer, and then sends $50 again as vertical blanking
;; starts, so its clock keeps time with the display. The IIe reads RDVBLBAR for that. The II and II Plus cannot,
;; so this clears hi-res page 1 but for two marks in its last line, shows it, and watches the video's bytes through
;; the PIA's sync latch for the marks; it leaves the display in text, with lo-res, page 1 and no mixing.
;; In:    X = $Cn, Y = $n0
;; Uses:  $2000..$3FFF (the II and II Plus's hi-res page 1)
INITBANK:
    lda MOUMODE-CN,x
    and #$0F
    ora #$40                        ; come back to bank 2
    sta MOUMODE-CN,x
    txa
    pha
    pha
    pha
    lda #<(INITBANK_1-1)
    bne INITBANK_SEND
INITBANK_1:
    lda #<(INITBANK_2-1)
    pha
    lda #6*2                        ; read a byte through bank 6
    sta MOUBANK-CN,x
    lda #1
    pha
    bne BANK2_SWITCH
INITBANK_2:
    lda VERSION
    cmp #$06                        ; the IIe
    bne INITBANK_PLUS
INITBANK_3:
    lda RDVBLBAR
    bmi INITBANK_3                  ; wait for the picture
INITBANK_4:
    lda RDVBLBAR
    bpl INITBANK_4                  ; then for blanking
INITBANK_5:
    lda RDVBLBAR
    bmi INITBANK_5                  ; then for the picture again: vertical blanking starts next time it changes
    lda #<(BANK2_DONE-1)
    bne INITBANK_SEND
;; Sends $50 through bank 6, which comes back through the address in A.
INITBANK_SEND:
    pha
    lda #$50
    pha
    lda #6*2
    sta MOUBANK-CN,x
    lda #0
    pha
    beq BANK2_SWITCH

;; The II and II Plus: clears hi-res page 1.
INITBANK_PLUS:
    lda MOUPTR
    pha
    lda MOUPTR+1
    pha
    tya
    pha
    lda #$20
    sta MOUPTR+1
    ldy #0
    sty MOUPTR
INITBANK_PLUS_1:
    lda #0
INITBANK_PLUS_2:
    sta (MOUPTR),y
    iny
    bne INITBANK_PLUS_2
    inc MOUPTR+1
    lda MOUPTR+1
    cmp #$40
    bne INITBANK_PLUS_1
    pla
    tay
    lda MOUCOUNT
    pha
    lda #0
    beq INITBANK_SYNC
    .byte $FF

.assert * == $C470
BANK2_SWITCH:
    lda PIADATAB,y
    and #$F1
    ora MOUBANK-CN,x
    sta PIADATAB,y
    pla
    bmi BANK2_RETURN
    beq INITBANK
;; Goes back to bank 0, done.
BANK2_DONE:
    lda #0
    sta MOUBANK-CN,x
    pha
    beq BANK2_SWITCH
BANK2_RETURN:
    rts
INITBANK_SEND_1:
    bne INITBANK_SEND

;; Shows the cleared page with its two marks, and reads the sync latch, in a loop timed to the cycle, until bit 0
;; of the latched video byte is 0, or a 24-bit count runs out.
INITBANK_SYNC:
    lda #$01
    sta HGRMARK1
    sta HGRMARK2
    lda HIRES
    lda LOWSCR
    lda MIXCLR
    lda TXTCLR
    nop
    sta MOUPTR                      ; the counter starts from what the switch's read left in A
    sta MOUPTR+1
    sta MOUCOUNT
INITBANK_SYNC_1:
    inc MOUPTR
    bne INITBANK_SYNC_2
    inc MOUPTR+1
    bne INITBANK_SYNC_3
    inc MOUCOUNT
    lda MOUCOUNT
    cmp #$01
    bcc INITBANK_SYNC_4
    bcs INITBANK_SYNC_5             ; given up
INITBANK_SYNC_2:
    php                             ; timing
    plp
INITBANK_SYNC_3:
    php
    plp
    lda #0
    lda LOC0
INITBANK_SYNC_4:
    lda CLRROM                      ; the read latches the video byte's bit 0
    lda PIADATAB,y
    lsr a
    nop
    nop
    bcs INITBANK_SYNC_1
    lda CLRROM
    lda PIADATAB,y
    lsr a
    lda LOC0
    nop
    bcs INITBANK_SYNC_1
INITBANK_SYNC_5:
    pla
    sta MOUCOUNT
    pla
    sta MOUPTR+1
    pla
    sta MOUPTR
    lda #<(INITBANK_TEXT-1)
    bne INITBANK_SEND_1
INITBANK_TEXT:
    lda TXTSET
    lda LORES
    clc
    bcc BANK2_DONE
    .res 18, $FF
    .byte $C1
.assert * == $C500

; Bank 3: sends one command byte, and for SERVEMOUSE reads the interrupt status back.
.logicalorg $C400

;; Sends MOUARG's command. For $20 it reads the answer and merges its bits 1-3 into MOUSTAT; for $30 it clears the
;; position's holes.
;; In:    MOUARG = the command, X = $Cn, Y = $n0
;; Out:   carry = clear, or set when $20 finds no interrupt (as it returns to bank 0)
SENDBANK:
    lda MOUARG-CN,x
    cmp #$20
    bne SENDBANK_1
    lda #$7F
    adc #$01                        ; overflow set: an answer to read
    bvs SENDBANK_2
SENDBANK_1:
    clv
SENDBANK_2:
    lda PIADATAB,y
    bmi SENDBANK_2                  ; wait until the microcontroller is free
    lda PIACTLA,y
    and #<~DATAREG
    sta PIACTLA,y
    lda #$FF
    sta PIADATAA,y                  ; port A out
    lda PIACTLA,y
    ora #DATAREG
    sta PIACTLA,y
    lda MOUARG-CN,x
    sta PIADATAA,y
    lda PIADATAB,y
    ora #STROBE
    sta PIADATAB,y
SENDBANK_3:
    lda PIADATAB,y
    bpl SENDBANK_3                  ; wait until it takes the byte
    and #<~STROBE
    sta PIADATAB,y
    bvs SENDBANK_READ
    lda MOUARG-CN,x
    cmp #$30
    bne BANK3_DONE
    lda #0
    sta MOUXH-CN,x
    sta MOUXL-CN,x
    sta MOUYH-CN,x
    sta MOUYL-CN,x
    beq BANK3_DONE
    .res 23, $FF

.assert * == $C470
BANK3_SWITCH:
    lda PIADATAB,y
    and #$F1
    ora MOUBANK-CN,x
    sta PIADATAB,y
    pla
    beq SENDBANK
;; Goes back to bank 0, done.
BANK3_DONE:
    lda #0
    sta MOUBANK-CN,x
    pha
    beq BANK3_SWITCH

;; Reads the interrupt status and merges it into MOUSTAT.
SENDBANK_READ:
    lda PIACTLA,y
    and #<~DATAREG
    sta PIACTLA,y
    lda #$00
    sta PIADATAA,y                  ; port A in
    lda PIACTLA,y
    ora #DATAREG
    sta PIACTLA,y
SENDBANK_READ_1:
    lda PIADATAB,y
    asl a
    bpl SENDBANK_READ_1             ; wait for the byte
    lda PIADATAA,y
    sta MOUARG-CN,x
    lda PIADATAB,y
    ora #ACK
    sta PIADATAB,y
SENDBANK_READ_2:
    lda PIADATAB,y
    asl a
    bmi SENDBANK_READ_2             ; wait until it sees the acknowledgment
    lda PIADATAB,y
    and #<~ACK
    sta PIADATAB,y
    lda MOUSTAT-CN,x
    and #$F1
    ora MOUARG-CN,x
    sta MOUSTAT-CN,x
    and #$0E
    bne BANK3_DONE                  ; the mouse's interrupt
    lda #0
    sta MOUBANK-CN,x
    lda #2                          ; not the mouse's: carry set
    pha
    bne BANK3_SWITCH
    .res 41, $FF
    .byte $C3
.assert * == $C500

; Bank 4: BASIC's IN# and PR#.
.logicalorg $C400

;; From $Cn00: output when CSW points at the card and has not been moved to $Cn07 yet, else input when KSW points at
;; it, else output. It moves the hook it finds to $Cn07 or $Cn05.
;; In:    X = $Cn, Y = $n0, the stack = the character
BASICHOOK:
    cpx CSWH
    bne BASICHOOK_1
    lda #<BASICOUT
    cmp CSWL
    beq BASICHOOK_1
    sta CSWL
;; Output: a return is ignored; any other character turns the mouse on with an odd code and off with an even one,
;; as CHR$(1) and CHR$(0) do, and puts it in BASIC mode.
BASICPUT:
    pla
    cmp #$8D
    beq BANK4_DONE
    and #$01
    ora #$80
    sta MOUMODE-CN,x
    txa
    pha
    lda #<(BANK4_DONE-1)
    pha
    lda MOUMODE-CN,x
    lsr a
    lda #$80                        ; on
    bcs BASICPUT_1
    asl a                           ; off
BASICPUT_1:
    pha
    lda #6*2                        ; send through bank 6
    sta MOUBANK-CN,x
    lda #0
    pha
    beq BANK4_SWITCH

BASICHOOK_1:
    cpx KSWH
    bne BASICPUT
    lda #<BASICIN
    sta KSWL
;; Input: reads the mouse, if it is on, and writes the line through bank 5. With the mouse off the position is 0, 0
;; and the status $C0.
BASICGET:
    lda MOUMODE-CN,x
    and #$01
    bne BASICGET_1
    pla                             ; the character, and BASICCALL's X, Y and A
    pla
    pla
    pla
    lda #0
    sta MOUXL-CN,x
    sta MOUXH-CN,x
    sta MOUYL-CN,x
    sta MOUYH-CN,x
    beq BASICGET_OFF
BASICGET_1:
    lda MOUMODE-CN,x
    and #$01
    ora #$80                        ; BASIC mode, which also brings bank 6 back here
    sta MOUMODE-CN,x
    txa
    pha
    lda #<(BASICGET_READ-1)
    pha
    lda #$10                        ; read status, Y and X
    pha
    lda #6*2
    bne BASICGET_BANK
    .res 6, $FF

.assert * == $C470
BANK4_SWITCH:
    lda PIADATAB,y
    and #$F1
    ora MOUBANK-CN,x
    sta PIADATAB,y
    pla
    bmi BANK4_RETURN
    beq BASICHOOK                   ; 0: from $Cn00
    ror a
    bcs BASICPUT                    ; 1: output
    bcc BASICGET                    ; 2: input
;; Goes back to bank 0 with entry code 1, which puts back BASICCALL's registers.
BANK4_DONE:
    lda #0
    sta MOUBANK-CN,x
    lda #1
    pha
    bne BANK4_SWITCH
BANK4_RETURN:
    rts

BASICGET_OFF:
    lda #$C0
    sta MOUSTAT-CN,x
;; Writes the line through bank 5.
BASICGET_LINE:
    sty SAVEY
    lda #5*2
BASICGET_BANK:
    sta MOUBANK-CN,x
    lda #0
    pha
    beq BANK4_SWITCH

;; After command $10: reads the five bytes into MOUSTAT, MOUYH, MOUYL, MOUXH and MOUXL.
BASICGET_READ:
    pla                             ; the character, and BASICCALL's X, Y and A
    pla
    pla
    pla
    lda #5
    sta MOUARG-CN,x
    lda PIACTLA,y
    and #<~DATAREG
    sta PIACTLA,y
    lda #$00
    sta PIADATAA,y                  ; port A in
    lda PIACTLA,y
    ora #DATAREG
    sta PIACTLA,y
BASICGET_READ_1:
    lda PIADATAB,y
    asl a
    bpl BASICGET_READ_1
    lda PIADATAA,y
    pha
    lda PIADATAB,y
    ora #ACK
    sta PIADATAB,y
BASICGET_READ_2:
    lda PIADATAB,y
    asl a
    bmi BASICGET_READ_2
    lda PIADATAB,y
    and #<~ACK
    sta PIADATAB,y
    dec MOUARG-CN,x
    bne BASICGET_READ_1
    pla
    sta MOUSTAT-CN,x
    pla
    sta MOUYH-CN,x
    pla
    sta MOUYL-CN,x
    pla
    sta MOUXH-CN,x
    pla
    sta MOUXL-CN,x
    clc
    bcc BASICGET_LINE
    .byte $FF, $FF, $FF, $C8
.assert * == $C500

; Bank 5: BASIC's "X,Y,B" line.
.logicalorg $C400

;; Writes "+XXXXX,+YYYYY,+BB" and a return into IN ($0200-$0211), each number signed and in decimal, and returns
;; the return with X = $11, the line's length, as GETLN would; so INPUT reads it, and nothing is echoed. B is 1 for
;; the button down and down at the last read, 2 pressed since, 3 released since and 4 up; negative when a key waits.
;; In:    X = $Cn, MSLOT = $Cn, SAVEY = Y
;; Out:   (through bank 0) A = $8D, X = Y = $11
BASICLINE:
    txa
    pha
    pha
    pha
    lda #<(BASICLINE_1-1)
    pha
    ldy MOUXL-CN,x
    lda MOUXH-CN,x
    tax
    tya
    ldy #5                          ; X's last digit, at IN+5
    bne SIGNED
BASICLINE_1:
    ldx MSLOT
    lda #<(BASICLINE_2-1)
    pha
    ldy MOUYL-CN,x
    lda MOUYH-CN,x
    tax
    tya
    ldy #12                         ; Y's last digit
    bne SIGNED
BASICLINE_2:
    ldx MSLOT
    lda #<(BASICLINE_3-1)
    pha
    lda KBD
    asl a
    php                             ; carry: a key is waiting
    lda MOUSTAT-CN,x
    rol a
    rol a
    rol a
    and #$03                        ; button now, button before
    eor #$03
    sec
    adc #$00                        ; 1 down and down, 2 pressed, 3 released, 4 up
    plp
    ldx #0
    ldy #16                         ; the button's last digit
    bne DECIMAL
BASICLINE_3:
    lda #$8D
    sta IN+$11
    pha                             ; A
    lda #$11
    pha                             ; Y
    pha                             ; X
    lda #0
    beq BASICLINE_DONE
    .res 18, $FF

;; Goes back to bank 0 with entry code 1, which returns the A, Y and X just pushed.
BASICLINE_DONE:
    ldx MSLOT
    ldy SAVEY
    sta MOUBANK-CN,x
    lda #1
    pha
.assert * == $C470
BANK5_SWITCH:
    lda PIADATAB,y
    and #$F1
    ora MOUBANK-CN,x
    sta PIADATAB,y
    pla
    bmi BANK5_RETURN
    beq BASICLINE

;; Writes a signed number, sign first, then five digits ending at IN+Y, then a comma after it.
;; In:    X/A = the number, high/low, Y = the place of its last digit
SIGNED:
    cpx #$80
    bcc DECIMAL
    eor #$FF                        ; negative: carry is set, so this adds one
    adc #$00
    pha
    txa
    eor #$FF
    adc #$00
    tax
    pla
    sec
;; Writes a number's digits, from IN+Y down to the place after a sign, then the sign and a comma after the digits.
;; In:    X/A = the number, high/low, Y = the place of its last digit, carry = set for a minus sign
DECIMAL:
    sta NUMBERL
    stx NUMBERH
    lda #'+'+$80
    bcc DECIMAL_1
    lda #'-'+$80
DECIMAL_1:
    pha
    lda #','+$80
    sta IN+1,y
DECIMAL_2:
    ldx #17
    lda #0
    clc
DECIMAL_3:
    rol a                           ; divide NUMBERH/NUMBERL by 10, the remainder in A
    cmp #10
    bcc DECIMAL_4
    sbc #10
DECIMAL_4:
    rol NUMBERL
    rol NUMBERH
    dex
    bne DECIMAL_3
    ora #'0'+$80
    sta IN,y
    dey
    beq DECIMAL_5
    cpy #7
    beq DECIMAL_5
    cpy #14
    bne DECIMAL_2
DECIMAL_5:
    pla
    sta IN,y                        ; the sign
BANK5_RETURN:
    rts
    .res 50, $FF
    .byte $CD
.assert * == $C500

; Bank 6: sends or receives one byte, and READMOUSE.
.logicalorg $C400

;; Sends the byte on the stack, then returns to the bank in MOUMODE's upper nibble, or to bank 0.
;; In:    the stack = the byte, X = $Cn, Y = $n0
SENDBYTE:
    clv
    bvc SENDBYTE_1

;; READMOUSE: when the mouse is on, sends command $10 and reads the five bytes into the holes.
READBANK:
    lda MOUMODE-CN,x
    and #$01
    beq BANK6_BANK                  ; off: back to bank 0
    lda #$10
    pha
    lda #5
    sta MOUARG-CN,x
    lda #$7F
    adc #$01                        ; overflow set: an answer to read
SENDBYTE_1:
    lda PIADATAB,y
    bmi SENDBYTE_1
    lda PIACTLA,y
    and #<~DATAREG
    sta PIACTLA,y
    lda #$FF
    sta PIADATAA,y                  ; port A out
    lda PIACTLA,y
    ora #DATAREG
    sta PIACTLA,y
    pla
    sta PIADATAA,y
    lda PIADATAB,y
    ora #STROBE
    sta PIADATAB,y
SENDBYTE_2:
    lda PIADATAB,y
    bpl SENDBYTE_2
    and #<~STROBE
    sta PIADATAB,y
    bvs READBYTES
;; Returns to the bank in MOUMODE's upper nibble, through the address its caller pushed, or to bank 0.
BANK6_BACK:
    bvs BANK6_BANK
    lda MOUMODE-CN,x
    lsr a
    lsr a
    lsr a
    lsr a
BANK6_BANK:
    clv
    sta MOUBANK-CN,x
    beq BANK6_BANK_1
    lda #$80                        ; another bank: return through the stack
BANK6_BANK_1:
    pha
    bvc BANK6_SWITCH
    .res 20, $FF

.assert * == $C470
BANK6_SWITCH:
    lda PIADATAB,y
    and #$F1
    ora MOUBANK-CN,x
    sta PIADATAB,y
    pla
    beq SENDBYTE                    ; 0: send
    cmp #$02
    beq READBANK                    ; 2: READMOUSE
    bne RECEIVEBYTE                 ; 1: receive
BANK6_BACK_1:
    beq BANK6_BACK

;; Receives a byte into MOUARG; READMOUSE, with overflow set, receives MOUARG's count onto the stack instead.
RECEIVEBYTE:
    clv
READBYTES:
    lda PIACTLA,y
    and #<~DATAREG
    sta PIACTLA,y
    lda #$00
    sta PIADATAA,y                  ; port A in
    lda PIACTLA,y
    ora #DATAREG
    sta PIACTLA,y
READBYTES_1:
    lda PIADATAB,y
    asl a
    bpl READBYTES_1
    lda PIADATAA,y
    bvs READBYTES_2
    sta MOUARG-CN,x
    bvc READBYTES_3
READBYTES_2:
    pha
READBYTES_3:
    lda PIADATAB,y
    ora #ACK
    sta PIADATAB,y
READBYTES_4:
    lda PIADATAB,y
    asl a
    bmi READBYTES_4
    lda PIADATAB,y
    and #<~ACK
    sta PIADATAB,y
    bvc READBYTES_5
    dec MOUARG-CN,x
    bne READBYTES_1
    pla
    sta MOUSTAT-CN,x
    pla
    sta MOUYH-CN,x
    pla
    sta MOUYL-CN,x
    pla
    sta MOUXH-CN,x
    pla
    sta MOUXL-CN,x
READBYTES_5:
    lda #0
    beq BANK6_BACK_1
    .res 29, $FF
    .byte $C1
.assert * == $C500

; Bank 7: a command with its parameters.
.logicalorg $C400

;; Sends MOUARG's command and its parameters: for $40 the slot's MOUXL, MOUXH, MOUYL and MOUYH; for $60 and $61 slot
;; 0's MOUXL, MOUYL, MOUXH and MOUYH; for $A0 the caller's A; for the factory's $9x and $Bx none to three of slot 0's
;; MOUXL, MOUYL and MOUXH, as bits 2 and 3 say.
;; In:    MOUARG = the command, X = $Cn, Y = $n0
PARAMBANK:
    lda MOUARG-CN,x
    cmp #$40
    beq PARAMBANK_POS
    cmp #$60
    beq PARAMBANK_CLAMP
    cmp #$61
    beq PARAMBANK_CLAMP
    cmp #$A0
    bne PARAMBANK_OTHER
    pha
    lda #2
    bne PARAMBANK_SEND
PARAMBANK_CLAMP:
    lda MOUYH
    pha
    lda MOUXH
    pha
    lda MOUYL
    pha
    lda MOUXL
    bcs PARAMBANK_COMMAND
PARAMBANK_POS:
    lda MOUYH-CN,x
    pha
    lda MOUYL-CN,x
    pha
    lda MOUXH-CN,x
    pha
    lda MOUXL-CN,x
PARAMBANK_COMMAND:
    pha
    lda MOUARG-CN,x
    pha
    lda #5
    bne PARAMBANK_SEND
PARAMBANK_OTHER:
    and #$0C
    lsr a
    lsr a
    lsr a
    bcs PARAMBANK_OTHER_3
    lsr a
    bcc PARAMBANK_OTHER_1
    lda MOUXH
    pha
    lda MOUARG-CN,x
    pha
    lda #2
    bne PARAMBANK_SEND
PARAMBANK_OTHER_1:
    lda MOUARG-CN,x
    pha
    lda #1
;; Sends A bytes from the stack.
PARAMBANK_SEND:
    sta MOUARG-CN,x
    bne SENDBYTES
    .res 14, $FF

.assert * == $C470
BANK7_SWITCH:
    lda PIADATAB,y
    and #$F1
    ora MOUBANK-CN,x
    sta PIADATAB,y
    pla
    bne PARAMBANK
;; Goes back to bank 0, done.
BANK7_DONE:
    lda #0
    sta MOUBANK-CN,x
    pha
    beq BANK7_SWITCH

PARAMBANK_OTHER_3:
    lsr a
    bcs PARAMBANK_OTHER_4
    lda MOUYL
    pha
    lda MOUXL
    pha
    lda MOUARG-CN,x
    pha
    lda #3
    sta MOUARG-CN,x
    bne SENDBYTES
PARAMBANK_OTHER_4:
    lda MOUXH
    pha
    lda MOUYL
    pha
    lda MOUXL
    pha
    lda MOUARG-CN,x
    pha
    lda #4
    sta MOUARG-CN,x

;; Sends MOUARG's count of bytes from the stack, then goes back to bank 0.
SENDBYTES:
    lda PIADATAB,y
    bmi SENDBYTES
    lda PIACTLA,y
    and #<~DATAREG
    sta PIACTLA,y
    lda #$FF
    sta PIADATAA,y                  ; port A out
SENDBYTES_1:
    lda PIACTLA,y
    ora #DATAREG
    sta PIACTLA,y
    pla
    sta PIADATAA,y
    lda PIADATAB,y
    ora #STROBE
    sta PIADATAB,y
SENDBYTES_2:
    lda PIADATAB,y
    bpl SENDBYTES_2
    and #<~STROBE
    sta PIADATAB,y
    dec MOUARG-CN,x
    beq BANK7_DONE
SENDBYTES_3:
    lda PIADATAB,y
    bmi SENDBYTES_3
    bpl SENDBYTES_1
    .res 18, $FF
    .byte $CE
.assert * == $C500
