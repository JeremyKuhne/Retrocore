;; INTEGER BASIC: CONSTANTS, PAGE ZERO AND THE MONITOR ADDRESSES IT USES
;;
;; The names Integer BASIC gives its constants, its page-zero locations and the parts of page 1 it borrows, and the
;; Monitor routines and locations it calls under the Monitor's own names that ../System/MonitorEntries.asm does not
;; provide. IntegerBasic.asm includes this file first. The floating-point routines, the Mini-Assembler and SWEET16
;; define their own page-zero names in their files.
;;
;; Integer BASIC uses most of page zero from $4A up. Several areas have two uses that never overlap in time: the
;; tokenizer's syntax stack, while a line is being entered, and the interpreter's noun stack, while a statement runs,
;; share $50 to $F1.

; Characters, without bit 7. The code adds $80 to them, as the Apple II's text has bit 7 set.
ETX = $03                           ;; Control-C, which stops a running program or input
CR = $0D                            ;; carriage return
BLANK = $20                         ;; space
DQT = $22                           ;; double quote

; The Monitor's page-zero locations, the input buffer and the keyboard, under the Monitor's names.
;; The width of the text window, in columns (40 unless a program changes it).
;;
;; Integer BASIC's TAB wraps a column past the window's width onto the next line by subtracting this.
;; See: <Monitor:WNDWDTH>, <SETCURCOL>
WNDWDTH = $21

;; The cursor's column within the window (0 is the window's left edge).
;;
;; The Monitor's output routine moves it. Integer BASIC reads it to tab PRINT's commas to the next multiple of 8 and
;; to break long lines when it lists a program, and TAB sets it.
;; See: <Monitor:CH>, <NEXTTAB>, <LISTBYTECOL>
CH = $24

;; The cursor's line on the screen, 0 to 23.
;;
;; VTAB stores the line here and calls <VTAB> to move the cursor there.
;; See: <Monitor:CV>, <IVTAB>
CV = $25

