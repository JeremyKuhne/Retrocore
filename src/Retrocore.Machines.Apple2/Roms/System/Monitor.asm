;; APPLE II, II PLUS AND IIE MONITORS ($F800-$FFFF)
;;
;; The Monitor is each Apple II's lowest layer: reset and power-up, the BRK and IRQ entry points, character
;; input and output through the CSWL/KSWL hooks, the text screen and lo-res graphics primitives, the
;; mini disassembler, and the Monitor command line (the * prompt). This file builds four Monitors:
;;
;; - The Apple II Monitor of the first Apple IIs (1978).
;; - The Autostart Monitor of the Apple II Plus and later Apple IIs (1979).
;; - The original Apple IIe's.
;; - The Enhanced Apple IIe's.
;;
;; Documented entry points keep their addresses in all four, so programs can call them by address.
;;
;; The Apple II Monitor has no power-up or warm-start logic: its reset vector points at OLDRST, which
;; sets up the screen and keyboard and enters the Monitor, so the user starts BASIC by hand and no disk
;; is booted. BRK shows the instruction and the registers directly, without a vector. Its S command
;; steps a program one instruction at a time and T traces it (STEP), and it carries 16-bit multiply
;; and divide routines (MULPM, DIVPM) at $FB60-$FBC0. Output goes to the screen without the Control-S
;; pause (VIDOUT), and escape mode takes one command, @ or A-F, at a time.
;;
;; The Autostart Monitor takes the machine from power-up to a program. Its RESET checks the soft entry
;; vector at $3F2-$3F4 (SOFTEV and its check byte PWREDUP): when it is valid, a reset continues the
;; program that set it; otherwise this is a power-up (PWRUP), which shows "APPLE ][", sets the vectors,
;; and boots the disk controller in the highest slot that has one, or starts BASIC. BRK goes through
;; the vector BRKV ($3F0). STEP, TRACE and the multiply and divide routines are gone; in their space are
;; the title and boot code, the Control-S pause on output (VIDWAIT) and the escape keys I, J, K and M.
;;
;; The IIe's Monitor keeps the Autostart Monitor's design but moves much of the screen work to the
;; internal firmware at $C100-$CFFF, which knows about 80 columns. Routines such as HOME, SCROLL,
;; CLREOL and KEYIN load a function number into Y and jump to GOTOCX, which switches internal ROM in and
;; enters the firmware's dispatcher at $C100. Its input line keeps lowercase, where the Apple II's
;; Monitors turn it into uppercase. The Enhanced IIe sends more routines that way (RDKEY, VTABZ,
;; CLREOP, SETWND, INSDS2, OUTPORT), replaces the cassette routines with stubs into internal ROM, and
;; adds lowercase input; its IRQ entry goes to $C3FA.
;;
;; Two predefined symbols choose the build. MONITOR picks the Monitor: 0 (MONITOR_II) for the Apple II
;; Monitor, chip 341-0004; 1 (MONITOR_AUTOSTART) for the Autostart Monitor, chip 341-0020; 2
;; (MONITOR_IIE, the default) for the IIe. For the IIe, ENHANCED picks the model: 1 (the default) for
;; the Enhanced IIe, 0 for the original; the Apple II builds need 0, their default. Each build
;; assembles byte-identically to its chip, or to the $F800-$FFFF part of the IIe model's system ROM.
;; All but the Enhanced IIe's assemble for the NMOS 6502; the Enhanced IIe's for the 65C02.
;;
;; Names are Apple's documented entry points, page-zero locations and soft switches; code only the
;; Apple II has takes its names from Apple's listings in the Apple II Reference Manual (1978 for the
;; Apple II Monitor, 1979 for the Autostart Monitor). Where those listings name a routine the IIe also
;; has differently, the IIe's name is kept and the documentation gives the other. Other labels are
;; named after the routine they are in. The page-zero locations, soft switches and keys it shares with
;; the other IIe sources are in IIeEquates.asm, which it includes; the few page-zero names only the
;; Apple II Monitor uses are defined here.
;;
;; The address comments give the Enhanced IIe's address, or for code only an Apple II build has, that
;; build's; "original" marks the address in the other three where it differs, and "1978" the Apple II
;; Monitor's where it differs again.
;;
;; Maintained by hand. The SystemSourceTests digests check that the IIe models assemble byte-identically.

;; The MONITOR value that builds the Apple II Monitor (1978), chip 341-0004.
;; See: <MONITOR_AUTOSTART>, <MONITOR_IIE>
MONITOR_II = 0

;; The MONITOR value that builds the Autostart Monitor of the Apple II Plus (1979), chip 341-0020.
;; See: <MONITOR_II>, <MONITOR_IIE>
MONITOR_AUTOSTART = 1

;; The MONITOR value that builds the Apple IIe's Monitor, original or enhanced by ENHANCED.
;; See: <MONITOR_II>, <MONITOR_AUTOSTART>
MONITOR_IIE = 2

.ifndef MONITOR
MONITOR = MONITOR_IIE
.endif
.ifndef ENHANCED
.if MONITOR = MONITOR_IIE
ENHANCED = 1
.else
ENHANCED = 0
.endif
.endif
.assert MONITOR = MONITOR_IIE || ENHANCED = 0, "Only the IIe's Monitor has an enhanced model."
.if ENHANCED
.cpu Rockwell65C02
.else
.cpu Mos6502
.endif

; Apple II text has bit 7 set, so this source's characters and strings assemble that way.
.repeat 128, character
.charmap character, character | $80
.endrepeat

; The IIe's page zero, low memory, soft switches and keys, shared with the firmware, the Disk II boot ROM and DOS.
.include "IIeEquates.asm"

; Page zero not in IIeEquates.asm, because DOS has names of its own spelled the same. The firmware inherits these.
;; The high byte of the pointer at <LOC0>.
;;
;; <PWRUP> counts it down from $C7 to $C1 as it tries each slot. On the Enhanced IIe, the interrupt return code
;; at <VIDSYNC_1@Enhanced> points it briefly at a slot's $Cn00 page to select that slot's $C800 ROM, then restores it.
;; See: <LOC0>, <MSLOT>
LOC1 = $01

;; The cursor's line on the screen, 0-23.
;;
;; It counts from the top of the screen, not of the window. <TABV>, <UP> and <LF> change it, and <VTAB> sets
;; <BASL>/<BASH> for it. The 80-column firmware keeps a copy in <Firmware:OURCV>.
;; See: <CH>, <BASL>, <WNDTOP>, <WNDBTM>, <VTAB>
CV = $25

; The internal firmware's entries, CLRROM (a label in the Enhanced IIe's firmware) and AppleSoft's entries.
B_FUNC = $C100
BASICIN = $C305
IRQHANDLER = $C3FA
IRQRESTORE = $C47C
TAPEHEADR = $C567
WRITETAPE = $C5AA
READTAPE = $C5D1
MINILINE = $CF9C
CLRROM = $CFFF                      ;; releases the $C800 expansion ROM
BASIC = $E000                       ;; AppleSoft cold start
BASIC2 = $E003                      ;; AppleSoft warm start
.if MONITOR = MONITOR_II

; Names the Apple II Monitor's listing gives page zero for STEP and the multiply and divide routines.
;; The low byte of the Monitor command line's return address while STEP runs a user instruction.
;;
;; <STEP> pops the address its caller left on the stack into <RTNL>/<RTNH>, so the user's instruction
;; sees the user's stack, and <RTNJMP> pushes it back. The same bytes are <H2> and <V2>.
;; See: <RTNH>, <STEP>, <RTNJMP>
RTNL = $2C

;; The high byte of the return address <STEP> keeps at <RTNL>.
;; See: <RTNL>, <STEP>
RTNH = $2D

;; The sign count of <MULPM> and <DIVPM>: bit 0 is set when the result is negative.
;;
;; <MD1> clears it and adds one for each operand it makes positive; the caller applies the sign. The
;; same byte is <LENGTH>.
;; See: <MD1>, <MULPM>, <DIVPM>
SIGN = $2F

;; The nine bytes where STEP runs one user instruction, $3C-$44.
;;
;; <STEP> copies the instruction here, padded with NOPs and followed by jumps to <NBRNCH> and <BRANCH>
;; from <INITBL>, then jumps here. The area overlaps <A1L> through <A5L>.
;; See: <STEP>, <INITBL>
XQT = $3C

;; The low byte of the 16-bit accumulator of <MUL> and <DIV>.
;;
;; It holds the multiplier or dividend on entry and the low half of the product, or the quotient, on
;; return.
;; See: <ACH>, <XTNDL>, <AUXL>, <MUL>, <DIV>
ACL = $50

;; The high byte of the 16-bit accumulator at <ACL>.
;; See: <ACL>
ACH = $51

;; The low byte of the 16-bit extension of <MUL> and <DIV>.
;;
;; <MUL> adds it to the product and returns the product's high half here; <DIV> takes it as the high
;; half of the dividend and returns the remainder here.
;; See: <XTNDH>, <ACL>, <MUL>, <DIV>
XTNDL = $52

;; The high byte of the extension at <XTNDL>.
;; See: <XTNDL>
XTNDH = $53

;; The low byte of the 16-bit multiplicand or divisor of <MUL> and <DIV>.
;; See: <AUXH>, <ACL>, <MUL>, <DIV>
AUXL = $54

;; The high byte of the multiplicand or divisor at <AUXL>.
;; See: <AUXL>
AUXH = $55
.endif

.org $F800

;; Plots one lo-res block in the current color.
;; In: A = row (0-47), Y = column (0-39), COLOR = color in both nibbles
;; Uses: A, GBASL/GBASH, MASK
;; Keeps: X, Y
PLOT:
    lsr a                           ; $F800
    php                             ; $F801
    jsr GBASCALC                    ; $F802
    plp                             ; $F805
    lda #$0F                        ; $F806 an even row is the low nibble of the text byte, an odd row the high nibble
    bcc RTMASK                      ; $F808
    adc #$E0                        ; $F80A

RTMASK:
    sta MASK                        ; $F80C

PLOT1:
    lda (GBASL),y                   ; $F80E
    eor COLOR                       ; $F810
    and MASK                        ; $F812
    eor (GBASL),y                   ; $F814
    sta (GBASL),y                   ; $F816
    rts                             ; $F818

;; Draws a horizontal lo-res line in the current color.
;; In: A = row, Y = leftmost column, H2 = rightmost column
;; Out: Y = H2.
;; Uses: A
HLINE:
    jsr PLOT                        ; $F819

HLINE1:
    cpy H2                          ; $F81C
    bcs RTS1                        ; $F81E
    iny                             ; $F820
    jsr PLOT1                       ; $F821
    bcc HLINE1                      ; $F824

VLINEZ:
    adc #$01                        ; $F826

;; Draws a vertical lo-res line in the current color.
;; In: A = top row, Y = column, V2 = bottom row
;; Uses: A
VLINE:
    pha                             ; $F828
    jsr PLOT                        ; $F829
    pla                             ; $F82C
    cmp V2                          ; $F82D
    bcc VLINEZ                      ; $F82F

RTS1:
    rts                             ; $F831

;; Clears the whole lo-res screen (48 rows) to black.
CLRSCR:
    ldy #$2F                        ; $F832
    bne CLRSC2                      ; $F834

;; Clears the top 40 lo-res rows to black, leaving the mixed-mode text lines.
CLRTOP:
    ldy #$27                        ; $F836

CLRSC2:
    sty V2                          ; $F838
    ldy #$27                        ; $F83A

CLRSC3:
    lda #$00                        ; $F83C
    sta COLOR                       ; $F83E
    jsr VLINE                       ; $F840
    dey                             ; $F843
    bpl CLRSC3                      ; $F844
    rts                             ; $F846

;; Computes the base address of the text line that holds a lo-res row.
;; In: A = row (0-47)
;; Out: GBASL/GBASH = base address of line A/2
;; Keeps: X, Y
GBASCALC:
    pha                             ; $F847
    lsr a                           ; $F848
    and #$03                        ; $F849
    ora #$04                        ; $F84B
    sta GBASH                       ; $F84D
    pla                             ; $F84F
    and #$18                        ; $F850
    bcc GBCALC                      ; $F852
    adc #$7F                        ; $F854

GBCALC:
    sta GBASL                       ; $F856
    asl a                           ; $F858
    asl a                           ; $F859
    ora GBASL                       ; $F85A
    sta GBASL                       ; $F85C
    rts                             ; $F85E

;; Advances COLOR to the next color (adds 3 to each nibble).
NXTCOL:
    lda COLOR                       ; $F85F
    clc                             ; $F861
    adc #$03                        ; $F862

;; Sets the lo-res color.
;; In: A = color (0-15)
;; Out: COLOR = the color in both nibbles
SETCOL:
    and #$0F                        ; $F864
    sta COLOR                       ; $F866
    asl a                           ; $F868
    asl a                           ; $F869
    asl a                           ; $F86A
    asl a                           ; $F86B
    ora COLOR                       ; $F86C
    sta COLOR                       ; $F86E
    rts                             ; $F870

;; Reads the color of one lo-res block.
;; In: A = row (0-47), Y = column (0-39)
;; Out: A = color (0-15)
SCRN:
    lsr a                           ; $F871
    php                             ; $F872
    jsr GBASCALC                    ; $F873
    lda (GBASL),y                   ; $F876
    plp                             ; $F878

SCRN2:
    bcc RTMSKZ                      ; $F879
    lsr a                           ; $F87B
    lsr a                           ; $F87C
    lsr a                           ; $F87D
    lsr a                           ; $F87E

RTMSKZ:
    and #$0F                        ; $F87F
    rts                             ; $F881

;; Starts disassembling the instruction at PCL/PCH: prints its address as "AAAA-" and three blanks,
;; then decodes its opcode (INSDS2).
;; Inherit: <INSDS2> Out
INSDS1:
    ldx PCL                         ; $F882
    ldy PCH                         ; $F884
    jsr PRYX2                       ; $F886
    jsr PRBLNK                      ; $F889

