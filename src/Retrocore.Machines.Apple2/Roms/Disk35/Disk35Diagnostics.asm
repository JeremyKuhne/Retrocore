;; THE BUILT-IN DIAGNOSTICS: THE HOST'S SIDE ($8800-$8DFF) AND THE CARD'S PAGE ZERO FOR THEM ($8E00-$8EFF)
;;
;; The diagnostics start when the host sends the card command $3D (CMDDIAGNOSTICS): Cn0DG from the Monitor, or three
;; Control-Ds while the card boots. The card then runs TestDiagnostics ($8F00), which copies $8A00-$8DFF over the
;; host's usual code at its $7C00-$7FFF, zeroes the slot page's DIAGWAIT branch, and so sends the host to $CC00
;; (DiagStart). Later it copies $8800-$89FF to its $0200-$03FF, which the host sees at $CA00-$CBFF with bank 0
;; latched: the unit report, its texts and the mailbox the two sides end the session with.
;;
;; It is 6502 code: it runs on the II Plus, the IIe, the IIc and the IIgs alike. Lowercase letters show as capitals
;; on a II Plus, whose VERSION byte is not 6.
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
;; Then, only with Apple's factory fixture in slot 1, the units and their read/write tests; and always:
;;
;;   Press E to Exit
;;
;; While "Press E to Exit" shows, host and card both read memory over and over, for a probe on the bus. E ends the
;; session: the card restarts from its reset, and the host invalidates the power-up byte and goes through its reset
;; vector, so it starts cold.
;;
;; THE HANDSHAKES
;;
;; The card reports each of its tests in its $0002 (DIAG_CardStatus): DIAG_PASSED or DIAG_FAILED. The host clears a
;; pass and goes on; a failure ends the tests. After the card's own tests, the two talk through card $03FF
;; (DiagSignal, the last byte of the page the card copies to $0300): the host writes DIAG_GO to let the card take its
;; next step, DIAG_STOP to stop it, and DIAG_EXIT to restart it; the card answers 0 for a step done, DIAG_STOP for no
;; more steps, or DIAG_RWFAILED with the block in its $07/$08 and the error in its $56.

.cpu Mos6502

DIAG_CR = $FC62                     ;; the Monitor's CR: the cursor to the start of the next line
DIAG_PRBYTE = $FDDA                 ;; the Monitor's PRBYTE: prints A as two hex digits
DIAG_COUT = $FDED                   ;; the Monitor's COUT: prints A through the output hook
DIAG_RESETVECTOR = $FFFC            ;; the 6502's reset vector, in the host's ROM
DIAG_HORIZCNT = $C02F               ;; the IIgs's horizontal count; the floating bus elsewhere: a byte that varies

; The host's page zero, borrowed.
DIAG_Pointer = $3E                  ;; the text being printed (with A as its low byte), or the RAM being summed
DIAG_BankSwitch = $40               ;; $C080+$n0: an access at it plus Y latches the card's bank Y at $C800-$CBFF
DIAG_Bank = $42                     ;; the bank being tested
DIAG_CaseMask = $43                 ;; ANDed with letters: $FF, or $DF on a II Plus without lowercase
DIAG_SaveY = $44                    ;; Y, while a bank is latched

; The text screen.
DIAG_SpinnerAt = $048D              ;; the "&" in the authors' line, which turns while the host waits
DIAG_ErrorMark = $0606              ;; just after "Tests:": an "E" for a failure of the RAM under the I/O page

; The card's RAM as the host sees it.
DIAG_UnderIo = $CA00                ;; bank 2's card $0A00-$0AFF: RAM that the card's I/O page hides from its 65C02
DIAG_CardStatus = $C802             ;; bank 0's card $0002: the card's report of its last test
DIAG_FailedBlock = $C807            ;; bank 0's card $0007/$0008: the block that failed, low byte first
DIAG_UnitCount = $C833              ;; bank 0's card $0033: the number of units the card found
DIAG_UnitKinds = $C834              ;; card $0034, a byte for each unit from 1: what kind of drive
DIAG_UnitMedia = $C840              ;; card $0040, a byte for each unit from 1: what kind of disk
DIAG_UnitStatus = $C846             ;; card $0046, a byte for each unit from 1: bit 5 set when the disk is locked

