; retrocore: style=strict
; INITIAL: BASIC's cold start, with the console's setup, then the memory routines the rest of BASIC shares: finding a
; FOR entry on the stack, moving blocks of memory up and down, and checking for room on the stack and below the
; strings.
;
; The cold start runs once. Everything from CharacterReaderTemplate to the end of ColdStart is used only at start, so
; Apple's comments allowed it to be reused as buffer space later; everything from Console::Initialize on must stay.

; ---------------------------------------------------------------------------------------------------------------------
; Values several files share
; ---------------------------------------------------------------------------------------------------------------------

;; The high byte of <CurrentLine> while a direct line runs: line numbers stop at 63999, so no program line has it.
DIRECT_LINE = $FF

;; The file number in <OutputFileNumber> that means the console.
CONSOLE_FILE = $FF

;; The X-byte of a pointer through bank pair 0; bank pair n's is this plus n, and an X-byte below it is not a
;; bank-pair pointer.
XBYTE_BANK_PAIR_0 = $80

;; The stack's page.
Stack = $0100

; ---------------------------------------------------------------------------------------------------------------------
; The cold start
; ---------------------------------------------------------------------------------------------------------------------

;; The model of <GetNextCharacter> and the random number seed, which <ColdStart> copies to zero page; this copy never runs.
;;
;; The copy steps <TextPointer> to the next character of the program and reads it, skipping spaces. Its LDA's operand is
;; the pointer itself, in zero page, so the Apple III's extended addressing reads it through its X-byte, <TextPointerXByte>,
;; as it would a (zp),Y pointer; <CharacterReaderTemplate::GetCurrent> reads the same character again. The eight
;; bytes after the code become <RandomValue>.
;;
;; Apple's listing marks its start, INITAT, as the start of the code that runs only at start and may later be reused
;; as buffer space, up to the end of <ColdStart>.
;; Out: A = the character, zero = set at the end of a statement (a zero or a colon),
;;   carry = clear for a digit, set for anything else
;; Keeps: X, Y
;; See: <GetNextCharacter>, <GetCurrentCharacter>, <ColdStart>
;; Also: INITAT (BB13), CHSGET (BB13)
.proc CharacterReaderTemplate
    inc TextPointer
    bne GetCurrent
    inc TextPointer+1

;; Reads the character at <TextPointer> again, without stepping first.
;; Also: CHSGOT (BB13)
GetCurrent:
    lda $EA60                               ; The copy's operand is TXTPTR
    cmp #':'                                ; Most characters are at or above the colon
    bcs Done
    cmp #' '
    beq CharacterReaderTemplate
    sec                                     ; Leaves carry clear for 0 to 9 only
    sbc #'0'
    sec
    sbc #$100-'0'

;; Returns, with the seed after it.
;; Also: CHSRT (BB13)
Done:
    rts
    .byte 0, 0, 0, 0                        ; The random number seed, for RNDX; ColdStart replaces two bytes of it
    .byte $10, $D6, $3A, $F1
.endproc

;; BASIC's cold start, where SOS starts the interpreter: sets up memory, zero page and the console, then runs the
;; program `HELLO` or, when there is none, waits at the prompt.
;;
;; In order, it:
;; - records the bank BASIC runs in, from <ColdStart::BankRegister>, in <BasicBank> and in the console events'
;;   <Console::AnyKeyBank> and <Console::AttentionBank>;
;; - reserves bank 0's $2000-$21FF with REQUEST_SEG (<Segments::ReserveList>), as BASIC's bank-pair pointers can't reach it;
;; - pushes a zero, the byte at the bottom of the stack that stops <FindForFrame>;
;; - clears zero page from $01 up, and the X-bytes of its pointers at <X_BYTE_OFFSET>;
;; - asks SOS for the program's memory with <Segments::FindForBasic>, which sets <SegmentStart> to its start and <MemoryTop> to its end;
;; - copies <CharacterReaderTemplate> and the seed to <GetNextCharacter> and <RandomValue>, with their X-bytes zero;
;; - clears <TerminalPosition>, <TraceMode> (trace off) and <ExecFile> (no `EXEC` file);
;; - sets <StringsBottom>, the bottom of the strings, to <MemoryTop>, and <ProgramStart>, the program's start, to <SegmentStart>;
;; - seeds two bytes of <RandomValue> from timers;
;; - calls <ResetInterpreter>, <Console::Initialize> (which opens the console and prints the sign-on) and
;;   <EraseProgram> (which leaves an empty program, no variables and the stack pointer at <STACK_END>);
;; - points the <ModuleCallJump> jump at <Modules::CallBasic>, for invokable modules;
;; - runs `HELLO` as the direct command `RUN HELLO`, through <Statements::Run>, when GET_FILE_INFO finds it, and otherwise
;;   goes to <CommandLoop> without a message.
;;
;; 1.3 first takes a program name the program selector left in zero page and runs that program instead.
;; See: <ResetInterpreter>, <Console::Initialize>, <EraseProgram>, <SosCalls::HelloInformation>
;; Also: INIT (BB13)
.proc ColdStart

