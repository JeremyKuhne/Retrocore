; retrocore: style=strict
;; Integer BASIC: the tokenizer
;;
;; Matches a typed line against the syntax table (SyntaxTable.asm) and writes its tokens into <InputBuffer> after the
;; line's text. Integer BASIC checks a line's syntax completely here, as it is typed, so a stored program never holds a
;; syntax error; the token of each keyword records which rule it matched, so the interpreter knows its meaning.
;;
;; Part of IntegerBasic.asm.

;; The tokenizer: a backtracking pattern matcher over the syntax table, whose pieces jump to each other as it goes.
;;
;; A rule is a list of alternatives, each a list of items, read downward through the table. Y holds the place in the
;; page that <SyntaxPage> points to, <TextIndex> the last character of the line matched, <TokenIndex> the last token
;; written. When an item calls another rule, the tokenizer pushes a frame on the syntax stack (<SyntaxStackLow>,
;; <SyntaxStackHigh>) with the place to return to, and <TextIndex> and <TokenIndex> as they were (<TextIndexStack>,
;; <TokenIndexStack>), so a rule that fails can put them back and let the caller try another alternative. The items
;; are:
;;
;; - $80-$FF, a character: the line's next character, after skipping blanks, must be this one. The low 6 bits are the
;;   character less $A0 ($A0-$DF can be matched). Two values are classes instead: $x0 matches any letter and $x1 any
;;   digit, and copy the character into the tokens. Consecutive characters form a keyword; when a keyword is matched,
;;   its token is written (<Tokenizer::GotKeyword>).
;; - $00: a SYNTAX error. It ends the lists where nothing else could be right.
;; - $01: copies one character of a string, unless it is a double quote or the end of the line; the item after it
;;   repeats it. $02 does the same up to the end of the line, for REM.
;; - $03: the line is matched: the tokenizer returns.
;; - $04-$7D: calls rule n, the low 5 bits, through <RuleStarts>. Rule 0 is a numeric constant, whose digits are turned
;;   into a 16-bit value when it returns (<Tokenizer::RuleMatched>).
;; - $7F repeats the item before it, and $7E the two items before it, as long as they match: lists such as PRINT's.
;;
;; Bit 6 marks an alternative's last item: once it matches, the rule has matched. When an item fails, the tokenizer
;; looks at the item before it: a call with bits 7-5 = 001 ($20-$3F) means the rest is optional, and the rule has
;; matched without it. Otherwise it restores <TextIndex> and <TokenIndex> and skips down past the alternative's last
;; item to try the next alternative. A character or a call with bit 5 set says another alternative follows; after a
;; call without it ($40-$5F) none does, and the rule fails, which fails the item in the rule that called it.
.scope Tokenizer

;; The bits 7-5 of an item, which tell an optional call ($20-$3F, <Syntax::ITEM_CALL_THEN_OPTIONAL>) from the other
;; items.
CALL_KIND = $E0

;; The bits of a call that hold the rule's number.
RULE_NUMBER = $1F

;; Matches a character item: compares the table's character with the line's next one.
;;
;; A holds the item's low 6 bits shifted right, and the carry their lowest bit; ROL puts them back together.
;; In: A = the item's low 6 bits shifted right, carry = their lowest bit, X = the index in <InputBuffer> of the line's
;;   next character, after blanks, Y = the item
;; Also: MATCHCHAR (UNKN)
.proc MatchCharacter
    rol a
    adc #SYNTAX_CHARACTER_BASE
    cmp InputBuffer,x
    bne ItemFailed
    lda (SyntaxPage),y
    asl a                           ; bit 6 set: the keyword's last character
    bmi GotKeyword
    dey
    lda (SyntaxPage),y
    bmi CharacterItem::NextKeyCharacter ; another character: more of the keyword
    iny                             ; not a character: the keyword ended with the one before
    ; Falls into GotKeyword.
.endproc