;; Decodes an opcode for the disassembler: loads it from (PCL,X), then from $F88E works on A.
;; In: X = 0 and PCL/PCH, or enter at $F88E with A = opcode
;; Out: LENGTH = number of operand bytes (0-2), MASK = operand format, A = index into MNEML/MNEMR
;; The Enhanced IIe hands the work to the internal firmware (GOTOCX function $10) so 65C02 opcodes
;; decode too; the original IIe decodes the 6502 set here.
INSDS2:
    lda (PCL,x)                     ; $F88C

INSDS2_1:
    tay                             ; $F88E
    lsr a                           ; $F88F
    bcc IEVEN                       ; $F890
    ror a                           ; $F892
    bcs ERR                         ; $F893
    cmp #$A2                        ; $F895 opcode $89 (no STA immediate)
    beq ERR                         ; $F897
    and #$87                        ; $F899

IEVEN:
    lsr a                           ; $F89B
    tax                             ; $F89C
    lda FMT1,x                      ; $F89D
    jsr SCRN2                       ; $F8A0
    bne GETFMT                      ; $F8A3

ERR:
    ldy #$80                        ; $F8A5
    lda #$00                        ; $F8A7

GETFMT:
    tax                             ; $F8A9
    lda FMT2,x                      ; $F8AA
    sta MASK                        ; $F8AD
.if .not ENHANCED
    and #$03                        ; $F8AF
    sta LENGTH                      ; $F8B1
    tya                             ; $F8B3
    and #$8F                        ; $F8B4
.endif
    tax                             ; $F8AF original $F8B6
.if ENHANCED
    sty BAS2L                       ; $F8B0
    ldy #$10                        ; $F8B2
    jmp GOTOCX                      ; $F8B4
.endif

GETFMT_1:
.if ENHANCED
    sta SETSLOTCXROM                ; $F8B7
.else
    tya                             ; $F8B7
    ldy #$03                        ; $F8B8
.endif

GETFMT_2:
.if ENHANCED
    ldx #$02                        ; $F8BA
.else
    cpx #$8A                        ; $F8BA
.endif

GETFMT_3:
.if ENHANCED
    lda BASICIN,x                   ; $F8BC
    cmp CLREOL,x                    ; $F8BF
    bne MNNDX3_1                    ; $F8C2
    dex                             ; $F8C4
    dex                             ; $F8C5
    bpl GETFMT_3                    ; $F8C6
.else
    beq MNNDX3                      ; $F8BC

MNNDX1:
    lsr a                           ; $F8BE
    bcc MNNDX3                      ; $F8BF
    lsr a                           ; $F8C1

MNNDX2:
    lsr a                           ; $F8C2
    ora #$20                        ; $F8C3
.endif
    dey                             ; $F8C8 original $F8C5
.if ENHANCED
    bne GETFMT_2                    ; $F8C9

MNNDX3_1:
    sta SETINTCXROM                 ; $F8CB
.else
    bne MNNDX2                      ; $F8C6
    iny                             ; $F8C8

MNNDX3:
    dey                             ; $F8C9
    bne MNNDX1                      ; $F8CA
.endif
    rts                             ; $F8CE original $F8CC
.if ENHANCED
    .byte $00                       ; $F8CF
.else
    .byte $FF, $FF, $FF             ; $F8CD
.endif

;; Disassembles and prints one instruction at PCL/PCH: address, bytes, mnemonic and operand.
;; Out: LENGTH = operand byte count.
;; Uses: A, X, Y
INSTDSP:
    jsr INSDS1                      ; $F8D0
    pha                             ; $F8D3

PRNTOP:
    lda (PCL),y                     ; $F8D4
    jsr PRBYTE                      ; $F8D6
    ldx #$01                        ; $F8D9

PRNTBL:
    jsr PRBL2                       ; $F8DB
    cpy LENGTH                      ; $F8DE
    iny                             ; $F8E0
    bcc PRNTOP                      ; $F8E1
    ldx #$03                        ; $F8E3
    cpy #$04                        ; $F8E5
    bcc PRNTBL                      ; $F8E7
    pla                             ; $F8E9
    tay                             ; $F8EA
    lda MNEML,y                     ; $F8EB
    sta H2                          ; $F8EE
    lda MNEMR,y                     ; $F8F0
    sta V2                          ; $F8F3

PRMN1:
    lda #$00                        ; $F8F5
    ldy #$05                        ; $F8F7

PRMN2:
    asl V2                          ; $F8F9
    rol H2                          ; $F8FB
    rol a                           ; $F8FD
    dey                             ; $F8FE
    bne PRMN2                       ; $F8FF
    adc #'?'                        ; $F901 a letter's five bits count from '?'
    jsr COUT                        ; $F903
    dex                             ; $F906
    bne PRMN1                       ; $F907
    jsr PRBLNK                      ; $F909
    ldy LENGTH                      ; $F90C
    ldx #$06                        ; $F90E

PRADR1:
    cpx #$03                        ; $F910
    beq PRADR5                      ; $F912

PRADR2:
    asl MASK                        ; $F914
    bcc PRADR3                      ; $F916
    lda CHAR1-1,x                   ; $F918
    jsr COUT                        ; $F91B
    lda CHAR2-1,x                   ; $F91E
    beq PRADR3                      ; $F921
    jsr COUT                        ; $F923

PRADR3:
    dex                             ; $F926
    bne PRADR1                      ; $F927
    rts                             ; $F929

;; Prints an instruction's operand bytes, and for a relative branch the target address (part of INSTDSP).
PRADR4:
    dey                             ; $F92A
    bmi PRADR2                      ; $F92B
    jsr PRBYTE                      ; $F92D

PRADR5:
    lda MASK                        ; $F930
    cmp #$E8                        ; $F932
    lda (PCL),y                     ; $F934
    bcc PRADR4                      ; $F936

RELADR:
    jsr PCADJ3                      ; $F938
    tax                             ; $F93B
    inx                             ; $F93C
    bne PRNTYX                      ; $F93D
    iny                             ; $F93F

;; Prints Y then X as four hex digits.
PRNTYX:
    tya                             ; $F940

;; Prints A then X as four hex digits.
PRNTAX:
    jsr PRBYTE                      ; $F941

;; Prints X as two hex digits.
PRNTX:
    txa                             ; $F944
    jmp PRBYTE                      ; $F945

;; Prints three blanks.
;; Out: X = 0
PRBLNK:
    ldx #$03                        ; $F948

;; Prints X blanks.
;; In: X = count (1-255)
;; Out: X = 0
PRBL2:
    lda #' '                        ; $F94A

PRBL3:
    jsr COUT                        ; $F94C
    dex                             ; $F94F
    bne PRBL2                       ; $F950
    rts                             ; $F952

;; Computes the address of the instruction after the one at PCL/PCH.
;; In: LENGTH = its operand byte count (from INSDS2)
;; Out: A = low byte, Y = high byte. PCL/PCH are not changed
PCADJ:
    sec                             ; $F953

PCADJ2:
    lda LENGTH                      ; $F954

PCADJ3:
    ldy PCH                         ; $F956
    tax                             ; $F958
    bpl PCADJ4                      ; $F959
    dey                             ; $F95B

PCADJ4:
    adc PCL                         ; $F95C
    bcc RTS2                        ; $F95E
    iny                             ; $F960

RTS2:
    rts                             ; $F961

; The mini disassembler's tables.
;
; INSDS2 hashes an opcode twice. The first hash picks its addressing mode from FMT1; the mode then
; picks FMT2's operand format. The second hash picks the mnemonic from MNEML/MNEMR.

;; Addressing modes, the FMT2 index of each. INVALID marks an opcode the 6502 does not have.
.enum AM
INVALID
IMM                                 ; #$nn
ZP                                  ; $nn
ABS                                 ; $nnnn
IMP                                 ; (nothing)
ACC                                 ; (nothing; the Monitor does not print "A")
INDX                                ; ($nn,X)
INDY                                ; ($nn),Y
ZPX                                 ; $nn,X
ABSX                                ; $nnnn,X
ABSY                                ; $nnnn,Y
IND                                 ; ($nnnn)
ZPY                                 ; $nn,Y
REL                                 ; $nnnn, the branch target
.endenum

;; Each opcode's addressing mode, two 4-bit modes per byte: the low nibble for the opcode with bit 1
;; clear, the high nibble for bit 1 set.
;; Even opcodes index the table by opcode/4, so each row below is the even columns of one row of the
;; opcode matrix. Odd opcodes (the ORA..SBC group) depend only on bits 2-4, and use the last four bytes.
;; Opcodes ending in binary 11, and $89, are invalid before the table is read.
.macro MODES m0, m2, m4, m6, m8, mA, mC, mE
    .byte AM::m0 | AM::m2 << 4, AM::m4 | AM::m6 << 4, AM::m8 | AM::mA << 4, AM::mC | AM::mE << 4
.endmacro

FMT1:
    MODES IMP, INVALID, INVALID, ZP, IMP, ACC, INVALID, ABS         ; $00-$0E BRK - - ASL PHP ASL - ASL
    MODES REL, INVALID, INVALID, ZPX, IMP, INVALID, INVALID, ABSX   ; $10-$1E BPL - - ASL CLC - - ASL
    MODES ABS, INVALID, ZP, ZP, IMP, ACC, ABS, ABS                  ; $20-$2E JSR - BIT ROL PLP ROL BIT ROL
    MODES REL, INVALID, INVALID, ZPX, IMP, INVALID, INVALID, ABSX   ; $30-$3E BMI - - ROL SEC - - ROL
    MODES IMP, INVALID, INVALID, ZP, IMP, ACC, ABS, ABS             ; $40-$4E RTI - - LSR PHA LSR JMP LSR
    MODES REL, INVALID, INVALID, ZPX, IMP, INVALID, INVALID, ABSX   ; $50-$5E BVC - - LSR CLI - - LSR
    MODES IMP, INVALID, INVALID, ZP, IMP, ACC, IND, ABS             ; $60-$6E RTS - - ROR PLA ROR JMP ROR
    MODES REL, INVALID, INVALID, ZPX, IMP, INVALID, INVALID, ABSX   ; $70-$7E BVS - - ROR SEI - - ROR
    MODES INVALID, INVALID, ZP, ZP, IMP, IMP, ABS, ABS              ; $80-$8E - - STY STX DEY TXA STY STX
    MODES REL, INVALID, ZPX, ZPY, IMP, IMP, INVALID, INVALID        ; $90-$9E BCC - STY STX TYA TXS - -
    MODES IMM, IMM, ZP, ZP, IMP, IMP, ABS, ABS                      ; $A0-$AE LDY LDX LDY LDX TAY TAX LDY LDX
    MODES REL, INVALID, ZPX, ZPY, IMP, IMP, ABSX, ABSY              ; $B0-$BE BCS - LDY LDX CLV TSX LDY LDX
    MODES IMM, INVALID, ZP, ZP, IMP, IMP, ABS, ABS                  ; $C0-$CE CPY - CPY DEC INY DEX CPY DEC
    MODES REL, INVALID, INVALID, ZPX, IMP, INVALID, INVALID, ABSX   ; $D0-$DE BNE - - DEC CLD - - DEC
    MODES IMM, INVALID, ZP, ZP, IMP, IMP, ABS, ABS                  ; $E0-$EE CPX - CPX INC INX NOP CPX INC
    MODES REL, INVALID, INVALID, ZPX, IMP, INVALID, INVALID, ABSX   ; $F0-$FE BEQ - - INC SED - - INC
    MODES INDX, ZP, IMM, ABS, INDY, ZPX, ABSY, ABSX                 ; $x1-$xD by bits 2-4: ORA..SBC

;; How PRADR prints each mode's operand: the operand length in bits 0-1, and which characters to print
;; around the operand bytes in bits 2-7 (CHAR1/CHAR2, from the top bit down: "$", "($", "#$", ",X",
;; ")", ",Y").
OPERAND_DOLLAR = $80

OPERAND_INDIRECT = $40              ;; prints "($" before the operand
OPERAND_IMMEDIATE = $20             ;; prints "#$" before the operand
OPERAND_X = $10                     ;; prints ",X" after the operand
OPERAND_CLOSE = $08                 ;; prints ")" after the operand
OPERAND_Y = $04                     ;; prints ",Y" after the operand

;; The relative mode's format is chosen so that shifted left three times it is $E8, which PRADR5 tests
;; for to print the branch target instead; its other bits never print.
FMT2:
    .byte 0                                                     ; INVALID
    .byte OPERAND_IMMEDIATE | 1                                 ; IMM  #$nn
    .byte OPERAND_DOLLAR | 1                                    ; ZP   $nn
    .byte OPERAND_DOLLAR | 2                                    ; ABS  $nnnn
    .byte 0                                                     ; IMP
    .byte 0                                                     ; ACC
    .byte OPERAND_INDIRECT | OPERAND_X | OPERAND_CLOSE | 1      ; INDX ($nn,X)
    .byte OPERAND_INDIRECT | OPERAND_CLOSE | OPERAND_Y | 1      ; INDY ($nn),Y
    .byte OPERAND_DOLLAR | OPERAND_X | 1                        ; ZPX  $nn,X
    .byte OPERAND_DOLLAR | OPERAND_X | 2                        ; ABSX $nnnn,X
    .byte OPERAND_DOLLAR | OPERAND_Y | 2                        ; ABSY $nnnn,Y
    .byte OPERAND_INDIRECT | OPERAND_CLOSE | 2                  ; IND  ($nnnn)
    .byte OPERAND_DOLLAR | OPERAND_Y | 1                        ; ZPY  $nn,Y
    .byte $9D                                                   ; REL  $nnnn

;; The operand characters, indexed from the end as PRADR shifts the format left: each entry prints
;; CHAR1's character, then CHAR2's unless it is zero.
CHAR1:
    .byte ",),#($"                                              ; ",Y" ")" ",X" "#$" "($" "$"

