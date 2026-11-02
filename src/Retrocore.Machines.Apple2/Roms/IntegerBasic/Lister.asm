;; INTEGER BASIC: ENTRY POINTS AND THE LISTER ($E000-$E0FA)
;;
;; The two entry points at the start of the ROM, which the Monitor's Control-B and Control-C commands jump to, and
;; LIST, which turns a program's tokens back into text.
;;
;; The lister prints a line's number, then walks its bytes. A byte with bit 7 set and bit 6 clear starts a constant,
;; whose value follows; one with bits 7 and 6 set starts a name, whose characters all have bit 7 set. Any other byte
;; is a token, whose text the lister finds in the syntax table (SyntaxTable.asm) by counting keywords down from the
;; top of a page, the same count that gave the word its token. After REM and an opening quote it copies the
;; characters that follow as they are. It adds blanks around keywords that begin or end with a letter, and starts a
;; new line, indented, when a line would run past the screen's width.
;;
;; Part of IntegerBasic.asm; it assembles at $E000.

;; Starts Integer BASIC from scratch: the cold start, which the Monitor's Control-B command runs.
;;
;; <COLD> sets <LOMEM> and <HIMEM> and erases any program, then returns here to fall into the warm start.
;; See: <COLD>, <BASIC2>
BASIC:
    jsr COLD                        ; $E000

;; Enters Integer BASIC keeping its program and variables: the warm start, which the Monitor's Control-C command
;; runs.
;;
;; Typing Control-C while a program waits for INPUT also comes here (<CHKCTRLC>).
;; See: <WARM>, <BASIC>
BASIC2:
    jmp WARM                        ; $E003

;; Sets the prompt character to A and prints it.
;; In: A = the prompt character
;; Keeps: X, Y
;; See: <PROMPT>
SetPrompt:
    sta PROMPT                      ; $E006
    jmp COUT                        ; $E008
    .byte $60                       ; $E00B an unused byte (an RTS)

;; Prints a blank if the keyword character in X is a letter, to separate a keyword from what follows.
;;
;; In the syntax table a character is stored as its code less $A0 in the low 6 bits, so bit 5 of the byte is set
;; for the letters ($C0-$DF) and clear for punctuation and digits ($A0-$BF).
;; In: X = the syntax table byte of the character just printed
;; Out: P2 = $A0 if a blank was printed
;; Uses: A
;; Keeps: X, Y
;; Entry: LISTBLANK = prints the blank whatever X holds
BLANKIFLET:
    txa                             ; $E00C
    and #$20                        ; $E00D
    beq NextByte_1                  ; $E00F

LISTBLANK:
    lda #BLANK+$80                  ; $E011
    sta P2                          ; $E013
    jmp COUT                        ; $E015

;; Fetches the next byte to list, first starting a new, indented line if the cursor is past column 32.
;;
;; The new line is a return and six blanks, so a long line continues under the start of its text.
;; Out: A = the byte at <P1>, Y = 0
;; Uses: P1 (advanced)
;; Keeps: X
;; Entry: LISTBYTECOL = takes the last column allowed in A instead of 32
LISTBYTE:
    lda #32                         ; $E018

LISTBYTECOL:
    cmp CH                          ; $E01A
    bcs NextByte                    ; $E01C still room on this line
    lda #CR+$80                     ; $E01E
    ldy #$07                        ; $E020 a return, then six blanks
@Loop:
    jsr COUT                        ; $E022
    lda #BLANK+$80                  ; $E025
    dey                             ; $E027
    bne @Loop                       ; $E028

;; Fetches the next byte to list from <P1> and steps <P1> past it.
;; Out: A = the byte, Y = 0
;; Keeps: X
NextByte:
    ldy #$00                        ; $E02A
    lda (P1),y                      ; $E02C
    inc P1                          ; $E02E
    bne NextByte_1                  ; $E030
    inc P1+1                        ; $E032

NextByte_1:
    rts                             ; $E034

