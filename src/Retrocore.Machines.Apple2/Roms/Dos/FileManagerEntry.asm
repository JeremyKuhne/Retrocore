; retrocore: style=strict
;; DOS 3.3 and 3.2: the command interpreter's variables, and the file manager's entry and dispatch tables
;;
;; Apple's FDOSENT module, at $AA4F-$AB21 where DOS runs. It begins with variables of the command interpreter, the
;; layer of DOS that reads commands such as CATALOG and LOAD, which sit here only because Apple's module does: the
;; states of DOS's input and output hooks, the keywords and file names of the command being carried out, and which
;; BASIC is active. Beneath Apple DOS, chapter 8, lists their uses.
;;
;; Then the file manager starts, the layer of DOS that keeps files on a disk: the VTOC, the catalog and each file's
;; track/sector lists (docs/Dos.md). Its first bytes are four addresses the relocator adjusts and the tables that
;; pick the routine for each request; then <CallFileManager>, the entry for programs, which the JMP at $03D6 reaches,
;; and its entry for DOS's own commands, <CallFileManager::ForDos>.
;;
;; A request is a parameter list laid out as <FileParameters>: DOS's own is <DosFileParameters>, whose address a
;; program gets by calling $03DC. The file manager keeps the state of a file between requests in the file's work
;; area, a copy of <FileManager::FileControlBlock> in the file's DOS buffer: <FileManager::LoadWorkArea> copies it in
;; when a request starts, and <FileManager::SaveWorkArea> copies it back when it ends. Every request ends at
;; <FileManager::Succeed> or <FileManager::Fail>, which return to the file manager's caller.

; The input states, for <InputState>.

;; Input state: DOS supplies no input of its own; characters come from the keyboard, or an EXEC file.
INPUT_STATE_NONE = 0

;; Input state: READ is in force, so a program's INPUT reads the open file.
INPUT_STATE_READING = 1

;; Input state: DOS has just started, and finishes starting at the first input BASIC asks for.
INPUT_STATE_STARTING = $80

;; Input state: FP found no Applesoft in ROM and has run the program that loads Applesoft into RAM; at that
;; Applesoft's first input DOS finishes starting with it. With this state, a file the file manager cannot find is
;; reported as LANGUAGE NOT AVAILABLE (<FileManager::OpenFile>).
INPUT_STATE_STARTING_RAM_APPLESOFT = $C0

; The echo options, for <EchoFlags> and <EchoOptions>.

;; The bit of <EchoFlags> that MON C sets: DOS echoes the commands it carries out to the screen.
;; Also: MC (DOS33, DOS31)
ECHO_COMMANDS = $40

; The command interpreter's variables.

;; The address of the DOS file buffer of the file the command is working on.
;; Also: CFTABA (DOS33, DOS31)
CurrentFileBuffer:
    Leftover $00, $2D, $2D
    Leftover $00, $18, $18

;; Whether DOS supplies input itself, an INPUT_STATE_ code: <INPUT_STATE_NONE>, <INPUT_STATE_READING>,
;; <INPUT_STATE_STARTING> or <INPUT_STATE_STARTING_RAM_APPLESOFT>.
;; Also: ISTATE (DOS33, DOS31)
InputState:
    .byte INPUT_STATE_NONE

;; The state of DOS's output hook, which picks the routine that handles the next character printed.
;; Also: OSTATE (DOS33, DOS31)
OutputState:
    .byte 0

;; The output hook DOS took over when it started (CSW, <OutputHook>): where characters go once DOS has looked at
;; them.
;; Also: SVOUTS (DOS33, DOS31)
SavedOutputHook:
    Leftover $00, $F0, $F0
    Leftover $00, $FD, $FD

;; The input hook DOS took over (KSW, <InputHook>), where DOS gets the characters it passes on.
;; Also: SVINS (DOS33, DOS31)
SavedInputHook:
    Leftover $00, $1B, $1B
    Leftover $00, $FD, $FD

