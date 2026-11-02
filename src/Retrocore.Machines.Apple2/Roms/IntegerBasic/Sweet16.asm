;; APPLE II SWEET16 ($F689-$F7FC), AFTER TWO REGISTER ROUTINES ($F669-$F688)
;;
;; Steve Wozniak's SWEET16: an interpreter for a 16-bit machine of his own design, which 6502 programs call to run
;; compact 16-bit code in place. A program does JSR SW16; the bytes after the JSR are SWEET16 instructions, up to an
;; RTN, after which the 6502 carries on with its registers as they were. SWEET16 shares the Integer BASIC chips;
;; Integer BASIC does not use it.
;;
;; Registers. SWEET16 has 16 registers of 16 bits, R0 to R15, in page zero: Rn is at 2n (low byte) and 2n+1. R0 is
;; the accumulator. R12 is the stack pointer for subroutine calls (BS and RS), R13 receives the result of a compare
;; (CPR), R14's high byte remembers which register got the last result (twice its number, with the carry in bit 0),
;; which the conditional branches test, and R15 is the program counter.
;;
;; Instructions. An opcode's high nibble is the operation and its low nibble the register n:
;;
;; - 1n SET Rn,constant (2 more bytes); 2n LD Rn (R0 = Rn); 3n ST Rn (Rn = R0);
;; - 4n LD @Rn and 5n ST @Rn: a byte, through Rn, which then steps up; 6n LDD @Rn and 7n STD @Rn: two bytes;
;; - 8n POP @Rn: Rn steps down, then a byte through it; 9n STP @Rn: the same, storing; Cn POPD @Rn: two bytes;
;; - An ADD Rn (R0 = R0 + Rn), Bn SUB Rn (R0 = R0 - Rn), Dn CPR Rn (R13 = R0 - Rn), En INR Rn, Fn DCR Rn.
;;
;; An opcode with a high nibble of 0 has no register; the branches take a signed offset byte after the opcode:
;; 00 RTN, 01 BR, 02 BNC, 03 BC, 04 BP, 05 BM, 06 BZ, 07 BNZ, 08 BM1, 09 BNM1 (branch if the last result is, or is
;; not, -1), 0A BK (a 6502 BRK), 0B RS (return from a subroutine), 0C BS (call a subroutine) and 0D to 0F, which do
;; nothing.
;;
;; Each instruction is run by pushing a routine's address and returning to it: every routine is in page $F7, and two
;; tables of low bytes, OPTBL and BRTBL, interleaved, hold their addresses less 1.
;;
;; Names follow Apple's listing in the Apple II Reference Manual (1978), but for ADD and POP, which are ADD16 and
;; POP16 here: the floating-point routines and Integer BASIC use those names. Part of IntegerBasic.asm; it follows
;; MiniAssembler.asm, at $F669.

;; The page all of SWEET16's instruction routines are in: the high byte the interpreter pushes before each.
SW16PAG = $F7

;; R0's low byte: the accumulator, and the base of the registers, which X indexes as twice their number.
;; See: <R0H>, <SW16>
R0L = $00

;; R0's high byte.
R0H = $01

;; R14's high byte: twice the number of the register that got the last result, plus the carry in bit 0.
;;
;; Every register instruction sets it to its own register; those whose result goes to R0 or R13 set that one, and
;; ADD, SUB and CPR add the carry. The branches test the register it names, and BC and BNC its carry.
;; See: <SW16C>, <SUB2>, <TOBR2>
R14H = $1D

;; R15, SWEET16's program counter (2 bytes): the address of the instruction being run.
;; See: <SW16C>, <BR1>
R15L = $1E

;; R15's high byte.
R15H = $1F

;; Where <Save_Registers> keeps A.
SAV_A = $56

SAV_X = $57                         ;; where <Save_Registers> keeps X
SAV_Y = $58                         ;; where <Save_Registers> keeps Y
SAV_P = $59                         ;; where <Save_Registers> keeps the status

