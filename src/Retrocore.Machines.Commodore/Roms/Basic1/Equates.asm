;; COMMODORE PET 2001 BASIC 1 EDITOR AND KERNAL EQUATES
;;
;; The RAM the screen editor (Editor1.asm) and the kernal (Kernal1.asm) of the PET 2001's first ROMs keep their state
;; in, the characters and codes they share, and the parts of BASIC 1 they use. Both sources include this file, after
;; ../PetEquates.asm, so each name here is defined and documented once.
;;
;; BASIC 1 keeps its page-zero variables at $00-$E0, in the order Microsoft's 6502 BASIC gives them: the input
;; buffer is in page zero at $0A, so the variables from <CHARAC> up sit $52 higher than in later Commodore BASICs.
;; The names of BASIC's locations and routines are Microsoft's, matched to BASIC 1 by its code. The editor and the
;; kernal have the rest of page zero, $E0-$FF, and page 2; the two cassette buffers fill $027A-$03F9.
;;
;; The editor and kernal names follow the ones Commodore's later kernals and the published PET memory maps use for
;; the same jobs (<PNT>, <PNTR>, <TBLX>, <NDX>, <STATUS>, <FNLEN> and so on); the locations only BASIC 1's tape
;; routines have are named after what they hold.
;;
;; Maintained by hand.

; BASIC's page zero.
;; Where USR jumps: a JMP to the user's routine, set to the ?ILLEGAL QUANTITY error by <INIT>.
USRPOK = $00

;; The first byte of BASIC's input buffer, 80 bytes in page zero at $0A-$59.
;;
;; The two bytes before it at <BUF>-4 and <BUF>-3 must not be zero, so that BASIC's line linking stops there; the
;; kernal's reset (<Editor1:CINT>) sets them to $7F.
BUF = $0A

;; BASIC's line number, or an address: <Kernal1:SYS> jumps through it.
;;
;; The byte after it, at <BUF>-1, holds a comma, which BASIC's INPUT expects before the data it reads.
LINNUM = $08

;; The first of BASIC's page-zero flags, the delimiter its string scanner looks for. BASIC's other page-zero
;; variables are at their places in Microsoft's 6502 BASIC plus $52 from here on.
CHARAC = $5A

;; A pointer BASIC uses for many jobs; <FRESTR> leaves the address of a string's text here.
INDEX = $71

;; The address of the start of BASIC's variables, just past the program's end; <Kernal1:LOAD> sets it to the end of
;; what it loaded, and <Kernal1:SAVE> saves up to it.
VARTAB = $7C

;; Gets BASIC's next character: increments <TXTPTR> and falls into <CHRGOT>. <INIT> copies it to page zero.
;;
;; Out: A = the character, carry = clear for a digit, zero = set at the end of a statement (a colon or zero byte)
CHRGET = $C2

;; Gets BASIC's current character again, at <TXTPTR>, without moving on.
;;
;; Out: A = the character, carry = clear for a digit, zero = set at the end of a statement (a colon or zero byte)
CHRGOT = $C8

;; BASIC's text pointer: the operand of the LDA in <CHRGOT>.
;;
;; In direct mode it points into <BUF> in page zero, so its high byte, <TXTPTR>+1, is zero; the kernal tests that to
;; print its messages only in direct mode.
TXTPTR = $C9

; The editor's and kernal's page zero.
;; The address of the screen line the cursor is on, in video RAM.
;;
;; <Editor1:STUPT> sets it from <TBLX>; for a logical line two rows long it is the first row's address.
PNT = $E0

;; The cursor's column in its logical line: 0-39 on a one-row line, 0-79 on a two-row one.
PNTR = $E2

;; A pointer to the byte a load, save or verify is at.
;;
;; The tape routines step it from <STAL> to <EAL>; <Editor1:SCROL> uses it for the line it copies from.
SAL = $E3

;; The address just past the end of what is loaded, saved or written to tape, and of a cassette buffer while one
;; is read or written.
EAL = $E5

;; The tape read's timing constant: the interrupt (<Kernal1:READ>) adds it to its pulse length thresholds, and
;; moves it a step at a time to follow the speed of the tape.
CMP0 = $E7

;; The tape timing's scratch byte: a pulse's length, a quarter of timer 2's count, as <Kernal1:READ> measures it,
;; or the low byte <Kernal1:STT1> adds to timer 1.
TIMTMP = $E8

;; The kernal's scratch byte: the character <Kernal1:BSOUT> is sending, a header's block type, or an index into a
;; file name.
KTEMP = $E9

;; Quote mode: bit 0 set while the cursor is inside quotes, so that cursor keys print as reversed characters.
QTSW = $EA

