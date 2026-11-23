; retrocore: style=strict
;; The Monitor's entry and command line: the Apple II Monitor's reset routine, the * prompt, the hexadecimal number
;; reader, the command table, and the 6502's vectors ($FF59-$FFFF).

; Hexadecimal numbers.

;; The decimal digits, which <ReadHexNumber> tells from other characters by their value EOR "0".
DECIMAL_DIGITS = 10

;; The lowest code <ReadHexNumber> gives a letter digit: "A"'s. The codes from it up are "A" to "F".
HEX_LETTER_CODE = (('A' ^ '0') + KEY_CODE_OFFSET) & $FF

; The Apple II Monitor has none of the later Monitors' power-up code, so Startup opens here, empty, in its build;
; every build then continues it.
.if MONITOR = MONITOR_II

;; Taking the machine from reset to a program. The Apple II Monitor has only <Startup::ResetToMonitor>, its reset
;; handler, which enters the Monitor; the user starts `BASIC` by hand.
.scope Startup
.endscope
.endif

; Startup: ResetToMonitor, at $FF59.
.scope Startup continued

;; Sets normal text, text mode with a full window (<InitDisplay>), and the screen and keyboard hooks, then enters the
;; Monitor.
;;
;; At $FF59. It is the Apple II Monitor's reset handler, which <ResetVector> points at and which the 1978 listing names
;; `RESET`; that name stays in prose here, as the later Monitors' listings give it to their own reset handler,
;; <Startup::Reset>. That handler does the same set-up itself, and programs jump here to enter the Monitor.
;; Also: OLDRST (A2RM79, IIEROM82, IIETRM85)
.proc ResetToMonitor
.assert * = $FF59, "Startup::ResetToMonitor must stay at $FF59."
    jsr SetNormal
    jsr InitDisplay
    jsr SetScreen
    jsr SetKeyboard
    ; Falls into EnterMonitor.
.endproc

.endscope

