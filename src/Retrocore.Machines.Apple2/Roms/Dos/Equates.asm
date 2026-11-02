;; DOS 3.3 AND 3.2: THE APPLE II ADDRESSES DOS USES (FROM RELOCTR)
;;
;; The Monitor routines, zero-page locations, BASIC entry points and page-3 vectors that DOS uses but does not
;; own: the equates at the start of Apple's RELOCTR module, kept in a file of their own because both builds
;; need them and only the master build includes Relocator.asm. They are fixed addresses in the machine's ROMs
;; and low memory, the same wherever DOS runs, and the same in DOS 3.2. Addresses in a module of their own (the
;; Disk II switches, RWTS's zero page) are in RwtsEquates.asm and Rwts1.asm (RwtsEquates32.asm and Rwts32.asm
;; for DOS 3.2).
;;
;; "IB" in a name means Integer BASIC, the BASIC in the original Apple II's ROM; "AS" means Applesoft, the
;; BASIC in the Apple II Plus's ROM or, on an older machine, loaded into RAM. The "1" names are the ROM
;; Applesoft's addresses, the "2" names those of the RAM Applesoft a System Master can load.
;;
;; The addresses DOS shares with the IIe's other sources under the same names, such as PROMPT, HOME and IORTS, come
;; from ../System/IIeEquates.asm and ../System/MonitorEntries.asm, which this file includes; the equates here are
;; the ones under DOS's own names.

;; A byte that holds what was in memory when a master was written, which DOS does not depend on: the 1983
;; DOS 3.3 master's value, then the 1980 DOS 3.3 master's, then the DOS 3.2 master's. DOS32 picks the DOS 3.2
;; byte; otherwise YEAR picks between the DOS 3.3 masters. The modules only DOS 3.3 includes (BootLoader.asm,
;; MsWait.asm) leave y32 out.
;; Parameters: y1983 = the byte in the 1983 build, y1980 = the byte in the 1980 build, y32 = the byte in the
;;             DOS 3.2 build
.macro LEFTOVER y1983, y1980, y32
.if DOS32
    .byte y32
.elseif YEAR = 1983
    .byte y1983
.else
    .byte y1980
.endif
.endmacro

;; Places a string's characters with bit 7 of the last one set, so code walking a list of words can tell
;; where each ends. The name is that of Apple's EDASM directive. The other characters keep bit 7 clear.
;; Parameters: text = the string
.macro DCI text
    .repeat .strlen(text) - 1, I
    .byte .strat(text, I)
    .endrepeat
    .byte .strat(text, .strlen(text) - 1) | $80
.endmacro

; The IIe's page zero, soft switches and keys, PROMPT and LENGTH among them, and the Monitor's entry points: SETVID,
; SETKBD, HOME (which DOS does not use) and IORTS among them.
.include "../System/IIeEquates.asm"
.include "../System/MonitorEntries.asm"

; Zero page and the input buffer, under DOS's own names.
;; DOS's name for the Monitor's output hook, <CSWL>: the address of the routine each character goes to
;; (2 bytes).
;;
;; <MVCSW> and <MVOSW> point it at DOS's <CHROUT>, saving the routine that was there in SVOUTS, and do it again
;; each time DOS returns control, since BASIC, PR# and IN# replace it. <SVREGS> puts the real routine back while
;; DOS prints, and <ORTN1> jumps through it.
;; See: <INSW>, <MVOSW>, <CHROUT>, <Monitor:COUT>
OUTSW = $36

;; DOS's name for the Monitor's input hook, <KSWL>: the address of the routine each key comes from
;; (2 bytes).
;;
;; <MVCSW> points it at DOS's <CHRIN>, saving the routine that was there in SVINS. <SVREGS> puts the real routine
;; back while DOS works, and <GETIN> jumps through it.
;; See: <OUTSW>, <MVCSW>, <CHRIN>, <Monitor:RDKEY>
INSW = $38