;; A keyword matched: works out its token and hands it to <WriteKeywordToken>.
;;
;; The token is the number of keywords from this one to the top of the page, plus the page's first byte: $50 for the
;; page at $EC00, 0 for the page at $ED00. A walks up the page with the next byte's bits: after LSR and EOR, bit 6 is
;; set when the byte below has bit 7 clear, so ORA gives $C0 or more for a keyword's last character: one with bit 6
;; set, or with a byte below it that is not a character. The lister (<Lister::PrintLine>) counts first characters,
;; down from the top.
;; In: X = the index of the keyword's last character in <InputBuffer>, Y = the item, its last character
;; Also: GOTKEYWORD (UNKN)
.proc GotKeyword
    stx TextIndex
    tya
    pha
    ldx #0
    lda (SyntaxPage,x)              ; the page's first byte: $50 or 0
    tax

    ; Count the keywords' last characters up to the top of the page.
CountKeyword:
    lsr a
    eor #Syntax::ITEM_LAST
    ora (SyntaxPage),y
    cmp #SYNTAX_LAST_CHARACTER
    bcc NextPlace
    inx
NextPlace:
    iny
    bne CountKeyword
    pla
    tay
    txa
    jmp WriteKeywordToken
.endproc

;; Writes A as the next token in <InputBuffer>, after the line's text.
;; In: A = the token
;; Out: X = TokenIndex = the token's index in <InputBuffer>
;; Errors: TOO LONG if the tokens would run past the end of the buffer
;; Keeps: A, Y
;; Entry:
;;   Done = returns; <Tokenizer::RuleItem> returns from the tokenizer here
;; Also: PUTTOKEN (UNKN)
.proc PutToken
    inc TokenIndex
    ldx TokenIndex
    beq TooLongError
    sta InputBuffer,x
Done:
    rts
.endproc

;; Matches a character item ($80-$FF) against the next character in the line, skipping blanks.
;;
;; Every character at or below $A0 (a blank or a control character) is skipped.
;; In: Y = the item
;; Entry:
;;   NextKeyCharacter = continues a keyword, with X already at the last character matched
;; Also: CHARITEM (UNKN)
.proc CharacterItem
    ldx TextIndex

;; Continues a keyword, with X already at the last character matched.
;; In: X = the index of the last character matched, Y = the item
;; Also: NEXTKEYCHAR (UNKN)
NextKeyCharacter:
    lda #BLANK | $80
SkipBlank:
    inx
    cmp InputBuffer,x
    bcs SkipBlank

    ; A character, or a class: $x0 a letter, $x1 a digit.
    lda (SyntaxPage),y
    and #SYNTAX_CHARACTER_BITS
    lsr a
    bne MatchCharacter              ; a character, not a class
    lda InputBuffer,x
    bcs IsDigit                     ; $x1: a digit
    adc #$100 - 'A'                 ; $x0: is it a letter? (carry is clear)
    cmp #'Z' - 'A' + 1
    bcc CopyCharacter

;; Tests for a digit: for $x1 the carry is set and A holds the character, so adding $4F leaves 0-9 for $B0-$B9.
;;
;; After a failed letter test, A holds the character plus $3F and carry is set, and the sum is never below 10 for a
;; character with bit 7 set.
IsDigit:
    adc #$100 - '0' - 1
    cmp #10
    bcc CopyCharacter
    ; Falls into ItemFailed.
.endproc

;; The item at Y failed: lets the rule match without the rest if the item before it was optional, or tries the rule's
;; next alternative, or fails the rule and passes the failure to its caller.
;; In: Y = the item that failed
;; Also: ITEMFAILED (UNKN)
.proc ItemFailed
    ldx SyntaxStackIndex

    ; The item before it: a call with bits 7-5 = 001 makes the rest of the rule optional.
TryOptional:
    iny
    lda (SyntaxPage),y
    and #CALL_KIND
    cmp #Syntax::ITEM_CALL_THEN_OPTIONAL
    beq RuleMatched

    ; Back to where the rule started.
    lda TextIndexStack,x
    sta TextIndex
    lda TokenIndexStack,x
    sta TokenIndex

    ; Skip to the alternative's last item (bit 6 set).
