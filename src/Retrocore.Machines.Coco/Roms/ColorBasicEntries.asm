;; COLOR BASIC ENTRY POINTS, FOR THE SOURCES THAT CALL COLOR BASIC
;;
;; The Color BASIC routines and tables that Extended and Disk Color BASIC and the CoCo 3's ROM use, as equates at
;; their addresses, which are the same in Color BASIC 1.0 to 1.3. ColorBasic.asm defines and documents each of them
;; as a label, so it does not include this file; the others do, and each definition here inherits Color BASIC's
;; documentation. The places within a routine that the others enter or patch have a line of their own instead, as
;; do the routines only the CoCo 3's build has.

;; Inherit: <ColorBasic:DEBDEL>
DEBDEL = $045E

;; Inherit: <ColorBasic:RESVEC>
RESVEC = $A027

EXECCART = $A05E                    ;; the CoCo 3's start of a ROM pack by hand, for EXEC &HE010: maps it in and jumps to it
WAITKY3 = $A0CE                     ;; the CoCo 3's wait for a key, on the hi-res text screen when one is in use
COLDST_RSTFLG = $A0E2               ;; the cold start's end: makes RESET a warm start, then enters BASIC

;; Inherit: <ColorBasic:BAWMST>
BAWMST = $A0E8

;; Inherit: <ColorBasic:INCHR>
INCHR = $A171

;; Inherit: <ColorBasic:CONIN>
CONIN = $A176

;; Inherit: <ColorBasic:WAITKY>
WAITKY = $A1B1

;; Inherit: <ColorBasic:KEYIN>
KEYIN = $A1CB

;; Inherit: <ColorBasic:PUTCHR>
PUTCHR = $A282

;; Inherit: <ColorBasic:SCRCHR>
SCRCHR = $A30A

SCRCHR_SAVED = $A30E                ;; SCRCHR with its registers saved: prints A on the 32-column screen

;; Inherit: <ColorBasic:SETPRM>
SETPRM = $A35F

SETPRM_STORE = $A37C                ;; SETPRM's end: sets the comma fields, position and width from X, B and A

;; Inherit: <ColorBasic:LINEIN_CLEAR>
LINEIN_CLEAR = $A38D

;; Inherit: <ColorBasic:LINEIN>
LINEIN = $A390

LINEIN_BREAK = $A3C2                ;; LINEIN's check for BREAK

LINEIN_BRKDONE = $A3C6              ;; LINEIN's BREAK check once the carry is set: BREAK ends the line

;; Inherit: <ColorBasic:CHKIN>
CHKIN = $A3ED

;; Inherit: <ColorBasic:NOTOPN>
NOTOPN = $A3FB

;; Inherit: <ColorBasic:CHKOUT>
CHKOUT = $A406

;; Inherit: <ColorBasic:CLSALL>
CLSALL = $A426

CLSALL_CASSETTE = $A429             ;; CLSALL past its hook: closes the cassette's file

;; Inherit: <ColorBasic:CLSONE>
CLSONE = $A42D

CLSONE_EOF = $A444                  ;; closing a cassette file for output: writes the end of file block

;; Inherit: <ColorBasic:CSAVE>
CSAVE = $A44C

CSAVE_END = $A491                   ;; the end of CSAVE: writes the end of file block

;; Inherit: <ColorBasic:CLOAD>
CLOAD = $A498

CLOADM_OFFSET = $A505               ;; CLOADM once its file is found: reads the offset and loads the file

;; Inherit: <ColorBasic:CHKBRK>
CHKBRK = $A549

;; Inherit: <ColorBasic:SETCUR>
SETCUR = $A554

;; Inherit: <ColorBasic:GETNAM>
GETNAM = $A578

;; Inherit: <ColorBasic:MOVEXU>
MOVEXU = $A59A

;; Inherit: <ColorBasic:COMDEV>
COMDEV = $A5A2

;; Inherit: <ColorBasic:GETDEV>
GETDEV = $A5A5