;; The Apple III's bank register, which says the bank $2000-$9FFF shows.
BankRegister = $FFEF

;; The high byte of a timer of the 6522 at $FFD0.
FirstTimerHigh = $FFD9

;; The high byte of a timer of the 6522 at $FFE0.
SecondTimerHigh = $FFE9

    lda BankRegister
    sta a:Console::AnyKeyBank
    sta BasicBank
    sta a:Console::AttentionBank
    brk                                     ; REQUEST_SEG bank 0's $2000-$21FF
    .byte SOS_REQUEST_SEGMENT
    .word Segments::ReserveList
    pha                                     ; The zero that stops FindForFrame
.if VERSION >= 130

;; Where 1.3's program selector leaves <SELECTOR_SIGNATURE> twice, to say it started BASIC.
SelectorMark = 0

;; Where 1.3's program selector leaves the address of the program's pathname, an extended pointer.
SelectorPathname = 2

    ; 1.3: when the program selector started BASIC, it left $EE in locations 0 and 1 and a pointer to the program's
    ; pathname in 2 and 3. Copy the pathname to PROGPATH and set SELECTOR.
    lda #SELECTOR_SIGNATURE
    cmp SelectorMark
    bne ClearZeroPage
    cmp SelectorMark+1
    bne ClearZeroPage
    ldy #0
    lda (SelectorPathname),Y                ; The pathname's length
    tay

;; Copies the pathname, with its length, last byte first.
CopyPathname:
    lda (SelectorPathname),Y
    sta ProgramPath,Y
    dey
    bpl CopyPathname
    sty StartedBySelector                            ; $FF: the selector started BASIC
.endif

;; Clears zero page and its X-bytes, then carries on with the start.
;; Also: NOTSEL (BB13)
ClearZeroPage:
    ldx #0
    txa
    inx

;; Clears a zero-page byte and its X-byte.
ClearNext:
    sta 0,X                                 ; $01-$FF
    sta X_BYTE_OFFSET-1,X                          ; and their X-bytes
    inx
    bne ClearNext
    jsr Segments::FindForBasic                              ; The program's memory
    ldx #.sizeof(CharacterReaderTemplate)

;; Copies <CharacterReaderTemplate> and the seed to <GetNextCharacter> and <RandomValue>, last byte first, clearing their X-bytes.
;; Also: MOVCHG (BB13)
CopyCharacterReader:
    lda CharacterReaderTemplate-1,X
    sta GetNextCharacter-1,X
    lda #0
    sta X_BYTE_OFFSET+GetNextCharacter-1,X
    dex
    bne CopyCharacterReader
    stx TerminalPosition
    stx TraceMode                              ; Trace off
    stx ExecFile                              ; No EXEC file
    ldy MemoryTop
    lda MemoryTop+1                            ; The strings start at the top of memory
    ldx MemoryTopXByte
    sty StringsBottom
    sta StringsBottom+1
    stx StringsBottomXByte
    ldx SegmentStart
    ldy SegmentStart+1                            ; The program starts at the bottom
    lda SegmentStartXByte
    stx ProgramStart
    sty ProgramStart+1
    sta ProgramStartXByte
    lda FirstTimerHigh
    and #$7F
    sta RandomValue+4
    lda SecondTimerHigh
    sta RandomValue+5
    jsr ResetInterpreter
    jsr Console::Initialize
    jsr EraseProgram
.if VERSION >= 130
    jsr ProgramPrefix::SaveSos                     ; 1.3: keep SOS's prefix in SOSPATH
.endif
    lda #<(Modules::CallBasic)
    sta ModuleCallJump+1
    lda #>(Modules::CallBasic)
    sta ModuleCallJump+2
