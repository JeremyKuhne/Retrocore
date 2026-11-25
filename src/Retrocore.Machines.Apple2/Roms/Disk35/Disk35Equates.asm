; retrocore: style=strict
;; THE APPLE II 3.5 DISK CONTROLLER CARD'S HARDWARE, AS ITS 65C02 SEES IT
;;
;; The card's own 65C02 runs at about 2 MHz with 32 KB of static RAM at $0000-$7FFF, its I/O page at $0A00-$0AFF
;; (over RAM), and the 32 KB EPROM at $8000-$FFFF. The host Apple II sees parts of the same RAM:
;;
;;   Host $Cn00-$CnFF  card $7B00-$7BFF   read only; the card writes the slot page there
;;   Host $C800-$CBFF  card $0000-$3FFF   a 1 KB window, bank n = card $n*$400, chosen by any access to $C080+$n0+n
;;   Host $CC00-$CFFF  card $7C00-$7FFF   always
;;
;; The SWIM (Sander-Wozniak Integrated Machine) answers at $0A00-$0A0F. At reset it is an IWM (Integrated Woz
;; Machine), whose sixteen addresses are switches like the Disk II controller's ([DiskII.md](../../../../docs/DiskII.md));
;; written with the right sequence it becomes the ISM, whose registers are written at $0A00-$0A07 and read at
;; $0A08-$0A0F. The ISM's registers keep the names Apple's Macintosh sources give them (SonyEqu.a), which no
;; document in the bibliography gives, so they cite UNKN.

;; The SWIM as an IWM: each address is a switch, set by any access. Q6 and Q7 together choose what a read gives
;; and what a write does: with both off a read gives the data, with Q6 on and Q7 off the status, with Q6 off and Q7
;; on the write handshake, and with both on a write sets the mode, or, with the motor on, writes data.
.scope Iwm

;; Turns stepper phase 0 off; on a 3.5 drive the phase lines also choose the register the drive reads or writes.
Phase0Off = $0A00

;; Turns stepper phase 0 on.
Phase0On = $0A01

;; Turns stepper phase 1 off.
Phase1Off = $0A02

;; Turns stepper phase 1 on.
Phase1On = $0A03

;; Turns stepper phase 2 off.
Phase2Off = $0A04

;; Turns stepper phase 2 on.
Phase2On = $0A05

;; Turns stepper phase 3 off; on a 3.5 drive it is the strobe (LSTRB) that runs a drive command.
Phase3Off = $0A06

;; Turns stepper phase 3 on.
Phase3On = $0A07

;; Turns the drive enable (the motor line) off.
MotorOff = $0A08

;; Turns the drive enable (the motor line) on.
MotorOn = $0A09

;; Selects drive 1.
SelectDrive1 = $0A0A

;; Selects drive 2.
SelectDrive2 = $0A0B

;; Q6 off: a read gives the data, or, with Q7 on, the write handshake.
DataLatch = $0A0C

;; Q6 on: a read gives the status, or, with Q7 on, a write sets the mode.
LoadLatch = $0A0D

;; Q7 off: reading.
ReadMode = $0A0E

;; Q7 on: writing.
WriteMode = $0A0F

.endscope

;; The SWIM as the ISM: registers written at $0A00-$0A07 and read at $0A08-$0A0F.
.scope Ism

;; The next byte to write.
;; Also: wData (UNKN)
WriteData = $0A00

;; The next byte to write, as a mark.
;; Also: wMark (UNKN)
WriteMark = $0A01

;; Writes the CRC in place of a byte.
;; Also: wCRC (UNKN)
WriteCrc = $0A02

;; The next of the sixteen timing parameters.
;; Also: wParams (UNKN)
WriteParameter = $0A03

;; The phase lines and their directions.
;; Also: wPhase (UNKN)
WritePhase = $0A04

;; The setup register.
;; Also: wSetup (UNKN)
WriteSetup = $0A05

;; Clears the mode bits set in the byte written.
;; Also: wZeroes (UNKN)
ClearMode = $0A06

;; Sets the mode bits set in the byte written.
;; Also: wOnes (UNKN)
SetMode = $0A07

;; The next byte read.
;; Also: rData (UNKN)
ReadData = $0A08

;; The next byte read, as a mark.
;; Also: rMark (UNKN)
ReadMark = $0A09

;; The error register, cleared by reading it.
;; Also: rError (UNKN)
ReadError = $0A0A

;; The next timing parameter.
;; Also: rParams (UNKN)
ReadParameter = $0A0B

;; The phase lines.
;; Also: rPhase (UNKN)
ReadPhase = $0A0C

;; The setup register.
;; Also: rSetup (UNKN)
ReadSetup = $0A0D

;; The mode register.
;; Also: rStatus (UNKN)
ReadMode = $0A0E

;; The FIFO's state.
;; Also: rHandshake (UNKN)
ReadHandshake = $0A0F