;; Inherit: <ColorBasic:SETDEV>
SETDEV = $A5AE

NAMEND_CHECK = $A5C7                ;; NAMEND after the name: ?SN ERROR unless the statement has ended
EOF_CHECK = $A5DA                   ;; EOF past its hook, with the device saved and set: the cassette's or the screen's answer
EOF_RESULT = $A5E4                  ;; the end of EOF: gives the device back from the stack and returns B as the result
OPEN_NAME = $A603                   ;; OPEN once its mode and device are read: reads the file's name and opens it

;; Inherit: <ColorBasic:FMERR>
FMERR = $A616

;; Inherit: <ColorBasic:IOERR>
IOERR = $A619

;; Inherit: <ColorBasic:AOERR>
AOERR = $A61C

;; Inherit: <ColorBasic:DNERR>
DNERR = $A61F

;; Inherit: <ColorBasic:RDDATA>
RDDATA = $A635

RDDATA_COUNT = $A644                ;; the end of RDDATA: the buffer's count from A, its pointer at its start

;; Inherit: <ColorBasic:FINDFL>
FINDFL = $A648

;; Inherit: <ColorBasic:WRHDR>
WRHDR = $A65F

;; Inherit: <ColorBasic:DELAY>
DELAY = $A7D1

;; Inherit: <ColorBasic:WAITX>
WAITX = $A7D3

;; Inherit: <ColorBasic:WRLDR>
WRLDR = $A7D8

;; Inherit: <ColorBasic:MOTOROFF>
MOTOROFF = $A7E9

;; Inherit: <ColorBasic:SNDBLK>
SNDBLK = $A7F4

;; Inherit: <ColorBasic:CLS>
CLS = $A910

CLS_HOOKED = $A913                  ;; CLS past its hook: clears the screen, to the color given when there is one

;; Inherit: <ColorBasic:CLRSCN>
CLRSCN = $A928

SOUND_DURATION = $A951              ;; SOUND with its tone set and its duration in B: plays it

;; Inherit: <ColorBasic:SNDOFF>
SNDOFF = $A974

;; Inherit: <ColorBasic:SNDON>
SNDON = $A976

;; Inherit: <ColorBasic:SELMUX>
SELMUX = $A9A2

BIRQSV_SOUND = $A9BB                ;; the IRQ handler past its field sync check: SOUND's timer

;; Inherit: <ColorBasic:MOVEUP>
MOVEUP = $AC1E

;; Inherit: <ColorBasic:GETSTK>
GETSTK = $AC33

;; Inherit: <ColorBasic:CHKMEM>
CHKMEM = $AC37

;; Inherit: <ColorBasic:OMERR>
OMERR = $AC44

;; Inherit: <ColorBasic:ERROR>
ERROR = $AC46

ERROR_HOOKED = $AC49                ;; ERROR past its first hook
ERROR_SHOW = $AC60                  ;; the error handler's message: the two letters at X+B, then ERROR and the line

ERROR_MESSAGE = $AC65               ;; ERROR after its code's two letters: shows ERROR and the line, then prompts

;; Inherit: <ColorBasic:OKPRMT>
OKPRMT = $AC73

OKPRMT_OK = $AC76                   ;; OKPRMT after its new line: shows OK and goes on to the main loop

;; Inherit: <ColorBasic:MAINLP>
MAINLP = $AC7C

MAINLP_RUN = $AC9D                  ;; where the main loop runs a crunched direct line

;; Inherit: <ColorBasic:ERRCHR>
ERRCHR = $ACA0

EDITLN_NUMBER = $ACA8               ;; EDITLN with the line number read: crunches the line and puts it in the program

;; Inherit: <ColorBasic:LINKLN>
LINKLN = $ACEF

LINKLN_LINE = $ACF1                 ;; LINKLN from the line at X

;; Inherit: <ColorBasic:FINDLN>
FINDLN = $AD01

FINDLN_NEXT = $AD05                 ;; FINDLN's search from the line at X