;; Nonzero while the tape read is inside a byte, with timer 1 armed to catch a byte that stops short.
RDBYTE = $EB

;; Set when the byte just read followed a leader, which starts a block.
NEWBLK = $EC

;; Nonzero when the byte just read had a bad pulse or a parity error, or did not match in a verify.
BYTERR = $ED

;; The length of the current file name, at <FNADR>.
FNLEN = $EE

;; The current logical file number, from OPEN, CLOSE, CMD and the like.
LA = $EF

;; The current secondary address. Bit 7 set means none was given.
SA = $F0

;; The current device: 0 the keyboard, 1 and 2 the cassettes, 3 the screen, 4 and up the IEEE-488 bus.
;;
;; <Kernal1:UNTLK> and <Kernal1:UNLSN> leave their command here.
FA = $F1

;; The last column of the cursor's logical line: 39 for one row, 79 for two.
LNMX = $F2

;; The address of the current cassette's buffer: <TBUFFR1> or <TBUFFR2>.
TAPE1 = $F3

;; The cursor's row on the screen, 0-24.
TBLX = $F5

;; A character in hand. The editor keeps the one it is printing or has just read here; the tape write keeps its
;; checksum here, and the tape read the kind of the first pulse of a bit.
DATAX = $F6

;; The address a load or save starts at.
STAL = $F7

;; The address of the current file name.
FNADR = $F9

;; The number of characters still to insert: set by INST, and while it is nonzero, control characters print
;; reversed instead of acting.
INSRT = $FB

;; The byte the tape write is sending, a bit at a time from bit 0, or the byte the tape read has just finished.
TBYTE = $FC

;; The copies of the block still to write or read: 2 for the first, 1 for the second, 0 when done.
BLKCNT = $FD

;; The byte the tape read is shifting its bits into.
RDBITS = $FE

; Page 1.
;; The 6502's stack page. The interrupt entry reads the stacked status at <STACK>+4,x to tell BRK from IRQ.
STACK = $0100

;; While a tape block is read, the bottom of page 1 logs the addresses of the bytes the first copy read badly, a
;; low and high byte each, up to 31 of them, for the second copy to put right.
BADLOG = $0100

; Page 2.
;; The jiffy clock: 3 bytes, high byte first, counting sixtieths of a second since midnight, which BASIC reads as
;; TI and TI$. <Kernal1:JUDTIM> keeps it and wraps it at 24 hours.
TIME = $0200

;; The key down at the last scan, as its 1-80 number in <Editor1:CHAR>, or $FF for none: a key is entered only
;; when it changes.
LSTX = $0203

;; Bit 0 set while a SHIFT key is down, during a keyboard scan.
SHFLAG = $0204

;; Counts interrupts for the jiffy clock's correction: <Kernal1:JUDTIM> skips one tick of <TIME> in every 623.
TIMADJ = $0205

;; Nonzero while the kernal runs cassette 1's motor: the interrupt leaves the motor alone until PLAY is let go.
CAS1 = $0207

;; Nonzero while the kernal runs cassette 2's motor, as <CAS1> is for cassette 1.
CAS2 = $0208

;; The keyboard row the last scan ended on, read each jiffy: $EF while STOP is down.
STKEY = $0209

;; The tape read's drift: how far the last bits' pulses ran from their expected lengths, which moves <CMP0>.
TDRIFT = $020A

;; Nonzero while verifying instead of loading.
VERCK = $020B

;; The I/O status, which BASIC reads as ST: $01 a write timed out, $02 a read timed out, $04 a short block, $08 a
;; long block, $10 a read or verify error, $20 a checksum error, $40 the end of a file, $80 no device.
STATUS = $020C

;; The number of keys in the keyboard buffer, <KEYD>.
NDX = $020D

;; Nonzero while reverse is on: characters print with bit 7 set.
RVS = $020E

;; The keyboard buffer: 10 keys, the oldest first.
KEYD = $020F

;; The IRQ vector: the interrupt entry jumps through it. It is <Editor1:KEY> normally, and one of the tape or test
;; handlers in <Kernal1:BSIT> while the kernal uses the cassettes.
CINV = $0219

;; The BRK vector: the interrupt entry jumps through it for a BRK instruction. BASIC 1 does not set it.
CBINV = $021B

;; The IEEE-488 output's buffered character: nonzero while <BSOUR> holds one not yet sent, $FF once
;; <Kernal1:CIOUT> has buffered it.
C3PO = $021D

;; The end of the line being read from the screen: one past its last character that is not a space.
INDX = $021E

;; Where input started: the cursor's row, then its column (<LXSP>+1), when the keyboard read began, so that a line
;; is read from there and not from the prompt before it.
LXSP = $0220

