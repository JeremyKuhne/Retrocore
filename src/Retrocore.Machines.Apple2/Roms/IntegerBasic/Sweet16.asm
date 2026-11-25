; retrocore: style=strict
;; Integer BASIC: SWEET16 ($F689-$F7FC), after two register routines ($F669-$F688)
;;
;; Steve Wozniak's SWEET16 (<Sweet16>), which shares the Integer BASIC chips; Integer BASIC does not use it, but the
;; Programmer's Aid ROM's Renumber and Relocate are partly written in it. Before it come two small routines that save
;; and restore the 6502's registers, which nothing in the ROM calls.
;;
;; Names follow Apple's listing in the Apple II Reference Manual (1978), kept as each definition's historical names,
;; but for ADD and POP, which Integer BASIC's floating point and POP statement use: Sweet16's old names for those two
;; are the SDK's ADD16 and POP16. Part of IntegerBasic.asm; it follows MiniAssembler.asm, at $F669.

; Two register routines, which nothing in the ROM calls.

;; Where <StashRegisters> keeps A.
;;
;; The four bytes, $56 to $59, are in Integer BASIC's noun and syntax stacks (<NounStackLow>, <SyntaxStackHigh>).
;; Also: SAV_A (UNKN)
StashedA = $56

;; Where <StashRegisters> keeps X.
;; Also: SAV_X (UNKN)
StashedX = $57

;; Where <StashRegisters> keeps Y.
;; Also: SAV_Y (UNKN)
StashedY = $58

;; Where <StashRegisters> keeps the status.
;; Also: SAV_P (UNKN)
StashedStatus = $59

;; Saves A, X, Y and the status in <StashedA> to <StashedStatus>, and returns a nibble from the stack.
;;
;; The nibble is the low nibble of the stack byte two above the stack pointer, which is the high byte of the return
;; address when this is called with JSR, shifted into A's high nibble.
;; Out: A = the nibble, in bits 4-7
;; Uses: X
;; Keeps: Y
;; See: <RecoverRegisters>
;; Also: Save_Registers (UNKN)
.proc StashRegisters

;; The 6502's stack page.
Stack = $0100

    sty StashedY
    stx StashedX
    sta StashedA
    php
    pla
    sta StashedStatus

    ; The return address's high byte, past the stack pointer and the low byte.
    tsx
    inx
    inx
    lda Stack,x
    asl a
    asl a
    asl a
    asl a
    rts
.endproc

;; Restores A, X, Y and the status from <StashedA> to <StashedStatus>.
;; Out: A = <StashedA>, X = <StashedX>, Y = <StashedY>, P = <StashedStatus>
;; See: <StashRegisters>
;; Also: Restore_Registers (UNKN)
.proc RecoverRegisters
    ldy StashedY
    ldx StashedX
    lda StashedStatus
    pha
    lda StashedA
    plp
    rts
.endproc

;; Steve Wozniak's SWEET16: an interpreter for a 16-bit machine of his own design, which 6502 programs call to run
;; compact 16-bit code in place.
;;
;; A program does JSR <Sweet16::Run>; the bytes after the JSR are SWEET16 instructions, up to an RTN, after which the
;; 6502 carries on with its registers as they were.
;;
;; Registers. SWEET16 has 16 registers of 16 bits, R0 to R15, in page zero: Rn is at 2n (low byte) and 2n+1. R0 is
;; the accumulator. R12 is the stack pointer for subroutine calls (BS and RS), R13 receives the result of a compare
;; (CPR), R14's high byte (<Sweet16::Register14High>) remembers which register got the last result, which the
;; conditional branches test, and R15 (<Sweet16::Register15>) is the program counter.
;;
;; Instructions. An opcode's high nibble is the operation and its low nibble the register n:
;;
;; - 1n SET Rn,constant (2 more bytes); 2n LD Rn (R0 = Rn); 3n ST Rn (Rn = R0);
;; - 4n LD @Rn and 5n ST @Rn: a byte, through Rn, which then steps up; 6n LDD @Rn and 7n STD @Rn: two bytes;
;; - 8n POP @Rn: Rn steps down, then a byte through it; 9n STP @Rn: the same, storing; Cn POPD @Rn: two bytes;
;; - An ADD Rn (R0 = R0 + Rn), Bn SUB Rn (R0 = R0 - Rn), Dn CPR Rn (R13 = R0 - Rn), En INR Rn, Fn DCR Rn.
;;
;; An opcode with a high nibble of 0 has no register; the branches take a signed offset byte after the opcode,
;; counted from the instruction after it: 00 RTN, 01 BR, 02 BNC, 03 BC, 04 BP, 05 BM, 06 BZ, 07 BNZ, 08 BM1, 09 BNM1
;; (branch if the last result is, or is not, -1), 0A BK (a 6502 BRK), 0B RS (return from a subroutine), 0C BS (call
;; a subroutine) and 0D to 0F, which do nothing.
;;
;; Each instruction is run by pushing a routine's address and returning to it: every routine is in page
;; <Sweet16::ROUTINE_PAGE>, and two tables of low bytes, <Sweet16::RegisterRoutines> and
;; <Sweet16::NonRegisterRoutines>, interleaved, hold their addresses less 1.
;;
;; The Programmer's Aid ROM's Sweet16.mac assembles these instructions with Apple's mnemonics as macros (SET, LD, ST,
;; LDD, STD, POP, STP, POPD, ADD, SUB, CPR, INR, DCR, RTN, and the branches BR to BNM1 and BS); it has none for RS and
;; BK.
.scope Sweet16

