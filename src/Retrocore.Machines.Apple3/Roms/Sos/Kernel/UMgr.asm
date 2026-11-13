; UMGR, the utility manager: the utility calls SET_FENCE, GET_FENCE, SET_TIME, GET_TIME, JOYSTICK and COLD_START. It
; also holds DATETIME, which gives the block file manager the date and time for the files it creates and changes,
; and the pseudo clock that keeps the time when the Apple III has no clock chip.
;
; Names follow Apple's SOS 1.3 listing.

ZZORG:

; ---------------------------------------------------------------------------------------------------------------------
; Parameters, constants and registers
; ---------------------------------------------------------------------------------------------------------------------

U_TPARMX = $C0                      ;; where SCMGR put the utility call's parameters
U_REQCODE = U_TPARMX                ;; the request number, 0-5 for $60-$65
PRIORITY = U_TPARMX+1               ;; SET_FENCE's new fence, or GET_FENCE's pointer for the result
J_MODE = U_TPARMX+1                 ;; JOYSTICK's mode: which joystick port, and which axes to read
J_VALUE = U_TPARMX+2                ;; JOYSTICK's pointer for the result (four bytes)
TIME = U_TPARMX+1                   ;; SET_TIME's and GET_TIME's pointer to the 18-character time
MEMORY = U_TPARMX+1                 ;; COLDSTRT's pointer as it blanks memory (two bytes)
BITON2 = $04                        ;; bit 2 alone
BITON5 = $20                        ;; bit 5 alone
BITON6 = $40                        ;; bit 6 alone
BITON7 = $80                        ;; bit 7 alone
BITOFF5 = $DF                       ;; every bit but 5
Z_REG = $FFD0                       ;; the zero-page register, which also selects the clock chip's register
E_REG = $FFDF                       ;; the environment register
B_REG = $FFEF                       ;; the bank register

; ---------------------------------------------------------------------------------------------------------------------
; The utility manager
; ---------------------------------------------------------------------------------------------------------------------

;; Carries out a utility call ($60-$65), through <USWTBL>, with the I/O space switched in.
;; In: U_REQCODE = the request number, with the call's parameters after it
;; Out: SERR = 0 or the error code, carry = set for an error
;; Errors: BADSCNUM, BADJMODE, XNORESRC (returned through <SYSERR>)
;; See: <SCMGR>, <USWTBL>
UMGR:
    lda E_REG                       ; I/O space on
    ora #BITON6
    sta E_REG
    lda U_REQCODE
    cmp #USWCNT
    bcs UMGRERR
    asl a
    tax
    lda USWTBL+1,x                  ; enter the call's routine by RTS
    pha
    lda USWTBL,x
    pha
    rts
UMGRERR:
    lda #<BADSCNUM
    jsr SYSERR

;; The utility calls' routines, by request number, each address less one for the RTS that enters it.
;; See: <UMGR>
USWTBL:
    .word SET_FENCE-1               ; $60
    .word GET_FENCE-1               ; $61
    .word SET_TIME-1                ; $62
    .word GET_TIME-1                ; $63
    .word JOYSTICK-1                ; $64
    .word COLDSTRT-1                ; $65

;; The number of utility calls in <USWTBL>.
USWCNT = (((* )- USWTBL)/2)

;; SET_FENCE: sets the event fence; events of this priority or lower wait until it is lowered.
;; In: PRIORITY = the new fence
;; Out: CEVPRI = the fence
;; See: <GET_FENCE>, <DISPATCH>
SET_FENCE:
    lda PRIORITY
    sta CEVPRI
    rts

;; GET_FENCE: returns the event fence in the caller's parameter list.
;; In: PRIORITY = SCMGR's pointer to the result
;; See: <SET_FENCE>
GET_FENCE:
    lda CEVPRI
    ldy #0
    sta (PRIORITY),y
    rts

; ---------------------------------------------------------------------------------------------------------------------
; The clock
;
; The time a program sees is 18 ASCII digits, "YYYYMMDDWHHMMSSmmm": year, month, day, weekday (1 for Sunday), hour,
; minute, second and millisecond. The clock chip, when there is one, counts from milliseconds to months, its registers
; selected by the zero-page register while CLOCK is read or written. It has no year and no 29 February; SOS keeps the
; year's two digits in spare bits of its day and month latches, and the century is always taken as 19.
;
; PCLOCK, the pseudo clock, holds the time in the clock's order, as BCD. SET_TIME sets it, and saves a copy, with a
; checksum, in the memory hidden behind the VIA at $FFD0; GET_TIME and DATETIME fall back on it when the clock is
; missing or can't be read.
; ---------------------------------------------------------------------------------------------------------------------

