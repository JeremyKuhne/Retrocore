; retrocore: style=strict
; Derived from Microsoft's BASIC for 6502 (m6502.asm, MIT license; see LICENSE in this folder).

.include "MsBasic.Families.asm"

; MICROSOFT 6502 BASIC: CHARACTER READING AND CLASSIFICATION

;; Emits the uppercase-letter test.
.macro LetterTest

    ;; Tests whether A holds an uppercase letter, $41 through $5A.
    ;;
    ;; The two subtractions take $5B and then $A5 from the character, $100 in all, so A comes back unchanged.
    ;; In: A = character, decimal = clear
    ;; Out: carry = set for A through Z, clear otherwise
    ;; Keeps: A, X, Y
    ;; Also: ISLETC (M6502, ASTIL, AS82, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc IsLetter
    cmp #$41
    bcc Done
    sbc #$5B
    sec
    sbc #$A5
;; Returns; a character below `A` branches here.
;; Also: ISLRTS (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
Done:
    rts
    .endproc

.endmacro

;; Emits the character-reader template and five-byte random seed.
;; Parameters: seedTail = the last byte of the random seed
.macro CharacterReader seedTail

    ;; Template for the character-fetch code copied to <GetNextCharacter> in page zero.
    ;;
    ;; The copy increments <TextPointer>, whose two bytes are the operand at <CharacterReaderTemplate::GetCurrent>, and
    ;; skips spaces. Five seed bytes follow the code, but startup copies only the first four to <RandomValue>. BASIC 1
    ;; stores $59 as the fifth byte; AppleSoft and the later PET BASICs store $58.
    ;;
    ;; Martin Hoffmann-Vetter's reconstructions spell the labels CHZGOT and CHZRTS as `CHDGOT` and `CHDRTS`: the PET
    ;; BASIC 1 and 2 builds take those as Commodore's historical names, and in BASIC 4 (HV4, HV4R) they are given here,
    ;; since BASIC 4's own source (CBM4S79) does not name the labels.
    ;; In: decimal = clear
    ;; Out: A = the non-space character, carry = clear for a digit and set otherwise, zero = set for a null or colon
    ;; Keeps: X, Y
    ;; Also: INITAT (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc CharacterReaderTemplate
    inc TextPointer
    bne GetCurrent
    inc TextPointer+1

;; Fetches the current character without advancing the pointer.
;; Also: CHZGOT (M6502)
GetCurrent:
    lda $EA60                       ; copied operand becomes TXTPTR
    cmp #':'
    bcs Done
    cmp #' '
    beq CharacterReaderTemplate
    sec
    sbc #'0'
    sec
    sbc #$D0

;; Returns; a colon or anything above it branches here. The seed bytes follow.
;; Also: CHZRTS (M6502)
Done:
    rts
    .byte $80, $4F, $C7, $52, seedTail
    .endproc

.endmacro
