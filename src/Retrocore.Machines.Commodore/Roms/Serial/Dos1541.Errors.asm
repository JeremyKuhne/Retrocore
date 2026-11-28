; retrocore: style=strict
; COMMODORE 1541 DOS: THE ERROR CHANNEL AND THE UTILITY LOADER ($E4FC-$E852)
.scope Errors continued

;; The error messages: each entry its BCD numbers, then its text, first and last bytes with bit 7 set and tokens for
;; shared words; the words last (Q3).
;; Also: ERRTAB (D1541)
Messages:
    .byte $00, $A0, $4F, $CB
    .byte $20, $21, $22, $23, $24, $27
    .byte $D2, "EAD", $89
    .byte $52, $83, " TOO LARG", $C5
    .byte $50, $8B, $06, " PRESEN", $D4
    .byte $51, $CF, "VERFLOW "
    .byte "IN", $8B
    .byte $25, $28, $8A, $89
    .byte $26, $8A, " PROTECT O", $CE
    .byte $29, $88, " ID", $85
    .byte $30, $31, $32, $33, $34
    .byte $D3, "YNTAX", $89
    .byte $60, $8A, $03, $84
    .byte $63, $83, " EXIST", $D3
    .byte $64, $83, " TYPE", $85
    .byte $65, $CE, "O BLOC", $CB
    .byte $66, $67, $C9, "LLEGAL TRACK"
    .byte " OR SECTO", $D2
    .byte $61, $83, $06, $84
    .byte $39, $62, $83, $06, $87
    .byte $01, $83, "S SCRATCHE", $C4
    .byte $70, $CE, "O CHANNE", $CC
    .byte $71, $C4, "IR", $89
    .byte $72, $88, " FUL", $CC
.if DRIVE_1540
    ; The 1540's message 73 is CBM DOS V2.6 V170.
    .byte $73, $C3, "BM DOS V2.6 V17", $B0
.else
    .byte $73, $C3, "BM DOS V2.6 154", $B1
.endif
    .byte $74, $C4, "RIVE", $06, " READ", $D9
    .byte $09, $C5, "RRO", $D2
    .byte $0A, $D7, "RIT", $C5
    .byte $03, $C6, "IL", $C5
    .byte $04, $CF, "PE", $CE
    .byte $05, $CD, "ISMATC", $C8
    .byte $06, $CE, $4F, $D4
    .byte $07, $C6, "OUN", $C4
    .byte $08, $C4, "IS", $CB
    .byte $0B, $D2, "ECOR", $C4

;; The end of <Messages>, <CopyMessage>'s bound; shares `$E60A` with ERROR (<JobError>), which owns the address (Q3).
;; Also: ETEND (D1541)
MessagesEnd:

;; A = a job's error code, X = the job: TRACK and SECTOR from its HDRS entry, the code made the DOS's number (2-11 are
;; 20-29, $10 is 24, $0F is 74), then <Abort>; while validating it skips <Abort>: CMDNUM = `$FF`, the message is set,
;; the drive reinitialized (INITDR) and it goes to <Recover> (ERR3 to INITDR, CMDER3). Shares `$E60A` with
;; `Errors::MessagesEnd` (ETEND), the table's end.
;; Also: ERROR (D1541)
.proc JobError
    pha
    stx JobNumber
    txa
    asl
    tax
    lda JobHeaders,x
    sta Track
    lda JobHeaders+1,x
    sta Sector
    pla
    and #$0F
    beq DecodingError
    cmp #$0F
    bne Convert
    lda #ERROR_DRIVE_NOT_READY
    bne CheckValidating

;; The low nybble 0, code $10: 24.
;; Also: ERR1 (D1541)
DecodingError:
    lda #$06

;; The code plus $20, less 2.
;; Also: ERR2 (D1541)
Convert:
    ora #$20
    tax
    dex
    dex
    txa

;; Validating?
;; Also: ERR3 (D1541)
CheckValidating:
    pha
    lda CommandNumber
    cmp #Commands::VALIDATE
    bne NotValidating
    lda #$FF
    sta CommandNumber
    pla
    jsr SetMessage
    jsr Bam::InitializeDrive
    jmp Recover

