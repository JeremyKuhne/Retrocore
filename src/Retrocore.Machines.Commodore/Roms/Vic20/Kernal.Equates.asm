; retrocore: style=strict
; COMMODORE VIC-20 KERNAL: THE EQUATES

; Zero page. $00-$8F are BASIC's: the PET monitor's registers the listing still declares there (PCH, PCL, FLGS, ACC,
; XR, YR, SP, INVH and INVL, $00-$08) are not used in the VIC-20. $FB-$FE (the listing's FREKZP) are left free for
; programs, and $FF (BASZPT) is BASIC's. The kernal's own bytes from $90 to $FA are here, or in the families' scopes
; below where one family uses a byte for itself.

;; The status of the last input or output: BASIC's ST. The serial bus, the tape and LOAD set its bits (the STATUS_*
;; constants) through <Channels::ReadStatus::SetStatus>, and READST returns it.
;; Also: STATUS (KV20, MTV)
IoStatus = $0090

;; The keyboard's rows in STOP's column, as the jiffy clock last read them.
;;
;; <Clock::Tick> reads them each jiffy, with the keyboard scan having left column 3 driven; it is $FE while STOP is
;; down, which <Channels::TestStopKey> tests.
;; Also: STKEY (KV20, MTV)
StopKeyRow = $0091

;; 0 for LOAD, 1 for VERIFY: the tape's and the serial bus's load routines compare the bytes with memory instead of
;; storing them.
;; Also: VERCK (KV20, MTV)
VerifyFlag = $0093

;; A byte the kernal keeps a register in while it calls another routine.
;;
;; CHRIN, GETIN and CHROUT keep X or Y here across the tape's and RS-232's routines. <Startup::TestMemory> uses it
;; as a flag: 0 while it looks for the first RAM, then that RAM's page.
;; Also: XSAV (KV20, MTV)
SavedX = $0097

;; How many files are open: the entries in <FileNumbers>, <FileDevices> and <FileSecondaryAddresses>, at most ten.
;; Also: LDTND (KV20, MTV)
OpenFileCount = $0098

;; The device CHRIN and GETIN read from: 0 the keyboard, 1 the tape, 2 RS-232, 3 the screen, 4-31 the serial bus.
;;
;; CHKIN sets it, and CLRCHN puts it back to 0.
;; Also: DFLTN (KV20, MTV)
InputDevice = $0099

;; The device CHROUT writes to, numbered as <InputDevice>'s: CHKOUT sets it, and CLRCHN puts it back to 3, the
;; screen.
;; Also: DFLTO (KV20, MTV)
OutputDevice = $009A

;; Which messages the kernal prints: bit 7 its control messages (SEARCHING, LOADING), bit 6 its I/O error messages.
;;
;; SETMSG sets it. BASIC turns bit 7 on in direct mode and off while a program runs.
;; Also: MSGFLG (KV20, MTV)
MessageMode = $009D

;; A temporary of the channel routines and the tape's file routines: a character on its way to the tape buffer, or a
;; register kept across a call.
;; Also: T1 (KV20)
Temporary1 = $009E

;; The time of day in jiffies, sixtieths of a second, in three bytes from the highest: BASIC's TI.
;;
;; <Clock::Tick> counts it each jiffy, and puts it back to 0 after 24 hours.
;; Also: TIME (KV20, MTV, V20PRG)
JiffyClock = $00A0

;; The address being loaded or saved, which steps through the memory; the screen editor uses the pair as a pointer
;; when it moves rows.
;; Also: SAL (KV20, MTV)
StartAddress = $00AC

;; <StartAddress>'s high byte.
;; Also: SAH (KV20)
StartAddressHigh = $00AD

;; The end of the memory being loaded or saved; the screen editor uses the pair as a second pointer, into the colour
;; RAM.
;; Also: EAL (KV20, MTV)
EndAddress = $00AE

;; <EndAddress>'s high byte.
;; Also: EAH (KV20)
EndAddressHigh = $00AF

;; A pointer to the tape buffer, <TapeBufferArea>, which <Startup::TestMemory> sets: the tape routines reach the
;; buffer through it.
;; Also: TAPE1 (KV20, MTV)
TapeBuffer = $00B2

;; The current file name's length, which SETNAM sets; 0 for no name.
;; Also: FNLEN (KV20, MTV)
FileNameLength = $00B7

;; The current logical file number, which SETLFS sets.
;; Also: LA (KV20, MTV)
LogicalFile = $00B8

;; The current secondary address, which SETLFS sets: $FF for none.
;; Also: SA (KV20)
SecondaryAddress = $00B9

;; The current device number, which SETLFS sets, numbered as <InputDevice>'s.
;; Also: FA (KV20, MTV)
Device = $00BA

;; A pointer to the current file name, which SETNAM sets.
;; Also: FNADR (KV20, MTV)
FileName = $00BB

;; 0 while the jiffy interrupt may run the cassette's motor by the PLAY key; non-zero while a tape routine runs it.
;; Also: CAS1 (KV20, MTV)
CassetteMotorMode = $00C0

;; The address LOAD was given in X and Y; a tape program saved to load at a fixed address replaces it with that
;; address from its header.
;; Also: MEMUSS (KV20, MTV)
LoadAddress = $00C3

;; How many characters are waiting in <KeyboardBuffer>, 0 to <KeyboardBufferSize>.
;; Also: NDX (KV20, MTV)
KeyboardBufferCount = $00C6

; Page 2. $0295-$0296 (the listing's M51AJB, a rate for RS-232's user baud rate) are declared but not used.

;; The 89-byte buffer BASIC reads a typed line into. The kernal only uses its page, in <Tape::BufferAddress>, as the
;; lowest a tape buffer may be.
;; Also: BUF (KV20, MTV)
InputBuffer = $0200

