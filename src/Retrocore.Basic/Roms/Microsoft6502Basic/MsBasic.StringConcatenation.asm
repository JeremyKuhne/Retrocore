; retrocore: style=strict
; Derived from Microsoft's BASIC for 6502 (m6502.asm, MIT license; see LICENSE in this folder).

.include "MsBasic.Families.asm"

; MICROSOFT 6502 BASIC: CONCATENATION, STRING MOVES AND RELEASE
;
; Emit StringConcatenation after the selected collector and before StringFunctions.

;; Emits <Strings::Concatenate> through <Strings::ReleaseTemporary>, immediately before <Functions::Chr>.
;;
;; The release choice is independent of the allocator and collector selections, which must use the
;; same string representation in a complete interpreter.
;; Parameters: linkedRelease = 1 to mark and reclaim BASIC 4's linked strings, 0 for unlinked strings
.macro StringConcatenation linkedRelease
    .assert linkedRelease = 0 || linkedRelease = 1, "linkedRelease must be 0 or 1."
    .assert DESCRIPTOR_SIZE = 3, "String temporaries must have three-byte descriptors."

    .scope Strings continued

    ;; Concatenates the <Fac> string with the next operand and resumes expression evaluation at
    ;; <EvaluateExpression::NextOperator>.
    ;;
    ;; It saves the first descriptor, evaluates the second string and allocates a combined result. It copies
    ;; the first string, releases and copies the second, then releases the first and creates a new temporary.
    ;; In: FacMantissa3 = first descriptor address (low byte), FacMantissa4 = its high byte, TextPointer = the plus
    ;;   sign, decimal = clear
    ;; Errors: STRING TOO LONG for a combined length above 255, TYPE MISMATCH for a non-string second operand,
    ;;   or an error from evaluation or allocation
    ;; Also: CAT (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc Concatenate
    lda FacMantissa4
    pha
    lda FacMantissa3
    pha
    jsr EvaluateOperand
    jsr RequireString
    pla
    sta StringPointer
    pla
    sta StringPointer+1
    ldy #$00
    lda (StringPointer),y
    clc
    adc (FacMantissa3),y
    bcc LengthOk
    ldx #<ERROR_STRING_TOO_LONG
    jmp ReportError

;; Allocates the combined string and copies the two strings into it.
;; Also: SIZEOK (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
LengthOk:
    jsr AllocateForFac
    jsr CopyString
    lda DescriptorPointer
    ldy DescriptorPointer+1
    jsr ReleaseDescriptor
    jsr CopyBytes
    lda StringPointer
    ldy StringPointer+1
    jsr ReleaseDescriptor
    jsr PushTemporary
    jmp EvaluateExpression::NextOperator
    .endproc

    ;; Copies the characters described by <StringPointer> to <NewString>, from the last character to the first.
    ;; In: StringPointer = descriptor address, NewString = destination, decimal = clear
    ;; Out: NewString = destination after the copy, Pointer1 = source address, X = source low byte, Y = 0
    ;; See: <Strings::CopyFrom>, <Strings::CopyBytes>
    ;; Also: MOVINS (M6502, ASTIL, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc CopyString
    ldy #$00
    lda (StringPointer),y
    pha
    iny
    lda (StringPointer),y
    tax
    iny
    lda (StringPointer),y
    tay
    pla
    ; Falls into CopyFrom.
    .endproc

    ;; Copies A bytes from X:Y to <NewString> and advances the destination pointer.
    ;; In: A = length, X = source low byte, Y = source high byte, NewString = destination, decimal = clear
    ;; Out: NewString = destination after the copy, Pointer1 = source address, Y = 0
    ;; Keeps: X
    ;; See: <Strings::CopyBytes>
    ;; Also: MOVSTR (M6502, ASTIL, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc CopyFrom
    stx Pointer1
    sty Pointer1+1
    ; Falls into CopyBytes.
    .endproc

    ;; Copies A bytes from <Pointer1> to <NewString> and advances the destination pointer.
    ;;
    ;; Bytes are copied in descending offset order, including across page boundaries. If the ranges overlap,
    ;; the destination must not start below the source. A zero length reads and writes no characters.
    ;; In: A = length, Pointer1 = source address, NewString = destination, decimal = clear
    ;; Out: A = destination low byte after the copy, Y = 0, NewString = destination after the copy
    ;; Keeps: X
    ;; Also: MOVDO (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc CopyBytes
    tay
    beq Advance
    pha

;; Copies one byte downward.
;; Also: MOVLP (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
Loop:
    dey
    lda (Pointer1),y
    sta (NewString),y

;; Loops while bytes remain.
;; Also: QMOVE (M6502)
CheckMore:
    tya
    bne Loop
    pla

;; Adds the length to <NewString>.
;; Also: MVDONE (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
Advance:
    clc
    adc NewString
    sta NewString
    bcc Done
    inc NewString+1

;; Returns.
;; Also: MVSTRT (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
Done:
    rts
    .endproc

    ;; Checks the <Fac> type, then releases its descriptor if it is the latest temporary.
    ;; Errors: TYPE MISMATCH if <Fac> is not a string
    ;; See: <Strings::ReleaseFac>, <Strings::ReleaseDescriptor>
    ;; Also: FRESTR (M6502, ASTIL, CBM4S79, K4S79, HV1, HV1R, HV2, HV4, HV4R, HVK4)
    .proc ReleaseFacString
    jsr RequireString
    ; Falls into ReleaseFac.
    .endproc

    ;; Releases the <Fac> string without checking its type.
    ;; In: FacMantissa3 = descriptor address (low byte), FacMantissa4 = its high byte, decimal = clear
    ;; Out: A = length, X = character address low byte, Y = character address high byte, Pointer1 = character address
    ;; See: <Strings::ReleaseDescriptor>
    ;; Also: FREFAC (M6502, ASTIL, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc ReleaseFac
    lda FacMantissa3
    ldy FacMantissa4
    ; Falls into ReleaseDescriptor.
    .endproc

    ;; Releases a descriptor if it is the latest temporary and returns its characters' address and length.
    ;;
    ;; Only the latest temporary is removed. With unlinked strings, its character space is reclaimed only if
    ;; it begins at <StringsBottom>. With linked strings, the platform's link helper marks eligible nonempty heap
    ;; strings as garbage; a string at <StringsBottom> also returns its two link bytes. Literals and other ineligible
    ;; strings are not marked. The character bytes themselves are left in place.
    ;; In: A = descriptor low byte, Y = descriptor high byte, decimal = clear
    ;; Out: A = length, X = character address low byte, Y = character address high byte, Pointer1 = character address
    ;; See: <Strings::ReleaseTemporary>
    ;; Also: FRETMP (M6502, ASTIL, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc ReleaseDescriptor
    sta Pointer1
    sty Pointer1+1
    jsr ReleaseTemporary
    .if linkedRelease
        bne ReadDescriptor
        jsr FindStringLink
        bcc ReadDescriptor
        dey
        lda #$FF
        sta (Pointer1),y
        dey
        txa
        sta (Pointer1),y
        pha
        eor #$FF
        sec
        adc Pointer1
        ldy Pointer1+1
        bcs CheckBottom
        dey

;; Stores the string's start and checks whether it is <StringsBottom>.
CheckBottom:
        sta Pointer1
        sty Pointer1+1
        tax
        pla
        cpy StringsBottom+1
        bne ReleaseTemporary::Done
        cpx StringsBottom
        bne ReleaseTemporary::Done
        pha
        sec
        adc StringsBottom
        sta StringsBottom
        bcc SkipLink
        inc StringsBottom+1

;; Raises <StringsBottom> past the second link byte.
SkipLink:
        inc StringsBottom
        bne RestoreLength
        inc StringsBottom+1

;; Pulls the length back into A.
;; Also: FREPLA (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
RestoreLength:
        pla
        rts

;; Loads the length into A and the address into <Pointer1> and X/Y.
ReadDescriptor:
        ldy #$00
        lda (Pointer1),y
        pha
        iny
        lda (Pointer1),y
        tax
        iny
        lda (Pointer1),y
        tay
        stx Pointer1
        sty Pointer1+1
        pla
        rts
    .else
        php
        ldy #$00
        lda (Pointer1),y
        pha
        iny
        lda (Pointer1),y
        tax
        iny
        lda (Pointer1),y
        tay
        pla
        plp
        bne StoreAddress
        cpy StringsBottom+1
        bne StoreAddress
        cpx StringsBottom
        bne StoreAddress
        pha
        clc
        adc StringsBottom
        sta StringsBottom
        bcc RestoreLength
        inc StringsBottom+1

;; Pulls the length back into A.
;; Also: FREPLA (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
RestoreLength:
        pla

;; Stores the address in <Pointer1> and returns.
;; Also: FRETRT (M6502, HV1, HV1R, HV2)
StoreAddress:
        stx Pointer1
        sty Pointer1+1
        rts
    .endif
    .endproc

    ;; Removes the descriptor A:Y from the temporary stack only if it is the latest entry.
    ;;
    ;; On a match, <NextTemporary> becomes the descriptor's low byte and the low byte of <LastTemporary> is reduced
    ;; by <DESCRIPTOR_SIZE>, without changing its high byte. The zero flag reports the match.
    ;; In: A = descriptor low byte, Y = descriptor high byte, decimal = clear
    ;; Out: zero = set if the descriptor matched <LastTemporary>, Y = 0 on a match
    ;; Keeps: X
    ;; Entry:
    ;;   Done = returns; where `linkedRelease` is 1 (BASIC 4), <Strings::ReleaseDescriptor> branches here
    ;; Also: FRETMS (M6502, ASTIL, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc ReleaseTemporary
    cpy LastTemporary+1
    bne Done
    cmp LastTemporary
    bne Done
    sta NextTemporary
    sbc #<DESCRIPTOR_SIZE
    sta LastTemporary
    ldy #$00

;; Returns; where `linkedRelease` is 1 (BASIC 4), <Strings::ReleaseDescriptor> branches here.
;; Also: FRERTS (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
Done:
    rts
    .endproc
    .endscope

.endmacro
