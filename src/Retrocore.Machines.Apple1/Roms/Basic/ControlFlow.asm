;; APPLE-1 BASIC: PRINTING NUMBERS, ASSIGNMENT AND RUNNING A PROGRAM ($E7C1-$E997)
;;
;; PRINT of a number, AUTO, numeric assignment and the statement separators; then the run loop, which takes the
;; program's lines in turn, and the statements that change its course: IF, GOTO, GOSUB, RETURN, END, FOR, TO, STEP
;; and NEXT.
;;
;; The run loop keeps PR at the line running and PX at its tokens. GOSUB keeps PX and PR on the GOSUB stack, and
;; FOR keeps its variable, step, limit and the place to loop back to on the FOR stack, both in page 1 (STK_00 and
;; STK_20); each holds 8 entries. A jump restarts the run loop, which resets the 6502's stack.
;;
;; Part of Basic.asm; it follows Arithmetic.asm, at $E7C1.

;; PRINT's comma before a number (token $49): moves to the next tab stop, then prints the number.
;; See: <NEXTTAB>, <PRINTNUM>
COMMA_PRNUM:
    jsr NEXTTAB                     ; $E7C1

;; PRINT of a number (token $62), and the semicolon before one (token $46): prints the number in decimal.
;;
;; A negative number gets a minus sign and is printed as its negative. The line now owes a return (<CRFLAG>).
;; In: X = the noun stack, its top entry the number
;; Out: X = the noun stack without the number; PRINTACC keeps X
;; Errors: >32767 for -32768, after the minus sign
;; Uses: A, Y, ACC
;; Entry: PRINTACC = prints the number in ACC
PRINTNUM:
    jsr GET16BIT                    ; $E7C4

PRINTACC:
    lda ACC+1                       ; $E7C7
    bpl PRINTNUM_1                  ; $E7C9
    lda #'-'                        ; $E7CB
    jsr COUT                        ; $E7CD
    jsr NEGATEACC                   ; $E7D0
    bvc PRINTNUM                    ; $E7D3 always: an overflow is an error

;; Prints a number that is not negative, and sets <CRFLAG>.
PRINTNUM_1:
    dey                             ; $E7D5
    sty CRFLAG                      ; $E7D6
    stx ACC+1                       ; $E7D8 keep X
    ldx ACC                         ; $E7DA
    jsr PRDEC                       ; $E7DC
    ldx ACC+1                       ; $E7DF
    rts                             ; $E7E1

;; AUTO (token $0D): starts AUTO mode at the line number given, counting by 10.
;; In: X = the noun stack, its top entry the first line number
;; See: <COMMA_AUTO>, <WARM>, <AUTOFLAG>
AUTO:
    jsr GET16BIT                    ; $E7E2
    lda ACC                         ; $E7E5
    sta AUTOLN                      ; $E7E7
    lda ACC+1                       ; $E7E9
    sta AUTOLN+1                    ; $E7EB
    dey                             ; $E7ED
    sty AUTOFLAG                    ; $E7EE AUTOFLAG = $FF
    iny                             ; $E7F0
    lda #10                         ; $E7F1

;; Sets the step between line numbers to A (low) and Y (high).
SETAUTOINC:
    sta AUTOINC                     ; $E7F3
    sty AUTOINC+1                   ; $E7F5
    rts                             ; $E7F7

;; The comma of AUTO (token $0E): AUTO n,m counts by m.
;; In: X = the noun stack, its top entry the step
COMMA_AUTO:
    jsr GET16BIT                    ; $E7F8
    lda ACC                         ; $E7FB
    ldy ACC+1                       ; $E7FD
    bpl SETAUTOINC                  ; $E7FF always: a number is at most 32767

;; Numeric assignment (token $71, and $56, the = of FOR): stores the number on top in the variable below it.
;; In: X = the noun stack: the value above the variable's address
;; Out: X = the noun stack, both popped
ASSIGN_NUM:
    jsr GET16BIT                    ; $E801
    lda NOUNSTKL,x                  ; $E804
    sta AUX                         ; $E806
    lda NOUNSTKH,x                  ; $E808
    sta AUX+1                       ; $E80A
    lda ACC                         ; $E80C
    sta (AUX),y                     ; $E80E
    iny                             ; $E810
    lda ACC+1                       ; $E811
    sta (AUX),y                     ; $E813
    inx                             ; $E815 pop the variable, and return through LET's RTS

;; LET (token $5E), and THEN before a statement (token $25): nothing to do.
LET:
    rts                             ; $E816

