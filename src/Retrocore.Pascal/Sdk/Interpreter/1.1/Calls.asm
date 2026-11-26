; retrocore: style=strict
;; Procedure calls and returns: finding a procedure's attributes, building its mark stack frame, and the call and
;; return handlers.

; Procedure dictionaries.

;; Where a segment's procedure dictionary, at <ProcedureDictionary>, keeps the segment's number, a byte.
SEG_SEGMENT_NUMBER = 0

;; <FindProcedure::Segment>'s value for a procedure in the current segment, which <FindProcedure> tests by bit 7.
NO_SEGMENT = $FF

;; Finds a procedure of a segment in memory, and enters it as <FindProcedure> does.
;; In: ProcedureNumber = the procedure, FindProcedure::Segment = its segment, which <Pcodes::CallExternalProcedure> or
;;     <LoadSegment> sets
;; Out:
;;   Procedure = its attributes, from <ATTR_DATA_SIZE>, for a p-code procedure
;;   Mark = its frame, as <LocalFrame>, with its static link still to set
;; Also: CALLX (WK11)
.proc FindProcedureIn
    ; Keep the return address, from over the parameters.
    pla
    sta ReturnAddress
    pla
    sta ReturnAddress+1

    ; The segment's dictionary, from SegmentAddresses.
    lda FindProcedure::Segment
    asl a
    tay
    lda SegmentAddresses,y
    sta FindProcedure::NewSeg
    sta FindProcedure::DictionaryWord
    lda SegmentAddresses+1,y
    sta FindProcedure::NewSeg+1
    sta FindProcedure::DictionaryWord+1
    jmp FindProcedure::Search
.endproc

;; Finds a procedure of the current segment, steps <InstructionPointer> past the call, and enters the procedure.
;;
;; An assembled procedure is jumped to, with <FindProcedure::NativeReturn> as its return address, and FindProcedure does
;; not return. For a p-code procedure, FindProcedure builds its mark stack frame below <ProgramStackTop>, pulls its
;; parameters from the stack into the frame's locals, makes it the current procedure (<LocalFrame>, <JumpTable>,
;; <ProcedureDictionary>, <InstructionPointer> and <ProgramStackTop>, and SYSCOM's copies of the first three) and
;; returns.
;; In: ProcedureNumber = the procedure, InstructionPointer = the 2-byte call (or a 3-byte <CXP at
;;     Pcodes::CallExternalProcedure>, already stepped once)
;; Out:
;;   Procedure = its attributes, from <ATTR_DATA_SIZE>
;;   Mark = its frame, as <LocalFrame>, with its static link still to set
;; Also: CALAXX (WK11)
.proc FindProcedure

;; The procedure's segment, or <NO_SEGMENT> for the current one.
Segment = Work1

;; The dictionary of the procedure's segment, for <ProcedureDictionary> once the frame is built.
NewSeg = Result + 2

;; The procedure's word in the dictionary, then the attributes' enter word: each a self-relative pointer.
DictionaryWord = Pointer

;; <ProgramStackTop>, where the frame goes below.
FrameTop = Buffer

;; Where an assembled procedure starts.
NativeEntry = Dictionary

;; The word below the frame, which keeps the caller's <ProgramStackTop>.
KpLink = Pointer2

    .assert LocalFrame = GlobalFrame + MarkStack::DYNAMIC_LINK, "The frame keeps LocalFrame as zero page does."
    .assert JumpTable = GlobalFrame + MarkStack::JUMP_TABLE, "The frame keeps JumpTable as zero page does."
    .assert ProcedureDictionary = GlobalFrame + MarkStack::PROCEDURE_DICTIONARY, "Frames keep it as zero page does."
    .assert InstructionPointer = GlobalFrame + MarkStack::INSTRUCTION_POINTER, "Frames keep it as zero page does."
    .assert MarkStack::STACK_POINTER = MarkStack::INSTRUCTION_POINTER + 2, "The stack pointer is last."

    ; Keep the return address, from over the parameters.
    pla
    sta ReturnAddress
    pla
    sta ReturnAddress+1

    ; The current segment's dictionary.
    lda ProcedureDictionary
    sta NewSeg
    sta DictionaryWord
    lda ProcedureDictionary+1
    sta NewSeg+1
    sta DictionaryWord+1
    lda #NO_SEGMENT
    sta Segment

