;; APPLESOFT: BUILD CONSTANTS, WORKSPACE AND MACHINE ADDRESSES
;;
;; These equates name existing RAM and ROM locations; they allocate no workspace. The configuration symbols
;; retain the intermediate assignments of the Microsoft expansion, but changing them does not regenerate this
;; already-expanded listing. In particular, <ROMLOC> and <RAMLOC> are build history, not runtime memory limits.
;;
;; The two-byte pointers <TXTTAB>, <VARTAB>, <ARYTAB> and <STREND> delimit the program, simple variables,
;; arrays and free memory in ascending order. Strings occupy the high end of memory down to <FRETOP>, below
;; <MEMSIZ>. Most zero-page storage is reused: aliases below name the same bytes for different phases, and
;; writing one alias overwrites the others. Monitor and graphics locations overlap other scratch as noted.

.org $0000

; Microsoft build configuration; .set assignments retain their original order.
REALIO = $04                        ;; Microsoft build target: 4 selects Apple II I/O
INTPRC = $01                        ;; Microsoft build switch for integer arrays
ADDPRC = $01                        ;; Microsoft build switch for the extra mantissa byte
LNGERR = $01                        ;; Microsoft build switch for full error messages
TIME = $00                          ;; Microsoft build switch for clock support
EXTIO = $00                         ;; Microsoft build switch for external channel I/O
DISKO = $00                         ;; Microsoft build switch for disk commands
NULCMD .set $01                     ;; Microsoft build switch for the NULL command
GETCMD .set $01                     ;; Microsoft build switch for the GET command
RORSW .set $01                      ;; Microsoft build switch for the hardware rotate instruction
ROMSW = $01                         ;; Microsoft build switch for ROM-resident BASIC
CLMWID = $0E                        ;; Microsoft build's print-zone width
LONGI = $01                         ;; Microsoft build switch for long initialization
STKEND .set $01FF                   ;; Microsoft build's upper stack limit
BUFPAG .set $00                     ;; Microsoft build's input buffer page
LINLEN .set $48                     ;; Microsoft build's terminal line width
BUFLEN .set $48                     ;; Microsoft build's input buffer length
ROMLOC .set $2000                   ;; Microsoft build's ROM origin
KIMROM .set $01                     ;; Microsoft build switch for KIM ROM
KIMROM .set $00                     ;; Microsoft build switch for KIM ROM
RAMLOC .set $4000                   ;; Microsoft build's RAM origin
RORSW .set $01                      ;; Microsoft build switch for the hardware rotate instruction
NULCMD .set $00                     ;; Microsoft build switch for the NULL command
GETCMD .set $01                     ;; Microsoft build switch for the GET command
CQINLN = $FD67                      ;; Monitor line-input entry used by the Microsoft build
CQPRMP = $33                        ;; Monitor prompt character location
CQINCH = $FD0C                      ;; Monitor character-input entry
CQCOUT = $FECD                      ;; Monitor cassette-write entry in the Microsoft build
CQCSIN = $FEFD                      ;; Monitor cassette-read entry in the Microsoft build
BUFPAG .set $02                     ;; Microsoft build's input buffer page
BUF = $0200                         ;; line input and tokenization buffer in page two
ROMLOC .set $D000                   ;; Microsoft build's ROM origin
RAMLOC .set $2A00                   ;; Microsoft build's RAM origin
OUTCH = $FDED                       ;; Monitor character-output entry
CZGETL = $FD0C                      ;; Monitor character-input entry used by GET
LINLEN .set $28                     ;; Microsoft build's terminal line width
BUFLEN .set $F0                     ;; Microsoft build's input buffer length
RORSW .set $01                      ;; Microsoft build switch for the hardware rotate instruction
STKEND .set $01FB                   ;; Microsoft build's upper stack limit
NUMLEV = $17                        ;; generic Microsoft stack reserve in two-byte levels; Apple uses a different reserve in <GETSTK>
STRSIZ = $03                        ;; bytes in a string descriptor
NUMTMP = $03                        ;; number of temporary string descriptors
CONTW = $0F                         ;; Control-O, the output-suppression character

