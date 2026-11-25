; retrocore: style=strict
;; $FB60-$FBC0: the Apple II Monitor's 16-bit multiply and divide (<Arithmetic>), or in the other Monitors the
;; title, the soft entry check, the Control-S pause, the escape cursor keys and, on the IIe, the model byte and
;; the call into the internal firmware.

.if MONITOR = MONITOR_II

; The arithmetic's sizes.

;; The bits of a number: the passes of <Arithmetic::Multiply> and <Arithmetic::Divide>.
WORD_BITS = 16

;; The bytes of <Arithmetic::Multiply>'s 32-bit result: <Arithmetic::ExtensionHigh>, <Arithmetic::Extension>,
;; <Arithmetic::AccumulatorHigh> and <Arithmetic::Accumulator>.
PRODUCT_BYTES = 4

;; The Apple II Monitor's 16-bit multiply and divide routines, on
;; <Arithmetic::Accumulator>/<Arithmetic::AccumulatorHigh>, <Arithmetic::Operand>/<Arithmetic::OperandHigh> and
;; <Arithmetic::Extension>/<Arithmetic::ExtensionHigh>.
;;
;; The signed versions make both numbers positive with <Arithmetic::MakePositive>, which counts the numbers it negates
;; in <Arithmetic::SignCount>; the caller applies the sign. The Autostart Monitor dropped them for the title, the soft
;; entry check and the escape cursor keys.
.scope Arithmetic

; Page zero, under the names this scope gives it.

;; The count of operands <MakePositive> negated: bit 0 is set when the result is negative. The same byte is
;; <OperandLength>.
;; Also: SIGN (A2RM78, A2RM79)
SignCount = OperandLength

;; The low byte of the 16-bit accumulator: the multiplier or dividend on entry, the product's low half or the quotient
;; on return.
;; Also: ACL (A2RM78, A2RM79)
Accumulator = $50

;; The high byte of <Accumulator>.
;; Also: ACH (A2RM79)
AccumulatorHigh = $51

;; The low byte of the extension: the product's high half, or the remainder.
;; Also: XTNDL (A2RM78, A2RM79)
Extension = $52

;; The high byte of <Extension>.
;; Also: XTNDH (A2RM79)
ExtensionHigh = $53

;; The low byte of the multiplicand or divisor.
;; Also: AUXL (A2RM78, A2RM79)
Operand = $54

;; The high byte of <Operand>.
;; Also: AUXH (A2RM79)
OperandHigh = $55

;; Multiplies two signed 16-bit numbers, <Arithmetic::Operand>/<Arithmetic::OperandHigh> times
;; <Arithmetic::Accumulator>/<Arithmetic::AccumulatorHigh>.
;;
;; At $FB60. It makes both numbers positive (<Arithmetic::MakePositive>), which leaves the product's sign in
;; bit 0 of <Arithmetic::SignCount> for the caller to apply, then multiplies them (<Arithmetic::Multiply>).
;; In: Accumulator/AccumulatorHigh = a number, Operand/OperandHigh = the other,
;;   Extension/ExtensionHigh = a number added to the product (usually 0)
;; Out: Accumulator/AccumulatorHigh = the product's low 16 bits, Extension/ExtensionHigh = its high 16 bits,
;;   SignCount = bit 0 set for a negative product
;; Uses: A, X, Y
;; See: <Arithmetic::SignedDivide>
;; Also: MULPM (A2RM78, A2RM79)
.proc SignedMultiply
.assert * = $FB60, "Arithmetic::SignedMultiply must stay at $FB60."
    jsr MakePositive
    ; Falls into Multiply.
.endproc

;; Multiplies two unsigned 16-bit numbers, <Arithmetic::Operand>/<Arithmetic::OperandHigh> times
;; <Arithmetic::Accumulator>/<Arithmetic::AccumulatorHigh>, and adds
;; <Arithmetic::Extension>/<Arithmetic::ExtensionHigh>.
;;
;; At $FB63. Each of its 16 passes adds the multiplicand to the extension when the multiplier's low bit is set,
;; then shifts the 32 bits of extension and multiplier right one, the add's carry coming in at the top.
;; In: Accumulator/AccumulatorHigh = a number, Operand/OperandHigh = the other,
;;   Extension/ExtensionHigh = a number added to the product (usually 0)
;; Out: Accumulator/AccumulatorHigh = the product's low 16 bits, Extension/ExtensionHigh = its high 16 bits,
;;   X = $FF, Y = 0
;; Uses: A
;; Also: MUL (A2RM78, A2RM79)
.proc Multiply
.assert * = $FB63, "Arithmetic::Multiply must stay at $FB63."
    ldy #WORD_BITS