.if VERSION >= 130
    ; 1.3: with the selector, run the program it named, or, with no name, carry on as without it. The run-time
    ; version reports FILE NOT FOUND for no name.
    lda StartedBySelector
    beq RunHello
    lda ProgramPath
    beq NoProgramName
    lda #<(ProgramPath)                        ; GET_FILE_INFO on PROGPATH
    sta a:SosCalls::HelloInformation+SosCalls::FileInfoList::PATHNAME
    lda #>(ProgramPath)
    sta a:SosCalls::HelloInformation+SosCalls::FileInfoList::PATHNAME+1
    brk
    .byte SOS_GET_FILE_INFO
    .word SosCalls::HelloInformation
    beq RunSelected

;; Reports the SOS error in A as a direct command's, for 1.3's selector.
;; Also: nopgm1 (BB13)
ReportDirect:
    ldx #DIRECT_LINE
    stx CurrentLine+1
    jmp ReportSosError

;; Runs the program the selector named, as <ColdStart::RunHello> runs `HELLO`.
;; Also: SELLO (BB13)
RunSelected:
    sta LineNumber                              ; RUN the program, as RunHello runs HELLO
    sta LineNumber+1
    sta TextPointerXByte
    dec CurrentLine+1
    lda #<(ProgramPath+1)
    sta TextPointer
    lda #>(ProgramPath+1)
    sta TextPointer+1
    jsr GetCurrentCharacter
    jmp Statements::Run
.if RUNTIME

;; The selector named no program: the run-time version reports FILE NOT FOUND.
;; Also: nopgm (BB13)
NoProgramName:
    lda #SOS_ERROR_FILE_NOT_FOUND
    bne ReportDirect
.else

;; The selector named no program: carries on as without the selector.
;; Also: nopgm (BB13)
NoProgramName:
.endif
.endif

;; Runs `HELLO` if it is there; otherwise goes to the prompt, or, in the run-time version, reports the error.
;;
;; The run is the direct command `RUN HELLO`: <TextPointer> points at <SosCalls::HelloName>, and <CurrentLine> is direct
;; ($FF in its high byte, one less than the zero <EraseProgram> left).
;; Also: BOOTRUN (BB13)
RunHello:
.if VERSION >= 130
    jsr ProgramPrefix::CopySosToProgram            ; 1.3: the program's prefix is SOS's
.endif
    brk                                     ; GET_FILE_INFO on HELLO
    .byte SOS_GET_FILE_INFO
    .word SosCalls::HelloInformation
    beq Found
.if RUNTIME
    ldx #DIRECT_LINE
    stx CurrentLine+1
    jmp ReportSosError
.else
    ldx CurrentLine+1                            ; Does nothing
    stx CurrentLine+1
    jmp CommandLoop
.endif

;; Runs `HELLO`, found: line 0 of the direct command at <SosCalls::HelloName>.
Found:
    sta LineNumber                              ; A = 0: line 0
    sta LineNumber+1
    sta TextPointerXByte
    dec CurrentLine+1
    lda #<(SosCalls::HelloName)
    sta TextPointer
    lda #>(SosCalls::HelloName)
    sta TextPointer+1
    jsr GetCurrentCharacter                              ; Reads the H
    jmp Statements::Run
.endproc

; ---------------------------------------------------------------------------------------------------------------------
; The console
; ---------------------------------------------------------------------------------------------------------------------

;; The console: its parameter lists for SOS, its setup and sign-on, its codes, reading a key, and the events of
;; the any-key and CONTROL-C (attention) keys.
.scope Console

; The console's control codes, which BASIC writes to it as characters.

;; Sets the text mode to the byte after it.
SET_TEXT_MODE = $10

;; The text mode BASIC uses: 80 columns, black and white.
TEXT_MODE_80_COLUMNS = 2

;; Sets the console's text options to the byte after it.
SET_TEXT_OPTIONS = $15

;; The text options BASIC sets.
TEXT_OPTIONS = $0D

;; Resets the viewport to the whole screen.
RESET_VIEWPORT = 1

;; Clears the viewport and puts the cursor at its top left.
CLEAR_VIEWPORT = $1C

;; Turns the cursor off.
CURSOR_OFF = 6

;; Sounds the bell.
BELL = 7

;; Turns the screen on.
SCREEN_ON = $0F

;; Normal video.
NORMAL_VIDEO = $11

;; Inverse video.
INVERSE_VIDEO = $12

;; Moves the cursor to the column in the byte after it, counting from 0.
SET_COLUMN = $18

;; Moves the cursor to the line in the byte after it, counting from 0.
SET_LINE = $19

;; A carriage return, which ends a line.
RETURN = $0D

;; A line feed.
LINE_FEED = $0A

