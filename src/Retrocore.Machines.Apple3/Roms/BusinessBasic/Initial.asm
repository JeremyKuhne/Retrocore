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

;; The high byte of <CURLIN> while a direct line runs: line numbers stop at 63999, so no program line has it.
DIRECT_LINE = $FF

;; The file number in <FILNO> that means the console.
CONSOLE_FILE = $FF

;; The X-byte of a pointer through bank pair 0; bank pair n's is this plus n, and an X-byte below it is not a
;; bank-pair pointer.
XBYTE_BANK_PAIR_0 = $80

;; The stack's page.
Stack = $0100

; ---------------------------------------------------------------------------------------------------------------------
; The cold start
; ---------------------------------------------------------------------------------------------------------------------

;; The model of <CHRGET> and the random number seed, which <ColdStart> copies to zero page; this copy never runs.
;;
;; The copy steps <TXTPTR> to the next character of the program and reads it, skipping spaces. Its LDA's operand is
;; the pointer itself, in zero page, so the Apple III's extended addressing reads it through its X-byte, <TXTPTRB>,
;; as it would a (zp),Y pointer; <CharacterReaderTemplate::GetCurrent> reads the same character again. The eight
;; bytes after the code become <RNDX>.
;;
;; Apple's listing marks its start, INITAT, as the start of the code that runs only at start and may later be reused
;; as buffer space, up to the end of <ColdStart>.
;; Out: A = the character, zero = set at the end of a statement (a zero or a colon),
;;   carry = clear for a digit, set for anything else
;; Keeps: X, Y
;; See: <CHRGET>, <CHRGOT>, <ColdStart>
;; Also: INITAT (BB13), CHSGET (BB13)
.proc CharacterReaderTemplate
    inc TXTPTR
    bne GetCurrent
    inc TXTPTR+1

;; Reads the character at <TXTPTR> again, without stepping first.
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
;; - records the bank BASIC runs in, from <ColdStart::BankRegister>, in <BASICBNK> and in the console events'
;;   <Console::AnyKeyBank> and <Console::AttentionBank>;
;; - reserves bank 0's $2000-$21FF with REQUEST_SEG (<SEGTAB4>), as BASIC's bank-pair pointers can't reach it;
;; - pushes a zero, the byte at the bottom of the stack that stops <FindForFrame>;
;; - clears zero page from $01 up, and the X-bytes of its pointers at <SYSPAG>;
;; - asks SOS for the program's memory with <TRYSEG>, which sets <RAMLOC> to its start and <MEMSIZ> to its end;
;; - copies <CharacterReaderTemplate> and the seed to <CHRGET> and <RNDX>, with their X-bytes zero;
;; - clears <TRMPOS>, <TRFLAG> (trace off) and <INFLNO> (no `EXEC` file);
;; - sets <FRETOP>, the bottom of the strings, to <MEMSIZ>, and <TXTTAB>, the program's start, to <RAMLOC>;
;; - seeds two bytes of <RNDX> from timers;
;; - calls <ResetInterpreter>, <Console::Initialize> (which opens the console and prints the sign-on) and
;;   <EraseProgram> (which leaves an empty program, no variables and the stack pointer at <STKEND>);
;; - points the <DISPATCH> jump at <SWCHGO>, for invokable modules;
;; - runs `HELLO` as the direct command `RUN HELLO`, through <RUN>, when GET_FILE_INFO finds it, and otherwise
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
    sta BASICBNK
    sta a:Console::AttentionBank
    brk                                     ; REQUEST_SEG bank 0's $2000-$21FF
    .byte MREQ
    .word SEGTAB4
    pha                                     ; The zero that stops FindForFrame
.if VERSION >= 130

;; Where 1.3's program selector leaves <SELFLG> twice, to say it started BASIC.
SelectorMark = 0

;; Where 1.3's program selector leaves the address of the program's pathname, an extended pointer.
SelectorPathname = 2

    ; 1.3: when the program selector started BASIC, it left $EE in locations 0 and 1 and a pointer to the program's
    ; pathname in 2 and 3. Copy the pathname to PROGPATH and set SELECTOR.
    lda #SELFLG
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
    sta PROGPATH,Y
    dey
    bpl CopyPathname
    sty SELECTOR                            ; $FF: the selector started BASIC
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
    sta SYSPAG-1,X                          ; and their X-bytes
    inx
    bne ClearNext
    jsr TRYSEG                              ; The program's memory
    ldx #.sizeof(CharacterReaderTemplate)