;; Saves A, X, Y and the status in <SAV_A> to <SAV_P>, and returns a nibble from the stack; nothing in the ROM calls
;; it.
;;
;; The nibble is the low nibble of the stack byte two above the stack pointer, the high byte of the return address
;; when this is called with JSR, shifted into A's high nibble.
;; Out: A = the nibble, in bits 4-7
;; Keeps: Y
;; See: <Restore_Registers>
Save_Registers:
    sty SAV_Y                       ; $F669
    stx SAV_X                       ; $F66B
    sta SAV_A                       ; $F66D
    php                             ; $F66F
    pla                             ; $F670
    sta SAV_P                       ; $F671
    tsx                             ; $F673
    inx                             ; $F674
    inx                             ; $F675
    lda $0100,x                     ; $F676 the stack page
    asl a                           ; $F679
    asl a                           ; $F67A
    asl a                           ; $F67B
    asl a                           ; $F67C
    rts                             ; $F67D

;; Restores A, X, Y and the status from <SAV_A> to <SAV_P>; nothing in the ROM calls it.
;; See: <Save_Registers>
Restore_Registers:
    ldy SAV_Y                       ; $F67E
    ldx SAV_X                       ; $F680
    lda SAV_P                       ; $F682
    pha                             ; $F684
    lda SAV_A                       ; $F685
    plp                             ; $F687
    rts                             ; $F688

;; Runs the SWEET16 code that follows the JSR to here, until its RTN.
;;
;; The 6502's registers are saved with the Monitor's <SAVE> and put back at RTN. The return address the JSR pushed,
;; the last byte of the JSR, becomes R15; each instruction steps it first.
;; See: <SW16C>, <RTNZ>
SW16:
    jsr SAVE                        ; $F689
    pla                             ; $F68C
    sta R15L                        ; $F68D
    pla                             ; $F68F
    sta R15H                        ; $F690

;; The interpreter's loop: one instruction at a time.
SW16B:
    jsr SW16C                       ; $F692
    jmp SW16B                       ; $F695

;; Runs one SWEET16 instruction: steps R15 to it, and returns into its routine.
;;
;; The page of the routine, <SW16PAG>, is pushed first. The opcode's low nibble, doubled, goes in X, the register's
;; offset; exclusive-ORing the low nibble out again leaves the high nibble. A register instruction records its
;; register in <R14H> and finds its routine in <OPTBL> at the high nibble doubled; Y is that, which <CPR> uses.
;; See: <OPTBL>, <TOBR>
;; Entry: SW16D = without stepping R15
SW16C:
    inc R15L                        ; $F698
    bne SW16D                       ; $F69A
    inc R15H                        ; $F69C

SW16D:
    lda #SW16PAG                    ; $F69E
    pha                             ; $F6A0
    ldy #$00                        ; $F6A1
    lda (R15L),y                    ; $F6A3
    and #$0F                        ; $F6A5
    asl a                           ; $F6A7
    tax                             ; $F6A8
    lsr a                           ; $F6A9
    eor (R15L),y                    ; $F6AA
    beq TOBR                        ; $F6AC 0: an instruction without a register
    stx R14H                        ; $F6AE
    lsr a                           ; $F6B0
    lsr a                           ; $F6B1
    lsr a                           ; $F6B2
    tay                             ; $F6B3
    lda OPTBL-2,y                   ; $F6B4
    pha                             ; $F6B7
    rts                             ; $F6B8

;; An instruction without a register: steps R15 to the byte after the opcode, its offset, and returns into the routine
;; from <BRTBL>.
;;
;; The routine starts with A = the number of the register that got the last result, and the carry as it left it.
;; Entry: TOBR2 = without stepping R15
TOBR:
    inc R15L                        ; $F6B9
    bne TOBR2                       ; $F6BB
    inc R15H                        ; $F6BD

TOBR2:
    lda BRTBL,x                     ; $F6BF
    pha                             ; $F6C2
    lda R14H                        ; $F6C3
    lsr a                           ; $F6C5
    rts                             ; $F6C6

;; RTN: leaves SWEET16 and continues the 6502 program after the RTN.
;;
;; R15 points past the RTN, as <TOBR> stepped it. Dropping the return to <SW16B> leaves the interpreter.
RTNZ:
    pla                             ; $F6C7
    pla                             ; $F6C8
    jsr RESTORE                     ; $F6C9
    jmp (R15L)                      ; $F6CC

