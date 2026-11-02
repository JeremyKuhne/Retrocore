;; INTEGER BASIC: THE TOKENIZER ($E3ED-$E51A)
;;
;; Matches a typed line against the syntax table (SyntaxTable.asm) and writes its tokens into IN after the line's
;; text. Integer BASIC checks a line's syntax completely here, as it is typed, so a stored program never holds a
;; syntax error; the token of each keyword records which rule it matched, so the interpreter knows its meaning.
;;
;; The tokenizer is a backtracking pattern matcher. A rule is a list of alternatives, each a list of items, read
;; downward through the table. Y holds the place in the page that SYNPAG points to, TXTNDX the last character of
;; the line matched, TOKNDX the last token written. When an item calls another rule, the tokenizer pushes a frame
;; on the syntax stack (SYNSTKL, SYNSTKH) with the place to return to and TXTNDX and TOKNDX as they were, so a rule
;; that fails can put them back and let the caller try another alternative. The items are:
;;
;; - $80-$FF, a character: the line's next character, after skipping blanks, must be this one. The low 6 bits are
;;   the character less $A0 ($A0-$DF can be matched). Two values are classes instead: $x0 matches any letter and $x1
;;   any digit, and copy the character into the tokens. Consecutive characters form a keyword; when a keyword is
;;   matched, its token is written (<GOTKEYWORD>).
;; - $00: a SYNTAX error. It ends the lists where nothing else could be right.
;; - $01: copies one character of a string, unless it is a double quote or the end of the line; the item after it
;;   repeats it. $02 does the same up to the end of the line, for REM.
;; - $03: the line is matched: the tokenizer returns.
;; - $04-$7D: calls rule n, the low 5 bits, through SYNTABLNDX. Rule 0 is a numeric constant, whose digits are
;;   turned into a 16-bit value when it returns (<RULEMATCHED>).
;; - $7F repeats the item before it, and $7E the two items before it, as long as they match: lists such as PRINT's.
;;
;; Bit 6 marks an alternative's last item: once it matches, the rule has matched. When an item fails, the tokenizer
;; looks at the item before it: a call with bits 7-5 = 001 ($20-$3F) means the rest is optional, and the rule has
;; matched without it. Otherwise it restores TXTNDX and TOKNDX and skips down past the alternative's last item to
;; try the next alternative. A character or a call with bit 5 set says another alternative follows; after a call
;; without it ($40-$5F) none does, and the rule fails, which fails the item in the rule that called it.
;;
;; Part of IntegerBasic.asm; it follows LineEditor.asm, at $E3ED.

;; Matches a character item: compares the table's character with the line's next one.
;;
;; A holds the item's low 6 bits shifted right, and the carry their lowest bit; ROL puts them back together.
;; In: X = the index in IN of the line's next character, after blanks, Y = the item
;; Errors: fails the item (<ITEMFAILED>) if the characters differ
MATCHCHAR:
    rol a                           ; $E3ED
    adc #$A0                        ; $E3EE the table holds the character less $A0
    cmp IN,x                        ; $E3F0
    bne ITEMFAILED                  ; $E3F3
    lda (SYNPAG),y                  ; $E3F5
    asl a                           ; $E3F7 bit 6 set: the keyword's last character
    bmi GOTKEYWORD                  ; $E3F8
    dey                             ; $E3FA
    lda (SYNPAG),y                  ; $E3FB
    bmi NEXTKEYCHAR                 ; $E3FD another character: more of the keyword
    iny                             ; $E3FF not a character: the keyword ended with the one before

;; A keyword matched: works out its token and writes it.
;;
;; The token is the number of keywords from this one to the top of the page, plus the page's first byte: $50 for
;; the page at $EC00, 0 for the page at $ED00. A walks up the page with the next byte's bits: after LSR and EOR,
;; bit 6 is set when the byte below has bit 7 clear, so ORA gives $C0 or more for a keyword's last character: one
;; with bit 6 set, or with a byte below it that is not a character. The lister (<LISTTOKEN>) counts first characters,
;; down from the top.
;; In: X = the index of the keyword's last character in IN, Y = the item
GOTKEYWORD:
    stx TXTNDX                      ; $E400
    tya                             ; $E402
    pha                             ; $E403
    ldx #$00                        ; $E404
    lda (SYNPAG,x)                  ; $E406 the page's first byte: $50 or 0
    tax                             ; $E408

GOTKEYWORD_1:
    lsr a                           ; $E409
    eor #$40                        ; $E40A
    ora (SYNPAG),y                  ; $E40C
    cmp #$C0                        ; $E40E
    bcc GOTKEYWORD_2                ; $E410
    inx                             ; $E412

GOTKEYWORD_2:
    iny                             ; $E413
    bne GOTKEYWORD_1                ; $E414 to the top of the page
    pla                             ; $E416
    tay                             ; $E417
    txa                             ; $E418
    jmp KEYMATCHED                  ; $E419

