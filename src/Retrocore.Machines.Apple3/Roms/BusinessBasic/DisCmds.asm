; retrocore: style=strict
; DISCMDS: the data file statements `READ#` and `WRITE#`, `CHAIN`, `OUTPUT#`, `EXEC` and `INPUT#`'s line read, with
; the helpers the file code shares: the file buffer's pointer and offset, a 16-bit multiply and divide, and the tables
; of a data file's item descriptors.
;
; A BASIC data file is read and written a record at a time through the file's buffer. Each item in a record is a
; descriptor byte followed by the value, and a 0 after the last item marks the record's end when there is room for it.
;
; Names follow Apple's Business BASIC 1.3 listing (BB13), kept in each definition's `Also:`.

; ---------------------------------------------------------------------------------------------------------------------
; The file buffer
; ---------------------------------------------------------------------------------------------------------------------

; Files: the record buffer, multiplying and dividing, and the item descriptors.
.scope Files continued

;; Points <DataBufferPointer> at the file buffer's current byte: the buffer's address plus the offset in the record.
;;
;; The buffer starts on a page boundary, so the offset's low byte is the pointer's low byte.
;; In: FileControlBlockIndex = the file's index in <FileControlBlocks>
;; Out: DataBufferPointer/DataBufferPointerXByte = the byte's extended address, Y = 0
;; Uses: A, X
;; See: <AdvanceOffset>
;; Also: GETNDX (BB13)
.proc PointAtItem
    ldx FileControlBlockIndex
    lda FileControlBlocks+FileControlBlock::BUFFER_OFFSET,X
    sta DataBufferPointer
    clc
    lda FileControlBlocks+FileControlBlock::BUFFER+1,X ; the buffer's page
    adc FileControlBlocks+FileControlBlock::BUFFER_OFFSET+1,X
    ldy FileControlBlocks+FileControlBlock::BUFFER,X ; and its bank
    jsr Memory::NormalizeAfterAdd
    sta DataBufferPointer+1
    sty DataBufferPointerXByte
    ldy #0
    rts
.endproc

;; Tests whether one more byte, the end-of-record mark, fits in the record.
;; In: FileControlBlockIndex = the file's index in <FileControlBlocks>
;; Out: carry = set if it fits
;; See: <ItemFits>
;; Also: TSTFTX (BB13)
.proc EndMarkFits
    lda #1
    ; Falls into ItemFits.
.endproc

;; Tests whether an item of A bytes fits in the rest of the record.
;;
;; A length of 0 stands for 256, a 255-character string with its descriptor. Only offsets in the record are compared,
;; so no bank arithmetic is needed.
;; In: A = the item's length, FileControlBlockIndex = the file's index in <FileControlBlocks>
;; Out: carry = set if it fits, DataItemLength = the length
;; Uses: A, X, Y, VariableNamePointer
;; See: <EndMarkFits>
;; Also: TSTFIT (BB13)
.proc ItemFits
    clc
    sta DataItemLength
    ldy FileControlBlockIndex
    adc FileControlBlocks+FileControlBlock::BUFFER_OFFSET,Y
    sta VariableNamePointer
    lda FileControlBlocks+FileControlBlock::BUFFER_OFFSET+1,Y
    ldx DataItemLength                      ; a length of 0 is 256
    bne AddCarry
    sec
AddCarry:
    adc #0
    sta VariableNamePointer+1
    lda FileControlBlocks+FileControlBlock::RECORD_LENGTH,Y ; the record length against the item's end
    cmp VariableNamePointer
    lda FileControlBlocks+FileControlBlock::RECORD_LENGTH+1,Y
    sbc VariableNamePointer+1
    rts
.endproc

;; Moves the file buffer's offset past the item just read or written, by <DataItemLength> bytes.
;; In: DataItemLength = the item's length (0 for 256), FileControlBlockIndex = the file's index in <FileControlBlocks>
;; Out: Y = FileControlBlockIndex, A = the new offset's high byte
;; Uses: X
;; See: <PointAtItem>
;; Also: UPOFS (BB13)
.proc AdvanceOffset
    clc
    lda DataItemLength
    ldy FileControlBlockIndex
    adc FileControlBlocks+FileControlBlock::BUFFER_OFFSET,Y
    sta FileControlBlocks+FileControlBlock::BUFFER_OFFSET,Y
    lda FileControlBlocks+FileControlBlock::BUFFER_OFFSET+1,Y
    ldx DataItemLength
    bne AddCarry
    sec
AddCarry:
    adc #0
    sta FileControlBlocks+FileControlBlock::BUFFER_OFFSET+1,Y
    rts
.endproc

; ---------------------------------------------------------------------------------------------------------------------
; Multiply and divide
; ---------------------------------------------------------------------------------------------------------------------

;; Multiplies <Multiplier> by <Multiplicand>, 16 bits by 16, into the 32-bit product at <Product>.
;;
;; The product's high word builds in <Remainder> while the multiplier shifts out of <Multiplier> and the product's low
;; word shifts in. The add indexes <Multiplicand> with X from $FE, counting on zero page wrapping round to reach
;; <Remainder>, so these locations must be in zero page and in this order.
;; In: Multiplier = the multiplier, Multiplicand = the multiplicand
;; Out: Product..Product+3 = the product
;; Uses: A, X, Y
;; See: <RecordPosition>
;; Also: MUL (BB13)
.proc Multiply
    lda #0                                  ; clear the product's high word
    sta Product+2
    sta Product+3
    ldy #16                                 ; 16 bits