;; Copies <CharacterReaderTemplate> and the seed to <CHRGET> and <RNDX>, last byte first, clearing their X-bytes.
;; Also: MOVCHG (BB13)
CopyCharacterReader:
    lda CharacterReaderTemplate-1,X
    sta CHRGET-1,X
    lda #0
    sta SYSPAG+CHRGET-1,X
    dex
    bne CopyCharacterReader
    stx TRMPOS
    stx TRFLAG                              ; Trace off
    stx INFLNO                              ; No EXEC file
    ldy MEMSIZ
    lda MEMSIZ+1                            ; The strings start at the top of memory
    ldx MEMSIZB
    sty FRETOP
    sta FRETOP+1
    stx FRETOPB
    ldx RAMLOC
    ldy RAMLOC+1                            ; The program starts at the bottom
    lda RAMLOCB
    stx TXTTAB
    sty TXTTAB+1
    sta TXTTABB
    lda FirstTimerHigh
    and #$7F
    sta RNDX+4
    lda SecondTimerHigh
    sta RNDX+5
    jsr ResetInterpreter
    jsr Console::Initialize
    jsr EraseProgram
.if VERSION >= 130
    jsr ProgramPrefix::SaveSos                     ; 1.3: keep SOS's prefix in SOSPATH
.endif
    lda #<(SWCHGO)
    sta DISPATCH+1
    lda #>(SWCHGO)
    sta DISPATCH+2
.if VERSION >= 130
    ; 1.3: with the selector, run the program it named, or, with no name, carry on as without it. The run-time
    ; version reports FILE NOT FOUND for no name.
    lda SELECTOR
    beq RunHello
    lda PROGPATH
    beq NoProgramName
    lda #<(PROGPATH)                        ; GET_FILE_INFO on PROGPATH
    sta a:SosCalls::HelloInformation+SosCalls::FileInfoList::PATHNAME
    lda #>(PROGPATH)
    sta a:SosCalls::HelloInformation+SosCalls::FileInfoList::PATHNAME+1
    brk
    .byte SGFI
    .word SosCalls::HelloInformation
    beq RunSelected

;; Reports the SOS error in A as a direct command's, for 1.3's selector.
;; Also: nopgm1 (BB13)
ReportDirect:
    ldx #DIRECT_LINE
    stx CURLIN+1
    jmp SERROR

;; Runs the program the selector named, as <ColdStart::RunHello> runs `HELLO`.
;; Also: SELLO (BB13)
RunSelected:
    sta LINNUM                              ; RUN the program, as RunHello runs HELLO
    sta LINNUM+1
    sta TXTPTRB
    dec CURLIN+1
    lda #<(PROGPATH+1)
    sta TXTPTR
    lda #>(PROGPATH+1)
    sta TXTPTR+1
    jsr CHRGOT
    jmp RUN
.if RUNTIME

;; The selector named no program: the run-time version reports FILE NOT FOUND.
;; Also: nopgm (BB13)
NoProgramName:
    lda #SEFNF
    bne ReportDirect
.else

;; The selector named no program: carries on as without the selector.
;; Also: nopgm (BB13)
NoProgramName:
.endif
.endif

;; Runs `HELLO` if it is there; otherwise goes to the prompt, or, in the run-time version, reports the error.
;;
;; The run is the direct command `RUN HELLO`: <TXTPTR> points at <SosCalls::HelloName>, and <CURLIN> is direct
;; ($FF in its high byte, one less than the zero <EraseProgram> left).
;; Also: BOOTRUN (BB13)
RunHello:
.if VERSION >= 130
    jsr ProgramPrefix::CopySosToProgram            ; 1.3: the program's prefix is SOS's
.endif
    brk                                     ; GET_FILE_INFO on HELLO
    .byte SGFI
    .word SosCalls::HelloInformation
    beq Found
