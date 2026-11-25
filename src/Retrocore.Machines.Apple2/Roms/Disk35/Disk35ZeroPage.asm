;; THE CARD'S PAGE ZERO, AS THE ROM SETS IT UP
;;
;; STARTUP copies $8001-$80BB to the card's page zero, and $80BC-$80BF (the signature) once the rest is
;; ready. Its first bytes are the mailbox the host reads and writes at $C800 with bank 0 latched. The vectors
;; at $72-$8C are JMP instructions that the control calls can repoint and put back.

.logicalorg $0000

;; Bit 7 = the card waits for a command; the host writes the command here.
CardState:
    .byte $FF

;; The host writes $FF; the card's bit 7 = busy, 0 = done (no data), else bank*2+half of the data.
CardData:
    .byte $FF

;; The host's command byte: bit 7 = a ProDOS call, bit 6 = an extended call.
CardCommand:
    .byte $00

;; The unit number (0 = the controller).
CardUnit:
    .byte $FF

;; The host's copy of a block being written, on a IIgs: $C0, $C1, $D0 done.
WriteProgress:
    .byte $00

;; The status or control code, or the block number's low byte.
ParameterLow:
    .byte $FF

;; The block number's middle byte.
ParameterMiddle:
    .byte $FF

;; The block number's high byte.
ParameterHigh:
    .byte $00

;; The next parameter.
Parameter3:
    .byte $00

;; Commands $0D/$0E: the extra blocks, low byte.
Parameter4:
    .byte $00

;; Commands $0D/$0E: the extra blocks, high byte.
Parameter5:
    .byte $00

;; The byte count of the list or data, both ways.
Count:
    .byte $00

CountHigh:
    .byte $00

;; Each drive's head position ($FF unknown; bit 6 = the second side's track, from a header).
CurrentTrack:
    .byte $FF, $FF

;; Each drive's disk: bit 7 = two sides.
DiskSides:
    .byte $80, $80

;; Each drive's last address field's format byte.
LastFormatByte:
    .byte $00, $00

;; A drive or count kept across calls.
SavedDrive:
    .byte $00

;; The track to reach.
Track:
    .byte $FF

;; The sector to read.
Sector:
    .byte $FF

;; The side: 0, or $20 for the second.
Side:
    .byte $FF

;; The bus packet's high bits.
PacketHighBits:
    .byte $FF

;; A 7-byte group's high bits, or the groups left.
GroupHighBits:
    .byte $FF

;; The bus packet's type: $80 command, $82 data.
PacketType:
    .byte $FF

;; The sectors in the track.
SectorsPerTrack:
    .byte $00

;; The track times 2, plus the side.
Cylinder:
    .byte $FF

;; Sectors left to read or write.
SectorCount:
    .byte $FF, $00

;; An address field's or packet's checksum.
HeaderChecksum:
    .byte $FF

;; The GCR data checksums.
Checksum0:
    .byte $00

Checksum1:
    .byte $00

Checksum2:
    .byte $00

;; The checksums' high bits, packed.
ChecksumHighBits:
    .byte $00

;; Scratch.
Work0:
    .byte $00

;; Scratch.
Work1:
    .byte $00, $00, $00

;; The address field read: checksum.
AddressChecksum:
    .byte $00

;; Format byte.
AddressFormat:
    .byte $00

;; Side bits.
AddressSide:
    .byte $00

;; Sector.
AddressSector:
    .byte $00

;; Track.
AddressTrack:
    .byte $00

;; Scratch.
Scratch:
    .byte $00

;; The current buffer's code: its card address / $200.
BufferCode:
    .byte $00

;; The current cache slot (0 = none).
CacheSlot:
    .byte $00

;; The unit less one: 0-1 the 3.5 drives, more a bus device, $FF the controller.
Drive:
    .byte $00

;; WAITREADY's counter.
WaitCount:
    .byte $00, $00

;; The first SmartPort bus device's unit, or 0.
FirstBusUnit:
    .byte $00

;; The units, 3.5 drives and bus devices.
UnitCount:
    .byte $00

;; Each unit's device: 1 Apple 3.5, 3 FDHD, $80 a bus device, 0 none.
DeviceKinds:
    .byte $00, $00, $00, $00

;; READSPAN's first sector.
SpanFirst:
    .byte $00

;; READSPAN's cylinder.
SpanCylinder:
    .byte $00

;; Each drive's disk: $11 GCR, $32 MFM 720K, $52 MFM 1440K; bits 5-6 = MFM.
MediaMode:
    .byte $00, $00, $00, $00, $00

;; The sense lines before the last READSENSE.
PreviousSense:
    .byte $00

;; Each drive's disk: 0 unknown, 2 400K, 4 800K, 6 800K (2:1), 8 720K, $0A 1440K.
MediaKind:
    .byte $00, $00

;; Each drive's block count, low bytes.
BlockCount:
    .byte $00, $00