DIAG_BANKSHARED = 0                 ;; the bank of card $0000-$03FF: page zero and this code at $CA00
DIAG_BANKIO = 2                     ;; the bank of card $0800-$0BFF, where the I/O page is
DIAG_BANKLAST = 15                  ;; the last bank, card $3C00-$3FFF

; DIAG_CardStatus.
DIAG_PASSED = $A1                   ;; the card's test passed
DIAG_FAILED = $4F                   ;; the card's test failed

; DiagSignal.
DIAG_GO = $A1                       ;; host to card: take the next step
DIAG_STOP = $4F                     ;; host to card: stop and wait; card to host: no more steps
DIAG_EXIT = $55                     ;; host to card: restart; the card answers 0
DIAG_RWFAILED = $4E                 ;; card to host: a unit's read/write test failed

; DIAG_UnitKinds.
DIAG_KINDAPPLE35 = $01              ;; an Apple 3.5 Drive, 800K
DIAG_KINDFDHD = $03                 ;; an Apple FDHD (SuperDrive)
DIAG_KINDUNIDISK = $80              ;; a UniDisk 3.5, an intelligent drive

; DIAG_UnitMedia.
DIAG_MEDIA400K = $02
DIAG_MEDIA800K = $04                ;; and DIAG_MEDIA800K+2
DIAG_MEDIA720K = $08
DIAG_MEDIA1440K = $0A               ;; and DIAG_MEDIA1440K+2

DIAG_LOCKED = $20                   ;; DIAG_UnitStatus: the disk is write-protected

; Card $0200-$03FF, from $8800-$89FF: seen at $CA00-$CBFF with bank 0 latched.
.logicalorg $CA00

;; Lists the units the card found, then has it test units 1 and 2, if Apple's factory fixture is in slot 1. A
;; failure or the end of the tests leaves for DiagFinish.
DiagReportUnits:
    jsr DIAG_CR
    lda #>DiagTextUnitHeader
    sta DIAG_Pointer+1
    lda #<DiagTextUnitHeader
    jsr DiagPrint
    lda DIAG_UnitCount
    tax
    jsr PRHEX
    jsr DIAG_CR
    txa
    bne DiagReportUnits_Some
    jmp DiagReportUnits_ReadWrite
DiagReportUnits_Some:
    lda #1                          ; the unit, kept on the stack
    pha
DiagReportUnits_Unit:
    pla
    pha
    tay
    jsr PRHEX
    lda DIAG_UnitKinds-1,y
    cmp #DIAG_KINDAPPLE35
    bne DiagReportUnits_NotApple35
    lda #<DiagTextApple35
    jsr DiagPrint
    jmp DiagReportUnits_Media
DiagReportUnits_NotApple35:
    cmp #DIAG_KINDFDHD
    bne DiagReportUnits_NotFdhd
    lda #<DiagTextFdhd
    jsr DiagPrint
    jmp DiagReportUnits_Media
DiagReportUnits_NotFdhd:
    cmp #DIAG_KINDUNIDISK
    bne DiagReportUnits_Media       ; any other kind: no name
    lda #<DiagTextUniDisk
    jsr DiagPrint
    jmp DiagReportUnits_Next        ; nothing about its disk
    ; Nothing reaches these: an unknown kind was perhaps meant to print "???".
    jsr DiagPrintUnknown
    jmp DiagReportUnits_Next
DiagReportUnits_Media:
    pla
    pha
    tay
    lda DIAG_UnitMedia-1,y
    cmp #DIAG_MEDIA400K
    bne DiagReportUnits_Not400K
    lda #<DiagText400K
    jsr DiagPrint
    jmp DiagReportUnits_Locked
DiagReportUnits_Not400K:
    cmp #DIAG_MEDIA720K
    bne DiagReportUnits_Not720K
    lda #<DiagText720K
    jsr DiagPrint
    jmp DiagReportUnits_Locked
DiagReportUnits_Not720K:
    cmp #DIAG_MEDIA800K
    bne DiagReportUnits_Not800K
    jsr DiagPrint800K
    jmp DiagReportUnits_Locked
DiagReportUnits_Not800K:
    cmp #DIAG_MEDIA800K+2
    bne DiagReportUnits_Not800K2
    jsr DiagPrint800K
    jmp DiagReportUnits_Locked