;; Adds the multiplicand into the high word when the multiplier's low bit is 1.
;; Also: MUL2 (BB13)
NextBit:
    lda Multiplier                          ; the multiplier's low bit
    lsr
    bcc Shift                               ; 0: nothing to add
    clc
    ldx #$FE

;; Adds one byte of the multiplicand.
;; Also: MUL3 (BB13)
AddByte:
    lda Multiplicand,X                      ; Multiplicand-2, by zero page wrapping: Remainder
    adc Multiplicand+2,X
    sta Multiplicand,X
    inx
    bne AddByte

;; Shifts the 32-bit product right.
;; Also: MUL4 (BB13)
Shift:
    ldx #3

;; Shifts one byte of the product.
;; Also: MUL5 (BB13)
ShiftByte:
    ror Product,X
    dex
    bpl ShiftByte
    dey
    bne NextBit
    rts
.endproc

;; Divides the 32-bit <Dividend> by <Divisor>, giving a 16-bit quotient in <Quotient> and the remainder in <Remainder>.
;;
;; The dividend's low word is in <Quotient> and its high word in <Remainder>, which must be below the divisor. Each of
;; the 16 steps shifts the pair left and takes the divisor from <Remainder> when it fits, as the Apple II Monitor's
;; divide does.
;;
;; The low bytes are subtracted twice, the second time with the first's borrow, so when the low bytes borrow and the
;; subtraction still fits, the remainder's low byte is kept one too small, which can throw the later quotient bits
;; off.
;; In: Dividend = the dividend, Divisor = the divisor
;; Out: Quotient = the quotient, Remainder = the remainder
;; Uses: A, X, Y
;; See: <RecordFromMark>
;; Also: DIV (BB13)
.proc Divide
    ldy #16

;; Shifts the dividend left and takes the divisor off when it fits.
;; Also: DIV2 (BB13)
NextBit:
    asl Quotient
    rol Quotient+1
    rol Remainder
    rol Remainder+1
    sec
    lda Remainder
    sbc Divisor
    tax
    lda Remainder
    sbc Divisor
    tax                                     ; the low byte again, with the first's borrow
    lda Remainder+1
    sbc Divisor+1
    bcc Count
    stx Remainder
    sta Remainder+1
    inc Quotient                            ; a 1 in the quotient

;; Counts the step.
;; Also: DIV3 (BB13)
Count:
    dey
    bne NextBit
    rts
.endproc

; ---------------------------------------------------------------------------------------------------------------------
; Item descriptors
; ---------------------------------------------------------------------------------------------------------------------

;; An integer, in <DescriptorValueTypes> beside the <ValueType> values (<VALUE_TYPE_REAL> ...); bit 3 tells `READ#` to
;; set <IntegerType>.
;; Also: VINT (BB13)
VALUE_TYPE_INTEGER = $08

;; The value type <DescriptorValueTypes> gives the end-of-record mark: no type.
VALUE_TYPE_NONE = $01

;; The bits of a number's descriptor that hold its value's length.
DESCRIPTOR_SIZE_MASK = $0F

;; The index of the 255-character string's descriptor, <DATA_ITEM_LONGEST_STRING>, in <Descriptors>;
;; <DATA_ITEM_STRING>'s is one less.
MAX_STRING_INDEX = 4

;; What the `TYP` function gives for a real.
TYP_REAL = 1

;; What `TYP` gives for an integer.
TYP_INTEGER = 2

;; What `TYP` gives for a long integer.
TYP_LONG = 3

;; What `TYP` gives for a string.
TYP_STRING = 4

;; What `TYP` gives at the end of the data.
TYP_END = 5

;; What `TYP` gives for a text file.
TYP_TEXT = 8

;; The descriptor byte of each kind of item in a data file: integer, real, long integer, string, 255-character string
;; and the end-of-record mark.
;;
;; A number's descriptor has its value's length in the low nibble: 2, 4 or 8 bytes. A string's is followed by its
;; length byte and characters, except a 255-character string's, which has no length byte.
;; See: <DescriptorValueTypes>, <DescriptorTypNumbers>, <DescriptorType>
;; Also: DTABLE (BB13)
Descriptors:
    .byte DATA_ITEM_INTEGER, DATA_ITEM_REAL, DATA_ITEM_LONG_INTEGER, DATA_ITEM_STRING
    .byte DATA_ITEM_LONGEST_STRING, DATA_ITEM_END_OF_RECORD

;; The <ValueType> of each descriptor in <Descriptors>, at the same index; both kinds of string are $FF, and the
;; end-of-record mark's 1 is no type.
;; Also: VTABLE (BB13)
DescriptorValueTypes:
    .byte VALUE_TYPE_INTEGER, VALUE_TYPE_REAL, VALUE_TYPE_LONG_INTEGER, VALUE_TYPE_STRING
    .byte VALUE_TYPE_STRING, VALUE_TYPE_NONE

;; The last index of <Descriptors> and <DescriptorValueTypes>.
;; Also: TBLLEN (BB13)
DESCRIPTOR_LAST = DescriptorValueTypes-Descriptors-1