SkipAlternative:
    dey
    lda (SyntaxPage),y
    asl a
    bpl SkipAlternative
    dey                             ; Y = the next alternative's first item
    bcs MatchItem                   ; the last item was a character: another alternative follows
    asl a
    bmi MatchItem                   ; a call with bit 5 set: another alternative follows

    ; None: return to the caller and fail its item.
    ldy SyntaxStackHigh,x
    sty SyntaxPage+1
    ldy SyntaxStackLow,x
    inx
    bpl TryOptional                 ; always: the stack index stays below $80
.endproc

;; An item $03-$7F: $03 ends the line, $7E and $7F repeat an item, and the rest call a rule.
;;
;; The flags are those of comparing the item with 3.
;; In: A = the item, Y = its place, X = the frame of the rule being matched
;; Errors: TOO LONG when the syntax stack is full
;; Also: RULEITEM (UNKN)
.proc RuleItem
    beq PutToken::Done              ; $03: the line is matched
    cmp #Syntax::ITEM_REPEAT_TWO
    bcs RepeatItem
    dex                             ; a new frame
    bpl CallRule
    ldy #<Messages::TooLong                  ; the syntax stack is full: the TOO LONG error
    bpl MatchItem::ToReportError    ; always
.endproc

;; Calls rule n: pushes a frame with the place to come back to and where the line and the tokens stand, then starts the
;; rule.
;; In: A = the item, X = the new frame, Y = the item's place
;; Also: CALLRULE (UNKN)
.proc CallRule
    sty SyntaxStackLow,x
    ldy SyntaxPage+1
    sty SyntaxStackHigh,x
    ldy TextIndex
    sty TextIndexStack,x
    ldy TokenIndex
    sty TokenIndexStack,x
    and #RULE_NUMBER
    tay
    lda RuleStarts,y
    ; Falls into StartRule.
.endproc

