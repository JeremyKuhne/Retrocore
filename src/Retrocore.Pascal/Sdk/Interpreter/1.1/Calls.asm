; retrocore: style=strict
;; Procedure calls and returns: finding a procedure's attributes, building its mark stack frame, and the call and
;; return handlers.

; Mark stack frames: what a call keeps in the frame it builds, at these offsets from the frame (MSCW_STATIC_LINK,
; at 0, is in Constants.asm). Each is a word but MSCW_STACK, a byte.

; A procedure's attributes, at these offsets from its JTAB, at the end of its code. The words below JTAB are
; self-relative: each holds how far below itself the address it means is.

; Procedure dictionaries.

;; Where a segment's procedure dictionary, at <SEG>, keeps the segment's number, a byte.
SEG_SEGMENT_NUMBER = 0

;; <FindProcedure::Segment>'s value for a procedure in the current segment, which <FindProcedure> tests by bit 7.
NO_SEGMENT = $FF

;; Finds a procedure of a segment in memory, and enters it as <FindProcedure> does.
;; In: ProcedureNumber = the procedure, FindProcedure::Segment = its segment, which <OpCXP> or <LoadSegment> sets
;; Out:
;;   Procedure = its attributes, from <ATTR_DATA_SIZE>, for a p-code procedure
;;   Mark = its frame, as <MP>, with its static link still to set
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

;; Finds a procedure of the current segment, steps <IPC> past the call, and enters the procedure.
;;
;; An assembled procedure is jumped to, with <FindProcedure::NativeReturn> as its return address, and FindProcedure does
;; not return. For a p-code procedure, FindProcedure builds its mark stack frame below <KP>, pulls its parameters from
;; the stack into the frame's locals, makes it the current procedure (<MP>, <JTAB>, <SEG>, <IPC> and <KP>, and SYSCOM's
;; copies) and returns.
;; In: ProcedureNumber = the procedure, IPC = the 2-byte call (or a 3-byte <CXP at OpCXP>, already stepped once)
;; Out:
;;   Procedure = its attributes, from <ATTR_DATA_SIZE>
;;   Mark = its frame, as <MP>, with its static link still to set
.proc FindProcedure

;; The procedure's segment, or <NO_SEGMENT> for the current one.
Segment = Work1

;; The dictionary of the procedure's segment, for <SEG> once the frame is built.
NewSeg = Result + 2

;; The procedure's word in the dictionary, then the attributes' enter word: each a self-relative pointer.
DictionaryWord = Pointer

;; <KP>, where the frame goes below.
FrameTop = Buffer

;; Where an assembled procedure starts.
NativeEntry = Dictionary

;; The word below the frame, which keeps the caller's <KP>.
KpLink = Pointer2

    .assert MP = BASE + MSCW_DYNAMIC_LINK && JTAB = BASE + MSCW_JTAB, "The frame keeps MP and JTAB as zero page does."
    .assert SEG = BASE + MSCW_SEG && IPC = BASE + MSCW_IPC, "The frame keeps SEG and IPC as zero page does."
    .assert MSCW_STACK = MSCW_IPC + 2, "The frame keeps the stack pointer after IPC."

    ; Keep the return address, from over the parameters.
    pla
    sta ReturnAddress
    pla
    sta ReturnAddress+1

    ; The current segment's dictionary.
    lda SEG
    sta NewSeg
    sta DictionaryWord
    lda SEG+1
    sta NewSeg+1
    sta DictionaryWord+1
    lda #NO_SEGMENT
    sta Segment

Search:
    lda KP
    sta FrameTop
    lda KP+1
    sta FrameTop+1

    ; Step IPC past the call.
    lda IPC
    clc
    adc #2
    sta IPC
    bcc FindWord
    inc IPC+1

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

    ; Follow it to the procedure's JTAB.
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

;; Where an assembled procedure's RTS returns to: runs the p-code after the call, as <IPC> already points there.
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
    sbc #MSCW_SIZE
    sta Mark
    lda Mark+1
    sbc #0
    sta Mark+1
    bcc Overflow

    ; It must stay above the heap, if need be once the heap's directory is given back.
    sec
    lda Mark
    sbc NP
    lda Mark+1
    sbc NP+1
    bcs Room
    jsr FreeDirectory
    sec
    lda Mark
    sbc NP
    lda Mark+1
    sbc NP+1
    bcs Room
Overflow:
    jmp ExecutionError::ResetForOverflow

    ; Keep the caller's MP, JTAB, SEG and IPC in the frame.
Room:
    ldy #MSCW_DYNAMIC_LINK
