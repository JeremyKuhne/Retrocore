; retrocore: style=strict
;; The Enhanced IIe's built-in self-test, $C600-$C7FF: page zero, the main and auxiliary RAM and the MMU's and the
;; IOU's soft switches, with a message in the middle of the text screen when a test fails and when all pass.

;; The built-in self-test, which the firmware's reset function runs when Solid-Apple is held at reset; it destroys
;; memory and never returns.
;;
;; <SelfTest::Run> starts it. On the original IIe, $C401-$C7FF, it checks the MMU's and the IOU's switches, sums the two
;; ROMs, then <SelfTest::RamTest> tests the RAM, printing the location of a failing chip; with both Apple keys held,
;; <SelfTest::Passed> runs it again through the stack page. On the Enhanced IIe, $C600-$C7FF, it tests page zero, then
;; <SelfTest::RamTest> the main and auxiliary RAM and the soft switches, showing a failure or "System OK" in the middle
;; of the text screen; with both Apple keys held, <SelfTest::Passed> runs it again.
.scope SelfTest

; The memory tests.

;; How many pattern increments <Patterns> holds, used in turn byte by byte.
PATTERN_COUNT = 5

;; What a pattern is exclusive-ored with between passes while the screen is drawing, to vary the next pass.
PATTERN_MIX = $A5

;; How many passes <RamTest> makes over pages $01-$FF.
RAM_PASSES = 5

;; The bits of a page number that give its 4K block.
BLOCK_MASK = $F0

;; The 4K block of the I/O space, $C000-$CFFF, whose pages <RamTest> moves to the language card's bank 1.
IO_BLOCK = $C0

;; What a page of the I/O space is moved up by, to bank 1 of the language card's $D000-$DFFF.
BANK1_OFFSET = $10

;; The byte of auxiliary memory that <TestAuxRam> writes and <RamTest> doubles, to see whether auxiliary memory
;; answers.
AuxTestByte = $0C00

;; The byte of auxiliary memory that reads the same as <AuxTestByte> on a card of only 1K, which repeats it there.
AuxMirrorByte = $0800

; The messages.

;; How many pairs of switches <Failed> turns off, one of each pair from each of two runs of three switches:
;; 80STORE, RAMRD and RAMWRT, and ALTZP, SLOTC3ROM and 80COL.
RESET_PAIRS = 3

;; The text line where the self-test shows its messages: line 11 of page one, the middle of the screen.
MessageLine = $05A8

;; The column of the "*" that marks a failure of auxiliary memory.
AUX_MARK_COLUMN = 8

;; The column of "RAM" or "RAM ZP".
NAME_COLUMN = 9

;; The column of the bad bits, and of "MMU", "IOU" and "System OK".
RESULT_COLUMN = 16

;; The length of "RAM ", the start of <RamZeroPageText> that a RAM failure shows.
RAM_TEXT_LENGTH = 4

;; The bits of a byte, each shown in two columns.
BYTE_BITS = 8

;; The length of <SystemOkText>.
SYSTEM_OK_LENGTH = 9

; The soft switch test.

;; The address the switch tables count from: one below the soft switches at $C000, so that 0 can end a group.
SwitchBase = Keyboard - 1

;; The index of the first switch of the first group: the language card's bank.
FIRST_GROUP = 1

;; The index of the first switch of the second group: the language card's RAM read.
SECOND_GROUP = 9

;; The index of the first switch whose failure shows "IOU": `TEXT`. The second group's first switch is the MMU's.
FIRST_IOU_SWITCH = 10

;; The first of <SwitchTest>'s patterns, which count down to 0: a bit for each switch of a group, and one more.
FIRST_PATTERN = $7F

;; The entry that ends a group of switches.
GROUP_END = 0

;; The <SwitchStates> entry for the speaker, which only clicks and has no state to check.
STATE_CLICK = $FF

; Page zero.

;; The page the RAM test is filling or checking, a scoped name for <LOC1>.
;;
;; <RamTest> counts it from $01 through $FF on each pass, filling the pages and then checking them. Pages $C0-$CF,
;; the I/O space, test bank 1 of the language card instead, through <Pointer>.
;; Also: TESTPAGE (UNKN)
Page = LOC1