DiagReportUnits_Not800K2:
    cmp #DIAG_MEDIA1440K
    bne DiagReportUnits_Not1440K
    jsr DiagPrint1440K
    jmp DiagReportUnits_Locked
DiagReportUnits_Not1440K:
    cmp #DIAG_MEDIA1440K+2
    bne DiagReportUnits_Unknown
    jsr DiagPrint1440K
    jmp DiagReportUnits_Locked
DiagReportUnits_Unknown:
    jsr DiagPrintUnknown
    jmp DiagReportUnits_Next
DiagReportUnits_Locked:
    pla
    pha
    cmp #3                          ; units 1 and 2 only
    bcs DiagReportUnits_Next
    tay
    lda DIAG_UnitStatus-1,y
    and #DIAG_LOCKED
    beq DiagReportUnits_Writable
    lda #<DiagTextYes
    jsr DiagPrint
    jmp DiagReportUnits_Next
DiagReportUnits_Writable:
    lda #<DiagTextNo
    jsr DiagPrint
DiagReportUnits_Next:
    pla
    tay
    cmp DIAG_UnitCount
    beq DiagReportUnits_ReadWrite
    iny
    tya
    pha
    jsr DIAG_CR
    jmp DiagReportUnits_Unit
DiagReportUnits_ReadWrite:
    jsr DIAG_CR
    jsr DIAG_CR
    jsr DiagAwaitResult             ; the card answers DIAG_STOP without the fixture
    lda #<DiagTextPassed
    jsr DiagPrint
    lda #1
    jsr PRHEX
    jsr DIAG_CR
    jsr DiagAwaitResult
    lda #<DiagTextPassed
    jsr DiagPrint
    lda #2
    jsr PRHEX
    jsr DIAG_CR
    jsr DiagAwaitResult             ; the card has no more steps: this goes to DiagFinish
    ; Falls into DiagPrint1440K, which nothing should reach from here.

;; Prints " 1440K".
;; Out: A = 0, Y = the text's length
DiagPrint1440K:
    lda #<DiagText1440K
    jsr DiagPrint
    rts

;; Prints " 800K ".
;; Out: A = 0, Y = the text's length
DiagPrint800K:
    lda #<DiagText800K
    jsr DiagPrint
    rts

;; Prints "  ??? ".
;; Out: A = 0, Y = the text's length
DiagPrintUnknown:
    lda #<DiagTextUnknown
    jsr DiagPrint
    rts

    .res 59                         ; unused

;; The texts DiagReportUnits and DiagAwaitResult print, in this page: DiagPrint takes their low bytes.
DiagTextPassed:
    .hiascii "Passed R/W for Unit "
    .byte 0
DiagTextRwFailure:
    .hiascii "R/W Failure on block $"
    .byte 0
DiagTextErr:
    .hiascii "  Err=$"
    .byte 0
DiagTextUnitHeader:
    .hiascii "# Unit        Volume  W/P   Drives="
    .byte 0
DiagTextUniDisk:
    .hiascii " UniDisk 3.5"
    .byte 0
DiagTextApple35:
    .hiascii " Apple 3.5  "
    .byte 0
DiagTextFdhd:
    .hiascii " Apple FDHD "
    .byte 0
DiagText400K:
    .hiascii " 400K "
    .byte 0
DiagText720K:
    .hiascii " 720K "
    .byte 0
DiagText800K:
    .hiascii " 800K "
    .byte 0
DiagText1440K:
    .hiascii " 1440K"
    .byte 0
DiagTextUnknown:
    .hiascii "  ??? "
    .byte 0
DiagTextYes:
    .hiascii "   YES"
    .byte 0
DiagTextNo:
    .hiascii "   NO"
    .byte 0
.assert >DiagTextPassed == >DiagTextNo

;; Card $03EE-$03FD: COPYC100, in the slot page, copies the first 16 bytes of slot 1's ROM here. TestUnits compares
;; them with Apple's factory fixture's.
DiagFixtureId:
    .res 16

;; Card $03FE: the host leaves a byte that varies here; TestWriteBlock makes the block to test from it.
DiagRandomBlock:
    .byte 0

;; Card $03FF: the mailbox for the card's later steps (DIAG_GO, DIAG_STOP, DIAG_EXIT and DIAG_RWFAILED).
DiagSignal:
    .byte 0

