; retrocore: style=strict
;; DOS 3.3 and 3.2 command interpreter: DOS's address table, the BASIC vectors, the starts and the page-3 vector
;;
;; The first page of DOS, $9D00-$9E80 where DOS runs (Apple's DOSINIT module). It opens with tables of addresses:
;; those DOS keeps of its own routines and buffers, the entry points of whichever BASIC is active, and the images
;; to choose them from. Then come DOS's entry points: <ColdStart>, which `BOOT 2` or the relocator reaches at the end
;; of a boot; <WarmStart>, which a reset or a CALL 976 reaches; and <FinishStart>, the rest of the setup, done when
;; BASIC first asks for a line. <VectorImage> is the page-3 jump table DOS installs at $3D0-$3FF, through which
;; programs reach DOS wherever it is in memory.
;;
;; The relocator (Relocator.asm) adjusts the addresses here when a master moves DOS: the table from
;; <InterpreterAddressesStart> to <InterpreterAddressesEnd>, the entries of the BASIC vectors its
;; <Relocator::AddressRanges> lists, and the code from <InterpreterCodeStart> on. docs/Dos.md says how DOS gets
;; here.

; DOS's vector in page 3: the jumps programs call, at fixed addresses, once FinishStart has copied VectorImage
; there.

;; A jump to DOS's warm start, <WarmStart>: CALL 976 or 3D0G. The first byte of DOS's page-3 vector.
DosWarmStartJump = $03D0

;; A jump to DOS's cold start, <ColdStart>: 3D3G.
DosColdStartJump = $03D3

;; A jump to the file manager, which carries out the request in the parameter list (docs/Dos.md).
FileManagerJump = $03D6

;; A jump to <Rwts>, through DOS's <CallRwts>, which carries out the request in the IOB whose address is in A (high) and
;; Y (low).
RwtsJump = $03D9

;; <LocateParameterList>, once copied: returns the file manager's parameter list's address.
LocateParameterListJump = $03DC

;; <LocateIob>, once copied: returns the IOB's address.
LocateIobJump = $03E3

;; A jump to <ConnectDos>, which puts DOS back in the input and output hooks.
HookDosJump = $03EA

;; Inherit: <Monitor:SOFT_ENTRY_CHECK>
SOFT_ENTRY_CHECK = $A5

; Which BASIC is active, as ASIBSW records it.

;; <ActiveBasic>'s value while Integer BASIC is active.
BASIC_INTEGER = 0

;; <ActiveBasic>'s value while the Applesoft in ROM is active.
BASIC_APPLESOFT_IN_ROM = $40

;; <ActiveBasic>'s value while an Applesoft loaded into RAM is active.
BASIC_APPLESOFT_IN_RAM = $80

; The macros for the tables.

;; One entry of <OutputHandlers>: a state's handler, less one for the RTS that jumps to it.
;; Parameters: state = the OUTPUT_STATE_ code, routine = its handler
.macro StateHandler state, routine
    .assert * - OutputHandlers = state * 2, "OutputHandlers is in the order of the OUTPUT_STATE_ codes."
    .word routine-1
.endmacro

;; One entry of <CommandHandlers>: a command's handler, less one for the RTS that jumps to it.
;; Parameters: command = the COMMAND_ code, routine = its handler
.macro CommandHandler command, routine
    .assert * - CommandHandlers = command * 2, "CommandHandlers is in the order of the COMMAND_ codes."
    .word routine-1
.endmacro

;; An image of <BasicVector> for one BASIC, which <ColdStart>, <WarmStart> or <FinishStart> copies there.
;; Parameters: chain = CHAIN's entry, run = RUN's, error = where an error is reported, cold = the cold start,
;;   warm = the warm start, relink = the routine that rebuilds a loaded program's line links (Applesoft's only;
;;   left out for Integer BASIC)
.macro BasicEntries chain, run, error, cold, warm, relink
    .word chain, run, error, cold, warm
    .ifnblank relink
        .word relink
    .endif
.endmacro

; DOS starts on a page boundary.
.align 256

;; DOS's first byte: $9D00 where DOS runs, $1D00 in the master image.
;; Also: START (DOS33, DOS31)
DosStart:

