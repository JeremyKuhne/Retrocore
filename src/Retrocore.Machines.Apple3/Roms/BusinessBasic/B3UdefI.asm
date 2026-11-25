; retrocore: style=strict
;; The rest of making an array, which B3DimnH.asm starts (<Variables::InitializeArray>), finding an array's element
;; (<Variables::ElementAddress>), the unsigned multiply that sizes and indexes arrays, `FRE`, `POS` and `VPOS`, and
;; user functions: `DEF` and `FN`.

; ---------------------------------------------------------------------------------------------------------------------
; Making an array
; ---------------------------------------------------------------------------------------------------------------------

.scope Variables continued

;; Writes a new array's entry, which <Variables::CreateArray> has made room for at <LOWTR>, and zeroes its elements;
;; then, unless in `DIM`, finds the element the subscripts name.
;; In: HIGHDS = the simple variables' new start, LOWTR = the entry, COUNT = the count of subscripts, the subscripts
;;   on the stack, CURTOL = the entry's size, VARNAM+1 = the name's length plus 3, TMPPTR = the name in the program
;; Out: VARPNT = the value's address, and the rest as from <FindVariable>
;; See: <Variables::ElementAddress>
.proc InitializeArray
    ldx HIGHDS+1                            ; the simple variables now start at HIGHDS
    ldy HIGHDSB
    lda HIGHDS
    sta SMVARS
    stx SMVARS+1
    sty SMVARSB
    lda COUNT
    sta INDEX+1                             ; the dimensions left
    lda #0
    jsr ElementsStart::SizesPlus            ; ARYPNT: where the sizes go
    ldy #0

;; Writes each dimension's size, high byte first: one more than its subscript in `DIM`, or 11.
;;
;; The subscripts come off the stack last first, so the last subscript's size is written first.
;; Also: INDLP1 (BB13)
WriteSize:
    ldx #DEFAULT_HIGHEST_SUBSCRIPT+1        ; not `DIM`
    lda #0
    bit DIMFLG
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
    sta (ARYPNT),Y
    iny
    txa
    sta (ARYPNT),Y
    iny
    dec INDEX+1
    bne WriteSize
    ldy #0                                  ; the entry's length, low byte first
    lda CURTOL
    sta (LOWTR),Y
    lda CURTOL+1
    iny
    sta (LOWTR),Y
    ldx VARNAM+1
    dex
    dex
    stx INDEX                               ; the offset of the name's last character

;; Copies the name from the program into the entry, upper-casing it, then writes the type byte and the count of
;; dimensions.
;; Also: NAMLOP (BB13)
CopyName:
    dey
    lda (TMPPTR),Y
    iny
    iny                                     ; the entry's name starts at offset 2
    cmp #'a'
    bcc Upper
    sbc #'a'-'A'
Upper:
    sta (LOWTR),Y
    cpy INDEX
    bne CopyName
    lda VALTYP
    iny
    sta (LOWTR),Y
    iny
    lda COUNT
    sta (LOWTR),Y
    jsr ElementsStart                       ; ARYPNT: the elements
    ldx VARTAB+1
    ldy ARYPNT

;; Zeroes the elements, from <ARYPNT> up to <VARTAB>, the start of the simple variables.
;;
;; <ARYPNT>'s low byte is kept in Y and its own low byte zero, so the store indexes through the page.
;; Also: ZERITA (BB13)
ClearLoop:
    lda #0
    sta ARYPNT
    sta (ARYPNT),Y
    iny
    bne CheckEnd
    inc ARYPNT+1                            ; the next page
    lda ARYPNT+1
    cmp #MAXPG
    bcc CheckEnd
    sbc #MAXPG-MINPG                        ; page 2 through the next X-byte
    sta ARYPNT+1
    inc ARYPNTB

;; Goes on until <VARTAB>; then returns in `DIM`, and otherwise finds the element.
;; Also: CHKUPR (BB13)
CheckEnd:
    cpx ARYPNT+1
    bne ClearLoop
    lda ARYPNTB
    cmp VARTABB
    bne ClearLoop
    cpy VARTAB
    bcc ClearLoop
    lda DIMFLG
    bne ElementAddress::ToSetIntegerFlag    ; `DIM`: done
    ; Falls into ElementAddress.
