; retrocore: style=strict
; APPLESOFT: APPLE II STATEMENTS AND LOW-RESOLUTION GRAPHICS ($F1D5-$F3D7)
;
; Machine calls, slot I/O, low-resolution graphics and display controls are followed by memory limits, error
; trapping, program editing, display modes and cassette array transfer. ReadLowResCoordinates is also used by SCRN in
; AppleSoft.Expressions.asm. This module follows AppleSoft.Initialization.asm.

;; Low-resolution rows; a coordinate must be below it.
LOW_RES_ROWS = 48

;; Low-resolution columns; a column must be below it.
LOW_RES_COLUMNS = 40

;; Text screen rows; VTAB's row less one must be below it.
TEXT_ROWS = 24

;; <INVFLG> for normal text: every bit kept.
INVERSE_MASK_NORMAL = $FF

;; <INVFLG> for inverse text: bits 6 and 7 cleared.
INVERSE_MASK_INVERSE = $3F

;; <INVFLG> for flashing text: bit 7 cleared.
INVERSE_MASK_FLASH = $7F

;; <FlashMask> for flashing text: bit 6 set on printable characters.
FLASH_MASK_FLASH = $40

; Machine calls and low-resolution graphics

.scope Statements continued

;; `CALL`: evaluates an address into <LineNumber> and jumps through it; the called code's `rts` returns to the
;; statement loop.
;; Also: CALL (UNKN)
.proc Call
    jsr EvaluateNumber
    jsr ConvertToAddress
    jmp (LineNumber)
.endproc

;; `IN#`: reads a byte and selects that slot for input through the Monitor's <INPORT>.
;; Also: INNUM (UNKN)
.proc InNumber
    jsr EvaluateByte
    txa
    jmp INPORT
.endproc

;; `PR#`: reads a byte and selects that slot for output through the Monitor's <OUTPOR>.
;; Also: PRNUM (UNKN)
.proc PrNumber
    jsr EvaluateByte
    txa
    jmp OUTPOR
.endproc

.endscope

;; Reads two comma-separated low-resolution coordinates, each below <LOW_RES_ROWS>.
;; Out: LowResFirst = the first coordinate, X = the second, H2 = V2 = the second
;; Errors: ILLEGAL QUANTITY for a coordinate of 48 or more
;; Also: PLOTFN (UNKN), PLOTFNS (ASTIL)
.proc ReadLowResCoordinates
    jsr EvaluateByte
    cpx #LOW_RES_ROWS
    bcs ToIllegalQuantity
    stx LowResFirst
    lda #','
    jsr CheckCharacter
    jsr EvaluateByte
    cpx #LOW_RES_ROWS
    bcs ToIllegalQuantity
    stx H2
    stx V2
    rts
.endproc

;; Jumps on to <IllegalQuantityError>; the low-resolution, cursor and high-resolution argument checks branch here.
;; Also: PLOTF1 (UNKN)
.proc ToIllegalQuantity
    jmp IllegalQuantityError
.endproc

.scope Statements continued

;; Reads a low-resolution line's two endpoints, ordering them, then `AT` and its coordinate.
;; Out: LowResFirst = the lower endpoint, H2 = V2 = the higher, X = the `AT` coordinate
;; Errors: ILLEGAL QUANTITY for a coordinate of 48 or more
;; Also: LINFNS (UNKN)
.proc ReadLowResLine
    jsr ReadLowResCoordinates
    cpx LowResFirst
    bcs ReadAt
    lda LowResFirst
    sta H2
    sta V2
    stx LowResFirst

;; Requires the `AT` token and reads the line's row or column, below <LOW_RES_ROWS>, into X.
;; Also: LINFN1 (UNKN)
ReadAt:
    lda #<TOKEN_AT
    jsr CheckCharacter
    jsr EvaluateByte
    cpx #LOW_RES_ROWS
    bcs ToIllegalQuantity
    rts
.endproc

;; `PLOT`: reads the coordinates, checks that the column is below <LOW_RES_COLUMNS>, and plots through the Monitor's
;; <MPLOT>.
;; Errors: ILLEGAL QUANTITY for a column of 40 or more or a row of 48 or more
;; Also: PLOT (UNKN)
.proc Plot
    jsr ReadLowResCoordinates
    txa
    ldy LowResFirst
    cpy #LOW_RES_COLUMNS
    bcs ToIllegalQuantity
    jmp MPLOT