PCLK = $D0                          ;; SET_TIME's pointer to the saved copy, $8F:FFD0 (two bytes)
WKDAY = $D2                         ;; SET_TIME's work while it works out the weekday
CKSUM = $D3                         ;; SET_TIME's checksum of the saved copy
CLKTEMP = $18D4                     ;; GET_TIME's copy of the clock's registers: SOS zero page $D4-$DD, absolute

;; The pseudo clock: ten BCD bytes in the clock chip's order.
;;
;; 0: thousandths of a second (high nibble), 1: tenths and hundredths, 2: seconds, 3: minutes, 4: hours, 5: the
;; weekday, 6: the day, 7: the month, 8: the year's two digits, 9: the century. The initial contents are whatever was
;; in memory when Apple built SOS.KERNEL; SOS sets the pseudo clock at boot and in SET_TIME and GET_TIME.
;; See: <SET_TIME>, <GET_TIME>, <DATETIME>
PCLOCK:
    .byte $A0, $D3, $A0, $A0, $D0, $A0, $A0, $FE, $A0, $A0

;; GET_TIME's count of tries left at reading the clock. The initial value is whatever was in memory when Apple built
;; SOS.KERNEL.
RETRY:
    .res $01, $C5

CLOCK = $C070                       ;; the clock chip's data; the zero-page register selects the chip's register
CSEC = $02                          ;; the clock's seconds counter
CMIN = $03                          ;; the clock's minutes counter
CMON = $07                          ;; the clock's months counter, the last counter
LDAY = $0E                          ;; the clock's day latch; the month latch follows. They hold the year.
CRESET = $12                        ;; the clock's register that resets the counters
STATUS = $14                        ;; the clock's status: bit 7 set for no clock, non-zero after a rollover

;; For each month, a number that, added to the year, a quarter of it and the day, gives the weekday modulo 7.
;; See: <SET_TIME>
WKMON:
    .byte 8, 11, 11, 7, 9, 12
    .byte 7, 10, 13, 8, 11, 13

;; SET_TIME: sets the clock, and the pseudo clock, from an 18-digit time.
;;
;; The weekday given is ignored and worked out from the date, the century is ignored, and the milliseconds are set to
;; 0. The date is taken to be valid. Without a clock chip only the pseudo clock is set.
;; In: TIME = the time ("YYYYMMDDWHHMMSSmmm")
;; Uses: A, X, Y, PCLOCK, PCLK, WKDAY, CKSUM
;; See: <GET_TIME>, <PCLOCK>
SET_TIME:
    ldx #$00
    ldy #$12
    lda #'0'                        ; the low nibble of byte 0 is always 0
    bne STIM011
STIM010:
    inx
    lda (TIME),y
STIM011:
    and #$0F                        ; two ASCII digits into each BCD byte, from the end
    sta PCLOCK,x
    dey
    cpy #$07
    beq STIM010                     ; the weekday is a single digit
    lda (TIME),y
    asl a
    asl a
    asl a
    asl a
    ora PCLOCK,x
    sta PCLOCK,x
    dey
    bpl STIM010
    lda PCLOCK+7                    ; work out the weekday
    jsr BCDBIN
    tax                             ; X = the month
    lda PCLOCK+8
    jsr BCDBIN
    tay                             ; Y = the year
    lsr a
    lsr a
    sta WKDAY
    tya
    and #$03
    bne STIM015
    cpx #3
    bcs STIM015
    dey                             ; January or February of a leap year
STIM015:
    clc
    tya
    adc WKDAY
    adc WKMON-1,x
    sta WKDAY
    lda PCLOCK+6
    jsr BCDBIN
    clc
    adc WKDAY
    sec
STIM016:
    sbc #7                          ; down to 1-7
    cmp #8
    bcs STIM016
    sta PCLOCK+5
    lda #$D0                        ; save the pseudo clock at $8F:FFD0, behind the VIA
    sta PCLK
    lda #$FF
    sta PCLK+1
    lda #$8F
    sta $1401+PCLK
    lda #$A5
    sta CKSUM
    ldy #$00