;; Opens .CONSOLE and sets it up: copies its reference number and device number into BASIC's console parameter
;; lists, resets it, turns on the CONTROL-C attention event, makes reads end at a carriage return, and prints the
;; sign-on.
;;
;; Invokable modules can call it through <ModuleRoutines>.
;; Errors: a SOS error goes to <ReportSosError>
;; See: <Console::OpenParameters>, <Console::DeviceNumberParameters>, <Console::ResetParameters>,
;;   <Console::AttentionParameters>, <Console::NewlineParameters>, <Console::WriteParameters>
;; Also: INITCNS (BB13)
.proc Initialize
    brk
    .byte SOS_OPEN
    .word OpenParameters
    bne Failed
    lda a:Reference
    sta a:CharacterParameters+SosCalls::ReadList::REFERENCE
    sta a:LineParameters+SosCalls::ReadList::REFERENCE
    sta a:WriteParameters+SosCalls::WriteList::REFERENCE
    sta a:NewlineParameters+SosCalls::NewlineList::REFERENCE
    sta a:KeyParameters+SosCalls::ReadList::REFERENCE
    brk
    .byte SOS_GET_DEVICE_NUMBER
    .word DeviceNumberParameters
    bne Failed
    lda a:Device
    sta a:ResetDevice
    sta a:AttentionDevice
    sta a:AnyKeyDevice
    sta a:EchoDevice
    sta a:CursorDevice
    sta a:FlushTypeAheadDevice
    brk                                     ; Control 0: reset
    .byte SOS_DEVICE_CONTROL
    .word ResetParameters
    bne Failed
    brk                                     ; Control 6: the attention event
    .byte SOS_DEVICE_CONTROL
    .word AttentionParameters
    bne Failed
    brk
    .byte SOS_NEWLINE
    .word NewlineParameters
    bne Failed
    brk
    .byte SOS_WRITE
    .word WriteParameters
    bne Failed
    rts

;; Ends with the SOS error of one of the calls.
;; Also: FUK2 (BB13)
Failed:
    jmp ReportSosError
.endproc

;; The sign-on <Console::Initialize> writes: console codes that set the screen up, then BASIC's name, version and
;; copyright.
;;
;; It sets 80-column text mode and the text options, resets the viewport to the whole screen, clears it, turns the
;; cursor off and beeps. After the text come three zeros, then a carriage return and two line feeds.
;; See: <Console::WriteParameters>
;; Also: SICHRS (BB13)
SignOn:
    .byte SET_TEXT_MODE, TEXT_MODE_80_COLUMNS, SET_TEXT_OPTIONS, TEXT_OPTIONS
    .byte RESET_VIEWPORT
    .byte CLEAR_VIEWPORT
    .byte CURSOR_OFF
    .byte BELL
    .byte RETURN
.if RUNTIME
    .byte "    "
.else
    .byte "       "
.endif
    .byte "Apple Business BASIC "
.if RUNTIME
    .byte "Run-Time "
.endif
.if VERSION = 123
    .byte "v1.23"
.else
    .byte "v1.3"
.endif
.if DEBUG
    .byte "D"                               ; The debugger's version
.endif
    .byte " - Copyright Apple Computer, 1980-83"
.if RUNTIME
.else
    .byte "       "
.endif
    .byte 0, 0, 0
    .byte RETURN, LINE_FEED, LINE_FEED

;; The sign-on's length.
;; Also: SICLEN (BB13)
SIGN_ON_LENGTH = * - SignOn
    .byte $DA, $19, $83                     ; Three bytes nothing uses

.endscope

; ---------------------------------------------------------------------------------------------------------------------
; Resetting BASIC's state
; ---------------------------------------------------------------------------------------------------------------------

;; Resets BASIC's state for a new program: no files, an empty program, nothing to report.
;;
;; It sets <CurrentLine> direct (for any error message) and output to the console (<OutputFileNumber>), gives <StoppedText> the X-byte of
;; bank pair 0, stores the JMP opcodes of <ModuleCallJump> and <FunctionJump>, clears <OnErrorActive> (no `ON ERR`), <StartupDone> and the
;; high byte of <LastTemporary>, sets up the string temporaries (<NextTemporary>, <CollectorStep>), sets the defaults `OUTREC` = 80 and
;; `INDENT` = 2, takes all memory back with <Segments::Grow>, clears the ten file control blocks at <FileControlBlocks>, and writes an
;; empty program, three zeros, at <ProgramStart>, with <ArraysStart> just after them.
;;
;; <ColdStart> calls it, and `NEW` through <EraseProgram>.
;; See: <EraseProgram>
;; Also: P1INIT (BB13)
.proc ResetInterpreter