;; What the `TYP` function gives for each descriptor in <Descriptors>: 2 for an integer, 1 a real, 3 a long integer,
;; 4 a string and 5 the end of a record.
;; Also: TYPFNT (BB13)
DescriptorTypNumbers:
    .byte TYP_INTEGER, TYP_REAL, TYP_LONG, TYP_STRING
    .byte TYP_STRING, TYP_END
.assert * - DescriptorTypNumbers = DESCRIPTOR_LAST + 1, "The descriptor tables have one entry per descriptor."
.assert Descriptors + MAX_STRING_INDEX + 1 = DescriptorValueTypes - 1, "DDMXSTR is the next to last descriptor."

.endscope

; ---------------------------------------------------------------------------------------------------------------------
; `CHAIN`
; ---------------------------------------------------------------------------------------------------------------------

; Statements: `CHAIN`.
.scope Statements continued

;; `CHAIN`: runs another program, keeping the variables; `CHAIN name [, line]`.
;;
;; The variables and arrays move up under the strings, out of the new program's way; the program loads with
;; <Files::LoadProgram>, and the variables move back down to follow it. The load checks the new program against the
;; top of memory only, not against the variables moved up under the strings, so a program longer than the room left
;; loads over them.
;; See: <Files::OpenProgramToRun>, <Files::StartProgram>
;; Also: CHAIN (BB13)
.proc Chain
    jsr Files::OpenProgramToRun
    jsr Strings::CollectGarbage             ; collect the strings first
    clc                                     ; the gap between the arrays and the strings, less 1
    lda StringsBottom
    sbc VariablesEnd
    sta MoveDistance
    lda StringsBottom+1
    sbc VariablesEnd+1
    ldy StringsBottomXByte
    jsr Memory::NormalizeAfterSubtract
    sta MoveDistance+1
    tya
    sbc VariablesEndXByte
    sta MoveDistanceXByte
    lda ArraysStart                         ; move up from the variables' start
    sta SourceStart
    lda ArraysStart+1
    sta SourceStart+1
    lda ArraysStartXByte
    sta SourceStartXByte
    jsr OpenGap
    lda ArraysStart                         ; keep where the variables now start, in the Fac
    sta Fac
    lda ArraysStart+1
    sta Fac+1
    lda ArraysStartXByte
    sta Fac+2
    jsr Files::LoadProgram
    jsr ClearVariables::RestoreData         ; take back memory, and reset DATA and the stack
    lda ArraysStart                         ; move the variables down to the new program's end
    sta SourceStart
    sec
    sbc Fac
    sta MoveDistance
    lda ArraysStart+1
    sta SourceStart+1
    sbc Fac+1
    ldy ArraysStartXByte
    sty SourceStartXByte
    jsr Memory::NormalizeAfterSubtract
    sta MoveDistance+1
    tya
    sbc Fac+2
    sta MoveDistanceXByte
    lda Fac
    sta ArraysStart
    sta Pointer1
    lda Fac+1
    sta ArraysStart+1
    sta Pointer1+1
    lda Fac+2
    sta Pointer1XByte
    sta ArraysStartXByte
    jsr CloseGap
    ; Falls into Files::StartProgram.
.endproc

.endscope

; Files: starting a program, and opening the one to run.
.scope Files continued

;; Starts the program from its beginning, or from the line in <LineNumber> when that is not 0.
;; In: LineNumber = the line to start at, or 0
;; See: <Statements::Chain>, <Statements::GoTo::SearchFromStart>
;; Also: FRUN (BB13)
.proc StartProgram
    jsr RewindTextPointer
    jsr ResetStack
    lda LineNumber
    ora LineNumber+1
    beq Run
    jsr Statements::GoTo::SearchFromStart
Run:
    jmp NextStatement
.endproc

;; Opens the program file `RUN` or `CHAIN` names, for reading, then reads the line number after a comma, if any.
;;
;; It sets <ProgramLoading>, which 1.3 takes as the sign to use the new program's prefix, and <StartupDone>, which says
;; a program has run.
;; Out: LineNumber = the line, or 0
;; See: <OpenOfType>, <Statements::Chain>
;; Also: LDRUN (BB13)
.proc OpenProgramToRun
    lda #OPEN_READ                          ; read only, and the value of `RUN`'s or `CHAIN`'s flag
    sta ProgramLoading
    ldx #FILE_TYPE_BASIC_PROGRAM
    jsr OpenOfType
    lda #1
    sta StartupDone
    jsr GetCurrentCharacter
    beq NoLine                              ; no line number
    jsr CheckComma
    jmp ReadLineNumber

;; Sets the line to start at to 0, for the program's beginning.
;; Also: DATSALL (BB13)
NoLine:
    lda #0
    sta LineNumber
    sta LineNumber+1
    rts
.endproc

.endscope

; ---------------------------------------------------------------------------------------------------------------------
; READ#
; ---------------------------------------------------------------------------------------------------------------------

; Statements: READ#.
.scope Statements continued