; Card $7C00-$7FFF, from $8A00-$8DFF: the host's $CC00-$CFFF.
.assert * == DIAGENTRY

;; The diagnostics' start, where the slot page's DIAGWAIT jumps once the card has put this code here. Sets up the
;; screen and reports each of the card's tests as it finishes them, then tests the card's RAM through the windows.
DiagStart:
    sei
    jsr SETVID
    jsr SETKBD
    jsr SETTXT
    jsr HOME
    lda #$FF
    sta DIAG_CaseMask
    lda #6                          ; the IIe, the IIc and the IIgs show lowercase
    cmp VERSION
    beq DiagStart_Title
    lda #$DF
    sta DIAG_CaseMask
DiagStart_Title:
    lda #>DiagTextTitle
    sta DIAG_Pointer+1
    lda #<DiagTextTitle
    jsr DiagPrint
    jsr DIAG_CR
    lda #<DiagTextAuthors
    jsr DiagPrint
    jsr DIAG_CR
    lda #<DiagTextCopyright
    jsr DiagPrint
    jsr DIAG_CR
    jsr DIAG_CR
    lda #<DiagTextTests
    jsr DiagPrint
    jsr DIAG_CR
    lda #<DiagTextSlot
    jsr DiagPrint
    lda MSLOT
    jsr PRHEX
    lda MSLOT
    asl a
    asl a
    asl a
    asl a
    ora #<LCRAM2
    sta DIAG_BankSwitch
    lda #>LCRAM2
    sta DIAG_BankSwitch+1
    jsr DIAG_CR
    lda #<DiagTextPseudoRom
    jsr DiagPrint
    jsr DiagAwaitCard
    lda #<DiagTextRomCrc
    jsr DiagPrint
    jsr DiagAwaitCard
    lda #<DiagTextRomChecksum
    jsr DiagPrint
    jsr DiagAwaitCard
    lda #<DiagTextSwim
    jsr DiagPrint
    jsr DiagAwaitCard
    lda #<DiagTextCardRam
    jsr DiagPrint
    jsr DiagAwaitCard
    lda #<DiagTextShared
    jsr DiagPrint
    ; Falls into DiagSharedData.

;; Sums the card's RAM that the host can see, as TestSharedData did: card $0006-$07FF and $0C00-$3FFF through the
;; window, $7C00-$7FFE, $0B00-$0BFF, the slot page ($7B00) and $0800-$09FF. The card left the complement of its own
;; sum in $09FF, so the sum is $FF when both saw the same bytes.
DiagSharedData:
    lda #0
    tax
    ldy #6                          ; past the card's $0000-$0005
    stx DIAG_Pointer
DiagSharedData_Bank:
    stx DIAG_Bank
    sty DIAG_SaveY
    ldy DIAG_Bank
    sta (DIAG_BankSwitch),y
    ldy DIAG_SaveY
    ldx #$C8
    stx DIAG_Pointer+1
    ldx #$CC
DiagSharedData_AddBank:
    clc
    adc (DIAG_Pointer),y
    iny
    bne DiagSharedData_AddBank
    inc DIAG_Pointer+1
    cpx DIAG_Pointer+1
    bne DiagSharedData_AddBank
    ldx DIAG_Bank
    cpx #DIAG_BANKIO-1
    bne DiagSharedData_NotIo
    inx                             ; skips the bank with the I/O page
DiagSharedData_NotIo:
    cpx #DIAG_BANKLAST
    beq DiagSharedData_Expansion
    inx
    jmp DiagSharedData_Bank
DiagSharedData_Expansion:
    ldx #$CC
    stx DIAG_Pointer+1
    ldx #$CF
DiagSharedData_AddExpansion:
    clc
    adc (DIAG_Pointer),y
    iny
    bne DiagSharedData_AddExpansion
    inc DIAG_Pointer+1
    cpx DIAG_Pointer+1
    bne DiagSharedData_AddExpansion
DiagSharedData_AddLast:
    clc
    adc (DIAG_Pointer),y
    iny
    cpy #<CLRROM                    ; not $CFFF, which would release this code
    bne DiagSharedData_AddLast
    ldy #DIAG_BANKIO
    sta (DIAG_BankSwitch),y
    ldy #0
    ldx #$CB
    stx DIAG_Pointer+1