CHAR2:
    .byte "Y", 0, "X$$", 0

;; Mnemonics, three letters packed five bits each into 15 bits ("?" = 0, "A" = 2), shifted left one.
;; MNEML holds the high bytes and MNEMR the low bytes. INSDS2's second hash gives the slot:
;;   slots  0-31: opcodes $x0 and $x8, at opcode/8
;;   slots 32-39: the other $x4 and $xC opcodes, at 32 + opcode/32
;;   slots 40-47: TXA..NOP ($8A-$EA), at 32 + opcode/16
;;   slots 48-55: the other $x2, $x6, $xA and $xE opcodes, at 48 + opcode/32
;;   slots 56-63: the $x1-$xD group, at 56 + opcode/32
;; An invalid opcode gets slot 16, "???".
.macro MNEMONIC slot, name
    .ident(.sprintf("MNEMONIC_%d", slot)) = (.strat(name, 0) - '?') << 11 | (.strat(name, 1) - '?') << 6 | (.strat(name, 2) - '?') << 1
.endmacro

.macro MNEMONICS first, n0, n1, n2, n3, n4, n5, n6, n7
    MNEMONIC first, n0
    MNEMONIC first + 1, n1
    MNEMONIC first + 2, n2
    MNEMONIC first + 3, n3
    MNEMONIC first + 4, n4
    MNEMONIC first + 5, n5
    MNEMONIC first + 6, n6
    MNEMONIC first + 7, n7
.endmacro

    MNEMONICS 0, "BRK", "PHP", "BPL", "CLC", "JSR", "PLP", "BMI", "SEC"             ; opcodes $00-$38 by 8
    MNEMONICS 8, "RTI", "PHA", "BVC", "CLI", "RTS", "PLA", "BVS", "SEI"             ; opcodes $40-$78 by 8
    MNEMONICS 16, "???", "DEY", "BCC", "TYA", "LDY", "TAY", "BCS", "CLV"            ; opcodes $80-$B8 by 8 ($80 is invalid)
    MNEMONICS 24, "CPY", "INY", "BNE", "CLD", "CPX", "INX", "BEQ", "SED"            ; opcodes $C0-$F8 by 8
    MNEMONICS 32, "???", "BIT", "JMP", "JMP", "STY", "LDY", "CPY", "CPX"            ; $x4/$xC: -, BIT, JMP, JMP (), STY, LDY, CPY, CPX
    MNEMONICS 40, "TXA", "TXS", "TAX", "TSX", "DEX", "???", "NOP", "???"            ; $8A-$EA by 16
    MNEMONICS 48, "ASL", "ROL", "LSR", "ROR", "STX", "LDX", "DEC", "INC"            ; $x2-$xE: shifts, STX, LDX, DEC, INC
    MNEMONICS 56, "ORA", "AND", "EOR", "ADC", "STA", "LDA", "CMP", "SBC"            ; $x1-$xD

MNEML:
.repeat 64, slot
    .byte >.ident(.sprintf("MNEMONIC_%d", slot))
.endrepeat

MNEMR:
.repeat 64, slot
    .byte <.ident(.sprintf("MNEMONIC_%d", slot))
.endrepeat

.if MONITOR = MONITOR_II
    .byte $FF, $FF, $FF             ; $FA40 unused

;; Runs one instruction of the program at PCL/PCH for the S and T commands, then shows the registers.
;;
;; Apple II Monitor only. It disassembles the instruction (<INSTDSP>) and runs it with the program's
;; registers from <A5H>, <XREG>, <YREG> and <STATUS>. Most instructions are copied to <XQT> and run
;; there, followed by NOPs and a jump to <NBRNCH>, which saves the registers again and moves PCL/PCH past
;; the instruction. A relative branch is copied with a displacement of 4, so that when it is taken it
;; lands on the jump to <BRANCH> instead, which applies the real displacement. JSR, RTS, JMP, JMP
;; indirect and RTI would leave the copy, so they are simulated (<XJSR>, <XRTS>, <XJMP>, <XJMPAT>,
;; <XRTI>), and BRK stops in <XBRK>. Every other way ends at <RTNJMP>, which shows the registers.
;;
;; The command line called it through <TOSUB>; its return address is moved to <RTNL>/<RTNH> while the
;; instruction runs, so the instruction sees the program's stack.
;; In: PCL/PCH = the instruction to run
;; Out: PCL/PCH = the next instruction to run
;; See: <STEPZ>, <TRACE>, <INITBL>
STEP:
    jsr INSTDSP                     ; $FA43 sets LENGTH
    pla                             ; $FA46
    sta RTNL                        ; $FA47
    pla                             ; $FA49
    sta RTNH                        ; $FA4A
    ldx #$08                        ; $FA4C

XQINIT:
    lda INITBL-1,x                  ; $FA4E fills XQT+1 to XQT+8 with NOPs and the two jumps
    sta XQT,x                       ; $FA51
    dex                             ; $FA53
    bne XQINIT                      ; $FA54
    lda (PCL,x)                     ; $FA56 the opcode
    beq XBRK                        ; $FA58
    ldy LENGTH                      ; $FA5A
    cmp #$20                        ; $FA5C JSR
    beq XJSR                        ; $FA5E
    cmp #$60                        ; $FA60 RTS (equal, so carry is set)
    beq XRTS                        ; $FA62
    cmp #$4C                        ; $FA64 JMP
    beq XJMP                        ; $FA66
    cmp #$6C                        ; $FA68 JMP indirect (carry set)
    beq XJMPAT                      ; $FA6A
    cmp #$40                        ; $FA6C RTI
    beq XRTI                        ; $FA6E
    and #$1F                        ; $FA70
    eor #$14                        ; $FA72 only a branch, %xxx10000, gives 4
    cmp #$04                        ; $FA74
    beq XQ2                         ; $FA76 a branch's displacement becomes 4

XQ1:
    lda (PCL),y                     ; $FA78

XQ2:
    sta XQT,y                       ; $FA7A
    dey                             ; $FA7D
    bpl XQ1                         ; $FA7E
    jsr RESTORE                     ; $FA80
    jmp XQT                         ; $FA83 returns through NBRNCH or BRANCH
.endif

