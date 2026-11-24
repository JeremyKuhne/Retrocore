; retrocore: style=strict
;; The Enhanced IIe's 80-column screen access and the end of the ROM, $CDFE-$CFFF: the line base, uppercase, the
;; cursor, reading and writing the screen at a column through 80STORE, the escape cursor, Pascal's setup, the
;; Monitor copied into the language card, the mini-assembler's branches, opcode search, line and parse, and the
;; expansion ROM switch at $CFFF.

; The masks <InverseMask> holds for the 80-column firmware.

;; <InverseMask> for normal text: the 80-column firmware stores characters as they are.
MASK_NORMAL = $FF

;; <InverseMask> for inverse text: the 80-column firmware stores characters with bit 7 clear.
MASK_INVERSE = $7F

; Screen characters.

;; The mask that turns a lowercase letter into uppercase: it clears bit 5.
UPPERCASE_MASK = %11011111

;; The end of $00-$1F, the codes where the alternate character set shows inverse capitals.
INVERSE_CAPITALS_END = $20

;; What MouseText off moves an inverse capital by with the alternate character set: from $40-$5F, where that set
;; shows MouseText, to $00-$1F, where it shows inverse capitals; reading the screen moves it back.
MOUSETEXT_OFFSET = $40

; Memory.

;; The page the Monitor's ROM starts at, $F800.
MONITOR_ROM_PAGE = $F8

;; The byte the IIe's Monitor has at <ModelId>.
MODEL_ID_IIE = $06

; The mini-assembler's operand formats, as the Monitor's disassembler packs them.

;; Inherit: <Monitor:Disassembler::OPERAND_DOLLAR>
OPERAND_DOLLAR = $80

;; Inherit: <Monitor:Disassembler::OPERAND_IMMEDIATE>
OPERAND_IMMEDIATE = $20

;; Inherit: <Monitor:Disassembler::RELATIVE_FORMAT>
RELATIVE_FORMAT = $9D

;; Inherit: <Monitor:Disassembler::FORMAT_POSITIONS>
FORMAT_POSITIONS = 6

;; The format <LineAssembler::CheckFormat> gives an operand of one byte with no other characters than "$", or none:
;; a branch takes it, or the two-byte one after it.
ADDRESS_FORMAT = OPERAND_DOLLAR | 1

; The mini-assembler's mnemonics.

;; The letters of a mnemonic.
MNEMONIC_LETTERS = 3

;; The bits of a packed mnemonic letter.
LETTER_BITS = 5

;; What <LineAssembler::Parse> takes from a letter shifted left: it leaves the letter's code, counted from "?" as
;; the Monitor's mnemonics count it, in bits 1-5, below bits 6 and 7 set.
LETTER_OFFSET = $BE

;; What <LETTER_OFFSET> leaves for "@", the first character a mnemonic letter may be.
FIRST_LETTER_CODE = $C2

;; The code <ReadHexNumber> leaves in A for a ":" after the address, as the Monitor's commands read their keys: the
;; character, exclusive-or "0", plus $89.
COLON_CODE = ((':' ^ '0') + $89) & $FF

;; Computes the base of the cursor's line, the Monitor's <CV>, which it copies to <EightyColumns::CursorLine>.
;;
;; At $CDFE. It adds the window's left edge, halved in 80 columns, where each byte of a half holds two columns.
;; Apple calls it VTAB, and the entry VTABZ: names left out of Also: because they are the Monitor's
;; <VerticalTab> and <SetLineBase>.
;; In: CV = the line
;; Out: TextBase/TextBaseHigh = the line's base, A = its low byte
;; Keeps: X, Y
;; Entry:
;;   Row = computes the base of line A
;; Also: C8_BASCALC (UNKN), VTAB80 (UNKN)
.proc LineBase
.assert * = $CDFE, "LineBase must stay at $CDFE."
    lda CV
    sta EightyColumns::CursorLine

