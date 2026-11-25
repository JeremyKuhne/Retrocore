;; THE CARD'S FIRMWARE: THE 3.5 DRIVES: FINDING THEM, THEIR DISKS, THE HEAD, THE SWIM'S MODES AND THE DRIVE LINES

;; Finds the 3.5 drives on the card's own port: drive 1, then drive 2 if drive 1 is there. Each is
;; identified and its disk, if any, read for its format; a drive whose disk cannot be read has it ejected.
;; Out:   UnitCount = the drives found (0-2), DeviceKinds set for each
FINDDRIVES:
    jsr MFMOFF
    ldx #$00
FINDDRIVES_1:
    stx SavedDrive
    stx Drive
    jsr DETECTDRIVE
    bcs FINDDRIVES_4
    ora #$01
    sta DeviceKinds,X
    lda #$03
    jsr DRIVECOMMAND
    jsr SENSELINES
    bvc FINDDRIVES_2
    jsr FORGETDISK
    bra FINDDRIVES_3
FINDDRIVES_2:
    clc
    jsr IDENTIFYMEDIA
    bcc FINDDRIVES_3
    ldx SavedDrive
    jsr EJECT
FINDDRIVES_3:
    jsr MFMOFF
    ldx SavedDrive
    inx
    cpx #$02
    bcc FINDDRIVES_1
FINDDRIVES_4:
    stx UnitCount
    txa
    beq FINDDRIVES_5
    dex
    jsr RELEASEDRIVE
FINDDRIVES_5:
    rts

;; Checks that a 3.5 drive answers on a drive line: its step direction must follow the commands.
;; In:    X = the drive (0 or 1)
;; Out:   carry = set if there is no drive; else A = 0 for an Apple 3.5 Drive, 2 for an FDHD (SuperDrive)
DETECTDRIVE:
    jsr PORTON
    lda Iwm::SelectDrive1,X
    bit Iwm::DataLatch
    bit Iwm::ReadMode
    bit Iwm::MotorOn
    lda #$01
    jsr DRIVECOMMAND
    lda #$00
    jsr DRIVESENSE
    bcc DETECTDRIVE_1
    lda #$00
    jsr DRIVECOMMAND
    lda #$00
    jsr DRIVESENSE
    bcs DETECTDRIVE_1
    lda #$01
    jsr DRIVECOMMAND
    lda #$00
    jsr DRIVESENSE
    bcc DETECTDRIVE_1
    lda #$05
    jsr DRIVESENSE
    bcc DETECTDRIVE_2
    lda #$02
    clc
    rts
DETECTDRIVE_1:
    sec
DETECTDRIVE_2:
    rts

;; Finds a double-density disk's format: GCR 400K or 800K from an address field's format byte, and
;; on an FDHD drive MFM 720K if no GCR field reads.
;; In:    X = the drive
;; Out:   carry = set if no format was found; else MediaKind, BlockCount/HI and MediaMode set
IDENTIFYDD:
    stx SavedDrive
    lda #$04
    sta Retries
    jsr WAITREADYEVER
IDENTIFYDD_1:
    stz Side
    jsr READADDRESS
    bcc IDENTIFYDD_4
    lda DiskErrors
    bit #$20
    bne IDENTIFYDD_2
    bit #$04
    beq IDENTIFYDD_3
    lda AddressTrack
    sta Track
IDENTIFYDD_2:
    dec Retries
    bne IDENTIFYDD_1
    bra IDENTIFYDD_MFM
IDENTIFYDD_3:
    bit #$01
    bne IDENTIFYDD_MFM
    sec
    rts
IDENTIFYDD_4:
    ldx SavedDrive
    jsr READSENSE
    ldy #$04
    lda LastFormatByte,X
    and #$1F
    cmp #$02
    bne IDENTIFYDD_5
    ldy #$06
IDENTIFYDD_5:
    bit DiskSides,X
    bmi IDENTIFYDD_6
    lda Sense,X
    ora #$10
    sta Sense,X
    ldy #$02