;; One pass: adds the multiplicand when the multiplier's low bit is set.
;; Also: MUL2 (A2RM78, A2RM79)
NextBit:
    lda Accumulator
    lsr a
    bcc Shift
    clc

    ; X = -2, then -1: the low byte, then the high byte.
    ldx #$100 - 2

;; Adds a byte of <Operand>/<OperandHigh> to <Extension>/<ExtensionHigh>; in page zero <Extension> + 2,X wraps
;; round to <Extension>.
;; Also: MUL3 (A2RM78, A2RM79)
AddByte:
    lda Extension + 2,x
    adc Operand + 2,x
    sta Extension + 2,x
    inx
    bne AddByte

;; Shifts the 32-bit result right, the carry coming in at the top.
;; Also: MUL4 (A2RM78, A2RM79)
Shift:
    ldx #PRODUCT_BYTES - 1

;; Shifts a byte: <ExtensionHigh>, <Extension>, <AccumulatorHigh>, then <Accumulator>.
;; Also: MUL5 (A2RM78, A2RM79)
ShiftByte:
    ror Accumulator,x
    dex
    bpl ShiftByte
    dey
    bne NextBit
    rts
.endproc

;; Divides two signed 16-bit numbers, <Arithmetic::Accumulator>/<Arithmetic::AccumulatorHigh> by
;; <Arithmetic::Operand>/<Arithmetic::OperandHigh>.
;;
;; At $FB81. It makes both numbers positive (<Arithmetic::MakePositive>), which leaves the quotient's sign in
;; bit 0 of <Arithmetic::SignCount> for the caller to apply, then divides them (<Arithmetic::Divide>).
;; In: Accumulator/AccumulatorHigh = the dividend, Operand/OperandHigh = the divisor, Extension/ExtensionHigh = 0
;; Out: Accumulator/AccumulatorHigh = the quotient, Extension/ExtensionHigh = the remainder,
;;   SignCount = bit 0 set for a negative quotient
;; Uses: A, X, Y
;; See: <Arithmetic::SignedMultiply>
;; Also: DIVPM (A2RM78, A2RM79)
.proc SignedDivide
.assert * = $FB81, "Arithmetic::SignedDivide must stay at $FB81."
    jsr MakePositive
    ; Falls into Divide.
.endproc

;; Divides the unsigned 32-bit number in <Arithmetic::Extension>/<Arithmetic::ExtensionHigh> (high) and
;; <Arithmetic::Accumulator>/<Arithmetic::AccumulatorHigh> (low) by <Arithmetic::Operand>/<Arithmetic::OperandHigh>.
;;
;; At $FB84. Each of its 16 passes shifts the 32 bits left one and, when the top half is at least the divisor,
;; subtracts it there and sets the quotient bit at the bottom. The quotient fits in 16 bits when the high half
;; starts below the divisor, as it does when it is 0.
;; In: Accumulator/AccumulatorHigh = the dividend's low half, Extension/ExtensionHigh = its high half (usually 0),
;;   Operand/OperandHigh = the divisor
;; Out: Accumulator/AccumulatorHigh = the quotient, Extension/ExtensionHigh = the remainder, Y = 0
;; Uses: A, X
;; Also: DIV (A2RM78)
.proc Divide
.assert * = $FB84, "Arithmetic::Divide must stay at $FB84."
    ldy #WORD_BITS

;; One pass: shifts the 32 bits left, then subtracts the divisor from the top half if it fits.
;; Also: DIV2 (A2RM78, A2RM79)
NextBit:
    asl Accumulator
    rol AccumulatorHigh
    rol Extension
    rol ExtensionHigh

    ; The top half minus the divisor, kept in X and A until it is known to fit.
    sec
    lda Extension
    sbc Operand
    tax
    lda ExtensionHigh
    sbc OperandHigh
    bcc Count
    stx Extension
    sta ExtensionHigh
    inc Accumulator

;; Counts the passes; when the divisor did not fit, the quotient bit stays 0.
;; Also: DIV3 (A2RM78, A2RM79)
Count:
    dey
    bne NextBit
    rts
.endproc