.if RUNTIME
    ldx #DIRECT_LINE
    stx CURLIN+1
    jmp SERROR
.else
    ldx CURLIN+1                            ; Does nothing
    stx CURLIN+1
    jmp CommandLoop
.endif

;; Runs `HELLO`, found: line 0 of the direct command at <SosCalls::HelloName>.
Found:
    sta LINNUM                              ; A = 0: line 0
    sta LINNUM+1
    sta TXTPTRB
    dec CURLIN+1
    lda #<(SosCalls::HelloName)
    sta TXTPTR
    lda #>(SosCalls::HelloName)
    sta TXTPTR+1
    jsr CHRGOT                              ; Reads the H
    jmp RUN
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
;; Invokable modules can call it through <JMPRTAB>.
;; Errors: a SOS error goes to <SERROR>
;; See: <Console::OpenParameters>, <Console::DeviceNumberParameters>, <Console::ResetParameters>,
;;   <Console::AttentionParameters>, <Console::NewlineParameters>, <Console::WriteParameters>
;; Also: INITCNS (BB13)
.proc Initialize
    brk
    .byte SOPN
    .word OpenParameters
    bne Failed
    lda a:Reference
    sta a:CharacterParameters+SosCalls::ReadList::REFERENCE
    sta a:LineParameters+SosCalls::ReadList::REFERENCE
    sta a:WriteParameters+SosCalls::WriteList::REFERENCE
    sta a:NewlineParameters+SosCalls::NewlineList::REFERENCE
    sta a:KeyParameters+SosCalls::ReadList::REFERENCE
    brk
    .byte SDGDN
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
    .byte SDCNT
    .word ResetParameters
    bne Failed
    brk                                     ; Control 6: the attention event
    .byte SDCNT
    .word AttentionParameters
    bne Failed
    brk
    .byte SNWL
    .word NewlineParameters
    bne Failed
    brk
    .byte SWRT
    .word WriteParameters
    bne Failed
    rts

;; Ends with the SOS error of one of the calls.
;; Also: FUK2 (BB13)
Failed:
    jmp SERROR
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
;; It sets <CURLIN> direct (for any error message) and output to the console (<FILNO>), gives <OLDTXT> the X-byte of
;; bank pair 0, stores the JMP opcodes of <DISPATCH> and <JMPER>, clears <ERRFLG> (no `ON ERR`), <RNFLG> and the
;; high byte of <LASTPT>, sets up the string temporaries (<TEMPPT>, <FOUR6>), sets the defaults `OUTREC` = 80 and
;; `INDENT` = 2, takes all memory back with <EXPAND>, clears the ten file control blocks at <FCB>, and writes an
;; empty program, three zeros, at <TXTTAB>, with <ARYTAB> just after them.
;;
;; <ColdStart> calls it, and `NEW` through <EraseProgram>.
;; See: <EraseProgram>
;; Also: P1INIT (BB13)
.proc ResetInterpreter

;; The JMP opcode, before the addresses in <DISPATCH> and <JMPER>.
OPCODE_JMP = $4C

;; `LIST`'s right margin at start, `OUTREC`'s default.
DEFAULT_OUTREC = 80

;; The spaces `LIST` indents each `FOR` loop by at start, `INDENT`'s default.
DEFAULT_INDENT = 2

;; The bytes of an empty program: a zero length, and the two bytes of its line number.
EMPTY_PROGRAM_SIZE = 3

    ldx #DIRECT_LINE
    stx CURLIN+1                            ; Direct
    stx FILNO                               ; Output to the console
    stx FILNO+1
    lda #XBYTE_BANK_PAIR_0
    sta OLDTXTB
    lda #OPCODE_JMP
    sta DISPATCH
    sta JMPER
    ldx #0
    stx LASTPT+1
    stx ERRFLG
    lda #STRSIZ
    sta FOUR6
    ldx #TEMPST
    stx TEMPPT                              ; No string temporaries in use
    lda #DEFAULT_OUTREC
    sta OUTREC                              ; LIST's right margin
    lda #DEFAULT_INDENT
    sta INDENT                              ; LIST's indent for each FOR
    lda #0
    jsr EXPAND                              ; All the memory there is
    ldy #0
    sty RNFLG
    tya
    sty ERRFLG
    dey
    sty FILNO                               ; Output to the console again
    sty FILNO+1
    ldy #FCBLEN*FILE_COUNT                  ; The ten files' control blocks