;; `READ#`: reads items from a data file's record into variables; `READ# file [, record] [; variables]`.
;;
;; Each item must match its variable's kind: a string into a string variable, a number into a numeric one, converted
;; to the variable's type. At an end-of-record mark the next record is read in; a record that starts with the mark
;; ends the data (<Handlers::EndOfFile>).
;; Entry:
;;   ToEndOfData = goes to the end-of-file handling; <Write> ends here for an item too long for any record
;;   StepOver = moves past the item just read, and on to the next; <ReadFileString> goes on here
;; See: <Write>, <Files::TakeFileAndRecord>, <ReadFile::NextRecordOrEnd>
;; Also: DREAD (BB13)
.proc ReadFile
    sec                                     ; reading
    ror FileAccessMode
    jsr Files::TakeFileAndRecord
    jsr Files::PrepareDataFile
    jsr Files::CheckReadAccess
    jsr GetCurrentCharacter
    cmp #';'                                ; a semicolon: variables follow
    bne Return
    jsr GetNextCharacter
    bne ReadItem                            ; always

;; Returns.
;; Also: RDRTS (BB13)
Return:
    rts

;; Takes the comma before the next variable, or ends at the statement's end.
;; Also: DRD1 (BB13)
NextItem:
    jsr GetCurrentCharacter
    beq Return
    jsr CheckComma

;; Reads the item at the buffer's offset, moving to the next record at an end-of-record mark.
;; Also: DRD2 (BB13)
ReadItem:
    jsr Files::PointAtItem
    lda (DataBufferPointer),Y               ; the item's descriptor
    bne TakeItem
    jsr NextRecordOrEnd                     ; the end of the record
    jmp ReadItem

;; Ends the data: goes to the end-of-file handling in <Handlers::EndOfFile>.
;; Also: ODERR (BB13)
ToEndOfData:
    jmp Handlers::EndOfFile

;; At an end-of-record mark, moves to the next record, unless the mark is the record's first byte, which ends the
;; data.
;; See: <Files::NextRecord>, <ToEndOfData>
;; Also: DRDNXT (BB13)
NextRecordOrEnd:
    ldy FileControlBlockIndex
    lda FileControlBlocks+FileControlBlock::BUFFER_OFFSET,Y
    ora FileControlBlocks+FileControlBlock::BUFFER_OFFSET+1,Y
    beq ToEndOfData
    jmp Files::NextRecord

;; Takes a numeric item into the numeric variable next in the statement; a string item goes to <ReadFileString>.
;; Also: DRD3 (BB13)
TakeItem:
    jsr Files::DescriptorType
    sta ValueType
    bmi ReadFileString                      ; a string
    pha
    jsr FindVariableToAssign
    bit ValueType                           ; a number needs a numeric variable
    bmi Files::ToTypeMismatchError
    jsr Files::ItemDescriptor
    tay                                     ; the variable's descriptor
    pla                                     ; the item's type
    cmp #Files::VALUE_TYPE_INTEGER
    clc
    bne SetInteger
    sec
SetInteger:
    ror IntegerType
    sta ValueType
    tya
    pha
    lda DataBufferPointer                   ; the value, after the descriptor
    ldy DataBufferPointer+1
    ldx DataBufferPointerXByte
    clc
    adc #1
    bcc LoadValue
    iny
LoadValue:
    jsr EvaluateVariable::AtAddress         ; into the Fac
    pla
    pha
    cmp #DATA_ITEM_LONG_INTEGER             ; a long integer variable?
    bne ToReal
    jsr Functions::ConvLong

;; Assigns the value to the variable, as the variable's type.
;; Also: DRD5 (BB13)
Assign:
    pla
    jsr Files::DescriptorType
    sta ValueType
    lsr
    lsr
    lsr
    lsr                                     ; VALUE_TYPE_INTEGER's bit 3 into carry
    ror IntegerType
    jsr AssignFac

;; Moves past the item just read, and to the next record when the item ends this one.
;; Also: DRD6 (BB13)
StepOver:
    jsr Files::PointAtItem
    lda (DataBufferPointer),Y
    sta DataItemDescriptor
    jsr Files::ItemLength
    jsr Files::AdvanceOffset
    cmp FileControlBlocks+FileControlBlock::RECORD_LENGTH+1,Y ; at the end of the record?
    bcc ToNextItem
    lda FileControlBlocks+FileControlBlock::BUFFER_OFFSET,Y
    cmp FileControlBlocks+FileControlBlock::RECORD_LENGTH,Y
    bcc ToNextItem
    jsr NextRecordOrEnd

;; Goes on to the next variable.
;; Also: DRD7 (BB13)
ToNextItem:
    jmp NextItem

;; Converts the value to a real for a real or integer variable.
;; Also: NTLNT (BB13)
ToReal:
    jsr Functions::Conv
    jmp Assign
.endproc

.endscope

; Files: a type mismatch.
.scope Files continued

;; Ends the statement with a type mismatch.
;; See: <ReportTypeMismatch>
;; Also: MSMTCH (BB13)
.proc ToTypeMismatchError
    jmp ReportTypeMismatch
.endproc

.endscope

;; Finds a variable as <FindVariable> does, and puts its address in <AssignedVariable> as well, for the statements that
;; assign to it.
;; Out: A/Y = the variable's address, AssignedVariable/AssignedVariableXByte = the same, X = its X-byte, from
;;   <VariablePointerXByte>
;; See: <FindVariable>
;; Also: MYPTRGET (BB13)
.proc FindVariableToAssign
    jsr FindVariable
    sta AssignedVariable
    sty AssignedVariable+1
    ldx VariablePointerXByte
    stx AssignedVariableXByte
    rts
.endproc

; Statements: READ#'s strings, and WRITE#.
.scope Statements continued