;; The RAM test's pointer to the page it is testing, a page address with the low byte 0.
;;
;; <RamTest> sets its high byte from <Page>, adding <BANK1_OFFSET> for the pages $C0-$CF so that they reach bank 1
;; of the language card at $D000-$DFFF, and fills or checks the page through it.
;; Also: TESTPTR (UNKN)
Pointer = $02

;; The high byte of <Pointer>.
PointerHigh = Pointer + 1

;; The number of passes the RAM test has left after this one.
;;
;; <RamTest> sets it to 4 and makes five passes, each going on from the pattern the last one ended with.
;; Also: TESTCOUNT (UNKN)
PassesLeft = $04

;; A byte of page zero that <Passed> shifts right, repeating <SwitchTest> until it is 0; it holds what the zero-page
;; test left there.
SwitchPasses = $80

;; A count of <Passed>'s key checks, which starts the patterns when both Apple keys run the test again.
RerunSeed = $FF

;; One entry of <SelfTest::SwitchesOff> or <SelfTest::SwitchesOn>: a soft switch, as its offset from
;; <SelfTest::SwitchBase>.
;; Parameters:
;;   switch = the soft switch's address
.macro SelfTestSwitch switch
    .byte switch - SwitchBase
.endmacro

;; One entry of <SelfTest::SwitchStates>: a switch's status read, as its offset from <Keyboard>, $C000.
;; Parameters:
;;   state = the status read's address
.macro SelfTestState state
    .byte state - Keyboard
.endmacro

;; Runs the Enhanced IIe's self-test, which never returns: page zero tested with five patterns, then <RamTest>,
;; which goes on to <SwitchTest> and <Passed>. It destroys memory.
;;
;; At $C600. <Functions::ResetFirmware> comes here when Solid-Apple is held at reset, and <Passed> to run the test
;; again. It turns graphics on. A starts the patterns: each fills page zero with a running sum, A plus the pattern's
;; increment from <Patterns> for each byte, and checks it; between patterns A is rotated right, and exclusive-ored with
;; <PATTERN_MIX> while the screen is drawing (<DrawingState>). A mismatch goes to <Failed::ZeroPage> with the bad bits.
;; Entry:
;;   ZeroPage = the test from page zero on, which <RamTest> runs again with the auxiliary zero page and RAM selected
;; Also: SELFTEST (UNKN), DIAGS (IIETRM85)
.proc Run
.assert * = $C600, "SelfTest::Run must stay at $C600."
    sta TextOff

    ; Five patterns, from the last increment.
;; The test from page zero on, which <RamTest> runs again with the auxiliary zero page and RAM selected.
;; Also: TSTZPG (IIETRM85)
ZeroPage:
    ldy #PATTERN_COUNT - 1
    ldx #0

    ; Page zero filled with the pattern.
;; Fills page zero with the pattern.
;; Also: ZP1 (IIETRM85)
FillZeroPage:
    clc
    adc Patterns,y
    sta SlotPointer,x
    inx
    bne FillZeroPage

    ; Then checked: the sum is back where it started after 256 bytes.
;; Checks page zero against the pattern.
;; Also: ZP2 (IIETRM85)
CheckZeroPage:
    clc
    adc Patterns,y
    cmp SlotPointer,x
    bne ZeroPageFailed
    inx
    bne CheckZeroPage

    ; The next pattern's start.
    ror a
    bit DrawingState
    bpl NextPattern
    eor #PATTERN_MIX
;; Goes on to the next pattern.
;; Also: ZP3 (IIETRM85)
NextPattern:
    dey
    bpl FillZeroPage
    ; Always taken: Y is $FF.
    bmi RamTest

    ; The bad bits, for Failed::ZeroPage with the carry clear.
;; A byte of page zero failed.
;; Also: ZPERROR (IIETRM85)
ZeroPageFailed:
    eor SlotPointer,x
    clc
    jmp Failed::ZeroPage
.endproc

