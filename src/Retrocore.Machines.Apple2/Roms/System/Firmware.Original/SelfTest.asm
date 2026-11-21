; retrocore: style=strict
;; The original IIe's built-in self-test, $C400-$C7FF: <RomChecksum>, the checksum byte at $C400, then the
;; self-test itself, which checks the MMU's and the IOU's switches, sums the ROMs, tests the RAM and prints the
;; location of a failing chip.

;; The byte that <SelfTest::ChecksumLow> compares the sum of $C100-$DFFF with, this byte left out.
;;
;; At $C400.
;; Also: CHECKSUM (UNKN)
RomChecksum:
.assert * = $C400, "RomChecksum must stay at $C400."
    .byte $1B

;; The built-in self-test, which the firmware's reset function runs when Solid-Apple is held at reset; it destroys
;; memory and never returns.
;;
;; <SelfTest::Run> starts it. On the original IIe, $C401-$C7FF, it checks the MMU's and the IOU's switches, sums the two
;; ROMs, then <SelfTest::RamTest> tests the RAM, printing the location of a failing chip; with both Apple keys held,
;; <SelfTest::Passed> runs it again through the stack page. On the Enhanced IIe, $C600-$C7FF, it tests page zero, then
;; <SelfTest::RamTest> the main and auxiliary RAM and the soft switches, showing a failure or "System OK" in the middle
;; of the text screen; with both Apple keys held, <SelfTest::Passed> runs it again.
.scope SelfTest

; The switch checks.

;; The stack pointer of an empty stack, which <Run> starts with.
STACK_TOP = $FF

;; How many MMU flags <Run> compares with <MmuStates>: $C011-$C018.
MMU_STATES = 8

;; How many IOU flags <Run> compares with <IouStates>: $C01A-$C01F.
IOU_STATES = 6

;; A flag that is on: bit 7 of its status read is set.
FLAG_ON = $80

;; A flag that is off: bit 7 of its status read is clear.
FLAG_OFF = $00

;; <Chip>'s value while <Run> checks the IOU's flags; 0 is the MMU's.
CHIP_IOU = $FF

; The checksums.

;; The first page of the ROM that <ChecksumLow> sums.
LOW_ROM_FIRST_PAGE = $C1

;; The page after the last that <ChecksumLow> sums, where <ChecksumHigh> goes on.
LOW_ROM_END_PAGE = $E0

;; The byte of the $E000-$FFFF ROM that <ChecksumHigh> compares that ROM's sum with, this byte left out: the last
;; byte of AppleSoft, below the Monitor.
HighRomChecksum = $F7FF

; The RAM test.

;; The first byte the RAM test fills and checks: $0000-$0005 hold the test's own variables.
FIRST_RAM_BYTE = 6

;; The first page of the I/O space, $C000-$CFFF, which the RAM test skips.
IO_PAGE = $C0

;; The first page of the language card's two banks, $D000-$DFFF.
LANGUAGE_CARD_PAGE = $D0

;; The first page of the language card's RAM above the banks, $E000-$FFFF.
HIGH_RAM_PAGE = $E0

;; The last page of memory, where the downward passes start, and the page number a pass below page zero wraps
;; round to.
LAST_PAGE = $FF

;; <LowerLimit>'s value for checking a whole page, down to offset 0.
WHOLE_PAGE_LIMIT = $FF

; The messages.

;; <InverseMask>'s value for normal video.
NORMAL_VIDEO = $FF

; The loop through the stack page.

;; The 6502's stack page, where <RunFromStack> copies <StackLoop> to run it.
StackPage = $0100

;; The low byte of $C090, slot 1's device space, where <StackLoop> starts reading and rewriting the slots.
FIRST_SLOT_BYTE = $90

;; The low byte of the last soft switch <StackLoop> reads, $C079, going down to $C001.
LAST_SWITCH_READ = $79

; Page zero.

;; The self-test's pointer into the memory it sums or tests, a scoped name for <SlotPointer>.
Pointer = SlotPointer

;; The pointer's high byte, the page, a scoped name for <LOC1>.
PointerHigh = LOC1

;; The value the RAM test expects each byte to hold on this pass; X holds its complement, which it writes.
Expected = $02

;; Where <RamTest>'s downward passes stop in a page: the offset below the last byte they check.
;;
;; It is <WHOLE_PAGE_LIMIT> for every page but page zero, where it is <FIRST_RAM_BYTE>, so the downward passes check
;; page zero only down to $0007.
LowerLimit = $03

