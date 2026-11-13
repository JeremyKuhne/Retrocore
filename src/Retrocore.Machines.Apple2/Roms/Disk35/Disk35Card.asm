;; THE APPLE II 3.5 DISK CONTROLLER CARD'S OWN FIRMWARE ($D000-$FFFF)
;;
;; What the card's 65C02 runs: it waits for the host's commands in its page zero, and answers ProDOS and
;; SmartPort calls for up to two 3.5 drives on its own port (the Apple 3.5 Drive, GCR 400K and 800K, and the
;; Apple FDHD, which adds MFM 720K and 1440K) and for SmartPort bus devices such as the UniDisk 3.5 on its
;; second port, which it passes their calls to. Assembles byte-identically as part of Disk35Controller.asm.
;;
;; THE UNITS
;;
;; Unit 0 is the controller. Units 1 and 2 are the 3.5 drives found at startup (drive 2 only if drive 1 is
;; there), and the bus devices follow, up to unit 4. DEVICEKIND holds each unit's device, UNITCOUNT their number.
;;
;; THE MAILBOX
;;
;; The host writes its command at CARDSTATE ($00) once bit 7 there says the card waits, after setting CARDDATA
;; to $FF and copying its command, unit and parameters to $02-$0A. DOCOMMAND runs it. Data moves through 512-byte
;; buffers in the card's RAM, named by a code: the card address divided by $200, which is the host's bank (code / 2)
;; and half (code & 1) of its $C800-$CBFF window. A handler that has data for the host, or wants data from it,
;; puts the buffer's code in CARDDATA and waits for the host to OR in $F0; a handler that is done puts 0 there with
;; the error in ERRORCODE ($56). MAINLOOP then sets CARDSTATE to $FF again.
;;
;;   Code 6 ($0C00-$0DFF)        status lists, control lists, a block being written, READ/WRITE's 524 bytes
;;   Codes $08-$19 ($1000-$33FF) the sector cache: a track's 18 slots, one per sector
;;
;; THE COMMANDS AT CARDSTATE
;;
;;   $00-$0B  SmartPort's command less its extended bit ($40); a ProDOS call arrives as SmartPort's 0-3 with
;;            CARDCOMMAND bit 7 set
;;   $0C      the slot ROM's boot: read block 0 of unit 1
;;   $0D/$0E  READAHEAD and READSPAN, which the slot ROM does not use
;;   $3D      run the diagnostics at $8F00
;;   $7E/$7F  the host is not / is a IIgs (HOSTTYPE)

; The host's slot page, at $7B00: offsets of the branches the card patches to release the host.
BOOTWAITOFFSET = $0C                ;; BOOTWAIT's branch offset; $16 sends it on to CALL
CALLWAITOFFSET = $22                ;; CALLWAIT's branch offset; 0 releases the host's calls
HOSTTYPEOFFSET = $09                ;; HOSTTYPE, at $CC09: bit 7 not yet known, bit 6 a IIgs

; The other parts of the ROM.
DIAGNOSTICSENTRY = $8F00            ;; the diagnostics' entry, for command $3D
POWERONTEST = $9649                 ;; the power-on test, which ends at STARTUP

; The card's RAM.
NIBBLES1 = $0100                    ;; a GCR sector's nibbles for WRITEDATAGCR: the first of three 175-byte lanes
TAGBYTES = $01B2                    ;; a sector's 12 tag bytes, as READDATAGCR reads them
HOSTCODE = $0200                    ;; the host's $C800 code ($CA00-$CBFF with bank 0)
INTERLEAVEMAP = $0600               ;; FORMAT's sector order; READSPAN's count and buffer codes
SECTORFLAGS = $0620                 ;; a track's sectors: $40 done, 0 wanted, $C0 not wanted
NIBBLES2 = $0640                    ;; the second lane
NIBBLES3 = $0741                    ;; the third lane
CACHECYLINDER = $0B00               ;; each cache slot's cylinder (indexed from 1)
CACHESECTORS = $0B20                ;; each slot's sector
CACHEOWNER = $0B40                  ;; each slot's drive; $80 empty, $8E not a 3.5 sector, $8F filling, $40 kept
CARDHOOK1 = $0B80                   ;; the host's hooks for units 1-4, RTS until something is loaded
CARDHOOK2 = $0BA0
CARDHOOK3 = $0BC0
CARDHOOK4 = $0BE0
XFERBUFFER = $0C00                  ;; buffer code 6, where lists and single blocks move

;; The 6-and-2 GCR encode table: the 64 valid disk bytes, four times over, so that a byte's low six bits
;; need not be masked.
GCRENCODE:
.repeat 4
    .byte $96, $97, $9A, $9B, $9D, $9E, $9F, $A6, $A7, $AB, $AC, $AD, $AE, $AF, $B2, $B3
    .byte $B4, $B5, $B6, $B7, $B9, $BA, $BB, $BC, $BD, $BE, $BF, $CB, $CD, $CE, $CF, $D3
    .byte $D6, $D7, $D9, $DA, $DB, $DC, $DD, $DE, $DF, $E5, $E6, $E7, $E9, $EA, $EB, $EC
    .byte $ED, $EE, $EF, $F2, $F3, $F4, $F5, $F6, $F7, $F9, $FA, $FB, $FC, $FD, $FE, $FF
.endrepeat
.assert * == $D100

;; The card's fixed entry points, for the diagnostics and the self-test.
CARDVECTORS:
    jmp MOTORON
    jmp RECALIBRATE
    jmp SEEK
    jmp WAITREADY
    jmp SELECTREADHEAD
    jmp CTLEJECT

;; SmartPort INIT ($05), and the INIT vector: releases the bus and the drives, then restarts the card
;; from its reset, which runs the power-on test again. The host waits for the card to come back ready.
INITCARD:
    jsr PORTOFF
    jsr DELAY1MS
    bit IWM_MTROFF
    stz CARDDATA

;; The 65C02's reset (and NMI) entry: clears the state byte, so the host waits, and runs the power-on
;; test at $9649, which comes back to STARTUP.
;; In:    EJECTDRIVE = a drive whose eject a reset cut short, or bit 7 set
CARDRESET:
    cld
    sei
    ldx #$FF
    txs
    stz CARDSTATE
    lda EJECTDRIVE
    jmp POWERONTEST

;; Starts the card after the power-on test: copies the host's code into the shared RAM, then either
;; starts cold (finds the drives and the bus devices) or, if page zero still holds the signature, warm (keeps them).
;; Ends in MAINLOOP.
;; In:    EJECTDRIVE = a drive whose eject a reset cut short, or bit 7 set
STARTUP:
    lda EJECTDRIVE
    jsr COPYHOSTCODE
    ldx #$04
STARTUP_1:
    dex
    bmi WARMSTART
    lda ZeroPageImage+SIGNATURE,X
    cmp SIGNATURE,X
    beq STARTUP_1
    jsr COLDINIT
    bra STARTUP_5
WARMSTART:
    jsr CLEARCACHE
    ldx #$FF
    stx DRIVE
    jsr INITSWIM
    jsr MFMOFF
    ldx FIRSTBUSUNIT
    beq STARTUP_2
    lda #$80
    jsr BUSINIT
    lda #$1F
    jsr SETIWMMODE
STARTUP_2:
    lda FIRSTBUSUNIT
    cmp #$01
    beq STARTUP_5
    ldx UNITCOUNT
STARTUP_3:
    dex
    bmi STARTUP_4
    bit DEVICEKIND,X
    bmi STARTUP_3
    stx SAVEDRIVE
    stx DRIVE
    jsr PORTON
    ldx SAVEDRIVE
    jsr CHECKDISK
    phx
    clc
    jsr IDENTIFYMEDIA
    jsr MFMOFF
    ldx SAVEDRIVE
    jsr RELEASEDRIVE
    plx
    bra STARTUP_3
STARTUP_4:
    jsr PORTON
STARTUP_5:
    bit EJECTDRIVE
    bmi MAINLOOP
    ldx #$FF
    stx DRIVE
    jsr PORTON
    ldx EJECTDRIVE
    lda IWM_DRIVE1,X
    bit IWM_MTRON
    jsr EJECT

;; Waits for the host's commands and runs them, forever. The card is ready while CARDSTATE ($00) has bit 7
;; set; the host writes the command there. About every three passes of a 65536-count wait without a command it
;; polls the drives for a disk's removal (POLLDRIVES). Each command is logged at LASTCOMMAND ($E0-$E4).
MAINLOOP:
    lda #$FF
    sta CARDDATA
    sta CARDSTATE
    ldx #$03
MAINLOOP_1:
    dec WORKPTR
    bne MAINLOOP_2
    dec WORKPTR+1
    bne MAINLOOP_2
    dex
    bne MAINLOOP_2
    jsr POLLDRIVES
    ldx #$03
MAINLOOP_2:
    lda CARDSTATE
    bmi MAINLOOP_1
    sta LASTCOMMAND
    lda CARDCOMMAND
    sta LASTCOMMAND+1
    lda CARDUNIT
    sta LASTCOMMAND+2
    lda PARAMLO
    sta LASTCOMMAND+3
    lda PARAMMID
    sta LASTCOMMAND+4
MAINLOOP_3:
    jsr VECCOMMAND
    bcs MAINLOOP_4
    lda #$FF
    sta CARDSTATE
MAINLOOP_4:
    stz WORKPTR+1
    stz SAVEDRIVE
    jsr MFMOFF
    lda CARDSTATE
    bpl MAINLOOP_3
    bit IWM_MTROFF
    ldx #$03
    bra MAINLOOP_1

;; Runs the command in CARDSTATE: the VECCOMMAND vector's routine.
;; Commands $00-$0E go to the handler for the unit; $3D jumps to the diagnostics, $7E/$7F name the host
;; (not a IIgs, a IIgs) in HOSTTYPE; others answer $01.
;; Out:   carry = clear when the card is ready for another command, set when the handler left it waiting
;;        ERRORCODE ($56) = the error, CARDDATA = 0 when the result is final
DOCOMMAND:
    stz ERRORCODE
    stz RETRIES
    stz TAGCALL
    stz SWIMSTATE
    lda #$FF
    sta SECTOR
    sta CYLINDER
    sta TRACK
    lda CARDSTATE
    cmp #$0F
    bcc DOCOMMAND_3
    cmp #$7E
    bcc DOCOMMAND_2
    eor #$7E
    beq DOCOMMAND_1
    lda #$40
DOCOMMAND_1:
    sta SHARED_EXPANSION+HOSTTYPEOFFSET
    clc
    rts
DOCOMMAND_2:
    cmp #$3D
    bne DOCOMMAND_7
    jmp DIAGNOSTICSENTRY
DOCOMMAND_3:
    stz UNITHIGHBIT
DOCOMMAND_4:
    lda UNITCOUNT
    cmp CARDUNIT
    bcs DOCOMMAND_6
    lda CARDSTATE
    ora PARAMLO
    bne DOCOMMAND_5
    bit CARDCOMMAND
    bvc DOCOMMAND_5
    lda CARDUNIT
    bpl DOCOMMAND_5
    sta UNITHIGHBIT
    and #$7F
    sta CARDUNIT
    bne DOCOMMAND_4
DOCOMMAND_5:
    lda #$11
    bra SETERROR
DOCOMMAND_6:
    ldx CARDUNIT
    dex
    stx DRIVE
    bmi CALLHANDLER
    lda DEVICEKIND,X
    bpl CALLHANDLER
    lda CARDSTATE
    cmp #$0D
    bcc PASSTOBUS
DOCOMMAND_7:
    bra ERRBADCOMMAND
CALLHANDLER:
    lda #$1F
    jsr SETIWMMODE
    jsr PORTON
    lda CARDSTATE
    asl A
    tax
    jmp (HANDLERS,X)
PASSTOBUS:
    ldx #$FF
    stx DRIVE
    jsr PORTOFF
    jsr MFMOFF
    ldx CARDUNIT
    stx DRIVE
    jsr BUSCALL
    lda FIRSTBUSUNIT
    cmp #$01
    beq DOCOMMAND_8
    lda #$FF
    sta DRIVE
    jsr PORTON
DOCOMMAND_8:
    clc
    rts

;; Each command's handler, by the command at CARDSTATE ($00-$0E).
HANDLERS:
    .word DOSTATUS, DOREADBLOCK, DOWRITEBLOCK, DOFORMAT ; $00-$03: STATUS, READBLOCK, WRITEBLOCK, FORMAT
    .word DOCONTROL, INITCARD, ERRBADCOMMAND, ERRBADCOMMAND ; $04-$07: CONTROL, INIT, OPEN, CLOSE
    .word READWRITE, READWRITE, SETFORMAT, FORMATOPTIONS ; $08-$0B: READ, WRITE, SETFORMAT, FORMATOPTIONS
    .word BOOTREAD, READAHEAD, READSPAN ; $0C-$0E: the boot read, READAHEAD, READSPAN
ERRBADCOMMAND:
    lda #$01

;; Ends a command with an error code and no data.
;; In:    A = the error
;; Out:   carry = clear, ERRORCODE = A, CARDDATA = 0
SETERROR:
    clc
    sta ERRORCODE
    stz CARDDATA
    rts

;; Ends a command with $22, a bad parameter (a wrong byte count).
;; Out:   carry = clear
ERRBADPARAMETER:
    lda #$22
    bra SETERROR

;; Starts the card cold: page zero from the ROM, the SWIM set up, the bus reset, the drives found and
;; the SmartPort bus devices numbered after them, then the signature and an empty cache.
;; Out:   UNITCOUNT = the units, FIRSTBUSUNIT = the first bus unit, DEVICEKIND = each unit's kind
COLDINIT:
    jsr COPYZEROPAGE
    lda #$D2
    sta FORMATHOOK+1
    lda #$75
    sta FORMATHOOK
    lda #$FF
    sta DRIVE
    jsr INITSWIM
    lda #$96
    jsr DELAY2
    lda #$1F
    jsr SETIWMMODE
    jsr PORTOFF
    jsr BUSRESET
    jsr PORTON
    jsr DELAY1MS
    jsr PORTOFF
    jsr FINDDRIVES
    stz FIRSTBUSUNIT
    ldx UNITCOUNT
    inx
    lda #$00
    jsr BUSINIT
    beq COLDINIT_1
    ldx UNITCOUNT
    inx
    stx FIRSTBUSUNIT
    clc
    adc UNITCOUNT
    sta UNITCOUNT
COLDINIT_1:
    stz DRIVE
    jsr COPYSIGNATURE

;; Empties the sector cache: each slot's track and sector 0 and owner $40 (free), slot $12's $80.
CLEARCACHE:
    ldx #$1F
    lda #$40
CLEARCACHE_1:
    stz CACHECYLINDER,X
    stz CACHESECTORS,X
    sta CACHEOWNER,X
    cpx #$12
    bne CLEARCACHE_2
    lda #$80
CLEARCACHE_2:
    dex
    bpl CLEARCACHE_1
    rts

;; Copies the ROM's page-zero image, $8001-$80BB, to $01-$BB.
COPYZEROPAGE:
    ldx #$BB
COPYZEROPAGE_1:
    lda ZeroPageImage,X
    sta CARDSTATE,X
    dex
    bne COPYZEROPAGE_1
    rts

;; Copies the warm-start signature, $80BC-$80BF, to SIGNATURE ($BC-$BF).
COPYSIGNATURE:
    ldx #$BF
COPYSIGNATURE_1:
    lda ZeroPageImage,X
    sta CARDSTATE,X
    dex
    cpx #$BB
    bne COPYSIGNATURE_1
    rts

;; Copies the host's slot page to $7B00, its $C800 code to $0200-$03FF and its $CC00 code to $7C00-$7FFF,
;; then sets the slot page's BOOTWAIT offset to $16 (to CALL) and CALLWAIT's to 0, and puts an RTS at each
;; unit's hook ($0B80, $0BA0, $0BC0, $0BE0).
;; Out:   Y = 0
COPYHOSTCODE:
    ldy #$00
COPYHOSTCODE_1:
    lda SlotPageImage,Y
    sta SHARED_SLOTPAGE,Y
    iny
    bne COPYHOSTCODE_1
COPYHOSTCODE_2:
    lda SlotPageImage+$100,Y
    sta HOSTCODE,Y
    lda SlotPageImage+$200,Y
    sta HOSTCODE+$100,Y
    lda SlotPageImage+$300,Y
    sta SHARED_EXPANSION,Y
    lda SlotPageImage+$400,Y
    sta SHARED_EXPANSION+$100,Y
    lda SlotPageImage+$500,Y
    sta SHARED_EXPANSION+$200,Y
    lda SlotPageImage+$600,Y
    sta SHARED_EXPANSION+$300,Y
    iny
    bne COPYHOSTCODE_2
    lda #$16
    sta SHARED_SLOTPAGE+BOOTWAITOFFSET
    stz SHARED_SLOTPAGE+CALLWAITOFFSET
    lda #$60
    sta CARDHOOK1
    sta CARDHOOK2
    sta CARDHOOK3
    sta CARDHOOK4
    rts

;; Finds the 3.5 drives on the card's own port: drive 1, then drive 2 if drive 1 is there. Each is
;; identified and its disk, if any, read for its format; a drive whose disk cannot be read has it ejected.
;; Out:   UNITCOUNT = the drives found (0-2), DEVICEKIND set for each
FINDDRIVES:
    jsr MFMOFF
    ldx #$00
FINDDRIVES_1:
    stx SAVEDRIVE
    stx DRIVE
    jsr DETECTDRIVE
    bcs FINDDRIVES_4
    ora #$01
    sta DEVICEKIND,X
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
    ldx SAVEDRIVE
    jsr EJECT
FINDDRIVES_3:
    jsr MFMOFF
    ldx SAVEDRIVE
    inx
    cpx #$02
    bcc FINDDRIVES_1
FINDDRIVES_4:
    stx UNITCOUNT
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
    lda IWM_DRIVE1,X
    bit IWM_Q6L
    bit IWM_Q7L
    bit IWM_MTRON
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
;; Out:   carry = set if no format was found; else MEDIAKIND, BLOCKSLO/HI and MEDIAMODE set
IDENTIFYDD:
    stx SAVEDRIVE
    lda #$04
    sta RETRIES
    jsr WAITREADYEVER
IDENTIFYDD_1:
    stz SIDE
    jsr READADDRESS
    bcc IDENTIFYDD_4
    lda DISKERRORS
    bit #$20
    bne IDENTIFYDD_2
    bit #$04
    beq IDENTIFYDD_3
    lda HDRTRACK
    sta TRACK
IDENTIFYDD_2:
    dec RETRIES
    bne IDENTIFYDD_1
    bra IDENTIFYDD_MFM
IDENTIFYDD_3:
    bit #$01
    bne IDENTIFYDD_MFM
    sec
    rts
IDENTIFYDD_4:
    ldx SAVEDRIVE
    jsr READSENSE
    ldy #$04
    lda FORMATBYTE,X
    and #$1F
    cmp #$02
    bne IDENTIFYDD_5
    ldy #$06
IDENTIFYDD_5:
    bit SIDES,X
    bmi IDENTIFYDD_6
    lda SENSE,X
    ora #$10
    sta SENSE,X
    ldy #$02
IDENTIFYDD_6:
    lda MEDIABLOCKS,Y
    sta BLOCKSLO,X
    lda MEDIABLOCKS+1,Y
    sta BLOCKSHI,X
    lda SENSE,X
    and #$BF
    sta SENSE,X
    lda MEDIAMODE,X
    and #$94
    ora MODEFLAGS,Y
    sta MEDIAMODE,X
    sty MEDIAKIND,X
    clc
    rts
IDENTIFYDD_MFM:
    ldx SAVEDRIVE
    lda #$02
    bit DEVICEKIND,X
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
    stz TRACK
    lda #$04
    sta RETRIES
IDENTIFYDD_7:
    stz SIDE
    jsr READADDRESS
    bcc IDENTIFYDD_10
    lda DISKERRORS
    bit #$20
    bne IDENTIFYDD_8
    bit #$04
    beq IDENTIFYDD_8
    lda HDRTRACK
    sta TRACK
IDENTIFYDD_8:
    dec RETRIES
    bne IDENTIFYDD_7
    lda #$07
    jsr DRIVECOMMAND
    lda #$0B
    jsr DELAY2
