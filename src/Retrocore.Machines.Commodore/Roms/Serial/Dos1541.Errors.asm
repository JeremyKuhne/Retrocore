; retrocore: style=strict
; COMMODORE 1541 DOS: THE ERROR CHANNEL AND THE UTILITY LOADER ($E4FC-$E852)

;; Emits one text piece of an error message: a string's characters, or a word token's number, with bit 7 set on the
;; message's first and last byte (which end the text).
;; Parameters:
;;   item = a string or a token (an `Errors::WORD_` constant)
;;   isFirst = nonzero when the piece starts the text
;;   isLast = nonzero when the piece ends the text
.macro MessagePiece item, isFirst, isLast
    .if .match(.left(1, {item}), {""})
        .repeat .strlen(item), I
            .if (I = 0 && isFirst) || (I = .strlen(item) - 1 && isLast)
                .byte .strat(item, I) | $80
            .else
                .byte .strat(item, I)
            .endif
        .endrepeat
    .else
        .if isFirst || isLast
            .byte item | $80
        .else
            .byte item
        .endif
    .endif
.endmacro

;; Emits an error message's entry for <Errors::Messages>: its BCD number, then its text of up to three pieces, each a
;; string or a word token, with bit 7 set on the text's first and last byte. A message with more numbers has the
;; others in a `.byte` line above this one.
;; Parameters:
;;   number = the error's number, in BCD as the DOS keeps it
;;   first = the text's first piece
;;   second = its second piece, if any
;;   third = its third piece, if any
.macro Message number, first, second, third
    .byte number
    MessagePiece first, 1, .blank({second})
    .if .not .blank({second})
        MessagePiece second, 0, .blank({third})
    .endif
    .if .not .blank({third})
        MessagePiece third, 0, 1
    .endif
.endmacro

; The error channel: the messages, how a failure sets one, and how it ends the command. The family opens in
; Commands.asm; this is its main part.
.scope Errors continued

; The words the messages share, as tokens: a byte below $20 in a message's text stands for a space and the word, which
; <CopyMessage> finds as the entry with that number at the table's end.

;; The token for the word ERROR.
WORD_ERROR = $09

;; The token for the word WRITE.
WORD_WRITE = $0A

;; The token for the word FILE.
WORD_FILE = $03

;; The token for the word OPEN.
WORD_OPEN = $04

;; The token for the word MISMATCH.
WORD_MISMATCH = $05

;; The token for the word NOT.
WORD_NOT = $06

;; The token for the word FOUND.
WORD_FOUND = $07

;; The token for the word DISK.
WORD_DISK = $08

;; The token for the word RECORD.
WORD_RECORD = $0B

;; The error messages, as "nn, text,tt,ss" is built from them: each entry has its BCD number or numbers, then its text,
;; whose first and last bytes have bit 7 set, with tokens (the `WORD_` constants) for words that messages share. The
;; entries for the words themselves come last. <CopyMessage> searches the table from its start for a number.
;;
;; A message may have several numbers (20 to 24 and 27 are all READ ERROR); the numbers before a text are those of its
;; entry. Message 73 differs in the 1540 (`V170`).
;; Also: ERRTAB (D1541)
Messages:
    Message $00, " OK"
    .byte $20, $21, $22, $23, $24
    Message $27, "READ", WORD_ERROR
    Message $52, WORD_FILE, " TOO LARGE"
    Message $50, WORD_RECORD, WORD_NOT, " PRESENT"
    Message $51, "OVERFLOW IN", WORD_RECORD
    .byte $25
    Message $28, WORD_WRITE, WORD_ERROR
    Message $26, WORD_WRITE, " PROTECT ON"
    Message $29, WORD_DISK, " ID", WORD_MISMATCH
    .byte $30, $31, $32, $33
    Message $34, "SYNTAX", WORD_ERROR
    Message $60, WORD_WRITE, WORD_FILE, WORD_OPEN
    Message $63, WORD_FILE, " EXISTS"
    Message $64, WORD_FILE, " TYPE", WORD_MISMATCH
    Message $65, "NO BLOCK"
    .byte $66
    Message $67, "ILLEGAL TRACK OR SECTOR"
    Message $61, WORD_FILE, WORD_NOT, WORD_OPEN
    .byte $39
    Message $62, WORD_FILE, WORD_NOT, WORD_FOUND
    Message $01, WORD_FILE, "S SCRATCHED"
    Message $70, "NO CHANNEL"
    Message $71, "DIR", WORD_ERROR
    Message $72, WORD_DISK, " FULL"