;; The number of file buffers DOS has, as MAXFILES set it.
;; Also: CNFTBS (DOS33, DOS31)
FileBufferCount:
    Leftover $00, $03, $03

;; A count of 3 file buffers that nothing reads; <DefaultFileBufferCount> is the one DOS uses.
;; Also: DFNFTB (DOS33, DOS31)
UnusedFileBufferCount:
    .byte 3

;; The stack pointer when DOS's hooks were entered.
;; Also: SVSTK (DOS33, DOS31)
HookStackPointer:
    Leftover $00, $FB, $FB

;; X when DOS's hooks were entered.
;; Also: SVX (DOS33, DOS31)
HookX:
    Leftover $00, $0D, $0A

;; Y when DOS's hooks were entered.
;; Also: SVY (DOS33, DOS31)
HookY:
    Leftover $00, $28, $28

;; A when DOS's hooks were entered: the character being read or printed.
;; Also: SVA (DOS33, DOS31)
HookA:
    Leftover $00, $8D, $8D

;; The index into the input line, <InputBuffer>, while a command is read.
;; Also: LBUFD (DOS33, DOS31)
LineIndex:
    Leftover $00, $0D, $0A

;; What MON asked DOS to echo to the screen, one bit each: <ECHO_COMMANDS>, and the bits for input and output.
;; Also: MONMOD (DOS33, DOS31)
EchoFlags:
    .byte 0

;; The command being carried out, as its number times 2: its offset in the command tables.
;;
;; It is 0 when DOS has just been loaded, which DOS's start takes to mean that it runs the disk's greeting program.
;; <CallFileManager> sets it too, to 0 or 2, the offsets of INIT and LOAD, since <FileManager::OpenFile> creates a
;; missing file only for a command whose entry in the command tables allows it.
;; Also: CMDNO (DOS33, DOS31)
CommandOffset:
    .byte $00

;; Where LOAD and BLOAD read each two-byte field at the start of a file: its address or its length.
;; Also: SVBL (DOS33, DOS31)
FileHeaderWord:
    Leftover $00, $85, $00
    Leftover $00, $03, $00

;; A command to carry out once the language has changed, as a <CommandOffset>, or 0.
;; Also: SVCMD (DOS33, DOS31)
PendingCommand:
    .byte 0

;; A scratch byte of the command interpreter.
;; Also: TEMP1A (DOS33, DOS31)
InterpreterScratch:
    Leftover $00, $0B, $0B

;; A scratch byte of the command scanner.
;; Also: TEMP2A (DOS33, DOS31)
ScannerScratch:
    Leftover $00, $01, $00

;; Which keywords the command line gave, one bit each.
;; Also: INOPTS (DOS33, DOS31)
GivenKeywords:
    Leftover $00, $20, $00

;; The keywords' values, from the command line or defaulted, two bytes each: V, D, S, L, R, B and A, from
;; <KeywordVolume> to <KeywordAddress>. The command scanner stores each value here, indexed by the keyword.
;; Also: CUROPT (DOS33, DOS31)
KeywordValues:
;; The V keyword's value: the volume number.
;;
;; Apple's listing calls it CV. That name is the Monitor's, for the cursor's line, so it is not kept here.
KeywordVolume:
    .word 0

;; The D keyword's value: the drive number.
;; Also: CD (DOS33, DOS31)
KeywordDrive:
    Leftover $00, $01, $01
    Leftover $00, $00, $00

;; The S keyword's value: the slot number.
;; Also: CS (DOS33, DOS31)
KeywordSlot:
    Leftover $00, $06, $06
    Leftover $00, $00, $00

;; The L keyword's value: the length, or OPEN's record length.
;; Also: CL (DOS33, DOS31)
KeywordLength:
    .word 1

;; The R keyword's value: the record number.
;; Also: CR (DOS33, DOS31)
KeywordRecord:
    .word 0

