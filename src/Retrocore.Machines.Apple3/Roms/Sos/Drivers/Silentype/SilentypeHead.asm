; .SILENTYPE's mechanism layer: the printer's lines, its motors and head, and the bytes that drive them. Included by
; Silentype.asm.

; ---------------------------------------------------------------------------------------------------------------------
; The printer's lines and motors.
; ---------------------------------------------------------------------------------------------------------------------

;; Sends the printer 16 bits, <LATCHDOTS> and <LATCHPHASES>, through the D VIA's shift register, then strobes them in.
;; In: LATCHDOTS = the dots to heat, LATCHPHASES = the motors' phases
;; Uses: A
LATCH:
    lda AN1_OFF                         ; the strobe low
    lda E_REG
    pha
    ora #E_1MHZ
    sta E_REG
    lda LATCHDOTS
    sta D_SR
LATCH_1:
    lda D_IFR
    and #IFR_SR
    beq LATCH_1
    lda LATCHPHASES
    sta D_SR
LATCH_2:
    lda D_IFR
    and #IFR_SR
    beq LATCH_2
    lda AN2_ON                          ; the strobe: AN2 up, then a pulse on AN1
    lda AN1_ON
    nop
    lda AN1_OFF
    nop
    lda AN2_OFF
    pla
    sta E_REG
    rts

;; Steps the head right: rotates its phases right and sends them, with no dots and the paper motor off.
;; Uses: A
STEPRIGHT:
    lda a:HEADPHASE
    lsr a
    bcc STEPRIGHT_1
    ora #$08
STEPRIGHT_1:
    sta a:HEADPHASE

;; Sends the motors' phases, with no dots.
;; In: A = the phases
;; Uses: A
PHASEOUT:
    sta LATCHPHASES
    lda #$00
    sta LATCHDOTS
    jmp LATCH

;; Steps the head left: rotates its phases left and sends them.
;; Uses: A
STEPLEFT:
    lda a:HEADPHASE
    asl a
    cmp #$10
    bcc STEPRIGHT_1
    and #$0F
    ora #$01
    bne STEPRIGHT_1

;; Steps the paper forward: rotates its phases right and sends them, with the head motor off.
;; Uses: A
FEEDSTEP:
    lda a:PAPERPHASE
    lsr a
    bcc FEEDSTEP_1
    ora #$08
FEEDSTEP_1:
    sta a:PAPERPHASE

;; Sends the paper motor's phases.
;; In: A = the phases, in bits 0-3
;; Uses: A
PAPEROUT:
    asl a
    asl a
    asl a
    asl a
    bne PHASEOUT

;; Steps the paper back: rotates its phases left and sends them.
;; Uses: A
UNFEEDSTEP:
    lda a:PAPERPHASE
    asl a
    cmp #$10
    bcc FEEDSTEP_1
    and #$0F
    ora #$01
    bne FEEDSTEP_1

;; Holds the head motor alone a moment, then releases both motors, marking the head idle (<HEADIDLE>).
;; Uses: A
HEADOFF:
    lda a:HEADPHASE
    jsr PHASEOUT
    dec a:HEADIDLE
    jsr WAIT

;; Releases both motors.
;; Uses: A
MOTORSOFF:
    lda #$00
    sta LATCHPHASES
    sta LATCHDOTS
    jmp LATCH

;; Holds the paper motor alone a moment, then releases both motors.
;; Uses: A
PAPEROFF:
    lda a:PAPERPHASE
    jsr PAPEROUT
    jsr WAIT3
    jmp MOTORSOFF

;; Waits three times <WAITTIME>.
;; Uses: A
WAIT3:
    jsr WAIT
    jsr WAIT

;; Waits <WAITTIME> cycles.
;; Uses: A, DELAYTIME
WAIT:
    lda #>WAITTIME
    sta DELAYTIME+1
    lda #<WAITTIME
    sta DELAYTIME