;; Computes the base of line A, with the window's left edge.
;; In: A = the line
;; Also: BASCALC2 (IIEROM82)
Row:
    jsr RowBase
    lda WindowLeft
    bit Columns80State
    bpl AddLeft
    lsr a

;; Also: BASCLC3 (IIEROM82), VTAB40 (IIETRM85)
AddLeft:
    clc
    adc TextBase
    sta TextBase
    rts                             ; VTABX in Apple's listing
.endproc

;; Turns a lowercase letter into uppercase, and leaves every other character as it is.
;;
;; At $CE14.
;; In: A = the character
;; Out: A = the character, uppercase
;; Keeps: X, Y
;; Also: B_FIXCHR (IIEROM82), UPSHIFT (UNKN), UPSHFT (IIETRM85)
.proc Upshift
.assert * = $CE14, "Upshift must stay at $CE14."
    cmp #'a'
    bcc Done
    cmp #'z' + 1
    bcs Done
    and #UPPERCASE_MASK

;; Also: UPSHFT2 (IIETRM85)
Done:
    rts
.endproc

;; The 80-column firmware's access to the text screen: reading and writing the character at a column of the line at
;; <TextBase>, and the cursor drawn by flipping the character under it.
;;
;; In 80 columns an even column is in auxiliary memory, which <Page2On> switches in while 80STORE is on, and an odd
;; one in main memory. <Screen::ReadCharacter> and <Screen::StoreCharacter> are the entries the rest of the firmware
;; uses, and <Screen::OverflowByte> is the $60 that `bit` reads to set overflow. On the original IIe one routine
;; reads or writes, by the overflow flag; on the Enhanced IIe, with MouseText off, the writes put inverse capitals
;; where the alternate character set shows them, and the reads undo it.
.scope Screen

;; Flips the character at the cursor, as <InvertCursor> does, unless <MODE_CURSOR_OFF> hides the cursor. Falls into
;; <InvertCursor>.
;; Out: A = 0 when it flips the character, <MODE_CURSOR_OFF> when it does not
;; Keeps: Y
;; Also: FLIPCURSOR (UNKN), PASINV (IIETRM85)
.proc FlipCursor
    lda EightyColumns::Mode
    and #MODE_CURSOR_OFF
    bne InvertCursor::Done
    ; Falls into InvertCursor.
.endproc

;; Flips bit 7 of the character at the cursor, which shows or hides the cursor, whatever <MODE_CURSOR_OFF> says.
;; Keeps: A, Y
;; Entry:
;;   Done = the return <FlipCursor> branches to when the cursor is hidden
;; Also: INVERT (IIEROM82, IIETRM85)
.proc InvertCursor
    pha
    tya
    pha
    ldy EightyColumns::CursorColumn
    jsr ReadCharacter
    eor #NORMAL_BIT
    jsr WriteCharacter
    pla
    tay
    pla

;; The return <FlipCursor> branches to when the cursor is hidden.
;; Also: INVX (IIETRM85)
Done:
    rts
.endproc

;; Stores a character at window column Y of the cursor's line, with bit 7 cleared when <InverseMask> says inverse.
;; Falls into <OverflowByte>.
;; In: A = the character, Y = the column
;; Keeps: A, X, Y
;; Also: STORCHAR (IIEROM82, IIETRM85), PUTINV (UNKN)
.proc StoreCharacter
    pha
    bit InverseMask
    bmi Store
    and #NORMAL_BIT ^ $FF

;; Also: STOR2 (IIEROM82, IIETRM85)
Store:
    jsr WriteCharacter
    pla
    ; Falls into OverflowByte.
.endproc

;; <StoreCharacter>'s RTS, $60, which `bit OverflowByte` reads to set overflow.
;; Also: SEV (IIEROM82, IIETRM85)
OverflowByte:
    rts