.endproc

;; `HLIN`: reads the line, checks that its right end is below <LOW_RES_COLUMNS>, and draws it through the Monitor's
;; <HLINE>.
;; Errors: ILLEGAL QUANTITY for an endpoint of 40 or more or a row of 48 or more
;; Also: HLIN (UNKN)
.proc HLin
    jsr ReadLowResLine
    txa
    ldy H2
    cpy #LOW_RES_COLUMNS
    bcs ToIllegalQuantity
    ldy LowResFirst
    jmp HLINE
.endproc

;; `VLIN`: reads the line, checks that the `AT` column is below <LOW_RES_COLUMNS>, and draws it through the Monitor's
;; <VLINE>.
;; Errors: ILLEGAL QUANTITY for a row of 48 or more or a column of 40 or more
;; Also: VLIN (UNKN)
.proc VLin
    jsr ReadLowResLine
    txa
    tay
    cpy #LOW_RES_COLUMNS
    bcs ToIllegalQuantity
    lda LowResFirst
    jmp VLINE
.endproc

;; `COLOR=`: reads a byte and passes it to the Monitor's <SETCOL>.
;; Also: COLSTM (UNKN)
.proc Color
    jsr EvaluateByte
    txa
    jmp SETCOL
.endproc

;; `VTAB`: reads a row from 1 to 24 and moves the cursor there through the Monitor's <TABV>.
;; Errors: ILLEGAL QUANTITY for a row of 0 or more than 24
;; Also: VTAB (UNKN)
.proc VTab
    jsr EvaluateByte
    dex
    txa
    cmp #TEXT_ROWS
    bcs ToIllegalQuantity
    jmp TABV
.endproc

;; `SPEED=`: reads a byte and stores its negation, 256 less it, in <OutputDelay>.
;; Also: SPEED (UNKN)
.proc Speed
    jsr EvaluateByte
    txa
    eor #$FF
    tax
    inx
    stx OutputDelay
    rts
.endproc

;; `TRACE`: sets carry and skips <Statements::NoTrace>'s `clc`, so its `ror` sets bit 7 of <TraceMode>.
;; Also: TRACE (UNKN)
.proc Trace
    sec
    .byte $90                       ; BCC: skips NoTrace's CLC, since carry is set
    ; Falls into NoTrace, past its clc.
.endproc

;; `NOTRACE`: clears carry and rotates it into bit 7 of <TraceMode>, turning tracing off.
;; Also: NOTRAC (UNKN)
.proc NoTrace
    clc
    ror TraceMode
    rts
.endproc

;; `NORMAL`: sets <INVFLG> to <INVERSE_MASK_NORMAL> and clears <FlashMask> through <Statements::SetInverseMask>.
;; The cold start calls it too.
;; Also: NRMSTM (UNKN)
.proc Normal
    lda #INVERSE_MASK_NORMAL
    bne SetInverseMask
.endproc

;; `INVERSE`: loads <INVERSE_MASK_INVERSE> and falls into <Statements::SetInverseMask>.
;; Also: INVERS (UNKN)
.proc Inverse
    lda #INVERSE_MASK_INVERSE
    ; Falls into SetInverseMask.
.endproc

;; Clears X, for no flashing, and falls into <Statements::SetTextMasks>.
;; In: A = the inverse mask
;; Also: INVER1 (UNKN)
.proc SetInverseMask
    ldx #0
    ; Falls into SetTextMasks.
.endproc

;; Stores the masks output applies to text.
;; In: A = the inverse mask, for <INVFLG>; X = the flash mask, for <FlashMask>
;; Also: INVER2 (UNKN)
.proc SetTextMasks
    sta INVFLG
    stx FlashMask
    rts
.endproc

;; `FLASH`: sets <INVFLG> to <INVERSE_MASK_FLASH> and <FlashMask> to <FLASH_MASK_FLASH> through
;; <Statements::SetTextMasks>.
;; Also: FLASH (UNKN)
.proc Flash
    lda #INVERSE_MASK_FLASH
    ldx #FLASH_MASK_FLASH
    bne SetTextMasks
.endproc

; Memory limits, error trapping and editing