Search:
    lda ProgramStackTop
    sta FrameTop
    lda ProgramStackTop+1
    sta FrameTop+1

    ; Step InstructionPointer past the call.
    lda InstructionPointer
    clc
    adc #2
    sta InstructionPointer
    bcc FindWord
    inc InstructionPointer+1

    ; The procedure's word is 2 bytes a procedure below the dictionary's last word.
FindWord:
    lda DictionaryWord
    sec
    sbc ProcedureNumber
    sta DictionaryWord
    bcs SecondTime
    dec DictionaryWord+1
SecondTime:
    lda DictionaryWord
    sec
    sbc ProcedureNumber
    sta DictionaryWord
    bcs FollowWord
    dec DictionaryWord+1

    ; Follow it to the procedure's JumpTable.
FollowWord:
    ldy #0
    sec
    lda DictionaryWord
    sbc (DictionaryWord),y
    sta Procedure
    lda DictionaryWord+1
    iny
    sbc (DictionaryWord),y
    sta Procedure+1

    ; A p-code procedure has a number other than 0: build its frame.
    ldy #ATTR_PROCEDURE_NUMBER
    lda (Procedure),y
    bne BuildFrame

    ; An assembled procedure in another segment gives back the use LoadSegment counted, as no RNP will.
    lda Segment
    bmi FindEntry
    asl a
    tax
    sec
    lda SegmentUses,x
    sbc #1
    sta SegmentUses,x
    bcs FindEntry
    dec SegmentUses+1,x

    ; Follow the enter word to its code.
FindEntry:
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
    sta NativeEntry
    iny
    lda Procedure+1
    sbc (Procedure),y
    sta NativeEntry+1

    ; Jump to it, with NativeReturn as its return address.
    lda NativeReturnAddress+1
    pha
    lda NativeReturnAddress
    pha
    jmp (NativeEntry)

;; Where an assembled procedure's RTS returns to: runs the p-code after the call, as <InstructionPointer> already points
;; there.
;; Also: JXEM1 (WK11)
NativeReturn:
    jmp Fetch::Next

;; <NativeReturn> less 1, as RTS takes it, which <FindProcedure> pushes before jumping into an assembled procedure.
NativeReturnAddress:
    .word NativeReturn - 1

    ; Move Procedure down to the data size.
BuildFrame:
    lda Procedure
    sec
    sbc #ATTR_PROCEDURE_NUMBER - ATTR_DATA_SIZE
    sta Procedure
    bcs PlaceFrame
    dec Procedure+1

    ; The frame goes below the data and the parameters: no more than 255 bytes of them.
PlaceFrame:
    sec
    ldy #0
    lda FrameTop
    sbc (Procedure),y
    sta Mark
    lda FrameTop+1
    iny
    sbc (Procedure),y
    sta Mark+1
    bcc Overflow
    ldy #ATTR_PARAMETER_SIZE - ATTR_DATA_SIZE + 1
    lda (Procedure),y
    bne Overflow
    dey
    lda Mark
    sec
    sbc (Procedure),y
    sta Mark
    bcs BelowFrame
    lda Mark+1
    sbc #0
    sta Mark+1
    bcc Overflow

    ; Then the frame itself.
BelowFrame:
    lda Mark
    sec
    sbc #.sizeof(MarkStack)
    sta Mark
    lda Mark+1
    sbc #0
    sta Mark+1
    bcc Overflow

    ; It must stay above the heap, if need be once the heap's directory is given back.
    sec
    lda Mark
    sbc HeapTop
    lda Mark+1
    sbc HeapTop+1
    bcs Room
    jsr FreeDirectory
    sec
    lda Mark
    sbc HeapTop
    lda Mark+1
    sbc HeapTop+1
    bcs Room

;; Reports a stack overflow: the new frame would reach the heap.
;; Also: JOOME1 (WK11)
Overflow:
    jmp ExecutionError::ResetForOverflow

    ; Keep the caller's LocalFrame, JumpTable, ProcedureDictionary and InstructionPointer in the frame.
Room:
    ldy #MarkStack::DYNAMIC_LINK
KeepRegister:
    lda GlobalFrame,y
    sta (Mark),y
    iny
    cpy #MarkStack::STACK_POINTER
    bne KeepRegister

    ; Pull the parameters into the start of the locals, after the frame.
    clc
    lda Mark
    adc #.sizeof(MarkStack)
    sta Target
    lda Mark+1
    adc #0
    sta Target+1
    ldy #ATTR_PARAMETER_SIZE - ATTR_DATA_SIZE
    lda (Procedure),y
    ldy #0
    tax
    jmp CountParameter