;; Makes <Arithmetic::Operand>/<Arithmetic::OperandHigh> and <Arithmetic::Accumulator>/<Arithmetic::AccumulatorHigh>
;; positive for <Arithmetic::SignedMultiply> and <Arithmetic::SignedDivide>, counting the numbers it negates in
;; <Arithmetic::SignCount>.
;;
;; <Arithmetic::MakePositive::Number> negates the 16-bit number at page zero X when it is negative, and
;; <Arithmetic::MakePositive::Negate> negates it whatever its sign; both need Y = 0. Bit 0 of the count ends set
;; when exactly one number was negative.
;; Out: SignCount = the count of negated numbers, Y = 0
;; Uses: A, X
;; Also: MD1 (A2RM78, A2RM79)
.proc MakePositive
    ldy #0
    sty SignCount
    ldx #Operand
    jsr Number
    ldx #Accumulator

;; Negates the number at X, X+1 in page zero if it is negative; needs Y = 0.
;; Also: MD2 (A2RM78, A2RM79)
Number:
    lda LOC1,x
    bpl Done
    ; The IIe's ModelId is at this byte's address, and programs read this SEC's $38 there.
    sec

;; Negates the number at X, X+1 (with Y = 0 and the carry set): 0 minus it, low byte first, and counts it in
;; <Arithmetic::SignCount>.
;; Also: MD3 (A2RM78)
Negate:
    tya
    sbc SlotPointer,x
    sta SlotPointer,x
    tya
    sbc LOC1,x
    sta LOC1,x
    inc SignCount

;; Returns.
;; Also: MDRTS (A2RM78)
Done:
    rts
.endproc

.endscope
.else

; The IIe's model bytes.

;; The model byte at <ModelId> on the IIe.
MODEL_ID_IIE = $06

;; The byte at $FBC0 on the original IIe, which with <ModelId> tells it from the Enhanced IIe.
MODEL_ID_ORIGINAL = $EA

;; The byte at $FBC0 on the Enhanced IIe, which with <ModelId> tells it from the original IIe.
MODEL_ID_ENHANCED = $E0

; The title.
.if ENHANCED

;; The length of the title <Startup::ShowTitle> shows: "Apple //e" (<Startup::TitleEnhanced>) on the Enhanced IIe.
TITLE_LENGTH = 9
.else

;; The length of the title <Startup::ShowTitle> shows: "Apple ][" or "APPLE ][" (<Startup::Title>).
TITLE_LENGTH = 8
.endif

;; The screen column of the title's first character.
TITLE_COLUMN = 15

; Startup: showing the title.
.scope Startup continued

;; Clears the screen and shows the model's title at the top center: "Apple ][" on the original IIe, "Apple //e" on
;; the Enhanced IIe.
;;
;; At $FB60. The Autostart Monitor's <Startup::PowerUp> shows "APPLE ][" this way. The Apple II Monitor has no
;; title.
;; Out: Y = 0
;; Also: APPLEII (A2RM79, IIEROM82, IIETRM85)
.proc ShowTitle
.assert * = $FB60, "Startup::ShowTitle must stay at $FB60."
    jsr Home
    ldy #TITLE_LENGTH

;; Copies a character of the title to the top line, from the last.
;; Also: STITLE (A2RM79, IIEROM82, IIETRM85)
Loop:
.if ENHANCED
    lda Startup::TitleEnhanced - 1,y
.else
    lda Title - 1,y
.endif
    sta TextPage1 + TITLE_COLUMN - 1,y
    dey
    bne Loop
    rts
.endproc

.endscope

;; Makes the soft entry vector valid: <SoftEntryCheck> = <SoftEntryVector>'s high byte exclusive-ored with $A5. Call it
;; after changing it.
;;
;; At $FB6F.
;; Out: SoftEntryCheck = the check byte for <SoftEntryVector>'s current high byte
;; Uses: A
;; Keeps: X, Y, carry
;; Also: SETPWRC (A2RM79, IIEROM82, IIETRM85)
.proc ValidateSoftEntry
.assert * = $FB6F, "ValidateSoftEntry must stay at $FB6F."
    lda SoftEntryVector+1
    eor #SOFT_ENTRY_CHECK
    sta SoftEntryCheck
    rts
.endproc

;; Screen output with the Control-S pause: when A is a carriage return and the user has typed Control-S, waits
;; for another key before printing. Then prints A (<ScreenOutDirect>).
;;
;; At $FB78.
;; In: A = the character
;; Uses: A, Y
;; Also: VIDWAIT (A2RM79, IIEROM82, IIETRM85)
.proc ScreenOutPausing
.assert * = $FB78, "ScreenOutPausing must stay at $FB78."

    ; Only a carriage return with Control-S waiting pauses.
    cmp #KEY_RETURN
    bne Print
    ldy Keyboard
    bpl Print
    cpy #KEY_CONTROL_S
    bne Print
    bit KeyboardStrobe