;; DOS's general-purpose pointer (2 bytes), most often at the header of the file buffer being worked on.
;;
;; <BLDFTB> builds the chain of file buffers through it, and <TSINIT> and <TSNXT> walk the chain, as
;; <FILSRC> does to find a file's buffer. The relocator, <DOSREL>, uses it to step through DOS's code.
;; See: <ZPGFCB>, <BLDFTB>, <FILSRC>, <TSNXT>
ZPGWRK = $40

;; A number from a command (2 bytes): the value of a decimal or hexadecimal parameter, or a count to print.
;;
;; <GETNUM> converts a parameter into it, and the commands that take a number, such as MAXFILES, PR# and IN#,
;; read it there. <FILSRC> also leaves the lowest free file buffer in it, and the catalog prints volume numbers
;; and file sizes from it through <PRNUM>.
;; See: <GETNUM>, <FILSRC>, <PRNUM>
CNUM = $44

LBUFF = $200                        ;; the input line buffer the Monitor's line reader fills

MULT = $FB63                        ;; the Monitor's multiply routine; not used by DOS
INPRT = $FE8B                       ;; the Monitor's IN#: points KSW at the slot in A
OUTPRT = $FE95                      ;; the Monitor's PR#: points CSW at the slot in A

; Integer BASIC.
IBCHN = $E836                       ;; the entry DOS uses to run a program for CHAIN

;; Integer BASIC's LOMEM, the bottom of its variables (2 bytes).
;;
;; <IBRUN> sets the end of the variables, <IBSOV>, back to it to clear them, and loading a program (<ELOAD>)
;; checks that the program stays above it.
;; See: <IBSOV>, <IBHMEM>, <IBSOP>, <IBRUN>
IBLMEM = $4A

;; Integer BASIC's HIMEM, the top of the memory it may use (2 bytes).
;;
;; <BLDFTB> sets it, and <IBSOP>, just below DOS's file buffers. SAVE (<ESAVE>) writes the program from <IBSOP>
;; up to it, and loading a program places it to end there.
;; See: <IBSOP>, <IBLMEM>, <BLDFTB>
IBHMEM = $4C

;; The start of Integer BASIC's program (2 bytes), which grows down from HIMEM, <IBHMEM>.
;;
;; <BLDFTB> sets it to HIMEM, an empty program, and loading a program sets it to HIMEM less the program's
;; length.
;; See: <IBHMEM>, <IBLMEM>, <ESAVE>, <ELOAD>
IBSOP = $CA

IBBRK = $E3E3                       ;; the error entry DOS uses to report a failed command
IBGO = $E000                        ;; cold start: clears the program
IBCONT = $E003                      ;; warm start: keeps the program

;; The end of Integer BASIC's variables (2 bytes), which grow up from LOMEM, <IBLMEM>.
;;
;; <IBRUN> sets it to LOMEM, clearing the variables, before it starts a program.
;; See: <IBLMEM>, <IBRUN>
IBSOV = $CC

; Applesoft.
;; Applesoft's TXTTAB, the start of the program, normally $0801 (2 bytes).
;;
;; SAVE (<ESAVE>) writes the program from it up to <ASEOP>, and loading a program places it there and sets
;; <ASEOP> and <ASEOP2> to its end.
;; See: <AppleSoft:TXTTAB>, <ASEOP>, <ASEOP2>, <ELOAD>
ASSOP = $67

;; Applesoft's PRGEND, the end of the program (2 bytes).
;;
;; SAVE writes the program from <ASSOP> up to it, and loading a program sets it with <ASEOP2>.
;; See: <AppleSoft:PRGEND>, <ASSOP>, <ASEOP2>
ASEOP = $AF

;; Applesoft's VARTAB, the start of the variables, just after the program (2 bytes).
;;
;; Loading a program sets it to the program's end, with <ASEOP>, which leaves no variables.
;; See: <AppleSoft:VARTAB>, <ASEOP>, <ASSOP>
ASEOP2 = $69