;; The start of the first range of addresses the relocator adjusts, the table below to the command handlers.
;; Also: SAT1 (DOS33, DOS31)
InterpreterAddressesStart:

; Addresses DOS keeps of its own routines and buffers, so that code elsewhere, and programs, can find them
; wherever DOS is.

;; The address of the first file buffer's header, the file-name field 45 bytes below DOS; the file buffers are just
;; below it.
;;
;; At $9D00 where DOS runs.
;; Also: FTAB (DOS33, DOS31)
FileBuffersAddress:
.assert MASTER || * = $9D00, "FileBuffersAddress is at $9D00 where DOS runs."
    .word *-45

;; The address of DOS's input routine, <InputHandler>, which DOS puts in the input hook.
;;
;; At $9D02 where DOS runs.
;; Also: CINA (DOS33, DOS31)
InputHandlerAddress:
.assert MASTER || * = $9D02, "InputHandlerAddress is at $9D02 where DOS runs."
    .word InputHandler

;; The address of DOS's output routine, <OutputHandler>, which DOS puts in the output hook.
;;
;; At $9D04 where DOS runs.
;; Also: COUTA (DOS33, DOS31)
OutputHandlerAddress:
.assert MASTER || * = $9D04, "OutputHandlerAddress is at $9D04 where DOS runs."
    .word OutputHandler

;; The address of the file name buffer that commands fill, <FileName>.
;;
;; At $9D06 where DOS runs.
;; Also: FN1ADR (DOS33, DOS31)
FileNameAddress:
.assert MASTER || * = $9D06, "FileNameAddress is at $9D06 where DOS runs."
    .word FileName

;; The address of the second file name buffer, <SecondFileName>, for RENAME's new name.
;;
;; At $9D08 where DOS runs.
;; Also: FN2ADR (DOS33, DOS31)
SecondNameAddress:
.assert MASTER || * = $9D08, "SecondNameAddress is at $9D08 where DOS runs."
    .word SecondFileName

;; The address of <FileHeaderWord>, a length LOAD keeps.
;;
;; At $9D0A where DOS runs.
;; Also: SVBLA (DOS33, DOS31)
LoadFieldAddress:
.assert MASTER || * = $9D0A, "LoadFieldAddress is at $9D0A where DOS runs."
    .word FileHeaderWord

;; DOS's first address, which INIT writes to the disk from.
;;
;; At $9D0C where DOS runs. In the master image it names <ImageStart>, the relocator, until the relocator points
;; it at <DosStart>.
;; Also: ASTART (DOS33, DOS31)
WriteStartAddress:
.assert MASTER || * = $9D0C, "WriteStartAddress is at $9D0C where DOS runs."
    .word ImageStart

;; The address of the file manager's parameter list, <DosFileParameters>, which <LocateParameterList> returns.
;;
;; At $9D0E where DOS runs.
;; Also: CCBADR (DOS33, DOS31)
ParameterListAddress:
.assert MASTER || * = $9D0E, "ParameterListAddress is at $9D0E where DOS runs."
    .word DosFileParameters

;; The handler for each state of DOS's output hook, in the order of the OUTPUT_STATE_ codes, each less one:
;; <OutputHandler> pushes the address and returns to it, and RTS adds the one back.
;; Also: OUTSVT (DOS33, DOS31)
OutputHandlers:
    StateHandler OUTPUT_STATE_LINE_START, Output::LineStart
    StateHandler OUTPUT_STATE_COMMAND_LINE, Output::CommandLine
    StateHandler OUTPUT_STATE_PLAIN_LINE, Output::PlainLine
    StateHandler OUTPUT_STATE_ECHO, Output::Echo
    StateHandler OUTPUT_STATE_FILE_LINE, Output::FileLine
    StateHandler OUTPUT_STATE_FILE_LINE_START, Output::FileLineStart
    StateHandler OUTPUT_STATE_FILE_ECHO, Output::FileEcho

