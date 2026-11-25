; retrocore: style=strict
;; The rest of making an array, which B3DimnH.asm starts (<Variables::InitializeArray>), finding an array's element
;; (<Variables::ElementAddress>), the unsigned multiply that sizes and indexes arrays, `FRE`, `POS` and `VPOS`, and
;; user functions: `DEF` and `FN`.

; ---------------------------------------------------------------------------------------------------------------------
; Making an array
; ---------------------------------------------------------------------------------------------------------------------

.scope Variables continued

;; Writes a new array's entry, which <Variables::CreateArray> has made room for at <SourceStart>, and zeroes its
;; elements; then, unless in `DIM`, finds the element the subscripts name.
;; In: DestinationEnd = the simple variables' new start, SourceStart = the entry, Counter = the count of subscripts, the
;;   subscripts on the stack, LinearIndex = the entry's size, VariableSizes+1 = the name's length plus 3,
;;   VariableNamePointer = the name in the program
;; Out: VariablePointer = the value's address, and the rest as from <FindVariable>
;; See: <Variables::ElementAddress>
.proc InitializeArray
    ldx DestinationEnd+1                    ; the simple variables now start at DestinationEnd
    ldy DestinationEndXByte
    lda DestinationEnd
    sta VariablesStart
    stx VariablesStart+1
    sty VariablesStartXByte
    lda Counter
    sta Pointer1+1                          ; the dimensions left
    lda #0
    jsr ElementsStart::SizesPlus            ; ArrayPointer: where the sizes go
    ldy #0

;; Writes each dimension's size, high byte first: one more than its subscript in `DIM`, or 11.
;;
;; The subscripts come off the stack last first, so the last subscript's size is written first.
;; Also: INDLP1 (BB13)
WriteSize:
    ldx #DEFAULT_HIGHEST_SUBSCRIPT+1        ; not `DIM`
    lda #0
    bit Dimensioning
    bvc StoreSize
    pla                                     ; `DIM`: the subscript's low byte
    clc
    adc #1
    tax
    pla                                     ; and high byte, plus the carry
    adc #0

;; Stores the size's two bytes, high byte first.
;; Also: NTDIMD (BB13)
StoreSize:
    sta (ArrayPointer),Y
    iny
    txa
    sta (ArrayPointer),Y
    iny
    dec Pointer1+1
    bne WriteSize
    ldy #0                                  ; the entry's length, low byte first
    lda LinearIndex
    sta (SourceStart),Y
    lda LinearIndex+1
    iny
    sta (SourceStart),Y
    ldx VariableSizes+1
    dex
    dex
    stx Pointer1                            ; the offset of the name's last character

;; Copies the name from the program into the entry, upper-casing it, then writes the type byte and the count of
;; dimensions.
;; Also: NAMLOP (BB13)
CopyName:
    dey
    lda (VariableNamePointer),Y
    iny
    iny                                     ; the entry's name starts at offset 2
    cmp #'a'
    bcc Upper
    sbc #'a'-'A'
Upper:
    sta (SourceStart),Y
    cpy Pointer1
    bne CopyName
    lda ValueType
    iny
    sta (SourceStart),Y
    iny
    lda Counter
    sta (SourceStart),Y
    jsr ElementsStart                       ; ArrayPointer: the elements
    ldx VariablesStart+1
    ldy ArrayPointer

;; Zeroes the elements, from <ArrayPointer> up to <VariablesStart>, the start of the simple variables.
;;
;; <ArrayPointer>'s low byte is kept in Y and its own low byte zero, so the store indexes through the page.
;; Also: ZERITA (BB13)
ClearLoop:
    lda #0
    sta ArrayPointer
    sta (ArrayPointer),Y
    iny
    bne CheckEnd
    inc ArrayPointer+1                      ; the next page
    lda ArrayPointer+1
    cmp #POINTER_PAGE_LIMIT
    bcc CheckEnd
    sbc #POINTER_PAGE_LIMIT-POINTER_PAGE_FIRST ; page 2 through the next X-byte
    sta ArrayPointer+1
    inc ArrayPointerXByte

;; Goes on until <VariablesStart>; then returns in `DIM`, and otherwise finds the element.
;; Also: CHKUPR (BB13)
CheckEnd:
    cpx ArrayPointer+1
    bne ClearLoop
    lda ArrayPointerXByte
    cmp VariablesStartXByte
    bne ClearLoop
    cpy VariablesStart
    bcc ClearLoop
    lda Dimensioning
    bne ElementAddress::ToSetIntegerFlag    ; `DIM`: done
    ; Falls into ElementAddress.
