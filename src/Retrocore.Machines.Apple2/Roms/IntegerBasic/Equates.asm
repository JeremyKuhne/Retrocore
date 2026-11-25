; retrocore: style=strict ignore=unlinked-name:BASIC
;; Integer BASIC: constants, page zero and the Monitor addresses it uses
;;
;; The names Integer BASIC gives its constants, its page-zero locations and the parts of page 1 it borrows, and the
;; Monitor's locations and routines it uses that ../System/MonitorEntries.asm does not provide, under the Monitor's
;; current names. IntegerBasic.asm includes this file first. The floating-point routines, the Mini-Assembler and
;; SWEET16 define their own page-zero names in their files.
;;
;; Integer BASIC uses most of page zero from $4A up. Several areas have two uses that never overlap in time: the
;; tokenizer's syntax stack, while a line is being entered, and the interpreter's noun stack, while a statement runs,
;; share $50 to $F1.
;;
;; This file does not include ../System/IIeEquates.asm, as DOS's equates do: its Monitor locations carry the
;; Monitor's historical name ACC (for <Monitor:SavedA>), which would clash with Integer BASIC's ACC (<Accumulator>).

; Characters, without bit 7. The code adds $80 to them, as the Apple II's text has bit 7 set.

;; Control-C, which stops a running program or input.
;; Also: ETX (IBSM)
CONTROL_C = $03

;; A carriage return, the Return key.
;; Also: CR (IBSM)
CARRIAGE_RETURN = $0D

;; A blank (a space).
BLANK = $20

;; A double quote.
;; Also: DQT (IBSM)
DOUBLE_QUOTE = $22

; The Monitor's page-zero locations, the input buffer and the keyboard, under the Monitor's current names. Each
; inherits the Monitor's documentation and repeats its historical names, so code written with Apple's names assembles.

;; Inherit: <Monitor:WindowWidth>
;; Integer BASIC's `TAB` wraps a column past the window's width onto the next line by subtracting this.
;; Also: WNDWDTH (A2RM78, A2RM79, IIEROM82, IIETRM85)
WindowWidth = $21

;; Inherit: <Monitor:CursorColumn>
;; Integer BASIC reads it to tab `PRINT`'s commas to the next multiple of 8 and to break long lines when it lists a
;; program, and `TAB` sets it.
;; Also: CH (A2RM78, A2RM79, IIEROM82, IIETRM85)
CursorColumn = $24

;; Inherit: <Monitor:CV>
;; `VTAB` stores the line here and calls <VerticalTab> to move the cursor there.
CV = $25

