; retrocore: style=strict
;; Integer BASIC: decimal output, finding lines, `NEW` and `CLR` ($E51B-$E5CB)
;;
;; <PrintDecimal>, which prints line numbers and values in decimal; the search for a line by its number
;; (<FindLine>), which `GOTO`, `GOSUB`, `LIST`, `DEL` and line entry use; and `NEW` and `CLR`, which discard the
;; program and the variables.
;;
;; Part of IntegerBasic.asm; it follows Tokenizer.asm, at $E51B.

;; Prints a 16-bit number in decimal, as five places with the leading zeros printed as <LeadingZero> says.
;;
;; At $E51B, where Programmer's Aid calls it. The number is unsigned (0 to 65535). Each place is found by subtracting
;; its power of ten as many times as it goes. While `AUTO` mode is on, each character printed is also stored in
;; <InputBuffer> at Y, so the line number the `AUTO` prompt shows becomes the start of the line typed.
;; In: A = the high byte, X = the low byte, LeadingZero = 0 to drop leading zeros, or the character to print for each
;;   ($A0, a blank), Y = where in <InputBuffer> the characters go, in `AUTO` mode
;; Out: X = $FF, Y = past the characters stored, in `AUTO` mode
;; Uses: A, DecimalNumber, DigitCharacter, DigitPlace
;; See: <LeadingZero>, <WarmStart>
;; Also: PRDEC (IBSM)
.proc PrintDecimal
.assert * = $E51B, "PrintDecimal must stay at $E51B, where Programmer's Aid calls it."
    sta DecimalNumber+1
    stx DecimalNumber

    ; From the ten thousands down. Bit 7 of DigitPlace stays clear until a digit other than 0 is printed.
    ldx #DECIMAL_PLACES - 1
    stx DigitPlace
StartPlace:
    lda #'0'
    sta DigitCharacter

    ; Subtracts the place's power of ten while it goes, counting the digit up.
Subtract:
    lda DecimalNumber
    cmp PowersOfTenLow,x
    lda DecimalNumber+1
    sbc PowersOfTenHigh,x
    bcc PlaceDone
    sta DecimalNumber+1
    lda DecimalNumber
    sbc PowersOfTenLow,x
    sta DecimalNumber
    inc DigitCharacter
    bne Subtract

PlaceDone:
    ; The units are always printed.
    lda DigitCharacter
    inx
    dex
    beq PrintCharacter

    ; A digit that is not 0 sets bit 7 of DigitPlace: from here on, every digit is printed.
    cmp #'0'
    beq CheckLeading
    sta DigitPlace
CheckLeading:
    bit DigitPlace
    bmi PrintCharacter

    ; A leading zero: printed as LeadingZero, or not at all for 0.
    lda LeadingZero
    beq NextPlace

;; Prints the character in A, and copies it into <InputBuffer> at Y in `AUTO` mode.
;; Also: PRDEC5 (IBSM)
PrintCharacter:
    jsr CharacterOut
    bit AutoNumbering
    bpl NextPlace
    sta InputBuffer,y
    iny

;; Goes on to the next place, or returns after the units.
;; Also: PRDEC6 (IBSM)
NextPlace:
    dex
    bpl StartPlace
    rts

;; The number of places printed.
DECIMAL_PLACES = 5

;; The low bytes of the powers of ten it subtracts, by place: 1, 10, 100, 1000 and 10000.
;; Also: NUMLOW (IBSM)
PowersOfTenLow:
    .byte <1, <10, <100, <1000, <10000

;; The high bytes of the powers of ten, as <PowersOfTenLow>.
;; Also: NUMHI (IBSM)
PowersOfTenHigh:
    .byte >1, >10, >100, >1000, >10000
.endproc

;; Finds the first line whose number is at least <Accumulator>, searching from the start of the program.
;;
;; The two comparisons of a line's number use the carry from the one before, so each is off by one in the way that
;; matters: the first returns with carry set for a number above Accumulator, the second with carry clear for
;; Accumulator itself.
;; In: Accumulator = the line number
;; Out: Pointer2 = the line found, or <HighMemory> if there is none, carry = clear if its number is Accumulator, set
;;   if not, Pointer3 = the line after Pointer2 when the number is Accumulator, otherwise Pointer2
;; Uses: A, Y
;; Keeps: X, Accumulator
;; Entry:
;;   PopFromPointer3 = takes an entry off the noun stack (INX), then searches from Pointer3
;;   FromPointer3 = searches from Pointer3
;; Also: FINDLINE (UNKN)
.proc FindLine
    lda ProgramStart
    sta Pointer3
    lda ProgramStart+1
    sta Pointer3+1

;; Takes an entry off the noun stack, then searches from the line at <Pointer3>.
;; In: Accumulator = the line number, Pointer3 = the line to start at
;; Out: X = one entry higher, the rest as <FindLine>'s
;; Also: FINDP3POP (UNKN)
PopFromPointer3:
    inx

;; Searches from the line at <Pointer3>: the next line to look at.
;; In: Accumulator = the line number, Pointer3 = the line to start at
;; Also: FINDFROMP3 (UNKN)
FromPointer3:
    lda Pointer3+1
    sta Pointer2+1
    lda Pointer3
    sta Pointer2

    ; Past the last line: carry set.
    cmp HighMemory
    lda Pointer2+1
    sbc HighMemory+1
    bcs Done

    ; Carry is clear: the line's number - Accumulator - 1. A number above Accumulator returns, carry set.
    ldy #ProgramLine::NUMBER
    lda (Pointer2),y
    sbc Accumulator
    iny
    lda (Pointer2),y
    sbc Accumulator+1
    bcs Done

    ; Steps Pointer3 to the next line.
    ldy #ProgramLine::LENGTH
    lda Pointer3
    adc (Pointer2),y
    sta Pointer3
    bcc CompareNumber
    inc Pointer3+1
    clc
CompareNumber:
    ; Carry is clear: Accumulator - the number - 1. Below Accumulator, keeps looking; equal, returns with carry
    ; clear.
    iny
    lda Accumulator
    sbc (Pointer2),y
    iny
    lda Accumulator+1
    sbc (Pointer2),y
    bcs FromPointer3
Done:
    rts
.endproc

; Statements: NEW and CLR.
.scope Statements continued

;; `NEW` (token $0B): leaves `AUTO` mode and discards the program, then the variables (falls into <Statements::Clr>).
;; Uses: A
;; Keeps: X, Y
;; Also: NEW (IBSM)
.proc New
    lsr AutoNumbering
    lda HighMemory
    sta ProgramStart
    lda HighMemory+1
    sta ProgramStart+1
    ; Falls into Clr.
.endproc

;; `CLR` (token $0C): discards the variables, and the `FOR` and `GOSUB` stacks.
;;
;; It also clears <SyntaxPage>, whose low byte must be 0, and $1D (<Clr::Cleared>).
;; Uses: A
;; Keeps: X, Y
;; See: <Statements::New>, <Statements::Run>
;; Also: CLR (IBSM)
.proc Clr

;; A page-zero byte that `CLR` clears and no other code in Integer BASIC reads.
Cleared = $1D

    lda LowMemory
    sta VariablesEnd
    lda LowMemory+1
    sta VariablesEnd+1
    lda #0
    sta ForIndex
    sta GoSubIndex
    sta SyntaxPage
    lda #0
    sta Cleared
    rts
.endproc

.endscope
