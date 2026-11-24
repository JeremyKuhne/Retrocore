; retrocore: style=strict
;; COMMODORE BASIC 4: THE KERNAL'S WORKSPACE AND ENTRIES THE MONITOR AND DISK COMMANDS USE
;;
;; These are the PET 4.0 kernal's and screen editor's own addresses, as Basic4.mac gives them, not allocations. The
;; monitor and the disk commands share this storage with the editor and the kernal. Each name cites the kernal's
;; listing of October 23, 1979 (K4S79) and its reconstruction (HVK4), where they give it. Including this file emits
;; no bytes and does not change the origin.
;;
;; The I/O status byte (`SATUS`) is <IoStatus>, the carriage return (`CR`) <CARRIAGE_RETURN> and the `ON` token
;; (`ONTK`) <TOKEN_ON>, each defined once with the workspace or its table and carrying these names.

; The kernal's page-zero workspace.

;; The two-byte RAM interrupt vector; the monitor saves it on entry and restores it on `G`.
;; Also: CINV (K4S79, HVK4)
IrqVector = $90

;; 0 for `LOAD`, 1 for `VERIFY`; the monitor and `DLOAD` clear it.
;; Also: VERCK (K4S79, HVK4)
LoadVerifyFlag = $9D

;; The number of entries in the kernal's file tables, <LogicalFileTable> and its neighbors.
;; Also: LDTND (K4S79, HVK4)
OpenFileCount = $AE

;; The kernal's current output device.
;; Also: DFLTO (K4S79, HVK4)
DefaultOutputDevice = $B0

;; The kernal's cassette write flag, which `CATALOG` reuses to keep its output file.
;; Also: WSW (K4S79, HVK4)
CatalogOutputFile = $B3

;; The index of the monitor command being run, in <Monitor::CommandKeys>; `L` and `S` test it.
;; Also: SAVX (K4S79, HVK4), T1 (K4S79, HVK4)
MonitorCommandIndex = $B4

;; The monitor's entry letter (`B` or `C`), then the count of bytes a command shows or alters.
;; Also: TMPC (K4S79, HVK4), RCNT (K4S79, HVK4), T2 (K4S79, HVK4)
MonitorCount = $B5

;; The kernal's cassette countdown, which `CATALOG` reuses to keep <DefaultOutputDevice>.
;; Also: CNTDN (K4S79, HVK4)
CatalogOutputDevice = $BA

;; The end address of a kernal save; the monitor's `S` sets it.
;; Also: EAL (K4S79, HVK4)
EndAddress = $C9

;; The high byte of <EndAddress>.
;; Also: EAH (K4S79, HVK4)
EndAddressHigh = $CA

;; The length of the kernal's current filename.
;; Also: FNLEN (K4S79, HVK4)
FilenameLength = $D1

;; The kernal's current logical file number.
;; Also: LA (K4S79, HVK4)
LogicalFile = $D2

;; The kernal's current secondary address.
;; Also: SA (K4S79, HVK4)
SecondaryAddress = $D3

;; The kernal's current device (primary address).
;; Also: FA (K4S79, HVK4)
DeviceNumber = $D4

;; The two-byte pointer to the kernal's current filename.
;; Also: FNADR (K4S79, HVK4)
FilenamePointer = $DA

;; Made nonzero (incremented) when the monitor's address passes $FFFF, so a display stops there.
;; Also: WRAP (K4S79, HVK4), FSBLK (K4S79, HVK4)
MonitorAddressWrapped = $DE

;; The two-byte address a monitor command is working on.
;; Also: TMP0 (K4S79, HVK4), STAL (K4S79, HVK4)
MonitorAddress = $FB

;; The two-byte second address of a monitor command: the end of a range.
;; Also: TMP2 (K4S79, HVK4)
MonitorEndAddress = $FD

;; The disk commands' pointer to their second filename, in <MonitorEndAddress>'s bytes.
;; Also: FNADR2 (K4S79, HVK4)
SecondFilenamePointer = MonitorEndAddress

;; The byte where the monitor assembles a hexadecimal byte from its two digits: <NumberBuffer>'s first byte, which
;; the monitor borrows.
;; Also: BAD (K4S79, HVK4)
MonitorHexByte = NumberBuffer
.assert MonitorHexByte = $0100, "The monitor's hexadecimal scratch is at $0100."

; The monitor's saved registers and the kernal's file tables, in page two.

;; The saved program counter's high byte, which the monitor stores below the low byte.
;; Also: PCH (K4S79, HVK4)
ProgramCounterHigh = $0200