;; The B keyword's value: the byte offset.
;; Also: CB (DOS33, DOS31)
KeywordByte:
    .word 0

;; The A keyword's value: the address.
;; Also: CA (DOS33, DOS31)
KeywordAddress:
    Leftover $00, $00, $00
    Leftover $00, $03, $00

;; The C, I and O given with MON or NOMON, as the bits of <EchoFlags> they stand for.
;; Also: IMBITS (DOS33, DOS31)
EchoOptions:
    .byte 0

;; The file name from the command line: 30 characters with bit 7 set, padded with spaces.
;;
;; When DOS starts for the first time it runs the program named here, so the name INIT leaves here as it writes DOS
;; to a disk becomes that disk's greeting program. The master's is HELLO.
;; Also: FNAME1 (DOS33, DOS31)
FileName:
    .hiascii "HELLO                         "

;; The second file name from the command line, RENAME's new name.
;; Also: FNAME2 (DOS33, DOS31)
SecondFileName:
    ; A file name's length, CATALOG_NAME_LENGTH, which FileManagerData.asm defines after this.
    .res 30, ' ' | $80
.assert * - SecondFileName = CATALOG_NAME_LENGTH, "SecondFileName holds one file name."
.assert SecondFileName - FileName = CATALOG_NAME_LENGTH, "FileName holds one file name."

;; The number of file buffers DOS starts with: MAXFILES 3.
;; Also: DFNFTS (DOS33, DOS31)
DefaultFileBufferCount:
    .byte 3

;; The character that starts a DOS command in what a program prints: Control-D, bit 7 set.
;; Also: CCHAR (DOS33, DOS31)
CommandCharacter:
    .byte ('D' & $1F) | $80

;; Nonzero while an EXEC file supplies the input.
;; Also: ESTATE (DOS33, DOS31)
ExecState:
    .byte 0

;; The address of the EXEC file's DOS file buffer.
;; Also: EFTABA (DOS33, DOS31)
ExecFileBuffer:
    .byte 0, 0

;; Which BASIC is active: 0 for Integer BASIC, $40 for Applesoft in ROM, $80 for Applesoft loaded into RAM.
;;
;; At $AAB6 where DOS runs; programs read it to learn which BASIC DOS takes to be in use.
;; Also: ASIBSW (DOS33, DOS31)
ActiveBasic:
.assert MASTER || * = $AAB6, "ActiveBasic is at $AAB6 where DOS runs."
    .byte 0

;; Nonzero while a RUN waits to be finished, the next time output reaches DOS's hook.
;; Also: RSTATE (DOS33)
RunPending:
    .byte 0

;; The name of the file FP runs when the machine has no Applesoft in ROM, which loads Applesoft into RAM.
;; Also: FASB (DOS33, DOS31)
ApplesoftFileName:
    .hiascii "APPLESOFT"

;; The length of <ApplesoftFileName>, 9.
;; Also: FASBL (DOS33, DOS31)
APPLESOFT_FILE_NAME_LENGTH = * - ApplesoftFileName

; The file manager's dispatch tables.

;; One entry of a dispatch table: the address less 1 of the routine for one code, which the dispatcher pushes and
;; "returns" to with RTS. The entry must sit at the code's place in the table.
;; Parameters: table = the table, code = the code the routine handles, routine = the routine
.macro DispatchEntry table, code, routine
    .assert * - table = code * 2, "A dispatch table's entries are in the order of their codes."
    .word routine - 1
.endmacro

;; The start of the file manager's range of addresses the relocator adjusts as words when it moves the master's DOS
;; to the top of memory (Relocator.asm, <Relocator::AddressRanges>): four addresses, then the request, read and
;; write dispatch tables, up to <FileManagerAddressesEnd>.
;; Also: SAT2 (DOS33, DOS31)
FileManagerAddressesStart:

