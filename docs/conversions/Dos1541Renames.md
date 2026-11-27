# 1541 DOS rename table

The rename table for the 1541's and 1540's DOS, step 3 of [the method](../ConvertingSources.md): every name in
Commodore's listing of 901229-05 (D1541) and the name the SDK's source gives that address. It is drafted in six parts
(decision D4 of the log, [Dos1541.md](Dos1541.md), which also has the documents and the inventory). Each part opens
with its questions, each with a recommendation and how it was settled; the owner left them to the drafter's judgement
after an independent review of each part (D2), and each outcome is recorded in the log. The rows follow the settled
questions, and give the names the source has.

The columns:

- **#**: the row's number in its part, for reference in reviews.
- **Old**: the name in Commodore's listing (D1541).
- **Address**: where the listing, assembled, puts it (it assembles to 325302-01 and 901229-05 byte for byte), or a
  constant's value.
- **New**: the source's name: a top-level name, a scope member (`Controller::Seek`), a constant (`MAX_CHANNELS`), or
  DROP, an equate the code never uses or a label nothing reaches that marks no data.
- **Kind**: routine (a `.proc`), entry (a label other code enters, listed in its routine's `Entry:`), local,
  location, table or constant.
- **Documents (checked)**: the documents checked to give the old name for this address, by key: the row's `Also:`
  entries. Only D1541 is cited for now (D5).
- **Used in**: the listing's files that use the name, with how many lines: what decides its scope.
- **Reason**: what it holds or does, from the code and what the listing's comments explain; where a comment and the
  code disagree, the code. Each is checked against the code again as it is converted.

## Part 1: the zero page, the RAM, the VIAs and the constants

Settled on 2026-11-27 after an independent review of the part (D2, D7).

The 1541 DOS's declarations: the controller's and the DOS's zero page (`common`, `lccvar`, `ramvarsf`), the RAM at
`$0100-$02FF` and the buffers at `$0300-$07FF`, the format routine's variables in buffer 3, the two VIAs (`$1800`
for the serial bus, `$1C00` for the drive), the ROM's first bytes (`romsf`), and the constants of `equatesf`,
`iodefsf`, `lccvar`, `erproc`, `romtblsf`, `lccgcrbin`, `block` and `trnsfr`. These names are used across the whole
DOS, so the questions settle the scopes, the hardware's names and the shared tables' layouts for every later part.
The draft kinds are corrected: the generator marked every equate below `$C000` a location, but most of `equatesf`,
`iodefsf`, `erproc` and the end of `lccvar` are values, so they are constants here, with their value in the
Address column (`= $30`), as the kernal's table writes them.

### Questions

- D-P1-Q1. **Scopes.** A variable goes in the family whose code uses it; one that two or more families use is top
  level. Startup's setting a variable up at reset (`dskintsf`, `lccinit`) does not count as a use, since it
  initializes nearly everything: `Jobs::Retries` stays in `Jobs` though `dskintsf` sets it. Three of the brief's
  file assignments don't fit their code, and the rows follow the code: `tst2`-`tst4` are the channels' and buffers'
  routines (the LRU table, finding and freeing buffers and channels, reading a channel's next byte), so `Files`, not
  `Directory`; `tstfnd` finds the next free block, so `Bam`; and `trnsfr`'s directory-line routines (GETNAM, BLKNB,
  MSGFRE) build the listing, so `Directory`, while its name transfer (TRNAME, TRCMBF) stays in `Commands`. That is
  why NAMBUF, DIRLEN, NBSIZ and MSGLEN are `Directory`'s and LSTSEC `Bam`'s. *Recommended.* The alternative is the
  brief's assignment as written, which would put the channel routines' names in `Directory`. **Settled:** A variable
  goes in the family whose code uses it and several families' variables are top level; `tst2`-`tst4` are `Files`,
  `tstfnd` is `Bam`, and `trnsfr`'s listing routines are `Directory`, as recommended.
- D-P1-Q2. **Bytes with two jobs.** As K-P1-Q2: where the listing gives a byte two names for two jobs, each job
  gets its own name in its own scope: NBKL and RECL (`$B5`, a sequential file's block count or a relative file's
  record number) are `ChannelBlocks` and `ChannelRecord`, likewise NBKH and RECH. Where it gives one job two names,
  they are one definition with both in `Also:` (TIMER1 and T1HC1, LEDPRT and DSKCNT, LEDOUT and DDRB2, TEMP and T0,
  EOI and EOISND, TOPRD and TOPWRT). Where one name has two jobs, the definition is named for the main job, and the
  conversion adds a second name for the other, defined from it with a `;;` comment (no old name of its own):
  ERWORD is `ErrorFlash`, and the command's held error is `PendingError = ErrorFlash`; DRVTRK is
  `Controller::HeadTrack`, and drive 1's byte, which the NMI's UI+ and UI- patch makes the serial bus's speed flag,
  is `SerialNoDelay = Controller::HeadTrack + 1`; FILSEC is `FileNameSector`, and the block commands' numeric
  parameters, which the parser leaves there, are `Commands::Parameters = FileNameSector`; TOPWRT is
  `Controller::OVERFLOW_SIZE`, and the three stack resets that load it are `STACK_START = Controller::OVERFLOW_SIZE`.
  *Recommended.* **Settled:** each job of a two-job byte gets its own name in its own scope, and one-job synonyms share
  one definition with `Also:`, as recommended.
- D-P1-Q3. **The VIAs' registers.** As K-P1-Q3: each register is a location named for the chip and the register,
  `Via1` for `$1800` (the serial bus) and `Via2` for `$1C00` (the drive), with the listing's names in `Also:`
  (`Via1PortB`, PB; `Via2Timer1LatchHigh`, T1HL2). The listing's register names that say a job are aliases named
  for it, with `Inherit:`: DSKCNT and LEDPRT, both `$1C00`, are `DriveControl` (an alias of `Via2PortB`: stepper
  phases, motor, LED, write protect, density, sync), and DATA2 is `DiskData` (an alias of `Via2PortAHandshake`,
  the GCR byte read or written). TIMER1 is a second name for `Via1Timer1High`, and LEDOUT one for
  `Via2DirectionB`, with no job of their own. The unused registers stay, since the list describes the chip; the
  listing has no `$1C0F`, which the conversion adds as `Via2PortA` with no old name. *Recommended.* The alternative
  is `Via2PortB` everywhere, as the kernal writes its serial port; but the drive code reads far better as
  `DriveControl`, and the listing names the port for that job. **Settled:** VIA registers are named for chip and
  register with the listing's names in `Also:`, and the job-named aliases `DriveControl` and `DiskData` stand, as
  recommended.
- D-P1-Q4. **The job queue and the buffers.** The job queue is `JobQueue` (`$00`), `JOB_COUNT` bytes, one per
  buffer: a job code (`JOB_READ` `$80` to `JOB_EXECUTE` `$E0`, the drive in bit 0), which the controller replaces
  with a result below `$80` (1 for success, 2-11 for the errors reported as 20-29). Job n's header is at
  `JobHeaders + 2 × n`, the track then the sector (the listing's `4/12` comments mark where an older DOS's 8-byte
  headers were cut to 2). `LastJobs` (`$025B`) keeps the last job each of the `BUFFER_COUNT` (5) data buffers was
  given, for retries and to know its drive. Buffer n is at `Buffers + $100 × n` (`$0300-$07FF`); the job queue's
  sixth entry has no RAM behind it. `BufferPositions` (`$99`) holds a pointer per buffer, 7 of them: the five data
  buffers, then the command buffer (buffer 5, `CommandPointer` at `+COMMAND_BUFFER_SLOT`) and the error buffer
  (buffer 6). They stay arrays with the stride in each one's comment, not structs, since the code indexes them by
  shifting the buffer number. *Recommended.* The job result codes are literal numbers in the listing; they get
  `JOB_*` constants in the controller's part, and the format errors here (`Controller::FORMAT_*`) are among them.
  **Settled:** `JobQueue`, `JobHeaders`, `LastJobs`, `Buffers` and `BufferPositions` stay arrays with strides in their
  comments, as recommended.
- D-P1-Q5. **The per-channel tables.** The tables indexed by the channel number in `Channel` (LINDX, 0-5) are top
  level, each `Channel` and its field: `ChannelBuffer` and `ChannelSecondBuffer` (BUF0, BUF1, the buffer numbers,
  bit 7 for inactive and bit 6 for dirty; 7 entries, the seventh `BAM_CHANNEL`'s), `ChannelByte` (CHNDAT),
  `ChannelLastByte` (LSTCHR), `ChannelStatus` (CHNRDY), `ChannelFileType` (FILTYP), `ChannelEntrySector` and
  `ChannelEntryIndex` (DSEC, DIND), and the relative files' `ChannelRecord`, `ChannelNextRecord`,
  `ChannelRecordSize` and `ChannelSideSector`, which `Files`' OPEN and channel code set up too. `SecondaryChannels`
  (LINTAB) maps a secondary address to its channel. The parser's tables indexed by a file name's number (0-4) are
  likewise `FileName` and the field (`FileNameStart`, `FileNameDrive`, `FileNamePattern`, `FileNameTrack`...).
  *Recommended.* The alternative, a struct per channel, does not fit: each table is a separate array in memory.
  **Settled:** the per-channel and per-file-name tables are top level, named `Channel` or `FileName` plus the field, as
  recommended.
- D-P1-Q6. **The constant sets.** Prefixed constants, one prefix per set, top level where several families use the
  set: `ERROR_*` for the DOS's error numbers (each written in hex as the decimal number it prints: `ERROR_SYNTAX =
  $30` is 30), `TYPE_*` for file types, `JOB_*` for job codes, `CHANNEL_*` for `ChannelStatus`'s bits, `RELATIVE_*`
  for the flags in `ChannelFileType`, `LED_*`. Sets one family uses are in its scope: `Files::MODE_*`,
  `Serial::DATA_IN` and the bus's other bits, `Controller::FORMAT_*`, the GCR masks. The error channel's constants
  are `MESSAGE_CHANNEL` and `MESSAGE_SECONDARY`, so nothing named `ERROR_` is not an error number. *Recommended.*
  **Settled:** prefixed constant sets are top level where several families use them and scoped otherwise, as
  recommended.
- D-P1-Q7. **23 declarations are dropped**, as K-P1-Q6: the zero-page bytes nothing uses (ACTJOB, GCRERR, BITCNT,
  HINIB, BYTE, CTRACK, ADRSED, ICMD, MYPA) and RLINDX; the equates nothing uses (RDMODE, LISNER, TALKER, VERERR,
  FM2030, JMPC, WVERFY, FBUFS, BUFF1); the end markers ZPEND and RAMEND; and ZP2 and ROM, used only as the
  assembler's origins. The unused bytes keep their places with `.res`, and the layout's comment names them in prose.
  The seven unused VIA registers stay (Q3), and so do CCHKSM and FREEC0, which mark ROM bytes the conversion must
  emit. *Recommended.* **Settled:** the 23 declarations are dropped and named in prose, and the seven unused VIA
  registers, CCHKSM and FREEC0 stay, as recommended.
- D-P1-Q8. **Wrong comments.** The rows say what the code does where the listing's comments disagree: the
  controller's interrupt comes every 14.8 ms (TIM, 58 × 256 cycles), not the 8 ms `lccend` says, so the settle time
  is 5 × 14.8 ms and the motor's run-out 255 interrupts; MAXSA is the highest secondary address, not one above it;
  POTA1 (`$180F`) is not read; the `$1C08`-`$1C09` names say latch but the registers are timer 2's counter.
  *Recommended.* **Settled:** the rows say what the code does where the listing's comments disagree, including the 14.8
  ms interrupt, MAXSA, POTA1, the `$1C08` timer 2 names, PHASE's direction and SYSTS's message, as recommended.

### Rows

| # | Old | Address | New | Kind | Documents (checked) | Used in | Reason |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | JOBS | $0000 | JobQueue | location | D1541 | jobssf 9, tst3 3, duplct 2, lcccntrl 2, lccwrt 2, block 1, idlesf 1, lccutil 1 | The job queue, a byte per buffer: the job code with the drive in bit 0, which the controller replaces with a result below $80 when it is done (Q4). |
| 2 | LED1 | = 0 | LED_DRIVE1 | constant | D1541 | leds 3, dskintsf 3, idlesf 1, romtblsf 1 | Drive 1's LED bit in DriveControl: the 1541 has no drive 1, so 0, and the masks that include it change nothing. |
| 3 | NOTRDY | = 0 | CHANNEL_NOT_READY | constant | D1541 | tst4 1 | ChannelStatus: nothing more to send, after the last byte. |
| 4 | SEQTYP | = 1 | TYPE_SEQUENTIAL | constant | D1541 | open 3 | File type 1, SEQ. |
| 5 | WTMODE | = 1 | Files::MODE_WRITE | constant | D1541 | open 2 | OPEN's mode W, write. |
| 6 | DOSVER | = 2 | Commands::DOS_VERSION | constant | D1541 | new 1 | The DOS version, 2, which NEW writes in the BAM beside the format's "A". |
| 7 | PRGTYP | = 2 | TYPE_PROGRAM | constant | D1541 | open 5, rename 1 | File type 2, PRG. |
| 8 | TOLONG | = 2 | Controller::FORMAT_NO_SYNC | constant | D1541 | lccfmt1 2 | Formatting's result when a sync or the gap after it doesn't end within 65,536 counts of the 100 µs timer. |
| 9 | TOMANY | = 3 | Controller::FORMAT_TRACK_TOO_LONG | constant | D1541 | lccfmt1 1 | Formatting's result when the bytes counted round the track pass 65,535. |
| 10 | USRTYP | = 3 | TYPE_USER | constant | D1541 | utlodr 1 | File type 3, USR. |
| 11 | CMDCHN | = 4 | COMMAND_CHANNEL | constant | D1541 | tst2 3, dskintsf 3 | The command channel's channel number, which secondary address 15 writes to. |
| 12 | NMODES | = 4 | Files::MODE_COUNT | constant | D1541 | open 1 | The four letters of the mode table, R, W, A and M. |
| 13 | TOBIG | = 4 | Controller::FORMAT_TRACK_TOO_SHORT | constant | D1541 | lccfmt2 1 | Formatting's result when the track can't hold its sectors at their smallest size. |
| 14 | ERRCHN | = 5 | MESSAGE_CHANNEL | constant | D1541 | erproc 3, dskintsf 3, tst4 2, memrw 1 | The error channel's channel number, which reading secondary address 15 reaches (Q6 for the name). |
| 15 | MXFILS | = 5 | FILE_NAME_COUNT | constant | D1541 | parsex 2, block 1 | The most file names a command may give: the FileName tables' length. |
| 16 | NTYPES | = 5 | TYPE_COUNT | constant | D1541 | setdrv 1, open 1 | The five letters of the type tables, D, S, P, U and R or L. |
| 17 | NUMSYN | = 5 | Controller::SYNC_LENGTH | constant | D1541 | lccfmt2 2, lccwrt 1 | The $FF bytes written for a sync, 40 one bits. |
| 18 | TOSMAL | = 5 | Controller::FORMAT_GAP_TOO_SMALL | constant | D1541 | lccfmt2 1 | Formatting's result when the gap left between sectors is under MIN_SECTOR_GAP. |
| 19 | BLINDX | = 6 | BAM_CHANNEL | constant | D1541 | dskintsf 2, tst2 1, frets 1 | The seventh entry of ChannelBuffer and ChannelSecondBuffer, which hold the BAM's buffers. |
| 20 | HDRS | $0006 | JobHeaders | location | D1541 | jobssf 6, tsutil 2, erproc 2, frets 2, lcccntrl 1 | The jobs' headers, two bytes a buffer, the track then the sector (Q4). |
| 21 | NBCMDS | = 6 | Commands::BLOCK_SUBCOMMAND_COUNT | constant | D1541 | block 1 | The six letters of the block commands' table, A, F, R, W, E and P. |
| 22 | NOTFND | = 6 | Controller::FORMAT_VERIFY_FAILED | constant | D1541 | lccfmt3 1 | Formatting's result when checking the written track fails too often. |
| 23 | NUMJOB | = 6 | JOB_COUNT | constant | D1541 | lcccntrl 2, lccseek 1 | The job queue's six entries, which the controller scans (Q4). |
| 24 | DIRTYP | = 7 | TYPE_DIRECT | constant | D1541 | block 2, tst4 1, close 1 | The file type of a direct-access channel, opened on "#". |
| 25 | EOISND | = $08 | CHANNEL_MORE | constant | D1541 | rename 2, tst4 1 | ChannelStatus's bit 3: set while the byte to send is not the last, so it goes without EOI. |
| 26 | LED0 | = $08 | LED_DRIVE0 | constant | D1541 | leds 3, dskintsf 3, idlesf 2, romtblsf 1 | The activity LED's bit in DriveControl, PB3. |
| 27 | GAP1 | = 11 | Controller::HEADER_GAP | constant | D1541 | lccwrt 1, lccfmt2 1 | The gap after a header, in GCR bytes, that writing a data block waits out (less two). |
| 28 | LDCMD | = 12 | Commands::LOAD_STRUCTURE | constant | D1541 | open 1 | The index of LOAD's syntax image in the images after the command table's. |
| 29 | MSGLEN | = 12 | Directory::BLOCKS_FREE_LENGTH | constant | D1541 | trnsfr 1 | The length of the listing's last line, BLOCKS FREE. (Q1 for the scope.) |
| 30 | CR | = $0D | CARRIAGE_RETURN | constant | D1541 | parsex 2, tst4 1, close 1, rel1 1, rel3 1 | 13, RETURN, which ends a command and a relative record's data. |
| 31 | CMDSA | = 15 | COMMAND_SECONDARY | constant | D1541 | tst2 1, dskintsf 1 | Secondary address 15, the command and error channel. |
| 32 | LXINT | = $0F | Startup::FREE_CHANNELS | constant | D1541 | dskintsf 1 | FreeChannels at reset: channels 0-3 free, the command and error channels taken. |
| 33 | ERRSA | = 16 | MESSAGE_SECONDARY | constant | D1541 | tst2 1, dskintsf 1 | The internal secondary address the error channel is entered under: reading 15 is switched to it. |
| 34 | SSIOFF | = 16 | SIDE_SECTOR_POINTERS | constant | D1541 | addrel 3, newss 3, opnchnl 2, close 1, ssend 1 | The offset in a side sector of its data blocks' track-and-sector pairs, after the links to the six side sectors. |
| 35 | IRSA | = 17 | INTERNAL_READ_SECONDARY | constant | D1541 | rename 4, tst4 2, open 2, trnsfr 1, addfil 1 | The secondary address of the DOS's own read channel (directory and copying). |
| 36 | DSKID | $0012 | DiskId | location | D1541 | new 4, lccseek 4, tst2 2, lccread 2, lccfmt2 2 | Each drive's disk ID, two bytes, which the controller checks every header against. |
| 37 | IWSA | = 18 | INTERNAL_WRITE_SECONDARY | constant | D1541 | rename 4, tst4 2, tst2 1 | The secondary address of the DOS's own write channel. |
| 38 | MAXSA | = 18 | LAST_SECONDARY | constant | D1541 | tst2 2, tstflg 1, dskintsf 1 | The highest secondary address in SecondaryChannels; higher ones are taken modulo 16. (The listing says one above it.) |
| 39 | HEADER | $0016 | LastHeader | location | D1541 | lccseek 12, lccread 9, lccconhdr 5, tst2 2 | The last header read, in binary: the ID's two bytes, the track, the sector and the checksum. |
| 40 | DIRLEN | = 24 | Directory::LISTING_LINE_LENGTH | constant | D1541 | trnsfr 3 | The length of a listing line built in ListingLine. |
| 41 | ACTJOB | $001B | DROP | location | D1541 | none | The controller's active job; not used. Named in prose. |
| 42 | NBSIZ | = 27 | Directory::LISTING_TEXT_LENGTH | constant | D1541 | trnsfr 1 | The listing line's text that is blanked before each entry. |
| 43 | WPSW | $001C | DiskChanged | location | D1541 | dskintsf 2, idlesf 2, lookup 1, tst2 1, lccend 1 | Each drive's flag, set by the controller when the write-protect sense changes (a disk going in or out); the DOS reinitializes. |
| 44 | LWPT | $001E | Controller::LastWriteProtect | location | D1541 | lccend 2 | The write-protect sense at the last interrupt, to see it change. |
| 45 | DRVST | $0020 | Controller::DriveStatus | location | D1541 | lccend 5, lcccntrl 4, lccutil 3, lccfmt1 1 | The drive's state: bit 7 the motor coming up to speed, bit 6 stepping, bit 5 on, bit 4 running out before it stops. |
| 46 | OVRFLO | = $20 | RELATIVE_OVERFLOW | constant | D1541 | rel2 4, rel1 2, tst2 1, record 1 | ChannelFileType's flag for a record written past its size. |
| 47 | DRVTRK | $0022 | Controller::HeadTrack | location | D1541 | lcccntrl 3, sertalk 1, lccseek 1, lccfmt1 1, vector 1 | Each drive's head track, 0 when unknown; drive 1's byte is the serial bus's speed flag, SerialNoDelay (Q2). |
| 48 | STAB | $0024 | Controller::HeaderGcr | location | D1541 | lccseek 5, lccconhdr 2, lccread 1 | A header in GCR: as read, for decoding and comparing, and as built for writing. |
| 49 | CMDLEN | = 41 | COMMAND_LENGTH_MAX | constant | D1541 | parsex 2, tst2 1 | The longest command, 41 characters (the buffer has 42). |
| 50 | SAVPNT | $002E | Controller::SavedPointer | location | D1541 | lccwrt 13, lccbingcr 10, lccgcrbin 10, lccfmt4 6, lccconhdr 2 | The buffer being encoded to GCR, kept while DataPointer moves to the overflow buffer. |
| 51 | BADSYN | = $30 | ERROR_SYNTAX | constant | D1541 | parsex 1, copset 1, block 1, open 1 | 30 SYNTAX ERROR: the command's form is wrong. |
| 52 | BUFPNT | $0030 | Controller::DataPointer | location | D1541 | lccwrt 16, lccgcrbin 16, lccbingcr 9, lccseek 7, lcccntrl 5, lccfmt3 5, lccfmt4 4, lccconhdr 3, lccfmt2 3, lccread 1 | The job's buffer, which the controller reads, writes and converts through. |
| 53 | BADCMD | = $31 | ERROR_INVALID_COMMAND | constant | D1541 | parsex 1, duplct 1, memrw 1, block 1 | 31 SYNTAX ERROR: no such command. |
| 54 | HDRPNT | $0032 | Controller::HeaderPointer | location | D1541 | lcccntrl 4, lccfmt2 4, lccseek 2, lccread 2, lccfmt1 2 | The job's header in JobHeaders. |
| 55 | LONGLN | = $32 | ERROR_LINE_TOO_LONG | constant | D1541 | parsex 1 | 32 SYNTAX ERROR: the command is longer than COMMAND_LENGTH_MAX. |
| 56 | BADFN | = $33 | ERROR_INVALID_NAME | constant | D1541 | open 1, new 1 | 33 SYNTAX ERROR: a pattern where a single name is needed. |
| 57 | GCRPNT | $0034 | Controller::GcrIndex | location | D1541 | lccbingcr 3, lccgcrbin 3, lccseek 1, lccwrt 1, lccconhdr 1, lccfmt4 1 | The index of the next GCR byte in the buffer being converted. |
| 58 | NOFILE | = $34 | ERROR_NO_NAME | constant | D1541 | parsex 1 | 34 SYNTAX ERROR: no file name, or a comma before the colon. |
| 59 | GCRERR | $0035 | DROP | location | D1541 | none | A GCR decoding error flag; not used. Named in prose. |
| 60 | BYTCNT | $0036 | Controller::ByteIndex | location | D1541 | lccwrt 8, lccbingcr 4, lccgcrbin 4, lccfmt4 3 | The index of the next binary byte in the buffer being converted. |
| 61 | BITCNT | $0037 | DROP | location | D1541 | none | Not used. Named in prose. |
| 62 | BID | $0038 | Controller::BlockId | location | D1541 | lccread 1, lccwrt 1, lccgcrbin 1 | The block ID decoded from a block's first byte, checked against DataId. |
| 63 | HBID | $0039 | Controller::HeaderId | location | D1541 | lccinit 1, lccconhdr 1, lccfmt2 1 | The ID byte that starts a header, $08. |
| 64 | NOCFIL | = $39 | ERROR_COMMAND_FILE_NOT_FOUND | constant | D1541 | utlodr 1 | 39 FILE NOT FOUND: the & command's file. |
| 65 | CHKSUM | $003A | Controller::Checksum | location | D1541 | lccwrt 2, lccread 1, lccbingcr 1, lccgcrbin 1, lccfmt2 1 | A data block's checksum, the exclusive OR of its bytes. |
| 66 | TIM | = 58 | Controller::IRQ_PERIOD | constant | D1541 | lccinit 1 | VIA 2's timer 1 latch, high byte: 58 × 256 cycles, an interrupt every 14.8 ms, counted from the end of each pass, so times counted in interrupts are minimums. (Not 8 ms, as `lccend` says.) |
| 67 | HINIB | $003B | DROP | location | D1541 | none | Not used. Named in prose. |
| 68 | BYTE | $003C | DROP | location | D1541 | none | Not used. Named in prose. |
| 69 | DRIVE | $003D | Controller::Drive | location | D1541 | lcccntrl 4, setdrv 1, lccread 1, lccfmt1 1, lccfmt2 1 | The drive of the job being served. |
| 70 | CDRIVE | $003E | Controller::ActiveDrive | location | D1541 | lccseek 3, lcccntrl 2, lccend 2, lccinit 1, lccutil 1 | The drive whose motor is on, $FF for none. |
| 71 | JOBN | $003F | Controller::JobIndex | location | D1541 | lcccntrl 6, lccseek 4, lccwrt 1, lccutil 1 | The job queue entry being looked at or served. |
| 72 | DYFILE | = $40 | RELATIVE_DIRTY | constant | D1541 | close 1, rel2 1 | ChannelFileType's flag for a relative file whose records changed. |
| 73 | TRACC | $0040 | Controller::JobTrack | location | D1541 | lcccntrl 1, lccseek 1 | The track of the job being served, so jobs on it are taken in turn. |
| 74 | NXTJOB | $0041 | Controller::SeekJob | location | D1541 | lcccntrl 2 | The job to seek for next: the last off-track job the scan finds, which is the lowest-numbered since JobIndex counts down. |
| 75 | NXTRK | $0042 | Controller::SeekDistance | location | D1541 | lcccntrl 3 | That job's distance from the head in tracks, signed. |
| 76 | SECTR | $0043 | Controller::SectorCount | location | D1541 | lccfmt2 4, lccseek 3, lcccntrl 1, lccfmt3 1 | The sectors on the job's track, from its zone. |
| 77 | WORK | $0044 | Controller::Work | location | D1541 | lcccntrl 2, lccseek 1 | A work byte: the density bits, then the job code being compared. |
| 78 | JOB | $0045 | Controller::JobCode | location | D1541 | lccseek 4, lcccntrl 2 | The job's code without its top bit and drive: $00 read, $10 write, $30 seek, $40 bump... |
| 79 | TOPRD | = 69 | Controller::OVERFLOW_SIZE | constant | D1541 | lccread 1, lccgcrbin 1 | As TOPWRT, which it equals: the read side's name. Reading takes 70 bytes, from $01BA (`ldy #255-TOPRD`), one more than writing. |
| 80 | TOPWRT | = 69 | Controller::OVERFLOW_SIZE | constant | D1541 | lccwrt 5, lccfmt4 2, erproc 1, seratn 1, dskintsf 1, lccbingcr 1, lccfmt2 1, lccfmt3 1 | The 69 GCR bytes of a data block beyond 256, kept at the top of the stack page: written from $01BB (256 - TOPWRT, 69 bytes); the stack resets load it too, as STACK_START (Q2). |
| 81 | CTRACK | $0046 | DROP | location | D1541 | none | Not used. Named in prose. |
| 82 | DBID | $0047 | Controller::DataId | location | D1541 | lccinit 1, lccread 1, lccbingcr 1 | The ID byte that starts a data block, $07. |
| 83 | ACLTIM | $0048 | Controller::MotorTimer | location | D1541 | lccutil 2, lccend 1 | Interrupts until the motor is up to speed (60) or, running out, until it stops (255). |
| 84 | SAVSP | $0049 | Controller::SavedStack | location | D1541 | lcccntrl 1, lccutil 1 | The stack pointer at the controller's start, restored when a job ends. |
| 85 | STEPS | $004A | Controller::Steps | location | D1541 | lccend 6, lcccntrl 3, lccfmt1 1 | The half-track steps still to take, signed: positive inward. |
| 86 | TMP | $004B | Controller::Scratch | location | D1541 | lccseek 2, lccend 2 | A work byte: the headers left to search, the stepper's phase bits. |
| 87 | CSECT | $004C | Controller::BestDistance | location | D1541 | lccseek 3 | The distance in sectors of the best job found on this track. |
| 88 | NEXTS | $004D | Controller::UpcomingSector | location | D1541 | lccseek 2 | The sector two after the header just read: the first the head can still serve. |
| 89 | NXTBF | $004E | Controller::NextPage | location | D1541 | lccgcrbin 3, lccwrt 1 | The page decoding goes on in when it reaches the end of the first. |
| 90 | NXTPNT | $004F | Controller::NextIndex | location | D1541 | lccgcrbin 3, lccwrt 1 | The index it goes on at in that page. |
| 91 | GCRFLG | $0050 | Controller::BufferIsGcr | location | D1541 | lccwrt 1, lccbingcr 1, lccutil 1, lccfmt3 1, lccfmt4 1 | Set while the buffer holds GCR, so a job's end converts it back. |
| 92 | NOREC | = $50 | ERROR_RECORD_NOT_PRESENT | constant | D1541 | open 1, rel3 1, addrel 1, utlodr 1 | 50 RECORD NOT PRESENT. |
| 93 | FTNUM | $0051 | Controller::FormatTrack | location | D1541 | lccfmt3 3, lccfmt1 2, lccinit 1, lccfmt2 1, lccfmt4 1 | The track being formatted, $FF while no format is under way. |
| 94 | RECOVF | = $51 | ERROR_RECORD_OVERFLOW | constant | D1541 | record 2, rel2 1, utlodr 1 | 51 OVERFLOW IN RECORD. |
| 95 | BIGFIL | = $52 | ERROR_FILE_TOO_LARGE | constant | D1541 | addrel 1 | 52 FILE TOO LARGE: the side sectors are full. |
| 96 | BTAB | $0052 | Controller::BinaryBytes | location | D1541 | lccbingcr 19, lccwrt 14, lccgcrbin 13, lccconhdr 8, lccseek 5, lccfmt4 4 | Four binary bytes, encoded to five GCR bytes or decoded from them. |
| 97 | GTAB | $0056 | Controller::GcrGroup | location | D1541 | lccgcrbin 24, lccbingcr 19 | Eight bytes with two jobs: encoding builds the five GCR bytes in +0..4, decoding extracts the eight 5-bit codes in +0..7, as indexes into the GCR decode tables. |
| 98 | AS | $005E | Controller::AccelerationSteps | location | D1541 | lccend 4, lccinit 1 | The steps the stepper takes speeding up, and slowing down (4). |
| 99 | AF | $005F | Controller::AccelerationFactor | location | D1541 | lccend 2, lccinit 1 | How much each of those steps shortens or lengthens the step time. |
| 100 | ACLSTP | $0060 | Controller::StepCountdown | location | D1541 | lccend 7 | The steps left in the stepper's phase, or the interrupts left to settle. |
| 101 | FILOPN | = $60 | ERROR_FILE_OPEN | constant | D1541 | open 1 | 60 WRITE FILE OPEN. |
| 102 | FILNOP | = $61 | ERROR_FILE_NOT_OPEN | constant | D1541 | tst2 1 | 61 FILE NOT OPEN. |
| 103 | RSTEPS | $0061 | Controller::RunSteps | location | D1541 | lccend 2 | The steps at full speed between speeding up and slowing down. |
| 104 | FLNTFD | = $62 | ERROR_FILE_NOT_FOUND | constant | D1541 | rename 1, open 1 | 62 FILE NOT FOUND. |
| 105 | NXTST | $0062 | Controller::StepperState | location | D1541 | lccend 15, lccinit 2 | The routine the next interrupt's stepping runs: idle, short steps, speeding up, running, slowing down, settling. |
| 106 | FLEXST | = $63 | ERROR_FILE_EXISTS | constant | D1541 | rename 1, open 1 | 63 FILE EXISTS. |
| 107 | MINSTP | $0064 | Controller::MinimumAccelerationSteps | location | D1541 | lccinit 1, lccend 1 | Below this many steps the stepper doesn't speed up (200). Never true: STEPS is a signed byte, so a job's steps are at most 128 in either direction. |
| 108 | MISTYP | = $64 | ERROR_FILE_TYPE_MISMATCH | constant | D1541 | rename 1, open 1, record 1 | 64 FILE TYPE MISMATCH. |
| 109 | NOBLK | = $65 | ERROR_NO_BLOCK | constant | D1541 | block 2 | 65 NO BLOCK: B-A's block is in use. |
| 110 | VNMI | $0065 | NmiVector | location | D1541 | dskintsf 2, vector 1 | The NMI's vector, which the UI command jumps through. |
| 111 | BADTS | = $66 | ERROR_ILLEGAL_TRACK_SECTOR | constant | D1541 | jobssf 1 | 66 ILLEGAL TRACK OR SECTOR. |
| 112 | NMIFLG | $0067 | Idle::NmiDebounce | location | D1541 | idlesf 1 | Cleared before each command; nothing reads it. |
| 113 | SYSTS | = $67 | ERROR_ILLEGAL_SYSTEM_TRACK_SECTOR | constant | D1541 | tstfnd 1 | 67 ILLEGAL TRACK OR SECTOR, the same message as $66 (the message table holds them together): raised by the free-block search for a track beyond the last. |
| 114 | AUTOFG | $0068 | Bam::AutoInitializeOff | location | D1541 | lookup 1 | Non-zero to stop a changed disk being initialized on its next use; only a memory write sets it. |
| 115 | SECINC | $0069 | SectorInterleave | location | D1541 | tst4 3, dskintsf 1, tstfnd 1 | The sectors between a file's blocks that the free-block search skips. |
| 116 | REVCNT | $006A | Jobs::Retries | location | D1541 | jobssf 3, dskintsf 1 | A failed job's recovery: bits 0-5 the tries, bit 6 set for no head offsets, bit 7 for a last bump. |
| 117 | USRJMP | $006B | Commands::UserVectorsPointer | location | D1541 | block 4 | A pointer to UserCommandVectors, the U commands' jump table. |
| 118 | BMPNT | $006D | BamPointer | location | D1541 | frets 12, map 7, tstfnd 5, new 2, tst2 1 | A pointer to the BAM entry of the track being allocated or freed. |
| 119 | T0 | $006F | Temporary | location | D1541 | tst3 5, frets 4, map 3 | As TEMP: its first byte's second name. |
| 120 | TEMP | $006F | Temporary | location | D1541 | block 25, tstfnd 11, lookup 10, memrw 9, ssutil 9, idlesf 9, fndrel 7, tst4 6, ramvarsf 5, tstflg 5, frets 4, parsex 3, tst3 3, dskintsf 3, tst2 2, close 2, trnsfr 1 | Six bytes of temporaries every family uses; routines name their uses by scoped aliases. |
| 121 | NOCHNL | = $70 | ERROR_NO_CHANNEL | constant | D1541 | block 2, tst2 2, tst3 2, record 1, frets 1 | 70 NO CHANNEL: no free channel or buffer. |
| 122 | T1 | $0070 | Temporary1 | location | D1541 | frets 8, lccfmt1 6, addrel 3, close 2, ssutil 2, getact 2, map 2 | Temporary's second byte. |
| 123 | DIRERR | = $71 | ERROR_DIRECTORY | constant | D1541 | tstfnd 2 | 71 DIR ERROR: the BAM's count and map disagree. |
| 124 | T2 | $0071 | Temporary2 | location | D1541 | lccfmt1 4, close 2, addrel 2, map 2, ssutil 1 | Temporary's third byte. |
| 125 | DSKFUL | = $72 | ERROR_DISK_FULL | constant | D1541 | frets 1, tstfnd 1 | 72 DISK FULL. |
| 126 | T3 | $0072 | Temporary3 | location | D1541 | close 1, ssutil 1, addrel 1 | Temporary's fourth byte. |
| 127 | CBMV2 | = $73 | ERROR_DOS_VERSION | constant | D1541 | jobssf 1 | 73 CBM DOS V2.6 1541: the start-up message, and the error for writing a disk of another format. |
| 128 | T4 | $0073 | Temporary4 | location | D1541 | close 2, ssutil 1, addrel 1 | Temporary's fifth byte. |
| 129 | NODRIV | = $74 | ERROR_DRIVE_NOT_READY | constant | D1541 | lookup 1, erproc 1, frets 1 | 74 DRIVE NOT READY. |
| 130 | IP | $0075 | Pointer | location | D1541 | dskintsf 15, block 3 | A general pointer: the start-up's ROM and RAM tests, the block commands' memory access. |
| 131 | LSNADR | $0077 | Serial::ListenAddress | location | D1541 | seratn 1, dskintsf 1 | The drive's LISTEN command, $20 plus the device number from the jumpers. |
| 132 | NSSP | = 120 | Relative::POINTERS_PER_SIDE_SECTOR | constant | D1541 | ssutil 1 | The 120 data blocks one side sector lists. |
| 133 | TLKADR | $0078 | Serial::TalkAddress | location | D1541 | seratn 1, dskintsf 1 | The drive's TALK command, $40 plus the device number. |
| 134 | LSNACT | $0079 | Listening | location | D1541 | seratn 5, erproc 1 | Set while the drive is addressed to listen. |
| 135 | TLKACT | $007A | Talking | location | D1541 | seratn 5, erproc 1 | Set while the drive is addressed to talk. |
| 136 | ADRSED | $007B | DROP | location | D1541 | none | An addressed flag; not used. Named in prose. |
| 137 | ATNPND | $007C | AtnPending | location | D1541 | seratn 2, idlesf 1 | Set by the ATN interrupt for the idle loop to serve the bus. |
| 138 | ATNMOD | $007D | Serial::AtnMode | location | D1541 | seratn 2, serlistn 1 | Set while serving ATN, so receiving stops when ATN goes. |
| 139 | PRGTRK | $007E | Files::LastProgramTrack | location | D1541 | open 2 | The first track of the last program loaded, for LOAD "*". |
| 140 | DRVNUM | $007F | DriveNumber | location | D1541 | jobssf 10, open 7, lookup 6, frets 6, tst2 4, idlesf 4, new 4, map 4, setdrv 3, rename 3, block 3, parsex 2, tst3 2, addfil 2, close 2, opnchnl 2, ssutil 2, leds 1, trnsfr 1, duplct 1, copall 1, tst4 1, tsutil 1, record 1, lstdir 1 | The drive the DOS is working on, 0 or 1. |
| 141 | LRF | = $80 | RELATIVE_LAST_RECORD | constant | D1541 | rel2 3, record 3, rename 2, rel1 2, open 1, rel3 1, addrel 1 | ChannelFileType's flag for a relative file at its last record. |
| 142 | TRACK | $0080 | Track | location | D1541 | tstfnd 10, tst2 9, scrtch 5, open 5, opnchnl 5, verdir 5, map 5, frets 5, tsutil 4, erproc 4, block 3, jobssf 3, close 3, record 3, addrel 3, parsex 2, lookup 2, newss 2, new 2, rename 1, tst4 1, addfil 1, ssutil 1, rel1 1, utlodr 1 | The track of the block being worked on. |
| 143 | RNDEOI | = $81 | CHANNEL_RANDOM_LAST | constant | D1541 | rel3 2, tst4 1 | ChannelStatus for a channel both ways whose next byte is the last. |
| 144 | SECTOR | $0081 | Sector | location | D1541 | tstfnd 12, tst2 8, open 6, lookup 5, opnchnl 5, block 4, addfil 4, tsutil 4, verdir 4, scrtch 3, jobssf 3, close 3, addrel 3, erproc 3, parsex 2, rename 2, record 2, newss 2, new 2, frets 2, tst4 1, ssutil 1, utlodr 1 | The sector of the block being worked on. |
| 145 | LINDX | $0082 | Channel | location | D1541 | tst2 10, opnchnl 10, tst3 9, open 6, rel1 6, close 5, getact 4, rel4 4, newss 4, lstdir 4, tst4 3, tstflg 3, ssutil 3, sertalk 3, trnsfr 2, block 2, addfil 2, tsutil 2, rel2 2, record 2, addrel 2, rename 1, fndrel 1, rel3 1, ssend 1, nulbuf 1, erproc 1, idlesf 1 | The channel being worked on, 0-5: the index into the Channel tables (Q5). |
| 146 | SA | $0083 | SecondaryAddress | location | D1541 | tst3 8, open 8, close 7, tst4 6, rename 5, block 4, tst2 4, trnsfr 3, addfil 3, opnchnl 2, erproc 2, record 1, seratn 1, lstdir 1 | The secondary address being worked on, 0-15 or an internal one. |
| 147 | ORGSA | $0084 | SecondaryCommand | location | D1541 | seratn 2, parsex 1, tst2 1, erproc 1, serlistn 1 | The secondary byte as received: the address with $60 for data, $E0 for CLOSE or $F0 for OPEN. |
| 148 | DATA | $0085 | DataByte | location | D1541 | tst2 7, rel2 5, tst4 3, lstdir 3, rel1 2, utlodr 2, serlistn 2, rename 1, memrw 1, rel3 1 | The byte being received, sent or moved. |
| 149 | R0 | $0086 | Work0 | location | D1541 | close 17, erproc 15, tstfnd 6, addrel 4, scrtch 3, utlodr 3, idlesf 2, rename 1 | The first of five work bytes several families use; routines name their uses by scoped aliases. |
| 150 | R1 | $0087 | Work1 | location | D1541 | rel4 6, utlodr 4, addrel 3, newss 2, rename 1 | The second work byte. |
| 151 | R2 | $0088 | Work2 | location | D1541 | utlodr 7, rel4 3, addrel 3, newss 2, rename 1 | The third work byte. |
| 152 | R3 | $0089 | Work3 | location | D1541 | record 5, utlodr 4, newss 2 | The fourth work byte. |
| 153 | RNDRDY | = $89 | CHANNEL_RANDOM | constant | D1541 | block 2, tst4 1, rel3 1, record 1 | ChannelStatus for a channel both ways, more to send. |
| 154 | R4 | $008A | Work4 | location | D1541 | newss 4, utlodr 2, record 1 | The fifth work byte. |
| 155 | RESULT | $008B | Relative::Product | location | D1541 | fndrel 15 | Four bytes: the record number times the record size plus the offset, the record's place in the file. |
| 156 | ACCUM | $008F | Relative::Accumulator | location | D1541 | fndrel 29 | Five bytes the multiplication and division work in. |
| 157 | WRITE | = $90 | JOB_WRITE | constant | D1541 | jobssf 5, tsutil 3, tst2 1, tst4 1, close 1, ssutil 1 | Job code $90: write the buffer to its header's block. |
| 158 | DIRBUF | $0094 | BufferPointer | location | D1541 | trnsfr 12, lookup 10, newss 10, open 9, tsutil 8, tst4 5, ssutil 5, ssend 5, verdir 5, scrtch 4, addfil 4, new 4, sstest 3, record 2, nulbuf 2, addrel 2, tst2 1, rel4 1 | A pointer into a buffer: a directory entry, a side sector, the BAM sector's name. |
| 159 | ICMD | $0096 | DROP | location | D1541 | none | The IEEE-488 drives' command byte; not used. Named in prose. |
| 160 | MYPA | $0097 | DROP | location | D1541 | none | The IEEE-488 drives' flag; not used. Named in prose. |
| 161 | CONT | $0098 | Serial::BitCount | location | D1541 | sertalk 2, serlistn 2 | The bits left to send or receive. |
| 162 | BUFTAB | $0099 | BufferPositions | location | D1541 | tst4 13, tst2 12, frets 7, dskintsf 6, lstdir 6, rel3 4, block 3, rel2 3, parsex 2, trnsfr 2, opnchnl 2, ssutil 2, rel1 2, ramvarsf 1, tst3 1, open 1, tsutil 1, erproc 1, new 1 | A pointer per buffer, 7 of them, whose low byte is the position in it: the five data buffers, the command buffer, the error buffer (Q4). |
| 163 | CB | $00A3 | CommandPointer | location | D1541 | erproc 9, parsex 3, setdrv 2, memrw 2, tst4 1 | BufferPositions' entry for the command buffer, the parser's place in it; the next pointer, the error buffer's, is used as CB+2. |
| 164 | BUF0 | $00A7 | ChannelBuffer | location | D1541 | tst3 10, getact 5, tst2 4, dskintsf 4, block 2, rel2 2, frets 2, scrtch 1, copset 1, opnchnl 1, newss 1 | Each channel's buffer number, 7 entries; bit 7 set while inactive or none, bit 6 while dirty (Q5). |
| 165 | BUF1 | $00AE | ChannelSecondBuffer | location | D1541 | tst3 4, getact 4, tst2 2, opnchnl 2, dskintsf 2 | Each channel's second buffer, for double buffering, as ChannelBuffer; seven bytes after it, so ActiveBufferSlot indexes both. |
| 166 | RECL | $00B5 | ChannelRecord | location | D1541 | fndrel 1, rel1 1, record 1 | A relative file's channel: its record number, low byte. The same bytes are ChannelBlocks for other files (Q2). |
| 167 | RECH | $00BB | ChannelRecordHigh | location | D1541 | fndrel 1, rel1 1, record 1 | ChannelRecord's high byte. |
| 168 | BUMP | = $C0 | JOB_BUMP | constant | D1541 | jobssf 1 | Job code $C0: knock the head against track 1's stop to find it. |
| 169 | NR | $00C1 | ChannelNextRecord | location | D1541 | rel1 5, nulbuf 3, opnchnl 2, rel2 2, tsutil 1, rel4 1, addrel 1 | A relative file's channel: where its next record starts in the buffer, 0 for none. |
| 170 | RS | $00C7 | ChannelRecordSize | location | D1541 | opnchnl 3, record 2, fndrel 1, rel4 1, nulbuf 1, addrel 1 | A relative file's channel: its record size. |
| 171 | SS | $00CD | ChannelSideSector | location | D1541 | opnchnl 4, tst3 3, ssutil 3, newss 3, tsutil 1, ssend 1, dskintsf 1 | A relative file's channel: its side sector's buffer number, $FF for none. |
| 172 | F1PTR | $00D3 | Commands::NameIndex | location | D1541 | block 3, setdrv 2, parsex 1 | The file name being set up, or the block command's next parameter. |
| 173 | RECPTR | $00D4 | RecordOffset | location | D1541 | record 2, rename 1, fndrel 1, addrel 1 | The position within the record that P set. |
| 174 | SSNUM | $00D5 | SideSectorNumber | location | D1541 | addrel 5, rename 3, ssend 3, sstest 2, fndrel 1, close 1 | Which side sector lists the record's block, 0-5. |
| 175 | SSIND | $00D6 | SideSectorIndex | location | D1541 | addrel 6, rename 3, fndrel 1, close 1, ssutil 1, sstest 1, ssend 1 | Where in that side sector the block's pointer is. |
| 176 | RELPTR | $00D7 | BlockOffset | location | D1541 | fndrel 3, record 2, rename 1, addrel 1 | Where in its data block the record starts. |
| 177 | ENTSEC | $00D8 | FileNameEntrySector | location | D1541 | rename 4, open 2, parsex 1, lookup 1, addfil 1, tstflg 1 | For each file name, the directory sector its entry was found in (Q5). |
| 178 | ENTIND | $00DD | FileNameEntryIndex | location | D1541 | rename 4, open 2, parsex 1, lookup 1, addfil 1, tstflg 1 | For each file name, the entry's offset in that sector. |
| 179 | FILDRV | $00E2 | FileNameDrive | location | D1541 | rename 9, lookup 5, open 3, addfil 2, parsex 1, setdrv 1, copall 1, tstflg 1, new 1 | For each file name, its drive in bit 0, bit 7 set when it was the default. |
| 180 | PATTYP | $00E7 | FileNamePattern | location | D1541 | open 8, lookup 5, parsex 3, rename 2, scrtch 1, addfil 1 | For each file name, bit 7 set if it is a pattern, with the entry's type and flags once found. |
| 181 | FILTYP | $00EC | ChannelFileType | location | D1541 | tstflg 5, open 2, opnchnl 2, block 1, tst2 1, close 1, ssutil 1, record 1 | Each channel's file type and drive, with the RELATIVE_ flags in bits 5-7. |
| 182 | CHNRDY | $00F2 | ChannelStatus | location | D1541 | tst4 5, rel3 3, block 2, opnchnl 2, sertalk 2, dskintsf 2, lstdir 2, rename 1, tst2 1, tst3 1, open 1, record 1, erproc 1, serlistn 1 | Each channel's readiness, the CHANNEL_ bits: to talk, to listen, more to send. |
| 183 | EOIFLG | $00F8 | MoreBytes | location | D1541 | rename 2, rel2 2, utlodr 2, tst2 1, seratn 1, serlistn 1 | 0 when the byte just received or read was the last (EOI or end of file), non-zero otherwise. |
| 184 | JOBNUM | $00F9 | JobNumber | location | D1541 | jobssf 4, ssutil 4, frets 4, block 3, tst2 2, tst4 2, trnsfr 1, addfil 1, close 1, tsutil 1, erproc 1, new 1, map 1 | The buffer whose job is being set up or waited for. |
| 185 | LRUTBL | $00FA | Files::LeastRecentlyUsed | location | D1541 | tst2 4, tst3 1 | The channels in order of use, most recent first, to pick one whose buffer to take. |
| 186 | NODRV | $00FF | NoDrive | location | D1541 | lookup 2, parsex 1, tst2 1, frets 1 | Each drive's flag, set when initializing it failed. |
| 187 | OVRBUF | $0100 | Controller::OverflowBuffer | location | D1541 | lccwrt 4, lccfmt4 2, lccread 1, lccbingcr 1, lccgcrbin 1, lccfmt2 1, lccfmt3 1 | The stack page, at the top of page 1: the last OVERFLOW_SIZE bytes hold a data block's GCR beyond 256, written from $01BB (69 bytes) and read from $01BA (70 bytes). |
| 188 | DSKVER | $0101 | DiskVersion | location | D1541 | jobssf 2, new 2, tst2 1 | Each drive's disk format, from the BAM, "A"; writing refuses another. |
| 189 | ZPEND | $0103 | DROP | location | D1541 | none | The zero page's end; not used. Named in prose. |
| 190 | CMDBUF | $0200 | CommandBuffer | location | D1541 | memrw 7, open 7, block 4, record 4, parsex 3, setdrv 3, lookup 2, trnsfr 2, dskintsf 2, new 2, copset 1, tst2 1, vector 1 | The command channel's text, and an OPEN's name. |
| 191 | CMDNUM | $022A | CommandNumber | location | D1541 | parsex 4, block 2, open 2, erproc 2 | The command's index in the command table. |
| 192 | LINTAB | $022B | SecondaryChannels | location | D1541 | tst3 4, opnchnl 4, rename 3, dskintsf 3, block 2, tst2 2, open 1, close 1, tstflg 1, erproc 1, idlesf 1 | Each secondary address's channel, bit 7 set for writing, bit 6 for a channel that does both, $FF for none. |
| 193 | CHNDAT | $023E | ChannelByte | location | D1541 | tst4 4, block 2, rel3 2, sertalk 2, open 1, opnchnl 1, erproc 1 | Each channel's next byte to send, fetched ahead. |
| 194 | LSTCHR | $0244 | ChannelLastByte | location | D1541 | block 4, tst2 4, lstdir 4, tst4 2, opnchnl 2, rel3 2, rel4 2, memrw 1, rel1 1, erproc 1 | Each channel's position of the last byte in its buffer, where reading ends. |
| 195 | TYPE | $024A | FileType | location | D1541 | open 9, addfil 4, rename 2, opnchnl 2, parsex 1, tst4 1, erproc 1 | The type of the file being opened. |
| 196 | STRSIZ | $024B | Commands::StringLength | location | D1541 | trnsfr 4 | The length of the name being moved from the command buffer. |
| 197 | TEMPSA | $024C | Files::SavedSecondary | location | D1541 | open 4 | OPEN's secondary address, kept while it parses. |
| 198 | CMD | $024D | JobCommand | location | D1541 | jobssf 6, tsutil 6, tst2 1, tst4 1, ssutil 1, tstfnd 1 | The job code being set up, and a sector number meanwhile. |
| 199 | LSTSEC | $024E | Bam::LastSector | location | D1541 | tstfnd 4 | The free-block search's highest sector on the track. (Q1 for the scope.) |
| 200 | BUFUSE | $024F | BuffersInUse | location | D1541 | block 6, tst3 5, dskintsf 2, copset 1 | A bit per buffer, two bytes, set while in use; bits 5-15 are always set, since there are five. |
| 201 | MDIRTY | $0251 | BamDirty | location | D1541 | map 2, tst2 1, frets 1 | Each drive's flag, set when its BAM has changed and must be written. |
| 202 | ENTFND | $0253 | EntryFound | location | D1541 | lookup 6, trnsfr 1, scrtch 1, tstflg 1 | The directory search's last match, the file name's number, or $FF. |
| 203 | DIRLST | $0254 | ListingActive | location | D1541 | tst4 1, close 1, lstdir 1 | Set while a channel reads the directory as a program. |
| 204 | CMDWAT | $0255 | CommandWaiting | location | D1541 | idlesf 2, tst2 1 | Set when the command channel's text is complete, for the idle loop to run. |
| 205 | LINUSE | $0256 | FreeChannels | location | D1541 | tst3 5, copset 1, dskintsf 1 | A bit per channel, set while it is free. |
| 206 | LBUSED | $0257 | ActiveBufferSlot | location | D1541 | getact 2, rel2 2, newss 1 | Which entry of ChannelBuffer or ChannelSecondBuffer (its index plus 7) holds the active buffer. |
| 207 | REC | $0258 | RecordSize | location | D1541 | open 5, opnchnl 3, lookup 2, parsex 1, copall 1, rename 1, addfil 1 | The record size of the relative file being opened or found. |
| 208 | TRKSS | $0259 | SideSectorTrack | location | D1541 | opnchnl 2, addfil 1, open 1 | The track of the relative file's first side sector. |
| 209 | SECSS | $025A | SideSectorSector | location | D1541 | opnchnl 2, addfil 1, open 1 | Its sector. |
| 210 | LSTJOB | $025B | LastJobs | location | D1541 | jobssf 8, tst3 2, block 1, tst2 1, addfil 1, tstflg 1, tsutil 1, idlesf 1, lstdir 1, map 1 | The last job each data buffer was given, for retries and its drive (Q4). |
| 211 | DSEC | $0260 | ChannelEntrySector | location | D1541 | open 2, addfil 1, close 1, tstflg 1 | Each channel's directory entry, its sector, to update at CLOSE. |
| 212 | DIND | $0266 | ChannelEntryIndex | location | D1541 | open 2, addfil 1, close 1, tstflg 1 | The entry's offset in that sector. |
| 213 | ERWORD | $026C | ErrorFlash | location | D1541 | parsex 3, idlesf 3, leds 2, close 2, rel2 2, record 1 | The error LED's countdown, which the idle loop toggles the LED by; a command's held error is PendingError, the same byte (Q2). |
| 214 | ERLED | $026D | ErrorLed | location | D1541 | jobssf 3, leds 2, idlesf 1 | The LED bit to flash for the error, 0 for none. |
| 215 | PRGDRV | $026E | Files::LastProgramDrive | location | D1541 | open 2 | The drive of the last program loaded. |
| 216 | PRGSEC | $026F | Files::LastProgramSector | location | D1541 | open 2 | Its first sector. |
| 217 | WLINDX | $0270 | WriteChannel | location | D1541 | open 2, close 2 | The channel of the file being written. |
| 218 | RLINDX | $0271 | DROP | location | D1541 | none | A read channel; not used. Named in prose. |
| 219 | NBTEMP | $0272 | BlockTotal | location | D1541 | trnsfr 5, lstdir 5, addrel 2, map 2 | Two bytes: a block count, a file's in the listing or the free total. |
| 220 | CMDSIZ | $0274 | CommandLength | location | D1541 | parsex 3, block 3, setdrv 2, trnsfr 1, memrw 1, open 1, new 1 | The length of the command in the command buffer. |
| 221 | CHAR | $0275 | Commands::Character | location | D1541 | parsex 4 | The command letter, or the character the parser looks for. |
| 222 | LIMIT | $0276 | StringEnd | location | D1541 | trnsfr 2, lookup 1 | The end of a name in the command buffer, its last index plus one. |
| 223 | F1CNT | $0277 | FirstStreamEnd | location | D1541 | parsex 4, open 3, setdrv 2, rename 2, block 2 | The number of names before "=". |
| 224 | F2CNT | $0278 | SecondStreamEnd | location | D1541 | setdrv 6, parsex 3, rename 3, utlodr 3, lookup 2, open 2 | The number of names in all. |
| 225 | F2PTR | $0279 | SecondStreamStart | location | D1541 | rename 6, lookup 4, open 3, parsex 2, block 2, setdrv 1 | The number of the first name after "=". |
| 226 | FILTBL | $027A | FileNameStart | location | D1541 | parsex 7, open 5, setdrv 4, copall 2, new 2, lookup 1, copset 1, rename 1, addfil 1 | For each file name, where it starts in the command buffer, with the end after the last (6 entries). |
| 227 | FILTRK | $0280 | FileNameTrack | location | D1541 | open 5, lookup 2, copall 2, rename 2, utlodr 2, parsex 1, scrtch 1, block 1, addfil 1 | For each file name, the track of its file's first block once found, 0 if none. |
| 228 | FILSEC | $0285 | FileNameSector | location | D1541 | block 8, parsex 1, lookup 1, scrtch 1, addfil 1, open 1, utlodr 1 | Its sector; the block commands' parameters go here too, as Commands::Parameters (Q2). |
| 229 | PATFLG | $028A | PatternFlag | location | D1541 | parsex 8, lookup 2 | Counts "*" and "?" while a name is parsed. |
| 230 | IMAGE | $028B | Commands::Structure | location | D1541 | parsex 6, setdrv 2, copset 2 | The command's shape as parsed (patterns, several names, drives, names given), checked against its syntax image. |
| 231 | DRVCNT | $028C | DriveSearches | location | D1541 | lookup 7, copall 1 | The drives still to search. |
| 232 | DRVFLG | $028D | DriveSearchFlag | location | D1541 | trnsfr 5, lookup 3 | Set while the search goes on to the other drive. |
| 233 | LSTDRV | $028E | LastDrive | location | D1541 | parsex 2, open 2, setdrv 1, block 1 | The last drive used without an error, the default. |
| 234 | FOUND | $028F | Directory::Found | location | D1541 | lookup 7 | Set once every name has been found. |
| 235 | DIRSEC | $0290 | Directory::SearchSector | location | D1541 | lookup 2 | The directory sector being searched. |
| 236 | DELSEC | $0291 | FreeEntrySector | location | D1541 | lookup 3, addfil 3, copall 1 | The sector of the first free directory entry seen, 0 if none. |
| 237 | DELIND | $0292 | FreeEntryIndex | location | D1541 | lookup 5, addfil 5, verdir 1 | That entry's offset. |
| 238 | LSTBUF | $0293 | Directory::LastBlock | location | D1541 | lookup 3 | 0 at the directory's last block. |
| 239 | INDEX | $0294 | EntryOffset | location | D1541 | lookup 3, close 2, open 1 | The offset of the directory entry being looked at. |
| 240 | FILCNT | $0295 | Directory::EntriesLeft | location | D1541 | lookup 3 | The entries left in the directory sector. |
| 241 | TYPFLG | $0296 | MatchType | location | D1541 | lookup 2, parsex 1, setdrv 1, open 1 | The file type a search must match, 0 for any. |
| 242 | MODE | $0297 | Files::Mode | location | D1541 | open 8 | OPEN's mode, one of MODE_ (read 0). |
| 243 | JOBRTN | $0298 | JobErrorReturn | location | D1541 | jobssf 3, lookup 1 | Set to return a job's error to the caller instead of reporting it. |
| 244 | EPTR | $0299 | Jobs::OffsetIndex | location | D1541 | jobssf 4 | Recovery: the next entry of the head offset table. |
| 245 | TOFF | $029A | Jobs::TotalOffset | location | D1541 | jobssf 4 | Recovery: the head's offset so far, to step it back. |
| 246 | UBAM | $029B | Bam::LastImage | location | D1541 | frets 2 | Each drive's BAM image last used, so the other is swapped out. |
| 247 | TBAM | $029D | Bam::ImageTracks | location | D1541 | frets 7 | The track of each of the four BAM images, two a drive, 0 for none. |
| 248 | BAM | $02A1 | Bam::Images | location | D1541 | frets 5 | Four tracks' BAM entries, four bytes each, held out of the BAM's buffer while they are worked on. |
| 249 | NAMBUF | $02B1 | Directory::ListingLine | location | D1541 | trnsfr 19, lstdir 1 | The listing line being built. (Q1 for the scope.) |
| 250 | ERRBUF | $02D5 | ErrorBuffer | location | D1541 | tst4 4, erproc 4, dskintsf 2 | The error message, buffer 6, which the error channel reads. |
| 251 | WBAM | $02F9 | BamWriteDeferred | location | D1541 | frets 4, tstfnd 4, parsex 2, scrtch 2, verdir 2, block 1, open 1, close 1, erproc 1 | Non-zero to hold off writing the BAM; bit 7 then marks a write pending. |
| 252 | NDBL | $02FA | FreeBlocks | location | D1541 | frets 4, tst2 1, map 1 | Each drive's free blocks, low byte. |
| 253 | NDBH | $02FC | FreeBlocksHigh | location | D1541 | frets 3, tst2 1, map 1 | The high bytes. |
| 254 | PHASE | $02FE | StepRequest | location | D1541 | jobssf 3, lccend 3 | Each drive's request to the controller to step the head a half track: 1 inward, $FF outward. The controller sets 2 when it accepts the request and starts the step; the step routine waits for the change, then clears it to 0. (The listing's comment is wrong.) |
| 255 | BUFF0 | $0300 | Buffer0 | location | D1541 | lccfmt2 14, lccfmt4 4, lccfmt3 1 | Buffer 0, where formatting builds the headers. |
| 256 | BUFS | $0300 | Buffers | location | D1541 | lccvar 3, duplct 3, lcccntrl 2, ramvarsf 1, lccseek 1 | The data buffers, buffer n at Buffers + $100 × n (Q4). Defined in both `lccvar` and `ramvarsf`. |
| 257 | FBUFS | $0300 | DROP | location | D1541 | none | The format code's image; not used. Named in prose. |
| 258 | RAMEND | $0300 | DROP | location | D1541 | none | The variables' end; not used. Named in prose. |
| 259 | BUFF1 | $0400 | DROP | location | D1541 | none | Buffer 1; not used by name. Named in prose. |
| 260 | BUFF2 | $0500 | Buffer2 | location | D1541 | lccfmt2 2, lccfmt3 1 | Buffer 2, where formatting builds a sector's data. |
| 261 | CNT | $0620 | Controller::FormatRetries | location | D1541 | lccfmt1 1, lccfmt4 1 | Formatting: the errors still allowed on a track, from 10. |
| 262 | FMTVAR | $0620 | Controller::FormatVariables | location | D1541 | lccfmt1 7 | Formatting's variables, in buffer 3; the rows after it are its bytes. |
| 263 | NUM | $0621 | Controller::SegmentLength | location | D1541 | lccfmt1 6, lccfmt4 2 | Formatting: the bytes of sync, and then of non-sync, written to time the track, adjusted until they match. |
| 264 | TRYS | $0623 | Controller::VerifyRetries | location | D1541 | lccfmt3 2 | Formatting: the tries left to read back a header. |
| 265 | TRAL | $0624 | Controller::TrackLength | location | D1541 | lccfmt2 3, lccfmt1 2 | Formatting: the bytes the track holds, high byte first. |
| 266 | DTRCK | $0626 | Controller::SectorGap | location | D1541 | lccfmt2 4 | Formatting: the smallest sector's size, then the gap each sector gets. |
| 267 | REMDR | $0627 | Controller::GapRemainder | location | D1541 | lccfmt2 1 | Formatting: the bytes left over, put at the track's end. |
| 268 | SECT | $0628 | Controller::FormatSector | location | D1541 | lccfmt2 5, lccfmt3 2 | Formatting: the sector being built or checked. |
| 269 | PB | $1800 | Via1PortB | location | D1541 | sertalk 10, seratn 8, serlistn 4, dskintsf 2, idlesf 2, vector 2 | VIA 1's port B, the serial bus: data, clock and ATN in and out, ATN's acknowledge, and the device number's jumpers on PB5-PB6. |
| 270 | PA1 | $1801 | Via1PortAHandshake | location | D1541 | seratn 1 | VIA 1's port A, with CA1's handshake: read only to clear the ATN interrupt. |
| 271 | DDRB1 | $1802 | Via1DirectionB | location | D1541 | dskintsf 1, vector 1 | VIA 1's port B direction register. |
| 272 | DDRA1 | $1803 | Via1DirectionA | location | D1541 | vector 1 | VIA 1's port A direction register. |
| 273 | T1LC1 | $1804 | Via1Timer1 | location | D1541 | lccfmt1 2 | VIA 1's timer 1, low byte: read to clear its flag while formatting times the track. |
| 274 | T1HC1 | $1805 | Via1Timer1High | location | D1541 | lccfmt1 1, vector 1 | VIA 1's timer 1, high byte: the format's 100 µs timer, the EOI wait, the LED's flash and the read's sync timeout. |
| 275 | TIMER1 | $1805 | Via1Timer1High | location | D1541 | idlesf 2, lccread 2 | As T1HC1, a second name (Q3). |
| 276 | T1LL1 | $1806 | Via1Timer1Latch | location | D1541 | lccfmt1 1 | VIA 1's timer 1 latch, low byte. |
| 277 | T1HL1 | $1807 | Via1Timer1LatchHigh | location | D1541 | lccfmt1 1 | VIA 1's timer 1 latch, high byte. |
| 278 | T2LC1 | $1808 | Via1Timer2 | location | D1541 | none | VIA 1's timer 2, low byte (not used). |
| 279 | T2HC1 | $1809 | Via1Timer2High | location | D1541 | none | VIA 1's timer 2, high byte (not used). |
| 280 | SR1 | $180A | Via1Shift | location | D1541 | none | VIA 1's shift register (not used). |
| 281 | ACR1 | $180B | Via1AuxiliaryControl | location | D1541 | lccfmt1 4 | VIA 1's auxiliary control register: the format sets timer 1 free-running. |
| 282 | PCR1 | $180C | Via1PeripheralControl | location | D1541 | dskintsf 1 | VIA 1's peripheral control register: CA1, the ATN interrupt's edge. |
| 283 | IFR1 | $180D | Via1InterruptFlags | location | D1541 | lccfmt1 2, serlistn 1, dskintsf 1, irq 1 | VIA 1's interrupt flags: ATN, and timer 1's timeouts. |
| 284 | IER1 | $180E | Via1InterruptEnable | location | D1541 | dskintsf 1 | VIA 1's interrupt enable register: ATN's interrupt. |
| 285 | POTA1 | $180F | Via1PortA | location | D1541 | none | VIA 1's port A, without handshake (not used; the listing's photo sensor is not read). |
| 286 | DSKCNT | $1C00 | DriveControl | location | D1541 | lccfmt1 8, lccend 7, lcccntrl 4, lccutil 2, lccinit 1, lccread 1, lccwrt 1 | VIA 2's port B as the drive's lines (an alias of Via2PortB): stepper phase in bits 0-1, motor 2, LED 3, write protect 4, density 5-6, sync 7. |
| 287 | LEDPRT | $1C00 | DriveControl | location | D1541 | leds 6, dskintsf 5, jobssf 4, idlesf 3, vector 1 | As DSKCNT, a second name, for the LED's bit (Q3). |
| 288 | DATA2 | $1C01 | DiskData | location | D1541 | lccfmt2 7, lccwrt 5, lccread 4, lccfmt3 3, lccseek 2, lccfmt4 2, lccfmt1 1 | VIA 2's port A as the GCR byte read from or written to the disk (an alias of Via2PortAHandshake). |
| 289 | DDRB2 | $1C02 | Via2DirectionB | location | D1541 | lccinit 1 | VIA 2's port B direction register. |
| 290 | LEDOUT | $1C02 | Via2DirectionB | location | D1541 | vector 1 | As DDRB2, a second name: the start-up's error flashing makes the LED's pin an output (Q3). |
| 291 | DDRA2 | $1C03 | Via2DirectionA | location | D1541 | lccfmt4 3, lccwrt 2 | VIA 2's port A direction register: all out to write, all in to read. |
| 292 | T1LC2 | $1C04 | Via2Timer1 | location | D1541 | lcccntrl 1 | VIA 2's timer 1, low byte: read to clear the controller's interrupt. |
| 293 | T1HC2 | $1C05 | Via2Timer1High | location | D1541 | lccend 3, lccinit 1 | VIA 2's timer 1, high byte: the stepper's speeding up and slowing down set the next interrupt's time. |
| 294 | T1LL2 | $1C06 | Via2Timer1Latch | location | D1541 | lccinit 1 | VIA 2's timer 1 latch, low byte. |
| 295 | T1HL2 | $1C07 | Via2Timer1LatchHigh | location | D1541 | lccend 3, lccinit 1 | VIA 2's timer 1 latch, high byte: the interrupt's period, IRQ_PERIOD. |
| 296 | T2LL2 | $1C08 | Via2Timer2 | location | D1541 | none | VIA 2's timer 2, low byte (not used; the listing calls it a latch). |
| 297 | T2LH2 | $1C09 | Via2Timer2High | location | D1541 | none | VIA 2's timer 2, high byte (not used). |
| 298 | SR2 | $1C0A | Via2Shift | location | D1541 | none | VIA 2's shift register (not used). |
| 299 | ACR2 | $1C0B | Via2AuxiliaryControl | location | D1541 | lccinit 1 | VIA 2's auxiliary control register: timer 1 free-running, port A latched. |
| 300 | PCR2 | $1C0C | Via2PeripheralControl | location | D1541 | lccfmt4 6, lccwrt 4, lccinit 2, lcccntrl 2, lccend 2 | VIA 2's peripheral control register: CA2 lets byte ready reach the 6502's SO pin, CB2 selects reading or writing. |
| 301 | IFR2 | $1C0D | Via2InterruptFlags | location | D1541 | lccinit 1, irq 1 | VIA 2's interrupt flags: timer 1's, the controller's interrupt. |
| 302 | IER2 | $1C0E | Via2InterruptEnable | location | D1541 | lccinit 2 | VIA 2's interrupt enable register. |
| 303 | CCHKSM | $C000 | LowerRomChecksum | table | D1541 | none | The $C000 chip's first byte, $97, chosen so the start-up's sum of the chip comes to its first page, $C0. |
| 304 | FREEC0 | $C001 | PatchSpace | table | D1541 | none | The $C000 chip's unused bytes to $C0FF, filled with $AA. |
| 305 | RDMODE | = 0 | DROP | constant | D1541 | none | OPEN's mode R, 0; not used by name. Named in prose with the MODE_ constants. |
| 306 | VAL | = 0 | Commands::VALIDATE | constant | D1541 | erproc 1 | V's index in the command table, which the error handler checks. |
| 307 | DATIN | = $01 | Serial::DATA_IN | constant | D1541 | sertalk 7 | Via1PortB's bit 0: the bus's data line, read (1 while pulled). |
| 308 | LISNER | = $01 | DROP | constant | D1541 | none | The IEEE-488 drives' listener flag; not used. Named in prose. |
| 309 | MASK4 | = $01 | Controller::CODE4_HIGH | constant | D1541 | lccgcrbin 1 | GCR decoding: the fourth code's high bit, bit 0 of the second byte. |
| 310 | RDYLST | = $01 | CHANNEL_LISTEN | constant | D1541 | iodefsf 2, open 1, opnchnl 1, dskintsf 1 | ChannelStatus's bit 0: the channel accepts bytes. |
| 311 | APMODE | = 2 | Files::MODE_APPEND | constant | D1541 | open 2 | OPEN's mode A, append. |
| 312 | DATOUT | = $02 | Serial::DATA_OUT | constant | D1541 | sertalk 2 | Via1PortB's bit 1: set to pull the data line. |
| 313 | MASK7 | = $03 | Controller::CODE7_HIGH | constant | D1541 | lccgcrbin 1 | GCR decoding: the seventh code's high two bits, bits 0-1 of the fourth byte. |
| 314 | MDMODE | = 3 | Files::MODE_MODIFY | constant | D1541 | open 1 | OPEN's mode M, modify (read a file not closed). |
| 315 | CLKIN | = $04 | Serial::CLOCK_IN | constant | D1541 | serlistn 4, seratn 1 | Via1PortB's bit 2: the clock line, read. |
| 316 | GAP2 | = 4 | Controller::MIN_SECTOR_GAP | constant | D1541 | lccfmt2 1 | The smallest gap after a data block that formatting accepts. |
| 317 | RELTYP | = 4 | TYPE_RELATIVE | constant | D1541 | open 3, addfil 2, close 2, opnchnl 2, tst2 1, erproc 1 | File type 4, REL. |
| 318 | BFCNT | = 5 | BUFFER_COUNT | constant | D1541 | dskintsf 3, equatesf 2, block 1, idlesf 1 | The five data buffers. |
| 319 | MXCHNS | = 6 | CHANNEL_COUNT | constant | D1541 | tst3 4, equatesf 2, getact 1, dskintsf 1, frets 1 | The six channels, the Channel tables' length. |
| 320 | NSSL | = 6 | Relative::SIDE_SECTOR_COUNT | constant | D1541 | equatesf 2, sstest 1, addrel 1 | The most side sectors a relative file has. |
| 321 | RDMAX | = 6 | Controller::READ_DISTANCE | constant | D1541 | lccseek 1 | A read is taken if its sector is less than 6 away. |
| 322 | MASK2 | = $07 | Controller::CODE2_HIGH | constant | D1541 | lccgcrbin 1 | GCR decoding: the second code's high three bits, bits 0-2 of the first byte. |
| 323 | TYPMSK | = 7 | TYPE_MASK | constant | D1541 | open 3, rename 2, lookup 1 | The type's bits in a directory entry. |
| 324 | VERERR | = 7 | DROP | constant | D1541 | none | The controller's verify error; not used. Named in prose. |
| 325 | CLKOUT | = $08 | Serial::CLOCK_OUT | constant | D1541 | sertalk 2 | Via1PortB's bit 3: set to pull the clock line. |
| 326 | EOI | = $08 | CHANNEL_MORE | constant | D1541 | sertalk 1 | As EOISND, a second name, which TALK tests. |
| 327 | PCMD | = 9 | Commands::FIRST_PARSED | constant | D1541 | parsex 1, romtblsf 1 | The first command that the parser tags with names (R, S and N, indexes 9-11 of the command table); C, index 8, parses itself when it copies. |
| 328 | WRTMIN | = 9 | Controller::WRITE_DISTANCE_MIN | constant | D1541 | lccseek 1 | A write is taken only if its sector is at least 9 away. |
| 329 | CBPTR | = 10 | COMMAND_BUFFER_SLOT | constant | D1541 | parsex 2, ramvarsf 1, open 1, erproc 1 | The command buffer's pointer's offset in BufferPositions, 2 × BUFFER_COUNT. |
| 330 | NCMDS | = 12 | Commands::COUNT | constant | D1541 | romtblsf 2, parsex 1 | The command table's twelve letters. |
| 331 | WRTMAX | = 12 | Controller::WRITE_DISTANCE_MAX | constant | D1541 | lccseek 1 | A write is taken only if its sector is less than 12 away: 9-11 sectors ahead. |
| 332 | MASK5 | = $0F | Controller::CODE5_HIGH | constant | D1541 | lccgcrbin 1 | GCR decoding: the fifth code's high four bits, the third byte's low nibble. |
| 333 | ATNA | = $10 | Serial::ATN_ACKNOWLEDGE | constant | D1541 | seratn 2 | Via1PortB's bit 4: ATN's acknowledge, which pulls data unless it matches ATN. |
| 334 | MASK8 | = $1F | Controller::CODE8 | constant | D1541 | lccgcrbin 1 | GCR decoding: the eighth code, bits 0-4 of the fifth byte. |
| 335 | SKIP2 | = $2C | OPCODE_BIT | constant | D1541 | lccseek 2, lccread 1 | The BIT absolute opcode, as a byte that skips the next two (K-P3-Q4). |
| 336 | MASK3 | = $3E | Controller::CODE3 | constant | D1541 | lccgcrbin 1 | GCR decoding: the third code, bits 1-5 of the second byte. |
| 337 | UNLSN | = $3F | Serial::UNLISTEN | constant | D1541 | seratn 1 | The bus's UNLISTEN command. |
| 338 | BUMPC | = $40 | Controller::JOB_CODE_BUMP | constant | D1541 | lcccntrl 1 | JOB_BUMP as JobCode holds it, the top bit and drive removed. |
| 339 | FM4040 | = $41 | FORMAT_VERSION | constant | D1541 | romtblsf 1 | "A", the format of 4040 and 1541 disks, which the BAM holds. |
| 340 | FM2030 | = $42 | DROP | constant | D1541 | none | The 2030's format; not used. Named in prose. |
| 341 | JMPC | = $50 | DROP | constant | D1541 | none | The jump job as JobCode would hold it; not used. Named in prose. |
| 342 | UNTLK | = $5F | Serial::UNTALK | constant | D1541 | seratn 1 | The bus's UNTALK command. |
| 343 | EXECD | = $60 | Controller::JOB_CODE_EXECUTE | constant | D1541 | lcccntrl 1, lccseek 1 | JOB_EXECUTE as JobCode holds it. |
| 344 | ZP2 | = $65 | DROP | constant | D1541 | ramvarsf 1 | The DOS's zero page's start, used only as the origin. Named in prose. |
| 345 | MASK6 | = $7C | Controller::CODE6 | constant | D1541 | lccgcrbin 1 | GCR decoding: the sixth code, bits 2-6 of the fourth byte. |
| 346 | ATN | = $80 | Serial::ATN_IN | constant | D1541 | seratn 1 | Via1PortB's bit 7: the ATN line, read. |
| 347 | EOIOUT | = $80 | CHANNEL_TALK_LAST | constant | D1541 | iodefsf 1, tst2 1, tst4 1, lstdir 1 | ChannelStatus's bit 7 alone: the channel has one byte left, to send with EOI. |
| 348 | MASK5X | = $80 | Controller::CODE5_LOW | constant | D1541 | lccgcrbin 1 | GCR decoding: the fifth code's low bit, bit 7 of the fourth byte. |
| 349 | READ | = $80 | JOB_READ | constant | D1541 | tsutil 3, tst2 1, tst4 1, jobssf 1, ssutil 1, erproc 1, lccread 1 | Job code $80: read the header's block into the buffer. |
| 350 | TALKER | = $80 | DROP | constant | D1541 | none | The IEEE-488 drives' talker flag; not used. Named in prose. |
| 351 | RDYTLK | = $88 | CHANNEL_TALK | constant | D1541 | iodefsf 1, tst4 1, opnchnl 1, erproc 1, dskintsf 1, lstdir 1 | ChannelStatus for a channel with more to send. |
| 352 | WVERFY | = $A0 | DROP | constant | D1541 | none | Job code $A0, verify; not used by name. Named in prose with the JOB_ constants. |
| 353 | SEEK | = $B0 | JOB_SEEK | constant | D1541 | equatesf 1, tst2 1, lccseek 1 | Job code $B0: find the track and read its ID. |
| 354 | NBKL | $00B5 | ChannelBlocks | location | D1541 | close 5, tst2 1, opnchnl 1 | A sequential or program file's channel: the blocks written, low byte, for its entry. The same bytes are ChannelRecord (Q2). |
| 355 | SECSEK | = $B8 | JOB_SECTOR_SEEK | constant | D1541 | jobssf 1 | Job code $B8: find the header of the job's sector on its track, without reading or writing it; recovery puts it in place of a write. |
| 356 | NBKH | $00BB | ChannelBlocksHigh | location | D1541 | close 4, tst2 1, opnchnl 1 | ChannelBlocks' high byte. The same bytes are ChannelRecordHigh. |
| 357 | MASK2X | = $C0 | Controller::CODE2_LOW | constant | D1541 | lccgcrbin 1 | GCR decoding: the second code's low two bits, bits 6-7 of the second byte. |
| 358 | JUMPC | = $D0 | JOB_JUMP | constant | D1541 | lcccntrl 1 | Job code $D0: run the code in the buffer at once. |
| 359 | EXEC | = $E0 | JOB_EXECUTE | constant | D1541 | duplct 1 | Job code $E0: run the code in the buffer once its track is reached. |
| 360 | MASK7X | = $E0 | Controller::CODE7_LOW | constant | D1541 | lccgcrbin 1 | GCR decoding: the seventh code's low three bits, bits 5-7 of the fifth byte. |
| 361 | MASK4X | = $F0 | Controller::CODE4_LOW | constant | D1541 | lccgcrbin 1 | GCR decoding: the fourth code's low four bits, the third byte's high nibble. |
| 362 | MASK1 | = $F8 | Controller::CODE1 | constant | D1541 | lccgcrbin 1 | GCR decoding: the first code, bits 3-7 of the first byte. |
| 363 | ROM | = $C000 | DROP | constant | D1541 | 1541 1, romsf 1 | The ROM's start, used only as the origin. Named in prose. |

## Part 2: the job loop and GCR

Settled on 2026-11-27 after an independent review of the part (D2, D7).

The job queue from both sides. `jobssf` is the DOS side, `Jobs`: it checks a job's track and sector, puts the job
in the queue, waits for it and recovers from its errors, with retries, half-track offsets and a bump. The `lcc*`
files and `irq` are the controller, `Controller`, which runs in the interrupt every ~14.85 ms: `SYSIRQ` calls `LCC`,
which looks for a job, spins the motor up and steps to the job's track, finds the header and dispatches by job
type (seek, read, write, verify, sector seek, bump, execute, jump), converts between binary and GCR, formats, and
ends each pass in `END`, which runs the motor's spin-up and timeout and steps the head. The variables these use are
part 1's, named here by their listing names (`JOBS`, `HDRS`, `LSTJOB`, `DRVST`, `CDRIVE`, `NXTST`...).

### Questions

- D-P2-Q1. **The two sides of the queue.** Everything in `jobssf` is `Jobs`, including HEDOFF and MOVHED, which
  ask the controller for a half-track step through `PHASE` and wait for it. Everything in `lcc*` and `irq` is
  `Controller`. The routines every family calls (WATJOB from 11 files, SETH, DOREAD, DOWRIT) stay in `Jobs`, as the
  kernal's `Serial::Talk` stays in `Serial`, since top level is for the vectors and what they reach.
  *Recommended.* The alternative is making `Jobs::Wait`, `Read` and `Write` top level, since every family uses
  them. **Settled:** everything in jobssf is Jobs and everything in lcc* and irq is Controller; the routines every
  family calls (Jobs::Wait, Read, Write, SetHeader) stay in Jobs, not top level.
- D-P2-Q2. **The controller's main loop and its job dispatch.** LCC is `Controller::ScanJobs`, the routine the
  interrupt calls. It saves the stack pointer, enables byte-ready, scans the queue and either starts the motor,
  starts a step toward the job's track, or dispatches the job on the head's track. TOP is its entry `Rescan`,
  which `Controller::FinishJob` (ERRR) enters after resetting the stack, so one pass can run several jobs. The jump
  and execute jobs and the bump are locals of ScanJobs (`JumpToBuffer`, `Execute`, `Bump`). The handlers for the
  jobs that read the disk are routines, each passing the job on by `JMP` when it is not its type, as the listing
  chains them: `Seek` (finds a header, finishes seek jobs, checks the ID) to `ChooseSector` (WSECT, which picks the
  job whose sector comes soonest) to `Read`, `Write`, `Verify` and `SectorSeek`. Every job ends in one of two
  exits: `FinishJob`, which stores the result code, or `EndPass` (END), which ends the pass with the motor and the
  stepper and returns from the interrupt's call. The stepper's states, which EndPass reaches through `NXTST`, are
  its locals, except StepIdle (INACT), an entry because `Controller::Initialize` stores its address. SETJB is
  `Controller::LoadJob`, and SETJB1 its entry `JobInY`. CNTINT, `Controller::Initialize`, has no `RTS`: it falls
  into ScanJobs in the next file, so start-up runs one pass of the controller. This gets a "Falls into" comment and
  an `.assert`. *Recommended.* The alternatives are one `.proc` for the whole dispatch chain, from SEAK to SECTSK,
  which hides that each job type has its own handler, or naming LCC `Controller::MainLoop` after the listing's
  heading, although it is one pass per interrupt and not a loop. **Settled:** LCC is Controller::ScanJobs with entry
  Rescan, the job handlers are chained routines, FinishJob and EndPass are the two exits, Initialize falls into ScanJobs
  with an assert, and no single dispatch proc or MainLoop name.
- D-P2-Q3. **SYSIRQ** is `Controller::Interrupt`, in the family the brief gives `irq`, although it also passes ATN
  to the serial code (`ATNIRQ`, part 6's `Serial::AtnInterrupt`). *Recommended.* The alternative is a top-level
  `Interrupt`, since the IRQ vector points at it and it serves two families. **Settled:** SYSIRQ is
  Controller::Interrupt, calling part 6's Serial::AtnInterrupt.
- D-P2-Q4. **The GCR tables and routines.** BGTAB is `Controller::GcrCodes` (16 five-bit codes, one per nibble).
  GCRHI and GCRLO are `Controller::GcrHighNibbles` and `GcrLowNibbles` (32 entries each, indexed by a five-bit code,
  giving the nibble already in place, $FF for the 16 codes that are not GCR). They stay in `Controller` although
  fast loaders read them by address, as the style says (`LowRes::Plot`). The routines are named for what they
  convert: `EncodeGroup` (PUT4BG, 4 bytes in `BTAB` to 5 GCR bytes) and `DecodeGroup` (GET4GB, the reverse),
  `EncodeBlock` (BINGCR, a buffer to the 325-byte write image), `DecodeBlock` (GCRBIN, a read image to binary),
  `DecodeWriteImage` (WTOBIN, a write image back to the buffer), `EncodeHeader` (CONHDR) and `DecodeHeader`
  (CNVBIN), and `EncodeHeaders` (FBTOG, the format's header buffer). `Gcr` is the hardware's own term, like `Irq`.
  No decode path checks for a bad code. The $FF entries make bad bytes that only the checksum catches, and
  `GCRERR` (part 1's) is never set. The reasons say so. *Recommended.* **Settled:** BGTAB is Controller::GcrCodes (part
  1's GTAB is Controller::GcrGroup), GCRHI/GCRLO stay in Controller as GcrHighNibbles/GcrLowNibbles, and the
  Encode/Decode routines are named as listed, with reasons saying bad codes are never checked.
- D-P2-Q5. **The format routine's pieces.** FORMT is entered through a job. DUPLCT's FORMAT writes `JMP FORMT` at
  $0600 and queues an execute job for buffer 3, so the controller re-enters FORMT on each pass until the job
  finishes, and `FTNUM` says how far it has got. lccfmt1-3 run straight through, each falling into the next file.
  The recommendation is three routines, one per file, each with its own contract and an `.assert` at each fall:
  `Controller::Format` (lccfmt1: bumps, steps to the track, then erases and measures it), `Controller::WriteTrack`
  (lccfmt2, from DS08, its unreferenced first label, kept as its old name: sizes the gaps, builds the headers and
  the zero block, writes every sector) and `Controller::VerifyTrack` (lccfmt3, whose first instruction, at $FD27,
  has no listing name: reads the track back, then moves to the next track or finishes). lccfmt4's pieces are
  routines of their own (`EraseWithSync`, `WriteCount`, `ShiftBufferUp`, `CopyOverflow`, `EndWrite`, `EraseTrack`,
  `EncodeHeaders`). FMTERR, which every piece jumps to, is the routine `Controller::FormatError`. It allows 10
  errors over the whole format, not per track, each one retrying the track on the next pass. CODE, a second
  unreferenced name on FORMT, is dropped. The alternative is one `Format` `.proc` spanning lccfmt1-3 (as
  ConvertingSources allows for a routine split over files), which is 732 bytes with one contract. **Settled:** the
  format is three routines (Format, WriteTrack, VerifyTrack) with an assert at each fall, lccfmt4's pieces are routines,
  FMTERR is Controller::FormatError, and CODE is dropped.
- D-P2-Q6. **The timing.** The controller's tick is VIA 2's timer 1, latched at 58 × 256 cycles, about 14.85 ms
  at 1 MHz (the `TIM` comment's "15 ms" is right). The listing's other comments assume other ticks: END's "every 8
  ms", the settle's "5*8=40ms", TURNON's "1.5 sec" and TRNOFF's "255*.025s". END restarts the timer at its start
  ($F99C), so the next interrupt comes 14.85 ms after a pass ends, not after it began; a tick is that plus the pass, and
  the times are minimums. The reasons give what the code does: spin-up 60 ticks (at least 0.9 s), timeout 255 ticks (at
  least 3.8 s), settle 5 ticks (at least 74 ms). The accelerated stepping (SSACL, SSRUN, SSDEC) shortens or lengthens
  the tick by `AF`. It is never reached with the ROM's settings, because start-up sets `MINSTP` to 200 and `STEPS` is a
  signed byte, so any move is at most 128 half-tracks. It keeps its names, with a comment that it runs only if a program
  lowers `MINSTP`. SYNC's 20 ms timeout is VIA 1's timer 1 (`TIMER1`, $1805). The format's segment timing is VIA 1's
  timer 1 in continuous mode at 100 µs. The `bvc *` waits for byte-ready have no labels. *Recommended.* **Settled:** the
  tick is VIA 2 timer 1 at about 14.85 ms restarted at the end of each pass, so the reasons give minimum times (spin-up
  60 ticks, timeout 255, settle 5); the accelerated stepping is kept with a comment that it never runs, because STEPS is
  a signed byte (at most 128) and MINSTP is 200.
- D-P2-Q7. **What the 1541 patched.** The source keeps 901229-05's bytes and describes each patch in a comment,
  with no `.if` for the earlier ROMs, which are not built. The patches:
  - The "4/12" patch made each job's header 2 bytes (track and sector) instead of 4. SETJOB, HED2TS and SETH have
    one `ASL` where there were two.
  - SETH no longer copies the disk ID into the header, so its last `ASL`/`TAX` leaves X = `DRVNUM` × 2, which
    nothing uses. The comment says so.
  - The "harris fix": a seek job copies the ID read from the header into `DSKID`, which is how initializing learns
    the ID.
  - WGP3's erase gap after each data block is commented out.
  - The header gap: 901229-01 and -02 wait out and write 8 bytes after the header (`LDX #8` at $F58C and $FCCF),
    and -03 onward write 9 (`GAP1` 11, less 2). The comment on `GAP1` notes the change.
  **Settled:** 901229-05's bytes are kept with each patch described in a comment and no .if for earlier ROMs.

  The listing's wrong comments are corrected in the reasons, not carried over. These are HEDOFF's step directions
  (below), CNTINT's "disable s.o." (CA2 high enables byte-ready), the format's "diff/2" (the code adds twice the
  difference), "282*5/4-256=85" (the value is $66, 102), "write 4 sync" (`NUMSYN` is 5) and "move up 79 bytes" (69).
  *Recommended.*
- D-P2-Q8. **The head offsets are half-tracks, inward for positive.** In MOVHED, Y = 1 makes the controller
  advance the stepper's phase, the way it moves toward higher tracks. Each step is half a track (ScanJobs doubles a
  track distance into steps). The listing's HEDOFF says "step out 1 track" for that. The locals are named for what
  happens (`OffsetHead::StepIn` for HOF1, `StepOut` for HOF2), and the recovery's `OFFSET` table (1, -1, -1, 1)
  tries half a track in, back, half a track out, back. *Recommended.* **Settled:** head offsets are half-tracks,
  positive inward, with locals OffsetHead::StepIn and StepOut.
- D-P2-Q9. **SETJOB's pieces.** Commodore put HED2TS, TSCHK and VNERR between SETJOB's error exit and its tail,
  SJB1. The recommendation is separate routines in that order:
  - `Jobs::Start` (SETJOB) checks the job and falls into `Jobs::TrackSectorError` (TSERR), whose entry `Report`
    (TSER1) is what TSCHK branches to.
  - `Jobs::LoadTrackSector` (HED2TS).
  - `Jobs::CheckTrackSector` (TSCHK).
  - `Jobs::VersionError` (VNERR), which Start branches to and NEW jumps to.
  - `Jobs::Queue` (SJB1), reached by branch from Start with the command on the stack, which its contract says.
    **Settled:** HED2TS, TSCHK and VNERR are separate routines in listing order, not one Start proc, and SETLJB is
    Jobs::StartOnLastDrive.

  The alternative is one `Start` `.proc` over all of it, which would make the routines that BLOCK, VERDIR and NEW
  call into entries of Start. SETLJB, which falls into SETJOB, is `Jobs::StartOnLastDrive`.
- D-P2-Q10. **DOREAD, DOWRIT, DOJOB, DOIT, DOIT2 and WATJOB.** `Jobs::Read` branches to `Jobs::Run` (DOJOB, a
  routine because TST2 jumps to it as one), `Jobs::Write` falls into it, and Run's entries are `WithDrive` (DOIT,
  the command already has its drive bit) and `Repeat` (DOIT2, runs `CMD` again). Run falls into `Jobs::Wait`
  (WATJOB). TSTJOB is `Jobs::Poll`, and the recovery (RECOV to REC95) is its locals, since only it enters them.
  *Recommended.* **Settled:** Read branches to Run, Write falls into it, Run has entries WithDrive and Repeat and falls
  into Wait, and TSTJOB is Jobs::Poll with the recovery as its locals.
- D-P2-Q11. **The skipped instructions.** DONE, BADID and CSERR in Seek, and READ's checksum error, each load a
  code and skip the next load with `.byte SKIP2` (`$2C`, BIT absolute). They stay inside their routine, with the
  `$2C` explained, as the kernal's NODEV and FRMERR do. DONE is Seek's entry `JobDone`, because Verify and
  SectorSeek jump to it. *Recommended.* **Settled:** the skipped loads stay inside their routines with the $2C
  explained, and DONE is Seek's entry JobDone.
- D-P2-Q12. **Unreferenced labels** (FIN, EXE, EX3, END001, STPOUT, WTOB52, CODE) are dropped with "Not
  referenced", as the kernal's were. STPOUT's code, the outward step, is described in `EndPass::Step`'s comment.
  CNTST, the listing's note of the address to go back to after it lays out VIA 2 with `*=$1C00`, is assembly
  bookkeeping, not a name the code uses. It is dropped and named in prose where VIA 2's registers are defined.
  *Recommended.* **Settled:** unreferenced labels are dropped with Not referenced, and CNTST is dropped and named in
  prose.
- D-P2-Q13. **One drive.** ScanJobs fails any job for drive 1 with code $0F (no drive), and the dual-drive
  leftovers (`DRVST`, `DRVTRK` and `DSKID` per drive, TRNOFF's unused `LDX CDRIVE`) stay as they are, with
  comments. No name here mentions a drive number. *Recommended.* **Settled:** ScanJobs fails drive 1 jobs with $0F, the
  dual-drive leftovers stay with comments, and no name mentions a drive number.

### Rows

| # | Old | Address | New | Kind | Documents (checked) | Used in | Reason |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | SETLJB | $D506 | Jobs::StartOnLastDrive | routine | D1541 | tst2 1, tsutil 1 | A = `CMD` plus the drive bit of buffer X's last job (`LSTJOB`); falls into Start. |
| 2 | SETJOB | $D50E | Jobs::Start | routine | D1541 | jobssf 1 | Checks job X's track and sector against `MAXTRK` and MAXSEC, and a write's disk version against `VERNUM`; falls into TrackSectorError when they are bad, branches to Queue when good. |
| 3 | SJB2 | $D535 | Jobs::Start::SecondDriveVersion | local | D1541 | jobssf 1 | A = drive 1's `DSKVER`. |
| 4 | SJB3 | $D538 | Jobs::Start::CheckVersion | local | D1541 | jobssf 1 | A version of 0 (none read yet) passes; any other must be `VERNUM`. |
| 5 | SJB4 | $D53F | Jobs::Start::CheckSector | local | D1541 | jobssf 1 | The sector must be below the track's MAXSEC. |
| 6 | TSERR | $D54A | Jobs::TrackSectorError | routine | D1541 | jobssf 3 | Copies the job's header to `TRACK` and `SECTOR` for the message and reports 66, ILLEGAL TRACK OR SECTOR, through CMDER2. |
| 7 | TSER1 | $D54D | Jobs::TrackSectorError::Report | entry | D1541 | jobssf 4 | Reports 66 with `TRACK` and `SECTOR` as they are; CheckTrackSector branches here. |
| 8 | HED2TS | $D552 | Jobs::LoadTrackSector | routine | D1541 | jobssf 2 | `TRACK` and `SECTOR` = job `JOBNUM`'s header (two bytes a job since the 4/12 patch). |
| 9 | TSCHK | $D55F | Jobs::CheckTrackSector | routine | D1541 | block 1, verdir 1 | Checks `TRACK` (1 to `MAXTRK`-1) and `SECTOR` (below MAXSEC); returns if good, else reports 66. |
| 10 | VNERR | $D572 | Jobs::VersionError | routine | D1541 | jobssf 1, new 1 | Reports 73 (`CBMV2`), the disk's DOS version is not this one's, for a write; NEW jumps here too. |
| 11 | SJB1 | $D57A | Jobs::Queue | routine | D1541 | jobssf 2 | Start's tail, reached by branch with the command on the stack: stores it in `CMD`, `JOBS` and `LSTJOB` for job `JOBNUM`, which starts the job. |
| 12 | DOREAD | $D586 | Jobs::Read | routine | D1541 | tst2 1, frets 1 | Reads the job's sector and waits: A = `READ`, then branches to Run. |
| 13 | DOWRIT | $D58A | Jobs::Write | routine | D1541 | frets 2, map 1 | Writes the job's sector and waits: A = `WRITE`; falls into Run. |
| 14 | DOJOB | $D58C | Jobs::Run | routine | D1541 | tst2 1, jobssf 1 | Runs job type A on drive `DRVNUM` for job `JOBNUM` and waits; falls into Wait. |
| 15 | DOIT | $D590 | Jobs::Run::WithDrive | entry | D1541 | close 1 | Runs command A, which already has its drive bit, for job X. |
| 16 | DOIT2 | $D593 | Jobs::Run::Repeat | entry | D1541 | tst4 1, ssutil 1 | Runs `CMD` again for job X, after a caller has set a new header. |
| 17 | WATJOB | $D599 | Jobs::Wait | routine | D1541 | opnchnl 3, rename 2, tst2 2, rel1 2, newss 2, scrtch 1, tst4 1, jobssf 1, close 1, tsutil 1, addrel 1 | Polls job X until it is done, recovering from its errors, then clears `JOBRTN`; A = the job's code. |
| 18 | TSTJOB | $D5A6 | Jobs::Poll | routine | D1541 | jobssf 1 | Carry set while job X is still running; carry clear when it is done, after recovering from an error, or with the error returned when `JOBRTN` bit 7 asks for that. |
| 19 | TJ10 | $D5BA | Jobs::Poll::NotRetried | local | D1541 | jobssf 2 | Write protect (8), ID mismatch (11) and no drive (15) are not retried: returned if `JOBRTN` asks, else reported. |
| 20 | OK | $D5C2 | Jobs::Poll::Finished | local | D1541 | jobssf 2 | Carry clear: done. |
| 21 | NOTYET | $D5C4 | Jobs::Poll::Busy | local | D1541 | jobssf 1 | Carry set: still running. |
| 22 | RECOV | $D5C6 | Jobs::Poll::Recover | local | D1541 | jobssf 1 | Error recovery: selects the job's drive and its LED mask, and retries the job `REVCNT` times. |
| 23 | REC01 | $D5E3 | Jobs::Poll::RetriesFailed | local | D1541 | jobssf 1 | Keeps the job's type, and turns a write into a sector seek (`SECSEK`) for the rest of the recovery, so nothing is written while the head is off. |
| 24 | REC0 | $D5F4 | Jobs::Poll::TryOffsets | local | D1541 | jobssf 1 | Unless `REVCNT` bit 6 turns them off, retries with the head offset by each entry of `OFFSET` in turn. |
| 25 | REC1 | $D600 | Jobs::Poll::NextOffset | local | D1541 | jobssf 1 | Moves the head by the next offset, keeps the total in `TOFF`, and retries; a 0 ends the table. |
| 26 | REC3 | $D625 | Jobs::Poll::Recentre | local | D1541 | jobssf 1 | Moves the head back by the total offset. |
| 27 | REC5 | $D631 | Jobs::Poll::CheckBump | local | D1541 | jobssf 1 | `REVCNT` bit 7 clear: tries a bump. |
| 28 | QUIT | $D635 | Jobs::Poll::Fail | local | D1541 | jobssf 1 | Recovery failed: restores a write job in `LSTJOB`. |
| 29 | QUIT2 | $D63F | Jobs::Poll::ReportError | local | D1541 | jobssf 3 | Reports the job's code as a DOS error through ERROR, which does not return. |
| 30 | REC7 | $D644 | Jobs::Poll::Bump | local | D1541 | jobssf 1 | Returns the error if `JOBRTN` asks; else queues a bump on the drive. |
| 31 | REC8 | $D651 | Jobs::Poll::WaitBump | local | D1541 | jobssf 1 | Waits for the bump, then retries the job once more. |
| 32 | REC9 | $D65C | Jobs::Poll::Recovered | local | D1541 | jobssf 1 | The job, or its sector seek, worked: a write is put back and retried for real. |
| 33 | REC95 | $D66D | Jobs::Poll::Restore | local | D1541 | jobssf 3 | Restores `DRVNUM` and Y; A = the job's code, carry clear. |
| 34 | HEDOFF | $D676 | Jobs::OffsetHead | routine | D1541 | jobssf 2 | Moves the head A half-tracks, inward for positive (the listing's comments have the directions reversed), one StepHead at a time. |
| 35 | HOF1 | $D67C | Jobs::OffsetHead::StepIn | local | D1541 | jobssf 1 | One half-track inward (Y = 1). |
| 36 | HOF2 | $D688 | Jobs::OffsetHead::StepOut | local | D1541 | jobssf 2 | One half-track outward (Y = $FF). |
| 37 | HOF3 | $D692 | Jobs::OffsetHead::Done | local | D1541 | jobssf 2 | Returns. |
| 38 | MOVHED | $D693 | Jobs::StepHead | routine | D1541 | jobssf 2 | Puts Y (1 in, $FF out) in the drive's `PHASE` for the controller's EndPass to step, waits until it takes it, and clears it; keeps A. |
| 39 | MH10 | $D69A | Jobs::StepHead::Wait | local | D1541 | jobssf 1 | Waits for the controller to change `PHASE`. |
| 40 | DOREC | $D6A6 | Jobs::Retry | routine | D1541 | jobssf 4 | Requeues the last job (`LSTJOB`) up to `REVCNT` & $3F times, flashing the drive's LED each try, until it works; leaves the LED on; A = the code. |
| 41 | DOREC1 | $D6AB | Jobs::Retry::Again | local | D1541 | jobssf 1 | Toggles the LED and requeues the job. |
| 42 | DOREC2 | $D6B9 | Jobs::Retry::Wait | local | D1541 | jobssf 1 | Waits for the job; below 2 is success. |
| 43 | DOREC3 | $D6C4 | Jobs::Retry::Done | local | D1541 | jobssf 1 | Turns the LED back on and returns the code. |
| 44 | SETHDR | $D6D0 | Jobs::SetHeader | routine | D1541 | tst2 4, addrel 2, opnchnl 1, tsutil 1 | Sets the active buffer's job header (GETACT) to `TRACK` and `SECTOR`. |
| 45 | SETH | $D6D3 | Jobs::SetHeader::ForBuffer | entry | D1541 | opnchnl 2, duplct 1, tst2 1, tst4 1, ssutil 1 | The same for buffer A. Leaves X = `DRVNUM` × 2, which is what is left of the ID copy the 4/12 patch commented out. |
| 46 | CNTINT | $F259 | Controller::Initialize | routine | D1541 | dskintsf 1 | Sets up VIA 2 (port B's directions; motor off, LED off; CA2 high, which enables byte-ready, though the listing's comment says it disables it; timer 1 free-running at 58 × 256 cycles with its interrupt), the block IDs (`HBID` 8, `DBID` 7), the stepper (`NXTST` = StepIdle, `MINSTP` 200, `AS`, `AF` 4), no drive and no format; falls into ScanJobs. |
| 47 | LCC | $F2B0 | Controller::ScanJobs | routine | D1541 | irq 1 | One pass of the controller: saves the stack for FinishJob, clears the timer's interrupt (END restarts it), enables byte-ready, and finds a job. Starts the motor, steps toward the job's track, or dispatches the job on this track; ends in EndPass. |
| 48 | TOP | $F2BE | Controller::ScanJobs::Rescan | entry | D1541 | lccutil 1 | Scans the queue from job 5 down for the first job (bit 7 set); FinishJob comes back here after each job. |
| 49 | CONT10 | $F2C0 | Controller::ScanJobs::FindJob | local | D1541 | lcccntrl 1 | Scans the queue for a job (jobs count down from the last); a jump job (`JUMPC`) runs its buffer at once, motor or not. |
| 50 | CONT30 | $F2CD | Controller::ScanJobs::CheckDrive | local | D1541 | lcccntrl 1 | Drive 1 fails the job with $0F, no drive. |
| 51 | CONT35 | $F2D8 | Controller::ScanJobs::CheckCurrentDrive | local | D1541 | lcccntrl 1 | A drive not yet active (`CDRIVE`) is turned on, and the pass ends to let it spin up. |
| 52 | CONT40 | $F2E9 | Controller::ScanJobs::CheckReady | local | D1541 | lcccntrl 1 | Waits while `DRVST` says spinning up (bit 7) or stepping (bit 6). |
| 53 | CONT50 | $F2F0 | Controller::ScanJobs::ToEndPass | local | D1541 | lcccntrl 1 | Jumps on to EndPass. |
| 54 | CONT20 | $F2F3 | Controller::ScanJobs::NextJob | local | D1541 | lcccntrl 1 | The next job; none found ends the pass. |
| 55 | QUE | $F2F9 | Controller::ScanJobs::ScanTrack | local | D1541 | lcccntrl 1 | `DRVST` = running; scans every job for one on the head's track (`DRVTRK`). |
| 56 | QUE10 | $F301 | Controller::ScanJobs::ScanTrackNext | local | D1541 | lcccntrl 1 | Loads job `JOBN`; a pending one is checked. |
| 57 | QUE05 | $F306 | Controller::ScanJobs::ScanTrackLoop | local | D1541 | lcccntrl 2 | The next lower job. With none on the track, steps toward the track of the lowest-numbered job seen (`NXTJOB`): `STEPS` = twice the distance, `DRVST` = stepping, `DRVTRK` = its track. |
| 58 | FIN | $F31D | DROP | local | D1541 | none | Not referenced. |
| 59 | QUE20 | $F320 | Controller::ScanJobs::CheckTrack | local | D1541 | lcccntrl 1 | For the active drive's job: an unknown head track (0) or the job's track is on track; otherwise its distance (`NXTRK`) and number (`NXTJOB`) are kept. |
| 60 | GOTU | $F33C | Controller::ScanJobs::OnTrack | local | D1541 | lcccntrl 2 | Finds the track's zone in `TRKNUM`, sets `SECTR` from `NUMSEC` and the density bits in `DSKCNT`, and dispatches by job type. |
| 61 | GOTU10 | $F342 | Controller::ScanJobs::FindZone | local | D1541 | lcccntrl 1 | Counts down the zone boundaries. |
| 62 | EXE | $F367 | DROP | local | D1541 | none | Not referenced. |
| 63 | EX | $F36E | Controller::ScanJobs::Execute | local | D1541 | lcccntrl 1 | An execute job (`EXECD`), once on its track: runs its buffer. |
| 64 | EX2 | $F370 | Controller::ScanJobs::JumpToBuffer | local | D1541 | lcccntrl 1 | Jumps to the start of buffer A ($0300 + A × 256), which ends the job itself, through FinishJob or EndPass. |
| 65 | EX3 | $F379 | DROP | local | D1541 | none | Not referenced. |
| 66 | BMP | $F37C | Controller::ScanJobs::Bump | local | D1541 | lcccntrl 1 | A bump: 92 half-tracks outward against the stop (`STEPS` = -92) with `DRVTRK` = 1, and the job finished with 1. |
| 67 | SETJB | $F393 | Controller::LoadJob | routine | D1541 | lccseek 2, lcccntrl 1 | Job `JOBN`: if pending, `JOB` = its type ($00 read to $60 execute), `HDRPNT` = its header, `BUFPNT` = its buffer; returns the queue byte, N set if pending, Y = 0. |
| 68 | SETJB1 | $F395 | Controller::LoadJob::JobInY | entry | D1541 | lcccntrl 1 | The same for job Y. |
| 69 | SETJ10 | $F3AB | Controller::LoadJob::Finish | local | D1541 | lcccntrl 1 | Clears `BUFPNT`'s low byte and Y, and returns the queue byte. |
| 70 | SEAK | $F3B1 | Controller::Seek | routine | D1541 | lcccntrl 1, lccwrt 1 | Reads headers (up to 90) until one checks: sets `DRVTRK` from it, finishes a seek job, checks the disk ID, then goes to ChooseSector. A write comes back here to become its verify. |
| 71 | SEEK10 | $F3BB | Controller::Seek::FindHeader | local | D1541 | lccseek 1 | Waits for a sync and the header's first GCR byte, $52. |
| 72 | SEEK15 | $F3C8 | Controller::Seek::ReadHeader | local | D1541 | lccseek 1 | Reads the header's other 7 GCR bytes into `STAB`, then decodes them. |
| 73 | SEEK30 | $F3DC | Controller::Seek::Checksum | local | D1541 | lccseek 1 | The header's five bytes must XOR to 0, else error 9. |
| 74 | SEEK20 | $F407 | Controller::Seek::NotHeader | local | D1541 | lccseek 1 | Not a header: tries again, and after 90 fails with 2, header not found. |
| 75 | ESEEK | $F410 | Controller::Seek::SeekJob | local | D1541 | lccseek 1 | A seek job copies the header's ID into `DSKID` (the "harris fix"), which is how the DOS learns a disk's ID, and finishes. |
| 76 | DONE | $F418 | Controller::Seek::JobDone | entry | D1541 | lccwrt 2 | Finishes the job with 1, success; skips the next load with $2C. |
| 77 | BADID | $F41B | Controller::Seek::IdMismatch | local | D1541 | lccseek 2 | Finishes with 11, disk ID mismatch; skips the next load with $2C. |
| 78 | CSERR | $F41E | Controller::Seek::HeaderChecksumError | local | D1541 | lccseek 1 | Finishes with 9, header checksum error. |
| 79 | WSECT | $F423 | Controller::ChooseSector | routine | D1541 | lccseek 1 | Of the active drive's jobs on this track, picks the one whose sector comes soonest after the next but one. A read must be within `RDMAX` (6) sectors, and a write, verify or sector seek `WRTMIN` to `WRTMAX`-1 (9 to 11). Loads it and goes to Read; none ends the pass. |
| 80 | L460 | $F432 | Controller::ChooseSector::SetNext | local | D1541 | lccseek 1 | `NEXTS` = the header's sector + 2, wrapped. |
| 81 | L480 | $F43A | Controller::ChooseSector::CheckJob | local | D1541 | lccseek 1 | A pending job on this drive and track: its distance from `NEXTS`, wrapped. |
| 82 | L465 | $F461 | Controller::ChooseSector::CompareDistance | local | D1541 | lccseek 2 | Keeps the job if it is nearer than the best so far (`CSECT`) and inside its type's window. |
| 83 | DOITT | $F473 | Controller::ChooseSector::Best | local | D1541 | lccseek 1 | The best so far: `CSECT`, X = its job, `BUFPNT` = its buffer. |
| 84 | TSTRDJ | $F47E | Controller::ChooseSector::ReadWindow | local | D1541 | lccseek 1 | A read: within 6 sectors. |
| 85 | L470 | $F483 | Controller::ChooseSector::NextJob | local | D1541 | lccseek 7 | The next lower job. |
| 86 | L490 | $F48D | Controller::ChooseSector::Dispatch | local | D1541 | lccseek 1 | Loads the chosen job and goes to Read with its type. |
| 87 | CNVBIN | $F497 | Controller::DecodeHeader | routine | D1541 | lccseek 1 | Decodes the 8 GCR bytes in `STAB` into `HEADER` (ID, ID, track, sector, checksum); keeps `BUFPNT`. |
| 88 | REED | $F4CA | Controller::Read | routine | D1541 | lccseek 1 | A = job type: anything but a read goes on to Write. Reads the sector's 325 GCR bytes into the buffer and the overflow buffer, decodes them, and checks the block ID (error 4) and checksum (error 5). |
| 89 | READ01 | $F4D1 | Controller::Read::Start | local | D1541 | lccread 1 | Finds the sector's header and then its data block's sync. |
| 90 | READ11 | $F4D4 | Controller::Read::ReadBuffer | local | D1541 | lccread 1 | The first 256 GCR bytes, into the buffer. |
| 91 | READ20 | $F4E1 | Controller::Read::ReadOverflow | local | D1541 | lccread 1 | The rest, into the overflow buffer from $01BA. |
| 92 | READ28 | $F4FB | Controller::Read::CheckBlock | local | D1541 | lccread 1 | A data block: compares the checksum; a mismatch finishes with 5, skipping the next load with $2C. |
| 93 | READ40 | $F505 | Controller::Read::ReadOk | local | D1541 | lccread 1 | Finishes with 1. |
| 94 | DSTRT | $F50A | Controller::FindData | routine | D1541 | lccread 1, lccwrt 1 | Finds the job's header, then the data block's sync. |
| 95 | SRCH | $F510 | Controller::FindHeader | routine | D1541 | lccwrt 2, lccread 1 | Builds the job's header (the drive's `DSKID`, its track and sector, the checksum), encodes it, and reads up to 90 headers until one matches all 8 GCR bytes; else finishes with 2. |
| 96 | SRCH20 | $F538 | Controller::FindHeader::NextSync | local | D1541 | lccread 1 | Waits for the next sync. |
| 97 | SRCH25 | $F53D | Controller::FindHeader::Compare | local | D1541 | lccread 1 | Compares the next GCR byte with `STAB`. |
| 98 | SRCH30 | $F54E | Controller::FindHeader::Mismatch | local | D1541 | lccread 1 | Not this header: tries the next. |
| 99 | ERR | $F553 | Controller::FindHeader::ToFinishJob | entry | D1541 | lccread 1 | Jumps on to FinishJob; WaitForSync branches here on its timeout with 3. |
| 100 | SYNC | $F556 | Controller::WaitForSync | routine | D1541 | lccread 2, lccfmt3 2, lccseek 1, lccfmt1 1 | Waits up to 20 ms (VIA 1's timer 1, `TIMER1`) for the end of a sync, else finishes the job with 3, no sync; clears the latch and V; Y = 0. |
| 101 | SYNC10 | $F55D | Controller::WaitForSync::Wait | local | D1541 | lccread 1 | Polls the timer and the sync bit. |
| 102 | WRIGHT | $F56E | Controller::Write | routine | D1541 | lccread 1 | A = job type: anything but a write goes on to Verify. Fails with 8 if the disk is protected. Otherwise encodes the buffer, finds the header, waits out the header gap, and writes 5 sync bytes and the 325 GCR bytes. Then it decodes the buffer again and turns the job into a verify for Seek. |
| 103 | WRT05 | $F575 | Controller::Write::WriteJob | local | D1541 | lccwrt 1 | `CHKSUM` = the buffer's checksum; checks the write-protect sense. |
| 104 | WRT10 | $F586 | Controller::Write::NotProtected | local | D1541 | lccwrt 1 | Encodes the buffer and finds the header. |
| 105 | WRT20 | $F58E | Controller::Write::SkipGap | local | D1541 | lccwrt 1 | Waits 9 bytes (`GAP1`-2) past the header, then switches the port to output and the head to writing. |
| 106 | WRTSNC | $F5AB | Controller::Write::WriteSync | local | D1541 | lccwrt 1 | Five $FF bytes, the data block's sync (`NUMSYN`). |
| 107 | WRT30 | $F5B3 | Controller::Write::WriteOverflow | local | D1541 | lccwrt 1 | The 69 GCR bytes in the overflow buffer, first. |
| 108 | WRT40 | $F5BF | Controller::Write::WriteBuffer | local | D1541 | lccwrt 1 | The 256 in the buffer; then back to reading, decodes, and makes the job a verify. |
| 109 | CHKBLK | $F5E9 | Controller::BlockChecksum | routine | D1541 | lccwrt 2, lccread 1, lccfmt2 1 | A = the XOR of the buffer's 256 bytes; Y = 0. |
| 110 | CHKB10 | $F5EC | Controller::BlockChecksum::Loop | local | D1541 | lccwrt 1 | XORs the next byte. |
| 111 | WTOBIN | $F5F2 | Controller::DecodeWriteImage | routine | D1541 | lccwrt 1, lccutil 1 | Decodes the write image in place (overflow buffer first, then the buffer), `BID` = its block ID. Moves the result up and the decoded start in from the overflow buffer, so the buffer is binary again, and clears `GCRFLG`. |
| 112 | WTOB14 | $F624 | Controller::DecodeWriteImage::NextOverflowGroup | local | D1541 | lccwrt 1 | Decodes groups into the overflow buffer until it fills. |
| 113 | WTOB50 | $F643 | Controller::DecodeWriteImage::CrossToBuffer | local | D1541 | lccwrt 1 | The group that crosses into the buffer. |
| 114 | WTOB53 | $F64F | Controller::DecodeWriteImage::NextBufferGroup | local | D1541 | lccwrt 1 | Decodes groups into the buffer up to byte 187. |
| 115 | WTOB52 | $F66E | DROP | local | D1541 | none | Not referenced. |
| 116 | WTOB55 | $F678 | Controller::DecodeWriteImage::MoveUp | local | D1541 | lccwrt 1 | Moves the buffer's bytes up 69, from the top. |
| 117 | WTOB57 | $F685 | Controller::DecodeWriteImage::MoveOverflow | local | D1541 | lccwrt 1 | Copies the overflow buffer's bytes to the buffer's start. |
| 118 | VRFY | $F691 | Controller::Verify | routine | D1541 | lccwrt 1 | A = job type: anything but a verify goes on to SectorSeek. Encodes the buffer and compares it with the sector's data block, all but the 2 off bytes; a difference finishes with 7. |
| 119 | VRF10 | $F698 | Controller::Verify::VerifyJob | local | D1541 | lccwrt 1 | Computes the checksum, encodes, and finds the data block. |
| 120 | VRF15 | $F6A5 | Controller::Verify::CompareOverflow | local | D1541 | lccwrt 1 | Compares the overflow buffer's 69 bytes. |
| 121 | VRF30 | $F6B3 | Controller::Verify::CompareBuffer | local | D1541 | lccwrt 1 | Compares the buffer's bytes up to $FD. |
| 122 | VRF20 | $F6C5 | Controller::Verify::Mismatch | local | D1541 | lccwrt 2 | Finishes with 7, verify error. |
| 123 | SECTSK | $F6CA | Controller::SectorSeek | routine | D1541 | lccwrt 1 | The job type left, sector seek (`SECSEK`): finds the job's header and finishes with 1. |
| 124 | PUT4BG | $F6D0 | Controller::EncodeGroup | routine | D1541 | lccbingcr 2, lccconhdr 2, lccfmt4 2 | Encodes the 4 bytes in `BTAB` as 5 GCR bytes at `BUFPNT`+`GCRPNT`, moving to the buffer `SAVPNT` names when the index wraps. |
| 125 | BING35 | $F76F | Controller::EncodeGroup::LastByte | local | D1541 | lccbingcr 1 | The fifth GCR byte; `GCRPNT` advances. |
| 126 | BGTAB | $F77F | Controller::GcrCodes | table | D1541 | lccbingcr 8 | The 16 five-bit GCR codes, one per nibble value. |
| 127 | BINGCR | $F78F | Controller::EncodeBlock | routine | D1541 | lccwrt 2, lccbingcr 1, lccfmt2 1 | Encodes the block ID (`DBID`), the buffer, `CHKSUM` and two 0 off bytes (260 bytes) as the 325-byte write image: 69 bytes in the overflow buffer, then the buffer itself. Sets `GCRFLG`. |
| 128 | BING07 | $F7BA | Controller::EncodeBlock::NextGroup | local | D1541 | lccbingcr 1 | Encodes the next four bytes. |
| 129 | BING20 | $F7D9 | Controller::EncodeBlock::Trailer | local | D1541 | lccbingcr 1 | The last data byte, the checksum and the off bytes. |
| 130 | GET4GB | $F7E6 | Controller::DecodeGroup | routine | D1541 | lccwrt 3, lccseek 2, lccgcrbin 2 | Decodes 5 GCR bytes at `BUFPNT`+`GCRPNT` into 4 in `BTAB`, moving to `NXTBF` at `NXTPNT` when the index wraps; bad codes are not checked. |
| 131 | XX05 | $F802 | Controller::DecodeGroup::SecondByte | local | D1541 | lccgcrbin 1 | The second GCR byte, after a possible change of buffer. |
| 132 | XX06 | $F85A | Controller::DecodeGroup::FifthByte | local | D1541 | lccgcrbin 1 | The fifth, likewise; then the tables give the nibbles. |
| 133 | GCRHI | $F8A0 | Controller::GcrHighNibbles | table | D1541 | lccgcrbin 4 | For each five-bit code, its nibble in the high half; $FF for the 16 that are not GCR. |
| 134 | GCRLO | $F8C0 | Controller::GcrLowNibbles | table | D1541 | lccgcrbin 4 | The same in the low half. |
| 135 | GCRBIN | $F8E0 | Controller::DecodeBlock | routine | D1541 | lccread 1 | Decodes a read image (the buffer, then the overflow buffer from $01BA) into the buffer: `BID` = the block ID, `CHKSUM` = the checksum read. |
| 136 | GCRB10 | $F90C | Controller::DecodeBlock::NextGroup | local | D1541 | lccgcrbin 1 | Decodes the next group. |
| 137 | GCRB20 | $F92B | Controller::DecodeBlock::Finish | local | D1541 | lccgcrbin 1 | Keeps the checksum and restores `BUFPNT`. |
| 138 | CONHDR | $F934 | Controller::EncodeHeader | routine | D1541 | lccread 1, lccconhdr 1 | Encodes `HEADER` with `HBID` (block ID, checksum, sector, track, ID, ID, 0, 0) as the 10 GCR bytes in `STAB`, which FindHeader compares. |
| 139 | ERRR | $F969 | Controller::FinishJob | routine | D1541 | lccread 3, lcccntrl 2, lccseek 2, lccwrt 2, lccfmt3 1, lccfmt4 1 | Ends job `JOBN` with code A (1 success, 2-15 errors) in its queue byte. Decodes a buffer left in GCR, starts the motor's timeout, resets the stack to ScanJobs' and rescans. |
| 140 | ERRR10 | $F975 | Controller::FinishJob::Rescan | local | D1541 | lccutil 1 | Starts the timeout, resets the stack, and goes back to ScanJobs. |
| 141 | TURNON | $F97E | Controller::MotorOn | routine | D1541 | lcccntrl 1 | Starts the motor: `DRVST` = on and spinning up, `ACLTIM` = 60 ticks (at least 0.9 s; the listing says 1.5 s). |
| 142 | TRNOFF | $F98F | Controller::MotorTimeout | routine | D1541 | lccutil 1, vector 1 | Sets `DRVST`'s timeout bit and `ACLTIM` = 255 ticks (at least 3.8 s), after which EndPass stops the motor; the user command table points here too. |
| 143 | END | $F99C | Controller::EndPass | routine | D1541 | lcccntrl 4, lccfmt1 2, lccseek 1, lccfmt3 1, lccfmt4 1 | Ends each pass. Restarts the tick, notes a change of the write-protect sense (`WPSW`) and takes a half-track step the DOS asked for in `PHASE`. Counts down the spin-up and timeout (stopping the motor when it ends) and runs the stepper's state in `NXTST`; disables byte-ready and returns. |
| 144 | END001 | $F9A5 | DROP | local | D1541 | none | Not referenced. |
| 145 | END002 | $F9B1 | Controller::EndPass::CheckHeadOffset | local | D1541 | lccend 1 | `PHASE` 1 or $FF: steps once and sets it to 2, which StepHead waits for; StepHead then clears the 2 to 0 (MOVHED). |
| 146 | END003 | $F9C1 | Controller::EndPass::OffsetStep | local | D1541 | lccend 1 | `STEPS` = the offset; steps. |
| 147 | END40 | $F9CB | Controller::EndPass::CheckMotor | local | D1541 | lccend 2 | Nothing to do without an active drive, or when it is only running. |
| 148 | END33X | $F9D6 | Controller::EndPass::ToDone | local | D1541 | lccend 2 | Jumps on to Done. |
| 149 | END10 | $F9D9 | Controller::EndPass::CountDown | local | D1541 | lccend 1 | Counts `ACLTIM` down; at 0 the spin-up ends. |
| 150 | END20 | $F9E4 | Controller::EndPass::CheckTimeout | local | D1541 | lccend 1 | At the end of the timeout: motor off, no active drive, `DRVST` = 0. |
| 151 | END30 | $F9FA | Controller::EndPass::CheckStepping | local | D1541 | lccend 2 | Steps only while `DRVST` says stepping. |
| 152 | END30X | $FA02 | Controller::EndPass::RunStepState | local | D1541 | lccend 1 | Jumps to the stepper's state, `NXTST`. |
| 153 | INACT | $FA05 | Controller::EndPass::StepIdle | entry | D1541 | lccinit 2, lccend 2 | The stepper's start state: a move shorter than `MINSTP` steps one at a time (always, since `STEPS` is a signed byte, at most 128, and the ROM's `MINSTP` is 200); a longer one is accelerated. |
| 154 | INAC10 | $FA0E | Controller::EndPass::CheckDistance | local | D1541 | lccend 1 | Compares the move's length with `MINSTP`. |
| 155 | INAC20 | $FA1C | Controller::EndPass::Accelerated | local | D1541 | lccend 1 | `RSTEPS` = the length less twice `AS`, `ACLSTP` = `AS`; next state StepAccelerate. |
| 156 | DOSTEP | $FA2E | Controller::EndPass::Step | local | D1541 | lccend 4 | One half-track toward `STEPS`' sign: inward for positive, outward for negative (the listing's unreferenced STPOUT). |
| 157 | STPOUT | $FA32 | DROP | local | D1541 | none | Not referenced; the outward step, described at Step. |
| 158 | SHORT | $FA3B | Controller::EndPass::StepShort | local | D1541 | lccend 2 | One step a tick until `STEPS` is 0, then settles for 5 ticks (at least 74 ms; the listing says 40 ms). |
| 159 | SETLE | $FA4E | Controller::EndPass::StepSettle | local | D1541 | lccend 4 | Counts the settle down, then clears `DRVST`'s stepping bit and goes back to StepIdle. |
| 160 | STPIN | $FA63 | Controller::EndPass::StepIn | local | D1541 | lccend 1 | Counts `STEPS` down and advances the phase, moving the head inward. |
| 161 | STP | $FA69 | Controller::EndPass::SetPhase | local | D1541 | lccend 1 | Puts X's low two bits in `DSKCNT`'s phase bits. |
| 162 | SSACL | $FA7B | Controller::EndPass::StepAccelerate | local | D1541 | lccend 2 | Shortens this tick by `AF` and steps, `AS` times; then StepRun. Unused with the ROM's `MINSTP`. |
| 163 | SSA10 | $FA94 | Controller::EndPass::ToStep | local | D1541 | lccend 4 | Jumps on to Step. |
| 164 | SSRUN | $FA97 | Controller::EndPass::StepRun | local | D1541 | lccend 2 | Steps at the normal tick `RSTEPS` times; then StepDecelerate. |
| 165 | SSDEC | $FAA5 | Controller::EndPass::StepDecelerate | local | D1541 | lccend 2 | Lengthens the tick by `AF` and steps, `AS` times; then settles. |
| 166 | END33 | $FABE | Controller::EndPass::Done | local | D1541 | lccend 6 | Disables byte-ready (CA2 low) and returns. |
| 167 | CODE | $FAC7 | DROP | local | D1541 | none | Not referenced; a second name on Format's first byte. |
| 168 | FORMT | $FAC7 | Controller::Format | routine | D1541 | duplct 2 | The format, run as an execute job (FORMAT's `JMP` at $0600) on every pass until it finishes. The first time it bumps to track 1 and sets 10 errors (`CNT`) and a first track length of 4000 (`NUM`). After that it steps to `FTNUM`, checks write protect, and erases and measures the track. Falls into WriteTrack. |
| 169 | L213 | $FAF5 | Controller::Format::Started | local | D1541 | lccfmt1 1 | Puts `FTNUM` in the job's header, so ScanJobs steps there, unless the head is there. |
| 170 | L214 | $FB00 | Controller::Format::OnTrack | local | D1541 | lccfmt1 1 | Fails with 8 if the disk is protected. |
| 171 | TOPP | $FB0C | Controller::Format::MeasureTrack | local | D1541 | lccfmt1 2 | Fills the track with sync, writes `NUM` sync bytes and `NUM` $55 bytes, and times the two segments with VIA 1's timer 1 at 100 µs. |
| 172 | FWAIT | $FB39 | Controller::Format::WaitSync | local | D1541 | lccfmt1 1 | Waits for sync. |
| 173 | FWAIT2 | $FB3E | Controller::Format::WaitData | local | D1541 | lccfmt1 1 | Waits for its end. |
| 174 | F000 | $FB43 | Controller::Format::NextDataTick | local | D1541 | lccfmt1 2 | Counts the $55 segment in 100 µs ticks, failing with `TOLONG` (2) at 65536. |
| 175 | F001 | $FB46 | Controller::Format::WaitDataTick | local | D1541 | lccfmt1 1 | Waits for the tick or a sync. |
| 176 | F005 | $FB5C | Controller::Format::TimeSync | local | D1541 | lccfmt1 1 | Keeps the count in `T2`; counts the sync segment. |
| 177 | F006 | $FB64 | Controller::Format::NextSyncTick | local | D1541 | lccfmt1 2 | Counts a tick of the sync, failing with `TOLONG` at 65536. |
| 178 | F007 | $FB67 | Controller::Format::WaitSyncTick | local | D1541 | lccfmt1 1 | Waits for the tick or the sync's end. |
| 179 | F009 | $FB7D | Controller::Format::Compare | local | D1541 | lccfmt1 1 | `T1` = the sync's time less the data's. |
| 180 | F013 | $FB97 | Controller::Format::CheckClose | local | D1541 | lccfmt1 2 | A difference under 4 ticks is close enough. |
| 181 | F014 | $FB9E | Controller::Format::Adjust | local | D1541 | lccfmt1 1 | `NUM` += twice the difference (the listing's comment says half), and measures again. |
| 182 | COUNT | $FBB6 | Controller::Format::CountBytes | local | D1541 | lccfmt1 1 | Counts the bytes of the $55 segment, failing with `TOMANY` (3) at 65536. |
| 183 | CNT10 | $FBBB | Controller::Format::CountLoop | local | D1541 | lccfmt1 3 | Counts a byte-ready until the sync. |
| 184 | CNT20 | $FBCE | Controller::Format::Counted | local | D1541 | lccfmt1 1 | `TRAL` = twice the count, the track's length in bytes; stops the timer's free-running mode. |
| 185 | DS08 | $FBE0 | Controller::WriteTrack | routine | D1541 | none | Fallen into from Format. Sizes the gap after each data block from `TRAL` (102 bytes a sector plus 256, then the rest shared out). Builds every sector's header in buffer 0 and a zero data block in buffer 2, encodes both, and writes the track, every sector's sync, header, gap, sync and data. Falls into VerifyTrack. |
| 186 | DS10 | $FBEA | Controller::WriteTrack::AddSector | local | D1541 | lccfmt2 1 | Adds one sector's 358 bytes to the total. |
| 187 | DS14 | $FBF1 | Controller::WriteTrack::NextSector | local | D1541 | lccfmt2 1 | Counts a page and the next sector. |
| 188 | DS15 | $FC03 | Controller::WriteTrack::SpareHigh | local | D1541 | lccfmt2 1 | The spare's high byte; negative fails with `TOBIG` (4). |
| 189 | DS17 | $FC15 | Controller::WriteTrack::Divide | local | D1541 | lccfmt2 1 | Divides the spare by `SECTR`. |
| 190 | DS20 | $FC19 | Controller::WriteTrack::DivideLoop | local | D1541 | lccfmt2 1 | Subtracts `SECTR` again. |
| 191 | DS22 | $FC21 | Controller::WriteTrack::CountQuotient | local | D1541 | lccfmt2 1 | Counts the quotient. |
| 192 | DS30 | $FC24 | Controller::WriteTrack::HaveGap | local | D1541 | lccfmt2 1 | `DTRCK` = the gap; under `GAP2` (4) fails with `TOSMAL` (5). |
| 193 | DS32 | $FC30 | Controller::WriteTrack::GapOk | local | D1541 | lccfmt2 1 | `REMDR` = the remainder. |
| 194 | MAK10 | $FC3F | Controller::WriteTrack::MakeHeader | local | D1541 | lccfmt2 1 | Sector `SECT`'s header in buffer 0: `HBID`, checksum, sector, track, the two ID bytes and two $0F, 8 bytes each. |
| 195 | CRTDAT | $FC88 | Controller::WriteTrack::ClearData | local | D1541 | lccfmt2 1 | Zeroes buffer 2, the data block every sector gets. |
| 196 | WRTSYN | $FCB1 | Controller::WriteTrack::WriteSector | local | D1541 | lccfmt2 1 | Writes the next sector, starting with five sync bytes (the listing says 4). |
| 197 | WRTS10 | $FCB8 | Controller::WriteTrack::WriteHeaderSync | local | D1541 | lccfmt2 1 | Waits out the sync bytes. |
| 198 | WRTS20 | $FCC2 | Controller::WriteTrack::WriteHeader | local | D1541 | lccfmt2 1 | The header's 10 GCR bytes. |
| 199 | WRTS30 | $FCD1 | Controller::WriteTrack::WriteHeaderGap | local | D1541 | lccfmt2 1 | 9 $55 bytes (`GAP1`-2; 8 before 901229-03). |
| 200 | DBSYNC | $FCE0 | Controller::WriteTrack::WriteDataSync | local | D1541 | lccfmt2 1 | The data block's five sync bytes. |
| 201 | WRTS40 | $FCEB | Controller::WriteTrack::WriteOverflow | local | D1541 | lccfmt2 1 | The 69 GCR bytes in the overflow buffer. |
| 202 | WRTS50 | $FCF9 | Controller::WriteTrack::WriteData | local | D1541 | lccfmt2 1 | The 256 in buffer 2. |
| 203 | WGP2 | $FD09 | Controller::WriteTrack::WriteDataGap | local | D1541 | lccfmt2 1 | `DTRCK` $55 bytes; then the next header, and after the last, back to reading. |
| 204 | COMP | $FD2C | Controller::VerifyTrack::Restart | local | D1541 | lccfmt3 1 | VerifyTrack starts just before, at $FD27, with 200 tries (`TRYS`). Points at the first GCR header in buffer 0 and counts `SECTR` sectors. |
| 205 | CMPR10 | $FD39 | Controller::VerifyTrack::NextHeader | local | D1541 | lccfmt3 1 | Waits for a sync. |
| 206 | CMPR15 | $FD40 | Controller::VerifyTrack::CompareHeader | local | D1541 | lccfmt3 1 | Compares the 10 GCR bytes with the header written. |
| 207 | CMPR20 | $FD58 | Controller::VerifyTrack::Mismatch | local | D1541 | lccfmt3 3 | Starts over, and after 200 fails with `NOTFND` (6). |
| 208 | TSTDAT | $FD62 | Controller::VerifyTrack::CompareData | local | D1541 | lccfmt3 1 | Waits for the data block's sync. |
| 209 | TST05 | $FD67 | Controller::VerifyTrack::CompareOverflow | local | D1541 | lccfmt3 1 | Compares the overflow buffer's 69 bytes. |
| 210 | TST10 | $FD77 | Controller::VerifyTrack::CompareBuffer | local | D1541 | lccfmt3 1 | Compares buffer 2's bytes, all but the last 4 GCR bytes; the next sector, or the next track (`FTNUM`) and the end of the pass, until track 35. |
| 211 | FMTEND | $FD96 | Controller::VerifyTrack::Finished | local | D1541 | lccfmt3 1 | All 35 tracks: clears `FTNUM` and `GCRFLG` and finishes with 1. |
| 212 | SYNCLR | $FDA3 | Controller::EraseWithSync | routine | D1541 | lccfmt1 1 | Writes sync for 10240 bytes, more than a track, and leaves the head writing. |
| 213 | SYC10 | $FDB9 | Controller::EraseWithSync::Loop | local | D1541 | lccfmt4 2 | Counts the bytes. |
| 214 | WRTNUM | $FDC3 | Controller::WriteCount | routine | D1541 | lccfmt1 2 | Writes the byte in the port `NUM` times. |
| 215 | WRTN10 | $FDC9 | Controller::WriteCount::Loop | local | D1541 | lccfmt4 2 | Counts the bytes. |
| 216 | FMTERR | $FDD3 | Controller::FormatError | routine | D1541 | lccfmt1 4, lccfmt2 2, lccfmt3 1 | A format error A: while errors are left in `CNT` (10 for the whole format), ends the pass to retry the track; at the last, clears the format and finishes with A. |
| 217 | FMTE10 | $FDDB | Controller::FormatError::GiveUp | local | D1541 | lccfmt4 1 | Clears `FTNUM` and `GCRFLG`, and finishes the job. |
| 218 | MOVUP | $FDE5 | Controller::ShiftBufferUp | routine | D1541 | lccfmt2 1, lccfmt4 1 | Moves buffer 0's bytes 0 to Y up 69, from the top down. |
| 219 | MOVOVR | $FDF5 | Controller::CopyOverflow | routine | D1541 | lccfmt2 1 | Copies the 69 GCR bytes from the overflow buffer to the start of the buffer at `BUFPNT`. |
| 220 | MOVO10 | $FDF7 | Controller::CopyOverflow::Loop | local | D1541 | lccfmt4 1 | Copies the next byte, from the top. |
| 221 | KILL | $FE00 | Controller::EndWrite | routine | D1541 | lccfmt1 1, lccfmt2 1 | Switches the head back to reading and the port to input. |
| 222 | CLEAR | $FE0E | Controller::EraseTrack | routine | D1541 | lccfmt2 1 | Switches to writing and writes $55 for 10240 bytes, more than a track, leaving the head writing. |
| 223 | CLER10 | $FE26 | Controller::EraseTrack::Loop | local | D1541 | lccfmt4 2 | Counts the bytes. |
| 224 | FBTOG | $FE30 | Controller::EncodeHeaders | routine | D1541 | lccfmt2 1 | Encodes the buffer at `BUFPNT` (the format's headers) as GCR with no block ID, into the overflow buffer and then the buffer. |
| 225 | FBG10 | $FE44 | Controller::EncodeHeaders::NextGroup | local | D1541 | lccfmt4 1 | Takes the next four bytes and encodes them. |
| 226 | FBG15 | $FE64 | Controller::EncodeHeaders::LastGroup | local | D1541 | lccfmt4 1 | Encodes the last and returns through EncodeGroup. |
| 227 | SYSIRQ | $FE67 | Controller::Interrupt | routine | D1541 | vector 1 | The IRQ handler: saves A, X and Y; ATN (VIA 1's CA1) goes to ATNIRQ, and VIA 2's timer 1 runs a pass of ScanJobs. |
| 228 | IRQ10 | $FE76 | Controller::Interrupt::CheckTimer | local | D1541 | irq 1 | Tests VIA 2's timer 1 flag. |
| 229 | IRQ20 | $FE7F | Controller::Interrupt::Restore | local | D1541 | irq 1 | Restores Y, X and A, and returns from the interrupt. |
| 230 | CNTST | $F259 | DROP | constant | D1541 | none | The listing's note of the address to go back to after laying out VIA 2 at $1C00; assembly bookkeeping, named in prose. |

## Part 3: the command parser and the commands

Settled on 2026-11-27 after an independent review of the part (D2, D7).

The command channel's code, $C146-$CE0D and $E77F-$E852, with N at $EE0D: the parser that runs the string in the
command buffer (`parsex`), the drive numbers (`setdrv`), moving names out of the command string (`trnsfr`), and the
commands themselves: S (`scrtch`), D and the format job N starts (`duplct`), C (`copset`, `copall`, and `rename`'s
copy half), R (`rename`), M-R, M-W and M-E (`memrw`), U and B- and OPEN "#" (`block`), & (`utlodr`) and N (`new`).
215 rows. The variables are part 1's, named here by their listing names; the command table, the structure images
and the user table are part 6's rows (`romtblsf`, `vector`), and the questions below recommend their names so the
two parts agree.

### Questions

- D-P3-Q1. **The command table and the dispatch.** PARSXQ is `Commands::Execute`: it looks the first letter up in
  `CommandLetters` (CMDTBL, 'VIDMBUP&CRSN') and jumps through `CommandRoutinesLow` and `CommandRoutinesHigh` (CJUMPL,
  CJUMPH), the top-level tables part 6's rows name. STRUCT is not a table of its own: the listing makes it an equate,
  `CommandPatterns - 8`, so that CMDNUM (8 for C) indexes `CommandPatterns` (at $FEAD), whose first byte is C's;
  part 6 names the 8. The command numbers are constants of `Commands` that part 1 owns, since OPEN and the error
  channel use CMDNUM too: `Commands::VALIDATE` (VAL, 0), `Commands::LOAD_STRUCTURE` (LDCMD, 12, LOAD's index into
  CommandPatterns), `Commands::COUNT` (NCMDS) and `Commands::FIRST_PARSED` (PCMD, 9, R: C is below it because its
  names are parsed by `Copy` itself, which calls `ParseNames::AfterColon`). Each handler the table reaches is a
  routine, though the draft calls SCRTCH, MEM, BLOCK, USER, UTLODR, RENAME, NEW and DSKCPY locals: nothing calls
  them, but they are jumped to as routines of their own. They are named for the command (`Commands::Scratch`,
  `Commands::Memory`, `Commands::Block`, `Commands::User`, `Commands::LoadUtility`, `Commands::Rename`,
  `Commands::New`, `Commands::Copy`, `Commands::Duplicate`); V, I and P are other parts' (`verdir`, `intdrv`,
  `record`). *Recommended.* The alternative, one word table of handler addresses, would not assemble to the ROM.
  **Settled:** the tables are part 6's `CommandLetters`, `CommandRoutinesLow`, `CommandRoutinesHigh` and
  `CommandPatterns`; the command numbers are part 1's `Commands::VALIDATE`, `LOAD_STRUCTURE`, `COUNT` and
  `FIRST_PARSED`; each handler is a routine named for its command.
- D-P3-Q2. **The two ends of every command.** ENDCMD and CMDERR are used by 18 files in nine families. They stay
  in `Commands`, as `Commands::Finish` and `Commands::Fail`, and other families qualify them: they reset and report
  the command channel's state, and `Errors` keeps the message building they hand on to (CMDER2). Finish's other
  starts are its entries: `KeepBamFlag` (ENDSAV, OPEN), `Report` (SCREND, scratch's count) and `NoMessage`
  (SCREN1, CLOSE). *Recommended.* The alternative is top-level `EndCommand` and `CommandError`.
  **Settled:** `Commands::Finish` (with entries `KeepBamFlag`, `Report`, `NoMessage`) and `Commands::Fail`.
- D-P3-Q3. **The parser's routines.** PARSE, the scanner every parser uses, is `Commands::ScanFor` (it scans for
  the character A, filling FILTBL on the way); TAGCMD, which works out the names and the string's shape, is
  `Commands::ParseNames`, with TC30 and TC35 as its entries `AfterColon` (C) and `Equals` (LOAD); CMDSET is
  `Commands::Prepare` and CMDRST, which LOAD also calls, its entry `ClearTables`. IMAGE's bits are described in
  ParseNames' reason; part 1 should name IMAGE's and CommandPatterns' bits as constants (`IMAGE_FIRST_PATTERN` ...)
  for the code that tests them (`copset`). *Recommended.*
  **Settled:** `ScanFor`, `ParseNames` (entries `AfterColon`, `Equals`) and `Prepare` (entry `ClearTables`), as
  recommended; naming the image bits is left to part 1.
- D-P3-Q4. **The block commands' shared parser.** B- and U1 and U2 parse their numbers with one routine,
  `Commands::BlockParameters` (BLKPAR), whose entry `FromY` (BP05) OPEN "#n" uses, and `Commands::ParseNumber`
  (ASCHEX). The numbers go into the file-name tables: FILSEC,X their low bytes and FILTRK,X their high, F1CNT
  their count, F1PTR the next to take (FindBlockChannel and CheckBlock read them), F2PTR the place in the string.
  These are shared bytes with a second job, so `Commands` gets scoped aliases from part 1's names, each with a `;;`
  comment: `Parameters` (FILSEC, which part 1 defines), `ParametersHigh` (FILTRK), `ParameterCount` (F1CNT),
  `NextParameter` (F1PTR). The commands are flat members of `Commands` named for themselves: `BlockAllocate`,
  `BlockFree`, `BlockRead`, `BlockWrite`, `BlockExecute`, and B-P as `SetBufferPosition` (BLKPTR; a name that does
  not repeat the buffer pointer variable it sets); the checks are `FindBlockChannel` (BUFTST), `CheckChannelBlock`
  (BKOTST, which falls into) `CheckBlock` (BLKTST), and the reads `FetchBlock` and `FetchCountedBlock` (BLKRD2,
  BLKRD3). The sub-command table and its handlers are members of the dispatcher: `Commands::Block::Subcommands` and
  `Commands::Block::SubcommandHandlers`, named apart from the top-level `CommandLetters`; NBCMDS is part 1's
  `Commands::BLOCK_SUBCOMMAND_COUNT`. BLK30 (`Block::BadSyntax`) is an entry of Block, since BlockParameters'
  too-many-numbers branch at $CC9F jumps to it from outside. The five bytes between BlockFree and BlockAllocate (LDA #1,
  STA WBAM, at $CCFE) are reached by nothing: they stay as code, with a comment, and no label. *Recommended.* The
  alternative, a `.scope Commands::Block` with `Block::Read` and the rest, reads well but puts U1 and U2, which use the
  same routines, outside it. **Settled:** as recommended, with B-P named `Commands::SetBufferPosition` and
  `Block::BadSyntax` an entry.
- D-P3-Q5. **M-R, M-W and M-E** are one routine, `Commands::Memory`, with the locals `Read`, `OneByte`, `Write`
  and `BadSyntax`, as the code is: one handler that checks the '-' and sets up the address, then branches. MEMEX
  (M-E's JMP (TEMP)) is not referenced and is dropped, named in the routine's prose. Characters of the command
  are numbered from 0 throughout this part: the '-' is character 1, the address characters 3 and 4, the count 5.
  None of the three ends through Finish, and the reasons say so: Execute has already set the error channel to
  00, OK (its JSR OKERR at $C150), and M-W and M-E return straight to the idle loop leaving it so. M-R answers
  on channel 15 through Files' `NextByte::ErrorEnd` (GE15) and `ErrorReady` (GE20): with a count of 1 or none it
  takes the one-byte path, which resets the error channel's pointer to ERRBUF-1 and answers through DATA; with a
  count of 0 or 2 or more it points the channel at memory (a count of 0 gives 256 bytes). KILLP, called before M-W
  and M-E, is `Commands::DisableProtection` and is now only an RTS. *Recommended.* The alternative is three
  routines, `MemoryRead`, `MemoryWrite` and `MemoryExecute`, which would split one check across them.
  **Settled:** one routine `Commands::Memory` with locals `Read`, `OneByte`, `Write`, `BadSyntax`; MEMEX is dropped.
- D-P3-Q6. **The user commands.** USER is `Commands::User`; USRINT, inside it, which start-up calls, its entry
  `Reset`; U0 falls into Reset and returns by its RTS without Finish. USREXC is `Commands::UserJump`, which indexes
  the table at `UserVectorsPointer` (USRJMP, part 1) by ((the character - 1) and 15) x 2, so U1 and UA are the
  first entry, U9 and UI the ninth (the NMI vector's NNMI) and U: and UJ the tenth (reset). The table (UBLOCK,
  $FFEA) is part 6's top-level `UserCommandVectors`, since it sits in the vectors and programs may point the
  pointer elsewhere; the two words before it ($FFE6, FORMAT and TRNOFF) are part 6's `FormatVector` and
  `MotorOffVector`. U1 and U2 are `Commands::UserRead` and `Commands::UserWrite`: they are the block read and write
  without the byte count, reached only through the table. *Recommended.*
  **Settled:** `Commands::User` (entry `Reset`), `Commands::UserJump`, `UserRead` and `UserWrite`, with the
  pointer and table named by parts 1 and 6 as above.
- D-P3-Q7. **The utility loader** (&) is `Commands::LoadUtility`, with its two helpers as nested routines,
  `LoadUtility::GetByte` (GTABYT) and `LoadUtility::AddToChecksum` (ADDSUM), since nothing else uses them. It uses
  R0-R4 (part 1's `Work0`-`Work4`) for its own purposes, so it names them in its scope as aliases: `FirstRecord`
  (R0), `Checksum` (R1), `Address` and `AddressHigh` (R2, R3), `Count` (R4). The label UTLD20, which would collide
  with the alias, is `LoadUtility::ReadCount`. The listing's comment that the file type is 5 is wrong: the code
  opens type 3 (USRTYP). *Recommended.*
  **Settled:** as recommended, with UTLD20 named `LoadUtility::ReadCount`.
- D-P3-Q8. **The boot loader's remains.** BOOT, which start-up calls last, is now one RTS, then 34 bytes of filler
  ($EA and a closing $60) where the loader was; it is start-up's, `Startup::Boot`, though it sits in `utlodr`'s
  file. The filler is written as data with a comment. BOOT2 (an RTS before it that nothing reaches), BOOT3 (Boot's
  own address) and BOOT4 (inside LoadUtility, where the loader joined it) are not referenced and are dropped, named
  in prose. *Recommended.* The alternative keeps it as `Commands::Boot`, by its file.
  **Settled:** `Startup::Boot`, the filler as data, BOOT2-BOOT4 dropped.
- D-P3-Q9. **trnsfr's listing half goes to `Directory`, and three routines change scope.** GETNAM, GNSUB, BLKNB,
  NEWDIR, MSGFRE and FREMSG build the lines of the directory listed as a program; only `lstdir` and LOAD"$" use
  them. They are `Directory::NextLine`, `BuildLine`, `BlankLine`, `HeaderLine`, `FreeLine` and `FreeText`. The other
  half, which moves names out of the command string (TRNAME, TRCMBF, FNDLMT), stays in `Commands`. TOGDRV is
  `Directory::ToggleDrive` (only the directory code calls it), DELDIR `Directory::DeleteEntry`, and DELFIL
  `Bam::FreeChain`, which frees a file's blocks in the BAM; the rows stay in this part. *Recommended.*
  **Settled:** as recommended, with the three scope changes above.
- D-P3-Q10. **OPEN "#"** (OPNBLK) is in `block`'s file and only Files' OPEN jumps to it; all it does is make the
  direct-access channel the block commands work on, touching channel and buffer state only (it parses its number
  with BlockParameters::FromY). It is `Files::OpenDirect`. *Recommended.* The alternative is `Files::OpenDirect`,
  by its file. **Settled:** `Files::OpenDirect`.
- D-P3-Q11. **The copy command's pieces.** DSKCPY, C's handler, is `Commands::Copy` (it checks the string);
  COPY, which it jumps to, `Commands::CopyFiles` (it looks up and decides on appending); CY `Commands::CreateCopy`,
  whose loop CY10 is the entry `CopySources`, since appending enters it at the second source. The helpers are flat,
  since others use them: `OpenSource`, `GetInternalByte` (with the entry `AnyChannel`, GCBYTE, which OPEN's APPEND
  uses), `CopyRelative`, `CheckSources` (CHKIN), `CheckFiles` (CHKIO). PUPS1, the set-up of the removed copy of a
  whole disk, is reached by nothing but kept as `Commands::SetUpCopyAll`, like the kernal's VPAN; the
  commented-out code around it in `copset` and `copall` has no bytes and gets nothing. D is
  `Commands::Duplicate` (only error 31, on one drive), and FORMAT, in the same file, `Commands::Format`.
  *Recommended.* **Settled:** as recommended.
- D-P3-Q12. **Unreferenced labels and shared addresses.** Labels nothing refers to that only the listing names are
  dropped, as the kernal's table does: GN45, ND10, DX0005, MEMEX, BA10, BW20, BE05, BT05 and BOOT2-BOOT4. Two
  names at one address that are both referenced get one name with both in `Also:` (DEL10 and DEL2,
  `Bam::FreeChain::Next`; M10 and MEMWRT, `Commands::Memory::Write`). SD50, which the listing writes as
  `sd50 =*`, is a label (`Commands::DriveOfName::NoColon`), not the constant the draft guessed. *Recommended.*
  **Settled:** as recommended.
- D-P3-Q13. **The drive defaults.** SETDRV's interface takes the default drive in Y, but the code sets Y to 0
  first, and FindDrive defaults to 0 too (the listing marks both with rows of '!'): only the defaults are forced
  to drive 0, so an explicit "1:" still gives drive 1 (LSTDRV seeds DRVNUM at Execute and OpenDirect). The reasons
  say what the code does, and the routines keep the two-drive names (`SetDrives`, `Directory::ToggleDrive`), since
  the tables and DRVFLG still have room for two. *Recommended.*
  **Settled:** the names stay two-drive, the reasons say only the defaults are forced to drive 0.

### Rows

| # | Old | Address | New | Kind | Documents (checked) | Used in | Reason |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | PARSXQ | $C146 | Commands::Execute | routine | D1541 | idlesf 1 | Runs the command in CMDBUF: WBAM cleared, DRVNUM from LSTDRV, the error channel to 00 OK; a string that came with an OPEN on a data channel (ORGSA bit 7, channel not 15) is a file name, for Files' OPEN. Otherwise the first letter is looked up in CommandLetters and its handler jumped to through CommandRoutinesLow and CommandRoutinesHigh, R, S and N with their names parsed first. |
| 2 | PS05 | $C160 | Commands::Execute::CommandChannel | local | D1541 | parsex 2 | A command: CMDSIZ and the tables set up, the first letter into CHAR. |
| 3 | PS10 | $C16A | Commands::Execute::Search | local | D1541 | parsex 1 | Each of CommandLetters' letters, from the last; none matches: 31 SYNTAX ERROR. |
| 4 | PS20 | $C17A | Commands::Execute::Found | local | D1541 | parsex 1 | CMDNUM = the command's number; from PCMD on (R, S, N), ParseNames first. |
| 5 | PS30 | $C184 | Commands::Execute::Dispatch | local | D1541 | parsex 1 | The handler's address from CommandRoutinesLow and CommandRoutinesHigh into TEMP, and jumps there. |
| 6 | ENDCMD | $C194 | Commands::Finish | routine | D1541 | block 10, rename 3, open 2, close 2, tst2 1, record 1, verdir 1, new 1 | A command's successful end: WBAM cleared, then Fail if ERWORD holds an error; else the error channel's 00 OK with track and sector 0, then the drive remembered, the command buffer cleared and both internal channels, read (IRSA, $11) and write (IWSA, $12), freed. |
| 7 | ENDSAV | $C199 | Commands::Finish::KeepBamFlag | entry | D1541 | open 1 | OPEN ends here: as Finish, but WBAM left as it is. |
| 8 | SCREND | $C1A3 | Commands::Finish::Report | entry | D1541 | scrtch 1 | Scratch ends here: the message A (1, FILES SCRATCHED) with TRACK (the count) and sector Y. |
| 9 | SCREN1 | $C1AD | Commands::Finish::NoMessage | entry | D1541 | close 2 | CLOSE ends here: no message; LSTDRV = DRVNUM, the drive's NODRV flag cleared, CMDBUF cleared, both internal channels (IRSA and IWSA) freed. |
| 10 | CLRCB | $C1BD | Commands::ClearBuffer | routine | D1541 | parsex 1, erproc 1 | Zeroes the CMDLEN bytes of CMDBUF. |
| 11 | CLRB2 | $C1C1 | Commands::ClearBuffer::Loop | local | D1541 | parsex 1 | Each byte, from the last. |
| 12 | CMDERR | $C1C8 | Commands::Fail | routine | D1541 | open 7, parsex 5, block 5, rename 3, record 3, tst2 2, tst3 2, addrel 2, lookup 1, duplct 1, copset 1, memrw 1, rel2 1, rel3 1, utlodr 1, new 1, frets 1, tstfnd 1 | Ends a command with error A: track and sector 0 in the message, then the error channel's handling (CMDER2), which does not return. |
| 13 | SIMPRS | $C1D1 | Commands::ParseDriveOnly | routine | D1541 | tst2 1, open 1, verdir 1 | For a string that names at most a drive (I, V, OPEN of "$"): FILTBL = the place before ':', or 0 without one; then FindDrive. |
| 14 | SP10 | $C1E2 | Commands::ParseDriveOnly::ToFindDrive | local | D1541 | parsex 1 | Jumps to FindDrive. |
| 15 | PRSCLN | $C1E5 | Commands::FindColon | routine | D1541 | open 2, parsex 1, copset 1 | Scans the string from its start for ':' (ScanFor): Y just past it, or 0 with Z set; X = the commas before it. |
| 16 | TAGCMD | $C1EE | Commands::ParseNames | routine | D1541 | parsex 2 | From ':' and '=', each name's start in FILTBL, the counts F1CNT and F2CNT, F2PTR, and IMAGE, the string's shape (bit 7 a pattern in the first names, 6 more than one, 5 first names given; 3, 2 and 1 the same for the second names; 0 no second names). Bits the command's byte of CommandPatterns forbids are a syntax error. |
| 17 | TC25 | $C1F3 | Commands::ParseNames::NoName | local | D1541 | parsex 1 | No ':', or a ',' before it: 34 SYNTAX ERROR (no file given). |
| 18 | TC30 | $C1F8 | Commands::ParseNames::AfterColon | entry | D1541 | parsex 1, copset 1 | With Y past ':' and X its commas, as FindColon leaves them (C comes here): FILTBL = the place before ':', where the drive is. |
| 19 | TC35 | $C200 | Commands::ParseNames::Equals | entry | D1541 | open 1 | With FILTBL set (LOAD comes here): scans on for '='. |
| 20 | TC40 | $C20A | Commands::ParseNames::FirstNames | local | D1541 | parsex 1 | IMAGE's bits 5 and 0 (bit 6 too if more than one name); F1CNT = F2CNT = the names' count, so no second names yet; bit 7 if any had a pattern, and PATFLG cleared. |
| 21 | TC50 | $C228 | Commands::ParseNames::SecondNames | local | D1541 | parsex 1 | Y = 0: no '='. Otherwise the second names' start into FILTBL, F2PTR = F1CNT, and the rest of the string scanned (for shifted RETURN, $8D, which ends it); F2CNT = the names in all. |
| 22 | TC60 | $C245 | Commands::ParseNames::CountSecond | local | D1541 | parsex 1 | Bit 2 if there is more than one second name. |
| 23 | TC70 | $C24C | Commands::ParseNames::SecondGiven | local | D1541 | parsex 1 | Bit 1 set and bit 0 cleared (one EOR does both), with bits 3 and 2. |
| 24 | TC75 | $C254 | Commands::ParseNames::Check | local | D1541 | parsex 1 | IMAGE against the command's byte of CommandPatterns: no bit in both, and it returns. |
| 25 | TC80 | $C260 | Commands::ParseNames::BadSyntax | local | D1541 | parsex 1 | ERWORD = the clashing bits; 30 SYNTAX ERROR. |
| 26 | PARSE | $C268 | Commands::ScanFor | routine | D1541 | parsex 4, block 2, open 1, utlodr 1 | Scans CMDBUF from Y to CMDSIZ for the character A, on the way putting the start of each name after a ',' into FILTBL+1,X and marking in PATTYP the names with '*' or '?' (PATFLG counts them). Returns Y just past the character, or 0 with Z set if it is not there or there are more than MXFILS-1 commas; FILTBL+1,X = CMDSIZ, the end. |
| 27 | PR10 | $C26B | Commands::ScanFor::Next | local | D1541 | parsex 2 | The next character; the string's end is NotFound. |
| 28 | PR20 | $C280 | Commands::ScanFor::Pattern | local | D1541 | parsex 1 | '*' or '?': PATFLG counts it. |
| 29 | PR25 | $C283 | Commands::ScanFor::Comma | local | D1541 | parsex 1 | A ',' ends a name: the next one's start into FILTBL+1,X. |
| 30 | PR28 | $C299 | Commands::ScanFor::NextName | local | D1541 | parsex 1 | X on; at MXFILS-1 names, stops as NotFound. |
| 31 | PR30 | $C29E | Commands::ScanFor::NotFound | local | D1541 | parsex 1 | Y = 0. |
| 32 | PR35 | $C2A0 | Commands::ScanFor::Found | local | D1541 | parsex 1 | The last name's end, CMDSIZ, into FILTBL+1,X, and its pattern mark. |
| 33 | PR40 | $C2B1 | Commands::ScanFor::Return | local | D1541 | parsex 1 | A = Y, Z set if it is 0. |
| 34 | CMDSET | $C2B3 | Commands::Prepare | routine | D1541 | parsex 1, open 1, record 1 | Sets CMDSIZ from the command buffer's count, without a RETURN at the end (or one before the last character); more than CMDLEN characters is 32 SYNTAX ERROR (line too long), with CMDNUM = $FF. Then falls into ClearTables. |
| 35 | CS07 | $C2CA | Commands::Prepare::Whole | local | D1541 | parsex 1 | No RETURN: the whole count. |
| 36 | CS08 | $C2CB | Commands::Prepare::SetSize | local | D1541 | parsex 3 | CMDSIZ = Y, and the length checked. |
| 37 | CMDRST | $C2DC | Commands::Prepare::ClearTables | entry | D1541 | parsex 1, open 1 | Clears the buffer's count, REC, TYPE, TYPFLG, F1PTR, F2PTR, F1CNT, F2CNT, PATFLG and ERWORD, and the MXFILS entries of FILTBL, ENTSEC, ENTIND, FILDRV, PATTYP, FILTRK and FILSEC. LOAD comes here to search by name alone. |
| 38 | CS10 | $C2FD | Commands::Prepare::ClearEntry | local | D1541 | parsex 1 | Each table's entry X-1, from the last. |
| 39 | ONEDRV | $C312 | Commands::SetFirstDrive | routine | D1541 | open 1, new 1 | Takes only the first name: F1CNT = F2CNT, F2CNT = F2PTR = 1; falls into SetDrives. |
| 40 | ALLDRS | $C320 | Commands::SetDrives | routine | D1541 | scrtch 1, copset 1, rename 1, open 1 | For each name, 0 to F2CNT-1: its drive (DriveOfName) into FILDRV, bit 7 if it was not given, and FILTBL moved past its ':'. |
| 41 | AD10 | $C325 | Commands::SetDrives::Next | local | D1541 | setdrv 1 | Each name, F1PTR keeping the index. |
| 42 | SETDRV | $C33C | Commands::DriveOfName | routine | D1541 | setdrv 1 | In: A = the place of a name in CMDBUF. A "0:" or "1:" there gives its drive; a ':' alone, or a letter before ':', gives drive 0; a name with no ':' gives drive 0 with bit 7, defaulted. Out: Y = the drive; A = the place past the ':' when there is one, else the place as it came in. The listing says Y comes in as the default, but the code sets it to 0 (one drive). |
| 43 | SD20 | $C34C | Commands::DriveOfName::Default | local | D1541 | setdrv 1 | Drive 0, not marked as defaulted. |
| 44 | SD22 | $C34D | Commands::DriveOfName::Number | local | D1541 | setdrv 2 | Bit 0 is the drive ('0' or '1', or 0). |
| 45 | SD24 | $C34F | Commands::DriveOfName::Return | local | D1541 | setdrv 1 | Y = the drive, A = the place. |
| 46 | SD40 | $C352 | Commands::DriveOfName::Colon | local | D1541 | setdrv 1 | A ':' after the first character: the character before it, '0' or '1', is the drive. |
| 47 | SETANY | $C368 | Commands::FindDrive | routine | D1541 | parsex 1 | For a command with at most a drive: DRVNUM from the character at FILTBL, or failing that the string's last character, '0' or '1'; with neither, drive 0 and IMAGE = $FF. Then the drive's LEDs (SETLDS). |
| 48 | SA05 | $C370 | Commands::FindDrive::Try | local | D1541 | setdrv 1 | Tests the character at Y; the next try is the last character. |
| 49 | SA10 | $C383 | Commands::FindDrive::Default | local | D1541 | setdrv 1 | No drive given: IMAGE = $FF, drive 0. |
| 50 | SA20 | $C388 | Commands::FindDrive::Found | local | D1541 | setdrv 1 | DRVNUM = bit 0, and the LEDs. |
| 51 | TOGDRV | $C38F | Directory::ToggleDrive | routine | D1541 | lookup 5, trnsfr 2 | DRVNUM to the other drive, 0 or 1. |
| 52 | FS1SET | $C398 | Commands::TakeType | routine | D1541 | scrtch 1, open 1 | With second names, the last is taken off (F2CNT down one) as a file type: its first letter looked up in TYPLST, TYPFLG = the type's number; without, or for a letter not there, 0 (S0:name=P scratches only programs). |
| 53 | FS10 | $C3B0 | Commands::TakeType::Search | local | D1541 | setdrv 1 | Each type letter but the first (D), from the last. |
| 54 | FS15 | $C3B8 | Commands::TakeType::Store | local | D1541 | setdrv 2 | TYPFLG = Y. |
| 55 | TST0V1 | $C3BD | Commands::DriveDigit | routine | D1541 | setdrv 1, open 1 | A = 0 or 1 for the character '0' or '1', N clear; any other character comes back with bit 7 set. |
| 56 | T0V1 | $C3C7 | Commands::DriveDigit::Mask | local | D1541 | setdrv 2 | Keeps bits 7 and 0. |
| 57 | TRNAME | $C66E | Commands::CopyName | routine | D1541 | rename 1, addfil 1, new 1 | Copies the name at X in CMDBUF (to ',' or '=', at most 16 characters) into buffer Y at its pointer, then pads with shifted spaces ($A0) to A characters. |
| 58 | TN10 | $C681 | Commands::CopyName::Pad | local | D1541 | trnsfr 1 | Each shifted space. |
| 59 | TN20 | $C687 | Commands::CopyName::Return | local | D1541 | trnsfr 2 | Returns; the name filled the field. |
| 60 | TRCMBF | $C688 | Commands::CopyToBuffer | routine | D1541 | trnsfr 1 | DIRBUF = buffer Y's pointer; copies CMDBUF from X up to LIMIT there, stopping at the buffer's end. |
| 61 | TR10 | $C697 | Commands::CopyToBuffer::Loop | local | D1541 | trnsfr 1 | Each character. |
| 62 | TR20 | $C6A5 | Commands::CopyToBuffer::Return | local | D1541 | trnsfr 1 | Returns. |
| 63 | FNDLMT | $C6A6 | Commands::FindNameEnd | routine | D1541 | lookup 1, trnsfr 1 | LIMIT = the place of the ',' or '=' that ends the name at X, or the string's end, at most 16 characters on; STRSIZ = its length. X kept. |
| 64 | FL05 | $C6AD | Commands::FindNameEnd::Next | local | D1541 | trnsfr 1 | Each character. |
| 65 | FL10 | $C6C8 | Commands::FindNameEnd::Done | local | D1541 | trnsfr 3 | LIMIT set; X back. |
| 66 | GETNAM | $C6CE | Directory::NextLine | routine | D1541 | trnsfr 1, lstdir 1 | The directory listing's next line, built in NAMBUF (BuildLine), with SA and LINDX kept across it: C clear after the last. |
| 67 | GNSUB | $C6DE | Directory::BuildLine | routine | D1541 | trnsfr 1 | On the internal read channel: the next entry's line, or after the last the blocks-free line (C clear); DRVFLG steps the two-drive listing through a drive's free line and the next drive's header. |
| 68 | GN05 | $C6F7 | Directory::BuildLine::More | local | D1541 | trnsfr 1 | An entry: DRVFLG 0 means its line. |
| 69 | GN050 | $C6FC | Directory::BuildLine::Pending | local | D1541 | trnsfr 1 | DRVFLG counts down: at 0, this drive's blocks-free line (the other drive's DRVNUM for the count) and C set; otherwise the next header. |
| 70 | GN051 | $C70E | Directory::BuildLine::Header | local | D1541 | trnsfr 1 | A drive's header line (HeaderLine), DRVFLG and the line number's high byte cleared; C set. |
| 71 | GN10 | $C71B | Directory::BuildLine::Entry | local | D1541 | trnsfr 1 | A file's line: the blocks (entry bytes 28 and 29) as its line number in NBTEMP, and X where the name ends, one place less for 10 or more blocks and another for 100 or more, so the names line up. |
| 72 | GN12 | $C728 | Directory::BuildLine::Low | local | D1541 | trnsfr 1 | The low byte of the block count. |
| 73 | GN14 | $C73C | Directory::BuildLine::Type | local | D1541 | trnsfr 3 | NAMBUF blanked; the entry's type byte: '<' after a locked file (bit 6), then its three letters from TYPLST, TP1LST and TP2LST. |
| 74 | GN15 | $C74A | Directory::BuildLine::TypeLetters | local | D1541 | trnsfr 1 | The type's three letters, backwards. |
| 75 | GN20 | $C76B | Directory::BuildLine::Name | local | D1541 | trnsfr 1 | A '*' before the type of a file never closed (bit 7 clear), a space, then the 16 characters of the name, backwards. |
| 76 | GN22 | $C773 | Directory::BuildLine::NameCharacters | local | D1541 | trnsfr 1 | Each character, from the 16th. |
| 77 | GN30 | $C783 | Directory::BuildLine::Quote | local | D1541 | trnsfr 1 | A '"' before the name, then a search for its end: a shifted space, a '"' or the line's end. |
| 78 | GN35 | $C793 | Directory::BuildLine::CloseQuote | local | D1541 | trnsfr 2 | The closing '"'. |
| 79 | GN37 | $C798 | Directory::BuildLine::Unshift | local | D1541 | trnsfr 1 | Bit 7 off for the rest, so shifted spaces print as spaces. |
| 80 | GN40 | $C7A7 | Directory::BuildLine::NextEntry | local | D1541 | trnsfr 1 | The next matching entry found (FNDFIL); C set. |
| 81 | GN45 | $C7AB | DROP | local | D1541 | none | Not referenced: the RTS after NextEntry; only the listing names it. |
| 82 | BLKNB | $C7AC | Directory::BlankLine | routine | D1541 | trnsfr 3 | Fills NAMBUF's NBSIZ bytes with spaces. |
| 83 | BLKNB1 | $C7B0 | Directory::BlankLine::Loop | local | D1541 | trnsfr 1 | Each byte, from the last. |
| 84 | NEWDIR | $C7B7 | Directory::HeaderLine | routine | D1541 | trnsfr 1, open 1 | The listing's header line from the BAM, read first: the drive as its line number, reverse on ($12), and the disk name in quotes then its ID and format from the BAM sector, shifted spaces as spaces; a missing format letter is '1'. |
| 85 | ND10 | $C7DC | DROP | local | D1541 | none | Not referenced: the test of the 23rd byte, where a shifted space becomes '1'; only the listing names it (the next instruction's BIT skips HeaderLine::Next's first LDA). |
| 86 | ND15 | $C7E5 | Directory::HeaderLine::Next | local | D1541 | trnsfr 1 | Each byte down to the first: a shifted space becomes a space. |
| 87 | ND20 | $C7ED | Directory::HeaderLine::Store | local | D1541 | trnsfr 2 | Into NAMBUF+2 on. |
| 88 | MSGFRE | $C806 | Directory::FreeLine | routine | D1541 | trnsfr 2 | The line 'BLOCKS FREE.' in NAMBUF, and the free count as its number (NUMFRE). |
| 89 | MSG1 | $C80B | Directory::FreeLine::Loop | local | D1541 | trnsfr 1 | Each character, from the last. |
| 90 | FREMSG | $C817 | Directory::FreeText | table | D1541 | trnsfr 2 | The text 'BLOCKS FREE.'; MSGLEN is its length. |
| 91 | SCRTCH | $C823 | Commands::Scratch | routine | D1541 | romtblsf 2 | S: a type filter (TakeType), the drives, then each matching entry, unless its file is open or locked (bit 6): the entry cleared and written, a relative file's side-sector chain freed, then the file's chain, unless the file was never closed. Ends with 01 FILES SCRATCHED, TRACK the count. (Reached through the command table, so a routine, not a local.) |
| 92 | SC15 | $C835 | Commands::Scratch::Match | local | D1541 | scrtch 1 | An entry that matches: open (TSTCHN) or locked is left. |
| 93 | SC17 | $C855 | Commands::Scratch::Chain | local | D1541 | scrtch 1 | The file's own chain from FILTRK and FILSEC, unless PATTYP's bit 5 says it was never closed. |
| 94 | SC20 | $C86B | Commands::Scratch::Count | local | D1541 | scrtch 1 | R0, the count, up one. |
| 95 | SC25 | $C86D | Commands::Scratch::NextMatch | local | D1541 | scrtch 2 | The next match (FFRE). |
| 96 | SC30 | $C872 | Commands::Scratch::Done | local | D1541 | scrtch 1 | TRACK = the count; to Finish::Report with message 1. |
| 97 | DELFIL | $C87D | Bam::FreeChain | routine | D1541 | scrtch 2, close 1 | Frees a file's blocks from TRACK and SECTOR along their links: each freed in the BAM (FRETS) and read for the next link (on the internal read channel), WBAM's bit 6 set while the BAM is in memory; at the last, the BAM written out (MAPOUT) and the channel freed. CLOSE uses it for a replaced file. |
| 98 | DEL10 | $C894 | Bam::FreeChain::Next | local | D1541 | scrtch 1 | Each block: the link at its start into TRACK and SECTOR; track 0 is the last. One address with DEL2, both in Also. |
| 99 | DEL2 | $C894 | Bam::FreeChain::Next | local | D1541 | scrtch 1 | The listing's second name for DEL10's address, which the loop jumps back to. |
| 100 | DEL1 | $C8AD | Bam::FreeChain::FreeNext | local | D1541 | scrtch 1 | Frees the next block and reads it. |
| 101 | DELDIR | $C8B6 | Directory::DeleteEntry | routine | D1541 | scrtch 1, open 1, verdir 1 | The directory entry at DIRBUF gets type 0 (deleted), and its sector is written and waited for. |
| 102 | DUPLCT | $C8C1 | Commands::Duplicate | routine | D1541 | romtblsf 2, copset 1 | D: there is no second drive to copy to: 31 SYNTAX ERROR. A C without ':' comes here too. (Reached through the command table.) |
| 103 | FORMAT | $C8C6 | Commands::Format | routine | D1541 | new 1, vector 1 | Puts a JMP to the controller's format routine (FORMT) at buffer 3's start ($0600), then gives buffer 3 the execute job for DRVNUM, and waits; a result of 2 or more is the job's error (ERROR). The ROM's vector at $FFE6 points here too. |
| 104 | FMT105 | $C8E0 | Commands::Format::Wait | local | D1541 | duplct 1 | Until the job's bit 7 clears. |
| 105 | FMT110 | $C8EF | Commands::Format::Return | local | D1541 | duplct 1 | Done. |
| 106 | DSKCPY | $C8F0 | Commands::Copy | routine | D1541 | romtblsf 2 | C: the BAM's buffer and the channels freed (the BAM marked out of memory), ':' found (none: Duplicate's error), the names parsed and their drives; one destination name, no patterns, else 30 SYNTAX ERROR; then CopyFiles. (With no pattern bits but IMAGE's bit 7, it also tests whether the first name starts with '*'; a '*' sets bit 7, which the check at NoPatterns rejects anyway, so that test is redundant.) (Reached through the command table.) |
| 107 | DX0000 | $C90C | Commands::Copy::Parse | local | D1541 | copset 1 | The names (ParseNames::AfterColon) and their drives. |
| 108 | DX0005 | $C90F | DROP | local | D1541 | none | Not referenced; only the listing names it. |
| 109 | DX0010 | $C923 | Commands::Copy::BadSyntax | local | D1541 | copset 1 | 30 SYNTAX ERROR. |
| 110 | DX0020 | $C928 | Commands::Copy::NoPatterns | local | D1541 | copset 2 | IMAGE: no pattern, one destination, second names given; then CopyFiles. |
| 111 | PUPS1 | $C932 | Commands::SetUpCopyAll | routine | D1541 | none | Nothing calls it: what is left of copying a whole disk (the rest is commented out in the listing). Clears REC, DRVCNT and the first two FILTRK entries, DRVNUM from the second name's drive, DELSEC nonzero, and the first name's place from the second's. Kept, since its bytes are in the ROM. |
| 112 | COPY | $C952 | Commands::CopyFiles | routine | D1541 | copset 2 | Looks the names up; with two or more sources the first of which is the destination itself (same drive, entry sector and index), the rest are appended to it (a relative file or program cannot be: 64 FILE TYPE MISMATCH); otherwise CreateCopy. Then Finish. |
| 113 | COP01 | $C982 | Commands::CopyFiles::Mismatch | local | D1541 | rename 1 | 64 FILE TYPE MISMATCH. |
| 114 | COP05 | $C987 | Commands::CopyFiles::Append | local | D1541 | rename 1 | The destination's channel moved from the internal read address to the write one, positioned at its end (APPEND), then CreateCopy::CopySources from the second source. |
| 115 | COP10 | $C9A1 | Commands::CopyFiles::ToNew | local | D1541 | rename 4 | An ordinary copy: CreateCopy, then Finish. |
| 116 | CY | $C9A7 | Commands::CreateCopy | routine | D1541 | rename 1 | The sources must exist and the destination not (CheckFiles); the destination opened on the internal write channel and added to the directory; then CopySources from the first source. |
| 117 | CY10 | $C9B9 | Commands::CreateCopy::CopySources | entry | D1541 | rename 2 | For each source from X (F2PTR) to F2CNT-1: opened (OpenSource), a relative one's records made first (CopyRelative), then its bytes put to the write channel; the write channel closed after the last. |
| 118 | CY10A | $C9CE | Commands::CreateCopy::Start | local | D1541 | rename 1 | EOIFLG to 'not the end'. |
| 119 | CY15 | $C9D5 | Commands::CreateCopy::Put | local | D1541 | rename 1 | The byte to the write channel (PIBYTE). |
| 120 | CY20 | $C9D8 | Commands::CreateCopy::NextByte | local | D1541 | rename 1 | The next byte (GetInternalByte), until the last-record flag is set. |
| 121 | CY30 | $C9EA | Commands::CreateCopy::NextFile | local | D1541 | rename 1 | The next source, if any; else the copy's channel and file closed. |
| 122 | OPIRFL | $C9FA | Commands::OpenSource | routine | D1541 | rename 2 | Opens source F2PTR for reading on the internal channel: its drive, its entry (directory track, ENTSEC, ENTIND), TYPE from PATTYP, then OPREAD; the pointer at its first data byte (1 for a relative file, 2 for others). |
| 123 | OPIR10 | $CA31 | Commands::OpenSource::SetPointer | local | D1541 | rename 1 | The pointer to Y. |
| 124 | GIBYTE | $CA35 | Commands::GetInternalByte | routine | D1541 | utlodr 2, rename 1 | The next byte of the internal read channel into DATA; falls into AnyChannel. |
| 125 | GCBYTE | $CA39 | Commands::GetInternalByte::AnyChannel | entry | D1541 | open 1 | The same from the channel SA selects (APPEND comes here): DATA = the byte, EOIFLG = 0 if it was the last, and then for a file that is not relative the channel's last-record flag (LRF) set. |
| 126 | GIB20 | $CA52 | Commands::GetInternalByte::Return | local | D1541 | rename 2 | Returns. |
| 127 | CYEXT | $CA53 | Commands::CopyRelative | routine | D1541 | rename 1 | A relative source: finds the last side sector of the source and of the copy, then adds records to the copy (Relative's ADDR1) until it is as long as the source. |
| 128 | RENAME | $CA88 | Commands::Rename | routine | D1541 | romtblsf 2 | R: both names' drives (both drives searched if they differ), looked up; the old name must exist and the new not (CheckFiles). The old entry's sector read, the new name written over the old (16 characters, padded), and the sector written back. (Reached through the command table.) |
| 129 | RN10 | $CA97 | Commands::Rename::LookUp | local | D1541 | rename 1 | FILDRV set; both names looked up. |
| 130 | CHKIN | $CACC | Commands::CheckSources | routine | D1541 | rename 2 | TYPE = the first source's type; each source, F2CNT-1 down to F1CNT, must have been found (FILTRK not 0), else 62 FILE NOT FOUND. Returns X = F1CNT-1. |
| 131 | CK10 | $CAD6 | Commands::CheckSources::Next | local | D1541 | rename 1 | Each source. |
| 132 | CK20 | $CAE6 | Commands::CheckSources::Return | local | D1541 | rename 1 | All found. |
| 133 | CHKIO | $CAE7 | Commands::CheckFiles | routine | D1541 | rename 2 | CheckSources, then each destination name, F1CNT-1 down to 0, must not exist, else 63 FILE EXISTS. |
| 134 | CK25 | $CAEA | Commands::CheckFiles::Test | local | D1541 | rename 1 | Found is the error. |
| 135 | CK30 | $CAF4 | Commands::CheckFiles::Next | local | D1541 | rename 1 | The next name down. |
| 136 | MEM | $CAF8 | Commands::Memory | routine | D1541 | romtblsf 2 | M-R, M-W and M-E: the '-' must be character 1 (else 31 SYNTAX ERROR); the address from characters 3 and 4 into TEMP. M-R reads, M-W writes from character 6 on (character 5 the count), M-E jumps to the address. None ends through Finish: they return to the idle loop with the error channel as Execute set it, 00 OK (JSR OKERR at $C150). (Reached through the command table.) |
| 137 | MEMEX | $CB1D | DROP | local | D1541 | none | Not referenced: M-E's JMP (TEMP); only the listing names it. |
| 138 | MEMRD | $CB20 | Commands::Memory::Read | local | D1541 | memrw 1 | M-R: the byte at the address into DATA; with a count (character 5) of 0 or 2 or more, the error channel's pointer set to the address and its last byte to the address plus the count less one (0 gives 256 bytes), so the bytes are read on channel 15 straight from memory; a count of 1, or none, takes OneByte. |
| 139 | M30 | $CB45 | Commands::Memory::OneByte | local | D1541 | memrw 2 | One byte: Files' NextByte::ErrorEnd (GE15) resets the error channel's pointer to ERRBUF-1, and NextByte::ErrorReady (GE20) makes DATA ready to talk. |
| 140 | MEMERR | $CB4B | Commands::Memory::BadSyntax | local | D1541 | memrw 2 | 31 SYNTAX ERROR. |
| 141 | M10 | $CB50 | Commands::Memory::Write | local | D1541 | memrw 1 | M-W: each of the count's bytes from CMDBUF+6 to the address (at least one, even for a count of 0); returns. One address with MEMWRT, both in Also. |
| 142 | MEMWRT | $CB50 | Commands::Memory::Write | local | D1541 | memrw 1 | The listing's second name for M10's address. |
| 143 | USER | $CB5C | Commands::User | routine | D1541 | romtblsf 2 | U: U0 falls into Reset and returns by its RTS, without Finish; any other runs its entry (UserJump), then Finish. (Reached through the command table.) |
| 144 | USRINT | $CB63 | Commands::User::Reset | entry | D1541 | dskintsf 1 | UserVectorsPointer = UserCommandVectors, the ROM's table. Start-up calls it. |
| 145 | US10 | $CB6C | Commands::User::Run | local | D1541 | block 1 | The entry for the character, then Finish. |
| 146 | USREXC | $CB72 | Commands::UserJump | routine | D1541 | block 1 | Jumps through entry ((Y-1) and 15) of the table at UserVectorsPointer, by IP: U1 or UA the first, U2 the second ... U9 or UI the ninth, U: or UJ the tenth. |
| 147 | OPNBLK | $CB84 | Files::OpenDirect | routine | D1541 | open 1 | OPEN "#": a direct-access channel for the block commands. The disk initialised if needed (SA kept across it); "#" alone takes any free buffer, "#n" buffer n if it is free (fewer than BFCNT, 5: the listing's comment says 13), else 70 NO CHANNEL. Files' OPEN jumps here. |
| 148 | OB05 | $CBA0 | Files::OpenDirect::NoChannel | local | D1541 | block 3 | 70 NO CHANNEL. |
| 149 | OB10 | $CBA5 | Files::OpenDirect::Requested | local | D1541 | block 1 | "#n": n from character 1 (BlockParameters::FromY) into FILSEC; marked used in BUFUSE if it was free, and given the drive's job. |
| 150 | OB15 | $CBB8 | Files::OpenDirect::Bit | local | D1541 | block 1 | The buffer's bit in TEMP, TEMP+1. |
| 151 | OB30 | $CBF1 | Files::OpenDirect::SetChannel | local | D1541 | block 1 | The channel set up: LINTAB's bit 6 (it can write), LSTCHR $FF, ready to talk and listen, the buffer's number as its first byte to read, the pointer at 1, the direct type. Then Finish. |
| 152 | BLOCK | $CC1B | Commands::Block | routine | D1541 | romtblsf 2 | B-: finds the '-', looks the next letter up in Subcommands (no ',' before it, else 30; not there, 31), CMDNUM = its index with bit 7, the parameters parsed (BlockParameters), and jumps to its handler. (Reached through the command table.) |
| 153 | BLK10 | $CC26 | Commands::Block::BadCommand | local | D1541 | block 1 | 31 SYNTAX ERROR (no '-' or an unknown letter). |
| 154 | BLK30 | $CC2B | Commands::Block::BadSyntax | entry | D1541 | block 2 | 30 SYNTAX ERROR; an entry of Block, since BlockParameters (BCS at $CC9F, outside Block) comes here with too many numbers. |
| 155 | BLK40 | $CC30 | Commands::Block::Dash | local | D1541 | block 1 | The '-': no ',' before it, then the letter after. |
| 156 | BLK50 | $CC38 | Commands::Block::Search | local | D1541 | block 1 | Each letter, from the last. |
| 157 | BLK60 | $CC42 | Commands::Block::Dispatch | local | D1541 | block 1 | The handler from SubcommandHandlers into TEMP, and jumps there. |
| 158 | BCTAB | $CC5D | Commands::Block::Subcommands | table | D1541 | block 2 | The block commands' letters: A, F, R, W, E, P. |
| 159 | BCJMP | $CC63 | Commands::Block::SubcommandHandlers | table | D1541 | block 2 | Their handlers, in Subcommands' order: BlockAllocate, BlockFree, BlockRead, BlockWrite, BlockExecute, SetBufferPosition. |
| 160 | BLKPAR | $CC6F | Commands::BlockParameters | routine | D1541 | block 3 | The numbers after ':', or from character 3 without one, separated by spaces, commas or cursor-rights (29), each into the parameter list (ParseNumber), F1CNT counting them; a fifth is 30 SYNTAX ERROR. |
| 161 | BP05 | $CC7C | Commands::BlockParameters::FromY | entry | D1541 | block 3 | From character Y (OpenDirect comes here for "#n"). |
| 162 | BP10 | $CC8B | Commands::BlockParameters::Skip | local | D1541 | block 3 | Past a separator; at the string's end, returns. |
| 163 | BP20 | $CC92 | Commands::BlockParameters::Number | local | D1541 | block 1 | A number, then the next. |
| 164 | ASCHEX | $CCA1 | Commands::ParseNumber | routine | D1541 | block 1 | The decimal number at Y (its last three digits count; any of $30-$3F is a digit, its low four bits) into FILSEC,X (low) and FILTRK,X (high) at X = F1CNT; F2PTR = the place after it. |
| 165 | AH10 | $CCAB | Commands::ParseNumber::Digit | local | D1541 | block 1 | Each digit, the earlier ones moved up through TEMP, TEMP+1, TEMP+2. |
| 166 | AH20 | $CCCA | Commands::ParseNumber::Convert | local | D1541 | block 2 | F2PTR = Y; the digits times their place values summed. |
| 167 | AH30 | $CCD0 | Commands::ParseNumber::Place | local | D1541 | block 1 | Each place, units first (X from $FF; the first INX gives 0, DECTAB,0 = 1; TEMP holds the last digit), then tens and hundreds. |
| 168 | AH35 | $CCD7 | Commands::ParseNumber::Add | local | D1541 | block 2 | Adds the place value once per unit of the digit, carrying into TEMP+3. |
| 169 | AH40 | $CCE4 | Commands::ParseNumber::Store | local | D1541 | block 1 | Into the parameter list at F1CNT. |
| 170 | DECTAB | $CCF2 | Commands::PlaceValues | table | D1541 | block 1 | 1, 10, 100, the decimal places. |
| 171 | BLKFRE | $CCF5 | Commands::BlockFree | routine | D1541 | block 1 | B-F drive track sector: checked (CheckBlock), freed in the BAM, then Finish. Five bytes after it, LDA #1 and STA WBAM, are reached by nothing. |
| 172 | BLKALC | $CD03 | Commands::BlockAllocate | routine | D1541 | block 1 | B-A drive track sector: a free block is allocated (WUSED); a used one is 65 NO BLOCK with the next free block after it in the message, or track and sector 0 when none is left. |
| 173 | BA10 | $CD06 | DROP | local | D1541 | none | Not referenced; only the listing names it. |
| 174 | BA15 | $CD19 | Commands::BlockAllocate::NextTrack | local | D1541 | block 1 | None free above it on this track: the sector off the stack. |
| 175 | BA20 | $CD1A | Commands::BlockAllocate::Search | local | D1541 | block 1 | Sector 0 of each later track, up to MAXTRK, for a free one. |
| 176 | BA30 | $CD2C | Commands::BlockAllocate::Taken | local | D1541 | block 1 | 65 NO BLOCK, with the free block's track and sector (CMDER2 keeps them). |
| 177 | BA40 | $CD31 | Commands::BlockAllocate::Full | local | D1541 | block 1 | 65 NO BLOCK, track and sector 0. |
| 178 | BLKRD2 | $CD36 | Commands::FetchBlock | routine | D1541 | block 2 | Checks the channel and the block (CheckChannelBlock), and reads it into the channel's buffer (Jobs::ReadTrackSector). |
| 179 | GETSIM | $CD3C | Commands::PeekByte | routine | D1541 | block 1 | The channel's byte at its pointer, without moving it; Y = LINDX. |
| 180 | BLKRD3 | $CD42 | Commands::FetchCountedBlock | routine | D1541 | block 2 | FetchBlock, then the block's first byte into LSTCHR, the last byte to read, and the channel ready. |
| 181 | BLKRD | $CD56 | Commands::BlockRead | routine | D1541 | block 1 | B-R channel drive track sector: the block, read from byte 1 to the count in byte 0. Then Finish. |
| 182 | UBLKRD | $CD5F | Commands::UserRead | routine | D1541 | vector 1 | U1 (the first entry of UserCommandVectors): the parameters (User does not parse them), the block, and all 256 bytes to read from byte 0, LSTCHR $FF. Then Finish. |
| 183 | BLKWT | $CD73 | Commands::BlockWrite | routine | D1541 | block 1 | B-W channel drive track sector: byte 0 = the channel's pointer less one (the bytes written, at least 1), the block written, the channel's next byte made ready. Then Finish. |
| 184 | BW10 | $CD81 | Commands::BlockWrite::SetCount | local | D1541 | block 1 | The count into byte 0. |
| 185 | BW20 | $CD8C | DROP | local | D1541 | none | Not referenced; only the listing names it. |
| 186 | UBLKWT | $CD97 | Commands::UserWrite | routine | D1541 | vector 1 | U2 (UserCommandVectors' second entry): the parameters, then the buffer written as it is. Then Finish. |
| 187 | BLKEXC | $CDA3 | Commands::BlockExecute | routine | D1541 | block 1 | B-E channel drive track sector: the block read into the channel's buffer and called at its first byte; then Finish. |
| 188 | BE05 | $CDAB | DROP | local | D1541 | none | Not referenced; only the listing names it. |
| 189 | BE10 | $CDBA | Commands::BlockExecute::Call | local | D1541 | block 1 | JMP (TEMP), which the JSR before it makes a call. |
| 190 | BLKPTR | $CDBD | Commands::SetBufferPosition | routine | D1541 | block 1 | B-P channel position: the channel's buffer pointer set to the position, its byte made ready to read. Then Finish. |
| 191 | BUFTST | $CDD2 | Commands::FindBlockChannel | routine | D1541 | block 2 | The next parameter (F1PTR, moved on) as a channel: 2 to 13 with an open channel, else 70 NO CHANNEL; SA and JOBNUM, its buffer, set. |
| 192 | BT15 | $CDE0 | Commands::FindBlockChannel::NoChannel | local | D1541 | block 1 | 70 NO CHANNEL. |
| 193 | BT20 | $CDE5 | Commands::FindBlockChannel::Valid | local | D1541 | block 1 | SA set and the channel found. |
| 194 | BKOTST | $CDF2 | Commands::CheckChannelBlock | routine | D1541 | block 3 | FindBlockChannel; falls into CheckBlock. |
| 195 | BLKTST | $CDF5 | Commands::CheckBlock | routine | D1541 | block 2 | From the parameters at F1PTR: DRVNUM, TRACK and SECTOR; the track and sector checked (TSCHK), then the LEDs. |
| 196 | BT05 | $CE08 | DROP | local | D1541 | none | Not referenced; only the listing names it. |
| 197 | BOOT2 | $E77F | DROP | local | D1541 | none | Not referenced: an RTS nothing reaches, the removed boot loader's exit; named in Startup::Boot's prose. |
| 198 | BOOT | $E780 | Startup::Boot | routine | D1541 | dskintsf 1 | Start-up calls it last: only an RTS, where the boot loader was (it ran a utility when clock and data were grounded; it does not work on the serial bus). 34 bytes of filler follow, NOPs and an RTS. |
| 199 | BOOT3 | $E780 | DROP | local | D1541 | none | Not referenced, at Boot's address: the removed loader's wait for the clip; named in Boot's prose. |
| 200 | UTLODR | $E7A3 | Commands::LoadUtility | routine | D1541 | romtblsf 2 | &: the name (the string scanned to its end), looked up (not found: 39); opened as a user file (type 3; the listing's comment says 5); then each record, an address, a count, the bytes and a checksum, stored; a bad checksum is 50, an early end 51. Jumps to the first record's address, F2CNT kept for the utility. (Reached through the command table.) |
| 201 | BOOT4 | $E7A8 | DROP | local | D1541 | none | Not referenced: where the removed boot loader joined; only the listing names it. |
| 202 | UTLD00 | $E7C5 | Commands::LoadUtility::Found | local | D1541 | utlodr 1 | F2CNT back; the file's first block from FILTRK and FILSEC, and opened. |
| 203 | UTLD10 | $E7D8 | Commands::LoadUtility::NextRecord | local | D1541 | utlodr 1 | R1, the checksum, cleared; the address into R2 and R3, kept on the stack for the first record (R0 flags it). |
| 204 | UTLD20 | $E7FA | Commands::LoadUtility::ReadCount | local | D1541 | utlodr 1 | The byte count into R4. |
| 205 | UTLD30 | $E802 | Commands::LoadUtility::StoreByte | local | D1541 | utlodr 1 | Each byte to the address, into the checksum. |
| 206 | UTLD35 | $E817 | Commands::LoadUtility::CountDown | local | D1541 | utlodr 1 | R4 down; then the checksum byte compared. |
| 207 | UTLD50 | $E82C | Commands::LoadUtility::CheckEnd | local | D1541 | utlodr 1 | Not the file's end: the next record; at the end, jumps to the first record's address. |
| 208 | GTABYT | $E839 | Commands::LoadUtility::GetByte | routine | D1541 | utlodr 4 | The next byte (GetInternalByte) in A; if it was the file's last, 51 (the record overran), with the block's track and sector. |
| 209 | GTABYE | $E848 | Commands::LoadUtility::GetByte::Return | local | D1541 | utlodr 1 | A = DATA. |
| 210 | ADDSUM | $E84B | Commands::LoadUtility::AddToChecksum | routine | D1541 | utlodr 4 | R1 = R1 + A, the carry added back in. |
| 211 | NEW | $EE0D | Commands::New | routine | D1541 | romtblsf 2 | N: the drive (not given: 33 SYNTAX ERROR); with an ID, the disk formatted (channels cleared, Format, the BAM zeroed); without, only the directory cleared, on a disk of this format. Then a new BAM with the name, ID, DOS version and format, the BAM's and first directory block marked used and written, and an empty first directory block. Then Finish. (Reached through the command table.) |
| 212 | N101 | $EE19 | Commands::New::Drive | local | D1541 | new 1 | DRVNUM and the LEDs; the ID, after the ',', into DSKID if given. |
| 213 | N108 | $EE46 | Commands::New::Clear | local | D1541 | new 1 | No ID: the directory cleared (INITDR), and the disk's format must be VERNUM's, else 73 (VNERR). |
| 214 | N110 | $EE56 | Commands::New::Build | local | D1541 | new 2 | The new BAM (NEWMAP), the name (CopyName, 27 places), the ID, '2' and VERNUM into the BAM sector, the BAM and directory blocks used; the BAM and the empty directory block written, and the BAM read back. |
| 215 | SD50 | $C361 | Commands::DriveOfName::NoColon | local | D1541 | setdrv 1 | No ':' after the name: drive 0 with bit 7 (defaulted). The listing defines it as an equate (=*), but it is a label; not a constant. |

## Part 4: the directory, the BAM, and the files and channels

Settled on 2026-11-27 after an independent review of the part (D2, D7).

The listing's `lookup`, `tst2`, `tst3`, `tst4`, `tstfnd`, `lstdir` and `verdir` (the directory, and the channel and
buffer helpers), `map` and `frets` (the BAM), and `open`, `close`, `opnchnl`, `tstflg` and `addfil` (OPEN, CLOSE
and the channels): `$C3CA-$C66D`, `$CEFA-$D505`, `$D6E4-$DDF0` and `$EC9E-$F257` (less the new command's code between
`verdir` and `map`): 399 names, 397 labels and two tables (SCHTBL, BMASK). `getact` and `nulbuf` are part 5's rows. The
variables in the reasons are part 1's, by their
listing names (LINDX, BUF0, LINTAB). The code is Commodore's two-drive DOS cut down to one drive: DRVNUM,
TOGDRV and the two-drive search stay, and the names say "drive" where the code chooses one (Q9). Relative files
are part 5's; the routines here they use are said to be shared in their reasons.

### Questions

- D-P4-Q1. **Where Directory ends and Files begins in OPEN's name lookup.** Directory owns everything that reads or
  writes a directory entry: choosing the drives (OPTSCH), finding and matching names (LOOKUP, FFRE/FFST/FNDFIL,
  COMPAR, CMPCHK, SRCHST/SRRE/SEARCH), adding an entry (ADDFIL), allocating a directory block (NXDRBK), closing
  a written file's entry (CLSDIR), the listing (STDIR, GETDIR, MOVBUF) and Validate (VERDIR). Files owns OPEN's and
  CLOSE's own steps: parsing the name, mode and type (CKTM), choosing read, write, replace, append or modify, and
  opening the channel; it calls `Directory::FindFile::First` and `Directory::AddEntry`. LOADIR, OPEN's "$" branch
  in `open`, is `Files::LoadDirectory`: it parses the pattern and hands the listing to `Directory::StartListing`.
  *Recommended.* The brief lists `addfil` under Files; the alternative is `Files::AddEntry` and
  `Files::CloseEntry`, as the files have them, but both write the directory and the Directory family's own
  description ("adding and changing entries") covers them. **Settled:** Directory owns everything that reads or writes a
  directory entry, Files owns OPEN's and CLOSE's own steps, and LOADIR is `Files::LoadDirectory`.
- D-P4-Q2. **The channels and buffers are one scope, Files.** The channel indexes (FNDLNX, LINUSE), getting and
  freeing a channel (GETRCH/GETWCH, FRECHN, CLRCHN, CLDCHN, FREICH), the buffer pool (GETBUF, FNDBUF, FREBUF,
  FREIAC, STLBUF and the LRU table), a channel's two buffers (DBLBUF, DBSET, TGLBUF, INITP) and its bytes and
  pointers (GETBYT, RDBYT, PUTBYT, WRTBYT, SETPNT, GETPNT, DRDBYT) are all `Files::`, though Bam, Directory and
  Relative call them: they are the channels' machinery, and the families are few enough that a separate `Buffers`
  scope would be the only one not in the brief. Nothing of it is top level but BMASK (Q8). *Recommended.* **Settled:**
  The channels and buffers are all `Files::`, with only BMASK top level.
- D-P4-Q3. **The tst2-tst4 helpers, by what each does.** Most are Files (Q2). The rest: INTDRV is the I command's
  routine, `Commands::Initialize`; INITDR, ITRIAL and AUTOI (and NFCALC, which INITDR falls into) read a disk's ID
  and BAM, so they are `Bam::InitializeDrive`, `Bam::SeekHeader`, `Bam::AutoInitialize` and
  `Bam::CountFreeBlocks` (AUTOI is in `lookup`, but is the same work); DRTRD and DRTWRT set a buffer's header,
  start its job and wait, which is Jobs' description: `Jobs::ReadTrackSector` and `Jobs::WriteTrackSector`; NXDRBK
  allocates a directory block, `Directory::NewBlock`. PUTSS, in `opnchnl`, puts a byte in a side sector, so it is
  `Relative::PutSideSectorByte` (part 5's rows cite it by that name). *Recommended.* The alternative is to scope by
  file, which puts the I command and the job calls in Files. **Settled:** The tst2-tst4 helpers are scoped by what they
  do: I is `Commands::Initialize`, the disk-reading ones `Bam::`, DRTRD and DRTWRT `Jobs::ReadTrackSector` and
  `Jobs::WriteTrackSector`, NXDRBK `Directory::NewBlock` and PUTSS `Relative::PutSideSectorByte`.
- D-P4-Q4. **Routines that share one body.** FFRE, FFST and FNDFIL branch into each other's code, and so do SRCHST,
  SRRE and SEARCH; each trio is one routine whose entries are its starts: `Directory::FindFile` (FFRE, at its
  start) with `First` and `Next`, and `Directory::Search` (SRCHST) with `Again` and `Next`. Elsewhere a routine
  that only falls into the next one (COMPAR into CMPCHK, INITDR into NFCALC, MAPOUT into SCRBAM, WUSED into
  USEDTS, FREIAC into FREBUF, OPWRIT into OPFIN's code) stays its own routine, saying so; a label another routine
  branches to is an entry (CC10, DBL30, STRTIT, DRT, GETR2, CLRF10, FRI20, USE10, FREUS3, DERR, L40, L42).
  *Recommended.* **Settled:** Routines sharing a body are one routine with entries, `Directory::FindFile` and
  `Directory::Search`, and a routine that only falls into the next stays its own.
- D-P4-Q5. **Two names at one address.** Nine addresses have two or three of the listing's names (CMPCHK and
  CP50, INCPTR and INCPNT, FRECO, FRERD and FREWRT, GP1 and SETDIR, VERDIR and VALDAT, NEWMAP and NEWMPV, FRE10 and
  FRERTS, NXTDS and NXT1, DERR and FND2): one name, with every listing name in its `Also:`, as K-P5-Q2 did for
  NMIRTI and PREND, whether or not the second is referenced. The other 19 labels nothing references are dropped,
  as the kernal's were (RD0, RD01, GETR52, OP02, OP77 ...). *Recommended.* **Settled:** Each address with two or three
  listing names gets one name with the rest in `Also:`, and the 19 unreferenced labels are dropped.
- D-P4-Q6. **Dead routines.** WFREE (FIXBAM, then into FRETS) and SCFLG (set or clear a flag by carry) are code
  nothing calls. As K-P2-Q7 kept VPAN, each keeps a name so the code has a `.proc`, its comment saying nothing
  calls it: `Bam::FlushAndMarkFree` and `Files::SetOrClearFlag`. *Recommended.* **Settled:** WFREE and SCFLG keep names
  (`Bam::FlushAndMarkFree`, `Files::SetOrClearFlag`) with a comment that nothing calls them.
- D-P4-Q7. **The code's slips are documented, not changed** (K-P7-Q5). FRETS, freeing a block on the directory
  track, branches to USEDTS's count down (`beq use10`, `$EF7D`), so the free count goes down instead of staying;
  that count down skips the borrow, so NDBH is not decremented when NDBL was 0 (off by 256), and it falls into
  USE20's check, so with fewer than 3 blocks left a free can raise error 72, DISK FULL;
  OPEN's ENDRD loads X but stores FILTYP through Y, which works because the read leaves Y = LINDX; AUTOI's
  comments swap job results 2 and 3 (2 is no header, 3 no sync); CLRCHN frees SA 14 to 1, not 0, unlike CLDCHN; that
  last one is a difference between two routines, not a slip, and is said in CLRCHN's comment. The slips are each said in
  the routine's comment. *Recommended.* **Settled:** The slips, FRETS's directory-track branch included with its missing
  borrow and its fall into the DISK FULL check, are documented in the routines' comments and not changed, and CLRCHN's
  counting to 1 is documented as a difference, not a slip.
- D-P4-Q8. **Two top-level names.** BMASK, the eight bit masks, serves the BAM's routines and the buffer pool's
  (BUFUSE): top-level `BitMasks`. MAXSEC reads the zone tables (top level) and serves Jobs' track check as much
  as the BAM: top-level `SectorsOnTrack`, the routine that returns the count for a track in A, not part 1's
  `Controller::SectorCount` (SECTR), the zero-page count for the job's track. *Recommended*; the alternative is
  `Bam::SectorsOnTrack`, by its file. **Settled:** BMASK is top-level `BitMasks` and MAXSEC is top-level
  `SectorsOnTrack`, distinct from part 1's `Controller::SectorCount`.
- D-P4-Q9. **The second drive.** The 1541 has one drive, but the code keeps the two-drive DOS's: DRVNUM, DRVCNT, the
  drive bits in FILDRV and the search table SCHTBL. The names describe what the code does (`Directory::ChooseDrives`,
  `Directory::SearchOrder`), and the comments say drive 1 never answers on the 1541. *Recommended.* **Settled:** The
  two-drive code keeps its structure, named for what it does (`Directory::ChooseDrives`, `Directory::SearchOrder`), with
  comments that drive 1 never answers.
- D-P4-Q10. **Two commands found here.** INTDRV (I) and VERDIR (V) are the command table's targets. INTDRV goes to
  Commands (Q3). VERDIR is Validate, which the brief's families put in Directory, where its work is: a walk of the
  directory that rebuilds the BAM; `Directory::Validate`, with VMKBAM as `Directory::MarkChain`. *Recommended*;
  the alternative is `Commands::Validate`, beside the other commands. **Settled:** INTDRV is `Commands::Initialize` and
  VERDIR is `Directory::Validate`, with VMKBAM as `Directory::MarkChain`.
- D-P4-Q11. **Locals named for a family.** No local is named for a scope (K-P6-Q5): CLSREL is
  `CloseChannel::RelativeFile`, and OPNWCH's relative branch `OpenWriteChannel::RelativeFile`. *Recommended.*
  **Settled:** No local is named for a scope or for a top-level name, so CLSREL is `CloseChannel::RelativeFile` and
  OPNWCH's relative branch `OpenWriteChannel::RelativeFile`, and the colliding locals are renamed.

### Rows

| # | Old | Address | New | Kind | Documents (checked) | Used in | Reason |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | OPTSCH | $C3CA | Directory::ChooseDrives | routine | D1541 | lookup 2, open 2, scrtch 1 | Sets DRVCNT and DRVNUM, the drives to search for the stream's names, from the drives they name (FILDRV, through SCHTBL); checks each for a new disk (AutoInitialize), leaving out one with none, with error 74, DRIVE NOT READY, when neither has one. Ends by turning on the LED. |
| 2 | OS10 | $C3D5 | Directory::ChooseDrives::NextName | local | D1541 | lookup 2 | Each name, from the last: adds its drive bit to the mask on the stack. |
| 3 | OS15 | $C3E8 | Directory::ChooseDrives::DriveBit | local | D1541 | lookup 1 | Drive 1's bit is the one for drive 0 shifted once. |
| 4 | OS30 | $C3EF | Directory::ChooseDrives::Choose | local | D1541 | lookup 1 | The mask picks SCHTBL's entry: DRVCNT is its bits 0-1. |
| 5 | OS35 | $C400 | Directory::ChooseDrives::SetDrive | local | D1541 | lookup 1 | DRVNUM = bit 0 of A; with one drive to search, it is checked alone. |
| 6 | OS45 | $C41B | Directory::ChooseDrives::NotReady | local | D1541 | lookup 1 | Error 74, DRIVE NOT READY. |
| 7 | OS50 | $C420 | Directory::ChooseDrives::CheckOther | local | D1541 | lookup 1 | The first drive has a disk: the other is checked too (DRVNUM put back), and left out of the search if it has none. |
| 8 | OS60 | $C434 | Directory::ChooseDrives::OneDrive | local | D1541 | lookup 1 | One drive: error 74 if it has no disk. |
| 9 | OS70 | $C439 | Directory::ChooseDrives::Done | local | D1541 | lookup 3 | On to TurnOnActivityLed (SETLDS). |
| 10 | OS40 | $C43C | Directory::ChooseDrives::FixedDrive | local | D1541 | lookup 1 | Bit 6 clear: the entry's bit 7 is the drive to start on. |
| 11 | SCHTBL | $C440 | Directory::SearchOrder | table | D1541 | lookup 1 | For each mask of drives the names ask for (bits 0-1 named, 2-3 by default): bits 0-1 the drives after the first to search, bit 6 set to start on the first name's drive, else bit 7 the drive. |
| 12 | LOOKUP | $C44F | Directory::FindAll | routine | D1541 | rename 2, utlodr 1 | LOOKUP: looks up every name in the stream on the drives ChooseDrives picks, filling the tables (FILTRK, FILSEC, PATTYP, ENTSEC, ENTIND) for each found; FOUND nonzero once all are. |
| 13 | LK05 | $C452 | Directory::FindAll::SearchDrive | local | D1541 | lookup 1 | A search from the drive's first directory block (DELIND = 0: in-use entries only). |
| 14 | LK10 | $C45C | Directory::FindAll::NextDrive | local | D1541 | lookup 1 | The directory is used up: on to the other drive, if DRVCNT says so. |
| 15 | LK15 | $C462 | Directory::FindAll::OtherDrive | local | D1541 | lookup 1 | DRVFLG set, the drive toggled and its LED on. |
| 16 | LK20 | $C470 | Directory::FindAll::NextEntry | local | D1541 | lookup 1 | The next entry in use; Z set at the directory's end. |
| 17 | LK25 | $C475 | Directory::FindAll::Compare | local | D1541 | lookup 2 | The entry against the names not yet found. |
| 18 | LK26 | $C47E | Directory::FindAll::NotAllFound | local | D1541 | lookup 1 | ENTFND minus: no name matched, so the next entry; else the same entry again for the other names. |
| 19 | LK30 | $C485 | Directory::FindAll::EndOfDirectory | local | D1541 | lookup 1 | Not all found: the other drive. |
| 20 | FFRE | $C48B | Directory::FindFile | routine | D1541 | scrtch 1 | FFRE: the next entry matching any name in the stream, after the one last found, whose sector (DIRSEC) is read again; its details go in the tables. The three find routines share one body. |
| 21 | FF15 | $C492 | Directory::FindFile::OtherDrive | local | D1541 | lookup 1 | DRVFLG set, the drive toggled and its LED on, then a search from its start. |
| 22 | FFST | $C49D | Directory::FindFile::First | entry | D1541 | open 2, scrtch 1 | FFST: the first matching entry, from the start of the directory (Files::Open and the scratch command enter here). |
| 23 | FF10 | $C4AA | Directory::FindFile::EndOfDirectory | local | D1541 | lookup 2 | Done if FOUND says so, else the other drive, if DRVCNT has one left. |
| 24 | FNDFIL | $C4B5 | Directory::FindFile::Next | entry | D1541 | lookup 3, trnsfr 1 | FNDFIL: the next matching entry, going on with the search without reading the sector again (the transfer code enters here). |
| 25 | FF25 | $C4BA | Directory::FindFile::Compare | local | D1541 | lookup 2 | The entry against the names; no match, and not all found: the next entry. |
| 26 | FF30 | $C4C9 | Directory::FindFile::CheckType | local | D1541 | lookup 1 | A match: with TYPFLG set, its type must be that one, or the search goes on. |
| 27 | FF40 | $C4D7 | Directory::FindFile::Done | local | D1541 | lookup 3 | Returns. |
| 28 | COMPAR | $C4D8 | Directory::MatchEntry | routine | D1541 | lookup 3 | Compares the entry at DIRBUF with each name in the stream not yet found, on its drive, with ? and * as patterns; on a match ENTFND = the name's index and its tables get the entry's type, track, sector, place and record size. Falls into NextUnfound. |
| 29 | CP02 | $C4E6 | Directory::MatchEntry::Done | local | D1541 | lookup 1 | Every name found: returns. |
| 30 | CP05 | $C4E7 | Directory::MatchEntry::NextName | local | D1541 | lookup 5 | The next name not yet found. |
| 31 | CP10 | $C4EC | Directory::MatchEntry::CheckDrive | local | D1541 | lookup 1 | The name's drive must be this one, or a default drive while both are searched. |
| 32 | CP20 | $C4FE | Directory::MatchEntry::CompareName | local | D1541 | lookup 1 | From the name's start (FILTBL, FNDLMT for its end) and the entry's byte 3. |
| 33 | CP30 | $C50A | Directory::MatchEntry::CompareCharacter | local | D1541 | lookup 1 | A character that differs fails unless it is ? and the entry's name has not ended (shifted space). |
| 34 | CP32 | $C51B | Directory::MatchEntry::NextCharacter | local | D1541 | lookup 1 | Both indexes on. |
| 35 | CP33 | $C51D | Directory::MatchEntry::CheckPattern | local | D1541 | lookup 1 | At the pattern's end (LIMIT), or a * that matches the rest. |
| 36 | CP34 | $C52B | Directory::MatchEntry::EndOfPattern | local | D1541 | lookup 1 | The pattern ended: the entry's name must end there too (16 characters or a shifted space). |
| 37 | CP40 | $C535 | Directory::MatchEntry::Matched | local | D1541 | lookup 2 | A match: ENTFND, PATFLG, ENTIND and ENTSEC for it. |
| 38 | CP42 | $C55C | Directory::MatchEntry::StoreType | local | D1541 | lookup 1 | PATTYP = the entry's type with its locked bit, bit 5 set for a file not closed, the name's pattern bit kept; then the drive, the first track and sector, and the record size if REC has none. |
| 39 | CMPCHK | $C589 | Directory::NextUnfound | routine | D1541 | lookup 1 | CMPCHK: FOUND = 0 with F2PTR the next name, from the last, that is a pattern or not yet found; FOUND = $FF when there is none. MatchEntry falls into it (CP50, its second name here, is MatchEntry's branch to it). |
| 40 | CP50 | $C589 | Directory::NextUnfound | routine | D1541 | lookup 1 | CP50: MatchEntry's label on NextUnfound's first instruction, where it falls in; one name, with CP50 in Also:. |
| 41 | CC10 | $C594 | Directory::NextUnfound::Continue | entry | D1541 | lookup 2 | From the name before F2PTR (MatchEntry enters here for its next name). |
| 42 | CC15 | $C59A | Directory::NextUnfound::Check | local | D1541 | lookup 1 | A pattern always counts as not found; a name with a track is found. |
| 43 | CC20 | $C5A6 | Directory::NextUnfound::NotFound | local | D1541 | lookup 1 | FOUND = 0. |
| 44 | SRCHST | $C5AC | Directory::Search | routine | D1541 | lookup 2, addfil 1, verdir 1 | SRCHST: starts a search at the directory's first block (track DIRTRK, sector 1) through the internal read channel, and returns the first entry: one in use (Z clear, INDEX and DIRSEC set), or with DELIND set the first deleted one; Z set at the end. DELSEC = the first deleted entry's sector. |
| 45 | SR10 | $C5C4 | Directory::Search::NextBlock | local | D1541 | lookup 1 | Z set (the end) when the last block (LSTBUF 0) is used up. |
| 46 | SR15 | $C5CA | Directory::Search::ReadBlock | local | D1541 | lookup 1 | Eight entries; LSTBUF = the block's link track. |
| 47 | SR20 | $C5D7 | Directory::Search::NextEntry | local | D1541 | lookup 1 | The entry at the pointer: type 0 is a deleted one, noted in DELSEC the first time; returned if DELIND asks for deleted entries. |
| 48 | SR30 | $C5FB | Directory::Search::InUse | local | D1541 | lookup 1 | An entry in use: returned, unless DELIND = 1 asks only for deleted ones. |
| 49 | SRRE | $C604 | Directory::Search::Again | entry | D1541 | lookup 1, verdir 1 | SRRE: reads the sector of the entry last returned (DIRSEC) again, and goes on from it (INDEX); Validate and FindFile enter here. |
| 50 | SEARCH | $C617 | Directory::Search::Next | entry | D1541 | lookup 6, addfil 1 | SEARCH: the entry after the last returned, ENTFND cleared (FindAll, FindFile and AddEntry enter here). |
| 51 | SR40 | $C629 | Directory::Search::EndOfBlock | local | D1541 | lookup 1 | The block's eighth entry was the last: the next block (Files::FollowLink). |
| 52 | SR50 | $C62F | Directory::Search::Found | local | D1541 | lookup 1 | INDEX and DIRSEC = the entry's place; Z clear. |
| 53 | AUTOI | $C63D | Bam::AutoInitialize | routine | D1541 | lookup 4, block 1 | AUTOI: unless AutoInitializeOff (AUTOFG) turns it off, a drive whose disk has changed (WPSW bit 0) is initialized, or marked in NODRV when the seek finds no disk (job results 2, 3 and $0F: no header, no sync, not ready; the listing's comments swap the first two). A = NODRV, Z set when the drive has a disk. |
| 54 | AUTO1 | $C65F | Bam::AutoInitialize::SetNoDrive | local | D1541 | lookup 3 | NODRV = Y; a drive with a disk is initialized. |
| 55 | AUTO2 | $C669 | Bam::AutoInitialize::Done | local | D1541 | lookup 3 | A = NODRV for DRVNUM. |
| 56 | LRUINT | $CEFA | Files::ResetUseOrder | routine | D1541 | tst2 1, dskintsf 1 | LRUINT: LRUTBL, the channels in order of use, = 0-3 and the BAM's index (BLINDX). |
| 57 | LRUILP | $CEFC | Files::ResetUseOrder::Loop | local | D1541 | tst2 1 | Each entry. |
| 58 | LRUUPD | $CF09 | Files::MarkMostRecent | routine | D1541 | tst2 2 | LRUUPD: moves LINDX to LRUTBL's end, the most recently used, shifting the others down; LRUTBL is reset when LINDX is not in it. |
| 59 | LRULP1 | $CF0D | Files::MarkMostRecent::Loop | local | D1541 | tst2 1 | Each entry, from the end, until LINDX's. |
| 60 | LRUEXT | $CF1D | Files::MarkMostRecent::Done | local | D1541 | tst2 1 | Returns. |
| 61 | DBLBUF | $CF1E | Files::SwapBuffers | routine | D1541 | tst2 6, rel1 4, close 3, rel4 3, addrel 3, newss 2, record 1 | DBLBUF: makes the channel's other buffer active and waits for its job; a channel with one buffer gets a second (error 70, NO CHANNEL, if none), into which the block linked next is read first, except while writing. Relative files (part 5) use it throughout. |
| 62 | DBL05 | $CF57 | Files::SwapBuffers::ReadAhead | local | D1541 | tst2 2 | Relative, or reading: the swap, and a read of the linked block into the new active buffer. |
| 63 | DBL08 | $CF5D | Files::SwapBuffers::RestoreBlock | local | D1541 | tst2 1 | TRACK and SECTOR back. |
| 64 | DBL10 | $CF66 | Files::SwapBuffers::LastBlock | local | D1541 | tst2 1 | No link: TRACK and SECTOR back, and the swap alone. |
| 65 | DBL15 | $CF6C | Files::SwapBuffers::Swap | local | D1541 | tst2 1 | Swaps the two. |
| 66 | DBL20 | $CF6F | Files::SwapBuffers::Wait | local | D1541 | tst2 1 | Waits for the active buffer's job. |
| 67 | DBL30 | $CF76 | Files::SwapBuffers::NoBuffers | entry | D1541 | tst2 2 | Error 70, NO CHANNEL (AddSecondBuffer comes here too). |
| 68 | DBSET | $CF7B | Files::AddSecondBuffer | routine | D1541 | addrel 1 | DBSET: as SwapBuffers without the swap: the channel is marked used and gets an inactive buffer if it has none (addrel, part 5, calls it). |
| 69 | DBS10 | $CF8B | Files::AddSecondBuffer::Done | local | D1541 | tst2 1 | Returns. |
| 70 | TGLBUF | $CF8C | Files::FlipBuffers | routine | D1541 | tst2 3 | TGLBUF: flips bit 7 of BUF0 and BUF1 for LINDX, so the inactive buffer becomes the active one. |
| 71 | PIBYTE | $CF9B | Files::AcceptInternalByte | routine | D1541 | rename 2 | PIBYTE: AcceptByte for the internal write channel (SA 18), its LED on; a relative file's overflow flag is cleared first (the copy command uses it). |
| 72 | PBYTE | $CFAF | Files::AcceptInternalByte::ToChannel | local | D1541 | tst2 1 | On to AcceptByte's command or file path, by SA. |
| 73 | PUT | $CFB7 | Files::AcceptByte | routine | D1541 | serlistn 1 | PUT: takes DATA, the byte the bus received, for channel ORGSA: secondary address 15's go into the command buffer (CMDWAT set at the last, EOIFLG 0), others into the file: sequential, relative (WRTREL) or direct. |
| 74 | L40 | $CFBF | Files::AcceptByte::ToFile | entry | D1541 | tst2 1 | A file's byte, by type (AcceptInternalByte enters here). |
| 75 | L41 | $CFC9 | Files::AcceptByte::NotSequential | local | D1541 | tst2 1 | Relative: WRTREL. |
| 76 | L46 | $CFCE | Files::AcceptByte::Direct | local | D1541 | tst2 1 | Direct: stored, and the next byte made ready (NextByte::RandomAtPointer). |
| 77 | L42 | $CFD8 | Files::AcceptByte::ToCommand | entry | D1541 | tst2 2 | Into the command buffer, unless it is full (AcceptInternalByte enters here). |
| 78 | L50 | $CFE8 | Files::AcceptByte::CheckEnd | local | D1541 | tst2 1 | EOIFLG not yet 0: more to come. |
| 79 | L45 | $CFED | Files::AcceptByte::CommandReady | local | D1541 | tst2 1 | The last byte: CMDWAT up, a command to run. |
| 80 | PUTBYT | $CFF1 | Files::PutByte | routine | D1541 | lstdir 18, tst2 5, tst4 5, addfil 3, close 3, block 1 | PUTBYT: A into the active buffer at its pointer, which moves on; Z set when that filled the buffer. Error 61, FILE NOT OPEN, with no active buffer. |
| 81 | PUTB1 | $CFFD | Files::PutByte::IntoBuffer | entry | D1541 | tst2 1, opnchnl 1 | Stores the byte on the stack into buffer A (PutSideSectorByte enters here for the side sector's buffer). |
| 82 | INTDRV | $D005 | Commands::Initialize | routine | D1541 | romtblsf 2 | The I command (the command table's entry): parses the drive and initializes it. |
| 83 | ID20 | $D00B | DROP | local | D1541 | none | Not referenced; no document names it. |
| 84 | ITRIAL | $D00E | Bam::SeekHeader | routine | D1541 | lookup 1, tst2 1 | ITRIAL: gives the BAM its buffer if it has none (error 70, NO CHANNEL), and runs a seek job to the directory track, which reads a header's disk ID into HEADER; A = the job's result. |
| 85 | IT20 | $D024 | Bam::SeekHeader::Buffered | local | D1541 | tst2 1 | The buffer, marked inactive, as the BAM's. |
| 86 | IT30 | $D02C | Bam::SeekHeader::Seek | local | D1541 | tst2 1 | JOBNUM = it, the job's header 18/0, and the seek. |
| 87 | INITDR | $D042 | Bam::InitializeDrive | routine | D1541 | lookup 1, tst2 1, open 1, erproc 1, verdir 1, new 1 | INITDR: forgets the BAM images and closes the drive's channels, seeks, then keeps the disk's ID (DSKID), reads the BAM (18/0) and its DOS version (DSKVER), clears WPSW and NODRV, and falls into CountFreeBlocks. |
| 88 | NFCALC | $D075 | Bam::CountFreeBlocks | routine | D1541 | map 1 | NFCALC: NDBL/NDBH = the free blocks in the BAM, the directory track's left out (BuildEmpty jumps here). |
| 89 | NUMF1 | $D07D | Bam::CountFreeBlocks::Add | local | D1541 | tst2 1 | Each track's count. |
| 90 | NUMF2 | $D083 | Bam::CountFreeBlocks::NextTrack | local | D1541 | tst2 2 | Four bytes on; track 18's entry ($48) skipped. |
| 91 | STRRD | $D09B | Files::StartRead | routine | D1541 | tst2 1, opnchnl 1 | STRRD: reads the block at TRACK and SECTOR into the active buffer and waits; TRACK and SECTOR = its link. |
| 92 | STRDBL | $D0AF | Files::StartDoubleRead | routine | D1541 | record 1 | STRDBL: StartRead, then, when the file goes on, a read of its next block into a second buffer (record, part 5, calls it). |
| 93 | STR1 | $D0B7 | Files::StartDoubleRead::ReadNext | local | D1541 | tst2 1 | The second buffer, and the read started in it. |
| 94 | RDBUF | $D0C3 | Files::ReadFileBlock | routine | D1541 | tst2 3 | RDBUF: starts a read job on the active buffer; its header (track and sector) is already set by the caller, unlike Files::ReadBlock (RDAB, part 5), which sets it. The buffer pointer is zeroed; X = the buffer on return. |
| 95 | WRTBUF | $D0C7 | Files::WriteFileBlock | routine | D1541 | tst2 1, tst4 1, close 1 | WRTBUF: starts a write job on the active buffer; its header is already set by the caller, unlike Files::WriteBlock (WRTAB, part 5). The buffer pointer is zeroed and, for types below relative, the channel's block count (NBKL/NBKH) goes up; X = the buffer on return. |
| 96 | STRTIT | $D0C9 | Files::WriteFileBlock::Start | entry | D1541 | tst2 1 | CMD = A, the job started (SETLJB), the pointer 0; for types below relative the channel's block count (NBKL/NBKH) goes up. X = the buffer (ReadFileBlock enters here). |
| 97 | WRTC1 | $D0E8 | Files::WriteFileBlock::Done | local | D1541 | tst2 2 | X = the buffer. |
| 98 | FNDRCH | $D0EB | Files::FindReadChannel | routine | D1541 | trnsfr 1, rename 1, memrw 1, block 1, tst4 1, open 1, tsutil 1, record 1, erproc 1, sertalk 1 | FNDRCH: LINDX and X = the read channel of SA (SA 15's is the error channel's); carry set when it has none. |
| 99 | FNDC20 | $D0F3 | Files::FindReadChannel::InRange | local | D1541 | tst2 1 | SA 15 reads the error channel (SA 16). |
| 100 | FNDC25 | $D0F9 | Files::FindReadChannel::Lookup | local | D1541 | tst2 1 | LINTAB's entry: bit 7 clear for a read channel. |
| 101 | FNDC30 | $D106 | Files::FindReadChannel::Done | local | D1541 | tst2 1 | Returns. |
| 102 | FNDWCH | $D107 | Files::FindWriteChannel | routine | D1541 | close 2, rename 1, tst2 1, erproc 1, serlistn 1 | FNDWCH: LINDX and X = the write channel of SA (LINTAB bit 7, or bit 6 for a relative file's); carry set when it has none. |
| 103 | FNDW13 | $D10F | Files::FindWriteChannel::Lookup | local | D1541 | tst2 1 | LINTAB's entry, by its two top bits. |
| 104 | FNDW10 | $D119 | Files::FindWriteChannel::Found | local | D1541 | tst2 1 | LINDX = it; carry clear. |
| 105 | FNDW15 | $D121 | Files::FindWriteChannel::ReadOnly | local | D1541 | tst2 1 | Bit 7 clear: a write channel only if bit 6 is set. |
| 106 | FNDW20 | $D123 | Files::FindWriteChannel::None | local | D1541 | tst2 1 | Carry set. |
| 107 | TYPFIL | $D125 | Files::ChannelType | routine | D1541 | rename 5, tst2 4, tst4 3, close 2, record 1, erproc 1 | TYPFIL: A = the channel's file type (FILTYP's bits 1-3), compared with the relative type: Z set for relative, carry set for relative or above. |
| 108 | GETPRE | $D12F | Files::BufferIndexes | routine | D1541 | rel3 3, block 2, tst2 1, tst4 1, rel1 1 | GETPRE: X = the active buffer's BUFTAB index, Y = LINDX (the relative files' routines use it). |
| 109 | GETBYT | $D137 | Files::GetByte | routine | D1541 | tst2 6, tsutil 2, verdir 2, tst4 1, open 1, lstdir 1 | GETBYT: A = the active buffer's next byte; Z set when it was the buffer's last, or, in the file's last block, the byte at LSTCHR (the pointer then goes to 0). |
| 110 | GETB2 | $D14D | Files::GetByte::Next | local | D1541 | tst2 1 | Pointer on. |
| 111 | GETB1 | $D151 | Files::GetByte::NotLastBlock | local | D1541 | tst2 1 | No LSTCHR: Z set when the pointer wraps. |
| 112 | RDBYT | $D156 | Files::ReadByte | routine | D1541 | scrtch 2, tst4 2, opnchnl 1 | RDBYT: A and DATA = the file's next byte; at a buffer's end the next block is made active and the one after it started; with the file's last byte CHNRDY gets EOI. |
| 113 | RD0 | $D15D | DROP | local | D1541 | none | Not referenced; no document names it. |
| 114 | RD01 | $D164 | DROP | local | D1541 | none | Not referenced; no document names it. |
| 115 | RD1 | $D16A | Files::ReadByte::NextBlock | local | D1541 | tst2 1 | The other buffer: its link, and a read of the block after into this one. |
| 116 | RD3 | $D191 | Files::ReadByte::Done | local | D1541 | tst2 1 | Returns. |
| 117 | RD4 | $D192 | Files::ReadByte::LastBlock | local | D1541 | tst2 1 | Link track 0: LSTCHR = the last byte's place. |
| 118 | WRTBYT | $D19D | Files::WriteByte | routine | D1541 | tst2 1 | WRTBYT: A into the file; when the buffer is full it goes out (NextBlock). |
| 119 | WRT0 | $D1A3 | Files::WriteByte::NextBlock | entry | D1541 | tst2 1, open 1 | Allocates the next block, links the full buffer to it and starts its write, and swaps to the other buffer, its pointer 2 (Append enters here). |
| 120 | INCPNT | $D1C6 | Files::AdvancePointer | routine | D1541 | none | INCPNT: the second name at AdvancePointer's address; in its Also:. |
| 121 | INCPTR | $D1C6 | Files::AdvancePointer | routine | D1541 | lookup 1 | INCPTR: moves the active buffer's pointer, and DIRBUF, on by A. |
| 122 | SETDRN | $D1D3 | Files::SetDriveFromBuffer | routine | D1541 | tst2 3, rename 2, rel1 1, addrel 1 | SETDRN: DRVNUM = the drive of the active buffer's last job (LSTJOB). |
| 123 | GETWCH | $D1DF | Files::GetWriteChannel | routine | D1541 | opnchnl 1 | GETWCH: GetReadChannel for a write channel (carry set). |
| 124 | GETRCH | $D1E2 | Files::GetReadChannel | routine | D1541 | block 2, opnchnl 1, lstdir 1 | GETRCH: frees SA's channel, gives SA a new one (LINDX, LINTAB; bit 7 for writing) and A buffers (BUF0, BUF1); SS cleared. Error 70, NO CHANNEL, the buffers released, when they run out. |
| 125 | GETR2 | $D1E3 | Files::GetReadChannel::Allocate | entry | D1541 | tst3 1 | Carry set for a write channel (GetWriteChannel enters here). |
| 126 | GETR52 | $D1F3 | DROP | local | D1541 | none | Not referenced; no document names it. |
| 127 | GETR55 | $D1F5 | Files::GetReadChannel::SetEntry | local | D1541 | tst3 1 | LINTAB for SA = the channel. |
| 128 | GETBF | $D1F8 | DROP | local | D1541 | none | Not referenced; no document names it. |
| 129 | GETR3 | $D206 | DROP | local | D1541 | none | Not referenced; no document names it. |
| 130 | GBERR | $D20F | Files::GetReadChannel::NoBuffer | entry | D1541 | opnchnl 2, tst3 1 | Releases the buffers and gives error 70, NO CHANNEL (OpenReadChannel and OpenWriteChannel come here without a side-sector buffer). |
| 131 | GETR5 | $D217 | Files::GetReadChannel::Second | local | D1541 | tst3 1 | BUF0 = the first; the second if wanted. |
| 132 | GETR4 | $D226 | Files::GetReadChannel::Done | local | D1541 | tst3 2 | Returns. |
| 133 | FRECHN | $D227 | Files::FreeChannel | routine | D1541 | tst3 3, close 3, tst4 2, scrtch 1, erproc 1, verdir 1 | FRECHN: frees SA's channel, unless SA is 15: LINTAB cleared, CHNRDY 0, its buffers released and its index free in LINUSE. |
| 134 | FRECO | $D22E | Files::FreeChannel::Free | local | D1541 | tst3 1 | FRECO: the channel's release; FRERD and FREWRT are its other names here, in Also:. |
| 135 | FRERD | $D22E | Files::FreeChannel::Free | local | D1541 | none | FRERD: a second name at Free's address; in its Also:. |
| 136 | FREWRT | $D22E | Files::FreeChannel::Free | local | D1541 | none | FREWRT: a third name at Free's address; in its Also:. |
| 137 | RELINX | $D249 | DROP | local | D1541 | none | Not referenced; no document names it. |
| 138 | REL15 | $D24D | Files::FreeChannel::Shift | local | D1541 | tst3 1 | The channel's bit in LINUSE. |
| 139 | REL10 | $D253 | Files::FreeChannel::SetFree | local | D1541 | tst3 1 | Set: free. |
| 140 | FRE25 | $D259 | Files::FreeChannel::Done | local | D1541 | tst3 1 | Returns. |
| 141 | RELBUF | $D25A | Files::ReleaseBuffers | routine | D1541 | tst3 2 | RELBUF: frees the channel's buffers, BUF0, BUF1 and SS, each slot cleared. |
| 142 | REL1 | $D26B | Files::ReleaseBuffers::Second | local | D1541 | tst3 1 | BUF1. |
| 143 | REL2 | $D27C | Files::ReleaseBuffers::SideSector | local | D1541 | tst3 1 | SS. |
| 144 | REL3 | $D28D | Files::ReleaseBuffers::Done | local | D1541 | tst3 1 | Returns. |
| 145 | GETBUF | $D28E | Files::GetBuffer | routine | D1541 | tst2 3, tst3 2, opnchnl 2, frets 1 | GETBUF: a free buffer (from the second byte of BUFUSE, then the first, else stolen); once its job is done, JOBS and LSTJOB = DRVNUM and its pointer 2. A and X = it, N set (A = $FF) if none; Y kept. |
| 146 | GBF1 | $D2A3 | Files::GetBuffer::Found | local | D1541 | tst3 3 | Waits for its job, then sets it up. |
| 147 | GBF2 | $D2B6 | Files::GetBuffer::Done | local | D1541 | tst3 1 | Y back; A = X. |
| 148 | FNDBUF | $D2BA | Files::FindFreeBuffer | routine | D1541 | tst3 2 | FNDBUF: the first free buffer in BUFUSE's byte Y, marked used; X = it (8 more for byte 1), or minus. |
| 149 | FB1 | $D2BC | Files::FindFreeBuffer::Loop | local | D1541 | tst3 1 | Each bit, from 7. |
| 150 | FB2 | $D2C8 | Files::FindFreeBuffer::Found | local | D1541 | tst3 1 | The bit set. |
| 151 | FB3 | $D2D8 | Files::FindFreeBuffer::SetX | local | D1541 | tst3 1 | X = it. |
| 152 | FRI20 | $D2D9 | Files::FindFreeBuffer::Return | entry | D1541 | tst3 2 | Returns (FreeInactiveBuffer ends here when there is nothing to free). |
| 153 | FREIAC | $D2DA | Files::FreeInactiveBuffer | routine | D1541 | record 2 | FREIAC: frees the channel's inactive buffer, if it has one (record, part 5, calls it); falls into FreeBuffer. |
| 154 | FRI10 | $D2E9 | Files::FreeInactiveBuffer::Found | local | D1541 | tst3 1 | A buffer, if not empty: its slot cleared. |
| 155 | FREBUF | $D2F3 | Files::FreeBuffer | routine | D1541 | tst3 3 | FREBUF: marks buffer A free in BUFUSE. |
| 156 | FREB1 | $D2F9 | Files::FreeBuffer::Loop | local | D1541 | tst3 1 | Rotates BUFUSE's 16 bits once round, the buffer's bit cleared on the way. |
| 157 | FREB2 | $D303 | Files::FreeBuffer::Next | local | D1541 | tst3 1 | The count. |
| 158 | CLRCHN | $D307 | Files::FreeAllChannels | routine | D1541 | new 1 | CLRCHN: frees the channels of secondary addresses 14 down to 1 (the new command calls it). |
| 159 | CLRC1 | $D30B | Files::FreeAllChannels::Loop | local | D1541 | tst3 1 | Each one. |
| 160 | CLDCHN | $D313 | Files::FreeDriveChannels | routine | D1541 | idlesf 2, tst2 1 | CLDCHN: frees each channel, SA 14 down to 0, whose active buffer's last job was for DRVNUM. |
| 161 | CLSD | $D317 | Files::FreeDriveChannels::Next | local | D1541 | tst3 1 | Each secondary address. |
| 162 | CLD2 | $D334 | Files::FreeDriveChannels::Skip | local | D1541 | tst3 2 | The next. |
| 163 | STLBUF | $D339 | Files::StealBuffer | routine | D1541 | tst3 1 | STLBUF: takes an inactive buffer, from the least recently used channel on (LRUTBL), whose job finished without error, clearing its slot. A = it, minus if none. |
| 164 | STL05 | $D33E | Files::StealBuffer::EachChannel | local | D1541 | tst3 1 | Each channel's BUF0. |
| 165 | STL10 | $D348 | Files::StealBuffer::OtherSlot | local | D1541 | tst3 2 | Its BUF1. |
| 166 | STL20 | $D355 | Files::StealBuffer::NextChannel | local | D1541 | tst3 2 | The next in LRUTBL. |
| 167 | STL30 | $D35E | Files::StealBuffer::Inactive | local | D1541 | tst3 2 | An inactive buffer: T0 = its slot. |
| 168 | STL40 | $D363 | Files::StealBuffer::WaitJob | local | D1541 | tst3 1 | Its job done; one with an error is passed over. |
| 169 | STL50 | $D373 | Files::StealBuffer::Take | local | D1541 | tst3 1 | Its slot cleared. |
| 170 | STL60 | $D37A | Files::StealBuffer::Done | local | D1541 | tst3 1 | T0 back; A = the buffer. |
| 171 | FNDLNX | $D37F | Files::AllocateChannel | routine | D1541 | tst3 1 | FNDLNX: the first free channel index in LINUSE, marked used; A = it. Error 70, NO CHANNEL, if none. |
| 172 | FND10 | $D383 | Files::AllocateChannel::Loop | local | D1541 | tst3 1 | Each bit. |
| 173 | FND30 | $D391 | Files::AllocateChannel::Found | local | D1541 | tst3 1 | Marked used. |
| 174 | GBYTE | $D39B | Files::ReadChannelByte | routine | D1541 | rename 1 | GBYTE: the next byte of SA's read channel, its LED on; A = it (the copy command uses it). |
| 175 | GET | $D3AA | Files::NextByte | routine | D1541 | tst4 1, sertalk 1 | GET: puts channel LINDX's next byte in CHNDAT and sets CHNRDY, for the bus to send: from a relative record (RDREL), the error channel, the directory listing, a file or a direct buffer. After the last byte only a direct channel goes on. |
| 176 | GET00 | $D3B4 | Files::NextByte::NotRelative | local | D1541 | tst4 1 | Not relative: SA 15 is the error channel. |
| 177 | GET0 | $D3CE | Files::NextByte::NotReady | local | D1541 | tst4 1 | The last byte went with EOI: CHNRDY = not ready. |
| 178 | GET1 | $D3D3 | Files::NextByte::More | local | D1541 | tst4 1 | Not after EOI: SA 0, a load, is the listing or the file; others by type. |
| 179 | GET2 | $D3D7 | DROP | local | D1541 | none | Not referenced; no document names it. |
| 180 | RNDGET | $D3DE | Files::NextByte::RandomByte | local | D1541 | tst4 1 | A direct or user channel's next byte; after the last the pointer wraps. |
| 181 | RNGET1 | $D3EC | Files::NextByte::NextRandom | entry | D1541 | block 1, tst4 1 | The pointer on, then the byte (the block commands enter here). |
| 182 | RNGET2 | $D3EE | Files::NextByte::RandomAtPointer | entry | D1541 | block 2, tst2 1 | The byte at the pointer into CHNDAT, CHNRDY with EOI at LSTCHR (AcceptByte and the block commands enter here). |
| 183 | RNGET4 | $D3F0 | DROP | local | D1541 | none | Not referenced; no document names it. |
| 184 | RNGET3 | $D3FF | Files::NextByte::RandomDone | local | D1541 | tst4 1 | Returns. |
| 185 | SEQGET | $D400 | Files::NextByte::Sequential | local | D1541 | tst4 2 | ReadByte. |
| 186 | GET3 | $D403 | Files::NextByte::Store | local | D1541 | tst4 1 | CHNDAT = A. |
| 187 | GET6 | $D409 | Files::NextByte::Load | local | D1541 | tst4 1 | DIRLST set: the listing's next byte. |
| 188 | GETERC | $D414 | Files::NextByte::ErrorChannel | local | D1541 | tst4 1 | The error channel: after the message's last byte, a RETURN with EOI, and the error reset to 00, OK. |
| 189 | GE10 | $D433 | Files::NextByte::ErrorByte | local | D1541 | tst4 2 | The message's next byte. |
| 190 | GE15 | $D43A | Files::NextByte::ErrorEnd | entry | D1541 | memrw 1 | The last: the pointer back before ERRBUF, so a RETURN comes next (the memory-read command enters here). |
| 191 | GE20 | $D443 | Files::NextByte::ErrorReady | entry | D1541 | memrw 1, tst4 1 | CHNRDY = ready to talk (the memory-read command enters here). |
| 192 | GE30 | $D445 | Files::NextByte::SetError | local | D1541 | tst4 1 | The error channel's CHNRDY and CHNDAT. |
| 193 | NXTBUF | $D44D | Files::FollowLink | routine | D1541 | lookup 1, scrtch 1, verdir 1 | NXTBUF: the file's next block, when the active buffer links to one, through ReadByte; Z set when there is none. |
| 194 | NXTB1 | $D45F | Files::FollowLink::Done | local | D1541 | tst4 1 | Returns. |
| 195 | DRTRD | $D460 | Jobs::ReadTrackSector | routine | D1541 | block 1, addfil 1, close 1, new 1 | DRTRD: reads TRACK and SECTOR into buffer JOBNUM and waits. |
| 196 | DRTWRT | $D464 | Jobs::WriteTrackSector | routine | D1541 | block 2, open 2, addfil 1, new 1 | DRTWRT: writes buffer JOBNUM to TRACK and SECTOR and waits. |
| 197 | DRT | $D466 | Jobs::WriteTrackSector::Start | entry | D1541 | tst4 1 | The job for DRVNUM, its header set, run and waited for (DOIT2); ReadTrackSector enters here. |
| 198 | OPNIRD | $D475 | Files::OpenInternalRead | routine | D1541 | lookup 2, scrtch 1, rename 1, verdir 1 | OPNIRD: opens the internal read channel (SA 17) on TRACK and SECTOR as a sequential file, its pointer 2. |
| 199 | OPNTYP | $D477 | Files::OpenInternalRead::WithType | entry | D1541 | utlodr 1 | Of type A (the utility loader enters here). |
| 200 | OPNIWR | $D486 | Files::OpenInternalWrite | routine | D1541 | rename 1 | OPNIWR: opens the internal write channel (SA 18). |
| 201 | NXDRBK | $D48D | Directory::NewBlock | routine | D1541 | addfil 1 | NXDRBK: allocates the directory's next block (three sectors on, on track 18), links the current one to it and writes it, then clears the buffer for the new block, link 0/$FF. |
| 202 | NXDB1 | $D4BB | Directory::NewBlock::Clear | local | D1541 | tst4 1 | Zeros to the buffer's end. |
| 203 | SETPNT | $D4C8 | Files::SetPointer | routine | D1541 | tst4 4, newss 4, rename 3, tst2 3, block 2, open 2, opnchnl 2, rel1 2, lookup 1, scrtch 1, addfil 1, close 1, tsutil 1, record 1, lstdir 1, verdir 1 | SETPNT: the active buffer's pointer, and DIRBUF, = A. |
| 204 | FREICH | $D4DA | Files::FreeInternalChannels | routine | D1541 | parsex 1, close 1, erproc 1 | FREICH: frees the internal read and write channels (SA 17 and 18). |
| 205 | GETPNT | $D4E8 | Files::GetPointer | routine | D1541 | tst2 2, close 2, rel4 2, lookup 1, trnsfr 1, block 1, tst4 1, rel1 1 | GETPNT: DIRBUF = the active buffer's pointer; A = its low byte. |
| 206 | GP1 | $D4EB | Files::GetPointer::OfBuffer | entry | D1541 | ssutil 1 | The same for buffer A (ssutil, part 5, enters here). |
| 207 | SETDIR | $D4EB | Files::GetPointer::OfBuffer | entry | D1541 | none | SETDIR: a second name at OfBuffer's address; in its Also:. |
| 208 | DRDBYT | $D4F6 | Files::PeekByte | routine | D1541 | tst2 2, lookup 1, rel1 1, addrel 1 | DRDBYT: A = byte A of the active buffer, its pointer unchanged. |
| 209 | ADDFIL | $D6E4 | Directory::AddEntry | routine | D1541 | rename 1, open 1 | ADDFIL: writes the directory entry for the file being opened: in the first deleted slot, or a new block when there is none; type (a relative file's already closed), first track and sector, name, side sector and record size. The tables and the channel's DSEC/DIND get its place. |
| 210 | AF08 | $D715 | Directory::AddEntry::SameDrive | local | D1541 | addfil 1 | The last search's sector is the drive's: its first deleted slot, read in if need be. |
| 211 | AF10 | $D726 | Directory::AddEntry::SearchOn | local | D1541 | addfil 1 | No deleted slot noted: the search goes on for one. |
| 212 | AF15 | $D730 | Directory::AddEntry::NewBlock | local | D1541 | addfil 1 | None: a new block, its first slot. |
| 213 | AF20 | $D73D | Directory::AddEntry::WriteEntry | local | D1541 | addfil 4 | The entry at DELIND. |
| 214 | AF25 | $D74D | Directory::AddEntry::StoreType | local | D1541 | addfil 1 | The type. |
| 215 | AF30 | $D76F | Directory::AddEntry::ClearRest | local | D1541 | addfil 1 | Bytes 16-26 cleared. |
| 216 | AF50 | $D790 | Directory::AddEntry::WriteBlock | local | D1541 | addfil 1 | The sector written; the variables back. |
| 217 | OPEN | $D7B4 | Files::Open | routine | D1541 | parsex 1 | OPEN, for a secondary address other than 15: parses the name sent, finds it in the directory, and opens a channel for it by mode and type: "*" loads the last program, "$" the directory, "#" a direct channel; else read, write, replace (@), append or modify. |
| 218 | OP02 | $D7CF | DROP | local | D1541 | none | Not referenced; no document names it. |
| 219 | ENDRD | $D7EB | Files::Open::SetType | local | D1541 | open 1 | FILTYP = A; the command ends. (The store indexes with Y, which the read leaves as the channel; the code loads X.) |
| 220 | OP021 | $D7F3 | Files::Open::NotLastProgram | local | D1541 | open 2 | "$": the directory. |
| 221 | OP04 | $D7FF | Files::Open::DirectoryAsFile | local | D1541 | open 1 | Not SA 0: the directory as a sequential file. |
| 222 | OP041 | $D815 | Files::Open::NotDirectory | local | D1541 | open 1 | "#": a direct channel (the block command's). |
| 223 | OP0415 | $D81C | Files::Open::NoLastProgram | local | D1541 | open 1 | No program loaded yet: drive 0 initialized, and its first program. |
| 224 | OP042 | $D82B | Files::Open::ParseName | local | D1541 | open 1 | The name, after a colon if there is one. |
| 225 | OP049 | $D834 | Files::Open::HasColon | local | D1541 | open 1 | More than a drive before it is error 30, SYNTAX ERROR. |
| 226 | OP05 | $D837 | DROP | local | D1541 | none | Not referenced; no document names it. |
| 227 | OP10 | $D83C | Files::Open::BeforeColon | local | D1541 | open 1 | Back to the drive number, if any. |
| 228 | OP20 | $D840 | Files::Open::SetName | local | D1541 | open 2 | FILTBL; the name parsed and looked up; then the type and mode, if given. |
| 229 | OP40 | $D876 | Files::Open::SetMode | local | D1541 | open 4 | SA back; SA 0 or 1, a load or save, is read or write mode, program type. |
| 230 | OP45 | $D891 | Files::Open::DefaultType | local | D1541 | open 1 | The type given, else the file's, else sequential. |
| 231 | OP50 | $D8A7 | Files::Open::ByMode | local | D1541 | open 3 | Write mode, or read. |
| 232 | OP60 | $D8B1 | Files::Open::SetRecordSize | local | D1541 | open 1 | A relative file: REC; one not there is opened for writing. |
| 233 | OP75 | $D8C6 | Files::Open::ForWrite | local | D1541 | open 1 | A pattern or an existing file needs @; a file not closed has its entry deleted first. |
| 234 | OP77 | $D8CD | DROP | local | D1541 | none | Not referenced; no document names it. |
| 235 | OP80 | $D8D9 | Files::Open::CheckExists | local | D1541 | open 1 | A closed entry: there, it needs @; not there, it is written. |
| 236 | OP81 | $D8E1 | Files::Open::Exists | local | D1541 | open 2 | There: error 63, FILE EXISTS, unless @; for a pattern, error 33. |
| 237 | OP815 | $D8F0 | Files::Open::PatternName | local | D1541 | open 1 | Error 33, SYNTAX ERROR (a pattern). |
| 238 | OP82 | $D8F5 | Files::Open::Replace | local | D1541 | open 1 | @: same type, not relative; a write channel, and the old entry marked for replace, with the new chain's start in bytes 26-27. |
| 239 | OP90 | $D940 | Files::Open::ForRead | local | D1541 | open 1 | Reading: error 62, FILE NOT FOUND, if not there. |
| 240 | OP95 | $D945 | DROP | local | D1541 | none | Not referenced; no document names it. |
| 241 | OP100 | $D94A | Files::Open::Found | local | D1541 | open 1 | Unless modifying, a file not closed is error 60, WRITE FILE OPEN. |
| 242 | OP110 | $D95C | Files::Open::CheckType | local | D1541 | open 2 | Its type must be the one asked. |
| 243 | OP115 | $D965 | Files::Open::TypeMismatch | local | D1541 | open 3 | Error 64, FILE TYPE MISMATCH. |
| 244 | OP120 | $D96A | Files::Open::TypeMatches | local | D1541 | open 1 | Append (not relative): the entry marked not closed, and written. |
| 245 | OP125 | $D990 | Files::Open::ReadIt | local | D1541 | open 1 | OpenRead; append goes on to Append. |
| 246 | OPREAD | $D9A0 | Files::OpenRead | routine | D1541 | rename 1, open 1 | OPREAD: opens a read channel on the file found (F2PTR's entry): side sector and record size from the entry (error 50, RECORD NOT PRESENT, if REC differs), and DSEC/DIND its place. |
| 247 | OP130 | $D9C3 | Files::OpenRead::OpenChannel | local | D1541 | open 2 | The channel on its first block. |
| 248 | OPWRIT | $D9E3 | Files::OpenWrite | routine | D1541 | open 2 | OPWRIT: opens a write channel on the drive of the name and adds its directory entry; falls into Finish. |
| 249 | OPFIN | $D9EF | Files::OpenWrite::Finish | entry | D1541 | open 2 | A load or save keeps the file's start (PRGTRK, PRGSEC, PRGDRV) for "*"; the command ends (Open enters here). |
| 250 | OPF1 | $DA06 | Files::OpenWrite::Done | local | D1541 | open 1 | On to ENDSAV. |
| 251 | CKTM | $DA09 | Files::ParseTypeAndMode | routine | D1541 | open 2 | CKTM: the parameter at FILTBL,X sets MODE (MODLST: R W A M) and TYPE (TPLST: D S P U L), if it is one. |
| 252 | CKM1 | $DA11 | Files::ParseTypeAndMode::Mode | local | D1541 | open 1 | Each mode letter. |
| 253 | CKM2 | $DA1C | Files::ParseTypeAndMode::NoMode | local | D1541 | open 1 | Then the types. |
| 254 | CKT1 | $DA1E | Files::ParseTypeAndMode::Type | local | D1541 | open 1 | Each type letter. |
| 255 | CKT2 | $DA29 | Files::ParseTypeAndMode::Done | local | D1541 | open 1 | Returns. |
| 256 | APPEND | $DA2A | Files::Append | routine | D1541 | open 2, rename 1 | APPEND: reads to the file's last block, then makes the channel a write channel at its end, a new block when the last is full. |
| 257 | AP30 | $DA42 | Files::Append::SetEnd | local | D1541 | open 1 | The pointer; CHNRDY ready to listen, LINTAB marked for writing. |
| 258 | LOADIR | $DA55 | Files::LoadDirectory | routine | D1541 | open 1 | LOADIR: Open's "$" with SA 0: parses the pattern ("$", "$0", "$:name") and starts the listing (StartListing), its first byte ready. |
| 259 | LD01 | $DA62 | DROP | local | D1541 | none | Not referenced; no document names it. |
| 260 | LD02 | $DA6D | Files::LoadDirectory::AllFiles | local | D1541 | open 1 | No name: the pattern "*". |
| 261 | LD03 | $DA86 | Files::LoadDirectory::ByName | local | D1541 | open 2 | A name, after a colon or not. |
| 262 | LD05 | $DA90 | Files::LoadDirectory::SetName | local | D1541 | open 1 | FILTBL; the name parsed, on both drives. |
| 263 | LD10 | $DA9E | Files::LoadDirectory::Search | local | D1541 | open 1 | The drives, the header, the first match, the listing. |
| 264 | LD20 | $DAA7 | DROP | local | D1541 | none | Not referenced; no document names it. |
| 265 | CLOSE | $DAC0 | Files::Close | routine | D1541 | seratn 1 | CLOSE: closes SA's channel: SA 0 the listing (and the internal channels), SA 15 every channel; after SA 2-15 the command status is reported (ENDCMD, or the last error). |
| 266 | CLS05 | $DAD1 | Files::Close::FreeInternal | local | D1541 | close 1 | The internal channels. |
| 267 | CLS10 | $DAD4 | Files::Close::NotLoad | local | D1541 | close 1 | Not SA 0: SA 15 closes every channel; others their own, SA 1 the internal ones too. |
| 268 | CLS15 | $DAE9 | Files::Close::Error | local | D1541 | close 1 | The last command's error. |
| 269 | CLSALL | $DAEC | Files::Close::CommandChannel | local | D1541 | close 1 | SA 15: SA 14 down to 0, each closed. |
| 270 | CLS20 | $DAF0 | Files::Close::Next | local | D1541 | close 1 | The next. |
| 271 | CLS25 | $DAFF | Files::Close::AllError | local | D1541 | close 1 | The last command's error. |
| 272 | CLSCHN | $DB02 | Files::CloseChannel | routine | D1541 | close 2, rename 1 | CLSCHN: closes SA's channel by type: a direct one writes the BAM, a relative one goes to part 5's routines, a write channel writes its last block and closes its entry; then it is freed. |
| 273 | CLSC28 | $DB0C | Files::CloseChannel::Open | local | D1541 | close 1 | The channel, by type. |
| 274 | CLSC30 | $DB26 | Files::CloseChannel::WriteBam | local | D1541 | close 1 | BAM out (Bam::WriteForChannel). |
| 275 | CLSC31 | $DB29 | Files::CloseChannel::Free | local | D1541 | close 1 | FreeChannel. |
| 276 | CLSREL | $DB2C | Files::CloseChannel::RelativeFile | local | D1541 | close 1 | A relative file (shared with part 5): its record written, its last side sector found, the block count worked out; a changed file closes its entry. Named so as not to shadow Relative. |
| 277 | CLSR1 | $DB5F | Files::CloseChannel::RelativeDone | local | D1541 | close 1 | FreeChannel. |
| 278 | CLSWRT | $DB62 | Files::CloseWrite | routine | D1541 | close 1 | CLSWRT: writes a sequential file's last block: a file with nothing in it gets a RETURN; an empty buffer gives the block before it back; the link 0 and the last byte's place, written and waited for. |
| 279 | CLSW10 | $DB76 | Files::CloseWrite::NotEmpty | local | D1541 | close 2 | The buffer's pointer. |
| 280 | CLSW15 | $DB88 | Files::CloseWrite::CountDown | local | D1541 | close 1 | One block fewer. |
| 281 | CLSW20 | $DB8C | Files::CloseWrite::SetLast | local | D1541 | close 1 | The last byte's place = pointer - 1. |
| 282 | CLSDIR | $DBA5 | Directory::CloseEntry | routine | D1541 | close 2 | CLSDIR: closes a written file's directory entry (DSEC, DIND): closed bit set, block count; a replace (@) swaps in the new chain and deletes the old (error 67 if it has none). |
| 283 | CLSD4 | $DC06 | Directory::CloseEntry::Swap | local | D1541 | close 1 | The new chain's start into the entry, bytes 26-27 cleared, and the old chain deleted. |
| 284 | CLSD5 | $DC21 | Directory::CloseEntry::NotReplace | local | D1541 | close 1 | Closed bit set. |
| 285 | CLSD6 | $DC29 | Directory::CloseEntry::SetBlocks | local | D1541 | close 2 | The block count, the sector written, SA and LINDX back. |
| 286 | OPNRCH | $DC46 | Files::OpenReadChannel | routine | D1541 | open 3, tst4 1 | OPNRCH: a read channel with one buffer for TRACK and SECTOR, FILTYP from TYPE; the first block read and its first byte ready. A relative file (shared with part 5) gets read-write, its record size, its side sector read and its first record. |
| 287 | OR10 | $DC65 | Files::OpenReadChannel::NotLast | local | D1541 | opnchnl 1 | In the last block LSTCHR = the link's sector, the last byte's place. |
| 288 | OR20 | $DC81 | Files::OpenReadChannel::SideSector | local | D1541 | opnchnl 1 | SS = the buffer; side sector read. |
| 289 | OROW | $DC98 | Files::OpenReadChannel::FirstRecord | entry | D1541 | opnchnl 1 | NR = 2, the first record set up, TRACK and SECTOR back (OpenWriteChannel enters here for a new relative file). |
| 290 | OR30 | $DCA9 | Files::OpenReadChannel::Sequential | local | D1541 | opnchnl 1 | The first byte into CHNDAT, ready to talk. |
| 291 | INITP | $DCB6 | Files::ResetPointers | routine | D1541 | opnchnl 2 | INITP: both buffers' pointers 2, BUF1 inactive, NBKL/NBKH and LSTCHR 0. |
| 292 | OPNWCH | $DCDA | Files::OpenWriteChannel | routine | D1541 | open 2, tst4 1 | OPNWCH: a write channel with one buffer on the first free block, ready to listen. A relative file (shared with part 5) gets its first side sector and its first block of empty records written. |
| 293 | OW10 | $DCFD | Files::OpenWriteChannel::RelativeFile | local | D1541 | opnchnl 1 | Read-write, its record size, a side-sector buffer. |
| 294 | OW20 | $DD16 | Files::OpenWriteChannel::SideSector | local | D1541 | opnchnl 1 | The side sector: its block, its header (link, last byte, number, record size, its own place), the first data block; written; then empty records. |
| 295 | PUTSS | $DD8D | Relative::PutSideSectorByte | routine | D1541 | opnchnl 8, addrel 2 | PUTSS: A into the side sector's buffer at its pointer (through PutByte); in opnchnl, but the side sectors' (addrel, part 5, uses it). |
| 296 | SCFLG | $DD95 | Files::SetOrClearFlag | routine | D1541 | none | SCFLG: sets FILTYP's flag bits A with carry set, clears them with carry clear. Nothing calls it; kept as a routine, its comment says so. |
| 297 | SETFLG | $DD97 | Files::SetFlag | routine | D1541 | rel2 2, rename 1, rel1 1, record 1, addrel 1 | SETFLG: sets bits A in the channel's FILTYP (the relative files' flags). |
| 298 | CLRFLG | $DD9D | Files::ClearFlag | routine | D1541 | rel1 2, tst2 1, tstflg 1, rel2 1, record 1 | CLRFLG: clears bits A in the channel's FILTYP. |
| 299 | CLRF10 | $DDA3 | Files::ClearFlag::Store | entry | D1541 | tstflg 1 | FILTYP = A (SetFlag ends here). |
| 300 | TSTFLG | $DDA6 | Files::TestFlag | routine | D1541 | rel2 3, rename 1, open 1, close 1, rel1 1, rel3 1, record 1 | TSTFLG: A = the channel's FILTYP and A; Z set when the bits are clear. |
| 301 | TSTWRT | $DDAB | Files::TestWriteJob | routine | D1541 | rel1 2, tst2 1 | TSTWRT: Z set when the active buffer's last job was a write. |
| 302 | TSTCHN | $DDB7 | Files::TestEntryOpen | routine | D1541 | scrtch 1 | TSTCHN: carry clear when a channel (SA 0-15) has the entry found open: the same drive and directory place (DSEC, DIND) as ENTFND's; X = ENTFND, Y = the channel. |
| 303 | TSTC20 | $DDB9 | Files::TestEntryOpen::Next | local | D1541 | tstflg 1 | Each SA. |
| 304 | TSTC30 | $DDC2 | Files::TestEntryOpen::Skip | local | D1541 | tstflg 3 | Not it: the next. |
| 305 | TSTRTS | $DDC9 | DROP | local | D1541 | none | Not referenced; no document names it. |
| 306 | TSTC40 | $DDCA | Files::TestEntryOpen::Compare | local | D1541 | tstflg 1 | Drive, DSEC and DIND against the entry's. |
| 307 | STDIR | $EC9E | Directory::StartListing | routine | D1541 | open 1 | STDIR: the directory as a BASIC program, through a read channel with one buffer: load address $0401, the header line (drive and disk name), then lines of entries until the buffer is full; each line is 32 bytes, so a buffer holds eight. |
| 308 | DIR1 | $ECEA | Directory::StartListing::FillBuffer | entry | D1541 | lstdir 2 | The next lines, from GETNAM, until the buffer fills or the listing ends (NextListingByte enters here for the next buffer). |
| 309 | DIR10 | $ED0D | Directory::StartListing::BufferFull | local | D1541 | lstdir 1 | The pointer 0, DIRLST and CHNRDY ready to talk; A = DATA. |
| 310 | DIR3 | $ED23 | Directory::StartListing::LastLine | local | D1541 | lstdir 1 | The BLOCKS FREE line, the program's end (three zeros), LSTCHR its last byte. |
| 311 | MOVBUF | $ED59 | Directory::PutLineText | routine | D1541 | lstdir 3 | MOVBUF: NAMBUF's 27 bytes, a line's text, into the buffer. |
| 312 | MOVB1 | $ED5B | Directory::PutLineText::Loop | local | D1541 | lstdir 1 | Each byte. |
| 313 | GETDIR | $ED67 | Directory::NextListingByte | routine | D1541 | tst4 1 | GETDIR: A = the listing's next byte; at a buffer's end, EOI if it is the last, else the buffer filled again. |
| 314 | GETD3 | $ED6D | Directory::NextListingByte::BufferEnd | local | D1541 | lstdir 1 | DATA = it. |
| 315 | GD1 | $ED7E | Directory::NextListingByte::Refill | local | D1541 | lstdir 1 | The next lines, A kept. |
| 316 | VALDAT | $ED84 | Directory::Validate | routine | D1541 | none | VALDAT: a second name at Validate's address; in its Also:. |
| 317 | VERDIR | $ED84 | Directory::Validate | routine | D1541 | romtblsf 2 | VERDIR: the V command (the command table's entry): initializes the drive, builds a new BAM with every block free, marks used the directory's blocks and each closed file's (and its side sectors'), deletes entries not closed, and writes the BAM. |
| 318 | VD10 | $ED9C | Directory::Validate::Finish | local | D1541 | verdir 1 | The directory's own chain (18/0), then the BAM written. |
| 319 | VD15 | $EDB3 | Directory::Validate::ClosedFile | local | D1541 | verdir 1 | The file's start; a relative file's side sectors first. |
| 320 | VD17 | $EDCB | Directory::Validate::DataBlocks | local | D1541 | verdir 1 | The data chain. |
| 321 | VD20 | $EDD4 | Directory::Validate::NextFile | local | D1541 | verdir 1 | The next entry (Search::Again). |
| 322 | VD25 | $EDD9 | Directory::Validate::CheckEntry | local | D1541 | verdir 1 | Closed: its blocks; not closed: its entry deleted. |
| 323 | VMKBAM | $EDE5 | Directory::MarkChain | routine | D1541 | verdir 3 | VMKBAM: marks used in the BAM each block of the chain from TRACK and SECTOR, through the internal read channel. |
| 324 | MRK2 | $EDEE | Directory::MarkChain::Next | local | D1541 | verdir 1 | The block's link. |
| 325 | MRK1 | $EE04 | Directory::MarkChain::Mark | local | D1541 | verdir 1 | Marked, and on to it. |
| 326 | NEWMAP | $EEB7 | Bam::BuildEmpty | routine | D1541 | new 1 | NEWMAP: builds a new BAM in its buffer, every block free: link 18/1, each track's count and bits from SectorsOnTrack; then CountFreeBlocks. NEWMPV is its second name, in Also:. |
| 327 | NEWMPV | $EEB7 | Bam::BuildEmpty | routine | D1541 | verdir 1 | NEWMPV: a second name at BuildEmpty's address (Validate calls it by it); in its Also:. |
| 328 | NM10 | $EEC7 | Bam::BuildEmpty::NextTrack | local | D1541 | map 1 | A track's count. |
| 329 | NM20 | $EED9 | Bam::BuildEmpty::SetBits | local | D1541 | map 1 | One bit for each sector. |
| 330 | NM30 | $EEE3 | Bam::BuildEmpty::StoreBits | local | D1541 | map 1 | The three bytes. |
| 331 | MAPOUT | $EEF4 | Bam::WriteForChannel | routine | D1541 | scrtch 1, close 1, opnchnl 1, addrel 1 | MAPOUT: DRVNUM = the drive of the active buffer's last job; falls into WriteIfDirty. |
| 332 | MO10 | $EEFB | DROP | local | D1541 | none | Not referenced; no document names it. |
| 333 | SCRBAM | $EEFF | Bam::WriteIfDirty | routine | D1541 | verdir 1, new 1 | SCRBAM: when MDIRTY says DRVNUM's BAM changed, puts its track images back, checks each track's count against its bits (CheckTrackCount) and writes the BAM block. |
| 334 | SB10 | $EF07 | Bam::WriteIfDirty::Dirty | local | D1541 | map 1 | MDIRTY cleared; the images back. |
| 335 | SB20 | $EF24 | Bam::WriteIfDirty::CheckTrack | local | D1541 | map 1 | Each track's count. |
| 336 | SETBPT | $EF3A | Bam::SetPointer | routine | D1541 | tst2 1, map 1, frets 1 | SETBPT: BMPNT = the BAM's buffer, read in if need be. |
| 337 | NUMFRE | $EF4D | Bam::CopyFreeBlocks | routine | D1541 | trnsfr 1, addrel 1 | NUMFRE: NBTEMP = DRVNUM's free blocks (NDBL, NDBH), for the listing and the messages. |
| 338 | WFREE | $EF5C | Bam::FlushAndMarkFree | routine | D1541 | none | WFREE: FlushPending, then MarkFree. Nothing calls it; kept as a routine, its comment says so. |
| 339 | FRETS | $EF5F | Bam::MarkFree | routine | D1541 | scrtch 2, block 1 | FRETS: marks TRACK and SECTOR free in the BAM: its bit set, its track's count and NDBL/NDBH up; already free, carry set. A block on the directory track branches to MarkUsed's count down (USE10), which skips the borrow (NDBL = 0 leaves NDBH unchanged: the count is off by 256) and falls into CheckFull, so under 3 free blocks it can raise error 72, DISK FULL: a slip, documented, not changed. |
| 340 | FRETS2 | $EF62 | DROP | local | D1541 | none | Not referenced; no document names it. |
| 341 | FRE10 | $EF87 | Bam::MarkFree::Done | local | D1541 | frets 1 | FRE10: returns; FRERTS is its second name, in Also:. |
| 342 | FRERTS | $EF87 | Bam::MarkFree::Done | local | D1541 | frets 1 | FRERTS: a second name at Done's address; in its Also:. |
| 343 | DTYBAM | $EF88 | Bam::MarkDirty | routine | D1541 | frets 2 | DTYBAM: MDIRTY for DRVNUM set. |
| 344 | WUSED | $EF90 | Bam::FlushAndMarkUsed | routine | D1541 | verdir 2, tstfnd 2, block 1 | WUSED: FlushPending, then MarkUsed. |
| 345 | USEDTS | $EF93 | Bam::MarkUsed | routine | D1541 | new 2 | USEDTS: marks TRACK and SECTOR used in the BAM (Z set, nothing done, if it was): its bit cleared, its track's count and, off the directory track, NDBL/NDBH down; fewer than three blocks left sets error 72, DISK FULL. |
| 346 | USE10 | $EFBA | Bam::MarkUsed::CountDown | entry | D1541 | frets 2 | NDBL down (MarkFree comes here for the directory track). |
| 347 | USE20 | $EFBD | Bam::MarkUsed::CheckFull | local | D1541 | frets 1 | Fewer than three left: DISK FULL (ERRMSG). |
| 348 | USERTS | $EFCE | Bam::MarkUsed::Done | local | D1541 | frets 3 | Returns. |
| 349 | FREUSE | $EFCF | Bam::FindBit | routine | D1541 | frets 2 | FREUSE: the track's image selected; Y = the byte of SECTOR's bit, X its number, A = it: Z set when used. |
| 350 | FREUS2 | $EFD3 | DROP | local | D1541 | none | Not referenced; no document names it. |
| 351 | FREUS3 | $EFD5 | Bam::FindBit::InImage | entry | D1541 | tstfnd 1 | From the image index in TEMP (FindFreeSector enters here). |
| 352 | BMASK | $EFE9 | BitMasks | table | D1541 | frets 3, tst3 2, tstfnd 1 | 1, 2, 4 ... 128: bit X's mask; the BAM's routines and the buffer allocation (BUFUSE) use it, so top level. |
| 353 | FIXBAM | $EFF1 | Bam::FlushPending | routine | D1541 | frets 2 | FIXBAM: writes the BAM now if WBAM's bit 7 marks a write pending and bit 6 is not holding writes back; WBAM cleared. |
| 354 | FBAM10 | $F004 | Bam::FlushPending::Done | local | D1541 | frets 3 | Returns. |
| 355 | CLRBAM | $F005 | Bam::ZeroBuffer | routine | D1541 | new 2 | CLRBAM: the BAM's buffer, all 256 bytes, cleared (the new command). |
| 356 | CLB1 | $F00B | Bam::ZeroBuffer::Loop | local | D1541 | frets 1 | Each byte. |
| 357 | SETBAM | $F011 | Bam::SelectTrack | routine | D1541 | tstfnd 4, frets 1 | SETBAM: BMPNT = the image of TRACK's four BAM bytes (count and bits), swapped in from the buffer when neither of DRVNUM's images has it; UBAM notes the one used. Y = 0. Error 74, DRIVE NOT READY, for a drive with no disk. |
| 358 | SBM10 | $F022 | Bam::SelectTrack::HaveDrive | local | D1541 | frets 1 | TBAM's two entries for the drive. |
| 359 | SBM30 | $F03E | Bam::SelectTrack::InImage | local | D1541 | frets 2 | UBAM and BMPNT. |
| 360 | SWAP | $F05B | Bam::SwapIn | routine | D1541 | frets 1 | SWAP: puts the image used less recently back in the BAM buffer and copies TRACK's bytes into it (clearing them in the buffer); the BAM is written at once unless WBAM holds writes, when bit 7 marks one pending. |
| 361 | SWAP3 | $F07F | Bam::SwapIn::Copy | local | D1541 | frets 1 | Each of the four bytes. |
| 362 | SWAP4 | $F09F | Bam::SwapIn::Pending | local | D1541 | frets 1 | WBAM's bit 7. |
| 363 | PUTBAM | $F0A5 | Bam::PutImage | routine | D1541 | map 2, frets 1 | PUTBAM: image A back into the BAM buffer at its track's place, the image and its TBAM cleared; nothing for an empty one. |
| 364 | SWAP1 | $F0BE | Bam::PutImage::Copy | local | D1541 | frets 1 | Each of the four bytes. |
| 365 | SWAP2 | $F0D0 | Bam::PutImage::Done | local | D1541 | frets 1 | Returns. |
| 366 | CLNBAM | $F0D1 | Bam::ForgetImages | routine | D1541 | copset 1, tst2 1, map 1 | CLNBAM: TBAM's two entries for DRVNUM cleared: no track images. |
| 367 | REDBAM | $F0DF | Bam::ReadIfNeeded | routine | D1541 | trnsfr 1, map 1, frets 1 | REDBAM: with X the BAM's index, reads the BAM (18/0) into a buffer of its own (inactive, so it can be stolen) when it has none (error 70, NO CHANNEL); JOBNUM = its buffer. |
| 368 | RBM10 | $F0F2 | Bam::ReadIfNeeded::Got | local | D1541 | frets 1 | The buffer, as the BAM's, and the read. |
| 369 | RBM20 | $F10A | Bam::ReadIfNeeded::InMemory | local | D1541 | frets 1 | JOBNUM = its buffer. |
| 370 | BAM2A | $F10F | Bam::ChannelIndex | routine | D1541 | frets 2, tst2 1, map 1 | BAM2A: A = the BAM's index into BUF0 and BUF1 for DRVNUM: BLINDX's second slot for drive 0, its first for drive 1. |
| 371 | B2X10 | $F118 | Bam::ChannelIndex::Done | local | D1541 | frets 1 | Returns. |
| 372 | BAM2X | $F119 | Bam::ChannelIndexInX | routine | D1541 | trnsfr 1, scrtch 1, copset 1 | BAM2X: X = ChannelIndex. |
| 373 | NXTTS | $F11E | Bam::AllocateNext | routine | D1541 | addrel 2, tst2 1, opnchnl 1, newss 1 | NXTTS: allocates the free block after the active buffer's TRACK and SECTOR: on that track SECINC sectors on, else outward from track 18 on the same side, then the other side; error 72, DISK FULL, when none is left. WBAM holds the BAM's writes. Relative files (part 5) use it. |
| 374 | NXT1 | $F12D | Bam::AllocateNext::Search | entry | D1541 | tstfnd 4 | NXT1: the loop's label at Search's address; NXTDS, the entry, is its second name, in Also:. |
| 375 | NXTDS | $F12D | Bam::AllocateNext::Search | entry | D1541 | tst4 1 | NXTDS: from TRACK and SECTOR, with TEMP passes (NewBlock enters here for the directory track); in Also: with NXT1. |
| 376 | NXTERR | $F15A | Bam::AllocateNext::DiskFull | local | D1541 | tstfnd 2 | Error 72, DISK FULL. |
| 377 | NXT2 | $F15F | Bam::AllocateNext::Downward | local | D1541 | tstfnd 1 | Below track 18: down a track; past track 1, from track 19. |
| 378 | FNDNXT | $F173 | Bam::AllocateNext::NextSector | local | D1541 | tstfnd 1 | SECINC sectors on, wrapping inside the track. |
| 379 | FNDN0 | $F195 | Bam::AllocateNext::FindSector | local | D1541 | tstfnd 2 | The first free from there. |
| 380 | FNDN1 | $F19A | Bam::AllocateNext::Use | local | D1541 | tstfnd 1 | Marked used. |
| 381 | FNDN2 | $F19D | Bam::AllocateNext::FromStart | local | D1541 | tstfnd 1 | From sector 0; none means the count was wrong (error 71). |
| 382 | INTTS | $F1A9 | Bam::AllocateFirst | routine | D1541 | opnchnl 1 | INTTS: allocates a file's first block on the free track nearest the directory's, below first (17, 19, 16, 20 ...), from sector 0; error 67 past the last track. |
| 383 | ITS1 | $F1B8 | Bam::AllocateFirst::Below | local | D1541 | tstfnd 1 | Track 18 - R0. |
| 384 | ITS2 | $F1CB | Bam::AllocateFirst::Above | local | D1541 | tstfnd 2 | Track 18 + R0, R0 up. |
| 385 | ITS3 | $F1DF | Bam::AllocateFirst::CheckAbove | local | D1541 | tstfnd 1 | Free blocks there, or the next pair. |
| 386 | FNDSEC | $F1E6 | Bam::AllocateFirst::FindSector | local | D1541 | tstfnd 1 | R0 back; the first free sector, marked used. |
| 387 | DERR | $F1F5 | Bam::AllocateFirst::DirectoryError | entry | D1541 | tstfnd 1 | Error 71, DIR ERROR: the count says free but no bit is (AllocateNext comes here); FND2 is its second name, in Also:. |
| 388 | FND2 | $F1F5 | Bam::AllocateFirst::DirectoryError | entry | D1541 | tstfnd 1 | FND2: a second name at DirectoryError's address; in its Also:. |
| 389 | GETSEC | $F1FA | Bam::FindFreeSector | routine | D1541 | tstfnd 3, block 2 | GETSEC: with TRACK's count checked, the first free sector from SECTOR on: SECTOR = it, Z clear; Z set when none. |
| 390 | GS10 | $F20D | Bam::FindFreeSector::Loop | local | D1541 | tstfnd 1 | Each sector below the track's last. |
| 391 | GS20 | $F21D | Bam::FindFreeSector::None | local | D1541 | tstfnd 1 | A = 0. |
| 392 | GS30 | $F21F | Bam::FindFreeSector::Done | local | D1541 | tstfnd 1 | Returns. |
| 393 | AVCK | $F220 | Bam::CheckTrackCount | routine | D1541 | map 1, tstfnd 1 | AVCK: counts the bits set in the selected track's three bytes; error 71, DIR ERROR, when its count byte differs. |
| 394 | AC10 | $F22B | Bam::CheckTrackCount::Byte | local | D1541 | tstfnd 1 | Each byte, from the third. |
| 395 | AC20 | $F22D | Bam::CheckTrackCount::Bit | local | D1541 | tstfnd 1 | Each bit. |
| 396 | AC30 | $F236 | Bam::CheckTrackCount::NextBit | local | D1541 | tstfnd 1 | The bit count. |
| 397 | AC40 | $F246 | Bam::CheckTrackCount::Mismatch | local | D1541 | tstfnd 1 | Error 71. |
| 398 | MAXSEC | $F24B | SectorsOnTrack | routine | D1541 | jobssf 2, tstfnd 2, map 1 | MAXSEC: A = the sectors on track A, from the zones (TRKNUM, NUMSEC); Jobs check a track and sector with it and the BAM's routines size a track, so top level (not Controller::SectorCount, SECTR, the zero-page count for the job's track). |
| 399 | MAX1 | $F24E | SectorsOnTrack::Zone | local | D1541 | tstfnd 1 | Each zone's first track, from the last. |

## Part 5: the relative files and the side sectors

Settled on 2026-11-27 after an independent review of the part (D2, D7).

The listing's `fndrel`, `tsutil`, `ssutil`, `sstest`, `getact`, `rel1`-`rel4`, `ssend`, `record`, `nulbuf`,
`addrel` and `newss`, `$CE0E-$CEF0` and `$DDF1-$E4DE`: 170 names, all code. They find a record's side sector,
index and byte (`fndrel`, with its own multiply and divide), keep a channel's two buffers and their links
(`tsutil`, `getact`), move the side-sector buffer about (`ssutil`, `sstest`, `ssend`), read and write a relative
channel's bytes and records (`rel1`-`rel4`), carry out the P command (`record`), and add blocks and side sectors to a
file (`nulbuf`, `addrel`, `newss`). The variables are part 1's, by their listing names (`lindx`, `dirbuf`, `nr`,
`rs`, `ss`, `ssnum`, `ssind`, `relptr`, `recptr`, `lbused`). None of these addresses differs between the 901229
revisions.

### Questions

- D-P5-Q1. **The channel's buffer routines are `Files`', though every family calls them.** GETACT, GAFLGS,
  GETINA and PUTINA (`getact`), and `tsutil`'s CURBLK, GETHDR, WRTAB, RDAB, WRTOUT, RDLNK and SCRUB, with rel2's
  CDIRTY, work on the current channel's active and inactive buffers, the `Files` family's business; the directory,
  the commands, the BAM and the job code call them as services, as the kernal's families call `Serial::Talk`.
  They go in `Files`, not top level: top level is for the hardware, the shared variables, the tables and the
  vectors. *Recommended.* The alternative is top level for the five other families call too (GETACT, CURBLK,
  GETHDR, RDAB, WRTOUT); GAFLGS is called only by `Files` and `Relative` code (SDIRTY, CDIRTY, SCRUB, NRBUF, NEWSS),
  so it is `Files`' either way. **Settled:** all of them are `Files`', with CDIRTY as `Files::MarkClean`.
- D-P5-Q2. **The helpers only relative-file code calls are `Relative`'s**, though they read as general:
  `tsutil`'s SET00, SETLNK, GETLNK and NULLNK (their callers are `rel4`, `nulbuf`, `addrel`, `record` and
  `opnchnl`'s relative open), `ssutil`'s B0TOB0 and CLRBUF (`newss`, and `opnchnl` clearing a new side sector), and
  `nulbuf`'s NULBUF and ADDNR, which lay records out by `nr` and `rs`. SETLNK ends in SDIRTY, which sets the
  relative file's `dyfile` flag; NULLNK uses `nr`. SDIRTY is `Relative::MarkDirty`; CDIRTY, its pair, is
  `Files::MarkClean` (Q1), since only the buffer jobs' tail calls it. *Recommended.* PUTSS, the side-sector buffer's
  byte writer, is part 4's `Relative::PutSideSectorByte`, and the rows here that use it (AR60 and the rest of ADDREL)
  cite it by that name. The alternative is `Files` for SET00, CLRBUF and B0TOB0, as buffer tools. **Settled:**
  `Relative`'s, as recommended.
- D-P5-Q3. **`tsutil`'s six job starters and their tail.** WRTAB, RDAB, WRTOUT, RDIN, WRTSS and RDSS each put a
  command in `cmd` and branch (always taken, except RDSS's own, below) into a shared tail: SJ10 sets the header from
  `track` and `sector` and notes the drive in `lstjob`, SJ20 clears the dirty bit, SJ30 starts the job through
  `Jobs::StartOnLastDrive`. The tail is its own routine, `Files::StartBlockJob`, with SJ20 and SJ30 its entries
  (`ClearDirty`, `Start`); each starter is a short `.proc` ending in its branch. WRTSS and RDSS, which use the
  side-sector buffer, are `Relative`'s: RDSS falls into RDS5, which is its entry, and WRTSS branches to it; RDS5 takes
  the channel's side-sector number into X and `bpl`s to `Files::StartBlockJob::Start`. That branch (the listing's "was
  bne") is taken only for an allocated side-sector buffer (a number under $80); with `ss` = $FF (none) it falls into
  SJ10, which would set the active buffer's header, and the comment says so. *Recommended.* The alternative is one
  `.proc` holding all six as entries, which makes callers write `Files::WriteBlock::ReadBlock`. **Settled:** the tail as
  its own routine with ClearDirty and Start entries, and the starters as short routines.
- D-P5-Q4. **Dead code and the labels nothing names.** RDIN (`tsutil`) and IBWT (`ssutil`) are complete starters
  that nothing calls and that the code before them always branches past: their labels are dropped and their bytes
  kept with a comment saying nothing reaches them (RDIN would read the active buffer from its header; IBWT would
  write a side sector). The `lda #recovf / jsr cmderr` after POSITN's `jmp rd15` has no label and is kept the same
  way. GA2, RELP06, WR20, WR51, RD10 and NS20 mark code reached only by falling into it: dropped, as the kernal's
  unreferenced locals were. *Recommended.* **Settled:** as recommended.
- D-P5-Q5. **SSCALC is entered after its loop.** The code at SCAL1 (`$DF4C`) adds 120 for one side sector, and
  SSCALC, five bytes on, counts X down and branches back to it; callers enter at SSCALC. The `.proc` starts at
  SCAL1, as it must, named `Relative::CountBlocks`, with SSCALC its entry `Relative::CountBlocks::Start`, which
  callers use; the comment says the first byte is the loop's body. It falls into ADDT12, its own routine
  (`Relative::AddToCount`), which it also calls. *Recommended.* The alternative, naming the routine for the loop
  body (`AddSideSector`), makes callers' `jsr` read wrongly. **Settled:** as recommended.
- D-P5-Q6. **The skipped load.** DIV254 ends in a `BIT` opcode (`$2C`) that skips DIV120's `lda #120`: each stays
  its own `.proc` (`Relative::DivideBy254`, `Relative::DivideBy120`), with the `.byte $2C` explained and an
  `.assert` that DivideBy120 follows, as K-P3-Q4 settled TALK's. *Recommended.* **Settled:** as recommended.
- D-P5-Q7. **Two labels at one address.** R35 and R40 are both at `$E253`, in RECORD: one label,
  `Relative::PositionCommand::SetOffset`, with both names in `Also:`. *Recommended.* **Settled:** as recommended.
- D-P5-Q8. **RECORD, the P command, is `Relative`'s**, not `Commands`', as the families put `record` there: it is
  reached only through the command table in `romtblsf` (so the inventory's draft kind says local), and is a
  routine: `Relative::PositionCommand`, named for the command so as not to read as part of the record's seek
  (`Relative::SeekRecord`). *Recommended.* **Settled:** `Relative`'s, as recommended.
- D-P5-Q9. **Entries and routines the draft left open.** Entered from outside their routine, so entries: NXOUT
  (POSITN calls it inside NXTREC), RD15, RD40 and RD05 (inside RDREL), ADDR1 (rename's relative copy jumps into
  ADDREL), RDS5 (Q3). Routines a routine falls into: GETHDR (from CURBLK), ACCX2 (from ACCX4) and ACC200 (from ACCX2),
  ADDT12 (Q5), BHERE2 (from BHERE), DIV120 (Q6). BREAK, the error exit SSEND branches to and POSITN jumps to, is
  its own routine, `Relative::SideSectorError`, as the kernal's NODEV is `Serial::BusError`. NXTR35, called with
  `jsr` and fallen into inside NXTREC, and WR10, AR55 and NS50, jumped to inside their routines, are locals.
  *Recommended.* **Settled:** as recommended.
- D-P5-Q10. **Where the listing's comments are wrong**, the reasons say what the code does, and the source's
  comments will: POSBUF's `bne p10 ; yes!` branches when the block is *not* in the buffer; NXTREC's `beq nxtr45
  ; there is a nr` branches when `nr` is 0, no next record; BREAK loads `$67`, error 67, ILLEGAL TRACK OR SECTOR,
  as a literal where `ERROR_ILLEGAL_SYSTEM_TRACK_SECTOR` names it (the source uses the constant); and
  NULBUF's `sta (dirbuf),y ; init record w/ cr` (`nulbuf.src` line 29) stores $FF, the empty-record mark, not a
  carriage return. *Recommended.* **Settled:** the reasons describe the code, and the new source's comments say
  what it does.
- D-P5-Q11. **B0TOB0's count.** The copy loop counts Y down from A-1 with `bpl`: counts 1 to 129 copy that many
  bytes, but 0 and 130 to 256 stop after one byte. Its one caller copies 16, so the limit is never reached; the
  code is kept as it is, and the row says what it does rather than claiming a general copy. *Recommended.*
  **Settled:** kept byte for byte, with the limit documented in the routine's comment.

### Rows

| # | Old | Address | New | Kind | Documents (checked) | Used in | Reason |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | FNDREL | $CE0E | Relative::FindRecord | routine | D1541 | addrel 2, record 1 | For the channel's record (`recl`/`rech`, `rs`) and `recptr`: the byte's place in the file, divided by 254 for its block (`relptr`, the remainder plus 2 for the link) and by 120 for its side sector (`ssnum`) and entry (`ssind`, 16 plus twice the remainder). |
| 2 | MULPLY | $CE2C | Relative::FindOffset | routine | D1541 | fndrel 1 | `Relative::Product` = (record - 1) * `rs` + `recptr`: the byte's offset in the file's data. Records 0 and 1 are both the first. |
| 3 | MUL25 | $CE41 | Relative::FindOffset::CountFromZero | local | D1541 | fndrel 1 | Takes 1 from the record number. |
| 4 | MUL50 | $CE4C | Relative::FindOffset::Multiply | local | D1541 | fndrel 2 | The record size into `temp`, the multiplier. |
| 5 | MUL100 | $CE50 | Relative::FindOffset::NextBit | local | D1541 | fndrel 1 | Each bit of the size, low first: a 1 adds the shifted record number to `Relative::Product`. |
| 6 | MUL200 | $CE57 | Relative::FindOffset::Double | local | D1541 | fndrel 1 | Doubles the record number for the next bit. |
| 7 | MUL400 | $CE6D | Relative::FindOffset::Done | local | D1541 | fndrel 2 | `recptr` added: done. |
| 8 | DIV254 | $CE6E | Relative::DivideBy254 | routine | D1541 | fndrel 1 | Divides `Relative::Product` by 254 (bytes in a block): quotient in `Relative::Product`, remainder in `Relative::Accumulator`+1. Skips DivideBy120's load with a `BIT` (Q6). |
| 9 | DIV120 | $CE71 | Relative::DivideBy120 | routine | D1541 | fndrel 1 | Divides `Relative::Product` by 120 (entries in a side sector), or by the divisor in A from DivideBy254: subtracts whole 256s (or 128s), adding the 2 (or 8) each leaves over back in, until what is left is under 256. |
| 10 | DIV100 | $CE77 | Relative::DivideBy120::Swap | local | D1541 | fndrel 1 | Swaps `Relative::Product` with `Relative::Accumulator`+1-3: the dividend into the accumulator. |
| 11 | DIV150 | $CE87 | Relative::DivideBy120::NextStep | local | D1541 | fndrel 1 | Each step: the accumulator divided by 256... |
| 12 | DIV200 | $CE89 | Relative::DivideBy120::ShiftDown | local | D1541 | fndrel 1 | ...a byte at a time, leaving the low byte in `Relative::Accumulator`. |
| 13 | DIV300 | $CEA3 | Relative::DivideBy120::AddQuotient | local | D1541 | fndrel 1 | Adds the step's quotient to `Relative::Product`, and makes it the leftover: times 2 for 254, times 8 for 120. |
| 14 | DIV400 | $CEB0 | Relative::DivideBy120::AddRemainder | local | D1541 | fndrel 1 | Adds the low byte back in. |
| 15 | DIV500 | $CEBF | Relative::DivideBy120::TestSize | local | D1541 | fndrel 2 | Another step while what is left is 256 or more. |
| 16 | DIV600 | $CED6 | Relative::DivideBy120::SetRemainder | local | D1541 | fndrel 2 | Under 256 but not under the divisor: one more in `Relative::Product`, the divisor off the remainder. |
| 17 | DIV700 | $CED8 | Relative::DivideBy120::Done | local | D1541 | fndrel 1 | Done. |
| 18 | ZERRES | $CED9 | Relative::ClearProduct | routine | D1541 | fndrel 2 | `Relative::Product`'s three bytes = 0; returns A = 0. |
| 19 | ACCX4 | $CEE2 | Relative::Quadruple | routine | D1541 | fndrel 1 | `Relative::Accumulator`+1-3 times 4; falls into Double. |
| 20 | ACCX2 | $CEE5 | Relative::Double | routine | D1541 | fndrel 3 | `Relative::Accumulator`+1-3 times 2: clears carry and falls into RotateLeft. |
| 21 | ACC200 | $CEE6 | Relative::RotateLeft | routine | D1541 | fndrel 1 | Rotates `Relative::Accumulator`+1-3 left through carry. |
| 22 | ADDRES | $CEED | Relative::AddToProduct | routine | D1541 | fndrel 2 | `Relative::Product` += `Relative::Accumulator`+1-3. |
| 23 | ADD100 | $CEF0 | Relative::AddToProduct::NextByte | local | D1541 | fndrel 1 | Each byte, X counting up from $FD. |
| 24 | SCRUB | $DDF1 | Files::Flush | routine | D1541 | close 1, record 1, newss 1 | Writes the active buffer back to its block if it is dirty, and waits. |
| 25 | SCR1 | $DDFC | Files::Flush::Clean | local | D1541 | tsutil 1 | Clean, or written. |
| 26 | SETLNK | $DDFD | Relative::SetLink | routine | D1541 | addrel 2 | `track` and `sector` into the active buffer's link, its first two bytes; marks it dirty with MarkDirty (Q2). |
| 27 | GETLNK | $DE0C | Relative::GetLink | routine | D1541 | record 1, addrel 1 | The active buffer's link into `track` and `sector`, leaving its pointer alone. |
| 28 | NULLNK | $DE19 | Relative::EndLink | routine | D1541 | opnchnl 1, addrel 1 | Makes the active buffer the file's last block: track link 0, and the sector link `nr` - 1, the last byte used. |
| 29 | SET00 | $DE2B | Relative::PointAtBuffer | routine | D1541 | tsutil 3, rel4 1, nulbuf 1 | `dirbuf` = the active buffer's start; Y = 0. |
| 30 | CURBLK | $DE3B | Files::GetChannelBlock | routine | D1541 | lookup 2, open 2, tst4 1, addfil 1 | Finds the channel for `sa` (`Files::FindReadChannel`), and falls into GetBufferBlock. |
| 31 | GETHDR | $DE3E | Files::GetBufferBlock | routine | D1541 | opnchnl 2, utlodr 2, open 1, record 1, addrel 1, tstfnd 1 | The block the active buffer holds, from its job header, into `track` and `sector`; `jobnum` = the buffer. |
| 32 | WRTAB | $DE50 | Files::WriteBlock | routine | D1541 | newss 1 | Starts writing the active buffer to the block at `track` and `sector` (StartBlockJob); the caller waits. |
| 33 | RDAB | $DE57 | Files::ReadBlock | routine | D1541 | rel1 3, rename 1, tst2 1 | Starts reading the block at `track` and `sector` into the active buffer; the caller waits. |
| 34 | WRTOUT | $DE5E | Files::WriteBuffer | routine | D1541 | addrel 2, scrtch 1, rename 1, opnchnl 1, tsutil 1, rel1 1, newss 1 | Starts writing the channel's active buffer out to the block its header names, whether or not it is dirty (SCRUB, `Files::Flush`, tests that first), and clears its dirty bit (StartBlockJob::ClearDirty); the caller waits. |
| 35 | RDIN | $DE65 | DROP | local | D1541 | none | Nothing reaches it: WriteBuffer's branch is always taken (Q4). Would read the active buffer from its header; the bytes stay, with a comment. |
| 36 | WRTSS | $DE6C | Relative::WriteSideSector | routine | D1541 | opnchnl 1, addrel 1 | Starts writing the side-sector buffer to its header's block; branches to ReadSideSector's SetCommand. |
| 37 | RDSS | $DE73 | Relative::ReadSideSector | routine | D1541 | opnchnl 1 | Starts reading the side-sector buffer from its header's block, falling into SetCommand and from there, for an allocated buffer, StartBlockJob::Start (Q3). |
| 38 | RDS5 | $DE75 | Relative::ReadSideSector::SetCommand | entry | D1541 | tsutil 1 | The command into `cmd`; X = the channel's side-sector buffer. WriteSideSector branches here, and ReadSideSector falls into it. |
| 39 | SJ10 | $DE7F | Files::StartBlockJob | routine | D1541 | tsutil 2 | The starters' tail (Q3): sets the active buffer's header from `track` and `sector`, and its drive in `lstjob`... |
| 40 | SJ20 | $DE8B | Files::StartBlockJob::ClearDirty | entry | D1541 | tsutil 2 | ...clears its dirty bit (MarkClean), X = the buffer... |
| 41 | SJ30 | $DE92 | Files::StartBlockJob::Start | entry | D1541 | tsutil 1 | ...and starts the job in `cmd` on buffer X, with the drive in `lstjob` (`Jobs::StartOnLastDrive`). |
| 42 | RDLNK | $DE95 | Files::ReadLink | routine | D1541 | rel1 2, open 1 | The active buffer's link into `track` and `sector`, read through its pointer, which is left at 2. |
| 43 | B0TOB0 | $DEA5 | Relative::CopyBuffer | routine | D1541 | newss 1 | Copies A bytes (counting down) from the start of buffer Y to the start of buffer X; a count of 1 to 129 copies that many bytes; 0 or 130 to 256 copies one, as its loop ends with `bpl` (Q11). Its one caller copies 16. |
| 44 | B02 | $DEB9 | Relative::CopyBuffer::NextByte | local | D1541 | ssutil 1 | Each byte, last first. |
| 45 | CLRBUF | $DEC1 | Relative::ClearBuffer | routine | D1541 | opnchnl 1, newss 1 | Fills buffer A with zeros; returns A and Y = 0. |
| 46 | CB10 | $DECC | Relative::ClearBuffer::NextByte | local | D1541 | ssutil 1 | Each of the 256 bytes. |
| 47 | SSSET | $DED2 | Relative::GetSideSectorNumber | routine | D1541 | sstest 1, ssend 1 | `dirbuf` = the start of the side-sector buffer; A = the number of the side sector in it (its byte 2). |
| 48 | SSDIR | $DEDC | Relative::PointAtSideSector | routine | D1541 | ssutil 2, addrel 1, newss 1 | `dirbuf` = byte A of the side-sector buffer; X = that buffer. |
| 49 | SETSSP | $DEE9 | Relative::SetSideSectorPointer | routine | D1541 | opnchnl 2, addrel 2, ssutil 1, ssend 1 | `dirbuf` and the side-sector buffer's `buftab` pointer = byte A of it. |
| 50 | SSPOS | $DEF8 | Relative::PositionSideSector | routine | D1541 | record 1, addrel 1 | Puts the side sector `ssnum` in its buffer, reading it if it exists and is not there, pointing at entry `ssind`: V clear. Past the file's end: points at its last entry (SeekEnd), V set. |
| 51 | SSP10 | $DF0B | Relative::PositionSideSector::OutOfRange | local | D1541 | ssutil 1 | Past the end: SeekEnd, V set. |
| 52 | SSP20 | $DF12 | Relative::PositionSideSector::InRange | local | D1541 | ssutil 2 | The pointer at `ssind`, V clear. |
| 53 | IBRD | $DF1B | Relative::ReadLinkedSideSector | routine | D1541 | ssutil 1, ssend 1, newss 1 | Reads into buffer A the side sector whose track and sector are at (`dirbuf`),Y, on the drive of the channel in X (`lindx`), and waits. |
| 54 | IBWT | $DF21 | DROP | local | D1541 | none | Nothing reaches it: ReadLinkedSideSector's branch is always taken (Q4). Would write the block instead; the bytes stay, with a comment. |
| 55 | IBOP | $DF25 | Relative::ReadLinkedSideSector::StartJob | local | D1541 | ssutil 1 | The command with the drive (from `filtyp`) into `cmd`, the track and sector into the buffer's header, then `Jobs::Run::Repeat` starts it and waits. |
| 56 | GSSPNT | $DF45 | Relative::GetSideSectorPointer | routine | D1541 | addrel 3 | A = the side-sector buffer's pointer, with `dirbuf` there (through `Files::GetPointer::OfBuffer`). |
| 57 | SCAL1 | $DF4C | Relative::CountBlocks | routine | D1541 | ssutil 1 | The loop's body, before its entry (Q5): adds 120 to `t1`/`t2` for each whole side sector. |
| 58 | SSCALC | $DF51 | Relative::CountBlocks::Start | entry | D1541 | close 1, addrel 1 | Where callers enter: adds to `t1`/`t2` 120 for each of X side sectors, half `t3` (the entries), and `t4` (the side sectors' own blocks): a file's block count. Falls into AddToCount. |
| 59 | ADDT12 | $DF5C | Relative::AddToCount | routine | D1541 | ssutil 2 | `t1`/`t2` += A. |
| 60 | ADDRTS | $DF65 | Relative::AddToCount::Done | local | D1541 | ssutil 1 | No carry. |
| 61 | SSTEST | $DF66 | Relative::TestSideSector | routine | D1541 | ssutil 2 | Is entry `ssind` of side sector `ssnum` in the buffer and used? N clear, V clear: yes. N clear, V set: that side sector exists but is not in the buffer. N set: past the end, V clear if the side sector is in the buffer. |
| 62 | ST10 | $DF77 | Relative::TestSideSector::PastEnd | local | D1541 | sstest 1 | In the buffer, but the entry is empty: past the end. |
| 63 | ST20 | $DF7B | Relative::TestSideSector::NotLoaded | local | D1541 | sstest 1 | Another side sector: looks for its link in the buffer's table of side sectors (byte 4 on); leaves `dirbuf` at $xx04 and Y = 2 * `ssnum` for ReadLinkedSideSector. |
| 64 | ST30 | $DF8B | Relative::TestSideSector::NoSuchSideSector | local | D1541 | sstest 1 | `ssnum` is 6 or more, or has no link: past the end. |
| 65 | ST40 | $DF8F | Relative::TestSideSector::Exists | local | D1541 | sstest 1 | It exists, not in the buffer. |
| 66 | GETACT | $DF93 | Files::GetActiveBuffer | routine | D1541 | tst2 5, lstdir 5, tst4 4, tsutil 4, newss 2, rename 1, block 1, tst3 1, jobssf 1, addfil 1, close 1, tstflg 1, rel2 1, idlesf 1, map 1 | A = the channel `lindx`'s active buffer (`buf0`, else `buf1`), its dirty bit off; X = `lindx`; N set if it has none (Q1). |
| 67 | GA1 | $DF9B | Files::GetActiveBuffer::StripDirty | local | D1541 | getact 1 | Takes the dirty bit off. |
| 68 | GAFLGS | $DF9E | Files::GetActiveBufferState | routine | D1541 | rel2 2, tsutil 1, rel1 1, newss 1 | As GetActiveBuffer, with `lbused` = the index of its `buf0`/`buf1` byte (for writing back), and V = its dirty bit; clobbers `t1`. |
| 69 | GA2 | $DFA0 | DROP | local | D1541 | none | Not referenced; marks only the code GAFLGS falls into (Q4). |
| 70 | GA3 | $DFB0 | Files::GetActiveBufferState::TestFlags | local | D1541 | getact 1 | The buffer number, with N and V from the byte's top bits. |
| 71 | GETINA | $DFB7 | Files::GetInactiveBuffer | routine | D1541 | tst2 2 | A = the channel's inactive buffer byte (the one with bit 7 set); Z set if it has none ($FF). |
| 72 | GI10 | $DFBF | Files::GetInactiveBuffer::Test | local | D1541 | getact 1 | Compares with $FF. |
| 73 | PUTINA | $DFC2 | Files::SetInactiveBuffer | routine | D1541 | tst2 2 | Buffer A, with bit 7 set, into the slot of `buf0`/`buf1` the active buffer is not in. |
| 74 | PI1 | $DFCD | Files::SetInactiveBuffer::SecondSlot | local | D1541 | getact 1 | `buf0` is active: into `buf1`. |
| 75 | NXTREC | $DFD0 | Relative::NextRecord | routine | D1541 | rel3 1 | Moves the channel to its next record: the record number up, the buffers on if the record starts in the next block, its first byte into `data`, `nr` past it, and its last byte found (FindRecordEnd); at the file's end sets the last-record flag and gives a carriage return. |
| 76 | NXTR15 | $DFE4 | Relative::NextRecord::CheckNext | local | D1541 | rel1 1 | `nr` 0 means there is no next record (the listing's comment says the opposite; Q10). Past `nr` in this buffer: NextBuffer. |
| 77 | NXTR20 | $DFF6 | Relative::NextRecord::ReadFirstByte | local | D1541 | rel1 1 | The pointer to `nr`, the record's first byte into `data`, the overflow flag cleared, the next `nr` reckoned (AddRecordSize). |
| 78 | NXOUT | $E009 | Relative::NextRecord::CheckEnd | entry | D1541 | record 1 | With A the next record's place and carry set if it is in the next block: in the last block (track link 0) that is the end; otherwise `nr` = A. SeekRecord enters here. |
| 79 | NXTR45 | $E018 | Relative::NextRecord::SetLastRecord | local | D1541 | rel1 1 | Sets the last-record flag... |
| 80 | NXTR40 | $E01D | Relative::NextRecord::AtEnd | local | D1541 | rel1 1 | ...the channel's last character at its pointer, and `data` a carriage return. |
| 81 | NXTR50 | $E02A | Relative::NextRecord::EndsAtBlock | local | D1541 | rel1 1 | The last record ends at the last block's end: its end found, then `nr` = 0. |
| 82 | NXTR30 | $E034 | Relative::NextRecord::NotLast | local | D1541 | rel1 2 | Not the end: A back... |
| 83 | NXTR35 | $E035 | Relative::NextRecord::SetNext | local | D1541 | rel1 1 | ...into `nr`, and on to FindRecordEnd. Called with `jsr` inside the routine, and fallen into. |
| 84 | NRBUF | $E03C | Relative::NextBuffer | routine | D1541 | rel1 1, rel2 1, rel3 1 | On to the next block: writes the active buffer if dirty, swaps to the other buffer (which the read-ahead filled), reads the block there now if its last job was a write, and starts reading the block after into the buffer it left (that read-ahead only on the clean path: after a write it returns once the needed block is in). |
| 85 | NRBU50 | $E05D | Relative::NextBuffer::Clean | local | D1541 | rel1 1 | Clean: swaps without writing. |
| 86 | NRBU70 | $E06B | Relative::NextBuffer::ReadAhead | local | D1541 | rel1 1 | Starts reading the following block into the inactive buffer, unless this is the last. |
| 87 | NRBU20 | $E07B | Relative::NextBuffer::Done | local | D1541 | rel1 2 | Done. |
| 88 | RELPUT | $E07C | Relative::PutByte | routine | D1541 | rel2 2 | `data` into the active buffer at its pointer, marking it dirty; at the record's end (`nr`) sets the overflow flag, and at the block's end goes on to NextBuffer. |
| 89 | RELP06 | $E094 | DROP | local | D1541 | none | Not referenced; marks only the code fallen into (Q4). |
| 90 | RELP05 | $E096 | Relative::PutByte::CompareEnd | local | D1541 | rel2 1 | The next place (past the link if the block ended): is it `nr`? |
| 91 | RELP07 | $E09E | Relative::PutByte::Overflow | local | D1541 | rel2 1 | It is: the overflow flag. |
| 92 | RELP10 | $E0A3 | Relative::PutByte::Advance | local | D1541 | rel2 1 | The pointer on; NextBuffer if it wraps. |
| 93 | RELP20 | $E0AA | Relative::PutByte::Done | local | D1541 | rel2 1 | Done. |
| 94 | WRTREL | $E0AB | Relative::WriteByte | routine | D1541 | tst2 1 | A byte sent to a relative channel: puts it in the record, adding blocks first past the file's end; at EOI fills the record's rest with zeros, moves to the next record, and reports 51 RECORD OVERFLOW if it was too long. A byte past the record's end without EOI is dropped. |
| 95 | WR10 | $E0B2 | Relative::WriteByte::Put | local | D1541 | rel2 1 | Puts `data` (PutByte); jumped to after Extend. |
| 96 | WR20 | $E0B7 | DROP | local | D1541 | none | Not referenced; marks only the code fallen into (Q4). |
| 97 | WR30 | $E0BC | Relative::WriteByte::CheckOverflow | local | D1541 | rel2 1 | EOI after an overflow: the overflow error into `PendingError`. |
| 98 | WR40 | $E0C8 | Relative::WriteByte::EndRecord | local | D1541 | rel2 2 | Fills the record's rest (FillRecord), moves to the next (ReadByte::LoadNextRecord), and reports `PendingError` or OK. |
| 99 | WR45 | $E0D6 | Relative::WriteByte::Ok | local | D1541 | rel2 1 | No error: `Errors::SetOk`. |
| 100 | WR50 | $E0D9 | Relative::WriteByte::FlagSet | local | D1541 | rel2 1 | The last-record or overflow flag is set. |
| 101 | WR51 | $E0E1 | DROP | local | D1541 | none | Not referenced; marks only the code fallen into (Q4). |
| 102 | WR60 | $E0E2 | Relative::WriteByte::Extend | local | D1541 | rel2 1 | Past the last record: AddBlocks, keeping `data`, then the flag off and Put. |
| 103 | CLREC | $E0F3 | Relative::FillRecord | routine | D1541 | rel2 2 | Puts zeros until the record overflows: its rest cleared. |
| 104 | CLR10 | $E104 | Relative::FillRecord::Done | local | D1541 | rel2 1 | Done. |
| 105 | SDIRTY | $E105 | Relative::MarkDirty | routine | D1541 | tsutil 1, rel2 1 | Sets the channel's `dyfile` flag (the file changed) and the active buffer's dirty bit (Q2). |
| 106 | CDIRTY | $E115 | Files::MarkClean | routine | D1541 | tsutil 1 | Clears the active buffer's dirty bit (Q2). |
| 107 | RDREL | $E120 | Relative::ReadByte | routine | D1541 | tst4 1 | Readies a relative channel's next byte in `chndat`, with EOI on the record's last; at a record's end, the next record's first; past the file's end, 50 RECORD NOT PRESENT. |
| 108 | RD10 | $E127 | DROP | local | D1541 | none | Not referenced; marks only the code fallen into (Q4). |
| 109 | RD15 | $E138 | Relative::ReadByte::ReadAtPointer | entry | D1541 | record 1 | The byte at the active buffer's pointer, readied. SeekRecord enters here. |
| 110 | RD20 | $E13B | Relative::ReadByte::Load | local | D1541 | rel3 1 | Loads the byte... |
| 111 | RD25 | $E13D | Relative::ReadByte::Store | local | D1541 | rel3 1 | ...into `chndat`, ready, or with EOI if it is the record's last (`lstchr`). |
| 112 | RD30 | $E14D | Relative::ReadByte::LastByte | local | D1541 | rel3 1 | The record's last: EOI. |
| 113 | RD40 | $E153 | Relative::ReadByte::LoadNextRecord | entry | D1541 | opnchnl 1, rel2 1, rel3 1 | NextRecord, then its first byte readied. |
| 114 | RD05 | $E15E | Relative::ReadByte::NoRecord | entry | D1541 | record 2, rel3 1 | Past the end: a carriage return with EOI, and 50 RECORD NOT PRESENT. |
| 115 | SETLST | $E16E | Relative::FindRecordEnd | routine | D1541 | rel1 1 | Sets the channel's last character (`lstchr`) to the record's last nonzero byte, looking in the next buffer first if the record runs into it; an all-zero record ends at its first byte. |
| 116 | SETL01 | $E17E | Relative::FindRecordEnd::GetSize | local | D1541 | rel4 1 | `r2` = `rs`, the bytes to look at (`r1`, the record's last place, `nr` - 1 or $FF if it ends the block, is set in SETLST before it). |
| 117 | SETL05 | $E19D | Relative::FindRecordEnd::NotInNext | local | D1541 | rel4 1 | Nothing in the next buffer: back, from the block's end. |
| 118 | SETL10 | $E1A4 | Relative::FindRecordEnd::SearchThis | local | D1541 | rel4 2 | Looks in the active buffer. |
| 119 | SETL40 | $E1AC | Relative::FindRecordEnd::Store | local | D1541 | rel4 1 | Into `lstchr`. |
| 120 | FNDLST | $E1B2 | Relative::FindLastNonzero | routine | D1541 | rel4 2 | Looks back from byte `r1` of the active buffer, down to byte 2 and for at most `r2` bytes, for one not zero: carry set and A its place if found. |
| 121 | FNDL10 | $E1B7 | Relative::FindLastNonzero::Loop | local | D1541 | rel4 1 | Each byte. |
| 122 | FNDL30 | $E1C4 | Relative::FindLastNonzero::NotFound | local | D1541 | rel4 1 | Carry clear. |
| 123 | FNDL20 | $E1C8 | Relative::FindLastNonzero::Found | local | D1541 | rel4 1 | Carry set, A = its place. |
| 124 | SSEND | $E1CB | Relative::SeekEnd | routine | D1541 | rename 2, close 1, ssutil 1, addrel 1 | Puts the file's last side sector in its buffer, found from the link table, with `ssnum` its number and `ssind` and the pointer at its last entry: the last data block. |
| 125 | SE10 | $E1D8 | Relative::SeekEnd::PreviousLink | local | D1541 | ssend 1 | Back a link... |
| 126 | SE20 | $E1DC | Relative::SeekEnd::TestLink | local | D1541 | ssend 1 | ...until one is used: that side sector is the last; read if not the one in the buffer. |
| 127 | SE30 | $E1EF | Relative::SeekEnd::LastSideSector | local | D1541 | ssend 1 | Its own link must be 0 (else SideSectorError); its byte 1, the last used, less 1, is the last entry. |
| 128 | BREAK | $E202 | Relative::SideSectorError | routine | D1541 | ssend 2, record 1 | Error 67, ILLEGAL TRACK OR SECTOR: the side sectors do not make sense. Loads `$67` where `systs` names it (Q9, Q10). |
| 129 | RECORD | $E207 | Relative::PositionCommand | routine | D1541 | romtblsf 2 | The P command (Q8): sets the channel on the secondary address in the command to the record and byte given, through the side sectors; 50 RECORD NOT PRESENT past the end, 51 RECORD OVERFLOW for a byte past the record's size. |
| 130 | R20 | $E219 | Relative::PositionCommand::HaveChannel | local | D1541 | record 1 | The channel found (else 70 NO CHANNEL); its flags cleared. |
| 131 | R30 | $E228 | Relative::PositionCommand::IsRelative | local | D1541 | record 1 | A relative file (else 64 FILE TYPE MISMATCH): the drive, record number and ready state set. |
| 132 | R35 | $E253 | Relative::PositionCommand::SetOffset | local | D1541 | record 1 | As R40: one label at this address (Q7). |
| 133 | R40 | $E253 | Relative::PositionCommand::SetOffset | local | D1541 | record 2 | `recptr` = the byte, from 0 (the command's 0 and 1 are both the first); FindRecord and PositionSideSector. |
| 134 | R50 | $E265 | Relative::PositionCommand::Found | local | D1541 | record 1 | In the file: SeekRecord. |
| 135 | R60 | $E272 | Relative::PositionCommand::Done | local | D1541 | record 1 | `Commands::Finish`. |
| 136 | POSITN | $E275 | Relative::SeekRecord | routine | D1541 | record 1, addrel 1 | With the side sector placed: the record's block into the active buffer (LoadBlocks), the pointer to `relptr`, `nr` past the record, and its first wanted byte readied (ReadByte::ReadAtPointer). |
| 137 | P2 | $E289 | Relative::SeekRecord::SetNext | local | D1541 | record 1 | The record's end: `relptr` + `rs` - `recptr`, plus 2 if it runs into the next block. (`rs` under `recptr` cannot happen: SideSectorError.) |
| 138 | P30 | $E291 | Relative::SeekRecord::CheckEnd | local | D1541 | record 1 | NextRecord::CheckEnd, then ReadAtPointer. |
| 139 | POSBUF | $E29C | Relative::LoadBlocks | routine | D1541 | rename 1, record 1, addrel 1 | Makes the active buffer hold the data block the side-sector pointer names, and the other buffer the block after: nothing if it is there; if the wanted block is the buffer's next, a swap (`dblbuf`) and a jump to FreeInactiveBuffer, which frees the old buffer and reads nothing after; else a read. The listing's "yes!" is on the branch for not there (Q10). |
| 140 | P10 | $E2AA | Relative::LoadBlocks::NotLoaded | local | D1541 | record 1 | Not in the buffer: writes it if dirty (Flush), takes its link; if that is 0 (last block) goes to ReadWanted, else is the block wanted that link? If so, swaps and frees the old buffer (`Files::FreeInactiveBuffer`), reading nothing. |
| 141 | P75 | $E2BF | Relative::LoadBlocks::NotNext | local | D1541 | record 1 | Not the next: frees the inactive buffer (`Files::FreeInactiveBuffer`)... |
| 142 | P80 | $E2C2 | Relative::LoadBlocks::ReadWanted | local | D1541 | record 1 | ...and reads the block wanted, and the one after into the other buffer (`Files::StartDoubleRead`). |
| 143 | BHERE | $E2D0 | Relative::IsInBuffer | routine | D1541 | record 1 | Z set if the active buffer holds the block named at (`r3`): its header's block (GetBufferBlock), then IsSameBlock. |
| 144 | BHERE2 | $E2D3 | Relative::IsSameBlock | routine | D1541 | record 1 | Z set if `track` and `sector` are the block named at (`r3`). |
| 145 | BH10 | $E2DC | Relative::IsSameBlock::TestSector | local | D1541 | record 1 | The track matches: the sector. |
| 146 | NULBUF | $E2E2 | Relative::FillEmptyRecords | routine | D1541 | addrel 2, opnchnl 1 | Makes the active buffer a block of empty records: zeros after the link, with $FF at each record's start, from `nr` (where the last record ended in the block before); `nr` left at the last record's place, or 0 if it ends the block. |
| 147 | NB10 | $E2E9 | Relative::FillEmptyRecords::ClearByte | local | D1541 | nulbuf 1 | Each byte from 2 to the block's end. |
| 148 | NB20 | $E2F1 | Relative::FillEmptyRecords::MarkRecord | local | D1541 | nulbuf 1 | Each record in the block: $FF at its start. |
| 149 | NB30 | $E303 | Relative::FillEmptyRecords::Done | local | D1541 | nulbuf 1 | Done. |
| 150 | ADDNR | $E304 | Relative::AddRecordSize | routine | D1541 | nulbuf 2, rel1 1 | A = `nr` + `rs`, the next record's place; carry set if that is in the next block, where it is moved past the link (exactly the block's end gives 2 with Z set). `nr` 0 gives 2. |
| 151 | AN05 | $E318 | Relative::AddRecordSize::NextBlock | local | D1541 | nulbuf 2 | In the next block: 2 more, for its link. |
| 152 | AN10 | $E31B | Relative::AddRecordSize::Done | local | D1541 | nulbuf 1 | Done. |
| 153 | ADDREL | $E31C | Relative::AddBlocks | routine | D1541 | rel2 1 | Extends the file to the record wanted: counts the blocks and side sectors needed against the free blocks (52 FILE TOO LARGE), then adds blocks of empty records, with new side sectors as they fill, and the BAM written; ends at the record (SeekRecord). |
| 154 | ADDR1 | $E33B | Relative::AddBlocks::CheckRoom | entry | D1541 | rename 1 | With the end found: counts the free blocks (`Bam::CopyFreeBlocks`) and what is needed. The relative-file copy in `rename` enters here. |
| 155 | AR10 | $E355 | Relative::AddBlocks::SetPointer | local | D1541 | addrel 2 | The side-sector pointer past the file's last entry. |
| 156 | AR20 | $E363 | Relative::AddBlocks::TooBig | local | D1541 | addrel 2 | 52 FILE TOO LARGE: more than 6 side sectors, or not enough free blocks. |
| 157 | AR25 | $E368 | Relative::AddBlocks::CountNeeded | local | D1541 | addrel 1 | The entries needed... |
| 158 | AR30 | $E372 | Relative::AddBlocks::CountSideSectors | local | D1541 | addrel 1 | ...and the side sectors, into CountBlocks; `r2` set if it is one block. |
| 159 | AR35 | $E38F | Relative::AddBlocks::CompareFree | local | D1541 | addrel 2 | Against the free blocks (`nbtemp`). |
| 160 | AR40 | $E39D | Relative::AddBlocks::LinkNext | local | D1541 | addrel 1 | Room: `nr` from the last block's sector link, and a new block linked to it. |
| 161 | AR45 | $E3B6 | Relative::AddBlocks::NextBlock | local | D1541 | addrel 2 | Each new block but the last: in the other buffer, linked to one more new block, filled with empty records. |
| 162 | AR50 | $E3C8 | Relative::AddBlocks::LastBlock | local | D1541 | addrel 2 | The last new block: empty records, link ended (EndLink). |
| 163 | AR55 | $E3D4 | Relative::AddBlocks::WriteAndRecord | local | D1541 | addrel 1 | Writes the block and puts its track and sector in the side sector, starting a new side sector (NewSideSector) if that one is full. |
| 164 | AR60 | $E3F9 | Relative::AddBlocks::PutEntry | local | D1541 | addrel 1 | The entry put (`Relative::PutSideSectorByte`); on while blocks remain. |
| 165 | AR65 | $E418 | Relative::AddBlocks::Finish | local | D1541 | addrel 1 | Ends the side sector (link 0, its last byte), writes it and the BAM, and finds the record again. |
| 166 | AR70 | $E444 | Relative::AddBlocks::NoRecord | local | D1541 | addrel 1 | Still not in the file: 50 RECORD NOT PRESENT. |
| 167 | NEWSS | $E44E | Relative::NewSideSector | routine | D1541 | addrel 1 | Starts a side sector in a new block: copies the link table into it, adds itself to the table, writes it, makes it the side-sector buffer, links the old one to it, and adds it to every earlier side sector's table. |
| 168 | NS20 | $E4AC | DROP | local | D1541 | none | Not referenced; marks only the code fallen into (Q4). |
| 169 | NS40 | $E4D1 | Relative::NewSideSector::ReadEarlier | local | D1541 | newss 1 | The side sector before, read into the active buffer... |
| 170 | NS50 | $E4DE | Relative::NewSideSector::AddToTable | local | D1541 | newss 1 | ...the new side sector's track and sector put in its table, and written; on while earlier ones remain. |

## Part 6: the serial bus, the idle loop, start-up, errors and the ROM's tables and vectors

Settled on 2026-11-27 after an independent review of the part (D2, D7).

The listing's `LEDS` (`$C100-$C12F`), `ERPROC` (`$E4FC-$E77E`), `SER.ATN`, `SER.TALK` and `SER.LISTN`
(`$E853-$EA6D`), `DSKINT.SF` (`$EA6E-$EBE6`), `IDLE...SF` (`$EBE7-$EC9C`), `SYSTEM` (KILLP, `$F258`), `ROMTBL`
(`$FE85-$FEE5`) and `VECTOR` (`$FEE6-$FFFF`): 178 labels and two assembly-time constants, 180 rows. The drive is the
other end of the kernal's serial bus (part 3 of the kernal's table): where the DOS does the same step from the
device's side it takes the kernal's name for it (`ReceiveByte`, `PullClock`, `ReadLines`, `WaitClockHigh`). The
variables are part 1's, being drafted at the same time, so the reasons cite them by their listing names (ATNMOD,
ERWORD, SerialNoDelay). Every address is 901229-05's; question D-P6-Q7 lists where the other revisions and the 1540
differ.

### Questions

- D-P6-Q1. **The serial bus's names are the kernal's, from the device's end.** The drive receives exactly as the
  computer does, so ACPTR is `Serial::ReceiveByte` with the kernal's locals where the step is the same
  (`WaitForTalker`, `WaitForClock`, `Eoi`, `WaitClockHigh`, `WaitClockLow`); TALK's byte loop is the kernal's
  SendBufferedByte from the other side (`WaitReady`, `NextBit`, `BitOne`, `ClockBit`, `EoiReleased`,
  `EoiAcknowledged`, `WaitAccepted`). The four line routines are named for the bus line, as K-P3-Q2 has it:
  DATHI, DATLOW, CLKHI and CLKLOW are `ReleaseData`, `PullData`, `ReleaseClock` and `PullClock` (VIA 1 port B's
  DATOUT and CLKOUT bits, through the inverters), and DEBNC is `ReadLines`. The drive's own roles take the
  kernal's words for them: TALK and LISTEN, which here *are* the talker and the listener rather than sending the
  commands, are `Serial::Talk` and `Serial::Listen`; ATNIRQ is `Serial::AtnInterrupt`, ATNSRV
  `Serial::HandleAtn`, TSTATN `Serial::CheckAtn`, and ILERR (with FRMERR and ITERR, the same address)
  `Serial::BusError`, the kernal's name (K-P3), with FRMERR and ITERR entries of it. The kernal's own `Serial::Talk` is
  in another module, so the names do not clash. *Recommended.* The alternative is device-side names
  (`Serial::BeTalker`), which read worse and break the parallel with the kernal's table. **Settled:** the serial bus
  takes the kernal's names, from the device's end, with ILERR, FRMERR and ITERR as `Serial::BusError`.
- D-P6-Q2. **Two names at one address.** ACP01 and ACP03 (`$EA0B`) are one local, `WaitClockHigh`, with ACP01 in
  `Also:`; FRMERR, ITERR and ILERR (`$EA4E`) are one routine, `Serial::BusError`, with the other two in
  `Also:` as entries (as the kernal's part 3 has them). MAXTRK and TRKNUM (`$FED7`) are two jobs of one table: TRKNUM's
  four zone limits, whose first byte, 36, is also one past the last track. They stay two labels, `TrackLimit` and
  `ZoneLimits`, with an `.assert` that they are the same address and a comment saying why. *Recommended.* **Settled:**
  ACP01/ACP03 and FRMERR/ITERR/ILERR share one name each (`Serial::BusError` with entries), and MAXTRK/TRKNUM stay two
  labels with an `.assert`.
- D-P6-Q3. **The error message table and its tokens.** ERRTAB is `Errors::Messages`. Each entry is one or more
  error numbers, written in BCD as the DOS keeps them (`$20` is 20), then the text, whose first and last bytes
  have bit 7 set; a byte below `$20` in the text (bit 7 apart) is a token, the number of a shared word, which
  ERMOVE expands, with a space before it, by searching the same table for an entry with that number (the listing's
  comment says tokens are below `$10`; the code takes anything below `$20`). The nine words (ERROR `$09`, WRITE
  `$0A`, FILE `$03`, OPEN `$04`, MISMATCH `$05`, NOT `$06`, FOUND `$07`, DISK `$08`, RECORD `$0B`) are entries at the
  table's end. Recommended: the tokens get constants, `Errors::WORD_ERROR` to `Errors::WORD_RECORD` (new names: the
  listing gives the words only in comments), and each entry is written with a macro, `Message`, that takes the
  numbers and the text and sets bit 7 on the text's first and last bytes, so an entry reads
  `Message $50, WORD_RECORD, WORD_NOT, " PRESENT"`; ETEND, the table's end, used only as the search's bound, is a
  label, `Errors::MessagesEnd`, with the end check's slip (it also compares the byte at `MessagesEnd`, ERROR's
  first, before stopping) documented. Message 73 is `CBM DOS V2.6 1541`, and the 1540's `CBM DOS V2.6 V170`, under
  its switch. *Recommended.* The alternative is plain `.byte` lines as the listing has them, which hide the
  scheme. **Settled:** the error table is `Errors::Messages` written with a `Message` macro and `Errors::WORD_*` token
  constants, with `Errors::MessagesEnd` documenting the one-byte overrun, and ETEND sharing ERROR's address.
- D-P6-Q4. **The ROM's tables are top level**, since the command parser, OPEN, the directory, the BAM, relative
  files and the controller read them. Each is named for what it holds: `CommandLetters` (CMDTBL,
  `VIDMBUP&CRSN`), `CommandRoutinesLow` and `CommandRoutinesHigh` (CJUMPL, CJUMPH: validate, initialize,
  duplicate, memory, block, user, position, the utility loader, copy, rename, scratch, new), with `.assert`s that
  both have Commands::COUNT entries; `CommandPatterns` (a label at `$FEAD`, the first pattern byte, which the listing
  does not name), and STRUCT, the listing's name at `$FEA5`, is not a table: it is an equate, `CommandPatterns - 8`, a
  constant (`PATTERN_ORIGIN`) so the command's number indexes the table (copy is 8, rename 9, scratch 10, new 11, and
  `Commands::LOAD_STRUCTURE`, 12, is LOAD's); the 8 is the number of the first command with a pattern, named in the
  equate's comment (the conversion adds the label; `$FEA1-$FEAC` is CJUMPH); `FileModes` (MODLST, `RWAM`);
  `OpenTypeLetters` (TPLST, `DSPUL`, the letters OPEN takes, L for relative); `TypeFirstLetters`, `TypeSecondLetters`
  and `TypeThirdLetters` (TYPLST, TP1LST, TP2LST: DEL, SEQ, PRG, USR, REL, as the directory lists them); and the disk's
  constants in ROM, `DirectoryTrack`, `BamEntrySize`, `BamOffset` (MAPOFF, which nothing reads), `DiskNameOffset`,
  `FormatType`, `ZoneCount`, `SectorsPerTrack`, `TrackLimit`, `ZoneLimits`, `RecoveryOffsets`, `BufferPages` and
  `LedMasks`. ER00-ER3 are bytes a `BIT` reads to set N and V as a routine's answer: `BitZero` (0, Z set too),
  `BitNeither` ($3F), `BitOverflow` ($7F), `BitNegative` ($BF) and `BitBoth` ($FF). *Recommended.* These stay ROM bytes
  read by `LDA`, not assembly-time constants, because the code reads them from the ROM (the listing meant them to be
  patched without reassembling). **Settled:** the ROM's tables are top-level, named for what they hold,
  `CommandPatterns` is a new label at `$FEAD` with STRUCT an equate `CommandPatterns - 8` named `PATTERN_ORIGIN`, and
  the `Bit*` bytes stay ROM bytes.
- D-P6-Q5. **The vectors at the ROM's end.** `$FFE6-$FFF9` are ten words: FORMAT and TRNOFF (no listing label), then
  UBLOCK's eight, which the user commands jump through (`Commands::UserVectorsPointer` points at UBLOCK; U1 or UA takes
  the first word): U1 and U2 are UBLKRD and UBLKWT, U3-U8 jump into buffer 2 at `$0500`, `$0503`... `$050F`. The table
  runs on into the processor's vectors, so U9 (UI) reaches the NMI vector's target, U: (UJ) the reset's and U; the
  IRQ's. Recommended: UBLOCK is `UserCommandVectors`, top level, with a comment that U9 to U; read the next three words;
  the two words before it get new names, `FormatVector` and `MotorOffVector`, since programs call through them and no
  listing names them (rows are not added for them: they are new names, given here); the processor's vectors are three
  `.word`s with no labels, as K-P7-Q1 has it. NNMI, the NMI vector's target, is `Startup::Nmi` (UI- sets the 64's bus
  speed, UI+ the VIC-20's, UI alone restarts), and NMI, its `JMP (VNMI)`, is `Startup::Reinitialize` (it jumps to
  Initialize, with no self-test), a routine since the 1540's NMI vector points straight at it. *Recommended.*
  **Settled:** UBLOCK is `UserCommandVectors` (pointed at by `Commands::UserVectorsPointer`), the two words before it
  are `FormatVector` and `MotorOffVector`, NNMI is `Startup::Nmi` and NMI is `Startup::Reinitialize`.
- D-P6-Q6. **The patches.** Code moved to the patch area at `$FEEA-$FF2E` and jumped to from the middle of a
  routine is a `.proc` of its own in that routine's family, named for the routine with `Patch`, with a comment
  saying where it returns: PEA7A `Startup::BlinkFaultPatch`, PATCH5 `Startup::ResetPatch` and PATCH6
  `Serial::ReceiveBytePatch`. The labels they return to are entries of the routine they return into (REA7D
  `Startup::BlinkFault::LedsLit`, DKIT10 `Startup::Reset::SelfTest`, ACP00 `Serial::ReceiveByte::WaitForClock`).
  SLOWD and CLKDAT, which TALK calls, are routines of their own, `Serial::SlowDown` and
  `Serial::PullClockAndReleaseData`. *Recommended.* The alternative, `.scope ... continued` pieces as K-P3-Q3 has,
  suits whole routines moved for room, not fragments that jump back. **Settled:** the patches are routines of their own
  in their families, named with `Patch`, and the labels they return to are entries.
- D-P6-Q7. **The revisions' switches.** Byte comparisons of the dumps give these differences in this part (each
  against 901229-05, which the rows describe): 
  - -01 to -03: TLKERR and LSNERR `JSR ILERR` (`$E683`, `$E68B`; TLKERR's listing comment says ITERR, but both are
    `$EA4E`) where -05 has three NOPs, so the old ROMs release the bus and go idle without freeing the channel; BOOT
    (`$E780-$E7A2`, part 3's) is the power-on utility loader, which -05 turned into an RTS and NOPs; ACPTR starts its
    timer inline (`STA T1HC1` at `$E9DC`, after `LDA #1` at `$E9DA`) where -05 jumps to PATCH6; DSKINT sets DDRA1 inline
    (`$EAA4`) where -05 jumps to PATCH5; after SETERR (`$EBDB`) the bus is set up DDRB1 first, then PB, where -05
    releases the lines (PB) before it sets their directions; `$FF10-$FF2E` is fill (`$AA`).
  - -01 alone: ACPTR's bit loop reads CLK and then DATA in two reads (`$EA0E-$EA17`); -02's speed-up reads both at
    once and leaves the three NOPs the listing has.
  - -02 and -03: `RSR` in the fill at `$FFE2`.
  - -06: a patch at `$FF2F` (`LDA #$FF`, `STA $51`, `JMP FORMAT`) that NEW calls (the `JSR` at `$EE3D`; `$EE3E` is its
    operand; part 3's) instead of FORMAT, so the format starts with FormatTrack at `$FF`; it has no listing name, and is
    `Commands::FormatPatch`, beside `Commands::Format`.
  - ECHKSM: `$FD`, `$10`, `$0E`, `$3E` and `$EC` for -01, -02, -03, -05 and -06; `$60` in the 1540's 325303-01.
  - 325303-01, the 1540, is -01 with four changes in this part: no SLOWD, CLKDAT or NNMI (`$FEF3-$FF0F` is fill),
    TALK's ISRCLK clocks each bit without the speed test (`JSR CLKHI`, four NOPs, `JSR CLKLOW`, `JSR DATHI` at
    `$E979-$E982`), the NMI vector points at NMI (`$FEE7`), and message 73 reads V170. (-01's and -02's `$F58D`
    and `$FCD0`, and the 1540's `$FC86`, are part 2's.)
  Recommended: one `.if` per difference on the revision's constant, at the place, with the -05 names kept
  wherever the code exists; the patch routines (and their `JMP`s) are built only in the revisions that have
  them; the rows are 901229-05's. *Recommended.* **Settled:** each revision difference is one `.if` on the revision's
  constant at its place, with the corrected addresses (`$E683`, `$E68B`, `$E9DC`, `$EE3D`) and four changes for the
  1540; -06's patch is `Commands::FormatPatch`, built for R6 only.
- D-P6-Q8. **Labels nothing reaches.** As the brief and K-P7 (RAMTBT) have it, a label nothing refers to and that
  marks no data is dropped, its code kept and its name in prose: ISR02, ERMSG2, CR20, CR30, RAMTST, INTTAB and
  SETERR (SETERR's place, where 73's message and the bus's set-up begin, gets a comment naming it, since the
  revisions' switch is there). Two are code nothing calls: LEDSON (lights both LEDs; `$C118`) and ATNLOW (a `JMP
  ATNSRV`; `$EA56`). Recommended: they are dropped too, their bytes kept with a comment saying they are
  unreached, rather than named as routines nobody calls. MAPOFF marks data and stays (Q4). *Recommended.* **Settled:**
  unreached labels are dropped, their code kept with a comment, and MAPOFF stays as data.
- D-P6-Q9. **Scope of the LED routines.** SETLDS lights the activity LED and is called by three families (Directory,
  Commands and Files), so it is top level, `TurnOnActivityLed`; it belongs to none of them. ERRON, ERROFF (and Abort)
  are called from other families too, but they are the error family's own: the error channel and its flashing are its
  job, so they stay in `Errors`; ERRON and ERROFF start and stop the error flashing and are `Errors::StartFlashing` and
  `Errors::StopFlashing`. KILLP, a stub (its body is commented out) that three commands (block, memrw, utlodr) call
  before running code in the drive, belongs to Commands, `Commands::DisableProtection`. *Recommended.* **Settled:**
  SETLDS is top-level `TurnOnActivityLed` (three families call it), ERRON and ERROFF are `Errors::StartFlashing` and
  `Errors::StopFlashing`, and KILLP is `Commands::DisableProtection`.
- D-P6-Q10. **The code's slips are documented, not changed.** (1) In -05, TLKERR's branch to TLERR tests the flags
  FNDRCH leaves (the removed `JSR` had made the branch unreachable): when FNDRCH fails (carry set, A negative) the BNE
  is taken with LINDX stale, so TLERR frees whatever channel LINDX last named; a channel whose index is 0 runs on
  through LSNERR's FNDWCH as well (harmless). (2) IDLE tests ERWORD for `$80` as the flashing's first pass, but ERRON
  sets it to `$50` (80 decimal), so that path is never taken. (3) ERMOVE's bound check compares one byte past the table
  (Q3). (4) The listing's warning that CLOSE under ATN may not return in time stays as the comment's. (5) PATCH5's
  comment says it sets the clock high; it writes `$02`, which releases CLK and pulls DATA while the self-test runs.
  *Recommended.* **Settled:** the code's slips (including TLERR freeing a stale channel on a failed FNDRCH) are
  documented, not changed.

### Rows

| # | Old | Address | New | Kind | Documents (checked) | Used in | Reason |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | SETLDS | $C100 | TurnOnActivityLed | routine | D1541 | lookup 3, setdrv 1, block 1, tst2 1, tst4 1, open 1, new 1 | Lights DRVNUM's LED in LEDPRT, LED0 for drive 0 (LED1 is 0: the 1541 has one), the other cleared; interrupts off meanwhile. Top level (Q9). |
| 2 | LEDS0 | $C110 | TurnOnActivityLed::Drive0 | local | D1541 | leds 1 | Drive 0: LED0. |
| 3 | LEDS1 | $C113 | TurnOnActivityLed::Store | local | D1541 | leds 1 | Writes LEDPRT. |
| 4 | LEDSON | $C118 | DROP | local | D1541 | none | Lights both LEDs; nothing calls it: its code is kept, unreached, with the name in prose (Q8). |
| 5 | ERROFF | $C123 | Errors::StopFlashing | routine | D1541 | parsex 1, tst4 1, erproc 1 | Stops the error LED's flashing: ERWORD and ERLED = 0. |
| 6 | ERRON | $C12C | Errors::StartFlashing | routine | D1541 | erproc 1 | Starts the flashing: ERWORD = `$50` (80 decimal), ERLED = drive 0's mask from LedMasks, and that LED on; X kept, interrupts off meanwhile. |
| 7 | ERRTAB | $E4FC | Errors::Messages | table | D1541 | erproc 2 | The error messages: each entry its BCD numbers, then its text, first and last bytes with bit 7 set and tokens for shared words; the words last (Q3). |
| 8 | ERROR | $E60A | Errors::JobError | routine | D1541 | duplct 1, jobssf 1 | A = a job's error code, X = the job: TRACK and SECTOR from its HDRS entry, the code made the DOS's number (2-11 are 20-29, $10 is 24, $0F is 74), then Abort; while validating it skips Abort: CMDNUM = `$FF`, the message is set, the drive reinitialized (INITDR) and it goes to Recover (ERR3 to INITDR, CMDER3). Shares `$E60A` with `Errors::MessagesEnd` (ETEND), the table's end. |
| 9 | ERR1 | $E625 | Errors::JobError::DecodingError | local | D1541 | erproc 1 | The low nybble 0, code $10: 24. |
| 10 | ERR2 | $E627 | Errors::JobError::Convert | local | D1541 | erproc 1 | The code plus $20, less 2. |
| 11 | ERR3 | $E62D | Errors::JobError::CheckValidating | local | D1541 | erproc 1 | Validating? |
| 12 | ERR4 | $E644 | Errors::JobError::NotValidating | local | D1541 | erproc 1 | The number back, and on into Abort. |
| 13 | CMDER2 | $E645 | Errors::Abort | routine | D1541 | tstfnd 3, jobssf 2, utlodr 2, parsex 1, block 1, close 1, ssend 1 | A = an error number: sets its message with the current TRACK and SECTOR, and falls into Recover. |
| 14 | CMDER3 | $E648 | Errors::Recover | routine | D1541 | tst2 1, erproc 1, frets 1 | Ends a failed command: clears the command buffer and WBAM, starts the flashing, frees the internal channel, resets the stack, and goes idle; for a data channel it first frees the channel (not a relative or direct one) of the listener or talker it was. |
| 15 | TLKERR | $E680 | Errors::Recover::WhileTalking | local | D1541 | erproc 1 | Talking: the read channel (the listing's comment says ITERR; Q10's slip, and -01 to -03 release the bus here, Q7). |
| 16 | LSNERR | $E688 | Errors::Recover::WhileListening | local | D1541 | erproc 1 | Listening: the write channel. |
| 17 | TLERR | $E68E | Errors::Recover::FreeChannel | local | D1541 | erproc 2 | Frees LINDX's channel unless its file is relative or direct (Files::ChannelType at RELTYP or above). |
| 18 | ERR10 | $E698 | Errors::Recover::ToIdle | local | D1541 | erproc 3 | On to the idle loop. |
| 19 | HEXDEC | $E69B | Errors::PutDecimal | routine | D1541 | erproc 2 | A = a number below 100: made BCD by counting up in decimal mode, then falls into PutBcd. |
| 20 | HEX0 | $E69F | Errors::PutDecimal::Count | local | D1541 | erproc 1 | Each count. |
| 21 | HEX5 | $E6AA | Errors::PutDecimal::Converted | local | D1541 | erproc 1 | Binary mode again. |
| 22 | BCDDEC | $E6AB | Errors::PutBcd | routine | D1541 | erproc 1 | A = BCD: its two digits at (CB+2),Y, Y advanced; X = the BCD. |
| 23 | BCD2 | $E6B4 | Errors::PutDigit | routine | D1541 | erproc 1 | A's low digit as ASCII at (CB+2),Y, Y advanced. |
| 24 | OKERR | $E6BC | Errors::SetOk | routine | D1541 | parsex 1, rel2 1 | Stops the flashing and falls into SetMessageWithoutBlock with 00: 00, OK,00,00. |
| 25 | ERRTS0 | $E6C1 | Errors::SetMessageWithoutBlock | routine | D1541 | tst4 1, dskintsf 1 | TRACK and SECTOR = 0, and falls into SetMessage. |
| 26 | ERRMSG | $E6C7 | Errors::SetMessage | routine | D1541 | erproc 2, parsex 1, frets 1 | A = the error's BCD number: writes "nn,TEXT,tt,ss" to ERRBUF, puts its first byte in the error channel's CHNDAT and its end in LSTCHR, and makes the channel ready to talk. |
| 27 | ERMSG2 | $E6E3 | DROP | local | D1541 | none | Not referenced: where the track and sector are added. |
| 28 | ERMOVE | $E706 | Errors::CopyMessage | routine | D1541 | erproc 2 | A = a BCD error number or a token: finds its entry in Messages and copies the text to (CB+2),Y, expanding tokens by calling itself; R0 kept. Copies nothing if none matches. |
| 29 | E10 | $E718 | Errors::CopyMessage::Compare | local | D1541 | erproc 1 | Does this entry's number match? |
| 30 | E20 | $E722 | Errors::CopyMessage::SkipText | local | D1541 | erproc 1 | No: past the entry's text, to its last byte. |
| 31 | E30 | $E727 | Errors::CopyMessage::CheckEnd | local | D1541 | erproc 1 | Until past MessagesEnd (Q10: one byte past). |
| 32 | E40 | $E735 | Errors::CopyMessage::Next | local | D1541 | erproc 1 | The next byte. |
| 33 | E45 | $E739 | Errors::CopyMessage::NotFound | local | D1541 | erproc 2 | Not in the table. |
| 34 | E50 | $E73D | Errors::CopyMessage::Found | local | D1541 | erproc 2 | Past the entry's other numbers, to its text. |
| 35 | E55 | $E742 | Errors::CopyMessage::CopyText | local | D1541 | erproc 1 | Each byte, to the last. |
| 36 | E90 | $E74D | Errors::CopyMessage::Done | local | D1541 | erproc 1 | R0 back. |
| 37 | E60 | $E754 | Errors::PutMessageByte | routine | D1541 | erproc 2 | A = a byte of a message's text: below $20 it is a token, a space and the word; otherwise the character. |
| 38 | E70 | $E763 | Errors::PutMessageByte::Character | local | D1541 | erproc 1 | A character: at (CB+2),Y. |
| 39 | EADV1 | $E767 | Errors::AdvanceAndRead | routine | D1541 | erproc 2 | R0 up one, then Read. |
| 40 | EA10 | $E76D | Errors::AdvanceAndRead::Read | entry | D1541 | erproc 2 | The byte at R0: A = it without bit 7, carry = bit 7 (a text's first or last byte). |
| 41 | EADV2 | $E775 | Errors::ReadAndAdvance | routine | D1541 | erproc 2 | Read, then R0 up one. |
| 42 | EA20 | $E77E | Errors::ReadAndAdvance::Done | local | D1541 | erproc 1 | Returns. |
| 43 | ATNIRQ | $E853 | Serial::AtnInterrupt | routine | D1541 | irq 1 | The IRQ's ATN case: reads VIA 1's port A to clear CA1's flag, and sets ATNPND for the idle loop. |
| 44 | ATNSRV | $E85B | Serial::HandleAtn | routine | D1541 | serlistn 2, idlesf 1 | ATN: abandons what it was doing (the stack reset), releases CLK, pulls DATA and sets ATNA so the gate stops pulling it, and takes the command bytes: UNLISTEN, UNTALK, its talk or listen address, a secondary address (CLOSE for $Ex). |
| 45 | ATNS15 | $E87B | Serial::HandleAtn::WaitClockReleased | local | D1541 | seratn 1 | Until the computer releases CLK, or ATN ends. |
| 46 | ATN30 | $E884 | Serial::HandleAtn::NextCommand | local | D1541 | seratn 1 | A command byte, by ReceiveByte. |
| 47 | ATN35 | $E891 | Serial::HandleAtn::NotUnlisten | local | D1541 | seratn 1 | UNTALK? |
| 48 | ATN40 | $E89B | Serial::HandleAtn::NotUntalk | local | D1541 | seratn 1 | TLKADR: TLKACT set, LSNACT clear. |
| 49 | ATN45 | $E8A9 | Serial::HandleAtn::NotTalk | local | D1541 | seratn 1 | LSNADR: LSNACT set, TLKACT clear. |
| 50 | ATN50 | $E8B7 | Serial::HandleAtn::NotListen | local | D1541 | seratn 1 | A secondary address ($60-$7F, $E0-$FF): ORGSA = it, SA its low nybble; $Ex closes the file. |
| 51 | ATN95 | $E8D2 | Serial::HandleAtn::StillAtn | local | D1541 | seratn 2 | ATN still on: the next command. |
| 52 | ATNS20 | $E8D7 | Serial::HandleAtn::AtnEnded | entry | D1541 | seratn 2, serlistn 1 | ATN over (CheckAtn comes here): ATNMOD and ATNA clear, then Listen, Talk, or the lines released. |
| 53 | ATN100 | $E8ED | Serial::HandleAtn::NotListening | local | D1541 | seratn 1 | Talking: releases DATA, pulls CLK, and Talk. |
| 54 | ATN110 | $E8FA | Serial::HandleAtn::ToBusError | local | D1541 | seratn 1 | On to BusError. |
| 55 | ATN120 | $E8FD | Serial::HandleAtn::NotForUs | local | D1541 | seratn 1 | Not a command for this drive: only ATNA set, so DATA is released and the computer can see no device answers. |
| 56 | ATN122 | $E902 | Serial::HandleAtn::WaitAtnEnd | local | D1541 | seratn 4 | Until ATN ends. |
| 57 | TALK | $E909 | Serial::Talk | routine | D1541 | seratn 1, sertalk 1 | The drive as talker: sends the read channel's bytes, each with GET's next, the last with EOI, until ATN; returns at once if SA has no channel ready to talk. |
| 58 | TALK1 | $E90F | Serial::Talk::NextByte | local | D1541 | sertalk 1 | Each byte: CHNRDY bit 7, ready to talk? |
| 59 | NOTLK | $E915 | Serial::Talk::NotReady | local | D1541 | sertalk 1 | Returns. |
| 60 | TLK05 | $E916 | Serial::Talk::ReadyToSend | local | D1541 | sertalk 1 | Releases CLK; if DATA is already released then, it takes the EOI handshake whatever the channel says (the listing's verify-error fix). |
| 61 | TALK2 | $E925 | Serial::Talk::WaitListener | local | D1541 | sertalk 1 | Until the listener releases DATA; EOI if CHNRDY's EOI bit is clear. |
| 62 | TLK02 | $E937 | Serial::Talk::EoiReleased | local | D1541 | sertalk 2 | EOI: waits for DATA released... |
| 63 | TLK03 | $E941 | Serial::Talk::EoiAcknowledged | local | D1541 | sertalk 1 | ...and pulled again: the listener has seen the EOI. |
| 64 | NOEOI | $E94B | Serial::Talk::WaitReady | local | D1541 | sertalk 2 | Pulls CLK and waits for DATA released: ready for the byte. |
| 65 | ISR01 | $E95C | Serial::Talk::NextBit | local | D1541 | sertalk 1 | Each bit, low first: DATA must be released, or BusError. |
| 66 | ISR02 | $E963 | DROP | local | D1541 | none | Not referenced: the bit from CHNDAT (Q8). |
| 67 | ISRHI | $E973 | Serial::Talk::BitOne | local | D1541 | sertalk 1 | A 1: DATA released. |
| 68 | ISRCLK | $E976 | Serial::Talk::ClockBit | local | D1541 | sertalk 1 | Releases CLK for the bit, waits 40 µs more (SlowDown) when SerialNoDelay is 0, the VIC-20's speed, then pulls CLK and releases DATA (the 1540 differs, Q7). |
| 69 | ISR03 | $E980 | Serial::Talk::EndBit | local | D1541 | sertalk 1 | Ends the bit: PullClockAndReleaseData, so the listener sees CLK pulled with the bit on DATA. |
| 70 | ISR04 | $E987 | Serial::Talk::WaitAccepted | local | D1541 | sertalk 1 | Until the listener pulls DATA: the byte is taken; then GET's next byte. |
| 71 | FRMERX | $E999 | Serial::Talk::ToBusError | local | D1541 | sertalk 1 | On to BusError. |
| 72 | DATHI | $E99C | Serial::ReleaseData | routine | D1541 | serlistn 2, seratn 1, sertalk 1, vector 1 | Lets DATA go high: DATOUT clear in VIA 1's port B. |
| 73 | DATLOW | $E9A5 | Serial::PullData | routine | D1541 | serlistn 2, seratn 1, sertalk 1 | Pulls DATA low: DATOUT set. |
| 74 | CLKLOW | $E9AE | Serial::PullClock | routine | D1541 | seratn 1, sertalk 1, vector 1 | Pulls CLK low: CLKOUT set. |
| 75 | CLKHI | $E9B7 | Serial::ReleaseClock | routine | D1541 | sertalk 2, seratn 1 | Lets CLK go high: CLKOUT clear. |
| 76 | DEBNC | $E9C0 | Serial::ReadLines | routine | D1541 | sertalk 8, serlistn 4 | A = VIA 1's port B, read until two reads agree (DATIN, CLKIN and ATN set while their lines are pulled). |
| 77 | ACPTR | $E9C9 | Serial::ReceiveByte | routine | D1541 | seratn 1, serlistn 1 | A byte from the talker, as the kernal's ACPTR: A = it; EOIFLG = 0 at EOI. Checks ATN at each wait. |
| 78 | ACP00A | $E9CD | Serial::ReceiveByte::WaitForTalker | local | D1541 | serlistn 1 | Until the talker releases CLK; then releases DATA and goes to ReceiveBytePatch to start the 256 µs timer. |
| 79 | ACP00 | $E9DF | Serial::ReceiveByte::WaitForClock | entry | D1541 | serlistn 1, vector 1 | Until CLK is pulled, or VIA 1's timer 1 runs out, which is EOI. |
| 80 | ACP00B | $E9F2 | Serial::ReceiveByte::Eoi | local | D1541 | serlistn 1 | EOI: acknowledges it by pulsing DATA... |
| 81 | ACP02 | $E9F7 | Serial::ReceiveByte::EoiPulse | local | D1541 | serlistn 1 | ...for a short count... |
| 82 | ACP02A | $E9FD | Serial::ReceiveByte::WaitClockAfterEoi | local | D1541 | serlistn 1 | ...waits for CLK pulled, and EOIFLG = 0. |
| 83 | ACP01 | $EA0B | Serial::ReceiveByte::WaitClockHigh | local | D1541 | serlistn 1 | The same address as ACP03: one local, with ACP01 in its Also: (Q2). |
| 84 | ACP03 | $EA0B | Serial::ReceiveByte::WaitClockHigh | local | D1541 | serlistn 2 | Each bit is taken as CLK is released, DATA in the same read (since -02, with three NOPs left; -01 differs, Q7). |
| 85 | ACP03A | $EA1A | Serial::ReceiveByte::WaitClockLow | local | D1541 | serlistn 1 | And CLK pulled again; after eight, pulls DATA to accept the byte. |
| 86 | LISTEN | $EA2E | Serial::Listen | routine | D1541 | seratn 1, serlistn 1 | The drive as listener: PUTs each byte received into SA's write channel until ATN; with no channel ready to listen, and not an OPEN ($Fx), BusError. |
| 87 | LSN15 | $EA39 | Serial::Listen::NotWriting | local | D1541 | serlistn 1 | No write channel: an OPEN's name? |
| 88 | LSN30 | $EA44 | Serial::Listen::NextByte | local | D1541 | serlistn 2 | A byte, PUT. |
| 89 | FRMERR | $EA4E | Serial::BusError | entry | D1541 | sertalk 1 | The same address as ILERR: in its Also: (Q2). |
| 90 | ILERR | $EA4E | Serial::BusError | routine | D1541 | seratn 1, serlistn 1 | Releases DATA, CLK and ATNA (VIA 1's port B = 0) and goes to the idle loop. |
| 91 | ITERR | $EA4E | Serial::BusError | entry | D1541 | none | The same address as ILERR: in its Also: (Q2). |
| 92 | ATNLOW | $EA56 | DROP | local | D1541 | none | A JMP to HandleAtn that nothing reaches: kept, unreached, with the name in prose (Q8). |
| 93 | TSTATN | $EA59 | Serial::CheckAtn | routine | D1541 | sertalk 6, serlistn 4 | In ATN mode (ATNMOD), returns while ATN is on and goes to AtnEnded when it ends; otherwise returns unless ATN is on, then HandleAtn. |
| 94 | TSTRTN | $EA62 | Serial::CheckAtn::Done | local | D1541 | serlistn 1 | Returns. |
| 95 | TSTA50 | $EA63 | Serial::CheckAtn::NotAtnMode | local | D1541 | serlistn 1 | Not in ATN mode: has ATN come? |
| 96 | TATN20 | $EA6B | Serial::CheckAtn::ToAtnEnded | local | D1541 | serlistn 1 | On to HandleAtn::AtnEnded. |
| 97 | PEZRO | $EA6E | Startup::BlinkFault | routine | D1541 | dskintsf 3 | The self-test's failure: blinks the LEDs the fault's number of times, pauses and repeats, for ever: once for zero page (here, X = 0), twice the upper ROM, three times the lower, four the RAM. The count is kept in the stack pointer, since RAM may be bad. |
| 98 | PERR | $EA71 | Startup::BlinkFault::Numbered | entry | D1541 | dskintsf 1 | X = TEMP, the failed test's number; PEZRO's `LDX #0` is followed by a `.byte $2C` (BIT) that skips this `LDX TEMP`, as K-P3-Q4 documents for the kernal. |
| 99 | PE20 | $EA74 | Startup::BlinkFault::Again | local | D1541 | dskintsf 1 | The count again. |
| 100 | PE30 | $EA75 | Startup::BlinkFault::Blink | local | D1541 | dskintsf 1 | Both LEDs on, through BlinkFaultPatch. |
| 101 | REA7D | $EA7D | Startup::BlinkFault::LedsLit | entry | D1541 | vector 1 | Where BlinkFaultPatch returns: waits with the LEDs lit. |
| 102 | PD10 | $EA7E | Startup::BlinkFault::OnOuter | local | D1541 | dskintsf 1 | 256 times... |
| 103 | PD20 | $EA7F | Startup::BlinkFault::OnInner | local | D1541 | dskintsf 1 | ...256 counts. |
| 104 | PE40 | $EA8E | Startup::BlinkFault::Pause | local | D1541 | dskintsf 1 | The LEDs off: waits, and after the last blink waits three times more. |
| 105 | PD11 | $EA8F | Startup::BlinkFault::OffOuter | local | D1541 | dskintsf 1 | 256 times... |
| 106 | PD21 | $EA90 | Startup::BlinkFault::OffInner | local | D1541 | dskintsf 1 | ...256 counts. |
| 107 | DSKINT | $EAA0 | Startup::Reset | routine | D1541 | vector 1 | The reset vector's target (and UJ's): interrupts off, binary mode, ResetPatch; tests zero page, both ROMs' checksums and RAM to $07FF, then sets the drive up (Initialize) and falls into the idle loop. |
| 108 | DKIT10 | $EAA7 | Startup::Reset::SelfTest | entry | D1541 | vector 1 | Where ResetPatch returns: the self-test. |
| 109 | PU10 | $EAAC | Startup::Reset::FillZeroPage | local | D1541 | dskintsf 1 | Each zero-page byte = its address. |
| 110 | PU20 | $EAB2 | Startup::Reset::CheckZeroPageByte | local | D1541 | dskintsf 1 | Each byte: still its address? |
| 111 | PU30 | $EAB7 | Startup::Reset::CountUp | local | D1541 | dskintsf 1 | Incremented 256 times, it must come back; then zeroed, it must read 0. |
| 112 | RM10 | $EAC9 | Startup::Reset::TestRom | local | D1541 | dskintsf 1 | An 8 KB ROM, from its top: the bytes summed with each carry added in must equal its first page, $E0 then $C0 (UpperRomChecksum makes it so). |
| 113 | RT10 | $EAD5 | Startup::Reset::NextPage | local | D1541 | dskintsf 1 | Each page, downwards. |
| 114 | RT20 | $EAD7 | Startup::Reset::AddByte | local | D1541 | dskintsf 1 | Each byte. |
| 115 | CR20 | $EAEA | DROP | local | D1541 | none | Not referenced: the RAM test's start (Q8). |
| 116 | CR30 | $EAEC | DROP | local | D1541 | none | Not referenced (Q8). |
| 117 | RAMTST | $EAF0 | DROP | local | D1541 | none | Not referenced (Q8). |
| 118 | RA10 | $EAF2 | Startup::Reset::FillRam | local | D1541 | dskintsf 2 | Pages 1-7, each byte its low address plus its page. |
| 119 | RA30 | $EB02 | Startup::Reset::CheckRamPage | local | D1541 | dskintsf 1 | Each page, downwards... |
| 120 | RA40 | $EB04 | Startup::Reset::CheckRamByte | local | D1541 | dskintsf 1 | ...each byte its pattern, then its inverse, then left 0. |
| 121 | PERR2 | $EB1F | Startup::Reset::ToBlinkFault | local | D1541 | dskintsf 3 | On to BlinkFault::Numbered. |
| 122 | DIAGOK | $EB22 | Startup::Reset::Initialize | entry | D1541 | dskintsf 3 | The tests passed (and VNMI's target, so Reinitialize comes here): the stack, the LEDs off, ATN's interrupt on VIA 1's CA1, TLKADR and LSNADR from the jumpers on PB5 and PB6 ($48 and $28 for device 8), BUFTAB, the channels and buffers free, the command and error channels, the user table, the LRU table, the controller (CNTINT), VNMI, SECINC, REVCNT, message 73, the bus lines released, and BOOT. |
| 123 | INTTAB | $EB4B | DROP | local | D1541 | none | Not referenced: BUFTAB's set-up (Q8). |
| 124 | INTT1 | $EB4F | Startup::Reset::NextBuffer | local | D1541 | dskintsf 1 | Each buffer's pointer, page from BufferPages; then the command and error buffers'. |
| 125 | DSKIN1 | $EB76 | Startup::Reset::ClearChannelTable | local | D1541 | dskintsf 1 | LINTAB's entries $FF: no secondary address has a channel. |
| 126 | DSKIN2 | $EB7E | Startup::Reset::FreeBuffers | local | D1541 | dskintsf 1 | Each channel's BUF0, BUF1 and SS $FF: no buffer. |
| 127 | SETERR | $EBD5 | DROP | local | D1541 | none | Not referenced: message 73 and the bus's set-up, which the revisions change (a comment names it, Q7, Q8). |
| 128 | IDLE | $EBE7 | Idle::Loop | routine | D1541 | erproc 1, seratn 1, serlistn 1 | Releases CLK, DATA and ATNA, runs a waiting command (CMDWAT: PARSXQ), then loops: HandleAtn when ATNPND is set; the activity LED on while a file is open or a job runs; the error LED's flashing. Reset falls into it. |
| 129 | IDL1 | $EBFF | Idle::Loop::NextPass | local | D1541 | idlesf 2 | Each pass: ATN pending? |
| 130 | IDL01 | $EC07 | Idle::Loop::CountActive | local | D1541 | idlesf 1 | TEMP and TEMP+1 count each drive's open files and jobs. |
| 131 | IDL2 | $EC12 | Idle::Loop::NextChannel | local | D1541 | idlesf 1 | Each LINTAB entry: a file open on which drive (LSTJOB)? |
| 132 | IDL3 | $EC2B | Idle::Loop::SkipChannel | local | D1541 | idlesf 1 | The next. |
| 133 | IDL4 | $EC31 | Idle::Loop::NextJob | local | D1541 | idlesf 1 | Each job still running, by its drive bit. |
| 134 | IDL5 | $EC3B | Idle::Loop::SkipJob | local | D1541 | idlesf 1 | The next; then drive 0: active, its channels closed (CLDCHN) if WPSW is set. |
| 135 | IDL6 | $EC58 | Idle::Loop::LightDrive0 | local | D1541 | idlesf 1 | LED0 on. |
| 136 | IDL7 | $EC5C | Idle::Loop::Drive1 | local | D1541 | idlesf 1 | Drive 1, as drive 0 (LED1 is 0). |
| 137 | IDL8 | $EC69 | Idle::Loop::LightDrive1 | local | D1541 | idlesf 1 | LED1 on. |
| 138 | IDL9 | $EC6D | Idle::Loop::CheckFlashing | local | D1541 | idlesf 1 | DRVNUM back; flashing while ERWORD is set (its $80 test is never true, Q10). |
| 139 | IDL10 | $EC81 | Idle::Loop::Timing | local | D1541 | idlesf 1 | Each count waits for VIA 1's timer 1 (TIMER1) to fall below $8000, about 8 ms from $A0xx. |
| 140 | IDL11 | $EC8B | Idle::Loop::CountDown | local | D1541 | idlesf 1 | ERWORD down one; at 0 the LED toggles (ERLED) and the count starts again at 16. |
| 141 | IDL12 | $EC98 | Idle::Loop::SetLeds | local | D1541 | idlesf 3 | Writes LEDPRT, and the next pass. |
| 142 | KILLP | $F258 | Commands::DisableProtection | routine | D1541 | memrw 1, block 1, utlodr 1 | A Commands routine: called before running code in the drive; a stub (RTS), its signal to the controller commented out (Q9). |
| 143 | DIRTRK | $FE85 | DirectoryTrack | table | D1541 | tstfnd 5, frets 3, lookup 2, rename 1, tst2 1, open 1, close 1, verdir 1, new 1 | 18: the directory's and the BAM's track. |
| 144 | BAMSIZ | $FE86 | BamEntrySize | table | D1541 | tstfnd 1 | 4: the BAM's bytes for each track. |
| 145 | MAPOFF | $FE87 | BamOffset | table | D1541 | none | 4: where the BAM starts in its sector; nothing reads it (Q4). |
| 146 | DSKNAM | $FE88 | DiskNameOffset | table | D1541 | trnsfr 1, new 1 | $90: the disk name's offset in the BAM sector. |
| 147 | CMDTBL | $FE89 | CommandLetters | table | D1541 | parsex 1, romtblsf 1 | The commands' letters, VIDMBUP&CRSN; the parser's command number is the index. |
| 148 | CJUMPL | $FE95 | CommandRoutinesLow | table | D1541 | parsex 1, romtblsf 1 | Each command's routine, low bytes. |
| 149 | CJUMPH | $FEA1 | CommandRoutinesHigh | table | D1541 | parsex 1, romtblsf 1 | And high bytes. |
| 150 | MODLST | $FEB2 | FileModes | table | D1541 | open 1, romtblsf 1 | OPEN's modes: R, W, A, M. |
| 151 | TPLST | $FEB6 | OpenTypeLetters | table | D1541 | open 1 | The types OPEN takes: D, S, P, U, L. |
| 152 | TYPLST | $FEBB | TypeFirstLetters | table | D1541 | setdrv 1, trnsfr 1, romtblsf 1 | The types' names' first letters, DSPUR (DEL, SEQ, PRG, USR, REL)... |
| 153 | TP1LST | $FEC0 | TypeSecondLetters | table | D1541 | trnsfr 1 | ...second, EERSE... |
| 154 | TP2LST | $FEC5 | TypeThirdLetters | table | D1541 | trnsfr 1 | ...and third, LQGRL. |
| 155 | LEDMSK | $FECA | LedMasks | table | D1541 | leds 1, jobssf 1 | Each drive's LED bit: LED0, LED1. |
| 156 | ER00 | $FECC | BitZero | table | D1541 | nulbuf 1 | 0: BIT clears N and V and sets Z. |
| 157 | ER0 | $FECD | BitNeither | table | D1541 | ssutil 1, sstest 1 | $3F: BIT clears N and V. |
| 158 | ER1 | $FECE | BitOverflow | table | D1541 | ssutil 1, sstest 1 | $7F: V set, N clear. |
| 159 | ER2 | $FECF | BitNegative | table | D1541 | sstest 1 | $BF: N set, V clear. |
| 160 | ER3 | $FED0 | BitBoth | table | D1541 | sstest 1 | $FF: N and V set. |
| 161 | NUMSEC | $FED1 | SectorsPerTrack | table | D1541 | tstfnd 1, lcccntrl 1 | Each zone's sectors: 17 for tracks 31-35, 18 for 25-30, 19 for 18-24, 21 for 1-17. |
| 162 | VERNUM | $FED5 | FormatType | table | D1541 | new 3, jobssf 1 | FM4040, A: the format NEW writes and a disk's header must have. |
| 163 | NZONES | $FED6 | ZoneCount | table | D1541 | tstfnd 1 | 4 zones. |
| 164 | MAXTRK | $FED7 | TrackLimit | table | D1541 | jobssf 2, tstfnd 2, block 1, map 1 | 36: one past the last track; ZoneLimits' first byte (Q2). |
| 165 | TRKNUM | $FED7 | ZoneLimits | table | D1541 | tstfnd 1, lcccntrl 1 | Each zone's first track past it: 36, 31, 25, 18, searched down to find a track's zone. |
| 166 | OFFSET | $FEDB | RecoveryOffsets | table | D1541 | jobssf 3 | The head's steps for a job's retries, 1, -1, -1, 1, ended by 0. |
| 167 | BUFIND | $FEE0 | BufferPages | table | D1541 | ssutil 4, trnsfr 1, block 1, tst4 1, close 1, dskintsf 1, map 1 | Each buffer's page, $03-$07, by its number (a sixth byte repeats $07). |
| 168 | ECHKSM | $FEE6 | Startup::UpperRomChecksum | table | D1541 | none | The byte that makes the $E000 ROM's sum come out at $E0; each revision has its own (Q7). |
| 169 | NMI | $FEE7 | Startup::Reinitialize | routine | D1541 | vector 1 | JMP (VNMI): VNMI holds Reset::Initialize, so a plain UI re-initializes the drive without the self-test; the 1540's NMI vector points here (Q5). |
| 170 | PEA7A | $FEEA | Startup::BlinkFaultPatch | routine | D1541 | dskintsf 1 | The power-on patch, the same in every build (vector.src's first): lights the LEDs and sets VIA 2's port B direction (LEDOUT) so the LED is an output before CNTINT has run, and back to BlinkFault::LedsLit (Q6). |
| 171 | SLOWD | $FEF3 | Serial::SlowDown | routine | D1541 | sertalk 1 | About 40 µs more for each bit sent at the VIC-20's speed; X kept, A lost. |
| 172 | SLOWE | $FEF6 | Serial::SlowDown::Wait | local | D1541 | vector 1 | Five counts. |
| 173 | CLKDAT | $FEFB | Serial::PullClockAndReleaseData | routine | D1541 | sertalk 1 | Ends a bit: PullClock, then ReleaseData. |
| 174 | NNMI | $FF01 | Startup::Nmi | routine | D1541 | vector 1 | The NMI vector's target, which UI reaches through the user table: UI- sets SerialNoDelay nonzero (the 64's speed), UI+ zero (the VIC-20's), and UI alone goes to `Startup::Reinitialize`. |
| 175 | NNMI10 | $FF0D | Startup::Nmi::SetSpeed | local | D1541 | vector 1 | SerialNoDelay = A. |
| 176 | PATCH5 | $FF10 | Startup::ResetPatch | routine | D1541 | dskintsf 1 | -05's fix: VIA 1's port A all outputs, then port B = $02 and its directions set, so CLK is released and DATA pulled during the self-test (the comment says the clock); back to Reset::SelfTest (Q6, Q10). |
| 177 | PATCH6 | $FF20 | Serial::ReceiveBytePatch | routine | D1541 | serlistn 1, vector 1 | -05's fix to EOI's timing: waits until DATA reads released, every listener ready, before starting the 256 µs timer; back to ReceiveByte::WaitForClock. |
| 178 | UBLOCK | $FFEA | UserCommandVectors | table | D1541 | block 2 | The user commands' addresses, U1 and U2 (UBLKRD, UBLKWT), U3-U8 into buffer 2; U9 to U; read on into the processor's vectors (Q5). |
| 179 | ETEND | $E60A | Errors::MessagesEnd | table | D1541 | erproc 2 | The end of Messages, CopyMessage's bound; shares `$E60A` with ERROR (JobError), which owns the address (Q3). |
| 180 | STRUCT | $FEA5 | PATTERN_ORIGIN | constant | D1541 | parsex 1, romtblsf 1 | The parsed commands' patterns (copy, rename, scratch, new, and LOAD's at LDCMD), an equate, not a table: `CommandPatterns - 8`, a constant (`PATTERN_ORIGIN`), where `CommandPatterns` is the table label at `$FEAD`, which the conversion adds (it is CJUMPH's bytes `$FEA1-$FEAC` before it); so the command's number indexes the table (copy is 8, LOAD `Commands::LOAD_STRUCTURE`, 12): each byte says whether a pattern, more than one file, a default drive and a file name are allowed (Q4). |