;; The JMP opcode, before the addresses in <ModuleCallJump> and <FunctionJump>.
OPCODE_JMP = $4C

;; `LIST`'s right margin at start, `OUTREC`'s default.
DEFAULT_OUTREC = 80

;; The spaces `LIST` indents each `FOR` loop by at start, `INDENT`'s default.
DEFAULT_INDENT = 2

;; The bytes of an empty program: a zero length, and the two bytes of its line number.
EMPTY_PROGRAM_SIZE = 3

    ldx #DIRECT_LINE
    stx CurrentLine+1                            ; Direct
    stx OutputFileNumber                               ; Output to the console
    stx OutputFileNumber+1
    lda #XBYTE_BANK_PAIR_0
    sta StoppedTextXByte
    lda #OPCODE_JMP
    sta ModuleCallJump
    sta FunctionJump
    ldx #0
    stx LastTemporary+1
    stx OnErrorActive
    lda #DESCRIPTOR_SIZE
    sta CollectorStep
    ldx #TemporaryDescriptors
    stx NextTemporary                              ; No string temporaries in use
    lda #DEFAULT_OUTREC
    sta OutputRecordLength                              ; LIST's right margin
    lda #DEFAULT_INDENT
    sta ListIndent                              ; LIST's indent for each FOR
    lda #0
    jsr Segments::Grow                              ; All the memory there is
    ldy #0
    sty StartupDone
    tya
    sty OnErrorActive
    dey
    sty OutputFileNumber                               ; Output to the console again
    sty OutputFileNumber+1
    ldy #FILE_CONTROL_BLOCK_SIZE*FILE_COUNT                  ; The ten files' control blocks

;; Clears the control blocks, from the top.
ClearControlBlocks:
    sta FileControlBlocks-1,Y
    dey
    bne ClearControlBlocks
    sta (ProgramStart),Y                          ; The empty program
    iny
    sta (ProgramStart),Y
    iny
    sta (ProgramStart),Y
    lda ProgramStart
    clc
    adc #EMPTY_PROGRAM_SIZE
    sta ArraysStart
    lda ProgramStart+1
    adc #0
    ldy ProgramStartXByte
    jsr Memory::NormalizeAfterAdd
    sta ArraysStart+1
    tya
    adc #0
    sta ArraysStartXByte
    rts
.endproc

; ---------------------------------------------------------------------------------------------------------------------
; The stack
; ---------------------------------------------------------------------------------------------------------------------

;; The bytes a `FOR` entry takes on the stack.
;; Also: FORSIZ (BB13)
FOR_FRAME_SIZE = $14

;; The first bytes of a `FOR` entry on the stack, the ones <FindForFrame> reads; the rest are `FOR`'s.
.struct ForFrame
    TOKEN .byte                             ;; <TOKEN_FOR>
    TYPE .byte                              ;; the variable's type
    VARIABLE .word                          ;; the variable's address
.endstruct

;; Finds the `FOR` entry for the variable in <AssignedVariable> on the stack, or the topmost `FOR` entry when <AssignedVariable> is zero.
;;
;; It starts above its caller's and the statement fetcher's return addresses. A `FOR` entry starts with <TOKEN_FOR>, then
;; the variable's type and its address (<ForFrame>); the search stops at the first entry that isn't a `FOR` (a `GOSUB`
;; entry, or the zero <ColdStart> pushed at the bottom). When <AssignedVariable> is zero, it takes the top entry's variable
;; into <AssignedVariable>, <ForVariableType>, <IntegerType> and <ArrayElementFound>.
;; In: FORPNT = the variable's address, or zero, TEMPFOR = its type
;; Out: zero = set when found, X = the entry's offset from the stack's page, less 1 (its <TOKEN_FOR> is at $0101,X)
;; Keeps: Y
;; See: <FOR_FRAME_SIZE>
;; Also: FNDFOR (BB13)
.proc FindForFrame
    tsx
    inx
    inx
    inx
    inx                                     ; Above the two return addresses

