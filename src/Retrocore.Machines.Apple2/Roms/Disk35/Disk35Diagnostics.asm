; retrocore: style=strict
;; THE BUILT-IN DIAGNOSTICS: THE HOST'S SIDE ($8800-$8DFF) AND THE CARD'S PAGE ZERO FOR THEM ($8E00-$8EFF)
;;
;; The diagnostics start when the host sends the card command <COMMAND_DIAGNOSTICS>: Cn0DG from the Monitor, or three
;; Control-Ds while the card boots. The card then runs <SelfTest::CardDiagnostics> ($8F00), which copies $8A00-$8DFF
;; over the host's usual code at its $7C00-$7FFF, zeroes the slot page's <WaitForDiagnostics> branch, and so sends the
;; host to $CC00 (<Diagnostics::Start>). Later it copies $8800-$89FF to its $0200-$03FF, which the host sees at
;; $CA00-$CBFF with bank 0 latched: the unit report, its texts and the mailbox the two sides end the session with.
;;
;; It is 6502 code: it runs on the II Plus, the IIe, the IIc and the IIgs alike. Lowercase letters show as capitals
;; on a II Plus, whose <ModelId> byte is not 6.
;;
;; THE SCREEN
;;
;;    3.5" Disk Controller Test
;;       J.Arkley & T.Rudin              the "&" turns as a spinner while the host waits
;;   (C)Apple Computer Inc.,1991
;;
;;   Tests:                              an "E" after it: the RAM under the card's I/O page failed
;;   Slot #n
;;   Card pseudoROM-PASS                 the card's tests, reported through card $0002 (host $C802)
;;   Card ROM CRC-PASS
;;   Card ROM Checksum-PASS
;;   SWIM Regs.-PASS
;;   Card RAM-PASS
;;   Host/Card shared data-PASS          the host's own tests of the card's RAM through its windows
;;   Host RAM-PASS
;;
;; Then the units, and, only with Apple's factory fixture in slot 1, their read/write tests; and always:
;;
;;   Press E to Exit
;;
;; While "Press E to Exit" shows, host and card both read memory over and over, for a probe on the bus. E ends the
;; session: the card restarts from its reset, and the host invalidates the power-up byte and goes through its reset
;; vector, so it starts cold.
;;
;; THE HANDSHAKES
;;
;; The card reports each of its tests in its $0002 (<Diagnostics::CardStatus>): <Diagnostics::STATUS_PASSED> or
;; <Diagnostics::STATUS_FAILED>. The host clears a pass and goes on; a failure ends the tests. After the card's own
;; tests, the two talk through card $03FF (<Diagnostics::Signal>, the last byte of the page the card copies to
;; $0300): the host writes <Diagnostics::SIGNAL_GO> to let the card take its next step, <Diagnostics::SIGNAL_STOP>
;; to stop it, and <Diagnostics::SIGNAL_EXIT> to restart it; the card answers 0 for a step done,
;; <Diagnostics::SIGNAL_STOP> for no more steps, or <Diagnostics::SIGNAL_READ_WRITE_FAILED> with the block in its
;; $07/$08 and the error in its $56.

.cpu Mos6502

;; The diagnostics' host code, its texts and its constants.
.scope Diagnostics

; The Monitor's entries that MonitorEntries.asm lacks.

;; Inherit: <Monitor:CarriageReturn>
;; At $FC62.
;; Also: CR (A2RM78, A2RM79, IIEROM82, IIETRM85)
CarriageReturn = $FC62

;; Inherit: <Monitor:PrintHexByte>
;; At $FDDA.
;; Also: PRBYTE (A2RM78, A2RM79, IIEROM82, IIETRM85)
PrintHexByte = $FDDA

;; Inherit: <Monitor:CharacterOut>
;; At $FDED.
;; Also: COUT (A2RM78, A2RM79, IIEROM82, IIETRM85)
CharacterOut = $FDED

; The machine.

;; The 6502's reset vector, in the host's ROM.
ResetVector = $FFFC

;; The IIgs's horizontal count; elsewhere the floating bus: either way a byte that varies.
;; Also: HORIZCNT (UNKN)
HorizontalCount = $C02F

;; What <CaseMask> is on a II Plus: it turns lowercase letters into capitals.
UPPERCASE_MASK = $DF

;; The first character <Print> masks, "@" with its high bit set: masking changes only lowercase, $E0-$FF.
MASKED_FIRST = $C0