;; SET: loads the two bytes after the opcode into the register, then steps R15 past them.
;; In: X = the register's offset, Y = 2
SETZ:
    lda (R15L),y                    ; $F6CF
    sta R0H,x                       ; $F6D1
    dey                             ; $F6D3
    lda (R15L),y                    ; $F6D4
    sta R0L,x                       ; $F6D6
    tya                             ; $F6D8 Y = 1: R15 + 2
    sec                             ; $F6D9
    adc R15L                        ; $F6DA
    sta R15L                        ; $F6DC
    bcc SET2                        ; $F6DE
    inc R15H                        ; $F6E0

SET2:
    rts                             ; $F6E2

;; The routines of the register instructions, interleaved with <BRTBL>: their addresses in page $F7, less 1, for the
;; high nibbles 1 to F, at every other byte from here.
;; See: <SW16C>
OPTBL:
    .byte <(SET-1)                  ; $F6E3 1n SET

;; The routines of the instructions without a register, opcodes 00 to 0F, at every other byte from here.
;; See: <TOBR2>
BRTBL:
    .byte <(RTN-1)                  ; $F6E4 00 RTN
    .byte <(LD-1)                   ; $F6E5 2n LD
    .byte <(BR-1)                   ; $F6E6 01 BR
    .byte <(ST-1)                   ; $F6E7 3n ST
    .byte <(BNC-1)                  ; $F6E8 02 BNC
    .byte <(LDAT-1)                 ; $F6E9 4n LD @
    .byte <(BC-1)                   ; $F6EA 03 BC
    .byte <(STAT-1)                 ; $F6EB 5n ST @
    .byte <(BP-1)                   ; $F6EC 04 BP
    .byte <(LDDAT-1)                ; $F6ED 6n LDD @
    .byte <(BM-1)                   ; $F6EE 05 BM
    .byte <(STDAT-1)                ; $F6EF 7n STD @
    .byte <(BZ-1)                   ; $F6F0 06 BZ
    .byte <(POP16-1)                ; $F6F1 8n POP @
    .byte <(BNZ-1)                  ; $F6F2 07 BNZ
    .byte <(STPAT-1)                ; $F6F3 9n STP @
    .byte <(BM1-1)                  ; $F6F4 08 BM1
    .byte <(ADD16-1)                ; $F6F5 An ADD
    .byte <(BNM1-1)                 ; $F6F6 09 BNM1
    .byte <(SUB-1)                  ; $F6F7 Bn SUB
    .byte <(BK-1)                   ; $F6F8 0A BK
    .byte <(POPD-1)                 ; $F6F9 Cn POPD @
    .byte <(RS-1)                   ; $F6FA 0B RS
    .byte <(CPR-1)                  ; $F6FB Dn CPR
    .byte <(BS-1)                   ; $F6FC 0C BS
    .byte <(INR-1)                  ; $F6FD En INR
    .byte <(NUL-1)                  ; $F6FE 0D, nothing
    .byte <(DCR-1)                  ; $F6FF Fn DCR
    .byte <(NUL-1)                  ; $F700 0E, nothing
    .byte <(NUL-1)                  ; $F701 not used
    .byte <(NUL-1)                  ; $F702 0F, nothing

;; SET Rn (1n): the branch is always taken, as the routine's low byte, still in A, is positive.
SET:
    bpl SETZ                        ; $F703

;; LD Rn (2n): R0 = Rn.
;;
;; Its first byte is LDA zero page,X; the operand, 0, is the BRK of <BK>, which BK's table entry points at.
LD:
    .byte $B5                       ; $F705 LDA R0L,X, whose operand byte is BK's BRK

;; BK (0A): runs a 6502 BRK.
BK:
    brk                             ; $F706
    sta R0L                         ; $F707
    lda R0H,x                       ; $F709
    sta R0H                         ; $F70B
    rts                             ; $F70D