;; Each open file's logical file number, ten entries.
;; Also: LAT (KV20, MTV), LOT (MTV)
FileNumbers = $0259

;; Each open file's device number, beside its entry in <FileNumbers>.
;; Also: FAT (KV20, MTV)
FileDevices = $0263

;; Each open file's secondary address, beside its entry in <FileNumbers>.
;; Also: SAT (KV20, MTV)
FileSecondaryAddresses = $026D

;; The ten-character keyboard buffer: the keyboard scan adds to its end, and GETIN and CHRIN take from its start.
;; Also: KEYD (KV20, MTV)
KeyboardBuffer = $0277

;; The bottom of the RAM for BASIC, which <Startup::TestMemory> finds: $1000 unexpanded, $0400 with 3K of RAM at
;; $0400, $1200 with RAM in block 1. MEMBOT reads and sets it.
;; Also: MEMSTR (KV20, MTV)
MemoryStart = $0281

;; The top of the RAM for BASIC, plus one: $1E00 unexpanded, below the screen, or the end of the RAM in blocks 1-3.
;;
;; <Startup::TestMemory> sets it, MEMTOP reads and sets it, and OPEN and CLOSE move it down and back up for RS-232's
;; buffers.
;; Also: MEMSIZ (KV20, MTV), MEMHIGH (MTV)
MemoryEnd = $0283

;; The colour the screen editor gives each character it prints, 0 to 7: blue, 6, from start-up. The colour keys set
;; it.
;; Also: COLOR (KV20, MTV)
TextColour = $0286

;; The page the screen starts at, which <Startup::TestMemory> chooses: $1E unexpanded, $10 with RAM in block 1.
;; Also: HIBASE (KV20, MTV)
ScreenPage = $0288

;; The most characters <KeyboardBuffer> may hold, 10 from start-up.
;; Also: XMAX (KV20, MTV)
KeyboardBufferSize = $0289

;; Which keys repeat while held: bit 7 set, every key; bit 6 set, none; both clear, as at start-up, only space,
;; INST/DEL and the cursor keys.
;; Also: RPTFLG (KV20, MTV)
KeyRepeat = $028A

;; The shift keys down at the last scan: bit 0 SHIFT, bit 1 the Commodore key, bit 2 CTRL.
;; Also: SHFLAG (KV20, MTV)
ShiftKeys = $028D

;; The vector of the routine that picks the keyboard table for the shift keys down, <Editor::SelectKeyTable> from
;; start-up; a program can put its own here.
;; Also: KEYLOG (KV20, MTV)
KeyTableSetup = $028F

;; Whether SHIFT with the Commodore key may switch the character set: 0 lets it, $80 locks it. Printing CHR$(8)
;; locks it and CHR$(9) unlocks it.
;; Also: MODE (KV20)
CaseSwitchLock = $0291

