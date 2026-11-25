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
;; there), and the bus devices follow, up to unit 4. DeviceKinds holds each unit's device, UnitCount their number.
;;
;; THE MAILBOX
;;
;; The host writes its command at CardState ($00) once bit 7 there says the card waits, after setting CardData
;; to $FF and copying its command, unit and parameters to $02-$0A. RunCommand runs it. Data moves through 512-byte
;; buffers in the card's RAM, named by a code: the card address divided by $200, which is the host's bank (code / 2)
;; and half (code & 1) of its $C800-$CBFF window. A handler that has data for the host, or wants data from it,
;; puts the buffer's code in CardData and waits for the host to OR in $F0; a handler that is done puts 0 there with
;; the error in ErrorCode ($56). MAINLOOP then sets CardState to $FF again.
;;
;;   Code 6 ($0C00-$0DFF)        status lists, control lists, a block being written, READ/WRITE's 524 bytes
;;   Codes $08-$19 ($1000-$33FF) the sector cache: a track's 18 slots, one per sector
;;
;; THE COMMANDS AT CardState
;;
;;   $00-$0B  SmartPort's command less its extended bit ($40); a ProDOS call arrives as SmartPort's 0-3 with
;;            CardCommand bit 7 set
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
NIBBLES1 = $0100                    ;; a GCR sector's nibbles for WriteGcrDataField: the first of three 175-byte lanes
TAGBYTES = $01B2                    ;; a sector's 12 tag bytes, as ReadGcrDataField reads them
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
InitializeCard:
    jsr PORTOFF
    jsr DELAY1MS
    bit Iwm::MotorOff
    stz CardData

;; The 65C02's reset (and NMI) entry: clears the state byte, so the host waits, and runs the power-on
;; test at $9649, which comes back to STARTUP.
;; In:    EjectDrive = a drive whose eject a reset cut short, or bit 7 set
CARDRESET:
    cld
    sei
    ldx #$FF
    txs
    stz CardState
    lda EjectDrive
    jmp POWERONTEST

;; Starts the card after the power-on test: copies the host's code into the shared RAM, then either
;; starts cold (finds the drives and the bus devices) or, if page zero still holds the signature, warm (keeps them).
;; Ends in MAINLOOP.
;; In:    EjectDrive = a drive whose eject a reset cut short, or bit 7 set
STARTUP:
    lda EjectDrive
    jsr COPYHOSTCODE
    ldx #$04
STARTUP_1:
    dex
    bmi WARMSTART
    lda ZeroPageImage+WarmSignature,X
    cmp WarmSignature,X
    beq STARTUP_1
    jsr COLDINIT
    bra STARTUP_5
WARMSTART:
    jsr CLEARCACHE
    ldx #$FF
    stx Drive
    jsr INITSWIM
    jsr MFMOFF
    ldx FirstBusUnit
    beq STARTUP_2
    lda #$80
    jsr BUSINIT
    lda #$1F
    jsr SETIWMMODE
STARTUP_2:
    lda FirstBusUnit
    cmp #$01
    beq STARTUP_5
    ldx UnitCount
STARTUP_3:
    dex
    bmi STARTUP_4
    bit DeviceKinds,X
    bmi STARTUP_3
    stx SavedDrive
    stx Drive
    jsr PORTON
    ldx SavedDrive
    jsr CHECKDISK
    phx
    clc
    jsr IDENTIFYMEDIA
    jsr MFMOFF
    ldx SavedDrive
    jsr RELEASEDRIVE
    plx
    bra STARTUP_3
STARTUP_4:
    jsr PORTON
STARTUP_5:
    bit EjectDrive
    bmi MAINLOOP
    ldx #$FF
    stx Drive
    jsr PORTON
    ldx EjectDrive
    lda Iwm::SelectDrive1,X
    bit Iwm::MotorOn
    jsr EJECT

;; Waits for the host's commands and runs them, forever. The card is ready while CardState ($00) has bit 7
;; set; the host writes the command there. About every three passes of a 65536-count wait without a command it
;; polls the drives for a disk's removal (POLLDRIVES). Each command is logged at LastCommand ($E0-$E4).
MAINLOOP:
    lda #$FF
    sta CardData
    sta CardState
    ldx #$03
MAINLOOP_1:
    dec WorkPointer
    bne MAINLOOP_2
    dec WorkPointer+1
    bne MAINLOOP_2
    dex
    bne MAINLOOP_2
    jsr POLLDRIVES
    ldx #$03
MAINLOOP_2:
    lda CardState
    bmi MAINLOOP_1
    sta LastCommand
    lda CardCommand
    sta LastCommand+1
    lda CardUnit
    sta LastCommand+2
    lda ParameterLow
    sta LastCommand+3
    lda ParameterMiddle
    sta LastCommand+4
MAINLOOP_3:
    jsr CommandVector
    bcs MAINLOOP_4
    lda #$FF
    sta CardState
MAINLOOP_4:
    stz WorkPointer+1
    stz SavedDrive
    jsr MFMOFF
    lda CardState
    bpl MAINLOOP_3
    bit Iwm::MotorOff
    ldx #$03
    bra MAINLOOP_1

;; Runs the command in CardState: the CommandVector vector's routine.
;; Commands $00-$0E go to the handler for the unit; $3D jumps to the diagnostics, $7E/$7F name the host
;; (not a IIgs, a IIgs) in HOSTTYPE; others answer $01.
;; Out:   carry = clear when the card is ready for another command, set when the handler left it waiting
;;        ErrorCode ($56) = the error, CardData = 0 when the result is final
RunCommand:
    stz ErrorCode
    stz Retries
    stz TagCall
    stz SwimState
    lda #$FF
    sta Sector
    sta Cylinder
    sta Track
    lda CardState
    cmp #$0F
    bcc DOCOMMAND_3
    cmp #$7E
    bcc DOCOMMAND_2
    eor #$7E
    beq DOCOMMAND_1
    lda #$40
