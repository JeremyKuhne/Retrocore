; retrocore: style=strict
;; Programmer's Aid #1: RAM Test ($D5BC-$D6DC)
;;
;; Steve Wozniak's memory test (1977), run from the Monitor: D5BCG sets the Monitor's Control-Y up
;; (<RamTest::SetUp>), and then `start.pages` Control-Y tests the given number of pages from the start page, which the
;; Monitor leaves in A1 and A2. With $00 and then with $FF, it fills the block and checks it, then gallops: each cell in
;; turn holds the inverse of the data while every cell a power-of-2 distance from it is written and checked, which
;; finds cells and address lines that disturb one another. It beeps at the end, whatever it found.
;;
;; An error in the fill prints `address expected bad ERR`, then each failing chip as its row and column, `r-c`: the
;; row is D if the block starts below $5000 and E otherwise, the column the socket of the data bit that failed. An
;; error in the gallop prints the cell, the expected and bad data, the neighbor's address and the gallop data, then
;; ERR, where RAMTESTFIX is 1; the chip jumps to $02CB after the expected data instead. The test counts on the output
;; hook keeping Y, as the screen's does.
;;
;; The listing's names are those of Apple's listing in the Programmer's Aid #1 manual (1978,
;; https://archive.org/details/programmers-aid-1), which is of an earlier version: this one reports the failing chips
;; (<RamTest::PrintFailingChips>), and the chip jumps to $02CB at $D670 where the listing prints a byte, which
;; RAMTESTFIX puts back. Part of ProgrammersAid.asm.

.scope RamTest

; Page zero: SWEET16's register bytes, which the test borrows.

;; The test data, $00 or $FF.
;; Also: DATA (PA1)
TestData = Sweet16Registers

;; The inverse of <TestData>.
;; Also: NDATA (PA1)
InverseData = Sweet16Registers + 1

;; The gallop's data, which <TestNeighbor> writes to the neighbor.
;; Also: TESTD (PA1)
GallopData = Sweet16Registers + 2

;; The address checked (2 bytes), in the fill's check.
;; Also: R3L (PA1)
CheckAddress = Sweet16Registers + 3 * SWEET16_REGISTER_SIZE

;; The high byte of <CheckAddress>.
;; Also: R3H (PA1)
CheckAddressHigh = CheckAddress + 1

;; The address written (2 bytes): the fill's, then the gallop's neighbor.
;; Also: R4L (PA1)
WriteAddress = Sweet16Registers + 4 * SWEET16_REGISTER_SIZE

;; The high byte of <WriteAddress>.
;; Also: R4H (PA1)
WriteAddressHigh = WriteAddress + 1

;; The gallop's test cell (2 bytes).
;; Also: R5L (PA1)
TestCell = Sweet16Registers + 5 * SWEET16_REGISTER_SIZE

;; The high byte of <TestCell>.
;; Also: R5H (PA1)
TestCellHigh = TestCell + 1

;; The gallop's bit mask (2 bytes), $0001 up to 2^n: the bit that makes the neighbor's address from the test cell's.
;; Also: R6L (PA1)
GallopMask = Sweet16Registers + 6 * SWEET16_REGISTER_SIZE

;; The high byte of <GallopMask>.
;; Also: R6H (PA1)
GallopMaskHigh = GallopMask + 1

;; The data bits that failed, which <PrintFailingChips> reports.
;; Also: BADBITS (UNKN)
BadBits = Sweet16Registers + 7 * SWEET16_REGISTER_SIZE

;; Where <PrintFailingChips> keeps Y.
;; Also: YSAVE (UNKN)
KeptY = BadBits + 1

;; The first page of the block: the start the Monitor leaves in A1's high byte.
FirstPage = Address1High

;; The number of pages: the count the Monitor leaves in A2's low byte.
PageCount = Address2

;; D5BCG: points the Monitor's Control-Y command at <Command>.
;; Keeps: X
;; Also: SETUP (PA1)
.proc SetUp
.assert * = $D5BC, "RamTest::SetUp must stay at $D5BC, where the manual's D5BCG enters it."
    lda #<Command
    ldy #>Command
    jmp SetControlY
.endproc

;; The Control-Y command: tests <PageCount> pages from page <FirstPage> with $00, then $FF, and beeps.
;; In: FirstPage = the first page, PageCount = the number of pages
;; Also: RAMTST (PA1)
.proc Command
    lda #$00
    jsr TestBlock
    lda #$FF
    jsr TestBlock
    jmp Beep
.endproc

;; Tests the block with the data in A: fills it and checks it, then gallops.
;; In: A = the data, FirstPage = the first page, PageCount = the number of pages
;; Out: X = 0, Y = 0
;; Also: TEST (PA1)
.proc TestBlock
    sta TestData
    eor #$FF
    sta InverseData
    lda FirstPage
    sta CheckAddressHigh
    sta WriteAddressHigh
    sta TestCellHigh
    ldy #0
    sty CheckAddress
    sty WriteAddress
    sty TestCell
    ldx PageCount
    lda TestData

;; Fills the block.
;; Also: TEST01 (PA1)
Fill:
    sta (WriteAddress),y
    iny
    bne Fill
    inc WriteAddressHigh
    dex
    bne Fill
    ldx PageCount