; The host's page zero, borrowed.

;; The text being printed (with A as its low byte), or the RAM being summed or checked.
Pointer = $3E

;; The high byte of <Pointer>.
PointerHigh = $3F

;; $C080 plus the slot times 16: an access at it plus Y latches the card's bank Y at $C800-$CBFF.
BankSwitch = $40

;; The high byte of <BankSwitch>.
BankSwitchHigh = $41

;; The bank being tested.
Bank = $42

;; What letters are ANDed with: $FF, or <UPPERCASE_MASK> on a II Plus, which has no lowercase.
CaseMask = $43

;; Y, while a bank is latched.
SavedY = $44

; The text screen.

;; The "&" in the authors' line, which turns while the host waits.
SpinnerOnScreen = $048D

;; Just after "Tests:": an "E" there marks a failure of the RAM under the card's I/O page.
ErrorMark = $0606

; The card's RAM as the host sees it.

;; The card's $7C00-$7FFF, always there.
ExpansionWindow = $CC00

;; The card's page zero, at $C800-$C8FF with bank 0 latched.
CardPageZero = CardWindow

;; Bank 2's card $0A00-$0AFF: RAM that the card's I/O page hides from its 65C02.
RamUnderIo = $CA00

;; Card $0002: the card's report of its last test, <STATUS_PASSED> or <STATUS_FAILED>, which the host clears.
CardStatus = CardPageZero + 2

;; Card $0007: the block whose read/write test failed, low byte first.
FailedBlock = CardPageZero + 7

;; Card $0008: the high byte of <FailedBlock>.
FailedBlockHigh = CardPageZero + 8

;; The card's <UnitCount>: the number of units it found.
CardUnitCount = CardPageZero + UnitCount

;; The card's <DeviceKinds>, a byte for each unit from 1: what kind of drive (<DEVICE_DRIVE>, with
;; <DEVICE_FDHD> for an FDHD, or <DEVICE_BUS>).
CardDeviceKinds = CardPageZero + DeviceKinds

;; The card's <MediaKind>, a byte for each unit from 1: what kind of disk (the MEDIA_ values).
CardMediaKinds = CardPageZero + MediaKind

;; The card's <Sense>, a byte for each unit from 1: <DISK_PROTECTED> is set when the disk is locked.
CardSense = CardPageZero + Sense

; The card's banks, in the window.

;; The bank of card $0000-$03FF: page zero, and this code at $CA00.
BANK_SHARED = 0

;; The bank of card $0800-$0BFF, where the I/O page is.
BANK_IO = 2

;; The last bank, card $3C00-$3FFF.
BANK_LAST = 15

; CardStatus.

;; The card's test passed.
STATUS_PASSED = $A1

;; The card's test failed.
STATUS_FAILED = $4F

; Signal.

;; Host to card: take the next step.
SIGNAL_GO = $A1

;; Host to card: stop and wait. Card to host: no more steps.
SIGNAL_STOP = $4F

;; Host to card: restart. The card answers 0.
SIGNAL_EXIT = $55

;; Card to host: a unit's read/write test failed.
SIGNAL_READ_WRITE_FAILED = $4E


; Card $0200-$03FF, from $8800-$89FF: seen at $CA00-$CBFF with bank 0 latched.
.logicalorg $CA00

;; Lists the units the card found, then has it test units 1 and 2, if Apple's factory fixture is in slot 1. A
;; failure or the end of the tests leaves for <Finish>.
;; In: BankSwitch = $C080 plus the slot times 16
.proc ReportUnits

    ; The heading and the count.
    jsr CarriageReturn
    lda #>TextUnitHeader
    sta PointerHigh
    lda #<TextUnitHeader
    jsr Print
    lda CardUnitCount
    tax
    jsr PrintHexDigit
    jsr CarriageReturn
    txa
    bne Some
    jmp ReadWrite
Some:
    lda #1                          ; the unit, kept on the stack
    pha

    ; Each unit: its number and the kind of drive.
Unit:
    pla
    pha
    tay
    jsr PrintHexDigit
    lda CardDeviceKinds - 1,y
    cmp #DEVICE_DRIVE
    bne NotApple35
    lda #<TextApple35
    jsr Print
    jmp Media
NotApple35:
    cmp #DEVICE_DRIVE | DEVICE_FDHD
    bne NotFdhd
    lda #<TextFdhd
    jsr Print
    jmp Media