; Page-zero entry vectors and general interpreter scratch.
START = $00                         ;; page-zero restart jump, initialized to <MAIN>
RDYJSR = $03                        ;; page-zero jump initialized to <STROUT>
ADRAYI = $06                        ;; page-zero vector for floating-point to signed-integer conversion
ADRGAY = $08                        ;; page-zero vector for signed-integer to floating-point conversion
USRPOK = $0A                        ;; writable jump vector used by USR
CHARAC = $0D                        ;; delimiter character, shared with <INTEGR>
INTEGR = $0D                        ;; one-byte integer result, sharing <CHARAC>
ENDCHR = $0E                        ;; second delimiter character
COUNT = $0F                         ;; general counter
DIMFLG = $10                        ;; array-dimensioning flag, shared with <KIMY>
KIMY = $10                          ;; saved Y for output in the Microsoft source, sharing <DIMFLG>
VALTYP = $11                        ;; value-type flag, negative for a string and clear for a number
INTFLG = $12                        ;; integer-variable type flag
DORES = $13                         ;; tokenizer flag suppressing reserved-word recognition in DATA, shared with <GARBFL>
GARBFL = $13                        ;; string allocation and garbage-collection flag, sharing <DORES>
SUBFLG = $14                        ;; flag suppressing subscripted-variable recognition for FOR and user functions
INPFLG = $15                        ;; distinguishes INPUT from READ
TANSGN = $16                        ;; tangent sign scratch, shared with <DOMASK>
CNTWFL = $8F                        ;; output-suppression flag in the Microsoft source, sharing <FOUR6>
TRMPOS = $24                        ;; terminal position alias of <CH>
LINWID = $25                        ;; terminal width alias of <CV>
NCMWID = $70                        ;; Microsoft print-zone limit alias of the high byte of <FRETOP>

; Temporary descriptors, arithmetic scratch and dynamic-memory pointers.
LINNUM = $50                        ;; two-byte line number during input, shared with <POKER>
TEMPPT = $52                        ;; page-zero pointer to the next free temporary string descriptor
LASTPT = $53                        ;; two-byte pointer to the last-used temporary descriptor
TEMPST = $55                        ;; three consecutive three-byte temporary string descriptors
INDEX1 = $5E                        ;; two-byte index scratch, also named <INDEX>
INDEX = $5E                         ;; two-byte index scratch, also named <INDEX1>
INDEX2 = $60                        ;; second two-byte index scratch
RESHO = $62                         ;; high byte of multiplication or division result scratch
RESMOH = $63                        ;; next byte of multiplication or division result scratch
RESMO = $64                         ;; middle byte of result scratch, shared with <ADDEND>
RESLO = $65                         ;; low byte of multiplication or division result scratch
ADDEND = $64                        ;; multiplication addend scratch, sharing <RESMO>
TXTTAB = $67                        ;; two-byte pointer to the first program line
VARTAB = $69                        ;; two-byte pointer to the simple variables after the program
ARYTAB = $6B                        ;; two-byte pointer to the first array after the simple variables
STREND = $6D                        ;; two-byte pointer to the end of array and simple-variable storage
FRETOP = $6F                        ;; two-byte pointer to the bottom of allocated string space
FRESPC = $71                        ;; two-byte pointer to a newly allocated string
MEMSIZ = $73                        ;; two-byte upper limit of BASIC's string storage
CURLIN = $75                        ;; two-byte current line number; its high byte is $FF for direct execution
OLDLIN = $77                        ;; two-byte saved line number for CONT
POKER = $50                         ;; two-byte POKE address scratch, sharing <LINNUM>
OLDTXT = $79                        ;; two-byte saved text pointer for CONT
DATLIN = $7B                        ;; two-byte line number of the current DATA statement
DATPTR = $7D                        ;; two-byte pointer into DATA for READ
INPPTR = $7F                        ;; two-byte pointer into input for INPUT or READ