;; The byte the IEEE-488 routines send next.
BSOUR = $0222

;; The key found down by the current scan, as its 1-80 number, or $FF.
SFDX = $0223

;; Zero while the cursor blinks: <Editor1:LOOP5> sets it to the number of keys waiting.
BLNSW = $0224

;; Counts down the jiffies to the cursor's next blink.
BLNCT = $0225

;; The character under the cursor, as it was before the blink reversed it.
GDBLN = $0226

;; Bit 0 set while the cursor is shown, its character reversed.
BLNON = $0227

;; The tape read's leader detector: the count of short pulses over medium ones, saved when it passes 16.
;;
;; The editor reads the same byte as the link table's entry for the row above the screen, <LDTB1>-1, which nothing
;; else sets.
LDRCNT = $0228

;; The screen line link table: 25 bytes, one for each row, holding the high byte of the row's address in video RAM,
;; with bit 7 set when the row starts a logical line and clear when it continues the row above.
LDTB1 = $0229

;; The logical file table: the file numbers of the open files, 10 at most.
LAT = $0242

;; The device table: each open file's device, in step with <LAT>.
FAT = $024C

;; The secondary address table: each open file's secondary address, in step with <LAT>.
SAT = $0256

;; Nonzero while a line is being read from the screen: <Editor1:LOOP5> returns its characters one at a time.
CRSW = $0260

;; Keeps X while <Kernal1:BASIN> reads a cassette.
XSAV = $0261

;; The number of open files.
LDTND = $0262

;; The input device, 0 (the keyboard) normally.
DFLTN = $0263

;; The output device, 3 (the screen) normally.
DFLTO = $0264

;; The parity of the tape byte so far: the bits read or written, exclusive-ORed.
PRTY = $0265

;; Set when the tape read has seen a byte's long marker pulse, so that the next pulses are its data.
MARKER = $0266

;; An index into the cassette buffer, where a header's file name is compared or copied.
HDRIDX = $0268

;; Counts the cursor-right characters sent to a cassette; <Kernal1:CHKOUT> sets it to $FF, so the first one after
;; it wraps the count to zero and is not written (<Kernal1:BO21>).
RIGHTS = $026A

;; The bits of the tape byte still to go: 8, counted down, then the parity bit.
BITCNT = $026C

;; Which pulse of a bit the tape routines are on: 0 for the first, 1 for the second.
PHASE = $026F

;; The cassette buffer pointers: <BUFPT>+1 for cassette 1 and <BUFPT>+2 for cassette 2, indexed by <FA>, each the
;; offset of the next byte in its buffer.
;;
;; The tape write counts the sync bytes down in <BUFPT> itself.
BUFPT = $0270

;; A tape counter: the leader pulses still to write, or the copy of the block the read is on.
TCOUNT = $0273

;; The tape write: set once a byte's long marker pulse is written. The tape read: nonzero when the byte just
;; finished is not good data, because a long pulse came among its bits or it is the noise before a block's first
;; marker.
TMARK1 = $0274

;; The tape write: set once a byte's medium marker pulse is written. The tape read: the count of short pulses
;; less medium ones, which a leader drives up and a good bit leaves even.
TMARK2 = $0275

;; The end of the log of bad bytes in <BADLOG>: twice the number logged.
PTR1 = $0276

;; How far the second copy of a block has got through the log in <BADLOG>.
PTR2 = $0277

;; The tape read's state: bit 7 set to look for the sync bytes before a block, bit 6 set while in the data, and
;; the low four bits the sync count expected next.
RDSTATE = $0278

;; The checksum of a tape block, the exclusive OR of its bytes; before a block the tape write counts its leaders
;; down here.
CHKSUM = $0279

;; Cassette 1's buffer: 192 bytes, holding a header or a block of a data file.
TBUFFR1 = $027A

;; Cassette 2's buffer: 192 bytes, as <TBUFFR1> is for cassette 1.
TBUFFR2 = $033A

; BASIC's routines.
;; Ends an error: resets BASIC's stack, prints " ERROR" and the line number in a program, and goes to READY.
;;
;; The kernal prints its own message, after a question mark, then jumps here.
TYPERR = $C379

;; Finishes a change to the program: clears the variables, links the program's lines and goes to BASIC's main loop.
FINI = $C430

;; Restores the DATA pointer and resets BASIC's stack, keeping the variables.
FLOAD = $C581

;; Points <TXTPTR> just before the start of the program.
STXTPT = $C59A

;; BASIC's STOP check: with zero and carry set, as <Kernal1:STOP1> leaves them when the STOP key is down, it
;; ends the program with BREAK; otherwise it returns.
STOP = $C71C