;; Reads a string item into the string variable next in the statement, for `READ#`.
;;
;; A 255-character string's descriptor has no length byte after it.
;; See: <ReadFile>
;; Also: RDSTRI (BB13)
.proc ReadFileString
;; The length of a string whose descriptor is <DATA_ITEM_LONGEST_STRING>.
MAX_STRING_LENGTH = 255

    jsr FindVariableToAssign
    bit ValueType                           ; a string needs a string variable
    bpl Files::ToTypeMismatchError
    ldy #0
    lda (DataBufferPointer),Y
    iny
    cmp #DATA_ITEM_LONGEST_STRING
    bne TakeLength
    lda #MAX_STRING_LENGTH
    dey
    .byte $2C                               ; BIT absolute skips the length byte's LDA

;; Takes the string's length from the byte after its descriptor.
;; Also: NTMXSTR (BB13)
TakeLength:
    lda (DataBufferPointer),Y               ; the length
    pha
    iny                                     ; the characters follow
    tya
    clc
    adc DataBufferPointer
    sta StringPointer
    lda DataBufferPointer+1
    adc #0
    sta StringPointer+1
    lda DataBufferPointerXByte
    sta StringPointerXByte
    pla
    tay
    jsr Strings::FromTextUntil::AtZero
    jsr AssignString
    jmp ReadFile::StepOver
.endproc

; ---------------------------------------------------------------------------------------------------------------------
; WRITE#
; ---------------------------------------------------------------------------------------------------------------------

;; `WRITE#`: writes expressions as items into a data file's record; `WRITE# file [, record] [; expressions]`.
;;
;; An item that does not fit in the rest of the record goes in the next one; one too long for any record goes to the
;; end-of-file handling (<ReadFile::ToEndOfData>). Starting a record first writes the whole record, to reserve its
;; space on the disk. A 0 follows the items as the end-of-record mark, when there is room.
;; See: <ReadFile>, <Files::EvaluateItem>, <Files::WriteRecord>
;; Also: DWRITE (BB13)
.proc Write
    lsr FileAccessMode                      ; writing
    jsr Files::TakeFileAndRecord
    jsr Files::PrepareDataFile
    jsr Files::CheckWriteAccess
    jsr GetCurrentCharacter
    cmp #';'                                ; a semicolon: expressions follow
    bne Return
    jsr GetNextCharacter
    bne TakeItem                            ; always

;; Returns.
;; Also: WRRTS (BB13)
Return:
    rts

;; Takes the comma before the next expression, or ends at the statement's end.
;; Also: DWR1 (BB13)
NextItem:
    jsr GetCurrentCharacter
    beq Return
    jsr CheckComma

;; Evaluates the next expression.
;; Also: DWR2 (BB13)
TakeItem:
    jsr Files::EvaluateItem

;; Starts a record by writing it whole, when the item is the first in it.
;; Also: DWR3 (BB13)
Place:
    ldx FileControlBlockIndex
    lda FileControlBlocks+FileControlBlock::BUFFER_OFFSET,X ; at the record's start?
    ora FileControlBlocks+FileControlBlock::BUFFER_OFFSET+1,X
    bne CheckFit
    jsr Files::SeekRecord
    jsr Files::SetRecordTransfer            ; write the whole record, to reserve the space
    ldy #SosCalls::CALL_WRITE
    jsr SosCalls::MakeFileCall
    jsr Files::SeekRecord

;; Moves to the next record when the item doesn't fit in this one, unless it would fit in none.
;; Also: DWR4 (BB13)
CheckFit:
    jsr Files::PointAtItem
    jsr Files::ItemLength
    jsr Files::ItemFits
    bcs Store
    ldy FileControlBlockIndex               ; would it fit in an empty record?
    lda FileControlBlocks+FileControlBlock::RECORD_LENGTH+1,Y
    bne ToNextRecord                        ; a record of 256 bytes or more: yes
    lda DataItemLength
    beq TooLong                             ; a 256-byte item: no
    lda FileControlBlocks+FileControlBlock::RECORD_LENGTH,Y
    cmp DataItemLength
    bcc TooLong

;; Writes the record back and moves to the next.
;; Also: NXREC (BB13)
ToNextRecord:
    jsr Files::NextRecord
    jmp Place

;; Goes to the end-of-file handling for an item too long for any record.
;; Also: DNTFIT (BB13)
TooLong:
    jmp ReadFile::ToEndOfData

;; Stores the descriptor and the value's bytes in the buffer.
;; Also: ITFITS (BB13)
Store:
    ldy #0
    ldx DataItemLength
    dex
    stx SavedX                              ; the bytes after the descriptor
    lda DataItemDescriptor
    sta (DataBufferPointer),Y
    iny
    dex
    cmp #DATA_ITEM_STRING
    bne CopyValue
    stx SavedX                              ; a string: its length byte, then its characters
    txa
    sta (DataBufferPointer),Y
    beq Stored                              ; an empty string
    iny

;; Copies the value's next byte.
;; Also: ITF1 (BB13)
CopyValue:
    ldx #0
    lda (VariablePointer,X)
    sta (DataBufferPointer),Y
    iny
    inc VariablePointer
    bne Counted
    inc VariablePointer+1
Counted:
    dec SavedX
    bne CopyValue

