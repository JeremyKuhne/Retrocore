;; APPLE-1 BASIC: VARIABLES AND THE STATEMENT INTERPRETER ($E5CC-$E6FE)
;;
;; The interpreter that runs a line's tokens (EXECLINE), and the variable lookup it calls for each name.
;;
;; The interpreter evaluates by operator priority. Operands are pushed on the noun stack as they come: a constant's
;; value, a variable's address, a string's address and range. Every token is an operator, a statement keyword as
;; much as a plus sign, with two priorities in TABLE1 (VerbTables.asm): one for when it arrives, one for while it
;; waits. Tokens wait on the 6502's stack. When a token arrives, each waiting token whose waiting priority is at
;; least the new one's arriving priority runs first, taking its operands off the noun stack and pushing its result;
;; then the new token waits in turn. So in A=2+3*4 the * runs before the +, and the = (an assignment) runs last. The
;; stack starts with token 0, whose routine (BEGIN_LINE) ends the line, so $01 at the end of the line, which every
;; waiting token yields to, finishes the line.
;;
;; A variable's name is looked up each time it is met, from LOMEM up; one that is not found is created at the
;; end of the variables, with a value of 0. Its address goes on the noun stack, and the statement routines read or
;; store through it, so the same push serves both A=1 and PRINT A.
;;
;; Part of Basic.asm; it follows Program.asm, at $E5CC.

;; Adds a variable at <PV>, the end of the variables, then searches again, which finds it.
;;
;; A variable is six bytes: its two name bytes (<ACC>), the address of the next variable, and its value, 0 to
;; start. A string's characters follow its entry when it is assigned (<LET_STR>).
;; In: SRCH = PV, carry set
;; Errors: MEM FULL if the entry would reach the program
NEWVAR:
    lda SRCH                        ; $E5CC
    adc #$05                        ; $E5CE carry is set: SRCH + 6, past the entry
    sta SRCH2                       ; $E5D0
    lda SRCH+1                      ; $E5D2
    adc #$00                        ; $E5D4
    sta SRCH2+1                     ; $E5D6
    lda SRCH2                       ; $E5D8
    cmp PP                          ; $E5DA it must stay below the program
    lda SRCH2+1                     ; $E5DC
    sbc PP+1                        ; $E5DE
    bcc NEWVAR_1                    ; $E5E0
    jmp MEMFULL                     ; $E5E2

NEWVAR_1:
    lda ACC                         ; $E5E5 the name
    sta (SRCH),y                    ; $E5E7
    lda ACC+1                       ; $E5E9
    iny                             ; $E5EB
    sta (SRCH),y                    ; $E5EC
    lda SRCH2                       ; $E5EE the next variable's address: the new end
    iny                             ; $E5F0
    sta (SRCH),y                    ; $E5F1
    lda SRCH2+1                     ; $E5F3
    iny                             ; $E5F5
    sta (SRCH),y                    ; $E5F6
    lda #$00                        ; $E5F8 the value, 0
    iny                             ; $E5FA
    sta (SRCH),y                    ; $E5FB
    iny                             ; $E5FD
    sta (SRCH),y                    ; $E5FE
    lda SRCH2                       ; $E600
    sta PV                          ; $E602
    lda SRCH2+1                     ; $E604
    sta PV+1                        ; $E606
    lda SRCH                        ; $E608
    bcc LOOKUPVAR_NEXT              ; $E60A always: search on from this variable

;; Looks up the variable whose name starts at <PX>, and pushes its address.
;;
;; A name is a letter and an optional second character: a digit, or $40, the $ of a string. The two name bytes
;; are the letter shifted left and the second character, or 0; the search compares them with each variable's,
;; from <LOMEM> up to <PV>, and a name that is not found is added (<NEWVAR>). A numeric variable pushes the address
;; of its 2-byte value. A string pushes its address and above it a range from 0 to its length, found by counting
;; the characters that have bit 7 set. <PX> ends on the token after the name.
;; In: A = the name's letter shifted left, Y = 0, PX = the letter
;; See: <NEWVAR>, <PV>
LOOKUPVAR:
    sta ACC                         ; $E60C
    sty ACC+1                       ; $E60E no second character yet
    jsr GETVERB                     ; $E610
    bmi LOOKUPVAR_2ND               ; $E613 a character: the name's second
    cmp #$40                        ; $E615
    beq LOOKUPVAR_2ND               ; $E617 the $ of a string
    jmp LOOKUPVAR_SEARCH            ; $E619
    .byte $06, $C9, $49, $D0, $07, $A9, $49 ; $E61C unused bytes