;; The file manager: the layer of DOS that keeps files on a disk, its VTOC, its catalog and each file's track/sector
;; lists (docs/Dos.md).
;;
;; A program asks for a request through <CallFileManager> (the JMP at $03D6), and DOS's own commands through
;; <CallFileManager::ForDos>, with a parameter list laid out as <FileParameters>. The routine for each REQUEST_ code
;; (<FileManager::RequestHandlers>) works on the open file's state in <FileManager::FileControlBlock>, copied in from
;; the file's work area when the request starts, and ends at <FileManager::Succeed> or <FileManager::Fail>, which copy
;; it back and return to the file manager's caller. Where DOS runs, the addresses, dispatch tables and code are at
;; $AAC1-$B396 (the code from $AAFD) and the data (the VTOC and catalog buffers, the file control block and the work
;; cells) at $B397-$B5FD.
.scope FileManager

;; The address of DOS's IOB, <DosIob>, which <AccessDisk> fills in for every disk access. The page-3 vector at
;; $03E3 loads it.
;; Also: AIOB (DOS33, DOS31)
IobAddress:
    .word DosIob

;; The address of the VTOC buffer, <VtocBuffer>.
;; Also: AVTOC (DOS33, DOS31)
VtocAddress:
    .word VtocBuffer

;; The address of the catalog buffer, <CatalogBuffer>.
;; Also: AVOLDR (DOS33, DOS31)
CatalogBufferAddress:
    .word CatalogBuffer

;; The address after the last byte of DOS, $C000 where DOS runs. Nothing in DOS reads it.
;; Also: AEND (DOS33, DOS31)
DosEndAddress:
    .word DosEnd

;; The routines for the requests: for each REQUEST_ code, 0 to <REQUEST_COUNT>, the address less 1 of its routine,
;; which <CallFileManager::ForDos> reaches with RTS.
;;
;; <REQUEST_NONE> does nothing but succeed. <CallFileManager::ForDos> refuses <REQUEST_COUNT> and above, so the last
;; entry is never used.
;; Also: CMDVT (DOS33, DOS31)
RequestHandlers:
    DispatchEntry RequestHandlers, REQUEST_NONE, Succeed
    DispatchEntry RequestHandlers, REQUEST_OPEN, Open
    DispatchEntry RequestHandlers, REQUEST_CLOSE, Close
    DispatchEntry RequestHandlers, REQUEST_READ, Read
    DispatchEntry RequestHandlers, REQUEST_WRITE, Write
    DispatchEntry RequestHandlers, REQUEST_DELETE, Delete
    DispatchEntry RequestHandlers, REQUEST_CATALOG, Catalog
    DispatchEntry RequestHandlers, REQUEST_LOCK, Lock
    DispatchEntry RequestHandlers, REQUEST_UNLOCK, Unlock
    DispatchEntry RequestHandlers, REQUEST_RENAME, Rename
    DispatchEntry RequestHandlers, REQUEST_POSITION, Position
    DispatchEntry RequestHandlers, REQUEST_INIT, InitDisk
    DispatchEntry RequestHandlers, REQUEST_VERIFY, Verify
    DispatchEntry RequestHandlers, REQUEST_COUNT, Succeed

;; READ's routines: for each TRANSFER_ code, 0 to <TRANSFER_COUNT>, the address less 1 of its routine, which
;; <Read> reaches with RTS. <Read> refuses <TRANSFER_COUNT> and above, so the last entry is never used.
;; Also: RVT (DOS33, DOS31)
ReadHandlers:
    DispatchEntry ReadHandlers, TRANSFER_NONE, Succeed
    DispatchEntry ReadHandlers, TRANSFER_NEXT_BYTE, ReadNextByte
    DispatchEntry ReadHandlers, TRANSFER_NEXT_RANGE, ReadNextRange
    DispatchEntry ReadHandlers, TRANSFER_POSITIONED_BYTE, ReadByteAt
    DispatchEntry ReadHandlers, TRANSFER_POSITIONED_RANGE, ReadRangeAt
    DispatchEntry ReadHandlers, TRANSFER_COUNT, Succeed