.endproc

; ---------------------------------------------------------------------------------------------------------------------
; Finding an element
; ---------------------------------------------------------------------------------------------------------------------

;; Points VARPNT at the element the subscripts on the stack name, checking each against its dimension's size.
;;
;; The offset is built from the last subscript to the first: at each, it is multiplied by that dimension's size and
;; the subscript added, so the first subscript varies fastest. Times the element's size, it is added to the elements'
;; address.
;; In: LOWTR = the array's entry, COUNT = the count of subscripts, on the stack (the low byte on top, the last first)
;; Out: VARPNT = the element's address (<VARPNTB> its bank), ISARA = $80, A = VARPNT's low byte, Y = its page
;; Errors: ERRBS = a subscript not below its size, ERROM = an offset of 64K or more
;; Entry:
;;   ToOutOfMemoryError = ends with OUT OF MEMORY; <Variables::MultiplyUnsigned> branches here
;;   SetArrayFlags = sets <VARPNTB> from A, and ISARA, and finishes; <Variables::ArrayNotFound> goes here
;;   ToSetIntegerFlag = finishes as <FindVariable::SetIntegerFlag> does; <Variables::InitializeArray> branches here
;;     for `DIM`
;; See: <Variables::MultiplyUnsigned>, <Variables::ElementsStart>
;; Also: GETDEF (BB13)
.proc ElementAddress
    lda COUNT
    sta INDEX+1                             ; the subscripts left
    lda #0
    jsr ElementsStart::SizesPlus            ; ARYPNT: the sizes
    ldy #0
    sty CURTOL                              ; the offset so far
    sty CURTOL+1

;; Takes the next subscript off the stack and checks it is below its dimension's size.
;; Also: INLPNM (BB13)
NextSubscript:
    pla                                     ; the low byte
    tax
    sta INDICE
    pla                                     ; the high byte
    sta INDICE+1
    cmp (ARYPNT),Y                          ; against the size's high byte
    bcc SkipLow
    bne ToBadSubscriptError
    iny
    txa
    cmp (ARYPNT),Y                          ; and low byte
    bcc InBounds

;; Ends the statement with BAD SUBSCRIPT.
;; Also: BSERR7 (BB13)
ToBadSubscriptError:
    jmp BadSubscriptError

;; Ends the statement with OUT OF MEMORY, for <Variables::MultiplyUnsigned>.
;; Also: OMERR1 (BB13)
ToOutOfMemoryError:
    jmp OMERR

;; Steps Y past the size's high byte, for a subscript whose high byte is below it.
;; Also: INLPN2 (BB13)
SkipLow:
    iny

;; Multiplies the offset by this dimension's size and adds the subscript; an offset of zero just takes it.
;; Also: INLPN1 (BB13)
InBounds:
    lda CURTOL+1
    ora CURTOL
    clc
    beq AddSubscript
    sty INDEX
    lda (ARYPNT),Y                          ; the size's low byte
    pha
    dey
    lda (ARYPNT),Y                          ; and high byte
    tax
    pla
    tay
    jsr MultiplyUnsigned
    txa
    adc INDICE
    tax
    tya
    ldy INDEX

;; Adds the subscript's high byte, and goes on to the next subscript; past the last, works out the element's address.
;; Also: ADDIND (BB13)
AddSubscript:
    adc INDICE+1
    iny
    stx CURTOL
    sta CURTOL+1
    dec INDEX+1
    bne NextSubscript
    jsr ElementsStart                       ; ARYPNT: the elements
    ldx #0
    ldy VARNAM                              ; the element's size
    jsr MultiplyUnsigned
    txa
    adc ARYPNT                              ; carry is clear after MultiplyUnsigned
    sta VARPNT
    tya
    adc ARYPNT+1
    ldy ARYPNTB
    jsr Memory::NormalizeAfterAdd
    sta VARPNT+1
    tya
    adc #0