;; Where the NMI vector points: an instruction in BASIC's character output. Nothing on the PET 2001 drives NMI.
NMIENT = $CA60

;; Evaluates a numeric expression into BASIC's floating accumulator, with a ?TYPE MISMATCH error for a string.
FRMNUM = $CCA4

;; Evaluates an expression at <TXTPTR> into BASIC's floating accumulator.
FRMEVL = $CCB8

;; Checks that the character at <TXTPTR> is the one in A and moves past it, or gives a ?SYNTAX ERROR.
;;
;; In: A = the character
SYNCHR = $CE13

;; Gives a ?SYNTAX ERROR.
SNERR = $CE1C

;; Frees the string in BASIC's floating accumulator.
;;
;; Out: A = its length, INDEX = its address
FRESTR = $D57B

;; Evaluates an expression into a byte, with an ?ILLEGAL QUANTITY error for anything outside 0-255.
;;
;; Out: X = the byte
GETBYT = $D676

;; Converts BASIC's floating accumulator to an address in <LINNUM>.
GETADR = $D6D0

;; BASIC's cold start: sets up page zero and <CHRGET>, finds the top of RAM, prints the sign-on and the bytes free,
;; and goes to READY.
INIT = $E0D2

; The devices.
DEV_KEYBOARD = 0                    ;; the keyboard, the input device normally
DEV_SCREEN = 3                      ;; the screen, the output device normally; above it are the IEEE-488 devices

; Values for a PIA's control register, as the editor and kernal write them: each selects the port's data register
; and makes CA2 or CB2 an output.
PIA_HIGH = $3C                      ;; CA2 or CB2 high, with CA1 or CB1's interrupt off
PIA_LOW = $34                       ;; CA2 or CB2 low, with CA1 or CB1's interrupt off
PIA_HIGH_IRQ = $3D                  ;; CA2 or CB2 high, with CA1 or CB1's interrupt on
PIA_LOW_IRQ = $35                   ;; CA2 or CB2 low, with CA1 or CB1's interrupt on

; PIA 1's port A bits.
PIA1A_SENSE1 = $10                  ;; cassette 1's keys, low while PLAY is down
PIA1A_SENSE2 = $20                  ;; cassette 2's keys, low while PLAY is down
PIA1A_EOI = $40                     ;; EOI from the IEEE-488 bus, low with a byte's last

; The VIA's port B bits.
VIAB_NDAC = $01                     ;; NDAC in from the IEEE-488 bus
VIAB_NRFD_OUT = $02                 ;; NRFD out to the IEEE-488 bus
VIAB_ATN = $04                      ;; ATN out to the IEEE-488 bus
VIAB_WRITE = $08                    ;; the cassettes' write line
VIAB_MOTOR2 = $10                   ;; cassette 2's motor, running while low
VIAB_RETRACE = $20                  ;; VIDEO ON, low during vertical blanking
VIAB_NRFD = $40                     ;; NRFD in from the IEEE-488 bus
VIAB_DAV = $80                      ;; DAV in from the IEEE-488 bus

; Characters the editor and kernal act on, in the PET's ASCII.
CHR_LF = $0A                        ;; line feed, which the kernal does not send to files
CHR_RETURN = $0D                    ;; RETURN; shifted, it ends the line without being read
CHR_DOWN = $11                      ;; cursor down; shifted, cursor up
CHR_RVS = $12                       ;; reverse on; shifted, reverse off
CHR_HOME = $13                      ;; cursor home; shifted, clear the screen
CHR_DEL = $14                       ;; delete the character left of the cursor; shifted, insert a space
CHR_RIGHT = $1D                     ;; cursor right; shifted, cursor left
CHR_RUN = $83                       ;; shifted STOP, RUN: types LOAD and RUN
CHR_PI = $FF                        ;; pi, which the screen holds as $5E

; The tape header's first byte: the kind of block.
TAPE_PROGRAM = $01                  ;; a program's header, which <Kernal1:LOAD> and <Kernal1:VER> look for
TAPE_DATA = $02                     ;; a block of a data file
TAPE_FILE = $04                     ;; a data file's header
TAPE_EOT = $05                      ;; the end of the tape: a search stops at it

; IEEE-488 commands, sent with ATN.
IEEE_LISTEN = $20                   ;; LISTEN, ORed with the device number
IEEE_UNLISTEN = $3F                 ;; UNLISTEN
IEEE_TALK = $40                     ;; TALK, ORed with the device number
IEEE_UNTALK = $5F                   ;; UNTALK
IEEE_SECOND = $60                   ;; a secondary address, ORed with it
IEEE_CLOSE = $E0                    ;; CLOSE, ORed with the secondary address
IEEE_OPEN = $F0                     ;; OPEN, ORed with the secondary address