;; Waits for a key and clears the strobe, except for Control-C, which stays in the keyboard latch for the program
;; to see. Then prints A. At $FB88.
;; Also: KBDWAIT (A2RM79, IIEROM82, IIETRM85)
WaitForKey:
.assert * = $FB88, "WaitForKey must stay at $FB88."
    ldy Keyboard
    bpl WaitForKey
    cpy #KEY_CONTROL_C
    beq Print
    bit KeyboardStrobe

;; Prints the character.
;; Also: NOWAIT (A2RM79, IIEROM82, IIETRM85)
Print:
    jmp ScreenOutDirect
.endproc

; Escape: the cursor keys I, J, K and M, which keep escape mode on.
.scope Escape continued

;; Performs the character in A as an escape command (<Escape::Command>), with the carry set as it needs.
;;
;; Every key but the cursor keys ends escape mode this way.
;; In: A = the command character
;; Also: ESCOLD (A2RM79, IIEROM82, IIETRM85)
.proc Perform
    sec
    jmp Escape::Command
.endproc

;; Performs a cursor key's command, reads the next key, and goes on in escape mode (<Escape::NextKey>).
;;
;; The keys I, J, K and M become the commands D, B, A and C (<Escape::CursorKeyCommands>). The IIe reads the next key
;; with `Escape::ReadEscapeKey`, the Autostart Monitor with <ReadKey>. The Apple II Monitor has no escape keys I, J, K
;; and M: its <Escape::Sequence> hands every key to <Escape::Command>.
;; In: A = I, J, K or M
;; Also: ESCNOW (A2RM79, IIETRM85)
.proc CursorKey
    tay
    lda CursorKeyCommands - 'I',y
    jsr Perform
.if MONITOR = MONITOR_IIE

    ; The next key; then falls into NextKey.
    jsr Escape::ReadEscapeKey
.else

    ; The next key; then falls into NextKey.
    jsr ReadKey
.endif
.endproc

;; Handles a key in escape mode: I, J, K and M move the cursor and keep escape mode on (<Escape::CursorKey>); any
;; other key is performed once (<Escape::Perform>) and ends it.
;; In: A = the key
;; Also: ESCNEW (A2RM79, IIEROM82, IIETRM85)
.proc NextKey
    cmp #'N'
    bcs Perform
    cmp #'I'
    bcc Perform
    cmp #'L'
    beq Perform
    bne CursorKey
.endproc

.endscope

;; The model identification byte: $06 means an Apple IIe, and the byte at $FBC0 tells which.
;;
;; At $FBB3. Programs read the same address on the Apple II: the Autostart Monitor has $EA here, followed by
;; unused $EA bytes up to $FBC0, and the Apple II Monitor $38, a SEC in `Arithmetic::MakePositive`.
;; Also: VERSION (IIEROM82, IIETRM85), F8VERSION (IIEROM82, IIETRM85)
ModelId:
.assert * = $FBB3, "ModelId must stay at $FBB3."
.if MONITOR = MONITOR_AUTOSTART
    .byte $EA
    ; Unused.
    .res 13, $EA
.else
    .byte MODEL_ID_IIE

;; Calls the internal firmware: saves whether slot ROM or internal ROM was selected at $C100-$CFFF, switches
;; internal ROM in and jumps to the firmware's dispatcher at <DispatchFunction>, which performs the function in Y and
;; switches back.
;;
;; At $FBB4. The original IIe also saves the interrupt state and disables interrupts first.
;; In: Y = the function number; other registers as the function needs
;; Also: GOTOCX (IIEROM82, IIETRM85)
.proc CallFirmware
.assert * = $FBB4, "CallFirmware must stay at $FBB4."
.if .not ENHANCED
    php
    sei
.endif

    ; InternalCxRomState's bit 7 into the pushed status, then internal ROM.
    bit InternalCxRomState
    php
    sta InternalCxRomOn
    jmp DispatchFunction
.if ENHANCED

    ; Two unused bytes, then the byte at $FBC0 that tells the Enhanced IIe from the original.
    .byte $00, $00
    .byte MODEL_ID_ENHANCED
.else

    ; The byte at $FBC0 that tells the original IIe from the Enhanced.
    .byte MODEL_ID_ORIGINAL
.endif
.endproc
.endif
.endif
