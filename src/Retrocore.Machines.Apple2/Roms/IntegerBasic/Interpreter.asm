;; INTEGER BASIC: VARIABLES AND THE STATEMENT INTERPRETER ($E5CC-$E6FE)
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
;; Part of IntegerBasic.asm; it follows Program.asm, at $E5CC.

;; An unused instruction that falls into the MEM FULL error; nothing in the ROM reaches it.
UNUSED_MEMFULL:
    lda SRCH                        ; $E5CC

;; The MEM FULL error.
ErrMemFull:
    jmp MEMFULL                     ; $E5CE

;; Compares the name at <PX> with the variable at <SRCH>, and goes on to the next variable if it differs.
;;
;; A name in the program is its characters, then $40 for a string, then a token. Bit 7 of <XSAVE> stays set for a
;; numeric name; $40 clears it.
;; In: SRCH = the variable to compare
;; Entry: CMPVARNAMEY = with Y already $FF
CMPVARNAME:
    ldy #$FF                        ; $E5D1

CMPVARNAMEY:
    sty XSAVE                       ; $E5D3

CMPVARNAME_1:
    iny                             ; $E5D5
    lda (PX),y                      ; $E5D6
    bmi CMPVARNAME_2                ; $E5D8
    cmp #$40                        ; $E5DA
    bne LOOKUPVAR_1                 ; $E5DC a token: the name ends here
    sta XSAVE                       ; $E5DE $40, the $ of a string name

;; Compares a character of the name with the variable's.
CMPVARNAME_2:
    cmp (SRCH),y                    ; $E5E0
    beq CMPVARNAME_1                ; $E5E2

;; The names differ: skips the rest of the variable's name, up to its display flag (0 or 1), and moves to the
;; next variable through the address after the flag.
CMPVARNAME_3:
    lda (SRCH),y                    ; $E5E4

CMPVARNAME_4:
    iny                             ; $E5E6
    lsr a                           ; $E5E7
    bne CMPVARNAME_3                ; $E5E8
    lda (SRCH),y                    ; $E5EA
    pha                             ; $E5EC
    iny                             ; $E5ED
    lda (SRCH),y                    ; $E5EE
    tay                             ; $E5F0
    pla                             ; $E5F1

;; Goes on with the variable at A (low) and Y (high), unless that is the end of the variables, <PV>.
;;
;; At the end the name is new: it is added at <PV> and found on the next pass.
TRYVAR:
    sta SRCH                        ; $E5F2
    sty SRCH+1                      ; $E5F4
    cmp PV                          ; $E5F6
    bne CMPVARNAME                  ; $E5F8
    cpy PV+1                        ; $E5FA
    bne CMPVARNAME                  ; $E5FC
    ldy #$00                        ; $E5FE count the new name's characters
@Loop:
    iny                             ; $E600
    lda (PX),y                      ; $E601
    bmi @Loop                       ; $E603
    eor #$40                        ; $E605
    beq @Loop                       ; $E607
    tya                             ; $E609
    adc #$04                        ; $E60A carry is set: name + flag + next address + value
    pha                             ; $E60C
    adc SRCH                        ; $E60D
    tay                             ; $E60F
    lda SRCH+1                      ; $E610
    adc #$00                        ; $E612
    pha                             ; $E614
    cpy PP                          ; $E615 it must stay below the program
    sbc PP+1                        ; $E617
    bcs ErrMemFull                  ; $E619
    sty PV                          ; $E61B
    pla                             ; $E61D
    sta PV+1                        ; $E61E
    pla                             ; $E620
    tay                             ; $E621
    lda #$00                        ; $E622
    dey                             ; $E624 the value, 0
    sta (SRCH),y                    ; $E625
    dey                             ; $E627
    sta (SRCH),y                    ; $E628
    dey                             ; $E62A
    lda PV+1                        ; $E62B the address of the next variable: the new PV
    sta (SRCH),y                    ; $E62D
    dey                             ; $E62F
    lda PV                          ; $E630
    sta (SRCH),y                    ; $E632
    dey                             ; $E634
    lda #$00                        ; $E635 the display flag, 0

;; Copies the name in from the program, from its end, then searches again, which finds it.
TRYVAR_1:
    sta (SRCH),y                    ; $E637
    dey                             ; $E639
    bmi CMPVARNAMEY                 ; $E63A all copied: search again, from this variable
    lda (PX),y                      ; $E63C
    bne TRYVAR_1                    ; $E63E

;; Looks up the variable whose name starts at <PX>, from <LOMEM>, and pushes its address.
;;
;; A numeric variable pushes the address of its 2-byte value. A string pushes its address and above it a range from
;; 0 to its length, found by counting the characters before the byte that ends it. The display flag goes in the
;; <NOUNSTKC> byte of the address entry, where the assignment routines look for it. <PX> ends on the token after
;; the name.
;; In: PX = the name's first character
;; See: <CMPVARNAME>, <PV>
LOOKUPVAR:
    lda LOMEM                       ; $E640
    ldy LOMEM+1                     ; $E642
    bne TRYVAR                      ; $E644 always: LOMEM is above page 0

;; The name at <PX> has ended: the variable matches if its name ends here too.
LOOKUPVAR_1:
    lda (SRCH),y                    ; $E646
    cmp #$40                        ; $E648
    bcs CMPVARNAME_4                ; $E64A the variable's name goes on: not this one
    sta NOUNSTKC-1,x                ; $E64C the display flag
    tya                             ; $E64E carry is clear: past the flag and the next address, to the value
    adc #$03                        ; $E64F
    pha                             ; $E651
    adc SRCH                        ; $E652
    jsr PUSHNOUNLO                  ; $E654 push the value's address, low byte
@Loop:
    jsr GETVERB                     ; $E657 step PX over the name
    dey                             ; $E65A
    bne @Loop                       ; $E65B
    tya                             ; $E65D
    adc SRCH+1                      ; $E65E
    sta NOUNSTKH,x                  ; $E660
    pla                             ; $E662
    bit XSAVE                       ; $E663
    bmi EXECLINE_3                  ; $E665 a numeric variable: done
    tay                             ; $E667
    lda #$00                        ; $E668
    jsr PUSHNOUNLO                  ; $E66A
    sta NOUNSTKH,x                  ; $E66D

;; Counts the string's characters into the range's end.
LOOKUPVAR_2:
    lda (SRCH),y                    ; $E66F
    bpl EXECLINE_2                  ; $E671
    inc NOUNSTKH,x                  ; $E673
    iny                             ; $E675
    bne LOOKUPVAR_2                 ; $E676
    .byte $09                       ; $E678 unused byte

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
    jsr GETVERB0                    ; $E6E5 the next item
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