;; ST Rn (3n): Rn = R0.
ST:
    lda R0L                         ; $F70E
    sta R0L,x                       ; $F710
    lda R0H                         ; $F712
    sta R0H,x                       ; $F714
    rts                             ; $F716

;; ST @Rn (5n): stores R0's low byte at the address in Rn, then steps Rn up.
;; Entry: STAT2 = stores A instead, STAT3 = with Y in <R14H> and stepping Rn only
STAT:
    lda R0L                         ; $F717

STAT2:
    sta (R0L,x)                     ; $F719
    ldy #$00                        ; $F71B

STAT3:
    sty R14H                        ; $F71D

;; INR Rn (En): Rn = Rn + 1.
INR:
    inc R0L,x                       ; $F71F
    bne INR2                        ; $F721
    inc R0H,x                       ; $F723

INR2:
    rts                             ; $F725

;; LD @Rn (4n): loads the byte at the address in Rn into R0, with a high byte of 0, then steps Rn up.
LDAT:
    lda (R0L,x)                     ; $F726
    sta R0L                         ; $F728
    ldy #$00                        ; $F72A
    sty R0H                         ; $F72C
    beq STAT3                       ; $F72E always

;; POP @Rn (8n): steps Rn down, then loads the byte at its address into R0, with a high byte of 0.
POP16:
    ldy #$00                        ; $F730
    beq POP2                        ; $F732 always

;; POPD @Rn (Cn): steps Rn down twice, loading the two bytes there into R0.
;; Entry: POP2 = the low byte, with the high byte in Y, POP3 = makes R0 the last result's register
POPD:
    jsr DCR                         ; $F734
    lda (R0L,x)                     ; $F737
    tay                             ; $F739

POP2:
    jsr DCR                         ; $F73A
    lda (R0L,x)                     ; $F73D
    sta R0L                         ; $F73F
    sty R0H                         ; $F741

POP3:
    ldy #$00                        ; $F743
    sty R14H                        ; $F745
    rts                             ; $F747

;; LDD @Rn (6n): loads the two bytes at the address in Rn into R0, stepping Rn up past them.
LDDAT:
    jsr LDAT                        ; $F748
    lda (R0L,x)                     ; $F74B
    sta R0H                         ; $F74D
    jmp INR                         ; $F74F

;; STD @Rn (7n): stores R0's two bytes at the address in Rn, stepping Rn up past them.
STDAT:
    jsr STAT                        ; $F752
    lda R0H                         ; $F755
    sta (R0L,x)                     ; $F757
    jmp INR                         ; $F759

;; STP @Rn (9n): steps Rn down, then stores R0's low byte at its address.
STPAT:
    jsr DCR                         ; $F75C
    lda R0L                         ; $F75F
    sta (R0L,x)                     ; $F761
    jmp POP3                        ; $F763

;; DCR Rn (Fn): Rn = Rn - 1.
DCR:
    lda R0L,x                       ; $F766
    bne DCR2                        ; $F768
    dec R0H,x                       ; $F76A

DCR2:
    dec R0L,x                       ; $F76C
    rts                             ; $F76E

;; SUB Rn (Bn): R0 = R0 - Rn, recording R0 and the carry in <R14H>.
SUB:
    ldy #$00                        ; $F76F

;; CPR Rn (Dn): R13 = R0 - Rn, recording R13 and the carry in <R14H>.
;;
;; Y is $1A, R13's offset, because the dispatch left the high nibble D doubled in it.
CPR:
    sec                             ; $F771
    lda R0L                         ; $F772
    sbc R0L,x                       ; $F774
    sta a:R0L,y                     ; $F776 absolute: the 6502 has no zero-page,Y store
    lda R0H                         ; $F779
    sbc R0H,x                       ; $F77B

;; Stores the high byte of the result, then records its register, Y, and the carry in <R14H>.
SUB2:
    sta a:R0H,y                     ; $F77D
    tya                             ; $F780
    adc #$00                        ; $F781
    sta R14H                        ; $F783
    rts                             ; $F785