;; Checks the stack entry at X: stops at one that isn't a `FOR`.
;; Also: FFLOOP (BB13)
NextFrame:
    lda Stack+1+ForFrame::TOKEN,X
    cmp #TOKEN_FOR
    bne Done                                ; Not a FOR: no more to look at
    lda AssignedVariable+1
    ora AssignedVariable
    bne Compare
    lda Stack+1+ForFrame::VARIABLE,X        ; No variable given: take this one's
    sta AssignedVariable
    lda Stack+1+ForFrame::VARIABLE+1,X
    sta AssignedVariable+1
    lda Stack+1+ForFrame::TYPE,X
    sta ForVariableType
    sta IntegerType
    ror
    ror ArrayElementFound

;; Compares the entry's variable and type with <AssignedVariable> and <ForVariableType>.
;; Also: CMPFOR (BB13)
Compare:
    lda AssignedVariable+1
    cmp Stack+1+ForFrame::VARIABLE+1,X
    bne SkipFrame
    lda AssignedVariable
    cmp Stack+1+ForFrame::VARIABLE,X
    bne SkipFrame
    lda ForVariableType
    cmp Stack+1+ForFrame::TYPE,X
    beq Done                                ; Found

;; Steps to the next entry down the stack.
;; Also: ADDFRS (BB13)
SkipFrame:
    txa
    clc
    adc #FOR_FRAME_SIZE
    tax
    bne NextFrame

;; Returns.
;; Also: FFRTS (BB13)
Done:
    rts
.endproc

; ---------------------------------------------------------------------------------------------------------------------
; Moving memory
;
; BASIC's pointers into its memory are three bytes: an address whose page stays in MINPG to MAXPG-1 ($02-$81), and
; an X-byte at SYSPAG beside it. FIXADC and FIXSBC keep the page in range as they add and subtract.
; ---------------------------------------------------------------------------------------------------------------------

;; Moves a block of memory up, after checking with <CheckFreeMemory> that its new top is below the strings, and
;; makes that top the new <VariablesEnd>.
;;
;; The block runs from <SourceStart> to just below <SourceEnd>, and moves to end just below <DestinationEnd>. It moves from the top
;; down, so the two may overlap.
;; In: A = the new end of the variables' low byte, Y = its high byte, X = its X-byte, LOWTR = the block's start,
;;   HIGHTR = its end, HIGHDS = where its end goes
;; Out: HIGHDS = where the block now starts, LOWTR = unchanged, HIGHTR = within a page of LOWTR
;; Errors: OUT OF MEMORY, from <CheckFreeMemory>
;; Entry: Unchecked = moves without the check or setting <VariablesEnd>; invokable modules can call it through <ModuleRoutines>
;; See: <OpenGap>, <CloseGap>
;; Also: BLTU (BB13)
.proc MoveRangeUp
    jsr CheckFreeMemory
    sta VariablesEnd
    sty VariablesEnd+1
    stx VariablesEndXByte

;; Moves the block: whole pages while a page or more is left, then the rest.
;; Also: BLTUC (BB13)
Unchecked:
    ldy SourceEnd                              ; How much is left to move
    cpy SourceStart
    lda SourceEnd+1
    sbc SourceStart+1
    ldy SourceEndXByte
    ldx SourceStartXByte
    jsr Memory::PageDifference
    cpy #0
    bne MovePage
    cmp #1
    bcc MoveRest                            ; Less than a page

;; Moves the top page of what is left down from <SourceEnd> to <DestinationEnd>, lowering both by a page.
;; Also: MV256 (BB13)
MovePage:
    ldx #DestinationEnd
    jsr SubtractPage
    ldx #SourceEnd
    jsr SubtractPage
    ldy #$FF

;; Copies a page, from the top down.
;; Also: BLK2 (BB13)
CopyPage:
    lda (SourceEnd),Y
    sta (DestinationEnd),Y
    dey
    bne CopyPage
    lda (SourceEnd),Y                          ; And its first byte
    sta (DestinationEnd),Y
    jmp Unchecked

;; Moves the last part of a page, from <SourceStart>, lowering <DestinationEnd> to its start.
;; Also: MVEND (BB13)
MoveRest:
    lda SourceEnd
    sec
    sbc SourceStart
    beq Done                                ; Nothing left
    pha                                     ; The bytes left
    ldy DestinationEndXByte
    sta DestinationEndXByte                             ; Briefly holds the count
    lda DestinationEnd
    sec
    sbc DestinationEndXByte
    sta DestinationEnd
    lda DestinationEnd+1
    sbc #0
    cpy #XBYTE_BANK_PAIR_0                  ; A bank-pair pointer?
    bcc StoreDestinationPage
    jsr Memory::NormalizePage                              ; Keep its page in range