;; Enters the Monitor with a beep: the command line, with decimal mode cleared.
;;
;; At $FF65. A BRK comes here after showing the registers.
;; Also: MON (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc EnterMonitor
.assert * = $FF65, "EnterMonitor must stay at $FF65."
    cld
    jsr Beep
    ; Falls into CommandLine.
.endproc

;; The Monitor's command line: prompts with "*", reads a line, and runs its commands, then prompts again.
;;
;; $FF69 in every build, which `CALL -151` enters from `BASIC`. A key that is no command beeps and starts over.
;; Also: MONZ (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc CommandLine
.assert * = $FF69, "CommandLine must stay at $FF69."
    lda #'*'
    sta PROMPT
    jsr GetLineAfterReturn
    jsr ClearMode

;; Reads a number and the character after it, and runs that command.
;; In: Y = the index in <IN>
;; Also: NXTITM (A2RM78, A2RM79, IIEROM82, IIETRM85)
NextItem:
    jsr ReadHexNumber
    sty YSAV
    ldy #Commands::Routines - Commands::Keys

;; Looks the character up in the key table, from its end.
;; Also: CHRSRCH (A2RM78, A2RM79, IIEROM82, IIETRM85)
Search:
    dey
    bmi EnterMonitor
    cmp Commands::Keys,y
    bne Search

    ; Runs it, then goes on after it.
    jsr Commands::RunCommand
    ldy YSAV
    jmp NextItem
.endproc

; Commands: the digits of a number, after the command line.
.scope Commands continued

;; Shifts a hexadecimal digit into A2, then copies the number to A1 and A3 and reads on.
;; In: A = the digit, in bits 0-3
;; Entry:
;;   NextBit = shifts the top bit of A into A2 X + 1 times
;; Also: DIG (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc ShiftDigit
    ; The digit's 4 bits, from the top of A.
    ldx #3
    asl a
    asl a
    asl a
    asl a

;; Shifts the top bit of A into A2 X + 1 times.
;; In: A = the bits, X = the count less one
;; Also: NXTBIT (A2RM78, A2RM79, IIEROM82, IIETRM85)
NextBit:
    asl a
    rol A2L
    rol A2H
    dex
    bpl NextBit
    ; Falls into CopyNumber.
.endproc

;; Copies the number in A2 to A1 and A3, unless a command is waiting for it, then reads the next character.
;;
;; It starts with X = $FF, so that <A2H>,X is <A2L> in page zero.
;; In: X = $FF
;; Out: X = 1
;; Also: NXTBAS (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc CopyNumber
    lda MODE
    bne Next
    lda A2H,x
    sta A1H,x
    sta A3H,x

;; The next byte: the high one after the low one, then the next character.
;; Also: NXTBS2 (A2RM78, A2RM79, IIEROM82, IIETRM85)
Next:
    inx
    beq CopyNumber
    bne ReadHexNumber::NextCharacter
.endproc

.endscope

;; Reads a hexadecimal number from the input line into A2, and returns the character after it as a command code.
;;
;; At $FFA7. Each digit also copies the number to A1 and A3 unless a command is waiting (<MODE>). The
;; code is (character EOR "0") + $89, as <Commands::Keys> holds them. On the Enhanced IIe it reads the line in
;; uppercase, so a to f are digits too, and an apostrophe makes the character after it 8 bits of the number
;; (<Commands::LetterOrQuote>).
;; In: Y = the index in <IN>
;; Out: A = the code, Y = the index after the character, A2L/A2H = the number, X = 1 after a digit, 0 when none
;; Entry:
;;   NextCharacter = reads the next character of the number
;; Also: GETNUM (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc ReadHexNumber
.assert * = $FFA7, "ReadHexNumber must stay at $FFA7."
    ldx #0
    stx A2L
    stx A2H

;; Reads the next character of the number.
;; In: Y = the index in <IN>
;; Also: NXTCHR (A2RM78, A2RM79, IIEROM82, IIETRM85)
NextCharacter:
.if ENHANCED
    ; In uppercase.
    jsr NextInputCharacter
    nop
.else
    lda IN,y
    iny
.endif

    ; 0 to 9 are digits as they are, and A to F become $FA to $FF.
    eor #'0'
    cmp #DECIMAL_DIGITS
    bcc Commands::ShiftDigit
    adc #KEY_CODE_OFFSET - 1
    cmp #HEX_LETTER_CODE
.if ENHANCED
    jmp Commands::LetterOrQuote
.else
    bcs Commands::ShiftDigit
    rts
.endif
.endproc

; Commands: running a handler, after ReadHexNumber.
.scope Commands continued

;; Runs the command at index Y of <Commands::Keys>, by returning to its handler's address minus one.
;;
;; $FFBE in every build, which Integer `BASIC` calls. The handler is entered as <Commands> says.
;; In: Y = the command's index
;; Out: A = MODE, Y = 0, MODE = 0
;; Also: TOSUB (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc RunCommand
.assert * = $FFBE, "Commands::RunCommand must stay at $FFBE, where Integer BASIC calls it."
    lda #COMMAND_PAGE
    pha
    lda Routines,y
    pha
    lda MODE
    ; Falls into ClearMode, which returns to the handler.
.endproc

.endscope

;; Clears <MODE>, so that no command is waiting for a number.
;;
;; At $FFC7.
;; Out: Y = 0
;; Keeps: A, X
;; Also: ZMODE (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc ClearMode
.assert * = $FFC7, "ClearMode must stay at $FFC7."
    ldy #0
    sty MODE
    rts
.endproc

; Commands: the key table, after ClearMode.
.scope Commands continued

;; The page of every command handler's address minus one, which <Commands::RunCommand> pushes.
COMMAND_PAGE = $FE

;; The commands <Command> has added so far: at the end, the length of <Commands::Keys> and
;; <Commands::Routines>.
.set CommandCount, 0

;; One command of the key table: its key and the routine that runs it.
;; Parameters:
;;   key = the key, with its high bit set
;;   handler = the routine, in page $FE after its first byte
.macro Command key, handler
    .ident(.sprintf("COMMAND_KEY_%d", CommandCount)) = (((key) ^ '0') + KEY_CODE_OFFSET) & $FF
    .ident(.sprintf("COMMAND_SUB_%d", CommandCount)) = <(handler - 1)
    .assert >(handler - 1) = COMMAND_PAGE, "A Monitor command handler must follow the first byte of page $FE."
    .set CommandCount, CommandCount + 1
.endmacro

    ; The commands. <CommandLine> searches from the end, so a later entry for the same key wins.
    Command KEY_CTRL_C, ContinueBasic
    Command KEY_CTRL_Y, User
    Command KEY_CTRL_E, Registers
.if ENHANCED
    Command '!', Assemble
.elseif MONITOR = MONITOR_II
    Command 'T', Trace
.else
    ; Left from the T command; the later Control-Y entries hide it.
    Command KEY_CTRL_Y, Trace
.endif
    Command 'V', VerifyMemory
    Command KEY_CTRL_K, SetInput::FromA2
.if ENHANCED
    Command 'S', Search
.elseif MONITOR = MONITOR_II
    Command 'S', Step
.elseif MONITOR = MONITOR_AUTOSTART
    ; Left from the S command: this one wins, and its five NOPs run into User.
    Command KEY_CTRL_Y, Step + 1
.else
    ; Left from the S command: this one wins.
    Command KEY_CTRL_Y, UserText
.endif
    Command KEY_CTRL_P, SetOutput::FromA2
    Command KEY_CTRL_B, StartBasic
    Command '-', SetMode
    Command '+', SetMode
    Command 'M', MoveMemory
    Command '<', Destination
    Command 'N', SetNormal
    Command 'I', SetInverse
    Command 'L', ListInstructions
    Command 'W', WriteCassette
    Command 'G', Go
    Command 'R', ReadCassette
    Command ':', SetMode
    Command '.', SetMode
    Command KEY_CR, Return
    Command ' ', Blank

;; The command keys, as <ReadHexNumber> returns them.
;; Also: CHRTBL (A2RM78, A2RM79, IIEROM82, IIETRM85)
Keys:
.repeat CommandCount, index
    .byte .ident(.sprintf("COMMAND_KEY_%d", index))
.endrepeat

;; Each command's handler: the low byte of its address minus one, in <Commands::COMMAND_PAGE>.
;; Also: SUBTBL (A2RM78, A2RM79, IIEROM82, IIETRM85)
Routines:
.repeat CommandCount, index
    .byte .ident(.sprintf("COMMAND_SUB_%d", index))
.endrepeat

.endscope

;; The 6502's non-maskable interrupt vector: <NMI>, in page three, where a program puts a jump.
;;
;; At $FFFA.
;; Also: NMIVEC (UNKN)
NmiVector:
.assert * = $FFFA, "NmiVector must be at $FFFA, the 6502's NMI vector."
    .word NMI

;; The 6502's reset vector: <Startup::ResetToMonitor> on the Apple II Monitor, <Startup::Reset> on the others.
;;
;; At $FFFC.
;; Also: RESETVEC (UNKN)
ResetVector:
.if MONITOR = MONITOR_II
    .word Startup::ResetToMonitor
.else
    .word Startup::Reset
.endif

;; The 6502's IRQ and BRK vector: <Interrupt>, or on the Enhanced IIe the internal firmware's handler at $C3FA.
;;
;; At $FFFE.
;; Also: IRQVEC (UNKN)
IrqVector:
.if ENHANCED
    .word IRQHANDLER
.else
    .word Interrupt
.endif
.assert * = $10000, "The Monitor must end at $FFFF."