;; Reads the character at window column Y of the line at <TextBase>.
;;
;; In 80 columns an even column on the screen is in auxiliary memory, which <Page2On> switches in with 80STORE on,
;; and an odd one in main memory. With the alternate character set, a code below $20, an inverse capital, comes back
;; as $40-$5F, as <WriteCharacter> was given it.
;; In: Y = the column
;; Out: A = the character
;; Keeps: X, Y
;; Also: PICK (IIEROM82, IIETRM85), GETSCRCHAR (UNKN)
.proc ReadCharacter
    lda (TextBase),y
    bit Columns80State
    bpl MouseText

    ; 80 columns: the byte at Y/2 of its half, with the window's left edge, as <Fill80> works it out.
    sta Store80On
    sty ScrollBase
    tya
    eor WindowLeft
    ror a
    bcs Read80
    lda Page2On
    iny

;; Reads the byte in the half switched in, then main memory back.
;; Also: PICK2 (IIETRM85)
Read80:
    tya
    lsr a
    tay
    lda (TextBase),y
    bit Page2Off
    ldy ScrollBase

;; With the alternate character set, an inverse capital back to $40-$5F.
;; Also: PICK3 (IIETRM85)
MouseText:
    bit AlternateCharactersState
    bpl Done
    cmp #INVERSE_CAPITALS_END
    bcs Done
    ora #MOUSETEXT_OFFSET

;; Also: PICK4 (IIETRM85)
Done:
    rts
.endproc

;; Writes a character at window column Y of the line at <TextBase>, as <ReadCharacter> reads it.
;;
;; With <MODE_MOUSETEXT_OFF> and the alternate character set, an inverse capital given as $40-$5F is written as
;; $00-$1F, where that set shows inverse capitals instead of MouseText.
;; In: A = the character, Y = the column
;; Keeps: A, X, Y
;; Also: PUTSCRCHAR (UNKN), STORIT (IIETRM85)
.proc WriteCharacter
    pha

    ; Normal characters as they are.
    and #$FF
    bmi Write

    ; MouseText off, and the alternate set: $40-$5F to $00-$1F. The bit through <RangeMask> tells $40-$5F, once
    ; moved, by bits 5 and 6 clear.
    lda EightyColumns::Mode
    ror a
    pla
    pha
    bcc Write
    bit AlternateCharactersState
    bpl Write
    eor #MOUSETEXT_OFFSET
    bit RangeMask
    beq Write
    eor #MOUSETEXT_OFFSET

;; Writes by the columns.
;; Also: STORE1 (IIETRM85)
Write:
    bit Columns80State
    bpl Write40

    ; 80 columns: the byte at Y/2 of its half, as <ReadCharacter> works it out.
    sta Store80On
    pha
    sty ScrollBase
    tya
    eor WindowLeft
    lsr a
    bcs Write80
    lda Page2On
    iny

;; Writes the byte in the half switched in, then main memory back, and takes A back.
;; Also: STORE2 (IIETRM85)
Write80:
    tya
    lsr a
    tay
    pla                             ; STORIT2 in Apple's listing
    sta (TextBase),y
    lda Page2Off
    ldy ScrollBase
    pla

;; The routine's RTS, $60, which `bit RangeMask` reads to test bits 5 and 6.
;; Also: HEX60 (IIETRM85)
RangeMask:
    rts

;; 40 columns: byte Y.
;; Also: STOR40 (IIEROM82, IIETRM85)
Write40:
    sta (TextBase),y
    pla
    rts
.endproc

;; Saves the character at the cursor in <EightyColumns::CurrentCharacter> and shows a "+" there in the opposite
;; video: the escape mode's cursor.
;; Keeps: A, X, Y
;; Also: ESCON (IIEROM82, IIETRM85), ESCCURSOR (UNKN)
.proc ShowEscapeCursor
    pha
    tya
    pha
    ldy EightyColumns::CursorColumn
    jsr ReadCharacter
    sta EightyColumns::CurrentCharacter

    ; The character's bit 7 flips the "+"'s.
    and #NORMAL_BIT
    eor #'+'
    jmp RestoreCharacter::Store
.endproc