;; <FlagError>'s copy of the flag number, while it prints.
FlagNumber = $04

;; Whether the RAM test failed on the read of a byte (0) or on the check of the complement it wrote (1).
;;
;; <RamTest> keeps it in <FlagNumber>'s byte, which <FlagError> no longer needs, and <RamFailed> reads it.
WriteCheck = FlagNumber

;; <Button0> as <Run> found it: bit 7 set, Open-Apple held, makes the RAM test click the speaker.
Clicks = $05

;; The bits that failed, set for each bad bit, which <RamFailed> prints a chip location for.
BadBits = $06

;; A, kept by <PrintMessage> while it prints.
MessageSavedA = $07

;; Which chip's flags <Run> is checking: 0 for the MMU's, <CHIP_IOU> for the IOU's.
Chip = $08

;; Not 0 once an MMU flag has failed: <FlagError> has printed the MMU's heading.
MmuFailed = $09

;; Not 0 once an IOU flag has failed: <FlagError> has printed the IOU's heading.
IouFailed = $0A

;; Runs the original IIe's self-test, which never returns: the MMU's and the IOU's switches, then <ChecksumLow>,
;; <ChecksumHigh>, <RamTest> and <Passed>.
;;
;; At $C401. <Functions::ResetFirmware> comes here when Solid-Apple is held at reset, and <StackLoop> to run the test
;; again. It resets the stack, sends output to <ScreenOut>, selects the language card's ROM and clears the screen. Each
;; MMU flag, $C011-$C018, is compared with <MmuStates>; then each MMU switch is changed and changed back, and its flag
;; must follow. The IOU's flags, $C01A-$C01F, and switches follow, against <IouStates>. <FlagError> prints each failure;
;; after all the checks, any failure hangs the test, and otherwise <ChecksumLow> follows.
;; Also: SELFTEST (UNKN)
.proc Run
.assert * = $C401, "SelfTest::Run must stay at $C401."
    ; Open-Apple, held with Solid-Apple, makes the RAM test click the speaker.
    lda Button0
    sta Clicks

    ; An empty stack, output to the screen, the language card's ROM and a clear screen.
    ldx #STACK_TOP
    txs
    lda #<ScreenOut
    sta OutputHook
    lda #>ScreenOut
    sta OutputHookHigh
    lda LanguageCardRomOnly
    jsr Home

    ; No failures yet, and the MMU's flags from flag 0.
    lda #0
    sta MmuFailed
    sta IouFailed
    sta Chip
    tax

    ; Flags 0-7: each MMU flag against its state in MmuStates.
CheckMmuFlag:
    lda LanguageCardBank2State,x
    eor MmuStates,x
    bpl NextMmuFlag
    jsr FlagError
NextMmuFlag:
    inx
    cpx #MMU_STATES
    bne CheckMmuFlag

    ; Flag 8: with bank 1 selected, bank 2's flag must read off.
    sta LanguageCardBank1ReadWrite
    bit LanguageCardBank2State
    sta LanguageCardBank2ReadWrite
    bpl LanguageCardRam
    jsr FlagError

    ; Flag 9: the language card's RAM read on, its flag must read on; then the ROM again.
LanguageCardRam:
    inx
    sta LanguageCardBank2ReadOnly
    bit LanguageCardRamState
    sta LanguageCardRomOnly
    bmi AuxRead
    jsr FlagError

    ; Flag 10: RAMRD.
AuxRead:
    inx
    sta AuxReadOn
    bit AuxReadState
    sta AuxReadOff
    bmi AuxWrite
    jsr FlagError

    ; Flag 11: RAMWRT.
AuxWrite:
    inx
    sta AuxWriteOn
    bit AuxWriteState
    sta AuxWriteOff
    bmi AuxZeroPage
    jsr FlagError

    ; Flag 12: ALTZP.
AuxZeroPage:
    inx
    sta AuxZeroPageOn
    bit AuxZeroPageState
    sta AuxZeroPageOff
    bmi SlotC3Rom
    jsr FlagError

    ; Flag 13: SLOTC3ROM.
SlotC3Rom:
    inx
    sta SlotC3RomOn
    bit SlotC3RomState
    sta SlotC3RomOff
    bmi Store80
    jsr FlagError

    ; Flag 14: 80STORE.
