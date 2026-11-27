; retrocore: style=strict
;; The Enhanced IIe's internal firmware from $C3FA to $C5FF: the interrupt and BRK handler, which saves the memory
;; state and switches to main memory and ROM, the code that puts the state back after the user's handler, the line
;; assembler's operand parser, AppleSoft's `SHLOAD`, `STORE` and `RECALL` helper, and the cassette routines that the
;; Monitor's header, W and R call.

; The Monitor's and AppleSoft's entries this code jumps to, not in MonitorEntries.asm.

;; Inherit: <Monitor:BreakFromFirmware>
BreakFromFirmware = $FA47

;; Inherit: <Monitor:CallUserIrq>
CallUserIrq = $FC74

;; AppleSoft's routine that points <DestinationEnd> at an array's data, past its header: two bytes for each dimension, A
;; of them, and five more.
;; In: A = the array's dimensions, SourceStart = the array
;; See: <AppleSoft:Variables::ElementsStart::FromCount>
FMAPT1 = $E0EF

; The stack.

;; The 6502's stack page.
Stack = $0100

;; While a program runs with the auxiliary zero page and stack, the auxiliary stack page's first byte holds main's
;; stack pointer: the IIe's convention, which <HandleInterrupt> follows.
;; See: <AuxStackPointer>
MainStackPointer = $0100

;; Where <HandleInterrupt> keeps the auxiliary stack pointer, in the auxiliary stack page, while it runs on main's.
;; See: <MainStackPointer>
AuxStackPointer = $0101

; The status register and the soft switches.

;; The status register's break bit, as an interrupt pushes it: set for a BRK, clear for an IRQ.
BREAK_FLAG = $10

;; Bit 7 of a soft switch's state read: set while the switch is on.
SWITCH_ON = $80

; The memory state <HandleInterrupt> builds and <RestoreInterruptedState> puts back, a bit for each switch it changed.

;; The internal $C100-$CFFF ROM was in (INTCXROM on).
STATE_INTERNAL_CX_ROM = $01

;; Language card RAM bank 2 was read: bits 3 and 1, which touch <LanguageCardBank1ReadWrite>, then
;; <LanguageCardBank2ReadWrite>.
STATE_LANGUAGE_CARD_BANK2 = $0A

;; Language card RAM bank 1 was read: bits 3 and 2, which touch <LanguageCardBank1ReadWrite> twice.
STATE_LANGUAGE_CARD_BANK1 = $0C

;; Writes went to auxiliary memory (RAMWRT on).
STATE_AUX_WRITE = $10

;; Reads came from auxiliary memory (RAMRD on).
STATE_AUX_READ = $20

;; 80STORE and PAGE2 were both on, so the auxiliary text page was mapped in.
STATE_PAGE2 = $40

;; The auxiliary zero page and stack were in (ALTZP on).
STATE_AUX_ZERO_PAGE = $80

;; The state bits that each name a switch in <InterruptSwitches>: 6 down to 1.
STATE_SWITCH_BITS = 6

; The code <RestoreInterruptedState> builds below the stack: sta to a $CX ROM switch, then rti.

;; The opcode of rti.
OPCODE_RTI = $40

;; The opcode of sta with an absolute address.
OPCODE_STA_ABSOLUTE = $8D

;; The code's length.
RETURN_CODE_SIZE = 4

;; From the stack pointer, once Y is pulled, to the reserved bytes that become the return address into the code: past
;; the saved X and A.
RETURN_ADDRESS_OFFSET = 3

; The line assembler.

;; The format position at which <LineAssembler::ParseOperand> reads the operand's number: the characters of positions
;; 5 down to this one come before it, those of 2 down to 0 after it.
OPERAND_NUMBER_POSITION = 3

; AppleSoft's arrays and shape tables on cassette.

;; The offset in an AppleSoft array's header of its number of dimensions.
ARRAY_DIMENSIONS = 4

;; How long `SHLOAD` lets the header play, as a header length, once it hears the tape.
SHAPE_HEADER_DELAY = 3

; Cassette timing: delay counts, each a loop of 5 cycles, as the Monitor's own cassette code has them.