NotFdhd:
    cmp #DEVICE_BUS
    bne Media                       ; any other kind: no name
    lda #<TextUniDisk
    jsr Print
    jmp Next                        ; nothing about its disk

    ; Nothing reaches these: an unknown kind was perhaps meant to print "???".
    jsr PrintUnknown
    jmp Next

    ; The kind of disk.
Media:
    pla
    pha
    tay
    lda CardMediaKinds - 1,y
    cmp #MEDIA_400K
    bne Not400K
    lda #<Text400K
    jsr Print
    jmp Locked
Not400K:
    cmp #MEDIA_720K
    bne Not720K
    lda #<Text720K
    jsr Print
    jmp Locked
Not720K:
    cmp #MEDIA_800K
    bne Not800K
    jsr Print800K
    jmp Locked
Not800K:
    cmp #MEDIA_800K_2_TO_1
    bne NotOther800K
    jsr Print800K
    jmp Locked
NotOther800K:
    cmp #MEDIA_1440K
    bne Not1440K
    jsr Print1440K
    jmp Locked
Not1440K:
    cmp #MEDIA_1440K + 2
    bne Unknown
    jsr Print1440K
    jmp Locked
Unknown:
    jsr PrintUnknown
    jmp Next

    ; Whether the disk is locked, for units 1 and 2 only.
Locked:
    pla
    pha
    cmp #3
    bcs Next
    tay
    lda CardSense - 1,y
    and #DISK_PROTECTED
    beq Writable
    lda #<TextYes
    jsr Print
    jmp Next
Writable:
    lda #<TextNo
    jsr Print

    ; The next unit, up to the last.
Next:
    pla
    tay
    cmp CardUnitCount
    beq ReadWrite
    iny
    tya
    pha
    jsr CarriageReturn
    jmp Unit

    ; The card's read/write tests of units 1 and 2.
ReadWrite:
    jsr CarriageReturn
    jsr CarriageReturn
    jsr AwaitCardStep               ; the card answers SIGNAL_STOP without the fixture
    lda #<TextPassed
    jsr Print
    lda #1
    jsr PrintHexDigit
    jsr CarriageReturn
    jsr AwaitCardStep
    lda #<TextPassed
    jsr Print
    lda #2
    jsr PrintHexDigit
    jsr CarriageReturn
    jsr AwaitCardStep               ; the card has no more steps: this goes to Finish
    ; Falls into Print1440K, which nothing should reach from here.
.endproc

;; Prints " 1440K".
;; In: PointerHigh = the high byte of the unit report's texts
;; Out: A = 0, Y = the text's length
.proc Print1440K
    lda #<Text1440K
    jsr Print
    rts
.endproc

;; Prints " 800K ".
;; In: PointerHigh = the high byte of the unit report's texts
;; Out: A = 0, Y = the text's length
.proc Print800K
    lda #<Text800K
    jsr Print
    rts
.endproc

;; Prints "  ??? ".
;; In: PointerHigh = the high byte of the unit report's texts
;; Out: A = 0, Y = the text's length
.proc PrintUnknown
    lda #<TextUnknown
    jsr Print
    rts
.endproc

    .res 59                         ; unused

; The texts ReportUnits and AwaitCardStep print, all in this page: Print takes their low bytes.

;; "Passed R/W for Unit ".
TextPassed:
    .hiascii "Passed R/W for Unit "
    .byte 0

;; "R/W Failure on block $".
TextReadWriteFailure:
    .hiascii "R/W Failure on block $"
    .byte 0

;; "  Err=$".
TextError:
    .hiascii "  Err=$"
    .byte 0

;; The unit list's heading.
TextUnitHeader:
    .hiascii "# Unit        Volume  W/P   Drives="
    .byte 0

;; " UniDisk 3.5".
TextUniDisk:
    .hiascii " UniDisk 3.5"
    .byte 0

;; " Apple 3.5  ".
TextApple35:
    .hiascii " Apple 3.5  "
    .byte 0

;; " Apple FDHD ".
TextFdhd:
    .hiascii " Apple FDHD "
    .byte 0

;; " 400K ".
Text400K:
    .hiascii " 400K "
    .byte 0

;; " 720K ".
Text720K:
    .hiascii " 720K "
    .byte 0

;; " 800K ".
Text800K:
    .hiascii " 800K "
    .byte 0