Store80:
    inx
    sta Store80On
    bit Store80State
    sta Store80Off
    bmi IouFlags
    jsr FlagError

    ; The IOU's flags, on a new line, from flag 0.
IouFlags:
    jsr PrintReturn
    ldx #0
    lda #CHIP_IOU
    sta Chip

    ; Flags 0-5: each IOU flag against its state in IouStates.
CheckIouFlag:
    lda TextState,x
    eor IouStates,x
    bpl NextIouFlag
    jsr FlagError
NextIouFlag:
    inx
    cpx #IOU_STATES
    bne CheckIouFlag

    ; Flag 6: 80COL.
    sta Columns80On
    bit Columns80State
    sta Columns80Off
    bmi AlternateCharacters
    jsr FlagError

    ; Flag 7: ALTCHAR.
AlternateCharacters:
    inx
    sta AlternateCharactersOn
    bit AlternateCharactersState
    sta AlternateCharactersOff
    bmi Text
    jsr FlagError

    ; Flag 8: with graphics on, TEXT must read off.
Text:
    inx
    sta TextOff
    bit TextState
    sta TextOn
    bpl Page2
    jsr FlagError

    ; Flag 9: PAGE2.
Page2:
    inx
    sta Page2On
    bit Page2State
    sta Page2Off
    bmi Mixed
    jsr FlagError

    ; Flag 10: MIXED.
Mixed:
    inx
    sta MixedOn
    bit MixedState
    sta MixedOff
    bmi HiRes
    jsr FlagError

    ; Flag 11: HIRES.
HiRes:
    inx
    sta HiResOn
    bit HiResState
    sta HiResOff
    bmi CheckErrors
    jsr FlagError

    ; On to the checksums when no flag failed; otherwise the test stops here.
CheckErrors:
    lda MmuFailed
    ora IouFailed
    beq ChecksumLow
Hang:
    jmp Hang
.endproc

;; Prints a failing flag's number: first, once for each chip, "MMU FLAG E4:" (<MmuFlagText>) or "IOU FLAG E5:"
;; (<IouFlagText>), then the number as a hexadecimal digit and a space.
;; In: X = the flag's number, Chip = which chip's flags, 0 for the MMU's
;; Out: A = the flag's number, MmuFailed/IouFailed = not 0 for the chip whose flag failed
;; Keeps: X, Y
;; Also: FLAGERR (UNKN)
.proc FlagError
    stx FlagNumber

    ; The chip's heading, unless one of its flags has failed already.
    lda Chip
    bne Iou
    lda MmuFailed
    bne PrintNumber
    ldx #MmuFlagText - Messages
    jsr PrintMessage
    inc MmuFailed
    bne PrintNumber
Iou:
    lda IouFailed
    bne PrintNumber
    ldx #IouFlagText - Messages
    jsr PrintMessage
    inc IouFailed

    ; The number and a space, and X back.
PrintNumber:
    lda FlagNumber
    jsr PrintHexDigit
    lda #' '
    jsr ScreenOut
    lda FlagNumber
    tax
    rts
.endproc

;; Sums the ROM from $C100 to $DFFF, <RomChecksum> left out, and compares the sum with it; on a mismatch
;; prints "ROM:E8" (<RomLowText>) and hangs, otherwise goes on to <ChecksumHigh>.
;;
;; The bytes are added with the carry clear each time, so the sum is modulo 256. $D000-$DFFF are read from ROM,
;; which <Run> selected. It leaves <Pointer>/<PointerHigh> at $E000 for <ChecksumHigh>.
;; Also: ROMSUM1 (UNKN)
.proc ChecksumLow
    lda #LOW_ROM_FIRST_PAGE
    sta PointerHigh
    lda #0
    sta Pointer
    tay

    ; A page; page $C4 starts at its second byte, leaving RomChecksum out.
AddPage:
    clc
    adc (Pointer),y
    iny
    bne AddPage
    inc PointerHigh
    ldx PointerHigh
    cpx #>RomChecksum
    bne CheckEnd
    iny
    bne AddPage

    ; Up to the end of $DFFF.
CheckEnd:
    cpx #LOW_ROM_END_PAGE
    beq Compare
    bne AddPage

    ; The sum against RomChecksum.
Compare:
    cmp RomChecksum
    beq ChecksumHigh
    ldx #RomLowText - Messages
    jsr PrintMessage
Hang:
    jmp Hang
.endproc