; Variable, expression, transfer and floating-point scratch; aliases overlap.
VARNAM = $81                        ;; two-byte encoded variable name
VARPNT = $83                        ;; two-byte pointer to a variable's value, shared with <FDECPT>
FDECPT = $83                        ;; power-of-ten table pointer for numeric output, sharing <VARPNT>
FORPNT = $85                        ;; two-byte FOR or assignment variable pointer, shared with <LSTPNT> and WAIT masks
LSTPNT = $85                        ;; two-byte string-list pointer, sharing <FORPNT>
ANDMSK = $85                        ;; WAIT AND mask, sharing the first byte of <FORPNT>
EORMSK = $86                        ;; WAIT exclusive-OR mask, sharing the second byte of <FORPNT>
OPPTR = $87                         ;; two-byte pointer to an <OPTAB> entry, shared with <VARTXT>
VARTXT = $87                        ;; two-byte variable-text pointer, sharing <OPPTR>
OPMASK = $89                        ;; current relational-operator mask
DOMASK = $16                        ;; relation-operation mask, sharing <TANSGN>
DEFPNT = $8A                        ;; two-byte function-definition pointer, shared with <GRBPNT> and <TEMPF3>
GRBPNT = $8A                        ;; two-byte garbage-collection pointer, sharing <DEFPNT>
DSCPNT = $8C                        ;; two-byte pointer to a string descriptor
FOUR6 = $8F                         ;; garbage collector's descriptor size scratch, sharing <CNTWFL>
JMPER = $90                         ;; writable page-zero jump instruction, followed by <SIZE> and <OLDOV>
SIZE = $91                          ;; first operand byte of <JMPER>, also size scratch
OLDOV = $92                         ;; second operand byte of <JMPER>, also saved floating-point overflow
TEMPF3 = $8A                        ;; packed floating-point temporary, sharing <DEFPNT>
TEMPF1 = $93                        ;; packed floating-point temporary overlapping transfer scratch
HIGHDS = $94                        ;; two-byte end of the destination block for <BLTU>, shared with <ARYPNT>
HIGHTR = $96                        ;; two-byte end of the source block for <BLTU>
TEMPF2 = $98                        ;; packed floating-point temporary overlapping transfer scratch
LOWDS = $99                         ;; transfer scratch, shared with decimal-conversion scratch <DECCNT>
LOWTR = $9B                         ;; two-byte start of the source block for <BLTU>, shared with <GRBTOP>
ARYPNT = $94                        ;; two-byte array-building pointer, sharing <HIGHDS>
GRBTOP = $9B                        ;; two-byte garbage-collection pointer, sharing <LOWTR>
DECCNT = $99                        ;; decimal digit-count scratch, sharing <LOWDS>
TENEXP = $9A                        ;; decimal exponent scratch, sharing <LOWDS>+1
DPTFLG = $9B                        ;; decimal-point flag, sharing <LOWTR>
EXPSGN = $9C                        ;; decimal exponent sign flag, sharing <LOWTR>+1
FAC = $9D                           ;; floating-point accumulator, also descriptor scratch <DSCTMP>
FACEXP = $9D                        ;; floating-point accumulator exponent
FACHO = $9E                         ;; high mantissa byte of <FAC>
FACMOH = $9F                        ;; second mantissa byte of <FAC>
FACMO = $A0                         ;; third mantissa byte of <FAC>, shared with <INDICE>
FACLO = $A1                         ;; low mantissa byte of <FAC>
FACSGN = $A2                        ;; unpacked sign of <FAC>
SGNFLG = $A3                        ;; saved accumulator sign, shared with <DEGREE>
DEGREE = $A3                        ;; polynomial degree counter, sharing <SGNFLG>
DSCTMP = $9D                        ;; temporary string descriptor built in <FAC>
INDICE = $A0                        ;; integer conversion scratch, sharing <FACMO>
BITS = $A4                          ;; shift-count scratch for floating-point operations
ARGEXP = $A5                        ;; floating-point argument exponent
ARGHO = $A6                         ;; high mantissa byte of the floating-point argument
ARGMOH = $A7                        ;; second mantissa byte of the floating-point argument
ARGMO = $A8                         ;; third mantissa byte of the floating-point argument
ARGLO = $A9                         ;; low mantissa byte of the floating-point argument
ARGSGN = $AA                        ;; unpacked sign of the floating-point argument
ARISGN = $AB                        ;; arithmetic result-sign scratch, shared with <STRNG1>
FACOV = $AC                         ;; floating-point accumulator overflow byte
STRNG1 = $AB                        ;; two-byte string or descriptor pointer, sharing <ARISGN>
FBUFPT = $AD                        ;; two-byte pointer into the numeric output buffer, shared with <BUFPTR>, <STRNG2>, <POLYPT> and <CURTOL>
BUFPTR = $AD                        ;; two-byte tokenizer buffer pointer, sharing <FBUFPT>
STRNG2 = $AD                        ;; two-byte string or descriptor pointer, sharing <FBUFPT>
POLYPT = $AD                        ;; two-byte polynomial-coefficient pointer, sharing <FBUFPT>
CURTOL = $AD                        ;; two-byte linear array index, sharing <FBUFPT>