;; IRQ and BRK entry (the 6502's $FFFE vector points here on the original IIe).
;; Saves A in A5H.
;; Original IIe: looks at the pushed status; BRK goes to BREAK, other interrupts to the user's handler
;; through IRQLOC ($03FE).
;; Enhanced IIe: the vector points to the firmware at $C3FA instead; this entry passes A to it.
;;
;; The Apple II's two Monitors work as the original IIe's; the Apple II Monitor's is at $FA86.
IRQ:
    sta A5H                         ; $FA40 1978 $FA86
.if ENHANCED
    lda A5H                         ; $FA42
    jmp IRQHANDLER                  ; $FA44
.else
    pla                             ; $FA42
    pha                             ; $FA43
    asl a                           ; $FA44
    asl a                           ; $FA45
    asl a                           ; $FA46
.endif

IRQ_1:
.if ENHANCED
    sta SETSLOTCXROM                ; $FA47
    sta A5H                         ; $FA4A
.else
    bmi BREAK                       ; $FA47
    jmp (IRQLOC)                    ; $FA49
.endif

;; Handles BRK: saves A, X, Y, P and S (SAVE), sets PCL/PCH from the return address on the stack,
;; then jumps through BRKV ($03F0), normally OLDBRK.
;;
;; The Apple II Monitor has no BRKV: it continues in <XBRK>, which does what OLDBRK does.
BREAK:
    plp                             ; $FA4C 1978 $FA92
    jsr SAV1                        ; $FA4D
    pla                             ; $FA50
    sta PCL                         ; $FA51
    pla                             ; $FA53
    sta PCH                         ; $FA54
.if MONITOR = MONITOR_II

;; Apple II Monitor: shows the instruction at PC and the registers, and enters the Monitor.
;;
;; <BREAK> continues here after a BRK, and <STEP> comes here when the instruction to run is a BRK.
;; Later Monitors call this code OLDBRK and reach it through the vector BRKV.
XBRK:
.else
    jmp (BRKV)                      ; $FA56

;; The default BRK handler: disassembles the instruction at PC, shows the registers, and enters the
;; Monitor.
OLDBRK:
.endif
    jsr INSDS1                      ; $FA59 1978 $FA9C
    jsr RGDSP1                      ; $FA5C
    jmp MON                         ; $FA5F
.if MONITOR = MONITOR_II

;; Apple II Monitor: simulates RTI for <STEP>: pulls the status, then the return address (<XRTS>).
;;
;; The carry is cleared so the address is used as it is, where RTS adds one.
XRTI:
    clc                             ; $FAA5
    pla                             ; $FAA6
    sta STATUS                      ; $FAA7

;; Apple II Monitor: simulates RTS for <STEP>: pulls the return address into PCL/PCH and adds one.
;;
;; <STEP> enters with the carry set from its compare, which adds the one; <XRTI> enters with it clear.
;; Entry: PCINC2 = with A the new PCH, PCINC3 = adds LENGTH and the carry to PCL/PCH
XRTS:
    pla                             ; $FAA9
    sta PCL                         ; $FAAA
    pla                             ; $FAAC

PCINC2:
    sta PCH                         ; $FAAD

PCINC3:
    lda LENGTH                      ; $FAAF
    jsr PCADJ3                      ; $FAB1 adds LENGTH and the carry to PCL/PCH
    sty PCH                         ; $FAB4
    clc                             ; $FAB6
    bcc NEWPCL                      ; $FAB7

;; Apple II Monitor: simulates JSR for <STEP>: pushes the address of the JSR's last byte, as JSR does,
;; then jumps to its target (<XJMP>).
XJSR:
    clc                             ; $FAB9
    jsr PCADJ2                      ; $FABA PC + LENGTH, the JSR's last byte
    tax                             ; $FABD
    tya                             ; $FABE
    pha                             ; $FABF
    txa                             ; $FAC0
    pha                             ; $FAC1
    ldy #$02                        ; $FAC2

;; Apple II Monitor: simulates JMP for <STEP>: loads PCL/PCH from the instruction's operand.
;;
;; JMP indirect enters at XJMPAT with the carry set: the first pass loads the pointer into PCL/PCH,
;; and the second, from <NEWPCL>, loads the address it points to.
;; Entry: XJMPAT = keeps the carry, NEWPCL = with A the new PCL
XJMP:
    clc                             ; $FAC4

XJMPAT:
    lda (PCL),y                     ; $FAC5 the high byte (Y = 2, then 1)
    tax                             ; $FAC7
    dey                             ; $FAC8
    lda (PCL),y                     ; $FAC9
    stx PCH                         ; $FACB

NEWPCL:
    sta PCL                         ; $FACD
    bcs XJMP                        ; $FACF

;; Apple II Monitor: ends <STEP>: pushes back the command line's return address, then shows the
;; registers (<REGDSP>) and returns to the command line.
RTNJMP:
    lda RTNH                        ; $FAD1
    pha                             ; $FAD3
    lda RTNL                        ; $FAD4
    pha                             ; $FAD6
.else

;; The reset handler (RESETVEC).
;; Restores normal video, text mode, a full window and the screen and keyboard hooks, turns
;; annunciators 0 and 1 off, lets the internal firmware reset its state, releases any $C800 ROM and
;; clears the keyboard strobe, then beeps.
;; When PWREDUP shows the reset vector (SOFTEV) was set by a program, jumps through SOFTEV; the first
;; time SOFTEV holds BASIC's cold start ($E000) it is changed to $E003 so later resets warm-start
;; AppleSoft. Otherwise this is a power-up (PWRUP).
;;
;; The Autostart Monitor reads CLRAN2 and CLRAN3 in place of the firmware call, as the IIe has no
;; internal firmware to reset. The Apple II Monitor has no RESET: its reset vector points at OLDRST.
RESET:
    cld                             ; $FA62
    jsr SETNORM                     ; $FA63
    jsr INIT                        ; $FA66
    jsr SETVID                      ; $FA69
    jsr SETKBD                      ; $FA6C

INITAN:
    lda CLRAN0                      ; $FA6F
    lda CLRAN1                      ; $FA72
.if MONITOR = MONITOR_AUTOSTART
    lda CLRAN2                      ; $FA75
    lda CLRAN3                      ; $FA78
.else
.if ENHANCED
    ldy #$09                        ; $FA75 firmware function: 5 on the original IIe, 9 on the Enhanced IIe
.else
    ldy #$05                        ; $FA75 firmware function: 5 on the original IIe, 9 on the Enhanced IIe
.endif
    jsr GOTOCX                      ; $FA77
    nop                             ; $FA7A
.endif
    lda CLRROM                      ; $FA7B
    bit KBDSTRB                     ; $FA7E

NEWMON:
    cld                             ; $FA81
    jsr BELL                        ; $FA82
    lda SOFTEV+1                    ; $FA85
    eor #$A5                        ; $FA88
    cmp PWREDUP                     ; $FA8A PWREDUP must equal SOFTEV's high byte EOR $A5
    bne PWRUP                       ; $FA8D
    lda SOFTEV                      ; $FA8F
    bne NOFIX                       ; $FA92
    lda #$E0                        ; $FA94
    cmp SOFTEV+1                    ; $FA96
    bne NOFIX                       ; $FA99

FIXSEV:
    ldy #$03                        ; $FA9B
    sty SOFTEV                      ; $FA9D
    jmp BASIC                       ; $FAA0

;; Warm reset: continues at the program's reset vector, SOFTEV ($03F2).
NOFIX:
    jmp (SOFTEV)                    ; $FAA3

;; Power-up: shows the title, sets BRKV, SOFTEV and PWREDUP to their defaults, then looks for a
;; bootable disk controller from slot 7 down to slot 1 by its signature bytes, and starts the first
;; one found at $Cn00. With none, starts AppleSoft (BASIC).
PWRUP:
    jsr APPLEII                     ; $FAA6

SETPG3:
    ldx #$05                        ; $FAA9

SETPLP:
    lda PWRCON-1,x                  ; $FAAB
    sta BRKV-1,x                    ; $FAAE
    dex                             ; $FAB1
    bne SETPLP                      ; $FAB2
    lda #$C8                        ; $FAB4
    stx LOC0                        ; $FAB6
    sta LOC1                        ; $FAB8

SLOOP:
.if ENHANCED
    ldy #$05                        ; $FABA
.else
    ldy #$07                        ; $FABA
.endif
    dec LOC1                        ; $FABC
    lda LOC1                        ; $FABE
    cmp #$C0                        ; $FAC0
    beq FIXSEV                      ; $FAC2
    sta MSLOT                       ; $FAC4

NXTBYT:
    lda (LOC0),y                    ; $FAC7
    cmp DISKID-1,y                  ; $FAC9
    bne SLOOP                       ; $FACC
    dey                             ; $FACE
    dey                             ; $FACF
    bpl NXTBYT                      ; $FAD0
    jmp (LOC0)                      ; $FAD2
.if ENHANCED
    .byte $00, $00                  ; $FAD5
.else
    .byte $EA, $EA                  ; $FAD5
.endif
.endif

;; Prints a carriage return, then the registers saved by SAVE as "A=xx X=xx Y=xx P=xx S=xx".
;;
;; In the Apple II Monitor, <RTNJMP> falls into it at the end of <STEP>.
REGDSP:
    jsr CROUT                       ; $FAD7

RGDSP1:
    lda #<A5H                       ; $FADA
    sta A3L                         ; $FADC
    lda #>A5H                       ; $FADE
    sta A3H                         ; $FAE0
    ldx #$FB                        ; $FAE2 X runs $FB-$FF over the five registers

RDSP1:
    lda #' '                        ; $FAE4
    jsr COUT                        ; $FAE6
    lda RTBL-$FB,x                  ; $FAE9
    jsr COUT                        ; $FAEC
    lda #'='                        ; $FAEF
    jsr COUT                        ; $FAF1
    lda A5H+5,x                     ; $FAF4 wraps in page zero: A5H, XREG, YREG, STATUS, SPNT
    jsr PRBYTE                      ; $FAF6
    inx                             ; $FAF9
    bmi RDSP1                       ; $FAFA
    rts                             ; $FAFC
.if MONITOR = MONITOR_II

;; Apple II Monitor: the end of a taken branch run by <STEP>: moves PCL/PCH to the branch's target.
;;
;; The copied branch lands on the jump to here in <XQT> when it is taken. The target is PCL/PCH plus
;; the real displacement plus 2, the branch's length.
BRANCH:
    clc                             ; $FAFD
    ldy #$01                        ; $FAFE
    lda (PCL),y                     ; $FB00 the displacement
    jsr PCADJ3                      ; $FB02
    sta PCL                         ; $FB05
    tya                             ; $FB07
    sec                             ; $FB08 PCINC3 adds LENGTH + 1
    bcs PCINC2                      ; $FB09

;; Apple II Monitor: the end of an instruction run by <STEP> that did not branch: saves the registers
;; and moves PCL/PCH past the instruction (<PCINC3>).
NBRNCH:
    jsr SAVE                        ; $FB0B
    sec                             ; $FB0E
    bcs PCINC3                      ; $FB0F

;; Apple II Monitor: what <STEP> puts after the instruction it copies to <XQT>: two NOPs, then a jump
;; to <NBRNCH> for an instruction that falls through and one to <BRANCH> for a taken branch.
;;
;; The instruction overwrites as many of the NOPs as it has operand bytes.
INITBL:
    nop                             ; $FB11
    nop                             ; $FB12
    jmp NBRNCH                      ; $FB13
    jmp BRANCH                      ; $FB16
.else

;; Power-up defaults for $03F0-$03F4: BRKV = OLDBRK, SOFTEV = BASIC ($E000), PWREDUP = $45.
PWRCON:
    .word OLDBRK                    ; $FAFD BRKV
    .word BASIC                     ; $FAFF SOFTEV
    .byte >BASIC ^ $A5              ; $FB01 PWREDUP

;; The disk controller signature PWRUP compares at $Cn01, $Cn03, $Cn05 (and $Cn07 on the original IIe):
;; every other byte. The $FF bytes between are never compared.
;;
;; The Autostart Monitor compares four bytes, as the original IIe does.
DISKID:
    .byte $20, $FF, $00, $FF, $03, $FF, $3C ; $FB02

;; The original IIe's title, "Apple ][", copied by APPLEII.
;;
;; The Autostart Monitor's is in capitals, "APPLE ][".
TITLE:
.if MONITOR = MONITOR_IIE
    .byte "Apple ]["                ; $FB09
.else
    .byte "APPLE ]["                ; $FB09
.endif

;; ESCNOW's translation of the escape-mode keys I, J, K and M to the cursor commands D (up), B (left),
;; A (right) and C (down). L and the bytes after it are not used.
XLTBL:
    .byte "DBA", $FF, "C", $FF, $FF, $FF ; $FB11
.endif

;; Register names for REGDSP: "AXYPS", in reverse order of display.
;;
;; Apple's listing of the Apple II Monitor gives the table no name.
RTBL:
    .byte "AXYPS"                   ; $FB19

;; Reads a game paddle.
;; In: X = paddle (0-3)
;; Out: Y = position (0-255, the time the paddle's timer ran).
;; Uses: A
PREAD:
    lda PTRIG                       ; $FB1E
    ldy #$00                        ; $FB21
    nop                             ; $FB23
    nop                             ; $FB24

PREAD2:
    lda PADDL0,x                    ; $FB25
    bpl RTS2D                       ; $FB28
    iny                             ; $FB2A
    bne PREAD2                      ; $FB2B
    dey                             ; $FB2D

RTS2D:
    rts                             ; $FB2E

;; Sets text mode with a full window, and the lo-res and page-one switches for later graphics.
;; Clears STATUS.
INIT:
    lda #$00                        ; $FB2F
    sta STATUS                      ; $FB31
    lda LORES                       ; $FB33
    lda LOWSCR                      ; $FB36

;; Sets text mode with a full window.
SETTXT:
    lda TXTSET                      ; $FB39
    lda #$00                        ; $FB3C
    beq SETWND                      ; $FB3E

;; Sets mixed lo-res graphics with four text lines, and clears the graphics area.
SETGR:
    lda TXTCLR                      ; $FB40
    lda MIXSET                      ; $FB43
    jsr CLRTOP                      ; $FB46
    lda #$14                        ; $FB49

;; Sets the text window: WNDTOP = A, WNDLFT = 0, and the width and bottom for the current
;; display (40 or 80 columns) through the internal firmware.
;;
;; The Apple II's Monitors set the 40-column width here themselves, then WNDBTM = 24, and move the
;; cursor to the bottom line (TABV).
;; In: A = top line
SETWND:
    sta WNDTOP                      ; $FB4B
    lda #$00                        ; $FB4D
    sta WNDLFT                      ; $FB4F
.if MONITOR = MONITOR_IIE
.if ENHANCED
    ldy #$0C                        ; $FB51
.else
    ldy #$08                        ; $FB51
.endif
    bne GOTOCX                      ; $FB53
.else
    lda #$28                        ; $FB51
    sta WNDWDTH                     ; $FB53
.endif

SETWND_1:
    lda #$18                        ; $FB55
    sta WNDBTM                      ; $FB57
    lda #$17                        ; $FB59

;; Moves the cursor to a line.
;; In: A = line (0-23)
;; Out: CV = A, BASL/BASH set for it (VTAB)
TABV:
    sta CV                          ; $FB5B
    jmp VTAB                        ; $FB5D

.if MONITOR = MONITOR_II

;; Apple II Monitor: multiplies two signed 16-bit numbers, AUXL/AUXH times ACL/ACH.
;;
;; Apple II Monitor only. It makes both numbers positive (<MD1>), which leaves the product's sign in
;; bit 0 of <SIGN> for the caller to apply, then multiplies them (<MUL>).
;; In: ACL/ACH = a number, AUXL/AUXH = the other, XTNDL/XTNDH = a number added to the product (usually 0)
;; Out: ACL/ACH = the product's low 16 bits, XTNDL/XTNDH = its high 16 bits,
;;   SIGN = bit 0 set for a negative product
;; Uses: A, X, Y
;; See: <DIVPM>
MULPM:
    jsr MD1                         ; $FB60

;; Apple II Monitor: multiplies two unsigned 16-bit numbers, AUXL/AUXH times ACL/ACH, and adds
;; XTNDL/XTNDH.
;;
;; Each of its 16 passes adds AUXL/AUXH to XTNDL/XTNDH when bit 0 of ACL is set, then shifts the 32 bits
;; of XTNDH, XTNDL, ACH and ACL right one, the add's carry coming in at the top.
;; In: ACL/ACH = a number, AUXL/AUXH = the other, XTNDL/XTNDH = a number added to the product (usually 0)
;; Out: ACL/ACH = the product's low 16 bits, XTNDL/XTNDH = its high 16 bits, X = $FF, Y = 0
;; Uses: A
MUL:
    ldy #$10                        ; $FB63 16 passes

MUL2:
    lda ACL                         ; $FB65
    lsr a                           ; $FB67
    bcc MUL4                        ; $FB68
    clc                             ; $FB6A
    ldx #$FE                        ; $FB6B X = $FE, $FF: the low byte, then the high byte

MUL3:
    lda XTNDL+2,x                   ; $FB6D
    adc AUXL+2,x                    ; $FB6F
    sta XTNDL+2,x                   ; $FB71
    inx                             ; $FB73
    bne MUL3                        ; $FB74

MUL4:
    ldx #$03                        ; $FB76

MUL5:
    ror ACL,x                       ; $FB78 XTNDH, XTNDL, ACH, ACL
    dex                             ; $FB7A
    bpl MUL5                        ; $FB7B
    dey                             ; $FB7D
    bne MUL2                        ; $FB7E
    rts                             ; $FB80

;; Apple II Monitor: divides two signed 16-bit numbers, ACL/ACH by AUXL/AUXH.
;;
;; Apple II Monitor only. It makes both numbers positive (<MD1>), which leaves the quotient's sign in
;; bit 0 of <SIGN> for the caller to apply, then divides them (<DIV>).
;; In: ACL/ACH = the dividend, AUXL/AUXH = the divisor, XTNDL/XTNDH = 0
;; Out: ACL/ACH = the quotient, XTNDL/XTNDH = the remainder, SIGN = bit 0 set for a negative quotient
;; Uses: A, X, Y
;; See: <MULPM>
DIVPM:
    jsr MD1                         ; $FB81

;; Apple II Monitor: divides the unsigned 32-bit number in XTNDL/XTNDH (high) and ACL/ACH (low) by
;; AUXL/AUXH.
;;
;; Each of its 16 passes shifts the 32 bits left one and, when the top half is at least AUXL/AUXH,
;; subtracts it there and sets the quotient bit at the bottom of ACL. The quotient fits in 16 bits when
;; XTNDL/XTNDH starts below AUXL/AUXH, as it does with XTNDL/XTNDH = 0.
;; In: ACL/ACH = the dividend's low half, XTNDL/XTNDH = its high half (usually 0), AUXL/AUXH = the divisor
;; Out: ACL/ACH = the quotient, XTNDL/XTNDH = the remainder, Y = 0
;; Uses: A, X
DIV:
    ldy #$10                        ; $FB84 16 passes

DIV2:
    asl ACL                         ; $FB86
    rol ACH                         ; $FB88
    rol XTNDL                       ; $FB8A
    rol XTNDH                       ; $FB8C
    sec                             ; $FB8E
    lda XTNDL                       ; $FB8F
    sbc AUXL                        ; $FB91
    tax                             ; $FB93
    lda XTNDH                       ; $FB94
    sbc AUXH                        ; $FB96
    bcc DIV3                        ; $FB98 too small: the quotient bit stays 0
    stx XTNDL                       ; $FB9A
    sta XTNDH                       ; $FB9C
    inc ACL                         ; $FB9E

DIV3:
    dey                             ; $FBA0
    bne DIV2                        ; $FBA1
    rts                             ; $FBA3

;; Apple II Monitor: makes AUXL/AUXH and ACL/ACH positive for <MULPM> and <DIVPM>, counting the
;; numbers it negates in <SIGN>.
;;
;; MD2 negates the 16-bit number at page zero X when it is negative, and MD3 negates it whatever its
;; sign; both need Y = 0. Bit 0 of SIGN ends set when exactly one number was negative.
;; Out: SIGN = the count of negated numbers, Y = 0
;; Uses: A, X
;; Entry: MD2 = with X the number's address, MD3 = with X the number's address and the carry set
MD1:
    ldy #$00                        ; $FBA4
    sty SIGN                        ; $FBA6
    ldx #AUXL                       ; $FBA8
    jsr MD2                         ; $FBAA
    ldx #ACL                        ; $FBAD

MD2:
    lda LOC1,x                      ; $FBAF the high byte
    bpl MDRTS                       ; $FBB1
    sec                             ; $FBB3 the byte the IIe's VERSION reads here, $38

MD3:
    tya                             ; $FBB4 0 minus the number
    sbc LOC0,x                      ; $FBB5
    sta LOC0,x                      ; $FBB7
    tya                             ; $FBB9
    sbc LOC1,x                      ; $FBBA
    sta LOC1,x                      ; $FBBC
    inc SIGN                        ; $FBBE

MDRTS:
    rts                             ; $FBC0
.else

;; Clears the screen and shows the model's title at the top center: "Apple ][" on the original IIe,
;; "Apple //e" on the Enhanced IIe.
;;
;; The Autostart Monitor's PWRUP shows "APPLE ][" this way. The Apple II Monitor has no title.
APPLEII:
    jsr HOME                        ; $FB60
.if ENHANCED
    ldy #$09                        ; $FB63
.else
    ldy #$08                        ; $FB63
.endif

STITLE:
.if ENHANCED
    lda TITLE2E-1,y                 ; $FB65
.else
    lda TITLE-1,y                   ; $FB65
.endif
    sta $040E,y                     ; $FB68
    dey                             ; $FB6B
    bne STITLE                      ; $FB6C
    rts                             ; $FB6E

;; Makes the reset vector valid: PWREDUP = SOFTEV's high byte EOR $A5. Call after changing SOFTEV.
SETPWRC:
    lda SOFTEV+1                    ; $FB6F
    eor #$A5                        ; $FB72
    sta PWREDUP                     ; $FB74
    rts                             ; $FB77

;; Screen output with pause: when A is a carriage return and the user has typed Control-S, waits
;; for another key before printing (KBDWAIT). Then prints A (VIDOUT).
;; In: A = character
VIDWAIT:
    cmp #KEY_CR                     ; $FB78
    bne NOWAIT                      ; $FB7A
    ldy KBD                         ; $FB7C
    bpl NOWAIT                      ; $FB7F
    cpy #KEY_CTRL_S                 ; $FB81
    bne NOWAIT                      ; $FB83
    bit KBDSTRB                     ; $FB85

;; Waits for a key and clears the strobe, except for Control-C, which stays in the keyboard latch
;; for the program to see. Then prints A (VIDOUT).
KBDWAIT:
    ldy KBD                         ; $FB88
    bpl KBDWAIT                     ; $FB8B
    cpy #KEY_CTRL_C                 ; $FB8D
    beq NOWAIT                      ; $FB8F
    bit KBDSTRB                     ; $FB91

NOWAIT:
    jmp VIDOUT                      ; $FB94

;; Escape-mode cursor command: handles the character in A as an ESC command (ESC1) with carry set.
ESCOLD:
    sec                             ; $FB97
    jmp ESC1                        ; $FB98

;; Escape mode: shows the escape cursor, reads a key and handles cursor-moving keys until another
;; key ends escape mode.
;;
;; The Autostart Monitor reads the next key with RDKEY, without an escape cursor of its own. The Apple
;; II Monitor has no escape keys I, J, K and M: its <ESC> hands every key to ESC1.
ESCNOW:
    tay                             ; $FB9B
    lda XLTBL-'I',y                 ; $FB9C
    jsr ESCOLD                      ; $FB9F
.if MONITOR = MONITOR_IIE
    jsr RDESC                       ; $FBA2
.else
    jsr RDKEY                       ; $FBA2
.endif

ESCNEW:
    cmp #'N'                        ; $FBA5
    bcs ESCOLD                      ; $FBA7
    cmp #'I'                        ; $FBA9
    bcc ESCOLD                      ; $FBAB
    cmp #'L'                        ; $FBAD
    beq ESCOLD                      ; $FBAF
    bne ESCNOW                      ; $FBB1

;; The model identification byte: $06 means an Apple IIe (with $FBC0, below).
;;
;; Programs read the same address on the Apple II: the Autostart Monitor has $EA here, followed by
;; unused $EA bytes up to $FBC0, and the Apple II Monitor $38, a SEC in its MD2.
VERSION:
.if MONITOR = MONITOR_AUTOSTART
    .byte $EA                       ; $FBB3
    .res 13, $EA                    ; $FBB4 unused
.else
    .byte $06                       ; $FBB3

;; Calls the internal firmware: saves whether slot ROM or internal ROM was selected at $C100-$CFFF,
;; switches internal ROM in and jumps to the firmware's dispatcher at $C100, which performs the
;; function in Y and switches back.
;; In: Y = function number; other registers as the function needs
;; The original IIe also saves the interrupt state and disables interrupts first.
GOTOCX:
.if .not ENHANCED
    php                             ; $FBB4
    sei                             ; $FBB5
.endif
    bit RDCXROM                     ; $FBB4 original $FBB6
    php                             ; $FBB7 original $FBB9
    sta SETINTCXROM                 ; $FBB8 original $FBBA
.if ENHANCED
    jmp $C100                       ; $FBBB
    .byte $00, $00, $E0             ; $FBBE $FBC0 = $E0 identifies the Enhanced IIe
.else
    jmp B_FUNC                      ; $FBBD
    .byte $EA                       ; $FBC0 identifies the original IIe ($EA)
.endif
.endif
.endif

;; Computes a text line's base address on page one.
;; In: A = line (0-23)
;; Out: BASL/BASH
;; Keeps: X, Y
BASCALC:
    pha                             ; $FBC1
    lsr a                           ; $FBC2
    and #$03                        ; $FBC3
    ora #$04                        ; $FBC5
    sta BASH                        ; $FBC7
    pla                             ; $FBC9
    and #$18                        ; $FBCA
    bcc BASCLC2                     ; $FBCC
    adc #$7F                        ; $FBCE

BASCLC2:
    sta BASL                        ; $FBD0
    asl a                           ; $FBD2
    asl a                           ; $FBD3
    ora BASL                        ; $FBD4
    sta BASL                        ; $FBD6
    rts                             ; $FBD8

;; Rings the bell when A is Control-G ($87): about 0.1 seconds at roughly 1 kHz. VIDOUT sends other
;; control characters here too, and they are ignored.
;; Uses A, Y.
BELL1:
    cmp #KEY_BELL                   ; $FBD9
    bne RTS2B                       ; $FBDB
    lda #$40                        ; $FBDD from here the bell rings whatever A holds
    jsr WAIT                        ; $FBDF
    ldy #$C0                        ; $FBE2

BELL2:
    lda #$0C                        ; $FBE4
    jsr WAIT                        ; $FBE6
    lda SPKR                        ; $FBE9
    dey                             ; $FBEC
    bne BELL2                       ; $FBED

RTS2B:
    rts                             ; $FBEF

;; Stores a printable character at the cursor, then advances the cursor (ADVANCE).
STORADV:
    ldy CH                          ; $FBF0
    sta (BASL),y                    ; $FBF2

;; Moves the cursor right; at the window's right edge, starts a new line (CR).
ADVANCE:
    inc CH                          ; $FBF4
    lda CH                          ; $FBF6
    cmp WNDWDTH                     ; $FBF8
    bcs CR                          ; $FBFA

RTS3:
    rts                             ; $FBFC

;; The screen's character output: prints A at the cursor, or performs carriage return, line feed,
;; backspace or bell.
;; In: A = character with the high bit set
VIDOUT:
    cmp #' '                        ; $FBFD
    bcs STORADV                     ; $FBFF
    tay                             ; $FC01
    bpl STORADV                     ; $FC02
    cmp #KEY_CR                     ; $FC04
    beq CR                          ; $FC06
    cmp #KEY_LF                     ; $FC08
    beq LF                          ; $FC0A
    cmp #KEY_BS                     ; $FC0C
    bne BELL1                       ; $FC0E

;; Moves the cursor left; at the window's left edge, to the end of the line above.
BS:
    dec CH                          ; $FC10
    bpl RTS3                        ; $FC12
    lda WNDWDTH                     ; $FC14
    sta CH                          ; $FC16
    dec CH                          ; $FC18

;; Moves the cursor up a line unless it is on the window's top line.
UP:
    lda WNDTOP                      ; $FC1A
    cmp CV                          ; $FC1C
.if ENHANCED
    bcs RTS3                        ; $FC1E
.else
    bcs RTS4                        ; $FC1E
.endif
    dec CV                          ; $FC20

;; Sets BASL/BASH for the cursor's line, CV.
VTAB:
    lda CV                          ; $FC22

;; Sets BASL/BASH for a line, offset by the window's left edge.
;; In: A = line
;; The Enhanced IIe asks the internal firmware (function 4), which knows the 80-column layout.
VTABZ:
.if ENHANCED
    sta BASL                        ; $FC24
    tya                             ; $FC26
    ldy #$04                        ; $FC27
.else
    jsr BASCALC                     ; $FC24
    adc WNDLFT                      ; $FC27
.endif

VTABZ_1:
.if ENHANCED
    bne GOTOCX                      ; $FC29
    .byte $00                       ; $FC2B unused
.else
    sta BASL                        ; $FC29

RTS4:
    rts                             ; $FC2B
.endif

;; Performs an escape command: @ clears the window (HOME), A/B/C/D move the cursor right, left,
;; down and up, E clears to the end of the line, F to the end of the window.
;; In: A = command character
ESC1:
    eor #'@'                        ; $FC2C
    beq HOME                        ; $FC2E
    adc #$FD                        ; $FC30
    bcc ADVANCE                     ; $FC32
    beq BS                          ; $FC34
    adc #$FD                        ; $FC36
    bcc LF                          ; $FC38
    beq UP                          ; $FC3A
    adc #$FD                        ; $FC3C
    bcc CLREOL                      ; $FC3E
.if ENHANCED
    bne RTS3                        ; $FC40
.else
    bne RTS4                        ; $FC40
.endif

;; Clears from the cursor to the end of the window.
;;
;; The Apple II's Monitors clear the window here themselves, a line at a time from the cursor's line
;; down (CLREOLZ), then set BASL/BASH for the cursor's line again (VTAB).
CLREOP:
.if MONITOR = MONITOR_IIE
.if ENHANCED
    ldy #$0A                        ; $FC42
    bne VTABZ_1                     ; $FC44

CLREOP_1:
    bit RD80VID                     ; $FC46
    bpl CLREOP_2                    ; $FC49
.endif
    ldy #$00                        ; $FC4B original $FC42
.if ENHANCED
    beq HOME_1                      ; $FC4D
.else
    beq XGOTOCX                     ; $FC44

CLREOP_1:
    .byte "(C) 1981-"               ; $FC46 unused bytes holding a copyright notice
.endif

CLREOP_2:
.if ENHANCED
    tya                             ; $FC4F
    pha                             ; $FC50
    jsr VIDWAIT                     ; $FC51
    pla                             ; $FC54
    ldy YSAV1                       ; $FC55
    rts                             ; $FC57
.else
    .byte "82, APPLE"               ; $FC4F
.endif
.else
    ldy CH                          ; $FC42 the first line clears from the cursor
    lda CV                          ; $FC44

CLEOP1:
    pha                             ; $FC46
    jsr VTABZ                       ; $FC47
    jsr CLREOLZ                     ; $FC4A returns with the carry set
    ldy #$00                        ; $FC4D the other lines clear from column 0
    pla                             ; $FC4F
    adc #$00                        ; $FC50 the next line (plus the carry)
    cmp WNDBTM                      ; $FC52
    bcc CLEOP1                      ; $FC54
    bcs VTAB                        ; $FC56
.endif

;; Clears the window and puts the cursor at its top left.
;;
;; The Apple II's Monitors move the cursor to the window's top line, column 0, and clear from there
;; in CLREOP.
HOME:
.if MONITOR = MONITOR_IIE
.if ENHANCED
    ldy #$05                        ; $FC58
.else
    ldy #$01                        ; $FC58
.endif

HOME_1:
.if ENHANCED
    jmp GOTOCX                      ; $FC5A
    .byte $53, $5C, $5C, $00, $00   ; $FC5D
.else
    bne XGOTOCX                     ; $FC5A
    .byte "RICK A"                  ; $FC5C
.endif
.else
    lda WNDTOP                      ; $FC58
    sta CV                          ; $FC5A
    ldy #$00                        ; $FC5C
    sty CH                          ; $FC5E
    beq CLEOP1                      ; $FC60
.endif

;; Carriage return: moves the cursor to the start of the next line (LF).
CR:
    lda #$00                        ; $FC62
    sta CH                          ; $FC64

;; Line feed: moves the cursor down a line, scrolling the window at the bottom.
LF:
    inc CV                          ; $FC66
    lda CV                          ; $FC68
    cmp WNDBTM                      ; $FC6A
    bcc VTABZ                       ; $FC6C
    dec CV                          ; $FC6E

;; Scrolls the text window up one line and clears the bottom line.
;;
;; The Apple II's Monitors scroll here themselves: from the window's top line down, each line gets a
;; copy of the one below it, from the right edge of the window to the left. The bottom line is then
;; cleared and BASL/BASH set for the cursor's line again (VTAB).
SCROLL:
.if MONITOR = MONITOR_IIE
.if ENHANCED
    ldy #$06                        ; $FC70
    bne VTABZ_1                     ; $FC72

XGOTOCX_1:
    sta SETSLOTCXROM                ; $FC74
    jmp (IRQLOC)                    ; $FC77
.else
    ldy #$02                        ; $FC70

XGOTOCX:
    jmp GOTOCX                      ; $FC72

;; Original IIe: returning from the internal firmware. Restores page one when 80STORE is on and page
;; two was displayed, briefly enables interrupts with slot ROM switched in so a pending interrupt can
;; run, and restores the saved ROM selection and display page.
;; Enhanced IIe: these bytes select a slot's $C800 ROM (MSLOT) for the interrupt handler, then continue
;; in the internal firmware at $C47C.
VIDSYNC:
    pha                             ; $FC75
    lda RD80STORE                   ; $FC76
    asl a                           ; $FC79
.endif

VIDSYNC_1:
    pla                             ; $FC7A
.if ENHANCED
    sta MSLOT                       ; $FC7B
    cmp #$C1                        ; $FC7E
    bcc IRQNOSLT                    ; $FC80
    sta CLRROM                      ; $FC82
    ldy #$00                        ; $FC85
    ldx LOC1                        ; $FC87
    sta LOC1                        ; $FC89
    lda (LOC0),y                    ; $FC8B
    stx LOC1                        ; $FC8D

;; Enhanced IIe: switches internal ROM back in and continues in the firmware's interrupt code (IRQRESTORE).
IRQNOSLT:
.else
    bit RDPAGE2                     ; $FC7B
    php                             ; $FC7E
    bcc RDCX                        ; $FC7F
    sta LOWSCR                      ; $FC81

RDCX:
    bit RDCXROM                     ; $FC84
    sta SETSLOTCXROM                ; $FC87
    cli                             ; $FC8A
    sei                             ; $FC8B
    bpl ISSLOTS                     ; $FC8C
.endif
    sta SETINTCXROM                 ; $FC8F original $FC8E
.if ENHANCED
    jmp IRQRESTORE                  ; $FC92

;; Enhanced IIe: COUT1's printable-character path: applies INVFLG and prints the character (COUTZ).
DOCOUT1:
    bcc DOCOUT2                     ; $FC95
    and INVFLG                      ; $FC97

DOCOUT2:
    jmp COUTZ_1                     ; $FC99
.else

;; Original IIe: restores the saved status and, when page two was displayed, switches back to it.
ISSLOTS:
    plp                             ; $FC91
    bcc ISPAGE1                     ; $FC92
    bpl ISPAGE1                     ; $FC94
    bit HISCR                       ; $FC96

ISPAGE1:
    rts                             ; $FC99
    .byte $EA, $EA                  ; $FC9A
.endif
.else
    lda WNDTOP                      ; $FC70
    pha                             ; $FC72 the line number being filled
    jsr VTABZ                       ; $FC73

SCRL1:
    lda BASL                        ; $FC76 the line just read becomes the one to fill
    sta BAS2L                       ; $FC78
    lda BASH                        ; $FC7A
    sta BAS2H                       ; $FC7C
    ldy WNDWDTH                     ; $FC7E
    dey                             ; $FC80
    pla                             ; $FC81
    adc #$01                        ; $FC82 the next line down
    cmp WNDBTM                      ; $FC84
    bcs SCRL3                       ; $FC86
    pha                             ; $FC88
    jsr VTABZ                       ; $FC89

SCRL2:
    lda (BASL),y                    ; $FC8C
    sta (BAS2L),y                   ; $FC8E
    dey                             ; $FC90
    bpl SCRL2                       ; $FC91
    bmi SCRL1                       ; $FC93

SCRL3:
    ldy #$00                        ; $FC95
    jsr CLREOLZ                     ; $FC97 BASL/BASH still hold the bottom line; returns with the carry set
    bcs VTAB                        ; $FC9A
.endif

;; Clears from the cursor to the end of the line.
CLREOL:
.if MONITOR = MONITOR_IIE
.if ENHANCED
    sec                             ; $FC9C
    .byte $90                       ; $FC9D bcc: skips the next byte
.else
    clc                             ; $FC9C
    .byte $B0                       ; $FC9D bcs: skips the next byte
.endif
.else
    ldy CH                          ; $FC9C
.endif

;; Clears a line from a column to its end.
;;
;; The Apple II's Monitors store blanks here themselves, up to the window's width, and return with the
;; carry set. Their listings call it CLEOLZ.
;; In: Y = column; BASL/BASH = the line
CLREOLZ:
.if MONITOR = MONITOR_IIE
.if ENHANCED
    clc                             ; $FC9E
    sty BAS2L                       ; $FC9F
    ldy #$07                        ; $FCA1
    bcs KEYIN_1                     ; $FCA3
.else
    sec                             ; $FC9E
    sty $1F                         ; $FC9F
    ldy #$03                        ; $FCA1
    bcc XGOTOCX                     ; $FCA3
.endif
    iny                             ; $FCA5
.if ENHANCED
    bne KEYIN_1                     ; $FCA6
.else
    bne XGOTOCX                     ; $FCA6
.endif
.else
    lda #' '                        ; $FC9E

CLEOL2:
    sta (BASL),y                    ; $FCA0
    iny                             ; $FCA1
    cpy WNDWDTH                     ; $FCA3
    bcc CLEOL2                      ; $FCA5
    rts                             ; $FCA7
.endif

;; Delays.
;; In: A = count
;; Takes about (26 + 27A + 5A^2) / 2 microseconds.
;; Out: A = 0.
WAIT:
    sec                             ; $FCA8

WAIT2:
    pha                             ; $FCA9

WAIT3:
    sbc #$01                        ; $FCAA
    bne WAIT3                       ; $FCAC
    pla                             ; $FCAE
    sbc #$01                        ; $FCAF
    bne WAIT2                       ; $FCB1
    rts                             ; $FCB3

;; Increments A4, then does NXTA1 (used by MOVE to step source and destination together).
NXTA4:
    inc A4L                         ; $FCB4
    bne NXTA1                       ; $FCB6
    inc A4H                         ; $FCB8

;; Compares A1 with A2, then increments A1.
;; Out:   carry = set when A1 was at or past A2 (the range is finished)
NXTA1:
    lda A1L                         ; $FCBA
    cmp A2L                         ; $FCBC
    lda A1H                         ; $FCBE
    sbc A2H                         ; $FCC0
    inc A1L                         ; $FCC2
    bne RTS4B                       ; $FCC4
    inc A1H                         ; $FCC6

RTS4B:
    rts                             ; $FCC8

;; Writes a cassette header tone.
;; Original IIe: a tone of A times 256 half cycles, then the sync bit.
;; Enhanced IIe: the cassette routines live in internal ROM; this calls them there.
HEADR:
.if ENHANCED
    sta SETINTCXROM                 ; $FCC9
    jsr TAPEHEADR                   ; $FCCC
    jmp SLOTRTS                     ; $FCCF
.else
    ldy #$4B                        ; $FCC9
    jsr ZERDLY                      ; $FCCB
    bne HEADR                       ; $FCCE
    adc #$FE                        ; $FCD0
.endif

HEADR_1:
.if ENHANCED
    sta SETSLOTCXROM                ; $FCD2
    jsr PRBL2                       ; $FCD5
    lda #'^'                        ; $FCD8
    jsr COUT                        ; $FCDA
    jsr BELL                        ; $FCDD
    jmp RDBYT2_1                    ; $FCE0
.else
    bcs HEADR                       ; $FCD2
    ldy #$21                        ; $FCD4

WRBIT:
    jsr ZERDLY                      ; $FCD6
    iny                             ; $FCD9
    iny                             ; $FCDA

ZERDLY:
    dey                             ; $FCDB
    bne ZERDLY                      ; $FCDC
    bcc WRTAPE                      ; $FCDE
    ldy #$32                        ; $FCE0

ONEDLY:
    dey                             ; $FCE2
.endif

ONEDLY_1:
.if ENHANCED
    sta SETSLOTCXROM                ; $FCE3
    jsr INSTDSP                     ; $FCE6
    jsr PCADJ                       ; $FCE9
.else
    bne ONEDLY                      ; $FCE3

WRTAPE:
    ldy TAPEOUT                     ; $FCE5
    ldy #$2C                        ; $FCE8
    dex                             ; $FCEA
    rts                             ; $FCEB
.endif

; Original IIe: reads one byte from the cassette.
; Out: A = the byte.
; The Enhanced IIe uses these bytes for its command line (input of the mini-assembler and the
; uppercase conversion of Monitor input).
.if ENHANCED
    sty PCH                         ; $FCEC
    sta PCL                         ; $FCEE

RDBYT2_1:
    lda #'!'                        ; $FCF0
    sta PROMPT                      ; $FCF2
    jsr GETLNZ                      ; $FCF4
    sta SETINTCXROM                 ; $FCF7
.else

RDBYTE:
    ldx #$08                        ; $FCEC

RDBYT2:
    pha                             ; $FCEE
    jsr RD2BIT                      ; $FCEF
    pla                             ; $FCF2
    rol a                           ; $FCF3
    ldy #$3A                        ; $FCF4
    dex                             ; $FCF6
    bne RDBYT2                      ; $FCF7
    rts                             ; $FCF9
.endif

; Original IIe: reads a cassette bit as the time between two transitions.
; Out: carry = the bit.
; The Apple II's Monitors read cassette bits the same way; their listings call LENGTH LASTIN here.
.if ENHANCED
    jmp MINILINE                    ; $FCFA

UPMON:
    lda IN,y                        ; $FCFD
    iny                             ; $FD00
    cmp #'a'                        ; $FD01
    bcc RDBIT_1                     ; $FD03
    cmp #'z' + 1                    ; $FD05
    bcs RDBIT_1                     ; $FD07
    and #$DF                        ; $FD09 to uppercase
.else

RD2BIT:
    jsr RDBIT                       ; $FCFA

RDBIT:
    dey                             ; $FCFD
    lda TAPEIN                      ; $FCFE
    eor LENGTH                      ; $FD01
    bpl RDBIT                       ; $FD03
    eor LENGTH                      ; $FD05
    sta LENGTH                      ; $FD07
    cpy #$80                        ; $FD09
.endif

RDBIT_1:
    rts                             ; $FD0B

;; Reads a key through the input hook, KSWL, with a cursor shown.
;; Out: A = key with the high bit set
;; Original IIe: shows the cursor by flashing the character under it. Enhanced IIe: the internal
;; firmware (function $0B) shows the cursor for 40 or 80 columns.
RDKEY:
.if ENHANCED
    ldy #$0B                        ; $FD0C
    bne RDKEY_1                     ; $FD0E
    jmp RDKEYHOOK                   ; $FD10 not reached from here
.else
    ldy CH                          ; $FD0C
    lda (BASL),y                    ; $FD0E
    pha                             ; $FD10
    and #$3F                        ; $FD11
.endif

RDKEY_1:
.if ENHANCED
    jsr GOTOCX                      ; $FD13
    nop                             ; $FD16
    nop                             ; $FD17
.else
    ora #$40                        ; $FD13
    sta (BASL),y                    ; $FD15
    pla                             ; $FD17
.endif

RDKEYHOOK:
    jmp (KSWL)                      ; $FD18

;; The keyboard's input routine (KSWL's default): the internal firmware waits for a key, then clears
;; the strobe.
;;
;; The Apple II's Monitors wait here themselves, counting up RNDL/RNDH while they wait. When a key
;; comes, they put back the character that RDKEY replaced with the flashing cursor (A at the cursor,
;; CH in Y), then read the key and clear the strobe.
;; Out: A = key with the high bit set
KEYIN:
.if MONITOR = MONITOR_IIE
.if ENHANCED
    ldy #$03                        ; $FD1B
.else
    ldy #$06                        ; $FD1B
.endif

KEYIN_1:
    jmp GOTOCX                      ; $FD1D
    .byte $EA                       ; $FD20

;; Reads a key, then lets the internal firmware handle it as an escape-mode key.
RDESC:
    jsr RDKEY                       ; $FD21
.if ENHANCED
    ldy #$01                        ; $FD24
    bne KEYIN_1                     ; $FD26

RDESC_1:
    lsr MSLOT                       ; $FD28
    jmp RDKEY                       ; $FD2B
    .byte $EA                       ; $FD2E
.else
    ldy #$07                        ; $FD24
    jmp GOTOCX                      ; $FD26

;; Original IIe: switches slot ROM back in and returns with the saved status (the internal firmware's
;; way back).
SLOTRTN:
    sta SETSLOTCXROM                ; $FD29

SLOTRTN_1:
    plp                             ; $FD2C
    rts                             ; $FD2D
    .byte $60                       ; $FD2E
.endif
.else
    inc RNDL                        ; $FD1B
    bne KEYIN2                      ; $FD1D
    inc RNDH                        ; $FD1F

KEYIN2:
    bit KBD                         ; $FD21
    bpl KEYIN                       ; $FD24
    sta (BASL),y                    ; $FD26
    lda KBD                         ; $FD28
    bit KBDSTRB                     ; $FD2B
    rts                             ; $FD2E
.endif

;; Escape mode: handles ESC commands until a non-command key, then reads the next character.
;;
;; The Apple II's Monitors read the key with RDKEY. The Apple II Monitor performs one command (ESC1)
;; and leaves escape mode.
ESC:
.if MONITOR = MONITOR_IIE
    jsr RDESC                       ; $FD2F
.else
    jsr RDKEY                       ; $FD2F
.endif
.if MONITOR = MONITOR_II
    jsr ESC1                        ; $FD32
.else
    jsr ESCNEW                      ; $FD32
.endif

;; Reads a character, handling ESC sequences (cursor movement) instead of returning them.
;; Out: A = character
RDCHAR:
.if ENHANCED
    jsr RDESC_1                     ; $FD35
.else
    jsr RDKEY                       ; $FD35
.endif
    cmp #KEY_ESC                    ; $FD38
    beq ESC                         ; $FD3A
    rts                             ; $FD3C

; GETLN's echo of a character that is not a carriage return: prints it, handles backspace and
; Control-X (cancel), and beeps near the end of the 248-byte buffer.
.if ENHANCED

PICKFIX:
    ldy #$0F                        ; $FD3D
    jsr GOTOCX                      ; $FD3F
    ldy CH                          ; $FD42
    sta IN,x                        ; $FD44

NOTCR_1:
    jsr COUT                        ; $FD47
    nop                             ; $FD4A
.else

NOTCR:
    lda INVFLG                      ; $FD3D
    pha                             ; $FD3F
    lda #$FF                        ; $FD40
.endif
.if MONITOR = MONITOR_IIE
    nop                             ; $FD4B original $FD42
    nop                             ; $FD4C original $FD43
.else
    sta INVFLG                      ; $FD42 the Apple II's echo is always in normal video
.endif
    lda IN,x                        ; $FD4D original $FD44
.if .not ENHANCED

NOTCR_1:
    jsr COUT                        ; $FD47
    pla                             ; $FD4A
    sta INVFLG                      ; $FD4B
    lda IN,x                        ; $FD4D
.endif
    cmp #KEY_BS                     ; $FD50
    beq BCKSPC                      ; $FD52
    cmp #KEY_CTRL_X                 ; $FD54
    beq CANCEL                      ; $FD56
    cpx #$F8                        ; $FD58
    bcc NOTCR1                      ; $FD5A
    jsr BELL                        ; $FD5C

NOTCR1:
    inx                             ; $FD5F
    bne NXTCHAR                     ; $FD60

;; Cancels the input line: prints a backslash and starts again.
CANCEL:
    lda #'\'                        ; $FD62
    jsr COUT                        ; $FD64

;; GETLN after a carriage return.
GETLNZ:
    jsr CROUT                       ; $FD67

;; Reads a line of input into IN ($0200) after printing the prompt character in PROMPT.
;; Backspace deletes a character, Control-X cancels the line, and the right arrow (Control-U) copies
;; the character under the cursor.
;;
;; The Apple II's Monitors store lowercase letters as capitals, and echo the line in normal video
;; whatever INVFLG holds.
;; Out: X = length; the line ends with a carriage return at IN,X
GETLN:
    lda PROMPT                      ; $FD6A
    jsr COUT                        ; $FD6C

;; GETLN without printing the prompt.
GETLN_1:
    ldx #$01                        ; $FD6F

BCKSPC:
    txa                             ; $FD71
    beq GETLNZ                      ; $FD72
    dex                             ; $FD74

;; Reads the next character of an input line; Control-U takes the character under the cursor.
NXTCHAR:
    jsr RDCHAR                      ; $FD75
    cmp #KEY_RIGHT                  ; $FD78
.if ENHANCED
    bne ADDINP                      ; $FD7A
.else
    bne CAPTST                      ; $FD7A
.endif
    lda (BASL),y                    ; $FD7C
.if ENHANCED
    bit RD80VID                     ; $FD7E
    bmi PICKFIX                     ; $FD81
    nop                             ; $FD83
.else

CAPTST:
    cmp #'a' - 1                    ; $FD7E lowercase passes unchanged
    bcc ADDINP                      ; $FD80
.if MONITOR = MONITOR_IIE
    and #$FF                        ; $FD82
.else
    and #$DF                        ; $FD82 the Apple II's Monitors make it uppercase
.endif
.endif

;; Stores a character in the input line and handles it (NOTCR) unless it is a carriage return.
ADDINP:
    sta IN,x                        ; $FD84
    cmp #KEY_CR                     ; $FD87
.if ENHANCED
    bne NOTCR_1                     ; $FD89
.else
    bne NOTCR                       ; $FD89
.endif

;; Clears the rest of the line, then prints a carriage return.
CROUT1:
    jsr CLREOL                      ; $FD8B

;; Prints a carriage return.
CROUT:
    lda #KEY_CR                     ; $FD8E
    bne COUT                        ; $FD90

;; Prints a carriage return, then A1 as "AAAA-".
PRA1:
    ldy A1H                         ; $FD92
    ldx A1L                         ; $FD94

PRYX2:
    jsr CROUT                       ; $FD96
    jsr PRNTYX                      ; $FD99
    ldy #$00                        ; $FD9C
    lda #'-'                        ; $FD9E
    jmp COUT                        ; $FDA0

;; Monitor examine: shows the eight bytes from A1 (to the next multiple of 8).
XAM8:
    lda A1L                         ; $FDA3
    ora #$07                        ; $FDA5
    sta A2L                         ; $FDA7
    lda A1H                         ; $FDA9
    sta A2H                         ; $FDAB

MOD8CHK:
    lda A1L                         ; $FDAD
    and #$07                        ; $FDAF
    bne DATAOUT                     ; $FDB1

;; Monitor examine: shows memory from A1 to A2, eight bytes per line.
XAM:
    jsr PRA1                        ; $FDB3

DATAOUT:
    lda #' '                        ; $FDB6
    jsr COUT                        ; $FDB8
    lda (A1L),y                     ; $FDBB
    jsr PRBYTE                      ; $FDBD
    jsr NXTA1                       ; $FDC0
    bcc MOD8CHK                     ; $FDC3

RTS4C:
    rts                             ; $FDC5

;; Monitor + and - commands: prints A1 plus or minus A2 as "=xx".
XAMPM:
    lsr a                           ; $FDC6
    bcc XAM                         ; $FDC7
    lsr a                           ; $FDC9
    lsr a                           ; $FDCA
    lda A2L                         ; $FDCB
    bcc ADD                         ; $FDCD
    eor #$FF                        ; $FDCF

ADD:
    adc A1L                         ; $FDD1
    pha                             ; $FDD3
    lda #'='                        ; $FDD4
    jsr COUT                        ; $FDD6
    pla                             ; $FDD9

;; Prints A as two hex digits.
PRBYTE:
    pha                             ; $FDDA
    lsr a                           ; $FDDB
    lsr a                           ; $FDDC
    lsr a                           ; $FDDD
    lsr a                           ; $FDDE
    jsr PRHEXZ                      ; $FDDF
    pla                             ; $FDE2

;; Prints the low four bits of A as a hex digit.
PRHEX:
    and #$0F                        ; $FDE3

PRHEXZ:
    ora #'0'                        ; $FDE5
    cmp #'9' + 1                    ; $FDE7
    bcc COUT                        ; $FDE9
    adc #$06                        ; $FDEB

;; Prints a character through the output hook, CSWL.
;; In: A = character with the high bit set
COUT:
    jmp (CSWL)                      ; $FDED

;; The screen's output routine (CSWL's default): applies INVFLG to printable characters, then prints
;; with the Control-S pause (VIDWAIT).
;; Keeps: A, Y
COUT1:
.if ENHANCED
    pha                             ; $FDF0