;; Sums the ROM from $E000 to $FFFF, <HighRomChecksum> left out, and compares the sum with it; on a
;; mismatch prints "ROM:E10" (<RomHighText>) and hangs, otherwise goes on to <RamTest>.
;;
;; It goes on from where <ChecksumLow> left <Pointer>/<PointerHigh>, $E000, and adds as <ChecksumLow> does.
;; Also: ROMSUM2 (UNKN)
.proc ChecksumHigh
    ldy #0
    tya

    ; A byte, skipping the last byte of page $F7.
AddByte:
    clc
    adc (Pointer),y
    iny
    beq NextPage
    cpy #<HighRomChecksum
    bne AddByte
    ldx PointerHigh
    cpx #>HighRomChecksum
    bne AddByte
    iny

    ; The next page, up to the end of $FFFF; then the sum against HighRomChecksum.
NextPage:
    inc PointerHigh
    bne AddByte
    cmp HighRomChecksum
    beq RamTest
    ldx #RomHighText - Messages
    jsr PrintMessage
Hang:
    jmp Hang
.endproc

;; Tests the RAM on the hi-res screen: fills it with 0, then makes four passes that check each byte holds the
;; value expected and write its complement, two upward from $0006 and two downward from $FFFF.
;;
;; The RAM is $0006-$BFFF, the language card's $D000-$DFFF in bank 2 and then in bank 1, and $E000-$FFFF; each pass
;; tests bank 2's $D000-$DFFF before bank 1's. The hi-res screen shows $2000-$3FFF as it is tested. With
;; <Clicks> bit 7 set, the speaker clicks once a page while the RAM is filled and once a byte on the passes. A
;; byte that fails goes to <RamFailed>, with <Expected>, <WriteCheck> and <Pointer>/<PointerHigh> + Y saying which;
;; after the four passes, <Passed>. The downward passes check page zero only down to $0007, so only the upward
;; passes check $0006 (<LowerLimit>).
;; Also: RAMTEST (UNKN)
.proc RamTest
    ; The hi-res screen, and bank 2 of the language card, read and written.
    lda TextOff
    lda HiResOn
    lda MixedOff
    lda LanguageCardBank2ReadWrite
    lda LanguageCardBank2ReadWrite

    ; From $0006, filling with X, 0.
    lda #1
    sta WriteCheck
    lda #WHOLE_PAGE_LIMIT
    sta LowerLimit
    lda #0
    tax
    sta Pointer
    sta PointerHigh
    ldy #FIRST_RAM_BYTE

    ; A page, and a click.
Fill:
    sta (Pointer),y
    iny
    bne Fill
    bit Clicks
    bpl NextFillPage
    sta Speaker

    ; The next page: $C0 becomes $D0, and $E0 the first time becomes $D0 again in bank 1.
NextFillPage:
    inc PointerHigh
    beq StartPasses
    lda PointerHigh
    cmp #IO_PAGE
    bne FillLanguageCard
    lda #LANGUAGE_CARD_PAGE
    sta PointerHigh
    bmi FillMore
FillLanguageCard:
    cmp #HIGH_RAM_PAGE
    bne FillMore
    bit LanguageCardBank2State
    bpl FillBank2
    lda LanguageCardBank1ReadWrite
    lda LanguageCardBank1ReadWrite
    lda #LANGUAGE_CARD_PAGE
    sta PointerHigh
    bmi FillMore

    ; After bank 1's $D000-$DFFF, bank 2 again for $E000-$FFFF.
FillBank2:
    lda LanguageCardBank2ReadWrite
    lda LanguageCardBank2ReadWrite
FillMore:
    txa
    beq Fill

    ; The first pass expects A, 0, and writes its complement.
StartPasses:
    sta Expected
    eor #$FF
    tax

    ; An upward pass, from $0006.
UpPass:
    lda #0
    sta PointerHigh
    ldy #FIRST_RAM_BYTE

    ; A byte, and a click.
UpByte:
    bit Clicks
    bpl CheckUp
    sta Speaker

    ; The byte must hold the value expected.
CheckUp:
    dec WriteCheck
    lda (Pointer),y
    cmp Expected
    beq WriteUp
    jmp RamFailed

    ; Then it must hold its complement, written.
;; The upward pass's write of the complement, which it then checks.
;; Also: RAMUP (UNKN)
WriteUp:
    inc WriteCheck
    txa
    sta (Pointer),y
    cmp (Pointer),y
    beq NextUp
    jmp RamFailed

    ; The next byte or page, through the language card's banks as the fill went.
