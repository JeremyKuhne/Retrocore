; retrocore: style=strict
; Derived from Microsoft's BASIC for 6502 (m6502.asm, MIT license; see LICENSE in this folder).

.include "MsBasic.Families.asm"

; MICROSOFT 6502 BASIC: STRING FUNCTIONS AND BYTE CONVERSION
;
; These entries use the platform's string allocator and temporary-descriptor release routines.
; The switches separately select argument checking, the slice preamble's return sequence, the shared
; `LEN`/`ASC` jump, and the instruction used to put a zero terminator after a `VAL` argument.

;; Emits `CHR$`, slicing, `LEN`, `ASC`, byte conversion and `VAL` through <SetTextPointer::Done>.
;; Parameters: rejectZeroSlices = 1 to reject zero `LEFT$`/`RIGHT$` counts in <Functions::SliceArguments>, 0 to
;;   reject only `MID$`'s zero start,
;;   indirectReturn = 1 to return from <Functions::SliceArguments> through the writable jump operand, 0 to restore
;;   the stack return,
;;   sharedLenJump = 1 for <Functions::Asc> to jump through `LEN`'s conversion, 0 to jump directly to <ReturnByte>,
;;   zeroTermViaY = 1 to use `TYA` for <Functions::Val>'s terminator, 0 to load zero immediately
.macro StringFunctions rejectZeroSlices, indirectReturn, sharedLenJump, zeroTermViaY
    .assert rejectZeroSlices = 0 || rejectZeroSlices = 1, "rejectZeroSlices must be 0 or 1."
    .assert indirectReturn = 0 || indirectReturn = 1, "indirectReturn must be 0 or 1."
    .assert sharedLenJump = 0 || sharedLenJump = 1, "sharedLenJump must be 0 or 1."
    .assert zeroTermViaY = 0 || zeroTermViaY = 1, "zeroTermViaY must be 0 or 1."

    .scope Functions continued

    ;; Returns `CHR$(n)`, a one-byte string containing the value of n.
    ;;
    ;; It discards the function dispatcher's return, so that <CallFunction> does not check for a number.
    ;; Errors: ILLEGAL QUANTITY if the argument cannot be converted to a byte
    ;; Also: CHR (M6502)
    .proc Chr
    jsr ConvertToByte
    txa
    pha
    lda #$01
    jsr Strings::Allocate
    pla
    ldy #$00
    sta (NewDescriptor+1),y
    pla
    pla

