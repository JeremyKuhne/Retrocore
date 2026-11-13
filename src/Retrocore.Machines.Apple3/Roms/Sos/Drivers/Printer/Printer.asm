;; SOS .PRINTER DRIVER 1.10 (SERIAL)
;;
;; The SOS character device driver for a printer on the Apple III's built-in serial port, a 6551 ACIA at
;; $C0F0-$C0F3. It only writes. SOS loads it from SOS.DRIVER and calls it through the entry point in its device
;; information block, <SP_MAIN>, with the request in SOS's driver parameters at $C0-$C9.
;;
;; A write copies the caller's bytes, up to 55 at a time, into a 110-byte ring buffer, <LOCBUF>, waiting for room,
;; and starts the transmitter if it is idle by calling the interrupt handler, <ACIAMIH>, itself. The handler sends
;; the buffer's next byte each time the transmitter empties, and turns the transmit interrupt off when the buffer is
;; empty or when the printer holds DSR or DCD false. After a carriage return, line feed or form feed it can hold off
;; the next byte for a number of interrupts.
;;
;; Requests (see <SP_REQSW>):
;;
;; - 1, write (<SP_WRITE>). A read (<SP_READ>) is refused as a bad operation.
;; - 2, status (<SP_STAT>): codes 0-2; 1 and 2 return a zero byte.
;; - 3, control (<SP_CNTL>): code 0 waits for output to finish and resets the ACIA; 1 and 2 do nothing.
;; - 6, open (<SP_OPEN>), and 7, close (<SP_CLOSE>): claim the ACIA's interrupt and set the port up, or wait for
;;   the buffer to empty and give the interrupt back.
;; - 8, initialize (<SP_INIT>): marks the port closed and checks the configuration.
;; - 4 and 5 are refused as bad requests.
;;
;; The driver has one device, .PRINTER (<IDBLK>). Its configuration block, from <DRATE> to <FFDELAY>, holds the
;; settings the System Configuration Program can change: 1200 baud, seven data bits with odd parity, and no delays.
;; This release has no comment record, so its code starts with the device information block.
;;
;; Labels follow Apple's listing of a later release, "Apple /// Serial Printer Port Driver 1.30 Source Code Listing"
;; (https://www.apple3.org/Documents/SourceCode/Apple%203%20Serial%20Driver.pdf), and the comments are our own. This
;; source builds the driver on Apple's disks, release 1.10, which the listing's revision history dates 14 April 1981.
;; Release 1.30 changed it in these ways, each noted where it falls:
;;
;; - 1.30 adds a comment record before the code, and a transmit-in-progress flag, XMIT, after <OPENFLG>, which moves
;;   every later variable up a byte. The write sets XMIT when it starts the transmitter, and the interrupt handler
;;   clears it only on the second interrupt that finds the buffer empty, giving the last byte time to go. Close and
;;   reset wait for XMIT to clear; here they wait for the buffer count (<SP_CLOSE>, <CNTL00>), and the write asks
;;   the ACIA's command register whether the transmit interrupt is on (<SP_WRITE>).
;; - 1.30 keeps its copyright text in <LOCBUF>'s first bytes, which output overwrites. Here the text, which says
;;   1980, follows the configuration block, and the buffer starts empty.
;; - 1.30's close and reset turn interrupts off while they reprogram the ACIA, and close switches to 1 MHz first.
;; - Open clears the buffer count here, where 1.30 clears XMIT (<SP_OPEN>).
;; - The interrupt handler's code is arranged differently (<ACIAMIH>).
;;
;; Maintained by hand; SOS driver tests check it assembles byte-identically to Apple's .PRINTER 1.10.

.cpu Mos6502

;; The device type in the device information block: a character device that writes.
DEVTYPE = $41

;; The device subtype in the device information block.
SUBTYPE = $01

;; The manufacturer in the device information block: 1 for Apple.
APPLE = $01

;; The driver's release, 1.10, as SOS reports it.
RELEASE = $1100

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
    .local M3579
    .ifnblank p1
    lda p1
    .endif
    .ifnblank p2
    cmp #<(p2+$01)
    bcs M3579
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
M3579:
.endmacro

; ---------------------------------------------------------------------------------------------------------------------
; Device information and configuration blocks
; ---------------------------------------------------------------------------------------------------------------------

;; The device information block for .PRINTER: the link to the next device's block (none), the entry point, the
;; name's length and the name, the device number, slot and unit, the type and subtype, a reserved byte, the block
;; count (none for a character device), the manufacturer and the release. The configuration block's length, 5,
;; follows it.
IDBLK:
    .word $00
    .word SP_MAIN
    .byte $08
    .byte ".PRINTER       "
    .byte $80, $00, $00
    .byte DEVTYPE
    .byte SUBTYPE
    .byte $00
    .word $00
    .word APPLE
    .word RELEASE
    .word $05

;; The baud rate, the low four bits of <ACIACTL>: 8 for 1200 baud.
;; See: <SP_INIT>
DRATE:
    .byte $08

;; The data format. The high four bits go to <ACIACTL>'s stop bits, word length and receive clock, and bits 3-1 to
;; <ACIACMD>'s parity; $22 is seven data bits with odd parity.
;; See: <SP_INIT>
DFORMAT:
    .byte $22

;; Interrupts to wait after sending a carriage return.
CRDELAY:
    .byte $00

;; Interrupts to wait after sending a line feed.
LFDELAY:
    .byte $00

;; Interrupts to wait after sending a form feed.
FFDELAY:
    .byte $00

    ; 1.30 has no text here; its copyright is in LOCBUF.
    .byte "(C) 1980 by Apple Computer Inc."

; ---------------------------------------------------------------------------------------------------------------------
; SOS calls, errors and hardware
; ---------------------------------------------------------------------------------------------------------------------

ALLOCSIR = $1913                    ;; SOS's call that claims interrupt resources for a driver
DEALCSIR = $1916                    ;; SOS's call that gives interrupt resources back
SYSERR = $1928                      ;; SOS's call that ends a request with the error code in A; it does not return

XREQCODE = $20                      ;; error: the request code is not one the driver takes
XCTLCODE = $21                      ;; error: the control or status code is not one the driver takes
XNOTOPEN = $23                      ;; error: the printer is not open
XNOTAVIL = $24                      ;; error: the printer is already open
XNORESRC = $25                      ;; error: the ACIA's interrupt belongs to another driver
XBADOP = $26                        ;; error: the operation is not one the device does

ACIADATA = $C0F0                    ;; the ACIA's data register: the byte to send goes here
ACIASTAT = $C0F1                    ;; the ACIA's status register; writing it resets the ACIA

;; The ACIA's command register. Bits 7-5: the parity; 4: echo; 3-2: the transmitter, 01 for RTS true with its
;; interrupt on, 10 for RTS true with it off; 1: set to turn the receive interrupt off; 0: DTR true.
ACIACMD = $C0F2

;; The ACIA's control register. Bit 7: two stop bits; 6-5: the word length, 8 bits less their value; 4: the internal
;; receive clock; 3-0: the baud rate, 3 for 110 baud, 8 for 1200, up to $F for 19,200.
ACIACTL = $C0F3

;; The environment register. Bit 7 set runs the machine at 1 MHz.
E_REG = $FFDF

;; The bank register: which bank of memory is at $2000-$9FFF.
B_REG = $FFEF

TRUE = $80                          ;; a flag that is on: bit 7 set
FALSE = $00                         ;; a flag that is off
ASC_LF = $0A                        ;; line feed
ASC_FF = $0C                        ;; form feed
ASC_CR = $0D                        ;; carriage return
BITON4 = $10                        ;; bit 4 alone
BITON7 = $80                        ;; bit 7 alone

; ---------------------------------------------------------------------------------------------------------------------
; SOS's driver parameters and the driver's zero page
; ---------------------------------------------------------------------------------------------------------------------

;; Where SOS puts a request's parameters for its driver.
SOSINT = $C0

REQCODE = SOSINT+$00                ;; the request code
BUFFER = SOSINT+$02                 ;; write: the caller's buffer, an extended address
REQCNT = SOSINT+$04                 ;; write: the number of bytes
CTLSTAT = SOSINT+$02                ;; status and control: the code
CSLIST = SOSINT+$03                 ;; status and control: the caller's list, an extended address
ZPGSAVE = SOSINT+$0A                ;; the zero page a driver may use
ZPGTEMP = ZPGSAVE+$00               ;; the first of those bytes
MOVCNT = ZPGTEMP+$00                ;; the number of bytes a write is moving into the buffer this time

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

;; Bit 7 set while the printer is open. Release 1.30 puts its XMIT flag after this byte.
OPENFLG:
    .byte FALSE

;; Interrupts to let pass before the next byte goes out, after a carriage return, line feed or form feed.
DLYCNT:
    .byte $00

;; The number of bytes in the buffer.
BUFCNT:
    .byte $00

;; Where the next byte to send is in the buffer.
BUFHEAD:
    .byte $00

;; Where the next byte written goes in the buffer.
BUFTAIL:
    .byte $00

;; The size of <LOCBUF>.
BUFSIZE = 110

;; The output ring buffer.
LOCBUF:
    .res BUFSIZE, $00

; ---------------------------------------------------------------------------------------------------------------------
; Requests
; ---------------------------------------------------------------------------------------------------------------------

;; The driver's entry point: carries out the request in <REQCODE>.
;; In: REQCODE = the request, with its parameters at <SOSINT>
;; Errors: XREQCODE = a request the driver does not take, XNOTOPEN = the printer is not open
;; See: <SP_REQSW>
SP_MAIN:
    SWITCH REQCODE, $08, SP_REQSW

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
SP_REQSW:
    .word SP_READ-$01
    .word SP_WRITE-$01
    .word SP_STAT-$01
    .word SP_CNTL-$01
    .word BADREQ-$01
    .word BADREQ-$01
    .word SP_OPEN-$01
    .word SP_CLOSE-$01
    .word SP_INIT-$01

;; Initialize: marks the printer closed and checks the configuration, when SOS starts.
;;
;; It keeps the baud rate to four bits, and in the data format turns echo off, chooses the internal receive clock,
;; and adds a second stop bit at 110 baud.
;; Out: carry = clear
;; Uses: A, X
SP_INIT:
    lda #<FALSE
    sta a:OPENFLG
    lda a:DRATE
    and #$0F
    sta a:DRATE
    tax
    lda a:DFORMAT
    and #$EE
    ora #$10
    cpx #$03
    bne @L010
    ora #$80
@L010:
    sta a:DFORMAT
    clc
    rts

;; Open: claims the ACIA's interrupt, empties the buffer and resets the port.
;;
;; Release 1.30 clears its XMIT flag here instead of the buffer count.
;; Errors: XNOTAVIL = the printer is already open, XNORESRC = another driver has the ACIA's interrupt
;; Uses: A, X, Y
;; See: <CNTL00>
SP_OPEN:
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
    lda #$00
    sta a:BUFCNT
    jsr CNTL00
    lda #<TRUE
    sta a:OPENFLG
    rts
@L020:
    lda #<XNORESRC
    jsr SYSERR

;; Close: waits for the buffer to empty, resets the ACIA and gives the interrupt back.
;;
;; The last byte may still be leaving the ACIA when the reset comes. Release 1.30 waits for its XMIT flag instead,
;; which clears an interrupt later, and resets the ACIA at 1 MHz with interrupts off.
;; Errors: XNOTOPEN = the printer is not open
;; Uses: A, X, Y
SP_CLOSE:
    asl a:OPENFLG
    bcs @L010
    jmp NOTOPEN
@L010:
    lda a:BUFCNT
    bne @L010
    sta ACIASTAT
    lda #<SIRCOUNT
    ldx a:SIRADDR
    ldy a:SIRADDR+$01
    jsr DEALCSIR
    rts

;; Read: refused, since the printer only writes.
;; Errors: XNOTOPEN = the printer is not open, XBADOP = the printer is open
SP_READ:
    bit a:OPENFLG
    bmi @L010
    jmp NOTOPEN
@L010:
    lda #<XBADOP
    jsr SYSERR

;; Write: copies the caller's bytes into the buffer and has them sent.
;;
;; Each pass moves up to half the buffer, 55 bytes, waiting until there is room for them, then starts the
;; transmitter unless its interrupt is already on, by calling the interrupt handler with the ACIA's status. Before a
;; pass it moves the caller's pointer back by $80 into the next bank when it is in page $FF, so that the pass cannot
;; run off the end of the bank. Release 1.30 decides whether to start the transmitter by its XMIT flag instead.
;; In: BUFFER = the caller's buffer, REQCNT = the number of bytes
;; Errors: XNOTOPEN = the printer is not open
;; Uses: A, X, Y, BUFFER, REQCNT, MOVCNT
SP_WRITE:
    bit a:OPENFLG
    bmi @L010
    jmp NOTOPEN
@L010:
    lda #<(BUFSIZE/$02)
    ldy REQCNT+$01
    bne @L020
    cmp REQCNT
    bcc @L020
    lda REQCNT
    bne @L020
    rts
@L020:
    sta MOVCNT
    lda BUFFER+$01
    cmp #$FF
    bcc @L030
    sbc #$80
    sta BUFFER+$01
    inc $1401+BUFFER
@L030:
    sec
    lda #<BUFSIZE
    sbc MOVCNT
@L040:
    cmp a:BUFCNT
    bcc @L040
    ldy #$00
    ldx a:BUFTAIL
@L050:
    lda (BUFFER),y
    sta a:LOCBUF,x
    inx
    cpx #<BUFSIZE
    bcc @L060
    ldx #$00
@L060:
    iny
    cpy MOVCNT
    bcc @L050
    stx a:BUFTAIL
    php
    sei
    clc
    lda a:BUFCNT
    adc MOVCNT
    sta a:BUFCNT
    lda E_REG
    pha
    ora #<BITON7
    sta E_REG
    lda ACIACMD                     ; 1.30 tests and sets XMIT here
    and #$0C
    cmp #$04
    beq @L070
    ldy ACIASTAT
    jsr ACIAMIH
@L070:
    pla
    sta E_REG
    plp
    clc
    lda BUFFER
    adc MOVCNT
    sta BUFFER
    bcc @L080
    inc BUFFER+$01
@L080:
    sec
    lda REQCNT
    sbc MOVCNT
    sta REQCNT
    bcs @L010
    dec REQCNT+$01
    jmp @L010

; ---------------------------------------------------------------------------------------------------------------------
; The interrupt handler
; ---------------------------------------------------------------------------------------------------------------------

;; The ACIA's interrupt handler: sends the buffer's next byte when the transmitter is empty, and keeps the transmit
;; interrupt on while there is more to send.
;;
;; DSR or DCD false, or an empty buffer, turns the transmit interrupt off. While a delay is counting down, each
;; interrupt only counts it. A carriage return, line feed or form feed starts its delay. Release 1.30 puts the code
;; that turns the interrupt off at the handler's end, and when the buffer empties it leaves the interrupt on for one
;; more, turning it off and clearing XMIT on the next.
;; In: Y = the ACIA's status, read by SOS's interrupt dispatcher or by <SP_WRITE>
;; Uses: A, X
ACIAMIH:
    lda E_REG
    ora #<BITON7
    sta E_REG
    tya
    and #$60
    beq @L005
@L080:
    lda ACIACMD
    and #$E0
    ora #$0B
    sta ACIACMD
    rts
@L005:
    tya
    and #<BITON4
    beq @L060
    lda a:DLYCNT
    beq @L010
    dec a:DLYCNT
    jmp @L060
@L010:
    lda a:BUFCNT
    beq @L080
    ldx a:BUFHEAD
    lda a:LOCBUF,x
    sta ACIADATA
    inx
    cpx #<BUFSIZE
    bcc @L020
    ldx #$00
@L020:
    stx a:BUFHEAD
    dec a:BUFCNT
    cmp #<ASC_CR
    beq @L040
    bcs @L060
    cmp #<ASC_LF
    bne @L030
    lda a:LFDELAY
    bcs @L050
@L030:
    cmp #<ASC_FF
    bne @L060
    lda a:FFDELAY
    bcs @L050
@L040:
    lda a:CRDELAY
@L050:
    sta a:DLYCNT
@L060:
    lda ACIACMD
    and #$E0
    ora #$07
    sta ACIACMD
    rts

; ---------------------------------------------------------------------------------------------------------------------
; Status and control
; ---------------------------------------------------------------------------------------------------------------------

;; Status: answers the status code in <CTLSTAT>.
;; In: CTLSTAT = the status code, CSLIST = the caller's list
;; Errors: XNOTOPEN = the printer is not open, XCTLCODE = a code above 2
;; See: <STATSW>
SP_STAT:
    bit a:OPENFLG
    bmi @L010
    jmp NOTOPEN
@L010:
    SWITCH CTLSTAT, $02, STATSW

;; Ends the request with <XCTLCODE>.
BADCTL:
    lda #<XCTLCODE
    jsr SYSERR

;; Each status code's routine, less one.
STATSW:
    .word STAT00-$01
    .word STAT01-$01
    .word STAT02-$01

;; Status code 0: does nothing.
STAT00:
    rts

;; Status code 1, the status table: returns a zero byte.
;; In: CSLIST = the list
;; Uses: A, Y
STAT01:
    ldy #$00
    lda #$00
    sta (CSLIST),y
    rts

;; Status code 2, the newline mode: returns <FALSE>, since the driver has none.
;; In: CSLIST = the list
;; Uses: A, Y
STAT02:
    ldy #$00
    lda #<FALSE
    sta (CSLIST),y
    rts

;; Control: carries out the control code in <CTLSTAT>.
;; In: CTLSTAT = the control code, CSLIST = the caller's list
;; Errors: XNOTOPEN = the printer is not open, XCTLCODE = a code above 2
;; See: <CNTLSW>
SP_CNTL:
    bit a:OPENFLG
    bmi @L010
    jmp NOTOPEN
@L010:
    SWITCH CTLSTAT, $02, CNTLSW
    jmp BADCTL

;; Each control code's routine, less one.
CNTLSW:
    .word CNTL00-$01
    .word CNTL01-$01
    .word CNTL02-$01

;; Control code 0: waits for the buffer to empty and any delay to pass, then resets the ACIA and sets it up.
;;
;; The ACIA gets the baud rate and data format, with DTR and RTS true and both its interrupts off. Release 1.30
;; waits for its XMIT flag instead, and turns interrupts off while it sets the ACIA up.
;; Uses: A, X
CNTL00:
@L010:
    lda a:BUFCNT
    ora a:DLYCNT
    bne @L010
    sta a:BUFHEAD
    sta a:BUFTAIL
    lda E_REG
    tax
    ora #<BITON7
    sta E_REG
    sta ACIASTAT
    lda a:DFORMAT
    and #$F0
    ora a:DRATE
    sta ACIACTL
    lda a:DFORMAT
    asl a
    asl a
    asl a
    asl a
    ora #$0B
    sta ACIACMD
    stx E_REG
    rts

;; Control code 1: does nothing.
CNTL01:
    rts

;; Control code 2: does nothing.
CNTL02:
    rts