;; Token 0, at the bottom of the waiting tokens: ends the line.
;;
;; It runs when the end-of-line token arrives, after all the others. Dropping the return to the interpreter's loop
;; makes its RTS return from <EXECLINE>; first it falls into <COLON>, to print a return PRINT owes.
BEGIN_LINE:
    pla                             ; $E817
    pla                             ; $E818

;; The colon between statements (token $03): prints the return that a PRINT without a final ; or , owes.
;; See: <CRFLAG>
COLON:
    bit CRFLAG                      ; $E819
    bpl COLON_1                     ; $E81B

;; PRINT alone (token $63): prints a return.
PRINT_CR:
    jsr CROUT                       ; $E81D

;; PRINT's semicolon at the end of the statement (token $47): the line owes no return.
SEMI_END:
    lsr CRFLAG                      ; $E820

COLON_1:
    rts                             ; $E822

;; The left parenthesis tokens ($22, $34, $38, $3F and others): set <PRFLAG> to $FF, so nothing waiting before the
;; parenthesis runs.
;;
;; A left parenthesis runs when the right parenthesis arrives, after the operators inside it. Raising the arriving
;; priority to $FF then stops the waiting tokens outside the parentheses from running yet.
;; See: <RIGHT_PAREN>, <DOTOKEN>
LEFT_PAREN:
    ldy #$FF                        ; $E823
    sty PRFLAG                      ; $E825

;; The right parenthesis (token $72): nothing to do; its arrival made the parentheses' contents run.
RIGHT_PAREN:
    rts                             ; $E827

;; IF (token $60): when the condition is 0, sets <IFFLAG> so the rest of the statement is skipped.
;;
;; IF runs when THEN arrives. A false condition also changes the arriving token to $25, the THEN that comes before a
;; statement, so that IF X THEN 100 does not jump; the skipping then passes over the line number.
;; In: X = the noun stack, its top entry the condition
;; See: <IFFLAG>, <EXECLINE_10>, <GOTO>
IF:
    jsr NOTTOP                      ; $E828
    beq IF_1                        ; $E82B true: nothing to skip
    lda #$25                        ; $E82D
    sta VERBNOW                     ; $E82F
    dey                             ; $E831
    sty IFFLAG                      ; $E832

;; Pops the condition.
IF_1:
    inx                             ; $E834
    rts                             ; $E835

;; Runs the program from its first line, keeping the variables.
;;
;; RUN comes here after CLR.
;; See: <RUN>
RUNWARM:
    lda PP                          ; $E836
    ldy PP+1                        ; $E838
    bne TRYLINE                     ; $E83A always: the program is not in page 0

;; GOSUB (token $5C): saves where the program is on the GOSUB stack, then goes to the line (<GOTO>).
;;
;; The saved <PX> is the token after the line number, where <RETURN> picks up.
;; In: X = the noun stack, its top entry the line number
;; Errors: >8 GOSUBS if 8 are already active
;; See: <RETURN>
GOSUB:
    ldy #<ErrMsg08                  ; $E83C
    lda GOSUBNDX                    ; $E83E
    cmp #8                          ; $E840
    bcs JmpERRMESS1                 ; $E842
    tay                             ; $E844
    inc GOSUBNDX                    ; $E845
    lda PX                          ; $E847
    sta STK_00,y                    ; $E849
    lda PX+1                        ; $E84C
    sta STK_08,y                    ; $E84E
    lda PR                          ; $E851
    sta STK_10,y                    ; $E853
    lda PR+1                        ; $E856
    sta STK_18,y                    ; $E858

;; GOTO (token $5F), and THEN before a line number (token $24): goes to the line.
;; In: X = the noun stack, its top entry the line number
;; Errors: BAD BRANCH if there is no such line
;; See: <FINDLINE>, <GOLINE>
GOTO:
    jsr GET16BIT                    ; $E85B
    jsr FINDLINE                    ; $E85E
    bcc GOTO_1                      ; $E861
    ldy #<ErrMsg07                  ; $E863
    bne JmpERRMESS1                 ; $E865

;; Runs the program from the line found, at <P2>.
GOTO_1:
    lda P2                          ; $E867
    ldy P2+1                        ; $E869

;; Runs the program from the line at A (low) and Y (high): the run loop.
;;
;; A line's tokens start 3 bytes in, after its length and number. Running a line ends when <EXECLINE> returns; then the
;; loop steps to the next line by its length, until it reaches <HIMEM>. Before each line it looks at the keyboard:
;; any key typed stops the program, STOPPED AT the line, and is left for the prompt to read.
;; In: A/Y = the line's address
;; Errors: END if the program runs past its last line
GOLINE:
    sta PR                          ; $E86B
    sty PR+1                        ; $E86D
    bit KBDCR                       ; $E86F
    bmi STOPPED_AT                  ; $E872 a key: stop
    clc                             ; $E874
    adc #$03                        ; $E875
    bcc GETNEXT                     ; $E877
    iny                             ; $E879