;; The comma of LIST with two numbers (token $75): lists from where <LISTNUM> stopped up to the second line number.
;;
;; <FINDFROMP3> finds the first line numbered at or above the number, starting where <LISTNUM>'s search ended, and leaves
;; the address after it in <P3> when the number exists, so that line is listed too.
;; In: X = the noun stack, its top entry the last line number to list
;; See: <LISTNUM>, <LIST>
COMMA_LIST:
    jsr GET16BIT                    ; $E035
    jsr FINDFROMP3                  ; $E038

;; Lists the lines from <P1> up to, but not including, <P3>.
;; Uses: A, Y, P1, P2, LEADZR, ACC
LISTRANGE:
    lda P1                          ; $E03B
    cmp P3                          ; $E03D
    lda P1+1                        ; $E03F
    sbc P3+1                        ; $E041
    bcs NextByte_1                  ; $E043
    jsr UNPACK                      ; $E045
    jmp LISTRANGE                   ; $E048

;; LIST alone (token $76): lists the whole program, from <PP> up to <HIMEM>.
;; See: <LISTNUM>, <UNPACK>
LIST:
    lda PP                          ; $E04B
    sta P1                          ; $E04D
    lda PP+1                        ; $E04F
    sta P1+1                        ; $E051
    lda HIMEM                       ; $E053
    sta P3                          ; $E055
    lda HIMEM+1                     ; $E057
    sta P3+1                        ; $E059
    bne LISTRANGE                   ; $E05B always: HIMEM is above page 0

;; LIST with a number (token $74): lists that line, if it exists, and leaves <P1> ready for <COMMA_LIST>.
;;
;; When the line is missing, <P1> is left at the next line above the number, so LIST 5,30 lists from there.
;; In: X = the noun stack, its top entry the line number
;; See: <COMMA_LIST>, <FINDLINE>
LISTNUM:
    jsr GET16BIT                    ; $E05D
    jsr FINDLINE                    ; $E060
    lda P2                          ; $E063
    sta P1                          ; $E065
    lda P2+1                        ; $E067
    sta P1+1                        ; $E069
    bcs NextByte_1                  ; $E06B the number is not a line: list nothing yet

;; Lists one line: prints its number, then its tokens as text, and a return.
;;
;; <P2> remembers what was printed last: 0 at the start of the line, a token, or a value with bit 7 set after a
;; constant, a name or a blank. Only a name at the start of the line, where <P2> is 0, gets a blank before it, to
;; separate it from the line number; a keyword that starts with a letter gets one unless a blank or a name came last
;; (<KEYBLANK>).
;; In: P1 = the line's length byte
;; Out: P1 = the next line
;; Uses: A, Y, P2, LEADZR, ACC
;; Keeps: X
UNPACK:
    stx XSAVE                       ; $E06D
    lda #BLANK+$80                  ; $E06F
    sta LEADZR                      ; $E071 pad the line number to five places with blanks
    jsr NextByte                    ; $E073
    tya                             ; $E076 A = 0: nothing printed yet

;; Prints a constant: its value follows the digit that marks it.
;;
;; A holds the marker shifted left, which is not 0, so <P2> no longer asks for a blank before a name.
UNPACK_1:
    sta P2                          ; $E077
    jsr NextByte                    ; $E079
    tax                             ; $E07C
    jsr NextByte                    ; $E07D
    jsr PRDEC                       ; $E080 print the value, or the line number the first time through

;; The loop over the line's bytes: fetches the next one and decides what it starts.
UNPACK_2:
    jsr LISTBYTE                    ; $E083
    sty LEADZR                      ; $E086 no padding for constants after the line number
    tax                             ; $E088
    bpl LISTTOKEN                   ; $E089 bit 7 clear: a token
    asl a                           ; $E08B
    bpl UNPACK_1                    ; $E08C bit 6 clear: a digit, the start of a constant
    lda P2                          ; $E08E
    bne @NotEq                      ; $E090 a name: a blank before it only after the line number
    jsr LISTBLANK                   ; $E092
@NotEq:
    txa                             ; $E095

;; Prints a name or text: the character in A, then every following byte with bit 7 set.
;;
;; Text breaks onto a new line at column 37, later than tokens do.
;; Entry: LISTTEXTNXT = starts by fetching the next byte, after REM or an opening quote
LISTTEXT:
    jsr COUT                        ; $E096