;; Sets <VARPNTB> and <ISARA> ($80, an array element), then finishes as <FindVariable::SetIntegerFlag> does.
;; In: A = the element's bank, VARPNT = its address
;; Out: A = VARPNT's low byte, Y = its page
;; Also: DIMRTS2 (BB13)
SetArrayFlags:
    sta VARPNTB
    lda #$80
    sta ISARA
    ldy VARPNT+1
    lda VARPNT

;; Finishes the variable search in <FindVariable::SetIntegerFlag>, which sorts out an integer's type.
;; Also: DIMRTS1 (BB13)
ToSetIntegerFlag:
    jmp FindVariable::SetIntegerFlag
.endproc

; ---------------------------------------------------------------------------------------------------------------------
; Unsigned multiply
; ---------------------------------------------------------------------------------------------------------------------

;; Multiplies CURTOL by a 16-bit number, for array sizes and offsets.
;; In: Y = the number's low byte, X = its high byte, CURTOL = the other factor
;; Out: X = the product's low byte, Y = its high byte, carry = clear
;; Uses: A, CURTOL (left zero), DECCNT, ADDEND
;; Errors: ERROM = a product of 64K or more
;; Entry:
;;   Done = returns; <RejectDirectMode> branches here as the nearest RTS
;; See: <Variables::ElementAddress>, <Variables::CreateArray>
;; Also: UMULT (BB13)
.proc MultiplyUnsigned
;; The bits of <CURTOL>, one round each.
BITS = 16

    lda #BITS
    sta DECCNT
    stx ADDEND+1
    sty ADDEND
    ldx #0
    ldy #0

;; Doubles the product, then adds the number when the next bit of <CURTOL>, from the top, is set.
;; Also: UMULTC (BB13)
NextBit:
    txa
    asl
    tax
    tya
    rol
    tay
    bcs ElementAddress::ToOutOfMemoryError
    asl CURTOL
    rol CURTOL+1
    bcc CountBit
    clc
    txa
    adc ADDEND
    tax
    tya
    adc ADDEND+1
    tay
    bcs ElementAddress::ToOutOfMemoryError

;; Counts the bits down.
;; Also: UMLCNT (BB13)
CountBit:
    dec DECCNT
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

;; The `FRE` function: collects the strings' garbage, then gives the bytes free between <STREND> and <FRETOP>.
;;
;; <EXPAND>, with A = 0, first grows BASIC's memory segment as far as SOS lets it. The count is made as a long
;; integer, up to 24 bits, and turned into a real.
;; Out: FAC = the bytes free, as a real
;; See: <Strings::CollectGarbage>, <LMAKFLT>
;; Also: NOFREF (BB13)
.proc Fre
    jsr LONGST0
    lda #0
    sta GARBFL
    jsr EXPAND
    jsr Strings::CollectGarbage
    sec
    lda FRETOP                              ; FRETOP - STREND
    sbc STREND
    sta FAC+7
    lda FRETOP+1
    sbc STREND+1
    ldy FRETOPB
    ldx STRENDB
    jsr Memory::PageDifference
    sta FAC+6
    sty FAC+5
    jmp LMAKFLT
.endproc

.endscope

;; Puts a signed 16-bit integer in the FAC as a real.
;; In: A = the high byte, Y = the low byte
;; Out: FAC = the real, VALTYP = 0
;; See: <ReturnByte>
;; Also: GIVAYF (BB13)
.proc ReturnSignedWord
    ldx #VALUE_TYPE_REAL
    stx VALTYP
    sta FACHO
    sty FACHO+1
    ldx #WORD_EXPONENT
    jmp FLOATS
.endproc

.scope Functions continued

;; The `POS` function: the cursor's column, counting from 1.
;; Out: FAC = the column, as a real
;; Entry:
;;   CountFromOne = adds 1 to Y and gives it as a real; <Functions::VPos> goes here
;; See: <Functions::VPos>, <ReadCursorPosition>
;; Also: POS (BB13)
.proc Pos
    jsr ReadCursorPosition
    ldy CURX

;; Adds 1, to count from 1 as `TAB` and `HTAB` do, and gives Y as a real.
;; Also: VPOS2 (BB13)
CountFromOne:
    iny
    ; Falls into ReturnByte.
.endproc

.endscope