;; The page all of SWEET16's instruction routines are in: the high byte <Sweet16::Step> pushes before each.
;; Also: SW16PAG (A2RM78)
ROUTINE_PAGE = $F7

;; The offset of R12, the subroutine stack pointer: twice its number.
STACK_REGISTER = 2 * 12

;; R0, the accumulator (2 bytes), and the base of the registers, which X indexes as twice their number.
;; Also: R0L (A2RM78)
Register0 = $00

;; R0's high byte.
;; Also: R0H (A2RM78)
Register0High = $01

;; R14's high byte: twice the number of the register that got the last result, plus the carry in bit 0.
;;
;; <Sweet16::Step> sets it to the register of each register instruction, SET, LD, ST, INR and DCR keeping that one.
;; The instructions through a register (LD @ to POPD @) set it to R0, as do ADD and SUB; CPR sets it to R13; and ADD,
;; SUB and CPR add the carry. BS sets it to R0 too, as it stores through <Sweet16::StoreIndirect::FromA>. The
;; branches test the register it names, and BC and BNC its carry.
;; Also: R14H (A2RM78)
Register14High = $1D

;; R15, SWEET16's program counter (2 bytes): the address of the instruction being run, or of a branch's offset byte.
;; Also: R15L (A2RM78)
Register15 = $1E

;; R15's high byte.
;; Also: R15H (A2RM78)
Register15High = $1F

;; Runs the SWEET16 code that follows the JSR to here, until its RTN.
;;
;; At $F689. The 6502's registers are saved with the Monitor's <SaveRegisters> and put back at RTN
;; (<Sweet16::Exit>), which goes on after the RTN. The return address the JSR pushed, the last byte of the JSR,
;; becomes R15; each instruction steps it first.
;; Keeps: A, X, Y
;; Entry:
;;   WithoutSaving = runs without saving the 6502's registers, so RTN puts back those saved last: the Programmer's
;;     Aid ROM's Renumber calls it as SW16+3, to go back to SWEET16 after some 6502 code
;; See: <Sweet16::Step>, <Sweet16::Exit>
;; Also: SW16 (A2RM78)
.proc Run
.assert * = $F689, "Sweet16::Run must stay at $F689, where programs and the Programmer's Aid ROM call SW16."
    jsr SaveRegisters

;; Runs without saving the 6502's registers.
WithoutSaving:
.assert * = $F68C, "Sweet16::Run::WithoutSaving must stay at $F68C, where the Programmer's Aid ROM calls SW16+3."
    pla
    sta Register15
    pla
    sta Register15High

;; The interpreter's loop: one instruction at a time.
;; Also: SW16B (A2RM78)
Loop:
    jsr Step
    jmp Loop
.endproc