;; WRITE's routines, laid out as <ReadHandlers>, which <Write> reaches with RTS.
;; Also: WVT (DOS33, DOS31)
WriteHandlers:
    DispatchEntry WriteHandlers, TRANSFER_NONE, Succeed
    DispatchEntry WriteHandlers, TRANSFER_NEXT_BYTE, WriteNextByte
    DispatchEntry WriteHandlers, TRANSFER_NEXT_RANGE, WriteNextRange
    DispatchEntry WriteHandlers, TRANSFER_POSITIONED_BYTE, WriteByteAt
    DispatchEntry WriteHandlers, TRANSFER_POSITIONED_RANGE, WriteRangeAt
    DispatchEntry WriteHandlers, TRANSFER_COUNT, Succeed

.endscope

;; The end of the relocator's range of addresses, <FileManagerAddressesStart> to here.
;; Also: EAT2 (DOS33, DOS31)
FileManagerAddressesEnd:

;; The start of the file manager's code, to <FileManagerCodeEnd>, whose instructions the relocator adjusts
;; (Relocator.asm, <Relocator::CodeRanges>).
;; Also: SC2 (DOS33, DOS31)
FileManagerCodeStart:

;; The file manager's entry for programs, which the JMP at $03D6 reaches: carries out the request in
;; <DosFileParameters>.
;;
;; At $AAFD where DOS runs. X says whether a missing file may be created: X = 0 sets <CommandOffset> to INIT's
;; offset, whose command may create files, and any other X to LOAD's, which may not (<FileManager::OpenFile>). A
;; created file is reported as <ERROR_FILE_NOT_FOUND>, but with the carry clear. The parameter list is always DOS's
;; own; A and Y are not used.
;; In: X = 0 to allow creating a file, DosFileParameters = the request
;; Out: DosFileParameters::ReturnCode = 0, or an ERROR_ code, carry = set on an error
;; Entry:
;;   ForDos = DOS's own entry, which keeps <CommandOffset>, the command being carried out
;; Also: USERENT (DOS33)
.proc CallFileManager
.assert MASTER || * = $AAFD, "CallFileManager is at $AAFD where DOS runs."
    .using FileManager

    ; The command whose create rule OpenFile follows: INIT's for X = 0, else LOAD's.
    cpx #0

;; Apple's label, which nothing uses.
;; Also: NOT (DOS33)
TestCreate:
    beq SetCommand
    ldx #2

;; Stores the command's offset.
;; Also: USRCR (DOS33)
SetCommand:
    stx CommandOffset

;; DOS's own entry: carries out the request in <DosFileParameters> for the command <CommandOffset> names.
;;
;; At $AB06 where DOS runs.
;; In: DosFileParameters = the request, CommandOffset = the command
;; Out: DosFileParameters::ReturnCode = 0, or an ERROR_ code, carry = set on an error
;; Also: DOSENT (DOS33, DOS31)
ForDos:
.assert MASTER || * = $AB06, "CallFileManager::ForDos is at $AB06 where DOS runs."

    ; Every exit (Leave) sets S back to this and returns to the caller, however deep the request has gone.
    tsx
    stx EntryStack

    ; Bring in the file's work area, and clear the return code.
    jsr LoadWorkArea

    ; Push the request's routine less 1, high byte first, and "return" to it.
    lda DosFileParameters::Request
    cmp #REQUEST_COUNT
    bcs ToBadRequest
    asl a
    tax
    lda RequestHandlers + 1,x
    pha
    lda RequestHandlers,x
    pha

;; The RTS that goes to the request's routine.
;; Also: DENRTS (DOS33, DOS31)
Dispatch:
    rts

;; Goes on to <FileManager::BadRequest>, out of a branch's range.
;; Also: ERR2 (DOS33, DOS31)
ToBadRequest:
    jmp BadRequest
.endproc
