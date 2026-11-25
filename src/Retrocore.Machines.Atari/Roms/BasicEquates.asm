;; ATARI BASIC EQUATES: BASIC'S RAM, ITS TOKENS AND ITS CODES
;;
;; What Atari BASIC (rev. C) keeps in RAM: its zero page from $80 to $CA, with the pointers to the program's tables
;; that Atari's manuals name, and the working bytes of the line editor, the syntax checker, the expression evaluator
;; and the statements; the syntax checker's stack in page four; and the parts of the floating point package's line
;; buffer (LBUFF) that SAVE, LOAD and CHR$ borrow. Then the values every part of BASIC shares: the tokens of the
;; statements, operators and functions, the codes of the syntax tables, the bits of a variable's type, the sizes of
;; the run-time stack's entries, and the error numbers.
;;
;; The names of the pointers LOMEM to STOPLN, ERRSAV and PTABW follow Atari's BASIC Reference Manual and De Re
;; Atari; Atari calls the pointer at $90 MEMTOP, which here is BASIC_MEMTOP, as the OS's MEMTOP is at $02E5. The
;; others are named for what BASIC keeps in them. Many working bytes serve the line editor while a line is entered
;; and something else while a program runs; where the two uses have nothing to do with each other, each has its own
;; name at the same address. A pointer or a line number is two bytes, low byte first, named by its first byte.

; ---------------------------------------------------------------------------------------------------------------------
; The program's tables, $80-$91
; ---------------------------------------------------------------------------------------------------------------------

; The tables lie in this order from MEMLO up, each pointer the start of its table and the end of the one before. SAVE
; writes LOMEM to STARP less LOMEM, LOAD adds MEMLO back, and the memory mover moves each pointer from the one that
; grows up to BASIC_MEMTOP.

LOMEM = $80                         ;; the token output buffer, 256 bytes at MEMLO; the expression stacks while running
VNTP = $82                          ;; the variable name table (2 bytes)
VNTD = $84                          ;; the end of the variable name table, its dummy zero byte (2 bytes)
VVTP = $86                          ;; the variable value table, eight bytes for each variable (2 bytes)
STMTAB = $88                        ;; the statement table: the program's lines, then the immediate line (2 bytes)
STMCUR = $8A                        ;; the line being entered or run, within the statement table (2 bytes)
STARP = $8C                         ;; the string and array area (2 bytes)
RUNSTK = $8E                        ;; the run-time stack of GOSUB and FOR entries (2 bytes)
BASIC_MEMTOP = $90                  ;; the end of the run-time stack and of BASIC's memory; Atari's MEMTOP (2 bytes)

; ---------------------------------------------------------------------------------------------------------------------
; The line editor and the syntax checker
; ---------------------------------------------------------------------------------------------------------------------

EOL_PATCHED = $92                   ;; nonzero while a string's following byte is replaced by an EOL, to restore it
TOKEN_INDEX = $94                   ;; the index in the token output buffer of the next token to write
PRINT_COLUMN = $94                  ;; the characters this PRINT has written, for its commas' tab stops
NAME_POINTER = $95                  ;; the name table entry being searched or printed (2 bytes)
POKE_ADDRESS = $95                  ;; POKE's address (2 bytes)

;; The space the memory mover has just opened, which was where the table it grew began (2 bytes).
NEW_SPACE = $97

SECOND_INDEX = $97                  ;; an array's second subscript, a substring's last index or DIM's second size
PATCHED_CHARACTER = $97             ;; the byte that EOL_PATCHED's EOL replaced
PATCHED_INDEX = $98                 ;; where that byte is, from the string's start
MOVE_FROM = $99                     ;; the memory mover's source (2 bytes)
MOVE_TO = $9B                       ;; the memory mover's destination (2 bytes)
SYNTAX_POINTER = $9D                ;; the syntax checker's place in the syntax tables (2 bytes)
VARIABLE_ENTRY = $9D                ;; the variable value table's entry of the variable being read or written (2 bytes)
ERROR_INDEX = $9F                   ;; the furthest index in the input line that the syntax checker reached
LINE_LENGTH = $9F                   ;; while running: the length of the line at STMCUR, the offset of the next line
LINE_NUMBER = $A0                   ;; the line number being entered, or searched for (2 bytes)
MOVE_LENGTH = $A2                   ;; the length of the memory the mover moves, or of a string being assigned (2 bytes)
SPACE_SIZE = $A4                    ;; how many bytes the memory mover opens or closes (2 bytes)