;; The address of the lo-res row being drawn (2 bytes), which <GBASCALC> sets.
;;
;; SCRN( reads a block's color through it.
;; See: <Monitor:GBASL>, <SCRN>
GBASL = $26

;; The rightmost column of a lo-res line that <HLINE> draws; HLIN's second column goes here.
;; See: <Monitor:H2>, <COMMA_HLIN>
H2 = $2C

;; The bottom row of a lo-res line that <VLINE> draws; VLIN's second row goes here.
;; See: <Monitor:V2>, <COMMA_VLIN>
V2 = $2D

;; An instruction's length less one, which the Monitor's <INSDS2> sets.
;;
;; The Mini-Assembler reads it to copy an instruction's bytes into memory.
;; See: <Monitor:LENGTH>, <FINDOP>
LENGTH = $2F

;; The Monitor's command mode: the delimiter character of the command being read, or 0.
;;
;; The Mini-Assembler passes it to the Monitor when a line starting with $ runs a Monitor command.
;; See: <Monitor:MODE>, <FAKEMON2>
MODE = $31

;; The character the Monitor's <GETLNZ> and <NXTCHAR> print as the prompt.
;;
;; Integer BASIC prompts with > (<SetPrompt>), and adds 1 to make it ? while INPUT reads a line, then takes 1 away
;; again. The Mini-Assembler prompts with !.
;; See: <Monitor:PROMPT>, <SetPrompt>, <INPUTSTR>, <GETQLINE>
PROMPT = $33

;; Where the Monitor's command parser is in the input line, an index into <IN>.
;;
;; The Mini-Assembler keeps its own place in the line here too, and the Monitor's <GETNUM> starts from it.
;; See: <Monitor:YSAV>, <FAKEMON>
YSAV = $34

;; The Monitor's program counter (2 bytes): where the Mini-Assembler puts the next instruction.
;; See: <Monitor:PCL>, <FINDOP>
PCL = $3A

;; The high byte of <PCL>.
PCH = $3B

;; The Monitor's first address parameter (2 bytes).
;;
;; Integer BASIC points it at the start of what the cassette routines read or write: <SETHDR> and <SETPRG> set
;; it. The Mini-Assembler uses <A1H> to count opcodes and characters.
;; See: <Monitor:A1L>, <SETHDR>, <SETPRG>
A1L = $3C

;; The high byte of <A1L>.
A1H = $3D

;; The Monitor's second address parameter (2 bytes): the last address the cassette routines read or write.
;;
;; The Mini-Assembler reads the number <GETNUM> leaves here as an instruction's operand.
;; See: <Monitor:A2L>, <SETHDR>, <SETPRG>, <REL>
A2L = $3E

;; The high byte of <A2L>.
A2H = $3F

;; The Monitor's fourth address parameter (2 bytes).
;;
;; The Mini-Assembler packs the three letters of a mnemonic into it, five bits each, in the form of the Monitor's
;; <MNEML> and <MNEMR> tables.
;; See: <Monitor:A4L>, <NXTM2>, <TRYNEXT>
A4L = $42

;; The high byte of <A4L>.
A4H = $43

;; A 16-bit count (low byte) that the Monitor's keyboard routine increments while it waits for a key.
;;
;; Since it depends on how long the user takes to type, RND uses it as its seed and keeps its random state here.
;; See: <Monitor:RNDL>, <RND>
RNDL = $4E

;; The high byte of <RNDL>.
RNDH = $4F

;; The input buffer, $0200-$02FF, where the Monitor's <NXTCHAR> puts a typed line.
;;
;; Integer BASIC also writes a line's tokens here, after the line's text, and runs an immediate statement from
;; here.
;; See: <Monitor:IN>, <GETCMD>, <TXTNDX>, <TOKNDX>
IN = $0200

;; The keyboard: the last key pressed, with bit 7 set until <KBDSTRB> is touched.
;; See: <Monitor:KBD>, <CHKBREAK>
KBD = $C000

;; Touching it clears bit 7 of <KBD>, taking the key.
;; See: <Monitor:KBDSTRB>
KBDSTRB = $C010

; Integer BASIC's own locations.
;; The lowest address of the variables, LOMEM (2 bytes): they grow upward from here to <PV>.
;;
;; The cold start (<COLD>) sets it to $0800, the first page above the text screen, and LOMEM: (<VLOMEM>) changes it.
;; <CLR> discards the variables by setting <PV> back to it.
;; See: <HIMEM>, <PV>, <CLR>, <VLOMEM>
LOMEM = $4A

;; The address just above the program, HIMEM (2 bytes): the program grows downward from here to <PP>.
;;
;; The cold start (<COLD>) sets it to the top of RAM, and HIMEM: (<VHIMEM>) moves it, taking the program with it.
;; <NEW> discards the program by setting <PP> to it.
;; See: <LOMEM>, <PP>, <NEW>, <VHIMEM>
HIMEM = $4C

;; The noun stack's low bytes: one per entry, indexed by X, which starts at $20 and counts down as entries are
;; pushed.
;;
;; While a statement runs, each operand (a "noun") takes one entry in three arrays: <NOUNSTKL>, <NOUNSTKH> and
;; <NOUNSTKC>. A number is its low byte here and its high byte in <NOUNSTKC>, with 0 in <NOUNSTKH>. A variable is its
;; address, low byte here and high byte in <NOUNSTKH>, which is never 0, so <GET16BIT> can tell the two apart. A
;; string takes two entries: its address, and above it the range of characters, the first index here and the end
;; index in <NOUNSTKH>. A push below X = 0 (<PUSHNOUNLO>) is an error, whose message is PPED AT (<PUSHNOUN_1>).
;;
;; These bytes overlap the tokenizer's <SYNSTKH>, and <CHKBREAK> saves the place to continue here when Control-C stops
;; a program, for CON.
;; See: <NOUNSTKH>, <NOUNSTKC>, <GET16BIT>, <PUSHNOUN>, <SYNSTKH>
NOUNSTKL = $50

;; The tokenizer's syntax stack: the high byte of the syntax table address to return to, one per rule being
;; matched.
;;
;; The tokenizer pushes a frame when one syntax rule calls another (<CALLRULE>): the place in the caller here and in
;; <SYNSTKL>, and where the input and output stood in <TXTNDXSTK> and <TOKNDXSTK>, so a rule that fails can restore
;; them and let the caller try its next alternative. X indexes the frames, from $20 down. These bytes are the noun
;; stack's (<NOUNSTKL>) while a statement runs.
;; See: <SYNSTKL>, <TXTNDXSTK>, <TOKNDXSTK>, <SYNSTKDX>, <SYNTABL>
SYNSTKH = $58

;; The noun stack's high bytes of addresses: the high byte of a variable's address, or 0 for a number.
;;
;; For a string's second entry it is the index just past the string's last character. <CHKBREAK> saves the current
;; line's address in its first two bytes when Control-C stops a program.
;; See: <NOUNSTKL>, <NOUNSTKC>
NOUNSTKH = $78

;; The tokenizer's syntax stack: the low byte of the syntax table address to return to.
;; See: <SYNSTKH>
SYNSTKL = $80

;; The noun stack's high bytes of numbers.
;;
;; Its first byte, $A0, is also the TRACE flag: <TRACE> sets bit 7, <NOTRACE> clears it, and the run loop prints each
;; line's number while it is set (<TRACELINE>).
;; See: <NOUNSTKL>, <NOUNSTKH>, <TRACE>
NOUNSTKC = $A0

;; The tokenizer's syntax stack: <TXTNDX> as it was when each rule began, to back up to if the rule fails.
;; See: <SYNSTKH>, <TXTNDX>
TXTNDXSTK = $A8

;; The tokenizer's index of the last character it has matched in <IN>.
;;
;; It starts at $FF, before the line. When a rule fails, the tokenizer sets it back from <TXTNDXSTK>. Statements
;; reuse it as a scratch byte once the line is tokenized: POKE, PLOT, HLIN and VLIN keep their first value here
;; (<GETVAL255>), and INPUT keeps its place in the typed line.
;; See: <TOKNDX>, <TXTNDXSTK>, <GETVAL255>, <COMMA_INPUT>
TXTNDX = $C8

;; A count of digits: <PRDEC> counts down the places of a number it prints and keeps the first digit that is not
;; 0 here; the tokenizer keeps the place in <IN> where a constant's digits start (<RULEMATCHED>).
;; See: <PRDEC>, <LEADZR>
LEADBL = $C9

;; The start of the program, PP (2 bytes): its lowest address. The program's lines lie from here up to <HIMEM>.
;;
;; Each line is a length byte (counting itself), the line number (low byte first), the line's tokens and $01, the
;; end-of-line token. Lines are kept in increasing order of their numbers. Entering a line moves the lines below it
;; down to make room, so <PP> moves down; <NEW> sets it to <HIMEM>.
;; See: <HIMEM>, <PV>, <FINDLINE>, <WARM>
PP = $CA

;; The end of the variables, PV (2 bytes): the address just past the last one. They lie from <LOMEM> up to here.
;;
;; Each variable is its name (characters with bit 7 set; a string variable's name ends in $40, the $ token), a
;; display flag (1 after DSP, otherwise 0), the address of the next variable (2 bytes, the next one's name, which
;; is <PV> for the last), and its value: 2 bytes for a number, 2 for each element of an array, and its dimension
;; plus 1 for a string, whose characters end in a byte with bit 7 clear. A memory full error comes when <PV> would
;; pass <PP>.
;; See: <LOMEM>, <PP>, <CLR>, <CMPVARNAME>
PV = $CC

;; The main 16-bit accumulator (2 bytes, low byte first).
;;
;; <GET16BIT> leaves a noun's value here, and the arithmetic, the statements and the cassette routines work on it.
;; <DOTOKEN_2> also jumps through it to run each token's routine.
;; See: <GET16BIT>, <AUX>
ACC = $CE

;; A pointer that walks the variables (2 bytes) when <CMPVARNAME> looks a name up.
;;
;; <EXP> counts its multiplications in it instead.
;; See: <CMPVARNAME>, <PRVARNAME>, <EXP>
SRCH = $D0

;; The tokenizer's syntax stack: <TOKNDX> as it was when each rule began, to back up to if the rule fails.
;;
;; Its first byte is also the high byte of <SRCH>.
;; See: <SYNSTKH>, <TOKNDX>
TOKNDXSTK = $D1

;; A second 16-bit work location (2 bytes): <EXP> keeps the number it multiplies by here.
;; See: <EXP>
SRCH2 = $D2

;; The IF flag: bit 7 is set while the statement after a false IF's THEN is being skipped.
;;
;; <IF> sets it when the condition is 0. The interpreter (<EXECLINE_10>) then passes over tokens until the next colon or
;; the end of the line, and clears it there, so the statements after a colon run whatever the condition was.
;; See: <IF>, <EXECLINE>, <EXECLINE_10>
IFFLAG = $D4

;; The carriage return flag: bit 7 is set when PRINT has printed something and still owes the line a return.
;;
;; Printing a number or a string sets it (<PRINTNUM_1>, <SETCRFLAG>); a semicolon or comma at the end of PRINT clears it
;; (<SEMI_END>, <COMMA_PREND>), and <COLON> prints the return at the end of the statement while it is set.
;; See: <COLON>, <PRINTNUM>, <PRINTSTR>
CRFLAG = $D5

;; The token the interpreter is about to run (<DOTOKEN>), the operator whose priority decides what runs first.
;;
;; IF stores the THEN token in it so a false condition skips the rest of the statement.
;; See: <DOTOKEN>, <IF>
VERBNOW = $D6

;; The priority of the token waiting to run, which <DOTOKEN> compares with the operators on the stack.
;;
;; A left parenthesis and SCRN( set it to $FF (<LEFT_PAREN>), above any operator's, so nothing waiting before the
;; parenthesis runs until the right parenthesis comes.
;; See: <DOTOKEN>, <LEFT_PAREN>, <TABLE1>
PRFLAG = $D7

;; A place to keep X while a routine uses it: the noun stack index, around calls to the Monitor and while a routine
;; walks memory.
;;
;; <CMPVARNAME> also keeps whether a variable name ends in $ in bit 6 here.
XSAVE = $D8

;; The run flag: bit 7 is set while a program runs, clear for an immediate statement.
;;
;; <GETNEXT> sets it for each statement; errors (<ERRMESS>) and END check it.
;; See: <GETNEXT>, <ERRMESS>
RUNFLAG = $D9

;; A second 16-bit accumulator (2 bytes), the other operand of the arithmetic and a pointer for string work.
;; See: <ACC>, <MULT>, <DIVMOD>
AUX = $DA

;; The address of the line running (2 bytes): its length byte, from which the run loop steps to the next line.
;;
;; GOSUB and FOR save it, and errors and TRACE read the line number through it.
;; See: <GOLINE>, <PX>, <GOSUB>, <FOR>
PR = $DC

;; The address of the token being run (2 bytes).
;;
;; <GETVERB> steps it through the line. GOSUB and FOR save it to come back to.
;; See: <GETVERB>, <PR>, <GETNEXT>
PX = $E0

;; A work pointer (2 bytes): the next byte to list (<NextByte>), and the place to delete from when a line is
;; replaced.
;; See: <NextByte>, <DELLINE>
P1 = $E2

;; A work pointer (2 bytes): the line found by <FINDLINE>, the new start of the program while lines move, and the
;; listed token's flags.
;; See: <FINDLINE>, <CLOSEGAP>
P2 = $E4

;; A work pointer (2 bytes): where <FINDLINE> searches from, the end of a range to list or delete, and a remainder in
;; division.
;; See: <FINDLINE>, <COMMA_LIST>, <DIVMOD>
P3 = $E6

;; The tokenizer's index of the last token it has written in <IN>.
;;
;; The tokens go into <IN> after the line's text: GETCMD sets it to the length of the line, and <PUTTOKEN> adds each
;; token after it. A line that fills the buffer is TOO LONG.
;; See: <TXTNDX>, <PUTTOKEN>, <TOKNDXSTK>
TOKNDX = $F1

;; A 16-bit number (2 bytes) being built from a constant's digits by the tokenizer (<RULEMATCHED>), or printed in decimal
;; by <PRDEC>.
;; See: <PRDEC>, <RULEMATCHED>
PCON = $F2

;; The step between line numbers in AUTO mode (2 bytes), 10 unless AUTO gives one.
;; See: <AUTO>, <COMMA_AUTO>, <AUTOLN>
AUTOINC = $F4

;; The next line number AUTO offers (2 bytes).
;; See: <AUTO>, <AUTOINC>, <WARM>
AUTOLN = $F6

;; The AUTO flag: bit 7 is set in AUTO mode, when the prompt offers the next line number.
;;
;; <AUTO> sets it; MAN (<MAN>) and <NEW> clear it.
;; See: <AUTO>, <MAN>
AUTOFLAG = $F8

;; A character, or a count: the digit <PRDEC> is about to print, or the loop count of the tokenizer's multiply by 10.
;; See: <PRDEC>, <RULEMATCHED>
CHAR = $F9

;; What <PRDEC> prints for a leading zero: 0 prints nothing, $A0 a blank.
;;
;; The lister sets it to a blank so that line numbers line up; the prompt sets it to 0.
;; See: <PRDEC>, <UNPACK>
LEADZR = $FA

;; The number of FOR loops active, 0 to 16: an index into the FOR stack in page 1.
;; See: <FOR>, <NEXT>, <STK_40>
FORNDX = $FB

;; The number of GOSUBs active, 0 to 16: an index into the GOSUB stack in page 1.
;; See: <GOSUB>, <RETURN>, <STK_00>
GOSUBNDX = $FC

;; The tokenizer's syntax stack index: the frame of the rule being matched, from $20 down.
;; See: <SYNSTKH>, <MATCHITEM>
SYNSTKDX = $FD

;; A pointer into the syntax table (2 bytes): its low byte is always 0 (<CLR> clears it), and its high byte selects
;; the page, $EC or $ED. Y is the place in that page.
;; See: <SYNTABL>, <STARTRULE>
SYNPAG = $FE

; Page 1 below the 6502's stack, where GOSUB and FOR keep their state: 16 entries in each 16-byte column, indexed by
; GOSUBNDX or FORNDX. Integer BASIC starts the 6502's stack at $01FF, and it does not grow down this far.
;; The GOSUB stack's return token addresses, low bytes: <PX> at each GOSUB.
;;
;; <STK_10> holds the high bytes, and <STK_20> and <STK_30> the line (<PR>) to return to.
;; See: <GOSUB>, <RETURN>, <GOSUBNDX>
STK_00 = $0100

STK_10 = $0110                      ;; the GOSUB stack: return token addresses, high bytes
STK_20 = $0120                      ;; the GOSUB stack: return line addresses, low bytes
STK_30 = $0130                      ;; the GOSUB stack: return line addresses, high bytes

;; The FOR stack's loop variable addresses, low bytes.
;;
;; Each FOR keeps one entry across the columns from here: its variable's address (<STK_40>, <STK_50>), its step
;; (<STK_60>, <STK_70>), the line and token after the FOR to loop back to (<STK_80> to <STK_B0>) and its limit
;; (<STK_C0>, <STK_D0>).
;; See: <FOR>, <TO>, <STEP>, <NEXT>, <FORNDX>
STK_40 = $0140

STK_50 = $0150                      ;; the FOR stack: loop variable addresses, high bytes
STK_60 = $0160                      ;; the FOR stack: steps, low bytes
STK_70 = $0170                      ;; the FOR stack: steps, high bytes
STK_80 = $0180                      ;; the FOR stack: the FOR's line addresses, low bytes
STK_90 = $0190                      ;; the FOR stack: the FOR's line addresses, high bytes
STK_A0 = $01A0                      ;; the FOR stack: the token addresses after the FOR, low bytes
STK_B0 = $01B0                      ;; the FOR stack: the token addresses after the FOR, high bytes
STK_C0 = $01C0                      ;; the FOR stack: limits, low bytes
STK_D0 = $01D0                      ;; the FOR stack: limits, high bytes

;; Where the floating-point routines jump on overflow: a JMP the program using them stores in page 3.
;; See: <OVFL>
OVLOC = $03F5

; The Monitor's routines that MonitorEntries.asm leaves out, under the Monitor's names.
;; Plots a lo-res block: A = row, Y = column, in the color <SETCOL> chose. PLOT jumps here.
;; See: <Monitor:PLOT>, <COMMA_PLOT>
PLOT = $F800

;; Draws a lo-res line across, at row A from column Y to <H2>. HLIN jumps here.
;; See: <Monitor:HLINE>, <AT_HLIN>
HLINE = $F819

;; Draws a lo-res line down, in column Y from row A to <V2>. VLIN jumps here.
;; See: <Monitor:VLINE>, <AT_VLIN>
VLINE = $F828

;; Sets <GBASL> to the address of a lo-res row pair, from the row number halved in A.
;; See: <Monitor:GBASCALC>, <SCRN>
GBASCALC = $F847

;; Sets the lo-res color from A (0 to 15). COLOR= jumps here.
;; See: <Monitor:SETCOL>, <COLOR_EQ>
SETCOL = $F864

;; Finds an opcode's format (in <FORMAT>), length (in <LENGTH>) and mnemonic (in A) for the disassembler; the
;; Mini-Assembler uses it on each opcode it tries.
;; See: <Monitor:INSDS2>, <TRYNEXT>
INSDS2 = $F88E

;; Prints the instruction at <PCL> in the disassembler's form; the Mini-Assembler shows each line it assembles.
;; See: <Monitor:INSTDSP>, <FINDOP>
INSTDSP = $F8D0

;; Prints X blanks.
;; See: <Monitor:PRBL2>, <ERR2>
PRBL2 = $F94A

;; Steps <PCL> past the instruction there, returning the new address in A (low) and Y (high).
;; See: <Monitor:PCADJ>, <FINDOP>
PCADJ = $F953

;; Reads game paddle X (0 to 3), returning its position, 0 to 255, in Y. PDL calls it.
;; See: <Monitor:PREAD>, <PDL>
PREAD = $FB1E

;; Sets the screen to text. TEXT runs it directly from the verb table.
;; See: <Monitor:SETTXT>, <VERBADRL>
SETTXT = $FB39

;; Sets the screen to lo-res graphics with four lines of text and clears the graphics. GR runs it directly from the
;; verb table.
;; See: <Monitor:SETGR>, <VERBADRL>
SETGR = $FB40

;; Prints a return and the prompt, and reads a line into <IN>. The Mini-Assembler reads its lines with it.
;; See: <Monitor:GETLNZ>, <NXTLINE>
GETLNZ = $FD67

;; Reads keys into <IN> from index X until Return, returning the index of the return in X.
;;
;; Integer BASIC enters the Monitor's line input here, after the prompt, so it can print its own prompt first.
;; See: <Monitor:NXTCHAR>, <GETCMD>, <RDKEY>
NXTCHAR = $FD75

;; Prints the character in A through the output hook, keeping A, X and Y.
;; See: <Monitor:COUT>
COUT = $FDED

;; The part of the Monitor's command loop that handles a Return: the Mini-Assembler passes a $ line's Return here.
;; See: <Monitor:BL1>, <FAKEMON2>
BL1 = $FE00

;; Sets the input hook to slot A's ROM ($Cn00), or to the keyboard for 0. IN# calls it.
;; See: <Monitor:INPORT>, <INSLOT>
INPORT = $FE8B

;; Sets the output hook to slot A's ROM ($Cn00), or to the screen for 0. PR# calls it.
;; See: <Monitor:OUTPORT>, <PRSLOT>
OUTPORT = $FE95

;; Writes the bytes from <A1L> to <A2L> to the cassette, after a header tone and a sync bit.
;; See: <Monitor:WRITE>, <VSAVE>
WRITE = $FECD

;; <WRITE> entered after its first instruction (LDA #$40), so A sets the length of the header tone.
;;
;; SAVE writes the program with a shorter tone ($1A) than its first record, the program's length.
;; See: <Monitor:WRITE>, <VSAVE>
WRITE0 = $FECF

;; Reads bytes from the cassette into <A1L> to <A2L>, beeping if the checksum is wrong.
;; See: <Monitor:READ>, <LOAD>
READ = $FEFD

;; Sounds the bell (prints Control-G).
;; See: <Monitor:BELL>, <PRTERR>, <RESETZ>
BELL = $FF3A

;; Restores A, X, Y and the status from the Monitor's save area.
;; See: <Monitor:RESTORE>, <RTNZ>
RESTORE = $FF3F

;; Saves A, X, Y, the status and the stack pointer in the Monitor's save area.
;; See: <Monitor:SAVE>, <SW16>
SAVE = $FF4A

;; Reads a hexadecimal number from <IN> at Y into <A2L>, returning the character that ended it in the coded form
;; <CHRTBL> lists.
;; See: <Monitor:GETNUM>, <FAKEMON>, <FORM6>
GETNUM = $FFA7

;; Runs the Monitor command for the delimiter at index Y of <CHRTBL>, by its address in the Monitor's table.
;; See: <Monitor:TOSUB>, <FAKEMON3>
TOSUB = $FFBE

;; The Monitor's table of command characters, in the form <GETNUM> returns them.
;; See: <Monitor:CHRTBL>, <FAKEMON2>
CHRTBL = $FFCC
