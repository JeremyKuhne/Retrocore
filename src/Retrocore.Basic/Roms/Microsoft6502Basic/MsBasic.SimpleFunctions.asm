; MICROSOFT 6502 BASIC: FREE SPACE AND POSITION
;
; These entries follow array multiplication and precede the user-defined-function code.

;; Emits the free-space, position and integer-to-float entries.
;; Parameters: setCarry = 1 to set carry before the <SNGFLT> branch, 0 to leave it unchanged
.macro SIMPLE_FUNCTIONS setCarry
    .assert setCarry = 0 || setCarry = 1, "setCarry must be 0 or 1."

;; Collects unused strings and returns free space between <STREND> and <FRETOP> in <FAC>.
;;
;; If the argument is a string, its temporary descriptor is released before collection. The 16-bit
;; difference is converted as a signed integer, so free space of 32768 bytes or more appears negative.
FRE:
    lda VALTYP
    beq NOFREF
    jsr FREFAC

NOFREF:
    jsr GARBA2
    sec
    lda FRETOP
    sbc STREND
    tay
    lda FRETOP+1
    sbc STREND+1

;; Converts the signed 16-bit value in A:Y to floating point in <FAC>.
;; In: A = high byte, Y = low byte
;; Out: FAC = numeric result, VALTYP = numeric
GIVAYF:
    ldx #$00
    stx VALTYP
    sta FACHO
    sty FACMOH
    ldx #$90
    jmp FLOATS

;; Returns the current text output column in <FAC>.
POS:
    ldy TRMPOS

;; Converts the unsigned byte in Y to floating point in <FAC>.
;; In: Y = value
;; Out: FAC = numeric result, VALTYP = numeric
SNGFLT:
    lda #$00
.if setCarry
    sec
.endif
    beq GIVAYF
.endmacro
