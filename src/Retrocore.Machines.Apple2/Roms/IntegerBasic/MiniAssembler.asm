; retrocore: style=strict
;; Integer BASIC: the Mini-Assembler, and the end of the floating point ($F500-$F668)
;;
;; Steve Wozniak and Allen Baum's one-line assembler, which shares the Integer BASIC chips (<MiniAssembler>), and
;; between its routines and its entry point the floating-point routines' last two, <Float::ShiftTowardInteger> and
;; <Float::ToInteger> ($F63D-$F65D; FloatingPoint.asm has the rest).
;;
;; Names follow Apple's listing in the Apple II Reference Manual (1978), kept as each definition's historical names.
;; Part of IntegerBasic.asm; it follows FloatingPoint.asm, at $F500.

;; The Mini-Assembler: assembles one instruction a line, at the address the line gives or after the last one.
;;
;; From the Monitor, F666G starts it (<MiniAssembler::Run>), and it prompts with "!". A line is:
;;
;; - an address and a colon, then an instruction, as in "300: LDA #$01", which sets the address;
;; - a blank, then an instruction, which assembles after the last instruction;
;; - "$" and a Monitor command, such as "$300L" to list or "$FF69G" to go back to the Monitor.
;;
;; An instruction is a mnemonic and its operand written as the Monitor's disassembler writes it; "$" may be left out
;; of a number, and a ";" starts a comment. The Mini-Assembler packs the mnemonic's three letters as the
;; disassembler's tables do (<MnemonicsLeft>, <MnemonicsRight>), reads the operand into a format of the address mode
;; characters the disassembler prints (<FormatCharacter1>, <FormatCharacter2>), and then tries every opcode:
;; <Disassembler::Decode::Opcode> gives each one's mnemonic and format, and the first that matches both is the one.
;; The instruction is stored, the line is shown again as the disassembler lists it, and the address moves on. An
;; error prints a caret under the place where reading stopped and sounds the bell.
.scope MiniAssembler

; Operand formats, as the Monitor's disassembler packs them.

;; Inherit: <Monitor:Disassembler::OPERAND_DOLLAR>
OPERAND_DOLLAR = $80

;; Inherit: <Monitor:Disassembler::OPERAND_IMMEDIATE>
OPERAND_IMMEDIATE = $20

;; Inherit: <Monitor:Disassembler::RELATIVE_FORMAT>
RELATIVE_FORMAT = $9D

;; Inherit: <Monitor:Disassembler::FORMAT_POSITIONS>
FORMAT_POSITIONS = 6

;; The format position at which the operand's number is read: after "#$" and before ",X".
NUMBER_POSITION = 3

;; The format <MiniAssembler::ParseOperand> gives an operand of one byte written with "$" and no other characters:
;; a branch takes it, or the two-byte one after it.
ADDRESS_FORMAT = OPERAND_DOLLAR | 1

; Mnemonics.

;; The letters of a mnemonic.
MNEMONIC_LETTERS = 3

;; Inherit: <Monitor:Disassembler::LETTER_BITS>
LETTER_BITS = 5

;; What <MiniAssembler::ParseMnemonic> takes from a letter shifted left: it leaves the letter's code, counted from "?"
;; as the Monitor's mnemonics count it, in bits 1-5, below bits 6 and 7 set.
LETTER_OFFSET = $BE

;; What <MiniAssembler::LETTER_OFFSET> leaves for "@", the first character a mnemonic letter may be.
FIRST_LETTER_CODE = $C2

; The Monitor's command keys.

;; The code <ReadHexNumber> leaves in A for a ":" after the address, as the Monitor's commands read their keys: the
;; character, exclusive-or "0", plus $89.
COLON_CODE = ((':' ^ '0') + $89) & $FF

;; The keys in the Monitor's <Commands::Keys>.
COMMAND_KEY_COUNT = 23

;; The place of the Return key in <Commands::Keys>.
RETURN_KEY_INDEX = 21