.if DRIVE_1540
    ; The 1540's message 73 is CBM DOS V2.6 V170.
    Message $73, "CBM DOS V2.6 V170"
.else
    Message $73, "CBM DOS V2.6 1541"
.endif
    Message $74, "DRIVE", WORD_NOT, " READY"

    ; The words themselves, which tokens are the numbers of.
    Message WORD_ERROR, "ERROR"
    Message WORD_WRITE, "WRITE"
    Message WORD_FILE, "FILE"
    Message WORD_OPEN, "OPEN"
    Message WORD_MISMATCH, "MISMATCH"
    Message WORD_NOT, "NOT"
    Message WORD_FOUND, "FOUND"
    Message WORD_DISK, "DISK"
    Message WORD_RECORD, "RECORD"

;; The end of <Messages>, which <CopyMessage> stops its search at. It shares its address, `$E60A`, with <JobError>,
;; which owns it.
;;
;; The search stops only once its pointer is past this address, so it still compares the byte at it, <JobError>'s first
;; instruction, with the number it looks for: a one-byte overrun, harmless while no message has that number.
;; Also: ETEND (D1541)
MessagesEnd:

;; A message text's byte below this is a word token, not a character.
TOKEN_LIMIT = $20

;; Sets the message for a job that failed, then ends the command like <Abort>, so it never returns.
;;
;; The job's track and sector, from <JobHeaders>, go in the message. Its error code, the low nybble of A, becomes the
;; DOS's number: codes 2 to 11 are 20 to 29, code 0 (the code $10) is 24, and code $0F is 74, drive not ready. While
;; the VALIDATE command runs, it instead sets <CommandNumber> to $FF, sets the message, reinitializes the drive and goes
;; straight to <Recover>.
;; In: A = the job's error code, X = the job's number
;; Errors: 20 to 29 and 74, by the code
;; Also: ERROR (D1541)
.proc JobError
    ; The job's track and sector, for the message.
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

    ; The code: 0 is 24 and $0F is 74; the others are made 20 to 29 below.
    and #$0F
    beq DecodingError
    cmp #$0F
    bne Convert
    lda #ERROR_DRIVE_NOT_READY
    bne CheckValidating

;; Code 0, which is $10 with its high nybble dropped: error 24.
;; Also: ERR1 (D1541)
DecodingError:
    lda #$06

;; The code plus $20, less 2: 20 to 29 in BCD.
;; Also: ERR2 (D1541)
Convert:
    ora #$20
    tax
    dex
    dex
    txa

;; Validating? Then the message is set without ending the command.
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

;; Not validating: the number back, and on into <Abort>.
;; Also: ERR4 (D1541)
NotValidating:
    pla
    ; Falls into Abort.
    .assert * = Abort, "JobError falls into Abort."
.endproc

;; Sets the message for an error, with the current track and sector, and ends the command with <Recover>: it never
;; returns.
;; In: A = the error's number, in BCD
;; Errors: the number in A
;; Also: CMDER2 (D1541)
.proc Abort
    jsr SetMessage
    ; Falls into Recover.
    .assert * = Recover, "Abort falls into Recover."
.endproc

;; Ends a failed command and goes idle: it never returns. It clears the command buffer and the deferred BAM write,
;; starts the error LED flashing, frees the internal channels, and resets the stack to just below
;; <Controller::OVERFLOW_SIZE>'s bytes. For a data channel it first frees the channel, unless it is a relative or direct
;; one, of the listener or talker the bus had.
;; Also: CMDER3 (D1541)
.proc Recover
    ; The command and the BAM's pending write are dropped; the LED flashes.
    jsr Commands::ClearBuffer
    lda #$00
    sta BamWriteDeferred
    jsr StartFlashing
    jsr Files::FreeInternalChannels
    lda #$00
    sta CommandPointer

    ; The stack is reset, and the secondary address of the last command found.
    ldx #Controller::OVERFLOW_SIZE
    txs
    lda SecondaryCommand
    and #$0F
    sta SecondaryAddress
    cmp #COMMAND_SECONDARY
    beq ToIdle

    ; A data channel: free the one the bus was listening to or talking to, or else the secondary address's.
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

