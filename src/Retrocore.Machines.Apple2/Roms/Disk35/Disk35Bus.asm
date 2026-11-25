; retrocore: style=strict
;; THE CARD'S FIRMWARE: THE SMARTPORT BUS, AND THE DELAYS
;;
;; The card's second port is a SmartPort bus, which devices such as the UniDisk 3.5 share. Its lines are the IWM's:
;; phases 1 and 3 high together enable the bus, phase 0 is the host's request (REQ), phases 0 and 2 high together
;; reset it, and the drive's sense line is the device's acknowledgement (ACK). A packet is sent and received through
;; the IWM in its slow mode ($17), as bytes with the high bit set: sync bytes and a start byte ($C3), a header
;; (destination, source, type, aux type, status, the odd-byte count and the 7-byte group count), the odd bytes
;; after a byte of their high bits, each group of seven after a byte of theirs, a checksum in two bytes, and an end
;; byte ($C8). <Bus::PassCommand> passes a host's command for a bus unit to its device, and <Bus::Initialize> gives
;; the devices their unit numbers. The millisecond delays every part of the firmware uses are here too.

;; One entry of <Bus::CommandTable>: how a command's packets go.
;; Parameters:
;;   sends = 1 when the host's data goes to the device after the command
;;   returns = 1 when the device's reply has data for the host
;;   parameters = the command packet's parameter count
.macro BusCommand sends, returns, parameters
    .byte sends << 7 | returns << 6 | parameters
.endmacro

;; The SmartPort bus's packets and the commands passed through it.
.scope Bus

; The packets.

;; The IWM's mode for the bus: latched, asynchronous, no motor timer, slow (4-microsecond) bits.
IWM_MODE_SLOW = $17

;; A packet's type: a command.
TYPE_COMMAND = $80

;; A packet's type: data.
TYPE_DATA = $82

;; The byte that starts a packet, after the sync bytes (PBEGIN).
PACKET_BEGIN = $C3

;; The byte that ends a packet (PEND).
PACKET_END = $C8

;; The bits a checksum byte always has set: each of its two bytes carries four of the checksum's bits.
CHECKSUM_FILL = $AA

;; The bytes of a packet's header after the start byte.
HEADER_LENGTH = 7

;; The command packet's bytes: the command, the parameter count and seven parameters.
COMMAND_PACKET_LENGTH = 9

;; The command packet's bits in <Bus::CommandTable>: host data goes to the device.
SENDS_DATA = $80

;; The command packet's bits in <Bus::CommandTable>: the reply has data for the host.
RETURNS_DATA = $40

;; The command packet's bits in <Bus::CommandTable>: the parameter count.
PARAMETER_COUNT = $0F

; <DiskErrors> after a packet.

;; No packet came.
NO_PACKET = $80

;; The packet did not end with <Bus::PACKET_END>.
NO_END = $81

;; The device did not take the packet's end.
NOT_TAKEN = $82

;; The packet's checksum was wrong.
BAD_CHECKSUM = $83

;; The device did not answer the request to send.
NOT_READY = $84

;; The packet's group count had its high bit set, which cannot happen: the count is stored without it.
BAD_GROUPS = $8A

; SmartPort's error for a bus that failed.

;; The bus did not work: the device did not answer.
;; Also: BUSERR (UNKN)
ERROR_BUS = $06

;; The most host data a command other than WRITEBLOCK may send, in pages.
MOST_DATA_PAGES = $05

;; The highest unit number.
LAST_UNIT = $04

;; The most bus devices <Bus::Initialize> counts.
MOST_DEVICES = $02

; Unused bytes, up to <Bus::DivideBySeven> at $F500.
    .res $F500 - *

;; Divides a 16-bit count by 7: the 7-byte groups of a packet and the bytes left over.
;; In: WorkPointer = the count, below 7 * 256
;; Out: Groups = the quotient, OddBytes = the remainder, X = 0; WorkPointer's low byte is shifted out
;; Keeps: Y
.proc DivideBySeven
    stz Groups
    ldx #8
    lda WorkPointer + 1