;; " 1440K".
Text1440K:
    .hiascii " 1440K"
    .byte 0

;; "  ??? ".
TextUnknown:
    .hiascii "  ??? "
    .byte 0

;; "   YES": the disk is locked.
TextYes:
    .hiascii "   YES"
    .byte 0

;; "   NO": the disk is not locked.
TextNo:
    .hiascii "   NO"
    .byte 0
.assert >TextPassed = >TextNo, "The unit report's texts must share a page."

;; Card $03EE-$03FD: <CopySlot1Rom>, in the slot page, copies the first 16 bytes of slot 1's ROM here. The card's test
;; of its units compares them with Apple's factory fixture's.
FixtureId:
    .res 16

;; Card $03FE: the host leaves a byte that varies here; the card makes the block it tests from it.
RandomBlock:
    .byte 0

;; Card $03FF: the mailbox for the card's later steps (the SIGNAL_ values).
Signal:
    .byte 0

; Card $7C00-$7FFF, from $8A00-$8DFF: the host's $CC00-$CFFF.
.assert * = DiagnosticsCode, "The diagnostics' start must be where the slot page jumps."

;; The diagnostics' start, where the slot page's <WaitForDiagnostics> jumps once the card has put this code here. Sets
;; up the screen and reports each of the card's tests as it finishes them, then tests the card's RAM through the
;; windows.
;; In: ExpansionRomSlot = $Cn, the card's slot page; bank 0 latched
.proc Start
    sei
    jsr SetScreen
    jsr SetKeyboard
    jsr SetText
    jsr Home

    ; Lowercase on the IIe, the IIc and the IIgs; capitals on a II Plus.
    lda #$FF
    sta CaseMask
    lda #MODEL_ID_IIE
    cmp ModelId
    beq Title
    lda #UPPERCASE_MASK
    sta CaseMask

    ; The title, and the slot.
Title:
    lda #>TextTitle
    sta PointerHigh
    lda #<TextTitle
    jsr Print
    jsr CarriageReturn
    lda #<TextAuthors
    jsr Print
    jsr CarriageReturn
    lda #<TextCopyright
    jsr Print
    jsr CarriageReturn
    jsr CarriageReturn
    lda #<TextTests
    jsr Print
    jsr CarriageReturn
    lda #<TextSlot
    jsr Print
    lda ExpansionRomSlot
    jsr PrintHexDigit

    ; BankSwitch is $C080 plus the slot times 16 (the slot page's high byte's low nibble, shifted).
    lda ExpansionRomSlot
    asl a
    asl a
    asl a
    asl a
    ora #<BankLatch
    sta BankSwitch
    lda #>BankLatch
    sta BankSwitchHigh
    jsr CarriageReturn

    ; The card's own tests, as it reports them.
    lda #<TextPseudoRom
    jsr Print
    jsr AwaitCardTest
    lda #<TextRomCrc
    jsr Print
    jsr AwaitCardTest
    lda #<TextRomChecksum
    jsr Print
    jsr AwaitCardTest
    lda #<TextSwim
    jsr Print
    jsr AwaitCardTest
    lda #<TextCardRam
    jsr Print
    jsr AwaitCardTest
    lda #<TextShared
    jsr Print
    ; Falls into CheckSharedData.
.endproc

;; Sums the card's RAM that the host can see, as the card's <SelfTest::SumSharedRam> did: card $0006-$07FF and
;; $0C00-$3FFF through the window, $7C00-$7FFE, $0B00-$0BFF, the slot page ($7B00) and $0800-$09FF. The card left the
;; complement of its own sum in $09FF, so the sum is $FF when both saw the same bytes. Goes on to <TestHostRam> when it
;; is, and falls into <Failed> when it is not.
;; In: BankSwitch = $C080 plus the slot times 16, ExpansionRomSlot = $Cn
.proc CheckSharedData
    lda #0
    tax
    ldy #6                          ; past the card's $0000-$0005
    stx Pointer

    ; Banks 0 to 15, but for the I/O page's: card $0006-$07FF and $0C00-$3FFF.
NextBank:
    stx Bank
    sty SavedY
    ldy Bank
    sta (BankSwitch),y
    ldy SavedY
    ldx #>CardWindow
    stx PointerHigh
    ldx #>ExpansionWindow