;; Runs one SWEET16 instruction: steps R15 to it, and returns into its routine.
;;
;; The page of the routine, <Sweet16::ROUTINE_PAGE>, is pushed first. The opcode's low nibble, doubled, goes in X, the
;; register's offset; exclusive-ORing the low nibble out again leaves the high nibble. A register instruction records
;; its register in <Sweet16::Register14High> and finds its routine in <Sweet16::RegisterRoutines> at the high nibble
;; doubled.
;;
;; A register instruction's routine starts with X = the register's offset, Y = the high nibble doubled (which
;; <Sweet16::Compare> uses), A = the low byte of its own address less 1, and the carry clear.
;; Entry:
;;   Fetch = without stepping R15
;;   NonRegister = runs the instruction without a register at R15, with X = its opcode doubled
;; Also: SW16C (A2RM78)
.proc Step
    inc Register15
    bne Fetch
    inc Register15High

;; Pushes the routine's page and reads the opcode.
;; Also: SW16D (A2RM78)
Fetch:
    lda #ROUTINE_PAGE
    pha
    ldy #0
    lda (Register15),y
    and #$0F
    asl a
    tax
    lsr a
    eor (Register15),y
    beq NonRegister

    ; A register instruction: its routine from the table, at the high nibble doubled.
    stx Register14High
    lsr a
    lsr a
    lsr a
    tay
    lda RegisterRoutines - 2,y
    pha
    rts

;; An instruction without a register: steps R15 to the byte after the opcode, its offset, and returns into the routine
;; from <Sweet16::NonRegisterRoutines>.
;;
;; The routine starts with A = the number of the register that got the last result, the carry as that instruction
;; left it, and Y = 0.
;; Also: TOBR (A2RM78)
NonRegister:
    inc Register15
    bne PushRoutine
    inc Register15High

;; Also: TOBR2 (A2RM78)
PushRoutine:
    lda NonRegisterRoutines,x
    pha
    lda Register14High
    lsr a
    rts
.endproc

;; Leaves SWEET16: puts back the 6502's registers and continues the 6502 program after the RTN.
;;
;; R15 points past the RTN, as <Sweet16::Step::NonRegister> stepped it. Dropping the return to
;; <Sweet16::Run::Loop> leaves the interpreter.
;; Also: RTNZ (A2RM78)
.proc Exit
    pla
    pla
    jsr RestoreRegisters
    jmp (Register15)
.endproc

;; SET's work: loads the two bytes after the opcode into the register, then steps R15 past them.
;; In: X = the register's offset, Y = 2
;; Also: SETZ (A2RM78)
.proc SetConstant
    lda (Register15),y
    sta Register0High,x
    dey
    lda (Register15),y
    sta Register0,x

    ; Y is 1: R15 + 2, with the carry.
    tya
    sec
    adc Register15
    sta Register15
    bcc Done
    inc Register15High

;; Also: SET2 (A2RM78)
Done:
    rts
.endproc

;; One entry of <Sweet16::RegisterRoutines> or <Sweet16::NonRegisterRoutines>: the low byte of a routine's address
;; less 1, which <Sweet16::Step> pushes after <Sweet16::ROUTINE_PAGE> and returns to.
;; Parameters:
;;   routine = the instruction's routine, which must be in page ROUTINE_PAGE
.macro Routine routine
    .byte <(routine - 1)
    .assert >(routine - 1) = ROUTINE_PAGE, "A SWEET16 routine must be in page ROUTINE_PAGE."
.endmacro

;; The routines of the register instructions, interleaved with <Sweet16::NonRegisterRoutines>: for the high nibbles 1
;; to F, at every other byte from here.
;; Also: OPTBL (A2RM78)
RegisterRoutines:
    Routine Set                     ; 1n SET