IDENTIFYDD_6:
    lda MEDIABLOCKS,Y
    sta BlockCount,X
    lda MEDIABLOCKS+1,Y
    sta BlockCountHigh,X
    lda Sense,X
    and #$BF
    sta Sense,X
    lda MediaMode,X
    and #$94
    ora MODEFLAGS,Y
    sta MediaMode,X
    sty MediaKind,X
    clc
    rts
IDENTIFYDD_MFM:
    ldx SavedDrive
    lda #$02
    bit DeviceKinds,X
    beq IDENTIFYDD_9
    lda #$06
    jsr DRIVECOMMAND
    lda #$0B
    jsr DELAY2
    jsr MFMON
    lda #$07
    jsr DRIVESENSE
    bcc IDENTIFYDD_MFM
    jsr WAITREADYEVER
    stz Track
    lda #$04
    sta Retries
IDENTIFYDD_7:
    stz Side
    jsr READADDRESS
    bcc IDENTIFYDD_10
    lda DiskErrors
    bit #$20
    bne IDENTIFYDD_8
    bit #$04
    beq IDENTIFYDD_8
    lda AddressTrack
    sta Track
IDENTIFYDD_8:
    dec Retries
    bne IDENTIFYDD_7
    lda #$07
    jsr DRIVECOMMAND
    lda #$0B
    jsr DELAY2
IDENTIFYDD_9:
    jsr MFMOFF
    ldx SavedDrive
    lda MediaMode,X
    and #$9F
    sta MediaMode,X
    sec
    rts
IDENTIFYDD_10:
    jsr LEAVEISM
    ldx SavedDrive
    jsr READSENSE
    ldy #$08
    lda MEDIABLOCKS,Y
    sta BlockCount,X
    lda MEDIABLOCKS+1,Y
    sta BlockCountHigh,X
    lda Sense,X
    and #$BF
    sta Sense,X
    lda MODEFLAGS,Y
    sta MediaMode,X
    sty MediaKind,X
    clc
    rts

;; MediaMode for each MediaKind (even indexes; the odd bytes are not read).
MODEFLAGS:
    .byte $00, $00, $11, $88, $11, $88, $11, $88, $32, $09, $52, $12, $52, $12

;; Finds the format of the disk in a drive: on an FDHD drive with a high-density disk, MFM 1440K;
;; else IDENTIFYDD.
;; In:    X = the drive
;; Out:   carry = set with A = $2F (no disk) or $27 (unreadable); else clear
;; Keeps: A (when carry is clear)
IDENTIFYMEDIA:
    php
    pha
    stx SavedDrive
    jsr FORGETMEDIA
    lda #$02
    jsr DRIVESENSE
    bcc IDENTIFYMEDIA_1
    pla
    lda #$2F
    bra IDENTIFYMEDIA_8
IDENTIFYMEDIA_1:
    lda #$02
    bit DeviceKinds,X
    beq IDENTIFYMEDIA_6
    lda #$0F
    jsr DRIVESENSE
    bcs IDENTIFYMEDIA_6
    lda #$80
    sta DiskSides,X
    lda #$54
    ora MediaMode,X
    sta MediaMode,X
    lda Sense,X
    and #$BF
    sta Sense,X
    jsr RECALIBRATE
    jsr MFMON
    jsr MOTORON
    stz Side
    stz Track
    jsr WAITREADYEVER
    lda #$04
    sta Retries
IDENTIFYMEDIA_2:
    stz Side
    jsr READADDRESS
    bcc IDENTIFYMEDIA_4
    lda DiskErrors
    bit #$20
    bne IDENTIFYMEDIA_3
    bit #$04
    beq IDENTIFYMEDIA_3
    lda AddressTrack
    sta Track
IDENTIFYMEDIA_3:
    dec Retries
    bne IDENTIFYMEDIA_2
    bra IDENTIFYMEDIA_7
IDENTIFYMEDIA_4:
    jsr LEAVEISM
    ldx SavedDrive
    jsr READSENSE
    ldy #$0A
    lda MEDIABLOCKS,Y
    sta BlockCount,X
    lda MEDIABLOCKS+1,Y
    sta BlockCountHigh,X
    sty MediaKind,X
    clc
IDENTIFYMEDIA_5:
    pla
    plp
    rts
