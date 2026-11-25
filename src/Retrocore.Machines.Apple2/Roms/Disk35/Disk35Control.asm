;; THE CARD'S FIRMWARE: CONTROL AND STATUS

;; SmartPort CONTROL ($04): asks the host for the control list in buffer code 6 ($0C00) and runs the
;; control code in ParameterLow. Codes $14 and up, and the ones a unit does not take, answer $21; a list of
;; $400 bytes or more answers $22.
DOCONTROL:
    ldx ParameterLow
    cpx #$14
    bcs ERRBADCONTROL
    lda Drive
    bpl DOCONTROL_1
    bit CONTROLUNIT0,X
    bmi ERRBADCONTROL
    bvc DOCONTROL_1
    bra ERRBADCONTROL
DOCONTROL_1:
    ldx CountHigh
    cpx #$04
    bcs ERRBADCTLPARAM
    lda #$06
    sta CardData
DOCONTROL_2:
    lda CardData
    bpl DOCONTROL_2
    lda ParameterLow
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
    lda ZeroPageImage+Marks-1,X
    sta Marks-1,X
    dex
    bne CTLRESETMARKS_1
    bra CTLSETSIDES_1

;; Control $0E: puts the vectors ($72-$8C) back from the ROM.
CTLRESETVECTORS:
    ldx ZeroPageImage+VectorLength
CTLRESETVECTORS_1:
    lda ZeroPageImage+Vectors-1,X
    sta Vectors-1,X
    dex
    bne CTLRESETVECTORS_1
    bra CTLSETSIDES_1

;; Control $0F: one byte, whose bit 7 goes to CacheOption; the cache is flushed.
CTLSETCACHE:
    lda #$01
    jsr CHECKCOUNT
    lda XFERBUFFER
    and #$80
    sta CacheOption
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
    sty Interleave
    ldx Drive
    sty FormatInterleave,X
    bra CTLSETSIDES_1

;; Control $09: one byte, whose bit 7 set has FORMAT write both sides.
CTLSETSIDES:
    lda #$01
    jsr CHECKCOUNT
    bne SETADDRESSCOUNT_1
    lda XFERBUFFER
    and #$80
    sta TwoSided
CTLSETSIDES_1:
    lda #$00
    jmp CONTROLDONE

;; Control $00, reset: forgets the disk and reads it again.
;; Out:   carry = set if the drive has no usable disk
CTLRESET:
    ldx Drive
    jsr FORGETDISK
    jsr CHECKDISK
    bpl CTLRESET_1
    jsr IDENTIFYMEDIA
CTLRESET_1:
    bcc CTLRESET_2
    jmp SETERROR
CTLRESET_2:
    rts

;; Control $04, eject: ejects Drive's disk and forgets its sectors.
;; Out:   carry = clear
CTLEJECT:
    ldx Drive
    jsr READSENSE
    jsr EJECT
    ldx Drive
    jsr FORGETCACHE
    clc
    rts

;; Control $12: calls code in the card at an address set in the list (CALLUSER), and keeps A, X, Y
;; and P in ResultA-ResultStatus for status code 5.
CTLEXECUTE:
    jsr CALLUSER
    sta ResultA
    stx ResultX
    sty ResultY
    php
    pla
    sta ResultStatus
    clc
    rts

;; Control $13: two bytes, an address; its byte goes to Retries ($58) for status code 5.
CTLPEEK:
    jsr CTLSETADDRESS
    lda (UserPointer)
    sta Retries
    clc
    rts

;; Control $0C: three bytes, an address and (read from $0C04) a byte to store there.
CTLPOKE:
    lda #$03
    jsr SETADDRESSCOUNT
    lda XFERBUFFER+4
    sta (UserPointer)
    clc
    rts

;; Control $10: two bytes, an address in card RAM for CTLDOWNLOAD.
CTLSETADDRESS:
    lda #$02