IDENTIFYDD_9:
    jsr MFMOFF
    ldx SAVEDRIVE
    lda MEDIAMODE,X
    and #$9F
    sta MEDIAMODE,X
    sec
    rts
IDENTIFYDD_10:
    jsr LEAVEISM
    ldx SAVEDRIVE
    jsr READSENSE
    ldy #$08
    lda MEDIABLOCKS,Y
    sta BLOCKSLO,X
    lda MEDIABLOCKS+1,Y
    sta BLOCKSHI,X
    lda SENSE,X
    and #$BF
    sta SENSE,X
    lda MODEFLAGS,Y
    sta MEDIAMODE,X
    sty MEDIAKIND,X
    clc
    rts

;; MEDIAMODE for each MEDIAKIND (even indexes; the odd bytes are not read).
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
    stx SAVEDRIVE
    jsr FORGETMEDIA
    lda #$02
    jsr DRIVESENSE
    bcc IDENTIFYMEDIA_1
    pla
    lda #$2F
    bra IDENTIFYMEDIA_8
IDENTIFYMEDIA_1:
    lda #$02
    bit DEVICEKIND,X
    beq IDENTIFYMEDIA_6
    lda #$0F
    jsr DRIVESENSE
    bcs IDENTIFYMEDIA_6
    lda #$80
    sta SIDES,X
    lda #$54
    ora MEDIAMODE,X
    sta MEDIAMODE,X
    lda SENSE,X
    and #$BF
    sta SENSE,X
    jsr RECALIBRATE
    jsr MFMON
    jsr MOTORON
    stz SIDE
    stz TRACK
    jsr WAITREADYEVER
    lda #$04
    sta RETRIES
IDENTIFYMEDIA_2:
    stz SIDE
    jsr READADDRESS
    bcc IDENTIFYMEDIA_4
    lda DISKERRORS
    bit #$20
    bne IDENTIFYMEDIA_3
    bit #$04
    beq IDENTIFYMEDIA_3
    lda HDRTRACK
    sta TRACK
IDENTIFYMEDIA_3:
    dec RETRIES
    bne IDENTIFYMEDIA_2
    bra IDENTIFYMEDIA_7
IDENTIFYMEDIA_4:
    jsr LEAVEISM
    ldx SAVEDRIVE
    jsr READSENSE
    ldy #$0A
    lda MEDIABLOCKS,Y
    sta BLOCKSLO,X
    lda MEDIABLOCKS+1,Y
    sta BLOCKSHI,X
    sty MEDIAKIND,X
    clc
IDENTIFYMEDIA_5:
    pla
    plp
    rts
IDENTIFYMEDIA_6:
    jsr RECALIBRATE
    jsr MOTORON
    stz SIDE
    ldx SAVEDRIVE
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
    sta SENSE,X

;; Forgets a drive's format: no blocks, an unknown track, and its cached sectors dropped.
;; In:    X = the drive
;; Keeps: X, Y
FORGETMEDIA:
    stz BLOCKSLO,X
    stz BLOCKSHI,X
    lda MEDIAMODE,X
    and #$80
    sta MEDIAMODE,X
    lda #$FF
    sta CURTRACK,X
    stz MEDIAKIND,X
    phx
    phy
    jsr FORGETCACHE
    ply
    plx
    rts

;; Turns DRIVE's motor on, if it is off, and waits for it to come up to speed: 500 ms the first time
;; since its disk was found (SENSE bit 0), else 100 ms.
MOTORON:
    lda #$08
    jsr DRIVESENSE
    bcc MOTORON_2
    jsr SETDRIVEMODE
    lda #$08
    jsr DRIVECOMMAND
    ldx DRIVE
    lda #$01
    bit SENSE,X
    bne MOTORON_1
    ora SENSE,X
    sta SENSE,X
    lda #$C8
    jsr DELAY2
MOTORON_1:
    lda #$64
    jsr DELAYMS
MOTORON_2:
    rts

;; On an FDHD drive, sets the drive's MFM or GCR mode to suit its disk's MEDIAMODE.
SETDRIVEMODE:
    ldx DRIVE
    lda #$02
    bit DEVICEKIND,X
    beq SETDRIVEMODE_4
    ldy #$06
    lda #$60
    bit MEDIAMODE,X
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

;; Moves DRIVE's head to TRACK, through the VECSEEK vector.
;; Out:   carry = set if the head could not find track 0
SEEK:
    jmp VECSEEK

;; SEEK's routine: recalibrates if the track is unknown, then steps to TRACK.
;; Out:   carry = set if track 0 was not found; else A = 0 if the head was already there, 1 if it moved
SEEKTRACK:
    ldx DRIVE
    lda CURTRACK,X
    bpl SEEKTRACK_1
    jsr RECALIBRATE
    bcs SEEKTRACK_4
SEEKTRACK_1:
    ldx DRIVE
    lda CURTRACK,X
    sec
    sbc TRACK
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
    ldx DRIVE
    lda TRACK
    sta CURTRACK,X
    lda #$01
SEEKTRACK_3:
    clc
SEEKTRACK_4:
    rts

;; Steps DRIVE's head out until the drive senses track 0: up to 80 steps.
;; Out:   carry = set if track 0 was not found (DISKERRORS bit 1 set); CURTRACK = 0, or $FF
RECALIBRATE:
    stz DISKERRORS
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
    tsb DISKERRORS
    lda #$FF
    sec
    bra RECALIBRATE_4
RECALIBRATE_3:
    lda #$00
    clc
RECALIBRATE_4:
    ldx DRIVE
    sta CURTRACK,X
    rts

;; Selects the head for SIDE through the card's head latch.
;; In:    A = SIDE
SELECTHEAD:
    lda SIDE
    beq SELECTHEAD_1
    sta HEADSEL1
    rts
SELECTHEAD_1:
    sta HEADSEL0
    rts

;; Writes the IWM's mode register until it reads back.
;; In:    A = the mode (bits 0-4)
SETIWMMODE:
    bit IWM_Q7L
    tay
    bit IWM_MTROFF
    bit IWM_Q6H
SETIWMMODE_1:
    lda IWM_Q7L
    and #$20
    bne SETIWMMODE_1
    bra SETIWMMODE_3
SETIWMMODE_2:
    sty IWM_Q7H
SETIWMMODE_3:
    tya
    eor IWM_Q7L
    and #$1F
    bne SETIWMMODE_2
    lda #$40
    trb SWIMSTATE
    lda IWM_Q6L
    rts

;; Loads the ISM's sixteen timing parameters for TRACK's zone, until they read back (five tries).
;; Out:   carry = set if they never matched
SETISMPARAMS:
    lda TRACK
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
    sta ISM_wZeroes
    phx
SETISMPARAMS_4:
    dex
    lda ISMPARAMS,X
    beq SETISMPARAMS_5
    cmp ISM_rParams
    bne SETISMPARAMS_6
    bra SETISMPARAMS_4
SETISMPARAMS_5:
    plx
    clc
    rts
SETISMPARAMS_6:
    lda #$18
    sta ISM_wZeroes
    plx
    phx
SETISMPARAMS_7:
    pha
    pla
    dex
    lda ISMPARAMS,X
    beq SETISMPARAMS_8
    sta ISM_wParams
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
    stz SWIMSTATE
    stz SETUPCOPY
    jsr ENTERISM
    lda #$00
    sta ISM_wSetup
    sta SETUPCOPY
    lda ISM_rSetup
    lda #$38
    sta ISM_wZeroes
    lda #$00
    sta ISM_wCRC
    lda ISM_rStatus
    lda ISM_rPhase
    ora #$F0
    sta ISM_wPhase
    jsr SETISMPARAMS
    jmp LEAVEISM

;; Switches the SWIM from IWM to ISM mode, if it is not there already, and enables DRIVE.
;; Keeps: X
ENTERISM:
    phx
    bit SWIMSTATE
    bvs ENTERISM_1
    bit IWM_Q7L
    bit IWM_Q6H
    lda IWM_Q7L
    pha
    bit IWM_MTROFF
    and #$1F
    ora #$40
    sta IWM_Q7H
    eor #$40
    sta IWM_Q7H
    eor #$40
    sta IWM_Q7H
    sta IWM_Q7H
    lda #$40
    tsb SWIMSTATE
    pla
    bit #$20
    beq ENTERISM_3
ENTERISM_1:
    lda ISM_rStatus
    and #$06
    cmp #$06
    bne ENTERISM_2
    lda #$06
    sta ISM_wZeroes
ENTERISM_2:
    ldx DRIVE
    cpx #$02
    bcs ENTERISM_3
    lda #$06
    sta ISM_wZeroes
    lda DRIVEBITS,X
    sta ISM_wOnes
    lda #$80
    sta ISM_wOnes
ENTERISM_3:
    plx
    lda ISM_rStatus
    rts

;; The ISM mode register's drive-enable bit for drives 1 and 2.
DRIVEBITS:
    .byte $02, $04

;; Switches the SWIM back to IWM mode, keeping the drive enabled and the motor as they were.
;; Keeps: X
LEAVEISM:
    lda ISM_rStatus
    pha
    lda #$9E
    sta ISM_wZeroes
    lda #$40
    sta ISM_wZeroes
    pha
    pla
    bit IWM_Q7L
    bit IWM_Q6L
    lda #$40
    trb SWIMSTATE
    pla
    bmi LEAVEISM_2
    phx
    ldx DRIVE
    cpx #$02
    bcs LEAVEISM_1
    bit IWM_DRIVE1,X
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
    bit IWM_DRIVE1,X
    plx
    bit IWM_MTRON
    rts

;; Switches back to IWM mode if the SWIM is in ISM mode.
LEAVEISMIF:
    bit SWIMSTATE
    bvc LEAVEISMIF_1
    jsr LEAVEISM
LEAVEISMIF_1:
    rts

;; Sets setup bit 1 (SETUPCOPY bit 1), which this card uses to select its 3.5 drive port.
;; Keeps: A
PORTON:
    pha
    lda #$02
    bit SETUPCOPY
    bne PORTON_1
    jsr ENTERISM
    lda #$02
    ora ISM_rSetup
    sta ISM_wSetup
    sta SETUPCOPY
    cmp ISM_rSetup
    jsr LEAVEISM
PORTON_1:
    pla
    rts

;; Clears setup bit 1, which this card uses to select the SmartPort bus port.
;; Keeps: A
PORTOFF:
    pha
    lda #$02
    bit SETUPCOPY
    beq PORTOFF_1
    jsr ENTERISM
    lda #$FD
    and ISM_rSetup
    sta ISM_wSetup
    sta SETUPCOPY
    cmp ISM_rSetup
    jsr LEAVEISM
PORTOFF_1:
    pla
    rts

;; Readies the SWIM for MFM: SWIMSTATE bit 7 and the setup's MFM bits.
MFMON:
    lda #$80
    tsb SWIMSTATE
    lda #$20
    bit SETUPCOPY
    bne MFMON_1
    jsr ENTERISM
    lda #$20
    sta ISM_wOnes
    ora ISM_rSetup
    sta ISM_wSetup
    sta SETUPCOPY
    lda #$40
    sta ISM_wCRC
    jsr LEAVEISM
MFMON_1:
    rts

;; Readies the SWIM for GCR: clears MFM mode, and sets the IWM's mode to $1F.
MFMOFF:
    lda #$80
    trb SWIMSTATE
    lda #$20
    bit SETUPCOPY
    beq MFMOFF_1
    jsr ENTERISM
    lda #$20
    sta ISM_wZeroes
    lda ISM_rSetup
    and #$DF
    sta ISM_wSetup
    sta SETUPCOPY
    lda #$00
    sta ISM_wCRC
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
    stx DRIVE
    jsr ENTERISM
    lda DRIVEBITS,X
    ora #$80
    sta ISM_wOnes
    lda #$32
RELEASEDRIVE_1:
    dec A
    bne RELEASEDRIVE_1
    lda ISM_rSetup
    and #$FD
    sta ISM_wSetup
    sta SETUPCOPY
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
    bit IWM_PH0L
    bit IWM_PH1H
    bit IWM_PH3L
    bit IWM_PH2L
    lsr A
    bcc SETDRIVEREG_1
    bit IWM_PH2H
SETDRIVEREG_1:
    lsr A
    bcc SETDRIVEREG_2
    bit HEADSEL1
    bra SETDRIVEREG_3
SETDRIVEREG_2:
    bit HEADSEL0
SETDRIVEREG_3:
    lsr A
    bcc SETDRIVEREG_4
    bit IWM_PH0H
SETDRIVEREG_4:
    lsr A
    bcs SETDRIVEREG_5
    bit IWM_PH1L
SETDRIVEREG_5:
    rts

;; Gives a 3.5 drive a command: selects the register, then pulses LSTRB.
;; In:    A = the command: 0/1 step in/out, 3 clear the disk-switched latch, 4 step, 6/7 MFM/GCR mode,
;;        8/9 motor on/off, $0D eject
DRIVECOMMAND:
    jsr SETDRIVEREG
    bit IWM_PH3H
    bit IWM_PH3L
    rts

;; Reads one of a 3.5 drive's sense lines.
;; In:    A = the sense: 0 step direction, 2 no disk, 4 step done, 5 FDHD drive, 6 write enabled, 7 MFM mode,
;;        8 motor off, $0A not at track 0, $0B not ready, $0C disk switched, $0F not high density
;; Out:   carry = the line, A = 0
DRIVESENSE:
    jsr SETDRIVEREG
    bit IWM_Q6H
    lda IWM_Q7L
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
    sta WAITCOUNT
WAITREADY_2:
    bit IWM_Q7L
    bpl WAITREADY_3
    dec WAITCOUNT
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
    lda IWM_Q7L
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
    lda IWM_Q7L
    and #$80
    bpl WAITSENSE_1
    asl A
    rts

;; Checks the 3.5 drives for a removed disk while the card waits, forgetting the disk of a drive
;; that has none.
POLLDRIVES:
    ldx #$00
    lda DEVICEKIND,X
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
    lda DEVICEKIND,X
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
    lda MEDIAKIND,X
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
    and SENSE,X
    beq CHECKWRITE_1
    lda #$2B
CHECKWRITE_1:
    clc
CHECKWRITE_2:
    bit SENSE,X
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
    bit CARDCOMMAND
    bvs CLEARSWITCHED_1
    lda #$00
    clc
CLEARSWITCHED_1:
    rts

;; Enables a drive and its motor line and reads its sense lines into SENSE,X.
;; In:    X = the drive
;; Out:   OLDSENSE = the last lines; SENSE,X bit 7 = switched, 6 = no disk, 5 = write protected;
;;        negative and overflow from bits 7 and 6, zero = clear if write protected
READSENSE:
    lda IWM_DRIVE1,X
    bit IWM_MTRON

;; READSENSE without enabling the drive.
;; In:    X = the drive
SENSELINES:
    lda SENSE,X
    sta OLDSENSE
    and #$1F
    ora #$20
    sta SENSE,X
    ldy #$03
SENSELINES_1:
    lda SENSEREGISTERS-1,Y
    jsr DRIVESENSE
    bcc SENSELINES_2
    lda SENSEMASKS-1,Y
    eor SENSE,X
    sta SENSE,X
SENSELINES_2:
    dey
    bne SENSELINES_1
    lda #$20
    bit SENSE,X
    rts

;; The sense lines READSENSE reads: write enabled, no disk, switched...
SENSEREGISTERS:
    .byte $06, $02
    .byte $0C

;; ...and the SENSE bits each one flips.
SENSEMASKS:
    .byte $20, $40, $80

;; Marks every cache slot not in use for a write ($40) as empty ($80).
FLUSHCACHE:
    lda #$80
    ldx #$12
FLUSHCACHE_1:
    bit CACHEOWNER-1,X
    bvs FLUSHCACHE_2
    sta CACHEOWNER-1,X
FLUSHCACHE_2:
    dex
    bne FLUSHCACHE_1
    rts

;; Never called: claims a cache slot, as FILLSLOT does, without setting the buffer pointers.
UNUSEDCLAIM:
    lda CACHEOWNER-1,Y
    bit #$40
    bne UNUSEDCLAIM_1
    lda #$80
    sta CACHEOWNER-1,Y
UNUSEDCLAIM_1:
    lda SLOTBUFFERS,Y
    sty CACHESLOT
    sta BUFFERCODE
    rts

;; Claims the cache slot for a sector ($8F, filling) and points the buffers at it.
;; In:    X = the sector
;; Out:   BUFFERCODE = its buffer code, CACHESLOT = the slot
FILLSLOT:
    lda SECTORSLOTS,X
    tax
    lda #$8F
    sta CACHEOWNER-1,X
    lda SLOTBUFFERS,X
    sta BUFFERCODE
    stx CACHESLOT

;; Points BUFPTR and BUFPTR2 at the two halves of a 512-byte buffer.
;; In:    A = the buffer code (the card address / $200)
SETBUFFER:
    tax
    lda BUFFERHIGH,X
    sta BUFPTR2+1
    dec A
    sta BUFPTR+1
    stz BUFPTR
    stz BUFPTR2
    rts

;; A buffer code's second half's page: code * 2 + 1.
BUFFERHIGH:
    .byte $01, $03, $05, $07, $09, $0B, $0D, $0F, $11, $13, $15, $17, $19, $1B, $1D, $1F
    .byte $21, $23, $25, $27, $29, $2B, $2D, $2F, $31, $33, $35

;; Each cache slot's buffer code, from slot 1 ($08, card $1000) to slot $12.
SLOTBUFFERS:
    .byte $37, $08, $09, $0A, $0B, $0C, $0D, $0E, $0F, $10, $11, $12, $13, $14, $15, $16
    .byte $17, $18, $19, $1A, $1B

;; Each sector's cache slot: the sector plus 1.
SECTORSLOTS:
    .byte $01, $02, $03, $04, $05, $06, $07, $08, $09, $0A, $0B, $0C, $0D, $0E, $0F, $10
    .byte $11, $12

;; Records the sector just read in its cache slot: the sector, the cylinder (track and side) and the
;; owner (DRIVE), or $8E if the data is not for a 3.5 drive.
;; In:    A = the sector, CACHESLOT = the slot
CACHESECTOR:
    ldy CACHESLOT
    beq CACHESECTOR_1
    sta CACHESECTORS-1,Y
    lda SIDE
    cmp #$01
    lda TRACK
    rol A
    sta CACHECYLINDER-1,Y
    lda DRIVE
    cmp UNITCOUNT
    bcs CACHESECTOR_1
    sta CACHEOWNER-1,Y
    rts
CACHESECTOR_1:
    lda #$8E
    sta CACHEOWNER-1,Y
    rts

;; Answers whether the block in PARAMLO/PARAMMID is on DRIVE's disk.
;; Out:   carry = set with A = $2D if it is not
CHECKBLOCK:
    ldx DRIVE
    lda PARAMLO
    cmp BLOCKSLO,X
    lda PARAMMID
    sbc BLOCKSHI,X
    bcc CHECKBLOCK_1
    lda #$2D
CHECKBLOCK_1:
    rts

;; Drops a drive's sectors from the cache.
;; In:    X = the drive
FORGETCACHE:
    stx SAVEDRIVE
    ldy #$12
FORGETCACHE_1:
    lda CACHEOWNER-1,Y
    cmp #$20
    bcs FORGETCACHE_2
    cmp SAVEDRIVE
    bne FORGETCACHE_2
    lda #$80
    sta CACHEOWNER-1,Y
FORGETCACHE_2:
    dey
    bne FORGETCACHE_1
    rts

;; Looks for SECTOR of the current track in the cache.
;; Out:   carry = set with A = its buffer code if it is there
FINDCACHED:
    ldy SECTOR
    lda SECTORSLOTS,Y
    tay
    jsr MATCHSLOT
    bne FINDCACHED_1
    lda SLOTBUFFERS,Y
    sec
    rts
FINDCACHED_1:
    clc
    rts

;; Compares a cache slot with DRIVE, the cylinder and SECTOR.
;; In:    Y = the slot
;; Out:   zero = they match
MATCHSLOT:
    lda CACHEOWNER-1,Y
    cmp DRIVE
    bne MATCHSLOT_1
    lda SIDE
    cmp #$01
    lda TRACK
    rol A
    cmp CACHECYLINDER-1,Y
    bne MATCHSLOT_1
    lda SECTOR
    cmp CACHESECTORS-1,Y
MATCHSLOT_1:
    rts

