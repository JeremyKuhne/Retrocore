;; APPLE II MINI-ASSEMBLER ($F500-$F668), AND THE END OF THE FLOATING-POINT ROUTINES
;;
;; Steve Wozniak and Allen Baum's one-line assembler, which shares the Integer BASIC chips. From the Monitor, F666G
;; starts it (MINIASM), and it prompts with !. Each line is an instruction to assemble at the current address:
;;
;; - "addr:" first sets the address, as in 300: LDA #$01;
;; - a line starting with a blank assembles at the address after the last instruction;
;; - a line starting with $ runs a Monitor command, such as $300L.
;;
;; The Mini-Assembler packs the mnemonic's three letters as the Monitor's disassembler tables do (MNEML, MNEMR), reads
;; the operand into the address mode characters the disassembler prints (CHAR1, CHAR2), and then tries every opcode:
;; the Monitor's INSDS2 gives each one's mnemonic and format, and the first that matches both is the one. The
;; instruction is stored, the line is shown again as the Monitor's disassembler lists it, and the address moves on.
;; An error prints ^ under the place where reading stopped.
;;
;; Between the Mini-Assembler and its entry point sit the floating-point routines' last two, FIX1 and FIX, with
;; UNDFL ($F63D-$F65D; FloatingPoint.asm has the rest).
;;
;; Names follow Apple's listing in the Apple II Reference Manual (1978). Part of IntegerBasic.asm; it follows
;; FloatingPoint.asm, at $F500.

;; The format the opcode being tried has, from the Monitor's <INSDS2>: its address mode bits.
;;
;; It is the Monitor's location at $2E, which the IIe sources call MASK.
;; See: <FMT>, <TRYNEXT>
FORMAT = $2E

;; The length of the operand typed, 1 or 2 bytes (0 for none): the Mini-Assembler's L.
;;
;; It is the Monitor's YSAV1, at $35.
;; See: <FORM6>, <NEXTOP>
L = $35

;; The format of the operand typed: a bit for each address mode character matched, then the operand's length in the
;; low two bits.
;;
;; It is the Monitor's A5L, at $44.
;; See: <FORM5>, <FORM8>, <TRYNEXT>
FMT = $44

;; Assembles a branch: turns the target address into the offset from the instruction after it.
;;
;; The operand typed must be a plain address (a format of $81 or $82), and the target must be within a byte's reach.
;; In: A = FMT, carry set
;; Errors: ERR if the format does not fit or the branch is too far
REL:
    sbc #$81                        ; $F500
    lsr a                           ; $F502
    bne ERR3                        ; $F503
    ldy A2H                         ; $F505
    ldx A2L                         ; $F507
    bne REL2                        ; $F509 A2 - 1, then minus PC + 1: A2 - PC - 2
    dey                             ; $F50B

REL2:
    dex                             ; $F50C
    txa                             ; $F50D
    clc                             ; $F50E
    sbc PCL                         ; $F50F
    sta A2L                         ; $F511
    bpl REL3                        ; $F513
    iny                             ; $F515

;; The high byte of the offset must be 0, or $FF for a branch backward.
REL3:
    tya                             ; $F516
    sbc PCH                         ; $F517

ERR3:
    bne ERR                         ; $F519

;; Stores the instruction: the opcode in <A1H> and the operand in <A2L> and <A2H>, which follow it in page zero.
;;
;; Then it lists the line again over the one typed and moves <PCL> past the instruction.
;; See: <INSTDSP>, <PCADJ>
FINDOP:
    ldy LENGTH                      ; $F51B

FNDOP2:
    lda A1H,y                       ; $F51D
    sta (PCL),y                     ; $F520
    dey                             ; $F522
    bpl FNDOP2                      ; $F523
    jsr UP                          ; $F525
    jsr UP                          ; $F528 back over the line typed
    jsr INSTDSP                     ; $F52B
    jsr PCADJ                       ; $F52E
    sty PCH                         ; $F531
    sta PCL                         ; $F533
    jmp NXTLINE                     ; $F535

;; A $ line: runs the Monitor command for the delimiter, then reads the next parameter.
;;
;; <TOSUB> runs the command whose delimiter is at index Y in <CHRTBL>.
;; Entry: FAKEMON = reads the first parameter
FAKEMON3:
    jsr TOSUB                       ; $F538
    ldy YSAV                        ; $F53B