;; Talking: the read channel. The listing's comment says ITERR, a slip: the -01 to -03 builds call the bus error routine
;; here, which releases the bus, and -05 and later have three NOPs.
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

;; Frees the channel in <Channel> unless its file is a relative or direct one, whose type <Files::ChannelType> gives as
;; <TYPE_RELATIVE> or above.
;; Also: TLERR (D1541)
FreeChannel:
    jsr Files::ChannelType
    cmp #TYPE_RELATIVE
    bcs ToIdle
    jsr Files::FreeChannel

;; On to the idle loop, which never returns.
;; Also: ERR10 (D1541)
ToIdle:
    jmp Idle::Loop
.endproc

;; Makes a number below 100 BCD by counting up in decimal mode, then puts its digits like <PutBcd>.
;; In: A = a number from 0 to 99, Y = the offset into the message being built, at (CommandPointer+2)
;; Out: A = the low digit's character, X = the BCD, Y = advanced by 2, decimal = clear
;; Also: HEXDEC (D1541)
.proc PutDecimal
    tax
    lda #$00
    sed

;; One count up, for each unit of the number.
;; Also: HEX0 (D1541)
Count:
    cpx #$00
    beq Converted
    clc
    adc #$01
    dex
    jmp Count

;; The count is done: binary mode again.
;; Also: HEX5 (D1541)
Converted:
    cld
    ; Falls into PutBcd.
    .assert * = PutBcd, "PutDecimal falls into PutBcd."
.endproc

;; Puts a BCD number's two digits, as characters, at the message's end.
;; In: A = the BCD number, Y = the offset into the message being built, at (CommandPointer+2)
;; Out: A = the low digit's character, X = the BCD, Y = advanced by 2
;; Also: BCDDEC (D1541)
.proc PutBcd
    tax
    lsr
    lsr
    lsr
    lsr
    jsr PutDigit
    txa
    ; Falls into PutDigit.
    .assert * = PutDigit, "PutBcd falls into PutDigit."
.endproc

;; Puts a digit's character at the message's end.
;; In: A = the digit, in the low nybble, Y = the offset into the message being built, at (CommandPointer+2)
;; Out: A = the character, Y = advanced by 1
;; Keeps: X
;; Also: BCD2 (D1541)
.proc PutDigit
    and #$0F
    ora #'0'
    sta (CommandPointer+2),y
    iny
    rts
.endproc

;; Stops the error LED's flashing and sets the message 00, OK,00,00.
;; Out: as <SetMessage>
;; Also: OKERR (D1541)
.proc SetOk
    jsr StopFlashing
    lda #$00
    ; Falls into SetMessageWithoutBlock.
    .assert * = SetMessageWithoutBlock, "SetOk falls into SetMessageWithoutBlock."
.endproc

;; Sets the message for an error with no block: its track and sector are 0.
;; In: A = the error's number, in BCD
;; Out: as <SetMessage>
;; Also: ERRTS0 (D1541)
.proc SetMessageWithoutBlock
    ldy #$00
    sty Track
    sty Sector
    ; Falls into SetMessage.
    .assert * = SetMessage, "SetMessageWithoutBlock falls into SetMessage."
.endproc