;; Clears the control blocks, from the top.
ClearControlBlocks:
    sta FCB-1,Y
    dey
    bne ClearControlBlocks
    sta (TXTTAB),Y                          ; The empty program
    iny
    sta (TXTTAB),Y
    iny
    sta (TXTTAB),Y
    lda TXTTAB
    clc
    adc #EMPTY_PROGRAM_SIZE
    sta ARYTAB
    lda TXTTAB+1
    adc #0
    ldy TXTTABB
    jsr FIXADC
    sta ARYTAB+1
    tya
    adc #0
    sta ARYTABB
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
    TOKEN .byte                             ;; <FORTK>
    TYPE .byte                              ;; the variable's type
    VARIABLE .word                          ;; the variable's address
.endstruct

;; Finds the `FOR` entry for the variable in <FORPNT> on the stack, or the topmost `FOR` entry when <FORPNT> is zero.
;;
;; It starts above its caller's and the statement fetcher's return addresses. A `FOR` entry starts with <FORTK>, then
;; the variable's type and its address (<ForFrame>); the search stops at the first entry that isn't a `FOR` (a `GOSUB`
;; entry, or the zero <ColdStart> pushed at the bottom). When <FORPNT> is zero, it takes the top entry's variable
;; into <FORPNT>, <TEMPFOR>, <INTFLG> and <ISARA>.
;; In: FORPNT = the variable's address, or zero, TEMPFOR = its type
;; Out: zero = set when found, X = the entry's offset from the stack's page, less 1 (its <FORTK> is at $0101,X)
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
    cmp #FORTK
    bne Done                                ; Not a FOR: no more to look at
    lda FORPNT+1
    ora FORPNT
    bne Compare
    lda Stack+1+ForFrame::VARIABLE,X        ; No variable given: take this one's
    sta FORPNT
    lda Stack+1+ForFrame::VARIABLE+1,X
    sta FORPNT+1
    lda Stack+1+ForFrame::TYPE,X
    sta TEMPFOR
    sta INTFLG
    ror
    ror ISARA

;; Compares the entry's variable and type with <FORPNT> and <TEMPFOR>.
;; Also: CMPFOR (BB13)
Compare:
    lda FORPNT+1
    cmp Stack+1+ForFrame::VARIABLE+1,X
    bne SkipFrame
    lda FORPNT
    cmp Stack+1+ForFrame::VARIABLE,X
    bne SkipFrame
    lda TEMPFOR
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
;; makes that top the new <STREND>.
;;
;; The block runs from <LOWTR> to just below <HIGHTR>, and moves to end just below <HIGHDS>. It moves from the top
;; down, so the two may overlap.
;; In: A = the new end of the variables' low byte, Y = its high byte, X = its X-byte, LOWTR = the block's start,
;;   HIGHTR = its end, HIGHDS = where its end goes
;; Out: HIGHDS = where the block now starts, LOWTR = unchanged, HIGHTR = within a page of LOWTR
;; Errors: OUT OF MEMORY, from <CheckFreeMemory>
;; Entry: Unchecked = moves without the check or setting <STREND>; invokable modules can call it through <JMPRTAB>
;; See: <OpenGap>, <CloseGap>
;; Also: BLTU (BB13)
.proc MoveRangeUp
    jsr CheckFreeMemory
    sta STREND
    sty STREND+1
    stx STRENDB

;; Moves the block: whole pages while a page or more is left, then the rest.
;; Also: BLTUC (BB13)
Unchecked:
    ldy HIGHTR                              ; How much is left to move
    cpy LOWTR
    lda HIGHTR+1
    sbc LOWTR+1
    ldy HIGHTRB
    ldx LOWTRB
    jsr FIXAYX
    cpy #0
    bne MovePage
    cmp #1
    bcc MoveRest                            ; Less than a page

;; Moves the top page of what is left down from <HIGHTR> to <HIGHDS>, lowering both by a page.
;; Also: MV256 (BB13)
MovePage:
    ldx #HIGHDS
    jsr SubtractPage
    ldx #HIGHTR
    jsr SubtractPage
    ldy #$FF

