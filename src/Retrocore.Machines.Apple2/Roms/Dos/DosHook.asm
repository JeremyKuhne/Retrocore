; retrocore: style=strict ignore=unlinked-name:PR|INPUT -- the PR# command, and BASIC's INPUT
;; DOS 3.3 and 3.2 command interpreter: the input and output hooks, and the output states
;;
;; How DOS hears BASIC (Apple's DOSHOOK module), at $9E81-$9FCC where DOS runs. Every character the Apple II prints goes
;; through the Monitor's <CharacterOut>, which jumps through the output hook, <OutputHook> ($36-$37); every character it
;; reads goes through <ReadKey>, which jumps through the input hook, <InputHook> ($38-$39). DOS puts its own routines in
;; both, <OutputHandler> ($9EBD) and <InputHandler> ($9E81), and keeps the real handlers (normally the screen and
;; keyboard, or a card after PR# or IN#) in <SavedOutputHook> and <SavedInputHook>. <ConnectDos> (BuildFileTables.asm)
;; installs the hooks, and puts them back each time DOS exits, since BASIC and PR# or IN# overwrite $36-$39 freely.
;;
;; How PRINT CHR$(4);"CATALOG" reaches a command handler:
;;
;; - PRINT sends Control-D ($84 with the high bit set, <CommandCharacter>), then C, A, T ... and a return, each through
;;   <CharacterOut> and so to <OutputHandler>. That saves the registers and stack pointer (<SaveCaller>), hands
;;   $36-$39 back to the real handlers so that anything DOS prints goes straight out, and jumps to the handler for
;;   the output state <OutputState>.
;; - At the start of a line <OutputState> is <OUTPUT_STATE_LINE_START>, so <Output::LineStart> sees the Control-D, sets
;;   <OUTPUT_STATE_COMMAND_LINE> and starts filling the line buffer, <InputBuffer> ($0200).
;;   <Output::CommandLine> adds each later character; nothing is shown unless MON C is on.
;; - The return ends the line and <Output::CommandLine> jumps to <Scanner::Scan> (CommandScan.asm). It finds CATALOG in
;;   <CommandNames>, checks the operands against <CommandSyntax>, collects options into <KeywordVolume>, <KeywordDrive>,
;;   <KeywordSlot> and the rest, and <Scanner::Execute> calls the handler through <CommandHandlers>, here
;;   <Commands::Catalog> in MiscCommands.asm. Handlers call the file manager through <RunFileRequest> (DosGoer.asm).
;; - When the handler returns, <EndCommand> and <ExitDos> finish the "print": they put DOS's hooks back, restore
;;   the stack pointer and registers saved on entry, and return to whoever called <CharacterOut>, as though the
;;   return had been printed.
;;
;; Commands typed at BASIC's prompt take another path. <InputHandler> sets <OUTPUT_STATE_ECHO> before it reads a
;; key, so the echo of that key, which BASIC's line input (the Monitor's GETLN) prints through <CharacterOut>, goes
;; to <Output::Echo>. GETLN keeps the line in $0200 too; when the return is echoed in direct mode, <Output::Echo>
;; hands the line to <Scanner::Scan> as if it had come after a Control-D. If it is a DOS command, <EndCommand>
;; empties the line so that BASIC sees a blank one.
;;
;; The other states carry WRITE (output goes to a file: <OUTPUT_STATE_FILE_LINE> and
;; <OUTPUT_STATE_FILE_LINE_START>) and READ (input comes from a file: <InputState>, and <OUTPUT_STATE_FILE_ECHO> to hide
;; INPUT's prompt). An EXEC file (<ExecState>) feeds <InputHandler> in place of the keyboard. docs/Dos.md describes the
;; whole interpreter.

; The output states: OutputState's values, which pick the handler in OutputHandlers for the next character printed.

;; The first character of a line, where a Control-D starts a command: <Output::LineStart>.
OUTPUT_STATE_LINE_START = 0

;; A command line after its Control-D, collected in <InputBuffer>: <Output::CommandLine>.
OUTPUT_STATE_COMMAND_LINE = 1

;; The rest of an ordinary line: <Output::PlainLine>.
OUTPUT_STATE_PLAIN_LINE = 2

;; The echo of a key just read: <Output::Echo>.
OUTPUT_STATE_ECHO = 3

;; WRITE is on, after a line's first character: <Output::FileLine>.
OUTPUT_STATE_FILE_LINE = 4

;; WRITE is on, at the start of a line: <Output::FileLineStart>.
OUTPUT_STATE_FILE_LINE_START = 5

;; The echo of a character read from a file: <Output::FileEcho>.
OUTPUT_STATE_FILE_ECHO = 6

;; A flashing blank: the cursor, as the screen holds it.
FLASHING_BLANK = $60

;; DOS's input hook: <InputHook> points here, so the Monitor's <ReadKey> comes here for every character BASIC reads.
;;
;; At $9E81 where DOS runs. While a file is being read (READ), the character comes from the file
;; (<TextFile::ReadCharacter>). The first read after DOS starts finishes starting it (<FinishStart>). Otherwise an EXEC
;; file supplies the character (<TextFile::ReadExecCharacter>), or, when there is none, the real input routine does. The
;; output state is set to <OUTPUT_STATE_ECHO>, so that the echo of the character is checked for a typed command.
;; In: A = the screen character under the cursor, Y = the cursor column, TextBase = the cursor's row, as
;;   <ReadKey> leaves them
;; Out: A = the character read (through <ExitDos>); from the real input routine, X as it returns it too
;; Also: CHRIN (DOS33, DOS31)
.proc InputHandler
.assert MASTER || * = $9E81, "InputHandler is at $9E81 where DOS runs."
    jsr SaveCaller
    lda a:InputState
    beq CheckExec                   ; not reading a file and not just started: go read
    pha
    lda a:HookA
    sta (TextBase),y                ; put back the character ReadKey replaced with a flashing cursor
    pla
    bmi Starting                    ; InputState negative: DOS has just started
    jmp TextFile::ReadCharacter     ; InputState positive: READ is on; take the character from the file

;; Also: CHIN0 (DOS33, DOS31)
Starting:
    jsr FinishStart
    ldy CursorColumn
    lda #FLASHING_BLANK             ; the cursor again, since a key will be read after all
    sta (TextBase),y

;; Also: CHIN1 (DOS33, DOS31)
CheckExec:
    lda a:ExecState
    beq ReadReal
    jsr TextFile::ReadExecCharacter         ; the character from the EXEC file; returns here only at its end

;; Also: CHIN2 (DOS33, DOS31)
ReadReal:
    lda #OUTPUT_STATE_ECHO
    sta a:OutputState                    ; the echo of this character goes to Output::Echo
    jsr LoadCaller
    jsr CallRealInput
    sta a:HookA
    stx a:HookX
    jmp ExitDos
.endproc

;; Calls the real input routine, whose address <SaveCaller> has put back in <InputHook>.
;; Also: GETIN (DOS33, DOS31)
.proc CallRealInput
    jmp (InputHook)
.endproc

;; DOS's output hook: <OutputHook> points here, so the Monitor's <CharacterOut> comes here for every character
;; printed.
;;
;; At $9EBD where DOS runs. Saves the registers and goes to the handler for the current output state through
;; <OutputHandlers>. The table holds each address less one, and pushing it and returning goes there: the 6502's
;; RTS adds one to the address it pulls.
;;
;; It returns to <CharacterOut>'s caller through <ExitDos>, with the registers as the real output routine leaves
;; them, or as on entry if the character was not printed. The state handlers start with A = the character.
;; In: A = the character
;; Also: CHROUT (DOS33, DOS31)
.proc OutputHandler
.assert MASTER || * = $9EBD, "OutputHandler is at $9EBD where DOS runs."
    jsr SaveCaller
    lda a:OutputState
    asl a
    tax
    lda OutputHandlers+1,x
    pha
    lda OutputHandlers,x
    pha
    lda a:HookA
    rts
.endproc

;; Saves the registers on entry to DOS and gives $36-$39 back to the real input and output routines.
;;
;; <HookStackPointer> gets the stack pointer as it was before the JSR here, so that <ExitDos> can later return to the
;; program that called <CharacterOut> or <ReadKey> whatever DOS has pushed in between. With the real routines back in
;; <OutputHook> and <InputHook>, what DOS prints or reads while it works does not come back into DOS.
;; In: A, X, Y = the caller's registers
;; Out:
;;   HookA/HookX/HookY = A, X and Y
;;   HookStackPointer = the stack pointer before the JSR here
;;   OutputHook/InputHook = <SavedOutputHook>/<SavedInputHook>
;; Keeps: Y
;; Entry: ExceptA = saves all but A
;; Also: SVREGS (DOS33, DOS31)
.proc SaveCaller
    sta a:HookA

;; Also: SVRGSA (DOS33, DOS31)
ExceptA:
    stx a:HookX
    sty a:HookY
    tsx
    inx
    inx                             ; drop this routine's own return address
    stx a:HookStackPointer
    ldx #3

;; Also: SVRB (DOS33, DOS31)
RestoreHooks:
    lda a:SavedOutputHook,x         ; the saved hooks lie in the same order as OutputHook and InputHook
    sta OutputHook,x
    dex
    bpl RestoreHooks
    rts
.endproc

;; The handlers of DOS's output hook, one for each output state (<OutputState>, an OUTPUT_STATE_ code), which
;; <OutputHandler> picks through <OutputHandlers> for each character printed.
;;
;; They collect command lines after a Control-D or from typed input, pass ordinary output on, write to a file
;; while WRITE is on, and hide or show echoes as MON asks. Each starts with A = the character and leaves DOS
;; through <EchoExit> or <ExitDos>. DosHook.asm explains the states.
.scope Output

;; State <OUTPUT_STATE_LINE_START>: the first character of a line. A Control-D here starts a DOS command.
;;
;; While <InputState> is not 0 (normally because READ is on, and BASIC's INPUT is reading from the file), a "?", which
;; INPUT prints as its prompt, is hidden unless MON I is on (<FileEcho>), and the prompt character in
;; <PromptCharacter> is printed with the state left at <OUTPUT_STATE_LINE_START>. Falls into <CommandLine> for a
;; Control-D.
;; In: A = the character
;; Also: COS0 (DOS33, DOS31)
.proc LineStart
    ldx a:RunPending
    beq CheckInput
    jmp FinishRun                   ; a RUN is waiting to be finished

;; Also: COS00 (DOS33)
CheckInput:
    ldx a:InputState
    beq CheckControlD
    cmp #'?'|$80
    beq FileEcho
    cmp PromptCharacter             ; the character the Monitor's GETLN prints first
    beq PlainLine::EndLine

;; Also: COS01 (DOS33, DOS31)
CheckControlD:
    ldx #OUTPUT_STATE_PLAIN_LINE
    stx a:OutputState                    ; an ordinary line, unless ...
    cmp a:CommandCharacter
    bne PlainLine
    dex
    stx a:OutputState                    ; ... it starts with Control-D: OUTPUT_STATE_COMMAND_LINE
    dex
    stx a:LineIndex                     ; and the line buffer starts empty; the Control-D goes in first
    ; Falls into CommandLine.
.endproc

;; State <OUTPUT_STATE_COMMAND_LINE>: collects a command line in <InputBuffer>, and scans it at the return.
;; In: A = the character
;; Entry: StoreAtX = stores at X rather than <LineIndex> (<Echo>'s typed line)
;; Also: COS1 (DOS33, DOS31)
.proc CommandLine
    ldx a:LineIndex

;; Also: COS1A (DOS33, DOS31)
StoreAtX:
    sta InputBuffer,x
    inx
    stx a:LineIndex
    cmp #KEY_RETURN
    bne EchoExit                    ; not yet the end: shown only under MON C
    jmp Scanner::Scan
.endproc

;; State <OUTPUT_STATE_PLAIN_LINE>: the rest of an ordinary line. Prints it; the return goes back to
;; <OUTPUT_STATE_LINE_START>.
;; In: A = the character
;; Entry: EndLine = goes back to <OUTPUT_STATE_LINE_START> and prints, whatever the character
;; Also: COS2 (DOS33, DOS31)
.proc PlainLine
    cmp #KEY_RETURN
    bne EchoExit::Always

;; Also: COS2A (DOS33)
EndLine:
    ldx #OUTPUT_STATE_LINE_START
    stx a:OutputState
    jmp EchoExit::Always
.endproc

;; State <OUTPUT_STATE_ECHO>: the echo of a character just read through <InputHandler>.
;;
;; Prints it, unless it came from an EXEC file, when only MON I shows it. At a return, if the line was typed in
;; direct mode or came from an EXEC file, it is a possible command: the line is already in <InputBuffer>, where
;; GETLN keeps it, so <CommandLine::StoreAtX> adds the return and scans it. Lines a running program reads with
;; INPUT are left alone.
;; In: A = the character
;; Also: COS3 (DOS33, DOS31)
.proc Echo
    ldx #OUTPUT_STATE_LINE_START
    stx a:OutputState
    cmp #KEY_RETURN
    beq AtReturn

;; Also: COS3B (DOS33, DOS31)
ShowIfExec:
    lda a:ExecState
    beq EchoExit::Always
    bne EchoExit::Read

;; Also: COS3A (DOS33, DOS31)
AtReturn:
    pha
    sec                             ; from an EXEC file: as if in direct mode
    lda a:ExecState
    bne CheckDirect
    jsr TestProgramRunning                      ; carry set in direct mode, clear while a program runs

;; Also: COS3C (DOS33)
CheckDirect:
    pla
    bcc ShowIfExec
    ldx a:HookX                       ; GETLN's X: the length of the line
    jmp CommandLine::StoreAtX
.endproc

;; State <OUTPUT_STATE_FILE_LINE>: WRITE is on and this is not the first character of a line. Writes the character
;; to the file (<TextFile::WriteCharacter>); shown only under MON O. A return moves to <OUTPUT_STATE_FILE_LINE_START>.
;; In: A = the character
;; Entry: Write = writes the character whatever it is, keeping the state
;; Also: COS4 (DOS33, DOS31)
.proc FileLine
    cmp #KEY_RETURN
    bne Write
    lda #OUTPUT_STATE_FILE_LINE_START
    sta a:OutputState

;; Also: COS4A (DOS33, DOS31)
Write:
    jsr TextFile::WriteCharacter
    jmp EchoExit::Written
.endproc

;; State <OUTPUT_STATE_FILE_LINE_START>: WRITE is on and this is the first character of a line.
;;
;; A Control-D starts a command, as at <OUTPUT_STATE_LINE_START>; a line feed is written without leaving the
;; state; anything else is written in <OUTPUT_STATE_FILE_LINE>.
;; In: A = the character
;; Also: COS5 (DOS33, DOS31)
.proc FileLineStart
    cmp a:CommandCharacter
    beq LineStart
    cmp #KEY_LINE_FEED
    beq FileLine::Write
    ldx #OUTPUT_STATE_FILE_LINE
    stx a:OutputState
    bne FileLine                    ; always
.endproc

;; State <OUTPUT_STATE_FILE_ECHO>: the echo of a character read from a file (<TextFile::ReadCharacter> sets this state),
;; and <LineStart> sends INPUT's "?" here while READ is on. Shown only under MON I; goes back to
;; <OUTPUT_STATE_LINE_START>.
;; Also: COS6 (DOS33, DOS31)
.proc FileEcho
    lda #OUTPUT_STATE_LINE_START
    sta a:OutputState
    beq EchoExit::Read              ; always
.endproc

;; Finishes a RUN under Applesoft.
;;
;; <Commands::Run> (LoadSave.asm) sets <RunPending>, then loads the program, and an Applesoft load ends by jumping into
;; Applesoft through <BasicRelink> instead of returning. So the RUN is finished here, when Applesoft next prints at the
;; start of a line: <Commands::Run::AfterLoad> starts the program.
;; Also: COS7 (DOS33)
.proc FinishRun
    lda #0
    sta a:RunPending
    jsr ConnectDos
    jmp Commands::Run::AfterLoad
.endproc

.endscope

;; Where a command handler returns (through <Scanner::Execute>): ends the command line and leaves DOS.
;;
;; A line BASIC printed after a Control-D is simply finished. A line typed at the prompt is replaced by an empty
;; one, a return at $0200 with X = 0, so that GETLN hands BASIC a blank line instead of the DOS command. Falls into
;; <EchoExit>.
;; In: HookA = the return that ended the line
;; Also: CERTN (DOS33, DOS31)
.proc EndCommand
    lda InputBuffer
    cmp a:CommandCharacter
    beq EchoExit
    lda #KEY_RETURN
    sta InputBuffer
    ldx #0
    stx a:HookX                       ; GETLN's line length on return
    ; Falls into EchoExit.
.endproc

;; Leaves DOS from an output state, printing the character in <HookA> as MON asks: entered here, only if MON C is
;; on.
;;
;; Each entry prints the character only if its MON option is on (an ECHO_ bit of <EchoFlags>); <EchoExit::Always>
;; always prints it. All end at <ExitDos>.
;; Entry: Written = only under MON O (file output), Read = only under MON I (file input), IfEchoed = with A = the
;;   ECHO_ bit, Always = always
;; Also: CMDRTN (DOS33, DOS31)
.proc EchoExit
    lda #ECHO_COMMANDS
    bne IfEchoed

;; Also: DRTNO (DOS33, DOS31)
Written:
    lda #ECHO_OUTPUT
    bne IfEchoed

;; Also: DRTNI (DOS33, DOS31)
Read:
    lda #ECHO_INPUT

;; Also: MODECK (DOS33, DOS31)
IfEchoed:
    and a:EchoFlags
    beq ExitDos

;; Also: PRRTN (DOS33, DOS31)
Always:
    jsr LoadCaller
    jsr CallRealOutput
    sta a:HookA                       ; return the registers as it leaves them
    sty a:HookY
    stx a:HookX
    ; Falls into ExitDos.
.endproc

;; Leaves DOS: puts DOS's hooks back in $36-$39, resets the stack pointer to what it was on entry to
;; <InputHandler> or <OutputHandler>, and returns to their caller with the saved registers.
;;
;; Any routine in DOS may jump here, however deep: the stack reset discards whatever is above the caller's return
;; address. Falls into <LoadCaller>.
;; Out: A, X, Y = <HookA>, <HookX>, <HookY>, carry = set
;; Also: ORTN (DOS33, DOS31)
.proc ExitDos
    jsr ConnectDos
    ldx a:HookStackPointer
    txs
    ; Falls into LoadCaller.
.endproc

;; Loads A, X and Y from <HookA>, <HookX> and <HookY>.
;; Out: A, X, Y = <HookA>, <HookX>, <HookY>, carry = set
;; Also: LDREGS (DOS33, DOS31)
.proc LoadCaller
    lda a:HookA
    ldy a:HookY
    ldx a:HookX
    sec
    rts
.endproc

;; Calls the real output routine, whose address <SaveCaller> has put back in <OutputHook>.
;; Also: ORTN1 (DOS33, DOS31)
.proc CallRealOutput
    jmp (OutputHook)
.endproc

;; Prints a return through the real output routine.
;; Also: PRCRIF (DOS33, DOS31)
.proc OutputReturn
    lda #KEY_RETURN
    jmp CallRealOutput
.endproc