;; Moves past the item and marks the buffer changed, with the end-of-record mark after it when it fits.
;; Also: DATDON (BB13)
Stored:
    jsr Files::AdvanceOffset
    jsr Files::MarkChanged
    jsr Files::EndMarkFits                  ; room for the end-of-record mark?
    bcc FreeString
    jsr Files::PointAtItem
    lda #DATA_ITEM_END_OF_RECORD
    sta (DataBufferPointer),Y               ; the offset stays before it

;; Frees a string's temporary, and goes on to the next expression.
;; Also: GODWR1 (BB13)
FreeString:
    bit ValueType
    bpl Next
    jsr Strings::FreeFacTemporary           ; free a string's temporary
Next:
    jmp NextItem
.endproc

.endscope

; Files: an item's descriptor and length, and the access checks.
.scope Files continued

;; Marks the file's buffer as changed, to be written back: <FLAG_CHANGED> in the control block's flags.
;;
;; Nothing clears the flag again but closing the file, so once a file has been written, each move to another record
;; writes the record in hand back first (<WriteRecord>), whether or not it changed since.
;; In: FileControlBlockIndex = the file's index in <FileControlBlocks>
;; Out: Y = <FileControlBlockIndex>
;; Uses: A
;; Keeps: X
;; See: <WriteRecord>
;; Also: SETOUT (BB13)
.proc MarkChanged
    ldy FileControlBlockIndex
    lda FileControlBlocks+FileControlBlock::FLAGS,Y
    ora #FLAG_CHANGED
    sta FileControlBlocks+FileControlBlock::FLAGS,Y
    rts
.endproc

;; Works out an item's length in the file from its descriptor: the descriptor and the value, with a string's length
;; byte and characters.
;; In: DataItemDescriptor = the descriptor, FacMantissa3 = the string, for a string
;; Out: A = the length, 0 for a 255-character string's 256, DataItemLength = the same
;; Uses: Y
;; Also: CALCLEN (BB13)
.proc ItemLength
    lda DataItemDescriptor
    eor #DATA_ITEM_LONGEST_STRING           ; a 255-character string: 0, for 256
    beq Done
    eor #DATA_ITEM_STRING-DATA_ITEM_LONGEST_STRING
    bne Number
    tay                                     ; a string: A and Y are 0
    lda (FacMantissa3),Y                    ; its length
    sec
    bcs AddOne                              ; always; with AddOne's add, the length plus 2

;; Takes a number's length from its descriptor.
;; Also: CANUM (BB13)
Number:
    lda DataItemDescriptor
    and #DESCRIPTOR_SIZE_MASK               ; a number's length
    clc

;; Adds the descriptor's byte.
;; Also: ADJLEN (BB13)
AddOne:
    adc #1

;; Keeps the length.
;; Also: GOTLEN (BB13)
Done:
    sta DataItemLength
    rts
.endproc

;; Evaluates `WRITE#`'s next expression and works out its descriptor, pointing <VariablePointer> at the bytes to write.
;;
;; A lone integer variable, followed by the end of the statement or a comma, is written as an integer from the
;; variable itself. Anything else is evaluated into the <Fac>; a real is rounded and packed, its sign in the top bit of
;; the mantissa, and a string's bytes are its characters.
;; Out: A = the descriptor, DataItemDescriptor = the same, VariablePointer/VariablePointerXByte = the value's bytes
;; See: <ItemDescriptor>, <ItemLength>
;; Also: GETXPR (BB13)
.proc EvaluateItem
;; The mantissa's bits below the sign.
MANTISSA_MASK = $7F

    jsr GetCurrentCharacter
    bcc Evaluate                            ; a digit: not a variable
    jsr IsLetter
    bcc Evaluate                            ; not a letter: not a variable
    jsr SaveTextPointer                     ; a lone integer variable?
    jsr FindVariable
    bit IntegerType
    bpl NotInteger
    jsr GetCurrentCharacter                 ; only if the end or a comma follows
    beq ItemDescriptor
    cmp #','
    beq ItemDescriptor

;; Goes back to the expression's start, to evaluate it.
;; Also: NOTINT (BB13)
NotInteger:
    jsr RestoreTextPointer                  ; no: evaluate the expression

;; Evaluates the expression and points <VariablePointer> at its bytes.
;; Also: GETX2 (BB13)
Evaluate:
    lda #VALUE_TYPE_ANY
    sta ValueType
    jsr EvaluateExpression
    lda #>(Fac)                             ; a number's bytes are the Fac's
    ldy #<(Fac)
    ldx #0
    bit ValueType
    bpl SetPointer
    jsr Strings::FindFacString
    lda Pointer1+1                          ; a string's are its characters
    ldy Pointer1
    ldx Pointer1XByte

;; Points <VariablePointer> at the bytes, then packs a real.
;; Also: GTX3 (BB13)
SetPointer:
    sta VariablePointer+1
    sty VariablePointer
    stx VariablePointerXByte
    bit ValueType
    bmi NotIntegerItem                      ; a string
    bvs NotIntegerItem                      ; a long integer
    jsr Float::Round                        ; a real: round it, and pack the sign into the mantissa
    lda FacSign
    ora #MANTISSA_MASK
    and FacMantissa1
    sta FacMantissa1

;; Clears <IntegerType>: the item is no integer.
;; Also: NTINT2 (BB13)
NotIntegerItem:
    lsr IntegerType                         ; not an integer
    ; Falls into ItemDescriptor.
.endproc