;; Copies a page, from the top down.
;; Also: BLK2 (BB13)
CopyPage:
    lda (HIGHTR),Y
    sta (HIGHDS),Y
    dey
    bne CopyPage
    lda (HIGHTR),Y                          ; And its first byte
    sta (HIGHDS),Y
    jmp Unchecked

;; Moves the last part of a page, from <LOWTR>, lowering <HIGHDS> to its start.
;; Also: MVEND (BB13)
MoveRest:
    lda HIGHTR
    sec
    sbc LOWTR
    beq Done                                ; Nothing left
    pha                                     ; The bytes left
    ldy HIGHDSB
    sta HIGHDSB                             ; Briefly holds the count
    lda HIGHDS
    sec
    sbc HIGHDSB
    sta HIGHDS
    lda HIGHDS+1
    sbc #0
    cpy #XBYTE_BANK_PAIR_0                  ; A bank-pair pointer?
    bcc StoreDestinationPage
    jsr FIXSB2                              ; Keep its page in range

;; Stores <HIGHDS>'s page and X-byte, then copies the bytes.
StoreDestinationPage:
    sta HIGHDS+1
    sty HIGHDSB
    pla
    tay
    dey

;; Copies a byte, from the top down.
CopyByte:
    lda (LOWTR),Y
    sta (HIGHDS),Y
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
    ldy SYSPAG,X                            ; The X-byte
    sec
    sbc #1
    jsr FIXSBC
    sta 1,X
    tya                                     ; There's no STY abs,X
    sta SYSPAG,X
    rts
.endproc

;; Closes a gap: moves the memory from <INDEX1> up to <STREND> down to <LOWTR>, then adds <DELTA> to <VARTAB>,
;; <ARYTAB> and <STREND>.
;;
;; The caller sets <DELTA> (and <DELTAB>) to the distance, negative, in BASIC's three-byte form. The move goes from
;; the bottom up, so the two may overlap. Apple's comment said it adjusts every table pointer and buffer; it adjusts
;; just these three.
;; In: INDEX1 = the first byte to move, LOWTR = where it goes, DELTA = LOWTR less INDEX1
;; Out: LOWTR = unchanged
;; Entry: AdjustPointers = adds <DELTA> to the pointers alone, from X = 5 (all three) or 3 (<ARYTAB> and <VARTAB>)
;; See: <OpenGap>, <MoveRangeUp>
;; Also: MVDWN (BB13)
.proc CloseGap
    lda LOWTR
    pha
    lda LOWTR+1
    pha
    lda LOWTRB
    pha
    ldy #0

;; Stops the loop when <INDEX1> reaches <STREND>.
;; Also: MVDWN0 (BB13)
CheckEnd:
    lda INDEX1
    cmp STREND
    bne MoveByte
    lda INDEX1+1
    cmp STREND+1
    bne MoveByte
    lda INDEX1B
    cmp STRENDB
    beq RestoreDestination

;; Moves a byte and steps both pointers, keeping their pages in range.
;; Also: MVDWN1 (BB13)
MoveByte:
    lda (INDEX),Y
    sta (LOWTR),Y
    inc INDEX1
    bne StepDestination
    ldx INDEX1+1
    inx
    cpx #MAXPG
    bcc StoreSourcePage
    ldx #MINPG                              ; Into the next bank pair
    inc INDEX1B

;; Stores <INDEX1>'s page.
StoreSourcePage:
    stx INDEX1+1

;; Steps <LOWTR>.
;; Also: MVDWN4 (BB13)
StepDestination:
    inc LOWTR
    bne CheckEnd
    ldx LOWTR+1
    inx
    cpx #MAXPG
    bcc StoreDestinationPage
    ldx #MINPG
    inc LOWTRB

;; Stores <LOWTR>'s page.
StoreDestinationPage:
    stx LOWTR+1
    bne CheckEnd                            ; Always

;; Gets <LOWTR> back, then adjusts the pointers.
;; Also: MVDWN3 (BB13)
RestoreDestination:
    pla
    sta LOWTRB
    pla
    sta LOWTR+1
    pla
    sta LOWTR
    ldx #5                                  ; STREND, ARYTAB, VARTAB