;; The number back, and on into <Abort>.
;; Also: ERR4 (D1541)
NotValidating:
    pla
.endproc

;; A = an error number: sets its message with the current TRACK and SECTOR, and falls into <Recover>.
;; Also: CMDER2 (D1541)
.proc Abort
    jsr SetMessage
.endproc

;; Ends a failed command: clears the command buffer and WBAM, starts the flashing, frees the internal channel, resets
;; the stack, and goes idle; for a data channel it first frees the channel (not a relative or direct one) of the
;; listener or talker it was.
;; Also: CMDER3 (D1541)
.proc Recover
    jsr Commands::ClearBuffer
    lda #$00
    sta BamWriteDeferred
    jsr StartFlashing
    jsr Files::FreeInternalChannels
    lda #$00
    sta $A3
    ldx #Controller::OVERFLOW_SIZE
    txs
    lda SecondaryCommand
    and #$0F
    sta SecondaryAddress
    cmp #$0F
    beq ToIdle
    sei
    lda Listening
    bne WhileListening
    lda Talking
    bne WhileTalking
    ldx SecondaryAddress
    lda SecondaryChannels,x
    cmp #$FF
    beq ToIdle
    and #$0F
    sta Channel
    jmp FreeChannel

;; Talking: the read channel (the listing's comment says ITERR; Q10's slip, and -01 to -03 release the bus here, Q7).
;; Also: TLKERR (D1541)
WhileTalking:
    jsr Files::FindReadChannel
.if LATE_PATCHES
    nop
    nop
    nop
.else
    jsr Serial::BusError
.endif
    bne FreeChannel

;; Listening: the write channel.
;; Also: LSNERR (D1541)
WhileListening:
    jsr Files::FindWriteChannel
.if LATE_PATCHES
    nop
    nop
    nop
.else
    jsr Serial::BusError
.endif

;; Frees LINDX's channel unless its file is relative or direct (<Files::ChannelType> at RELTYP or above).
;; Also: TLERR (D1541)
FreeChannel:
    jsr Files::ChannelType
    cmp #TYPE_RELATIVE
    bcs ToIdle
    jsr Files::FreeChannel

;; On to the idle loop.
;; Also: ERR10 (D1541)
ToIdle:
    jmp Idle::Loop
.endproc

;; A = a number below 100: made BCD by counting up in decimal mode, then falls into <PutBcd>.
;; Also: HEXDEC (D1541)
.proc PutDecimal
    tax
    lda #$00
    sed

;; Each count.
;; Also: HEX0 (D1541)
Count:
    cpx #$00
    beq Converted
    clc
    adc #$01
    dex
    jmp Count

;; Binary mode again.
;; Also: HEX5 (D1541)
Converted:
    cld
.endproc

;; A = BCD: its two digits at (CB+2),Y, Y advanced; X = the BCD.
;; Also: BCDDEC (D1541)
.proc PutBcd
    tax
    lsr
    lsr
    lsr
    lsr
    jsr PutDigit
    txa
.endproc

;; A's low digit as ASCII at (CB+2),Y, Y advanced.
;; Also: BCD2 (D1541)
.proc PutDigit
    and #$0F
    ora #$30
    sta (CommandPointer+2),y
    iny
    rts
.endproc

;; Stops the flashing and falls into <SetMessageWithoutBlock> with 00: 00, OK,00,00.
;; Also: OKERR (D1541)
.proc SetOk
    jsr StopFlashing
    lda #$00
.endproc

;; TRACK and SECTOR = 0, and falls into <SetMessage>.
;; Also: ERRTS0 (D1541)
.proc SetMessageWithoutBlock
    ldy #$00
    sty Track
    sty Sector
.endproc

;; A = the error's BCD number: writes "nn,TEXT,tt,ss" to ERRBUF, puts its first byte in the error channel's CHNDAT and
;; its end in LSTCHR, and makes the channel ready to talk.
;; Also: ERRMSG (D1541)
.proc SetMessage
    ldy #$00
    ldx #<ErrorBuffer
    stx CommandPointer+2
    ldx #>ErrorBuffer
    stx CommandPointer+3
    jsr PutBcd
    lda #$2C
    sta (CommandPointer+2),y
    iny
    lda ErrorBuffer
    sta $0243
    txa
    jsr CopyMessage
    lda #$2C
    sta (CommandPointer+2),y
    iny
    lda Track
    jsr PutDecimal
    lda #$2C
    sta (CommandPointer+2),y
    iny
    lda Sector
    jsr PutDecimal
    dey
    tya
    clc
    adc #<ErrorBuffer
    sta $0249
    inc CommandPointer+2
    lda #CHANNEL_TALK
    sta $F7
    rts