IDENTIFYMEDIA_6:
    jsr RECALIBRATE
    jsr MOTORON
    stz Side
    ldx SavedDrive
    jsr IDENTIFYDD
    bcc IDENTIFYMEDIA_5
IDENTIFYMEDIA_7:
    pla
    lda #$27
IDENTIFYMEDIA_8:
    plp
    sec
    rts

;; Records that a drive has no disk, and forgets its format and its cached sectors.
;; In:    X = the drive
FORGETDISK:
    lda #$40
    sta Sense,X

;; Forgets a drive's format: no blocks, an unknown track, and its cached sectors dropped.
;; In:    X = the drive
;; Keeps: X, Y
FORGETMEDIA:
    stz BlockCount,X
    stz BlockCountHigh,X
    lda MediaMode,X
    and #$80
    sta MediaMode,X
    lda #$FF
    sta CurrentTrack,X
    stz MediaKind,X
    phx
    phy
    jsr FORGETCACHE
    ply
    plx
    rts

;; Turns Drive's motor on, if it is off, and waits for it to come up to speed: 500 ms the first time
;; since its disk was found (Sense bit 0), else 100 ms.
MOTORON:
    lda #$08
    jsr DRIVESENSE
    bcc MOTORON_2
    jsr SETDRIVEMODE
    lda #$08
    jsr DRIVECOMMAND
    ldx Drive
    lda #$01
    bit Sense,X
    bne MOTORON_1
    ora Sense,X
    sta Sense,X
    lda #$C8
    jsr DELAY2
MOTORON_1:
    lda #$64
    jsr DELAYMS
MOTORON_2:
    rts

;; On an FDHD drive, sets the drive's MFM or GCR mode to suit its disk's MediaMode.
SETDRIVEMODE:
    ldx Drive
    lda #$02
    bit DeviceKinds,X
    beq SETDRIVEMODE_4
    ldy #$06
    lda #$60
    bit MediaMode,X
    bne SETDRIVEMODE_1
    iny
SETDRIVEMODE_1:
    lda #$07
    jsr DRIVESENSE
    bcs SETDRIVEMODE_2
    cpy #$07
    beq SETDRIVEMODE_4
    bra SETDRIVEMODE_3
SETDRIVEMODE_2:
    cpy #$06
    beq SETDRIVEMODE_4
SETDRIVEMODE_3:
    tya
    jsr DRIVECOMMAND
    lda #$07
SETDRIVEMODE_4:
    rts

;; Steps the head a number of tracks, in the direction already set, and lets it settle.
;; In:    X = the tracks
STEPTRACKS:
    lda #$04
    jsr DRIVECOMMAND
    lda #$04
    jsr WAITSENSE
    dex
    bne STEPTRACKS
    ldx #$3E
STEPTRACKS_1:
    dex
    bne STEPTRACKS_1
    rts

;; Moves Drive's head to Track, through the SeekVector vector.
;; Out:   carry = set if the head could not find track 0
SEEK:
    jmp SeekVector

;; SEEK's routine: recalibrates if the track is unknown, then steps to Track.
;; Out:   carry = set if track 0 was not found; else A = 0 if the head was already there, 1 if it moved
SeekTrack:
    ldx Drive
    lda CurrentTrack,X
    bpl SEEKTRACK_1
    jsr RECALIBRATE
    bcs SEEKTRACK_4
SEEKTRACK_1:
    ldx Drive
    lda CurrentTrack,X
    sec
    sbc Track
    beq SEEKTRACK_3
    ldy #$01
    bcs SEEKTRACK_2
    ldy #$00
    eor #$FF
    adc #$01
SEEKTRACK_2:
    tax
    tya
    jsr DRIVECOMMAND
    jsr STEPTRACKS
    ldx Drive
    lda Track
    sta CurrentTrack,X
    lda #$01
SEEKTRACK_3:
    clc
SEEKTRACK_4:
    rts