DOCOMMAND_1:
    sta SharedExpansion+HOSTTYPEOFFSET
    clc
    rts
DOCOMMAND_2:
    cmp #$3D
    bne DOCOMMAND_7
    jmp DIAGNOSTICSENTRY
DOCOMMAND_3:
    stz UnitWithHighBit
DOCOMMAND_4:
    lda UnitCount
    cmp CardUnit
    bcs DOCOMMAND_6
    lda CardState
    ora ParameterLow
    bne DOCOMMAND_5
    bit CardCommand
    bvc DOCOMMAND_5
    lda CardUnit
    bpl DOCOMMAND_5
    sta UnitWithHighBit
    and #$7F
    sta CardUnit
    bne DOCOMMAND_4
DOCOMMAND_5:
    lda #$11
    bra SETERROR
DOCOMMAND_6:
    ldx CardUnit
    dex
    stx Drive
    bmi CALLHANDLER
    lda DeviceKinds,X
    bpl CALLHANDLER
    lda CardState
    cmp #$0D
    bcc PASSTOBUS
DOCOMMAND_7:
    bra ERRBADCOMMAND
CALLHANDLER:
    lda #$1F
    jsr SETIWMMODE
    jsr PORTON
    lda CardState
    asl A
    tax
    jmp (HANDLERS,X)
PASSTOBUS:
    ldx #$FF
    stx Drive
    jsr PORTOFF
    jsr MFMOFF
    ldx CardUnit
    stx Drive
    jsr BUSCALL
    lda FirstBusUnit
    cmp #$01
    beq DOCOMMAND_8
    lda #$FF
    sta Drive
    jsr PORTON
DOCOMMAND_8:
    clc
    rts

;; Each command's handler, by the command at CardState ($00-$0E).
HANDLERS:
    .word DOSTATUS, DOREADBLOCK, DOWRITEBLOCK, DOFORMAT ; $00-$03: STATUS, READBLOCK, WRITEBLOCK, FORMAT
    .word DOCONTROL, InitializeCard, ERRBADCOMMAND, ERRBADCOMMAND ; $04-$07: CONTROL, INIT, OPEN, CLOSE
    .word READWRITE, READWRITE, SETFORMAT, FORMATOPTIONS ; $08-$0B: READ, WRITE, SETFORMAT, FORMATOPTIONS
    .word BOOTREAD, READAHEAD, READSPAN ; $0C-$0E: the boot read, READAHEAD, READSPAN
ERRBADCOMMAND:
    lda #$01

;; Ends a command with an error code and no data.
;; In:    A = the error
;; Out:   carry = clear, ErrorCode = A, CardData = 0
SETERROR:
    clc
    sta ErrorCode
    stz CardData
    rts

;; Ends a command with $22, a bad parameter (a wrong byte count).
;; Out:   carry = clear
ERRBADPARAMETER:
    lda #$22
    bra SETERROR

;; Starts the card cold: page zero from the ROM, the SWIM set up, the bus reset, the drives found and
;; the SmartPort bus devices numbered after them, then the signature and an empty cache.
;; Out:   UnitCount = the units, FirstBusUnit = the first bus unit, DeviceKinds = each unit's kind
COLDINIT:
    jsr COPYZEROPAGE
    lda #$D2
    sta FormatHook+1
    lda #$75
    sta FormatHook
    lda #$FF
    sta Drive
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
    stz FirstBusUnit
    ldx UnitCount
    inx
    lda #$00
    jsr BUSINIT
    beq COLDINIT_1
    ldx UnitCount
    inx
    stx FirstBusUnit
    clc
    adc UnitCount
    sta UnitCount
COLDINIT_1:
    stz Drive
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
    sta CardState,X
    dex
    bne COPYZEROPAGE_1
    rts

;; Copies the warm-start signature, $80BC-$80BF, to WarmSignature ($BC-$BF).
COPYSIGNATURE:
    ldx #$BF
COPYSIGNATURE_1:
    lda ZeroPageImage,X
    sta CardState,X
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
    sta SharedSlotPage,Y
    iny
    bne COPYHOSTCODE_1
COPYHOSTCODE_2:
    lda SlotPageImage+$100,Y
    sta HOSTCODE,Y
    lda SlotPageImage+$200,Y
    sta HOSTCODE+$100,Y
    lda SlotPageImage+$300,Y
    sta SharedExpansion,Y
    lda SlotPageImage+$400,Y
    sta SharedExpansion+$100,Y
    lda SlotPageImage+$500,Y
    sta SharedExpansion+$200,Y
    lda SlotPageImage+$600,Y
    sta SharedExpansion+$300,Y
    iny
    bne COPYHOSTCODE_2
    lda #$16
    sta SharedSlotPage+BOOTWAITOFFSET
    stz SharedSlotPage+CALLWAITOFFSET
    lda #$60
    sta CARDHOOK1
    sta CARDHOOK2
    sta CARDHOOK3
    sta CARDHOOK4
    rts

.include "Disk35Drives.asm"
.include "Disk35Cache.asm"
.include "Disk35Blocks.asm"
.include "Disk35Gcr.asm"
.include "Disk35Mfm.asm"
.include "Disk35Control.asm"
.include "Disk35Format.asm"
.include "Disk35Bus.asm"

;; The IRQ and BRK handler: blinks the LED forever.
FATAL:
    ldx #$FF
FATAL_1:
    inx
    bit LedOn,X
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

