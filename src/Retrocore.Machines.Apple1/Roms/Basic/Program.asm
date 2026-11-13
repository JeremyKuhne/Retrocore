;; APPLE-1 BASIC: DECIMAL OUTPUT, FINDING LINES, SCR AND CLR ($E51B-$E5CB)
;;
;; PRDEC, which prints line numbers and values in decimal; the search for a line by its number, which GOTO, GOSUB,
;; LIST, DEL and line entry use; and SCR and CLR, which discard the program and the variables.
;;
;; Part of Basic.asm; it follows Tokenizer.asm, at $E51B.

;; Prints a 16-bit number in decimal, as five places with the leading zeros printed as <LEADZR>.
;;
;; Each place is found by subtracting its power of ten (<NUMLOW>, <NUMHI>) as many times as it goes. While AUTO
;; mode is on, each character printed is also stored in <IN> at Y, so the line number the AUTO prompt shows becomes
;; the start of the line typed.
;; In: A = the high byte, X = the low byte, LEADZR = 0 to drop leading zeros, $A0 to print them as blanks
;; Out: X = $FF
;; Uses: A, PCON, CHAR, LEADBL, Y (in AUTO mode)
;; See: <LEADZR>, <WARM>
PRDEC:
    sta PCON+1                      ; $E51B
    stx PCON                        ; $E51D
    ldx #$04                        ; $E51F from the ten thousands down
    stx LEADBL                      ; $E521 bit 7 clear: no digit printed yet

PRDEC_1:
    lda #'0'                        ; $E523
    sta CHAR                        ; $E525
@Loop2:
    lda PCON                        ; $E527
    cmp NUMLOW,x                    ; $E529
    lda PCON+1                      ; $E52C
    sbc NUMHI,x                     ; $E52E
    bcc PRDEC_2                     ; $E531
    sta PCON+1                      ; $E533
    lda PCON                        ; $E535
    sbc NUMLOW,x                    ; $E537
    sta PCON                        ; $E53A
    inc CHAR                        ; $E53C
    bne @Loop2                      ; $E53E

;; One place is done: prints its digit, or a leading zero as <LEADZR> says.
PRDEC_2:
    lda CHAR                        ; $E540
    inx                             ; $E542
    dex                             ; $E543
    beq PRDEC5                      ; $E544 the units: always printed
    cmp #'0'                        ; $E546
    beq PRDEC_3                     ; $E548
    sta LEADBL                      ; $E54A a digit that is not 0: from here on all are printed

PRDEC_3:
    bit LEADBL                      ; $E54C
    bmi PRDEC5                      ; $E54E a digit has been printed
    lda LEADZR                      ; $E550
    beq PRDEC6                      ; $E552 a leading zero, not printed

;; Prints the character in A, and copies it into <IN> in AUTO mode.
PRDEC5:
    jsr COUT                        ; $E554
    bit AUTOFLAG                    ; $E557
    bpl PRDEC6                      ; $E559
    sta IN,y                        ; $E55B
    iny                             ; $E55E

;; The next place.
PRDEC6:
    dex                             ; $E55F
    bpl PRDEC_1                     ; $E560
    rts                             ; $E562

;; The low bytes of the powers of ten <PRDEC> subtracts: 1, 10, 100, 1000 and 10000.
;; See: <NUMHI>
NUMLOW:
    .byte 1                         ; $E563
    .byte 10                        ; $E564
    .byte 100                       ; $E565
    .byte $E8                       ; $E566
    .byte $10                       ; $E567

;; The high bytes of the powers of ten, as <NUMLOW>.
NUMHI:
    .byte 0                         ; $E568
    .byte 0                         ; $E569
    .byte 0                         ; $E56A
    .byte $03                       ; $E56B
    .byte $27                       ; $E56C

;; Finds the first line whose number is at least ACC, searching from the start of the program.
;;
;; The two comparisons of a line's number use the carry from the one before, so each is off by one in the way
;; that matters: the first returns with carry set for a number above ACC, the second with carry clear for ACC
;; itself.
;; In: ACC = the line number
;; Out: P2 = the line found, or <HIMEM> if there is none, carry = clear if its number is ACC, set if not, P3 = the
;;   line after P2 when the number is ACC, otherwise P2
;; Uses: A, Y
;; Entry: FINDP3POP = searches from P3 and takes an entry off the noun stack (INX), FINDFROMP3 = searches from P3
FINDLINE:
    lda PP                          ; $E56D
    sta P3                          ; $E56F
    lda PP+1                        ; $E571
    sta P3+1                        ; $E573

FINDP3POP:
    inx                             ; $E575

FINDFROMP3:
    lda P3+1                        ; $E576
    sta P2+1                        ; $E578
    lda P3                          ; $E57A
    sta P2                          ; $E57C
    cmp HIMEM                       ; $E57E
    lda P2+1                        ; $E580
    sbc HIMEM+1                     ; $E582
    bcs FINDLINE_2                  ; $E584 past the last line: carry set
    ldy #$01                        ; $E586 carry is clear: the line's number - ACC - 1
    lda (P2),y                      ; $E588
    sbc ACC                         ; $E58A
    iny                             ; $E58C
    lda (P2),y                      ; $E58D
    sbc ACC+1                       ; $E58F
    bcs FINDLINE_2                  ; $E591 above ACC
    ldy #$00                        ; $E593
    lda P3                          ; $E595 step P3 to the next line
    adc (P2),y                      ; $E597
    sta P3                          ; $E599
    bcc FINDLINE_1                  ; $E59B
    inc P3+1                        ; $E59D
    clc                             ; $E59F

FINDLINE_1:
    iny                             ; $E5A0
    lda ACC                         ; $E5A1 carry is clear: ACC - the number - 1
    sbc (P2),y                      ; $E5A3
    iny                             ; $E5A5
    lda ACC+1                       ; $E5A6
    sbc (P2),y                      ; $E5A8
    bcs FINDFROMP3                  ; $E5AA below ACC: keep looking; equal: carry clear

FINDLINE_2:
    rts                             ; $E5AC

;; SCR (token $0B): leaves AUTO mode and discards the program, then falls into CLR.
;; See: <CLR>
NEW:
    lsr AUTOFLAG                    ; $E5AD
    lda HIMEM                       ; $E5AF
    sta PP                          ; $E5B1
    lda HIMEM+1                     ; $E5B3
    sta PP+1                        ; $E5B5

;; CLR (token $0C): discards the variables, and the FOR and GOSUB stacks.
;;
;; It also clears <SYNPAG>, whose low byte must be 0, and $1D.
;; Uses: A
;; Keeps: X, Y
;; See: <NEW>, <RUN>
CLR:
    lda LOMEM                       ; $E5B7
    sta PV                          ; $E5B9
    lda LOMEM+1                     ; $E5BB
    sta PV+1                        ; $E5BD
    lda #$00                        ; $E5BF
    sta FORNDX                      ; $E5C1
    sta GOSUBNDX                    ; $E5C3
    sta SYNPAG                      ; $E5C5
    lda #$00                        ; $E5C7
    sta $1D                         ; $E5C9 $1D: no other code in BASIC reads it
    rts                             ; $E5CB