;; Builds the error message "nn,TEXT,tt,ss" in <ErrorBuffer>, with the current track and sector, and makes the error
;; channel ready to talk it.
;;
;; The message's first byte goes to the channel's byte, its last byte's offset to the channel's last, and the channel's
;; status is set to <CHANNEL_TALK>. The channel's read position, (CommandPointer+2), is left at the message's second
;; byte.
;; In: A = the error's number, in BCD
;; Out:
;;   ChannelByte+MESSAGE_CHANNEL = the message's first byte
;;   ChannelLastByte+MESSAGE_CHANNEL = the offset of the message's end
;;   ChannelStatus+MESSAGE_CHANNEL = CHANNEL_TALK
;; Uses: A, X, Y, Work0
;; Also: ERRMSG (D1541)
.proc SetMessage
    ; The number, then a comma and the text.
    ldy #$00
    ldx #<ErrorBuffer
    stx CommandPointer+2
    ldx #>ErrorBuffer
    stx CommandPointer+3
    jsr PutBcd
    lda #','
    sta (CommandPointer+2),y
    iny
    lda ErrorBuffer
    sta ChannelByte+MESSAGE_CHANNEL
    txa
    jsr CopyMessage

    ; The track, then the sector, each after a comma.
    lda #','
    sta (CommandPointer+2),y
    iny
    lda Track
    jsr PutDecimal
    lda #','
    sta (CommandPointer+2),y
    iny
    lda Sector
    jsr PutDecimal

    ; The channel: its last byte is the one before Y, and it is ready to talk.
    dey
    tya
    clc
    adc #<ErrorBuffer
    sta ChannelLastByte+MESSAGE_CHANNEL
    inc CommandPointer+2
    lda #CHANNEL_TALK
    sta ChannelStatus+MESSAGE_CHANNEL
    rts
.endproc

;; Finds an error's entry in <Messages> and copies its text to the message being built, with its tokens expanded: it
;; calls itself for each. It copies nothing when no entry has the number.
;; In: A = a BCD error number or a word token, Y = the offset into the message, at (CommandPointer+2)
;; Out: X = 0, Y = advanced past the text
;; Keeps: Work0, Work0+1
;; Also: ERMOVE (D1541)
.proc CopyMessage
    ; The number kept in X, and <Work0> on the stack, then pointed at the table.
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

;; Does the byte at the pointer match the number?
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

;; Is the pointer past <MessagesEnd>? Only then it is the table's end: a byte at it is still compared.
;; Also: E30 (D1541)
CheckEnd:
    lda Work0+1
    cmp #>MessagesEnd
    bcc Next
    bne NotFound
    lda #<MessagesEnd
    cmp Work0
    bcc NotFound

;; The next byte, with the number back.
;; Also: E40 (D1541)
Next:
    pla
    jmp Compare

;; Not in the table.
;; Also: E45 (D1541)
NotFound:
    pla
    jmp Done

;; The entry: past its other numbers, to its text's first byte, which has bit 7 set.
;; Also: E50 (D1541)
Found:
    jsr AdvanceAndRead
    bcc Found

;; Each byte of the text, to the last, which has bit 7 set.
;; Also: E55 (D1541)
CopyText:
    jsr PutMessageByte
    jsr AdvanceAndRead
    bcc CopyText
    jsr PutMessageByte

;; <Work0> back.
;; Also: E90 (D1541)
Done:
    pla
    sta Work0+1
    pla
    sta Work0
    rts
.endproc

;; Puts a byte of a message's text at the message's end: a character as it is, a token as a space and then its word.
;; In: A = the byte without bit 7, Y = the offset into the message, at (CommandPointer+2)
;; Out: Y = advanced; X = 0 after a token
;; Also: E60 (D1541)
.proc PutMessageByte
    cmp #TOKEN_LIMIT
    bcs Character
    tax
    lda #' '
    sta (CommandPointer+2),y
    iny
    txa
    jsr CopyMessage
    rts

;; A character: put as it is.
;; Also: E70 (D1541)
Character:
    sta (CommandPointer+2),y
    iny
    rts
.endproc

;; Moves the table pointer on one byte, then reads it as <AdvanceAndRead::Read> does.
;; In: X = 0, Work0 = the pointer
;; Out: as Read
;; Entry:
;;   Read = reads the byte at the pointer without moving it: A = the byte without bit 7, carry = bit 7, which a text's
;;     first and last byte have set
;; Also: EADV1 (D1541)
.proc AdvanceAndRead
    inc Work0
    bne Read
    inc Work0+1

;; Reads the table's byte at the pointer.
;; Also: EA10 (D1541)
Read:
    lda (Work0,x)
    asl
    lda (Work0,x)
    and #$7F
    rts
.endproc

;; Reads the byte at the table pointer as <AdvanceAndRead::Read> does, then moves the pointer on one byte.
;; In: X = 0, Work0 = the pointer
;; Out: A = the byte without bit 7, carry = bit 7
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