KeepRegister:
    lda BASE,y
    sta (Mark),y
    iny
    cpy #MSCW_STACK
    bne KeepRegister

    ; Pull the parameters into the start of the locals, after the frame.
    clc
    lda Mark
    adc #MSCW_SIZE
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
    ldy #MSCW_STACK
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
    sta IPC
    lda DictionaryWord+1
    iny
    sbc (DictionaryWord),y
    sta IPC+1

    ; Make it the current procedure.
    lda Procedure
    clc
    adc #ATTR_PROCEDURE_NUMBER - ATTR_DATA_SIZE
    sta JTAB
    sta SysJtab
    lda Procedure+1
    adc #0
    sta JTAB+1
    sta SysJtab+1
    lda Mark
    sta MP
    sta SysMp
    lda Mark+1
    sta MP+1
    sta SysMp+1

    ; Keep the caller's KP in the word below the frame, and take KP down to it.
    lda Mark
    sec
    sbc #KP_LINK_SIZE
    sta KpLink
    lda Mark+1
    sbc #0
    sta KpLink+1
    ldy #0
    lda KP
    sta (KpLink),y
    iny
    lda KP+1
    sta (KpLink),y
    lda KpLink
    sta KP
    lda KpLink+1
    sta KP+1

    ; Its segment.
    lda NewSeg
    sta SEG
    sta SysSeg
    lda NewSeg+1
    sta SEG+1
    sta SysSeg+1

    ; Return past the caller's JSR.
    inc ReturnAddress
    bne Return
    inc ReturnAddress+1
Return:
    jmp (ReturnAddress)
.endproc

;; <CIP at OpCIP>: calls an intermediate procedure, whose static link is the frame of the latest active procedure one
;; lexical level out.
.proc OpCIP

;; The lexical level of the procedure whose frame the static link must be.
OuterLevel = Result + 4

;; A frame on the way back through the dynamic links, whose <JTAB> and dynamic link are its caller's.
CallerFrame = Work2

;; The <JTAB> of <CallerFrame>'s caller.
CallerJtab = Work4

    ; Find the procedure and build its frame.
    ldy #1
    lda (IPC),y
    sta ProcedureNumber
    jsr FindProcedure

;; Where <OpCXP> goes for a procedure above lexical level 0.
;; In: Procedure = the attributes, from <ATTR_DATA_SIZE>, MP = Mark = the new frame
FindStaticLink:
    ldy #ATTR_LEXICAL_LEVEL - ATTR_DATA_SIZE
    lda (Procedure),y
    sta OuterLevel
    dec OuterLevel

    ; Go back from the new frame through the dynamic links.
    lda MP
    sta CallerFrame
    lda MP+1
    sta CallerFrame+1
    jmp CheckCaller
NextFrame:
    ldy #MSCW_DYNAMIC_LINK
    lda (CallerFrame),y
    tax
    iny
    lda (CallerFrame),y
    sta CallerFrame+1
    stx CallerFrame

    ; Is this frame's caller at the outer level?
CheckCaller:
    ldy #MSCW_JTAB
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
    ldy #MSCW_DYNAMIC_LINK
    lda (CallerFrame),y
    ldy #MSCW_STATIC_LINK
    sta (MP),y
    ldy #MSCW_DYNAMIC_LINK + 1
    lda (CallerFrame),y
    ldy #MSCW_STATIC_LINK + 1
    sta (MP),y
    jmp Fetch::Next
.endproc

;; <CLP at OpCLP>: calls a procedure local to the current one, whose static link is the caller's frame.
.proc OpCLP
    ; Find the procedure and build its frame.
    ldy #1
    lda (IPC),y
    sta ProcedureNumber
    jsr FindProcedure

    ; Its static link is its dynamic link.
    ldy #MSCW_DYNAMIC_LINK
    lda (Mark),y
    ldy #MSCW_STATIC_LINK
    sta (Mark),y
    ldy #MSCW_DYNAMIC_LINK + 1
    lda (Mark),y
    ldy #MSCW_STATIC_LINK + 1
    sta (Mark),y
    jmp Fetch::Next
.endproc

;; <CGP at OpCGP>: calls a global procedure, whose static link is <BASE>.
.proc OpCGP
    ; Find the procedure and build its frame.
    ldy #1
    lda (IPC),y
    sta ProcedureNumber
    jsr FindProcedure

    ; Its static link is BASE.
    ldy #MSCW_STATIC_LINK
    lda BASE
    sta (Mark),y
    lda BASE+1
    iny
    sta (Mark),y
    jmp Fetch::Next
.endproc

;; <CXP at OpCXP>: calls a procedure of another segment, loading the segment first unless it is segment 0, the system's,
;; which stays in memory. A procedure at lexical level 0 or below is called as <CBP at OpCBP> calls one, and the others
;; as <CIP at OpCIP> does.
.proc OpCXP