.endproc

; ---------------------------------------------------------------------------------------------------------------------
; Finding an element
; ---------------------------------------------------------------------------------------------------------------------

;; Points <VariablePointer> at the element the subscripts on the stack name, checking each against its dimension's size.
;;
;; The offset is built from the last subscript to the first: at each, it is multiplied by that dimension's size and
;; the subscript added, so the first subscript varies fastest. Times the element's size, it is added to the elements'
;; address.
;; In: SourceStart = the array's entry, Counter = the count of subscripts, on the stack (the low byte on top, the last
;;   first)
;; Out: VariablePointer = the element's address (<VariablePointerXByte> its bank), ArrayElementFound = $80, A =
;;   <VariablePointer>'s low byte, Y = its page
;; Errors: <ERROR_BAD_SUBSCRIPT> = a subscript not below its size, <ERROR_OUT_OF_MEMORY> = an offset of 64K or more
;; Entry:
;;   ToOutOfMemoryError = ends with `OUT OF MEMORY`; <Variables::MultiplyUnsigned> branches here
;;   SetArrayFlags = sets <VariablePointerXByte> from A, and <ArrayElementFound>, and finishes;
;;   <Variables::ArrayNotFound> goes here
;;   ToSetIntegerFlag = finishes as <FindVariable::SetIntegerFlag> does; <Variables::InitializeArray> branches here
;;     for `DIM`
;; See: <Variables::MultiplyUnsigned>, <Variables::ElementsStart>
;; Also: GETDEF (BB13)
.proc ElementAddress
    lda Counter
    sta Pointer1+1                          ; the subscripts left
    lda #0
    jsr ElementsStart::SizesPlus            ; ArrayPointer: the sizes
    ldy #0
    sty LinearIndex                         ; the offset so far
    sty LinearIndex+1

;; Takes the next subscript off the stack and checks it is below its dimension's size.
;; Also: INLPNM (BB13)
NextSubscript:
    pla                                     ; the low byte
    tax
    sta ArrayIndex
    pla                                     ; the high byte
    sta ArrayIndex+1
    cmp (ArrayPointer),Y                    ; against the size's high byte
    bcc SkipLow
    bne ToBadSubscriptError
    iny
    txa
    cmp (ArrayPointer),Y                    ; and low byte
    bcc InBounds

;; Ends the statement with BAD SUBSCRIPT.
;; Also: BSERR7 (BB13)
ToBadSubscriptError:
    jmp BadSubscriptError

;; Ends the statement with `OUT OF MEMORY`, for <Variables::MultiplyUnsigned>.
;; Also: OMERR1 (BB13)
ToOutOfMemoryError:
    jmp ReportOutOfMemory

;; Steps Y past the size's high byte, for a subscript whose high byte is below it.
;; Also: INLPN2 (BB13)
SkipLow:
    iny

;; Multiplies the offset by this dimension's size and adds the subscript; an offset of zero just takes it.
;; Also: INLPN1 (BB13)
InBounds:
    lda LinearIndex+1
    ora LinearIndex
    clc
    beq AddSubscript
    sty Pointer1
    lda (ArrayPointer),Y                    ; the size's low byte
    pha
    dey
    lda (ArrayPointer),Y                    ; and high byte
    tax
    pla
    tay
    jsr MultiplyUnsigned
    txa
    adc ArrayIndex
    tax
    tya
    ldy Pointer1

;; Adds the subscript's high byte, and goes on to the next subscript; past the last, works out the element's address.
;; Also: ADDIND (BB13)
AddSubscript:
    adc ArrayIndex+1
    iny
    stx LinearIndex
    sta LinearIndex+1
    dec Pointer1+1
    bne NextSubscript
    jsr ElementsStart                       ; ArrayPointer: the elements
    ldx #0
    ldy VariableSizes                       ; the element's size
    jsr MultiplyUnsigned
    txa
    adc ArrayPointer                        ; carry is clear after MultiplyUnsigned
    sta VariablePointer
    tya
    adc ArrayPointer+1
    ldy ArrayPointerXByte
    jsr Memory::NormalizeAfterAdd
    sta VariablePointer+1
    tya
    adc #0

;; Sets <VariablePointerXByte> and <ArrayElementFound> ($80, an array element), then finishes as
;; <FindVariable::SetIntegerFlag> does.
;; In: A = the element's bank, VariablePointer = its address
;; Out: A = <VariablePointer>'s low byte, Y = its page
;; Also: DIMRTS2 (BB13)
SetArrayFlags:
    sta VariablePointerXByte
    lda #$80
    sta ArrayElementFound
    ldy VariablePointer+1
    lda VariablePointer

