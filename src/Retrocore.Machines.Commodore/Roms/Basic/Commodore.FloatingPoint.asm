; retrocore: style=strict
;; COMMODORE BASIC: THE FLOATING-POINT PACKAGE
;;
;; This module emits the contiguous math package, from the addition entries through the arctangent table, in the
;; families `Float` and `Functions`. Its caller supplies the origin and the definitions it uses. The shared macros,
;; which ship beside the PET source folder, document the five-byte arithmetic, the conversions, the constants and the
;; transcendental functions. BASIC 1 selects an earlier exponent limit and a different output threshold, BASIC 2
;; includes a hidden WAIT message, and BASIC 4 a checksum byte and patch space before decimal output.

.cpu Mos6502

; The caller defines these six switches as 0 or 1:
; SHORT_MULTIPLY_ZERO: 1 for BASIC 1's short zero-multiply branch in <Float::MultiplyArg>.
; EARLY_INPUT_EXPONENT_LIMIT: 1 for BASIC 1's exponent-12 test in <Float::AccumulateExponentDigit>. On its negative
;   over-limit path, the new exponent is (88 + twice the old exponent + the next digit) modulo 256.
; PRECISE_OUTPUT_LIMIT: 1 for BASIC 1's 999,999,999.5 upper threshold in <Float::UpperOutputLimit>.
; ZERO_IN_HALF_CONSTANT: 1 to define `ZeroValue` within <Float::Half> for BASIC 2 and 4; BASIC 1 has its own.
; WAIT_EASTER_EGG: 1 to include BASIC 2's hidden WAIT routine and its encoded bytes.
; BASIC4_OUTPUT_PADDING: 1 to include BASIC 4's checksum and patch space before <Float::PrintInLineNumber>.
; SQR_PATCH_SPACE and UNSPACED_LINE_NUMBERS, which default to 0, are described where they are defined.

.include "Commodore.Switches.asm"
.include "../../Microsoft6502Basic/MsBasic.AdditionCore.asm"
.include "../../Microsoft6502Basic/MsBasic.FloatConstants.asm"
.include "../../Microsoft6502Basic/MsBasic.Logarithm.asm"
.include "../../Microsoft6502Basic/MsBasic.ArithmeticCore.asm"
.include "../../Microsoft6502Basic/MsBasic.MovementCore.asm"
.include "../../Microsoft6502Basic/MsBasic.ConversionCore.asm"
.include "../../Microsoft6502Basic/MsBasic.DecimalInputCore.asm"
.include "../../Microsoft6502Basic/MsBasic.OutputCore.asm"
.include "../../Microsoft6502Basic/MsBasic.TranscendentalCore.asm"
.include "../../Microsoft6502Basic/MsBasic.RandomCore.asm"

.assert SHORT_MULTIPLY_ZERO = 0 || SHORT_MULTIPLY_ZERO = 1, "SHORT_MULTIPLY_ZERO is 0 or 1."
.assert EARLY_INPUT_EXPONENT_LIMIT = 0 || EARLY_INPUT_EXPONENT_LIMIT = 1, "EARLY_INPUT_EXPONENT_LIMIT is 0 or 1."
.assert PRECISE_OUTPUT_LIMIT = 0 || PRECISE_OUTPUT_LIMIT = 1, "PRECISE_OUTPUT_LIMIT is 0 or 1."
.assert ZERO_IN_HALF_CONSTANT = 0 || ZERO_IN_HALF_CONSTANT = 1, "ZERO_IN_HALF_CONSTANT is 0 or 1."
.assert WAIT_EASTER_EGG = 0 || WAIT_EASTER_EGG = 1, "WAIT_EASTER_EGG is 0 or 1."
.assert BASIC4_OUTPUT_PADDING = 0 || BASIC4_OUTPUT_PADDING = 1, "BASIC4_OUTPUT_PADDING is 0 or 1."

