; retrocore: style=strict
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

; Tokens: the values the tokenizer stores, which the code tests or writes. Each token's routine is in the verb tables
; (VerbTables.asm), which list them all.

;; The token that ends every line, stored or typed, and runs every token still waiting.
TOKEN_END_OF_LINE = $01

;; The colon between statements.
TOKEN_COLON = $03

;; `THEN` before a statement, which does nothing: <Statements::If> makes the arriving `THEN` this one when the
;; condition is false, so that `THEN` followed by a line number does not jump.
TOKEN_THEN_STATEMENT = $25

;; The quote that opens a string constant; the string's characters follow, with bit 7 set, then the closing quote's
;; token, $29.
TOKEN_OPEN_QUOTE = $28

;; The $ that ends a string variable's name: the name's characters have bit 7 set, and this byte does not.
TOKEN_DOLLAR = $40

;; `REM`; the remark's characters follow it to the end of the line.
TOKEN_REM = $5D

;; The token the `INPUT` rule (<Syntax::InputLineStart>) writes at the end of a line of numbers, and which `INPUT`
;; puts at the start of <InputBuffer> (<MarkInputLineUsed>) to mark the line used up, so the next variable asks for
;; a new one.
TOKEN_INPUT_END = $80

;; A comma between `INPUT`'s numbers.
TOKEN_INPUT_COMMA = $81

;; A plus sign before one of `INPUT`'s numbers.
TOKEN_INPUT_PLUS = $82

;; A minus sign before one of `INPUT`'s numbers, which <Statements::InputNumberComma> negates.
TOKEN_INPUT_MINUS = $83

; The stacks' sizes.

;; X when the noun stack is empty; it counts down as entries are pushed.
NOUN_STACK_EMPTY = $20

;; X when the tokenizer's syntax stack is empty, where it starts a line: the frames are pushed from here down. It is
;; the noun stack's start too, as the two stacks share their bytes.
SYNTAX_STACK_EMPTY = $20

;; The number of `GOSUB`s that can be active, the entries of the `GOSUB` stack (<GoSubTokenLow>).
GOSUB_STACK_DEPTH = 16

;; The number of `FOR` loops that can be active, the entries of the `FOR` stack (<ForVariableLow>).
FOR_STACK_DEPTH = 16

; The syntax table's characters (SyntaxTable.asm) and the typed line's end.

;; The character that marks the end of a typed line in <InputBuffer>: the underline, which takes the place of the
;; Return, and which the syntax table's last rule matches.
LINE_END_MARK = '_'

;; The bits of a character byte in the syntax table that hold the character, less <SYNTAX_CHARACTER_BASE>.
SYNTAX_CHARACTER_BITS = $3F

;; What a syntax table character's low 6 bits are added to: the blank, with bit 7 set, so the table can hold $A0
;; to $DF.
SYNTAX_CHARACTER_BASE = BLANK | $80

;; The least syntax table byte that is a keyword's last character: bit 7, a character, and bit 6, its alternative's
;; last item.
SYNTAX_LAST_CHARACTER = $80 | Syntax::ITEM_LAST

;; The bit of a syntax table character that is set for the letters ($C0-$DF) and clear for punctuation and digits.
SYNTAX_LETTER_BIT = $20

; The screens.

;; The lo-res screen's rows: `PLOT` and `HLIN` take a row from 0 to 47.
LOW_RES_ROWS = 48

;; The lo-res screen's columns: `PLOT` and `VLIN` take a column from 0 to 39.
LOW_RES_COLUMNS = 40

;; The text screen's lines: `VTAB` takes a line from 1 to 24.
TEXT_ROWS = 24

; The layouts of the program's lines and the variables.

;; A line of the program, as it is stored from <ProgramStart> up; its tokens end with <TOKEN_END_OF_LINE>.
.struct ProgramLine
    LENGTH .byte                    ;; The line's length in bytes, counting this byte.
    NUMBER .word                    ;; The line number, low byte first.
    TOKENS .byte                    ;; The first of the line's tokens.
.endstruct