;; Inherit: <ColorBasic:ERASEP>
ERASEP = $AD19

;; Inherit: <ColorBasic:CLRVAR>
CLRVAR = $AD21

;; Inherit: <ColorBasic:CLRSTR>
CLRSTR = $AD26

;; Inherit: <ColorBasic:RSTSTK>
RSTSTK = $AD33

RSTSTK_OLDPTR = $AD3F               ;; RSTSTK with the stack reset: clears OLDPTR so CONT cannot continue

RSTSTK_ARYDIS = $AD43               ;; RSTSTK's end: allows arrays again and returns

;; Inherit: <ColorBasic:NEWSTT>
NEWSTT = $AD9E

GONE_LOOP = $ADC4                   ;; GONE after the statement: back to NEWSTT, the interpreter's loop

;; Inherit: <ColorBasic:GONE2>
GONE2 = $ADC6

GONE_DISPATCH = $ADD4               ;; runs the command whose place is in A from the table at X

;; Inherit: <ColorBasic:ISCNTC>
ISCNTC = $ADEB

ISCNTC_KEY = $ADF0                  ;; ISCNTC once a key is read: BREAK stops, SHIFT-@ pauses

ISCNTC_NOTBRK = $ADF4               ;; ISCNTC's key that is not BREAK: pauses for SHIFT-@, or keeps the key

;; Inherit: <ColorBasic:STOP>
STOP = $AE09

;; Inherit: <ColorBasic:STOPIT>
STOPIT = $AE11

;; Inherit: <ColorBasic:ENDPRG>
ENDPRG = $AE15

;; Inherit: <ColorBasic:SETPTR>
SETPTR = $AEBB

;; Inherit: <ColorBasic:ULERR>
ULERR = $AED2

;; Inherit: <ColorBasic:DATA>
DATA = $AEE0

;; Inherit: <ColorBasic:SKPLIN>
SKPLIN = $AEEB

;; Inherit: <ColorBasic:ON>
ON = $AF42

ON_GO = $AF45                       ;; ON once n is read: reads GOTO or GOSUB and its lines

;; Inherit: <ColorBasic:LINGET>
LINGET = $AF67

;; Inherit: <ColorBasic:LET>
LET = $AF89

LET_VALUE = $AF9A                   ;; where LET's expression returns to, with the variable's type on the stack

;; Inherit: <ColorBasic:LETSTR>
LETSTR = $AFA4

LETSTR_COPY = $AFB1                 ;; LETSTR once it knows the string must be copied into string space
INPDEV_FILE = $B00C                 ;; where INPUT # returns to once CHKIN has opened the file for input
INPDEV_LINE = $B01E                 ;; INPUT once its prompt is shown: reads the first line from the device
INPLIN_READ = $B035                 ;; INPLIN without its prompt: reads a line into the line input buffer
INPLIN_BREAK = $B03C                ;; INPUT's line read, ended by BREAK: stops as STOP does
INPRD_ITEM = $B069                  ;; where INPUT reads its next item, from the text at X

;; Inherit: <ColorBasic:FRMNUM>
FRMNUM = $B141

;; Inherit: <ColorBasic:CKNUM>
CKNUM = $B143

;; Inherit: <ColorBasic:CKSTR>
CKSTR = $B146

;; Inherit: <ColorBasic:CKTYPE>
CKTYPE = $B148

TMERR = $B151                       ;; CKTYPE's ?TM ERROR: raises a type mismatch

;; Inherit: <ColorBasic:FRMEVL>
FRMEVL = $B156

FRMEVL_START = $B158                ;; FRMEVL without backing up first
FRMEVL_TERM = $B166                 ;; where FRMEVL's first term returns to

;; Inherit: <ColorBasic:STRLIT>
STRLIT = $B244

;; Inherit: <ColorBasic:PARENS>
PARENS = $B262

;; Inherit: <ColorBasic:SYNRPR>
SYNRPR = $B267