.endif
    cmp #' '                        ; $FDF1 original $FDF0
.if ENHANCED
    jmp DOCOUT1                     ; $FDF3
.else
    bcc COUTZ                       ; $FDF2
    and INVFLG                      ; $FDF4
.endif

;; Prints a character on the screen without applying INVFLG.
;;
;; The Apple II Monitor prints with VIDOUT, without the Control-S pause.
;; Keeps: A, Y
COUTZ:
.if ENHANCED
    pha                             ; $FDF6

COUTZ_1:
.endif
    sty YSAV1                       ; $FDF7 original $FDF6
.if ENHANCED
    tay                             ; $FDF9
.else
    pha                             ; $FDF8
.if MONITOR = MONITOR_II
    jsr VIDOUT                      ; $FDF9
.else
    jsr VIDWAIT                     ; $FDF9
.endif
.endif
    pla                             ; $FDFA original $FDFC
.if ENHANCED
    jmp CLREOP_1                    ; $FDFB
    .byte $EA, $EA                  ; $FDFE
.else
    ldy YSAV1                       ; $FDFD
    rts                             ; $FDFF
.endif

;; Monitor command line: counts down the examine-on-return line (part of the blank handler).
BL1:
    dec YSAV                        ; $FE00
    beq XAM8                        ; $FE02

