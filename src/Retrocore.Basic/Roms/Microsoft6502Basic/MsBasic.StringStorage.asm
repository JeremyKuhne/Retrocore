; retrocore: style=strict
; Derived from Microsoft's BASIC for 6502 (m6502.asm, MIT license; see LICENSE in this folder).

.include "MsBasic.Families.asm"

; MICROSOFT 6502 BASIC: STRING DESCRIPTORS AND LITERALS
;
; StringStorage emits <Strings::AllocateForFac> through <Strings::PushTemporary>. Follow it with StringAllocation
; and the matching platform collector, <Strings::CollectGarbage>. The separate allocators are macro definitions
; only; the linked one emits no bytes unless selected. Allocation is independent of the literal and
; temporary-descriptor choices.

.include "MsBasic.StringStorage.Classic.asm"
.include "MsBasic.StringStorage.Linked.asm"

;; Emits the common string initialization, literal scanning and temporary-descriptor routines.
;; Parameters: bufferPage = input buffer page, or 0 when it is already in page zero;
;;   clearFacOverflow = 1 to clear <FacExtension> when making a temporary, 0 to leave it unchanged
.macro StringStorage bufferPage, clearFacOverflow
    .assert bufferPage >= 0 && bufferPage <= 255, "bufferPage must fit in a byte."
    .assert clearFacOverflow = 0 || clearFacOverflow = 1, "clearFacOverflow must be 0 or 1."
    .assert DESCRIPTOR_SIZE = 3 && TEMPORARY_COUNT > 0, "String temporaries must have three-byte descriptors."
    .assert TemporaryDescriptors >= 0, "The temporary stack must not start below address zero."
    .assert TemporaryDescriptors + DESCRIPTOR_SIZE * TEMPORARY_COUNT <= $FF, "The temporaries must fit in page zero."

    .scope Strings continued

    ;; Allocates space for a result string, saving the current descriptor pointer in <DescriptorPointer>.
    ;; In: A = string length, FacMantissa3 = descriptor address (low byte), FacMantissa4 = its high byte
    ;; Out: DescriptorPointer = original descriptor address, NewDescriptor = length and character address
    ;; Also: STRINI (M6502, ASTIL, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc AllocateForFac
    ldx FacMantissa3
    ldy FacMantissa4
    stx DescriptorPointer
    sty DescriptorPointer+1
    ; Falls into Allocate.
    .endproc

    ;; Allocates space and builds a temporary descriptor without saving the previous descriptor.
    ;;
    ;; With the linked allocator, a zero-length descriptor has low address byte zero and the entry's Y as its
    ;; unused high byte. When reached through <Strings::AllocateForFac>, Y is the original <FacMantissa4>.
    ;; In: A = string length
    ;; Out: NewDescriptor = length and character address, A = the length, X = the address's low byte, Y = its high byte
    ;; Errors: OUT OF MEMORY if the string does not fit after collection
    ;; Also: STRSPA (M6502, ASTIL, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc Allocate
    jsr ReserveSpace
    stx NewDescriptor+1
    sty NewDescriptor+2
    sta NewDescriptor
    rts
    .endproc

    ;; Builds a temporary string from text beginning at A:Y, stopping at a quote or zero.
    ;;
    ;; For a quoted literal the leading quote has already been consumed; a closing quote is skipped.
    ;; See: <Strings::FromTextUntil>
    ;; In: A = low text address, Y = high text address
    ;; Out: FacMantissa3 = temporary descriptor pointer (low byte), FacMantissa4 = 0,
    ;;   SecondStringPointer = position after a quote or at zero
    ;; Errors: FORMULA TOO COMPLEX if no temporary descriptor is available, or OUT OF MEMORY while copying
    ;; Also: STRLIT (M6502, ASTIL, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc FromText
    ldx #'"'
    stx Delimiter
    stx EndDelimiter
    ; Falls into FromTextUntil.
    .endproc

    ;; Scans a literal using <Delimiter> and <EndDelimiter> as additional terminators.
    ;;
    ;; A quote terminator is skipped, but a zero or other terminator is not. The initial text page alone
    ;; selects copying: page zero and the configured nonzero input-buffer page are copied to string space;
    ;; other pages remain in place. A terminator must occur within the first 256 bytes.
    ;; In: A = low text address, Y = high text address
    ;; Out: FacMantissa3 = temporary descriptor pointer (low byte), FacMantissa4 = 0,
    ;;   SecondStringPointer = position after a quote or at another terminator
    ;; Errors: FORMULA TOO COMPLEX if no temporary descriptor is available, or OUT OF MEMORY while copying
    ;; Also: STRLT2 (M6502, ASTIL, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc FromTextUntil
    sta StringPointer
    sty StringPointer+1
    sta NewDescriptor+1
    sty NewDescriptor+2
    ldy #$FF

;; Reads characters until a terminator.
;; Also: STRGET (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
Scan:
    iny
    lda (StringPointer),y
    beq AtZero
    cmp Delimiter
    beq AtDelimiter
    cmp EndDelimiter
    bne Scan

;; Sets carry to skip a closing quote.
;; Also: STRFIN (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
AtDelimiter:
    cmp #'"'
    beq SetLength

;; Clears carry: the terminator is not skipped.
;; Also: STRFI1 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
AtZero:
    clc

;; Stores the length and the end position in <SecondStringPointer>.
;; Also: STRFI2 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
SetLength:
    sty NewDescriptor
    tya
    adc StringPointer
    sta SecondStringPointer
    ldx StringPointer+1
    bcc CheckPage
    inx

;; Chooses copying by the text's page.
;; Also: STRST2 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
CheckPage:
    stx SecondStringPointer+1
    lda StringPointer+1
    ; Where the input buffer is outside page zero (all but BASIC 1, by default), text in page zero or the buffer's page
    ; is copied.
    .if bufferPage
        beq CopyText
        cmp #bufferPage
    .endif
    bne PushTemporary

;; Allocates and copies the text into string space.
;; Also: STRCP (M6502, CBM4S79, HV2, HV4, HV4R)
CopyText:
    tya
    jsr AllocateForFac
    ldx StringPointer
    ldy StringPointer+1
    jsr CopyFrom
    ; Falls into PushTemporary.
    .endproc

    ;; Copies <NewDescriptor> to the next temporary descriptor and marks the result as a string.
    ;;
    ;; Only the low byte of <LastTemporary> is updated; its high byte must already identify page zero.
    ;; The overflow check tests equality with the end of the temporary stack.
    ;; Out: FacMantissa3 = temporary descriptor pointer (low byte), FacMantissa4 = 0, ValueType = string ($FF)
    ;; Errors: FORMULA TOO COMPLEX if no temporary descriptor is available
    ;; Entry:
    ;;   ToError = jumps to <ReportError> with the error in X; both allocators branch here with OUT OF MEMORY
    ;; Also: PUTNEW (M6502, ASTIL, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc PushTemporary
    ldx NextTemporary
    cpx #<(TemporaryDescriptors+DESCRIPTOR_SIZE*TEMPORARY_COUNT)
    bne Store
    ldx #<ERROR_FORMULA_TOO_COMPLEX

;; Jumps to <ReportError> with the error in X; both allocators branch here with OUT OF MEMORY.
;; Also: ERRGO2 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
ToError:
    jmp ReportError

;; Stores the descriptor and advances <NextTemporary> and <LastTemporary>.
;; Also: PUTNW1 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
Store:
    lda NewDescriptor
    sta StringDescriptor::LENGTH,x
    lda NewDescriptor+1
    sta StringDescriptor::ADDRESS,x
    lda NewDescriptor+2
    sta StringDescriptor::ADDRESS+1,x
    ldy #$00
    stx FacMantissa3
    sty FacMantissa4
    .if clearFacOverflow
        sty FacExtension
    .endif
    dey
    sty ValueType
    stx LastTemporary
    inx
    inx
    inx
    stx NextTemporary
    rts
    .endproc
    .endscope

.endmacro

;; Emits the selected string-space allocator, <Strings::ReserveSpace>, immediately before the matching
;; <Strings::CollectGarbage>.
;;
;; Each allocator is a whole <Strings::ReserveSpace> of its own, since the two share only their first instruction;
;; each opens the scope and the routine itself, so that the documentation names its labels in the routine.
;; Parameters: linkedStrings = 1 for the BASIC 4 linked allocator, 0 for ordinary unlinked allocation
.macro StringAllocation linkedStrings
    .assert linkedStrings = 0 || linkedStrings = 1, "linkedStrings must be 0 or 1."

    .if linkedStrings
        LinkedStringAllocation
    .else
        UnlinkedStringAllocation
    .endif

.endmacro