.endproc

;; A = a BCD error number or a token: finds its entry in <Messages> and copies the text to (CB+2),Y, expanding tokens by
;; calling itself; R0 kept. Copies nothing if none matches.
;; Also: ERMOVE (D1541)
.proc CopyMessage
    tax
    lda Work0
    pha
    lda Work0+1
    pha
    lda #<Messages
    sta Work0
    lda #>Messages
    sta Work0+1
    txa
    ldx #$00

;; Does this entry's number match?
;; Also: E10 (D1541)
Compare:
    cmp (Work0,x)
    beq Found
    pha
    jsr ReadAndAdvance
    bcc CheckEnd

;; No: past the entry's text, to its last byte.
;; Also: E20 (D1541)
SkipText:
    jsr ReadAndAdvance
    bcc SkipText

;; Until past <MessagesEnd> (Q10: one byte past).
;; Also: E30 (D1541)
CheckEnd:
    lda Work0+1
    cmp #>MessagesEnd
    bcc Next
    bne NotFound
    lda #<MessagesEnd
    cmp Work0
    bcc NotFound

;; The next byte.
;; Also: E40 (D1541)
Next:
    pla
    jmp Compare

;; Not in the table.
;; Also: E45 (D1541)
NotFound:
    pla
    jmp Done

;; Past the entry's other numbers, to its text.
;; Also: E50 (D1541)
Found:
    jsr AdvanceAndRead
    bcc Found

;; Each byte, to the last.
;; Also: E55 (D1541)
CopyText:
    jsr PutMessageByte
    jsr AdvanceAndRead
    bcc CopyText
    jsr PutMessageByte

;; R0 back.
;; Also: E90 (D1541)
Done:
    pla
    sta Work0+1
    pla
    sta Work0
    rts
.endproc

;; A = a byte of a message's text: below $20 it is a token, a space and the word; otherwise the character.
;; Also: E60 (D1541)
.proc PutMessageByte
    cmp #$20
    bcs Character
    tax
    lda #$20
    sta (CommandPointer+2),y
    iny
    txa
    jsr CopyMessage
    rts

;; A character: at (CB+2),Y.
;; Also: E70 (D1541)
Character:
    sta (CommandPointer+2),y
    iny
    rts
.endproc

;; R0 up one, then Read.
;; Entry:
;;   Read = The byte at R0
;; Also: EADV1 (D1541)
.proc AdvanceAndRead
    inc Work0
    bne Read
    inc Work0+1