;; Monitor command line: a blank or colon after a number. After a colon, stores the number at A3 and
;; advances A3.
BLANK:
    dex                             ; $FE04
    bne SETMDZ                      ; $FE05
    cmp #':'                        ; $FE07
    bne XAMPM                       ; $FE09

STOR:
    sta MODE                        ; $FE0B
    lda A2L                         ; $FE0D
    sta (A3L),y                     ; $FE0F
    inc A3L                         ; $FE11
    bne RTS5                        ; $FE13
    inc A3H                         ; $FE15

RTS5:
    rts                             ; $FE17

;; Monitor command line: sets MODE from the command character (".", ":", "+", "-").
SETMODE:
    ldy YSAV                        ; $FE18
    lda $01FF,y                     ; $FE1A

;; Sets MODE from A.
SETMDZ:
    sta MODE                        ; $FE1D
    rts                             ; $FE1F

;; Monitor < command: copies A2 to A4 and A5, the destination of MOVE and VFY.
LT:
    ldx #$01                        ; $FE20

;; Copies A2 to A4 and A5 (from LT).
LT2:
    lda A2L,x                       ; $FE22
    sta A4L,x                       ; $FE24
    sta A5L,x                       ; $FE26
    dex                             ; $FE28
    bpl LT2                         ; $FE29
    rts                             ; $FE2B