Bit:
    asl WorkPointer
    rol a
    cmp #7
    bcc Shift
    sbc #7
Shift:
    rol Groups
    dex
    bne Bit
    sta OddBytes
    rts
.endproc

;; Receives a packet from the bus into the buffer at BufferPointer: waits for the device's ACK, raises REQ, reads
;; the header into PacketHeader's last seven bytes (so the status lands in BusResult, and the counts in Groups and
;; OddBytes), then the data, and lowers REQ once ACK falls.
;; Out: carry = clear, DiskErrors = 0; or carry = set with DiskErrors = <Bus::NO_PACKET>, <Bus::NO_END> or
;;      <Bus::BAD_CHECKSUM>
.proc Receive
    ldx #HEADER_LENGTH
ClearHeader:
    stz PacketHeader,x
    dex
    bne ClearHeader
    stz HeaderChecksum
    stz DiskErrors
    jsr Bus::Enable

    ; Clears the stack page's free bytes, from the stack pointer down to $01E1.
    tsx
ClearStack:
    stz StackPage,x
    dex
    cpx #$E1
    bcs ClearStack

    ; Waits for ACK, about 256 * 100 * 205 polls; X counts from 0, as HeaderChecksum is.
    bit Iwm::LoadLatch
    ldx HeaderChecksum
Wait:
    lda #$64
WaitMore:
    ldy #$CD
Poll:
    bit Iwm::ReadMode
    bmi Acknowledged
    dey
    bne Poll
    dec a
    bne WaitMore
    dex
    bne Wait
    bra Check                       ; zero: no packet

    ; REQ, then up to 256 reads for the start byte.
Acknowledged:
    lda Iwm::Phase0On
    ldy #0
FindStart:
    lda Iwm::DataLatch
    dey
Check:
    beq NoPacket
    cmp #PACKET_BEGIN
    bne FindStart

    ; The header, last byte first, without the high bits, into the checksum as sent.
    ldy #HEADER_LENGTH
HeaderByte:
    lda Iwm::DataLatch
    bpl HeaderByte
    and #$7F
    sta PacketHeader,y
    ora #$80
    eor HeaderChecksum
    sta HeaderChecksum
    dey
    bne HeaderByte
    lda Groups
    bmi BadGroups
    sta GroupHighBits

    ; The odd bytes, after their high bits, then each group of seven after its own; GroupHighBits counts the groups.
    ldx OddBytes
    beq NextGroup
HighBits:
    lda Iwm::DataLatch
    bpl HighBits
    asl a
    sta PacketHighBits
DataByte:
    lda Iwm::DataLatch
    bpl DataByte
    asl PacketHighBits
    bcs Store
    and #$7F
Store:
    sta (BufferPointer),y
    eor HeaderChecksum
    sta HeaderChecksum
    iny
    bne Counted
    inc BufferPointer + 1
Counted:
    dex
    bne DataByte
NextGroup:
    ldx #7
    dec GroupHighBits
    bpl HighBits

    ; The checksum, its even bits in the first byte and its odd bits in the second.
FirstSum:
    lda Iwm::DataLatch
    bpl FirstSum
    sta Scratch
SecondSum:
    lda Iwm::DataLatch
    bpl SecondSum
    sec
    rol a
    and Scratch
    eor HeaderChecksum
    bne BadChecksum

    ; The end byte; then REQ falls once ACK has.
End:
    lda Iwm::DataLatch
    bpl End
    cmp #PACKET_END
    bne NoEnd
    lda Iwm::LoadLatch
WaitRelease:
    lda Iwm::ReadMode
    bmi WaitRelease
    lda Iwm::Phase0Off
    clc
    rts

BadGroups:
    lda #BAD_GROUPS
    bra Failed
