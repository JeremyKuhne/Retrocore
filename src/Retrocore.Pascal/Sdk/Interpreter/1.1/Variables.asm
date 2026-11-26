; retrocore: style=strict
;; Constants, and loading and storing locals, globals, intermediates, a data segment's words and indirect words.
;;
;; A variable is a word, numbered from 1: word n of a frame's variables is 2n + <VARIABLE_BIAS> bytes from the frame,
;; and its high byte one more. <GetBig> gives 2n for a big operand.

; The opcodes whose handlers work out a variable from the opcode.

;; <SLDL at OpSLDL> 1. <SLDL at OpSLDL> 1-16 are $D8-$E7.
OPCODE_SLDL1 = $D8

;; <SLDO at OpSLDO> 1. <SLDO at OpSLDO> 1-16 are $E8-$F7.
OPCODE_SLDO1 = $E8

;; <SIND at OpSIND> 0. <SIND at OpSIND> 1-7 are $F9-$FF.
OPCODE_SIND0 = $F8

; Variables.

;; What to add to a variable's number times 2 for its offset from its frame: the variables follow the frame's
;; <MSCW_SIZE> bytes, and are numbered from 1.
VARIABLE_BIAS = MSCW_SIZE - 2

;; <LDCN at OpLDCN>: pushes NIL, 0.
.proc OpLDCN
    lda #0
    pha
    pha
    jmp Fetch::Skip1
.endproc

;; <LDCI at OpLDCI>: pushes the word that follows the opcode.
.proc OpLDCI
    ldy #2
    lda (IPC),y
    pha
    dey
    lda (IPC),y
    pha
    jmp Fetch::Skip3
.endproc

;; <SLDL at OpSLDL> 1-16: pushes local 1-16, as the opcode gives it.
;; In: A = the opcode times 2, less 256, and carry = set, as <Fetch> leaves them
.proc OpSLDL
    ; The opcode gives the local's number: A less 2 times (SLDL 1's opcode less 1) is the number times 2.
    sbc #<(2 * (OPCODE_SLDL1 - 1)) - VARIABLE_BIAS - 1
    tay

    ; Push it.
    lda (MP),y
    pha
    dey
    lda (MP),y
    pha
    jmp Fetch::Skip1
.endproc

;; <LDL at OpLDL>: pushes the local the big operand numbers.
.proc OpLDL
    ; Find it.
    ldy #1
    jsr GetBig
    lda MP
    clc
    adc Offset
    sta Address
    lda MP+1
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

;; <LLA at OpLLA>: pushes the address of the local the big operand numbers.
.proc OpLLA
    ; Work out its address.
    ldy #1
    jsr GetBig
    lda MP
    clc
    adc Offset
    sta Address
    lda MP+1
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

;; <STL at OpSTL>: pops a word into the local the big operand numbers.
.proc OpSTL
    ; Find it.
    ldy #1
    jsr GetBig
    lda MP
    clc
    adc Offset
    sta Address
    lda MP+1
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

;; <SLDO at OpSLDO> 1-16: pushes global 1-16, as the opcode gives it.
;; In: A = the opcode times 2, less 256, and carry = set, as <Fetch> leaves them
.proc OpSLDO
    ; The opcode gives the global's number: A less 2 times (SLDO 1's opcode less 1) is the number times 2.
    sbc #<(2 * (OPCODE_SLDO1 - 1)) - VARIABLE_BIAS - 1
    tay

    ; Push it.
    lda (BASE),y
    pha
    dey
    lda (BASE),y
    pha
    jmp Fetch::Skip1
.endproc

;; <LDO at OpLDO>: pushes the global the big operand numbers.
.proc OpLDO
    ; Find it.
    ldy #1
    jsr GetBig
    lda BASE
    clc
    adc Offset
    sta Address
    lda BASE+1
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

;; <LAO at OpLAO>: pushes the address of the global the big operand numbers.
.proc OpLAO
    ; Work out its address.
    ldy #1
    jsr GetBig
    lda BASE
    clc
    adc Offset
    sta Address
    lda BASE+1
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

;; <SRO at OpSRO>: pops a word into the global the big operand numbers.
.proc OpSRO
    ; Find it.
    ldy #1
    jsr GetBig
    lda BASE
    clc
    adc Offset
    sta Address
    lda BASE+1
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

;; <LOD at OpLOD>: pushes an intermediate variable: the first operand gives how many lexical levels out its procedure
;; is, and the big operand after it the variable.
.proc OpLOD
    ; Find the procedure's frame, and the variable in it.
    ldy #1
    lda (IPC),y
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

;; LDA: pushes the address of an intermediate variable, given as <LOD at OpLOD> gives it.
.proc OpLDA
    ; Find the procedure's frame, and work out the variable's address in it.
    ldy #1
    lda (IPC),y
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

;; <STR at OpSTR>: pops a word into an intermediate variable, given as <LOD at OpLOD> gives it.
.proc OpSTR
    ; Find the procedure's frame, and the variable in it.
    ldy #1
    lda (IPC),y
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

;; <LDE at OpLDE>: pushes a word of a data segment: the first operand gives the segment, and the big operand after it
;; the word, n at 2n bytes above the segment's <SegmentAddresses> entry.
.proc OpLDE

;; The word's address.
Word = Pointer

    ; Find the word.
    ldy #1
    lda (IPC),y
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

;; <STE at OpSTE>: pops a word into a data segment's word, given as <LDE at OpLDE> gives it.
.proc OpSTE

;; The word's address.
Word = Pointer

    ; Find the word.
    ldy #1
    lda (IPC),y
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

;; <LAE at OpLAE>: pushes the address of a data segment's word, given as <LDE at OpLDE> gives it.
.proc OpLAE
    ; Work out its address, and push it.
    ldy #1
    lda (IPC),y
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

;; <SIND at OpSIND> 0-7: pops an address, and pushes the word at an offset from it: 0 for <SIND at OpSIND> 0, and for
;; <SIND at OpSIND> 1-7 the opcode's number, in words.
;; In: A = the opcode times 2, less 256, carry = set, and Y = 0, as <Fetch> leaves them
.proc OpSIND
    ; SIND 1-7: the opcode gives the offset. A less 2 times SIND 0's opcode is the offset in bytes.
    sbc #<(2 * OPCODE_SIND0)
    tay

;; <SIND at OpSIND> 0, which <Fetch> reaches with Y = 0: the word at the address itself.
;; In: Y = the offset in bytes
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

;; <STO at OpSTO>: pops a word, then an address, and stores the word there.
.proc OpSTO

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
