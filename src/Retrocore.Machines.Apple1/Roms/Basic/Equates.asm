;; APPLE-1 BASIC: CONSTANTS, PAGE ZERO AND THE HARDWARE IT USES
;;
;; The names BASIC gives its constants, its page-zero locations and the parts of page 1 it borrows, and the PIA's
;; registers, which it reads and writes itself: BASIC calls nothing in the Monitor. Basic.asm includes this file
;; first.
;;
;; BASIC uses most of page zero from $48 up. Several areas have two uses that never overlap in time: the tokenizer's
;; syntax stack, while a line is being entered, and the interpreter's noun stack, while a statement runs, share $50
;; to $F1.

; Characters, without bit 7. The code adds $80 to them, as the keyboard sets bit 7.
CR = $0D                            ;; carriage return
BLANK = $20                         ;; space
DQT = $22                           ;; double quote

; The cursor's column, the input buffer and the PIA.

;; The column the next character goes to, counted from 1 after a return.
;;
;; The terminal keeps its own cursor and cannot move it back, so <COUT> counts the columns here instead: TAB and
;; PRINT's commas print blanks until it passes their column, and the lister starts a new line when it gets past
;; column 32.
;; See: <COUT>, <NEXTTAB>, <TAB>, <LISTBYTECOL>
CH = $24

;; RND's random state (2 bytes, low byte first).
;;
;; Only RND changes it, so a program's first random numbers depend on what memory held when BASIC started.
;; See: <RND>
RNDL = $4E

;; The high byte of <RNDL>.
RNDH = $4F

;; The input buffer, $0200-$02FF, where <GETLINE> puts a typed line, as the Monitor does.
;;
;; BASIC also writes a line's tokens here, after the line's text, and runs an immediate statement from here.
;; See: <WozMonitor:IN>, <GETLINE>, <TXTNDX>, <TOKNDX>
IN = $0200

;; The PIA's port A: the last key typed, with bit 7 set. Reading it clears bit 7 of <KBDCR>.
;; See: <WozMonitor:KBD>, <RDKEY>
KBD = $D010

;; The PIA's port A control register: bit 7 is set when a key has been typed and not yet read from <KBD>.
;;
;; The run loop looks at it before each line, and a key typed stops the program (<GOLINE>).
;; See: <WozMonitor:KBDCR>, <RDKEY>, <GOLINE>
KBDCR = $D011

;; The PIA's port B, the display: bit 7 reads 1 while the terminal is still taking the last character.
;;
;; BASIC writes it at $D0F2, one of the places the PIA repeats through $D000-$DFFF, where the Monitor uses $D012.
;; See: <WozMonitor:DSP>, <COUT>
DSP = $D0F2

; BASIC's own locations.
;; Where HIMEM= is moving the program to (2 bytes): it starts at the new HIMEM and steps down with each byte moved,
;; ending at the program's new start.
;; See: <VHIMEM>, <MOVEPROG>
NEWPP = $48

;; The lowest address of the variables, LOMEM (2 bytes): they grow upward from here to <PV>.
;;
;; The cold start (<COLD>) sets it to $0800, and LOMEM= (<VLOMEM>) changes it. <CLR> discards the variables by
;; setting <PV> back to it.
;; See: <HIMEM>, <PV>, <CLR>, <VLOMEM>
LOMEM = $4A

;; The address just above the program, HIMEM (2 bytes): the program grows downward from here to <PP>.
;;
;; The cold start (<COLD>) sets it to $1000, the top of a 4K machine, and HIMEM= (<VHIMEM>) moves it up, taking the
;; program with it. <NEW> discards the program by setting <PP> to it.
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
;; These bytes overlap the tokenizer's <SYNSTKH>.
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
;; For a string's second entry it is the index just past the string's last character.
;; See: <NOUNSTKL>, <NOUNSTKC>
NOUNSTKH = $78

;; The tokenizer's syntax stack: the low byte of the syntax table address to return to.
;; See: <SYNSTKH>
SYNSTKL = $80

;; The noun stack's high bytes of numbers.
;; See: <NOUNSTKL>, <NOUNSTKH>
NOUNSTKC = $A0

;; The tokenizer's syntax stack: <TXTNDX> as it was when each rule began, to back up to if the rule fails.
;; See: <SYNSTKH>, <TXTNDX>
TXTNDXSTK = $A8

;; The tokenizer's index of the last character it has matched in <IN>.
;;
;; It starts at $FF, before the line. When a rule fails, the tokenizer sets it back from <TXTNDXSTK>. INPUT reuses
;; it once the line is tokenized, to keep its place in the typed line's tokens.
;; See: <TOKNDX>, <TXTNDXSTK>, <COMMA_INPUT>
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
;; Each variable is its two name bytes (<LOOKUPVAR>), the address of the next variable (2 bytes, which is <PV> for
;; the last), and its value: 2 bytes for a number, 2 for each element of an array, and the room its DIM gave for a
;; string, whose characters end in a byte with bit 7 clear. A memory full error comes when <PV> would reach <PP>.
;; See: <LOMEM>, <PP>, <CLR>, <NEWVAR>
PV = $CC

;; The main 16-bit accumulator (2 bytes, low byte first).
;;
;; <GET16BIT> leaves a noun's value here, and the arithmetic and the statements work on it. <DOTOKEN_2> also jumps
;; through it to run each token's routine, and <LOOKUPVAR> keeps the name it looks for here.
;; See: <GET16BIT>, <AUX>
ACC = $CE

;; A pointer that walks the variables (2 bytes) when <LOOKUPVAR> looks a name up.
;; See: <LOOKUPVAR>, <NEWVAR>
SRCH = $D0