;; ADD Rn (An): R0 = R0 + Rn, recording R0 and the carry in <R14H>.
;;
;; The carry is clear: the dispatch shifted zeros out of the high nibble.
ADD16:
    lda R0L                         ; $F786
    adc R0L,x                       ; $F788
    sta R0L                         ; $F78A
    lda R0H                         ; $F78C
    adc R0H,x                       ; $F78E
    ldy #$00                        ; $F790
    beq SUB2                        ; $F792 always

;; BS (0C): calls a SWEET16 subroutine: pushes R15 through R12, then branches.
;;
;; X is $18, R12's offset, because the dispatch doubled the opcode, $0C.
BS:
    lda R15L                        ; $F794
    jsr STAT2                       ; $F796
    lda R15H                        ; $F799
    jsr STAT2                       ; $F79B

;; BR (01): branches always: adds the signed offset byte at R15 to R15.
;; Entry: BNC = BNC (02), branches if the last result's carry is clear, BR1 = branches whatever the carry
BR:
    clc                             ; $F79E

BNC:
    bcs BNC2                        ; $F79F

BR1:
    lda (R15L),y                    ; $F7A1
    bpl BR2                         ; $F7A3
    dey                             ; $F7A5 a negative offset: Y = $FF, the high byte

BR2:
    adc R15L                        ; $F7A6
    sta R15L                        ; $F7A8
    tya                             ; $F7AA
    adc R15H                        ; $F7AB
    sta R15H                        ; $F7AD

;; No branch.
BNC2:
    rts                             ; $F7AF

;; BC (03): branches if the last result's carry is set.
BC:
    bcs BR                          ; $F7B0
    rts                             ; $F7B2

;; BP (04): branches if the last result is positive (its high byte's bit 7 clear).
BP:
    asl a                           ; $F7B3
    tax                             ; $F7B4
    lda R0H,x                       ; $F7B5
    bpl BR1                         ; $F7B7
    rts                             ; $F7B9

;; BM (05): branches if the last result is negative.
BM:
    asl a                           ; $F7BA
    tax                             ; $F7BB
    lda R0H,x                       ; $F7BC
    bmi BR1                         ; $F7BE
    rts                             ; $F7C0

;; BZ (06): branches if the last result is 0.
BZ:
    asl a                           ; $F7C1
    tax                             ; $F7C2
    lda R0L,x                       ; $F7C3
    ora R0H,x                       ; $F7C5
    beq BR1                         ; $F7C7
    rts                             ; $F7C9

;; BNZ (07): branches if the last result is not 0.
BNZ:
    asl a                           ; $F7CA
    tax                             ; $F7CB
    lda R0L,x                       ; $F7CC
    ora R0H,x                       ; $F7CE
    bne BR1                         ; $F7D0
    rts                             ; $F7D2

;; BM1 (08): branches if the last result is -1 ($FFFF).
BM1:
    asl a                           ; $F7D3
    tax                             ; $F7D4
    lda R0L,x                       ; $F7D5
    and R0H,x                       ; $F7D7
    eor #$FF                        ; $F7D9
    beq BR1                         ; $F7DB
    rts                             ; $F7DD

;; BNM1 (09): branches if the last result is not -1.
BNM1:
    asl a                           ; $F7DE
    tax                             ; $F7DF
    lda R0L,x                       ; $F7E0
    and R0H,x                       ; $F7E2
    eor #$FF                        ; $F7E4
    bne BR1                         ; $F7E6

;; Opcodes 0D to 0F: nothing. They pass over the byte after them, as an untaken branch does.
NUL:
    rts                             ; $F7E8

;; RS (0B): returns from a SWEET16 subroutine: pops R15 through R12.
RS:
    ldx #$18                        ; $F7E9
    jsr DCR                         ; $F7EB
    lda (R0L,x)                     ; $F7EE
    sta R15H                        ; $F7F0
    jsr DCR                         ; $F7F2
    lda (R0L,x)                     ; $F7F5
    sta R15L                        ; $F7F7
    rts                             ; $F7F9

;; RTN (00): leaves SWEET16 (<RTNZ>).
RTN:
    jmp RTNZ                        ; $F7FA
    .byte $F6, $FF, $FF             ; $F7FD .junk 3 unused bytes