;; Tests pages $01-$FF with five passes of patterns, then goes on to the auxiliary memory or to <SwitchTest>.
;;
;; Each pass fills every page with a running sum, A plus one of <Patterns> for each byte in turn, then checks it; a
;; mismatch goes to <Failed> with the bad bits. Pages $C0-$CF, the I/O space, test bank 1 of the language card's
;; $D000-$DFFF instead, and $D000-$FFFF are tested with bank 2 selected. Between passes A changes as in <Run>.
;;
;; Then <TestAuxRam>: when auxiliary memory answers and its <AuxMirrorByte> does not change along with
;; <AuxTestByte>, so that it is more than 1K, the whole test runs again from <Run::ZeroPage> with the auxiliary zero
;; page and RAM selected; otherwise <SwitchTest> follows. On that second run <TestAuxRam> returns at once, since RAMRD
;; reads auxiliary memory already, with the flags of its `bit`, which normally go on to <SwitchTest>.
;; In: X = 0
;; Also: RAMTEST (UNKN), TSTMEM (IIETRM85)
.proc RamTest
    stx Page
    stx Pointer
    stx PointerHigh
    ldx #RAM_PASSES - 1
    stx PassesLeft

    ; A pass, from page 1.
;; The next pass.
;; Also: MEM1 (IIETRM85)
NextPass:
    inc Page

    ; A page to fill: bank 2, or for the I/O space bank 1, $10 pages up.
;; Fills a page.
;; Also: MEM2 (IIETRM85)
FillPage:
    tay
    sta LanguageCardBank2ReadWrite
    sta LanguageCardBank2ReadWrite
    lda Page
    and #BLOCK_MASK
    cmp #IO_BLOCK
    bne MainFillPage
    lda LanguageCardBank1ReadWrite
    lda LanguageCardBank1ReadWrite
    lda Page
    ; The carry is set, so this adds BANK1_OFFSET.
    adc #BANK1_OFFSET - 1
    bne SetFillPage
;; A page outside the I/O space.
;; Also: MEM3 (IIETRM85)
MainFillPage:
    lda Page
;; Points at the page.
;; Also: MEM4 (IIETRM85)
SetFillPage:
    sta PointerHigh
    tya
    ldy #0

    ; Each byte, the next increment each time.
;; Fills a byte.
;; Also: MEM5 (IIETRM85)
FillByte:
    clc
    adc Patterns,x
    sta (Pointer),y
    dex
    bpl NextFillByte
    ldx #PATTERN_COUNT - 1
;; Goes on to the next byte.
;; Also: MEM6 (IIETRM85)
NextFillByte:
    iny
    bne FillByte
    inc Page
    bne FillPage
    inc Page

    ; A page to check, banked as it was filled.
;; Checks a page.
;; Also: MEM7 (IIETRM85)
CheckPage:
    tay
    lda LanguageCardBank2ReadWrite
    lda LanguageCardBank2ReadWrite
    lda Page
    and #BLOCK_MASK
    cmp #IO_BLOCK
    bne MainCheckPage
    lda LanguageCardBank1ReadWrite
    lda Page
    ; The carry is set, so this adds BANK1_OFFSET.
    adc #BANK1_OFFSET - 1
    bne SetCheckPage
;; A page outside the I/O space.
;; Also: MEM8 (IIETRM85)
MainCheckPage:
    lda Page
;; Points at the page.
;; Also: MEM9 (IIETRM85)
SetCheckPage:
    sta PointerHigh
    tya
    ldy #0

    ; Each byte against the pattern; A goes on from the byte read.
;; Checks a byte.
;; Also: MEMA (IIETRM85)
CheckByte:
    clc
    adc Patterns,x
    eor (Pointer),y
    bne Failed
    lda (Pointer),y
    dex
    bpl NextCheckByte
    ldx #PATTERN_COUNT - 1
;; Goes on to the next byte.
;; Also: MEMB (IIETRM85)
NextCheckByte:
    iny
    bne CheckByte
    inc Page
    bne CheckPage

    ; The next pass's start, as in Run.
    ror a
    bit DrawingState
    bpl CountPass
    eor #PATTERN_MIX
;; Counts the pass.
;; Also: MEMC (IIETRM85)
CountPass:
    dec PassesLeft
    bpl NextPass

    ; Auxiliary memory, when it answers and AuxMirrorByte is not AuxTestByte.
    tax
    jsr TestAuxRam
    bne AfterAux
    asl AuxTestByte
    asl a
    cmp AuxTestByte
;; Decides between the auxiliary memory and <SwitchTest>.
;; Also: SWCHTST1 (IIETRM85)
AfterAux:
    bne SwitchTest
    cmp AuxMirrorByte
    beq SwitchTest
    txa
    sta AuxZeroPageOn
    jmp Run::ZeroPage
.endproc

