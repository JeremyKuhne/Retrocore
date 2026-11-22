;; COMMODORE BASIC: WORKSPACE AND SYSTEM ENTRIES
;;
;; These are addresses in RAM and the kernal jump table, not allocations or addresses of BASIC ROM routines.
;; Including this file emits no bytes and does not change the origin. The RAM code at <CHRGET> is copied there
;; by initialization; the ROM copy and the rest of the interpreter still need their own labels.
;;
;; The defaults describe BASIC 2. For either BASIC 1 revision, set <BUFPAG>=0, <BUFLEN>=80, <NULCMD>=1,
;; <FULL_STACK_TOP>=1, <STACK_RESERVE_19>=1, <TERMINAL_FIRST>=1, <LOCAL_TRMPOS>=1, <VARTXT_IN_LINNUM>=1,
;; <CLOCK_IN_PAGE2>=1, <STATUS_IN_PAGE2>=1, <RND_TIMER_9044>=1 and <ERROR_PADDING5>=1 before including this file.
;; For either BASIC 4 revision, set <DISK_STATUS_STRING>=1, <LINE_WIDTH_STORAGE>=0 and <EXTENDED_DISK_VECTORS>=1
;; instead. The chip revisions change code, not this workspace. Layouts that overlap kernal storage are rejected.
;;
;; The layout and names follow the <REALIO>=3 build of Microsoft's m6502.asm with the Basic1.mac, Basic2.mac and
;; Basic4.mac overlays. The two sign tokens and two error offsets below are the table constants needed by the
;; math package, not ROM addresses; a native dispatch table should use rather than redefine them.

.cpu Mos6502

; Microsoft configuration values used to place the workspace.
REALIO = 3                          ;; Microsoft build target: 3 selects Commodore I/O
.include "../../Microsoft6502Basic/MsBasic.Switches.asm"

.ifndef BUFPAG
BUFPAG = 2                          ;; input buffer page: 0 for page zero or 2 for page two
.endif
.ifndef BUFLEN
BUFLEN = 81                         ;; input buffer length in bytes
.endif
.ifndef NULCMD
NULCMD = 0                          ;; 1 reserves the NULL count byte; BASIC 1 has the code but no NULL token
.endif

; Independent changes in the terminal, interpreter and operating-system workspaces.
.ifndef TERMINAL_FIRST
TERMINAL_FIRST = 0                  ;; 1 places terminal storage before general scratch, including a page-zero buffer
.endif
.ifndef FULL_STACK_TOP
FULL_STACK_TOP = 0                  ;; 1 allows the stack to reach the top of page one instead of $01FB
.endif
.ifndef STACK_RESERVE_19
STACK_RESERVE_19 = 0                ;; 1 makes the stack check reserve 19 levels instead of 23
.endif
.ifndef LOCAL_TRMPOS
LOCAL_TRMPOS = 0                    ;; 1 reserves BASIC's own cursor position and names the early editor column
.endif
.ifndef LINE_WIDTH_STORAGE
LINE_WIDTH_STORAGE = 1               ;; 1 reserves the line-width and last-print-zone bytes
.endif
.ifndef DISK_STATUS_STRING
DISK_STATUS_STRING = 0              ;; 1 replaces output suppression with the three-byte disk-status descriptor
.endif
.ifndef VARTXT_IN_LINNUM
VARTXT_IN_LINNUM = 0                ;; 1 shares the variable-list pointer with the input line number
.endif
.ifndef CLOCK_IN_PAGE2
CLOCK_IN_PAGE2 = 0                  ;; 1 places the three-byte clock at $0200 rather than in page zero
.endif
.ifndef STATUS_IN_PAGE2
STATUS_IN_PAGE2 = 0                 ;; 1 places the I/O status byte at $020C rather than in page zero
.endif
.ifndef RND_TIMER_9044
RND_TIMER_9044 = 0                  ;; 1 makes RND(0) read from $9044 instead of the VIA at $E844
.endif
.ifndef ERROR_PADDING5
ERROR_PADDING5 = 0                  ;; 1 includes BASIC 1's five unused bytes in the long error table
.endif
.ifndef EXTENDED_DISK_VECTORS
EXTENDED_DISK_VECTORS = 0           ;; 1 includes the disk-command jump table below $FFC0
.endif

