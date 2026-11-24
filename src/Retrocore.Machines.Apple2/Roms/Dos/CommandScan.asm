; retrocore: style=strict ignore=unlinked-name:PR -- PR#, and the SYNTAX ERROR message
;; DOS 3.3 and 3.2 command interpreter: the command scanner, which reads a command line and runs its handler
;;
;; Parses the line in <InputBuffer> ($0200) that the output hook (DosHook.asm) has collected, either after a
;; Control-D or typed at BASIC's prompt, and calls the command's handler (Apple's CMDSCAN module, at $9FCD-$A192
;; where DOS runs). In order:
;;
;; - <Scanner::Scan> looks the command's name up in <CommandNames> (CommandTables.asm). Blanks are skipped, so "`CAT`
;;   ALOG" matches too. The command's number, doubled, ends up in <CommandOffset>.
;; - <Scanner::ReadOperands> checks the command's entry in <CommandSyntax>: whether it may be used in direct mode, and
;;   whether it takes one or two file names (into <FileName> and <SecondFileName>, 30 characters each, padded with
;;   blanks) or a number (<Scanner::ReadNumber>: the slot of PR# and IN#, the count of MAXFILES).
;; - <Scanner::ReadOptions> reads the keyword options that follow, ",V254", ",D2", ",S6", ",A$2000" and the rest, into
;;   <KeywordValues> (<KeywordVolume>, <KeywordDrive>, <KeywordSlot>, <KeywordLength>, <KeywordRecord>, <KeywordByte>,
;;   <KeywordAddress>), checking each against its range in <OptionRanges> and the set the command allows.
;; - <Scanner::Execute> calls the handler through <CommandHandlers> (DosInit.asm), by <RunCommand>.
;;
;; A line that is not a DOS command is passed on to BASIC if it was typed, and is a SYNTAX ERROR if it came after a
;; Control-D. So are a few half-commands BASIC has its own meaning for: LOAD, SAVE and RUN with no file name
;; (cassette LOAD and SAVE, BASIC's RUN), and names that do not start with a letter (RUN 100).
;;
;; The character routines the scanner uses, <Scanner::NextNonBlank>, <Scanner::NextCharacter> and
;; <Scanner::ParseNumber>, are in OpenClose.asm.

;; A blank as the screen and DOS's file names hold it: a space with bit 7 set.
BLANK = ' '|$80

;; The number of slots, 0 to 7: PR# and IN# take a slot below it.
SLOT_COUNT = 8

;; The most file buffers MAXFILES can ask for.
MOST_FILE_BUFFERS = 16

;; The command scanner: reads a command line in <InputBuffer>, finds the command in <CommandNames>, reads its file
;; names or number and its options, and runs its handler.
;;
;; <Scanner::Scan> is the way in, from the output hook; CommandScan.asm describes the steps. The character routines the
;; scanner reads the line with (<Scanner::NextNonBlank>, <Scanner::NextCharacter>, <Scanner::ParseNumber>) and the
;; parameter list's clearing (<Scanner::ClearParameterList>) are its piece in OpenClose.asm.
.scope Scanner

;; Scans the command line in <InputBuffer> and, if it is a DOS command, carries it out.
;;
;; At $9FCD where DOS runs. Each entry of <CommandNames> is compared with the line in turn. The status pushed by
;; PHP holds the result so far in its zero flag: set (from LDX #0) at the start of an entry, replaced by a copy
;; with the zero flag clear at the first character that differs. In each comparison, the EOR leaves the table
;; character's top bit, which marks the last character of a name, in bit 7, and ASL moves it into the carry while
;; the rest says whether the characters match. Falls into <NotCommand> when no name matches.
;;
;; It does not return: it leaves through <Execute> and <EndCommand>, an error (<Errors::Report>), or <EchoExit::Always>
;; for a line that is not a command.
;; In: InputBuffer = the line, ending in a return; it may start with Control-D (<CommandCharacter>)
;; Also: SCNCMD (DOS33, DOS31)
.proc Scan
.assert MASTER || * = $9FCD, "Scanner::Scan is at $9FCD where DOS runs."
.if LOWERCASE_INPUT
    ; The lowercase build: Uppercase (BootLoader.asm) raises letters outside quotes to capitals and returns with
    ; Y = CommandOffset = $FF.
    ldx #0
    jsr Uppercase
.else
    ldy #$FF
    sty a:CommandOffset                     ; incremented to 0 for the first command
.endif
    iny                             ; Y = 0, the index into CommandNames
    sty a:PendingCommand                     ; no command saved for FinishStart to resume

;; Also: SC0 (DOS33, DOS31)
NextName:
    inc a:CommandOffset
    ldx #0                          ; sets the zero flag: matches so far
    php
    lda InputBuffer,x
    cmp a:CommandCharacter
    bne StartLine
    inx                             ; skip the Control-D

;; Also: SC0A (DOS33, DOS31)
StartLine:
    stx a:LineIndex

;; Also: SC1X (DOS33, DOS31)
CompareCharacter:
    jsr Scanner::NextNonBlank
    and #$7F
    eor a:CommandNames,y
    iny
    asl a                           ; carry = last character of the name; A = 0 if the characters match
    beq CheckLast
    pla
    php                             ; a mismatch: replace the saved status with this one, zero flag clear

;; Also: SC1A (DOS33, DOS31)
CheckLast:
    bcc CompareCharacter
    plp
    beq ReadOperands                ; every character matched
    lda a:CommandNames,y
    bne NextName                    ; try the next name; a 0 ends the table
    ; Falls into NotCommand.
.endproc

;; The line is not a command. A typed line goes to BASIC; a Control-D line is a syntax error, except a Control-D
;; alone, which does nothing.
;;
;; LOAD and SAVE with no file name come here too, through <Reject>, so that BASIC does its cassette LOAD or SAVE.
;; Also: CNF (DOS33, DOS31)
.proc NotCommand
    lda InputBuffer
    cmp a:CommandCharacter
    beq BareControlD
    jmp EchoExit::Always            ; typed: print the return and let BASIC have the line

;; Also: CNF1 (DOS33, DOS31)
BareControlD:
    lda InputBuffer+1
    cmp #KEY_RETURN
    bne BadLine
    jsr ClearStates
    jmp EchoExit

;; Also: CSERR (DOS33, DOS31)
BadLine:
    jmp Errors::Syntax
.endproc

;; Checks and collects the operands of the command found: the file names or the number.
;;
;; The status pushed after <ClearFileNames> and before the second name records which name is being read: the zero
;; flag set for the first (Y = 0 then), clear for the second (Y = 30). Goes on to <ReadNumber> for a command that
;; takes no file name, to <ReadOptions> once the names are read, and falls into <Reject> for a line that is not a
;; DOS command after all.
;; In: CommandOffset = the command's number, LineIndex = the index just past its name
;; Also: SYNTAX (DOS33, DOS31)
.proc ReadOperands
    asl a:CommandOffset             ; the number * 2 indexes CommandSyntax and CommandHandlers, two bytes an entry
    ldy a:CommandOffset
    jsr TestProgramRunning                      ; carry clear while a program is running
    bcc CheckRun
    lda #SYNTAX_PROGRAM_ONLY
    and a:CommandSyntax+CommandSyntaxEntry::OPERANDS,y
    beq CheckRun
    lda #ERROR_NOT_DIRECT           ; a program-only command typed in direct mode
    jmp Errors::Report

;; For RUN, makes the prompt not "]", so that <TestProgramRunning> sees the program as running.
;; Also: SYN1 (DOS33)
CheckRun:
    cpy #COMMAND_RUN*2
    bne CheckFileName
    sty PromptCharacter

;; Also: SYN1A (DOS33)
CheckFileName:
    lda #SYNTAX_FILE_NAME
    and a:CommandSyntax+CommandSyntaxEntry::OPERANDS,y
    beq ReadNumber                  ; no file name: maybe a number
    jsr ClearFileNames
    php                             ; the zero flag set: reading the first name

    ; A name's first character: $C0-$FF (a letter, lowercase, or one of @[\]^_{|}~ and DEL) or one with bit 7
    ; clear. $80-$BF (a digit, a blank, punctuation) can't start a name: RUN 100 is BASIC's.

;; Also: SN2 (DOS33, DOS31)
StartName:
    jsr Scanner::NextNonBlank
    beq NameDone                    ; a comma or the return: no name
    asl a                           ; carry = bit 7, negative = bit 6 of the character
    bcc RestoreCharacter
    bmi RestoreCharacter
    jmp NotCommand

;; Also: SN2A (DOS33, DOS31)
RestoreCharacter:
    ror a
    jmp StoreCharacter

;; Also: SN3 (DOS33, DOS31)
NextCharacter:
    jsr Scanner::NextCharacter                       ; inside the name, blanks count
    beq NameDone

;; Also: SN4 (DOS33, DOS31)
StoreCharacter:
    sta a:FileName,y
    iny
    cpy #2*CATALOG_NAME_LENGTH      ; SecondFileName follows FileName
    bcc NextCharacter

;; Also: SN5 (DOS33, DOS31)
SkipRest:
    jsr Scanner::NextCharacter                       ; at the limit: skip the rest of the name
    bne SkipRest

;; Also: SN6 (DOS33, DOS31)
NameDone:
    plp
    bne CheckSecondName             ; that was the second name
    ldy a:CommandOffset
    lda #SYNTAX_SECOND_NAME
    and a:CommandSyntax+CommandSyntaxEntry::OPERANDS,y
    beq CheckFirstName
    ldy #CATALOG_NAME_LENGTH        ; the second name goes to SecondFileName
    php                             ; the zero flag clear: reading the second name
    bne StartName                   ; always

;; Also: SN7 (DOS33, DOS31)
CheckSecondName:
    lda a:SecondFileName
    cmp #BLANK
    beq Reject                      ; the second name is missing

;; Also: SN8 (DOS33, DOS31)
CheckFirstName:
    lda a:FileName
    cmp #BLANK
    bne ReadOptions

    ; No file name. Commands with SYNTAX_NONE_ALLOWED alone do without one; the rest, SYNTAX_NONE_TO_BASIC's among
    ; them, go through Reject to NotCommand, which gives a typed line to BASIC.
    ldy a:CommandOffset
    lda #SYNTAX_NONE_TO_BASIC|SYNTAX_NONE_ALLOWED
    and a:CommandSyntax+CommandSyntaxEntry::OPERANDS,y
    beq Reject
    bpl ReadOptions                 ; SYNTAX_NONE_ALLOWED without SYNTAX_NONE_TO_BASIC
    ; Falls into Reject.
.endproc

;; Rejects the line as not a DOS command, for <NotCommand> to pass on or report. <ReadOperands>,
;; <ReadNumber> and <ReadOptions> come here.
;; Also: SERR1 (DOS33, DOS31)
Reject:
    jmp NotCommand

.endscope

;; Fills both file names, <FileName> and <SecondFileName>, with blanks.
;; Out: Y = 0, zero = set
;; Keeps: X
;; Entry: FromY = fills the Y bytes from <FileName> with blanks
;; Also: CLRFNS (DOS33, DOS31)
.proc ClearFileNames
    ldy #2*CATALOG_NAME_LENGTH

;; Also: CLRFNA (DOS33, DOS31)
FromY:
    lda #BLANK

;; Also: SN1 (DOS33, DOS31)
Fill:
    sta a:FileName-1,y
    dey
    bne Fill
    rts
.endproc

; Scanner: reading a number and the options, and running the command.
.scope Scanner continued

;; The command takes no file name. Reads its number if it takes one: a slot 0-7 (<SYNTAX_SLOT>: PR#, IN#) or a
;; count 1-16 (<SYNTAX_COUNT>: MAXFILES), left in <ParsedNumber>. Goes on to <ReadOptions>, and falls into
;; <RangeError> for MAXFILES 0.
;; In: A = 0, Y = <CommandOffset>
;; Also: SN10 (DOS33, DOS31)
.proc ReadNumber
    sta a:FileName                    ; A = 0: the first name's first character becomes 0
    lda #SYNTAX_SLOT|SYNTAX_COUNT
    and a:CommandSyntax+CommandSyntaxEntry::OPERANDS,y
    beq ReadOptions
    jsr Scanner::ParseNumber                      ; X = low byte, A = high byte; carry set if not a number
    bcs SyntaxError
    tay
    bne RangeError                  ; 256 or more
    cpx #MOST_FILE_BUFFERS+1
    bcs RangeError                  ; more than 16
    ldy a:CommandOffset
    lda #SYNTAX_SLOT
    and a:CommandSyntax+CommandSyntaxEntry::OPERANDS,y
    beq CheckCount
    cpx #SLOT_COUNT
    bcs Reject                      ; a slot of 8 or more: not a DOS command
    bcc ReadOptions                 ; always

;; Also: SN11 (DOS33, DOS31)
CheckCount:
    txa
    bne ReadOptions                 ; MAXFILES 0 is a range error
    ; Falls into RangeError.
.endproc

;; Reports RANGE ERROR, for a number or an option out of its range.
;; Also: SERR3 (DOS33)
RangeError:
    lda #ERROR_RANGE
    jmp Errors::Report

;; Reports SYNTAX ERROR, for a number or an option that can't be read.
;; Also: SERR2 (DOS33, DOS31)
SyntaxError:
    jmp Errors::Syntax

;; Reads the keyword options after the operands, each a letter from <OptionLetters>, and checks them.
;;
;; V, D, S, L, R, B and A take a number, decimal or hex after "$", which is checked against the option's range in
;; <OptionRanges> and stored in <KeywordValues>. C, I and O (for MON and NOMON) take none and set bits in <EchoOptions>.
;; <GivenKeywords> gets a bit for each option given (<OptionBits>), and at the end any option the command does not allow
;; (its <CommandSyntaxEntry::OPTIONS>) is an error.
;;
;; The code has room for two passes, the first checking without storing: <InterpreterScratch> not 0 would mean the first
;; pass, holding the index to start the second from. But <InterpreterScratch> is set to 0 here, so there is one pass,
;; and each value is stored as soon as it is checked.
;;
;; It does not return: it goes on to <Execute>, or to an error.
;; In: LineIndex = the index of the first character after the operands
;; Also: SOPTS (DOS33, DOS31)
.proc ReadOptions
    lda #0
    sta a:GivenKeywords
    sta a:EchoOptions
    sta a:KeywordVolume                        ; volume 0: any volume
    sta a:KeywordLength
    sta a:KeywordLength+1
    jsr ClearByteOption             ; InterpreterScratch = 0 and KeywordByte = 0 (DosPatches.asm)
    lda a:LineIndex                     ; not used: InterpreterScratch stays 0

;; Also: SP1 (DOS33, DOS31)
NextOption:
    jsr Scanner::NextNonBlank
    bne FindLetter                  ; an option letter
    cmp #KEY_RETURN
    bne NextOption                  ; a comma: go on

    ; The end of the line. GivenKeywords OR allowed, EOR allowed, leaves the options given but not allowed.
    ldx a:CommandOffset
    lda a:GivenKeywords
    ora a:CommandSyntax+CommandSyntaxEntry::OPTIONS,x
    eor a:CommandSyntax+CommandSyntaxEntry::OPTIONS,x
    bne Reject
    ldx a:InterpreterScratch
    beq Execute                     ; the (only) pass is done
    sta a:InterpreterScratch
    stx a:LineIndex
    bne NextOption

;; Also: SP2 (DOS33, DOS31)
FindLetter:
    ldx #OPTION_LETTER_COUNT

;; Also: SP3 (DOS33, DOS31)
CompareLetter:
    cmp a:OptionLetters-1,x
    beq FoundLetter
    dex
    bne CompareLetter

;; Also: SERR2A (DOS33)
NotLetter:
    beq SyntaxError                 ; not an option letter

;; Also: SP4 (DOS33, DOS31)
FoundLetter:
    lda a:OptionBits-1,x
    bmi EchoOption                  ; C, I or O
    ora a:GivenKeywords
    sta a:GivenKeywords
    dex
    stx a:ScannerScratch                    ; the option's number, 0 for V to 6 for A
    jsr Scanner::ParseNumber
    bcs SyntaxError

    ; Compare ParsedNumber with the option's lowest and highest values: its entry in OptionRanges, four bytes an
    ; option, at ScannerScratch * 4.
    lda a:ScannerScratch
    asl a
    asl a
    tay
    lda ParsedNumber+1
    bne CompareHigh                 ; 256 or more: above every lowest value
    lda ParsedNumber
    cmp a:OptionRanges+OptionRange::LOW,y
    bcc RangeError
    lda ParsedNumber+1

;; Also: SP5 (DOS33, DOS31)
CompareHigh:
    cmp a:OptionRanges+OptionRange::HIGH+1,y
    bcc StoreValue

;; Also: SERR3A (DOS33)
ToRangeError:
    bne RangeError
    lda ParsedNumber
    cmp a:OptionRanges+OptionRange::HIGH,y
    bcc StoreValue
    bne ToRangeError

;; Also: SP6 (DOS33, DOS31)
StoreValue:
    lda a:InterpreterScratch
    bne NextOption                  ; first pass: don't store (never taken)
    tya
    lsr a
    tay                             ; the option's number * 2 indexes KeywordValues
    lda ParsedNumber+1
    sta a:KeywordValues+1,y
    lda ParsedNumber
    sta a:KeywordValues,y

;; Also: SP7 (DOS33, DOS31)
ToNextOption:
    jmp NextOption

    ; C, I or O: OPTION_ECHO into GivenKeywords, and the rest of its OptionBits byte, its ECHO_ bit, into EchoOptions.

;; Also: SP8 (DOS33, DOS31)
EchoOption:
    pha
    lda #OPTION_ECHO
    ora a:GivenKeywords
    sta a:GivenKeywords
    pla
    and #$FF^OPTION_ECHO
    ora a:EchoOptions               ; ECHO_INPUT, ECHO_OUTPUT or ECHO_COMMANDS
    sta a:EchoOptions
    bne ToNextOption                ; always
    beq NotLetter                   ; never reached
.endproc

;; Carries out the command, then leaves DOS through <EndCommand> (DosHook.asm).
;; Also: CMDGO (DOS33, DOS31)
.proc Execute
    jsr RunCommand
    jmp EndCommand
.endproc

.endscope

;; Calls the handler for the command in <CommandOffset>, after clearing the input and output states and the file
;; manager's parameter list.
;;
;; The handler's address less one is pushed from <CommandHandlers>, and RTS goes to it; its own RTS returns to this
;; routine's caller. <FinishStart> (DosInit.asm) also jumps here, to run the greeting program after a boot or to
;; resume the command saved in <PendingCommand>.
;; In: CommandOffset = the command's number * 2, KeywordValues = the options' values, GivenKeywords = the options
;;   given (OPTION_ bits), EchoOptions = the ECHO_ bits given
;; Entry: CallHandler = calls the handler without clearing anything
;; Also: CMDGO1 (DOS33)
.proc RunCommand
    jsr ClearStates
    jsr Scanner::ClearParameterList

;; Also: ECMD (DOS33, DOS31)
CallHandler:
    lda a:CommandOffset
    tax
    lda CommandHandlers+1,x
    pha
    lda CommandHandlers,x
    pha
    rts
.endproc