; The RAM vectors, $0314-$0333: the interrupts and most of the jump table go through them, so a program can point one
; at its own routine. <Startup::RestoreVectors> sets all 16 back from <Startup::DefaultVectors>. The 14th, $032E (the
; listing's USRCMD), is not used by the kernal.

;; The IRQ's RAM vector, <Interrupts::Jiffy> from start-up; the tape routines point it at their own interrupt
;; routines while they run.
;; Also: CINV (KV20, MTV)
IrqVector = $0314

;; The BRK instruction's RAM vector, <Interrupts::NmiHandler::Break> from start-up, which puts the vectors, the I/O
;; and the screen back and starts BASIC warm, as STOP-RESTORE does.
;; Also: CBINV (KV20, MTV)
BreakVector = $0316

;; The NMI's RAM vector, <Interrupts::NmiHandler> from start-up: the RESTORE key, and RS-232's bit timers.
;; Also: NMINV (KV20, MTV)
NmiVector = $0318

;; OPEN's RAM vector, which <KernalOpen> goes through: <Channels::Open> from start-up.
;; Also: IOPEN (KV20, MTV)
OpenVector = $031A

;; CLOSE's RAM vector, which <KernalClose> goes through: <Channels::Close> from start-up.
;; Also: ICLOSE (KV20, MTV)
CloseVector = $031C

;; CHKIN's RAM vector, which <KernalSelectInput> goes through: <Channels::SelectInput> from start-up.
;; Also: ICHKIN (KV20, MTV)
SelectInputVector = $031E

;; CHKOUT's RAM vector, which <KernalSelectOutput> goes through: <Channels::SelectOutput> from start-up.
;; Also: ICKOUT (KV20, MTV)
SelectOutputVector = $0320

;; CLRCHN's RAM vector, which <KernalResetChannels> goes through: <Channels::ResetChannels> from start-up.
;; Also: ICLRCH (KV20, MTV)
ResetChannelsVector = $0322

;; CHRIN's RAM vector, which <KernalCharacterIn> goes through: <Channels::CharacterIn> from start-up.
;; Also: IBASIN (KV20, MTV)
CharacterInVector = $0324

;; CHROUT's RAM vector, which <KernalCharacterOut> goes through: <Channels::CharacterOut> from start-up.
;; Also: IBSOUT (KV20, MTV)
CharacterOutVector = $0326

;; STOP's RAM vector, which <KernalTestStopKey> goes through: <Channels::TestStopKey> from start-up.
;; Also: ISTOP (KV20, MTV)
TestStopKeyVector = $0328

;; GETIN's RAM vector, which <KernalGetInput> goes through: <Channels::GetInput> from start-up.
;; Also: IGETIN (KV20, MTV)
GetInputVector = $032A

;; CLALL's RAM vector, which <KernalCloseAll> goes through: <Channels::CloseAll> from start-up.
;; Also: ICLALL (KV20, MTV)
CloseAllFilesVector = $032C

;; LOAD's RAM vector, which <KernalLoad> goes through once it has kept the address: <Channels::Load> from start-up.
;; Also: ILOAD (KV20, MTV)
LoadVector = $0330

;; SAVE's RAM vector, which <KernalSave> goes through once it has kept the range: <Channels::Save> from start-up.
;; Also: ISAVE (KV20, MTV)
SaveVector = $0332

; The tape buffer.

;; The tape buffer, 192 bytes from $033C: a file's header, or a data file's block, on its way to or from the tape.
;; <TapeBuffer> points at it.
;; Also: TBUFFR (KV20, MTV)
TapeBufferArea = $033C

; The screen and colour memory.

;; The screen's place with RAM in block 1, $1000; unexpanded it is at $1E00, which has the same low byte.
;;
;; <ScreenPage> says which page it is at; the editor makes its table of the rows' low bytes from this address.
;; Also: VICSCN (KV20)
ScreenMemory = $1000

;; The colour RAM, $9400-$97FF, four bits for each screen byte: a character's colour is at this address plus the
;; character's place in the screen's kilobyte, $9400 for the screen at $1000 and $9600 for the one at $1E00.
;; Also: VICCOL (KV20)
ColourMemory = $9400

; The VIC, the 6560 (NTSC) or 6561 (PAL) video interface chip: its 16 registers at $9000-$900F.

;; The VIC's first register, which the editor's start-up table is loaded into, all 16 at once.
;; Also: VICREG (KV20)
VicRegisters = $9000

;; Bits 0-6: the screen's left edge, in steps of 4 pixels; bit 7: interlace.
;; Also: VICCR0 (MTV)
VicHorizontalOrigin = $9000

;; The screen's top edge, in steps of 2 lines.
;; Also: VICCR1 (MTV)
VicVerticalOrigin = $9001

;; Bits 0-6: the screen's columns; bit 7: bit 9 of the screen's and the colour RAM's addresses.
;; Also: VICCR2 (MTV)
VicColumns = $9002

;; Bit 0: characters 8 by 16 pixels, not 8 by 8; bits 1-6: the screen's rows; bit 7: bit 0 of the raster line.
;; Also: VICCR3 (MTV)
VicRows = $9003

;; Bits 1-8 of the line the VIC is drawing, read only.
;; Also: VICCR4 (MTV)
VicRaster = $9004

;; Bits 0-3: where the character patterns are; bits 4-7: where the screen is. Bit 1 picks the character set the
;; editor switches between, upper case and graphics or lower and upper case.
;; Also: VICCR5 (MTV)
VicScreenAndCharacters = $9005

;; The light pen's horizontal position, read only.
;; Also: VICCR6 (MTV)
VicLightPenX = $9006

;; The light pen's vertical position, read only.
;; Also: VICCR7 (MTV)
VicLightPenY = $9007

;; The first paddle's position, read only.
;; Also: VICCR8 (MTV)
VicPaddleX = $9008

;; The second paddle's position, read only.
;; Also: VICCR9 (MTV)
VicPaddleY = $9009

;; The lowest voice: bit 7 turns it on, bits 0-6 set its pitch.
;; Also: VICCRA (MTV)
VicVoice1 = $900A

;; The middle voice, as <VicVoice1>.
;; Also: VICCRB (MTV)
VicVoice2 = $900B

;; The highest voice, as <VicVoice1>.
;; Also: VICCRC (MTV)
VicVoice3 = $900C

;; The noise voice, as <VicVoice1>.
;; Also: VICCRD (MTV)
VicNoise = $900D

;; Bits 0-3: the volume; bits 4-7: the auxiliary colour of multicolour characters.
;; Also: VICCRE (MTV)
VicVolume = $900E

;; Bits 0-2: the border's colour; bit 3: clear for reversed characters; bits 4-7: the background's colour.
;; Also: VICCRF (MTV)
VicBackgroundAndBorder = $900F

; VIA 1, the 6522 at $9110: the user port and RS-232, the serial bus's inputs and ATN, the joystick, the cassette's
; PLAY key and motor, and the RESTORE key's NMI. The latches and the shift register are not used.

;; VIA 1's port B: the user port's eight lines, which RS-232 uses for its received data (PB0) and its handshake
;; signals.
;; Also: D1ORB (KV20), VIA1PB (MTV)
Via1PortB = $9110

;; VIA 1's port A, read with CA1's handshake: reading it clears the RESTORE key's interrupt flag.
;; Also: D1ORAH (KV20), VIA1PA1 (MTV)
Via1PortAHandshake = $9111

;; VIA 1's port B direction register: a bit set makes the user port's line an output.
;; Also: D1DDRB (KV20)
Via1DirectionB = $9112

;; VIA 1's port A direction register: only bit 7, the serial bus's ATN, is an output.
;; Also: D1DDRA (KV20)
Via1DirectionA = $9113

;; VIA 1's timer 1, low byte: RS-232's bit timer for sending.
;; Also: D1T1L (KV20)
Via1Timer1 = $9114

;; VIA 1's timer 1, high byte: writing it starts the timer.
;; Also: D1T1H (KV20)
Via1Timer1High = $9115

;; VIA 1's timer 1 latch, low byte; not used.
;; Also: D1T1LL (KV20)
Via1Timer1Latch = $9116

;; VIA 1's timer 1 latch, high byte; not used.
;; Also: D1T1LH (KV20)
Via1Timer1LatchHigh = $9117

;; VIA 1's timer 2, low byte: RS-232's bit timer for receiving.
;; Also: D1T2L (KV20)
Via1Timer2 = $9118

;; VIA 1's timer 2, high byte: writing it starts the timer.
;; Also: D1T2H (KV20)
Via1Timer2High = $9119

;; VIA 1's shift register; not used.
;; Also: D1SR (KV20)
Via1Shift = $911A

;; VIA 1's auxiliary control register: the timers' modes, the shift register and the ports' latches.
;; Also: D1ACR (KV20)
Via1AuxiliaryControl = $911B

;; VIA 1's peripheral control register: CA1 is the RESTORE key, CA2 drives the cassette's motor (low runs it), CB1
;; is RS-232's received data and CB2 its sent data.
;; Also: D1PCR (KV20)
Via1PeripheralControl = $911C

;; VIA 1's interrupt flags: bit 1 the RESTORE key, bits 4-6 RS-232's received data edge and its two timers.
;; Also: D1IFR (KV20)
Via1InterruptFlags = $911D

;; VIA 1's interrupt enable register, whose sources make NMIs: the RESTORE key, and RS-232's while it runs.
;; Also: D1IER (KV20)
Via1InterruptEnable = $911E

;; VIA 1's port A, without the handshake: bit 0 the serial bus's CLK in, bit 1 DATA in, bits 2-5 the joystick, bit
;; 6 the cassette's PLAY key (clear while down), bit 7 ATN out.
;; Also: D1ORA (KV20), VIA1PA2 (MTV)
Via1PortA = $911F

; VIA 2, the 6522 at $9120: the keyboard, the cassette's read and write lines, the serial bus's CLK and DATA outputs,
; and the jiffy interrupt. The latches and the shift register are not used.

;; VIA 2's port B: the keyboard's columns out, bit 3 the cassette's write line too, and bit 7 the joystick's right.
;; Also: D2ORB (KV20), VIA2PB (MTV)
Via2PortB = $9120

;; VIA 2's port B by its job in the keyboard scan: the columns, one driven low at a time.
;; Inherit: <Via2PortB>
;; Also: COLM (KV20)
KeyboardColumns = $9120

;; VIA 2's port A, read with CA1's handshake: the keyboard's rows; CA1 is the cassette's read line, and reading
;; here clears its flag.
;; Also: D2ORAH (KV20), VIA2PA1 (MTV)
Via2PortAHandshake = $9121

;; VIA 2's port A by its job in the keyboard scan: the rows, a bit clear for each key down in the driven column.
;; Inherit: <Via2PortAHandshake>
;; Also: ROWS (KV20)
KeyboardRows = $9121

;; VIA 2's port B direction register: every bit an output, for the keyboard's columns.
;; Also: D2DDRB (KV20)
Via2DirectionB = $9122

;; VIA 2's port A direction register: every bit an input, for the keyboard's rows.
;; Also: D2DDRA (KV20)
Via2DirectionA = $9123

;; VIA 2's timer 1, low byte: the jiffy interrupt, 60 times a second, and while the tape runs its pulse timer.
;; Reading it clears the timer's interrupt flag.
;; Also: D2T1L (KV20)
Via2Timer1 = $9124

;; VIA 2's timer 1, high byte: writing it starts the timer.
;; Also: D2T1H (KV20)
Via2Timer1High = $9125

;; VIA 2's timer 1 latch, low byte; not used.
;; Also: D2T1LL (KV20)
Via2Timer1Latch = $9126

;; VIA 2's timer 1 latch, high byte; not used.
;; Also: D2T1LH (KV20)
Via2Timer1LatchHigh = $9127

;; VIA 2's timer 2, low byte: the tape's pulses are measured on it, and the serial bus's waits and timeouts.
;; Also: D2T2L (KV20)
Via2Timer2 = $9128

;; VIA 2's timer 2, high byte: writing it starts the timer.
;; Also: D2T2H (KV20)
Via2Timer2High = $9129

;; VIA 2's shift register; not used.
;; Also: D2SR (KV20)
Via2Shift = $912A

;; VIA 2's auxiliary control register: the timers' modes, the shift register and the ports' latches.
;; Also: D2ACR (KV20)
Via2AuxiliaryControl = $912B

;; VIA 2's peripheral control register: CA1 is the cassette's read line, CA2 drives the serial bus's CLK and CB2 its
;; DATA (high pulls the line low), and CB1 is the bus's SRQ.
;; Also: D2PCR (KV20)
Via2PeripheralControl = $912C

;; VIA 2's interrupt flags: bit 6 timer 1, bit 5 timer 2, bit 1 the cassette's read line.
;; Also: D2IFR (KV20)
Via2InterruptFlags = $912D

;; VIA 2's interrupt enable register, whose sources make IRQs: timer 1 for the jiffy, and the tape's while it runs.
;; Also: D2IER (KV20)
Via2InterruptEnable = $912E

;; VIA 2's port A, without the handshake: the keyboard's rows, which <Clock::Tick> reads for the STOP key.
;; Also: D2ORA (KV20), VIA2PA2 (MTV)
Via2PortA = $912F

; The cartridge's and BASIC's start vectors.

;; A cartridge's cold-start address, its first word at $A000: <Startup::Reset> jumps through it when
;; <Startup::FindCartridge> finds the cartridge's signature.
CartridgeColdStart = $A000

;; A cartridge's warm-start address, its second word: the NMI handler jumps through it for the RESTORE key when the
;; cartridge's signature is there.
CartridgeWarmStart = $A002

;; Where a cartridge has the five bytes of <Startup::CartridgeSignature>, after its two start addresses.
CartridgeSignatureArea = $A004

;; BASIC's cold-start address, the first word of its ROM: <Startup::Reset> starts BASIC through it.
BasicColdStart = $C000

;; BASIC's warm-start address, the second word of its ROM, which STOP-RESTORE and BRK start BASIC through.
BasicWarmStart = $C002

; Constants. The listing also declares LLEN2 (44, a two-row line's columns) and CR (13, RETURN), which the code does
; not use by name.

; The devices, as <InputDevice>, <OutputDevice> and <Device> number them.

;; The 6502's BIT absolute opcode: as a data byte it makes the next two bytes its operand, so it skips the
;; instruction they hold, as the error entries and the serial bus's TALK and UNTALK use it.
OPCODE_BIT = $2C

;; RETURN, the character that ends a line, in PETSCII and the screen editor's input.
CARRIAGE_RETURN = $0D

;; The keyboard, device 0.
DEVICE_KEYBOARD = 0

;; The Datasette, device 1.
DEVICE_TAPE = 1

;; RS-232 on the user port, device 2.
DEVICE_RS232 = 2

;; The screen, device 3; devices 4 to 31 are on the serial bus.
DEVICE_SCREEN = 3

; The tape: a header's type, the first byte of a header block, and the buffer's size.

;; A header's type: a program that loads where BASIC's program starts, wherever it was saved from.
;; Also: BLF (KV20)
TAPE_PROGRAM = 1

;; A data file's block: the first byte of each block of data after a data file's header.
;; Also: BDF (KV20)
TAPE_DATA = 2

;; A header's type: a program that loads at the address it was saved from.
;; Also: PLF (KV20)
TAPE_PROGRAM_FIXED = 3

;; A header's type: a data file's header, which its data blocks follow.
;; Also: BDFH (KV20)
TAPE_DATA_HEADER = 4

;; A header's type: the end of the tape, which a search stops at.
;; Also: EOT (KV20)
TAPE_END_OF_TAPE = 5

;; The tape buffer's size, 192 bytes.
;; Also: BUFSZ (KV20)
TAPE_BUFFER_SIZE = 192

; The screen.

;; The screen's columns, 22 to a row.
;; Also: LLEN (KV20)
SCREEN_COLUMNS = 22

;; The screen's rows, 23.
;; Also: NLINES (KV20)
SCREEN_ROWS = 23

;; The most characters in a logical line, 88: four rows.
;; Also: MAXCHR (KV20)
LONGEST_LINE = 88

;; The most rows a logical line takes, 4.
;; Also: NWRAP (KV20)
ROWS_PER_LINE = 4

;; White, the screen's colour from start-up.
;; Also: WHITE (KV20)
COLOUR_WHITE = 1

;; Blue, the characters' colour from start-up.
;; Also: BLUE (KV20)
COLOUR_BLUE = 6

; The bits of <IoStatus>.

;; <IoStatus>: the serial bus's listener did not take a byte in time (the bus's write timeout sets this bit and the
;; next).
STATUS_WRITE_TIMEOUT = $01

;; <IoStatus>: the serial bus's talker sent nothing in time, a read timeout.
STATUS_READ_TIMEOUT = $02

;; <IoStatus>: a tape block that ended early.
;; Also: SBERR (KV20)
STATUS_SHORT_BLOCK = 4

;; <IoStatus>: a tape block longer than it should be.
;; Also: LBERR (KV20)
STATUS_LONG_BLOCK = 8

;; <IoStatus>: bytes that both copies of a tape block had wrong, or that VERIFY found different.
;; Also: SPERR (KV20)
STATUS_SECOND_PASS_ERROR = 16

;; <IoStatus>: a tape block whose checksum does not match its bytes.
;; Also: CKERR (KV20)
STATUS_CHECKSUM_ERROR = 32

;; <IoStatus>: the end of the file, the serial bus's EOI or a tape data file's last byte.
STATUS_END_OF_FILE = $40

;; <IoStatus>: no device answered on the serial bus.
STATUS_DEVICE_NOT_PRESENT = $80

; RS-232.

;; About the clock cycles the NMI takes from a start bit's edge to starting VIA 1's timer 2: <Rs232::BaudRates>' half
;; bit times are this much shorter, so that the bits are sampled near their middles.
;; Also: CBIT (KV20)
START_BIT_LATENCY = 100

; The kernal's errors: the numbers the jump table's routines return in A, with carry set, and print as I/O ERROR #n
; when <MessageMode>'s bit 6 is set.

;; Error 1, TOO MANY FILES: ten files are open already.
KERNAL_ERROR_TOO_MANY_FILES = 1

;; Error 2, FILE OPEN: the logical file number is in use.
KERNAL_ERROR_FILE_OPEN = 2

;; Error 3, FILE NOT OPEN: no open file has the logical file number.
KERNAL_ERROR_FILE_NOT_OPEN = 3

;; Error 4, FILE NOT FOUND: the tape or the serial bus has no file of the name.
KERNAL_ERROR_FILE_NOT_FOUND = 4

;; Error 5, DEVICE NOT PRESENT: no device answered on the serial bus.
KERNAL_ERROR_DEVICE_NOT_PRESENT = 5

;; Error 6, NOT INPUT FILE: the file was opened for output.
KERNAL_ERROR_NOT_INPUT_FILE = 6

;; Error 7, NOT OUTPUT FILE: the file was opened for input.
KERNAL_ERROR_NOT_OUTPUT_FILE = 7

;; Error 8, MISSING FILE NAME: the operation needs a file name and was given none.
KERNAL_ERROR_MISSING_FILE_NAME = 8

;; Error 9, ILLEGAL DEVICE NUMBER: the device cannot do what was asked, such as LOAD from the screen.
KERNAL_ERROR_ILLEGAL_DEVICE = 9

; The VIAs.

;; An interrupt enable register's bit 7: set, the bits written as 1 turn their sources on; clear, they turn them off.
VIA_INTERRUPTS_ON = $80

;; Every source in an interrupt enable register, bits 0-6: written alone, with bit 7 clear, it turns them all off.
VIA_INTERRUPTS_ALL = $7F

;; An interrupt bit: CA1's edge, the RESTORE key's on VIA 1.
VIA_INTERRUPT_CA1 = $02

;; An interrupt bit: timer 1's time-out, the jiffy's on VIA 2.
VIA_INTERRUPT_TIMER1 = $40

;; An auxiliary control register's value: timer 1 free-running, so that it reloads and interrupts again by itself,
;; timer 2 one-shot, the shift register off and the ports unlatched.
VIA_TIMER1_FREE_RUNNING = %01000000

;; A direction register's value: every line an input.
VIA_ALL_INPUTS = %00000000

;; A direction register's value: every line an output.
VIA_ALL_OUTPUTS = %11111111

;; VIA 1's port A, bit 7: the serial bus's ATN output, the only output on the port (set pulls ATN low).
VIA1_SERIAL_ATN = %10000000

; The jiffy clock.

.if PAL
;; VIA 2's timer 1 count for 60 interrupts a second: 18470 ($4826) in the <PAL> kernal, 901486-07, whose processor
;; runs faster than NTSC's (1.108 MHz against 1.023 MHz, where the count is 17033), so the jiffy is a sixtieth of a
;; second on both.
;; Also: SIXTY (KV20)
JIFFY_TIMER_COUNT = 18470
.else
;; VIA 2's timer 1 count for 60 interrupts a second: 17033 ($4289) in the NTSC kernal, 901486-06 (18470 in the <PAL>
;; kernal, whose processor runs faster), so the jiffy is a sixtieth of a second on both.
;; Also: SIXTY (KV20)
JIFFY_TIMER_COUNT = 17033
.endif

