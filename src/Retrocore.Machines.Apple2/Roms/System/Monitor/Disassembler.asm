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