LISTTEXTNXT:
    lda #$25                        ; $E099
    jsr LISTBYTECOL                 ; $E09B
    tax                             ; $E09E
    bmi LISTTEXT                    ; $E09F
    sta P2                          ; $E0A1 the token that ended the text

;; Lists a token: ends the line at $01; otherwise finds the token's text in the syntax table and prints it.
;;
;; Tokens below $51 are counted in the page at <SYNTABL2> ($ED00), the rest in the page at <SYNTABL> ($EC00), whose
;; count starts at $50. Each keyword is stored with its last character lowest, and the count goes down from the top
;; of the page: a keyword's first character is a character byte whose neighbor above is either not a character or
;; the last character of another keyword (bit 6 set). The X-th such character from the top starts token X's text.
LISTTOKEN:
    cmp #$01                        ; $E0A3
    bne @NotEq                      ; $E0A5 not the end of the line
    ldx XSAVE                       ; $E0A7
    jmp CROUT                       ; $E0A9 end of line: a return
@NotEq:
    pha                             ; $E0AC
    sty ACC                         ; $E0AD ACC = $ED00, Y = 0: the top byte is the first one read below
    ldx #>SYNTABL2                  ; $E0AF
    stx ACC+1                       ; $E0B1
    cmp #$51                        ; $E0B3
    bcc LISTTOKEN_1                 ; $E0B5 tokens below $51 are in the second page
    dec ACC+1                       ; $E0B7
    sbc #$50                        ; $E0B9 carry is set: the count in the first page starts at $50

;; Counts keywords down the page until A reaches 0.
LISTTOKEN_1:
    pha                             ; $E0BB
    lda (ACC),y                     ; $E0BC
@Loop2:
    tax                             ; $E0BE X = the byte above the one read next
    dey                             ; $E0BF
    lda (ACC),y                     ; $E0C0
    bpl @Loop2                      ; $E0C2 skip bytes that are not characters
    cpx #$C0                        ; $E0C4
    bcs LISTTOKEN_2                 ; $E0C6 a character below a keyword's last character starts a keyword
    cpx #$00                        ; $E0C8
    bmi @Loop2                      ; $E0CA a character below another character: not a start

;; Found the start of the token's keyword: Y indexes its first character, X holds it.
LISTTOKEN_2:
    tax                             ; $E0CC
    pla                             ; $E0CD
    sbc #$01                        ; $E0CE
    bne LISTTOKEN_1                 ; $E0D0 not this keyword yet
    bit P2                          ; $E0D2
    bmi @Loop                       ; $E0D4 a blank or a name came last: no blank before the keyword
    jsr KEYBLANK                    ; $E0D6 a blank before a keyword starting with a letter
@Loop:
    ; Print the keyword's characters, down the page, through the one with bit 6 set.
    lda (ACC),y                     ; $E0D9
    bpl LISTTOKEN_3                 ; $E0DB a byte that is not a character ends the keyword
    tax                             ; $E0DD
    and #$3F                        ; $E0DE P2 = the character, bit 7 clear: not a blank or a name
    sta P2                          ; $E0E0
    clc                             ; $E0E2
    adc #BLANK+$80                  ; $E0E3 the table holds each character less $A0
    jsr COUT                        ; $E0E5
    dey                             ; $E0E8
    cpx #$C0                        ; $E0E9 bit 6 clear: more characters
    bcc @Loop                       ; $E0EB

;; After the keyword: a blank if it ends with a letter, then the text that follows REM or an opening quote.
LISTTOKEN_3:
    jsr BLANKIFLET                  ; $E0ED
    pla                             ; $E0F0
    cmp #$5D                        ; $E0F1 REM: copy the remark
    beq LISTTEXTNXT                 ; $E0F3
    cmp #$28                        ; $E0F5 the opening quote: copy the string
    bne UNPACK_2                    ; $E0F7 anything else: the next token
    beq LISTTEXTNXT                 ; $E0F9 always