;; The upward pass's next byte or page.
;; Also: RAMUPNEXT (UNKN)
NextUp:
    iny
    bne UpByte
    inc PointerHigh
    beq Down
    lda PointerHigh
    cmp #IO_PAGE
    bne UpLanguageCard
    lda #LANGUAGE_CARD_PAGE
    sta PointerHigh
    bmi UpByte
UpLanguageCard:
    cmp #HIGH_RAM_PAGE
    bne UpByte
    bit LanguageCardBank2State
    bpl UpBank2
    lda LanguageCardBank1ReadWrite
    lda LanguageCardBank1ReadWrite
    lda #LANGUAGE_CARD_PAGE
    sta PointerHigh
    bmi UpByte
UpBank2:
    lda LanguageCardBank2ReadWrite
    lda LanguageCardBank2ReadWrite
    jmp UpByte

    ; After an upward pass, A is the value it wrote, which the next pass expects. After the first, X is 0 and a
    ; second upward pass follows; after the second, the downward passes.
;; The end of an upward pass: the value written becomes the value expected.
;; Also: RAMDOWN (UNKN)
Down:
    sta Expected
    eor #$FF
    tax
    beq UpPass

    ; A downward pass, from $FFFF.
DownPass:
    lda #LAST_PAGE
    sta PointerHigh
    tay

    ; A byte, and a click.
DownByte:
    bit Clicks
    bpl CheckDown
    sta Speaker

    ; The byte must hold the value expected, then its complement, written.
CheckDown:
    dec WriteCheck
    lda (Pointer),y
    cmp Expected
    bne RamFailed
    inc WriteCheck
    txa
    sta (Pointer),y
    cmp (Pointer),y
    bne RamFailed

    ; The next byte down, to LowerLimit.
    dey
    cpy LowerLimit
    bne DownByte

    ; The next page down: below $D0 the first time, bank 1's $DF; the second time, bank 2 and $BF.
    dec PointerHigh
    lda PointerHigh
    cmp #LAST_PAGE
    beq NextPattern
    cmp #LANGUAGE_CARD_PAGE - 1
    bne CheckPageZero
    bit LanguageCardBank2State
    bpl DownBank2
    lda LanguageCardBank1ReadWrite
    lda LanguageCardBank1ReadWrite
    lda #HIGH_RAM_PAGE - 1
    sta PointerHigh
    bmi DownByte
DownBank2:
    lda LanguageCardBank2ReadWrite
    lda LanguageCardBank2ReadWrite
    lda #IO_PAGE - 1
    sta PointerHigh
    bmi DownByte

    ; Page zero stops at FIRST_RAM_BYTE, which leaves $0006 itself unchecked.
CheckPageZero:
    cmp #0
    beq PageZeroLimit
    bne DownByte
PageZeroLimit:
    lda #FIRST_RAM_BYTE
    sta LowerLimit
    bne DownByte

    ; After a downward pass that wrote 0, both are done; after the first, which wrote $FF, the second expects
    ; $FF, checking whole pages again.
NextPattern:
    txa
    beq Passed
    sta Expected
    sta LowerLimit
    eor #$FF
    tax
    ; Always taken: X is 0.
    beq DownPass
.endproc

;; Reports a failing byte of RAM and hangs: switches the language card's ROM back in, resets the text screen,
;; prints "RAM:" (<RamText>), then the location of the chip of each bad bit, from "F13" (<ChipF13Text>) for bit 7
;; down to "F6" (<ChipF6Text>) for bit 0.
;;
;; <WriteCheck> says which value the byte failed: 0, the one read, against <Expected>; 1, the complement written
;; back. The bad bits are that value exclusive-ored with the byte at <Pointer>/<PointerHigh> + Y. But Y no longer
;; holds the failing byte's offset by then: <ResetScreen> calls <Home>, which passes the firmware its function number
;; in Y. So the bits printed are those of another byte of the failing page, read from ROM for a page from $D000 up.
;; In: Y = the failing byte's offset, carry and the rest as <RamTest> leaves them
;; Also: RAMFAIL (UNKN)
.proc RamFailed
    lda LanguageCardRomOnly
    jsr ResetScreen
    lda TextOn
    ldx #RamText - Messages
    jsr PrintMessage

    ; The bad bits, against the value written back.
    lda WriteCheck
    beq BadBitsOnRead
    lda Expected
    eor #$FF
    eor (Pointer),y
    sta BadBits
    jmp PrintBits

    ; Or against the value expected.
