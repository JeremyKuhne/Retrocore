;; PET BASIC 4 RAM LOCATIONS, SHARED BY THE SCREEN EDITORS AND THE KERNAL
;;
;; The page-zero, stack-page and page 2-3 locations the editors (Editor4.asm) and the kernal (Kernal4.asm) of the
;; 4016 and 4032 keep their state in, the values the kernal stores in <CQSTAT>, the editors' keys, and the PIA
;; control values both write. Both sources include this file, after PetEquates.asm.
;;
;; BASIC 4 keeps the kernal's page zero where BASIC 2 has it, so most names and addresses are BASIC 2's. BASIC's own
;; locations that the ROMs read or write are named as Microsoft's m6502.asm names them for its Commodore build. The
;; rest follow the names Commodore's 1979 BASIC 4 kernal listing gives them where its names are Commodore's later
;; ones (<NDX>, <LSTX>, <PNTR>, <FNLEN>, <LDTB1>, <BOB>), and otherwise are named after what the ROMs keep there.
;; Several tape locations do one job while a block is read and another while one is written; their documentation
;; gives both.

; BASIC's page zero, as m6502.asm's Commodore build lays it out for BASIC 4.
CHANNL = $10                ;; BASIC's current I/O channel: the logical file of a CMD, or 0 for the screen.
LINNUM = $11                ;; BASIC's integer result, two bytes: SYS jumps through it.
INDEX = $1F                 ;; BASIC's string pointer, two bytes: where a string evaluated for a file name is.
TXTTAB = $28                ;; The start of the BASIC program, two bytes: where LOAD and SAVE begin.
VARTAB = $2A                ;; The end of the BASIC program (its variables' start), two bytes: where SAVE stops.
CHRGOT = $76                ;; BASIC's routine in page zero that rereads the current character of the program text.
TXTPTR = $77                ;; The program-text pointer inside CHRGET, two bytes; its high byte is 2 in direct mode.
CQTIMR = $8D                ;; The jiffy clock TI, three bytes, high byte first: sixtieths of a second since midnight.
CQSTAT = $96                ;; The I/O status ST: the ST_ bits of the last operation.
BUF = $0200                 ;; BASIC's input buffer, where TXTPTR points in direct mode.

; Interrupt vectors in page zero.
CINV = $90                  ;; The IRQ vector, two bytes: <Editor4:KEY> normally, a tape handler while the tape runs.
CBINV = $92                 ;; The BRK vector, two bytes: the monitor's <BRKE>, in BASIC's ROM.
NMINV = $94                 ;; The NMI vector, two bytes: BASIC's <READY> after reset.

; The keyboard and the clock.
LSTX = $97                  ;; The key-table index of the key found down at the last scan, or $FF for none.
SHFLAG = $98                ;; 1 while a SHIFT key is down during a keyboard scan.
SKIP_COUNT = $99            ;; Jiffies since <CQTIMR> last skipped one, two bytes; it skips one in 623 to keep time.
STKEY = $9B                 ;; Keyboard row 9 as last read, low bits for keys down: $EF when only STOP is.
TAPE_DRIFT = $9C            ;; While reading tape, the signed drift of the pulse lengths from <TAPE_SPEED>.
VERCK = $9D                 ;; 0 to load, 1 to verify: whether tape and disk data is stored or compared.
NDX = $9E                   ;; The number of keys waiting in <KEYD>.
RVS = $9F                   ;; Nonzero while the screen prints reversed characters.
C3PO = $A0                  ;; $FF while a byte for the IEEE-488 bus waits in <BSOUR>, so the next can mark it last.
INDX = $A1                  ;; The column just past the last nonblank character of the logical line being read.
INPUT_ROW = $A3             ;; The row where the current INPUT began, or negative when none did.
INPUT_COLUMN = $A4          ;; The column where the current INPUT began, just past its prompt.
BSOUR = $A5                 ;; The byte waiting to go out on the IEEE-488 bus.
SFDX = $A6                  ;; The key-table index of the key the current scan found down, or $FF.
BLNSW = $A7                 ;; Zero while the cursor blinks, that is, while no key is waiting.
BLNCT = $A8                 ;; Jiffies until the cursor next blinks.
GDBLN = $A9                 ;; The character under the cursor, as it is when not reversed by the blink.
BLNON = $AA                 ;; Nonzero while the blink has the cursor's character reversed.
LEADER_SEEN = $AB           ;; While reading tape, the count of short pulses once a leader long enough is found.
CRSW = $AC                  ;; Nonzero while input comes from the line on the screen instead of the keyboard.
XSAV = $AD                  ;; X, saved while <Kernal4:BASIN> reads a byte from tape.
LDTND = $AE                 ;; The number of open files in <LAT>, <FAT> and <SAT>.
DFLTN = $AF                 ;; The input device: 0 the keyboard, 1-2 a cassette, 3 the screen, 4 up the bus.
DFLTO = $B0                 ;; The output device: 3 the screen, 1-2 a cassette, 4 up the bus.
PRTY = $B1                  ;; The parity of the tape byte being read or written.
DPSW = $B2                  ;; While reading tape, nonzero once a byte marker has been seen.
WORKA = $B4                 ;; Work byte: the byte going to tape, a file name index, a header's type.
WORKB = $B5                 ;; Work byte: a tape header's index while a file name is compared or stored.
BITCI = $B7                 ;; The tape bits left in the byte being read or written, counting down from 8.
PULSE_PHASE = $B9           ;; 1 between the first and second pulses of a tape bit.
SYNC_COUNT = $BA            ;; While writing tape, the sync bytes left before the block's data, from 9.
BUFPNT = $BB                ;; The index of the last byte used in each tape buffer, two bytes: cassette 1, then 2.
PASSES = $BD                ;; Reading tape, the copies of the block left (2, 1); writing, the pulses left in the leader's group.
PULSE_ERROR = $BE           ;; Reading tape, nonzero for a bad pulse; writing, nonzero once a byte marker's long pulse is out.
SEQUENCE = $BF              ;; Reading tape, the leader's pulse count, or bit errors; writing, nonzero once the marker's medium pulse is out.
PTR1 = $C0                  ;; Reading tape, the next free entry of <BAD>, the bad bytes of the first copy.
PTR2 = $C1                  ;; Reading tape, the next entry of <BAD> the second copy corrects.
BLOCK_STATE = $C2           ;; Reading tape: 0 waiting for sync, 1-15 sync bytes to come, $40 reading data, $80 done.
CHECKSUM = $C3              ;; Reading tape, the block's checksum; writing, the leader's groups still to go, counted down until negative.
PNT = $C4                   ;; The address of the cursor's line in video RAM, two bytes.
PNTR = $C6                  ;; The cursor's column in its logical line, 0-79.
SAL = $C7                   ;; A pointer, two bytes: the byte the tape reads or writes, or the source when scrolling.
EAL = $C9                   ;; The end of the memory a tape block or a SAVE covers, two bytes.
TAPE_SPEED = $CB            ;; While reading tape, the timing base the pulse lengths are compared with.
PULSE_WIDTH = $CC           ;; While reading tape, the length of the last pulse, in units of 4 microseconds.
QTSW = $CD                  ;; Bit 0 set inside quotes, where cursor keys print as reversed characters.
TIMER_ON = $CE              ;; While reading tape, nonzero once the VIA's timer 1 watches for the gap after a block.
END_SEEN = $CF              ;; While reading tape, nonzero once the gap after a block is found.
BYTE_ERROR = $D0            ;; While reading tape, nonzero when the byte just read is bad.
FNLEN = $D1                 ;; The length of the file name at <FNADR>.
LA = $D2                    ;; The current logical file number.
SA = $D3                    ;; The current secondary address, with $60 added once the file is open.
FA = $D4                    ;; The current device: 0 the keyboard, 1-2 a cassette, 3 the screen, 4 up the bus.
LNMX = $D5                  ;; The last column of the cursor's logical line: 39, or 79 for a line of two rows.
TAPE1 = $D6                 ;; The address of the current cassette's buffer, <TBUFFR1> or <TBUFFR2>, two bytes.
TBLX = $D8                  ;; The cursor's row, 0-24: the first row of its logical line.
CHAR_TEMP = $D9             ;; The character being printed or read; reading tape, a bit's first pulse; writing, the checksum.
FNADR = $DA                 ;; The address of the file name, two bytes.
INSRT = $DC                 ;; The number of characters INST has made room for that are still to be typed.
TAPE_BYTE = $DD             ;; The tape byte being written, or the byte just read.
FSBLK = $DE                 ;; The copies of a tape block left to read or write.
MYCH = $DF                  ;; While reading tape, the bits of the byte coming in.
LDTB1 = $E0                 ;; The screen line link table, 25 bytes: each row's video RAM page, bit 7 clear for a row continuing the row above.
CAS1 = $F9                  ;; Nonzero while the kernal runs cassette 1's motor, so the keys don't stop it.
CAS2 = $FA                  ;; Nonzero while the kernal runs cassette 2's motor, so the keys don't stop it.
STAL = $FB                  ;; The start address of a load or save, two bytes.

; The stack page and pages 2 and 3.
BAD = $0100                 ;; The tape read's error log: the address of each bad byte of a block's first copy, up to 31.
LAT = $0251                 ;; The open files' logical numbers, 10 bytes.
FAT = $025B                 ;; The open files' devices, 10 bytes.
SAT = $0265                 ;; The open files' secondary addresses, 10 bytes.
KEYD = $026F                ;; The keyboard buffer, 10 keys.
TBUFFR1 = $027A             ;; Cassette 1's buffer, 192 bytes.
TBUFFR2 = $033A             ;; Cassette 2's buffer, 192 bytes.
TAB_COLUMN = $033A          ;; The business editor's work byte in cassette 2's buffer: a column while it finds a tab stop.
TAB_BIT = $033E             ;; The business editor's work byte in cassette 2's buffer: a column's bit in its byte of <TAB_STOPS>.
TAB_STOPS = $03EE           ;; The business editor's tab stops, 10 bytes: a bit for each of 80 columns, column 0 in bit 0 of the first.
REPEAT_KEY = $03F8          ;; The business editor's REPEAT flag: 3 once a scan finds REPEAT down, shifted right as it is tested.
REPEAT_COUNT = $03F9        ;; The business editor's jiffies since a held key last repeated.
USRCMD = $03FA              ;; The monitor's vector for commands it doesn't know, two bytes: BASIC's <ERROPR> normally.
BOB = $03FC                 ;; With bit 7 set, the IEEE-488 handshake waits for a slow device until STOP instead of timing out.

; Sizes.
SCREEN_COLUMNS = 40         ;; The columns of a screen row.
SCREEN_ROWS = 25            ;; The rows of the screen.
KEY_BUFFER_SIZE = 10        ;; The keys <KEYD> holds.
MAX_FILES = 10              ;; The files that can be open at once.
TAPE_BUFFER_SIZE = 192      ;; The bytes of a tape block that a cassette buffer holds.

; Devices.
DEV_KEYBOARD = 0            ;; The keyboard.
DEV_SCREEN = 3              ;; The screen.
DEV_IEEE = 4                ;; The first device on the IEEE-488 bus; devices from here up are on the bus.

; The bits of CQSTAT.
ST_WRITE_TIMEOUT = $01      ;; No device took a byte from the IEEE-488 bus in time.
ST_READ_TIMEOUT = $02       ;; No device put a byte on the IEEE-488 bus in time.
ST_SHORT_BLOCK = $04        ;; A tape block ended before its end address.
ST_LONG_BLOCK = $08         ;; A tape block went past its end address.
ST_READ_ERROR = $10         ;; A tape byte was bad in both copies, or a LOAD or VERIFY failed.
ST_CHECKSUM = $20           ;; A tape block's checksum didn't match.
ST_EOI = $40                ;; The end of the file: EOI on the IEEE-488 bus, or a zero after a tape file's data.
ST_NOT_PRESENT = $80        ;; No device answered on the IEEE-488 bus.

; The type in the first byte of a tape block.
TAPE_PROGRAM = 1            ;; A header for a program, whose data block follows.
TAPE_DATA = 2               ;; A block of a data file.
TAPE_DATA_HEADER = 4        ;; A header for a data file, whose blocks follow.
TAPE_END_OF_TAPE = 5        ;; A header that marks the end of the tape.

; Secondary addresses, as the kernal keeps them with $60 added, and the bus's commands.
SA_READ = $60               ;; The secondary address of a tape file opened to read, and of a LOAD.
SA_SAVE = $61               ;; The secondary address of a SAVE to a disk.
IEEE_TALK = $40             ;; The bus's TALK command, with the device in bits 0-4.
IEEE_LISTEN = $20           ;; The bus's LISTEN command, with the device in bits 0-4.
IEEE_UNTALK = $5F           ;; The bus's UNTALK command.
IEEE_UNLISTEN = $3F         ;; The bus's UNLISTEN command.
IEEE_CLOSE = $E0            ;; The bus's CLOSE command, with the secondary address in bits 0-3.
IEEE_OPEN = $F0             ;; The bus's OPEN command, with the secondary address in bits 0-3.

; Values for a PIA's control register, with the port (not its direction register) selected.
PIA_HIGH = $3C              ;; CA2 or CB2 an output, high; the CA1 or CB1 interrupt off.
PIA_LOW = $34               ;; CA2 or CB2 an output, low; the CA1 or CB1 interrupt off.
PIA_HIGH_IRQ = $3D          ;; CA2 or CB2 an output, high; the CA1 or CB1 interrupt on.
PIA_LOW_IRQ = $35           ;; CA2 or CB2 an output, low; the CA1 or CB1 interrupt on.

; The VIA's port B lines and PIA 1's port A lines, as bits.
VIA_NDAC_IN = $01           ;; The VIA's PB0, NDAC from the bus.
VIA_NRFD_OUT = $02          ;; The VIA's PB1, NRFD to the bus: set, ready for data.
VIA_ATN_OUT = $04           ;; The VIA's PB2, ATN to the bus: clear, attention.
VIA_TAPE_WRITE = $08        ;; The VIA's PB3, the cassettes' write line.
VIA_MOTOR2 = $10            ;; The VIA's PB4, cassette 2's motor: clear, running.
VIA_NRFD_IN = $40           ;; The VIA's PB6, NRFD from the bus: set, the listeners are ready.
VIA_DAV_IN = $80            ;; The VIA's PB7, DAV from the bus: clear, the data is valid.
VIA_IER_SET = $80           ;; In the VIA's interrupt enable register, sets the bits given; without it, clears them.
VIA_IRQ_T1 = $40            ;; The VIA's timer 1 interrupt, in its flag and enable registers.
VIA_IRQ_T2 = $20            ;; The VIA's timer 2 interrupt.
VIA_IRQ_CB1 = $10           ;; The VIA's CB1 interrupt, cassette 2's read line.
VIA_IRQ_ALL = $7F           ;; All of the VIA's interrupts.
PIA1_SENSE1 = $10           ;; PIA 1's PA4, cassette 1's keys: clear while PLAY is down.
PIA1_SENSE2 = $20           ;; PIA 1's PA5, cassette 2's keys: clear while PLAY is down.

; Characters and keys.
KEY_STOP = $03              ;; The STOP key.
KEY_TAB = $09               ;; TAB, on the business keyboard: to the next tab stop; with SHIFT ($89), sets or clears one.
KEY_RETURN = $0D            ;; RETURN, ending a line; with SHIFT it is $8D.
KEY_REPEAT = $10            ;; REPEAT, on the business keyboard: held, it repeats the key held with it. It types nothing.
KEY_DOWN = $11              ;; Cursor down; with SHIFT ($91), cursor up.
KEY_RVS = $12               ;; RVS, reversed characters on; with SHIFT ($92), off.
KEY_HOME = $13              ;; HOME, the cursor to the top left; with SHIFT ($93), CLR, clearing the screen.
KEY_DEL = $14               ;; DEL, deleting left of the cursor; with SHIFT ($94), INST, making room at it.
KEY_ESC = $1B               ;; ESC, on the business keyboard.
KEY_RIGHT = $1D             ;; Cursor right; with SHIFT ($9D), cursor left.
KEY_SHIFTED = $80           ;; Added to a key typed with SHIFT.
KEY_SHIFT_RUN = $83         ;; RUN with SHIFT, which types <Editor4:RUNTB>.