;; <WriteCassetteHeader>'s count for a half cycle of the header tone. The carry is set while it is written, which adds
;; <ONE_DELAY>, so the tone is lower than a 1 bit's.
HEADER_DELAY = $4B

;; The count for the first half cycle of the sync bit, shorter than a 0 bit's.
SYNC_DELAY = $21

;; The count a 1 bit's half cycle adds to a 0 bit's.
ONE_DELAY = $32

;; The count <WriteCassetteHeader>'s half cycle leaves in Y for the next one; callers adjust it for the time their own
;; code takes.
NEXT_HALF_CYCLE_DELAY = $2C

;; The count <ReadCassetteByte> starts each of its bits after the first at.
READ_BIT_START = $3A

;; The count at which <ReadCassetteBit::Transition> tells a 1 from a 0: a bit long enough to count Y down past 0
;; leaves it at this or above.
READ_ONE_THRESHOLD = $80

;; How many bits <ReadCassetteByte> reads.
BITS_PER_BYTE = 8

;; The header tone's length <ReadCassetteData> lets play once it hears the tape: about 3.5 seconds.
READ_HEADER_DELAY = $16

;; The count before the first data byte <WriteCassetteData> writes.
WRITE_FIRST_COUNT = $27

;; The count before each later data byte.
WRITE_NEXT_COUNT = $1D

;; The count before the checksum byte.
WRITE_CHECKSUM_COUNT = $22

;; The half cycles <WriteCassetteData> writes for a byte: two for each bit, each counting X down once.
HALF_CYCLES_PER_BYTE = 16

;; The count that tells the sync bit from the header: a half cycle that ends before the bit reader counts Y down past
;; 0 from here is the sync bit's, and the header's are longer.
READ_SYNC_COUNT = $24

;; The count before the first data byte <ReadCassetteData> reads.
READ_FIRST_COUNT = $3B

;; The count before each later byte.
READ_NEXT_COUNT = $35

;; The IRQ and BRK handler: switches to the internal ROM, main memory and the language card's ROM, keeping what it
;; changed in a state byte, then hands a BRK to the Monitor and an IRQ to the user's handler.
;;
;; At $C3FA, where the 6502's IRQ vector at $FFFE points (<Monitor:IrqVector>); the Monitor's <Monitor:Interrupt> at
;; $FA40 jumps here too, from $FA44, for code that calls it by address. A card in slot 3 whose ROM is in must have
;; the first two instructions here, as at <InterruptReturn>; the code goes on at $C400 in the internal ROM.
;;
;; It pushes A three times, so the stack keeps it in place of $45, where <RestoreInterruptedState> later puts its return
;; address in the other two, and saves X and Y. The state byte has <STATE_INTERNAL_CX_ROM>, <STATE_PAGE2> (and selects
;; page 1), <STATE_AUX_READ> and <STATE_AUX_WRITE> (and selects main memory), <STATE_LANGUAGE_CARD_BANK1> or
;; <STATE_LANGUAGE_CARD_BANK2> (and selects the ROM), and <STATE_AUX_ZERO_PAGE>: then it keeps the auxiliary stack
;; pointer in <AuxStackPointer>, takes main's from <MainStackPointer> and selects the main zero page and stack.
;;
;; A BRK leaves the state byte in <Address5>, pulls the registers back and goes on at the Monitor's
;; <BreakFromFirmware>. With the auxiliary zero page on, the registers and the BRK's frame are on the auxiliary
;; stack, but this path pulls them from main's. An IRQ pushes the state byte and <ExpansionRomSlot>, and a frame that
;; returns to <InterruptReturn>, and goes to the user's handler through the Monitor's <CallUserIrq>.
;; In: A = the interrupted program's A, the stack as the interrupt left it
;; Also: IRQ (IIETRM85), IRQHANDLER (UNKN)
.proc HandleInterrupt
.assert * = $C3FA, "HandleInterrupt must stay at $C3FA, where the IRQ vector points."
    bit InternalCxRomState
    sta InternalCxRomOn

;; The code goes on here in the internal ROM. The carry keeps whether it was in already.
;; Also: NEWIRQ (IIETRM85)
InternalRom:
.assert * = $C400, "HandleInterrupt must go on at $C400, the internal ROM's first byte after slot 3's page."
    cld
    sec
    bmi SaveXY
    clc

