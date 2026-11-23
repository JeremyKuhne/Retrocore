; COMMODORE BASIC 4: PATCH SPACE BEFORE VARIABLE-VALUE HANDLING

;; Emits the BASIC 4 checksum, variable-entry trampoline and reserved patch area.
;; Parameters: revised = 1 for the revised ROM's patches, 0 for the original ROM
.macro COMMODORE_BASIC4_OPERAND_SPLIT revised
    .assert revised = 0 || revised = 1, "revised is 0 or 1."
.if revised
    .byte $B8
.else
    .byte $E1
.endif

;; Enters variable-value handling beyond the BASIC 4 patch area.
ISVAR:
    jmp ISVAR1
.if revised
;; Adjusts a moved string descriptor unless it belongs to the disk-status string.
;; In: A = high byte of the string address, DSDESC = disk-status descriptor
ADJDS:
    pha
    lda DSDESC
    beq ADJDS2
    pla
    cmp DSDESC+2
    bne ADJDS3
    jmp ADJDS1
ADJDS2:
    pla
ADJDS3:
    jmp ADJ02

;; Rejects the PI token as a statement before returning its next character.
GONEGT:
    jsr CHRGET
    cmp #<PI
    bne GONEG1
    jmp SNERR
GONEG1:
    jmp CHRGOT

;; Handles a blank INPUT line, distinguishing a terminal stop from file end-of-input.
INPNUL:
    lda CHANNL
    bne INPNU1
    jmp INPSTP
INPNU1:
    lda CQSTAT
    and #$40
    bne INPNU2
    jmp GETAGN
INPNU2:
    jmp INPCON
.endif

; The remainder is reserved for ROM patches.
    .res $BF8C - *, $AA
    .assert * = $BF8C, "BASIC 4 variable-value handling must resume at $BF8C."
.endmacro
