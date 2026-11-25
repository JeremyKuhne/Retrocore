; retrocore: style=strict
;; Programmer's Aid #1: Relocate ($D4D5-$D52D)
;;
;; Steve Wozniak's relocation of 6502 code (1977): it copies a program to another address and adjusts the absolute
;; addresses in its instructions that point into the program, so the copy runs where it lands. It works through the
;; Monitor's Control-Y command, after D4D5G sets Control-Y up (<Relocate::SetUp>):
;;
;; 1. `dest<begin.end` Control-Y, with a `*` after it, defines the blocks: the program's source block and where its
;;    copy will run.
;; 2. `dest<begin.end` Control-Y relocates a segment of code; `dest<begin.end` M (the Monitor's Move) copies a segment
;;    of data unchanged.
;; 3. `.end` Control-Y or `.end` M continues with the next segment.
;;
;; An instruction's address is adjusted when it falls in the source block: it moves by the same distance as the
;; block. The work is shared with SWEET16 (Sweet16.mac), whose 16-bit compare and add adjust the address. The listing's
;; names are those of Apple's listing in the Programmer's Aid #1 manual (1978,
;; https://archive.org/details/programmers-aid-1). Part of ProgrammersAid.asm.

.scope Relocate

; SWEET16's registers, which hold the blocks once they are defined.

;; R1: the source block's start, the Monitor's A1 when the blocks were defined.
;; Also: FRMBEG (PA1)
SOURCE_START = 1

;; R2: the source block's end, A2.
;; Also: FRMEND (PA1)
SOURCE_END = 2

;; R4: the destination block's start, A4.
;; Also: TOBEG (PA1)
TARGET_START = 4

;; R6: the address part of the instruction being relocated, from <Instruction> + 1.
;; Also: ADR (PA1)
OPERAND = 6

;; Where <Command> copies the Monitor's A1 to A4 to define the blocks: SWEET16's R1 to R4.
;; Also: R1L (PA1)
Blocks = Sweet16Registers + SOURCE_START * SWEET16_REGISTER_SIZE

;; Where the instruction being relocated is copied (3 bytes), for SWEET16 to adjust its address: R5's high byte, then
;; R6, <OPERAND>.
;; Also: INST (PA1)
Instruction = Sweet16Registers + OPERAND * SWEET16_REGISTER_SIZE - 1

;; D4D5G: points the Monitor's Control-Y command at <Command>.
;; Keeps: X
;; Also: RELSETUP (UNKN)
.proc SetUp
.assert * = $D4D5, "Relocate::SetUp must stay at $D4D5, where the manual's D4D5G enters it."
    lda #<Command
    ldy #>Command
    jmp SetControlY
.endproc

;; The Control-Y command: defines the blocks when the command line goes on with `*`, else relocates the segment from
;; A1 to A2 to the one at A4.
;;
;; Each instruction is copied to <Instruction> and its length found with the Monitor's <DecodeOpcode>; a 3-byte
;; instruction's address, or a zero-page one's, read as $00xx, is moved with the block when it lies in the source block.
;; An immediate operand and a branch's offset are copied unchanged.
;; In: CommandPosition = the index after Control-Y in <InputBuffer>, Address1 = the segment's start, Address2 = its
;;   end, Address4 = where it goes
;; Out: CommandPosition = after the `*`, when it defines the blocks; otherwise <Address1> and <Address4> are past the
;;   segment and its copy
;; Also: RELOC (PA1)
.proc Command

;; An opcode's bits that are all clear for the 2-byte instructions with an immediate operand in X or Y or a branch
;; offset (LDY, LDX, CPY, CPX immediate and the branches).
IMMEDIATE_XY_OR_BRANCH_MASK = $0D

;; The opcode bit that is set for the other immediate instructions; a 2-byte instruction with neither is a zero-page
;; one.
IMMEDIATE_MASK = $08

    ldy CommandPosition
    lda InputBuffer,y
    cmp #'*'
    bne NextInstruction
    inc CommandPosition
    ldx #4 * SWEET16_REGISTER_SIZE - 1

;; Copies A1, A2, A3 and A4 to SWEET16's R1 to R4. Apple's listing calls it INIT, which here would clash with the
;; Monitor's INIT, <InitDisplay>.
DefineBlocks:
    lda Address1,x
    sta Blocks,x
    dex
    bpl DefineBlocks
    rts

;; Also: RELOC2 (PA1)
NextInstruction:
    ldy #2

;; Copies the instruction at A1 to <Instruction>, all 3 bytes whatever its length.
;; Also: GETINS (PA1)
CopyInstruction:
    lda (Address1),y
    sta Instruction,y
    dey
    bpl CopyInstruction
    jsr DecodeOpcode
    ldx OperandLength
    dex
    ; A 2-byte operand is an address. An instruction with none goes the same way: only its opcode is stored.
    bne Translate
    lda Instruction
    and #IMMEDIATE_XY_OR_BRANCH_MASK
    beq StoreInstruction
    and #IMMEDIATE_MASK
    bne StoreInstruction

    ; A zero-page address: treat it as $00xx.
    sta Instruction + 2

;; Moves the operand with the block when it lies in the source block.
;; Also: XLATE (PA1)
Translate:
    jsr SW16
    LD SOURCE_END
    CPR OPERAND
    ; Past the source block.
    BNC Translated
    LD OPERAND
    SUB SOURCE_START
    ; Before it.
    BNC Translated
    ADD TARGET_START
    ST OPERAND

;; Also: SW16RT (PA1)
Translated:
    RTN

;; Also: STINST (PA1)
StoreInstruction:
    ldx #0

;; Copies the instruction to A4, stepping A1 and A4, until past A2.
;; Also: STINS2 (PA1)
StoreByte:
    lda Instruction,x
    sta (Address4),y
    inx
    jsr NextInRangeAndTarget
    dec OperandLength
    bpl StoreByte
    bcc NextInstruction
    rts
.endproc

.endscope