;; Pushes A three times and saves X and Y, then takes the break bit from the pushed status into Y.
;; Also: IRQINTCX (IIETRM85)
SaveXY:
    pha
    pha
    pha
    txa
    tsx
    inx
    inx
    inx
    inx
    pha
    tya
    pha
    lda Stack,x
    and #BREAK_FLAG
    tay

    ; 80STORE with PAGE2: page 1, and the bit before it is shifted into place.
    lda Store80State
    and Page2State
    and #SWITCH_ON
    beq AuxRead
    lda #STATE_PAGE2 >> 1
    sta Page2Off

;; Shifts in the carry, the internal ROM's bit; then RAMRD: main memory read.
;; Also: IRQ2 (IIETRM85)
AuxRead:
    rol a
    bit AuxReadState
    bpl AuxWrite
    sta AuxReadOff
    ora #STATE_AUX_READ

;; RAMWRT: main memory written.
;; Also: IRQ3 (IIETRM85)
AuxWrite:
    bit AuxWriteState
    bpl LanguageCard
    sta AuxWriteOff
    ora #STATE_AUX_WRITE

;; The language card's RAM read, and which bank.
;; Also: IRQ4 (IIETRM85), IRQ5 (IIETRM85)
LanguageCard:
    bit LanguageCardRamState
    bpl AuxZeroPage
    ora #STATE_LANGUAGE_CARD_BANK1
    bit LanguageCardBank2State
    bpl SelectRom
    eor #STATE_LANGUAGE_CARD_BANK1 ^ STATE_LANGUAGE_CARD_BANK2

;; Selects the ROM for reading. A store leaves the RAM's write enabling as it was (Apple's listing).
;; Also: IRQ6 (IIETRM85)
SelectRom:
    sta LanguageCardRomWriteBank2

;; ALTZP: the main zero page and stack, keeping the auxiliary stack pointer.
;; Also: IRQ7 (IIETRM85)
AuxZeroPage:
    bit AuxZeroPageState
    bpl BreakOrIrq
    tsx
    stx AuxStackPointer
    ldx MainStackPointer
    txs
    sta AuxZeroPageOff
    ora #STATE_AUX_ZERO_PAGE

;; A BRK: the state in <Address5>, the registers back, and the Monitor's break handling.
;; Also: IRQ8 (IIETRM85)
BreakOrIrq:
    dey
    bmi CallUser
    sta Address5
    pla
    tay
    pla
    tax
    pla
    pla
    pla
    jmp BreakFromFirmware

;; An IRQ: the state and the slot whose $C800 ROM was in, then a frame for the user's rti, which returns to
;; <InterruptReturn>.
;; Also: IRQCALL (UNKN), IRQ9 (IIETRM85)
CallUser:
    pha
    lda ExpansionRomSlot
    pha
    lda #>InterruptReturn
    pha
    lda #<InterruptReturn
    pha
    php
    jmp CallUserIrq
.endproc