;; Writes A as the next token in <IN>, after the line's text.
;; In: A = the token
;; Out: X = the token's index in <IN>
;; Errors: TOO LONG if the tokens would run past the end of the buffer
;; Keeps: A, Y
PUTTOKEN:
    inc TOKNDX                      ; $E41C
    ldx TOKNDX                      ; $E41E
    beq ErrTooLong                  ; $E420
    sta IN,x                        ; $E422

PUTTOKEN_1:
    rts                             ; $E425

;; Matches a character item ($80-$FF) against the next character in the line, skipping blanks.
;;
;; Every character at or below $A0 (a blank or a control character) is skipped.
;; In: Y = the item
;; Entry: NEXTKEYCHAR = continues a keyword, with X already at the last character matched
CHARITEM:
    ldx TXTNDX                      ; $E426

NEXTKEYCHAR:
    lda #BLANK+$80                  ; $E428

CHARITEM_1:
    inx                             ; $E42A
    cmp IN,x                        ; $E42B
    bcs CHARITEM_1                  ; $E42E
    lda (SYNPAG),y                  ; $E430
    and #$3F                        ; $E432
    lsr a                           ; $E434
    bne MATCHCHAR                   ; $E435 a character, not a class
    lda IN,x                        ; $E437
    bcs CHARITEM_2                  ; $E43A $x1: a digit
    adc #$3F                        ; $E43C $x0: is it a letter? (carry is clear)
    cmp #$1A                        ; $E43E
    bcc COPYCHAR                    ; $E440

;; Tests for a digit: for $x1 the carry is set and A holds the character, so adding $4F leaves 0-9 for $B0-$B9.
;;
;; After a failed letter test, A holds the character plus $3F, and the sum is never below 10.
CHARITEM_2:
    adc #$4F                        ; $E442
    cmp #$0A                        ; $E444
    bcc COPYCHAR                    ; $E446

;; The item at Y failed: lets the rule match without the rest if the item before it was optional, or tries the
;; rule's next alternative, or fails the rule and passes the failure to its caller.
;; In: Y = the item that failed
ITEMFAILED:
    ldx SYNSTKDX                    ; $E448
@Loop1:
    iny                             ; $E44A
    lda (SYNPAG),y                  ; $E44B
    and #$E0                        ; $E44D
    cmp #$20                        ; $E44F a call with bits 7-5 = 001: the rest of the rule is optional
    beq RULEMATCHED                 ; $E451
    lda TXTNDXSTK,x                 ; $E453 back to where the rule started
    sta TXTNDX                      ; $E455
    lda TOKNDXSTK,x                 ; $E457
    sta TOKNDX                      ; $E459
@Loop2:
    dey                             ; $E45B
    lda (SYNPAG),y                  ; $E45C
    asl a                           ; $E45E
    bpl @Loop2                      ; $E45F skip to the alternative's last item (bit 6 set)
    dey                             ; $E461 Y = the next alternative's first item
    bcs MATCHITEM                   ; $E462 the last item was a character: another alternative follows
    asl a                           ; $E464
    bmi MATCHITEM                   ; $E465 a call with bit 5 set: another alternative follows
    ldy SYNSTKH,x                   ; $E467 none: return to the caller and fail its item
    sty SYNPAG+1                    ; $E469
    ldy SYNSTKL,x                   ; $E46B
    inx                             ; $E46D
    bpl @Loop1                      ; $E46E always: the stack index stays below $80

;; An item $03-$7F: $03 ends the line, $7E and $7F repeat an item, and the rest call a rule.
;;
;; The flags are those of comparing the item with 3.
RULEITEM:
    beq PUTTOKEN_1                  ; $E470 $03: the line is matched
    cmp #$7E                        ; $E472
    bcs REPEATITEM                  ; $E474
    dex                             ; $E476 a new frame
    bpl CALLRULE                    ; $E477
    ldy #<ErrMsg01                  ; $E479 the syntax stack is full: the TOO LONG error
    bpl TOKERROR                    ; $E47B always

;; Calls rule n: pushes a frame with the place to come back to and where the line and the tokens stand, then starts
;; the rule.
;; In: A = the item, X = the new frame
CALLRULE:
    sty SYNSTKL,x                   ; $E47D
    ldy SYNPAG+1                    ; $E47F
    sty SYNSTKH,x                   ; $E481
    ldy TXTNDX                      ; $E483
    sty TXTNDXSTK,x                 ; $E485
    ldy TOKNDX                      ; $E487
    sty TOKNDXSTK,x                 ; $E489
    and #$1F                        ; $E48B the rule's number
    tay                             ; $E48D
    lda SYNTABLNDX,y                ; $E48E

