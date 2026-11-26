; retrocore: style=strict
;; Segments: reading them in below <ProgramStackTop>, relocating their assembled procedures, counting their uses, and
;; giving them back.

; Assembled procedures.

;; Where an assembled procedure's attributes, at these offsets from its <JumpTable> as <ATTR_ENTER> is, start its
;; relocation lists: the first list's count word, where a p-code procedure keeps <ATTR_EXIT>.
ATTR_RELOCATION = -4

; Procedure dictionaries.

;; Where a segment's procedure dictionary, at its last word, keeps how many procedures the segment has, a byte.
SEG_PROCEDURE_COUNT = 1

;; Follows a self-relative pointer: a word that holds how far below itself the address it means is.
;; In: Dictionary = the word's address
;; Out: Procedure = the address it means, Y = 1
;; Keeps: X
;; Also: SETA7C (WK11)
.proc FollowSelfRelative
    ldy #0
    sec
    lda Dictionary
    sbc (Dictionary),y
    sta Procedure
    lda Dictionary+1
    iny
    sbc (Dictionary),y
    sta Procedure+1
    rts
.endproc

;; Relocates the words one of an assembled procedure's relocation lists names, by adding <Relocate::Amount> to each.
;;
;; A list is a count word, then that many self-relative pointers to the words, going down.
;; In: Procedure = the list's count word, Relocate::Amount = what to add
;; Out: Procedure = the word below the list, the next list's count
.proc Relocate

;; What <Relocate> adds to each word.
Amount = Work2

;; The count's high byte, counted down.
;; Also: LCNTH (WK11)
CountHigh = Result + 4

;; The word being relocated.
;; Also: NB8 (WK11)
Word = Pointer

    ; The count: its low byte in X, plus 1 for the DEX that ends each pass.
    ldy #0
    lda (Procedure),y
    tax
    inx
    iny
    lda (Procedure),y
    sta CountHigh
    jmp NextEntry

    ; Follow the entry to its word, and add Amount.
RelocateWord:
    ldy #0
    sec
    lda Procedure
    sbc (Procedure),y
    sta Word
    iny
    lda Procedure+1
    sbc (Procedure),y
    sta Word+1
    clc
    dey
    lda (Word),y
    adc Amount
    sta (Word),y
    iny
    lda (Word),y
    adc Amount+1
    sta (Word),y

    ; Down to the next entry, while the count lasts.
NextEntry:
    lda Procedure
    sec
    sbc #2
    sta Procedure
    bcs CountEntry
    dec Procedure+1
CountEntry:
    dex
    bne RelocateWord
    dec CountHigh
    bpl RelocateWord
    rts
.endproc

;; Reads a segment's code from its unit, as its <Syscom::SegmentTable> entry places it, into memory taken below
;; <ProgramStackTop>.
;;
;; A disk drive's segment is read through <BiosDiskRead>, and any other unit's through <BiosUnitDriver>, which runs the
;; unit's <UnitTable> routine. A character device's is a system I/O error.
;; In: A = the segment
;; Out: ProgramStackTop = where the code was read, ReadSegment::SegmentBase = the same
;; Also: RDSEG (WK11)
.proc ReadSegment

;; The segment, while A is worked into its <Syscom::SegmentTable> offset; then the segment's size.
;; Also: PCDSIZ (WK11)
Size = Pointer

;; Where the code is read, for <LoadSegment>.
SegmentBase = ReturnAddress

    ; X = the segment's Syscom::SegmentTable offset, the segment times 6.
    sta Size
    asl a
    clc
    adc Size
    asl a
    tax

    ; Push the control word, 0, and the drive word's high byte.
    lda #0
    pha
    pha
    pha

    ; What kind of unit? Y = its UnitTable offset.
    lda Syscom::SegmentTable + SegmentEntry::UNIT,x
    asl a
    tay
    lda UnitTable+1,y
    beq DiskUnit
    cmp #>CHARACTER_DEVICE
    beq SystemIo

    ; Another unit: its number, unless bit 7 is set, when it is its UnitTable entry's low byte as for a disk drive.
    lda Syscom::SegmentTable + SegmentEntry::UNIT,x
    bpl PushDrive
DiskUnit:
    lda UnitTable,y
PushDrive:
    pha

    ; Take the segment's size below ProgramStackTop, if need be once the heap's directory is given back.
    lda Syscom::SegmentTable + SegmentEntry::SIZE,x
    sta Size
    lda Syscom::SegmentTable + SegmentEntry::SIZE + 1,x
    sta Size+1
    lda ProgramStackTop
    sec
    sbc Size
    sta ProgramStackTop
    lda ProgramStackTop+1
    sbc Size+1
    sta ProgramStackTop+1
    bcc Overflow
    lda ProgramStackTop
    sbc HeapTop
    lda ProgramStackTop+1
    sbc HeapTop+1
    bcs Room
    jsr FreeDirectory
    sec
    lda ProgramStackTop
    sbc HeapTop
    lda ProgramStackTop+1
    sbc HeapTop+1
    bcs Room

