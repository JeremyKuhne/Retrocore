;; THE CARD'S FIRMWARE: THE SMARTPORT BUS

;; Receives a SmartPort bus packet into BufferPointer.
;; Out:   carry = set with DiskErrors = $80 (none), $81, $83 or $8A for a bad packet
BUSRECEIVE:
    ldx #$07
BUSRECEIVE_1:
    stz PacketHeader,X
    dex
    bne BUSRECEIVE_1
    stz HeaderChecksum
    stz DiskErrors
    jsr BUSREQUEST
    tsx
BUSRECEIVE_2:
    stz NIBBLES1,X
    dex
    cpx #$E1
    bcs BUSRECEIVE_2
    bit Iwm::LoadLatch
    ldx HeaderChecksum
BUSRECEIVE_3:
    lda #$64
BUSRECEIVE_4:
    ldy #$CD
BUSRECEIVE_5:
    bit Iwm::ReadMode
    bmi BUSRECEIVE_6
    dey
    bne BUSRECEIVE_5
    dec A
    bne BUSRECEIVE_4
    dex
    bne BUSRECEIVE_3
    bra BUSRECEIVE_8
BUSRECEIVE_6:
    lda Iwm::Phase0On
    ldy #$00
BUSRECEIVE_7:
    lda Iwm::DataLatch
    dey
BUSRECEIVE_8:
    beq BUSRECEIVE_20
    cmp #$C3
    bne BUSRECEIVE_7
    ldy #$07
BUSRECEIVE_9:
    lda Iwm::DataLatch
    bpl BUSRECEIVE_9
    and #$7F
    sta PacketHeader,Y
    ora #$80
    eor HeaderChecksum
    sta HeaderChecksum
    dey
    bne BUSRECEIVE_9
    lda Groups
    bmi BUSRECEIVE_19
    sta GroupHighBits
    ldx OddBytes
    beq BUSRECEIVE_14
BUSRECEIVE_10:
    lda Iwm::DataLatch
    bpl BUSRECEIVE_10
    asl A
    sta PacketHighBits
BUSRECEIVE_11:
    lda Iwm::DataLatch
    bpl BUSRECEIVE_11
    asl PacketHighBits
    bcs BUSRECEIVE_12
    and #$7F
BUSRECEIVE_12:
    sta (BufferPointer),Y
    eor HeaderChecksum
    sta HeaderChecksum
    iny
    bne BUSRECEIVE_13
    inc BufferPointer+1
BUSRECEIVE_13:
    dex
    bne BUSRECEIVE_11
BUSRECEIVE_14:
    ldx #$07
    dec GroupHighBits
    bpl BUSRECEIVE_10
BUSRECEIVE_15:
    lda Iwm::DataLatch
    bpl BUSRECEIVE_15
    sta Scratch
BUSRECEIVE_16:
    lda Iwm::DataLatch
    bpl BUSRECEIVE_16
    sec
    rol A
    and Scratch
    eor HeaderChecksum
    bne BUSRECEIVE_22
BUSRECEIVE_17:
    lda Iwm::DataLatch
    bpl BUSRECEIVE_17
    cmp #$C8
    bne BUSRECEIVE_21
    lda Iwm::LoadLatch
BUSRECEIVE_18:
    lda Iwm::ReadMode
    bmi BUSRECEIVE_18
    lda Iwm::Phase0Off
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
    sta DiskErrors
    sec
    rts

;; Sends a SmartPort bus packet from BufferPointer (BusCount bytes).
;; Out:   carry = set with DiskErrors = $84 or $82 if the device did not answer
BUSSEND:
    bit Iwm::ReadMode
    bit Iwm::DataLatch
    jsr PACKHIGHBITS
    jsr BUSREQUEST
    lda Iwm::SelectDrive1
    lda Iwm::MotorOn
    bit Iwm::LoadLatch
    ldy #$FA
BUSSEND_1:
    lda Iwm::ReadMode
    bmi BUSSEND_2
    dey
    bne BUSSEND_1
    lda #$84
    jmp BUSSEND_DONE
BUSSEND_2:
    lda Iwm::Phase0On
    ldy #$05
    lda #$FF
    sta Iwm::WriteMode
BUSSEND_3:
    lda BUSSYNC,Y
BUSSEND_4:
    bit Iwm::DataLatch
    bpl BUSSEND_4
    sta Iwm::LoadLatch
    dey
    bpl BUSSEND_3
    lda #$00
    sta HeaderChecksum
    lda Drive
    ora #$80
    jsr SENDCHECKED
    jsr SENDZERO
    lda PacketType
    jsr SENDCHECKED
    jsr SENDZERO
    jsr SENDZERO
    lda OddBytes
    ora #$80
    jsr SENDCHECKED
    lda Groups
    ora #$80
    jsr SENDCHECKED
    ldy #$00
    ldx OddBytes
    beq BUSSEND_6
    lda PacketHighBits
    jsr SENDBYTE
BUSSEND_5:
    lda (BufferPointer),Y
    jsr SENDCHECKED
    iny
    dex
    bne BUSSEND_5