;; Shows a failure in the middle of the text screen and hangs: "RAM" or "RAM ZP" with the bad bits, or with no bad
;; bits "MMU" or "IOU".
;;
;; It first selects main memory and 40 columns, SLOTC3ROM off, text and page one, and clears the text page.
;; A failure of the RAM shows "RAM" (the start of <RamZeroPageText>), one of page zero "RAM ZP", after a "*" when
;; auxiliary memory was being tested, then the bits from 7 down to 0 as "0" or "1", 1 for a bad bit. A failure of a
;; switch shows "MMU" (<MmuText>) or "IOU" (<IouText>).
;; In: A = the bad bits
;; Entry:
;;   ZeroPage = a failure of page zero: A = the bad bits, carry = clear
;;   Switches = a failure of a switch: X = 0, carry = clear for an MMU switch, set for an IOU switch
;; Also: TESTFAIL (UNKN), MEMERROR (IIETRM85)
.proc Failed
    sec

    ; Overflow set when auxiliary memory was being tested.
;; A failure of page zero, with the carry clear.
;; Also: BADBITS (IIETRM85)
ZeroPage:
    tax
    lda AuxReadState
    clv
    bpl Switches
    ; The first pattern, $53, has bit 6 set.
    bit Patterns

    ; Off: 80STORE, RAMRD and RAMWRT through Store80Off, and ALTZP, SLOTC3ROM and 80COL through AuxZeroPageOff.
;; A failure of a switch, from <SwitchTest>.
;; Also: BBITS1 (IIETRM85)
Switches:
    lda #' '
    ldy #RESET_PAIRS * 2
;; Turns a pair of switches off.
;; Also: CLRSTS (IIETRM85)
SwitchOff:
    sta Store80Off - 2,y
    sta AuxZeroPageOff - 2,y
    dey
    dey
    bne SwitchOff
    sta TextOn
    sta Page2Off

    ; The text page cleared.
;; Clears the text page.
;; Also: CLRS (IIETRM85)
ClearText:
    sta TextPage1,y
    sta TextPage1 + $100,y
    sta TextPage1 + $200,y
    sta TextPage1 + $300,y
    iny
    bne ClearText

    ; "RAM" or "RAM ZP", after a "*" for auxiliary memory.
    txa
    beq ShowChip
    ldy #RAM_TEXT_LENGTH - 1
    bcs MarkAux
    ldy #MmuText - RamZeroPageText - 1
;; Marks a failure of auxiliary memory.
;; Also: BADMAIN (IIETRM85)
MarkAux:
    lda #'*'
    bvc ShowRam
    sta MessageLine + AUX_MARK_COLUMN
;; Shows "RAM" or "RAM ZP".
;; Also: BADPRIM (IIETRM85)
ShowRam:
    lda RamZeroPageText,y
    sta MessageLine + NAME_COLUMN,y
    dey
    bpl ShowRam

    ; The bits, from bit 0 in the last column, every other column.
    ldy #BYTE_BITS * 2
;; Shows a bit.
;; Also: BBITS2 (IIETRM85)
ShowBit:
    txa
    lsr a
    tax
    lda #'0' >> 1
    rol a
    sta MessageLine + RESULT_COLUMN - 2,y
    dey
    dey
    bne ShowBit
;; Hangs.
;; Also: HANGX (IIETRM85)
Hang:
    beq Hang

    ; "MMU" or "IOU".
;; Shows the chip of a failing switch.
;; Also: BADSWTCH (IIETRM85)
ShowChip:
    ldy #IouText - MmuText - 1
;; Shows a letter.
;; Also: BSWTCH1 (IIETRM85)
ShowLetter:
    lda MmuText,y
    bcc StoreLetter
    lda IouText,y
;; Stores the letter.
;; Also: BSWTCH2 (IIETRM85)
StoreLetter:
    sta MessageLine + RESULT_COLUMN,y
    dey
    bpl ShowLetter
;; Hangs.
;; Also: HANGY (IIETRM85)
HangChip:
    bmi HangChip
.endproc

