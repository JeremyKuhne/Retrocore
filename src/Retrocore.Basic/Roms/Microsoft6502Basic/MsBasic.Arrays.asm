; retrocore: style=strict
; Derived from Microsoft's BASIC for 6502 (m6502.asm, MIT license; see LICENSE in this folder).

.include "MsBasic.Families.asm"

; MICROSOFT 6502 BASIC: ARRAY ALLOCATION AND INDEXING

;; Emits array parsing, lookup, allocation and indexing.
;; Parameters: existingArrays = 1 to support Apple's existing-array lookup,
;;             clearWithY = 1 to initialize the allocation counter with Y,
;;             saveOffsetHigh = 1 to retain the corrected high byte of the element offset
.macro ArrayLookup existingArrays, clearWithY, saveOffsetHigh
    .assert existingArrays = 0 || existingArrays = 1, "existingArrays is 0 or 1."
    .assert clearWithY = 0 || clearWithY = 1, "clearWithY is 0 or 1."
    .assert saveOffsetHigh = 0 || saveOffsetHigh = 1, "saveOffsetHigh is 0 or 1."

    .scope Variables continued

    ;; Parses subscripts and locates or creates an array.
    ;;
    ;; The array descriptor contains the two name bytes, total byte length (low byte first), a dimension
    ;; count, and one two-byte bound per dimension (high byte first). Each bound is the maximum index plus
    ;; one. A new implicitly dimensioned array has bounds 0 through 10 in every dimension. Subscripts and
    ;; type flags are stacked while recursive expressions are evaluated.
    ;;
    ;; Where `existingArrays` is 1 (AppleSoft), <Variables::ChooseArrayLookup> enters at `Search` to skip the
    ;; subscripts.
    ;; Also: ISARY (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc FindArray
    lda Dimensioning
    ora IntegerType
    pha
    lda ValueType
    pha
    ldy #$00

;; Evaluates one subscript and swaps it under the saved flags on the stack; loops while a comma follows.
;; Also: INDLOP (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
NextSubscript:
    tya
    pha
    lda VariableName+1
    pha
    lda VariableName
    pha
    jsr EvaluateSubscript
    pla
    sta VariableName
    pla
    sta VariableName+1
    pla
    tay
    tsx
    lda Stack + 2,x
    pha
    lda Stack + 1,x
    pha
    lda ArrayIndex
    sta Stack + 2,x
    lda ArrayIndex+1
    sta Stack + 1,x
    iny
    jsr GetCurrentCharacter
    cmp #','
    beq NextSubscript
    sty Counter
    jsr CheckCloseParenthesis
    pla
    sta ValueType
    pla
    sta IntegerType
    and #$7F
    sta Dimensioning

    .if existingArrays
;; Starts the table search at <ArraysStart>; <Variables::ChooseArrayLookup> enters here to skip the subscripts.
Search:
    .endif
    ldx ArraysStart
    lda ArraysStart+1

;; Points <SourceStart> at the next array header and stops at <ArraysEnd>.
;; Also: LOPFDA (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
CheckEnd:
    stx SourceStart
    sta SourceStart+1
    cmp ArraysEnd+1
    bne CompareName
    cpx ArraysEnd
    .if existingArrays
        beq ArrayMissing
    .else
        beq CreateArray
    .endif

;; Compares the header's two name bytes with <VariableName>.
;; Also: LOPFDV (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
CompareName:
    ldy #$00
    lda (SourceStart),y
    iny
    cmp VariableName
    bne NextArray
    lda VariableName+1
    cmp (SourceStart),y
    beq ArrayFound

;; Adds the header's length to <SourceStart>; on an address carry falls into <BadSubscriptError>, which a table that
;; ends below $FFFF never reaches.
;; Also: NMARY1 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
NextArray:
    iny
    lda (SourceStart),y
    clc
    adc SourceStart
    tax
    iny
    lda (SourceStart),y
    adc SourceStart+1
    bcc CheckEnd
    ; Falls into BadSubscriptError.
    .endproc
    .endscope

    ;; Reports a bad subscript.
    ;;
    ;; It loads the error and skips <IllegalQuantityError>'s load with a `BIT`.
    ;; Errors: BAD SUBSCRIPT
    ;; Also: BSERR (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc BadSubscriptError
    ldx #<ERROR_BAD_SUBSCRIPT
    .byte $2C                   ; BIT absolute skips the next two bytes
    ; Falls into IllegalQuantityError.
    .endproc

    ;; Reports ILLEGAL QUANTITY.
    ;; Errors: ILLEGAL QUANTITY
    ;; Entry:
    ;;   ToError = jumps to <ERROR> with the error in X; <Variables::ArrayFound> branches here with REDIM'D ARRAY
    ;; Also: FCERR (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc IllegalQuantityError
    ldx #<ERROR_ILLEGAL_QUANTITY

;; Jumps to <ERROR> with the error in X; <Variables::ArrayFound> branches here with REDIM'D ARRAY.
;; Also: ERRGO3 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
ToError:
    jmp ERROR
    .endproc

    .scope Variables continued

    ;; Goes on to the element of an array <Variables::FindArray> found, or reports REDIM'D ARRAY when dimensioning.
    ;;
    ;; Where `existingArrays` is 1 (AppleSoft), a nonzero <SubscriptMode> (the existing-array lookup) returns at once
    ;; with carry set and the header at <SourceStart>.
    ;; In: SourceStart = the array's header, Counter = the number of subscripts on the stack
    ;; Errors: REDIM'D ARRAY when dimensioning, BAD SUBSCRIPT for a different number of subscripts
    ;; Also: GOTARY (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc ArrayFound
    ldx #<ERROR_REDIMENSIONED_ARRAY
    lda Dimensioning
    bne IllegalQuantityError::ToError
    .if existingArrays
        lda SubscriptMode
        beq CheckDimensions
        sec
        rts

;; An ordinary reference: sets <ArrayPointer> and compares the number of subscripts with the header's.
CheckDimensions:
    .endif
    jsr ElementsStart
    lda Counter
    ldy #ArrayHeader::DIMENSIONS
    cmp (SourceStart),y
    bne BadSubscriptError
    jmp ElementAddress
    .endproc

    .if existingArrays
        ;; Goes on to create a missing array, or reports OUT OF DATA for the existing-array lookup (AppleSoft).
        ;; In: SubscriptMode = zero for an ordinary reference
        ;; Errors: OUT OF DATA for the existing-array lookup
        .proc ArrayMissing
        lda SubscriptMode
        beq CreateArray
        ldx #<ERROR_OUT_OF_DATA
        jmp ERROR
        .endproc
    .endif

    ;; Builds an array descriptor and clears its values after checking that the allocation fits.
    ;;
    ;; <Statements::Dim> supplies each upper bound; implicit arrays use 11 elements per dimension. <MultiplyByBound>
    ;; checks for overflow while multiplying the dimensions by the element size. <Statements::Dim> returns after
    ;; allocation; a normal reference continues into <ElementAddress> to find the requested element.
    ;; In: SourceStart = where the header goes (<ArraysEnd>), Counter = the number of subscripts on the stack
    ;; Errors: OUT OF MEMORY when the array does not fit
    ;; Also: NOTFDD (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc CreateArray
    jsr ElementsStart
    jsr CheckFreeMemory
    .if clearWithY
        ldy #$00
        sty LinearIndex+1
    .else
        lda #$00
        tay
        sta LinearIndex+1
    .endif
    ldx #FLOAT_SIZE
    lda VariableName
    sta (SourceStart),y
    bpl CheckSecond
    dex

;; Element size so far: 5, minus 1 if the first name byte has bit 7 set; now tests the second byte.
;; Also: NOTFLT (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
CheckSecond:
    iny
    lda VariableName+1
    sta (SourceStart),y
    bpl StoreSize
    dex
    dex

;; Saves the element size (5, 3 or 2) in <LinearIndex> and writes the dimension count.
;; Also: STOMLT (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
StoreSize:
    stx LinearIndex
    lda Counter
    iny
    iny
    iny
    sta (SourceStart),y

;; Takes the next bound: 11 by default, or the stacked DIM subscript plus one.
;; Also: LOPPTA (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
NextDimension:
    ldx #DEFAULT_BOUND
    lda #$00
    bit Dimensioning
    bvc StoreBound
    pla
    clc
    adc #$01
    tax
    pla
    adc #$00

;; Writes the bound high byte first and multiplies it into the running size.
;; Also: NOTDIM (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
StoreBound:
    iny
    sta (SourceStart),y
    iny
    txa
    sta (SourceStart),y
    jsr MultiplyByBound
    stx LinearIndex
    sta LinearIndex+1
    ldy Pointer1
    dec Counter
    bne NextDimension
    adc ArrayPointer+1
    bcs ElementAddress::ToOutOfMemoryError
    sta ArrayPointer+1
    tay
    txa
    adc ArrayPointer
    bcc CheckRoom
    iny
    beq ElementAddress::ToOutOfMemoryError

;; Checks the new <ArraysEnd> with <CheckFreeMemory> and stores it, then clears the values page by page.
;; Also: GREASE (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
CheckRoom:
    jsr CheckFreeMemory
    sta ArraysEnd
    sty ArraysEnd+1
    lda #$00
    inc LinearIndex+1
    ldy LinearIndex
    beq NextPage

;; Zeroes the bytes of one page of values downward.
;; Also: ZERITA (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
ClearLoop:
    dey
    sta (ArrayPointer),y
    bne ClearLoop

;; Moves <ArrayPointer> down a page and counts pages, then writes the header's length.
;; Also: DECCUR (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
NextPage:
    dec ArrayPointer+1
    dec LinearIndex+1
    bne ClearLoop
    inc ArrayPointer+1
    sec
    lda ArraysEnd
    sbc SourceStart
    ldy #ArrayHeader::LENGTH
    sta (SourceStart),y
    lda ArraysEnd+1
    iny
    sbc SourceStart+1
    sta (SourceStart),y
    lda Dimensioning
    bne ElementAddress::Done
    iny
    ; Falls into ElementAddress.
    .endproc

    ;; Checks each subscript against its bound and computes the element's linear offset.
    ;;
    ;; The accumulated offset is multiplied by each successive dimension and increased by the next subscript,
    ;; then scaled by the element size and added to <ArrayPointer>. Where `saveOffsetHigh` is 0 (BASIC 1), the final
    ;; offset's high byte is not stored before the scaling, which uses the high byte left from the step before: an
    ;; element whose offset is 256 or more can be misplaced, BASIC 1's array bug.
    ;; In: SourceStart = the array's header, Y = the offset of its dimension count, ArrayPointer = its first value
    ;; Out: VariablePointer = address of the selected array element, A = its low byte, Y = its high byte
    ;; Errors: BAD SUBSCRIPT if a subscript is out of bounds, OUT OF MEMORY if the offset overflows
    ;; Entry:
    ;;   ToOutOfMemoryError = jumps to <OMERR>; <CreateArray> and <MultiplyUnsigned> branch here on overflow
    ;;   Done = returns; <CreateArray> (for DIM) and <RejectDirectMode> branch here as the nearest `RTS`
    ;; Also: GETDEF (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc ElementAddress
    lda (SourceStart),y
    sta Counter
    lda #$00
    sta LinearIndex

;; Pops the next subscript into <ArrayIndex> and compares it with the bound, high byte first.
;; Also: INLPNM (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
NextSubscript:
    sta LinearIndex+1
    iny
    pla
    tax
    sta ArrayIndex
    pla
    sta ArrayIndex+1
    cmp (SourceStart),y
    bcc SkipLow
    bne ToBadSubscriptError
    iny
    txa
    cmp (SourceStart),y
    bcc InBounds

;; Jumps to <BadSubscriptError> for a subscript at or above its bound.
;; Also: BSERR7 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
ToBadSubscriptError:
    jmp BadSubscriptError

;; Jumps to <OMERR>; <CreateArray> and <MultiplyUnsigned> branch here on overflow.
;; Also: OMERR1 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
ToOutOfMemoryError:
    jmp OMERR

;; High byte below the bound: skips the bound's low byte.
;; Also: INLPN2 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
SkipLow:
    iny

;; Multiplies the index so far by this dimension's bound and adds the subscript's low byte.
;; Also: INLPN1 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
InBounds:
    lda LinearIndex+1
    ora LinearIndex
    clc
    beq AddSubscript
    jsr MultiplyByBound
    txa
    adc ArrayIndex
    tax
    tya
    ldy Pointer1

;; Adds the subscript's high byte and counts down the dimensions.
;; Also: ADDIND (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
AddSubscript:
    adc ArrayIndex+1
    stx LinearIndex
    dec Counter
    bne NextSubscript
    .if saveOffsetHigh
        sta LinearIndex+1
    .endif
    ldx #FLOAT_SIZE
    lda VariableName
    bpl CheckSecond
    dex

;; Element size so far from the first name byte; now tests the second.
;; Also: NOTFL1 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
CheckSecond:
    lda VariableName+1
    bpl ScaleBySize
    dex
    dex

;; Multiplies the linear index by the element size and adds <ArrayPointer> to give <VariablePointer>.
;; Also: STOML1 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
ScaleBySize:
    stx Addend
    lda #$00
    jsr MultiplyUnsigned
    txa
    adc ArrayPointer
    sta VariablePointer
    tya
    adc ArrayPointer+1
    sta VariablePointer+1
    tay
    lda VariablePointer

;; Returns; <CreateArray> (for DIM) and <RejectDirectMode> branch here as the nearest `RTS`.
;; Also: DIMRTS (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
Done:
    rts
    .endproc
    .endscope

.endmacro