;; Monitor M command: copies A1-A2 to A4.
MOVE:
    lda (A1L),y                     ; $FE2C
    sta (A4L),y                     ; $FE2E
    jsr NXTA4                       ; $FE30
    bcc MOVE                        ; $FE33
    rts                             ; $FE35

;; Monitor V command: compares A1-A2 with the memory at A4, printing each difference as
;; "AAAA-xx (yy)".
VFY:
    lda (A1L),y                     ; $FE36
    cmp (A4L),y                     ; $FE38
    beq VFY_1                       ; $FE3A
    jsr PRA1                        ; $FE3C
    lda (A1L),y                     ; $FE3F
    jsr PRBYTE                      ; $FE41
    lda #' '                        ; $FE44
    jsr COUT                        ; $FE46
    lda #'('                        ; $FE49
    jsr COUT                        ; $FE4B
    lda (A4L),y                     ; $FE4E
    jsr PRBYTE                      ; $FE50
    lda #')'                        ; $FE53
    jsr COUT                        ; $FE55

VFY_1:
    jsr NXTA4                       ; $FE58

VFYOK:
    bcc VFY                         ; $FE5B
    rts                             ; $FE5D

;; Monitor L command: disassembles 20 instructions from A1 (or the current PC).
LIST:
    jsr A1PC                        ; $FE5E
    lda #$14                        ; $FE61

LIST2:
    pha                             ; $FE63
    jsr INSTDSP                     ; $FE64
    jsr PCADJ                       ; $FE67
    sta PCL                         ; $FE6A
    sty PCH                         ; $FE6C
    pla                             ; $FE6E
    sec                             ; $FE6F
    sbc #$01                        ; $FE70
    bne LIST2                       ; $FE72
    rts                             ; $FE74

;; Copies A1 to PCL/PCH when the command gave an address (X is not zero).
A1PC:
    txa                             ; $FE75
    beq A1PCRTS                     ; $FE76

A1PCLP:
    lda A1L,x                       ; $FE78
    sta PCL,x                       ; $FE7A
    dex                             ; $FE7C
    bpl A1PCLP                      ; $FE7D

A1PCRTS:
    rts                             ; $FE7F

;; Sets inverse text: INVFLG = $3F.
SETINV:
    ldy #$3F                        ; $FE80
    bne SETIFLG                     ; $FE82

;; Sets normal text: INVFLG = $FF.
SETNORM:
    ldy #$FF                        ; $FE84

SETIFLG:
    sty INVFLG                      ; $FE86
    rts                             ; $FE88

;; Sets the input hook to the keyboard (KEYIN).
SETKBD:
    lda #$00                        ; $FE89

;; Sets the input hook to a slot.
;; In: A = slot (0 for the keyboard)
INPORT:
    sta A2L                         ; $FE8B

INPRT:
    ldx #KSWL                       ; $FE8D
    ldy #<KEYIN                     ; $FE8F
    bne IOPRT                       ; $FE91

;; Sets the output hook to the screen (COUT1).
SETVID:
    lda #$00                        ; $FE93

;; Sets the output hook to a slot.
;; In: A = slot (0 for the screen)
OUTPORT:
    sta A2L                         ; $FE95

OUTPRT:
    ldx #CSWL                       ; $FE97
    ldy #<COUT1                     ; $FE99

IOPRT:
    lda A2L                         ; $FE9B
    and #$0F                        ; $FE9D
.if ENHANCED
    beq IOPRT_1                     ; $FE9F
.else
    beq IOPRT1                      ; $FE9F
.endif
    ora #$C0                        ; $FEA1
    ldy #$00                        ; $FEA3

IOPRT_1:
.if .not ENHANCED
    beq IOPRT2                      ; $FEA5

IOPRT1:
    lda #>COUT1                     ; $FEA7

IOPRT2:
.endif
    sty LOC0,x                      ; $FEA5 original $FEA9
    sta LOC1,x                      ; $FEA7 original $FEAB
.if ENHANCED
    ldy #$0E                        ; $FEA9
    jmp GOTOCX                      ; $FEAB
.else
    rts                             ; $FEAD
.endif
    .byte $EA                       ; $FEAE

CKSUMFIX:
.if ENHANCED
    .byte $00                       ; $FEAF
.elseif MONITOR = MONITOR_IIE
    .byte $D1                       ; $FEAF
.else
    .byte $EA                       ; $FEAF
.endif

;; Monitor Control-B: starts AppleSoft (cold).
;;
;; On an Apple II, $E000 starts whichever BASIC its ROMs hold, Integer BASIC or AppleSoft.
XBASIC:
    jmp BASIC                       ; $FEB0

;; Monitor Control-C: continues AppleSoft (warm).
BASCONT:
    jmp BASIC2                      ; $FEB3

;; Monitor G command: restores the registers and runs the program at A1 (or the current PC).
GO:
    jsr A1PC                        ; $FEB6
    jsr RESTORE                     ; $FEB9
    jmp (PCL)                       ; $FEBC

;; Monitor Control-E: shows the registers.
REGZ:
    jmp REGDSP                      ; $FEBF

;; Monitor T command: tracing was removed on the IIe; does nothing.
;;
;; The Autostart Monitor does nothing here either. In the Apple II Monitor, T steps the program
;; without end: it moves YSAV back onto the T, so that after each step (STEPZ, which it falls into)
;; the command line performs the T again. A BRK in the program, or reset, stops it.
TRACE:
.if MONITOR = MONITOR_II
    dec YSAV                        ; $FEC2
.else
    rts                             ; $FEC2
    .byte $EA                       ; $FEC3
.endif

;; Monitor S command: single-stepping was removed on the IIe; does nothing.
;;
;; The Autostart Monitor does nothing here either. In the Apple II Monitor, S runs one instruction of
;; the program, at A1 when the command gives an address (A1PC), and shows it and the registers (STEP).
STEPZ:
.if MONITOR = MONITOR_II
    jsr A1PC                        ; $FEC4
    jmp STEP                        ; $FEC7
.else
    rts                             ; $FEC4
.if MONITOR = MONITOR_AUTOSTART
    .res 5, $EA                     ; $FEC5 unused; the S command's Control-Y entry runs on into USR
.else

;; Enhanced IIe: switches slot ROM back in and returns (internal firmware calls end here).
;; The original IIe has unused bytes here.
SLOTRTS:
.if ENHANCED
    sta SETSLOTCXROM                ; $FEC5
