;; MBASIC 5.21: EQUATES
;;
;; The names MBASIC's modules share: CP/M's page zero, the BDOS functions BASIC calls, the layout of the file
;; data block (FDB) BASIC keeps for each open file, and BASIC's tokens, error codes and crunched constants. They define no bytes. Mbasic.asm includes this file
;; before the modules.
;;
;; BASIC calls the BDOS through CPMENT with the function in C and its argument, an FCB's or a buffer's address,
;; in DE. The console and printer don't go through the BDOS: INIT patches the BIOS's own entries into the calls in
;; Console.asm, found through BIOSWB.

; CP/M's page zero, below the program.
CPMWRM = $0000                      ;; the warm boot jump: SYSTEM leaves BASIC through it
BIOSWB = $0001                      ;; the warm boot jump's address, the BIOS's warm boot entry, from which INIT finds the BIOS's console entries
CPMENT = $0005                      ;; the BDOS jump: C = the function, DE = its argument
CPMMEM = $0006                      ;; the BDOS jump's address, the top of the TPA: MEMSIZ starts below it

; CP/M's BDOS functions, passed in C to CPMENT (Digital Research's names).
S_BDOSVER = 12                      ;; return the version in A: 0 before CP/M 2, else $2x
DRV_ALLRESET = 13                   ;; reset the disk system, logging every drive back in
DRV_SET = 14                        ;; select the drive in E (0 = A:)
F_OPEN = 15                         ;; open the file DE's FCB names; A = $FF if not found
F_CLOSE = 16                        ;; close the file, recording its extent in the directory
F_SFIRST = 17                       ;; search for the first directory entry matching DE's FCB; A = $FF if none
F_SNEXT = 18                        ;; search for the next matching entry; A = $FF if no more
F_DELETE = 19                       ;; delete the files DE's FCB matches
F_READ = 20                         ;; read the next record sequentially into the DMA buffer
F_WRITE = 21                        ;; write the DMA buffer as the next record
F_MAKE = 22                         ;; create the file DE's FCB names; A = $FF if the directory is full
F_RENAME = 23                       ;; rename the file DE's FCB names to the name 16 bytes on
DRV_GET = 25                        ;; return the current drive in A
F_DMAOFF = 26                       ;; set the DMA buffer to DE
F_READRAND = 33                     ;; read the record the FCB's random record field names (CP/M 2)
F_WRITERAND = 34                    ;; write the record the FCB's random record field names (CP/M 2)
F_SIZE = 35                         ;; set the FCB's random record field to the file's size in records (CP/M 2)
F_RANDREC = 36                      ;; set the FCB's random record field from its sequential position (CP/M 2)

; CP/M's default DMA buffer and records.
TBUFF = $0080                       ;; the default DMA buffer, where CP/M leaves the command line's length and text
DIRTMP = TBUFF                      ;; the same buffer, where directory searches return their entries
DATPSC = 128                        ;; the bytes in a CP/M record, and in a file's buffer

; The modes of a file, in its FDB's first byte (Microsoft's names).
MD_SQI = 1                          ;; sequential input
MD_SQO = 2                          ;; sequential output
MD_RND = 3                          ;; random

; The layout of a file data block.
FD_MODE = $00                       ;; the mode: 0 when closed, else MD_SQI, MD_SQO or MD_RND
FD_FCB = $01                        ;; CP/M's 36-byte file control block
FD_EXT = $0D                        ;; the FCB's extent number (byte 12)
FD_RC = $10                         ;; the FCB's count of records in the extent (byte 15), LOF's result
FD_CR = $21                         ;; the FCB's current record in the extent (byte 32)
FD_RR = $22                         ;; the FCB's random record number (bytes 33-35)
FD_REC = $25                        ;; a word: the records read or written so far, LOC's result for a sequential file
FD_BCNT = $27                       ;; the bytes in the buffer: those written, or DATPSC read (0 at the end of the file)
FD_BREM = $28                       ;; reading, the bytes left in the buffer; writing, the column printed to
FD_BUF = $29                        ;; the DATPSC-byte record buffer, CP/M's DMA buffer for the file
FD_RLEN = $A9                       ;; a random file's record length (OPEN's LEN, 128 by default); file 0's block ends here
FD_PREC = $AB                       ;; a random file's 128-byte record in the buffer, plus 1 (0 for none)
FD_LREC = $AD                       ;; a random file's current record, from 1, LOC's result
FD_FPOS = $B0                       ;; a random file's position in its record buffer, for PRINT# and INPUT#
FD_FIELD = $B2                      ;; a random file's record buffer, FD_RLEN bytes, which FIELD maps variables onto