;; The line editor's flags for the line: bit 7 set for an immediate line, without a line number, and bit 6 set
;; when the syntax checker found an error, so that the line is stored with the error token.
EDIT_FLAGS = $A6

EDIT_ERROR = %01000000              ;; EDIT_FLAGS: the syntax checker found an error in the line

READ_FLAG = $A6                     ;; READ_FROM_DATA set while READ takes its values from DATA, clear while INPUT does
READ_FROM_DATA = %01000000          ;; READ_FLAG: READ is reading DATA

;; The offset in the line of the next statement: while running, of the statement after the one being run; while
;; tokenizing, of the byte that will hold that offset.
NEXT_STATEMENT = $A7

STATEMENT_START = $A8               ;; the index in the input line of the line's first statement, after its number
TOKEN_OFFSET = $A8                  ;; while running: the offset in the line at STMCUR of the next token to read
SYNTAX_STACK_INDEX = $A9            ;; the syntax checker's stack's top entry, from SYNTAX_STACK, four bytes each
OPERATOR_INDEX = $A9                ;; the operator stack's top, from LOMEM+$FF down
NAME_OFFSET = $AA                   ;; the offset of a name in each entry of the name table being searched or listed
ARGUMENT_INDEX = $AA                ;; the argument stack's top entry, from LOMEM up, eight bytes each
STRING_LENGTH_INDEX = $AB           ;; the index in the token output buffer of a string constant's length byte
OPERATOR_TOKEN = $AB                ;; the operator just read from the expression, before it goes on the stack
NAME_START = $AC                    ;; the index in the input line of the name or number being tokenized
INCOMING_PRECEDENCE = $AC           ;; that operator's precedence when it comes to the stack, from the high nibble
SAVED_VNTD = $AD                    ;; VNTD at the start of the line, to take its new variables out again (2 bytes)
LIST_LAST_LINE = $AD                ;; the last line LIST lists (2 bytes)

