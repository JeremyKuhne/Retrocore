# VIC-20 kernal rename table

The rename table for the VIC-20's kernal, step 3 of [the method](../ConvertingSources.md): drafted for the owner's
review in parts (decision K3 of the log, [Vic20.md](Vic20.md), which also has the documents and the inventory), and
complete, all seven parts settled (K11). Each part opens with its questions, each with a recommendation; the rows
follow the recommendations, and give the names the source has.

The columns:

- **#**: the row's number in its part, for reference in reviews.
- **Old**: the name in Commodore's listing (KV20).
- **Address**: where the listing, assembled, puts it in the 901486-06 kernal (or a constant's value).
- **New**: the source's name: a top-level name, a scope member (`Tape::Parity`), a constant (`TAPE_DATA`), or
  DROP, an equate the code never uses, left out and named in prose where the layout is described.
- **Kind**: routine (a `.proc`), entry (a label other code enters, listed in its routine's `Entry:`), local,
  location, table or constant.
- **Documents (checked)**: the documents checked to give the old name for this address, by key: the row's `Also:`
  entries. "Spelling only" lists documents that spell the name but not by its address; "other names here" lists a
  document's other names for the address, which go in the same `Also:`.
- **Used in**: the listing's files that use the name, with how many lines: what decides its scope.
- **Reason**: what it holds, from the listing's comments, *Mapping the VIC* and the code; each is checked against
  the code again as it is converted.

## Part 1: the variables, the RAM vectors, the VIC, the VIAs and the constants

Accepted by the owner on 2026-11-25, with every question as recommended (K5).

### Questions

- K-P1-Q1. **The families.** The kernal's scopes: `Editor` (the screen editor and the keyboard scan), `Serial`
  (the serial bus), `Tape`, `Rs232`, `Channels` (OPEN, CLOSE, the channel selection and the character I/O that
  dispatches by device, LOAD and SAVE), `Clock` (the jiffy clock), `Startup` (reset, the RAM test, the vectors'
  restore) and `Interrupts` (IRQ, NMI and BRK). Top level holds the jump-table entries (X14's `Kernal` names),
  the RAM vectors, the hardware, and the variables BASIC, programs or several families use (the ones *Mapping the
  VIC* calls handy locations). *Recommended.* The alternative is everything top level, as the listing has it.
- K-P1-Q2. **Bytes with two jobs.** Where the listing gives one byte two names for two families (`$A7` is the
  tape's SHCNL and RS-232's INBIT), each job gets its own name in its own family's scope, with its listing name in
  `Also:` (`Tape::ShortCountLow` and `Rs232::ReceivedBit`). A byte two families use under one name (T1 at
  `$9E`, used by the channel routines and the tape's) stays one top-level name. *Recommended.*
- K-P1-Q3. **The VIAs' registers.** Each register is a location named for the chip and the register
  (`Via1PortB`, `Via2Timer2High`), with the listing's D1ORB and *Mapping the VIC*'s VIA1PB in `Also:`; the two
  the keyboard uses by their own names (COLM, ROWS) are aliases for their job (`KeyboardColumns`, with
  `Inherit:`). The unused latches and shift registers stay, since the list describes the chip.
  *Recommended.* The alternative is a `.struct Via` with `Via1 + Via::PORT_B` in the code: one description of
  the chip, but longer operands and no home for each register's old names.
- K-P1-Q4. **The VIC's registers.** The kernal uses only their base (`VicRegisters`, VICREG). *Mapping the VIC*
  names each register `VICCR0`-`VICCRF`; the source defines each as a location named for what it sets
  (`VicHorizontalOrigin`, `VicScreenAndCharacters`) with MTV's name in `Also:`, so programs and the debugger
  can use them. These come in part 7 with the start-up's table, which loads them. *Recommended.*
- K-P1-Q5. **Spelling of colour.** `Colour` (`TextColour`, `ColourMemory`, `COLOUR_BLUE`), as the
  emulator's names have it (`ColourRam`); Commodore's and the references' `COLOR` stays in `Also:`.
  *Recommended.* The alternative is `Color`, as Commodore writes it.
- K-P1-Q6. **16 of the 22 unused declarations** (the PET monitor's registers at `$00-$08`, TMPC, FREKZP, BASZPT,
  M51AJB, USRCMD, LLEN2 and CR) are left out and named in prose. *Recommended*, as the conversion rules say for an
  equate a source never uses. The other six are VIA registers, kept by Q3.

### Rows

| # | Old | Address | New | Kind | Documents (checked) | Used in | Reason |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | PCH | $0000 | DROP | location | KV20, V20PRG | none | The PET monitor's saved PC, high; not used: $00-$08 is BASIC's in the VIC-20. |
| 2 | PCL | $0001 | DROP | location | KV20, V20PRG | none | As PCH: the PET monitor's saved PC, low; not used. |
| 3 | FLGS | $0002 | DROP | location | KV20 | none | As PCH: the PET monitor's saved status; not used. |
| 4 | ACC | $0003 | DROP | location | KV20 | none | As PCH: the PET monitor's saved A; not used. |
| 5 | XR | $0004 | DROP | location | KV20, V20PRG | none | As PCH: the PET monitor's saved X; not used. |
| 6 | YR | $0005 | DROP | location | KV20, V20PRG | none | As PCH: the PET monitor's saved Y; not used. |
| 7 | SP | $0006 | DROP | location | KV20, MTV, V20PRG | none | As PCH: the PET monitor's saved stack pointer; not used. |
| 8 | INVH | $0007 | DROP | location | KV20 | none | As PCH: the PET monitor's user IRQ vector; not used. |
| 9 | INVL | $0008 | DROP | location | KV20 | none | As PCH; not used. |
| 10 | STATUS | $0090 | IoStatus | location | KV20, MTV; spelling only: V20PRG | channelio:1, close:1, init:3, load:7, open:1, openchannel:2, serial2.1:1, tapecontrol:1 | The status of the last I/O, which BASIC's ST reads; every device's routines set its bits. |
| 11 | STKEY | $0091 | StopKeyRow | location | KV20, MTV | errorhandler:1, time:2 | The keyboard's bottom row as the jiffy clock last read it: $FE while STOP is down, which the STOP test checks. |
| 12 | SVXT | $0092 | Tape::TimingAdjust | location | KV20, MTV | read:4 | Reading: how far a dipole's time is from the timebase, which moves the timebase. |
| 13 | VERCK | $0093 | VerifyFlag | location | KV20, MTV | load:3, read:3, tapecontrol:1, tapefile:2 | 0 for LOAD, 1 for VERIFY: the tape's and the serial bus's load routines compare instead of store. |
| 14 | C3P0 | $0094 | Serial::CharacterWaiting | location | KV20; other names here: MTV spells it C3P0 (OCR: G3P0) | serial2.1:4 | Bit 7 set while a character waits in Serial::BufferedCharacter, sent when the next one comes (so the last can go with EOI). |
| 15 | BSOUR | $0095 | Serial::BufferedCharacter | location | KV20, MTV | serial2.1:5 | The character waiting to be sent on the serial bus. |
| 16 | SYNO | $0096 | Tape::BlockSync | location | KV20; spelling only: MTV | read:5 | Reading: set once 16 more short pulses than long have come (about 8 zero dipoles), block sync, between blocks. (Corrected by K-P4-Q1.) |
| 17 | XSAV | $0097 | SavedX | location | KV20, MTV | channelio:7, init:3 | X kept across CHRIN and CHROUT's device calls, and the RAM test's pointer. |
| 18 | LDTND | $0098 | OpenFileCount | location | KV20, MTV | clall:1, close:4, open:2 | How many files are open: the number of entries in the file tables, at most ten. |
| 19 | DFLTN | $0099 | InputDevice | location | KV20, MTV | channelio:2, clall:2, editor.1:2, openchannel:1, rs232inout:1 | The device CHRIN and GETIN read: 0 keyboard, 1 tape, 2 RS-232, 3 screen, 4-31 the serial bus. |
| 20 | DFLTO | $009A | OutputDevice | location | KV20, MTV | channelio:1, clall:2, editor.1:2, openchannel:1, rs232inout:1 | The device CHROUT writes: 3 screen, as InputDevice's numbers. |
| 21 | PRTY | $009B | Tape::Parity | location | KV20, MTV | read:4, write:3 | The parity of the byte being read or written. |
| 22 | DPSW | $009C | Tape::ByteMarkerSeen | location | KV20, MTV | read:3, tapecontrol:1 | Reading: set by the byte marker, so the byte is finished at the next timeout. (Corrected by K-P4-Q1.) |
| 23 | MSGFLG | $009D | MessageMode | location | KV20, MTV | errorhandler:1, init:1, load:1, messages:1, save:1, tapefile:1 | Which messages the kernal prints: bit 7 its control messages (SEARCHING, LOADING), bit 6 its error messages. |
| 24 | PTR1 | $009E | Tape::FirstPassErrors | location | KV20, MTV | read:5, tapecontrol:1 | Reading: how many errors the first copy of a block logged (an index into the bad-byte log at $0100). |
| 25 | T1 | $009E | Temporary1 | location | KV20; spelling only: MTV, V20PRG | channelio:4, tapefile:8 | A temporary that the channel routines and tape file routines use; shared, so top level. |
| 26 | TMPC | $009F | DROP | location | KV20 | none | A third name for $9F, not used. |
| 27 | PTR2 | $009F | Tape::SecondPassErrors | location | KV20, MTV | read:3, tapecontrol:1 | Reading: how many of the logged errors the second copy has corrected. |
| 28 | T2 | $009F | Tape::Temporary2 | location | KV20; spelling only: V20PRG | tapefile:6 | The tape file routines' second temporary (only they use it). |
| 29 | TIME | $00A0 | JiffyClock | location | KV20, MTV, V20PRG | kernal:1, time:16 | The time of day in jiffies, 1/60 second, three bytes, high first: BASIC's TI. The IRQ counts it; 24 hours wrap it to 0. |
| 30 | R2D2 | $00A3 | Serial::EndOfFile | location | KV20 | serial2.1:3 | Bit 7 set to send the next byte with EOI, as the last; the serial routines' flags. |
| 31 | PCNTR | $00A3 | Tape::BitCount | location | KV20, MTV | read:5, write:2 | Reading and writing: the bits left in the byte. |
| 32 | BSOUR1 | $00A4 | Serial::ReceivedByte | location | KV20 | serial2.1:2 | The byte coming in on the serial bus, a bit at a time. |
| 33 | FIRT | $00A4 | Tape::Dipole | location | KV20, MTV | read:4, write:2 | Reading and writing: which half of the bit's dipole is being timed. |
| 34 | COUNT | $00A5 | Serial::BitCount | location | KV20, MTV | serial2.1:7 | The bits left to send or receive, and the serial routines' countdowns. |
| 35 | CNTDN | $00A5 | Tape::SyncCountdown | location | KV20, MTV | write:3 | Writing: the countdown bytes still to write before a block. |
| 36 | BUFPT | $00A6 | Tape::BufferIndex | location | KV20 | channelio:3, open:1, tapecontrol:2 | The next byte in the tape buffer, for the channel routines' character reads and writes. |
| 37 | INBIT | $00A7 | Rs232::ReceivedBit | location | KV20, MTV; spelling only: V20PRG | rs232nmifile:1, rs232rcvr:5 | Receiving: the last bit sampled. |
| 38 | SHCNL | $00A7 | Tape::ShortCountLow | location | KV20 | read:4, write:2 | Writing: the leader's and trailer's short pulses still to write, low byte. Reading, the same byte is Tape::CopiesLeft. (Corrected by K-P4-Q1.) |
| 39 | BITCI | $00A8 | Rs232::ReceiveBitCount | location | KV20, MTV; spelling only: V20PRG | rs232nmifile:1, rs232rcvr:3 | Receiving: the bits still to come in the byte. |
| 40 | RER | $00A8 | Tape::ReadError | location | KV20 | read:4, write:2 | Reading: set when a byte has an error. Writing, the same byte is Tape::MarkerLongWritten. (Corrected by K-P4-Q1.) |
| 41 | RINONE | $00A9 | Rs232::WaitingForStart | location | KV20, MTV; spelling only: V20PRG | rs232rcvr:3 | Receiving: 1 while waiting for a start bit. |
| 42 | REZ | $00A9 | Tape::ZeroesCount | location | KV20 | read:5, write:2 | Reading: the zeroes counted, for block sync. Writing, the same byte is Tape::MarkerOneWritten. (Corrected by K-P4-Q1.) |
| 43 | RIDATA | $00AA | Rs232::ReceivedByte | location | KV20, MTV; spelling only: V20PRG | rs232rcvr:3 | Receiving: the byte the bits are shifted into. |
| 44 | RDFLG | $00AA | Tape::ReadMode | location | KV20 | read:7, tapecontrol:1 | Reading: which part of a block is being read (leader, data, end) and whether to store it. |
| 45 | RIPRTY | $00AB | Rs232::ReceivedParity | location | KV20, MTV; spelling only: V20PRG | rs232rcvr:3 | Receiving: the received byte's parity, as it accumulates. |
| 46 | SHCNH | $00AB | Tape::ShortCountHigh | location | KV20 | read:5, tapecontrol:1, tapefile:1, write:2 | Writing: the leader's count, high byte. After a load, the same byte is Tape::LoadChecksum. (Corrected by K-P4-Q1.) |
| 47 | SAL | $00AC | StartAddress | location | KV20, MTV | editor.2:10, read:7, save:2, write:3 | The start of the memory being loaded or saved, and the pointer that steps through it; the screen editor uses it for scrolling. |
| 48 | SAH | $00AD | StartAddressHigh | location | KV20 | editor.2:4, read:3, save:1, write:5 | StartAddress's high byte. |
| 49 | EAL | $00AE | EndAddress | location | KV20, MTV | editor.2:7, load:7, save:1, tapefile:4, write:1 | The end of the memory being loaded or saved; the screen editor uses it too. |
| 50 | EAH | $00AF | EndAddressHigh | location | KV20 | editor.2:4, load:5, save:1, tapefile:4, write:1 | EndAddress's high byte. |
| 51 | CMP0 | $00B0 | Tape::TimeCorrection | location | KV20 | read:7, tapecontrol:4 | Reading: the correction to the pulse timer for the tape's speed. |
| 52 | TEMP | $00B1 | Tape::Temporary | location | KV20 | read:12, tapecontrol:6 | Reading and writing: a temporary of the tape routines. |
| 53 | TAPE1 | $00B2 | TapeBuffer | location | KV20, MTV | channelio:3, init:2, load:6, open:1, tapefile:12 | A pointer to the tape buffer, $033C: the cassette routines use the buffer through it. |
| 54 | BITTS | $00B4 | Rs232::SendBitCount | location | KV20; spelling only: V20PRG | rs232trans:7 | Sending: the bits still to go out. |
| 55 | SNSW1 | $00B4 | Tape::SyncFound | location | KV20 | read:7, tapecontrol:1 | Reading: set once a block's sync has been found. |
| 56 | NXTBIT | $00B5 | Rs232::NextBit | location | KV20, MTV; spelling only: V20PRG | rs232nmifile:1, rs232trans:2 | Sending: the next bit to put on the line. |
| 57 | DIFF | $00B5 | Tape::BlockSyncSaved | location | KV20 | read:4 | Reading: a copy of BlockSync, kept between the bit routines. (Corrected by K-P4-Q1.) |
| 58 | RODATA | $00B6 | Rs232::SendByte | location | KV20, MTV; spelling only: V20PRG | rs232trans:2 | Sending: the byte being shifted out. |
| 59 | PRP | $00B6 | Tape::ByteErrors | location | KV20 | read:6 | Reading: the byte's error and zero count combined, which the byte handler checks. (Corrected by K-P4-Q1.) |
| 60 | FNLEN | $00B7 | FileNameLength | location | KV20, MTV | init:1, load:5, open:5, save:1, tapefile:2 | The current file name's length, which SETNAM sets. |
| 61 | LA | $00B8 | LogicalFile | location | KV20, MTV; spelling only: V20PRG | close:1, init:1, open:2 | The current logical file number, which SETLFS sets. |
| 62 | SA | $00B9 | SecondaryAddress | location | KV20; spelling only: MTV, V20PRG | close:3, init:1, load:4, open:6, openchannel:4, save:6 | The current secondary address, which SETLFS sets. |
| 63 | FA | $00BA | Device | location | KV20, MTV; spelling only: V20PRG | close:2, conkat:1, init:2, load:2, open:2, openchannel:2, save:3 | The current device number, which SETLFS sets. |
| 64 | FNADR | $00BB | FileName | location | KV20, MTV | init:2, load:1, open:2, tapefile:2 | A pointer to the current file name, which SETNAM sets. |
| 65 | ROPRTY | $00BD | Rs232::SendParity | location | KV20, MTV | rs232trans:5 | Sending: the parity of the byte going out. |
| 66 | OCHAR | $00BD | Tape::OutputCharacter | location | KV20 | read:6, write:8 | Reading and writing: the byte being read or written, a bit at a time. |
| 67 | FSBLK | $00BE | Tape::BlockCount | location | KV20, MTV | read:5, tapecontrol:1, write:3 | Reading and writing: which copy of the block is in progress (2, 1, then 0). |
| 68 | MYCH | $00BF | Tape::ByteBuffer | location | KV20, MTV | read:2 | Reading: the byte assembled from the bits. |
| 69 | CAS1 | $00C0 | CassetteMotorMode | location | KV20, MTV | editor.2:2, tapecontrol:1 | 0 while the IRQ may turn the motor on and off with the PLAY key; set while a tape routine runs it. |
| 70 | TMP0 | $00C1 | Startup::Pointer | location | KV20 | init:13 | The start-up's RAM test pointer (the listing's MEMUSS shares the byte with TMP2). |
| 71 | STAL | $00C1 | Tape::LoadAddress | location | KV20, MTV | load:1, read:1, save:1, tapefile:4 | The address a tape program loads at and a save starts from, low byte. |
| 72 | STAH | $00C2 | Tape::LoadAddressHigh | location | KV20 | load:1, read:1, save:1, tapefile:4 | Tape::LoadAddress's high byte. |
| 73 | MEMUSS | $00C3 | LoadAddress | location | KV20, MTV | load:10 | LOAD's address, kept while the header is read: the program's own or the one asked for. |
| 74 | TMP2 | $00C3 | Startup::Temporary | location | KV20 | init:4 | The start-up's second pointer, the RAM test's. |
| 75 | LSTX | $00C5 | Editor::LastKey | location | KV20, MTV | editor.2:2 | The keyboard matrix's code of the key down at the last scan, 64 for none: the repeat is timed against it. |
| 76 | NDX | $00C6 | KeyboardBufferCount | location | KV20, MTV | channelio:1, editor.1:4, editor.2:4, errorhandler:1 | How many characters are in the keyboard buffer, 0-10. |
| 77 | RVS | $00C7 | Editor::Reverse | location | KV20, MTV; spelling only: V20PRG | editor.1:4 | Non-zero while printing reversed characters (after RVS ON). |
| 78 | INDX | $00C8 | Editor::LineEnd | location | KV20, MTV | channelio:1, editor.1:3 | The column of the last character of the line being read from the screen. |
| 79 | LSXP | $00C9 | Editor::InputRow | location | KV20 | channelio:1, editor.1:3, editor.2:1 | The row the cursor was on when input started. |
| 80 | LSTP | $00CA | Editor::InputColumn | location | KV20 | channelio:1, editor.1:1 | The column the cursor was at when input started. |
| 81 | SFDX | $00CB | Editor::KeyDown | location | KV20, MTV | editor.2:4 | The matrix code of the key found by this scan, 64 for none. |
| 82 | BLNSW | $00CC | Editor::BlinkOff | location | KV20 | editor.1:2, editor.2:1 | 0 while the cursor blinks (input waits for a key). |
| 83 | BLNCT | $00CD | Editor::BlinkCountdown | location | KV20 | editor.1:1, editor.2:3 | Jiffies until the cursor changes, from 20. |
| 84 | GDBLN | $00CE | Editor::CharacterUnderCursor | location | KV20 | editor.1:1, editor.2:2 | The character the cursor covers, put back when it stops. |
| 85 | BLNON | $00CF | Editor::CursorShown | location | KV20 | editor.1:3, editor.2:2 | 1 while the cursor's reversed phase shows. |
| 86 | CRSW | $00D0 | Editor::InputFromScreen | location | KV20, MTV | channelio:1, editor.1:4 | Non-zero while CHRIN reads a line back from the screen; 0 waits for keys. |
| 87 | PNT | $00D1 | Editor::Line | location | KV20, MTV | editor.1:11, editor.2:8 | A pointer to the start of the cursor's line in screen memory. |
| 88 | PNTR | $00D3 | Editor::Column | location | KV20, MTV | channelio:1, editor.1:27, editor.2:2 | The cursor's column in its logical line, 0-87. |
| 89 | QTSW | $00D4 | Editor::QuoteMode | location | KV20, MTV | editor.1:8 | 1 inside quotes, where cursor and colour keys print as reversed characters. |
| 90 | LNMX | $00D5 | Editor::LineLength | location | KV20, MTV | channelio:1, editor.1:10, editor.3:1 | The logical line's last column: 21, 43, 65 or 87. |
| 91 | TBLX | $00D6 | Editor::Row | location | KV20, MTV | channelio:1, editor.1:21, editor.2:5 | The cursor's row, 0-22. |
| 92 | DATA | $00D7 | Editor::Character | location | KV20, MTV; spelling only: V20PRG | editor.1:7, read:3, write:4 | The character being printed; the tape routines use the byte for theirs too. |
| 93 | INSRT | $00D8 | Editor::Inserts | location | KV20, MTV | editor.1:7 | How many inserted spaces are still open, which print cursor keys as characters. |
| 94 | LDTB1 | $00D9 | Editor::LineLinks | table | KV20, MTV | editor.1:9, editor.2:13, editor.3:2 | Each row's screen page, with bit 7 clear for a row that continues the row above: the logical lines (23 used of 25). |
| 95 | LINTMP | $00F2 | Editor::LinkSave | location | KV20 | editor.2:7 | A row's link byte, kept while the links are moved. |
| 96 | USER | $00F3 | Editor::ColourLine | location | KV20, MTV; spelling only: V20PRG | editor.1:6, editor.2:6 | A pointer to the cursor's line in colour RAM. |
| 97 | KEYTAB | $00F5 | Editor::KeyTable | location | KV20, MTV | editor.2:6 | A pointer to the keyboard table for the shift keys down: unshifted, SHIFT, C= or CTRL. |
| 98 | RIBUF | $00F7 | Rs232::InputBuffer | location | KV20, MTV; spelling only: V20PRG | close:2, open:3, rs232inout:1, rs232rcvr:1 | A pointer to RS-232's 256-byte input buffer, which OPEN takes from the top of memory. |
| 99 | ROBUF | $00F9 | Rs232::OutputBuffer | location | KV20, MTV; spelling only: V20PRG | close:2, open:3, rs232inout:1, rs232trans:1 | A pointer to RS-232's 256-byte output buffer. |
| 100 | FREKZP | $00FB | DROP | location | KV20, MTV | none | Four bytes left free for programs ($FB-$FE); not used. Named in prose. |
| 101 | BASZPT | $00FF | DROP | location | KV20, MTV | none | $FF, BASIC's; not used by the kernal. |
| 102 | BAD | $0100 | Tape::BadBytes | table | KV20, MTV; spelling only: V20PRG | read:4 | Reading: the log of bytes the first copy got wrong, at the bottom of the stack page. |
| 103 | BUF | $0200 | InputBuffer | table | KV20, MTV | tapefile:1 | The 89-byte buffer BASIC reads lines into; the kernal uses only its page, as the lowest a tape buffer may be. |
| 104 | LAT | $0259 | FileNumbers | table | KV20, MTV; other names here: MTV: LOT | close:4, open:1 | Each open file's logical file number, ten entries. |
| 105 | FAT | $0263 | FileDevices | table | KV20, MTV | close:3, open:1 | Each open file's device number. |
| 106 | SAT | $026D | FileSecondaryAddresses | table | KV20, MTV | close:3, open:1 | Each open file's secondary address. |
| 107 | KEYD | $0277 | KeyboardBuffer | table | KV20, MTV | editor.1:4, editor.2:1 | The ten-character keyboard buffer the IRQ's scan fills. |
| 108 | MEMSTR | $0281 | MemoryStart | location | KV20, MTV | init:7 | The start of RAM for BASIC, which the start-up finds (MEMBOT reads and sets it). |
| 109 | MEMSIZ | $0283 | MemoryEnd | location | KV20, MTV; other names here: MTV: MEMHIGH | init:4 | The top of RAM, plus one (MEMTOP reads and sets it). |
| 110 | TIMOUT | $0285 | Serial::TimeoutFlag | location | KV20, MTV | init:1 | The serial bus's timeout switch, which SETTMO sets; the VIC-20's serial routines do not read it. |
| 111 | COLOR | $0286 | TextColour | location | KV20, MTV; spelling only: V20PRG | editor.1:5, editor.2:1 | The colour new characters are printed in: 6, blue, at start-up. |
| 112 | GDCOL | $0287 | Editor::ColourUnderCursor | location | KV20, MTV | editor.1:1, editor.2:2 | The colour of the character the cursor covers. |
| 113 | HIBASE | $0288 | ScreenPage | location | KV20, MTV | editor.1:4, editor.2:2, init:2 | The page the screen starts at: $1E unexpanded, $10 with RAM in block 1. |
| 114 | XMAX | $0289 | KeyboardBufferSize | location | KV20, MTV | editor.1:1, editor.2:1 | The most characters the keyboard buffer takes, 10. |
| 115 | RPTFLG | $028A | KeyRepeat | location | KV20, MTV | editor.2:1 | Which keys repeat: $80 all, $40 none, 0 the cursor keys, space and DEL. |
| 116 | KOUNT | $028B | Editor::RepeatInterval | location | KV20; spelling only: MTV | editor.1:1, editor.2:2 | Jiffies between repeats of a held key. |
| 117 | DELAY | $028C | Editor::RepeatDelay | location | KV20; spelling only: MTV, V20PRG | editor.1:1, editor.2:3 | Jiffies before a held key starts to repeat. |
| 118 | SHFLAG | $028D | ShiftKeys | location | KV20, MTV | editor.2:5 | The shift keys down: bit 0 SHIFT, bit 1 C=, bit 2 CTRL. |
| 119 | LSTSHF | $028E | Editor::LastShiftKeys | location | KV20, MTV | editor.2:2 | The shift keys at the last scan, so SHIFT with C= switches the character set once. |
| 120 | KEYLOG | $028F | KeyTableSetup | location | KV20, MTV | editor.1:2, editor.2:1 | The vector to the routine that picks the keyboard table for the shift keys; a program can put its own here. |
| 121 | MODE | $0291 | CaseSwitchLock | location | KV20; spelling only: MTV, V20PRG | editor.1:1, editor.2:1, editor.3:4 | 0 lets SHIFT with C= switch the character set; $80 locks it (CHR$(8) and CHR$(9)). |
| 122 | AUTODN | $0292 | Editor::ScrollDownOff | location | KV20, MTV | editor.1:3 | 0 lets a line insert scroll the screen down below it; non-zero turns that off. |
| 123 | M51CTR | $0293 | Rs232::Control | location | KV20, MTV; spelling only: V20PRG | open:2, rs232nmifile:1, rs232rcvr:1, rs232trans:2 | Like a 6551's control register: the baud rate, the word length and the stop bits, from OPEN's file name. |
| 124 | M51CDR | $0294 | Rs232::Command | location | KV20, MTV; spelling only: V20PRG | open:1, rs232inout:2, rs232rcvr:1, rs232trans:2 | Like a 6551's command register: parity, duplex and handshaking. |
| 125 | M51AJB | $0295 | DROP | location | KV20; spelling only: MTV, V20PRG | none | A non-standard baud rate's bit time; not used by the VIC-20's code. Named in prose. |
| 126 | RSSTAT | $0297 | Rs232::Status | location | KV20, MTV; spelling only: V20PRG | init:2, open:1, rs232rcvr:2, rs232trans:2 | RS-232's status bits, which ST reads for device 2. |
| 127 | BITNUM | $0298 | Rs232::WordBits | location | KV20, MTV; spelling only: V20PRG | open:1, rs232nmifile:1, rs232rcvr:1, rs232trans:1 | The bits in a word with its stop bit and parity, as OPEN works them out. |
| 128 | BAUDOF | $0299 | Rs232::BitTime | location | KV20, MTV, V20PRG | open:2, rs232inout:2, rs232nmifile:2 | The time of a bit, in timer counts, for the baud rate: two bytes. |
| 129 | RIDBE | $029B | Rs232::InputEnd | location | KV20, MTV; spelling only: V20PRG | open:1, rs232inout:1, rs232rcvr:2 | The index in the input buffer of the next byte to store. |
| 130 | RIDBS | $029C | Rs232::InputStart | location | KV20; spelling only: V20PRG | open:1, rs232inout:2, rs232rcvr:1 | The index in the input buffer of the next byte to read. |
| 131 | RODBS | $029D | Rs232::OutputStart | location | KV20, MTV; spelling only: V20PRG | open:1, rs232inout:1, rs232trans:2 | The index in the output buffer of the next byte to send. |
| 132 | RODBE | $029E | Rs232::OutputEnd | location | KV20, MTV; spelling only: V20PRG | open:1, rs232inout:2, rs232trans:1 | The index in the output buffer of the next byte to store. |
| 133 | IRQTMP | $029F | Tape::SavedIrq | location | KV20; spelling only: MTV | tapecontrol:4, write:2 | The IRQ vector, kept while the tape routines take the interrupt over. |
| 134 | CINV | $0314 | IrqVector | location | KV20, MTV; other names here: MTV spells it CINV (OCR: C1NV) | init:2, irqfile:1, tapecontrol:3, write:4 | The IRQ's RAM vector: the jiffy routine at $EABF. |
| 135 | CBINV | $0316 | BreakVector | location | KV20, MTV | irqfile:1 | The BRK instruction's RAM vector. |
| 136 | NMINV | $0318 | NmiVector | location | KV20, MTV | rs232nmifile:1 | The NMI's RAM vector: RESTORE and RS-232. |
| 137 | IOPEN | $031A | OpenVector | location | KV20, MTV | vectors:1 | OPEN's RAM vector, which the jump table's OPEN goes through. |
| 138 | ICLOSE | $031C | CloseVector | location | KV20, MTV | vectors:1 | CLOSE's RAM vector. |
| 139 | ICHKIN | $031E | SelectInputVector | location | KV20, MTV | vectors:1 | CHKIN's RAM vector. |
| 140 | ICKOUT | $0320 | SelectOutputVector | location | KV20, MTV | vectors:1 | CHKOUT's RAM vector. |
| 141 | ICLRCH | $0322 | ResetChannelsVector | location | KV20, MTV | vectors:1 | CLRCHN's RAM vector. |
| 142 | IBASIN | $0324 | CharacterInVector | location | KV20, MTV | vectors:1 | CHRIN's RAM vector. |
| 143 | IBSOUT | $0326 | CharacterOutVector | location | KV20, MTV | vectors:1 | CHROUT's RAM vector. |
| 144 | ISTOP | $0328 | TestStopKeyVector | location | KV20, MTV | vectors:1 | STOP's RAM vector. |
| 145 | IGETIN | $032A | GetInputVector | location | KV20, MTV | vectors:1 | GETIN's RAM vector. |
| 146 | ICLALL | $032C | CloseAllFilesVector | location | KV20, MTV | vectors:1 | CLALL's RAM vector. |
| 147 | USRCMD | $032E | DROP | location | KV20, MTV | none | A user vector the kernal never uses ($032E). Named in prose. |
| 148 | ILOAD | $0330 | LoadVector | location | KV20, MTV | load:1 | LOAD's RAM vector. |
| 149 | ISAVE | $0332 | SaveVector | location | KV20, MTV | save:1 | SAVE's RAM vector. |
| 150 | TBUFFR | $033C | TapeBufferArea | table | KV20, MTV | init:2 | The 192-byte tape buffer at $033C, for headers and data files. |
| 151 | VICSCN | $1000 | ScreenMemory | location | KV20 | editor.3:1 | The screen's usual place with RAM in block 1, $1000 (the editor works from ScreenPage). |
| 152 | VICREG | $9000 | VicRegisters | location | KV20 | editor.1:4, editor.2:2, editor.3:4 | The VIC's 16 registers at $9000, which the start-up loads from its table. |
| 153 | D1ORB | $9110 | Via1PortB | location | KV20; other names here: MTV: VIA1PB | close:1, editor.1:2, open:1, rs232inout:9, rs232nmifile:2 | VIA 1's port B: the user port, RS-232's lines. |
| 154 | D1ORAH | $9111 | Via1PortAHandshake | location | KV20; other names here: MTV: VIA1PA1 | rs232nmifile:1 | VIA 1's port A, with CA1's handshake (reading clears the RESTORE flag). |
| 155 | D1DDRB | $9112 | Via1DirectionB | location | KV20 | init:1, open:1 | VIA 1's port B direction register. |
| 156 | D1DDRA | $9113 | Via1DirectionA | location | KV20 | init:1 | VIA 1's port A direction register. |
| 157 | D1T1L | $9114 | Via1Timer1 | location | KV20 | rs232inout:1, rs232nmifile:1, tapecontrol:1 | VIA 1's timer 1, low byte: RS-232's send timer. |
| 158 | D1T1H | $9115 | Via1Timer1High | location | KV20 | rs232inout:1 | VIA 1's timer 1, high byte: writing starts it. |
| 159 | D1T1LL | $9116 | Via1Timer1Latch | location | KV20 | none | VIA 1's timer 1 latch, low byte (not used by the kernal). |
| 160 | D1T1LH | $9117 | Via1Timer1LatchHigh | location | KV20 | none | VIA 1's timer 1 latch, high byte (not used). |
| 161 | D1T2L | $9118 | Via1Timer2 | location | KV20 | rs232nmifile:3 | VIA 1's timer 2, low byte: RS-232's receive timer. |
| 162 | D1T2H | $9119 | Via1Timer2High | location | KV20 | rs232nmifile:3 | VIA 1's timer 2, high byte. |
| 163 | D1SR | $911A | Via1Shift | location | KV20 | none | VIA 1's shift register (not used). |
| 164 | D1ACR | $911B | Via1AuxiliaryControl | location | KV20 | init:1 | VIA 1's auxiliary control register. |
| 165 | D1PCR | $911C | Via1PeripheralControl | location | KV20 | close:1, editor.2:3, init:1, open:1, rs232nmifile:1, tapecontrol:2, write:2 | VIA 1's peripheral control register: CA2 runs the cassette motor, CB2 is RS-232's send line. |
| 166 | D1IFR | $911D | Via1InterruptFlags | location | KV20 | rs232nmifile:1 | VIA 1's interrupt flags. |
| 167 | D1IER | $911E | Via1InterruptEnable | location | KV20 | close:1, editor.2:1, init:2, rs232inout:9, rs232nmifile:6, rs232rcvr:2, rs232trans:1 | VIA 1's interrupt enable register: RESTORE and RS-232's NMIs. |
| 168 | D1ORA | $911F | Via1PortA | location | KV20; other names here: MTV: VIA1PA2 | editor.2:1, init:1, serial2.1:14, tapecontrol:2 | VIA 1's port A, without handshake: the serial bus's lines, the joystick and the cassette's keys. |
| 169 | COLM | $9120 | KeyboardColumns | location | KV20 | editor.2:6, time:2 | VIA 2's port B as the keyboard's column outputs (an alias of Via2PortB). |
| 170 | D2ORB | $9120 | Via2PortB | location | KV20; other names here: MTV: VIA2PB | open:1, rs232trans:1, write:3 | VIA 2's port B: the keyboard's columns, the cassette's write line on PB3. |
| 171 | ROWS | $9121 | KeyboardRows | location | KV20 | editor.2:4, time:1 | VIA 2's port A as the keyboard's row inputs (an alias of Via2PortAHandshake). |
| 172 | D2ORAH | $9121 | Via2PortAHandshake | location | KV20; other names here: MTV: VIA2PA1 | read:1 | VIA 2's port A, with CA1's handshake (the cassette's read line). |
| 173 | D2DDRB | $9122 | Via2DirectionB | location | KV20 | init:1 | VIA 2's port B direction register. |
| 174 | D2DDRA | $9123 | Via2DirectionA | location | KV20 | init:1 | VIA 2's port A direction register. |
| 175 | D2T1L | $9124 | Via2Timer1 | location | KV20 | editor.2:1, init:1, tapecontrol:1 | VIA 2's timer 1, low byte: the jiffy interrupt, and the tape's write timer. |
| 176 | D2T1H | $9125 | Via2Timer1High | location | KV20 | init:1, tapecontrol:1 | VIA 2's timer 1, high byte. |
| 177 | D2T1LL | $9126 | Via2Timer1Latch | location | KV20 | none | VIA 2's timer 1 latch, low byte (not used). |
| 178 | D2T1LH | $9127 | Via2Timer1LatchHigh | location | KV20 | none | VIA 2's timer 1 latch, high byte (not used). |
| 179 | D2T2L | $9128 | Via2Timer2 | location | KV20 | read:2, tapecontrol:1, write:1 | VIA 2's timer 2, low byte: the tape's pulse timer and the serial bus's timeouts. |
| 180 | D2T2H | $9129 | Via2Timer2High | location | KV20 | read:3, serial2.1:3, tapecontrol:2, write:1 | VIA 2's timer 2, high byte. |
| 181 | D2SR | $912A | Via2Shift | location | KV20 | none | VIA 2's shift register (not used). |
| 182 | D2ACR | $912B | Via2AuxiliaryControl | location | KV20 | init:1, write:1 | VIA 2's auxiliary control register. |
| 183 | D2PCR | $912C | Via2PeripheralControl | location | KV20 | init:1, serial2.1:10 | VIA 2's peripheral control register: CA2 and CB2 drive the serial bus's CLK and DATA. |
| 184 | D2IFR | $912D | Via2InterruptFlags | location | KV20 | read:1, serial2.1:3, tapecontrol:1 | VIA 2's interrupt flags. |
| 185 | D2IER | $912E | Via2InterruptEnable | location | KV20 | init:2, read:2, tapecontrol:2, write:1 | VIA 2's interrupt enable register. |
| 186 | D2ORA | $912F | Via2PortA | location | KV20; other names here: MTV: VIA2PA2 | time:2 | VIA 2's port A, without handshake: the keyboard's rows for the STOP key test. |
| 187 | VICCOL | $9400 | ColourMemory | location | KV20 | editor.2:2 | The colour RAM's usual place with RAM in block 1, $9400. |
| 188 | EOT | = 5 | TAPE_END_OF_TAPE | constant | KV20 | close:1, save:1, tapefile:1 | A tape header's type: the end of the tape, which LOAD stops at. |
| 189 | BLF | = 1 | TAPE_PROGRAM | constant | KV20 | load:1, save:1, tapefile:1 | A tape header's type: a program that loads where BASIC starts (relocatable). |
| 190 | BDF | = 2 | TAPE_DATA | constant | KV20 | channelio:1, open:1 | A data file's block, after its header. |
| 191 | PLF | = 3 | TAPE_PROGRAM_FIXED | constant | KV20 | load:1, save:1, tapefile:1 | A tape header's type: a program that loads where it was saved. |
| 192 | BDFH | = 4 | TAPE_DATA_HEADER | constant | KV20 | open:1, tapefile:1 | A tape header's type: a data file's header. |
| 193 | BUFSZ | = 192 | TAPE_BUFFER_SIZE | constant | KV20 | open:1, tapecontrol:1, tapefile:2 | The tape buffer's 192 bytes. |
| 194 | LLEN | = 22 | SCREEN_COLUMNS | constant | KV20 | editor.1:12, editor.2:2, editor.3:22 | 22 columns a row. |
| 195 | LLEN2 | = 44 | DROP | constant | KV20 | none | 44, a two-row line's columns; not used. Named in prose. |
| 196 | NLINES | = 23 | SCREEN_ROWS | constant | KV20 | editor.1:5, editor.2:7 | 23 rows. |
| 197 | WHITE | = 1 | COLOUR_WHITE | constant | KV20 | editor.2:1 | White, the screen's colour at start-up. |
| 198 | BLUE | = 6 | COLOUR_BLUE | constant | KV20 | editor.1:1 | Blue, the characters' colour at start-up. |
| 199 | CR | = 13 | DROP | constant | KV20 | none | 13, RETURN; not used by name. Named in prose. |

## Part 2: the screen editor and the keyboard

Accepted by the owner on 2026-11-25, with every question as recommended (K6).

The listing's `EDITOR.1`, `CONKAT`, `EDITOR.2` and `EDITOR.3`, `$E500-$EE13`: 190 labels and three
constants. Every local is written by its full path (X16). Few have a document besides KV20: *Mapping the VIC* gives
IOBASE, PLOT, CLSR, LP2, SCNKEY and LDTB2 by their addresses.

### Questions

- K-P2-Q1. **The print routine, PRT, is the top-level `ScreenOut`**, the name the BASIC conversion gave the PET
  editor's PRT (X14), with its locals `ScreenOut::Delete` and so on; the rest of the editor is in `Editor`.
  *Recommended*: same job, same name. The alternative is `Editor::Print`.
- K-P2-Q2. **KEY, the IRQ routine** (the clock, the cursor's blink, the cassette motor, the keyboard scan), is
  `Interrupts::Jiffy`, in the family of the code that takes the interrupt (part 7), although the listing has it
  in the editor's file. *Recommended.* The alternative is `Editor::Interrupt`.
- K-P2-Q3. **IOBASE, SCRORG and PLOT**, three small kernal calls in the editor's file, are `Editor::IoBase`,
  `Editor::ScreenSize` and `Editor::Plot`; the jump table's entries for them come in part 7 with the
  `Kernal` prefix (`KernalPlot`). *Recommended.*
- K-P2-Q4. **Routines entered in the middle.** As X2 says, a label other code enters is an entry of the routine
  it sits in: the keyboard input's NextCharacter (LOOP5, CHRIN's entry) is `Editor::Input::NextCharacter`,
  inside `Editor::Input`, which starts at the key-echo loop (LOOP4); ScreenOut's common return (LOOP2) is
  `Editor::ShowCharacter::Finish`. *Recommended.*
- K-P2-Q5. **The jump-on labels.** Several labels only jump on to the same place (JPL2, JPL3, NCZ2 and INSEXT all
  go to `ShowCharacter::Finish`), so "To" plus the target would give them one name; each is named for the step
  it ends instead (`ScreenOut::RightDone`, `ScreenOut::DownDone`). *Recommended*; the alternative is
  `ToFinish1`, `ToFinish2`.
- K-P2-Q6. **What the Japanese version left.** The listing's editor carries the kana modes' traces: NOP runs where
  their code was (kept as `nop`s with a comment), the CONKAT conversion table nothing reads (its bytes kept,
  described in prose, as *Mapping the VIC* does), CCTTA2 (a table name left on LOWER's code), and the spare key
  table CCTTA3, which `KeyTables`' unused entries still point at (`Editor::SpareKeys`). The labels nothing
  references and no document names are dropped (13 of them, UNKAT among them), and so is SWITCH, which MTV and
  V20PRG spell but not for this code. *Recommended.*
- K-P2-Q7. **VPAN**, a routine nothing in the ROM calls (the listing's "panic NMI entry"), keeps a name,
  `Editor::ResetScreen`, so the code has a `.proc`; its comment says nothing calls it. *Recommended.*

### Rows

| # | Old | Address | New | Kind | Documents (checked) | Used in | Reason |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | IOBASE | $E500 | Editor::IoBase | routine | KV20, MTV, in prose: the name's Also: is its jump-table entry's; spelling only: V20PRG | vectors:1 | X and Y = VIA 1's address, $9110, for IOBASE: a program finds the I/O through it. |
| 2 | SCRORG | $E505 | Editor::ScreenSize | routine | KV20 | vectors:1 | X = 22 columns, Y = 23 rows, for SCREEN. |
| 3 | PLOT | $E50A | Editor::Plot | routine | KV20, MTV, in prose: the name's Also: is its jump-table entry's; spelling only: V20PRG | vectors:1 | With carry set, X and Y = the cursor's row and column; with carry clear, moves the cursor to row X, column Y. |
| 4 | PLOT10 | $E513 | Editor::Plot::Read | local | KV20 | editor.1:1 | Reads the cursor's place back. |
| 5 | CINT | $E518 | Editor::Initialize | routine | KV20 | init:1, rs232nmifile:1 | Resets the VIC, points it at the screen ScreenPage gives, sets the editor's variables, and falls into ClearScreen. |
| 6 | NOHALF | $E536 | Editor::Initialize::WholeKilobyte | local | KV20 | editor.1:1 | The screen starts on a 1K boundary: no half-K bit for the VIC. |
| 7 | CLSR | $E55F | Editor::ClearScreen | routine | KV20, MTV | editor.1:1 | Rebuilds the line links, clears every row to spaces in white, and falls into Home. |
| 8 | LPS1 | $E568 | Editor::ClearScreen::NextLink | local | KV20 | editor.1:1 | Each row's link: its screen page, as a line's first row. |
| 9 | LPS2 | $E570 | Editor::ClearScreen::SamePage | local | KV20 | editor.1:1 | The row starts in the same page. |
| 10 | CLEAR1 | $E57B | Editor::ClearScreen::NextRow | local | KV20 | editor.1:1 | Clears the rows from the bottom up. |
| 11 | NXTD | $E581 | Editor::Home | routine | KV20 | editor.1:2 | Moves the cursor to the top left, and falls into PlaceCursor. |
| 12 | STUPT | $E587 | Editor::PlaceCursor | routine | KV20 | editor.1:4 | From Row and Column, finds the logical line the cursor is in: Line, the column in the line, and LineLength. |
| 13 | FNDSTR | $E58B | Editor::PlaceCursor::FindLineStart | local | KV20 | editor.1:1 | Back to the line's first row, adding 22 to the column for each. |
| 14 | STOK | $E597 | Editor::PlaceCursor::LineStartFound | local | KV20 | editor.1:1 | Line = the first row's address. |
| 15 | FNDEND | $E5A8 | Editor::PlaceCursor::FindLineEnd | local | KV20 | editor.1:1 | On through the rows that continue the line, for its length. |
| 16 | STDONE | $E5B2 | Editor::PlaceCursor::Done | local | KV20 | editor.1:1 | LineLength = the line's last column. |
| 17 | VPAN | $E5B5 | Editor::ResetScreen | routine | KV20 | none | Resets the devices and the VIC and homes the cursor. Nothing in the ROM calls it (the listing's 'PANIC NMI ENTRY'). |
| 18 | PANIC | $E5BB | Editor::ResetDevices | routine | KV20 | editor.1:2 | Output to the screen, input from the keyboard; falls into InitializeVic. |
| 19 | INITV | $E5C3 | Editor::InitializeVic | routine | KV20 | init:1 | Loads the VIC's 16 registers from VicSetup. |
| 20 | PX4 | $E5C5 | Editor::InitializeVic::Next | local | KV20 | editor.1:1 | Each register, from the last. |
| 21 | LP2 | $E5CF | Editor::TakeKey | routine | KV20, MTV | channelio:1 | Takes the first character from the keyboard buffer and moves the rest up: A = the character, carry clear. |
| 22 | LP1 | $E5D4 | Editor::TakeKey::Shift | local | KV20 | editor.1:1 | Moves each character up one. |
| 23 | LOOP4 | $E5E5 | Editor::Input | routine | KV20 | editor.1:1 | Keyboard input: prints each key typed, until RETURN; then reads the logical line back from the screen a character at a time (NextCharacter). |
| 24 | LOOP3 | $E5E8 | Editor::Input::WaitForKey | local | KV20 | editor.1:3 | Waits with the cursor blinking for a key in the buffer. |
| 25 | LP21 | $E602 | Editor::Input::CursorRestored | local | KV20 | editor.1:1 | The character under the cursor is put back. |
| 26 | LP23 | $E60E | Editor::Input::TypeRun | local | KV20 | editor.1:1 | Shifted RUN/STOP: puts LOAD and RUN, each with RETURN, into the buffer. |
| 27 | LP22 | $E619 | Editor::Input::NotRun | local | KV20 | editor.1:1 | Any key but RETURN is printed. |
| 28 | CLP5 | $E621 | Editor::Input::FindLineEnd | local | KV20 | editor.1:1 | RETURN: back from the line's last column past the trailing spaces. |
| 29 | CLP6 | $E62A | Editor::Input::LineEndFound | local | KV20 | editor.1:1 | LineEnd = the last character's column; the line is read from its start, or from where input started. |
| 30 | LOOP5 | $E64F | Editor::Input::NextCharacter | entry | KV20 | channelio:2 | CHRIN from the keyboard: the next character of the line read back, waiting for a line first; A = it. |
| 31 | LOP5 | $E657 | Editor::Input::ReadScreen | local | KV20 | editor.1:4 | The screen code at the column, converted to PETSCII. |
| 32 | NOTONE | $E672 | DROP | local | KV20 | none | Not referenced; no document names it. |
| 33 | LOP51 | $E674 | DROP | local | KV20 | none | Not referenced; no document names it. |
| 34 | LOP54 | $E67E | Editor::Input::CheckShift | local | KV20 | editor.1:1 | A screen code of $40-$7F is a shifted character. |
| 35 | LOP52 | $E684 | Editor::Input::CheckGraphic | local | KV20 | editor.1:1 | Outside quotes, codes $00-$1F and $40-$5F map to $40-$5F. |
| 36 | LOP53 | $E688 | Editor::Input::Converted | local | KV20 | editor.1:2 | On to the next column; a quote toggles quote mode. |
| 37 | CLP2 | $E691 | Editor::Input::LineDone | local | KV20 | editor.1:1 | The line's end: input from the screen is over, and RETURN is echoed unless the screen is the device. |
| 38 | CLP2A | $E6A3 | Editor::Input::EchoReturn | local | KV20 | editor.1:1 | Prints RETURN. |
| 39 | CLP21 | $E6A6 | Editor::Input::EndOfLine | local | KV20 | editor.1:1 | A = RETURN. |
| 40 | CLP1 | $E6A8 | Editor::Input::Return | local | KV20 | editor.1:1 | Restores X and Y; returns the character, with carry clear. |
| 41 | CLP7 | $E6B6 | Editor::Input::NotPi | local | KV20 | editor.1:1 | Pi's screen code returns as $FF. |
| 42 | QTSWC | $E6B8 | Editor::ToggleQuote | routine | KV20 | editor.1:2 | A quote turns quote mode on or off; A is kept. |
| 43 | QTSWL | $E6C4 | Editor::ToggleQuote::Done | local | KV20 | editor.1:1 | Returns. |
| 44 | NXT33 | $E6C5 | Editor::ShowCharacter | routine | KV20 | editor.1:1 | ScreenOut's last step: adds $40 for a shifted character, reverses it in reverse mode, uses an insert, displays it in TextColour, moves the cursor on, and returns from ScreenOut. |
| 45 | NXT3 | $E6C7 | Editor::ShowCharacter::Unshifted | entry | KV20 | editor.1:1 | As ShowCharacter, the code as it is. |
| 46 | NC3 | $E6CB | Editor::ShowCharacter::Reversed | entry | KV20 | editor.1:3 | As ShowCharacter, reversed: cursor and colour keys in quote mode and inserts. |
| 47 | NVS | $E6CD | Editor::ShowCharacter::UseInsert | local | KV20 | editor.1:1 | An insert open is used up. |
| 48 | NVS1 | $E6D3 | Editor::ShowCharacter::Show | local | KV20 | editor.1:1 | Displays it and moves the cursor on. |
| 49 | LOOP2 | $E6DC | Editor::ShowCharacter::Finish | entry | KV20; spelling only: V20PRG | editor.1:8, editor.3:2 | ScreenOut's return: quote mode ends with the last insert; restores X, Y and A, carry clear, interrupts on. |
| 50 | LOP2 | $E6E4 | Editor::ShowCharacter::RestoreRegisters | local | KV20 | editor.1:1 | Restores the registers. |
| 51 | WLOGIC | $E6EA | Editor::AdvanceCursor | routine | KV20 | editor.1:1 | Moves the cursor on after a character: past a line's end, the line grows a row (up to four), scrolling or inserting a row as needed. |
| 52 | WLOG20 | $E701 | Editor::AdvanceCursor::GrowLine | local | KV20 | editor.1:1 | Scrolls first if the cursor is on the bottom row. |
| 53 | WLOG30 | $E70E | Editor::AdvanceCursor::JoinRow | entry | KV20 | editor.1:1, editor.2:2 | Joins row X to the line above (InsertLine enters here). |
| 54 | PATOUT | $E715 | Editor::AdvanceCursor::PatchReturn | entry | KV20 | editor.3:1 | EndRowPatch's return: LineLength grows by 22. |
| 55 | FINDST | $E719 | Editor::AdvanceCursor::FindLineStart | entry | KV20 | editor.1:2 | Back to the first row of row X's line; Input calls it. |
| 56 | FINX | $E720 | Editor::AdvanceCursor::LineStartFound | local | KV20 | editor.1:1 | Line = that row's address. |
| 57 | WLOG10 | $E723 | Editor::AdvanceCursor::LineFull | local | KV20 | editor.1:1 | The line is 88 characters: the cursor goes to the next line. |
| 58 | WLGRTS | $E72C | Editor::AdvanceCursor::Done | local | KV20 | editor.1:1 | Returns. |
| 59 | BKLN | $E72D | Editor::BackUpRow | routine | KV20 | editor.1:2 | Cursor left from a row's first column: to the end of the row above, or nowhere from the top row. |
| 60 | BKLN1 | $E737 | Editor::BackUpRow::Previous | local | KV20 | editor.1:1 | The row above, at its line's last column. |
| 61 | PRT | $E742 | ScreenOut | routine | KV20 | channelio:1, editor.1:2 | CHROUT to the screen: prints a character or carries out a control code (cursor, HOME, CLR, DEL, INST, RVS, colours, case). |
| 62 | NJT1 | $E75D | ScreenOut::NotReturn | local | KV20 | editor.1:1 | Not RETURN: a control code, or a character. |
| 63 | NJT8 | $E769 | ScreenOut::ToScreenCode | local | KV20 | editor.1:1 | $20-$5F become screen codes $20-$3F, $00-$1F. |
| 64 | NJT9 | $E76B | ScreenOut::Show | local | KV20 | editor.1:1 | Toggles quote mode for a quote, and shows the character. |
| 65 | NTCN | $E771 | ScreenOut::Control | local | KV20 | editor.1:1 | A control code; with an insert open it prints reversed. |
| 66 | CNC3X | $E778 | ScreenOut::NoInserts | local | KV20 | editor.1:1 | DEL, or another control code. |
| 67 | BAK1UP | $E785 | ScreenOut::Delete | local | KV20 | editor.1:1 | DEL: the cursor goes back one, and the rest of the line closes up. |
| 68 | BK1 | $E78B | DROP | local | KV20 | none | Not referenced; no document names it. |
| 69 | BK15 | $E78E | ScreenOut::CloseUp | local | KV20 | editor.1:1 | Moves each character and its colour left. |
| 70 | BK2 | $E79F | ScreenOut::BlankLast | local | KV20 | editor.1:1 | A space at the line's end. |
| 71 | NTCN1 | $E7AA | ScreenOut::NotDelete | local | KV20 | editor.1:1 | In quote mode, a control code prints reversed. |
| 72 | CNC3 | $E7AE | DROP | local | KV20 | none | Not referenced; no document names it. |
| 73 | NC3W | $E7B1 | ScreenOut::NotQuoted | local | KV20 | editor.1:1 | RVS ON. |
| 74 | NC1 | $E7B7 | ScreenOut::NotReverseOn | local | KV20 | editor.1:1 | HOME. |
| 75 | NC2 | $E7BE | ScreenOut::NotHome | local | KV20 | editor.1:1 | Cursor right. |
| 76 | JPL4 | $E7D4 | ScreenOut::SetColumn | local | KV20 | editor.1:2 | Column = Y. |
| 77 | NCZ2 | $E7D6 | ScreenOut::RightDone | local | KV20 | editor.1:1 | To ShowCharacter::Finish. |
| 78 | NCX2 | $E7D9 | ScreenOut::NotRight | local | KV20 | editor.1:1 | Cursor down: a row on, within the line or to the next. |
| 79 | CURS10 | $E7EC | ScreenOut::DownColumn | local | KV20 | editor.1:1 | The column in the next line. |
| 80 | GOTDWN | $E7F4 | ScreenOut::DownToNextLine | local | KV20 | editor.1:1 | To the next logical line. |
| 81 | JPL3 | $E7F7 | ScreenOut::DownDone | local | KV20 | editor.1:1 | To ShowCharacter::Finish. |
| 82 | COLR1 | $E7FA | ScreenOut::Colour | local | KV20 | editor.1:1 | A colour code, or the case codes. |
| 83 | NXTX | $E800 | ScreenOut::Shifted | local | KV20 | editor.1:1 | A character with bit 7 set: shifted, or a shifted control code. |
| 84 | KEEPIT | $E815 | DROP | local | KV20 | none | Not referenced; no document names it. |
| 85 | NXTX1 | $E81D | ScreenOut::NotPi | local | KV20 | editor.1:1 | $FF prints pi, $5E. |
| 86 | NXTXA | $E823 | DROP | local | KV20 | none | Not referenced; no document names it. |
| 87 | UHUH | $E82A | ScreenOut::ShiftedControl | local | KV20 | editor.1:1 | Shifted RETURN goes to the next line too. |
| 88 | UP5 | $E831 | ScreenOut::ShiftedNotReturn | local | KV20 | editor.1:1 | INST: opens a space at the cursor. |
| 89 | INS3 | $E845 | ScreenOut::InsertRow | local | KV20 | editor.1:1 | The line's last column is full: a row is opened below, if the line has room. |
| 90 | INS1 | $E84C | ScreenOut::OpenGap | local | KV20 | editor.1:1 | Moves the rest of the line right. |
| 91 | INS2 | $E851 | ScreenOut::MoveRight | local | KV20 | editor.1:1 | Each character and its colour one right. |
| 92 | INSEXT | $E86D | ScreenOut::InsertDone | local | KV20 | editor.1:1 | To ShowCharacter::Finish. |
| 93 | UP9 | $E870 | ScreenOut::NotInsert | local | KV20 | editor.1:1 | With inserts open, a shifted control code prints reversed. |
| 94 | UP6 | $E874 | ScreenOut::ShowShifted | local | KV20 | editor.1:1 | Prints it reversed, as a shifted character. |
| 95 | UP2 | $E879 | ScreenOut::NotInsertMode | local | KV20 | editor.1:1 | Cursor up. |
| 96 | UPALIN | $E88E | ScreenOut::UpToPreviousLine | local | KV20 | editor.1:1 | Up past the line's first row: PlaceCursor works out the line above. |
| 97 | NXT2 | $E893 | ScreenOut::NotUp | local | KV20 | editor.1:1 | RVS OFF. |
| 98 | NXT6 | $E89B | ScreenOut::NotReverseOff | local | KV20 | editor.1:1 | Cursor left. |
| 99 | BAKBAK | $E8AB | ScreenOut::LeftToPreviousRow | local | KV20 | editor.1:1 | Left from the first column: BackUpRow. |
| 100 | NXT61 | $E8B1 | ScreenOut::NotLeft | local | KV20 | editor.1:1 | CLR. |
| 101 | JPL2 | $E8B8 | ScreenOut::ShiftedDone | local | KV20 | editor.1:3 | To ShowCharacter::Finish. |
| 102 | SCCL | $E8BB | ScreenOut::ShiftedColour | local | KV20 | editor.1:1 | A shifted colour code, or the case codes. |
| 103 | NXLN | $E8C3 | Editor::NextLine | routine | KV20 | editor.1:4 | To the first row of the next logical line, scrolling at the bottom. |
| 104 | NXLN2 | $E8C7 | Editor::NextLine::NextRow | local | KV20 | editor.1:1 | The next row, scrolling when it is off the bottom. |
| 105 | NXLN1 | $E8CF | Editor::NextLine::CheckRow | local | KV20 | editor.1:1 | Until a row that starts a line. |
| 106 | NXT1 | $E8D8 | Editor::CarriageReturn | routine | KV20 | editor.1:2 | RETURN: ends inserts, reverse and quote mode, and goes to the next line's start. |
| 107 | JPL5 | $E8E5 | DROP | local | KV20 | none | Not referenced; no document names it. |
| 108 | CHKBAK | $E8E8 | Editor::CheckRowBack | routine | KV20 | editor.1:2 | If the cursor is at the start of one of its line's rows, Row moves up one. |
| 109 | CHKLUP | $E8EC | Editor::CheckRowBack::Next | local | KV20 | editor.1:1 | Each row's first column. |
| 110 | BACK | $E8F7 | Editor::CheckRowBack::Back | local | KV20; spelling only: MTV | editor.1:1, editor.3:1 | Row up one. |
| 111 | CHKDWN | $E8FA | Editor::CheckRowForward | routine | KV20 | editor.1:2 | If the cursor is at the end of one of its line's rows, Row moves down one. |
| 112 | DWNCHK | $E8FE | Editor::CheckRowForward::Next | local | KV20 | editor.1:1 | Each row's last column. |
| 113 | DNLINE | $E909 | Editor::CheckRowForward::Down | local | KV20 | editor.1:1 | Row down one, unless on the bottom row. |
| 114 | DWNBYE | $E911 | Editor::CheckRowForward::Done | local | KV20 | editor.1:1 | Returns. |
| 115 | CHKCOL | $E912 | Editor::CheckColour | routine | KV20 | editor.1:2 | A colour code sets TextColour. |
| 116 | CHK1A | $E914 | Editor::CheckColour::Next | local | KV20 | editor.1:1 | Each of the eight codes. |
| 117 | CHK1B | $E91D | Editor::CheckColour::Found | local | KV20 | editor.1:1 | TextColour = the code's colour. |
| 118 | COLTAB | $E921 | Editor::ColourCodes | table | KV20 | editor.1:1 | The eight colour codes, black to yellow, by colour. |
| 119 | UNKAT | $E953 | DROP | table | KV20 | none | Part of a conversion table of the Japanese version's, which nothing uses; the bytes stay, described in prose (MTV's 'code conversion table'). |
| 120 | SCROL | $E975 | Editor::ScrollUp | routine | KV20 | editor.1:2, editor.2:1 | Scrolls the screen up a logical line, links and all; holding CTRL slows it. |
| 121 | SCRO0 | $E981 | Editor::ScrollUp::Again | local | KV20 | editor.2:1 | Up one row, again while the top row continues a line. |
| 122 | SCR10 | $E989 | Editor::ScrollUp::NextRow | local | KV20 | editor.2:1 | Copies each row up. |
| 123 | SCR41 | $E99D | Editor::ScrollUp::ClearBottom | local | KV20 | editor.2:1 | Clears the bottom row. |
| 124 | SCRL5 | $E9A2 | Editor::ScrollUp::NextLink | local | KV20 | editor.2:1 | Moves each link up. |
| 125 | SCRL3 | $E9AC | Editor::ScrollUp::StoreLink | local | KV20 | editor.2:1 | Stores it. |
| 126 | MLP4 | $E9D6 | Editor::ScrollUp::Delay | local | KV20 | editor.2:2 | CTRL is down: a delay, and the keyboard buffer emptied. |
| 127 | MLP42 | $E9DF | Editor::ScrollUp::Done | local | KV20 | editor.2:1 | Restores the pointers. |
| 128 | NEWLIN | $E9EE | Editor::InsertLine | routine | KV20; spelling only: MTV | editor.1:1 | Opens a row below the cursor's logical line, scrolling the rows below down, for the line to grow into. |
| 129 | BMT1 | $E9F0 | Editor::InsertLine::FindLastRow | entry | KV20 | editor.1:1, editor.2:1 | The line's last row (AdvanceCursor enters here). |
| 130 | NEWLX | $EA08 | Editor::InsertLine::ScrollDown | local | KV20 | editor.2:2 | Moves the rows below down. |
| 131 | SCD10 | $EA16 | Editor::InsertLine::NextRow | local | KV20 | editor.2:1 | Each row, from the bottom. |
| 132 | SCR40 | $EA2C | Editor::InsertLine::ClearOpenedRow | local | KV20 | editor.2:2 | Clears the opened row. |
| 133 | SCRD21 | $EA31 | Editor::InsertLine::NextLink | local | KV20 | editor.2:1 | Moves each link down. |
| 134 | SCRD19 | $EA3F | Editor::InsertLine::StoreLink | local | KV20 | editor.2:1 | Stores it. |
| 135 | SCRD22 | $EA44 | Editor::InsertLine::Done | local | KV20 | editor.2:1 | Joins the opened row to the line. |
| 136 | SCRLIN | $EA56 | Editor::CopyRow | routine | KV20 | editor.2:2 | Copies a row's characters and colours to row X's place. |
| 137 | SCD20 | $EA62 | Editor::CopyRow::Next | local | KV20 | editor.2:1 | Each column. |
| 138 | TOFROM | $EA6E | Editor::ColourPointers | routine | KV20 | editor.2:1 | The colour RAM addresses for a row copy. |
| 139 | SETPNT | $EA7E | Editor::SetLinePointer | routine | KV20 | editor.1:1, editor.2:3 | Line = row X's address. |
| 140 | CLRLN | $EA8D | Editor::ClearRow | routine | KV20 | editor.1:1, editor.2:2 | Clears row X to spaces in white. |
| 141 | CLR10 | $EA95 | Editor::ClearRow::Next | local | KV20 | editor.2:1 | Each column. |
| 142 | DSPP | $EAA1 | Editor::Display | routine | KV20 | editor.1:2 | Puts A, in colour X, at the cursor, restarting the cursor's blink. |
| 143 | DSPP2 | $EAAA | Editor::Display::AtCursor | entry | KV20 | editor.2:1 | Puts it there without touching the blink. |
| 144 | SCOLOR | $EAB2 | Editor::SetColourPointer | routine | KV20 | editor.1:2, editor.2:4 | ColourLine = the colour RAM's address for Line. |
| 145 | KEY | $EABF | Interrupts::Jiffy | routine | KV20; spelling only: MTV, V20PRG | init:2 | The IRQ routine, 60 times a second: the clock, the cursor's blink, the cassette motor, the keyboard scan (CINV's default). |
| 146 | REPDO | $EACC | DROP | local | KV20 | none | Not referenced; no document names it. |
| 147 | KEY5 | $EAEA | Interrupts::Jiffy::Blink | local | KV20 | editor.2:1 | Reverses the character under the cursor. |
| 148 | KEY4 | $EAEF | Interrupts::Jiffy::Cassette | local | KV20 | editor.2:2 | PLAY up: CassetteMotorMode is cleared and the motor turned off. |
| 149 | KEY3 | $EB01 | Interrupts::Jiffy::PlayDown | local | KV20 | editor.2:1 | PLAY down: the motor runs, unless a tape routine has it. |
| 150 | KL24 | $EB0A | Interrupts::Jiffy::SetMotor | local | KV20 | editor.2:1 | Not while RS-232 sends, which uses the same line. |
| 151 | KL2 | $EB12 | Interrupts::Jiffy::Scan | local | KV20 | editor.2:2 | Scans the keyboard, then returns from the interrupt. |
| 152 | KPREND | $EB15 | DROP | local | KV20 | none | Not referenced; no document names it. |
| 153 | SCNKEY | $EB1E | Editor::ScanKeyboard | routine | KV20, MTV, in prose: the name's Also: is its jump-table entry's; spelling only: V20PRG | editor.2:1, vectors:1 | SCNKEY: reads the keyboard's matrix, sets ShiftKeys, picks the key table, and puts a new or repeating key in the buffer. |
| 154 | SCN20 | $EB40 | Editor::ScanKeyboard::NextColumn | local | KV20 | editor.2:2 | Reads a column's rows, until two reads agree. |
| 155 | SCN30 | $EB4A | Editor::ScanKeyboard::NextRow | local | KV20 | editor.2:1 | Each row. |
| 156 | SPCK2 | $EB60 | Editor::ScanKeyboard::KeyFound | local | KV20 | editor.2:2 | A key that isn't a shift key. |
| 157 | CKUT | $EB62 | Editor::ScanKeyboard::RowDone | local | KV20 | editor.2:1 | Restores the rows. |
| 158 | CKIT | $EB63 | Editor::ScanKeyboard::NextKey | local | KV20 | editor.2:1 | The next of the 64 keys. |
| 159 | CKIT1 | $EB71 | Editor::ScanKeyboard::Shifts | local | KV20 | editor.2:1 | Through KeyTableSetup, for the shift keys. |
| 160 | REKEY | $EB74 | Editor::ScanKeyboard::Decode | entry | KV20 | editor.2:1 | The key's character from the table; a new key, or a repeat (SelectKeyTable comes back here). |
| 161 | RPT10 | $EB84 | Editor::ScanKeyboard::SameKey | local | KV20 | editor.2:1 | The same key as last time: it repeats, as KeyRepeat allows. |
| 162 | SCNOUT | $EB8F | Editor::ScanKeyboard::ToStoreKey | local | KV20 | editor.2:1 | No key: on to StoreKey. |
| 163 | RPT20 | $EBA1 | Editor::ScanKeyboard::Repeat | local | KV20 | editor.2:4 | Counts down the delay before repeating. |
| 164 | RPT40 | $EBAB | Editor::ScanKeyboard::CountInterval | local | KV20 | editor.2:1 | Then the interval between repeats. |
| 165 | CKIT2 | $EBBA | Editor::ScanKeyboard::StoreKey | local | KV20 | editor.2:2 | Remembers the key and the shift keys, and puts a character in the buffer if there is room. |
| 166 | CKIT3 | $EBC4 | DROP | local | KV20 | none | Not referenced; no document names it. |
| 167 | PUTQUE | $EBD0 | DROP | local | KV20 | none | Not referenced; no document names it. |
| 168 | SCNRTS | $EBD6 | Editor::ScanKeyboard::Done | entry | KV20 | editor.2:8 | Leaves column 3 driven, for the STOP key's test, and returns. |
| 169 | SHFLOG | $EBDC | Editor::SelectKeyTable | routine | KV20 | editor.1:2 | KeyTableSetup's default: SHIFT with C= switches the character set (unless locked); otherwise the shift keys pick the key table. |
| 170 | SWITCH | $EC00 | DROP | local | KV20; spelling only: MTV, V20PRG | none | Not referenced; MTV and V20PRG spell SWITCH, but not for this code. |
| 171 | KEYLG2 | $EC0F | Editor::SelectKeyTable::NotCaseSwitch | local | KV20 | editor.2:1 | The table for the shift keys; CTRL's is the fourth. |
| 172 | NCTRL | $EC18 | Editor::SelectKeyTable::NotControl | local | KV20 | editor.2:1 | The Japanese version's kana modes, now NOPs. |
| 173 | NOTKAT | $EC33 | DROP | local | KV20 | none | Not referenced; no document names it. |
| 174 | SHFOUT | $EC43 | Editor::SelectKeyTable::Done | local | KV20 | editor.2:2 | Back to ScanKeyboard::Decode. |
| 175 | KEYCOD | $EC46 | Editor::KeyTables | table | KV20 | editor.2:2 | The key tables by the shift keys: unshifted, SHIFT, C=, CTRL, and the Japanese version's eight more. |
| 176 | MODE1 | $EC5E | Editor::UnshiftedKeys | table | KV20 | editor.2:2, editor.3:2 | The 64 keys' characters with no shift key, by matrix code. |
| 177 | MODE2 | $EC9F | Editor::ShiftedKeys | table | KV20 | editor.3:2 | With SHIFT. |
| 178 | MODE3 | $ECE0 | Editor::CommodoreKeys | table | KV20 | editor.3:1 | With C=. |
| 179 | CCTTA2 | $ED21 | DROP | table | KV20 | editor.3:1 | The Japanese version's kana table's name, left on the code at LOWER's address; named in prose. |
| 180 | LOWER | $ED21 | Editor::CaseCodes | routine | KV20; spelling only: MTV, V20PRG | editor.1:1 | CHR$(14) switches the VIC to the lower-case set, and falls into the shifted codes. |
| 181 | UPPER | $ED30 | Editor::CaseCodes::Shifted | entry | KV20; spelling only: V20PRG | editor.1:1, editor.3:1 | CHR$(142) switches back to upper case; CHR$(8) and CHR$(9) lock and unlock the switch. |
| 182 | OUTHRE | $ED3C | Editor::CaseCodes::Done | local | KV20 | editor.3:3 | To ShowCharacter::Finish. |
| 183 | LOCK | $ED3F | Editor::CaseCodes::Lock | local | KV20 | editor.3:1 | CHR$(8): CaseSwitchLock set. |
| 184 | UNLOCK | $ED4D | Editor::CaseCodes::Unlock | local | KV20 | editor.3:1 | CHR$(9): cleared. |
| 185 | PATCHX | $ED5B | Editor::EndRowPatch | routine | KV20 | editor.1:1 | A patch to AdvanceCursor: marks the next row as a line's start before joining the cursor's row. |
| 186 | CCTTA3 | $ED69 | Editor::SpareKeys | table | KV20 | editor.3:3 | The Japanese version's limited graphics table, which KeyTables' spare entries point at. |
| 187 | CONTRL | $EDA3 | Editor::ControlKeys | table | KV20 | editor.3:3 | With CTRL: the colours and RVS. |
| 188 | TVIC | $EDE4 | Editor::VicSetup | table | KV20 | editor.1:1 | The VIC's 16 registers at start-up: the screen's place (NTSC or PAL), 22 × 23, the sound off, white and cyan. |
| 189 | RUNTB | $EDF4 | Editor::RunKeyText | table | KV20; spelling only: MTV | editor.1:1 | What shifted RUN/STOP types: LOAD, RETURN, RUN, RETURN. |
| 190 | LDTB2 | $EDFD | Editor::RowStarts | table | KV20, MTV | editor.1:1, editor.2:3 | Each row's start in the screen, low byte (LineLinks has the page). |
| 191 | MAXCHR | = 88 | LONGEST_LINE | constant | KV20 | editor | A logical line's most characters, 88: four rows. |
| 192 | NWRAP | = 4 | ROWS_PER_LINE | constant | KV20 | editor | The most rows a logical line takes. |
| 193 | LINZ0 | = $1000 + 22 × n | DROP | constant | KV20 | editor | LINZ0-LINZ22, each row's address, which RowStarts is built from: arithmetic written inline, the listing's names in prose. |

## Part 3: the serial bus

Accepted by the owner on 2026-11-25, with every question as recommended (K7).

The listing's `SERIAL2.1`, `$EE14-$EF9F`, with three routines it moved to the patch area at `$E4A0`: 47
labels and two assembly-time constants. *Mapping the VIC* gives TALK, LIST1, SCATN, TKSA, CIOUT, UNTLK, UNLSN and
ACPTR by their addresses.

### Questions

- K-P3-Q1. **The bus's entry points** are named for what they send or receive, matching the names the BASIC
  conversion gave their jump-table entries (`KernalTalk`, `KernalSendSecondary`, `KernalReceiveByte`, part 7):
  `Serial::Talk`, `Listen`, `SendSecondary` (SECOND), `SendTalkSecondary` (TKSA), `SendByte` (CIOUT),
  `Untalk`, `Unlisten` and `ReceiveByte` (ACPTR). *Recommended.*
- K-P3-Q2. **The line routines are named for the bus line, not the VIA's pin.** The listing's CLKHI, CLKLO,
  DATAHI and DATALO name the line's level, which the inverters make the opposite of the VIA's CA2 and CB2: so
  `ReleaseClock` and `PullClock`, `ReleaseData` and `PullData`, saying what happens on the bus, with the
  pin in the comment. DEBPIA is `ReadLines`. *Recommended.* The alternative is `ClockHigh` and `ClockLow`.
- K-P3-Q3. **The patch area.** ReleaseData, PullData and ReadLines are at `$E4A0`, before the editor, where
  Commodore moved them for room: the source has them in a `.scope Serial continued` piece at the kernal's start,
  with a comment saying why. AROUND and KSP2, the listing's arithmetic for the move, are written inline and named
  in prose. *Recommended.*
- K-P3-Q4. **The skipped instructions.** TALK and UNTALK each end in a `BIT` opcode (`$2C`) that skips the next
  routine's first instruction: each stays its own `.proc`, with the `.byte $2C` explained and an `.assert` that
  the routine it skips into follows, as READ's mode is in the BASIC sources. NODEV's skip over FRMERR's load is
  inside one routine, `BusError`, with FRMERR its entry. *Recommended.*

### Rows

| # | Old | Address | New | Kind | Documents (checked) | Used in | Reason |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | TALK | $EE14 | Serial::Talk | routine | KV20, MTV, in prose: the name's Also: is its jump-table entry's; spelling only: V20PRG | load:1, openchannel:1, vectors:1 | TALK: sends device A's talk command under ATN; skips Listen's first instruction to share its code. |
| 2 | LISTN | $EE17 | Serial::Listen | routine | KV20 | open:1, openchannel:1, save:2, vectors:1 | LISTEN: sends device A's listen command under ATN, first sending any byte still buffered, with EOI; leaves ATN pulled. |
| 3 | LIST1 | $EE1C | Serial::Listen::SendCommand | entry | KV20, MTV | serial2.1:1 | Sends the command in A (Unlisten enters here with $3F). |
| 4 | LIST2 | $EE2B | Serial::Listen::NoneWaiting | local | KV20 | serial2.1:1 | BufferedCharacter = the command. The compare meant to release CLK for UNLISTEN tests VIA 2's peripheral control, so CLK is never released here. |
| 5 | LIST5 | $EE38 | Serial::Listen::PullAtn | local | KV20 | serial2.1:1 | Pulls ATN, and falls into SendCommandByte. |
| 6 | ISOURA | $EE40 | Serial::SendCommandByte | routine | KV20 | serial2.1:2 | Pulls CLK, releases DATA and waits 1 ms for the devices to answer ATN; falls into SendBufferedByte. |
| 7 | ISOUR | $EE49 | Serial::SendBufferedByte | routine | KV20 | serial2.1:2 | Sends BufferedCharacter, with EOI when EndOfFile says: waits for the listener, clocks out 8 bits, and waits 1 ms for it to accept; interrupts off meanwhile. |
| 8 | ISR02 | $EE5A | Serial::SendBufferedByte::EoiReleased | local | KV20 | serial2.1:1 | EOI: waits for the listener to release DATA... |
| 9 | ISR03 | $EE60 | Serial::SendBufferedByte::EoiAcknowledged | local | KV20 | serial2.1:1 | ...and to pull it again, which acknowledges the EOI. |
| 10 | NOEOI | $EE66 | Serial::SendBufferedByte::WaitReady | local | KV20 | serial2.1:2 | Waits for the listener to release DATA: ready for the byte. |
| 11 | ISR01 | $EE73 | Serial::SendBufferedByte::NextBit | local | KV20 | serial2.1:2 | Each bit, low first: DATA must be released before it. |
| 12 | ISRHI | $EE88 | Serial::SendBufferedByte::BitOne | local | KV20 | serial2.1:1 | A 1: DATA released. |
| 13 | ISRCLK | $EE8B | Serial::SendBufferedByte::ClockBit | local | KV20 | serial2.1:1 | Releases CLK for the listener to take the bit, then pulls it. |
| 14 | ISR04 | $EEA5 | Serial::SendBufferedByte::WaitAccepted | local | KV20 | serial2.1:1 | Waits up to 1 ms for the listener to pull DATA: the byte is taken. |
| 15 | NODEV | $EEB4 | Serial::BusError | routine | KV20 | serial2.1:1 | The serial routines' error exit: device not present ($80 in IoStatus); releases the lines, carry clear. |
| 16 | FRMERR | $EEB7 | Serial::BusError::Timeout | entry | KV20 | serial2.1:2 | A write timeout ($03): the listener did not answer. |
| 17 | CSBERR | $EEB9 | Serial::BusError::SetStatus | entry | KV20 | serial2.1:1 | Adds A's bits to IoStatus and releases the lines (ReceiveByte enters with a read timeout, $02). |
| 18 | SECND | $EEC0 | Serial::SendSecondary | routine | KV20 | open:1, openchannel:1, save:2, vectors:1 | SECOND: sends a secondary address after LISTEN, under ATN, and falls into ReleaseAtn. |
| 19 | SCATN | $EEC5 | Serial::ReleaseAtn | routine | KV20, MTV | openchannel:1, serial2.1:2 | Releases ATN. |
| 20 | TKSA | $EECE | Serial::SendTalkSecondary | routine | KV20, MTV, in prose: the name's Also: is its jump-table entry's; spelling only: V20PRG | load:1, openchannel:1, vectors:1 | TKSA: sends a secondary address after TALK, and falls into TurnAround. |
| 21 | TKATN | $EED3 | Serial::TurnAround | routine | KV20 | openchannel:1 | Makes the device the talker: pulls DATA, releases ATN and CLK, and waits for the device to pull CLK. |
| 22 | TKATN1 | $EEDD | Serial::TurnAround::WaitForTalker | local | KV20 | serial2.1:1 | Waits for CLK to go low. |
| 23 | CIOUT | $EEE4 | Serial::SendByte | routine | KV20, MTV, in prose: the name's Also: is its jump-table entry's; spelling only: V20PRG | channelio:1, open:1, save:3, vectors:1 | CIOUT: buffers A, sending the byte buffered before it, so the last byte can go with EOI at UNLISTEN; carry clear. |
| 24 | CI2 | $EEED | Serial::SendByte::SendPrevious | local | KV20 | serial2.1:1 | Sends the byte already buffered. |
| 25 | CI4 | $EEF2 | Serial::SendByte::Buffer | local | KV20 | serial2.1:1 | BufferedCharacter = A. |
| 26 | UNTLK | $EEF6 | Serial::Untalk | routine | KV20, MTV, in prose: the name's Also: is its jump-table entry's; spelling only: V20PRG | clall:1, load:1, vectors:1 | UNTALK: pulls CLK and ATN, and sends $5F, skipping Unlisten's first instruction. |
| 27 | UNLSN | $EF04 | Serial::Unlisten | routine | KV20, MTV, in prose: the name's Also: is its jump-table entry's; spelling only: V20PRG | clall:1, open:1, save:2, vectors:1 | UNLISTEN: sends $3F under ATN, then falls into ReleaseLines. |
| 28 | DLABYE | $EF09 | Serial::ReleaseLines | routine | KV20 | serial2.1:1 | Releases ATN, waits about 60 µs, and releases CLK and DATA. |
| 29 | DLADLH | $EF0C | Serial::ReleaseLines::ClockAndData | entry | KV20 | serial2.1:2 | The wait and CLK and DATA (ReceiveByte enters here); X is kept. |
| 30 | DLAD00 | $EF0F | Serial::ReleaseLines::Delay | local | KV20 | serial2.1:1 | The wait. |
| 31 | ACPTR | $EF19 | Serial::ReceiveByte | routine | KV20, MTV, in prose: the name's Also: is its jump-table entry's; spelling only: V20PRG | channelio:1, load:3, vectors:1 | ACPTR: a byte from the talker: A = it, carry clear; IoStatus gets $40 at EOI, $02 on a timeout. Interrupts off meanwhile. |
| 32 | ACP00A | $EF21 | Serial::ReceiveByte::WaitForTalker | local | KV20 | serial2.1:1 | Waits for the talker to release CLK, then releases DATA: ready. |
| 33 | EOIACP | $EF29 | Serial::ReceiveByte::StartTimer | local | KV20 | serial2.1:1 | Times 256 µs for the talker to pull CLK. |
| 34 | ACP00 | $EF2E | Serial::ReceiveByte::WaitForClock | local | KV20 | serial2.1:1 | Until CLK is pulled or the time is up. |
| 35 | ACP00B | $EF3C | Serial::ReceiveByte::TimedOut | local | KV20 | serial2.1:1 | Out of time twice is a read timeout. |
| 36 | ACP00C | $EF45 | Serial::ReceiveByte::Eoi | local | KV20 | serial2.1:1 | Out of time once is EOI: acknowledges it by pulsing DATA, and waits again. |
| 37 | ACP01 | $EF54 | Serial::ReceiveByte::ReadBits | local | KV20 | serial2.1:1 | Eight bits. |
| 38 | ACP03 | $EF58 | Serial::ReceiveByte::WaitClockHigh | local | KV20 | serial2.1:3 | Each bit is taken as CLK is released. |
| 39 | ACP03A | $EF66 | Serial::ReceiveByte::WaitClockLow | local | KV20 | serial2.1:2 | And CLK pulled again. |
| 40 | ACP04 | $EF7F | Serial::ReceiveByte::Done | local | KV20 | serial2.1:1 | Pulls DATA to accept the byte (releasing it after EOI), and returns it. |
| 41 | CLKHI | $EF84 | Serial::ReleaseClock | routine | KV20 | init:1, serial2.1:6 | Lets the CLK line go high: VIA 2's CA2 low, through the inverter. |
| 42 | CLKLO | $EF8D | Serial::PullClock | routine | KV20 | init:1, serial2.1:3 | Pulls CLK low: CA2 high. |
| 43 | DATAHI | $E4A0 | Serial::ReleaseData | routine | KV20 | serial2.1:6 | Lets DATA go high: VIA 2's CB2 low. In the patch area at $E4A0, moved there for room. |
| 44 | DATALO | $E4A9 | Serial::PullData | routine | KV20 | serial2.1:4 | Pulls DATA low: CB2 high. |
| 45 | DEBPIA | $E4B2 | Serial::ReadLines | routine | KV20 | serial2.1:9 | Reads VIA 1's port A until two reads agree: A = it shifted right once, carry = CLK, bit 0 = DATA. |
| 46 | W1MS | $EF96 | Serial::WaitOneMillisecond | routine | KV20 | serial2.1:1 | Waits 1 ms on VIA 2's timer 2. |
| 47 | W1MS1 | $EF9B | Serial::WaitOneMillisecond::Wait | local | KV20 | serial2.1:1 | Until the timer runs out. |
| 48 | AROUND | = * | DROP | constant | KV20 | serial2.1 | Where the code goes on after the patch area's routines; inline, named in prose. |
| 49 | KSP2 | = * | DROP | constant | KV20 | serial2.1 | The patch area's free space after ReadLines; inline, named in prose. |

## Part 4: the tape

Accepted by the owner on 2026-11-25, with every question as recommended (K8); Q1's corrections are made in
part 1's rows, and its second names added at the end of this part's.

The listing's `TAPEFILE`, `TAPECONTROL`, `READ` and `WRITE`, `$F7AF-$FD21`: 111 labels and four
constants, IoStatus's tape error bits. *Mapping the VIC* gives FAH, TAPEH, LDAD1, JTP20, CS10, RBLK, WBLK, TAPE,
TSTOP, STT1, READ, RD300, NEWCH, WRITE, WRTZ and TNIF by their addresses.

### Questions

- K-P4-Q1. **Corrections to part 1.** The read routines' own comments, which part 1 did not have, say eight of the
  tape's bytes do something else, or a second job, than part 1's reasons said. *Recommended*: fix them now, before
  any conversion:
  - DIFF (`$B5`, part 1's row 57) is not a bit difference: it keeps a copy of the block-sync flag between the bit
    routines. `Tape::BitDifference` becomes `Tape::BlockSyncSaved`.
  - PRP (`$B6`, row 59) is not a pulse kind: it holds the byte's errors and zero count combined, for the byte handler.
    `Tape::PulseKind` becomes `Tape::ByteErrors`.
  - SYNO (`$96`, row 16) is set once 16 more short pulses than long have come (about 8 zero dipoles): block
    sync. `Tape::BlockSync` stays; its reason is corrected.
  - DPSW (`$9C`, row 22) is set by the byte marker, to finish the byte at the next timeout ("bit throw away flag").
    `Tape::ByteReceived` becomes `Tape::ByteMarkerSeen`.
  - SHCNL and SHCNH (`$A7` and `$AB`) have second jobs. While reading, SHCNL counts the copies left to read (`Tape::CopiesLeft`), and
    after the load SHCNH holds the checksum being worked out (`Tape::LoadChecksum`). While writing they are the
    leader's count, as part 1 has them. So each gets a second name for that job, as K-P1-Q2 does for two families.
    Likewise RER and REZ, while writing, say whether the byte marker's long and one halves are written
    (`Tape::MarkerLongWritten`, `Tape::MarkerOneWritten`).
- K-P4-Q2. **The interrupts are routines.** READ, WRTN with WRTL3, and WRTZ are what the IRQ vector points at
  during tape work (`SetIrqVector`'s table, part 7): `Tape::ReadInterrupt`, `Tape::WriteData` (with
  `Interrupt` its vector's entry, since WRTL3 comes first in the code) and `Tape::WriteLeader`. The read's byte
  handler is part of `ReadInterrupt`, as the listing has it inline. *Recommended.*
- K-P4-Q3. **The error bits are IoStatus constants**, `STATUS_SHORT_BLOCK`, `STATUS_LONG_BLOCK`,
  `STATUS_SECOND_PASS_ERROR` and `STATUS_CHECKSUM_ERROR`, in the shared variables' file with IoStatus's
  other bits, which parts 3 and 6 name (the serial bus's timeouts, EOI and device not present). *Recommended.*

### Rows

| # | Old | Address | New | Kind | Documents (checked) | Used in | Reason |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | FAH | $F7AF | Tape::FindHeader | routine | KV20, MTV | load:1, open:1, tapefile:2 | Reads blocks until a header: a program, a fixed program or a data file's. Carry clear and X = its type; carry set at the end of the tape or STOP (A = VerifyFlag for STOP, 0 or 1). Prints FOUND and the name. |
| 2 | FAH50 | $F7CE | Tape::FindHeader::Found | local | KV20 | tapefile:2 | A header: X = its type, and FOUND with its name when messages are on. |
| 3 | FAH55 | $F7DA | Tape::FindHeader::PrintName | local | KV20 | tapefile:1 | The header's 16 characters of name. |
| 4 | FAH45 | $F7E4 | Tape::FindHeader::Success | local | KV20 | tapefile:1 | Carry clear. |
| 5 | FAH40 | $F7E6 | Tape::FindHeader::Done | local | KV20 | tapefile:2 | Returns. |
| 6 | TAPEH | $F7E7 | Tape::WriteHeader | routine | KV20, MTV | close:1, open:1, save:2 | Writes a header of type A: the start and end addresses, the file name, padded with spaces, with a long leader. Carry clear if done; the program's addresses are kept. |
| 7 | BLNK2 | $F7FE | Tape::WriteHeader::Blank | local | KV20 | tapefile:1 | Fills the buffer with spaces. |
| 8 | TH20 | $F822 | Tape::WriteHeader::CopyName | local | KV20 | tapefile:1 | Copies the file name after the addresses. |
| 9 | TH30 | $F834 | Tape::WriteHeader::Write | local | KV20 | tapefile:1 | Writes the buffer as a block. |
| 10 | TH40 | $F84C | Tape::WriteHeader::Done | local | KV20 | tapefile:1 | Returns. |
| 11 | ZZZ | $F84D | Tape::BufferAddress | routine | KV20 | close:1, load:1, open:1, save:1, tapecontrol:1, tapefile:2 | X and Y = TapeBuffer; carry clear if the buffer has been taken away (its high byte 0 or 1). |
| 12 | LDAD1 | $F854 | Tape::BufferBounds | routine | KV20, MTV | tapecontrol:2, tapefile:1 | Tape::LoadAddress and EndAddress = the tape buffer's start and end, to read or write a header. |
| 13 | FAF | $F867 | Tape::FindFile | routine | KV20 | load:1, open:1, tapefile:1 | Reads headers until one whose name starts with FileName: carry clear; carry set as FindHeader fails. |
| 14 | FAF20 | $F874 | Tape::FindFile::Compare | local | KV20 | tapefile:1 | Compares each character of the name. |
| 15 | FAF30 | $F888 | Tape::FindFile::Found | local | KV20 | tapefile:1 | Carry clear. |
| 16 | FAF40 | $F889 | Tape::FindFile::Done | local | KV20 | tapefile:1 | Returns. |
| 17 | JTP20 | $F88A | Tape::NextBufferByte | routine | KV20, MTV | channelio:2 | BufferIndex up one: Y = it, carry set at the buffer's end. |
| 18 | CSTE1 | $F894 | Tape::WaitForPlay | routine | KV20 | load:1, open:1, tapecontrol:1 | PRESS PLAY ON TAPE until a key is down, then OK; carry set if STOP is pressed instead. |
| 19 | CS30 | $F89B | Tape::WaitForPlay::Prompt | entry | KV20 | tapecontrol:1 | Prints the prompt in Y (WaitForRecord enters here). |
| 20 | CS40 | $F89E | Tape::WaitForPlay::Wait | local | KV20 | tapecontrol:1 | Watches STOP and the cassette's keys. |
| 21 | CS10 | $F8AB | Tape::KeysDown | routine | KV20, MTV | tapecontrol:3 | Zero set while a cassette key is down (VIA 1's PA6 low); carry clear. |
| 22 | CS25 | $F8B5 | Tape::KeysDown::Done | entry | KV20 | tapecontrol:3 | Carry clear (the prompts return here). |
| 23 | CSTE2 | $F8B7 | Tape::WaitForRecord | routine | KV20; spelling only: MTV | open:1, save:1, tapecontrol:1 | PRESS RECORD & PLAY ON TAPE, as WaitForPlay. |
| 24 | RBLK | $F8C0 | Tape::ReadHeader | routine | KV20, MTV | channelio:1, tapefile:1 | Reads a block into the tape buffer: clears IoStatus and VerifyFlag, and falls into ReadBlock. |
| 25 | TRD | $F8C9 | Tape::ReadBlock | routine | KV20 | load:1 | Reads a block to Tape::LoadAddress-EndAddress: asks for PLAY, then runs the read interrupt until both copies are in. |
| 26 | WBLK | $F8E3 | Tape::WriteBuffer | routine | KV20, MTV | channelio:1, close:1 | Writes the tape buffer as a block, and falls into WriteBlock. |
| 27 | TWRT | $F8E6 | Tape::WriteBlock | routine | KV20 | save:1 | Writes Tape::LoadAddress-EndAddress as a block, twice, with a short leader; asks for RECORD and PLAY. |
| 28 | TWRT2 | $F8EA | Tape::WriteBlock::WithLeader | entry | KV20 | tapefile:1 | With the leader the caller set (WriteHeader's is long). |
| 29 | TWRT3 | $F8ED | Tape::WriteBlock::Begin | entry | KV20 | tapecontrol:1 | STOP gave up the prompt, or starts the write's interrupts (ReadBlock enters here for its stop). |
| 30 | TAPE | $F8F4 | Tape::Run | routine | KV20, MTV; spelling only: V20PRG | tapecontrol:2, tapefile:1, write:1 | Starts a tape operation: takes over the IRQ (keeping the vector in SavedIrq), turns the motor on, and waits until the interrupts are done or STOP is pressed. |
| 31 | TP32 | $F923 | Tape::Run::Delay | local | KV20 | tapecontrol:1 | A delay for the motor's start. |
| 32 | TP35 | $F925 | Tape::Run::DelayInner | local | KV20 | tapecontrol:1 | The delay's inner count. |
| 33 | TP40 | $F92F | Tape::Run::WaitDone | local | KV20 | tapecontrol:2 | Until the IRQ vector is back, watching STOP and keeping the jiffy clock. |
| 34 | TSTOP | $F94B | Tape::CheckStop | routine | KV20, MTV | tapecontrol:2 | If STOP is down, stops the tape and returns to the caller's caller with carry set; carry clear otherwise. |
| 35 | STOP3 | $F957 | Tape::CheckStop::ReleaseIrq | entry | KV20 | tapecontrol:2 | SavedIrq is free again (Run and WriteBlock end here). |
| 36 | STOP4 | $F95C | Tape::CheckStop::Done | local | KV20 | tapecontrol:1 | Returns. |
| 37 | STT1 | $F95D | Tape::SetTimeout | routine | KV20, MTV | read:4 | Sets VIA 2's timer 1 to time out the next dipole: X, corrected for the tape's speed (TimeCorrection). |
| 38 | STT2 | $F972 | Tape::SetTimeout::Scale | local | KV20 | tapecontrol:1 | Times four. |
| 39 | STT3 | $F979 | Tape::SetTimeout::WaitTimer | local | KV20 | tapecontrol:1 | Not while timer 2's high byte is about to change. |
| 40 | READ | $F98E | Tape::ReadInterrupt | routine | KV20, MTV; spelling only: V20PRG | init:1, kernal:1, read:3 | The IRQ while reading: times each pulse on VIA 2's timer 2, decodes dipoles into bits and bytes, and hands each byte to its byte handler. |
| 41 | RJDJ | $F9C3 | Tape::ReadInterrupt::ClassifyPulse | local | KV20 | read:1 | A short, a one, or a long-long (the byte marker), from the pulse's length. |
| 42 | JRAD2 | $F9E2 | Tape::ReadInterrupt::ToLongLong | local | KV20 | read:2 | On to LongLong. |
| 43 | SRER | $F9E5 | Tape::ReadInterrupt::SetError | local | KV20 | read:3 | A pulse out of range, once synchronized, is an error. |
| 44 | RADX2 | $F9ED | Tape::ReadInterrupt::Short | local | KV20 | read:1 | A short: ZeroesCount up. |
| 45 | RADL | $F9F1 | Tape::ReadInterrupt::One | local | KV20 | read:2 | A one: ZeroesCount down. |
| 46 | RAD5 | $F9F3 | Tape::ReadInterrupt::Servo | local | KV20 | read:1 | TimingAdjust tracks how far the pulse is from its ideal; the dipole's half flips. |
| 47 | RDBK | $FA06 | Tape::ReadInterrupt::CheckTimer | local | KV20 | read:6 | Timer 1 ran out: the end of a bit. |
| 48 | RADP | $FA19 | Tape::ReadInterrupt::CheckParity | local | KV20 | read:1 | The parity bit: odd parity is an error. |
| 49 | RADBK | $FA22 | Tape::ReadInterrupt::Return | local | KV20 | read:3 | Returns from the interrupt. |
| 50 | RAD3 | $FA25 | Tape::ReadInterrupt::SecondHalf | local | KV20 | read:1 | The dipole's second half: adjusts TimeCorrection by TimingAdjust. |
| 51 | ROUT2 | $FA2E | Tape::ReadInterrupt::Slower | local | KV20 | read:1 | More time a pulse. |
| 52 | ROUT1 | $FA30 | Tape::ReadInterrupt::CompareHalves | local | KV20 | read:1 | Like halves: two zeros count toward block sync, two ones are an error. |
| 53 | RAD4 | $FA47 | Tape::ReadInterrupt::DataBit | local | KV20 | read:2 | A data bit: shifted into ByteBuffer, with the parity. |
| 54 | RAD2 | $FA60 | Tape::ReadInterrupt::LongLong | local | KV20 | read:1 | A long-long pulse: a byte marker, or a long one inside a byte. |
| 55 | RAD2Y | $FA68 | Tape::ReadInterrupt::EndOfByte | local | KV20 | read:1 | Within a byte, a long is a one. |
| 56 | RAD2X | $FA6C | Tape::ReadInterrupt::ByteMarker | local | KV20 | read:1 | A byte marker: times the last bit, and synchronizes on the first after the leader. |
| 57 | RADQ2 | $FA91 | Tape::ReadInterrupt::PassByte | local | KV20 | read:1 | Keeps block sync in BlockSyncSaved; leaves byte sync at the block's end. |
| 58 | RADK | $FAA0 | Tape::ReadInterrupt::HandBack | local | KV20 | read:1 | OutputCharacter = the byte, ByteErrors = its errors. |
| 59 | RDBK2 | $FAAA | Tape::ReadInterrupt::ReturnFromMarker | local | KV20 | read:1 | Returns; the byte is handled after its last bit. |
| 60 | RADJ | $FAAD | Tape::ReadInterrupt::FinishByte | local | KV20 | read:1 | The last bit's time: a new byte begins, and the finished one goes to the byte handler. |
| 61 | RD15 | $FABD | Tape::ReadInterrupt::HandleByte | local | KV20 | read:1 | The byte handler: by ReadMode, waits for the leader's zeros, counts the countdown down, or stores the byte. |
| 62 | RD12 | $FAD3 | Tape::ReadInterrupt::WaitForSync | local | KV20 | read:1 | Zeros found: wait for the countdown. |
| 63 | RD10 | $FAD7 | Tape::ReadInterrupt::Exit | local | KV20 | read:7 | Returns from the interrupt. |
| 64 | RD20 | $FADA | Tape::ReadInterrupt::Mode | local | KV20 | read:1 | Loading, or counting down. |
| 65 | RD22 | $FAF0 | Tape::ReadInterrupt::CheckBlock | local | KV20 | read:1 | The countdown byte says which copy this is: the one wanted is read. |
| 66 | RD200 | $FAF6 | Tape::ReadInterrupt::Countdown | local | KV20 | read:1 | Counts the countdown to the data; then sets the addresses. |
| 67 | RD40 | $FB07 | Tape::ReadInterrupt::IgnoreBytes | local | KV20 | read:2 | Not the copy wanted: ignore bytes until the next leader. |
| 68 | RD60 | $FB0D | Tape::ReadInterrupt::Loading | local | KV20 | read:1 | Block sync in the data is a short block. |
| 69 | RD70 | $FB1B | Tape::ReadInterrupt::CheckEnd | local | KV20 | read:1 | Past the end, the block is done. |
| 70 | RD80 | $FB38 | Tape::ReadInterrupt::LogError | local | KV20 | read:2 | A byte in error on the first copy is logged in BadBytes, up to 31. |
| 71 | RD58 | $FB55 | Tape::ReadInterrupt::SecondPass | local | KV20 | read:1 | The second copy: only the logged addresses are taken again. |
| 72 | RD52 | $FB7C | Tape::ReadInterrupt::CheckRetry | local | KV20 | read:1 | Still in error is a second pass error. |
| 73 | RD55 | $FB80 | Tape::ReadInterrupt::SecondPassError | local | KV20 | read:1 | IoStatus gets STATUS_SECOND_PASS_ERROR. |
| 74 | RD59 | $FB87 | Tape::ReadInterrupt::StoreByte | local | KV20 | read:3 | Stores the byte, unless verifying. |
| 75 | RD90 | $FB90 | Tape::ReadInterrupt::Advance | local | KV20 | read:6 | On to the next address. |
| 76 | RD160 | $FB95 | Tape::ReadInterrupt::BlockEnd | local | KV20 | read:1 | The block's end: skip bytes until the next. |
| 77 | RD161 | $FB97 | Tape::ReadInterrupt::SetMode | local | KV20 | read:1 | ReadMode = A; the next copy. |
| 78 | RD167 | $FBA0 | Tape::ReadInterrupt::NextPass | local | KV20 | read:1 | With no errors on the first copy, the second is still read, with nothing taken from it. |
| 79 | RD175 | $FBAC | Tape::ReadInterrupt::AllRead | local | KV20 | read:1 | Both copies read: stops the tape and checks the checksum. |
| 80 | VPRTY | $FBB6 | Tape::ReadInterrupt::Checksum | local | KV20; spelling only: MTV | read:1 | The exclusive or of every byte loaded, against the block's last byte; a mismatch is STATUS_CHECKSUM_ERROR. MTV spells VPRTY. |
| 81 | RD180 | $FBCF | Tape::ReadInterrupt::ToReturn | local | KV20 | read:4 | On to the return. |
| 82 | RD300 | $FBD2 | Tape::ResetAddress | routine | KV20, MTV | read:2, save:1, write:1 | StartAddress = Tape::LoadAddress: back to the block's start. |
| 83 | NEWCH | $FBDB | Tape::NewByte | routine | KV20, MTV | read:1, tapecontrol:1, write:2 | Clears the counters for a new byte: 8 bits, the dipole, the error, the parity and the zeros; A = 0. |
| 84 | WRITE | $FBEA | Tape::WritePulse | routine | KV20, MTV; spelling only: V20PRG | kernal:1, write:2 | Toggles the cassette's write line for half a dipole, short or long by OutputCharacter's low bit: zero set on the line's low half. |
| 85 | WRTW | $FBF1 | Tape::WritePulse::Long | entry | KV20 | write:1 | A long half. |
| 86 | WRT1 | $FBF3 | Tape::WritePulse::Time | entry | KV20 | write:2 | A half of length A. |
| 87 | WRTX | $FBF5 | Tape::WritePulse::TimeHigh | entry | KV20 | write:1 | A half of length X·256 + A. |
| 88 | WRTL3 | $FC06 | Tape::WriteData | routine | KV20 | write:1 | The IRQ while writing data: each byte as a marker, eight bits and parity, each bit a dipole; the countdown first, the checksum last. This first part marks the block's end. |
| 89 | WRTN | $FC0B | Tape::WriteData::Interrupt | entry | KV20; spelling only: MTV | init:1 | The vector's target: after each byte, the byte marker's long and one halves, then the bits. |
| 90 | WRTN1 | $FC21 | Tape::WriteData::NotLong | local | KV20; spelling only: MTV | write:1 | The marker's one half. |
| 91 | WRTN2 | $FC2E | Tape::WriteData::DataBit | local | KV20 | write:1 | A bit: its dipole's two halves, the second the complement. |
| 92 | WRT3 | $FC47 | Tape::WriteData::Return | local | KV20 | write:10 | Returns from the interrupt. |
| 93 | WRT2 | $FC4A | Tape::WriteData::NextBit | local | KV20 | write:1 | The next bit, then the parity. |
| 94 | WRTS | $FC54 | Tape::WriteData::NextByte | entry | KV20 | write:1 | A new byte: from the countdown, then the data. |
| 95 | WRTS1 | $FC60 | DROP | local | KV20 | none | Not referenced; no document names it. |
| 96 | WRT61 | $FC6A | Tape::WriteData::CountByte | local | KV20 | write:1 | The countdown byte (9 to 1, with bit 7 set on the first copy). |
| 97 | WRT6 | $FC6E | Tape::WriteData::DataByte | local | KV20 | write:1 | Past the end, the checksum, then the end mark. |
| 98 | WRT7 | $FC7D | Tape::WriteData::FetchByte | local | KV20 | write:1 | The next byte, added to the checksum. |
| 99 | WRT4 | $FC8C | Tape::WriteData::ParityBit | local | KV20 | write:1 | The parity bit. |
| 100 | WRTBK | $FC92 | Tape::WriteData::ToReturn | entry | KV20 | write:5 | On to the return. |
| 101 | WRNC | $FC95 | Tape::WriteData::BlockDone | local | KV20 | write:1 | The block written: the motor stops after the last copy. |
| 102 | WREND | $FC9C | Tape::WriteData::Trailer | local | KV20 | write:1 | 80 short pulses after the block, through WriteLeader. |
| 103 | WRTZ | $FCA8 | Tape::WriteLeader | routine | KV20, MTV | init:1 | The IRQ while writing a leader or trailer of short pulses; then the data's interrupt, or the end. |
| 104 | STKY | $FCF6 | Tape::AllWritten | routine | KV20 | write:1 | The last trailer: Finish. Its own routine, since its code follows Tape::Finish (Vic20.md, step 4). |
| 105 | TNIF | $FCCF | Tape::Finish | routine | KV20, MTV | read:1, tapecontrol:1, write:1 | Ends a tape operation: the motor off, VIA 2's interrupts and timers back to the keyboard's, and the IRQ vector restored from SavedIrq. |
| 106 | TNIQ | $FCF4 | Tape::Finish::Done | local | KV20 | write:1 | Restores the status and returns. |
| 107 | BSIV | $FCFB | Tape::SetIrqVector | routine | KV20; spelling only: MTV | tapecontrol:1, write:2 | Points the IRQ vector at the tape's interrupt X picks: 8 the leader, 10 the data, 12 the keyboard, 14 reading. |
| 108 | TNOF | $FD08 | Tape::MotorOff | routine | KV20 | write:2 | Turns the cassette motor off: VIA 1's CA2 high. |
| 109 | CMPSTE | $FD11 | Tape::CompareAddresses | routine | KV20 | read:2, save:1, write:1 | Compares StartAddress with EndAddress: carry set at the end. SAVE and the tape's read and write use it. |
| 110 | INCSAL | $FD1B | Tape::NextAddress | routine | KV20 | read:2, save:1, write:1 | StartAddress up one. |
| 111 | INCR | $FD21 | Tape::NextAddress::Done | local | KV20 | write:1 | Returns. |
| 112 | SPERR | = 16 | STATUS_SECOND_PASS_ERROR | constant | KV20 | read | IoStatus's bit for bytes the second copy got wrong too. |
| 113 | CKERR | = 32 | STATUS_CHECKSUM_ERROR | constant | KV20 | read | IoStatus's bit for a block whose checksum is wrong. |
| 114 | SBERR | = 4 | STATUS_SHORT_BLOCK | constant | KV20 | read | IoStatus's bit for a block that ended early. |
| 115 | LBERR | = 8 | STATUS_LONG_BLOCK | constant | KV20 | read | IoStatus's bit for a block longer than asked for. |
| 116 | (none: the second job of SHCNL's byte, part 1's row 38) | $00A7 | Tape::CopiesLeft | location | — (SHCNL in prose) | read, write | Reading: the block's copies still to read, which steers the byte handler (the listing's comment). (Added by K-P4-Q1.) |
| 117 | (none: the second job of SHCNH's byte, part 1's row 46) | $00AB | Tape::LoadChecksum | location | — (SHCNH in prose) | read, write | After a load: the exclusive or of the bytes loaded, against the block's checksum. (Added by K-P4-Q1.) |
| 118 | (none: the second job of RER's byte, part 1's row 40) | $00A8 | Tape::MarkerLongWritten | location | — (RER in prose) | read, write | Writing: set once the byte marker's long half is written. (Added by K-P4-Q1.) |
| 119 | (none: the second job of REZ's byte, part 1's row 42) | $00A9 | Tape::MarkerOneWritten | location | — (REZ in prose) | read, write | Writing: set once the byte marker's one half is written. (Added by K-P4-Q1.) |

## Part 5: RS-232 and the NMI

Accepted by the owner on 2026-11-25, with every question as recommended (K9).

The listing's `RS232TRANS`, `RS232RCVR`, `RS232INOUT` and `RS232NMIFILE`, `$EFA3-$F177` and
`$FEA9-$FF71`: 71 labels and one constant. Only NMI has a document besides KV20 (MTV, by its address). The
VIC-20 makes RS-232 in software on VIA 1's port B and its timers, as a 6551 would be programmed (part 1's
`Rs232::Control` and `Command`): timer 1's NMI sends each bit, CB1's edge finds a start bit, and timer 2's NMI
samples each received bit at its middle.

### Questions

- K-P5-Q1. **The NMI handler** is in the RS-232 listing's file, but it is the system's: `Interrupts::Nmi` (the
  processor's vector's target, which goes through NmiVector) and `Interrupts::NmiHandler` (NmiVector's default),
  in part 7's family. BRK's target, TIMB, sits inside it, where RESTORE with STOP falls into the warm start, so it is
  the entry `Interrupts::NmiHandler::Break` (X2), which BreakVector points at. The RS-232 work it calls stays in
  `Rs232`. *Recommended.*
- K-P5-Q2. **One exit, two names.** NMIRTI and PREND are the same address: the restore of the registers and the
  `RTI` that the NMI and the tape's interrupts end with. They are one entry, `Interrupts::NmiHandler::Return`,
  with both names in `Also:`. *Recommended.*
- K-P5-Q3. **The signals keep RS-232's own names** in the routine names and comments (DSR, CTS, RTS, DCD), as the
  style allows the hardware's short terms: `Rs232::SendError::ClearToSendLost` spells CTS out where it is the
  whole name, and comments use the abbreviations. *Recommended.*
- K-P5-Q4. **The baud rate tables** differ between the NTSC and PAL kernals, with the clock. Commodore wrote each
  entry as a rounded half bit time less CBIT (the NTSC kernal's 10230, 6820, 4650 ... 142, the PAL kernal's 11082,
  7388, 5037 ... 154), which the exact formula, the clock over twice the baud rate, misses by up to 3.5 counts. So
  each standard's table is written out, Commodore's rounded figure less `START_BIT_LATENCY` per rate with the rate
  in a comment, under `.if PAL`. *Recommended.* The alternative, one table from the formula, would not assemble to
  the ROMs.

### Rows

| # | Old | Address | New | Kind | Documents (checked) | Used in | Reason |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | RSTRAB | $EFA3 | Rs232::SendNextBit | routine | KV20 | rs232nmifile:1 | On each timer 1 NMI, after the NMI has put NextBit on the line: works out the bit after it (data from the low bit, then parity and stop bits), or starts the next byte. |
| 2 | RST005 | $EFB0 | Rs232::SendNextBit::Parity | local | KV20 | rs232trans:1 | Adds the bit to the parity. |
| 3 | RSTEXT | $EFB9 | Rs232::SendNextBit::SetBit | local | KV20 | rs232trans:3 | NextBit = the bit, as bit 5 of VIA 1's peripheral control, which sets CB2, the send line. |
| 4 | RST010 | $EFBF | Rs232::SendNextBit::ParityBit | local | KV20 | rs232trans:1 | After the data, the parity Command asks for: none, odd, even, mark or space. |
| 5 | RSWEXT | $EFCE | Rs232::SendNextBit::Flip | local | KV20 | rs232trans:3 | The guess was wrong: a one. |
| 6 | RSPEXT | $EFCF | Rs232::SendNextBit::StopBits | local | KV20 | rs232trans:3 | Then one or two stop bits, as Control says. |
| 7 | RSPNO | $EFDA | Rs232::SendNextBit::NoParity | local | KV20 | rs232trans:1 | No parity: a stop bit in its place. |
| 8 | RST030 | $EFDE | Rs232::SendNextBit::Even | local | KV20 | rs232trans:1 | Even parity. |
| 9 | RST040 | $EFE4 | Rs232::SendNextBit::Fixed | local | KV20 | rs232trans:1 | Mark or space. |
| 10 | RST050 | $EFE8 | Rs232::SendNextBit::StopBit | local | KV20 | rs232trans:1 | A stop bit: a one. |
| 11 | RSTBGN | $EFEE | Rs232::StartByte | routine | KV20 | rs232inout:1, rs232trans:1 | Starts sending the next byte from the output buffer: checks DSR and CTS with x-line handshaking, then a start bit; stops sending when the buffer is empty. |
| 12 | RST060 | $EFFB | Rs232::StartByte::NoHandshake | local | KV20 | rs232trans:1 | The parity cleared, a start bit, and the word's bit count. |
| 13 | RST070 | $F004 | DROP | local | KV20 | none | Not referenced; no document names it. |
| 14 | RST080 | $F006 | DROP | local | KV20 | none | Not referenced; no document names it. |
| 15 | DSRERR | $F016 | Rs232::SendError | routine | KV20 | open:1, rs232inout:1, rs232trans:1 | DSR has gone: Status gets $40; sending stops (timer 1's NMI off). |
| 16 | CTSERR | $F019 | Rs232::SendError::ClearToSendLost | entry | KV20 | rs232trans:1 | CTS has gone: Status gets $10. |
| 17 | RSODNE | $F021 | Rs232::SendError::StopSending | entry | KV20 | rs232trans:1 | Turns timer 1's NMI off: nothing more to send (StartByte comes here with an empty buffer). |
| 18 | BITCNT | $F027 | Rs232::CountWordBits | routine | KV20 | open:1 | X = the word's bits plus one (9, 8, 7 or 6), from Control's word length. |
| 19 | BIT010 | $F031 | Rs232::CountWordBits::NotSeven | local | KV20 | rs232trans:1 | Bit 6 takes two more off. |
| 20 | BIT020 | $F035 | Rs232::CountWordBits::Done | local | KV20 | rs232trans:1 | Returns. |
| 21 | RSRCVR | $F036 | Rs232::ReceiveBit | routine | KV20 | rs232nmifile:1 | On each timer 2 NMI, with ReceivedBit sampled: a data bit into ReceivedByte and the parity, the parity checked, the stop bits; at the byte's end, into the input buffer. |
| 22 | RSREXT | $F04A | Rs232::ReceiveBit::Return | local | KV20 | rs232rcvr:4 | Returns. |
| 23 | RSR018 | $F04B | Rs232::ReceiveBit::NoParity | local | KV20 | rs232rcvr:1 | No parity bit: on to the stop bit. |
| 24 | RSR020 | $F04D | Rs232::ReceiveBit::StopBit | local | KV20 | rs232rcvr:1 | A stop bit must be a one; a zero is a frame error or a break. |
| 25 | RSRABL | $F05B | Rs232::ReceiveBit::Rearm | entry | KV20 | rs232rcvr:2 | Waits for the next start bit: CB1's NMI on, timer 2's off. |
| 26 | RSRSXT | $F062 | DROP | local | KV20 | none | Not referenced; no document names it. |
| 27 | RSRTRT | $F068 | Rs232::ReceiveBit::StartBit | local | KV20 | rs232rcvr:1 | The start bit's middle: a mark there was noise, so wait again. |
| 28 | RSR030 | $F06F | Rs232::ReceiveBit::StoreByte | local | KV20 | rs232rcvr:1 | The byte is in: stored at InputEnd, unless the buffer is full. |
| 29 | RSR031 | $F081 | Rs232::ReceiveBit::Align | local | KV20 | rs232rcvr:1 | Shifts a short word down to bit 0. |
| 30 | RSR032 | $F089 | Rs232::ReceiveBit::Store | local | KV20 | rs232rcvr:1 | Into the buffer; then the parity check Command asks for. |
| 31 | RSR050 | $F09D | Rs232::ReceiveBit::Even | local | KV20 | rs232rcvr:1 | Even parity. |
| 32 | RECERR | $F0A2 | Rs232::ReceiveBit::Overrun | local | KV20 | rs232rcvr:1 | The buffer is full: Status gets $04. |
| 33 | BREAKE | $F0A5 | Rs232::ReceiveBit::Break | local | KV20 | rs232rcvr:1 | A break, all zeros: $80. |
| 34 | FRAMEE | $F0A8 | Rs232::ReceiveBit::FrameError | local | KV20 | rs232rcvr:1 | A frame error: $02. |
| 35 | ERR232 | $F0AA | DROP | local | KV20 | none | Not referenced; no document names it. |
| 36 | RSR060 | $F0B3 | Rs232::ReceiveBit::CheckStop | local | KV20 | rs232rcvr:1 | A zero stop bit: a break if the byte is all zeros, otherwise a frame error. |
| 37 | RS232 | $F0B9 | Rs232::NoLoadOrSave | routine | KV20; spelling only: V20PRG | load:1, open:1, rs232inout:4, save:1 | LOAD and SAVE on device 2: ILLEGAL DEVICE NUMBER. |
| 38 | CKO232 | $F0BC | Rs232::SelectOutput | routine | KV20 | openchannel:1 | CHKOUT for device 2: with x-line handshaking (Command's bit 0 alone), needs DSR, waits for the receiver to stop, raises RTS and waits for CTS; carry clear. |
| 39 | CKO020 | $F0CD | Rs232::SelectOutput::WaitInputDone | local | KV20 | rs232inout:1 | Until nothing is being received. |
| 40 | CKO030 | $F0D4 | Rs232::SelectOutput::WaitClearToSendOff | local | KV20 | rs232inout:1 | Until CTS is off. |
| 41 | CKO040 | $F0E1 | Rs232::SelectOutput::WaitClearToSend | local | KV20 | rs232inout:1 | Raises RTS and waits for CTS, while DSR holds. |
| 42 | CKDSRX | $F0E8 | Rs232::SelectOutput::DsrError | entry | KV20 | rs232inout:2 | No DSR: SendError (SelectInput comes here too). |
| 43 | CKO100 | $F0EB | Rs232::SelectOutput::Done | local | KV20 | rs232inout:3 | Carry clear. |
| 44 | BSO232 | $F0ED | Rs232::CharacterOut | routine | KV20 | channelio:1, rs232inout:1 | CHROUT to device 2: puts A in the output buffer, waiting while it is full, and starts the sender if it is idle. |
| 45 | BSO100 | $F0FC | DROP | local | KV20 | none | Not referenced; no document names it. |
| 46 | BSO110 | $F102 | Rs232::CharacterOut::StartSender | local | KV20 | rs232inout:1 | Starts timer 1 at the bit time, its NMI on, and the first byte. |
| 47 | CKI232 | $F116 | Rs232::SelectInput | routine | KV20 | openchannel:1 | CHKIN for device 2: with x-line handshaking and half duplex, waits for output to end, drops RTS and waits for the carrier, testing DTR (bit 2), not DCD (bit 4), so the wait ends at once; turns the start bit's NMI on. Carry clear. |
| 48 | CKI010 | $F12B | Rs232::SelectInput::WaitOutputDone | local | KV20 | rs232inout:1 | Until nothing is being sent. |
| 49 | CKI020 | $F138 | Rs232::SelectInput::WaitCarrier | local | KV20 | rs232inout:1 | Until the carrier, as the code tests it: DTR, bit 2, not DCD. |
| 50 | CKI080 | $F13F | Rs232::SelectInput::EnableStartBit | local | KV20 | rs232inout:1 | CB1's NMI on. |
| 51 | CKI090 | $F144 | Rs232::SelectInput::Done | local | KV20 | rs232inout:1 | Carry clear. |
| 52 | CKI100 | $F146 | Rs232::SelectInput::FullDuplex | local | KV20 | rs232inout:2 | Turns the receiver on unless it already runs. |
| 53 | BSI232 | $F14F | Rs232::CharacterIn | routine | KV20 | channelio:1 | CHRIN and GETIN from device 2: A = the next byte from the input buffer, or 0 if it is empty. |
| 54 | BSI010 | $F15D | Rs232::CharacterIn::Empty | local | KV20 | rs232inout:1 | A = 0. |
| 55 | RSP232 | $F160 | Rs232::Pause | routine | KV20 | serial2.1:1, tapecontrol:1 | Before the serial bus or the tape: waits for RS-232's timers to finish and turns its start bit's NMI off. A is kept. |
| 56 | RSPOFF | $F166 | Rs232::Pause::WaitDone | local | KV20 | rs232inout:1 | Until timers 1 and 2 are idle. |
| 57 | RSPOK | $F172 | Rs232::Pause::Done | local | KV20 | rs232inout:1 | Restores A. |
| 58 | NMI | $FEA9 | Interrupts::Nmi | routine | KV20, MTV; spelling only: V20PRG | rs232nmifile:1, vectors:1 | The processor's NMI vector's target: interrupts off, then through NmiVector. |
| 59 | NNMI | $FEAD | Interrupts::NmiHandler | routine | KV20 | init:1 | NmiVector's default: RESTORE (a cartridge's NMI, or with STOP a warm start) and RS-232's bits and start bits. |
| 60 | NNMI10 | $FEB2 | DROP | local | KV20 | none | Not referenced; no document names it. |
| 61 | NNMI18 | $FEBF | DROP | local | KV20 | none | Not referenced; no document names it. |
| 62 | NNMI19 | $FEC7 | Interrupts::NmiHandler::StopKey | local | KV20 | rs232nmifile:1 | RESTORE without a cartridge: only with STOP down does the warm start follow. |
| 63 | TIMB | $FED2 | Interrupts::NmiHandler::Break | entry | KV20 | init:2 | BreakVector's default, and RESTORE with STOP: restores the vectors, the I/O and the screen, and warm-starts BASIC through $C002. |
| 64 | NNMI20 | $FEDE | Interrupts::NmiHandler::Rs232Bits | local | KV20 | rs232nmifile:1 | RS-232's NMIs, the others held off meanwhile (named so as not to shadow the Rs232 scope). |
| 65 | NMIRTN | $FEFF | Interrupts::NmiHandler::ToReturn | local | KV20 | rs232nmifile:2 | On to Return. |
| 66 | NNMI30 | $FF02 | Interrupts::NmiHandler::ReceiveTimer | local | KV20 | rs232nmifile:1 | Timer 2: samples the received bit, and times the next bit's middle. |
| 67 | NNMI40 | $FF2C | Interrupts::NmiHandler::StartBitEdge | local | KV20 | rs232nmifile:1 | CB1's edge: a start bit; timer 2 is set to its middle. |
| 68 | NNMI42 | $FF38 | Interrupts::NmiHandler::SetBaudTimer | local | KV20 | rs232nmifile:1 | Half a bit's time from BaudRates. |
| 69 | NMIRTI | $FF56 | Interrupts::NmiHandler::Return | entry | KV20 | rs232nmifile:3 | Restores Y, X and A and returns from the interrupt; the tape's interrupts end here too. |
| 70 | PREND | $FF56 | Interrupts::NmiHandler::Return | entry | KV20 | read:5, write:2 | The listing's second name for NMIRTI's address, which the tape's interrupts jump to. |
| 71 | BAUDO | $FF5C | Rs232::BaudRates | table | KV20 | open:2, rs232nmifile:2 | Half a bit's time in clock cycles for each standard baud rate, 50 to 3600, less START_BIT_LATENCY: the NTSC or PAL clock's. |
| 72 | CBIT | = 100 | START_BIT_LATENCY | constant | KV20 | rs232nmifile | About the time to take the start bit's NMI, in µs, taken off BaudRates so timer 2 lands near each bit's middle. |

## Part 6: the channels, files, messages, errors and clock

The listing's `MESSAGES`, `CHANNELIO`, `OPENCHANNEL`, `CLOSE`, `CLALL`, `OPEN`, `LOAD`, `SAVE`,
`TIME` and `ERRORHANDLER`, `$F174-$F7AE` with the patches at `$E4BC-$E4FF`: 171 labels, four constants
(one row) and three new names. *Mapping the VIC* gives SPMSG, SAVING, UDTIM, RDTIM and SETTIM by their addresses.

Settled by the owner's leave (K10): the owner left this part's questions and part 7's to the drafter's judgement on
2026-11-25, so each is settled as recommended.

### Questions

- K-P6-Q1. **The RAM vectors' defaults are the family's routines**, named for the call: NBSOUT is
  `Channels::CharacterOut`, NCHKIN `Channels::SelectInput`, NLOAD `Channels::Load`. The jump table's entries
  (part 7) are the `Kernal` names BASIC already calls (`KernalCharacterOut`), each going through its vector.
  LOAD and SAVE's own jump-table targets, which set the address and go through the vector, are
  `Channels::LoadToAddress` and `SaveRange`, with `LoadThroughVector` and `SaveThroughVector` the
  vectored jumps. *Settled as recommended.*
- K-P6-Q2. **The messages** are one table, `Channels::Messages` (MS1, whose first entry is I/O ERROR #), with each
  message `<Name>Message` as the BASIC conversion's X4 names them; the code selects one by its offset from
  `Messages`. *Settled as recommended.*
- K-P6-Q3. **The kernal's errors.** ERROR1-ERROR9 are entries of one routine, `Channels::Error`, each loading its
  number and skipping the rest with `$2C`: `Error::TooManyFiles` (at its start) to `Error::IllegalDevice`.
  The numbers get constants, `KERNAL_ERROR_TOO_MANY_FILES` to `KERNAL_ERROR_ILLEGAL_DEVICE` (new names: the
  listing gives them only in comments). *Settled as recommended.*
- K-P6-Q4. **What 901486-06 and -07 changed.** The listing's STOP-key patch, STPTCH and ITSSET, is in neither ROM:
  their clock routine stores the row itself again, and the patch area at `$E4CF` holds a fix to CLOSE instead, which no
  listing names: `Channels::CloseTapePatch`, a new name. The two dropped names are kept in prose, as the
  listing's. Where the ROMs differ from the listing elsewhere, the conversion names what they have.
  *Settled as recommended.*
- K-P6-Q5. **No local shadows a family.** Locals that would read as the families (`Load::Tape`,
  `SelectInput::Serial`, part 5's `NmiHandler::Rs232`) are `OnTape`, `SerialDevice` and `Rs232Bits`
  instead, as ConvertingSources.md asks. *Settled as recommended.*

### Rows

| # | Old | Address | New | Kind | Documents (checked) | Used in | Reason |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | MS1 | $F174 | Channels::Messages | table | KV20 | errorhandler:1, load:4, messages:1, save:1, tapecontrol:3, tapefile:1 | The kernal's messages, each ending in a character with bit 7 set; the first is I/O ERROR #, and the others are found by their offset from here. |
| 2 | MS5 | $F180 | Channels::SearchingMessage | message | KV20 | load:1 | SEARCHING. |
| 3 | MS6 | $F18B | Channels::ForMessage | message | KV20 | load:1 | FOR, before the name. |
| 4 | MS7 | $F18F | Channels::PressPlayMessage | message | KV20 | tapecontrol:1 | PRESS PLAY ON TAPE. |
| 5 | MS8 | $F1A2 | Channels::PressRecordMessage | message | KV20 | tapecontrol:1 | PRESS RECORD & PLAY ON TAPE. |
| 6 | MS10 | $F1BD | Channels::LoadingMessage | message | KV20 | load:1 | LOADING. |
| 7 | MS11 | $F1C5 | Channels::SavingMessage | message | KV20 | save:1 | SAVING. |
| 8 | MS21 | $F1CD | Channels::VerifyingMessage | message | KV20 | load:1 | VERIFYING. |
| 9 | MS17 | $F1D7 | Channels::FoundMessage | message | KV20 | tapefile:1 | FOUND. |
| 10 | MS18 | $F1DE | Channels::OkMessage | message | KV20 | tapecontrol:1 | OK. |
| 11 | SPMSG | $F1E2 | Channels::PrintControlMessage | routine | KV20, MTV | load:1 | Prints message Y when MessageMode's bit 7 lets the control messages through; carry clear. |
| 12 | MSG | $F1E6 | Channels::PrintControlMessage::Always | entry | KV20; spelling only: MTV | errorhandler:1, load:2, messages:1, save:1, tapecontrol:2, tapefile:1 | Prints message Y through CHROUT, whatever MessageMode says. |
| 13 | MSG10 | $F1F3 | Channels::PrintControlMessage::Done | local | KV20 | messages:1 | Carry clear. |
| 14 | NGETIN | $F1F5 | Channels::GetInput | routine | KV20 | init:1 | GetInputVector's default, GETIN: a character from the input device without waiting: the keyboard buffer's next, or zero set when it is empty; RS-232's next; others as CHRIN. |
| 15 | GN10 | $F201 | Channels::GetInput::NotKeyboard | local | KV20 | channelio:1 | RS-232, or on to CHRIN. |
| 16 | GN232 | $F205 | Channels::GetInput::FromRs232 | entry | KV20 | channelio:1 | RS-232's next byte, Y kept (CharacterIn comes here too). |
| 17 | NBASIN | $F20E | Channels::CharacterIn | routine | KV20 | init:1 | CharacterInVector's default, CHRIN: the next character from the input device; from the keyboard a whole line is typed first. Carry set with an error from the tape. |
| 18 | BN10 | $F21D | Channels::CharacterIn::NotKeyboard | entry | KV20 | channelio:2 | The screen: the line the cursor is on is read (GetInput comes here for devices other than the keyboard and RS-232). |
| 19 | BN20 | $F22A | Channels::CharacterIn::NotScreen | local | KV20 | channelio:1 | The tape, RS-232 or the serial bus. |
| 20 | JTG35 | $F244 | Channels::CharacterIn::TapeCharacter | local | KV20 | channelio:1 | Returns the character read, X kept; a zero after it is the end of the file, $40 in IoStatus. |
| 21 | JTG36 | $F24A | Channels::CharacterIn::TapeError | local | KV20 | channelio:1 | An error reading the next: the character is dropped. |
| 22 | JTG37 | $F24D | Channels::CharacterIn::TapeReturn | local | KV20 | channelio:1 | Returns with the error, X kept. |
| 23 | JTGET | $F250 | Channels::CharacterIn::NextTapeByte | entry | KV20 | channelio:3 | The tape buffer's next byte, reading the next block when it is used up. |
| 24 | JTG10 | $F260 | Channels::CharacterIn::FromBuffer | local | KV20 | channelio:1 | A = the byte, carry clear. |
| 25 | BN30 | $F264 | Channels::CharacterIn::FromSerial | local | KV20 | channelio:1 | The serial bus: after an error, RETURN. |
| 26 | BN31 | $F26A | Channels::CharacterIn::Done | entry | KV20 | channelio:1 | Carry clear (GetInput comes here with an empty keyboard buffer). |
| 27 | BN32 | $F26B | Channels::CharacterIn::Return | local | KV20 | channelio:1 | Returns. |
| 28 | BN35 | $F26C | Channels::CharacterIn::ReceiveByte | local | KV20 | channelio:1 | On to Serial::ReceiveByte. |
| 29 | BN50 | $F26F | Channels::CharacterIn::FromRs232 | local | KV20 | channelio:2 | Waits for a byte that isn't 0. |
| 30 | BN52 | $F279 | Channels::CharacterIn::Rs232Done | local | KV20 | channelio:1 | Returns. |
| 31 | NBSOUT | $F27A | Channels::CharacterOut | routine | KV20 | init:1 | CharacterOutVector's default, CHROUT: A to the output device: the screen, the serial bus, the tape buffer (writing a block when it fills) or RS-232. A, X and Y are kept. |
| 32 | BO10 | $F285 | Channels::CharacterOut::NotScreen | local | KV20 | channelio:1 | The serial bus: Serial::SendByte. |
| 33 | BO20 | $F28B | Channels::CharacterOut::NotSerial | local | KV20 | channelio:1 | RS-232 or the tape. |
| 34 | CASOUT | $F290 | Channels::CharacterOut::ToTape | entry | KV20 | close:1 | Into the tape buffer (Close comes here for the end of file's zero). |
| 35 | JTP10 | $F2AA | Channels::CharacterOut::Store | local | KV20 | channelio:1 | Stores the character in the buffer. |
| 36 | RSTOR | $F2AF | Channels::CharacterOut::Restore | local | KV20 | channelio:1 | Restores the registers; after STOP, A = 0 and carry set. |
| 37 | RSTOR1 | $F2B8 | Channels::CharacterOut::Done | local | KV20 | channelio:1 | Returns. |
| 38 | BO50 | $F2B9 | Channels::CharacterOut::ToRs232 | local | KV20 | channelio:1 | Rs232::CharacterOut, X and Y kept. |
| 39 | NCHKIN | $F2C7 | Channels::SelectInput | routine | KV20 | init:1 | SelectInputVector's default, CHKIN: makes logical file X the input: a serial device is made to talk. Carry set with FILE NOT OPEN, NOT INPUT FILE or DEVICE NOT PRESENT. |
| 40 | JX310 | $F2CF | Channels::SelectInput::Found | local | KV20 | openchannel:1 | The keyboard and the screen need nothing. |
| 41 | JX315 | $F2E3 | Channels::SelectInput::OnTape | local | KV20 | openchannel:1 | A tape file must be open for reading. |
| 42 | JX320 | $F2EC | Channels::SelectInput::SetDevice | local | KV20 | openchannel:4 | InputDevice = it; carry clear. |
| 43 | JX330 | $F2F0 | Channels::SelectInput::SerialDevice | local | KV20 | openchannel:1 | TALK, and the secondary address or the turnaround. |
| 44 | JX340 | $F2FE | Channels::SelectInput::SendSecondary | local | KV20 | openchannel:1 | The secondary address. |
| 45 | JX350 | $F301 | Channels::SelectInput::CheckPresent | local | KV20 | openchannel:1 | DEVICE NOT PRESENT if it did not answer. |
| 46 | NCKOUT | $F309 | Channels::SelectOutput | routine | KV20 | init:1 | SelectOutputVector's default, CHKOUT: makes logical file X the output: a serial device is made to listen. Carry set with FILE NOT OPEN, NOT OUTPUT FILE or DEVICE NOT PRESENT. |
| 47 | CK5 | $F311 | Channels::SelectOutput::Found | local | KV20 | openchannel:1 | The keyboard cannot be written. |
| 48 | CK20 | $F318 | Channels::SelectOutput::NotOutputFile | local | KV20 | openchannel:1 | NOT OUTPUT FILE. |
| 49 | CK10 | $F31B | Channels::SelectOutput::NotKeyboard | local | KV20 | openchannel:1 | The screen needs nothing. |
| 50 | CK15 | $F328 | Channels::SelectOutput::OnTape | local | KV20 | openchannel:1 | A tape file must be open for writing. |
| 51 | CK30 | $F32E | Channels::SelectOutput::SetDevice | local | KV20 | openchannel:2 | OutputDevice = it; carry clear. |
| 52 | CK40 | $F332 | Channels::SelectOutput::SerialDevice | local | KV20 | openchannel:1 | LISTEN, and the secondary address or ATN released. |
| 53 | CK50 | $F33F | Channels::SelectOutput::SendSecondary | local | KV20 | openchannel:1 | The secondary address. |
| 54 | CK60 | $F342 | Channels::SelectOutput::CheckPresent | local | KV20 | openchannel:1 | DEVICE NOT PRESENT if it did not answer. |
| 55 | NCLOSE | $F34A | Channels::Close | routine | KV20 | init:1 | CloseVector's default, CLOSE: closes logical file A: a tape file being written gets its end of file and last block (and an end-of-tape header for secondary address 2), a serial file its close command, RS-232 its buffers back; then the file leaves the tables. |
| 56 | JX050 | $F351 | Channels::Close::Found | local | KV20 | close:1 | By the device. |
| 57 | CLS010 | $F37F | Channels::Close::InputFreed | local | KV20 | close:1 | The input buffer's page back. |
| 58 | CLS020 | $F384 | Channels::Close::Deallocate | local | KV20 | close:1 | The output buffer's; the top of memory goes up. |
| 59 | JX115 | $F38D | Channels::Close::OnTape | local | KV20 | close:1 | A file being written: its end, and its last block. |
| 60 | JX120 | $F3AE | Channels::Close::SerialDevice | local | KV20 | close:1 | CloseSerialFile. |
| 61 | JX150 | $F3B1 | Channels::Close::RemoveEntry | local | KV20 | close:5 | Takes the file's table index back off the stack. |
| 62 | JXRMV | $F3B2 | Channels::Close::Remove | entry | KV20 | close:1 | Removes table entry A, moving the last entry into its place (RS-232 comes here). |
| 63 | JX170 | $F3CD | Channels::Close::Done | local | KV20 | close:2 | Carry clear. |
| 64 | LOOKUP | $F3CF | Channels::FindFile | routine | KV20 | open:1, openchannel:2 | Clears IoStatus and looks logical file X up in the tables: zero set if found, with X its index. |
| 65 | JLTLK | $F3D4 | Channels::FindFile::FileInA | entry | KV20 | close:1 | Looks up logical file A (Close enters here). |
| 66 | JX600 | $F3D6 | Channels::FindFile::Next | local | KV20 | close:1 | Each entry, from the last. |
| 67 | JZ100 | $F3DF | Channels::FetchFile | routine | KV20 | close:1, openchannel:2 | LogicalFile, Device and SecondaryAddress = table entry X's. |
| 68 | JZ101 | $F3EE | Channels::FetchFile::Done | entry | KV20 | close:1 | Returns (FindFile ends here when the file is not found). |
| 69 | NCLALL | $F3EF | Channels::CloseAll | routine | KV20 | init:1 | CloseAllFilesVector's default, CLALL: forgets every open file, and falls into ResetChannels. |
| 70 | NCLRCH | $F3F3 | Channels::ResetChannels | routine | KV20 | init:1 | ResetChannelsVector's default, CLRCHN: UNLISTEN and UNTALK any serial device in use; input from the keyboard, output to the screen. |
| 71 | JX750 | $F3FC | Channels::ResetChannels::CheckInput | local | KV20 | clall:1 | The input device. |
| 72 | CLALL2 | $F403 | Channels::ResetChannels::Defaults | local | KV20 | clall:1 | OutputDevice = 3, InputDevice = 0. |
| 73 | NOPEN | $F40A | Channels::Open | routine | KV20 | init:1 | OpenVector's default, OPEN: adds the current file to the tables and opens it on its device: the tape (finding the file, or writing a data header), the serial bus (sending its name), RS-232. Carry set with an error. |
| 74 | OP98 | $F411 | Channels::Open::NotKeyboard | local | KV20 | open:1 | Logical file 0 is NOT INPUT FILE. |
| 75 | OP100 | $F419 | Channels::Open::NotOpen | local | KV20 | open:1 | FILE OPEN if it is; TOO MANY FILES past ten. |
| 76 | OP110 | $F422 | Channels::Open::AddEntry | local | KV20 | open:1 | The table entry; the secondary address gets $60, the serial bus's data command. |
| 77 | OP150 | $F444 | Channels::Open::OnTape | local | KV20 | open:1 | RS-232, or the tape. |
| 78 | OP152 | $F44B | Channels::Open::NotRs232 | local | KV20 | open:1 | The tape needs its buffer. |
| 79 | OP155 | $F453 | Channels::Open::Buffer | local | KV20 | open:1 | Reading or writing, by the secondary address. |
| 80 | OP160 | $F46C | Channels::Open::NotFound | local | KV20 | open:1 | FILE NOT FOUND. |
| 81 | OP170 | $F46F | Channels::Open::AnyFile | local | KV20 | open:1 | No name: the next header, of any kind. |
| 82 | OP200 | $F478 | Channels::Open::Write | local | KV20 | open:1 | Writing: RECORD and PLAY, then a data file's header. |
| 83 | OP171 | $F482 | Channels::Open::SetBuffer | local | KV20 | open:2 | The buffer index: at its end for reading, so the first CHRIN reads a block; after a type byte for writing. |
| 84 | OP172 | $F491 | Channels::Open::SetIndex | local | KV20 | open:1 | BufferIndex = it. |
| 85 | OP175 | $F493 | Channels::Open::Success | local | KV20 | open:3 | Carry clear. |
| 86 | OP180 | $F494 | Channels::Open::Done | local | KV20 | open:4 | Returns. |
| 87 | OPENI | $F495 | Channels::OpenSerialFile | routine | KV20 | load:1, open:1, save:1 | With a secondary address and a name: LISTEN, the secondary with $F0 (open), the name, UNLISTEN. DEVICE NOT PRESENT returns from its caller's caller. |
| 88 | OP35 | $F4B2 | Channels::OpenSerialFile::SendName | local | KV20 | open:1 | The name, if any. |
| 89 | OP40 | $F4B8 | Channels::OpenSerialFile::NextCharacter | local | KV20 | open:1 | Each character. |
| 90 | OP45 | $F4C2 | Channels::OpenSerialFile::Unlisten | local | KV20 | open:1 | UNLISTEN. |
| 91 | OP50 | $F4C5 | Channels::OpenSerialFile::Done | local | KV20 | open:2 | Carry clear. |
| 92 | OPN232 | $F4C7 | Rs232::Open | routine | KV20 | open:1 | Opens RS-232: the user port's lines, Control and Command (and two more bytes) from the file name, the word's bits, the bit time, the handshake's check, and 256-byte buffers from the top of memory. |
| 93 | OPN020 | $F4D9 | Rs232::Open::CopyParameters | local | KV20 | open:1 | Up to four bytes of the name. |
| 94 | OPN025 | $F4E7 | Rs232::Open::Bits | local | KV20 | open:1 | WordBits = CountWordBits. |
| 95 | OPN010 | $F4F4 | Rs232::Open::BaudTime | local | KV20 | open:1 | BitTime = twice BaudRates' entry, plus the latency twice. |
| 96 | OPN030 | $F50C | DROP | local | KV20 | none | Not referenced; no document names it. |
| 97 | OPN050 | $F51B | Rs232::Open::ResetBuffers | local | KV20 | open:2 | Both buffers empty. |
| 98 | OPN055 | $F527 | DROP | local | KV20 | none | Not referenced; no document names it. |
| 99 | OPN060 | $F533 | Rs232::Open::TakeOutputPage | local | KV20 | open:1 | The output buffer's page. |
| 100 | MEMTCF | $F53C | Rs232::Open::LowerMemoryTop | entry | KV20 | close:1, open:1 | Sets the top of memory with carry set, so BASIC is told it moved (Close comes here to raise it again). |
| 101 | LOADSP | $F542 | Channels::LoadToAddress | routine | KV20 | vectors:1 | The jump table's LOAD: with secondary address 0, loads at X and Y; falls into LoadThroughVector. |
| 102 | LOAD | $F546 | Channels::LoadThroughVector | routine | KV20, in prose: the name's Also: is its jump-table entry's; spelling only: MTV, V20PRG | editor.3:1, kernal:1, load:1 | Through LoadVector. |
| 103 | NLOAD | $F549 | Channels::Load | routine | KV20 | init:1 | LoadVector's default: LOAD or VERIFY (A non-zero) from the tape or the serial bus, at the file's address or LoadAddress. Carry clear and X, Y = the end; carry set with an error. |
| 104 | LD10 | $F553 | Channels::Load::BadDevice | local | KV20 | load:1 | ILLEGAL DEVICE NUMBER: the keyboard or the screen. |
| 105 | LD20 | $F556 | Channels::Load::NotKeyboard | local | KV20 | load:1 | The serial bus, or the tape. |
| 106 | LD25 | $F563 | Channels::Load::SerialDevice | local | KV20 | load:1 | Needs a name: SEARCHING, open with secondary address $60, TALK, the file's address. |
| 107 | LD40 | $F58A | Channels::Load::NextByte | local | KV20 | load:2 | Each byte until EOI, watching STOP. |
| 108 | LD45 | $F598 | Channels::Load::Receive | local | KV20 | load:1 | A timeout is tried again. |
| 109 | LD50 | $F5B3 | Channels::Load::Store | local | KV20 | load:1 | Stores the byte. |
| 110 | LD60 | $F5B5 | Channels::Load::Advance | local | KV20 | load:1 | On to the next address. |
| 111 | LD64 | $F5BB | Channels::Load::CheckEnd | local | KV20 | load:1 | Until EOI: then UNTALK and close. |
| 112 | LD90 | $F5C7 | Channels::Load::NotFound | local | KV20 | load:3 | FILE NOT FOUND. |
| 113 | LD100 | $F5CA | Channels::Load::OnTape | local | KV20 | load:1 | RS-232 can't load; the tape needs its buffer. |
| 114 | LD102 | $F5D1 | Channels::Load::NotRs232 | local | KV20 | load:1 | The tape buffer. |
| 115 | LD104 | $F5D9 | Channels::Load::Buffer | local | KV20 | load:1 | PRESS PLAY, SEARCHING. |
| 116 | LD112 | $F5E1 | Channels::Load::Search | local | KV20 | load:1 | The file by its name, or the next. |
| 117 | LD150 | $F5EE | Channels::Load::AnyHeader | local | KV20 | load:1 | The next header. |
| 118 | LD170 | $F5F5 | Channels::Load::HeaderFound | local | KV20 | load:1 | A program's header, read right. |
| 119 | LD177 | $F604 | Channels::Load::Fixed | local | KV20 | load:1 | A fixed program: its own address. |
| 120 | LD178 | $F611 | Channels::Load::Relocatable | local | KV20 | load:1 | A relocatable program loads at LoadAddress, unless the secondary address asks for its own. |
| 121 | LD179 | $F615 | Channels::Load::SetEnd | local | KV20 | load:1 | EndAddress = the start plus the header's length; LOADING, and the block. |
| 122 | LD180 | $F641 | Channels::Load::Success | local | KV20 | load:1 | Carry clear, X and Y = the end. |
| 123 | LD190 | $F646 | Channels::Load::Done | local | KV20 | load:4 | Returns. |
| 124 | LUKING | $F647 | Channels::PrintSearching | routine | KV20 | load:2, open:1 | SEARCHING, and FOR and the name, when the control messages are on. |
| 125 | OUTFN | $F659 | Channels::PrintSearching::PrintName | entry | KV20 | save:1 | The file name, if any (SAVING comes here). |
| 126 | LD110 | $F65F | Channels::PrintSearching::NextCharacter | local | KV20 | load:1 | Each character. |
| 127 | LD115 | $F669 | Channels::PrintSearching::Done | local | KV20 | load:3 | Returns. |
| 128 | LODING | $F66A | Channels::PrintLoading | routine | KV20 | load:2 | LOADING or VERIFYING, when the control messages are on. |
| 129 | LD410 | $F672 | Channels::PrintLoading::Print | local | KV20 | load:1 | Prints it. |
| 130 | PATCH2 | $E4BC | Channels::LoadSearchPatch | routine | KV20 | load:1 | A patch in the patch area for the serial bus's LOAD: X = the secondary address, then SEARCHING. |
| 131 | PATCH3 | $E4C1 | Channels::LoadAddressPatch | routine | KV20 | load:1 | A patch: with secondary address 0 the program loads at LoadAddress, not its own; then LOADING. |
| 132 | PATCH4 | $E4CC | Channels::LoadAddressPatch::Print | local | KV20 | load:1 | LOADING. |
| 133 | SAVESP | $F675 | Channels::SaveRange | routine | KV20 | vectors:1 | The jump table's SAVE: from the address in the zero-page pair A points at, to X and Y; falls into SaveThroughVector. |
| 134 | SAVE | $F682 | Channels::SaveThroughVector | routine | KV20, in prose: the name's Also: is its jump-table entry's; spelling only: MTV, V20PRG | kernal:1, save:1 | Through SaveVector. |
| 135 | NSAVE | $F685 | Channels::Save | routine | KV20 | init:1 | SaveVector's default: saves StartAddress-EndAddress to the tape or the serial bus. Carry set with an error, or STOP (A = 0). |
| 136 | SV10 | $F689 | Channels::Save::BadDevice | entry | KV20 | save:2 | ILLEGAL DEVICE NUMBER. |
| 137 | SV20 | $F68C | Channels::Save::NotKeyboard | local | KV20 | save:1 | The serial bus, or the tape. |
| 138 | SV25 | $F69D | Channels::Save::SerialDevice | local | KV20 | save:1 | Needs a name: open with secondary address $61, SAVING, LISTEN, the address. |
| 139 | SV30 | $F6BC | Channels::Save::NextByte | local | KV20 | save:1 | Each byte, watching STOP. |
| 140 | BREAK | $F6CB | Channels::Save::Break | entry | KV20; spelling only: MTV, V20PRG | load:1 | STOP: closes the file; A = 0, carry set (Load comes here too). MTV and V20PRG spell BREAK, but not for this code. |
| 141 | SV40 | $F6D2 | Channels::Save::Advance | local | KV20 | save:1 | On to the next address. |
| 142 | SV50 | $F6D7 | Channels::Save::Unlisten | local | KV20 | save:1 | UNLISTEN, and falls into CloseSerialFile. |
| 143 | CLSEI | $F6DA | Channels::CloseSerialFile | routine | KV20 | close:1, load:1, save:1 | With a secondary address: LISTEN, the secondary with $E0 (close), UNLISTEN. Carry clear. |
| 144 | CLSEI2 | $F6EF | Channels::CloseSerialFile::Done | local | KV20 | save:1 | Carry clear. |
| 145 | SV100 | $F6F1 | Channels::SaveToTape | routine | KV20 | save:1 | Save's tape half: RS-232 can't save; RECORD and PLAY, SAVING, a header (fixed for an odd secondary address), the block, and an end-of-tape header for secondary address 2. |
| 146 | SV102 | $F6F8 | Channels::SaveToTape::NotRs232 | local | KV20 | save:1 | The tape buffer. |
| 147 | SV105 | $F705 | DROP | local | KV20 | none | Not referenced; no document names it. |
| 148 | SV106 | $F70F | Channels::SaveToTape::WriteHeader | local | KV20 | save:1 | The header, then the program. |
| 149 | SV110 | $F726 | Channels::SaveToTape::Success | local | KV20 | save:1 | Carry clear. |
| 150 | SV115 | $F727 | Channels::SaveToTape::Done | entry | KV20 | save:4 | Returns (PrintSaving comes here with the messages off). |
| 151 | SAVING | $F728 | Channels::PrintSaving | routine | KV20, MTV; spelling only: V20PRG | messages:1, save:2 | SAVING and the name, when the control messages are on. |
| 152 | UDTIM | $F734 | Clock::Tick | routine | KV20, MTV, in prose: the name's Also: is its jump-table entry's; spelling only: V20PRG | rs232nmifile:1, tapecontrol:1, vectors:1 | UDTIM: the jiffy clock up one, back to 0 after 24 hours, and StopKeyRow from the keyboard's bottom row. |
| 153 | UD20 | $F736 | DROP | local | KV20 | none | Not referenced; no document names it. |
| 154 | UD30 | $F740 | Clock::Tick::CheckWrap | local | KV20 | time:2 | 24 hours, 5,184,000 jiffies, start it again. |
| 155 | UD60 | $F755 | Clock::Tick::ReadStopRow | local | KV20 | time:2 | Reads the row until two reads agree; StopKeyRow = it. (The listing jumps to its STOP patch here; 901486-06 and -07 store the row directly.) |
| 156 | RDTIM | $F760 | Clock::Read | routine | KV20, MTV, in prose: the name's Also: is its jump-table entry's; spelling only: V20PRG | vectors:1 | RDTIM: A, X and Y = the clock, lowest byte first; falls into Clock::Set, which stores it back. |
| 157 | SETTIM | $F767 | Clock::Set | routine | KV20, MTV, in prose: the name's Also: is its jump-table entry's; spelling only: V20PRG | vectors:1 | SETTIM: sets the clock from A, X and Y, interrupts held off meanwhile. |
| 158 | STPTCH | $E4CF | DROP | routine | KV20 | time:1 | The listing's patch telling STOP from SHIFT with STOP; 901486-06 and -07 removed it, and their patch area holds CloseTapePatch. |
| 159 | ITSSET | $E4E1 | DROP | local | KV20 | time:1 | Part of STPTCH, not in 901486-06 or -07. |
| 160 | NSTOP | $F770 | Channels::TestStopKey | routine | KV20 | init:1 | TestStopKeyVector's default, STOP: zero set if STOP is down, which also resets the channels and empties the keyboard buffer; A = StopKeyRow. |
| 161 | STOP2 | $F77D | Channels::TestStopKey::Done | local | KV20 | errorhandler:1 | Returns. |
| 162 | ERROR1 | $F77E | Channels::Error::TooManyFiles | entry | KV20 | open:1 | The kernal's errors, each loading its number and skipping the others with $2C: 1, TOO MANY FILES. Error itself starts here. |
| 163 | ERROR2 | $F781 | Channels::Error::FileOpen | entry | KV20 | open:1 | 2, FILE OPEN. |
| 164 | ERROR3 | $F784 | Channels::Error::FileNotOpen | entry | KV20 | openchannel:2 | 3, FILE NOT OPEN. |
| 165 | ERROR4 | $F787 | Channels::Error::FileNotFound | entry | KV20 | load:1, open:1 | 4, FILE NOT FOUND. |
| 166 | ERROR5 | $F78A | Channels::Error::DeviceNotPresent | entry | KV20 | open:1, openchannel:2 | 5, DEVICE NOT PRESENT. |
| 167 | ERROR6 | $F78D | Channels::Error::NotInputFile | entry | KV20 | open:1, openchannel:1 | 6, NOT INPUT FILE. |
| 168 | ERROR7 | $F790 | Channels::Error::NotOutputFile | entry | KV20 | openchannel:1 | 7, NOT OUTPUT FILE. |
| 169 | ERROR8 | $F793 | Channels::Error::MissingFileName | entry | KV20 | load:1, save:1 | 8, MISSING FILE NAME. |
| 170 | ERROR9 | $F796 | Channels::Error::IllegalDevice | entry | KV20 | load:2, open:1, rs232rcvr:1, save:1 | 9, ILLEGAL DEVICE NUMBER: then resets the channels, prints I/O ERROR # and the number when the error messages are on, and returns A = the number, carry set. |
| 171 | EREXIT | $F7AC | Channels::Error::Return | local | KV20 | errorhandler:1 | A = the error number, carry set. |
| 172 | SKIPBY | = * | DROP | constant | KV20 | load, time | SKIPBY, KSP3, SKIPIT and KSP4: the listing's arithmetic for moving the patches; inline, named in prose. |
| 173 | (none) | $E4CF | Channels::CloseTapePatch | routine | — | — | 901486-06's and -07's patch to Close: writes a tape file's last block, and after STOP drops the saved table index and returns A = 0. No listing names it; Close jumps here at $F39B. |
| 174 | (none) | — | Channels::Error | routine | — | — | The routine the ERROR1-ERROR9 entries are in, starting at TooManyFiles. |
| 175 | (none) | = 1-9 | KERNAL_ERROR_TOO_MANY_FILES ... KERNAL_ERROR_ILLEGAL_DEVICE | constant | — | — | The kernal's nine error numbers, which the code loads as immediates; the listing names them only in comments. |

## Part 7: start-up, the IRQ, the jump table and the VIC's registers

The listing's `INIT`, `IRQFILE` and `VECTORS`, `$FD22-$FEA8` and `$FF72-$FFFF`: 41 labels and one constant, the
jump table's 36 entries (the listing labels 13 of them; the reference guide names all 36 by address) and the VIC's
16 registers, which *Mapping the VIC* names (K-P1-Q4). Between the two, `$FF5C-$FF71` holds part 5's baud
table, the only other bytes here that the PAL kernal changes besides the 60 Hz timer's count.

Settled by the owner's leave (K10, K11): each question is settled as recommended.

### Questions

- K-P7-Q1. **The jump table.** Each entry is a top-level label on its `JMP`, `Kernal` and the name of what it
  reaches (`KernalSetFileName`, `KernalMemoryTop`), as X14 has it; the ones BASIC's shared modules already call
  keep those names (`KernalOpen` to `KernalSave`). The listing's label, where it has one, and the reference
  guide's name go in `Also:`, so `CHROUT` and `BSOUT` both lead to `KernalCharacterOut`. BASIC's shared modules
  call `$FFE1-$FFE7` `CheckStop`, `GetCharacter` and `CloseAllFiles`; the VIC-20's BASIC equates define those as
  the kernal's names (`Inherit:`), as the PET's do. The processor's vectors at `$FFFA` are three `.word`s naming
  their targets, with no labels, since no document names them. *Settled as recommended.*
- K-P7-Q2. **Where the small routines go.** SETNAM, SETLFS, READST and SETMSG set or read the channels' state:
  `Channels`. SETTMO is the serial bus's: `Serial::SetTimeout`. MEMTOP and MEMBOT, which the RAM test and RS-232's
  buffers use, join the RAM test in `Startup`. UDST, which the serial bus, the tape and LOAD call to report an
  error, is an entry of ReadStatus, `Channels::ReadStatus::SetStatus`, where its code is. *Settled as recommended.*
  The alternative is top level for all of them, as the listing has it.
- K-P7-Q3. **Table ends used only for a length** (TBLA0E and VECTSE) become constants,
  `CARTRIDGE_SIGNATURE_LENGTH` and `RAM_VECTORS_SIZE`, with an `.assert` after each table that its size
  matches. *Settled as recommended.*
- K-P7-Q4. **The VIC's registers** are defined with the other hardware locations, each named for what it sets,
  with *Mapping the VIC*'s `VICCR0`-`VICCRF` in `Also:`; `VicRegisters` stays as their base, which the editor's
  table of start-up values is loaded from. *Settled as recommended.*
- K-P7-Q5. **The code's slips are documented, not changed.** READST's RS-232 path loads 0 over the status
  before it returns, so it always returns 0 for device 2 (901486-06 and -07 have it too); its comment says so.
  The PAL kernal's timer count, 18470, is `JIFFY_TIMER_COUNT` under `.if PAL`, like the baud table.
  *Settled as recommended.*

### Rows

| # | Old | Address | New | Kind | Documents (checked) | Used in | Reason |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | START | $FD22 | Startup::Reset | routine | KV20, MTV; spelling only: V20PRG | vectors:1 | The processor's reset vector's target: the stack, binary mode, then a cartridge's cold start at ($A000) if FindCartridge finds one; otherwise the RAM test, the vectors, the I/O and the screen, and BASIC's cold start through ($C000). |
| 2 | START1 | $FD2F | Startup::Reset::NoCartridge | local | KV20 | init:1 | No cartridge: the system's own start-up. |
| 3 | A0INT | $FD3F | Startup::FindCartridge | routine | KV20 | init:1, rs232nmifile:1 | Zero set when the cartridge signature, A0CBM with CBM's high bits set, is at $A004 (the NMI asks too, for RESTORE). |
| 4 | A0IN1 | $FD41 | Startup::FindCartridge::Next | local | KV20 | init:1 | Each byte, from the last. |
| 5 | A0IN2 | $FD4C | Startup::FindCartridge::Done | local | KV20 | init:1 | Returns, zero clear at the first byte that differs. |
| 6 | TBLA0R | $FD4D | Startup::CartridgeSignature | table | KV20 | init:2 | A0 and CBM with their high bits set, the five bytes a cartridge has at $A004. |
| 7 | TBLA0E | $FD52 | Startup::CARTRIDGE_SIGNATURE_LENGTH | constant | KV20 | init:1 | The table's end, used only for its length, 5: a constant. |
| 8 | RESTOR | $FD52 | Startup::RestoreVectors | routine | KV20, MTV, in prose: the name's Also: is its jump-table entry's; spelling only: V20PRG | init:1, rs232nmifile:1, vectors:1 | RESTOR's target: the RAM vectors from DefaultVectors (X/Y = it, carry clear), falling into Copy. |
| 9 | VECTOR | $FD57 | Startup::RestoreVectors::Copy | entry | KV20, MTV, in prose: the name's Also: is its jump-table entry's; spelling only: V20PRG | vectors:1 | VECTOR's target: carry set copies the 16 RAM vectors to the 32 bytes at X/Y; carry clear copies those bytes into the RAM vectors (and back to X/Y). |
| 10 | MOVOS1 | $FD5D | Startup::RestoreVectors::Next | local | KV20 | init:1 | Each byte, from the last. |
| 11 | MOVOS2 | $FD64 | Startup::RestoreVectors::Store | local | KV20 | init:1 | Into both the RAM vectors and the bytes at X/Y. |
| 12 | VECTSS | $FD6D | Startup::DefaultVectors | table | KV20 | init:3 | The RAM vectors' defaults, IrqVector to SaveVector: Jiffy, Break, NmiHandler, the Channels routines, Break again for the unused USRCMD vector, Load and Save. |
| 13 | VECTSE | $FD8D | Startup::RAM_VECTORS_SIZE | constant | KV20 | init:1 | The table's end, used only for its size, 32 bytes (16 vectors): a constant. |
| 14 | RAMTAS | $FD8D | Startup::TestMemory | routine | KV20 | init:1 | Clears pages 0, 2 and 3, points TapeBuffer at TapeBufferArea, and tests RAM from $0401 up: MemoryStart at the first RAM, MemoryEnd at the end, and ScreenPage $1E, or $10 with 8K or more of expansion RAM at $2000 (BASIC then from $1200). Hangs if $1000-$1FFF fails. |
| 15 | RAMTZ0 | $FD90 | Startup::TestMemory::ClearPages | local | KV20 | init:1 | Zeroes pages 0, 2 and 3. |
| 16 | RAMTBT | $FDA3 | DROP | local | KV20 | none | Not referenced; no document names it. |
| 17 | RAMTZ1 | $FDAF | Startup::TestMemory::NextAddress | local | KV20 | init:3 | Pointer up one byte. |
| 18 | RAMTZ2 | $FDB5 | Startup::TestMemory::Check | local | KV20 | init:1 | TestByte; SavedX says whether the bottom or the top is sought. |
| 19 | RAMTZ3 | $FDCF | Startup::TestMemory::SetTop | local | KV20 | init:1 | MemoryEnd = the first byte that failed. |
| 20 | RAMTZ4 | $FDD2 | Startup::TestMemory::ScreenAtBottom | local | KV20 | init:1 | RAM goes on past $2100: the screen at $1000, and BASIC from $1200. |
| 21 | RAMTZ5 | $FDDE | Startup::TestMemory::SeekingBottom | local | KV20 | init:1 | Seeking the bottom: until a byte passes, which is MemoryStart's page. |
| 22 | BADRAM | $FDEB | Startup::TestMemory::NoSystemRam | local | KV20 | init:2 | No RAM at $1000-$1FFF: sets the VIC up and hangs. |
| 23 | BSIT | $FDF1 | Tape::InterruptHandlers | table | KV20 | write:2 | The tape's IRQ handlers, which the tape routines put in IrqVector: WriteLeader, WriteData's Interrupt, Jiffy (to end) and ReadInterrupt. |
| 24 | IOINIT | $FDF9 | Startup::InitializeIo | routine | KV20 | init:1, rs232nmifile:1 | Sets both VIAs up: their interrupts off, the timers' modes, the handshake lines, the ports' directions, the serial bus's lines released, RESTORE's NMI on; falls into StartJiffyTimer. |
| 25 | IOKEYS | $FE39 | Startup::InitializeIo::StartJiffyTimer | entry | KV20 | write:1 | VIA 2's timer 1 interrupts on, at 60 a second (the tape routines come here when they finish). |
| 26 | SETNAM | $FE49 | Channels::SetFileName | routine | KV20, MTV, in prose: the name's Also: is its jump-table entry's; spelling only: V20PRG | vectors:1 | SETNAM's target: FileNameLength = A, FileName = X/Y. |
| 27 | SETLFS | $FE50 | Channels::SetFile | routine | KV20, MTV, in prose: the name's Also: is its jump-table entry's; spelling only: V20PRG | vectors:1 | SETLFS's target: LogicalFile = A, Device = X, SecondaryAddress = Y. |
| 28 | READSS | $FE57 | Channels::ReadStatus | routine | KV20 | vectors:1 | READST's target: A = IoStatus, or for device 2 Rs232::Status, which is then cleared. The RS-232 path loads 0 over the status before it returns, so it gives A = 0 (in 901486-06 too). |
| 29 | SETMSG | $FE66 | Channels::ReadStatus::SetMessages | entry | KV20, MTV, in prose: the name's Also: is its jump-table entry's; spelling only: V20PRG | vectors:1 | SETMSG's target: MessageMode = A; falls into ReadIoStatus, so it returns A = IoStatus. |
| 30 | READST | $FE68 | Channels::ReadStatus::ReadIoStatus | local | KV20, MTV, in prose: the name's Also: is its jump-table entry's; spelling only: V20PRG | init:1 | A = IoStatus. |
| 31 | UDST | $FE6A | Channels::ReadStatus::SetStatus | entry | KV20 | channelio:1, load:1, read:4, serial2.1:2 | IoStatus = IoStatus or A: how the serial bus, the tape and LOAD report errors. |
| 32 | SETTMO | $FE6F | Serial::SetTimeout | routine | KV20, MTV, in prose: the name's Also: is its jump-table entry's; spelling only: V20PRG | vectors:1 | SETTMO's target: TimeoutFlag = A (a leftover of the PET's IEEE-488; the serial bus routines do not read it). |
| 33 | MEMTOP | $FE73 | Startup::MemoryTop | routine | KV20, MTV, in prose: the name's Also: is its jump-table entry's; spelling only: V20PRG | vectors:1 | MEMTOP's target: carry set reads MemoryEnd into X/Y; carry clear sets it from X/Y. |
| 34 | GETTOP | $FE75 | Startup::MemoryTop::Read | entry | KV20 | close:1, open:1 | X/Y = MemoryEnd, falling into SetTop (OPEN and CLOSE use it for RS-232's buffers). |
| 35 | SETTOP | $FE7B | Startup::MemoryTop::SetTop | entry | KV20 | init:2, open:1 | MemoryEnd = X/Y. |
| 36 | MEMBOT | $FE82 | Startup::MemoryBottom | routine | KV20, MTV, in prose: the name's Also: is its jump-table entry's; spelling only: V20PRG | vectors:1 | MEMBOT's target: carry set reads MemoryStart into X/Y; carry clear sets it from X/Y. |
| 37 | SETBOT | $FE8A | Startup::MemoryBottom::SetBottom | local | KV20 | init:1 | MemoryStart = X/Y. |
| 38 | CHKMEM | $FE91 | Startup::TestByte | routine | KV20 | init:1 | Carry set if the byte at (Pointer),Y holds $55 and $AA, so is RAM; the byte is put back. A = it, X too. |
| 39 | NOMEM | $FEA4 | Startup::TestByte::NoRam | local | KV20 | init:2 | Carry clear: no RAM. The code before it skips the CLC with $A9 when the test passes. |
| 40 | PULS | $FF72 | Interrupts::Irq | routine | KV20 | vectors:1 | The processor's IRQ vector's target: saves A, X and Y, then BRK goes through BreakVector and an IRQ through IrqVector. |
| 41 | PULS1 | $FF82 | Interrupts::Irq::NotBreak | local | KV20 | irqfile:1 | An IRQ: through IrqVector. |
| 42 | SIXTY | = 17033 | JIFFY_TIMER_COUNT | constant | KV20 | init | VIA 2's timer 1 count for 60 interrupts a second: 17033 ($4289) on NTSC, 18470 ($4826) in the PAL kernal, 901486-07. |
| 43 | (RESTOR) | $FF8A | KernalRestoreVectors | entry | MTV, V20PRG | BASIC, programs | The jump table: RestoreVectors: the RAM vectors' defaults. |
| 44 | (VECTOR) | $FF8D | KernalCopyVectors | entry | MTV, V20PRG | BASIC, programs | The jump table: RestoreVectors's Copy: reads or sets the RAM vectors. |
| 45 | (SETMSG) | $FF90 | KernalSetMessages | entry | MTV, V20PRG | BASIC, programs | The jump table: ReadStatus's SetMessages: which messages the kernal prints. |
| 46 | (SECOND) | $FF93 | KernalSendSecondary | entry | V20PRG; spelling only: MTV | BASIC, programs | The jump table: Serial::SendSecondary: a secondary address after LISTEN. |
| 47 | (TKSA) | $FF96 | KernalSendTalkSecondary | entry | V20PRG; spelling only: MTV | BASIC, programs | The jump table: Serial::SendTalkSecondary: a secondary address after TALK. |
| 48 | (MEMTOP) | $FF99 | KernalMemoryTop | entry | V20PRG; spelling only: MTV | BASIC, programs | The jump table: Startup::MemoryTop: reads or sets the top of memory. |
| 49 | (MEMBOT) | $FF9C | KernalMemoryBottom | entry | MTV, V20PRG | BASIC, programs | The jump table: Startup::MemoryBottom: reads or sets the bottom of memory. |
| 50 | (SCNKEY) | $FF9F | KernalScanKeyboard | entry | V20PRG; spelling only: MTV | BASIC, programs | The jump table: Editor::ScanKeyboard: scans the keyboard, for programs that turn the IRQ off. |
| 51 | (SETTMO) | $FFA2 | KernalSetTimeout | entry | MTV, V20PRG | BASIC, programs | The jump table: Serial::SetTimeout. |
| 52 | (ACPTR) | $FFA5 | KernalReceiveByte | entry | V20PRG; spelling only: MTV | BASIC, programs | The jump table: Serial::ReceiveByte: a byte from the talker. |
| 53 | (CIOUT) | $FFA8 | KernalSendByte | entry | V20PRG; spelling only: MTV | BASIC, programs | The jump table: Serial::SendByte: a byte to the listeners. |
| 54 | (UNTLK) | $FFAB | KernalUntalk | entry | V20PRG; spelling only: MTV | BASIC, programs | The jump table: Serial::Untalk. |
| 55 | (UNLSN) | $FFAE | KernalUnlisten | entry | V20PRG; spelling only: MTV | BASIC, programs | The jump table: Serial::Unlisten. |
| 56 | (LISTEN) | $FFB1 | KernalListen | entry | V20PRG; spelling only: MTV | BASIC, programs | The jump table: Serial::Listen (the listing's LISTN). |
| 57 | (TALK) | $FFB4 | KernalTalk | entry | MTV, V20PRG | BASIC, programs | The jump table: Serial::Talk. |
| 58 | (READST) | $FFB7 | KernalReadStatus | entry | MTV, V20PRG | BASIC, programs | The jump table: Channels::ReadStatus (the listing's READSS). |
| 59 | (SETLFS) | $FFBA | KernalSetFile | entry | MTV, V20PRG | BASIC, programs | The jump table: Channels::SetFile. |
| 60 | (SETNAM) | $FFBD | KernalSetFileName | entry | MTV, V20PRG | BASIC, programs | The jump table: Channels::SetFileName. |
| 61 | OPEN | $FFC0 | KernalOpen | entry | KV20, MTV, V20PRG | kernal:1, open:2, openchannel:2 | The jump table: through OpenVector, to Channels::Open. |
| 62 | CLOSE | $FFC3 | KernalClose | entry | KV20, MTV, V20PRG | clall:1, close:1, kernal:1 | The jump table: through CloseVector, to Channels::Close. |
| 63 | CHKIN | $FFC6 | KernalSelectInput | entry | KV20, MTV, V20PRG | none | The jump table: through SelectInputVector, to Channels::SelectInput. |
| 64 | CKOUT | $FFC9 | KernalSelectOutput | entry | KV20; other names here: MTV, V20PRG spell it CHKOUT | none | The jump table: through SelectOutputVector, to Channels::SelectOutput. |
| 65 | CLRCH | $FFCC | KernalResetChannels | entry | KV20; other names here: MTV, V20PRG spell it CLRCHN | errorhandler:2 | The jump table: through ResetChannelsVector, to Channels::ResetChannels. |
| 66 | BASIN | $FFCF | KernalCharacterIn | entry | KV20; other names here: MTV, V20PRG spell it CHRIN | none | The jump table: through CharacterInVector, to Channels::CharacterIn. |
| 67 | BSOUT | $FFD2 | KernalCharacterOut | entry | KV20; other names here: V20PRG spells it CHROUT (MTV too, but for $F27A) | errorhandler:1, load:1, messages:1, tapefile:1 | The jump table: through CharacterOutVector, to Channels::CharacterOut. |
| 68 | (LOAD) | $FFD5 | KernalLoad | entry | MTV, V20PRG | BASIC, programs | The jump table: Channels::LoadToAddress (the listing's LOADSP), then through LoadVector. |
| 69 | (SAVE) | $FFD8 | KernalSave | entry | MTV, V20PRG | BASIC, programs | The jump table: Channels::SaveRange (the listing's SAVESP), then through SaveVector. |
| 70 | (SETTIM) | $FFDB | KernalSetClock | entry | MTV, V20PRG | BASIC, programs | The jump table: Clock::Set. |
| 71 | (RDTIM) | $FFDE | KernalReadClock | entry | MTV, V20PRG | BASIC, programs | The jump table: Clock::Read. |
| 72 | STOP | $FFE1 | KernalTestStopKey | entry | KV20, MTV, V20PRG | load:1, rs232nmifile:1, save:1, tapecontrol:1 | The jump table: through TestStopKeyVector, to Channels::TestStopKey. |
| 73 | GETIN | $FFE4 | KernalGetInput | entry | KV20, MTV, V20PRG | none | The jump table: through GetInputVector, to Channels::GetInput. |
| 74 | CLALL | $FFE7 | KernalCloseAll | entry | KV20, MTV, V20PRG | kernal:1 | The jump table: through CloseAllFilesVector, to Channels::CloseAll. |
| 75 | (UDTIM) | $FFEA | KernalTickClock | entry | MTV, V20PRG | BASIC, programs | The jump table: Clock::Tick, for programs that take the IRQ themselves. |
| 76 | JSCROG | $FFED | KernalScreenSize | entry | KV20; other names here: V20PRG spells it SCREEN | none | The jump table: Editor::ScreenSize: the screen's columns and rows. |
| 77 | JPLOT | $FFF0 | KernalPlot | entry | KV20; other names here: MTV, V20PRG spell it PLOT | none | The jump table: Editor::Plot: reads or sets the cursor's row and column. |
| 78 | JIOBAS | $FFF3 | KernalIoBase | entry | KV20; other names here: MTV, V20PRG spell it IOBASE | none | The jump table: Editor::IoBase: the I/O's base, VIA 1. |
| 79 | VICCR0 | $9000 | VicHorizontalOrigin | location | MTV | none | Bits 0-6: the screen's left edge, in steps of 4 pixels; bit 7: interlace. (MTV's OCR: VICCRO.) |
| 80 | VICCR1 | $9001 | VicVerticalOrigin | location | MTV | none | The screen's top edge, in steps of 2 lines. |
| 81 | VICCR2 | $9002 | VicColumns | location | MTV | none | Bits 0-6: the screen's columns; bit 7: bit 9 of the screen's and colour memory's addresses. |
| 82 | VICCR3 | $9003 | VicRows | location | MTV | none | Bit 0: 8 by 16 characters; bits 1-6: the screen's rows; bit 7: bit 0 of the raster line. |
| 83 | VICCR4 | $9004 | VicRaster | location | MTV | none | Bits 1-8 of the raster line, read only. (MTV's OCR gives its address as 16868 $9084.) |
| 84 | VICCR5 | $9005 | VicScreenAndCharacters | location | MTV | none | Bits 0-3: the character set's address; bits 4-7: the screen's. |
| 85 | VICCR6 | $9006 | VicLightPenX | location | MTV | none | The light pen's horizontal position, read only. |
| 86 | VICCR7 | $9007 | VicLightPenY | location | MTV | none | The light pen's vertical position, read only. |
| 87 | VICCR8 | $9008 | VicPaddleX | location | MTV | none | Paddle X, read only. |
| 88 | VICCR9 | $9009 | VicPaddleY | location | MTV | none | Paddle Y, read only. |
| 89 | VICCRA | $900A | VicVoice1 | location | MTV | none | The lowest voice: bit 7 on, bits 0-6 the frequency. |
| 90 | VICCRB | $900B | VicVoice2 | location | MTV | none | The middle voice. |
| 91 | VICCRC | $900C | VicVoice3 | location | MTV | none | The highest voice. |
| 92 | VICCRD | $900D | VicNoise | location | MTV | none | The noise voice. |
| 93 | VICCRE | $900E | VicVolume | location | MTV | none | Bits 0-3: the volume; bits 4-7: the auxiliary colour. |
| 94 | VICCRF | $900F | VicBackgroundAndBorder | location | MTV | none | Bits 0-2: the border's colour; bit 3 clear: reversed characters; bits 4-7: the background's colour. |
