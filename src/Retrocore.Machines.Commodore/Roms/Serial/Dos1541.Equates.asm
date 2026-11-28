; retrocore: style=strict
; COMMODORE 1541 DOS: THE LOCATIONS AND THE CONSTANTS

;; The job queue, a byte per buffer: the job code with the drive in bit 0, which the controller replaces with a result
;; below $80 when it is done (Q4).
;; Also: JOBS (D1541)
JobQueue = $0000
;; The jobs' headers, two bytes a buffer, the track then the sector (Q4).
;; Also: HDRS (D1541)
JobHeaders = $0006
;; Each drive's disk ID, two bytes, which the controller checks every header against.
;; Also: DSKID (D1541)
DiskId = $0012
;; The last header read, in binary: the ID's two bytes, the track, the sector and the checksum.
;; Also: HEADER (D1541)
LastHeader = $0016
;; Each drive's flag, set by the controller when the write-protect sense changes (a disk going in or out); the DOS
;; reinitializes.
;; Also: WPSW (D1541)
DiskChanged = $001C
;; The NMI's vector, which the UI command jumps through.
;; Also: VNMI (D1541)
NmiVector = $0065
;; The sectors between a file's blocks that the free-block search skips.
;; Also: SECINC (D1541)
SectorInterleave = $0069
;; A pointer to the BAM entry of the track being allocated or freed.
;; Also: BMPNT (D1541)
BamPointer = $006D
;; As TEMP: its first byte's second name.
;; Also: T0 (D1541), TEMP (D1541)
Temporary = $006F
;; Temporary's second byte.
;; Also: T1 (D1541)
Temporary1 = $0070
;; Temporary's third byte.
;; Also: T2 (D1541)
Temporary2 = $0071
;; Temporary's fourth byte.
;; Also: T3 (D1541)
Temporary3 = $0072
;; Temporary's fifth byte.
;; Also: T4 (D1541)
Temporary4 = $0073
;; A general pointer: the start-up's ROM and RAM tests, the block commands' memory access.
;; Also: IP (D1541)
Pointer = $0075
;; Set while the drive is addressed to listen.
;; Also: LSNACT (D1541)
Listening = $0079
;; Set while the drive is addressed to talk.
;; Also: TLKACT (D1541)
Talking = $007A
;; Set by the ATN interrupt for the idle loop to serve the bus.
;; Also: ATNPND (D1541)
AtnPending = $007C
;; The drive the DOS is working on, 0 or 1.
;; Also: DRVNUM (D1541)
DriveNumber = $007F
;; The track of the block being worked on.
;; Also: TRACK (D1541)
Track = $0080
;; The sector of the block being worked on.
;; Also: SECTOR (D1541)
Sector = $0081
;; The channel being worked on, 0-5: the index into the Channel tables (Q5).
;; Also: LINDX (D1541)
Channel = $0082
;; The secondary address being worked on, 0-15 or an internal one.
;; Also: SA (D1541)
SecondaryAddress = $0083
;; The secondary byte as received: the address with $60 for data, $E0 for CLOSE or $F0 for OPEN.
;; Also: ORGSA (D1541)
SecondaryCommand = $0084
;; The byte being received, sent or moved.
;; Also: DATA (D1541)
DataByte = $0085
;; The first of five work bytes several families use; routines name their uses by scoped aliases.
;; Also: R0 (D1541)
Work0 = $0086
;; The second work byte.
;; Also: R1 (D1541)
Work1 = $0087
;; The third work byte.
;; Also: R2 (D1541)
Work2 = $0088
;; The fourth work byte.
;; Also: R3 (D1541)
Work3 = $0089
;; The fifth work byte.
;; Also: R4 (D1541)
Work4 = $008A
;; A pointer into a buffer: a directory entry, a side sector, the BAM sector's name.
;; Also: DIRBUF (D1541)
BufferPointer = $0094
;; A pointer per buffer, 7 of them, whose low byte is the position in it: the five data buffers, the command buffer, the
;; error buffer (Q4).
;; Also: BUFTAB (D1541)
BufferPositions = $0099
;; <BufferPositions>' entry for the command buffer, the parser's place in it; the next pointer, the error buffer's, is
;; used as CB+2.
;; Also: CB (D1541)
CommandPointer = $00A3
;; Each channel's buffer number, 7 entries; bit 7 set while inactive or none, bit 6 while dirty (Q5).
;; Also: BUF0 (D1541)
ChannelBuffer = $00A7
;; Each channel's second buffer, for double buffering, as <ChannelBuffer>; seven bytes after it, so <ActiveBufferSlot>
;; indexes both.
;; Also: BUF1 (D1541)
ChannelSecondBuffer = $00AE
;; A sequential or program file's channel: the blocks written, low byte, for its entry. The same bytes are
;; <ChannelRecord> (Q2).
;; Also: NBKL (D1541)
ChannelBlocks = $00B5
;; A relative file's channel: its record number, low byte. The same bytes are <ChannelBlocks> for other files (Q2).
;; Also: RECL (D1541)
ChannelRecord = $00B5
;; <ChannelBlocks>' high byte. The same bytes are <ChannelRecordHigh>.
;; Also: NBKH (D1541)
ChannelBlocksHigh = $00BB
;; <ChannelRecord>'s high byte.
;; Also: RECH (D1541)
ChannelRecordHigh = $00BB
;; A relative file's channel: where its next record starts in the buffer, 0 for none.
;; Also: NR (D1541)
ChannelNextRecord = $00C1
;; A relative file's channel: its record size.
;; Also: RS (D1541)
ChannelRecordSize = $00C7
;; A relative file's channel: its side sector's buffer number, $FF for none.
;; Also: SS (D1541)
ChannelSideSector = $00CD
;; The position within the record that P set.
;; Also: RECPTR (D1541)
RecordOffset = $00D4
;; Which side sector lists the record's block, 0-5.
;; Also: SSNUM (D1541)
SideSectorNumber = $00D5
;; Where in that side sector the block's pointer is.
;; Also: SSIND (D1541)
SideSectorIndex = $00D6
;; Where in its data block the record starts.
;; Also: RELPTR (D1541)
BlockOffset = $00D7
;; For each file name, the directory sector its entry was found in (Q5).
;; Also: ENTSEC (D1541)
FileNameEntrySector = $00D8
;; For each file name, the entry's offset in that sector.
;; Also: ENTIND (D1541)
FileNameEntryIndex = $00DD
;; For each file name, its drive in bit 0, bit 7 set when it was the default.
;; Also: FILDRV (D1541)
FileNameDrive = $00E2
;; For each file name, bit 7 set if it is a pattern, with the entry's type and flags once found.
;; Also: PATTYP (D1541)
FileNamePattern = $00E7
;; Each channel's file type and drive, with the RELATIVE_ flags in bits 5-7.
;; Also: FILTYP (D1541)
ChannelFileType = $00EC
;; Each channel's readiness, the CHANNEL_ bits: to talk, to listen, more to send.
;; Also: CHNRDY (D1541)
ChannelStatus = $00F2
;; 0 when the byte just received or read was the last (EOI or end of file), non-zero otherwise.
;; Also: EOIFLG (D1541)
MoreBytes = $00F8
;; The buffer whose job is being set up or waited for.
;; Also: JOBNUM (D1541)
JobNumber = $00F9
;; Each drive's flag, set when initializing it failed.
;; Also: NODRV (D1541)
NoDrive = $00FF
;; Each drive's disk format, from the BAM, "A"; writing refuses another.
;; Also: DSKVER (D1541)
DiskVersion = $0101
;; The command channel's text, and an OPEN's name.
;; Also: CMDBUF (D1541)
CommandBuffer = $0200
;; The command's index in the command table.
;; Also: CMDNUM (D1541)
CommandNumber = $022A
;; Each secondary address's channel, bit 7 set for writing, bit 6 for a channel that does both, $FF for none.
;; Also: LINTAB (D1541)
SecondaryChannels = $022B
;; Each channel's next byte to send, fetched ahead.
;; Also: CHNDAT (D1541)
ChannelByte = $023E
;; Each channel's position of the last byte in its buffer, where reading ends.
;; Also: LSTCHR (D1541)
ChannelLastByte = $0244
;; The type of the file being opened.
;; Also: TYPE (D1541)
FileType = $024A
;; The job code being set up, and a sector number meanwhile.
;; Also: CMD (D1541)
JobCommand = $024D
;; A bit per buffer, two bytes, set while in use; bits 5-15 are always set, since there are five.
;; Also: BUFUSE (D1541)
BuffersInUse = $024F
;; Each drive's flag, set when its BAM has changed and must be written.
;; Also: MDIRTY (D1541)
BamDirty = $0251
;; The directory search's last match, the file name's number, or $FF.
;; Also: ENTFND (D1541)
EntryFound = $0253
;; Set while a channel reads the directory as a program.
;; Also: DIRLST (D1541)
ListingActive = $0254
;; Set when the command channel's text is complete, for the idle loop to run.
;; Also: CMDWAT (D1541)
CommandWaiting = $0255
;; A bit per channel, set while it is free.
;; Also: LINUSE (D1541)
FreeChannels = $0256
;; Which entry of <ChannelBuffer> or <ChannelSecondBuffer> (its index plus 7) holds the active buffer.
;; Also: LBUSED (D1541)
ActiveBufferSlot = $0257
;; The record size of the relative file being opened or found.
;; Also: REC (D1541)
RecordSize = $0258
;; The track of the relative file's first side sector.
;; Also: TRKSS (D1541)
SideSectorTrack = $0259
;; Its sector.
;; Also: SECSS (D1541)
SideSectorSector = $025A
;; The last job each data buffer was given, for retries and its drive (Q4).
;; Also: LSTJOB (D1541)
LastJobs = $025B
;; Each channel's directory entry, its sector, to update at CLOSE.
;; Also: DSEC (D1541)
ChannelEntrySector = $0260
;; The entry's offset in that sector.
;; Also: DIND (D1541)
ChannelEntryIndex = $0266
;; The error LED's countdown, which the idle loop toggles the LED by; a command's held error is PendingError, the same
;; byte (Q2).
;; Also: ERWORD (D1541)
ErrorFlash = $026C
;; The LED bit to flash for the error, 0 for none.
;; Also: ERLED (D1541)
ErrorLed = $026D
;; The channel of the file being written.
;; Also: WLINDX (D1541)
WriteChannel = $0270
;; Two bytes: a block count, a file's in the listing or the free total.
;; Also: NBTEMP (D1541)
BlockTotal = $0272
;; The length of the command in the command buffer.
;; Also: CMDSIZ (D1541)
CommandLength = $0274
;; The end of a name in the command buffer, its last index plus one.
;; Also: LIMIT (D1541)
StringEnd = $0276
;; The number of names before "=".
;; Also: F1CNT (D1541)
FirstStreamEnd = $0277
;; The number of names in all.
;; Also: F2CNT (D1541)
SecondStreamEnd = $0278
;; The number of the first name after "=".
;; Also: F2PTR (D1541)
SecondStreamStart = $0279
;; For each file name, where it starts in the command buffer, with the end after the last (6 entries).
;; Also: FILTBL (D1541)
FileNameStart = $027A
;; For each file name, the track of its file's first block once found, 0 if none.
;; Also: FILTRK (D1541)
FileNameTrack = $0280
;; Its sector; the block commands' parameters go here too, as Commands::Parameters (Q2).
;; Also: FILSEC (D1541)
FileNameSector = $0285
;; Counts "*" and "?" while a name is parsed.
;; Also: PATFLG (D1541)
PatternFlag = $028A
;; The drives still to search.
;; Also: DRVCNT (D1541)
DriveSearches = $028C
;; The last drive used without an error, the default.
;; Also: LSTDRV (D1541)
LastDrive = $028E
;; The sector of the first free directory entry seen, 0 if none.
;; Also: DELSEC (D1541)
FreeEntrySector = $0291
;; That entry's offset.
;; Also: DELIND (D1541)
FreeEntryIndex = $0292
;; The offset of the directory entry being looked at.
;; Also: INDEX (D1541)
EntryOffset = $0294
;; The file type a search must match, 0 for any.
;; Also: TYPFLG (D1541)
MatchType = $0296
;; Set to return a job's error to the caller instead of reporting it.
;; Also: JOBRTN (D1541)
JobErrorReturn = $0298
;; The error message, buffer 6, which the error channel reads.
;; Also: ERRBUF (D1541)
ErrorBuffer = $02D5
;; Non-zero to hold off writing the BAM; bit 7 then marks a write pending.
;; Also: WBAM (D1541)
BamWriteDeferred = $02F9
;; Each drive's free blocks, low byte.
;; Also: NDBL (D1541)
FreeBlocks = $02FA
;; The high bytes.
;; Also: NDBH (D1541)
FreeBlocksHigh = $02FC
;; Each drive's request to the controller to step the head a half track: 1 inward, $FF outward. The controller sets 2
;; when it accepts the request and starts the step; the step routine waits for the change, then clears it to 0. (The
;; listing's comment is wrong.)
;; Also: PHASE (D1541)
StepRequest = $02FE
;; Buffer 0, where formatting builds the headers.
;; Also: BUFF0 (D1541)
Buffer0 = $0300
;; The data buffers, buffer n at Buffers + $100 x n (Q4). Defined in both `lccvar` and `ramvarsf`.
;; Also: BUFS (D1541)
Buffers = $0300
;; Buffer 2, where formatting builds a sector's data.
;; Also: BUFF2 (D1541)
Buffer2 = $0500
;; VIA 1's port B, the serial bus: data, clock and ATN in and out, ATN's acknowledge, and the device number's jumpers on
;; PB5-PB6.
;; Also: PB (D1541)
Via1PortB = $1800
;; VIA 1's port A, with CA1's handshake: read only to clear the ATN interrupt.
;; Also: PA1 (D1541)
Via1PortAHandshake = $1801
;; VIA 1's port B direction register.
;; Also: DDRB1 (D1541)
Via1DirectionB = $1802
;; VIA 1's port A direction register.
;; Also: DDRA1 (D1541)
Via1DirectionA = $1803
;; VIA 1's timer 1, low byte: read to clear its flag while formatting times the track.
;; Also: T1LC1 (D1541)
Via1Timer1 = $1804
;; VIA 1's timer 1, high byte: the format's 100 microseconds timer, the EOI wait, the LED's flash and the read's sync
;; timeout.
;; Also: T1HC1 (D1541), TIMER1 (D1541)
Via1Timer1High = $1805
;; VIA 1's timer 1 latch, low byte.
;; Also: T1LL1 (D1541)
Via1Timer1Latch = $1806
;; VIA 1's timer 1 latch, high byte.
;; Also: T1HL1 (D1541)
Via1Timer1LatchHigh = $1807
;; VIA 1's timer 2, low byte (not used).
;; Also: T2LC1 (D1541)
Via1Timer2 = $1808
;; VIA 1's timer 2, high byte (not used).
;; Also: T2HC1 (D1541)
Via1Timer2High = $1809
;; VIA 1's shift register (not used).
;; Also: SR1 (D1541)
Via1Shift = $180A
;; VIA 1's auxiliary control register: the format sets timer 1 free-running.
;; Also: ACR1 (D1541)
Via1AuxiliaryControl = $180B
;; VIA 1's peripheral control register: CA1, the ATN interrupt's edge.
;; Also: PCR1 (D1541)
Via1PeripheralControl = $180C
;; VIA 1's interrupt flags: ATN, and timer 1's timeouts.
;; Also: IFR1 (D1541)
Via1InterruptFlags = $180D
;; VIA 1's interrupt enable register: ATN's interrupt.
;; Also: IER1 (D1541)
Via1InterruptEnable = $180E
;; VIA 1's port A, without handshake (not used; the listing's photo sensor is not read).
;; Also: POTA1 (D1541)
Via1PortA = $180F
;; VIA 2's port B, as the drive's lines: stepper phase in bits 0-1, motor 2, LED 3, write protect 4, density 5-6, sync
;; 7.
;; Also: DSKCNT (D1541), LEDPRT (D1541)
DriveControl = $1C00
;; VIA 2's port A, with handshaking, as the GCR byte read from or written to the disk.
;; Also: DATA2 (D1541)
DiskData = $1C01
;; VIA 2's port B direction register.
;; Also: DDRB2 (D1541), LEDOUT (D1541)
Via2DirectionB = $1C02
;; VIA 2's port A direction register: all out to write, all in to read.
;; Also: DDRA2 (D1541)
Via2DirectionA = $1C03
;; VIA 2's timer 1, low byte: read to clear the controller's interrupt.
;; Also: T1LC2 (D1541)
Via2Timer1 = $1C04
;; VIA 2's timer 1, high byte: the stepper's speeding up and slowing down set the next interrupt's time.
;; Also: T1HC2 (D1541)
Via2Timer1High = $1C05
;; VIA 2's timer 1 latch, low byte.
;; Also: T1LL2 (D1541)
Via2Timer1Latch = $1C06
;; VIA 2's timer 1 latch, high byte: the interrupt's period, IRQ_PERIOD.
;; Also: T1HL2 (D1541)
Via2Timer1LatchHigh = $1C07
;; VIA 2's timer 2, low byte (not used; the listing calls it a latch).
;; Also: T2LL2 (D1541)
Via2Timer2 = $1C08
;; VIA 2's timer 2, high byte (not used).
;; Also: T2LH2 (D1541)
Via2Timer2High = $1C09
;; VIA 2's shift register (not used).
;; Also: SR2 (D1541)
Via2Shift = $1C0A
;; VIA 2's auxiliary control register: timer 1 free-running, port A latched.
;; Also: ACR2 (D1541)
Via2AuxiliaryControl = $1C0B
;; VIA 2's peripheral control register: CA2 lets byte ready reach the 6502's SO pin, CB2 selects reading or writing.
;; Also: PCR2 (D1541)
Via2PeripheralControl = $1C0C
;; VIA 2's interrupt flags: timer 1's, the controller's interrupt.
;; Also: IFR2 (D1541)
Via2InterruptFlags = $1C0D
;; VIA 2's interrupt enable register.
;; Also: IER2 (D1541)
Via2InterruptEnable = $1C0E
;; <ChannelStatus>: nothing more to send, after the last byte.
;; Also: NOTRDY (D1541)
CHANNEL_NOT_READY = 0
;; Drive 1's LED bit in <DriveControl>: the 1541 has no drive 1, so 0, and the masks that include it change nothing.
;; Also: LED1 (D1541)
LED_DRIVE1 = 0
;; <ChannelStatus>'s bit 0: the channel accepts bytes.
;; Also: RDYLST (D1541)
CHANNEL_LISTEN = $01
;; File type 1, SEQ.
;; Also: SEQTYP (D1541)
TYPE_SEQUENTIAL = 1
;; File type 2, PRG.
;; Also: PRGTYP (D1541)
TYPE_PROGRAM = 2
;; File type 3, USR.
;; Also: USRTYP (D1541)
TYPE_USER = 3
;; The command channel's channel number, which secondary address 15 writes to.
;; Also: CMDCHN (D1541)
COMMAND_CHANNEL = 4
;; File type 4, REL.
;; Also: RELTYP (D1541)
TYPE_RELATIVE = 4
;; The five data buffers.
;; Also: BFCNT (D1541)
BUFFER_COUNT = 5
;; The length of the file name tables (<FileNameStart> and the others); ScanFor fails at the fourth comma, so a command
;; gives at most MXFILS-1, four, names.
;; Also: MXFILS (D1541)
FILE_NAME_COUNT = 5
;; The error channel's channel number, which reading secondary address 15 reaches (Q6 for the name).
;; Also: ERRCHN (D1541)
MESSAGE_CHANNEL = 5
;; The five letters of the type tables, D, S, P, U and R or L.
;; Also: NTYPES (D1541)
TYPE_COUNT = 5
;; The seventh entry of <ChannelBuffer> and <ChannelSecondBuffer>, which hold the BAM's buffers.
;; Also: BLINDX (D1541)
BAM_CHANNEL = 6
;; The six channels, the <Channel> tables' length.
;; Also: MXCHNS (D1541)
CHANNEL_COUNT = 6
;; The job queue's six entries, which the controller scans (Q4).
;; Also: NUMJOB (D1541)
JOB_COUNT = 6
;; The file type of a direct-access channel, opened on "#".
;; Also: DIRTYP (D1541)
TYPE_DIRECT = 7
;; The type's bits in a directory entry.
;; Also: TYPMSK (D1541)
TYPE_MASK = 7
;; <ChannelStatus>'s bit 3: set while the byte to send is not the last, so it goes without EOI.
;; Also: EOISND (D1541), EOI (D1541)
CHANNEL_MORE = $08
;; The activity LED's bit in <DriveControl>, PB3.
;; Also: LED0 (D1541)
LED_DRIVE0 = $08
;; The command buffer's pointer's offset in <BufferPositions>, 2 x <BUFFER_COUNT>.
;; Also: CBPTR (D1541)
COMMAND_BUFFER_SLOT = 10
;; 13, RETURN, which ends a command and a relative record's data.
;; Also: CR (D1541)
CARRIAGE_RETURN = $0D
;; Secondary address 15, the command and error channel.
;; Also: CMDSA (D1541)
COMMAND_SECONDARY = 15
;; The internal secondary address the error channel is entered under: reading 15 is switched to it.
;; Also: ERRSA (D1541)
MESSAGE_SECONDARY = 16
;; The offset in a side sector of its data blocks' track-and-sector pairs, after the links to the six side sectors.
;; Also: SSIOFF (D1541)
SIDE_SECTOR_POINTERS = 16
;; The secondary address of the DOS's own read channel (directory and copying).
;; Also: IRSA (D1541)
INTERNAL_READ_SECONDARY = 17
;; The secondary address of the DOS's own write channel.
;; Also: IWSA (D1541)
INTERNAL_WRITE_SECONDARY = 18
;; The highest secondary address in <SecondaryChannels>; higher ones are taken modulo 16. (The listing says one above
;; it.)
;; Also: MAXSA (D1541)
LAST_SECONDARY = 18
;; <ChannelFileType>'s flag for a record written past its size.
;; Also: OVRFLO (D1541)
RELATIVE_OVERFLOW = $20
;; The longest command, 41 characters (the buffer has 42).
;; Also: CMDLEN (D1541)
COMMAND_LENGTH_MAX = 41
;; The BIT absolute opcode, as a byte that skips the next two (K-P3-Q4).
;; Also: SKIP2 (D1541)
OPCODE_BIT = $2C
;; 30 SYNTAX ERROR: the command's form is wrong.
;; Also: BADSYN (D1541)
ERROR_SYNTAX = $30
;; 31 SYNTAX ERROR: no such command.
;; Also: BADCMD (D1541)
ERROR_INVALID_COMMAND = $31
;; 32 SYNTAX ERROR: the command is longer than <COMMAND_LENGTH_MAX>.
;; Also: LONGLN (D1541)
ERROR_LINE_TOO_LONG = $32
;; 33 SYNTAX ERROR: a pattern where a single name is needed.
;; Also: BADFN (D1541)
ERROR_INVALID_NAME = $33
;; 34 SYNTAX ERROR: no file name, or a comma before the colon.
;; Also: NOFILE (D1541)
ERROR_NO_NAME = $34
;; 39 FILE NOT FOUND: the & command's file.
;; Also: NOCFIL (D1541)
ERROR_COMMAND_FILE_NOT_FOUND = $39
;; <ChannelFileType>'s flag for a relative file whose records changed.
;; Also: DYFILE (D1541)
RELATIVE_DIRTY = $40
;; "A", the format of 4040 and 1541 disks, which the BAM holds.
;; Also: FM4040 (D1541)
FORMAT_VERSION = $41
;; 50 RECORD NOT PRESENT.
;; Also: NOREC (D1541)
ERROR_RECORD_NOT_PRESENT = $50
;; 51 OVERFLOW IN RECORD.
;; Also: RECOVF (D1541)
ERROR_RECORD_OVERFLOW = $51
;; 52 FILE TOO LARGE: the side sectors are full.
;; Also: BIGFIL (D1541)
ERROR_FILE_TOO_LARGE = $52
;; 60 WRITE FILE OPEN.
;; Also: FILOPN (D1541)
ERROR_FILE_OPEN = $60
;; 61 FILE NOT OPEN.
;; Also: FILNOP (D1541)
ERROR_FILE_NOT_OPEN = $61
;; 62 FILE NOT FOUND.
;; Also: FLNTFD (D1541)
ERROR_FILE_NOT_FOUND = $62
;; 63 FILE EXISTS.
;; Also: FLEXST (D1541)
ERROR_FILE_EXISTS = $63
;; 64 FILE TYPE MISMATCH.
;; Also: MISTYP (D1541)
ERROR_FILE_TYPE_MISMATCH = $64
;; 65 NO BLOCK: B-A's block is in use.
;; Also: NOBLK (D1541)
ERROR_NO_BLOCK = $65
;; 66 ILLEGAL TRACK OR SECTOR.
;; Also: BADTS (D1541)
ERROR_ILLEGAL_TRACK_SECTOR = $66
;; 67 ILLEGAL TRACK OR SECTOR, the same message as $66 (the message table holds them together): raised by the free-block
;; search for a track beyond the last.
;; Also: SYSTS (D1541)
ERROR_ILLEGAL_SYSTEM_TRACK_SECTOR = $67
;; 70 NO CHANNEL: no free channel or buffer.
;; Also: NOCHNL (D1541)
ERROR_NO_CHANNEL = $70
;; 71 DIR ERROR: the BAM's count and map disagree.
;; Also: DIRERR (D1541)
ERROR_DIRECTORY = $71
;; 72 DISK FULL.
;; Also: DSKFUL (D1541)
ERROR_DISK_FULL = $72
;; 73 CBM DOS V2.6 1541: the start-up message, and the error for writing a disk of another format.
;; Also: CBMV2 (D1541)
ERROR_DOS_VERSION = $73
;; 74 DRIVE NOT READY.
;; Also: NODRIV (D1541)
ERROR_DRIVE_NOT_READY = $74
;; <ChannelStatus>'s bit 7 alone: the channel has one byte left, to send with EOI.
;; Also: EOIOUT (D1541)
CHANNEL_TALK_LAST = $80
;; Job code $80: read the header's block into the buffer.
;; Also: READ (D1541)
JOB_READ = $80
;; <ChannelFileType>'s flag for a relative file at its last record.
;; Also: LRF (D1541)
RELATIVE_LAST_RECORD = $80
;; <ChannelStatus> for a channel both ways whose next byte is the last.
;; Also: RNDEOI (D1541)
CHANNEL_RANDOM_LAST = $81
;; <ChannelStatus> for a channel with more to send.
;; Also: RDYTLK (D1541)
CHANNEL_TALK = $88
;; <ChannelStatus> for a channel both ways, more to send.
;; Also: RNDRDY (D1541)
CHANNEL_RANDOM = $89
;; Job code $90: write the buffer to its header's block.
;; Also: WRITE (D1541)
JOB_WRITE = $90
;; Job code $B0: find the track and read its ID.
;; Also: SEEK (D1541)
JOB_SEEK = $B0
;; Job code $B8: find the header of the job's sector on its track, without reading or writing it; recovery puts it in
;; place of a write.
;; Also: SECSEK (D1541)
JOB_SECTOR_SEEK = $B8
;; Job code $C0: knock the head against track 1's stop to find it.
;; Also: BUMP (D1541)
JOB_BUMP = $C0
;; Job code $D0: run the code in the buffer at once.
;; Also: JUMPC (D1541)
JOB_JUMP = $D0
;; Job code $E0: run the code in the buffer once its track is reached.
;; Also: EXEC (D1541)
JOB_EXECUTE = $E0
.scope Bam
;; Non-zero to stop a changed disk being initialized on its next use; only a memory write sets it.
;; Also: AUTOFG (D1541)
AutoInitializeOff = $0068
;; The free-block search's highest sector on the track. (Q1 for the scope.)
;; Also: LSTSEC (D1541)
LastSector = $024E
;; Each drive's BAM image last used, so the other is swapped out.
;; Also: UBAM (D1541)
LastImage = $029B
;; The track of each of the four BAM images, two a drive, 0 for none.
;; Also: TBAM (D1541)
ImageTracks = $029D
;; Four tracks' BAM entries, four bytes each, held out of the BAM's buffer while they are worked on.
;; Also: BAM (D1541)
Images = $02A1
.endscope
.scope Commands
;; A pointer to <UserCommandVectors>, the U commands' jump table.
;; Also: USRJMP (D1541)
UserVectorsPointer = $006B
;; The file name being set up, or the block command's next parameter.
;; Also: F1PTR (D1541)
NameIndex = $00D3
;; The length of the name being moved from the command buffer.
;; Also: STRSIZ (D1541)
StringLength = $024B
;; The command letter, or the character the parser looks for.
;; Also: CHAR (D1541)
Character = $0275
;; The command's shape as parsed (patterns, several names, drives, names given), checked against its syntax image.
;; Also: IMAGE (D1541)
Structure = $028B
;; V's index in the command table, which the error handler checks.
;; Also: VAL (D1541)
VALIDATE = 0
;; The DOS version, 2, which NEW writes in the BAM beside the format's "A".
;; Also: DOSVER (D1541)
DOS_VERSION = 2
;; The six letters of the block commands' table, A, F, R, W, E and P.
;; Also: NBCMDS (D1541)
BLOCK_SUBCOMMAND_COUNT = 6
;; The first command that the parser tags with names (R, S and N, indexes 9-11 of the command table); C, index 8, parses
;; itself when it copies.
;; Also: PCMD (D1541)
FIRST_PARSED = 9
;; The command table's twelve letters.
;; Also: NCMDS (D1541)
COUNT = 12
;; The index of LOAD's syntax image in the images after the command table's.
;; Also: LDCMD (D1541)
LOAD_STRUCTURE = 12
.endscope
.scope Controller
;; The write-protect sense at the last interrupt, to see it change.
;; Also: LWPT (D1541)
LastWriteProtect = $001E
;; The drive's state: bit 7 the motor coming up to speed, bit 6 stepping, bit 5 on, bit 4 running out before it stops.
;; Also: DRVST (D1541)
DriveStatus = $0020
;; Each drive's head track, 0 when unknown; drive 1's byte, which the 1541 has no use for, is the serial bus's speed
;; flag, <SerialNoDelay>.
;; Also: DRVTRK (D1541)
HeadTrack = $0022
;; A header in GCR: as read, for decoding and comparing, and as built for writing.
;; Also: STAB (D1541)
HeaderGcr = $0024
;; The buffer being encoded to GCR, kept while <DataPointer> moves to the overflow buffer.
;; Also: SAVPNT (D1541)
SavedPointer = $002E
;; The job's buffer, which the controller reads, writes and converts through.
;; Also: BUFPNT (D1541)
DataPointer = $0030
;; The job's header in <JobHeaders>.
;; Also: HDRPNT (D1541)
HeaderPointer = $0032
;; The index of the next GCR byte in the buffer being converted.
;; Also: GCRPNT (D1541)
GcrIndex = $0034
;; The index of the next binary byte in the buffer being converted.
;; Also: BYTCNT (D1541)
ByteIndex = $0036
;; The block ID decoded from a block's first byte, checked against <DataId>.
;; Also: BID (D1541)
BlockId = $0038
;; The ID byte that starts a header, $08.
;; Also: HBID (D1541)
HeaderId = $0039
;; A data block's checksum, the exclusive OR of its bytes.
;; Also: CHKSUM (D1541)
Checksum = $003A
;; The drive of the job being served.
;; Also: DRIVE (D1541)
Drive = $003D
;; The drive whose motor is on, $FF for none.
;; Also: CDRIVE (D1541)
ActiveDrive = $003E
;; The job queue entry being looked at or served.
;; Also: JOBN (D1541)
JobIndex = $003F
;; The track of the job being served, so jobs on it are taken in turn.
;; Also: TRACC (D1541)
JobTrack = $0040
;; The job to seek for next: the last off-track job the scan finds, which is the lowest-numbered since <JobIndex> counts
;; down.
;; Also: NXTJOB (D1541)
SeekJob = $0041
;; That job's distance from the head in tracks, signed.
;; Also: NXTRK (D1541)
SeekDistance = $0042
;; The sectors on the job's track, from its zone.
;; Also: SECTR (D1541)
SectorCount = $0043
;; A work byte: the density bits, then the job code being compared.
;; Also: WORK (D1541)
Work = $0044
;; The job's code without its top bit and drive: $00 read, $10 write, $30 seek, $40 bump...
;; Also: JOB (D1541)
JobCode = $0045
;; The ID byte that starts a data block, $07.
;; Also: DBID (D1541)
DataId = $0047
;; Interrupts until the motor is up to speed (60) or, running out, until it stops (255).
;; Also: ACLTIM (D1541)
MotorTimer = $0048
;; The stack pointer at the controller's start, restored when a job ends.
;; Also: SAVSP (D1541)
SavedStack = $0049
;; The half-track steps still to take, signed: positive inward.
;; Also: STEPS (D1541)
Steps = $004A
;; A work byte: the headers left to search, the stepper's phase bits.
;; Also: TMP (D1541)
Scratch = $004B
;; The distance in sectors of the best job found on this track.
;; Also: CSECT (D1541)
BestDistance = $004C
;; The sector two after the header just read: the first the head can still serve.
;; Also: NEXTS (D1541)
UpcomingSector = $004D
;; The page decoding goes on in when it reaches the end of the first.
;; Also: NXTBF (D1541)
NextPage = $004E
;; The index it goes on at in that page.
;; Also: NXTPNT (D1541)
NextIndex = $004F
;; Set while the buffer holds GCR, so a job's end converts it back.
;; Also: GCRFLG (D1541)
BufferIsGcr = $0050
;; The track being formatted, $FF while no format is under way.
;; Also: FTNUM (D1541)
FormatTrack = $0051
;; Four binary bytes, encoded to five GCR bytes or decoded from them.
;; Also: BTAB (D1541)
BinaryBytes = $0052
;; Eight bytes with two jobs: encoding builds the five GCR bytes in +0..4, decoding extracts the eight 5-bit codes in
;; +0..7, as indexes into the GCR decode tables.
;; Also: GTAB (D1541)
GcrGroup = $0056
;; The steps the stepper takes speeding up, and slowing down (4).
;; Also: AS (D1541)
AccelerationSteps = $005E
;; How much each of those steps shortens or lengthens the step time.
;; Also: AF (D1541)
AccelerationFactor = $005F
;; The steps left in the stepper's phase, or the interrupts left to settle.
;; Also: ACLSTP (D1541)
StepCountdown = $0060
;; The steps at full speed between speeding up and slowing down.
;; Also: RSTEPS (D1541)
RunSteps = $0061
;; The routine the next interrupt's stepping runs: idle, short steps, speeding up, running, slowing down, settling.
;; Also: NXTST (D1541)
StepperState = $0062
;; Below this many steps the stepper doesn't speed up (200). Never true: STEPS is a signed byte, so a job's steps are at
;; most 128 in either direction.
;; Also: MINSTP (D1541)
MinimumAccelerationSteps = $0064
;; The stack page, at the top of page 1: the last <OVERFLOW_SIZE> bytes hold a data block's GCR beyond 256, written from
;; $01BB (69 bytes) and read from $01BA (70 bytes).
;; Also: OVRBUF (D1541)
OverflowBuffer = $0100
;; Formatting: the errors still allowed for the whole format, set to 10 once as it starts and counted down by each
;; error.
;; Also: CNT (D1541)
FormatRetries = $0620
;; Formatting's variables, in buffer 3; the rows after it are its bytes.
;; Also: FMTVAR (D1541)
FormatVariables = $0620
;; Formatting: the bytes of sync, and then of non-sync, written to time the track, adjusted until they match.
;; Also: NUM (D1541)
SegmentLength = $0621
;; Formatting: the tries left to read back a header.
;; Also: TRYS (D1541)
VerifyRetries = $0623
;; Formatting: the bytes the track holds, high byte first.
;; Also: TRAL (D1541)
TrackLength = $0624
;; Formatting: the smallest sector's size, then the gap each sector gets.
;; Also: DTRCK (D1541)
SectorGap = $0626
;; Formatting: the bytes left over, put at the track's end.
;; Also: REMDR (D1541)
GapRemainder = $0627
;; Formatting: the sector being built or checked.
;; Also: SECT (D1541)
FormatSector = $0628
;; GCR decoding: the fourth code's high bit, bit 0 of the second byte.
;; Also: MASK4 (D1541)
CODE4_HIGH = $01
;; Formatting's result when a sync or the gap after it doesn't end within 65,536 counts of the 100 microseconds timer.
;; Also: TOLONG (D1541)
FORMAT_NO_SYNC = 2
;; GCR decoding: the seventh code's high two bits, bits 0-1 of the fourth byte.
;; Also: MASK7 (D1541)
CODE7_HIGH = $03
;; Formatting's result when the bytes counted round the track pass 65,535.
;; Also: TOMANY (D1541)
FORMAT_TRACK_TOO_LONG = 3
;; Formatting's result when the track can't hold its sectors at their smallest size.
;; Also: TOBIG (D1541)
FORMAT_TRACK_TOO_SHORT = 4
;; The smallest gap after a data block that formatting accepts.
;; Also: GAP2 (D1541)
MIN_SECTOR_GAP = 4
;; Formatting's result when the gap left between sectors is under <MIN_SECTOR_GAP>.
;; Also: TOSMAL (D1541)
FORMAT_GAP_TOO_SMALL = 5
;; The $FF bytes written for a sync, 40 one bits.
;; Also: NUMSYN (D1541)
SYNC_LENGTH = 5
;; Formatting's result when checking the written track fails too often.
;; Also: NOTFND (D1541)
FORMAT_VERIFY_FAILED = 6
;; A read is taken if its sector is less than 6 away.
;; Also: RDMAX (D1541)
READ_DISTANCE = 6
;; GCR decoding: the second code's high three bits, bits 0-2 of the first byte.
;; Also: MASK2 (D1541)
CODE2_HIGH = $07
;; A write is taken only if its sector is at least 9 away.
;; Also: WRTMIN (D1541)
WRITE_DISTANCE_MIN = 9
;; The gap after a header, in GCR bytes, that writing a data block waits out (less two): 11 from -03 on, 10 in -01, -02
;; and the 1540.
;; Also: GAP1 (D1541)
.if REVISION < 3 || DRIVE_1540
HEADER_GAP = 10
.else
HEADER_GAP = 11
.endif
;; A write is taken only if its sector is less than 12 away: 9-11 sectors ahead.
;; Also: WRTMAX (D1541)
WRITE_DISTANCE_MAX = 12
;; GCR decoding: the fifth code's high four bits, the third byte's low nibble.
;; Also: MASK5 (D1541)
CODE5_HIGH = $0F
;; GCR decoding: the eighth code, bits 0-4 of the fifth byte.
;; Also: MASK8 (D1541)
CODE8 = $1F
;; VIA 2's timer 1 latch, high byte: 58 x 256 cycles, an interrupt every 14.8 ms, counted from the end of each pass, so
;; times counted in interrupts are minimums. (Not 8 ms, as `lccend` says.)
;; Also: TIM (D1541)
IRQ_PERIOD = 58
;; GCR decoding: the third code, bits 1-5 of the second byte.
;; Also: MASK3 (D1541)
CODE3 = $3E
;; <JOB_BUMP> as <JobCode> holds it, the top bit and drive removed.
;; Also: BUMPC (D1541)
JOB_CODE_BUMP = $40
;; As TOPWRT, which it equals: the read side's name. Reading takes 70 bytes, from $01BA (`ldy #255-TOPRD`), one more
;; than writing.
;; Also: TOPRD (D1541), TOPWRT (D1541)
OVERFLOW_SIZE = 69
;; <JOB_EXECUTE> as <JobCode> holds it.
;; Also: EXECD (D1541)
JOB_CODE_EXECUTE = $60
;; GCR decoding: the sixth code, bits 2-6 of the fourth byte.
;; Also: MASK6 (D1541)
CODE6 = $7C
;; GCR decoding: the fifth code's low bit, bit 7 of the fourth byte.
;; Also: MASK5X (D1541)
CODE5_LOW = $80
;; GCR decoding: the second code's low two bits, bits 6-7 of the second byte.
;; Also: MASK2X (D1541)
CODE2_LOW = $C0
;; GCR decoding: the seventh code's low three bits, bits 5-7 of the fifth byte.
;; Also: MASK7X (D1541)
CODE7_LOW = $E0
;; GCR decoding: the fourth code's low four bits, the third byte's high nibble.
;; Also: MASK4X (D1541)
CODE4_LOW = $F0
;; GCR decoding: the first code, bits 3-7 of the first byte.
;; Also: MASK1 (D1541)
CODE1 = $F8
.endscope

