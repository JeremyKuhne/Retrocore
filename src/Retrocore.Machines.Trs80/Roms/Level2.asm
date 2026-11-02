;; TRS-80 MODEL I LEVEL II BASIC ($0000-$2FFF), REVISIONS 1.2 AND 1.3
;;
;; Level II is the Model I's 12K ROM: Microsoft BASIC for the Z80 with Radio Shack's device drivers.
;;
;; The first page holds the restarts. BASIC uses four of them as one-byte calls: RST $08 checks the next
;; character against the byte that follows it (SYNCHK), RST $10 gets the next character (CHRGTR), RST $18
;; compares HL with DE (DCOMPR) and RST $20 tests the accumulator's type (GETYPR). Each restart jumps
;; through a vector in RAM at $4000, so a disk operating system can take it over. The same page holds the
;; documented ROM calls: KBD_SCAN, DISPLAY_CHAR, PRINTER_CHAR, KBLINE, KBWAIT and DELAY. Devices are
;; reached through device control blocks in RAM, each naming its driver.
;;
;; BASIC itself follows Microsoft's design. A program line is stored crunched, with each reserved word a
;; one-byte token (KEYWORDS); statements run through STMDSP and functions through FUNDSP.
;; Errors load their code into E and jump to ERROR. Numbers are integers, or single or double precision in
;; Microsoft's binary format, in the accumulator at FACLO-FAC. Disk BASIC hooks in through the vectors
;; from $4152, which Level II points at NAVERR (Disk BASIC only) or at RET.
;;
;; Assembles byte-identically to Level II 1.2 or 1.3: REVISION selects the revision (13, the default, or
;; 12). 1.3 shortened the power-up messages, added a keyboard debounce, retimed the cassette and changed
;; PRINT.
;;
;; Labels are the names in Microsoft's and Radio Shack's original source, as trs-80.com's annotated
;; disassembly of Level II gives them, with any $ dropped: FDIV and its loops FDIV1 and FDIV2, CTPULS for
;; the cassette's pulse writer. A few keep other names: the documented ROM calls their usual names
;; (KBD_SCAN, DISPLAY_CHAR, KBLINE), statement and function handlers their keyword (ST_FOR, FN_LEFT),
;; error entries their code, and the RAM vectors, device control blocks and Disk BASIC hooks names that say
;; what they are. The few labels the original source does not name are named after the routine they are in.
;;
;; The comments are our own, written with trs-80.com's disassembly and the Level II ROM Reference Manual
;; (Micro Products, 1980) as references.
;;
;; Maintained by hand. Trs80RomSourceTests check that both revisions assemble byte-identically to the ROMs.

.ifndef REVISION
REVISION = 13
.endif
.assert (REVISION = 12) | (REVISION = 13), "REVISION is 12 or 13."

.cpu Z80

;; A reserved word: its first letter with bit 7 set marks where it starts.
.macro KEYWORD word
    .byte .strat(word, 0) | $80
    .repeat .strlen(word) - 1, index
    .byte .strat(word, index + 1)
    .endrepeat
.endmacro

;; A device control block: its type, driver, two bytes of driver state, a spare byte and its name.
.macro DCB type, driver, state, spare, name
    .byte type
    .word driver
    .word state
    .byte spare
    .byte name
.endmacro

;; Error codes: the code in E when a routine jumps to ERROR, twice the index of its two letters in
;; ERROR_CODES.
ERR_NF = $00                        ;; NF: NEXT without FOR
ERR_SN = $02                        ;; SN: syntax error
ERR_RG = $04                        ;; RG: RETURN without GOSUB
ERR_OD = $06                        ;; OD: out of DATA
ERR_FC = $08                        ;; FC: illegal function call
ERR_OV = $0A                        ;; OV: overflow
ERR_OM = $0C                        ;; OM: out of memory
ERR_UL = $0E                        ;; UL: undefined line
ERR_BS = $10                        ;; BS: subscript out of range
ERR_DD = $12                        ;; DD: redimensioned array
ERR_DV0 = $14                       ;; /0: division by zero
ERR_ID = $16                        ;; ID: illegal direct
ERR_TM = $18                        ;; TM: type mismatch
ERR_OS = $1A                        ;; OS: out of string space
ERR_LS = $1C                        ;; LS: string too long
ERR_ST = $1E                        ;; ST: string formula too complex
ERR_CN = $20                        ;; CN: can't continue
ERR_NR = $22                        ;; NR: no RESUME
ERR_RW = $24                        ;; RW: RESUME without error
ERR_UE = $26                        ;; UE: unprintable error
ERR_MO = $28                        ;; MO: missing operand
ERR_FD = $2A                        ;; FD: bad file data
ERR_L3 = $2C                        ;; L3: Disk BASIC only

;; Tokens: a keyword in a program line is stored as one byte, $80 plus its place in KEYWORDS.
TK_END = $80                        ;; END
TK_FOR = $81                        ;; FOR
TK_RESET = $82                      ;; RESET
TK_SET = $83                        ;; SET
TK_CLS = $84                        ;; CLS
TK_CMD = $85                        ;; CMD
TK_RANDOM = $86                     ;; RANDOM
TK_NEXT = $87                       ;; NEXT
TK_DATA = $88                       ;; DATA
TK_INPUT = $89                      ;; INPUT
TK_DIM = $8A                        ;; DIM
TK_READ = $8B                       ;; READ
TK_LET = $8C                        ;; LET
TK_GOTO = $8D                       ;; GOTO
TK_RUN = $8E                        ;; RUN
TK_IF = $8F                         ;; IF
TK_RESTORE = $90                    ;; RESTORE
TK_GOSUB = $91                      ;; GOSUB
TK_RETURN = $92                     ;; RETURN
TK_REM = $93                        ;; REM
TK_STOP = $94                       ;; STOP
TK_ELSE = $95                       ;; ELSE
TK_TRON = $96                       ;; TRON
TK_TROFF = $97                      ;; TROFF
TK_DEFSTR = $98                     ;; DEFSTR
TK_DEFINT = $99                     ;; DEFINT
TK_DEFSNG = $9A                     ;; DEFSNG
TK_DEFDBL = $9B                     ;; DEFDBL
TK_LINE = $9C                       ;; LINE
TK_EDIT = $9D                       ;; EDIT
TK_ERROR = $9E                      ;; ERROR
TK_RESUME = $9F                     ;; RESUME
TK_OUT = $A0                        ;; OUT
TK_ON = $A1                         ;; ON
TK_OPEN = $A2                       ;; OPEN
TK_FIELD = $A3                      ;; FIELD
TK_GET = $A4                        ;; GET
TK_PUT = $A5                        ;; PUT
TK_CLOSE = $A6                      ;; CLOSE
TK_LOAD = $A7                       ;; LOAD
TK_MERGE = $A8                      ;; MERGE
TK_NAME = $A9                       ;; NAME
TK_KILL = $AA                       ;; KILL
TK_LSET = $AB                       ;; LSET
TK_RSET = $AC                       ;; RSET
TK_SAVE = $AD                       ;; SAVE
TK_SYSTEM = $AE                     ;; SYSTEM
TK_LPRINT = $AF                     ;; LPRINT
TK_DEF = $B0                        ;; DEF
TK_POKE = $B1                       ;; POKE
TK_PRINT = $B2                      ;; PRINT
TK_CONT = $B3                       ;; CONT
TK_LIST = $B4                       ;; LIST
TK_LLIST = $B5                      ;; LLIST
TK_DELETE = $B6                     ;; DELETE
TK_AUTO = $B7                       ;; AUTO
TK_CLEAR = $B8                      ;; CLEAR
TK_CLOAD = $B9                      ;; CLOAD
TK_CSAVE = $BA                      ;; CSAVE
TK_NEW = $BB                        ;; NEW
TK_TAB = $BC                        ;; TAB(
TK_TO = $BD                         ;; TO
TK_FN = $BE                         ;; FN
TK_USING = $BF                      ;; USING
TK_VARPTR = $C0                     ;; VARPTR
TK_USR = $C1                        ;; USR
TK_ERL = $C2                        ;; ERL
TK_ERR = $C3                        ;; ERR
TK_STRING = $C4                     ;; STRING$
TK_INSTR = $C5                      ;; INSTR
TK_POINT = $C6                      ;; POINT
TK_TIME = $C7                       ;; TIME$
TK_MEM = $C8                        ;; MEM
TK_INKEY = $C9                      ;; INKEY$
TK_THEN = $CA                       ;; THEN
TK_NOT = $CB                        ;; NOT
TK_STEP = $CC                       ;; STEP
TK_PLUS = $CD                       ;; +
TK_MINUS = $CE                      ;; -
TK_TIMES = $CF                      ;; *
TK_DIVIDE = $D0                     ;; /
TK_POWER = $D1                      ;; [
TK_AND = $D2                        ;; AND
TK_OR = $D3                         ;; OR
TK_GREATER = $D4                    ;; >
TK_EQUAL = $D5                      ;; =
TK_LESS = $D6                       ;; <
TK_SGN = $D7                        ;; SGN
TK_INT = $D8                        ;; INT
TK_ABS = $D9                        ;; ABS
TK_FRE = $DA                        ;; FRE
TK_INP = $DB                        ;; INP
TK_POS = $DC                        ;; POS
TK_SQR = $DD                        ;; SQR
TK_RND = $DE                        ;; RND
TK_LOG = $DF                        ;; LOG
TK_EXP = $E0                        ;; EXP
TK_COS = $E1                        ;; COS
TK_SIN = $E2                        ;; SIN
TK_TAN = $E3                        ;; TAN
TK_ATN = $E4                        ;; ATN
TK_PEEK = $E5                       ;; PEEK
TK_CVI = $E6                        ;; CVI
TK_CVS = $E7                        ;; CVS
TK_CVD = $E8                        ;; CVD
TK_EOF = $E9                        ;; EOF
TK_LOC = $EA                        ;; LOC
TK_LOF = $EB                        ;; LOF
TK_MKI = $EC                        ;; MKI$
TK_MKS = $ED                        ;; MKS$
TK_MKD = $EE                        ;; MKD$
TK_CINT = $EF                       ;; CINT
TK_CSNG = $F0                       ;; CSNG
TK_CDBL = $F1                       ;; CDBL
TK_FIX = $F2                        ;; FIX
TK_LEN = $F3                        ;; LEN
TK_STR = $F4                        ;; STR$
TK_VAL = $F5                        ;; VAL
TK_ASC = $F6                        ;; ASC
TK_CHR = $F7                        ;; CHR$
TK_LEFT = $F8                       ;; LEFT$
TK_RIGHT = $F9                      ;; RIGHT$
TK_MID = $FA                        ;; MID$
TK_APOSTROPHE = $FB                 ;; '

FIN_SKIP_OPERAND = $321E            ;; not an address: operand of the never-taken JP M ($FA) that skips LD E,$32 in FIN
INTERRUPT_LATCH = $37E0             ;; bit 7: the 40 Hz clock; bit 6: the disk controller
DRIVE_SELECT = $37E1                ;; bits 0-3 select drives 0-3
CASSETTE_SELECT = $37E4             ;; the Expansion Interface's cassette select
PRINTER_STATUS = $37E8
FDC_STATUS = $37EC                  ;; the FD1771's status, and its command when written
FDC_TRACK = $37ED
FDC_SECTOR = $37EE
FDC_DATA = $37EF
KEYBOARD = $3800                    ;; rows are selected by address bits 0-7
KEYBOARD_ROW0 = $3801
KEYBOARD_ROW6 = $3840               ;; ENTER, CLEAR, BREAK, arrows, space
KEYBOARD_ROW7 = $3880               ;; SHIFT
VIDEO = $3C00                       ;; 64x16 characters
CASSETTE_STATUS_CHAR = $3C3E        ;; screen cell near the top right: '*' while reading tape, 'C' on a checksum error
CASSETTE_BLINK_CHAR = $3C3F         ;; screen cell at the top right corner: the asterisk that blinks as tape blocks load
RST08_VECTOR = $4000
RST10_VECTOR = $4003
RST18_VECTOR = $4006
RST20_VECTOR = $4009
RST28_VECTOR = $400C
RST30_VECTOR = $400F
RST38_VECTOR = $4012
KEYBOARD_DCB = $4015
VIDEO_DCB = $401D
CURSOR_ADDRESS = $4020              ;; the video DCB's cursor: the screen address of the next character
PRINTER_DCB = $4025
DCB_REQUEST_HOOK = $4033            ;; jump vector taken when a DCB's type does not allow the request in B
KEYBOARD_IMAGE = $4036              ;; the rows as the last scan saw them
PORT_FF_IMAGE = $403D               ;; the last value written to port $FF
FDIVC = $4080                  ;; the division routine and constants copied from $18F7
DIVIDE_SUB_LO = $4081               ;; in the RAM divide routine: SUB operand, the divisor's low mantissa byte
DIVIDE_SUB_MID = $4085              ;; in the RAM divide routine: SBC operand, the divisor's middle mantissa byte
DIVIDE_SUB_HI = $4089               ;; in the RAM divide routine: SBC operand, the divisor's high mantissa byte
DIVIDE_EXTRA_BYTE = $408C           ;; in the RAM divide routine: LD A operand, the dividend's extra high byte
USRTAB = $408E                 ;; the address USR calls
STAINP = $4093                     ;; iN A,(n) / RET built in RAM for INP
INP_PORT = $4094                    ;; the port operand of the INP routine in RAM
OUTWRD = $4096                     ;; oUT (n),A / RET built in RAM for OUT
OUT_PORT = $4097                    ;; the port operand of the OUT routine in RAM
CHARC = $4099                   ;; a key read by the BREAK check, kept for INKEY$; zero when none
ERRFLG = $409A
LPTPOS = $409B              ;; the printer's carriage position
PRTFLG = $409C               ;; 0 video, 1 printer, -1 cassette
LINLEN = $409D            ;; the video line width PRINT wraps at
CLMLST = $409E            ;; the last video column where a comma starts a new print zone
STKTOP = $40A0                      ;; the bottom of string space; the stack sits below it
CURLIN = $40A2
TXTTAB = $40A4                      ;; the program's first line
TTYPOS = $40A6                      ;; the cursor's column on the current output device
BUFPNT = $40A7                ;; the address of the line input buffer
CASFLG = $40A9                ;; zero while INPUT # reads the cassette, nonzero for the keyboard
RNDX = $40AA                    ;; the random number seed's low bytes (three bytes to $40AC)
RND_SEED_MID = $40AB                ;; the seed's middle byte, which RANDOM loads from R
RND_SEED_HIGH = $40AC               ;; the random number seed's high byte
DIMFLG = $40AE                      ;; nonzero while DIM creates arrays
VALTYP = $40AF                      ;; the type of the value in the accumulator: 2 integer, 3 string, 4 single, 8 double
DORES = $40B0                       ;; nonzero while CRUNCH copies DATA unchanged
MEMSIZ = $40B1                      ;; the top of memory BASIC uses
TEMPPT = $40B3                      ;; the next free temporary string descriptor
DSCTMP = $40D3                      ;; the descriptor of a string being built
DSCTMP_PTR = $40D4                  ;; the address in DSCTMP: where the string being built lives
FRETOP = $40D6                      ;; the bottom of the strings in string space
TEMP3 = $40D8                 ;; a work word: PRINT USING's format flags, an array pointer, garbage collection
DATLIN = $40DA                      ;; the line of the DATA statement being read
SUBFLG = $40DC                      ;; nonzero when subscripts are not allowed (FOR sets $64)
BFKLFL = $40DD                 ;; tested when a direct statement ends; nonzero returns to READY (DOS use)
READ_INPUT_FLAG = $40DE             ;; nonzero for READ, zero for INPUT; PRINT USING reuses it
TEMP = $40DF                        ;; a work word: the text pointer in LET, FOR and NEXT, SYSTEM's entry address
AUTFLG = $40E1                      ;; nonzero while AUTO numbers lines
AUTLIN = $40E2                      ;; the next line number AUTO offers
AUTINC = $40E4                      ;; aUTO's line increment
SAVTXT = $40E6                      ;; the text pointer of the statement being run, for errors, STOP and INPUT
SAVSTK = $40E8                      ;; the stack pointer for the statement being run
ERRLIN = $40EA                      ;; ERL: the line of the last error
DOT = $40EC                         ;; the current line, for "."
ERRTXT = $40EE                      ;; the text pointer of the last error, for RESUME
ONELIN = $40F0                      ;; the ON ERROR line's text
ONEFLG = $40F2                      ;; nonzero inside an error handler
TEMP2 = $40F3                 ;; a work word: the end of an array's subscripts, the end of a number's digits
OLDLIN = $40F5                      ;; the line STOP or END stopped in, for CONT
OLDTXT = $40F7                      ;; the text pointer STOP or END stopped at, for CONT
VARTAB = $40F9                      ;; the simple variables, after the program
ARYTAB = $40FB                      ;; the arrays, after the simple variables
STREND = $40FD                      ;; the first free byte, after the arrays
DATPTR = $40FF                      ;; the next DATA item
DEFTBL = $4101                      ;; the default type of each letter, A-Z
TRCFLG = $411B                      ;; nonzero while TRON traces line numbers
FAC_ROUND_BYTE = $411C              ;; the accumulator's extra low byte, kept for rounding
DFACLO = $411D                      ;; the double precision accumulator's low bytes, below FACLO
DFAC_MID = $411F                    ;; the double precision accumulator's third and fourth bytes
FACLO = $4121                       ;; the accumulator: an integer, a string's descriptor, or a single's mantissa
FACHI = $4123                       ;; the sign and high bits of a single's mantissa
FAC = $4124                         ;; the accumulator's exponent
FAC_SIGN_TEMP = $4126               ;; a work byte after the accumulator: the result's sign during arithmetic
ARGLO = $4127                       ;; the second accumulator, for double precision
ARGHI = $412D                       ;; the sign and high bits of the second accumulator's mantissa
ARG = $412E                         ;; the second accumulator's exponent
FMLTT1 = $414F                ;; fMULT's copy of the multiplier's high mantissa byte
FMLTT2 = $4150                ;; fMULT's copy of the multiplier's low mantissa bytes
HOOK_CVI = $4152
HOOK_FN = $4155                     ;; disk BASIC vector for FN
HOOK_CVS = $4158
HOOK_DEF = $415B
HOOK_CVD = $415E
HOOK_EOF = $4161
HOOK_LOC = $4164
HOOK_LOF = $4167
HOOK_MKI = $416A
HOOK_MKS = $416D
HOOK_MKD = $4170
HOOK_CMD = $4173
HOOK_TIME = $4176                   ;; disk BASIC vector for TIME$
HOOK_OPEN = $4179
HOOK_FIELD = $417C
HOOK_GET = $417F
HOOK_PUT = $4182
HOOK_CLOSE = $4185
HOOK_LOAD = $4188
HOOK_MERGE = $418B
HOOK_NAME = $418E
HOOK_KILL = $4191
HOOK_AMPERSAND = $4194              ;; disk BASIC vector for & (hex and octal constants)
HOOK_LSET = $4197
HOOK_RSET = $419A
HOOK_INSTR = $419D                  ;; disk BASIC vector for INSTR
HOOK_SAVE = $41A0
HOOK_LINE = $41A3
HOOK_ERROR_MSG = $41A6              ;; dOS exit before an error message is printed
HOOK_USR = $41A9                    ;; dOS exit at USR, before the argument is evaluated
HOOK_READY = $41AC                  ;; dOS exit before READY is printed
HOOK_INLIN = $41AF                  ;; dOS exit when a line of input starts
HOOK_LINE_ENTERED = $41B2           ;; dOS exit after a typed line's number is read, before it is crunched
HOOK_LINE_INSERTED = $41B5          ;; dOS exit after a program line is stored, before the variables are cleared
HOOK_LINE_CLEARED = $41B8           ;; dOS exit after storing a line and clearing, before the command loop
HOOK_CLEAR = $41BB                  ;; dOS exit as CLEARC finishes and at END
HOOK_FINPRT = $41BE                 ;; dOS exit when output returns to the video (FINPRT)
HOOK_OUTDO = $41C1                  ;; dOS exit for each character OUTDO prints
HOOK_KEY_SCAN = $41C4               ;; dOS exit before each keyboard scan
HOOK_RUN = $41C7                    ;; dOS exit at RUN with an argument
HOOK_PRINT = $41CA                  ;; dOS exit at PRINT
HOOK_PRINT_NUMBER = $41CD           ;; dOS exit when PRINT has formatted a number
HOOK_CRDO = $41D0                   ;; dOS exit after PRINT ends a line
HOOK_PRINT_POSITION = $41D3         ;; dOS exit at PRINT's comma and TAB, before the position is checked
HOOK_INPUT = $41D6                  ;; dOS exit at INPUT
HOOK_MID_STATEMENT = $41D9          ;; disk BASIC vector for MID$ used as a statement
HOOK_READ_ITEM = $41DC              ;; dOS exit before READ or INPUT assigns each variable
HOOK_READ_LIST = $41DF              ;; dOS exit at the end of READ/INPUT and before LIST prints each line
HOOK_SYSTEM = $41E2                 ;; dOS exit at SYSTEM
BOOT_SECTOR = $4200                 ;; where the disk boot sector is read to and run
USING_SKIP_OPERAND = $D1EB          ;; not an address: operand of a never-taken JP Z in PRINT USING's exponent check

.org $0000

;; Power-up and reset: interrupts off, then the cold start at INIT.
RESET:
    DI
    XOR A
    JP INIT
    JP RST08_VECTOR                 ; spare entry at $0005, also the RST $08 vector

;; RST $08: the character at HL must be the byte after the RST; returns past it with the next character,
;; or it is a syntax error.
RST_SYNCHK:
    JP RST08_VECTOR

WHERE:
    POP HL                          ; HL = the caller's return address
    JP [HL]
    JP BOOT                         ; fixed entry at $000D: boot the disk

;; RST $10: steps HL to the next nonblank character of the line and returns it in A, with carry for a
;; digit and Z at the end of a statement.
RST_CHRGTR:
    JP RST10_VECTOR

;; Reads a byte from the device whose control block DE addresses.
GET:
    PUSH BC                         ; BC carries the request code, CIO restores it
    LD B,$01                        ; request 1: read a byte
    JR CIOJ

;; RST $18: compares HL with DE, setting Z and C as for CP.
RST_DCOMPR:
    JP RST18_VECTOR

;; Writes the byte in A to the device whose control block DE addresses.
PUT:
    PUSH BC
    LD B,$02                        ; request 2: write a byte
    JR CIOJ

;; RST $20: tests VALTYP: M for an integer, Z for a string, PO for single and NC for double precision.
RST_GETYPR:
    JP RST20_VECTOR

;; Sends a control request to the device whose control block DE addresses.
CTL:
    PUSH BC
    LD B,$04                        ; request 4: control call
    JR CIOJ

;; RST $28: a request to the disk operating system, through RST28_VECTOR.
RST_DOS:
    JP RST28_VECTOR

;; Scans the keyboard: the character of a newly pressed key in A, or zero.
KBD_SCAN:
    LD DE,KEYBOARD_DCB
    JR GET

;; RST $30: a debugger breakpoint, through RST30_VECTOR.
RST_DEBUG:
    JP RST30_VECTOR

;; Shows the character in A at the cursor, acting on control codes.
DISPLAY_CHAR:
    LD DE,VIDEO_DCB
    JR PUT

;; RST $38: the maskable interrupt, through RST38_VECTOR.
RST_INTERRUPT:
    JP RST38_VECTOR

;; Sends the character in A to the printer.
PRINTER_CHAR:
    LD DE,PRINTER_DCB
    JR PUT

;; Reads a line of at most B characters into the buffer at HL; carry when BREAK ends it.
KBLINE:
    JP KEYIN
    RET                             ; padding to the next fixed entry
    NOP
    NOP

CIOJ:
    JP CIO

;; Waits for a key and returns its character in A.
KBWAIT:
    CALL KBD_SCAN
    OR A                            ; zero means no key yet, keep scanning
    RET NZ
    JR KBWAIT

KEYTAB:
    .byte $0D, $0D                  ; ENTER, then with SHIFT
    .byte $1F, $1F                  ; CLEAR, then with SHIFT
    .byte $01, $01                  ; BREAK, then with SHIFT
    .byte $5B, $1B                  ; up arrow, then with SHIFT
.if REVISION = 12
    .byte $0A, $1A                  ; down arrow, then with SHIFT
.else
    .byte $0A, $00                  ; down arrow, then with SHIFT
.endif
    .byte $08, $18                  ; left arrow, then with SHIFT
    .byte $09, $19                  ; right arrow, then with SHIFT
    .byte $20, $20                  ; space, then with SHIFT

;; Waits for BC passes of a 26 T-state loop, about 14.7 us each.
DELAY:
    DEC BC
    LD A,B
    OR C
    JR NZ,DELAY
    RET

;; The nonmaskable interrupt: RESET with the Expansion Interface. Boots a disk when a controller answers,
;; otherwise restarts BASIC.
NMI:
    LD SP,$0600
    LD A,[FDC_STATUS]               ; a missing disk controller reads back as $FF
    INC A                           ; $FF and $00 become 0 and 1, anything else 2 or more
    CP $02
    JP NC,RESET                     ; a controller answered: cold start, which boots the disk
    JP RESETR                       ; no disk: warm restart of BASIC

INIT2:
    LD DE,FDIVC                     ; RAM home of the division routine and its work area
    LD HL,$18F7                     ; ROM image of the initial RAM contents
    LD BC,$0027                     ; 39 bytes
    LDIR
    LD HL,$41E5                     ; the three bytes just before the input buffer
    LD [HL],$3A                     ; a colon ahead of the buffer
    INC HL
    LD [HL],B                       ; B is zero after the LDIR
    INC HL
    LD [HL],$2C                     ; and a comma
    INC HL
    LD [BUFPNT],HL                  ; the input buffer starts just past them
    LD DE,$012D                     ; NAVERR: Disk BASIC keywords give ?L3 ERROR
    LD B,$1C                        ; 28 Disk BASIC hooks
    LD HL,HOOK_CVI
ERLOPS:
    LD [HL],$C3                     ; a JP opcode
    INC HL
    LD [HL],E
    INC HL
    LD [HL],D
    INC HL
    DJNZ ERLOPS
    LD B,$15                        ; 21 DOS exits follow
LOPRTS:
    LD [HL],$C9                     ; a RET opcode, so the exit does nothing yet
    INC HL
    INC HL                          ; skip the rest of the three-byte slot
    INC HL
    DJNZ LOPRTS
    LD HL,$42E8                     ; the zero byte just before the program text
    LD [HL],B                       ; B is zero after the loop
    LD SP,$41F8                     ; a temporary stack in the communications area
    CALL STKINI
    CALL CLS

MEMGET:
    LD HL,MEMMSG
    CALL STROUT
    CALL QINLIN
    JR C,MEMGET
    RST $10                         ; first character of the reply
    OR A
    JR NZ,TYPMEM                    ; a size was typed
    LD HL,$434C                     ; scan for RAM from just below free memory
LOOPMM:
    INC HL
    LD A,H                          ; wrapping past $FFFF means all 64K is RAM
    OR L
    JR Z,USEDEF
    LD A,[HL]
    LD B,A                          ; keep the byte so it can be put back
    CPL                             ; write its complement and see if it stuck
    LD [HL],A
    CP [HL]
    LD [HL],B                       ; restore the original byte
    JR Z,LOOPMM                     ; still RAM, keep climbing
    JR USEDEF                       ; HL is the first address that is not RAM
TYPMEM:
    CALL LINGET                     ; DE = the size typed
    OR A
    JP NZ,SNERR                     ; anything after the number is a syntax error
    EX DE,HL
    DEC HL                          ; HL = the highest byte asked for
    LD A,$8F                        ; check that byte is really RAM
    LD B,[HL]
    LD [HL],A
    CP [HL]
    LD [HL],B                       ; restore the original byte
    JR NZ,MEMGET                    ; not RAM: ask again
USEDEF:
    DEC HL                          ; HL = the top byte BASIC may use
    LD DE,$4414                     ; the least memory BASIC can work in
    RST $18
    JP C,OMERR                      ; too little memory for BASIC
    LD DE,$FFCE                     ; minus 50: the default string space
    LD [MEMSIZ],HL                  ; top of memory for BASIC
    ADD HL,DE
    LD [STKTOP],HL                  ; string space starts 50 bytes below it
    CALL ERASE_PROGRAM
    LD HL,BANNER_MSG
    CALL STROUT
    JP READY

;; Holds the zero-terminated MEMORY SIZE prompt shown at power-up (shortened to MEM SIZE in 1.3).
MEMMSG:
.if REVISION = 12
    .byte "MEMORY SIZE", $00
.else
    .byte "MEM SIZE", $00
.endif

BANNER_MSG:
.if REVISION = 12
    .byte "RADIO SHACK LEVEL II BASIC", $0D
.else
    .byte "R/S L2 BASIC", $0D
.endif
    .byte $00
.if REVISION = 13

;; Level II 1.3: rereads a newly pressed key after about 19 ms and drops it if it has bounced up.
KEY_DEBOUNCE:
    PUSH BC
    LD BC,$0500
    CALL DELAY
    POP BC
    LD A,[BC]                       ; reread the key's keyboard row
    AND E                           ; keep only this key's bit
    RET Z                           ; it bounced up: no key
    LD A,D
    RLCA
    RLCA
    JP KEYBOARD_DRIVER_12
.endif
;; Raises the ?L3 ERROR that a Disk BASIC keyword gives when no DOS is loaded.
NAVERR:
    LD E,ERR_L3
    JP ERROR
;; Runs the POINT(x,y) function, leaving -1 in FAC when the graphics block is lit and 0 when not.
;; Shared with SET and RESET, which enter with their own mode in A.
POINT:
    RST $10
    XOR A                           ; mode 0: POINT tests the block
    .byte $01                       ; LD BC,nn: skips the next instruction
;; Runs the SET(x,y) statement, lighting the graphics block at column x (0-127), row y (0-47).
ST_SET:
    LD A,$80                        ; mode $80: SET lights the block
    .byte $01                       ; LD BC,nn: skips the next instruction
;; Runs the RESET(x,y) statement, turning off the graphics block at column x, row y.
ST_RESET:
    LD A,$01                        ; mode 1: RESET turns the block off
    PUSH AF                         ; keep the mode for later
    RST $08
    .byte '('
    CALL GETBYT
    CP $80                          ; x must be 0 to 127
    JP NC,FCERR
    PUSH AF                         ; keep x
    RST $08
    .byte ','
    CALL GETBYT
    CP $30                          ; y must be 0 to 47
    JP NC,FCERR
    LD D,$FF                        ; D counts text rows, starting at -1
;; Enters the SET/RESET/POINT loop that divides y by 3, giving the screen row in D and the
;; block's row within the cell in A.
LOPMD3:
    INC D
    SUB $03                         ; three block rows to a text row
    JR NC,LOPMD3
    ADD A,$03                       ; A = the block's row within the cell, 0 to 2
    LD C,A                          ; C = that row
    POP AF                          ; A = x
    ADD A,A                         ; D = text row, E = x times 2
    LD E,A
    LD B,$02                        ; two shifts: DE = row*64 + x/2, the cell offset
;; Enters the SET/RESET/POINT loop that shifts DE right to form the screen offset of the cell.
SHFTW:
    LD A,D
    RRA
    LD D,A
    LD A,E
    RRA
    LD E,A
    DJNZ SHFTW
    LD A,C                          ; the carry is x's odd bit: left or right column
    ADC A,A                         ; A = cell row*2 plus the column, the block's bit number
    INC A                           ; plus one, the count of shifts below
    LD B,A
    XOR A                           ; start the mask with the carry set
    SCF
;; Enters the SET/RESET/POINT loop that builds the bit mask for the block within its cell.
PWR2:
    ADC A,A
    DJNZ PWR2
    LD C,A                          ; C = the block's bit in the cell
    LD A,D
    OR $3C                          ; video memory starts at $3C00
    LD D,A
    LD A,[DE]                       ; A = the character now in the cell
    OR A
    JP M,FND4                       ; already a graphics character
    LD A,$80                        ; any other character counts as an empty graphics cell
;; Enters SET/RESET/POINT with the cell's contents, a non-graphics character reading as blank,
;; and sets, clears or tests the block according to the saved mode.
FND4:
    LD B,A
    POP AF                          ; the saved mode
    OR A
    LD A,B
    JR Z,TBIT                       ; mode 0: POINT only tests
    LD [DE],A                       ; the cell now holds a graphics character
    JP M,SBIT                       ; mode $80 is SET
    LD A,C                          ; RESET: invert the mask
    CPL
    LD C,A
    LD A,[DE]
    AND C                           ; turn the block off
FINSTB:
    LD [DE],A
;; Ends SET, RESET and POINT by requiring the closing parenthesis.
FINPTB:
    RST $08
    .byte ')'
    RET
;; Lights the block for SET by ORing the mask in C into the cell, then stores it.
SBIT:
    OR C
    JR FINSTB
;; Tests the block for POINT and returns -1 or 0 in FAC as an integer through <CONIA>.
TBIT:
    AND C                           ; keep only the block's bit
    ADD A,$FF                       ; carry when the block is lit
    SBC A,A                         ; A = $FF when lit, 0 when not
    PUSH HL                         ; keep the text pointer
    CALL CONIA                      ; FAC = -1 or 0
    POP HL
    JR FINPTB
;; Runs the INKEY$ function, returning the key just pressed as a one-character string, or an
;; empty string when no key is waiting.
INKEY:
    RST $10                         ; step past the INKEY$ token
    PUSH HL                         ; keep the text pointer
    LD A,[CHARC]                    ; a key saved while checking for BREAK
    OR A
    JR NZ,BUFCIN                    ; use the held key first

;; Enters INKEY$ at the keyboard scan, used when no key was held over in CHARC.
MRCHRI:
    CALL ISCHAR
    OR A
    JR Z,NULRT                      ; no key: return an empty string
;; Builds INKEY$'s one-character string from the key in A and clears CHARC.
BUFCIN:
    PUSH AF                         ; keep the key
    XOR A
    LD [CHARC],A                    ; the held key is now used up
    INC A                           ; a string one character long
    CALL STRINI
    POP AF
    LD HL,[DSCTMP_PTR]              ; address of the new string's text
    LD [HL],A
    JP PUTNEW                       ; return the string's descriptor as the result
;; Returns the empty string from INKEY$ by pointing FAC at a null string descriptor.
NULRT:
    LD HL,$1928                     ; a zero-length string descriptor in ROM
    LD [FACLO],HL
    LD A,$03                        ; result type 3, a string
    LD [VALTYP],A
    POP HL                          ; restore the text pointer
    RET

;; Clears the screen and homes the cursor.
CLS:
    LD A,$1C                        ; $1C homes the cursor
    CALL OUT2D
    LD A,$1F                        ; $1F clears to the end of the screen
    JP OUT2D
;; Runs the RANDOM statement, reseeding the random number generator from the R register.
ST_RANDOM:
    LD A,R                          ; R changes with every instruction
    LD [RND_SEED_MID],A
    RET

;; Writes one pulse to the tape: drives the cassette output one way, then the other, then
;; back to rest, with the delays that set the bit timing.
CASSETTE_WRITE_BIT:
    LD HL,$FC01                     ; drive the output high
    CALL SET_PORT_FF
    LD B,$0B                        ; pulse width delay
CT1:
    DJNZ CT1
    LD HL,$FC02                     ; then drive it low
    CALL SET_PORT_FF
    LD B,$0B
CT2:
    DJNZ CT2
    LD HL,$FC00                     ; then back to rest
    CALL SET_PORT_FF
    LD B,$5C                        ; the rest of the bit cell
CT3:
    DJNZ CT3
    RET

;; Stops the cassette motor.
CASSETTE_OFF:
    PUSH HL
    LD HL,$FB00                     ; clear the motor bit
    JR CTCHG2

;; Selects the cassette drive from #-1 or #-2 at HL and starts its motor (DEFDRV at _1, drive in A).
CASSETTE_SELECT_ARG:
    LD A,[HL]                       ; a # means a drive number follows
    SUB $23
    LD A,$00                        ; no #: drive 0, without changing the flags
    JR NZ,DEFDRV                    ; default to #-1
    CALL GETINT
    RST $08
    .byte ','
    LD A,E                          ; must be -1 or -2: D and E both $FF or $FE
    AND D
    ADD A,$02                       ; -1 and -2 become 1 and 0, others fail
    JP NC,FCERR                     ; not -1 or -2
    DEC A                           ; A = 0 for #-1, 1 for #-2

;; Selects the cassette drive in A and starts its motor.
;; In:    A = the drive (0 for #-1, 1 for #-2)
DEFDRV:
    LD [CASSETTE_SELECT],A
    PUSH HL
    LD HL,$FF04                     ; set the motor bit

CTCHG2:
    CALL SET_PORT_FF
    POP HL                          ; restore the caller's HL
    RET

;; Rewrites port $FF from PORT_FF_IMAGE, clearing the cassette input latch.
CTSTAT:
    LD HL,$FF00                     ; keep every bit, set none

;; Updates port $FF and its copy in PORT_FF_IMAGE by ANDing with H and ORing with L.
;; In:    H = the bits to keep, L = the bits to set
SET_PORT_FF:
    LD A,[PORT_FF_IMAGE]
    AND H
    OR L
    OUT [$FF],A
    LD [PORT_FF_IMAGE],A
    RET

;; Toggles the asterisk in the top-right screen corner while a tape loads.
BCASIN:
    LD A,[CASSETTE_BLINK_CHAR]
    XOR $0A                         ; swap between * and blank
    LD [CASSETTE_BLINK_CHAR],A
    RET

;; Reads a byte from the tape into A.
CASSETTE_READ:
    PUSH BC
    PUSH HL
    LD B,$08                        ; eight bits to a byte
CTB0:
    CALL CASSETTE_READ_BIT
    DJNZ CTB0
    POP HL
    POP BC
    RET

;; Waits for a tape pulse and shifts the bit that follows it into the low end of A.
CASSETTE_READ_BIT:
    PUSH BC
    PUSH AF
CBO:
    IN A,[$FF]                      ; bit 7 is the cassette input latch
    RLA
    JR NC,CBO                       ; wait for the clock pulse
.if REVISION = 12
    LD B,$41
.else
    LD B,$60                        ; wait past the clock pulse
.endif
CB1:
    DJNZ CB1
    CALL CTSTAT                     ; reset the latch
.if REVISION = 12
    LD B,$76
.else
    LD B,$85                        ; wait to the middle of the bit cell
.endif
CB2:
    DJNZ CB2
    IN A,[$FF]                      ; a pulse here is a 1 bit
    LD B,A
    POP AF                          ; the byte built so far
    RL B                            ; latch bit into carry
    RLA                             ; shift it into the byte
    PUSH AF
    CALL CTSTAT                     ; reset the latch for the next bit
    POP AF
    POP BC
    RET

;; Writes the byte in A to the tape twice.
TWOCSO:
    CALL CASSETTE_WRITE

;; Writes the byte in A to the tape.
CASSETTE_WRITE:
    PUSH HL
    PUSH BC
    PUSH DE
    PUSH AF
    LD C,$08                        ; eight bits, high bit first
    LD D,A
BYT0:
    CALL CASSETTE_WRITE_BIT         ; every bit starts with a clock pulse
    LD A,D
    RLCA                            ; next bit into carry
    LD D,A
    JR NC,BYT2                      ; a 0 bit has no data pulse
    CALL CASSETTE_WRITE_BIT         ; a 1 bit adds a data pulse
BYT1:
    DEC C
    JR NZ,BYT0
    POP AF
    POP DE
    POP BC
    POP HL
    RET
;; Enters CASSETTE_WRITE for a zero bit, waiting out the time a second pulse would take.
BYT2:
    LD B,$87                        ; time a data pulse would take
BYT3:
    DJNZ BYT3
    JR BYT1

;; Selects the cassette from #-n at HL, starts the motor and writes the leader and sync byte.
CWRTON:
    CALL CASSETTE_SELECT_ARG

;; Starts the motor and writes the leader and sync byte.
CASSETTE_WRITE_LEADER:
    LD B,$FF                        ; 255 zero bytes of leader
    XOR A
CSAV1:
    CALL CASSETTE_WRITE
    DJNZ CSAV1
    LD A,$A5                        ; the sync byte
    JR CASSETTE_WRITE

;; Selects the cassette from #-n at HL, starts the motor and waits for the leader and sync byte.
CSRDON:
    CALL CASSETTE_SELECT_ARG

;; Starts the motor and waits for the leader and sync byte.
CASSETTE_READ_LEADER:
    PUSH HL
    XOR A                           ; start with no bits
;; Enters the leader search, shifting tape bits into A until the $A5 sync byte appears, then
;; shows the asterisk in the top-right corner of the screen.
CLOD1:
    CALL CASSETTE_READ_BIT
    CP $A5                          ; the sync byte ends the leader
    JR NZ,CLOD1
    LD A,$2A                        ; an asterisk
    LD [CASSETTE_STATUS_CHAR],A     ; show it in the screen corner
    LD [CASSETTE_BLINK_CHAR],A      ; and blink it as blocks arrive
    POP HL
    RET
;; Ends a SYSTEM tape load: reads the entry address into TEMP, stops the motor and returns to
;; the *? prompt.
ENBLK:
    CALL CADRIN                     ; the entry address of the program
    LD [TEMP],HL                    ; kept for a bare / at the prompt
    CALL CASSETTE_OFF
;; Runs the SYSTEM command, loading a machine-language tape by name at the *? prompt, or running
;; code at an address given as /address.
ST_SYSTEM:
    CALL HOOK_SYSTEM
    LD SP,$4288                     ; a fresh stack for the loader
    CALL CRDO
    LD A,$2A                        ; the * prompt
    CALL OUTDO
    CALL QINLIN
    JP C,RESETR                     ; BREAK leaves SYSTEM
    RST $10                         ; first character typed
    JP Z,SNERR                      ; an empty reply is an error
    CP $2F                          ; a / runs code at an address
    JR Z,GODO
    CALL CSRDON                     ; start the tape, HL at the name typed
;; Enters the SYSTEM loader's search for the $55 header byte that begins a tape's file name.
LOPHD:
    CALL CASSETTE_READ
    CP $55                          ; $55 begins the tape's header
    JR NZ,LOPHD
    LD B,$06                        ; names are up to six characters
;; Enters the SYSTEM loader's comparison of the tape's file name with the one typed, up to six
;; characters; a mismatch resumes the header search.
CHKBYT:
    LD A,[HL]
    OR A                            ; the end of the typed name: it matches
    JR Z,GETDT
    CALL CASSETTE_READ
    CP [HL]
    JR NZ,LOPHD                     ; wrong file: wait for the next header
    INC HL
    DJNZ CHKBYT
GETDT:
    CALL BCASIN
;; Enters the SYSTEM loader's block loop, reading a $3C data block into memory or ending at the
;; $78 entry-address block.
GETDT2:
    CALL CASSETTE_READ
    CP $78                          ; $78 ends the file, the entry address follows
    JR Z,ENBLK
    CP $3C                          ; $3C begins a data block
    JR NZ,GETDT2
    CALL CASSETTE_READ              ; the block's byte count, 0 meaning 256
    LD B,A
    CALL CADRIN                     ; HL = where the block loads
    ADD A,L                         ; the checksum starts with the address bytes
    LD C,A
;; Enters the SYSTEM loader's loop that stores a data block and checks its checksum, showing a C
;; on the screen when it fails.
LDATIN:
    CALL CASSETTE_READ
    LD [HL],A                       ; store the data byte
    INC HL
    ADD A,C                         ; add it to the checksum
    LD C,A
    DJNZ LDATIN
    CALL CASSETTE_READ              ; the block's checksum byte
    CP C
    JR Z,GETDT                      ; good block, blink the asterisk
    LD A,$43                        ; a C shows a checksum error
    LD [CASSETTE_STATUS_CHAR],A
    JR GETDT2

;; Reads a two-byte address from the tape into HL, low byte first.
CADRIN:
    CALL CASSETTE_READ
    LD L,A
    CALL CASSETTE_READ
    LD H,A
    RET

;; Handles /address at the SYSTEM prompt, jumping to the given address or, with none, to the entry
;; address of the last tape loaded.
GODO:
    EX DE,HL
    LD HL,[TEMP]                    ; DE = the last tape's entry address
    EX DE,HL
    RST $10                         ; anything after the slash
    CALL NZ,LINGET                  ; an address was typed
    JR NZ,ST_SYSTEM                 ; junk after the address: back to the prompt
    EX DE,HL
    JP [HL]                         ; run the code

;; Prints the character in A on the current output device (PRTFLG), tracking TTYPOS.
OUTDO:
    PUSH BC
    LD C,A                          ; keep the character
    CALL HOOK_OUTDO
    LD A,[PRTFLG]                   ; 0 screen, 1 printer, negative for the cassette
    OR A
    LD A,C
    POP BC
    JP M,CASSETTE_WRITE             ; -1: write it to tape
    JR NZ,OUTLPT                    ; 1: the printer

;; Shows the character in A on the screen and updates TTYPOS from the cursor column.
OUT2D:
    PUSH DE
    CALL DISPLAY_CHAR
    PUSH AF                         ; keep the character
    CALL DSPPOS
    LD [TTYPOS],A                   ; the column PRINT tracks
    POP AF
    POP DE
    RET

;; Returns in A the cursor column, halved in 32-character mode.
DSPPOS:
    LD A,[PORT_FF_IMAGE]            ; port $FF bit 3 is 32-character mode
    AND $08
    LD A,[CURSOR_ADDRESS]           ; low byte of the cursor address
    JR Z,NT32PS
    RRCA                            ; two cells per character in this mode
    AND $1F

NT32PS:
    AND $3F                         ; column within the 64-character line
    RET

;; Scans the keyboard, returning the character of a newly pressed key in A, or zero.
ISCHAR:
    CALL HOOK_KEY_SCAN
    PUSH DE
    CALL KBD_SCAN
    POP DE
    RET

;; Reads a line from the keyboard into the input buffer at BUFPNT, ending it with a zero byte.
;; Out:   HL = the buffer address minus one, carry = BREAK was pressed
INLIN:
    XOR A                           ; no held key, and start at column 0
    LD [CHARC],A
    LD [TTYPOS],A
    CALL HOOK_INLIN
    PUSH BC
    LD HL,[BUFPNT]                  ; the input buffer
    LD B,$F0                        ; at most 240 characters
    CALL KEYIN
    PUSH AF                         ; keep the carry from BREAK
    LD C,B                          ; B = the count typed
    LD B,$00
    ADD HL,BC
    LD [HL],$00                     ; end the line with a zero
    LD HL,[BUFPNT]
    POP AF
    POP BC
    DEC HL                          ; one before the line, ready for CHRGTR
    RET C                           ; carry: BREAK was pressed
    XOR A                           ; clear the carry: a line was typed
    RET

;; Waits for a key and returns its character in A.
INCHR:
    CALL ISCHAR
    OR A                            ; zero means no key yet
    RET NZ
    JR INCHR

;; Sends output back to the screen and ends a pending printer line with a carriage return.
FINLPT:
    XOR A                           ; output back to the screen
    LD [PRTFLG],A
    LD A,[LPTPOS]                   ; the printer column
    OR A
    RET Z                           ; at the start of a line already
    LD A,$0D                        ; end the printer line
    PUSH DE
    CALL OUTLPT
    POP DE
    RET

;; Prints the character in A, turning LF into CR and tracking the printer column at $409B.
OUTLPT:
    PUSH AF
    PUSH DE
    PUSH BC
    LD C,A                          ; keep the character
    LD E,$00                        ; the column after a form feed or CR
    CP $0C                          ; a form feed starts a new page
    JR Z,LZRPOS
    CP $0A                          ; a line feed
    JR NZ,LZRNOT
    LD A,$0D                        ; is sent as a carriage return
    LD C,A

LZRNOT:
    CP $0D                          ; a carriage return also resets the column
    JR Z,LZRPOS
    LD A,[LPTPOS]
    INC A                           ; any other character advances the column
    LD E,A

LZRPOS:
    LD A,E
    LD [LPTPOS],A
    LD A,C
    CALL PRINTER_CHAR
    POP BC
    POP DE
    POP AF
    RET

;; Calls the driver of the control block DE addresses for the request in B (1 get, 2 put, 4 control).
CIO:
    PUSH HL
    PUSH IX
    PUSH DE
    POP IX
    PUSH DE
    LD HL,$03DD                     ; drivers return through CIORTN
    PUSH HL
    LD C,A                          ; C = the byte to write
    LD A,[DE]                       ; the DCB's type byte: the requests it accepts
    AND B
    CP B
    JP NZ,DCB_REQUEST_HOOK          ; a request the device cannot take goes to the DOS
    CP $02                          ; flags for the driver: C get, Z put, else control
    LD L,[IX+$01]                   ; HL = the driver's address from the DCB
    LD H,[IX+$02]
    JP [HL]

CIORTN:
    POP DE
    POP IX
    POP HL
    POP BC                          ; the BC saved by GET, PUT or CTL
    RET

;; Scans the rows against KEYBOARD_IMAGE and turns a newly pressed key into its character.
KEY:
    LD HL,KEYBOARD_IMAGE            ; how each row looked at the last scan
    LD BC,KEYBOARD_ROW0             ; row 0 of the keyboard matrix
    LD D,$00                        ; D = the row number
KEYLP:
    LD A,[BC]
    LD E,A                          ; E = the row as it is now
    XOR [HL]                        ; bits that changed since the last scan
    LD [HL],E                       ; remember the row for the next scan
    AND E                           ; only keys newly pressed
.if REVISION = 12
    JR NZ,KEYBOARD_DRIVER_2
.else
    JR NZ,KEYDWN
.endif
    INC D                           ; next row
    INC L
    RLC C                           ; next row's address bit
    JP P,KEYLP                      ; stop before row 7, the shift row
    RET
.if REVISION = 12
KEYBOARD_DRIVER_2:
.else
;; Enters the keyboard driver with a newly pressed key, turning its row and column into a key
;; number in D (1.3 first rechecks it through KEY_DEBOUNCE).
KEYDWN:
.endif
    LD E,A                          ; E = the new key's column bit
.if REVISION = 12
    LD A,D
    RLCA
    RLCA
.else
    JP KEY_DEBOUNCE
KEYBOARD_DRIVER_12:
.endif
    RLCA
    LD D,A                          ; D = row times 8, the row's first key number
    LD C,$01                        ; find which column bit is set
KEYDLP:
    LD A,C
    AND E
    JR NZ,KEYFND
    INC D                           ; D = row*8 + column, the key number
    RLC C
    JR KEYDLP
;; Enters the keyboard driver with the key number in D, translating a letter or @ key with shift
;; and the shift-down-arrow control combination, and passing other keys on.
KEYFND:
    LD A,[KEYBOARD_ROW7]            ; row 7: bit 0 is shift
    LD B,A
    LD A,D                          ; keys 0 to 26 are @ and the letters
    ADD A,$40
    CP $60                          ; past the letter rows
    JR NC,KEYNAL
    RRC B                           ; shift into carry
    JR NC,KEYRTN                    ; unshifted: upper case
    ADD A,$20                       ; shift gives lower case
    LD D,A
    LD A,[KEYBOARD_ROW6]            ; row 6 bit 4 is the down arrow
    AND $10
    JR Z,KEYRT2                     ; no down arrow: keep the lower case letter
    LD A,D
    SUB $60                         ; shift, down arrow and a letter: a control code
    JR KEYRTN
;; Translates a digit or punctuation key, applying shift to choose its character.
KEYNAL:
    SUB $70                         ; keys from 48 on are the ENTER and arrow row
    JR NC,KEYSPL
    ADD A,$40                       ; digits and punctuation from $30
    CP $3C                          ; the , - . / keys
    JR C,KEYINV
    XOR $10                         ; move down to $2C-$2F
KEYINV:
    RRC B                           ; shift into carry
    JR NC,KEYRTN
    XOR $10                         ; shifted: the character $10 away
    JR KEYRTN
;; Translates a key from the ENTER, arrow and space row through KEYTAB, using the shifted entry
;; when shift is held.
KEYSPL:
    RLCA                            ; two KEYTAB entries per key
    RRC B
    JR NC,KEYNSF
    INC A                           ; use the shifted entry
KEYNSF:
    LD HL,KEYTAB
    LD C,A
    LD B,$00
    ADD HL,BC
    LD A,[HL]
;; Ends the keyboard driver with the character in A: delays to debounce, and passes BREAK to
;; the DOS through RST $28.
KEYRTN:
    LD D,A
KEYRT2:
    LD BC,$0DAC                     ; debounce delay of about 50 ms
    CALL DELAY
    LD A,D
    CP $01                          ; code 1 is BREAK
    RET NZ
    RST $28                         ; let the DOS see BREAK
    RET

;; Shows a character, moving the cursor and scrolling, and handles the control codes.
DSP:
    LD L,[IX+$03]                   ; HL = the cursor address from the DCB
    LD H,[IX+$04]
    JR C,DSPRD                      ; carry: a read request
    LD A,[IX+$05]                   ; the character under the cursor, 0 when it is off
    OR A
    JR Z,DSPGRP                     ; cursor off: nothing to put back
    LD [HL],A                       ; put back the character the cursor covered
DSPGRP:
    LD A,C                          ; the character to show
    CP $20                          ; below $20 is a control code
    JP C,DSPCTL
    CP $80                          ; $80 up: graphics or space compression
    JR NC,DSPGSC
    CP $40                          ; $20-$3F are stored as is
    JR C,DSPCHR
    SUB $40                         ; @ to _ are stored as $00-$1F
    CP $20
    JR C,DSPCHR
    SUB $20                         ; lower case shows as upper case
DSPCHR:
    CALL DSPOUT
DSPSKP:
    LD A,H                          ; keep HL within video memory, $3C00-$3FFF
    AND $03
    OR $3C
    LD H,A
    LD D,[HL]                       ; D = the character at the new cursor position
    LD A,[IX+$05]
    OR A
    JR Z,DSPRTN                     ; cursor off: nothing to draw
    LD [IX+$05],D                   ; save what the cursor will cover
    LD [HL],$5F                     ; draw the underline cursor
DSPRTN:
    LD [IX+$03],L                   ; save the cursor address in the DCB
    LD [IX+$04],H
    LD A,C                          ; return the character shown
    RET
;; Returns in A the character at the cursor, or the one the cursor covers when it is shown.
DSPRD:
    LD A,[IX+$05]
    OR A
    RET NZ                          ; the cursor is showing: return what it covers
    LD A,[HL]
    RET
;; Moves the cursor in HL to the start of its line (control code $1D).
DSPBOL:
    LD A,L
    AND $C0
    LD L,A
    RET
;; Shows a character of $80 or above: a graphics block as is, or $C0 plus n as n spaces.
DSPGSC:
    CP $C0                          ; $80-$BF are graphics, shown as is
    JR C,DSPCHR
    SUB $C0
    JR Z,DSPSKP                     ; $C0 is no spaces
    LD B,A                          ; B = the number of spaces
;; Enters the loop that shows the B spaces a space compression code stands for.
DSPSPC:
    LD A,$20
    CALL DSPOUT
    DJNZ DSPSPC
    JR DSPSKP
;; Turns the cursor on (control code $0E), saving the character under it.
DSPCON:
    LD A,[HL]                       ; the character the cursor will cover
DSPCN2:
    LD [IX+$05],A
    RET
;; Turns the cursor off (control code $0F).
DSPCOF:
    XOR A                           ; zero marks the cursor off
    JR DSPCN2
;; Homes the cursor to the top left of the screen and returns to 64-character mode (code $1C).
DSPHOM:
    LD HL,VIDEO
    LD A,[PORT_FF_IMAGE]
    AND $F7                         ; clear bit 3: 64-character mode
    LD [PORT_FF_IMAGE],A
    OUT [$FF],A
    RET
;; Backspaces the cursor and blanks the character there (control code $08).
DSPBSP:
    DEC HL
    LD A,[PORT_FF_IMAGE]
    AND $08                         ; 32-character mode uses two cells a character
    JR Z,DSPBS2
    DEC HL
DSPBS2:
    LD [HL],$20                     ; blank the character
    RET
;; Moves the cursor left one character, wrapping within the line (control code $18).
DSPLFT:
    LD A,[PORT_FF_IMAGE]
    AND $08
    CALL NZ,DSPLF2                  ; move twice in 32-character mode

;; Moves the cursor in HL back one position, wrapping within the row; other cursor codes follow.
DSPLF2:
    LD A,L
    AND $3F                         ; column within the line
    DEC HL
    RET NZ                          ; it was not column 0: done

;; Moves the cursor in HL down one line (control code $1A).
DSPDWN:
    LD DE,KBLINE                    ; KBLINE is at $0040, one screen line
    ADD HL,DE                       ; wrapped back: down to this line's end
    RET

;; Moves the cursor right one character, wrapping within the line (control code $19).
DSPRHT:
    INC HL
    LD A,L
    AND $3F                         ; column within the line
    RET NZ                          ; still on the line

;; Moves the cursor in HL up one line (control code $1B).
DSPUP:
    LD DE,$FFC0                     ; minus 64: up one line
    ADD HL,DE
    RET

;; Switches the screen to 32-character mode, moving the cursor to an even position (code $17).
DSPETB:
    LD A,[PORT_FF_IMAGE]
    OR $08                          ; set bit 3: 32-character mode
    LD [PORT_FF_IMAGE],A
    OUT [$FF],A
    INC HL                          ; round the cursor up to an even cell
    LD A,L
    AND $FE
    LD L,A
    RET

;; Carries out the control code in A for the video driver, ignoring codes it does not use.
DSPCTL:
    LD DE,$0480                     ; DSPSKP, to redraw the cursor afterward
    PUSH DE
    CP $08
    JR Z,DSPBSP
    CP $0A
    RET C                           ; other codes below $0A are ignored
    CP $0E
    JR C,DSPCR                      ; $0A-$0D: new line
    JR Z,DSPCON
    CP $0F
    JR Z,DSPCOF
    CP $17
    JR Z,DSPETB
    CP $18
    JR Z,DSPLFT
    CP $19
    JR Z,DSPRHT
    CP $1A
    JR Z,DSPDWN
    CP $1B
    JR Z,DSPUP
    CP $1C
    JR Z,DSPHOM
    CP $1D
    JP Z,DSPBOL
    CP $1E
    JR Z,DSPEOL
    CP $1F
    JR Z,DSPEOF
    RET

;; Stores A at the cursor HL and advances it, scrolling the screen up past the last line.
DSPOUT:
    LD [HL],A
    INC HL
    LD A,[PORT_FF_IMAGE]
    AND $08                         ; 32-character mode skips the odd cell
    JR Z,DSPOT2
    INC HL

DSPOT2:
    LD A,H
    CP $40                          ; past the end of the screen
    RET NZ
    LD DE,$FFC0                     ; back to the start of the last line
    ADD HL,DE
    PUSH HL                         ; the cursor to restore after the scroll

;; Scrolls the screen up one line and blanks the bottom line.
DSPROL:
    LD DE,VIDEO
    LD HL,$3C40                     ; the second screen line
    PUSH BC
    LD BC,$03C0                     ; 15 lines of 64
    LDIR
    POP BC
    EX DE,HL                        ; HL = the bottom line, to be blanked
    JR DSPERF

;; Moves the cursor to the start of the next line and blanks it, scrolling at the bottom of the
;; screen (control codes $0A to $0D).
DSPCR:
    LD A,L
    AND $C0                         ; back to the start of this line
    LD L,A
    PUSH HL                         ; returned as the cursor if the screen scrolls
    LD DE,KBLINE                    ; KBLINE is at $0040, one screen line
    ADD HL,DE
    LD A,H                          ; moved off the bottom: scroll
    CP $40
    JR Z,DSPROL
    POP DE                          ; drop the old line start

;; Blanks from the cursor to the end of its line (control code $1E).
DSPEOL:
    PUSH HL                         ; the cursor to restore
    LD D,H
    LD A,L
    OR $3F                          ; E = the last column of the line
    LD E,A
    INC DE                          ; one past it
    JR DSPERA

;; Blanks from the cursor to the end of the screen (control code $1F).
DSPEOF:
    PUSH HL

DSPERF:
    LD DE,RST08_VECTOR              ; $4000, the end of video memory

;; Fills the screen with spaces from HL up to DE, then restores HL from the stack.
DSPERA:
    LD [HL],$20
    INC HL
    LD A,H
    CP D
    JR NZ,DSPERA
    LD A,L
    CP E
    JR NZ,DSPERA
    POP HL
    RET

;; Waits for the printer to be ready and sends it a character.
PRT:
    LD A,C                          ; C = the character, zero asks for the status
    OR A
    JR Z,PRTSTA
    CP $0B                          ; $0B: skip to the top of the next page
    JR Z,PRTVT
    CP $0C                          ; $0C: form feed
    JR NZ,PRTIT
    XOR A
    OR [IX+$03]                     ; page length 0: let the printer feed the page
    JR Z,PRTIT
PRTVT:
    LD A,[IX+$03]                   ; lines left on the page
    SUB [IX+$04]
    LD B,A
PRTFF:
    CALL PRTSTA
    JR NZ,PRTFF
    LD A,$0A                        ; a line feed
    LD [PRINTER_STATUS],A
    DJNZ PRTFF                      ; until the page is done
    JR PRTOP
PRTIT:
    PUSH AF                         ; keep the character
PRTIT2:
    CALL PRTSTA
    JR NZ,PRTIT2                    ; wait while the printer is busy
    POP AF
    LD [PRINTER_STATUS],A
    CP $0D                          ; a carriage return counts a line
    RET NZ
    INC [IX+$04]                    ; lines printed on this page
    LD A,[IX+$04]
    CP [IX+$03]                     ; page full
    LD A,C                          ; return the character
    RET NZ
PRTOP:
    LD [IX+$04],$00                 ; a new page begins
    RET

;; Tests the printer status: Z when the printer is ready for a character.
PRTSTA:
    LD A,[PRINTER_STATUS]
    AND $F0                         ; busy, paper, select and fault bits
    CP $30                          ; ready: not busy, paper in, selected, no fault
    RET

;; The line editor behind KBLINE: backspace, line delete, TAB and BREAK.
KEYIN:
    PUSH HL                         ; keep the buffer start
    LD A,$0E                        ; $0E turns the cursor on
    CALL DISPLAY_CHAR
    LD C,B                          ; C = the buffer size, B the room left
;; Enters KEYIN's loop that waits for a key and stores it or carries out its editing action.
KLNNXT:
    CALL KBWAIT
    CP $20                          ; printable characters are stored
    JR NC,KLNCHR
    CP $0D
    JP Z,KLNCR
    CP $1F                          ; the CLEAR key
    JR Z,KLNCLR
    CP $01                          ; the BREAK key
    JR Z,KLNBRK
    LD DE,$05E0                     ; KLNNXT: the editing keys return there
    PUSH DE
    CP $08                          ; left arrow: backspace
    JR Z,KLNBSP
    CP $18                          ; shift-left arrow: delete the line
    JR Z,KLNCAN
    CP $09                          ; right arrow: tab
    JR Z,KLNHT
    CP $19                          ; shift-right arrow: 32-character mode
    JR Z,KLNETB
    CP $0A                          ; down arrow is stored as a line feed
    RET NZ                          ; other control codes are ignored
    POP DE                          ; drop the KLNNXT return
;; Stores the character in A in the line buffer and echoes it, unless the buffer is full.
KLNCHR:
    LD [HL],A
    LD A,B
    OR A
    JR Z,KLNNXT                     ; buffer full: the character is not kept
    LD A,[HL]
    INC HL
    CALL DISPLAY_CHAR
    DEC B                           ; room for one less
    JR KLNNXT
;; Clears the screen and starts the line over with an empty buffer (the CLEAR key).
KLNCLR:
    CALL CLS
    LD B,C                          ; all the room back
    POP HL                          ; HL = the buffer start again
    PUSH HL
    JP KLNNXT
;; Enters KEYIN's line delete loop, backspacing over each character typed.
KLNCNL:
    CALL KLNBSP
    DEC HL                          ; look at the character before
    LD A,[HL]
    INC HL
    CP $0A
    RET Z                           ; stop at a line feed
;; Deletes the line typed so far, stopping at its start or at a line feed (shift-left arrow).
KLNCAN:
    LD A,B
    CP C                            ; back at the start of the line
    JR NZ,KLNCNL
    RET

;; Removes the last character typed into the KBLINE buffer and backspaces the screen.
KLNBSP:
    LD A,B
    CP C                            ; nothing typed to remove
    RET Z
    DEC HL
    LD A,[HL]
    CP $0A                          ; a line feed cannot be backed over
    INC HL
    RET Z
    DEC HL
    LD A,$08                        ; backspace on the screen
    CALL DISPLAY_CHAR
    INC B                           ; one more character of room
    RET

;; Switches the screen to 32-character mode (shift-right arrow).
KLNETB:
    LD A,$17
    JP DISPLAY_CHAR

;; Moves to the next multiple of eight columns by storing spaces (the right arrow).
KLNHT:
    CALL DSPPOS
    AND $07                         ; column within its tab stop
    CPL
    INC A
    ADD A,$08                       ; A = spaces to the next multiple of eight
    LD E,A

;; Enters KEYIN's tab loop, storing and echoing the E spaces that remain while there is room.
KLNHTL:
    LD A,B
    OR A
    RET Z                           ; buffer full
    LD A,$20
    LD [HL],A
    INC HL
    PUSH DE
    CALL DISPLAY_CHAR
    POP DE
    DEC B
    DEC E
    RET Z                           ; reached the tab stop
    JR KLNHTL

;; Ends the line for the BREAK key, returning with carry set.
KLNBRK:
    SCF                             ; carry marks BREAK

;; Ends the line with a carriage return and turns the cursor off.
;; Out:   HL = the buffer, B = the line's length, carry = BREAK was pressed
KLNCR:
    PUSH AF                         ; keep the carry
    LD A,$0D
    LD [HL],A                       ; end the buffer with a CR, not counted
    CALL DISPLAY_CHAR
    LD A,$0F                        ; $0F turns the cursor off
    CALL DISPLAY_CHAR
    LD A,C
    SUB B                           ; B = the number of characters typed
    LD B,A
    POP AF
    POP HL                          ; HL = the buffer start
    RET

;; Copies RAM_VECTORS to $4000 and clears the rest, then boots from drive 0 when a disk controller
;; answers and BREAK is not held, or starts BASIC.
INIT:
    OUT [$FF],A                     ; A is 0: cassette off, 64-character mode
;; Enters the power-up code at the copy of <RAM_VECTORS> into RAM at $4000.
REBLK:
    LD HL,RAM_VECTORS
    LD DE,RST08_VECTOR              ; copied to $4000
    LD BC,$0036                     ; 54 bytes
    LDIR
    DEC A                           ; repeat the copy 128 times as a power-up delay
    DEC A
    JR NZ,REBLK
    LD B,$27                        ; the next 39 bytes
CLRAM:
    LD [DE],A                       ; A is 0 here
    INC DE
    DJNZ CLRAM

;; Starts BASIC when BREAK is held or no disk controller answers, and otherwise boots from disk.
CHKMAN:
    LD A,[KEYBOARD_ROW6]            ; row 6 bit 2 is BREAK
    AND $04
    JP NZ,INIT2                     ; BREAK held: no disk boot
    LD SP,$407D                     ; a stack for the boot
    LD A,[FDC_STATUS]               ; reads $FF or $00 with no disk controller
    INC A
    CP $02
    JP C,INIT2                      ; no controller: start BASIC
;; Reads the boot sector from drive 0 into $4200 and jumps to it.
BOOT:
    LD A,$01                        ; select drive 0
    LD [DRIVE_SELECT],A
    LD HL,FDC_STATUS
    LD DE,FDC_DATA
    LD [HL],$03                     ; $03: restore the head to track 0
    LD BC,RESET                     ; BC = 0: the longest DELAY, about a second
    CALL DELAY
BOOTDL:
    BIT 0,[HL]                      ; wait while the controller is busy
    JR NZ,BOOTDL
    XOR A
    LD [FDC_SECTOR],A               ; sector 0
    LD BC,$4200                     ; where the boot sector goes
    LD A,$8C                        ; $8C: read a sector
    LD [HL],A
BOOTLP:
    BIT 1,[HL]                      ; wait for a data byte
    JR Z,BOOTLP
    LD A,[DE]
    LD [BC],A
    INC C                           ; until 256 bytes are read
    JR NZ,BOOTLP
    JP BOOT_SECTOR

;; Returns to BASIC's READY prompt through <ERESET>.
RESETR:
    LD BC,$1A18
    JP ERESET

;; Holds the RST vectors and keyboard, video and printer control blocks copied to $4000 at power-up.
RAM_VECTORS:
    JP SYNCHK                       ; $4000 (RST08_VECTOR): RST $08
    JP CHRGTR                       ; $4003 (RST10_VECTOR): RST $10
    JP DCOMPR                       ; $4006 (RST18_VECTOR): RST $18
    JP GETYPR                       ; $4009 (RST20_VECTOR): RST $20
    RET                             ; RST $28: DOS requests, which Level II ignores
    NOP
    NOP
    RET                             ; RST $30: debugger breakpoints
    NOP
    NOP
    EI                              ; RST $38: interrupts, which Level II leaves disabled
    RET
    NOP
    DCB $01, KEY, $0000, $00, "KI"  ; the keyboard's device control block
    DCB $07, DSP, $3C00, $00, "DO"     ; the video's device control block
    DCB $06, PRT, $0043, $00, "PR"   ; the printer's device control block
    JP $5000
    RST $00
    NOP
    NOP
    LD A,$00
    RET

;; Adds one half, the constant at $1380, to FAC.
FADDH:
    LD HL,$1380                     ; the constant 0.5

;; Adds the single-precision number at HL to FAC.
;; In:    HL = the address of the number
FADDS:
    CALL MOVRM
    JR FADD

;; Subtracts FAC from the single-precision number at HL, leaving the difference in FAC.
;; In:    HL = the address of the number
FSUBS:
    CALL MOVRM

;; Subtracts FAC from BCDE, leaving the difference in FAC.
FSUB:
    CALL NEG

;; Adds BCDE to FAC, leaving the sum in FAC.
FADD:
    LD A,B
    OR A                            ; BCDE is zero: FAC is the sum
    RET Z
    LD A,[FAC]
    OR A
    JP Z,MOVFR                      ; FAC is zero: the sum is BCDE
    SUB B                           ; difference of the exponents
    JR NC,FADD1                     ; FAC is the larger already
    CPL                             ; make the difference positive
    INC A
    EX DE,HL                        ; swap FAC and BCDE so BCDE is the smaller
    CALL PUSHF
    EX DE,HL
    CALL MOVFR
    POP BC
    POP DE
;; Enters FADD with the smaller operand in BCDE and the exponent difference in A, aligning and
;; combining the mantissas.
FADD1:
    CP $19                          ; 24 or more bits apart: BCDE adds nothing
    RET NC
    PUSH AF                         ; keep the shift count
    CALL UNPACK                     ; restore the implied bits, A = the signs compared
    LD H,A                          ; keep the sign comparison
    POP AF
    CALL SHIFTR                     ; align BCDE to FAC's exponent
    OR H
    LD HL,FACLO
    JP P,FADD3                      ; signs differ: subtract instead
    CALL FADDA                      ; same sign: add the mantissas
    JP NC,ROUND                     ; no carry out: round it
    INC HL
    INC [HL]                        ; a carry out raises the exponent
    JP Z,OVERR                      ; too large
    LD L,$01                        ; take the carry in with a one-bit shift
    CALL SHRADD
    JR ROUND
;; Subtracts the mantissa CDEB from the one at HL for FADD, then normalizes and rounds the result.
FADD3:
    XOR A                           ; B = 0 minus the extra low byte
    SUB B
    LD B,A
    LD A,[HL]                       ; subtract with borrow, byte by byte
    SBC A,E
    LD E,A
    INC HL
    LD A,[HL]
    SBC A,D
    LD D,A
    INC HL
    LD A,[HL]
    SBC A,C
    LD C,A

;; Negates the mantissa when carry is set, then normalizes and rounds it (NORMAL at _1).
FADFLT:
    CALL C,NEGR                     ; a borrow means the result changed sign

;; Normalizes the mantissa CDEB and rounds it into FAC, making FAC zero on underflow.
NORMAL:
    LD L,B                          ; HL holds the low bytes while shifting
    LD H,E
    XOR A                           ; A = the shift so far, in bits

;; Enters NORMAL's loop that shifts the mantissa left a byte at a time while its top byte is zero.
NORM1:
    LD B,A
    LD A,C
    OR A                            ; top byte not zero: shift by bits instead
    JR NZ,NORM3
    LD C,D                          ; shift the mantissa up a whole byte
    LD D,H
    LD H,L
    LD L,A
    LD A,B
    SUB $08                         ; eight more bits of shift
    CP $E0                          ; shifted 32 bits: the mantissa was zero
    JR NZ,NORM1

;; Makes FAC zero by clearing its exponent.
ZERO:
    XOR A
;; Stores A as FAC's exponent; entered with zero, it makes FAC zero.
ZERO0:
    LD [FAC],A
    RET
;; Enters NORMAL's loop that shifts the mantissa left a bit at a time, then adjusts the exponent.
NORM2:
    DEC B                           ; one more bit of shift
    ADD HL,HL                       ; shift the mantissa left a bit
    LD A,D
    RLA
    LD D,A
    LD A,C
    ADC A,A
    LD C,A
NORM3:
    JP P,NORM2                      ; until the top bit is set
    LD A,B                          ; A = the total shift, negative
    LD E,H                          ; back into CDEB
    LD B,L
    OR A
    JR Z,ROUND                      ; no shift: just round
    LD HL,FAC
    ADD A,[HL]                      ; lower the exponent by the shift
    LD [HL],A
    JR NC,ZERO                      ; below the smallest exponent: zero
    RET Z                           ; an exponent of zero is zero
;; Rounds the mantissa CDE by the top bit of B and stores the number in FAC with its sign.
ROUND:
    LD A,B                          ; the top bit of B decides the rounding
ROUNDB:
    LD HL,FAC
    OR A
    CALL M,ROUNDA                   ; round up when B is $80 or more
    LD B,[HL]                       ; B = the exponent
    INC HL
    LD A,[HL]
    AND $80                         ; the result's sign bit
    XOR C                           ; put the sign in the mantissa's top bit
    LD C,A
    JP MOVFR

;; Increments the mantissa CDE for rounding, bumping the exponent at HL; OV on overflow.
ROUNDA:
    INC E
    RET NZ
    INC D
    RET NZ
    INC C
    RET NZ
    LD C,$80                        ; the mantissa wrapped: make it $800000
    INC [HL]                        ; and raise the exponent
    RET NZ                          ; the exponent did not overflow
;; Raises an ?OV ERROR.
OVERR:
    LD E,ERR_OV
    JP ERROR

;; Adds the mantissa at HL to CDE.
FADDA:
    LD A,[HL]
    ADD A,E
    LD E,A
    INC HL
    LD A,[HL]
    ADC A,D
    LD D,A
    INC HL
    LD A,[HL]
    ADC A,C
    LD C,A
    RET

;; Negates the mantissa CDEB and complements the result sign at $4125.
NEGR:
    LD HL,$4125                     ; the result's sign byte
    LD A,[HL]
    CPL                             ; flip it
    LD [HL],A
    XOR A                           ; A and L = 0, to subtract from
    LD L,A
    SUB B                           ; negate CDEB as one 32-bit number
    LD B,A
    LD A,L
    SBC A,E
    LD E,A
    LD A,L
    SBC A,D
    LD D,A
    LD A,L
    SBC A,C
    LD C,A
    RET

;; Shifts the mantissa CDEB right by A bits.
SHIFTR:
    LD B,$00                        ; B collects the bits shifted out, used later for rounding

SHFTR1:
    SUB $08                         ; are 8 or more bits still to be shifted?
    JR C,SHFTR2                     ; fewer than 8 left, finish one bit at a time
    LD B,E                          ; move the mantissa down a whole byte, low byte into B
    LD E,D
    LD D,C
    LD C,$00                        ; a zero fills the vacated top byte
    JR SHFTR1

;; Finishes a right shift of CDEB one bit at a time, with A + 9 giving the leftover bit count plus one.
SHFTR2:
    ADD A,$09                       ; undo the extra subtract, leaving bits to go plus one
    LD L,A

SHFTR3:
    XOR A                           ; clear carry so a zero enters the top bit
    DEC L
    RET Z
    LD A,C

;; Rotates the carry and mantissa CDEB right one bit, repeating while L counts down.
SHRADD:
    RRA                             ; carry enters bit 7 of the high byte
    LD C,A
    LD A,D
    RRA
    LD D,A
    LD A,E
    RRA
    LD E,A
    LD A,B
    RRA
    LD B,A
    JR SHFTR3                       ; next bit

;; Holds the single-precision constant 1.0.
FONE:
    .byte $00, $00, $00, $81

;; Holds the LOG polynomial's coefficient table: a count of 3 followed by three single-precision values.
LOGCN2:
    .byte $03, $AA, $56, $19, $80, $F1, $22, $76, $80, $45, $AA, $38, $82
;; Replaces the FAC with its natural logarithm (the LOG function); FC error unless it is positive.
FN_LOG:
    CALL SIGN
    OR A                            ; sets parity from the sign result: PE means negative
    JP PE,FCERR                     ; LOG of zero or a negative number is illegal
    LD HL,FAC
    LD A,[HL]                       ; A = the argument's exponent
    LD BC,$8035                     ; BC DE = SQR(.5)
    LD DE,$04F3
    SUB B                           ; A = the binary exponent, minus the bias of SQR(.5)
    PUSH AF                         ; kept to add on as the integer part of the log
    LD [HL],B                       ; force the mantissa into the range .5 to 1
    PUSH DE
    PUSH BC
    CALL FADD                       ; mantissa + SQR(.5)
    POP BC
    POP DE
    INC B                           ; exponent one higher turns SQR(.5) into SQR(2)
    CALL FDIV                       ; SQR(2) / (mantissa + SQR(.5))
    LD HL,$07F8                     ; HL = FONE, the constant 1.0
    CALL FSUBS                      ; 1 minus the quotient gives the series variable
    LD HL,$07FC                     ; HL = LOGCN2, the odd-power coefficient table
    CALL POLYX
    LD BC,$8080                     ; BC DE = -0.5
    LD DE,RESET
    CALL FADD
    POP AF                          ; A = the binary exponent saved at the start
    CALL FINLOG                     ; add it on, giving log base 2

;; Multiplies the single-precision accumulator by ln 2.
MULLN2:
    LD BC,$8031                     ; BC DE = ln 2
    LD DE,$7218

;; Multiplies BCDE by the single-precision FAC, leaving the product in the FAC.
FMULT:
    CALL SIGN
    RET Z                           ; a zero multiplier makes the product zero
    LD L,$00                        ; L = 0 tells MULDIV this is a multiply
    CALL MULDIV
    LD A,C                          ; keep the multiplicand mantissa C D E in memory
    LD [FMLTT1],A
    EX DE,HL
    LD [FMLTT2],HL
    LD BC,RESET                     ; clear the product accumulator C D E B
    LD D,B
    LD E,B
    LD HL,$0765                     ; final return goes to the normalizer
    PUSH HL
    LD HL,$0869                     ; two returns to FMULT2 make three passes in all
    PUSH HL
    PUSH HL
    LD HL,FACLO                     ; start with the FAC's low mantissa byte

FMULT2:
    LD A,[HL]                       ; A = the next multiplier byte
    INC HL
    OR A
    JR Z,FMULT3                     ; a zero byte just shifts the product a whole byte
    PUSH HL                         ; keep the pointer to the multiplier bytes
    LD L,$08                        ; L counts the 8 bits of this byte
;; Runs FMULT's bit loop on the multiplier byte in A, adding the multiplicand into CDEB for each set
;; bit and shifting the product right; L counts the bits.
FMULT4:
    RRA                             ; next multiplier bit into carry
    LD H,A                          ; H keeps the multiplier bits still to test
    LD A,C
    JR NC,FMULT5                    ; bit clear, only shift the product
    PUSH HL
    LD HL,[FMLTT2]                  ; add the multiplicand into the product
    ADD HL,DE
    EX DE,HL
    POP HL
    LD A,[FMLTT1]
    ADC A,C
FMULT5:
    RRA                             ; shift the product right, carry entering the top
    LD C,A
    LD A,D
    RRA
    LD D,A
    LD A,E
    RRA
    LD E,A
    LD A,B
    RRA
    LD B,A
    DEC L
    LD A,H                          ; A = the remaining multiplier bits
    JR NZ,FMULT4
POPHRT:
    POP HL                          ; restore the multiplier pointer, then do the next byte
    RET
;; Shifts the product CDEB right one whole byte with A entering C, for a zero multiplier byte.
FMULT3:
    LD B,E
    LD E,D
    LD D,C
    LD C,A
    RET

;; Divides the single-precision accumulator by 10 (FDIVT at _1 pops the dividend first).
DIV10:
    CALL PUSHF                      ; save the dividend on the stack
    LD HL,$0DD8                     ; HL = the constant 10.0
    CALL MOVFM

;; Pops the dividend into BCDE and falls into FDIV to divide it by the FAC.
FDIVT:
    POP BC                          ; recover the dividend in BCDE
    POP DE

;; Divides BCDE by the single-precision accumulator, leaving the quotient in it.
FDIV:
    CALL SIGN
    JP Z,DV0ERR                     ; dividing by zero is a /0 error
    LD L,$FF                        ; L = $FF tells MULDIV this is a divide
    CALL MULDIV
    INC [HL]                        ; add 2 to the exponent to suit the divide loop
    INC [HL]
    DEC HL                          ; copy the divisor mantissa where FDIVC subtracts it
    LD A,[HL]
    LD [DIVIDE_SUB_HI],A
    DEC HL
    LD A,[HL]
    LD [DIVIDE_SUB_MID],A
    DEC HL
    LD A,[HL]
    LD [DIVIDE_SUB_LO],A
    LD B,C                          ; B H L = the dividend, the starting remainder
    EX DE,HL
    XOR A                           ; clear C D E, which collect the quotient bits
    LD C,A
    LD D,A
    LD E,A
    LD [DIVIDE_EXTRA_BYTE],A

;; Enters FDIV's loop, trying a subtraction of the divisor from the remainder for the next quotient bit.
FDIV1:
    PUSH HL                         ; save the remainder in case the divisor does not fit
    PUSH BC
    LD A,L                          ; A = low remainder byte for FDIVC
    CALL FDIVC                      ; subtract the divisor from the remainder
    SBC A,$00                       ; carry out of the extra byte means it did not fit
    CCF
    JR NC,FDIV2                     ; did not fit, restore the remainder, quotient bit 0
    LD [DIVIDE_EXTRA_BYTE],A        ; it fitted, keep the new remainder
    POP AF                          ; discard the saved old remainder
    POP AF
    SCF                             ; this quotient bit is a one
    .byte $D2                       ; JP NC,nn: skips the next instruction

;; Continues FDIV's loop: rounds once the quotient is full, else shifts the quotient and remainder left
;; and repeats (OV error if the exponent runs out).
FDIV2:
    POP BC
    POP HL
    LD A,C                          ; is the quotient's top bit set yet?
    INC A
    DEC A
    RRA                             ; moves carry aside, keeping the flags of C
    JP M,ROUNDB                     ; quotient is complete, round it into the FAC
    RLA                             ; carry back = the new quotient bit
    LD A,E                          ; shift the bit into the quotient C D E
    RLA
    LD E,A
    LD A,D
    RLA
    LD D,A
    LD A,C
    RLA
    LD C,A
    ADD HL,HL                       ; shift the remainder left one place
    LD A,B
    RLA
    LD B,A
    LD A,[DIVIDE_EXTRA_BYTE]
    RLA
    LD [DIVIDE_EXTRA_BYTE],A
    LD A,C                          ; has any quotient bit been set yet?
    OR D
    OR E
    JR NZ,FDIV1                     ; yes, keep dividing
    PUSH HL
    LD HL,FAC                       ; no, leading zero: lower the exponent instead
    DEC [HL]
    POP HL
    JR NZ,FDIV1                     ; more room in the exponent, keep going
    JP OVERR

;; Sets up the double-precision exponent and sign for a divide, then falls into MULDIV.
MULDVS:
    LD A,$FF                        ; $FF means divide, the next byte skips XOR A
    .byte $2E

;; Sets up the double-precision exponent and sign for a multiply, then falls into MULDIV.
MULDVA:
    XOR A                           ; A = 0 means multiply
    LD HL,$412D                     ; point at ARG's sign byte and exponent
    LD C,[HL]                       ; C = ARG's high mantissa byte and sign
    INC HL
    XOR [HL]                        ; B = ARG's exponent, complemented for a divide
    LD B,A
    LD L,$00                        ; FAC's exponent is used as it is

;; Combines the exponents of BCDE and the accumulator for a multiply (L=0) or divide (L=$FF).
MULDIV:
    LD A,B                          ; BCDE zero makes the result zero
    OR A
    JR Z,MULDV2
    LD A,L                          ; A = 0 to multiply or $FF to complement for a divide
    LD HL,FAC
    XOR [HL]
    ADD A,B                         ; add the two biased exponents
    LD B,A
    RRA                             ; checks the sum for exponent overflow or underflow
    XOR B
    LD A,B
    JP P,MULDV1                     ; out of range, decide between zero and overflow
    ADD A,$80                       ; take away one of the two biases
    LD [HL],A
    JP Z,POPHRT                     ; exponent of zero is an underflow: return a zero
    CALL UNPACK                     ; set the hidden bits, A gets the product's sign
    LD [HL],A                       ; keep the result sign in the FAC's sign byte

;; Decrements HL and returns; the multiply/divide overflow and underflow exits follow.
DCXHRT:
    DEC HL                          ; leave HL pointing at the FAC exponent
    RET

;; Drops two stack entries, then zeroes the FAC if it was negative or gives an OV error otherwise.
MLDVEX:
    CALL SIGN
    CPL                             ; positive becomes negative (overflow), negative zero
    POP HL                          ; drop a return address

MULDV1:
    OR A                            ; sign of A decides zero or overflow

MULDV2:
    POP HL                          ; discard the caller's return into the arithmetic
    JP P,ZERO                       ; positive means underflow, so the result is zero
    JP OVERR

;; Multiplies the single-precision accumulator by 10.
MUL10:
    CALL MOVRF                      ; BCDE = a copy of the FAC
    LD A,B
    OR A
    RET Z                           ; zero times 10 is zero
    ADD A,$02                       ; exponent + 2 makes the copy four times the FAC
    JP C,OVERR                      ; exponent overflowed
    LD B,A
    CALL FADD                       ; FAC + 4 FAC = 5 FAC
    LD HL,FAC
    INC [HL]                        ; double it, giving 10 times the original
    RET NZ                          ; done unless the exponent wrapped past $FF
    JP OVERR

;; Returns in A the sign of the single-precision FAC: 1, 0 or -1, with the flags set to match.
SIGN:
    LD A,[FAC]
    OR A                            ; an exponent of zero means the value is zero
    RET Z

SIGNC:
    LD A,[FACHI]                    ; the sign bit is bit 7 of the high mantissa byte
    .byte $FE                       ; CP n: skips the next instruction

FCOMPS:
    CPL
ICOMPS:
    RLA                             ; sign into carry
SIGNS:
    SBC A,A                         ; A = $FF if negative, else 0
    RET NZ                          ; negative gives -1

INRART:
    INC A                           ; positive gives 1
    RET

;; Converts the signed byte in A to single precision in the accumulator (FLOATR at _1).
FLOAT:
    LD B,$88                        ; exponent for a value whose binary point follows A
    LD DE,RESET                     ; zero the lower mantissa bytes

;; Normalizes the signed mantissa in A, D, E with exponent B into the single-precision FAC.
FLOATR:
    LD HL,FAC
    LD C,A                          ; C = the high mantissa byte, still signed
    LD [HL],B
    LD B,$00                        ; no rounding bits
    INC HL
    LD [HL],$80                     ; marker in the sign byte for the normalizer
    RLA                             ; sign into carry, which FADFLT uses to negate
    JP FADFLT                       ; normalize and store it in the FAC
;; Replaces the FAC with its absolute value for any numeric type (the ABS function).
FN_ABS:
    CALL VSIGN
    RET P                           ; already positive

;; Negates the FAC whatever its numeric type, giving a TM error for a string.
VNEG:
    RST $20                         ; integer, string or floating point?
    JP M,INEG                       ; integers are negated separately
    JP Z,TMERR                      ; strings cannot be negated

;; Flips the sign bit of the single- or double-precision FAC.
NEG:
    LD HL,FACHI
    LD A,[HL]
    XOR $80                         ; flip bit 7, the sign of the mantissa
    LD [HL],A
    RET
;; Replaces the FAC with the integer -1, 0 or 1 according to its sign (the SGN function).
FN_SGN:
    CALL VSIGN

;; Sign-extends A into HL and stores it as an integer in the accumulator.
CONIA:
    LD L,A
    RLA                             ; copy the sign bit through all of H
    SBC A,A
    LD H,A
    JP MAKINT

;; Returns in A the sign of the FAC of any numeric type: 1, 0 or -1; TM error for a string.
VSIGN:
    RST $20                         ; what type is the FAC?
    JP Z,TMERR                      ; a string has no sign
    JP P,SIGN                       ; single and double share the same sign test
    LD HL,[FACLO]

;; Returns in A the sign of the integer in HL: 1, 0 or -1.
ISIGN:
    LD A,H
    OR L                            ; zero integer gives A = 0
    RET Z
    LD A,H                          ; the sign bit of H decides between 1 and -1
    JR ICOMPS

;; Pushes the single-precision accumulator.
PUSHF:
    EX DE,HL                        ; keep HL in DE meanwhile
    LD HL,[FACLO]                   ; low two bytes of the FAC
    EX [SP],HL                      ; slip them under the return address
    PUSH HL
    LD HL,[FACHI]                   ; high byte and exponent
    EX [SP],HL                      ; pushed above the low bytes, return address on top
    PUSH HL
    EX DE,HL
    RET

;; Loads the single-precision FAC from the four bytes at HL.
MOVFM:
    CALL MOVRM

;; Copies BCDE into the single-precision FAC.
MOVFR:
    EX DE,HL
    LD [FACLO],HL                   ; low mantissa bytes
    LD H,B
    LD L,C
    LD [FACHI],HL                   ; high mantissa byte and exponent
    EX DE,HL
    RET

;; Loads BCDE from the single-precision FAC.
MOVRF:
    LD HL,FACLO

;; Loads BCDE from the four bytes at HL, leaving HL just past them.
MOVRM:
    LD E,[HL]
    INC HL

;; Loads D, C and B from the bytes at HL, advancing HL past them.
GETBCD:
    LD D,[HL]
    INC HL
    LD C,[HL]
    INC HL
    LD B,[HL]

;; Increments HL and returns.
INXHRT:
    INC HL                          ; leave HL just past the value
    RET

;; Copies the single-precision accumulator to the four bytes at HL.
MOVMF:
    LD DE,FACLO

;; Copies four bytes from DE to HL.
MOVE:
    LD B,$04                        ; a single-precision value is 4 bytes
    JR MOVE1

;; Copies a value sized by VALTYP from HL to DE.
MOVVFM:
    EX DE,HL                        ; swap so the copy goes from HL to DE

;; Copies a value sized by VALTYP from DE to HL.
VMOVE:
    LD A,[VALTYP]                   ; VALTYP is also the value's length in bytes
    LD B,A
;; Copies B bytes from DE to HL.
MOVE1:
    LD A,[DE]
    LD [HL],A
    INC DE
    INC HL
    DEC B
    JR NZ,MOVE1
    RET

;; Sets the implied leading 1 bits of the FAC and of C, saving the FAC's complemented sign at FAC+1;
;; A's bit 7 is set when the two signs agree.
UNPACK:
    LD HL,FACHI                     ; FAC's high mantissa byte, which holds the sign
    LD A,[HL]
    RLCA                            ; sign into carry
    SCF                             ; put back the implied leading 1 bit
    RRA
    LD [HL],A
    CCF                             ; complement the sign
    RRA                             ; into bit 7 of A
    INC HL                          ; FAC+1 holds the sign during arithmetic
    INC HL
    LD [HL],A
    LD A,C                          ; same treatment for the high byte in C
    RLCA
    SCF
    RRA
    LD C,A
    RRA                             ; A = BCDE's sign in bit 7
    XOR [HL]                        ; bit 7 set when the two signs differ, after the CPL
    RET
;; Copies ARG into the FAC, sized by VALTYP.
VMOVFA:
    LD HL,ARGLO

;; Copies the value at HL into the accumulator, sized by VALTYP.
VMOVFM:
    LD DE,$09D2                     ; DE = MOVVFM, which swaps then copies
    JR VMVVFM                       ; copy from HL into the FAC

;; Copies the accumulator into ARG, sized by VALTYP.
VMOVAF:
    LD HL,ARGLO

;; Copies the FAC to the bytes at HL, sized by VALTYP.
VMOVMF:
    LD DE,VMOVE                     ; DE = VMOVE, copying from the FAC to HL

;; Pushes the copy routine in DE as the return address, then points DE at the FAC value for its type.
VMVVFM:
    PUSH DE                         ; the copy runs when VDFACS returns

;; Returns in DE where the accumulator value starts for its type (FACLO, or $411D if double).
VDFACS:
    LD DE,FACLO
    RST $20                         ; double precision starts lower in memory
    RET C                           ; not double, FACLO is right
    LD DE,$411D                     ; double precision starts four bytes below FACLO
    RET

;; Compares the single-precision FAC with BCDE, returning A = 1, 0 or -1 as the FAC is larger, equal
;; or smaller.
FCOMP:
    LD A,B                          ; B is the exponent of BCDE
    OR A
    JP Z,SIGN                       ; BCDE zero, so the FAC's sign is the answer
    LD HL,$095E                     ; FCOMPS adjusts the answer when we return
    PUSH HL
    CALL SIGN                       ; is the FAC zero?
    LD A,C                          ; A = BCDE's sign byte
    RET Z                           ; FAC zero, answer from BCDE's sign, negated by FCOMPS
    LD HL,FACHI
    XOR [HL]                        ; compare the sign bits of the two values
    LD A,C
    RET M                           ; signs differ, BCDE's sign gives the answer
    CALL FCOMP2                     ; compare magnitudes, back here only if they differ
FCOMPD:
    RRA                             ; carry from the compare tells which is larger
    XOR C                           ; reverse the answer when both are negative
    RET

;; Compares the magnitude of BCDE with the accumulator at HL, returning from FCOMP if equal.
FCOMP2:
    INC HL                          ; HL = FAC exponent
    LD A,B
    CP [HL]                         ; exponents first
    RET NZ
    DEC HL
    LD A,C
    CP [HL]
    RET NZ
    DEC HL
    LD A,D
    CP [HL]
    RET NZ
    DEC HL
    LD A,E
    SUB [HL]                        ; a SUB leaves A = 0 if the values are equal
    RET NZ
    POP HL                          ; equal: drop the returns to FCOMPD and FCOMPS, A = 0
    POP HL
    RET

;; Compares the integers HL and DE, returning A=1, 0 or -1 for HL above, equal or below.
ICOMP:
    LD A,D                          ; do the sign bits of HL and DE match?
    XOR H
    LD A,H                          ; differing signs: HL's sign decides
    JP M,ICOMPS
    CP D                            ; same sign, compare the high bytes
    JP NZ,SIGNS                     ; turn the carry into 1 or -1
    LD A,L                          ; then the low bytes
    SUB E
    JP NZ,SIGNS
    RET                             ; equal, A = 0

;; Copies the double at DE into ARG and compares it with the accumulator: A=1, 0 or -1.
DCOMPD:
    LD HL,ARGLO
    CALL VMOVE

;; Compares the double-precision FAC with ARG, returning A = 1, 0 or -1 as the FAC is larger, equal
;; or smaller.
XDCOMP:
    LD DE,$412E                     ; DE = ARG's exponent
    LD A,[DE]
    OR A
    JP Z,SIGN                       ; ARG is zero, the FAC's sign is the answer
    LD HL,$095E                     ; FCOMPS fixes up the answer on return
    PUSH HL
    CALL SIGN                       ; is the FAC zero?
    DEC DE                          ; DE = ARG's sign byte
    LD A,[DE]
    LD C,A                          ; C keeps ARG's sign
    RET Z                           ; FAC zero, answer from ARG's sign
    LD HL,FACHI
    XOR [HL]                        ; compare the signs of FAC and ARG
    LD A,C
    RET M                           ; signs differ, ARG's sign gives the answer
    INC DE                          ; back to the exponents to compare 8 bytes downward
    INC HL
    LD B,$08                        ; exponent plus 7 mantissa bytes

DCOMP1:
    LD A,[DE]
    SUB [HL]
    JP NZ,FCOMPD                    ; first differing byte decides
    DEC DE
    DEC HL
    DEC B
    JR NZ,DCOMP1
    POP BC                          ; equal: drop the FCOMPS return, A = 0
    RET

;; Compares the double-precision FAC with ARG like <XDCOMP>, but with the sense of the result reversed.
DCOMP:
    CALL XDCOMP
    JP NZ,FCOMPS                    ; not equal: invert the answer
    RET

;; Converts the accumulator to an integer in HL.
FRCINT:
    RST $20                         ; which type is the FAC?
    LD HL,[FACLO]                   ; the value, in case it is already an integer
    RET M                           ; integer already
    JP Z,TMERR                      ; a string cannot be an integer
    CALL NC,CONSD                   ; double is first reduced to single precision
    LD HL,$07B2                     ; OVERR as return address if the value is too large
    PUSH HL

;; Converts the single-precision accumulator to an integer, or raises OV if out of range.
CONIS:
    LD A,[FAC]                      ; A = exponent
    CP $90                          ; $90 or more means 2^15 or larger
    JR NC,CONIS2                    ; too big, unless it is exactly -32768
    CALL QINT                       ; truncate to an integer in DE
    EX DE,HL

CONIS1:
    POP DE                          ; drop the OVERR address, the value fitted

;; Stores HL in the accumulator as an integer.
MAKINT:
    LD [FACLO],HL

;; Sets VALTYP to integer (2).
VALINT:
    LD A,$02                        ; 2 = integer
;; Stores A as the value type in VALTYP.
CONISD:
    LD [VALTYP],A
    RET

;; Accepts -32768, the one single value with exponent $90 that fits an integer.
CONIS2:
    LD BC,$9080                     ; BCDE = -32768
    LD DE,RESET
    CALL FCOMP
    RET NZ                          ; not -32768, return into OVERR
    LD H,C                          ; HL = $8000
    LD L,D
    JR CONIS1

;; Converts the FAC to single precision (the CSNG function), giving a TM error for a string.
FRCSNG:
    RST $20                         ; which type is the FAC?
    RET PO                          ; already single precision
    JP M,CONSI                      ; integer
    JP Z,TMERR                      ; string

;; Converts the double-precision accumulator to single precision, rounding.
CONSD:
    CALL MOVRF                      ; BCDE = the high four bytes of the double
    CALL VALSNG
    LD A,B                          ; B is the exponent
    OR A
    RET Z                           ; zero needs no rounding
    CALL UNPACK                     ; set the hidden bit and the sign byte
    LD HL,$4120                     ; the byte just below the single-precision part
    LD B,[HL]                       ; B = rounding byte
    JP ROUND

;; Converts the integer accumulator to single precision.
CONSI:
    LD HL,[FACLO]                   ; HL = the integer

;; Converts the integer in HL to single precision in the accumulator.
CONSIH:
    CALL VALSNG
    LD A,H                          ; A D E = the integer as a mantissa
    LD D,L
    LD E,$00
    LD B,$90                        ; exponent for a 16-bit integer
    JP FLOATR

;; Converts the FAC to double precision (the CDBL function), giving a TM error for a string.
FRCDBL:
    RST $20                         ; which type is the FAC?
    RET NC                          ; already double precision
    JP Z,TMERR                      ; string
    CALL M,CONSI                    ; integer becomes single first

;; Converts the single-precision accumulator to double by clearing the low bytes.
CONDS:
    LD HL,RESET                     ; HL = 0
    LD [DFACLO],HL                  ; zero the four extra low bytes of the double
    LD [DFAC_MID],HL

;; Sets VALTYP to double precision (8).
VALDBL:
    LD A,$08                        ; 8 = double
    .byte $01                       ; LD BC,nn: skips the next instruction

;; Sets VALTYP to single precision (4).
VALSNG:
    LD A,$04                        ; 4 = single
    JP CONISD

;; Returns if the FAC holds a string, otherwise gives a TM error.
CHKSTR:
    RST $20                         ; is the FAC a string?
    RET Z
;; Raises the TM (type mismatch) error.
TMERR:
    LD E,ERR_TM                     ; error code for type mismatch
    JP ERROR

;; Truncates the single-precision accumulator (exponent in A) to a signed integer in CDE.
QINT:
    LD B,A                          ; A = exponent, zero gives a zero result
    LD C,A
    LD D,A
    LD E,A
    OR A                            ; exponent of zero means the value is zero
    RET Z
    PUSH HL                         ; preserve the caller's HL
    CALL MOVRF
    CALL UNPACK                     ; A = the sign comparison, HL at the sign byte
    XOR [HL]                        ; A's top bit = the number's sign
    LD H,A                          ; H keeps the sign
    CALL M,QINTA                    ; negative: less 1, so the result rounds toward minus infinity
    LD A,$98                        ; $98 is the exponent of a 24-bit integer
    SUB B                           ; A = how many places to shift to drop the fraction
    CALL SHIFTR
    LD A,H                          ; recover the sign
    RLA                             ; sign into carry, surviving the calls below
    CALL C,ROUNDA                   ; negative: add the one back
    LD B,$00                        ; discard the fraction bits shifted out
    CALL C,NEGR                     ; negative: make it a two's complement integer
    POP HL
    RET

;; Decrements DE, and BC on a borrow, adjusting a negative mantissa before truncation.
QINTA:
    DEC DE                          ; the low 16 bits of the mantissa
    LD A,D                          ; a borrow out of D and E leaves both $FF
    AND E
    INC A
    RET NZ                          ; no borrow into C

;; Decrements BC and returns.
DCXBRT:
    DEC BC                          ; C is never zero here, so B is not affected
    RET
;; Truncates the FAC toward zero (the FIX function).
FN_FIX:
    RST $20                         ; what type is the argument?
    RET M                           ; an integer has no fraction to remove
    CALL SIGN
    JP P,FN_INT                     ; positive values truncate the same as INT
    CALL NEG                        ; negative: FIX(x) = -INT(-x)
    CALL FN_INT
    JP VNEG
;; Replaces the FAC with the largest whole number not above it (the INT function), for any numeric type.
FN_INT:
    RST $20                         ; what type is the FAC?
    RET M                           ; integers are already whole
    JR NC,DINT                      ; double precision has its own path
    JR Z,TMERR
    CALL CONIS                      ; if it fits, CONIS returns straight to our caller

;; Takes the integer part of the single-precision accumulator; the double case follows at _1.
INT:
    LD HL,FAC
    LD A,[HL]
    CP $98                          ; exponent $98 or more leaves no fraction bits
    LD A,[FACLO]                    ; A = low byte, wanted by one caller
    RET NC
    LD A,[HL]
    CALL QINT                       ; truncate to a signed integer in CDE
    LD [HL],$98                     ; exponent for a 24-bit integer before renormalizing
    LD A,E                          ; keep the low byte for the caller
    PUSH AF
    LD A,C                          ; sign of the integer into carry
    RLA
    CALL FADFLT                     ; float it back into the FAC
    POP AF
    RET

;; Applies INT to the double-precision FAC, converting to an integer when the result fits.
DINT:
    LD HL,FAC
    LD A,[HL]
    CP $90                          ; below 2^15 it can become an integer
    JP C,FRCINT
    JR NZ,DINT2                     ; larger, though it might still be -32768
    LD C,A
    DEC HL
    LD A,[HL]
    XOR $80                         ; a high byte of $80 means -.5 times 2^16
    LD B,$06                        ; the six lower mantissa bytes must all be zero

DINT1:
    DEC HL
    OR [HL]
    DEC B
    JR NZ,DINT1
    OR A
    LD HL,$8000                     ; HL = -32768 for MAKINT
    JP Z,MAKINT
    LD A,C

DINT2:
    CP $B8                          ; $B8 or more leaves no fraction bits in 56
    RET NC

;; Truncates the double-precision accumulator to its integer part, unnormalized at exponent $B8.
DINTFO:
    PUSH AF                         ; carry clear when FOUT calls, to skip normalizing
    CALL MOVRF                      ; high bytes into BCDE for UNPACK
    CALL UNPACK
    XOR [HL]                        ; A's top bit = the number's sign
    DEC HL                          ; exponent that normalizes to the integer value
    LD [HL],$B8
    PUSH AF                         ; keep the sign
    CALL M,DINTA                    ; negative: less 1, so the result rounds down
    LD HL,FACHI
    LD A,$B8                        ; A = bits to shift out to drop the fraction
    SUB B
    CALL DSHFTR
    POP AF
    CALL M,DROUNA                   ; negative: add the 1 back
    XOR A                           ; clear the round byte so zeros shift in
    LD [FAC_ROUND_BYTE],A
    POP AF                          ; recover the FOUT flag
    RET NC                          ; FOUT wants the unnormalized integer
    JP DNORML

;; Decrements the multi-byte mantissa starting at $411D, propagating the borrow.
DINTA:
    LD HL,$411D                     ; FAC's low mantissa byte

DINTA1:
    LD A,[HL]
    DEC [HL]
    OR A                            ; a byte that was zero borrows from the next
    INC HL
    JR Z,DINTA1
    RET

;; Multiplies BC by DE unsigned into DE, raising BS on overflow (array subscripts).
UMULT:
    PUSH HL
    LD HL,RESET                     ; HL = product, starting at zero
    LD A,B                          ; a zero multiplier gives a zero product
    OR C
    JR Z,MULRET
    LD A,$10                        ; 16 bits of multiplier in DE

;; Enters the unsigned multiply loop, shifting the product and multiplier left and adding BC for each
;; set bit; BS error on overflow.
UMULT1:
    ADD HL,HL                       ; shift the product left
    JP C,BSERR                      ; product over 64K: the array is too big
    EX DE,HL                        ; next multiplier bit into carry
    ADD HL,HL
    EX DE,HL
    JR NC,UMULT2
    ADD HL,BC                       ; bit set, add the multiplicand
    JP C,BSERR

;; Counts down the unsigned multiply's remaining bits in A, looping until all are done.
UMULT2:
    DEC A
    JR NZ,UMULT1

;; Ends the unsigned multiply, returning the product in DE and restoring HL from the stack.
MULRET:
    EX DE,HL                        ; product into DE
    POP HL
    RET

;; Subtracts the integer HL from DE into the FAC, going to single precision on overflow.
ISUB:
    LD A,H                          ; B = sign extension of HL
    RLA
    SBC A,A
    LD B,A
    CALL INEGHL                     ; negate the subtrahend and add instead
    LD A,C                          ; A = 0 from INEGHL
    SBC A,B                         ; sign extension of the negated value
    JR IADDS

;; Adds the integers HL and DE, going to single precision on overflow.
IADD:
    LD A,H
    RLA
    SBC A,A

IADDS:
    LD B,A                          ; B = sign extension of the second operand
    PUSH HL                         ; kept in case the sum must be redone in floating
    LD A,D                          ; A = sign extension of DE
    RLA
    SBC A,A
    ADD HL,DE
    ADC A,B                         ; A = bit 16 and up of the true sum
    RRCA                            ; bit 16 into bit 7
    XOR H                           ; differs from bit 15 only on overflow
    JP P,CONIS1                     ; fits, store it as an integer
    PUSH BC                         ; overflow: redo both operands in single precision
    EX DE,HL                        ; HL = the first operand, floated into the FAC
    CALL CONSIH
    POP AF                          ; A = the second operand's sign extension
    POP HL                          ; HL = the second operand
    CALL PUSHF                      ; first operand to the stack
    EX DE,HL                        ; second operand as A D E
    CALL INEGAD                     ; float it as a 24-bit integer
    JP FADDT                        ; add them in single precision

;; Multiplies the integers DE and HL into the integer FAC, going to single precision on overflow.
IMULT:
    LD A,H
    OR L
    JP Z,MAKINT                     ; times zero gives zero
    PUSH HL                         ; both operands kept in case of overflow
    PUSH DE
    CALL IMULDV                     ; make both positive, B = sign of the product
    PUSH BC                         ; keep the product's sign
    LD B,H                          ; BC = multiplicand
    LD C,L
    LD HL,$0000                     ; HL = product
    LD A,$10                        ; 16 multiplier bits in DE

IMULT1:
    ADD HL,HL
    JR C,IMULT5                     ; overflow, redo it in single precision
    EX DE,HL                        ; next multiplier bit into carry
    ADD HL,HL
    EX DE,HL
    JR NC,IMULT2
    ADD HL,BC                       ; add the multiplicand for a 1 bit
    JP C,IMULT5

IMULT2:
    DEC A
    JR NZ,IMULT1
    POP BC                          ; B = sign of the product
    POP DE                          ; DE = the first operand

;; Finishes an integer multiply or divide, applying the result sign in B or handling a value of 32768 up.
IMLDIV:
    LD A,H                          ; a result of 32768 or more?
    OR A
    JP M,IMULT3                     ; may be overflow, or exactly 32768
    POP DE                          ; drop the saved second operand
    LD A,B                          ; negate if the result should be negative
    JP INEGA

;; Handles a product with bit 15 set: exactly 32768 goes to <IMULT4>, anything larger is redone in
;; single precision.
IMULT3:
    XOR $80                         ; exactly $8000 means 32768
    OR L
    JR Z,IMULT4                     ; from IDIV it cannot be more than 32768
    EX DE,HL                        ; overflow: HL = first operand, skip two POPs
    .byte $01

IMULT5:
    POP BC                          ; discard the result sign
    POP HL                          ; HL = the first operand
    CALL CONSIH                     ; float it into the FAC
    POP HL                          ; HL = the second operand
    CALL PUSHF                      ; first operand, floated, onto the stack
    CALL CONSIH                     ; float the second operand into the FAC

FMULTT:
    POP BC                          ; first operand into BCDE
    POP DE
    JP FMULT

;; Returns a product of 32768 as the integer -32768 if negative, else as +32768 in single precision.
IMULT4:
    LD A,B                          ; sign of the result
    OR A
    POP BC                          ; drop the saved second operand
    JP M,MAKINT                     ; -32768 fits an integer as it is
    PUSH DE                         ; keep DE, the remainder for MOD
    CALL CONSIH                     ; float $8000, which gives -32768
    POP DE
    JP NEG                          ; flip it to +32768

;; Makes DE and HL positive for an integer multiply or divide, leaving the result's sign in B bit 7.
IMULDV:
    LD A,H                          ; result is negative if the signs differ
    XOR D
    LD B,A                          ; B bit 7 = sign of the result
    CALL INEGH                      ; absolute value of the second operand
    EX DE,HL                        ; now do the first operand

;; Stores the absolute value of the integer in HL as the integer FAC.
INEGH:
    LD A,H

INEGA:
    OR A
    JP P,MAKINT                     ; already positive

;; Negates the integer in HL and stores it as the integer accumulator.
INEGHL:
    XOR A                           ; A = 0
    LD C,A                          ; C = 0, used by ISUB
    SUB L
    LD L,A
    LD A,C
    SBC A,H
    LD H,A
    JP MAKINT

;; Negates the integer FAC, turning the one overflow case (-32768) into single-precision 32768.
INEG:
    LD HL,[FACLO]
    CALL INEGHL                     ; -32768 negated is still $8000
    LD A,H
    XOR $80                         ; is the result $8000?
    OR L
    RET NZ                          ; no, a valid integer

;; Converts the unsigned 16-bit value in HL to single precision in the accumulator.
INEG2:
    EX DE,HL                        ; 32768 must go to single precision
    CALL VALSNG
    XOR A                           ; A D E = 0, $80, 0 as an unsigned value

;; Converts the signed 24-bit value in A:D:E to single precision in the accumulator.
INEGAD:
    LD B,$98                        ; exponent for a 24-bit integer
    JP FLOATR

;; Subtracts the double-precision ARG from the double-precision FAC.
DSUB:
    LD HL,$412D                     ; ARG's sign byte
    LD A,[HL]
    XOR $80                         ; flip its sign, so adding it subtracts
    LD [HL],A

;; Adds the double-precision ARG to the double accumulator (DSUB negates ARG and falls in).
DADD:
    LD HL,$412E                     ; ARG's exponent
    LD A,[HL]
    OR A
    RET Z                           ; adding zero changes nothing
    LD B,A                          ; B = ARG exponent, C = its high byte and sign
    DEC HL
    LD C,[HL]
    LD DE,FAC                       ; FAC's exponent
    LD A,[DE]
    OR A
    JP Z,VMOVFA                     ; FAC zero: the sum is just ARG
    SUB B                           ; A = how many bits ARG must be shifted down
    JR NC,DADD2                     ; ARG is the smaller, as needed
    CPL                             ; FAC is smaller: make the count positive
    INC A
    PUSH AF
    LD C,$08                        ; swap FAC and ARG, 8 bytes each
    INC HL                          ; HL = ARG exponent
    PUSH HL

DADD1:
    LD A,[DE]
    LD B,[HL]
    LD [HL],A
    LD A,B
    LD [DE],A
    DEC DE
    DEC HL
    DEC C
    JR NZ,DADD1
    POP HL
    LD B,[HL]                       ; B = new ARG exponent
    DEC HL
    LD C,[HL]                       ; C = new ARG high byte and sign
    POP AF

DADD2:
    CP $39                          ; 56 bits or more apart: ARG is too small to matter
    RET NC
    PUSH AF
    CALL UNPACK                     ; hidden bits back, A bit 7 set if signs agree
    INC HL                          ; the byte below ARG gets its shifted-out bits
    LD [HL],$00
    LD B,A                          ; B = add or subtract flag
    POP AF
    LD HL,$412D                     ; align ARG with the FAC
    CALL DSHFTR
    LD A,[FAC_SIGN_TEMP]            ; bits shifted out of ARG become the round byte
    LD [FAC_ROUND_BYTE],A
    LD A,B                          ; signs differ?
    OR A
    JP P,DADD3                      ; yes, subtract
    CALL DMANT_ADD_ARG              ; signs agree, add the mantissas
    JP NC,DROUND                    ; no carry out, just round
    EX DE,HL                        ; HL = FAC exponent
    INC [HL]                        ; carry out: bump the exponent
    JP Z,OVERR
    CALL DSHFRB                     ; shift the carry back in at the top
    JP DROUND

;; Subtracts the mantissas when the double add's signs differ, negating a negative result, then normalizes.
DADD3:
    CALL DADDAS
    LD HL,$4125                     ; sign byte, for DNEGR
    CALL C,DNEGR                    ; borrow means the result came out negative

;; Normalizes the double-precision FAC, shifting out leading zero bytes and bits, then rounds it.
DNORML:
    XOR A                           ; B counts the shift, as a negative number

DNORM1:
    LD B,A
    LD A,[FACHI]                    ; high byte zero, a whole byte can be shifted
    OR A
    JR NZ,DNORM5                    ; nonzero, shift bit by bit
    LD HL,$411C                     ; start from the round byte, the lowest
    LD C,$08                        ; 8 bytes move up one place

DNORM2:
    LD D,[HL]
    LD [HL],A                       ; A holds the lower byte, zero the first time
    LD A,D
    INC HL
    DEC C
    JR NZ,DNORM2
    LD A,B                          ; shift count less 8
    SUB $08
    CP $C0                          ; all 64 bits shifted away?
    JR NZ,DNORM1
    JP ZERO                         ; the value is zero

;; Enters the double normalize's bit loop, shifting the mantissa left until its top bit is set.
DNORM3:
    DEC B                           ; one more bit of shift
    LD HL,$411C                     ; the round byte, lowest of the 8
    CALL DSHFLC
    OR A                            ; top bit set yet?

DNORM5:
    JP P,DNORM3                     ; not normalized, keep shifting
    LD A,B                          ; A = bits shifted, as a negative number
    OR A
    JR Z,DROUND                     ; no shift, go round
    LD HL,FAC
    ADD A,[HL]                      ; lower the exponent by the shift
    LD [HL],A
    JP NC,ZERO                      ; exponent went below zero
    RET Z                           ; exponent exactly zero is also a zero

;; Rounds the double-precision FAC using its extra low byte and restores the sign bit.
DROUND:
    LD A,[FAC_ROUND_BYTE]

DROUNB:
    OR A                            ; top bit of the extra byte set: round up
    CALL M,DROUNA
    LD HL,$4125                     ; unpacked sign byte, complemented
    LD A,[HL]
    AND $80                         ; keep only its sign bit
    DEC HL
    DEC HL
    XOR [HL]                        ; put the sign over the hidden bit
    LD [HL],A
    RET

;; Increments the double mantissa at $411D, carrying into the exponent (OV error on overflow).
DROUNA:
    LD HL,$411D                     ; FAC's low mantissa byte
    LD B,$07                        ; 7 mantissa bytes

DRONA1:
    INC [HL]
    RET NZ                          ; no carry, finished
    INC HL
    DEC B
    JR NZ,DRONA1
    INC [HL]                        ; all bytes wrapped to zero, bump the exponent
    JP Z,OVERR                      ; exponent overflowed
    DEC HL
    LD [HL],$80                     ; mantissa becomes .5 at the new exponent
    RET

;; Adds the ARG mantissa to the double accumulator's 7-byte mantissa; carry out in CF.
DMANT_ADD_ARG:
    LD HL,ARGLO

;; Adds the 7-byte mantissa at HL to the double accumulator's mantissa; carry out in CF.
DADDFO:
    LD DE,$411D

;; Adds the 7-byte number at HL to the one at DE, low byte first; carry out in CF.
DADDS:
    LD C,$07
    XOR A                           ; clear carry for the first byte

;; Enters the mantissa add loop, adding C bytes at HL into those at DE with carry.
DADDL:
    LD A,[DE]

;; Adds the byte at HL with carry to A and continues the mantissa add loop.
DADDOP:
    ADC A,[HL]
    LD [DE],A
    INC DE
    INC HL
    DEC C
    JR NZ,DADDL
    RET

;; Subtracts the ARG mantissa from the double accumulator's 7-byte mantissa; borrow in CF.
DADDAS:
    LD HL,ARGLO

;; Subtracts the 7-byte mantissa at HL from the double accumulator's mantissa; borrow in CF.
DADDFS:
    LD DE,$411D

;; Subtracts the 7-byte number at HL from the one at DE, low byte first; borrow in CF.
DADDSS:
    LD C,$07
    XOR A                           ; clear borrow for the first byte

;; Enters the mantissa subtract loop, subtracting C bytes at HL from those at DE with borrow.
DADDLS:
    LD A,[DE]
    SBC A,[HL]
    LD [DE],A
    INC DE
    INC HL
    DEC C
    JR NZ,DADDLS
    RET

;; Complements the sign byte at HL and negates the 8-byte double mantissa at $411C.
DNEGR:
    LD A,[HL]                       ; unpacked sign byte
    CPL
    LD [HL],A
    LD HL,$411C                     ; start at the round byte
    LD B,$08                        ; 8 bytes, round byte included
    XOR A                           ; clear borrow, C = 0
    LD C,A

DNEGR1:
    LD A,C
    SBC A,[HL]                      ; 0 minus the byte, with borrow
    LD [HL],A
    INC HL
    DEC B
    JR NZ,DNEGR1
    RET

;; Stores C at HL, then shifts the 8-byte number ending at HL right by A bits.
DSHFTR:
    LD [HL],C                       ; put the unpacked high byte back first
    PUSH HL

DSHFR1:
    SUB $08                         ; at least 8 bits still to shift?
    JR C,DSHFR3                     ; no, finish bit by bit
    POP HL

;; Shifts the 8-byte number ending at HL right one byte, then continues the A-bit shift.
DSHFRM:
    PUSH HL
    LD DE,$0800                     ; E = 0 enters the top, D counts 8 bytes

DSHFR2:
    LD C,[HL]                       ; move each byte down one place
    LD [HL],E
    LD E,C
    DEC HL
    DEC D
    JR NZ,DSHFR2
    JR DSHFR1

;; Finishes a double mantissa right shift one bit at a time, with A + 9 giving the bit count plus one.
DSHFR3:
    ADD A,$09                       ; A = bits left to shift plus one
    LD D,A

DSHFR4:
    XOR A                           ; zero carry enters the top bit
    POP HL                          ; HL = top byte of the number
    DEC D
    RET Z

DSHFRA:
    PUSH HL
    LD E,$08                        ; 8 bytes per bit shift

DSHFR5:
    LD A,[HL]
    RRA                             ; shift right through carry
    LD [HL],A
    DEC HL
    DEC E
    JR NZ,DSHFR5
    JR DSHFR4

;; Shifts the double accumulator's mantissa right one bit.
DSHFRB:
    LD HL,FACHI                     ; the double FAC's high byte
    LD D,$01                        ; one bit
    JR DSHFRA

;; Rotates the 8-byte number at HL left one bit through carry, low byte first.
DSHFLC:
    LD C,$08                        ; 8 bytes

;; Rotates the C bytes at HL left one bit through carry, low byte first.
DSHFTL:
    LD A,[HL]
    RLA                             ; shift left through carry
    LD [HL],A
    INC HL
    DEC C
    JR NZ,DSHFTL
    RET

;; Multiplies the double accumulator by the double-precision ARG.
DMULT:
    CALL SIGN                       ; is the FAC zero?
    RET Z                           ; zero times anything is zero
    CALL MULDVA                     ; add exponents and work out the result sign
    CALL DMULDV                     ; multiplier to FBUFFR, FAC zeroed for the product
    LD [HL],C                       ; clear the FAC's round byte
    INC DE                          ; DE = low byte of the multiplier copy
    LD B,$07                        ; 7 multiplier bytes

;; Enters the double multiply's outer loop on the next ARG byte at DE, shifting a whole byte if it is zero.
DMULT2:
    LD A,[DE]                       ; next multiplier byte
    INC DE
    OR A                            ; a zero byte only shifts the product
    PUSH DE                         ; keep the multiplier pointer
    JR Z,DMULT5
    LD C,$08                        ; 8 bits in this byte

;; Runs the double multiply's bit loop, adding the multiplicand for each set bit and shifting right.
DMULT3:
    PUSH BC                         ; keep the byte and bit counters
    RRA                             ; next multiplier bit into carry
    LD B,A                          ; B keeps the bits still to test
    CALL C,DMANT_ADD_ARG            ; bit set, add the multiplicand ARG
    CALL DSHFRB                     ; shift the product right a bit
    LD A,B
    POP BC
    DEC C
    JR NZ,DMULT3

;; Ends one multiplier byte of the double multiply, looping for the rest and then normalizing.
DMULT4:
    POP DE                          ; multiplier pointer back
    DEC B                           ; another multiplier byte?
    JR NZ,DMULT2
    JP DNORML                       ; normalize and round the product

;; Shifts the double product right one whole byte for a zero multiplier byte.
DMULT5:
    LD HL,FACHI
    CALL DSHFRM                     ; shift the product down a byte
    JR DMULT4

;; Holds the double-precision constant 10.0, whose high half is the single-precision 10.0 at <FTEN>.
DTEN:
    .byte $00, $00, $00, $00

;; Holds the single-precision constant 10.0, which is also the high half of the double 10.0.
FTEN:
    .byte $00, $00, $20, $84

;; Divides the double accumulator by 10; the general double divide starts inside at $0DE5.
DDIV10:
    LD DE,$0DD4                     ; DTEN, the double constant 10
    LD HL,ARGLO
    CALL VMOVE

;; Divides the double-precision FAC by ARG, leaving the quotient in the FAC; /0 error if ARG is zero.
DDIV:
    LD A,[ARG]                      ; exponent of ARG, the divisor
    OR A
    JP Z,DV0ERR                     ; dividing by zero is an error
    CALL MULDVS                     ; subtract exponents, work out the sign
    INC [HL]                        ; exponent + 2 to suit the divide loop
    INC [HL]
    CALL DMULDV                     ; dividend to FBUFFR, FAC zeroed for the quotient
    LD HL,$4151                     ; an extra high byte above the dividend
    LD [HL],C                       ; C = 0 here
    LD B,C                          ; B = 0 until a quotient 1 bit appears

DDIV1:
    LD DE,$414A                     ; low byte of the dividend in FBUFFR
    LD HL,ARGLO                     ; divisor
    CALL DADDSS                     ; try subtracting the divisor
    LD A,[DE]                       ; borrow through the extra high byte
    SBC A,C
    CCF                             ; carry now set if the divisor fitted
    JR C,DDIV2                      ; fitted, quotient bit is 1
    LD DE,$414A                     ; did not fit: add the divisor back
    LD HL,ARGLO
    CALL DADDS
    XOR A                           ; quotient bit is 0, skip the next two
    .byte $DA                       ; JP C,nn: skips the next instruction

DDIV2:
    LD [DE],A                       ; keep the new extra byte
    INC B                           ; a quotient 1 bit has been seen
    LD A,[FACHI]                    ; is the quotient's top bit set yet?
    INC A                           ; sign flag from A, carry kept
    DEC A
    RRA                             ; carry (the next bit) into bit 7 for rounding
    JP M,DROUNB                     ; quotient complete, round with it
    RLA                             ; carry back = the new quotient bit
    LD HL,$411D                     ; shift the bit into the quotient
    LD C,$07
    CALL DSHFTL
    LD HL,$414A                     ; and the dividend left a bit
    CALL DSHFLC
    LD A,B                          ; any quotient 1 bit yet?
    OR A
    JR NZ,DDIV1                     ; yes, keep dividing
    LD HL,FAC                       ; leading zero: lower the exponent instead
    DEC [HL]
    JR NZ,DDIV1
    JP OVERR                        ; exponent ran out

;; Saves C as ARG's sign, moves the 7-byte mantissa below HL to $414A and zeroes it.
DMULDV:
    LD A,C                          ; unpacked high byte of ARG
    LD [ARGHI],A
    DEC HL                          ; HL = FAC high mantissa byte
    LD DE,$4150                     ; top of FBUFFR
    LD BC,$0700                     ; 7 bytes, C = 0 to clear the FAC

DMLDV1:
    LD A,[HL]
    LD [DE],A
    LD [HL],C
    DEC DE
    DEC HL
    DEC B
    JR NZ,DMLDV1
    RET

;; Multiplies the double accumulator by 10 (x4 by exponent, add original, double).
DMUL10:
    CALL VMOVAF                     ; copy the FAC to ARG
    EX DE,HL
    DEC HL
    LD A,[HL]                       ; FAC exponent
    OR A
    RET Z                           ; zero times 10 is zero
    ADD A,$02                       ; exponent + 2 multiplies by 4
    JP C,OVERR
    LD [HL],A
    PUSH HL
    CALL DADD                       ; plus the original gives 5 times
    POP HL
    INC [HL]                        ; double it, giving 10 times
    RET NZ                          ; done unless the exponent wrapped to zero
    JP OVERR

;; Converts the number text at HL into the accumulator as double precision.
FINDBL:
    CALL ZERO
    CALL VALDBL                     ; the next byte skips XOR A, so NZ keeps it double
    .byte $F6

;; Converts the number at HL into the accumulator.
FIN:
    XOR A                           ; Z makes the number start as integer zero

FINCHR:
    EX DE,HL                        ; text pointer to DE meanwhile
    LD BC,$00FF                     ; B = digits after the point, C = $FF no point yet
    LD H,B
    LD L,B
    CALL Z,MAKINT                   ; FAC = integer 0, unless entered from FINDBL
    EX DE,HL
    LD A,[HL]                       ; first character of the number
    CP $2D                          ; leading minus sign?
    PUSH AF                         ; Z flag kept, to negate at the end
    JP Z,FIN_1                      ; skip past the sign
    CP $2B                          ; a leading plus is skipped too
    JR Z,FIN_1
    DEC HL                          ; no sign, so reread the first character
;; Reads the next character of a number being parsed and dispatches on a digit, decimal point,
;; exponent letter or type suffix.
FIN_1:
    RST $10                         ; next character, carry set for a digit
    JP C,FINDIG
    CP $2E                          ; decimal point
    JP Z,FINDP
    CP $45                          ; E: exponent, single precision
    JR Z,FINEX
    CP $25                          ; % suffix makes it an integer
    JP Z,FININT
    CP $23                          ; # suffix makes it double
    JP Z,FINDBF
    CP $21                          ; ! suffix makes it single
    JP Z,FINSNF
    CP $44                          ; D: exponent, double precision
    JR NZ,FINE                      ; none of these ends the number

FINEX1:
    OR A                            ; NZ asks for double precision
FINEX:
    CALL FINFRC                     ; make the FAC single (Z) or double (NZ)
    PUSH HL
    LD HL,$0EBD                     ; FINEC, so the RETs below go on to the digits
    EX [SP],HL
    RST $10                         ; first character after the E or D
    DEC D                           ; D = $FF, assuming a negative exponent
    CP $CE                          ; minus as a token
    RET Z
    CP $2D                          ; minus as a character, from VAL
    RET Z
    INC D                           ; not negative after all
    CP $CD                          ; plus as a token
    RET Z
    CP $2B                          ; plus as a character
    RET Z
    DEC HL                          ; no sign, reread the character as a digit
    POP AF                          ; discard the FINEC address
FINEC:
    RST $10                         ; next exponent character
    JP C,FINEDG                     ; add the digit into the exponent in E
    INC D                           ; D becomes zero if the exponent is negative
    JR NZ,FINE                      ; positive exponent
    XOR A                           ; negate the exponent
    SUB E
    LD E,A
FINE:
    PUSH HL
    LD A,E                          ; A = exponent less the digits after the point
    SUB B
;; Scales the parsed number by the power of ten in A, applies its sign, and finishes the conversion.
FINE2:
    CALL P,FINMUL                   ; positive: multiply by 10 once
    CALL M,FINDIV                   ; negative: divide by 10 once
    JR NZ,FINE2                     ; until the power of ten is used up
    POP HL
    POP AF                          ; Z flag from the leading minus test
    PUSH HL
    CALL Z,VNEG                     ; leading minus: negate
    POP HL
    RST $20                         ; 32768 parsed as a negative may need to be an int
    RET PE                          ; not single precision, so not -32768
    PUSH HL
    LD HL,$0890                     ; POPHRT restores the text pointer either way
    PUSH HL
    CALL CONIS2                     ; becomes integer -32768 if that is the value
    RET
;; Handles a decimal point while parsing a number, ending the number at a second one.
FINDP:
    RST $20
    INC C                           ; C goes $FF to 0 on the first decimal point
    JR NZ,FINE                      ; a second decimal point ends the number
    CALL C,FINFRC                   ; a fraction cannot be integer, so make it single unless double
    JP FIN_1
FININT:
    RST $20                         ; a % suffix is only legal while the number is still an integer
    JP P,SNERR                      ; value no longer fits an integer, so % is a syntax error
INFINE:
    INC HL                          ; skip the type suffix character
    JR FINE
FINDBF:
    OR A                            ; NZ here picks double precision for the # suffix
FINSNF:
    CALL FINFRC
    JR INFINE

;; Forces the accumulator to single (Z) or double (NZ) precision, preserving all registers.
FINFRC:
    PUSH HL
    PUSH DE
    PUSH BC
    PUSH AF
    CALL Z,FRCSNG                   ; Z from the caller selects single precision
    POP AF
    CALL NZ,FRCDBL                  ; NZ selects double precision instead
    POP BC
    POP DE
    POP HL
    RET

;; Returns if Z; otherwise multiplies the accumulator by 10 and decrements A.
FINMUL:
    RET Z                           ; nothing left to scale

;; Multiplies the single or double accumulator by 10 and decrements A.
FINMLT:
    PUSH AF
    RST $20
    PUSH AF                         ; keep the type flags for the second test
    CALL PO,MUL10
    POP AF
    CALL PE,DMUL10
    POP AF

;; Decrements A and returns.
DCRART:
    DEC A
    RET

;; Divides the single or double accumulator by 10 and increments A, preserving DE and HL.
FINDIV:
    PUSH DE
    PUSH HL
    PUSH AF
    RST $20
    PUSH AF                         ; keep the type flags for the second test
    CALL PO,DIV10
    POP AF
    CALL PE,DDIV10
    POP AF
    POP HL
    POP DE
    INC A                           ; one fewer digit past the decimal point to undo
    RET

;; Adds the next digit at HL into the number being parsed, as an integer while it fits, else as a
;; single or double.
FINDIG:
    PUSH DE
    LD A,B                          ; C is $FF before the point and 0 after, carry is set for a digit
    ADC A,C
    LD B,A                          ; B counts this digit only if it follows the decimal point
    PUSH BC
    PUSH HL
    LD A,[HL]
    SUB $30                         ; A = the digit's value 0 to 9
    PUSH AF
    RST $20
    JP P,FINDGV
    LD HL,[FACLO]
    LD DE,$0CCD                     ; 3277: above this, ten times the value overflows an integer
    RST $18
    JR NC,FINDG2                    ; too big to stay an integer, switch to single precision
    LD D,H
    LD E,L
    ADD HL,HL                       ; HL = value times 4
    ADD HL,HL
    ADD HL,DE                       ; HL = value times 5
    ADD HL,HL                       ; HL = value times 10
    POP AF
    LD C,A                          ; BC = digit, B is 0 since an integer has no decimal point
    ADD HL,BC
    LD A,H
    OR A
    JP M,FINDG1                     ; sign bit set means 32767 was exceeded
    LD [FACLO],HL

FINDGE:
    POP HL
    POP BC
    POP DE
    JP FIN_1

;; Handles an integer that overflowed while taking a digit, redoing the step in single precision.
FINDG1:
    LD A,C                          ; put the digit back on the stack for the single-precision path
    PUSH AF

;; Converts the parsed integer to single precision and continues adding the digit there.
FINDG2:
    CALL CONSI
    SCF                             ; carry tells FINDGV the value is single, not double

;; Adds the digit in single precision while the value is under 1E6, otherwise in double precision.
FINDGV:
    JR NC,FINDGD                    ; no carry means the value is already double precision
    LD BC,$9474                     ; BC/DE = 1E6 in single precision
    LD DE,$2400
    CALL FCOMP
    JP P,FINDG3                     ; seventh digit would lose precision in single, go double
    CALL MUL10
    POP AF                          ; A = the digit value
    CALL FINLOG
    JR FINDGE

;; Converts the parsed number to double precision and adds the digit there.
FINDG3:
    CALL CONDS

;; Multiplies the double-precision value by 10 and adds the digit.
FINDGD:
    CALL DMUL10
    CALL VMOVAF                     ; move the scaled value to ARG for the addition
    POP AF                          ; A = the digit value
    CALL FLOAT
    CALL CONDS
    CALL DADD                       ; value = value * 10 + digit
    JR FINDGE

;; Adds the signed byte in A to the single-precision accumulator.
FINLOG:
    CALL PUSHF
    CALL FLOAT

FADDT:
    POP BC                          ; BC/DE = the saved accumulator off the stack
    POP DE
    JP FADD

;; Adds a digit into the exponent being parsed in E, capping the exponent at 50 past two digits.
FINEDG:
    LD A,E
    CP $0A                          ; exponent already two digits long
    JR NC,FINEDO
    RLCA                            ; A = exponent times 4
    RLCA
    ADD A,E                         ; A = exponent times 5
    RLCA                            ; A = exponent times 10
    ADD A,[HL]
    SUB $30                         ; remove the ASCII bias from the digit just added
    LD E,A                          ; byte $FA turns the next LD into a dummy JP M, skipping it
    .byte $FA

FINEDO:
    LD E,$32                        ; cap at 50, already far past the range of any number
    JP FINEC

;; Prints " IN " and then the line number in HL.
INPRT:
    PUSH HL
    LD HL,INTXT
    CALL STROUT
    POP HL

;; Prints the integer in HL as a decimal number.
LINPRT:
    CALL MAKINT
    XOR A                           ; A = 0 selects free-format output
    CALL FOUINI
    OR [HL]                         ; force NZ so the value is not treated as zero
    CALL FOUT2
    JP STROUI

;; Converts the accumulator to text, returning its address in HL.
FOUT:
    XOR A

;; Converts the accumulator to text under PRINT USING format flags in A; HL at the text.
PUFOUT:
    CALL FOUINI
    AND $08                         ; bit 3 asks for a + sign on positive numbers
    JR Z,FOUT1
    LD [HL],$2B                     ; the + replaces the leading space

FOUT1:
    EX DE,HL
    CALL VSIGN                      ; DE keeps the buffer pointer while the sign is tested
    EX DE,HL
    JP P,FOUT2
    LD [HL],$2D                     ; negative: put a - in the sign position
    PUSH BC
    PUSH HL
    CALL VNEG                       ; print the magnitude, the sign is already stored
    POP HL
    POP BC
    OR H                            ; force NZ so FOUT2 does not treat the value as zero

;; Writes the accumulator's digits after the sign at HL, dispatching on type and format.
FOUT2:
    INC HL
    LD [HL],$30                     ; default text is a single 0
    LD A,[TEMP3]                    ; A = the PRINT USING format flags
    LD D,A
    RLA                             ; bit 7 set means a PRINT USING field is active
    LD A,[VALTYP]                   ; A = the value's type: 2 integer, 4 single, 8 double
    JP C,FOUTFX                     ; PRINT USING: format into a fixed field
    JP Z,FOUTZR                     ; Z here means the value is zero, so the 0 already stored is it
    CP $04
    JP NC,FOUFRV                    ; single or double take the floating-point path
    LD BC,RESET                     ; B = 0 and C = 0: no digit limit and no commas
    CALL FOUTCI

;; Blanks (or star-fills) leading zeros and commas, adding $ and sign as formatted.
FOUTZS:
    LD HL,$4130                     ; start of the output buffer, the sign position
    LD B,[HL]                       ; B = the sign character, kept for later
    LD C,$20                        ; C = the fill character for leading zeros, normally a space
    LD A,[TEMP3]
    LD E,A
    AND $20                         ; bit 5 asks for leading asterisks
    JR Z,FOTZS1
    LD A,B
    CP C                            ; test whether the number is positive, a space in the sign position
    LD C,$2A                        ; fill with * instead of spaces
    JR NZ,FOTZS1                    ; leave a - or + sign as it is
    LD B,C                          ; a positive number gets a * in its sign position too

FOTZS1:
    LD [HL],C                       ; blank out the sign position or the leading zero
    RST $10
    JR Z,FOTZS4                     ; end of text: put a single zero back
    CP $45                          ; E exponent marker: number is all zeros, keep one 0
    JR Z,FOTZS4
    CP $44                          ; D exponent marker: number is all zeros, keep one 0
    JR Z,FOTZS4
    CP $30                          ; keep blanking leading zeros
    JR Z,FOTZS1
    CP $2C                          ; blank leading commas too
    JR Z,FOTZS1
    CP $2E                          ; a decimal point reached: keep one 0 before it
    JR NZ,FOTZS2

FOTZS4:
    DEC HL                          ; step back to the last blanked position
    LD [HL],$30                     ; put a 0 there so the number is not empty

FOTZS2:
    LD A,E
    AND $10                         ; bit 4 asks for a leading $ sign
    JR Z,FOTZS3
    DEC HL
    LD [HL],$24                     ; $ goes just before the first digit

FOTZS3:
    LD A,E
    AND $04                         ; bit 2 means the sign goes after the number instead
    RET NZ                          ; sign is printed after the number by the caller
    DEC HL
    LD [HL],B                       ; put the sign just before the first digit
    RET

;; Stores the format flags in A and puts a space (sign) at the start of the output buffer.
FOUINI:
    LD [TEMP3],A                    ; remember the format flags for the conversion
    LD HL,$4130                     ; start of the output buffer
    LD [HL],$20                     ; a space stands in for the sign of a positive number
    RET

;; Formats a single- or double-precision FAC in free format, choosing plain or E/D notation.
FOUFRV:
    CP $05                          ; carry if single precision
    PUSH HL
    SBC A,$00
    RLA
    LD D,A
    INC D                           ; D = digit limit for plain notation, by precision
    CALL FOUTNV                     ; scale to a fixed number of digits, A = power of ten applied
    LD BC,$0300                     ; C = 0 means no commas in free format
    ADD A,D                         ; A = digits before the decimal point plus one
    JP M,FOFRS1                     ; too small to print without an exponent
    INC D
    CP D                            ; is the number too large for plain notation
    JR NC,FOFRS1                    ; too large: use E or D notation
    INC A                           ; plain notation: B = digits before the decimal point
    LD B,A
    LD A,$02                        ; A = 2 so that the exponent computed next is zero

FOFRS1:
    SUB $02                         ; A = the exponent to print, zero for plain notation
    POP HL
    PUSH AF                         ; save the exponent for after the digits are written
    CALL FOUTED
    LD [HL],$30                     ; a leading 0 in case the number is a pure fraction
    CALL Z,INXHRT                   ; keep the 0 only when the decimal point comes first
    CALL FOUTCV

;; Strips trailing zeros and a bare decimal point from the formatted number, then adds any exponent.
FOFRS2:
    DEC HL                          ; back up over a trailing zero
    LD A,[HL]
    CP $30
    JR Z,FOFRS2                     ; strip trailing zeros
    CP $2E                          ; a bare trailing decimal point is dropped too
    CALL NZ,INXHRT
    POP AF                          ; A = the exponent to print
    JR Z,FOUTDN                     ; zero exponent: plain notation, just end the text

;; Writes an E or D exponent with sign and two digits for the power of ten in A at HL.
FOFLDN:
    PUSH AF
    RST $20                         ; carry is clear for double, set for single
    LD A,$22                        ; $22 doubled gives D for double, plus carry gives E for single
    ADC A,A
    LD [HL],A
    INC HL
    POP AF
    LD [HL],$2B                     ; assume a positive exponent
    JP P,FOUCE1
    LD [HL],$2D
    CPL                             ; make the exponent positive
    INC A

;; Writes the exponent in A as two decimal digits after HL and ends the text.
FOUCE1:
    LD B,$2F                        ; B starts one below the ASCII 0

FOUCE2:
    INC B                           ; B = tens digit of the exponent in ASCII
    SUB $0A
    JR NC,FOUCE2                    ; subtract tens until the exponent goes negative
    ADD A,$3A                       ; undo the extra subtract and make it ASCII: units digit
    INC HL
    LD [HL],B
    INC HL
    LD [HL],A

FOUTZR:
    INC HL

;; Ends the formatted text at HL with a zero byte and returns its start in HL.
FOUTDN:
    LD [HL],$00                     ; terminate the text with a zero byte
    EX DE,HL                        ; DE = end of the text
    LD HL,$4130                     ; HL = start of the text
    RET

;; Formats the FAC as a fixed-point number for PRINT USING.
FOUTFX:
    INC HL
    PUSH BC                         ; save the field sizes from the PRINT USING format
    CP $04
    LD A,D                          ; A = the format flags
    JP NC,FOUFXV                    ; single or double go to the floating-point fixed format
    RRA                             ; bit 0 of the flags asks for exponential notation
    JP C,FFXIFL                     ; integer with ^^^^ format: convert to single and use E notation
    LD BC,$0603                     ; C = 3 digits per comma group, if commas are wanted
    CALL FOUICC
    POP DE                          ; D = digits wanted before the decimal point, E = digits after
    LD A,D
    SUB $05                         ; an integer has at most 5 digits
    CALL P,FOTZER                   ; field wider than 5 digits: pad with leading zeros
    CALL FOUTCI

FOUTTD:
    LD A,E                          ; A = digits wanted after the decimal point
    OR A
    CALL Z,DCXHRT                   ; no digits after the point: drop the decimal point
    DEC A                           ; one place is taken by the decimal point
    CALL P,FOTZER                   ; integer has no fraction, so the remaining places are zeros

;; Finishes a fixed-format number, adding any trailing sign and then tidying its leading characters.
FOUTTS:
    PUSH HL
    CALL FOUTZS                     ; blank leading zeros and add $ and sign as formatted
    POP HL
    JR Z,FFXIX1                     ; Z means the sign was already placed in front
    LD [HL],B                       ; B = sign character, appended after the digits
    INC HL

FFXIX1:
    LD [HL],$00                     ; end of the formatted text
    LD HL,$412F                     ; one byte early, the INC below lands on the buffer start

FOUBE1:
    INC HL

FOUBE5:
    LD A,[TEMP2]                    ; A = low byte of where the decimal point was written
    SUB L
    SUB D                           ; Z when the digits exactly fill the space before the point
    RET Z
    LD A,[HL]
    CP $20                          ; skip leading blanks to the first real character
    JR Z,FOUBE1
    CP $2A                          ; leading asterisks are blanks too
    JR Z,FOUBE1
    DEC HL                          ; HL = start of the field
    PUSH HL

;; Tries to drop the zero before the decimal point so the number fits, skipping a sign or dollar sign.
FOUBE2:
    PUSH AF                         ; save each character before the zero, last one tagged NZ
    LD BC,$10DF                     ; a sign or $ returns to FOUBE2 to be saved as well
    PUSH BC
    RST $10
    CP $2D
    RET Z
    CP $2B
    RET Z
    CP $24
    RET Z
    POP BC                          ; discard the FOUBE2 return address
    CP $30                          ; only a leading 0 can be dropped to make room
    JR NZ,FOUBE4
    INC HL                          ; look past the 0 and the character after it
    RST $10
    JR NC,FOUBE4                    ; no digit after the decimal point, the 0 must stay
    DEC HL                          ; $01 below skips the shift, landing on the POP
    .byte $01

;; Moves the saved characters back one place over the dropped zero, then continues at <FOUBE5>.
FOUBE3:
    DEC HL                          ; move a saved character one place right, over the 0
    LD [HL],A
    POP AF                          ; Z tags the saved signs, NZ the first character
    JR Z,FOUBE3
    POP BC                          ; discard the saved field start
    JP FOUBE5                       ; rescan in case the number now fits

;; Discards the saved characters and puts a % before the field, since the number does not fit.
FOUBE4:
    POP AF                          ; throw away the saved characters
    JR Z,FOUBE4
    POP HL                          ; HL = start of the field
    LD [HL],$25                     ; % marks a number too wide for its field
    RET

;; Formats a single or double value for PRINT USING, choosing exponential or fixed-point layout.
FOUFXV:
    PUSH HL
    RRA                             ; bit 0 of the format flags asks for exponential notation
    JP C,FFXFLV
    JR Z,FFXSFX                     ; Z from the type compare means single precision
    LD DE,$1384                     ; DE = the double constant 1E16
    CALL DCOMPD
    LD D,$10                        ; D = 16 digits of double precision
    JP M,FFXSDC                     ; below 1E16 fits in a fixed field

;; Formats a value too large for fixed point in free format with <FOUT>, preceded by a %.
FFXSDO:
    POP HL                          ; drop the field: print in free format instead
    POP BC                          ; discard the saved field sizes
    CALL FOUT
    DEC HL                          ; step back before the text for the % sign
    LD [HL],$25
    RET

;; Formats a single-precision value in fixed point, falling back to % free format at 10^16 or more.
FFXSFX:
    LD BC,$B60E                     ; BC/DE = 1E16 in single precision
    LD DE,$1BCA
    CALL FCOMP
    JP P,FFXSDO                     ; too big for a fixed field
    LD D,$06                        ; D = 6 digits of single precision

;; Formats a single or double value in fixed point with D significant digits, padding with zeros
;; and finishing at <FOUTTD>.
FFXSDC:
    CALL SIGN
    CALL NZ,FOUTNV                  ; scale a nonzero value, A = powers of ten applied
    POP HL
    POP BC
    JP M,FFXXVS                     ; scaled up means the value has digits after the point
    PUSH BC
    LD E,A                          ; E = powers of ten divided out, trailing zeros to add
    LD A,B
    SUB D                           ; A = leading zeros needed to fill the field
    SUB E
    CALL P,FOTZER
    CALL FOUTCD                     ; set up the point and comma counters
    CALL FOUTCV                     ; write the significant digits
    OR E                            ; any powers of ten divided out come back as zeros
    CALL NZ,FOTZEC
    OR E
    CALL NZ,FOUTED
    POP DE                          ; D = digits before the point, E = digits after
    JP FOUTTD

;; Formats a fixed-point value that has digits after the decimal point, rounding off digits that
;; do not fit.
FFXXVS:
    LD E,A                          ; E = powers of ten multiplied in, a negative count
    LD A,C                          ; A = digits wanted after the decimal point
    OR A
    CALL NZ,DCRART                  ; one of the places is taken by the point itself
    ADD A,E                         ; A = digits that will not fit and must be dropped
    JP M,FFXXV8
    XOR A                           ; nothing to drop

FFXXV8:
    PUSH BC
    PUSH AF

FFXXV2:
    CALL M,FINDIV                   ; divide by ten once per digit to drop
    JP M,FFXXV2
    POP BC
    LD A,E
    SUB B                           ; E = remaining scale after the digits dropped
    POP BC
    LD E,A
    ADD A,D
    LD A,B
    JP M,FFXXV3                     ; negative means no digits before the decimal point
    SUB D                           ; A = leading zeros needed to fill the field
    SUB E
    CALL P,FOTZER
    PUSH BC
    CALL FOUTCD
    JR FFXXV6

;; Formats a fixed-point value with no digits before the decimal point: zeros, the point, then digits.
FFXXV3:
    CALL FOTZER
    LD A,C                          ; A = digits wanted after the decimal point
    CALL FOUTDP
    LD C,A
    XOR A
    SUB D                           ; A = zeros between the point and the first digit
    SUB E
    CALL FOTZER
    PUSH BC
    LD B,A                          ; no more points or commas to insert
    LD C,A

FFXXV6:
    CALL FOUTCV
    POP BC
    OR C                            ; any digits wanted after the decimal point
    JR NZ,FFXXV7
    LD HL,[TEMP2]                   ; none: resume at the decimal point position

;; Writes any trailing zeros the field still needs, then finishes at <FOUTTS>.
FFXXV7:
    ADD A,E                         ; A = trailing zeros still needed to fill the field
    DEC A
    CALL P,FOTZER
    LD D,B                          ; D = digits before the point, for FOUTTS
    JP FOUTTS

;; Formats an integer in PRINT USING exponential layout by converting it to single precision first.
FFXIFL:
    PUSH HL
    PUSH DE                         ; keep the format flags held in D
    CALL CONSI
    POP DE
    XOR A                           ; Z sends FFXFLV down the single-precision path

;; Formats a single or double value in PRINT USING exponential layout, with 6 or 16 digits.
FFXFLV:
    JP Z,FFXSFL                     ; Z means single precision: 6 digits
    LD E,$10                        ; E = 16 digits for double
    .byte $01

FFXSFL:
    LD E,$06
    CALL SIGN
    SCF                             ; carry marks a zero value that needs no exponent
    CALL NZ,FOUTNV                  ; scale a nonzero value, A = powers of ten applied
    POP HL
    POP BC
    PUSH AF                         ; save the scale count and the zero-value carry
    LD A,C                          ; A = digits wanted after the decimal point
    OR A
    PUSH AF
    CALL NZ,DCRART                  ; one of those places is the point itself
    ADD A,B
    LD C,A                          ; C = total digit positions in the field
    LD A,D
    AND $04                         ; bit 2 set means the sign follows the number
    CP $01
    SBC A,A                         ; A = $FF if the sign leads the field, else 0
    LD D,A
    ADD A,C                         ; a leading sign takes one digit position
    LD C,A
    SUB E                           ; A = digits beyond the precision, negative means drop
    PUSH AF
    PUSH BC

FFXLV1:
    CALL M,FINDIV                   ; divide by ten for each digit that does not fit
    JP M,FFXLV1
    POP BC
    POP AF
    PUSH BC
    PUSH AF
    JP M,FFXLV3                     ; digits were dropped: count them as zeros to add
    XOR A                           ; nothing to make up

FFXLV3:
    CPL
    INC A
    ADD A,B
    INC A
    ADD A,D
    LD B,A
    LD C,$00                        ; C = 0: no commas in exponential notation
    CALL FOUTCV                     ; write the digits
    POP AF
    CALL P,FOTZNC                   ; pad the field with zeros where digits were dropped
    POP BC
    POP AF
    CALL Z,DCXHRT                   ; no digits before the point: drop the decimal point
    POP AF
    JR C,FFXLV2                     ; zero value: exponent stays zero
    ADD A,E                         ; A = the exponent to print, adjusted for the field
    SUB B
    SUB D

FFXLV2:
    PUSH BC
    CALL FOFLDN                     ; write the E or D exponent
    EX DE,HL                        ; HL = end of the text
    POP DE                          ; DE = the field sizes for FOUTTS
    JP FOUTTS

;; Scales the accumulator by powers of ten into the 6- or 16-digit range; A gets the count.
FOUTNV:
    PUSH DE
    XOR A                           ; A = 0 powers of ten applied so far
    PUSH AF
    RST $20
    JP PO,FOUNDB                    ; single precision needs no first rough scaling

FORBIG:
    LD A,[FAC]                      ; A = the exponent byte of the double value
    CP $91                          ; $91 and up is 65536 or more, big enough already
    JP NC,FOUNDB
    LD DE,$1364                     ; multiply a small value by ten powers of ten at once
    LD HL,ARGLO
    CALL VMOVE
    CALL DMULT
    POP AF
    SUB $0A                         ; count the ten powers of ten
    PUSH AF
    JR FORBIG

;; Scales the FAC with <FOUNVC>, then for single precision compares it with 99999.95 before
;; continuing the scaling.
FOUNDB:
    CALL FOUNVC                     ; bring large values down below the upper bound

FOUNV1:
    RST $20
    JR NC,FOUT_SCALE_4              ; double precision compares against its own constant
    LD BC,$9143                     ; BC/DE = 99999.95 in single precision
    LD DE,$4FF9
    CALL FCOMP
    JR FOUT_SCALE_5

FOUT_SCALE_4:
    LD DE,$136C                     ; DE = the double-precision lower bound
    CALL DCOMPD

FOUT_SCALE_5:
.if REVISION = 12
    JP P,FOUT_SCALE_7
.else
    JP P,FOUT_SCALE_6_1
.endif
    POP AF                          ; A = scale count
    CALL FINMLT                     ; multiply by ten, counting it in A
    PUSH AF
    JR FOUNV1

FOUT_SCALE_6:
    POP AF                          ; A = scale count
    CALL FINDIV                     ; divide by ten, counting it in A
    PUSH AF
    CALL FOUNVC                     ; check again against the upper bound

.if REVISION = 12
FOUT_SCALE_7:
.else
FOUT_SCALE_6_1:
.endif
    POP AF                          ; A = plus times divided, or minus times multiplied
.if REVISION = 12
    OR A
.endif
    POP DE
.if REVISION = 13
    OR A                            ; set the sign flag from the scale count
.endif
    RET

;; Divides the accumulator by 10 until it is below the single or double output bound.
FOUNVC:
    RST $20
    JP PE,FONVC1
    LD BC,$9474                     ; BC/DE = 999999.5 in single precision
    LD DE,$23F8
    CALL FCOMP
    JR FONVC2

FONVC1:
    LD DE,$1374                     ; DE = the double-precision upper bound
    CALL DCOMPD

FONVC2:
    POP HL                          ; HL = return address, so a retry can bypass it
    JP P,FOUT_SCALE_6               ; still too big: divide by ten again
    JP [HL]                         ; return to the caller

;; Writes A '0' characters at HL, advancing HL.
FOTZER:
    OR A

FOTZR1:
    RET Z
    DEC A
    LD [HL],$30                     ; write one ASCII zero
    INC HL
    JR FOTZR1

;; Returns if Z; otherwise writes A zeros at HL with point or comma separators.
FOTZNC:
    JR NZ,FOTZEC

FOTZRC:
    RET Z
    CALL FOUTED                     ; insert the point or a comma if one is due here

;; Writes A zeros at HL, inserting the point or commas between them as counted.
FOTZEC:
    LD [HL],$30                     ; write one ASCII zero
    INC HL
    DEC A
    JR FOTZRC

;; Sets B to the digits before the point (E+D+1) and C to the comma-group counter.
FOUTCD:
    LD A,E                          ; A = powers of ten divided out
    ADD A,D                         ; plus the significant digits
    INC A
    LD B,A                          ; B = digits before the decimal point
    INC A

FOTCD1:
    SUB $03
    JR NC,FOTCD1
    ADD A,$05                       ; C = digits until the first comma, plus one

FOUTCC:
    LD C,A

;; Clears the comma counter in C unless the format flags ask for commas.
FOUICC:
    LD A,[TEMP3]
    AND $40                         ; bit 6 of the format flags asks for commas
    RET NZ
    LD C,A                          ; A is 0 here, so no commas
    RET

;; Counts a digit off B, writing the decimal point or a comma at HL when one is due.
FOUTED:
    DEC B                           ; B counts digits left before the decimal point
    JR NZ,FOUED1

;; Writes the decimal point at HL and records its address at $40F3.
FOUTDP:
    LD [HL],$2E
    LD [TEMP2],HL                   ; remember where the point went
    INC HL
    LD C,B                          ; C = 0: no commas after the decimal point
    RET

;; Counts down C to the next thousands separator, writing a comma at HL every third digit.
FOUED1:
    DEC C                           ; C counts digits left until the next comma
    RET NZ
    LD [HL],$2C
    INC HL
    LD C,$03                        ; next comma three digits later
    RET

;; Writes the single or double accumulator's integer value as decimal digits at HL.
FOUTCV:
    PUSH DE
    RST $20
    JP PO,FOUTCS
    PUSH BC
    PUSH HL
    CALL VMOVAF                     ; ARG = the value, so 0.5 can be added for rounding
    LD HL,$137C                     ; HL = DHALF, the constant 0.5
    CALL VMOVFM
    CALL DADD                       ; round to the nearest whole number
    XOR A
    CALL DINTFO                     ; drop the fraction
    POP HL
    POP BC
    LD DE,$138C                     ; DE = FODTBL, powers of ten from 10^15 down
    LD A,$0A                        ; ten digits come from the double table

;; Enters the double-precision digit loop: writes A digits at HL by subtracting powers of ten from
;; the table at DE, then converts the rest as single precision.
FOUCD1:
    CALL FOUTED
    PUSH BC
    PUSH AF
    PUSH HL
    PUSH DE
    LD B,$2F                        ; B starts one below ASCII 0

FOUCD2:
    INC B
    POP HL                          ; HL = this power of ten, kept on the stack
    PUSH HL
    CALL DADDFS                     ; subtract this power of ten once
    JR NC,FOUCD2                    ; until the value goes negative
    POP HL
    CALL DADDFO                     ; add back the last power subtracted
    EX DE,HL                        ; DE = the next, smaller power of ten
    POP HL
    LD [HL],B                       ; store the digit
    INC HL
    POP AF
    POP BC
    DEC A
    JR NZ,FOUCD1
    PUSH BC                         ; the rest is under 10^6 and fits in 24 bits
    PUSH HL
    LD HL,$411D                     ; low bytes of the double accumulator
    CALL MOVFM
    JR FOUCDC                       ; finish the last six digits as single precision

;; Rounds the single-precision FAC to an integer and writes its decimal digits at HL.
FOUTCS:
    PUSH BC
    PUSH HL
    CALL FADDH                      ; add 0.5 to round to the nearest whole number
    INC A
    CALL QINT                       ; CDE = the value as a 24-bit integer
    CALL MOVFR                      ; keep the integer in the accumulator

FOUCDC:
    POP HL
    POP BC
    XOR A                           ; clear carry, the CCF below sets it for the first pass
    LD DE,$13D2                     ; DE = FOSTBL, 100000 then 10000

;; Enters the loop that writes the two highest digits of a 24-bit integer at HL, using the table at DE.
FOUCS1:
    CCF                             ; carry set on the first pass only
    CALL FOUTED
    PUSH BC
    PUSH AF
    PUSH HL
    PUSH DE
    CALL MOVRF                      ; CDE = the remaining value
    POP HL
    LD B,$2F                        ; B starts one below ASCII 0

;; Subtracts the power of ten at HL from CDE until it goes negative, counting the digit in B.
FOUCS2:
    INC B
    LD A,E                          ; subtract the 3-byte power of ten from CDE
    SUB [HL]
    LD E,A
    INC HL
    LD A,D
    SBC A,[HL]
    LD D,A
    INC HL
    LD A,C
    SBC A,[HL]
    LD C,A
    DEC HL                          ; HL back to the start of this power
    DEC HL
    JR NC,FOUCS2                    ; until the value goes negative
    CALL FADDA                      ; add back the last power subtracted
    INC HL                          ; HL = the next power of ten
    CALL MOVFR
    EX DE,HL                        ; DE = the next table entry
    POP HL
    LD [HL],B                       ; store the digit
    INC HL
    POP AF
    POP BC
    JR C,FOUCS1                     ; second pass for the 10000 digit
    INC DE                          ; DE = 1000 in FOITBL, the value is now under 10000
    INC DE
    LD A,$04                        ; four digits remain
    JR FOUCI1

;; Writes the integer in FACLO as five decimal digits at HL, with separators.
FOUTCI:
    PUSH DE
    LD DE,$13D8                     ; DE = FOITBL, 10000 down to 1
    LD A,$05                        ; five digits for a full integer

;; Enters the integer digit loop: writes A digits of FACLO at HL using the power-of-ten table at DE.
FOUCI1:
    CALL FOUTED
    PUSH BC
    PUSH AF
    PUSH HL
    EX DE,HL
    LD C,[HL]                       ; BC = this power of ten
    INC HL
    LD B,[HL]
    PUSH BC
    INC HL
    EX [SP],HL                      ; stack keeps the next entry, HL = this power
    EX DE,HL                        ; DE = this power of ten
    LD HL,[FACLO]                   ; HL = the remaining value
    LD B,$2F                        ; B starts one below ASCII 0

;; Subtracts the power of ten in DE from HL until it goes negative, counting the digit in B.
FOUCI2:
    INC B
    LD A,L
    SUB E                           ; subtract this power of ten from HL
    LD L,A
    LD A,H
    SBC A,D
    LD H,A
    JR NC,FOUCI2                    ; until the value goes negative
    ADD HL,DE                       ; add back the last power subtracted
    LD [FACLO],HL                   ; the remainder carries on to the next digit
    POP DE
    POP HL
    LD [HL],B                       ; store the digit
    INC HL
    POP AF
    POP BC
    DEC A
    JR NZ,FOUCI1
    CALL FOUTED                     ; the decimal point may fall after the last digit
    LD [HL],A                       ; A is 0 here: terminate the text
    POP DE
    RET

;; Holds the double-precision constants number output uses: 10^10, digit range bounds and one half.
TENTEN:
    .byte $00, $00, $00, $00, $F9, $02, $15, $A2

FOUTDL:
    .byte $FD, $FF, $9F, $31, $A9, $5F, $63, $B2

FOUTDU:
    .byte $FE, $FF, $03, $BF, $C9, $1B, $0E, $B6

DHALF:
    .byte $00, $00, $00, $00

FHALF:
    .byte $00, $00, $00, $80

FFXDXM:
    .byte $00, $00, $04, $BF, $C9, $1B, $0E, $B6

;; Holds the powers of ten from 10^15 down to 10^6 as 7-byte integers, for double-precision output.
FODTBL:
    .byte $00, $80, $C6, $A4, $7E, $8D, $03, $00, $40, $7A, $10, $F3, $5A, $00, $00, $A0, $72, $4E, $18, $09, $00, $00, $10, $A5, $D4, $E8, $00, $00, $00, $E8, $76, $48, $17, $00, $00, $00, $E4, $0B, $54, $02, $00, $00, $00, $CA, $9A, $3B, $00, $00, $00, $00, $E1, $F5, $05, $00, $00, $00, $80, $96, $98, $00, $00, $00, $00, $40, $42, $0F, $00, $00, $00, $00

;; Holds 100000 and 10000 as 3-byte integers, for single-precision output.
FOSTBL:
    .byte $A0, $86, $01, $10, $27, $00

;; Holds the powers of ten from 10000 down to 1 as 16-bit integers, for integer output.
FOITBL:
    .byte $10, $27, $E8, $03, $64, $00, $0A, $00, $01, $00

;; Makes the caller's return go through NEG, then resumes the caller.
PSHNEG:
    LD HL,NEG
    EX [SP],HL                      ; caller's return now goes through NEG
    JP [HL]                         ; resume the caller
;; Computes SQR: the square root of the FAC, as the FAC raised to the power 0.5.
FN_SQR:
    CALL PUSHF                      ; save x as the base
    LD HL,$1380                     ; HL = FHALF, the constant 0.5
    CALL MOVFM
    JR FPWRT                        ; SQR(x) = x ^ 0.5

;; Applies the ^ operator: raises the number on the stack to the power in the FAC, as single precision.
FPWRQ:
    CALL FRCSNG                     ; the power must be single precision
;; Pops the base from the stack into BCDE and raises it to the power in the FAC (<FPWR>).
FPWRT:
    POP BC
    POP DE

;; Raises BCDE to the power in the FAC, leaving the result in the FAC; zero to a negative power is
;; a ?/0 error.
FPWR:
    CALL SIGN                       ; test the power
    LD A,B                          ; A = exponent byte of the base, zero if the base is 0
    JR Z,FN_EXP                     ; anything to the power zero is 1, which EXP(0) gives
    JP P,POSEXP                     ; positive power: zero base is fine
    OR A
    JP Z,DV0ERR                     ; zero to a negative power divides by zero
;; Continues the power routine with a nonzero exponent: a zero base gives 0, and a negative base
;; needs an integer exponent.
POSEXP:
    OR A
    JP Z,ZERO0                      ; zero to a positive power is zero
    PUSH DE
    PUSH BC
    LD A,C                          ; A = sign byte of the base
    OR $7F
    CALL MOVRF                      ; BCDE = the power
    JP P,FPWR1                      ; positive base: no sign worries
    PUSH DE
    PUSH BC
    CALL INT                        ; a negative base needs a whole-number power
    POP BC
    POP DE
    PUSH AF                         ; keep the integer part of the power
    CALL FCOMP                      ; Z if the power was already a whole number
    POP HL
    LD A,H                          ; A = low byte of the integer power
    RRA                             ; carry = an odd power
;; Computes the power as EXP(exponent * LOG(base)), fixing the sign for a negative base.
FPWR1:
    POP HL                          ; put the base back into the accumulator
    LD [FACHI],HL
    POP HL
    LD [FACLO],HL
    CALL C,PSHNEG                   ; odd power of a negative base: negate the result
    CALL Z,NEG                      ; whole power: take the log of the base's magnitude
    PUSH DE                         ; keep the power for the multiply
    PUSH BC
    CALL FN_LOG
    POP BC
    POP DE
    CALL FMULT                      ; power times the log of the base
;; Computes EXP: e raised to the FAC, leaving the result in the FAC; too large a result overflows.
FN_EXP:
    CALL PUSHF                      ; save x
    LD BC,$8138                     ; BC/DE = 1/ln 2
    LD DE,$AA3B
    CALL FMULT                      ; x/ln 2 = x as a power of two
    LD A,[FAC]                      ; A = exponent byte of that power of two
    CP $88                          ; 2^128 or more overflows
    JP NC,MLDVEX
    CALL INT                        ; A = the whole part of the power of two
    ADD A,$80                       ; A becomes the exponent byte of the result
    ADD A,$02
    JP C,MLDVEX                     ; carry means the result would overflow
    PUSH AF                         ; save the result's exponent byte
    LD HL,$07F8                     ; HL = the constant 1.0
    CALL FADDS
    CALL MULLN2                     ; times ln 2
    POP AF
    POP BC
    POP DE
    PUSH AF
    CALL FSUB                       ; the remainder of x past the whole powers of two
    CALL NEG                        ; make it positive for the series
    LD HL,$1479                     ; HL = EXPCON, the series coefficients
    CALL POLY
    LD DE,RESET                     ; BCDE = 2 to the whole power, mantissa bytes zero
    POP BC
    LD C,D                          ; C = 0 too
    JP FMULT                        ; scale the series result by that power of two

;; Holds the count and coefficients of the polynomial EXP uses.
EXPCON:
    .byte $08, $40, $2E, $94, "tpO.wn"
    .byte $02, $88, $7A, $E6, $A0, $2A, $7C, $50, $AA, $AA, $7E, $FF, $FF, $7F, $7F, $00, $00, $80, $81, $00, $00, $00, $81

;; Evaluates the odd polynomial x*P(x^2) for the accumulator, coefficient table at HL.
POLYX:
    CALL PUSHF
    LD DE,$0C32                     ; return through code that multiplies the sum by x
    PUSH DE                         ; returned to once the series is done
    PUSH HL
    CALL MOVRF
    CALL FMULT                      ; square x
    POP HL

;; Evaluates the polynomial whose count and coefficients are at HL for the accumulator.
POLY:
    CALL PUSHF                      ; save x for each step of the series
    LD A,[HL]                       ; A = number of coefficients
    INC HL
    CALL MOVFM                      ; accumulator = the first coefficient
    .byte $06                       ; LD B,n: skips the next instruction

POLY1:
    POP AF                          ; A = coefficients left
    POP BC                          ; BCDE = x
    POP DE
    DEC A                           ; one coefficient used
    RET Z                           ; all terms done
    PUSH DE
    PUSH BC
    PUSH AF
    PUSH HL
    CALL FMULT                      ; running sum times x
    POP HL
    CALL MOVRM                      ; BCDE = the next coefficient
    PUSH HL
    CALL FADD                       ; plus the next coefficient
    POP HL
    JR POLY1
;; Computes RND(n): a random integer from 1 to n, or a fraction below 1 for RND(0); n < 0 is an
;; ?FC error.
FN_RND:
    CALL FRCINT                     ; HL = n
    LD A,H
    OR A
    JP M,FCERR                      ; negative n is illegal
    OR L
    JP Z,RND0                       ; RND(0) returns the bare fraction
    PUSH HL                         ; save n
    CALL RND0                       ; a fraction from 0 to 1
    CALL MOVRF
    EX DE,HL
    EX [SP],HL                      ; stack holds the fraction, HL = n
    PUSH BC
    CALL CONSIH                     ; accumulator = n as single precision
    POP BC
    POP DE
    CALL FMULT                      ; fraction times n
    LD HL,$07F8                     ; HL = the constant 1.0
    CALL FADDS
    JP INT                          ; whole part gives 1 to n

;; Advances the random seed and returns the next random number between 0 and 1.
RND0:
    LD HL,$4090                     ; HL = the 3-byte seed multiplier at $4090
    PUSH HL
    LD DE,RESET                     ; CDE = 0, the product being built
    LD C,E
    LD H,$03                        ; H = three multiplier bytes

;; Enters the random seed multiply for the next seed byte, with eight bits to process.
RNDO0:
    LD L,$08                        ; L = eight bits in each byte

;; Enters the random seed multiply's bit loop: shifts CDE left and adds the multiplier for a set bit.
RND1:
    EX DE,HL                        ; shift the product left one bit
    ADD HL,HL
    EX DE,HL
    LD A,C
    RLA
    LD C,A
    EX [SP],HL                      ; HL = pointer into the multiplier
    LD A,[HL]
    RLCA                            ; rotate the next multiplier bit into carry
    LD [HL],A
    EX [SP],HL                      ; HL = the loop counters again
    JP NC,RND2                      ; bit clear: no add this time
    PUSH HL
    LD HL,[RNDX]                    ; add the seed into the product
    ADD HL,DE
    EX DE,HL
    LD A,[RND_SEED_HIGH]            ; high byte of the seed
    ADC A,C
    LD C,A
    POP HL                          ; HL = the loop counters again

;; Ends one bit of the random seed multiply; after the last byte, stores the new seed and normalizes
;; it into the FAC as a fraction.
RND2:
    DEC L
    JP NZ,RND1                      ; next bit
    EX [SP],HL                      ; next multiplier byte
    INC HL
    EX [SP],HL
    DEC H
    JP NZ,RNDO0                     ; next byte
    POP HL
    LD HL,$B065                     ; HL = constant added to the low seed bytes
    ADD HL,DE
    LD [RNDX],HL                    ; the new seed
    CALL VALSNG                     ; the result is a single-precision fraction
    LD A,$05                        ; high byte gets 5 plus the carry
    ADC A,C
    LD [RND_SEED_HIGH],A            ; new high seed byte
    EX DE,HL
    LD B,$80                        ; B = $80, the exponent of a fraction below 1
    LD HL,$4125                     ; HL = the accumulator's sign byte
    LD [HL],B                       ; the result is positive
    DEC HL                          ; HL = the accumulator's exponent byte
    LD [HL],B                       ; exponent $80 keeps the value below 1
    LD C,A                          ; C = high byte of the new seed, top of the mantissa
    LD B,$00
    JP NORMAL                       ; normalize the fraction into the accumulator
;; Computes COS of the FAC in radians, as the sine of the FAC plus pi/2.
FN_COS:
    LD HL,$158B                     ; HL = PI2, the constant pi/2
    CALL FADDS                      ; COS(x) = SIN(x + pi/2)
;; Computes SIN of the FAC in radians, reducing the angle by 2*pi before evaluating a polynomial.
FN_SIN:
    CALL PUSHF                      ; save x
    LD BC,$8349                     ; BC/DE = 2 pi
    LD DE,$0FDB
    CALL MOVFR
    POP BC
    POP DE
    CALL FDIV                       ; x / 2 pi = the angle in whole turns
    CALL PUSHF                      ; keep the turns
    CALL INT                        ; whole number of turns
    POP BC
    POP DE
    CALL FSUB                       ; leave the fraction of a turn
    LD HL,$158F                     ; HL = FR4, the constant 0.25
    CALL FSUBS                      ; fraction minus a quarter turn
    CALL SIGN
    SCF                             ; carry = no sign flip for the result
    JP P,SIN1
    CALL FADDH
    CALL SIGN
    OR A
SIN1:
    PUSH AF                         ; save the quadrant flags
    CALL P,NEG
    LD HL,$158F                     ; HL = FR4, the constant 0.25
    CALL FADDS
    POP AF                          ; carry clear: flip the sign for this quadrant
    CALL NC,NEG
    LD HL,$1593                     ; HL = SINCON, the sine series coefficients
    JP POLYX                        ; evaluate the odd series in the reduced angle

;; Holds the constants SIN and COS use: pi/2, 1/4 and the sine polynomial's coefficients.
PI2:
    .byte $DB, $0F, $49, $81

FR4:
    .byte $00, $00, $00, $7F

SINCON:
    .byte $05, $BA, $D7, $1E, $86, $64, $26, $99, $87, $58, $34, $23, $87, $E0, $5D, $A5, $86, $DA, $0F, $49, $83
;; Computes TAN of the FAC in radians, as its sine divided by its cosine.
FN_TAN:
    CALL PUSHF                      ; save x
    CALL FN_SIN
    POP BC                          ; recover x
    POP HL
    CALL PUSHF                      ; save SIN(x)
    EX DE,HL                        ; BCDE = x
    CALL MOVFR                      ; accumulator = x again
    CALL FN_COS
    JP FDIVT                        ; TAN = SIN / COS
;; Computes ATN of the FAC in radians, using pi/2 - ATN(1/x) for arguments of 1 or more.
FN_ATN:
    CALL SIGN
    CALL M,PSHNEG                   ; negative x: the result is negated on return
    CALL M,NEG                      ; work with the magnitude of x
    LD A,[FAC]                      ; A = exponent byte of x
    CP $81                          ; $81 and up means x is 1 or more
    JR C,ATN2                       ; below 1: use the series directly
    LD BC,$8100                     ; BC/DE = 1.0, D and E zeroed below
    LD D,C
    LD E,C
    CALL FDIV                       ; accumulator = 1/x
    LD HL,FSUBS                     ; return through FSUBS to form pi/2 minus the series
    PUSH HL
ATN2:
    LD HL,$15E3                     ; HL = ATNCON, the arctangent series coefficients
    CALL POLYX
    LD HL,$158B                     ; HL = PI2, used by FSUBS for x of 1 or more
    RET

;; Holds the count and coefficients of the polynomial ATN uses.
ATNCON:
    .byte $09, $4A, $D7, $3B, $78, $02, $6E, $84, $7B, $FE, $C1, $2F, $7C, $74, $31, $9A, $7D, $84, $3D, $5A, $7D, $C8, $7F, $91, $7E, $E4, $BB, $4C, $7E, $6C, $AA, $AA, $7F, $00, $00, $00, $81

;; Lists the addresses of the BASIC function handlers in token order, starting with SGN.
FUNDSP:
    .word FN_SGN                    ; SGN
    .word FN_INT                    ; INT
    .word FN_ABS                    ; ABS
    .word FN_FRE                    ; FRE
    .word FN_INP                    ; INP
    .word FN_POS                    ; POS

SQRFIX:
    .word FN_SQR                    ; SQR

RNDFIX:
    .word FN_RND                    ; RND
    .word FN_LOG                    ; LOG
    .word FN_EXP                    ; EXP

COSFIX:
    .word FN_COS                    ; COS

SINFIX:
    .word FN_SIN                    ; SIN

TANFIX:
    .word FN_TAN                    ; TAN

ATNFIX:
    .word FN_ATN                    ; ATN
    .word FN_PEEK                   ; PEEK
    .word HOOK_CVI                  ; CVI
    .word HOOK_CVS                  ; CVS
    .word HOOK_CVD                  ; CVD
    .word HOOK_EOF                  ; EOF
    .word HOOK_LOC                  ; LOC
    .word HOOK_LOF                  ; LOF
    .word HOOK_MKI                  ; MKI$
    .word HOOK_MKS                  ; MKS$
    .word HOOK_MKD                  ; MKD$
    .word FRCINT                    ; CINT
    .word FRCSNG                    ; CSNG
    .word FRCDBL                    ; CDBL
    .word FN_FIX                    ; FIX
    .word FN_LEN                    ; LEN
    .word FN_STR                    ; STR$
    .word FN_VAL                    ; VAL
    .word FN_ASC                    ; ASC
    .word FN_CHR                    ; CHR$
    .word FN_LEFT                   ; LEFT$
    .word FN_RIGHT                  ; RIGHT$
    .word FN_MID                    ; MID$

;; Lists the BASIC reserved words in token order, starting with END; a word's position is its token.
KEYWORDS:
    KEYWORD "END"                   ; TK_END

FOR:
    KEYWORD "FOR"                   ; TK_FOR
    KEYWORD "RESET"                 ; TK_RESET
    KEYWORD "SET"                   ; TK_SET
    KEYWORD "CLS"                   ; TK_CLS
    KEYWORD "CMD"                   ; TK_CMD
    KEYWORD "RANDOM"                ; TK_RANDOM

NEXT:
    KEYWORD "NEXT"                  ; TK_NEXT

DATA:
    KEYWORD "DATA"                  ; TK_DATA

INPUT:
    KEYWORD "INPUT"                 ; TK_INPUT
    KEYWORD "DIM"                   ; TK_DIM
    KEYWORD "READ"                  ; TK_READ
    KEYWORD "LET"                   ; TK_LET

GOTO:
    KEYWORD "GOTO"                  ; TK_GOTO
    KEYWORD "RUN"                   ; TK_RUN

IF:
    KEYWORD "IF"                    ; TK_IF
    KEYWORD "RESTORE"               ; TK_RESTORE

GOSUB:
    KEYWORD "GOSUB"                 ; TK_GOSUB
    KEYWORD "RETURN"                ; TK_RETURN

REM:
    KEYWORD "REM"                   ; TK_REM
    KEYWORD "STOP"                  ; TK_STOP

ELSE:
    KEYWORD "ELSE"                  ; TK_ELSE
    KEYWORD "TRON"                  ; TK_TRON
    KEYWORD "TROFF"                 ; TK_TROFF
    KEYWORD "DEFSTR"                ; TK_DEFSTR
    KEYWORD "DEFINT"                ; TK_DEFINT
    KEYWORD "DEFSNG"                ; TK_DEFSNG
    KEYWORD "DEFDBL"                ; TK_DEFDBL
    KEYWORD "LINE"                  ; TK_LINE
    KEYWORD "EDIT"                  ; TK_EDIT
    KEYWORD "ERROR"                 ; TK_ERROR
    KEYWORD "RESUME"                ; TK_RESUME
    KEYWORD "OUT"                   ; TK_OUT
    KEYWORD "ON"                    ; TK_ON
    KEYWORD "OPEN"                  ; TK_OPEN
    KEYWORD "FIELD"                 ; TK_FIELD
    KEYWORD "GET"                   ; TK_GET
    KEYWORD "PUT"                   ; TK_PUT
    KEYWORD "CLOSE"                 ; TK_CLOSE
    KEYWORD "LOAD"                  ; TK_LOAD
    KEYWORD "MERGE"                 ; TK_MERGE
    KEYWORD "NAME"                  ; TK_NAME
    KEYWORD "KILL"                  ; TK_KILL
    KEYWORD "LSET"                  ; TK_LSET
    KEYWORD "RSET"                  ; TK_RSET
    KEYWORD "SAVE"                  ; TK_SAVE
    KEYWORD "SYSTEM"                ; TK_SYSTEM
    KEYWORD "LPRINT"                ; TK_LPRINT
    KEYWORD "DEF"                   ; TK_DEF
    KEYWORD "POKE"                  ; TK_POKE

PRINT:
    KEYWORD "PRINT"                 ; TK_PRINT
    KEYWORD "CONT"                  ; TK_CONT
    KEYWORD "LIST"                  ; TK_LIST
    KEYWORD "LLIST"                 ; TK_LLIST
    KEYWORD "DELETE"                ; TK_DELETE
    KEYWORD "AUTO"                  ; TK_AUTO
    KEYWORD "CLEAR"                 ; TK_CLEAR
    KEYWORD "CLOAD"                 ; TK_CLOAD
    KEYWORD "CSAVE"                 ; TK_CSAVE

NEW:
    KEYWORD "NEW"                   ; TK_NEW

TABTK:
    KEYWORD "TAB("                  ; TK_TAB

TO:
    KEYWORD "TO"                    ; TK_TO

FNTK:
    KEYWORD "FN"                    ; TK_FN

USINTK:
    KEYWORD "USING"                 ; TK_USING

VARPTR:
    KEYWORD "VARPTR"                ; TK_VARPTR

USRTK:
    KEYWORD "USR"                   ; TK_USR

ERLTK:
    KEYWORD "ERL"                   ; TK_ERL

ERCTK:
    KEYWORD "ERR"                   ; TK_ERR

STRING:
    KEYWORD "STRING$"               ; TK_STRING

INSRTK:
    KEYWORD "INSTR"                 ; TK_INSTR
    KEYWORD "POINT"                 ; TK_POINT

TIME:
    KEYWORD "TIME$"                 ; TK_TIME
    KEYWORD "MEM"                   ; TK_MEM
    KEYWORD "INKEY$"                ; TK_INKEY

THENTK:
    KEYWORD "THEN"                  ; TK_THEN

NOTTK:
    KEYWORD "NOT"                   ; TK_NOT

STEPTK:
    KEYWORD "STEP"                  ; TK_STEP

PLUSTK:
    KEYWORD "+"                     ; TK_PLUS

MINUTK:
    KEYWORD "-"                     ; TK_MINUS

MULTK:
    KEYWORD "*"                     ; TK_TIMES
    KEYWORD "/"                     ; TK_DIVIDE
    KEYWORD "["                     ; TK_POWER
    KEYWORD "AND"                   ; TK_AND
    KEYWORD "OR"                    ; TK_OR

GREATK:
    KEYWORD ">"                     ; TK_GREATER

EQULTK:
    KEYWORD "="                     ; TK_EQUAL

LESSTK:
    KEYWORD "<"                     ; TK_LESS

ONEFUN:
    KEYWORD "SGN"                   ; TK_SGN
    KEYWORD "INT"                   ; TK_INT
    KEYWORD "ABS"                   ; TK_ABS
    KEYWORD "FRE"                   ; TK_FRE
    KEYWORD "INP"                   ; TK_INP
    KEYWORD "POS"                   ; TK_POS

SQRTK:
    KEYWORD "SQR"                   ; TK_SQR
    KEYWORD "RND"                   ; TK_RND
    KEYWORD "LOG"                   ; TK_LOG
    KEYWORD "EXP"                   ; TK_EXP
    KEYWORD "COS"                   ; TK_COS
    KEYWORD "SIN"                   ; TK_SIN
    KEYWORD "TAN"                   ; TK_TAN

ATNTK:
    KEYWORD "ATN"                   ; TK_ATN
    KEYWORD "PEEK"                  ; TK_PEEK
    KEYWORD "CVI"                   ; TK_CVI
    KEYWORD "CVS"                   ; TK_CVS
    KEYWORD "CVD"                   ; TK_CVD
    KEYWORD "EOF"                   ; TK_EOF
    KEYWORD "LOC"                   ; TK_LOC
    KEYWORD "LOF"                   ; TK_LOF
    KEYWORD "MKI$"                  ; TK_MKI
    KEYWORD "MKS$"                  ; TK_MKS
    KEYWORD "MKD$"                  ; TK_MKD
    KEYWORD "CINT"                  ; TK_CINT
    KEYWORD "CSNG"                  ; TK_CSNG
    KEYWORD "CDBL"                  ; TK_CDBL
    KEYWORD "FIX"                   ; TK_FIX
    KEYWORD "LEN"                   ; TK_LEN
    KEYWORD "STR$"                  ; TK_STR
    KEYWORD "VAL"                   ; TK_VAL
    KEYWORD "ASC"                   ; TK_ASC

LASNUM:
    KEYWORD "CHR$"                  ; TK_CHR
    KEYWORD "LEFT$"                 ; TK_LEFT
    KEYWORD "RIGHT$"                ; TK_RIGHT

MIDTK:
    KEYWORD "MID$"                  ; TK_MID

SNGQTK:
    KEYWORD "'"                     ; TK_APOSTROPHE
    .byte $80                       ; the end of the list

;; Lists the addresses of the BASIC statement handlers in token order, starting with END.
STMDSP:
    .word ST_END                    ; END
    .word ST_FOR                    ; FOR
    .word ST_RESET                  ; RESET
    .word ST_SET                    ; SET
    .word CLS                       ; CLS
    .word HOOK_CMD                  ; CMD
    .word ST_RANDOM                 ; RANDOM
    .word ST_NEXT                   ; NEXT
    .word ST_DATA                   ; DATA
    .word ST_INPUT                  ; INPUT
    .word ST_DIM                    ; DIM
    .word ST_READ                   ; READ
    .word ST_LET                    ; LET
    .word ST_GOTO                   ; GOTO
    .word ST_RUN                    ; RUN
    .word ST_IF                     ; IF
    .word ST_RESTORE                ; RESTORE
    .word ST_GOSUB                  ; GOSUB
    .word ST_RETURN                 ; RETURN
    .word ST_REM                    ; REM
    .word ST_STOP                   ; STOP

IOGOR:
    .word ST_REM                    ; ELSE
    .word ST_TRON                   ; TRON
    .word ST_TROFF                  ; TROFF
    .word ST_DEFSTR                 ; DEFSTR
    .word ST_DEFINT                 ; DEFINT
    .word ST_DEFSNG                 ; DEFSNG
    .word ST_DEFDBL                 ; DEFDBL
    .word HOOK_LINE                 ; LINE
    .word ST_EDIT                   ; EDIT
    .word ST_ERROR                  ; ERROR
    .word ST_RESUME                 ; RESUME
    .word ST_OUT                    ; OUT
    .word ST_ON                     ; ON
    .word HOOK_OPEN                 ; OPEN
    .word HOOK_FIELD                ; FIELD
    .word HOOK_GET                  ; GET
    .word HOOK_PUT                  ; PUT
    .word HOOK_CLOSE                ; CLOSE
    .word HOOK_LOAD                 ; LOAD
    .word HOOK_MERGE                ; MERGE
    .word HOOK_NAME                 ; NAME
    .word HOOK_KILL                 ; KILL
    .word HOOK_LSET                 ; LSET
    .word HOOK_RSET                 ; RSET
    .word HOOK_SAVE                 ; SAVE
    .word ST_SYSTEM                 ; SYSTEM
    .word ST_LPRINT                 ; LPRINT
    .word HOOK_DEF                  ; DEF
    .word ST_POKE                   ; POKE
    .word ST_PRINT                  ; PRINT
    .word ST_CONT                   ; CONT
    .word ST_LIST                   ; LIST
    .word ST_LLIST                  ; LLIST
    .word ST_DELETE                 ; DELETE
    .word ST_AUTO                   ; AUTO
    .word ST_CLEAR                  ; CLEAR
    .word ST_CLOAD                  ; CLOAD
    .word ST_CSAVE                  ; CSAVE
    .word ST_NEW                    ; NEW

;; Holds the precedence of the operators +, -, *, /, ^, AND and OR, in that order.
OPTAB:
    .byte $79, $79, $7C, $7C, $7F, $50, $46

;; Holds the addresses of the routines that convert a value to a variable's type on assignment.
FRCTBL:
    .byte $DB, $0A, $00, $00, $7F, $0A, $F4, $0A, $B1, $0A

;; Holds the addresses of the double-precision add, subtract, multiply, divide and compare routines.
DBLDSP:
    .byte $77, $0C, $70, $0C, $A1, $0D, $E5, $0D, $78, $0A

;; Holds the addresses of the single-precision add, subtract, multiply, divide and compare routines.
SNGDSP:
    .byte $16, $07, $13, $07, $47, $08, $A2, $08, $0C, $0A

;; Holds the addresses of the integer add, subtract, multiply, divide and compare routines.
INTDSP:
    .byte $D2, $0B, $C7, $0B, $F2, $0B, $90, $24, $39, $0A

;; Holds the two-letter error codes, in error number order, starting with NF.
ERROR_CODES:
    .byte "NF"                      ; NEXT without FOR

ERRSN:
    .byte "SN"                      ; syntax error

ERRRG:
    .byte "RG"                      ; RETURN without GOSUB

ERROD:
    .byte "OD"                      ; out of DATA

ERRFC:
    .byte "FC"                      ; illegal function call

ERROV:
    .byte "OV"                      ; overflow

ERROM:
    .byte "OM"                      ; out of memory

ERRUS:
    .byte "UL"                      ; undefined line

ERRBS:
    .byte "BS"                      ; subscript out of range

ERRDD:
    .byte "DD"                      ; redimensioned array

ERRDV0:
    .byte "/0"                      ; division by zero

ERRID:
    .byte "ID"                      ; illegal direct

ERRTM:
    .byte "TM"                      ; type mismatch

ERRSO:
    .byte "OS"                      ; out of string space

ERRLS:
    .byte "LS"                      ; string too long

ERRST:
    .byte "ST"                      ; string formula too complex

ERRCN:
    .byte "CN"                      ; can't continue

ERRNR:
    .byte "NR"                      ; no RESUME

ERRRE:
    .byte "RW"                      ; RESUME without error

ERRUE:
    .byte "UE"                      ; unprintable error

ERRMO:
    .byte "MO"                      ; missing operand

ERRFD:
    .byte "FD"                      ; bad file data

ERRL3:
    .byte "L3"                      ; Disk BASIC only
    SUB $00                         ; operand bytes are patched in the RAM copy at run time
    LD L,A
    LD A,H
    SBC A,$00
    LD H,A
    LD A,B
    SBC A,$00
    LD B,A
    LD A,$00
    RET
    .byte $4A, $1E, $40, $E6, $4D
    IN A,[$00]                      ; port number is patched in the RAM copy for INP
    RET
    OUT [$00],A                     ; port number is patched in the RAM copy for OUT
    RET
    .byte $00, $00, $00, $00, $40, $30, $00, $4C, $43, $FE, $FF, $E9, $42

;; Holds the error and status message texts: " Error", " in ", READY and Break.
ERR:
    .byte " Error", $00

INTXT:
    .byte $20, $69, $6E, $20, $00

READY_MSG:
    .byte "READY", $0D
    .byte $00

BREAK_MSG:
    .byte "Break", $00

;; Searches the stack for the FOR entry of the loop variable at DE, or of any loop when DE is 0.
;; In:    DE = address of the loop variable, or 0
;; Out:   zero = set when found, HL = the entry past its variable address
FNDFOR:
    LD HL,$0004                     ; skip the return addresses above the FOR entries
    ADD HL,SP
LOOPER:
    LD A,[HL]
    INC HL
    CP $81                          ; $81 is the FOR token that marks a FOR entry
    RET NZ                          ; no more FOR entries on the stack
    LD C,[HL]                       ; BC = address of this loop's variable
    INC HL
    LD B,[HL]
    INC HL
    PUSH HL                         ; save the pointer past the variable address
    LD L,C
    LD H,B
    LD A,D                          ; DE = 0 means any FOR entry matches
    OR E
    EX DE,HL
    JR Z,POPGOF
    EX DE,HL
    RST $18                         ; Z if this entry is for the variable in DE
POPGOF:
    LD BC,$000E                     ; BC = bytes from here to the next stack entry
    POP HL                          ; HL = the entry, just past its variable address
    RET Z
    ADD HL,BC                       ; step over this entry to the one below it
    JR LOOPER

;; Checks memory room (REASON), then moves a block up in memory (BLTUC).
BLTU:
    CALL REASON

;; Copies bytes downward from HL to BC until HL reaches DE (moves a block up in memory).
BLTUC:
    PUSH BC
    EX [SP],HL                      ; swap HL and BC
    POP BC

BLTLOP:
    RST $18                         ; Z once the source reaches the end address in DE
    LD A,[HL]
    LD [BC],A
    RET Z
    DEC BC
    DEC HL
    JR BLTLOP

;; Checks that 2*C more bytes fit above the arrays, with an ?OM error otherwise.
;; In:    C = the number of two-byte entries needed
GETSTK:
    PUSH HL
    LD HL,[STREND]                  ; HL = end of the arrays, start of free memory
    LD B,$00                        ; BC = the entry count
    ADD HL,BC
    ADD HL,BC                       ; HL = free memory plus two bytes per entry
    .byte $3E                       ; LD A,n: skips the next instruction

;; Checks that HL is far enough below the stack, with an ?OM error otherwise.
;; In:    HL = the highest address that will be used
REASON:
    PUSH HL
    LD A,$C6                        ; HL = $FFC6 minus the address, so ADD HL,SP tests room
    SUB L
    LD L,A
    LD A,$FF
    SBC A,H
    JR C,OMERR                      ; an address that high can never fit
    LD H,A
    ADD HL,SP                       ; carry if the stack is clear of the address
    POP HL
    RET C                           ; enough room
;; Reports an ?OM (out of memory) error through <ERROR>.
OMERR:
    LD E,ERR_OM
    JR ERROR
;; Ends a run at the end of the program text, with an ?NR error if an error handler never resumed.
PRGEND:
    LD HL,[CURLIN]                  ; HL = current line, $FFFF in direct mode
    LD A,H
    AND L
    INC A                           ; Z when the line number is $FFFF
    JR Z,ENDCNJ                     ; direct mode: just end
    LD A,[ONEFLG]                   ; nonzero means an ON ERROR handler is still running
    OR A
    LD E,ERR_NR
    JR NZ,ERROR                     ; the handler reached the end without RESUME
;; Jumps to <ENDCON> to end the run.
ENDCNJ:
    JP ENDCON
;; Reports a ?SN error in a DATA statement, making the DATA line the current line.
DATSNE:
    LD HL,[DATLIN]                  ; HL = line number of the bad DATA statement
    LD [CURLIN],HL                  ; report the error against the DATA line
;; Reports a ?SN (syntax) error through <ERROR>.
SNERR:
    LD E,ERR_SN
    .byte $01                       ; LD BC,nn: skips the next instruction
;; Reports a ?/0 (division by zero) error through <ERROR>.
DV0ERR:
    LD E,ERR_DV0
    .byte $01                       ; LD BC,nn: skips the next instruction
;; Reports an ?NF (NEXT without FOR) error through <ERROR>.
NFERR:
    LD E,ERR_NF
    .byte $01
REERR:
    LD E,ERR_RW

;; Reports the error whose code is in E: an ON ERROR handler takes it if one is set; otherwise prints ?xx
;; ERROR, the line, and READY.
ERROR:
    LD HL,[CURLIN]
    LD [ERRLIN],HL                  ; ERRLIN is the line ERL returns
    LD [DOT],HL                     ; DOT makes this the current line for EDIT and LIST .
;; Enters the error handler after the error line is recorded, resetting the stack before going on.
ERRESM:
    LD BC,$19B4                     ; BC = ERRMOR, resumed once the stack is reset
;; Resets the stack from SAVSTK through <STKERR>, then resumes at the address in BC.
ERESET:
    LD HL,[SAVSTK]                  ; HL = the stack pointer saved for the running statement
    JP STKERR

;; Records the error code, line and text position, then jumps to an ON ERROR GOTO line if one is set
;; and no handler is running.
ERRMOR:
    POP BC                          ; discard the stack's top entry
    LD A,E
    LD C,E                          ; C keeps the error code
    LD [ERRFLG],A                   ; ERRFLG is the code ERR returns
    LD HL,[SAVTXT]                  ; HL = text position of the failing statement
    LD [ERRTXT],HL                  ; RESUME restarts from here
    EX DE,HL
    LD HL,[ERRLIN]                  ; HL = the line with the error
    LD A,H
    AND L
    INC A                           ; Z when the line number is $FFFF
    JR Z,NTMDCN                     ; direct mode cannot be continued
    LD [OLDLIN],HL                  ; line and position for CONT
    EX DE,HL
    LD [OLDTXT],HL
NTMDCN:
    LD HL,[ONELIN]                  ; HL = the ON ERROR GOTO line pointer, 0 if none
    LD A,H
    OR L                            ; zero means no ON ERROR GOTO is set
    EX DE,HL
    LD HL,ONEFLG                    ; HL = flag set while an error handler runs
    JR Z,NOTRAP
    AND [HL]                        ; already in a handler: an error there is fatal
    JR NZ,NOTRAP
    DEC [HL]                        ; mark the handler as running
    EX DE,HL
    JP GONE4                        ; continue the program at the handler line
;; Prints the error as ?xx ERROR, with the line number in a program, then returns to READY.
NOTRAP:
    XOR A
    LD [HL],A                       ; no handler is running now
    LD E,C                          ; E = the error code, an offset into ERROR_CODES
    CALL CRDONZ
    LD HL,ERROR_CODES
    CALL HOOK_ERROR_MSG             ; DOS can print its own long error message here
    LD D,A                          ; D = 0 so DE is the code's offset
    LD A,$3F
    CALL OUTDO
    ADD HL,DE                       ; HL = the two letters of the code
    LD A,[HL]
    CALL OUTDO
    RST $10                         ; second letter of the code
    CALL OUTDO
    LD HL,ERR                       ; HL = the " Error" text
    PUSH HL                         ; stack holds the text address
    LD HL,[ERRLIN]
    EX [SP],HL                      ; stack holds the error line, HL = the text
;; Prints the message at HL and, unless in direct mode, " in " and the line number, then READY.
ERRFIN:
    CALL STROUT
    POP HL                          ; HL = the line with the error
    LD DE,$FFFE                     ; line $FFFE marks an error during startup
    RST $18
    JP Z,INIT                       ; restart the initialization
    LD A,H
    AND L
    INC A                           ; Z when the line number is $FFFF
    CALL NZ,INPRT                   ; in a program: print " in" and the line number
    .byte $3E                       ; LD A,n: skips the next instruction
;; Discards one stack entry, then prints READY and enters the command loop.
STPRDY:
    POP BC                          ; discard the stack's top entry

;; Prints READY and falls into MAIN.
READY:
    CALL FINLPT
    CALL HOOK_READY
    CALL CASSETTE_OFF
    CALL CRDONZ
    LD HL,READY_MSG

;; Prints the message at HL, starts EDIT on the line after a syntax error, then enters MAIN.
REPINI:
    CALL STROUT
    LD A,[ERRFLG]                   ; A = the last error code
    SUB $02                         ; 2 is the ?SN error code
    CALL Z,ERREDT                   ; after ?SN, edit the bad line

;; The command loop: reads a line, stores it when it has a number, or runs it.
MAIN:
    LD HL,$FFFF                     ; line $FFFF marks direct mode
    LD [CURLIN],HL
    LD A,[AUTFLG]                   ; nonzero while AUTO numbering is on
    OR A
    JR Z,NTAUTO
    LD HL,[AUTLIN]                  ; HL = the next AUTO line number
    PUSH HL
    CALL LINPRT                     ; print it as the prompt
    POP DE
    PUSH DE
    CALL FNDLIN                     ; does that line already exist
    LD A,$2A                        ; * warns that the line exists
    JR C,AUTELN
    LD A,$20                        ; a space when it is a new line
;; Prints the character in A after the AUTO line number, then reads the line typed.
AUTELN:
    CALL OUTDO
    CALL INLIN
    POP DE                          ; DE = the AUTO line number
    JR NC,AUTGOD                    ; NC: the line ended normally, not with BREAK
;; Turns AUTO off and returns to READY.
AUTRES:
    XOR A                           ; BREAK ends AUTO numbering
    LD [AUTFLG],A
    JR READY
;; Advances the AUTO line number by its increment, ending AUTO past 65529, then stores the line.
AUTGOD:
    LD HL,[AUTINC]
    ADD HL,DE                       ; HL = the next AUTO line number
    JR C,AUTRES                     ; past 65535: turn AUTO off
    PUSH DE
    LD DE,$FFF9                     ; 65529 is the highest line number AUTO may offer
    RST $18
    POP DE
    JR NC,AUTRES                    ; at or past 65530: turn AUTO off
    LD [AUTLIN],HL                  ; remember the next number AUTO will offer
    OR $FF                          ; NZ tells EDITRT the line had a number
    JP EDITRT
;; Prompts with > and reads a command line, ignoring BREAK and empty lines, then parses its line number.
NTAUTO:
    LD A,$3E                        ; the > prompt of the command level
    CALL OUTDO
    CALL INLIN
    JP C,MAIN                       ; BREAK pressed: discard the line
    RST $10                         ; first character of the line, carry if a digit
    INC A                           ; sets Z without touching carry
    DEC A
    JP Z,MAIN                       ; empty line: prompt again
    PUSH AF                         ; carry kept: the line starts with a line number
    CALL LINGET                     ; DE = the line number, zero when none
;; Backs HL up over the spaces before it, then skips one space after the line number.
BAKSP:
    DEC HL
    LD A,[HL]
    CP $20
    JR Z,BAKSP
    INC HL
    LD A,[HL]
    CP $20
    CALL Z,INXHRT                   ; drop one space between the number and the statement
;; Tokenizes the input line, running it at once when it has no line number, else finding its place.
EDENT:
    PUSH DE
    CALL CRUNCH                     ; BC = the crunched line's length
    POP DE
    POP AF                          ; carry = the line had a line number
    LD [SAVTXT],HL
    CALL HOOK_LINE_ENTERED
    JP NC,GONE                      ; no line number: execute it as a direct command
    PUSH DE                         ; keep the line number
    PUSH BC                         ; keep the crunched length
    XOR A
    LD [BFKLFL],A                   ; clear the BREAK key flag
    RST $10                         ; first byte after the line number
    OR A                            ; Z when only a number was typed, which deletes the line
    PUSH AF
    EX DE,HL
    LD [DOT],HL                     ; the entered line becomes the current line for "."
    EX DE,HL
    CALL FNDLIN                     ; BC = where the line is, or where it belongs

;; Deletes the program line with the same number when one exists.
LEXIST:
    PUSH BC                         ; keep the insertion point
    CALL C,DEL                      ; an old line with this number is removed first

;; Opens room in the program text for the new line and writes its link and line number, unless it is
;; empty.
NODEL:
    POP DE                          ; DE = the insertion point
    POP AF                          ; Z = the line has no statements
    PUSH DE
    JR Z,FINI                       ; bare line number: nothing to insert
    POP DE
    LD HL,[VARTAB]                  ; HL = the end of the program text
    EX [SP],HL                      ; swap with the crunched length on the stack
    POP BC                          ; BC = the old end of the text
    ADD HL,BC                       ; HL = the new end after the line is added
    PUSH HL
    CALL BLTU                       ; shift the following text up to make the gap
    POP HL
    LD [VARTAB],HL                  ; the variables now start after the longer program
    EX DE,HL
    LD [HL],H                       ; a nonzero link so CHEAD does not see the end
    POP DE                          ; DE = the line number
    PUSH HL                         ; the new line's address, for CHEAD in FINI
    INC HL
    INC HL
    LD [HL],E                       ; write the line number after the link
    INC HL
    LD [HL],D
    INC HL
    EX DE,HL
    LD HL,[BUFPNT]                  ; the crunched line starts two bytes before the buffer
    EX DE,HL
    DEC DE
    DEC DE
;; Copies the tokenized line from the buffer into the program text, up to its zero byte.
MLOOPR:
    LD A,[DE]
    LD [HL],A
    INC HL
    INC DE
    OR A                            ; zero byte ends the line
    JR NZ,MLOOPR
;; Relinks the program lines, clears the variables and returns to the command loop.
FINI:
    POP DE                          ; DE = the first line whose link may be wrong
    CALL CHEAD
    CALL HOOK_LINE_INSERTED
    CALL RUNC                       ; the program changed, so variables are cleared
    CALL HOOK_LINE_CLEARED
    JP MAIN

;; Rebuilds the link of every program line, starting at the beginning of the program text.
LINKER:
    LD HL,[TXTTAB]
    EX DE,HL

;; Rebuilds the program's line links starting at the line at DE.
CHEAD:
    LD H,D
    LD L,E
    LD A,[HL]                       ; a zero link marks the end of the program
    INC HL
    OR [HL]
    RET Z
    INC HL                          ; skip the link and line number to the statement text
    INC HL
    INC HL
    XOR A                           ; A = 0, the end-of-line byte to look for

;; Finds the end of the current line and stores the next line's address in its link.
CZLOOP:
    CP [HL]
    INC HL
    JR NZ,CZLOOP
    EX DE,HL                        ; HL = the line's link field, DE = the next line
    LD [HL],E
    INC HL
    LD [HL],D
    JR CHEAD

;; Parses a line range (n, n-, -m, n-m) for LIST or DELETE and finds its first line.
SCNLIN:
    LD DE,RESET                     ; RESET is the return address when no range is given
    PUSH DE
    JR Z,ALLLST                     ; no arguments: list or delete every line
    POP DE                          ; not needed with a range
    CALL LINSPC                     ; DE = the first line number, zero when missing
    PUSH DE                         ; keep the range start
    JR Z,SNGLIN                     ; a single line number: the range is that one line
    RST $08                         ; a dash must separate the two line numbers
    .byte TK_MINUS

;; Takes 65530 as the end of a line range unless a line number follows, with a ?SN error for anything
;; else.
ALLLST:
    LD DE,$FFFA                     ; 65530 stands in for "through the last line"
    CALL NZ,LINSPC                  ; a number after the dash ends the range there
    JP NZ,SNERR                     ; anything else after the range is a syntax error

;; Moves the range end to HL and the start to DE, then finds the first line (<FNDLN1>).
SNGLIN:
    EX DE,HL                        ; HL = the last line number of the range
    POP DE                          ; DE = the first line number

;; Leaves HL on the stack under the return address, then finds line DE (FNDLIN).
FNDLN1:
    EX [SP],HL
    PUSH HL

;; Finds the line whose number is in DE: carry and BC at it when found, else BC at the next line.
FNDLIN:
    LD HL,[TXTTAB]

;; Finds line DE searching from the line at HL; carry and BC at it when found.
LOOP:
    LD B,H                          ; BC = the line being examined
    LD C,L
    LD A,[HL]
    INC HL
    OR [HL]                         ; Z when the link is zero, the end of the program
    DEC HL
    RET Z                           ; not found: carry clear, BC at the program end
    INC HL
    INC HL
    LD A,[HL]                       ; HL = this line's number
    INC HL
    LD H,[HL]
    LD L,A
    RST $18                         ; compare it with the wanted number
    LD H,B                          ; back to the start of the line
    LD L,C
    LD A,[HL]                       ; HL = the next line's address
    INC HL
    LD H,[HL]
    LD L,A
    CCF
    RET Z                           ; equal: carry set, the line is found
    CCF
    RET NC                          ; past the wanted number: BC is where it would go
    JR LOOP
;; Executes NEW: clears the screen, erases the program and clears all variables.
ST_NEW:
    RET NZ                          ; NEW takes no argument
    CALL CLS

;; Erases the program (NEW): turns off trace, empties the text and clears variables.
ERASE_PROGRAM:
    LD HL,[TXTTAB]
    CALL ST_TROFF                   ; also leaves A = 0
    LD [AUTFLG],A                   ; AUTO off
    LD [HL],A                       ; a zero link: the program is empty
    INC HL
    LD [HL],A
    INC HL
    LD [VARTAB],HL                  ; variables start right after the empty program

;; Clears variables, strings and the DATA pointer to run from the program's start.
RUNC:
    LD HL,[TXTTAB]
    DEC HL                          ; the text pointer sits just before the first line

;; Clears the variables, arrays, strings and ON ERROR state, makes every letter single precision,
;; and resets the DATA pointer and the stack.
CLEARC:
    LD [TEMP],HL                    ; the text pointer to hand back to the caller
    LD B,$1A                        ; one type entry per letter A to Z
    LD HL,DEFTBL
;; Enters CLEARC's loop that sets each letter's default type to single precision.
LOPDFT:
    LD [HL],$04                     ; 4 = single precision
    INC HL
    DJNZ LOPDFT
    XOR A
    LD [ONEFLG],A                   ; not inside an error trap
    LD L,A
    LD H,A
    LD [ONELIN],HL                  ; no ON ERROR GOTO line
    LD [OLDTXT],HL                  ; no line to CONTinue from
    LD HL,[MEMSIZ]
    LD [FRETOP],HL                  ; the string space is empty
    CALL ST_RESTORE                 ; READ starts again at the first DATA
    LD HL,[VARTAB]
    LD [ARYTAB],HL                  ; no simple variables
    LD [STREND],HL                  ; no arrays
    CALL HOOK_CLEAR

;; Resets the stack and string temporaries, keeping the caller's return address.
STKINI:
    POP BC                          ; BC = the caller's return address
    LD HL,[STKTOP]
    DEC HL
    DEC HL
    LD [SAVSTK],HL                  ; the stack top used to recover from errors
    INC HL
    INC HL

;; Sets SP to HL, resets the string temporaries and the output device, and rebuilds the stack base.
;; Out:   HL = the pointer saved in TEMP
STKERR:
    LD SP,HL
    LD HL,$40B5                     ; the start of the string temporaries
    LD [TEMPPT],HL
    CALL FINLPT                     ; finish any line left on the printer
    CALL FINPRT                     ; send output to the video display again
    XOR A
    LD H,A                          ; a zero word marks the base of the stack
    LD L,A

;; Stores A in SUBFLG and pushes HL and the return address in BC onto the new stack, then exits.
WASDIR:
    LD [SUBFLG],A                   ; not inside a subscripted variable reference
    PUSH HL
    PUSH BC                         ; return to the caller on the new stack

;; Loads HL from TEMP and returns: the exit of the stack reset.
GTMPRT:
    LD HL,[TEMP]
    RET

;; Prints a question mark and a space, then reads a line from the keyboard through <INLIN>.
QINLIN:
    LD A,$3F                        ; the ? of an INPUT prompt
    CALL OUTDO
    LD A,$20
    CALL OUTDO
    JP INLIN

;; Crunches the line at HL into tokens in the input buffer.
CRUNCH:
    XOR A
    LD [DORES],A                    ; not inside a DATA or REM yet
    LD C,A                          ; C counts the bytes of the crunched line
    EX DE,HL
    LD HL,[BUFPNT]                  ; crunched output overwrites the buffer in place
    DEC HL
    DEC HL
    EX DE,HL

;; Takes the next character of the line being crunched and stores it, a string or a keyword token.
;; Characters in DATA statements, digits and some punctuation are copied unchanged.
KLOOP:
    LD A,[HL]
    CP $20
    JP Z,STUFFH                     ; spaces are kept as typed
    LD B,A                          ; B = the character, kept for later checks
    CP $22
    JP Z,KRUNCH_15                  ; a quote copies the string unchanged
    OR A
    JP Z,CRDONE                     ; zero byte: the end of the typed line
    LD A,[DORES]
    OR A
    LD A,[HL]
    JP NZ,STUFFH                    ; inside DATA or REM: copy the text unchanged
    CP $3F                          ; ? is shorthand for PRINT
    LD A,$B2                        ; the PRINT token
    JP Z,STUFFH
    LD A,[HL]
    CP $30                          ; below 0: may start a keyword
    JR C,MUSTCR
    CP $3C                          ; digits, colon and semicolon are copied as is
    JP C,STUFFH

;; Starts the reserved word search for the text at HL, folding a lowercase letter to uppercase.
MUSTCR:
    PUSH DE                         ; save the output pointer
    LD DE,$164F                     ; just before the reserved word list
    PUSH BC
    LD BC,$1C3D                     ; NOTRES is the return address for the search
    PUSH BC
    LD B,$7F                        ; token counter, the first word becomes $80
    LD A,[HL]
    CP $61                          ; below a: no case folding needed
    JR C,TRYAGA
    CP $7B                          ; above z: not a letter
    JR NC,TRYAGA
    AND $5F                         ; make the letter uppercase in the line itself
    LD [HL],A

;; Retries the reserved word search at the same text position against the next word in the list.
TRYAGA:
    LD C,[HL]                       ; C = the character to match
    EX DE,HL                        ; HL walks the word list, DE the line

;; Skips to the next word in the reserved word list, counting tokens in B; returns at the list's end.
LOPSKP:
    INC HL
    OR [HL]
    JP P,LOPSKP                     ; a byte with bit 7 set begins the next word
    INC B                           ; B = that word's token
    LD A,[HL]
    AND $7F                         ; strip the flag to get the word's first letter
    RET Z                           ; $80 alone ends the list: not a keyword
    CP C                            ; first letter differs: try the next word
    JR NZ,LOPSKP
    EX DE,HL
    PUSH HL                         ; keep the text position to retry from

;; Compares the rest of a reserved word with the text, letting GOTO match with spaces after GO.
LOPPSI:
    INC DE
    LD A,[DE]                       ; bit 7 set: the next word, so all letters matched
    OR A
    JP M,FOUND
    LD C,A                          ; C = the letter the word expects next
    LD A,B
    CP $8D                          ; the GOTO token
    JR NZ,NTGOTO
    RST $10                         ; allows spaces between GO and TO
    DEC HL                          ; NTGOTO steps forward again

;; Advances to the next text character, uppercases it, and continues the reserved word comparison.
NTGOTO:
    INC HL
    LD A,[HL]
    CP $61                          ; only lowercase letters are folded
    JR C,NOTLW1
    AND $5F

;; Continues the reserved word match if A equals C, else restores the text pointer and tries the next word.
NOTLW1:
    CP C
    JR Z,LOPPSI                     ; letter matches: compare the next one
    POP HL                          ; mismatch: back to the start of the text
    JR TRYAGA

;; Ends the reserved word search with a match: the token number in C, the text after the word in DE.
FOUND:
    LD C,B                          ; C = the token found
    POP AF                          ; drop the saved text position
    EX DE,HL
    RET

;; Handles the result of the reserved word search, putting a colon before ELSE in the crunched line.
NOTRES:
    EX DE,HL
    LD A,C                          ; A = the token, or the character when none matched
    POP BC                          ; restore the character and the byte count
    POP DE                          ; DE = the output pointer
    EX DE,HL                        ; HL = the output pointer, DE = the text
    CP $95                          ; the ELSE token
    LD [HL],$3A                     ; ELSE always gets a colon in front of it
    JR NZ,CKSNGQ
    INC C                           ; count the colon
    INC HL                          ; keep the colon before ELSE

;; Replaces an apostrophe remark with a colon and REM token, then copies the rest of the line unchanged.
CKSNGQ:
    CP $FB                          ; the token for an apostrophe remark
    JR NZ,NTSNGT
    LD [HL],$3A                     ; split it off from the statement before it
    INC HL
    LD B,$93                        ; the REM token
    LD [HL],B
    INC HL
    EX DE,HL
    INC C                           ; the colon and REM token add two bytes
    INC C
    JR KRUNCH_15                    ; copy the rest of the line as remark text

;; Stores a byte in the crunched line and tracks colons and DATA; after REM copies the rest of the line.
NTSNGT:
    EX DE,HL

STUFFH:
    INC HL
    LD [DE],A
    INC DE
    INC C
    SUB $3A                         ; a colon ends any DATA statement
    JR Z,COLIS
    CP $4E                          ; $3A + $4E is the DATA token
    JR NZ,NODATT

COLIS:
    LD [DORES],A                    ; nonzero while inside DATA, zero after a colon

NODATT:
    SUB $59                         ; $3A + $59 is the REM token
    JP NZ,KLOOP                     ; anything else: crunch the next character
    LD B,A                          ; B = 0, so only the end of the line stops the copy

STR1:
    LD A,[HL]
    OR A
    JR Z,CRDONE                     ; the line ended inside a string or remark
    CP B                            ; the closing quote ends the literal copy
    JR Z,STUFFH

KRUNCH_15:
    INC HL
    LD [DE],A
    INC C
    INC DE
    JR STR1

;; Ends a crunched line with three zero bytes and returns its length plus 5 in BC.
CRDONE:
    LD HL,$0005                     ; the line length grows by five bytes
    LD B,H                          ; B = 0, so BC is the byte count in C
    ADD HL,BC
    LD B,H
    LD C,L
    LD HL,[BUFPNT]                  ; HL = just before the crunched line, for execution
    DEC HL
    DEC HL
    DEC HL
    LD [DE],A                       ; end of line plus a zero link for direct mode
    INC DE
    LD [DE],A
    INC DE
    LD [DE],A
    RET

;; The routine behind RST $18.
DCOMPR:
    LD A,H
    SUB D                           ; compare the high bytes first
    RET NZ                          ; differ: Z clear, carry if HL is below DE
    LD A,L
    SUB E                           ; equal high bytes: decided by the low bytes
    RET

;; The routine behind RST $08.
SYNCHK:
    LD A,[HL]
    EX [SP],HL                      ; HL = the expected character after the RST
    CP [HL]
    INC HL                          ; skip it in the return address
    EX [SP],HL
    JP Z,CHRGTR                     ; matched: fetch the next character
    JP SNERR
;; Runs FOR: assigns the start value, drops any loop on the same variable and pushes a FOR entry.
;; Integer loops are handled here; strings give a TM error.
ST_FOR:
    LD A,$64                        ; marks a FOR, so the variable cannot be an array
    LD [SUBFLG],A
    CALL ST_LET                     ; assign the start value to the loop variable
    EX [SP],HL                      ; HL = the loop variable's address
    CALL FNDFOR                     ; look for a FOR already using this variable
    POP DE                          ; DE = the text pointer
    JR NZ,NOTOL                     ; none: build a new entry
    ADD HL,BC                       ; drop the old loop and everything above it
    LD SP,HL
    LD [SAVSTK],HL
NOTOL:
    EX DE,HL
    LD C,$08                        ; room for 16 bytes of FOR entry
    CALL GETSTK
    PUSH HL                         ; keep the text pointer
    CALL ST_DATA                    ; HL = the end of the FOR statement
    EX [SP],HL                      ; stack the end of the statement, back to the text
    PUSH HL
    LD HL,[CURLIN]
    EX [SP],HL                      ; stack the line number of the FOR
    RST $08                         ; TO must follow the start value
    .byte TK_TO
    RST $20                         ; the loop variable's type
    JP Z,TMERR                      ; string loop variables are not allowed
    JP NC,TMERR                     ; double precision loop variables are not allowed
    PUSH AF                         ; keep the loop variable's type
    CALL FRMEVL                     ; evaluate the TO limit
    POP AF
    PUSH HL                         ; keep the text pointer
    JP P,SNGFOR                     ; not an integer loop: use single precision
    CALL FRCINT                     ; an integer loop keeps an integer limit
    EX [SP],HL                      ; stack the limit, HL = text
    LD DE,$0001                     ; the default STEP of 1
    LD A,[HL]
    CP $CC                          ; the STEP token
    CALL Z,GETINT                   ; DE = the integer step
    PUSH DE                         ; keep the step
    PUSH HL
    EX DE,HL
    CALL ISIGN                      ; A = the sign of the step
    JR STPSGN
;; Builds the single-precision FOR entry from the limit and optional STEP, then starts the next statement.
SNGFOR:
    CALL FRCSNG
    CALL MOVRF                      ; BCDE = the limit
    POP HL                          ; HL = text pointer
    PUSH BC                         ; stack the limit
    PUSH DE
    LD BC,$8100                     ; BCDE = 1.0, the default step
    LD D,C
    LD E,D
    LD A,[HL]
    CP $CC                          ; the STEP token
    LD A,$01                        ; a positive step when STEP is missing
    JR NZ,ONEON
    CALL FRMCHK                     ; evaluate the step value
    PUSH HL
    CALL FRCSNG
    CALL MOVRF                      ; BCDE = the step
    CALL SIGN                       ; A = the sign of the step
STPSGN:
    POP HL                          ; HL = text pointer
ONEON:
    PUSH BC                         ; stack the step
    PUSH DE
    LD C,A                          ; C = the sign of the step
    RST $20                         ; B = the loop's type
    LD B,A
    PUSH BC                         ; stack the type and sign
    PUSH HL
    LD HL,[TEMP]                    ; the loop variable's address, saved by LET
    EX [SP],HL                      ; stack it, HL = text pointer
NXTCON:
    LD B,$81                        ; the FOR token tags the entry
    PUSH BC
    INC SP                          ; only the one byte with the token stays pushed
;; Runs the next statement: checks for BREAK, moves to the next line at its end and traces with TRON.
;; Ends the program when it runs off the last line.
NEWSTT:
    CALL ISCHAR                     ; check for a key
    OR A
    CALL NZ,CNTCCN                  ; handle BREAK or the pause key
    LD [SAVTXT],HL                  ; the current position, for CONT and errors
    LD [SAVSTK],SP                  ; the stack to recover after an error
    LD A,[HL]
    CP $3A                          ; a colon: another statement on this line
    JR Z,GONE
    OR A
    JP NZ,SNERR                     ; anything but the end of line is a syntax error
    INC HL                          ; step past the zero ending the line
GONE4:
    LD A,[HL]
    INC HL
    OR [HL]
    JP Z,PRGEND                     ; a zero link: the program has run out
    INC HL
    LD E,[HL]                       ; DE = the new line's number
    INC HL
    LD D,[HL]
    EX DE,HL
    LD [CURLIN],HL                  ; the line being executed
    LD A,[TRCFLG]                   ; is TRON on?
    OR A
    JR Z,NOTTRC
    PUSH DE                         ; keep the text pointer
    LD A,$3C                        ; the line number is shown between < and >
    CALL OUTDO
    CALL LINPRT
    LD A,$3E
    CALL OUTDO
    POP DE                          ; DE = text pointer
;; Restores the text pointer after the TRON line number and executes the statement.
NOTTRC:
    EX DE,HL
;; Gets the first character of a statement and executes it, returning to <NEWSTT> afterwards.
GONE:
    RST $10                         ; A = the statement's first character
    LD DE,$1D1E                     ; NEWSTT is the return address of every statement
    PUSH DE
;; Executes the statement starting with the character in A, or returns if it ends the statement.
GONE3:
    RET Z                           ; an empty statement does nothing
;; Dispatches the statement token in A through STMDSP; other characters start an implied LET.
;; Tokens past the statement range go to <ISMID> for MID$ assignment.
GONE2:
    SUB $80
    JP C,ST_LET                     ; not a keyword: an assignment without LET
    CP $3C                          ; tokens past the statements: maybe MID$ assignment
    JP NC,ISMID
    RLCA                            ; two bytes per entry in the dispatch table
    LD C,A
    LD B,$00
    EX DE,HL
    LD HL,STMDSP
    ADD HL,BC
    LD C,[HL]
    INC HL
    LD B,[HL]
    PUSH BC                         ; the statement routine becomes the return address
    EX DE,HL                        ; HL = text pointer, falls into the fetch

;; The routine behind RST $10.
CHRGTR:
    INC HL                          ; step to the next character

CHRGT2:
    LD A,[HL]
    CP $3A
    RET NC                          ; not a digit or a space: return NC and NZ

;; Skips spaces, tabs and line feeds, then sets carry for a digit and Z for a zero byte.
;; Finishes the RST $10 character fetch.
CHRCON:
    CP $20
    JP Z,CHRGTR                     ; spaces are skipped
    CP $0B                          ; above line feed: a normal character
    JR NC,NOTLFT
    CP $09                          ; tab and line feed are skipped too
    JP NC,CHRGTR
NOTLFT:
    CP $30
    CCF                             ; carry for a digit
    INC A
    DEC A                           ; Z for the zero byte at the end of a line
    RET
;; Runs RESTORE: points the DATA pointer at the start of the program so READ starts over.
ST_RESTORE:
    EX DE,HL                        ; keep the text pointer
    LD HL,[TXTTAB]
    DEC HL                          ; just before the first line, as READ expects
RESFIN:
    LD [DATPTR],HL
    EX DE,HL
    RET

;; Scans the keyboard and handles BREAK or the shift-@ pause if a key is down.
ISCNTC:
    CALL ISCHAR
    OR A
    RET Z                           ; no key down

;; Pauses on shift-@ for a key, saves the key at $4099, and stops on BREAK.
CNTCCN:
    CP $60                          ; shift-@ pauses until another key is pressed
    CALL Z,INCHR
    LD [CHARC],A                    ; keep the key for INKEY$
    DEC A                           ; Z for BREAK, whose code is 1
;; Runs STOP: stops the program with the Break message, ready for CONT.
ST_STOP:
    RET NZ                          ; anything else: carry on
    INC A                           ; A nonzero, so the Break message is printed
    JP CONSTP
;; Runs END: lets a disk system close its files and stops the program without a message.
ST_END:
    RET NZ                          ; text after END: leave it to the syntax check
    PUSH AF
    CALL Z,HOOK_CLEAR               ; a disk system closes its files here
    POP AF
;; Saves the text pointer for CONT and resets the string temporaries, then stops the program.
CONSTP:
    LD [SAVTXT],HL                  ; where CONT will resume
    LD HL,$40B5                     ; discard the string temporaries
    LD [TEMPPT],HL
    .byte $21
;; Stops the program with the Break message, discarding the return address to <NEWSTT>.
STPEND:
    OR $FF                          ; nonzero: print the Break message
    POP BC                          ; discard the return address to NEWSTT
;; Stops the program, remembering the line and statement for CONT unless in direct mode.
ENDCON:
    LD HL,[CURLIN]
    PUSH HL
    PUSH AF                         ; keep the message flag
    LD A,L
    AND H
    INC A                           ; line number 65535 means direct mode
    JR Z,DIRIS                      ; a direct command cannot be continued
    LD [OLDLIN],HL                  ; the line for CONT to resume in
    LD HL,[SAVTXT]
    LD [OLDTXT],HL                  ; the position for CONT to resume at
;; Ends a stop by printing Break in the stopped line if A is not zero, else returning to Ready.
DIRIS:
    CALL FINLPT                     ; finish any line left on the printer
    CALL CRDONZ                     ; start a fresh line on the screen
    POP AF
    LD HL,BREAK_MSG                 ; the Break message for ERRFIN
    JP NZ,ERRFIN                    ; nonzero: Break in the stopped line
    JP STPRDY                       ; END: straight to Ready
;; Runs CONT: resumes the program at the statement where it stopped, or gives a CN error.
ST_CONT:
    LD HL,[OLDTXT]
    LD A,H
    OR L                            ; zero: nothing to continue
RESERR:
    LD E,ERR_CN                     ; the Can't Continue error
    JP Z,ERROR
    EX DE,HL                        ; keep the resume position
    LD HL,[OLDLIN]
    LD [CURLIN],HL                  ; back in the line that stopped
    EX DE,HL                        ; HL = where to resume, then on to NEWSTT
    RET
;; Runs TRON: turns on the trace of line numbers.
ST_TRON:
    .byte $3E                       ; LD A,n: skips the next instruction
;; Runs TROFF: turns off the trace of line numbers.
ST_TROFF:
    XOR A                           ; zero turns tracing off, nonzero turns it on
    LD [TRCFLG],A
    RET

;; Discards the word on top of the stack, restores HL from the next one and returns.
POPAHT:
    POP AF
    POP HL
    RET
;; Runs DEFSTR: makes variables starting with the given letters strings by default.
ST_DEFSTR:
    LD E,$03                        ; 3 = string
    .byte $01                       ; LD BC,nn: skips the next instruction
;; Runs DEFINT: makes variables starting with the given letters integers by default.
ST_DEFINT:
    LD E,$02                        ; 2 = integer
    .byte $01                       ; LD BC,nn: skips the next instruction
;; Runs DEFSNG: makes variables starting with the given letters single precision by default.
ST_DEFSNG:
    LD E,$04                        ; 4 = single precision
    .byte $01                       ; LD BC,nn: skips the next instruction
;; Runs DEFDBL: makes variables starting with the given letters double precision by default.
ST_DEFDBL:
    LD E,$08                        ; 8 = double precision
;; Sets the default type of each letter or letter range in the list to the type code in E.
;; In:    E = the type code (2 integer, 3 string, 4 single, 8 double)
DEFCON:
    CALL ISLET                      ; carry when not a letter
    LD BC,$1997                     ; SNERR, the return address for an error
    PUSH BC
    RET C                           ; a letter must start the range
    SUB $41                         ; C = the first letter as an index from A
    LD C,A
    LD B,A                          ; B = the last letter, the same for a single letter
    RST $10
    CP $CE                          ; a minus sign makes a range of letters
    JR NZ,NOTRNG
    RST $10
    CALL ISLET                      ; a letter must end the range
    RET C
    SUB $41                         ; B = the last letter as an index
    LD B,A
    RST $10
;; Stores the type code in E for the letters from C to B in the default type table.
NOTRNG:
    LD A,B
    SUB C
    RET C                           ; a backward range is a syntax error
    INC A                           ; A = how many letters to set
    EX [SP],HL                      ; drop the error address, keep the text pointer
    LD HL,DEFTBL
    LD B,$00                        ; BC = the first letter's index
    ADD HL,BC
;; Stores E in A entries of the default type table, then moves on to the next letter range after a comma.
LPDCHG:
    LD [HL],E
    INC HL
    DEC A
    JR NZ,LPDCHG
    POP HL                          ; HL = text pointer
    LD A,[HL]
    CP $2C                          ; a comma brings another letter range
    RET NZ
    RST $10
    JR DEFCON                       ; set the next range of letters

;; Tests whether the character at HL is an uppercase letter.
;; Out:   A = the character, carry = clear for A-Z
ISLET:
    LD A,[HL]

;; Tests whether A is an uppercase letter, clearing carry for A-Z.
ISLET2:
    CP $41
    RET C                           ; below A: carry set, not a letter
    CP $5B
    CCF                             ; carry set above Z, clear for a letter
    RET

;; Gets the next character and evaluates a non-negative integer into DE, else FC error.
INTIDX:
    RST $10

;; Evaluates a non-negative integer expression into DE, else FC error.
INTID2:
    CALL GETIN2
    RET P                           ; positive or zero is accepted
;; Reports an FC (illegal function call) error.
FCERR:
    LD E,ERR_FC
    JP ERROR

;; Reads a line number at HL into DE, accepting a period for the current line.
LINSPC:
    LD A,[HL]
    CP $2E                          ; a period means the current line
    EX DE,HL
    LD HL,[DOT]                     ; DE = the line last entered, listed or in error
    EX DE,HL
    JP Z,CHRGTR                     ; skip the period, DE holds the line

;; Reads a line number at HL into DE.
LINGET:
    DEC HL

;; Reads a line number starting at the character after HL into DE (SN error if too big).
LINGT2:
    LD DE,RESET                     ; DE = 0, the number built so far

MORLIN:
    RST $10
    RET NC                          ; not a digit: the number is complete
    PUSH HL                         ; keep the text pointer
    PUSH AF                         ; keep the digit
    LD HL,$1998                     ; 6552: one more digit would pass 65529
    RST $18
    JP C,SNERR                      ; the line number is too large
    LD H,D
    LD L,E
    ADD HL,DE                       ; HL = number times 2
    ADD HL,HL                       ; HL = number times 4
    ADD HL,DE                       ; HL = number times 5
    ADD HL,HL                       ; HL = number times 10
    POP AF
    SUB $30                         ; the digit's value
    LD E,A
    LD D,$00
    ADD HL,DE                       ; add the digit
    EX DE,HL                        ; DE = the new number
    POP HL
    JR MORLIN
;; Runs CLEAR: clears the variables, setting the size of the string space first if one is given.
ST_CLEAR:
    JP Z,CLEARC                     ; no argument: clear the variables only
    CALL INTID2                     ; DE = the new string space size
    DEC HL
    RST $10
    RET NZ                          ; more after the size: syntax error
    PUSH HL                         ; keep the text pointer
    LD HL,[MEMSIZ]                  ; HL = the top of memory for BASIC
    LD A,L
    SUB E
    LD E,A                          ; DE = the top minus the string space
    LD A,H
    SBC A,D
    LD D,A
    JP C,OMERR                      ; more string space than memory
    LD HL,[VARTAB]                  ; the end of the program text
    LD BC,RST_DOS                   ; room for 40 bytes of stack
    ADD HL,BC
    RST $18
    JP NC,OMERR                     ; no room for the program, stack and strings
    EX DE,HL
    LD [STKTOP],HL                  ; the stack now ends where the strings begin
    POP HL
    JP CLEARC
;; Runs RUN: starts the program from the beginning, or clears the variables and goes to a line number.
ST_RUN:
    JP Z,RUNC                       ; no line number: run from the start
    CALL HOOK_RUN                   ; a disk system handles RUN with a file name
    CALL CLEARC
    LD BC,$1D1E                     ; NEWSTT, the return address for the GOTO
    JR RUNC2
;; Runs GOSUB: pushes a return entry with the text pointer and line number, then goes to the line.
ST_GOSUB:
    LD C,$03                        ; a GOSUB entry needs 6 bytes
    CALL GETSTK
    POP BC                          ; BC = the NEWSTT return address
    PUSH HL                         ; the text pointer, to continue after RETURN
    PUSH HL                         ; a slot for the line number
    LD HL,[CURLIN]
    EX [SP],HL                      ; stack the line of the GOSUB
    LD A,$91                        ; the GOSUB token tags the entry
    PUSH AF
    INC SP                          ; only the token byte stays pushed
;; Pushes the return address in BC and goes to the line number in the program text.
RUNC2:
    PUSH BC                         ; put the return address back on top
;; Runs GOTO: reads a line number and continues the program at that line.
ST_GOTO:
    CALL LINGET
;; Goes to the line numbered DE, searching from the current line when it lies ahead.
;; In:    DE = the line number
GOTO2:
    CALL ST_REM                     ; HL = the end of the current line
    PUSH HL
    LD HL,[CURLIN]                  ; is the target after the current line?
    RST $18
    POP HL
    INC HL                          ; HL = the next line
    CALL C,LOOP                     ; ahead: search from the next line
    CALL NC,FNDLIN                  ; behind: search from the start of the program
    LD H,B
    LD L,C
    DEC HL                          ; just before the line, as NEWSTT expects
    RET C                           ; found: continue there
;; Reports a UL (undefined line number) error.
USERR:
    LD E,ERR_UL
    JP ERROR
;; Runs RETURN: pops the stack to the latest GOSUB entry and continues after that GOSUB.
;; Gives an RG error if there is none.
ST_RETURN:
    RET NZ                          ; RETURN takes no argument
    LD D,$FF                        ; matches no loop, so FOR entries are discarded
    CALL FNDFOR
    LD SP,HL                        ; drop everything above the found entry
    LD [SAVSTK],HL
    CP $91                          ; is it a GOSUB entry?
RGERR:
    LD E,ERR_RG
    JP NZ,ERROR                     ; no GOSUB is active
    POP HL                          ; HL = the line the GOSUB was in
    LD [CURLIN],HL
    INC HL
    LD A,H                          ; line 65535: the GOSUB was a direct command
    OR L
    JR NZ,GOBACK
    LD A,[BFKLFL]
    OR A
    JP NZ,STPRDY
;; Continues after a GOSUB by skipping the rest of its statement, returning to <NEWSTT>.
GOBACK:
    LD HL,$1D1E                     ; NEWSTT, the return address
    EX [SP],HL                      ; HL = the text after the GOSUB's line number
    .byte $3E
;; Pops the text pointer into HL and skips to the end of the statement.
DATAH:
    POP HL
;; Runs DATA: skips to the end of the statement, passing over quoted strings.
ST_DATA:
    .byte $01                       ; LD BC,nn: skips the next instruction
    .byte $3A
;; Runs REM: skips to the end of the line, passing over quoted strings.
ST_REM:
    .byte $0E                       ; LD C,n: skips the next instruction
    NOP                             ; C = 0 for REM, which stops only at the line end
    LD B,$00                        ; B = 0, the other terminator
EXCHQT:
    LD A,C                          ; swap terminators when a quote is crossed
    LD C,B
    LD B,A
REMER:
    LD A,[HL]
    OR A
    RET Z                           ; the end of the line
    CP B
    RET Z                           ; the terminator, unless inside a string
    INC HL
    CP $22                          ; a quote toggles the colon test on and off
    JR Z,EXCHQT
    SUB $8F                         ; the IF token
    JR NZ,REMER                     ; anything else is skipped
    CP B
    ADC A,D                         ; D counts the IFs passed, for ELSE matching
    LD D,A
    JR REMER
;; Runs LET: evaluates the expression after the equals sign and assigns it to the variable.
;; In:    HL = the variable name in the program text
ST_LET:
    CALL PTRGET                     ; DE = the variable's address
    RST $08                         ; an equals sign must follow the variable
    .byte TK_EQUAL
    EX DE,HL
    LD [TEMP],HL                    ; FOR finds the loop variable here
    EX DE,HL

REDINP:
    PUSH DE                         ; keep the variable's address
    RST $20                         ; the variable's type
    PUSH AF                         ; keep it for the conversion

LETCN3:
    CALL FRMEVL                     ; evaluate the value to assign

LETCON:
    POP AF

LETCN2:
    EX [SP],HL                      ; HL = the variable, stack the text pointer
INPCOM:
    ADD A,$03                       ; A = the variable's type code
    CALL DOCNVF                     ; convert the value to the variable's type
    CALL VDFACS                     ; DE = where the value is, Z for a string
    PUSH HL                         ; keep the variable's address
    JR NZ,COPNUM                    ; numbers are copied straight into the variable
    LD HL,[FACLO]                   ; HL = the string's descriptor
    PUSH HL
    INC HL
    LD E,[HL]                       ; DE = the string's text
    INC HL
    LD D,[HL]
    LD HL,[TXTTAB]
    RST $18                         ; below the program text: in the input buffer
    JR NC,INBUFC                    ; buffer text must be copied into string space
    LD HL,[STKTOP]
    RST $18                         ; below the string space: a literal in the program
    POP DE                          ; DE = the descriptor
    JR NC,DNTCPY                    ; literals are pointed at, not copied
    LD HL,[VARTAB]
    RST $18                         ; is the descriptor a temporary or a variable's?
    JR NC,DNTCPY                    ; a temporary: use its string space as is
    .byte $3E

INBUFC:
    POP DE                          ; DE = the descriptor
    CALL FRETMS                     ; release the temporary descriptor
    EX DE,HL
    CALL STRCPY                     ; make a new copy in string space
DNTCPY:
    CALL FRETMS                     ; release the temporary descriptor
    EX [SP],HL                      ; HL = the variable, stack the descriptor
COPNUM:
    CALL VMOVE                      ; store the value or descriptor in the variable
    POP DE                          ; drop the variable's address
    POP HL                          ; HL = text pointer
    RET
;; Runs ON: sets the error trap line for ON ERROR GOTO, or dispatches ON n GOTO and ON n GOSUB.
ST_ON:
    CP $9E                          ; the ERROR token of ON ERROR GOTO
    JR NZ,NTOERR
    RST $10
    RST $08                         ; GOTO must follow ON ERROR
    .byte TK_GOTO
    CALL LINGET                     ; DE = the trap line
    LD A,D
    OR E
    JR Z,RESTRP                     ; line 0 turns the trap off
    CALL FNDLN1                     ; BC = the trap line, carry when it exists
    LD D,B                          ; DE = the line's address
    LD E,C
    POP HL                          ; HL = text pointer
    JP NC,USERR                     ; the trap line does not exist
;; Stores the error trap line; turning the trap off inside a trap reports the pending error.
RESTRP:
    EX DE,HL
    LD [ONELIN],HL                  ; store the trap line's address, zero for none
    EX DE,HL
    RET C                           ; a trap set: done
    LD A,[ONEFLG]                   ; inside a trap routine?
    OR A
    RET Z                           ; no: just turned off
    LD A,[ERRFLG]                   ; the error being trapped is reported now
    LD E,A
    JP ERRESM
;; Runs ON n GOTO or ON n GOSUB: picks the nth line number, or continues if there is none.
NTOERR:
    CALL GETBYT                     ; E = the index n
    LD A,[HL]
    LD B,A                          ; B = the GOTO or GOSUB token
    CP $91                          ; the GOSUB token
    JR Z,ISGOSU
    RST $08                         ; otherwise it must be GOTO
    .byte TK_GOTO
    DEC HL                          ; LINGT2 starts at the next character
ISGOSU:
    LD C,E                          ; C counts down the line numbers
LOOPON:
    DEC C
    LD A,B                          ; the nth one: run the GOTO or GOSUB from here
    JP Z,GONE2                      ; the statement reads its line number at HL
    CALL LINGT2                     ; skip a line number
    CP $2C
    RET NZ                          ; no more line numbers: carry on after ON
    JR LOOPON
;; Runs RESUME: leaves an error trap, continuing at the failing statement, the next one or a line.
;; Gives an RW error outside a trap.
ST_RESUME:
    LD DE,ONEFLG
    LD A,[DE]
    OR A
    JP Z,REERR                      ; RESUME outside a trap routine
    INC A                           ; A = 0, the trap routine ends
    LD [ERRFLG],A
    LD [DE],A
    LD A,[HL]
    CP $87                          ; the NEXT token, for RESUME NEXT
    JR Z,RESNXT
    CALL LINGET                     ; DE = the line number, zero when none
    RET NZ                          ; anything else after RESUME: syntax error
    LD A,D
    OR E
    JP NZ,GOTO2                     ; RESUME n continues at line n
    INC A                           ; NZ: retry the statement that failed
    JR RESTXT
;; Runs RESUME NEXT: continues after the statement that caused the error.
RESNXT:
    RST $10
    RET NZ                          ; text after RESUME NEXT: syntax error
;; Restores the line and text pointer of the error, then retries or skips the failing statement.
RESTXT:
    LD HL,[ERRTXT]
    EX DE,HL                        ; DE = the text where the error occurred
    LD HL,[ERRLIN]                  ; HL = the line of the error
    LD [CURLIN],HL
    EX DE,HL                        ; HL = the text of the failing statement
    RET NZ                          ; retry: execute it again
    LD A,[HL]
    OR A                            ; at the end of a line?
    JR NZ,NOTBGL
    INC HL                          ; skip the link and line number of the next line
    INC HL
    INC HL
    INC HL
;; Skips the failing statement to resume after it, stopping if the error happened in a direct command.
NOTBGL:
    INC HL
    LD A,D
    AND E
    INC A                           ; not line 65535: a program line
    JP NZ,ST_DATA                   ; skip the rest of the failing statement
    LD A,[BFKLFL]                   ; in direct mode, maybe stop instead
    DEC A
    JP Z,STPEND
    JP ST_DATA
;; Runs ERROR: simulates the error with the given code, using the UE error for unknown codes.
ST_ERROR:
    CALL GETBYT
    RET NZ                          ; more after the code: syntax error
    OR A
    JP Z,FCERR                      ; code 0 is an FC error
    DEC A
    ADD A,A                         ; error codes are stored as offsets, two apart
    LD E,A
    CP $2D                          ; codes above 23 have no message
    JR C,GOERR
    LD E,ERR_UE                     ; the Unprintable Error code
;; Reports the error whose code is in E.
GOERR:
    JP ERROR
;; Runs AUTO: numbers new lines automatically from a starting line by an increment.
ST_AUTO:
    LD DE,$000A                     ; the default start and increment are 10
    PUSH DE                         ; keep the start line
    JR Z,SNGAUT                     ; AUTO alone: start 10, increment 10
    CALL LINSPC                     ; DE = the start line
    EX DE,HL
    EX [SP],HL                      ; stack the start, HL = the increment
    JR Z,SNGAU1                     ; just a start line: keep the increment of 10
    EX DE,HL
    RST $08                         ; a comma must come before the increment
    .byte ','
    EX DE,HL
    LD HL,[AUTINC]                  ; the increment used last time
    EX DE,HL
    JR Z,SNGAUT                     ; a trailing comma keeps the last increment
    CALL LINGET                     ; DE = the new increment
    JP NZ,SNERR                     ; more after the increment: syntax error
SNGAUT:
    EX DE,HL
SNGAU1:
    LD A,H
    OR L
    JP Z,FCERR                      ; an increment of 0 is an FC error
    LD [AUTINC],HL
    LD [AUTFLG],A                   ; nonzero: AUTO on
    POP HL                          ; HL = the start line
    LD [AUTLIN],HL                  ; the first line number AUTO offers
    POP BC                          ; drop the NEWSTT return address
    JP MAIN                         ; the command level now prompts with numbers
;; Runs IF: evaluates the condition and runs the THEN part if it is true, else the ELSE part.
ST_IF:
    CALL FRMEVL
    LD A,[HL]
    CP $2C                          ; a comma may come before THEN
    CALL Z,CHRGTR
    CP $CA                          ; the THEN token
    CALL Z,CHRGTR
    DEC HL                          ; DOCOND fetches the character again

OKGOTO:
    PUSH HL
    CALL VSIGN                      ; Z when the condition is false
    POP HL
    JR Z,FALSIF                     ; false: look for an ELSE
;; Runs the chosen part of an IF: goes to a line number, or executes the statement.
DOCOND:
    RST $10                         ; the first character of the THEN or ELSE part
    JP C,ST_GOTO                    ; a line number means GOTO that line
    JP GONE3                        ; otherwise it is a statement to execute
;; Skips a false IF's THEN part to its matching ELSE, counting nested IFs, or to the line's end.
FALSIF:
    LD D,$01                        ; D = 1, the IF whose ELSE is wanted
SKPMRF:
    CALL ST_DATA                    ; skip one statement
    OR A
    RET Z                           ; the line ended with no ELSE: carry on
    RST $10
    CP $95                          ; the ELSE token
    JR NZ,SKPMRF
    DEC D                           ; a nested IF owns this ELSE: keep looking
    JR NZ,SKPMRF
    JR DOCOND                       ; the matching ELSE: run what follows it
;; Runs LPRINT: sends the PRINT output to the printer.
ST_LPRINT:
    LD A,$01                        ; 1 = printer
    LD [PRTFLG],A
.if REVISION = 12
    JP ST_PRINT_2
.else
ST_LPRINT_1:
    JP ST_PRINT_8
.endif
;; Runs PRINT: handles PRINT @ and PRINT # for the cassette, then prints the list of items.
ST_PRINT:
    CALL HOOK_PRINT                 ; a disk system may take over PRINT
.if REVISION = 12
    CP $40
    JR NZ,PNOTAT
.else
    CP $23                          ; PRINT # writes to the cassette
    JR NZ,ST_PRINT_8
    CALL CWRTON                     ; start the cassette, A = the cassette flag
    LD [PRTFLG],A
ST_PRINT_8:
    DEC HL                          ; fetch the character again
    RST $10
    CALL Z,CRDO                     ; PRINT alone prints an empty line
ST_PRINT_9:
    JP Z,FINPRT                     ; the statement ended: back to the display
    OR $20                          ; fold the case, so @ becomes $60
    CP $60                          ; is it PRINT @?
    JR NZ,ST_PRINT_10
.endif
    CALL GETINT                     ; DE = the screen position
    CP $04                          ; positions run 0 to 1023
    JP NC,FCERR
    PUSH HL
    LD HL,VIDEO                     ; the start of video memory
    ADD HL,DE
    LD [CURSOR_ADDRESS],HL          ; the cursor moves to that position
    LD A,E
    AND $3F                         ; the column within the 64-column row
    LD [TTYPOS],A
    POP HL
    RST $08                         ; a comma follows the position
    .byte ','
.if REVISION = 12
PNOTAT:
    CP $23
    JR NZ,ST_PRINT_2
    CALL CWRTON
    LD A,$80
    LD [PRTFLG],A
ST_PRINT_2:
    DEC HL
    RST $10
    CALL Z,CRDO
PRINTC:
    JP Z,FINPRT
.else
    JR ST_LPRINT_1                  ; on to the items to print
ST_PRINT_10:
    LD A,[HL]
.endif
    CP $BF                          ; the USING token
    JP Z,PRINUS
    CP $BC                          ; the TAB( token
    JP Z,TABER
    PUSH HL                         ; keep the text pointer
    CP $2C                          ; a comma moves to the next print zone
.if REVISION = 12
    JP Z,COMPRT
.else
    JR Z,COMPRT
.endif
    CP $3B                          ; a semicolon prints nothing between items
.if REVISION = 12
    JP Z,FINISH_CR_HOOK_11
    POP BC
.else
    JR Z,FINISH_CR_HOOK_1_1
.endif
    CALL FRMEVL                     ; evaluate the item to print
.if REVISION = 12
    PUSH HL
.else
    EX [SP],HL                      ; stack the text after the item
.endif
    RST $20                         ; Z for a string
    JR Z,STRDON
    CALL FOUT                       ; turn the number into text
    CALL STRLIT                     ; make it a temporary string
    CALL HOOK_PRINT_NUMBER          ; a disk system may format the number
    LD HL,[FACLO]                   ; HL = the number's string descriptor
    LD A,[PRTFLG]                   ; where is the output going?
    OR A
    JP M,LINCH2                     ; cassette: no line length to check
    JR Z,ISTTY                      ; zero: the display

LPTCD2:
    LD A,[LPTPOS]                   ; the printer's column
    ADD A,[HL]                      ; plus the item's length
    CP $84                          ; a printer line holds 132 columns
    JR LINCHK
;; Starts a new display line if the item at HL will not fit on the current one, then prints it.
ISTTY:
    LD A,[LINLEN]                   ; the display's line width
    LD B,A
    LD A,[TTYPOS]                   ; the cursor's column
    ADD A,[HL]                      ; plus the item's length
    CP B                            ; carry when it fits on this line
;; Prints a carriage return if carry is clear, then prints the item and a space.
LINCHK:
    CALL NC,CRDO
;; Prints a number's string and a space, then continues with the next PRINT item.
LINCH2:
    CALL STRPRT
    LD A,$20                        ; numbers are followed by a space
    CALL OUTDO
    OR A                            ; NZ, so the number is not printed again
;; Prints the string if Z is set, then continues with the next PRINT item.
STRDON:
    CALL Z,STRPRT
    POP HL                          ; HL = text pointer
.if REVISION = 12
    JP ST_PRINT_2
.else
    JP ST_PRINT_8                   ; on to the next item
.endif

;; Prints a carriage return unless the cursor is already at the start of a line (TTYPOS zero).
CRDONZ:
    LD A,[TTYPOS]
    OR A
    RET Z                           ; already at the start of a line

;; Prints a carriage return.
CRDO:
    LD A,$0D
    CALL OUTDO

;; Finishes a carriage return through the $41D0 hook and returns A zero.
CRFIN:
    CALL HOOK_CRDO                  ; a disk system can act on the new line
    XOR A                           ; A = 0, the new column
    RET

;; Moves PRINT output to the next 16-column zone for a comma, or writes a comma to the cassette.
COMPRT:
    CALL HOOK_PRINT_POSITION        ; a disk system can handle the comma
    LD A,[PRTFLG]
    OR A                            ; positive: display or printer
    JP P,NTCCAS
    LD A,$2C                        ; the cassette gets a comma between items
    CALL OUTDO
.if REVISION = 12
    JR FINISH_CR_HOOK_11
.else

FINISH_CR_HOOK_1_1:
    JR NOTABR                       ; on to the next item
.endif

;; Moves to the next print zone on the display or the printer.
NTCCAS:
    JR Z,ISCTTY                     ; zero: the display

;; Moves to the next print zone on the printer, from the printer's column.
LPTCD3:
    LD A,[LPTPOS]
    CP $70                          ; the last zone starts at column 112
    JP CHKCOM

;; Moves to the next print zone on the display, or starts a new line past the last zone.
ISCTTY:
    LD A,[CLMLST]                   ; the column of the last print zone
    LD B,A
    LD A,[TTYPOS]
    CP B                            ; at or past it: start a new line

;; Starts a new line if carry is clear, else prints the spaces to the next print zone.
CHKCOM:
    CALL NC,CRDO
.if REVISION = 12
    JR NC,FINISH_CR_HOOK_11
.else
    JR NC,NOTABR                    ; a new line is already the next zone
.endif

;; Works out the spaces from the column in A to the next 16-column zone and prints them.
MORCOM:
    SUB $10                         ; reduce the column below 16
    JR NC,MORCOM
    CPL                             ; A = spaces to the zone, minus one
    JR ASPA2

;; Runs TAB( in PRINT: prints spaces up to the given column on the display or printer.
;; Gives an FC error for the cassette.
TABER:
    CALL GTBYTC                     ; A = the TAB column
.if REVISION = 12
    AND $3F
.else
    AND $7F                         ; at most column 127
.endif
    LD E,A                          ; E = the column to tab to
    RST $08                         ; a parenthesis closes TAB(
    .byte ')'
    DEC HL                          ; the next fetch rereads the last character
    PUSH HL                         ; keep the text pointer
    CALL HOOK_PRINT_POSITION        ; a disk system can handle TAB(
    LD A,[PRTFLG]
    OR A
    JP M,FCERR                      ; TAB( on the cassette is an FC error
    JP Z,TTYIST                     ; zero: the display
    LD A,[LPTPOS]                   ; the printer's column
    JR DOSIZT

;; Prints spaces from the display's cursor column up to the TAB column in E.
TTYIST:
    LD A,[TTYPOS]

;; Prints the spaces that move from the current column to the TAB column in E, or none if already past it.
;; In:    A = current column, E = TAB column
DOSIZT:
    CPL                             ; A = minus the column, minus one
    ADD A,E                         ; A = spaces needed, minus one
.if REVISION = 12
    JR NC,FINISH_CR_HOOK_11
.else
    JR NC,NOTABR                    ; already at or past the column
.endif

ASPA2:
    INC A                           ; A = the number of spaces

;; Prints A spaces through <OUTDO>, then resumes the PRINT statement.
;; In:    A = number of spaces (1-255)
ASPAC:
    LD B,A                          ; B counts the spaces
    LD A,$20

REPOUT:
    CALL OUTDO
    DEC B
    JR NZ,REPOUT

.if REVISION = 12
FINISH_CR_HOOK_11:
.else
NOTABR:
.endif
    POP HL                          ; HL = text pointer
    RST $10                         ; the next item or the end of the statement
.if REVISION = 12
    JP PRINTC
.else
    JP ST_PRINT_9
.endif

;; Ends output to the printer or cassette: turns the cassette off if it was on and makes the video current.
FINPRT:
    LD A,[PRTFLG]                   ; is the cassette the output?
    OR A
    CALL M,CASSETTE_OFF             ; cassette output ends with the motor off
    XOR A                           ; output goes back to the display
    LD [PRTFLG],A
    CALL HOOK_FINPRT                ; a disk system can finish its output
    RET

;; Holds the "?REDO" message shown when keyboard INPUT data is not valid.
TRYAGN:
    .byte "?REDO", $0D
    .byte $00
;; Handles badly formed INPUT or READ data: ?SN for READ, ?FD for cassette INPUT, else ?REDO and a retry.
TRMNOK:
    LD A,[READ_INPUT_FLAG]          ; set while READ is running
    OR A
    JP NZ,DATSNE                    ; bad DATA is a syntax error in its line
    LD A,[CASFLG]                   ; zero while INPUT # reads the cassette
    OR A
    LD E,ERR_FD                     ; bad data on tape cannot be asked again
    JP Z,ERROR
    POP BC                          ; drop the return address

;; Prints ?REDO and returns with HL back at the INPUT statement so it runs again.
RDOINP:
    LD HL,$2178                     ; the ?REDO message
    CALL STROUT
    LD HL,[SAVTXT]                  ; HL = the INPUT statement, to run it again
    RET
;; Runs INPUT: reads a cassette record for INPUT #-1, or prints the prompt and reads a keyboard line,
;; then assigns the values to the listed variables.
ST_INPUT:
    CALL ERRDIR                     ; INPUT is not allowed in direct mode
    LD A,[HL]
    CALL HOOK_INPUT                 ; a disk system may take over INPUT
    SUB $23                         ; zero for INPUT #, the cassette
    LD [CASFLG],A                   ; remember where the data comes from
    LD A,[HL]
    JR NZ,INTCAS                    ; from the keyboard
    CALL CSRDON                     ; skip the #-1, and start the tape
    PUSH HL                         ; keep the text pointer
    LD B,$FA                        ; at most 250 bytes per record
    LD HL,[BUFPNT]                  ; the record goes into the input buffer
;; Copies cassette bytes into the input buffer until a carriage return or 250 bytes.
FILBUF:
    CALL CASSETTE_READ
    LD [HL],A
    INC HL
    CP $0D                          ; a carriage return ends the record
    JR Z,ENDREC
    DJNZ FILBUF
;; Ends a cassette INPUT record with a zero byte, stops the cassette and joins the shared assignment code.
ENDREC:
    DEC HL                          ; replace the carriage return or last byte
    LD [HL],$00                     ; with the end-of-line zero
    CALL CASSETTE_OFF
    LD HL,[BUFPNT]                  ; HL just before the data, ready for parsing
    DEC HL
    JR INPCN3                       ; on to assign the values
;; Prints any quoted INPUT prompt, then goes on to read a keyboard line at $21DB.
INTCAS:
    LD BC,$21DB                     ; NOTQTI reads the reply after the prompt
    PUSH BC

;; Prints the quoted prompt at HL and its semicolon, or returns at once if HL is not at a quote.
;; In:    A = character at HL
QTINP:
    CP $22
    RET NZ                          ; no quote: no prompt to print
    CALL STRLTI                     ; make the prompt a temporary string
    RST $08                         ; a semicolon must follow the prompt
    .byte ';'
    PUSH HL                         ; keep the text pointer
    CALL STRPRT                     ; show the prompt
    POP HL
    RET

;; Prints "? " and reads a keyboard line for INPUT; BREAK stops the program and an empty line skips it.
NOTQTI:
    PUSH HL                         ; keep the text pointer

GETAGN:
    CALL QINLIN
    POP BC                          ; BC = text pointer
    JP C,STPEND                     ; BREAK stops the program
    INC HL
    LD A,[HL]                       ; the first character typed
    OR A                            ; Z for an empty reply
    DEC HL
    PUSH BC                         ; keep the text pointer again
    JP Z,DATAH                      ; an empty reply leaves the variables unchanged
;; Stores a comma before the input text and enters the shared INPUT and READ assignment loop.
INPCN3:
    LD [HL],$2C                     ; Comma at the buffer start lets the loop expect a separator
    JR INPCON
;; Runs READ, assigning values from DATA statements starting at the saved DATA position.
ST_READ:
    PUSH HL
    LD HL,[DATPTR]                  ; HL = where the last READ stopped in the DATA statements
    .byte $F6

;; Enters the INPUT and READ assignment loop for INPUT, with HL at the data to read.
INPCON:
    XOR A                           ; Zero flag value marks INPUT (READ arrives here with A nonzero)
    LD [READ_INPUT_FLAG],A          ; Remember whether keyboard input or DATA statements supply values
    EX [SP],HL                      ; Stack the data pointer, HL back to the variable list
    JR LOPDAT
;; Requires a comma, then assigns the next variable in the INPUT or READ list.
LOPDT2:
    RST $08
    .byte ','
;; Finds the next listed variable and the data for it, moving on to the next DATA statement for READ
;; or asking for more input with "?" when keyboard data runs out.
LOPDAT:
    CALL PTRGET                     ; DE = address of the variable to fill
    EX [SP],HL                      ; HL = data pointer, text pointer saved on the stack
    PUSH DE                         ; Keep the variable address for the assignment
    LD A,[HL]
    CP $2C                          ; A separator here means a value follows
    JR Z,DATBK
    LD A,[READ_INPUT_FLAG]          ; Out of data: READ must look for another DATA statement
    OR A
    JP NZ,DATLOP
    LD A,[CASFLG]                   ; Reading from cassette has no way to ask for more
    OR A
    LD E,ERR_OD                     ; Cassette data ran out: Out of DATA
    JP Z,ERROR
    LD A,$3F                        ; Prompt "?" for the remaining INPUT values
    CALL OUTDO
    CALL QINLIN
    POP DE                          ; DE = variable address
    POP BC                          ; BC = saved text pointer
    JP C,STPEND                     ; BREAK pressed: stop the program
    INC HL                          ; Look at the first typed character
    LD A,[HL]
    OR A
    DEC HL                          ; An empty reply leaves the remaining variables unchanged
    PUSH BC
    JP Z,DATAH
    PUSH DE
;; Reads one value from the data at HL into the current variable, as a string or a number by its type.
DATBK:
    CALL HOOK_READ_ITEM             ; Extension hook for reading one item
    RST $20                         ; Test the target variable's type, strings are handled here
    PUSH AF                         ; Keep the type flags for choosing single or double conversion
    JR NZ,NUMINS                    ; Numeric variable: convert the text as a number
    RST $10                         ; First character of the string value
    LD D,A
    LD B,A
    CP $22                          ; A quoted string runs up to the closing quote
    JR Z,NOWGET
    LD D,$3A                        ; Unquoted string ends at a colon or a comma
    LD B,$2C
    DEC HL                          ; Back up so the first character is included
;; Makes a string from the data at HL, ending at the terminator in B or D, and assigns it.
;; In:    B, D = terminating characters (a quote, or a comma and a colon)
NOWGET:
    CALL STRLT2                     ; Build a string descriptor for the text

;; Stores the value read into the variable through <INPCOM>, then checks what follows the value.
DOASIG:
    POP AF                          ; Drop the saved type flags
    EX DE,HL
    LD HL,$225A                     ; Return through STRDN2 to check what follows the value
    EX [SP],HL                      ; Data pointer to stack, HL = variable address
    PUSH DE
    JP INPCOM                       ; Assign the value through the shared LET code
;; Converts the numeric data at HL into the FAC, in double precision for a double variable, and assigns it.
NUMINS:
    RST $10                         ; Skip spaces before the number
    POP AF
    PUSH AF
    LD BC,$2243                     ; Return to DOASIG once the number is converted
    PUSH BC
    JP C,FIN                        ; Carry set means the variable is not double precision
    JP NC,FINDBL                    ; Double variable: convert at full precision

;; Checks that a value read ends at a comma or the end of the data, else reports bad data via <TRMNOK>.
STRDN2:
    DEC HL
    RST $10                         ; Next character after the value
    JR Z,TRMOK                      ; End of the data is a valid stop
    CP $2C                          ; Only a comma may separate values
    JP NZ,TRMNOK
;; Moves to the next listed variable, or at the end of the list saves the DATA position for READ
;; or warns ?Extra ignored when INPUT data is left over.
TRMOK:
    EX [SP],HL                      ; Save the data pointer, HL = variable list
    DEC HL
    RST $10                         ; More text after the variable means more to assign
    JP NZ,LOPDT2                    ; Another variable follows, so require a comma
    POP DE                          ; DE = data pointer
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,[READ_INPUT_FLAG]          ; Find out whether this was READ or INPUT
    OR A
    EX DE,HL                        ; HL = text pointer, DE = data pointer
    JP NZ,RESFIN                    ; READ: record where the data stopped and finish
    PUSH DE                         ; Save the text pointer for FINPRG
    CALL HOOK_READ_LIST             ; Extension hook for the end of an INPUT list
    OR [HL]                         ; Anything left in the typed data is surplus
    LD HL,$2286                     ; HL = the "?Extra ignored" message
    CALL NZ,STROUT

;; Restores the text pointer and ends INPUT or READ through <FINPRT>.
FINPRG:
    POP HL
    JP FINPRT

;; Holds the "?Extra ignored" warning shown when INPUT gets more values than variables.
EXIGNT:
    .byte "?Extra ignored", $0D
    .byte $00
;; Skips ahead to the next DATA statement in the program text for READ, giving ?OD at the program's end
;; and noting each line number passed in DATLIN.
DATLOP:
    CALL ST_DATA                    ; Skip to the end of the current statement

DATFND:
    OR A                            ; Zero byte means the line ended, else a colon did
    JR NZ,NOWLIN
    INC HL                          ; Fetch the link to the next line
    LD A,[HL]
    INC HL
    OR [HL]                         ; A zero link marks the end of the program
    LD E,ERR_OD                     ; No more DATA anywhere: Out of DATA
    JP Z,ERROR
    INC HL                          ; DE = number of the line being entered
    LD E,[HL]
    INC HL
    LD D,[HL]
    EX DE,HL
    LD [DATLIN],HL                  ; Kept so a bad DATA item reports the right line
    EX DE,HL
;; Starts reading values if the statement at HL is DATA, else keeps looking for one.
NOWLIN:
    RST $10                         ; Look at the statement's first token
    CP $88                          ; Is it the DATA token?
    JR NZ,DATLOP
    JP DATBK
;; Runs NEXT: adds the STEP to the loop variable and loops back to the FOR unless it passed the limit,
;; then does the same for each further variable in a comma list.
ST_NEXT:
    LD DE,RESET                     ; DE = zero accepts any FOR when NEXT names no variable

;; Steps one NEXT loop variable (DE) and loops or pops the FOR entry; repeats for a comma list.
NEXTC:
    CALL NZ,PTRGET                  ; A variable after NEXT gives its address in DE
    LD [TEMP],HL                    ; Keep the text pointer in case the loop ends
    CALL FNDFOR                     ; Find the FOR entry on the stack matching DE
    JP NZ,NFERR                     ; No matching FOR: NEXT without FOR
    LD SP,HL                        ; Discard any inner FOR and GOSUB entries
    LD [SAVSTK],HL                  ; Make the trimmed stack the one restored on errors
    PUSH DE                         ; Keep the loop variable address
    LD A,[HL]                       ; A = sign of the STEP value
    INC HL
    PUSH AF                         ; Saved for the termination test
    PUSH DE
    LD A,[HL]                       ; A = flag for an integer loop variable
    INC HL
    OR A                            ; Negative flag means an integer FOR
    JP M,INTNXT
    CALL MOVFM                      ; FAC = the STEP value
    EX [SP],HL                      ; Entry pointer saved, HL = loop variable address
    PUSH HL
    CALL FADDS                      ; Add the variable's value to the STEP
    POP HL
    CALL MOVMF                      ; Store the stepped value back into the variable
    POP HL                          ; HL = pointer into the FOR entry, at the limit
    CALL MOVRM                      ; BC/DE = the TO limit
    PUSH HL                         ; Keep the entry pointer, now past the limit
    CALL FCOMP                      ; A = sign of (variable - limit)
    JR FINNXT

;; Steps an integer FOR variable with <IADD>, giving ?OV on overflow, and compares it with the limit.
INTNXT:
    INC HL                          ; Skip the unused single precision STEP slot
    INC HL
    INC HL
    INC HL
    LD C,[HL]                       ; BC = integer STEP value
    INC HL
    LD B,[HL]
    INC HL
    EX [SP],HL                      ; Entry pointer saved, HL = loop variable address
    LD E,[HL]                       ; DE = current loop variable value
    INC HL
    LD D,[HL]
    PUSH HL                         ; Keep the pointer to the variable's high byte
    LD L,C                          ; HL = STEP for the addition
    LD H,B
    CALL IADD
    LD A,[VALTYP]                   ; IADD switched to single precision on overflow
    CP $04
    JP Z,OVERR                      ; Loop variable left the integer range: Overflow
    EX DE,HL                        ; DE = new loop variable value
    POP HL
    LD [HL],D                       ; Store the new value in the variable
    DEC HL
    LD [HL],E
    POP HL                          ; HL = pointer into the FOR entry, at the limit
    PUSH DE                         ; Keep the new value for the comparison
    LD E,[HL]                       ; DE = the TO limit
    INC HL
    LD D,[HL]
    INC HL
    EX [SP],HL                      ; Entry pointer saved, HL = new loop variable value
    CALL ICOMP                      ; A = sign of (variable - limit)

;; Ends the loop if the variable passed its limit, else continues after the FOR statement on its line.
FINNXT:
    POP HL                          ; HL = entry pointer past the limit
    POP BC                          ; B = sign of the STEP
    SUB B                           ; Zero when the variable moved past the limit
    CALL MOVRM                      ; DE = the FOR's line number, BC = its text pointer
    JR Z,LOOPDN                     ; Loop finished
    EX DE,HL                        ; Resume on the FOR's line
    LD [CURLIN],HL
    LD L,C                          ; HL = text just after the FOR statement
    LD H,B
    JP NXTCON

;; Drops the finished FOR entry and runs the next statement, or steps the next variable after a comma.
LOOPDN:
    LD SP,HL                        ; Pop the FOR entry off the stack
    LD [SAVSTK],HL                  ; Make the trimmed stack the one restored on errors
    LD HL,[TEMP]                    ; HL = text after the NEXT variable
    LD A,[HL]
    CP $2C                          ; A comma means another variable to step
    JP NZ,NEWSTT
    RST $10                         ; Skip the comma
    CALL NEXTC

;; Checks for an opening parenthesis and evaluates the expression that follows.
FRMPRN:
    RST $08
    .byte '('

;; Evaluates the expression at HL into the accumulator.
FRMEVL:
    DEC HL                          ; Back up so the next fetch reads the first character

;; Evaluates the expression at HL starting at the lowest operator precedence (D zero).
FRMCHK:
    LD D,$00                        ; Zero precedence accepts every operator

;; Evaluates an expression with operators above precedence D, the core of FRMEVL.
LPOPER:
    PUSH DE                         ; Save the caller's precedence
    LD C,$01                        ; Ensure stack room before recursing
    CALL GETSTK
    CALL EVAL                       ; Evaluate one operand into the FAC
    LD [TEMP2],HL                   ; Keep the text pointer after the operand

RETAOP:
    LD HL,[TEMP2]

;; Gathers the relational operators (less than, equals, greater than) after an operand into a mask in D, giving ?SN for repeats.
TSTOP:
    POP BC                          ; B = precedence the current operator must beat

NOTSTV:
    LD A,[HL]                       ; Look at the character after the operand
    LD D,$00                        ; D collects bits for <, =, > seen in a row

LOPREL:
    SUB $D4                         ; Relational tokens start at > ($D4)
    JR C,ENDREL
    CP $03                          ; Tokens beyond < are not relational
    JR NC,ENDREL
    CP $01                          ; Turn > = < into mask bits 1, 2 and 4
    RLA
    XOR D                           ; Add the bit, carry if it was already present
    CP D
    LD D,A                          ; D = updated relational mask
    JP C,SNERR                      ; The same relation twice is a Syntax error
    LD [TEMP3],HL                   ; Remember where the operator was
    RST $10
    JR LOPREL

;; Applies the operator at HL: relationals go to <FINREL>, string + to <CAT>, and an arithmetic
;; operator that binds tighter than B saves the left operand and evaluates the right one.
ENDREL:
    LD A,D                          ; Any relation seen goes to the comparison code
    OR A
    JP NZ,FINREL
    LD A,[HL]                       ; A = the operator token
    LD [TEMP3],HL                   ; Remember where the operator was
    SUB $CD                         ; Arithmetic and logical tokens start at + ($CD)
    RET C                           ; Not an operator: the expression ends here
    CP $07                          ; Only + - * / ^ AND OR are binary operators
    RET NC
    LD E,A                          ; E = operator index, 0 for +
    LD A,[VALTYP]                   ; A string with + (index zero) means concatenation
    SUB $03
    OR E
    JP Z,CAT
    LD HL,$189A                     ; HL = the operator precedence table
    ADD HL,DE                       ; Index it by the operator
    LD A,B                          ; A = precedence the caller needs exceeded
    LD D,[HL]                       ; D = this operator's precedence
    CP D                            ; Weaker operator: let the caller apply its own first
    RET NC
    PUSH BC                         ; Save the caller's precedence
    LD BC,$2346                     ; Come back to RETAOP after the right operand
    PUSH BC                         ; Return address on the stack for after the right operand
    LD A,D                          ; Precedence $7F belongs only to ^
    CP $7F
    JP Z,EXPSTK
    CP $51                          ; AND and OR have the lowest arithmetic precedence
    JP C,ANDORD

;; Pushes the FAC as the left operand of a numeric operator, giving ?TM for a string, then evaluates
;; the right operand.
NUMREL:
    LD HL,FACLO                     ; HL = the FAC, holding the left operand
    OR A                            ; Clear carry: a double takes its low half from the double FAC

PUSVAL:
    LD A,[VALTYP]                   ; A = type minus 3: negative int, zero string, 1 single, 5 double
    DEC A
    DEC A
    DEC A
    JP Z,TMERR                      ; A string cannot take an arithmetic operator: Type mismatch
    LD C,[HL]                       ; Push the low word of the value
    INC HL
    LD B,[HL]
    PUSH BC
    JP M,VPUSHD                     ; An integer is fully pushed
    INC HL                          ; Push the high word of a single
    LD C,[HL]
    INC HL
    LD B,[HL]
    PUSH BC
    PUSH AF                         ; Keep the adjusted type
    OR A                            ; Odd parity of 1 marks single, even parity of 5 marks double
    JP PO,VPSHD1
    POP AF
    INC HL                          ; Step to the double's remaining bytes
    JR C,PUSDVR                     ; Carry means HL already points at the low half
    LD HL,$411D                     ; HL = the double FAC's low four bytes

PUSDVR:
    LD C,[HL]                       ; Push the low half of the double
    INC HL
    LD B,[HL]
    INC HL
    PUSH BC
    LD C,[HL]
    INC HL
    LD B,[HL]
    PUSH BC
    .byte $06

VPSHD1:
    POP AF

VPUSHD:
    ADD A,$03                       ; Restore the real type code
    LD C,E                          ; C = operator index
    LD B,A                          ; B = type of the stacked left operand
    PUSH BC                         ; Stack the type and operator for APPLOP
    LD BC,$2406                     ; After the right operand, apply the operator in APPLOP

FINTMP:
    PUSH BC
    LD HL,[TEMP3]                   ; HL = position of the operator
    JP LPOPER                       ; Evaluate the right operand at this operator's precedence

;; Sets up ^: pushes the left operand as single precision and evaluates the right operand.
EXPSTK:
    CALL FRCSNG                     ; ^ always works on single precision values
    CALL PUSHF                      ; Stack the base as the left operand
    LD BC,$13F2                     ; BC = the exponentiation routine to run after the right side
    LD D,$7F                        ; Precedence of ^, the tightest binding operator
    JR FINTMP

;; Sets up AND or OR: pushes the left operand as an integer and evaluates the right operand.
ANDORD:
    PUSH DE                         ; Keep the precedence and operator index
    CALL FRCINT                     ; AND and OR work on 16-bit integers
    POP DE
    PUSH HL                         ; Stack the integer left operand
    LD BC,$25E9                     ; BC = the AND/OR routine to run after the right side
    JR FINTMP

;; Sets up a relational operator: saves the left operand, number or string, and evaluates the right one.
FINREL:
    LD A,B                          ; A = precedence the caller needs exceeded
    CP $64                          ; Relations bind at $64, so a tighter caller returns first
    RET NC
    PUSH BC                         ; Save the caller's precedence
    PUSH DE                         ; D = relational mask, saved for the comparison
    LD DE,$6404                     ; D = relational precedence, E = compare operator index
    LD HL,$25B8                     ; After the compare, turn its result into true or false
    PUSH HL
    RST $20                         ; Strings are compared differently from numbers
    JP NZ,NUMREL                    ; Numbers are pushed like any arithmetic operand
    LD HL,[FACLO]                   ; HL = descriptor of the left string
    PUSH HL
    LD BC,$258C                     ; BC = the string compare routine
    JR FINTMP

;; Applies a pending operator to the stacked left operand and the FAC, bringing both to one type first
;; and calling the routine for that type.
APPLOP:
    POP BC                          ; B = left operand type, C = operator index
    LD A,C
    LD [DORES],A                    ; Keep the operator index for the dispatch tables
    LD A,B
    CP $08                          ; Is the left operand double precision?
    JR Z,STKDBL
    LD A,[VALTYP]                   ; Is the right operand in the FAC double?
    CP $08
    JP Z,FACDBL
    LD D,A                          ; D = right operand type
    LD A,B
    CP $04                          ; Is the left operand single precision?
    JP Z,STKSNG
    LD A,D
    CP $03                          ; A string on the right with a number on the left
    JP Z,TMERR
    JP NC,FACSNG                    ; Right side single, left integer: work in single
    LD HL,$18BF                     ; HL = table of integer operator routines
    LD B,$00                        ; BC = operator index, doubled for word entries
    ADD HL,BC
    ADD HL,BC
    LD C,[HL]                       ; BC = address of the integer routine
    INC HL
    LD B,[HL]
    POP DE                          ; DE = left integer operand
    LD HL,[FACLO]                   ; HL = right integer operand
    PUSH BC                         ; Run the routine by returning into it
    RET

;; Applies an operator whose left operand is double precision, converting the FAC to double to match.
STKDBL:
    CALL FRCDBL                     ; Bring the right operand up to double
    CALL VMOVAF                     ; Move it to the second accumulator ARG
    POP HL                          ; Pop the left double's low half into the FAC
    LD [DFAC_MID],HL
    POP HL
    LD [DFACLO],HL

SNGDBL:
    POP BC                          ; Pop the left operand's high half
    POP DE
    CALL MOVFR                      ; Put it into the FAC

SETDBL:
    CALL FRCDBL                     ; Convert a single or integer FAC to double
    LD HL,$18AB                     ; HL = table of double precision operator routines

DODSP:
    LD A,[DORES]                    ; A = operator index times two
    RLCA
    PUSH BC
    LD C,A
    LD B,$00
    ADD HL,BC                       ; HL = entry for this operator
    POP BC
    LD A,[HL]                       ; HL = routine address
    INC HL
    LD H,[HL]
    LD L,A
    JP [HL]

;; Applies an operator to a double FAC and an integer or single left operand, which becomes double.
FACDBL:
    PUSH BC                         ; Keep the left type and operator index
    CALL VMOVAF                     ; Right double goes to ARG
    POP AF                          ; A = type of the left operand
    LD [VALTYP],A                   ; Make the FAC's type that of the left operand
    CP $04                          ; Single left operand: pop it and convert
    JR Z,SNGDBL
    POP HL                          ; Integer left operand into the FAC
    LD [FACLO],HL
    JR SETDBL

;; Applies an operator whose left operand is single precision, converting the FAC to single to match.
STKSNG:
    CALL FRCSNG                     ; Bring the right operand up to single
    POP BC                          ; BC/DE = left single operand
    POP DE

SNGDO:
    LD HL,$18B5                     ; HL = table of single precision operator routines
    JR DODSP

;; Applies an operator to a single FAC and an integer left operand, which becomes single.
FACSNG:
    POP HL                          ; HL = left integer operand
    CALL PUSHF                      ; Stack the right single operand
    CALL CONSIH                     ; Turn the left integer into single in the FAC
    CALL MOVRF                      ; BC/DE = the left operand, now single
    POP HL                          ; Pop the right operand back into the FAC
    LD [FACHI],HL
    POP HL
    LD [FACLO],HL
    JR SNGDO

;; Divides the integer in DE by the integer in HL in single precision, leaving the quotient in the FAC.
INTDIV:
    PUSH HL                         ; Keep the divisor
    EX DE,HL                        ; Convert the dividend first
    CALL CONSIH
    POP HL
    CALL PUSHF                      ; Stack the dividend as single
    CALL CONSIH                     ; Convert the divisor in the FAC
    JP FDIVT

;; Evaluates one operand at HL into the FAC: a number, variable, string, unary minus, NOT or a function.
;; Gives ?MO if the operand is missing.
EVAL:
    RST $10                         ; Fetch the operand's first character
MOERR:
    LD E,ERR_MO                     ; Nothing there: Missing operand
    JP Z,ERROR
    JP C,FIN                        ; A digit starts a numeric constant
    CALL ISLET                      ; A letter starts a variable name
    JP NC,ISVAR
    CP $CD                          ; Unary + is ignored
    JR Z,EVAL
    CP $2E                          ; A leading point starts a number too
    JP Z,FIN
    CP $CE                          ; Unary minus token
    JP Z,DOMIN
    CP $22                          ; Opening quote of a string literal
    JP Z,STRLTI
    CP $CB                          ; NOT token
    JP Z,NOTER
    CP $26                          ; & prefix goes to the extension hook
    JP Z,HOOK_AMPERSAND
    CP $C3                          ; ERR token
    JR NZ,NTERC
    RST $10
    LD A,[ERRFLG]                   ; A = the last error code

NTDERC:
    PUSH HL
    CALL SNGFLT                     ; Return it as a number in the FAC
    POP HL
    RET
NTERC:
    CP $C2                          ; ERL token
    JR NZ,NTERL
    RST $10
    PUSH HL
    LD HL,[ERRLIN]                  ; HL = line number of the last error
    CALL INEG2                      ; Return it as a positive number
    POP HL
    RET
;; Handles VARPTR, returning a variable's address as an integer, or ?FC if it doesn't exist.
NTERL:
    CP $C0                          ; VARPTR token
    JR NZ,NTVARP
    RST $10
    RST $08
    .byte '('
    CALL PTRGET                     ; DE = address of the named variable

VARRET:
    RST $08
    .byte ')'
    PUSH HL
    EX DE,HL                        ; HL = the variable address
    LD A,H                          ; Zero means the variable was never created
    OR L
    JP Z,FCERR                      ; Unknown variable: Illegal function call
    CALL MAKINT                     ; Return the address as an integer
    POP HL
    RET
;; Dispatches USR, INSTR, MEM, TIME$, POINT, INKEY$, STRING$, FN and the other built-in functions.
NTVARP:
    CP $C1                          ; USR token
    JP Z,USRFN
    CP $C5                          ; INSTR token, handled by the extension hook
    JP Z,HOOK_INSTR
    CP $C8                          ; MEM token
    JP Z,MEM
    CP $C7                          ; TIME$ token, handled by the extension hook
    JP Z,HOOK_TIME
    CP $C6                          ; POINT token
    JP Z,POINT
    CP $C9                          ; INKEY$ token
    JP Z,INKEY
    CP $C4                          ; STRING$ token
    JP Z,STRNG
    CP $BE                          ; FN token, handled by the extension hook
    JP Z,HOOK_FN
    SUB $D7                         ; Function tokens start at SGN ($D7)
    JP NC,ISFUN                     ; A built-in function

;; Evaluates a parenthesized expression at HL, checking both parentheses.
PARCHK:
    CALL FRMPRN
    RST $08
    .byte ')'
    RET

;; Evaluates a unary minus, evaluating its operand and negating the FAC with <VNEG>.
DOMIN:
    LD D,$7D                        ; Precedence of unary minus, above all binary arithmetic
    CALL LPOPER                     ; Evaluate just the operand
    LD HL,[TEMP2]                   ; HL = text after the operand
    PUSH HL                         ; Saved for LABBCK
    CALL VNEG

;; Restores the text pointer to HL and returns, the shared exit of functions and unary minus.
LABBCK:
    POP HL
    RET

;; Loads the variable named at HL into the FAC; a string leaves its descriptor address in the FAC.
ISVAR:
    CALL PTRGET                     ; DE = the variable's address

;; Loads the variable at DE into the FAC, entered once its address is known.
RETVAR:
    PUSH HL
    EX DE,HL                        ; HL = the variable address
    LD [FACLO],HL                   ; For a string the FAC holds its descriptor address
    RST $20                         ; Numeric variables copy their value into the FAC
    CALL NZ,VMOVFM
    POP HL
    RET

;; Calls a built-in function, first evaluating the string and number arguments for the string functions
;; that take them.
;; In:    A = function token minus $D7
ISFUN:
    LD B,$00
    RLCA                            ; Double the index for the word-sized dispatch table
    LD C,A
    PUSH BC                         ; Keep the table offset
    RST $10                         ; Step to the opening parenthesis
    LD A,C
    CP $41                          ; LEFT$, RIGHT$ and MID$ take a string and a number
    JR C,OKNORM
    CALL FRMPRN                     ; Evaluate the string argument
    RST $08
    .byte ','
    CALL CHKSTR                     ; The first argument must be a string
    EX DE,HL
    LD HL,[FACLO]                   ; HL = the string's descriptor
    EX [SP],HL                      ; Stack the descriptor, HL = table offset
    PUSH HL                         ; Keep the table offset
    EX DE,HL
    CALL GETBYT                     ; E = the numeric argument
    EX DE,HL                        ; HL = the number, DE = text pointer
    EX [SP],HL                      ; Stack the number, HL = table offset
    JR FINGO

;; Evaluates a function's argument in parentheses, as single precision where needed, and calls it.
OKNORM:
    CALL PARCHK                     ; Evaluate the single argument in parentheses
    EX [SP],HL                      ; Stack the text pointer, HL = table offset
    LD A,L
    CP $0C                          ; SGN through POS take any numeric type
    JR C,NOTFRF
    CP $1B                          ; SQR through ATN work in single precision
    PUSH HL
    CALL C,FRCSNG
    POP HL

;; Calls the built-in function whose doubled number is in HL through FUNDSP, returning through $253E.
NOTFRF:
    LD DE,$253E                     ; Functions return through LABBCK to restore the text pointer
    PUSH DE

FINGO:
    LD BC,FUNDSP                    ; BC = the function address table

;; Jumps to the address stored at HL+BC, dispatching through a table of addresses.
DISPAT:
    ADD HL,BC
    LD C,[HL]                       ; Fetch the routine address from the table
    INC HL
    LD H,[HL]
    LD L,C
    JP [HL]

;; Compares the string on the stack with the string in the FAC, leaving the result in A for DOCMP.
STRCMP:
    CALL FRESTR                     ; Free the right string, HL = its descriptor
    LD A,[HL]                       ; A = right string length
    INC HL
    LD C,[HL]                       ; BC = right string address
    INC HL
    LD B,[HL]
    POP DE                          ; DE = descriptor of the left string
    PUSH BC                         ; Keep the right string's address and length
    PUSH AF
    CALL FRETMP                     ; Free the left string, HL = its descriptor
    POP DE                          ; D = right string length
    LD E,[HL]                       ; E = left string length
    INC HL
    LD C,[HL]                       ; BC = left string address
    INC HL
    LD B,[HL]
    POP HL                          ; HL = right string address

;; Compares two strings in memory a byte at a time, the shorter one being less when they match.
;; In:    BC, E = first string's address and length; HL, D = second string's
CSLOOP:
    LD A,E                          ; Both strings used up with no difference: equal
    OR D
    RET Z
    LD A,D                          ; Right string ended first, so it is the smaller
    SUB $01
    RET C
    XOR A                           ; Left string ended first, so it is the smaller
    CP E
    INC A
    RET NC
    DEC D                           ; One character less in each
    DEC E
    LD A,[BC]                       ; Compare the next characters
    CP [HL]
    INC HL
    INC BC
    JR Z,CSLOOP
    CCF                             ; Result follows which character is larger
    JP SIGNS

;; Turns a comparison result in A into -1 (true) or 0 (false) in the FAC by the relational mask.
DOCMP:
    INC A                           ; Map the result (-1, 0, 1) onto bits >, =, <
    ADC A,A
    POP BC                          ; B = mask of the relations written
    AND B                           ; Does the outcome match any of them?
    ADD A,$FF                       ; Carry when it does
    SBC A,A                         ; A = -1 for true, 0 for false
    CALL CONIA                      ; The result is an integer
    JR RETAPG

;; Evaluates NOT, complementing every bit of its operand as an integer.
NOTER:
    LD D,$5A                        ; Precedence of NOT, above the relations
    CALL LPOPER                     ; Evaluate the operand
    CALL FRCINT                     ; NOT works on a 16-bit integer
    LD A,L                          ; Complement both bytes
    CPL
    LD L,A
    LD A,H
    CPL
    LD H,A
    LD [FACLO],HL                   ; Store the result in the FAC
    POP BC                          ; Drop EVAL's return, the operand pointer is already saved

;; Goes back to <RETAOP> to continue evaluating the expression.
RETAPG:
    JP RETAOP

;; The routine behind RST $20.
GETYPR:
    LD A,[VALTYP]
    CP $08

;; Sets the type flags from VALTYP in A after its CP 8: carry clear for double, else Z for a string
;; and minus for an integer.
CGETYP:
    JR NC,NCASE
    SUB $03                         ; Map 2, 3, 4 to -1, 0, 1 for the sign and zero flags
    OR A
    SCF                             ; Carry set marks a non-double type
    RET
;; Returns the flags for double precision: carry, zero and sign all clear.
NCASE:
    SUB $03
    OR A
    RET

;; Applies AND or OR to the stacked integer and the FAC as 16-bit integers, leaving an integer result.
DANDOR:
    PUSH BC                         ; B = precedence, telling AND from OR
    CALL FRCINT                     ; Right operand as an integer in HL
    POP AF                          ; A = the operator's precedence
    POP DE                          ; DE = left integer operand
    LD BC,$27FA                     ; Return through the integer result routine with A, L
    PUSH BC
    CP $46                          ; OR has precedence $46, AND has $50
    JR NZ,NOTOR
    LD A,E                          ; OR the low bytes
    OR L
    LD L,A
    LD A,H                          ; OR the high bytes into A
    OR D
    RET
;; ANDs DE with HL, the high byte in A and the low byte in L, for the AND operator.
NOTOR:
    LD A,E                          ; AND the low bytes
    AND L
    LD L,A
    LD A,H                          ; AND the high bytes into A
    AND D
    RET

;; Continues a DIM list: returns at the end of the statement, else requires a comma and goes on.
DIMCON:
    DEC HL
    RST $10                         ; End of the statement ends DIM
    RET Z
    RST $08
    .byte $2C
;; Runs DIM, creating each array in the list with the sizes given.
ST_DIM:
    LD BC,$2603                     ; Return to DIMCON after each array
    PUSH BC                         ; (DIM enters PTRGET with A nonzero)
    .byte $F6

;; Finds the variable named at HL, creating it if needed, and returns the address of its value in DE.
PTRGET:
    XOR A                           ; Not dimensioning, a plain lookup
    LD [DIMFLG],A
    LD B,[HL]                       ; B = first character of the name

;; Enters PTRGET with DIMFLG already set, parsing the name whose first character is in B.
PTRGT2:
    CALL ISLET                      ; A name must start with a letter
    JP C,SNERR
    XOR A                           ; C = second name character, zero if none
    LD C,A
    RST $10                         ; A digit can be the second character
    JR C,ISSEC
    CALL ISLET                      ; Neither letter nor digit: a one-character name
    JR C,NOSEC
ISSEC:
    LD C,A                          ; Keep the second character
EATEM:
    RST $10                         ; Skip any further digits
    JR C,EATEM
    CALL ISLET                      ; And any further letters, only two count
    JR NC,EATEM
;; Finds a variable's type from its suffix (%, $, ! or #) or from the DEF type table.
NOSEC:
    LD DE,$2652                     ; Return to HAVTYP with the type in D
    PUSH DE
    LD D,$02                        ; % means integer
    CP $25
    RET Z
    INC D                           ; $ means string
    CP $24
    RET Z
    INC D                           ; ! means single precision
    CP $21
    RET Z
    LD D,$08                        ; # means double precision
    CP $23
    RET Z
    LD A,B                          ; No suffix: the type set by DEFINT and friends
    SUB $41                         ; Index the table by the first letter
    AND $7F
    LD E,A
    LD D,$00
    PUSH HL
    LD HL,DEFTBL
    ADD HL,DE
    LD D,[HL]                       ; D = the default type for that letter
    POP HL
    DEC HL                          ; Back up, no suffix character was used
    RET

;; Records the variable's type and sends a name followed by ( to the array code, else searches
;; the simple variables.
HAVTYP:
    LD A,D
    LD [VALTYP],A                   ; The expression takes the variable's type
    RST $10                         ; Move past the name
    LD A,[SUBFLG]                   ; SUBFLG set: only a simple variable is wanted
    OR A
    JP NZ,NOARYS
    LD A,[HL]                       ; A parenthesis after the name means an array
    SUB $28
    JP Z,ISARY
NOARYS:
    XOR A                           ; Clear the flag for the next lookup
    LD [SUBFLG],A
    PUSH HL                         ; Save the text pointer
    PUSH DE                         ; Keep the wanted type in D
    LD HL,[VARTAB]                  ; HL = start of the simple variables
;; Searches the simple variable table for an entry with the type and name being looked up.
LOPFND:
    EX DE,HL                        ; DE = current entry
    LD HL,[ARYTAB]                  ; HL = end of the simple variables
    RST $18                         ; Reached the end of the table?
    POP HL                          ; H = the wanted type
    JR Z,NOTFNS                     ; Not found
    LD A,[DE]                       ; A = entry type, which is also its value size
    LD L,A                          ; L = value size for skipping the entry
    CP H                            ; Same type?
    INC DE
    JR NZ,NOTIT1
    LD A,[DE]                       ; Same second character?
    CP C
    JR NZ,NOTIT1
    INC DE
    LD A,[DE]                       ; Same first character?
    CP B
    JP Z,FINPTR                     ; Found it
    .byte $3E                       ; LD A,n: skips the next instruction
NOTIT1:
    INC DE                          ; Skip the remaining name bytes
    INC DE
    PUSH HL                         ; Keep the wanted type for the next entry
    LD H,$00                        ; HL = value size
    ADD HL,DE                       ; Step DE past the value to the next entry
    JR LOPFND
;; Handles a simple variable not found: returns zero for VARPTR or a read, else adds a zeroed entry.
NOTFNS:
    LD A,H                          ; A = the wanted type
    POP HL                          ; HL = text pointer
    EX [SP],HL                      ; HL = caller's return address
    PUSH AF                         ; Keep the type
    PUSH DE                         ; Keep the table end where the entry would go
    LD DE,$24F1                     ; Called from VARPTR?
    RST $18
    JR Z,VARNOT                     ; VARPTR of an unknown variable
    LD DE,$2543                     ; Called from ISVAR to read the value?
    RST $18
    POP DE                          ; DE = table end
    JR Z,FINZER                     ; Reading an unset variable just gives zero
    POP AF                          ; A = the type
    EX [SP],HL                      ; Put the return address back, HL = text pointer
    PUSH HL
    PUSH BC                         ; Keep the name
    LD C,A                          ; BC = value size
    LD B,$00
    PUSH BC                         ; Kept to store the type later
    INC BC                          ; Add the type byte and two name bytes
    INC BC
    INC BC
    LD HL,[STREND]                  ; HL = end of the arrays
    PUSH HL
    ADD HL,BC                       ; HL = new end after making room
    POP BC                          ; BC = old end
    PUSH HL
    CALL BLTU                       ; Move the arrays up to open a gap
    POP HL
    LD [STREND],HL                  ; Record the new end of the arrays
    LD H,B                          ; HL = the new start of the arrays
    LD L,C
    LD [ARYTAB],HL                  ; The arrays now start above the new entry
ZEROER:
    DEC HL                          ; Zero the new entry from the top down
    LD [HL],$00
    RST $18                         ; Stop at the start of the entry
    JR NZ,ZEROER
    POP DE                          ; E = the type
    LD [HL],E                       ; Store the type in the entry's first byte
    INC HL
    POP DE                          ; DE = the name
    LD [HL],E                       ; Second name character, then the first
    INC HL
    LD [HL],D
    EX DE,HL                        ; DE = entry's last name byte
;; Returns the address of the found variable's value in DE.
FINPTR:
    INC DE                          ; DE = address of the value just past the name
    POP HL                          ; HL = text pointer
    RET
;; Returns DE = 0 when VARPTR names a variable that doesn't exist.
VARNOT:
    LD D,A                          ; DE = 0 tells VARPTR the variable does not exist
    LD E,A
    POP AF                          ; Discard the saved table end and type
    POP AF
    EX [SP],HL                      ; Restore the return address, HL = text pointer
    RET
;; Returns zero, or an empty string, in the FAC for a variable that doesn't exist yet.
FINZER:
    LD [FAC],A                      ; Zero exponent makes the FAC hold zero
    POP BC                          ; Discard the saved type
    LD H,A
    LD L,A
    LD [FACLO],HL                   ; Clear the integer and descriptor part too
    RST $20                         ; Only a string needs more
    JR NZ,POPHR2
    LD HL,$1928                     ; Point at a zero byte, making an empty string
    LD [FACLO],HL
POPHR2:
    POP HL
    RET
;; Evaluates an array reference's subscripts, then looks the array up in the array table.
ISARY:
    PUSH HL                         ; Save the text pointer
    LD HL,[DIMFLG]                  ; Fetch DIMFLG, the subscripts may change it
    EX [SP],HL                      ; Stack it, HL = text pointer
    LD D,A                          ; D = subscript count, starting at zero
INDLOP:
    PUSH DE                         ; Keep the count
    PUSH BC                         ; Keep the name
    CALL INTIDX                     ; DE = this subscript's value
    POP BC
    POP AF                          ; A = subscript count so far
    EX DE,HL                        ; HL = subscript, DE = text pointer
    EX [SP],HL                      ; Put the subscript under the saved DIMFLG
    PUSH HL
    EX DE,HL
    INC A                           ; Count it
    LD D,A
    LD A,[HL]                       ; A comma means another subscript
    CP $2C
    JR Z,INDLOP
    RST $08
    .byte ')'

SUBSOK:
    LD [TEMP2],HL                   ; Keep the text pointer after the parenthesis
    POP HL
    LD [DIMFLG],HL                  ; Restore DIMFLG
    PUSH DE                         ; Keep the subscript count
    LD HL,[ARYTAB]                  ; HL = start of the arrays
    .byte $3E
;; Searches the array table for the array, giving ?DD if DIM finds it and ?BS for the wrong number
;; of subscripts.
LOPFDA:
    ADD HL,DE
    EX DE,HL                        ; Point DE at the end of the arrays
    LD HL,[STREND]
    EX DE,HL
    RST $18                         ; Reached the end?
    LD A,[VALTYP]                   ; A = the wanted type
    JR Z,NOTFDD                     ; No such array yet
    CP [HL]                         ; Does the type match?
    INC HL
    JR NZ,NMARY2
    LD A,[HL]                       ; Does the second character match?
    CP C
    INC HL
    JR NZ,NMARY1
    LD A,[HL]                       ; Does the first character match?
    CP B
    .byte $3E

NMARY2:
    INC HL
NMARY1:
    INC HL
    LD E,[HL]                       ; DE = size of this array entry
    INC HL
    LD D,[HL]
    INC HL
    JR NZ,LOPFDA                    ; Not this one: skip to the next array
    LD A,[DIMFLG]                   ; Found: DIM may not create it again
    OR A
    LD E,ERR_DD                     ; Array already exists: Redimensioned array
    JP NZ,ERROR
    POP AF                          ; A = subscript count given
    SUB [HL]                        ; Must match the array's dimension count
    JP Z,GETDEF                     ; Right count: find the element
;; Raises ?BS ERROR, a subscript out of range.
BSERR:
    LD E,ERR_BS
    JP ERROR
;; Creates a new array at the end of the array table, 11 elements per dimension unless DIMmed,
;; and zeroes it.
NOTFDD:
    LD [HL],A                       ; Store the type
    INC HL
    LD E,A                          ; DE = element size
    LD D,$00
    POP AF                          ; A = subscript count
    LD [HL],C                       ; Store the name
    INC HL
    LD [HL],B
    INC HL
    LD C,A                          ; C = number of dimensions
    CALL GETSTK                     ; Check the subscripts on the stack fit
    INC HL                          ; Skip the entry size, filled in later
    INC HL
    LD [TEMP3],HL                   ; Remember where the dimension count goes
    LD [HL],C                       ; Store the dimension count
    INC HL
    LD A,[DIMFLG]                   ; Carry if DIM is creating it
    RLA
    LD A,C                          ; A = dimensions left to store
LOPPTA:
    LD BC,$000B                     ; Undimensioned arrays get 11 elements, 0 to 10
    JR NC,NOTDIM
    POP BC                          ; DIM: BC = the subscript given
    INC BC                          ; Plus one for element zero
NOTDIM:
    LD [HL],C                       ; Store this dimension's size
    INC HL
    LD [HL],B
    INC HL
    PUSH AF                         ; Keep the count and the DIM carry
    CALL UMULT                      ; Multiply the total size by this dimension
    POP AF
    DEC A
    JR NZ,LOPPTA
    PUSH AF                         ; Keep the DIM carry for the end
    LD B,D                          ; BC = total data size in bytes
    LD C,E
    EX DE,HL                        ; DE = start of the data
    ADD HL,DE                       ; HL = end of the data
    JR C,BSERR                      ; Beyond 64K: Bad subscript
    CALL REASON                     ; Make sure memory is free up to there
    LD [STREND],HL                  ; The array table now ends after it
ZERITA:
    DEC HL                          ; Zero the elements from the top down
    LD [HL],$00
    RST $18                         ; Down to the start of the data
    JR NZ,ZERITA
    INC BC                          ; Include the dimension count byte
    LD D,A
    LD HL,[TEMP3]                   ; HL = address of the dimension count
    LD E,[HL]                       ; E = number of dimensions
    EX DE,HL
    ADD HL,HL                       ; Two bytes per dimension, plus the data
    ADD HL,BC
    EX DE,HL                        ; DE = the entry's size
    DEC HL                          ; Back to the size word
    DEC HL
    LD [HL],E                       ; Store the size for skipping this entry
    INC HL
    LD [HL],D
    INC HL                          ; Point at the dimension count
    POP AF
    JR C,FINNOW                     ; DIM only creates the array
;; Works out an array element's address from its subscripts, giving ?BS if one is out of range.
GETDEF:
    LD B,A                          ; BC = element offset, starting at zero
    LD C,A
    LD A,[HL]                       ; A = number of dimensions
    INC HL
    .byte $16
INLPNM:
    POP HL                          ; HL = pointer to the next dimension size
    LD E,[HL]                       ; DE = this dimension's size
    INC HL
    LD D,[HL]
    INC HL
    EX [SP],HL                      ; Keep the pointer, HL = this subscript
    PUSH AF                         ; Keep the dimensions left
    RST $18                         ; Is the subscript below the size?
    JP NC,BSERR                     ; Subscript too large: Bad subscript
    CALL UMULT                      ; Scale the offset so far by this dimension
    ADD HL,DE                       ; Then add this subscript
    POP AF
    DEC A
    LD B,H                          ; BC = updated element offset
    LD C,L
    JR NZ,INLPNM
    LD A,[VALTYP]                   ; Turn the offset into bytes by element size
    LD B,H
    LD C,L
    ADD HL,HL                       ; Two bytes for integers
    SUB $04                         ; Single and double need more doubling
    JR C,SMLVAL
    ADD HL,HL                       ; Four bytes for singles
    JR Z,DONMUL
    ADD HL,HL                       ; Eight bytes for doubles
SMLVAL:
    OR A                            ; Odd parity here means no extra element byte
    JP PO,DONMUL
    ADD HL,BC                       ; Strings use three bytes per element
DONMUL:
    POP BC                          ; BC = start of the data
    ADD HL,BC
    EX DE,HL                        ; DE = the element's address
FINNOW:
    LD HL,[TEMP2]                   ; HL = text after the subscripts
    RET
;; Runs MEM, returning the number of free bytes of memory in the FAC.
MEM:
    XOR A                           ; Mark the value numeric so FRE counts all memory
    PUSH HL
    LD [VALTYP],A
    CALL FN_FRE
    POP HL
    RST $10                         ; Re-fetch the character after MEM
    RET
;; Runs FRE: free string space after compacting for a string argument, else the free bytes in memory.
FN_FRE:
    LD HL,[STREND]                  ; DE = end of the arrays
    EX DE,HL
    LD HL,RESET                     ; HL = stack pointer
    ADD HL,SP
    RST $20                         ; A string argument asks for free string space
    JR NZ,GIVDBL
    CALL FREFAC                     ; Release the argument string
    CALL GARBAG                     ; Compact string space first
    LD HL,[STKTOP]                  ; DE = bottom of string space
    EX DE,HL
    LD HL,[FRETOP]                  ; HL = lowest string in use
;; Returns HL - DE as an unsigned number in the FAC, through <INEG2>.
GIVDBL:
    LD A,L                          ; HL = gap between the two pointers
    SUB E
    LD L,A
    LD A,H
    SBC A,D
    LD H,A
    JP INEG2
;; Runs POS, returning the current print column as an integer.
FN_POS:
    LD A,[TTYPOS]                   ; A = current print column

;; Returns the unsigned byte in A as an integer in the FAC.
;; In:    A = value
SNGFLT:
    LD L,A
    XOR A                           ; High byte zero

GIVINT:
    LD H,A
    JP MAKINT
;; Runs USR, calling the machine-language routine whose address is in USRTAB with the argument in the FAC.
USRFN:
    CALL HOOK_USR
    RST $10                         ; Step to the opening parenthesis
    CALL PARCHK                     ; Evaluate the argument into the FAC
    PUSH HL                         ; Save the text pointer
    LD HL,$0890                     ; User routine returns into $0890, which cleans up
    PUSH HL
    LD A,[VALTYP]                   ; Keep the argument's type
    PUSH AF
    CP $03                          ; A string argument is released first
    CALL Z,FREFAC
    POP AF                          ; A = argument type for the routine
    EX DE,HL                        ; DE = the string descriptor, if any
    LD HL,[USRTAB]                  ; HL = the routine's address from USRTAB
    JP [HL]

;; Converts the accumulator to the type in A (VALTYP-style) through the conversion table at $18A1.
DOCNVF:
    PUSH HL
    AND $07                         ; A = type code 2, 3, 4 or 8, mod 8 for 8
    LD HL,$18A1                     ; HL = the conversion routine table
    LD C,A
    LD B,$00
    ADD HL,BC                       ; Index the table by the type code
    CALL DISPAT
    POP HL
    RET

;; Gives an ID error if BASIC is in direct mode (CURLIN $FFFF); otherwise returns.
ERRDIR:
    PUSH HL
    LD HL,[CURLIN]                  ; HL = current line number
    INC HL                          ; $FFFF becomes zero in direct mode
    LD A,H
    OR L
    POP HL
    RET NZ                          ; Running a program: allowed
;; Raises ?ID ERROR, a statement not allowed in direct mode.
IDERR:
    LD E,ERR_ID                     ; Direct mode: Illegal direct
    JP ERROR
;; Runs STR$, converting the number in the FAC to text and making it a temporary string.
FN_STR:
    CALL FOUT                       ; Convert the number to text
    CALL STRLIT                     ; Make a temporary string of the text
    CALL FREFAC                     ; Release the temporary from the descriptor stack
    LD BC,$2A2B                     ; Return through $2A2B to push the new string
    PUSH BC

;; Copies the string of descriptor HL into new string space; DE points at the new descriptor.
STRCPY:
    LD A,[HL]                       ; A = string length
    INC HL
    PUSH HL                         ; Keep the descriptor pointer
    CALL GETSPA                     ; Get string space for the copy
    POP HL
    LD C,[HL]                       ; BC = address of the original text
    INC HL
    LD B,[HL]
    CALL STRAD2                     ; Fill in the new descriptor
    PUSH HL                         ; Keep the descriptor address
    LD L,A                          ; L = number of bytes to copy
    CALL MOVSTR                     ; Copy the text into the new space
    POP DE                          ; DE = the new descriptor
    RET

;; Allocates A bytes of string space and builds a descriptor for them in DSCTMP.
;; In:    A = the string's length
;; Out:   DE = the allocated space, HL = DSCTMP
STRINI:
    CALL GETSPA

;; Writes the length in A and address in DE into the descriptor at DSCTMP.
;; In:    A = length, DE = string address
;; Out:   HL = DSCTMP
STRAD2:
    LD HL,DSCTMP                    ; The work descriptor for a new string

STRAD1:
    PUSH HL
    LD [HL],A                       ; Store the length

PUTDEI:
    INC HL
    LD [HL],E                       ; Then the address
    INC HL
    LD [HL],D
    POP HL
    RET

;; Builds a temporary string from the text at HL, ending at a quotation mark or zero.
STRLIT:
    DEC HL

;; Builds a temporary string from the literal after HL, ending at a quotation mark or zero.
STRLTI:
    LD B,$22                        ; A quoted literal ends at the closing quote

STRLT3:
    LD D,B                          ; Second terminator the same as the first

;; Builds a temporary string from the text after HL, ending at zero or the delimiters in B and D.
STRLT2:
    PUSH HL                         ; Keep the start for building the descriptor
    LD C,$FF                        ; C counts characters, starting at -1

;; Enters STRLT2's scan loop, counting characters in C until zero or the delimiter in B or D.
STRGET:
    INC HL
    LD A,[HL]
    INC C
    OR A
    JR Z,STRFIN                     ; End of the line ends the string
    CP D                            ; Either terminator ends the string
    JR Z,STRFIN
    CP B
    JR NZ,STRGET

;; Ends a literal scan: skips a closing quotation mark, then makes the counted text a temporary string.
STRFIN:
    CP $22                          ; Step past a closing quote
    CALL Z,CHRGTR
    EX [SP],HL                      ; HL = start, text pointer saved on the stack
    INC HL                          ; First character of the string
    EX DE,HL                        ; DE = string address
    LD A,C                          ; A = its length
    CALL STRAD2

;; Copies the descriptor in DSCTMP to a new temporary and points FAC at it as a string result.
;; Gives an ST error when the temporary descriptors are all in use.
PUTNEW:
    LD DE,DSCTMP
    LD A,$D5                        ; (A is reloaded below, this value goes unused)
    LD HL,[TEMPPT]                  ; HL = next free temporary descriptor
    LD [FACLO],HL                   ; The FAC refers to that descriptor
    LD A,$03                        ; The result is a string
    LD [VALTYP],A
    CALL VMOVE                      ; Copy DSCTMP into the temporary
    LD DE,FRETOP                    ; The temporaries end where FRETOP is stored
    RST $18                         ; Has the last temporary been used?
    LD [TEMPPT],HL                  ; Advance to the next free temporary
    POP HL                          ; HL = text pointer
    LD A,[HL]                       ; A = current character
    RET NZ
    LD E,ERR_ST                     ; Too many temporaries: String formula too complex
    JP ERROR
;; Prints the string that starts at HL+1, ending at zero or a quotation mark.
STROUI:
    INC HL

;; Prints the string at HL through a zero or a quotation mark.
STROUT:
    CALL STRLIT

;; Prints the string in FAC, freeing it if it is a temporary.
STRPRT:
    CALL FREFAC                     ; Release the string, HL = its descriptor
    CALL GETBCD                     ; D = length, BC = address
    INC D                           ; Bias the count for the decrement below
;; Enters STRPRT's loop, printing D-1 characters from BC.
STRPR2:
    DEC D
    RET Z
    LD A,[BC]                       ; Next character
    CALL OUTDO
    CP $0D                          ; After a carriage return the column restarts
    CALL Z,CRFIN
    INC BC
    JR STRPR2

;; Allocates A bytes of string space, collecting garbage or giving OS error; DE points at it.
GETSPA:
    OR A                            ; NZ first time, a retry after collecting enters with Z
    LD C,$F1                        ; $F1 here is the POP AF the retry returns to
    PUSH AF                         ; Keep the length and the collected flag
    LD HL,[STKTOP]                  ; DE = bottom of string space
    EX DE,HL
    LD HL,[FRETOP]                  ; HL = lowest string in use
    CPL                             ; BC = -(length + 1)
    LD C,A
    LD B,$FF
    ADD HL,BC
    INC HL                          ; HL = proposed new bottom of strings
    RST $18                         ; Would it go below string space?
    JR C,GETSPA_2
    LD [FRETOP],HL                  ; Claim the space
    INC HL
    EX DE,HL                        ; DE = start of the new space

PPSWRT:
    POP AF
    RET

;; Handles a string-space shortage: gives OS error if garbage was already collected,
;; otherwise collects it and retries the allocation.
GETSPA_2:
    POP AF
    LD E,ERR_OS                     ; Already collected and still short: Out of string space
    JP Z,ERROR
    CP A                            ; Mark that garbage has now been collected
    PUSH AF
    LD BC,$28C1                     ; Then retry the allocation from POP AF
    PUSH BC

;; Compacts string space, moving every live string up to the top of memory.
GARBAG:
    LD HL,[MEMSIZ]                  ; Everything starts out free up to the top of memory

FNDVAR:
    LD [FRETOP],HL
    LD HL,RESET                     ; Zero: no strings found yet this pass
    PUSH HL
    LD HL,[STKTOP]                  ; Strings below string space, in the program, are left alone
    PUSH HL
    LD HL,$40B5                     ; HL = first temporary string descriptor

;; Enters the garbage collector's scan of the temporary string descriptors, then the simple variables.
TVAR:
    EX DE,HL
    LD HL,[TEMPPT]                  ; DE = next free temporary descriptor
    EX DE,HL
    RST $18                         ; All temporaries checked?
    LD BC,$28F7                     ; Come back to TVAR after each one
    JP NZ,DVAR2                     ; Check this temporary's string

;; Enters the garbage collector's scan of the simple variables, checking each string one.
SVARS:
    LD HL,[VARTAB]                  ; HL = start of the simple variables

SVAR:
    EX DE,HL
    LD HL,[ARYTAB]                  ; DE = start of the arrays, ending the simple ones
    EX DE,HL
    RST $18                         ; All simple variables checked?
    JR Z,ARYVAR                     ; Go on to the arrays
    LD A,[HL]                       ; A = the variable's type
    INC HL                          ; Step past the type and name to the value
    INC HL
    INC HL
    CP $03                          ; Only strings matter
    JR NZ,SKPVAR
    CALL GC_CHECK_STRING
    XOR A

SKPVAR:
    LD E,A                          ; DE = bytes of value to skip, zero once a string is checked
    LD D,$00
    ADD HL,DE                       ; Step past the value to the next simple variable
    JR SVAR

ARYVA2:
    POP BC

;; Enters the garbage collector's scan of the arrays, checking each element of string arrays.
ARYVAR:
    EX DE,HL
    LD HL,[STREND]
    EX DE,HL
    RST $18
    JP Z,GRBPAS                     ; All arrays scanned, finish this pass
    LD A,[HL]                       ; A = the array's type code
    INC HL
    CALL MOVRM                      ; DE = array name, BC = bytes to the next array
    PUSH HL                         ; Save the pointer to the dimension count
    ADD HL,BC                       ; HL = start of the next array
    CP $03                          ; Only string arrays hold descriptors to check
    JR NZ,ARYVA2
    LD [TEMP3],HL                   ; TEMP3 = end of this string array
    POP HL
    LD C,[HL]                       ; C = number of dimensions
    LD B,$00
    ADD HL,BC                       ; Skip two bytes per dimension size
    ADD HL,BC
    INC HL                          ; and the count, reaching the first element

ARYSTR:
    EX DE,HL
    LD HL,[TEMP3]
    EX DE,HL
    RST $18
    JR Z,ARYVAR                     ; Elements done, go on to the next array
    LD BC,$293F                     ; Have GC_CHECK_STRING return to ARYSTR

DVAR2:
    PUSH BC

;; Checks the string descriptor at HL during garbage collection, keeping the highest one found.
GC_CHECK_STRING:
    XOR A
    OR [HL]                         ; A = string length
    INC HL
    LD E,[HL]                       ; DE = the string's address
    INC HL
    LD D,[HL]
    INC HL
    RET Z                           ; An empty string owns no space
    LD B,H                          ; Keep the descriptor pointer in BC
    LD C,L
    LD HL,[FRETOP]                  ; Is the string below FRETOP?
    RST $18
    LD H,B
    LD L,C
    RET C                           ; Already packed above FRETOP, ignore it
    POP HL                          ; Lift off the return address to reach the best candidate
    EX [SP],HL
    RST $18                         ; Compare the highest address so far with this string's
    EX [SP],HL
    PUSH HL
    LD H,B
    LD L,C
    RET NC                          ; Not higher than the best so far
    POP BC                          ; New highest string: pop the return address
    POP AF                          ; and discard the old candidate's address
    POP AF                          ; and its descriptor pointer
    PUSH HL                         ; Record this descriptor pointer
    PUSH DE                         ; and this string's address as the new best
    PUSH BC
    RET

;; Ends a garbage collection pass: moves the highest string found up to FRETOP and starts another pass,
;; or returns when no string remains to move.
GRBPAS:
    POP DE                          ; DE = address of the highest string found
    POP HL                          ; HL = just past its descriptor, zero if none was found
    LD A,L
    OR H
    RET Z                           ; No string left to move, collection is done
    DEC HL
    LD B,[HL]                       ; BC = the string's address from the descriptor
    DEC HL
    LD C,[HL]
    PUSH HL                         ; Save the pointer to the descriptor's address field
    DEC HL
    LD L,[HL]                       ; L = the string's length
    LD H,$00
    ADD HL,BC                       ; HL = byte after the string's end
    LD D,B                          ; DE = start of the string to move
    LD E,C
    DEC HL
    LD B,H                          ; BC = the string's last byte
    LD C,L
    LD HL,[FRETOP]                  ; Move the string to the top of free string space
    CALL BLTUC
    POP HL
    LD [HL],C                       ; Point the descriptor at the string's new place
    INC HL
    LD [HL],B
    LD L,C
    LD H,B
    DEC HL                          ; The byte below the moved string is the new FRETOP
    JP FNDVAR                       ; Start the next pass

;; Concatenates the string in FAC with the string expression after the plus sign at HL.
;; Gives an LS error when the result would exceed 255 characters.
CAT:
    PUSH BC
    PUSH HL
    LD HL,[FACLO]                   ; Stack the first operand's descriptor
    EX [SP],HL
    CALL EVAL                       ; Evaluate the second operand
    EX [SP],HL                      ; Stack the text pointer, HL = first operand's descriptor
    CALL CHKSTR                     ; The second operand must be a string too
    LD A,[HL]                       ; A = length of the first string
    PUSH HL
    LD HL,[FACLO]
    PUSH HL
    ADD A,[HL]                      ; A = combined length, carry if over 255
LSERR:
    LD E,ERR_LS
    JP C,ERROR
    CALL STRINI                     ; Reserve space for the joined string
    POP DE                          ; DE = second string's descriptor
    CALL FRETMP                     ; Free the second string if it is a temporary
    EX [SP],HL                      ; Stack the second descriptor, HL = the first
    CALL FRETM2                     ; Free the first string if it is a temporary
    PUSH HL
    LD HL,[DSCTMP_PTR]              ; HL = where the result's characters go
    EX DE,HL
    CALL MOVINS                     ; Copy the first string
    CALL MOVINS                     ; then append the second
    LD HL,$2349                     ; Resume the expression evaluator at TSTOP afterward
    EX [SP],HL
    PUSH HL
    JP PUTNEW

;; Copies the string of the descriptor on the stack to DE.
MOVINS:
    POP HL                          ; HL = return address
    EX [SP],HL                      ; HL = the descriptor, return address back on the stack
    LD A,[HL]                       ; A = length
    INC HL
    LD C,[HL]                       ; BC = the string's address
    INC HL
    LD B,[HL]
    LD L,A                          ; L = count of bytes to copy

;; Copies L bytes from BC to DE.
MOVSTR:
    INC L                           ; Offset the DEC L that starts the loop

;; Enters MOVSTR's copy loop: copies bytes from BC to DE, decrementing L, until L is zero.
MOVLP:
    DEC L
    RET Z                           ; All bytes copied
    LD A,[BC]
    LD [DE],A
    INC BC
    INC DE
    JR MOVLP

;; Checks the accumulator holds a string and frees it if temporary; HL points at its descriptor.
FRESTR:
    CALL CHKSTR

;; Frees the string in FAC if it is a temporary.
;; Out:   HL = its descriptor
FREFAC:
    LD HL,[FACLO]

;; Frees the temporary string whose descriptor HL points at; returns the descriptor in HL.
FRETM2:
    EX DE,HL

;; Frees the temporary string whose descriptor DE points at, reclaiming its space if it is lowest.
;; In:    DE = the descriptor
;; Out:   HL = the descriptor
FRETMP:
    CALL FRETMS                     ; Is DE the most recent temporary?
    EX DE,HL
    RET NZ                          ; Not the last temporary, no space to reclaim
    PUSH DE
    LD D,B                          ; DE = the string's address
    LD E,C
    DEC DE                          ; DE = the byte below it
    LD C,[HL]                       ; C = the string's length
    LD HL,[FRETOP]
    RST $18                         ; Does the string sit just above FRETOP?
    JR NZ,NOTLST                    ; Not the lowest string, its space stays in use
    LD B,A                          ; A is zero after the match, so BC = the length
    ADD HL,BC
    LD [FRETOP],HL                  ; Give the string's bytes back to free space
;; Exits FRETMP without reclaiming string space, restoring HL to the descriptor.
NOTLST:
    POP HL
    RET

;; Releases the descriptor at DE if it is the most recent temporary.
;; In:    DE = the descriptor
;; Out:   zero = it was released, BC = the last temporary's string address
FRETMS:
    LD HL,[TEMPPT]                  ; HL = just past the last temporary descriptor
    DEC HL                          ; Back up to it, BC = its string address
    LD B,[HL]
    DEC HL
    LD C,[HL]
    DEC HL
    RST $18                         ; Is DE that descriptor?
    RET NZ
    LD [TEMPPT],HL                  ; Pop it off the temporary descriptor stack
    RET
;; Returns the length of the string argument for LEN.
FN_LEN:
    LD BC,SNGFLT                    ; Return through SNGFLT to float the result in A
    PUSH BC

;; Frees the string argument and returns its length in A, with Z set when it is empty.
LEN1:
    CALL FRESTR
    XOR A                           ; D = 0 so DE can hold the length
    LD D,A
    LD A,[HL]                       ; A = the length
    OR A
    RET
;; Returns the code of the string argument's first character for ASC; FC error if it is empty.
FN_ASC:
    LD BC,SNGFLT                    ; Return through SNGFLT to float the code in A
    PUSH BC

;; Returns the first character of the string argument in A; FC error if it is empty.
ASC2:
    CALL LEN1
    JP Z,FCERR                      ; An empty string gives FC error
    INC HL
    LD E,[HL]                       ; DE = the string's address
    INC HL
    LD D,[HL]
    LD A,[DE]                       ; A = its first character
    RET
;; Returns a one-character string of the code argument for CHR$.
FN_CHR:
    LD A,$01                        ; Reserve a one-character string
    CALL STRINI
    CALL CONINT                     ; E = the character code

;; Stores E as the character of the new one-character string and returns it as a temporary.
SETSTR:
    LD HL,[DSCTMP_PTR]              ; HL = the new string's space
    LD [HL],E
;; Drops a stacked value and returns the string in DSCTMP as a temporary result.
FINBCK:
    POP BC                          ; Discard the value under the return address
    JP PUTNEW
;; Parses STRING$(count, character) and returns the repeated-character string.
STRNG:
    RST $10                         ; Skip the STRING$ token
    RST $08
    .byte '('
    CALL GETBYT                     ; E = the repeat count
    PUSH DE                         ; Save the count
    RST $08
    .byte ','
    CALL FRMEVL                     ; Evaluate the character, a number or a string
    RST $08
    .byte ')'
    EX [SP],HL                      ; Stack the text pointer, HL = the count
    PUSH HL
    RST $20                         ; A string argument supplies its first character
    JR Z,STRSTR
    CALL CONINT                     ; A numeric argument is the character code
    JR CALSPA
;; Takes STRING$'s character from the first character of its string argument.
STRSTR:
    CALL ASC2
;; Pops the count into E and builds a string of E copies of the character in A.
CALSPA:
    POP DE                          ; E = the repeat count
    PUSH AF                         ; Save the character

SPACE2:
    PUSH AF
    LD A,E
    CALL STRINI                     ; Make a string of E characters
    LD E,A                          ; E = the length to fill
    POP AF
    INC E                           ; A zero count gives an empty string
    DEC E
    JR Z,FINBCK
    LD HL,[DSCTMP_PTR]              ; HL = the new string's space
;; Enters the fill loop of STRING$, storing A at HL for each of the E characters.
SPLP:
    LD [HL],A
    INC HL
    DEC E
    JR NZ,SPLP
    JR FINBCK
;; Returns the leftmost characters of a string for LEFT$.
FN_LEFT:
    CALL PREAM
    XOR A                           ; LEFT$ starts at offset zero
;; Enters LEFT$'s substring code with the start offset in A and the count in B.
LEFT3:
    EX [SP],HL                      ; Stack the text pointer, HL = the descriptor
    LD C,A                          ; C = the start offset
    .byte $3E

;; Returns up to B characters of the string at descriptor HL, from offset C, for PRINT USING.
;; In:    HL = the descriptor, B = count, C = start offset
LEFTUS:
    PUSH HL

;; Makes a temporary of up to B characters from offset C of the string whose descriptor HL points at.
LEFT2:
    PUSH HL
    LD A,[HL]                       ; A = the string's length
    CP B
    JR C,ALLSTR                     ; Length below the count, take the whole string
    LD A,B                          ; A = count of characters to take
    .byte $11

;; Takes the whole string for a substring whose count is not less than the length.
ALLSTR:
    LD C,$00
    PUSH BC                         ; Save the offset and count
    CALL GETSPA                     ; Reserve A bytes for the result
    POP BC
    POP HL
    PUSH HL                         ; Keep the source descriptor for FRETMP
    INC HL                          ; HL = the source string's address
    LD B,[HL]
    INC HL
    LD H,[HL]
    LD L,B
    LD B,$00                        ; BC = the start offset
    ADD HL,BC                       ; Advance to the first character to copy
    LD B,H                          ; BC = the copy source
    LD C,L
    CALL STRAD2                     ; Set up the result's descriptor
    LD L,A                          ; L = count to copy
    CALL MOVSTR
    POP DE                          ; DE = source descriptor, freed if temporary
    CALL FRETMP
    JP PUTNEW
;; Returns the rightmost characters of a string for RIGHT$.
FN_RIGHT:
    CALL PREAM
    POP DE                          ; DE = the string's descriptor
    PUSH DE
    LD A,[DE]                       ; A = its length
    SUB B                           ; Start offset = length minus count
    JR LEFT3
;; Returns a substring from a given position, with an optional length, for the MID$ function.
;; Gives an FC error when the position is zero.
FN_MID:
    EX DE,HL                        ; HL = the text pointer
    LD A,[HL]                       ; A = the character after the start position
    CALL PREAM2
    INC B                           ; A start position of zero gives FC error
    DEC B
    JP Z,FCERR
    PUSH BC                         ; Save the start position
    LD E,$FF                        ; Default length 255 takes the rest of the string
    CP $29                          ; A closing parenthesis means no length argument
    JR Z,MID2
    RST $08
    .byte ','
    CALL GETBYT                     ; E = the requested length
;; Finishes MID$'s arguments and computes its offset and count, returning into LEFT2's code.
MID2:
    RST $08
    .byte ')'
    POP AF                          ; A = the start position
    EX [SP],HL                      ; Stack the text pointer, HL = the descriptor
    LD BC,$2A69                     ; Return into LEFT2 to build the substring
    PUSH BC
    DEC A                           ; Make the position a zero-based offset
    CP [HL]                         ; Compare it with the string's length
    LD B,$00                        ; B = 0 gives an empty result
    RET NC                          ; Start beyond the end yields an empty string
    LD C,A                          ; C = the start offset
    LD A,[HL]
    SUB C                           ; A = characters from the offset to the end
    CP E                            ; Fewer left than requested?
    LD B,A
    RET C                           ; Then take all that remain
    LD B,E                          ; Otherwise take the requested length
    RET
;; Converts the leading number in the string argument to a value for VAL.
FN_VAL:
    CALL LEN1
    JP Z,SNGFLT                     ; VAL of an empty string is zero
    LD E,A                          ; DE = the length
    INC HL                          ; HL = the string's address
    LD A,[HL]
    INC HL
    LD H,[HL]
    LD L,A
    PUSH HL                         ; Save the string's start
    ADD HL,DE                       ; HL = byte just after the string
    LD B,[HL]                       ; Save that byte
    LD [HL],D                       ; Mark the string's end with zero for the number scanner
    EX [SP],HL                      ; HL = string start, end pointer stacked
    PUSH BC
    LD A,[HL]
    CALL FINDBL                     ; Convert the leading number into FAC
    POP BC
    POP HL                          ; HL = byte after the string
    LD [HL],B                       ; Restore the byte the zero replaced
    RET

;; Checks the closing parenthesis of LEFT$ or RIGHT$ and pops the descriptor and count (B).
PREAM:
    EX DE,HL                        ; HL = the text pointer
    RST $08
    .byte ')'

;; Pops a string function's descriptor (DE) and byte argument (B) from under the return address.
PREAM2:
    POP BC                          ; BC = the return address
    POP DE                          ; DE = the string's descriptor
    PUSH BC
    LD B,E                          ; B = the byte argument
    RET

;; Passes a MID$ assignment to Disk BASIC's hook; SN error for any other token in A.
ISMID:
    CP $7A
    JP NZ,SNERR
    JP HOOK_MID_STATEMENT           ; MID$ on the left side is left to Disk BASIC
;; Reads the port given by the argument for INP and returns the byte.
FN_INP:
    CALL CONINT
    LD [INP_PORT],A                 ; Patch the port into the IN instruction stub
    CALL STAINP                     ; A = the byte read from the port
    JP SNGFLT
;; Executes OUT, writing a byte value to a port.
ST_OUT:
    CALL SETIO
    JP OUTWRD                       ; Write the byte through the OUT stub

;; Skips to the next character and evaluates an integer expression into DE.
;; Out:   DE = the value, A = D
GETINT:
    RST $10

;; Evaluates the expression at HL as an integer in DE; sign flag from the high byte.
GETIN2:
    CALL FRMEVL

;; Converts the accumulator to an integer in DE, keeping HL; A and flags from D.
INTFR2:
    PUSH HL
    CALL FRCINT                     ; HL = the integer value
    EX DE,HL
    POP HL
    LD A,D                          ; Flags from the high byte for range checks
    OR A
    RET

;; Reads a port number and, after a comma, a byte value for OUT; stores the port for the I/O stubs.
SETIO:
    CALL GETBYT
    LD [INP_PORT],A                 ; Patch the port into both I/O stubs
    LD [OUT_PORT],A
    RST $08
    .byte ','
    JR GETBYT                       ; Then evaluate the byte to write

;; Skips to the next character and evaluates a byte expression into A and E.
GTBYTC:
    RST $10

;; Evaluates the expression at HL as a byte in A and E; FC error outside 0-255.
GETBYT:
    CALL FRMEVL

;; Converts FAC to a byte in A and E and rereads the current character; FC error outside 0-255.
CONINT:
    CALL INTFR2
    JP NZ,FCERR                     ; A nonzero high byte is outside 0-255
    DEC HL                          ; Reload the current text character
    RST $10
    LD A,E
    RET
;; Executes LLIST, listing the program to the printer.
ST_LLIST:
    LD A,$01                        ; Route LIST output to the printer
    LD [PRTFLG],A
;; Executes LIST, displaying the program or a range of its line numbers.
ST_LIST:
    POP BC                          ; Hold the return address while parsing the range
    CALL SCNLIN                     ; Parse the range: first line found, last stacked
    PUSH BC
;; Enters LIST's loop, which prints each line up to the end of the range, checking for BREAK.
LIST4:
    LD HL,$FFFF                     ; Line number -1 shows no program line is running
    LD [CURLIN],HL
    POP HL                          ; HL = the line to list
    POP DE                          ; DE = the last line number of the range
    LD C,[HL]                       ; BC = the link to the next line
    INC HL
    LD B,[HL]
    INC HL
    LD A,B
    OR C                            ; A zero link is the program's end
    JP Z,READY
    CALL HOOK_READ_LIST
    CALL ISCNTC                     ; Stop if BREAK is pressed
    PUSH BC                         ; Save the next line's link
    LD C,[HL]                       ; BC = this line's number
    INC HL
    LD B,[HL]
    INC HL
    PUSH BC
    EX [SP],HL                      ; Stack the text pointer, HL = the line number
    EX DE,HL                        ; HL = the range end, DE = the line number
    RST $18                         ; Is this line past the range?
    POP BC                          ; BC = the line's text pointer
    JP C,STPRDY                     ; Past the range, stop listing
    EX [SP],HL                      ; Stack the range end, HL = the next line's link
    PUSH HL
    PUSH BC
    EX DE,HL                        ; HL = the line number
    LD [DOT],HL                     ; It becomes the current line for EDIT
    CALL LINPRT
    LD A,$20                        ; A space follows the line number
    POP HL                          ; HL = the line's text
    CALL OUTDO
    CALL BUFLIN                     ; Expand the line's tokens into the buffer
    LD HL,[BUFPNT]
    CALL LISPRT                     ; Print the expanded line
    CALL CRDO
    JR LIST4

;; Prints the zero-terminated string at HL.
LISPRT:
    LD A,[HL]
    OR A
    RET Z
    CALL OUTDO
    INC HL
    JR LISPRT

;; Expands the crunched line at HL into the input buffer, spelling out its reserved words.
BUFLIN:
    PUSH HL
    LD HL,[BUFPNT]                  ; BC = destination in the input buffer
    LD B,H
    LD C,L
    POP HL
    LD D,$FF                        ; D = room left in the buffer
    JR PLOOP2

PLOOP:
    INC BC
    DEC D
    RET Z                           ; Stop when the buffer is full

PLOOP2:
    LD A,[HL]                       ; A = next byte of the line
    OR A
    INC HL
    LD [BC],A
    RET Z                           ; A zero byte ends the line
    JP P,PLOOP                      ; Ordinary characters are copied unchanged
    CP $FB                          ; $FB is the apostrophe remark token
    JR NZ,NTQTTK
    DEC BC                          ; Remove the :REM text stored before the apostrophe
    DEC BC
    DEC BC
    DEC BC
    INC D                           ; Give back the buffer room
    INC D
    INC D
    INC D

;; Expands a keyword token into its keyword text while detokenizing a line, dropping ELSE's colon.
NTQTTK:
    CP $95                          ; $95 is the ELSE token
    CALL Z,DCXBRT                   ; Remove the colon stored before ELSE
    SUB $7F                         ; E = token number, counting from one
    PUSH HL
    LD E,A
    LD HL,KEYWORDS

LOPRES:
    LD A,[HL]                       ; Scan for a byte with bit 7 set
    OR A
    INC HL
    JP P,LOPRES                     ; which starts a keyword in KEYWORDS
    DEC E                           ; Count down to this token's keyword
    JR NZ,LOPRES
    AND $7F                         ; Clear the marker bit of the first letter

MORPUR:
    LD [BC],A                       ; Store a keyword letter
    INC BC
    DEC D
    JP Z,PPSWRT                     ; Out of buffer room
    LD A,[HL]                       ; A = the keyword's next letter
    INC HL
    OR A
    JP P,MORPUR                     ; Copy until the next keyword's first letter
    POP HL                          ; Resume the line's text
    JR PLOOP2
;; Executes DELETE, removing a range of program lines; FC error if the range is invalid.
ST_DELETE:
    CALL SCNLIN                     ; Parse the range: BC = first line, last stacked
    POP DE                          ; DE = the last line number
    PUSH BC                         ; Keep the first line's pointer twice
    PUSH BC
    CALL FNDLIN                     ; Find the last line of the range
    JR NC,FCERRG                    ; The last line must exist
    LD D,H                          ; DE = pointer past the last line
    LD E,L
    EX [SP],HL                      ; Stack it, HL = the first line's pointer
    PUSH HL
    RST $18                         ; The first line must come before it
;; Gives DELETE's FC error when carry is clear, otherwise prints Ready and removes the lines.
FCERRG:
    JP NC,FCERR
    LD HL,READY_MSG
    CALL STROUT
    POP BC                          ; BC = where the deleted lines start
    LD HL,$1AE8                     ; Finish at FINI, which relinks the program
    EX [SP],HL                      ; HL = text after the range, FINI stacked

;; Moves program text from DE up to VARTAB down to BC and sets VARTAB to the new end.
DEL:
    EX DE,HL
    LD HL,[VARTAB]                  ; Move everything up to the program's end

MLOOP:
    LD A,[DE]
    LD [BC],A
    INC BC
    INC DE
    RST $18                         ; Stop at the old end of the program
    JR NZ,MLOOP
    LD H,B
    LD L,C
    LD [VARTAB],HL                  ; The program now ends lower
    RET
;; Executes CSAVE, writing a header, the one-character file name and the program text to tape.
ST_CSAVE:
    CALL CWRTON                     ; Start the tape and write the leader
    CALL FRMEVL                     ; Evaluate the file name
    PUSH HL
    CALL ASC2                       ; DE = the name's first character
    LD A,$D3                        ; $D3 header bytes mark a BASIC program
    CALL CASSETTE_WRITE
    CALL TWOCSO                     ; Two more header bytes
    LD A,[DE]                       ; Then the one-character file name
    CALL CASSETTE_WRITE
    LD HL,[TXTTAB]                  ; DE = program start
    EX DE,HL
    LD HL,[VARTAB]                  ; HL = program end
;; Enters CSAVE's loop, writing each byte of the program text to tape, then stops the cassette.
LOPCSO:
    LD A,[DE]
    INC DE
    CALL CASSETTE_WRITE
    RST $18                         ; Stop at the end of the program text
    JR NZ,LOPCSO
    CALL CASSETTE_OFF
    POP HL                          ; Restore the text pointer
    RET
;; Executes CLOAD, loading a program from tape, or CLOAD?, comparing the tape with the program.
ST_CLOAD:
.if REVISION = 12
    CALL CSRDON
    LD A,[HL]
.endif
    SUB $B2                         ; CLOAD? appears as the PRINT token after CLOAD
.if REVISION = 12
    JR Z,ST_CLOAD_1
.else
    JR Z,ST_CLOAD_12
.endif
    XOR A                           ; Plain CLOAD: flag zero, skip the next two bytes
    .byte $01
.if REVISION = 12
ST_CLOAD_1:
.else
ST_CLOAD_12:
.endif
    CPL                             ; Verify flag $FF for CLOAD?
    INC HL                          ; Step past the ?
    PUSH AF                         ; Save the verify flag
.if REVISION = 12
    DEC HL
    RST $10
    LD A,$00
    JR Z,ST_CLOAD_2
.else
    LD A,[HL]
    OR A
    JR Z,ST_CLOAD_13                ; No file name given
.endif
    CALL FRMEVL
    CALL ASC2
    LD A,[DE]                       ; A = the name's first character
.if REVISION = 12
ST_CLOAD_2:
.else
;; Saves CLOAD's file name and verify flag, clears the program for a plain CLOAD, and reads the tape.
ST_CLOAD_13:
.endif
    LD L,A                          ; L = name to match, zero accepts any
    POP AF
    OR A                            ; Z for a plain CLOAD
    LD H,A                          ; H = the verify flag
    LD [FACLO],HL                   ; Keep the name and flag in FACLO for the loader
    CALL Z,ERASE_PROGRAM            ; A plain CLOAD clears the current program first
.if REVISION = 13
    LD HL,RESET
    CALL CSRDON                     ; Start the tape and wait for its leader
.endif
    LD HL,[FACLO]
    EX DE,HL                        ; D = verify flag, E = file name to find
;; Waits for CLOAD's three header bytes, then checks the tape's file name against the one asked for.
LOPCLK:
    LD B,$03                        ; Expect three $D3 header bytes
LOPCL2:
    CALL CASSETTE_READ
    SUB $D3
    JR NZ,LOPCLK                    ; Any other byte restarts the header search
    DJNZ LOPCL2
    CALL CASSETTE_READ              ; A = the tape's file name
    INC E                           ; No name asked for, so any file will do
    DEC E
    JR Z,NONAMC
    CP E
    JR NZ,SKPFIL                    ; Another file's name, skip past it
;; Starts reading the tape's program into memory at the start of the program text.
NONAMC:
    LD HL,[TXTTAB]                  ; Load at the start of the program text
;; Enters CLOAD's read loop, storing or comparing each byte until three zeros end the program.
DOCRS:
    LD B,$03                        ; Three zero bytes in a row end the program
DOCSMR:
    CALL CASSETTE_READ
    LD E,A                          ; E = the byte from tape
    SUB [HL]                        ; Compare it with memory
    AND D                           ; Differences count only when verifying (D = $FF)
    JR NZ,NOGOOD                    ; CLOAD? found a mismatch
    LD [HL],E                       ; Store the byte
    CALL REASON                     ; OM error if memory is full
    LD A,[HL]
    OR A
    INC HL
    JR NZ,DOCRS                     ; A nonzero byte restarts the zero count
    CALL BCASIN                     ; Blink the tape-loading asterisk
    DJNZ DOCSMR                     ; Count the run of zeros
    LD [VARTAB],HL                  ; The program ends here

OKCASS:
    LD HL,READY_MSG
    CALL STROUT
    CALL CASSETTE_OFF
    LD HL,[TXTTAB]
    PUSH HL
    JP FINI                         ; Relink the loaded lines and return to Ready
;; Prints BAD when CLOAD? finds a difference, and returns to the command level.
NOGOOD:
    LD HL,$2CA5                     ; $2CA5 is the BAD message at NOOKCS
    CALL STROUT
    JP STPRDY
SKPFIL:
    LD [CASSETTE_STATUS_CHAR],A     ; Show the skipped file's name on screen
ZERSRF:
    LD B,$03                        ; Skip to the three zeros that end that file
GETCHZ:
    CALL CASSETTE_READ
    OR A
    JR NZ,ZERSRF                    ; A nonzero byte resets the count
    DJNZ GETCHZ
    CALL CASSETTE_READ_LEADER       ; Then find the next file's leader
    JR LOPCLK

;; Holds the message BAD and a carriage return, printed when CLOAD? finds a difference.
NOOKCS:
    .byte $42, $41, $44, $0D, $00
;; Returns the byte at the address argument for PEEK.
FN_PEEK:
    CALL FRCINT                     ; HL = the address
    LD A,[HL]                       ; A = the byte there
    JP SNGFLT
;; Executes POKE, storing a byte value at an address.
ST_POKE:
    CALL GETIN2                     ; DE = the address
    PUSH DE
    RST $08
    .byte ','
    CALL GETBYT                     ; A = the value
    POP DE
    LD [DE],A
    RET
;; Executes the USING part of PRINT, formatting the values that follow by the format string.
PRINUS:
    CALL FRMCHK                     ; Evaluate the format string
    CALL CHKSTR
    RST $08
    .byte ';'
    EX DE,HL                        ; DE = the text pointer
    LD HL,[FACLO]                   ; HL = the format's descriptor
    JR INIUS
REUSST:
    LD A,[READ_INPUT_FLAG]          ; Was any field used in a full pass of the format?
    OR A
    JR Z,FCERR3                     ; A format with no fields cannot print values
    POP DE                          ; DE = the format's descriptor
    EX DE,HL                        ; HL = the descriptor, DE = the text pointer
INIUS:
    PUSH HL                         ; Save the format's descriptor
    XOR A
    LD [READ_INPUT_FLAG],A          ; No value printed yet in this pass
    CP D                            ; NZ: the value list has not ended
    PUSH AF                         ; Save that state
    PUSH DE                         ; Save the text pointer
    LD B,[HL]                       ; B = format length
    OR B
FCERR3:
    JP Z,FCERR                      ; An empty format gives FC error
    INC HL                          ; HL = the format string's text
    LD C,[HL]
    INC HL
    LD H,[HL]
    LD L,C
    JR PRCCHR
BGSTRF:
    LD E,B                          ; E = characters left, in case no field forms
    PUSH HL                         ; Save the position after the %
    LD C,$02                        ; A %...% field is at least two wide
LPSTRF:
    LD A,[HL]
    INC HL
    CP $25
    JP Z,ISSTRF                     ; A closing % completes the string field
    CP $20
    JR NZ,NOSTRF                    ; Only spaces may come between the percent signs
    INC C                           ; Widen the field
    DJNZ LPSTRF
;; Prints the percent sign of an unfinished string field as plain text and resumes the format scan.
NOSTRF:
    POP HL                          ; Back to just after the %
    LD B,E                          ; Restore the count of characters left
    LD A,$25                        ; Print the % as text
;; Prints the format character in A as text, then scans the format string for the next field.
NEWUCH:
    CALL PLSPRT
    CALL OUTDO
PRCCHR:
    XOR A                           ; Start a new field: no flags or digits yet
    LD E,A
    LD D,A
PLSFIN:
    CALL PLSPRT
    LD D,A                          ; D = field flags
    LD A,[HL]                       ; A = the next format character
    INC HL
    CP $21                          ; ! is a one-character string field
    JP Z,SMSTRF
    CP $23                          ; # starts a numeric field
    JR Z,NUMNUM
    DEC B
    JP Z,REUSIN                     ; Last character of the format
    CP $2B                          ; + asks for a sign before the number
    LD A,$08                        ; Flag $08 for a leading sign
    JR Z,PLSFIN
    DEC HL
    LD A,[HL]                       ; Reread the character
    INC HL
    CP $2E                          ; A period may start a numeric field
    JR Z,DOTNUM
    CP $25                          ; A percent sign may start a string field
    JR Z,BGSTRF
    CP [HL]                         ; The rest need a doubled character
    JR NZ,NEWUCH
    CP $24                          ; $$ is a floating dollar sign
    JR Z,DOLRNM
    CP $2A                          ; ** fills leading spaces with asterisks
    JR NZ,NEWUCH
    LD A,B
    CP $02                          ; Room for a $ after the **?
    INC HL
    JR C,NOTSPC
    LD A,[HL]                       ; **$ adds a dollar sign too
    CP $24
NOTSPC:
    LD A,$20                        ; Flag $20 for asterisk fill
    JR NZ,SPCNUM                    ; Plain ** field
    DEC B                           ; Count the $ character
    INC E                           ; The $ takes a digit position
    .byte $FE
DOLRNM:
    XOR A
    ADD A,$10                       ; Add the dollar sign flag $10
    INC HL                          ; Skip the doubled character
SPCNUM:
    INC E                           ; The doubled characters count as digits
    ADD A,D
    LD D,A                          ; Merge into the field flags
NUMNUM:
    INC E                           ; One more digit before the point
    LD C,$00                        ; No digits after the point yet
    DEC B
    JR Z,ENDNUS                     ; Format ended within the field
    LD A,[HL]
    INC HL
    CP $2E                          ; A period starts the fraction digits
    JR Z,AFTDOT
    CP $23                          ; Another digit position
    JR Z,NUMNUM
    CP $2C                          ; A comma asks for thousands separators
    JR NZ,FINNUM
    LD A,D
    OR $40                          ; Comma flag $40
    LD D,A
    JR NUMNUM
;; Starts a numeric field at a period in the format string if a number sign follows it.
DOTNUM:
    LD A,[HL]
    CP $23                          ; A digit must follow the period
    LD A,$2E
    JR NZ,NEWUCH                    ; Otherwise print the period as text
    LD C,$01                        ; C counts the decimal point
    INC HL
AFTDOT:
    INC C                           ; Count a digit after the point
    DEC B
    JR Z,ENDNUS                     ; Format ended within the field
    LD A,[HL]
    INC HL
    CP $23
    JR Z,AFTDOT                     ; More fraction digits
;; Checks a numeric field for the four exponent marks that request scientific notation.
FINNUM:
    PUSH DE                         ; Save the field flags and digit count
    LD DE,$2D97                     ; Return via $2D97 to undo the lookahead if no marks
    PUSH DE
    LD D,H                          ; DE = position to restore
    LD E,L
    CP $5B                          ; [ shows as an up arrow, the exponent mark
    RET NZ
    CP [HL]                         ; Four marks in a row are required
    RET NZ
    INC HL
    CP [HL]
    RET NZ
    INC HL
    CP [HL]
    RET NZ
    INC HL
    LD A,B
    SUB $04
    RET C                           ; Not enough format left for all four
    POP DE                          ; Drop the $2D97 return address
    POP DE                          ; Restore the field flags
    LD B,A                          ; B = characters left after the marks
    INC D                           ; Flag exponential notation
    INC HL
    JP Z,USING_SKIP_OPERAND         ; Only the opcode runs, its operand is the code at $2D97
ENDNUS:
    LD A,D                          ; A = field flags
    DEC HL                          ; Back to the character after the field
    INC E                           ; Count a position for the sign
    AND $08
    JR NZ,ENDNUM                    ; A leading + already provides the sign place
    DEC E
    LD A,B
    OR A
    JR Z,ENDNUM                     ; End of format, so no trailing sign
    LD A,[HL]
    SUB $2D
    JR Z,SGNTRL                     ; A trailing - prints a minus after negatives
    CP $FE                          ; $FE means the character was +
    JR NZ,ENDNUM
    LD A,$08                        ; Trailing plus flag
SGNTRL:
    ADD A,$04                       ; Trailing sign flags: $04 minus, $0C plus
    ADD A,D
    LD D,A
    DEC B                           ; The sign character is used
;; Evaluates the next value and prints it in the numeric field just scanned.
;; Gives an FC error when the field has more than 24 digits.
ENDNUM:
    POP HL                          ; HL = the text pointer
    POP AF                          ; Z when no values remain
    JR Z,FLDFIN                     ; No value left, finish the statement
    PUSH BC                         ; Save the digit counts and flags
    PUSH DE
    CALL FRMEVL                     ; Evaluate the value to print
    POP DE
    POP BC
    PUSH BC
    PUSH HL
    LD B,E                          ; B = digits before the point
    LD A,B
    ADD A,C                         ; Total digit positions
    CP $19
    JP NC,FCERR                     ; More than 24 gives FC error
    LD A,D
    OR $80                          ; Bit 7 asks PUFOUT for formatted output
    CALL PUFOUT                     ; Format the number into a string
    CALL STROUT
FNSTRF:
    POP HL                          ; HL = the text pointer
    DEC HL                          ; Reread the character after the value
    RST $10
    SCF                             ; Carry asks for a new line at the end
    JR Z,CRDNUS                     ; The statement ends after this value
    LD [READ_INPUT_FLAG],A          ; Note that a value was printed
    CP $3B                          ; A semicolon or comma may separate values
    JR Z,SEMUSN
    CP $2C
    JP NZ,SNERR                     ; Anything else is a syntax error
SEMUSN:
    RST $10                         ; Skip the separator
;; Recomputes the position in the format string after evaluating a value, then continues the scan.
CRDNUS:
    POP BC                          ; B = format characters left
    EX DE,HL                        ; DE = the text pointer
    POP HL                          ; HL = the format's descriptor
    PUSH HL                         ; Keep it for the next value
    PUSH AF                         ; Save whether the statement ended
    PUSH DE                         ; Save the text pointer
    LD A,[HL]
    SUB B                           ; A = format characters already used
    INC HL                          ; HL = the format text
    LD C,[HL]
    INC HL
    LD H,[HL]
    LD L,C
    LD D,$00
    LD E,A
    ADD HL,DE                       ; HL = the position after this field
    LD A,B
    OR A
    JP NZ,PRCCHR                    ; Format remains, keep scanning
    JR FINUSI                       ; Format used up
;; Prints the last format character as text and ends the format string, reusing it if values remain.
REUSIN:
    CALL PLSPRT
    CALL OUTDO
FINUSI:
    POP HL                          ; HL = the text pointer
    POP AF                          ; NZ when values remain
    JP NZ,REUSST                    ; Values remain: start the format over
FLDFIN:
    CALL C,CRDO                     ; New line unless a separator ended the statement
    EX [SP],HL                      ; HL = the format's descriptor
    CALL FRETM2                     ; Free the format string
    POP HL                          ; HL = the text pointer
    JP FINPRT
;; Handles a one-character string field marked by an exclamation point.
SMSTRF:
    LD C,$01                        ; A ! field is one character wide
    .byte $3E
ISSTRF:
    POP AF                          ; Drop the position saved by BGSTRF
    DEC B                           ; Count the closing %
    CALL PLSPRT
    POP HL                          ; HL = the text pointer
    POP AF                          ; Z when no values remain
    JR Z,FLDFIN                     ; Nothing left to print
    PUSH BC                         ; Save the counts
    CALL FRMEVL                     ; Evaluate the value to print
    CALL CHKSTR                     ; It must be a string
    POP BC
    PUSH BC
    PUSH HL
    LD HL,[FACLO]                   ; HL = its descriptor
    LD B,C                          ; B = field width
    LD C,$00                        ; taken from the first character
    PUSH BC                         ; Save the width
    CALL LEFTUS                     ; Take up to the width
    CALL STRPRT
    LD HL,[FACLO]
    POP AF
    SUB [HL]                        ; B = padding needed after the string
    LD B,A
    LD A,$20                        ; Pad with spaces
    INC B                           ; Offset the DEC B at UPRTSP
;; Pads a string field with B-1 spaces, then moves to the next value.
UPRTSP:
    DEC B
    JP Z,FNSTRF                     ; Padding done, go on to the next value
    CALL OUTDO
    JR UPRTSP

;; Prints a plus sign when D is nonzero, for PRINT USING; keeps A.
PLSPRT:
    PUSH AF
    LD A,D                          ; D nonzero means a + is pending
    OR A
    LD A,$2B
    CALL NZ,OUTDO
    POP AF
    RET

;; Stores the error code in A and, after a syntax error in a program line, edits that line.
ERREDT:
    LD [ERRFLG],A                   ; Remember the error code
    LD HL,[ERRLIN]                  ; HL = the line where the error occurred
    OR H
    AND L
    INC A                           ; Z when ERRLIN is $FFFF, a direct command
    EX DE,HL                        ; DE = the line number to edit
    RET Z                           ; No program line to edit
    JR EREDIT
;; Executes EDIT, letting the user change a program line with the editing commands; UL error if missing.
ST_EDIT:
    CALL LINSPC                     ; DE = the line number to edit
    RET NZ                          ; Text after the line number is an error
EREDIT:
    POP HL                          ; Discard the return address
EEDITS:
    EX DE,HL
    LD [DOT],HL                     ; The edited line becomes the current line
    EX DE,HL
    CALL FNDLIN
    JP NC,USERR                     ; No such line gives UL error
    LD H,B                          ; HL = the line found
    LD L,C
    INC HL                          ; Step past its link
    INC HL
    LD C,[HL]                       ; BC = the line number
    INC HL
    LD B,[HL]
    INC HL
    PUSH BC                         ; Save it for printing
    CALL BUFLIN                     ; Expand the line into the buffer
LLED:
    POP HL                          ; HL = the line number

INLED:
    PUSH HL                         ; Keep it for later reprints
    CALL LINPRT
    LD A,$20
    CALL OUTDO
    LD HL,[BUFPNT]                  ; HL = the expanded text
    LD A,$0E                        ; $0E turns the cursor on
    CALL OUTDO
    PUSH HL                         ; Save the text start
    LD C,$FF                        ; C counts the line's length
LENLP:
    INC C
    LD A,[HL]
    OR A
    INC HL
    JR NZ,LENLP                     ; Until the zero terminator
    POP HL                          ; Back to the start of the text
    LD B,A                          ; B = cursor position, starting at zero

DISPED:
    LD D,$00                        ; No repeat count yet
DISPI:
    CALL INCHR

DISP:
    SUB $30                         ; Digit keys build a repeat count
    JR C,NOTDGI
    CP $0A
    JR NC,NOTDGI
    LD E,A                          ; E = the digit's value
    LD A,D                          ; D = D times ten
    RLCA
    RLCA
    ADD A,D
    RLCA
    ADD A,E                         ; plus the new digit
    LD D,A
    JR DISPI
;; Dispatches an EDIT command key, after any repeat count in D, to its handler.
NOTDGI:
    PUSH HL
    LD HL,$2E99                     ; Handlers return to DISPED for the next key
    EX [SP],HL
    DEC D
    INC D
    JP NZ,NTZERD
    INC D                           ; No count given, do the command once
NTZERD:
    CP $D8                          ; Backspace, as key code minus $30
    JP Z,DELED
    CP $DD                          ; Enter
    JP Z,CRED
    CP $F0                          ; Space
    JR Z,SPED
    CP $31
    JR C,NOTLW4
    SUB $20                         ; Fold lowercase command letters to uppercase
NOTLW4:
    CP $21                          ; Q quits without changes
    JP Z,QED
    CP $1C                          ; L lists the line
    JP Z,LED
    CP $23                          ; S searches for a character
    JR Z,SED
    CP $19                          ; I inserts
    JP Z,IED
    CP $14                          ; D deletes
    JP Z,DED
    CP $13                          ; C changes characters
    JP Z,CED
    CP $15                          ; E ends the edit, keeping changes
    JP Z,EED
    CP $28                          ; X extends at the end of the line
    JP Z,XED
    CP $1B                          ; K kills up to a character
    JR Z,KED
    CP $18                          ; H hacks off the rest and inserts
    JP Z,HED
    CP $11                          ; A starts again with the unchanged line
    RET NZ                          ; Ignore any other key
    POP BC                          ; Drop the DISPED return address
    POP DE                          ; DE = the line number
    CALL CRDO
    JP EEDITS

;; In EDIT, prints and moves past up to D characters of the line at HL, counting B.
SPED:
    LD A,[HL]
    OR A
    RET Z                           ; Stop at the end of the line
    INC B                           ; Advance the cursor position
    CALL OUTDO
    INC HL
    DEC D
    JR NZ,SPED                      ; Repeat count times
    RET

;; Handles the EDIT K command, deleting characters up to the D-th occurrence of a typed character.
KED:
    PUSH HL
    LD HL,$2F5F                     ; K returns through TYPSLH to close the ! bracket
    EX [SP],HL
    SCF                             ; Carry selects delete mode for K

SED:
    PUSH AF                         ; Save the K or S mode flag
    CALL INCHR                      ; E = the character to search for
    LD E,A
    POP AF
    PUSH AF
    CALL C,TYPSLH                   ; K shows deletions between ! marks

SRCALP:
    LD A,[HL]
    OR A
    JP Z,POPART                     ; Line ended, stop searching
    CALL OUTDO
    POP AF
    PUSH AF
    CALL C,DELCHR                   ; K deletes the character instead of passing it
    JR C,NOTSRC
    INC HL                          ; S moves past it
    INC B

NOTSRC:
    LD A,[HL]
    CP E
    JR NZ,SRCALP                    ; Not the target, keep going
    DEC D
    JR NZ,SRCALP                    ; Stop at its D-th occurrence

POPART:
    POP AF                          ; Drop the mode flag
    RET

;; Handles the EDIT L command, printing the rest of the line and restarting at its beginning.
LED:
    CALL LISPRT
    CALL CRDO
    POP BC                          ; Drop the return address
    JP LLED

;; Handles the EDIT D command, deleting D characters and showing them between exclamation marks.
DED:
    LD A,[HL]
    OR A
    RET Z
    LD A,$21                        ; Open the ! bracket
    CALL OUTDO

DELLP:
    LD A,[HL]
    OR A
    JR Z,TYPSLH                     ; Line ended, close the bracket
    CALL OUTDO
    CALL DELCHR                     ; Remove it from the line
    DEC D
    JR NZ,DELLP

;; Prints the exclamation mark that brackets characters deleted in EDIT.
TYPSLH:
    LD A,$21
    CALL OUTDO
    RET

;; Handles the EDIT C command, replacing D characters with typed ones.
CED:
    LD A,[HL]
    OR A
    RET Z
    CALL INCHR                      ; Read the replacement character
    LD [HL],A                       ; Overwrite the line's character
    CALL OUTDO
    INC HL
    INC B
    DEC D
    JR NZ,CED
    RET

;; Handles the EDIT H command, removing the rest of the line and entering insert mode.
HED:
    LD [HL],$00                     ; Truncate the line at the cursor
    LD C,B                          ; C = the new line length

XED:
    LD D,$FF                        ; As many characters as remain
    CALL SPED                       ; Move to the end of the line

;; Handles the EDIT I command, inserting typed characters until Enter or ESC.
IED:
    CALL INCHR
    OR A
    JP Z,IED                        ; Wait for a key
    CP $08                          ; Backspace
    JR Z,TYPARW
    CP $0D
    JP Z,CRED                       ; Enter ends the edit
    CP $1B
    RET Z                           ; ESC leaves insert mode
    JR NZ,NTARRW                    ; Insert any other character

;; Handles backspace in EDIT's insert mode, deleting the character before the cursor.
TYPARW:
    LD A,$08

TYPAR1:
    DEC B
    INC B
    JR Z,DINGI                      ; At the line's start, nothing to delete
    CALL OUTDO                      ; Back up on screen
    DEC HL                          ; Move the cursor back
    DEC B
    LD DE,$2F7D                     ; Return to insert mode after deleting
    PUSH DE

;; In EDIT, deletes the character at HL by shifting the rest of the line left; decrements C.
DELCHR:
    PUSH HL
    DEC C                           ; The line is one shorter

CMPRSS:
    LD A,[HL]
    OR A
    SCF
    JP Z,POPHRT                     ; Done at the terminator, carry set
    INC HL
    LD A,[HL]                       ; Shift the next character left
    DEC HL
    LD [HL],A
    INC HL
    JR CMPRSS

;; Inserts the typed character in A when the line has room, otherwise ignores it.
NTARRW:
    PUSH AF
    LD A,C
    CP $FF                          ; Room only while the length is under 255
    JR C,OKINS
    POP AF                          ; Line full, ignore the key

DINGI:
    JR IED

OKINS:
    SUB B                           ; A = characters after the cursor
    INC C                           ; The line is one longer
    INC B                           ; The cursor moves right
    PUSH BC
    EX DE,HL                        ; DE = the cursor position
    LD L,A
    LD H,$00
    ADD HL,DE                       ; HL = the terminator
    LD B,H                          ; BC = the last byte to move
    LD C,L
    INC HL                          ; HL = its destination one byte up
    CALL BLTUC                      ; Open a gap at the cursor
    POP BC
    POP AF
    LD [HL],A                       ; Put the typed character in the gap
    CALL OUTDO
    INC HL
    JP IED

;; Handles backspace in EDIT's command mode, moving the cursor back D characters.
DELED:
    LD A,B
    OR A
    RET Z                           ; Already at the line's start
    DEC B                           ; Move the cursor back
    DEC HL
    LD A,$08                        ; Backspace on screen
    CALL OUTDO
    DEC D
    JR NZ,DELED
    RET

CRED:
    CALL LISPRT                     ; Print the rest of the line

EED:
    CALL CRDO
    POP BC                          ; Drop the return address
    POP DE                          ; DE = the line number
    LD A,D
    AND E
    INC A                           ; Z when DE is $FFFF, an edit of a typed line

EDITRT:
    LD HL,[BUFPNT]                  ; HL = the input buffer
    DEC HL
    RET Z                           ; Return to the line input code that called EDIT
    SCF                             ; Carry flags that a line number was seen
    INC HL
    PUSH AF
    JP EDENT                        ; Enter the edited line into the program

;; Handles the EDIT Q command, abandoning the changes and returning to the command level.
QED:
    POP BC                          ; Drop the return address
    POP DE                          ; and the line number
    JP READY                        ; Leave the line unchanged
    .byte $DE, $C3, $C3, $44, $B2