;; The handler for each command, in the order of the COMMAND_ codes, each less one for the same RTS jump.
;; <CommandOffset>, the command's number times 2, is the entry's offset: <COMMAND_RUN> * 2 for RUN.
;; Also: CMDETB (DOS33, DOS31)
CommandHandlers:
    CommandHandler COMMAND_INIT, Commands::Init
    CommandHandler COMMAND_LOAD, Commands::Load
    CommandHandler COMMAND_SAVE, Commands::Save
    CommandHandler COMMAND_RUN, Commands::Run
    CommandHandler COMMAND_CHAIN, Commands::Chain
    CommandHandler COMMAND_DELETE, Commands::Delete
    CommandHandler COMMAND_LOCK, Commands::Lock
    CommandHandler COMMAND_UNLOCK, Commands::Unlock
    CommandHandler COMMAND_CLOSE, Commands::Close
    CommandHandler COMMAND_READ, Commands::Read
    CommandHandler COMMAND_EXEC, Commands::Exec
    CommandHandler COMMAND_WRITE, Commands::Write
    CommandHandler COMMAND_POSITION, Commands::Position
    CommandHandler COMMAND_OPEN, Commands::Open
    CommandHandler COMMAND_APPEND, Commands::Append
    CommandHandler COMMAND_RENAME, Commands::Rename
    CommandHandler COMMAND_CATALOG, Commands::Catalog
    CommandHandler COMMAND_MON, Commands::Mon
    CommandHandler COMMAND_NOMON, Commands::NoMon
    CommandHandler COMMAND_PR_NUMBER, Commands::PrNumber
    CommandHandler COMMAND_IN_NUMBER, Commands::InNumber
    CommandHandler COMMAND_MAXFILES, Commands::MaxFiles
    CommandHandler COMMAND_FP, Commands::Fp
    CommandHandler COMMAND_INT, Commands::Int
    CommandHandler COMMAND_BSAVE, Commands::BSave
    CommandHandler COMMAND_BLOAD, Commands::BLoad
    CommandHandler COMMAND_BRUN, Commands::BRun
    CommandHandler COMMAND_VERIFY, Commands::Verify

;; The end of the relocator's first range of addresses: the BASIC vectors below hold addresses outside DOS too, so
;; <Relocator::AddressRanges> lists only their entries that point into DOS.
;; Also: EAT1 (DOS33, DOS31)
InterpreterAddressesEnd:

;; The entry points of the active BASIC, which DOS jumps through (12 bytes).
;;
;; <ColdStart> and <FinishStart> fill it from one of the three images below, <IntegerVector>,
;; <RomAppleSoftVector> or <RamAppleSoftVector>. Some entries are DOS's own routines, so the relocator lists
;; them; the rest point into a BASIC and stay as they are.
;; Also: IBASVT (DOS33, DOS31)
BasicVector:

;; CHAIN's entry into BASIC: runs the program just loaded, keeping the variables.
;; Also: CHAIN (DOS33, DOS31)
BasicChain:
    .word IBCHN

;; RUN's entry into BASIC: runs the program just loaded.
;; Also: RUN (DOS33, DOS31)
BasicRun:
    .word Commands::IntegerRun

;; Where DOS goes to report an error: BASIC's error handler, just after it prints its own message.
;; Also: BREAK (DOS33, DOS31)
BasicError:
    .word IBBRK

;; BASIC's cold start, which clears the program; the way into BASIC after DOS's own cold start.
;; Also: GO (DOS33, DOS31)
BasicColdStart:
    .word IBGO

;; BASIC's warm start, which keeps the program.
;; Also: CONT (DOS33, DOS31)
BasicWarmStart:
    .word IBCONT

;; Applesoft's routine that rebuilds a loaded program's line links, which LOAD calls; Integer BASIC's image leaves
;; it as it was.
;; Also: ASEQ (DOS33)
BasicRelink:
    Leftover $00, $F2, $00
    Leftover $00, $D4, $00

;; The image of <BasicVector> for Integer BASIC. It is two bytes shorter than the others: Integer BASIC needs no
;; <BasicRelink>.
;; Also: IBVT (DOS33, DOS31)
IntegerVector:
    BasicEntries IBCHN, Commands::IntegerRun, IBBRK, IBGO, IBCONT

;; The length of <IntegerVector> in bytes, 10.
;; Also: IBVTL (DOS33, DOS31)
INTEGER_VECTOR_SIZE = *-IntegerVector