AddBank:
    clc
    adc (Pointer),y
    iny
    bne AddBank
    inc PointerHigh
    cpx PointerHigh
    bne AddBank
    ldx Bank
    cpx #BANK_IO - 1
    bne NotIo
    inx                             ; skips the bank with the I/O page
NotIo:
    cpx #BANK_LAST
    beq Expansion
    inx
    jmp NextBank

    ; Card $7C00-$7FFE: the host's $CC00-$CFFE.
Expansion:
    ldx #>ExpansionWindow
    stx PointerHigh
    ldx #>ExpansionRomOff
AddExpansion:
    clc
    adc (Pointer),y
    iny
    bne AddExpansion
    inc PointerHigh
    cpx PointerHigh
    bne AddExpansion
AddLast:
    clc
    adc (Pointer),y
    iny
    cpy #<ExpansionRomOff                    ; not $CFFF, which would release this code
    bne AddLast

    ; Card $0B00-$0BFF, in the I/O page's bank.
    ldy #BANK_IO
    sta (BankSwitch),y
    ldy #0
    ldx #>CardWindow + 3
    stx PointerHigh
AddPageB:
    clc
    adc (Pointer),y
    iny
    bne AddPageB

    ; The slot page.
    ldx ExpansionRomSlot
    stx PointerHigh
AddSlot:
    clc
    adc (Pointer),y
    iny
    bne AddSlot

    ; Card $0800-$09FF, in the same bank.
    ldx #>CardWindow
    stx PointerHigh
    ldx #>RamUnderIo
AddLow:
    clc
    adc (Pointer),y
    iny
    bne AddLow
    inc PointerHigh
    cpx PointerHigh
    bne AddLow
    cmp #$FF
    beq TestHostRam
    ; Falls into Failed.
.endproc

;; Prints "-FAIL" and ends the tests.
.proc Failed
    jsr PrintFail
    jmp Finish
.endproc

;; Prints "-PASS" for the shared data, then writes and reads back the card's banks 1-15 (card $0400-$3FFF) through
;; the window, with the byte's offset plus the bank plus the page; then sends the card on to its units.
;; In: BankSwitch = $C080 plus the slot times 16, ExpansionRomSlot = $Cn
.proc TestHostRam
    jsr PrintPass
    lda #<TextHostRam
    jsr Print

    ; Fills each bank.
    ldx #0
    stx Pointer
    inx
Fill:
    stx Bank
    jsr Spin
    ldy Bank
    sta (BankSwitch),y
    ldy #0
    ldx #>CardWindow
    stx PointerHigh
    ldx #>ExpansionWindow
FillByte:
    tya
    clc
    adc Bank
    adc PointerHigh
    sta (Pointer),y
    iny
    bne FillByte
    inc PointerHigh
    cpx PointerHigh
    bne FillByte
    ldx Bank
    cpx #BANK_LAST
    beq Check
    inx
    jmp Fill

    ; Reads each bank back.
Check:
    ldx #0
    stx Pointer
    inx
CheckBank:
    stx Bank
    jsr Spin
    ldy Bank
    sta (BankSwitch),y
    ldy #0
    ldx #>CardWindow
    stx PointerHigh
    ldx #>ExpansionWindow
CheckByte:
    tya
    clc
    adc Bank
    adc PointerHigh
    cmp (Pointer),y
    beq Same
    jmp Failed
Same:
    iny
    bne CheckByte
    inc PointerHigh
    cpx PointerHigh
    bne CheckByte
    ldx Bank
    cpx #BANK_LAST
    beq Passed
    inx
    jmp CheckBank
Passed:
    jsr PrintPass
    ldy #BANK_SHARED
    sta (BankSwitch),y

    ; Calls the slot page's CopySlot1Rom, which must run there: it releases the $C800 space after each read of slot 1,
    ; and its next fetch from $Cn00 takes the space back. Its RTS goes on to AskForUnits.
    lda #>(AskForUnits - 1)
    pha
    lda #<(AskForUnits - 1)
    pha
    lda ExpansionRomSlot
    pha
    lda #<(CopySlot1Rom - 1)
    pha
    rts
.endproc

;; Where <CopySlot1Rom> returns: leaves a byte that varies for the block to test, lets the card find its units, and
;; reports them.
.proc AskForUnits
    lda HorizontalCount
    sta RandomBlock
    jsr AwaitCardStep
    jmp ReportUnits
.endproc