;; Puts the character saved in <EightyColumns::CurrentCharacter> back at the cursor.
;; Keeps: A, X, Y
;; Entry:
;;   Store = writes A at column Y, with Y and A pushed: <ShowEscapeCursor> enters here
;; Also: ESCOFF (IIEROM82, IIETRM85), RESTCHAR (UNKN)
.proc RestoreCharacter
    pha
    tya
    pha
    ldy EightyColumns::CursorColumn
    lda EightyColumns::CurrentCharacter

;; Writes A at column Y, then takes Y and A back from the stack, where the caller pushed A, then Y.
;; In: A = the character, Y = the column
;; Also: ESCRET (IIEROM82, IIETRM85)
Store:
    jsr WriteCharacter
    pla
    tay
    pla
    rts
.endproc

.endscope

; Pascal: the setup before each call.
.scope Pascal continued

;; Sets up a Pascal call: the full 80-column window, <InverseMask> from <MODE_INVERSE>, and <TextBase> and <CV> from
;; <EightyColumns::SavedTextBase> and <EightyColumns::CursorLine>.
;; Keeps: X, Y
;; Also: PSETUP (IIEROM82, IIETRM85), PASRESTORE (UNKN)
.proc Setup
    jsr FullWindow80

    ; Normal video, or inverse with MODE_INVERSE: MASK_NORMAL shifted right is MASK_INVERSE.
    lda #MASK_NORMAL
    sta InverseMask
    lda EightyColumns::Mode
    and #MODE_INVERSE
    beq RestoreBase
    lsr InverseMask

;; Also: PSETUPRET (IIEROM82, IIETRM85)
RestoreBase:
    lda EightyColumns::SavedTextBase
    sta TextBase
    lda EightyColumns::SavedTextBaseHigh
    sta TextBaseHigh
    lda EightyColumns::CursorLine
    sta CV
    rts
.endproc

.endscope

;; Copies the Monitor, $F800-$FFFF, from ROM into the language card's RAM when RAM is being read and its
;; <ModelId> is not the IIe's, then puts back the bank and whether RAM can be written.
;;
;; At $CEF4. It copies through <OutputHook>, which it leaves at $0000 for its caller to set.
;; Also: COPYROM (IIEROM82, IIETRM85), LCMONCOPY (UNKN)
.proc CopyMonitorToRam
.assert * = $CEF4, "CopyMonitorToRam must stay at $CEF4."
    bit LanguageCardRamState
    bpl Done
    lda #MODEL_ID_IIE
    cmp ModelId
    beq Done

    ; The switch that puts the bank back, reading and writing RAM.
    ldx #<(LanguageCardBank2ReadWrite - LanguageCardBank2ReadOnly)
    bit LanguageCardBank2State
    bmi CheckWrite
    ldx #<(LanguageCardBank1ReadWrite - LanguageCardBank2ReadOnly)

;; Whether RAM can be written: if the model byte does not stick, the switch one on, which reads RAM without
;; writing it.
;; Also: BANK2 (IIETRM85)
CheckWrite:
    sta ModelId
    bit LanguageCardBank2ReadOnly
    lda ModelId
    cmp #MODEL_ID_IIE
    beq Copy
    inx

;; ROM read, RAM written (two reads), and the pointer from $F800.
;; Also: WRTENBL (IIETRM85)
Copy:
    bit LanguageCardRomWriteBank2
    bit LanguageCardRomWriteBank2
    ldy #0
    lda #MONITOR_ROM_PAGE
    sta OutputHookHigh
    sty OutputHook

;; Also: COPYROM2 (IIEROM82, IIETRM85)
CopyByte:
    lda (OutputHook),y
    sta (OutputHook),y
    iny
    bne CopyByte
    inc OutputHookHigh
    bne CopyByte

    ; The bank back (two reads, for writing).
    lda LanguageCardBank2ReadOnly,x
    lda LanguageCardBank2ReadOnly,x

;; Also: COPYRET (IIEROM82), ROMOK (IIETRM85)
Done:
    rts