;; The image of <BasicVector> for the Applesoft in ROM.
;; Also: AS1VT (DOS33, DOS31)
RomAppleSoftVector:
    BasicEntries Commands::ApplesoftRomRun, Commands::ApplesoftRomRun, ASBRK1, IBGO, ASCNTU1, ASRSEQ1

;; The length of <RomAppleSoftVector> in bytes, 12.
;; Also: AS1VTL (DOS33, DOS31)
ROM_APPLESOFT_VECTOR_SIZE = *-RomAppleSoftVector

;; The image of <BasicVector> for an Applesoft loaded into RAM. Its cold start is DOS's own.
;; Also: AS2VT (DOS33, DOS31)
RamAppleSoftVector:
    BasicEntries Commands::ApplesoftRamRun, Commands::ApplesoftRamRun, ASBRK2, ColdStart, ASCNTU2, ASRSEQ2

;; The length of <RamAppleSoftVector> in bytes, 12.
;; Also: AS2VTL (DOS33, DOS31)
RAM_APPLESOFT_VECTOR_SIZE = *-RamAppleSoftVector

;; The start of the relocator's first range of code, which runs to <InterpreterCodeEnd>: the command interpreter.
;; Also: SC1 (DOS33, DOS31)
InterpreterCodeStart:

;; DOS's cold start, where every boot ends: CALL 40324 or 3D3G.
;;
;; At $9D84 where DOS runs. It takes the slot and drive in the IOB (after a boot, those it booted from) as the
;; defaults for commands, and sees which BASIC is in ROM from <RomBasicId>. <ActiveBasic> records the BASIC:
;; <BASIC_INTEGER> or <BASIC_APPLESOFT_IN_ROM> (<BASIC_APPLESOFT_IN_RAM> is set later by <FinishStart>). It then
;; hooks DOS into input and output and cold starts BASIC. When BASIC first asks for a line, DOS's input routine
;; finishes the job (<FinishStart>).
;;
;; It doesn't return: it ends in BASIC.
;; Also: DBINIT (DOS33, DOS31)
.proc ColdStart
.assert MASTER || * = $9D84, "ColdStart is at $9D84 where DOS runs."

    ; The boot's slot (the IOB holds it times 16) and drive become the defaults.
    lda a:DosIob::SlotTimes16
    lsr a
    lsr a
    lsr a
    lsr a
    sta a:KeywordSlot
    lda a:DosIob::Drive
    sta a:KeywordDrive

    ; Which BASIC is in ROM?
    lda RomBasicId
    eor #INTEGER_BASIC_ID
    bne AppleSoftInRom
    sta a:ActiveBasic                    ; A = 0: BASIC_INTEGER
    ldx #INTEGER_VECTOR_SIZE

;; Also: IIB1 (DOS33, DOS31)
CopyIntegerVector:
    lda IntegerVector-1,x
    sta BasicVector-1,x
    dex
    bne CopyIntegerVector
    jmp Cold

;; Also: IAS1 (DOS33, DOS31)
AppleSoftInRom:
    lda #BASIC_APPLESOFT_IN_ROM
    sta a:ActiveBasic
    ldx #ROM_APPLESOFT_VECTOR_SIZE

;; Also: IAS1A (DOS33, DOS31)
CopyRomVector:
    lda RomAppleSoftVector-1,x
    sta BasicVector-1,x
    dex
    bne CopyRomVector

;; Also: INITAA (DOS33, DOS31)
Cold:
    sec                             ; carry set: a cold start
    bcs WarmStart::Enter
.endproc

;; DOS's warm start, where a reset goes once DOS has set the reset vector: CALL 976 or 3D0G.
;;
;; At $9DBF where DOS runs. It selects again the BASIC in ROM that <ActiveBasic> records (<Commands::FindBasic> switches
;; the language card, or Apple's firmware card, until <RomBasicId> holds that BASIC's first byte), hooks DOS back into
;; input and output and warm starts BASIC, keeping the program.
;;
;; It doesn't return: it ends in BASIC.
;; Entry:
;;   Enter = with the carry set for a cold start, clear for a warm one; <ColdStart> comes here
;; Also: DBRST (DOS33, DOS31)
.proc WarmStart
.assert MASTER || * = $9DBF, "WarmStart is at $9DBF where DOS runs."
    lda a:ActiveBasic
    bne AppleSoft
    lda #INTEGER_BASIC_ID
    bne SelectRom

