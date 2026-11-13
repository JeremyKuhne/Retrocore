; Formatting a disk: selecting the drive, and writing and checking each track. Included by Fmtd1.asm.

;; Moves the head to a track, counting in whole tracks where the ROM's <SEEK> counts in half tracks.
;; In: A = the track, X = the slot times 16, CURTRK = the track the head is on
;; Out: CURTRK = the track
;; Uses: A, Y, TRKN
MYSEEK:
    asl a
    asl CURTRK
    sta TRKN
    txa
    lsr a
    lsr a
    lsr a
    lsr a
    tay                                 ; the slot
    lda TRKN
    jsr SEEK
    lsr CURTRK
    rts

;; Checks that the formatter can start: it always can.
;; Out: A = 0
FMTSTARTUP:
    lda #$00
    rts

;; Formats the disk in a drive: writes and verifies its 35 tracks with copies of the sector image.
;;
;; It selects the drive, switches to 1 MHz with the ROM in, saves the ROM's zero page ($80-$9F) and extension bytes
;; ($1480-$149F), starts the motor, and encodes the sector image while the motor comes up to speed and the head goes
;; back to track 0. With interrupts off it writes each track (<WT16>), checks that the drive's speed kept the gaps
;; between <DCB_MINSYNC> and <DCB_MAXSYNC>, and finds sector 0 again to line the next track up. It then stops the
;; motor, returns the head to track 0, and restores what it saved and the caller's interrupt flag and environment.
;; In: X = the drive, 1-4, USERBUF = the sector image's address and extension byte
;; Out: A = 0 = formatted, 1 = the disk won't format, 2 = write-protected, 3 = the drive is too slow,
;;   4 = the drive is too fast
;; Uses: X, Y
;; See: <FORMTRK>
DSKFORM:
    ldy a:SEL1,x                        ; select the drive
    lda $C000,y
    ldy a:SEL2,x
    lda $C000,y
    ldy a:SEL3,x
    lda $C000,y
    cpx #$01
    bne DSKFORM_030
    lda $C0EA                           ; the built-in drive
    jmp DSKFORM_032
DSKFORM_030:
    lda $C0EB                           ; an external drive
DSKFORM_032:
    lda E_REG
    sta a:E_SAVE
    ora #$83                            ; 1 MHz, the ROM in
    sta E_REG
    php
    pla
    sta a:P_SAVE
    ldx #31
DSKFORM_035:
    lda $1480,x
    sta a:XTNDSAVE,x
    lda $80,x
    sta a:ZEROSAVE,x
    dex
    bpl DSKFORM_035
    ldx #$60
    stx IBSLOT
    lda MOTORON,x
    lda E_REG
    and #$7F                            ; 2 MHz while the image is encoded; PRENIB16 returns at 1 MHz
    sta E_REG
    lda a:USERBUF
    sta BUF
    lda a:USERBUF+$01
    sta BUF+$01
    lda a:USERBUF+$02
    sta $1400+BUF+$01
    jsr PRENIB16
    lda #$D7                            ; nearly a second for the motor
    sta MONTIME+$01
    lda #80                             ; the head can be anywhere: step out far enough to reach track 0
    sta CURTRK
    lda #$00
    jsr MYSEEK

;; Waits for the motor to come up to speed.
WAITUP:
    lda MONTIME+$01
    beq WAITUP_040
    jsr MSWAIT
    jmp WAITUP
WAITUP_040:
    sei
    lda #$00
    sta INTRTRY
    lda #$80                            ; interrupts stay off in the ROM's routines
    sta IMASK
    lda #$01
    sta NVOL
    lda #$AA
    sta AA
    lda a:DCB_MAXSYNC
    clc
    adc #$02                            ; start with gaps too large; WT16 shrinks them
    sta NSYNC
    lda #$00
    sta TRK

;; Formats the next track: checks write protection, writes and verifies it, checks the drive's speed, and finds
;; sector 0 so that the next track starts in line with it.
FORMTRK:
    lda TRK
    ldx #$60
    jsr MYSEEK
    ldx #$60
    lda Q6H,x                           ; sense write protection
    lda Q7L,x
    tay
    lda Q7L,x
    lda Q6L,x
    tya
    bpl FORMTRK_010
    lda #$02                            ; write-protected
    jmp FORMDONE
FORMTRK_010:
    jsr WT16
    bcc FORMTRK_020
    lda #$01                            ; the disk won't format, unless the gaps shrank too far
    ldy NSYNC
    cpy a:DCB_MINSYNC
    bcs FORMTRK_015
    lda #$04                            ; too fast
FORMTRK_015:
    jmp FORMDONE
FORMTRK_020:
    ldy NSYNC
    cpy a:DCB_MINSYNC
    bcs FORMTRK_025
    lda #$04                            ; too fast
    jmp FORMDONE
FORMTRK_025:
    cpy a:DCB_MAXSYNC
    bcc FORMTRK_030
    lda #$03                            ; too slow
    jmp FORMDONE
FORMTRK_030:
    lda a:DCB_SECTRETRY
    sta RETRYCNT

;; Reads address fields until sector 0's, then its data field, to stand just past sector 0 for the next track.
FINDS0:
    dec RETRYCNT
    bne FINDS0_010
    lda #$01                            ; the disk won't format
    jmp FORMDONE
FINDS0_010:
    ldx #$60
    jsr RDADR16
    bcs FINDS0
    lda SECT
    bne FINDS0
    ldx #$60
    jsr READ16
    bcs FINDS0
    inc TRK
    lda TRK
    cmp #35
    bcc FORMTRK
    lda #$00                            ; formatted

;; Finishes a format: stops the motor, returns the head to track 0, and restores the ROM's zero page and extension
;; bytes and the caller's interrupt flag and environment.
;; In: A = the result
;; Out: A = the result
FORMDONE:
    pha
    ldx #$60
    lda MOTOROFF,x
    lda #$00
    jsr MYSEEK
    ldx #31
FORMDONE_035:
    lda a:XTNDSAVE,x
    sta $1480,x
    lda a:ZEROSAVE,x
    sta $80,x
    dex
    bpl FORMDONE_035
    lda a:P_SAVE
    pha
    plp
    lda a:E_SAVE
    sta E_REG
    pla
    rts