NoPacket:
    lda #NO_PACKET
    bra Failed
NoEnd:
    lda #NO_END
    bra Failed
BadChecksum:
    lda #BAD_CHECKSUM
Failed:
    sta DiskErrors
    sec
    rts
.endproc

;; Sends a packet to the bus from the buffer at BufferPointer, BusCount bytes long, to unit <Drive>, of
;; <PacketType>: enables the bus, waits for the device's ACK, raises REQ, writes the packet, and waits for ACK to
;; fall once it is out.
;; Out: carry = clear, DiskErrors = 0; or carry = set with DiskErrors = <Bus::NOT_READY> or <Bus::NOT_TAKEN>
.proc Send
    bit Iwm::ReadMode
    bit Iwm::DataLatch
    jsr Bus::PrepareHighBits
    jsr Bus::Enable

    ; Up to 250 polls for ACK.
    lda Iwm::SelectDrive1
    lda Iwm::MotorOn
    bit Iwm::LoadLatch
    ldy #$FA
WaitReady:
    lda Iwm::ReadMode
    bmi Ready
    dey
    bne WaitReady
    lda #NOT_READY
    jmp Fail

    ; REQ, then the sync bytes and the start byte.
Ready:
    lda Iwm::Phase0On
    ldy #PACKET_START_LENGTH - 1
    lda #$FF
    sta Iwm::WriteMode
StartByte:
    lda Bus::PacketStart,y
WaitStart:
    bit Iwm::DataLatch
    bpl WaitStart
    sta Iwm::LoadLatch
    dey
    bpl StartByte

    ; The header: the unit, the host (0), the type, aux type and status (0), and the counts.
    lda #0
    sta HeaderChecksum
    lda Drive
    ora #$80
    jsr Bus::SendChecked
    jsr Bus::SendZero
    lda PacketType
    jsr Bus::SendChecked
    jsr Bus::SendZero
    jsr Bus::SendZero
    lda OddBytes
    ora #$80
    jsr Bus::SendChecked
    lda Groups
    ora #$80
    jsr Bus::SendChecked

    ; The odd bytes, after their high bits.
    ldy #0
    ldx OddBytes
    beq NextGroup
    lda PacketHighBits
    jsr Bus::SendByte
OddByte:
    lda (BufferPointer),y
    jsr Bus::SendChecked
    iny
    dex
    bne OddByte

    ; Each group after its high bits, collecting the next group's (seven bytes on, through WorkPointer) as it goes.
NextGroup:
    dec Groups
    bmi Checksum
    lda GroupHighBits
    jsr Bus::SendByte
    lda #1
    sta GroupHighBits
    ldx #7
GroupByte:
    lda (BufferPointer),y
    jsr Bus::SendChecked
    lda (WorkPointer),y
    asl a
    rol GroupHighBits
    iny
    bne Counted
    inc BufferPointer + 1
    inc WorkPointer + 1
Counted:
    dex
    bne GroupByte
    beq NextGroup                   ; always

    ; The checksum's even bits, its odd bits, and the end byte.
Checksum:
    lda HeaderChecksum
    ora #CHECKSUM_FILL
    jsr Bus::SendByte
    lda HeaderChecksum
    lsr a
    ora #CHECKSUM_FILL
    jsr Bus::SendByte
    lda #PACKET_END
    jsr Bus::SendByte

    ; Until the IWM has written the last byte, then up to 250 polls for ACK to fall.
WaitEmpty:
    bit Iwm::DataLatch
    bvs WaitEmpty
    sta Iwm::LoadLatch
    ldy #$FA
WaitTaken:
    dey
    bne Poll
    lda #NOT_TAKEN
Fail:
    sec
    bra Done
Poll:
    lda Iwm::ReadMode
    bmi WaitTaken
    lda #0
    clc

    ; REQ falls, and the IWM goes back to reading.
Done:
    bit Iwm::Phase0Off
    bit Iwm::DataLatch
    sta DiskErrors
    rts
