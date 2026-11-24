; retrocore: style=strict ignore=unlinked-name:PR|MULT -- a command, the disk layer, X7 prose
;; DOS 3.3 and 3.2: the Apple II addresses DOS uses, and the macros its modules share
;;
;; The Monitor routines, zero-page locations, BASIC entry points and BASIC variables that DOS uses but does not own:
;; the equates at the start of Apple's RELOCTR module, kept in a file of their own because both builds need them and
;; only the master build includes Relocator.asm. They are fixed addresses in the machine's ROMs and low memory, the
;; same wherever DOS runs ($9D00-$BFFF on a 48K machine), and the same in DOS 3.2. The Disk II controller's switches
;; and the disk routines' shared zero page are in RwtsEquates.asm, and the layouts the disk routines share in
;; IoBlock.asm.
;;
;; The locations and routines DOS shares with the IIe's other sources come from ../System/IIeEquates.asm and
;; ../System/MonitorEntries.asm, which this file includes. DOS's names for those locations are in their definitions'
;; historical names: OUTSW is <OutputHook>, INSW <InputHook>, LBUFF <InputBuffer>, ZRSET <SoftEntryVector> and
;; PWCNST <SoftEntryCheck>. The definitions here are the Monitor routines MonitorEntries.asm does not export, DOS's
;; purposes for the Monitor's general zero-page bytes, and the BASICs' addresses.
;;
;; "IB" in a name means Integer BASIC, the BASIC in the original Apple II's ROM; "AS" means Applesoft, the BASIC in
;; the Apple II Plus's ROM or, on an older machine, loaded into RAM. The "1" names are the ROM Applesoft's
;; addresses, the "2" names those of the RAM Applesoft a System Master can load. These keep Apple's names until the
;; BASICs' sources are converted.
;;
;; Apple's equates also define two names DOS never uses, left out here: MULT, the Monitor's
;; <Monitor:Arithmetic::Multiply>, and ASLMEM, the same byte as <ASSOP>. Their BOOTSL, a name for $2E, which DOS 3.1
;; meant as the boot slot, is cited on <FoundTrack>, the track RWTS keeps in that byte.

; The macros.

;; A byte that holds what was in memory when a master was written, which DOS does not depend on: the 1983 DOS 3.3
;; master's value, then the 1980 DOS 3.3 master's, then the DOS 3.2 master's.
;;
;; <DOS32> picks the DOS 3.2 byte; otherwise <YEAR> picks between the DOS 3.3 masters. Code only DOS 3.3 assembles
;; (the parts of BootLoader.asm and MsWait.asm under `.if DOS32 = 0`) leaves y32 out.
;; Parameters: y1983 = the byte in the 1983 build, y1980 = the byte in the 1980 build, y32 = the byte in the DOS 3.2
;;   build
.macro Leftover y1983, y1980, y32
    .if DOS32
        .byte y32
    .elseif YEAR = 1983
        .byte y1983
    .else
        .byte y1980
    .endif
.endmacro

;; Places a string's characters with bit 7 of the last one set, so that code walking a list of words can tell where
;; each ends; the other characters keep bit 7 clear.
;;
;; Apple's listing writes these strings with <MarkedText>, the directive of its EDASM assembler.
;; Parameters: text = the string
.macro MarkedText text
    .repeat .strlen(text) - 1, I
        .byte .strat(text, I)
    .endrepeat
    .byte .strat(text, .strlen(text) - 1) | $80
.endmacro

; The IIe's page zero, low memory, soft switches and keys, and the Monitor's entry points that the other sources
; share.
.include "../System/IIeEquates.asm"
.include "../System/MonitorEntries.asm"

; The Monitor's routines that MonitorEntries.asm does not export, with DOS's names for them.

;; Inherit: <Monitor:CharacterOut>
;; At $FDED. DOS's CATALOG prints through it.
;; Also: COUT (A2RM78, A2RM79, IIEROM82, IIETRM85), PRINT (DOS33, DOS31)
CharacterOut = $FDED

;; Inherit: <Monitor:ReadKey>
;; At $FD0C. DOS's CATALOG waits on it when the screen is full.
;; Also: RDKEY (A2RM78, A2RM79, IIEROM82, IIETRM85), GETKEY (DOS33, DOS31)
ReadKey = $FD0C

;; Inherit: <Monitor:EnterMonitor>
;; At $FF65. DOS's page-3 vectors send Control-Y, NMI and IRQ to it, and reset until DOS has started.
;; Also: MON (A2RM78, A2RM79, IIEROM82, IIETRM85), MONRST (DOS33)
EnterMonitor = $FF65