PullParameter:
    pla
    sta (Target),y
    iny
    dex
CountParameter:
    bne PullParameter

    ; Keep the stack pointer they leave.
    tsx
    txa
    ldy #MarkStack::STACK_POINTER
    sta (Mark),y

    ; Start at the procedure's first p-code, from its enter word.
    lda Procedure
    clc
    adc #ATTR_ENTER - ATTR_DATA_SIZE
    sta DictionaryWord
    lda Procedure+1
    adc #0
    sta DictionaryWord+1
    ldy #0
    sec
    lda DictionaryWord
    sbc (DictionaryWord),y
    sta InstructionPointer
    lda DictionaryWord+1
    iny
    sbc (DictionaryWord),y
    sta InstructionPointer+1

    ; Make it the current procedure.
    lda Procedure
    clc
    adc #ATTR_PROCEDURE_NUMBER - ATTR_DATA_SIZE
    sta JumpTable
    sta Syscom::SavedJumpTable
    lda Procedure+1
    adc #0
    sta JumpTable+1
    sta Syscom::SavedJumpTable+1
    lda Mark
    sta LocalFrame
    sta Syscom::SavedLocalFrame
    lda Mark+1
    sta LocalFrame+1
    sta Syscom::SavedLocalFrame+1

    ; Keep the caller's ProgramStackTop in the word below the frame, and take ProgramStackTop down to it.
    lda Mark
    sec
    sbc #KP_LINK_SIZE
    sta KpLink
    lda Mark+1
    sbc #0
    sta KpLink+1
    ldy #0
    lda ProgramStackTop
    sta (KpLink),y
    iny
    lda ProgramStackTop+1
    sta (KpLink),y
    lda KpLink
    sta ProgramStackTop
    lda KpLink+1
    sta ProgramStackTop+1

    ; Its segment.
    lda NewSeg
    sta ProcedureDictionary
    sta Syscom::SavedProcedureDictionary
    lda NewSeg+1
    sta ProcedureDictionary+1
    sta Syscom::SavedProcedureDictionary+1

    ; Return past the caller's JSR.
    inc ReturnAddress
    bne Return
    inc ReturnAddress+1
Return:
    jmp (ReturnAddress)
.endproc

;; The p-code handlers: the routine that runs each opcode, as <OpcodeTable> gives them, but for <Fetch>, which pushes an
;; <SLDC> itself, <Jump>'s <FJP> and <UJP>, and <EFJ> and <NFJ>, which 1.1 doesn't implement. Each is named for what its
;; p-code does; the mnemonics Apple's manual and UCSD's listings give the p-code are its old names.
.scope Pcodes

;; <CIP at Pcodes::CallIntermediateProcedure>: calls an intermediate procedure, whose static link is the frame of the
;; latest active procedure one lexical level out.
;; Also: CIP (A2POSRM, UCSD20, WK11)
.proc CallIntermediateProcedure

;; The lexical level of the procedure whose frame the static link must be.
;; Also: MLEXLV (WK11)
OuterLevel = Result + 4

;; A frame on the way back through the dynamic links, whose <JumpTable> and dynamic link are its caller's.
;; Also: TMSPTR (WK11)
CallerFrame = Work2

;; The <JumpTable> of <CallerFrame>'s caller.
;; Also: TJTPTR (WK11)
CallerJtab = Work4

    ; Find the procedure and build its frame.
    ldy #1
    lda (InstructionPointer),y
    sta ProcedureNumber
    jsr FindProcedure

;; Where <Pcodes::CallExternalProcedure> goes for a procedure above lexical level 0.
;; In: Procedure = the attributes, from <ATTR_DATA_SIZE>, LocalFrame = Mark = the new frame
;; Also: CPCOMA (WK11)
FindStaticLink:
    ldy #ATTR_LEXICAL_LEVEL - ATTR_DATA_SIZE
    lda (Procedure),y
    sta OuterLevel
    dec OuterLevel

    ; Go back from the new frame through the dynamic links.
    lda LocalFrame
    sta CallerFrame
    lda LocalFrame+1
    sta CallerFrame+1
    jmp CheckCaller
NextFrame:
    ldy #MarkStack::DYNAMIC_LINK
    lda (CallerFrame),y
    tax
    iny
    lda (CallerFrame),y
    sta CallerFrame+1
    stx CallerFrame

    ; Is this frame's caller at the outer level?