.endproc

;; The bytes of <Bus::PacketStart>.
PACKET_START_LENGTH = 6

;; Turns Groups and OddBytes back into a byte count: 7 * Groups + OddBytes.
;; Out: A = the count's low byte, Y = its high byte
;; Keeps: X
.proc ByteCount
    stz Scratch
    lda Groups
    asl a
    rol Scratch
    asl a
    rol Scratch
    asl a
    rol Scratch
    sec
    sbc Groups
    bcs Odd
    dec Scratch
Odd:
    clc
    adc OddBytes
    bcc Done
    inc Scratch
Done:
    ldy Scratch
    rts
.endproc

;; Sends a 0, as $80, and adds it to the packet's checksum.
;; Keeps: X, Y
.proc SendZero
    lda #$80
    ; Falls into SendChecked.
.endproc

;; Sends a byte with its high bit set, and adds the byte as given to the packet's checksum.
;; In: A = the byte
;; Keeps: X, Y
.proc SendChecked
    pha
    eor HeaderChecksum
    sta HeaderChecksum
    pla
    ora #$80
    ; Falls into SendByte.
.endproc

;; Sends a byte to the bus once the IWM can take it.
;; In: A = the byte
;; Keeps: A, X, Y
.proc SendByte
Wait:
    bit Iwm::DataLatch
    bpl Wait
    sta Iwm::LoadLatch
    rts
.endproc

;; Works out a packet's groups and odd bytes from BusCount, and the high bits <Bus::Send> sends first: those of the
;; first seven bytes in PacketHighBits (the odd bytes use the first of them) and those of the first group in
;; GroupHighBits. WorkPointer points seven bytes past BufferPointer, for the later groups' high bits.
.proc PrepareHighBits
    lda BusCount
    sta WorkPointer
    lda BusCount + 1
    sta WorkPointer + 1
    jsr Bus::DivideBySeven
    lda BufferPointer
    clc
    adc #7
    sta WorkPointer
    lda BufferPointer + 1
    adc #0
    sta WorkPointer + 1
    ldy #0
    jsr Bus::CollectHighBits
    lda GroupHighBits
    sta PacketHighBits
    ldy OddBytes
    jsr Bus::CollectHighBits
    rts
.endproc

;; Collects the high bits of seven bytes from BufferPointer + Y into GroupHighBits: bit 7 set, then the first
;; byte's bit in bit 6, through the seventh's in bit 0.
;; In: Y = the first byte's offset
;; Out: Y = past the seventh, X = 0
.proc CollectHighBits
    ldx #7
    lda #1
    sta GroupHighBits
Next:
    lda (BufferPointer),y
    asl a
    rol GroupHighBits
    iny
    dex
    bne Next
    rts
.endproc

;; Enables the bus: phases 1 and 3 high, the others low.
;; Keeps: X, Y
.proc Enable
    jsr Bus::Idle
    lda Iwm::Phase1On
    lda Iwm::Phase3On
    rts
.endproc

;; Resets the bus's devices: phases 0 and 2 high for 80 ms, then all low for 10 ms.
;; Out: A = 0
;; Keeps: X, Y
.proc ResetDevices
    jsr Bus::Idle
    lda Iwm::Phase0On
    lda Iwm::Phase2On
    lda #80
    jsr DelayMilliseconds
    jsr Bus::Idle
    lda #5
    ; Falls into DelayMillisecondPairs.
.endproc

.endscope

;; Waits twice A milliseconds (512 for A = 0).
;; In: A = the pairs of milliseconds
;; Out: A = 0
;; Keeps: X, Y
.proc DelayMillisecondPairs
    pha
    jsr DelayMilliseconds
    pla
    ; Falls into DelayMilliseconds.
.endproc

;; Waits A milliseconds (256 for A = 0).
;; In: A = the milliseconds
;; Out: A = 0
;; Keeps: X, Y
.proc DelayMilliseconds
Next:
    jsr DelayMillisecond
    dec a
    bne Next
    rts