;; `HIMEM:`: evaluates an address and, unless it is below <ArraysEnd>, sets <MemoryTop> and <StringsBottom> to it. It
;; does not move strings already above the new top.
;; Errors: OUT OF MEMORY for an address below <ArraysEnd>
;; Entry:
;;   ToOutOfMemory = jumps on to <ReportOutOfMemory>; <Statements::LoMem> branches here
;; Also: HIMEM (UNKN)
.proc HiMem
    jsr EvaluateNumber
    jsr ConvertToAddress
    lda LineNumber
    cmp ArraysEnd
    lda LineNumber+1
    sbc ArraysEnd+1
    bcs SetMemoryTop

;; Jumps on to <ReportOutOfMemory>.
;; Also: HIMEM1 (UNKN)
ToOutOfMemory:
    jmp ReportOutOfMemory

;; Stores <LineNumber> in <MemoryTop> and <StringsBottom>.
;; Also: HIMEM2 (UNKN)
SetMemoryTop:
    lda LineNumber
    sta MemoryTop
    sta StringsBottom
    lda LineNumber+1
    sta MemoryTop+1
    sta StringsBottom+1
    rts
.endproc

;; `LOMEM:`: evaluates an address and, if it is below <MemoryTop> and not below <VariablesStart>, sets
;; <VariablesStart> to it and clears the variables.
;; Errors: OUT OF MEMORY for an address at or above <MemoryTop> or below <VariablesStart>
;; Also: LOMEM (UNKN)
.proc LoMem
    jsr EvaluateNumber
    jsr ConvertToAddress
    lda LineNumber
    cmp MemoryTop
    lda LineNumber+1
    sbc MemoryTop+1
    bcs HiMem::ToOutOfMemory
    lda LineNumber
    cmp VariablesStart
    lda LineNumber+1
    sbc VariablesStart+1
    bcc HiMem::ToOutOfMemory
    lda LineNumber
    sta VariablesStart
    lda LineNumber+1
    sta VariablesStart+1
    jmp ClearVariables
.endproc

;; `ONERR GOTO`: requires `GOTO`, saves <TextPointer> in <OnErrorText> and <CurrentLine> in <OnErrorLine>, sets bit 7
;; of <OnErrorActive>, then skips the rest of the line.
;; Also: ONERR (UNKN)
.proc OnErr
    lda #<TOKEN_GOTO
    jsr CheckCharacter
    lda TextPointer
    sta OnErrorText
    lda TextPointer+1
    sta OnErrorText+1
    sec
    ror OnErrorActive
    lda CurrentLine
    sta OnErrorLine
    lda CurrentLine+1
    sta OnErrorLine+1
    jsr FindLineEnd
    jmp AdvanceTextPointer
.endproc

.endscope

;; Gives a trapped error to the `ONERR` handler.
;;
;; It saves the error code, <StatementStack>, <CurrentLine> and <StoppedText> for `RESUME`, restores the handler's
;; position and line, and runs its `GOTO`.
;; In: X = the error code
;; Also: HANDLE (UNKN), HANDLERR (ASTIL)
.proc TrapError
    stx ErrorCode
    ldx StatementStack
    stx ErrorStack
    lda CurrentLine
    sta ErrorLine
    lda CurrentLine+1
    sta ErrorLine+1
    lda StoppedText
    sta ErrorText
    lda StoppedText+1
    sta ErrorText+1
    lda OnErrorText
    sta TextPointer
    lda OnErrorText+1
    sta TextPointer+1
    lda OnErrorLine
    sta CurrentLine
    lda OnErrorLine+1
    sta CurrentLine+1
    jsr GetCurrentCharacter
    jsr Statements::GoTo
    jmp NextStatementSavingStack
.endproc

.scope Statements continued

;; `RESUME`: restores <CurrentLine>, <TextPointer> and the stack pointer saved at the error, then goes on to
;; <NextStatementSavingStack>. ASTIL gives RESUME as $F317, the dispatch table's value, one less than this address.
;; Also: RESUME (ASTIL)
.proc Resume
    lda ErrorLine
    sta CurrentLine
    lda ErrorLine+1
    sta CurrentLine+1
    lda ErrorText
    sta TextPointer
    lda ErrorText+1
    sta TextPointer+1
    ldx ErrorStack
    txs
    jmp NextStatementSavingStack
.endproc

;; Jumps on to <SyntaxError>; <Statements::Del> branches here when its argument does not start with a digit.
;; Also: RESUM1 (UNKN)
.proc ToSyntaxError
    jmp SyntaxError
.endproc