CheckCaller:
    ldy #MarkStack::JUMP_TABLE
    lda (CallerFrame),y
    sta CallerJtab
    iny
    lda (CallerFrame),y
    sta CallerJtab+1
    ldy #ATTR_LEXICAL_LEVEL
    lda (CallerJtab),y
    cmp OuterLevel
    bne NextFrame

    ; Then the caller's frame is the static link.
    ldy #MarkStack::DYNAMIC_LINK
    lda (CallerFrame),y
    ldy #MarkStack::STATIC_LINK
    sta (LocalFrame),y
    ldy #MarkStack::DYNAMIC_LINK + 1
    lda (CallerFrame),y
    ldy #MarkStack::STATIC_LINK + 1
    sta (LocalFrame),y
    jmp Fetch::Next
.endproc

;; <CLP at Pcodes::CallLocalProcedure>: calls a procedure local to the current one, whose static link is the caller's
;; frame.
;; Also: CLP (A2POSRM, UCSD20, WK11)
.proc CallLocalProcedure
    ; Find the procedure and build its frame.
    ldy #1
    lda (InstructionPointer),y
    sta ProcedureNumber
    jsr FindProcedure

    ; Its static link is its dynamic link.
    ldy #MarkStack::DYNAMIC_LINK
    lda (Mark),y
    ldy #MarkStack::STATIC_LINK
    sta (Mark),y
    ldy #MarkStack::DYNAMIC_LINK + 1
    lda (Mark),y
    ldy #MarkStack::STATIC_LINK + 1
    sta (Mark),y
    jmp Fetch::Next
.endproc

;; <CGP at Pcodes::CallGlobalProcedure>: calls a global procedure, whose static link is <GlobalFrame>.
;; Also: CGP (A2POSRM, UCSD20, WK11)
.proc CallGlobalProcedure
    ; Find the procedure and build its frame.
    ldy #1
    lda (InstructionPointer),y
    sta ProcedureNumber
    jsr FindProcedure

    ; Its static link is GlobalFrame.
    ldy #MarkStack::STATIC_LINK
    lda GlobalFrame
    sta (Mark),y
    lda GlobalFrame+1
    iny
    sta (Mark),y
    jmp Fetch::Next
.endproc

;; <CXP at Pcodes::CallExternalProcedure>: calls a procedure of another segment, loading the segment first unless it is
;; segment 0, the system's, which stays in memory. A procedure at lexical level 0 or below is called as
;; <CBP at Pcodes::CallBaseProcedure> calls one, and the others as <CIP at Pcodes::CallIntermediateProcedure> does.
;; Also: CXP (A2POSRM, UCSD20, WK11)
.proc CallExternalProcedure

;; The segment, for <LoadSegment> and <FindProcedureIn>.
Segment = Work1

    ; The procedure and the segment.
    ldy #2
    lda (InstructionPointer),y
    sta ProcedureNumber
    ldy #1
    lda (InstructionPointer),y
    sta Segment
    beq StepIpc
    jsr LoadSegment

    ; Step InstructionPointer past the extra operand byte: FindProcedureIn steps it past the other two.
StepIpc:
    inc InstructionPointer
    bne Find
    inc InstructionPointer+1
Find:
    jsr FindProcedureIn

    ; Which call is it?
    ldy #ATTR_LEXICAL_LEVEL - ATTR_DATA_SIZE
    lda (Procedure),y
    beq Pcodes::CallBaseProcedure::NewBase
    bmi Pcodes::CallBaseProcedure::NewBase
    jmp Pcodes::CallIntermediateProcedure::FindStaticLink
.endproc

;; <CBP at Pcodes::CallBaseProcedure>: calls a base procedure, an outer block, which becomes <GlobalFrame>. The old
;; <GlobalFrame> is pushed before the frame keeps the stack pointer, so <RBP at Pcodes::ReturnFromBaseProcedure> finds
;; it on top once it puts the stack back.
;; Also: CBP (A2POSRM, UCSD20, WK11)
.proc CallBaseProcedure
    ; Find the procedure and build its frame.
    ldy #1
    lda (InstructionPointer),y
    sta ProcedureNumber
    jsr FindProcedure