;; Reports a stack overflow: the segment would reach the heap.
;; Also: JOOME2 (WK11)
Overflow:
    jmp ExecutionError::ResetForOverflow

    ; Push the buffer, ProgramStackTop, the byte count and the first block.
Room:
    lda ProgramStackTop+1
    sta SegmentBase+1
    pha
    lda ProgramStackTop
    sta SegmentBase
    pha
    lda Size+1
    pha
    lda Size
    pha
    lda Syscom::SegmentTable + SegmentEntry::BLOCK + 1,x
    pha
    lda Syscom::SegmentTable + SegmentEntry::BLOCK,x
    pha

    ; Read it.
    lda UnitTable+1,y
    beq ReadDisk
    lda Syscom::SegmentTable + SegmentEntry::UNIT,x
    ldx #0
    jsr BiosUnitDriver
    jmp CheckResult
ReadDisk:
    jsr BiosDiskRead

    ; X = 0, or the I/O error.
CheckResult:
    cpx #0
    beq Done
    stx Syscom::IoResult
SystemIo:
    jmp ExecutionError::SystemIo

Done:
    rts
.endproc

;; Counts a use of a segment, reading it in below <ProgramStackTop> when it had none and relocating its assembled
;; procedures.
;;
;; A data segment, with no block on disk, is given its size below <ProgramStackTop>. A code segment's assembled
;; procedures have four relocation lists, below their enter words: words relocated by the globals (the data segment the
;; procedure's <ATTR_LEXICAL_LEVEL> byte names, or else the globals' frame), by the segment's address, by the
;; procedure's own, and by <InterpAddress>, for .INTERP.
;; In: A = the segment
;; Out: LoadSegment::Segment = the segment, where <FindProcedureIn> takes it
;; Also: LODSEG (WK11)
.proc LoadSegment

;; The segment.
Segment = Work1

;; The dictionary word being worked on, from the segment's last word down.
DictionaryWord = Dictionary

;; Where <ReadSegment> read the segment.
SegmentBase = ReturnAddress

;; Where the globals are: the frame a call to the segment's outer block will build, or else <GlobalFrame>.
Globals = Work4

;; Where the assembled procedure being relocated starts.
ProcedureStart = Work3

;; The procedures still to look at.
ProceduresLeft = Buffer

    ; Is it in memory already?
    sta Segment
    asl a
    tay
    lda SegmentUses,y
    bne CountUse
    lda SegmentUses+1,y
    beq Load
CountUse:
    tya
    tax
    inc SegmentUses,x
    bne Counted
    inc SegmentUses+1,x
Counted:
    rts

    ; Keep ProgramStackTop for ReleaseSegmentUse, and count the use.
Load:
    lda ProgramStackTop
    sta SegmentKp,y
    lda ProgramStackTop+1
    sta SegmentKp+1,y
    lda #1
    sta SegmentUses,y

    ; X = the segment's Syscom::SegmentTable offset, the segment times 6.
    tya
    sta Pointer
    asl a
    clc
    adc Pointer
    tax

    ; A data segment has no block: give it its size below ProgramStackTop. Its address is 2 bytes below its data, so
    ; that the word LDE, LAE and STE number 1 is its first.
    lda Syscom::SegmentTable + SegmentEntry::BLOCK,x
    bne ReadCode
    lda Syscom::SegmentTable + SegmentEntry::BLOCK + 1,x
    bne ReadCode
    sec
    lda ProgramStackTop
    sbc Syscom::SegmentTable + SegmentEntry::SIZE,x
    sta ProgramStackTop
    lda ProgramStackTop+1
    sbc Syscom::SegmentTable + SegmentEntry::SIZE + 1,x
    sta ProgramStackTop+1
    lda ProgramStackTop
    sec
    sbc #2
    sta SegmentAddresses,y
    lda ProgramStackTop+1
    sbc #0
    sta SegmentAddresses+1,y
    rts

    ; A code segment: its dictionary will be its last word, just below ProgramStackTop. Read it.
ReadCode:
    sec
    lda ProgramStackTop
    sbc #2
    sta SegmentAddresses,y
    sta DictionaryWord
    lda ProgramStackTop+1
    sbc #0
    sta SegmentAddresses+1,y
    sta DictionaryWord+1
    lda Segment
    jsr ReadSegment

    ; How many procedures, and down to procedure 1's word.
    ldy #SEG_PROCEDURE_COUNT
    lda (DictionaryWord),y
    sta ProceduresLeft
    lda DictionaryWord
    sec
    sbc #2
    sta DictionaryWord
    bcs FindGlobals
    dec DictionaryWord+1

    ; When procedure 1 is at lexical level 0, the segment's outer block, the globals will be the frame a call to it
    ; builds below ProgramStackTop, as FindProcedure places it. Otherwise they are GlobalFrame's.