.endproc

;; Waits about a millisecond: 203 turns of 10 cycles, at the card's 2 MHz.
;; Keeps: A, X, Y
.proc DelayMillisecond
    pha
    lda #$CB
Turn:
    dec a
    bne Pad
Pad:
    nop
    bne Turn
    pla
    rts
.endproc

; The bus, continued: its idle state, packets, retries and the commands passed to it.
.scope Bus continued

;; Lowers all four phase lines: the bus idle, REQ low.
;; Keeps: A, X, Y
.proc Idle
    bit Iwm::Phase0Off
    bit Iwm::Phase1Off
    bit Iwm::Phase2Off
    bit Iwm::Phase3Off
    rts
.endproc

;; A packet's sync bytes and start byte, sent from the last.
PacketStart:
    .byte PACKET_BEGIN, $FF, $FC, $F3, $CF, $3F
.assert * - PacketStart = PACKET_START_LENGTH, "Bus::Send sends PACKET_START_LENGTH bytes of PacketStart."

;; Builds the command packet for the host's command: the command, the parameter count from <Bus::CommandTable>, two
;; zeros, and the host's ParameterLow through Parameter5; then falls into <Bus::PointAtCommandPacket>.
.proc MakeCommandPacket
    lda #TYPE_COMMAND
    sta PacketType
    lda CardCommand
    and #$0F
    sta CommandPacket
    ldy CardState
    lda Bus::CommandTable,y
    and #PARAMETER_COUNT
    sta CommandPacket + 1
    stz CommandPacket + 2
    stz CommandPacket + 3
    ldx #6
Parameter:
    lda ParameterLow - 1,x
    sta CommandPacket + 3,x
    dex
    bne Parameter
    ; Falls into PointAtCommandPacket.
.endproc

;; Points BufferPointer at the command packet, and BusCount at its 9 bytes.
.proc PointAtCommandPacket
    lda #COMMAND_PACKET_LENGTH
    sta BusCount
    stz BusCount + 1
    lda #<CommandPacket
    sta BufferPointer
    stz BufferPointer + 1
    rts
.endproc

;; Sends a data packet; if the device does not take it, initializes the bus's devices again.
;; Out: carry = set if it failed
.proc SendData
    jsr Bus::SendWithRetries
    bcs Bus::Reinitialize
    rts
.endproc

;; Initializes the bus's devices again from the first bus unit, keeping <Drive>.
;; Out: carry = set
.proc Reinitialize
    lda Drive
    pha
    ldx FirstBusUnit
    lda #$80
    jsr Bus::Initialize
    pla
    sta Drive
    sec
    rts
.endproc

;; Sends the command packet: one try, then twice more up to 100 tries, with the devices initialized again and the
;; packet built again before each.
;; Out: carry = set if it failed
.proc SendCommand
    lda #1
    jsr Bus::SendWithTries
    bcc Done
    jsr Bus::Reinitialize
    jsr Bus::MakeCommandPacket
    lda #100
    jsr Bus::SendWithTries
    bcc Done
    jsr Bus::Reinitialize
    jsr Bus::MakeCommandPacket
    lda #100
    jsr Bus::SendWithTries
Done:
    rts
.endproc

;; Sends a packet with up to 32 tries, fewer for a long one.
;; Out: carry = set if it failed
.proc SendWithRetries
    lda #32
    ; Falls into SendWithTries.
.endproc

;; Sends a packet with up to A tries, halved for each 256 bytes of it, waiting 5 ms between tries of a short one.
;; In: A = the tries
;; Out: carry = set if it failed
.proc SendWithTries
    ldx BusCount + 1
    beq SetTries
Halve:
    lsr a
    dex
    bne Halve
SetTries:
    sta Retries
