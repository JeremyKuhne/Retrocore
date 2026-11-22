; MICROSOFT 6502 BASIC: CHARACTER READING AND CLASSIFICATION

;; Emits the uppercase-letter test.
.macro LETTER_TEST

;; Tests whether A is an uppercase ASCII letter.
;; In: A = character, decimal = clear
;; Out: carry = set for A through Z, clear otherwise
ISLETC:
    cmp #$41
    bcc ISLRTS
    sbc #$5B
    sec
    sbc #$A5
ISLRTS:
    rts

.endmacro

;; Emits the character-reader template and five-byte random seed.
;; Parameters: seedTail = the last byte of the random seed
.macro CHARACTER_READER seedTail

;; Template for the character-fetch code copied to <CHRGET> in page zero.
;;
;; The copy increments <TXTPTR>, whose two bytes are the operand at <CHZGOT>, and skips spaces. Five seed bytes
;; follow the code, but startup copies only the first four to <RNDX>. BASIC 1 stores $59 as the fifth byte;
;; AppleSoft and the later PET BASICs store $58.
;; Entry: CHZGOT = fetches the current character without advancing the pointer
;; In: decimal = clear
;; Out: A = the non-space character, carry = clear for a digit and set otherwise, zero = set for a null or colon
;; Keeps: X, Y
INITAT:
    inc TXTPTR
    bne CHZGOT
    inc TXTPTR+1

CHZGOT:
    lda $EA60                       ; copied operand becomes TXTPTR
    cmp #':'
    bcs CHZRTS
    cmp #' '
    beq INITAT
    sec
    sbc #'0'
    sec
    sbc #$D0

CHZRTS:
    rts
    .byte $80, $4F, $C7, $52, seedTail

.endmacro