;; Tests the MMU's and the IOU's soft switches, then goes on to <Passed>: for each pattern from $7F down to $00, sets
;; each switch of a group by one bit of the pattern, then checks each switch's state.
;;
;; A 0 bit sets the switch in <SwitchesOff> and a 1 the one in <SwitchesOn>; <SwitchStates> gives the status read
;; that must follow. The pattern is rotated right through the carry to set the switches, from the group's first, and
;; back left to check them, from its last. The first group is the language card's bank, the speaker (which only
;; clicks), RAMRD, RAMWRT, ALTZP, SLOTC3ROM and 80STORE; the second the language card's RAM read, `TEXT`, MIXED, PAGE2,
;; HIRES, ALTCHAR and 80COL. A mismatch goes to <Failed::Switches>, which shows "MMU" for the first group and the
;; language card's RAM read, and "IOU" for the rest.
;; Also: SWITCHTEST (UNKN), SWCHTST (IIETRM85)
.proc SwitchTest
    ldy #FIRST_GROUP

    ; A group, from the first pattern.
;; Starts a group.
;; Also: SWTST1 (IIETRM85)
Group:
    lda #FIRST_PATTERN

    ; Each switch by the next bit, to the group's end.
;; Sets the next switch by the next bit.
;; Also: SWTST2 (IIETRM85)
SetSwitch:
    ror a
    ldx SwitchesOff,y
    beq Verify
    bcc Hit
    ldx SwitchesOn,y
;; Sets the switch.
;; Also: SWTST3 (IIETRM85)
Hit:
    sta SwitchBase,x
    iny
    bne SetSwitch

    ; The speaker: a click, and its bit back.
;; Clicks the speaker for its entry.
;; Also: CLICK (IIETRM85)
Click:
    ldx Speaker
    rol a

    ; Each switch's state by its bit, back to the group's start.
;; Checks the next switch's state.
;; Also: SWTST4 (IIETRM85)
Verify:
    dey
    ldx SwitchStates,y
    beq NextPattern
    bmi Click
    rol a
    bcc ExpectOff
    asl Keyboard,x
    bcc Mismatch
    bcs Verify
;; The switch must be off.
;; Also: SWTST5 (IIETRM85)
ExpectOff:
    asl Keyboard,x
    bcs Mismatch
    bcc Verify

    ; The next pattern; after $00, the second group, then Passed.
;; Goes on to the next pattern.
;; Also: SWTST6 (IIETRM85)
NextPattern:
    rol a
    iny
    sec
    sbc #1
    bcs SetSwitch
    dey
    bne Passed
    ldy #SECOND_GROUP
    bne Group

    ; MMU or IOU by the failing switch.
;; A switch's state is wrong.
;; Also: SWERR (IIETRM85)
Mismatch:
    ldx #0
    cpy #FIRST_IOU_SWITCH
    jmp Failed::Switches
.endproc

;; Ends a self-test that passed: repeats <SwitchTest> while shifting <SwitchPasses> right leaves bits, clears the
;; text page, then waits: both Apple keys held run <Run> again, otherwise <ShowOk> shows "System OK".
;; Entry:
;;   CheckKeys = the key check, which <ShowOk> goes back to
;; Also: TESTPASS (UNKN), BIGLOOP (IIETRM85)
.proc Passed
    lsr SwitchPasses
    bne SwitchTest
    lda #' '
    ldy #0

    ; The text page cleared.
;; Clears the text page.
;; Also: BLP3 (IIETRM85)
ClearScreen:
    sta TextPage1,y
    sta TextPage1 + $100,y
    sta TextPage1 + $200,y
    sta TextPage1 + $300,y
    iny
    bne ClearScreen

    ; Both Apple keys run the test again, from the next RerunSeed.
;; The key check, which <ShowOk> goes back to.
;; Also: BLP4 (IIETRM85)
CheckKeys:
    lda Button0
    and Button1
    asl a
    inc RerunSeed
    lda RerunSeed
    bcc ShowOk
    jmp Run
.endproc

;; Shows "System OK" (<SystemOkText>) on the text page and goes back to <Passed::CheckKeys>.
;; Also: SYSTEMOK (UNKN), DQUIT (IIETRM85)
.proc ShowOk
    lda TextOn
    ldy #SYSTEM_OK_LENGTH - 1
;; Shows a letter.
;; Also: SUC2 (IIETRM85)
NextLetter:
    lda SystemOkText,y
    sta MessageLine + RESULT_COLUMN,y
    dey
    bpl NextLetter
    ; Always taken: Y is $FF.
    bmi Passed::CheckKeys
.endproc