;; And high bytes.
BlockCountHigh:
    .byte $00, $00

;; Each drive's sense lines: 7 switched, 6 no disk, 5 protected, 4 one side only, 0 motor has had its full start.
Sense:
    .byte $00, $00

;; Each drive's format for the next FORMAT (0 = the default).
FormatKind:
    .byte $00, $00

;; Each drive's interleave for the next FORMAT.
FormatInterleave:
    .byte $00, $00

;; The bus command packet: command, parameter count, parameters.
CommandPacket:
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00

;; The result the host reads.
ErrorCode:
    .byte $00

;; What went wrong on the disk or the bus.
DiskErrors:
    .byte $00

;; Retries left; CTLPEEK's byte.
Retries:
    .byte $00

;; CTLEXECUTE's A; also counts errors.
ResultA:
    .byte $00

;; CTLEXECUTE's X; also counts errors.
ResultX:
    .byte $00

;; CTLEXECUTE's Y; also a retry count.
ResultY:
    .byte $00

;; CTLEXECUTE's P; also a seek count.
ResultStatus:
    .byte $00

;; Address fields left to look at.
SectorTries:
    .byte $00

;; $21 when a tagged call meets an MFM disk.
TagError:
    .byte $00

;; Control $0F's bit 7.
CacheOption:
    .byte $00

;; A read's state: 7 the cache full, 6 the block handed over.
ReadState:
    .byte $00

;; Negative during READWRITE.
TagCall:
    .byte $00

;; The interleave for FORMAT.
Interleave:
    .byte $04

;; Bit 7 = FORMAT writes both sides.
TwoSided:
    .byte $80

;; The address for the control calls.
UserPointer:
    .byte $00, $05

;; A GCR write's high bits.
NibbleHighBits:
    .byte $00

;; The bytes being nibblized.
Nibble0:
    .byte $00

Nibble1:
    .byte $00

Nibble2:
    .byte $00

;; The ISM setup register's value.
SetupCopy:
    .byte $00

;; $80 while a read is in progress.
Reading:
    .byte $00

;; A bus packet's byte count.
BusCount:
    .byte $00, $00

;; Where PREPAREDATA starts.
NibbleStart:
    .byte $00

;; The drive being ejected; bit 7 = none.
EjectDrive:
    .byte $80

;; The vectors' length, for CTLRESETVECTORS.
VectorLength:
    .byte $1B, $00
;; the vectors, JMP instructions the control calls can change
Vectors:
ReadAddressVector:
    jmp ReadGcrAddressField

ReadDataVector:
    jmp ReadGcrDataField

WriteDataVector:
    jmp WriteGcrDataField

SeekVector:
    jmp SeekTrack

FormatVector:
    jmp FormatDisk

WriteTrackVector:
    jmp WriteGcrTrack

VerifyVector:
    jmp VerifyGcrTrack

CommandVector:
    jmp RunCommand

InitializeVector:
    jmp InitializeCard

;; The GCR marks and sync bytes.
Marks:
    .byte $FF

;; The data field's mark, last byte first: D5 AA AD.
DataMark:
    .byte $AD, $AA, $D5, $FF

;; A self-sync group, last byte first.
SyncBytes:
    .byte $FC, $F3, $CF, $3F, $FF

;; The fields' end, last byte first: DE AA.
Epilogue:
    .byte $FF, $AA, $DE, $FF, $FF, $FF, $FF, $FF

;; The address field's mark, last byte first: D5 AA 96.
AddressMark:
    .byte $96, $AA, $D5, $FF

;; A received bus packet's header.
PacketHeader:
    .byte $00

;; A bus packet's 7-byte groups.
Groups:
    .byte $00

;; And its other bytes.
OddBytes:
    .byte $00

;; The bus device's result.
BusResult:
    .byte $00, $00, $00, $00, $00

;; The first half of the buffer.
BufferPointer:
    .byte $00, $00

;; A pointer, or a timer.
WorkPointer:
    .byte $00, $00

;; The second half of the buffer.
SecondBufferPointer:
    .byte $00, $00

;; The sectors wanted: first.
SpanStart:
    .byte $00

;; And past the last.
SpanEnd:
    .byte $00, $00

;; Bit 7 = the disk is MFM, bit 6 = the SWIM is in ISM mode.
SwimState:
    .byte $00

;; The unit with bit 7, for an extended unit-0-style status.
UnitWithHighBit:
    .byte $00

;; The MFM format's gap length.
MfmGap:
    .byte $00, $00, $00

;; Negative when the self-test calls a command.
TestCall:
    .byte $00

;; A routine FORMAT calls for an Apple 3.5 drive.
FormatHook:
    .byte $00, $00

;; The warm-start signature.
WarmSignature:
    .byte $4A, $CF, $41, $55, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00

;; The last command: CardState, CardCommand, CardUnit, ParameterLow, ParameterMiddle.
LastCommand:
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
.logicalorg