;; The saved program counter's low byte.
;; Also: PCL (K4S79, HVK4)
ProgramCounter = $0201

;; The saved processor status, the first of the five register bytes the monitor shows and alters.
;; Also: FLGS (K4S79, HVK4)
SavedStatus = $0202

;; The saved accumulator.
;; Also: ACC (K4S79, HVK4)
SavedA = $0203

;; The saved X register.
;; Also: XR (K4S79, HVK4)
SavedX = $0204

;; The saved Y register.
;; Also: YR (K4S79, HVK4)
SavedY = $0205

;; The saved stack pointer.
;; Also: SP (K4S79, HVK4)
SavedStackPointer = $0206

;; The high byte of <IrqVector> as the monitor found it.
;; Also: INVH (K4S79, HVK4)
SavedIrqVectorHigh = $0207

;; The low byte of <IrqVector> as the monitor found it.
;; Also: INVL (K4S79, HVK4)
SavedIrqVector = $0208

;; The buffer for the monitor's `L` and `S` filename, at most 15 characters: a 16th fails the command.
;; Also: SAVNAM (K4S79, HVK4), ZZZ1 (K4S79, HVK4)
MonitorFilename = $0209

;; The kernal's table of the open files' logical file numbers.
;; Also: LAT (K4S79, HVK4)
LogicalFileTable = $0251

;; The kernal's table of the open files' devices.
;; Also: FAT (K4S79, HVK4)
DeviceTable = $025B

;; The kernal's table of the open files' secondary addresses.
;; Also: SAT (K4S79, HVK4)
SecondaryAddressTable = $0265

; The disk commands' parameters, in page three.

;; The length of a disk command's second filename. The kernal listings (K4S79, HVK4) also call this byte POS, which
;; BASIC's POS function already has, so it is named here only in prose.
;; Also: FNLEN2 (K4S79, HVK4), TAPE2 (K4S79, HVK4)
SecondFilenameLength = $033A

;; `RECORD`'s byte position in the record, in <SecondFilenameLength>'s byte.
;; Also: RECPOS (UNKN)
RecordPosition = SecondFilenameLength

;; The disk command's first drive number.
;; Also: DRIVE1 (K4S79, HVK4)
FirstDrive = $033B

;; The disk command's second drive number.
;; Also: DRIVE2 (K4S79, HVK4)
SecondDrive = $033C

;; A relative file's record length, from `DOPEN`'s `L`.
;; Also: LRECL (K4S79, HVK4)
RecordLength = $033D

;; Set once the parser has read a disk ID, in <RecordLength>'s byte.
;; Also: DIDCHK (K4S79, HVK4)
DiskIdSeen = RecordLength

;; The bits of the disk parameters the parser has read. The kernal listings (K4S79, HVK4) call this byte PARCHK, which
;; BASIC's `EvaluateParenthesized` already has, so it is named here only in prose.
;; Also: PRSCHK (UNKN)
ParsedParameters = $033E

;; The two-byte disk ID for `HEADER`.
;; Also: DISKID (K4S79, HVK4)
DiskId = $033F

;; The bytes left in the disk-command template being expanded. The kernal listings (K4S79, HVK4) call this byte COUNT,
;; which BASIC's `Counter` already has, so it is named here only in prose.
;; Also: KCOUNT (UNKN)
TemplateCount = $0341

;; The disk command's first filename, as the parser copied it.
;; Also: TBUF2 (K4S79, HVK4)
FirstFilename = $0342

;; Where a disk command is built before it is sent to the drive.
;; Also: TBUFF (K4S79, HVK4)
DiskCommandBuffer = $0353

;; The vector the monitor jumps through for a command letter it does not know.
;; Also: USRCMD (K4S79, HVK4)
MonitorUserCommandVector = $03FA

; The screen editor's and the kernal's entries.

;; The screen editor's character output, which prints the disk status to the screen.
;; Also: PRT (K4S79, HVK4)
ScreenOut = $E202

;; The base of the kernal's messages; an offset from it selects one.
;; Also: MS1 (K4S79, HVK4), MSG1 (K4S79, HVK4)
KernalMessages = $F000

;; The kernal's `FILE NOT OPEN` message.
;; Also: MS3 (K4S79, HVK4)
FileNotOpenMessage = $F017

;; The kernal's confirmation prompt.
;; Also: MSG30 (K4S79, HVK4)
ConfirmMessage = $F0B6