;; Steps Drive's head out until the drive senses track 0: up to 80 steps.
;; Out:   carry = set if track 0 was not found (DiskErrors bit 1 set); CurrentTrack = 0, or $FF
RECALIBRATE:
    stz DiskErrors
    lda #$01
    jsr DRIVECOMMAND
    lda #$0A
    jsr DRIVESENSE
    bcc RECALIBRATE_3
    ldy #$05
RECALIBRATE_1:
    ldx #$10
    jsr STEPTRACKS
    ldx #$10
RECALIBRATE_2:
    lda #$07
    jsr DELAYMS
    lda #$0A
    jsr DRIVESENSE
    bcc RECALIBRATE_3
    dex
    bne RECALIBRATE_2
    dey
    bne RECALIBRATE_1
    lda #$02
    tsb DiskErrors
    lda #$FF
    sec
    bra RECALIBRATE_4
RECALIBRATE_3:
    lda #$00
    clc
RECALIBRATE_4:
    ldx Drive
    sta CurrentTrack,X
    rts

;; Selects the head for Side through the card's head latch.
;; In:    A = Side
SELECTHEAD:
    lda Side
    beq SELECTHEAD_1
    sta SelectSide1
    rts
SELECTHEAD_1:
    sta SelectSide0
    rts

;; Writes the IWM's mode register until it reads back.
;; In:    A = the mode (bits 0-4)
SETIWMMODE:
    bit Iwm::ReadMode
    tay
    bit Iwm::MotorOff
    bit Iwm::LoadLatch
SETIWMMODE_1:
    lda Iwm::ReadMode
    and #$20
    bne SETIWMMODE_1
    bra SETIWMMODE_3
SETIWMMODE_2:
    sty Iwm::WriteMode
SETIWMMODE_3:
    tya
    eor Iwm::ReadMode
    and #$1F
    bne SETIWMMODE_2
    lda #$40
    trb SwimState
    lda Iwm::DataLatch
    rts

;; Loads the ISM's sixteen timing parameters for Track's zone, until they read back (five tries).
;; Out:   carry = set if they never matched
SETISMPARAMS:
    lda Track
    cmp #$50
    bcc SETISMPARAMS_1
    lda #$00
SETISMPARAMS_1:
    ldx #$FE
SETISMPARAMS_2:
    inx
    inx
    cmp ISMZONES,X
    bcs SETISMPARAMS_2
    lda ISMZONES+1,X
    tax
    ldy #$05
SETISMPARAMS_3:
    lda #$18
    sta Ism::ClearMode
    phx
SETISMPARAMS_4:
    dex
    lda ISMPARAMS,X
    beq SETISMPARAMS_5
    cmp Ism::ReadParameter
    bne SETISMPARAMS_6
    bra SETISMPARAMS_4
SETISMPARAMS_5:
    plx
    clc
    rts
SETISMPARAMS_6:
    lda #$18
    sta Ism::ClearMode
    plx
    phx
SETISMPARAMS_7:
    pha
    pla
    dex
    lda ISMPARAMS,X
    beq SETISMPARAMS_8
    sta Ism::WriteParameter
    bra SETISMPARAMS_7
SETISMPARAMS_8:
    plx
    dey
    bne SETISMPARAMS_3
    sec
    rts

;; SETISMPARAMS' zones: the first track past each zone, and where its parameters end in ISMPARAMS.
ISMZONES:
    .byte $28
    .byte $11, $50, $22, $50, $00, $50, $00

;; The ISM's timing parameters, read backwards from a zone's end.
ISMPARAMS:
    .byte $00, $3B, $57, $1B, $97, $19, $19, $2F, $2F, $1B, $1B, $18, $18, $2E, $2E, $41
    .byte $18, $00, $3B, $57, $1B, $97, $19, $19, $2F, $2F, $1B, $1B, $18, $18, $2E, $2E
    .byte $41, $18

;; Puts the SWIM into ISM mode and sets it up: the setup register, the phases as outputs, the
;; parameters; then back to IWM mode.
INITSWIM:
    stz SwimState
    stz SetupCopy
    jsr ENTERISM
    lda #$00
    sta Ism::WriteSetup
    sta SetupCopy
    lda Ism::ReadSetup
    lda #$38
    sta Ism::ClearMode
    lda #$00
    sta Ism::WriteCrc
    lda Ism::ReadMode
    lda Ism::ReadPhase
    ora #$F0
    sta Ism::WritePhase
    jsr SETISMPARAMS
    jmp LEAVEISM