;; The byte at R0: A = it without bit 7, carry = bit 7 (a text's first or last byte).
;; Also: EA10 (D1541)
Read:
    lda (Work0,x)
    asl
    lda (Work0,x)
    and #$7F
    rts
.endproc

;; Read, then R0 up one.
;; Also: EADV2 (D1541)
.proc ReadAndAdvance
    jsr AdvanceAndRead::Read
    inc Work0
    bne Done
    inc Work0+1

;; Returns.
;; Also: EA20 (D1541)
Done:
    rts
.endproc
.endscope
.scope Startup continued

.if LATE_PATCHES = 0
;; The boot loader's exit, where <Boot> finds no clip.
;; Also: BOOT2 (D1541)
.proc BootExit
    rts
.endproc
.else
    ; The removed boot loader's exit, which nothing reaches now (BOOT2 in the listing).
    rts
.endif

;; Start-up calls it last. Before -05, and in the 1540, it is the boot loader: with CLK and DATA both grounded (a clip
;; on the bus), it waits for the clip to come off and loads the first utility on the disk, as & would. -05 removed it,
;; since it does not work on the serial bus: there it is only an RTS, with 34 bytes of filler, NOPs and an RTS.
;; Also: BOOT (D1541)
.proc Boot
.if LATE_PATCHES
    rts
    .res 33, $EA
    rts
.else
    lda Via1PortB
    tax
    and #$04
    beq BootExit
    txa
    and #$01
    beq BootExit
    cli

;; The clip must come off before the utility loads.
;; Also: BOOT3 (D1541)
WaitForClip:
    lda Via1PortB
    and #$05
    bne WaitForClip
    inc SecondStreamEnd
    inc CommandLength
    lda #$2A
    sta CommandBuffer
    jmp Commands::LoadUtility::AfterName
.endif
.endproc
.endscope
.scope Commands continued

;; &: the name (the string scanned to its end), looked up (not found: 39); opened as a user file (type 3; the listing's
;; comment says 5); then each record, an address, a count, the bytes and a checksum, stored; a bad checksum is 50, an
;; early end 51. Jumps to the first record's address, F2CNT kept for the utility. (Reached through the command table.)
;; Also: UTLODR (D1541)
.proc LoadUtility
    lda #$8D
    jsr ScanFor
.if LATE_PATCHES = 0

;; Where the boot loader joins, with the name `*` set.
;; Also: BOOT4 (D1541)
AfterName:
.endif
    jsr DisableProtection
    lda SecondStreamEnd
    pha
    lda #$01
    sta SecondStreamEnd
    lda #$FF
    sta Work0
    jsr Directory::FindAll
    lda FileNameTrack
    bne Found
    lda #ERROR_COMMAND_FILE_NOT_FOUND
    jsr Fail

;; F2CNT back; the file's first block from FILTRK and FILSEC, and opened.
;; Also: UTLD00 (D1541)
Found:
    pla
    sta SecondStreamEnd
    lda FileNameTrack
    sta Track
    lda FileNameSector
    sta Sector
    lda #TYPE_USER
    jsr Files::OpenInternalRead::WithType

;; R1, the checksum, cleared; the address into R2 and R3, kept on the stack for the first record (R0 flags it).
;; Also: UTLD10 (D1541)
NextRecord:
    lda #$00
    sta Work1
    jsr GetByte
    sta Work2
    jsr AddToChecksum
    jsr GetByte
    sta Work3
    jsr AddToChecksum
    lda Work0
    beq ReadCount
    lda Work2
    pha
    lda Work3
    pha
    lda #$00
    sta Work0

;; The byte count into R4.
;; Also: UTLD20 (D1541)
ReadCount:
    jsr GetByte
    sta Work4
    jsr AddToChecksum

;; Each byte to the address, into the checksum.
;; Also: UTLD30 (D1541)
StoreByte:
    jsr GetByte
    ldy #$00
    sta (Work2),y
    jsr AddToChecksum
    lda Work2
    clc
    adc #$01
    sta Work2
    bcc CountDown
    inc Work3

;; R4 down; then the checksum byte compared.
;; Also: UTLD35 (D1541)
CountDown:
    dec Work4
    bne StoreByte
    jsr GetInternalByte
    lda DataByte
    cmp Work1
    beq CheckEnd
    jsr Files::GetBufferBlock
    lda #ERROR_RECORD_NOT_PRESENT
    jsr Errors::Abort

;; Not the file's end: the next record; at the end, jumps to the first record's address.
;; Also: UTLD50 (D1541)
CheckEnd:
    lda MoreBytes
    bne NextRecord
    pla
    sta Work3
    pla
    sta Work2
    jmp (Work2)

;; The next byte (<GetInternalByte>) in A; if it was the file's last, 51 (the record overran), with the block's track
;; and sector.
;; Also: GTABYT (D1541)
.proc GetByte
    jsr GetInternalByte
    lda MoreBytes
    bne Return
    jsr Files::GetBufferBlock
    lda #ERROR_RECORD_OVERFLOW
    jsr Errors::Abort

;; A = DATA.
;; Also: GTABYE (D1541)
Return:
    lda DataByte
    rts
.endproc

;; R1 = R1 + A, the carry added back in.
;; Also: ADDSUM (D1541)
.proc AddToChecksum
    clc
    adc Work1
    adc #$00
    sta Work1
    rts
.endproc
.endproc
.endscope