;; `DEL`: finds the first line and the line after the second number, moves the rest of the program down over them,
;; sets <VariablesStart> and relinks the program through <ClearAndRelink>.
;; In: carry = clear for a digit, as <GetNextCharacter> leaves it
;; Also: DEL (UNKN)
.proc Del
    bcs Statements::ToSyntaxError
    ldx ProgramEnd
    stx VariablesStart
    ldx ProgramEnd+1
    stx VariablesStart+1
    jsr ReadLineNumber
    jsr FindLine
    lda SourceStart
    sta Pointer2
    lda SourceStart+1
    sta Pointer2+1
    lda #','
    jsr CheckCharacter
    jsr ReadLineNumber
    inc LineNumber
    bne FindEnd
    inc LineNumber+1

;; Finds the first line at or after the upper bound plus one, and returns if it is before the first line's position.
;; Also: DEL1 (UNKN)
FindEnd:
    jsr FindLine
    lda SourceStart
    cmp Pointer2
    lda SourceStart+1
    sbc Pointer2+1
    bcs Move
    rts

;; Starts the move with Y = 0.
;; Also: DEL11 (UNKN)
Move:
    ldy #0

;; Copies a byte from <SourceStart> to <Pointer2> and advances <SourceStart>.
;; Also: DEL111 (UNKN)
MoveByte:
    lda (SourceStart),y
    sta (Pointer2),y
    inc SourceStart
    bne StepDestination
    inc SourceStart+1

;; Advances <Pointer2>.
;; Also: DEL112 (UNKN)
StepDestination:
    inc Pointer2
    bne TestEnd
    inc Pointer2+1

;; Loops while <SourceStart> has not passed <VariablesStart>.
;; Also: DEL113 (UNKN)
TestEnd:
    lda VariablesStart
    cmp SourceStart
    lda VariablesStart+1
    sbc SourceStart+1
    bcs MoveByte
    ldx Pointer2+1
    ldy Pointer2
    bne SetVariablesStart
    dex

;; Sets <VariablesStart> to <Pointer2> less one and relinks the program.
;; Also: DEL114 (UNKN)
SetVariablesStart:
    dey
    stx VariablesStart+1
    sty VariablesStart
    jmp ClearAndRelink
.endproc

; Display modes and cassette arrays

;; `GR`: reads <LORES> and <MIXSET>, then the Monitor's <SETGR> shows and clears the low-resolution screen.
;; Also: GR (UNKN)
.proc Gr
    lda LORES
    lda MIXSET
    jmp SETGR
.endproc

;; `TEXT`: reads <LOWSCR>, then the Monitor's <SETTXT> selects full-screen text.
;; Also: TEXT (UNKN)
.proc Text
    lda LOWSCR
    jmp SETTXT
.endproc

;; `STORE`: finds the array, writes its length less one, from <LineNumber>, to cassette, then its data, both through
;; the Monitor's <MWRITE>. The enhanced IIe sets the data's range through <Statements::CallAppleSoftCassette>, the
;; others through <Statements::SetArrayBlock>.
;; Also: STORE (UNKN)
.proc Store
    jsr FindCassetteArray
    ldy #ArrayHeader::LENGTH+1
    lda (SourceStart),y
    tax
    dey
    lda (SourceStart),y
    sbc #1
    bcs WriteLength
    dex

;; Stores the length less one in <LineNumber> and writes the header.
;; Also: STORE1 (UNKN)
WriteLength:
    sta LineNumber
    stx LineNumber+1
    jsr MWRITE
.if ENHNCD
    jsr CallAppleSoftCassette
.else
    jsr SetArrayBlock
.endif
    jmp MWRITE
.endproc

;; `RECALL`: finds the array and reads the length from cassette, then reads the data, unless the length is larger
;; than the array's.
;; Errors: OUT OF MEMORY for a stored array larger than the array
;; Also: RECALL (UNKN)
.proc Recall
    jsr FindCassetteArray
    jsr MREAD
    ldy #ArrayHeader::LENGTH
    lda (SourceStart),y
    cmp LineNumber
    iny
    lda (SourceStart),y
    sbc LineNumber+1
    bcs ReadData
    jmp ReportOutOfMemory

;; Sets the cassette range to the array's data and reads it.
;; Also: RECAL1 (UNKN)
ReadData:
.if ENHNCD
    jsr CallAppleSoftCassette
.else
    jsr SetArrayBlock
.endif
    jmp MREAD
.endproc

.endscope