.ifndef NUMLEV
.if STACK_RESERVE_19
NUMLEV = 19                         ;; stack reserve, counted in two-byte levels
.else
NUMLEV = 23                         ;; stack reserve, counted in two-byte levels
.endif
.endif
.ifndef STKEND
.if FULL_STACK_TOP
STKEND = $01FF                      ;; upper stack limit
.else
STKEND = $01FB                      ;; upper stack limit
.endif
.endif

.assert BUFPAG = 0 || BUFPAG = 2, "BUFPAG is 0 or 2."
.assert BUFLEN > 0 && BUFLEN <= 255, "BUFLEN is 1 through 255."
.assert NULCMD = 0 || NULCMD = 1, "NULCMD is 0 or 1."
.assert INTPRC = 1 && ADDPRC = 1, "The PET workspace uses integer arrays and five-byte floats."
.assert STKEND >= $0100 && STKEND <= $01FF, "STKEND is in page one."
.assert NUMLEV > 0, "NUMLEV is positive."
.assert TERMINAL_FIRST = 0 || TERMINAL_FIRST = 1, "TERMINAL_FIRST is 0 or 1."
.assert FULL_STACK_TOP = 0 || FULL_STACK_TOP = 1, "FULL_STACK_TOP is 0 or 1."
.assert STACK_RESERVE_19 = 0 || STACK_RESERVE_19 = 1, "STACK_RESERVE_19 is 0 or 1."
.assert LOCAL_TRMPOS = 0 || LOCAL_TRMPOS = 1, "LOCAL_TRMPOS is 0 or 1."
.assert LINE_WIDTH_STORAGE = 0 || LINE_WIDTH_STORAGE = 1, "LINE_WIDTH_STORAGE is 0 or 1."
.assert DISK_STATUS_STRING = 0 || DISK_STATUS_STRING = 1, "DISK_STATUS_STRING is 0 or 1."
.assert VARTXT_IN_LINNUM = 0 || VARTXT_IN_LINNUM = 1, "VARTXT_IN_LINNUM is 0 or 1."
.assert CLOCK_IN_PAGE2 = 0 || CLOCK_IN_PAGE2 = 1, "CLOCK_IN_PAGE2 is 0 or 1."
.assert STATUS_IN_PAGE2 = 0 || STATUS_IN_PAGE2 = 1, "STATUS_IN_PAGE2 is 0 or 1."
.assert RND_TIMER_9044 = 0 || RND_TIMER_9044 = 1, "RND_TIMER_9044 is 0 or 1."
.assert ERROR_PADDING5 = 0 || ERROR_PADDING5 = 1, "ERROR_PADDING5 is 0 or 1."
.assert EXTENDED_DISK_VECTORS = 0 || EXTENDED_DISK_VECTORS = 1, "EXTENDED_DISK_VECTORS is 0 or 1."

; Sizes and terminal constants from the Microsoft build.
STRSIZ = 3                          ;; bytes in a string descriptor: length followed by a two-byte pointer
NUMTMP = 3                          ;; number of temporary string descriptors
LINLEN = 40                         ;; default terminal line width
CLMWID = 10                         ;; width of a print zone
NCMPOS = ((LINLEN / CLMWID) - 1) * CLMWID ;; column beyond which there are no more print zones
CONTW = 15                          ;; Control-O, the output-suppression character
PI = 255                            ;; PET's single-character PI token
RAMLOC = $0400                      ;; Microsoft build's initial RAM location, not the current memory limit