STIM020:
    lda PCLOCK,y
    sta (PCLK),y
    eor CKSUM
    sta CKSUM
    iny
    cpy #$0A
    bcc STIM020
    sta (PCLK),y                    ; then the checksum
    lda Z_REG
    pha
    lda E_REG
    pha
    ora #BITON7                     ; the clock is read at 1 MHz
    sta E_REG
    ldy #STATUS
    sty Z_REG
    lda CLOCK
    bmi STIM050                     ; no clock
    ldx #CRESET
    stx Z_REG
    lda #$FF                        ; reset every counter
    sta CLOCK
    sta CLOCK
    ldx #CSEC-1
STIM030:
    inx
    php
    sei
STIM040:
    stx Z_REG                       ; set a counter, until no rollover spoils it
    lda CLOCK
    lda PCLOCK,x
    sta CLOCK
    lda CLOCK
    sty Z_REG
    lda CLOCK
    bne STIM040
    plp
    cpx #CMON
    bcc STIM030
    ldx #LDAY                       ; the year, in the day and month latches
    stx Z_REG
    lda PCLOCK+8
    ora #$CC
    sta CLOCK
    inc Z_REG
    lda PCLOCK+8
    lsr a
    lsr a
    ora #$CC
    sta CLOCK
STIM050:
    pla
    sta E_REG
    pla
    sta Z_REG
    rts

;; GET_TIME: returns the time as 18 digits, from the clock, or from the pseudo clock if there is no clock or it can't
;; be read in 17 tries.
;;
;; The century is always 19.
;; In: TIME = SCMGR's pointer to the result
;; Uses: A, X, Y, PCLOCK, RETRY, CLKTEMP
;; See: <SET_TIME>, <PCLOCK>
GET_TIME:
    lda Z_REG
    pha
    lda E_REG
    pha
    ora #BITON7                     ; the clock is read at 1 MHz
    sta E_REG
    ldy #STATUS
    sty Z_REG
    lda CLOCK
    bmi GTIM050                     ; no clock
    lda #$10
    sta RETRY
GTIM010:
    ldx #CMON+1
    php
    sei
GTIM020:
    dex                             ; read the counters, months first
    bmi GTIM030
    stx Z_REG
    lda CLOCK
    sta CLKTEMP,x
    sty Z_REG
    lda CLOCK
    beq GTIM020
    plp                             ; a rollover: try again
    dec RETRY
    bpl GTIM010
    bmi GTIM050
GTIM030:
    plp
    ldx #LDAY+1                     ; the year, from the month and day latches
    stx Z_REG
    lda CLOCK
    sec
    rol a
    rol a
    dec Z_REG
    and CLOCK
    sta CLKTEMP+8
    ldx #$09
GTIM040:
    lda CLKTEMP,x
    sta PCLOCK,x
    dex
    bpl GTIM040
GTIM050:
    lda #$19                        ; the century
    sta PCLOCK+9
    pla
    sta E_REG
    pla
    sta Z_REG
    ldy #$11
    ldx #$00
GTIM060:
    lda PCLOCK,x                    ; each BCD byte into two ASCII digits, from the end
    lsr a
    lsr a
    lsr a
    lsr a
    ora #$30
    sta (TIME),y
    inx
    dey
    bmi GTIM080
GTIM070:
    lda PCLOCK,x
    and #$0F
    ora #$30
    sta (TIME),y
    dey
    cpy #$07
    bne GTIM060
    inx                             ; the weekday is a single digit
    bne GTIM070
GTIM080:
    rts

; ---------------------------------------------------------------------------------------------------------------------
; The block file manager's date and time
; ---------------------------------------------------------------------------------------------------------------------

;; The caller's zero-page offset for <DATETIME>'s stamp.
OFFSET:
    .byte 0

;; <DATETIME>'s tries left at reading the clock.
ERRCNT:
    .byte 0

;; <DATETIME>'s copy of the clock's minutes, hours, weekday, day and month, in BCD. The initial contents are whatever
;; was in memory when Apple built SOS.KERNEL.
CLKREGS:
    .byte $C7, $80, $85, $D0, $80

MIN = CLKREGS+0                     ;; the minutes
HOUR = CLKREGS+1                    ;; the hours
DAY = CLKREGS+3                     ;; the day
MON = CLKREGS+4                     ;; the month
YEAR = CLKREGS+2                    ;; the year, in place of the weekday, once it is read

