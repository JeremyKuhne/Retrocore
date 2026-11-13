;; SOS .RS232 DRIVER 1.30
;;
;; The SOS character device driver for the Apple III's built-in serial port, a 6551 ACIA at $C0F0-$C0F3. SOS loads
;; it from SOS.DRIVER and calls it through the entry point in its device information block, <RS_MAIN>, with the
;; request in SOS's driver parameters at $C0-$C9.
;;
;; Data moves through two 256-byte ring buffers, one each way, and the ACIA's interrupt handler, <ACIAMIH>, does
;; the transfers: a received character goes into the input buffer (<RS_IN>), and while the transmitter is empty and
;; output is waiting, the next character goes out (<RS_OUT>). A write only fills the output buffer and turns on the
;; transmit interrupt (<PRIME_OUT>); a read takes characters from the input buffer, waiting for them unless read
;; immediate is on. After a carriage return, line feed or form feed the handler can hold off the next character for
;; a number of interrupts. Flow control is one of three kinds, chosen in the configuration:
;;
;; - XON/XOFF: a received XOFF stops output and XON restarts it; when the input buffer fills to a high-water mark
;;   the driver sends XOFF, and once a read drains it to a low-water mark, XON.
;; - ENQ/ACK: after a set number of characters the driver sends ENQ and stops until an ACK comes back.
;; - Hardware: the driver drops RTS at the input high-water mark and raises it at the low-water mark, and stops
;;   transmitting while DSR or DCD is false.
;;
;; Requests (see <RS_REQSW>):
;;
;; - 0, read (<RS_READ>), and 1, write (<RS_WRITE>): any number of bytes; a read can end at a newline character.
;; - 2, status (<RS_STAT>): code 0 does nothing, 1 returns the control parameters with the latched line errors,
;;   2 the newline mode and character, and 3 the two buffers' sizes and counts.
;; - 3, control (<RS_CNTL>): code 0 resets the port, 1 sets the control parameters, 2 the newline mode and
;;   character, and 3 sends a break.
;; - 6, open (<RS_OPEN>), and 7, close (<RS_CLOSE>): claim the ACIA's interrupt and set the port up, or wait for
;;   output to finish and give the interrupt back.
;; - 8, initialize (<RS_INIT>): marks the port closed.
;; - 4 and 5 are refused as bad requests.
;;
;; The driver has one device, .RS232 (<IDBLK>). Its configuration block, <DCB>, holds the defaults the System
;; Configuration Program can change: 300 baud, seven data bits with odd parity, no delays and no flow control. Open
;; copies them into the control parameters (<CNTL_PARAM>), which control requests can change. Its comment record,
;; <DRIVER_COMMENT>, comes first; SOS.DRIVER keeps it apart from the code, whose addresses count from the device
;; information block.
;;
;; Labels follow Apple's listing of the driver, "Apple /// RS-232 Serial Port Driver 1.30 Source Code Listing"
;; (https://www.apple3.org/Documents/SourceCode/Apple%203%20RS232%20Driver.pdf), and the comments are our own. Labels
;; inside routines that the listing leaves to local labels are named after the routine (<RS_READ_099>).
;;
;; Maintained by hand; SOS driver tests check it assembles byte-identically to Apple's .RS232 1.30.

.cpu Mos6502

;; The device type in the device information block: a character device that reads and writes.
DEVTYPE = $63

;; The device subtype in the device information block.
SUBTYPE = $01

;; The manufacturer in the device information block: 1 for Apple.
MANID = $01

;; The driver's release, 1.30, as SOS reports it.
RELEASE = $1300

;; Jumps to the routine a table gives for an index: the table holds each routine's address minus one, and the
;; jump is an RTS to the address it pushes.
;;
;; When the index is out of range the macro falls through to the code after it. A fourth argument of * leaves
;; out the RTS, so the code after the macro makes the jump.
;; Parameters:
;;   p1 = the index, loaded into A first when given
;;   p2 = the highest index, checked when given
;;   p3 = the table of addresses minus one
;;   p4 = * to leave the jump to the code that follows
;; Uses: A, Y
.macro SWITCH p1, p2, p3, p4, p5, p6
    .local M010
    .ifnblank p1
    lda p1
    .endif
    .ifnblank p2
    cmp #<(p2+$01)
    bcs M010
    .endif
    asl a
    tay
    lda p3+$01,y
    pha
    lda p3,y
    pha
    .if .not .xmatch({p4}, {*})
    rts
    .endif
M010:
.endmacro

;; Adds one to a 16-bit count.
;; Parameters:
;;   p1 = the count's low byte; the high byte follows it
.macro INW p1, p2, p3, p4, p5, p6
    .local M210
    inc p1
    bne M210
    inc p1+$01
M210:
.endmacro

;; Steps a SOS extended-address buffer pointer in zero page to the next byte.
;;
;; When the pointer's high byte passes $FF it starts again at $80, and the bank byte that goes with the pointer, at
;; its address + $1401, goes up by one, so the pointer moves on into the next bank.
;; Parameters:
;;   p1 = the pointer's low byte
.macro INCADR p1, p2, p3, p4, p5, p6
    .local M310
    inc p1
    bne M310
    inc p1+$01
    bne M310
    sec
    ror p1+$01
    inc p1+$01+$1400
M310:
.endmacro

;; Slows the machine to 1 MHz, as the ACIA needs.
;; Uses: A
.macro SET_1MHZ p1, p2, p3, p4, p5, p6
    lda E_REG
    ora #<BITON7
    sta E_REG
.endmacro

;; Returns the machine to 2 MHz.
;; Uses: A
.macro SET_2MHZ p1, p2, p3, p4, p5, p6
    lda E_REG
    and #$7F
    sta E_REG
.endmacro

; ---------------------------------------------------------------------------------------------------------------------
; SOS calls, errors and hardware
; ---------------------------------------------------------------------------------------------------------------------

ALLOCSIR = $1913                    ;; SOS's call that claims interrupt resources for a driver
DEALCSIR = $1916                    ;; SOS's call that gives interrupt resources back
SYSERR = $1928                      ;; SOS's call that ends a request with the error code in A; it does not return

XREQCODE = $20                      ;; error: the request code is not one the driver takes
XCTLCODE = $21                      ;; error: the control or status code is not one the driver takes
XCTLPARM = $22                      ;; error: the control or status list is the wrong length
XNOTOPEN = $23                      ;; error: the port is not open
XNOTAVIL = $24                      ;; error: the port is already open
XNORESRC = $25                      ;; error: the ACIA's interrupt belongs to another driver
XBADOP = $26                        ;; error: the operation is not one the device does

ACIADATA = $C0F0                    ;; the ACIA's data register: received characters in, characters to send out
ACIASTAT = $C0F1                    ;; the ACIA's status register; writing it resets the ACIA

;; The ACIA's command register. Bits 7-5: the parity; 4: echo; 3-2: the transmitter, 00 for RTS false with its
;; interrupt off, 01 for RTS true with its interrupt on, 10 for RTS true with it off, 11 for a break; 1: set to turn
;; the receive interrupt off; 0: DTR true and the receiver on.
ACIACMD = $C0F2

;; The ACIA's control register. Bit 7: two stop bits; 6-5: the word length, 8 bits less their value; 4: the internal
;; receive clock; 3-0: the baud rate, 6 for 300 baud, 3 for 110, up to $F for 19,200.
ACIACTL = $C0F3

;; The environment register. Bit 7 set runs the machine at 1 MHz.
E_REG = $FFDF

;; The bank register: which bank of memory is at $2000-$9FFF.
B_REG = $FFEF

TRUE = $80                          ;; a flag that is on: bit 7 set
FALSE = $00                         ;; a flag that is off
BITON0 = $01                        ;; bit 0 alone
BITON1 = $02                        ;; bit 1 alone
BITON2 = $04                        ;; bit 2 alone
BITON3 = $08                        ;; bit 3 alone
BITON4 = $10                        ;; bit 4 alone
BITON6 = $40                        ;; bit 6 alone
BITON7 = $80                        ;; bit 7 alone
ASC_LF = $0A                        ;; line feed
ASC_FF = $0C                        ;; form feed
ASC_CR = $0D                        ;; carriage return

; ---------------------------------------------------------------------------------------------------------------------
; Comment record and device information block
; ---------------------------------------------------------------------------------------------------------------------

;; The driver's comment record: $FFFF, the text's length and the text, which SOS.DRIVER keeps apart from the code.
DRIVER_COMMENT:
    .word $FFFF
    .word DRIVER_COMMENT_END - DRIVER_COMMENT - 4
    .byte "(C) Apple Computer 1981, 1982, 1983.  "
    .byte "Built-in Serial Port RS-232 Driver."
DRIVER_COMMENT_END:
    .logicalorg * - (DRIVER_COMMENT_END - DRIVER_COMMENT)

;; The device information block for .RS232: the link to the next device's block (none), the entry point, the name's
;; length and the name, the device number, slot and unit, the type and subtype, a reserved byte, the block count
;; (none for a character device), the manufacturer and the release.
;; See: <CNFGBLK>
IDBLK:
    .word $00
    .word RS_MAIN
    .byte $06
    .byte ".RS232         "
    .byte $80, $00, $00
    .byte DEVTYPE
    .byte SUBTYPE
    .byte $00
    .word $00
    .word MANID
    .word RELEASE

;; The configuration block's length, which the System Configuration Program reads before the block itself.
CNFGBLK:
    .word 12

;; The configuration block: the defaults that open copies into the control parameters, from <BAUD> through
;; <HDW_HSHAKE>, in the same order.
;; See: <RS_OPEN>
DCB:
    .byte $06                       ; 300 baud
    .byte $22                       ; seven data bits, odd parity, one stop bit
    .byte $00                       ; no delay after a carriage return
    .byte $00                       ; no delay after a line feed
    .byte $00                       ; no delay after a form feed
    .byte $00                       ; no flow control
    .byte $13                       ; XOFF, Control-S
    .byte $11                       ; XON, Control-Q
    .byte 223                       ; the input high-water mark
    .byte 132                       ; the input low-water mark
    .byte 80                        ; characters between ENQs
    .byte $00                       ; no hardware handshake

;; The configuration block's length.
DCB_LN = *-DCB

    .byte "(C) Apple Computer Inc. 1983"

; ---------------------------------------------------------------------------------------------------------------------
; SOS's driver parameters and the driver's zero page
; ---------------------------------------------------------------------------------------------------------------------

;; Where SOS puts a request's parameters for its driver.
SOSINT = $C0

REQCODE = SOSINT+$00                ;; the request code
BUFFER = SOSINT+$02                 ;; read and write: the caller's buffer, an extended address
REQCNT = SOSINT+$04                 ;; read and write: the number of bytes asked for
CTLSTAT = SOSINT+$02                ;; status and control: the code
CSLIST = SOSINT+$03                 ;; status and control: the caller's list, an extended address
RETPTR = SOSINT+$08                 ;; read: where to put the number of bytes read
ZPGSAVE = SOSINT+$0A                ;; the zero page a driver may use
ZPGTEMP = ZPGSAVE+$00               ;; the first of those bytes

OPRODPTR = $E1                      ;; a write's place in the output buffer, kept here while it runs
ICSMRPTR = $E2                      ;; a read's place in the input buffer, kept here while it runs
RETCNT = $E3                        ;; the number of bytes a read has returned (two bytes)

; ---------------------------------------------------------------------------------------------------------------------
; The driver's variables
; ---------------------------------------------------------------------------------------------------------------------

;; The address of <SIRTABLE>, for <ALLOCSIR> and <DEALCSIR>.
SIRADDR:
    .word SIRTABLE

;; The interrupt resource the driver claims: resource 1, the ACIA, with <ACIAMIH> as its handler, in the bank
;; <MIHBANK> holds.
SIRTABLE:
    .byte $01, $00
    .word ACIAMIH

;; The bank the interrupt handler runs in, the bank the driver was loaded in.
MIHBANK:
    .byte $00

;; The length of <SIRTABLE>.
SIRCOUNT = *-SIRTABLE

;; Bit 7 set while the port is open.
OPENFLG:
    .byte FALSE

;; Bit 7 set when a read ends at <NEWLINE>.
IS_NEWLINE:
    .byte FALSE

;; The character that ends a read in newline mode.
NEWLINE:
    .byte $00

;; XOFF state. Bit 7: XOFF has gone out, and XON must follow; bit 6: XOFF must go out.
IN_PROG:
    .byte $00

;; Bit 7 set when XON must go out.
SEND_XON:
    .byte $00

;; Bit 7 set while the hardware handshake holds RTS false.
RTS_FALSE:
    .byte $00

;; Bit 7 set while a received XOFF has stopped output.
NO_OUTPUT:
    .byte $00

;; Interrupts to let pass before the next character goes out, after a carriage return, line feed or form feed.
DLYCNT:
    .byte $00

;; Intervals left while a break is sent; nonzero holds the output.
BRK_CNT:
    .byte $00

;; Characters left to send before the next ENQ.
CHAR_OUT:
    .byte $00

;; Bit 7 set while an ENQ waits for its ACK.
IN_PROG1:
    .byte $00

;; The control parameters, as status and control code 1 read and write them. This first byte is their length less
;; this byte, 15; control code 1 writes the 13 that follow it up to <RD_IMMEDIATE>.
;; See: <STAT01>, <CNTL01>
CNTL_PARAM:
    .byte 15

;; The baud rate, the low four bits of <ACIACTL>.
BAUD:
    .byte $00

;; The data format. The high three bits go to <ACIACTL>'s stop bits and word length, and bits 3-1 to
;; <ACIACMD>'s parity.
DFORMAT:
    .byte $00

;; Interrupts to wait after sending a carriage return.
CRDELAY:
    .byte $00

;; Interrupts to wait after sending a line feed.
LFDELAY:
    .byte $00

;; Interrupts to wait after sending a form feed.
FFDELAY:
    .byte $00

;; The flow control: bit 7 for XON/XOFF, bit 6 for ENQ/ACK, neither for none.
PROTOCOL:
    .byte $00

;; The XOFF character, or ENQ.
CTLCHR1:
    .byte $00

;; The XON character, or ACK.
CTLCHR2:
    .byte $00

;; The input count at which the driver sends XOFF, or drops RTS.
MAXBUF:
    .byte $00

;; The input count at which a read sends XON, or raises RTS.
MINBUF:
    .byte $00

;; The number of characters to send between ENQs.
CHARCNT:
    .byte $00

;; Bit 7 set for the hardware handshake on RTS, DSR and DCD.
HDW_HSHAKE:
    .byte $00

;; Bit 7 set when a read returns what the input buffer holds instead of waiting for the count.
RD_IMMEDIATE:
    .byte $00

;; The ACIA's status at the last interrupt.
STAT_REG:
    .byte $00

;; Line conditions since status code 1 or a reset last cleared them. Bit 0: a parity error; 1: a framing error;
;; 2: an overrun; 5: DCD false; 6: DSR false; 7: a character lost to a full input buffer.
STAT_LATCH:
    .byte $00

;; The length of the control parameters, <CNTL_PARAM> through <STAT_LATCH>.
CNTL_LN = *-CNTL_PARAM

;; The number of characters in the output buffer.
OBUFCNT:
    .byte $00

;; Where the next character written goes in the output buffer, between writes.
OSPRODPTR:
    .byte $00

;; Where the next character to send is in the output buffer.
OCSMRPTR:
    .byte $00

;; The output ring buffer.
OLOCBUF:
    .res $0100, $00

;; The number of characters in the input buffer.
IBUFCNT:
    .byte $00

;; Where the next character to read is in the input buffer, between reads.
ISCSMRPTR:
    .byte $00

;; Where the next character received goes in the input buffer.
IPRODPTR:
    .byte $00

;; The input ring buffer.
ILOCBUF:
    .res $0100, $00

; ---------------------------------------------------------------------------------------------------------------------
; Requests
; ---------------------------------------------------------------------------------------------------------------------

;; The driver's entry point: carries out the request in <REQCODE>.
;; In: REQCODE = the request, with its parameters at <SOSINT>
;; Errors: XREQCODE = a request the driver does not take, XNOTOPEN = the port is not open
;; See: <RS_REQSW>
RS_MAIN:
    SWITCH REQCODE, $08, RS_REQSW

;; Ends the request with <XREQCODE>.
BADREQ:
    lda #<XREQCODE
    jsr SYSERR

;; Ends the request with <XNOTOPEN>.
NOTOPEN:
    lda #<XNOTOPEN
    jsr SYSERR

;; Each request's routine, less one, by request code: read, write, status, control, two that are refused, open, close
;; and initialize.
RS_REQSW:
    .word RS_READ-$01
    .word RS_WRITE-$01
    .word RS_STAT-$01
    .word RS_CNTL-$01
    .word BADREQ-$01
    .word BADREQ-$01
    .word RS_OPEN-$01
    .word RS_CLOSE-$01
    .word RS_INIT-$01

;; Initialize: marks the port closed, when SOS starts.
;; Out: carry = clear
;; Uses: A
RS_INIT:
    lda #<FALSE
    sta a:OPENFLG
    clc
    rts

;; Open: claims the ACIA's interrupt, copies the configuration block into the control parameters, turns newline mode,
;; read immediate and XON/XOFF state off, and resets the port.
;; Errors: XNOTAVIL = the port is already open, XNORESRC = another driver has the ACIA's interrupt
;; Uses: A, X, Y
;; See: <CNTL00>
RS_OPEN:
    bit a:OPENFLG
    bpl @L010
    lda #<XNOTAVIL
    jsr SYSERR
@L010:
    lda B_REG
    and #$0F
    sta a:MIHBANK
    lda #<SIRCOUNT
    ldx a:SIRADDR
    ldy a:SIRADDR+$01
    jsr ALLOCSIR
    bcs @L020
    ldx #<(DCB_LN-$01)
@L015:
    lda a:DCB,x
    sta a:CNTL_PARAM+$01,x
    dex
    bpl @L015
    lda #$00
    sta a:IS_NEWLINE
    sta a:NEWLINE
    sta a:RD_IMMEDIATE
    sta a:IN_PROG
    sta a:SEND_XON
    jsr CNTL00
    lda #<TRUE
    sta a:OPENFLG
    rts
@L020:
    lda #<XNORESRC
    jsr SYSERR

;; Close: waits for the output buffer to empty and any delay to pass, turns the ACIA's interrupts, DTR and RTS off,
;; and gives the interrupt back.
;; Errors: XNOTOPEN = the port is not open
;; Uses: A, X, Y
RS_CLOSE:
    asl a:OPENFLG
    bcs @L05
    jmp NOTOPEN
@L05:
    lda a:OBUFCNT
    ora a:DLYCNT
    bne @L05
    php
    sei
    SET_1MHZ
    lda ACIACMD
    and #$F0
    sta ACIACMD
    lda ACIASTAT
    plp
    lda #<SIRCOUNT
    ldx a:SIRADDR
    ldy a:SIRADDR+$01
    jsr DEALCSIR
    rts

;; Read: moves characters from the input buffer to the caller's buffer.
;;
;; It waits for each character, unless read immediate is on, when it stops at an empty buffer. In newline mode it
;; stops after the newline character. When taking characters drains the buffer to the low-water mark, it has XON
;; sent if XOFF went out, or raises RTS if the hardware handshake dropped it.
;; In: BUFFER = the caller's buffer, REQCNT = the number of bytes, RETPTR = where to put the number read
;; Errors: XNOTOPEN = the port is not open
;; Uses: A, X, Y, REQCNT, BUFFER, ICSMRPTR, RETCNT
RS_READ:
    bit a:OPENFLG
    bmi RS_READ_005
    jmp NOTOPEN
RS_READ_005:
    lda ISCSMRPTR
    sta ICSMRPTR
    ldy #$00
    sty RETCNT
    sty RETCNT+$01
    lda #$FF
    eor REQCNT
    sta REQCNT
    lda #$FF
    eor REQCNT+$01
    sta REQCNT+$01
RS_READ_010:
    inc REQCNT
    bne RS_READ_015
    inc REQCNT+$01
    beq RS_READ_099
RS_READ_015:
    lda IBUFCNT
    bne RS_READ_020
    bit a:RD_IMMEDIATE
    bpl RS_READ_015
    bmi RS_READ_099
RS_READ_020:
    ldy #$00
    ldx ICSMRPTR
    lda ILOCBUF,x
    sta (BUFFER),y
    pha
    INCADR BUFFER
    inc ICSMRPTR
    dec IBUFCNT
    INW RETCNT
    lda a:MINBUF
    cmp IBUFCNT
    bcc RS_READ_025
    bit a:IN_PROG
    bmi RS_READ_022
    bit a:RTS_FALSE
    bpl RS_READ_025
    php
    sei
    SET_1MHZ
    lda ACIACMD
    and #$F2
    ora #$05
    sta ACIACMD
    lda #$00
    sta a:RTS_FALSE
    SET_2MHZ
    plp
    jmp RS_READ_025
RS_READ_022:
    lda #$80
    sta a:SEND_XON
    jsr PRIME_OUT
RS_READ_025:
    pla
    bit a:IS_NEWLINE
    bpl RS_READ_010
    cmp a:NEWLINE
    beq RS_READ_099
    jmp RS_READ_010
RS_READ_099:
    ldy #$00
    lda ICSMRPTR
    sta ISCSMRPTR
    lda RETCNT
    sta (RETPTR),y
    lda RETCNT+$01
    iny
    sta (RETPTR),y
    rts

;; Write: copies the caller's characters into the output buffer, starting the transmitter whenever the buffer
;; fills and waiting for room, then starts it for the rest.
;; In: BUFFER = the caller's buffer, REQCNT = the number of bytes
;; Errors: XNOTOPEN = the port is not open
;; Uses: A, X, Y, REQCNT, BUFFER, OPRODPTR
;; See: <PRIME_OUT>
RS_WRITE:
    bit a:OPENFLG
    bmi RS_WRITE_005
    jmp NOTOPEN
RS_WRITE_005:
    lda a:OSPRODPTR
    sta OPRODPTR
    lda #$FF
    eor REQCNT
    sta REQCNT
    lda #$FF
    eor REQCNT+$01
    sta REQCNT+$01
RS_WRITE_010:
    inc REQCNT
    bne RS_WRITE_030
    inc REQCNT+$01
    bne RS_WRITE_030
    jsr PRIME_OUT
    lda OPRODPTR
    sta a:OSPRODPTR
    rts
RS_WRITE_030:
    ldx a:OBUFCNT
    inx
    bne RS_WRITE_040
    jsr PRIME_OUT
    jmp RS_WRITE_030
RS_WRITE_040:
    ldy #$00
    lda (BUFFER),y
    INCADR BUFFER
    ldx OPRODPTR
    sta a:OLOCBUF,x
    inc OPRODPTR
    inc a:OBUFCNT
    bne RS_WRITE_010

;; Status: answers the status code in <CTLSTAT>.
;; In: CTLSTAT = the status code, CSLIST = the caller's list
;; Errors: XNOTOPEN = the port is not open, XCTLCODE = a code above 3
;; See: <STATSW>
RS_STAT:
    bit a:OPENFLG
    bmi @L05
    jmp NOTOPEN
@L05:
    SWITCH CTLSTAT, $03, STATSW

;; Ends the request with <XCTLCODE>.
BADCTL:
    lda #<XCTLCODE
    jsr SYSERR

;; Each status code's routine, less one.
STATSW:
    .word STAT00-$01
    .word STAT01-$01
    .word STAT02-$01
    .word STAT03-$01

;; Status code 0: does nothing.
STAT00:
    rts

;; Status code 1: copies the control parameters, <CNTL_PARAM> through <STAT_LATCH>, to the caller's list, then clears
;; the latched line conditions.
;; In: CSLIST = the list, whose first byte is its length, at least 15
;; Errors: XCTLPARM = the list is too short
;; Uses: A, Y
STAT01:
    ldy #$00
    lda (CSLIST),y
    cmp a:CNTL_PARAM
    bcs @L01
    lda #<XCTLPARM
    jsr SYSERR
@L01:
    ldy #<(CNTL_LN-$01)
    php
    sei
@L05:
    lda a:CNTL_PARAM,y
    sta (CSLIST),y
    dey
    bpl @L05
    iny
    sty a:STAT_LATCH
    plp
    rts

;; Status code 2: returns the newline mode, then the newline character.
;; In: CSLIST = the list
;; Uses: A, Y
STAT02:
    ldy #$00
    lda a:IS_NEWLINE
    sta (CSLIST),y
    iny
    lda a:NEWLINE
    sta (CSLIST),y
    rts

;; Status code 3: returns four words: the output buffer's size and count, then the input buffer's.
;; In: CSLIST = the list
;; Uses: A, Y
STAT03:
    ldy #$00
    lda #$FF
    jsr CNTOUT
    lda a:OBUFCNT
    jsr CNTOUT
    lda #$FF
    jsr CNTOUT
    lda IBUFCNT
    jsr CNTOUT
    rts

;; Stores A as a word, its high byte 0, at the next place in the caller's list.
;; In: A = the value, Y = the place, CSLIST = the list
;; Out: Y = the next place
;; Uses: A
CNTOUT:
    sta (CSLIST),y
    iny
    lda #$00
    sta (CSLIST),y
    iny
    rts

;; Control: carries out the control code in <CTLSTAT>.
;; In: CTLSTAT = the control code, CSLIST = the caller's list
;; Errors: XNOTOPEN = the port is not open, XCTLCODE = a code above 3
;; See: <CNTLSW>
RS_CNTL:
    bit a:OPENFLG
    bmi @L05
    jmp NOTOPEN
@L05:
    SWITCH CTLSTAT, $03, CNTLSW
    jmp BADCTL

;; Each control code's routine, less one.
CNTLSW:
    .word CNTL00-$01
    .word CNTL01-$01
    .word CNTL02-$01
    .word CNTL03-$01

;; Control code 0: resets the port.
;;
;; If XOFF went out it sends XON and waits for it to go. Then it empties both buffers, clears the delay, break,
;; handshake, ENQ and latched states, and sets the ACIA up from <BAUD> and <DFORMAT>, with two stop bits at 110 baud,
;; the receiver and its interrupt on, DTR and RTS true and the transmit interrupt off.
;; Uses: A, X
CNTL00:
    bit a:IN_PROG
    bpl @L020
    lda #$80
    sta a:SEND_XON
    jsr PRIME_OUT
@L015:
    bit a:SEND_XON
    bmi @L015
@L020:
    php
    sei
    lda a:BAUD
    and #$0F
    sta a:BAUD
    SET_1MHZ
    lda #$00
    sta IBUFCNT
    sta a:OBUFCNT
    sta a:DLYCNT
    sta a:BRK_CNT
    sta a:OSPRODPTR
    sta a:OCSMRPTR
    sta ISCSMRPTR
    sta IPRODPTR
    sta a:RTS_FALSE
    sta a:NO_OUTPUT
    sta a:CHAR_OUT
    sta a:IN_PROG1
    sta a:STAT_LATCH
    lda ACIASTAT
    sta a:STAT_REG
    lda a:DFORMAT
    and #$E0
    ora #<BITON4
    ora a:BAUD
    ldx #$03
    cpx a:BAUD
    bne @L025
    ora #<BITON7
@L025:
    sta ACIACTL
    lda a:DFORMAT
    asl a
    asl a
    asl a
    asl a
    and #$E0
    ora #$09
    sta ACIACMD
    plp
    rts

;; Control code 1: sets the control parameters, <BAUD> through <RD_IMMEDIATE>, from the caller's list, then resets
;; the port.
;; In: CSLIST = the list, whose first byte is its length, 15
;; Errors: XCTLPARM = the list's length is not 15
;; Uses: A, X, Y
;; See: <CNTL00>
CNTL01:
    ldy #$00
    lda (CSLIST),y
    cmp a:CNTL_PARAM
    beq @L01
    lda #<XCTLPARM
    jsr SYSERR
@L01:
    ldy #<(CNTL_LN-$03)
@L05:
    lda (CSLIST),y
    sta a:CNTL_PARAM,y
    dey
    bpl @L05
    jsr CNTL00
    rts

;; Control code 2: sets the newline mode, then the newline character, from the caller's list.
;; In: CSLIST = the list
;; Uses: A, Y
CNTL02:
    ldy #$00
    lda (CSLIST),y
    sta a:IS_NEWLINE
    iny
    lda (CSLIST),y
    sta a:NEWLINE
    rts

;; Control code 3: waits for the output buffer to empty, then sends a break for 1 to 100 intervals of about 233 ms.
;;
;; A count of 0, or above 100, does nothing. Output and the hardware handshake wait while the break lasts.
;; In: CSLIST = the list, whose first byte is the count
;; Uses: A, X, Y
CNTL03:
@L05:
    lda a:OBUFCNT
    bne @L05
    tay
    lda (CSLIST),y
    bmi @L050
    beq @L050
    cmp #101
    bcs @L050
    sta a:BRK_CNT
    php
    sei
    SET_1MHZ
    lda ACIACMD
    ora #$0C
    sta ACIACMD
    lda #$00
    sta a:RTS_FALSE
    plp
@L010:
    ldy #181
    ldx #$00
@L015:
    dex
    bne @L015
    dey
    bne @L015
    dec a:BRK_CNT
    bne @L010
    jsr PRIME_OUT
@L050:
    rts

; ---------------------------------------------------------------------------------------------------------------------
; The interrupt handler
; ---------------------------------------------------------------------------------------------------------------------

;; The ACIA's interrupt handler: records the status, then receives a character if one has come, or else sends the
;; next one.
;;
;; The status's error bits (parity, framing and overrun, with a receive) and DCD and DSR bits go into <STAT_LATCH>.
;; In: Y = the ACIA's status, read by SOS's interrupt dispatcher
;; Uses: A, X
;; See: <RS_IN>, <RS_OUT>
ACIAMIH:
    sty a:STAT_REG
    tya
    and #<BITON3
    beq @L010
    tya
    and #$67
    ora a:STAT_LATCH
    sta a:STAT_LATCH
    jmp RS_IN
@L010:
    tya
    and #$60
    ora a:STAT_LATCH
    sta a:STAT_LATCH
    jmp RS_OUT

;; Receives a character from the ACIA, then goes on to send one.
;;
;; With XON/XOFF, a received XOFF stops output and XON restarts it, and neither is kept; reaching the high-water
;; mark has XOFF sent. With ENQ/ACK, an ACK lets the next run of characters go. With the hardware handshake, reaching
;; the high-water mark drops RTS, unless a break is being sent. A character that finds the buffer full is lost, and
;; <STAT_LATCH> says so.
;; Uses: A, X
;; See: <RS_OUT>
RS_IN:
    SET_1MHZ
    ldx ACIADATA
    SET_2MHZ
    txa
    bit a:PROTOCOL
    bpl @L016
    cmp a:CTLCHR1
    bne @L010
    lda #<TRUE
    sta a:NO_OUTPUT
    jmp RS_OUT
@L010:
    cmp a:CTLCHR2
    bne @L015
    lda #<FALSE
    sta a:NO_OUTPUT
    beq RS_OUT
@L015:
    ldx IBUFCNT
    cpx a:MAXBUF
    bcc @L020
    bit a:IN_PROG
    bmi @L020
    ldx #<BITON6
    stx a:IN_PROG
    bne @L020
@L016:
    bvc @L017
    cmp a:CTLCHR2
    bne @L020
    lda a:CHARCNT
    sta a:CHAR_OUT
    lda #$00
    sta a:IN_PROG1
    beq RS_OUT
@L017:
    bit a:HDW_HSHAKE
    bpl @L020
    ldx IBUFCNT
    cpx a:MAXBUF
    bcc @L020
    ldx a:BRK_CNT
    bne @L020
    pha
    lda #<BITON7
    sta a:RTS_FALSE
    SET_1MHZ
    lda ACIACMD
    and #$F3
    sta ACIACMD
    SET_2MHZ
    pla
@L020:
    ldx IBUFCNT
    inx
    bne @L025
    lda #<BITON7
    ora a:STAT_LATCH
    sta a:STAT_LATCH
    bmi RS_OUT
@L025:
    ldx IPRODPTR
    sta ILOCBUF,x
    inc IBUFCNT
    inc IPRODPTR

;; Sends the next character if the transmitter is empty, and leaves the transmit interrupt on while there is more to
;; send.
;;
;; Nothing goes out during a break, or while the hardware handshake holds RTS false; with the handshake, DSR or DCD
;; false turns the transmit interrupt off once any delay is over. A pending XOFF or XON goes first, then a delay is
;; counted down, then the output buffer's next character, unless a received XOFF stopped output or an ENQ is waiting
;; for its ACK. With ENQ/ACK, an ENQ goes out after each run of characters. A carriage return, line feed or form feed
;; starts its delay.
;; Uses: A, X
RS_OUT:
    lda a:BRK_CNT
    beq @L001
    jmp RETURN
@L001:
    bit a:HDW_HSHAKE
    bpl @L003
    bit a:RTS_FALSE
    bpl @L002
    jmp RETURN
@L002:
    lda a:STAT_REG
    and #$60
    beq @L003
    lda a:DLYCNT
    bne @L011
    jmp D_XMIT
@L003:
    lda #<BITON4
    bit a:STAT_REG
    bne @L004
    jmp E_XMIT
@L004:
    bit a:IN_PROG
    bvc @L005
    lda #<BITON7
    sta a:IN_PROG
    lda a:CTLCHR1
    jmp @L020
@L005:
    bit a:SEND_XON
    bpl @L010
    lda #$00
    sta a:SEND_XON
    sta a:IN_PROG
    lda a:CTLCHR2
    jmp @L020
@L010:
    lda a:DLYCNT
    beq @L015
@L011:
    dec a:DLYCNT
    jmp E_XMIT
@L015:
    ldx a:OBUFCNT
    beq D_XMIT
    bit a:NO_OUTPUT
    bmi D_XMIT
    bit a:PROTOCOL
    bvc @L018
    lda a:CHAR_OUT
    bne @L016
    bit a:IN_PROG1
    bmi D_XMIT
    lda #<BITON7
    sta a:IN_PROG1
    lda a:CTLCHR1
    jmp @L020
@L016:
    dec a:CHAR_OUT
@L018:
    ldx a:OCSMRPTR
    lda a:OLOCBUF,x
    dec a:OBUFCNT
    inc a:OCSMRPTR
@L020:
    tax
    SET_1MHZ
    stx ACIADATA
    cpx #<ASC_CR
    bne @L022
    lda a:CRDELAY
    jmp @L024
@L022:
    cpx #<ASC_LF
    bne @L023
    lda a:LFDELAY
    jmp @L024
@L023:
    cpx #<ASC_FF
    bne E_XMIT
    lda a:FFDELAY
@L024:
    sta a:DLYCNT

;; Turns the transmit interrupt on, with RTS and DTR true, leaving the machine at 1 MHz.
;; Uses: A
E_XMIT:
    SET_1MHZ
    lda ACIACMD
    and #$F2
    ora #$05
    sta ACIACMD
    rts

;; Turns the transmit interrupt off, keeping RTS and DTR true, leaving the machine at 1 MHz.
;; Uses: A
D_XMIT:
    SET_1MHZ
    lda ACIACMD
    and #$F2
    ora #$09
    sta ACIACMD

;; Returns from the interrupt handler.
RETURN:
    rts

;; Starts the transmitter by turning its interrupt on, unless the hardware handshake holds RTS false; the interrupt
;; handler then sends what is waiting.
;; Uses: A
;; See: <E_XMIT>
PRIME_OUT:
    php
    sei
    bit a:RTS_FALSE
    bmi @L010
    jsr E_XMIT
    SET_2MHZ
@L010:
    plp
    rts