;; Puts Y, 0-255, in the FAC as a real.
;; In: Y = the number
;; Out: FAC = the real, VALTYP = 0
;; See: <ReturnSignedWord>
;; Also: SNGFLT (BB13)
.proc ReturnByte
    lda #0
    sec
    beq ReturnSignedWord                    ; always
.endproc

.scope Functions continued

;; The `VPOS` function: the cursor's line, counting from 1.
;; Out: FAC = the line, as a real
;; See: <Functions::Pos>
;; Also: DOVPOS (BB13)
.proc VPos
    jsr ReadCursorPosition
    ldy CURY
    jmp Pos::CountFromOne
.endproc

.endscope

; ---------------------------------------------------------------------------------------------------------------------
; User functions
;
; `DEF FN` names a function of one numeric argument with a one-line formula, as in `DEF FN A(X) = X * X + 1`. Its
; entry is a simple variable of type Variables::TYPE_FUNCTION and its name (the letters after `FN`, without a type
; character), whose six-byte value is the formula's address in the program (three bytes, just past the `=`) and the
; argument variable's (three bytes, relative to SMVARS, as `FOR` keeps its variable). An entry `DEF` has not filled
; is all zero.
; ---------------------------------------------------------------------------------------------------------------------

;; Refuses a statement in direct mode, where <CURLIN>'s high byte is $FF.
;; Errors: ERRID = in direct mode
;; Entry:
;;   UndefinedFunction = ends the statement with UNDEF'D FUNCTION; <Functions::Fn> and <PERFERR> go here
;; Also: ERRDIR (BB13)
.proc RejectDirectMode
    ldx CURLIN+1
    inx
    bne Variables::MultiplyUnsigned::Done   ; a running program
    ldx #ERRID
    .byte $2C                               ; BIT absolute skips UndefinedFunction's LDX

;; Ends the statement with UNDEF'D FUNCTION.
;; Also: ERRGUF (BB13)
UndefinedFunction:
    ldx #ERRUF
    jmp ERROR
.endproc

.scope Statements continued

;; The `DEF` statement: notes the formula's address and the argument variable in the function's entry, and skips the
;; formula.
;;
;; <CHKNUM> lets the argument be an integer variable as well as a real one, but `FN` stores a four-byte real into it
;; and saves and restores four bytes, so an integer argument (two bytes) has the two bytes after it written over.
;; Errors: ERRID = in direct mode
;; See: <ReadFunctionName>, <Functions::Fn>, <PNTREL>
;; Also: DEF (BB13)
.proc Def
    jsr ReadFunctionName
    jsr RejectDirectMode
    jsr CheckOpenParenthesis
    lda #$80
    sta SUBFLG                              ; no subscripts on the argument
    jsr MYPTRGET
    jsr PNTREL                              ; FORPNT relative to SMVARS
    jsr CHKNUM
    jsr CheckCloseParenthesis
    lda #'='
    jsr CheckCharacter
    lda FORPNTB
    pha
    lda FORPNT+1
    pha
    lda FORPNT
    pha
    lda TXTPTRB
    pha
    lda TXTPTR+1
    pha
    lda TXTPTR
    pha
    jsr DATA                                ; skips the formula
    ldx #Variables::SIZE_FUNCTION-1         ; six bytes to the entry
    jmp PopToFunctionPointer
.endproc

.endscope

;; Reads `FN` and the function's name, finding or making its entry.
;; Out: DEFPNT = the entry's value (<DEFPNTB> its bank), VALTYP = 0
;; Errors: ERRSN = no `FN`, or a bad name
;; Entry:
;;   AfterFn = finds or makes the entry of the function named at <TXTPTR>; <Functions::Fn> enters here
;; Also: GETFNM (BB13)
.proc ReadFunctionName
    lda #FNTK
    jsr MSTESC