;; Inherit: <Monitor:ShowBreak>
;; At $FA59. DOS puts it in the BRK vector, <BreakVector>.
;; Also: XBRK (A2RM78, A2RM79), OLDBRK (A2RM79, IIEROM82, IIETRM85), MONBRK (DOS33)
ShowBreak = $FA59

;; Inherit: <Monitor:SetInput>
;; At $FE8B. DOS's IN# calls it to point the input hook at a slot. Apple's DOS listings call it INPRT, the name the
;; Monitor's listings give the entry two bytes later, <Monitor:SetInput::FromA2>.
SetInput = $FE8B

;; Inherit: <Monitor:SetOutput>
;; At $FE95. DOS's PR# calls it to point the output hook at a slot. Apple's DOS listings call it OUTPRT, the name the
;; Monitor's listings give the entry two bytes later, <Monitor:SetOutput::FromA2>.
SetOutput = $FE95

;; Inherit: <Monitor:Disassembler::Decode::Opcode>
;; At $F88E. The relocator, <RelocateDos at DOSREL>, calls it to learn each instruction's length.
;; Also: INSDS2 (DOS33)
DecodeOpcode = $F88E

; DOS's purposes for the Monitor's general zero-page pointers.

;; DOS's general pointer (2 bytes), most often at the header of the file buffer being worked on.
;;
;; <FileBuffers::Build> builds the chain of file buffers through it, and <FileBuffers::First> and <FileBuffers::Next>
;; walk the chain, as <FileBuffers::Find> does to find a file's buffer. The relocator, <RelocateDos at DOSREL>, uses it
;; to step through DOS's code.
;; See: <FilePointer>, <FileBuffers::Build>, <FileBuffers::Find>, <FileBuffers::Next>
;; Also: ZPGWRK (DOS33, DOS31)
WorkPointer = Address3

;; DOS's second pointer (2 bytes), usually at one of an open file's buffers.
;;
;; The file manager points it at the file's work area, its track/sector list or its data sector
;; (<FileManager::PointAtWorkArea>, <FileManager::PointAtListBuffer>, <FileManager::PointAtDataBuffer>) and reads and
;; writes the buffer through it. The relocator, <RelocateDos at DOSREL>, and the boot loader use it as a pointer too.
;; See: <WorkPointer>, <FileManager::PointAtWorkArea>
;; Also: ZPGFCB (DOS33, DOS31)
FilePointer = Address4

;; A number from a command (2 bytes): the value of a decimal or hexadecimal parameter, or a count to print.
;;
;; <Scanner::ParseNumber> converts a parameter into it, and the commands that take a number, such as MAXFILES, PR# and
;; IN#, read it there. <FileBuffers::Find> also leaves the lowest free file buffer in it, and the catalog prints volume
;; numbers and file sizes from it through <FileManager::PrintNumber>.
;; See: <Scanner::ParseNumber>, <FileBuffers::Find>, <FileManager::PrintNumber>
;; Also: CNUM (DOS33, DOS31)
ParsedNumber = Address5

; Integer BASIC.

;; Integer BASIC's <RUNWARM>: runs the program from its first line, keeping the variables. DOS's CHAIN uses it.
IBCHN = $E836

;; Integer BASIC's LOMEM, the bottom of its variables (2 bytes).
;;
;; <Commands::IntegerRun> sets the end of the variables, <IBSOV>, back to it to clear them, and loading a program
;; (<Commands::Load>) checks that the program stays above it.
;; See: <IBSOV>, <IBHMEM>, <IBSOP>, <Commands::IntegerRun>
IBLMEM = $4A

;; Integer BASIC's HIMEM, the top of the memory it may use (2 bytes).
;;
;; <FileBuffers::Build> sets it, and <IBSOP>, just below DOS's file buffers. SAVE (<Commands::Save>) writes the program
;; from <IBSOP> up to it, and loading a program places it to end there.
;; See: <IBSOP>, <IBLMEM>, <FileBuffers::Build>
IBHMEM = $4C

;; The start of Integer BASIC's program (2 bytes), which grows down from HIMEM, <IBHMEM>.
;;
;; <FileBuffers::Build> sets it to HIMEM, an empty program, and loading a program sets it to HIMEM less the program's
;; length.
;; See: <IBHMEM>, <IBLMEM>, <Commands::Save>, <Commands::Load>
IBSOP = $CA

