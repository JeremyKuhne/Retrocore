;; BBC BASIC EQUATES: ZERO PAGE, PAGES FOUR TO SEVEN, THE TOKENS AND THE ERRORS
;;
;; The RAM BBC BASIC keeps. The MOS gives the current language zero page &00-&8F and pages four to seven (&0400-&07FF);
;; BASIC uses &00-&4F of zero page as its registers and pointers, page four for the resident integer variables and
;; the heads of its variable lists, page five for the FOR, REPEAT and GOSUB stacks, page six for the string
;; accumulator and page seven for the line being typed. The program starts at PAGE; its variables grow up from LOMEM
;; on the heap, and BASIC's own stack grows down from HIMEM.
;;
;; Acorn published no names for this workspace. The names here are ours, after the terms of the BASIC ROM User Guide
;; (Mark Plumbley, Adder Publishing, 1984, https://archive.org/details/bbc-basic-rom-user-guide), which describes each
;; location in its section 3.3: IntA, FPA, FPB and StrA are its integer, floating point and string accumulators, and
;; PTRA and PTRB the two pointers into the text being run.

; ---------------------------------------------------------------------------------------------------------------------
; Zero page: the pointers and registers, &00-&4F
; ---------------------------------------------------------------------------------------------------------------------

LOMEM = $00                         ;; the start of the variables' heap, normally <TOP>
HEAP = $02                          ;; the top of the heap: the first free byte above the variables
BASIC_STACK = $04                   ;; BASIC's stack pointer: the last byte pushed, growing down from <HIMEM>
HIMEM = $06                         ;; the top of the memory BASIC uses; its stack starts here
ERL = $08                           ;; the number of the line the last error happened in

;; PTRA's offset: the position in the text at <PTR_A> that statements are read from.
;;
;; The interpreter reads a statement's keyword, and most statements their arguments, at PTR_A + PTR_A_OFFSET.
;; See: <PTR_A>, <PTR_B_OFFSET>
PTR_A_OFFSET = $0A

PTR_A = $0B                         ;; PTRA: the base of the text being run, a line of the program or the input line
RANDOM = $0D                        ;; RND's 33-bit random number, low byte first; bit 0 of &11 is its top bit
TOP = $12                           ;; the end of the program: the byte after its end marker
PRINT_FIELD_WIDTH = $14             ;; the width PRINT pads numbers to, from @%; printing a line number sets it to 5
PRINT_HEX = $15                     ;; bit 7 set while PRINT prints numbers in hexadecimal (~)
ON_ERROR = $16                      ;; the text ON ERROR runs: the default handler in the ROM, or a program's
PAGE_HIGH = $18                     ;; the high byte of PAGE, where the program starts; its low byte is always zero
PTR_B = $19                         ;; PTRB: the base of the text expressions are read from
PTR_B_OFFSET = $1B                  ;; PTRB's offset: the position in the text at <PTR_B> expressions are read from
;; READ's pointer into the program: where it looks for the next DATA item.
;;
;; After a READ it points at the comma or carriage return that ended the item read; after RESTORE, at PAGE or at
;; the start of the line RESTORE named.
DATA_POINTER = $1C

COUNT = $1E                         ;; COUNT: the characters printed since the last new line

;; LISTO's option: which spaces LIST adds.
;;
;; Bit 0 adds a space after each line number, bit 1 indents the lines inside FOR loops, and bit 2 the lines inside
;; REPEAT loops.
LISTO = $1F

TRACE_FLAG = $20                    ;; &FF while TRACE is on, &00 while it is off
TRACE_LIMIT = $21                   ;; TRACE's limit: line numbers from it up are not printed
WIDTH = $23                         ;; WIDTH: the line length PRINT wraps at, or &FF for no wrapping
REPEAT_LEVEL = $24                  ;; the number of REPEAT loops open, the index into the REPEAT stack
GOSUB_LEVEL = $25                   ;; the number of GOSUBs not yet returned from, the index into the GOSUB stack
FOR_LEVEL = $26                     ;; the size of the FOR stack in bytes: 15 for each FOR loop open

;; The type of the value in the accumulators: &00 for a string, &40 for an integer, &FF for a real.
;;
;; The expression evaluator returns the type in A as well, and sets this byte so that a routine called later knows
;; which accumulator holds the value. Routines also keep other things here for a while: the evaluator the next
;; operator across a call, a FN or PROC call its token, and NUMBER_TO_STRING the rounding byte of FPA.
EXPRESSION_TYPE = $27

;; OPT: the assembler's options.
;;
;; Bit 0 lists the code as it is assembled, bit 1 reports errors, and bit 2 (BASIC II) puts the code at O% instead
;; of P%, so that it can be assembled in one place to run in another. While bit 1 is clear, an unknown variable reads
;; as the value of P%, so a first pass can run before the labels it uses are set.
OPT = $28

OPCODE = $29                        ;; the opcode the assembler is building
OPERAND = $2A                       ;; the assembler's operand, low byte first, shared with <INT_A>

;; IntA: the integer accumulator, four bytes, low byte first.
;;
;; Integer results and arguments pass through it. When BASIC handles a variable, its low three bytes are the
;; variable's descriptor instead: the address of its value (&2A-&2B) and its type (&2C).
INT_A = $2A

;; FPA: the floating point accumulator, eight bytes.
;;
;; A real number loaded from memory is unpacked into it: the sign in its own byte, a two-byte exponent offset by &80
;; (the high byte, &2F, holds overflow during a calculation), and a mantissa of five bytes, the top bit of its first
;; byte set and its last byte kept for rounding. Packed in memory, a real number takes five bytes: the exponent, then
;; four bytes of mantissa, most significant first, whose top bit is the sign.
;; See: <FP_B>, <INT_A>
FP_A = $2E

FP_A_SIGN = FP_A                    ;; FPA's sign: bit 7 set when negative
FP_A_OVERFLOW = FP_A + 1            ;; FPA's exponent overflow: the high byte of its exponent during a calculation
FP_A_EXPONENT = FP_A + 2            ;; FPA's exponent, offset by &80; zero when FPA is zero
FP_A_MANTISSA = FP_A + 3            ;; FPA's mantissa, four bytes, most significant first
FP_A_ROUNDING = FP_A + 7            ;; FPA's fifth mantissa byte, kept for rounding

STRING_LENGTH = $36                 ;; StrA's length: the number of characters at <STRING_BUFFER>

; The multi-purpose workspace, &37-&4E. Its uses overlap; each routine says which it uses.

WORK = $37                          ;; a pointer and work bytes the routines share, &37-&3A

;; FPB: the second floating point accumulator, eight bytes laid out as <FP_A>.
;;
;; Outside the floating point routines its bytes are more work bytes, and the parts name what they keep there: the
;; tokeniser's two flags in &3B and &3C, a pointer in &3A-&3B for walking the variable lists, and <FIND_LINE>'s
;; result, the address of the line it found, in &3D-&3E.
FP_B = $3B

FP_B_SIGN = FP_B                    ;; FPB's sign: bit 7 set when negative
FP_B_OVERFLOW = FP_B + 1            ;; FPB's exponent overflow
FP_B_EXPONENT = FP_B + 2            ;; FPB's exponent, offset by &80
FP_B_MANTISSA = FP_B + 3            ;; FPB's mantissa, four bytes, most significant first
FP_B_ROUNDING = FP_B + 7            ;; FPB's fifth mantissa byte
FP_WORK = $43                       ;; the floating point routines' work bytes, &43-&4A
FP_POINTER = $4B                    ;; a pointer to a packed real number the floating point routines load or store
SERIES_POINTER = $4D                ;; <EVALUATE_CONTINUED_FRACTION>'s pointer to its table of coefficients

; ---------------------------------------------------------------------------------------------------------------------
; Page four: the resident integers and the variable lists
; ---------------------------------------------------------------------------------------------------------------------

;; The resident integer variables, four bytes each: @% at &0400, then A% to Z%.
;;
;; A% to Z% survive NEW, RUN and BREAK, since BASIC clears only the heap. @%, PRINT's number format, survives NEW
;; and RUN, but BASIC sets it back to &0000090A when it starts again after BREAK.
RESIDENT_INTEGERS = $0400

AT_PERCENT = RESIDENT_INTEGERS      ;; @%: PRINT's number format and field width
A_PERCENT = $0404                   ;; A%: CALL and USR load A from its low byte
C_PERCENT = $040C                   ;; C%: CALL and USR load the carry from its bit 0
O_PERCENT = $043C                   ;; O%: where the assembler puts the code when OPT bit 2 is set
P_PERCENT = $0440                   ;; P%: the address the assembler is assembling for
X_PERCENT = $0460                   ;; X%: CALL and USR load X from its low byte
Y_PERCENT = $0464                   ;; Y%: CALL and USR load Y from its low byte
FP_TEMP_1 = $046C                   ;; a packed real number the floating point routines keep
FP_TEMP_2 = $0471                   ;; a second packed real number the floating point routines keep
FP_TEMP_3 = $0476                   ;; a third packed real number the floating point routines keep
FP_TEMP_4 = $047B                   ;; a fourth packed real number the floating point routines keep

;; The heads of the variable lists, a word for each character a name can start with, from &40 (@) to &7A (z).
;;
;; Each list links the variables whose names start with that character, in the order they were made. The words
;; for the characters a name cannot start with are not used, and two of them hold the PROC and FN lists.
;; See: <PROC_LIST>, <FN_LIST>
VARIABLE_LISTS = $0480

PROC_LIST = $04F6                   ;; the head of the list of PROCs found so far
FN_LIST = $04F8                     ;; the head of the list of FNs found so far

; ---------------------------------------------------------------------------------------------------------------------
; Page five: the control stacks
; ---------------------------------------------------------------------------------------------------------------------

;; The FOR stack: 15 bytes for each open FOR loop, ten at most.
;;
;; Each entry holds the control variable's address and type (3 bytes), the STEP (5), the limit (5) and the address
;; in the program to loop back to (2). <FOR_LEVEL> is the offset of the next free entry.
FOR_STACK = $0500

REPEAT_STACK_LOW = $05A4            ;; the low bytes of the addresses UNTIL loops back to, 20 at most
REPEAT_STACK_HIGH = $05B8           ;; the high bytes of the addresses UNTIL loops back to
GOSUB_STACK_LOW = $05CC             ;; the low bytes of the addresses RETURN returns to, 26 at most
GOSUB_STACK_HIGH = $05E6            ;; the high bytes of the addresses RETURN returns to

; ---------------------------------------------------------------------------------------------------------------------
; Pages six and seven: the string accumulator and the input line
; ---------------------------------------------------------------------------------------------------------------------

STRING_BUFFER = $0600               ;; StrA: the string accumulator's characters, <STRING_LENGTH> of them
LINE_BUFFER = $0700                 ;; the line being typed or read, ending with a carriage return

; ---------------------------------------------------------------------------------------------------------------------
; Values the parts share
; ---------------------------------------------------------------------------------------------------------------------

CARRIAGE_RETURN = $0D               ;; the carriage return that ends a typed line, a line of the program and a $ string

TYPE_STRING = $00                   ;; <EXPRESSION_TYPE> for a string, in StrA
TYPE_INTEGER = $40                  ;; <EXPRESSION_TYPE> for an integer, in IntA
TYPE_REAL = $FF                     ;; <EXPRESSION_TYPE> for a real number, in FPA

; The types in a variable's descriptor (INT_A+2), which say how its value is stored. A number's type is also its size.

VARIABLE_BYTE = $00                 ;; a byte, from the ? indirection
VARIABLE_INTEGER = $04              ;; a four-byte integer: an integer variable, or the ! indirection
VARIABLE_REAL = $05                 ;; a five-byte packed real
VARIABLE_STRING_AT = $80            ;; a string at an address, ending with a carriage return, from the $ indirection
VARIABLE_STRING = $81               ;; a string variable: its value is the string's information block

;; The lowest 6502 stack pointer that leaves a FN or PROC's frame in place.
;;
;; A FN or PROC call moves the 6502 stack's contents to BASIC's stack and starts the 6502 stack again at &01FF with
;; its own frame: the call's token at &01FF, then PTRA, the count of LOCAL variables, PTRB and a return address. A
;; stack pointer of &FC or more means there is no such frame.
FN_PROC_STACK_LIMIT = $FC

; ---------------------------------------------------------------------------------------------------------------------
; The tokens: each keyword is stored in a program as one byte, &80-&FF
; ---------------------------------------------------------------------------------------------------------------------

; The keyword table in Keywords.asm gives each keyword its token. PTR, PAGE, TIME, LOMEM and HIMEM have two: one as a
; function, and one, &40 higher, at the start of a statement, where they are assigned to.

TOKEN_AND = $80                     ;; the token for AND
TOKEN_DIV = $81                     ;; the token for DIV
TOKEN_EOR = $82                     ;; the token for EOR
TOKEN_MOD = $83                     ;; the token for MOD
TOKEN_OR = $84                      ;; the token for OR
TOKEN_ERROR = $85                   ;; the token for ERROR
TOKEN_LINE = $86                    ;; the token for LINE
TOKEN_OFF = $87                     ;; the token for OFF
TOKEN_STEP = $88                    ;; the token for STEP
TOKEN_SPC = $89                     ;; the token for SPC
TOKEN_TAB = $8A                     ;; the token for TAB(
TOKEN_ELSE = $8B                    ;; the token for ELSE
TOKEN_THEN = $8C                    ;; the token for THEN
TOKEN_LINE_NUMBER = $8D             ;; the line number that follows, packed in three bytes
TOKEN_OPENIN = $8E                  ;; the token for OPENIN
TOKEN_PTR = $8F                     ;; the token for PTR, as a function
TOKEN_PAGE = $90                    ;; the token for PAGE, as a function
TOKEN_TIME = $91                    ;; the token for TIME, as a function
TOKEN_LOMEM = $92                   ;; the token for LOMEM, as a function
TOKEN_HIMEM = $93                   ;; the token for HIMEM, as a function
TOKEN_ABS = $94                     ;; the token for ABS
TOKEN_ACS = $95                     ;; the token for ACS
TOKEN_ADVAL = $96                   ;; the token for ADVAL
TOKEN_ASC = $97                     ;; the token for ASC
TOKEN_ASN = $98                     ;; the token for ASN
TOKEN_ATN = $99                     ;; the token for ATN
TOKEN_BGET = $9A                    ;; the token for BGET
TOKEN_COS = $9B                     ;; the token for COS
TOKEN_COUNT = $9C                   ;; the token for COUNT
TOKEN_DEG = $9D                     ;; the token for DEG
TOKEN_ERL = $9E                     ;; the token for ERL
TOKEN_ERR = $9F                     ;; the token for ERR
TOKEN_EVAL = $A0                    ;; the token for EVAL
TOKEN_EXP = $A1                     ;; the token for EXP
TOKEN_EXT = $A2                     ;; the token for EXT
TOKEN_FALSE = $A3                   ;; the token for FALSE
TOKEN_FN = $A4                      ;; the token for FN
TOKEN_GET = $A5                     ;; the token for GET
TOKEN_INKEY = $A6                   ;; the token for INKEY
TOKEN_INSTR = $A7                   ;; the token for INSTR(
TOKEN_INT = $A8                     ;; the token for INT
TOKEN_LEN = $A9                     ;; the token for LEN
TOKEN_LN = $AA                      ;; the token for LN
TOKEN_LOG = $AB                     ;; the token for LOG
TOKEN_NOT = $AC                     ;; the token for NOT
TOKEN_OPENUP = $AD                  ;; the token for OPENUP
TOKEN_OPENOUT = $AE                 ;; the token for OPENOUT
TOKEN_PI = $AF                      ;; the token for PI
TOKEN_POINT = $B0                   ;; the token for POINT(
TOKEN_POS = $B1                     ;; the token for POS
TOKEN_RAD = $B2                     ;; the token for RAD
TOKEN_RND = $B3                     ;; the token for RND
TOKEN_SGN = $B4                     ;; the token for SGN
TOKEN_SIN = $B5                     ;; the token for SIN
TOKEN_SQR = $B6                     ;; the token for SQR
TOKEN_TAN = $B7                     ;; the token for TAN
TOKEN_TO = $B8                      ;; the token for TO
TOKEN_TRUE = $B9                    ;; the token for TRUE
TOKEN_USR = $BA                     ;; the token for USR
TOKEN_VAL = $BB                     ;; the token for VAL
TOKEN_VPOS = $BC                    ;; the token for VPOS
TOKEN_CHR_STR = $BD                 ;; the token for CHR$
TOKEN_GET_STR = $BE                 ;; the token for GET$
TOKEN_INKEY_STR = $BF               ;; the token for INKEY$
TOKEN_LEFT_STR = $C0                ;; the token for LEFT$(
TOKEN_MID_STR = $C1                 ;; the token for MID$(
TOKEN_RIGHT_STR = $C2               ;; the token for RIGHT$(
TOKEN_STR_STR = $C3                 ;; the token for STR$
TOKEN_STRING_STR = $C4              ;; the token for STRING$(
TOKEN_EOF = $C5                     ;; the token for EOF
TOKEN_AUTO = $C6                    ;; the token for AUTO
TOKEN_DELETE = $C7                  ;; the token for DELETE
TOKEN_LOAD = $C8                    ;; the token for LOAD
TOKEN_LIST = $C9                    ;; the token for LIST
TOKEN_NEW = $CA                     ;; the token for NEW
TOKEN_OLD = $CB                     ;; the token for OLD
TOKEN_RENUMBER = $CC                ;; the token for RENUMBER
TOKEN_SAVE = $CD                    ;; the token for SAVE
TOKEN_PTR_STATEMENT = $CF           ;; the token for PTR at the start of a statement, as a statement
TOKEN_PAGE_STATEMENT = $D0          ;; the token for PAGE at the start of a statement, as a statement
TOKEN_TIME_STATEMENT = $D1          ;; the token for TIME at the start of a statement, as a statement
TOKEN_LOMEM_STATEMENT = $D2         ;; the token for LOMEM at the start of a statement, as a statement
TOKEN_HIMEM_STATEMENT = $D3         ;; the token for HIMEM at the start of a statement, as a statement
TOKEN_SOUND = $D4                   ;; the token for SOUND
TOKEN_BPUT = $D5                    ;; the token for BPUT
TOKEN_CALL = $D6                    ;; the token for CALL
TOKEN_CHAIN = $D7                   ;; the token for CHAIN
TOKEN_CLEAR = $D8                   ;; the token for CLEAR
TOKEN_CLOSE = $D9                   ;; the token for CLOSE
TOKEN_CLG = $DA                     ;; the token for CLG
TOKEN_CLS = $DB                     ;; the token for CLS
TOKEN_DATA = $DC                    ;; the token for DATA
TOKEN_DEF = $DD                     ;; the token for DEF
TOKEN_DIM = $DE                     ;; the token for DIM
TOKEN_DRAW = $DF                    ;; the token for DRAW
TOKEN_END = $E0                     ;; the token for END
TOKEN_ENDPROC = $E1                 ;; the token for ENDPROC
TOKEN_ENVELOPE = $E2                ;; the token for ENVELOPE
TOKEN_FOR = $E3                     ;; the token for FOR
TOKEN_GOSUB = $E4                   ;; the token for GOSUB
TOKEN_GOTO = $E5                    ;; the token for GOTO
TOKEN_GCOL = $E6                    ;; the token for GCOL
TOKEN_IF = $E7                      ;; the token for IF
TOKEN_INPUT = $E8                   ;; the token for INPUT
TOKEN_LET = $E9                     ;; the token for LET
TOKEN_LOCAL = $EA                   ;; the token for LOCAL
TOKEN_MODE = $EB                    ;; the token for MODE
TOKEN_MOVE = $EC                    ;; the token for MOVE
TOKEN_NEXT = $ED                    ;; the token for NEXT
TOKEN_ON = $EE                      ;; the token for ON
TOKEN_VDU = $EF                     ;; the token for VDU
TOKEN_PLOT = $F0                    ;; the token for PLOT
TOKEN_PRINT = $F1                   ;; the token for PRINT
TOKEN_PROC = $F2                    ;; the token for PROC
TOKEN_READ = $F3                    ;; the token for READ
TOKEN_REM = $F4                     ;; the token for REM
TOKEN_REPEAT = $F5                  ;; the token for REPEAT
TOKEN_REPORT = $F6                  ;; the token for REPORT
TOKEN_RESTORE = $F7                 ;; the token for RESTORE
TOKEN_RETURN = $F8                  ;; the token for RETURN
TOKEN_RUN = $F9                     ;; the token for RUN
TOKEN_STOP = $FA                    ;; the token for STOP
TOKEN_COLOUR = $FB                  ;; the token for COLOUR
TOKEN_TRACE = $FC                   ;; the token for TRACE
TOKEN_UNTIL = $FD                   ;; the token for UNTIL
TOKEN_WIDTH = $FE                   ;; the token for WIDTH
TOKEN_OSCLI = $FF                   ;; the token for OSCLI
