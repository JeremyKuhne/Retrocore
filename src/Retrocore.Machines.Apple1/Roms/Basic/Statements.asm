;; APPLE-1 BASIC: PRINTING STRINGS, MEMORY AND MORE STATEMENTS ($EE00-$EFFF)
;;
;; The routines of many tokens: PRINT of a string, LEN(, COLOR= and PLOT's comma, HIMEM= and LOMEM=, CALL, PEEK,
;; POKE, division, DIM of numeric arrays and array elements, RND, INPUT of strings and the start of INPUT with a
;; prompt, AND and OR's common part, and RUN; with GETBYTE, which most of them use, the error messages' printer, the
;; division loop and the cold start's memory setup.
;;
;; A statement with two values, such as POKE, has a routine for its keyword and one for its comma. The comma's runs
;; first and does nothing, leaving both values on the noun stack for the keyword's routine.
;;
;; Part of Basic.asm; it follows SyntaxTable.asm, at $EE00.

;; PRINT's comma before a string (token $48): moves to the next tab stop, then prints the string.
;; See: <NEXTTAB>, <PRINTSTR>
COMMA_PRSTR:
    jsr NEXTTAB                     ; $EE00

;; PRINT of a string (token $61), and the semicolon before one (token $45): prints the string's range.
;;
;; The line then owes a return (<CRFLAG>).
;; In: X = the noun stack, its top entries the string's range and address
;; Out: X = the noun stack, both popped
;; Uses: A, Y, AUX
PRINTSTR:
    inx                             ; $EE03
    inx                             ; $EE04
    lda NOUNSTKL-1,x                ; $EE05
    sta AUX                         ; $EE07
    lda NOUNSTKH-1,x                ; $EE09
    sta AUX+1                       ; $EE0B
    ldy NOUNSTKL-2,x                ; $EE0D Y = the first character's index
@Loop:
    tya                             ; $EE0F
    cmp NOUNSTKH-2,x                ; $EE10
    bcs SETCRFLAG                   ; $EE12 the end of the range
    lda (AUX),y                     ; $EE14
    jsr COUT                        ; $EE16
    iny                             ; $EE19
    jmp @Loop                       ; $EE1A

;; Sets <CRFLAG>: the line owes a return.
SETCRFLAG:
    lda #$FF                        ; $EE1D
    sta CRFLAG                      ; $EE1F
    rts                             ; $EE21

;; LEN( (token $3B): replaces a string with its length, the size of its range.
;; In: X = the noun stack, its top entries the string's range and address
;; Out: X = the noun stack, its top entry the length
LEN:
    inx                             ; $EE22 the result replaces the address entry
    lda #$00                        ; $EE23
    sta NOUNSTKH,x                  ; $EE25
    sta NOUNSTKC,x                  ; $EE27
    lda NOUNSTKH-1,x                ; $EE29
    sec                             ; $EE2B
    sbc NOUNSTKL-1,x                ; $EE2C
    sta NOUNSTKL,x                  ; $EE2E
    jmp LEFT_PAREN                  ; $EE30 then end like a left parenthesis
    .byte $FF                       ; $EE33 an unused byte

;; Takes a number from the noun stack that must fit in a byte.
;; In: X = the noun stack
;; Out: A = the number, ACC = the number, X = one entry higher, Y = 0
;; Errors: >255 if the number is above 255 or negative
;; See: <GET16BIT>
GETBYTE:
    jsr GET16BIT                    ; $EE34
    lda ACC+1                       ; $EE37
    bne HI255ERR                    ; $EE39
    lda ACC                         ; $EE3B
    rts                             ; $EE3D

;; PLOT's comma (token $68): checks a row and a column, the start of a graphics statement BASIC never finished.
;;
;; It draws nothing. The column it checks is <TXTNDX>, which holds whatever the tokenizer left there.
;; In: X = the noun stack, its top entry the row
;; Errors: RANGE if the row is 48 or more, or the column 40 or more
COMMA_PLOT:
    jsr GETBYTE                     ; $EE3E
    ldy TXTNDX                      ; $EE41
    cmp #48                         ; $EE43
    bcs RANGERR                     ; $EE45
    cpy #40                         ; $EE47
    bcs RANGERR                     ; $EE49
    rts                             ; $EE4B
    nop                             ; $EE4C
    nop                             ; $EE4D

;; COLOR= (token $66): takes a color, and does nothing with it.
;; In: X = the noun stack, its top entry the color
;; Errors: >255
COLOR_EQ:
    jsr GETBYTE                     ; $EE4E
    rts                             ; $EE51
    nop                             ; $EE52

;; The end of HIMEM=: sets <HIMEM> to the new value in <ACC>, and <PP> to where the program now starts, in <NEWPP>.
;; Keeps: X
;; See: <VHIMEM>, <MOVEPROG>
SETHIMEMPP:
    txa                             ; $EE53
    ldx #$01                        ; $EE54

SETHIMEMPP_1:
    ldy ACC,x                       ; $EE56
    sty HIMEM,x                     ; $EE58
    ldy NEWPP,x                     ; $EE5A
    sty PP,x                        ; $EE5C
    dex                             ; $EE5E
    beq SETHIMEMPP_1                ; $EE5F
    tax                             ; $EE61
    rts                             ; $EE62

;; The >255 error.
;; Entry: JmpERRMESS3 = an error with the message offset in Y
HI255ERR:
    ldy #<ErrMsg15                  ; $EE63

JmpERRMESS3:
    jmp ERRMESS                     ; $EE65

;; The RANGE error.
RANGERR:
    ldy #<ErrMsg16                  ; $EE68
    bne JmpERRMESS3                 ; $EE6A

;; Divides two numbers from the noun stack: the lower by the top one.
;;
;; <MDARGS> takes both as positive values and keeps the sign. Each of the 16 steps shifts the next bit of the dividend
;; into the remainder and subtracts the divisor where it fits, setting the quotient's bit.
;; In: X = the noun stack: the dividend, then the divisor on top
;; Out: ACC = the quotient's magnitude, P3 = the remainder's magnitude, P2+1 = the sign, Y = 0, X = both popped
;; Errors: >32767 for a division by 0
;; See: <DIVIDE>, <MOD>, <MultEnd>
DIVMOD:
    jsr MDARGS                      ; $EE6C
    lda AUX                         ; $EE6F
    bne DIVMOD_1                    ; $EE71
    lda AUX+1                       ; $EE73
    bne DIVMOD_1                    ; $EE75
    jmp Err32767                    ; $EE77

;; One step: the dividend and the remainder shift left together.
DIVMOD_1:
    asl ACC                         ; $EE7A
    rol ACC+1                       ; $EE7C
    rol P3                          ; $EE7E
    rol P3+1                        ; $EE80
    lda P3                          ; $EE82
    cmp AUX                         ; $EE84 does the divisor fit in the remainder?
    lda P3+1                        ; $EE86
    sbc AUX+1                       ; $EE88
    bcc DIVMOD_2                    ; $EE8A
    sta P3+1                        ; $EE8C
    lda P3                          ; $EE8E
    sbc AUX                         ; $EE90
    sta P3                          ; $EE92
    inc ACC                         ; $EE94 yes: a 1 in the quotient

DIVMOD_2:
    dey                             ; $EE96
    bne DIVMOD_1                    ; $EE97
    rts                             ; $EE99
    .byte $FF, $FF, $FF, $FF, $FF, $FF ; $EE9A unused bytes

;; CALL (token $4D): calls the machine-language routine at the address.
;;
;; The routine returns to the interpreter with RTS. Negative numbers reach the top half of memory: CALL -225 enters
;; the Monitor at $FF1F (<WozMonitor:GETLINE>).
;; In: X = the noun stack, its top entry the address
CALL:
    jsr GET16BIT                    ; $EEA0
    jmp (ACC)                       ; $EEA3

;; Moves the program up for HIMEM=, a byte at a time from its top, until <HIMEM> passes <PP>.
;;
;; <HIMEM> and <NEWPP> step down together from the old and the new HIMEM; when the loop ends, <NEWPP> is where the
;; program now starts. HIMEM= enters at MOVEPROG_COPY, which first copies the byte at the old HIMEM itself.
;; In: HIMEM = the old HIMEM, NEWPP = the new HIMEM
;; Out: NEWPP = the program's new start
;; Uses: A, Y
;; See: <VHIMEM>, <SETHIMEMPP>
MOVEPROG:
    lda HIMEM                       ; $EEA6
    bne MOVEPROG_1                  ; $EEA8
    dec HIMEM+1                     ; $EEAA

MOVEPROG_1:
    dec HIMEM                       ; $EEAC

MOVEPROG_2:
    lda NEWPP                       ; $EEAE
    bne MOVEPROG_3                  ; $EEB0
    dec NEWPP+1                     ; $EEB2

MOVEPROG_3:
    dec NEWPP                       ; $EEB4

MOVEPROG_COPY:
    ldy #$00                        ; $EEB6
    lda (HIMEM),y                   ; $EEB8

MOVEPROG_4:
    sta (NEWPP),y                   ; $EEBA

MOVEPROG_5:
    lda PP                          ; $EEBC
    cmp HIMEM                       ; $EEBE
    lda PP+1                        ; $EEC0

MOVEPROG_6:
    sbc HIMEM+1                     ; $EEC2
    bcc MOVEPROG                    ; $EEC4
    jmp SETHIMEMPP                  ; $EEC6
    .byte $C9, $28                  ; $EEC9 unused bytes

;; A RANGE error if the carry is set; otherwise returns <TXTNDX> in A, with the number in A kept in Y.
;;
;; TAB, the array routines, HIMEM= and LOMEM= use it.
BcsRANGERR:
    bcs RANGERR                     ; $EECB
    tay                             ; $EECD
    lda TXTNDX                      ; $EECE
    rts                             ; $EED0
    nop                             ; $EED1
    nop                             ; $EED2

;; Prints an error: ***, the message at offset Y, then ERR and a return.
;; In: Y = the message's offset from <ErrMsg00>
;; See: <ERRMESS>, <ERRORMESS>
PRINTERR:
    tya                             ; $EED3
    tax                             ; $EED4
    ldy #<ErrMsg13                  ; $EED5
    jsr ERRORMESS                   ; $EED7
    txa                             ; $EEDA
    tay                             ; $EEDB
    jsr ERRORMESS                   ; $EEDC
    ldy #<ErrMsg14                  ; $EEDF
    jmp ERRORMESS                   ; $EEE1

;; Takes an array index from the noun stack and turns it into a size in bytes: index x 2.
;;
;; The doubling runs once more if bit 15 becomes set, so the carry catches a size of $8000 or more. So DIM A(10)
;; makes room for 10 elements, and an element's index runs from 1 to the size DIM gave.
;; In: X = the noun stack, its top entry the index
;; Out: ACC = the size, carry clear
;; Errors: RANGE for a size of $8000 or more, or of 0 (an index of 0)
;; Entry: DBLACC = doubles ACC
;; See: <DIMNUM>, <PAREN_ARRAY>
NDXSIZE:
    jsr GET16BIT                    ; $EEE4

DBLACC:
    asl ACC                         ; $EEE7
    rol ACC+1                       ; $EEE9
    bmi DBLACC                      ; $EEEB
    bcs BcsRANGERR                  ; $EEED
    bne NDXSIZE_1                   ; $EEEF
    cmp ACC                         ; $EEF1
    bcs BcsRANGERR                  ; $EEF3

NDXSIZE_1:
    rts                             ; $EEF5

;; PEEK (token $2E): replaces an address with the byte there.
;; In: X = the noun stack, its top entry the address
;; Out: X = the noun stack, its top entry the byte
PEEK:
    jsr GET16BIT                    ; $EEF6
    lda (ACC),y                     ; $EEF9
    sty NOUNSTKC-1,x                ; $EEFB
    jmp PUSHNOUN                    ; $EEFD

;; POKE (token $64): stores the value at the address, both on the noun stack.
;;
;; The tokens of PLOT and HLIN (tokens $67 and $69) point here too, and VLIN's ($6C), which no line produces.
;; In: X = the noun stack: the address, then the value on top
;; Errors: >255 if the value does not fit in a byte
;; See: <COMMA_POKE>
POKE:
    jsr GETBYTE                     ; $EF00
    lda ACC                         ; $EF03
    pha                             ; $EF05
    jsr GET16BIT                    ; $EF06
    pla                             ; $EF09
    sta (ACC),y                     ; $EF0A

;; POKE's comma (token $65): nothing to do, as <POKE> takes both numbers.
COMMA_POKE:
    rts                             ; $EF0C
    .byte $FF, $FF, $FF             ; $EF0D unused bytes

;; Division (token $15): replaces two numbers with the quotient, rounded toward 0.
;; In: X = the noun stack: the dividend, then the divisor on top
;; Out: X = the noun stack, its top entry the quotient
;; Errors: >32767 for a division by 0
;; See: <DIVMOD>, <MOD>
DIVIDE:
    jsr DIVMOD                      ; $EF10
    lda ACC                         ; $EF13
    sta P3                          ; $EF15
    lda ACC+1                       ; $EF17
    sta P3+1                        ; $EF19
    jmp MultEnd                     ; $EF1B

;; DIM of a numeric array (token $4F, and $44 after a comma): makes the newest variable's value 2 x (n + 1) bytes:
;; elements 0 to n.
;; In: X = the noun stack: the size n above the variable's address
;; See: <SETVARSIZE>, <DIMSTR>
DIMNUM:
    jsr NDXSIZE                     ; $EF1E
    jmp SETVARSIZE                  ; $EF21

;; An array element (token $2D): replaces an array's address and an index with the element's address.
;;
;; The element must lie below the address of the next variable, the end of the array: indexes run from 0 to the
;; size DIM gave. An array that was never DIMed has room for element 0 only.
;; In: X = the noun stack: the index above the array's address
;; Errors: RANGE for an index past the end, or below 0
;; See: <NDXSIZE>
PAREN_ARRAY:
    jsr NDXSIZE                     ; $EF24
    ldy NOUNSTKH,x                  ; $EF27
    lda NOUNSTKL,x                  ; $EF29
    adc #$FE                        ; $EF2B carry is clear: the address - 2, of the next variable's address
    bcs PAREN_ARRAY_1               ; $EF2D
    dey                             ; $EF2F

;; Adds the size to the array's address less 2 and checks it against the array's end.
PAREN_ARRAY_1:
    sta AUX                         ; $EF30
    sty AUX+1                       ; $EF32
    clc                             ; $EF34
    adc ACC                         ; $EF35 AUX + (index + 1) x 2: the element
    sta NOUNSTKL,x                  ; $EF37
    tya                             ; $EF39
    adc ACC+1                       ; $EF3A
    sta NOUNSTKH,x                  ; $EF3C
    ldy #$00                        ; $EF3E
    lda NOUNSTKL,x                  ; $EF40 below the next variable?
    cmp (AUX),y                     ; $EF42
    iny                             ; $EF44
    lda NOUNSTKH,x                  ; $EF45
    sbc (AUX),y                     ; $EF47
    bcs BcsRANGERR                  ; $EF49
    jmp LEFT_PAREN                  ; $EF4B

;; RND (token $2F): replaces n with a random number from 0 to n - 1 (from 0 to -(n - 1) for a negative n).
;;
;; The random state is <RNDL>/<RNDH>, which the keyboard routine has been counting up while it waited for keys. RND
;; returns the state, cleared of bit 15 and never 0, modulo n, then advances it 17 times as a shift register whose
;; new low bit is bits 14 and 13 exclusive-ORed.
;; In: X = the noun stack, its top entry n
;; Out: X = the noun stack, its top entry the random number
;; See: <MOD>
RND:
    jsr GET16BIT                    ; $EF4E
    lda RNDL                        ; $EF51
    jsr PUSHNOUN                    ; $EF53
    lda RNDH                        ; $EF56
    bne RND_1                       ; $EF58
    cmp RNDL                        ; $EF5A
    adc #$00                        ; $EF5C RNDH is 0: it becomes 1 if RNDL is 0 too, so the state is never 0

RND_1:
    and #$7F                        ; $EF5E
    sta RNDH                        ; $EF60
    sta NOUNSTKC,x                  ; $EF62
    ldy #$11                        ; $EF64

RND_2:
    lda RNDH                        ; $EF66
    asl a                           ; $EF68 bits 14 and 13: (RNDH x 2 + $40) has their exclusive-OR in bit 7
    clc                             ; $EF69
    adc #$40                        ; $EF6A
    asl a                           ; $EF6C
    rol RNDL                        ; $EF6D
    rol RNDH                        ; $EF6F
    dey                             ; $EF71
    bne RND_2                       ; $EF72
    lda ACC                         ; $EF74
    jsr PUSHNOUN                    ; $EF76
    lda ACC+1                       ; $EF79
    sta NOUNSTKC,x                  ; $EF7B
    jmp MOD                         ; $EF7D the state modulo n

;; HIMEM= (token $10): sets HIMEM, moving the program up with it.
;;
;; A new HIMEM below the old one is ignored, as the move only goes up: lower it after SCR, which erases the
;; program. The variables are kept.
;; In: X = the noun stack, its top entry the new HIMEM
;; See: <MOVEPROG>, <SETHIMEMPP>
VHIMEM:
    jsr GET16BIT                    ; $EF80
    ldy ACC                         ; $EF83
    cpy HIMEM                       ; $EF85
    lda ACC+1                       ; $EF87
    sbc HIMEM+1                     ; $EF89
    bcc JmpBcsRANGEERR              ; $EF8B below the old HIMEM: nothing to do (the carry is clear)
    sty NEWPP                       ; $EF8D
    lda ACC+1                       ; $EF8F
    sta NEWPP+1                     ; $EF91
    jmp MOVEPROG_COPY               ; $EF93

;; LOMEM= (token $11): sets LOMEM, which must be below the program, and erases the variables.
;; In: X = the noun stack, its top entry the new LOMEM
;; Errors: RANGE if it is not below <PP>
;; See: <CLR>
VLOMEM:
    jsr GET16BIT                    ; $EF96
    ldy ACC                         ; $EF99
    cpy PP                          ; $EF9B
    lda ACC+1                       ; $EF9D
    sbc PP+1                        ; $EF9F
    bcs JmpBcsRANGEERR              ; $EFA1
    sty LOMEM                       ; $EFA3
    lda ACC+1                       ; $EFA5
    sta LOMEM+1                     ; $EFA7
    jmp CLR                         ; $EFA9

;; A RANGE error if the carry is set; otherwise nothing.
JmpBcsRANGEERR:
    jmp BcsRANGERR                  ; $EFAC
    .byte $EA, $EA, $EA, $EA        ; $EFAF unused bytes
    .byte $20, $C9, $EF             ; $EFB3

;; INPUT of a string (token $52, and $26 after a comma): reads a line into the string variable.
;; In: X = the noun stack, its top entries the variable's range and address
;; See: <INPUTSTR>
INPUT_STRVAR:
    jsr INPUTSTR                    ; $EFB6
    jmp INLINEDONE                  ; $EFB9

;; INPUT with a prompt (token $53): prints the prompt string; the variables follow.
;;
;; It marks the input line as used up, so the first numeric variable asks for a line (<COMMA_INPUT>).
;; In: X = the noun stack, its top entries the prompt's range and address
INPUT_PROMPT:
    jsr PRINTSTR                    ; $EFBC

;; Marks the input line as used up: <TXTNDX> before the buffer, and $80, the INPUT rule's end token, at its start.
INLINEDONE:
    lda #$FF                        ; $EFBF
    sta TXTNDX                      ; $EFC1
    lda #$74                        ; $EFC3
    sta IN                          ; $EFC5
    rts                             ; $EFC8

;; Replaces the top two numbers with NOT of each, for AND and OR, leaving the lower one's in A.
;;
;; By De Morgan's laws, AND is NOT of (NOT a OR NOT b), and OR is NOT of (NOT a AND NOT b) (<VAND>, <VOR>).
;; Out: A = NOT of the lower number, 0 or 1, X = the noun stack at the lower one
;; Entry: NOTTOP = NOT of the top number only (IF), without moving X
NOTBOTH:
    jsr NOT                         ; $EFC9
    inx                             ; $EFCC

NOTTOP:
    jsr NOT                         ; $EFCD
    lda NOUNSTKL,x                  ; $EFD0
    rts                             ; $EFD2

;; Sets up memory for a 4K machine: LOMEM at $0800 and HIMEM at $1000, then erases the program.
;; See: <COLD>
SETMEM4K:
    lda #$00                        ; $EFD3
    sta LOMEM                       ; $EFD5
    sta HIMEM                       ; $EFD7
    lda #$08                        ; $EFD9
    sta LOMEM+1                     ; $EFDB
    lda #$10                        ; $EFDD
    sta HIMEM+1                     ; $EFDF
    jmp NEW                         ; $EFE1

;; The end of a substring's checks: carry clear if A is at most the string's end.
;; See: <COMMA_SUBSTR>, <CHKSTRRNG>
CHKSTREND:
    cmp NOUNSTKH,x                  ; $EFE4
    bne CHKSTREND_1                 ; $EFE6
    clc                             ; $EFE8

CHKSTREND_1:
    jmp CHKSTRRNG                   ; $EFE9

;; RUN alone (token $08): clears the variables and runs the program from its first line.
;; See: <CLR>, <RUNWARM>
RUN:
    jsr CLR                         ; $EFEC
    jmp RUNWARM                     ; $EFEF

;; RUN with a line number (token $07): clears the variables and runs the program from that line.
;; See: <CLR>, <GOTO>
RUNNUM:
    jsr CLR                         ; $EFF2
    jmp GOTO                        ; $EFF5

;; For the lister: before a keyword, skips the blank its text starts with, if any, then prints a blank if the keyword
;; starts with a letter.
;; In: X = the keyword's first table byte
;; See: <BLANKIFLET>, <LISTTOKEN>
KEYBLANK:
    cpx #$80                        ; $EFF8
    bne KEYBLANK_1                  ; $EFFA
    dey                             ; $EFFC

KEYBLANK_1:
    jmp BLANKIFLET                  ; $EFFD