;; The kernal's bad-disk message.
;; Also: MSG31 (K4S79, HVK4)
BadDiskMessage = $F0C5

;; Addresses a device on the IEEE bus as a talker.
;; Also: TALK (K4S79, HVK4)
KernalTalk = $F0D2

;; Addresses a device on the IEEE bus as a listener.
;; Also: LISTN (K4S79, HVK4)
KernalListen = $F0D5

;; Prints the kernal message at offset Y from <KernalMessages>.
;; Also: MSG (K4S79, HVK4)
KernalPrintMessage = $F185

;; Sends a secondary address after <KernalTalk>. The overlay's SECND is the kernal's name for another routine, at its
;; own address.
;; Also: SECND (UNKN), TKSA (K4S79, HVK4)
KernalSendSecondary = $F193

;; Sends UNTALK on the bus.
;; Also: UNTLK (K4S79, HVK4)
KernalUntalk = $F1AE

;; Sends UNLISTEN on the bus.
;; Also: UNLSN (K4S79, HVK4)
KernalUnlisten = $F1B9

;; Receives a byte from the bus's talker.
;; Also: ACPTR (K4S79, HVK4)
KernalReceiveByte = $F1C0

;; Gets a character without waiting.
;; Also: GETIN (K4S79, HVK4)
KernalGetInput = $F205

;; Reads a character from the selected input.
;; Also: BASIN (K4S79, HVK4)
KernalInputCharacter = $F215

;; Writes a character to the selected output.
;; Also: BSOUT (K4S79, HVK4)
KernalOutputCharacter = $F266

;; Restores the default input and output channels.
;; Also: CLRCH (K4S79, HVK4), CLRCHN (K4S79, HVK4)
KernalRestoreChannels = $F2A6

;; Looks up <LogicalFile> in the kernal's file tables; zero is set when it is found.
;; Also: JLTLK (K4S79, HVK4)
KernalFindLogicalFile = $F2C1

;; Loads the found file's table entries into the current file's fields.
;; Also: JZ100 (K4S79, HVK4)
KernalLoadFileEntry = $F2CD

;; Closes the selected logical file.
;; Also: CLOS5 (K4S79, HVK4), FCLOSE (K4S79, HVK4)
KernalCloseLogicalFile = $F2E2

;; Closes the file at table position X.
;; Also: CLOS10 (K4S79, HVK4)
KernalCloseFileAt = $F2E7

;; Tests the `STOP` key; zero is set when it is down.
;; Also: STOP1 (K4S79, HVK4)
KernalTestStopKey = $F335

;; The kernal's load entry that the monitor's `L` calls.
;; Also: LD15 (K4S79, HVK4)
KernalMonitorLoad = $F356

;; Loads without parsing a filename, for `DLOAD`.
;; Also: LOADNP (K4S79, HVK4)
KernalLoadWithoutName = $F408

;; Sends an `OPEN` with the filename on the bus.
;; Also: OPENIB (K4S79, HVK4)
KernalSendOpen = $F4B4

;; Opens the filename a disk command prepared.
;; Also: OP94 (K4S79, HVK4)
KernalOpenPrepared = $F563

;; Opens a file from the current file's fields.
;; Also: FOPEN (K4S79, HVK4)
KernalOpenCurrentFile = $F565

;; Reports kernal message Y as an error.
;; Also: ERMSG (K4S79, HVK4)
KernalReportMessage = $F5AF

;; The kernal's save entry for BASIC, which `DSAVE` calls.
;; Also: SV3 (K4S79, HVK4)
KernalBasicSave = $F6E0

;; The kernal's save entry that the monitor's `S` calls.
;; Also: SV5 (K4S79, HVK4)
KernalMonitorSave = $F6E3

;; Selects a logical file for input.
;; Also: CHKIN (K4S79, HVK4)
KernalSetInputChannel = $F7AF

;; Selects a logical file for output.
;; Also: CHKOUT (K4S79, HVK4), CKOUT (K4S79, HVK4)
KernalSetOutputChannel = $F7FE

;; Waits for the tape operation to finish.
;; Also: TWAIT (K4S79, HVK4)
KernalWaitForTape = $F92B

; Values.

;; The bit of <IoStatus> that reports a load or verify error.
;; Also: SPERR (K4S79, HVK4)
STATUS_LOAD_ERROR = $10

;; The number of command letters the monitor knows, in <Monitor::CommandKeys>.
;; Also: NCMDS (K4S79, HVK4)
MONITOR_COMMAND_COUNT = 8