; The writable USR jump is followed either by the terminal block or by general scratch.
USRPOK = $00                        ;; three-byte writable jump used by USR
.if TERMINAL_FIRST
CHANNL = USRPOK + 3                 ;; current logical channel number
.else
CHANNL = TANSGN + 2 + 2 * DISK_STATUS_STRING ;; current logical channel number, after the flags
.endif
.if NULCMD
NULCNT = CHANNL + 1                 ;; number of NULL characters to print
.endif
.if LOCAL_TRMPOS
TRMPOS = CHANNL + 1 + NULCMD        ;; BASIC's own terminal position
CQPNTR = $E2                        ;; early screen editor's cursor column, used when <TRMPOS> wraps
.else
TRMPOS = $C6                        ;; screen editor's terminal position
.endif
.if LINE_WIDTH_STORAGE
LINWID = CHANNL + 1 + NULCMD + LOCAL_TRMPOS ;; stored terminal line width
NCMWID = LINWID + 1                 ;; stored last print-zone column
.endif
LINNUM = CHANNL + 1 + NULCMD + LOCAL_TRMPOS + 2 * LINE_WIDTH_STORAGE ;; two-byte input line number, shared with <POKER>
.if BUFPAG = 0
BUF = LINNUM + 2                    ;; page-zero input buffer after the line-number and comma bytes
.else
BUF = BUFPAG * 256                  ;; page-two input and tokenization buffer
.endif
BUFOFS = BUFPAG * 256               ;; page base used when indexing the input buffer

; General scratch and flags; aliases deliberately share their storage.
.if TERMINAL_FIRST
.if BUFPAG = 0
CHARAC = BUF + BUFLEN               ;; delimiter character after the page-zero input buffer
.else
CHARAC = LINNUM + 2                 ;; delimiter character after the terminal block
.endif
.else
CHARAC = USRPOK + 3                 ;; delimiter character after the USR jump
.endif
INTEGR = CHARAC                     ;; one-byte integer result, sharing <CHARAC>
ENDCHR = CHARAC + 1                 ;; second delimiter character
COUNT = ENDCHR + 1                  ;; general counter
DIMFLG = COUNT + 1                  ;; array-dimensioning flag, immediately before <VALTYP>
KIMY = DIMFLG                       ;; Microsoft output scratch sharing <DIMFLG>
VALTYP = DIMFLG + 1                 ;; value type: zero for numeric, $FF for string
INTFLG = VALTYP + 1                 ;; integer-variable type flag
DORES = INTFLG + 1                  ;; tokenizer flag suppressing reserved words in DATA, shared with <GARBFL>
GARBFL = DORES                      ;; garbage-collection flag sharing <DORES>
SUBFLG = DORES + 1                  ;; suppresses subscripted-variable recognition
INPFLG = SUBFLG + 1                 ;; distinguishes INPUT from READ
TANSGN = INPFLG + 1                 ;; tangent sign scratch, shared with <DOMASK>
.if DISK_STATUS_STRING
DSDESC = TANSGN + 1                 ;; three-byte DS$ disk-status string descriptor
.else
CNTWFL = TANSGN + 1                 ;; output-suppression flag
.endif

; Three temporary descriptors, arithmetic scratch and dynamic-memory pointers.
.if TERMINAL_FIRST
.if DISK_STATUS_STRING
TEMPPT = DSDESC + 3                 ;; page-zero pointer to the next free temporary descriptor
.else
TEMPPT = CNTWFL + 1                 ;; page-zero pointer to the next free temporary descriptor
.endif
.else
.if BUFPAG = 0
TEMPPT = BUF + BUFLEN               ;; page-zero pointer to the next free temporary descriptor
.else
TEMPPT = LINNUM + 2                 ;; page-zero pointer to the next free temporary descriptor
.endif
.endif
LASTPT = TEMPPT + 1                 ;; two-byte pointer to the last-used temporary descriptor
TEMPST = LASTPT + 2                  ;; three consecutive three-byte temporary string descriptors
INDEX1 = TEMPST + STRSIZ * NUMTMP   ;; two-byte index scratch, also named <INDEX>
INDEX = INDEX1                      ;; two-byte index scratch, also named <INDEX1>
INDEX2 = INDEX1 + 2                 ;; second two-byte index scratch
RESHO = INDEX2 + 2                  ;; high byte of multiplication or division result scratch
RESMOH = RESHO + 1                  ;; second byte of multiplication or division result scratch
RESMO = RESMOH + 1                  ;; third result byte, shared with <ADDEND>
RESLO = RESMO + 1                   ;; low byte of multiplication or division result scratch
ADDEND = RESMO                      ;; multiplication addend scratch, sharing <RESMO>
TXTTAB = RESLO + 2                  ;; two-byte pointer to the first program line, after the result overflow byte
VARTAB = TXTTAB + 2                 ;; two-byte pointer to simple variables after the program
ARYTAB = VARTAB + 2                 ;; two-byte pointer to arrays after the simple variables
STREND = ARYTAB + 2                 ;; two-byte pointer to the end of variable and array storage
FRETOP = STREND + 2                 ;; two-byte pointer to the bottom of allocated string space
FRESPC = FRETOP + 2                 ;; two-byte pointer to a newly allocated string
MEMSIZ = FRESPC + 2                 ;; two-byte upper limit of BASIC's string storage
CURLIN = MEMSIZ + 2                 ;; current two-byte line number; its high byte is $FF for direct execution
OLDLIN = CURLIN + 2                 ;; two-byte line number saved for CONT
POKER = LINNUM                      ;; two-byte POKE and WAIT address scratch, sharing <LINNUM>
OLDTXT = OLDLIN + 2                 ;; two-byte text pointer saved for CONT
DATLIN = OLDTXT + 2                 ;; two-byte line number of the current DATA statement
DATPTR = DATLIN + 2                 ;; two-byte pointer into DATA for READ
INPPTR = DATPTR + 2                 ;; two-byte pointer into input for INPUT or READ