LOOKUPVAR_2ND:
    sta ACC+1                       ; $E623
    jsr GETVERB                     ; $E625

LOOKUPVAR_SEARCH:
    lda LOMEM+1                     ; $E628
    sta SRCH+1                      ; $E62A
    lda LOMEM                       ; $E62C

;; Tries the variable at A (low) and <SRCH>+1 (high), unless that is the end of the variables.
LOOKUPVAR_TRY:
    sta SRCH                        ; $E62E
    cmp PV                          ; $E630
    lda SRCH+1                      ; $E632
    sbc PV+1                        ; $E634
    bcs NEWVAR                      ; $E636 the end: a new name
    lda (SRCH),y                    ; $E638
    iny                             ; $E63A
    cmp ACC                         ; $E63B
    bne LOOKUPVAR_SKIP              ; $E63D
    lda (SRCH),y                    ; $E63F
    cmp ACC+1                       ; $E641
    beq LOOKUPVAR_FOUND             ; $E643

;; Not this one: moves to the next variable through the address after the name.
LOOKUPVAR_SKIP:
    iny                             ; $E645
    lda (SRCH),y                    ; $E646
    pha                             ; $E648
    iny                             ; $E649
    lda (SRCH),y                    ; $E64A
    sta SRCH+1                      ; $E64C
    pla                             ; $E64E

LOOKUPVAR_NEXT:
    ldy #$00                        ; $E64F
    beq LOOKUPVAR_TRY               ; $E651 always

;; Found: pushes the address of the value, and for a string the range of its characters.
LOOKUPVAR_FOUND:
    lda SRCH                        ; $E653
    adc #$03                        ; $E655 carry is set: SRCH + 4, the value
    jsr PUSHNOUNLO                  ; $E657
    lda SRCH+1                      ; $E65A
    adc #$00                        ; $E65C
    sta NOUNSTKH,x                  ; $E65E
    lda ACC+1                       ; $E660
    cmp #$40                        ; $E662
    bne EXECLINE_2                  ; $E664 a numeric variable: done
    dey                             ; $E666 Y = 0
    tya                             ; $E667
    jsr PUSHNOUNLO                  ; $E668 the range, from 0
    dey                             ; $E66B
    sty NOUNSTKH,x                  ; $E66C $FF, which the first character counted makes 0
    ldy #$03                        ; $E66E

;; Counts the string's characters into the range's end.
LOOKUPVAR_COUNT:
    inc NOUNSTKH,x                  ; $E670
    iny                             ; $E672
    lda (SRCH),y                    ; $E673
    bmi LOOKUPVAR_COUNT             ; $E675
    bpl EXECLINE_2                  ; $E677 always

;; Runs the tokens of a line, starting at <PX>, by operator priority, until the end-of-line token finishes it.
;;
;; The 6502's stack holds the tokens waiting to run, starting with token 0, and X the noun stack. When the line's
;; end arrives, every waiting token runs, and token 0's routine, <BEGIN_LINE>, returns from here.
;; In: PX = the first token, Y = 0
;; Uses: all
;; See: <DOTOKEN>, <TABLE1>, <VERBADRL>, <BEGIN_LINE>
EXECLINE:
    lda #$00                        ; $E679
    sta IFFLAG                      ; $E67B
    sta CRFLAG                      ; $E67D
    ldx #$20                        ; $E67F the noun stack is empty

EXECLINE_1:
    pha                             ; $E681 the token in A waits

EXECLINE_2:
    ldy #$00                        ; $E682

;; Takes the item at <PX>: a constant, a name or a token.
EXECLINE_3:
    lda (PX),y                      ; $E684

EXECLINE_4:
    bpl EXECLINE_7                  ; $E686 bit 7 clear: a token
    asl a                           ; $E688
    bmi LOOKUPVAR                   ; $E689 bits 7 and 6 set: a name
    jsr GETVERB                     ; $E68B a constant: its value follows the marker
    jsr PUSHNOUN                    ; $E68E push the low byte, as a number (Y = 0)
    jsr GETVERB                     ; $E691
    sta NOUNSTKC,x                  ; $E694

