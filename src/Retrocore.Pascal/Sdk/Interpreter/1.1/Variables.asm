; retrocore: style=strict
;; Constants, and loading and storing locals, globals, intermediates, a data segment's words and indirect words.
;;
;; A variable is a word, numbered from 1: word n of a frame's variables is 2n + <VARIABLE_BIAS> bytes from the frame,
;; and its high byte one more. <GetBig> gives 2n for a big operand.

; The opcodes whose handlers work out a variable from the opcode.

;; <SLDL at Pcodes::ShortLoadLocal> 1. <SLDL at Pcodes::ShortLoadLocal> 1-16 are $D8-$E7.
OPCODE_SLDL1 = $D8

;; <SLDO at Pcodes::ShortLoadGlobal> 1. <SLDO at Pcodes::ShortLoadGlobal> 1-16 are $E8-$F7.
OPCODE_SLDO1 = $E8

;; <SIND at Pcodes::ShortLoadIndirect> 0. <SIND at Pcodes::ShortLoadIndirect> 1-7 are $F9-$FF.
OPCODE_SIND0 = $F8

; Variables.

;; What to add to a variable's number times 2 for its offset from its frame: the variables follow the frame's
;; <MarkStack> bytes, and are numbered from 1.
VARIABLE_BIAS = .sizeof(MarkStack) - 2

; Pcodes: the loads and stores of constants, locals, globals, intermediates, extended words and indirect words.
.scope Pcodes continued

;; <LDCN at Pcodes::LoadNil>: pushes NIL, 0.
;; Also: LDCN (A2POSRM, UCSD20, WK11)
.proc LoadNil
    lda #0
    pha
    pha
    jmp Fetch::Skip1
.endproc

;; <LDCI at Pcodes::LoadConstantWord>: pushes the word that follows the opcode.
;; Also: LDCI (A2POSRM, WK11)
.proc LoadConstantWord
    ldy #2
    lda (InstructionPointer),y
    pha
    dey
    lda (InstructionPointer),y
    pha
    jmp Fetch::Skip3
.endproc

;; <SLDL at Pcodes::ShortLoadLocal> 1-16: pushes local 1-16, as the opcode gives it.
;; In: A = the opcode times 2, less 256, and carry = set, as <Fetch> leaves them
;; Also: SLDL (A2POSRM, WK11)
.proc ShortLoadLocal
    ; The opcode gives the local's number: A less 2 times (SLDL 1's opcode less 1) is the number times 2.
    sbc #<(2 * (OPCODE_SLDL1 - 1)) - VARIABLE_BIAS - 1
    tay

    ; Push it.
    lda (LocalFrame),y
    pha
    dey
    lda (LocalFrame),y
    pha
    jmp Fetch::Skip1
.endproc

;; <LDL at Pcodes::LoadLocal>: pushes the local the big operand numbers.
;; Also: LDL (A2POSRM, UCSD20, WK11)
.proc LoadLocal
    ; Find it.
    ldy #1
    jsr GetBig
    lda LocalFrame
    clc
    adc Offset
    sta Address
    lda LocalFrame+1
    adc Offset+1
    sta Address+1

    ; Push it.
    ldy #VARIABLE_BIAS + 1
    lda (Address),y
    pha
    dey
    lda (Address),y
    pha
    jmp Fetch::Skip2
.endproc

;; <LLA at Pcodes::LoadLocalAddress>: pushes the address of the local the big operand numbers.
;; Also: LLA (A2POSRM, WK11)
.proc LoadLocalAddress
    ; Work out its address.
    ldy #1
    jsr GetBig
    lda LocalFrame
    clc
    adc Offset
    sta Address
    lda LocalFrame+1
    adc Offset+1
    sta Address+1
    lda Address
    clc
    adc #VARIABLE_BIAS
    sta Address
    bcc Push
    inc Address+1

    ; Push it.
Push:
    lda Address+1
    pha
    lda Address
    pha
    jmp Fetch::Skip2
.endproc

;; <STL at Pcodes::StoreLocal>: pops a word into the local the big operand numbers.
;; Also: STL (A2POSRM, WK11)
.proc StoreLocal
    ; Find it.
    ldy #1
    jsr GetBig
    lda LocalFrame
    clc
    adc Offset
    sta Address
    lda LocalFrame+1
    adc Offset+1
    sta Address+1

    ; Pop the word into it.
    ldy #VARIABLE_BIAS
    pla
    sta (Address),y
    iny
    pla
    sta (Address),y
    jmp Fetch::Skip2