.endscope

; The card's own latches, also set by any access.

;; Selects the lower head (side 0).
SelectSide0 = $0A40

;; Selects the upper head (side 1).
SelectSide1 = $0A41

;; Turns the diagnostic LED on.
LedOn = $0A80

;; Turns the diagnostic LED off.
LedOff = $0A81

; The RAM the host sees.

;; The host's $Cn00-$CnFF.
SharedSlotPage = $7B00

;; The host's $CC00-$CFFF.
SharedExpansion = $7C00

; The commands the host writes at the card's CardState: SmartPort's commands less their extended bit ($40), and the
; card's own. A ProDOS call arrives as SmartPort's STATUS to FORMAT, with CardCommand's bit 7 set.

;; SmartPort STATUS, and ProDOS's status call.
COMMAND_STATUS = $00

;; SmartPort READBLOCK, and ProDOS's read.
COMMAND_READ_BLOCK = $01

;; SmartPort WRITEBLOCK, and ProDOS's write.
COMMAND_WRITE_BLOCK = $02

;; SmartPort FORMAT, and ProDOS's format.
COMMAND_FORMAT = $03

;; SmartPort CONTROL.
COMMAND_CONTROL = $04

;; SmartPort INIT.
COMMAND_INIT = $05

;; SmartPort OPEN, which a block device refuses.
COMMAND_OPEN = $06

;; SmartPort CLOSE, which a block device refuses.
COMMAND_CLOSE = $07

;; SmartPort READ: a block with its tag bytes.
COMMAND_READ = $08

;; SmartPort WRITE: a block with its tag bytes.
COMMAND_WRITE = $09

;; The 3.5 controller's SETFORMAT: the format the next FORMAT writes.
COMMAND_SET_FORMAT = $0A

;; The 3.5 controller's FORMATOPTIONS: the list of formats a unit can write.
COMMAND_FORMAT_OPTIONS = $0B

;; The slot ROM's boot: reads block 0 of unit 1.
COMMAND_BOOT = $0C

;; READAHEAD, which the slot ROM does not use.
COMMAND_READ_AHEAD = $0D

;; READSPAN, which the slot ROM does not use.
COMMAND_READ_SPAN = $0E

;; Runs the diagnostics.
COMMAND_DIAGNOSTICS = $3D

;; The host is not a IIgs.
COMMAND_NOT_IIGS = $7E

;; The host is a IIgs.
COMMAND_IIGS = $7F

; SmartPort's error codes, as Apple's Apple IIgs Firmware Reference names them.

;; The command is not one the device knows.
;; Also: BADCMD (UNKN)
ERROR_BAD_COMMAND = $01

;; The parameter list's count is wrong for the command.
;; Also: BADPCNT (UNKN)
ERROR_BAD_PARAMETER_COUNT = $04

;; The unit is not one there is.
;; Also: BADUNIT (UNKN)
ERROR_BAD_UNIT = $11

;; The control or status code is not one the device knows.
;; Also: BADCTL (UNKN)
ERROR_BAD_CONTROL = $21

;; A control call's parameter is wrong.
;; Also: BADCTLPARM (UNKN)
ERROR_BAD_CONTROL_PARAMETER = $22

;; The disk could not be read or written.
;; Also: IOERROR (UNKN)
ERROR_IO = $27

;; There is no drive.
;; Also: NODRIVE (UNKN)
ERROR_NO_DRIVE = $28

;; The disk is write-protected.
;; Also: NOWRITE (UNKN)
ERROR_WRITE_PROTECTED = $2B

;; The block number is past the disk's end.
;; Also: BADBLOCK (UNKN)
ERROR_BAD_BLOCK = $2D

;; The disk was switched since the last call.
;; Also: DISKSW (UNKN)
ERROR_DISK_SWITCHED = $2E

;; There is no disk in the drive.
;; Also: OFFLINE (UNKN)
ERROR_OFFLINE = $2F

; The bits of DiskErrors: what went wrong on the disk.

;; No address mark or data mark was found, or the data field's sector number was not the address field's.
DISK_ERROR_NO_FIELD = $01

;; The head did not find track 0.
DISK_ERROR_NO_TRACK_0 = $02

;; The address field was on the wrong track.
DISK_ERROR_WRONG_TRACK = $04

;; A data field's epilogue was wrong.
DISK_ERROR_BAD_EPILOGUE = $08

;; A data field's checksum was wrong.
DISK_ERROR_BAD_CHECKSUM = $10

;; The address field's checksum, CRC or epilogue did not match.
DISK_ERROR_BAD_FIELD = $20

;; The IWM ran out of bytes to write (an underrun).
DISK_ERROR_UNDERRUN = $40

;; The address field was for the other side.
DISK_ERROR_WRONG_SIDE = DISK_ERROR_BAD_FIELD | DISK_ERROR_BAD_EPILOGUE