;; Applesoft's MEMSIZ, HIMEM, the top of the memory it may use (2 bytes).
;;
;; <BLDFTB> sets it, and <ASHM2>, just below DOS's file buffers, and loading a program checks that it ends
;; below it.
;; See: <AppleSoft:MEMSIZ>, <ASHM2>, <BLDFTB>
ASHM1 = $73

;; Applesoft's FRETOP, the bottom of the strings, which grow down from HIMEM (2 bytes).
;;
;; <BLDFTB> sets it to HIMEM, <ASHM1>, which clears the strings.
;; See: <AppleSoft:FRETOP>, <ASHM1>, <BLDFTB>
ASHM2 = $6F

;; Applesoft's LOCK flag: bit 7 set when the program is run-only.
;;
;; SAVE (<ESAVE>) refuses such a program, with PROGRAM TOO LARGE.
;; See: <AppleSoft:LOCK>, <ESAVE>
ASRNX = $D6

;; Applesoft's ERRFLG: bit 7 set while an ONERR GOTO is in force.
;;
;; DOS's <ERROR> prints no message while it is set, so that the program's handler deals with the error.
;; <ASRUN1> and <ASRUN2> clear it when DOS starts a program.
;; See: <AppleSoft:ERRFLG>, <ERROR>, <ASRUN1>
ASONERR = $D8

;; The bottom of Applesoft's memory, the same byte as <ASSOP>; DOS does not use the name.
;; See: <ASSOP>
ASLMEM = ASSOP

ASBRK1 = $D865                      ;; ROM Applesoft's error entry, for DOS's errors
ASBRK2 = $1067                      ;; RAM Applesoft's error entry
ASCNTU1 = $D43C                     ;; ROM Applesoft's warm start
ASCNTU2 = $C3C                      ;; RAM Applesoft's warm start
ASRSEQ1 = $D4F2                     ;; ROM Applesoft's routine that rebuilds a loaded program's line links
ASRSEQ2 = $CF2                      ;; the same in RAM Applesoft

; Telling the BASICs apart: the first byte of the BASIC in ROM, at $E000, is a JMP in Applesoft and a JSR in
; Integer BASIC.
AITSTL = $E000                      ;; the byte that says which BASIC is in ROM
ATSTV = $4C                         ;; its value with Applesoft (JMP)
ITSTV = $20                         ;; its value with Integer BASIC (JSR)

;; A name for $2E, which DOS defines but does not use.
;;
;; In DOS, $2E is <TRACK>, a byte of the address field RWTS has just read.
;; See: <TRACK>
BOOTSL = $2E

;; DOS's second pointer (2 bytes), usually at one of an open file's buffers.
;;
;; The file manager points it at the file's work area, its track/sector list or its data sector (<MVFCBP>,
;; <MVFCBD>, <MVFCBS>) and reads and writes the buffer through it. The relocator, <DOSREL>, and the boot loader
;; use it as a pointer too.
;; See: <ZPGWRK>, <MVFCBP>
ZPGFCB = $42

; More Monitor routines, under DOS's own names.
MONRST = $FF65                      ;; the Monitor's command loop, entered with a beep
MONBRK = $FA59                      ;; the Monitor's handler for BRK
PRINT = $FDED                       ;; COUT: prints the character in A through CSW
GETKEY = $FD0C                      ;; RDKEY: reads a key through KSW
INSDS2 = $F88E                      ;; part of the disassembler: sets LENGTH from the opcode in A

; The reset vector of the Autostart Monitor (the Apple II Plus and later). A reset goes through ZRSET only if
; PWCNST holds ZRSET's high byte exclusive-ored with $A5; otherwise the machine cold starts.
ZRSET = $3F2                        ;; where a reset goes (2 bytes)
PWCNST = $3F4                       ;; the power-up byte that makes ZRSET valid