;; Starts matching at a byte of the syntax table: A, doubled, is the place, and its top bit the page.
;;
;; The page's high byte is $EC or $ED: half of $EC, shifted back left with the bit from A, so a rule can start at an
;; odd address only, the one after 2 x A. The command loop starts with A = $FF (the line's top rule, at $EDFF) and
;; INPUT of numbers with A = $15 (at $EC2B).
;; In: A = the rule's place halved, with the page in bit 7, X = the syntax stack index ($20 for a new line)
;; See: <SYNTABLNDX>, <WARM>, <COMMA_INPUT>
STARTRULE:
    asl a                           ; $E491
    tay                             ; $E492
    lda #(>SYNTABL) >> 1            ; $E493
    rol a                           ; $E495
    sta SYNPAG+1                    ; $E496

;; Moves Y up to repeat an item: $7F goes up one, to the item before, $7E up two.
REPEATITEM:
    bne REPEATITEM_1                ; $E498
    iny                             ; $E49A the high byte is never 0: one INY

REPEATITEM_1:
    iny                             ; $E49B

;; Matches the item at Y.
;; In: X = the frame of the rule being matched, Y = the item
MATCHITEM:
    stx SYNSTKDX                    ; $E49C
    lda (SYNPAG),y                  ; $E49E
    bmi CHARITEM                    ; $E4A0 a character
    bne MATCHITEM_1                 ; $E4A2 not 0
    ldy #<ErrMsg02                  ; $E4A4 $00: the SYNTAX error

TOKERROR:
    jmp ERRMESS                     ; $E4A6

;; An item from $01 to $7F: $01 and $02 copy text; the rest go to <RULEITEM>.
MATCHITEM_1:
    cmp #$03                        ; $E4A9
    bcs RULEITEM                    ; $E4AB
    lsr a                           ; $E4AD carry set for $01: stop at a quote too
    ldx TXTNDX                      ; $E4AE
    inx                             ; $E4B0

;; Copies the character at X into the tokens, unless it ends the text: a quote ends a string, the underline ends
;; the line.
;;
;; Letters and digits matched by a class item come here too, with the carry clear.
COPYCHAR:
    lda IN,x                        ; $E4B1
    bcc COPYCHAR_1                  ; $E4B4
    cmp #DQT+$80                    ; $E4B6
    beq NEXTITEM                    ; $E4B8

COPYCHAR_1:
    cmp #'_'                        ; $E4BA
    beq NEXTITEM                    ; $E4BC
    stx TXTNDX                      ; $E4BE matched: it is consumed

;; Writes A as a token, then goes on after the item at Y.
PUTTOKNEXT:
    jsr PUTTOKEN                    ; $E4C0
    iny                             ; $E4C3

;; Goes on after the item at Y without writing anything: to the next item, or back to the caller if this was the
;; alternative's last item (bit 6 set).
;; Entry: NEXTITEMX = with X already the frame
NEXTITEM:
    dey                             ; $E4C4
    ldx SYNSTKDX                    ; $E4C5

NEXTITEMX:
    lda (SYNPAG),y                  ; $E4C7
    dey                             ; $E4C9
    asl a                           ; $E4CA
    bpl MATCHITEM                   ; $E4CB

;; The rule has matched: returns to the item that called it, then goes on after that item.
;;
;; When the item called rule 0, a numeric constant, the digits it copied into the tokens are turned into a value:
;; the first digit stays, as the constant's marker, and the value's low and high bytes replace the rest.
;; Errors: >32767 if the value does not fit in 15 bits
RULEMATCHED:
    ldy SYNSTKH,x                   ; $E4CD
    sty SYNPAG+1                    ; $E4CF
    ldy SYNSTKL,x                   ; $E4D1
    inx                             ; $E4D3
    lda (SYNPAG),y                  ; $E4D4
    and #%10011111                  ; $E4D6 a call to rule 0: $00, $20, $40 or $60
    bne NEXTITEMX                   ; $E4D8
    sta PCON                        ; $E4DA
    sta PCON+1                      ; $E4DC
    tya                             ; $E4DE
    pha                             ; $E4DF
    stx SYNSTKDX                    ; $E4E0
    ldy TOKNDXSTK-1,x               ; $E4E2 the tokens as they were before the digits
    sty LEADBL                      ; $E4E4
    clc                             ; $E4E6
@Loop1:
    lda #$0A                        ; $E4E7 multiply by 10 by adding the value ten times to the digit
    sta CHAR                        ; $E4E9
    ldx #$00                        ; $E4EB
    iny                             ; $E4ED
    lda IN,y                        ; $E4EE
    and #$0F                        ; $E4F1
@Loop2:
    adc PCON                        ; $E4F3
    pha                             ; $E4F5
    txa                             ; $E4F6
    adc PCON+1                      ; $E4F7
    bmi RULEMATCHED_1               ; $E4F9 past 32767
    tax                             ; $E4FB
    pla                             ; $E4FC
    dec CHAR                        ; $E4FD
    bne @Loop2                      ; $E4FF
    sta PCON                        ; $E501
    stx PCON+1                      ; $E503
    cpy TOKNDX                      ; $E505 up to the last digit
    bne @Loop1                      ; $E507
    ldy LEADBL                      ; $E509
    iny                             ; $E50B
    sty TOKNDX                      ; $E50C the low byte goes after the first digit
    jsr PUTTOKEN                    ; $E50E
    pla                             ; $E511
    tay                             ; $E512
    lda PCON+1                      ; $E513 then the high byte (carry is set)
    bcs PUTTOKNEXT                  ; $E515

;; The >32767 error.
RULEMATCHED_1:
    ldy #<ErrMsg00                  ; $E517
    bpl TOKERROR                    ; $E519
