; OPRMSG, operator messages. The block file manager calls OPMSGRPLY when it needs the user to do something, such as
; put a volume in a drive: the message appears in a window over the top four lines of the screen, with the rest of the
; screen dark, until the user presses Alpha Lock twice. Everything it changes is put back afterwards.
;
; Names follow Apple's SOS 1.3 listing.

ZZORG:

; ---------------------------------------------------------------------------------------------------------------------
; Hardware
; ---------------------------------------------------------------------------------------------------------------------

Z_REG = $FFD0                       ;; the zero-page register
E_REG = $FFDF                       ;; the environment register; bit 5 turns the screen on
KBPORT = $C008                      ;; the keyboard's state; bit 3 is the Alpha Lock key
BELL = $C040                        ;; reading it sounds the bell
VM0 = $C050                         ;; the first display mode switch; reading VM0 clears it, VM0+1 sets it
VM1 = $C052                         ;; the second display mode switch
VM2 = $C054                         ;; the third display mode switch
VM3 = $C056                         ;; the fourth display mode switch
E_T2 = $FFE8                        ;; the E VIA's timer 2
E_ACR = $FFEB                       ;; the E VIA's auxiliary control register; bit 5 makes timer 2 count pulses
E_PCR = $FFEC                       ;; the E VIA's peripheral control register; its high nibble sets up CB1 and CB2
E_IFR = $FFED                       ;; the E VIA's interrupt flags: bit 3 vertical blanking (CB2), bit 5 timer 2
E_IER = $FFEE                       ;; the E VIA's interrupt enables

; ---------------------------------------------------------------------------------------------------------------------
; Zero page
;
; OPMSGRPLY moves zero page to page 2 ($0200) while it runs, and keeps its work there.
; ---------------------------------------------------------------------------------------------------------------------

;; The page OPMSGRPLY uses as its zero page.
ZPBASE = $200

MSGPTR = $0000                      ;; the message's address (two bytes)
MSGIDX = $0002                      ;; the index of the message's next byte
SCRNIDX = $0003                     ;; the column of the next character on the line
SCRNPTR = $0004                     ;; the screen line's address (two bytes)
DATAPTR = $0006                     ;; where in DATABUF the screen line is saved (two bytes)
DATABUF = $0008                     ;; the four screen lines the window covers, 40 bytes each
SV_ZREG = $00A8                     ;; the caller's zero-page register
SV_EREG = $00A9                     ;; the caller's environment register
SV_SMODE = $00AA                    ;; the caller's SCRNMODE
SV_EACR = $00AB                     ;; bit 5 of the E VIA's auxiliary control register as it was
SV_EPCR = $00AC                     ;; the high nibble of the E VIA's peripheral control register as it was
SV_EIER = $00AD                     ;; the E VIA's blanking and timer interrupt enables that were on
FLAG = $00AE                        ;; the Alpha Lock key's last state

; ---------------------------------------------------------------------------------------------------------------------
; The operator message
; ---------------------------------------------------------------------------------------------------------------------

;; Shows a message in a window at the top of the screen until the user presses Alpha Lock twice, then puts the screen
;; back as it was.
;;
;; The message is up to four lines of 40 characters, in the current bank. A carriage return ($0D) starts a new line,
;; and a line longer than 40 characters goes on to the next. Zero bytes are skipped, and a byte with bit 7 set ends
;; the message. The window's lines are saved first and restored afterwards, and the bell sounds when it appears.
;;
;; To show only the window, it switches to 40-column text and turns the screen on at each vertical blanking and off
;; again 31 blanking pulses later (<VIDEO>), with the E VIA set up to flag them and those interrupts masked. The E VIA,
;; the display mode, SCRNMODE, the environment and zero-page registers are all restored before it returns.
;; In: X/Y = the message's address (low, high)
;; Uses: A, X, Y, ZPBASE..ZPBASE+$AE
;; Keeps: interrupt
;; See: <VIDEO>, <SETPTRS>
OPMSGRPLY:
    php
    sei
    lda Z_REG
    sta ZPBASE+SV_ZREG
    lda #>ZPBASE
    sta Z_REG
    stx MSGPTR
    sty MSGPTR+1
    lda E_REG
    sta SV_EREG
    and #$5F                        ; 2 MHz, screen off
    ora #$40                        ; I/O space on
    sta E_REG
    lda SCRNMODE
    sta SV_SMODE
    lda #$00
    sta SCRNMODE
    bit VM0                         ; 40-column black-and-white text
    bit VM1
    bit VM2
    bit VM3
    ldx E_ACR
    txa
    and #$20
    sta SV_EACR
    txa
    ora #$20                        ; timer 2 counts blanking pulses
    sta E_ACR
    ldx E_PCR
    txa
    and #$F0
    sta SV_EPCR
    txa
    and #$0F
    ora #$60                        ; CB2 flags the start of vertical blanking
    sta E_PCR
    lda E_IER
    and #$38                        ; mask the blanking and timer interrupts that were on
    sta E_IER
    sta SV_EIER
    plp
    ldx #3