;; Writes the date and time stamp the block file manager keeps for a file, from the clock or the pseudo clock.
;;
;; The stamp is four bytes in zero page: the day in bits 0-4 and the month's low 3 bits in bits 5-7; the month's top
;; bit in bit 0 and the year (0-99) in bits 1-7; the minute; the hour. When there is no clock, or it can't be read in
;; 9 tries, the pseudo clock's time is used.
;; In: X = the stamp's zero-page address
;; Out: carry = clear
;; Uses: A, X, Y, OFFSET, ERRCNT, CLKREGS
;; See: <PCLOCK>, <BCDBIN>
DATETIME:
    stx OFFSET
    lda Z_REG
    pha
    lda E_REG
    pha
    ora #BITON7+BITON6              ; 1 MHz, I/O space on
    sta E_REG
    ldy #STATUS
    sty Z_REG
    lda CLOCK
    bmi DT030                       ; no clock
    lda #8
    sta ERRCNT
DT010:
    ldx #CMON+1
    php
    sei
DT020:
    dex                             ; read the months down to the minutes
    cpx #CMIN
    bcc DT050
    stx Z_REG
    lda CLOCK
    sta CLKREGS-CMIN,x
    sty Z_REG
    lda CLOCK
    beq DT020
    plp                             ; a rollover: try again
    dec ERRCNT
    bpl DT010
DT030:
    pla
    sta E_REG
    pla
    sta Z_REG
    ldx #CMON-CMIN                  ; use the pseudo clock
DT040:
    lda PCLOCK+CMIN,x
    sta CLKREGS,x
    dex
    bpl DT040
    ldx PCLOCK+8
    jmp DT060
DT050:
    plp
    lda #LDAY+1                     ; the year, from the month and day latches
    sta Z_REG
    lda CLOCK
    sec
    rol a
    rol a
    dec Z_REG
    and CLOCK
    tax
    pla
    sta E_REG
    pla
    sta Z_REG
DT060:
    txa                             ; X = the year, in BCD
    jsr BCDBIN
    sta YEAR
    lda MON
    jsr BCDBIN
    asl a
    asl a
    asl a
    asl a
    asl a
    sta MON
    rol YEAR                        ; the month's top bit under the year
    lda DAY
    jsr BCDBIN
    ora MON
    ldx OFFSET
    sta 0,x
    lda YEAR
    sta 1,x
    lda MIN
    jsr BCDBIN
    sta 2,x
    lda HOUR
    jsr BCDBIN
    sta 3,x
    clc
    rts

;; Converts a two-digit BCD byte to binary.
;; In: A = the BCD byte
;; Out: A = its value
;; Uses: Y
;; Keeps: X
;; See: <TENS>
BCDBIN:
    pha
    lsr a
    lsr a
    lsr a
    lsr a
    tay
    pla
    and #$0F
    clc
    adc TENS,y
    rts

;; The value of each tens digit, for <BCDBIN>.
TENS:
    .byte 00, 10, 20, 30, 40, 50, 60, 70, 80, 90

; ---------------------------------------------------------------------------------------------------------------------
; The joysticks
; ---------------------------------------------------------------------------------------------------------------------

AD_INPUT = $D0                      ;; the analog input being read
AD_TEMP = $D1                       ;; AD_READ's work
PA_SW0 = $C061                      ;; port A's switch 0; bit 7 set when pressed
PA_SW1 = $C063                      ;; port A's switch 1
PB_SW0 = $C062                      ;; port B's switch 0
PB_SW1 = $C060                      ;; port B's switch 1
AD_SEL0 = $C058                     ;; the input select switch for bit 0; reading clears it, reading +1 sets it
AD_SEL1 = $C05E                     ;; the input select switch for bit 1
AD_SEL2 = $C05A                     ;; the input select switch for bit 2
AD_CHRG = $C05C                     ;; reading it charges the analog ramp's capacitor
AD_STRT = $C05D                     ;; reading it starts the analog timeout
AD_FLAG = $C066                     ;; bit 7 set while the analog timeout runs
TCHARGE = 500                       ;; the capacitor's charging time, in timer counts
TOFFSET = 360                       ;; the timer's start for a reading, offsetting it into range
ANALOG = $F4A8                      ;; the boot ROM's routine that times an analog input
ANLOG1 = $F4AB                      ;; ANALOG after it starts the timer, to go on after an interrupt
D_T2 = $FFD8                        ;; the D VIA's timer 2
D_ACR = $FFDB                       ;; the D VIA's auxiliary control register
D_IFR = $FFDD                       ;; the D VIA's interrupt flags; bit 5 is timer 2's
ENSEL = $C0DC                       ;; the ENSEL switch, which reading turns off
ENSIO = $C0DE                       ;; the ENSIO switch, which reading sets for input