;; The segment, for <LoadSegment> and <FindProcedureIn>.
Segment = Work1

    ; The procedure and the segment.
    ldy #2
    lda (IPC),y
    sta ProcedureNumber
    ldy #1
    lda (IPC),y
    sta Segment
    beq StepIpc
    jsr LoadSegment

    ; Step IPC past the extra operand byte: FindProcedureIn steps it past the other two.
StepIpc:
    inc IPC
    bne Find
    inc IPC+1
Find:
    jsr FindProcedureIn

    ; Which call is it?
    ldy #ATTR_LEXICAL_LEVEL - ATTR_DATA_SIZE
    lda (Procedure),y
    beq OpCBP::NewBase
    bmi OpCBP::NewBase
    jmp OpCIP::FindStaticLink
.endproc

;; <CBP at OpCBP>: calls a base procedure, an outer block, which becomes <BASE>. The old <BASE> is pushed before the
;; frame keeps the stack pointer, so <RBP at OpRBP> finds it on top once it puts the stack back.
.proc OpCBP
    ; Find the procedure and build its frame.
    ldy #1
    lda (IPC),y
    sta ProcedureNumber
    jsr FindProcedure

;; Where <OpCXP> goes for a procedure at lexical level 0 or below.
;; In: Mark = the new frame
NewBase:
    ; Push the old BASE, and keep the stack pointer that leaves.
    lda BASE+1
    pha
    lda BASE
    pha
    tsx
    txa
    ldy #MSCW_STACK
    sta (Mark),y

    ; Its static link is the old base procedure's.
    ldy #MSCW_STATIC_LINK
    lda (BASE),y
    sta (Mark),y
    iny
    lda (BASE),y
    sta (Mark),y

    ; It becomes BASE.
    lda Mark
    sta BASE
    sta SysBase
    lda Mark+1
    sta BASE+1
    sta SysBase+1
    jmp Fetch::Next
.endproc

;; <RBP at OpRBP>: returns from a base procedure, giving back the old <BASE> that <CBP at OpCBP> pushed, and then as
;; <RNP at OpRNP> does.
.proc OpRBP
    ; Put the stack back, and pull the old BASE.
    ldy #MSCW_STACK
    lda (MP),y
    tax
    txs
    pla
    sta BASE
    sta SysBase
    pla
    sta BASE+1
    sta SysBase+1
    jmp OpRNP::Unwind
.endproc

;; <RNP at OpRNP>: returns from a procedure, pushing as many words of its result as the operand says, and giving back
;; its segment when the caller's differs.
.proc OpRNP

;; The word below the frame, which keeps the caller's <KP>.
KpLink = Pointer

;; The caller's <SEG>, from the frame.
CallerSeg = Pointer

    ; Put the stack back as the call left it.
    ldy #MSCW_STACK
    lda (MP),y
    tax
    txs

;; Where <RBP at OpRBP> goes on, once it has put the stack back and pulled the old <BASE>.
;; In: MP = the frame to return from
Unwind:
    ; Give back the stack below the frame.
    lda MP
    sec
    sbc #KP_LINK_SIZE
    sta KpLink
    lda MP+1
    sbc #0
    sta KpLink+1
    ldy #0
    lda (KpLink),y
    sta KP
    iny
    lda (KpLink),y
    sta KP+1

    ; Push the result's words, the first of the locals, from the last byte down.
    ldy #1
    lda (IPC),y
    asl a
    clc
    adc #MSCW_SIZE - 1
    tay
PushByte:
    cpy #MSCW_SIZE - 1
    beq CheckSegment
    lda (MP),y
    pha
    dey
    jmp PushByte

    ; Back to another segment? Then give back a use of this one.
CheckSegment:
    ldy #MSCW_SEG
    lda (MP),y
    sta CallerSeg
    iny
    lda (MP),y
    sta CallerSeg+1
    ldy #SEG_SEGMENT_NUMBER
    lda (SEG),y
    cmp (CallerSeg),y
    beq RestoreCaller
    jsr ReleaseSegment
    lda CallerSeg
    sta SEG
    sta SysSeg
    lda CallerSeg+1
    sta SEG+1
    sta SysSeg+1

    ; Make the caller current again.
RestoreCaller:
    ldy #MSCW_JTAB
    lda (MP),y
    sta JTAB
    sta SysJtab
    iny
    lda (MP),y
    sta JTAB+1
    sta SysJtab+1
    ldy #MSCW_IPC
    lda (MP),y
    sta IPC
    iny
    lda (MP),y
    sta IPC+1
    ldy #MSCW_DYNAMIC_LINK + 1
    lda (MP),y
    tax
    dey
    lda (MP),y
    sta MP
    sta SysMp
    stx MP+1
    stx SysMp+1
    jmp Fetch::Next
.endproc