; Character-fetch code copied to page zero, random state and page-one output buffer.
CHRGET = $B1                        ;; page-zero character-fetch entry copied from <INITAT>
CHRGOT = $B7                        ;; page-zero entry to fetch without incrementing <TXTPTR>
TXTPTR = $B8                        ;; two-byte operand of the load in <CHRGOT>, the current text pointer
QNUM = $BE                          ;; character classification entry in the page-zero <CHRGET> code
CHRRTS = $C8                        ;; return in the page-zero <CHRGET> code
RNDX = $C9                          ;; five-byte floating-point random-number state
LOFBUF = $FF                        ;; low byte immediately preceding <FBUFFR> at the page boundary
FBUFFR = $0100                      ;; numeric output buffer in page one, below the stack

; Monitor workspace and Apple II graphics state.
WNDLFT = $20                        ;; Monitor text window's left edge
WNDWDT = $21                        ;; Monitor text window width
WNDTOP = $22                        ;; Monitor text window's top edge
WNDBTM = $23                        ;; Monitor text window's bottom edge
CH = $24                            ;; Monitor cursor column, shared with <TRMPOS>
CV = $25                            ;; Monitor cursor row, shared with <LINWID>
GBASL = $26                         ;; low byte of the Monitor lo-res graphics base address
GBASH = $27                         ;; high byte of <GBASL>
BASL = $28                          ;; low byte of the Monitor text row base address
BASH = $29                          ;; high byte of <BASL>
H2 = $2C                            ;; Monitor lo-res horizontal line endpoint
V2 = $2D                            ;; Monitor lo-res vertical line endpoint
MASK = $2E                          ;; Monitor lo-res color mask
LENGTH = $2F                        ;; Monitor length scratch
COLOR = $30                         ;; Monitor lo-res color
MODE = $31                          ;; Monitor mode scratch
INVFLG = $32                        ;; Monitor normal, inverse or flashing text mask
PROMPT = $33                        ;; Monitor prompt character
YSAV = $34                          ;; Monitor Y-register scratch
YSAV1 = $35                         ;; additional Monitor Y-register scratch
CSWL = $36                          ;; low byte of the Monitor character-output vector
CSWH = $37                          ;; high byte of <CSWL>
KSWL = $38                          ;; low byte of the Monitor character-input vector
KSWH = $39                          ;; high byte of <KSWL>
PCL = $3A                           ;; low byte of the Monitor program counter
PCH = $3B                           ;; high byte of <PCL>
A1L = $3C                           ;; low byte of the Monitor first address parameter
A1H = $3D                           ;; high byte of <A1L>
A2L = $3E                           ;; low byte of the Monitor second address parameter
A2H = $3F                           ;; high byte of <A2L>
A3L = $40                           ;; low byte of the Monitor third address parameter
A3H = $41                           ;; high byte of <A3L>
A4L = $42                           ;; low byte of the Monitor fourth address parameter
A4H = $43                           ;; high byte of <A4L>
A5L = $44                           ;; low byte of the Monitor fifth address parameter
A5H = $45                           ;; high byte of <A5L>
XREG = $46                          ;; Monitor saved X register
YREG = $47                          ;; Monitor saved Y register
STATUS = $48                        ;; Monitor saved processor status
RNDL = $4E                          ;; low byte of the Monitor keyboard timing counter
RNDH = $4F                          ;; high byte of <RNDL>
SHAPEL = $1A                        ;; low byte of the shape or hi-res clear pointer
SHAPEH = $1B                        ;; high byte of <SHAPEL>
HCOLR2 = $1C                        ;; hi-res color byte being drawn
HCOUNT = $1D                        ;; hi-res line step count
PRGEND = $AF                        ;; two-byte saved program end
HGRDX = $D0                         ;; two-byte hi-res line X distance
HGRDY = $D2                         ;; hi-res line Y distance
HGRQUA = $D3                        ;; hi-res line quadrant
HGRE = $D4                          ;; hi-res line error term
LOCK = $D6                          ;; run-only flag; bit 7 prevents listing and editing
ERRFLG = $D8                        ;; ONERR flag; bit 7 indicates an active handler
ERRLIN = $DA                        ;; two-byte line number of the last error
ERRPOS = $DC                        ;; two-byte text pointer at the last error
ERRNUM = $DE                        ;; last error code
ERRSTK = $DF                        ;; stack pointer at the last error
HGRX = $E0                          ;; two-byte current hi-res X coordinate
HGRY = $E2                          ;; current hi-res Y coordinate
HCOLR1 = $E4                        ;; hi-res color byte
HNDX = $E5                          ;; hi-res byte index in the row
HPAG = $E6                          ;; hi-res page high byte, $20 or $40
HSCALE = $E7                        ;; shape scale
SHPTBL = $E8                        ;; two-byte shape-table address
COLCNT = $EA                        ;; shape collision count
FIRST = $F0                         ;; lo-res plotting scratch
SPEEDZ = $F1                        ;; output delay, represented as 256 minus SPEED
TRCFLG = $F2                        ;; TRACE flag, enabled when bit 7 is set
FLASHB = $F3                        ;; flashing text mask
TXTPSV = $F4                        ;; two-byte text pointer saved for RESUME
CURLSV = $F6                        ;; two-byte line number saved for RESUME
REMSTK = $F8                        ;; stack pointer saved before a statement
HROT = $F9                          ;; shape rotation
AMPERV = $03F5                      ;; writable jump vector for the & statement
OURCH = $057B                       ;; 80-column firmware horizontal cursor position