FindGlobals:
    jsr FollowSelfRelative
    ldy #ATTR_LEXICAL_LEVEL
    lda (Procedure),y
    cmp #1
    bcs UseBase
    lda Procedure
    sec
    sbc #ATTR_PROCEDURE_NUMBER - ATTR_DATA_SIZE
    sta Procedure
    bcs BelowData
    dec Procedure+1
BelowData:
    sec
    ldy #0
    lda ProgramStackTop
    sbc (Procedure),y
    sta Globals
    iny
    lda ProgramStackTop+1
    sbc (Procedure),y
    sta Globals+1
    iny
    sec
    lda Globals
    sbc (Procedure),y
    sta Globals
    bcs BelowParameters
    dec Globals+1
BelowParameters:
    lda Globals
    sec
    sbc #.sizeof(MarkStack)
    sta Globals
    bcs NextProcedure
    dec Globals+1
NextProcedure:
    jmp Procedures
UseBase:
    lda GlobalFrame
    sta Globals
    lda GlobalFrame+1
    sta Globals+1

    ; Each procedure: only an assembled one, numbered 0, is relocated.
Procedures:
    jsr FollowSelfRelative
    ldy #ATTR_PROCEDURE_NUMBER
    lda (Procedure),y
    bne Relocated

    ; Where it starts, from its enter word.
    lda Procedure
    sec
    sbc #ATTR_PROCEDURE_NUMBER - ATTR_ENTER
    sta Procedure
    bcs FollowEntry
    dec Procedure+1
FollowEntry:
    sec
    lda Procedure
    sbc (Procedure),y
    sta ProcedureStart
    iny
    lda Procedure+1
    sbc (Procedure),y
    sta ProcedureStart+1

    ; Down to the first list.
    lda Procedure
    sec
    sbc #ATTR_ENTER - ATTR_RELOCATION
    sta Procedure
    bcs FindDataSegment
    dec Procedure+1

    ; The globals: a data segment's, 2 bytes past its SegmentAddresses entry, when the procedure names one.
FindDataSegment:
    ldy #ATTR_LEXICAL_LEVEL - ATTR_RELOCATION
    lda (Procedure),y
    beq FrameGlobals
    asl a
    tay
    lda SegmentAddresses,y
    clc
    adc #2
    sta Relocate::Amount
    lda SegmentAddresses+1,y
    adc #0
    sta Relocate::Amount+1
    jmp RelocateGlobals
FrameGlobals:
    lda Globals
    sta Relocate::Amount
    lda Globals+1
    sta Relocate::Amount+1
RelocateGlobals:
    jsr Relocate

    ; The segment.
    lda SegmentBase
    sta Relocate::Amount
    lda SegmentBase+1
    sta Relocate::Amount+1
    jsr Relocate

    ; The procedure.
    lda ProcedureStart
    sta Relocate::Amount
    lda ProcedureStart+1
    sta Relocate::Amount+1
    jsr Relocate

    ; .INTERP.
    lda InterpAddress
    sta Relocate::Amount
    lda InterpAddress+1
    sta Relocate::Amount+1
    jsr Relocate

    ; Down to the next procedure's word.
Relocated:
    lda DictionaryWord
    sec
    sbc #2
    sta DictionaryWord
    bcs CountProcedure
    dec DictionaryWord+1
CountProcedure:
    dec ProceduresLeft
    beq Done
    jmp Procedures
Done:
    rts
.endproc

;; Gives back a use of a segment: when its uses fall to 0, <ProgramStackTop> goes back to where it was before the
;; segment was read. Segment 0, the system's, is never given back.
;; In: A = the segment
;; Also: UNLSEG (WK11)
.proc ReleaseSegmentUse
    asl a
    tax
    beq Done

    ; Count the use down.
    sec
    lda SegmentUses,x
    sbc #1
    sta SegmentUses,x
    bcs CheckUnused
    dec SegmentUses+1,x
    rts

    ; None left? Give the memory back.
CheckUnused:
    bne Done
    lda SegmentUses+1,x
    bne Done
    lda SegmentKp,x
    sta ProgramStackTop
    lda SegmentKp+1,x
    sta ProgramStackTop+1
Done:
    rts
.endproc

;; The standard procedures: the routine that runs each, as <CspTable> gives them for <Pcodes::CallStandardProcedure>.
;; Each is named for what it does; the names the documents give the standard procedure are its old names.
.scope StandardProcedures

;; <GSEG at StandardProcedures::GetSegment>: counts a use of the segment on the stack, reading it in if need be.
;; Also: CSP21 (WK11), GETSEG (UCSD20)
.proc GetSegment
    pla
    tax
    pla
    txa
    jsr LoadSegment
    jmp Fetch::Skip2
.endproc

;; <RSEG at StandardProcedures::ReleaseSegment>: gives back a use of the segment on the stack.
;; Also: CSP22 (WK11), RELSEG (UCSD20)
.proc ReleaseSegment
    pla
    tax
    pla
    txa
    jsr ReleaseSegmentUse
    jmp Fetch::Skip2
.endproc
.endscope
