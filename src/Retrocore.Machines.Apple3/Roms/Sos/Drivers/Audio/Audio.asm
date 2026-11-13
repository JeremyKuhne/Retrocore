;; SOS .AUDIO DRIVER 1.0
;;
;; The Apple III's sound driver: it plays notes on the 6-bit DAC, the low six bits of the E VIA's port B. A program
;; opens .AUDIO and writes notes to it, six bytes each (<NOTE>): a $80 mark, a volume, a period and a length. For each
;; note the driver runs the E VIA's timer 1 free at the note's half period and flips the DAC between two levels each
;; time it runs out, a square wave, while timer 2 counts the length in sixtieths of a second. A write returns when
;; its last note has played. The driver doesn't use the speaker ($C030) or the beep ($C040).
;;
;; Requests:
;;
;; - D_OPEN claims the sound port and the E VIA's two timers (<SIRTABLE>) and sets timer 1 free-running; D_CLOSE
;;   puts timer 1 back to one-shot and gives them back.
;; - D_WRITE plays notes (<AUDIO_WRITE>); D_READ returns XBADOP.
;; - D_STATUS 0, 1 and 2 report nothing, an empty configuration block and newline off; D_CONTROL 0 (reset) drops a
;;   partly written note, and 1 and 2 do nothing.
;; - D_INIT marks the device closed.
;;
;; One DIB, .AUDIO: device type $43, subtype $01, Apple's (manufacturer 1), release 1.0, with no
;; configuration block. The copyright text after the DIB is part of the code, not a SOS.DRIVER comment record.
;;
;; The names are ours; the standard parts follow the SOS Device Driver Writer's Guide
;; (https://archive.org/details/Apple_III_SOS_Device_Driver_Writers_Guide).
;;
;; Maintained by hand; SOS driver tests check it assembles byte-identically to Apple's .AUDIO 1.0.

.cpu Mos6502

;; Performs an N-way branch on a switch index, through a table of addresses less one.
;;
;; It loads the index (when given), checks it against the bounds (when given; carry set and falling through when
;; it is larger), then pushes the table entry and returns to it. With `*` as the fourth parameter it pushes the
;; address but falls through instead.
;; Parameters: index = the index's location, or blank for A, bounds = the largest index, or blank for no check,
;;   table = the table of addresses less one, low byte first, stay = `*` to fall through
.macro SWITCH index, bounds, table, stay
    .local M010
    .ifnblank index
    lda index
    .endif
    .ifnblank bounds
    cmp #<(bounds+$01)
    bcs M010
    .endif
    asl a
    tay
    lda table+$01,y
    pha
    lda table,y
    pha
    .if .not .xmatch({stay}, {*})
    rts
    .endif
M010:
.endmacro

; ---------------------------------------------------------------------------------------------------------------------
; SOS: the kernel's calls and error codes, and the request block in zero page.
; ---------------------------------------------------------------------------------------------------------------------

;; Allocates system internal resources: A = the table's length, X/Y = its address.
ALLOCSIR = $1913

;; Releases system internal resources: A = the table's length, X/Y = its address.
DEALCSIR = $1916

;; Returns an error from the SOS call: A = the error code. It doesn't return.
SYSERR = $1928

XREQCODE = $20                          ;; the request code is invalid
XCTLCODE = $21                          ;; the control or status code is invalid
XNOTOPEN = $23                          ;; the device is not open
XNOTAVAIL = $24                         ;; the device is not available
XNORESRC = $25                          ;; a resource the driver needs is not available
XBADOP = $26                            ;; the operation is invalid

D_READ = 0                              ;; request: read
D_WRITE = 1                             ;; request: write
D_STATUS = 2                            ;; request: status
D_CONTROL = 3                           ;; request: control
D_OPEN = 6                              ;; request: open
D_CLOSE = 7                             ;; request: close
D_INIT = 8                              ;; request: initialize, at boot

;; The request block SOS passes to a driver, in zero page.
SOSINT = $C0

REQCODE = SOSINT+$00                    ;; the request code
BUFFER = SOSINT+$02                     ;; read/write: the buffer's address, with its extension byte at $1400+BUFFER+1
REQCNT = SOSINT+$04                     ;; read/write: the byte count
CTLSTAT = SOSINT+$02                    ;; status/control: the code
CSLIST = SOSINT+$03                     ;; status/control: the list's address

;; The DAC bits a note flips: its volume, 0-63.
TOGGLE = SOSINT+$0A

;; The note's length in sixtieths, low byte; the count left of the current 256.
TICKS = SOSINT+$0B

;; The note's length in sixtieths, high byte; the count of 256s left.
TICKSHI = SOSINT+$0C

; ---------------------------------------------------------------------------------------------------------------------
; Hardware: the E VIA, whose port B drives the DAC, and its timers.
; ---------------------------------------------------------------------------------------------------------------------

;; The E VIA's port B: the DAC in bits 0-5.
E_IORB = $FFE0

;; The E VIA's timer 1 counter, low byte (writing sets the latch).
E_T1CL = $FFE4

;; The E VIA's timer 1 counter, high byte (writing loads the counter and starts it).
E_T1CH = $FFE5

;; The E VIA's timer 2 counter, low byte (writing sets the latch).
E_T2CL = $FFE8

;; The E VIA's timer 2 counter, high byte (writing loads the counter and starts it).
E_T2CH = $FFE9

;; The E VIA's auxiliary control register: bits 5-7 set the timers' modes.
E_ACR = $FFEB

;; The E VIA's interrupt flags: bit 6 timer 1, bit 5 timer 2; writing ones clears them.
E_IFR = $FFED

ACR_TIMERS = $1F                        ;; the auxiliary control bits that keep the timers' modes out
ACR_T1FREE = $40                        ;; timer 1 free-running, without PB7
IFR_T2 = $20                            ;; timer 2's interrupt flag
IFR_T1 = $40                            ;; timer 1's interrupt flag

;; The cycles in a sixtieth of a second at the VIAs' 1.02 MHz: timer 2's count for each tick of a note.
TICK_CYCLES = $4274

;; The longest note, in sixtieths: five seconds.
MAX_TICKS = 300

;; The shortest half period timer 1 is given, so the driver keeps up with it.
MIN_PERIOD = 100

;; The longest half period, and the one a silent note gets.
MAX_PERIOD = $3FFF

;; The byte that starts each note in the data a program writes.
NOTE_MARK = $80

; ---------------------------------------------------------------------------------------------------------------------
; The device information block.
; ---------------------------------------------------------------------------------------------------------------------

;; .AUDIO's device information block: the only device this driver has.
AUDIO_DIB:
    .word $0000                         ; no next DIB
    .word AUDIO_MAIN                    ; the entry point
    .byte 6                             ; the name's length
    .byte ".AUDIO         "
    .byte $80                           ; active
    .byte $00, $00                      ; slot and unit
    .byte $43                           ; the device type
    .byte $01                           ; the subtype
    .byte $00
    .word $0000                         ; no blocks
    .word $0001                         ; the manufacturer: Apple
    .word $1000                         ; the release: 1.0
    .word $0000                         ; no configuration block
    .byte "(C) 1980 by Apple Computer Inc."

; ---------------------------------------------------------------------------------------------------------------------
; The driver's data.
; ---------------------------------------------------------------------------------------------------------------------

;; Bit 7 set while .AUDIO is open.
OPENFLG:
    .byte $00

;; The address of <SIRTABLE>, for <ALLOCSIR> and <DEALCSIR>.
SIRADDR:
    .word SIRTABLE

;; The system internal resources the driver claims while open, with no interrupt handlers: the sound port, and the
;; E VIA's timer 2 and timer 1. Each entry is the resource, the ID byte, and the handler's address and bank.
SIRTABLE:
    .byte $00, $00                      ; the sound port
    .word $0000
    .byte $00
    .byte $07, $00                      ; the E VIA's timer 2
    .word $0000
    .byte $00
    .byte $08, $00                      ; the E VIA's timer 1
    .word $0000
    .byte $00
SIRCOUNT = * - SIRTABLE                 ;; the table's length in bytes

;; The count of a note's bytes collected in <NOTE>.
NOTECOUNT:
    .byte $00

;; The note being collected from the data a program writes: six bytes, <NOTE_MARK> first.
NOTE:
    .byte $00
;; The note's volume: the DAC bits it flips, in bits 0-5 (0 is silent).
NOTE_VOLUME:
    .byte $00
;; The note's half period in VIA cycles, low byte first: the tone is 1.02 MHz / (2 x (period + 2)).
NOTE_PERIOD:
    .word $0000
;; The note's length in sixtieths of a second, low byte first.
NOTE_TICKS:
    .word $0000

; ---------------------------------------------------------------------------------------------------------------------
; The requests.
; ---------------------------------------------------------------------------------------------------------------------

;; The driver's entry point: goes to the request's routine.
;; In: REQCODE = the request
;; See: <REQSTSW>
AUDIO_MAIN:
    SWITCH REQCODE, D_INIT, REQSTSW

;; Fails the request: its code is not one SOS has.
BADREQ:
    lda #XREQCODE
    jsr SYSERR

;; Fails the request: .AUDIO is not open.
NOTOPEN:
    lda #XNOTOPEN
    jsr SYSERR

;; The request routines' addresses less one, by request code.
REQSTSW:
    .word AUDIO_READ-1                  ; D_READ
    .word AUDIO_WRITE-1                 ; D_WRITE
    .word AUDIO_STATUS-1                ; D_STATUS
    .word AUDIO_CONTROL-1               ; D_CONTROL
    .word BADREQ-1                      ; 4
    .word BADREQ-1                      ; 5
    .word AUDIO_OPEN-1                  ; D_OPEN
    .word AUDIO_CLOSE-1                 ; D_CLOSE
    .word AUDIO_INIT-1                  ; D_INIT

;; Initializes the driver at boot: .AUDIO starts closed.
;; Out: carry = clear
;; Uses: A
AUDIO_INIT:
    lda #$00
    sta a:OPENFLG
    clc
    rts

;; Opens .AUDIO: claims the sound port and the E VIA's timers, and sets timer 1 free-running.
;; Out: OPENFLG = $80
;; Errors: XNOTAVAIL = already open, XNORESRC = a resource is taken
;; Uses: A, X, Y
AUDIO_OPEN:
    bit a:OPENFLG
    bpl AUDIO_OPEN_1
    lda #XNOTAVAIL
    jsr SYSERR
AUDIO_OPEN_1:
    lda #SIRCOUNT
    ldx a:SIRADDR
    ldy a:SIRADDR+1
    jsr ALLOCSIR
    bcs AUDIO_OPEN_2
    php
    sei
    lda E_ACR
    and #ACR_TIMERS
    ora #ACR_T1FREE
    sta E_ACR
    plp
    jsr CTL_RESET
    lda #$80
    sta a:OPENFLG
    rts
AUDIO_OPEN_2:
    lda #XNORESRC
    jsr SYSERR

;; Closes .AUDIO: puts timer 1 back to one-shot, clears both timers' flags and gives the resources back.
;; Out: OPENFLG = 0
;; Errors: XNOTOPEN = not open
;; Uses: A, X, Y
AUDIO_CLOSE:
    asl a:OPENFLG
    bcs AUDIO_CLOSE_1
    jmp NOTOPEN
AUDIO_CLOSE_1:
    php
    sei
    lda E_ACR
    and #ACR_TIMERS
    sta E_ACR
    lda #IFR_T1 | IFR_T2
    sta E_IFR
    plp
    lda #SIRCOUNT
    ldx a:SIRADDR
    ldy a:SIRADDR+1
    jsr DEALCSIR
    rts

;; Fails a read: .AUDIO can only be written.
;; Errors: XNOTOPEN = not open, XBADOP = open
AUDIO_READ:
    bit a:OPENFLG
    bmi AUDIO_READ_1
    jmp NOTOPEN
AUDIO_READ_1:
    lda #XBADOP
    jsr SYSERR

;; Plays the notes in the caller's buffer, collecting them six bytes at a time into <NOTE>.
;;
;; Bytes before a note's <NOTE_MARK> are skipped, and a note the buffer ends in the middle of is finished by the next
;; write. Each note plays (<PLAYNOTE>) as soon as its sixth byte arrives.
;; In: BUFFER = the notes, REQCNT = their length in bytes
;; Errors: XNOTOPEN = not open
;; Uses: A, X, Y, BUFFER, REQCNT, TOGGLE, TICKS, TICKSHI
AUDIO_WRITE:
    bit a:OPENFLG
    bmi AUDIO_WRITE_1
    jmp NOTOPEN
AUDIO_WRITE_1:
    lda REQCNT
    ora REQCNT+1
    beq AUDIO_WRITE_5                   ; every byte taken
    ldy #$00
    lda (BUFFER),y
    inc BUFFER
    bne AUDIO_WRITE_2
    inc BUFFER+1
    bne AUDIO_WRITE_2
    inc $1400+BUFFER+1                  ; past the bank's end: the next bank, at $8000
    lda #$80
    sta BUFFER+1
AUDIO_WRITE_2:
    ldx REQCNT
    bne AUDIO_WRITE_3
    dec REQCNT+1
AUDIO_WRITE_3:
    dec REQCNT
    ldy a:NOTECOUNT
    bne AUDIO_WRITE_4
    cmp #NOTE_MARK
    bne AUDIO_WRITE_1                   ; not a note's start: skip it
AUDIO_WRITE_4:
    sta NOTE,y
    iny
    sty a:NOTECOUNT
    cpy #6
    bcc AUDIO_WRITE_1
    jsr PLAYNOTE
    ldy #$00
    sty a:NOTECOUNT
    beq AUDIO_WRITE_1                   ; always
AUDIO_WRITE_5:
    rts

;; Plays the note in <NOTE> on the DAC, returning when its length has passed.
;;
;; The length is held to <MAX_TICKS>, and a zero length plays nothing. The half period is held to <MIN_PERIOD> through
;; <MAX_PERIOD>, and a silent note waits out its length at <MAX_PERIOD>. The DAC rests at $3F and flips its volume's
;; bits each time timer 1 runs out; timer 2 is reloaded by adding to its count, so the ticks keep time however late
;; the loop sees them. Interrupts are off except for a moment each pass, and the DAC is left at rest. A length whose
;; low byte is 0 plays 256 sixtieths longer: 256 plays as 512.
;; In: NOTE_VOLUME, NOTE_PERIOD, NOTE_TICKS
;; Uses: A, X, Y, TOGGLE, TICKS, TICKSHI
PLAYNOTE:
    ldx a:NOTE_TICKS+1
    bne PLAYNOTE_1
    lda a:NOTE_TICKS
    bne PLAYNOTE_3
    rts                                 ; no length
PLAYNOTE_1:
    cpx #(>MAX_TICKS)+1
    bcs PLAYNOTE_2
    lda a:NOTE_TICKS
    cmp #<(MAX_TICKS+1)
    bcc PLAYNOTE_3
PLAYNOTE_2:
    lda #<MAX_TICKS
    ldx #>MAX_TICKS
PLAYNOTE_3:
    sta TICKS
    stx TICKSHI
    lda a:NOTE_VOLUME
    and #$3F
    sta TOGGLE
    beq PLAYNOTE_4                      ; silent
    lda a:NOTE_PERIOD
    ldx a:NOTE_PERIOD+1
    beq PLAYNOTE_5
    cpx #>(MAX_PERIOD+1)
    bcc PLAYNOTE_6
PLAYNOTE_4:
    lda #<MAX_PERIOD
    ldx #>MAX_PERIOD
    bne PLAYNOTE_6                      ; always
PLAYNOTE_5:
    cmp #MIN_PERIOD
    bcs PLAYNOTE_6
    lda #MIN_PERIOD
PLAYNOTE_6:
    sei
    sta E_T1CL
    stx E_T1CH                          ; start the half periods
    lda #<TICK_CYCLES
    ldx #>TICK_CYCLES
    sta E_T2CL
    stx E_T2CH                          ; start the first tick
    ldy TICKS
    lda #$FF
    eor TOGGLE
    sta E_IORB
    ldx #IFR_T1
PLAYNOTE_7:
    cli                                 ; let a waiting interrupt in
    sei
    lda #IFR_T2
    bit E_IFR
    bvc PLAYNOTE_8                      ; timer 1 hasn't run out
    stx E_IFR
    php
    lda E_IORB
    eor TOGGLE
    sta E_IORB                          ; flip the DAC
    plp
PLAYNOTE_8:
    beq PLAYNOTE_7                      ; the tick isn't over
    clc
    lda E_T2CL
    adc #<TICK_CYCLES
    sta E_T2CL
    lda E_T2CH
    adc #>TICK_CYCLES
    sta E_T2CH                          ; the next tick
    dey
    bne PLAYNOTE_7
    dec TICKSHI
    bpl PLAYNOTE_7
    cli
    lda #$FF
    sta E_IORB                          ; the DAC at rest
    rts

;; Answers a status request: code 0 reports nothing, 1 an empty configuration block, 2 newline off.
;; In: CTLSTAT = the status code, CSLIST = where to put the answer
;; Errors: XNOTOPEN = not open, XCTLCODE = another code
;; Uses: A, Y
AUDIO_STATUS:
    bit a:OPENFLG
    bmi AUDIO_STATUS_1
    jmp NOTOPEN
AUDIO_STATUS_1:
    SWITCH CTLSTAT, 2, STATSW

;; Fails a status or control request: the code is not one .AUDIO has.
BADCTL:
    lda #XCTLCODE
    jsr SYSERR

;; The status routines' addresses less one, by status code.
STATSW:
    .word STAT_NONE-1                   ; 0: status
    .word STAT_DCB-1                    ; 1: the configuration block
    .word STAT_NEWLINE-1                ; 2: newline mode

;; Status 0: nothing to report.
STAT_NONE:
    rts

;; Status 1: the configuration block, which is empty.
;; Out: (CSLIST) = 0, its length
;; Uses: A, Y
STAT_DCB:
    ldy #$00
    lda #$00
    sta (CSLIST),y
    rts

;; Status 2: newline mode, which is off.
;; Out: (CSLIST) = 0
;; Uses: A, Y
STAT_NEWLINE:
    ldy #$00
    lda #$00
    sta (CSLIST),y
    rts

;; Answers a control request: code 0 drops a partly written note, and 1 and 2 do nothing.
;; In: CTLSTAT = the control code
;; Errors: XNOTOPEN = not open, XCTLCODE = another code
;; Uses: A, Y
AUDIO_CONTROL:
    bit a:OPENFLG
    bmi AUDIO_CONTROL_1
    jmp NOTOPEN
AUDIO_CONTROL_1:
    SWITCH CTLSTAT, 2, CNTLSW
    jmp BADCTL

;; The control routines' addresses less one, by control code.
CNTLSW:
    .word CTL_RESET-1                   ; 0: reset
    .word CTL_DCB-1                     ; 1: set the configuration block
    .word CTL_NEWLINE-1                 ; 2: set newline mode

;; Control 0: resets the driver, dropping a partly collected note.
;; Out: NOTECOUNT = 0
;; Uses: A
CTL_RESET:
    lda #$00
    sta a:NOTECOUNT
    rts

;; Control 1: there is no configuration block to set.
CTL_DCB:
    rts

;; Control 2: newline mode isn't kept.
CTL_NEWLINE:
    rts