;; The tokenizer's syntax stack: <TOKNDX> as it was when each rule began, to back up to if the rule fails.
;;
;; Its first byte is also the high byte of <SRCH>.
;; See: <SYNSTKH>, <TOKNDX>
TOKNDXSTK = $D1

;; A second 16-bit work location (2 bytes): the end of a variable <NEWVAR> adds.
;; See: <NEWVAR>
SRCH2 = $D2

;; The IF flag: bit 7 is set while the statement after a false IF's THEN is being skipped.
;;
;; <IF> sets it when the condition is 0. The interpreter (<EXECLINE_10>) then passes over tokens until the next colon or
;; the end of the line, and clears it there, so the statements after a colon run whatever the condition was.
;; See: <IF>, <EXECLINE>, <EXECLINE_10>
IFFLAG = $D4

;; The carriage return flag: bit 7 is set when PRINT has printed something and still owes the line a return.
;;
;; Printing a number or a string sets it (<PRINTNUM_1>, <SETCRFLAG>); a semicolon or comma at the end of PRINT clears
;; it, and <COLON> prints the return at the end of the statement while it is set.
;; See: <COLON>, <PRINTNUM>, <PRINTSTR>
CRFLAG = $D5

;; The token the interpreter is about to run (<DOTOKEN>), the operator whose priority decides what runs first.
;;
;; IF stores the THEN token in it so a false condition skips the rest of the statement.
;; See: <DOTOKEN>, <IF>
VERBNOW = $D6

;; The priority of the token waiting to run, which <DOTOKEN> compares with the operators on the stack.
;;
;; A left parenthesis sets it to $FF (<LEFT_PAREN>), above any operator's, so nothing waiting before the
;; parenthesis runs until the right parenthesis comes.
;; See: <DOTOKEN>, <LEFT_PAREN>, <TABLE1>
PRFLAG = $D7

;; A place to keep X while the lister uses it.
;; See: <UNPACK>
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
;; GOSUB and FOR save it, and errors read the line number through it.
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
;; The tokens go into <IN> after the line's text: the command loop sets it to the length of the line, and <PUTTOKEN>
;; adds each token after it. A line that fills the buffer is TOO LONG.
;; See: <TXTNDX>, <PUTTOKEN>, <TOKNDXSTK>
TOKNDX = $F1

;; A 16-bit number (2 bytes) being built from a constant's digits by the tokenizer (<RULEMATCHED>), or printed in
;; decimal by <PRDEC>.
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
;; <AUTO> sets it; Control-D (<GETLINE>) and <NEW> clear it.
;; See: <AUTO>, <GETLINE>
AUTOFLAG = $F8

;; A character, or a count: the digit <PRDEC> is about to print, or the loop count of the tokenizer's multiply by 10.
;; See: <PRDEC>, <RULEMATCHED>
CHAR = $F9

;; What <PRDEC> prints for a leading zero: 0 prints nothing, $A0 a blank.
;;
;; The lister sets it to a blank so that line numbers line up; the prompt sets it to 0.
;; See: <PRDEC>, <UNPACK>
LEADZR = $FA

;; The number of FOR loops active, 0 to 8: an index into the FOR stack in page 1.
;; See: <FOR>, <NEXT>, <STK_20>
FORNDX = $FB

;; The number of GOSUBs active, 0 to 8: an index into the GOSUB stack in page 1.
;; See: <GOSUB>, <RETURN>, <STK_00>
GOSUBNDX = $FC

;; The tokenizer's syntax stack index: the frame of the rule being matched, from $20 down.
;; See: <SYNSTKH>, <MATCHITEM>
SYNSTKDX = $FD

;; A pointer into the syntax table (2 bytes): its low byte is always 0 (<CLR> clears it), and its high byte selects
;; the page, $EC or $ED. Y is the place in that page.
;; See: <SYNTABL>, <STARTRULE>
SYNPAG = $FE

; Page 1 below the 6502's stack, where GOSUB and FOR keep their state: 8 entries in each 8-byte column, indexed by
; GOSUBNDX or FORNDX. BASIC starts the 6502's stack at $01FF, and it does not grow down this far.
;; The GOSUB stack's return token addresses, low bytes: <PX> at each GOSUB.
;;
;; <STK_08> holds the high bytes, and <STK_10> and <STK_18> the line (<PR>) to return to.
;; See: <GOSUB>, <RETURN>, <GOSUBNDX>
STK_00 = $0100

STK_08 = $0108                      ;; the GOSUB stack: return token addresses, high bytes
STK_10 = $0110                      ;; the GOSUB stack: return line addresses, low bytes
STK_18 = $0118                      ;; the GOSUB stack: return line addresses, high bytes

;; The FOR stack's loop variable addresses, low bytes.
;;
;; Each FOR keeps one entry across the columns from here: its variable's address (<STK_20>, <STK_28>), its step
;; (<STK_30>, <STK_38>), the line and token after the FOR to loop back to (<STK_40> to <STK_58>) and its limit
;; (<STK_60>, <STK_68>).
;; See: <FOR>, <TO>, <STEP>, <NEXT>, <FORNDX>
STK_20 = $0120

STK_28 = $0128                      ;; the FOR stack: loop variable addresses, high bytes
STK_30 = $0130                      ;; the FOR stack: steps, low bytes
STK_38 = $0138                      ;; the FOR stack: steps, high bytes
STK_40 = $0140                      ;; the FOR stack: the FOR's line addresses, low bytes
STK_48 = $0148                      ;; the FOR stack: the FOR's line addresses, high bytes
STK_50 = $0150                      ;; the FOR stack: the token addresses after the FOR, low bytes
STK_58 = $0158                      ;; the FOR stack: the token addresses after the FOR, high bytes
STK_60 = $0160                      ;; the FOR stack: limits, low bytes
STK_68 = $0168                      ;; the FOR stack: limits, high bytes