;; Finishes the variable search in <FindVariable::SetIntegerFlag>, which sorts out an integer's type.
;; Also: DIMRTS1 (BB13)
ToSetIntegerFlag:
    jmp FindVariable::SetIntegerFlag
.endproc

; ---------------------------------------------------------------------------------------------------------------------
; Unsigned multiply
; ---------------------------------------------------------------------------------------------------------------------

;; Multiplies <LinearIndex> by a 16-bit number, for array sizes and offsets.
;; In: Y = the number's low byte, X = its high byte, LinearIndex = the other factor
;; Out: X = the product's low byte, Y = its high byte, carry = clear
;; Uses: A, LinearIndex (left zero), DigitCount, Addend
;; Errors: <ERROR_OUT_OF_MEMORY> = a product of 64K or more
;; Entry:
;;   Done = returns; <RejectDirectMode> branches here as the nearest RTS
;; See: <Variables::ElementAddress>, <Variables::CreateArray>
;; Also: UMULT (BB13)
.proc MultiplyUnsigned
;; The bits of <LinearIndex>, one round each.
BITS = 16

    lda #BITS
    sta DigitCount
    stx Addend+1
    sty Addend
    ldx #0
    ldy #0

;; Doubles the product, then adds the number when the next bit of <LinearIndex>, from the top, is set.
;; Also: UMULTC (BB13)
NextBit:
    txa
    asl
    tax
    tya
    rol
    tay
    bcs ElementAddress::ToOutOfMemoryError
    asl LinearIndex
    rol LinearIndex+1
    bcc CountBit
    clc
    txa
    adc Addend
    tax
    tya
    adc Addend+1
    tay
    bcs ElementAddress::ToOutOfMemoryError

;; Counts the bits down.
;; Also: UMLCNT (BB13)
CountBit:
    dec DigitCount
    bne NextBit

;; Returns.
;; Also: UMLRTS (BB13)
Done:
    rts
.endproc

.endscope

; ---------------------------------------------------------------------------------------------------------------------
; `FRE`, `POS` and `VPOS`
; ---------------------------------------------------------------------------------------------------------------------

.scope Functions continued

;; The `FRE` function: collects the strings' garbage, then gives the bytes free between <VariablesEnd> and
;; <StringsBottom>.
;;
;; <Segments::Grow>, with A = 0, first grows BASIC's memory segment as far as SOS lets it. The count is made as a long
;; integer, up to 24 bits, and turned into a real.
;; Out: Fac = the bytes free, as a real
;; See: <Strings::CollectGarbage>, <LongInteger::ToReal>
;; Also: NOFREF (BB13)
.proc Fre
    jsr LongInteger::SetFacToZero
    lda #0
    sta CollectionState
    jsr Segments::Grow
    jsr Strings::CollectGarbage
    sec
    lda StringsBottom                       ; StringsBottom - VariablesEnd
    sbc VariablesEnd
    sta Fac+7
    lda StringsBottom+1
    sbc VariablesEnd+1
    ldy StringsBottomXByte
    ldx VariablesEndXByte
    jsr Memory::PageDifference
    sta Fac+6
    sty Fac+5
    jmp LongInteger::ToReal
.endproc

.endscope

;; Puts a signed 16-bit integer in the <Fac> as a real.
;; In: A = the high byte, Y = the low byte
;; Out: Fac = the real, ValueType = 0
;; See: <ReturnByte>
;; Also: GIVAYF (BB13)
.proc ReturnSignedWord
    ldx #VALUE_TYPE_REAL
    stx ValueType
    sta FacMantissa1
    sty FacMantissa1+1
    ldx #Float::WORD_EXPONENT
    jmp Float::ConvertSignedWord
.endproc

.scope Functions continued

;; The `POS` function: the cursor's column, counting from 1.
;; Out: Fac = the column, as a real
;; Entry:
;;   CountFromOne = adds 1 to Y and gives it as a real; <Functions::VPos> goes here
;; See: <Functions::VPos>, <ReadCursorPosition>
;; Also: POS (BB13)
.proc Pos
    jsr ReadCursorPosition
    ldy Console::CursorColumn

;; Adds 1, to count from 1 as `TAB` and `HPOS` do, and gives Y as a real.
;; Also: VPOS2 (BB13)
CountFromOne:
    iny
    ; Falls into ReturnByte.