DiagSharedData_AddPageB:
    clc
    adc (DIAG_Pointer),y
    iny
    bne DiagSharedData_AddPageB
    ldx MSLOT
    stx DIAG_Pointer+1
DiagSharedData_AddSlot:
    clc
    adc (DIAG_Pointer),y
    iny
    bne DiagSharedData_AddSlot
    ldx #$C8
    stx DIAG_Pointer+1
    ldx #$CA
DiagSharedData_AddLow:
    clc
    adc (DIAG_Pointer),y
    iny
    bne DiagSharedData_AddLow
    inc DIAG_Pointer+1
    cpx DIAG_Pointer+1
    bne DiagSharedData_AddLow
    cmp #$FF
    beq DiagHostRam

;; Prints "-FAIL" and ends the tests.
DiagFailed:
    jsr DiagPrintFail
    jmp DiagFinish

;; Prints "-PASS" for the shared data, then writes and reads back the card's banks 1-15 (card $0400-$3FFF) through
;; the window, with the byte's offset plus the bank plus the page; then sends the card on to its units.
DiagHostRam:
    jsr DiagPrintPass
    lda #<DiagTextHostRam
    jsr DiagPrint
    ldx #0
    stx DIAG_Pointer
    inx
DiagHostRam_Fill:
    stx DIAG_Bank
    jsr DiagSpin
    ldy DIAG_Bank
    sta (DIAG_BankSwitch),y
    ldy #0
    ldx #$C8
    stx DIAG_Pointer+1
    ldx #$CC
DiagHostRam_FillByte:
    tya
    clc
    adc DIAG_Bank
    adc DIAG_Pointer+1
    sta (DIAG_Pointer),y
    iny
    bne DiagHostRam_FillByte
    inc DIAG_Pointer+1
    cpx DIAG_Pointer+1
    bne DiagHostRam_FillByte
    ldx DIAG_Bank
    cpx #DIAG_BANKLAST
    beq DiagHostRam_Check
    inx
    jmp DiagHostRam_Fill
DiagHostRam_Check:
    ldx #0
    stx DIAG_Pointer
    inx
DiagHostRam_CheckBank:
    stx DIAG_Bank
    jsr DiagSpin
    ldy DIAG_Bank
    sta (DIAG_BankSwitch),y
    ldy #0
    ldx #$C8
    stx DIAG_Pointer+1
    ldx #$CC
DiagHostRam_CheckByte:
    tya
    clc
    adc DIAG_Bank
    adc DIAG_Pointer+1
    cmp (DIAG_Pointer),y
    beq DiagHostRam_Same
    jmp DiagFailed
DiagHostRam_Same:
    iny
    bne DiagHostRam_CheckByte
    inc DIAG_Pointer+1
    cpx DIAG_Pointer+1
    bne DiagHostRam_CheckByte
    ldx DIAG_Bank
    cpx #DIAG_BANKLAST
    beq DiagHostRam_Passed
    inx
    jmp DiagHostRam_CheckBank
DiagHostRam_Passed:
    jsr DiagPrintPass
    ldy #DIAG_BANKSHARED
    sta (DIAG_BankSwitch),y
    ; Calls the slot page's COPYC100, which must run there: it releases the $C800 space after each read of slot 1,
    ; and its next fetch from $Cn00 takes the space back.
    lda #>(DiagAskUnits-1)
    pha
    lda #<(DiagAskUnits-1)
    pha
    lda MSLOT
    pha
    lda #<(COPYC100-1)
    pha
    rts

;; Where COPYC100 returns: leaves a byte that varies for the block to test, lets the card find its units, and
;; reports them.
DiagAskUnits:
    lda DIAG_HORIZCNT
    sta DiagRandomBlock
    jsr DiagAwaitResult
    jmp DiagReportUnits

;; Ends the tests: puts the "&" back, stops the card and reads all the card's RAM over and over until E is pressed.
;; Then has the card restart, and restarts the host cold through its reset vector.
DiagFinish:
    lda #'&'|$80
    sta DIAG_SpinnerAt
    ldy #DIAG_BANKSHARED
    sta (DIAG_BankSwitch),y
    lda #DIAG_STOP
    sta DiagSignal
    jsr DIAG_CR
    lda #>DiagTextExit
    sta DIAG_Pointer+1
    lda #<DiagTextExit
    jsr DiagPrint
    jsr DIAG_CR
    lda KBDSTRB