; The Mini-Assembler's page zero: two of the Monitor's locations.

;; The length of the operand typed: 1 or 2 bytes, or 0 for none.
;;
;; <MiniAssembler::FindOpcode> counts it down to try a one-byte operand as two bytes. The location is the one the
;; Monitor's listing calls YSAV1, at $35.
;; Also: L (A2RM78)
TypedLength = $35

;; The format of the operand typed: a bit for each address mode character matched, from "$" in bit 7 to ",Y" in bit
;; 2, then the operand's length in the low two bits, as <Disassembler::FormatBits> has an opcode's.
;;
;; The location is the Monitor's A5L, at $44.
;; Also: FMT (A2RM78)
TypedFormat = $44

;; Assembles a relative branch: the offset from the instruction after it to the target in <Address2>, or <Error> when
;; the target is out of reach. Falls into <StoreInstruction>.
;; In: A = the operand's format, carry = set, Address2/Address2High = the target
;; Out: Address2 = the offset
;; Also: REL (A2RM78)
.proc Branch

    ; The operand must be a plain address: ADDRESS_FORMAT, or the two-byte one after it.
    sbc #ADDRESS_FORMAT
    lsr a
    bne ToError

    ; The target less the instruction's address and its 2 bytes.
    ldy Address2High
    ldx Address2
    bne Offset
    dey

;; Also: REL2 (A2RM78)
Offset:
    dex
    txa
    clc
    sbc ProgramCounter
    sta Address2
    bpl Page
    iny

;; The high byte must say the offset fits in a signed byte: 0, or $FF for a branch backward.
;; Also: REL3 (A2RM78)
Page:
    tya
    sbc ProgramCounterHigh

;; Also: ERR3 (A2RM78)
ToError:
    bne Error
    ; Falls into StoreInstruction.
.endproc

;; Stores the assembled instruction at <ProgramCounter>, shows it over the line typed, moves the address past it and
;; reads the next line.
;;
;; The instruction is the opcode in <Address1High> and the operand in <Address2> and <Address2High>, which follow it
;; in page zero. <Disassembler::PrintInstruction> lists the instruction over the line typed.
;; In: OperandLength = the operand's bytes, as <Disassembler::Decode::Opcode> left it
;; Also: FINDOP (A2RM78)
.proc StoreInstruction

;; The instruction as assembled: the opcode, then the operand.
Instruction = Address1High

    ldy OperandLength

;; Also: FNDOP2 (A2RM78)
NextByte:
    lda Instruction,y
    sta (ProgramCounter),y
    dey
    bpl NextByte

    ; Up two lines, as the listing starts with a Return, which brings it back down to the line typed.
    jsr CursorUp
    jsr CursorUp
    jsr Disassembler::PrintInstruction
    jsr NextInstruction
    sty ProgramCounterHigh
    sta ProgramCounter
    jmp ReadLine
.endproc

;; A "$" line: runs the Monitor command for the key found, then reads the next number and finds its key.
;;
;; It reads the line as the Monitor's command line does: a number, then a key it looks up in <Commands::Keys> and runs
;; through <Commands::RunCommand>. A Return ends the line as the Monitor's <Commands::ExamineNextOrBlank> handles it:
;; alone, it examines the bytes after the last ones shown. A key that is not a command sounds the bell.
;; In: Y = the key's place in <Commands::Keys>
;; Entry:
;;   ReadNumber = reads the first number, with Y at the place in <InputBuffer> after the "$": <ReadLine> enters here
;; Also: FAKEMON3 (A2RM78)
.proc RunMonitorCommand
    jsr Commands::RunCommand
    ldy CommandPosition

;; Reads a number and the key after it.
;; In: Y = the place in <InputBuffer>
;; Also: FAKEMON (A2RM78)
ReadNumber:
    jsr ReadHexNumber
    sty CommandPosition
    ldy #COMMAND_KEY_COUNT