;; JOYSTICK: reads a joystick's two switches and, as asked, its X and Y axes.
;;
;; The mode's bit 2 picks the port (set for port A, clear for port B), bit 0 asks for the X axis and bit 1 for the
;; Y axis. The result is four bytes: switch 0 and switch 1, each $FF when pressed and 0 when not, then the X and Y
;; axes (0-255), each written only when asked for.
;; In: J_MODE = the mode (0-7), J_VALUE = SCMGR's pointer to the result
;; Out: carry = set for an error
;; Errors: BADJMODE, or XNORESRC when the analog hardware is in use (returned through <SYSERR>)
;; Uses: A, X, Y, J_MODE, AD_INPUT
;; See: <AD_READ>, <AD_SETUP>
JOYSTICK:
    lda J_MODE
    cmp #$08
    bcc JS010
    lda #<BADJMODE
JS_ERR:
    jsr SYSERR
JS010:
    jsr AD_SETUP
    bcs JS_ERR
    lda J_MODE
    and #BITON2
    bne JS020
    lda PB_SW0                      ; port B: analog inputs 1 and 2
    ldx PB_SW1
    ldy #$01
    bne JS030
JS020:
    lda PA_SW0                      ; port A: analog inputs 3 and 4
    ldx PA_SW1
    ldy #$03
JS030:
    sty AD_INPUT
    and #BITON7
    beq JS040
    lda #$FF
JS040:
    ldy #$00
    sta (J_VALUE),y
    txa
    and #BITON7
    beq JS050
    lda #$FF
JS050:
    iny
    sta (J_VALUE),y
    lsr J_MODE
    bcc JS060
    lda AD_INPUT
    jsr AD_READ
    ldy #$02
    sta (J_VALUE),y
JS060:
    inc AD_INPUT
    lsr J_MODE
    bcc JS070
    lda AD_INPUT
    jsr AD_READ
    ldy #$03
    sta (J_VALUE),y
JS070:
    jsr AD_CLNUP
    rts

;; Takes the resources the joystick needs and sets up for reading it: 2 MHz, the I/O space and the boot ROM, and the D
;; VIA's timer 2 as a one-shot.
;; Out: carry = set when the resources are in use, A = XNORESRC then
;; Uses: A, X, Y, JOYSIRTBL
;; See: <JOYSIRTBL>, <AD_CLNUP>, <ALLOCSIR>
AD_SETUP:
    lda #JOYSIRSIZ
    ldx #<JOYSIRTBL
    ldy #>JOYSIRTBL
    jsr ALLOCSIR
    bcc ADS010
    lda #<XNORESRC
    rts
ADS010:
    lda E_REG
    and #$7F                        ; 2 MHz
    ora #$43                        ; I/O space on, the boot ROM at $F000
    sta E_REG
    php
    sei
    lda D_ACR
    and #BITOFF5                    ; timer 2 one-shot
    sta D_ACR
    plp
    bit ENSEL
    bit ENSIO
    rts

;; The resources the joystick needs, in <ALLOCSIR>'s form: ENSIO ($0C), ENSEL ($0D) and the D VIA's timer 2 ($0E),
;; none with an interrupt handler. ALLOCSIR writes the ID bytes into it.
JOYSIRTBL:
    .byte $0C, 0, 0, 0, 0
    .byte $0D, 0, 0, 0, 0
    .byte $0E, 0, 0, 0, 0

;; The size of <JOYSIRTBL>.
JOYSIRSIZ = * - JOYSIRTBL

;; Puts RAM back at $C000 and $F000, at 2 MHz, and gives back the joystick's resources.
;; Uses: A, X, Y
;; See: <AD_SETUP>, <DEALCSIR>
AD_CLNUP:
    lda E_REG
    and #$3C
    sta E_REG
    lda #JOYSIRSIZ
    ldx #<JOYSIRTBL
    ldy #>JOYSIRTBL
    jsr DEALCSIR
    rts