;; The Datasette's routines: the headers, the buffer, the motor, and the interrupt routines that read and write the
;; tape's pulses. Most of its variables share bytes with the serial bus's and RS-232's, since only one device runs at a
;; time.
.scope Tape

; Zero page.

;; Reading: how far the last dipole's time was from what it should be, which moves <Tape::TimeCorrection>.
;; Also: SVXT (KV20, MTV)
TimingAdjust = $0092

;; Reading: the count of zeros, 16 or more, once a block's leader has been found; the byte marker that starts the
;; data clears it.
;; Also: SYNO (KV20)
BlockSync = $0096

;; The parity of the byte being read or written, bit 0, from each bit as it goes.
;; Also: PRTY (KV20, MTV)
Parity = $009B

;; Reading: set by a byte marker, so that the next pulse finishes the byte and starts the next.
;; Also: DPSW (KV20, MTV)
ByteMarkerSeen = $009C

;; Reading: the index in <Tape::BadBytes> of its next entry: two bytes for each byte the first copy of a block had
;; wrong, at most 31 (to $013D).
;; Also: PTR1 (KV20, MTV)
FirstPassErrors = $009E

;; Reading: how far the second copy of a block has come through <Tape::BadBytes>, correcting the logged bytes.
;; Also: PTR2 (KV20, MTV)
SecondPassErrors = $009F