;; Looks the key up in <Commands::Keys>, from the end.
;; Also: FAKEMON2 (A2RM78)
FindKey:
    dey
    bmi Restart
    cmp Commands::Keys,y
    bne FindKey
    cpy #RETURN_KEY_INDEX
    bne RunMonitorCommand

    ; The Return: the place before it, which ExamineNextOrBlank counts down once more to see whether it was alone.
    lda CommandMode
    ldy #0
    dec CommandPosition
    jsr Commands::ExamineNextOrBlank
    jmp ReadLine
.endproc

;; Finds the opcode whose mnemonic and format the line has, and assembles it.
;;
;; It tries the opcode in <Address1High>, then counts it down: <ParseOperand> leaves it 0, so the opcodes are tried
;; from $00, then $FF down to $01. When none matches, a one-byte operand is tried again as two bytes, as a number
;; below $100 can be either: "JMP 12" assembles as an absolute jump. Falls into <Error> when nothing matches.
;; In: Address4/Address4High = the packed mnemonic, TypedFormat = the operand's format, TypedLength = its length
;; Also: TRYNEXT (A2RM78)
.proc FindOpcode

;; The opcode being tried.
Opcode = Address1High

    lda Opcode
    jsr Disassembler::Decode::Opcode
    tax
    lda MnemonicsRight,x
    cmp Address4
    bne NextOpcode
    lda MnemonicsLeft,x
    cmp Address4High
    bne NextOpcode

    ; The format: a branch's operand is worked out, any other's must be the same.
    lda TypedFormat
    ldy Disassembler::FormatBits
    cpy #RELATIVE_FORMAT
    beq Branch

;; Also: NREL (A2RM78)
CompareFormat:
    cmp Disassembler::FormatBits
    beq StoreInstruction

;; The next opcode, then the two-byte format once.
;; Also: NEXTOP (A2RM78)
NextOpcode:
    dec Opcode
    bne FindOpcode
    inc TypedFormat
    dec TypedLength
    beq FindOpcode
    ; Falls into Error.
.endproc

;; Shows where the line went wrong: a caret under the character before the place in <CommandPosition>, then the bell,
;; and reads a new line.
;;
;; The line typed starts in the column after the "!", so the caret, after as many blanks as the place, falls under the
;; character before it.
;; Entry:
;;   AtY = at the place in Y: <ReadLine> and <ParseMnemonic> enter here
;; Also: ERR (A2RM78)
.proc Error
    ldy CommandPosition

;; Shows where the line went wrong, under the character before the place in Y.
;; In: Y = the place in <InputBuffer>
;; Also: ERR2 (A2RM78)
AtY:
    tya
    tax
    jsr PrintBlanks
    lda #'^'
    jsr CharacterOut
    ; Falls into Restart.
.endproc

;; Sounds the bell, then reads a new line.
;; Also: RESETZ (A2RM78)
.proc Restart
    jsr Beep
    ; Falls into ReadLine.
.endproc

;; Reads a line after the "!" prompt and assembles it: an address and a colon, a blank, or a "$" line.
;;
;; An address becomes <ProgramCounter>, through the Monitor's <SetPcFromA1::Loop>. A line that is none of the three,
;; a Return alone among them, is an error.
;; Entry:
;;   ToError = <Error::AtY> unless the zero flag is set: <ParseOperand> enters here
;; Also: NXTLINE (A2RM78)
.proc ReadLine
    lda #'!'
    sta PromptCharacter
    jsr GetLineAfterReturn
    jsr ClearMode

    ; The first character: a blank, a "$", or the address.
    lda InputBuffer
    cmp #' '
    beq ParseMnemonic
    iny
    cmp #'$'
    beq RunMonitorCommand::ReadNumber
    dey
    jsr ReadHexNumber
    cmp #COLON_CODE

;; An error unless the character after the address is the colon, and an address came before it.
;; Also: ERR4 (A2RM78)
ToError:
    bne Error::AtY
    txa
    beq Error::AtY
    jsr SetPcFromA1::Loop
    ; Falls into ParseMnemonic.
