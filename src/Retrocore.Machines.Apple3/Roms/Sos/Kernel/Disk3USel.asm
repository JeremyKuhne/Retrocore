; DISK3, continued: selecting and starting a drive, and working out how long its motor needs to come up to speed.

;; Selects the request's drive and starts its motor, setting how long to wait for it to come up to speed.
;;
;; The wait depends on the request (<MTIMES>: 200 milliseconds for a read, a second for a write, 50 for status) less
;; the time the motor has already been on (<UPTIME>). When no motor is turning, every drive is deselected and the
;; full wait applies. When this drive was not the selected one, its motor counts as stopped; for an external drive
;; the other external drives are deselected too, since they share the select lines, and if one of them was selected
;; <SEEKWAIT> asks for a pause before the next seek. The built-in drive's motor is left alone when an external one
;; starts, and the other way round. If there is a wait, it spends 50 milliseconds of it here, so that <CHKDRV>
;; sees a turning motor reliably afterwards.
;; In: D_UNITNUM = the drive, D_COMMAND = the request (0-2), 1 MHz
;; Out: MONTIMEL/MONTIMEH = minus the time still to wait, SEEKWAIT, DRIVESEL,Y = 1 for the drive
;; Uses: A, X, Y
;; See: <MAIN>, <SECTORIO>, <EXTDESEL>, <ADDTIME>
UNITSEL:
    ldy D_UNITNUM
    lda #0
    sta SEEKWAIT
    sta MONTIMEL
    sta MONTIMEH
    jsr CHKDRV
    bne SPINNING
    ldx MD_INT                          ; nothing turning: deselect every drive and start afresh
    lda #0
    sta DRIVESEL+0
    sta UPTIME+0
    jsr EXTDESEL
    jmp SETTIME
SPINNING:
    lda DRIVESEL,y
    bne GOFORIT                         ; our motor is the one turning
    cpy #0
    beq SETTIME                         ; the built-in drive: leave the external motor alone
    lda #0
    ora DRIVESEL+3
    ora DRIVESEL+2
    ora DRIVESEL+1
    beq SETTIME
    inc SEEKWAIT                        ; another external drive was running: stop it, and pause before seeking
    jsr EXTDESEL
    jmp SETTIME
GOFORIT:
    ldx D_COMMAND
    lda MTIMES,x
    sec
    sbc UPTIME,y                        ; the time still needed, if any
    bcs SELECT
    lda #0
    jmp SELECT
SETTIME:
    lda #0
    sta UPTIME,y                        ; the motor starts from rest
    ldx D_COMMAND
    lda MTIMES,x
SELECT:
    sta MONTIMEH
    lda #0
    sec
    sbc MONTIMEH                        ; negated: the ROM's MSWAIT counts it up to 0
    sta MONTIMEH
    cpy #1
    bcs SELEXT
    lda IS_INT
    lda MS_INT
    jmp UNITRET
SELEXT:
    lda IS_EXT
    cpy #2
    bcs NOTD2
    lda MD_EXT1                         ; .D2
    lda MS_EXT2
    jmp UNITRET
NOTD2:
    bne ISD4
    lda MS_EXT1                         ; .D3
    lda MD_EXT2
    jmp UNITRET
ISD4:
    lda MS_EXT1                         ; .D4
    lda MS_EXT2
UNITRET:
    lda MOTORON
    lda #1
    sta DRIVESEL,y
    lda MONTIMEH
    bpl UNITRTS                         ; no wait needed
    ldy #5                              ; 5 x 10 ms
UNITDEL:
    lda #100
    jsr MSWAIT
    dey
    bne UNITDEL
    lda #2
    jsr ADDTIME
UNITRTS:
    rts

;; Deselects every external drive's motor and marks .D2-.D4 as not selected and stopped.
;; Out: A = 0, X = 0
;; Keeps: Y
;; See: <UNITSEL>, <DRIVESEL>, <UPTIME>
EXTDESEL:
    lda MD_EXT1
    lda MD_EXT2
    ldx #3
    lda #0
EDS1:
    sta DRIVESEL,x
    sta UPTIME,x
    dex
    bne EDS1
    rts
    .include "Disk3Subs.asm"
