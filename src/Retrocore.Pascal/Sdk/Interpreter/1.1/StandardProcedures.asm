; retrocore: style=strict
;; Standard procedures: <CSP at Pcodes::CallStandardProcedure>'s dispatch, and the standard procedures not grouped
;; elsewhere, with <BPT at Pcodes::Breakpoint>.

; The Compiler's identifier tree, which TRS searches.

;; How many bytes of a name a tree node holds, from its start.
TREE_NAME_LENGTH = 8

;; Where a tree node keeps its link to the names greater than its own.
TREE_GREATER_LINK = 8

;; Where a tree node keeps its link to the names less than its own.
TREE_LESS_LINK = 10

;; What <TRS at StandardProcedures::TreeSearch> returns when it finds the name.
TREE_FOUND = 0

;; What <TRS at StandardProcedures::TreeSearch> returns, as both bytes, when the name is not there and would go on a
;; node's <TREE_LESS_LINK>: -1.
TREE_LESS = $FF

;; What <TRS at StandardProcedures::TreeSearch> returns when the name is not there and would go on a node's
;; <TREE_GREATER_LINK>.
TREE_GREATER = 1

; Pcodes: CallStandardProcedure.
.scope Pcodes continued

;; <CSP at Pcodes::CallStandardProcedure>: runs the standard procedure its operand numbers, through <CspDispatch> and
;; <CspTable>.
;; Also: CSP (A2POSRM, UCSD20, WK11)
.proc CallStandardProcedure
    ldy #1
    lda (InstructionPointer),y
    asl a
    sta CspDispatchLow
    jmp CspDispatch
.endproc
.endscope

; StandardProcedures: IdentifierSearch, TreeSearch, FillCharacters, Scan and ExitProcedure.
.scope StandardProcedures continued

;; <IDS at StandardProcedures::IdentifierSearch>: the Compiler's identifier search, which <IdSearch> runs in bank 2.
;; Also: CSP7 (WK11), IDS (A2POSRM, UCSD20), IDSEARCH (A2POSRM, UCSD20)
.proc IdentifierSearch
    jsr BiosIdSearch
    jmp Fetch::Skip2
.endproc

;; <TRS at StandardProcedures::TreeSearch>: searches the Compiler's identifier tree for a name, and pushes <TREE_FOUND>,
;; <TREE_LESS> or <TREE_GREATER>.
;;
;; Its parameters, from the top of the stack: the name's address, the variable to set to the last node it reached,
;; and the root node. The names compare a byte at a time, with BMI.
;; Also: TREES (WK11), TREESEARCH (A2POSRM, UCSD20), TRS (A2POSRM, UCSD20)
.proc TreeSearch

;; The name to find.
Name = ProcedureNumber

;; The variable <TRS at StandardProcedures::TreeSearch> sets to the last node it reached.
FoundNode = Pointer

;; The node it is at.
Node = Pointer2

    ; Pull the parameters.
    pla
    sta Name
    pla
    sta Name+1
    pla
    sta FoundNode
    pla
    sta FoundNode+1
    pla
    sta Node
    pla
    sta Node+1

    ; Compare the names a byte at a time, Y starting one before the first.
CompareNode:
    ldx #TREE_NAME_LENGTH
    ldy #$FF
CompareByte:
    dex
    bmi Found
    iny
    lda (Name),y
    cmp (Node),y
    beq CompareByte
    bmi GoLess

    ; Greater: on along the greater link, unless it is NIL.
    ldy #TREE_GREATER_LINK
    lda (Node),y
    tax
    iny
    lda (Node),y
    cmp #0
    bne FollowGreater
    cpx #0
    beq Greater
FollowGreater:
    stx Node
    sta Node+1
    jmp CompareNode

    ; Less: on along the less link, unless it is NIL.
GoLess:
    ldy #TREE_LESS_LINK
    lda (Node),y
    tax
    iny
    lda (Node),y
    cmp #0
    bne FollowLess
    cpx #0
    beq Less
FollowLess:
    stx Node
    sta Node+1
    jmp CompareNode

    ; Push the result.
Found:
    lda #TREE_FOUND
    pha
    pha
    jmp SetFound
Less:
    lda #TREE_LESS
    pha
    pha
    jmp SetFound
Greater:
    lda #0
    pha
    lda #TREE_GREATER
    pha

    ; Set the variable to the node.
SetFound:
    ldy #0
    lda Node
    sta (FoundNode),y
    iny
    lda Node+1
    sta (FoundNode),y
    jmp Fetch::Skip2
.endproc