;; Also: INITA1 (DOS33, DOS31)
AppleSoft:
    asl a
    bpl Warm                        ; BASIC_APPLESOFT_IN_RAM: no ROM to select
    lda #APPLESOFT_ID

;; Also: INITA2 (DOS33, DOS31)
SelectRom:
    jsr Commands::FindBasic

;; Also: INITA3 (DOS33, DOS31)
Warm:
    clc                             ; carry clear: a warm start

;; Also: INITA (DOS33, DOS31)
Enter:
    php
    jsr ConnectDos
    lda #0
    sta a:EchoFlags                    ; MON's echoes off
    sta a:OutputState
    plp
    ror a                           ; the carry to bit 7: ISTATE = $80 after a cold start, else 0
    sta a:InputState
    bmi ToColdBasic
    jmp (BasicWarmStart)

;; Also: INITB (DOS33, DOS31)
ToColdBasic:
    jmp (BasicColdStart)
.endproc

;; Finishes DOS's setup when BASIC first asks for a line after a cold start; DOS's input routine calls it while
;; <InputState> has bit 7 set.
;;
;; <InputState> $C0 means FP, finding no Applesoft in ROM, has run the program that loads it into RAM: DOS then uses
;; that Applesoft's vector and copies the second file name buffer over the first. Then, every time, it sets MAXFILES to
;; its default, builds the file buffers below HIMEM, keeps an EXEC file going, and clears the input and output states.
;;
;; After a boot <CommandOffset> is 0, INIT's number, as it was when the disk's copy of DOS was written. DOS then
;; installs its page-3 jump table, points the reset vector at <WarmStart>, and runs the disk's greeting program, whose
;; name INIT left in <FileName>. Otherwise it carries out any command that was waiting (<PendingCommand>).
;; In: A = <InputState>
;; Also: INITC (DOS33, DOS31)
.proc FinishStart
    asl a
    bpl BuildBuffers                ; $80: ROM BASIC
    sta a:ActiveBasic                    ; $C0 becomes BASIC_APPLESOFT_IN_RAM
    ldx #RAM_APPLESOFT_VECTOR_SIZE

;; Also: IAS2A (DOS33, DOS31)
CopyRamVector:
    lda RamAppleSoftVector-1,x
    sta BasicVector-1,x
    dex
    bne CopyRamVector
    ldx #CATALOG_NAME_LENGTH-1

;; Also: IAS2B (DOS33, DOS31)
CopyName:
    lda a:SecondFileName,x
    sta a:FileName,x
    dex
    bpl CopyName

;; Also: INITD (DOS33, DOS31)
BuildBuffers:
    lda a:DefaultFileBufferCount
    sta a:FileBufferCount
    jsr FileBuffers::Build

    ; BLDFTB marked every buffer free by clearing the first byte of its file name. ESTATE, when an EXEC file is
    ; open, is the first character of that file's name: it goes back in the EXEC file's buffer.
    lda a:ExecState
    beq ClearAndResume
    pha
    jsr TextFile::PointAtExecBuffer
    pla
    ldy #0
    sta (WorkPointer),y

;; Also: INITZ (DOS33, DOS31)
ClearAndResume:
    jsr ClearStates
    lda a:CommandOffset
    bne ResumeCommand               ; not just booted

    ; Just booted: copies VectorImage to page 3 and makes a reset go to WarmStart. The Autostart Monitor follows
    ; SoftEntryVector only while SoftEntryCheck holds its high byte exclusive-ored with SOFT_ENTRY_CHECK.
    ldx #VECTOR_IMAGE_LAST

;; Also: INITE (DOS33, DOS31)
CopyVectors:
    lda a:VectorImage,x
    sta DosWarmStartJump,x
    dex
    bpl CopyVectors
    lda a:VectorImage+2             ; the address in the image's first JMP: WarmStart
    sta SoftEntryVector+1
    eor #SOFT_ENTRY_CHECK
    sta SoftEntryCheck
    lda a:VectorImage+1
    sta SoftEntryVector
    lda #COMMAND_RUN*2              ; RUN the greeting program
    bne StartCommand