;; Jumps to <Strings::PushTemporary>.
;; Also: RLZRET (M6502)
ToPushTemporary:
    jmp Strings::PushTemporary
    .endproc

    ;; Returns the leftmost requested characters, or the whole string if the count exceeds its length.
    ;;
    ;; Errors: ILLEGAL QUANTITY for a zero count where `rejectZeroSlices` is 1
    ;; Also: LEFT (M6502)
    .proc Left
    jsr SliceArguments
    cmp (DescriptorPointer),y
    tya
    ; Falls into Slice.
    .endproc

    ;; Shared by `LEFT$`, `RIGHT$` and `MID$`: allocates the slice, releases the source and copies from its start
    ;; offset, then pushes the result as a temporary.
    ;; In: A = the start offset, X = the count, carry = clear to use them, set to take the whole string from offset
    ;;   0, DescriptorPointer = the source descriptor, Y = 0
    ;; Entry:
    ;;   CountInX = takes the count from X; <Mid> branches here
    ;;   CountInA = pushes the count in A, allocates it and releases the source descriptor; <Mid> branches here
    ;; Also: RLEFT (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc Slice
    bcc PushStart
    lda (DescriptorPointer),y
    tax
    tya

;; Pushes the start offset.
;; Also: RLEFT1 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
PushStart:
    pha

;; Takes the count from X; <Mid> branches here.
;; Also: RLEFT2 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
CountInX:
    txa

;; Pushes the count in A, allocates it and releases the source descriptor; <Mid> branches here.
;; Also: RLEFT3 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
CountInA:
    pha
    jsr Strings::Allocate
    lda DescriptorPointer
    ldy DescriptorPointer+1
    jsr Strings::ReleaseDescriptor
    pla
    tay
    pla
    clc
    adc Pointer1
    sta Pointer1
    bcc Copy
    inc Pointer1+1

;; Copies the characters and pushes the result.
;; Also: PULMOR (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
Copy:
    tya
    jsr Strings::CopyBytes
    jmp Strings::PushTemporary
    .endproc

    ;; Returns the rightmost requested characters, or the whole string if the count exceeds its length.
    ;;
    ;; Errors: ILLEGAL QUANTITY for a zero count where `rejectZeroSlices` is 1
    ;; Also: RIGHT (M6502)
    .proc Right
    jsr SliceArguments
    clc
    sbc (DescriptorPointer),y
    eor #$FF
    jmp Slice
    .endproc

    ;; Returns `MID$(string, start [, length])`, with a one-based start and an optional length.
    ;;
    ;; A start beyond the end produces an empty string; a length extending past the end is shortened.
    ;;
    ;; Errors: ILLEGAL QUANTITY for a zero start
    ;; Also: MID (M6502)
    .proc Mid
    lda #$FF
    sta FacMantissa4
    jsr GetCurrentCharacter
    cmp #')'
    beq HaveLength
    jsr CheckComma
    jsr EvaluateByte

;; Gets the descriptor and start with <Functions::SliceArguments>.
;; Also: MID2 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
HaveLength:
    jsr SliceArguments
    ; `rejectZeroSlices` is 1 in AppleSoft and, by default, BASIC 1, and 0 in BASIC 2 and 4.
    .if .not rejectZeroSlices
        .if indirectReturn
            txa
        .endif
        beq ToIllegalQuantityError
    .endif
    dex
    txa
    pha
    clc
    ldx #$00
    sbc (DescriptorPointer),y
    bcs Slice::CountInX
    eor #$FF
    cmp FacMantissa4
    bcc Slice::CountInA
    lda FacMantissa4
    bcs Slice::CountInA
    .endproc

    ;; Checks the closing parenthesis and retrieves the stacked string descriptor and byte argument.
    ;;
    ;; The dispatcher's return address is discarded. Where `indirectReturn` is 1 (BASIC 1), the return increments
    ;; only the saved low byte, so its continuation wraps within the same page when that byte was $FF; the stack
    ;; return (`indirectReturn` = 0) carries normally.
    ;; The stack holds the preamble return, dispatcher return, byte argument, and descriptor low and high bytes.
    ;; The stack return sets zero from the argument; the indirect return sets it from the incremented return byte.
    ;; Out: A = byte argument, X = byte argument, Y = 0, DescriptorPointer = descriptor address
    ;; Errors: ILLEGAL QUANTITY for a zero byte argument where `rejectZeroSlices` is 1
    ;; Also: PREAM (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc SliceArguments
    jsr CheckCloseParenthesis
    pla
    .if indirectReturn
        sta FunctionJump+1
        pla
        sta FunctionJump+2
    .else
        tay
        pla
        sta FunctionJump+1
    .endif
    pla
    pla
    pla
    tax
    pla
    sta DescriptorPointer
    pla
    sta DescriptorPointer+1
    .if .not indirectReturn
        lda FunctionJump+1
        pha
        tya
        pha
    .endif
    ldy #$00
    txa
    .if rejectZeroSlices
        beq ToIllegalQuantityError
    .endif
    .if indirectReturn
        inc FunctionJump+1
        jmp (FunctionJump+1)
    .else
        rts
    .endif
    .endproc

    ;; Returns the length of a string in <Fac>.
    ;;
    ;; Where `sharedLenJump` is 1 (BASIC 1), <Asc> jumps to this routine's `ToFloat`, the jump to <ReturnByte>.
    ;; Errors: TYPE MISMATCH if <Fac> is not a string
    ;; Also: LEN (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc Len
    jsr ReleaseArgument
    .if sharedLenJump
;; Jumps to <ReturnByte>; <Asc> jumps here.
ToFloat:
    .endif
    jmp ReturnByte
    .endproc

    ;; Checks and releases a string, returning its length and character address for string functions.
    ;; Out: A = length, Y = length, zero = set for an empty string, X = 0, Pointer1 = character address,
    ;;   ValueType = numeric
    ;; Errors: TYPE MISMATCH if <Fac> is not a string
    ;; Also: LEN1 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc ReleaseArgument
    jsr Strings::ReleaseFacString
    ldx #$00
    stx ValueType
    tay
    rts
    .endproc

    ;; Returns the first character's byte value in <Fac>.
    ;; Errors: TYPE MISMATCH if <Fac> is not a string, ILLEGAL QUANTITY for an empty string
    ;; Also: ASC (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc Asc
    jsr ReleaseArgument
    beq ToIllegalQuantityError
    ldy #$00
    lda (Pointer1),y
    tay
    .if sharedLenJump
        jmp Len::ToFloat
    .else
        jmp ReturnByte
    .endif
    .endproc

    ;; Jumps to <IllegalQuantityError>, shared by the string functions, <ConvertToByte> and the memory statements.
    ;; Also: GOFUC (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc ToIllegalQuantityError
    jmp IllegalQuantityError
    .endproc
    .endscope

    ;; Advances past the current character and reads a byte-valued numeric expression.
    ;; Also: GTBYTC (M6502, ASTIL, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc SkipAndEvaluateByte
    jsr GetNextCharacter
    ; Falls into EvaluateByte.
    .endproc

    ;; Reads a byte-valued numeric expression.
    ;; Out: X = value, A = the current character, as <GetCurrentCharacter> returns it, TextPointer = terminating
    ;;   character
    ;; Errors: TYPE MISMATCH for a string, ILLEGAL QUANTITY if the value is outside the byte range
    ;; Also: GETBYT (M6502, ASTIL, CBM4S79, K4S79, HV1, HV1R, HV2, HV4, HV4R, HVK4)
    .proc EvaluateByte
    jsr EvaluateNumber
    ; Falls into ConvertToByte.
    .endproc

    ;; Converts <Fac> to a nonnegative byte and refreshes the current text character.
    ;; Out: X = value, A = the current character, as <GetCurrentCharacter> returns it
    ;; Errors: ILLEGAL QUANTITY if the value is outside the byte range
    ;; Also: CONINT (M6502, ASTIL, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc ConvertToByte
    jsr FacToNonnegativeInteger
    ldx FacMantissa3
    bne Functions::ToIllegalQuantityError
    ldx FacMantissa4

;; Jumps to <GetCurrentCharacter>.
;; Also: CHRGO2 (M6502)
ToGetCurrentCharacter:
    jmp GetCurrentCharacter
    .endproc

    .scope Functions continued

    ;; Converts the numeric prefix of a string to <Fac>; an empty string yields zero.
    ;;
    ;; The byte immediately after the counted characters must be writable. It is saved and replaced with zero for
    ;; <Float::ReadNumber>; on success, that byte and the caller's <TextPointer> are restored. An error from
    ;; <Float::ReadNumber> bypasses restoration.
    ;; Errors: TYPE MISMATCH if <Fac> is not a string
    ;; Also: VAL (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc Val
    jsr ReleaseArgument
    bne NotEmpty
    jmp Float::SetZero

;; A nonempty string: saves <TextPointer> and points it at the characters.
NotEmpty:
    ldx TextPointer
    ldy TextPointer+1
    stx SecondStringPointer
    sty SecondStringPointer+1
    ldx Pointer1
    stx TextPointer
    clc
    adc Pointer1
    sta Pointer2
    ldx Pointer1+1
    stx TextPointer+1
    bcc SetEnd
    inx

;; Saves the byte after the string, writes a terminator and parses the number.
;; Also: VAL2 (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
SetEnd:
    stx Pointer2+1
    ldy #$00
    lda (Pointer2),y
    pha
    ; BASIC 4 takes the zero from Y.
    .if zeroTermViaY
        tya
    .else
        lda #$00
    .endif
    sta (Pointer2),y
    jsr GetCurrentCharacter
    jsr Float::ReadNumber
    pla
    ldy #$00
    sta (Pointer2),y
    ; Falls into SetTextPointer.
    .endproc
    .endscope

    ;; Sets <TextPointer> from <SecondStringPointer>.
    ;;
    ;; After <Strings::FromTextUntil> that moves past the scanned text; after <Functions::Val> it restores the caller's
    ;; position.
    ;; Also: ST2TXT (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
    .proc SetTextPointer
    ldx SecondStringPointer
    ldy SecondStringPointer+1
    stx TextPointer
    sty TextPointer+1

;; Returns.
;; Also: VALRTS (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
Done:
    rts
    .endproc
.endmacro