;; The memory tests' five pattern increments, used in turn byte by byte from the last.
;;
;; Its first byte, $53, has bit 6 set, so `bit Patterns` sets overflow (<Failed::ZeroPage>).
;; Also: TESTPATTERNS (UNKN), NTBL (IIETRM85), SETV (IIETRM85)
Patterns:
    .byte $53, $43, $2B, $29, $07
.assert * - Patterns = PATTERN_COUNT, "PATTERN_COUNT increments."

;; The switch <SwitchTest> sets for a 0 bit, at each index of <SwitchStates>; <GROUP_END> ends a group.
;;
;; The second group ends at the 0 that starts <SwitchesOn>, just past this table.
;; Also: TESTSWITCH1 (UNKN), SWTBL0 (IIETRM85)
SwitchesOff:
    .byte GROUP_END
    SelfTestSwitch LanguageCardBank1ReadOnly
    SelfTestSwitch Speaker
    SelfTestSwitch AuxReadOff
    SelfTestSwitch AuxWriteOff
    SelfTestSwitch AuxZeroPageOff
    SelfTestSwitch SlotC3RomOff
    SelfTestSwitch Store80Off
.assert * - SwitchesOff = SECOND_GROUP - 1, "The first group's end."
    .byte GROUP_END
    SelfTestSwitch LanguageCardRomOnly
    SelfTestSwitch TextOff
    SelfTestSwitch MixedOff
    SelfTestSwitch Page2Off
    SelfTestSwitch HiResOff
    SelfTestSwitch AlternateCharactersOff
    SelfTestSwitch Columns80Off

;; The switch <SwitchTest> sets for a 1 bit, at each index of <SwitchStates>.
;; Also: TESTSWITCH2 (UNKN), SWTBL1 (IIETRM85)
SwitchesOn:
    .byte GROUP_END
    SelfTestSwitch LanguageCardBank2ReadOnly
    SelfTestSwitch Speaker
    SelfTestSwitch AuxReadOn
    SelfTestSwitch AuxWriteOn
    SelfTestSwitch AuxZeroPageOn
    SelfTestSwitch SlotC3RomOn
    SelfTestSwitch Store80On
    .byte GROUP_END
    SelfTestSwitch LanguageCardBank2ReadWrite
    SelfTestSwitch TextOn
    SelfTestSwitch MixedOn
    SelfTestSwitch Page2On
    SelfTestSwitch HiResOn
    SelfTestSwitch AlternateCharactersOn
    SelfTestSwitch Columns80On

;; The status read whose bit 7 must follow each switch <SwitchTest> sets; <STATE_CLICK> for the speaker, which has
;; none.
;;
;; A 0 starts each group, where the checks stop. The last 0 is not read: the checks start one entry below the end.
;; Also: TESTSTATUS (UNKN), RSWTBL (IIETRM85)
SwitchStates:
    .byte GROUP_END
    SelfTestState LanguageCardBank2State
    .byte STATE_CLICK
    SelfTestState AuxReadState
    SelfTestState AuxWriteState
    SelfTestState AuxZeroPageState
    SelfTestState SlotC3RomState
    SelfTestState Store80State
    .byte GROUP_END
    SelfTestState LanguageCardRamState
    SelfTestState TextState
    SelfTestState MixedState
    SelfTestState Page2State
    SelfTestState HiResState
    SelfTestState AlternateCharactersState
    SelfTestState Columns80State
    .byte GROUP_END

;; "RAM ZP", which <Failed> shows for page zero, and whose first four characters it shows for the rest of the RAM.
;; Also: RAMZPTEXT (UNKN), RMESS (IIETRM85)
RamZeroPageText:
    .byte "RAM ZP"

;; "MMU", which <Failed> shows for a switch of the MMU.
;; Also: MMUTEXT (UNKN), SMESS (IIETRM85)
MmuText:
    .byte "MMU"

;; "IOU", which <Failed> shows for a switch of the IOU.
;; Also: IOUTEXT (UNKN)
IouText:
    .byte "IOU"

;; "System OK", which <ShowOk> shows when the self-test passes.
;; Also: SYSOKTEXT (UNKN), SUCCESS (IIETRM85)
SystemOkText:
    .byte "System OK"
.assert * - SystemOkText = SYSTEM_OK_LENGTH, "SYSTEM_OK_LENGTH characters."

    ; The ROM's last byte, which the self-test does not read.
    .byte $00
.assert * = $C800, "The self-test ends at the end of $C7FF."

.endscope
