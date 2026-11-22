;; COMMODORE BASIC FLOATING-POINT PACKAGE
;;
;; This module emits the contiguous math package from the addition entries through the arctangent table. Its caller
;; supplies the origin and external symbols. The shared sources ship beside the PET source folder.
;; The shared macros document the five-byte arithmetic, conversions, constants and transcendental routines.
;; BASIC 1 selects an earlier exponent limit and a different output threshold, BASIC 2 includes a hidden WAIT message,
;; and BASIC 4 includes a checksum and patch space before decimal output.

.cpu Mos6502

; The caller defines these six feature constants as 0 or 1:
; SHORT_FMUL_ZERO: 1 for BASIC 1's short zero-multiply branch in <FMULTT>.
; EARLY_FIN_LIMIT: 1 for BASIC 1's exponent-12 test in <FINEDG>. On its negative over-limit path, the new exponent
;   is (88 + twice the old exponent + the next digit) modulo 256.
; PRECISE_FOUT_LIMIT: 1 for BASIC 1's 999,999,999.5 upper threshold in <NZ9999>.
; ZERO_AT_FHALF: 1 to define <ZERO> within <FHALF> for BASIC 2 and 4; BASIC 1 supplies <ZERO> elsewhere.
; WAIT_EASTER_EGG: 1 to include BASIC 2's hidden WAIT routine and its encoded bytes.
; BASIC4_OUTPUT_PADDING: 1 to include BASIC 4's checksum and patch space before <INPRT>.

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

.assert SHORT_FMUL_ZERO = 0 || SHORT_FMUL_ZERO = 1, "SHORT_FMUL_ZERO is 0 or 1."
.assert EARLY_FIN_LIMIT = 0 || EARLY_FIN_LIMIT = 1, "EARLY_FIN_LIMIT is 0 or 1."
.assert PRECISE_FOUT_LIMIT = 0 || PRECISE_FOUT_LIMIT = 1, "PRECISE_FOUT_LIMIT is 0 or 1."
.assert ZERO_AT_FHALF = 0 || ZERO_AT_FHALF = 1, "ZERO_AT_FHALF is 0 or 1."
.assert WAIT_EASTER_EGG = 0 || WAIT_EASTER_EGG = 1, "WAIT_EASTER_EGG is 0 or 1."
.assert BASIC4_OUTPUT_PADDING = 0 || BASIC4_OUTPUT_PADDING = 1, "BASIC4_OUTPUT_PADDING is 0 or 1."

    ADD_ENTRIES

.if WAIT_EASTER_EGG
;; Handles BASIC 2's WAIT with no second mask, including its hidden message.
;;
;; For an address other than $1966 (decimal 6502), it continues the normal wait with a zero second mask. For $1966,
;; it writes "MICROSOFT!" as PET screen codes to successive addresses starting at $8000, repeating it the number of
;; times in the first mask. A zero count wraps to 256 repetitions, writing through $89FF. This path changes the saved
;; address and decrements the first mask to zero before returning.
;; In: X = 0
;; See: <WAIT_SIGNATURE>
ZSTORD:
    lda POKER
    cmp #$66
    bne STORDO
    lda POKER+1
    sbc #$19
    bne STORDO
    sta POKER
    tay
    lda #$80
    sta POKER+1

MRCHKR:
    ldx #$0A

MRCHR:
    lda WAIT_SIGNATURE-1,x
    and #$3F
    sta (POKER),y
    iny
    bne PKINC
    inc POKER+1

PKINC:
    dex
    bne MRCHR
    dec ANDMSK
    bne MRCHKR
    rts
.endif

    ADD_AND_NORMALIZE
    LOG_CONSTANTS
    LOG_ROUTINE
    FLOAT_ARITHMETIC SHORT_FMUL_ZERO
    FLOAT_MOVEMENT
    SIGN_INTEGER_ROUTINES
    DECIMAL_INPUT EARLY_FIN_LIMIT
    OUTPUT_CONSTANTS PRECISE_FOUT_LIMIT

.if BASIC4_OUTPUT_PADDING
;; Checksum adjustment byte for BASIC 4's $C000 ROM.
BASIC4_OUTPUT_CHECKSUM:
    .byte $F9

; Unused patch space through $CF77; decimal output resumes at $CF78.
    .res $CF78 - *, $AA
    .assert * = $CF78, "BASIC 4 INPRT must begin at $CF78."
.endif

    DECIMAL_OUTPUT 0, 1
    OUTPUT_TABLES ZERO_AT_FHALF, 1
    POWER_ROUTINES
    EXP_CONSTANTS
    EXP_ROUTINE
    POLYNOMIAL_ROUTINES
    RANDOM_ROUTINE 1
    TRIG_ROUTINES
    SIN_CONSTANTS

.if WAIT_EASTER_EGG
;; Encoded screen codes for BASIC 2's hidden WAIT message, stored in reverse order.
;;
;; <ZSTORD> reads the ten bytes backwards and masks off their upper two bits.
WAIT_SIGNATURE:
    .byte $A1, $54, $46, $8F, $13, $8F, $52, $43, $89, $CD
    .assert * - WAIT_SIGNATURE = 10, "WAIT_SIGNATURE has ten bytes."
.endif

    ATN_ROUTINE
    ATN_CONSTANTS