.else
    .byte "Bry"                     ; $FEC5 with the next two bytes, "Bryan"
.endif

SLOTRTS_1:
.if ENHANCED
    rts                             ; $FEC8
    .byte $EA                       ; $FEC9
.else
    .byte "an"                      ; $FEC8
.endif
.endif
.endif

;; Monitor Control-Y: jumps to the user routine at USRADR ($03F8).
USR:
    jmp USRADR                      ; $FECA

;; Monitor W command: writes A1-A2 to cassette.
;; The Enhanced IIe calls the cassette routine in internal ROM.
WRITE:
    lda #$40                        ; $FECD
.if ENHANCED
    sta SETINTCXROM                 ; $FECF
    jsr WRITETAPE                   ; $FED2
    beq READ_1                      ; $FED5

;; Enhanced IIe: prints the address of each place from A1 to A2 that holds the byte in A4L,
;; followed by A4H when A4H is not zero.
MEMFIND:
    ldy #$01                        ; $FED7
    lda A4H                         ; $FED9
    beq MEMFIND_1                   ; $FEDB
    cmp (A1L),y                     ; $FEDD
    bne MEMFIND_2                   ; $FEDF
.else
    jsr HEADR                       ; $FECF
    ldy #$27                        ; $FED2

WR1:
    ldx #$00                        ; $FED4
    eor (A1L,x)                     ; $FED6
    pha                             ; $FED8
    lda (A1L,x)                     ; $FED9
    jsr WRBYTE                      ; $FEDB
    jsr NXTA1                       ; $FEDE
.endif

MEMFIND_1:
.if ENHANCED
    dey                             ; $FEE1
    lda A4L                         ; $FEE2
    cmp (A1L),y                     ; $FEE4
    bne MEMFIND_2                   ; $FEE6
    jsr PRA1                        ; $FEE8
.else
    ldy #$1D                        ; $FEE1
    pla                             ; $FEE3
    bcc WR1                         ; $FEE4
    ldy #$22                        ; $FEE6
    jsr WRBYTE                      ; $FEE8
.endif

MEMFIND_2:
.if ENHANCED
    jsr NXTA1                       ; $FEEB
    bcc MEMFIND                     ; $FEEE
.else
    beq BELL                        ; $FEEB

WRBYTE:
    ldx #$10                        ; $FEED

WRBYT2:
    asl a                           ; $FEEF
    jsr WRBIT                       ; $FEF0
    bne WRBYT2                      ; $FEF3
.endif
    rts                             ; $FEF0 original $FEF5
.if ENHANCED

;; Enhanced IIe: enters the mini-assembler in the internal firmware (function $0D).
MINIASM:
    ldy #$0D                        ; $FEF1
    jsr GOTOCX                      ; $FEF3
.endif

;; Monitor command line: a carriage return ends the line; examines the next lines and returns to the
;; prompt.
CRMON:
    jsr BL1                         ; $FEF6
    pla                             ; $FEF9
    pla                             ; $FEFA
    bne MONZ                        ; $FEFB

;; Monitor R command: reads cassette data into A1-A2, then beeps, or prints ERR on a checksum error.
;; The Enhanced IIe calls the cassette routine in internal ROM.
READ:
.if ENHANCED
    sta SETINTCXROM                 ; $FEFD
    jsr READTAPE                    ; $FF00

READ_1:
    sta SETSLOTCXROM                ; $FF03
    beq BELL                        ; $FF06
    bne PRERR                       ; $FF08

;; Enhanced IIe: the title, "Apple //e", copied by APPLEII.
TITLE2E:
    .byte "Apple //e"               ; $FF0A

;; Enhanced IIe: Monitor input: skips blanks, returning the next character.
SKIPBLNK:
    jsr UPMON                       ; $FF13
    cmp #' '                        ; $FF16
    beq SKIPBLNK                    ; $FF18
    rts                             ; $FF1A
.else
    jsr RD2BIT                      ; $FEFD
    lda #$16                        ; $FF00
    jsr HEADR                       ; $FF02
    sta MASK                        ; $FF05
    jsr RD2BIT                      ; $FF07

RD2:
    ldy #$24                        ; $FF0A
    jsr RDBIT                       ; $FF0C
    bcs RD2                         ; $FF0F
    jsr RDBIT                       ; $FF11
    ldy #$3B                        ; $FF14

RD3:
    jsr RDBYTE                      ; $FF16
    sta (A1L,x)                     ; $FF19
.endif

RD3_1:
.if ENHANCED
    bcs DIG                         ; $FF1B
    cmp #' '                        ; $FF1D
    bne RESTR1_1                    ; $FF1F
    lda IN,y                        ; $FF21
    ldx #$07                        ; $FF24
    cmp #KEY_CR                     ; $FF26
    beq GETNUM                      ; $FF28
    iny                             ; $FF2A
    bne NXTBIT                      ; $FF2B
.else
    eor MASK                        ; $FF1B
    sta MASK                        ; $FF1D
    jsr NXTA1                       ; $FF1F
    ldy #$35                        ; $FF22
    bcc RD3                         ; $FF24
    jsr RDBYTE                      ; $FF26
    cmp MASK                        ; $FF29
    beq BELL                        ; $FF2B
.endif

;; Prints "ERR" and beeps.
PRERR:
    lda #'E'                        ; $FF2D
    jsr COUT                        ; $FF2F
    lda #'R'                        ; $FF32
    jsr COUT                        ; $FF34
    jsr COUT                        ; $FF37

;; Beeps by printing Control-G.
BELL:
    lda #KEY_BELL                   ; $FF3A
    jmp COUT                        ; $FF3C

;; Restores A, X, Y and P from A5H, XREG, YREG and STATUS.
RESTORE:
    lda STATUS                      ; $FF3F
    pha                             ; $FF41
    lda A5H                         ; $FF42

RESTR1:
    ldx XREG                        ; $FF44
    ldy YREG                        ; $FF46
    plp                             ; $FF48

RESTR1_1:
    rts                             ; $FF49

;; Saves A, X, Y, P and S in A5H, XREG, YREG, STATUS and SPNT, and clears decimal mode.
SAVE:
    sta A5H                         ; $FF4A

SAV1:
    stx XREG                        ; $FF4C
    sty YREG                        ; $FF4E
    php                             ; $FF50
    pla                             ; $FF51
    sta STATUS                      ; $FF52
    tsx                             ; $FF54
    stx SPNT                        ; $FF55
    cld                             ; $FF57
    rts                             ; $FF58

;; The older reset sequence, without the IIe's power-up checks: normal video, text, the screen and
;; keyboard hooks, then the Monitor.
;;
;; It is the Apple II Monitor's reset handler (RESETVEC), named RESET in its listing.
OLDRST:
    jsr SETNORM                     ; $FF59
    jsr INIT                        ; $FF5C
    jsr SETVID                      ; $FF5F
    jsr SETKBD                      ; $FF62

;; Enters the Monitor with a beep.
MON:
    cld                             ; $FF65
    jsr BELL                        ; $FF66

;; Enters the Monitor: prompts with "*", reads a command line and performs its commands.
MONZ:
    lda #'*'                        ; $FF69
    sta PROMPT                      ; $FF6B
    jsr GETLNZ                      ; $FF6D
    jsr ZMODE                       ; $FF70

;; Monitor command line: reads the next number and command character, and performs the command.
NXTITM:
    jsr GETNUM                      ; $FF73
    sty YSAV                        ; $FF76
    ldy #SUBTBL-CHRTBL              ; $FF78

CHRSRCH:
    dey                             ; $FF7A
    bmi MON                         ; $FF7B
    cmp CHRTBL,y                    ; $FF7D
    bne CHRSRCH                     ; $FF80
    jsr TOSUB                       ; $FF82
    ldy YSAV                        ; $FF85
    jmp NXTITM                      ; $FF87

;; Shifts a hex digit into A2.
DIG:
    ldx #$03                        ; $FF8A
    asl a                           ; $FF8C
    asl a                           ; $FF8D
    asl a                           ; $FF8E
    asl a                           ; $FF8F

;; Shifts A2 left one bit, taking the bit from A.
NXTBIT:
    asl a                           ; $FF90
    rol A2L                         ; $FF91
    rol A2H                         ; $FF93
    dex                             ; $FF95
    bpl NXTBIT                      ; $FF96

;; Copies A2 to A1 and A3, unless a mode (".", ":", "+", "-") is pending.
NXTBAS:
    lda MODE                        ; $FF98
    bne NXTBS2                      ; $FF9A
    lda A2H,x                       ; $FF9C
    sta A1H,x                       ; $FF9E
    sta A3H,x                       ; $FFA0

;; Continues the copy in NXTBAS.
NXTBS2:
    inx                             ; $FFA2
    beq NXTBAS                      ; $FFA3
    bne NXTCHR                      ; $FFA5

;; Reads a hex number from IN at Y into A2.
;; Out: A = the next non-digit character (encoded for CHRTBL); Y after it
GETNUM:
    ldx #$00                        ; $FFA7
    stx A2L                         ; $FFA9
    stx A2H                         ; $FFAB

;; Reads the next character of a number.
NXTCHR:
.if ENHANCED
    jsr UPMON                       ; $FFAD
    nop                             ; $FFB0
.else
    lda IN,y                        ; $FFAD
    iny                             ; $FFB0
.endif
    eor #'0'                        ; $FFB1
    cmp #$0A                        ; $FFB3
    bcc DIG                         ; $FFB5
    adc #$88                        ; $FFB7
    cmp #$FA                        ; $FFB9
.if ENHANCED
    jmp RD3_1                       ; $FFBB
.else
    bcs DIG                         ; $FFBB
    rts                             ; $FFBD
.endif

;; Performs the Monitor command at CHRTBL,Y by pushing its handler's address minus one and
;; returning to it.
;; Out: A = MODE
TOSUB:
    lda #COMMAND_PAGE               ; $FFBE
    pha                             ; $FFC0
    lda SUBTBL,y                    ; $FFC1
    pha                             ; $FFC4
    lda MODE                        ; $FFC5

;; Clears MODE.
ZMODE:
    ldy #$00                        ; $FFC7
    sty MODE                        ; $FFC9
    rts                             ; $FFCB

;; The Monitor's commands: each key and the routine that performs it.
;; CHRTBL holds the keys as GETNUM returns them, (key EOR $B0) + $89, and SUBTBL the low byte of
;; each handler's address minus one; TOSUB pushes the page, COMMAND_PAGE, and returns to it. NXTITM
;; searches from the end, so a later entry for the same key wins.
COMMAND_PAGE = $FE
.set COMMANDS, 0

.macro COMMAND key, handler
    .ident(.sprintf("COMMAND_KEY_%d", COMMANDS)) = (((key) ^ $B0) + $89) & $FF
    .ident(.sprintf("COMMAND_SUB_%d", COMMANDS)) = <(handler - 1)
    .assert >(handler - 1) = COMMAND_PAGE, "A Monitor command handler must follow the first byte of page $FE."
    .set COMMANDS, COMMANDS + 1
.endmacro

    COMMAND KEY_CTRL_C, BASCONT     ; continue BASIC
    COMMAND KEY_CTRL_Y, USR         ; the user's routine
    COMMAND KEY_CTRL_E, REGZ        ; show the registers
.if ENHANCED
    COMMAND '!', MINIASM            ; the mini-assembler
.elseif MONITOR = MONITOR_II
    COMMAND 'T', TRACE              ; trace
.else
    COMMAND KEY_CTRL_Y, TRACE       ; left from the T command; the later Control-Y entries win
.endif
    COMMAND 'V', VFY                ; verify
    COMMAND KEY_CTRL_K, INPRT       ; IN#
.if ENHANCED
    COMMAND 'S', MEMFIND            ; search
.elseif MONITOR = MONITOR_II
    COMMAND 'S', STEPZ              ; step
.elseif MONITOR = MONITOR_AUTOSTART
    COMMAND KEY_CTRL_Y, STEPZ + 1   ; left from the S command; this one wins, and runs into USR
.else
    COMMAND KEY_CTRL_Y, SLOTRTS     ; left from the S command; this one wins
.endif
    COMMAND KEY_CTRL_P, OUTPRT      ; PR#
    COMMAND KEY_CTRL_B, XBASIC      ; start BASIC
    COMMAND '-', SETMODE            ; subtract
    COMMAND '+', SETMODE            ; add
    COMMAND 'M', MOVE               ; move
    COMMAND '<', LT                 ; destination
    COMMAND 'N', SETNORM            ; normal text
    COMMAND 'I', SETINV             ; inverse text
    COMMAND 'L', LIST               ; list (disassemble)
    COMMAND 'W', WRITE              ; write to cassette
    COMMAND 'G', GO                 ; go
    COMMAND 'R', READ               ; read from cassette
    COMMAND ':', SETMODE            ; store
    COMMAND '.', SETMODE            ; range
    COMMAND KEY_CR, CRMON           ; end of the line
    COMMAND ' ', BLANK              ; separator

CHRTBL:
.repeat COMMANDS, index
    .byte .ident(.sprintf("COMMAND_KEY_%d", index))
.endrepeat

SUBTBL:
.repeat COMMANDS, index
    .byte .ident(.sprintf("COMMAND_SUB_%d", index))
.endrepeat

;; The 6502's NMI vector: $03FB.
NMIVEC:
    .word NMI                       ; $FFFA

;; The 6502's reset vector: RESET.
;;
;; The Apple II Monitor's points at OLDRST, which its listing calls RESET.
RESETVEC:
.if MONITOR = MONITOR_II
    .word OLDRST                    ; $FFFC
.else
    .word RESET                     ; $FFFC
.endif

;; The 6502's IRQ and BRK vector: IRQ on the original IIe, the internal firmware at $C3FA on the
;; Enhanced IIe.
IRQVEC:
.if ENHANCED
    .word IRQHANDLER                ; $FFFE
.else
    .word IRQ                       ; $FFFE
.endif