.ifndef SQR_PATCH_SPACE
;; 1 includes the BASIC chip's checksum byte, `BASIC_ROM_CHECKSUM`, and patch space before `SQR`, which then starts
;; $1F71 bytes into the chip (the VIC-20's).
SQR_PATCH_SPACE = 0
.endif
.assert SQR_PATCH_SPACE = 0 || SQR_PATCH_SPACE = 1, "SQR_PATCH_SPACE is 0 or 1."

.ifndef UNSPACED_LINE_NUMBERS
;; 1 prints line numbers without the space before them (the VIC-20's): <Float::PrintDecimalAX> enters
;; <Float::FormatFacAtOffset> with the Y of 0 that the conversion leaves, so the sign's place falls before the string.
UNSPACED_LINE_NUMBERS = 0
.endif
.assert UNSPACED_LINE_NUMBERS = 0 || UNSPACED_LINE_NUMBERS = 1, "UNSPACED_LINE_NUMBERS is 0 or 1."

    AddEntries

.if WAIT_EASTER_EGG
;; Handles BASIC 2's WAIT with no second mask, including its hidden message.
;;
;; For an address other than $1966 (decimal 6502), it continues the plain wait at <Statements::Wait::StoreMask> with a
;; zero second mask. For $1966, it writes "MICROSOFT!" as PET screen codes to successive addresses from $8000, repeating
;; it the number of times in the first mask. A zero count wraps to 256 repetitions, writing through $89FF. This path
;; changes the saved address and decrements the first mask to zero before returning.
;; In: X = 0
;; Entry:
;;   Repeat = starts the ten-character message again
;;   NextCharacter = stores one character and advances the screen address
;; See: <HiddenMessageText>
;; Also: ZSTORD (M6502), STORD1 (HV2)
.proc WaitHiddenMessage
    lda PokeAddress
    cmp #$66
    bne STORDO
    lda PokeAddress+1
    sbc #$19
    bne STORDO
    sta PokeAddress
    tay
    lda #$80
    sta PokeAddress+1

;; Starts the ten-character message again.
;; Also: MRCHKR (M6502, HV2)
Repeat:
    ldx #HIDDEN_MESSAGE_LENGTH

;; Stores one character, masked to a screen code, and advances the screen address.
;; Also: MRCHR (M6502, HV2)
NextCharacter:
    lda HiddenMessageText-1,x
    and #SCREEN_CODE_MASK
    sta (PokeAddress),y
    iny
    bne Count
    inc PokeAddress+1

;; Counts the characters, then the repetitions in <WaitAndMask>.
;; Also: PKINC (M6502, HV2)
Count:
    dex
    bne NextCharacter
    dec WaitAndMask
    bne Repeat
    rts
.endproc

;; The number of characters in the hidden message.
HIDDEN_MESSAGE_LENGTH = 10

;; The bits of a message byte that make its screen code.
SCREEN_CODE_MASK = $3F
.endif

    AddAndNormalize
    LogarithmConstants
    LogarithmRoutine
    FloatArithmetic SHORT_MULTIPLY_ZERO
    FloatMovement
    SignAndIntegerRoutines
    DecimalInput EARLY_INPUT_EXPONENT_LIMIT
    OutputConstants PRECISE_OUTPUT_LIMIT

.if BASIC4_OUTPUT_PADDING
;; The byte that adjusts the checksum of BASIC 4's $C000 ROM, before the patch space.
;; Also: CHSUMC (HV4, HV4R)
RomChecksumAdjustment:
    .byte $F9

    ; Unused patch space through $CF77; decimal output resumes at $CF78.
    .res $CF78 - *, $AA
    .assert * = $CF78, "BASIC 4's PrintInLineNumber must begin at $CF78."
.endif

.if UNSPACED_LINE_NUMBERS
    DecimalOutput 0, 1, 1
.else
    DecimalOutput 0, 1
.endif
    OutputTables ZERO_IN_HALF_CONSTANT, 1

.if SQR_PATCH_SPACE
;; The byte that makes the BASIC chip's checksum come out to its page: the root defines <BASIC_ROM_CHECKSUM>.
;; Also: CKSMC0 (BV20)
BasicRomChecksumAdjustment:
    .byte BASIC_ROM_CHECKSUM

;; Unused patch space, filled with $AA, up to `SQR`.
;; Also: PATCHS (BV20)
PatchSpace:
    .res ROM_ORIGIN + $1F71 - *, $AA
.endif

    PowerRoutines
    ExponentialConstants
    ExponentialRoutine
    PolynomialRoutines
.if STANDARD_KERNAL
    RandomRoutine 2
    CommodoreKernalStatements
.else
    RandomRoutine 1
.endif
    TrigonometricRoutines
    SineConstants

.if WAIT_EASTER_EGG
;; The screen codes of BASIC 2's hidden WAIT message, stored in reverse order.
;;
;; <WaitHiddenMessage> reads the ten bytes backwards and masks off their upper two bits.
HiddenMessageText:
    .byte $A1, $54, $46, $8F, $13, $8F, $52, $43, $89, $CD
    .assert * - HiddenMessageText = HIDDEN_MESSAGE_LENGTH, "HiddenMessageText has ten bytes."
.endif

    ArctangentRoutine
    ArctangentConstants