;; Puts back the memory state <HandleInterrupt> saved, after the user's interrupt handler, and returns from the
;; interrupt.
;;
;; At $C47C, where the Monitor's <SelectInterruptRom> goes on once it has selected the interrupted slot's $C800 ROM
;; again. It reads <LanguageCardRomWriteBank2> to select the ROM (Apple's listing: it must be a read, so that the
;; RAM's write enabling stays as it was), then pulls the state byte. For <STATE_AUX_ZERO_PAGE> it selects the
;; auxiliary zero page and stack and takes the stack pointer from <AuxStackPointer>; for each other set bit from 6 to
;; 1 it touches the switch <InterruptSwitches> names with an inc, which reads it twice, as the language card's write
;; enabling needs, and then writes it, so that it works for the switches set by a write too. Last, it builds a sta to
;; <InternalCxRomOff> or <InternalCxRomOn>, then an rti, just below the stack, makes the reserved bytes a return
;; address into it, pulls X and A and returns there.
;; Also: IRQRESTORE (UNKN), IRQFIX (IIETRM85)
.proc RestoreInterruptedState
.assert * = $C47C, "RestoreInterruptedState must stay at $C47C."
    lda LanguageCardRomWriteBank2
    pla
    bpl Switches

    ; The auxiliary zero page and its stack.
    sta AuxZeroPageOn
    ldx AuxStackPointer
    txs

;; The switches, from bit 6 down.
;; Also: IRQDN1 (IIETRM85)
Switches:
    ldy #STATE_SWITCH_BITS

;; Touches the switch for a set bit, which is in the negative flag.
;; Also: IRQDN2 (IIETRM85)
NextBit:
    bpl CountBit
    ldx InterruptSwitches,y
    inc Keyboard,x

;; The next bit, until all six are done or none is left.
;; Also: IRQDN3 (IIETRM85)
CountBit:
    dey
    bmi BuildReturn
    asl a
    bne NextBit

;; Takes the internal ROM's bit into the carry, pulls Y and builds the code below the stack: sta $C006 or, with the
;; carry, $C007, then rti.
;; Also: IRQDN4 (IIETRM85)
BuildReturn:
    asl a
    asl a
    pla
    tay
    tsx
    lda #OPCODE_RTI
    pha
    lda #>InternalCxRomOff
    pha
    lda #<InternalCxRomOff
    adc #0
    pha
    lda #OPCODE_STA_ABSOLUTE
    pha
    txs

    ; The reserved bytes past X and A: the code's address less one.
    txa
    adc #RETURN_ADDRESS_OFFSET
    tax
    sec
    sbc #RETURN_ADDRESS_OFFSET + RETURN_CODE_SIZE
    sta Stack,x
    inx
    lda #>Stack
    sta Stack,x

    ; X and A back; the return runs the code, whose rti returns from the interrupt.
    pla
    tax
    pla
    rts
.endproc

;; The soft switches, as offsets from $C000, that <RestoreInterruptedState> touches for state bits 1 to 6, in that
;; order: bit 1 <LanguageCardBank2ReadWrite>, bits 2 and 3 <LanguageCardBank1ReadWrite>, bit 4 <AuxWriteOn>, bit 5
;; <AuxReadOn> and bit 6 <Page2On>. The last byte is not used.
;; Also: IRQSWITCHES (UNKN), IRQTBLE (IIETRM85)
InterruptSwitches:
    .byte <LanguageCardBank2ReadWrite, <LanguageCardBank1ReadWrite, <LanguageCardBank1ReadWrite, <AuxWriteOn
    .byte <AuxReadOn, <Page2On, $00
.assert * - InterruptSwitches = STATE_SWITCH_BITS + 1, "A switch for each state bit, then the unused byte."

;; The internals of the Enhanced IIe's mini-assembler, which <AssembleLine> runs for each line the Monitor reads at its
;; "!" prompt: the line's address and mnemonic, its operand, the search for the opcode, the branch offsets, and
;; storing the instruction.
;;
;; Its first piece, <LineAssembler::ParseOperand>, is at $C4C8, among the interrupt code; the rest is at $CF3A-$CFFE.
;; Not the Monitor's <Monitor:MiniAssembler>, which holds the entries this code jumps back to.
.scope LineAssembler

;; The operand's format as the line assembler builds it: <ParseOperand>'s match bits, one for each format position,
;; which <CheckFormat> combines with <OperandBytes>. <Address5>'s byte.
Format = Address5

;; The operand's length in bytes, 0 to 2, as <ParseOperand> reads it. <SavedOutputY>'s byte.
OperandBytes = SavedOutputY

;; Parses an instruction's operand: for each format position from X down to 0, shifts into <Format> whether the
;; input has that position's characters, and reads the operand's number in between.
;;
;; A position matches when the input's next characters, blanks skipped, are its <FormatCharacter1> and
;; <FormatCharacter2>; a position whose second character is "$" or none matches the first alone. At
;; <OPERAND_NUMBER_POSITION> it reads the number with the Monitor's <ReadHexNumber> into A2 and sets <OperandBytes>: 0
;; for none, 1, or 2 when A2's high byte is not 0. <Parse> calls it with X = 5.
;; In: X = the format position to start at, Y = the index in <InputBuffer>
;; Out: Format = the match bits, OperandBytes = the operand's length, Address2/Address2High = the number, Y = the index
;;     after the operand, X = $FF
;; Uses: CommandPosition, Address1High
;; Also: MINIOPND (UNKN), AMOD1 (IIETRM85)
.proc ParseOperand
    ; The position's first character, then its second.
    jsr SkipBlanks
    sty CommandPosition
    cmp FormatCharacter1,x
    bne NoMatch
    jsr SkipBlanks
    cmp FormatCharacter2,x
    beq ShiftBit

    ; A "$" or no second character: a match on the first, the second not taken.
    lda FormatCharacter2,x
    beq Back
    cmp #'$'
    beq Back
    ldy CommandPosition

;; No match: the input from before the first character again.
;; Also: AMOD2 (IIETRM85)
NoMatch:
    clc

;; Also: AMOD4 (IIETRM85)
Back:
    dey

;; Shifts the match into <Format>; at <OPERAND_NUMBER_POSITION>, reads the number.
;; Also: AMOD3 (IIETRM85)
ShiftBit:
    rol Format
    cpx #OPERAND_NUMBER_POSITION
    bne NextMode
    jsr ReadHexNumber
    lda Address2High
    beq StoreCount
    inx

;; Also: AMOD5 (IIETRM85)
StoreCount:
    stx OperandBytes
    ldx #OPERAND_NUMBER_POSITION
    dey

;; Also: AMOD6 (IIETRM85)
NextMode:
    stx Address1High
    dex
    bpl ParseOperand
    rts
.endproc

.endscope

;; AppleSoft's cassette helper for `SHLOAD`, `STORE` and `RECALL`, which AppleSoft's $F775 (`SHLOAD`, carry set) and
;; $F777 (`STORE` and `RECALL`, carry clear) call with the internal ROM switched in.
;;
;; At $C500. For `SHLOAD` it reads the shape table's two-byte length into <LineNumber> and, when the table fits between
;; <ArraysEnd> and HIMEM (<MemoryTop>), loads it just below HIMEM (<AppleSoftCassette::ShapeTable>); otherwise it
;; returns carry set, meaning memory is full, but leaves the start's low byte on the stack, so the return goes astray: a
;; bug in the ROM. The fit is checked on the high bytes only: the table must start in a page above <ArraysEnd>'s. For
;; `STORE` and `RECALL` it sets A1 and A2 to the array's data (<AppleSoftCassette::ArrayBlock>), which AppleSoft then
;; writes or reads with the Monitor.
;; In: carry = set for `SHLOAD`, clear for `STORE` and `RECALL`, SourceStart = the array, LineNumber = its size less one
;;     (`STORE` and `RECALL`)
;; Out: carry = set when the shape table does not fit (that return goes astray, as above)
;; Also: BASTAPE (UNKN)
.proc AppleSoftCassette
.assert * = $C500, "AppleSoftCassette must stay at $C500, where AppleSoft calls it."
    bcc ArrayBlock

    ; `SHLOAD`: the length, two bytes, into LineNumber.
    lda #0
    sta Address1High
    sta Address2High
    ldy #LineNumber
    sty Address1
    iny
    sty Address2
    jsr ReadCassetteData

    ; A2 = HIMEM less one, the table's end; A and the stack = HIMEM less the length less one,
    ; its start.
    clc
    lda MemoryTop
    tax
    dex
    stx Address2
    sbc LineNumber
    pha
    lda MemoryTop+1
    tay
    inx
    bne StoreEnd
    dey

    ; A2's high byte; the start's must be above ArraysEnd's.
StoreEnd:
    sty Address2High
    sbc LineNumber+1
    cmp ArraysEnd+1
    bcc OutOfMemory
    bne ShapeTable

    ; Too long: carry set. The start's low byte is still on the stack, so this return goes astray.
OutOfMemory:
    sec
    rts

;; Lowers HIMEM and <StringsBottom> to the table's start, points <::ShapeTable> and A1 there, and reads the table from
;; tape.
;;
;; The read's checksum is not looked at: it returns carry clear in any case.
;; In: A = the start's high byte, the stack = its low byte
;; Also: TAPESHLOAD (UNKN)
ShapeTable:
    sta MemoryTop+1
    sta StringsBottom+1
    sta Address1High
    sta ::ShapeTable+1
    pla
    sta ::ShapeTable
    sta MemoryTop
    sta StringsBottom
    sta Address1
    jsr ReadCassetteBit
    lda #SHAPE_HEADER_DELAY
    jsr ReadCassetteData::WithHeader
    clc
    rts

;; `STORE` and `RECALL`: A2 = <SourceStart> + <LineNumber>, the array's last byte, and A1 = the start of its data, which
;; AppleSoft's <FMAPT1> leaves in <DestinationEnd>.
;; In: carry = clear
;; Also: TAPEARRAY (UNKN)
ArrayBlock:
    lda SourceStart
    adc LineNumber
    sta Address2
    lda SourceStart+1
    adc LineNumber+1
    sta Address2High
    ldy #ARRAY_DIMENSIONS
    lda (SourceStart),y
    jsr FMAPT1
    lda DestinationEnd
    sta Address1
    lda DestinationEnd+1
    sta Address1High
    clc
    rts
.endproc

;; Writes a cassette header tone, then the sync bit.
;;
;; At $C567, which the Monitor's <Monitor:Cassette::WriteHeader> calls; <ReadCassetteData> calls it to wait out the
;; header, since it toggles <CassetteOut> in timed loops. It and its entries are the same as the original IIe
;; Monitor's.
;; In: A = the tone's length in rounds of 256 half cycles: A + 1 rounds with carry set, A rounds with carry clear but
;;   one for A = 0 or 1, X = the first round's half cycles (0 for 256)
;; Entry:
;;   WriteBit = writes one bit
;; Also: XHEADER (IIETRM85), TAPEHEADR (UNKN)
.proc WriteCassetteHeader
.assert * = $C567, "WriteCassetteHeader must stay at $C567."
    ; Wait counts X down: 256 half cycles a round.
    ldy #HEADER_DELAY
    jsr Wait
    bne WriteCassetteHeader

    ; With the carry set, takes one off A, until it passes 0 and clears the carry.
    adc #$100 - 2
    bcs WriteCassetteHeader

    ; The sync bit: a 0 with a shorter first half.
    ldy #SYNC_DELAY

;; Writes a bit as two half cycles.
;; In: carry = the bit, Y = the first half cycle's count
;; Out: Y = <NEXT_HALF_CYCLE_DELAY>, X = two less, zero = X reached 0
;; Keeps: A, carry
WriteBit:
    jsr Wait

    ; The second half: a little longer, for the time this takes.
    iny
    iny

    ; Waits a half cycle, longer for a 1, then toggles the output.
Wait:
    dey
    bne Wait
    bcc Toggle

    ; A 1 takes longer.
    ldy #ONE_DELAY
LongHalf:
    dey
    bne LongHalf

    ; Toggles the output by reading CassetteOut, and counts the half cycle in X.
Toggle:
    ldy CassetteOut
    ldy #NEXT_HALF_CYCLE_DELAY
    dex
    rts
.endproc

;; Reads a byte from the cassette, high bit first.
;; In: Y = the first bit's starting count
;; Out: A = the byte, X = 0
;; Also: RDTAPEBYTE (UNKN)
.proc ReadCassetteByte
    ldx #BITS_PER_BYTE

    ; Reads a bit and shifts it in.
NextBit:
    pha
    jsr ReadCassetteBit
    pla
    rol a
    ldy #READ_BIT_START
    dex
    bne NextBit
    rts
.endproc

;; Reads a bit by timing two transitions of the cassette input.
;;
;; <ReadCassetteBit::LastLevel> holds the input's last level.
;; In: Y = the starting count
;; Out: carry = the bit: set for a 1, whose half cycles count Y down past 0
;; Keeps: X
;; Entry:
;;   Transition = waits for one transition
;; Also: RDTAPE2BIT (UNKN)
.proc ReadCassetteBit

;; The tape input's last level, which <Transition> compares the input with: <OperandLength>'s byte.
LastLevel = OperandLength
    jsr Transition
    ; Falls into Transition.

;; Waits for the next transition of the cassette input, counting Y down meanwhile.
;; In: Y = the count so far
;; Out: Y = the count, carry = set when it is <READ_ONE_THRESHOLD> or above
;; Keeps: X
Transition:
    ; Until the input's level differs from the last one.
    dey
    lda CassetteIn
    eor LastLevel
    bpl Transition

    ; The new level is the last one now.
    eor LastLevel
    sta LastLevel
    cpy #READ_ONE_THRESHOLD
    rts
.endproc

;; Writes the bytes from A1 to A2 to the cassette after a header tone, then their checksum, the exclusive or of them
;; all with $FF.
;;
;; At $C5AA, which the Monitor's W command (<Monitor:WriteCassette>) calls.
;; In: A = the header's length, Address1/Address1High = the first address, Address2/Address2High = the last
;; Out: X = 0, zero = set
;; Also: WRITE2 (IIETRM85), WRITETAPE (UNKN)
.proc WriteCassetteData
.assert * = $C5AA, "WriteCassetteData must stay at $C5AA."
    jsr WriteCassetteHeader

    ; WriteCassetteHeader leaves A at $FF, where the checksum starts.
    ldy #WRITE_FIRST_COUNT

    ; Writes the byte at A1, keeping the checksum on the stack, and steps A1 to the next until it passes A2.
NextByte:
    ldx #0
    eor (Address1,x)
    pha
    lda (Address1,x)
    jsr WriteByte
    jsr NextInRange
    ldy #WRITE_NEXT_COUNT
    pla
    bcc NextByte

    ; Then the checksum.
    ldy #WRITE_CHECKSUM_COUNT
    jsr WriteByte
    beq Done

;; Writes the 8 bits of A, high bit first.
;; In: A = the byte, Y = the count for the first bit
;; Out: X = 0, zero = set
WriteByte:
    ldx #HALF_CYCLES_PER_BYTE

    ; Writes one bit, from the carry.
NextBit:
    asl a
    jsr WriteCassetteHeader::WriteBit
    bne NextBit
Done:
    rts
.endproc

;; Reads the bytes from A1 to A2 from the cassette, then the checksum byte, and compares it with theirs.
;;
;; At $C5D1, which the Monitor's R command (<Monitor:ReadCassette>) calls. It waits for the tape's tone, lets the
;; header play, finds the sync bit and reads the bytes, keeping the exclusive or of them all with $FF in
;; <ReadCassetteData::Checksum>.
;; In: Address1/Address1High = the first address, Address2/Address2High = the last
;; Out: zero = set when the checksum matches, X = 0
;; Entry:
;;   WithHeader = lets a header of A's length play, for <AppleSoftCassette::ShapeTable>
;; Also: XREAD (IIETRM85), READTAPE (UNKN)
.proc ReadCassetteData
.assert * = $C5D1, "ReadCassetteData must stay at $C5D1."

;; The checksum of the bytes read: <PlotMask>'s byte.
Checksum = PlotMask
    jsr ReadCassetteBit
    lda #READ_HEADER_DELAY

;; Lets the header play for A, then reads.
;; In: A = the header's length to wait out
WithHeader:
    jsr WriteCassetteHeader

    ; WriteCassetteHeader leaves A at $FF, where the checksum starts.
    sta Checksum
    jsr ReadCassetteBit

    ; Waits out the header's half cycles for the shorter one of the sync bit.
FindSync:
    ldy #READ_SYNC_COUNT
    jsr ReadCassetteBit::Transition
    bcs FindSync
    jsr ReadCassetteBit::Transition
    ldy #READ_FIRST_COUNT

    ; Reads a byte into A1, keeping the checksum, and steps A1 to the next until it passes A2.
NextByte:
    jsr ReadCassetteByte
    ; ReadCassetteByte leaves X at 0.
    sta (Address1,x)
    eor Checksum
    sta Checksum
    jsr NextInRange
    ldy #READ_NEXT_COUNT
    bcc NextByte

    ; Then the checksum byte.
    jsr ReadCassetteByte
    cmp Checksum
    rts
.endproc