;; Runs from the token at A (low) and Y (high) in the line at <PR>, with a fresh 6502 stack.
;; See: <RETURN>, <NEXT>
GETNEXT:
    ldx #$FF                        ; $E87A
    stx RUNFLAG                     ; $E87C
    txs                             ; $E87E
    sta PX                          ; $E87F
    sty PX+1                        ; $E881

;; Runs the line from the token at <PX>, then the lines after it, until a statement stops the program.
;;
;; A typed line without a number runs from here too, with <RUNFLAG> clear. When <PX> is at a statement's first
;; token, that statement starts here; after RETURN or NEXT it is at the colon or the end of the line instead, and
;; the statement after it starts at <WAITTOKEN>.
;; See: <GETNEXT>, <EXECLINE>
RUNLOOP:
    jsr EXECLINE                    ; $E883 run the line
    bit RUNFLAG                     ; $E886
    bpl END                         ; $E888 a statement stopped the program
    clc                             ; $E88A
    ldy #$00                        ; $E88B
    lda PR                          ; $E88D the next line: PR + its length
    adc (PR),y                      ; $E88F
    ldy PR+1                        ; $E891
    bcc TRYLINE                     ; $E893
    iny                             ; $E895

;; Runs the line at A/Y unless it is <HIMEM>, the end of the program.
TRYLINE:
    cmp HIMEM                       ; $E896
    bne GOLINE                      ; $E898
    cpy HIMEM+1                     ; $E89A
    bne GOLINE                      ; $E89C
    ldy #<ErrMsg06+3                ; $E89E END, the last word of NO END

TRYLINE_END:
    lsr RUNFLAG                     ; $E8A0 no longer running

JmpERRMESS1:
    jmp ERRMESS                     ; $E8A2

;; RETURN (token $5B): goes back to the token after the last GOSUB.
;; Errors: BAD RETURN if no GOSUB is active
;; See: <GOSUB>
RETURN:
    ldy #<ErrMsg09                  ; $E8A5
    lda GOSUBNDX                    ; $E8A7
    beq JmpERRMESS1                 ; $E8A9
    dec GOSUBNDX                    ; $E8AB
    tay                             ; $E8AD
    lda STK_10-1,y                  ; $E8AE
    sta PR                          ; $E8B1
    lda STK_18-1,y                  ; $E8B3
    sta PR+1                        ; $E8B6
    ldx a:STK_00-1,y                ; $E8B8 X = the token address, low byte (absolute: $00FF,Y)
    lda STK_08-1,y                  ; $E8BB

;; Runs from the token at X (low) and A (high), in the line at <PR>.
GETNEXTXA:
    tay                             ; $E8BE
    txa                             ; $E8BF
    jmp GETNEXT                     ; $E8C0

;; Stops the program: prints STOPPED AT and the number of the line at <PR>, then ends.
;;
;; A key typed while a program runs (<GOLINE>), and errors in a running program, come here.
;; See: <GOLINE>, <RUNERROR>
STOPPED_AT:
    ldy #<ErrMsg12                  ; $E8C3
    jsr ERRORMESS                   ; $E8C5
    ldy #$01                        ; $E8C8
    lda (PR),y                      ; $E8CA
    tax                             ; $E8CC
    iny                             ; $E8CD
    lda (PR),y                      ; $E8CE
    jsr PRDEC                       ; $E8D0

;; END (token $51): stops the program and returns to the prompt.
END:
    jmp WARM                        ; $E8D3

;; Drops the innermost FOR loop, whose variable is not NEXT's.
NEXT_1:
    dec FORNDX                      ; $E8D6

;; NEXT (token $59, and $5A after a comma): adds the step to the loop's variable and loops back, unless it has passed
;; the limit.
;;
;; The FOR stack is searched from the innermost loop for the variable; loops inside it are dropped. The loop goes on
;; while the variable equals the limit or the sign of variable - limit is not the step's sign.
;; In: X = the noun stack, its top entry the variable
;; Errors: BAD NEXT if no FOR loop has the variable
;; See: <FOR>, <STK_20>
NEXT:
    ldy #<ErrMsg11                  ; $E8D8
    lda FORNDX                      ; $E8DA