;; The routines of the instructions without a register, opcodes 00 to 0F, at every other byte from here.
;; Also: BRTBL (A2RM78)
NonRegisterRoutines:
    Routine Return                  ; 00 RTN
    Routine Load                    ; 2n LD
    Routine Branch                  ; 01 BR
    Routine Store                   ; 3n ST
    Routine BranchIfNoCarry         ; 02 BNC
    Routine LoadIndirect            ; 4n LD @
    Routine BranchIfCarry           ; 03 BC
    Routine StoreIndirect           ; 5n ST @
    Routine BranchIfPlus            ; 04 BP
    Routine LoadDoubleIndirect      ; 6n LDD @
    Routine BranchIfMinus           ; 05 BM
    Routine StoreDoubleIndirect     ; 7n STD @
    Routine BranchIfZero            ; 06 BZ
    Routine Pop                     ; 8n POP @
    Routine BranchIfNotZero         ; 07 BNZ
    Routine StorePop                ; 9n STP @
    Routine BranchIfMinusOne        ; 08 BM1
    Routine Add                     ; An ADD
    Routine BranchIfNotMinusOne     ; 09 BNM1
    Routine Subtract                ; Bn SUB
    Routine Break                   ; 0A BK
    Routine PopDouble               ; Cn POPD @
    Routine ReturnFromSubroutine    ; 0B RS
    Routine Compare                 ; Dn CPR
    Routine BranchToSubroutine      ; 0C BS
    Routine Increment               ; En INR
    Routine Nothing                 ; 0D
    Routine Decrement               ; Fn DCR
    Routine Nothing                 ; 0E
    Routine Nothing                 ; no register instruction has a high nibble of $10
    Routine Nothing                 ; 0F
.assert NonRegisterRoutines = RegisterRoutines + 1, "The two tables interleave."
.assert * - RegisterRoutines = 2 * 16, "Sixteen entries of each table."

;; SET Rn (1n): loads a constant into Rn. The branch is always taken, as A, the low byte of Set's address less 1,
;; is positive.
;; Also: SET (A2RM78)
.proc Set
    bpl SetConstant
.endproc

;; LD Rn (2n): R0 = Rn.
;;
;; Its first byte is LDA zero page,X; the operand, 0, is the BRK of <Sweet16::Break>, which BK's table entry points
;; at.
;; In: X = the register's offset
;; Also: LD (A2RM78)
.proc Load
    .byte $B5                       ; LDA Register0,X, whose operand byte is Break's BRK
    .assert * = Break, "LD's operand must be BK's BRK."
.endproc

;; BK (0A): runs a 6502 BRK, which stops in the Monitor. Its BRK is also the operand of <Sweet16::Load>'s first
;; instruction, after which <Sweet16::Load> goes on here.
;; Also: BK (A2RM78)
.proc Break
    brk
    sta Register0
    lda Register0High,x
    sta Register0High
    rts
.endproc

;; ST Rn (3n): Rn = R0.
;; In: X = the register's offset
;; Also: ST (A2RM78)
.proc Store
    lda Register0
    sta Register0,x
    lda Register0High
    sta Register0High,x
    rts
.endproc

;; ST @Rn (5n): stores R0's low byte at the address in Rn, then steps Rn up; R0 is the last result.
;; In: X = the register's offset
;; Out: Y = 0
;; Entry:
;;   FromA = stores A instead: <Sweet16::BranchToSubroutine> enters here
;;   SetResult = records the register Y as the last result, then steps Rn up
;; Also: STAT (A2RM78)
.proc StoreIndirect
    lda Register0

;; Stores A at the address in Rn, then steps Rn up.
;; Also: STAT2 (A2RM78)
FromA:
    sta (Register0,x)
    ldy #0

;; Records Y's register as the last result, then steps Rn up.
;; Also: STAT3 (A2RM78)
SetResult:
    sty Register14High
    ; Falls into Increment.
.endproc

;; INR Rn (En): Rn = Rn + 1.
;; In: X = the register's offset
;; Keeps: A, Y
;; Also: INR (A2RM78)
.proc Increment
    inc Register0,x
    bne Done
    inc Register0High,x

;; Also: INR2 (A2RM78)
Done:
    rts
.endproc

;; LD @Rn (4n): loads the byte at the address in Rn into R0, with a high byte of 0, then steps Rn up.
;; In: X = the register's offset
;; Out: Y = 0
;; Also: LDAT (A2RM78)
.proc LoadIndirect
    lda (Register0,x)
    sta Register0
    ldy #0
    sty Register0High
    beq StoreIndirect::SetResult
.endproc

;; POP @Rn (8n): steps Rn down, then loads the byte at its address into R0, with a high byte of 0.
;;
;; Apple's listing calls it POP, which Integer BASIC's POP statement uses in this assembly.
;; In: X = the register's offset
;; Also: POP16 (UNKN)
.proc Pop
    ldy #0
    beq PopDouble::PopByte