;; <FLC at StandardProcedures::FillCharacters>: fills bytes with a character. Its parameters, from the top of the stack:
;; the character, the count, and two words that add to the first byte's address, an address and an offset. A negative
;; count fills nothing.
;; Also: FILLC (WK11), FILLCHAR (A2POSRM, UCSD20), FLC (A2POSRM, UCSD20)
.proc FillCharacters

;; How many bytes to fill.
Count = Offset

    ; Pull the character, in X, and the count.
    pla
    tax
    pla
    pla
    sta Count
    pla
    sta Count+1
    bpl Fill
    pla
    pla
    pla
    pla
    jmp Fetch::Skip2

    ; Target = the sum of the two words.
Fill:
    pla
    sta Target
    pla
    sta Target+1
    clc
    pla
    adc Target
    sta Target
    pla
    adc Target+1
    sta Target+1

    ; Fill the whole pages.
    txa
    ldx Count+1
    ldy #0
NextPage:
    cpx #0
    beq LastPart
    dex
FillPage:
    sta (Target),y
    iny
    bne FillPage
    inc Target+1
    jmp NextPage

    ; Then the bytes left.
LastPart:
    ldx Count
    jmp CountByte
FillByte:
    sta (Target),y
    iny
    dex
CountByte:
    bne FillByte
    jmp Fetch::Skip2
.endproc

;; <SCN at StandardProcedures::Scan>: scans bytes for one that is, or is not, a character, and pushes how far it went
;; from the start.
;;
;; Its parameters, from the top of the stack: a word it ignores, two words that add to the start's address, the
;; character, the mode, and the limit, how far to go. A negative limit scans down. The byte at the limit is checked
;; too, so the result is the limit when no byte stops the scan.
;; Also: SCAN (A2POSRM, UCSD20, WK11), SCN (A2POSRM, UCSD20)
.proc Scan

;; The byte being checked.
Cursor = Procedure

;; Where the scan stops, the start plus the limit.
Limit = Result

;; Where the scan starts.
Start = Result + 4

;; The character the bytes are compared with.
Wanted = Work2

;; 0 to stop at a byte that is the character, or else at one that is not.
Mode = Work3

;; The limit's high byte: negative to scan down.
Direction = Work1

;; The limit. When the scan's end address is $8000 or above, the low byte is replaced by its two's complement, and the
;; high byte by the end address's high byte's complement plus that carry. Nothing reads it.
Distance = Offset

    ; Pull the parameters.
    pla
    pla
    pla
    sta Cursor
    pla
    sta Cursor+1
    clc
    pla
    adc Cursor
    sta Cursor
    sta Start
    pla
    adc Cursor+1
    sta Cursor+1
    sta Start+1
    pla
    sta Wanted
    pla
    pla
    sta Mode
    pla
    pla
    sta Distance
    clc
    adc Start
    sta Limit
    pla
    sta Distance+1
    sta Direction
    adc Start+1
    sta Limit+1
    bpl Scan
    tax
    lda Distance
    eor #$FF
    clc
    adc #1
    sta Distance
    txa
    eor #$FF
    adc #0
    sta Distance+1

    ; Does this byte stop the scan?
Scan:
    ldy #0
CheckByte:
    lda (Cursor),y
    cmp Wanted
    bne NotCharacter
    lda Mode
    beq Done
    jmp CheckLimit
NotCharacter:
    lda Mode
    bne Done

    ; Or is it the last?
CheckLimit:
    lda Limit
    cmp Cursor
    bne Step
    lda Limit+1
    cmp Cursor+1
    beq Done

    ; On to the next byte, up or down.
Step:
    lda Direction
    bmi StepDown
    inc Cursor
    bne CheckByte
    inc Cursor+1
    jmp CheckByte
StepDown:
    lda Cursor
    sec
    sbc #1
    sta Cursor
    bcs CheckByte
    dec Cursor+1
    jmp CheckByte

    ; Push how far it went.
Done:
    lda Cursor
    sec
    sbc Start
    tax
    lda Cursor+1
    sbc Start+1
    pha
    txa
    pha
    jmp Fetch::Skip2
.endproc

;; <EXIT at StandardProcedures::ExitProcedure>: leaves a procedure, by sending the current procedure to its exit code
;; and each caller's frame back to the procedure to its caller's, so each returns into its exit code. Its parameters,
;; from the top of the stack: the procedure and its segment.
;;
;; In the system's outer block, at a negative lexical level, it leaves the system through <Pcodes::ExitSystem>. Reaching
;; that block without finding the procedure is <ExecutionError::ExitFromUncalledProc>.
;; Also: EXIT (A2POSRM, UCSD20, WK11)
.proc ExitProcedure

;; The procedure to leave.
ExitProcedure = ProcedureNumber

;; Its segment.
ExitSegment = Work1