Try:
    jsr Bus::Send
    bcc Done
    dec Retries
    beq Done
    ldx BusCount + 1
    bne Try
    lda #5
    jsr DelayMilliseconds
    bra Try
Done:
    rts
.endproc

;; Receives a packet with up to 5 tries, 60 for FORMAT, a millisecond apart.
;; Out: carry = set if it failed, with A = DiskErrors
.proc ReceiveWithRetries
    lda #5
    sta Retries
    lda CardState
    cmp #COMMAND_FORMAT
    bne Try
    lda #60
    sta Retries
Try:
    jsr Bus::Receive
    bcc Done
    jsr DelayMillisecond
    sec
    bit Iwm::Phase0Off
    bit Iwm::DataLatch
    dec Retries
    bne Try
Done:
    rts
.endproc

;; Widens a bus device's STATUS reply to the extended form, whose block count has four bytes: moves the reply's
;; bytes 4 to $18 up one, puts a 0 in byte 4, and counts the byte.
.proc ExtendStatus
    ldy #$19
Move:
    lda TransferBuffer - 1,y
    sta TransferBuffer,y
    dey
    cpy #4
    bne Move
    stz TransferBuffer + 4
    inc Count
    rts
.endproc

;; Passes the host's command for a bus unit to its device: the command packet, the host's data if the command has
;; any, then the device's reply, whose data goes to the host in buffer 6 (TransferBuffer).
;; Commands $0A-$0C, which the bus does not know, read <Bus::CommandTable> past its end, and end with ErrorCode = A
;; as it is then: the reply's length's low byte, or the failure's code.
;; Out: carry = clear; ErrorCode = the device's status, <Bus::ERROR_BUS> if it did not answer, <ERROR_IO> for a bad
;;      reply, or <ERROR_BAD_CONTROL_PARAMETER> for host data of 5 pages or more; CardData = 6 when the reply has
;;      data, 0 after the bad parameter; Count and CountHigh = the reply's length, when one came
.proc PassCommand
    lda #IWM_MODE_SLOW
    jsr Swim::SetIwmMode
    stz BusResult
    jsr Bus::MakeCommandPacket
    jsr Bus::Idle
    jsr Bus::SendCommand
    bcs SendFailed

    ; The host's data, if the command sends some: WRITEBLOCK's 512 bytes, or Count bytes up to 5 pages.
    ldx CardState
    bit Bus::CommandTable,x
    bpl Reply
    cpx #COMMAND_WRITE_BLOCK
    beq GetData
    lda CountHigh
    cmp #MOST_DATA_PAGES
    bcc GetData
    bit Bus::CommandTable           ; overflow set: CardData gets Y, 0
    ldy #0
    lda #ERROR_BAD_CONTROL_PARAMETER
    bra Result
GetData:
    lda #TransferBuffer / $200
    sta CardData
WaitData:
    lda CardData
    bpl WaitData
    ldx Count
    ldy CountHigh
    lda CardState
    cmp #COMMAND_WRITE_BLOCK
    bne Length
    ldy #>512
    ldx #<512
Length:
    sty BusCount + 1
    stx BusCount
    lda #TYPE_DATA
    sta PacketType
    jsr Bus::Idle
    stz BufferPointer
    lda #>TransferBuffer
    sta BufferPointer + 1
    jsr Bus::SendData
SendFailed:
    bcs NoAnswer

    ; The reply, into the transfer buffer.
Reply:
    stz BufferPointer
    lda #>TransferBuffer
    sta BufferPointer + 1
    jsr Bus::ReceiveWithRetries
    bcs ReceiveFailed
    jsr Bus::ByteCount
    sta Count
    sty CountHigh

    ; An extended STATUS widens the block count; the result, and the buffer when the reply has data.
Finish:
    ldy #0
    ldx CardState
    bne Known
    bit CardCommand
    bvc Known
    jsr Bus::ExtendStatus
Known:
    cpx #COMMAND_SET_FORMAT
    clv
    bcs Result
    bit Bus::CommandTable,x
    bvc GetStatus
    ldy #TransferBuffer / $200