;; Runs the D VIA's timer 2 for <DELAYTIME> cycles and waits for it.
;; In: DELAYTIME = the cycles
;; Uses: A
DELAY:
    lda DELAYTIME
    sta D_T2CL
    lda DELAYTIME+1
    sta D_T2CH
DELAY_1:
    lda D_IFR
    and #IFR_T2
    beq DELAY_1
    rts

; ---------------------------------------------------------------------------------------------------------------------
; Finding the margin, setting up the port, and printing a column.
; ---------------------------------------------------------------------------------------------------------------------

;; Finds the margin switch: steps the head left until the switch closes, then right until it opens, then a step more,
;; which is column 0.
;; Out: carry = set when the switch was not found, ERRCODE = XIOERROR then
;; Uses: A, X, Y, HOMETRIES, DOTS
FINDHOME:
    lda #HOMEPASSES
    sta HOMETRIES
    jsr GOLEFT
    lda #$00                            ; no dots while it searches
    sta DOTS
FINDHOME_1:
    ldy #HOMESTEPS
FINDHOME_2:
    jsr COLUMN
    lda MARGINSW                        ; at the margin switch?
    bmi FINDHOME_4
    dey
    bne FINDHOME_2
    dec HOMETRIES
    bne FINDHOME_1
FINDHOME_3:
    lda #XIOERROR
    sta ERRCODE
    sec
    rts
FINDHOME_4:
    jsr COLUMN                          ; one more step, then make sure
    jsr WAIT
    lda MARGINSW
    bpl FINDHOME_2
    jsr WAIT
    lda MARGINSW
    bpl FINDHOME_2
    jsr WAIT3
    ldy #$10                            ; move right off the switch, at most 17 steps
    jsr GORIGHT
FINDHOME_5:
    lda MARGINSW
    bpl FINDHOME_6
    jsr COLUMN
    dey
    bpl FINDHOME_5
    bmi FINDHOME_3
FINDHOME_6:
    jsr WAIT                            ; make sure it has let go
    lda MARGINSW
    bmi FINDHOME_5
    jsr WAIT
    lda MARGINSW
    bmi FINDHOME_5
    jsr WAIT
    lda MARGINSW
    bmi FINDHOME_5
    jsr COLUMN                          ; one step past it is column 0
    jsr HEADOFF
    lda #$00
    sta a:HEADPOS                       ; the head is at column 0
    sta a:HEADPOS+1
    clc
    rts

;; Sets the joystick port and the D VIA up for the printer: the shift register shifting out, the control lines, and
;; their interrupts off.
;; Uses: A
SETUPPORT:
    lda AN0_ON
    lda ENCSEL_ON
    lda ENSIO_ON
    lda AN1_ON
    lda AN2_OFF
    php
    sei
    lda D_ACR
    and #ACR_KEEP
    ora #ACR_SROUT
    sta D_ACR
    lda D_PCR
    and #PCR_KEEP
    ora #PCR_OPEN
    sta D_PCR
    lda #PORT_IRQS                      ; their interrupts off
    sta D_IER
    sta D_IFR                           ; and their flags clear
    plp
    rts

;; Steps the head a column in its direction and prints a column of dots there.
;; The dots heated in neither of the two columns before get <PREHEAT> alone first; then all heat for <HEATTIME>.
;; In: DOTS = the dots, the top dot in bit 7
;; Out: carry = clear
;; Uses: A, NEWDOTS, LATCHDOTS, LATCHPHASES, DELAYTIME
COLUMN:
    tya
    pha
    lda a:LASTCOL
    pha
    ora a:PREVCOL                       ; dots not fired in the last two columns
    eor #$FF
    and DOTS
    sta NEWDOTS
    pla
    sta a:PREVCOL
    lda DOTS
    sta a:LASTCOL
    lda a:DIRECTION
    bmi COLUMN_2
    jsr STEPRIGHT                       ; right
    inc a:HEADPOS
    bne COLUMN_1
    inc a:HEADPOS+1