.endproc

    ; Three bytes nothing uses.
    .byte 0, 0, 0

; LineAssembler: the branches, the opcode search and the errors.
.scope LineAssembler continued

;; Inherit: <Monitor:Disassembler::Decode::Opcode>
DecodeOpcode = $F88E

;; Inherit: <Monitor:MiniAssembler::ShowError>
ShowError = $FCD2

;; Inherit: <Monitor:MiniAssembler::ShowInstruction>
;; Also: GETINST1 (IIETRM85)
ShowInstruction = $FCE3

;; Assembles a relative branch: the offset from the instruction after it to the target in <Address2>, or
;; <Error> when the target is out of reach. Falls into <StoreInstruction>.
;; In: A = the operand's format, carry = set, Address2/Address2High = the target
;; Out: Address2 = the offset
;; Also: MINIREL (UNKN), REL (IIETRM85)
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

;; Also: REL1 (IIETRM85)
Offset:
    dex
    txa
    clc
    sbc ProgramCounter
    sta Address2
    bpl Page
    iny

;; The high byte must say the offset fits in a signed byte.
;; Also: REL2 (IIETRM85)
Page:
    tya
    sbc ProgramCounterHigh

;; Also: GOERR (IIETRM85)
ToError:
    bne Error
    ; Falls into StoreInstruction.
.endproc

;; Stores the assembled instruction at <ProgramCounter>, moves up the two lines the input left, and has the
;; Monitor's <ShowInstruction> show it and read the next line.
;; In: OperandLength = the operand's bytes, Address1High = the opcode, Address2/Address2High = the operand
;; Also: MOVINST (IIETRM85)
.proc StoreInstruction

;; The instruction as assembled: the opcode, then the operand in <Address2> and <Address2High>.
Instruction = Address1High

    ldy OperandLength

;; Also: MOV1 (IIETRM85)
NextByte:
    lda a:Instruction,y
    sta (ProgramCounter),y
    dey
    bpl NextByte
    jsr PrintThreeBlanks
    jsr CursorUp
    jsr CursorUp
    jmp ShowInstruction
.endproc

;; Finds the opcode whose mnemonic and format the parsed line has, trying $00 and then $FF down to $01, and
;; assembles it.
;;
;; When no opcode matches and the operand had one byte, it tries once more with the two-byte format, so that
;; "JMP $12" assembles as an absolute jump. Falls into <Error> when nothing matches.
;; In: Address1High = 0, as <ParseOperand> leaves it, Address4/Address4High = the packed mnemonic, Address5 = the
;;   operand's format, SavedOutputY = the operand's bytes
;; Also: MINIFIND (UNKN), GETOP (IIETRM85)
.proc FindOpcode

;; The opcode being tried.
Opcode = Address1High

;; The format the parsed operand has.
Format = Address5

    lda Opcode
    jsr DecodeOpcode
    tax
    lda MnemonicsRight,x
    cmp Address4
    bne NextOpcode
    lda MnemonicsLeft,x
    cmp Address4High
    bne NextOpcode

    ; The format: a branch's operand is worked out, any other's must be the same.
    lda Format
    ldy PlotMask
    cpy #RELATIVE_FORMAT
    beq Branch
    cmp PlotMask
    beq StoreInstruction

;; The next opcode, then the two-byte format once.
;; Also: NXTOP (IIETRM85)
NextOpcode:
    dec Opcode
    bne FindOpcode
    inc Format
    dec SavedOutputY
    beq FindOpcode
    ; Falls into Error.
.endproc

;; Shows where the line went wrong, at the position in <CommandPosition>, with the Monitor's <ShowError>.
;; Entry:
;;   AtY = at column Y: <Parse> and <CheckFormat> enter here
;; Also: MINIERR (IIETRM85)
.proc Error
    ldy CommandPosition

;; Shows where the line went wrong, at column Y.
;; In: Y = the column
;; Also: ERR2 (IIETRM85)
AtY:
    tya
    tax
    jmp ShowError
.endproc

.endscope