.endproc

;; <SLDO at Pcodes::ShortLoadGlobal> 1-16: pushes global 1-16, as the opcode gives it.
;; In: A = the opcode times 2, less 256, and carry = set, as <Fetch> leaves them
;; Also: SLDO (A2POSRM, WK11)
.proc ShortLoadGlobal
    ; The opcode gives the global's number: A less 2 times (SLDO 1's opcode less 1) is the number times 2.
    sbc #<(2 * (OPCODE_SLDO1 - 1)) - VARIABLE_BIAS - 1
    tay

    ; Push it.
    lda (GlobalFrame),y
    pha
    dey
    lda (GlobalFrame),y
    pha
    jmp Fetch::Skip1
.endproc

;; <LDO at Pcodes::LoadGlobal>: pushes the global the big operand numbers.
;; Also: LDO (A2POSRM, UCSD20, WK11)
.proc LoadGlobal
    ; Find it.
    ldy #1
    jsr GetBig
    lda GlobalFrame
    clc
    adc Offset
    sta Address
    lda GlobalFrame+1
    adc Offset+1
    sta Address+1

    ; Push it.
    ldy #VARIABLE_BIAS + 1
    lda (Address),y
    pha
    dey
    lda (Address),y
    pha
    jmp Fetch::Skip2
.endproc

;; <LAO at Pcodes::LoadGlobalAddress>: pushes the address of the global the big operand numbers.
;; Also: LAO (A2POSRM, UCSD20, WK11)
.proc LoadGlobalAddress
    ; Work out its address.
    ldy #1
    jsr GetBig
    lda GlobalFrame
    clc
    adc Offset
    sta Address
    lda GlobalFrame+1
    adc Offset+1
    sta Address+1
    lda Address
    clc
    adc #VARIABLE_BIAS
    sta Address
    bcc Push
    inc Address+1

    ; Push it.
Push:
    lda Address+1
    pha
    lda Address
    pha
    jmp Fetch::Skip2
.endproc

;; <SRO at Pcodes::StoreGlobal>: pops a word into the global the big operand numbers.
;; Also: SRO (A2POSRM, UCSD20, WK11)
.proc StoreGlobal
    ; Find it.
    ldy #1
    jsr GetBig
    lda GlobalFrame
    clc
    adc Offset
    sta Address
    lda GlobalFrame+1
    adc Offset+1
    sta Address+1

    ; Pop the word into it.
    ldy #VARIABLE_BIAS
    pla
    sta (Address),y
    iny
    pla
    sta (Address),y
    jmp Fetch::Skip2
.endproc

;; <LOD at Pcodes::LoadIntermediate>: pushes an intermediate variable: the first operand gives how many lexical levels
;; out its procedure is, and the big operand after it the variable.
;; Also: LOD (A2POSRM, UCSD20, WK11)
.proc LoadIntermediate
    ; Find the procedure's frame, and the variable in it.
    ldy #1
    lda (InstructionPointer),y
    tax
    jsr FindFrame
    ldy #2
    jsr GetBig
    lda Offset
    clc
    adc Frame
    sta Address
    lda Offset+1
    adc Frame+1
    sta Address+1

    ; Push it.
    ldy #VARIABLE_BIAS + 1
    lda (Address),y
    pha
    dey
    lda (Address),y
    pha
    jmp Fetch::Skip3
.endproc

;; LDA: pushes the address of an intermediate variable, given as <LOD at Pcodes::LoadIntermediate> gives it.
;; Also: LDA (A2POSRM, UCSD20, WK11)
.proc LoadIntermediateAddress
    ; Find the procedure's frame, and work out the variable's address in it.
    ldy #1
    lda (InstructionPointer),y
    tax
    jsr FindFrame
    ldy #2
    jsr GetBig
    lda Offset
    clc
    adc Frame
    sta Address
    lda Offset+1
    adc Frame+1
    sta Address+1
    lda Address
    clc
    adc #VARIABLE_BIAS
    sta Address
    bcc Push
    inc Address+1

    ; Push it.
Push:
    lda Address+1
    pha
    lda Address
    pha
    jmp Fetch::Skip3
.endproc