;; Where <Pcodes::CallExternalProcedure> goes for a procedure at lexical level 0 or below.
;; In: Mark = the new frame
;; Also: CPCOMB (WK11)
NewBase:
    ; Push the old GlobalFrame, and keep the stack pointer that leaves.
    lda GlobalFrame+1
    pha
    lda GlobalFrame
    pha
    tsx
    txa
    ldy #MarkStack::STACK_POINTER
    sta (Mark),y

    ; Its static link is the old base procedure's.
    ldy #MarkStack::STATIC_LINK
    lda (GlobalFrame),y
    sta (Mark),y
    iny
    lda (GlobalFrame),y
    sta (Mark),y

    ; It becomes GlobalFrame.
    lda Mark
    sta GlobalFrame
    sta Syscom::SavedGlobalFrame
    lda Mark+1
    sta GlobalFrame+1
    sta Syscom::SavedGlobalFrame+1
    jmp Fetch::Next
.endproc

;; <RBP at Pcodes::ReturnFromBaseProcedure>: returns from a base procedure, giving back the old <GlobalFrame> that
;; <CBP at Pcodes::CallBaseProcedure> pushed, and then as <RNP at Pcodes::ReturnFromProcedure> does.
;; Also: RBP (A2POSRM, UCSD20, WK11)
.proc ReturnFromBaseProcedure
    ; Put the stack back, and pull the old GlobalFrame.
    ldy #MarkStack::STACK_POINTER
    lda (LocalFrame),y
    tax
    txs
    pla
    sta GlobalFrame
    sta Syscom::SavedGlobalFrame
    pla
    sta GlobalFrame+1
    sta Syscom::SavedGlobalFrame+1
    jmp Pcodes::ReturnFromProcedure::Unwind
.endproc

;; <RNP at Pcodes::ReturnFromProcedure>: returns from a procedure, pushing as many words of its result as the operand
;; says, and giving back its segment when the caller's differs.
;; Also: RNP (A2POSRM, UCSD20, WK11)
.proc ReturnFromProcedure

;; The word below the frame, which keeps the caller's <ProgramStackTop>.
KpLink = Pointer

;; The caller's <ProcedureDictionary>, from the frame.
CallerSeg = Pointer

    ; Put the stack back as the call left it.
    ldy #MarkStack::STACK_POINTER
    lda (LocalFrame),y
    tax
    txs

;; Where <RBP at Pcodes::ReturnFromBaseProcedure> goes on, once it has put the stack back and pulled the old
;; <GlobalFrame>.
;; In: LocalFrame = the frame to return from
Unwind:
    ; Give back the stack below the frame.
    lda LocalFrame
    sec
    sbc #KP_LINK_SIZE
    sta KpLink
    lda LocalFrame+1
    sbc #0
    sta KpLink+1
    ldy #0
    lda (KpLink),y
    sta ProgramStackTop
    iny
    lda (KpLink),y
    sta ProgramStackTop+1

    ; Push the result's words, the first of the locals, from the last byte down.
    ldy #1
    lda (InstructionPointer),y
    asl a
    clc
    adc #.sizeof(MarkStack) - 1
    tay
PushByte:
    cpy #.sizeof(MarkStack) - 1
    beq CheckSegment
    lda (LocalFrame),y
    pha
    dey
    jmp PushByte

    ; Back to another segment? Then give back a use of this one.
CheckSegment:
    ldy #MarkStack::PROCEDURE_DICTIONARY
    lda (LocalFrame),y
    sta CallerSeg
    iny
    lda (LocalFrame),y
    sta CallerSeg+1
    ldy #SEG_SEGMENT_NUMBER
    lda (ProcedureDictionary),y
    cmp (CallerSeg),y
    beq RestoreCaller
    jsr ReleaseSegmentUse
    lda CallerSeg
    sta ProcedureDictionary
    sta Syscom::SavedProcedureDictionary
    lda CallerSeg+1
    sta ProcedureDictionary+1
    sta Syscom::SavedProcedureDictionary+1

    ; Make the caller current again.
RestoreCaller:
    ldy #MarkStack::JUMP_TABLE
    lda (LocalFrame),y
    sta JumpTable
    sta Syscom::SavedJumpTable
    iny
    lda (LocalFrame),y
    sta JumpTable+1
    sta Syscom::SavedJumpTable+1
    ldy #MarkStack::INSTRUCTION_POINTER
    lda (LocalFrame),y
    sta InstructionPointer
    iny
    lda (LocalFrame),y
    sta InstructionPointer+1
    ldy #MarkStack::DYNAMIC_LINK + 1
    lda (LocalFrame),y
    tax
    dey
    lda (LocalFrame),y
    sta LocalFrame
    sta Syscom::SavedLocalFrame
    stx LocalFrame+1
    stx Syscom::SavedLocalFrame+1
    jmp Fetch::Next
.endproc
.endscope