;; A temporary of the tape's file routines: the index in the tape buffer while a file name is copied into a header
;; or compared with one. The listing's TMPC, a third name for the byte, is not used.
;; Also: T2 (KV20)
Temporary2 = $009F

;; Reading and writing: the bits left of the byte, then the parity bit (negative once the byte's bits are done).
;; Also: PCNTR (KV20, MTV)
BitCount = $00A3

;; Reading and writing: which half of the bit's dipole is being timed, 0 or 1.
;; Also: FIRT (KV20, MTV)
Dipole = $00A4

;; Writing: the countdown bytes still to write before a block's data, from 9.
;; Also: CNTDN (KV20, MTV)
SyncCountdown = $00A5

;; The index of the next byte in the tape buffer, for the character reads and writes of a data file.
;; Also: BUFPT (KV20)
BufferIndex = $00A6

;; Writing: the short pulses still to write in a leader or trailer, low byte. Reading, the same byte is
;; <Tape::CopiesLeft>.
;; Also: SHCNL (KV20)
ShortCountLow = $00A7

;; Reading: the block's copies still to read, which steers the byte handler.
;; The listing's name for the byte, SHCNL, is <Tape::ShortCountLow>'s.
CopiesLeft = $00A7

;; Reading: set when a pulse goes wrong in the byte being read. Writing, the same byte is
;; <Tape::MarkerLongWritten>.
;; Also: RER (KV20)
ReadError = $00A8

;; Writing: set once the byte marker's long half is written.
;; The listing's name for the byte, RER, is <Tape::ReadError>'s.
MarkerLongWritten = $00A8

;; Reading: the zeros counted less the ones, for finding a leader. Writing, the same byte is
;; <Tape::MarkerOneWritten>.
;; Also: REZ (KV20)
ZeroesCount = $00A9

;; Writing: set once the byte marker's second half is written.
;; The listing's name for the byte, REZ, is <Tape::ZeroesCount>'s.
MarkerOneWritten = $00A9

;; Reading: what the byte handler does with each byte: $80 ignores bytes to the next leader, $40 loads them, 1-15
;; counts the countdown down, and 0 waits for the countdown.
;; Also: RDFLG (KV20)
ReadMode = $00AA

;; Writing: the leader's short pulses still to write, high byte. Reading, the same byte is <Tape::LoadChecksum>.
;; Also: SHCNH (KV20)
ShortCountHigh = $00AB

;; Reading: the exclusive or of a block's bytes, checked against the checksum at the block's end. Writing keeps its
;; checksum in <Tape::WriteChecksum>.
;; The listing's name for the byte, SHCNH, is <Tape::ShortCountHigh>'s.
LoadChecksum = $00AB

;; Reading: the correction to the pulses' expected lengths, which follows the tape's speed.
;; Also: CMP0 (KV20)
TimeCorrection = $00B0

;; Reading and writing: a temporary of the pulse timing.
;; Also: TEMP (KV20)
Temporary = $00B1

;; Reading: set once the block's byte sync has been found, so that bytes are assembled.
;; Also: SNSW1 (KV20)
SyncFound = $00B4

;; Reading: <Tape::BlockSync> as the last byte marker found it, for the byte handler.
;; Also: DIFF (KV20)
BlockSyncSaved = $00B5

;; Reading: the byte's error flag and zero count together; non-zero means the byte was read wrong.
;; Also: PRP (KV20)
ByteErrors = $00B6

;; Reading: the byte just finished, for the byte handler. Writing: the byte being written.
;; Also: OCHAR (KV20)
OutputCharacter = $00BD

;; Reading and writing: the copies of the block still to come, 2, 1, then 0.
;; Also: FSBLK (KV20, MTV)
BlockCount = $00BE

;; Reading: the byte being put together from the bits, shifted in from the top.
;; Also: MYCH (KV20, MTV)
ByteBuffer = $00BF

;; The address a save starts from, which <Channels::SaveRange> sets for every device, or a tape program loads at,
;; low byte.
;; Also: STAL (KV20, MTV)
LoadAddress = $00C1

;; <Tape::LoadAddress>'s high byte.
;; Also: STAH (KV20)
LoadAddressHigh = $00C2

; The stack page and page 2.

;; Reading: the log of the bytes the first copy of a block had wrong, two bytes each, at the bottom of the stack page.
;; Also: BAD (KV20, MTV)
BadBytes = $0100

;; The IRQ vector the tape routines keep while they have the interrupt, put back when they finish.
;; Also: IRQTMP (KV20)
SavedIrq = $029F

.endscope

;; The serial bus, which the disk drives and printers are on: its lines, the commands under ATN, and the bytes sent
;; and received with the bus's handshake.
.scope Serial

; Zero page.

;; Bit 7 set while a character waits in <Serial::BufferedCharacter>: each is sent when the next comes, so that the
;; last can go with EOI.
;; Also: C3P0 (KV20, MTV)
CharacterWaiting = $0094

;; The character, or the command, waiting to be sent on the bus.
;; Also: BSOUR (KV20, MTV)
BufferedCharacter = $0095

;; Bit 7 set to send the next byte with EOI, as the last of the file.
;; Also: R2D2 (KV20)
EndOfFile = $00A3

;; The byte coming in on the bus, a bit at a time.
;; Also: BSOUR1 (KV20)
ReceivedByte = $00A4

;; The bits left to send or receive, and the count of timeouts while waiting for a byte.
;; Also: COUNT (KV20, MTV)
BitCount = $00A5

; Page 2.

;; The PET's IEEE-488 timeout switch, which SETTMO sets; the VIC-20's serial routines never read it.
;; Also: TIMOUT (KV20, MTV)
TimeoutFlag = $0285

.endscope

;; RS-232 on the user port, done in software: the NMI times each bit with VIA 1's timers, and OPEN gives the input and
;; output buffers 256 bytes each below the top of memory.
.scope Rs232

; Zero page.

;; Receiving: the last bit sampled from the line.
;; Also: INBIT (KV20, MTV)
ReceivedBit = $00A7

;; Receiving: the bits still to come in the word.
;; Also: BITCI (KV20, MTV)
ReceiveBitCount = $00A8

;; Receiving: set while waiting for a start bit.
;; Also: RINONE (KV20, MTV)
WaitingForStart = $00A9

;; Receiving: the byte the bits are shifted into.
;; Also: RIDATA (KV20, MTV)
ReceivedByte = $00AA

;; Receiving: the parity of the bits received so far.
;; Also: RIPRTY (KV20, MTV)
ReceivedParity = $00AB

;; Sending: the bits still to go out.
;; Also: BITTS (KV20)
SendBitCount = $00B4

;; Sending: the next bit to put on the line.
;; Also: NXTBIT (KV20, MTV)
NextBit = $00B5

;; Sending: the byte being shifted out.
;; Also: RODATA (KV20, MTV)
SendByte = $00B6

;; Sending: the parity of the bits sent so far.
;; Also: ROPRTY (KV20, MTV)
SendParity = $00BD

;; A pointer to the 256-byte input buffer, which OPEN takes from the top of memory; a high byte of 0 means none.
;; Also: RIBUF (KV20, MTV)
InputBuffer = $00F7

;; A pointer to the 256-byte output buffer, taken the same way.
;; Also: ROBUF (KV20, MTV)
OutputBuffer = $00F9

; Page 2.

;; Like a 6551's control register, the first byte of OPEN's file name: bits 0-3 the baud rate, bits 5-6 the word
;; length (8 to 5 bits), bit 7 two stop bits.
;; Also: M51CTR (KV20, MTV)
Control = $0293

;; Like a 6551's command register, the second byte of OPEN's file name: bit 0 the full handshake, bit 4 half duplex,
;; bits 5-7 the parity.
;; Also: M51CDR (KV20, MTV)
Command = $0294

;; RS-232's status: bit 0 a parity error, bit 1 a framing error, bit 2 the input buffer full, bit 4 CTS missing, bit
;; 6 DSR missing, bit 7 a break. READST clears it.
;; Also: RSSTAT (KV20, MTV)
Status = $0297

;; The word's data bits plus one, 6 to 9, which OPEN works out from <Rs232::Control>: the count each byte starts from.
;; Also: BITNUM (KV20, MTV)
WordBits = $0298

;; A bit's time in clock cycles for the baud rate, two bytes, which OPEN works out from <Rs232::BaudRates>.
;; Also: BAUDOF (KV20, MTV, V20PRG)
BitTime = $0299

;; The index in the input buffer where the next byte received goes.
;; Also: RIDBE (KV20, MTV)
InputEnd = $029B

;; The index in the input buffer of the next byte to read.
;; Also: RIDBS (KV20)
InputStart = $029C

;; The index in the output buffer of the next byte to send.
;; Also: RODBS (KV20, MTV)
OutputStart = $029D

;; The index in the output buffer where the next byte to send goes.
;; Also: RODBE (KV20, MTV)
OutputEnd = $029E

.endscope

;; Start-up: the reset, the RAM test that places the screen and BASIC, the RAM vectors' defaults, the VIAs' set-up,
;; and the calls that read and set the memory's top and bottom.
.scope Startup

;; The RAM test's pointer, the byte being tested. <Tape::LoadAddress> is the same byte.
;; Also: TMP0 (KV20)
Pointer = $00C1

;; <Startup::RestoreVectors::Copy>'s pointer to the caller's 32 bytes of vectors. <::LoadAddress> (MEMUSS) is the
;; same byte.
;; Also: TMP2 (KV20)
Temporary = $00C3

.endscope

;; The screen editor and the keyboard: printing to the screen and its control characters, logical lines of up to four
;; rows, reading a line back from the screen for input, and the keyboard scan.
.scope Editor

; Zero page.

;; The keyboard matrix's code of the key down at the last scan, 64 for none: a key the same as it repeats.
;; Also: LSTX (KV20, MTV)
LastKey = $00C5

;; Non-zero while characters print reversed, after RVS ON.
;; Also: RVS (KV20, MTV)
Reverse = $00C7

;; The column of the last character of the line being read back from the screen.
;; Also: INDX (KV20, MTV)
LineEnd = $00C8

;; The row the cursor was on when keyboard input started, so that the line read back starts there; the scroll moves
;; it up with the screen.
;; Also: LSXP (KV20)
InputRow = $00C9

;; The column the cursor was at when keyboard input started.
;; Also: LSTP (KV20)
InputColumn = $00CA

;; The matrix code of the key this scan found, 64 for none.
;; Also: SFDX (KV20, MTV)
KeyDown = $00CB

;; 0 while the cursor blinks: input sets it from <KeyboardBufferCount>, so it blinks while no key waits.
;; Also: BLNSW (KV20)
BlinkOff = $00CC

;; Jiffies until the cursor next blinks, counted down from 20.
;; Also: BLNCT (KV20)
BlinkCountdown = $00CD

;; The character the cursor covers, put back when it stops blinking.
;; Also: GDBLN (KV20)
CharacterUnderCursor = $00CE

;; 1 while the cursor's reversed phase shows.
;; Also: BLNON (KV20)
CursorShown = $00CF

;; Non-zero while CHRIN reads a line back from the screen; 0 while it waits for keys.
;; Also: CRSW (KV20, MTV)
InputFromScreen = $00D0

;; A pointer to the start of the cursor's logical line in screen memory.
;; Also: PNT (KV20, MTV)
Line = $00D1

;; The cursor's column in its logical line, 0 to 87.
;; Also: PNTR (KV20, MTV)
Column = $00D3

;; Non-zero inside quotes, where the cursor and colour keys print as reversed characters instead of acting.
;; Also: QTSW (KV20, MTV)
QuoteMode = $00D4

;; The logical line's last column: 21, 43, 65 or 87.
;; Also: LNMX (KV20, MTV)
LineLength = $00D5

;; The cursor's row, 0 to 22.
;; Also: TBLX (KV20, MTV)
Row = $00D6

;; The character being printed; the tape routines use the byte for theirs too (a dipole's first half, or the
;; checksum being written).
;; Also: DATA (KV20, MTV)
Character = $00D7

;; How many inserted spaces are still open: until they are filled, the cursor and colour keys print as characters.
;; Also: INSRT (KV20, MTV)
Inserts = $00D8

;; The rows' links, one for each row and one more, then $FF at $F1 to end them.
;;
;; A link's bit 7 is set on a row that starts a logical line, clear on one that continues the row above; its low
;; bits, with <ScreenPage>'s, are the high byte of the row's address.
;; Also: LDTB1 (KV20, MTV)
LineLinks = $00D9

;; A row the scroll and the line insert keep while they move rows and their links.
;; Also: LINTMP (KV20)
LinkSave = $00F2

;; A pointer to the cursor's logical line in the colour RAM.
;; Also: USER (KV20, MTV)
ColourLine = $00F3

;; A pointer to the keyboard table for the shift keys down: unshifted, SHIFT, the Commodore key or CTRL.
;; Also: KEYTAB (KV20, MTV)
KeyTable = $00F5

; Page 2.

;; The colour of the character the cursor covers, put back with it.
;; Also: GDCOL (KV20, MTV)
ColourUnderCursor = $0287

;; Jiffies between the repeats of a held key, counted down from 4.
;; Also: KOUNT (KV20)
RepeatInterval = $028B

;; Jiffies before a held key starts to repeat: 16 from each new key.
;; Also: DELAY (KV20)
RepeatDelay = $028C

;; The shift keys at the last scan, so that holding SHIFT with the Commodore key switches the character set once.
;; Also: LSTSHF (KV20, MTV)
LastShiftKeys = $028E

;; Non-zero, as once input has a key to echo (it is 0 while input waits for one), lets a line that grows past its
;; row push the rows below it down; 0, as for output from a program, makes it take the row below instead. Despite its
;; name, non-zero is the one that scrolls.
;; Also: AUTODN (KV20, MTV)
ScrollDownOff = $0292

.endscope