;; Also: INITF (DOS33, DOS31)
ResumeCommand:
    lda a:PendingCommand
    beq Done

;; Also: INITF1 (DOS33)
StartCommand:
    sta a:CommandOffset
    jmp RunCommand

;; Also: INITG (DOS33, DOS31)
Done:
    rts
.endproc

;; The image of DOS's page-3 vector, which <FinishStart> copies to $3D0-$3FF; programs reach DOS through the copy
;; wherever DOS is in memory.
;;
;; Its entries, by address in page 3: <DosWarmStartJump>, <DosColdStartJump>, <FileManagerJump> (to <CallFileManager>),
;; <RwtsJump> (to <CallRwts>), <LocateParameterListJump>, <LocateIobJump> and <HookDosJump> (to <ConnectDos>). From $3EF
;; on, the image fills the Monitor's vectors: <BreakVector> ($3F0) gets <ShowBreak>, the address in the JMP at $3EF;
;; <SoftEntryVector> and <SoftEntryCheck> ($3F2-$3F4) get the next JMP's bytes, which mean nothing there, until
;; <FinishStart> points the vector at <WarmStart> a moment later; Applesoft's ampersand jump ($3F5) goes to the
;; Monitor's RTS, <UserJump> ($3F8, Control-Y) and <NmiJump> ($3FB) to <EnterMonitor>, and <UserIrqVector> ($3FE) is a
;; bare address. They are written as JMPs so that the relocator, which walks this as code, stays in step; the last
;; word's low byte, $65, reads as a two-byte instruction.
;; Also: DBVECT (DOS33, DOS31), IFB (DOS33)
VectorImage:
    jmp WarmStart
    jmp ColdStart
    jmp CallFileManager
    jmp CallRwts

;; Returns the address of the file manager's parameter list. It runs as the copy at $3DC,
;; <LocateParameterListJump>.
;; Out: A = its high byte, Y = its low byte
;; Keeps: X
;; Also: CCBLDR (DOS33, DOS31)
.proc LocateParameterList
.assert * - VectorImage = LocateParameterListJump - DosWarmStartJump, "LocateParameterList is copied to $3DC."
    lda ParameterListAddress+1
    ldy ParameterListAddress
    rts
.endproc

;; Returns the address of RWTS's IOB, <DosIob>. It runs as the copy at $3E3, <LocateIobJump>.
;; Out: A = its high byte, Y = its low byte
;; Keeps: X
;; Also: IOBLDR (DOS33, DOS31)
.proc LocateIob
.assert * - VectorImage = LocateIobJump - DosWarmStartJump, "LocateIob is copied to $3E3."
    lda a:FileManager::IobAddress+1
    ldy a:FileManager::IobAddress
    rts
.endproc

; The rest of the image: the jump that hooks DOS back in, then the Monitor's vectors.
.assert * - VectorImage = HookDosJump - DosWarmStartJump, "HookDosJump's JMP is copied to $3EA."
    jmp ConnectDos
    nop
    nop
.assert * + 1 - VectorImage = BreakVector - DosWarmStartJump, "The address of this JMP is copied to BreakVector."
    jmp ShowBreak
.assert * - VectorImage = SoftEntryVector - DosWarmStartJump, "This JMP is copied over SoftEntryVector."
    jmp EnterMonitor
    jmp SaveRegisters::Return
.assert * - VectorImage = UserJump - DosWarmStartJump, "This JMP is copied to UserJump."
    jmp EnterMonitor
.assert * - VectorImage = NmiJump - DosWarmStartJump, "This JMP is copied to NmiJump."
    jmp EnterMonitor
.assert * - VectorImage = UserIrqVector - DosWarmStartJump, "This address is copied to UserIrqVector."
    .word EnterMonitor

;; The length of <VectorImage> less one: the last index <FinishStart> copies.
;; Also: IFBL (DOS33, DOS31)
VECTOR_IMAGE_LAST = *-VectorImage-1
.assert VECTOR_IMAGE_LAST = $3FF - DosWarmStartJump, "VectorImage fills page 3 to $3FF."