;; A frame on the way back through the dynamic links, whose <JumpTable>, <ProcedureDictionary> and dynamic link are its
;; caller's.
CallerFrame = Work2

;; The <JumpTable> of <CallerFrame>'s caller, then its exit word.
CallerJtab = Pointer2

;; The current procedure's exit word, then <CallerFrame>'s caller's <ProcedureDictionary>.
Word = Pointer

    ; Pull the parameters.
    pla
    sta ExitProcedure
    pla
    pla
    sta ExitSegment
    pla

    ; Leave the system from its outer block.
    ldy #ATTR_LEXICAL_LEVEL
    lda (JumpTable),y
    bpl ExitCurrent
    jmp Pcodes::ExitSystem

    ; Send the current procedure to its exit code.
ExitCurrent:
    lda JumpTable
    sec
    sbc #ATTR_PROCEDURE_NUMBER - ATTR_EXIT
    sta Word
    lda JumpTable+1
    sbc #0
    sta Word+1
    ldy #0
    lda Word
    sec
    sbc (Word),y
    sta InstructionPointer
    iny
    lda Word+1
    sbc (Word),y
    sta InstructionPointer+1

    ; Is it the one to leave?
    dey
    lda ExitProcedure
    cmp (JumpTable),y
    bne FindCaller
    lda ExitSegment
    cmp (ProcedureDictionary),y
    bne FindCaller
    jmp Fetch::Next

    ; Go back from the current frame through the dynamic links.
FindCaller:
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

    ; The frame's caller: an error when it is the system's outer block.
CheckCaller:
    ldy #MarkStack::JUMP_TABLE
    lda (CallerFrame),y
    sta CallerJtab
    iny
    lda (CallerFrame),y
    sta CallerJtab+1
    ldy #ATTR_LEXICAL_LEVEL
    lda (CallerJtab),y
    bpl ExitCaller
    jmp ExecutionError::ExitFromUncalledProc

    ; Return into the caller's exit code.
ExitCaller:
    lda CallerJtab
    sec
    sbc #ATTR_PROCEDURE_NUMBER - ATTR_EXIT
    sta CallerJtab
    bcs SetIpc
    dec CallerJtab+1
SetIpc:
    ldy #0
    lda CallerJtab
    sec
    sbc (CallerJtab),y
    ldy #MarkStack::INSTRUCTION_POINTER
    sta (CallerFrame),y
    ldy #1
    lda CallerJtab+1
    sbc (CallerJtab),y
    ldy #MarkStack::INSTRUCTION_POINTER + 1
    sta (CallerFrame),y

    ; Is the caller the one to leave?
    ldy #ATTR_PROCEDURE_NUMBER - ATTR_EXIT
    lda ExitProcedure
    cmp (CallerJtab),y
    bne NextFrame
    ldy #MarkStack::PROCEDURE_DICTIONARY
    lda (CallerFrame),y
    sta Word
    iny
    lda (CallerFrame),y
    sta Word+1
    lda ExitSegment
    ldy #SEG_SEGMENT_NUMBER
    cmp (Word),y
    bne NextFrame
    jmp Fetch::Next
.endproc
.endscope

; Pcodes: Breakpoint.
.scope Pcodes continued

;; <BPT at Pcodes::Breakpoint>: a breakpoint, which SYSTEM.APPLE steps over with its big operand.
;; Also: BPT (A2POSRM, UCSD20, WK11)
.proc Breakpoint
    ldy #1
    jsr GetBig
    jmp Fetch::Skip2
.endproc
.endscope

; StandardProcedures: Halt and Time.
.scope StandardProcedures continued

;; <HLT at StandardProcedures::Halt>: steps <InstructionPointer> past the <CSP at Pcodes::CallStandardProcedure> and
;; reports <ExecutionError::Interrupted>.
;; Also: CSP39 (WK11), HALT (UCSD20)
.proc Halt
    lda InstructionPointer
    clc
    adc #2
    sta InstructionPointer
    bcc Report
    inc InstructionPointer+1
Report:
    jmp ExecutionError::Interrupted
.endproc

;; <TIM at StandardProcedures::Time>: sets both of its variables, the time's two words, to 0, as the Apple II has no
;; clock. Its parameters, from the top of the stack: the two variables' addresses.
;; Also: TIM (A2POSRM, UCSD20), TIME (A2POSRM, UCSD20, WK11)
.proc Time

;; The variable on top.
First = Pointer

;; The variable below it.
Second = Pointer2

    ; Pull the variables.
    pla
    sta First
    pla
    sta First+1
    pla
    sta Second
    pla
    sta Second+1

    ; Clear them.
    ldy #0
    lda #0
    sta (First),y
    sta (Second),y
    iny
    sta (First),y
    sta (Second),y
    jmp Fetch::Skip2