.endproc

.endscope

;; Puts Y, 0-255, in the <Fac> as a real.
;; In: Y = the number
;; Out: Fac = the real, ValueType = 0
;; See: <ReturnSignedWord>
;; Also: SNGFLT (BB13)
.proc ReturnByte
    lda #0
    sec
    beq ReturnSignedWord                    ; always
.endproc

.scope Functions continued

;; The `VPOS` function: the cursor's line, counting from 1.
;; Out: Fac = the line, as a real
;; See: <Functions::Pos>
;; Also: DOVPOS (BB13)
.proc VPos
    jsr ReadCursorPosition
    ldy Console::CursorLine
    jmp Pos::CountFromOne
.endproc

.endscope

; ---------------------------------------------------------------------------------------------------------------------
; User functions
;
; `DEF FN` names a function of one numeric argument with a one-line formula, as in `DEF FN A(X) = X * X + 1`. Its
; entry is a simple variable of type Variables::TYPE_FUNCTION and its name (the letters after `FN`, without a type
; character), whose six-byte value is the formula's address in the program (three bytes, just past the `=`) and the
; argument variable's (three bytes, relative to VariablesStart, as `FOR` keeps its variable). An entry `DEF` has not
; filled is all zero.
; ---------------------------------------------------------------------------------------------------------------------

;; Refuses a statement in direct mode, where <CurrentLine>'s high byte is $FF.
;; Errors: <ERROR_ILLEGAL_DIRECT> = in direct mode
;; Entry:
;;   UndefinedFunction = ends the statement with UNDEF'D FUNCTION; <Functions::Fn> and
;;   <Modules::ToUndefinedFunctionError> go here
;; Also: ERRDIR (BB13)
.proc RejectDirectMode
    ldx CurrentLine+1
    inx
    bne Variables::MultiplyUnsigned::Done   ; a running program
    ldx #ERROR_ILLEGAL_DIRECT
    .byte $2C                               ; BIT absolute skips UndefinedFunction's LDX

;; Ends the statement with UNDEF'D FUNCTION.
;; Also: ERRGUF (BB13)
UndefinedFunction:
    ldx #ERROR_UNDEFINED_FUNCTION
    jmp ReportError
.endproc

.scope Statements continued

;; The `DEF` statement: notes the formula's address and the argument variable in the function's entry, and skips the
;; formula.
;;
;; <RequireNumber> lets the argument be an integer variable as well as a real one, but `FN` stores a four-byte real into
;; it and saves and restores four bytes, so an integer argument (two bytes) has the two bytes after it written over.
;; Errors: <ERROR_ILLEGAL_DIRECT> = in direct mode
;; See: <ReadFunctionName>, <Functions::Fn>, <Variables::SimpleVariableOffset>
;; Also: DEF (BB13)
.proc Def
    jsr ReadFunctionName
    jsr RejectDirectMode
    jsr CheckOpenParenthesis
    lda #$80
    sta SubscriptMode                       ; no subscripts on the argument
    jsr FindVariableToAssign
    jsr Variables::SimpleVariableOffset     ; AssignedVariable relative to VariablesStart
    jsr RequireNumber
    jsr CheckCloseParenthesis
    lda #'='
    jsr CheckCharacter
    lda AssignedVariableXByte
    pha
    lda AssignedVariable+1
    pha
    lda AssignedVariable
    pha
    lda TextPointerXByte
    pha
    lda TextPointer+1
    pha
    lda TextPointer
    pha
    jsr SkipStatement                       ; skips the formula
    ldx #Variables::SIZE_FUNCTION-1         ; six bytes to the entry
    jmp PopToFunctionPointer
.endproc

.endscope

;; Reads `FN` and the function's name, finding or making its entry.
;; Out: FunctionPointer = the entry's value (<FunctionPointerXByte> its bank), ValueType = 0
;; Errors: <ERROR_SYNTAX> = no `FN`, or a bad name
;; Entry:
;;   AfterFn = finds or makes the entry of the function named at <TextPointer>; <Functions::Fn> enters here
;; Also: GETFNM (BB13)
.proc ReadFunctionName
    lda #TOKEN_FN
    jsr RequireTwoByteToken