FAKEMON:
    jsr GETNUM                      ; $F53D
    sty YSAV                        ; $F540
    ldy #$17                        ; $F542

;; Looks the delimiter up in <CHRTBL>; Return (index $15) ends the command line, as the Monitor's <BL1> handles it.
FAKEMON2:
    dey                             ; $F544
    bmi RESETZ                      ; $F545 not a Monitor delimiter: an error
    cmp CHRTBL,y                    ; $F547
    bne FAKEMON2                    ; $F54A
    cpy #$15                        ; $F54C
    bne FAKEMON3                    ; $F54E
    lda MODE                        ; $F550
    ldy #$00                        ; $F552
    dec YSAV                        ; $F554
    jsr BL1                         ; $F556
    jmp NXTLINE                     ; $F559

;; Tries the opcode in <A1H>: its mnemonic must match the one typed, and its format the operand's.
;;
;; The opcodes are tried from 0, then $FF down to 1.
;; See: <INSDS2>, <MNEML>, <MNEMR>
TRYNEXT:
    lda A1H                         ; $F55C
    jsr INSDS2                      ; $F55E
    tax                             ; $F561
    lda MNEMR,x                     ; $F562
    cmp A4L                         ; $F565
    bne NEXTOP                      ; $F567
    lda MNEML,x                     ; $F569
    cmp A4H                         ; $F56C
    bne NEXTOP                      ; $F56E
    lda FMT                         ; $F570
    ldy FORMAT                      ; $F572
    cpy #$9D                        ; $F574 the format of a relative branch
    beq REL                         ; $F576

;; Compares the opcode's format with the operand's.
NREL:
    cmp FORMAT                      ; $F578
    beq FINDOP                      ; $F57A

;; Moves to the next opcode. When none is left, a one-byte operand is tried again as two bytes, as an operand below
;; $100 can be either.
NEXTOP:
    dec A1H                         ; $F57C
    bne TRYNEXT                     ; $F57E
    inc FMT                         ; $F580
    dec L                           ; $F582
    beq TRYNEXT                     ; $F584

;; An error: prints ^ under the character where reading stopped, sounds the bell and reads a new line.
;; Entry: ERR2 = with that character's position in Y
ERR:
    ldy YSAV                        ; $F586

ERR2:
    tya                             ; $F588
    tax                             ; $F589
    jsr PRBL2                       ; $F58A
    lda #$DE                        ; $F58D
    jsr COUT                        ; $F58F

;; Sounds the bell, then reads a new line (<NXTLINE>).
RESETZ:
    jsr BELL                        ; $F592

;; Reads a line after the ! prompt and assembles it: an address and a colon, a blank, or a $ line.
NXTLINE:
    lda #$A1                        ; $F595
    sta PROMPT                      ; $F597
    jsr GETLNZ                      ; $F599
    jsr ZMODE                       ; $F59C
    lda IN                          ; $F59F
    cmp #$A0                        ; $F5A2
    beq SPACE                       ; $F5A4
    iny                             ; $F5A6
    cmp #$A4                        ; $F5A7
    beq FAKEMON                     ; $F5A9
    dey                             ; $F5AB
    jsr GETNUM                      ; $F5AC
    cmp #$93                        ; $F5AF $93: a colon, as GETNUM returns it

;; An error unless the character after the address is the colon, and an address came before it.
ERR4:
    bne ERR2                        ; $F5B1
    txa                             ; $F5B3
    beq ERR2                        ; $F5B4
    jsr A1PCLP                      ; $F5B6

;; Reads the mnemonic: its three letters, five bits each, into <A4L> and <A4H>.
SPACE:
    lda #$03                        ; $F5B9
    sta A1H                         ; $F5BB

NXTMN:
    jsr GETNSP                      ; $F5BD

;; Turns a letter into its 5-bit code and shifts it in.
NXTM:
    asl a                           ; $F5C0
    sbc #$BE                        ; $F5C1
    cmp #$C2                        ; $F5C3 not a letter
    bcc ERR2                        ; $F5C5
    asl a                           ; $F5C7
    asl a                           ; $F5C8
    ldx #$04                        ; $F5C9