;; Finds or makes the entry of the function named at <TXTPTR>.
;;
;; <SUBFLG> gets the name's first character with bit 7 set: bits 7 and 6 both set for a letter, which
;; <FindVariable::KeepDimensionFlag> takes as an `FN` name.
;; In: A = the name's first character
;; Out: DEFPNT = the entry's value (<DEFPNTB> its bank), VALTYP = 0
;; Also: GETFN1 (BB13)
AfterFn:
    ora #$80
    sta SUBFLG
    jsr FindVariable::KeepDimensionFlag
    sta DEFPNT
    sty DEFPNT+1
    lda VARPNTB
    sta DEFPNTB
    ldx #VALUE_TYPE_REAL                    ; the argument is real
    stx VALTYP
    jmp CHKNUM
.endproc

.scope Functions continued

;; Evaluates `FN`: puts the argument's value in the argument variable, evaluates the function's formula, then gives
;; the variable its old value back.
;;
;; The old value, the text pointer and the variable's address are kept on the stack, so a function's formula can use
;; `FN` itself. A function whose `DEF` has not run, or whose `DEF` line is gone (no `=` where the formula was), is an
;; UNDEF'D FUNCTION error.
;; Out: FAC = the function's value
;; Errors: ERRUF = no `DEF`, ERRSN = more after the formula
;; See: <Statements::Def>, <ReadFunctionName::AfterFn>, <FOURBYT>
;; Also: FNDOER (BB13)
.proc Fn
    jsr CHRGOT
    jsr ReadFunctionName::AfterFn
    lda DEFPNTB
    pha
    lda DEFPNT+1
    pha
    lda DEFPNT
    pha
    jsr EvaluateParenthesized               ; the argument
    jsr CHKNUM
    pla
    sta DEFPNT
    pla
    sta DEFPNT+1
    pla
    sta DEFPNTB
    ldy #3
    lda (DEFPNT),Y                          ; the argument variable, relative to SMVARS
    sta INDEX
    iny
    lda (DEFPNT),Y
    sta INDEX+1
    iny
    lda (DEFPNT),Y
    bne Defined                             ; a zero bank: `DEF` has not filled the entry

;; Ends the statement with UNDEF'D FUNCTION.
;; Also: NOFUN (BB13)
ToUndefinedFunction:
    jmp RejectDirectMode::UndefinedFunction
Defined:
    sta INDEXB
    ldx #INDEX
    jsr PNTRL1                              ; makes INDEX an address again
    ldy #Variables::SIZE_REAL-1

;; Pushes the argument variable's old value, four bytes.
;; Also: DEFSTF (BB13)
SaveArgument:
    lda (INDEX),Y
    pha
    dey
    bpl SaveArgument
    lda INDEXB
    jsr FOURBYT                             ; the argument into the variable, leaving Y = 0
    lda TXTPTRB
    pha
    lda TXTPTR+1
    pha
    lda TXTPTR
    pha
    lda (DEFPNT),Y                          ; the formula
    sta TXTPTR
    iny
    lda (DEFPNT),Y
    sta TXTPTR+1
    iny
    lda (DEFPNT),Y
    sta TXTPTRB
    lda INDEXB
    pha
    lda INDEX+1
    pha
    lda INDEX
    pha
    jsr BackUpTextPointer                   ; back to the `=`
    jsr CHRGOT
    cmp #'='
    bne ToUndefinedFunction                 ; the `DEF` line is gone
    jsr CHRGET
    jsr FRMNUM
    pla                                     ; DEFPNT: the argument variable now
    sta DEFPNT
    pla
    sta DEFPNT+1
    pla
    sta DEFPNTB
    jsr CHRGOT
    beq RestoreText
    jmp SyntaxError                         ; more after the formula
RestoreText:
    pla
    sta TXTPTR
    pla
    sta TXTPTR+1
    pla
    sta TXTPTRB
    ldx #Variables::SIZE_REAL-1             ; four bytes back to the variable
    ; Falls into PopToFunctionPointer.
.endproc

.endscope

;; Pulls X+1 bytes off the stack into DEFPNT's bytes 0 up: `DEF`'s entry, or `FN`'s argument variable's old value.
;; In: X = the count less 1, DEFPNT = where they go
;; Also: DEFFIN (BB13)
.proc PopToFunctionPointer
    ldy #$FF

;; Stores the next byte.
;; Also: DEFLOP (BB13)
Loop:
    iny
    pla
    sta (DEFPNT),Y
    dex
    bpl Loop
    rts
.endproc