;; Finds where a block is on DRIVE's disk, by its MEDIAKIND.
;; Out:   carry = set with A = $3D for an unknown format; else A = the sectors in the track,
;;        TRACK, SIDE, SECTOR and CYLINDER set
BLOCKTOSECTOR:
    ldx DRIVE
    lda MEDIAKIND,X
    tax
    jmp (BLOCKMAPS,X)

;; BLOCKTOSECTOR's routine for each MEDIAKIND.
BLOCKMAPS:
    .word MAPNONE, MAP400K, MAP800K, MAP800K, MAP720K, MAP1440K, MAP1440K ; MEDIAKIND 0, 2, 4, 6, 8, $0A, $0C

;; BLOCKTOSECTOR for a disk of unknown format: no place.
;; Out:   carry = set, A = $3D
MAPNONE:
    stz SIDE
    stz TRACK
    stz SECTOR
    lda #$3D
    sec
    rts

;; BLOCKTOSECTOR for a 400K GCR disk: one side, the 4:1 interleave of Apple II disks.
MAP400K:
    lda PARAMLO
    sta SIDE
    and #$0F
    sta SECTOR
    lda PARAMMID
    rol SIDE
    rol A
    rol SIDE
    rol A
    rol SIDE
    rol A
    rol SIDE
    rol A
    tax
    lda GROUP400TRACK,X
    sta CYLINDER
    lda GROUP400SECTOR,X
    and #$E0
    ora SECTOR
    tay
    lda GROUP400SECTOR,X
    jsr ZONESECTOR400
    rts

;; MAP400K's first track (times 2) of each 32-block group.
GROUP400TRACK:
    .byte $00, $02, $04, $08, $0A, $0C, $10, $12, $14, $18, $1A, $1C, $20, $22, $24, $28
    .byte $2A, $2E, $30, $34, $36, $3A, $3C, $40, $42, $46, $48, $4C, $50, $52, $56, $58
    .byte $5C, $60, $62, $66, $6A, $6E, $70, $74, $78, $7C, $80, $84, $88, $8C, $90, $94
    .byte $98, $9C

;; MAP400K's group start: the zone (bits 5-7) and the first sector.
GROUP400SECTOR:
    .byte $00, $04, $08, $00, $04, $08, $00, $04, $08, $00, $04, $08, $20, $25, $2A, $24
    .byte $29, $23, $28, $22, $27, $21, $26, $40, $46, $42, $48, $44, $40, $46, $42, $48
    .byte $44, $60, $67, $65, $63, $61, $68, $66, $64, $62, $80, $80, $80, $80, $80, $80
    .byte $80, $80

;; BLOCKTOSECTOR for an 800K GCR disk: two sides, a track's two sides in turn.
MAP800K:
    lda PARAMLO
    sta SIDE
    and #$1F
    sta SECTOR
    lda PARAMMID
    rol SIDE
    rol A
    rol SIDE
    rol A
    rol SIDE
    rol A
    tax
    lda GROUP800TRACK,X
    sta CYLINDER
    lda GROUP800SECTOR,X
    and #$E0
    ora SECTOR
    tay
    lda GROUP800SECTOR,X
    jsr ZONESECTOR800
    rts

;; MAP800K's first cylinder of each 32-block group.
GROUP800TRACK:
    .byte $00, $02, $05, $08, $0A, $0D, $10, $12, $15, $18, $1A, $1D, $20, $22, $25, $28
    .byte $2B, $2E, $31, $34, $37, $3A, $3D, $40, $43, $46, $49, $4C, $50, $53, $56, $59
    .byte $5C, $60, $63, $67, $6A, $6E, $71, $75, $78, $7C, $80, $84, $88, $8C, $90, $94
    .byte $98, $9C

;; MAP800K's group start: the zone (bits 5-7) and the first sector.
GROUP800SECTOR:
    .byte $00, $08, $04, $00, $08, $04, $00, $08, $04, $00, $08, $04, $20, $2A, $29, $28
    .byte $27, $26, $25, $24, $23, $22, $21, $40, $42, $44, $46, $48, $40, $42, $44, $46
    .byte $48, $60, $65, $61, $66, $62, $67, $63, $68, $64, $80, $80, $80, $80, $80, $80
    .byte $80, $80

;; BLOCKTOSECTOR for a 1440K MFM disk: 18 sectors a side, sides in turn.
MAP1440K:
    ldx #$FE
MAP1440K_1:
    inx
    inx
    lda ZONES1440+2,X
    cmp PARAMLO
    lda ZONES1440+3,X
    sbc PARAMMID
    bcc MAP1440K_1
    lda PARAMLO
    sbc ZONES1440,X
    sta WORK0
    lda PARAMMID
    sbc ZONES1440+1,X
    sta WORK1
    lda CYLINDERS1440,X
    tax
    lda WORK0
    bpl MAP1440K_2
    sec
    sbc #$7E
    tay
    txa
    clc
    adc #$07
    tax
    tya
MAP1440K_2:
    cmp #$12
    bcc MAP1440K_5
MAP1440K_3:
    sec
    sbc #$12
    bmi MAP1440K_4
    inx
    bra MAP1440K_3
MAP1440K_4:
    clc
    adc #$12
MAP1440K_5:
    sta SECTOR
    stx CYLINDER
    txa
    lsr A
    sta TRACK
    lda #$00
    bcc MAP1440K_6
    lda #$20
MAP1440K_6:
    sta SIDE
    lda #$12
    clc
    rts

;; MAP1440K's blocks where each run of 10 cylinders starts, and the end ($FFFF).
ZONES1440:
    .byte $00
    .byte $00
    .byte $B4
    .byte $00, $68, $01, $1C, $02, $D0, $02, $84, $03, $38, $04, $EC, $04, $A0, $05, $54
    .byte $06, $08, $07, $BC, $07, $70, $08, $24, $09, $D8, $09, $8C, $0A, $40, $0B, $FF
    .byte $FF

;; And the first cylinder of each run.
CYLINDERS1440:
    .byte $00, $00, $0A, $00, $14, $00, $1E, $00, $28, $00, $32, $00, $3C, $00, $46, $00
    .byte $50, $00, $5A, $00, $64, $00, $6E, $00, $78, $00, $82, $00, $8C, $00, $96, $00
    .byte $FF, $FF

;; BLOCKTOSECTOR for a 720K MFM disk: 9 sectors a side, sides in turn.
MAP720K:
    ldx #$FE
MAP720K_1:
    inx
    inx
    lda ZONES720+2,X
    cmp PARAMLO
    lda ZONES720+3,X
    sbc PARAMMID
    bcc MAP720K_1
    lda PARAMLO
    sbc ZONES720,X
    sta WORK0
    lda PARAMMID
    sbc ZONES720+1,X
    sta WORK1
    lda CYLINDERS720,X
    tax
    lda WORK0
    cmp #$09
    bcc MAP720K_4
MAP720K_2:
    sec
    sbc #$09
    bmi MAP720K_3
    inx
    bra MAP720K_2
MAP720K_3:
    clc
    adc #$09
MAP720K_4:
    sta SECTOR
    stx CYLINDER
    txa
    lsr A
    sta TRACK
    lda #$00
    bcc MAP720K_5
    lda #$20
MAP720K_5:
    sta SIDE
    lda #$09
    clc
    rts

;; MAP720K's blocks where each run of 10 cylinders starts, and the end ($FFFF).
ZONES720:
    .byte $00
    .byte $00
    .byte $5A
    .byte $00, $B4, $00, $0E, $01, $68, $01, $C2, $01, $1C, $02, $76, $02, $D0, $02, $2A
    .byte $03, $84, $03, $DE, $03, $38, $04, $92, $04, $EC, $04, $46, $05, $A0, $05, $FF
    .byte $FF

;; And the first cylinder of each run.
CYLINDERS720:
    .byte $00, $00, $0A, $00, $14, $00, $1E, $00, $28, $00, $32, $00, $3C, $00, $46, $00
    .byte $50, $00, $5A, $00, $64, $00, $6E, $00, $78, $00, $82, $00, $8C, $00, $96, $00
    .byte $FF, $FF

;; Finishes MAP800K: the track and sector from a group of 32 blocks and the zone's sector count.
ZONESECTOR800:
    and #$1F
    clc
    sta SECTOR
    lda GROUPOFFSETS,Y
    and #$1F
    adc SECTOR
    tax
    lda GROUPOFFSETS,Y
    lsr A
    lsr A
    lsr A
    lsr A
    lsr A
    clc
    adc CYLINDER
    sta CYLINDER
    lsr A
    lsr A
    lsr A
    lsr A
    lsr A
    tay
    txa
    cmp ZONESECTORS,Y
    bcc ZONESECTOR800_1
    sbc ZONESECTORS,Y
    inc CYLINDER
ZONESECTOR800_1:
    sta SECTOR
    lda CYLINDER
    lsr A
    sta TRACK
    lda #$00
    bcc ZONESECTOR800_2
    lda #$20
ZONESECTOR800_2:
    sta SIDE
    lda ZONESECTORS,Y
    clc
    rts

;; Finishes MAP400K: the track and sector from a group of 32 blocks and the zone's sector count.
ZONESECTOR400:
    and #$1F
    clc
    sta SECTOR
    lda GROUPOFFSETS,Y
    and #$1F
    adc SECTOR
    tax
    lda GROUPOFFSETS,Y
    lsr A
    lsr A
    lsr A
    lsr A
    and #$0E
    clc
    adc CYLINDER
    sta CYLINDER
    lsr A
    lsr A
    lsr A
    lsr A
    lsr A
    tay
    txa
    cmp ZONESECTORS,Y
    bcc ZONESECTOR400_1
    sbc ZONESECTORS,Y
    inc CYLINDER
    inc CYLINDER
ZONESECTOR400_1:
    sta SECTOR
    lda CYLINDER
    lsr A
    sta TRACK
    stz SIDE
    lda ZONESECTORS,Y
    clc
    rts

;; The cylinder (bits 5-7) and sector (bits 0-4) of each block in a group, by zone.
GROUPOFFSETS:
    .byte $00, $01, $02, $03, $04, $05, $06, $07, $08, $09, $0A, $0B, $20, $21, $22, $23
    .byte $24, $25, $26, $27, $28, $29, $2A, $2B, $40, $41, $42, $43, $44, $45, $46, $47
    .byte $00, $01, $02, $03, $04, $05, $06, $07, $08, $09, $0A, $20, $21, $22, $23, $24
    .byte $25, $26, $27, $28, $29, $2A, $40, $41, $42, $43, $44, $45, $46, $47, $48, $49
    .byte $00, $01, $02, $03, $04, $05, $06, $07, $08, $09, $20, $21, $22, $23, $24, $25
    .byte $26, $27, $28, $29, $40, $41, $42, $43, $44, $45, $46, $47, $48, $49, $60, $61
    .byte $00, $01, $02, $03, $04, $05, $06, $07, $08, $20, $21, $22, $23, $24, $25, $26
    .byte $27, $28, $40, $41, $42, $43, $44, $45, $46, $47, $48, $60, $61, $62, $63, $64
    .byte $00, $01, $02, $03, $04, $05, $06, $07, $20, $21, $22, $23, $24, $25, $26, $27
    .byte $40, $41, $42, $43, $44, $45, $46, $47, $60, $61, $62, $63, $64, $65, $66, $67
    .byte $00, $01, $02, $03, $04, $05, $06, $07, $08, $09, $0A, $0B, $0C, $0D, $0E, $0F
    .byte $10, $11, $00, $01, $02, $03, $04, $05, $06, $07, $08, $09, $0A, $0B, $0C, $0D
    .byte $0E, $0F, $10, $11, $00, $01, $02, $03, $04, $05, $06, $07, $08, $09, $0A, $0B
    .byte $0C, $0D, $0E, $0F, $10, $11, $00, $01, $02, $03, $04, $05, $06, $07, $08, $09
    .byte $12, $11, $10, $0F, $0E, $0D

;; The GCR sectors per track in each 16-track zone: 12, 11, 10, 9, 8.
ZONESECTORS:
    .byte $0C, $0B, $0A, $09, $08

;; Counts a retry: RESULTA/RESULTX tally the errors, RETRIES counts down.
;; Out:   carry = set with ERRORCODE = $27 when the retries are used up; else A = DISKERRORS, which is cleared
COUNTRETRY:
    inc RESULTA
    bne COUNTRETRY_1
    inc RESULTX
COUNTRETRY_1:
    dec RETRIES
    bpl COUNTRETRY_2
    lda #$27
    sta ERRORCODE
    sec
    rts
COUNTRETRY_2:
    lda DISKERRORS
    stz DISKERRORS
    clc
    rts

;; SmartPort READ ($08) and WRITE ($09): a 524-byte block with its 12 tag bytes, on a GCR 400K or 800K
;; disk. The byte count must be $020C, and the address parameter is the block number.
;; Out:   READ: the tags and data at $0C00-$0E0B, CARDDATA = 6
READWRITE:
    lda #$11
    ldx DRIVE
    bpl READWRITE_2
READWRITE_1:
    jmp SETERROR
READWRITE_2:
    jsr CHECKDISK
    bpl READWRITE_3
    jsr IDENTIFYMEDIA
READWRITE_3:
    bcs READWRITE_1
    lda MEDIAKIND,Y
    cmp #$04
    beq READWRITE_4
    cmp #$02
    beq READWRITE_4
    lda #$27
    jmp SETERROR
READWRITE_4:
    lda COUNTHI
    cmp #$02
    beq READWRITE_6
READWRITE_5:
    jmp ERRBADPARAMETER
READWRITE_6:
    lda COUNTLO
    cmp #$0C
    bne READWRITE_5
    lda PARAMHI
    sta PARAMLO
    lda PARAM3
    sta PARAMMID
    stz PARAMHI
    stz PARAM3
    dec TAGCALL
    lda #$06
    sta BUFFERCODE
    lda CARDSTATE
    cmp #$01
    beq READWRITE_7
    jmp DOWRITEBLOCK
READWRITE_7:
    jsr READTAGGED
    bcs READWRITE_10
    ldy #$0B
READWRITE_8:
    lda TAGBYTES,Y
    sta XFERBUFFER,Y
    dey
    bpl READWRITE_8
    ldy #$00
READWRITE_9:
    lda XFERBUFFER+$200,Y
    sta XFERBUFFER+$0C,Y
    lda XFERBUFFER+$300,Y
    sta XFERBUFFER+$10C,Y
    iny
    bne READWRITE_9
    lda BUFFERCODE
    stz ERRORCODE
    sta CARDDATA
READWRITE_10:
    clc
    rts

;; Reads the block in PARAMLO/PARAMMID and its tags into buffer code 6's two halves.
;; Out:   carry = set with ERRORCODE set if it failed
READTAGGED:
    jsr CHECKBLOCK
    bcs READTAGGED_7
    lda #$06
    sta RETRIES
    stz SWIMSTATE
    jsr MOTORON
    jsr BLOCKTOSECTOR
    bcs READTAGGED_7
    asl A
    asl A
    asl A
    sta SECTORCOUNT
READTAGGED_1:
    jsr SEEK
    bcs READTAGGED_6
READTAGGED_2:
    lda BUFFERCODE
    jsr SETBUFFER
    jsr WAITREADYEVER
READTAGGED_3:
    jsr READADDRESS
    bcc READTAGGED_8
    jsr COUNTRETRY
    bcs READTAGGED_6
    bit #$04
    bne READTAGGED_1
    bit #$01
    beq READTAGGED_4
    jsr RECALIBRATE
    bcc READTAGGED_1
READTAGGED_4:
    bit #$20
    beq READTAGGED_6
READTAGGED_5:
    dec SECTORCOUNT
    bne READTAGGED_3
READTAGGED_6:
    lda #$27
READTAGGED_7:
    jsr SETERROR
    sec
    rts
READTAGGED_8:
    lda HDRSECTOR
    cmp SECTOR
    bne READTAGGED_5
    jsr READDATA
    bcc READTAGGED_9
    jsr COUNTRETRY
    bcc READTAGGED_2
    bra READTAGGED_6
READTAGGED_9:
    clc
    rts

;; SmartPort READBLOCK ($01), and ProDOS READ: reads the block from the cache, or reads its whole
;; track into the cache and hands the host the block's buffer as soon as it is read.
;; Out:   CARDDATA = the buffer code the host copies from, or 0 with ERRORCODE set
DOREADBLOCK:
    lda #$11
    ldx DRIVE
    bpl DOREADBLOCK_2
DOREADBLOCK_1:
    jmp SETERROR
DOREADBLOCK_2:
    jsr CHECKDISK
    bpl DOREADBLOCK_3
    jsr IDENTIFYMEDIA
DOREADBLOCK_3:
    bcs DOREADBLOCK_1
    jsr CHECKBLOCK
    bcs DOREADBLOCK_1
    lda #$80
    sta READING
    ldx DRIVE
    lda #$60
    bit MEDIAMODE,X
    beq DOREADBLOCK_5
    bit TAGCALL
    bpl DOREADBLOCK_4
    lda #$21
    sta TAGERROR
    rts
DOREADBLOCK_4:
    jsr MFMON
DOREADBLOCK_5:
    jsr BLOCKTOSECTOR
    bcs DOREADBLOCK_1
    sta SECTORS
    and #$10
    asl A
    adc #$60
    sta SECTORTRIES
    jsr FINDCACHED
    bcc DOREADBLOCK_6
    sta CARDDATA
    clc
    rts
DOREADBLOCK_6:
    lda #$06
    sta RETRIES
    lda #$04
    sta RESULTP
    lda #$14
    sta RESULTY
    jsr MOTORON
    lda #$00
    sta SPANLOW
    lda SECTORS
    sta SPANHIGH
    dec A
    sta SECTORCOUNT
    lda #$C0
    ldx SECTORS
DOREADBLOCK_7:
    sta SECTORFLAGS,X
    cpx SPANLOW
    bcc DOREADBLOCK_8
    cpx SPANHIGH
    bcs DOREADBLOCK_8
    stz SECTORFLAGS,X
DOREADBLOCK_8:
    dex
    bpl DOREADBLOCK_7
    lda CACHEOPTION
    sta READOPTION
    bra DOREADBLOCK_10
DOREADBLOCK_9:
    jsr RECALIBRATE
    bcs DOREADBLOCK_FAIL
DOREADBLOCK_10:
    dec RESULTP
    bmi DOREADBLOCK_FAIL
    jsr SEEK
    bcs DOREADBLOCK_FAIL
    jsr WAITREADY
    bcc DOREADBLOCK_READ
DOREADBLOCK_11:
    lda #$2F
    bra DOREADBLOCK_15
DOREADBLOCK_READ:
    stz DISKERRORS
    jsr READADDRESS
    bcc DOREADBLOCK_16
    lda DISKERRORS
    bit #$04
    bne DOREADBLOCK_10
    bit #$20
    beq DOREADBLOCK_14
    dec SECTORTRIES
    beq DOREADBLOCK_FAIL
    lda SECTORTRIES
    and #$3F
    lsr A
    cmp SECTORS
    beq DOREADBLOCK_12
    bit #$08
    beq DOREADBLOCK_READ
    bra DOREADBLOCK_10
DOREADBLOCK_12:
    bit READOPTION
    bvc DOREADBLOCK_9
DOREADBLOCK_13:
    jsr LEAVEISMIF
    sec
    rts
DOREADBLOCK_14:
    bit #$01
    beq DOREADBLOCK_FAIL
    bit READOPTION
    bvs DOREADBLOCK_13
    lda #$02
    jsr DRIVESENSE
    bcs DOREADBLOCK_11
    dec RESULTP
    bmi DOREADBLOCK_FAIL
    jsr RECALIBRATE
    stz DISKERRORS
    jsr READADDRESS
    bcc DOREADBLOCK_10
    ldx DRIVE
    jsr FORGETDISK
DOREADBLOCK_FAIL:
    lda #$27
DOREADBLOCK_15:
    bit READOPTION
    bvs DOREADBLOCK_13
    jmp SETERROR
DOREADBLOCK_16:
    ldx HDRSECTOR
    cpx SECTOR
    bne DOREADBLOCK_18
    bit READOPTION
    bvs DOREADBLOCK_13
    jsr FILLSLOT
    stz READING
    jsr READDATA
    bcc DOREADBLOCK_17
    jsr COUNTRETRY
    bcs DOREADBLOCK_FAIL
    bra DOREADBLOCK_26
