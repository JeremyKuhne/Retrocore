; retrocore: style=strict
; COMMODORE BASIC: CLOCK-STRING ASSIGNMENT

.include "../../Microsoft6502Basic/MsBasic.Families.asm"
.include "Commodore.Switches.asm"

;; The number of digits a `TI$` assignment takes: hours, minutes and seconds, two digits each.
CLOCK_STRING_LENGTH = 6

;; Emits the `TI$` assignment, the PET's start of <AssignString>: every string assignment comes here first, and one to
;; any other variable goes on to <StoreString>.
;; Parameters: longLengthError = 1 to reach <IllegalQuantityError> for a wrong length by a jump, which the right length
;;   branches over (BASIC 1), 0 to branch to the digit check's jump
.macro TimeStringAssignment longLengthError
    .assert longLengthError = 0 || longLengthError = 1, "longLengthError must be 0 or 1."

    ;; Assigns a string to `TI$`, setting the clock, or passes any other variable on to <StoreString>.
    ;;
    ;; The reserved variables' values are in ROM, in <ZeroValue>'s page, so a destination there is `TI$` (the only
    ;; reserved string variable). The string must be six characters, `HHMMSS`; it is converted to 60 Hz ticks
    ;; (sixtieths of a second), and the low three bytes of the integer are stored in <JiffyClock>
    ;; with interrupts off, so the clock interrupt never sees half of the new value (with <STANDARD_KERNAL>, the
    ;; VIC-20's, by the kernal's SETTIM). The value is not checked against
    ;; 24 hours: `TI$ = "999999"` sets the clock past a day. Nor are the digits checked as digits: <ClassifyCharacter>
    ;; is the reader's entry after its colon test, so it takes every byte from `0` up for a digit, with the value of
    ;; its distance from `0` (`A` counts 17), and rejects only the bytes below `0`. A space it skips by going on to
    ;; <GetNextCharacter>, which moves <TextPointer> on and reads through it (past the statement's end, for `LET`);
    ;; that byte takes the digit's place with the reader's full test, so a byte from `:` up is rejected there and
    ;; another space is skipped too.
    ;; In: AssignedVariable = the destination variable, FacMantissa3 = the string descriptor's address (low byte),
    ;;   FacMantissa4 = its high byte
    ;; Errors: ILLEGAL QUANTITY if the length is not six, a character other than a space is below `0`, or the byte
    ;;   read for a space is not a digit
    .proc AssignClockString
    ldy AssignedVariable+1
    cpy #>ZeroValue
    bne StoreString
    jsr Strings::ReleaseFac
    cmp #CLOCK_STRING_LENGTH
    .if longLengthError
        beq Convert
        jmp IllegalQuantityError
    .else
        bne AddClockDigit::ToIllegalQuantity
    .endif

;; Starts the conversion: a zero <Fac>, and Y = 0, the first digit's offset, which <NextPair> keeps in
;; <NumberBufferPointer>.
Convert:
    ldy #$00
    sty FacExponent
    sty FacSign

;; Adds the next two digits to <Fac>, as (<Fac> + first) * 10 + second, and multiplies it by 6 unless it is zero. With
;; the last multiplication by 10, the clock gets HH * 216000 + MM * 3600 + SS * 60, the time in sixtieths of a second.
;; Also: TIMELP (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
NextPair:
    sty NumberBufferPointer
    jsr AddClockDigit
    jsr Float::MultiplyByTen
    inc NumberBufferPointer
    ldy NumberBufferPointer
    jsr AddClockDigit
    jsr Float::CopyFacToArg
    tax
    beq SkipScale
    inx
    txa
    jsr Float::AddScaledArgAndDouble

;; Counts to six digits; then multiplies the whole value by 10 more, converts <Fac> to an integer and stores the clock.
;; Also: NOML6 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
SkipScale:
    ldy NumberBufferPointer
    iny
    cpy #CLOCK_STRING_LENGTH
    bne NextPair
    jsr Float::MultiplyByTen
    jsr Float::ToLongInteger
    .if STANDARD_KERNAL
        ldx FacMantissa3
        ldy FacMantissa2
        lda FacMantissa4
        jmp KernalSetClock
    .else
        ldx #$02
        sei

;; Stores the integer's three low bytes in <JiffyClock>, interrupts off.
;; Also: TIMEST (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
StoreClock:
        lda FacMantissa2,x
        sta JiffyClock,x
        dex
        bpl StoreClock
        cli
        rts
    .endif

    ;; Adds the digit at <Pointer1>+Y to <Fac>: any byte from `0` up, counted from `0`
    ;; (see <AssignClockString>).
    ;; In: Pointer1 = the string's characters, Y = the digit's offset
    ;; Errors: ILLEGAL QUANTITY if the character is below `0` and not a space
    ;; Entry:
    ;;   ToIllegalQuantity = jumps to <IllegalQuantityError>; the length check branches here where `longLengthError`
    ;;     is 0
    ;; Also: TIMNUM (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc AddClockDigit
    lda (Pointer1),y
    jsr ClassifyCharacter
    bcc Digit

;; Jumps to <IllegalQuantityError>.
;; Also: FCERR2 (M6502, CBM4S79, HV2, HV4, HV4R)
ToIllegalQuantity:
    jmp IllegalQuantityError

;; A digit, or any byte above it: subtracts the character `0` (the operand is one less, since the carry is clear)
;; and adds the value with <Float::AddSignedByte>.
;; Also: GOTNUM (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
Digit:
    sbc #('0'-1)
    jmp Float::AddSignedByte
    .endproc
    .endproc
.endmacro