; Tokens: a reserved word in a program line is one byte, from $81, by its place in STMDSP and ALPTAB. A
; function is TK_FUNCTION and its number, a TF_ constant, by its place in FUNDSP.
TK_END = $81                        ;; END
TK_FOR = $82                        ;; FOR
TK_NEXT = $83                       ;; NEXT
TK_DATA = $84                       ;; DATA
TK_INPUT = $85                      ;; INPUT
TK_DIM = $86                        ;; DIM
TK_READ = $87                       ;; READ
TK_LET = $88                        ;; LET
TK_GOTO = $89                       ;; GOTO
TK_RUN = $8A                        ;; RUN
TK_IF = $8B                         ;; IF
TK_RESTORE = $8C                    ;; RESTORE
TK_GOSUB = $8D                      ;; GOSUB
TK_RETURN = $8E                     ;; RETURN
TK_REM = $8F                        ;; REM
TK_STOP = $90                       ;; STOP
TK_PRINT = $91                      ;; PRINT
TK_CLEAR = $92                      ;; CLEAR
TK_LIST = $93                       ;; LIST
TK_NEW = $94                        ;; NEW
TK_ON = $95                         ;; ON
TK_NULL = $96                       ;; NULL
TK_WAIT = $97                       ;; WAIT
TK_DEF = $98                        ;; DEF
TK_POKE = $99                       ;; POKE
TK_CONT = $9A                       ;; CONT
TK_OUT = $9D                        ;; OUT
TK_LPRINT = $9E                     ;; LPRINT
TK_LLIST = $9F                      ;; LLIST
TK_WIDTH = $A1                      ;; WIDTH
TK_ELSE = $A2                       ;; ELSE
TK_TRON = $A3                       ;; TRON
TK_TROFF = $A4                      ;; TROFF
TK_SWAP = $A5                       ;; SWAP
TK_ERASE = $A6                      ;; ERASE
TK_EDIT = $A7                       ;; EDIT
TK_ERROR = $A8                      ;; ERROR
TK_RESUME = $A9                     ;; RESUME
TK_DELETE = $AA                     ;; DELETE
TK_AUTO = $AB                       ;; AUTO
TK_RENUM = $AC                      ;; RENUM
TK_DEFSTR = $AD                     ;; DEFSTR
TK_DEFINT = $AE                     ;; DEFINT
TK_DEFSNG = $AF                     ;; DEFSNG
TK_DEFDBL = $B0                     ;; DEFDBL
TK_LINE = $B1                       ;; LINE
TK_WHILE = $B4                      ;; WHILE
TK_WEND = $B5                       ;; WEND
TK_CALL = $B6                       ;; CALL
TK_WRITE = $B7                      ;; WRITE
TK_COMMON = $B8                     ;; COMMON
TK_CHAIN = $B9                      ;; CHAIN
TK_OPTION = $BA                     ;; OPTION
TK_RANDOMIZE = $BB                  ;; RANDOMIZE
TK_SYSTEM = $BD                     ;; SYSTEM
TK_OPEN = $BF                       ;; OPEN
TK_FIELD = $C0                      ;; FIELD
TK_GET = $C1                        ;; GET
TK_PUT = $C2                        ;; PUT
TK_CLOSE = $C3                      ;; CLOSE
TK_LOAD = $C4                       ;; LOAD
TK_MERGE = $C5                      ;; MERGE
TK_FILES = $C6                      ;; FILES
TK_NAME = $C7                       ;; NAME
TK_KILL = $C8                       ;; KILL
TK_LSET = $C9                       ;; LSET
TK_RSET = $CA                       ;; RSET
TK_SAVE = $CB                       ;; SAVE
TK_RESET = $CC                      ;; RESET
TK_TO = $CE                         ;; TO
TK_THEN = $CF                       ;; THEN
TK_TAB = $D0                        ;; TAB(
TK_STEP = $D1                       ;; STEP
TK_USR = $D2                        ;; USR
TK_FN = $D3                         ;; FN
TK_SPC = $D4                        ;; SPC(
TK_NOT = $D5                        ;; NOT
TK_ERL = $D6                        ;; ERL
TK_ERR = $D7                        ;; ERR
TK_STRING = $D8                     ;; STRING$
TK_USING = $D9                      ;; USING
TK_INSTR = $DA                      ;; INSTR
TK_APOSTROPHE = $DB                 ;; ', a remark, stored as :REM' after a colon
TK_VARPTR = $DC                     ;; VARPTR
TK_INKEY = $DD                      ;; INKEY$
TK_GREATER = $EF                    ;; >
TK_EQUAL = $F0                      ;; =
TK_LESS = $F1                       ;; <
TK_PLUS = $F2                       ;; +
TK_MINUS = $F3                      ;; -
TK_TIMES = $F4                      ;; *
TK_DIVIDE = $F5                     ;; /
TK_POWER = $F6                      ;; ^
TK_AND = $F7                        ;; AND
TK_OR = $F8                         ;; OR
TK_XOR = $F9                        ;; XOR
TK_EQV = $FA                        ;; EQV
TK_IMP = $FB                        ;; IMP
TK_MOD = $FC                        ;; MOD
TK_IDIV = $FD                       ;; \, integer division
TK_FUNCTION = $FF                   ;; precedes a function's number

; Function numbers, the byte after TK_FUNCTION.
TF_LEFT = $81                       ;; LEFT$
TF_RIGHT = $82                      ;; RIGHT$
TF_MID = $83                        ;; MID$
TF_SGN = $84                        ;; SGN
TF_INT = $85                        ;; INT
TF_ABS = $86                        ;; ABS
TF_SQR = $87                        ;; SQR
TF_RND = $88                        ;; RND
TF_SIN = $89                        ;; SIN
TF_LOG = $8A                        ;; LOG
TF_EXP = $8B                        ;; EXP
TF_COS = $8C                        ;; COS
TF_TAN = $8D                        ;; TAN
TF_ATN = $8E                        ;; ATN
TF_FRE = $8F                        ;; FRE
TF_INP = $90                        ;; INP
TF_POS = $91                        ;; POS
TF_LEN = $92                        ;; LEN
TF_STR = $93                        ;; STR$
TF_VAL = $94                        ;; VAL
TF_ASC = $95                        ;; ASC
TF_CHR = $96                        ;; CHR$
TF_PEEK = $97                       ;; PEEK
TF_SPACE = $98                      ;; SPACE$
TF_OCT = $99                        ;; OCT$
TF_HEX = $9A                        ;; HEX$
TF_LPOS = $9B                       ;; LPOS
TF_CINT = $9C                       ;; CINT
TF_CSNG = $9D                       ;; CSNG
TF_CDBL = $9E                       ;; CDBL
TF_FIX = $9F                        ;; FIX
TF_CVI = $AB                        ;; CVI
TF_CVS = $AC                        ;; CVS
TF_CVD = $AD                        ;; CVD
TF_EOF = $AF                        ;; EOF
TF_LOC = $B0                        ;; LOC
TF_LOF = $B1                        ;; LOF
TF_MKI = $B2                        ;; MKI$
TF_MKS = $B3                        ;; MKS$
TF_MKD = $B4                        ;; MKD$

; Error codes: the code in E when a routine jumps to ERROR, which ERR returns. Codes from 50 are the disk
; errors, whose messages follow the others in ERRTAB. The names are GW-BASIC's, ERRSN and the rest.
ERR_NF = 1                          ;; NEXT without FOR
ERR_SN = 2                          ;; Syntax error
ERR_RG = 3                          ;; RETURN without GOSUB
ERR_OD = 4                          ;; Out of DATA
ERR_FC = 5                          ;; Illegal function call
ERR_OV = 6                          ;; Overflow
ERR_OM = 7                          ;; Out of memory
ERR_US = 8                          ;; Undefined line number
ERR_BS = 9                          ;; Subscript out of range
ERR_DD = 10                         ;; Duplicate Definition
ERR_DV0 = 11                        ;; Division by zero
ERR_ID = 12                         ;; Illegal direct
ERR_TM = 13                         ;; Type mismatch
ERR_SO = 14                         ;; Out of string space
ERR_LS = 15                         ;; String too long
ERR_ST = 16                         ;; String formula too complex
ERR_CN = 17                         ;; Can't continue
ERR_UF = 18                         ;; Undefined user function
ERR_NR = 19                         ;; No RESUME
ERR_RE = 20                         ;; RESUME without error
ERR_UE = 21                         ;; Unprintable error
ERR_MO = 22                         ;; Missing operand
ERR_LBO = 23                        ;; Line buffer overflow
ERR_FN = 26                         ;; FOR Without NEXT
ERR_WH = 29                         ;; WHILE without WEND
ERR_WE = 30                         ;; WEND without WHILE
ERR_FOV = 50                        ;; FIELD overflow
ERR_IER = 51                        ;; Internal error
ERR_BFN = 52                        ;; Bad file number
ERR_FNF = 53                        ;; File not found
ERR_BFM = 54                        ;; Bad file mode
ERR_FAO = 55                        ;; File already open
ERR_DIO = 57                        ;; Disk I/O error
ERR_FAE = 58                        ;; File already exists
ERR_DFL = 61                        ;; Disk full
ERR_RPE = 62                        ;; Input past end
ERR_BRN = 63                        ;; Bad record number
ERR_IFN = 64                        ;; Bad file name
ERR_DSF = 66                        ;; Direct statement in file
ERR_TMF = 67                        ;; Too many files

; The bytes that start a constant crunched into a line, GW-BASIC's names. CHRGTR reads the constant into
; CONLO, with its type in CONTYP.
OCTCON = $0B                        ;; an octal constant (&O), with two bytes
HEXCON = $0C                        ;; a hexadecimal constant (&H), with two bytes
PTRCON = $0D                        ;; a line number RUN has turned into its line's address, less one, with two bytes
LINCON = $0E                        ;; a line number, with two bytes
IN2CON = $0F                        ;; an integer from 10 to 255, with one byte
CONCN2 = $10                        ;; what CHRGTR returns at a constant's end, to go past it
ONECON = $11                        ;; the integers 0 to 9 are ONECON to ONECON+9, with no bytes
INTCON = $1C                        ;; an integer, with two bytes
SNGCON = $1D                        ;; a single-precision constant, with four bytes
CONCON = $1E                        ;; what CHRGTR returns for a constant it has already read
DBLCON = $1F                        ;; a double-precision constant, with eight bytes