;; Stores <DestinationEnd>'s page and X-byte, then copies the bytes.
StoreDestinationPage:
    sta DestinationEnd+1
    sty DestinationEndXByte
    pla
    tay
    dey

;; Copies a byte, from the top down.
CopyByte:
    lda (SourceStart),Y
    sta (DestinationEnd),Y
    dey
    cpy #$FF
    bne CopyByte

;; Returns.
;; Also: MVDONE (BB13)
Done:
    rts
.endproc

;; Lowers the three-byte pointer at X by a page, keeping its page in range.
;; In: X = the pointer's zero-page address
;; Keeps: X
;; Also: SUB256 (BB13)
.proc SubtractPage
    lda 1,X
    ldy X_BYTE_OFFSET,X                            ; The X-byte
    sec
    sbc #1
    jsr Memory::NormalizeAfterSubtract
    sta 1,X
    tya                                     ; There's no STY abs,X
    sta X_BYTE_OFFSET,X
    rts
.endproc

;; Closes a gap: moves the memory from <Pointer1> up to <VariablesEnd> down to <SourceStart>, then adds <MoveDistance> to <VariablesStart>,
;; <ArraysStart> and <VariablesEnd>.
;;
;; The caller sets <MoveDistance> (and <MoveDistanceXByte>) to the distance, negative, in BASIC's three-byte form. The move goes from
;; the bottom up, so the two may overlap. Apple's comment said it adjusts every table pointer and buffer; it adjusts
;; just these three.
;; In: INDEX1 = the first byte to move, LOWTR = where it goes, DELTA = LOWTR less INDEX1
;; Out: LOWTR = unchanged
;; Entry: AdjustPointers = adds <MoveDistance> to the pointers alone, from X = 5 (all three) or 3 (<ArraysStart> and <VariablesStart>)
;; See: <OpenGap>, <MoveRangeUp>
;; Also: MVDWN (BB13)
.proc CloseGap
    lda SourceStart
    pha
    lda SourceStart+1
    pha
    lda SourceStartXByte
    pha
    ldy #0

;; Stops the loop when <Pointer1> reaches <VariablesEnd>.
;; Also: MVDWN0 (BB13)
CheckEnd:
    lda Pointer1
    cmp VariablesEnd
    bne MoveByte
    lda Pointer1+1
    cmp VariablesEnd+1
    bne MoveByte
    lda Pointer1XByte
    cmp VariablesEndXByte
    beq RestoreDestination

;; Moves a byte and steps both pointers, keeping their pages in range.
;; Also: MVDWN1 (BB13)
MoveByte:
    lda (Pointer1),Y
    sta (SourceStart),Y
    inc Pointer1
    bne StepDestination
    ldx Pointer1+1
    inx
    cpx #POINTER_PAGE_LIMIT
    bcc StoreSourcePage
    ldx #POINTER_PAGE_FIRST                              ; Into the next bank pair
    inc Pointer1XByte

;; Stores <Pointer1>'s page.
StoreSourcePage:
    stx Pointer1+1

;; Steps <SourceStart>.
;; Also: MVDWN4 (BB13)
StepDestination:
    inc SourceStart
    bne CheckEnd
    ldx SourceStart+1
    inx
    cpx #POINTER_PAGE_LIMIT
    bcc StoreDestinationPage
    ldx #POINTER_PAGE_FIRST
    inc SourceStartXByte

;; Stores <SourceStart>'s page.
StoreDestinationPage:
    stx SourceStart+1
    bne CheckEnd                            ; Always

;; Gets <SourceStart> back, then adjusts the pointers.
;; Also: MVDWN3 (BB13)
RestoreDestination:
    pla
    sta SourceStartXByte
    pla
    sta SourceStart+1
    pla
    sta SourceStart
    ldx #5                                  ; STREND, ARYTAB, VARTAB

;; Adds <MoveDistance> to the pointer at <VariablesStart>-1+X, then to those below it.
;; Also: MVDWN2 (BB13)
AdjustPointers:
    clc
    lda VariablesStart-1,X
    adc MoveDistance
    sta VariablesStart-1,X
    lda VariablesStart,X
    adc MoveDistance+1
    ldy VariablesStartXByte-1,X
    jsr Memory::NormalizeAfterAdd
    sta VariablesStart,X
    tya
    adc MoveDistanceXByte
    sta VariablesStartXByte-1,X
    dex
    dex
    bpl AdjustPointers
    rts
.endproc