;; Ends the tests: puts the "&" back, stops the card and reads all the card's RAM over and over until E is pressed.
;; Then has the card restart, and restarts the host cold through its reset vector.
;; In: BankSwitch = $C080 plus the slot times 16, ExpansionRomSlot = $Cn
.proc Finish
    lda #'&' | $80
    sta SpinnerOnScreen
    ldy #BANK_SHARED
    sta (BankSwitch),y
    lda #SIGNAL_STOP
    sta Signal
    jsr CarriageReturn
    lda #>TextExit
    sta PointerHigh
    lda #<TextExit
    jsr Print
    jsr CarriageReturn
    lda KeyboardStrobe

    ; Reads every bank, for a probe on the bus.
Read:
    ldx #0
    stx Pointer
NextBank:
    stx Bank
    ldy Bank
    sta (BankSwitch),y
    ldy #0
    ldx #>CardWindow
    stx PointerHigh
    ldx #>ExpansionWindow
ReadBank:
    lda (Pointer),y
    iny
    bne ReadBank
    inc PointerHigh
    cpx PointerHigh
    bne ReadBank
    ldx Bank
    cpx #BANK_LAST
    beq SlotPage
    inx
    jmp NextBank

    ; Then the slot page and $CC00-$CFFE.
SlotPage:
    ldx ExpansionRomSlot
    stx PointerHigh
ReadSlot:
    lda (Pointer),y
    iny
    bne ReadSlot
    ldx #>ExpansionWindow
    stx PointerHigh
    ldx #>ExpansionRomOff
ReadExpansion:
    lda (Pointer),y
    iny
    bne ReadExpansion
    inc PointerHigh
    cpx PointerHigh
    bne ReadExpansion
ReadLast:
    lda (Pointer),y
    iny
    cpy #<ExpansionRomOff
    bne ReadLast

    ; Until E is pressed.
    lda Keyboard
    bpl Read
    sta KeyboardStrobe
    cmp #'E' | $80
    beq Exit
    cmp #'e' | $80
    beq Exit
    bne Read                        ; always

    ; Spoils the power-up byte, so the reset starts cold, and has the card restart.
Exit:
    lda SoftEntryVector + 1         ; makes SoftEntryCheck wrong, for a cold start
    sta SoftEntryCheck
    lda ResetVector + 1             ; returns to the reset handler's second byte, past its CLD
    pha
    lda ResetVector
    pha
    ldy #BANK_SHARED
    sta (BankSwitch),y
    lda #SIGNAL_EXIT
    sta Signal
Wait:
    lda Signal                      ; the card clears it as it restarts
    bne Wait
    rts
.endproc

;; Waits for the card's report of a test, testing the RAM under the card's I/O page meanwhile, and prints "-PASS",
;; or "-FAIL" and ends the tests. It leaves bank 0 latched.
;; In: BankSwitch = $C080 plus the slot times 16, PointerHigh = the high byte of the screen's texts
.proc AwaitCardTest
    jsr Spin

    ; Writes and reads back the RAM under the I/O page.
    ldy #BANK_IO
    sta (BankSwitch),y
    ldy #0
    lda RamUnderIo
    tax
Fill:
    inx
    txa
    sta RamUnderIo,y
    iny
    bne Fill
Check:
    inx
    txa
    cmp RamUnderIo,y
    bne Bad
    iny
    bne Check
    jmp ReadStatus
Bad:
    lda #'E' | $80
    sta ErrorMark

    ; The card's report, if there is one yet.
ReadStatus:
    ldy #BANK_SHARED
    sta (BankSwitch),y
    lda CardStatus
    beq AwaitCardTest
    cmp #STATUS_PASSED
    beq Passed
    jsr PrintFail
    jmp Finish
Passed:
    sty CardStatus                  ; Y = 0: seen
    jmp PrintPass
.endproc

;; Turns the spinner: - \ | / and round again.
;; Out: Y = the new character's place in <Spinner>, plus 1
;; Keeps: X
.proc Spin
    lda SpinnerOnScreen
    ldy #4
Find:
    cmp Spinner,y
    beq Next
    dey
    bne Find
    iny                             ; not found: starts again at "-"
Next:
    lda Spinner - 1,y
    sta SpinnerOnScreen
    rts
.endproc

;; Prints "-PASS" and a new line.
.proc PrintPass
    lda #>TextPass
    sta PointerHigh
    lda #<TextPass
    jsr Print
    jsr CarriageReturn
    rts
.endproc