; Variable, expression and transfer scratch.
VARNAM = INPPTR + 2                 ;; two-byte encoded variable name
VARPNT = VARNAM + 2                 ;; two-byte pointer to a variable's value, shared with <FDECPT>
FDECPT = VARPNT                     ;; power-of-ten table pointer for numeric output, sharing <VARPNT>
FORPNT = VARPNT + 2                 ;; two-byte FOR or assignment pointer, also used for the WAIT masks
LSTPNT = FORPNT                     ;; two-byte string-list pointer, sharing <FORPNT>
ANDMSK = FORPNT                     ;; WAIT AND mask, sharing the first byte of <FORPNT>
EORMSK = FORPNT + 1                 ;; WAIT exclusive-OR mask, sharing the second byte of <FORPNT>
OPPTR = FORPNT + 2                  ;; two-byte pointer to the current operator table entry
.if VARTXT_IN_LINNUM
VARTXT = LINNUM                     ;; variable-list pointer sharing <LINNUM>
.else
VARTXT = OPPTR                      ;; variable-list pointer sharing <OPPTR>
.endif
OPMASK = OPPTR + 2                  ;; current relational-operator mask
DOMASK = TANSGN                     ;; relation-operation mask, sharing <TANSGN>
DEFPNT = OPMASK + 1                 ;; two-byte function-definition pointer, shared with <GRBPNT> and <TEMPF3>
GRBPNT = DEFPNT                     ;; garbage-collection pointer, sharing <DEFPNT>
DSCPNT = DEFPNT + 2                 ;; two-byte pointer to a string descriptor
FOUR6 = DSCPNT + 3                  ;; garbage collector's descriptor-size scratch, after the extra temporary byte
JMPER = FOUR6 + 1                   ;; writable three-byte jump whose operand bytes are <SIZE> and <OLDOV>
SIZE = JMPER + 1                    ;; first operand byte of <JMPER>, also size scratch
OLDOV = JMPER + 2                   ;; second operand byte of <JMPER>, also saved floating-point overflow
TEMPF3 = DEFPNT                     ;; five-byte floating-point temporary overlapping <DEFPNT> and <DSCPNT>
TEMPF1 = JMPER + 3                  ;; five-byte floating-point temporary overlapping transfer scratch
HIGHDS = TEMPF1 + 1                 ;; two-byte end of the destination block, shared with <ARYPNT>
HIGHTR = HIGHDS + 2                 ;; two-byte end of the source block
TEMPF2 = HIGHTR + 2                 ;; five-byte floating-point temporary overlapping transfer scratch
LOWDS = TEMPF2 + 1                  ;; two-byte transfer scratch, shared with <DECCNT> and <TENEXP>
LOWTR = LOWDS + 2                   ;; two-byte start of the source block, shared with <GRBTOP>
ARYPNT = HIGHDS                     ;; two-byte array-building pointer, sharing <HIGHDS>
GRBTOP = LOWTR                      ;; two-byte garbage-collection pointer, sharing <LOWTR>
DECCNT = LOWDS                      ;; decimal digit-count scratch, sharing <LOWDS>
TENEXP = LOWDS + 1                  ;; decimal exponent scratch, sharing the second byte of <LOWDS>
DPTFLG = LOWTR                      ;; decimal-point flag, sharing the first byte of <LOWTR>
EXPSGN = LOWTR + 1                  ;; decimal exponent sign flag, sharing the second byte of <LOWTR>