DiagFinish_Read:
    ldx #0
    stx DIAG_Pointer
DiagFinish_Bank:
    stx DIAG_Bank
    ldy DIAG_Bank
    sta (DIAG_BankSwitch),y
    ldy #0
    ldx #$C8
    stx DIAG_Pointer+1
    ldx #$CC
DiagFinish_ReadBank:
    lda (DIAG_Pointer),y
    iny
    bne DiagFinish_ReadBank
    inc DIAG_Pointer+1
    cpx DIAG_Pointer+1
    bne DiagFinish_ReadBank
    ldx DIAG_Bank
    cpx #DIAG_BANKLAST
    beq DiagFinish_SlotPage
    inx
    jmp DiagFinish_Bank
DiagFinish_SlotPage:
    ldx MSLOT
    stx DIAG_Pointer+1
DiagFinish_ReadSlot:
    lda (DIAG_Pointer),y
    iny
    bne DiagFinish_ReadSlot
    ldx #$CC
    stx DIAG_Pointer+1
    ldx #$CF
DiagFinish_ReadExpansion:
    lda (DIAG_Pointer),y
    iny
    bne DiagFinish_ReadExpansion
    inc DIAG_Pointer+1
    cpx DIAG_Pointer+1
    bne DiagFinish_ReadExpansion
DiagFinish_ReadLast:
    lda (DIAG_Pointer),y
    iny
    cpy #<CLRROM
    bne DiagFinish_ReadLast
    lda KBD
    bpl DiagFinish_Read
    sta KBDSTRB
    cmp #'E'|$80
    beq DiagFinish_Exit
    cmp #'e'|$80
    beq DiagFinish_Exit
    bne DiagFinish_Read             ; always
DiagFinish_Exit:
    lda SOFTEV+1                    ; makes PWREDUP wrong, for a cold start
    sta PWREDUP
    lda DIAG_RESETVECTOR+1          ; returns to the reset handler's second byte, past its CLD
    pha
    lda DIAG_RESETVECTOR
    pha
    ldy #DIAG_BANKSHARED
    sta (DIAG_BankSwitch),y
    lda #DIAG_EXIT
    sta DiagSignal
DiagFinish_Wait:
    lda DiagSignal                  ; the card clears it as it restarts
    bne DiagFinish_Wait
    rts

;; Waits for the card's report of a test, testing the RAM under the card's I/O page meanwhile, and prints "-PASS",
;; or "-FAIL" and ends the tests. It leaves bank 0 latched.
DiagAwaitCard:
    jsr DiagSpin
    ldy #DIAG_BANKIO
    sta (DIAG_BankSwitch),y
    ldy #0
    lda DIAG_UnderIo
    tax
DiagAwaitCard_Fill:
    inx
    txa
    sta DIAG_UnderIo,y
    iny
    bne DiagAwaitCard_Fill
DiagAwaitCard_Check:
    inx
    txa
    cmp DIAG_UnderIo,y
    bne DiagAwaitCard_Bad
    iny
    bne DiagAwaitCard_Check
    jmp DiagAwaitCard_Status
DiagAwaitCard_Bad:
    lda #'E'|$80
    sta DIAG_ErrorMark
DiagAwaitCard_Status:
    ldy #DIAG_BANKSHARED
    sta (DIAG_BankSwitch),y
    lda DIAG_CardStatus
    beq DiagAwaitCard
    cmp #DIAG_PASSED
    beq DiagAwaitCard_Passed
    jsr DiagPrintFail
    jmp DiagFinish
DiagAwaitCard_Passed:
    sty DIAG_CardStatus             ; Y = 0: seen
    jmp DiagPrintPass

;; Turns the spinner: - \ | / and round again.
;; Out: Y = the new character's place in DiagSpinner, plus 1
;; Keeps: X
DiagSpin:
    lda DIAG_SpinnerAt
    ldy #4
DiagSpin_Find:
    cmp DiagSpinner,y
    beq DiagSpin_Next
    dey
    bne DiagSpin_Find
    iny                             ; not found: starts again at "-"
DiagSpin_Next:
    lda DiagSpinner-1,y
    sta DIAG_SpinnerAt
    rts