GetStatus:
    lda BusResult
Result:
    sta ErrorCode
    bvc Idle
    sty CardData
Idle:
    jsr Bus::Idle
    clc
    rts

    ; No packet is the bus's error; any other failure an I/O error.
ReceiveFailed:
    cmp #NO_PACKET
    beq NoAnswer
    lda #ERROR_IO
    bra Failed
NoAnswer:
    lda #ERROR_BUS
Failed:
    sta BusResult
    bra Finish
.endproc

;; How each command's packets go, by the command at CardState, STATUS ($00) to WRITE ($09). Commands $0A-$0C read on
;; into <Bus::Initialize>'s first bytes ($85, $50, $DA), which <Bus::PassCommand> takes as their entries.
CommandTable:
    BusCommand 0, 1, 3              ; STATUS
    BusCommand 0, 1, 3              ; READBLOCK
    BusCommand 1, 0, 3              ; WRITEBLOCK
    BusCommand 0, 0, 1              ; FORMAT
    BusCommand 1, 0, 3              ; CONTROL
    BusCommand 0, 0, 1              ; INIT
    BusCommand 0, 0, 1              ; OPEN
    BusCommand 0, 0, 1              ; CLOSE
    BusCommand 0, 1, 4              ; READ
    BusCommand 1, 0, 4              ; WRITE
.assert * - CommandTable = COMMAND_WRITE + 1, "Bus::CommandTable has an entry for each command to Host::Write."

;; Resets the bus and gives its devices unit numbers from X up, with an INIT command to each in turn until one
;; answers that it is the last. Units X to 3 are first marked as no device; each device found below unit 5 is
;; marked a bus device in DeviceKinds, with MediaMode 0. The drive lines are released first and the motor turned
;; off at the end.
;; In: A = the command packet's byte 4 ($80 from <Bus::Reinitialize>), X = the first unit
;; Out: A = the devices found, at most 2; Drive = the unit after the last device found
.proc Initialize
.assert * = CommandTable + COMMAND_WRITE + 1, "PassCommand reads CommandTable on into Initialize's first bytes."
    sta CommandPacket + 4
    phx
    lda #0
Clear:
    sta DeviceKinds - 1,x
    inx
    cpx #LAST_UNIT
    bcc Clear

    ; The 3.5 drives' lines released, and the IWM in the bus's mode.
    bit Iwm::MotorOff
    lda #$FF
    sta Drive
    jsr Swim::SelectBusPort
    jsr Swim::UseGcr
    lda #IWM_MODE_SLOW
    jsr Swim::SetIwmMode
    plx
    stx Drive
    jsr Bus::ResetDevices
    jsr Bus::Idle
    stz SavedDrive

    ; INIT to unit Drive, until a device says it is the last.
Next:
    lda #TYPE_COMMAND
    sta PacketType
    lda #COMMAND_INIT
    sta CommandPacket
    lda #2
    sta CommandPacket + 1
    stz CommandPacket + 3
    stz CommandPacket + 5
    jsr Bus::PointAtCommandPacket
    jsr Bus::Send
    bcs Done
    stz BufferPointer
    lda #>TransferBuffer
    sta BufferPointer + 1
    jsr Bus::Receive
    bcs Done
    ldy Drive
    cpy #LAST_UNIT + 1
    bcs Counted
    lda #$80
    sta DeviceKinds - 1,y
    lda #0
    sta MediaMode - 1,y
Counted:
    inc SavedDrive
    inc Drive
    lda BusResult
    beq Next
    lda SavedDrive
    cmp #MOST_DEVICES + 1
    bcc Done
    lda #MOST_DEVICES
    sta SavedDrive

    ; The bus idle and the motor off.
Done:
    jsr Bus::Idle
    bit Iwm::MotorOff
    lda SavedDrive
    rts
.endproc

.endscope