NXTM2:
    asl a                           ; $F5CB
    rol A4L                         ; $F5CC
    rol A4H                         ; $F5CE
    dex                             ; $F5D0
    bpl NXTM2                       ; $F5D1
    dec A1H                         ; $F5D3
    beq NXTM2                       ; $F5D5 the third letter: one more shift
    bpl NXTMN                       ; $F5D7

;; Reads the operand: for each of the five address mode characters, a bit in <FMT> says whether it was there.
;;
;; The number comes at the third, read by <GETNUM>; its length goes in <L>.
FORM1:
    ldx #$05                        ; $F5D9

FORM2:
    jsr GETNSP                      ; $F5DB
    sty YSAV                        ; $F5DE
    cmp CHAR1,x                     ; $F5E0
    bne FORM3                       ; $F5E3
    jsr GETNSP                      ; $F5E5
    cmp CHAR2,x                     ; $F5E8
    beq FORM5                       ; $F5EB
    lda CHAR2,x                     ; $F5ED
    beq FORM4                       ; $F5F0
    cmp #$A4                        ; $F5F2
    beq FORM4                       ; $F5F4
    ldy YSAV                        ; $F5F6

;; No match: a 0 bit.
FORM3:
    clc                             ; $F5F8

FORM4:
    dey                             ; $F5F9

FORM5:
    rol FMT                         ; $F5FA
    cpx #$03                        ; $F5FC
    bne FORM7                       ; $F5FE
    jsr GETNUM                      ; $F600
    lda A2H                         ; $F603
    beq FORM6                       ; $F605
    inx                             ; $F607

FORM6:
    stx L                           ; $F608
    ldx #$03                        ; $F60A
    dey                             ; $F60C

FORM7:
    stx A1H                         ; $F60D
    dex                             ; $F60F
    bpl FORM2                       ; $F610
    lda FMT                         ; $F612
    asl a                           ; $F614
    asl a                           ; $F615
    ora L                           ; $F616
    cmp #$20                        ; $F618
    bcs FORM8                       ; $F61A an address with no other mode characters: the $ bit
    ldx L                           ; $F61C
    beq FORM8                       ; $F61E
    ora #$80                        ; $F620

;; Ends the format: <FMT>, with its length; after the operand comes a comment (;) or the end of the line.
FORM8:
    sta FMT                         ; $F622
    sty YSAV                        ; $F624
    lda IN,y                        ; $F626
    cmp #$BB                        ; $F629
    beq FORM9                       ; $F62B
    cmp #$8D                        ; $F62D
    bne ERR4                        ; $F62F

FORM9:
    jmp TRYNEXT                     ; $F631

;; Returns the next character of the line that is not a blank.
;; In: Y = the place in <IN>
;; Out: A = the character, Y = the place after it
;; Keeps: X
GETNSP:
    lda IN,y                        ; $F634
    iny                             ; $F637
    cmp #$A0                        ; $F638
    beq GETNSP                      ; $F63A
    rts                             ; $F63C

;; The floating-point routines' last two: FIX converts FP1 to a 16-bit integer in <M1> (high byte) and M1+1.
;;
;; It shifts the mantissa right until the exponent is 14 ($8E). A negative number with a fraction left over is moved
;; one toward 0. A number below 1 in size gives 0 (<UNDFL>).
;; In: X1/M1 = the number
;; Out: M1, M1+1 = the integer
;; Entry: FIX = without the first shift
;; See: <FLOAT>
FIX1:
    jsr RTAR                        ; $F63D

FIX:
    lda X1                          ; $F640
    bpl UNDFL                       ; $F642
    cmp #$8E                        ; $F644
    bne FIX1                        ; $F646
    bit M1                          ; $F648
    bpl FIXRTS                      ; $F64A
    lda M1+2                        ; $F64C
    beq FIXRTS                      ; $F64E
    inc M1+1                        ; $F650
    bne FIXRTS                      ; $F652
    inc M1                          ; $F654

FIXRTS:
    rts                             ; $F656

;; Returns 0: clears <M1> and M1+1.
UNDFL:
    lda #$00                        ; $F657
    sta M1                          ; $F659
    sta M1+1                        ; $F65B
    rts                             ; $F65D
    .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF ; $F65E .fill 8,$FF unused bytes

;; The Mini-Assembler's entry point, F666G from the Monitor: sounds the bell and reads the first line.
;; See: <RESETZ>
MINIASM:
    jmp RESETZ                      ; $F666