;; Non-zero when the bus may send at the 64's speed, without `Serial::SlowDown`'s 40 microseconds a bit: UI- sets it and
;; UI+ clears it (`Startup::Nmi`, which the 1540 does not have). It is drive 1's <Controller::HeadTrack>, which the
;; listing writes as DRVTRK+1.
SerialNoDelay = Controller::HeadTrack + 1

.scope Directory
;; Used only by the directory code (lookup and trnsfr's listing half): set while the search goes on to the other drive.
;; Also: DRVFLG (D1541)
DriveSearchFlag = $028D
;; Set once every name has been found.
;; Also: FOUND (D1541)
Found = $028F
;; The directory sector being searched.
;; Also: DIRSEC (D1541)
SearchSector = $0290
;; 0 at the directory's last block.
;; Also: LSTBUF (D1541)
LastBlock = $0293
;; The entries left in the directory sector.
;; Also: FILCNT (D1541)
EntriesLeft = $0295
;; The listing line being built. (Q1 for the scope.)
;; Also: NAMBUF (D1541)
ListingLine = $02B1
;; The length of the listing's last line, BLOCKS FREE. (Q1 for the scope.)
;; Also: MSGLEN (D1541)
BLOCKS_FREE_LENGTH = 12
;; <ListingLine>'s starting column for the spacing after a line's block count: 24 for a count below 10, 23 for 10 to 99,
;; and 22 for 100 or more, so the names line up.
;; Also: DIRLEN (D1541)
BLOCK_COUNT_END = 24
;; The listing line's text that is blanked before each entry.
;; Also: NBSIZ (D1541)
LISTING_TEXT_LENGTH = 27
.endscope
.scope Files
;; The first track of the last program loaded, for LOAD "*".
;; Also: PRGTRK (D1541)
LastProgramTrack = $007E
;; The channels in order of use, most recent first, to pick one whose buffer to take.
;; Also: LRUTBL (D1541)
LeastRecentlyUsed = $00FA
;; OPEN's secondary address, kept while it parses.
;; Also: TEMPSA (D1541)
SavedSecondary = $024C
;; The drive of the last program loaded.
;; Also: PRGDRV (D1541)
LastProgramDrive = $026E
;; Its first sector.
;; Also: PRGSEC (D1541)
LastProgramSector = $026F
;; OPEN's mode, one of MODE_ (read 0).
;; Also: MODE (D1541)
Mode = $0297
;; OPEN's mode W, write.
;; Also: WTMODE (D1541)
MODE_WRITE = 1
;; OPEN's mode A, append.
;; Also: APMODE (D1541)
MODE_APPEND = 2
;; OPEN's mode M, modify (read a file not closed).
;; Also: MDMODE (D1541)
MODE_MODIFY = 3
;; The four letters of the mode table, R, W, A and M.
;; Also: NMODES (D1541)
MODE_COUNT = 4
.endscope
.scope Idle
;; Cleared before each command; nothing reads it.
;; Also: NMIFLG (D1541)
NmiDebounce = $0067
.endscope
.scope Jobs
;; A failed job's recovery: bits 0-5 the tries, bit 6 set for no head offsets, bit 7 set to give up without the last
;; bump (CheckBump bumps when it is clear).
;; Also: REVCNT (D1541)
Retries = $006A
;; Recovery: the next entry of the head offset table.
;; Also: EPTR (D1541)
OffsetIndex = $0299
;; Recovery: the head's offset so far, to step it back.
;; Also: TOFF (D1541)
TotalOffset = $029A
.endscope
.scope Relative
;; Four bytes: the record number times the record size plus the offset, the record's place in the file.
;; Also: RESULT (D1541)
Product = $008B
;; Five bytes the multiplication and division work in.
;; Also: ACCUM (D1541)
Accumulator = $008F
;; The most side sectors a relative file has.
;; Also: NSSL (D1541)
SIDE_SECTOR_COUNT = 6
;; The 120 data blocks one side sector lists.
;; Also: NSSP (D1541)
POINTERS_PER_SIDE_SECTOR = 120
.endscope
.scope Serial
;; The drive's LISTEN command, $20 plus the device number from the jumpers.
;; Also: LSNADR (D1541)
ListenAddress = $0077
;; The drive's TALK command, $40 plus the device number.
;; Also: TLKADR (D1541)
TalkAddress = $0078
;; Set while serving ATN, so receiving stops when ATN goes.
;; Also: ATNMOD (D1541)
AtnMode = $007D
;; The bits left to send or receive.
;; Also: CONT (D1541)
BitCount = $0098
;; <Via1PortB>'s bit 0: the bus's data line, read (1 while pulled).
;; Also: DATIN (D1541)
DATA_IN = $01
;; <Via1PortB>'s bit 1: set to pull the data line.
;; Also: DATOUT (D1541)
DATA_OUT = $02
;; <Via1PortB>'s bit 2: the clock line, read.
;; Also: CLKIN (D1541)
CLOCK_IN = $04
;; <Via1PortB>'s bit 3: set to pull the clock line.
;; Also: CLKOUT (D1541)
CLOCK_OUT = $08
;; <Via1PortB>'s bit 4: ATN's acknowledge, which pulls data unless it matches ATN.
;; Also: ATNA (D1541)
ATN_ACKNOWLEDGE = $10
;; The bus's UNLISTEN command.
;; Also: UNLSN (D1541)
UNLISTEN = $3F
;; The bus's UNTALK command.
;; Also: UNTLK (D1541)
UNTALK = $5F
.endscope
.scope Startup
;; <FreeChannels> at reset: channels 0-3 free, the command and error channels taken.
;; Also: LXINT (D1541)
FREE_CHANNELS = $0F
.endscope