;; Prints "-PASS" and a new line.
DiagPrintPass:
    lda #>DiagTextPass
    sta DIAG_Pointer+1
    lda #<DiagTextPass
    jsr DiagPrint
    jsr DIAG_CR
    rts

;; Prints "-FAIL" and a new line.
DiagPrintFail:
    lda #>DiagTextFail
    sta DIAG_Pointer+1
    lda #<DiagTextFail
    jsr DiagPrint
    jsr DIAG_CR
    rts

;; Prints a text that ends with a zero byte, masking its letters with DIAG_CaseMask.
;; In:  A = the text's low byte, DIAG_Pointer+1 = its high byte
;; Out: A = 0, Y = the text's length
;; Keeps: X
DiagPrint:
    sta DIAG_Pointer
    ldy #0
DiagPrint_Next:
    lda (DIAG_Pointer),y
    bne DiagPrint_Character
    rts
DiagPrint_Character:
    cmp #$C0
    bcc DiagPrint_Show
    and DIAG_CaseMask
DiagPrint_Show:
    jsr DIAG_COUT
    iny
    bne DiagPrint_Next
    rts

;; Lets the card take its next step and waits for its answer: returns when the step is done, and on DIAG_STOP or a
;; read/write failure (which it prints) goes to DiagFinish. It leaves bank 0 latched.
DiagAwaitResult:
    ldy #DIAG_BANKSHARED
    sta (DIAG_BankSwitch),y
    lda #DIAG_GO
    sta DiagSignal
DiagAwaitResult_Wait:
    jsr DiagSpin
    lda DiagSignal
    cmp #DIAG_STOP
    bne DiagAwaitResult_NotStop
    jmp DiagFinish
DiagAwaitResult_NotStop:
    cmp #DIAG_RWFAILED
    bne DiagAwaitResult_NotFailed
    lda #<DiagTextRwFailure         ; DIAG_Pointer+1 is still DiagReportUnits's
    jsr DiagPrint
    lda DIAG_FailedBlock+1
    jsr DIAG_PRBYTE
    lda DIAG_FailedBlock
    jsr DIAG_PRBYTE
    lda #<DiagTextErr
    jsr DiagPrint
    lda MBERROR
    jsr DIAG_PRBYTE
    jsr DIAG_CR
    jmp DiagFinish
DiagAwaitResult_NotFailed:
    cmp #0
    bne DiagAwaitResult_Wait        ; still DIAG_GO
    rts

    .res 35                         ; unused

;; The texts of DiagStart's screen, in this page: DiagPrint takes their low bytes.
DiagTextTitle:
    .hiascii " 3.5", '"', " Disk Controller Test"
    .byte 0
DiagTextAuthors:
    .hiascii "    J.Arkley & T.Rudin"
    .byte 0
DiagTextCopyright:
    .hiascii "(C)Apple Computer Inc.,1991"
    .byte 0
DiagTextTests:
    .hiascii "Tests:"
    .byte 0
DiagTextSlot:
    .hiascii "Slot #"
    .byte 0
DiagTextPseudoRom:
    .hiascii "Card pseudoROM"
    .byte 0
DiagTextRomCrc:
    .hiascii "Card ROM CRC"
    .byte 0
DiagTextRomChecksum:
    .hiascii "Card ROM Checksum"
    .byte 0
DiagTextSwim:
    .hiascii "SWIM Regs."
    .byte 0
DiagTextCardRam:
    .hiascii "Card RAM"
    .byte 0
DiagTextShared:
    .hiascii "Host/Card shared data"
    .byte 0
DiagTextHostRam:
    .hiascii "Host RAM"
    .byte 0
DiagTextPass:
    .hiascii "-PASS"
    .byte 0
DiagTextFail:
    .hiascii "-FAIL"
    .byte 0
DiagTextExit:
    .hiascii "Press E to Exit"
    .byte 0
.assert >DiagTextTitle == >DiagTextExit

;; The spinner's characters: DiagSpin turns each into the one before it.
DiagSpinner:
    .hiascii "-/|", '\', "-"
    .byte 0                         ; $CFFF, which the host never reads here
.assert * == $D000
.logicalorg

; The card's page zero for the diagnostics, which TestDiagnostics copies in and checks: a pattern in $00-$01 and
; zeros. TestCardRam soon writes over $00-$05.
.logicalorg $0000
    .byte $55, $0F
    .res 254
.logicalorg