;; Takes UserPointer from the list's first two bytes, if the list has the expected length.
;; In:    A = the length
;; Out:   carry = clear; or an error $22 through CONTROLDONE
SETADDRESSCOUNT:
    jsr CHECKCOUNT
    bne SETADDRESSCOUNT_1
    lda XFERBUFFER
    sta UserPointer
    lda XFERBUFFER+1
    sta UserPointer+1
    clc
    rts
SETADDRESSCOUNT_1:
    jmp ERRBADCTLPARAM

;; Control $11: copies the control list to UserPointer, leaving the pointer where it was.
CTLDOWNLOAD:
    ldx UserPointer+1
    ldy #$00
    lda #$00
    sta WorkPointer
    lda #$0C
    sta WorkPointer+1
CTLDOWNLOAD_1:
    lda (WorkPointer),Y
    sta (UserPointer),Y
    iny
    bne CTLDOWNLOAD_2
    inc WorkPointer+1
    inc UserPointer+1
CTLDOWNLOAD_2:
    dec Count
    bne CTLDOWNLOAD_1
    dec CountHigh
    bpl CTLDOWNLOAD_1
    stx UserPointer+1
    clc
    rts

;; Loads A, X, Y and P from the list's first four bytes and jumps to the address in its next two.
CALLUSER:
    lda XFERBUFFER+4
    sta WorkPointer
    lda XFERBUFFER+5
    sta WorkPointer+1
    lda XFERBUFFER+3
    pha
    ldx XFERBUFFER+1
    ldy XFERBUFFER+2
    lda XFERBUFFER
    plp
    jmp (WorkPointer)

;; Compares the control list's length with A.
;; Out:   zero = it matches
CHECKCOUNT:
    ldy CountHigh
    bne CHECKCOUNT_1
    cmp Count
CHECKCOUNT_1:
    rts

;; Ejects a drive's disk: the motor off (200 ms), the eject command, then up to about 2 s for the disk to leave.
;; In:    X = the drive
;; Out:   carry = clear; ErrorCode = $27 if the disk did not leave
EJECT:
    stx EjectDrive
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
    sta Retries
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
    sta ErrorCode
    bra EJECT_4
EJECT_3:
    jsr FORGETDISK
EJECT_4:
    lda #$80
    sta EjectDrive
    clc
    rts

;; Unit 0's name, for status code 1.
CONTROLLERNAME:
    .byte "APPLE UNIVERSAL 3.5 CONTROLLER"

;; SmartPort STATUS ($00), and ProDOS STATUS: builds the status list at $0C00 for the host.
;; Unit 0: code 0, the controller's 8 bytes; code 1, its name. A 3.5 drive: code 0, the general status;
;; code 3, the DIB; code 5, the last result. Others answer $21.
;; Out:   Count, CountHigh = the list's length, CardData = 6
DOSTATUS:
    stz Count
    stz CountHigh
    ldx Drive
    bpl DOSTATUS_2
    lda ParameterLow
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
    ldx ParameterLow
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
    stx Count
    lda #$06
    sta CardData
    ldx Drive
    bit UnitWithHighBit
    bmi DOSTATUS_5
    jsr RELEASEDRIVE
    clc
    rts
DOSTATUS_5:
    clc
    rts
DOSTATUS_6:
    lda UnitCount
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
    lda ErrorCode,X
    sta XFERBUFFER,X
    inx
    cpx #$08
    bcc DOSTATUS_9
    bra STATUSDONE
STATUSDRIVE:
    ldx Drive
    jsr READSENSE
    php
    and Sense,X
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
    bit PreviousSense
    bvc DOSTATUS_12
DOSTATUS_11:
    bit CardCommand
    bvc DOSTATUS_12
    ora #$01
DOSTATUS_12:
    sta XFERBUFFER
    jsr CHECKDISK
    bpl DOSTATUS_13
    jsr IDENTIFYMEDIA
DOSTATUS_13:
    ldx #$04
    ldy Drive
    lda BlockCount,Y
    sta XFERBUFFER+1
    lda BlockCountHigh,Y
    sta XFERBUFFER+2
    stz XFERBUFFER+3
    bit CardCommand
    bvc DOSTATUS_14
    stz XFERBUFFER+4
    inx
