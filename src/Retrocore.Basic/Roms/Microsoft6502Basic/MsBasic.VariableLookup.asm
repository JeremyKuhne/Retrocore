; retrocore: style=strict
; Derived from Microsoft's BASIC for 6502 (m6502.asm, MIT license; see LICENSE in this folder).

.include "MsBasic.Families.asm"

; MICROSOFT 6502 BASIC: VARIABLE NAMES AND SIMPLE-VARIABLE LOOKUP
;
; Emit VariableSearch, the separately shared LetterTest, and SimpleVariableLookup in that order.
; The integer-conversion entries follow; AppleSoft then emits ExistingArrayEntry before <Variables::FindArray>.

;; Emits the variable-name parser and scalar-table search up to the letter test.
;; Parameters: fixedVectors = 1 to emit Apple's fixed ROM vectors, vectorByte = the model byte at $E006,
;;   rejectAnyFlag = 1 to reject integer names for any nonzero subscript flag, 0 to test bit 7 only,
;;   existingArrays = 1 for Apple's existing-array lookup mode, clearWithY = 1 to clear the flag using Y,
;;   longFound = 1 when the found-variable branch must jump to <Variables::ValueAddress>
.macro VariableSearch fixedVectors, vectorByte, rejectAnyFlag, existingArrays, clearWithY, longFound
    .assert fixedVectors = 0 || fixedVectors = 1, "fixedVectors must be 0 or 1."
    .assert vectorByte >= 0 && vectorByte <= 255, "vectorByte must fit in one byte."
    .assert rejectAnyFlag = 0 || rejectAnyFlag = 1, "rejectAnyFlag must be 0 or 1."
    .assert existingArrays = 0 || existingArrays = 1, "existingArrays must be 0 or 1."
    .assert clearWithY = 0 || clearWithY = 1, "clearWithY must be 0 or 1."
    .assert longFound = 0 || longFound = 1, "longFound must be 0 or 1."

    ;; Parses a variable name and finds or creates its value.
    ;;
    ;; The name starts with a letter; only its first two letters or digits are significant, though further letters
    ;; and digits are consumed. A dollar suffix sets the high bit of the second name byte and makes a string;
    ;; a percent suffix sets both name bits and selects an integer. Subscripts can recursively evaluate expressions.
    ;; Scalar entries are seven bytes.
    ;; An absent scalar read by the expression evaluator can return a shared zero without setting <VariablePointer>.
    ;; The array check ORs the following character with <SubscriptMode> before comparing it with '('. PET rejects a
    ;; percent suffix for any nonzero flag; AppleSoft tests bit 7 instead and, when bit 7 is clear, uses bit 6
    ;; for the cassette `STORE` and `RECALL` existing-array lookup. That lookup returns carry set without an element
    ;; address, or reports OUT OF DATA when the array is absent.
    ;; In: TextPointer = first character, SubscriptMode = subscript mode, decimal = clear
    ;; Out: A = low value address and Y = high value address for a scalar or an array element,
    ;;   TextPointer = next non-space character,
    ;;   ValueType = $FF for a string or 0 for a number, IntegerType = $80 for an integer or 0 otherwise
    ;; Errors: SYNTAX for an invalid first character, a disallowed integer name or a name the PET reserves
    ;;   (<Variables::CheckReservedName>), OUT OF MEMORY when a new variable does not fit (<Variables::Create>), and
    ;;   the array path's: BAD SUBSCRIPT, REDIM'D ARRAY, ILLEGAL QUANTITY, OUT OF MEMORY, and OUT OF DATA for
    ;;   AppleSoft's existing-array lookup
    ;; Entry:
    ;;   WithDimensionFlag = starts with A = first character and X = dimension flag
    ;;   KeepDimensionFlag = starts with A = first character, retaining the current dimension flag
    ;; See: <IsLetter>, <Variables::NotFound>, <Variables::ValueAddress>, <Variables::FindArray>
    ;; Also: PTRGET (M6502, ASTIL, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc FindVariable
    ldx #$00
    jsr GetCurrentCharacter

;; Starts with A = first character and X = dimension flag.
;; Also: PTRGT1 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
WithDimensionFlag:
    stx Dimensioning

;; Starts with A = first character, retaining the current dimension flag.
;; Also: PTRGT2 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
KeepDimensionFlag:
    sta VariableName
    jsr GetCurrentCharacter
    jsr IsLetter
    bcs ValidFirst

;; Jumps to <SyntaxError> for a bad first character or a forbidden `%`.
;; Also: INTERR (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
ToSyntaxError:
    jmp SyntaxError

;; Clears <ValueType> and <IntegerType> and reads the second character.
;; Also: PTRGT3 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
ValidFirst:
    ldx #$00
    stx ValueType
    stx IntegerType
    .if fixedVectors
        jmp AfterVectors
        .assert * = $E000, "AppleSoft's fixed vectors must start at $E000."
        jmp INIT
        jmp MAIN
        .byte vectorByte

;; The code after AppleSoft's fixed jumps at $E000 (to <INIT> and <MAIN>) and its model byte.
AfterVectors:
    .endif
    jsr GetNextCharacter
    bcc SecondCharacter
    jsr IsLetter
    bcc CheckSuffix

;; Keeps a letter or digit as the second name character.
;; Also: ISSEC (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
SecondCharacter:
    tax

;; Consumes further letters and digits.
;; Also: EATEM (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
SkipRest:
    jsr GetNextCharacter
    bcc SkipRest
    jsr IsLetter
    bcs SkipRest

;; `$` makes a string: sets <ValueType> and the second byte's bit 7.
;; Also: NOSEC (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
CheckSuffix:
    cmp #'$'
    bne CheckInteger
    lda #$FF
    sta ValueType
    bne MarkSecond

;; `%` makes an integer (a syntax error where subscripts are not allowed) and sets both bytes' bit 7.
;; Also: NOTSTR (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
CheckInteger:
    cmp #'%'
    bne CheckSubscript
    lda SubscriptMode
    .if rejectAnyFlag
        bne ToSyntaxError
    .else
        bmi ToSyntaxError
    .endif
    lda #$80
    sta IntegerType
    ora VariableName
    sta VariableName

;; Sets bit 7 of the second name byte and consumes the suffix.
;; Also: TURNON (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
MarkSecond:
    txa
    ora #$80
    tax
    jsr GetNextCharacter

;; Stores the second byte and compares the next character, ORed with <SubscriptMode>, with `(`.
;; Also: STRNAM (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
CheckSubscript:
    stx VariableName+1
    sec
    ora SubscriptMode
    sbc #'('
    .if existingArrays
        bne NoParenthesis

;; Jumps to <Variables::ChooseArrayLookup>.
ToChooseArrayLookup:
        jmp Variables::ChooseArrayLookup

;; No `(`: bit 7 of <SubscriptMode> searches the scalars, bit 6 goes to the existing-array lookup, and a zero
;; <SubscriptMode> falls into <SearchScalars>.
NoParenthesis:
        bit SubscriptMode
        bmi SearchScalars
        bvs ToChooseArrayLookup

    .else
        bne SearchScalars
        jmp Variables::FindArray
    .endif

;; Clears <SubscriptMode> and starts at <VariablesStart>.
SearchScalars:
    ; BASIC 4 clears with Y, the others with A.
    .if clearWithY
        ldy #$00
        sty SubscriptMode
    .else
        lda #$00
        sta SubscriptMode
    .endif
    lda VariablesStart
    ldx VariablesStart+1
    .if .not clearWithY
        ldy #$00
    .endif

;; Stores the entry pointer's high byte (start, and on a page crossing).
;; Also: STXFND (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
SetEntryHigh:
    stx SourceStart+1

;; Stores the low byte; at <ArraysStart> the name is not found.
;; Also: LOPFND (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
CheckEnd:
    sta SourceStart
    cpx ArraysStart+1
    bne CompareName
    cmp ArraysStart
    beq Variables::NotFound

;; Compares both name bytes with <VariableName>.
;; Also: LOPFN (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
CompareName:
    lda VariableName
    cmp (SourceStart),y
    bne Advance
    lda VariableName+1
    iny
    cmp (SourceStart),y
    ; BASIC 4 jumps to the value's address; the others branch.
    .if longFound
        bne SecondMismatch
        jmp Variables::ValueAddress

;; The second byte differs: restores Y.
SecondMismatch:
        dey
    .else
        beq Variables::ValueAddress
        dey
    .endif

;; Steps past an entry and loops.
;;
;; Only a table that wrapped past $FFFF would fall out of the routine, into the code after it.
;; Also: NOTIT (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
Advance:
    clc
    lda SourceStart
    adc #.sizeof(Variable)
    bcc CheckEnd
    inx
    bne SetEntryHigh
    .endproc
.endmacro

;; Emits the absent-variable handling, scalar insertion and array-data pointer calculation.
;; Parameters: callerHigh = 1 to check both bytes of the evaluator's return address,
;;   inlineZero = 1 to emit two zero bytes here, ownZero = 1 for AppleSoft's own <ZeroVariable> rather than
;;   <ZeroValue>,
;;   clockNames = 1 to recognize TI and TI$, statusName = 1 to protect ST,
;;   diskNames = 1 to protect DS and DS$, linkedArrays = 1 to adjust BASIC 4's string back-links,
;;   countEntry = 1 to give <Variables::ElementsStart> AppleSoft's entry with the count in A
.macro SimpleVariableLookup callerHigh, inlineZero, ownZero, clockNames, statusName, diskNames, linkedArrays, countEntry
    .assert callerHigh = 0 || callerHigh = 1, "callerHigh must be 0 or 1."
    .assert inlineZero = 0 || inlineZero = 1, "inlineZero must be 0 or 1."
    .assert ownZero = 0 || ownZero = 1, "ownZero must be 0 or 1."
    .assert clockNames = 0 || clockNames = 1, "clockNames must be 0 or 1."
    .assert statusName = 0 || statusName = 1, "statusName must be 0 or 1."
    .assert diskNames = 0 || diskNames = 1, "diskNames must be 0 or 1."
    .assert linkedArrays = 0 || linkedArrays = 1, "linkedArrays must be 0 or 1."
    .assert countEntry = 0 || countEntry = 1, "countEntry must be 0 or 1."

    .scope Variables continued

    ;; Handles a missing scalar, returning a shared zero to the expression evaluator or creating an entry.
    ;;
    ;; The stacked return address is compared with <ISVRET>-1. PET compares only the low byte, so another
    ;; caller with the same low byte also receives the zero; AppleSoft checks the high byte as well.
    ;; The zero return does not update <VariablePointer>. Otherwise reserved names are checked before insertion.
    ;; With clock support, TI is rejected and TI$ returns the zero; ST is rejected with channel status support.
    ;; BASIC 4 additionally rejects DS and DS$. Other names proceed to insertion.
    ;; In: VariableName = encoded name, Y = 0, decimal = clear
    ;; See: <Variables::ReturnZero>, <Variables::Create>
    ;; Also: NOTFNS (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc NotFound
    pla
    pha
    cmp #<(ISVRET-1)
    bne CheckReservedName
    .if callerHigh
        tsx
        lda Stack + 2,x
        cmp #>(ISVRET-1)
        bne CheckReservedName
    .endif
    ; Falls into ReturnZero.
    .endproc

    ;; Returns the address of the shared zero without allocating a variable.
    ;;
    ;; BASIC 1 and AppleSoft place two zero bytes here. BASIC 2 and 4 use bytes within <Float::Half> instead.
    ;; Out: A = low address, Y = high address
    ;; Also: LDZR (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc ReturnZero
    .if ownZero
        lda #<ZeroVariable
        ldy #>ZeroVariable
    .else
        lda #<ZeroValue
        ldy #>ZeroValue
    .endif
    rts
    .endproc
    .endscope

    .if inlineZero
        .if ownZero
;; Two zero bytes that an absent scalar reads: AppleSoft's own, rather than <ZeroValue>.
ZeroVariable:
        .else
;; Two zero bytes that an absent scalar reads.
;;
;; BASIC 2 and 4 have no such bytes here: their <ZeroValue> lies inside <Float::Half>.
;; Also: ZERO (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
ZeroValue:
        .endif
        .byte $00, $00
    .endif

    .scope Variables continued

    ;; Rejects the names the PET reserves, and returns the zero for `TI$`; other names fall into <Create>.
    ;;
    ;; Where `clockNames` is 1 (the PET), `TI` is rejected with a syntax error and `TI$` gets the zero; where
    ;; `statusName` is 1 (the PET), `ST`; where `diskNames` is 1 (BASIC 4), `DS` and `DS$`. In AppleSoft it is empty.
    ;; In: VariableName = encoded name, Y = 0
    ;; Errors: SYNTAX for a reserved name
    ;; Also: NOTEVL (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc CheckReservedName
    .if clockNames || statusName || diskNames
        lda VariableName
        ldy VariableName+1
    .endif
    .if clockNames
        cmp #'T'
        bne CheckStatus
        cpy #('I'+$80)
        beq ReturnZero
        cpy #'I'
        bne CheckStatus
    .elseif statusName || diskNames
        jmp CheckStatus
    .endif
    .if clockNames || statusName || diskNames
;; Jumps to <SyntaxError> for a reserved name.
;; Also: GOBADV (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
ToSyntaxError:
        jmp SyntaxError
    .endif

;; Checks for `ST`.
;; Also: QSTAVR (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
CheckStatus:
    .if statusName
        cmp #'S'
        .if diskNames
            bne CheckDiskStatus
        .else
            bne Create
        .endif
        cpy #'T'
        beq ToSyntaxError
    .endif
    .if diskNames
;; Checks for `DS` and `DS$`.
CheckDiskStatus:
        cmp #'D'
        bne Create
        cpy #'S'
        beq ToSyntaxError
        cpy #('S'+$80)
        beq ToSyntaxError
    .endif
    .endproc

    ;; Inserts a zero-initialized seven-byte scalar entry before the array table.
    ;;
    ;; <MoveRangeUp> moves existing arrays upward and checks that the new end fits. When enabled, the linked-string
    ;; collector's array back-links are adjusted after the move. The entry's two name bytes precede five zero bytes.
    ;; In: VariableName = encoded name, decimal = clear
    ;; Out: VariablePointer = address of the new value, A = its low byte, Y = its high byte
    ;; Errors: OUT OF MEMORY if the enlarged tables cannot fit
    ;; See: <MoveRangeUp>, <Variables::ValueAddress>
    ;; Also: VAROK (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc Create
    lda ArraysStart
    ldy ArraysStart+1
    sta SourceStart
    sty SourceStart+1
    lda ArraysEnd
    ldy ArraysEnd+1
    sta SourceEnd
    sty SourceEnd+1
    clc
    adc #.sizeof(Variable)
    bcc SetNewEnd
    iny

;; Stores the arrays' new end and moves them.
;; Also: NOTEVE (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
SetNewEnd:
    sta DestinationEnd
    sty DestinationEnd+1
    jsr MoveRangeUp
    lda DestinationEnd
    ldy DestinationEnd+1
    iny
    sta ArraysStart
    sty ArraysStart+1
    .if linkedArrays
        sta ArrayPointer
        sty ArrayPointer+1

;; Adjusts back-links for live strings in arrays moved to make room for a scalar.
;;
;; String descriptors are three bytes. For a nonempty string, the descriptor address is stored immediately
;; after its characters. If that back-link address is at or above <StringsBottom>, its value is increased by the
;; entry's seven bytes.
;; Numeric arrays, empty strings and back-links below <StringsBottom> are left alone.
;; In: ArrayPointer = first moved array, ArraysEnd = end of array storage, decimal = clear
NextArray:
        lda ArrayPointer
        ldx ArrayPointer+1

;; Stops at <ArraysEnd>.
CheckArraysEnd:
        cpx ArraysEnd+1
        bne ReadArray
        cmp ArraysEnd
        beq WriteEntry

;; Advances <ArrayPointer> past the array and, for a string array, points <Pointer1> at its first element.
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
        ldy #$00
        asl a
        adc #.sizeof(ArrayHeader)
        adc Pointer1
        sta Pointer1
        bcc ScanElements
        inc Pointer1+1

;; Stops at the array's end.
ScanElements:
        ldx Pointer1+1
        cpx ArrayPointer+1
        bne CheckElement
        cmp ArrayPointer
        beq CheckArraysEnd

;; Skips an empty string or one below <StringsBottom>.
CheckElement:
        ldy #$00
        lda (Pointer1),y
        beq Advance
        iny
        clc
        adc (Pointer1),y
        sta SourceEnd
        tax
        iny
        lda (Pointer1),y
        adc #$00
        sta SourceEnd+1
        cmp StringsBottom+1
        bcc Advance
        bne MoveLink
        cpx StringsBottom
        bcc Advance

;; Adds the entry's seven bytes to the back-link after the string's characters.
MoveLink:
        ldy #$00
        lda (SourceEnd),y
        adc #.sizeof(Variable) - 1      ; carry is set, so this adds the entry's size
        sta (SourceEnd),y
        iny
        lda (SourceEnd),y
        adc #$00
        sta (SourceEnd),y

;; Steps <Pointer1> to the next descriptor.
Advance:
        lda #DESCRIPTOR_SIZE
        clc
        adc Pointer1
        sta Pointer1
        bcc ScanElements
        inc Pointer1+1
        bne ScanElements

;; Back-links done: writes the new entry.
WriteEntry:
    .endif
    ldy #$00
    lda VariableName
    sta (SourceStart),y
    iny
    lda VariableName+1
    sta (SourceStart),y
    lda #$00
    iny
    sta (SourceStart),y
    iny
    sta (SourceStart),y
    iny
    sta (SourceStart),y
    iny
    sta (SourceStart),y
    iny
    sta (SourceStart),y
    ; Falls into ValueAddress.
    .endproc

    ;; Returns the value address two bytes after the scalar entry at <SourceStart>.
    ;; In: SourceStart = scalar entry address, decimal = clear
    ;; Out: A = low value address, Y = high value address, VariablePointer = value address
    ;; Also: FINPTR (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc ValueAddress
    lda SourceStart
    clc
    adc #$02
    ldy SourceStart+1
    bcc Store
    iny

;; Stores <VariablePointer> and returns.
;; Also: FINNOW (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
Store:
    sta VariablePointer
    sty VariablePointer+1
    rts
    .endproc

    ;; Computes the start of array values from the descriptor and dimension count.
    ;;
    ;; Where `countEntry` is 1 (AppleSoft), `FromCount` takes the count in A instead; `STORE` and `RECALL` call it.
    ;; In: SourceStart = array descriptor, Counter = number of dimensions, decimal = clear
    ;; Out: ArrayPointer = first value address, A = its low byte, Y = its high byte
    ;; Also: FMAPTR (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc ElementsStart
    lda Counter
    .if countEntry

;; Computes the start of array values with the dimension count already in A.
FromCount:
    .endif
    asl a
    adc #.sizeof(ArrayHeader)
    adc SourceStart
    ldy SourceStart+1
    bcc Store
    iny

;; Stores <ArrayPointer> and returns.
;; Also: JSRGM (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
Store:
    sta ArrayPointer
    sty ArrayPointer+1
    rts
    .endproc
    .endscope

.endmacro

;; Emits the AppleSoft entry for choosing an existing-array lookup.
.macro ExistingArrayEntry

    .scope Variables continued

    ;; Enters array parsing, or skips the subscripts for an existing-array lookup.
    ;; In: SubscriptMode = 0 for ordinary subscripts, nonzero for the existing-array path
    ;; See: <Variables::FindArray>, <Variables::FindArray::Search>
    .proc ChooseArrayLookup
    lda SubscriptMode
    bne FindArray::Search
    ; Falls into FindArray.
    .endproc
    .endscope

.endmacro