;; The fields that follow a variable's name, a display flag, the link to the next variable and the value.
;;
;; A new variable's value is 2 bytes, 0: a number, or room that `DIM` can enlarge for an array or a string.
.struct VariableFields
    DISPLAY_FLAG .byte              ;; 1 after `DSP`, otherwise 0: the byte that ends the name.
    NEXT .word                      ;; The address of the next variable's name; <VariablesEnd> for the last.
    VALUE .word                     ;; The value, or the first 2 bytes of an array's or a string's.
.endstruct

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
;; The lowest address of the variables, `LOMEM` (2 bytes): they grow upward from here to <VariablesEnd>.
;;
;; The cold start (<ColdStart>) sets it to $0800, the first page above the text screen, and LOMEM: (<Statements::LoMem>)
;; changes it. <Statements::Clr> discards the variables by setting <VariablesEnd> back to it.
;; See: <HighMemory>, <VariablesEnd>, <Statements::Clr>, <Statements::LoMem>
;; Also: LOMEM (IBSM)
LowMemory = $4A

;; The address just above the program, `HIMEM` (2 bytes): the program grows downward from here to <ProgramStart>.
;;
;; The cold start (<ColdStart>) sets it to the top of RAM, and HIMEM: (<Statements::HiMem>) moves it, taking the program
;; with it. <Statements::New> discards the program by setting <ProgramStart> to it.
;; See: <LowMemory>, <ProgramStart>, <Statements::New>, <Statements::HiMem>
;; Also: HIMEM (IBSM)
HighMemory = $4C

;; The noun stack's low bytes: one per entry, indexed by X, which starts at $20 and counts down as entries are
;; pushed.
;;
;; While a statement runs, each operand (a "noun") takes one entry in three arrays: <NounStackLow>, <NounStackHigh> and
;; <NounStackNumberHigh>. A number is its low byte here and its high byte in <NounStackNumberHigh>, with 0 in
;; <NounStackHigh>. A variable is its address, low byte here and high byte in <NounStackHigh>, which is never 0, so
;; <GetNumber> can tell the two apart. A string takes two entries: its address, and above it the range of characters,
;; the first index here and the end index in <NounStackHigh>. A push below X = 0 (<PushNoun::LowOnly>) is an error,
;; whose message is PPED `AT` (<PushNoun::Full>).
;;
;; These bytes overlap the tokenizer's <SyntaxStackHigh>, and <Break::Check> saves the place to continue here when
;; Control-C stops a program, for `CON`.
;; See: <NounStackHigh>, <NounStackNumberHigh>, <GetNumber>, <PushNoun>, <SyntaxStackHigh>
;; Also: NOUNSTKL (IBSM)
NounStackLow = $50

;; The tokenizer's syntax stack: the high byte of the syntax table address to return to, one per rule being
;; matched.
;;
;; The tokenizer pushes a frame when one syntax rule calls another (<Tokenizer::CallRule>): the place in the caller here
;; and in <SyntaxStackLow>, and where the input and output stood in <TextIndexStack> and <TokenIndexStack>, so a rule
;; that fails can restore them and let the caller try its next alternative. X indexes the frames, from $20 down. These
;; bytes are the noun stack's (<NounStackLow>) while a statement runs.
;; See: <SyntaxStackLow>, <TextIndexStack>, <TokenIndexStack>, <SyntaxStackIndex>, <Syntax::Table>
;; Also: SYNSTKH (IBSM)
SyntaxStackHigh = $58

;; The noun stack's high bytes of addresses: the high byte of a variable's address, or 0 for a number.
;;
;; For a string's second entry it is the index just past the string's last character. <Break::Check> saves the current
;; line's address in its first two bytes when Control-C stops a program.
;; See: <NounStackLow>, <NounStackNumberHigh>
;; Also: NOUNSTKH (IBSM)
NounStackHigh = $78

;; The tokenizer's syntax stack: the low byte of the syntax table address to return to.
;; See: <SyntaxStackHigh>
;; Also: SYNSTKL (IBSM)
SyntaxStackLow = $80

;; The noun stack's high bytes of numbers.
;;
;; Its first byte, $A0, is also the `TRACE` flag: <Statements::Trace> sets bit 7, <Statements::NoTrace> clears it, and
;; the run loop prints each line's number while it is set (<Display::TraceLine>).
;; See: <NounStackLow>, <NounStackHigh>, <Statements::Trace>
;; Also: NOUNSTKC (IBSM)
NounStackNumberHigh = $A0

