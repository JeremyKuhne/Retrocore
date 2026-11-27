; retrocore: style=strict
; Derived from Microsoft's BASIC for 6502 (m6502.asm, MIT license; see LICENSE in this folder).

.include "MsBasic.Families.asm"

; MICROSOFT 6502 BASIC: VARIABLE ASSIGNMENT
;
; AssignmentStart emits LET through the common <AssignString> entry. A variant may put
; its time-string assignment there before invoking StringAssignment.

;; Emits the common LET and numeric-assignment entries.
.macro AssignmentStart

    .scope Statements continued

    ;; Evaluates an expression and assigns it to a numeric or string variable.
    ;; See: <FindVariable>, <StoreNumber>, <AssignString>
    ;; Also: LET (M6502, ASTIL, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
    .proc Let
    jsr FindVariable
    sta AssignedVariable
    sty AssignedVariable+1
    lda #TOKEN_EQUAL
    jsr CheckCharacter
    lda IntegerType
    pha
    lda ValueType
    pha
    jsr EvaluateExpression
    pla
    rol a
    jsr RequireType
    bne LetString

;; Numeric result: pulls the saved <IntegerType> into A and falls into <StoreNumber>.
;; Also: COPNUM (M6502)
Number:
    pla
    ; Falls into StoreNumber.
    .endproc
    .endscope

    ;; Stores numeric <Fac> in the variable at <AssignedVariable>, choosing integer or floating-point storage.
    ;; The integer is rounded and stored high byte first; a float is packed.
    ;; In: A = negative for an integer variable (as <IntegerType>), Fac = the value
    ;; Also: QINTGR (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
    .proc StoreNumber
    bpl ToPackFac
    jsr Float::Round
    jsr FacToInteger
    ldy #$00
    lda FacMantissa3
    sta (AssignedVariable),y
    iny
    lda FacMantissa4
    sta (AssignedVariable),y
    rts

;; Jumps to <Float::StoreFacInVariable>, which packs <Fac> into the variable.
;; Also: COPFLT (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
ToPackFac:
    jmp Float::StoreFacInVariable
    .endproc

    .scope Statements continued

    ;; LET's string path: drops the saved flag and falls into <AssignString>.
    ;; Also: COPSTR (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
    .proc LetString
    pla
    ; Falls into AssignString.
    .endproc
    .endscope

;; Assigns the string result of `LET`, `INPUT` or `READ` to the variable at <AssignedVariable>.
;;
;; The time-string implementation, when present, precedes <StoreString>.
;; Also: INPCOM (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
AssignString:

.endmacro

;; Emits the common string-assignment code, with optional platform hooks.
;; Parameters: statusCheck = 1 to invoke `StringStatusCheck`, linkedCollector = 1 to invoke `LinkedStringRelease` and
;;   `LinkedStringStore`
.macro StringAssignment statusCheck, linkedCollector
    .assert statusCheck = 0 || statusCheck = 1, "statusCheck must be 0 or 1."
    .assert linkedCollector = 0 || linkedCollector = 1, "linkedCollector must be 0 or 1."

    ;; Copies a string's descriptor to <AssignedVariable>, copying the characters first if necessary.
    ;;
    ;; In AppleSoft, Apple Computer, in The Apple Orchard (March/April 1980, p. 15), calls the <StoreDescriptor> entry
    ;; `COPY`, which is distinct from Microsoft's <StoreString::CopyCharacters> entry.
    ;;
    ;; In: FacMantissa3 = the descriptor's address (low byte), FacMantissa4 = its high byte,
    ;;   AssignedVariable = the destination variable
    ;; See: <Strings::AllocateForFac>, <Strings::ReleaseTemporary>
    ;; Also: GETSPT (M6502, ASTIL, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
    .proc StoreString
    ldy #$02
    lda (FacMantissa3),y
    .if statusCheck
        StringStatusCheck
    .endif
    cmp StringsBottom+1
    bcc KeepCharacters
    bne CheckDescriptor
    dey
    lda (FacMantissa3),y
    cmp StringsBottom
    bcc KeepCharacters

;; String is in string space: copies it only if its descriptor lies at or above <VariablesStart> (a variable's).
;; Also: QVARIA (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
CheckDescriptor:
    ldy FacMantissa4
    cpy VariablesStart+1
    bcc KeepCharacters
    bne CopyCharacters
    lda FacMantissa3
    cmp VariablesStart
    bcs CopyCharacters

;; Uses the source descriptor as it is and jumps to <StoreDescriptor>.
;; Also: DNTCPY (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
KeepCharacters:
    lda FacMantissa3
    ldy FacMantissa4
    jmp StoreDescriptor

;; Allocates the length, copies the characters with <Strings::CopyString> and stores <NewDescriptor>.
;; Also: COPY (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
CopyCharacters:
    ldy #$00
    lda (FacMantissa3),y
    jsr Strings::AllocateForFac
    lda DescriptorPointer
    ldy DescriptorPointer+1
    sta StringPointer
    sty StringPointer+1
    jsr Strings::CopyString
    .if linkedCollector
        LinkedStringRelease
        ; Falls into StoreDescriptor, BASIC 4's linked copy.
        .endproc
        LinkedStringStore
    .else
        lda #<NewDescriptor
        ldy #$00
        ; Falls into StoreDescriptor.
        .endproc

        ;; Releases the descriptor addressed by Y:A if it is the latest temporary and copies it to <AssignedVariable>:
        ;; the classic collector's copy (BASIC 4's is its own, in its vendor's file).
        ;; In: A = descriptor address (low byte), Y = its high byte, AssignedVariable = the destination variable
        ;; Also: COPYZC (M6502)
        .proc StoreDescriptor
        sta DescriptorPointer
        sty DescriptorPointer+1
        jsr Strings::ReleaseTemporary
        ldy #$00
        lda (DescriptorPointer),y
        sta (AssignedVariable),y
        iny
        lda (DescriptorPointer),y
        sta (AssignedVariable),y
        iny
        lda (DescriptorPointer),y
        sta (AssignedVariable),y
        rts
        .endproc
    .endif

.endmacro