;; Inherit: <Monitor:LowResBase>
;; SCRN( reads a block's color through it.
;; Also: GBASL (A2RM78, A2RM79, IIEROM82, IIETRM85)
LowResBase = $26

;; Inherit: <Monitor:HorizontalLineEnd>
;; `HLIN`'s second column goes here.
;; Also: H2 (A2RM78, A2RM79, IIEROM82, IIETRM85)
HorizontalLineEnd = $2C

;; Inherit: <Monitor:VerticalLineEnd>
;; `VLIN`'s second row goes here.
;; Also: V2 (A2RM78, A2RM79, IIEROM82, IIETRM85)
VerticalLineEnd = $2D

;; Inherit: <Monitor:OperandLength>
;; The Mini-Assembler reads it to copy an instruction's bytes into memory.
;; Also: LENGTH (A2RM78, A2RM79, IIEROM82, IIETRM85)
OperandLength = $2F

;; Inherit: <Monitor:CommandMode>
;; The Mini-Assembler passes it to the Monitor when a line starting with $ runs a Monitor command.
;; Also: MODE (A2RM78, A2RM79, IIEROM82, IIETRM85)
CommandMode = $31

;; Inherit: <Monitor:PromptCharacter>
;; Integer BASIC prompts with > (<SetPrompt>), and adds 1 to make it ? while `INPUT` reads a line, then takes 1 away
;; again. The Mini-Assembler prompts with !.
;; Also: PROMPT (A2RM78, A2RM79, IIEROM82, IIETRM85)
PromptCharacter = $33

;; Inherit: <Monitor:CommandPosition>
;; The Mini-Assembler keeps its own place in the line here too, and the Monitor's <ReadHexNumber> starts from it.
;; Also: YSAV (A2RM78, A2RM79, IIEROM82, IIETRM85)
CommandPosition = $34

;; Inherit: <Monitor:ProgramCounter>
;; Where the Mini-Assembler puts the next instruction.
;; Also: PCL (A2RM78, A2RM79, IIEROM82, IIETRM85)
ProgramCounter = $3A

;; Inherit: <Monitor:ProgramCounterHigh>
;; Also: PCH (A2RM78, A2RM79, IIEROM82, IIETRM85)
ProgramCounterHigh = $3B

;; Inherit: <Monitor:Address1>
;; Integer BASIC points it at the start of what the cassette routines read or write. The Mini-Assembler uses
;; <Address1High> to count opcodes and characters.
;; Also: A1L (A2RM78, A2RM79, IIEROM82, IIETRM85)
Address1 = $3C

;; Inherit: <Monitor:Address1High>
;; Also: A1H (A2RM78, A2RM79, IIEROM82, IIETRM85)
Address1High = $3D

;; Inherit: <Monitor:Address2>
;; The last address the cassette routines read or write; the Mini-Assembler reads the number <ReadHexNumber> leaves here
;; as an instruction's operand.
;; Also: A2L (A2RM78, A2RM79, IIEROM82, IIETRM85)
Address2 = $3E

;; Inherit: <Monitor:Address2High>
;; Also: A2H (A2RM78, A2RM79, IIEROM82, IIETRM85)
Address2High = $3F

;; Inherit: <Monitor:Address4>
;; The Mini-Assembler packs the three letters of a mnemonic into it, five bits each, in the form of the Monitor's
;; <MnemonicsLeft> and <MnemonicsRight> tables.
;; Also: A4L (A2RM78, A2RM79, IIEROM82, IIETRM85)
Address4 = $42

;; Inherit: <Monitor:Address4High>
;; Also: A4H (A2RM78, A2RM79, IIEROM82, IIETRM85)
Address4High = $43

;; Inherit: <Monitor:RandomSeed>
;; Since it depends on how long the user takes to type, `RND` uses it as its seed and keeps its random state here.
;; Also: RNDL (A2RM78, A2RM79, IIEROM82, IIETRM85)
RandomSeed = $4E

;; Inherit: <Monitor:RandomSeedHigh>
;; Also: RNDH (A2RM78, A2RM79, IIEROM82, IIETRM85)
RandomSeedHigh = $4F

;; Inherit: <Monitor:InputBuffer>
;; Integer BASIC also writes a line's tokens here, after the line's text, and runs an immediate statement from here.
;; Also: IN (A2RM78, A2RM79, IIEROM82, IIETRM85), LBUFF (DOS33, DOS31)
InputBuffer = $0200

;; Inherit: <Monitor:Keyboard>
;; Also: IOADR (A2RM78, A2RM79, IIEROM82, IIETRM85), KBD (A2RM78, A2RM79, IIEROM82, IIETRM85)
Keyboard = $C000

;; Inherit: <Monitor:KeyboardStrobe>
;; Also: KBDSTRB (A2RM78, A2RM79, IIEROM82, IIETRM85)
KeyboardStrobe = $C010

; The Monitor's routines and tables that MonitorEntries.asm leaves out, under the Monitor's current names, in the
; Monitor's scopes where it has them.

;; Inherit: <Monitor:LowRes>
.scope LowRes

;; Inherit: <Monitor:LowRes::Plot>
;; `PLOT` jumps here.
;; Also: PLOT (A2RM78, A2RM79, IIEROM82, IIETRM85)
Plot = $F800

;; Inherit: <Monitor:LowRes::HorizontalLine>
;; `HLIN` jumps here.
;; Also: HLINE (A2RM78, A2RM79, IIEROM82, IIETRM85)
HorizontalLine = $F819

;; Inherit: <Monitor:LowRes::VerticalLine>
;; `VLIN` jumps here.
;; Also: VLINE (A2RM78, A2RM79, IIEROM82, IIETRM85)
VerticalLine = $F828

;; Inherit: <Monitor:LowRes::RowAddress>
;; SCRN( calls it to find a block's row.
;; Also: GBASCALC (A2RM78, A2RM79, IIEROM82, IIETRM85)
RowAddress = $F847

;; Inherit: <Monitor:LowRes::SetColor>
;; COLOR= jumps here.
;; Also: SETCOL (A2RM78, A2RM79, IIEROM82, IIETRM85)
SetColor = $F864

.endscope

;; Inherit: <Monitor:Disassembler>
.scope Disassembler

;; Inherit: <Monitor:Disassembler::Decode>
.scope Decode

;; Inherit: <Monitor:Disassembler::Decode::Opcode>
;; The Mini-Assembler calls it on each opcode it tries.
;; Also: INSDS2 (A2RM78, A2RM79, IIEROM82, IIETRM85)
Opcode = $F88E

.endscope

;; Inherit: <Monitor:Disassembler::FormatBits>
;; The Mini-Assembler compares each opcode's format with the operand it read.
;; Also: FORMAT (A2RM78, A2RM79, IIEROM82, IIETRM85)
FormatBits = $2E

;; Inherit: <Monitor:Disassembler::PrintInstruction>
;; The Mini-Assembler shows each line it assembles with it.
;; Also: INSTDSP (A2RM78, A2RM79, IIEROM82, IIETRM85)
PrintInstruction = $F8D0

.endscope

;; Inherit: <Monitor:PrintBlanks>
;; Also: PRBL2 (A2RM78, A2RM79, IIEROM82, IIETRM85)
PrintBlanks = $F94A

;; Inherit: <Monitor:NextInstruction>
;; Also: PCADJ (A2RM78, A2RM79, IIEROM82, IIETRM85)
NextInstruction = $F953

;; Inherit: <Monitor:ReadPaddle>
;; `PDL` calls it.
;; Also: PREAD (A2RM78, A2RM79, IIEROM82, IIETRM85)
ReadPaddle = $FB1E

;; Inherit: <Monitor:SetText>
;; `TEXT` runs it directly from the verb table.
;; Also: SETTXT (A2RM78, A2RM79, IIEROM82, IIETRM85)
SetText = $FB39

;; Inherit: <Monitor:SetGraphics>
;; `GR` runs it directly from the verb table.
;; Also: SETGR (A2RM78, A2RM79, IIEROM82, IIETRM85)
SetGraphics = $FB40

;; Inherit: <Monitor:GetLineAfterReturn>
;; The Mini-Assembler reads its lines with it.
;; Also: GETLNZ (A2RM78, A2RM79, IIEROM82, IIETRM85)
GetLineAfterReturn = $FD67

;; Inherit: <Monitor:GetLine>
.scope GetLine

;; Inherit: <Monitor:GetLine::NextCharacter>
;; Integer BASIC enters the Monitor's line input here, after the prompt, so it can print its own prompt first.
;; Also: NXTCHAR (A2RM78, A2RM79, IIEROM82, IIETRM85)
NextCharacter = $FD75

.endscope

;; Inherit: <Monitor:CharacterOut>
;; Also: COUT (A2RM78, A2RM79, IIEROM82, IIETRM85)
CharacterOut = $FDED

;; Inherit: <Monitor:Commands>
.scope Commands

;; Inherit: <Monitor:Commands::ExamineNextOrBlank>
;; The Mini-Assembler passes a $ line's Return here.
;; Also: BL1 (A2RM78, A2RM79, IIEROM82, IIETRM85)
ExamineNextOrBlank = $FE00

;; Inherit: <Monitor:Commands::RunCommand>
;; Also: TOSUB (A2RM78, A2RM79, IIEROM82, IIETRM85)
RunCommand = $FFBE

;; Inherit: <Monitor:Commands::Keys>
;; Also: CHRTBL (A2RM78, A2RM79, IIEROM82, IIETRM85)
Keys = $FFCC

.endscope

;; Inherit: <Monitor:SetInput>
;; IN# calls it.
;; Also: INPORT (A2RM78, A2RM79, IIEROM82, IIETRM85)
SetInput = $FE8B

;; Inherit: <Monitor:SetOutput>
;; PR# calls it.
;; Also: OUTPORT (A2RM78, A2RM79, IIEROM82, IIETRM85)
SetOutput = $FE95

;; Inherit: <Monitor:WriteCassette>
;; Also: WRITE (A2RM78, A2RM79, IIEROM82, IIETRM85)
WriteCassette = $FECD

;; <WriteCassette> entered after its first instruction, which loads the length of the header tone, so the caller's A
;; sets the length instead.
;;
;; `SAVE` writes the program with a shorter tone ($1A) than its first record, the program's length.
;; Also: WRITE0 (UNKN)
WriteCassetteWithHeader = WriteCassette + 2

;; Inherit: <Monitor:ReadCassette>
;; Also: READ (A2RM78, A2RM79, IIEROM82, IIETRM85)
ReadCassette = $FEFD

;; Inherit: <Monitor:Beep>
;; Also: BELL (A2RM78, A2RM79, IIEROM82, IIETRM85)
Beep = $FF3A

;; Inherit: <Monitor:RestoreRegisters>
;; Also: RESTORE (A2RM78, A2RM79, IIEROM82, IIETRM85)
RestoreRegisters = $FF3F

;; Inherit: <Monitor:SaveRegisters>
;; Also: SAVE (A2RM78, A2RM79, IIEROM82, IIETRM85)
SaveRegisters = $FF4A

;; Inherit: <Monitor:ReadHexNumber>
;; Also: GETNUM (A2RM78, A2RM79, IIEROM82, IIETRM85)
ReadHexNumber = $FFA7


; Integer BASIC's own locations.
;; The lowest address of the variables, `LOMEM` (2 bytes): they grow upward from here to <PV>.
;;
;; The cold start (<COLD>) sets it to $0800, the first page above the text screen, and LOMEM: (<VLOMEM>) changes it.
;; <CLR> discards the variables by setting <PV> back to it.
;; See: <HIMEM>, <PV>, <CLR>, <VLOMEM>
;; Also: LOMEM (IBSM)
LowMemory = $4A

;; The address just above the program, `HIMEM` (2 bytes): the program grows downward from here to <PP>.
;;
;; The cold start (<COLD>) sets it to the top of RAM, and HIMEM: (<VHIMEM>) moves it, taking the program with it.
;; <NEW> discards the program by setting <PP> to it.
;; See: <LOMEM>, <PP>, <NEW>, <VHIMEM>
;; Also: HIMEM (IBSM)
HighMemory = $4C

;; The noun stack's low bytes: one per entry, indexed by X, which starts at $20 and counts down as entries are
;; pushed.
;;
;; While a statement runs, each operand (a "noun") takes one entry in three arrays: <NOUNSTKL>, <NOUNSTKH> and
;; <NOUNSTKC>. A number is its low byte here and its high byte in <NOUNSTKC>, with 0 in <NOUNSTKH>. A variable is its
;; address, low byte here and high byte in <NOUNSTKH>, which is never 0, so <GET16BIT> can tell the two apart. A
;; string takes two entries: its address, and above it the range of characters, the first index here and the end
;; index in <NOUNSTKH>. A push below X = 0 (<PUSHNOUNLO>) is an error, whose message is PPED `AT` (<PUSHNOUN_1>).
;;
;; These bytes overlap the tokenizer's <SYNSTKH>, and <CHKBREAK> saves the place to continue here when Control-C stops
;; a program, for `CON`.
;; See: <NOUNSTKH>, <NOUNSTKC>, <GET16BIT>, <PUSHNOUN>, <SYNSTKH>
;; Also: NOUNSTKL (IBSM)
NounStackLow = $50

;; The tokenizer's syntax stack: the high byte of the syntax table address to return to, one per rule being
;; matched.
;;
;; The tokenizer pushes a frame when one syntax rule calls another (<CALLRULE>): the place in the caller here and in
;; <SYNSTKL>, and where the input and output stood in <TXTNDXSTK> and <TOKNDXSTK>, so a rule that fails can restore
;; them and let the caller try its next alternative. X indexes the frames, from $20 down. These bytes are the noun
;; stack's (<NOUNSTKL>) while a statement runs.
;; See: <SYNSTKL>, <TXTNDXSTK>, <TOKNDXSTK>, <SYNSTKDX>, <SYNTABL>
;; Also: SYNSTKH (IBSM)
SyntaxStackHigh = $58

;; The noun stack's high bytes of addresses: the high byte of a variable's address, or 0 for a number.
;;
;; For a string's second entry it is the index just past the string's last character. <CHKBREAK> saves the current
;; line's address in its first two bytes when Control-C stops a program.
;; See: <NOUNSTKL>, <NOUNSTKC>
;; Also: NOUNSTKH (IBSM)
NounStackHigh = $78

;; The tokenizer's syntax stack: the low byte of the syntax table address to return to.
;; See: <SYNSTKH>
;; Also: SYNSTKL (IBSM)
SyntaxStackLow = $80

;; The noun stack's high bytes of numbers.
;;
;; Its first byte, $A0, is also the `TRACE` flag: <TRACE> sets bit 7, <NOTRACE> clears it, and the run loop prints each
;; line's number while it is set (<TRACELINE>).
;; See: <NOUNSTKL>, <NOUNSTKH>, <TRACE>
;; Also: NOUNSTKC (IBSM)
NounStackNumberHigh = $A0

;; The tokenizer's syntax stack: <TXTNDX> as it was when each rule began, to back up to if the rule fails.
;; See: <SYNSTKH>, <TXTNDX>
;; Also: TXTNDXSTK (IBSM)
TextIndexStack = $A8

;; The tokenizer's index of the last character it has matched in <IN>.
;;
;; It starts at $FF, before the line. When a rule fails, the tokenizer sets it back from <TXTNDXSTK>. Statements
;; reuse it as a scratch byte once the line is tokenized: `POKE`, `PLOT`, `HLIN` and `VLIN` keep their first value here
;; (<GETVAL255>), and `INPUT` keeps its place in the typed line.
;; See: <TOKNDX>, <TXTNDXSTK>, <GETVAL255>, <COMMA_INPUT>
;; Also: TXTNDX (IBSM)
TextIndex = $C8

;; A count of digits: <PRDEC> counts down the places of a number it prints and keeps the first digit that is not
;; 0 here; the tokenizer keeps the place in <IN> where a constant's digits start (<RULEMATCHED>).
;; See: <PRDEC>, <LEADZR>
;; Also: LEADBL (IBSM)
DigitPlace = $C9

;; The start of the program, PP (2 bytes): its lowest address. The program's lines lie from here up to <HIMEM>.
;;
;; Each line is a length byte (counting itself), the line number (low byte first), the line's tokens and $01, the
;; end-of-line token. Lines are kept in increasing order of their numbers. Entering a line moves the lines below it
;; down to make room, so <PP> moves down; <NEW> sets it to <HIMEM>.
;; See: <HIMEM>, <PV>, <FINDLINE>, <WARM>
;; Also: PP (IBSM)
ProgramStart = $CA

;; The end of the variables, PV (2 bytes): the address just past the last one. They lie from <LOMEM> up to here.
;;
;; Each variable is its name (characters with bit 7 set; a string variable's name ends in $40, the $ token), a
;; display flag (1 after `DSP`, otherwise 0), the address of the next variable (2 bytes, the next one's name, which
;; is <PV> for the last), and its value: 2 bytes for a number, 2 for each element of an array, and its dimension
;; plus 1 for a string, whose characters end in a byte with bit 7 clear. A memory full error comes when <PV> would
;; pass <PP>.
;; See: <LOMEM>, <PP>, <CLR>, <CMPVARNAME>
;; Also: PV (IBSM)
VariablesEnd = $CC

;; The main 16-bit accumulator (2 bytes, low byte first).
;;
;; <GET16BIT> leaves a noun's value here, and the arithmetic, the statements and the cassette routines work on it.
;; <DOTOKEN_2> also jumps through it to run each token's routine.
;; See: <GET16BIT>, <AUX>
;; Also: ACC (IBSM)
Accumulator = $CE

;; A pointer that walks the variables (2 bytes) when <CMPVARNAME> looks a name up.
;;
;; <EXP> counts its multiplications in it instead.
;; See: <CMPVARNAME>, <PRVARNAME>, <EXP>
;; Also: SRCH (IBSM)
SearchPointer = $D0

;; The tokenizer's syntax stack: <TOKNDX> as it was when each rule began, to back up to if the rule fails.
;;
;; Its first byte is also the high byte of <SRCH>.
;; See: <SYNSTKH>, <TOKNDX>
;; Also: TOKNDXSTK (IBSM)
TokenIndexStack = $D1

;; A second 16-bit work location (2 bytes): <EXP> keeps the number it multiplies by here.
;; See: <EXP>
;; Also: SRCH2 (IBSM)
SearchPointer2 = $D2

;; The `IF` flag: bit 7 is set while the statement after a false `IF`'s `THEN` is being skipped.
;;
;; <IF> sets it when the condition is 0. The interpreter (<EXECLINE_10>) then passes over tokens until the next colon or
;; the end of the line, and clears it there, so the statements after a colon run whatever the condition was.
;; See: <IF>, <EXECLINE>, <EXECLINE_10>
;; Also: IFFLAG (IBSM)
SkippingStatement = $D4

;; The carriage return flag: bit 7 is set when `PRINT` has printed something and still owes the line a return.
;;
;; Printing a number or a string sets it (<PRINTNUM_1>, <SETCRFLAG>); a semicolon or comma at the end of `PRINT` clears it
;; (<SEMI_END>, <COMMA_PREND>), and <COLON> prints the return at the end of the statement while it is set.
;; See: <COLON>, <PRINTNUM>, <PRINTSTR>
;; Also: CRFLAG (IBSM)
ReturnPending = $D5

;; The token the interpreter is about to run (<DOTOKEN>), the operator whose priority decides what runs first.
;;
;; `IF` stores the `THEN` token in it so a false condition skips the rest of the statement.
;; See: <DOTOKEN>, <IF>
;; Also: VERBNOW (IBSM)
CurrentVerb = $D6

;; The priority of the token waiting to run, which <DOTOKEN> compares with the operators on the stack.
;;
;; A left parenthesis and SCRN( set it to $FF (<LEFT_PAREN>), above any operator's, so nothing waiting before the
;; parenthesis runs until the right parenthesis comes.
;; See: <DOTOKEN>, <LEFT_PAREN>, <TABLE1>
;; Also: PRFLAG (IBSM)
VerbPriority = $D7

;; A place to keep X while a routine uses it: the noun stack index, around calls to the Monitor and while a routine
;; walks memory.
;;
;; <CMPVARNAME> also keeps whether a variable name ends in $ in bit 6 here.
;; Also: XSAVE (IBSM)
SavedX = $D8

;; The run flag: bit 7 is set while a program runs, clear for an immediate statement.
;;
;; <GETNEXT> sets it for each statement; errors (<ERRMESS>) and `END` check it.
;; See: <GETNEXT>, <ERRMESS>
;; Also: RUNFLAG (IBSM)
Running = $D9

;; A second 16-bit accumulator (2 bytes), the other operand of the arithmetic and a pointer for string work.
;; See: <ACC>, <MULT>, <DIVMOD>
;; Also: AUX (IBSM)
Auxiliary = $DA

;; The address of the line running (2 bytes): its length byte, from which the run loop steps to the next line.
;;
;; `GOSUB` and `FOR` save it, and errors and `TRACE` read the line number through it.
;; See: <GOLINE>, <PX>, <GOSUB>, <FOR>
;; Also: PR (IBSM)
CurrentLine = $DC

;; The address of the token being run (2 bytes).
;;
;; <GETVERB> steps it through the line. `GOSUB` and `FOR` save it to come back to.
;; See: <GETVERB>, <PR>, <GETNEXT>
;; Also: PX (IBSM)
TokenPointer = $E0

;; A work pointer (2 bytes): the next byte to list (<NextByte>), and the place to delete from when a line is
;; replaced.
;; See: <NextByte>, <DELLINE>
;; Also: P1 (IBSM)
Pointer1 = $E2

;; A work pointer (2 bytes): the line found by <FINDLINE>, the new start of the program while lines move, and the
;; listed token's flags.
;; See: <FINDLINE>, <CLOSEGAP>
;; Also: P2 (IBSM)
Pointer2 = $E4

;; A work pointer (2 bytes): where <FINDLINE> searches from, the end of a range to list or delete, and a remainder in
;; division.
;; See: <FINDLINE>, <COMMA_LIST>, <DIVMOD>
;; Also: P3 (IBSM)
Pointer3 = $E6

;; The tokenizer's index of the last token it has written in <IN>.
;;
;; The tokens go into <IN> after the line's text: GETCMD sets it to the length of the line, and <PUTTOKEN> adds each
;; token after it. A line that fills the buffer is TOO LONG.
;; See: <TXTNDX>, <PUTTOKEN>, <TOKNDXSTK>
;; Also: TOKNDX (IBSM)
TokenIndex = $F1

;; A 16-bit number (2 bytes) being built from a constant's digits by the tokenizer (<RULEMATCHED>), or printed in decimal
;; by <PRDEC>.
;; See: <PRDEC>, <RULEMATCHED>
;; Also: PCON (IBSM)
DecimalNumber = $F2

;; The step between line numbers in `AUTO` mode (2 bytes), 10 unless `AUTO` gives one.
;; See: <AUTO>, <COMMA_AUTO>, <AUTOLN>
;; Also: AUTOINC (IBSM)
AutoIncrement = $F4

;; The next line number `AUTO` offers (2 bytes).
;; See: <AUTO>, <AUTOINC>, <WARM>
;; Also: AUTOLN (IBSM)
AutoLine = $F6

;; The `AUTO` flag: bit 7 is set in `AUTO` mode, when the prompt offers the next line number.
;;
;; <AUTO> sets it; `MAN` (<MAN>) and <NEW> clear it.
;; See: <AUTO>, <MAN>
;; Also: AUTOFLAG (IBSM)
AutoNumbering = $F8

;; A character, or a count: the digit <PRDEC> is about to print, or the loop count of the tokenizer's multiply by 10.
;; See: <PRDEC>, <RULEMATCHED>
;; Also: CHAR (IBSM)
DigitCharacter = $F9

;; What <PRDEC> prints for a leading zero: 0 prints nothing, $A0 a blank.
;;
;; The lister sets it to a blank so that line numbers line up; the prompt sets it to 0.
;; See: <PRDEC>, <UNPACK>
;; Also: LEADZR (IBSM)
LeadingZero = $FA

;; The number of `FOR` loops active, 0 to 16: an index into the `FOR` stack in page 1.
;; See: <FOR>, <NEXT>, <STK_40>
;; Also: FORNDX (IBSM)
ForIndex = $FB

;; The number of GOSUBs active, 0 to 16: an index into the `GOSUB` stack in page 1.
;; See: <GOSUB>, <RETURN>, <STK_00>
;; Also: GOSUBNDX (IBSM)
GoSubIndex = $FC

;; The tokenizer's syntax stack index: the frame of the rule being matched, from $20 down.
;; See: <SYNSTKH>, <MATCHITEM>
;; Also: SYNSTKDX (IBSM)
SyntaxStackIndex = $FD

;; A pointer into the syntax table (2 bytes): its low byte is always 0 (<CLR> clears it), and its high byte selects
;; the page, $EC or $ED. Y is the place in that page.
;; See: <SYNTABL>, <STARTRULE>
;; Also: SYNPAG (IBSM)
SyntaxPage = $FE

; Page 1 below the 6502's stack, where `GOSUB` and `FOR` keep their state: 16 entries in each 16-byte column, indexed by
; GOSUBNDX or FORNDX. Integer BASIC starts the 6502's stack at $01FF, and it does not grow down this far.
;; The `GOSUB` stack's return token addresses, low bytes: <PX> at each `GOSUB`.
;;
;; <STK_10> holds the high bytes, and <STK_20> and <STK_30> the line (<PR>) to return to.
;; See: <GOSUB>, <RETURN>, <GOSUBNDX>
;; Also: STK_00 (IBSM)
GoSubTokenLow = $0100

;; The `GOSUB` stack: return token addresses, high bytes.
;; Also: STK_10 (IBSM)
GoSubTokenHigh = $0110

;; The `GOSUB` stack: return line addresses, low bytes.
;; Also: STK_20 (IBSM)
GoSubLineLow = $0120

;; The `GOSUB` stack: return line addresses, high bytes.
;; Also: STK_30 (IBSM)
GoSubLineHigh = $0130

;; The `FOR` stack's loop variable addresses, low bytes.
;;
;; Each `FOR` keeps one entry across the columns from here: its variable's address (<STK_40>, <STK_50>), its step
;; (<STK_60>, <STK_70>), the line and token after the `FOR` to loop back to (<STK_80> to <STK_B0>) and its limit
;; (<STK_C0>, <STK_D0>).
;; See: <FOR>, <TO>, <STEP>, <NEXT>, <FORNDX>
;; Also: STK_40 (IBSM)
ForVariableLow = $0140

;; The `FOR` stack: loop variable addresses, high bytes.
;; Also: STK_50 (IBSM)
ForVariableHigh = $0150

;; The `FOR` stack: steps, low bytes.
;; Also: STK_60 (IBSM)
ForStepLow = $0160

;; The `FOR` stack: steps, high bytes.
;; Also: STK_70 (IBSM)
ForStepHigh = $0170

;; The `FOR` stack: the `FOR`'s line addresses, low bytes.
;; Also: STK_80 (IBSM)
ForLineLow = $0180

;; The `FOR` stack: the `FOR`'s line addresses, high bytes.
;; Also: STK_90 (IBSM)
ForLineHigh = $0190

;; The `FOR` stack: the token addresses after the `FOR`, low bytes.
;; Also: STK_A0 (IBSM)
ForTokenLow = $01A0

;; The `FOR` stack: the token addresses after the `FOR`, high bytes.
;; Also: STK_B0 (IBSM)
ForTokenHigh = $01B0

;; The `FOR` stack: limits, low bytes.
;; Also: STK_C0 (IBSM)
ForLimitLow = $01C0

;; The `FOR` stack: limits, high bytes.
;; Also: STK_D0 (IBSM)
ForLimitHigh = $01D0