;; The bad bits when the byte failed as it was read.
;; Also: RAMBITS (UNKN)
BadBitsOnRead:
    lda Expected
    eor (Pointer),y
    sta BadBits

    ; A chip for each bad bit, from bit 7 down; PrintMessage keeps A.
PrintBits:
    lda BadBits
    asl a
    bcc Bit6
    ldx #ChipF13Text - Messages
    jsr PrintMessage
Bit6:
    asl a
    bcc Bit5
    ldx #ChipF12Text - Messages
    jsr PrintMessage
Bit5:
    asl a
    bcc Bit4
    ldx #ChipF11Text - Messages
    jsr PrintMessage
Bit4:
    asl a
    bcc Bit3
    ldx #ChipF10Text - Messages
    jsr PrintMessage
Bit3:
    asl a
    bcc Bit2
    ldx #ChipF9Text - Messages
    jsr PrintMessage
Bit2:
    asl a
    bcc Bit1
    ldx #ChipF8Text - Messages
    jsr PrintMessage
Bit1:
    asl a
    bcc Bit0
    ldx #ChipF7Text - Messages
    jsr PrintMessage
Bit0:
    asl a
    bcc Hang
    ldx #ChipF6Text - Messages
    jsr PrintMessage
Hang:
    jmp Hang
.endproc

;; Ends a self-test that passed: switches the language card's ROM back in and resets the text screen; with both
;; Apple keys still held runs the test again through <RunFromStack>, otherwise prints "KERNEL OK"
;; (<KernelOkText>) and hangs.
;; Also: TESTPASS (UNKN)
.proc Passed
    lda LanguageCardRomOnly
    jsr ResetScreen
    lda TextOn

    ; Both Apple keys: again.
    lda Button0
    and Button1
    bmi RunFromStack
    ldx #KernelOkText - Messages
    jsr PrintMessage
Hang:
    jmp Hang
.endproc

;; Copies <StackLoop> to the stack page, <StackPage>, and runs it there.
;; Also: TESTLOOP (UNKN)
.proc RunFromStack
    ldx #0
CopyByte:
    lda StackLoop,x
    sta StackPage,x
    inx
    cpx #.sizeof(StackLoop)
    bne CopyByte
    jmp StackPage
.endproc

;; Prints the message at <Messages> + X, which ends with a 0, through <ScreenOut>.
;; In: X = the message's offset from <Messages>
;; Out: X = the offset of the 0 that ends it
;; Keeps: A, Y
;; Also: TESTMSG (UNKN)
.proc PrintMessage
    sta MessageSavedA
NextCharacter:
    lda Messages,x
    beq Done
    jsr ScreenOut
    inx
    bne NextCharacter
Done:
    lda MessageSavedA
    rts
.endproc

;; The self-test's messages, each ended by a 0, which <PrintMessage> finds by their offsets from here.
;; Also: TESTMSGS (UNKN)
Messages:
;; "ROM:E8" and a Return: the sum of $C100-$DFFF is wrong.
;; Also: MSGROM1 (UNKN)
RomLowText:
    .byte "ROM:E8", KEY_RETURN, 0

;; "ROM:E10" and a Return: the sum of $E000-$FFFF is wrong.
;; Also: MSGROM2 (UNKN)
RomHighText:
    .byte "ROM:E10", KEY_RETURN, 0

;; "RAM:", before the chips of a RAM failure.
;; Also: MSGRAM (UNKN)
RamText:
    .byte "RAM:", 0

;; "KERNEL OK", when the self-test passes.
;; Also: MSGOK (UNKN)
KernelOkText:
    .byte "KERNEL OK", 0

;; "F13 ", the RAM chip of bit 7.
;; Also: MSGF13 (UNKN)
ChipF13Text:
    .byte "F13 ", 0

;; "F12 ", the RAM chip of bit 6.
;; Also: MSGF12 (UNKN)
ChipF12Text:
    .byte "F12 ", 0

;; "F11 ", the RAM chip of bit 5.
;; Also: MSGF11 (UNKN)
ChipF11Text:
    .byte "F11 ", 0

;; "F10 ", the RAM chip of bit 4.
;; Also: MSGF10 (UNKN)
ChipF10Text:
    .byte "F10 ", 0