;; Prints "-FAIL" and a new line.
.proc PrintFail
    lda #>TextFail
    sta PointerHigh
    lda #<TextFail
    jsr Print
    jsr CarriageReturn
    rts
.endproc

;; Prints a text that ends with a zero byte, masking its letters with <CaseMask>. It leaves X as the output hook
;; leaves it, which the Monitor's screen output does not change.
;; In: A = the text's low byte, PointerHigh = its high byte
;; Out: A = 0, Y = the text's length
.proc Print
    sta Pointer
    ldy #0
Next:
    lda (Pointer),y
    bne Character
    rts
Character:
    cmp #MASKED_FIRST
    bcc Show
    and CaseMask
Show:
    jsr CharacterOut
    iny
    bne Next
    rts
.endproc

;; Lets the card take its next step and waits for its answer: returns when the step is done, and on
;; <SIGNAL_STOP> or a read/write failure (which it prints) goes to <Finish>. It leaves bank 0 latched.
;; In: BankSwitch = $C080 plus the slot times 16, PointerHigh = the high byte of the unit report's texts
;; Out: A = 0
.proc AwaitCardStep
    ldy #BANK_SHARED
    sta (BankSwitch),y
    lda #SIGNAL_GO
    sta Signal
Wait:
    jsr Spin
    lda Signal
    cmp #SIGNAL_STOP
    bne NotStop
    jmp Finish
NotStop:
    cmp #SIGNAL_READ_WRITE_FAILED
    bne NotFailed

    ; The block and the error.
    lda #<TextReadWriteFailure      ; PointerHigh is still ReportUnits's
    jsr Print
    lda FailedBlockHigh
    jsr PrintHexByte
    lda FailedBlock
    jsr PrintHexByte
    lda #<TextError
    jsr Print
    lda MailboxError
    jsr PrintHexByte
    jsr CarriageReturn
    jmp Finish
NotFailed:
    cmp #0
    bne Wait                        ; still SIGNAL_GO
    rts
.endproc

    .res 35                         ; unused

; The texts of Start's screen, all in this page: Print takes their low bytes.

;; The title.
TextTitle:
    .hiascii " 3.5", '"', " Disk Controller Test"
    .byte 0

;; The authors, whose "&" is the spinner.
TextAuthors:
    .hiascii "    J.Arkley & T.Rudin"
    .byte 0

;; The copyright.
TextCopyright:
    .hiascii "(C)Apple Computer Inc.,1991"
    .byte 0

;; "Tests:".
TextTests:
    .hiascii "Tests:"
    .byte 0

;; "Slot #".
TextSlot:
    .hiascii "Slot #"
    .byte 0

;; The slot page's test.
TextPseudoRom:
    .hiascii "Card pseudoROM"
    .byte 0

;; The test of the EPROM's CRCs.
TextRomCrc:
    .hiascii "Card ROM CRC"
    .byte 0

;; The test of the EPROM's checksum.
TextRomChecksum:
    .hiascii "Card ROM Checksum"
    .byte 0

;; The SWIM's test.
TextSwim:
    .hiascii "SWIM Regs."
    .byte 0

;; The test of the card's RAM.
TextCardRam:
    .hiascii "Card RAM"
    .byte 0

;; The shared RAM's sum.
TextShared:
    .hiascii "Host/Card shared data"
    .byte 0

;; The host's test of the card's RAM through the window.
TextHostRam:
    .hiascii "Host RAM"
    .byte 0

;; "-PASS".
TextPass:
    .hiascii "-PASS"
    .byte 0

;; "-FAIL".
TextFail:
    .hiascii "-FAIL"
    .byte 0

;; "Press E to Exit".
TextExit:
    .hiascii "Press E to Exit"
    .byte 0
.assert >TextTitle = >TextExit, "The screen's texts must share a page."

;; The spinner's characters: <Spin> turns each into the one before it.
Spinner:
    .hiascii "-/|", '\', "-"
    .byte 0                         ; $CFFF, which the host never reads here
.assert * = $D000, "The diagnostics' host code must end at $CFFF."
.logicalorg

; The card's page zero for the diagnostics, which SelfTest::CardDiagnostics copies in and checks: a pattern in $00-$01
; and zeros. SelfTest::TestRam soon writes over $00-$01 and $04-$05.
.logicalorg $0000
    .byte $55, $0F
    .res 254
.logicalorg

.endscope