DOREADBLOCK_17:
    lda BUFFERCODE
    sta CARDDATA
    lda SECTORCOUNT
    ora #$80
    sta CARDSTATE
    lda #$40
    tsb READOPTION
    bra DOREADBLOCK_23
DOREADBLOCK_18:
    bit READOPTION
    bmi DOREADBLOCK_26
    bit SECTORFLAGS,X
    bvs DOREADBLOCK_19
    ldy SECTORSLOTS,X
    lda CACHEOWNER-1,Y
    bmi DOREADBLOCK_22
    cmp DRIVE
    bne DOREADBLOCK_22
    lda CACHECYLINDER-1,Y
    cmp CYLINDER
    bne DOREADBLOCK_22
    lda CACHESECTORS-1,Y
    cmp HDRSECTOR
    bne DOREADBLOCK_22
    lda #$40
    sta SECTORFLAGS,X
    bra DOREADBLOCK_25
DOREADBLOCK_19:
    bit READOPTION
    bvc DOREADBLOCK_26
    ldx #$08
DOREADBLOCK_20:
    lda #$CC
DOREADBLOCK_21:
    bit CARDSTATE
    bpl DOREADBLOCK_27
    dec A
    bne DOREADBLOCK_21
    dex
    bne DOREADBLOCK_20
    bra DOREADBLOCK_26
DOREADBLOCK_22:
    jsr FILLSLOT
    jsr READDATA
    bcc DOREADBLOCK_23
    dec RESULTY
    bpl DOREADBLOCK_25
    lda #$80
    tsb READOPTION
    bra DOREADBLOCK_25
DOREADBLOCK_23:
    ldx HDRSECTOR
    lda #$40
    sta SECTORFLAGS,X
    lda HDRSECTOR
    jsr CACHESECTOR
    bcc DOREADBLOCK_25
DOREADBLOCK_24:
    jmp DOREADBLOCK_FAIL
DOREADBLOCK_25:
    bit READOPTION
    bvc DOREADBLOCK_26
    bmi DOREADBLOCK_27
    dec SECTORCOUNT
    beq DOREADBLOCK_27
    lda CARDSTATE
    bpl DOREADBLOCK_27
DOREADBLOCK_26:
    jsr LEAVEISMIF
    dec SECTORTRIES
    beq DOREADBLOCK_24
    jmp DOREADBLOCK_READ
DOREADBLOCK_27:
    jsr LEAVEISMIF
    bit READOPTION
    bvs DOREADBLOCK_28
    clc
    rts
DOREADBLOCK_28:
    sec
    rts

;; SmartPort WRITEBLOCK ($02), and ProDOS WRITE: asks the host for the block in buffer code 6 and
;; writes it; on a IIgs it starts writing while the host is still copying.
;; Out:   ERRORCODE = the error
DOWRITEBLOCK:
    lda #$11
    ldx DRIVE
    bmi DOWRITEBLOCK_2
    jsr CHECKDISK
    bpl DOWRITEBLOCK_1
    jsr IDENTIFYMEDIA
DOWRITEBLOCK_1:
    bcc DOWRITEBLOCK_3
DOWRITEBLOCK_2:
    jmp SETERROR
DOWRITEBLOCK_3:
    bne DOWRITEBLOCK_2
    jsr CHECKBLOCK
    bcs DOWRITEBLOCK_2
    ldx DRIVE
    lda #$60
    bit MEDIAMODE,X
    beq DOWRITEBLOCK_5
    bit TAGCALL
    bpl DOWRITEBLOCK_4
    lda #$21
    sta TAGERROR
    rts
DOWRITEBLOCK_4:
    jsr MFMON
DOWRITEBLOCK_5:
    lda #$06
    sta RETRIES
    lda #$03
    sta RESULTP
    jsr BLOCKTOSECTOR
    bcs DOWRITEBLOCK_2
    sta SECTORS
    and #$18
    asl A
    adc #$60
    sta SECTORTRIES
    ldx SECTOR
    jsr FILLSLOT
    stz CARDPROGRESS
    bit TESTCALL
    bmi DOWRITEBLOCK_6
    bit SHARED_EXPANSION+HOSTTYPEOFFSET
    bvc DOWRITEBLOCK_6
    bit TAGCALL
    bmi DOWRITEBLOCK_6
    bit SWIMSTATE
    bmi DOWRITEBLOCK_6
    dec CARDPROGRESS
DOWRITEBLOCK_6:
    lda BUFFERCODE
    sta CARDDATA
    jsr MOTORON
    jsr SEEK
    bcs DOWRITEBLOCK_19
    bit TESTCALL
    bmi DOWRITEBLOCK_9
    bit CARDPROGRESS
    bmi DOWRITEBLOCK_8
DOWRITEBLOCK_7:
    lda CARDDATA
    bpl DOWRITEBLOCK_7
DOWRITEBLOCK_8:
    bit TAGCALL
    bpl DOWRITEBLOCK_9
    jsr PREPAREDATATAGS
    bra DOWRITEBLOCK_10
DOWRITEBLOCK_9:
    jsr PREPAREDATA
DOWRITEBLOCK_10:
    jsr WAITREADY
    bcc DOWRITEBLOCK_12
DOWRITEBLOCK_11:
    lda #$2F
    bra DOWRITEBLOCK_20
DOWRITEBLOCK_12:
    jsr READADDRESS
    bcc DOWRITEBLOCK_16
    lda DISKERRORS
    bit #$04
    bne DOWRITEBLOCK_14
    bit #$20
    beq DOWRITEBLOCK_15
    dec SECTORTRIES
    beq DOWRITEBLOCK_19
    lda SECTORTRIES
    and #$3F
    lsr A
    cmp SECTORS
    beq DOWRITEBLOCK_13
    bit #$08
    beq DOWRITEBLOCK_12
    bra DOWRITEBLOCK_14
DOWRITEBLOCK_13:
    jsr RECALIBRATE
    bcs DOWRITEBLOCK_19
DOWRITEBLOCK_14:
    dec RESULTP
    bmi DOWRITEBLOCK_19
    jsr SEEK
    bcc DOWRITEBLOCK_10
    bra DOWRITEBLOCK_19
DOWRITEBLOCK_15:
    bit #$01
    beq DOWRITEBLOCK_19
    lda #$02
    jsr DRIVESENSE
    bcs DOWRITEBLOCK_11
    bra DOWRITEBLOCK_13
DOWRITEBLOCK_16:
    lda HDRSECTOR
    cmp SECTOR
    beq DOWRITEBLOCK_17
    dec SECTORTRIES
    beq DOWRITEBLOCK_19
    jsr LEAVEISMIF
    bra DOWRITEBLOCK_12
DOWRITEBLOCK_17:
    jsr WRITEDATA
    bcs DOWRITEBLOCK_19
    bit TESTCALL
    bmi DOWRITEBLOCK_18
    lda SECTOR
    jsr CACHESECTOR
DOWRITEBLOCK_18:
    clc
    rts
DOWRITEBLOCK_19:
    lda #$27
DOWRITEBLOCK_20:
    sta ERRORCODE
    clc
    rts

;; The boot command ($0C): READBLOCK of block 0 of unit 1 as a ProDOS call, or $28 if there is no
;; drive 1. A SmartPort bus device as unit 1 is read through the bus.
BOOTREAD:
    stz ERRORCODE
    stz SIDE
    stz TRACK
    stz CYLINDER
    jsr FLUSHCACHE
    lda #$01
    sta CARDSTATE
    ora #$80
    sta CARDCOMMAND
    stz PARAMLO
    stz PARAMMID
    stz PARAMHI
    stz DRIVE
    lda #$01
    sta CARDUNIT
    stz SAVEDRIVE
    ldx SAVEDRIVE
    lda DEVICEKIND,X
    beq BOOTREAD_2
    bmi BOOTREAD_1
    jsr FORGETDISK
    jmp CALLHANDLER
BOOTREAD_1:
    lda #$FF
    jsr DELAY2
    jmp PASSTOBUS
BOOTREAD_2:
    lda #$28
    sta ERRORCODE
    stz CARDDATA
    clc
    rts

;; Unused, to put the tables below on a page.
GCRHIGH_PAD:
    .res $E200-*

;; The high two bits of a 6-and-2 auxiliary nibble's three fields, for READDATAGCR.
GCRHIGH1:
.repeat 64, I
    .byte ((I >> 4) & 3) << 6
.endrepeat
GCRHIGH2:
.repeat 64, I
    .byte ((I >> 2) & 3) << 6
.endrepeat
GCRHIGH3:
.repeat 64, I
    .byte ((I >> 0) & 3) << 6
.endrepeat

