; COMMODORE BASIC: CLOCK, STATUS AND VARIABLE VALUES

;; Emits the PET variable-value handler after its optional BASIC 4 trampoline.
;; Parameters: splitEntry = 1 to enter at ISVAR1 after a trampoline,
;;             clockPatch = 1 to use BASIC 1's editor-ROM clock checks,
;;             diskStatus = 1 to recognize BASIC 4's DS and DS$ variables
.macro COMMODORE_VARIABLE_VALUE splitEntry, clockPatch, diskStatus
    .assert splitEntry = 0 || splitEntry = 1, "splitEntry is 0 or 1."
    .assert clockPatch = 0 || clockPatch = 1, "clockPatch is 0 or 1."
    .assert diskStatus = 0 || diskStatus = 1, "diskStatus is 0 or 1."
    .assert clockPatch = 0 || diskStatus = 0, "Clock-patch and disk-status handlers are distinct."

.if splitEntry
;; Resolves a variable and loads its value, including PET clock and status variables.
;; Out: FAC = numeric value or string descriptor, VALTYP = result type
ISVAR1:
.else
;; Resolves a variable and loads its value, including PET clock and status variables.
;; Out: FAC = numeric value or string descriptor, VALTYP = result type
ISVAR:
.endif
    jsr PTRGET
ISVRET:
    sta FACMO
    sty FACLO
    lda VARNAM
    ldy VARNAM+1
    ldx VALTYP
    beq GOOO
.if clockPatch
    jmp TISTR
    .byte $18                   ; original branch displacement left by the editor-ROM patch
TISTR1:
.else
    ldx #$00
    stx FACOV
.if diskStatus
    ldx FACLO
    cpx #$8B
    bcc STRRTS
.else
    bit FACLO
    bpl STRRTS
.endif
    cmp #'T'
.if diskStatus
    bne ISVDS
.else
    bne STRRTS
.endif
.endif
    cpy #('I'+$80)
.if diskStatus
    bne ISVDS
.else
    bne STRRTS
.endif
    jsr GETTIM
    sty TENEXP
    dey
    sty FBUFPT
    ldy #$06
    sty DECCNT
    ldy #<(FDCEND-FOUTBL)
    jsr FOUTIM
    jmp TIMSTR
.if diskStatus

;; Resolves DS$ using the cached disk status, reading it from the drive if necessary.
ISVDS:
    cmp #'D'
    bne STRRTS
    cpy #('S'+$80)
    bne STRRTS
    jsr CHKDS
    lda DSDESC+1
    ldy DSDESC+2
    jmp STRLIT
.endif
STRRTS:
    rts

    INTEGER_VARIABLE_VALUE

.if clockPatch
    jmp TINUM
    .byte $19                   ; original branch displacement left by the editor-ROM patch
TINUM1:
.else
.if diskStatus
    ldx FACLO
    cpx #$8B
    bcc GOMOVF
.else
    bit FACLO
    bpl GOMOVF
.endif
    cmp #'T'
    bne QSTATV
.endif
    cpy #'I'
.if clockPatch
    bne QSTATV
.else
    bne GOMOVF
.endif
    jsr GETTIM
    tya
    ldx #$A0
    jmp FLOATB
.if diskStatus

;; Reads the disk status only if its descriptor is empty.
CHKDS:
    lda DSDESC
    bne STRRTS
    jmp CQRDDS
.endif

;; Copies the clock bytes into <FAC> while interrupts are disabled.
GETTIM:
    lda #<(CQTIMR-2)
    ldy #>(CQTIMR-2)
    sei
    jsr MOVFM
    cli
    sty FACHO
    rts

QSTATV:
    cmp #'S'
.if diskStatus
    bne QDSAV
.else
    bne GOMOVF
.endif
    cpy #'T'
.if diskStatus
    bne QDSAV
.else
    bne GOMOVF
.endif
    lda CQSTAT
    jmp FLOAT
.if diskStatus

;; Converts the first two disk-status digits to the numeric DS value.
QDSAV:
    cmp #'D'
    bne GOMOVF
    cpy #'S'
    bne GOMOVF
    jsr CHKDS
    ldy #$00
    lda (DSDESC+1),y
    and #$0F
    asl a
    sta GARBFL
    asl a
    asl a
    adc GARBFL
    sta GARBFL
    iny
    lda (DSDESC+1),y
    and #$0F
    adc GARBFL
    jmp FLOAT
.endif
GOMOVF:
    lda FACMO
    ldy FACLO
    jmp MOVFM
.endmacro