;; Checks the fill; a byte that differs prints `address expected bad ERR` and the failing chips.
;; Also: TEST02 (PA1)
Check:
    lda (CheckAddress),y
    cmp TestData
    beq NextCheck
    pha
    lda CheckAddressHigh
    jsr PrintHexByte
    tya
    jsr PrintByteSpace
    lda TestData
    jsr PrintByteSpace
    pla
    jsr PrintFailingChips

;; Also: TEST03 (PA1)
NextCheck:
    iny
    bne Check
    inc CheckAddressHigh
    dex
    bne Check
    ldx PageCount

;; Gallops on the next test cell: it gets the inverse while each neighbor is written.
;; Also: TEST04 (PA1)
NextTestCell:
    lda InverseData
    sta (TestCell),y
    sty GallopMaskHigh
    sty GallopMask
    inc GallopMask

;; Writes the next neighbor with the inverse, then the data, checking the test cell each time.
;; Also: TEST05 (PA1)
NextNeighbor:
    lda InverseData
    jsr TestNeighbor
    lda TestData
    jsr TestNeighbor

    ; The next neighbor, twice as far, while it is inside the block.
    asl GallopMask
    rol GallopMaskHigh
    lda GallopMaskHigh
    cmp PageCount
    bcc NextNeighbor

    ; The test cell gets the data back; then the next cell.
    lda TestData
    sta (TestCell),y
    inc TestCell
    bne NextTestCell
    inc TestCellHigh
    dex
    bne NextTestCell

;; Returns; <TestNeighbor> branches here too. Apple's listing calls it RTS1, which here would clash with
;; <HiResGraphics::StepHorizontal::Done>'s.
Done:
    rts
.endproc

;; Writes the gallop data to the test cell's neighbor, and checks that the test cell kept its data, the inverse.
;;
;; A test cell that changed gets the inverse back and prints the cell and the expected data; then, where RAMTESTFIX is
;; 1, the bad data, the neighbor's address and the gallop data, then ERR. The chip jumps to $02CB instead.
;; In: A = the gallop data, TestCell = the test cell, GallopMask = the bit that makes the neighbor, Y = 0
;; Also: TEST6 (PA1)
.proc TestNeighbor
    sta GallopData
    lda TestCell
    eor GallopMask
    sta WriteAddress
    lda TestCellHigh
    eor GallopMaskHigh
    sta WriteAddressHigh
    lda GallopData
    sta (WriteAddress),y
    lda (TestCell),y
    cmp InverseData
    beq TestBlock::Done

    ; The test cell changed.
    pha
    lda TestCellHigh
    jsr PrintHexByte
    lda TestCell
    jsr PrintByteSpace
    lda InverseData
    sta (TestCell),y
    jsr PrintByteSpace
    pla
.if RAMTESTFIX
    ; The bad data, as the manual's listing prints it.
    jsr PrintByteSpace
.else
    ; The chip jumps into the Monitor's input buffer here, where the listing prints the bad data; what it meant to
    ; find there is not known.
    jmp $02CB
.endif
    lda WriteAddressHigh
    jsr PrintHexByte
    lda WriteAddress
    jsr PrintByteSpace
    lda GallopData
    ; Falls into PrintByteAndError.
.endproc

;; Prints a byte and a space, then ERR, beeping, and a return.
;; In: A = the byte
;; Entry:
;;   EndLine = prints a return
;; Also: PRBYCR (PA1)
.proc PrintByteAndError
    jsr PrintByteSpace
    jsr PrintError

;; Prints a return.
EndLine:
    lda #KEY_RETURN
    jmp CharacterOut
.endproc

;; Prints a byte in hexadecimal and a space.
;; In: A = the byte
;; Also: PRBYSP (PA1)
.proc PrintByteSpace
    jsr PrintHexByte
    lda #' '
    jmp CharacterOut
.endproc

;; Prints the bad data, ERR, and then each failing chip as ` r-c`: its row, D if the block starts below $5000 and E
;; otherwise, and the socket of the data bit that differs; then a return.
;; In: A = the bad data, TestData = the data expected, FirstPage = the block's first page
;; Also: ERRBITS (UNKN)
.proc PrintFailingChips

;; The first page of the chips in row E; the pages below are row D's.
ROW_E_PAGE = $50

;; The last index into <SocketDigits>, bit 0's; bit n's is 7 - n.
LAST_BIT = 7

    sty KeptY
    sta BadBits
    jsr PrintByteSpace
    jsr PrintError
    lda TestData
    eor BadBits
    sta BadBits
    ldy #LAST_BIT

;; Takes the bits from bit 0 up, Y counting down to its digit in <SocketDigits>.
NextBit:
    lsr BadBits
    bcc SkipBit
    lda #' '
    jsr CharacterOut

    ; "D", or "E" from page $50: the compare's carry adds 1.
    lda FirstPage
    cmp #ROW_E_PAGE
    lda #'D'
    adc #0
    jsr CharacterOut
    lda #'-'
    jsr CharacterOut
    tya
    bne PrintColumn
    ; Bit 7's socket is 10.
    lda #'1'
    jsr CharacterOut

PrintColumn:
    lda SocketDigits,y
    jsr CharacterOut

SkipBit:
    dey
    bpl NextBit
    ldy KeptY
    jmp PrintByteAndError::EndLine
.endproc

;; The last digit of each data bit's socket, from bit 7 (10, printed with its 1) to bit 0 (3); the last two are never
;; read.
;; Also: SOCKETS (UNKN)
SocketDigits:
    .byte "0987654321"

.endscope