;; Command $0D: checks a run of blocks (PARAM4/PARAM5 more after the first) and works out how many
;; lie in the first block's track, for the host, then waits briefly for the next command.
;; Out:   carry = set (the host's next command is run at once)
READAHEAD:
    lda #$11
    ldx DRIVE
    bpl READAHEAD_2
READAHEAD_1:
    jmp SETERROR
READAHEAD_2:
    jsr CHECKDISK
    bpl READAHEAD_3
    jsr IDENTIFYMEDIA
READAHEAD_3:
    bcs READAHEAD_1
    jsr CHECKBLOCK
    bcs READAHEAD_1
    lda #$80
    sta READING
    ldx DRIVE
    lda #$60
    bit MEDIAMODE,X
    beq READAHEAD_4
    jsr MFMON
READAHEAD_4:
    lda PARAMMID
    pha
    lda PARAMLO
    pha
    clc
    adc PARAM4
    sta PARAMLO
    lda PARAMMID
    adc PARAM5
    sta PARAMLO
    jsr CHECKBLOCK
    bcs READAHEAD_1
    pla
    sta PARAMLO
    pla
    sta PARAMMID
    jsr BLOCKTOSECTOR
    bcs READAHEAD_1
    sta SECTORS
    stz COUNTHI
    lda SECTORS
    sec
    sbc SECTOR
    sta SECTORCOUNT
    ldy PARAM5
    bne READAHEAD_5
    cmp PARAM4
    beq READAHEAD_5
    bcc READAHEAD_5
    lda PARAM4
READAHEAD_5:
    sta COUNTLO
    stz CARDDATA
    lda #$FF
    sta CARDSTATE
    lda #$05
    sta WORKPTR+1
    stz WORKPTR
READAHEAD_6:
    dec WORKPTR
    bne READAHEAD_7
    dec WORKPTR+1
    bmi READAHEAD_8
READAHEAD_7:
    lda CARDSTATE
    bmi READAHEAD_6
READAHEAD_8:
    sec
    rts

;; Command $0E: reads the sectors of a run of blocks that share a track into the cache, and lists in
;; $0600 how many were read and, from $0602, each one's buffer code ($A7 for one that failed).
;; Out:   carry = set when all were read (the host's next command is run at once)
READSPAN:
    lda #$11
    ldx DRIVE
    bpl READSPAN_2
READSPAN_1:
    jmp SETERROR
READSPAN_2:
    jsr CHECKDISK
    bpl READSPAN_3
    jsr IDENTIFYMEDIA
READSPAN_3:
    bcs READSPAN_1
    jsr CHECKBLOCK
    bcs READSPAN_1
    lda #$80
    sta READING
    ldx DRIVE
    lda #$60
    bit MEDIAMODE,X
    beq READSPAN_4
    jsr MFMON
READSPAN_4:
    jsr BLOCKTOSECTOR
    bcs READSPAN_1
    sta SECTORS
    lda SECTOR
    sta SPANFIRST
    lda CYLINDER
    sta SPANCYLINDER
    lda PARAM4
    clc
    adc PARAMLO
    sta PARAMLO
    lda PARAM5
    adc PARAMMID
    sta PARAMMID
    lda PARAMLO
    bne READSPAN_5
    dec PARAMMID
READSPAN_5:
    dec PARAMLO
    jsr CHECKBLOCK
    bcs READSPAN_1
    jsr BLOCKTOSECTOR
    bcs READSPAN_1
    lda CYLINDER
    cmp SPANCYLINDER
    beq READSPAN_6
    lda #$2D
    jmp SETERROR
READSPAN_6:
    stz INTERLEAVEMAP
    stz INTERLEAVEMAP+1
    ldx SECTORS
READSPAN_7:
    dex
    stz INTERLEAVEMAP+2,X
    bne READSPAN_7
    lda SPANFIRST
    sta SPANLOW
    lda SECTOR
    inc A
    sta SPANHIGH
    sec
    sbc SPANFIRST
    sta SECTORCOUNT
    asl A
    asl A
    sta RETRIES
    lda #$40
    ldx SECTORS
    stx HDRSECTOR
READSPAN_8:
    sta SECTORFLAGS,X
    cpx SPANLOW
    bcc READSPAN_9
    cpx SPANHIGH
    bcs READSPAN_9
    stz SECTORFLAGS,X
READSPAN_9:
    dex
    bpl READSPAN_8
    lda #$03
    sta CARDDATA
    lda SECTORS
    asl A
    asl A
    inc A
    sta SECTORTRIES
    lda #$02
    sta RESULTP
    jsr MOTORON
    bra READSPAN_11
READSPAN_10:
    jsr RECALIBRATE
    bcs READSPAN_15
READSPAN_11:
    dec RESULTP
    bmi READSPAN_15
    jsr SEEK
    bcs READSPAN_15
    jsr WAITREADY
    bcc READSPAN_14
READSPAN_12:
    lda #$2F
    bra READSPAN_26
READSPAN_13:
    jsr LEAVEISMIF
READSPAN_14:
    stz DISKERRORS
    jsr READADDRESS
    bcc READSPAN_18
    lda DISKERRORS
    bit #$04
    bne READSPAN_11
    bit #$20
    bne READSPAN_16
    bit #$01
    bne READSPAN_12
READSPAN_15:
    bra READSPAN_25
READSPAN_16:
    dec SECTORTRIES
    beq READSPAN_25
    lda SECTORTRIES
    cmp SECTORS
    bne READSPAN_17
    bra READSPAN_10
READSPAN_17:
    bit #$08
    beq READSPAN_14
    bra READSPAN_11
READSPAN_18:
    ldx HDRSECTOR
    bit SECTORFLAGS,X
    bvs READSPAN_19
    jsr FILLSLOT
    jsr READDATA
    bcs READSPAN_24
    ldx HDRSECTOR
    lda #$40
    sta SECTORFLAGS,X
    txa
    sec
    sbc SPANFIRST
    tax
    lda BUFFERCODE
    sta INTERLEAVEMAP+2,X
    inc INTERLEAVEMAP
    dec SECTORCOUNT
    beq READSPAN_27
    bra READSPAN_23
READSPAN_19:
    stz SCRATCH
    ldx #$08
READSPAN_20:
    lda #$CC
READSPAN_21:
    bit SCRATCH
    bpl READSPAN_22
READSPAN_22:
    dec A
    bne READSPAN_21
    dex
    bne READSPAN_20
READSPAN_23:
    dec SECTORTRIES
    bne READSPAN_13
    bra READSPAN_25
READSPAN_24:
    dec RETRIES
    bpl READSPAN_13
    lda HDRSECTOR
    sec
    sbc SPANFIRST
    tax
    lda #$A7
    sta INTERLEAVEMAP+2,X
READSPAN_25:
    lda #$27
READSPAN_26:
    sta ERRORCODE
    lda #$01
    sta INTERLEAVEMAP+1
    clc
    rts
READSPAN_27:
    lda #$FF
    sta CARDSTATE
    lda #$05
    sta WORKPTR+1
    stz WORKPTR
READSPAN_28:
    dec WORKPTR
    bne READSPAN_29
    dec WORKPTR+1
    bmi READSPAN_30
READSPAN_29:
    lda CARDSTATE
    bmi READSPAN_28
READSPAN_30:
    sec
    rts

;; Unused, to put READADDRESS on a page: GCRDECODE is indexed from it.
READADDRESS_PAD:
    .res $E500-*

;; Finds the next sector's address field, by GCR or MFM.
;; Out:   carry = set if none was read: DISKERRORS bit 0 = no field, 2 = the wrong track, 5 = a bad field,
;;        or $28 = the wrong side; else HDRTRACK, HDRSECTOR, HDRSIDE, HDRFORMAT set
READADDRESS:
    bit SWIMSTATE
    bpl READADDRESS_1
    jmp READADDRESSMFM
READADDRESS_1:
    jmp VECREADADDRESS

;; The VECREADADDRESS routine: reads a GCR address field (D5 AA 96, five fields, DE AA).
READADDRESSGCR:
    jsr SELECTREADHEAD
    stz DISKERRORS
    lda IWM_Q6L
    lda IWM_Q7L
    lda #$08
    sta WORKPTR
    ldy #$00
READADDRESSGCR_1:
    ldx #$02
READADDRESSGCR_2:
    dey
    bne READADDRESSGCR_3
    dec WORKPTR
    beq READADDRESSGCR_10
READADDRESSGCR_3:
    lda IWM_Q6L
    bpl READADDRESSGCR_3
    cmp ADDRESSMARK,X
    bne READADDRESSGCR_1
    dex
    bpl READADDRESSGCR_2
    ldx #$04
    stz HEADERSUM
READADDRESSGCR_4:
    ldy IWM_Q6L
    bpl READADDRESSGCR_4
    lda GCRDECODE-$96,Y
    sta HDRCHECK,X
    eor HEADERSUM
    sta HEADERSUM
    dex
    bpl READADDRESSGCR_4
    tay
    bne READADDRESSGCR_11
READADDRESSGCR_5:
    ldx IWM_Q6L
    bpl READADDRESSGCR_5
    cpx EPILOGUE+2
    bne READADDRESSGCR_11
READADDRESSGCR_6:
    ldx IWM_Q6L
    bpl READADDRESSGCR_6
    cpx EPILOGUE+1
    bne READADDRESSGCR_11
    ldx DRIVE
    lda HDRFORMAT
    sta FORMATBYTE,X
    and #$20
    asl A
    asl A
    sta SIDES,X
    lda HDRSIDE
    eor SIDE
    lsr A
    bne READADDRESSGCR_9
    lda HDRTRACK
    bcc READADDRESSGCR_7
    ora #$40
READADDRESSGCR_7:
    cmp TRACK
    beq READADDRESSGCR_8
    ldx DRIVE
    sta CURTRACK,X
    lda #$04
    bra READADDRESSGCR_12
READADDRESSGCR_8:
    clc
    rts
READADDRESSGCR_9:
    lda #$28
    bra READADDRESSGCR_12
READADDRESSGCR_10:
    lda #$01
    bra READADDRESSGCR_12
READADDRESSGCR_11:
    lda #$20
READADDRESSGCR_12:
    tsb DISKERRORS
    sec
    rts

;; Disk bytes $8F-$95, never valid.
GCRINVALID:
    .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF

;; The 6-and-2 GCR decode table for disk bytes $96-$FF (an invalid byte holds a value of $80 or more), indexed from $E500.
GCRDECODE:
    .byte $00, $01, $98, $99, $02, $03, $9C, $04, $05, $06, $A0, $A1, $A2, $A3, $A4, $A5
    .byte $07, $08, $A8, $A9, $AA, $09, $0A, $0B, $0C, $0D, $B0, $B1, $0E, $0F, $10, $11
    .byte $12, $13, $B8, $14, $15, $16, $17, $18, $19, $1A, $C0, $C1, $C2, $C3, $C4, $C5
    .byte $C6, $C7, $C8, $C9, $CA, $1B, $CC, $1C, $1D, $1E, $D0, $D1, $D2, $1F, $D4, $D5
    .byte $20, $21, $D8, $22, $23, $24, $25, $26, $27, $28, $E0, $E1, $E2, $E3, $E4, $29
    .byte $2A, $2B, $E8, $2C, $2D, $2E, $2F, $30, $31, $32, $F0, $F1, $33, $34, $35, $36
    .byte $37, $38, $F8, $39, $3A, $3B, $3C, $3D, $3E, $3F

;; Selects the drive's read-data register for SIDE's head and puts the IWM in read mode.
SELECTREADHEAD:
    lda #$01
    jsr DRIVESENSE
    jsr SELECTHEAD
    bit IWM_Q6L
    bit IWM_Q7L
    rts

;; Reads the data field after an address field, by GCR or MFM, into BUFPTR and BUFPTR2.
;; Out:   carry = set if it failed (DISKERRORS bit 0 = no field, 3 = bad epilogue, 4 = bad checksum)
READDATA:
    bit SWIMSTATE
    bpl READDATA_1
    jmp READDATAMFM
READDATA_1:
    jmp VECREADDATA

;; The VECREADDATA routine: reads a GCR data field: the sector number, 12 tag bytes to TAGBYTES
;; and 512 data bytes, with their three checksums.
READDATAGCR:
    stz CHECKSUM2
    stz CHECKSUM1
    stz CHECKSUM0
    stz DISKERRORS
    ldy #$19
READDATAGCR_1:
    ldx #$02
READDATAGCR_2:
    dey
    beq READDATAGCR_5
READDATAGCR_3:
    lda IWM_Q6L
    bpl READDATAGCR_3
    cmp DATAMARK,X
    bne READDATAGCR_1
    dex
    bpl READDATAGCR_2
    ldy #$0C
READDATAGCR_4:
    ldx IWM_Q6L
    bpl READDATAGCR_4
    lda GCRDECODE-$96,X
    eor HDRSECTOR
    beq READDATAGCR_6
READDATAGCR_5:
    lda #$01
    jmp READDATAGCR_FAIL
READDATAGCR_6:
    clc
READDATAGCR_7:
    ldx IWM_Q6L
    bpl READDATAGCR_7
    adc CHECKSUM0
    cmp #$80
    rol A
    sta CHECKSUM0
    lda GCRDECODE-$96,X
    sta WORK0
READDATAGCR_8:
    ldx IWM_Q6L
    bpl READDATAGCR_8
    lda GCRDECODE-$96,X
    ldx WORK0
    ora GCRHIGH1,X
    eor CHECKSUM0
    sta TAGBYTES-1,Y
    dey
    adc CHECKSUM2
    sta CHECKSUM2
READDATAGCR_9:
    ldx IWM_Q6L
    bpl READDATAGCR_9
    lda GCRDECODE-$96,X
    ldx WORK0
    ora GCRHIGH2,X
    eor CHECKSUM2
    sta TAGBYTES-1,Y
    dey
    adc CHECKSUM1
    sta CHECKSUM1
READDATAGCR_10:
    ldx IWM_Q6L
    bpl READDATAGCR_10
    lda GCRDECODE-$96,X
    ldx WORK0
    ora GCRHIGH3,X
    eor CHECKSUM1
    sta TAGBYTES-1,Y
    dey
    bne READDATAGCR_7
    bra READDATAGCR_13
READDATAGCR_11:
    ldx IWM_Q6L
    lda GCRDECODE-$96,X
    ora GCRHIGH2,Y
    eor CHECKSUM2
    sta (BUFPTR)
    inc BUFPTR
    adc CHECKSUM1
    sta CHECKSUM1
READDATAGCR_12:
    ldx IWM_Q6L
    bpl READDATAGCR_12
    lda GCRDECODE-$96,X
    ora GCRHIGH3,Y
    eor CHECKSUM1
    sta (BUFPTR)
    inc BUFPTR
READDATAGCR_13:
    ldx IWM_Q6L
    bpl READDATAGCR_13
    adc CHECKSUM0
    cmp #$80
    rol A
    sta CHECKSUM0
    ldy GCRDECODE-$96,X
READDATAGCR_14:
    ldx IWM_Q6L
    bpl READDATAGCR_14
    lda GCRDECODE-$96,X
    ora GCRHIGH1,Y
    eor CHECKSUM0
    sta (BUFPTR)
    adc CHECKSUM2
    sta CHECKSUM2
    inc BUFPTR
    bne READDATAGCR_11
    ldx IWM_Q6L
    lda GCRDECODE-$96,X
    ora GCRHIGH2,Y
    eor CHECKSUM2
    sta (BUFPTR2)
    adc CHECKSUM1
    sta CHECKSUM1
    inc BUFPTR2
    nop
READDATAGCR_15:
    ldx IWM_Q6L
    lda GCRDECODE-$96,X
    ora GCRHIGH3,Y
    eor CHECKSUM1
    sta (BUFPTR2)
    inc BUFPTR2
READDATAGCR_16:
    ldx IWM_Q6L
    bpl READDATAGCR_16
    adc CHECKSUM0
    cmp #$80
    rol A
    sta CHECKSUM0
    ldy GCRDECODE-$96,X
READDATAGCR_17:
    ldx IWM_Q6L
    bpl READDATAGCR_17
    lda GCRDECODE-$96,X
    ora GCRHIGH1,Y
    eor CHECKSUM0
    sta (BUFPTR2)
    inc BUFPTR2
    adc CHECKSUM2
    sta CHECKSUM2
READDATAGCR_18:
    ldx IWM_Q6L
    bpl READDATAGCR_18
    lda GCRDECODE-$96,X
    ora GCRHIGH2,Y
    eor CHECKSUM2
    sta (BUFPTR2)
    adc CHECKSUM1
    sta CHECKSUM1
    inc BUFPTR2
    bne READDATAGCR_15
    ldx IWM_Q6L
    ldy GCRDECODE-$96,X
    lda GCRHIGH3,Y
    sta WORK0
    lda GCRHIGH2,Y
    sta WORK1
    lda GCRHIGH1,Y
    ldx #$02
READDATAGCR_19:
    ldy IWM_Q6L
    bpl READDATAGCR_19
    ora GCRDECODE-$96,Y
    eor CHECKSUM0,X
    sta CHECKSUM0,X
    lda CHECKSUMNIB,X
    dex
    bpl READDATAGCR_19
    ldx #$02
READDATAGCR_20:
    lda IWM_Q6L
    bpl READDATAGCR_20
    cmp EPILOGUE,X
    bne READDATAGCR_21
    dex
    bne READDATAGCR_20
    bra READDATAGCR_22
READDATAGCR_21:
    lda #$08
    tsb DISKERRORS
READDATAGCR_22:
    lda CHECKSUM2
    ora CHECKSUM1
    ora CHECKSUM0
    bne READDATAGCR_23
    lda DISKERRORS
    cmp #$01
    rts
READDATAGCR_23:
    lda #$10
READDATAGCR_FAIL:
    tsb DISKERRORS
    sec
    rts

;; Nibblizes a sector for WRITEDATA, keeping the tag bytes in the buffers (READWRITE's writes).
PREPAREDATATAGS:
    ldx #$AF
    bra PREPAREDATA_2

;; Nibblizes a sector for WRITEDATA with zero tags. On a IIgs host (CARDPROGRESS negative) it
;; follows the host's copy: $C0 first half, $C1 second, $D0 done.
PREPAREDATA:
    ldx #$04
PREPAREDATA_1:
    stz NIBBLES1+$AB,X
    stz NIBBLES2+$AB,X
    stz NIBBLES3+$AA,X
    dex
    bne PREPAREDATA_1
    ldx #$AB
PREPAREDATA_2:
    bit SWIMSTATE
    bpl PREPAREDATA_3
    lda BUFPTR+1
    inc A
    sta BUFPTR2+1
    lda BUFPTR
    sta BUFPTR2
    rts
PREPAREDATA_3:
    stx NIBBLESTART
    lda BUFPTR+1
    sta BUFPTR2+1
PREPAREDATA_4:
    lda CARDPROGRESS
    bpl PREPAREDATA_7
    cmp #$D0
    beq PREPAREDATA_6
    cmp #$C1
    beq PREPAREDATA_7
    cmp #$C0
    bne PREPAREDATA_4
    ldy #$C8
PREPAREDATA_5:
    dey
    bne PREPAREDATA_5
    bra PREPAREDATA_7
PREPAREDATA_6:
    stz CARDPROGRESS
PREPAREDATA_7:
    stz CHECKSUM2
    stz CHECKSUM1
    stz CHECKSUM0
    clc
    ldy #$00
    bra PREPAREDATA_9
PREPAREDATA_8:
    lda (BUFPTR),Y
    eor CHECKSUM1
    sta NIBBLES3,X
    eor CHECKSUM1
    adc CHECKSUM0
    cmp #$80
    rol A
    sta CHECKSUM0
    iny
    bne PREPAREDATA_9
    inc BUFPTR+1
    lda CARDPROGRESS
    bpl PREPAREDATA_9
    eor #$D0
    bne PREPAREDATA_11
PREPAREDATA_9:
    lda (BUFPTR),Y
    eor CHECKSUM0
    sta NIBBLES1,X
    eor CHECKSUM0
    adc CHECKSUM2
    sta CHECKSUM2
    iny
    bne PREPAREDATA_10
    inc BUFPTR+1
    lda CARDPROGRESS
    bpl PREPAREDATA_10
    eor #$D0
    bne PREPAREDATA_11
PREPAREDATA_10:
    lda (BUFPTR),Y
    eor CHECKSUM2
    sta NIBBLES2,X
    eor CHECKSUM2
    adc CHECKSUM1
    sta CHECKSUM1
    iny
    bne PREPAREDATA_14
    inc BUFPTR+1
    lda CARDPROGRESS
    bpl PREPAREDATA_14
    eor #$D0
    beq PREPAREDATA_14
PREPAREDATA_11:
    cmp #$11
    beq PREPAREDATA_13
    lda #$D0
PREPAREDATA_12:
    cmp CARDPROGRESS
    bne PREPAREDATA_12
    stz CARDPROGRESS
PREPAREDATA_13:
    lda BUFPTR2+1
    sta BUFPTR+1
    ldx NIBBLESTART
    bra PREPAREDATA_7
PREPAREDATA_14:
    dex
    bne PREPAREDATA_8
    lda CHECKSUM0
    lsr A
    lsr A
    eor CHECKSUM1
    and #$30
    eor CHECKSUM1
    lsr A
    lsr A
    eor CHECKSUM2
    and #$3C
    eor CHECKSUM2
    lsr A
    lsr A
    sta CHECKSUMNIB
    lda NIBBLES1+$AF
    sta NIBBLE0
    asl A
    rol NIBBLEHIGH
    asl A
    rol NIBBLEHIGH
    lda NIBBLES2+$AF
    sta NIBBLE1
    asl A
    rol NIBBLEHIGH
    asl A
    rol NIBBLEHIGH
    lda NIBBLES3+$AE
    sta NIBBLE2
    asl A
    rol NIBBLEHIGH
    asl A
    rol NIBBLEHIGH
    rts

;; Writes a data field after an address field, by GCR or MFM.
;; Out:   carry = set if it failed
WRITEDATA:
    bit SWIMSTATE
    bpl WRITEDATA_1
    jmp WRITEDATAMFM
WRITEDATA_1:
    jmp VECWRITEDATA

;; The VECWRITEDATA routine: writes the sync bytes, D5 AA AD, the nibblized sector and checksums,
;; and DE AA.
;; Out:   carry = set if the IWM underran (DISKERRORS bit 6)
WRITEDATAGCR:
    bit IWM_Q6H
    lda #$FF
    sta IWM_Q7H
    stz DISKERRORS
    ldx #$07
WRITEDATAGCR_1:
    lda DATAMARK,X
WRITEDATAGCR_2:
    bit IWM_Q6L
    bpl WRITEDATAGCR_2
    sta IWM_Q6H
    dex
    bpl WRITEDATAGCR_1
    ldy HDRSECTOR
    lda GCRENCODE,Y
WRITEDATAGCR_3:
    bit IWM_Q6L
    bpl WRITEDATAGCR_3
    sta IWM_Q6H
    ldx #$AE
    bra WRITEDATAGCR_5
WRITEDATAGCR_4:
    ldy NIBBLE2
    lda NIBBLES3,X
    sta NIBBLE2
    asl A
    rol NIBBLEHIGH
    asl A
    lda GCRENCODE,Y
    sta IWM_Q6H
    rol NIBBLEHIGH
WRITEDATAGCR_5:
    ldy NIBBLEHIGH
    lda GCRENCODE,Y
WRITEDATAGCR_6:
    bit IWM_Q6L
    bpl WRITEDATAGCR_6
    sta IWM_Q6H
    ldy NIBBLE0
    lda NIBBLES1,X
    sta NIBBLE0
    asl A
    rol NIBBLEHIGH
    asl A
    rol NIBBLEHIGH
    lda GCRENCODE,Y
    sta IWM_Q6H
    ldy NIBBLE1
    lda NIBBLES2,X
    sta NIBBLE1
    asl A
    rol NIBBLEHIGH
    asl A
    rol NIBBLEHIGH
    lda GCRENCODE,Y
    sta IWM_Q6H
    dex
    cpx #$FF
    bne WRITEDATAGCR_4
    ldx #$03
WRITEDATAGCR_7:
    ldy CHECKSUM0,X
    lda GCRENCODE,Y
WRITEDATAGCR_8:
    bit IWM_Q6L
    bpl WRITEDATAGCR_8
    sta IWM_Q6H
    dex
    bpl WRITEDATAGCR_7
    ldx #$02
WRITEDATAGCR_9:
    lda EPILOGUE,X
WRITEDATAGCR_10:
    bit IWM_Q6L
    bpl WRITEDATAGCR_10
    sta IWM_Q6H
    dex
    bpl WRITEDATAGCR_9
    lda #$40
    and IWM_Q6L
    eor #$40
    tsb DISKERRORS
WRITEDATAGCR_11:
    bit IWM_Q6L
    bvs WRITEDATAGCR_11
    bit IWM_Q7L
    lda DISKERRORS
    cmp #$01
    rts

;; Reads an MFM ID field through the ISM (A1 A1 A1 FE, track, side, sector, size, CRC).
READADDRESSMFM:
    jsr SELECTREADHEAD
    stz DISKERRORS
    jsr ENTERISM
    ldy #$FF
    sty WORKPTR
    bra READADDRESSMFM_4
READADDRESSMFM_1:
    ldx #$02
    ldy #$FF
READADDRESSMFM_2:
    bit ISM_rHandshake
    bmi READADDRESSMFM_3
    dey
    bmi READADDRESSMFM_2
    bra READADDRESSMFM_4
READADDRESSMFM_3:
    lda ISM_rMark
    cmp MFMINDEXMARK,X
    bne READADDRESSMFM_4
    dex
    bpl READADDRESSMFM_2
READADDRESSMFM_4:
    bit ISM_rError
    lda #$18
    sta ISM_wZeroes
    lda #$01
    sta ISM_wOnes
    sta ISM_wZeroes
    bit ISM_rError
    lda #$08
    sta ISM_wOnes
READADDRESSMFM_5:
    bit ISM_rHandshake
    bmi READADDRESSMFM_6
    dey
    bne READADDRESSMFM_5
    dec WORKPTR
    bne READADDRESSMFM_5
    lda #$01
    jmp READADDRESSMFM_FAIL
READADDRESSMFM_6:
    lda ISM_rMark
    cmp #$A1
    beq READADDRESSMFM_7
    cmp #$C2
    beq READADDRESSMFM_1
    bra READADDRESSMFM_4
READADDRESSMFM_7:
    ldy #$FF
    ldx #$02
READADDRESSMFM_8:
    bit ISM_rHandshake
    bmi READADDRESSMFM_9
    dey
    bmi READADDRESSMFM_8
    bra READADDRESSMFM_4
READADDRESSMFM_9:
    lda ISM_rMark
    cmp MFMIDMARK,X
    bne READADDRESSMFM_4
    dex
    bpl READADDRESSMFM_8
READADDRESSMFM_10:
    bit ISM_rHandshake
    bpl READADDRESSMFM_10
    lda ISM_rData
    sta HDRTRACK
READADDRESSMFM_11:
    bit ISM_rHandshake
    bpl READADDRESSMFM_11
    lda #$00
    ldy ISM_rData
    beq READADDRESSMFM_12
    lda #$20
READADDRESSMFM_12:
    sta HDRSIDE
READADDRESSMFM_13:
    bit ISM_rHandshake
    bpl READADDRESSMFM_13
    lda ISM_rData
    dec A
    sta HDRSECTOR
READADDRESSMFM_14:
    bit ISM_rHandshake
    bpl READADDRESSMFM_14
    lda #$20
    ora ISM_rData
    sta HDRFORMAT
READADDRESSMFM_15:
    bit ISM_rHandshake
    bpl READADDRESSMFM_15
    lda ISM_rData
    sta HEADERSUM
READADDRESSMFM_16:
    lda ISM_rHandshake
    bpl READADDRESSMFM_16
    ldy ISM_rData
    sty CHECKSUM0
    ldy ISM_rError
    sty CHECKSUM1
    sta CHECKSUM2
    and #$22
    bne READADDRESSMFM_18
    lda #$18
    sta ISM_wZeroes
    ldx DRIVE
    lda #$80
    sta SIDES,X
    lda HDRSIDE
    beq READADDRESSMFM_17
    lda #$20
READADDRESSMFM_17:
    eor SIDE
    bne READADDRESSMFM_20
    lda HDRTRACK
    cmp TRACK
    beq READADDRESSMFM_19
    sta CURTRACK,X
    lda #$04
    bra READADDRESSMFM_FAIL
READADDRESSMFM_18:
    lda #$20
READADDRESSMFM_FAIL:
    tsb DISKERRORS
    lda #$18
    sta ISM_wZeroes
    lda ISM_rError
    jsr LEAVEISM
    sec
    rts
READADDRESSMFM_19:
    clc
    rts
READADDRESSMFM_20:
    lda #$28
    bra READADDRESSMFM_FAIL

;; The MFM index mark (C2 C2 FC), read last byte first.
MFMINDEXMARK:
    .byte $FC, $C2, $C2

;; The ID mark (A1 A1 FE), last byte first.
MFMIDMARK:
    .byte $FE, $A1

;; The data mark (A1 A1 FB) and its first A1, last byte first.
MFMDATAMARK:
    .byte $A1, $FB, $A1, $A1, $A1

;; Reads an MFM data field through the ISM (A1 A1 A1 FB, 512 bytes, CRC).
READDATAMFM:
    bit ISM_rError
    lda #$18
    sta ISM_wZeroes
    lda #$01
    sta ISM_wOnes
    sta ISM_wZeroes
    bit ISM_rError
    lda #$08
    sta ISM_wOnes
    ldy #$80
READDATAMFM_1:
    dey
    bne READDATAMFM_3
READDATAMFM_2:
    lda #$18
    sta ISM_wZeroes
    jsr LEAVEISM
    sec
    rts
READDATAMFM_3:
    bit ISM_rHandshake
    bpl READDATAMFM_1
    lda ISM_rMark
    cmp #$A1
    bne READDATAMFM_1
    ldx #$03
    ldy #$14
READDATAMFM_4:
    bit ISM_rHandshake
    bmi READDATAMFM_5
    dey
    bpl READDATAMFM_4
    bra READDATAMFM_2
READDATAMFM_5:
    lda ISM_rMark
    cmp MFMDATAMARK,X
    bne READDATAMFM_2
    dex
    bne READDATAMFM_4
READDATAMFM_6:
    bit ISM_rHandshake
    bvc READDATAMFM_6
    lda ISM_rData
    ldx ISM_rData
    sta (BUFPTR)
    inc BUFPTR
    txa
    sta (BUFPTR)
    inc BUFPTR
    bne READDATAMFM_6
READDATAMFM_7:
    bit ISM_rHandshake
    bvc READDATAMFM_7
    lda ISM_rData
    ldx ISM_rData
    sta (BUFPTR2)
    inc BUFPTR2
    txa
    sta (BUFPTR2)
    inc BUFPTR2
    bne READDATAMFM_7
READDATAMFM_8:
    bit ISM_rHandshake
    bpl READDATAMFM_8
    lda ISM_rData
    sta HEADERSUM
READDATAMFM_9:
    lda ISM_rHandshake
    bpl READDATAMFM_9
    ldy ISM_rData
    sty CHECKSUM0
    ldy ISM_rError
    sty CHECKSUM1
    sta CHECKSUM2
    and #$22
    bne READDATAMFM_10
    lda #$18
    sta ISM_wZeroes
    stz DISKERRORS
    jsr LEAVEISM
    clc
    rts
READDATAMFM_10:
    lda #$18
    sta ISM_wZeroes
    jsr LEAVEISM
    lda #$10
    ora DISKERRORS
    sta DISKERRORS
    sec
    rts

;; Writes an MFM data field through the ISM.
WRITEDATAMFM:
    lda #$F0
    sta ISM_wPhase
    bit ISM_rError
    lda #$18
    sta ISM_wZeroes
    lda #$10
    sta ISM_wOnes
    lda #$01
    sta ISM_wOnes
    sta ISM_wZeroes
    bit ISM_rError
    ldy #$24
WRITEDATAMFM_1:
    lda ISM_rHandshake
    lda ISM_rHandshake
    lda ISM_rHandshake
    dey
    bne WRITEDATAMFM_1
    stz ISM_wData
    stz ISM_wData
    lda #$08
    sta ISM_wOnes
    ldx #$0A
WRITEDATAMFM_2:
    bit ISM_rHandshake
    bpl WRITEDATAMFM_2
    stz ISM_wData
    dex
    bne WRITEDATAMFM_2
    ldx #$03
WRITEDATAMFM_3:
    bit ISM_rHandshake
    bpl WRITEDATAMFM_3
    lda #$A1
    sta ISM_wMark
    dex
    bne WRITEDATAMFM_3
WRITEDATAMFM_4:
    bit ISM_rHandshake
    bpl WRITEDATAMFM_4
    lda #$FB
    sta ISM_wData
    ldy #$00
WRITEDATAMFM_5:
    lda (BUFPTR),Y
WRITEDATAMFM_6:
    bit ISM_rHandshake
    bpl WRITEDATAMFM_6
    sta ISM_wData
    iny
    bne WRITEDATAMFM_5
WRITEDATAMFM_7:
    lda (BUFPTR2),Y
WRITEDATAMFM_8:
    bit ISM_rHandshake
    bpl WRITEDATAMFM_8
    sta ISM_wData
    iny
    bne WRITEDATAMFM_7
WRITEDATAMFM_9:
    bit ISM_rHandshake
    bpl WRITEDATAMFM_9
    stz ISM_wCRC
    ldx #$04
    lda #$4E
WRITEDATAMFM_10:
    ldy ISM_rHandshake
    bpl WRITEDATAMFM_10
    sta ISM_wData
    dex
    bne WRITEDATAMFM_10
WRITEDATAMFM_11:
    bit ISM_rHandshake
    bvc WRITEDATAMFM_11
    lda #$18
    sta ISM_wZeroes
    tya
    and #$20
    clc
    beq WRITEDATAMFM_12
    lda ISM_rError
    sta CHECKSUM1
WRITEDATAMFM_12:
    php
    ldx #$78
WRITEDATAMFM_13:
    bne WRITEDATAMFM_14
WRITEDATAMFM_14:
    nop
    dex
    bne WRITEDATAMFM_13
    jsr LEAVEISM
    plp
    rts

;; SmartPort CONTROL ($04): asks the host for the control list in buffer code 6 ($0C00) and runs the
;; control code in PARAMLO. Codes $14 and up, and the ones a unit does not take, answer $21; a list of
;; $400 bytes or more answers $22.
DOCONTROL:
    ldx PARAMLO
    cpx #$14
    bcs ERRBADCONTROL
    lda DRIVE
    bpl DOCONTROL_1
    bit CONTROLUNIT0,X
    bmi ERRBADCONTROL
    bvc DOCONTROL_1
    bra ERRBADCONTROL
DOCONTROL_1:
    ldx COUNTHI
    cpx #$04
    bcs ERRBADCTLPARAM
    lda #$06
    sta CARDDATA
DOCONTROL_2:
    lda CARDDATA
    bpl DOCONTROL_2
    lda PARAMLO
    asl A
    tax
    jmp (CONTROLHANDLERS,X)
ERRBADCONTROL:
    lda #$21
    bra CONTROLDONE
ERRBADCTLPARAM:
    lda #$22
CONTROLDONE:
    jmp SETERROR

;; The control codes unit 0 takes: bit 7 = not taken.
CONTROLUNIT0:
    .byte $80, $80, $80, $80, $80, $80, $80, $80, $80, $80, $80, $80, $00, $80, $00, $00
    .byte $00, $00, $00, $00

;; Each control code's handler ($00-$13).
CONTROLHANDLERS:
    .word CTLRESET, ERRBADCONTROL, ERRBADCONTROL, ERRBADCONTROL, CTLEJECT ; $00-$04
    .word ERRBADCONTROL, ERRBADCONTROL, ERRBADCONTROL, ERRBADCONTROL, CTLSETSIDES ; $05-$09
    .word CTLSETSKEW, ERRBADCONTROL, CTLPOKE, CTLRESETMARKS, CTLRESETVECTORS ; $0A-$0E
    .word CTLSETCACHE, CTLSETADDRESS, CTLDOWNLOAD, CTLEXECUTE, CTLPEEK ; $0F-$13

;; Control $0D: puts the GCR marks and sync bytes ($8D-$A2) back from the ROM.
CTLRESETMARKS:
    ldx #$16
CTLRESETMARKS_1:
    lda ZeroPageImage+MARKS-1,X
    sta MARKS-1,X
    dex
    bne CTLRESETMARKS_1
    bra CTLSETSIDES_1

;; Control $0E: puts the vectors ($72-$8C) back from the ROM.
CTLRESETVECTORS:
    ldx ZeroPageImage+VECTORLENGTH
CTLRESETVECTORS_1:
    lda ZeroPageImage+VECTORS-1,X
    sta VECTORS-1,X
    dex
    bne CTLRESETVECTORS_1
    bra CTLSETSIDES_1

;; Control $0F: one byte, whose bit 7 goes to CACHEOPTION; the cache is flushed.
CTLSETCACHE:
    lda #$01
    jsr CHECKCOUNT
    lda XFERBUFFER
    and #$80
    sta CACHEOPTION
    jsr FLUSHCACHE
    bra CTLSETSIDES_1

;; Control $0A: one byte, the interleave for FORMAT (below 13), or $32.
CTLSETSKEW:
    lda #$01
    jsr CHECKCOUNT
    bne ERRBADCTLPARAM
    lda #$32
    ldy XFERBUFFER
    cpy #$0D
    bcs CONTROLDONE
    sty SKEW
    ldx DRIVE
    sty FORMATSKEW,X
    bra CTLSETSIDES_1

;; Control $09: one byte, whose bit 7 set has FORMAT write both sides.
CTLSETSIDES:
    lda #$01
    jsr CHECKCOUNT
    bne SETADDRESSCOUNT_1
    lda XFERBUFFER
    and #$80
    sta TWOSIDED
CTLSETSIDES_1:
    lda #$00
    jmp CONTROLDONE

;; Control $00, reset: forgets the disk and reads it again.
;; Out:   carry = set if the drive has no usable disk
CTLRESET:
    ldx DRIVE
    jsr FORGETDISK
    jsr CHECKDISK
    bpl CTLRESET_1
    jsr IDENTIFYMEDIA
CTLRESET_1:
    bcc CTLRESET_2
    jmp SETERROR
CTLRESET_2:
    rts

;; Control $04, eject: ejects DRIVE's disk and forgets its sectors.
;; Out:   carry = clear
CTLEJECT:
    ldx DRIVE
    jsr READSENSE
    jsr EJECT
    ldx DRIVE
    jsr FORGETCACHE
    clc
    rts

;; Control $12: calls code in the card at an address set in the list (CALLUSER), and keeps A, X, Y
;; and P in RESULTA-RESULTP for status code 5.
CTLEXECUTE:
    jsr CALLUSER
    sta RESULTA
    stx RESULTX
    sty RESULTY
    php
    pla
    sta RESULTP
    clc
    rts

;; Control $13: two bytes, an address; its byte goes to RETRIES ($58) for status code 5.
CTLPEEK:
    jsr CTLSETADDRESS
    lda (USERPOINTER)
    sta RETRIES
    clc
    rts

;; Control $0C: three bytes, an address and (read from $0C04) a byte to store there.
CTLPOKE:
    lda #$03
    jsr SETADDRESSCOUNT
    lda XFERBUFFER+4
    sta (USERPOINTER)
    clc
    rts

;; Control $10: two bytes, an address in card RAM for CTLDOWNLOAD.
CTLSETADDRESS:
    lda #$02

;; Takes USERPOINTER from the list's first two bytes, if the list has the expected length.
;; In:    A = the length
;; Out:   carry = clear; or an error $22 through CONTROLDONE
SETADDRESSCOUNT:
    jsr CHECKCOUNT
    bne SETADDRESSCOUNT_1
    lda XFERBUFFER
    sta USERPOINTER
    lda XFERBUFFER+1
    sta USERPOINTER+1
    clc
    rts
SETADDRESSCOUNT_1:
    jmp ERRBADCTLPARAM

;; Control $11: copies the control list to USERPOINTER, leaving the pointer where it was.
CTLDOWNLOAD:
    ldx USERPOINTER+1
    ldy #$00
    lda #$00
    sta WORKPTR
    lda #$0C
    sta WORKPTR+1
CTLDOWNLOAD_1:
    lda (WORKPTR),Y
    sta (USERPOINTER),Y
    iny
    bne CTLDOWNLOAD_2
    inc WORKPTR+1
    inc USERPOINTER+1
CTLDOWNLOAD_2:
    dec COUNTLO
    bne CTLDOWNLOAD_1
    dec COUNTHI
    bpl CTLDOWNLOAD_1
    stx USERPOINTER+1
    clc
    rts

;; Loads A, X, Y and P from the list's first four bytes and jumps to the address in its next two.
CALLUSER:
    lda XFERBUFFER+4
    sta WORKPTR
    lda XFERBUFFER+5
    sta WORKPTR+1
    lda XFERBUFFER+3
    pha
    ldx XFERBUFFER+1
    ldy XFERBUFFER+2
    lda XFERBUFFER
    plp
    jmp (WORKPTR)

;; Compares the control list's length with A.
;; Out:   zero = it matches
CHECKCOUNT:
    ldy COUNTHI
    bne CHECKCOUNT_1
    cmp COUNTLO
CHECKCOUNT_1:
    rts

;; Ejects a drive's disk: the motor off (200 ms), the eject command, then up to about 2 s for the disk to leave.
;; In:    X = the drive
;; Out:   carry = clear; ERRORCODE = $27 if the disk did not leave
EJECT:
    stx EJECTDRIVE
    lda #$02
    jsr DRIVESENSE
    bcs EJECT_4
    lda #$08
    jsr DRIVESENSE
    bcs EJECT_1
    lda #$09
    jsr DRIVECOMMAND
    lda #$C8
    jsr DELAYMS
EJECT_1:
    lda #$03
    sta RETRIES
    lda #$0D
    jsr DRIVECOMMAND
    ldy #$C3
EJECT_2:
    lda #$0A
    jsr DELAYMS
    lda #$02
    jsr DRIVESENSE
    bcs EJECT_3
    dey
    bne EJECT_2
    lda #$27
    sta ERRORCODE
    bra EJECT_4
EJECT_3:
    jsr FORGETDISK
EJECT_4:
    lda #$80
    sta EJECTDRIVE
    clc
    rts

;; Unit 0's name, for status code 1.
CONTROLLERNAME:
    .byte "APPLE UNIVERSAL 3.5 CONTROLLER"

;; SmartPort STATUS ($00), and ProDOS STATUS: builds the status list at $0C00 for the host.
;; Unit 0: code 0, the controller's 8 bytes; code 1, its name. A 3.5 drive: code 0, the general status;
;; code 3, the DIB; code 5, the last result. Others answer $21.
;; Out:   COUNTLO, COUNTHI = the list's length, CARDDATA = 6
DOSTATUS:
    stz COUNTLO
    stz COUNTHI
    ldx DRIVE
    bpl DOSTATUS_2
    lda PARAMLO
    beq DOSTATUS_6
    cmp #$01
    bne DOSTATUS_4
    ldx #$1E
    stx XFERBUFFER
DOSTATUS_1:
    lda CONTROLLERNAME-1,X
    sta XFERBUFFER,X
    dex
    bne DOSTATUS_1
    ldx #$1E
    inx
    bra STATUSDONE
DOSTATUS_2:
    ldx PARAMLO
    beq STATUSDRIVE
    cpx #$03
    beq STATUSDRIVE
    cpx #$05
    bne DOSTATUS_3
    jmp STATUSRESULT
DOSTATUS_3:
    cpx #$06
    bne DOSTATUS_4
DOSTATUS_4:
    lda #$21
    jmp SETERROR
STATUSDONE:
    stx COUNTLO
    lda #$06
    sta CARDDATA
    ldx DRIVE
    bit UNITHIGHBIT
    bmi DOSTATUS_5
    jsr RELEASEDRIVE
    clc
    rts
DOSTATUS_5:
    clc
    rts
DOSTATUS_6:
    lda UNITCOUNT
    sta XFERBUFFER
    ldx #$01
    lda #$00
DOSTATUS_7:
    sta XFERBUFFER,X
    inx
    cpx #$08
    bne DOSTATUS_7
    lda #$01
    sta XFERBUFFER+2
    lda #$00
    sta XFERBUFFER+4
    lda #$01
    sta XFERBUFFER+5
DOSTATUS_8:
    bra STATUSDONE
STATUSRESULT:
    ldx #$00
DOSTATUS_9:
    lda ERRORCODE,X
    sta XFERBUFFER,X
    inx
    cpx #$08
    bcc DOSTATUS_9
    bra STATUSDONE
STATUSDRIVE:
    ldx DRIVE
    jsr READSENSE
    php
    and SENSE,X
    lsr A
    lsr A
    lsr A
    ora #$E8
    bvs DOSTATUS_10
    ora #$10
DOSTATUS_10:
    plp
    bmi DOSTATUS_11
    bvs DOSTATUS_12
    bit OLDSENSE
    bvc DOSTATUS_12
DOSTATUS_11:
    bit CARDCOMMAND
    bvc DOSTATUS_12
    ora #$01
DOSTATUS_12:
    sta XFERBUFFER
    jsr CHECKDISK
    bpl DOSTATUS_13
    jsr IDENTIFYMEDIA
DOSTATUS_13:
    ldx #$04
    ldy DRIVE
    lda BLOCKSLO,Y
    sta XFERBUFFER+1
    lda BLOCKSHI,Y
    sta XFERBUFFER+2
    stz XFERBUFFER+3
    bit CARDCOMMAND
    bvc DOSTATUS_14
    stz XFERBUFFER+4
    inx
DOSTATUS_14:
    lda PARAMLO
    beq DOSTATUS_8
    ldy DRIVE
    lda DEVICEKIND,Y
    ldy #$00
    bit #$02
    beq DOSTATUS_15
    ldy #$16
DOSTATUS_15:
    lda DIB35,Y
    sta XFERBUFFER,X
    inx
    iny
    cmp #$FF
    bne DOSTATUS_15
    dex
    jmp STATUSDONE

;; An Apple 3.5 Drive's DIB, after the status bytes, ended by $FF.
DIB35:
    .byte 8, "DISK 3.5        " ; the name's length and the name, padded to 16
    .byte $01, $C0, $10, $10        ; type, subtype, version
    .byte $FF                       ; the end

;; An FDHD drive's DIB.
DIBFDHD:
    .byte 8, "DISK 3.5HD      " ; the length leaves out "HD"
    .byte $01, $C1, $10, $10
    .byte $FF

;; Command $0B: lists the formats a drive can write, 16 bytes each, after an 8-byte header.
;; Out:   COUNTLO, COUNTHI = the length, CARDDATA = 6, ERRORCODE = $22 if PARAMLO and PARAMMID ask for less
FORMATOPTIONS:
    ldx DRIVE
    bpl FORMATOPTIONS_1
    lda #$11
    jmp SETERROR
FORMATOPTIONS_1:
    jsr CHECKDISK
    bpl FORMATOPTIONS_2
    jsr IDENTIFYMEDIA
FORMATOPTIONS_2:
    ldx #$FF
FORMATOPTIONS_3:
    stz XFERBUFFER,X
    stz XFERBUFFER+$100,X
    dex
    bne FORMATOPTIONS_3
    lda #$08
    sta BUFPTR2
    lda #$0C
    sta BUFPTR2+1
    stz XFERBUFFER
    stz XFERBUFFER+2
    ldx DRIVE
    lda MEDIAKIND,X
    sta XFERBUFFER+6
    lda #$02
    bit DEVICEKIND,X
    beq FORMATOPTIONS_5
    lda #$0A
    sta XFERBUFFER+4
    lda MEDIAMODE,X
    bit #$40
    bne FORMATOPTIONS_4
    lda #$06
    sta XFERBUFFER+4
FORMATOPTIONS_4:
    lda #$0A
    jsr ADDFORMATOPTION
    lda #$06
    jsr ADDFORMATOPTION
    lda #$08
    jsr ADDFORMATOPTION
    bra FORMATOPTIONS_6
FORMATOPTIONS_5:
    lda #$06
    sta XFERBUFFER+4
    lda #$06
    jsr ADDFORMATOPTION
FORMATOPTIONS_6:
    ldy #$00
    lda XFERBUFFER
    asl A
    asl A
    asl A
    asl A
    bcc FORMATOPTIONS_7
    iny
FORMATOPTIONS_7:
    clc
    adc #$08
    cpy PARAMMID
    bcc FORMATOPTIONS_10
    beq FORMATOPTIONS_9
FORMATOPTIONS_8:
    jmp ERRBADPARAMETER
FORMATOPTIONS_9:
    cmp PARAMLO
    beq FORMATOPTIONS_10
    bcs FORMATOPTIONS_8
FORMATOPTIONS_10:
    sta COUNTLO
    sty COUNTHI
    lda #$06
    sta CARDDATA
    clc
    rts

;; Adds a format to FORMATOPTIONS' list.
;; In:    A = the format kind; BUFPTR2 = where
ADDFORMATOPTION:
    inc XFERBUFFER
    inc XFERBUFFER+2
    ldy #$00
    sta (BUFPTR2)
    tax
    lda FORMATINFO,X
    and #$0F
    ldy #$04
    sta (BUFPTR2),Y
    lda FORMATINFO,X
    lsr A
    lsr A
    lsr A
    lsr A
    ldy #$0C
    sta (BUFPTR2),Y
    lda MEDIABLOCKS,X
    ldy #$06
    sta (BUFPTR2),Y
    iny
    lda MEDIABLOCKS+1,X
    sta (BUFPTR2),Y
    ldy #$0B
    lda #$02
    sta (BUFPTR2),Y
    lda MEDIABLOCKS+1,X
    lsr A
    ldy #$0F
    sta (BUFPTR2),Y
    lda MEDIABLOCKS,X
    ror A
    dey
    sta (BUFPTR2),Y
    lda BUFPTR2
    clc
    adc #$10
    sta BUFPTR2
    bcc ADDFORMATOPTION_1
    inc BUFPTR2+1
ADDFORMATOPTION_1:
    lda FORMATINFO+1,X
    beq ADDFORMATOPTION_2
    bpl ADDFORMATOPTION
ADDFORMATOPTION_2:
    rts

;; Each format kind: interleave (bits 4-7) and a type (bits 0-3); then the next kind FORMATOPTIONS lists, or 0.
FORMATINFO:
    .byte $00
    .byte $00, $25, $00, $45, $00, $25, $04, $16, $00, $24, $0C, $14, $00

;; Each MEDIAKIND's block count.
MEDIABLOCKS:
    .byte $00
    .byte $00, $20, $03, $40, $06, $40, $06, $A0, $05, $40, $0B, $40, $0B, $00, $00

;; Command $0A: chooses the format the next FORMAT writes.
;; In:    PARAMLO = the format kind (0, or an even number below $0D), PARAMHI = the interleave, or 0
;; Out:   ERRORCODE = $21 for a bad kind
SETFORMAT:
    lda PARAMMID
    beq SETFORMAT_2
SETFORMAT_1:
    jmp ERRBADCONTROL
SETFORMAT_2:
    lda PARAMLO
    cmp #$0D
    bcs SETFORMAT_1
    and #$01
    bne SETFORMAT_1
    ldx DRIVE
    lda PARAMLO
    bne SETFORMAT_3
    lda #$02
    sta FORMATKIND,X
    jsr CLEARFORMAT
    bra SETFORMAT_4
SETFORMAT_3:
    sta FORMATKIND,X
    tay
    lda FORMATINFO,Y
    lsr A
    lsr A
    lsr A
    lsr A
    sta FORMATSKEW,X
    lda PARAMHI
    beq SETFORMAT_4
    cmp #$0D
    bcs SETFORMAT_1
    sta FORMATSKEW,X
SETFORMAT_4:
    stz CARDDATA
    clc
    rts

;; SmartPort FORMAT ($03), through the VECFORMAT vector.
DOFORMAT:
    jmp VECFORMAT

;; The VECFORMAT routine: formats DRIVE's disk, in the kind SETFORMAT chose or the drive's default
;; (800K GCR; 1440K MFM for a high-density disk in an FDHD drive), verifying each track, then reads it
;; back for its format.
;; Out:   ERRORCODE = 0, $27, $2B, $2F or $21
FORMATDISK:
    lda #$01
    ldx DRIVE
    bmi FORMATDISK_1
    jsr FORGETCACHE
    lda #$03
    jsr DRIVECOMMAND
    jsr MFMOFF
    ldx DRIVE
    jsr CHECKDISK
    bcc FORMATDISK_2
FORMATDISK_1:
    jmp SETERROR
FORMATDISK_2:
    bne FORMATDISK_1
    lda #$80
    sta SIDES,X
    lda #$02
    bit DEVICEKIND,X
    bne CALLFORMATHOOK_1
    lda FORMATKIND,X
    beq FORMATDISK_3
    cmp #$08
    bcs CALLFORMATHOOK_3
FORMATDISK_3:
    jsr CALLFORMATHOOK
    bcs CALLFORMATHOOK_3
    bra CALLFORMATHOOK_6

;; Calls FORMATHOOK ($BA), which points at an RTS until something changes it.
CALLFORMATHOOK:
    jmp (FORMATHOOK)
CALLFORMATHOOK_1:
    lda #$0F
    jsr DRIVESENSE
    bcc CALLFORMATHOOK_4
    ldy FORMATKIND,X
    cpy #$08
    bne CALLFORMATHOOK_2
    lda #$50
    sta MFMGAP
    lda #$20
    sta MEDIAMODE,X
    bra CALLFORMATHOOK_5
CALLFORMATHOOK_2:
    cpy #$08
    bcc CALLFORMATHOOK_6
CALLFORMATHOOK_3:
    lda #$21
    bra FORMATDISK_1
CALLFORMATHOOK_4:
    lda #$40
    sta MEDIAMODE,X
    lda #$02
    sta SKEW
    lda #$65
    sta MFMGAP
    ldx DRIVE
    lda FORMATKIND,X
    beq CALLFORMATHOOK_5
    cmp #$0A
    beq CALLFORMATHOOK_5
    cmp #$0C
    bne CALLFORMATHOOK_3
CALLFORMATHOOK_5:
    jsr MFMON
    stz NIBBLEHIGH
    stz NIBBLE0
CALLFORMATHOOK_6:
    jsr FORGETCACHE
    jsr MOTORON
    jsr RECALIBRATE
    bcs CALLFORMATHOOK_12
    jsr WAITREADY
    bcs CALLFORMATHOOK_12
    ldy DRIVE
    ldx FORMATKIND,Y
    beq CALLFORMATHOOK_7
    lda FORMATSKEW,Y
    sta SKEW
    cpx #$02
    bne CALLFORMATHOOK_7
    stz TWOSIDED
CALLFORMATHOOK_7:
    stz SIDE
    stz TRACK
CALLFORMATHOOK_8:
    lda #$03
    sta RETRIES
CALLFORMATHOOK_9:
    jsr WRITETRACK
    bcs CALLFORMATHOOK_12
    jsr VERIFYTRACK
    bcc CALLFORMATHOOK_10
    jsr COUNTRETRY
    bcc CALLFORMATHOOK_9
    bra CALLFORMATHOOK_12
CALLFORMATHOOK_10:
    bit TWOSIDED
    bmi CALLFORMATHOOK_11
    lda #$20
    sta SIDE
    jsr WIPESIDE
CALLFORMATHOOK_11:
    lda #$20
    eor SIDE
    sta SIDE
    bne CALLFORMATHOOK_8
    inc TRACK
    lda TRACK
    cmp #$50
    bcc CALLFORMATHOOK_8
    stz SIDE
    stz TRACK
    ldx DRIVE
    jsr CLEARFORMAT
    jsr RECALIBRATE
    clc
    jsr IDENTIFYMEDIA
    bcs CALLFORMATHOOK_13
    rts
CALLFORMATHOOK_12:
    lda #$27
CALLFORMATHOOK_13:
    pha
    ldx DRIVE
    jsr CLEARFORMAT
    jsr EJECT
    pla
    jmp SETERROR

;; Forgets SETFORMAT's choice: the defaults (two sides, interleave 4) for the next FORMAT.
;; In:    X = the drive
CLEARFORMAT:
    lda FORMATKIND,X
    beq CLEARFORMAT_1
    lda #$80
    sta TWOSIDED
    lda #$04
    sta SKEW
    stz FORMATSKEW,X
    stz FORMATKIND,X
CLEARFORMAT_1:
    rts

;; Writes a track's length of $BB bytes over the second side of a single-sided GCR format.
WIPESIDE:
    bit SWIMSTATE
    bmi WIPESIDE_2
    lda TRACK
    lsr A
    lsr A
    lsr A
    and #$0E
    sta SCRATCH
    jsr SELECTREADHEAD
    ldx SCRATCH
    lda WIPELENGTHS+1,X
    tay
    lda WIPELENGTHS,X
    tax
    lda #$BB
    bit IWM_Q6H
    sta IWM_Q7H
WIPESIDE_1:
    bit IWM_Q6L
    bpl WIPESIDE_1
    sta IWM_Q6H
    dex
    bne WIPESIDE_1
    dey
    bne WIPESIDE_1
    bit IWM_Q7L
    bit IWM_Q6L
WIPESIDE_2:
    rts

;; WIPESIDE's byte counts (low, high) by zone.
WIPELENGTHS:
    .byte $94
    .byte $25, $74, $22, $54, $1F, $34, $1C, $14, $19

;; Writes a whole track, by GCR or MFM.
;; Out:   carry = set if it failed
WRITETRACK:
    bit SWIMSTATE
    bpl WRITETRACK_1
    jmp WRITETRACKMFM
WRITETRACK_1:
    jmp VECWRITETRACK

;; The VECWRITETRACK routine: writes a GCR track: each sector's address and an empty data field,
;; in INTERLEAVEMAP's order.
WRITETRACKGCR:
    jsr SEEK
    jsr MAKEHEADER
    jsr WAITREADYEVER
    stz DISKERRORS
    lda SIDE
    bne WRITETRACKGCR_1
    lda TRACK
    and #$0F
    bne WRITETRACKGCR_1
    lda TRACK
    lsr A
    lsr A
    lsr A
    lsr A
    tax
    lda ZONEDELAYS,X
    jsr DELAY2
WRITETRACKGCR_1:
    jsr SELECTREADHEAD
    lda SECTORS
    sta SECTORCOUNT
    ldy #$C8
    lda #$FF
    bit IWM_Q6H
    sta IWM_Q7H
WRITETRACKGCR_SECTOR:
    ldx #$04
WRITETRACKGCR_2:
    lda SYNCBYTES,X
WRITETRACKGCR_3:
    bit IWM_Q6L
    bpl WRITETRACKGCR_3
    sta IWM_Q6H
    dex
    bpl WRITETRACKGCR_2
    dey
    bne WRITETRACKGCR_SECTOR
    ldx #$03
WRITETRACKGCR_4:
    lda ADDRESSMARK,X
WRITETRACKGCR_5:
    bit IWM_Q6L
    bpl WRITETRACKGCR_5
    sta IWM_Q6H
    dex
    bpl WRITETRACKGCR_4
    ldx #$04
WRITETRACKGCR_6:
    ldy HDRCHECK,X
    lda GCRENCODE,Y
WRITETRACKGCR_7:
    bit IWM_Q6L
    bpl WRITETRACKGCR_7
    sta IWM_Q6H
    dex
    bpl WRITETRACKGCR_6
    ldx #$0B
WRITETRACKGCR_8:
    lda DATAMARK,X
WRITETRACKGCR_9:
    bit IWM_Q6L
    bpl WRITETRACKGCR_9
    sta IWM_Q6H
    dex
    bpl WRITETRACKGCR_8
    ldx HDRSECTOR
    lda GCRENCODE,X
WRITETRACKGCR_10:
    bit IWM_Q6L
    bpl WRITETRACKGCR_10
    sta IWM_Q6H
    ldx #$03
    ldy #$EB
    bra WRITETRACKGCR_12
WRITETRACKGCR_11:
    ldy #$EA
WRITETRACKGCR_12:
    lda #$96
WRITETRACKGCR_13:
    bit IWM_Q6L
    bpl WRITETRACKGCR_13
    sta IWM_Q6H
    dey
    bne WRITETRACKGCR_12
    dex
    bne WRITETRACKGCR_11
    ldx #$01
WRITETRACKGCR_14:
    lda EPILOGUE+1,X
WRITETRACKGCR_15:
    bit IWM_Q6L
    bpl WRITETRACKGCR_15
    sta IWM_Q6H
    dex
    bpl WRITETRACKGCR_14
    dec SECTORCOUNT
    beq WRITETRACKGCR_16
    lda HDRSECTOR
    eor HDRCHECK
    ldy SECTORCOUNT
    ldx INTERLEAVEMAP-1,Y
    stx HDRSECTOR
    eor HDRSECTOR
    ldy #$FF
    sty IWM_Q6H
    sta HDRCHECK
    ldy #$0A
    jmp WRITETRACKGCR_SECTOR
WRITETRACKGCR_16:
    lda #$40
    and IWM_Q6L
    eor #$40
    tsb DISKERRORS
WRITETRACKGCR_17:
    lda IWM_Q6L
    bpl WRITETRACKGCR_17
    lda #$FF
    sta IWM_Q6H
WRITETRACKGCR_18:
    bit IWM_Q6L
    bvs WRITETRACKGCR_18
    bit IWM_Q7L
    lda DISKERRORS
    cmp #$01
    rts

;; Milliseconds / 2 to wait before writing the first track of each GCR zone.
ZONEDELAYS:
    .byte $96, $19, $19, $19, $19

;; Reads back each sector of the track just written, through the VECVERIFY vector.
VERIFYTRACK:
    jmp VECVERIFY

;; The VECVERIFY routine: reads every sector of the track once.
;; Out:   carry = set if one failed
VERIFYTRACKGCR:
    jsr DELAY1MS
    lda #$00
    sta BUFPTR
    sta BUFPTR2
    lda #$0C
    sta BUFPTR+1
    sta BUFPTR2+1
    jsr SELECTREADHEAD
    ldx SECTORS
    stx SECTORCOUNT
VERIFYTRACKGCR_1:
    stz SECTORFLAGS,X
    dex
    bpl VERIFYTRACKGCR_1
VERIFYTRACKGCR_2:
    jsr READADDRESS
    bcs VERIFYTRACKGCR_4
    ldx HDRSECTOR
    cpx SECTORS
    bcs VERIFYTRACKGCR_3
    lda SECTORFLAGS,X
    bmi VERIFYTRACKGCR_3
    lda #$FF
    sta SECTORFLAGS,X
    jsr READDATA
    bcs VERIFYTRACKGCR_4
    dec SECTORCOUNT
    bne VERIFYTRACKGCR_2
    clc
    rts
VERIFYTRACKGCR_3:
    jsr LEAVEISMIF
VERIFYTRACKGCR_4:
    sec
    rts

;; Works out a GCR track's sector count, interleave map and address-field bytes.
MAKEHEADER:
    lda TRACK
    lsr A
    lsr A
    lsr A
    lsr A
    tax
    lda ZONESECTORS,X
    sta SECTORS
    jsr MAKEINTERLEAVE
    lda TRACK
    and #$3F
    sta HDRTRACK
    stz HDRSECTOR
    lda TRACK
    and #$40
    beq MAKEHEADER_1
    inc A
MAKEHEADER_1:
    ldx SIDE
    beq MAKEHEADER_2
    ora #$20
MAKEHEADER_2:
    sta HDRSIDE
    lda SKEW
    bit TWOSIDED
    bpl MAKEHEADER_3
    ora #$20
MAKEHEADER_3:
    sta HDRFORMAT
    eor HDRSIDE
    eor HDRTRACK
    sta HDRCHECK
    rts

;; Builds INTERLEAVEMAP: the order of the track's sectors for SKEW.
MAKEINTERLEAVE:
    lda SKEW
    bne MAKEINTERLEAVE_1
    lda #$01
    sta SKEW
MAKEINTERLEAVE_1:
    lda SECTORS
    dec A
    dec A
    cmp SKEW
    bcs MAKEINTERLEAVE_2
    sta SKEW
MAKEINTERLEAVE_2:
    ldx SECTORS
    inx
    lda #$FF
MAKEINTERLEAVE_3:
    sta INTERLEAVEMAP,X
    dex
    bpl MAKEINTERLEAVE_3
    ldx SECTORS
    dex
    ldy #$00
MAKEINTERLEAVE_4:
    tya
    sta INTERLEAVEMAP,X
    iny
    cpy SECTORS
    beq MAKEINTERLEAVE_7
    txa
    sec
    sbc SKEW
    tax
MAKEINTERLEAVE_5:
    bpl MAKEINTERLEAVE_6
    txa
    clc
    adc SECTORS
    tax
MAKEINTERLEAVE_6:
    bit INTERLEAVEMAP,X
    bmi MAKEINTERLEAVE_4
    dex
    bra MAKEINTERLEAVE_5
MAKEINTERLEAVE_7:
    clc
MAKEINTERLEAVE_8:
    rts

;; Writes an MFM track through the ISM: the gaps, each sector's ID and an empty data field.
WRITETRACKMFM:
    jsr SEEK
    stz UNITHIGHBIT
    lda #$12
    ldx DRIVE
    ldy FORMATKIND,X
    cpy #$08
    bne WRITETRACKMFM_1
    lda #$09
    dec UNITHIGHBIT
WRITETRACKMFM_1:
    sta SECTORS
    sta SECTORCOUNT
    jsr MAKEINTERLEAVE
    jsr WAITREADY
    bcs MAKEINTERLEAVE_8
    lda TRACK
    bne WRITETRACKMFM_2
    lda SIDE
    bne WRITETRACKMFM_2
    lda #$96
    jsr DELAY2
    lda #$96
    jsr DELAY2
WRITETRACKMFM_2:
    jsr SELECTREADHEAD
    jsr ENTERISM
    bit ISM_rError
    lda #$18
    sta ISM_wZeroes
    lda #$10
    sta ISM_wOnes
    lda #$01
    sta ISM_wOnes
    sta ISM_wZeroes
    sta HDRSECTOR
    bit ISM_rError
    ldy #$34
    ldx #$35
    bit UNITHIGHBIT
    bpl WRITETRACKMFM_3
    ldy #$9A
    ldx #$1A
WRITETRACKMFM_3:
    lda #$4E
    sta ISM_wData
    sta ISM_wData
    lda #$08
    sta ISM_wOnes
WRITETRACKMFM_4:
    bit ISM_rHandshake
    bpl WRITETRACKMFM_4
    beq WRITETRACKMFM_5
    lda #$4E
    sta ISM_wData
    lda #$08
    dey
    bne WRITETRACKMFM_4
    dex
    bne WRITETRACKMFM_4
    jmp WRITETRACKMFM_TIMEOUT
WRITETRACKMFM_5:
    lda #$4E
    sta ISM_wData
    lda #$08
WRITETRACKMFM_6:
    bit ISM_rHandshake
    bpl WRITETRACKMFM_6
    bne WRITETRACKMFM_7
    lda #$4E
    sta ISM_wData
    lda #$08
    dey
    bne WRITETRACKMFM_6
    dex
    bne WRITETRACKMFM_6
    jmp WRITETRACKMFM_TIMEOUT
WRITETRACKMFM_7:
    lda #$4E
    sta ISM_wData
    lda #$F0
    sta ISM_wPhase
    ldx #$4F
    lda #$4E
WRITETRACKMFM_8:
    bit ISM_rHandshake
    bpl WRITETRACKMFM_8
    sta ISM_wData
    dex
    bne WRITETRACKMFM_8
    ldx #$0C
WRITETRACKMFM_9:
    bit ISM_rHandshake
    bpl WRITETRACKMFM_9
    stz ISM_wData
    dex
    bne WRITETRACKMFM_9
    ldx #$03
WRITETRACKMFM_10:
    bit ISM_rHandshake
    bpl WRITETRACKMFM_10
    lda #$C2
    sta ISM_wMark
    dex
    bne WRITETRACKMFM_10
WRITETRACKMFM_11:
    bit ISM_rHandshake
    bpl WRITETRACKMFM_11
    lda #$FC
    sta ISM_wData
    ldx #$32
    lda #$4E
WRITETRACKMFM_12:
    bit ISM_rHandshake
    bpl WRITETRACKMFM_12
    sta ISM_wData
    dex
    bne WRITETRACKMFM_12
    bra WRITETRACKMFM_14
WRITETRACKMFM_SECTOR:
    ldx MFMGAP
    lda #$4E
WRITETRACKMFM_13:
    bit ISM_rHandshake
    bpl WRITETRACKMFM_13
    sta ISM_wData
    dex
    bne WRITETRACKMFM_13
WRITETRACKMFM_14:
    ldx #$0C
WRITETRACKMFM_15:
    bit ISM_rHandshake
    bpl WRITETRACKMFM_15
    stz ISM_wData
    dex
    bne WRITETRACKMFM_15
    ldx #$03
WRITETRACKMFM_16:
    bit ISM_rHandshake
    bpl WRITETRACKMFM_16
    lda #$A1
    sta ISM_wMark
    dex
    bne WRITETRACKMFM_16
WRITETRACKMFM_17:
    bit ISM_rHandshake
    bpl WRITETRACKMFM_17
    lda #$FE
    sta ISM_wData
    lda TRACK
WRITETRACKMFM_18:
    bit ISM_rHandshake
    bpl WRITETRACKMFM_18
    sta ISM_wData
    lda #$00
    ldx SIDE
    beq WRITETRACKMFM_19
    inc A
WRITETRACKMFM_19:
    bit ISM_rHandshake
    bpl WRITETRACKMFM_19
    sta ISM_wData
    lda HDRSECTOR
WRITETRACKMFM_20:
    bit ISM_rHandshake
    bpl WRITETRACKMFM_20
    sta ISM_wData
WRITETRACKMFM_21:
    bit ISM_rHandshake
    bpl WRITETRACKMFM_21
    lda #$02
    sta ISM_wData
WRITETRACKMFM_22:
    bit ISM_rHandshake
    bpl WRITETRACKMFM_22
    stz ISM_wCRC
    ldx #$16
    lda #$4E
WRITETRACKMFM_23:
    bit ISM_rHandshake
    bpl WRITETRACKMFM_23
    sta ISM_wData
    dex
    bne WRITETRACKMFM_23
    ldx #$0C
WRITETRACKMFM_24:
    bit ISM_rHandshake
    bpl WRITETRACKMFM_24
    stz ISM_wData
    dex
    bne WRITETRACKMFM_24
    ldx #$03
WRITETRACKMFM_25:
    bit ISM_rHandshake
    bpl WRITETRACKMFM_25
    lda #$A1
    sta ISM_wMark
    dex
    bne WRITETRACKMFM_25
WRITETRACKMFM_26:
    bit ISM_rHandshake
    bpl WRITETRACKMFM_26
    lda #$FB
    sta ISM_wData
    ldx #$00
    lda #$00
WRITETRACKMFM_27:
    bit ISM_rHandshake
    bpl WRITETRACKMFM_27
    sta ISM_wData
    dex
    bne WRITETRACKMFM_27
WRITETRACKMFM_28:
    bit ISM_rHandshake
    bpl WRITETRACKMFM_28
    sta ISM_wData
    dex
    bne WRITETRACKMFM_28
WRITETRACKMFM_29:
    bit ISM_rHandshake
    bpl WRITETRACKMFM_29
    stz ISM_wCRC
    dec SECTORCOUNT
    beq WRITETRACKMFM_30
    ldy SECTORCOUNT
    lda INTERLEAVEMAP-1,Y
    inc A
    sta HDRSECTOR
    jmp WRITETRACKMFM_SECTOR
WRITETRACKMFM_30:
    lda #$04
    sta SCRATCH
    ldx #$05
WRITETRACKMFM_31:
    bit ISM_rHandshake
    bpl WRITETRACKMFM_31
    lda #$4E
    sta ISM_wData
    dex
    bne WRITETRACKMFM_31
    ldy #$00
    lda #$F4
    sta ISM_wPhase
    ldx #$4E
WRITETRACKMFM_32:
    lda ISM_rHandshake
    bpl WRITETRACKMFM_32
    stx ISM_wData
    bit #$08
    bne WRITETRACKMFM_33
    dey
    bne WRITETRACKMFM_32
    dec SCRATCH
    bne WRITETRACKMFM_32
    bra WRITETRACKMFM_TIMEOUT
WRITETRACKMFM_33:
    and #$20
    beq WRITETRACKMFM_34
    lda #$34
    sec
    bra WRITETRACKMFM_35
WRITETRACKMFM_34:
    lda #$00
    clc
WRITETRACKMFM_35:
    sta DISKERRORS
    php
    lda #$18
    sta ISM_wZeroes
    jsr LEAVEISM
    plp
    rts
WRITETRACKMFM_TIMEOUT:
    lda #$35
    sec
    bra WRITETRACKMFM_35

;; Unused.
DIVIDE7_PAD:
    .res $F500-*

;; Divides a bus packet's byte count by 7.
;; In:    WORKPTR = the count
;; Out:   GROUPS = the 7-byte groups, ODDBYTES = the rest
DIVIDE7:
    stz GROUPS
    ldx #$08
    lda WORKPTR+1
DIVIDE7_1:
    asl WORKPTR
    rol A
    cmp #$07
    bcc DIVIDE7_2
    sbc #$07
DIVIDE7_2:
    rol GROUPS
    dex
    bne DIVIDE7_1
    sta ODDBYTES
    rts

;; Receives a SmartPort bus packet into BUFPTR.
;; Out:   carry = set with DISKERRORS = $80 (none), $81, $83 or $8A for a bad packet
BUSRECEIVE:
    ldx #$07
BUSRECEIVE_1:
    stz PACKETIN,X
    dex
    bne BUSRECEIVE_1
    stz HEADERSUM
    stz DISKERRORS
    jsr BUSREQUEST
    tsx
BUSRECEIVE_2:
    stz NIBBLES1,X
    dex
    cpx #$E1
    bcs BUSRECEIVE_2
    bit IWM_Q6H
    ldx HEADERSUM
BUSRECEIVE_3:
    lda #$64
BUSRECEIVE_4:
    ldy #$CD
BUSRECEIVE_5:
    bit IWM_Q7L
    bmi BUSRECEIVE_6
    dey
    bne BUSRECEIVE_5
    dec A
    bne BUSRECEIVE_4
    dex
    bne BUSRECEIVE_3
    bra BUSRECEIVE_8
BUSRECEIVE_6:
    lda IWM_PH0H
    ldy #$00
BUSRECEIVE_7:
    lda IWM_Q6L
    dey
BUSRECEIVE_8:
    beq BUSRECEIVE_20
    cmp #$C3
    bne BUSRECEIVE_7
    ldy #$07
BUSRECEIVE_9:
    lda IWM_Q6L
    bpl BUSRECEIVE_9
    and #$7F
    sta PACKETIN,Y
    ora #$80
    eor HEADERSUM
    sta HEADERSUM
    dey
    bne BUSRECEIVE_9
    lda GROUPS
    bmi BUSRECEIVE_19
    sta HIGHGROUP
    ldx ODDBYTES
    beq BUSRECEIVE_14
BUSRECEIVE_10:
    lda IWM_Q6L
    bpl BUSRECEIVE_10
    asl A
    sta HIGHBYTE
BUSRECEIVE_11:
    lda IWM_Q6L
    bpl BUSRECEIVE_11
    asl HIGHBYTE
    bcs BUSRECEIVE_12
    and #$7F
BUSRECEIVE_12:
    sta (BUFPTR),Y
    eor HEADERSUM
    sta HEADERSUM
    iny
    bne BUSRECEIVE_13
    inc BUFPTR+1
BUSRECEIVE_13:
    dex
    bne BUSRECEIVE_11
BUSRECEIVE_14:
    ldx #$07
    dec HIGHGROUP
    bpl BUSRECEIVE_10
BUSRECEIVE_15:
    lda IWM_Q6L
    bpl BUSRECEIVE_15
    sta SCRATCH
BUSRECEIVE_16:
    lda IWM_Q6L
    bpl BUSRECEIVE_16
    sec
    rol A
    and SCRATCH
    eor HEADERSUM
    bne BUSRECEIVE_22
BUSRECEIVE_17:
    lda IWM_Q6L
    bpl BUSRECEIVE_17
    cmp #$C8
    bne BUSRECEIVE_21
    lda IWM_Q6H
BUSRECEIVE_18:
    lda IWM_Q7L
    bmi BUSRECEIVE_18
    lda IWM_PH0L
    clc
    rts
BUSRECEIVE_19:
    lda #$8A
    bra BUSRECEIVE_23
BUSRECEIVE_20:
    lda #$80
    bra BUSRECEIVE_23
BUSRECEIVE_21:
    lda #$81
    bra BUSRECEIVE_23
BUSRECEIVE_22:
    lda #$83
BUSRECEIVE_23:
    sta DISKERRORS
    sec
    rts

;; Sends a SmartPort bus packet from BUFPTR (BUSCOUNT bytes).
;; Out:   carry = set with DISKERRORS = $84 or $82 if the device did not answer
BUSSEND:
    bit IWM_Q7L
    bit IWM_Q6L
    jsr PACKHIGHBITS
    jsr BUSREQUEST
    lda IWM_DRIVE1
    lda IWM_MTRON
    bit IWM_Q6H
    ldy #$FA
BUSSEND_1:
    lda IWM_Q7L
    bmi BUSSEND_2
    dey
    bne BUSSEND_1
    lda #$84
    jmp BUSSEND_DONE
BUSSEND_2:
    lda IWM_PH0H
    ldy #$05
    lda #$FF
    sta IWM_Q7H
BUSSEND_3:
    lda BUSSYNC,Y
BUSSEND_4:
    bit IWM_Q6L
    bpl BUSSEND_4
    sta IWM_Q6H
    dey
    bpl BUSSEND_3
    lda #$00
    sta HEADERSUM
    lda DRIVE
    ora #$80
    jsr SENDCHECKED
    jsr SENDZERO
    lda PACKETTYPE
    jsr SENDCHECKED
    jsr SENDZERO
    jsr SENDZERO
    lda ODDBYTES
    ora #$80
    jsr SENDCHECKED
    lda GROUPS
    ora #$80
    jsr SENDCHECKED
    ldy #$00
    ldx ODDBYTES
    beq BUSSEND_6
    lda HIGHBYTE
    jsr SENDBYTE
BUSSEND_5:
    lda (BUFPTR),Y
    jsr SENDCHECKED
    iny
    dex
    bne BUSSEND_5
BUSSEND_6:
    dec GROUPS
    bmi BUSSEND_9
    lda HIGHGROUP
    jsr SENDBYTE
    lda #$01
    sta HIGHGROUP
    ldx #$07
BUSSEND_7:
    lda (BUFPTR),Y
    jsr SENDCHECKED
    lda (WORKPTR),Y
    asl A
    rol HIGHGROUP
    iny
    bne BUSSEND_8
    inc BUFPTR+1
    inc WORKPTR+1
BUSSEND_8:
    dex
    bne BUSSEND_7
    beq BUSSEND_6
BUSSEND_9:
    lda HEADERSUM
    ora #$AA
    jsr SENDBYTE
    lda HEADERSUM
    lsr A
    ora #$AA
    jsr SENDBYTE
    lda #$C8
    jsr SENDBYTE
BUSSEND_10:
    bit IWM_Q6L
    bvs BUSSEND_10
    sta IWM_Q6H
    ldy #$FA
BUSSEND_11:
    dey
    bne BUSSEND_12
    lda #$82
BUSSEND_DONE:
    sec
    bra BUSSEND_13
BUSSEND_12:
    lda IWM_Q7L
    bmi BUSSEND_11
    lda #$00
    clc
BUSSEND_13:
    bit IWM_PH0L
    bit IWM_Q6L
    sta DISKERRORS
    rts

;; Turns GROUPS and ODDBYTES back into a byte count.
;; Out:   A = the low byte, Y = the high
GROUPCOUNT:
    stz SCRATCH
    lda GROUPS
    asl A
    rol SCRATCH
    asl A
    rol SCRATCH
    asl A
    rol SCRATCH
    sec
    sbc GROUPS
    bcs GROUPCOUNT_1
    dec SCRATCH
GROUPCOUNT_1:
    clc
    adc ODDBYTES
    bcc GROUPCOUNT_2
    inc SCRATCH
GROUPCOUNT_2:
    ldy SCRATCH
    rts

;; Sends a $80 (a zero with the high bit) and adds it to the checksum.
SENDZERO:
    lda #$80

;; Sends a byte with its high bit set and adds it to the packet's checksum.
;; In:    A = the byte
SENDCHECKED:
    pha
    eor HEADERSUM
    sta HEADERSUM
    pla
    ora #$80

;; Sends a byte to the bus once the IWM can take it.
;; In:    A = the byte
SENDBYTE:
    bit IWM_Q6L
    bpl SENDBYTE
    sta IWM_Q6H
    rts

;; Collects the high bits of a packet's odd bytes and its first group for BUSSEND.
PACKHIGHBITS:
    lda BUSCOUNT
    sta WORKPTR
    lda BUSCOUNT+1
    sta WORKPTR+1
    jsr DIVIDE7
    lda BUFPTR
    clc
    adc #$07
    sta WORKPTR
    lda BUFPTR+1
    adc #$00
    sta WORKPTR+1
    ldy #$00
    jsr HIGHBITS7
    lda HIGHGROUP
    sta HIGHBYTE
    ldy ODDBYTES
    jsr HIGHBITS7
    rts

;; Collects the high bits of seven bytes into HIGHBYTE's low bits, with bit 7 set.
;; In:    Y = the first
HIGHBITS7:
    ldx #$07
    lda #$01
    sta HIGHGROUP
HIGHBITS7_1:
    lda (BUFPTR),Y
    asl A
    rol HIGHGROUP
    iny
    dex
    bne HIGHBITS7_1
    rts

;; Raises the bus's REQ line (phases 1 and 3).
BUSREQUEST:
    jsr BUSIDLE
    lda IWM_PH1H
    lda IWM_PH3H
    rts

;; Resets the SmartPort bus: phases 0 and 2 for 80 ms, then 10 ms idle.
BUSRESET:
    jsr BUSIDLE
    lda IWM_PH0H
    lda IWM_PH2H
    lda #$50
    jsr DELAYMS
    jsr BUSIDLE
    lda #$05

;; Waits 2 x A milliseconds.
;; Keeps: A
DELAY2:
    pha
    jsr DELAYMS
    pla

;; Waits A milliseconds.
;; Out:   A = 0
DELAYMS:
    jsr DELAY1MS
    dec A
    bne DELAYMS
    rts

;; Waits about a millisecond (2030 cycles).
;; Keeps: A, X, Y
DELAY1MS:
    pha
    lda #$CB
DELAY1MS_1:
    dec A
    bne DELAY1MS_2
DELAY1MS_2:
    nop
    bne DELAY1MS_1
    pla
    rts

;; Lowers all four phase lines.
BUSIDLE:
    bit IWM_PH0L
    bit IWM_PH1L
    bit IWM_PH2L
    bit IWM_PH3L
    rts

;; A bus packet's sync bytes and PBEGIN ($C3), sent last first.
BUSSYNC:
    .byte $C3, $FF, $FC, $F3, $CF, $3F

;; Builds the bus command packet from the host's command and parameters.
MAKEPACKET:
    lda #$80
    sta PACKETTYPE
    lda CARDCOMMAND
    and #$0F
    sta PACKET
    ldy CARDSTATE
    lda BUSCOMMANDS,Y
    and #$0F
    sta PACKET+1
    stz PACKET+2
    stz PACKET+3
    ldx #$06
MAKEPACKET_1:
    lda CARDPROGRESS,X
    sta PACKET+3,X
    dex
    bne MAKEPACKET_1

;; Points BUFPTR at the 9-byte command packet.
COMMANDPOINTER:
    lda #$09
    sta BUSCOUNT
    stz BUSCOUNT+1
    lda #$4C
    sta BUFPTR
    stz BUFPTR+1
    rts

;; Sends a data packet, re-initialising the bus if the device does not take it.
SENDDATA:
    jsr SENDTRIES32
    bcs BUSREINIT
    rts

;; Re-initialises the bus devices and keeps DRIVE.
;; Out:   carry = set
BUSREINIT:
    lda DRIVE
    pha
    ldx FIRSTBUSUNIT
    lda #$80
    jsr BUSINIT
    pla
    sta DRIVE
    sec
    rts

;; Sends the command packet, re-initialising the bus between tries.
SENDCOMMAND35:
    lda #$01
    jsr SENDTRIES
    bcc SENDCOMMAND35_1
    jsr BUSREINIT
    jsr MAKEPACKET
    lda #$64
    jsr SENDTRIES
    bcc SENDCOMMAND35_1
    jsr BUSREINIT
    jsr MAKEPACKET
    lda #$64
    jsr SENDTRIES
SENDCOMMAND35_1:
    rts

;; BUSSEND with up to 32 tries (fewer for long packets).
SENDTRIES32:
    lda #$20

;; BUSSEND with up to A tries, halved for each 256 bytes of the packet.
SENDTRIES:
    ldx BUSCOUNT+1
    beq SENDTRIES_2
SENDTRIES_1:
    lsr A
    dex
    bne SENDTRIES_1
SENDTRIES_2:
    sta RETRIES
SENDTRIES_3:
    jsr BUSSEND
    bcc SENDTRIES_4
    dec RETRIES
    beq SENDTRIES_4
    ldx BUSCOUNT+1
    bne SENDTRIES_3
    lda #$05
    jsr DELAYMS
    bra SENDTRIES_3
SENDTRIES_4:
    rts

;; BUSRECEIVE with up to 5 tries, 60 for FORMAT.
RECEIVETRIES:
    lda #$05
    sta RETRIES
    lda CARDSTATE
    cmp #$03
    bne RECEIVETRIES_1
    lda #$3C
    sta RETRIES
RECEIVETRIES_1:
    jsr BUSRECEIVE
    bcc RECEIVETRIES_2
    jsr DELAY1MS
    sec
    bit IWM_PH0L
    bit IWM_Q6L
    dec RETRIES
    bne RECEIVETRIES_1
RECEIVETRIES_2:
    rts

;; Widens a bus device's status to the extended form: a 4-byte block count.
EXTENDSTATUS:
    ldy #$19
EXTENDSTATUS_1:
    lda XFERBUFFER-1,Y
    sta XFERBUFFER,Y
    dey
    cpy #$04
    bne EXTENDSTATUS_1
    stz XFERBUFFER+4
    inc COUNTLO
    rts

;; Passes a command for a SmartPort bus device (a UniDisk 3.5) to it: the command packet, the host's
;; data if any, and the device's reply.
;; Out:   ERRORCODE = the device's result, $27 or $06; CARDDATA = 6 with data
BUSCALL:
    lda #$17
    jsr SETIWMMODE
    stz BUSRESULT
    jsr MAKEPACKET
    jsr BUSIDLE
    jsr SENDCOMMAND35
    bcs BUSCALL_4
    ldx CARDSTATE
    bit BUSCOMMANDS,X
    bpl BUSCALL_5
    cpx #$02
    beq BUSCALL_1
    lda COUNTHI
    cmp #$05
    bcc BUSCALL_1
    bit BUSCOMMANDS
    ldy #$00
    lda #$22
    bra BUSCALL_9
BUSCALL_1:
    lda #$06
    sta CARDDATA
BUSCALL_2:
    lda CARDDATA
    bpl BUSCALL_2
    ldx COUNTLO
    ldy COUNTHI
    lda CARDSTATE
    cmp #$02
    bne BUSCALL_3
    ldy #$02
    ldx #$00
BUSCALL_3:
    sty BUSCOUNT+1
    stx BUSCOUNT
    lda #$82
    sta PACKETTYPE
    jsr BUSIDLE
    stz BUFPTR
    lda #$0C
    sta BUFPTR+1
    jsr SENDDATA
BUSCALL_4:
    bcs BUSCALL_12
BUSCALL_5:
    stz BUFPTR
    lda #$0C
    sta BUFPTR+1
    jsr RECEIVETRIES
    bcs BUSCALL_11
    jsr GROUPCOUNT
    sta COUNTLO
    sty COUNTHI
BUSCALL_6:
    ldy #$00
    ldx CARDSTATE
    bne BUSCALL_7
    bit CARDCOMMAND
    bvc BUSCALL_7
    jsr EXTENDSTATUS
BUSCALL_7:
    cpx #$0A
    clv
    bcs BUSCALL_9
    bit BUSCOMMANDS,X
    bvc BUSCALL_8
    ldy #$06
BUSCALL_8:
    lda BUSRESULT
BUSCALL_9:
    sta ERRORCODE
    bvc BUSCALL_10
    sty CARDDATA
BUSCALL_10:
    jsr BUSIDLE
    clc
    rts
BUSCALL_11:
    cmp #$80
    beq BUSCALL_12
    lda #$27
    bra BUSCALL_13
BUSCALL_12:
    lda #$06
BUSCALL_13:
    sta BUSRESULT
    bra BUSCALL_6

;; Each bus command's packet: bit 7 data to the device, bit 6 data back, bits 0-3 the parameters.
BUSCOMMANDS:
    .byte $43, $43, $83, $01, $83, $01, $01, $01, $44, $84

;; Resets the SmartPort bus and assigns unit numbers to its devices with INIT commands.
;; In:    A = $00 (cold) or $80, X = the first unit for the bus
;; Out:   A = the devices found (DEVICEKIND = $80 for each)
BUSINIT:
    sta PACKET+4
    phx
    lda #$00
BUSINIT_1:
    sta UNITCOUNT,X
    inx
    cpx #$04
    bcc BUSINIT_1
    bit IWM_MTROFF
    lda #$FF
    sta DRIVE
    jsr PORTOFF
    jsr MFMOFF
    lda #$17
    jsr SETIWMMODE
    plx
    stx DRIVE
    jsr BUSRESET
    jsr BUSIDLE
    stz SAVEDRIVE
BUSINIT_2:
    lda #$80
    sta PACKETTYPE
    lda #$05
    sta PACKET
    lda #$02
    sta PACKET+1
    stz PACKET+3
    stz PACKET+5
    jsr COMMANDPOINTER
    jsr BUSSEND
    bcs BUSINIT_4
    stz BUFPTR
    lda #$0C
    sta BUFPTR+1
    jsr BUSRECEIVE
    bcs BUSINIT_4
    ldy DRIVE
    cpy #$05
    bcs BUSINIT_3
    lda #$80
    sta UNITCOUNT,Y
    lda #$00
    sta SPANCYLINDER,Y
BUSINIT_3:
    inc SAVEDRIVE
    inc DRIVE
    lda BUSRESULT
    beq BUSINIT_2
    lda SAVEDRIVE
    cmp #$03
    bcc BUSINIT_4
    lda #$02
    sta SAVEDRIVE
BUSINIT_4:
    jsr BUSIDLE
    bit IWM_MTROFF
    lda SAVEDRIVE
    rts

;; The IRQ and BRK handler: blinks the LED forever.
FATAL:
    ldx #$FF
FATAL_1:
    inx
    bit LEDON,X
    ldy #$00
FATAL_2:
    lda #$00
FATAL_3:
    dec A
    bne FATAL_4
FATAL_4:
    bne FATAL_3
    dey
    bne FATAL_2
    txa
    beq FATAL_1
    bra FATAL

;; Unused.
ROMFREE:
    .res $FFDA-*

;; The self-test's checksums of the ROM's parts.
CHECKSUMS:
    .word $C850, $B8A7, $67EC, $4686, $0000, $0000, $0000, $0000, $0000, $0000, $89CA, $C2F6, $7319, $B19A, $9E81

;; The word that makes the ROM's checksum come out right.
ROMCHECKSUM:
    .word $7378

;; The 65C02's vectors.
CPUVECTORS:
    .word CARDRESET                 ; NMI
    .word CARDRESET                 ; reset
    .word FATAL                     ; IRQ and BRK