;; Switches the SWIM from IWM to ISM mode, if it is not there already, and enables Drive.
;; Keeps: X
ENTERISM:
    phx
    bit SwimState
    bvs ENTERISM_1
    bit Iwm::ReadMode
    bit Iwm::LoadLatch
    lda Iwm::ReadMode
    pha
    bit Iwm::MotorOff
    and #$1F
    ora #$40
    sta Iwm::WriteMode
    eor #$40
    sta Iwm::WriteMode
    eor #$40
    sta Iwm::WriteMode
    sta Iwm::WriteMode
    lda #$40
    tsb SwimState
    pla
    bit #$20
    beq ENTERISM_3
ENTERISM_1:
    lda Ism::ReadMode
    and #$06
    cmp #$06
    bne ENTERISM_2
    lda #$06
    sta Ism::ClearMode
ENTERISM_2:
    ldx Drive
    cpx #$02
    bcs ENTERISM_3
    lda #$06
    sta Ism::ClearMode
    lda DRIVEBITS,X
    sta Ism::SetMode
    lda #$80
    sta Ism::SetMode
ENTERISM_3:
    plx
    lda Ism::ReadMode
    rts

;; The ISM mode register's drive-enable bit for drives 1 and 2.
DRIVEBITS:
    .byte $02, $04

;; Switches the SWIM back to IWM mode, keeping the drive enabled and the motor as they were.
;; Keeps: X
LEAVEISM:
    lda Ism::ReadMode
    pha
    lda #$9E
    sta Ism::ClearMode
    lda #$40
    sta Ism::ClearMode
    pha
    pla
    bit Iwm::ReadMode
    bit Iwm::DataLatch
    lda #$40
    trb SwimState
    pla
    bmi LEAVEISM_2
    phx
    ldx Drive
    cpx #$02
    bcs LEAVEISM_1
    bit Iwm::SelectDrive1,X
LEAVEISM_1:
    plx
    rts
LEAVEISM_2:
    phx
    ldx #$00
    bit #$04
    beq LEAVEISM_3
    ldx #$01
LEAVEISM_3:
    bit Iwm::SelectDrive1,X
    plx
    bit Iwm::MotorOn
    rts

;; Switches back to IWM mode if the SWIM is in ISM mode.
LEAVEISMIF:
    bit SwimState
    bvc LEAVEISMIF_1
    jsr LEAVEISM
LEAVEISMIF_1:
    rts

;; Sets setup bit 1 (SetupCopy bit 1), which this card uses to select its 3.5 drive port.
;; Keeps: A
PORTON:
    pha
    lda #$02
    bit SetupCopy
    bne PORTON_1
    jsr ENTERISM
    lda #$02
    ora Ism::ReadSetup
    sta Ism::WriteSetup
    sta SetupCopy
    cmp Ism::ReadSetup
    jsr LEAVEISM
PORTON_1:
    pla
    rts

;; Clears setup bit 1, which this card uses to select the SmartPort bus port.
;; Keeps: A
PORTOFF:
    pha
    lda #$02
    bit SetupCopy
    beq PORTOFF_1
    jsr ENTERISM
    lda #$FD
    and Ism::ReadSetup
    sta Ism::WriteSetup
    sta SetupCopy
    cmp Ism::ReadSetup
    jsr LEAVEISM
PORTOFF_1:
    pla
    rts

;; Readies the SWIM for MFM: SwimState bit 7 and the setup's MFM bits.
MFMON:
    lda #$80
    tsb SwimState
    lda #$20
    bit SetupCopy
    bne MFMON_1
    jsr ENTERISM
    lda #$20
    sta Ism::SetMode
    ora Ism::ReadSetup
    sta Ism::WriteSetup
    sta SetupCopy
    lda #$40
    sta Ism::WriteCrc
    jsr LEAVEISM
MFMON_1:
    rts