;; The tokenizer's syntax stack: <TextIndex> as it was when each rule began, to back up to if the rule fails.
;; See: <SyntaxStackHigh>, <TextIndex>
;; Also: TXTNDXSTK (IBSM)
TextIndexStack = $A8

;; The tokenizer's index of the last character it has matched in <InputBuffer>.
;;
;; It starts at $FF, before the line. When a rule fails, the tokenizer sets it back from <TextIndexStack>. Statements
;; reuse it as a scratch byte once the line is tokenized: `POKE`, `PLOT`, `HLIN` and `VLIN` keep their first value here
;; (<Statements::FirstValue>), and `INPUT` keeps its place in the typed line.
;; See: <TokenIndex>, <TextIndexStack>, <Statements::FirstValue>, <Statements::InputNumberComma>
;; Also: TXTNDX (IBSM)
TextIndex = $C8

;; A byte two routines use for digits: <PrintDecimal> sets its bit 7 once it has printed a digit that is not 0, so the
;; zeros after it print; the tokenizer keeps the place in <InputBuffer> just before a constant's first digit
;; (<Tokenizer::RuleMatched>).
;; See: <PrintDecimal>, <LeadingZero>
;; Also: LEADBL (IBSM)
DigitPlace = $C9

;; The start of the program, PP (2 bytes): its lowest address. The program's lines lie from here up to <HighMemory>.
;;
;; Each line is a length byte (counting itself), the line number (low byte first), the line's tokens and $01, the
;; end-of-line token. Lines are kept in increasing order of their numbers. Entering a line moves the lines below it
;; down to make room, so <ProgramStart> moves down; <Statements::New> sets it to <HighMemory>.
;; See: <HighMemory>, <VariablesEnd>, <FindLine>, <WarmStart>
;; Also: PP (IBSM)
ProgramStart = $CA