.endproc
.endscope

;; MVR's move: copies bytes from <Source> to <Target>, the last byte first, so a move up in memory does not overwrite
;; bytes before it copies them.
;; In: <Source>, Target = the first bytes, MoveBytesBackward::Count = how many
.proc MoveBytesBackward

;; How many bytes to copy.
Count = Offset

    ; Point past the last bytes.
    lda Source
    clc
    adc Count
    sta Source
    lda Source+1
    adc Count+1
    sta Source+1
    lda Target
    clc
    adc Count
    sta Target
    lda Target+1
    adc Count+1
    sta Target+1

    ; Copy the whole pages, each from its byte $FF down, the page below the pointers.
    ldy #$FF
    ldx Count+1
NextPage:
    dec Source+1
    dec Target+1
    cpx #0
    beq LastPart
    dex
CopyPage:
    lda (Source),y
    sta (Target),y
    dey
    cpy #$FF
    bne CopyPage
    jmp NextPage

    ; Then the bytes left.
LastPart:
    ldx Count
    jmp CountByte
CopyByte:
    lda (Source),y
    sta (Target),y
    dey
    dex
CountByte:
    bne CopyByte
    jmp Fetch::Skip2
.endproc

; StandardProcedures: MoveLeftOrRight.
.scope StandardProcedures continued

;; MVL and MVR: copy bytes, MVL with <MoveBytes> and MVR with <MoveBytesBackward>. Their parameters, from the top of the
;; stack: the count, two words that add to the target's address, and two that add to the source's. A negative count
;; copies nothing.
;; Also: MOVELEFT (A2POSRM, UCSD20), MOVELR (WK11), MOVERIGHT (A2POSRM, UCSD20), MVL (A2POSRM, UCSD20),
;;   MVR (A2POSRM, UCSD20)
.proc MoveLeftOrRight

;; How many bytes to copy.
Count = Offset

    ; Pull the count.
    pla
    sta Count
    pla
    sta Count+1
    bpl Move
    pla
    pla
    pla
    pla
    pla
    pla
    pla
    pla
    jmp Fetch::Skip2

    ; Target and Source, each the sum of its two words.
Move:
    pla
    sta Target
    pla
    sta Target+1
    clc
    pla
    adc Target
    sta Target
    pla
    adc Target+1
    sta Target+1
    pla
    sta Source
    pla
    sta Source+1
    clc
    pla
    adc Source
    sta Source
    pla
    adc Source+1
    sta Source+1

    ; MVR copies from the last byte. MVL goes on into MoveBytes.
    ldy #1
    lda (InstructionPointer),y
    cmp #CSP::MVL
    bne MoveBytesBackward
.endproc
.endscope

;; Copies bytes from <Source> to <Target>, the first byte first, and runs the next p-code after a 2-byte one. MVL comes
;; to it from <StandardProcedures::MoveLeftOrRight>, and <MOV at Pcodes::MoveWords> jumps to it.
;; In: <Source>, Target = the first bytes, MoveBytes::Count = how many
.proc MoveBytes

;; How many bytes to copy.
Count = Offset

    ; Copy the whole pages.
    ldx Count+1
    ldy #0
NextPage:
    cpx #0
    beq LastPart
    dex
CopyPage:
    lda (Source),y
    sta (Target),y
    iny
    bne CopyPage
    inc Target+1
    inc Source+1
    jmp NextPage

    ; Then the bytes left.
LastPart:
    ldx Count
    jmp CountByte
CopyByte:
    lda (Source),y
    sta (Target),y
    iny
    dex
CountByte:
    bne CopyByte
    jmp Fetch::Skip2
.endproc

; StandardProcedures: MemoryAvailable.
.scope StandardProcedures continued

;; <MEMA at StandardProcedures::MemoryAvailable>: pushes how many words are free between the heap and <ProgramStackTop>,
;; counting SYSTEM.PASCAL's directory on the heap as free.
;; Also: FRE (WK11), MEMAVAIL (UCSD20)
.proc MemoryAvailable
    ; ProgramStackTop less the directory, if there is one, or else less HeapTop.
    sec
    lda Syscom::Directory+1
    beq NoDirectory
    lda ProgramStackTop
    sbc Syscom::Directory
    tax
    lda ProgramStackTop+1
    sbc Syscom::Directory+1
    jmp Push
NoDirectory:
    lda ProgramStackTop
    sbc HeapTop
    tax
    lda ProgramStackTop+1
    sbc HeapTop+1

    ; Push it in words.
Push:
    lsr a
    pha
    txa
    ror a
    pha
    jmp Fetch::Skip2
.endproc
.endscope