.endproc

;; Reads the mnemonic: its three letters, five bits each, packed into <Address4> and <Address4High> as the Monitor's
;; mnemonic tables hold them. Falls into <ParseOperand>.
;; In: Y = the place in <InputBuffer>
;; Also: SPACE (A2RM78)
.proc ParseMnemonic

;; The mnemonic's letters left to read.
LettersLeft = Address1High

    lda #MNEMONIC_LETTERS
    sta LettersLeft

;; Also: NXTMN (A2RM78)
NextLetter:
    jsr NextNonBlank

;; Turns the letter into its 5-bit code, in A's top bits.
;; Also: NXTM (A2RM78)
LetterCode:
    asl a
    sbc #LETTER_OFFSET
    cmp #FIRST_LETTER_CODE
    bcc Error::AtY
    asl a
    asl a
    ldx #LETTER_BITS - 1

;; Shifts the letter's bits into the packed mnemonic; after the last letter, one bit more.
;; Also: NXTM2 (A2RM78)
PackBits:
    asl a
    rol Address4
    rol Address4High
    dex
    bpl PackBits
    dec LettersLeft
    beq PackBits
    bpl NextLetter
    ; Falls into ParseOperand.
.endproc

;; Reads the operand into <TypedFormat>, then checks that the line ends, and finds the opcode (<FindOpcode>).
;;
;; For each of the six format positions, from "$" to ",Y", it looks for the position's characters
;; (<FormatCharacter1> and <FormatCharacter2>) and shifts a bit into the format: 1 when they are there. The number
;; comes at <NUMBER_POSITION>, read by <ReadHexNumber>; its length goes in <TypedLength>, and the format takes it in
;; its low two bits, with the "$" bit for a number that has no "$", "($" or "#$" before it. After the operand comes a
;; comment (";") or the end of the line.
;;
;; The "$" of "($" and "#$" may be left out: a position whose first character matches gives a 1 when its second is
;; "$" or it has none, whatever follows.
;; In: Y = the place in <InputBuffer>
;; Out: Address1High = 0, the first opcode <FindOpcode> tries, Address2/Address2High = the number,
;;   CommandPosition = the place of the end of the line
;; Also: FORM1 (A2RM78)
.proc ParseOperand
    ldx #FORMAT_POSITIONS - 1

;; Looks for the position's first character.
;; Also: FORM2 (A2RM78)
NextPosition:
    jsr NextNonBlank
    sty CommandPosition
    cmp FormatCharacter1,x
    bne NoMatch
    jsr NextNonBlank
    cmp FormatCharacter2,x
    beq ShiftBit
    lda FormatCharacter2,x
    beq BackUp
    cmp #'$'
    beq BackUp
    ldy CommandPosition

;; No match: a 0 bit, and the character read again.
;; Also: FORM3 (A2RM78)
NoMatch:
    clc

;; Backs up a character, so that the next position reads it.
;; Also: FORM4 (A2RM78)
BackUp:
    dey

;; Shifts the bit into the format; at the number's position, reads the number.
;; Also: FORM5 (A2RM78)
ShiftBit:
    rol TypedFormat
    cpx #NUMBER_POSITION
    bne NextFormatPosition
    jsr ReadHexNumber
    lda Address2High
    beq StoreLength
    inx

;; Stores the length: <ReadHexNumber> leaves X 1 after a digit and 0 for none, and a high byte makes it 2.
;; Also: FORM6 (A2RM78)
StoreLength:
    stx TypedLength
    ldx #NUMBER_POSITION
    dey

;; The next position. Storing X each time leaves <Address1High> 0 after the last.
;; Also: FORM7 (A2RM78)
NextFormatPosition:
    stx Address1High
    dex
    bpl NextPosition

    ; The format: the bits shifted to the top, the length below, and "$" for a bare number.
    lda TypedFormat
    asl a
    asl a
    ora TypedLength
    cmp #OPERAND_IMMEDIATE
    bcs StoreFormat
    ldx TypedLength
    beq StoreFormat
    ora #OPERAND_DOLLAR