;; The end of the variables, PV (2 bytes): the address just past the last one. They lie from <LowMemory> up to here.
;;
;; Each variable is its name (characters with bit 7 set; a string variable's name ends in $40, the $ token), a
;; display flag (1 after `DSP`, otherwise 0), the address of the next variable (2 bytes, the next one's name, which
;; is <VariablesEnd> for the last), and its value: 2 bytes for a number, 2 for each element of an array, and its
;; dimension plus 1 for a string, whose characters end in a byte with bit 7 clear. A memory full error comes when
;; <VariablesEnd> would pass <ProgramStart>.
;; See: <LowMemory>, <ProgramStart>, <Statements::Clr>, <Variables::CompareName>
;; Also: PV (IBSM)
VariablesEnd = $CC

;; The main 16-bit accumulator (2 bytes, low byte first).
;;
;; <GetNumber> leaves a noun's value here, and the arithmetic, the statements and the cassette routines work on it.
;; <Interpreter::RunLine::RunWaiting> also jumps through it to run each token's routine.
;; See: <GetNumber>, <Auxiliary>
;; Also: ACC (IBSM)
Accumulator = $CE

;; A pointer that walks the variables (2 bytes) when <Variables::CompareName> looks a name up.
;;
;; <Operators::Power> counts its multiplications in it instead.
;; See: <Variables::CompareName>, <Display::PrintVariableName>, <Operators::Power>
;; Also: SRCH (IBSM)
SearchPointer = $D0

;; The tokenizer's syntax stack: <TokenIndex> as it was when each rule began, to back up to if the rule fails.
;;
;; Its first byte is also the high byte of <SearchPointer>.
;; See: <SyntaxStackHigh>, <TokenIndex>
;; Also: TOKNDXSTK (IBSM)
TokenIndexStack = $D1

;; A second 16-bit work location (2 bytes): <Operators::Power> keeps the number it multiplies by here.
;; See: <Operators::Power>
;; Also: SRCH2 (IBSM)
SearchPointer2 = $D2

;; The `IF` flag: bit 7 is set while the statement after a false `IF`'s `THEN` is being skipped.
;;
;; <Statements::If> sets it when the condition is 0. The interpreter (<Interpreter::RunLine::CheckSkipping>) then passes
;; over tokens until the next colon or the end of the line, and clears it there, so the statements after a colon run
;; whatever the condition was.
;; See: <Statements::If>, <Interpreter::RunLine>, <Interpreter::RunLine::CheckSkipping>
;; Also: IFFLAG (IBSM)
SkippingStatement = $D4

;; The carriage return flag: bit 7 is set when `PRINT` has printed something and still owes the line a return.
;;
;; Printing a number or a string sets it (<Statements::PrintNumber::NotNegative>,
;; <Statements::PrintString::SetReturnPending>); a semicolon or comma at the end of `PRINT` clears it
;; (<Statements::PrintSemicolonEnd>, <Statements::PrintCommaEnd>), and <Statements::Colon> prints the return at the end
;; of the statement while it is set.
;; See: <Statements::Colon>, <Statements::PrintNumber>, <Statements::PrintString>
;; Also: CRFLAG (IBSM)
ReturnPending = $D5

;; The token the interpreter is about to run (<Interpreter::RunLine::Arrive>), the operator whose priority decides what
;; runs first.
;;
;; `IF` stores the `THEN` token in it so a false condition skips the rest of the statement.
;; See: <Interpreter::RunLine::Arrive>, <Statements::If>
;; Also: VERBNOW (IBSM)
CurrentVerb = $D6

;; The priority of the token waiting to run, which <Interpreter::RunLine::Arrive> compares with the operators on the
;; stack.
;;
;; A left parenthesis and SCRN( set it to $FF (<Operators::LeftParenthesis>), above any operator's, so nothing waiting
;; before the parenthesis runs until the right parenthesis comes.
;; See: <Interpreter::RunLine::Arrive>, <Operators::LeftParenthesis>, <Verbs::Priorities>
;; Also: PRFLAG (IBSM)
VerbPriority = $D7

;; A place to keep X while a routine uses it: the noun stack index, around calls to the Monitor and while a routine
;; walks memory.
;;
;; <Variables::CompareName> also keeps whether a variable name ends in $ in bit 6 here.
;; Also: XSAVE (IBSM)
SavedX = $D8

;; The run flag: bit 7 is set while a program runs, clear for an immediate statement.
;;
;; <Lines::RunFromToken> sets it for each statement; errors (<ReportError>) and `END` check it.
;; See: <Lines::RunFromToken>, <ReportError>
;; Also: RUNFLAG (IBSM)
Running = $D9

;; A second 16-bit accumulator (2 bytes), the other operand of the arithmetic and a pointer for string work.
;; See: <Accumulator>, <Operators::Multiply>, <DivideWithRemainder>
;; Also: AUX (IBSM)
Auxiliary = $DA

;; The address of the line running (2 bytes): its length byte, from which the run loop steps to the next line.
;;
;; `GOSUB` and `FOR` save it, and errors and `TRACE` read the line number through it.
;; See: <Lines::RunFrom>, <TokenPointer>, <Statements::GoSub>, <Statements::For>
;; Also: PR (IBSM)
CurrentLine = $DC

;; The address of the token being run (2 bytes).
;;
;; <Interpreter::ReadNextByte> steps it through the line. `GOSUB` and `FOR` save it to come back to.
;; See: <Interpreter::ReadNextByte>, <CurrentLine>, <Lines::RunFromToken>
;; Also: PX (IBSM)
TokenPointer = $E0

;; A work pointer (2 bytes): the next byte to list (<Lister::FetchByte>), and the place to delete from when a line is
;; replaced.
;; See: <Lister::FetchByte>, <Editor::DeleteLine>
;; Also: P1 (IBSM)
Pointer1 = $E2

;; A work pointer (2 bytes): the line found by <FindLine>, the new start of the program while lines move, and the
;; listed token's flags.
;; See: <FindLine>, <Editor::CloseGap>
;; Also: P2 (IBSM)
Pointer2 = $E4

;; A work pointer (2 bytes): where <FindLine> searches from, the end of a range to list or delete, and a remainder in
;; division.
;; See: <FindLine>, <Statements::ListComma>, <DivideWithRemainder>
;; Also: P3 (IBSM)
Pointer3 = $E6

;; The tokenizer's index of the last token it has written in <InputBuffer>.
;;
;; The tokens go into <InputBuffer> after the line's text: <Editor::ReadLine> sets it to the length of the line, and
;; <Tokenizer::PutToken> adds each token after it. A line that fills the buffer is TOO LONG.
;; See: <TextIndex>, <Tokenizer::PutToken>, <TokenIndexStack>
;; Also: TOKNDX (IBSM)
TokenIndex = $F1

;; A 16-bit number (2 bytes) being built from a constant's digits by the tokenizer (<Tokenizer::RuleMatched>), or
;; printed in decimal by <PrintDecimal>.
;; See: <PrintDecimal>, <Tokenizer::RuleMatched>
;; Also: PCON (IBSM)
DecimalNumber = $F2

;; The step between line numbers in `AUTO` mode (2 bytes), 10 unless `AUTO` gives one.
;; See: <Statements::Auto>, <Statements::AutoComma>, <AutoLine>
;; Also: AUTOINC (IBSM)
AutoIncrement = $F4

;; The next line number `AUTO` offers (2 bytes).
;; See: <Statements::Auto>, <AutoIncrement>, <WarmStart>
;; Also: AUTOLN (IBSM)
AutoLine = $F6

;; The `AUTO` flag: bit 7 is set in `AUTO` mode, when the prompt offers the next line number.
;;
;; <Statements::Auto> sets it; `MAN` (<Statements::Man>) and <Statements::New> clear it.
;; See: <Statements::Auto>, <Statements::Man>
;; Also: AUTOFLAG (IBSM)
AutoNumbering = $F8

;; A character, or a count: the digit <PrintDecimal> is about to print, or the loop count of the tokenizer's multiply by
;; 10.
;; See: <PrintDecimal>, <Tokenizer::RuleMatched>
;; Also: CHAR (IBSM)
DigitCharacter = $F9

;; What <PrintDecimal> prints for a leading zero: 0 prints nothing, $A0 a blank.
;;
;; The lister sets it to a blank so that line numbers line up; the prompt sets it to 0.
;; See: <PrintDecimal>, <Lister::PrintLine>
;; Also: LEADZR (IBSM)
LeadingZero = $FA

;; The number of `FOR` loops active, 0 to 16: an index into the `FOR` stack in page 1.
;; See: <Statements::For>, <Statements::Next>, <ForVariableLow>
;; Also: FORNDX (IBSM)
ForIndex = $FB

;; The number of GOSUBs active, 0 to 16: an index into the `GOSUB` stack in page 1.
;; See: <Statements::GoSub>, <Statements::Return>, <GoSubTokenLow>
;; Also: GOSUBNDX (IBSM)
GoSubIndex = $FC

;; The tokenizer's syntax stack index: the frame of the rule being matched, from $20 down.
;; See: <SyntaxStackHigh>, <Tokenizer::MatchItem>
;; Also: SYNSTKDX (IBSM)
SyntaxStackIndex = $FD

;; A pointer into the syntax table (2 bytes): its low byte is always 0 (<Statements::Clr> clears it), and its high byte
;; selects the page, $EC or $ED. Y is the place in that page.
;; See: <Syntax::Table>, <Tokenizer::StartRule>
;; Also: SYNPAG (IBSM)
SyntaxPage = $FE

; Page 1 below the 6502's stack, where `GOSUB` and `FOR` keep their state: 16 entries in each 16-byte column, indexed by
; GoSubIndex or ForIndex. Integer BASIC starts the 6502's stack at $01FF, and it does not grow down this far.
;; The `GOSUB` stack's return token addresses, low bytes: <TokenPointer> at each `GOSUB`.
;;
;; <GoSubTokenHigh> holds the high bytes, and <GoSubLineLow> and <GoSubLineHigh> the line (<CurrentLine>) to return to.
;; See: <Statements::GoSub>, <Statements::Return>, <GoSubIndex>
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
;; Each `FOR` keeps one entry across the columns from here: its variable's address (<ForVariableLow>,
;; <ForVariableHigh>), its step (<ForStepLow>, <ForStepHigh>), the line and token after the `FOR` to loop back to
;; (<ForLineLow> to <ForTokenHigh>) and its limit (<ForLimitLow>, <ForLimitHigh>).
;; See: <Statements::For>, <Statements::To>, <Statements::Step>, <Statements::Next>, <ForIndex>
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