;; <STR at Pcodes::StoreIntermediate>: pops a word into an intermediate variable, given as
;; <LOD at Pcodes::LoadIntermediate> gives it.
;; Also: STR (A2POSRM, UCSD20, WK11)
.proc StoreIntermediate
    ; Find the procedure's frame, and the variable in it.
    ldy #1
    lda (InstructionPointer),y
    tax
    jsr FindFrame
    ldy #2
    jsr GetBig
    lda Offset
    clc
    adc Frame
    sta Address
    lda Offset+1
    adc Frame+1
    sta Address+1

    ; Pop the word into it.
    ldy #VARIABLE_BIAS
    pla
    sta (Address),y
    iny
    pla
    sta (Address),y
    jmp Fetch::Skip3
.endproc

;; <LDE at Pcodes::LoadExtended>: pushes a word of a data segment: the first operand gives the segment, and the big
;; operand after it the word, n at 2n bytes above the segment's <SegmentAddresses> entry.
;; Also: LDE (A2POSRM, WK11)
.proc LoadExtended

;; The word's address.
Word = Pointer

    ; Find the word.
    ldy #1
    lda (InstructionPointer),y
    asl a
    tax
    iny
    jsr GetBig
    lda SegmentAddresses,x
    clc
    adc Offset
    sta Word
    lda SegmentAddresses+1,x
    adc Offset+1
    sta Word+1

    ; Push it.
    ldy #1
    lda (Word),y
    pha
    dey
    lda (Word),y
    pha
    jmp Fetch::Skip3
.endproc

;; <STE at Pcodes::StoreExtended>: pops a word into a data segment's word, given as <LDE at Pcodes::LoadExtended> gives
;; it.
;; Also: STE (A2POSRM, WK11)
.proc StoreExtended

;; The word's address.
Word = Pointer

    ; Find the word.
    ldy #1
    lda (InstructionPointer),y
    asl a
    tax
    iny
    jsr GetBig
    lda SegmentAddresses,x
    clc
    adc Offset
    sta Word
    lda SegmentAddresses+1,x
    adc Offset+1
    sta Word+1

    ; Pop the word into it.
    ldy #0
    pla
    sta (Word),y
    iny
    pla
    sta (Word),y
    jmp Fetch::Skip3
.endproc

;; <LAE at Pcodes::LoadExtendedAddress>: pushes the address of a data segment's word, given as
;; <LDE at Pcodes::LoadExtended> gives it.
;; Also: LAE (A2POSRM, WK11)
.proc LoadExtendedAddress
    ; Work out its address, and push it.
    ldy #1
    lda (InstructionPointer),y
    asl a
    tax
    iny
    jsr GetBig
    lda SegmentAddresses,x
    clc
    adc Offset
    tay
    lda SegmentAddresses+1,x
    adc Offset+1
    pha
    tya
    pha
    jmp Fetch::Skip3
.endproc

;; <SIND at Pcodes::ShortLoadIndirect> 0-7: pops an address, and pushes the word at an offset from it: 0 for
;; <SIND at Pcodes::ShortLoadIndirect> 0, and for <SIND at Pcodes::ShortLoadIndirect> 1-7 the opcode's number, in words.
;; In: A = the opcode times 2, less 256, carry = set, and Y = 0, as <Fetch> leaves them
;; Also: SIND (A2POSRM, WK11)
.proc ShortLoadIndirect
    ; SIND 1-7: the opcode gives the offset. A less 2 times SIND 0's opcode is the offset in bytes.
    sbc #<(2 * OPCODE_SIND0)
    tay

;; <SIND at Pcodes::ShortLoadIndirect> 0, which <Fetch> reaches with Y = 0: the word at the address itself.
;; In: Y = the offset in bytes
;; Also: SIND0 (WK11)
Zero:
    ; Pop the address, and push the word.
    pla
    sta Pointer
    pla
    sta Pointer+1
    iny
    lda (Pointer),y
    pha
    dey
    lda (Pointer),y
    pha
    jmp Fetch::Skip1
.endproc

;; <STO at Pcodes::StoreIndirect>: pops a word, then an address, and stores the word there.
;; Also: STO (A2POSRM, UCSD20, WK11)
.proc StoreIndirect

;; The word.
Value = Pointer

;; The address.
Destination = Pointer2

    ; Pop them.
    pla
    sta Value
    pla
    sta Value+1
    pla
    sta Destination
    pla
    sta Destination+1

    ; Store the word.
    ldy #0
    lda Value
    sta (Destination),y
    iny
    lda Value+1
    sta (Destination),y
    jmp Fetch::Skip1
.endproc
.endscope