;; After an operand: while a false IF is skipped, it is dropped again.
EXECLINE_5:
    bit IFFLAG                      ; $E696
    bpl EXECLINE_6                  ; $E698
    dex                             ; $E69A

;; Steps to the next item; the branch is always taken (carry is set).
EXECLINE_6:
    jsr GETVERB                     ; $E69B
    bcs EXECLINE_4                  ; $E69E

;; A token: pushes a string constant, or runs or holds the token.
;;
;; After an opening quote ($28) the string's address is <PX>, the quote itself, and its range runs from 1 to the
;; index of the closing quote.
EXECLINE_7:
    cmp #$28                        ; $E6A0
    bne EXECLINE_10                 ; $E6A2 not a string constant
    lda PX                          ; $E6A4
    jsr PUSHNOUNLO                  ; $E6A6
    lda PX+1                        ; $E6A9
    sta NOUNSTKH,x                  ; $E6AB
    bit IFFLAG                      ; $E6AD
    bmi EXECLINE_9                  ; $E6AF skipped: no range
    lda #$01                        ; $E6B1
    jsr PUSHNOUNLO                  ; $E6B3
    lda #$00                        ; $E6B6 the range's end, counted up
    sta NOUNSTKH,x                  ; $E6B8

EXECLINE_8:
    inc NOUNSTKH,x                  ; $E6BA

EXECLINE_9:
    jsr GETVERB                     ; $E6BC
    bmi EXECLINE_8                  ; $E6BF
    bcs EXECLINE_5                  ; $E6C1

;; While a false IF is skipped, passes over every token but $01 and $03, the end of the line and a colon, which
;; end the skipping.
EXECLINE_10:
    bit IFFLAG                      ; $E6C3
    bpl DOTOKEN                     ; $E6C5
    cmp #$04                        ; $E6C7
    bcs EXECLINE_6                  ; $E6C9
    lsr IFFLAG                      ; $E6CB

;; Lets the waiting tokens that come first run, then makes the token wait.
;;
;; Each <TABLE1> byte holds two priorities with their bits interleaved: the even bits ($55) are the priority on
;; arrival, the odd bits ($AA) the priority while waiting. Shifting the arriving priority left puts it in the odd
;; bits, so the two compare as plain bytes.
;; In: A = the token
DOTOKEN:
    tay                             ; $E6CD
    sta VERBNOW                     ; $E6CE
    lda TABLE1,y                    ; $E6D0
    and #%01010101                  ; $E6D3
    asl a                           ; $E6D5
    sta PRFLAG                      ; $E6D6 the arriving priority, in the odd bits

;; Takes the next waiting token and runs it if its waiting priority is at least the arriving one; otherwise puts it
;; back, makes the arriving token wait and steps <PX> on.
DOTOKEN_1:
    pla                             ; $E6D8
    tay                             ; $E6D9
    lda TABLE1,y                    ; $E6DA
    and #%10101010                  ; $E6DD
    cmp PRFLAG                      ; $E6DF
    bcs DOTOKEN_2                   ; $E6E1
    tya                             ; $E6E3 put it back
    pha                             ; $E6E4

;; The arriving token is to wait: steps <PX> past it to the next item, then makes it wait.
;;
;; When the token is a colon ($03), every token of the statement before it has run, so the next statement starts at
;; the item after it; the debugger's BASIC thread takes each statement after the first in a line from here.
;; See: <RUNLOOP>, <COLON>
WAITTOKEN:
    jsr GETVERB                     ; $E6E5 the next item
    lda VERBNOW                     ; $E6E8
    bcc EXECLINE_1                  ; $E6EA always: the compare cleared the carry

;; Runs a waiting token through the verb tables, then looks at the next one.
DOTOKEN_2:
    lda VERBADRL,y                  ; $E6EC
    sta ACC                         ; $E6EF
    lda VERBADRH,y                  ; $E6F1
    sta ACC+1                       ; $E6F4
    jsr JMPVERB                     ; $E6F6
    jmp DOTOKEN_1                   ; $E6F9

;; Jumps to the address in <ACC>: JSR here calls the token's routine.
JMPVERB:
    jmp (ACC)                       ; $E6FC