;; Adds <DELTA> to the pointer at <VARTAB>-1+X, then to those below it.
;; Also: MVDWN2 (BB13)
AdjustPointers:
    clc
    lda VARTAB-1,X
    adc DELTA
    sta VARTAB-1,X
    lda VARTAB,X
    adc DELTA+1
    ldy VARTABB-1,X
    jsr FIXADC
    sta VARTAB,X
    tya
    adc DELTAB
    sta VARTABB-1,X
    dex
    dex
    bpl AdjustPointers
    rts
.endproc

;; Opens a gap: moves the memory from <LOWTR> up to <STREND> up by <DELTA>, and adds <DELTA> to <STREND>, <ARYTAB>
;; and <VARTAB>.
;; In: LOWTR = the first byte to move, DELTA = the distance, positive
;; Out: LOWTR = unchanged
;; Errors: OUT OF MEMORY when the new top would reach the strings
;; See: <MoveRangeUp>, <CloseGap>
;; Also: MVUP (BB13)
.proc OpenGap
    lda STREND+1
    sta HIGHTR+1
    lda STRENDB
    sta HIGHTRB
    lda STREND
    sta HIGHTR                              ; The top of what moves
    clc
    adc DELTA                               ; and where it goes
    sta HIGHDS
    lda STREND+1
    adc DELTA+1
    ldy STRENDB
    jsr FIXADC
    sta HIGHDS+1
    tya
    adc DELTAB
    sta HIGHDSB
    tax
    ldy HIGHDS+1
    lda HIGHDS
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
;; entries on the stack. The stack pointer must stay at or above 2A + 54 (2 * <NUMLEV> + 16 more).
;; In: A = the number of two-byte entries
;; Errors: STACK OVERFLOW
;; Keeps: Y
;; Also: GETSTK (BB13)
.proc CheckStack
    asl
    adc #NUMLEV*2+3+13
    bcs StackOverflowError
    sta INDEX
    tsx
    cpx INDEX
    bcc StackOverflowError
    rts
.endproc

;; Checks that an address is below <FRETOP>, the bottom of the strings, collecting the strings' garbage once if it
;; is not.
;;
;; Around the collection it keeps <HIGHDS> through <LOWTR> and their X-bytes, which a block move may be using.
;; In: A = the address's low byte, Y = its high byte, X = its X-byte
;; Keeps: A, X, Y
;; Errors: OUT OF MEMORY when the address is still too high
;; See: <GARBA2>, <MoveRangeUp>
;; Also: REASON (BB13)
.proc CheckFreeMemory
    cpx FRETOPB
    bcc Done
    bne Collect
    cpy FRETOP+1
    bcc Done
    bne Collect
    cmp FRETOP
    bcc Done

;; Collects the strings' garbage and checks again.
;; Also: TRYMOR (BB13)
Collect:
    pha
    txa
    pha
    ldx #10+1
    tya

;; Pushes Y, then <HIGHDS> through <LOWTR>+1, eleven bytes.
;; Also: REASAV (BB13)
SaveScratch:
    pha
    lda HIGHDS-1,X
    dex
    bpl SaveScratch
    lda LOWDSB
    pha
    lda LOWTRB
    pha
    lda HIGHDSB
    pha
    lda HIGHTRB
    pha
    jsr GARBA2
    pla
    sta HIGHTRB
    pla
    sta HIGHDSB
    pla
    sta LOWTRB
    pla
    sta LOWDSB
    ldx #$F5                                ; -11; the index wraps within zero page

;; Pulls <HIGHDS> through <LOWTR>+1 back.
;; Also: REASTO (BB13)
RestoreScratch:
    pla
    sta HIGHDS+10+1,X
    inx
    bmi RestoreScratch
    pla
    tay
    pla
    tax
    pla
    cpx FRETOPB
    bcc Done
    bne ReportOutOfMemory
    cpy FRETOP+1
    bcc Done
    bne ReportOutOfMemory
    cmp FRETOP
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
    ldx #ERRSK
    bne ReportError
.endproc