;; Works out the descriptor for <ValueType> and <IntegerType>: an integer's, else the type's in <DescriptorValueTypes>,
;; with a string's by its length.
;;
;; `WRITE#` uses it for the expression, and `READ#` for the variable it reads into.
;; In: ValueType = the type, IntegerType = bit 7 set for an integer, FacMantissa3 = the string, for a string
;; Out: A = the descriptor, DataItemDescriptor = the same, X = its index in <Descriptors>
;; Errors: a type mismatch for a type not in the table
;; Also: NTINT3 (BB13)
.proc ItemDescriptor
    lda ValueType
    ldx #0
    bit IntegerType
    bmi Found                               ; an integer
    ldx #DESCRIPTOR_LAST

;; Looks the type up in <DescriptorValueTypes>, from the end.
;; Also: GTDSC1 (BB13)
Search:
    cmp DescriptorValueTypes,X
    beq Matched
    dex
    bpl Search
    bmi ToTypeMismatchError                 ; always

;; Gives a string shorter than 255 characters <DATA_ITEM_STRING>, the descriptor before.
;; Also: NTDONE (BB13)
Matched:
    cpx #MAX_STRING_INDEX                   ; a string?
    bne Found
    ldy #0
    lda (FacMantissa3),Y                    ; its length
    adc #0                                  ; plus the carry the compare set: 0 for 255 characters
    beq Found
    dex                                     ; shorter: DATA_ITEM_STRING, with a length byte

;; Takes the descriptor at the index.
;; Also: GOTDSC (BB13)
Found:
    lda Descriptors,X
    sta DataItemDescriptor
    rts

;; Ends the statement with a type mismatch.
;; Also: ERRMIS (BB13)
ToTypeMismatchError:
    jmp ReportTypeMismatch
.endproc

;; Checks that the file may be read, as <CheckWriteAccess> does for writing.
;; In: FileControlBlockIndex = the file's index in <FileControlBlocks>
;; Out: Y = <FileControlBlockIndex>
;; Keeps: X
;; See: <CheckWriteAccess>
;; Also: TSTIN (BB13)
.proc CheckReadAccess
    lda #ACCESS_READ                        ; the read bit
    .byte $2C                               ; BIT absolute skips CheckWriteAccess's LDA
    ; Falls into CheckWriteAccess.
.endproc

;; Checks that the file may be written, ending the statement with a type mismatch if not.
;;
;; A file with no access bits in its control block's type byte passes.
;; In: FileControlBlockIndex = the file's index in <FileControlBlocks>, A = the access bit when <CheckReadAccess> skips
;;   the LDA
;; Out: Y = <FileControlBlockIndex>
;; Uses: Temporary
;; Keeps: X
;; See: <CheckReadAccess>
;; Also: TSTOUT (BB13)
.proc CheckWriteAccess
    lda #ACCESS_WRITE                       ; the write bit
    ldy FileControlBlockIndex
    sta Temporary
    lda FileControlBlocks+FileControlBlock::TYPE_AND_ACCESS,Y
    and #ACCESS_MASK
    beq Return
    and Temporary
    beq DescriptorType::ToTypeMismatchError

;; Returns.
;; Also: TSTRTS (BB13)
Return:
    rts
.endproc

;; Finds a descriptor in <Descriptors> and gives its type from <DescriptorValueTypes>; an unknown descriptor is a type
;; mismatch.
;; In: A = the descriptor
;; Out: A = the type, Y = the descriptor's index
;; Keeps: X
;; Entry:
;;   ToTypeMismatchError = ends the statement with a type mismatch; <CheckWriteAccess> branches here
;; See: <DescriptorTypNumbers>
;; Also: GETVAL (BB13)
.proc DescriptorType
    ldy #DESCRIPTOR_LAST

;; Compares the descriptor with the next entry, from the end.
;; Also: GTVAL1 (BB13)
Search:
    cmp Descriptors,Y
    beq Found
    dey
    bpl Search

;; Ends the statement with a type mismatch.
;; Also: BADMD (BB13)
ToTypeMismatchError:
    jmp ReportTypeMismatch

;; Gives the descriptor's type.
;; Also: GOTVAL (BB13)
Found:
    lda DescriptorValueTypes,Y
    rts
.endproc

.endscope

; ---------------------------------------------------------------------------------------------------------------------
; Text files
; ---------------------------------------------------------------------------------------------------------------------

; Statements: `OUTPUT#` and `EXEC`.
.scope Statements continued

;; `OUTPUT#`: sends `PRINT`'s output to a text file, or back to the console; `OUTPUT# file`, 0 for the console.
;;
;; <OutputFileNumber> and the byte after it get the file number less one, <Files::FILE_CONSOLE> for the console.
;; Errors: an illegal quantity for a file number above 10
;; Entry:
;;   Return = returns; <Exec> and <Files::SetNewlineMode> branch here
;; Also: OUTPUT (BB13)
.proc OutputFile
    jsr CheckNumberSign
    jsr EvaluateByte
    cpx #FILE_COUNT+1
    bcc InRange
    jmp IllegalQuantityError
InRange:
    dex
    txa
    sta OutputFileNumber
    sta OutputFileNumber+1
    bmi Return                              ; `OUTPUT#` 0: the console
    jsr Files::TakeFileNumber::FromIndex
    jsr Files::PrepareTextFile              ; a text file only

;; Returns.
;; Also: OUTRTS (BB13)
Return:
    rts
.endproc