BUSSEND_6:
    dec Groups
    bmi BUSSEND_9
    lda GroupHighBits
    jsr SENDBYTE
    lda #$01
    sta GroupHighBits
    ldx #$07
BUSSEND_7:
    lda (BufferPointer),Y
    jsr SENDCHECKED
    lda (WorkPointer),Y
    asl A
    rol GroupHighBits
    iny
    bne BUSSEND_8
    inc BufferPointer+1
    inc WorkPointer+1
BUSSEND_8:
    dex
    bne BUSSEND_7
    beq BUSSEND_6
BUSSEND_9:
    lda HeaderChecksum
    ora #$AA
    jsr SENDBYTE
    lda HeaderChecksum
    lsr A
    ora #$AA
    jsr SENDBYTE
    lda #$C8
    jsr SENDBYTE
BUSSEND_10:
    bit Iwm::DataLatch
    bvs BUSSEND_10
    sta Iwm::LoadLatch
    ldy #$FA
BUSSEND_11:
    dey
    bne BUSSEND_12
    lda #$82
BUSSEND_DONE:
    sec
    bra BUSSEND_13
BUSSEND_12:
    lda Iwm::ReadMode
    bmi BUSSEND_11
    lda #$00
    clc
BUSSEND_13:
    bit Iwm::Phase0Off
    bit Iwm::DataLatch
    sta DiskErrors
    rts

;; Turns Groups and OddBytes back into a byte count.
;; Out:   A = the low byte, Y = the high
GROUPCOUNT:
    stz Scratch
    lda Groups
    asl A
    rol Scratch
    asl A
    rol Scratch
    asl A
    rol Scratch
    sec
    sbc Groups
    bcs GROUPCOUNT_1
    dec Scratch
GROUPCOUNT_1:
    clc
    adc OddBytes
    bcc GROUPCOUNT_2
    inc Scratch
GROUPCOUNT_2:
    ldy Scratch
    rts

;; Sends a $80 (a zero with the high bit) and adds it to the checksum.
SENDZERO:
    lda #$80

;; Sends a byte with its high bit set and adds it to the packet's checksum.
;; In:    A = the byte
SENDCHECKED:
    pha
    eor HeaderChecksum
    sta HeaderChecksum
    pla
    ora #$80

;; Sends a byte to the bus once the IWM can take it.
;; In:    A = the byte
SENDBYTE:
    bit Iwm::DataLatch
    bpl SENDBYTE
    sta Iwm::LoadLatch
    rts

;; Collects the high bits of a packet's odd bytes and its first group for BUSSEND.
PACKHIGHBITS:
    lda BusCount
    sta WorkPointer
    lda BusCount+1
    sta WorkPointer+1
    jsr DIVIDE7
    lda BufferPointer
    clc
    adc #$07
    sta WorkPointer
    lda BufferPointer+1
    adc #$00
    sta WorkPointer+1
    ldy #$00
    jsr HIGHBITS7
    lda GroupHighBits
    sta PacketHighBits
    ldy OddBytes
    jsr HIGHBITS7
    rts

;; Collects the high bits of seven bytes into PacketHighBits's low bits, with bit 7 set.
;; In:    Y = the first
HIGHBITS7:
    ldx #$07
    lda #$01
    sta GroupHighBits
HIGHBITS7_1:
    lda (BufferPointer),Y
    asl A
    rol GroupHighBits
    iny
    dex
    bne HIGHBITS7_1
    rts

;; Raises the bus's REQ line (phases 1 and 3).
BUSREQUEST:
    jsr BUSIDLE
    lda Iwm::Phase1On
    lda Iwm::Phase3On
    rts

;; Resets the SmartPort bus: phases 0 and 2 for 80 ms, then 10 ms idle.
BUSRESET:
    jsr BUSIDLE
    lda Iwm::Phase0On
    lda Iwm::Phase2On
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
    bit Iwm::Phase0Off
    bit Iwm::Phase1Off
    bit Iwm::Phase2Off
    bit Iwm::Phase3Off
    rts

;; A bus packet's sync bytes and PBEGIN ($C3), sent last first.
BUSSYNC:
    .byte $C3, $FF, $FC, $F3, $CF, $3F

;; Builds the bus command packet from the host's command and parameters.
MAKEPACKET:
    lda #$80
    sta PacketType
    lda CardCommand
    and #$0F
    sta CommandPacket
    ldy CardState
    lda BUSCOMMANDS,Y
    and #$0F
    sta CommandPacket+1
    stz CommandPacket+2
    stz CommandPacket+3
    ldx #$06
MAKEPACKET_1:
    lda WriteProgress,X
    sta CommandPacket+3,X
    dex
    bne MAKEPACKET_1

;; Points BufferPointer at the 9-byte command packet.
COMMANDPOINTER:
    lda #$09
    sta BusCount
    stz BusCount+1
    lda #$4C
    sta BufferPointer
    stz BufferPointer+1
    rts

;; Sends a data packet, re-initialising the bus if the device does not take it.
SENDDATA:
    jsr SENDTRIES32
    bcs BUSREINIT
    rts