DOSTATUS_14:
    lda ParameterLow
    beq DOSTATUS_8
    ldy Drive
    lda DeviceKinds,Y
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
;; Out:   Count, CountHigh = the length, CardData = 6, ErrorCode = $22 if ParameterLow and ParameterMiddle ask for less
FORMATOPTIONS:
    ldx Drive
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
    sta SecondBufferPointer
    lda #$0C
    sta SecondBufferPointer+1
    stz XFERBUFFER
    stz XFERBUFFER+2
    ldx Drive
    lda MediaKind,X
    sta XFERBUFFER+6
    lda #$02
    bit DeviceKinds,X
    beq FORMATOPTIONS_5
    lda #$0A
    sta XFERBUFFER+4
    lda MediaMode,X
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
    cpy ParameterMiddle
    bcc FORMATOPTIONS_10
    beq FORMATOPTIONS_9
FORMATOPTIONS_8:
    jmp ERRBADPARAMETER
FORMATOPTIONS_9:
    cmp ParameterLow
    beq FORMATOPTIONS_10
    bcs FORMATOPTIONS_8
FORMATOPTIONS_10:
    sta Count
    sty CountHigh
    lda #$06
    sta CardData
    clc
    rts

;; Adds a format to FORMATOPTIONS' list.
;; In:    A = the format kind; SecondBufferPointer = where
ADDFORMATOPTION:
    inc XFERBUFFER
    inc XFERBUFFER+2
    ldy #$00
    sta (SecondBufferPointer)
    tax
    lda FORMATINFO,X
    and #$0F
    ldy #$04
    sta (SecondBufferPointer),Y
    lda FORMATINFO,X
    lsr A
    lsr A
    lsr A
    lsr A
    ldy #$0C
    sta (SecondBufferPointer),Y
    lda MEDIABLOCKS,X
    ldy #$06
    sta (SecondBufferPointer),Y
    iny
    lda MEDIABLOCKS+1,X
    sta (SecondBufferPointer),Y
    ldy #$0B
    lda #$02
    sta (SecondBufferPointer),Y
    lda MEDIABLOCKS+1,X
    lsr A
    ldy #$0F
    sta (SecondBufferPointer),Y
    lda MEDIABLOCKS,X
    ror A
    dey
    sta (SecondBufferPointer),Y
    lda SecondBufferPointer
    clc
    adc #$10
    sta SecondBufferPointer
    bcc ADDFORMATOPTION_1
    inc SecondBufferPointer+1
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

;; Each MediaKind's block count.
MEDIABLOCKS:
    .byte $00
    .byte $00, $20, $03, $40, $06, $40, $06, $A0, $05, $40, $0B, $40, $0B, $00, $00

;; Command $0A: chooses the format the next FORMAT writes.
;; In:    ParameterLow = the format kind (0, or an even number below $0D), ParameterHigh = the interleave, or 0
;; Out:   ErrorCode = $21 for a bad kind
SETFORMAT:
    lda ParameterMiddle
    beq SETFORMAT_2
SETFORMAT_1:
    jmp ERRBADCONTROL
SETFORMAT_2:
    lda ParameterLow
    cmp #$0D
    bcs SETFORMAT_1
    and #$01
    bne SETFORMAT_1
    ldx Drive
    lda ParameterLow
    bne SETFORMAT_3
    lda #$02
    sta FormatKind,X
    jsr CLEARFORMAT
    bra SETFORMAT_4
SETFORMAT_3:
    sta FormatKind,X
    tay
    lda FORMATINFO,Y
    lsr A
    lsr A
    lsr A
    lsr A
    sta FormatInterleave,X
    lda ParameterHigh
    beq SETFORMAT_4
    cmp #$0D
    bcs SETFORMAT_1
    sta FormatInterleave,X
SETFORMAT_4:
    stz CardData
    clc
    rts