;; Tokenizes from a rule of the syntax table: A, doubled, is its place, and its top bit the page.
;;
;; The page's high byte is $EC or $ED: half of $EC, shifted back left with the bit from A, so a rule can start at an odd
;; address only, the one after 2 x A. The command loop starts with A = $FF (the line's top rule, at $EDFF) and INPUT of
;; numbers with A = $15 (at $EC2B); <Tokenizer::CallRule> comes here for each rule a rule calls. Called from outside,
;; it returns when the line is matched, and reports any error itself.
;; In: A = the rule's place halved, with the page in bit 7, X = <SYNTAX_STACK_EMPTY> or the new frame,
;;   TextIndex = the index in <InputBuffer> before the text, TokenIndex = the index before the first token
;; Out: TextIndex = the last character matched, TokenIndex = the last token written, carry = set
;; Errors: SYNTAX, TOO LONG, >32767 for a constant above 32767
;; See: <RuleStarts>, <WarmStart>, <Statements::InputNumber>
;; Also: STARTRULE (UNKN)
.proc StartRule
    asl a
    tay
    lda #(>Syntax::Table) >> 1
    rol a
    sta SyntaxPage+1
    ; Falls into RepeatItem, whose BNE the page's nonzero high byte takes.
.endproc

;; Moves Y up to repeat an item: $7F goes up one, to the item before, $7E up two.
;;
;; The flags are those of comparing the item with $7E.
;; In: Y = the item's place
;; Also: REPEATITEM (UNKN)
.proc RepeatItem
    bne UpOne
    iny
UpOne:
    iny
    ; Falls into MatchItem.
.endproc

;; Matches the item at Y.
;; In: X = the frame of the rule being matched, Y = the item
;; Entry:
;;   ToReportError = reports the error whose message's offset is in Y
;; Also: MATCHITEM (UNKN)
.proc MatchItem
    stx SyntaxStackIndex
    lda (SyntaxPage),y
    bmi CharacterItem
    bne NotError
    ldy #<Messages::SyntaxError                  ; $00: the SYNTAX error

;; Reports the error whose message's offset is in Y, for the branches nearby.
;; In: Y = the message's offset from <Messages::GreaterThan32767>
;; Also: TOKERROR (UNKN)
ToReportError:
    jmp ReportError

    ; An item from $01 to $7F: $01 and $02 copy text; the rest go to RuleItem.
NotError:
    cmp #Syntax::ITEM_LINE_MATCHED
    bcs RuleItem
    lsr a                           ; carry set for $01: stop at a quote too
    ldx TextIndex
    inx
    ; Falls into CopyCharacter.
.endproc

;; Copies the character at X into the tokens, unless it ends the text: a quote ends a string, the underline ends the
;; line.
;;
;; Letters and digits matched by a class item come here too, with the carry clear. A character that ends the text
;; goes on to <Tokenizer::NextItem> with Y at the copying item, so the repeat after it counts as matched.
;; In: X = the character's index in <InputBuffer>, Y = the item, carry = set to stop at a quote
;; Also: COPYCHAR (UNKN)
.proc CopyCharacter
    lda InputBuffer,x
    bcc NotQuote
    cmp #DOUBLE_QUOTE | $80
    beq NextItem
NotQuote:
    cmp #LINE_END_MARK
    beq NextItem
    stx TextIndex                   ; matched: it is consumed
    ; Falls into PutTokenAndNext.
.endproc

;; Writes A as a token, then goes on after the item at Y.
;; In: A = the token, Y = the item just matched
;; Also: PUTTOKNEXT (UNKN)
.proc PutTokenAndNext
    jsr PutToken
    iny
    ; Falls into NextItem.
.endproc

;; Goes on after the item below Y without writing anything: to the next item, or back to the caller if that one was
;; the alternative's last item (bit 6 set).
;; In: Y = one above the item just matched
;; Entry:
;;   WithFrame = with X already the frame and Y the item just matched
;; Also: NEXTITEM (UNKN)
.proc NextItem
    dey
    ldx SyntaxStackIndex

;; Goes on after the item at Y, with X already the frame.
;; In: X = the frame, Y = the item just matched
;; Also: NEXTITEMX (UNKN)
WithFrame:
    lda (SyntaxPage),y
    dey
    asl a
    bpl MatchItem
    ; Falls into RuleMatched.
.endproc

;; The rule has matched: returns to the item that called it, then goes on after that item.
;;
;; When the item called rule 0, a numeric constant, the digits it copied into the tokens are turned into a value: the
;; first digit stays, as the constant's marker, and the value's low and high bytes replace the rest.
;; In: X = the frame of the rule that matched
;; Errors: >32767 if the value does not fit in 15 bits
;; Also: RULEMATCHED (UNKN)
.proc RuleMatched
;; The bits of a digit's character that hold its value.
DIGIT_VALUE = $0F

    ; Back to the calling item.
    ldy SyntaxStackHigh,x
    sty SyntaxPage+1
    ldy SyntaxStackLow,x
    inx
    lda (SyntaxPage),y
    and #$80 | RULE_NUMBER          ; a call to rule 0: $00, $20, $40 or $60
    bne NextItem::WithFrame

    ; A constant: DecimalNumber = its value, from the digits after the tokens as they were before them.
    sta DecimalNumber
    sta DecimalNumber+1
    tya
    pha
    stx SyntaxStackIndex
    ldy TokenIndexStack-1,x
    sty DigitPlace
    clc

    ; Multiply by 10 by adding the value ten times to the next digit.
NextDigit:
    lda #10
    sta DigitCharacter
    ldx #0
    iny
    lda InputBuffer,y
    and #DIGIT_VALUE
AddValue:
    adc DecimalNumber
    pha
    txa
    adc DecimalNumber+1
    bmi TooBig                      ; past 32767
    tax
    pla
    dec DigitCharacter
    bne AddValue
    sta DecimalNumber
    stx DecimalNumber+1
    cpy TokenIndex                  ; up to the last digit
    bne NextDigit

    ; The low byte goes after the first digit, then the high byte.
    ldy DigitPlace
    iny
    sty TokenIndex
    jsr PutToken
    pla
    tay
    lda DecimalNumber+1
    bcs PutTokenAndNext             ; always: the CPY above set carry

;; The >32767 error.
TooBig:
    ldy #<Messages::GreaterThan32767
    bpl MatchItem::ToReportError    ; always
.endproc

.endscope