COLUMN_1:
    jmp COLUMN_4
COLUMN_2:
    jsr STEPLEFT                        ; left
    lda a:HEADPOS
    bne COLUMN_3
    dec a:HEADPOS+1
COLUMN_3:
    dec a:HEADPOS
    lda DOTS
    beq COLUMN_4
    sec                                 ; each dotted column right to left shortens EXTRAHEAT
    lda a:EXTRAHEAT
    sbc #$04
    sta a:EXTRAHEAT
    bcs COLUMN_4
    dec a:EXTRAHEAT+1
COLUMN_4:
    lda NEWDOTS                         ; after STEPTIME, the new dots on
    sta LATCHDOTS
    lda a:HEADPHASE
    sta LATCHPHASES
    lda a:STEPTIME
    sta DELAYTIME
    lda a:STEPTIME+1
    sta DELAYTIME+1
    jsr DELAY
    jsr LATCH
    lda a:HEADPHASE
    sta LATCHPHASES
    lda DOTS
    sta LATCHDOTS
    beq COLUMN_6
    lda a:PREHEAT                       ; after PREHEAT, all the dots on
    sta DELAYTIME
    lda a:PREHEAT+1
    sta DELAYTIME+1
    lda a:HEADIDLE                      ; longer after the head was idle
    bpl COLUMN_5
    inc DELAYTIME+1
COLUMN_5:
    jsr DELAY
    jsr LATCH
COLUMN_6:
    lda #$00                            ; after HEATTIME and EXTRAHEAT, all off
    sta a:HEADIDLE
    sta LATCHDOTS
    lda a:HEADPHASE
    sta LATCHPHASES
    clc
    lda a:HEATTIME
    bit a:EXTRAHEAT+1
    bmi COLUMN_7
    adc a:EXTRAHEAT
COLUMN_7:
    sta DELAYTIME
    lda a:HEATTIME+1
    bit a:EXTRAHEAT+1
    bmi COLUMN_8
    adc a:EXTRAHEAT+1
COLUMN_8:
    sta DELAYTIME+1
    jsr DELAY
    jsr LATCH
    lda a:STEPTIME                      ; then STEPTIME before the next step
    sta DELAYTIME
    lda a:STEPTIME+1
    sta DELAYTIME+1
    jsr DELAY
    pla
    tay
    clc
    rts

; ---------------------------------------------------------------------------------------------------------------------
; The mechanism bytes.
; ---------------------------------------------------------------------------------------------------------------------

;; Carries out a mechanism byte.
;; In: INBYTE = the byte: <M_DOTS> a column of dots, <M_BACK> and <M_SPACE> moves of the head, <M_FEED> and
;;   <M_UNFEED> moves of the paper, and $40-$48 the orders in <MECHSW>
;; Out: carry = set for a byte that is an error
;; Uses: A, X, Y, DOTS, MOVEKIND, REPEATS
MECHBYTE:
    lda INBYTE
    asl a
    bcc MECHBYTE_2                      ; $00-$7F
    sta DOTS                            ; $80-$FF: a column of dots
    jsr COLUMN
MECHBYTE_1:
    clc
    rts
MECHBYTE_2:
    bmi MECHBYTE_10                     ; $40-$7F
    pha
    asl a
    sta MOVEKIND
    lda #$00
    sta DOTS
    pla
    lsr a                               ; the count, 0 for 64
    and #$0F
    bne MECHBYTE_3
    lda #64
MECHBYTE_3:
    sta REPEATS
MECHBYTE_4:
    bit MOVEKIND
    bmi MECHBYTE_6                      ; $20-$3F: the paper
    bvc MECHBYTE_5                      ; $00-$0F: against the head's direction
    jsr COLUMN                          ; $10-$1F: with it
    jmp MECHBYTE_8
MECHBYTE_5:
    jsr TURN
    jsr COLUMN
    jsr TURN
    jmp MECHBYTE_8