;; Readies the SWIM for GCR: clears MFM mode, and sets the IWM's mode to $1F.
MFMOFF:
    lda #$80
    trb SwimState
    lda #$20
    bit SetupCopy
    beq MFMOFF_1
    jsr ENTERISM
    lda #$20
    sta Ism::ClearMode
    lda Ism::ReadSetup
    and #$DF
    sta Ism::WriteSetup
    sta SetupCopy
    lda #$00
    sta Ism::WriteCrc
    jsr LEAVEISM
MFMOFF_1:
    lda #$1F
    jsr SETIWMMODE
    rts

;; Leaves a 3.5 drive's motor to the SWIM's motor-off timer and the port deselected.
;; In:    X = the drive
RELEASEDRIVE:
    cpx #$02
    bcs RELEASEDRIVE_3
    stx Drive
    jsr ENTERISM
    lda DRIVEBITS,X
    ora #$80
    sta Ism::SetMode
    lda #$32
RELEASEDRIVE_1:
    dec A
    bne RELEASEDRIVE_1
    lda Ism::ReadSetup
    and #$FD
    sta Ism::WriteSetup
    sta SetupCopy
    lda #$19
RELEASEDRIVE_2:
    dec A
    bpl RELEASEDRIVE_2
    jsr LEAVEISM
RELEASEDRIVE_3:
    rts

;; Selects one of a 3.5 drive's sixteen registers: CA2, the head line, CA0 and CA1 from A's bits 0-3
;; (with LSTRB low).
;; In:    A = the register
SETDRIVEREG:
    bit Iwm::Phase0Off
    bit Iwm::Phase1On
    bit Iwm::Phase3Off
    bit Iwm::Phase2Off
    lsr A
    bcc SETDRIVEREG_1
    bit Iwm::Phase2On
SETDRIVEREG_1:
    lsr A
    bcc SETDRIVEREG_2
    bit SelectSide1
    bra SETDRIVEREG_3
SETDRIVEREG_2:
    bit SelectSide0
SETDRIVEREG_3:
    lsr A
    bcc SETDRIVEREG_4
    bit Iwm::Phase0On
SETDRIVEREG_4:
    lsr A
    bcs SETDRIVEREG_5
    bit Iwm::Phase1Off
SETDRIVEREG_5:
    rts

;; Gives a 3.5 drive a command: selects the register, then pulses LSTRB.
;; In:    A = the command: 0/1 step in/out, 3 clear the disk-switched latch, 4 step, 6/7 MFM/GCR mode,
;;        8/9 motor on/off, $0D eject
DRIVECOMMAND:
    jsr SETDRIVEREG
    bit Iwm::Phase3On
    bit Iwm::Phase3Off
    rts

;; Reads one of a 3.5 drive's sense lines.
;; In:    A = the sense: 0 step direction, 2 no disk, 4 step done, 5 FDHD drive, 6 write enabled, 7 MFM mode,
;;        8 motor off, $0A not at track 0, $0B not ready, $0C disk switched, $0F not high density
;; Out:   carry = the line, A = 0
DRIVESENSE:
    jsr SETDRIVEREG
    bit Iwm::LoadLatch
    lda Iwm::ReadMode
    and #$80
    asl A
    rts

;; Waits up to about 1.2 s for the drive to report ready.
;; Out:   carry = set if it never did
WAITREADY:
    lda #$0B
    jsr DRIVESENSE
    bcc WAITREADY_4
    ldx #$03
    ldy #$E8
WAITREADY_1:
    lda #$92
    sta WaitCount
WAITREADY_2:
    bit Iwm::ReadMode
    bpl WAITREADY_3
    dec WaitCount
    bne WAITREADY_2
    dey
    bne WAITREADY_1
    dex
    bne WAITREADY_1
    sec
    rts
WAITREADY_3:
    clc
WAITREADY_4:
    rts

;; Waits, without a limit, for the drive to report ready.
;; Out:   carry = clear
WAITREADYEVER:
    lda #$0B
    jsr DRIVESENSE
    bcc WAITREADYEVER_2
WAITREADYEVER_1:
    lda Iwm::ReadMode
    and #$80
    bmi WAITREADYEVER_1
    asl A
WAITREADYEVER_2:
    rts