.endproc

;; POPD @Rn (Cn): steps Rn down twice, loading the two bytes there into R0, the high byte first.
;; In: X = the register's offset
;; Out: Y = 0
;; Entry:
;;   PopByte = steps Rn down and loads the low byte, with the high byte in Y
;;   ResultInR0 = records R0 as the last result: <Sweet16::StorePop> ends here
;; Also: POPD (A2RM78)
.proc PopDouble
    jsr Decrement
    lda (Register0,x)
    tay

;; Steps Rn down and loads R0's low byte from there, and its high byte from Y.
;; Also: POP2 (A2RM78)
PopByte:
    jsr Decrement
    lda (Register0,x)
    sta Register0
    sty Register0High

;; Records R0 as the last result.
;; Also: POP3 (A2RM78)
ResultInR0:
    ldy #0
    sty Register14High
    rts
.endproc

;; LDD @Rn (6n): loads the two bytes at the address in Rn into R0, stepping Rn up past them.
;; In: X = the register's offset
;; Out: Y = 0
;; Also: LDDAT (A2RM78)
.proc LoadDoubleIndirect
    jsr LoadIndirect
    lda (Register0,x)
    sta Register0High
    jmp Increment
.endproc

;; STD @Rn (7n): stores R0's two bytes at the address in Rn, stepping Rn up past them.
;; In: X = the register's offset
;; Out: Y = 0
;; Also: STDAT (A2RM78)
.proc StoreDoubleIndirect
    jsr StoreIndirect
    lda Register0High
    sta (Register0,x)
    jmp Increment
.endproc

;; STP @Rn (9n): steps Rn down, then stores R0's low byte at its address.
;; In: X = the register's offset
;; Out: Y = 0
;; Also: STPAT (A2RM78)
.proc StorePop
    jsr Decrement
    lda Register0
    sta (Register0,x)
    jmp PopDouble::ResultInR0
.endproc

;; DCR Rn (Fn): Rn = Rn - 1.
;; In: X = the register's offset
;; Keeps: Y
;; Also: DCR (A2RM78)
.proc Decrement
    lda Register0,x
    bne LowByte
    dec Register0High,x

;; Also: DCR2 (A2RM78)
LowByte:
    dec Register0,x
    rts
.endproc

;; SUB Rn (Bn): R0 = R0 - Rn, recording R0 and the carry in <Sweet16::Register14High>.
;; In: X = the register's offset
;; Also: SUB (A2RM78)
.proc Subtract
    ldy #0
    ; Falls into Compare.
.endproc

;; CPR Rn (Dn): R13 = R0 - Rn, recording R13 and the carry in <Sweet16::Register14High>.
;;
;; Y is $1A, R13's offset, because <Sweet16::Step> left the high nibble, D, doubled in it.
;; In: X = the register's offset, Y = the result's register offset
;; Entry:
;;   StoreHigh = stores A as the result's high byte, then records the result's register and the carry:
;;     <Sweet16::Add> enters here
;; Also: CPR (A2RM78)
.proc Compare
    sec
    lda Register0
    sbc Register0,x
    sta a:Register0,y               ; absolute: the 6502 has no zero-page,Y store from A
    lda Register0High
    sbc Register0High,x

;; Stores the high byte of the result, then records its register, Y, and the carry in <Sweet16::Register14High>.
;; Also: SUB2 (A2RM78)
StoreHigh:
    sta a:Register0High,y
    tya
    adc #0
    sta Register14High
    rts
.endproc

;; ADD Rn (An): R0 = R0 + Rn, recording R0 and the carry in <Sweet16::Register14High>.
;;
;; Apple's listing calls it ADD, which the floating point's <Float::AddMantissas> has in this assembly. The carry is
;; clear: <Sweet16::Step> shifted zeros out of the high nibble.
;; In: X = the register's offset
;; Also: ADD16 (UNKN)
.proc Add
    lda Register0
    adc Register0,x
    sta Register0
    lda Register0High
    adc Register0High,x
    ldy #0
    beq Compare::StoreHigh
.endproc