;; Inherit: <ColorBasic:SYNLPR>
SYNLPR = $B26A

;; Inherit: <ColorBasic:SYNCOM>
SYNCOM = $B26D

;; Inherit: <ColorBasic:SYNCHR>
SYNCHR = $B26F

;; Inherit: <ColorBasic:SNERR>
SNERR = $B277

EVAL_VAR = $B284                    ;; evaluates the variable at the program's place as a term
EVAL_FN_DISPATCH = $B2CE            ;; calls the function at B's place in the table at X, then checks for a number

;; Inherit: <ColorBasic:PTRGET>
PTRGET = $B357

PTRGT2_NAME = $B35C                 ;; PTRGT2 with DIMFLG already set

;; Inherit: <ColorBasic:ISLETC>
ISLETC = $B3A2

;; Inherit: <ColorBasic:POSINT>
POSINT = $B3E6

;; Inherit: <ColorBasic:POSCHK>
POSCHK = $B3E9

;; Inherit: <ColorBasic:INTCNV>
INTCNV = $B3ED

;; Inherit: <ColorBasic:FCERR>
FCERR = $B44A

;; Inherit: <ColorBasic:GIVB>
GIVB = $B4F3

;; Inherit: <ColorBasic:GIVABF>
GIVABF = $B4F4

;; Inherit: <ColorBasic:STRSPA>
STRSPA = $B50F

;; Inherit: <ColorBasic:STRSET>
STRSET = $B511

;; Inherit: <ColorBasic:STRLX>
STRLX = $B516

;; Inherit: <ColorBasic:STRLT2>
STRLT2 = $B518

STRLT2_ENDS = $B51A                 ;; STRLT2 with the terminator in A

;; Inherit: <ColorBasic:PUTNEW>
PUTNEW = $B54C

;; Inherit: <ColorBasic:GETSPA>
GETSPA = $B56D

;; Inherit: <ColorBasic:MOVSTR>
MOVSTR = $B643

;; Inherit: <ColorBasic:FRESTR>
FRESTR = $B654

;; Inherit: <ColorBasic:FREFAC>
FREFAC = $B657

;; Inherit: <ColorBasic:FRETMP>
FRETMP = $B659

CHRSTR_DONE = $B69B                 ;; returns the string just made as a function's result

;; Inherit: <ColorBasic:FIRSTC>
FIRSTC = $B6A4

LEFT_START = $B6AD                  ;; LEFT$ once its arguments are read: the string's first B characters

;; Inherit: <ColorBasic:GETBYT>
GETBYT = $B70B

;; Inherit: <ColorBasic:BYTCHK>
BYTCHK = $B70E

;; Inherit: <ColorBasic:ADRBYT>
ADRBYT = $B734

;; Inherit: <ColorBasic:COMBYT>
COMBYT = $B738

;; Inherit: <ColorBasic:GETADR>
GETADR = $B73D

;; Inherit: <ColorBasic:ADRCHK>
ADRCHK = $B740

;; Inherit: <ColorBasic:LIST>
LIST = $B764

;; Inherit: <ColorBasic:DETOK>
DETOK = $B7C2

DETOK_TABLE = $B7F3                 ;; detokenizing a line: the next ROM's table
DETOK_FIND = $B7F9                  ;; detokenizing a line, in a ROM's table: the token's place in it
CRUNCH_TABLE = $B89D                ;; CRUNCH's search of a ROM's words, with U at the table before it

CRUNCH_FUNCTIONS = $B8D4            ;; CRUNCH once the commands are searched: the functions' tables next

CRUNCH_SEARCH = $B8D7               ;; CRUNCH's step to the next ROM's table, or to the functions after the last

PRINT_AT_CURSOR = $B902             ;; PRINT @ once its position is read: moves the cursor there

PRINT_AT_COMMA = $B905              ;; PRINT @ with the cursor moved: the comma, then the rest of PRINT

;; Inherit: <ColorBasic:PRNTCR>
PRNTCR = $B958