; Unpacked floating-point accumulators and reused string scratch.
FAC = LOWTR + 2                     ;; floating-point accumulator, also descriptor scratch <DSCTMP>
FACEXP = FAC                        ;; exponent of <FAC>
FACHO = FACEXP + 1                  ;; high mantissa byte of <FAC>
FACMOH = FACHO + 1                  ;; second mantissa byte of <FAC>
FACMO = FACMOH + 1                  ;; third mantissa byte of <FAC>, shared with <INDICE>
FACLO = FACMO + 1                   ;; low mantissa byte of <FAC>
FACSGN = FACLO + 1                  ;; unpacked sign of <FAC>
SGNFLG = FACSGN + 1                 ;; saved accumulator sign, shared with <DEGREE>
DEGREE = SGNFLG                     ;; polynomial degree counter, sharing <SGNFLG>
DSCTMP = FAC                        ;; temporary string descriptor built in <FAC>
INDICE = FACMO                      ;; integer-conversion scratch, sharing <FACMO>
BITS = SGNFLG + 1                   ;; shift-count scratch for floating-point operations
ARGEXP = BITS + 1                   ;; floating-point argument exponent
ARGHO = ARGEXP + 1                  ;; high mantissa byte of the floating-point argument
ARGMOH = ARGHO + 1                  ;; second mantissa byte of the floating-point argument
ARGMO = ARGMOH + 1                  ;; third mantissa byte of the floating-point argument
ARGLO = ARGMO + 1                   ;; low mantissa byte of the floating-point argument
ARGSGN = ARGLO + 1                  ;; unpacked sign of the floating-point argument
ARISGN = ARGSGN + 1                 ;; arithmetic result-sign scratch, shared with <STRNG1>
FACOV = ARISGN + 1                  ;; floating-point accumulator overflow byte
STRNG1 = ARISGN                     ;; two-byte string or descriptor pointer, sharing <ARISGN> and <FACOV>
FBUFPT = FACOV + 1                  ;; two-byte numeric-output pointer, shared with <BUFPTR>, <STRNG2>, <POLYPT> and <CURTOL>
BUFPTR = FBUFPT                     ;; two-byte tokenizer buffer pointer, sharing <FBUFPT>
STRNG2 = FBUFPT                     ;; two-byte string or descriptor pointer, sharing <FBUFPT>
POLYPT = FBUFPT                     ;; two-byte polynomial-coefficient pointer, sharing <FBUFPT>
CURTOL = FBUFPT                     ;; two-byte linear array index, sharing <FBUFPT>

; Addresses of code and data copied into RAM, followed by the page-one output buffer.
CHRGET = FBUFPT + 2                 ;; character-fetch entry in the code copied to page zero
CHRGOT = CHRGET + 6                 ;; fetch entry that does not increment <TXTPTR>
TXTPTR = CHRGOT + 1                 ;; two-byte load operand in <CHRGOT>, the current BASIC text pointer
QNUM = CHRGOT + 7                   ;; character-classification entry in the copied <CHRGET> code
CHRRTS = QNUM + 10                  ;; return instruction in the copied <CHRGET> code
RNDX = CHRRTS + 1                   ;; five-byte packed random-number state
LOFBUF = $FF                        ;; byte immediately before <FBUFFR>, usable by STR$ output
FBUFFR = LOFBUF + 1                 ;; sixteen-byte numeric output buffer at the bottom of page one
.assert RNDX + 5 <= LOFBUF, "The page-zero workspace must not overlap LOFBUF."

