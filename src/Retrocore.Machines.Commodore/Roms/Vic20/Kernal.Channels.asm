; retrocore: style=strict
; COMMODORE VIC-20 KERNAL: THE CHANNELS, FILES, LOAD, SAVE AND THE CLOCK ($F174-$F7AE)
;
; The messages; CHRIN, GETIN and CHROUT, which pass each character to the device in use; CHKIN, CHKOUT, CLRCHN and
; CLALL, which pick the devices; OPEN and CLOSE with the table of open files; LOAD and SAVE; the jiffy clock; and the
; errors. RS-232's OPEN sits among them.

; RS-232: the constants of its OPEN and CLOSE (the rest of RS-232 is in Kernal.Rs232.asm).
.scope Rs232 continued

;; How many bytes of the file name OPEN takes as RS-232's settings: <Control>, <Command> and the two bytes after them.
PARAMETER_BYTES = 4

;; What RS-232's OPEN and CLOSE return in A, with carry set: BASIC's I/O error check takes $F0 as a signal, not an
;; error, sets its own top of memory to X and Y and clears its variables (a CLR), since the buffers moved the top.
MEMORY_TOP_MOVED = $F0

.endscope

; The channels go on: the messages, the character routines, the devices' selection, OPEN and CLOSE.
.scope Channels continued

; Characters and the messages.

;; Bit 7, set on a message's last character.
MESSAGE_END = $80

; The file table and the secondary addresses.

;; The most files open at once: the size of <FileNumbers>, <FileDevices> and <FileSecondaryAddresses>.
OPEN_FILES_LIMIT = 10

;; Added to every secondary address OPEN stores: for the serial bus, the command that names a channel for its data,
;; the channel being the low nibble, as <Serial::SendSecondary> and <Serial::SendTalkSecondary> send it. A secondary
;; address of $FF, none, stays $FF.
SECONDARY_DATA = $60

;; The channel's bits of a secondary address: 0 to 15.
SECONDARY_CHANNEL = $0F

;; The serial bus's command that opens a channel with a file name, ORed with the channel.
SECONDARY_OPEN = $F0

;; The serial bus's command that closes a channel, ORed with the channel.
SECONDARY_CLOSE = $E0

;; The secondary address the serial bus's LOAD uses: channel 0, from which a disk drive reads a program.
SECONDARY_LOAD = SECONDARY_DATA | 0

;; The secondary address the serial bus's SAVE uses: channel 1, to which a disk drive writes a program.
SECONDARY_SAVE = SECONDARY_DATA | 1

;; A tape file opened with secondary address 0, for reading, as OPEN stores it; any other is for writing.
SECONDARY_TAPE_READ = SECONDARY_DATA | 0

;; A tape SAVE's secondary address, bit 0: the program is saved as a fixed one (<TAPE_PROGRAM_FIXED>), which loads
;; where it was saved from.
SECONDARY_TAPE_FIXED = 1

;; A tape file's secondary address, bit 1: an end-of-tape header (<TAPE_END_OF_TAPE>) is written after it.
SECONDARY_TAPE_END = 2

; The rest.

;; <StopKeyRow> with STOP down: bit 0 low, and no other key of its column.
STOP_KEY_DOWN = $FE

;; The opcode of BIT zero page, which skips a 1-byte instruction after it the same way.
OPCODE_BIT_ZERO_PAGE = $24

;; The kernal's messages, one table: the code picks one by its offset from here, in Y, for <PrintControlMessage>, and
;; each one's last character has bit 7 set (<MESSAGE_END>). The first is the start of the error message, I/O ERROR #.
;; Also: MS1 (KV20)
Messages:
    .byte CARRIAGE_RETURN, "I/O ERROR ", '#' | MESSAGE_END

;; SEARCHING, before the tape or the serial bus looks for a file.
;; Also: MS5 (KV20)
SearchingMessage:
    .byte CARRIAGE_RETURN, "SEARCHING", ' ' | MESSAGE_END

;; FOR, between SEARCHING and the file name.
;; Also: MS6 (KV20)
ForMessage:
    .byte "FOR", ' ' | MESSAGE_END

;; PRESS PLAY ON TAPE, the tape's prompt for reading.
;; Also: MS7 (KV20)
PressPlayMessage:
    .byte CARRIAGE_RETURN, "PRESS PLAY ON TAP", 'E' | MESSAGE_END

;; PRESS RECORD & PLAY ON TAPE, the tape's prompt for writing.
;; Also: MS8 (KV20)
PressRecordMessage:
    .byte "PRESS RECORD & PLAY ON TAP", 'E' | MESSAGE_END

;; LOADING, before a program is read.
;; Also: MS10 (KV20)
LoadingMessage:
    .byte CARRIAGE_RETURN, "LOADIN", 'G' | MESSAGE_END

;; SAVING, before the file name, when a program is written.
;; Also: MS11 (KV20)
SavingMessage:
    .byte CARRIAGE_RETURN, "SAVING", ' ' | MESSAGE_END

;; VERIFYING, before a program is compared.
;; Also: MS21 (KV20)
VerifyingMessage:
    .byte CARRIAGE_RETURN, "VERIFYIN", 'G' | MESSAGE_END

;; FOUND, before the name of a tape header found.
;; Also: MS17 (KV20)
FoundMessage:
    .byte CARRIAGE_RETURN, "FOUND", ' ' | MESSAGE_END

;; OK, once the tape's key is down.
;; Also: MS18 (KV20)
OkMessage:
    .byte CARRIAGE_RETURN, "OK", CARRIAGE_RETURN | MESSAGE_END

