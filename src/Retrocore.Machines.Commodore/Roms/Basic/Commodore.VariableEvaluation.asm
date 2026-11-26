; retrocore: style=strict
; COMMODORE BASIC: CLOCK, STATUS AND VARIABLE VALUES

;; Emits the PET's variable lookup and <LoadVariableValue>, after BASIC 4's trampoline where it has one.
;; Parameters: splitEntry = 1 to enter at the evaluator's body, `EvaluateVariableBody`, after a trampoline,
;;   clockPatch = 1 to use BASIC 1's editor-ROM clock checks,
;;   diskStatus = 1 to recognize BASIC 4's DS and DS$ variables
.macro CommodoreVariableValue splitEntry, clockPatch, diskStatus
    .assert splitEntry = 0 || splitEntry = 1, "splitEntry is 0 or 1."
    .assert clockPatch = 0 || clockPatch = 1, "clockPatch is 0 or 1."
    .assert diskStatus = 0 || diskStatus = 1, "diskStatus is 0 or 1."
    .assert clockPatch = 0 || diskStatus = 0, "Clock-patch and disk-status handlers are distinct."

    .if splitEntry
        ;; BASIC 4's variable lookup beyond its patch area, which its trampoline reaches: looks up the variable operand
        ;; with <FindVariable> and falls into <LoadVariableValue>.
        ;; Also: ISVAR1 (UNKN)
        .proc EvaluateVariableBody
        jsr FindVariable
        ; Falls into LoadVariableValue.
        .endproc
    .else
        ;; Looks up the variable operand with <FindVariable> and falls into <LoadVariableValue>.
        ;; Also: ISVAR (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
        .proc EvaluateVariable
        jsr FindVariable
        ; Falls into LoadVariableValue.
        .endproc
    .endif

    ;; Makes `TI$` and, in BASIC 4, `DS$` strings, and otherwise leaves a string variable's descriptor address in
    ;; <FacMantissa3> and <FacMantissa4>; loads `TI`, `ST` and, in BASIC 4, `DS` as numbers, and a numeric variable's
    ;; value, into <Fac>.
    ;;
    ;; Where `clockPatch` is 1 (BASIC 1), the editor ROM's `CheckClockString` and `RouteNumericVariable` test for
    ;; `TI$` and `TI`, returning to this routine's `MatchClockString` and `MatchClockNumber`, and
    ;; `RouteNumericVariable` to `MatchStatus` and `LoadFloat`.
    ;; In: A = the value's address (low byte), Y = its high byte, VariableName = the variable's name, ValueType = its
    ;;   type, IntegerType = negative for an integer variable
    ;; Out: Fac = the numeric value; for a string, FacMantissa3 = its descriptor's address (low byte), FacMantissa4 =
    ;;   its high byte
    ;; Also: ISVRET (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc LoadVariableValue
    sta FacMantissa3
    sty FacMantissa4
    lda VariableName
    ldy VariableName+1
    ldx ValueType
    beq LoadNumericVariable
    .if clockPatch
        jmp CheckClockString
        .byte $18                   ; original branch displacement left by the editor-ROM patch

;; BASIC 1's `CheckClockString` returns here to check the `I` of `TI$`.
;; Also: TISTR1 (UNKN)
MatchClockString:
    .else
        ldx #$00
        stx FacExtension
        .if diskStatus
            ldx FacMantissa4
            cpx #$8B                ; at or above $8B00, out of RAM, as a reserved variable's is; others test bit 7
            bcc Return
        .else
            bit FacMantissa4
            bpl Return
        .endif
        cmp #'T'
        .if diskStatus
            bne DiskStatusString
        .else
            bne Return
        .endif
    .endif
    cpy #('I'+$80)
    .if diskStatus
        bne DiskStatusString
    .else
        bne Return
    .endif
    jsr ReadClock
    sty DecimalExponent
    dey
    sty NumberBufferPointer
    ldy #$06                        ; TI$'s six digits
    sty DigitCount
    ldy #<(Float::PowersOfTenEnd-Float::PowersOfTen)
    jsr Float::FormatFacAtOffset::ExtractDigits
    jmp Strings::FromNumberBuffer
    .if diskStatus

;; `DS$` returns the disk-status string, reading it from the drive if it is empty.
;; Also: ISVDS (CBM4S79, HV4, HV4R)
DiskStatusString:
        cmp #'D'
        bne Return
        cpy #('S'+$80)
        bne Return
        jsr EnsureDiskStatus
        lda DiskStatusDescriptor+1
        ldy DiskStatusDescriptor+2
        jmp Strings::FromText
    .endif

;; Returns with a string's descriptor address in <FacMantissa3> and <FacMantissa4>.
;; Also: STRRTS (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
Return:
    rts

    IntegerVariableValue

    .if clockPatch
        jmp RouteNumericVariable
        .byte $19                   ; original branch displacement left by the editor-ROM patch

;; BASIC 1's `RouteNumericVariable` returns here to check the `I` of `TI`.
;; Also: TINUM1 (UNKN)
MatchClockNumber:
    .else
        .if diskStatus
            ldx FacMantissa4
            cpx #$8B                ; at or above $8B00, out of RAM, as a reserved variable's is; others test bit 7
            bcc LoadFloat
        .else
            bit FacMantissa4
            bpl LoadFloat
        .endif
        cmp #'T'
        bne MatchStatus
    .endif
    cpy #'I'
    .if clockPatch
        bne MatchStatus
    .else
        bne LoadFloat
    .endif
    jsr ReadClock
    tya
    ldx #$A0                        ; the exponent of a 32-bit integer in the mantissa
    jmp Float::ConvertMantissa
    .if diskStatus

;; Reads the disk status with <KernalReadDiskStatus> only if its descriptor is empty.
;; Also: CHKDS (CBM4S79, HV4, HV4R)
EnsureDiskStatus:
        lda DiskStatusDescriptor
        bne Return
        jmp KernalReadDiskStatus
    .endif

;; Copies the jiffy clock into <Fac> with interrupts off.
;; Also: GETTIM (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
ReadClock:
    lda #<(JiffyClock-2)            ; the clock's three bytes as the mantissa's low three
    ldy #>(JiffyClock-2)
    sei
    jsr Float::LoadFac
    cli
    sty FacMantissa1
    rts

;; `ST` returns the channel status as a number; BASIC 1's editor-ROM `RouteNumericVariable` enters here.
;; Also: QSTATV (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
MatchStatus:
    cmp #'S'
    .if diskStatus
        bne DiskStatusNumber
    .else
        bne LoadFloat
    .endif
    cpy #'T'
    .if diskStatus
        bne DiskStatusNumber
    .else
        bne LoadFloat
    .endif
    lda IoStatus
    jmp Float::ConvertSignedByte
    .if diskStatus

;; `DS` returns the disk status's first two digits as a number.
;; Also: QDSAV (CBM4S79, HV4, HV4R)
DiskStatusNumber:
        cmp #'D'
        bne LoadFloat
        cpy #'S'
        bne LoadFloat
        jsr EnsureDiskStatus
        ldy #$00
        lda (DiskStatusDescriptor+1),y
        and #$0F
        asl a
        sta CollectionState
        asl a
        asl a
        adc CollectionState
        sta CollectionState
        iny
        lda (DiskStatusDescriptor+1),y
        and #$0F
        adc CollectionState
        jmp Float::ConvertSignedByte
    .endif

;; Moves the real variable into <Fac>; BASIC 1's editor-ROM `RouteNumericVariable` enters here too.
;; Also: GOMOVF (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
LoadFloat:
    lda FacMantissa3
    ldy FacMantissa4
    jmp Float::LoadFac
    .endproc
.endmacro

;; Emits the variable lookup and <LoadVariableValue> for the standard kernal: a reserved variable is one whose value is
;; in BASIC's ROM, and `TI` and `ST` come from the kernal's `KernalReadClock` and `KernalReadStatus`.
.macro CommodoreKernalVariableValue

    ;; Tells whether the variable's value is in BASIC's ROM, as a reserved variable's and an undefined simple
    ;; variable's are: from <ROM_ORIGIN> up to <CharacterReaderTemplate>. An array element's is in RAM, so `TI(1)` and
    ;; `ST(1)` are ordinary.
    ;; In: FacMantissa3 = the value's address (low byte), FacMantissa4 = its high byte
    ;; Out: carry = set for an address in that range
    ;; Keeps: X, Y
    ;; Also: TSTROM (BV20)
    .proc IsRomVariable
    sec
    lda FacMantissa3
    sbc #<ROM_ORIGIN
    lda FacMantissa4
    sbc #>ROM_ORIGIN
    bcc Return
    lda #<CharacterReaderTemplate
    sbc FacMantissa3
    lda #>CharacterReaderTemplate
    sbc FacMantissa4

;; Returns.
;; Also: TSTR10 (BV20)
Return:
    rts
    .endproc

    ;; Looks up the variable operand with <FindVariable> and falls into <LoadVariableValue>.
    ;; Also: ISVAR (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
    .proc EvaluateVariable
    jsr FindVariable
    ; Falls into LoadVariableValue.
    .endproc

    ;; Makes `TI$` a string, and otherwise leaves a string variable's descriptor address in <FacMantissa3> and
    ;; <FacMantissa4>; loads `TI` and `ST` as numbers, and a numeric variable's value, into <Fac>.
    ;; In: A = the value's address (low byte), Y = its high byte, VariableName = the variable's name, ValueType = its
    ;;   type, IntegerType = negative for an integer variable
    ;; Out: Fac = the numeric value; for a string, FacMantissa3 = its descriptor's address (low byte), FacMantissa4 =
    ;;   its high byte
    ;; Also: ISVRET (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
    .proc LoadVariableValue
    sta FacMantissa3
    sty FacMantissa4
    ldx VariableName
    ldy VariableName+1
    lda ValueType
    beq LoadNumericVariable

    ; A string: TI$ is the clock, as six digits.
    lda #$00
    sta FacExtension
    jsr IsRomVariable
    bcc Return
    cpx #'T'
    bne Return
    cpy #('I'+$80)
    bne Return
    jsr ReadClock
    sty DecimalExponent
    dey
    sty NumberBufferPointer
    ldy #$06                        ; TI$'s six digits
    sty DigitCount
    ldy #<(Float::PowersOfTenEnd-Float::PowersOfTen)
    jsr Float::FormatFacAtOffset::ExtractDigits
    jmp Strings::FromNumberBuffer

;; Returns with a string's descriptor address in <FacMantissa3> and <FacMantissa4>.
;; Also: STRRTS (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
Return:
    rts

    IntegerVariableValue 1

    ; A real variable: TI and ST are the clock and the status.
    jsr IsRomVariable
    bcc LoadFloat
    cpx #'T'
    bne MatchStatus
    cpy #'I'
    bne LoadFloat
    jsr ReadClock
    tya
    ldx #$A0                        ; the exponent of a 32-bit integer in the mantissa
    jmp Float::ConvertMantissa

;; Reads the jiffy clock through <KernalReadClock> into <Fac>'s low three mantissa bytes, with zero above them.
;; Out: Y = 0
;; Also: GETTIM (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
ReadClock:
    jsr KernalReadClock
    stx FacMantissa3
    sty FacMantissa2
    sta FacMantissa4
    ldy #$00
    sty FacMantissa1
    rts

;; `ST` returns <KernalReadStatus>'s status as a number.
;; Also: QSTATV (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
MatchStatus:
    cpx #'S'
    bne LoadFloat
    cpy #'T'
    bne LoadFloat
    jsr KernalReadStatus
    jmp Float::ConvertSignedByte

;; Moves the real variable into <Fac>.
;; Also: GOMOVF (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
LoadFloat:
    lda FacMantissa3
    ldy FacMantissa4
    jmp Float::LoadFac
    .endproc
.endmacro