;; The entry number of the name that a name table search matched (the statement's token, an operator's less $10 or
;; a variable's number), or the entry the lister looks for.
ENTRY_NUMBER = $AF

TAB_STOP = $AF                      ;; PRINT's next tab stop, a multiple of PTABW
LIST_COUNT = $AF                    ;; the lister's index into a name, or the characters of a string constant left
SAVED_ARGUMENT = $AF                ;; the argument stack's index before an assignment's target array element
OPERATOR_FOUND = $B0                ;; the operator token that matched the input, compared with what the syntax wants
COMMA_COUNT = $B0                   ;; the commas counted in an array's subscripts or a function's arguments
NEW_VARIABLES = $B1                 ;; how many variables the line being tokenized added to the tables

;; The assignment's flags: bit 7 set when the expression's last array element or substring is the target of an
;; assignment, and bit 6 set for DIM. The substring routine sets bit 0 when a substring has its last index, which
;; string assignment shifts to bit 1.
ASSIGN_FLAGS = $B1

OPERATOR_END = $B2                  ;; the index in the input line after the operator that matched
RETURN_OFFSET = $B2                 ;; the offset in its line of the statement a popped run-time stack entry came from
OPERATOR_SEARCHED = $B3             ;; the input line's index where the operator table was last searched
STATEMENT_OFFSET = $B3              ;; the offset just after the current statement's token, for a run-time stack entry
ON_COUNT = $B3                      ;; ON's count of line numbers left to skip

; ---------------------------------------------------------------------------------------------------------------------
; The program's state while it runs
; ---------------------------------------------------------------------------------------------------------------------

INPUT_IOCB = $B4                    ;; the IOCB INPUT and the line editor read: 0, INPUT's #, or 7 for ENTER
OUTPUT_IOCB = $B5                   ;; the IOCB PRINT and LIST write: 0, PRINT's #, or 7 for LPRINT and LIST to a file
DATA_ELEMENT = $B6                  ;; the next DATA element READ reads, counted in its line
DATA_LINE = $B7                     ;; the line READ reads DATA from, 0 for the program's first (2 bytes)
ERROR_NUMBER = $B9                  ;; the error being reported, or 0
STOPLN = $BA                        ;; the line where the program stopped, by STOP, END, BREAK or an error (2 bytes)

;; TRAP's line, where an error goes; the high byte has bit 7 set when no TRAP is set, which BASIC makes $80 once
;; the trap is taken (2 bytes).
TRAP_LINE = $BC

TRAP_OFF = $80                      ;; TRAP_LINE+1 once a trap is taken, or with no TRAP set

STMCUR_SAVE = $BE                   ;; STMCUR before a line search, to go back to after it fails (2 bytes)
IO_COMMAND = $C0                    ;; the CIO command for the next call
IOCB_NUMBER = $C1                   ;; the IOCB being used, 0-7
PROMPT = $C2                        ;; the prompt INPUT prints, "?"; $5D while the line editor reads a line
ERRSAV = $C3                        ;; the number of the error that TRAP caught, for PEEK(195)

RADFLG = DEGFLG                     ;; the reference manual's name for DEGFLG, which DEG and RAD set
DEGFLG_RADIANS = 0                  ;; DEGFLG for radians, as RAD and the cold start set it
DEGFLG_DEGREES = 6                  ;; DEGFLG for degrees: the offset of the degree constants after the radian ones
RUNSTACK_ENTRY = $C4                ;; the run-time stack's entry being pushed or popped (2 bytes)
LOOP_COUNT = $C6                    ;; a count: USR's arguments left to push, or a value's bytes left to copy
FOR_VARIABLE = $C7                  ;; the variable token whose FOR entry NEXT and FOR look for on the run-time stack
PLOT_COLOR = $C8                    ;; the colour COLOR set, which PLOT and DRAWTO draw with
PTABW = $C9                         ;; the width of PRINT's tab stops for commas, 10 from the cold start
LOAD_FLAG = $CA                     ;; nonzero while LOAD reads a program, so that SYSTEM RESET or BREAK starts cold

; The value of a variable, a constant or an expression's result is eight bytes, as in the variable value table and
; on the argument stack: its type and variable number here, then FR0's six bytes.

VALUE_TYPE = $D2                    ;; the value's type and state, the VALUE_ bits
VALUE_NUMBER = $D3                  ;; the variable number the value came from

; ---------------------------------------------------------------------------------------------------------------------
; Pages four and five
; ---------------------------------------------------------------------------------------------------------------------

;; The syntax checker's stack, 64 entries of four bytes, $0480-$057F: each holds the input line's index, the token
;; output buffer's index, which an alternative starts again from, and the caller's place in the syntax tables (2 bytes),
;; to go back to when the rule ends, whether it matched or not. The index wraps to 0
;; when it overflows, and the line is too long.
SYNTAX_STACK = $0480

SYNTAX_STACK_INPUT = $0480          ;; an entry's index in the input line
SYNTAX_STACK_OUTPUT = $0481         ;; an entry's index in the token output buffer
SYNTAX_STACK_RULE = $0482           ;; an entry's caller's place in the syntax tables, less 1 (2 bytes)

;; Where SAVE writes and LOAD reads the program's header in LBUFF: LOMEM to STARP less LOMEM, 14 bytes. The code
;; reaches it indexed by the pointer's own address, as SAVE_HEADER-LOMEM,X.
SAVE_HEADER = $0580

CHR_BUFFER = $05C0                  ;; the one character CHR$ returns, in the upper half of LBUFF

; ---------------------------------------------------------------------------------------------------------------------
; Sizes
; ---------------------------------------------------------------------------------------------------------------------

TOKEN_BUFFER_SIZE = 256             ;; the token output buffer's size, and the longest tokenized line
VARIABLE_COUNT = 128                ;; the most variables a program can have
VALUE_SIZE = 8                      ;; a variable value table entry, or an argument stack entry
SYNTAX_STACK_ENTRY = 4              ;; a syntax stack entry
RUNSTACK_HEADER = 4                 ;; a run-time stack entry's header: the token, the line number and the offset
FOR_VALUES = 12                     ;; a FOR entry's limit and step, below its header
FOR_LIMIT = 0                       ;; a FOR entry's limit, from the start of its values
FOR_STEP = 6                        ;; a FOR entry's step, from the start of its values
RUNSTACK_GOSUB = 0                  ;; a GOSUB entry's token; a FOR entry's is its variable's token, never 0
RUNSTACK_OFFSET = 3                 ;; the header's byte with the statement's offset in its line
VALUE_OFFSET = 2                    ;; a variable value table entry's value, after its type and number
STATEMENT_NAME_OFFSET = 2           ;; a statement name table entry's name, after its rule's address
SAVE_HEADER_SIZE = 14               ;; the header SAVE writes before the tables
PROMPT_EDITOR = $5D                 ;; PROMPT while the line editor reads, so that the end of ENTER's file ends ENTER
FILE_IOCB = 7                       ;; the IOCB for LOAD, SAVE, ENTER, LIST to a device, LPRINT and the cassette
SCREEN_IOCB = 6                     ;; the IOCB for GRAPHICS, PLOT, DRAWTO, POSITION and LOCATE

; ---------------------------------------------------------------------------------------------------------------------
; A line's format
; ---------------------------------------------------------------------------------------------------------------------

; A tokenized line is its line number (2 bytes), its length, then each statement: the offset of the next statement,
; the statement's token and the rest of its tokens, ending with TOKEN_STATEMENT_END or, for the last, TOKEN_LINE_END.

LINE_NUMBER_OFFSET = 0              ;; the line number's offset in a line
LINE_LENGTH_OFFSET = 2              ;; the line's length's offset
FIRST_STATEMENT_OFFSET = 3          ;; the first statement's offset
IMMEDIATE_LINE = $8000              ;; the immediate line's number, after every program line

; ---------------------------------------------------------------------------------------------------------------------
; The tokens
; ---------------------------------------------------------------------------------------------------------------------

; The statements, $00-$37, in the order of the statement name table and the statement execution table.

TOKEN_REM = $00
TOKEN_DATA = $01
TOKEN_INPUT = $02
TOKEN_COLOR = $03
TOKEN_LIST = $04
TOKEN_ENTER = $05
TOKEN_LET = $06
TOKEN_IF = $07
TOKEN_FOR = $08
TOKEN_NEXT = $09
TOKEN_GOTO = $0A
TOKEN_GO_TO = $0B
TOKEN_GOSUB = $0C
TOKEN_TRAP = $0D
TOKEN_BYE = $0E
TOKEN_CONT = $0F
TOKEN_COM = $10
TOKEN_CLOSE = $11
TOKEN_CLR = $12
TOKEN_DEG = $13
TOKEN_DIM = $14
TOKEN_END = $15
TOKEN_NEW = $16
TOKEN_OPEN = $17
TOKEN_LOAD = $18
TOKEN_SAVE = $19
TOKEN_STATUS = $1A
TOKEN_NOTE = $1B
TOKEN_POINT = $1C
TOKEN_XIO = $1D
TOKEN_ON = $1E
TOKEN_POKE = $1F
TOKEN_PRINT = $20
TOKEN_RAD = $21
TOKEN_READ = $22
TOKEN_RESTORE = $23
TOKEN_RETURN = $24
TOKEN_RUN = $25
TOKEN_STOP = $26
TOKEN_POP = $27
TOKEN_QUESTION = $28                ;; ?, the short form of PRINT
TOKEN_GET = $29
TOKEN_PUT = $2A
TOKEN_GRAPHICS = $2B
TOKEN_PLOT = $2C
TOKEN_POSITION = $2D
TOKEN_DOS = $2E
TOKEN_DRAWTO = $2F
TOKEN_SETCOLOR = $30
TOKEN_LOCATE = $31
TOKEN_SOUND = $32
TOKEN_LPRINT = $33
TOKEN_CSAVE = $34
TOKEN_CLOAD = $35
TOKEN_IMPLIED_LET = $36             ;; an assignment without LET, which lists without a name
TOKEN_ERROR = $37                   ;; a line with a syntax error, its text kept as typed after this token
STATEMENT_COUNT = $38               ;; how many statements there are

; The operators, $0E-$3C. $0E and $0F introduce constants; from $10 each is its entry in the operator name table,
; from OPERATOR_NAMES_FIRST; from $1D each has an entry in the operator execution table, and a precedence.

TOKEN_NUMBER = $0E                  ;; a numeric constant: the token, then six bytes of floating point
TOKEN_STRING = $0F                  ;; a string constant: the token, its length, then its characters
OP_QUOTE = $10                      ;; unused in lines: the operator name table's first entry, a placeholder
OP_SENTINEL = $11                   ;; unnamed: the bottom of the operator stack, of the lowest precedence
OP_COMMA = $12                      ;; , between items
OP_DOLLAR = $13                     ;; $, of a string variable's name
TOKEN_STATEMENT_END = $14           ;; :, the end of a statement
OP_SEMICOLON = $15                  ;; ;
TOKEN_LINE_END = $16                ;; the end of the line, which lists as nothing
OP_GOTO = $17                       ;; GOTO, in ON
OP_GOSUB = $18                      ;; GOSUB, in ON
OP_TO = $19                         ;; TO, in FOR
OP_STEP = $1A                       ;; STEP, in FOR
OP_THEN = $1B                       ;; THEN, in IF
OP_HASH = $1C                       ;; #, before an IOCB number
OP_LE = $1D                         ;; <=, comparing numbers
OP_NE = $1E                         ;; <>
OP_GE = $1F                         ;; >=
OP_LT = $20                         ;; <
OP_GT = $21                         ;; >
OP_EQ = $22                         ;; =
OP_POWER = $23                      ;; ^
OP_MULTIPLY = $24                   ;; *
OP_ADD = $25                        ;; +
OP_SUBTRACT = $26                   ;; -
OP_DIVIDE = $27                     ;; /
OP_NOT = $28                        ;; NOT
OP_OR = $29                         ;; OR
OP_AND = $2A                        ;; AND
OP_OPEN_PAREN = $2B                 ;; ( in an expression
OP_CLOSE_PAREN = $2C                ;; )
OP_ASSIGN_NUMBER = $2D              ;; = assigning a number
OP_ASSIGN_STRING = $2E              ;; = assigning a string
OP_STRING_LE = $2F                  ;; <=, comparing strings
OP_STRING_NE = $30                  ;; <>
OP_STRING_GE = $31                  ;; >=
OP_STRING_LT = $32                  ;; <
OP_STRING_GT = $33                  ;; >
OP_STRING_EQ = $34                  ;; =
OP_PLUS = $35                       ;; unary +
OP_MINUS = $36                      ;; unary -
OP_STRING_PAREN = $37               ;; ( after a string variable, for a substring
OP_ARRAY_PAREN = $38                ;; ( after an array variable, which lists as nothing as the name has it
OP_DIM_ARRAY_PAREN = $39            ;; ( after an array variable in DIM or COM, which lists as nothing
OP_FUNCTION_PAREN = $3A             ;; ( after a function's name
OP_DIM_STRING_PAREN = $3B           ;; ( after a string variable in DIM or COM
OP_ARRAY_COMMA = $3C                ;; , between an array's subscripts or a function's arguments
OPERATOR_NAMES_FIRST = $10          ;; the token of the operator name table's first entry
FIRST_EXECUTED = OP_LE              ;; the token of the operator execution table's first entry

; The functions, $3D-$54, from the operator name table's end; from FN_ATN each takes one number.

FN_STR = $3D                        ;; STR$
FN_CHR = $3E                        ;; CHR$
FN_USR = $3F
FN_ASC = $40
FN_VAL = $41
FN_LEN = $42
FN_ADR = $43
FN_ATN = $44
FN_COS = $45
FN_PEEK = $46
FN_SIN = $47
FN_RND = $48
FN_FRE = $49
FN_EXP = $4A
FN_LOG = $4B
FN_CLOG = $4C
FN_SQR = $4D
FN_SGN = $4E
FN_ABS = $4F
FN_INT = $50
FN_PADDLE = $51
FN_STICK = $52
FN_PTRIG = $53
FN_STRIG = $54

TOKEN_VARIABLE = %10000000          ;; set in a variable's token, with its number in bits 0-6
NAME_END = %10000000                ;; set in a name's last character, in every name table

; ---------------------------------------------------------------------------------------------------------------------
; A value's type, in VALUE_TYPE and the first byte of each variable value table entry
; ---------------------------------------------------------------------------------------------------------------------

; A number is 0. An array's or a string's entry holds its data's offset from STARP (2 bytes), then an array's two
; sizes plus 1, or a string's length and size.

VALUE_STRING = %10000000            ;; a string
VALUE_ARRAY = %01000000             ;; an array
VALUE_ABSOLUTE = %00000010          ;; the address is absolute, STARP added (only while evaluating)
VALUE_DIMENSIONED = %00000001       ;; the array or string has been DIMensioned

; ---------------------------------------------------------------------------------------------------------------------
; The syntax tables' codes
; ---------------------------------------------------------------------------------------------------------------------

; Each rule is a list of codes that the syntax checker matches against the input, writing tokens as it goes. A code
; that fails abandons the rest of its alternative, going back to where it began. From $10 up a code is a token for
; the input to match, by the operator name table, and writes it.

SYNTAX_CALL = $00                   ;; match the rule at the following word plus 1, which is the rule's address less 1
SYNTAX_ROUTINE = $01                ;; call the routine at the following word plus 1; carry set when it fails
SYNTAX_OR = $02                     ;; the alternative matched, so the rule did; or the next alternative starts here
SYNTAX_RETURN = $03                 ;; the rule matched
SYNTAX_TOKEN = $0D                  ;; match the token in the next byte, from the input's current place
SYNTAX_EXPRESSION = $0E             ;; match an expression (any of $05-$0C and $0E does)
SYNTAX_REPLACE = $0F                ;; replace the token just written with the next byte
SYNTAX_RELATIVE = $80               ;; from here, match the rule at this code's address plus the code less SYNTAX_BIAS
SYNTAX_BIAS = $C0                   ;; so $C1 is the next code and $80 64 bytes back
SYNTAX_FIRST_TOKEN = $10            ;; the first code that is a token

; ---------------------------------------------------------------------------------------------------------------------
; The errors BASIC reports, in ERROR_NUMBER. From 128 up they are CIO's status codes.
; ---------------------------------------------------------------------------------------------------------------------

ERR_MEMORY = 2                      ;; memory insufficient
ERR_VALUE = 3                       ;; value error: a value out of range
ERR_TOO_MANY_VARIABLES = 4          ;; too many variables, more than 128
ERR_STRING_LENGTH = 5               ;; string length error: beyond the DIMensioned length
ERR_OUT_OF_DATA = 6                 ;; out of data
ERR_NUMBER_TOO_BIG = 7              ;; a number greater than 32767, or negative
ERR_INPUT = 8                       ;; input statement error: not a number for a numeric variable
ERR_DIM = 9                         ;; array or string DIM error
ERR_STACK_OVERFLOW = 10             ;; argument stack overflow
ERR_FP_OVERFLOW = 11                ;; floating point overflow or underflow
ERR_LINE_NOT_FOUND = 12             ;; line not found
ERR_NO_FOR = 13                     ;; no matching FOR statement
ERR_LINE_TOO_LONG = 14              ;; line too long
ERR_LINE_DELETED = 15               ;; GOSUB or FOR line deleted
ERR_RETURN = 16                     ;; RETURN error: no matching GOSUB
ERR_GARBAGE = 17                    ;; garbage error: running a line with a syntax error
ERR_INVALID_STRING = 18             ;; invalid string character, as in VAL
ERR_LOAD_TOO_LONG = 19              ;; LOAD program too long
ERR_DEVICE_NUMBER = 20              ;; device number larger than 7 or equal to 0
ERR_LOAD_FILE = 21                  ;; LOAD file error: not a saved program

; DOS's commands that NOTE and POINT send through CIO.

CNOTE = $26                         ;; NOTE: where the file is, in ICAX3-ICAX5
CPOINT = $25                        ;; POINT: move the file to ICAX3-ICAX5
CASSETTE_SHORT_GAPS = $80           ;; ICAX2 for the cassette: short gaps between records, as CSAVE and CLOAD use
