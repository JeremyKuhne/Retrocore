; retrocore: style=strict
;; The Monitor's examine and arithmetic commands, its hexadecimal and character output, and its M, V and L
;; commands ($FDA3-$FE74).

; Sizes and counts.

;; The bytes <Commands::ExamineLine> shows on a line. A line starts at an address that is a multiple of it, so one
;; less is the mask of an address's place in its line.
BYTES_PER_LINE = 8

;; What a hexadecimal digit's character is moved by when the digit is 10 to 15: the letters before A, after 9.
LETTER_OFFSET = 'A' - '9' - 1

;; The instructions <ListInstructions> disassembles for one L command.
LIST_LENGTH = 20

;; The handlers of the Monitor's commands that are not documented routines of their own, and the parts of the
;; command line that only <Commands::Routines> and <CommandLine> reach.
;;
;; <CommandLine> reads each number and the character after it with <ReadHexNumber>, finds the character in
;; <Commands::Keys>, and runs its handler through <Commands::RunCommand>. A handler is entered with:
;;
;; - A = <MODE>, the command that was waiting for this number (".", ":", "+" or "-"), or 0 for none, and the
;;   byte itself cleared;
;; - X = 1 when a number came before the command character, 0 when none did;
;; - Y = 0;
;; - <A1L>/<A1H> and <A3L>/<A3H> = the last number typed with no command waiting, the first of a range, and
;;   <A2L>/<A2H> = the last number typed.
;;
;; The scope is in nine pieces on the Enhanced IIe and eight in the other builds, because the Monitor's documented
;; routines sit between its parts at fixed addresses. Each handler's address minus one must be in page $FE, after its
;; first byte (<Commands::Routines>).
.scope Commands