;; Opens a gap: moves the memory from <SourceStart> up to <VariablesEnd> up by <MoveDistance>, and adds <MoveDistance> to <VariablesEnd>, <ArraysStart>
;; and <VariablesStart>.
;; In: LOWTR = the first byte to move, DELTA = the distance, positive
;; Out: LOWTR = unchanged
;; Errors: OUT OF MEMORY when the new top would reach the strings
;; See: <MoveRangeUp>, <CloseGap>
;; Also: MVUP (BB13)
.proc OpenGap
    lda VariablesEnd+1
    sta SourceEnd+1
    lda VariablesEndXByte
    sta SourceEndXByte
    lda VariablesEnd
    sta SourceEnd                              ; The top of what moves
    clc
    adc MoveDistance                               ; and where it goes
    sta DestinationEnd
    lda VariablesEnd+1
    adc MoveDistance+1
    ldy VariablesEndXByte
    jsr Memory::NormalizeAfterAdd
    sta DestinationEnd+1
    tya
    adc MoveDistanceXByte
    sta DestinationEndXByte
    tax
    ldy DestinationEnd+1
    lda DestinationEnd
    jsr MoveRangeUp
    ldx #3                                  ; MoveRangeUp set STREND: just ARYTAB and VARTAB
    jmp CloseGap::AdjustPointers
.endproc

; ---------------------------------------------------------------------------------------------------------------------
; Checking for room
; ---------------------------------------------------------------------------------------------------------------------

;; Checks that the stack has room for A more two-byte entries, beyond the levels every routine may use.
;;
;; Routines that push without limit, such as the formula evaluator, call it, and so do `FOR` and `GOSUB`, which leave
;; entries on the stack. The stack pointer must stay at or above 2A + 54 (2 * <STACK_LEVELS> + 16 more).
;; In: A = the number of two-byte entries
;; Errors: STACK OVERFLOW
;; Keeps: Y
;; Also: GETSTK (BB13)
.proc CheckStack
    asl
    adc #STACK_LEVELS*2+3+13
    bcs StackOverflowError
    sta Pointer1
    tsx
    cpx Pointer1
    bcc StackOverflowError
    rts
.endproc

;; Checks that an address is below <StringsBottom>, the bottom of the strings, collecting the strings' garbage once if it
;; is not.
;;
;; Around the collection it keeps <DestinationEnd> through <SourceStart> and their X-bytes, which a block move may be using.
;; In: A = the address's low byte, Y = its high byte, X = its X-byte
;; Keeps: A, X, Y
;; Errors: OUT OF MEMORY when the address is still too high
;; See: <Strings::CollectGarbage>, <MoveRangeUp>
;; Also: REASON (BB13)
.proc CheckFreeMemory
    cpx StringsBottomXByte
    bcc Done
    bne Collect
    cpy StringsBottom+1
    bcc Done
    bne Collect
    cmp StringsBottom
    bcc Done

;; Collects the strings' garbage and checks again.
;; Also: TRYMOR (BB13)
Collect:
    pha
    txa
    pha
    ldx #10+1
    tya

;; Pushes Y, then <DestinationEnd> through <SourceStart>+1, eleven bytes.
;; Also: REASAV (BB13)
SaveScratch:
    pha
    lda DestinationEnd-1,X
    dex
    bpl SaveScratch
    lda DestinationStartXByte
    pha
    lda SourceStartXByte
    pha
    lda DestinationEndXByte
    pha
    lda SourceEndXByte
    pha
    jsr Strings::CollectGarbage
    pla
    sta SourceEndXByte
    pla
    sta DestinationEndXByte
    pla
    sta SourceStartXByte
    pla
    sta DestinationStartXByte
    ldx #$F5                                ; -11; the index wraps within zero page

;; Pulls <DestinationEnd> through <SourceStart>+1 back.
;; Also: REASTO (BB13)
RestoreScratch:
    pla
    sta DestinationEnd+10+1,X
    inx
    bmi RestoreScratch
    pla
    tay
    pla
    tax
    pla
    cpx StringsBottomXByte
    bcc Done
    bne ReportOutOfMemory
    cpy StringsBottom+1
    bcc Done
    bne ReportOutOfMemory
    cmp StringsBottom
    bcs ReportOutOfMemory

;; Returns.
;; Also: REARTS (BB13)
Done:
    rts
.endproc

;; Ends with STACK OVERFLOW.
;; See: <ReportError>
;; Also: OSERR (BB13)
.proc StackOverflowError
    ldx #ERROR_STACK_OVERFLOW
    bne ReportError
.endproc