;; Re-initialises the bus devices and keeps Drive.
;; Out:   carry = set
BUSREINIT:
    lda Drive
    pha
    ldx FirstBusUnit
    lda #$80
    jsr BUSINIT
    pla
    sta Drive
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
    ldx BusCount+1
    beq SENDTRIES_2
SENDTRIES_1:
    lsr A
    dex
    bne SENDTRIES_1
SENDTRIES_2:
    sta Retries
SENDTRIES_3:
    jsr BUSSEND
    bcc SENDTRIES_4
    dec Retries
    beq SENDTRIES_4
    ldx BusCount+1
    bne SENDTRIES_3
    lda #$05
    jsr DELAYMS
    bra SENDTRIES_3
SENDTRIES_4:
    rts

;; BUSRECEIVE with up to 5 tries, 60 for FORMAT.
RECEIVETRIES:
    lda #$05
    sta Retries
    lda CardState
    cmp #$03
    bne RECEIVETRIES_1
    lda #$3C
    sta Retries
RECEIVETRIES_1:
    jsr BUSRECEIVE
    bcc RECEIVETRIES_2
    jsr DELAY1MS
    sec
    bit Iwm::Phase0Off
    bit Iwm::DataLatch
    dec Retries
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
    inc Count
    rts

;; Passes a command for a SmartPort bus device (a UniDisk 3.5) to it: the command packet, the host's
;; data if any, and the device's reply.
;; Out:   ErrorCode = the device's result, $27 or $06; CardData = 6 with data
BUSCALL:
    lda #$17
    jsr SETIWMMODE
    stz BusResult
    jsr MAKEPACKET
    jsr BUSIDLE
    jsr SENDCOMMAND35
    bcs BUSCALL_4
    ldx CardState
    bit BUSCOMMANDS,X
    bpl BUSCALL_5
    cpx #$02
    beq BUSCALL_1
    lda CountHigh
    cmp #$05
    bcc BUSCALL_1
    bit BUSCOMMANDS
    ldy #$00
    lda #$22
    bra BUSCALL_9
BUSCALL_1:
    lda #$06
    sta CardData
BUSCALL_2:
    lda CardData
    bpl BUSCALL_2
    ldx Count
    ldy CountHigh
    lda CardState
    cmp #$02
    bne BUSCALL_3
    ldy #$02
    ldx #$00
BUSCALL_3:
    sty BusCount+1
    stx BusCount
    lda #$82
    sta PacketType
    jsr BUSIDLE
    stz BufferPointer
    lda #$0C
    sta BufferPointer+1
    jsr SENDDATA
BUSCALL_4:
    bcs BUSCALL_12
BUSCALL_5:
    stz BufferPointer
    lda #$0C
    sta BufferPointer+1
    jsr RECEIVETRIES
    bcs BUSCALL_11
    jsr GROUPCOUNT
    sta Count
    sty CountHigh
BUSCALL_6:
    ldy #$00
    ldx CardState
    bne BUSCALL_7
    bit CardCommand
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
    lda BusResult
BUSCALL_9:
    sta ErrorCode
    bvc BUSCALL_10
    sty CardData
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
    sta BusResult
    bra BUSCALL_6

;; Each bus command's packet: bit 7 data to the device, bit 6 data back, bits 0-3 the parameters.
BUSCOMMANDS:
    .byte $43, $43, $83, $01, $83, $01, $01, $01, $44, $84

;; Resets the SmartPort bus and assigns unit numbers to its devices with INIT commands.
;; In:    A = $00 (cold) or $80, X = the first unit for the bus
;; Out:   A = the devices found (DeviceKinds = $80 for each)
BUSINIT:
    sta CommandPacket+4
    phx
    lda #$00
BUSINIT_1:
    sta UnitCount,X
    inx
    cpx #$04
    bcc BUSINIT_1
    bit Iwm::MotorOff
    lda #$FF
    sta Drive
    jsr PORTOFF
    jsr MFMOFF
    lda #$17
    jsr SETIWMMODE
    plx
    stx Drive
    jsr BUSRESET
    jsr BUSIDLE
    stz SavedDrive
BUSINIT_2:
    lda #$80
    sta PacketType
    lda #$05
    sta CommandPacket
    lda #$02
    sta CommandPacket+1
    stz CommandPacket+3
    stz CommandPacket+5
    jsr COMMANDPOINTER
    jsr BUSSEND
    bcs BUSINIT_4
    stz BufferPointer
    lda #$0C
    sta BufferPointer+1
    jsr BUSRECEIVE
    bcs BUSINIT_4
    ldy Drive
    cpy #$05
    bcs BUSINIT_3
    lda #$80
    sta UnitCount,Y
    lda #$00
    sta SpanCylinder,Y
BUSINIT_3:
    inc SavedDrive
    inc Drive
    lda BusResult
    beq BUSINIT_2
    lda SavedDrive
    cmp #$03
    bcc BUSINIT_4
    lda #$02
    sta SavedDrive
BUSINIT_4:
    jsr BUSIDLE
    bit Iwm::MotorOff
    lda SavedDrive
    rts
