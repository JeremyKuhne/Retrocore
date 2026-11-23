; retrocore: style=strict
; Derived from Microsoft's BASIC for 6502 (m6502.asm, MIT license; see LICENSE in this folder).

.include "MsBasic.Families.asm"

; MICROSOFT 6502 BASIC: UNLINKED STRING GARBAGE COLLECTION
;
; Emit StringGarbageCollection immediately after the unlinked allocator. When selected, the
; `ARYINC` array-step patch is an external routine in the editor ROM.

;; Emits the repeated-scan collector for unlinked string storage.
;;
;; The three choices are independent: the full pointer test recognizes page-zero descriptors;
;; the array step may be performed by an out-of-line `ARYINC` patch; and the descriptor offset
;; may be calculated by subtraction instead of masking. AppleSoft uses 0,0,0, PET BASIC 1
;; 0,1,1 by default, and PET BASIC 2 1,0,0.
;; Parameters: fullDescriptorPointer = 1 to test both bytes of the selected descriptor pointer,
;;   patchedArrayStep = 1 to call `ARYINC`, subtractDescriptorOffset = 1 to subtract 3
.macro StringGarbageCollection fullDescriptorPointer, patchedArrayStep, subtractDescriptorOffset
    .assert fullDescriptorPointer = 0 || fullDescriptorPointer = 1, "fullDescriptorPointer must be 0 or 1."
    .assert patchedArrayStep = 0 || patchedArrayStep = 1, "patchedArrayStep must be 0 or 1."
    .assert subtractDescriptorOffset = 0 || subtractDescriptorOffset = 1, "subtractDescriptorOffset must be 0 or 1."
    .assert ADDITIONAL_PRECISION = 1 && INTEGER_VARIABLES = 1, "This collector requires five-byte floats."
    .assert DESCRIPTOR_SIZE = 3, "This collector requires three-byte string descriptors."

    .scope Strings continued

    ;; Compacts live strings toward <MemoryTop>, updating the descriptors that refer to them.
    ;;
    ;; Each pass scans temporaries, scalars and string arrays, chooses the highest nonempty string at or
    ;; above <ArraysEnd> and below <StringsBottom>, moves it upward, and repeats. Literal strings below <ArraysEnd>
    ;; and other scalar and array types are left alone. <CollectorStep> must initially hold <DESCRIPTOR_SIZE>.
    ;; Where `fullDescriptorPointer` is 0 (AppleSoft, and PET BASIC 1 by default), only the selected descriptor
    ;; pointer's high byte is tested: if the selected descriptor is in page zero, as for a temporary, collection
    ;; ends without moving it or any lower remaining strings. PET BASIC 2 tests both bytes and collects those
    ;; temporaries.
    ;;
    ;; In AppleSoft, Apple Computer, in The Apple Orchard (March/April 1980, p. 16), calls it `GARBAG`, which is
    ;; distinct from Microsoft's `GARBAG` allocation-retry entry.
    ;;
    ;; In: CollectorStep = <DESCRIPTOR_SIZE>, as Microsoft's and AppleSoft's cold starts set it and every collection
    ;;   leaves it (the temporaries' scan reads it before the pass sets it), decimal = clear
    ;; Out: StringsBottom = lower boundary after collection
    ;; See: <Strings::CollectGarbage::ConsiderDescriptor>, <Strings::CollectGarbage::MoveBest>, <MoveRangeUp::Unchecked>
    ;; Also: GARBA2 (M6502, HV1, HV1R, HV2)
    .proc CollectGarbage
    ldx MemoryTop
    lda MemoryTop+1

;; Sets <StringsBottom> to the top of the collected strings, clears the best candidate and starts at the
;; temporaries.
;; Also: FNDVAR (M6502, HV1, HV1R, HV2)
NextPass:
    stx StringsBottom
    sta StringsBottom+1
    ldy #$00
    sty CollectorPointer+1
    .if fullDescriptorPointer
        sty CollectorPointer
    .endif
    lda ArraysEnd
    ldx ArraysEnd+1
    sta CollectorTop
    stx CollectorTop+1
    lda #<TemporaryDescriptors
    ldx #$00
    sta Pointer1
    stx Pointer1+1

;; Considers each temporary descriptor up to <NextTemporary>.
;; Also: TVAR (M6502, HV1, HV1R, HV2)
ScanTemporaries:
    cmp NextTemporary
    beq StartScalars
    jsr ConsiderDescriptor
    beq ScanTemporaries

;; Sets the step to a scalar entry's size and starts at <VariablesStart>.
;; Also: SVARS (M6502, HV1, HV1R, HV2)
StartScalars:
    lda #.sizeof(Variable)
    sta CollectorStep
    lda VariablesStart
    ldx VariablesStart+1
    sta Pointer1
    stx Pointer1+1

;; Stops at <ArraysStart>.
;; Also: SVAR (M6502, HV1, HV1R, HV2)
ScanScalars:
    cpx ArraysStart+1
    bne CheckScalar
    cmp ArraysStart
    beq StartArrays

;; Considers one scalar if it is a string variable.
;; Also: SVARGO (M6502, HV1, HV1R, HV2)
CheckScalar:
    jsr ConsiderScalar
    beq ScanScalars

;; Sets <ArrayPointer> to the arrays and the step to a descriptor's size.
;; Also: ARYVAR (M6502, HV1, HV1R, HV2)
StartArrays:
    sta ArrayPointer
    stx ArrayPointer+1
    lda #<DESCRIPTOR_SIZE
    sta CollectorStep

;; Loads the next array's address.
NextArray:
    lda ArrayPointer
    ldx ArrayPointer+1

;; At <ArraysEnd> the scan is over: moves the best string.
CheckArraysEnd:
    cpx ArraysEnd+1
    bne ReadArray
    cmp ArraysEnd
    bne ReadArray
    jmp MoveBest

;; Advances <ArrayPointer> past this array and, for a string array, points <Pointer1> at its first element.
ReadArray:
    sta Pointer1
    stx Pointer1+1
    ldy #$00
    lda (Pointer1),y
    tax
    iny
    lda (Pointer1),y
    php
    iny
    lda (Pointer1),y
    adc ArrayPointer
    sta ArrayPointer
    iny
    lda (Pointer1),y
    adc ArrayPointer+1
    sta ArrayPointer+1
    plp
    bpl NextArray
    txa
    bmi NextArray
    iny
    lda (Pointer1),y
    .if patchedArrayStep
        jsr ARYINC
    .else
        ldy #$00
        asl a
        adc #.sizeof(ArrayHeader)
    .endif
    adc Pointer1
    sta Pointer1
    bcc ElementsReady
    inc Pointer1+1

;; Loads <Pointer1>'s high byte for the element loop.
ElementsReady:
    ldx Pointer1+1

;; Stops at the array's end (<ArrayPointer>).
;; Also: ARYSTR (M6502, HV1, HV1R, HV2)
ScanElements:
    cpx ArrayPointer+1
    bne CheckElement
    cmp ArrayPointer
    beq CheckArraysEnd

;; Considers one element's descriptor.
CheckElement:
    jsr ConsiderDescriptor
    beq ScanElements

;; Considers a scalar string descriptor during garbage collection, skipping other scalar types.
;; Also: DVARS (M6502, HV1, HV1R, HV2)
ConsiderScalar:
    lda (Pointer1),y
    bmi Advance
    iny
    lda (Pointer1),y
    bpl Advance
    iny

;; Considers the descriptor at <Pointer1> for the current garbage-collection pass.
;;
;; <CollectorStep> is the descriptor stride, either three bytes for a temporary or array element or seven for
;; a scalar variable. Empty strings need no storage moved.
;; Also: DVAR (M6502, HV1, HV1R, HV2)
ConsiderDescriptor:
    lda (Pointer1),y
    beq Advance
    iny
    lda (Pointer1),y
    tax
    iny
    lda (Pointer1),y
    cmp StringsBottom+1
    bcc CheckBest
    bne Advance
    cpx StringsBottom
    bcs Advance

;; Compares the string's address with <CollectorTop> (the best so far).
;; Also: DVAR2 (M6502, HV1, HV1R, HV2)
CheckBest:
    cmp CollectorTop+1
    bcc Advance
    bne NewBest
    cpx CollectorTop
    bcc Advance

;; Records the string's address in <CollectorTop>, the descriptor in <CollectorPointer> and the step in
;; <CollectorOffset>.
;; Also: DVAR3 (M6502, HV1, HV1R, HV2)
NewBest:
    stx CollectorTop
    sta CollectorTop+1
    lda Pointer1
    ldx Pointer1+1
    sta CollectorPointer
    stx CollectorPointer+1
    lda CollectorStep
    sta CollectorOffset

;; Adds the step (<CollectorStep>) to <Pointer1>.
Advance:
    lda CollectorStep
    clc
    adc Pointer1
    sta Pointer1
    bcc Return
    inc Pointer1+1

;; Returns with X = <Pointer1>'s high byte and Y = 0 (also the collector's exit when nothing is left to move).
;; Also: GRBRTS (M6502, HV1, HV1R, HV2)
Return:
    ldx Pointer1+1
    ldy #$00
    rts

;; Moves the string chosen by the completed scan and rewrites its descriptor.
;; Also: GRBPAS (M6502, HV1, HV1R, HV2)
MoveBest:
    .if fullDescriptorPointer
        lda CollectorPointer+1
        ora CollectorPointer
    .else
        ldx CollectorPointer+1
    .endif
    beq Return
    lda CollectorOffset
    .if subtractDescriptorOffset
        sbc #$03
    .else
        and #$04
    .endif
    lsr a
    tay
    sta CollectorOffset
    lda (CollectorPointer),y
    adc CollectorTop
    sta SourceEnd
    lda CollectorTop+1
    adc #$00
    sta SourceEnd+1
    lda StringsBottom
    ldx StringsBottom+1
    sta DestinationEnd
    stx DestinationEnd+1
    jsr MoveRangeUp::Unchecked
    ldy CollectorOffset
    iny
    lda DestinationEnd
    sta (CollectorPointer),y
    tax
    inc DestinationEnd+1
    lda DestinationEnd+1
    iny
    sta (CollectorPointer),y
    jmp NextPass
    .endproc
    .endscope

.endmacro