MECHBYTE_6:
    bvc MECHBYTE_9                      ; $20-$2F: forward
    jsr UNFEEDSTEP
MECHBYTE_7:
    jsr WAIT3
MECHBYTE_8:
    dec REPEATS
    bne MECHBYTE_4
    beq MECHBYTE_1
MECHBYTE_9:
    jsr FEEDSTEP
    jmp MECHBYTE_7
MECHBYTE_10:
    asl a
    bpl MECHBYTE_11
    clc                                 ; $60-$7F do nothing
    rts
MECHBYTE_11:
    lsr a
    tay
    cpy #MECHCOUNT*2
    bcs MECHBAD                         ; $49-$5F are errors
    lda MECHSW+1,y
    pha
    lda MECHSW,y
    pha
    rts

;; The routines for mechanism bytes $40-$48, less one.
MECHSW:
    .word MECH_RESET-1                  ; $40: set up the port and find the margin
    .word MECH_HOME-1                   ; $41: find the margin
    .word MECH_LEFT-1                   ; $42: move left from now on
    .word MECH_RIGHT-1                  ; $43: move right from now on
    .word MECH_TURN-1                   ; $44: turn around
    .word MECH_UNUSED-1                 ; $45: an error
    .word MECH_HEADOFF-1                ; $46: release the head motor
    .word MECH_PAPEROFF-1               ; $47: release the paper motor
    .word MECH_TEXT-1                   ; $48: back to text
    .assert * - MECHSW == MECHCOUNT*2

;; Returns the error of a bad mechanism byte.
;; Out: carry = set
MECHBAD:
    sec
    rts

;; Makes the head move left from now on.
;; Uses: A
GOLEFT:
    lda a:DIRECTION
    ora #DIR_LEFT

;; Stores the head's direction.
;; In: A = the direction
SETDIR:
    sta a:DIRECTION
    rts

;; Makes the head move right from now on.
;; Uses: A
GORIGHT:
    lda a:DIRECTION
    and #<(~DIR_LEFT)
    bpl SETDIR

;; Turns the head's direction around.
;; Uses: A
TURN:
    lda a:DIRECTION
    eor #DIR_LEFT
    jmp SETDIR

;; Mechanism byte $48: back to text, the head at the left margin.
;; Out: carry = clear
;; Uses: A, X, Y
MECH_TEXT:
    lda #IN_TEXT
    sta a:STATE
    jsr HOMEHEAD
    clc
    rts

;; Mechanism byte $41: finds the margin switch, the head then facing right.
;; Out: carry = set when it was not found
;; Uses: A, X, Y
MECH_HOME:
    jsr FINDHOME
    lda #$00
    sta a:DIRECTION
    bcs MECHBAD
    rts

;; Mechanism byte $46: releases the head motor.
;; Out: carry = clear
MECH_HEADOFF:
    jsr HEADOFF
    clc
    rts

;; Mechanism byte $47: releases the paper motor.
;; Out: carry = clear
MECH_PAPEROFF:
    jsr PAPEROFF
    clc
    rts

;; Mechanism byte $42: the head moves left from now on.
;; Out: carry = clear
MECH_LEFT:
    jsr GOLEFT
    clc
    rts

;; Mechanism byte $43: the head moves right from now on.
;; Out: carry = clear
MECH_RIGHT:
    jsr GORIGHT
    clc
    rts

;; Mechanism byte $44: turns the head around.
;; Out: carry = clear
MECH_TURN:
    jsr TURN
    clc
    rts

;; Mechanism byte $40: sets the port up and both motors' phases, and finds the margin switch.
;; Out: carry = set when it was not found
;; Uses: A, X, Y
MECH_RESET:
    jsr SETUPPORT
    lda #PHASE_START                    ; two phases on
    sta a:HEADPHASE
    sta a:PAPERPHASE
    bne MECH_HOME

;; Mechanism byte $45: an error.
;; Out: carry = set
MECH_UNUSED:
    sec
    rts