;; Integer BASIC's error entry, just after its message is printed, where DOS goes to report a failed command.
IBBRK = $E3E3

;; Integer BASIC's cold start, which clears the program.
IBGO = $E000

;; Integer BASIC's warm start, which keeps the program.
IBCONT = $E003

;; The end of Integer BASIC's variables (2 bytes), which grow up from LOMEM, <IBLMEM>.
;;
;; <Commands::IntegerRun> sets it to LOMEM, clearing the variables, before it starts a program.
;; See: <IBLMEM>, <Commands::IntegerRun>
IBSOV = $CC

; Applesoft.

;; Applesoft's <TXTTAB>, the start of the program, normally $0801 (2 bytes).
;;
;; SAVE (<Commands::Save>) writes the program from it up to <ASEOP>, and loading a program places it there and sets
;; <ASEOP> and <ASEOP2> to its end.
;; See: <AppleSoft:TXTTAB>, <ASEOP>, <ASEOP2>, <Commands::Load>
ASSOP = $67

;; Applesoft's <PRGEND>, the end of the program (2 bytes).
;;
;; SAVE writes the program from <ASSOP> up to it, and loading a program sets it with <ASEOP2>.
;; See: <AppleSoft:PRGEND>, <ASSOP>, <ASEOP2>
ASEOP = $AF

;; Applesoft's <VARTAB>, the start of the variables, just after the program (2 bytes).
;;
;; Loading a program sets it to the program's end, with <ASEOP>, which leaves no variables.
;; See: <AppleSoft:VARTAB>, <ASEOP>, <ASSOP>
ASEOP2 = $69

;; Applesoft's MEMSIZ, HIMEM, the top of the memory it may use (2 bytes).
;;
;; <FileBuffers::Build> sets it, and <ASHM2>, just below DOS's file buffers, and loading a program checks that it ends
;; below it.
;; See: <AppleSoft:MEMSIZ>, <ASHM2>, <FileBuffers::Build>
ASHM1 = $73

;; Applesoft's FRETOP, the bottom of the strings, which grow down from HIMEM (2 bytes).
;;
;; <FileBuffers::Build> sets it to HIMEM, <ASHM1>, which clears the strings.
;; See: <AppleSoft:FRETOP>, <ASHM1>, <FileBuffers::Build>
ASHM2 = $6F

;; Applesoft's <LOCK> flag: bit 7 set when the program is run-only.
;;
;; SAVE (<Commands::Save>) refuses such a program, with PROGRAM TOO LARGE.
;; See: <AppleSoft:LOCK>, <Commands::Save>
ASRNX = $D6

;; Applesoft's <ERRFLG>: bit 7 set while an `ONERR` GOTO is in force.
;;
;; DOS's <Errors::Report> prints no message while it is set, so that the program's handler deals with the error.
;; <Commands::ApplesoftRomRun> and <Commands::ApplesoftRamRun> clear it when DOS starts a program.
;; See: <AppleSoft:ERRFLG>, <Errors::Report>, <Commands::ApplesoftRomRun>
ASONERR = $D8

;; ROM Applesoft's error entry, where DOS goes to report a failed command.
ASBRK1 = $D865

;; RAM Applesoft's error entry.
ASBRK2 = $1067

;; ROM Applesoft's warm start.
ASCNTU1 = $D43C

;; RAM Applesoft's warm start.
ASCNTU2 = $0C3C

;; ROM Applesoft's routine that rebuilds a loaded program's line links.
ASRSEQ1 = $D4F2

;; RAM Applesoft's routine that rebuilds a loaded program's line links.
ASRSEQ2 = $0CF2

; Telling the BASICs apart.

;; The first byte of the BASIC in ROM, which tells DOS which BASIC that is: <APPLESOFT_ID> or
;; <INTEGER_BASIC_ID>.
;;
;; Both BASICs start at $E000 (Integer BASIC's cold start is <IBGO>), with a JMP in Applesoft and a JSR in Integer
;; BASIC. DOS reads it when it starts, and again when a command asks for the other BASIC.
;; Also: AITSTL (DOS33, DOS31)
RomBasicId = $E000

;; <RomBasicId>'s value when the ROM holds Applesoft: a JMP's opcode.
;; Also: ATSTV (DOS33, DOS31)
APPLESOFT_ID = $4C

;; <RomBasicId>'s value when the ROM holds Integer BASIC: a JSR's opcode.
;; Also: ITSTV (DOS33, DOS31)
INTEGER_BASIC_ID = $20