;; Waits until a sense line is set.
;; In:    A = the sense
;; Out:   carry = set
WAITSENSE:
    jsr DRIVESENSE
WAITSENSE_1:
    lda Iwm::ReadMode
    and #$80
    bpl WAITSENSE_1
    asl A
    rts

;; Checks the 3.5 drives for a removed disk while the card waits, forgetting the disk of a drive
;; that has none.
POLLDRIVES:
    ldx #$00
    lda DeviceKinds,X
    bmi POLLDRIVES_5
    beq POLLDRIVES_5
    jsr PORTON
POLLDRIVES_1:
    ldy #$0A
POLLDRIVES_2:
    dey
    bne POLLDRIVES_2
    jsr READSENSE
    bvc POLLDRIVES_3
    jsr FORGETDISK
POLLDRIVES_3:
    inx
    cpx #$01
    bne POLLDRIVES_4
    lda DeviceKinds,X
    bmi POLLDRIVES_4
    bne POLLDRIVES_1
POLLDRIVES_4:
    dex
    jsr RELEASEDRIVE
POLLDRIVES_5:
    rts

;; Reads a drive's sense lines and answers whether it can be used.
;; In:    X = the drive
;; Out:   carry = set with A = $2F (no disk) or $2E (switched, extended calls only); else A = 0, or $2B
;;        if the disk is write protected; negative = the disk was switched (its format must be found again)
CHECKDISK:
    jsr READSENSE
    bvc CHECKDISK_2
    php
    jsr FORGETDISK
    plp
    bpl CHECKDISK_1
    jsr CLEARSWITCHED
    bcs CHECKWRITE_2
CHECKDISK_1:
    lda #$2F
    sec
    bra CHECKWRITE_2
CHECKDISK_2:
    bmi CHECKDISK_3
    lda MediaKind,X
    bne CHECKWRITE
    jsr CHECKWRITE
    bit BITNEGATIVE
    rts
CHECKDISK_3:
    jsr FORGETMEDIA
    jsr CLEARSWITCHED
    bcs CHECKWRITE_2

;; Answers whether a drive's disk is write protected.
;; In:    X = the drive
;; Out:   carry = clear, A = $2B if protected, else 0
CHECKWRITE:
    lda #$20
    and Sense,X
    beq CHECKWRITE_1
    lda #$2B
CHECKWRITE_1:
    clc
CHECKWRITE_2:
    bit Sense,X
    rts

;; A $A0 for BIT: sets negative, clears overflow.
BITNEGATIVE:
    .byte $A0

;; Clears the drive's disk-switched latch.
;; Out:   carry = set with A = $2E for an extended call, else clear with A = 0
CLEARSWITCHED:
    lda #$03
    jsr DRIVECOMMAND
    lda #$2E
    sec
    bit CardCommand
    bvs CLEARSWITCHED_1
    lda #$00
    clc
CLEARSWITCHED_1:
    rts

;; Enables a drive and its motor line and reads its sense lines into Sense,X.
;; In:    X = the drive
;; Out:   PreviousSense = the last lines; Sense,X bit 7 = switched, 6 = no disk, 5 = write protected;
;;        negative and overflow from bits 7 and 6, zero = clear if write protected
READSENSE:
    lda Iwm::SelectDrive1,X
    bit Iwm::MotorOn

;; READSENSE without enabling the drive.
;; In:    X = the drive
SENSELINES:
    lda Sense,X
    sta PreviousSense
    and #$1F
    ora #$20
    sta Sense,X
    ldy #$03
SENSELINES_1:
    lda SENSEREGISTERS-1,Y
    jsr DRIVESENSE
    bcc SENSELINES_2
    lda SENSEMASKS-1,Y
    eor Sense,X
    sta Sense,X
SENSELINES_2:
    dey
    bne SENSELINES_1
    lda #$20
    bit Sense,X
    rts

;; The sense lines READSENSE reads: write enabled, no disk, switched...
SENSEREGISTERS:
    .byte $06, $02
    .byte $0C

;; ...and the Sense bits each one flips.
SENSEMASKS:
    .byte $20, $40, $80