;; "F9 ", the RAM chip of bit 3.
;; Also: MSGF9 (UNKN)
ChipF9Text:
    .byte "F9 ", 0

;; "F8 ", the RAM chip of bit 2.
;; Also: MSGF8 (UNKN)
ChipF8Text:
    .byte "F8 ", 0

;; "F7 ", the RAM chip of bit 1.
;; Also: MSGF7 (UNKN)
ChipF7Text:
    .byte "F7 ", 0

;; "F6 ", the RAM chip of bit 0.
;; Also: MSGF6 (UNKN)
ChipF6Text:
    .byte "F6 ", 0

;; "MMU FLAG E4:", the heading of the MMU's failing flags.
;; Also: MSGMMU (UNKN)
MmuFlagText:
    .byte "MMU FLAG E4:", 0

;; "IOU FLAG E5:", the heading of the IOU's failing flags.
;; Also: MSGIOU (UNKN)
IouFlagText:
    .byte "IOU FLAG E5:", 0

;; Exercises the slot ROMs and soft switches, then runs the self-test again: code that <RunFromStack> copies to
;; <StackPage> and runs there.
;;
;; It selects the slot ROMs at $C100-$CFFF and frees the $C800 space (<ExpansionRomOff>), reads and rewrites every byte
;; from $C090 to $CFFF, reads $C079 down to $C001, then selects the internal ROM and text again and jumps to <Run>. It
;; is assembled here, but its branches are relative and its one jump goes to <Run>, so it runs the same at $0100.
;; Also: LOOPCODE (UNKN)
.proc StackLoop
    sta InternalCxRomOff
    sta ExpansionRomOff

    ; From $C090; Y is set twice, and the first is not used.
    ldy #0
    lda #IO_PAGE
    sta PointerHigh
    lda #0
    sta Pointer
    ldy #FIRST_SLOT_BYTE

    ; Each byte read and written back, to the end of $CFFF.
TouchSlotRoms:
    lda (Pointer),y
    sta (Pointer),y
    iny
    bne TouchSlotRoms
    inc PointerHigh
    lda PointerHigh
    cmp #LANGUAGE_CARD_PAGE
    bne TouchSlotRoms

    ; The soft switches read from $C079 down to $C001.
    lda #IO_PAGE
    sta PointerHigh
    ldy #LAST_SWITCH_READ
ReadSwitches:
    lda (Pointer),y
    dey
    bne ReadSwitches

    ; The internal ROM and text, and the test again.
    sta InternalCxRomOn
    sta TextOn
    jmp Run
.endproc

;; Resets the text screen for a message: <InitDisplay>, normal video in <InverseMask>, and <Home>.
;; Also: TESTSCRN (UNKN)
.proc ResetScreen
    jsr InitDisplay
    lda #NORMAL_VIDEO
    sta InverseMask
    jsr Home
    rts
.endproc

;; The state each MMU flag, $C011-$C018, must have when <Run> starts: bank 2 and the internal $Cx ROM on, the rest
;; off.
;; Also: MMUFLAGS (UNKN)
MmuStates:
    .byte FLAG_ON                   ; LanguageCardBank2State
    .byte FLAG_OFF                  ; LanguageCardRamState
    .byte FLAG_OFF                  ; AuxReadState
    .byte FLAG_OFF                  ; AuxWriteState
    .byte FLAG_ON                   ; InternalCxRomState
    .byte FLAG_OFF                  ; AuxZeroPageState
    .byte FLAG_OFF                  ; SlotC3RomState
    .byte FLAG_OFF                  ; Store80State
.assert * - MmuStates = MMU_STATES, "A state for each MMU flag."

;; The state each IOU flag, $C01A-$C01F, must have when <Run> checks them: text on, the rest off.
;; Also: IOUFLAGS (UNKN)
IouStates:
    .byte FLAG_ON                   ; TextState
    .byte FLAG_OFF                  ; MixedState
    .byte FLAG_OFF                  ; Page2State
    .byte FLAG_OFF                  ; HiResState
    .byte FLAG_OFF                  ; AlternateCharactersState
    .byte FLAG_OFF                  ; Columns80State
.assert * - IouStates = IOU_STATES, "A state for each IOU flag."

    ; The ROM's last four bytes, unused.
    .res 4, 0
.assert * = $C800, "The self-test ends at the end of $C7FF."

.endscope