; The start-up part that follows the error channel: the boot loader's exit and the boot loader, which the older builds
; have.
.scope Startup continued

.if LATE_PATCHES = 0
;; The boot loader's exit, where <Boot> finds no clip on the bus.
;; Also: BOOT2 (D1541)
.proc BootExit
    rts
.endproc
.else
    ; The removed boot loader's exit, which nothing reaches now (BOOT2 in the listing).
    rts
.endif

;; Start-up calls it last. Before -05, and in the 1540, it is the boot loader: with CLK and DATA both pulled (a clip
;; on the bus), it waits for the clip to come off, then loads the first utility on the disk, as the `&` command
;; would. -05 removed it, because it does not work on the serial bus: there it is an RTS, 33 bytes of NOPs and another
;; RTS.
;; Also: BOOT (D1541)
.proc Boot
.if LATE_PATCHES
    rts
    .res 33, $EA
    rts
.else
    ; The clip: CLK and DATA both read pulled, or it exits.
    lda Via1PortB
    tax
    and #Serial::CLOCK_IN
    beq BootExit
    txa
    and #Serial::DATA_IN
    beq BootExit
    cli

;; The clip must come off before the utility loads.
;; Also: BOOT3 (D1541)
WaitForClip:
    lda Via1PortB
    and #Serial::CLOCK_IN | Serial::DATA_IN
    bne WaitForClip

    ; One name, "*", which any file matches, then the loader's code after its name is scanned.
    inc SecondStreamEnd
    inc CommandLength
    lda #'*'
    sta CommandBuffer
    jmp Commands::LoadUtility::AfterName
.endif
.endproc
.endscope
.scope Commands continued

; The utility loader, the `&` command.

;; Loads a utility from the disk and runs it, as the `&` command: it never returns. The command's first name is looked
;; up, and opened as a user file (type 3; the listing's comment says 5). Then each record, a load address, a count, that
;; many bytes and a checksum byte, is stored, and the first record's address is jumped to, with the file count in
;; <SecondStreamEnd> as the command left it for the utility.
;;
;; The older builds' boot loader (before -05, and the 1540's) enters the routine at `AfterName`, after the name
;; scan, with the name `*` set.
;; Errors: 39 = the name is not found, 50 = a record's checksum is wrong, 51 = the file ends within a record
;; Also: UTLODR (D1541)
.proc LoadUtility
    lda #SHIFTED_RETURN
    jsr ScanFor
.if LATE_PATCHES = 0

;; Where the boot loader joins, with the name `*` set.
;; Also: BOOT4 (D1541)
AfterName:
.endif
    ; One file name is wanted: <SecondStreamEnd> is kept on the stack, set to 1, and the directory is searched. The
    ; flag in <Work0> says the first record is next.
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

;; <SecondStreamEnd> back; the file's first block, from its entry, and opened as a user file.
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

;; The checksum, in <Work1>, cleared; the record's address into <Work2> and <Work3>, kept on the stack for the first
;; record (<Work0> flags it).
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

;; The byte count into <Work4>.
;; Also: UTLD20 (D1541)
ReadCount:
    jsr GetByte
    sta Work4
    jsr AddToChecksum

;; Each byte to the address, and into the checksum.
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

;; <Work4> down; after the last byte, the checksum byte is compared with the sum.
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

;; Not the file's end: the next record; at the end, a jump to the first record's address.
;; Also: UTLD50 (D1541)
CheckEnd:
    lda MoreBytes
    bne NextRecord
    pla
    sta Work3
    pla
    sta Work2
    jmp (Work2)

;; Gets the next byte of the file (<GetInternalByte>); if it was past the file's last, error 51, with the block's track
;; and sector.
;; Out: A = the byte
;; Errors: 51 = the record overran the file
;; Also: GTABYT (D1541)
.proc GetByte
    jsr GetInternalByte
    lda MoreBytes
    bne Return
    jsr Files::GetBufferBlock
    lda #ERROR_RECORD_OVERFLOW
    jsr Errors::Abort

;; The byte.
;; Also: GTABYE (D1541)
Return:
    lda DataByte
    rts
.endproc

;; Adds a byte to the checksum, with the carry added back in.
;; In: A = the byte
;; Out: A = <Work1> = the new sum
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