;; Prints the message at offset Y in <Messages>, through <KernalCharacterOut>, if <MessageMode>'s bit 7 lets the
;; kernal's control messages through (SEARCHING, LOADING and the like).
;; In: Y = the message's offset from <Messages>
;; Out: carry = clear, Y = the offset past the message, if it was printed
;; Keeps: X
;; Entry:
;;   Always = prints the message whatever <MessageMode> says (the tape's prompts and the error message come here)
;; Also: SPMSG (KV20, MTV)
.proc PrintControlMessage
    bit MessageMode
    bpl Done

;; Prints the message at offset Y whatever <MessageMode> says, a character at a time to the one with bit 7 set.
;; Also: MSG (KV20)
Always:
    lda Messages,y
    php
    and #<~MESSAGE_END
    jsr KernalCharacterOut
    iny
    plp
    bpl Always

;; Carry clear.
;; Also: MSG10 (KV20)
Done:
    clc
    rts
.endproc

;; <GetInputVector>'s default, GETIN: a character from the input device, without waiting for one.
;;
;; From the keyboard it is the keyboard buffer's first key, or 0 when the buffer is empty; from RS-232, the input
;; buffer's next byte, or 0 when it is empty. Every other device is read as <CharacterIn> reads it, which waits.
;; In: InputDevice = the device
;; Out: A = the character, or 0 for none, carry = clear (but see <CharacterIn> for the tape)
;; Entry:
;;   FromRs232 = RS-232's next byte, or 0, with Y kept (<CharacterIn> comes here too)
;; Also: NGETIN (KV20)
.proc GetInput
    lda InputDevice
    bne NotKeyboard

    ; The keyboard: A = 0 if its buffer is empty; otherwise its first key, with interrupts off while the rest move up.
    lda KeyboardBufferCount
    beq CharacterIn::Done
    sei
    jmp Editor::TakeKey

;; Not the keyboard: RS-232 here, the other devices through <CharacterIn>.
;; Also: GN10 (KV20)
NotKeyboard:
    cmp #DEVICE_RS232
    bne CharacterIn::NotKeyboard

;; RS-232's next byte, or 0 when the input buffer is empty, with Y kept in <SavedX> meanwhile; carry clear.
;; Also: GN232 (KV20)
FromRs232:
    sty SavedX
    jsr Rs232::CharacterIn
    ldy SavedX
    clc
    rts
.endproc

;; <CharacterInVector>'s default, CHRIN: the next character from the input device, waiting for it.
;;
;; From the keyboard, the first call waits, with the cursor blinking, while a line is typed and RETURN pressed; each
;; call then returns the next character of that line as the screen shows it, from where the cursor was, and RETURN
;; at its end. From the screen, the logical line is read the same way from the cursor's column, with nothing typed.
;; From the tape, it is the buffer's next byte, the file's next block being read when the buffer is used up; the 0
;; after the file's last character sets the end-of-file bit in <IoStatus>. From RS-232, the next byte that isn't 0.
;; From the serial bus, the byte <Serial::ReceiveByte> brings, or RETURN once <IoStatus> is not 0: after the last
;; byte, or an error.
;; In: InputDevice = the device
;; Out: A = the character, carry = clear
;; Errors: carry = set, A = 0, from the tape when STOP is pressed while a block is wanted
;; Keeps: X
;; Entry:
;;   NotKeyboard = any device but the keyboard, by its number in A (<GetInput> comes here for all but the keyboard
;;     and RS-232)
;;   NextTapeByte = the tape buffer's next byte, reading the next block when the buffer is used up
;;   Done = carry clear (<GetInput> comes here with an empty keyboard buffer, A = 0)
;; Also: NBASIN (KV20)
.proc CharacterIn
    lda InputDevice
    bne NotKeyboard

    ; The keyboard: the line starts where the cursor is.
    lda Editor::Column
    sta Editor::InputColumn
    lda Editor::Row
    sta Editor::InputRow
    jmp Editor::Input::NextCharacter

;; Any device but the keyboard, by its number in A: the screen reads the logical line from the cursor's column to its
;; last column (<GetInput> comes here for all but the keyboard and RS-232).
;; Also: BN10 (KV20)
NotKeyboard:
    cmp #DEVICE_SCREEN
    bne NotScreen
    sta Editor::InputFromScreen
    lda Editor::LineLength
    sta Editor::LineEnd
    jmp Editor::Input::NextCharacter

;; The serial bus (carry set by the compare with 3), RS-232, or the tape, which reads a character and looks at the
;; byte after it, with X kept in <SavedX>.
;; Also: BN20 (KV20)
NotScreen:
    bcs FromSerial
    cmp #DEVICE_RS232
    beq FromRs232
    stx SavedX
    jsr NextTapeByte
    bcs TapeReturn
    pha
    jsr NextTapeByte
    bcs TapeError
    bne TapeCharacter

    ; The byte after it is 0: this character is the file's last.
    lda #STATUS_END_OF_FILE
    jsr ReadStatus::SetStatus

;; Puts back the byte looked at, for the next call, and returns the character with X restored; carry clear.
;; Also: JTG35 (KV20)
TapeCharacter:
    dec Tape::BufferIndex
    ldx SavedX
    pla
    rts

;; STOP while looking at the next byte: the character is dropped, and A = the 0 that came back.
;; Also: JTG36 (KV20)
TapeError:
    tax
    pla
    txa

;; Returns carry set, with X restored.
;; Also: JTG37 (KV20)
TapeReturn:
    ldx SavedX
    rts

;; The tape buffer's next byte. When the buffer is used up, the file's next block is read into it and the index starts
;; again past the block's type byte; carry set and A = 0 if STOP gives that up.
;; Also: JTGET (KV20)
NextTapeByte:
    jsr Tape::NextBufferByte
    bne FromBuffer
    jsr Tape::ReadHeader
    bcs Return
    lda #0
    sta Tape::BufferIndex
    beq NextTapeByte

;; A = the byte at Y, <Tape::BufferIndex>, with zero set if it is 0; carry clear.
;; Also: JTG10 (KV20)
FromBuffer:
    lda (TapeBuffer),y
    clc
    rts

;; The serial bus: once <IoStatus> is not 0 (the last byte has come, with EOI, or there was an error), A = RETURN, and
;; nothing more is asked for.
;; Also: BN30 (KV20)
FromSerial:
    lda IoStatus
    beq ReceiveByte
    lda #CARRIAGE_RETURN

;; Carry clear (<GetInput> comes here with an empty keyboard buffer, A = 0).
;; Also: BN31 (KV20)
Done:
    clc

;; Returns.
;; Also: BN32 (KV20)
Return:
    rts

;; On to <Serial::ReceiveByte>, which returns the byte.
;; Also: BN35 (KV20)
ReceiveByte:
    jmp Serial::ReceiveByte

;; RS-232: waits for a byte that isn't 0, since 0 is what an empty input buffer gives (so a real 0 is passed over).
;; Also: BN50 (KV20)
FromRs232:
    jsr GetInput::FromRs232
    bcs Rs232Done                   ; never taken: GetInput::FromRs232 clears carry
    cmp #0
    beq FromRs232
    clc

;; Returns.
;; Also: BN52 (KV20)
Rs232Done:
    rts
.endproc

;; <CharacterOutVector>'s default, CHROUT: sends A to the output device.
;;
;; The screen prints it or carries out its control code (<ScreenOut>); the serial bus buffers it, sending the byte
;; before it (<Serial::SendByte>); the tape puts it in the tape buffer, writing the buffer as a block when it is full;
;; RS-232 puts it in the output buffer, starting the sender if it is idle (<Rs232::CharacterOut>). A is kept too,
;; except after STOP on the tape and when RS-232's sender is started, which loads A.
;; In: A = the character, OutputDevice = the device
;; Out: carry = clear
;; Errors: carry = set, A = 0, from the tape when STOP is pressed while a full buffer is written
;; Keeps: X, Y
;; Entry:
;;   ToTape = into the tape buffer, whatever the device (<Close> comes here for the end of file's 0)
;; Also: NBSOUT (KV20)
.proc CharacterOut
    pha
    lda OutputDevice
    cmp #DEVICE_SCREEN
    bne NotScreen
    pla
    jmp ScreenOut

;; Not the screen: a serial device (carry set by the compare with 3) gets it through <Serial::SendByte>.
;; Also: BO10 (KV20)
NotScreen:
    bcc NotSerial
    pla
    jmp Serial::SendByte

;; RS-232, or else the tape (device 1; nothing selects the keyboard for output).
;; Also: BO20 (KV20)
NotSerial:
    cmp #DEVICE_RS232
    beq ToRs232
    pla

;; Into the tape buffer, with A, X and Y saved; the character waits in <Temporary1> (<Close> comes here for the end of
;; file's 0).
;; Also: CASOUT (KV20)
ToTape:
    sta Temporary1
    pha
    txa
    pha
    tya
    pha
    jsr Tape::NextBufferByte
    bne Store

    ; The buffer is full: it is written as a block, and the next one starts with its type byte.
    jsr Tape::WriteBuffer
    bcs Restore
    lda #TAPE_DATA
    ldy #0
    sta (TapeBuffer),y
    iny
    sty Tape::BufferIndex

;; Stores the character at Y, <Tape::BufferIndex>; carry clear.
;; Also: JTP10 (KV20)
Store:
    lda Temporary1
    sta (TapeBuffer),y
    clc

;; Restores A, X and Y; after STOP, A = 0 with carry set.
;; Also: RSTOR (KV20)
Restore:
    pla
    tay
    pla
    tax
    pla
    bcc Done
    lda #0

;; Returns.
;; Also: RSTOR1 (KV20)
Done:
    rts

;; RS-232: <Rs232::CharacterOut>, with X kept in <SavedX> and Y in <Temporary1>; carry clear.
;; Also: BO50 (KV20)
ToRs232:
    pla
    stx SavedX
    sty Temporary1
    jsr Rs232::CharacterOut
    ldx SavedX
    ldy Temporary1
    clc
    rts
.endproc

;; <SelectInputVector>'s default, CHKIN: makes logical file X the input for CHRIN and GETIN, and the current file.
;;
;; A serial device is told to talk, with the file's secondary address; RS-232 waits as its handshake needs
;; (<Rs232::SelectInput>); the keyboard and the screen need nothing; a tape file must have been opened for reading.
;; In: X = the logical file
;; Out: InputDevice = the file's device, carry = clear
;; Errors: carry = set, A = 3 if the file is not open, 6 for a tape file being written, 5 if a serial device does not
;;   answer, the channels reset by <Error>
;; Also: NCHKIN (KV20)
.proc SelectInput
    jsr FindFile
    beq Found
    jmp Error::FileNotOpen

;; The file is open: it becomes the current file. The keyboard and the screen need nothing more.
;; Also: JX310 (KV20)
Found:
    jsr FetchFile
    lda Device
    beq SetDevice
    cmp #DEVICE_SCREEN
    beq SetDevice
    bcs SerialDevice
    cmp #DEVICE_RS232
    bne OnTape
    jmp Rs232::SelectInput

;; The tape: the file must have been opened for reading, with secondary address 0.
;; Also: JX315 (KV20)
OnTape:
    ldx SecondaryAddress
    cpx #SECONDARY_TAPE_READ
    beq SetDevice
    jmp Error::NotInputFile

;; <InputDevice> = A, the device; carry clear.
;; Also: JX320 (KV20)
SetDevice:
    sta InputDevice
    clc
    rts

;; The serial bus: TALK, then the secondary address, which also turns the bus around, or with none just the
;; turnaround.
;; Also: JX330 (KV20)
SerialDevice:
    tax
    jsr Serial::Talk
    lda SecondaryAddress
    bpl SendSecondary
    jsr Serial::TurnAround
    jmp CheckPresent

;; The secondary address, through <Serial::SendTalkSecondary>.
;; Also: JX340 (KV20)
SendSecondary:
    jsr Serial::SendTalkSecondary

;; A = the device again: DEVICE NOT PRESENT if <IoStatus>'s bit 7 says nothing answered.
;; Also: JX350 (KV20)
CheckPresent:
    txa
    bit IoStatus
    bpl SetDevice
    jmp Error::DeviceNotPresent
.endproc

;; <SelectOutputVector>'s default, CHKOUT: makes logical file X the output for CHROUT, and the current file.
;;
;; A serial device is told to listen, with the file's secondary address; RS-232 waits as its handshake needs
;; (<Rs232::SelectOutput>); the screen needs nothing; the keyboard can't be written, and a tape file must have been
;; opened for writing.
;; In: X = the logical file
;; Out: OutputDevice = the file's device, carry = clear
;; Errors: carry = set, A = 3 if the file is not open, 7 for the keyboard or a tape file being read, 5 if a serial
;;   device does not answer, the channels reset by <Error>
;; Also: NCKOUT (KV20)
.proc SelectOutput
    jsr FindFile
    beq Found
    jmp Error::FileNotOpen

;; The file is open: it becomes the current file. The keyboard can't be written.
;; Also: CK5 (KV20)
Found:
    jsr FetchFile
    lda Device
    bne NotKeyboard

;; NOT OUTPUT FILE: the keyboard, or a tape file opened for reading.
;; Also: CK20 (KV20)
NotOutputFile:
    jmp Error::NotOutputFile

;; The screen needs nothing; RS-232 goes to <Rs232::SelectOutput>.
;; Also: CK10 (KV20)
NotKeyboard:
    cmp #DEVICE_SCREEN
    beq SetDevice
    bcs SerialDevice
    cmp #DEVICE_RS232
    bne OnTape
    jmp Rs232::SelectOutput

;; The tape: the file must have been opened for writing, with a secondary address other than 0.
;; Also: CK15 (KV20)
OnTape:
    ldx SecondaryAddress
    cpx #SECONDARY_TAPE_READ
    beq NotOutputFile

;; <OutputDevice> = A, the device; carry clear.
;; Also: CK30 (KV20)
SetDevice:
    sta OutputDevice
    clc
    rts

;; The serial bus: LISTEN, then the secondary address, or with none ATN released.
;;
;; The BNE after <Serial::ReleaseAtn> counts on <Via1PortA>'s other bits not all being 0, which the joystick's lines,
;; high while it is idle, see to; if they were all 0, A = 0 would be sent to the device as a byte.
;; Also: CK40 (KV20)
SerialDevice:
    tax
    jsr Serial::Listen
    lda SecondaryAddress
    bpl SendSecondary
    jsr Serial::ReleaseAtn
    bne CheckPresent

;; The secondary address, through <Serial::SendSecondary>, which releases ATN after it.
;; Also: CK50 (KV20)
SendSecondary:
    jsr Serial::SendSecondary

;; A = the device again: DEVICE NOT PRESENT if <IoStatus>'s bit 7 says nothing answered.
;; Also: CK60 (KV20)
CheckPresent:
    txa
    bit IoStatus
    bpl SetDevice
    jmp Error::DeviceNotPresent
.endproc

;; <CloseVector>'s default, CLOSE: closes logical file A and takes it out of the file tables.
;;
;; A tape file being written gets its end-of-file 0 and its last block, and an end-of-tape header after it when it
;; was opened with secondary address 2; a serial file gets its close command (<CloseSerialFile>); RS-232 turns its
;; NMIs off and gives its buffers' pages back to the top of memory, returning as <Rs232::Open> does: carry set, A =
;; <Rs232::MEMORY_TOP_MOVED>, X and Y = the new top. A file that isn't open is no error.
;; In: A = the logical file
;; Out: carry = clear (set for RS-232, as above)
;; Errors: carry = set, A = 0, after STOP while a tape file's last block is written; the file stays in the tables
;; Entry:
;;   LastBlockWritten = a tape file's last block is written (<CloseTapePatch> comes back here, carry set after STOP)
;;   Remove = removes table entry A, moving the last entry into its place (RS-232 comes here)
;; Also: NCLOSE (KV20)
.proc Close
    jsr FindFile::FileInA
    beq Found
    clc
    rts

;; The file is open: it becomes the current file, and its table index goes on the stack. Then by the device: the
;; keyboard and the screen need nothing.
;; Also: JX050 (KV20)
Found:
    jsr FetchFile
    txa
    pha
    lda Device
    beq RemoveEntry
    cmp #DEVICE_SCREEN
    beq RemoveEntry
    bcs SerialDevice
    cmp #DEVICE_RS232
    bne OnTape

    ; RS-232: out of the tables at once; its NMIs off, RTS and DTR raised, and the send line idle.
    pla
    jsr Remove
    lda #VIA_INTERRUPTS_ALL & <~VIA_INTERRUPT_CA1  ; all off but CA1's, the RESTORE key's
    sta Via1InterruptEnable
    lda #Rs232::REQUEST_TO_SEND | Rs232::DATA_TERMINAL_READY
    sta Via1PortB
    lda #Rs232::SEND_LINE_LOW_CONTROL | Rs232::SEND_LINE_HIGH
    sta Via1PeripheralControl

    ; Each buffer's page goes back: the top of memory, in X and Y, a page higher for each.
    jsr Startup::MemoryTop::Read
    lda Rs232::InputBuffer+1
    beq InputFreed
    iny

;; The input buffer's page is back, if it had one; now the output buffer's.
;; Also: CLS010 (KV20)
InputFreed:
    lda Rs232::OutputBuffer+1
    beq Deallocate
    iny

;; Both buffers' pointers cleared, and the top of memory set to X and Y through <Rs232::Open::LowerMemoryTop>.
;; Also: CLS020 (KV20)
Deallocate:
    lda #0
    sta Rs232::InputBuffer+1
    sta Rs232::OutputBuffer+1
    jmp Rs232::Open::LowerMemoryTop

;; The tape: a file being read needs nothing; one being written gets its end-of-file 0 in the buffer, and
;; <CloseTapePatch> writes its last block.
;; Also: JX115 (KV20)
OnTape:
    lda SecondaryAddress
    and #SECONDARY_CHANNEL
    beq RemoveEntry
    jsr Tape::BufferAddress
    lda #0
    jsr CharacterOut::ToTape
    jmp CloseTapePatch

;; The tape file's last block is written (<CloseTapePatch> comes back here): after STOP, carry is set and <Close>
;; returns at once. A file opened with secondary address 2 gets an end-of-tape header after it. This local and
;; <Close::Return> are 901486-06's, where its patch returns; no listing names them.
LastBlockWritten:
    bcs Return
    lda SecondaryAddress
    cmp #SECONDARY_DATA | SECONDARY_TAPE_END
    bne RemoveEntry
    lda #TAPE_END_OF_TAPE
    jsr Tape::WriteHeader
    jmp RemoveEntry

;; The serial bus: <CloseSerialFile>.
;; Also: JX120 (KV20)
SerialDevice:
    jsr CloseSerialFile

;; Takes the file's table index back off the stack.
;; Also: JX150 (KV20)
RemoveEntry:
    pla

;; Removes table entry A: <OpenFileCount> goes down one, and unless the entry was the last, the last one moves into its
;; place (RS-232 comes here).
;; Also: JXRMV (KV20)
Remove:
    tax
    dec OpenFileCount
    cpx OpenFileCount
    beq Done
    ldy OpenFileCount
    lda FileNumbers,y
    sta FileNumbers,x
    lda FileDevices,y
    sta FileDevices,x
    lda FileSecondaryAddresses,y
    sta FileSecondaryAddresses,x

;; Carry clear.
;; Also: JX170 (KV20)
Done:
    clc

;; Returns with carry as it is: <Close::LastBlockWritten> comes here with it set, after STOP at a tape file's last
;; block.
Return:
    rts
.endproc

;; Clears <IoStatus> and looks logical file X up in <FileNumbers>, from the last entry down.
;; In: X = the logical file
;; Out: zero = set if found, X = its index, or $FF if not found, A = the logical file
;; Keeps: Y
;; Entry:
;;   FileInA = looks up logical file A, leaving <IoStatus> as it is (<Close> enters here)
;; Also: LOOKUP (KV20)
.proc FindFile
    lda #0
    sta IoStatus
    txa

;; Looks up logical file A, leaving <IoStatus> as it is (<Close> enters here).
;; Also: JLTLK (KV20)
FileInA:
    ldx OpenFileCount

;; Each entry, from the last: zero is clear when X goes below 0.
;; Also: JX600 (KV20)
Next:
    dex
    bmi FetchFile::Done
    cmp FileNumbers,x
    bne Next
    rts
.endproc

;; Makes table entry X the current file: <LogicalFile>, <Device> and <SecondaryAddress> = the entry's.
;; In: X = the entry's index
;; Out: A = the secondary address
;; Keeps: X, Y
;; Entry:
;;   Done = returns (<FindFile> ends here when the file is not found)
;; Also: JZ100 (KV20)
.proc FetchFile
    lda FileNumbers,x
    sta LogicalFile
    lda FileDevices,x
    sta Device
    lda FileSecondaryAddresses,x
    sta SecondaryAddress

;; Returns (<FindFile> ends here when the file is not found).
;; Also: JZ101 (KV20)
Done:
    rts
.endproc

;; <CloseAllFilesVector>'s default, CLALL: forgets every open file, sending no device its close command, and falls
;; into <ResetChannels>.
;; Out: OpenFileCount = 0, OutputDevice = 3, InputDevice = 0, A = 0, X = 3
;; Keeps: Y
;; Also: NCLALL (KV20)
.proc CloseAll
    lda #0
    sta OpenFileCount
    ; Falls into ResetChannels.
.endproc

;; <ResetChannelsVector>'s default, CLRCHN: puts input back on the keyboard and output on the screen, first sending
;; UNLISTEN to a serial device that was the output and UNTALK to one that was the input.
;; Out: OutputDevice = 3, the screen, InputDevice = 0, the keyboard, A = 0, X = 3
;; Keeps: Y
;; Also: NCLRCH (KV20)
.proc ResetChannels
    ldx #DEVICE_SCREEN
    cpx OutputDevice
    bcs CheckInput
    jsr Serial::Unlisten

;; The input device: UNTALK if it is on the serial bus.
;; Also: JX750 (KV20)
CheckInput:
    cpx InputDevice
    bcs Defaults
    jsr Serial::Untalk

;; <OutputDevice> = 3, the screen, and <InputDevice> = 0, the keyboard.
;; Also: CLALL2 (KV20)
Defaults:
    stx OutputDevice
    lda #DEVICE_KEYBOARD
    sta InputDevice
    rts
.endproc

;; <OpenVector>'s default, OPEN: opens the current file, as SETLFS and SETNAM set it, and adds it to the file tables.
;;
;; The secondary address is stored with <SECONDARY_DATA> added. A serial file with a secondary address and a name gets
;; its open command (<OpenSerialFile>); RS-232 is set up by <Rs232::Open>; the tape asks for PLAY and finds the file,
;; or with a secondary address other than 0 asks for RECORD and writes a data file's header; the keyboard and the
;; screen need nothing.
;;
;; The file stays in the tables when its device then fails, and STOP while a tape header is written is not reported.
;; On the tape, an end-of-tape header ends the search as STOP does, carry set with no error and A = 5; and since
;; <Tape::FindHeader> loads <VerifyFlag> back into A, STOP during the search reports FILE NOT FOUND when the last
;; LOAD was a VERIFY.
;; In: LogicalFile = the file's number, Device = its device, SecondaryAddress = 0-15, or $FF for none,
;;   FileName = the name, FileNameLength = its length
;; Out: carry = clear (set for RS-232: see <Rs232::Open>)
;; Errors: carry = set, A = 6 for logical file 0, 2 if the file is open, 1 if ten are, 9 if <TapeBuffer> has been
;;   taken away, 4 if the tape has no such file, 5 if a serial device does not answer, 0 after STOP on the tape
;; Also: NOPEN (KV20)
.proc Open
    ldx LogicalFile
    bne NotKeyboard
    jmp Error::NotInputFile

;; Not logical file 0, which is refused as NOT INPUT FILE: FILE OPEN if this one is open already.
;; Also: OP98 (KV20)
NotKeyboard:
    jsr FindFile
    bne NotOpen
    jmp Error::FileOpen

;; Not open yet: TOO MANY FILES if <OPEN_FILES_LIMIT> are.
;; Also: OP100 (KV20)
NotOpen:
    ldx OpenFileCount
    cpx #OPEN_FILES_LIMIT
    bcc AddEntry
    jmp Error::TooManyFiles

;; The new table entry, with <SECONDARY_DATA> added to the secondary address. Then by the device: the keyboard and
;; the screen are done, and a serial file gets <OpenSerialFile>.
;; Also: OP110 (KV20)
AddEntry:
    inc OpenFileCount
    lda LogicalFile
    sta FileNumbers,x
    lda SecondaryAddress
    ora #SECONDARY_DATA
    sta SecondaryAddress
    sta FileSecondaryAddresses,x
    lda Device
    sta FileDevices,x
    beq Success
    cmp #DEVICE_SCREEN
    beq Success
    bcc OnTape
    jsr OpenSerialFile
    bcc Success                     ; always taken: OpenSerialFile returns carry clear

;; RS-232, through <Rs232::Open>, or the tape.
;; Also: OP150 (KV20)
OnTape:
    cmp #DEVICE_RS232
    bne NotRs232
    jmp Rs232::Open

;; The tape: ILLEGAL DEVICE NUMBER if <TapeBuffer> has been taken away (moved below $0200).
;; Also: OP152 (KV20)
NotRs232:
    jsr Tape::BufferAddress
    bcs Buffer
    jmp Error::IllegalDevice

;; Secondary address 0 reads: PRESS PLAY ON TAPE, SEARCHING, and the file by its name, or the next header with none.
;; Also: OP155 (KV20)
Buffer:
    lda SecondaryAddress
    and #SECONDARY_CHANNEL
    bne Write
    jsr Tape::WaitForPlay
    bcs Done
    jsr PrintSearching
    lda FileNameLength
    beq AnyFile
    jsr Tape::FindFile
    bcc SetBuffer
    beq Done

;; FILE NOT FOUND.
;; Also: OP160 (KV20)
NotFound:
    jmp Error::FileNotFound

;; No name: the next header, of any kind.
;; Also: OP170 (KV20)
AnyFile:
    jsr Tape::FindHeader
    beq Done
    bcc SetBuffer
    bcs NotFound

;; Any other secondary address writes: PRESS RECORD & PLAY ON TAPE, then a data file's header with the name.
;; Also: OP200 (KV20)
Write:
    jsr Tape::WaitForRecord
    bcs Done
    lda #TAPE_DATA_HEADER
    jsr Tape::WriteHeader

;; The buffer index: at the buffer's end for a file being read, so that the first CHRIN reads a block; after the
;; block's type byte, <TAPE_DATA>, for one being written.
;; Also: OP171 (KV20)
SetBuffer:
    lda #TAPE_BUFFER_SIZE-1
    ldy SecondaryAddress
    cpy #SECONDARY_TAPE_READ
    beq SetIndex
    ldy #0
    lda #TAPE_DATA
    sta (TapeBuffer),y
    tya

;; <Tape::BufferIndex> = A.
;; Also: OP172 (KV20)
SetIndex:
    sta Tape::BufferIndex

;; Carry clear.
;; Also: OP175 (KV20)
Success:
    clc

;; Returns.
;; Also: OP180 (KV20)
Done:
    rts
.endproc

;; Sends a serial file's open command: LISTEN, the secondary address with <SECONDARY_OPEN>, the file name, UNLISTEN.
;; A file with no secondary address ($FF) or no name gets nothing.
;;
;; If the device does not answer, it drops its own return address and goes to <Error::DeviceNotPresent>, so its
;; caller (<Open>, <Load> or <Save>) returns with the error. The length is checked again at
;; <OpenSerialFile::SendName>, where it can't be 0.
;; In: Device = the device, SecondaryAddress = with <SECONDARY_DATA> added, FileName = the name,
;;   FileNameLength = its length
;; Out: carry = clear
;; Errors: carry = set, A = 5, DEVICE NOT PRESENT, returned from the caller's caller
;; Keeps: X
;; Also: OPENI (KV20)
.proc OpenSerialFile
    lda SecondaryAddress
    bmi Done
    ldy FileNameLength
    beq Done

    ; LISTEN and the open command.
    lda Device
    jsr Serial::Listen
    lda SecondaryAddress
    ora #SECONDARY_OPEN
    jsr Serial::SendSecondary
    lda IoStatus
    bpl SendName

    ; No device answered: the error, returned from the caller.
    pla
    pla
    jmp Error::DeviceNotPresent

;; The name, if it has one.
;; Also: OP35 (KV20)
SendName:
    lda FileNameLength
    beq Unlisten
    ldy #0

;; Each character, through <Serial::SendByte>.
;; Also: OP40 (KV20)
NextCharacter:
    lda (FileName),y
    jsr Serial::SendByte
    iny
    cpy FileNameLength
    bne NextCharacter

;; UNLISTEN, which sends the last character with EOI.
;; Also: OP45 (KV20)
Unlisten:
    jsr Serial::Unlisten

;; Carry clear.
;; Also: OP50 (KV20)
Done:
    clc
    rts
.endproc

.endscope

; RS-232: its OPEN, which sits among the channels.
.scope Rs232 continued

;; Opens RS-232 on the user port, device 2, for <Channels::Open>: RTS and DTR raised, the send line idle, the file
;; name's first four bytes as the settings, the bit time for the baud rate, and a 256-byte buffer each way, taken from
;; the top of memory.
;;
;; The name's bytes go to <Control> (the baud rate, word length and stop bits) and <Command> (parity, duplex and
;; handshake), as a 6551's registers have them, and to the two bytes after them, $0295-$0296: the listing's M51AJB, a
;; non-standard bit time, which this code never reads. Baud rate 0 is not handled: its branch lands on the next
;; instruction, so it takes the two bytes before <BaudRates>, and 12 to 15 read past the table's end.
;;
;; With x-line handshaking it checks DSR, but on <Via2PortB>, the keyboard's columns, rather than on <Via1PortB>,
;; where the user port's DSR is; *Mapping the VIC* calls the test erroneous and says it always passes. Were it to
;; fail, OPEN would return through <SendError> with carry clear and no buffers.
;; In: FileName = the settings, FileNameLength = how many, up to 4
;; Out: carry = set, A = <MEMORY_TOP_MOVED>, X = the new top of memory's low byte, Y = its high byte
;; Entry:
;;   LowerMemoryTop = sets the top of memory to X and Y and returns carry set with A = <MEMORY_TOP_MOVED>, which BASIC
;;     takes as the signal to use the new top (<Channels::Close> comes here to raise it again)
;; Also: OPN232 (KV20)
.proc Open
    lda #REQUEST_TO_SEND | DATA_TERMINAL_READY
    sta Via1DirectionB
    sta Via1PortB
    lda #SEND_LINE_LOW_CONTROL | SEND_LINE_HIGH
    sta Via1PeripheralControl
    ldy #0
    sty Status

;; Up to four bytes of the file name, into <Control> and on.
;; Also: OPN020 (KV20)
CopyParameters:
    cpy FileNameLength
    beq Bits
    lda (FileName),y
    sta Control,y
    iny
    cpy #PARAMETER_BYTES
    bne CopyParameters

;; <WordBits> = <CountWordBits>'s count: the word's bits plus one.
;; Also: OPN025 (KV20)
Bits:
    jsr CountWordBits
    stx WordBits
    lda Control
    and #CONTROL_BAUD_RATE
    bne BaudTime                    ; lands on BaudTime either way: rate 0 has no case of its own

;; <BitTime> = twice the rate's <BaudRates> entry plus twice <START_BIT_LATENCY>: a whole bit's time, in clock
;; cycles.
;; Also: OPN010 (KV20)
BaudTime:
    asl a
    tax
    lda BaudRates-2,x
    asl a
    tay
    lda BaudRates-1,x
    rol a
    pha
    tya
    adc #START_BIT_LATENCY+START_BIT_LATENCY
    sta BitTime
    pla
    adc #0
    sta BitTime+1

    ; With x-line handshaking (Command's bit 0), DSR must be on: tested on the wrong VIA, as above.
    lda Command
    lsr a
    bcc ResetBuffers
    lda Via2PortB
    asl a
    bcs ResetBuffers
    jmp SendError

;; Both buffers empty. The input buffer, if it has no page yet, gets the one below the top of memory, which
;; <Startup::MemoryTop::Read> leaves in X and Y.
;; Also: OPN050 (KV20)
ResetBuffers:
    lda InputEnd
    sta InputStart
    lda OutputEnd
    sta OutputStart
    jsr Startup::MemoryTop::Read
    lda InputBuffer+1
    bne TakeOutputPage
    dey
    sty InputBuffer+1
    stx InputBuffer

;; The output buffer, if it has no page yet, gets the one below that.
;; Also: OPN060 (KV20)
TakeOutputPage:
    lda OutputBuffer+1
    bne LowerMemoryTop
    dey
    sty OutputBuffer+1
    stx OutputBuffer

;; Sets the top of memory to X and Y, and returns carry set with A = <MEMORY_TOP_MOVED>, which BASIC takes as the
;; signal to use the new top (<Channels::Close> comes here to raise it again).
;; Also: MEMTCF (KV20)
LowerMemoryTop:
    sec
    lda #MEMORY_TOP_MOVED
    jmp Startup::MemoryTop::SetTop
.endproc

.endscope

; The channels go on: LOAD and SAVE.
.scope Channels continued

;; The jump table's LOAD: <LoadAddress> = X and Y, where a program loads when the secondary address is 0, then on
;; through <LoadVector>, falling into <LoadThroughVector>.
;; In: A = 0 to load, otherwise to verify, X = the load address's low byte, Y = its high byte
;; Also: LOADSP (KV20)
.proc LoadToAddress
    stx LoadAddress
    sty LoadAddress+1
    ; Falls into LoadThroughVector.
.endproc

;; Goes on through <LoadVector>: to <Load>, unless a program has pointed the vector at its own code.
;; Commodore's listing names it LOAD (KV20), the name of <KernalLoad>.
.proc LoadThroughVector
    jmp (LoadVector)
.endproc

;; <LoadVector>'s default: LOAD or VERIFY of the current file from the tape or the serial bus, into memory at
;; <LoadAddress> or at the file's own address.
;;
;; With secondary address 0 a program loads at <LoadAddress>, otherwise at the address it was saved from; on the tape,
;; a fixed program (<TAPE_PROGRAM_FIXED>) always does. VERIFY compares instead of storing, and a byte that differs sets
;; <STATUS_SECOND_PASS_ERROR> in <IoStatus>. The serial bus needs a name: it reads the file on channel 0
;; (<SECONDARY_LOAD>), its address first, then the bytes until EOI, asking again for a byte that times out, and STOP
;; ends it. The tape finds the first program whose name starts with the one given, or with no name the next program,
;; and reads it as one block; read errors are left in <IoStatus>.
;;
;; On the tape, an end-of-tape header ends the search as STOP does, carry set with no error and A = 5; and since
;; <Tape::FindHeader> loads <VerifyFlag> back into A, STOP during a VERIFY's search reports FILE NOT FOUND.
;; In: A = 0 to load, otherwise to verify, Device = the device, SecondaryAddress = 0 to load at <LoadAddress>,
;;   LoadAddress = where to load, FileName = the name, FileNameLength = its length
;; Out: carry = clear, X = the low byte of the address after the last byte loaded, Y = its high byte
;; Errors: carry = set, A = 9 for the keyboard, the screen or RS-232, or if <TapeBuffer> has been taken away, 8 for the
;;   serial bus with no name, 4 if the file is not found, 5 if a serial device does not answer, 16 if the tape's header
;;   could not be read, 0 after STOP
;; Also: NLOAD (KV20)
.proc Load
    sta VerifyFlag
    lda #0
    sta IoStatus
    lda Device
    bne NotKeyboard

;; ILLEGAL DEVICE NUMBER: the keyboard or the screen.
;; Also: LD10 (KV20)
BadDevice:
    jmp Error::IllegalDevice

;; Not the keyboard: the screen can't load either, the tape and RS-232 go on at <Load::OnTape>, and the serial bus
;; needs a name.
;; Also: LD20 (KV20)
NotKeyboard:
    cmp #DEVICE_SCREEN
    beq BadDevice
    bcc OnTape
    ldy FileNameLength
    bne SerialDevice
    jmp Error::MissingFileName

;; The serial bus: SEARCHING, the file opened on channel 0, TALK, and the file's first two bytes, its address; a read
;; timeout on the first is FILE NOT FOUND. <LoadAddressPatch> then picks where the bytes go, and prints LOADING.
;; Also: LD25 (KV20)
SerialDevice:
    jsr LoadSearchPatch
    lda #SECONDARY_LOAD
    sta SecondaryAddress
    jsr OpenSerialFile
    lda Device
    jsr Serial::Talk
    lda SecondaryAddress
    jsr Serial::SendTalkSecondary
    jsr Serial::ReceiveByte
    sta EndAddress
    lda IoStatus
    lsr a
    lsr a
    bcs NotFound                    ; the read timeout bit
    jsr Serial::ReceiveByte
    sta EndAddressHigh
    jsr LoadAddressPatch

;; Each byte until EOI: the read timeout bit cleared, and STOP checked, which closes the file.
;; Also: LD40 (KV20)
NextByte:
    lda #<~STATUS_READ_TIMEOUT
    and IoStatus
    sta IoStatus
    jsr KernalTestStopKey
    bne Receive
    jmp Save::Break

;; A byte; one that timed out is asked for again. VERIFY compares it with memory, and sets
;; <STATUS_SECOND_PASS_ERROR> in <IoStatus> when it differs.
;; Also: LD45 (KV20)
Receive:
    jsr Serial::ReceiveByte
    tax
    lda IoStatus
    lsr a
    lsr a
    bcs NextByte                    ; the read timeout bit
    txa
    ldy VerifyFlag
    beq Store
    ldy #0
    cmp (EndAddress),y
    beq Advance
    lda #STATUS_SECOND_PASS_ERROR
    jsr ReadStatus::SetStatus
    .byte OPCODE_BIT                ; skips the store

;; Stores the byte (Y = 0, from <VerifyFlag>).
;; Also: LD50 (KV20)
Store:
    sta (EndAddress),y

;; On to the next address.
;; Also: LD60 (KV20)
Advance:
    inc EndAddress
    bne CheckEnd
    inc EndAddressHigh

;; Until the byte that came with EOI: then UNTALK, and the file's close command.
;; Also: LD64 (KV20)
CheckEnd:
    bit IoStatus
    bvc NextByte
    jsr Serial::Untalk
    jsr CloseSerialFile
    bcc Success                     ; always taken: CloseSerialFile returns carry clear

;; FILE NOT FOUND.
;; Also: LD90 (KV20)
NotFound:
    jmp Error::FileNotFound

;; RS-232 can't load: <Rs232::NoLoadOrSave> is ILLEGAL DEVICE NUMBER.
;; Also: LD100 (KV20)
OnTape:
    cmp #DEVICE_RS232
    bne NotRs232
    jmp Rs232::NoLoadOrSave

;; The tape: ILLEGAL DEVICE NUMBER if <TapeBuffer> has been taken away.
;; Also: LD102 (KV20)
NotRs232:
    jsr Tape::BufferAddress
    bcs Buffer
    jmp Error::IllegalDevice

;; PRESS PLAY ON TAPE, then SEARCHING.
;; Also: LD104 (KV20)
Buffer:
    jsr Tape::WaitForPlay
    bcs Done
    jsr PrintSearching

;; The next header, by the name if there is one: the end of the tape and STOP return (as above), and any other
;; failure is FILE NOT FOUND.
;; Also: LD112 (KV20)
Search:
    lda FileNameLength
    beq AnyHeader
    jsr Tape::FindFile
    bcc HeaderFound
    beq Done
    bcs NotFound

;; No name: the next header of any kind.
;; Also: LD150 (KV20)
AnyHeader:
    jsr Tape::FindHeader
    beq Done
    bcs NotFound

;; A header, of type X: if it could not be read, carry set with A = <STATUS_SECOND_PASS_ERROR>; a data file's is
;; passed over.
;; Also: LD170 (KV20)
HeaderFound:
    lda IoStatus
    and #STATUS_SECOND_PASS_ERROR
    sec
    bne Done
    cpx #TAPE_PROGRAM
    beq Relocatable
    cpx #TAPE_PROGRAM_FIXED
    bne Search

;; A fixed program, or a secondary address other than 0: <LoadAddress> = the address it was saved from, the header's
;; bytes 1 and 2.
;; Also: LD177 (KV20)
Fixed:
    ldy #1
    lda (TapeBuffer),y
    sta LoadAddress
    iny
    lda (TapeBuffer),y
    sta LoadAddress+1
    bcs SetEnd                      ; always taken: carry is set from the compare that matched

;; A relocatable program loads at <LoadAddress>, unless the secondary address asks for its own.
;; Also: LD178 (KV20)
Relocatable:
    lda SecondaryAddress
    bne Fixed

;; <EndAddress> = <LoadAddress> plus the program's length, the header's end address less its start; then LOADING or
;; VERIFYING, and the program, as one block, through <Tape::ReadBlock>.
;; Also: LD179 (KV20)
SetEnd:
    ldy #3
    lda (TapeBuffer),y
    ldy #1
    sbc (TapeBuffer),y
    tax
    ldy #4
    lda (TapeBuffer),y
    ldy #2
    sbc (TapeBuffer),y
    tay
    clc
    txa
    adc LoadAddress
    sta EndAddress
    tya
    adc LoadAddress+1
    sta EndAddressHigh
    lda LoadAddress
    sta Tape::LoadAddress
    lda LoadAddress+1
    sta Tape::LoadAddressHigh
    jsr PrintLoading
    jsr Tape::ReadBlock
    .byte OPCODE_BIT_ZERO_PAGE      ; skips the CLC: carry as ReadBlock left it, set after STOP

;; Carry clear; X and Y = the address after the last byte.
;; Also: LD180 (KV20)
Success:
    clc
    ldx EndAddress
    ldy EndAddressHigh

;; Returns.
;; Also: LD190 (KV20)
Done:
    rts
.endproc

;; Prints SEARCHING, and FOR and the file name when there is one, if <MessageMode> lets the control messages through.
;; In: FileName = the name, FileNameLength = its length
;; Keeps: X
;; Entry:
;;   PrintName = prints the file name, if there is one, whatever <MessageMode> says (<PrintSaving> comes here)
;; Also: LUKING (KV20)
.proc PrintSearching
    lda MessageMode
    bpl Done
    ldy #SearchingMessage-Messages
    jsr PrintControlMessage::Always
    lda FileNameLength
    beq Done
    ldy #ForMessage-Messages
    jsr PrintControlMessage::Always

;; Prints the file name, if there is one, whatever <MessageMode> says (<PrintSaving> comes here).
;; Also: OUTFN (KV20)
PrintName:
    ldy FileNameLength
    beq Done
    ldy #0

;; Each character, through <KernalCharacterOut>.
;; Also: LD110 (KV20)
NextCharacter:
    lda (FileName),y
    jsr KernalCharacterOut
    iny
    cpy FileNameLength
    bne NextCharacter

;; Returns.
;; Also: LD115 (KV20)
Done:
    rts
.endproc

;; Prints LOADING, or VERIFYING when <VerifyFlag> is set, if <MessageMode> lets the control messages through.
;; In: VerifyFlag = 0 for LOAD
;; Out: carry = clear
;; Keeps: X
;; Also: LODING (KV20)
.proc PrintLoading
    ldy #LoadingMessage-Messages
    lda VerifyFlag
    beq Print
    ldy #VerifyingMessage-Messages

;; Prints the message in Y through <PrintControlMessage>.
;; Also: LD410 (KV20)
Print:
    jmp PrintControlMessage
.endproc

;; The jump table's SAVE: the memory from the address the zero-page pointer at A holds up to X and Y. It sets
;; <Tape::LoadAddress> and <EndAddress>, and falls into <SaveThroughVector>.
;; In: A = the zero-page address of a pointer to the first byte, X = the low byte of the address after the last byte,
;;   Y = its high byte
;; Also: SAVESP (KV20)
.proc SaveRange
    stx EndAddress
    sty EndAddressHigh
    tax
    lda $00,x                       ; the pointer's low byte
    sta Tape::LoadAddress
    lda $01,x                       ; and its high byte
    sta Tape::LoadAddressHigh
    ; Falls into SaveThroughVector.
.endproc

;; Goes on through <SaveVector>: to <Save>, unless a program has pointed the vector at its own code.
;; Commodore's listing names it SAVE (KV20), the name of <KernalSave>.
.proc SaveThroughVector
    jmp (SaveVector)
.endproc

;; <SaveVector>'s default: saves the memory from <Tape::LoadAddress> up to <EndAddress> as the current file, to the
;; tape or the serial bus.
;;
;; The serial bus needs a name: the file is opened on channel 1 (<SECONDARY_SAVE>) and gets the start address, then
;; the bytes; STOP closes it. The tape is <SaveToTape>'s.
;; In: Tape::LoadAddress = the first byte, EndAddress = the address after the last, Device = the device,
;;   SecondaryAddress = for the tape, <SECONDARY_TAPE_FIXED> and <SECONDARY_TAPE_END>, FileName = the name,
;;   FileNameLength = its length
;; Out: carry = clear
;; Errors: carry = set, A = 9 for the keyboard, the screen or RS-232, or if <TapeBuffer> has been taken away, 8 for the
;;   serial bus with no name, 5 if a serial device does not answer, 0 after STOP
;; Entry:
;;   Break = STOP: closes the serial file and returns A = 0, carry set (<Load> comes here too). MTV and V20PRG spell
;;     BREAK, but not for this code.
;; Also: NSAVE (KV20)
.proc Save
    lda Device
    bne NotKeyboard

;; ILLEGAL DEVICE NUMBER: the keyboard or the screen.
;; Also: SV10 (KV20)
BadDevice:
    jmp Error::IllegalDevice

;; Not the keyboard: the screen can't be saved to either, the tape and RS-232 are <SaveToTape>'s, and the serial bus
;; uses channel 1 and needs a name.
;; Also: SV20 (KV20)
NotKeyboard:
    cmp #DEVICE_SCREEN
    beq BadDevice
    bcc SaveToTape
    lda #SECONDARY_SAVE
    sta SecondaryAddress
    ldy FileNameLength
    bne SerialDevice
    jmp Error::MissingFileName

;; The serial bus: the file opened, SAVING, LISTEN on channel 1, and the start address's two bytes first.
;; Also: SV25 (KV20)
SerialDevice:
    jsr OpenSerialFile
    jsr PrintSaving
    lda Device
    jsr Serial::Listen
    lda SecondaryAddress
    jsr Serial::SendSecondary
    ldy #0
    jsr Tape::ResetAddress
    lda StartAddress
    jsr Serial::SendByte
    lda StartAddressHigh
    jsr Serial::SendByte

;; Each byte up to <EndAddress>, with STOP checked after each.
;; Also: SV30 (KV20)
NextByte:
    jsr Tape::CompareAddresses
    bcs Unlisten
    lda (StartAddress),y
    jsr Serial::SendByte
    jsr KernalTestStopKey
    bne Advance

;; STOP: closes the file; A = 0, carry set (<Load> comes here too). MTV and V20PRG spell BREAK, but not for this code.
;; Also: BREAK (KV20)
Break:
    jsr CloseSerialFile
    lda #0
    sec
    rts

;; On to the next address (only a wrap to $0000 falls through).
;; Also: SV40 (KV20)
Advance:
    jsr Tape::NextAddress
    bne NextByte

;; UNLISTEN, which sends the last byte with EOI, then falls into <CloseSerialFile>.
;; Also: SV50 (KV20)
Unlisten:
    jsr Serial::Unlisten
    ; Falls into CloseSerialFile.
.endproc

;; Sends a serial file's close command: LISTEN, the secondary address with <SECONDARY_CLOSE>, UNLISTEN. A file with no
;; secondary address gets nothing.
;; In: Device = the device, SecondaryAddress = with <SECONDARY_DATA> added
;; Out: carry = clear
;; Keeps: X, Y
;; Also: CLSEI (KV20)
.proc CloseSerialFile
    bit SecondaryAddress
    bmi Done
    lda Device
    jsr Serial::Listen

    ; The close command: the bit that tells an open command from a close cleared (it is already clear in a secondary
    ; address OPEN stored), then the close command's bits.
    lda SecondaryAddress
    and #<~(SECONDARY_OPEN ^ SECONDARY_CLOSE)
    ora #SECONDARY_CLOSE
    jsr Serial::SendSecondary
    jsr Serial::Unlisten

;; Carry clear.
;; Also: CLSEI2 (KV20)
Done:
    clc
    rts
.endproc

;; <Save>'s tape half: RS-232 can't save; RECORD and PLAY, SAVING, a program header, the program as a block, and an
;; end-of-tape header after it when the secondary address has <SECONDARY_TAPE_END>.
;;
;; The header is a relocatable program's (<TAPE_PROGRAM>), or a fixed one's (<TAPE_PROGRAM_FIXED>) when the secondary
;; address has <SECONDARY_TAPE_FIXED>.
;; In: A = the device, 1 or 2, SecondaryAddress = the secondary address as SETLFS set it
;; Out: carry = clear
;; Errors: carry = set, A = 9 for RS-232, or if <TapeBuffer> has been taken away, 0 after STOP
;; Entry:
;;   Done = returns (<PrintSaving> comes here with the messages off)
;; Also: SV100 (KV20)
.proc SaveToTape
    cmp #DEVICE_RS232
    bne NotRs232
    jmp Rs232::NoLoadOrSave

;; The tape: ILLEGAL DEVICE NUMBER if <TapeBuffer> has been taken away; then PRESS RECORD & PLAY ON TAPE, SAVING, and
;; the header's type in X.
;; Also: SV102 (KV20)
NotRs232:
    jsr Tape::BufferAddress
    bcc Save::BadDevice
    jsr Tape::WaitForRecord
    bcs Done
    jsr PrintSaving
    ldx #TAPE_PROGRAM_FIXED
    lda SecondaryAddress
    and #SECONDARY_TAPE_FIXED
    bne WriteHeader
    ldx #TAPE_PROGRAM

;; The header, then the program; then the end-of-tape header if it is asked for.
;; Also: SV106 (KV20)
WriteHeader:
    txa
    jsr Tape::WriteHeader
    bcs Done
    jsr Tape::WriteBlock
    bcs Done
    lda SecondaryAddress
    and #SECONDARY_TAPE_END
    beq Success
    lda #TAPE_END_OF_TAPE
    jsr Tape::WriteHeader
    .byte OPCODE_BIT_ZERO_PAGE      ; skips the CLC: carry as WriteHeader left it

;; Carry clear.
;; Also: SV110 (KV20)
Success:
    clc

;; Returns (<PrintSaving> comes here with the messages off).
;; Also: SV115 (KV20)
Done:
    rts
.endproc

;; Prints SAVING and the file name, if <MessageMode> lets the control messages through.
;; In: FileName = the name, FileNameLength = its length
;; Keeps: X
;; Also: SAVING (KV20, MTV)
.proc PrintSaving
    lda MessageMode
    bpl SaveToTape::Done
    ldy #SavingMessage-Messages
    jsr PrintControlMessage::Always
    jmp PrintSearching::PrintName
.endproc

.endscope

;; The jiffy clock, <JiffyClock>: three bytes that the IRQ counts up 60 times a second, a jiffy each time, which BASIC
;; reads as TI and TI$.
.scope Clock

;; A day's jiffies, 24 hours of 60 a second: 5,184,000.
JIFFIES_PER_DAY = 24 * 60 * 60 * 60

;; The count <Tick> sets the clock back to 0 at: one past <JIFFIES_PER_DAY>, so for one jiffy the clock reads a whole
;; day before it starts again.
CLOCK_WRAP = JIFFIES_PER_DAY + 1

;; Counts a jiffy on <JiffyClock>, setting the clock back to 0 at <CLOCK_WRAP>, and copies VIA 2's port A into
;; <StopKeyRow> for the STOP test: the keyboard's rows for column 3, which the keyboard scan leaves selected.
;;
;; The IRQ calls it every jiffy, and <Tape::Run> while the tape has the IRQ.
;; Commodore's listing names it UDTIM (KV20), the name of <KernalTickClock>.
;; Out: A = <StopKeyRow>, X = 0
;; Keeps: Y
.proc Tick
    ldx #0
    inc JiffyClock+2
    bne CheckWrap
    inc JiffyClock+1
    bne CheckWrap
    inc JiffyClock

;; At <CLOCK_WRAP>, back to 0: the clock, less the count, without a borrow.
;; Also: UD30 (KV20)
CheckWrap:
    sec
    lda JiffyClock+2
    sbc #<CLOCK_WRAP
    lda JiffyClock+1
    sbc #<(CLOCK_WRAP >> 8)
    lda JiffyClock
    sbc #<(CLOCK_WRAP >> 16)
    bcc ReadStopRow
    stx JiffyClock
    stx JiffyClock+1
    stx JiffyClock+2

;; Reads <Via2PortA> until two reads agree, and stores it in <StopKeyRow>.
;;
;; This is 901486-06's code. Commodore's listing jumps from here to its STOP-key patch in the patch area, STPTCH
;; (with its label ITSSET), which told STOP from SHIFT with STOP; 901486-06 has no such patch and stores the row here
;; itself, and holds <Channels::CloseTapePatch> at STPTCH's address, $E4CF.
;; Also: UD60 (KV20)
ReadStopRow:
    lda Via2PortA
    cmp Via2PortA
    bne ReadStopRow
    sta StopKeyRow
    rts
.endproc

;; Reads the jiffy clock into A, X and Y, lowest byte first, with interrupts off so the IRQ can't count between the
;; bytes; it falls into <Clock::Set>, which stores the same bytes back and turns interrupts on.
;;
;; So it returns with interrupts on, even if they were off when it was called.
;; Commodore's listing names it RDTIM (KV20), the name of <KernalReadClock>.
;; Out: A = the lowest byte, X = the middle byte, Y = the highest, interrupt = clear
.proc Read
    sei
    lda JiffyClock+2
    ldx JiffyClock+1
    ldy JiffyClock
    ; Falls into Set.
.endproc

;; Sets the jiffy clock from A, X and Y, lowest byte first, with interrupts off meanwhile; it returns with them on.
;; Commodore's listing names it SETTIM (KV20), the name of <KernalSetClock>.
;; In: A = the lowest byte, X = the middle byte, Y = the highest
;; Out: interrupt = clear
;; Keeps: A, X, Y
.proc Set
    sei
    sta JiffyClock+2
    stx JiffyClock+1
    sty JiffyClock
    cli
    rts
.endproc

.endscope

; The channels go on: the STOP test and the errors.
.scope Channels continued

;; <TestStopKeyVector>'s default, STOP: whether STOP was down at the last jiffy, from <StopKeyRow>. If it was, the
;; channels are reset (<KernalResetChannels>) and the keyboard buffer emptied.
;; Out: zero = set if STOP is down, A = <StopKeyRow> if it isn't, 0 if it is
;; Keeps: Y
;; Also: NSTOP (KV20)
.proc TestStopKey
    lda StopKeyRow
    cmp #STOP_KEY_DOWN
    bne Done

    ; STOP: the channels reset, which leaves A = 0, and the keyboard buffer emptied with it.
    php
    jsr KernalResetChannels
    sta KeyboardBufferCount
    plp

;; Returns.
;; Also: STOP2 (KV20)
Done:
    rts
.endproc

;; The kernal's errors: each entry loads its number (one of the KERNAL_ERROR_* constants) and skips the entries after
;; it with <OPCODE_BIT>, so all of them reach the same end: the channels reset (<KernalResetChannels>), I/O ERROR #
;; and the number printed if <MessageMode>'s bit 6 lets the error messages through, and A = the number with carry set.
;;
;; A routine jumps to its error, so the error returns to that routine's caller.
;; Out: A = the error number, carry = set
;; Entry:
;;   TooManyFiles = error 1, TOO MANY FILES, at the start
;;   FileOpen = error 2, FILE OPEN
;;   FileNotOpen = error 3, FILE NOT OPEN
;;   FileNotFound = error 4, FILE NOT FOUND
;;   DeviceNotPresent = error 5, DEVICE NOT PRESENT
;;   NotInputFile = error 6, NOT INPUT FILE
;;   NotOutputFile = error 7, NOT OUTPUT FILE
;;   MissingFileName = error 8, MISSING FILE NAME
;;   IllegalDevice = error 9, ILLEGAL DEVICE NUMBER, which every error goes on from
.proc Error
;; TOO MANY FILES, error 1: OPEN with ten files open. <Error> itself starts here.
;; Also: ERROR1 (KV20)
TooManyFiles:
    lda #KERNAL_ERROR_TOO_MANY_FILES
    .byte OPCODE_BIT                ; skips the next LDA

;; FILE OPEN, error 2: OPEN of a logical file that is open already.
;; Also: ERROR2 (KV20)
FileOpen:
    lda #KERNAL_ERROR_FILE_OPEN
    .byte OPCODE_BIT                ; skips the next LDA

;; FILE NOT OPEN, error 3: CHKIN or CHKOUT of a logical file that isn't open.
;; Also: ERROR3 (KV20)
FileNotOpen:
    lda #KERNAL_ERROR_FILE_NOT_OPEN
    .byte OPCODE_BIT                ; skips the next LDA

;; FILE NOT FOUND, error 4: LOAD or OPEN found no such file.
;; Also: ERROR4 (KV20)
FileNotFound:
    lda #KERNAL_ERROR_FILE_NOT_FOUND
    .byte OPCODE_BIT                ; skips the next LDA

;; DEVICE NOT PRESENT, error 5: nothing answered on the serial bus.
;; Also: ERROR5 (KV20)
DeviceNotPresent:
    lda #KERNAL_ERROR_DEVICE_NOT_PRESENT
    .byte OPCODE_BIT                ; skips the next LDA

;; NOT INPUT FILE, error 6: CHKIN of a tape file being written, or OPEN of logical file 0.
;; Also: ERROR6 (KV20)
NotInputFile:
    lda #KERNAL_ERROR_NOT_INPUT_FILE
    .byte OPCODE_BIT                ; skips the next LDA

;; NOT OUTPUT FILE, error 7: CHKOUT of the keyboard or of a tape file being read.
;; Also: ERROR7 (KV20)
NotOutputFile:
    lda #KERNAL_ERROR_NOT_OUTPUT_FILE
    .byte OPCODE_BIT                ; skips the next LDA

;; MISSING FILE NAME, error 8: LOAD or SAVE on the serial bus with no name.
;; Also: ERROR8 (KV20)
MissingFileName:
    lda #KERNAL_ERROR_MISSING_FILE_NAME
    .byte OPCODE_BIT                ; skips the next LDA

;; ILLEGAL DEVICE NUMBER, error 9: LOAD or SAVE on the keyboard, the screen or RS-232, or the tape with its buffer taken
;; away. Every error goes on from here: the channels reset, I/O ERROR # and the number printed if the error messages
;; are on, and A = the number with carry set.
;; Also: ERROR9 (KV20)
IllegalDevice:
    lda #KERNAL_ERROR_ILLEGAL_DEVICE

    ; Every error: the number kept, and the channels reset.
    pha
    jsr KernalResetChannels

    ; I/O ERROR # and the number, as a digit, if <MessageMode>'s bit 6 lets the error messages through.
    ldy #Messages-Messages
    bit MessageMode
    bvc Return
    jsr PrintControlMessage::Always
    pla
    pha
    ora #'0'
    jsr KernalCharacterOut

;; A = the error number, carry set.
;; Also: EREXIT (KV20)
Return:
    pla
    sec
    rts
.endproc

.endscope