;; `EXEC`: closes any `EXEC` file and opens the named text file for BASIC to take its input from.
;;
;; The file's reads end at a carriage return. A file of unknown type is closed and quietly ignored; any other type
;; but text is a type mismatch.
;; Out: ExecFile = the file's reference number, or 0
;; See: <Files::CloseExecFile>, <Console::ReadKey>
;; Also: EXEC (BB13)
.proc Exec
    lda ExecFile
    beq OpenFile
    sta SosCalls::Reference                 ; close the one before
    jsr Files::CloseSosFile

;; Opens the named file.
;; Also: EXEC2 (BB13)
OpenFile:
    lda #Files::OPEN_READ                   ; read only
    jsr Files::OpenNamed
    sta ExecFile
    lda SosCalls::FileType
    cmp #FILE_TYPE_TEXT
    beq Files::SetNewlineMode
    jsr Files::CloseSosFile                 ; not text: close it
    sta ExecFile                            ; A = 0
    lda SosCalls::FileType
    cmp #FILE_TYPE_UNKNOWN
    beq OutputFile::Return
    jmp RequireString::Mismatch
.endproc

.endscope

; Files: text files' new-line mode, and INPUT#'s line read.
.scope Files continued

;; Turns SOS's new-line mode on, at a carriage return, for a text file, closing it with the error if that fails.
;; In: SosCalls::Reference = the file's reference number
;; Also: EXRTS (BB13)
.proc SetNewlineMode
    lda SosCalls::Reference
    sta Console::NewlineParameters+1
    brk                                     ; SOS's NEWLINE
    .byte SOS_NEWLINE
    .word Console::NewlineParameters
    beq Statements::OutputFile::Return
    ; Falls into CloseWithError.
.endproc

;; Closes the file in <SosCalls::Reference>, then ends the statement with the SOS error in A.
;; In: A = the SOS error code, SosCalls::Reference = the file's reference number
;; See: <ReportSosError>
;; Also: CLTERR (BB13)
.proc CloseWithError
    pha
    jsr CloseSosFile
    pla
    jmp ReportSosError
.endproc

;; Reads a line for `INPUT#` from the text file in <OutputFileNumber> into <InputBuffer>, or the next catalog line from
;; a directory opened as a file.
;;
;; The read uses the console's list, <Console::LineParameters>, with the file's reference number in place of the
;; console's for the call. A carriage return ending the line is dropped.
;; Out: X = the low byte of the address before <InputBuffer>, Y = its high byte, as <InputLine::Terminate> leaves them
;; Entry:
;;   ReadFailed = takes a failed read's SOS error in A; `GET#` ends here when its read fails
;; See: <ReadTextLine::CatalogLine>, <Console::ReadKey>
;; Also: DSKLIN (BB13)
.proc ReadTextLine
;; A carriage return.
CARRIAGE_RETURN = $0D

;; How many bytes of <CatalogBuffer> a catalog line copies to <InputBuffer>: the line, its 0 and what follows it.
CATALOG_LINE_COPY = 79

    ldx OutputFileNumber
    jsr TakeFileNumber::FromIndex
    lda FileControlBlocks+FileControlBlock::SEGMENT,Y ; no buffer segment: a directory
    beq CatalogLine
    jsr PrepareTextFile
    jsr CheckReadAccess
    lda FileControlBlocks+FileControlBlock::REFERENCE_NUMBER,Y
    ldx Console::LineParameters+1
    sta Console::LineParameters+1
    brk                                     ; SOS's READ, from the file
    .byte SOS_READ
    .word Console::LineParameters
    stx Console::LineParameters+1           ; the console's reference number back
    beq DropReturn

;; Takes a failed read: the end of the file goes to `ON EOF#`'s handling in <Handlers::EndOfFile>; any other error ends
;; the statement.
;; In: A = the SOS error code
;; Also: DSKEOF (BB13)
ReadFailed:
    cmp #SOS_ERROR_END_OF_FILE
    beq ToEndOfFile
    jmp ReportSosError

;; Goes to the end-of-file handling in <Handlers::EndOfFile>.
;; Also: NMOR (BB13)
ToEndOfFile:
    jmp Handlers::EndOfFile

;; Drops the carriage return that ends the line.
;; Also: DSKLRT (BB13)
DropReturn:
    ldx Console::LineLength
    lda InputBuffer-1,X                     ; does a carriage return end the line?
    cmp #CARRIAGE_RETURN
    beq Finish
    inx

;; Ends the line in <InputBuffer>.
;; Also: DSKLRT1 (BB13)
Finish:
    dex
    jmp InputLine::Terminate

;; Makes the next catalog line with <Directory::NextLine> and copies it to <InputBuffer>, as `INPUT#` reads from a
;; directory.
;;
;; At the catalog's end, <ValueType> is left on the stack; <Handlers::EndOfFile> resets the stack, which discards it.
;; Also: LINCAT (BB13)
CatalogLine:
    lda ValueType
    pha
    jsr Directory::NextLine
    bcs ToEndOfFile                         ; the end of the catalog
    pla
    sta ValueType
    ldx #0

;; Copies the line's next byte.
;; Also: MVCATL (BB13)
CopyLine:
    lda CatalogBuffer,X
    sta InputBuffer,X
    inx
    cpx #CATALOG_LINE_COPY
    bcc CopyLine
    bcs Finish                              ; always
.endproc

.endscope