;; Inherit: <ColorBasic:NEWLIN>
NEWLIN = $B95C

NEWLIN_CHECK = $B95F                ;; NEWLIN after SETPRM: a new line unless the device is at the start of one

;; Inherit: <ColorBasic:STROUT1>
STROUT1 = $B99C

;; Inherit: <ColorBasic:STRPRT>
STRPRT = $B99F

STRPRT_COUNT = $B9A2                ;; prints B characters from X

;; Inherit: <ColorBasic:OUTSPC>
OUTSPC = $B9AC

;; Inherit: <ColorBasic:OUTQST>
OUTQST = $B9AF

;; Inherit: <ColorBasic:ADDHLF>
ADDHLF = $B9B4

;; Inherit: <ColorBasic:FSUBX>
FSUBX = $B9B9

;; Inherit: <ColorBasic:FADDX>
FADDX = $B9C2

;; Inherit: <ColorBasic:FPADD>
FPADD = $B9C5

;; Inherit: <ColorBasic:NORMAL>
NORMAL = $BA1C

ZEROF0_EXP = $BA3A                  ;; sets FPA0's exponent and sign to A, so zero with A clear

;; Inherit: <ColorBasic:OVERR>
OVERR = $BA92

;; Inherit: <ColorBasic:FPONE>
FPONE = $BAC5

;; Inherit: <ColorBasic:FMULX>
FMULX = $BACA

;; Inherit: <ColorBasic:MULDIV>
MULDIV = $BB48

;; Inherit: <ColorBasic:MULDIV_SIGN>
MULDIV_SIGN = $BB5C

;; Inherit: <ColorBasic:MUL10>
MUL10 = $BB6A

;; Inherit: <ColorBasic:DIV10>
DIV10 = $BB82

;; Inherit: <ColorBasic:FDIVX>
FDIVX = $BB8F

;; Inherit: <ColorBasic:FPDIV>
FPDIV = $BB91

;; Inherit: <ColorBasic:MOVFM>
MOVFM = $BC14

;; Inherit: <ColorBasic:MOVV40>
MOVV40 = $BC2F

;; Inherit: <ColorBasic:MOVVAR>
MOVVAR = $BC33

;; Inherit: <ColorBasic:MOVMF>
MOVMF = $BC35

MOVFA_SIGN = $BC4C                  ;; MOVFA with FPA1's sign in A

;; Inherit: <ColorBasic:MOVAF>
MOVAF = $BC5F

;; Inherit: <ColorBasic:SIGN>
SIGN = $BC6D

FCOMP_SAME = $BCA0                  ;; compares FPA0 with the number at X, as FCOMP does, when their signs agree

;; Inherit: <ColorBasic:QINT>
QINT = $BCC8

;; Inherit: <ColorBasic:INT>
INT = $BCEE

;; Inherit: <ColorBasic:FADDB>
FADDB = $BD99

;; Inherit: <ColorBasic:FMAX9>
FMAX9 = $BDB6

;; Inherit: <ColorBasic:FMAX10>
FMAX10 = $BDBB

;; Inherit: <ColorBasic:FBILN>
FBILN = $BDC0

;; Inherit: <ColorBasic:INPRT>
INPRT = $BDC5

;; Inherit: <ColorBasic:LINPRT>
LINPRT = $BDCC

;; Inherit: <ColorBasic:FOUT>
FOUT = $BDD9

;; Inherit: <ColorBasic:FHALF>
FHALF = $BEC0

;; Inherit: <ColorBasic:FPWRTB>
FPWRTB = $BEC5

;; Inherit: <ColorBasic:NEGATE>
NEGATE = $BEE9

;; Inherit: <ColorBasic:ODDPOL>
ODDPOL = $BEF0

;; Inherit: <ColorBasic:POLYX>
POLYX = $BEFF

;; Inherit: <ColorBasic:SIN>
SIN = $BF78

SIN_NEGATE = $BFA6                  ;; the end of SIN: negates FPA0, then finishes the sine