; Operating-system state and RND(0)'s read addresses.
.if CLOCK_IN_PAGE2
CQTIMR = $0200                      ;; three-byte clock in the early kernal's page-two workspace
.else
CQTIMR = $8D                        ;; three-byte clock in page zero
.endif
.if STATUS_IN_PAGE2
CQSTAT = $020C                      ;; I/O status byte in the early kernal's page-two workspace
.else
CQSTAT = $96                        ;; I/O status byte in page zero
.endif
.if RND_TIMER_9044
CQHTIM = $9044                      ;; RND(0) reads here and at offsets 1, 4 and 5, not the VIA timer
.else
CQHTIM = $E844                      ;; RND(0) reads the VIA timer registers at offsets 0, 1, 4 and 5
.endif
.if CLOCK_IN_PAGE2 = 0
.assert RNDX + 5 <= CQTIMR, "The BASIC workspace must not overlap the page-zero clock."
.endif
.if STATUS_IN_PAGE2 = 0
.assert RNDX + 5 <= CQSTAT, "The BASIC workspace must not overlap the page-zero I/O status."
.endif
.if LOCAL_TRMPOS
.assert RNDX + 5 <= CQPNTR, "The BASIC workspace must not overlap the editor's cursor column."
.else
.assert RNDX + 5 <= TRMPOS, "The BASIC workspace must not overlap the editor's terminal position."
.endif
.if BUFPAG = 2
.if CLOCK_IN_PAGE2
.assert BUF + BUFLEN <= CQTIMR || BUF >= CQTIMR + 3, "The input buffer must not overlap the clock."
.endif
.if STATUS_IN_PAGE2
.assert BUF + BUFLEN <= CQSTAT || BUF > CQSTAT, "The input buffer must not overlap the I/O status."
.endif
.endif
.assert STKEND - FBUFFR > 2 * NUMLEV + 16, "NUMLEV's stack reserve must fit above FBUFFR."

; PET kernal jump table, named as Microsoft's BASIC calls its entries.
CQOPEN = $FFC0                      ;; execute BASIC's OPEN
CQCLOS = CQOPEN + 3                 ;; execute BASIC's CLOSE
CQOIN = CQCLOS + 3                  ;; select a logical channel for input
CQOOUT = CQOIN + 3                  ;; select a logical channel for output
CQCCHN = CQOOUT + 3                 ;; restore the default input and output channels
CQINCH = CQCCHN + 3                 ;; read a character from the current input
OUTCH = CQINCH + 3                  ;; write a character to the current output
CQLOAD = OUTCH + 3                  ;; execute BASIC's LOAD
CQSAVE = CQLOAD + 3                 ;; execute BASIC's SAVE
CQVERF = CQSAVE + 3                 ;; execute BASIC's VERIFY
CQSYS = CQVERF + 3                  ;; execute BASIC's SYS
ISCNTC = CQSYS + 3                  ;; test the STOP key
CZGETL = ISCNTC + 3                 ;; get one character for BASIC's GET
CQCALL = CZGETL + 3                 ;; close all open channels

.if EXTENDED_DISK_VECTORS
CQCONC = CQOPEN - 45                ;; concatenate two files
CQDOPN = CQCONC + 3                 ;; open a disk file
CQDCLS = CQDOPN + 3                 ;; close disk files
CQRECD = CQDCLS + 3                 ;; position a relative record
CQFORM = CQRECD + 3                 ;; prepare disk media
CQCOLL = CQFORM + 3                 ;; validate the disk block allocation map
CQBACK = CQCOLL + 3                 ;; copy a whole disk
CQCOPY = CQBACK + 3                 ;; copy a file
CQAPND = CQCOPY + 3                 ;; open a file to append
CQDSAV = CQAPND + 3                 ;; save a BASIC program to disk
CQDLOD = CQDSAV + 3                 ;; load a BASIC program from disk
CQDCAT = CQDLOD + 3                 ;; list a disk directory
CQRENM = CQDCAT + 3                 ;; rename a disk file
CQSCRA = CQRENM + 3                 ;; scratch a disk file
CQRDDS = CQSCRA + 3                 ;; read the disk status
.endif

; Scalar values from the token and long-error tables, used by the math package.
PLUSTK = $AA                        ;; token for the plus operator
MINUTK = PLUSTK + 1                 ;; token for the minus operator
ERROV = 16 + 6 + 20 + 11 + 16 + 5 * ERROR_PADDING5 ;; offset of OVERFLOW in the long error table
ERRDV0 = ERROV + 8 + 13 + 17 + 13 + 13 ;; offset of DIVISION BY ZERO in the long error table