;; BS (0C): calls a SWEET16 subroutine: pushes R15 through R12, then branches.
;;
;; X is $18, R12's offset, because <Sweet16::Step> doubled the opcode, $0C. The push records R0 as the last result.
;; Also: BS (A2RM78)
.proc BranchToSubroutine
    .assert 2 * $0C = STACK_REGISTER, "BS's opcode, doubled, must be R12's offset."
    lda Register15
    jsr StoreIndirect::FromA
    lda Register15High
    jsr StoreIndirect::FromA
    ; Falls into Branch.
.endproc

;; BR (01): branches always: adds the signed offset byte at R15 to R15.
;; In: Y = 0
;; Also: BR (A2RM78)
.proc Branch
    clc
    ; Falls into BranchIfNoCarry.
.endproc

;; BNC (02): branches if the last result's carry is clear.
;; In: Y = 0, carry = the last result's carry
;; Entry:
;;   Take = branches whatever the carry, which must be clear: the other branches enter here
;;   Done = returns without branching
;; Also: BNC (A2RM78)
.proc BranchIfNoCarry
    bcs Done

;; Adds the offset to R15.
;; Also: BR1 (A2RM78)
Take:
    lda (Register15),y
    bpl AddOffset
    dey                             ; a negative offset: Y = $FF, the high byte

;; Also: BR2 (A2RM78)
AddOffset:
    adc Register15
    sta Register15
    tya
    adc Register15High
    sta Register15High

;; No branch.
;; Also: BNC2 (A2RM78)
Done:
    rts
.endproc

;; BC (03): branches if the last result's carry is set.
;; In: carry = the last result's carry
;; Also: BC (A2RM78)
.proc BranchIfCarry
    bcs Branch
    rts
.endproc

;; BP (04): branches if the last result is positive (its high byte's bit 7 clear).
;; In: A = the last result's register
;; Also: BP (A2RM78)
.proc BranchIfPlus
    asl a
    tax
    lda Register0High,x
    bpl BranchIfNoCarry::Take
    rts
.endproc

;; BM (05): branches if the last result is negative.
;; In: A = the last result's register
;; Also: BM (A2RM78)
.proc BranchIfMinus
    asl a
    tax
    lda Register0High,x
    bmi BranchIfNoCarry::Take
    rts
.endproc

;; BZ (06): branches if the last result is 0.
;; In: A = the last result's register
;; Also: BZ (A2RM78)
.proc BranchIfZero
    asl a
    tax
    lda Register0,x
    ora Register0High,x
    beq BranchIfNoCarry::Take
    rts
.endproc

;; BNZ (07): branches if the last result is not 0.
;; In: A = the last result's register
;; Also: BNZ (A2RM78)
.proc BranchIfNotZero
    asl a
    tax
    lda Register0,x
    ora Register0High,x
    bne BranchIfNoCarry::Take
    rts
.endproc

;; BM1 (08): branches if the last result is -1 ($FFFF).
;; In: A = the last result's register
;; Also: BM1 (A2RM78)
.proc BranchIfMinusOne
    asl a
    tax
    lda Register0,x
    and Register0High,x
    eor #$FF
    beq BranchIfNoCarry::Take
    rts
.endproc

;; BNM1 (09): branches if the last result is not -1.
;; In: A = the last result's register
;; Also: BNM1 (A2RM78)
.proc BranchIfNotMinusOne
    asl a
    tax
    lda Register0,x
    and Register0High,x
    eor #$FF
    bne BranchIfNoCarry::Take
    ; Falls into Nothing.
.endproc

;; Opcodes 0D to 0F: nothing. They pass over the byte after them, as an untaken branch does.
;; Also: NUL (A2RM78)
.proc Nothing
    rts
.endproc

;; RS (0B): returns from a SWEET16 subroutine: pops R15 through R12.
;; Also: RS (A2RM78)
.proc ReturnFromSubroutine
    ldx #STACK_REGISTER
    jsr Decrement
    lda (Register0,x)
    sta Register15High
    jsr Decrement
    lda (Register0,x)
    sta Register15
    rts
.endproc

;; RTN (00): leaves SWEET16 (<Sweet16::Exit>).
;; Also: RTN (A2RM78)
.proc Return
    jmp Exit
.endproc

.endscope

    ; Three bytes nothing uses, to the end of the ROM.
    .byte $F6, $FF, $FF
