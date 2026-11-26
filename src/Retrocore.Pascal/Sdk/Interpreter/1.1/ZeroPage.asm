; retrocore: style=strict
;; Zero page: the p-machine's registers, the dispatch code, the handlers' working storage, and the BIOS's and the
;; Disk II driver's own bytes.

; The p-machine's registers, with UCSD's names.

;; BASE: the outer block's mark stack frame, whose globals <LDO at OpLDO>, <SRO at OpSRO> and <LAO at OpLAO> reach.
BASE = $50

;; MP: the current procedure's mark stack frame, whose locals <LDL at OpLDL>, <STL at OpSTL> and <LLA at OpLLA> reach.
MP = $52

;; JTAB: the current procedure's attributes, at the end of its code.
JTAB = $54

;; SEG: the current segment's procedure dictionary, its last word.
SEG = $56

;; IPC: the next p-code.
IPC = $58

;; NP: the heap's top. <NEW at CspNEW> allocates up from it.
NP = $5A

;; KP: the program stack's bottom. Each call takes its frame below it, and the stack overflows when KP comes down
;; to <NP>.
KP = $5C

; Dispatch. Initialize::StartSystem writes JMP indirect instructions here, and Fetch and OpCSP set their addresses'
; low bytes.

;; JMP (<OpcodeTable>): <Fetch> sets its address's low byte, <DispatchLow>, to the opcode times 2, and jumps here.
Dispatch = $6E

;; The low byte of <Dispatch>'s address.
DispatchLow = Dispatch + 1

;; JMP (<CspTable>): <OpCSP> sets its address's low byte, <CspDispatchLow>, to the standard procedure's number times 2,
;; and jumps here.
CspDispatch = $71

;; The low byte of <CspDispatch>'s address.
CspDispatchLow = CspDispatch + 1

; Working storage the handlers share. Routines that use a byte for something of their own give it a name in their
; scope, as Divisor = Work1 in division.

;; A big operand times 2, as <GetBig> leaves it: the byte offset of the word it numbers.
Offset = $5E

;; The mark stack frame <FindFrame> finds.
Frame = $62

;; A variable's address, as the load and store handlers work it out.
Address = $64

;; A byte of working storage.
Scratch = $66

;; Initialize sets it to 1. Nothing in SYSTEM.APPLE reads it.
UnreadFlag = $67

;; Where a move copies from.
Source = $68

;; Where a move copies to.
Target = $6A

;; Which comparison the comparison handlers make, for the routines they share.
Comparison = $6C

;; A pointer the handlers share.
Pointer = $74

;; A second pointer the handlers share.
Pointer2 = $76

;; The number of the procedure a call is calling.
ProcedureNumber = $78

;; The buffer a unit call reads into or writes from.
Buffer = $7A

;; The attributes of the procedure a call is calling.
Procedure = $7C

;; The mark stack frame a call builds.
Mark = $7E

;; The floating-point routines' result, an unpacked real of 6 bytes (see <REAL_SIGN>).
Result = $80

;; A word of working storage.
Work1 = $86

;; A second word of working storage.
Work2 = $88

;; A third word of working storage.
Work3 = $8A

;; A fourth word of working storage.
Work4 = $8C

;; A caller's return address, kept while a routine pulls its arguments from under it.
ReturnAddress = $8E

;; A segment's procedure dictionary, while it is being read in and relocated.
Dictionary = $90

;; Each character unit's DLE state, a byte for each unit from unit 0: DleFlags+1 is the console's and DleFlags+6
;; the printer's.
DleFlags = $96

; The Disk II driver's bytes.

;; The 256 bytes <ReadSector> fills and <PrenibbleSector> reads: in the caller's buffer, or <ScratchBuffer> for a read's
;; partial last page.
SectorPointer = $3E

;; A 16-bit count <TransferTrack> starts at -10001 ($D8EF) when it turns the motor on, and <DiskWait> counts up every
;; 100 microseconds. A write to a drive that was not turning waits for it to reach 0, about a second.
MotorTimer = $46

;; Where a transfer starts in its first track, in Pascal's sector order (0, 2 .. 14), and 0 for the tracks after.
FirstSector = $BD

;; For a read, the byte count's low byte: the bytes in the last, partial page, or 0 for none. 0 for a write.
PartialBytes = $BE

;; The 256-byte pages still to read or write.
PagesLeft = $BF

;; <DiskTransfer>'s return address, kept while it pulls its parameters.
DiskReturn = $C0

;; The block number's high byte, halved, which must be 0.
BlockHigh = $C2

;; The sectors still to read or write in this track.
SectorsLeft = $C3

;; Where a read's partial last page is copied to from <ScratchBuffer>.
PartialDest = $C4

;; The sectors to transfer in this track.
TrackSectors = $C6

;; The drive's index into <ArmTracks>: its slot, plus $80 for drive 2.
DriveIndex = $C7

;; <StepArm>'s slot times 16.
StepSlot = $C8

;; The half-track <StepArm> moves the arm to.
StepTarget = $C9

;; The last address field's checksum.
AddressChecksum = $CA

;; The last address field's sector. <TransferTrack> then keeps the sector to handle next here.
AddressSector = $CB

;; The last address field's track.
AddressTrack = $CC

;; The last address field's volume.
AddressVolume = $CD

;; A byte of the disk routines' working storage.
DiskTemp = $CE

;; A second byte of the disk routines' working storage.
DiskTemp2 = $CF

;; A byte for each sector of the track ($D0-$DF): cleared each track, and set to $FF once the sector is read or
;; written.
SectorDone = $D0

; The BIOS's bytes.

;; A, kept while <BiosCall> switches banks.
BiosSavedA = $D2

;; The vector <BiosCall> jumps through.
BiosVector = $D3

;; A status call's control word.
StatusControl = $D6

;; The record a status call fills.
StatusRecord = $D8

;; Bit 7 set: <PutScreen> shows capital letters inverse. Output $12 and the keys Control-E and Control-W set it, and
;; output $14 clears it.
InverseCapitals = $E0

;; Bit 7 set: <ConsoleCheck> leaves letters in upper case, or else lowers them unless <Button2> shows shift; bit 6:
;; for the next key only. Startup and output $14 set $80, Control-E flips bit 7, and Control-W sets $C0.
KeyboardCase = $E1

;; <UnitReaders>+2, unit 1's entry, for attaching drivers.
ReadersPointer = $E4

;; <UnitWriters>+2, unit 1's entry, for attaching drivers.
WritersPointer = $E6

;; Startup's copy of <BiosPointers>, 8 bytes. Nothing in SYSTEM.APPLE reads it.
BiosPointersCopy = $E8

;; The cursor row's address in text page 1, which shows 40 of the 80 columns.
TextLine = $F0

;; The cursor row's address in text page 2, which keeps the other 40 columns.
TextLine2 = $F2

;; The cursor's column, 0-79.
ConsoleColumn = $F4

;; The cursor's row, 0-23.
CursorRow = $F5

;; $Cn00 for the card being called, then the firmware entry <CallFirmware> jumps through.
CardPointer = $F6

;; SYSCOM's address, from <ConsoleInit>, for <ConsoleCheck> to read the console's keys from.
SyscomPointer = $F8