;; Assembles a line of the mini-assembler, which <Monitor:MiniAssembler::ReadLine> has read.
;;
;; At $CF9C. A blank at the start means an instruction, a Return alone returns, and anything else
;; starts with an address, then an instruction.
;; In: InputBuffer = the line
;; Also: MINILINE (UNKN), DOINST (IIETRM85)
.proc AssembleLine
.assert * = $CF9C, "AssembleLine must stay at $CF9C."
    jsr ClearMode
    lda InputBuffer
    cmp #' '
    beq LineAssembler::Parse::Mnemonic
    cmp #KEY_RETURN
    bne LineAssembler::Parse
    rts
.endproc

; LineAssembler: parsing a line.
.scope LineAssembler continued

;; Parses an address, which must end in ":" and becomes <ProgramCounter>, then the instruction: the mnemonic's
;; letters packed into <Address4>/<Address4High>, and the operand with <ParseOperand>. Falls into <CheckFormat>.
;; In: Y = the position in <InputBuffer>
;; Entry:
;;   ToError = <Error::AtY> when the zero flag is clear: <CheckFormat> enters here
;;   Mnemonic = parses the instruction without the address: <AssembleLine> enters here
;; Also: MINIPARSE (UNKN), GETI1 (IIETRM85)
.proc Parse

;; The mnemonic's letters left to parse.
LettersLeft = Address1High

    jsr ReadHexNumber
    cmp #COLON_CODE

;; Shows the error at column Y unless the zero flag is set.
;; Also: GOERR2 (IIETRM85)
ToError:
    bne Error::AtY
    txa
    beq Error::AtY
    jsr SetPcFromA1::Loop

;; Parses the instruction: its mnemonic's letters, then its operand.
;; Also: DOLIN (IIETRM85)
Mnemonic:
    lda #MNEMONIC_LETTERS
    sta LettersLeft

;; Also: NXTCH (IIETRM85)
NextLetter:
    jsr SkipBlanks
    asl a
    sbc #LETTER_OFFSET
    cmp #FIRST_LETTER_CODE
    bcc Error::AtY
    asl a
    asl a
    ldx #LETTER_BITS - 1

;; Shifts the letter's bits into the packed mnemonic; after the last letter, one bit more.
;; Also: NXTMN (IIETRM85)
PackBits:
    asl a
    rol Address4
    rol Address4High
    dex
    bpl PackBits
    dec LettersLeft
    beq PackBits
    bpl NextLetter

    ; The operand.
    ldx #FORMAT_POSITIONS - 1
    jsr ParseOperand
    ; Falls into CheckFormat.
.endproc

;; Packs the operand's format: the characters <ParseOperand> matched, and its bytes, with "$" taken for a bare number.
;; The line must then end, in ";" or a Return; then <FindOpcode>.
;; In: Address5 = the characters matched, SavedOutputY = the operand's bytes, Y = the position in <InputBuffer>
;; Also: MINIFMT (UNKN), AMOD7 (IIETRM85)
.proc CheckFormat
    lda Address5
    asl a
    asl a
    ora SavedOutputY
    cmp #OPERAND_IMMEDIATE
    bcs StoreFormat
    ldx SavedOutputY
    beq StoreFormat
    ora #OPERAND_DOLLAR

;; Also: AMOD8 (IIETRM85)
StoreFormat:
    sta Address5
    sty CommandPosition
    lda InputBuffer,y
    cmp #';'
    beq ToFind
    cmp #KEY_RETURN
    bne Parse::ToError

;; Goes to <FindOpcode>.
ToFind:
    jmp FindOpcode
.endproc

.endscope

;; The internal ROM's last byte: reading $CFFF releases every slot's $C800 expansion ROM.
;;
;; At $CFFF. <ClaimExpansionRom> reads it.
;; Also: CLRROM (A2RM79, IIEROM82, IIETRM85)
ExpansionRomOff:
.assert * = $CFFF, "ExpansionRomOff must stay at $CFFF."
    .byte $DF