;; Examines memory from A1 to the end of its line of 8 bytes: a carriage return alone after another command.
;; In: A1L/A1H = the first address, Y = 0
;; Out: A1L/A1H = the address after the last byte shown
;; Entry:
;;   Range = examines memory from A1 to A2, 8 bytes a line: a carriage return, "AAAA-" and the bytes, each after a blank
;; Also: XAM8 (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc ExamineLine
    ; The line ends at A1's last address with the same high bits.
    lda A1L
    ora #BYTES_PER_LINE - 1
    sta A2L
    lda A1H
    sta A2H

;; Starts a new line, printing its address, when A1 is at a multiple of 8.
;; Also: MOD8CHK (A2RM79, IIEROM82, IIETRM85)
CheckLineStart:
    lda A1L
    and #BYTES_PER_LINE - 1
    bne PrintByte

;; Examines memory from A1 to A2, 8 bytes a line: a carriage return, "AAAA-" and the bytes, each after a blank.
;; In: A1L/A1H = the first address, A2L/A2H = the last, Y = 0
;; Out: A1L/A1H = the address after A2
;; Also: XAM (A2RM78, A2RM79, IIEROM82, IIETRM85)
Range:
    jsr PrintAddress

;; Prints the byte at A1 as " xx", then steps A1 to the next until it passes A2.
;; Also: DATAOUT (A2RM78, A2RM79, IIEROM82, IIETRM85)
PrintByte:
    lda #' '
    jsr CharacterOut
    lda (A1L),y
    jsr PrintHexByte
    jsr NextInRange
    bcc CheckLineStart

;; The return when A1 has passed A2.
;; Also: RTS4C (A2RM78, A2RM79, IIEROM82, IIETRM85)
Done:
    rts
.endproc

;; The ".", "+" and "-" commands, run by the number after them: "." examines A1 to A2, and "+" and "-" print
;; <A1L> plus or minus <A2L> as "=xx".
;;
;; <Commands::Blank> comes here when a blank or carriage return ends the number, and the waiting command is not ":". A
;; number with no command waiting comes here too, and with A1 = A2 shows its one byte.
;; In: A = the waiting command, or 0 for none, A1L/A1H = the first number, A2L/A2H = the second, Y = 0
;; Also: XAMPM (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc ExamineOrCalculate
    ; Bit 0 is clear for "." ($AE) and 0: examine.
    lsr a
    bcc ExamineLine::Range

    ; Bit 2 is clear for "+" ($AB) and set for "-" ($AD). For "-", the carry it leaves set makes adding the
    ; complement a subtraction.
    lsr a
    lsr a
    lda A2L
    bcc Add
    eor #$FF

;; Adds <A1L> to <A2L>, or to its complement for "-", and prints "=" and the result.
;; Also: ADD (A2RM78, A2RM79, IIEROM82, IIETRM85)
Add:
    adc A1L
    pha
    lda #'='
    jsr CharacterOut
    pla
    ; Falls into PrintHexByte.
.endproc

.endscope

;; Prints a byte as two hexadecimal digits.
;;
;; At $FDDA.
;; In: A = the byte
;; Also: PRBYTE (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc PrintHexByte
.assert * = $FDDA, "PrintHexByte must stay at $FDDA."
    ; The high nibble first.
    pha
    lsr a
    lsr a
    lsr a
    lsr a
    jsr PrintHexDigit::Unmasked

    ; Then the low one.
    pla
    ; Falls into PrintHexDigit.
.endproc

;; Prints the low nibble of A as a hexadecimal digit.
;;
;; At $FDE3.
;; In: A = the nibble, in bits 0-3
;; Entry:
;;   Unmasked = prints A, 0 to 15, as a hexadecimal digit
;; Also: PRHEX (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc PrintHexDigit
.assert * = $FDE3, "PrintHexDigit must stay at $FDE3."
    and #$0F

;; Prints A, 0 to 15, as a hexadecimal digit.
;; In: A = the digit, 0 to 15
;; Also: PRHEXZ (A2RM78, A2RM79, IIEROM82, IIETRM85)
Unmasked:
    ora #'0'
    cmp #'9' + 1
    bcc CharacterOut

    ; 10 to 15 are A to F. The carry is set.
    adc #LETTER_OFFSET - 1
    ; Falls into CharacterOut.
.endproc

;; Prints a character through the output hook, <CSWL>/<CSWH>: on the screen through <ScreenOut>, or to the routine
;; a program or `PR#` set.
;;
;; At $FDED.
;; In: A = the character, with its high bit set
;; Also: COUT (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc CharacterOut
.assert * = $FDED, "CharacterOut must stay at $FDED."
    jmp (CSWL)
.endproc
.if ENHANCED

;; The screen's output routine, the output hook's default: prints a character, applying <INVFLG> to a printable
;; one.
;;
;; At $FDF0. A character below $A0, a control character, is printed as it is. In 80 columns the
;; firmware applies the mask itself and A comes back as given; in 40 columns a printable character comes back with
;; the mask applied.
;; In: A = the character, with its high bit set
;; Out: A = the character as printed
;; Keeps: Y
;; Also: COUT1 (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc ScreenOut
.assert * = $FDF0, "ScreenOut must stay at $FDF0."
    pha
    cmp #' '
    jmp ApplyInverse
.endproc

;; Prints a character on the screen as it is, without <INVFLG>.
;;
;; At $FDF6. In 80 columns the firmware prints it; in 40 columns <ScreenOutPausing at ScreenOutPausing>
;; does, with the Control-S pause.
;; In: A = the character, with its high bit set
;; Keeps: A, Y
;; Entry:
;;   Pushed = prints a character, with the one for 80 columns already pushed
;; Also: COUTZ (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc ScreenOutNoInverse
.assert * = $FDF6, "ScreenOutNoInverse must stay at $FDF6."
    pha

;; Prints a character, with the one for 80 columns already pushed.
;;
;; <ApplyInverse at ApplyInverse> comes here with the character as given pushed and A = the character with <INVFLG>
;; applied. <ScreenOutByWidth at ScreenOutByWidth@Enhanced> prints the pushed one in 80 columns, and A in 40.
;; In: A = the character for 40 columns, with the one for 80 columns on the stack
Pushed:
    sty YSAV1
    tay
    pla
    jmp ScreenOutByWidth

    ; Two unused bytes.
    .byte $EA, $EA
.endproc
.else

;; The screen's output routine, the output hook's default: prints a character, applying <INVFLG> to a printable
;; one.
;;
;; At $FDF0. A character below $A0, a control character, is printed as it is.
;; In: A = the character, with its high bit set
;; Out: A = the character as printed, with <INVFLG> applied when printable
;; Keeps: Y
;; Also: COUT1 (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc ScreenOut
.assert * = $FDF0, "ScreenOut must stay at $FDF0."
    cmp #' '
    bcc ScreenOutNoInverse
    and INVFLG
    ; Falls into ScreenOutNoInverse.
.endproc

;; Prints a character on the screen as it is, without <INVFLG>.
;;
;; At $FDF6. The Apple II Monitor prints with <ScreenOutDirect at ScreenOutDirect>; the others with
;; <ScreenOutPausing at ScreenOutPausing>, which adds the Control-S pause.
;; In: A = the character, with its high bit set
;; Keeps: A, Y
;; Also: COUTZ (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc ScreenOutNoInverse
.assert * = $FDF6, "ScreenOutNoInverse must stay at $FDF6."
    sty YSAV1
    pha
.if MONITOR = MONITOR_II
    jsr ScreenOutDirect
.else
    jsr ScreenOutPausing
.endif
    pla
    ldy YSAV1
    rts
.endproc
.endif

; Commands: the Return, blank, mode and "<" handlers, after the character output.
.scope Commands continued

;; A carriage return: alone on its line, examines the next line of 8 bytes; otherwise ends a number as a blank does.
;;
;; $FE00 in every build, which Integer `BASIC` calls. <Commands::Return> calls it. A carriage return is alone when
;; it is the line's first character, so that <YSAV>, the index after it, counts down to 0.
;; In: A = the waiting command, or 0, X = 1 after a number, 0 when none, Y = 0
;; Also: BL1 (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc ExamineNextOrBlank
.assert * = $FE00, "ExamineNextOrBlank must stay at $FE00, where Integer BASIC calls it."
    dec YSAV
    beq ExamineLine
    ; Falls into Blank.
.endproc

;; A blank, or a carriage return through <Commands::ExamineNextOrBlank>: runs the waiting command with the number
;; before it.
;;
;; After ":" it stores the number's low byte at A3 and keeps ":" waiting, so each number after it is stored in
;; the next byte. Any other waiting command, or none, goes to <Commands::ExamineOrCalculate>. With no number
;; before it, the waiting command stays waiting.
;; In: A = the waiting command, or 0, X = 1 after a number, 0 when none, Y = 0
;; Also: BLANK (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc Blank
    dex
    bne SetMode::FromA
    cmp #':'
    bne ExamineOrCalculate

;; Stores A2L at A3 and steps A3 to the next byte, keeping ":" waiting.
;; In: A = ":", A2L = the byte, A3L/A3H = where, Y = 0
;; Also: STOR (A2RM78, A2RM79, IIEROM82, IIETRM85)
Store:
    sta MODE
    lda A2L
    sta (A3L),y
    inc A3L
    bne Done
    inc A3H

;; The return.
;; Also: RTS5 (A2RM78, A2RM79, IIEROM82, IIETRM85)
Done:
    rts
.endproc

;; ".", ":", "+" and "-": waits for the next number, setting <MODE> to the command character.
;;
;; Its rts, at $FE1F, is one the Disk 3.5 firmware calls as a routine that does nothing on the IIe.
;; Entry:
;;   FromA = sets <MODE> to A
;; Also: SETMODE (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc SetMode
    ; The command character is the one before IN,YSAV.
    ldy YSAV
    lda IN - 1,y

;; Sets <MODE> to A.
;; In: A = the command, or 0 for none
;; Also: SETMDZ (A2RM78, A2RM79, IIEROM82, IIETRM85)
FromA:
    sta MODE
    rts
.endproc

;; "<": sets the destination of the next command, A4 and A5, to the number before it, A2.
;;
;; M and V take their destination from A4, and the Enhanced IIe's S its value.
;; Also: LT (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc Destination
    ; Both bytes.
    ldx #1

;; Copies X + 1 bytes of A2 to A4 and A5.
;; In: X = the index of the last byte, 1 for both
;; Out: X = $FF
;; Also: LT2 (A2RM78, A2RM79, IIEROM82, IIETRM85)
Copy:
    lda A2L,x
    sta A4L,x
    sta A5L,x
    dex
    bpl Copy
    rts
.endproc

.endscope

;; M: copies the bytes from A1 to A2 to A4 on.
;;
;; At $FE2C. It copies upward a byte at a time, so a destination inside the source and above its
;; start repeats the source's first bytes: 301<300.3FEM fills $301-$3FF with the byte at $300.
;; In: A1L/A1H = the first address, A2L/A2H = the last, A4L/A4H = the destination, Y = 0
;; Out: A1L/A1H = the address after A2, A4L/A4H = the address after the last copied
;; Also: MOVE (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc MoveMemory
.assert * = $FE2C, "MoveMemory must stay at $FE2C."
    lda (A1L),y
    sta (A4L),y
    jsr NextInRangeAndTarget
    bcc MoveMemory
    rts
.endproc

;; V: compares the bytes from A1 to A2 with those from A4 on, printing each difference as "AAAA-xx (yy)".
;;
;; At $FE36. AAAA is the address in A1's range, xx its byte and yy the byte at A4.
;; In: A1L/A1H = the first address, A2L/A2H = the last, A4L/A4H = the other range, Y = 0
;; Out: A1L/A1H = the address after A2
;; Also: VFY (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc VerifyMemory
.assert * = $FE36, "VerifyMemory must stay at $FE36."
    lda (A1L),y
    cmp (A4L),y
    beq Next

    ; A difference.
    jsr PrintAddress
    lda (A1L),y
    jsr PrintHexByte
    lda #' '
    jsr CharacterOut
    lda #'('
    jsr CharacterOut
    lda (A4L),y
    jsr PrintHexByte
    lda #')'
    jsr CharacterOut
Next:
    jsr NextInRangeAndTarget

;; The test for the end of the range.
;; Also: VFYOK (A2RM78, IIEROM82, IIETRM85)
Continue:
    bcc VerifyMemory
    rts
.endproc

;; L: disassembles 20 instructions, from A1 when the command gave an address, or else from PC.
;;
;; At $FE5E.
;; In: X = 1 when the command gave an address, 0 when not, A1L/A1H = the address
;; Out: PCL/PCH = the address after the last instruction
;; Also: LIST (A2RM78, A2RM79, IIEROM82, IIETRM85)
.proc ListInstructions
.assert * = $FE5E, "ListInstructions must stay at $FE5E."
    jsr SetPcFromA1
    lda #LIST_LENGTH

;; Disassembles the instruction at PC and moves PC past it, counting the instructions on the stack.
;; Also: LIST2 (A2RM78, A2RM79, IIEROM82, IIETRM85)
Next:
    pha
    jsr Disassembler::PrintInstruction
    jsr NextInstruction
    sta PCL
    sty PCH
    pla
    sec
    sbc #1
    bne Next
    rts
.endproc