;; Finds or makes the entry of the function named at <TextPointer>.
;;
;; <SubscriptMode> gets the name's first character with bit 7 set: bits 7 and 6 both set for a letter, which
;; <FindVariable::KeepDimensionFlag> takes as an `FN` name.
;; In: A = the name's first character
;; Out: FunctionPointer = the entry's value (<FunctionPointerXByte> its bank), ValueType = 0
;; Also: GETFN1 (BB13)
AfterFn:
    ora #$80
    sta SubscriptMode
    jsr FindVariable::KeepDimensionFlag
    sta FunctionPointer
    sty FunctionPointer+1
    lda VariablePointerXByte
    sta FunctionPointerXByte
    ldx #VALUE_TYPE_REAL                    ; the argument is real
    stx ValueType
    jmp RequireNumber
.endproc

.scope Functions continued

;; Evaluates `FN`: puts the argument's value in the argument variable, evaluates the function's formula, then gives
;; the variable its old value back.
;;
;; The old value, the text pointer and the variable's address are kept on the stack, so a function's formula can use
;; `FN` itself. A function whose `DEF` has not run, or whose `DEF` line is gone (no `=` where the formula was), is an
;; UNDEF'D FUNCTION error.
;; Out: Fac = the function's value
;; Errors: <ERROR_UNDEFINED_FUNCTION> = no `DEF`, <ERROR_SYNTAX> = more after the formula
;; See: <Statements::Def>, <ReadFunctionName::AfterFn>, <Float::StoreFac::AtPointer>
;; Also: FNDOER (BB13)
.proc Fn
    jsr GetCurrentCharacter
    jsr ReadFunctionName::AfterFn
    lda FunctionPointerXByte
    pha
    lda FunctionPointer+1
    pha
    lda FunctionPointer
    pha
    jsr EvaluateParenthesized               ; the argument
    jsr RequireNumber
    pla
    sta FunctionPointer
    pla
    sta FunctionPointer+1
    pla
    sta FunctionPointerXByte
    ldy #3
    lda (FunctionPointer),Y                 ; the argument variable, relative to VariablesStart
    sta Pointer1
    iny
    lda (FunctionPointer),Y
    sta Pointer1+1
    iny
    lda (FunctionPointer),Y
    bne Defined                             ; a zero bank: `DEF` has not filled the entry

;; Ends the statement with UNDEF'D FUNCTION.
;; Also: NOFUN (BB13)
ToUndefinedFunction:
    jmp RejectDirectMode::UndefinedFunction
Defined:
    sta Pointer1XByte
    ldx #Pointer1
    jsr Variables::SimpleVariableOffset::OfPointerAtX ; makes Pointer1 an address again
    ldy #Variables::SIZE_REAL-1

;; Pushes the argument variable's old value, four bytes.
;; Also: DEFSTF (BB13)
SaveArgument:
    lda (Pointer1),Y
    pha
    dey
    bpl SaveArgument
    lda Pointer1XByte
    jsr Float::StoreFac::AtPointer          ; the argument into the variable, leaving Y = 0
    lda TextPointerXByte
    pha
    lda TextPointer+1
    pha
    lda TextPointer
    pha
    lda (FunctionPointer),Y                 ; the formula
    sta TextPointer
    iny
    lda (FunctionPointer),Y
    sta TextPointer+1
    iny
    lda (FunctionPointer),Y
    sta TextPointerXByte
    lda Pointer1XByte
    pha
    lda Pointer1+1
    pha
    lda Pointer1
    pha
    jsr BackUpTextPointer                   ; back to the `=`
    jsr GetCurrentCharacter
    cmp #'='
    bne ToUndefinedFunction                 ; the `DEF` line is gone
    jsr GetNextCharacter
    jsr EvaluateNumber
    pla                                     ; FunctionPointer: the argument variable now
    sta FunctionPointer
    pla
    sta FunctionPointer+1
    pla
    sta FunctionPointerXByte
    jsr GetCurrentCharacter
    beq RestoreText
    jmp SyntaxError                         ; more after the formula
RestoreText:
    pla
    sta TextPointer
    pla
    sta TextPointer+1
    pla
    sta TextPointerXByte
    ldx #Variables::SIZE_REAL-1             ; four bytes back to the variable
    ; Falls into PopToFunctionPointer.
.endproc

.endscope

;; Pulls X+1 bytes off the stack into <FunctionPointer>'s bytes 0 up: `DEF`'s entry, or `FN`'s argument variable's old
;; value.
;; In: X = the count less 1, FunctionPointer = where they go
;; Also: DEFFIN (BB13)
.proc PopToFunctionPointer
    ldy #$FF

;; Stores the next byte.
;; Also: DEFLOP (BB13)
Loop:
    iny
    pla
    sta (FunctionPointer),Y
    dex
    bpl Loop
    rts
.endproc