;; Stores the format; a comment or the end of the line must follow.
;; Also: FORM8 (A2RM78)
StoreFormat:
    sta TypedFormat
    sty CommandPosition
    lda InputBuffer,y
    cmp #';'
    beq ToFind
    cmp #CARRIAGE_RETURN | $80
    bne ReadLine::ToError

;; Goes to <FindOpcode>.
;; Also: FORM9 (A2RM78)
ToFind:
    jmp FindOpcode
.endproc

;; Returns the next character of the line that is not a blank.
;; In: Y = the place in <InputBuffer>
;; Out: A = the character, Y = the place after it, zero = clear
;; Keeps: X
;; Also: GETNSP (A2RM78)
.proc NextNonBlank
    lda InputBuffer,y
    iny
    cmp #' '
    beq NextNonBlank
    rts
.endproc

.endscope

; Float: the conversion to an integer, which follows the Mini-Assembler's routines.
.scope Float continued

;; Shifts FP1 right one place, then converts it to an integer as <Float::ToInteger> does.
;;
;; At $F63D. <Float::ToInteger> comes back here for each place the number must move.
;; Errors: jumps to <Float::OverflowJump> as <Float::ToInteger> does
;; Also: FIX1 (A2RM78)
.proc ShiftTowardInteger
.assert * = $F63D, "Float::ShiftTowardInteger must stay at $F63D, where FIX1 is."
    jsr ShiftRight
    ; Falls into ToInteger.
.endproc

;; Converts FP1 to a 16-bit integer in <Float::Mantissa1> (high byte) and <Float::Mantissa1>+1.
;;
;; At $F640. It shifts the mantissa right (<Float::ShiftTowardInteger>) until the exponent is
;; <Float::INTEGER_EXPONENT>, 14. A negative number with a fraction left over is moved one toward 0, but only the
;; fraction's top 8 bits, in <Float::Mantissa1>+2, are looked at: the shifting moves the rest into
;; <Float::Extension>, so a negative number whose fraction is below 1/256 is rounded down instead. A number below 1 in
;; size gives 0 (<Float::ToInteger::Zero>).
;; In: Exponent1/Mantissa1 = the number
;; Out: Mantissa1, Mantissa1+1 = the integer
;; Keeps: Y
;; Errors: jumps to <Float::OverflowJump> when the number is 32768 or more in size, but for -32768
;; Entry:
;;   Zero = returns 0
;; See: <Float::FromInteger>
;; Also: FIX (A2RM78)
.proc ToInteger
.assert * = $F640, "Float::ToInteger must stay at $F640, where programs call FIX."
    lda Exponent1
    bpl Zero
    cmp #INTEGER_EXPONENT
    bne ShiftTowardInteger

    ; Toward 0: a negative number with a fraction is one more.
    bit Mantissa1
    bpl Done
    lda Mantissa1 + 2
    beq Done
    inc Mantissa1 + 1
    bne Done
    inc Mantissa1

;; Also: FIXRTS (A2RM78)
Done:
    rts

;; Returns 0: clears <Float::Mantissa1> and <Float::Mantissa1>+1.
;; Out: A = 0
;; Also: UNDFL (A2RM78)
Zero:
    lda #0
    sta Mantissa1
    sta Mantissa1 + 1
    rts
.endproc

.endscope

    ; Unused bytes, up to the Mini-Assembler's entry point.
    .res $F666 - *, $FF

; MiniAssembler: its entry point.
.scope MiniAssembler continued

;; The Mini-Assembler's entry point, F666G from the Monitor: sounds the bell and reads the first line.
;;
;; At $F666.
;; Also: MINIASM (UNKN)
.proc Run
.assert * = $F666, "MiniAssembler::Run must stay at $F666, where F666G starts it."
    jmp Restart
.endproc

.endscope