OPR010:
    jsr SETPTRS                     ; save the four lines and blank them
    ldy #39
OPR020:
    lda (SCRNPTR),y
    sta (DATAPTR),y
    lda #$A0
    sta (SCRNPTR),y
    dey
    bpl OPR020
    dex
    bpl OPR010
    bit BELL
    ldx #$00
    stx MSGIDX
OPR100:
    jsr SETPTRS                     ; X = the line
    ldy #$00
    sty SCRNIDX
OPR110:
    ldy MSGIDX
    inc MSGIDX
    lda (MSGPTR),y
    beq OPR110
    bmi OPR200                      ; the end of the message
    cmp #$0D
    beq OPR120
    ldy SCRNIDX
    inc SCRNIDX
    ora #$80                        ; normal video
    sta (SCRNPTR),y
    cpy #39
    bcc OPR110
OPR120:
    inx
    cpx #4
    bcc OPR100
OPR200:
    ldy #2                          ; wait for Alpha Lock to change twice
    lda KBPORT
    and #$08
    sta FLAG
OPR210:
    jsr VIDEO
    lda KBPORT
    and #$08
    cmp FLAG
    beq OPR210
    sta FLAG
    dey
    bne OPR210
    ldx #3
OPR400:
    jsr SETPTRS                     ; put the four lines back
    ldy #39
OPR410:
    lda (DATAPTR),y
    sta (SCRNPTR),y
    dey
    bpl OPR410
    dex
    bpl OPR400
    php
    sei
    lda E_ACR
    and #$DF
    ora SV_EACR
    sta E_ACR
    lda E_PCR
    and #$0F
    ora SV_EPCR
    sta E_PCR
    lda SV_EIER                     ; unmask the interrupts that were on
    ora #$80
    sta E_IER
    lda SV_SMODE
    sta SCRNMODE
    lsr a                           ; set the display mode switches SCRNMODE's bits 0-2 and 6 call for
    bcc OPR500
    bit VM0+1
OPR500:
    lsr a
    bcc OPR510
    bit VM1+1
OPR510:
    lsr a
    bcc OPR520
    bit VM2+1
OPR520:
    bit SCRNMODE
    bvc OPR530
    bit VM3+1
OPR530:
    lda SV_EREG
    sta E_REG
    lda SV_ZREG
    sta Z_REG
    plp
    rts

;; Keeps the screen on for the message window only: turns it on at vertical blanking and off when timer 2 has counted
;; the window's blanking pulses.
;;
;; At the start of vertical blanking it starts timer 2 counting 31 pulses and turns the screen on; when the timer runs
;; out it turns the screen off. Bit 7 of SCRNMODE follows the screen. Nothing happens if neither flag is set. The E VIA
;; must be set up as <OPMSGRPLY> sets it.
;; Uses: A, SCRNMODE
;; Keeps: X, Y
;; See: <OPMSGRPLY>
VIDEO:
    lda E_IFR
    and #$28
    beq VID030
    sta E_IFR                       ; clear the flags
    and #$20
    bne VID010
    lda #$1F                        ; vertical blanking: count 31 pulses
    sta E_T2
    lda #$00
    sta E_T2+1
    lda E_REG
    ora #$20                        ; screen on
    sec
    bcs VID020
VID010:
    lda E_REG                       ; the timer ran out: screen off
    and #$DF
    clc
VID020:
    sta E_REG
    lda #$00
    ror a
    sta SCRNMODE
VID030:
    rts

;; Points SCRNPTR at one of the screen's top four lines and DATAPTR at its place in DATABUF.
;; In: X = the line, 0-3
;; Out: SCRNPTR = the line's address in text page 1, DATAPTR = its save area
;; Uses: A
;; Keeps: X, Y
;; See: <DBUFADR>
SETPTRS:
    txa
    lsr a
    ora #$04
    sta SCRNPTR+1
    lda #$00
    ror a
    sta SCRNPTR
    lda #>DATABUF
    sta DATAPTR+1
    lda DBUFADR,x
    sta DATAPTR
    rts

;; The low byte of each line's save area in DATABUF.
DBUFADR:
    .byte <(((0*40)+DATABUF))
    .byte <(((1*40)+DATABUF))
    .byte <(((2*40)+DATABUF))
    .byte <(((3*40)+DATABUF))
ZZEND:
ZZLEN = ZZEND-ZZORG
    .assert ZZLEN == LENOMSG, "SOSORG gives the module another length"