;; An error, when Z is set: no loops left (BAD NEXT), or 8 FOR loops already (>8 FORS).
JmpERRMESS2:
    beq JmpERRMESS1                 ; $E8DC
    tay                             ; $E8DE
    lda NOUNSTKL,x                  ; $E8DF
    cmp STK_20-1,y                  ; $E8E1
    bne NEXT_1                      ; $E8E4
    lda NOUNSTKH,x                  ; $E8E6
    cmp STK_28-1,y                  ; $E8E8
    bne NEXT_1                      ; $E8EB
    lda STK_30-1,y                  ; $E8ED
    sta AUX                         ; $E8F0
    lda STK_38-1,y                  ; $E8F2
    sta AUX+1                       ; $E8F5
    jsr GET16BIT                    ; $E8F7 the variable's value
    dex                             ; $E8FA push the variable back
    jsr ADDAUX                      ; $E8FB push value + step
    jsr ASSIGN_NUM                  ; $E8FE store it
    dex                             ; $E901 push the variable back again, then the limit
    ldy FORNDX                      ; $E902
    lda STK_68-1,y                  ; $E904
    sta NOUNSTKC-1,x                ; $E907
    lda STK_60-1,y                  ; $E909
    ldy #$00                        ; $E90C
    jsr PUSHNOUN                    ; $E90E
    jsr SUBTRACT                    ; $E911 the sign of variable - limit
    jsr SGN                         ; $E914
    jsr GET16BIT                    ; $E917
    ldy FORNDX                      ; $E91A
    lda ACC                         ; $E91C
    beq NEXT_2                      ; $E91E equal to the limit: once more
    eor STK_38-1,y                  ; $E920 the sign differs from the step's: once more
    bpl NEXT_3                      ; $E923

;; Loops back: runs from the token after the FOR statement.
NEXT_2:
    lda STK_40-1,y                  ; $E925
    sta PR                          ; $E928
    lda STK_48-1,y                  ; $E92A
    sta PR+1                        ; $E92D
    ldx STK_50-1,y                  ; $E92F
    lda STK_58-1,y                  ; $E932
    bne GETNEXTXA                   ; $E935 always: the address is not in page 0

;; The loop is done: drops it.
NEXT_3:
    dec FORNDX                      ; $E937
    rts                             ; $E939

;; FOR (token $55): starts a FOR loop for the variable, which = then assigns.
;;
;; The variable stays on the noun stack for the = (<ASSIGN_NUM>). TO and STEP fill in the rest of the entry. A FOR loop
;; already active for the same variable stays, and a NEXT for it finds the newer one first.
;; In: X = the noun stack, its top entry the variable
;; Errors: >8 FORS if 8 loops are active
;; See: <TO>, <STEP>, <NEXT>
FOR:
    ldy #<ErrMsg10                  ; $E93A
    lda FORNDX                      ; $E93C
    cmp #8                          ; $E93E
    beq JmpERRMESS2                 ; $E940
    inc FORNDX                      ; $E942
    tay                             ; $E944
    lda NOUNSTKL,x                  ; $E945
    sta STK_20,y                    ; $E947
    lda NOUNSTKH,x                  ; $E94A
    sta STK_28,y                    ; $E94C
    rts                             ; $E94F

;; TO (token $57): sets the loop's limit and a step of 1, and the place to loop back to.
;;
;; The place is the line at <PR> and the token at <PX>, which is the token after the statement, or STEP: STEP runs
;; later, and sets it again.
;; In: X = the noun stack, its top entry the limit
;; See: <FOR>, <STEP>
;; Entry: SETFORPLACE = stores the step's high byte from A, then the place
TO:
    jsr GET16BIT                    ; $E950
    ldy FORNDX                      ; $E953
    lda ACC                         ; $E955
    sta STK_60-1,y                  ; $E957
    lda ACC+1                       ; $E95A
    sta STK_68-1,y                  ; $E95C
    lda #$01                        ; $E95F
    sta STK_30-1,y                  ; $E961
    lda #$00                        ; $E964

SETFORPLACE:
    sta STK_38-1,y                  ; $E966
    lda PR                          ; $E969
    sta STK_40-1,y                  ; $E96B
    lda PR+1                        ; $E96E
    sta STK_48-1,y                  ; $E970
    lda PX                          ; $E973
    sta STK_50-1,y                  ; $E975
    lda PX+1                        ; $E978
    sta STK_58-1,y                  ; $E97A
    rts                             ; $E97D

;; STEP (token $58): sets the step of the FOR loop being set up, and the place to loop back to again, after STEP.
;; In: X = the noun stack, its top entry the step
;; See: <TO>, <FOR>
STEP:
    jsr GET16BIT                    ; $E97E
    ldy FORNDX                      ; $E981
    lda ACC                         ; $E983
    sta STK_30-1,y                  ; $E985
    lda ACC+1                       ; $E988
    jmp SETFORPLACE                 ; $E98A
    .byte $00, $00, $00, $00, $00, $00, $00, $00 ; $E98D unused bytes
    .byte $00, $00, $00             ; $E995