;; Reads an analog input as a number from 0 to 255.
;;
;; It selects the input, charges the ramp's capacitor (with interrupts enabled meanwhile), then times the ramp with
;; the boot ROM's <ANALOG> routine. An interrupt while timing is let in and the timing goes on, or starts over if the
;; ramp ended meanwhile. The time is scaled down to 0-255. <AD_SETUP> must have run first.
;; In: A = the input, 0-7
;; Out: A = the reading
;; Uses: X, Y, AD_TEMP
;; Keeps: interrupt
;; See: <JOYSTICK>
AD_READ:
    lsr a                           ; set the three select switches
    bit AD_SEL0
    bcc ADR010
    bit AD_SEL0+1
ADR010:
    lsr a
    bit AD_SEL1
    bcc ADR020
    bit AD_SEL1+1
ADR020:
    lsr a
    bit AD_SEL2
    bcc ADR030
    bit AD_SEL2+1
ADR030:
    php
ADR040:
    cli
    bit AD_CHRG                     ; charge the capacitor
    lda #<TCHARGE
    sta D_T2
    lda #>TCHARGE
    sta D_T2+1
    lda #BITON5
ADR050:
    bit D_IFR
    beq ADR050
    sei
    sec
    lda #<TOFFSET
    sta D_T2
    lda #>TOFFSET
    bit AD_STRT
    jsr ANALOG                      ; time the ramp
    bcc ADR070
ADR060:
    cli                             ; interrupted: let the interrupt in
    sei
    bit AD_FLAG
    bpl ADR040                      ; the ramp ended meanwhile: start over
    jsr ANLOG1
    bcs ADR060
ADR070:
    plp
    eor #$FF                        ; the time elapsed, divided by 8 and rounded
    bmi ADR080
    sta AD_TEMP
    tya
    eor #$FF
    lsr AD_TEMP
    ror a
    lsr AD_TEMP
    ror a
    lsr AD_TEMP
    bne ADR090
    ror a
    adc #0
    rts
ADR080:
    lda #0
    rts
ADR090:
    lda #$FF
    rts

; ---------------------------------------------------------------------------------------------------------------------
; Cold start
; ---------------------------------------------------------------------------------------------------------------------

;; COLD_START: stops the system and asks the user to reboot.
;;
;; With interrupts off, NMIs made to return at once and the Reset key disabled, it fills $0100-$BFFF with blank
;; spaces in every bank from SYSBANK down to 0, which also clears the screen, selects 40-column black-and-white text
;; and shows "INSERT SYSTEM DISKETTE & REBOOT" in the middle of the screen. Then it enables the Reset key and waits
;; for the user to press Control-RESET. SOS also makes it the reset vector, at $FFFC.
;; See: <UMGR>, <INT_INIT>
COLDSTRT:
    sei
    lda #$40                        ; an RTI where the ROM's NMI handler jumps
    sta a:$FFCA
    lda #$67                        ; Reset disabled
    sta E_REG
    lda #$00
    sta Z_REG
    ldx SYSBANK
    lda #$BF
    ldy #$00
    sty MEMORY
CS010:
    sta MEMORY+1                    ; X = the bank
    stx B_REG
    lda #$A0
CS020:
    sta (MEMORY),y
    dey
    bne CS020
    dec MEMORY+1
    bne CS020
    dex
    bpl CS010
    ldy #6
CS030:
    sta a:$C050,y                   ; 40-column black-and-white text
    dey
    bpl CS030
    ldy #BOOTLEN
CS040:
    lda BOOTMSG-1,y
    sta BOOTADR-1,y
    dey
    bne CS040
    lda #$77                        ; Reset enabled
    sta E_REG
    jmp *

;; The message <COLDSTRT> shows.
BOOTMSG:
    .hiascii "INSERT SYSTEM DISKETTE & REBOOT"

;; The length of <BOOTMSG>.
BOOTLEN = * - BOOTMSG

;; Where <BOOTMSG> goes: centered on the screen's thirteenth line.
BOOTADR = (((40-BOOTLEN)/2)+$628)
ZZEND:
ZZLEN = ZZEND-ZZORG
    .assert ZZLEN == LENUMGR, "SOSORG gives the module another length"