; Hardware switches and Monitor or firmware entry points.
KBD = $C000                         ;; keyboard data soft switch
SETSLO = $C006                      ;; select slot ROMs at $C100-$CFFF on the IIe
SETINT = $C007                      ;; select internal ROM at $C100-$CFFF on the IIe
RD80VI = $C01F                      ;; IIe 80-column display status, in bit 7
TXTCLR = $C050                      ;; select graphics display
TXTSET = $C051                      ;; select text display
MIXCLR = $C052                      ;; select full-screen graphics
MIXSET = $C053                      ;; select mixed text and graphics
LOWSCR = $C054                      ;; select display page one
HISCR = $C055                       ;; select display page two
LORES = $C056                       ;; select lo-res graphics
HIRES = $C057                       ;; select hi-res graphics
MPLOT = $F800                       ;; Monitor lo-res plot entry
HLINE = $F819                       ;; Monitor lo-res horizontal line entry
VLINE = $F828                       ;; Monitor lo-res vertical line entry
SETCOL = $F864                      ;; Monitor lo-res color entry
MSCRN = $F871                       ;; Monitor lo-res screen-read entry
PREAD = $FB1E                       ;; Monitor paddle-read entry
SETTXT = $FB39                      ;; Monitor text-mode entry
SETGR = $FB40                       ;; Monitor graphics-mode entry
TABV = $FB5B                        ;; Monitor vertical-tab entry
HOME = $FC58                        ;; Monitor home and clear-screen entry
MWAIT = $FCA8                       ;; Monitor delay entry
RD2BIT = $FCFA                      ;; Monitor cassette bit-read entry
GETLN = $FD6A                       ;; Monitor line-input entry
INPORT = $FE8B                      ;; Monitor input-slot selection entry
OUTPOR = $FE95                      ;; Monitor output-slot selection entry
MWRITE = $FECD                      ;; Monitor cassette-write entry
MREAD = $FEFD                       ;; Monitor cassette-read entry
C5ROM = $C500                       ;; enhanced IIe internal firmware at $C500
.org $D000
